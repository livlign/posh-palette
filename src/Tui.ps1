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

# "#rrggbb" -> "r;g;b" for truecolor ANSI.
function ConvertTo-PPRgb { param([string] $h) '{0};{1};{2}' -f [convert]::ToInt32($h.Substring(1,2),16), [convert]::ToInt32($h.Substring(3,2),16), [convert]::ToInt32($h.Substring(5,2),16) }

# Visible width of a string, ignoring SGR color escapes.
function Get-PPVisibleLength { param([string] $s) ($s -replace "$e\[[0-9;]*m", '').Length }

# Render the actual prompt for a resolved theme. If oh-my-posh is available we ask
# it to print the real prompt for this exact config (generated 'auto' prompt, or a
# referenced theme under POSH_THEMES_PATH); otherwise we fall back to a simple
# scheme-colored prompt. Cached per prompt config so scrolling stays responsive.
$script:PPPromptCache = @{}
function Get-PoshPalettePromptAnsi {
    param($Theme)
    $key = ($Theme.prompt | ConvertTo-Json -Depth 32 -Compress)
    if ($script:PPPromptCache.ContainsKey($key)) { return $script:PPPromptCache[$key] }

    $ansi = $null
    $omp  = Get-Command oh-my-posh -ErrorAction SilentlyContinue
    if ($omp) {
        $cfg = $null
        if ($Theme.prompt.generated) {
            try { $cfg = Save-PoshPalettePrompt -Config $Theme.prompt.config -Name 'pp-preview' } catch { }
        } elseif ($Theme.prompt.ohMyPoshTheme -and $env:POSH_THEMES_PATH) {
            $maybe = Join-Path $env:POSH_THEMES_PATH ('{0}.omp.json' -f $Theme.prompt.ohMyPoshTheme)
            if (Test-Path $maybe) { $cfg = $maybe }
        }
        if ($cfg) {
            try {
                $out  = & $omp.Source print primary --config $cfg --shell pwsh --pwd 'C:\Users\you\posh-palette' 2>$null
                $ansi = ($out -join "`n")
            } catch { }
        }
    }
    if ([string]::IsNullOrWhiteSpace($ansi)) {
        $sc   = $Theme.terminal.scheme
        $name = if ($Theme.prompt.ohMyPoshTheme) { $Theme.prompt.ohMyPoshTheme } else { 'posh-palette' }
        $ansi = "$e[38;2;$(ConvertTo-PPRgb $sc.blue)m$name $e[38;2;$(ConvertTo-PPRgb $sc.purple)m❯$e[0m"
    }
    $ansi = ($ansi -replace "`r", '' -replace "`n", '').TrimEnd()
    $script:PPPromptCache[$key] = $ansi
    $ansi
}

# A mini terminal session drawn from the theme's own hex values on a filled block
# of the theme's BACKGROUND color, so the whole thing recolors as you scroll. It
# renders the real oh-my-posh prompt plus a few representative commands + output.
function Show-PoshPalettePreview {
    param($Theme, [int] $Left = 42, [int] $Top = 4)
    $W = 46
    $bw = try { [Console]::BufferWidth } catch { 120 }
    if ($bw -lt ($Left + $W + 1)) { return }   # not enough room for a side panel; skip cleanly

    $sc = $Theme.terminal.scheme
    $pr = $Theme.psReadLine
    $ps = $Theme.psStyle
    $rgb = { param($h) ConvertTo-PPRgb $h }
    $bg  = & $rgb $sc.background

    # Plain colored line from flat hex,text,hex,text... pairs, padded on the bg.
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

    # The real prompt followed by a typed command, on the bg block.
    $promptAnsi = Get-PoshPalettePromptAnsi $Theme
    $promptBg   = $promptAnsi -replace [regex]::Escape("$e[0m"), "$e[0m$e[48;2;${bg}m"
    $promptVis  = Get-PPVisibleLength $promptAnsi
    $prow = {
        param($cmdHex, $cmdText)
        if (-not $cmdHex) { $cmdHex = $sc.foreground }
        $vis = 1 + $promptVis + 1 + ('' + $cmdText).Length
        $s = "$e[48;2;${bg}m " + $promptBg + "$e[38;2;$(& $rgb $cmdHex)m $cmdText"
        if ($vis -lt $W) { $s += (' ' * ($W - $vis)) }
        $s + "$e[0m"
    }

    $lines = @(
        (& $prow $pr.Command 'Get-ChildItem')
        (& $row  @($null, ''))
        (& $row  @($ps.TableHeader, 'Mode    LastWriteTime      Length Name'))
        (& $row  @($pr.Comment,     '----    -------------      ------ ----'))
        (& $row  @($null, 'd----   6/20/2026  9:39 AM        ', $ps.Directory, 'src'))
        (& $row  @($null, 'd----   6/20/2026  9:39 AM        ', $ps.Directory, 'docs'))
        (& $row  @($null, '-a---   6/18/2026  1:12 PM   ', $pr.Number, '8.9k', $null, ' README.md'))
        (& $row  @($null, ''))
        (& $prow $pr.Command 'git pull')
        (& $row  @($null, 'Updating ', $pr.Number, '1a2b3c4', $null, '..', $pr.Number, '5d6e7f8'))
        (& $row  @($sc.green, ' 3 files changed, ', $sc.green, '42 insertions(+)'))
        (& $row  @($null, ''))
        (& $prow $pr.Command 'npm test')
        (& $row  @($sc.green, '  ✓ ', $null, '42 passing'))
        (& $row  @($sc.red,   '  ✗ ', $null, '1 failing'))
        (& $row  @($null, ''))
        (& $prow $sc.foreground '█')
    )

    [Console]::CursorVisible = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        try { [Console]::SetCursorPosition($Left, $Top + $i); [Console]::Write($lines[$i]) } catch { }
    }
    [Console]::Write("$e[0m")
}

