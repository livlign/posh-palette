# Posh Palette

VS Code-style theme picker for **PowerShell + Windows Terminal**. Styles all
**4 layers** at once with live preview, from inside your terminal.

> **Naming:** the project/brand is **Posh Palette** (repo: `posh-palette`, kebab-case
> like `oh-my-posh` / `nerd-fonts`). The PowerShell module and its commands use
> PascalCase (`PoshPalette`, `Start-PoshPalette`) because command nouns can't
> contain hyphens. Keep that split when adding docs or commands.

| Layer | What it colors | How it applies |
|-------|----------------|----------------|
| Windows Terminal | scheme, background, opacity, font | `settings.json` (hot-reloads instantly) |
| PSReadLine | the command line you type | `$PROFILE` + live session |
| `$PSStyle` | command output (dirs, errors, tables) | `$PROFILE` + live session |
| oh-my-posh | the prompt | `$PROFILE` + live session |

## Install

PoshPalette needs **PowerShell 7.2 or newer** (the modern, cross-platform
PowerShell, `pwsh`), not the built-in Windows PowerShell 5.1. Check with
`$PSVersionTable.PSVersion`.

```powershell
winget install Microsoft.PowerShell      # if you don't have PowerShell 7 yet
pwsh                                      # start PowerShell 7 (not "powershell")
Install-Module PoshPalette -Scope CurrentUser
palette
```

In Windows Terminal, set the default profile to **PowerShell** (7.x) rather than
**Windows PowerShell** so new tabs use it automatically.

## Use

**Interactive (Simple or Detail mode):**
```powershell
Start-PoshPalette     # or just: palette
```
- **Simple mode:** scroll a list of full themes, live preview on the right, Enter to apply.
- **Detail mode:** choose each layer independently (scheme / prompt / input / output).

**Apply a full theme by name:**
```powershell
Install-PoshPaletteTheme tokyo-night
Install-PoshPaletteTheme catppuccin-mocha -DryRun   # preview without writing
```

### Tweak one layer

Change a single part by its catalog name and keep everything else exactly as it is.
Each command edits just that slot on top of your current look:

```powershell
Set-PoshPaletteScheme  nord           # color scheme (Windows Terminal bg + 16 ANSI)
Set-PoshPaletteColors  tokyo-night    # input + output colors (PSReadLine / $PSStyle)
Set-PoshPalettePrompt  agnoster       # the oh-my-posh prompt
Set-PoshPaletteFont    jetbrains      # the terminal font
Set-PoshPaletteLayer -Opacity 90 -Acrylic $true -FontSize 12   # window + size
```

