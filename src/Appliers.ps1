# Appliers.ps1 - write theme into the 4 layers.
#   Layer 1  Windows Terminal   -> settings.json (hot-reloads instantly)
#   Layer 2  PSReadLine          -> $PROFILE managed block + live session
#   Layer 3  $PSStyle output     -> $PROFILE managed block + live session
#   Layer 4  oh-my-posh prompt   -> $PROFILE managed block + live session

$script:BlockStart = '# >>> PoshPalette >>>'
$script:BlockEnd   = '# <<< PoshPalette <<<'

# --- Layer 1: Windows Terminal ------------------------------------------------

function Get-WindowsTerminalSettingsPath {
    if (-not $IsWindows -and $PSVersionTable.PSEdition -ne 'Desktop') { return $null }
    $candidates = @(
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json",
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json",
        "$env:APPDATA\Microsoft\Windows Terminal\settings.json"  # unpackaged / scoop
    )
    $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}

function Backup-PoshPaletteFile {
    param([string] $Path)
    if ($Path -and (Test-Path $Path)) {
        $stamp  = (Get-Date -Format 'yyyyMMdd-HHmmss')
        $backup = "$Path.poshpalette-$stamp.bak"
        Copy-Item $Path $backup -Force
        return $backup
    }
}

# Build the hashtable we upsert into settings.schemes / settings.profiles.defaults.
function Get-PoshPaletteTerminalEdits {
    param($Theme)
    $scheme = @{}
    $Theme.terminal.scheme.psobject.Properties | ForEach-Object { $scheme[$_.Name] = $_.Value }
    if (-not $scheme['name']) { $scheme['name'] = $Theme.name }
    @{
        SchemeName = $scheme['name']
        Scheme     = $scheme
        Defaults   = [ordered]@{
            colorScheme = $scheme['name']
            opacity     = $Theme.terminal.opacity
            useAcrylic  = [bool]$Theme.terminal.useAcrylic
            font        = [ordered]@{ face = $Theme.terminal.font; size = $Theme.terminal.fontSize }
        }
    }
}

# Menu (up/down + Enter) asking whether to install a missing font.
# Returns 'Install' or 'Keep'.
function Show-PoshPaletteFontInstallMenu {
    param([Parameter(Mandatory)][string] $Face)
    $options = @(
        [pscustomobject]@{ Action = 'Install'; Title = "Install '$Face' now"
            Desc = 'Download and install it (per-user, no admin), then set it as your font.' }
        [pscustomobject]@{ Action = 'Keep'; Title = 'Keep my current font'
            Desc = 'Apply the theme but leave the terminal font as it is.' }
    )
    $header = {
        Write-Host "  This theme uses '$Face', which isn't installed." -ForegroundColor Yellow
        Write-Host ""
    }.GetNewClosure()
    Show-PoshPaletteChoice -Options $options -RenderHeader $header
}

# When a theme's font isn't installed, offer to install it in-session (per-user,
# no admin) and keep it. Returns $true if the font is available afterwards (so the
# caller applies it), $false to fall back to the current terminal font.
function Confirm-PoshPaletteFontInstall {
    param([Parameter(Mandatory)][string] $Face)

    # Non-Windows can't read the font registry, so Test-* returns $true there and
    # we never reach this; on Windows, bail early if it's already present.
    if (Test-PoshPaletteFontInstalled $Face) { return $true }

    # Need the catalog id to know which Nerd Font asset to fetch.
    $fontId = (Get-PoshPaletteFonts | Where-Object { $_.face -eq $Face -or $_.name -eq $Face } | Select-Object -First 1).id

    $interactive = [Environment]::UserInteractive -and -not [Console]::IsInputRedirected
    if (-not $interactive -or -not $fontId) {
        Write-Host "  Font '$Face' is not installed - keeping your current terminal font." -ForegroundColor Yellow
        if ($fontId) { Write-Host "  Install it with:  Install-PoshPaletteFont $fontId" -ForegroundColor DarkGray }
        else { Write-Host "  Install a matching Nerd Font, then set it as your terminal font." -ForegroundColor DarkGray }
        return $false
    }

    $choice = Show-PoshPaletteFontInstallMenu -Face $Face
    if ($choice -ne 'Install') {
        Write-Host "  Keeping your current terminal font. Install later with:  Install-PoshPaletteFont $fontId" -ForegroundColor DarkGray
        return $false
    }

    try {
        Install-PoshPaletteFont $fontId
    } catch {
        Write-Host "  Font install failed: $_" -ForegroundColor Red
        Write-Host "  Keeping your current terminal font." -ForegroundColor DarkGray
        return $false
    }

    if (Test-PoshPaletteFontInstalled $Face) {
        Write-Host "  '$Face' installed and set as your terminal font." -ForegroundColor Green
    } else {
        # Files copied but the registry hasn't caught up yet (rare). Apply anyway -
        # Windows Terminal will pick it up, worst case after a restart.
        Write-Host "  '$Face' installed and set. Restart the terminal if glyphs look off." -ForegroundColor Yellow
    }
    return $true
}

