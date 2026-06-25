#requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

# Pester tests for the data/catalog layer. These cover the pure logic and the
# auto-refresh network/merge path (with GitHub mocked), which is exactly the part
# that can't be exercised on the author's macOS box. Run: Invoke-Pester ./tests

BeforeAll {
    Import-Module "$PSScriptRoot/../PoshPalette.psd1" -Force
}

Describe 'Bundled catalog' {
    It 'loads at least the 35 bundled themes' {
        (Get-PoshPaletteThemes).Count | Should -BeGreaterOrEqual 35
    }

    It 'orders the curated themes first (order 1 leads)' {
        (Get-PoshPaletteThemes)[0].Order | Should -Be 1
    }

    It 'every bundled theme resolves end to end' {
        foreach ($t in Get-PoshPaletteThemes) {
            $resolved = Import-PoshPaletteTheme -NameOrPath $t.Id
            $resolved.terminal.scheme.background | Should -Match '^#[0-9A-Fa-f]{6}$'
            $resolved.prompt | Should -Not -BeNullOrEmpty
        }
    }

    It 'exposes the generated prompt styles, including the new ones' {
        # Get-PoshPaletteCatalog is internal, so reach it inside the module scope.
        $ids = InModuleScope PoshPalette { (Get-PoshPaletteCatalog -Kind prompts).Id }
        $ids | Should -Contain 'auto-spaceship'
        $ids | Should -Contain 'auto-atomic'
        $ids | Should -Contain 'auto-smoothie'
        $ids | Should -Contain 'auto-1shell'
        $ids | Should -Contain 'auto-cert'
        $ids | Should -Contain 'auto-clean'
        $ids | Should -Contain 'auto-velvet'
        $ids | Should -Contain 'auto-avit'
        $ids | Should -Contain 'auto-darkblood'
        $ids | Should -Contain 'auto-tokyonight'
        $ids | Should -Contain 'auto-dracula'
    }
}

Describe 'Test-PoshPaletteDarkHex' {
    It 'classifies dark and light backgrounds by luminance' {
        InModuleScope PoshPalette {
            Test-PoshPaletteDarkHex '#000000' | Should -BeTrue
            Test-PoshPaletteDarkHex '#1A1B26' | Should -BeTrue   # Tokyo Night bg
            Test-PoshPaletteDarkHex '#FFFFFF' | Should -BeFalse
            Test-PoshPaletteDarkHex '#EFF1F5' | Should -BeFalse   # Catppuccin Latte bg
        }
    }
}

Describe 'New-PoshPaletteOmpConfig' {
    It 'generates a valid v4 config for every style' {
        InModuleScope PoshPalette {
            $colors = (Get-PoshPaletteCatalogItem -Kind schemes -Id 'tokyo-night').colors
            foreach ($style in 'powerline','twoline','robby','arrow','lambda','pure','spaceship','atomic','smoothie','1_shell','cert','clean-detailed','velvet','avit','darkblood','tokyonight','dracula') {
                $cfg = New-PoshPaletteOmpConfig $colors -Style $style
                $cfg.version | Should -Be 4
                @($cfg.blocks).Count | Should -BeGreaterThan 0
            }
        }
    }
}

