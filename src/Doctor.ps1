# Doctor.ps1 - preflight check.
#
# PoshPalette writes colors, but the layers only light up if the surrounding
# tools are present: PowerShell 7.2+, PSReadLine, oh-my-posh, a Nerd Font, and a
# reachable Windows Terminal settings.json. `Test-PoshPaletteSetup` reports what's
# ready and what to fix, so a fresh machine gets actionable guidance, not a shrug.

function New-PoshPaletteCheck {
    param([string] $Name, [ValidateSet('Ok','Warn','Fail')] [string] $Status, [string] $Detail, [string] $Fix)
    [pscustomobject]@{ Name = $Name; Status = $Status; Detail = $Detail; Fix = $Fix }
}

function Test-PoshPaletteFont {
    # Best-effort Nerd Font detection. Reliable only on Windows (font registry).
    if ($IsWindows -or $PSVersionTable.PSEdition -eq 'Desktop') {
        $keys = @('HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts',
                  'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts')
        foreach ($k in $keys) {
            if (Test-Path $k) {
                $names = (Get-ItemProperty $k).psobject.Properties.Name
                if ($names -match 'Nerd Font|NF ') { return $true }
            }
        }
        return $false
    }
    return $null   # unknown off-Windows
}

function Test-PoshPaletteSetup {
    [CmdletBinding()]
    param([switch] $Quiet)

    $checks = @()

    # PowerShell version
    $v = $PSVersionTable.PSVersion
    $checks += if ($v -ge [version]'7.2') {
        New-PoshPaletteCheck 'PowerShell 7.2+' 'Ok' "$v"
    } else {
        New-PoshPaletteCheck 'PowerShell 7.2+' 'Fail' "$v" 'Install PowerShell 7.2 or newer (winget install Microsoft.PowerShell).'
    }

    # PSReadLine (layer 2)
    $prl = Get-Module -ListAvailable PSReadLine | Sort-Object Version -Descending | Select-Object -First 1
    $checks += if ($prl) {
        New-PoshPaletteCheck 'PSReadLine (input colors)' 'Ok' "v$($prl.Version)"
    } else {
        New-PoshPaletteCheck 'PSReadLine (input colors)' 'Warn' 'not found' 'Install-Module PSReadLine -Scope CurrentUser'
    }

    # $PSStyle (layer 3) - built in on 7.2+, so this just confirms availability
    $checks += if ($PSStyle) {
        New-PoshPaletteCheck '$PSStyle (output colors)' 'Ok' 'available'
    } else {
        New-PoshPaletteCheck '$PSStyle (output colors)' 'Warn' 'unavailable' 'Upgrade to PowerShell 7.2+.'
    }

    # oh-my-posh (layer 4)
    $omp = Get-Command oh-my-posh -ErrorAction SilentlyContinue
    $checks += if ($omp) {
        New-PoshPaletteCheck 'oh-my-posh (prompt)' 'Ok' $omp.Source
    } else {
        New-PoshPaletteCheck 'oh-my-posh (prompt)' 'Warn' 'not on PATH' 'winget install JanDeDobbeleer.OhMyPosh - only needed for the prompt layer.'
    }

    # POSH_THEMES_PATH (only matters for referenced, non-auto prompts)
    $checks += if ($env:POSH_THEMES_PATH -and (Test-Path $env:POSH_THEMES_PATH)) {
        New-PoshPaletteCheck 'oh-my-posh themes path' 'Ok' $env:POSH_THEMES_PATH
    } else {
        New-PoshPaletteCheck 'oh-my-posh themes path' 'Warn' 'POSH_THEMES_PATH not set' "Set by oh-my-posh's installer, or use an 'auto' prompt (no external theme needed)."
    }

    # Nerd Font
    $font = Test-PoshPaletteFont
    $checks += if ($font -eq $true) {
        New-PoshPaletteCheck 'Nerd Font installed' 'Ok' 'found'
    } elseif ($font -eq $false) {
        New-PoshPaletteCheck 'Nerd Font installed' 'Warn' 'none detected' "Run Install-PoshPaletteFont jetbrains (or any font id) to download + install one."
    } else {
        New-PoshPaletteCheck 'Nerd Font installed' 'Warn' "can't verify on this OS" 'Run Install-PoshPaletteFont jetbrains, then set it as your terminal font.'
    }

    # Windows Terminal settings.json (layer 1)
    $wt = Get-WindowsTerminalSettingsPath
    $checks += if ($wt) {
        New-PoshPaletteCheck 'Windows Terminal settings' 'Ok' $wt
    } elseif ($IsWindows -or $PSVersionTable.PSEdition -eq 'Desktop') {
        New-PoshPaletteCheck 'Windows Terminal settings' 'Warn' 'settings.json not found' 'Open Windows Terminal once to create it.'
    } else {
        New-PoshPaletteCheck 'Windows Terminal settings' 'Warn' 'not on Windows' 'The Terminal scheme layer is Windows-only; the other 3 layers still apply.'
    }

    # $PROFILE (layers 2-4 are written here)
    $profDir = Split-Path $PROFILE -Parent
    $checks += if (Test-Path $PROFILE) {
        New-PoshPaletteCheck 'PowerShell profile' 'Ok' $PROFILE
    } elseif (Test-Path $profDir) {
        New-PoshPaletteCheck 'PowerShell profile' 'Ok' "will be created at $PROFILE"
    } else {
        New-PoshPaletteCheck 'PowerShell profile' 'Warn' 'profile dir missing' 'Created automatically on first apply.'
    }

    if (-not $Quiet) {
        $nameW = (@($checks | ForEach-Object { $_.Name.Length }) + 4 | Measure-Object -Maximum).Maximum
        Write-Host "`n  Doctor" -ForegroundColor White
        Write-Host ('  ' + ([string][char]0x2500 * ($nameW + 22))) -ForegroundColor DarkGray
        foreach ($c in $checks) {
            $glyph, $color = switch ($c.Status) {
                'Ok'   { [char]0x2713, 'Green' }   # check
                'Warn' { '!',          'Yellow' }
                'Fail' { [char]0x2717, 'Red' }     # cross
            }
            $word = switch ($c.Status) { 'Ok' { 'ok' } 'Warn' { 'warn' } 'Fail' { 'fail' } }
            Write-Host ('  ' + $c.Name.PadRight($nameW) + '  ') -NoNewline
            Write-Host "$glyph " -ForegroundColor $color -NoNewline
            Write-Host ($word.PadRight(5) + ' ') -ForegroundColor $color -NoNewline
            Write-Host $c.Detail -ForegroundColor DarkGray
            if ($c.Fix -and $c.Status -ne 'Ok') {
                Write-Host ('  ' + (' ' * $nameW) + '    ↳ ' + $c.Fix) -ForegroundColor DarkGray
            }
        }
        $fail = @($checks | Where-Object Status -eq 'Fail').Count
        $warn = @($checks | Where-Object Status -eq 'Warn').Count
        $msg  = if ($fail) { "$fail blocking issue(s), $warn warning(s)." }
                elseif ($warn) { "Ready. $warn optional warning(s) - layers with a warning just won't apply." }
                else { 'All clear. Every layer is good to go.' }
        Write-Host "`n  $msg`n" -ForegroundColor Cyan
    }

    $checks
}
