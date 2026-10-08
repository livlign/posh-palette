"""Setup check: what's ready, what to fix (the Linux side of Test-PoshPaletteSetup)."""

import glob
import os
import sys

from . import fonts, ohmyposh, shells, terminals
from .catalog import current_composition, resolve


def _zsh_plugin(name):
    pats = [f"/usr/share/{name}/{name}.zsh", f"/usr/share/zsh/plugins/{name}/{name}.zsh",
            f"/usr/local/share/{name}/{name}.zsh", os.path.expanduser(f"~/.oh-my-zsh/custom/plugins/{name}"),
            os.path.expanduser(f"~/.zsh/{name}"), os.path.expanduser(f"~/.local/share/zinit/plugins/*{name}*"),
            "/opt/homebrew/share/" + name, "/home/linuxbrew/.linuxbrew/share/" + name]
    return any(glob.glob(p) for p in pats)


def checks():
    """(status, label, detail) rows: status is ok / warn / info."""
    rows = []
    v = sys.version_info
    rows.append(("ok", "Python", f"{v.major}.{v.minor}.{v.micro}"))

    term = terminals.current_terminal()
    a = terminals.adapter(term)
    if a:
        rows.append(("ok" if a.managed() else "info", "Terminal",
                     f"{a.label} - config {a.config_path()}" + ("" if a.managed() else " (not themed yet)")))
    else:
        rows.append(("info", "Terminal", f"{term} - themed via OSC escapes from the shell init"))
    tc = os.environ.get("COLORTERM", "")
    rows.append(("ok" if tc in ("truecolor", "24bit") else "warn", "Truecolor",
                 "yes" if tc in ("truecolor", "24bit") else "COLORTERM isn't truecolor/24bit; previews may look off"))
    if os.environ.get("TMUX"):
        rows.append(("warn", "tmux", "OSC colors don't pass through tmux; theme the outer terminal instead"))
    others = [x.label for x in terminals.installed_adapters() if x.name != term]
    if others:
        rows.append(("info", "Also themed", ", ".join(others)))

    for s in shells.SHELLS:
        if not s.installed():
            continue
        if s.wired():
            rows.append(("ok", f"Shell: {s.name}", f"wired ({s.rc_path()})"))
        elif s.should_wire():
            rows.append(("info", f"Shell: {s.name}", "will be wired on the next apply"))
        else:
            rows.append(("info", f"Shell: {s.name}", f"installed, not used (no {s.rc_path().name})"))
    if any(s.name == "zsh" and s.installed() for s in shells.SHELLS):
        have = _zsh_plugin("zsh-syntax-highlighting")
        rows.append(("ok" if have else "info", "zsh input colors",
                     "zsh-syntax-highlighting found" if have else "install zsh-syntax-highlighting for command-line colors"))

    omp = ohmyposh.version()
    rows.append(("ok", "oh-my-posh", omp) if omp else ("warn", "oh-my-posh", f"not installed - prompt layer inactive. {ohmyposh.INSTALL_CMD}"))

    fams = fonts.installed_families()
    if fams is None:
        rows.append(("warn", "Fonts", "fc-list not found; can't check installed fonts"))
    else:
        try:
            face = resolve(current_composition())["terminal"]["font"]
        except LookupError:
            face = None
        if face:
            ok = fonts.is_installed(face, fams)
            entry = fonts.lookup(face)
            hint = f" - palette font-install {entry['id']}" if entry and not ok else ""
            rows.append(("ok" if ok else "warn", "Theme font", f"{face} {'installed' if ok else 'missing'}{hint}"))
        nerd = fonts.any_nerd_font(fams)
        rows.append(("ok" if nerd else "warn", "Nerd Fonts",
                     f"{len(nerd)} installed" if nerd else "none - prompt glyphs need one (palette font-install jetbrains)"))
    return rows
