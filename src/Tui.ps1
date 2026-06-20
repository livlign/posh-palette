# Tui.ps1 - the interactive console UI (Simple + Detail modes).
# Hand-rolled with [Console]::ReadKey + truecolor ANSI so there are zero deps.

$e = [char]27   # ESC

function Write-Fg { param([string]$Hex, [string]$Text)
    $r = [convert]::ToInt32($Hex.Substring(1,2),16)
    $g = [convert]::ToInt32($Hex.Substring(3,2),16)
    $b = [convert]::ToInt32($Hex.Substring(5,2),16)
    "$e[38;2;$r;$g;${b}m$Text$e[0m"
}

# --- shared UI primitives (refined-flat style) --------------------------------

# A dim horizontal rule under section titles.
function Write-PPRule { param([int] $Width = 54) Write-Host ('  ' + ([string][char]0x2500 * $Width)) -ForegroundColor DarkGray }

# A dim footer of key hints, separated by middots.
function Write-PPFooter { param([string[]] $Hints) Write-Host ''; Write-Host ('  ' + ($Hints -join '   ·   ')) -ForegroundColor DarkGray }

# Longest .Length among strings, for programmatic column sizing.
function Get-PPMaxLen { param([string[]] $Strings) (@($Strings | ForEach-Object { ([string]$_).Length }) + 0 | Measure-Object -Maximum).Maximum }

# One selectable row. The selected row gets an inverse-video pill; the leading
# marker area is a fixed 3 cells (" ❯ " when selected, "   " when not) so the
# text starts at the same column in both states.
function Write-PPRow {
    param([bool] $Selected, [string] $Text, [int] $Width)
    $pad = ([string]$Text).PadRight($Width)
    if ($Selected) {
        Write-Host '  ' -NoNewline
        Write-Host (" ❯ $pad ") -ForegroundColor Black -BackgroundColor Gray
    } else {
        Write-Host ("     $pad ") -ForegroundColor DarkGray
    }
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

# A mini terminal drawn from the theme's own hex values, rendered on a filled
# block of the theme's BACKGROUND color so the whole thing recolors as you scroll
# (a foreground-only preview looked static on the host terminal's dark bg).
function Show-PoshPalettePreview {
    param($Theme, [int] $Left = 42, [int] $Top = 4)
    $sc = $Theme.terminal.scheme
    $pr = $Theme.psReadLine
    $ps = $Theme.psStyle
    $W  = 42
    $rgb = { param($h) '{0};{1};{2}' -f [convert]::ToInt32($h.Substring(1,2),16), [convert]::ToInt32($h.Substring(3,2),16), [convert]::ToInt32($h.Substring(5,2),16) }
    $bg  = & $rgb $sc.background

    # Build one line from a flat list of hex,text,hex,text... on the bg block.
    $row = {
        param([object[]] $parts)
        $s = "$e[48;2;${bg}m"; $len = 0
        for ($j = 0; $j -lt $parts.Count; $j += 2) {
            $hex = $parts[$j]; if (-not $hex) { $hex = $sc.foreground }
            $s += "$e[38;2;$(& $rgb $hex)m$($parts[$j + 1])"
            $len += ('' + $parts[$j + 1]).Length
        }
        if ($len -lt $W) { $s += (' ' * ($W - $len)) }
        $s + "$e[0m"
    }

    $lines = @(
        (& $row @($sc.purple, '  preview'))
        (& $row @($null, ''))
        (& $row @($sc.green, '  user', $pr.Comment, ' in ', $sc.blue, '~/projects', $sc.purple, ' ❯'))
        (& $row @($pr.Command, '  git', $null, ' ', $pr.Parameter, 'commit', $null, ' ', $pr.Parameter, '-m', $null, ' ', $pr.String, '"feat: theme"'))
        (& $row @($pr.Variable, '  $count', $pr.Operator, ' = ', $pr.Number, '42'))
        (& $row @($pr.Comment, '  # tidy up'))
        (& $row @($ps.Directory, '  Documents/', $null, '  README.md'))
        (& $row @($ps.Error, '  Error: build failed'))
        (& $row @($null, ''))
        (& $row @($sc.green, '  user', $pr.Comment, ' in ', $sc.blue, '~/projects', $sc.purple, ' ❯ '))
    )

    [Console]::CursorVisible = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        try { [Console]::SetCursorPosition($Left, $Top + $i); [Console]::Write($lines[$i]) } catch { }
    }
    [Console]::Write("$e[0m")
}