# Comment-preserving write: edit only the spans that change, so the user's
# comments, key order, and formatting survive. Falls back to a parse->reserialize
# round-trip if the file is too irregular to edit surgically.
function Set-PoshPaletteTerminalLayer {
    param($Theme, [string] $SettingsPath, [switch] $DryRun)

    $edits      = Get-PoshPaletteTerminalEdits $Theme
    $schemeName = $edits.SchemeName

    # Don't set a font that isn't installed - that's what makes Windows Terminal
    # pop the "Unable to find the following fonts" warning. Offer to install it
    # in-session; if the user declines (or it's unavailable), keep their font.
    $face = $edits.Defaults.font.face
    if ($face -and -not (Test-PoshPaletteFontInstalled $face)) {
        if ($DryRun) {
            $fontId = (Get-PoshPaletteFonts | Where-Object { $_.face -eq $face -or $_.name -eq $face } | Select-Object -First 1).id
            $hint = if ($fontId) { " (would offer to install '$fontId')" } else { '' }
            Write-Host "  [dry-run] Font '$face' is not installed$hint." -ForegroundColor DarkGray
            $edits.Defaults.Remove('font')
        } elseif (-not (Confirm-PoshPaletteFontInstall $face)) {
            $edits.Defaults.Remove('font')
        }
    }

    if ($DryRun) {
        Write-Host "  [dry-run] would write Terminal scheme '$($Theme.name)' to $SettingsPath" -ForegroundColor DarkGray
        return
    }

    $text = Get-Content $SettingsPath -Raw
    $wrote = $false
    try {
        $rootOpen = $text.IndexOf('{')
        if ($rootOpen -lt 0) { throw 'no root object' }

        # profiles.defaults.{colorScheme,opacity,useAcrylic,font}
        $prof = Find-JsoncMember $text $rootOpen 'profiles'
        if (-not $prof) {
            $text = Set-JsoncMember $text $rootOpen 'profiles' '{ "defaults": {} }'
            $prof = Find-JsoncMember $text $rootOpen 'profiles'
        }
        $profOpen = $text.IndexOf('{', $prof.ValueStart)
        $defM = Find-JsoncMember $text $profOpen 'defaults'
        if (-not $defM) {
            $text = Set-JsoncMember $text $profOpen 'defaults' '{}'
            $defM = Find-JsoncMember $text $profOpen 'defaults'
        }
        $defOpen = $text.IndexOf('{', $defM.ValueStart)
        $text = Set-JsoncMember $text $defOpen 'colorScheme' ('"' + $schemeName + '"')
        $defOpen = $text.IndexOf('{', (Find-JsoncMember $text $profOpen 'defaults').ValueStart)
        $text = Set-JsoncMember $text $defOpen 'opacity' ([string]$edits.Defaults.opacity)
        $defOpen = $text.IndexOf('{', (Find-JsoncMember $text $profOpen 'defaults').ValueStart)
        $text = Set-JsoncMember $text $defOpen 'useAcrylic' ($edits.Defaults.useAcrylic.ToString().ToLower())
        if ($edits.Defaults.Contains('font')) {
            $defOpen = $text.IndexOf('{', (Find-JsoncMember $text $profOpen 'defaults').ValueStart)
            $fontJson = ($edits.Defaults.font | ConvertTo-Json -Depth 5 -Compress)
            $text = Set-JsoncMember $text $defOpen 'font' $fontJson
        }

        # schemes[] upsert by name
        $rootOpen = $text.IndexOf('{')
        $schM = Find-JsoncMember $text $rootOpen 'schemes'
        if (-not $schM) {
            $text = Set-JsoncMember $text $rootOpen 'schemes' '[]'
            $schM = Find-JsoncMember $text $rootOpen 'schemes'
        }
        $arrOpen = $text.IndexOf('[', $schM.ValueStart)
        $schemeJson = ($edits.Scheme | ConvertTo-Json -Depth 5)
        $text = Set-JsoncArrayItemByName $text $arrOpen $schemeName $schemeJson

        # validate before committing; if it doesn't parse, fall back
        $null = ConvertFrom-Jsonc $text
        Set-Content -Path $SettingsPath -Value $text -Encoding utf8
        $wrote = $true
    } catch {
        Write-Verbose "Surgical JSONC edit failed ($_); falling back to round-trip."
    }

    if (-not $wrote) {
        $settings = ConvertFrom-Jsonc (Get-Content $SettingsPath -Raw) -AsHashtable
        if (-not $settings.schemes) { $settings.schemes = @() }
        $settings.schemes = @($settings.schemes | Where-Object { $_.name -ne $schemeName }) + $edits.Scheme
        if (-not $settings.profiles)          { $settings.profiles = @{} }
        if (-not $settings.profiles.defaults) { $settings.profiles.defaults = @{} }
        $d = $settings.profiles.defaults
        $d.colorScheme = $schemeName
        $d.opacity     = $edits.Defaults.opacity
        $d.useAcrylic  = $edits.Defaults.useAcrylic
        if ($edits.Defaults.Contains('font')) { $d.font = @{ face = $edits.Defaults.font.face; size = $edits.Defaults.font.size } }
        Set-Content -Path $SettingsPath -Value ($settings | ConvertTo-Json -Depth 32) -Encoding utf8
    }
}