A name is the `id` of any entry in `schemes/`, `palettes/`, `prompts/`, or
`fonts.json`. Browse the options in Detail mode, in the
[theme gallery](https://livlign.github.io/posh-palette/themes.html), or by listing
those folders. Your current look is remembered in `~/.poshpalette/current.json`, so
tweaks stack: install a theme, then swap just its prompt, then just its font.

Every command takes `-DryRun` to preview without writing.

**Revert** (restores `settings.json` from the newest backup and removes the profile block):
```powershell
Restore-PoshPalette                 # full revert
Restore-PoshPalette -WhatIf         # show what it would do
Restore-PoshPalette -KeepProfileBlock   # revert Terminal only
```

**Import a scheme** from the formats the community already publishes:
```powershell
Import-PoshPaletteScheme ./Dracula.itermcolors -Save     # iTerm2
Import-PoshPaletteScheme ./gruvbox.yaml -Save            # base16
Import-PoshPaletteScheme ./scheme.json -Save             # Windows Terminal
```

**Pull a theme from the GitHub catalog** (no clone needed):
```powershell
Get-PoshPaletteRemoteCatalog                 # list what's published
Save-PoshPaletteRemoteTheme some-theme       # download into your catalog
```

**Check your setup** (PowerShell, fonts, oh-my-posh, terminal: what's ready, what to fix):
```powershell
Test-PoshPaletteSetup        # or: palette, then [3] Doctor
```

**Install a Nerd Font.** The pack references fonts by name; it does not bundle the
binaries, so it pulls one from the [nerd-fonts](https://www.nerdfonts.com/font-downloads)
releases for you:
```powershell
Install-PoshPaletteFont jetbrains      # any font id from the catalog
Install-PoshPaletteFont CascadiaCode   # or a raw Nerd Font name
```

## Bundled themes

**26 themes**, from muted dev classics to neon and retro CRT. Browse them all in
the [theme gallery](https://livlign.github.io/posh-palette/themes.html).

- **Vivid / neon:** `synthwave`, `cyberpunk`, `oxocarbon`, `monokai-pro`
- **Dark classics:** `tokyo-night`, `dracula`, `catppuccin-mocha`, `nord`, `one-dark`,
  `gruvbox`, `rose-pine`, `kanagawa`, `everforest`, `solarized-dark`, `github-dark`
- **Warm:** `horizon`, `ayu-dark`, `night-owl`
- **Retro CRT:** `green-phosphor`, `amber-crt`
- **Light:** `catppuccin-latte`, `github-light`, `solarized-light`, `rose-pine-dawn`
- **Baseline & a11y:** `campbell` (Windows Terminal default), `high-contrast`

## How it's structured (composition model)

A **theme is a composition**: it doesn't hold colors, it *references* one entry
from each per-layer catalog. This is what lets you swap a single layer (keep your
prompt, try a new scheme) instead of forcing all-or-nothing presets.

```
themes/*.json     a composition: { scheme, palette, prompt, font, opacity, acrylic, fontSize }
schemes/*.json    Windows Terminal color scheme (16 ANSI + bg/fg/cursor)
palettes/*.json   PSReadLine input colors + $PSStyle output colors
prompts/*.json    oh-my-posh theme reference
fonts.json        list of (nerd) fonts to choose from
```

The resolver expands a composition into the flat shape the appliers write, so
Simple mode, Detail mode, `Install-PoshPaletteTheme`, and the `Set-PoshPalette*`
layer commands all share one path.

> **Note on prompts:** oh-my-posh themes hard-code their own colors, so a prompt
> swapped onto a different scheme may not match. The preview shows the real combo
> before you apply. To always match the scheme, use a generated prompt instead:
> **`auto`** (classic), **`auto-minimal`**, **`auto-powerline`**, or **`auto-robby`**
> (the `❯❯ folder git:(branch) time` robbyrussell layout). The catalog also ships
> 20+ oh-my-posh built-in themes (`robbyrussell`, `agnoster`, `paradox`, `pure`,
> `spaceship`, `powerlevel10k_rainbow`, and more) to pick from.

## Contribute

Each layer is independently contributable: **one JSON file, one PR**.

- a **scheme** goes in `schemes/` (just the 16 ANSI colors)
- a **palette** goes in `palettes/` (PSReadLine + `$PSStyle` colors)
- a **prompt** goes in `prompts/` (an oh-my-posh theme reference)
- a **preset** goes in `themes/` (a composition tying the above together)

Copy an existing file in the matching folder, change the values, open a PR.

## Safety

- Backs up `settings.json` and `$PROFILE` before the first write (`*.poshpalette-*.bak`).
- Profile edits live in a single managed block (`# >>> PoshPalette >>>`), so re-applying
  replaces cleanly and removing it reverts you.

## Status

Phase 3.

**Done:** composition model + per-layer catalogs (26 bundled themes); 4-layer apply
engine; one-command-per-layer tweaks (`Set-PoshPaletteScheme` / `Colors` / `Prompt`
/ `Font`); backups + `Restore-PoshPalette`; Simple-mode picker and Detail-mode
per-layer composer (incl. opacity / acrylic / font size), both with live preview;
comment-preserving JSONC writer; palette-aware generated prompts; scheme importer
(iTerm2 / base16 / Windows Terminal); GitHub catalog fetch; `Test-PoshPaletteSetup`
doctor; `Install-PoshPaletteFont`; and Gallery publish tooling (`publish.ps1` +
tag-triggered CI).

**Next:** the first Gallery release (`Install-Module PoshPalette`); expand the prompt
template library; grow the community catalog.
