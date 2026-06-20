# Changelog

All notable changes to PoshPalette are documented here.
This project follows [Semantic Versioning](https://semver.org/).

## [0.3.5]

### Fixed
- **Preview glyphs no longer show as `?`.** The preview writes via
  `[Console]::Write`, which encodes through `[Console]::OutputEncoding` - a legacy
  code page on Windows, so `❯ ✓ ✗` collapsed to `?` (while `█`, which is in the
  code page, survived). The picker now switches the console to UTF-8 for the
  session and restores it on exit.

## [0.3.4]

### Fixed
- **Cleaner "applied" screen.** Applying from the menu printed the command's own
  progress lines and then a second confirmation panel that repeated them with
  mismatched alignment. The menu apply now runs quietly (`Set-PoshPaletteTheme
  -Quiet`) and shows a single tidy panel.
- **Preview no longer corrupts.** 0.3.3 embedded the real oh-my-posh prompt in
  the preview, which broke badly: captured Nerd Font glyphs turned into mojibake,
  full-width prompts wrapped over the theme list, and powerline segment
  backgrounds bled across the screen. The preview now draws a short,
  scheme-colored prompt itself instead of invoking oh-my-posh, so it stays inside
  its panel on every terminal. Generated `auto-*` prompts are drawn to match
  their real layout; a referenced theme shows a clean generic prompt (its exact
  shape still appears once applied, in a new tab).

## [0.3.3]

### Added
- **Type a name in the prompt and font pickers.** Both now have a "Type a
  name..." row, so you can enter any oh-my-posh theme (e.g. `atomic`) or font
  face directly, the same as passing a name to a command. The
  `Set-PoshPalettePrompt` / `Set-PoshPaletteFont` commands accept those names
  too, not just bundled catalog ids.

### Changed
- **The live preview now renders your real prompt.** When oh-my-posh is
  available it prints the actual prompt for the selected config (generated
  `auto` prompt or a referenced theme) instead of a generic stand-in, so Simple
  and Detail mode previews reflect the oh-my-posh prompt you'll get.
- **Bigger, more representative preview:** a short session with the prompt plus
  `Get-ChildItem`, `git pull`, and `npm test` output, colored from the theme.
- **Font picker shows the font name + how to install/apply it.** A font can't be
  rendered live (the terminal uses one font for the whole window), so instead of
  an empty preview it explains that and points at `Install-PoshPaletteFont`.

## [0.3.2]

### Added
- **Navigable Back / Quit entries.** Every list and Detail mode now has a `← Back`
  row, and the main menu has a `Quit` row, so you can move to them with the arrow
  keys instead of needing to know the Esc/Q shortcut (the shortcuts still work).
- **Post-apply confirmation screen.** After a theme applies you now get a clear
  "✓ Applied" panel with next steps (open a new tab, tweak a layer) and a CTA to
  return to the menu or quit, instead of being dropped back at a bare prompt.

### Changed
- **Refined-flat TUI styling.** Programmatic column alignment, a dim divider rule
  under each title, an inverse-highlight on the selected row, a two-column Detail
  mode (fields left, live preview right), and an aligned Doctor table. The main
  menu shows the `>_` brand mark instead of an unrelated pink block.

### Fixed
- **Detail mode no longer errors when you pick a layer.** Choosing a scheme,
  shell colors, or prompt threw `ConvertTo-PPComposition is not recognized`,
  because the live-preview callback was built with `.GetNewClosure()`, which
  rebinds the block to a throwaway module that can't see the module's own
  functions. The preview now uses a module-bound callback that resolves
  correctly.
- **Detail mode is arrow-navigable.** Move with up/down and press Enter to edit
  a layer (number keys 1-7 and A still work as shortcuts); it no longer forces
  you to type a number.

## [0.3.1]

### Changed
- Default font is now **RobotoMono Nerd Font** across all bundled themes (was
  JetBrainsMono). The showcase site renders previews in Roboto Mono to match.

### Fixed
- **No more "Unable to find the following fonts" warning / hang on apply.** A theme
  whose font isn't installed now keeps your current terminal font and points you to
  `Install-PoshPaletteFont`, instead of writing a missing font into `settings.json`.
- **Simple-mode preview** now renders on the theme's actual background color, so it
  recolors as you scroll (it looked static before).
- **Main menu** is arrow-navigable (up/down + Enter); number keys still work.

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
