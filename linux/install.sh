#!/bin/sh
# Install Posh Palette for Linux shells: links `posh-palette` (and `palette`,
# when that name is free) into ~/.local/bin. Re-run after moving the clone.
#   ./linux/install.sh            install
#   ./linux/install.sh --uninstall  remove the links (run `palette reset` first
#                                 to drop the theme from your configs)
set -e

here=$(cd "$(dirname "$0")" && pwd)
bin="${XDG_BIN_HOME:-$HOME/.local/bin}"

if ! command -v python3 >/dev/null 2>&1; then
  echo "posh-palette needs python3 (3.8+). Install it with your package manager first." >&2
  exit 1
fi
python3 -c 'import sys; sys.exit(sys.version_info < (3, 8))' || {
  echo "posh-palette needs Python 3.8 or newer." >&2; exit 1; }

ours() { [ -L "$1" ] && [ "$(readlink "$1")" = "$here/posh-palette" ]; }

if [ "${1-}" = "--uninstall" ]; then
  for name in posh-palette palette; do
    if ours "$bin/$name"; then rm "$bin/$name"; echo "removed $bin/$name"; fi
  done
  exit 0
fi

mkdir -p "$bin"
ln -sfn "$here/posh-palette" "$bin/posh-palette"
echo "linked $bin/posh-palette"

existing=$(command -v palette 2>/dev/null || true)
if [ -z "$existing" ] || [ "$existing" = "$bin/palette" ] || ours "$bin/palette"; then
  ln -sfn "$here/posh-palette" "$bin/palette"
  echo "linked $bin/palette"
else
  echo "skipped 'palette' ($existing already exists) - use 'posh-palette' instead"
fi

case ":$PATH:" in
  *":$bin:"*) ;;
  *) echo "note: $bin isn't on your PATH yet - add it in your shell rc." ;;
esac
echo
echo "Run 'palette' to pick a theme, or 'palette doctor' to check your setup."
