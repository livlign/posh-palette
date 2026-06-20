# Posh Palette

VS Code-style theme picker for **PowerShell + Windows Terminal** — styles all
**4 layers** at once with live preview, from inside your terminal.

> **Naming:** the project/brand is **Posh Palette** (repo: `posh-palette`, kebab-case
> like `oh-my-posh` / `nerd-fonts`). The PowerShell module and its commands use
> PascalCase — `PoshPalette`, `Start-PoshPalette` — because command nouns can't
> contain hyphens. Keep that split when adding docs or commands.

| Layer | What it colors | How it applies |
|-------|----------------|----------------|
| Windows Terminal | scheme, background, opacity, font | `settings.json` (hot-reloads instantly) |
| PSReadLine | the command line you type | `$PROFILE` + live session |
| `$PSStyle` | command output (dirs, errors, tables) | `$PROFILE` + live session |
| oh-my-posh | the prompt | `$PROFILE` + live session |

## Install

```powershell
Install-Module PoshPalette -Scope CurrentUser   # (once published)
```

## Use

**Interactive (Simple or Detail mode):**
```powershell
Start-PoshPalette     # or just: palette
```
- **Simple mode** — scroll a list of full themes, live preview on the right, Enter to apply.
- **Detail mode** — choose each layer independently (scheme / prompt / input / output).

**Headless, by name** (the names below):
```powershell
Install-PoshPaletteTheme tokyo-night
Install-PoshPaletteTheme catppuccin-mocha -DryRun   # preview without writing
```

**Revert** (restores `settings.json` from the newest backup and removes the profile block):
```powershell
Restore-PoshPalette                 # full revert
Restore-PoshPalette -WhatIf         # show what it would do
Restore-PoshPalette -KeepProfileBlock   # revert Terminal only
```

## Bundled themes

| Name | id |
|------|----|
| Catppuccin Mocha | `catppuccin-mocha` |
| Tokyo Night | `tokyo-night` |
| Nord | `nord` |

## How it's structured (composition model)

A **theme is a composition** — it doesn't hold colors, it *references* one entry
from each per-layer catalog. This is what lets Detail mode swap a single layer
(keep your prompt, try a new scheme) instead of forcing all-or-nothing presets.

```
themes/*.json     a composition: { scheme, palette, prompt, font, opacity, acrylic, fontSize }
schemes/*.json    Windows Terminal color scheme (16 ANSI + bg/fg/cursor)
palettes/*.json   PSReadLine input colors + $PSStyle output colors
prompts/*.json    oh-my-posh theme reference
fonts.json        list of (nerd) fonts to choose from
```

The resolver expands a composition into the flat shape the appliers write, so
Simple mode (pick a preset), Detail mode (override one slot) and
`Install-PoshPaletteTheme` all share one path.

> **Note on prompts:** oh-my-posh themes hard-code their own colors, so a prompt
> swapped onto a different scheme may not match. The preview shows the real combo
> before you apply. (Palette-aware prompt generation is a planned upgrade.)

## Contribute

Each layer is independently contributable — **one JSON file, one PR**:
- a **scheme** → `schemes/` (just the 16 ANSI colors)
- a **palette** → `palettes/` (PSReadLine + `$PSStyle` colors)
- a **prompt** → `prompts/` (an oh-my-posh theme reference)
- a **preset** → `themes/` (a composition tying the above together)

Copy an existing file in the matching folder, change the values, open a PR.

## Safety

- Backs up `settings.json` and `$PROFILE` before the first write (`*.poshpalette-*.bak`).
- Profile edits live in a single managed block (`# >>> PoshPalette >>>`), so re-applying
  replaces cleanly and removing it reverts you.

## Status

Phase-1 scaffold.

**Done:** composition model + per-layer catalogs; 4-layer apply engine; backups +
`Restore-PoshPalette`; comment-aware JSONC *parsing* + trailing-comma tolerance;
Simple-mode picker and **Detail-mode per-layer composer**, both with live preview.

**TODO:** comment-*preserving* JSONC writer (round-trip currently drops comments
— backup mitigates); palette-aware prompt generation (so swapped prompts inherit
the scheme); importer for the iTerm2/base16 catalogs; theme fetch from the GitHub
catalog; per-composition opacity/acrylic/font-size editing in Detail mode.