# Generic scrollable picker. Items need a .Name; returns the chosen item or $null.
# A navigable "Back" row sits below the items (Esc is still the shortcut).
function Show-PoshPaletteList {
    param([string] $Title, [array] $Items, [scriptblock] $PreviewFor)

    $idx   = 0
    $total = $Items.Count + 1   # +1 for the Back row
    $width = [Math]::Max((Get-PPMaxLen (@($Items | ForEach-Object { $_.Name }) + '← Back')), 12)
    [Console]::CursorVisible = $false
    try {
        while ($true) {
            Clear-Host
            Write-Host ""
            Write-Host "  $Title" -ForegroundColor White
            Write-PPRule
            Write-Host ""
            for ($i = 0; $i -lt $Items.Count; $i++) {
                Write-PPRow ($i -eq $idx) $Items[$i].Name $width
            }
            Write-PPRow ($idx -eq $Items.Count) '← Back' $width
            Write-PPFooter @('↑/↓ move', 'Enter select', 'Esc back')
            if ($PreviewFor -and $idx -lt $Items.Count) { & $PreviewFor $Items[$idx] }

            $key = [Console]::ReadKey($true)
            switch ($key.Key) {
                'UpArrow'   { $idx = ($idx - 1 + $total) % $total }
                'DownArrow' { $idx = ($idx + 1) % $total }
                'Enter'     { if ($idx -eq $Items.Count) { return $null } else { return $Items[$idx] } }
                'Escape'    { return $null }
            }
        }
    } finally { [Console]::CursorVisible = $true }
}

# --- Simple mode: pick a full preset ------------------------------------------

# Shown after a theme is applied: confirms what happened and what to do next.
# Returns 'quit' if the user chose to quit, otherwise $null (back to menu).
function Show-PoshPaletteApplied {
    param($Theme)
    Write-Host ""
    Write-Host "  ✓ Applied '$($Theme.name)'" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Next steps" -ForegroundColor Cyan
    Write-Host "    • Terminal colors update instantly in this window." -ForegroundColor Gray
    Write-Host "    • Open a NEW tab or window to load the prompt + input colors." -ForegroundColor Gray
    Write-Host "    • Tweak one layer later, e.g.  Set-PoshPalettePrompt <name>" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  [Enter] back to menu     [Q] quit" -ForegroundColor DarkGray
    while ($true) {
        $k = [Console]::ReadKey($true)
        if ($k.Key -eq 'Enter' -or $k.Key -eq 'Escape') { return $null }
        if ([string]$k.KeyChar -in 'q', 'Q')            { return 'quit' }
    }
}

