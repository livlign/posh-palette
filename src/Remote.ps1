# Remote.ps1 - fetch community catalog entries from a GitHub repo.
#
# Themes are contributed as one JSON file per catalog dir (like oh-my-posh /
# nerd-fonts). This lets a user browse and pull entries straight from a repo
# without cloning it: list what's there, then save the ones they want locally.

$script:DefaultRepo = 'livlign/posh-palette'

function Get-PoshPaletteRemoteCatalog {
    [CmdletBinding()]
    param(
        [ValidateSet('themes','schemes','palettes','prompts')] [string] $Kind = 'themes',
        [string] $Repo = $script:DefaultRepo,
        [string] $Branch = 'main',
        [int] $TimeoutSec = 10
    )
    $api = "https://api.github.com/repos/$Repo/contents/$Kind`?ref=$Branch"
    $headers = @{ 'User-Agent' = 'PoshPalette'; 'Accept' = 'application/vnd.github+json' }
    if ($env:GITHUB_TOKEN) { $headers['Authorization'] = "Bearer $env:GITHUB_TOKEN" }

    $items = Invoke-RestMethod -Uri $api -Headers $headers -TimeoutSec $TimeoutSec
    $items | Where-Object { $_.name -like '*.json' } | ForEach-Object {
        [pscustomobject]@{
            Id          = [IO.Path]::GetFileNameWithoutExtension($_.name)
            Kind        = $Kind
            Repo        = $Repo
            DownloadUrl = $_.download_url
        }
    }
}

# Download one entry into the local catalog dir (themes/, schemes/, ...).
function Save-PoshPaletteRemoteTheme {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string] $Id,
        [ValidateSet('themes','schemes','palettes','prompts')] [string] $Kind = 'themes',
        [string] $Repo = $script:DefaultRepo,
        [string] $Branch = 'main',
        [switch] $Force
    )
    $entry = Get-PoshPaletteRemoteCatalog -Kind $Kind -Repo $Repo -Branch $Branch |
        Where-Object { $_.Id -eq $Id } | Select-Object -First 1
    if (-not $entry) { throw "No '$Kind' entry '$Id' in $Repo." }

    $dest = Join-Path (Join-Path (Get-PoshPaletteDataRoot) $Kind) "$Id.json"
    if ((Test-Path $dest) -and -not $Force) { throw "$dest already exists. Use -Force to overwrite." }

    $headers = @{ 'User-Agent' = 'PoshPalette' }
    $body = Invoke-RestMethod -Uri $entry.DownloadUrl -Headers $headers
    $json = if ($body -is [string]) { $body } else { $body | ConvertTo-Json -Depth 32 }
    $null = ConvertFrom-Jsonc $json   # validate before writing
    Set-Content -Path $dest -Value $json -Encoding utf8
    Write-Host "Saved $Kind/$Id -> $dest" -ForegroundColor Green
    Get-Item $dest
}

# Download one remote entry into the user cache (~/.poshpalette/catalog/<kind>/),
# validate it, and return the parsed object. Used by the auto-refresh below.
function Save-PoshPaletteCacheEntry {
    param([Parameter(Mandatory)][string] $Kind, [Parameter(Mandatory)] $Entry, [int] $TimeoutSec = 6)
    $dir = Join-Path (Get-PoshPaletteCacheRoot) $Kind
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $headers = @{ 'User-Agent' = 'PoshPalette' }
    $body = Invoke-RestMethod -Uri $Entry.DownloadUrl -Headers $headers -TimeoutSec $TimeoutSec
    $json = if ($body -is [string]) { $body } else { $body | ConvertTo-Json -Depth 32 }
    $parsed = ConvertFrom-Jsonc $json   # validate before writing
    Set-Content -Path (Join-Path $dir "$($Entry.Id).json") -Value $json -Encoding utf8
    $parsed
}

