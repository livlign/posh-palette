# Contributing to Posh Palette

Posh Palette is built from small, independent JSON files. The most useful
contribution is usually a single new theme layer — **one JSON file, one PR**.

## Add a theme layer

Each layer lives in its own folder and can be contributed on its own:

| Folder | What it holds |
|--------|---------------|
| `schemes/` | a Windows Terminal color scheme (16 ANSI colors + bg/fg/cursor) |
| `palettes/` | PSReadLine input colors + `$PSStyle` output colors |
| `prompts/` | an oh-my-posh prompt reference |
| `themes/` | a **composition** that ties one entry from each layer together |

Workflow:

1. Copy an existing file in the matching folder.
2. Change the `id`, `name`, and the values.
3. (Optional) Add a `themes/` composition that references your new layer(s).
4. Open a PR.

Keep `id` kebab-case and matching the filename (e.g. `tokyo-night.json` → `"id": "tokyo-night"`).
If you add a full theme, make sure the same `id` exists across the layers it
references so the resolver can expand it.

A `themes/*.json` composition looks like:

```json
{ "id": "tokyo-night", "name": "Tokyo Night", "description": "...",
  "scheme": "tokyo-night", "palette": "tokyo-night",
  "prompt": "auto-powerline", "font": "jetbrains",
  "fontSize": 11, "opacity": 100, "acrylic": false, "order": 1 }
```

- `font` is a `fonts.json` id (or any installed face name). Vary it across themes —
  it's a real part of the look the tool applies.
- `order` controls where the theme appears in both the tool list and the web
  gallery (lower = earlier). The first nine are deliberately the most varied
  (background, color, prompt shape, font) since they're the first thing a new user
  sees — keep that diversity in mind when slotting a new theme near the top.

## Authoring helpers (color math)

`tools/` holds an optional workbench for making and tweaking theme colors —
contrast linting plus palette/scheme generators (the generators use the
[Pansies](https://github.com/PoshCode/Pansies) module). It's author-only; the
shipped module and end users never touch it. See [`tools/README.md`](tools/README.md).
A quick legibility check before you open a PR:

```powershell
Import-Module ./tools/PoshPalette.Authoring.psm1
Test-PoshPaletteContrast -Scheme my-scheme -Palette my-palette
```

CI runs that same contrast check (`tests/Contrast.Tests.ps1`) over every theme.

## Naming conventions

The project/brand is **Posh Palette** (repo: `posh-palette`, kebab-case like
`oh-my-posh` / `nerd-fonts`). The PowerShell module and its commands use
PascalCase (`PoshPalette`, `Start-PoshPalette`) because command nouns can't
contain hyphens. Keep that split when adding docs or commands.

## Keep the gallery in sync

The theme gallery (`docs/themes.html`) embeds a hand-maintained snapshot of every
theme's colors. If you add or change a scheme/palette, update the matching entry on
that page so the preview matches what actually gets applied (site == reality).
