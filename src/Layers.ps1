# Layers.ps1 - tweak one layer at a time.
#
# A theme is a composition of slots (scheme / palette / prompt / font / opacity /
# acrylic / font size). These commands change a single slot on top of whatever you
# last applied, so you can keep your prompt and just swap the color scheme, etc.
# The active composition is remembered in ~/.poshpalette/current.json.

$script:CurrentPath = Join-Path $HOME '.poshpalette/current.json'

# The composition behind the current look. Falls back to the first bundled theme
# the first time, so tweaking works even before anything has been applied.
function Get-PoshPaletteCurrentComposition {
    if (Test-Path $script:CurrentPath) {
        try { return (ConvertTo-PoshPaletteHashtable (Get-Content $script:CurrentPath -Raw | ConvertFrom-Json)) } catch { }
    }
    $base = (Get-PoshPaletteThemes | Select-Object -First 1).Data
    ConvertTo-PoshPaletteHashtable $base
}

function Save-PoshPaletteCurrentComposition {
    param([Parameter(Mandatory)] $Composition)
    $dir = Split-Path $script:CurrentPath -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    ([pscustomobject]$Composition) | ConvertTo-Json -Depth 10 | Set-Content -Path $script:CurrentPath -Encoding utf8
}

# Override one or more slots of the current composition and re-apply everything.
function Set-PoshPaletteLayer {
    [CmdletBinding()]
    param(
        [string] $Scheme,
        [string] $Palette,
        [string] $Prompt,
        [string] $Font,
        [ValidateRange(10, 100)][int] $Opacity,
        [ValidateRange(8, 32)][int] $FontSize,
        [bool] $Acrylic,
        [switch] $DryRun
    )
    $comp = Get-PoshPaletteCurrentComposition
    if (-not $comp.name) { $comp['name'] = 'Custom' }

    if ($Scheme)  { $null = Get-PoshPaletteCatalogItem -Kind 'schemes'  -Id $Scheme;  $comp['scheme']  = $Scheme }
    if ($Palette) { $null = Get-PoshPaletteCatalogItem -Kind 'palettes' -Id $Palette; $comp['palette'] = $Palette }
    # Prompt and font accept a catalog id OR a name typed directly (an oh-my-posh
    # theme name / a font face), so the command matches what the picker allows.
    if ($Prompt)  { $comp['prompt'] = $Prompt }
    if ($Font)    { $comp['font']   = $Font }
    if ($PSBoundParameters.ContainsKey('Opacity'))  { $comp['opacity']  = $Opacity }
    if ($PSBoundParameters.ContainsKey('FontSize')) { $comp['fontSize'] = $FontSize }
    if ($PSBoundParameters.ContainsKey('Acrylic'))  { $comp['acrylic']  = $Acrylic }

    Set-PoshPaletteTheme -Theme (Resolve-PoshPaletteTheme ([pscustomobject]$comp)) -DryRun:$DryRun
    if (-not $DryRun) { Save-PoshPaletteCurrentComposition $comp }
}

# --- One command per layer ----------------------------------------------------

function Set-PoshPaletteScheme {  # the Windows Terminal color scheme (bg/fg/16 ANSI)
    param([Parameter(Mandatory, Position = 0)][string] $Id, [switch] $DryRun)
    Set-PoshPaletteLayer -Scheme $Id -DryRun:$DryRun
}
function Set-PoshPaletteColors {  # PSReadLine input + $PSStyle output colors
    param([Parameter(Mandatory, Position = 0)][string] $Id, [switch] $DryRun)
    Set-PoshPaletteLayer -Palette $Id -DryRun:$DryRun
}
function Set-PoshPalettePrompt {  # the oh-my-posh prompt
    param([Parameter(Mandatory, Position = 0)][string] $Id, [switch] $DryRun)
    Set-PoshPaletteLayer -Prompt $Id -DryRun:$DryRun
}
function Set-PoshPaletteFont {    # the terminal font
    param([Parameter(Mandatory, Position = 0)][string] $Id, [switch] $DryRun)
    Set-PoshPaletteLayer -Font $Id -DryRun:$DryRun
}
