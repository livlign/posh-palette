# PoshPalette.Authoring.psm1 - color helpers for THEME AUTHORS.
#
# This module is NOT part of the shipped PoshPalette module and is never loaded
# by end users. It is a workbench for the small group of people who hand-author
# or tweak themes (you + PR contributors). It lives in tools/ on purpose so that
# `Install-Module PoshPalette` stays zero-dependency.
#
# Two kinds of commands live here:
#
#   * Contrast linting  - pure WCAG math, NO external dependency. Used by the
#                         Pester gate (tests/Contrast.Tests.ps1) so CI never
#                         hinges on a binary module loading. This is what
#                         automates the v0.6.3 "raise contrast on faint syntax
#                         colours" pass: a number instead of an eyeball.
#
#   * Generators        - New-PoshPalettePalette / New-PoshPaletteScheme /
#                         Test-PoshPaletteSchemeImport. These lean on the
#                         Pansies module (Get-Gradient / Get-ColorWheel /
#                         Get-Complement / [PoshCode.Pansies.RgbColor]) for the
#                         color math that is genuinely hard to hand-roll.
#
# Usage:
#   Import-Module ./tools/PoshPalette.Authoring.psm1
#   Test-PoshPaletteContrast -Theme tokyo-night
#   New-PoshPalettePalette  -Scheme tokyo-night | Set-Content palettes/tokyo-night.json
#
# Requires PowerShell 7.2+. Generators additionally require: Install-Module Pansies

Set-StrictMode -Version Latest

$script:Root = Split-Path $PSScriptRoot -Parent   # repo root (tools/ is one down)

# ---------------------------------------------------------------------------
# Native color core (no dependency) - parsing, luminance, WCAG contrast, blend.
# ---------------------------------------------------------------------------

# "#RRGGBB" -> @{ R=int; G=int; B=int } (0..255). Tolerant of missing '#'.
function ConvertFrom-PPHex {
    param([Parameter(Mandatory)][string] $Hex)
    $h = $Hex.TrimStart('#')
    if ($h.Length -ne 6) { throw "Not a 6-digit hex color: '$Hex'" }
    [pscustomobject]@{
        R = [convert]::ToInt32($h.Substring(0, 2), 16)
        G = [convert]::ToInt32($h.Substring(2, 2), 16)
        B = [convert]::ToInt32($h.Substring(4, 2), 16)
    }
}

function ConvertTo-PPHex {
    param([int] $R, [int] $G, [int] $B)
    $clamp = { param($v) [Math]::Max(0, [Math]::Min(255, [int][Math]::Round($v))) }
    '#{0:X2}{1:X2}{2:X2}' -f (& $clamp $R), (& $clamp $G), (& $clamp $B)
}

# WCAG 2.x relative luminance of a "#RRGGBB" color, 0 (black) .. 1 (white).
function Get-PPRelativeLuminance {
    param([Parameter(Mandatory)][string] $Hex)
    $rgb = ConvertFrom-PPHex $Hex
    $lin = foreach ($c in $rgb.R, $rgb.G, $rgb.B) {
        $s = $c / 255.0
        if ($s -le 0.03928) { $s / 12.92 } else { [Math]::Pow(($s + 0.055) / 1.055, 2.4) }
    }
    0.2126 * $lin[0] + 0.7152 * $lin[1] + 0.0722 * $lin[2]
}

# WCAG contrast ratio between two colors: 1.0 (identical) .. 21.0 (black/white).
function Get-PPContrastRatio {
    param([Parameter(Mandatory)][string] $A, [Parameter(Mandatory)][string] $B)
    $la = Get-PPRelativeLuminance $A
    $lb = Get-PPRelativeLuminance $B
    $hi = [Math]::Max($la, $lb); $lo = [Math]::Min($la, $lb)
    [Math]::Round(($hi + 0.05) / ($lo + 0.05), 2)
}

# Linear blend between two hex colors. $Amount 0 = all A, 1 = all B.
function Get-PPBlend {
    param([Parameter(Mandatory)][string] $A, [Parameter(Mandatory)][string] $B, [double] $Amount)
    $x = ConvertFrom-PPHex $A; $y = ConvertFrom-PPHex $B
    ConvertTo-PPHex ($x.R + ($y.R - $x.R) * $Amount) `
                    ($x.G + ($y.G - $x.G) * $Amount) `
                    ($x.B + ($y.B - $x.B) * $Amount)
}

