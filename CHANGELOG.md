# Changelog

All notable changes to PoshPalette are documented here.
This project follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.8.0]

### Added
- **Profile-override handling:** applying a theme now detects Windows Terminal
  profiles that pin their own `colorScheme`, `font`, `opacity` or `useAcrylic`
  (PoshPalette writes the theme to `profiles.defaults`, so such a profile would
  silently keep its old look). When any are found it asks, via an up/down menu,
  whether to clear them on just your default profile, on all profiles, or leave
  them be. Honest about exactly which keys each profile shadows.
- **In-session font install:** when a theme's font isn't installed, PoshPalette
  offers to download and install it (per-user via the nerd-fonts release, no
  admin) and set it right away, instead of only printing a manual command.

### Changed
- **Unified confirmations:** every interactive prompt (profile overrides, font
  install, oh-my-posh install) now uses one up/down + Enter menu - no typed
  yes/no input. Non-interactive runs (CI, piped input) fall back to the safe,
  non-destructive choice.

## [0.7.0]

### Added
- **Six new themes, leading the catalog:** Opaline (iridescent pearl on deep
  indigo), Patina (aged brass & verdigris), Oxblood (wine, sienna & antique
  gold), Citrus Ink (chartreuse & amber), Letterpress (a light editorial theme)
  and Aubade (a light dawn-gradient theme). Each pairs a hand-tuned scheme +
  palette with an oh-my-posh prompt, and all six clear the WCAG contrast gate.
- **Four new generated prompt styles** ported from oh-my-posh community themes:
  `avit`, `darkblood`, `tokyonight` and `dracula` — the last driven by a designed
  colour gradient carried on the prompt definition. All are palette-aware.
- **oh-my-posh auto-install:** applying a theme whose prompt needs oh-my-posh now
  offers to install it (per-user via winget, no admin) rather than silently
  skipping the prompt layer.
- **Authoring tools (`tools/`, dev-only):** a dependency-free WCAG contrast linter
  — now a CI gate (`tests/Contrast.Tests.ps1`) — plus Pansies-based scheme and
  palette generators. The shipped module stays zero-dependency.

### Changed
- **Richer in-terminal live preview:** the picker's preview panel is now wider and
  framed like a real terminal window (titlebar + traffic lights), and draws each
  theme's real prompt shape — including git status, language versions and cloud
  segments for the themes whose oh-my-posh config actually uses them.
- **Gallery** updated for the six new themes (now 47 total).

## [0.6.4]

### Fixed
- **Detail mode now starts from your current theme, not Eclipse.** The interactive
  composer seeded its working composition from the first bundled theme, so
  changing a single layer (e.g. the font) and applying silently reset every other
  layer to Eclipse. It now seeds from the currently-applied composition
  (`~/.poshpalette/current.json`), so a one-layer tweak keeps the rest of your
  look. Each layer picker (scheme, palette, prompt, font) now also opens with the
  cursor on your current selection instead of the top of the list.
- **Installed Nerd Fonts are now detected correctly.** The apply step checked the
  Windows font registry for a key starting with the family name (e.g. `GeistMono
  Nerd Font`), but Nerd Font files register under their space-less file title
  (`GeistMonoNerdFont-Regular`), so a font installed by `Install-PoshPaletteFont`
  was never recognised and the "font is not installed" warning showed every time.
  The check now compares with whitespace stripped from both sides, fixing it for
  every multi-word face.

### Changed
- **Reverted 0.6.3's theme-colour retune.** 0.6.3 deepened the syntax colours of
  several original themes to chase hard-to-read text, but the cause turned out to
  be the terminal client's own light/dark theme, not the PoshPalette schemes. The
  affected themes (Daybreak, Matcha Zen, Frostbyte, Porcelain, Cyberpunk,
  Synthwave) are restored to their original colours.

## [0.6.3]

### Changed
- Deepened the syntax colours of several original themes (Daybreak, Matcha Zen,
  Frostbyte, Porcelain, Cyberpunk, Synthwave) for contrast. Superseded by 0.6.4,
  which reverts this.

## [0.6.2]

### Changed
- **Re-tuned the six lead theme palettes for Windows Terminal rendering.** They
  were calibrated on macOS, where heavier grayscale anti-aliasing and display
  colour management make the same hex values read richer; on Windows Terminal
  the soft accents looked washed out and the backgrounds flat. Accent chroma is
  lifted in OKLCH (with a floor so Graphite stays near-monochrome) for the dark
  themes, and the light themes (Daybreak, Porcelain) are deepened rather than
  saturated. Every syntax colour was re-verified against WCAG AA. Re-apply a
  theme to pick up the new colours.
