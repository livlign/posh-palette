<#
.SYNOPSIS
    Validate and publish PoshPalette to the PowerShell Gallery.

.DESCRIPTION
    Stages only the module files (no docs/, .github/, backups) into a clean temp
    folder, runs Test-ModuleManifest, then Publish-Module. Use -WhatIf to dry-run
    everything except the actual publish.

.EXAMPLE
    ./publish.ps1 -WhatIf                       # validate + stage, don't publish
    ./publish.ps1 -NuGetApiKey $env:PSGALLERY_KEY
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $NuGetApiKey = $env:PSGALLERY_KEY,
    [string] $Repository  = 'PSGallery'
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

# Files/dirs that make up the shippable module (everything else is repo-only).
$include = @(
    'PoshPalette.psd1', 'PoshPalette.psm1', 'fonts.json',
    'README.md', 'LICENSE', 'CHANGELOG.md',
    'src', 'schemes', 'palettes', 'prompts', 'themes'
)

# Staging always runs (even under -WhatIf); only the publish itself is gated.
$stage = Join-Path ([IO.Path]::GetTempPath()) "PoshPalette-stage-$(Get-Random)"
$dest  = Join-Path $stage 'PoshPalette'
New-Item -ItemType Directory -Path $dest -Force -WhatIf:$false | Out-Null

foreach ($item in $include) {
    $src = Join-Path $root $item
    if (-not (Test-Path $src)) { throw "Missing required item: $item" }
    Copy-Item $src (Join-Path $dest $item) -Recurse -Force -WhatIf:$false
}
# Never ship backups.
Get-ChildItem $dest -Recurse -Filter '*.poshpalette-*.bak' | Remove-Item -Force -WhatIf:$false -ErrorAction SilentlyContinue

$manifest = Join-Path $dest 'PoshPalette.psd1'
$info = Test-ModuleManifest -Path $manifest
Write-Host "Validated PoshPalette v$($info.Version) - $($info.ExportedFunctions.Count) functions." -ForegroundColor Green
Write-Host "Staged at: $dest" -ForegroundColor DarkGray

if (-not $NuGetApiKey) {
    Write-Host "No NuGet API key provided - validation only. Pass -NuGetApiKey or set `$env:PSGALLERY_KEY to publish." -ForegroundColor Yellow
    return
}

if ($PSCmdlet.ShouldProcess("$Repository", "Publish PoshPalette v$($info.Version)")) {
    Publish-Module -Path $dest -NuGetApiKey $NuGetApiKey -Repository $Repository -Verbose
    Write-Host "Published PoshPalette v$($info.Version) to $Repository." -ForegroundColor Green
}