# Auto-refresh the catalog from GitHub: pull any themes (and the scheme / palette
# / prompt files they reference) that aren't already available locally, into the
# user cache so they appear in the picker. Safe to call on every launch:
#   * throttled to once / 24h unless -Force,
#   * disabled entirely by $env:POSHPALETTE_NO_AUTOUPDATE (unless -Force),
#   * every network call is time-boxed and the whole thing is best-effort, so an
#     offline or slow GitHub never blocks startup — it just uses what's cached.
# Returns the number of new themes added.
function Update-PoshPaletteCatalog {
    [CmdletBinding()]
    param(
        [switch] $Force,
        [string] $Repo = $script:DefaultRepo,
        [string] $Branch = 'main',
        [int] $TimeoutSec = 5
    )
    if ($env:POSHPALETTE_NO_AUTOUPDATE -and -not $Force) { return 0 }

    $cacheRoot = Get-PoshPaletteCacheRoot
    $stamp     = Join-Path $cacheRoot '.last-refresh'

    if (-not $Force -and (Test-Path $stamp)) {
        $last = try { [datetime]((Get-Content $stamp -Raw).Trim()) } catch { $null }
        if ($last -and ((Get-Date) - $last).TotalHours -lt 24) { return 0 }   # refreshed recently
    }

    $added = 0
    try {
        $haveThemes = @(Get-PoshPaletteThemes | ForEach-Object Id)
        $remote     = @(Get-PoshPaletteRemoteCatalog -Kind themes -Repo $Repo -Branch $Branch -TimeoutSec $TimeoutSec)
        $newThemes  = @($remote | Where-Object { $_.Id -notin $haveThemes })

        if ($newThemes.Count -gt 0) {
            # Indexes for resolving each new theme's referenced layers.
            $remIdx = @{}
            $have   = @{}
            foreach ($k in 'schemes', 'palettes', 'prompts') {
                $remIdx[$k] = @(Get-PoshPaletteRemoteCatalog -Kind $k -Repo $Repo -Branch $Branch -TimeoutSec $TimeoutSec)
                $have[$k]   = @(Get-PoshPaletteCatalog -Kind $k | ForEach-Object Id)
            }
            $themesDir = Join-Path (Get-PoshPaletteCacheRoot) 'themes'
            if (-not (Test-Path $themesDir)) { New-Item -ItemType Directory -Path $themesDir -Force | Out-Null }
            $headers = @{ 'User-Agent' = 'PoshPalette' }
            foreach ($t in $newThemes) {
                # Peek the theme to learn its referenced layers before committing it.
                $raw  = Invoke-RestMethod -Uri $t.DownloadUrl -Headers $headers -TimeoutSec $TimeoutSec
                $json = if ($raw -is [string]) { $raw } else { $raw | ConvertTo-Json -Depth 32 }
                $theme = ConvertFrom-Jsonc $json   # validate
                if (-not $theme.id) { continue }
                # Cache any missing scheme / palette / prompt it depends on first.
                foreach ($dep in @(
                        @{ k = 'schemes';  id = $theme.scheme },
                        @{ k = 'palettes'; id = $theme.palette },
                        @{ k = 'prompts';  id = $theme.prompt })) {
                    if (-not $dep.id -or ($dep.id -in $have[$dep.k])) { continue }   # already have it
                    $e = $remIdx[$dep.k] | Where-Object { $_.Id -eq $dep.id } | Select-Object -First 1
                    if ($e) { $null = Save-PoshPaletteCacheEntry -Kind $dep.k -Entry $e -TimeoutSec $TimeoutSec; $have[$dep.k] += $dep.id }
                }
                # Commit the theme LAST, so it never appears without its layers.
                Set-Content -Path (Join-Path $themesDir "$($t.Id).json") -Value $json -Encoding utf8
                $added++
            }
        }

        if (-not (Test-Path $cacheRoot)) { New-Item -ItemType Directory -Path $cacheRoot -Force | Out-Null }
        Set-Content -Path $stamp -Value ((Get-Date).ToString('o')) -Encoding utf8
    } catch {
        Write-Verbose "PoshPalette catalog refresh skipped: $_"   # offline / slow / rate-limited: non-fatal
    }
    $added
}