- **Redesigned the landing page and theme gallery** (`docs/`) into one cohesive,
  production-grade look: a single committed palette across page and terminal, a
  refined dark developer-product style (Hanken Grotesk + Cascadia Code), a
  one-screen hero with a polished PowerShell preview, an aligned install/CTA
  block, and a re-skinned gallery that keeps every theme's real colours, prompt
  shape and font.

## [0.6.1]

### Fixed
- **Generated prompts now actually honor their per-segment settings.** Every
  `auto-*` prompt wrote segment settings under an `options` key, but oh-my-posh
  reads them from `properties` — so they were silently ignored on every style.
  This surfaced as two visible bugs and several invisible ones:
  - **Prism (atomic) showed two git branch glyphs** — `branch_icon` never took
    effect, so `.HEAD`'s default `` rendered on top of the template's explicit
    one. Now a single icon.
  - **Eclipse (two-line) injected a stray Nerd Font branch glyph** despite the
    style promising "no Nerd Font required", and so didn't match its preview.
    Now renders `● <branch>` cleanly.
  - Also restores `fetch_status` (the changed-files → red coloring never fired),
    path `folder` style, `time_format`, and every other segment option across
    all 15 prompt styles.
- **Preview now matches the rendered prompt for the two-line, arrow and
  powerline styles** — the two-line and arrow previews were missing the time
  segment, and the powerline preview showed a `❯` chevron where the real prompt
  ends in a `✓`/`✗` status symbol.

## [0.6.0]

