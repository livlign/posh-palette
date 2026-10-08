"""Layer 1 on Linux: the terminal's scheme, font, size and opacity.

Terminals with a plain-text config get the theme written into it (a managed
block, or a PoshPalette-owned file the config includes). Every other terminal -
GNOME Terminal, Konsole, xterm, Tilix, WezTerm's Lua config... - gets the colors
via OSC escapes, emitted live and again by the shell init on every new session.
"""

import os
import re
import shutil
from pathlib import Path

from . import files
from .catalog import home
from .colors import ANSI, hex6, osc_reset_sequence, osc_sequence


def config_home():
    return Path(os.environ.get("XDG_CONFIG_HOME") or home() / ".config")


def current_terminal(env=None):
    """Best guess at the terminal this process runs in (an adapter name or a label)."""
    e = os.environ if env is None else env
    term, prog = e.get("TERM", ""), e.get("TERM_PROGRAM", "")
    if prog == "ghostty" or term == "xterm-ghostty" or e.get("GHOSTTY_RESOURCES_DIR"):
        return "ghostty"
    if e.get("KITTY_WINDOW_ID") or term == "xterm-kitty":
        return "kitty"
    if e.get("ALACRITTY_WINDOW_ID") or e.get("ALACRITTY_SOCKET") or term == "alacritty":
        return "alacritty"
    if prog == "WezTerm" or e.get("WEZTERM_PANE"):
        return "wezterm"
    if term.startswith("foot"):
        return "foot"
    if e.get("KONSOLE_VERSION"):
        return "konsole"
    if e.get("VTE_VERSION"):
        return "vte"
    return prog or term or "unknown"


def osc_capable(env=None):
    """Heuristic: does the current terminal honor OSC color-setting? Multiplexers
    need passthrough we don't emit, so they're excluded."""
    e = os.environ if env is None else env
    if e.get("TMUX") or e.get("STY"):
        return False
    if e.get("TERM", "") in ("", "dumb", "linux"):
        return False
    return True


def emit_live(scheme_colors, reset=False):
    """Recolor the current terminal now (per-session). Returns True if written."""
    if not osc_capable():
        return False
    seq = osc_reset_sequence() if reset else osc_sequence(scheme_colors)
    try:
        with open("/dev/tty", "w", encoding="utf-8") as tty:
            tty.write(seq)
            tty.flush()
        return True
    except OSError:
        return False


# --- Adapters -----------------------------------------------------------------

class Adapter:
    name = ""
    label = ""
    binary = ""

    def installed(self):
        return bool(shutil.which(self.binary)) or self.config_path().exists()

    def config_path(self):
        raise NotImplementedError

    def apply(self, theme, font_ok, dry_run=False):
        """Write the theme. Returns (changed_paths, notes)."""
        raise NotImplementedError

    def remove(self, dry_run=False):
        """Undo apply(). Returns changed paths."""
        changed = []
        if files.remove_block(self.config_path(), dry_run):
            changed.append(self.config_path())
        for p in self.owned_files():
            if p.exists():
                if not dry_run:
                    p.unlink()
                changed.append(p)
        return changed

    def owned_files(self):
        return []

    def managed(self):
        """Does the terminal's config currently carry our theme?"""
        return files.has_block(self.config_path())


def _opacity(theme):
    return max(0.1, min(1.0, float(theme["terminal"]["opacity"]) / 100))


class Ghostty(Adapter):
    name, label, binary = "ghostty", "Ghostty", "ghostty"

    def config_path(self):
        d = config_home() / "ghostty"
        for n in ("config.ghostty", "config"):
            if (d / n).exists():
                return d / n
        return d / "config.ghostty"

    def body(self, theme, font_ok):
        t, sc = theme["terminal"], theme["terminal"]["scheme"]
        lines = [f"# Theme: {theme.get('name') or sc.get('name')}"]
        lines += [f"palette = {i}=#{hex6(sc[n])}" for i, n in enumerate(ANSI) if sc.get(n)]
        for key, src in (("background", "background"), ("foreground", "foreground"),
                         ("cursor-color", "cursorColor"), ("selection-background", "selectionBackground")):
            if sc.get(src):
                lines.append(f"{key} = #{hex6(sc[src])}")
        if font_ok and t.get("font"):
            # font-family is repeatable (fallbacks); "" resets the list so ours wins.
            lines += ['font-family = ""', f'font-family = "{t["font"]}"']
        lines.append(f"font-size = {t['fontSize']}")
        lines.append(f"background-opacity = {_opacity(theme):g}")
        lines.append(f"background-blur = {'true' if t.get('useAcrylic') else 'false'}")
        return "\n".join(lines)

    def apply(self, theme, font_ok, dry_run=False):
        path = self.config_path()
        changed = [path] if files.upsert_block(path, self.body(theme, font_ok), dry_run=dry_run) else []
        return changed, ["Ghostty: colors are live now; press ctrl+shift+, (reload config) for font/size/opacity."]


