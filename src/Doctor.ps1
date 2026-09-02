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

# Does a font registry key name belong to a Nerd Font? Kept as a pure predicate
# so it's testable off-Windows, where there is no font registry to read.
#
# Keys are named after the font *file* title, not the family, so a normal install
# registers as 'JetBrainsMonoNerdFont-Bold (TrueType)' - no spaces - and matching
# on the spaced family name alone reports a fully-installed font as missing.
# Match both shapes: the spaced name for builds that register the family
# ('CaskaydiaCove NFM', 'FiraCode Nerd Font Mono') and the squashed name for the
# file titles. Same normalisation Test-PoshPaletteFontInstalled uses.
function Test-PoshPaletteNerdFontName {
    param([Parameter(Mandatory)] [AllowEmptyString()] [string] $Name)
    $Name -match 'Nerd Font|\bNF[MP]?\b' -or ($Name -replace '\s', '') -match 'NerdFont|NF[MP]?-'
}

# The registry key of the first installed Nerd Font, or $null. Windows only.
function Get-PoshPaletteNerdFontKey {
    $keys = @('HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts',
              'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts')
    foreach ($k in $keys) {
        if (-not (Test-Path $k)) { continue }
        foreach ($name in (Get-ItemProperty $k).psobject.Properties.Name) {
            if (Test-PoshPaletteNerdFontName $name) { return $name }
        }
    }
    $null
}

# 'JetBrainsMonoNerdFont-Bold (TrueType)' -> 'JetBrainsMonoNerdFont'
function Format-PoshPaletteFontFamily {
    param([Parameter(Mandatory)] [AllowEmptyString()] [string] $KeyName)
    (($KeyName -replace '\s*\((TrueType|OpenType)\)\s*$', '') -split '-')[0].Trim()
}

function Test-PoshPaletteFont {
    # Best-effort Nerd Font detection. Reliable only on Windows (font registry).
    if ($IsWindows -or $PSVersionTable.PSEdition -eq 'Desktop') {
        return [bool] (Get-PoshPaletteNerdFontKey)
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
        New-PoshPaletteCheck 'oh-my-posh (prompt)' 'Warn' 'not on PATH' 'Only needed for the prompt layer - applying a prompt theme offers to install it (winget, no admin), or run: winget install JanDeDobbeleer.OhMyPosh -s winget.'
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
        New-PoshPaletteCheck 'Nerd Font installed' 'Ok' (Format-PoshPaletteFontFamily (Get-PoshPaletteNerdFontKey))
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