### Added
- **A six-theme "style drift" now leads the catalog (positions 1–6)**, designed
  to showcase the full range on first scroll — each with a distinct background,
  prompt shape and font, and every syntax color verified to clear WCAG AA:
  - **Eclipse** (`eclipse`, #1, *dark*) — deep blue-slate (`#0E1116`, not pure
    black, to avoid halation) with soft-white text at ~14.6:1 contrast and
    not-quite-neon accents that all hit AAA. A warm gold cursor anchors the cool
    palette. Two-line prompt, JetBrains Mono. Tuned for marathon sessions.
  - **Graphite** (`graphite`, #2, *grey*) — near-monochrome charcoal with a
    single steel-blue accent. Lambda prompt, Commit Mono.
  - **Driftwood** (`driftwood`, #3, *neutral*) — warm taupe with soft earthen
    tones. Spaceship prompt, IBM Plex Mono.
  - **Prism** (`prism`, #4, *colorful*) — deep midnight navy lit by azure, cyan
    and starlight gold; a night-sky take on the colorful step. Atomic prompt,
    Martian Mono.
  - **Daybreak** (`daybreak`, #5, *soft light*) — warm paper with gentle,
    low-glare accents. Minimal prompt, Geist Mono.
  - **Porcelain** (`porcelain`, #6, *light*) — crisp cool white with clean,
    saturated accents. Detailed prompt, Cascadia Code.
- **Two brand-new original themes**, replacing two of the nine originals:
  **Verdigris** (`verdigris`) — oxidized copper and patina green over dark bronze,
  an earthy-metallic dark theme on the two-line prompt with IBM Plex Mono — and
  **Halcyon** (`halcyon`) — a dreamy twilight palette of dusty rose, periwinkle and
  soft gold on the minimal prompt with Roboto Mono. These retire `deep-current`
  and `golden-hour`.
- **Four new generated prompt styles that are faithful 1:1 ports of the
  oh-my-posh community themes they're named after** — `auto-1shell`, `auto-cert`,
  `auto-clean` (clean-detailed) and `auto-velvet`. Same blocks, segments, glyphs,
  templates and options as upstream; only the colors are swapped for the active
  scheme. Verified structurally identical to the upstream theme JSON.

### Changed
- **Reworked the color palettes of all nine original themes** for stronger,
  WCAG-grade contrast and a single clear hero color each: deeper, tinted
  backgrounds and punchier signature accents across Nebula Drift, Miami Heat,
  Forge Ember, Matcha Zen, Velvet Court, Acid Lime and Frostbyte.
- Reassigned prompt shapes: **Nebula Drift → `auto-1shell`**, **Miami Heat →
  `auto-smoothie`** (rounded neon pills), **Matcha Zen → `auto-clean`**,
  **Velvet Court → `auto-velvet`**.
- Generated oh-my-posh configs are now emitted as **schema version 4** (using
  `options` instead of the deprecated `properties`), matching current oh-my-posh
  and the official themes.

### Fixed
- **Picking a theme in the interactive picker didn't persist the active
  composition.** Simple and Detail mode now write `~/.poshpalette/current.json`,
  so a later `Set-PoshPalettePrompt`/`Set-PoshPaletteFont`/etc. tweaks *that*
  theme instead of silently falling back to the first bundled theme.
- **The "font not installed" hint always told you to install `robotomono`**,
  regardless of which font the theme actually needs. It now names the correct
  font id (e.g. `Install-PoshPaletteFont victormono`).
- **Forge Ember (and other powerline/atomic prompts) showed two git branch
  icons.** The git segment prepended a branch glyph while `{{ .HEAD }}` already
  rendered oh-my-posh's default `branch_icon`. The default icon is now suppressed
  so only one glyph shows.

## [0.5.1]

### Fixed
- **Long theme/catalog lists no longer push the header off a short terminal.**
  Simple mode and the Detail-mode pickers now scroll: they render only as many
  rows as fit, keep the selection in view, and show an `(n/total)` indicator —
  so the search bar and filters stay visible no matter the window height.

## [0.5.0]

### Added
- **Nine new original themes**, featured first in the catalog (now **35**):
  `nebula-drift`, `deep-current`, `miami-heat`, `forge-ember`, `matcha-zen`,
  `velvet-court`, `acid-lime`, `frostbyte`, `golden-hour` — each a distinct
  combination of color, font, and prompt shape.
- **Search + filter in Simple mode.** Type to live-filter themes by name, and
  press Tab to cycle All / Dark / Light (dark or light is detected from the
  scheme's background luminance).
- **Auto-updating community catalog.** On launch, `palette` pulls any new themes
  published to the GitHub catalog — and the scheme/palette/prompt files they
  reference — into `~/.poshpalette/catalog/`, so new themes arrive without
  reinstalling. Throttled to once a day, time-boxed, and best-effort (offline or
  slow never blocks). `palette -Refresh` forces a check; `Update-PoshPaletteCatalog`
  is exposed; `$env:POSHPALETTE_NO_AUTOUPDATE` opts out.
- **In-app update prompt.** On the same daily cadence, the menu shows a
  `[5] Update` item when a newer module version is on the PowerShell Gallery;
  selecting it runs `Update-Module PoshPalette`.
- **Three new generated prompt styles:** `auto-spaceship`, `auto-atomic`, and
  `auto-smoothie` (scheme-matched like the rest).
- **Per-theme fonts.** Themes now span the font catalog instead of all using one
  face, and the catalog gained IBM Plex, Space Mono, Source Code Pro, Monaspace,
  Martian Mono, and more.

### Changed
- **Curated catalog order** shared by the tool and the web gallery (via an
  `order` field), with the most varied themes first.
- All bundled themes now ship fully opaque (opacity 100, acrylic off).

### Tooling
- Pester test suite + GitHub Actions CI (Windows + Linux) covering the resolver,
  prompt generation, and the catalog/version auto-refresh.

## [0.4.2]

### Fixed
- **Reset now works every time, not just the first.** Reset restored the live
  prompt with `Remove-Item Function:\prompt`, which only drops the copy in the
  current scope - so after applying a theme again (which re-runs oh-my-posh in the
  session), a second reset left the themed prompt in place. Reset now sets the
  global prompt straight back to PowerShell's default and clears oh-my-posh's
  `POSH_*` environment, so repeated resets are reliable.

## [0.4.1]

### Added
- **Reset to default.** A new `[4] Reset` menu item and `Reset-PoshPalette` command
  return the terminal to the stock default look (Campbell scheme, Cascadia Mono, no
  opacity/acrylic, the default PowerShell prompt) - a clean, repeatable baseline,
  handy for demoing the before/after. Unlike `Restore-PoshPalette` (which restores
  your most recent backup), this sets known defaults regardless of prior state. It
  backs up first and preserves your `settings.json` comments.

## [0.4.0]

### Changed
- **Every bundled theme now uses a generated, scheme-matched prompt, so what you
  install matches the website.** Previously some themes referenced external
  oh-my-posh themes (e.g. `dracula`, `night-owl`, `tokyonight-storm`) that only
  loaded if you had those `.omp.json` files under `POSH_THEMES_PATH` and used
  their own hard-coded colors, while the showcase drew a different prompt shape
  entirely. Generated prompts are written by PoshPalette itself, always load, and
  always take the theme's colors.
- **Four new prompt styles** join `auto` / `auto-minimal` / `auto-powerline` /
  `auto-robby`: **`auto-twoline`**, **`auto-arrow`**, **`auto-lambda`**, and
  **`auto-pure`**. Each bundled theme is assigned the style the gallery shows, so
  the site, the in-app preview, and your terminal all agree.

### Removed
- The referenced oh-my-posh prompt entries (agnoster, atomic, dracula, etc.) are
  no longer listed in the picker, since they depended on external files and could
  silently fail to load. You can still use any oh-my-posh theme by passing its
  name to `Set-PoshPalettePrompt` or typing it in Detail mode.

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
