# Tui.ps1 - the interactive console UI (Simple + Detail modes).
# Hand-rolled with [Console]::ReadKey + truecolor ANSI so there are zero deps.

$e = [char]27   # ESC

function Write-Fg { param([string]$Hex, [string]$Text)
    $r = [convert]::ToInt32($Hex.Substring(1,2),16)
    $g = [convert]::ToInt32($Hex.Substring(3,2),16)
    $b = [convert]::ToInt32($Hex.Substring(5,2),16)
    "$e[38;2;$r;$g;${b}m$Text$e[0m"
}

# Merge a working composition (hashtable) with optional slot overrides and
# return it as a PSCustomObject ready for Resolve-PoshPaletteTheme.
function ConvertTo-PPComposition {
    param([hashtable] $Comp, [hashtable] $Override = @{})
    $h = @{}
    foreach ($k in $Comp.Keys)     { $h[$k] = $Comp[$k] }
    foreach ($k in $Override.Keys) { $h[$k] = $Override[$k] }
    [pscustomobject]$h
}

# A faithful mock of a styled prompt + typed command + output, drawn from the
# theme's own hex values. Stands in for the layers a full-screen TUI hides.
function Show-PoshPalettePreview {
    param($Theme, [int] $Left = 40, [int] $Top = 3)
    $pr = $Theme.psReadLine
    $line = { param($n,$txt) [Console]::SetCursorPosition($Left, $Top + $n); Write-Host $txt }

    & $line 0 (Write-Fg $Theme.terminal.scheme.purple '  Preview')
    & $line 1 ''
    & $line 2 ((Write-Fg $Theme.terminal.scheme.green '  user') + (Write-Fg $pr.Comment ' in ') + (Write-Fg $Theme.terminal.scheme.blue '~/projects') + (Write-Fg $Theme.terminal.scheme.purple ' ❯'))
    & $line 3 ('  ' + (Write-Fg $pr.Command 'git') + ' ' + (Write-Fg $pr.Parameter 'commit') + ' ' + (Write-Fg $pr.Parameter '-m') + ' ' + (Write-Fg $pr.String '"feat: theme"'))
    & $line 4 ('  ' + (Write-Fg $pr.Variable '$count') + ' ' + (Write-Fg $pr.Operator '=') + ' ' + (Write-Fg $pr.Number '42'))
    & $line 5 ('  ' + (Write-Fg $pr.Comment '# a comment'))
    & $line 6 ('  ' + (Write-Fg $Theme.psStyle.Directory 'Documents/') + '  ' + (Write-Fg $pr.Default 'README.md'))
    & $line 7 ('  ' + (Write-Fg $Theme.psStyle.Error 'Error: something failed'))
}

# Generic scrollable picker. Items need a .Name; returns the chosen item or $null.
function Show-PoshPaletteList {
    param([string] $Title, [array] $Items, [scriptblock] $PreviewFor)

    $idx = 0
    [Console]::CursorVisible = $false
    try {
        while ($true) {
            Clear-Host
            Write-Host ""
            Write-Host "  $Title" -ForegroundColor Cyan
            Write-Host "  ↑/↓ move   Enter select   Esc back" -ForegroundColor DarkGray
            Write-Host ""
            for ($i = 0; $i -lt $Items.Count; $i++) {
                $marker = if ($i -eq $idx) { '❯' } else { ' ' }
                $color  = if ($i -eq $idx) { 'White' } else { 'DarkGray' }
                Write-Host ("  $marker $($Items[$i].Name)") -ForegroundColor $color
            }
            if ($PreviewFor) { & $PreviewFor $Items[$idx] }

            $key = [Console]::ReadKey($true)
            switch ($key.Key) {
                'UpArrow'   { $idx = ($idx - 1 + $Items.Count) % $Items.Count }
                'DownArrow' { $idx = ($idx + 1) % $Items.Count }
                'Enter'     { return $Items[$idx] }
                'Escape'    { return $null }
            }
        }
    } finally { [Console]::CursorVisible = $true }
}

# --- Simple mode: pick a full preset ------------------------------------------

function Invoke-PoshPaletteSimpleMode {
    $themes = Get-PoshPaletteThemes
    $chosen = Show-PoshPaletteList -Title 'Simple mode - pick a theme' -Items $themes -PreviewFor {
        param($t) Show-PoshPalettePreview -Theme (Resolve-PoshPaletteTheme $t.Data)
    }
    if ($chosen) { Clear-Host; Set-PoshPaletteTheme -Theme (Resolve-PoshPaletteTheme $chosen.Data) }
}

# Adjust a numeric value with the arrow keys. Returns the new value, or $null on Esc.
function Invoke-PoshPaletteAdjust {
    param([string] $Label, [int] $Value, [int] $Min, [int] $Max, [int] $Step, [string] $Suffix = '')
    [Console]::CursorVisible = $false
    try {
        while ($true) {
            Clear-Host
            Write-Host "`n  $Label" -ForegroundColor Cyan
            Write-Host "  </> adjust   Enter confirm   Esc cancel`n" -ForegroundColor DarkGray
            Write-Host ("    " + $Value + $Suffix) -ForegroundColor White
            $key = [Console]::ReadKey($true)
            switch ($key.Key) {
                'LeftArrow'  { $Value = [Math]::Max($Min, $Value - $Step) }
                'RightArrow' { $Value = [Math]::Min($Max, $Value + $Step) }
                'Enter'      { return $Value }
                'Escape'     { return $null }
            }
        }
    } finally { [Console]::CursorVisible = $true }
}