function Invoke-PoshPaletteSimpleMode {
    $themes = Get-PoshPaletteThemes
    $chosen = Show-PoshPaletteList -Title 'Simple mode - pick a theme' -Items $themes -PreviewFor {
        param($t) Show-PoshPalettePreview -Theme (Resolve-PoshPaletteTheme $t.Data)
    }
    if ($chosen) {
        Clear-Host
        $t = Resolve-PoshPaletteTheme $chosen.Data
        Set-PoshPaletteTheme -Theme $t
        return (Show-PoshPaletteApplied $t)
    }
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

# Build a live preview callback for a list picker that swaps one slot of the
# working composition. We use a plain (non-closure) scriptblock bound to the
# module session state plus $script: capture vars, because .GetNewClosure()
# rebinds the block to a fresh dynamic module that can't see module functions
# like ConvertTo-PPComposition / Resolve-PoshPaletteTheme.
$script:PPPreviewComp = $null
$script:PPPreviewSlot = $null
function New-PoshPalettePreviewFor {
    param([hashtable] $Comp, [string] $Slot)
    $script:PPPreviewComp = $Comp
    $script:PPPreviewSlot = $Slot
    { param($it)
        Show-PoshPalettePreview -Theme (Resolve-PoshPaletteTheme (ConvertTo-PPComposition $script:PPPreviewComp @{ $script:PPPreviewSlot = $it.Id }))
    }
}

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

    # Menu rows: 7 editable fields + Apply + Back. Arrows OR number/letter keys.
    $rows = @('scheme', 'palette', 'prompt', 'font', 'opacity', 'acrylic', 'fontsize', 'apply', 'back')
    $idx  = 0

    $invoke = {
        param([string] $id)
        switch ($id) {
            'scheme' {
                $p = Show-PoshPaletteList -Title 'Color scheme' -Items (Get-PoshPaletteCatalog schemes) -PreviewFor (New-PoshPalettePreviewFor $comp 'scheme')
                if ($p) { $comp.scheme = $p.Id }
            }
            'palette' {
                $p = Show-PoshPaletteList -Title 'Shell colors (PSReadLine + output)' -Items (Get-PoshPaletteCatalog palettes) -PreviewFor (New-PoshPalettePreviewFor $comp 'palette')
                if ($p) { $comp.palette = $p.Id }
            }
            'prompt' {
                $p = Show-PoshPaletteList -Title 'Prompt (oh-my-posh)' -Items (Get-PoshPaletteCatalog prompts) -PreviewFor (New-PoshPalettePreviewFor $comp 'prompt')
                if ($p) { $comp.prompt = $p.Id }
            }
            'font' {
                # Font can't be shown in the ANSI preview; pick from the list.
                $p = Show-PoshPaletteList -Title 'Font (must be installed)' -Items (Get-PoshPaletteFonts)
                if ($p) { $comp.font = $p.id }
            }
            'opacity' {
                $v = Invoke-PoshPaletteAdjust 'Opacity' ([int]$comp.opacity) 30 100 5 '%'
                if ($null -ne $v) { $comp.opacity = $v }
            }
            'acrylic'  { $comp.acrylic = -not [bool]$comp.acrylic }
            'fontsize' {
                $v = Invoke-PoshPaletteAdjust 'Font size' ([int]$comp.fontSize) 8 24 1
                if ($null -ne $v) { $comp.fontSize = $v }
            }
            'apply' {
                Clear-Host
                $t = Resolve-PoshPaletteTheme (ConvertTo-PPComposition $comp)
                Set-PoshPaletteTheme -Theme $t
                return (Show-PoshPaletteApplied $t)   # 'quit' or $null
            }
        }
        return ''
    }

    [Console]::CursorVisible = $false
    try {
        while ($true) {
            Clear-Host
            Write-Host ""
            Write-Host "  Detail mode - compose your look" -ForegroundColor White
            Write-PPRule
            Write-Host ""
            $tr = { param($s) $v = [string]$s; if ($v.Length -gt 16) { $v.Substring(0, 15) + '…' } else { $v } }
            $labels = @(
                "[1] Scheme       : $(& $tr $comp.scheme)"
                "[2] Shell colors : $(& $tr $comp.palette)"
                "[3] Prompt       : $(& $tr $comp.prompt)"
                "[4] Font         : $(& $tr $comp.font)"
                "[5] Opacity      : $($comp.opacity)%"
                "[6] Acrylic      : $(if ($comp.acrylic) { 'on' } else { 'off' })"
                "[7] Font size    : $($comp.fontSize)"
                "[A] Apply"
                "[Esc] ← Back"
            )
            $lw = Get-PPMaxLen $labels
            for ($i = 0; $i -lt $labels.Count; $i++) {
                Write-PPRow ($i -eq $idx) $labels[$i] $lw
            }
            Write-PPFooter @('↑/↓ move', 'Enter edit', 'A apply', 'Esc back')
            # live preview as the right column, top-aligned with the field rows
            Show-PoshPalettePreview -Theme (Resolve-PoshPaletteTheme (ConvertTo-PPComposition $comp)) -Left ($lw + 9) -Top 4

            $key = [Console]::ReadKey($true)
            if ($key.Key -eq 'Escape') { return }
            $target = $null
            switch ($key.Key) {
                'UpArrow'   { $idx = ($idx - 1 + $rows.Count) % $rows.Count }
                'DownArrow' { $idx = ($idx + 1) % $rows.Count }
                'Enter'     { $target = $rows[$idx] }
            }
            switch ($key.KeyChar) {
                '1' { $target = 'scheme'; $idx = 0 }
                '2' { $target = 'palette'; $idx = 1 }
                '3' { $target = 'prompt'; $idx = 2 }
                '4' { $target = 'font'; $idx = 3 }
                '5' { $target = 'opacity'; $idx = 4 }
                '6' { $target = 'acrylic'; $idx = 5 }
                '7' { $target = 'fontsize'; $idx = 6 }
                { $_ -in 'a', 'A' } { $target = 'apply'; $idx = 7 }
            }
            if ($target -eq 'back') { return }
            if ($target) {
                $r = & $invoke $target
                if ($target -eq 'apply') { return $r }   # 'quit' bubbles to Start
            }
        }
    } finally { [Console]::CursorVisible = $true }
}