# --- Per-profile overrides ----------------------------------------------------
#
# PoshPalette writes the theme to profiles.defaults. A profile that sets any of
# these keys itself overrides the default, so it keeps its old look (color,
# font, opacity, acrylic) no matter which theme you apply. These helpers find
# such profiles and (on request) clear the overrides so the profile falls back
# to the theme in defaults.
$script:PPManagedProfileKeys = @('colorScheme', 'font', 'opacity', 'useAcrylic')

# Friendlier labels for the keys, shown in the menu so it's clear what changes.
function Format-PoshPaletteOverrideKeys {
    param([string[]] $Keys)
    $map = @{ colorScheme = 'color scheme'; font = 'font'; opacity = 'opacity'; useAcrylic = 'acrylic' }
    (($Keys | ForEach-Object { if ($map.ContainsKey($_)) { $map[$_] } else { $_ } })) -join ', '
}

function Get-PoshPaletteProfileOverrides {
    param([string] $SettingsPath)
    if (-not $SettingsPath -or -not (Test-Path $SettingsPath)) { return @() }
    $settings = try { ConvertFrom-Jsonc (Get-Content $SettingsPath -Raw) } catch { return @() }
    $list = $settings.profiles.list
    if (-not $list) { return @() }
    $default = $settings.defaultProfile
    @($list | ForEach-Object {
        $names = $_.psobject.Properties.Name
        $keys  = @($script:PPManagedProfileKeys | Where-Object { $names -contains $_ })
        if ($keys.Count) {
            [pscustomobject]@{
                Name      = $_.name
                Guid      = $_.guid
                Keys      = $keys
                IsDefault = ($_.guid -eq $default)
            }
        }
    })
}

# Remove every managed key from the profiles whose guids are listed. Re-reads
# offsets after each edit (removal shifts the text) and validates before writing.
function Clear-PoshPaletteProfileOverrides {
    param([string] $SettingsPath, [string[]] $Guids)
    if (-not $Guids -or -not $Guids.Count) { return }
    $text = Get-Content $SettingsPath -Raw
    foreach ($g in $Guids) {
        foreach ($key in $script:PPManagedProfileKeys) {
            $rootOpen = $text.IndexOf('{')
            $prof = Find-JsoncMember $text $rootOpen 'profiles'
            if (-not $prof) { continue }
            $profOpen = $text.IndexOf('{', $prof.ValueStart)
            $listM = Find-JsoncMember $text $profOpen 'list'
            if (-not $listM) { continue }
            $arrOpen = $text.IndexOf('[', $listM.ValueStart)
            $objOpen = Find-JsoncArrayObjectByMember $text $arrOpen 'guid' $g
            if ($objOpen -ge 0) { $text = Remove-JsoncMember $text $objOpen $key }
        }
    }
    try {
        $null = ConvertFrom-Jsonc $text
        Set-Content -Path $SettingsPath -Value $text -Encoding utf8
    } catch {
        Write-Verbose "Clearing profile overrides produced invalid JSON; leaving settings unchanged ($_)."
    }
}

