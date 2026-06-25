# Authoring tools

Color helpers for people who **make or tweak themes**. This is a workbench, not
part of the shipped module — `Install-Module PoshPalette` stays zero-dependency,
and end users never load any of this.

```powershell
Import-Module ./tools/PoshPalette.Authoring.psm1
```

## What's in here

| Command | Needs Pansies? | What it does |
|---------|:--:|--------------|
| `Test-PoshPaletteContrast` | no | Lint a theme's syntax colors for legible contrast against its background. The automated form of the v0.6.3 "faint syntax colour" pass. |
| `New-PoshPalettePalette` | yes | Derive a `palettes/*.json` from a `schemes/*.json`, auto-lifting any role that would be too faint. A starting point to hand-tune. |
| `New-PoshPaletteScheme` | yes | Generate a 16-color `schemes/*.json` from a background + one accent, via Pansies' color wheel. A scaffold for a new theme. |
| `Test-PoshPaletteSchemeImport` | yes | Report how far each scheme color drifts when snapped to XTerm-256 / 16-color terminals. |

The contrast linter is deliberately **dependency-free** (pure WCAG math) so the
CI gate in `tests/Contrast.Tests.ps1` runs the same everywhere. Only the three
generators use Pansies.

## Setup (generators only)

```powershell
Install-Module Pansies -Scope CurrentUser
```

## Examples

```powershell
# Lint an existing theme; see who's faint
Test-PoshPaletteContrast -Theme tokyo-night | Format-Table Role,Color,Ratio,Level

# Lint a scheme/palette pair before a composition exists
Test-PoshPaletteContrast -Scheme nord -Palette nord

# Generate a palette to match a scheme, write it out, then lint it
New-PoshPalettePalette -Scheme tokyo-night | Set-Content palettes/tokyo-night.json
Test-PoshPaletteContrast -Scheme tokyo-night -Palette tokyo-night

# Scaffold a brand-new scheme from a background + accent
New-PoshPaletteScheme -Background '#0B0E14' -Accent '#39BAE6' -Id ayu-ish |
    Set-Content schemes/ayu-ish.json

# After importing an outside scheme, check it survives lower-capability terminals
Test-PoshPaletteSchemeImport -Scheme my-imported-scheme | Format-Table
```

## ⚠️ Verify the Pansies API on Windows (one-time)

These tools were authored on a machine without `pwsh`, so the **Pansies calls
are written against its documented surface but not yet executed**. Before relying
on the three generators, confirm these member/parameter names in a real session
and adjust the marked lines in `PoshPalette.Authoring.psm1` if they differ:

```powershell
Import-Module Pansies
# 1. RgbColor cast + channel properties (used everywhere)
$c = [PoshCode.Pansies.RgbColor]'#39BAE6'; $c.Red; $c.Green; $c.Blue

# 2. Color wheel — New-PoshPaletteScheme calls: Get-ColorWheel -Color $c -Count 6
Get-Help Get-ColorWheel -Full        # confirm -Color / -Count (or positional)

# 3. Downsample members — Test-PoshPaletteSchemeImport calls .ToXterm256() / .ToConsoleColor()
$c | Get-Member                      # find the real nearest-palette members
```

The contrast linter (`Test-PoshPaletteContrast`) needs no such check — it's pure
math and is covered by `tests/Contrast.Tests.ps1`.
