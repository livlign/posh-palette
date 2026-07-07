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

# Where auto-fetched community entries are cached. The catalog loaders read this
# in addition to the bundled module dir, so new themes pulled from GitHub show up
# without reinstalling. Kept under the user's home so it's always writable and
# survives module updates.
function Get-PoshPaletteUserRoot  { Join-Path $HOME '.poshpalette' }
function Get-PoshPaletteCacheRoot { Join-Path (Get-PoshPaletteUserRoot) 'catalog' }

# --- Catalog loaders ----------------------------------------------------------

# Enumerate the *.json entries for a kind across both roots (bundled first, then
# the user cache), de-duped by id. Bundled wins on a clash, so the cache only
# *adds* new community entries and can never shadow a shipped one.
function Get-PoshPaletteCatalogFiles {
    param([Parameter(Mandatory)][string] $Kind)
    $seen = @{}
    foreach ($root in @((Get-PoshPaletteDataRoot), (Get-PoshPaletteCacheRoot))) {
        $dir = Join-Path $root $Kind
        if (-not (Test-Path $dir)) { continue }
        foreach ($file in (Get-ChildItem -Path $dir -Filter '*.json' -File | Sort-Object Name)) {
            $data = try { Get-Content $file.FullName -Raw | ConvertFrom-Json } catch { $null }
            if (-not $data -or -not $data.id -or $seen.ContainsKey($data.id)) { continue }
            $seen[$data.id] = $true
            [pscustomobject]@{ File = $file; Data = $data }
        }
    }
}

function Get-PoshPaletteCatalog {
    param([Parameter(Mandatory)][ValidateSet('schemes', 'palettes', 'prompts')] [string] $Kind)
    Get-PoshPaletteCatalogFiles -Kind $Kind | ForEach-Object {
        [pscustomobject]@{ Id = $_.Data.id; Name = $_.Data.name; Data = $_.Data }
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
    # Merges bundled themes with auto-fetched community ones (see
    # Get-PoshPaletteCatalogFiles). Sorted by the theme's 'order' field (the
    # curated sequence the web gallery also uses); entries without an order fall
    # to the end (where new community themes land), then by name as a tiebreak.
    Get-PoshPaletteCatalogFiles -Kind 'themes' | ForEach-Object {
        $data = $_.Data
        [pscustomobject]@{
            Id          = $data.id
            Name        = $data.name
            Description = $data.description
            Order       = if ($null -ne $data.order) { [int]$data.order } else { [int]::MaxValue }
            Path        = $_.File.FullName
            Data        = $data   # the composition
        }
    } | Sort-Object Order, Name
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
        # A prompt may carry a fixed gradient ramp (e.g. the 'dracula' style); pass it through.
        $ompArgs = @{ Style = $style }
        if ($prompt.gradient) { $ompArgs['Gradient'] = $prompt.gradient }
        @{ generated = $true; name = "pp-$($prompt.id)"; config = (New-PoshPaletteOmpConfig $scheme.colors @ompArgs) }
    } elseif ($prompt) {
        @{ ohMyPoshTheme = $prompt.ohMyPoshTheme }
    } else {
        @{ ohMyPoshTheme = $Composition.prompt }   # typed-in oh-my-posh theme name
    }

    # Fill the PSReadLine roles a palette doesn't set (Keyword/Type/Member/
    # ContinuationPrompt). Left unset, PSReadLine uses its own *fixed* built-in
    # colors (green keyword, gray type, white member) that clash with the theme.
    # Derive them from the palette's own roles - which already clear the contrast
    # gate - so they stay legible without per-theme authoring. An explicit value
    # in the palette JSON always wins.
    $psReadLine = ConvertTo-PoshPaletteHashtable $palette.psReadLine
    $derived = @{
        Keyword            = $psReadLine['Operator']
        Type               = $psReadLine['Parameter']
        Member             = $psReadLine['Default']
        ContinuationPrompt = $psReadLine['Comment']
    }
    foreach ($role in $derived.Keys) {
        if (-not $psReadLine.ContainsKey($role) -and $derived[$role]) { $psReadLine[$role] = $derived[$role] }
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
        psReadLine = $psReadLine
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
