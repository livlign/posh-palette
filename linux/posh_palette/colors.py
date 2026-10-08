"""Color helpers: hex math, OSC escape sequences, and LS_COLORS / GREP_COLORS."""

import re

ANSI = ("black", "red", "green", "yellow", "blue", "purple", "cyan", "white",
        "brightBlack", "brightRed", "brightGreen", "brightYellow",
        "brightBlue", "brightPurple", "brightCyan", "brightWhite")

ESC = "\x1b"
ST = ESC + "\\"   # String Terminator - spec-correct; BEL also works

_HEX = re.compile(r"^#?([0-9A-Fa-f]{6})$")


def hex6(h):
    """'#RRGGBB' / 'RRGGBB' -> 'rrggbb'. Raises on anything else."""
    m = _HEX.match((h or "").strip())
    if not m:
        raise ValueError(f"Expected a #RRGGBB hex color, got '{h}'.")
    return m.group(1).lower()


def rgb(h):
    x = hex6(h)
    return int(x[0:2], 16), int(x[2:4], 16), int(x[4:6], 16)


def blend(a, b, t):
    ra, ga, ba = rgb(a)
    rb, gb, bb = rgb(b)
    return "#{:02X}{:02X}{:02X}".format(int(ra + (rb - ra) * t), int(ga + (gb - ga) * t), int(ba + (bb - ba) * t))


def is_dark(h):
    """Perceived-luminance test used for the Dark/Light filter (matches the site)."""
    try:
        r, g, b = rgb(h)
    except ValueError:
        return True
    return ((0.2126 * r) + (0.7152 * g) + (0.0722 * b)) / 255 < 0.5


def sgr_fg(h):
    """The SGR parameter string for a truecolor foreground: '38;2;R;G;B'."""
    return "38;2;{};{};{}".format(*rgb(h))


def fg(h, text):
    return f"{ESC}[{sgr_fg(h)}m{text}{ESC}[0m"


# --- OSC ----------------------------------------------------------------------

def osc_color(h):
    """#RRGGBB -> rgb:rr/gg/bb, the most portable XParseColor form."""
    x = hex6(h)
    return f"rgb:{x[0:2]}/{x[2:4]}/{x[4:6]}"


def osc_sequence(scheme):
    """The OSC 4/10/11/12/17 bytes that recolor a running terminal from a scheme's
    colors (16 ANSI + foreground/background/cursor/selection)."""
    pairs = [f"{i};{osc_color(scheme[name])}" for i, name in enumerate(ANSI) if scheme.get(name)]
    out = []
    if pairs:
        out.append(f"{ESC}]4;{';'.join(pairs)}{ST}")
    for code, key in ((10, "foreground"), (11, "background"), (12, "cursorColor"), (17, "selectionBackground")):
        if scheme.get(key):
            out.append(f"{ESC}]{code};{osc_color(scheme[key])}{ST}")
    return "".join(out)


def osc_reset_sequence():
    """Reset palette, fg, bg, cursor, selection to the terminal's configured values."""
    return "".join(f"{ESC}]{c}{ST}" for c in (104, 110, 111, 112, 117))


# --- Output colors ------------------------------------------------------------

# category -> file extensions, the same buckets the pwsh $PSStyle.FileInfo layer
# uses plus the common Linux ones.
EXT_CATEGORIES = {
    "code": (".ps1", ".psm1", ".psd1", ".cs", ".py", ".js", ".ts", ".go", ".rs", ".rb", ".java", ".c",
             ".cpp", ".h", ".sh", ".bash", ".zsh", ".fish", ".lua", ".pl", ".php", ".kt", ".swift"),
    "data": (".json", ".xml", ".yaml", ".yml", ".toml", ".ini", ".csv", ".config", ".conf", ".env"),
    "docs": (".md", ".txt", ".rst", ".log", ".pdf"),
    "arch": (".zip", ".tar", ".gz", ".7z", ".rar", ".bz2", ".xz", ".zst", ".tgz", ".deb", ".rpm"),
    "media": (".png", ".jpg", ".jpeg", ".gif", ".svg", ".mp4", ".mp3", ".ico", ".webp", ".mkv", ".flac"),
}


def ls_colors(theme):
    """An LS_COLORS string (GNU ls, eza, fd, tree, zsh completion) from a resolved
    theme. Only the keys we set are overridden; ls keeps its defaults for the rest."""
    prl, ps = theme["psReadLine"], theme["psStyle"]
    cat_color = {"code": prl.get("Command"), "data": prl.get("Variable"), "docs": prl.get("Parameter"),
                 "arch": prl.get("Number"), "media": prl.get("Operator")}
    parts = []
    if ps.get("Directory"):
        parts.append(f"di=1;{sgr_fg(ps['Directory'])}")
    if prl.get("String"):
        parts.append(f"ex=1;{sgr_fg(prl['String'])}")
    if prl.get("Parameter"):
        parts.append(f"ln={sgr_fg(prl['Parameter'])}")
    if ps.get("Error"):
        parts.append(f"or={sgr_fg(ps['Error'])}")   # broken symlinks
    for cat, exts in EXT_CATEGORIES.items():
        col = cat_color.get(cat)
        if col:
            parts.extend(f"*{x}={sgr_fg(col)}" for x in exts)
    return ":".join(parts)


def grep_colors(theme):
    prl, ps = theme["psReadLine"], theme["psStyle"]
    parts = []
    if ps.get("Error"):
        parts.append(f"mt=1;{sgr_fg(ps['Error'])}")
    if prl.get("Command"):
        parts.append(f"fn={sgr_fg(prl['Command'])}")
    if prl.get("Number"):
        parts.append(f"ln={sgr_fg(prl['Number'])}")
    if prl.get("Comment"):
        parts.append(f"se={sgr_fg(prl['Comment'])}")
    return ":".join(parts)