# Generic up/down + Enter chooser used by every interactive confirmation, so they
# all look and behave the same (arrow keys, never typed input). $RenderHeader
# prints whatever context belongs above the list (it runs after a Clear-Host, so
# the menu owns the whole screen); $Options is an array of objects with Action and
# Title, plus an optional Desc line. Returns the chosen Action.
function Show-PoshPaletteChoice {
    param(
        [Parameter(Mandatory)] $Options,
        [scriptblock] $RenderHeader,
        [int] $Default = 0
    )
    $idx = [Math]::Max(0, [Math]::Min($Default, $Options.Count - 1))
    [Console]::CursorVisible = $false
    try {
        while ($true) {
            Clear-Host
            Write-Host ""
            if ($RenderHeader) { & $RenderHeader }
            for ($i = 0; $i -lt $Options.Count; $i++) {
                $sel = ($i -eq $idx)
                $marker = if ($sel) { '>' } else { ' ' }
                $color  = if ($sel) { 'Cyan' } else { 'Gray' }
                Write-Host ("  {0} {1}" -f $marker, $Options[$i].Title) -ForegroundColor $color
                if ($Options[$i].Desc) { Write-Host ("      {0}" -f $Options[$i].Desc) -ForegroundColor DarkGray }
            }
            Write-Host ""
            Write-Host "  up/down move   ·   Enter select" -ForegroundColor DarkGray

            $key = [Console]::ReadKey($true)
            switch ($key.Key) {
                'UpArrow'   { $idx = ($idx - 1 + $Options.Count) % $Options.Count }
                'DownArrow' { $idx = ($idx + 1) % $Options.Count }
                'Enter'     { return $Options[$idx].Action }
            }
        }
    } finally { [Console]::CursorVisible = $true }
}

# Menu shown when per-profile overrides would shadow the theme.
# Returns the chosen action: 'ThisProfile' | 'AllProfiles' | 'Keep'.
function Show-PoshPaletteOverrideMenu {
    param($Overrides, [string] $ThemeName)

    $default = $Overrides | Where-Object IsDefault | Select-Object -First 1
    $thisTitle = if ($default) { "This profile only  ($($default.Name))" } else { 'This profile only' }
    $options = @(
        [pscustomobject]@{ Action = 'ThisProfile'; Title = $thisTitle
            Desc = "Clear the overrides on your default profile so it follows '$ThemeName'." }
        [pscustomobject]@{ Action = 'AllProfiles'; Title = "All profiles ($($Overrides.Count))"
            Desc = 'Clear the overrides on every profile below so all tabs follow the theme.' }
        [pscustomobject]@{ Action = 'Keep'; Title = 'Leave them alone'
            Desc = 'Apply to defaults only; these profiles keep their look (theme may not fully apply).' }
    )

    $nameWidth = (@($Overrides | ForEach-Object { $_.Name.Length }) + 0 | Measure-Object -Maximum).Maximum
    $header = {
        Write-Host "  These Windows Terminal profiles set their own look and will partly" -ForegroundColor Yellow
        Write-Host "  ignore '$ThemeName':" -ForegroundColor Yellow
        Write-Host ""
        foreach ($o in $Overrides) {
            $tag = if ($o.IsDefault) { '  (your default)' } else { '' }
            Write-Host ("    - {0} -> {1}{2}" -f $o.Name.PadRight($nameWidth), (Format-PoshPaletteOverrideKeys $o.Keys), $tag) -ForegroundColor Gray
        }
        Write-Host ""
        Write-Host "  How should PoshPalette handle them?" -ForegroundColor White
        Write-Host ""
    }.GetNewClosure()

    Show-PoshPaletteChoice -Options $options -RenderHeader $header
}

# Decide and carry out the override handling for an apply. $Action 'Prompt' shows
# the menu when a console is attached, else falls back to 'Keep' (never edits
# profiles silently when no one can confirm).
function Resolve-PoshPaletteProfileOverrides {
    param([string] $SettingsPath, $Theme, [string] $Action, [switch] $Quiet)

    $overrides = Get-PoshPaletteProfileOverrides -SettingsPath $SettingsPath
    if (-not $overrides.Count) { return }

    $interactive = [Environment]::UserInteractive -and -not [Console]::IsInputRedirected
    if ($Action -eq 'Prompt') {
        $Action = if ($interactive) { Show-PoshPaletteOverrideMenu -Overrides $overrides -ThemeName $Theme.name } else { 'Keep' }
    }

    switch ($Action) {
        'ThisProfile' {
            $guids = @($overrides | Where-Object IsDefault | ForEach-Object Guid)
            if ($guids.Count) {
                Clear-PoshPaletteProfileOverrides -SettingsPath $SettingsPath -Guids $guids
                if (-not $Quiet) { Write-Host "  Cleared overrides on your default profile so it follows the theme." -ForegroundColor Green }
            } elseif (-not $Quiet) {
                Write-Host "  Your default profile already follows the theme; left the others as they are." -ForegroundColor DarkGray
            }
        }
        'AllProfiles' {
            Clear-PoshPaletteProfileOverrides -SettingsPath $SettingsPath -Guids @($overrides | ForEach-Object Guid)
            if (-not $Quiet) { Write-Host "  Cleared overrides on $($overrides.Count) profile(s) so all tabs follow the theme." -ForegroundColor Green }
        }
        default {
            if (-not $Quiet) {
                Write-Host "  Left per-profile overrides in place - those profiles keep their own look." -ForegroundColor DarkGray
            }
        }
    }
}