Describe 'Update-PoshPaletteCatalog' {
    BeforeEach {
        # Route the cache to a throwaway dir and stub GitHub + the version check
        # so no test in this block touches the network.
        Mock -ModuleName PoshPalette Get-PoshPaletteCacheRoot { Join-Path $TestDrive 'catalog' }
        Mock -ModuleName PoshPalette Get-PoshPaletteLatestVersion { $null }
        Remove-Item Env:\POSHPALETTE_NO_AUTOUPDATE -ErrorAction SilentlyContinue
    }
    AfterEach {
        Remove-Item Env:\POSHPALETTE_NO_AUTOUPDATE -ErrorAction SilentlyContinue
    }

    It 'is a no-op (no network) when disabled by env var' {
        $env:POSHPALETTE_NO_AUTOUPDATE = '1'
        Mock -ModuleName PoshPalette Get-PoshPaletteRemoteCatalog { @() }
        Update-PoshPaletteCatalog | Should -Be 0
        Should -Invoke -ModuleName PoshPalette Get-PoshPaletteRemoteCatalog -Times 0
    }

    It 'skips the fetch when refreshed within the last 24h' {
        $cache = Join-Path $TestDrive 'catalog'
        New-Item -ItemType Directory -Path $cache -Force | Out-Null
        Set-Content -Path (Join-Path $cache '.last-refresh') -Value ((Get-Date).ToString('o'))
        Mock -ModuleName PoshPalette Get-PoshPaletteRemoteCatalog { @() }
        Update-PoshPaletteCatalog | Should -Be 0
        Should -Invoke -ModuleName PoshPalette Get-PoshPaletteRemoteCatalog -Times 0
    }

    It 'never throws and returns 0 when GitHub is unreachable' {
        Mock -ModuleName PoshPalette Get-PoshPaletteRemoteCatalog { throw 'network down' }
        { Update-PoshPaletteCatalog -Force } | Should -Not -Throw
        Update-PoshPaletteCatalog -Force | Should -Be 0
    }

    It 'pulls a new theme and the layers it references into the cache' {
        Mock -ModuleName PoshPalette Get-PoshPaletteRemoteCatalog {
            param($Kind)
            switch ($Kind) {
                'themes'   { ,@([pscustomobject]@{ Id = 'zz-test'; DownloadUrl = 'https://x/themes/zz-test.json' }) }
                'schemes'  { ,@([pscustomobject]@{ Id = 'zz-scheme'; DownloadUrl = 'https://x/schemes/zz-scheme.json' }) }
                'palettes' { ,@([pscustomobject]@{ Id = 'zz-pal'; DownloadUrl = 'https://x/palettes/zz-pal.json' }) }
                default    { ,@() }
            }
        }
        Mock -ModuleName PoshPalette Invoke-RestMethod {
            param($Uri)
            if ($Uri -match 'themes/zz-test')    { return [pscustomobject]@{ id='zz-test'; name='ZZ'; description='x'; scheme='zz-scheme'; palette='zz-pal'; prompt='auto-pure'; font='robotomono'; fontSize=11; opacity=100; acrylic=$false } }
            if ($Uri -match 'schemes/zz-scheme') { return [pscustomobject]@{ id='zz-scheme'; name='ZZ'; colors=[pscustomobject]@{ background='#101010'; foreground='#EEEEEE'; cursorColor='#EEEEEE' } } }
            if ($Uri -match 'palettes/zz-pal')   { return [pscustomobject]@{ id='zz-pal'; name='ZZ'; psReadLine=[pscustomobject]@{ Command='#88AAFF' }; psStyle=[pscustomobject]@{ Directory='#88AAFF' } } }
            return $null
        }

        $added = Update-PoshPaletteCatalog -Force
        $added | Should -Be 1

        $cache = Join-Path $TestDrive 'catalog'
        Test-Path (Join-Path $cache 'themes/zz-test.json')   | Should -BeTrue
        Test-Path (Join-Path $cache 'schemes/zz-scheme.json')| Should -BeTrue
        Test-Path (Join-Path $cache 'palettes/zz-pal.json')  | Should -BeTrue

        # auto-pure is bundled, so no prompt file should have been written
        Test-Path (Join-Path $cache 'prompts') | Should -BeFalse

        # the new theme now merges into the catalog and is resolvable
        (Get-PoshPaletteThemes).Id | Should -Contain 'zz-test'
    }

    It 'does not re-download themes already present' {
        Mock -ModuleName PoshPalette Get-PoshPaletteRemoteCatalog {
            param($Kind)
            if ($Kind -eq 'themes') { ,@([pscustomobject]@{ Id = 'tokyo-night'; DownloadUrl = 'https://x/themes/tokyo-night.json' }) }
            else { ,@() }
        }
        Mock -ModuleName PoshPalette Invoke-RestMethod { throw 'should not be called' }
        Update-PoshPaletteCatalog -Force | Should -Be 0
    }
}

Describe 'Version check' {
    It 'parses the highest published version from the Gallery feed' {
        InModuleScope PoshPalette {
            Mock Invoke-WebRequest {
                [pscustomobject]@{ Content = @'
<feed>
<entry><m:properties><d:Version>0.3.0</d:Version></m:properties></entry>
<entry><m:properties><d:Version>0.4.2</d:Version></m:properties></entry>
<entry><m:properties><d:Version>0.4.10</d:Version></m:properties></entry>
</feed>
'@ }
            }
            Get-PoshPaletteLatestVersion | Should -Be '0.4.10'
        }
    }

    It 'flags an update when the cached latest exceeds the installed version' {
        Mock -ModuleName PoshPalette Get-PoshPaletteCacheRoot { Join-Path $TestDrive 'catalog' }
        Mock -ModuleName PoshPalette Get-PoshPaletteInstalledVersion { [version]'0.4.2' }
        $cache = Join-Path $TestDrive 'catalog'
        New-Item -ItemType Directory -Path $cache -Force | Out-Null
        Set-Content -Path (Join-Path $cache '.latest-version') -Value '9.9.9'
        (InModuleScope PoshPalette { Get-PoshPaletteUpdateAvailable }) | Should -Be '9.9.9'
    }

    It 'reports no update when already current' {
        Mock -ModuleName PoshPalette Get-PoshPaletteCacheRoot { Join-Path $TestDrive 'catalog' }
        Mock -ModuleName PoshPalette Get-PoshPaletteInstalledVersion { [version]'0.4.2' }
        $cache = Join-Path $TestDrive 'catalog'
        New-Item -ItemType Directory -Path $cache -Force | Out-Null
        Set-Content -Path (Join-Path $cache '.latest-version') -Value '0.1.0'
        (InModuleScope PoshPalette { Get-PoshPaletteUpdateAvailable }) | Should -BeNullOrEmpty
    }
}
