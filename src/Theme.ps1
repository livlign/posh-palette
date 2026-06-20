# Theme.ps1 - composition model.
#
# A *theme* is a composition: a set of slot references into per-layer catalogs.
#   themes/*.json    -> { scheme, palette, prompt, font, opacity, acrylic, fontSize }
#   schemes/*.json   -> Windows Terminal color scheme (16 ANSI + bg/fg/cursor)
#   palettes/*.json  -> PSReadLine input colors + $PSStyle output colors
#   prompts/*.json   -> oh-my-posh theme reference
#   fonts.json       -> list of installed (nerd) fonts
#
# Resolve-PoshPaletteTheme expands a composition into the flat shape the
# appliers consume (terminal/psReadLine/psStyle/prompt), so Simple mode (pick a
# preset), Detail mode (override one slot) and headless install all share one path.

function Get-PoshPaletteDataRoot { Split-Path $PSScriptRoot -Parent }
function Get-PoshPaletteThemeRoot { Join-Path (Get-PoshPaletteDataRoot) 'themes' }

# --- Catalog loaders ----------------------------------------------------------

function Get-PoshPaletteCatalog {
    param([Parameter(Mandatory)][ValidateSet('schemes', 'palettes', 'prompts')] [string] $Kind)
    $dir = Join-Path (Get-PoshPaletteDataRoot) $Kind
    Get-ChildItem -Path $dir -Filter '*.json' -File | Sort-Object Name | ForEach-Object {
        $data = Get-Content $_.FullName -Raw | ConvertFrom-Json
        [pscustomobject]@{ Id = $data.id; Name = $data.name; Data = $data }
    }
}

function Get-PoshPaletteCatalogItem {
    param([string] $Kind, [string] $Id)
    $item = Get-PoshPaletteCatalog -Kind $Kind | Where-Object { $_.Id -eq $Id } | Select-Object -First 1
    if (-not $item) { throw "No '$Kind' entry with id '$Id'." }
    $item.Data
}

function Get-PoshPaletteFonts {
    Get-Content (Join-Path (Get-PoshPaletteDataRoot) 'fonts.json') -Raw | ConvertFrom-Json
}

# --- Compositions (presets) ---------------------------------------------------

function Get-PoshPaletteThemes {
    Get-ChildItem -Path (Get-PoshPaletteThemeRoot) -Filter '*.json' -File | Sort-Object Name | ForEach-Object {
        $data = Get-Content $_.FullName -Raw | ConvertFrom-Json
        [pscustomobject]@{
            Id          = $data.id
            Name        = $data.name
            Description = $data.description
            Path        = $_.FullName
            Data        = $data   # the composition
        }
    }
}

# --- Resolver -----------------------------------------------------------------

function ConvertTo-PoshPaletteHashtable {
    param($Object)
    $h = @{}
    if ($Object) { $Object.psobject.Properties | ForEach-Object { $h[$_.Name] = $_.Value } }
    $h
}

# Expand a composition into the flat shape the appliers expect. Returns a
# PSCustomObject identical in shape to a hand-written full theme.
function Resolve-PoshPaletteTheme {
    param([Parameter(Mandatory)] $Composition)

    $scheme  = Get-PoshPaletteCatalogItem -Kind 'schemes'  -Id $Composition.scheme
    $palette = Get-PoshPaletteCatalogItem -Kind 'palettes' -Id $Composition.palette
    # A prompt may be a catalog id, or a bare oh-my-posh theme name typed directly
    # (same as you'd pass to a command); an unknown id is treated as that name.
    $prompt  = Get-PoshPaletteCatalog -Kind 'prompts' | Where-Object { $_.Id -eq $Composition.prompt } | Select-Object -First 1 | ForEach-Object Data
    # A font may be a fonts.json id or a literal font face name typed directly.
    $font    = Get-PoshPaletteFonts | Where-Object { $_.id -eq $Composition.font } | Select-Object -First 1
    if (-not $font) { $font = [pscustomobject]@{ id = $Composition.font; name = $Composition.font; face = $Composition.font; nerd = $Composition.font } }

    $schemeBlock = ConvertTo-PoshPaletteHashtable $scheme.colors
    $schemeBlock['name'] = $scheme.name   # WT scheme is named after the scheme, not the composition

    # A prompt is either a reference to a fixed-color oh-my-posh theme, or 'auto',
    # which generates a config from this scheme's colors so the prompt matches.
    $promptBlock = if ($prompt -and $prompt.generate) {
        $style = if ($prompt.style) { $prompt.style } else { 'classic' }
        @{ generated = $true; name = "pp-$($prompt.id)"; config = (New-PoshPaletteOmpConfig $scheme.colors -Style $style) }
    } elseif ($prompt) {
        @{ ohMyPoshTheme = $prompt.ohMyPoshTheme }
    } else {
        @{ ohMyPoshTheme = $Composition.prompt }   # typed-in oh-my-posh theme name
    }

    $resolved = @{
        name     = $Composition.name
        terminal = @{
            font       = $font.face
            fontSize   = ($Composition.fontSize ?? 11)
            opacity    = ($Composition.opacity ?? 100)
            useAcrylic = [bool]($Composition.acrylic ?? $false)
            scheme     = $schemeBlock
        }
        psReadLine = (ConvertTo-PoshPaletteHashtable $palette.psReadLine)
        psStyle    = (ConvertTo-PoshPaletteHashtable $palette.psStyle)
        prompt     = $promptBlock
    }
    # Round-trip to PSCustomObjects so appliers see the same shape as file themes.
    $resolved | ConvertTo-Json -Depth 32 | ConvertFrom-Json
}

# Resolve a composition by id/name/path into the applier-ready shape.
function Import-PoshPaletteTheme {
    param([Parameter(Mandatory)][string] $NameOrPath)

    $composition = if (Test-Path $NameOrPath) {
        Get-Content $NameOrPath -Raw | ConvertFrom-Json
    } else {
        $match = Get-PoshPaletteThemes | Where-Object { $_.Id -eq $NameOrPath -or $_.Name -eq $NameOrPath } | Select-Object -First 1
        if (-not $match) {
            $available = (Get-PoshPaletteThemes | ForEach-Object Id) -join ', '
            throw "Theme '$NameOrPath' not found. Available: $available"
        }
        $match.Data
    }
    Resolve-PoshPaletteTheme -Composition $composition
}
