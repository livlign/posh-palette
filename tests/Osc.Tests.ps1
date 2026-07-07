#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# SPIKE tests for the OSC scheme applier (issue #12). These assert the escape
# bytes are correct without needing a real terminal - the visual effect can only
# be confirmed on real hardware, but byte-correctness and terminal detection are
# fully checkable on CI.

BeforeAll {
    Import-Module "$PSScriptRoot/../PoshPalette.psd1" -Force
    $script:ESC = [char]27
}

Describe 'ConvertTo-PoshPaletteOscColor' {
    It 'converts #RRGGBB to the portable lowercase rgb: form' {
        InModuleScope PoshPalette { ConvertTo-PoshPaletteOscColor '#0E1116' } | Should -Be 'rgb:0e/11/16'
    }
    It 'accepts hex without the leading #' {
        InModuleScope PoshPalette { ConvertTo-PoshPaletteOscColor 'FF6366' } | Should -Be 'rgb:ff/63/66'
    }
    It 'rejects a non-hex / wrong-length value' {
        { InModuleScope PoshPalette { ConvertTo-PoshPaletteOscColor '#12345' } } | Should -Throw
        { InModuleScope PoshPalette { ConvertTo-PoshPaletteOscColor 'nope' } }    | Should -Throw
    }
}

Describe 'New-PoshPaletteOscSequence' {
    BeforeAll {
        $colors = [pscustomobject]@{
            background = '#0E1116'; foreground = '#DCE3ED'; cursorColor = '#F6C45F'
            selectionBackground = '#25324A'
            black = '#0A0D12'; red = '#FF6366'; green = '#85DF5E'; yellow = '#F1C655'
            blue = '#5FB9FF'; purple = '#CEA5FF'; cyan = '#3ADDC4'; white = '#B7C0CE'
            brightBlack = '#5C6675'; brightRed = '#FF8688'; brightGreen = '#A0EC7E'; brightYellow = '#FAD77C'
            brightBlue = '#84CCFF'; brightPurple = '#DDBFFF'; brightCyan = '#68EAD3'; brightWhite = '#F4F8FD'
        }
        $script:seq = New-PoshPaletteOscSequence -SchemeColors $colors
    }

    It 'chains all 16 palette entries in one ESC ] 4 sequence, index 0 first' {
        $seq | Should -Match ([regex]::Escape("$ESC]4;0;rgb:0a/0d/12;1;rgb:ff/63/66;"))
        $seq | Should -Match '15;rgb:f4/f8/fd'   # brightWhite at index 15
    }
    It 'emits OSC 10/11/12 for fg/bg/cursor' {
        $seq | Should -Match ([regex]::Escape("$ESC]10;rgb:dc/e3/ed$ESC\"))   # foreground
        $seq | Should -Match ([regex]::Escape("$ESC]11;rgb:0e/11/16$ESC\"))   # background
        $seq | Should -Match ([regex]::Escape("$ESC]12;rgb:f6/c4/5f$ESC\"))   # cursor
    }
    It 'emits OSC 17 for the selection background' {
        $seq | Should -Match ([regex]::Escape("$ESC]17;rgb:25/32/4a$ESC\"))
    }
    It 'terminates every sequence with ST (ESC backslash)' {
        # No bare BEL used; count of ST terminators == count of OSC openers.
        $openers = ([regex]::Matches($seq, [regex]::Escape("$ESC]"))).Count
        $closers = ([regex]::Matches($seq, [regex]::Escape("$ESC\"))).Count
        $closers | Should -Be $openers
    }
    It 'skips a color the scheme omits' {
        $partial = [pscustomobject]@{ background = '#101010' }   # no palette, no fg
        $s = New-PoshPaletteOscSequence -SchemeColors $partial
        $s | Should -Match ([regex]::Escape("$ESC]11;rgb:10/10/10"))
        $s | Should -Not -Match ([regex]::Escape("$ESC]4;"))
        $s | Should -Not -Match ([regex]::Escape("$ESC]10;"))
    }

    It 'renders non-empty bytes for every bundled scheme without throwing' {
        InModuleScope PoshPalette {
            foreach ($item in (Get-PoshPaletteCatalog -Kind 'schemes')) {
                $s = New-PoshPaletteOscSequence -SchemeColors $item.Data.colors
                $s | Should -Not -BeNullOrEmpty -Because "scheme '$($item.Id)' should render bytes"
            }
        }
    }
}

Describe 'Test-PoshPaletteOscTerminal' {
    It 'says yes for Windows Terminal' {
        InModuleScope PoshPalette {
            $env:WT_SESSION = 'x'; $env:TMUX = ''; $env:STY = ''
            Test-PoshPaletteOscTerminal | Should -BeTrue
        }
    }
    It 'says yes for a known TERM_PROGRAM (Apple_Terminal, verified)' {
        InModuleScope PoshPalette {
            $env:WT_SESSION = ''; $env:TMUX = ''; $env:STY = ''; $env:KITTY_WINDOW_ID = ''
            $env:TERM_PROGRAM = 'Apple_Terminal'
            Test-PoshPaletteOscTerminal | Should -BeTrue
        }
    }
    It 'says no inside a multiplexer (needs passthrough we do not emit yet)' {
        InModuleScope PoshPalette {
            $env:TMUX = '/tmp/tmux'; $env:WT_SESSION = 'x'
            Test-PoshPaletteOscTerminal | Should -BeFalse
        }
    }
}
