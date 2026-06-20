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

# Comment-preserving write: edit only the spans that change, so the user's
# comments, key order, and formatting survive. Falls back to a parse->reserialize
# round-trip if the file is too irregular to edit surgically.
function Set-PoshPaletteTerminalLayer {
    param($Theme, [string] $SettingsPath, [switch] $DryRun)

    $edits      = Get-PoshPaletteTerminalEdits $Theme
    $schemeName = $edits.SchemeName

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
        $defOpen = $text.IndexOf('{', (Find-JsoncMember $text $profOpen 'defaults').ValueStart)
        $fontJson = ($edits.Defaults.font | ConvertTo-Json -Depth 5 -Compress)
        $text = Set-JsoncMember $text $defOpen 'font' $fontJson

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
        $d.font        = @{ face = $edits.Defaults.font.face; size = $edits.Defaults.font.size }
        Set-Content -Path $SettingsPath -Value ($settings | ConvertTo-Json -Depth 32) -Encoding utf8
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
    if ($Theme.psStyle.TableHeader) { [void]$sb.AppendLine("    `$PSStyle.Formatting.TableHeader = `$PSStyle.Foreground.FromRgb('$($Theme.psStyle.TableHeader)')") }
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

# --- Orchestrator -------------------------------------------------------------

function Set-PoshPaletteTheme {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Theme,
        [string] $SettingsPath = (Get-WindowsTerminalSettingsPath),
        [string] $ProfilePath  = $PROFILE,
        [switch] $DryRun
    )

    Write-Host "Applying '$($Theme.name)'..." -ForegroundColor Cyan

    if ($SettingsPath) {
        if (-not $DryRun) { Backup-PoshPaletteFile $SettingsPath | Out-Null }
        Set-PoshPaletteTerminalLayer -Theme $Theme -SettingsPath $SettingsPath -DryRun:$DryRun
        Write-Host "  Terminal scheme applied (hot-reloads instantly)" -ForegroundColor Green
    } else {
        Write-Host "  Windows Terminal settings.json not found - skipping Terminal layer." -ForegroundColor Yellow
        Write-Host "  (This is expected when not on Windows / Windows Terminal.)" -ForegroundColor DarkGray
    }

    if (-not $DryRun) { Backup-PoshPaletteFile $ProfilePath | Out-Null }
    Set-PoshPaletteProfileLayer -Theme $Theme -ProfilePath $ProfilePath -DryRun:$DryRun
    Write-Host "  Prompt + input/output colors applied" -ForegroundColor Green
    Write-Host "Done. Open a new tab if the prompt didn't refresh." -ForegroundColor Cyan
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