# --- Entry point --------------------------------------------------------------

function Start-PoshPalette {
    [CmdletBinding()]
    param()
    $items = @(
        @{ Key = '1'; Title = 'Simple mode'; Desc = 'Pick a full theme from a scrollable list';   Run = { Invoke-PoshPaletteSimpleMode } }
        @{ Key = '2'; Title = 'Detail mode'; Desc = 'Compose scheme, colors, prompt, font';        Run = { Invoke-PoshPaletteDetailMode } }
        @{ Key = '3'; Title = 'Doctor';      Desc = 'Check fonts, oh-my-posh, terminal';           Run = { Clear-Host; Test-PoshPaletteSetup | Out-Null; Write-Host "`n  [Enter] back to menu" -ForegroundColor DarkGray; [Console]::ReadKey($true) | Out-Null } }
        @{ Key = 'Q'; Title = 'Quit';        Desc = 'Exit Posh Palette';                           Run = { 'quit' } }
    )
    $titleW = Get-PPMaxLen ($items | ForEach-Object { $_.Title })
    $texts  = $items | ForEach-Object { "[$($_.Key)] " + $_.Title.PadRight($titleW) + '   ' + $_.Desc }
    $rowW   = Get-PPMaxLen $texts
    $idx = 0
    [Console]::CursorVisible = $false
    try {
        while ($true) {
            Clear-Host
            Write-Host ""
            Write-Host "  >_  " -ForegroundColor White -NoNewline
            Write-Host "Posh Palette" -ForegroundColor White
            Write-PPRule
            Write-Host "  Style all 4 layers: scheme · PSReadLine · `$PSStyle · prompt" -ForegroundColor DarkGray
            Write-Host ""
            for ($i = 0; $i -lt $items.Count; $i++) {
                Write-PPRow ($i -eq $idx) $texts[$i] $rowW
            }
            Write-PPFooter @('↑/↓ move', 'Enter select', 'Q quit')

            $key = [Console]::ReadKey($true)
            # arrow navigation
            switch ($key.Key) {
                'UpArrow'   { $idx = ($idx - 1 + $items.Count) % $items.Count }
                'DownArrow' { $idx = ($idx + 1) % $items.Count }
                'Enter'     { if ((& $items[$idx].Run) -eq 'quit') { return } }
                'Escape'    { return }
            }
            # number/letter shortcuts (arrow keys have KeyChar 0, so no double-fire)
            $ch  = ([string]$key.KeyChar).ToUpper()
            $hit = $items | Where-Object { $_.Key -eq $ch } | Select-Object -First 1
            if ($hit) { if ((& $hit.Run) -eq 'quit') { return } }
        }
    } finally { [Console]::CursorVisible = $true }
}