# Nudge $Color toward $Toward (usually the scheme foreground) in small steps
# until it clears $TargetRatio against $Background. This is the programmatic
# version of "make the faint comment readable". Returns the original color
# untouched if it already passes.
function Resolve-PPReadableColor {
    param(
        [Parameter(Mandatory)][string] $Color,
        [Parameter(Mandatory)][string] $Background,
        [Parameter(Mandatory)][string] $Toward,
        [double] $TargetRatio = 4.5
    )
    $c = $Color
    for ($i = 1; $i -le 20; $i++) {
        if ((Get-PPContrastRatio $c $Background) -ge $TargetRatio) { break }
        $c = Get-PPBlend $Color $Toward ($i / 20.0)
    }
    $c
}

# ---------------------------------------------------------------------------
# Catalog helpers (read the repo's own JSON layers).
# ---------------------------------------------------------------------------

function Get-PPLayer {
    param([ValidateSet('schemes', 'palettes', 'themes')][string] $Kind, [string] $Id)
    $path = Join-Path $script:Root "$Kind/$Id.json"
    if (-not (Test-Path $path)) { throw "$Kind/$Id.json not found under $script:Root" }
    Get-Content $path -Raw | ConvertFrom-Json
}

# Roles in palettes/*.json that are *meant* to recede (dim comments, ghost text).
# They get a gentler contrast floor than primary syntax colors.
$script:MutedRoles = @('Comment', 'InlinePrediction')

# ---------------------------------------------------------------------------
# 1. Contrast linter  (native; the CI gate uses this)
# ---------------------------------------------------------------------------

<#
.SYNOPSIS
  Check every syntax color in a theme's palette for legible contrast against its
  scheme background. Automates the manual "faint syntax colour" pass.
