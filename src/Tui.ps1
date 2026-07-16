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

# A short, scheme-colored representation of the theme's prompt, as flat hex,text
# pairs. We draw it ourselves (rather than invoking oh-my-posh) so it stays inside
# the preview block on every terminal: a real oh-my-posh prompt is full-width, can
# carry powerline backgrounds, and uses glyphs that mangle when captured. The
# generated 'auto-*' prompts are drawn to match their real layout; a referenced
# theme gets a clean generic prompt (its true shape only shows once applied).
function Get-PoshPalettePromptParts {
    param($Theme)
    $sc = $Theme.terminal.scheme
    if ($Theme.prompt.generated) {
        switch -Wildcard ($Theme.prompt.name) {
            '*minimal*'   { return @($sc.purple, '❯ ') }
            '*twoline*'   { return @($sc.cyan, '╭─ ', $sc.blue, 'C:\proj\ccbit ', $sc.green, '● main ', $sc.yellow, '12:27 ', $sc.cyan, '╰─', $sc.purple, '❯ ') }
            '*clean*'     { return @($sc.cyan, '╭─ ', $sc.yellow, '♥ 12:27 | ', $sc.blue, 'C:\proj\ccbit ', $sc.green, '● main ', $sc.purple, '╰─ ') }
            '*cert*'      { return @($sc.red, ' user ', $sc.green, ' C:\proj\ccbit ', $sc.cyan, ' git(main) ', $sc.purple, ' 12:27 ') }
            '*velvet*'    { return @($sc.blue, ' C:\proj\ccbit ', $sc.cyan, ' main ', $sc.yellow, ' 12ms ', $sc.green, ' ✓ ', $sc.purple, ' 12:27 ') }
            '*powerline*' { return @($sc.blue, ' C:\proj\ccbit ', $sc.green, ' main ', $sc.cyan, ' ✓ ') }
            '*robby*'     { return @($sc.cyan, '❯❯ ', $sc.blue, 'C:\proj\ccbit ', $sc.green, 'git:(main) ', $sc.yellow, '18:50 ') }
            '*arrow*'     { return @($sc.blue, 'C:\proj\ccbit ', $sc.cyan, 'on ', $sc.green, '● main ', $sc.yellow, '12:27 ', $sc.purple, '❯ ') }
            '*lambda*'    { return @($sc.purple, 'λ ', $sc.blue, 'C:\proj\ccbit ', $sc.green, '→ ') }
            '*spaceship*' { return @($sc.blue, 'C:\proj\ccbit ', $sc.cyan, 'on ', $sc.purple, '⎇ main ', $sc.yellow, '12:27 ', $sc.green, '➜ ') }
            '*atomic*'    { return @($sc.purple, '⚡ ', $sc.blue, ' C:\proj\ccbit ', $sc.green, ' main ', $sc.purple, ' ❯ ') }
            '*smoothie*'  { return @($sc.purple, ' C:\proj\ccbit ', $sc.cyan, ' main ', $sc.purple, ' ❯ ') }
            '*pure*'      { return @($sc.blue, 'C:\proj\ccbit ', $sc.purple, '❯ ') }
            # 1_shell: session + time + git with status counts, plus its sysinfo (MEM).
            '*1shell*'    { return @($sc.yellow, 'user ', $sc.foreground, 'on ', $sc.purple, 'Mon 3:04 PM ', $sc.cyan, '⎇ main ', $sc.green, '↑1 ✚2 ', $sc.brightBlack, 'MEM 38% ', $sc.purple, '❯ ') }
            # avit: path + branch only (its config has no versions/cloud).
            '*avit*'      { return @($sc.blue, 'C:\proj\ccbit ', $sc.yellow, 'main ', $sc.cyan, '➜ ') }
            # darkblood: framed user + branch only (no extra segments in its config).
            '*darkblood*' { return @($sc.red, '┏[', $null, 'user', $sc.red, '] [', $null, 'main', $sc.red, '] ', $sc.red, '> ') }
            # tokyonight_storm: path + branch, plus its language-version block.
            '*tokyonight*'{ return @($sc.blue, '➜ ', $sc.purple, 'C:\proj\ccbit ', $sc.cyan, '(main) ', $sc.green, 'node 22.1 ', $sc.yellow, 'py 3.12 ', $sc.cyan, 'go 1.22 ') }
            # dracula: session + path + branch + node version + time + aws cloud cap.
            '*dracula*'   { return @($sc.cyan, 'user ', $sc.blue, 'C:\proj\ccbit ', $sc.purple, '⎇ main ', $sc.cyan, 'node 22.1 ', $sc.yellow, '12:27 ', $sc.green, 'aws default ') }
            # snoot: bespoke info line (cloud + date | path + git branch), then a dog + bone prompt.
            '*snoot*'     { return @($sc.red, "$([char]0xF0C2)  ", $sc.foreground, '16/07 Thu 12:27 | ', $sc.red, 'C:\proj\ccbit ', $sc.purple, "$([char]0xF418) main ", $sc.red, "$([char]0xEEF7) $([char]0xEE9A) ") }
            default       { return @($sc.blue, 'C:\proj\ccbit ', $sc.green, 'main ', $sc.purple, '❯ ') }
        }
    }
    @($sc.cyan, '❯❯ ', $sc.blue, 'C:\proj\ccbit ', $sc.green, 'git:(main) ')
}