# --- Layers 2-4: the $PROFILE managed block -----------------------------------

function New-PoshPaletteProfileBlock {
    param($Theme, [switch] $DryRun)
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine($script:BlockStart)
    [void]$sb.AppendLine('# Managed by PoshPalette - edit via the app, not by hand.')

    # Layer 2: PSReadLine input colors
    [void]$sb.AppendLine('if (Get-Module -ListAvailable PSReadLine) {')
    [void]$sb.AppendLine('    Set-PSReadLineOption -Colors @{')
    foreach ($p in $Theme.psReadLine.psobject.Properties) {
        [void]$sb.AppendLine("        $($p.Name) = '$($p.Value)'")
    }
    [void]$sb.AppendLine('    }')
    [void]$sb.AppendLine('}')

    # Layer 3: $PSStyle output colors (PS 7.2+)
    [void]$sb.AppendLine('if ($PSStyle) {')
    if ($Theme.psStyle.Directory)   { [void]$sb.AppendLine("    `$PSStyle.FileInfo.Directory = `$PSStyle.Foreground.FromRgb('$($Theme.psStyle.Directory)')") }
    if ($Theme.psStyle.Error)       { [void]$sb.AppendLine("    `$PSStyle.Formatting.Error = `$PSStyle.Foreground.FromRgb('$($Theme.psStyle.Error)')") }
    if ($Theme.psStyle.TableHeader) {
        [void]$sb.AppendLine("    `$PSStyle.Formatting.TableHeader = `$PSStyle.Foreground.FromRgb('$($Theme.psStyle.TableHeader)')")
        # PS 7.4+ styles calculated column headers (e.g. Length in a dir listing)
        # with a separate green-by-default property; keep the header row uniform.
        [void]$sb.AppendLine("    if (`$PSStyle.Formatting.PSObject.Properties['CustomTableHeaderLabel']) { `$PSStyle.Formatting.CustomTableHeaderLabel = `$PSStyle.Foreground.FromRgb('$($Theme.psStyle.TableHeader)') }")
    }
    [void]$sb.AppendLine('}')

    # Layer 4: oh-my-posh prompt. A generated ('auto') prompt is written to a
    # managed config file and referenced by absolute path; a referenced theme
    # resolves against $env:POSH_THEMES_PATH at load time.
    if ($Theme.prompt.generated) {
        $cfgPath = if ($DryRun) { Join-Path $HOME '.poshpalette/prompts/pp-auto.omp.json' }
                   else { Save-PoshPalettePrompt -Config $Theme.prompt.config -Name $Theme.prompt.name }
        [void]$sb.AppendLine('if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {')
        [void]$sb.AppendLine("    oh-my-posh init pwsh --config `"$cfgPath`" | Invoke-Expression")
        [void]$sb.AppendLine('}')
    }
    elseif ($Theme.prompt.ohMyPoshTheme) {
        [void]$sb.AppendLine('if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {')
        [void]$sb.AppendLine("    oh-my-posh init pwsh --config `"`$env:POSH_THEMES_PATH\$($Theme.prompt.ohMyPoshTheme).omp.json`" | Invoke-Expression")
        [void]$sb.AppendLine('}')
    }
    [void]$sb.AppendLine($script:BlockEnd)
    $sb.ToString()
}

function Set-PoshPaletteProfileLayer {
    param($Theme, [string] $ProfilePath = $PROFILE, [switch] $DryRun)

    $block   = New-PoshPaletteProfileBlock $Theme -DryRun:$DryRun
    $existing = if (Test-Path $ProfilePath) { Get-Content $ProfilePath -Raw } else { '' }

    # Replace an existing managed block, otherwise append. Idempotent re-apply.
    $pattern = "(?s)$([regex]::Escape($script:BlockStart)).*?$([regex]::Escape($script:BlockEnd))"
    $updated = if ($existing -match $pattern) {
        [regex]::Replace($existing, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $block.TrimEnd() })
    } else {
        ($existing.TrimEnd() + "`n`n" + $block).TrimStart()
    }

    if ($DryRun) {
        Write-Host "  [dry-run] would update PoshPalette block in $ProfilePath" -ForegroundColor DarkGray
        return
    }
    $dir = Split-Path $ProfilePath -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Set-Content -Path $ProfilePath -Value $updated -Encoding utf8

    # Apply to the *current* session too, so the change is visible immediately.
    $inner = ($block -split "`n" | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
    try { . ([scriptblock]::Create($inner)) } catch { Write-Verbose "Live apply skipped: $_" }
}

# --- oh-my-posh dependency ----------------------------------------------------

# Only the prompt layer needs the oh-my-posh binary, and only when the theme
# actually drives it (a generated 'auto' prompt or a referenced community theme).
function Test-PoshPaletteThemeUsesOhMyPosh {
    param($Theme)
    [bool]($Theme.prompt -and ($Theme.prompt.generated -or $Theme.prompt.ohMyPoshTheme))
}

# If this theme's prompt needs oh-my-posh and it isn't installed, offer to install
# it (per-user via winget - no admin). The other three layers apply regardless, so
# this is always optional: declining just leaves the prompt layer dormant until the
# binary appears (the $PROFILE block is guarded with `if (Get-Command oh-my-posh)`).
function Confirm-PoshPaletteOhMyPosh {
    param($Theme)

    if (-not (Test-PoshPaletteThemeUsesOhMyPosh $Theme)) { return }
    if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) { return }

    $intro = {
        Write-Host "  This theme's prompt needs oh-my-posh, which isn't installed yet." -ForegroundColor Yellow
        Write-Host "  (Terminal colors and input/output colors still apply without it.)" -ForegroundColor DarkGray
    }

    # No winget (older Windows, non-Windows): point at the official user-scope script.
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Host ""; & $intro
        Write-Host "  Install it (no admin needed), then re-open pwsh:" -ForegroundColor Gray
        Write-Host "    Set-ExecutionPolicy Bypass -Scope Process -Force; iex ((New-Object Net.WebClient).DownloadString('https://ohmyposh.dev/install.ps1'))" -ForegroundColor Cyan
        return
    }

    # Non-interactive (CI / piped input): never block on a menu - just print it.
    if (-not ([Environment]::UserInteractive -and -not [Console]::IsInputRedirected)) {
        Write-Host ""; & $intro
        Write-Host "  Install it (no admin needed) with:" -ForegroundColor Gray
        Write-Host "    winget install JanDeDobbeleer.OhMyPosh -s winget" -ForegroundColor Cyan
        return
    }

    $choice = Show-PoshPaletteChoice -RenderHeader { & $intro; Write-Host "" }.GetNewClosure() -Options @(
        [pscustomobject]@{ Action = 'Install'; Title = 'Install oh-my-posh now'
            Desc = 'Install it with winget (per-user, no admin), then activate the prompt.' }
        [pscustomobject]@{ Action = 'Skip'; Title = 'Skip for now'
            Desc = 'Apply the theme now; the prompt activates once oh-my-posh is installed.' }
    )
    if ($choice -ne 'Install') {
        Write-Host "  Skipped. Install it later with:  winget install JanDeDobbeleer.OhMyPosh -s winget" -ForegroundColor DarkGray
        return
    }

    Write-Host "  Installing oh-my-posh (per-user, no admin)..." -ForegroundColor Cyan
    try {
        # Plain per-user install - do NOT elevate; an admin winget puts it under
        # Program Files and breaks the per-user PATH/POSH_THEMES_PATH expectation.
        winget install JanDeDobbeleer.OhMyPosh --source winget --accept-source-agreements --accept-package-agreements
    } catch {
        Write-Host "  winget failed: $_" -ForegroundColor Red
        Write-Host "  Install manually, then re-open pwsh:  winget install JanDeDobbeleer.OhMyPosh -s winget" -ForegroundColor DarkGray
        return
    }

    if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
        Write-Host "  oh-my-posh installed and on PATH." -ForegroundColor Green
    } else {
        # winget updates the user PATH (and POSH_THEMES_PATH) but the running
        # session won't see them - the guarded $PROFILE block picks it up next launch.
        Write-Host "  oh-my-posh installed. Re-open pwsh (or restart your terminal) so it lands on PATH and the prompt activates." -ForegroundColor Yellow
    }
}

