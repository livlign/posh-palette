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
        [string] $Branch = 'main'
    )
    $api = "https://api.github.com/repos/$Repo/contents/$Kind`?ref=$Branch"
    $headers = @{ 'User-Agent' = 'PoshPalette'; 'Accept' = 'application/vnd.github+json' }
    if ($env:GITHUB_TOKEN) { $headers['Authorization'] = "Bearer $env:GITHUB_TOKEN" }

    $items = Invoke-RestMethod -Uri $api -Headers $headers
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
