"""Posh Palette for Linux shells and terminals.

A port of the PowerShell module's apply path to POSIX: the same JSON catalogs
(themes/, schemes/, palettes/, prompts/, fonts.json) drive four layers -

  terminal   scheme, font, size, opacity -> the terminal's own config file
             (Ghostty, kitty, Alacritty, foot, WezTerm) or OSC escapes for any
             other terminal
  input      command-line syntax colors -> zsh-syntax-highlighting /
             zsh-autosuggestions, fish_color_*, ble.sh
  output     LS_COLORS / GREP_COLORS / zsh completion colors
  prompt     an oh-my-posh config generated from the scheme (bash, zsh, fish)

Standard library only, so it runs on any distro with Python 3.8+.
"""

import re
from pathlib import Path

DATA_ROOT = Path(__file__).resolve().parent.parent.parent


def version():
    """The module version, read from the PowerShell manifest so both share one."""
    try:
        text = (DATA_ROOT / "PoshPalette.psd1").read_text(encoding="utf-8")
        m = re.search(r"ModuleVersion\s*=\s*'([^']+)'", text)
        return m.group(1) if m else None
    except OSError:
        return None