# --- Orchestrator -------------------------------------------------------------

function Set-PoshPaletteTheme {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Theme,
        [string] $SettingsPath = (Get-WindowsTerminalSettingsPath),
        [string] $ProfilePath  = $PROFILE,
        [switch] $DryRun,
        [switch] $Quiet,  # the TUI shows its own confirmation panel instead
        # How to handle profiles that pin their own colorScheme (and so ignore the
        # theme). 'Prompt' asks via an up/down menu when a console is attached, and
        # falls back to 'Keep' when it can't (CI, piped input).
        [ValidateSet('Prompt', 'ThisProfile', 'AllProfiles', 'Keep')]
        [string] $ProfileOverride = 'Prompt'
    )

    if (-not $Quiet) { Write-Host "Applying '$($Theme.name)'..." -ForegroundColor Cyan }

    if ($SettingsPath) {
        if (-not $DryRun) { Backup-PoshPaletteFile $SettingsPath | Out-Null }
        Set-PoshPaletteTerminalLayer -Theme $Theme -SettingsPath $SettingsPath -DryRun:$DryRun
        if (-not $Quiet) { Write-Host "  Terminal scheme applied (hot-reloads instantly)" -ForegroundColor Green }
        # A per-profile colorScheme would shadow what we just wrote to defaults.
        if (-not $DryRun) {
            Resolve-PoshPaletteProfileOverrides -SettingsPath $SettingsPath -Theme $Theme -Action $ProfileOverride -Quiet:$Quiet
        }
    } elseif (-not $Quiet) {
        Write-Host "  Windows Terminal settings.json not found - skipping Terminal layer." -ForegroundColor Yellow
        Write-Host "  (This is expected when not on Windows / Windows Terminal.)" -ForegroundColor DarkGray
    }

    # Offer to install oh-my-posh if this theme's prompt needs it (skip on dry-run).
    if (-not $DryRun) { Confirm-PoshPaletteOhMyPosh -Theme $Theme }

    if (-not $DryRun) { Backup-PoshPaletteFile $ProfilePath | Out-Null }
    Set-PoshPaletteProfileLayer -Theme $Theme -ProfilePath $ProfilePath -DryRun:$DryRun
    if (-not $Quiet) {
        Write-Host "  Prompt + input/output colors applied" -ForegroundColor Green
        Write-Host "Done. Open a new tab if the prompt didn't refresh." -ForegroundColor Cyan
    }
}

