# Posh Palette for Linux shells

The same themes, picker and composition model as the PowerShell module, for
**bash, zsh, fish** (and ksh/mksh/dash for colors) on any Linux terminal. One
`python3` script, standard library only, reading the repo's own `themes/`,
`schemes/`, `palettes/`, `prompts/` and `fonts.json`, so the two front ends
always offer the same catalog.

## Install

```sh
git clone https://github.com/livlign/posh-palette ~/Code/posh-palette
~/Code/posh-palette/linux/install.sh      # links posh-palette + palette into ~/.local/bin
palette                                   # pick a theme
```

Needs Python 3.8+. oh-my-posh (for the prompt) and a Nerd Font are optional;
the first apply that needs them offers to install them per-user, no root:
oh-my-posh into `~/.local/bin`, fonts into `~/.local/share/fonts`.

## The four layers on Linux

| Layer | What it colors | Where it goes |
|-------|----------------|---------------|
| Terminal | scheme, font, size, opacity, blur | Ghostty / kitty / Alacritty / foot config (managed block); OSC escapes for every other terminal |
| Input | the command line you type | zsh-syntax-highlighting + zsh-autosuggestions, `fish_color_*`, ble.sh faces |
| Output | `ls`, `eza`, `fd`, `tree`, `grep`, completion lists | `LS_COLORS`, `GREP_COLORS`, zsh `list-colors` |
| Prompt | the prompt | an oh-my-posh config generated from the scheme (bash, zsh, fish) |

How it's wired:

- Each apply writes one init script per shell to `~/.poshpalette/shell/`
  (`init.zsh`, `init.bash`, `init.fish`, `init.sh`). Your rc file gets a single
  managed line that sources it (`~/.zshrc`, `~/.bashrc`, `~/.kshrc`,
  `~/.mkshrc`; fish uses `~/.config/fish/conf.d/posh-palette.fish`). Re-applying
  a theme rewrites the init script and leaves the rc file alone.
- A shell gets wired when it's installed and in use: its rc file exists or it's
  your login shell. fish is wired whenever it's installed.
- The init scripts define a `palette` function that runs the picker and then
  re-sources the script, so a new theme reaches the shell you ran it from with
  no restart.
- Terminals whose config PoshPalette writes (Ghostty, kitty, Alacritty, foot)
  are skipped by the OSC step. Any other terminal (GNOME Terminal, Konsole,
  Tilix, xterm, WezTerm, …) gets its colors from OSC 4/10/11/12/17 each time a
  shell starts. Inside tmux/screen no OSC is sent; theme the outer terminal.
- Applying recolors the current terminal straight away. For Ghostty and kitty
  font/size/opacity changes, reload the config (`ctrl+shift+,` /
  `ctrl+shift+f5`). Alacritty reloads by itself.

## Commands

```sh
palette                              # interactive picker (Simple + Detail mode)
palette apply tokyo-night            # a full theme by id / name / path
palette apply nord --dry-run         # show what would change
palette scheme nord                  # swap one layer, keep the rest
palette colors dracula
palette prompt auto-twoline          # or any oh-my-posh theme name
palette font jetbrains               # fonts.json id or any installed face
palette set --opacity 90 --font-size 12 --blur on
palette list [themes|schemes|palettes|prompts|fonts]
palette doctor                       # what's ready, what to fix
palette reset                        # remove everything PoshPalette wrote
palette osc eclipse [--show-bytes]   # recolor only this session
palette import ./Dracula.itermcolors --save   # iTerm2, base16, WT, Ghostty, kitty
palette font-install jetbrains
palette refresh                      # pull new community themes now
```

Use `posh-palette` instead of `palette` wherever that name is taken.
`~/.poshpalette/current.json` (the active composition) and the community catalog
cache are the same ones the pwsh module uses, so both front ends build on the
same look.

## Safety

- Every edit to a file you own sits in a `# >>> PoshPalette >>>` block, and the
  file is backed up to `<file>.poshpalette-<timestamp>.bak` before the first
  change. `palette reset` removes the blocks and the generated files, so your
  own config is left exactly as it was.
- Symlinked dotfiles (stow, chezmoi, …) are edited through the link, so the
  link survives.
- A font is only set once fontconfig reports it installed, so the terminal never
  ends up with a missing face.

## Tests

```sh
python3 -m unittest discover -s linux/tests -t linux/tests
```

Every generated init script is syntax-checked with each installed shell
(bash, zsh, sh, fish) and then run in it. When `pwsh` is on PATH, a parity test
checks that every prompt style matches the PowerShell generator exactly.