class Kitty(Adapter):
    name, label, binary = "kitty", "kitty", "kitty"

    def config_path(self):
        return config_home() / "kitty" / "kitty.conf"

    def body(self, theme, font_ok):
        t, sc = theme["terminal"], theme["terminal"]["scheme"]
        lines = [f"# Theme: {theme.get('name') or sc.get('name')}"]
        for key, src in (("foreground", "foreground"), ("background", "background"),
                         ("cursor", "cursorColor"), ("selection_background", "selectionBackground")):
            if sc.get(src):
                lines.append(f"{key} #{hex6(sc[src])}")
        lines += [f"color{i} #{hex6(sc[n])}" for i, n in enumerate(ANSI) if sc.get(n)]
        if font_ok and t.get("font"):
            lines.append(f"font_family {t['font']}")
        lines.append(f"font_size {t['fontSize']}")
        lines.append(f"background_opacity {_opacity(theme):g}")
        lines.append(f"background_blur {32 if t.get('useAcrylic') else 0}")
        return "\n".join(lines)

    def apply(self, theme, font_ok, dry_run=False):
        path = self.config_path()
        changed = [path] if files.upsert_block(path, self.body(theme, font_ok), dry_run=dry_run) else []
        return changed, ["kitty: colors are live now; press ctrl+shift+f5 (reload config) for font/size/opacity."]


class Alacritty(Adapter):
    name, label, binary = "alacritty", "Alacritty", "alacritty"
    _NAMES = ("black", "red", "green", "yellow", "blue", "magenta", "cyan", "white")

    def config_path(self):
        return config_home() / "alacritty" / "alacritty.toml"

    def theme_path(self):
        return config_home() / "alacritty" / "posh-palette.toml"

    def owned_files(self):
        return [self.theme_path()]

    def theme_toml(self, theme, font_ok):
        t, sc = theme["terminal"], theme["terminal"]["scheme"]
        q = lambda k: f'"#{hex6(sc[k])}"'  # noqa: E731
        out = [f"# Generated by PoshPalette - theme: {theme.get('name') or sc.get('name')}", ""]
        out += ["[colors.primary]", f"background = {q('background')}", f"foreground = {q('foreground')}", ""]
        if sc.get("cursorColor"):
            out += ["[colors.cursor]", f"cursor = {q('cursorColor')}", ""]
        if sc.get("selectionBackground"):
            out += ["[colors.selection]", f"background = {q('selectionBackground')}", ""]
        for table, offset in (("normal", 0), ("bright", 8)):
            out.append(f"[colors.{table}]")
            out += [f"{n} = {q(ANSI[i + offset])}" for i, n in enumerate(self._NAMES) if sc.get(ANSI[i + offset])]
            out.append("")
        out += ["[font]", f"size = {float(t['fontSize']):g}", ""]
        if font_ok and t.get("font"):
            out += ["[font.normal]", f'family = "{t["font"]}"', ""]
        out += ["[window]", f"opacity = {_opacity(theme):g}", f"blur = {'true' if t.get('useAcrylic') else 'false'}", ""]
        return "\n".join(out)

    def apply(self, theme, font_ok, dry_run=False):
        changed, notes = [], []
        if files.write_generated(self.theme_path(), self.theme_toml(theme, font_ok), dry_run):
            changed.append(self.theme_path())
        path = self.config_path()
        text = files.read_text(path)
        base = files.without_block(text)   # the user's own config
        ref = f'"{self.theme_path()}"'
        # Imports load before the main file, so the user's own colors still win.
        if ref in base:
            pass  # wired by hand
        elif re.search(r"^\s*(general\.)?import\s*=", base, re.M):
            notes.append(f"Alacritty: add {ref} to the `import` list in {path} to use the theme.")
        elif re.search(r"^\s*\[general\]\s*$", base, re.M):
            # A [general] table exists: the block sits right under its header.
            if files.BLOCK_START in text:
                if files.upsert_block(path, f"import = [{ref}]", dry_run=dry_run):
                    changed.append(path)
            else:
                new = re.sub(r"^(\s*\[general\]\s*)$", lambda m: m.group(1) + "\n" + files.render_block(f"import = [{ref}]").rstrip("\n"),
                             text, count=1, flags=re.M)
                if not dry_run:
                    files.backup(path)
                    files.write_text(path, new)
                changed.append(path)
        elif files.upsert_block(path, f"general.import = [{ref}]", position="start", dry_run=dry_run):
            changed.append(path)
        return changed, notes


