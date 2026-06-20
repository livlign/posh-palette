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

# Windows Terminal settings.json is JSONC (// line comments, /* */ block
# comments, and tolerated trailing commas) which ConvertFrom-Json cannot parse.
# This strips comments while respecting string contents, so a "https://" inside
# a value or a "," inside a string is never mistaken for a comment/separator.
function Remove-JsoncComments {
    param([string] $Text)
    $sb = [System.Text.StringBuilder]::new()
    $inString = $false; $escaped = $false
    $i = 0; $n = $Text.Length
    while ($i -lt $n) {
        $c    = $Text[$i]
        $next = if ($i + 1 -lt $n) { $Text[$i + 1] } else { [char]0 }
        if ($inString) {
            [void]$sb.Append($c)
            if     ($escaped)      { $escaped = $false }
            elseif ($c -eq '\')    { $escaped = $true }
            elseif ($c -eq '"')    { $inString = $false }
            $i++; continue
        }
        if ($c -eq '"')                  { $inString = $true; [void]$sb.Append($c); $i++; continue }
        if ($c -eq '/' -and $next -eq '/') { while ($i -lt $n -and $Text[$i] -ne "`n") { $i++ }; continue }
        if ($c -eq '/' -and $next -eq '*') {
            $i += 2
            while ($i -lt $n -and -not ($Text[$i] -eq '*' -and $i + 1 -lt $n -and $Text[$i + 1] -eq '/')) { $i++ }
            $i += 2; continue
        }
        [void]$sb.Append($c); $i++
    }
    $sb.ToString()
}

function Set-PoshPaletteTerminalLayer {
    param($Theme, [string] $SettingsPath, [switch] $DryRun)

    $scheme = @{}
    $Theme.terminal.scheme.psobject.Properties | ForEach-Object { $scheme[$_.Name] = $_.Value }
    if (-not $scheme['name']) { $scheme['name'] = $Theme.name }
    $schemeName = $scheme['name']

    # NOTE: comments are stripped for parsing and NOT re-emitted on write, so a
    # round-trip drops any comments the user had. The pre-write backup is the
    # mitigation until a comment-preserving writer lands (see Restore-PoshPalette).
    $clean = Remove-JsoncComments (Get-Content $SettingsPath -Raw)
    $clean = [regex]::Replace($clean, ',(\s*[}\]])', '$1')   # tolerate trailing commas
    $settings = $clean | ConvertFrom-Json -AsHashtable

    if (-not $settings.schemes) { $settings.schemes = @() }
    $settings.schemes = @($settings.schemes | Where-Object { $_.name -ne $schemeName }) + $scheme

    if (-not $settings.profiles)          { $settings.profiles = @{} }
    if (-not $settings.profiles.defaults) { $settings.profiles.defaults = @{} }
    $d = $settings.profiles.defaults
    $d.colorScheme = $schemeName
    $d.opacity     = $Theme.terminal.opacity
    $d.useAcrylic  = [bool]$Theme.terminal.useAcrylic
    $d.font        = @{ face = $Theme.terminal.font; size = $Theme.terminal.fontSize }

    $json = $settings | ConvertTo-Json -Depth 32
    if ($DryRun) {
        Write-Host "  [dry-run] would write Terminal scheme '$($Theme.name)' to $SettingsPath" -ForegroundColor DarkGray
    } else {
        Set-Content -Path $SettingsPath -Value $json -Encoding utf8
    }
}

# --- Layers 2-4: the $PROFILE managed block -----------------------------------

function New-PoshPaletteProfileBlock {
    param($Theme)
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

    # Layer 4: oh-my-posh prompt
    if ($Theme.prompt.ohMyPoshTheme) {
        [void]$sb.AppendLine('if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {')
        [void]$sb.AppendLine("    oh-my-posh init pwsh --config `"`$env:POSH_THEMES_PATH\$($Theme.prompt.ohMyPoshTheme).omp.json`" | Invoke-Expression")
        [void]$sb.AppendLine('}')
    }
    [void]$sb.AppendLine($script:BlockEnd)
    $sb.ToString()
}

function Set-PoshPaletteProfileLayer {
    param($Theme, [string] $ProfilePath = $PROFILE, [switch] $DryRun)

    $block   = New-PoshPaletteProfileBlock $Theme
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