# --- Revert -------------------------------------------------------------------

# Backups are named "<file>.poshpalette-<timestamp>.bak" next to the original.
function Get-PoshPaletteBackups {
    param([string] $Path)
    if (-not $Path) { return @() }
    $dir  = Split-Path $Path -Parent
    $leaf = Split-Path $Path -Leaf
    Get-ChildItem -Path $dir -Filter "$leaf.poshpalette-*.bak" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending
}

function Restore-PoshPalette {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string] $SettingsPath = (Get-WindowsTerminalSettingsPath),
        [string] $ProfilePath  = $PROFILE,
        [switch] $KeepProfileBlock   # only revert Terminal settings, leave the profile block
    )

    Write-Host "Reverting PoshPalette..." -ForegroundColor Cyan

    # 1. Restore Windows Terminal settings.json from the newest backup.
    if ($SettingsPath) {
        $bak = Get-PoshPaletteBackups -Path $SettingsPath | Select-Object -First 1
        if ($bak -and $PSCmdlet.ShouldProcess($SettingsPath, "Restore from $($bak.Name)")) {
            Copy-Item $bak.FullName $SettingsPath -Force
            Write-Host "  Restored Terminal settings from $($bak.Name)" -ForegroundColor Green
        } elseif (-not $bak) {
            Write-Host "  No Terminal settings backup found - skipping." -ForegroundColor Yellow
        }
    }

    # 2. Remove the managed profile block (clean revert of layers 2-4).
    if (-not $KeepProfileBlock -and (Test-Path $ProfilePath)) {
        $content = Get-Content $ProfilePath -Raw
        $pattern = "(?s)\r?\n?$([regex]::Escape($script:BlockStart)).*?$([regex]::Escape($script:BlockEnd))\r?\n?"
        if ($content -match $pattern) {
            if ($PSCmdlet.ShouldProcess($ProfilePath, 'Remove PoshPalette block')) {
                $new = ([regex]::Replace($content, $pattern, "`n")).TrimEnd() + "`n"
                Set-Content -Path $ProfilePath -Value $new -Encoding utf8
                Write-Host "  Removed PoshPalette block from profile." -ForegroundColor Green
            }
        } else {
            Write-Host "  No PoshPalette block in profile." -ForegroundColor Yellow
        }
    }

    Write-Host "Restart PowerShell for the prompt/input/output to fully revert." -ForegroundColor Cyan
}