class Foot(Adapter):
    name, label, binary = "foot", "foot", "foot"

    def config_path(self):
        return config_home() / "foot" / "foot.ini"

    def theme_path(self):
        return config_home() / "foot" / "posh-palette.ini"

    def owned_files(self):
        return [self.theme_path()]

    def theme_ini(self, theme, font_ok):
        t, sc = theme["terminal"], theme["terminal"]["scheme"]
        out = [f"# Generated by PoshPalette - theme: {theme.get('name') or sc.get('name')}", "[main]"]
        if font_ok and t.get("font"):
            out.append(f"font={t['font']}:size={t['fontSize']}")
        if sc.get("cursorColor"):
            out += ["[cursor]", f"color={hex6(sc['background'])} {hex6(sc['cursorColor'])}"]
        out += ["[colors]", f"alpha={_opacity(theme):g}",
                f"foreground={hex6(sc['foreground'])}", f"background={hex6(sc['background'])}"]
        if sc.get("selectionBackground"):
            out.append(f"selection-background={hex6(sc['selectionBackground'])}")
        for i, n in enumerate(ANSI):
            if sc.get(n):
                out.append(f"{'regular' if i < 8 else 'bright'}{i % 8}={hex6(sc[n])}")
        return "\n".join(out) + "\n"

    def apply(self, theme, font_ok, dry_run=False):
        changed = []
        if files.write_generated(self.theme_path(), self.theme_ini(theme, font_ok), dry_run):
            changed.append(self.theme_path())
        # Lines before the first [section] belong to [main], where include= lives.
        if files.upsert_block(self.config_path(), f"include={self.theme_path()}", position="start", dry_run=dry_run):
            changed.append(self.config_path())
        return changed, ["foot: colors are live now; new foot windows pick up font/opacity."]


class WezTerm(Adapter):
    """WezTerm's config is Lua, which we don't edit: install the scheme as a named
    color scheme and rely on OSC (live + shell init) for the running session."""
    name, label, binary = "wezterm", "WezTerm", "wezterm"

    def config_path(self):
        return config_home() / "wezterm" / "colors" / "PoshPalette.toml"

    def owned_files(self):
        return [self.config_path()]

    def managed(self):
        return False   # colors still arrive via OSC

    def apply(self, theme, font_ok, dry_run=False):
        sc = theme["terminal"]["scheme"]
        q = lambda k: f'"#{hex6(sc[k])}"'  # noqa: E731
        arr = lambda r: "[" + ", ".join(q(ANSI[i]) for i in r) + "]"  # noqa: E731
        text = "\n".join([
            "# Generated by PoshPalette", "[colors]",
            f"foreground = {q('foreground')}", f"background = {q('background')}",
            f"cursor_bg = {q('cursorColor' if sc.get('cursorColor') else 'foreground')}",
            f"selection_bg = {q('selectionBackground' if sc.get('selectionBackground') else 'brightBlack')}",
            f"ansi = {arr(range(8))}", f"brights = {arr(range(8, 16))}", "",
            "[metadata]", 'name = "PoshPalette"', "",
        ])
        changed = [self.config_path()] if files.write_generated(self.config_path(), text, dry_run) else []
        return changed, ['WezTerm: for font/opacity too, set config.color_scheme = "PoshPalette" in wezterm.lua.']


ADAPTERS = (Ghostty(), Kitty(), Alacritty(), Foot(), WezTerm())


def adapter(name):
    return next((a for a in ADAPTERS if a.name == name), None)


def installed_adapters():
    return [a for a in ADAPTERS if a.installed()]