# Generic scrollable picker. Items need a .Name; returns the chosen item or $null.
# A navigable "Back" row sits below the items (Esc is still the shortcut). When
# -CustomPrompt is given, a "Type a name..." row lets you enter a value directly
# (returned as a synthetic item), so you can use any oh-my-posh theme / font name.
function Show-PoshPaletteList {
    param([string] $Title, [array] $Items, [scriptblock] $PreviewFor, [string] $CustomPrompt)

    $hasCustom = [bool]$CustomPrompt
    $customIdx = if ($hasCustom) { $Items.Count } else { -1 }
    $backIdx   = $Items.Count + $(if ($hasCustom) { 1 } else { 0 })
    $total     = $backIdx + 1
    $extra     = if ($hasCustom) { @('⌨ Type a name...', '← Back') } else { @('← Back') }
    $width     = [Math]::Max((Get-PPMaxLen (@($Items | ForEach-Object { $_.Name }) + $extra)), 16)
    $idx       = 0
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
            if ($hasCustom) { Write-PPRow ($idx -eq $customIdx) '⌨ Type a name...' $width }
            Write-PPRow ($idx -eq $backIdx) '← Back' $width
            Write-PPFooter @('↑/↓ move', 'Enter select', 'Esc back')
            if ($PreviewFor -and $idx -lt $Items.Count) { & $PreviewFor $Items[$idx] }

            $key = [Console]::ReadKey($true)
            switch ($key.Key) {
                'UpArrow'   { $idx = ($idx - 1 + $total) % $total }
                'DownArrow' { $idx = ($idx + 1) % $total }
                'Escape'    { return $null }
                'Enter'     {
                    if ($idx -eq $backIdx) { return $null }
                    elseif ($hasCustom -and $idx -eq $customIdx) {
                        [Console]::CursorVisible = $true
                        Write-Host ''
                        Write-Host "  $CustomPrompt" -ForegroundColor Cyan
                        $val = Read-Host '  name'
                        if (-not [string]::IsNullOrWhiteSpace($val)) {
                            return [pscustomobject]@{ Id = $val.Trim(); Name = $val.Trim(); Custom = $true }
                        }
                    }
                    else { return $Items[$idx] }
                }
            }
        }
    } finally { [Console]::CursorVisible = $true }
}

# Font info panel (fonts can't be rendered live - the terminal uses one font for
# the whole window - so we show the name + how to install/apply it).
function Show-PoshPaletteFontInfo {
    param($Font, [int] $Left = 42, [int] $Top = 4)
    $bw = try { [Console]::BufferWidth } catch { 120 }
    if ($bw -lt ($Left + 30)) { return }
    $dim = "$e[38;5;245m"; $wht = "$e[97m"; $rst = "$e[0m"
    $name = if ($Font.Custom) { $Font.Name } else { $Font.name }
    $face = if ($Font.face) { $Font.face } else { $name }
    $id   = if ($Font.Custom) { '<face name>' } else { $Font.id }
    $lines = @(
        "${wht}Font${rst}"
        ''
        "${wht}$name${rst}"
        "${dim}face: $face${rst}"
        ''
        "${dim}A font can't be shown here - the${rst}"
        "${dim}terminal renders one font for the${rst}"
        "${dim}whole window.${rst}"
        ''
        "${dim}Install a bundled one:${rst}"
        "${dim}  Install-PoshPaletteFont $id${rst}"
        "${dim}then pick it as your terminal font.${rst}"
    )
    [Console]::CursorVisible = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        try { [Console]::SetCursorPosition($Left, $Top + $i); [Console]::Write($lines[$i]) } catch { }
    }
    [Console]::Write($rst)
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

# Preview callback for the font picker: show the font info panel.
function New-PoshPaletteFontPreviewFor {
    { param($it) Show-PoshPaletteFontInfo -Font $it }
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
                $p = Show-PoshPaletteList -Title 'Prompt (oh-my-posh)' -Items (Get-PoshPaletteCatalog prompts) `
                    -PreviewFor (New-PoshPalettePreviewFor $comp 'prompt') `
                    -CustomPrompt 'Type an oh-my-posh theme name (e.g. atomic, jandedobbeleer):'
                if ($p) { $comp.prompt = $p.Id }
            }
            'font' {
                # A font can't be rendered live; show its name + install hint, and
                # allow typing any installed font face directly.
                $p = Show-PoshPaletteList -Title 'Font' -Items (Get-PoshPaletteFonts) `
                    -PreviewFor (New-PoshPaletteFontPreviewFor) `
                    -CustomPrompt 'Type an installed font face (e.g. Cascadia Code NF):'
                if ($p) { $comp.font = $p.Id }
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