# --- Reset to default ---------------------------------------------------------

# Force the stock default look (Windows Terminal's Campbell scheme + Cascadia
# Mono, no opacity/acrylic, the default PowerShell prompt) - a clean, repeatable
# baseline, e.g. to demo "before -> after". Unlike Restore-PoshPalette (which
# restores your backup), this sets known defaults regardless of prior state.
function Reset-PoshPaletteTerminalDefaults {
    param([string] $SettingsPath, [switch] $DryRun)
    if (-not $SettingsPath) { return }
    if ($DryRun) { Write-Host "  [dry-run] would reset Terminal defaults in $SettingsPath" -ForegroundColor DarkGray; return }
    $text = Get-Content $SettingsPath -Raw
    try {
        $rootOpen = $text.IndexOf('{')
        $prof = Find-JsoncMember $text $rootOpen 'profiles'
        if (-not $prof) { return }
        $profOpen = $text.IndexOf('{', $prof.ValueStart)
        if (-not (Find-JsoncMember $text $profOpen 'defaults')) { return }
        $get = { $text.IndexOf('{', (Find-JsoncMember $text $profOpen 'defaults').ValueStart) }
        $text = Set-JsoncMember $text (& $get) 'colorScheme' '"Campbell"'
        $text = Set-JsoncMember $text (& $get) 'opacity'     '100'
        $text = Set-JsoncMember $text (& $get) 'useAcrylic'  'false'
        $text = Set-JsoncMember $text (& $get) 'font'        '{ "face": "Cascadia Mono" }'
        $null = ConvertFrom-Jsonc $text
        Set-Content -Path $SettingsPath -Value $text -Encoding utf8
    } catch { Write-Verbose "Reset terminal defaults failed: $_" }
}

function Reset-PoshPalette {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string] $SettingsPath = (Get-WindowsTerminalSettingsPath),
        [string] $ProfilePath  = $PROFILE,
        [switch] $DryRun,
        [switch] $Quiet
    )

    if (-not $Quiet) { Write-Host "Resetting to the default look..." -ForegroundColor Cyan }

    # Layer 1: stock Windows Terminal defaults.
    if ($SettingsPath) {
        if (-not $DryRun) { Backup-PoshPaletteFile $SettingsPath | Out-Null }
        Reset-PoshPaletteTerminalDefaults -SettingsPath $SettingsPath -DryRun:$DryRun
        if (-not $Quiet) { Write-Host "  Terminal reset to Campbell + Cascadia Mono" -ForegroundColor Green }
    }

    # Layers 2-4: drop the managed block so the prompt/colors fall back to default.
    if (Test-Path $ProfilePath) {
        if (-not $DryRun) { Backup-PoshPaletteFile $ProfilePath | Out-Null }
        $content = Get-Content $ProfilePath -Raw
        $pattern = "(?s)\r?\n?$([regex]::Escape($script:BlockStart)).*?$([regex]::Escape($script:BlockEnd))\r?\n?"
        if ($content -match $pattern) {
            if (-not $DryRun) {
                $new = ([regex]::Replace($content, $pattern, "`n")).TrimEnd() + "`n"
                Set-Content -Path $ProfilePath -Value $new -Encoding utf8
            }
            if (-not $Quiet) { Write-Host "  Prompt + input/output colors reset" -ForegroundColor Green }
        }
    }

    if (-not $DryRun) {
        # Forget the active composition so tweaks start fresh.
        $cur = Join-Path $HOME '.poshpalette/current.json'
        if (Test-Path $cur) { Remove-Item $cur -Force }
        # Live session: oh-my-posh installs a prompt function (and POSH_* env). A
        # bare Remove-Item Function:\prompt only drops the copy in the current
        # scope, so a second reset can leave the visible (global) prompt in place.
        # Set the global prompt straight back to PowerShell's default instead, and
        # clear oh-my-posh's env so nothing re-applies it this session.
        try {
            $default = { "PS $($executionContext.SessionState.Path.CurrentLocation)$('>' * ($nestedPromptLevel + 1)) " }
            Set-Item -Path Function:global:prompt -Value $default -Force -ErrorAction SilentlyContinue
        } catch { }
        Get-ChildItem Env: -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'POSH_*' } |
            ForEach-Object { Remove-Item "Env:\$($_.Name)" -ErrorAction SilentlyContinue }
    }

    if (-not $Quiet) { Write-Host "Done. Terminal colors update now; open a new tab for the default prompt." -ForegroundColor Cyan }
}