# --- Detail mode: compose each layer independently ----------------------------

function Invoke-PoshPaletteDetailMode {
    $presets = Get-PoshPaletteThemes
    if (-not $presets) { return }
    $base = $presets[0].Data

    # Working composition as a mutable hashtable, seeded from the first preset.
    $comp = @{
        name     = 'Custom'
        scheme   = $base.scheme
        palette  = $base.palette
        prompt   = $base.prompt
        font     = $base.font
        fontSize = [int]($base.fontSize ?? 11)
        opacity  = [int]($base.opacity ?? 100)
        acrylic  = [bool]($base.acrylic ?? $false)
    }

    [Console]::CursorVisible = $false
    try {
        while ($true) {
            Clear-Host
            Write-Host "`n  Detail mode - compose your look" -ForegroundColor Cyan
            Write-Host "  1-7 edit   A apply   Esc back`n" -ForegroundColor DarkGray
            Write-Host "  [1] Scheme       : $($comp.scheme)"
            Write-Host "  [2] Shell colors : $($comp.palette)"
            Write-Host "  [3] Prompt       : $($comp.prompt)"
            Write-Host "  [4] Font         : $($comp.font)"
            Write-Host "  [5] Opacity      : $($comp.opacity)%"
            Write-Host "  [6] Acrylic      : $(if ($comp.acrylic) { 'on' } else { 'off' })"
            Write-Host "  [7] Font size    : $($comp.fontSize)"
            Write-Host "`n  [A] Apply   [Esc] Back" -ForegroundColor DarkGray
            Show-PoshPalettePreview -Theme (Resolve-PoshPaletteTheme (ConvertTo-PPComposition $comp))

            $key = [Console]::ReadKey($true)
            if ($key.Key -eq 'Escape') { return }
            switch ($key.KeyChar) {
                '1' {
                    $pf = { param($it) Show-PoshPalettePreview -Theme (Resolve-PoshPaletteTheme (ConvertTo-PPComposition $comp @{ scheme = $it.Id })) }.GetNewClosure()
                    $p = Show-PoshPaletteList -Title 'Color scheme' -Items (Get-PoshPaletteCatalog schemes) -PreviewFor $pf
                    if ($p) { $comp.scheme = $p.Id }
                }
                '2' {
                    $pf = { param($it) Show-PoshPalettePreview -Theme (Resolve-PoshPaletteTheme (ConvertTo-PPComposition $comp @{ palette = $it.Id })) }.GetNewClosure()
                    $p = Show-PoshPaletteList -Title 'Shell colors (PSReadLine + output)' -Items (Get-PoshPaletteCatalog palettes) -PreviewFor $pf
                    if ($p) { $comp.palette = $p.Id }
                }
                '3' {
                    $pf = { param($it) Show-PoshPalettePreview -Theme (Resolve-PoshPaletteTheme (ConvertTo-PPComposition $comp @{ prompt = $it.Id })) }.GetNewClosure()
                    $p = Show-PoshPaletteList -Title 'Prompt (oh-my-posh)' -Items (Get-PoshPaletteCatalog prompts) -PreviewFor $pf
                    if ($p) { $comp.prompt = $p.Id }
                }
                '4' {
                    # Font can't be shown in the ANSI preview; pick from the list.
                    $p = Show-PoshPaletteList -Title 'Font (must be installed)' -Items (Get-PoshPaletteFonts)
                    if ($p) { $comp.font = $p.id }
                }
                '5' {
                    $v = Invoke-PoshPaletteAdjust 'Opacity' ([int]$comp.opacity) 30 100 5 '%'
                    if ($null -ne $v) { $comp.opacity = $v }
                }
                '6' { $comp.acrylic = -not [bool]$comp.acrylic }
                '7' {
                    $v = Invoke-PoshPaletteAdjust 'Font size' ([int]$comp.fontSize) 8 24 1
                    if ($null -ne $v) { $comp.fontSize = $v }
                }
                { $_ -in 'a', 'A' } {
                    Clear-Host
                    Set-PoshPaletteTheme -Theme (Resolve-PoshPaletteTheme (ConvertTo-PPComposition $comp))
                    return
                }
            }
        }
    } finally { [Console]::CursorVisible = $true }
}

# --- Entry point --------------------------------------------------------------

function Start-PoshPalette {
    [CmdletBinding()]
    param()
    while ($true) {
        Clear-Host
        Write-Host ""
        Write-Host "  ██ Posh Palette" -ForegroundColor Magenta
        Write-Host "  Style your PowerShell + Windows Terminal across all 4 layers.`n" -ForegroundColor DarkGray
        Write-Host "  [1] Simple mode  - scroll a list of full themes, pick one"
        Write-Host "  [2] Detail mode  - compose each layer (scheme / colors / prompt / font)"
        Write-Host "  [3] Doctor       - check your setup (fonts, oh-my-posh, terminal)"
        Write-Host "  [Q] Quit`n"
        $key = [Console]::ReadKey($true)
        switch ($key.KeyChar) {
            '1' { Invoke-PoshPaletteSimpleMode }
            '2' { Invoke-PoshPaletteDetailMode }
            '3' { Clear-Host; Test-PoshPaletteSetup | Out-Null; Write-Host "  Press any key to return..." -ForegroundColor DarkGray; [Console]::ReadKey($true) | Out-Null }
            { $_ -in 'q', 'Q' } { return }
        }
    }
}
