# Changelog

All notable changes to PoshPalette are documented here.
This project follows [Semantic Versioning](https://semver.org/).

## [0.3.0]

### Added
- **One-command-per-layer tweaks:** `Set-PoshPaletteScheme`, `Set-PoshPaletteColors`,
  `Set-PoshPalettePrompt`, `Set-PoshPaletteFont`, and `Set-PoshPaletteLayer` change a
  single slot on top of your current look. The active composition is remembered in
  `~/.poshpalette/current.json` so tweaks stack.
- **`Install-PoshPaletteFont`:** download and install a Nerd Font for the current
  user straight from the nerd-fonts releases (Windows / macOS / Linux). The pack
  references fonts by name; this fills the "no font installed" gap.
- **14 more bundled themes** (26 total), chosen for range: neon (`synthwave`,
  `cyberpunk`, `oxocarbon`), vivid (`monokai-pro`), warm (`horizon`, `ayu-dark`,
  `night-owl`), retro CRT (`green-phosphor`, `amber-crt`), light (`github-light`,
  `solarized-light`, `rose-pine-dawn`), the `campbell` Windows Terminal default,
  and a `high-contrast` accessibility theme.
- **`Test-PoshPaletteSetup`** (the doctor): preflight check for PowerShell
  version, PSReadLine, `$PSStyle`, oh-my-posh, `POSH_THEMES_PATH`, a Nerd Font,
  Windows Terminal settings, and `$PROFILE`, with actionable fixes. Also reachable
  from the main menu (`palette`, then `[3] Doctor`).
- **Richer prompts:** generated palette-aware styles `auto` (classic),
  `auto-minimal`, `auto-powerline`, and `auto-robby` (robbyrussell layout:
  `❯❯ folder git:(branch) time`), plus 20+ oh-my-posh built-in themes added to the
  catalog (`robbyrussell`, `agnoster`, `paradox`, `pure`, `spaceship`, `sorin`,
  `powerlevel10k_rainbow`, and more) for Detail-mode choice.

## [0.2.0]

### Added
- **9 more bundled themes** (12 total): Catppuccin Latte, Dracula, Gruvbox,
  Rosé Pine, One Dark, Solarized Dark, Everforest, GitHub Dark, Kanagawa.
- **Comment-preserving JSONC writer:** applying a theme now edits `settings.json`
  in place, so your comments, key order, and formatting survive.
- **Palette-aware `auto` prompt:** generates an oh-my-posh config from the active
  scheme so the prompt always matches.
- **`Import-PoshPaletteScheme`:** import iTerm2 `.itermcolors`, base16 YAML, and
  Windows Terminal scheme JSON into the catalog.
- **`Get-PoshPaletteRemoteCatalog` / `Save-PoshPaletteRemoteTheme`:** browse and
  pull community catalog entries from a GitHub repo.
- **Detail-mode editing** of opacity, acrylic, and font size.

## [0.1.0]

### Added
- Composition model with per-layer catalogs (schemes / palettes / prompts / fonts).
- 4-layer apply engine (Windows Terminal, PSReadLine, `$PSStyle`, oh-my-posh).
- Simple and Detail interactive TUI modes with live preview.
- Backups + `Restore-PoshPalette`; comment-aware JSONC parsing.
