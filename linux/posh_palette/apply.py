"""Orchestrator: apply a resolved theme to every layer, or reset them all.

Interaction (install a missing font? install oh-my-posh?) goes through an
`ask(question, detail) -> bool` callback so the CLI, the TUI and tests can each
answer it their own way. With no callback nothing is installed - the hint for
doing it by hand is reported instead.
"""

import sys
from pathlib import Path

from . import fonts, ohmyposh, shells, terminals
from .catalog import forget_current_composition, user_root
from .prompt import save_prompt


def cli_path():
    """The entry script the generated `palette` function calls back into."""
    return str(Path(sys.argv[0]).resolve()) if sys.argv and sys.argv[0] else "posh-palette"


class Report:
    """What an apply/reset did, as (status, text) lines: ok / info / warn."""

    def __init__(self):
        self.lines = []

    def ok(self, text):
        self.lines.append(("ok", text))

    def info(self, text):
        self.lines.append(("info", text))

    def warn(self, text):
        self.lines.append(("warn", text))


def _font_ok(theme, ask, report, dry_run):
    face = theme["terminal"].get("font")
    if not face:
        return False
    if fonts.is_installed(face):
        return True
    entry = fonts.lookup(face)
    fid = entry["id"] if entry else None
    if dry_run or not ask or not fid:
        hint = f" Install it with: palette font-install {fid}" if fid else " Install it, then pick it as your font."
        report.warn(f"Font '{face}' isn't installed - keeping your current terminal font.{hint}")
        return False
    if not ask(f"This theme uses '{face}', which isn't installed. Install it now?",
               "Downloads it from the nerd-fonts releases into ~/.local/share/fonts (no root)."):
        report.info(f"Kept your current font. Install later with: palette font-install {fid}")
        return False
    try:
        fonts.install(fid, log=lambda m: None)
    except Exception as e:  # network / zip errors: fall back, never abort the apply
        report.warn(f"Font install failed ({e}) - keeping your current terminal font.")
        return False
    report.ok(f"Installed '{face}'.")
    return True


def _ensure_ohmyposh(theme, ask, report, dry_run):
    if not ohmyposh.uses_ohmyposh(theme) or ohmyposh.path():
        return
    if dry_run or not ask:
        report.warn(f"The prompt needs oh-my-posh (not installed). Install it: {ohmyposh.INSTALL_CMD}")
        return
    if not ask("This theme's prompt needs oh-my-posh, which isn't installed. Install it now?",
               "Runs the official installer into ~/.local/bin (no root). Colors apply either way."):
        report.info(f"Skipped oh-my-posh; the prompt activates once it's installed: {ohmyposh.INSTALL_CMD}")
        return
    if ohmyposh.install():
        report.ok("Installed oh-my-posh into ~/.local/bin.")
    else:
        report.warn(f"oh-my-posh install failed. Try by hand: {ohmyposh.INSTALL_CMD}")


def apply_theme(theme, ask=None, dry_run=False, live=True):
    report = Report()
    pre = "[dry-run] would write" if dry_run else "wrote"

    # Layer 1: terminal config files + live OSC for the running terminal.
    font_ok = _font_ok(theme, ask, report, dry_run)
    managed = []
    for a in terminals.installed_adapters():
        try:
            changed, notes = a.apply(theme, font_ok, dry_run=dry_run)
        except OSError as e:
            report.warn(f"{a.label}: couldn't update {a.config_path()} ({e}).")
            continue
        if a.managed() or (dry_run and a.name != "wezterm"):
            managed.append(a.name)
        report.ok(f"{a.label}: {pre} {', '.join(str(p) for p in changed)}" if changed else f"{a.label}: already up to date")
        here = terminals.current_terminal() == a.name
        for n in notes:
            if not dry_run and (here or a.name == "wezterm"):
                report.info(n)
    if not dry_run and live and terminals.emit_live(theme["terminal"]["scheme"]):
        report.ok("Recolored this terminal (live).")
    if terminals.current_terminal() not in managed:
        report.info(f"Other terminals ({terminals.current_terminal()}) get the colors via OSC on each new shell.")

    # Layer 4 prerequisite: oh-my-posh + the generated prompt config.
    if not dry_run:
        _ensure_ohmyposh(theme, ask, report, dry_run)
    prompt_path = None
    p = theme.get("prompt") or {}
    if p.get("generated"):
        prompt_path = (user_root() / "prompts" / f"{p['name']}.omp.json") if dry_run else save_prompt(p["config"], p["name"])

    # Layers 2-4: shell init scripts + one-line rc wiring.
    shells.write_init_scripts(theme, managed, prompt_path, cli_path(), dry_run)
    wired = []
    for s in shells.SHELLS:
        if s.should_wire():
            try:
                s.wire(dry_run)
            except OSError as e:
                report.warn(f"{s.name}: couldn't update {s.rc_path()} ({e}).")
                continue
            wired.append(s.name)
    if wired:
        report.ok(f"Input/output colors + prompt {'would be ' if dry_run else ''}set for: {', '.join(wired)}")
    else:
        report.warn("No supported shell found to wire (bash, zsh, fish, ksh, mksh).")
    return report


def reset(dry_run=False, live=True):
    """Remove everything PoshPalette wrote; your own config is left as it was."""
    report = Report()
    for a in terminals.ADAPTERS:
        changed = a.remove(dry_run)
        if changed:
            report.ok(f"{a.label}: removed PoshPalette settings ({', '.join(str(p) for p in changed)})")
    for s in shells.SHELLS:
        if s.unwire(dry_run):
            report.ok(f"{s.name}: removed the PoshPalette line from {s.rc_path()}")
    shells.remove_init_scripts(dry_run)
    if not dry_run:
        forget_current_composition()
        if live:
            terminals.emit_live(None, reset=True)
    report.info("Open a new shell for the prompt and input/output colors to revert.")
    return report