# A mini terminal session drawn from the theme's own hex values on a filled block
# of the theme's BACKGROUND color, so the whole thing recolors as you scroll. It
# shows a representative prompt plus a few commands + output, all theme-colored.
function Show-PoshPalettePreview {
    param($Theme, [int] $Left = 42, [int] $Top = 4)
    $bw = try { [Console]::BufferWidth } catch { 120 }
    # Use the room available, up to a comfortable shell width, so the preview reads
    # like a real terminal window instead of a cramped strip.
    $W = [Math]::Min(74, $bw - $Left - 2)
    if ($W -lt 40) { return }   # not enough room for a usable side panel; skip cleanly

    $sc = $Theme.terminal.scheme
    $pr = $Theme.psReadLine
    $ps = $Theme.psStyle
    $rgb = { param($h) ConvertTo-PPRgb $h }
    $bg  = & $rgb $sc.background

    # Plain colored line from flat hex,text,hex,text... pairs, padded on the bg.
    $row = {
        param([object[]] $parts)
        $s = "$e[48;2;${bg}m"; $len = 0
        for ($j = 0; $j -lt $parts.Count -and $len -lt $W; $j += 2) {
            $hex = $parts[$j]; if (-not $hex) { $hex = $sc.foreground }
            $txt = '' + $parts[$j + 1]
            if ($len + $txt.Length -gt $W) { $txt = $txt.Substring(0, $W - $len) }   # clip to panel
            $s += "$e[38;2;$(& $rgb $hex)m$txt"
            $len += $txt.Length
        }
        if ($len -lt $W) { $s += (' ' * ($W - $len)) }
        $s + "$e[0m"
    }

    # Window chrome: a titlebar one shade off the background, with traffic lights, so
    # the preview reads as a terminal window rather than loose colored text on a block.
    $blendHex = {
        param($a, $b, $t)
        $a = $a.TrimStart('#'); $b = $b.TrimStart('#')
        $m = { param($i) [int]([Convert]::ToInt32($a.Substring($i, 2), 16) + ([Convert]::ToInt32($b.Substring($i, 2), 16) - [Convert]::ToInt32($a.Substring($i, 2), 16)) * $t) }
        '#{0:X2}{1:X2}{2:X2}' -f (& $m 0), (& $m 2), (& $m 4)
    }
    $chrome   = & $rgb (& $blendHex $sc.background $sc.foreground 0.14)
    $titleHex = & $blendHex $sc.background $sc.foreground 0.5
    $crow = {
        param([object[]] $parts)
        $s = "$e[48;2;${chrome}m"; $len = 0
        for ($j = 0; $j -lt $parts.Count -and $len -lt $W; $j += 2) {
            $hex = $parts[$j]; if (-not $hex) { $hex = $sc.foreground }
            $txt = '' + $parts[$j + 1]
            if ($len + $txt.Length -gt $W) { $txt = $txt.Substring(0, $W - $len) }
            $s += "$e[38;2;$(& $rgb $hex)m$txt"
            $len += $txt.Length
        }
        if ($len -lt $W) { $s += (' ' * ($W - $len)) }
        $s + "$e[0m"
    }
    $titlebar = & $crow @($titleHex, ' ', '#FF5F56', '● ', '#FFBD2E', '● ', '#27C93F', '● ', $titleHex, '  ~/dev/posh-palette')

    # The prompt is drawn from the theme's own segments; render it (plus a typed
    # command) through $row so it clips to the panel width instead of overflowing.
    $promptParts = Get-PoshPalettePromptParts $Theme
    $prow = {
        param($cmdHex, $cmdText)
        if (-not $cmdHex) { $cmdHex = $sc.foreground }
        & $row (@($sc.foreground, ' ') + $promptParts + @($cmdHex, $cmdText))
    }

    $lines = @(
        $titlebar
        (& $prow $pr.Command 'Get-ChildItem')
        (& $row  @($null, ''))
        (& $row  @($ps.TableHeader, 'Mode    LastWriteTime      Length Name'))
        (& $row  @($pr.Comment,     '----    -------------      ------ ----'))
        (& $row  @($null, 'd----   6/20/2026  9:39 AM        ', $ps.Directory, 'src'))
        (& $row  @($null, '-a---   6/18/2026  1:12 PM   ', $pr.Number, '1.4k', $pr.Command, ' build.ps1'))
        (& $row  @($null, '-a---   6/18/2026  1:12 PM   ', $pr.Number, '2.1k', $pr.Variable, ' config.json'))
        (& $row  @($null, '-a---   6/18/2026  1:12 PM   ', $pr.Number, '8.9k', $pr.Parameter, ' README.md'))
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
    param([string] $Title, [array] $Items, [scriptblock] $PreviewFor, [string] $CustomPrompt, [string] $Current)

    $hasCustom = [bool]$CustomPrompt
    $customIdx = if ($hasCustom) { $Items.Count } else { -1 }
    $backIdx   = $Items.Count + $(if ($hasCustom) { 1 } else { 0 })
    $total     = $backIdx + 1
    $extra     = if ($hasCustom) { @('⌨ Type a name...', '← Back') } else { @('← Back') }
    $rows      = @($Items | ForEach-Object { $_.Name }) + $extra   # items, then Type-a-name / Back
    $width     = [Math]::Max((Get-PPMaxLen $rows), 16)
    # Start the cursor on the currently-selected item so opening a picker lands on
    # what you're already using, not the top of the list.
    $idx       = 0; $winTop = 0
    if ($Current) {
        for ($i = 0; $i -lt $Items.Count; $i++) {
            if ($Items[$i].Id -eq $Current) { $idx = $i; break }
        }
    }
    [Console]::CursorVisible = $false
    try {
        while ($true) {
            # Scroll window so long catalogs (35+ entries) don't push the title off
            # a short terminal. Keep the selection visible.
            $wh = try { [Console]::WindowHeight } catch { 30 }
            $maxRows = [Math]::Max(3, $wh - 7)
            if ($total -le $maxRows) { $winTop = 0 }
            elseif ($idx -lt $winTop) { $winTop = $idx }
            elseif ($idx -ge $winTop + $maxRows) { $winTop = $idx - $maxRows + 1 }
            if ($winTop -gt [Math]::Max(0, $total - $maxRows)) { $winTop = [Math]::Max(0, $total - $maxRows) }
            $winEnd = [Math]::Min($total, $winTop + $maxRows)

            Clear-Host
            Write-Host ""
            Write-Host "  $Title" -ForegroundColor White -NoNewline
            if ($total -gt $maxRows) { Write-Host "   ($($idx + 1)/$total)" -ForegroundColor DarkGray -NoNewline }
            Write-Host ""
            Write-PPRule
            Write-Host ""
            for ($i = $winTop; $i -lt $winEnd; $i++) {
                Write-PPRow ($i -eq $idx) $rows[$i] $width
            }
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
    Write-Host "  ✓ " -ForegroundColor Green -NoNewline
    Write-Host "Applied $($Theme.name)" -ForegroundColor White
    Write-PPRule
    Write-Host ""
    Write-Host "  Terminal colors changed in this window right away." -ForegroundColor Gray
    Write-Host "  Open a new tab to load the prompt and input colors." -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Change one layer anytime:" -ForegroundColor DarkGray
    Write-Host "    Set-PoshPaletteScheme  <name>" -ForegroundColor Cyan
    Write-Host "    Set-PoshPalettePrompt  <name>" -ForegroundColor Cyan
    Write-Host "    Set-PoshPaletteFont    <name>" -ForegroundColor Cyan
    Write-PPFooter @('Enter  back to menu', 'Q  quit')
    while ($true) {
        $k = [Console]::ReadKey($true)
        if ($k.Key -eq 'Enter' -or $k.Key -eq 'Escape') { return $null }
        if ([string]$k.KeyChar -in 'q', 'Q')            { return 'quit' }
    }
}

# Reset everything to the stock default look, then confirm. Returns 'quit'/$null.
function Invoke-PoshPaletteReset {
    Clear-Host
    Reset-PoshPalette -Quiet
    Write-Host ""
    Write-Host "  ✓ " -ForegroundColor Green -NoNewline
    Write-Host "Reset to the default look" -ForegroundColor White
    Write-PPRule
    Write-Host ""
    Write-Host "  Terminal is back to Campbell + Cascadia Mono." -ForegroundColor Gray
    Write-Host "  Open a new tab to see the default prompt." -ForegroundColor Gray
    Write-Host "  Then pick a theme to show the before/after." -ForegroundColor Gray
    Write-PPFooter @('Enter  back to menu', 'Q  quit')
    while ($true) {
        $k = [Console]::ReadKey($true)
        if ($k.Key -eq 'Enter' -or $k.Key -eq 'Escape') { return $null }
        if ([string]$k.KeyChar -in 'q', 'Q')            { return 'quit' }
    }
}

# Update the module from the PowerShell Gallery, then confirm. Returns 'quit'/$null.
function Invoke-PoshPaletteUpdate {
    Clear-Host
    Write-Host "`n  Updating PoshPalette from the PowerShell Gallery…" -ForegroundColor Cyan
    $ok = $false
    try {
        Update-Module PoshPalette -ErrorAction Stop
        $ok = $true
    } catch {
        Write-Host "`n  Couldn't update automatically: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "  Run this yourself, then reopen PowerShell:" -ForegroundColor Gray
        Write-Host "    Update-Module PoshPalette" -ForegroundColor Cyan
    }
    if ($ok) {
        Write-Host ""
        Write-Host "  ✓ " -ForegroundColor Green -NoNewline
        Write-Host "Updated." -ForegroundColor White
        Write-PPRule
        Write-Host ""
        Write-Host "  Open a new PowerShell tab to load the new version." -ForegroundColor Gray
    }
    Write-PPFooter @('Enter  back to menu', 'Q  quit')
    while ($true) {
        $k = [Console]::ReadKey($true)
        if ($k.Key -eq 'Enter' -or $k.Key -eq 'Escape') { return $null }
        if ([string]$k.KeyChar -in 'q', 'Q')            { return 'quit' }
    }
}

# Perceived-luminance test on a "#rrggbb" background: is it a dark theme? Used to
# tag each theme dark/light for the Simple-mode filter (matches the site's split).
function Test-PoshPaletteDarkHex {
    param([string] $Hex)
    if (-not $Hex -or $Hex.Length -lt 7) { return $true }
    $r = [convert]::ToInt32($Hex.Substring(1,2),16)
    $g = [convert]::ToInt32($Hex.Substring(3,2),16)
    $b = [convert]::ToInt32($Hex.Substring(5,2),16)
    (((0.2126 * $r) + (0.7152 * $g) + (0.0722 * $b)) / 255) -lt 0.5
}

# Simple-mode theme picker with type-to-search + a dark/light filter. The list is
# focused by default (arrows move, Enter applies). Just start typing to live-filter
# by name; Tab cycles All -> Dark -> Light; Backspace edits; Esc clears the query
# (or backs out when it's already empty). Returns the chosen theme item or $null.
function Show-PoshPaletteThemePicker {
    param([array] $Themes)

    # Precompute dark/light once from each theme's scheme background.
    $entries = foreach ($t in $Themes) {
        $bg = (Get-PoshPaletteCatalogItem -Kind 'schemes' -Id $t.Data.scheme).colors.background
        [pscustomobject]@{ Item = $t; Name = $t.Name; Id = $t.Id; Dark = (Test-PoshPaletteDarkHex $bg) }
    }

    $query = ''; $filter = 'all'; $idx = 0; $winTop = 0
    $nextFilter = @{ all = 'dark'; dark = 'light'; light = 'all' }
    [Console]::CursorVisible = $false
    try {
        while ($true) {
            $q = $query.ToLower()
            $view = @($entries | Where-Object {
                ($filter -eq 'all' -or ($filter -eq 'dark' -and $_.Dark) -or ($filter -eq 'light' -and -not $_.Dark)) -and
                ($q -eq '' -or $_.Name.ToLower().Contains($q) -or $_.Id.ToLower().Contains($q))
            })
            if ($idx -ge $view.Count) { $idx = [Math]::Max(0, $view.Count - 1) }

            # Scroll window: only render as many rows as fit, so the header/search
            # bar stays pinned on short terminals. Keep the selection in view.
            $wh = try { [Console]::WindowHeight } catch { 30 }
            $maxRows = [Math]::Max(3, $wh - 8)        # header (5) + footer (~3)
            if ($view.Count -le $maxRows) { $winTop = 0 }
            elseif ($idx -lt $winTop) { $winTop = $idx }
            elseif ($idx -ge $winTop + $maxRows) { $winTop = $idx - $maxRows + 1 }
            if ($winTop -gt [Math]::Max(0, $view.Count - $maxRows)) { $winTop = [Math]::Max(0, $view.Count - $maxRows) }
            $winEnd = [Math]::Min($view.Count, $winTop + $maxRows)

            Clear-Host
            Write-Host ""
            Write-Host "  Simple mode - pick a theme" -ForegroundColor White
            Write-Host "  Search: " -ForegroundColor DarkGray -NoNewline
            Write-Host ($query + [char]0x2588) -ForegroundColor White -NoNewline
            Write-Host "   Filter: " -ForegroundColor DarkGray -NoNewline
            foreach ($f in @('all', 'dark', 'light')) {
                $lbl = $f.Substring(0, 1).ToUpper() + $f.Substring(1)
                if ($f -eq $filter) { Write-Host " $lbl " -ForegroundColor Black -BackgroundColor Gray -NoNewline; Write-Host ' ' -NoNewline }
                else { Write-Host "$lbl " -ForegroundColor DarkGray -NoNewline }
            }
            if ($view.Count -gt $maxRows) { Write-Host "  ($($idx + 1)/$($view.Count))" -ForegroundColor DarkGray -NoNewline }
            Write-Host ""
            Write-PPRule
            Write-Host ""
            if ($view.Count -eq 0) {
                Write-Host "     no themes match" -ForegroundColor DarkGray
            } else {
                $width = [Math]::Max((Get-PPMaxLen ($view | ForEach-Object { $_.Name })), 16)
                for ($i = $winTop; $i -lt $winEnd; $i++) { Write-PPRow ($i -eq $idx) $view[$i].Name $width }
            }
            Write-PPFooter @('type to search', 'Tab filter', "$([char]0x2191)/$([char]0x2193) move", 'Enter apply', 'Esc back')
            if ($view.Count -gt 0) { Show-PoshPalettePreview -Theme (Resolve-PoshPaletteTheme $view[$idx].Item.Data) -Top 5 }

            $key = [Console]::ReadKey($true)
            switch ($key.Key) {
                'UpArrow'   { if ($view.Count) { $idx = ($idx - 1 + $view.Count) % $view.Count } }
                'DownArrow' { if ($view.Count) { $idx = ($idx + 1) % $view.Count } }
                'Enter'     { if ($view.Count) { return $view[$idx].Item } }
                'Tab'       { $filter = $nextFilter[$filter]; $idx = 0 }
                'Backspace' { if ($query.Length) { $query = $query.Substring(0, $query.Length - 1); $idx = 0 } }
                'Escape'    { if ($query.Length) { $query = ''; $idx = 0 } else { return $null } }
                default {
                    # Any printable character extends the search query.
                    $ch = $key.KeyChar
                    if ([int]$ch -ge 32 -and [int]$ch -ne 127) { $query += $ch; $idx = 0 }
                }
            }
        }
    } finally { [Console]::CursorVisible = $true }
}

function Invoke-PoshPaletteSimpleMode {
    $themes = Get-PoshPaletteThemes
    $chosen = Show-PoshPaletteThemePicker -Themes $themes
    if ($chosen) {
        Clear-Host
        $t = Resolve-PoshPaletteTheme $chosen.Data
        Set-PoshPaletteTheme -Theme $t -Quiet
        # Remember what's active so later per-layer tweaks build on THIS theme
        # (without this, Set-PoshPalette* falls back to the first bundled theme).
        Save-PoshPaletteCurrentComposition (ConvertTo-PoshPaletteHashtable $chosen.Data)
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

    # Seed from the currently-applied composition so tweaking a single layer (e.g.
    # the font) keeps the rest of your look. Falls back to the first bundled theme
    # the first time, before anything has been applied.
    $base = Get-PoshPaletteCurrentComposition

    # Working composition as a mutable hashtable.
    $comp = @{
        name     = $base.name ?? 'Custom'
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
                $p = Show-PoshPaletteList -Title 'Color scheme' -Items (Get-PoshPaletteCatalog schemes) -PreviewFor (New-PoshPalettePreviewFor $comp 'scheme') -Current $comp.scheme
                if ($p) { $comp.scheme = $p.Id }
            }
            'palette' {
                $p = Show-PoshPaletteList -Title 'Shell colors (PSReadLine + output)' -Items (Get-PoshPaletteCatalog palettes) -PreviewFor (New-PoshPalettePreviewFor $comp 'palette') -Current $comp.palette
                if ($p) { $comp.palette = $p.Id }
            }
            'prompt' {
                $p = Show-PoshPaletteList -Title 'Prompt (oh-my-posh)' -Items (Get-PoshPaletteCatalog prompts) `
                    -PreviewFor (New-PoshPalettePreviewFor $comp 'prompt') `
                    -CustomPrompt 'Type an oh-my-posh theme name (e.g. atomic, jandedobbeleer):' -Current $comp.prompt
                if ($p) { $comp.prompt = $p.Id }
            }
            'font' {
                # A font can't be rendered live; show its name + install hint, and
                # allow typing any installed font face directly.
                $p = Show-PoshPaletteList -Title 'Font' -Items (Get-PoshPaletteFonts) `
                    -PreviewFor (New-PoshPaletteFontPreviewFor) `
                    -CustomPrompt 'Type an installed font face (e.g. Cascadia Code NF):' -Current $comp.font
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
                Set-PoshPaletteTheme -Theme $t -Quiet
                # Persist the composition so per-layer tweaks build on it afterwards.
                Save-PoshPaletteCurrentComposition $comp
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
    param([switch] $Refresh)

    # Pull any new community themes from GitHub before showing the menu. This is
    # throttled (once/24h), time-boxed, and best-effort, so it's instant on the
    # common path and never blocks when offline. -Refresh forces it now.
    $script:PPNewThemes = 0
    try {
        Clear-Host
        Write-Host "`n  Checking for new themes…" -ForegroundColor DarkGray
        $script:PPNewThemes = Update-PoshPaletteCatalog -Force:$Refresh
    } catch { $script:PPNewThemes = 0 }

    $items = @(
        @{ Key = '1'; Title = 'Simple mode'; Desc = 'Pick a full theme from a scrollable list';   Run = { Invoke-PoshPaletteSimpleMode } }
        @{ Key = '2'; Title = 'Detail mode'; Desc = 'Compose scheme, colors, prompt, font';        Run = { Invoke-PoshPaletteDetailMode } }
        @{ Key = '3'; Title = 'Doctor';      Desc = 'Check fonts, oh-my-posh, terminal';           Run = { Clear-Host; Test-PoshPaletteSetup | Out-Null; Write-Host "`n  [Enter] back to menu" -ForegroundColor DarkGray; [Console]::ReadKey($true) | Out-Null } }
        @{ Key = '4'; Title = 'Reset';       Desc = 'Back to the default look (for before/after)'; Run = { Invoke-PoshPaletteReset } }
    )
    # Offer an Update item only when a newer version is on the Gallery (detected on
    # the same daily cadence as the theme refresh, read back from cache here).
    $updateVer = try { Get-PoshPaletteUpdateAvailable } catch { $null }
    if ($updateVer) {
        $items += @{ Key = '5'; Title = 'Update'; Desc = "New version $updateVer available. Select to Update."; Run = { Invoke-PoshPaletteUpdate } }
    }
    $items += @{ Key = 'Q'; Title = 'Quit'; Desc = 'Exit Posh Palette'; Run = { 'quit' } }
    $titleW = Get-PPMaxLen ($items | ForEach-Object { $_.Title })
    $texts  = $items | ForEach-Object { "[$($_.Key)] " + $_.Title.PadRight($titleW) + '   ' + $_.Desc }
    $rowW   = Get-PPMaxLen $texts
    $idx = 0
    # The preview writes via [Console]::Write, which encodes through
    # [Console]::OutputEncoding - a legacy code page on Windows, so glyphs like
    # ❯ ✓ ✗ collapse to '?'. Switch to UTF-8 for the session, restored on exit.
    $prevEnc = [Console]::OutputEncoding
    try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch { }
    [Console]::CursorVisible = $false
    try {
        while ($true) {
            Clear-Host
            Write-Host ""
            Write-Host "  >_  " -ForegroundColor White -NoNewline
            Write-Host "Posh Palette" -ForegroundColor White
            Write-PPRule
            Write-Host "  Style all 4 layers: scheme · PSReadLine · `$PSStyle · prompt" -ForegroundColor DarkGray
            if ($script:PPNewThemes -gt 0) {
                $s = if ($script:PPNewThemes -eq 1) { '' } else { 's' }
                Write-Host "  + $($script:PPNewThemes) new community theme$s from GitHub" -ForegroundColor Green
            }
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
    } finally {
        [Console]::CursorVisible = $true
        try { [Console]::OutputEncoding = $prevEnc } catch { }
    }
}
