"""Import outside color schemes into the catalog (port of src/Import.ps1, plus
the Ghostty and kitty theme formats common on Linux). Saved schemes go to the
user cache, ~/.poshpalette/catalog/schemes/, so the repo stays clean."""

import json
import plistlib
import re
from pathlib import Path

from .catalog import cache_root
from .colors import ANSI, hex6


def _hex(h):
    return "#" + hex6(h).upper()


def from_iterm(data):
    plist = plistlib.loads(data)

    def comp(key):
        d = plist.get(key)
        if not d:
            return None
        return "#{:02X}{:02X}{:02X}".format(*(int(round(float(d.get(f"{c} Component", 0)) * 255))
                                               for c in ("Red", "Green", "Blue")))
    colors = {ANSI[i]: comp(f"Ansi {i} Color") for i in range(16)}
    colors["background"] = comp("Background Color")
    colors["foreground"] = comp("Foreground Color")
    colors["cursorColor"] = comp("Cursor Color") or colors["foreground"]
    colors["selectionBackground"] = comp("Selection Color") or colors["background"]
    return colors


def from_base16(text):
    b = {}
    for m in re.finditer(r'^\s*(base0[0-9A-Fa-f])\s*:\s*"?#?([0-9A-Fa-f]{6})"?', text, re.M):
        b[m.group(1).lower()] = "#" + m.group(2).upper()
    if len(b) < 16:
        raise ValueError(f"Not a base16 scheme (found {len(b)}/16 base colors).")
    return {
        "black": b["base00"], "red": b["base08"], "green": b["base0b"], "yellow": b["base0a"],
        "blue": b["base0d"], "purple": b["base0e"], "cyan": b["base0c"], "white": b["base05"],
        "brightBlack": b["base03"], "brightRed": b["base08"], "brightGreen": b["base0b"], "brightYellow": b["base0a"],
        "brightBlue": b["base0d"], "brightPurple": b["base0e"], "brightCyan": b["base0c"], "brightWhite": b["base07"],
        "background": b["base00"], "foreground": b["base05"],
        "cursorColor": b["base05"], "selectionBackground": b["base02"],
    }


def _strip_jsonc(text):
    text = re.sub(r'("(?:\\.|[^"\\])*")|//[^\n]*|/\*.*?\*/', lambda m: m.group(1) or "", text, flags=re.S)
    return re.sub(r",(\s*[}\]])", r"\1", text)


def from_wt(text):
    s = json.loads(_strip_jsonc(text))
    keys = list(ANSI) + ["background", "foreground", "cursorColor", "selectionBackground"]
    return {k: s[k] for k in keys if s.get(k)}


def from_ghostty(text):
    colors = {}
    for line in text.splitlines():
        m = re.match(r"^\s*([a-z-]+)\s*=\s*(.+?)\s*$", line)
        if not m:
            continue
        key, val = m.groups()
        if key == "palette":
            pm = re.match(r"^(\d+)\s*=\s*#?([0-9A-Fa-f]{6})$", val)
            if pm and int(pm.group(1)) < 16:
                colors[ANSI[int(pm.group(1))]] = _hex(pm.group(2))
        else:
            dest = {"background": "background", "foreground": "foreground", "cursor-color": "cursorColor",
                    "selection-background": "selectionBackground"}.get(key)
            if dest and re.match(r"^#?[0-9A-Fa-f]{6}$", val):
                colors[dest] = _hex(val)
    return colors


def from_kitty(text):
    colors = {}
    for line in text.splitlines():
        m = re.match(r"^\s*(\w+)\s+#?([0-9A-Fa-f]{6})\s*$", line)
        if not m:
            continue
        key, val = m.groups()
        cm = re.match(r"^color(\d+)$", key)
        if cm and int(cm.group(1)) < 16:
            colors[ANSI[int(cm.group(1))]] = _hex(val)
        else:
            dest = {"background": "background", "foreground": "foreground", "cursor": "cursorColor",
                    "selection_background": "selectionBackground"}.get(key)
            if dest:
                colors[dest] = _hex(val)
    return colors


def detect_format(path, text):
    ext = path.suffix.lower()
    if ext == ".itermcolors" or "<plist" in text:
        return "iterm"
    if ext in (".yaml", ".yml") or re.search(r"^\s*base0[0-9A-Fa-f]\s*:", text, re.M):
        return "base16"
    if ext == ".json" or text.lstrip().startswith("{"):
        return "wt"
    if re.search(r"^\s*palette\s*=\s*\d+=", text, re.M):
        return "ghostty"
    if re.search(r"^\s*color\d+\s+#", text, re.M):
        return "kitty"
    raise ValueError(f"Can't tell the format of {path}; pass --format.")


def import_scheme(path, id_=None, name=None, fmt="auto", save=False):
    path = Path(path).expanduser()
    raw = path.read_bytes()
    text = raw.decode("utf-8", errors="replace")
    if fmt == "auto":
        fmt = detect_format(path, text)
    colors = {"iterm": lambda: from_iterm(raw), "base16": lambda: from_base16(text), "wt": lambda: from_wt(text),
              "ghostty": lambda: from_ghostty(text), "kitty": lambda: from_kitty(text)}[fmt]()
    missing = [k for k in list(ANSI) + ["background", "foreground"] if not colors.get(k)]
    if missing:
        raise ValueError(f"Scheme is missing colors: {', '.join(missing)}")
    id_ = id_ or re.sub(r"(^-|-$)", "", re.sub(r"[^a-z0-9]+", "-", path.stem.lower()))
    name = name or id_.replace("-", " ").title()
    ordered = {k: colors[k] for k in ["background", "foreground", "cursorColor", "selectionBackground"] + list(ANSI) if colors.get(k)}
    scheme = {"id": id_, "name": name, "colors": ordered}
    dest = None
    if save:
        dest = cache_root() / "schemes" / f"{id_}.json"
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(json.dumps(scheme, indent=2) + "\n", encoding="utf-8")
    return scheme, dest