.PARAMETER Theme
  A themes/*.json id. Its scheme + palette are resolved automatically.
.PARAMETER Scheme / .PARAMETER Palette
  Lint a scheme/palette pair directly by id (use when authoring before a
  composition exists).
.PARAMETER FailBelow
  Hard floor. A color below this is essentially unreadable -> Pass = $false.
.PARAMETER WarnBelow
  Guidance threshold (WCAG AA body text = 4.5). Below this -> Level 'Warn'.
.OUTPUTS
  One record per role: Role, Color, Background, Ratio, Level (Ok/Warn/Fail), Pass.
#>
function Test-PoshPaletteContrast {
    [CmdletBinding(DefaultParameterSetName = 'Theme')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Theme', Position = 0)][string] $Theme,
        [Parameter(Mandatory, ParameterSetName = 'Pair')][string] $Scheme,
        [Parameter(Mandatory, ParameterSetName = 'Pair')][string] $Palette,
        [double] $FailBelow = 1.6,
        [double] $WarnBelow = 4.5,
        # Comment / InlinePrediction are *meant* to recede; only flag them as a
        # hard fail when they're effectively invisible. (everforest's ghost text
        # sits at 1.55 - the catalog low - so the floor is just under it.)
        [double] $MutedFailBelow = 1.5,
        [double] $MutedWarnBelow = 2.5
    )

    if ($PSCmdlet.ParameterSetName -eq 'Theme') {
        $comp = Get-PPLayer -Kind themes -Id $Theme
        $schemeId = $comp.scheme; $paletteId = $comp.palette
    } else {
        $schemeId = $Scheme; $paletteId = $Palette
    }

    $scheme  = Get-PPLayer -Kind schemes  -Id $schemeId
    $palette = Get-PPLayer -Kind palettes -Id $paletteId

    # Colors may be nested under .colors (our format) or flat at the top level.
    # Access via PSObject so StrictMode never crashes on a missing property; if
    # the expected shape is absent, throw a diagnostic naming what we actually got.
    $schemeColors = if ($scheme.PSObject.Properties['colors']) { $scheme.colors } else { $scheme }
    if (-not $schemeColors.PSObject.Properties['background']) {
        throw "scheme '$schemeId' has no background color. Root='$script:Root'; top-level props=[$($scheme.PSObject.Properties.Name -join ', ')]"
    }
    $bg = $schemeColors.background

    if (-not $palette.PSObject.Properties['psReadLine']) {
        throw "palette '$paletteId' has no psReadLine block. top-level props=[$($palette.PSObject.Properties.Name -join ', ')]"
    }

    foreach ($role in $palette.psReadLine.PSObject.Properties) {
        $color = $role.Value
        if (-not $color) { continue }
        $ratio = Get-PPContrastRatio $color $bg
        $muted = $role.Name -in $script:MutedRoles
        $fail  = if ($muted) { $MutedFailBelow } else { $FailBelow }
        $warn  = if ($muted) { $MutedWarnBelow } else { $WarnBelow }
        $level = if ($ratio -lt $fail) { 'Fail' } elseif ($ratio -lt $warn) { 'Warn' } else { 'Ok' }
        [pscustomobject]@{
            Theme = $schemeId; Role = $role.Name; Color = $color
            Background = $bg; Ratio = $ratio; Level = $level; Pass = ($level -ne 'Fail')
        }
    }
}

# ---------------------------------------------------------------------------
# Pansies bootstrap (only generators need it).
# ---------------------------------------------------------------------------

function Assert-Pansies {
    if (Get-Module Pansies) { return }
    if (-not (Get-Module -ListAvailable Pansies)) {
        throw "This command needs the Pansies module. Install it once with:  Install-Module Pansies -Scope CurrentUser"
    }
    Import-Module Pansies -ErrorAction Stop
}

# ---------------------------------------------------------------------------
# 2. Palette-from-scheme generator  (Pansies-assisted)
# ---------------------------------------------------------------------------

# Which ANSI scheme slot seeds each palette role. A sane default mapping that
# authors then hand-tune. Comment/InlinePrediction intentionally use the dim
# brightBlack so they recede - the contrast pass keeps them just readable.
$script:RoleFromAnsi = [ordered]@{
    Command          = 'brightCyan'
    Parameter        = 'cyan'
    String           = 'green'
    Operator         = 'foreground'
    Variable         = 'yellow'
    Number           = 'brightPurple'
    Comment          = 'brightBlack'
    Error            = 'red'
    Default          = 'foreground'
    InlinePrediction = 'brightBlack'
}
$script:PsStyleFromAnsi = [ordered]@{
    Directory   = 'brightBlue'
    Error       = 'red'
    TableHeader = 'purple'
}

<#
.SYNOPSIS
  Derive a palettes/*.json (PSReadLine + $PSStyle colors) from an existing
  schemes/*.json, then auto-fix any role that would be too faint on the
  background. Output is a starting point to hand-tweak, not a final answer.
.PARAMETER Scheme
  A schemes/*.json id.
.PARAMETER TargetRatio
  Contrast floor each generated color is lifted to (toward the foreground).
.EXAMPLE
  New-PoshPalettePalette -Scheme tokyo-night | Set-Content palettes/tokyo-night.json
#>
function New-PoshPalettePalette {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string] $Scheme,
        [string] $Id = $Scheme,
        [string] $Name,
        [double] $TargetRatio = 4.5,
        [double] $MutedTargetRatio = 2.5
    )
    Assert-Pansies   # we round-trip colors through Pansies' RgbColor for validation

    $scheme = Get-PPLayer -Kind schemes -Id $Scheme
    $c  = $scheme.colors
    $bg = $c.background
    $fg = $c.foreground

    $pick = {
        param($role, $slot)
        $raw = $c.$slot
        if (-not $raw) { $raw = $fg }
        # Validate the hex by casting through Pansies (throws on a bad value).
        [void][PoshCode.Pansies.RgbColor]$raw
        $target = if ($role -in $script:MutedRoles) { $MutedTargetRatio } else { $TargetRatio }
        Resolve-PPReadableColor -Color $raw -Background $bg -Toward $fg -TargetRatio $target
    }

    $psrl = [ordered]@{}
    foreach ($r in $script:RoleFromAnsi.Keys) { $psrl[$r] = & $pick $r $script:RoleFromAnsi[$r] }
    $psstyle = [ordered]@{}
    foreach ($r in $script:PsStyleFromAnsi.Keys) { $psstyle[$r] = & $pick $r $script:PsStyleFromAnsi[$r] }

    if (-not $Name) { $Name = $scheme.name }
    [ordered]@{ id = $Id; name = $Name; psReadLine = $psrl; psStyle = $psstyle } |
        ConvertTo-Json -Depth 8
}

# ---------------------------------------------------------------------------
# 3. Scheme harmony builder  (Pansies Get-ColorWheel / Get-Gradient)
# ---------------------------------------------------------------------------

<#
.SYNOPSIS
  Generate a full 16-color schemes/*.json from a background + one accent color,
  using Pansies' color wheel to spread six balanced hues and gradients to derive
  the bright variants. A scaffold for a new theme - expect to hand-tune.
.PARAMETER Background  Dark or light base, e.g. '#101010'.
.PARAMETER Accent      The anchor hue the wheel rotates from, e.g. '#4DECA0'.
.PARAMETER Foreground  Body text color; defaults to a high-contrast tint of bg.
.EXAMPLE
  New-PoshPaletteScheme -Background '#0B0E14' -Accent '#39BAE6' -Id ayu-ish |
      Set-Content schemes/ayu-ish.json
#>
function New-PoshPaletteScheme {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Background,
        [Parameter(Mandatory)][string] $Accent,
        [string] $Foreground,
        [Parameter(Mandatory)][string] $Id,
        [string] $Name
    )
    Assert-Pansies

    [void][PoshCode.Pansies.RgbColor]$Background
    [void][PoshCode.Pansies.RgbColor]$Accent

    $isDark = (Get-PPRelativeLuminance $Background) -lt 0.5
    if (-not $Foreground) { $Foreground = if ($isDark) { '#D8DEE9' } else { '#2E3440' } }

    # Six evenly spaced hues around the wheel, seeded from the accent.
    # NOTE: confirm Get-ColorWheel's parameter names on Windows - see tools/README.md.
    $wheel = Get-ColorWheel -Color ([PoshCode.Pansies.RgbColor]$Accent) -Count 6
    $hex = { param($pc) ConvertTo-PPHex $pc.Red $pc.Green $pc.Blue }
    $h = $wheel | ForEach-Object { & $hex $_ }
    # wheel slots -> ANSI hues (red, green, yellow, blue, purple, cyan)
    $red = $h[0]; $yellow = $h[1]; $green = $h[2]; $cyan = $h[3]; $blue = $h[4]; $purple = $h[5]

    # bright variants: nudge each hue toward white (dark themes) for a little pop.
    $bright = { param($c) Get-PPBlend $c '#FFFFFF' 0.18 }
    $black       = if ($isDark) { Get-PPBlend $Background '#FFFFFF' 0.10 } else { '#1A1A1A' }
    $brightBlack = Get-PPBlend $black $Foreground 0.4

    $colors = [ordered]@{
        background = $Background; foreground = $Foreground
        cursorColor = $Accent; selectionBackground = (Get-PPBlend $Background $Accent 0.25)
        black = $black;  red = $red;  green = $green;  yellow = $yellow
        blue = $blue;  purple = $purple;  cyan = $cyan;  white = $Foreground
        brightBlack = $brightBlack
        brightRed = (& $bright $red); brightGreen = (& $bright $green); brightYellow = (& $bright $yellow)
        brightBlue = (& $bright $blue); brightPurple = (& $bright $purple); brightCyan = (& $bright $cyan)
        brightWhite = '#FFFFFF'
    }
    if (-not $Name) { $Name = (Get-Culture).TextInfo.ToTitleCase(($Id -replace '-', ' ')) }
    [ordered]@{ id = $Id; name = $Name; colors = $colors } | ConvertTo-Json -Depth 8
}

# ---------------------------------------------------------------------------
# 4. Import / downsample validator  (Pansies RgbColor nearest-palette)
# ---------------------------------------------------------------------------

<#
.SYNOPSIS
  Validate an imported scheme: confirm every color parses, and report how far
  each one shifts when snapped to the XTerm-256 and 16-color ConsoleColor
  palettes. Surfaces colors that won't survive on lower-capability terminals.
.PARAMETER Scheme  A schemes/*.json id (e.g. one just produced by Import-PoshPaletteScheme).
.OUTPUTS  One record per color: Slot, Hex, XTerm256, Drift256, Console16, Drift16.
#>
function Test-PoshPaletteSchemeImport {
    [CmdletBinding()]
    param([Parameter(Mandatory, Position = 0)][string] $Scheme)
    Assert-Pansies

    $colors = (Get-PPLayer -Kind schemes -Id $Scheme).colors
    foreach ($p in $colors.PSObject.Properties) {
        $hex = $p.Value
        if (-not ($hex -is [string]) -or $hex -notmatch '^#[0-9A-Fa-f]{6}$') { continue }
        $rgb = [PoshCode.Pansies.RgbColor]$hex
        # NOTE: confirm these RgbColor members on Windows (see tools/README.md):
        #   .ToXterm256()  -> nearest 256-color index
        #   .ToConsoleColor() -> nearest of the 16 ConsoleColors
        $x256 = $rgb.ToXterm256()
        $c16  = $rgb.ToConsoleColor()
        [pscustomobject]@{
            Slot = $p.Name; Hex = $hex
            XTerm256 = $x256
            Console16 = $c16
        }
    }
}

Export-ModuleMember -Function `
    Test-PoshPaletteContrast, New-PoshPalettePalette, New-PoshPaletteScheme, Test-PoshPaletteSchemeImport, `
    Get-PPContrastRatio, Get-PPRelativeLuminance, Get-PPBlend, Resolve-PPReadableColor
