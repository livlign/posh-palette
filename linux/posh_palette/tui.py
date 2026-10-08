"""The interactive picker (Simple + Detail modes) - port of src/Tui.ps1.

Hand-rolled with termios + truecolor ANSI on the alternate screen, so there are
no dependencies. Every screen is drawn as one frame string and written at once.
"""

import os
import select
import shutil
import sys
import termios
import tty
import unicodedata

from . import apply as applier
from . import doctor, remote, version
from .catalog import (catalog, catalog_item, current_composition, fonts, resolve,
                      save_current_composition, themes)
from .colors import blend, is_dark, rgb

E = "\x1b"
RST = f"{E}[0m"
WHITE, GRAY, DIM, CYAN, GREEN, YELLOW, RED = (f"{E}[97m", f"{E}[37m", f"{E}[90m", f"{E}[36m",
                                              f"{E}[32m", f"{E}[33m", f"{E}[31m")
PILL = f"{E}[30;47m"


# --- terminal plumbing --------------------------------------------------------

def width(s):
    """Display width (wide glyphs take 2 cells, combining marks 0)."""
    w = 0
    for ch in s:
        if unicodedata.combining(ch):
            continue
        w += 2 if unicodedata.east_asian_width(ch) in ("W", "F") else 1
    return w


def clip(s, room):
    out, w = [], 0
    for ch in s:
        cw = 0 if unicodedata.combining(ch) else (2 if unicodedata.east_asian_width(ch) in ("W", "F") else 1)
        if w + cw > room:
            break
        out.append(ch)
        w += cw
    return "".join(out), w


def pad(s, n):
    return s + " " * max(0, n - width(s))


class Screen:
    """cbreak mode on the alternate screen, cursor hidden; restored on exit."""

    def __enter__(self):
        self.fd = sys.stdin.fileno()
        self.saved = termios.tcgetattr(self.fd)
        tty.setcbreak(self.fd)
        sys.stdout.write(f"{E}[?1049h{E}[?25l")
        sys.stdout.flush()
        return self

    def __exit__(self, *exc):
        termios.tcsetattr(self.fd, termios.TCSADRAIN, self.saved)
        sys.stdout.write(f"{RST}{E}[?25h{E}[?1049l")
        sys.stdout.flush()

    def size(self):
        s = shutil.get_terminal_size((120, 30))
        return s.columns, s.lines

    def draw(self, lines, overlays=()):
        """Full redraw: left-column lines from row 1, then positioned overlays
        given as (row, col, text) - rows/cols 0-based."""
        cols, rows = self.size()
        out = [f"{E}[H{E}[2J"]
        for i, line in enumerate(lines[:rows]):
            out.append(f"{E}[{i + 1};1H{line}{RST}")
        for r, c, text in overlays:
            if r < rows:
                out.append(f"{E}[{r + 1};{c + 1}H{text}{RST}")
        sys.stdout.write("".join(out))
        sys.stdout.flush()

    def _read(self, timeout=None):
        r, _, _ = select.select([self.fd], [], [], timeout)
        return os.read(self.fd, 1) if r else b""

    def key(self):
        b = self._read()
        if b == b"\x1b":
            seq = b""
            while True:
                nxt = self._read(0.03)
                if not nxt:
                    break
                seq += nxt
                if len(seq) >= 2 and (nxt.isalpha() or nxt == b"~"):
                    break
            return {b"[A": "up", b"OA": "up", b"[B": "down", b"OB": "down", b"[C": "right", b"OC": "right",
                    b"[D": "left", b"OD": "left", b"[H": "home", b"[F": "end", b"[5~": "pgup",
                    b"[6~": "pgdn", b"[Z": "btab"}.get(seq, "esc" if not seq else "")
        if b in (b"\r", b"\n"):
            return "enter"
        if b in (b"\x7f", b"\x08"):
            return "backspace"
        if b == b"\t":
            return "tab"
        if b and b[0] >= 0xC0:   # UTF-8 lead byte: read the continuation bytes
            need = 1 if b[0] < 0xE0 else 2 if b[0] < 0xF0 else 3
            for _ in range(need):
                b += self._read(0.05)
        try:
            return b.decode("utf-8")
        except UnicodeDecodeError:
            return ""

    def read_line(self, lines, label):
        """Inline text entry under the given frame. Returns the text or None on Esc."""
        val = ""
        while True:
            self.draw(lines + ["", f"  {CYAN}{label}{RST}", f"  {WHITE}{val}█{RST}"])
            k = self.key()
            if k == "enter":
                return val.strip() or None
            if k == "esc":
                return None
            if k == "backspace":
                val = val[:-1]
            elif len(k) == 1 and k.isprintable():
                val += k


# --- shared UI pieces ---------------------------------------------------------

def rule(n=54):
    return f"  {DIM}{chr(0x2500) * n}{RST}"


def footer(hints):
    return ["", f"  {DIM}{'   ·   '.join(hints)}{RST}"]


def row(selected, text, w):
    if selected:
        return f"  {PILL} ❯ {pad(text, w)} {RST}"
    return f"     {DIM}{pad(text, w)} {RST}"


def window(total, idx, top, max_rows):
    """Scroll offset keeping idx visible."""
    if total <= max_rows:
        return 0
    if idx < top:
        top = idx
    elif idx >= top + max_rows:
        top = idx - max_rows + 1
    return max(0, min(top, total - max_rows))


def hexfg(h):
    r, g, b = rgb(h)
    return f"{E}[38;2;{r};{g};{b}m"


def hexbg(h):
    r, g, b = rgb(h)
    return f"{E}[48;2;{r};{g};{b}m"


# --- the preview --------------------------------------------------------------

PROJ = "~/proj/ccbit"


def prompt_parts(theme):
    """A short, scheme-colored stand-in for the theme's prompt as (hex, text)
    pairs, drawn ourselves so it stays inside the preview on every terminal."""
    sc = theme["terminal"]["scheme"]
    g = sc.get
    p = theme.get("prompt") or {}
    if not p.get("generated"):
        return [(g("cyan"), "❯❯ "), (g("blue"), f"{PROJ} "), (g("green"), "git:(main) ")]
    name = p.get("name", "")
    table = [
        ("minimal", [(g("purple"), "❯ ")]),
        ("twoline", [(g("cyan"), "╭─ "), (g("blue"), f"{PROJ} "), (g("green"), "● main "), (g("yellow"), "12:27 "), (g("cyan"), "╰─"), (g("purple"), "❯ ")]),
        ("clean", [(g("cyan"), "╭─ "), (g("yellow"), "♥ 12:27 | "), (g("blue"), f"{PROJ} "), (g("green"), "● main "), (g("purple"), "╰─ ")]),
        ("cert", [(g("red"), " user "), (g("green"), f" {PROJ} "), (g("cyan"), " git(main) "), (g("purple"), " 12:27 ")]),
        ("velvet", [(g("blue"), f" {PROJ} "), (g("cyan"), " main "), (g("yellow"), " 12ms "), (g("green"), " ✓ "), (g("purple"), " 12:27 ")]),
        ("powerline", [(g("blue"), f" {PROJ} "), (g("green"), " main "), (g("cyan"), " ✓ ")]),
        ("robby", [(g("cyan"), "❯❯ "), (g("blue"), f"{PROJ} "), (g("green"), "git:(main) "), (g("yellow"), "18:50 ")]),
        ("arrow", [(g("blue"), f"{PROJ} "), (g("cyan"), "on "), (g("green"), "● main "), (g("yellow"), "12:27 "), (g("purple"), "❯ ")]),
        ("lambda", [(g("purple"), "λ "), (g("blue"), f"{PROJ} "), (g("green"), "→ ")]),
        ("spaceship", [(g("blue"), f"{PROJ} "), (g("cyan"), "on "), (g("purple"), "⎇ main "), (g("yellow"), "12:27 "), (g("green"), "➜ ")]),
        ("atomic", [(g("purple"), "⚡ "), (g("blue"), f" {PROJ} "), (g("green"), " main "), (g("purple"), " ❯ ")]),
        ("smoothie", [(g("purple"), f" {PROJ} "), (g("cyan"), " main "), (g("purple"), " ❯ ")]),
        ("pure", [(g("blue"), f"{PROJ} "), (g("purple"), "❯ ")]),
        ("1shell", [(g("yellow"), "user "), (g("foreground"), "on "), (g("purple"), "Mon 3:04 PM "), (g("cyan"), "⎇ main "), (g("green"), "↑1 ✚2 "), (g("brightBlack"), "MEM 38% "), (g("purple"), "❯ ")]),
        ("avit", [(g("blue"), f"{PROJ} "), (g("yellow"), "main "), (g("cyan"), "➜ ")]),
        ("darkblood", [(g("red"), "┏["), (None, "user"), (g("red"), "] ["), (None, "main"), (g("red"), "] "), (g("red"), "> ")]),
        ("tokyonight", [(g("blue"), "➜ "), (g("purple"), f"{PROJ} "), (g("cyan"), "(main) "), (g("green"), "node 22.1 "), (g("yellow"), "py 3.12 "), (g("cyan"), "go 1.22 ")]),
        ("dracula", [(g("cyan"), "user "), (g("blue"), f"{PROJ} "), (g("purple"), "⎇ main "), (g("cyan"), "node 22.1 "), (g("yellow"), "12:27 "), (g("green"), "aws default ")]),
        ("bong", [(g("yellow"), "  "), (g("foreground"), "16/07 Thu 12:27 | "), (g("yellow"), f"{PROJ} "), (g("purple"), " main "), (g("yellow"), "  ")]),
    ]
    for key, parts in table:
        if key in name:
            return parts
    return [(g("blue"), f"{PROJ} "), (g("green"), "main "), (g("purple"), "❯ ")]


def preview(theme, left, top, cols):
    """A mini terminal session in the theme's own colors, as overlays."""
    W = min(74, cols - left - 2)
    if W < 40:
        return []
    sc, pr, ps = theme["terminal"]["scheme"], theme["psReadLine"], theme["psStyle"]
    fgc = sc["foreground"]

    def line(parts, bg):
        s, used = hexbg(bg), 0
        for hx, txt in parts:
            if used >= W:
                break
            txt, w = clip(txt, W - used)
            s += hexfg(hx or fgc) + txt
            used += w
        return s + " " * (W - used) + RST

    bg = sc["background"]
    chrome = blend(bg, fgc, 0.14)
    title = blend(bg, fgc, 0.5)
    pp = [(fgc, " ")] + prompt_parts(theme)

    def cmd(parts):
        return line(pp + parts, bg)

    ex = pr.get("String") or fgc
    rows = [
        line([(title, " "), ("#FF5F56", "● "), ("#FFBD2E", "● "), ("#27C93F", "● "), (title, "  ~/dev/posh-palette")], chrome),
        cmd([(pr.get("Command"), "ls "), (pr.get("Parameter"), "-l "), (pr.get("Parameter"), "--color")]),
        line([(None, "")], bg),
        line([(None, "drwxr-xr-x  duck   4.0K Jun 20 09:39 "), (ps.get("Directory"), "src")], bg),
        line([(None, "-rwxr-xr-x  duck   1.4K Jun 18 13:12 "), (ex, "build.sh")], bg),
        line([(None, "-rw-r--r--  duck   2.1K Jun 18 13:12 "), (pr.get("Variable"), "config.json")], bg),
        line([(None, "-rw-r--r--  duck   8.9K Jun 18 13:12 "), (pr.get("Parameter"), "README.md")], bg),
        line([(None, "")], bg),
        cmd([(pr.get("Command"), "git "), (fgc, "commit "), (pr.get("Parameter"), "-m "), (pr.get("String"), '"ship it"'), (pr.get("Comment"), "  # done")]),
        line([(None, "["), (sc.get("green"), "main "), (pr.get("Number"), "5d6e7f8"), (None, "] ship it")], bg),
        line([(sc.get("green"), " 3 files changed, 42 insertions(+)")], bg),
        line([(None, "")], bg),
        cmd([(pr.get("Command"), "npm "), (fgc, "test")]),
        line([(sc.get("green"), "  ✓ "), (None, "42 passing")], bg),
        line([(sc.get("red"), "  ✗ "), (None, "1 failing")], bg),
        line([(None, "")], bg),
        cmd([(pr.get("Command"), "ech"), (pr.get("InlinePrediction"), 'o "hello"'), (fgc, "█")]),
    ]
    return [(top + i, left, r) for i, r in enumerate(rows)]


def font_info(font, left, top, cols):
    if cols < left + 30:
        return []
    name = font.get("name") or font.get("id")
    face = font.get("face") or name
    fid = "<face name>" if font.get("custom") else font.get("id")
    lines = [f"{WHITE}Font", "", f"{WHITE}{name}", f"{DIM}face: {face}", "",
             f"{DIM}A font can't be shown here - the", f"{DIM}terminal renders one font for the",
             f"{DIM}whole window.", "", f"{DIM}Install a bundled one:", f"{DIM}  palette font-install {fid}"]
    return [(top + i, left, t) for i, t in enumerate(lines)]


# --- screens ------------------------------------------------------------------

class App:
    def __init__(self, scr):
        self.scr = scr
        self._dark = {}

    # A generic up/down chooser; returns the chosen option's key.
    def choice(self, header, options, default=0):
        idx = default
        while True:
            lines = [""] + [f"  {YELLOW}{h}{RST}" if i == 0 else f"  {GRAY}{h}{RST}" for i, h in enumerate(header)] + [""]
            for i, (key, title, desc) in enumerate(options):
                sel = i == idx
                lines.append(f"  {CYAN if sel else GRAY}{'>' if sel else ' '} {title}{RST}")
                if desc:
                    lines.append(f"      {DIM}{desc}{RST}")
            lines += footer(["↑/↓ move", "Enter select"])
            self.scr.draw(lines)
            k = self.scr.key()
            if k == "up":
                idx = (idx - 1) % len(options)
            elif k == "down":
                idx = (idx + 1) % len(options)
            elif k == "enter":
                return options[idx][0]
            elif len(k) == 1:   # first-letter shortcut (y / n ...)
                hit = next((o for o in options if o[0].startswith(k.lower())), None)
                if hit:
                    return hit[0]

    def ask(self, question, detail):
        return self.choice([question, detail], [("yes", "Yes, install it", None), ("no", "No, skip it", None)]) == "yes"

    def wait_back(self, lines):
        self.scr.draw(lines + footer(["Enter  back to menu", "Q  quit"]))
        while True:
            k = self.scr.key()
            if k in ("enter", "esc"):
                return None
            if k in ("q", "Q"):
                return "quit"

    def report_lines(self, report):
        icon = {"ok": f"{GREEN}✓", "info": f"{DIM}·", "warn": f"{YELLOW}!"}
        out = []
        cols, _ = self.scr.size()
        for status, text in report.lines:
            out.append(f"  {icon[status]} {GRAY}{clip(text, cols - 6)[0]}{RST}")
        return out

    def do_apply(self, comp):
        self.scr.draw(["", f"  {DIM}Applying…{RST}"])
        theme = resolve(comp)
        report = applier.apply_theme(theme, ask=self.ask)
        save_current_composition(comp)
        lines = ["", f"  {GREEN}✓ {WHITE}Applied {theme.get('name') or 'your look'}{RST}", rule(), ""]
        lines += self.report_lines(report)
        lines += ["", f"  {GRAY}Run {WHITE}palette{GRAY} in a wired shell to see the prompt here, or open a new one.{RST}",
                  "", f"  {DIM}Change one layer anytime:{RST}",
                  f"    {CYAN}palette scheme  <name>{RST}", f"    {CYAN}palette prompt  <name>{RST}",
                  f"    {CYAN}palette font    <name>{RST}"]
        return self.wait_back(lines)

    def dark(self, theme):
        sid = theme.get("scheme")
        if sid not in self._dark:
            try:
                self._dark[sid] = is_dark(catalog_item("schemes", sid)["colors"]["background"])
            except (LookupError, KeyError):
                self._dark[sid] = True
        return self._dark[sid]

    # Simple mode: type-to-search + Dark/Light filter, live preview.
    def simple(self):
        entries = themes()
        query, filt, idx, top = "", "all", 0, 0
        nxt = {"all": "dark", "dark": "light", "light": "all"}
        while True:
            ql = query.lower()
            view = [t for t in entries
                    if (filt == "all" or (filt == "dark") == self.dark(t))
                    and (not ql or ql in (t.get("name") or "").lower() or ql in t["id"].lower())]
            idx = max(0, min(idx, len(view) - 1))
            cols, rows_ = self.scr.size()
            max_rows = max(3, rows_ - 8)
            top = window(len(view), idx, top, max_rows)
            tabs = "".join(f"{PILL} {f.title()} {RST} " if f == filt else f"{DIM}{f.title()} {RST}" for f in ("all", "dark", "light"))
            count = f"  {DIM}({idx + 1}/{len(view)}){RST}" if len(view) > max_rows else ""
            lines = ["", f"  {WHITE}Simple mode - pick a theme{RST}",
                     f"  {DIM}Search: {WHITE}{query}█{RST}   {DIM}Filter: {RST}{tabs}{count}", rule(), ""]
            if not view:
                lines.append(f"     {DIM}no themes match{RST}")
            else:
                w = max(16, max(width(t.get("name") or t["id"]) for t in view))
                lines += [row(i == idx, view[i].get("name") or view[i]["id"], w) for i in range(top, min(len(view), top + max_rows))]
            lines += footer(["type to search", "Tab filter", "↑/↓ move", "Enter apply", "Esc back"])
            ov = []
            if view:
                try:
                    ov = preview(resolve(view[idx]), 42, 5, cols)
                except LookupError:
                    ov = []
            self.scr.draw(lines, ov)
            k = self.scr.key()
            if k == "up" and view:
                idx = (idx - 1) % len(view)
            elif k == "down" and view:
                idx = (idx + 1) % len(view)
            elif k == "enter" and view:
                comp = {k2: v for k2, v in view[idx].items() if not k2.startswith("_")}
                return self.do_apply(comp)
            elif k == "tab":
                filt, idx = nxt[filt], 0
            elif k == "backspace":
                query, idx = query[:-1], 0
            elif k == "esc":
                if query:
                    query, idx = "", 0
                else:
                    return None
            elif len(k) == 1 and k.isprintable():
                query, idx = query + k, 0

    # A list picker with a live preview; returns the chosen item dict or None.
    def pick(self, title, items, preview_for, custom_prompt=None, current=None):
        extra = (["⌨ Type a name..."] if custom_prompt else []) + ["← Back"]
        labels = [it.get("name") or it.get("id") for it in items] + extra
        total = len(labels)
        custom_idx = len(items) if custom_prompt else -1
        back_idx = total - 1
        w = max(16, max(width(x) for x in labels))
        idx = next((i for i, it in enumerate(items) if it.get("id") == current), 0)
        top = 0
        while True:
            cols, rows_ = self.scr.size()
            max_rows = max(3, rows_ - 7)
            top = window(total, idx, top, max_rows)
            count = f"   {DIM}({idx + 1}/{total}){RST}" if total > max_rows else ""
            lines = ["", f"  {WHITE}{title}{RST}{count}", rule(), ""]
            lines += [row(i == idx, labels[i], w) for i in range(top, min(total, top + max_rows))]
            lines += footer(["↑/↓ move", "Enter select", "Esc back"])
            ov = preview_for(items[idx], cols) if idx < len(items) else []
            self.scr.draw(lines, ov)
            k = self.scr.key()
            if k == "up":
                idx = (idx - 1) % total
            elif k == "down":
                idx = (idx + 1) % total
            elif k == "esc":
                return None
            elif k == "enter":
                if idx == back_idx:
                    return None
                if idx == custom_idx:
                    val = self.scr.read_line(lines, custom_prompt)
                    if val:
                        return {"id": val, "name": val, "custom": True}
                    continue
                return items[idx]

    def adjust(self, label, value, lo, hi, step, suffix=""):
        while True:
            self.scr.draw(["", f"  {CYAN}{label}{RST}", f"  {DIM}←/→ adjust   Enter confirm   Esc cancel{RST}", "",
                           f"    {WHITE}{value}{suffix}{RST}"])
            k = self.scr.key()
            if k == "left":
                value = max(lo, value - step)
            elif k == "right":
                value = min(hi, value + step)
            elif k == "enter":
                return value
            elif k == "esc":
                return None

    def detail(self):
        base = current_composition()
        comp = {"name": base.get("name") or "Custom", "scheme": base.get("scheme"), "palette": base.get("palette"),
                "prompt": base.get("prompt"), "font": base.get("font"), "fontSize": int(base.get("fontSize") or 11),
                "opacity": int(base.get("opacity") or 100), "acrylic": bool(base.get("acrylic"))}
        fields = ["scheme", "palette", "prompt", "font", "opacity", "acrylic", "fontSize", "apply", "back"]
        idx = 0

        def pv(slot):
            def f(item, cols):
                try:
                    return preview(resolve(dict(comp, **{slot: item["id"]})), 42, 4, cols)
                except LookupError:
                    return []
            return f

        def tr(s):
            s = str(s)
            return s[:15] + "…" if len(s) > 16 else s

        while True:
            labels = [
                f"[1] Scheme       : {tr(comp['scheme'])}", f"[2] Shell colors : {tr(comp['palette'])}",
                f"[3] Prompt       : {tr(comp['prompt'])}", f"[4] Font         : {tr(comp['font'])}",
                f"[5] Opacity      : {comp['opacity']}%", f"[6] Blur         : {'on' if comp['acrylic'] else 'off'}",
                f"[7] Font size    : {comp['fontSize']}", "[A] Apply", "[Esc] ← Back",
            ]
            lw = max(width(x) for x in labels)
            cols, _ = self.scr.size()
            lines = ["", f"  {WHITE}Detail mode - compose your look{RST}", rule(), ""]
            lines += [row(i == idx, labels[i], lw) for i in range(len(labels))]
            lines += footer(["↑/↓ move", "Enter edit", "A apply", "Esc back"])
            try:
                ov = preview(resolve(comp), lw + 9, 4, cols)
            except LookupError:
                ov = []
            self.scr.draw(lines, ov)
            k = self.scr.key()
            target = None
            if k == "esc":
                return None
            if k == "up":
                idx = (idx - 1) % len(fields)
            elif k == "down":
                idx = (idx + 1) % len(fields)
            elif k == "enter":
                target = fields[idx]
            elif k in "1234567" and len(k) == 1:
                idx = int(k) - 1
                target = fields[idx]
            elif k in ("a", "A"):
                idx, target = 7, "apply"
            if target == "back":
                return None
            if target == "scheme":
                p = self.pick("Color scheme", catalog("schemes"), pv("scheme"), current=comp["scheme"])
                if p:
                    comp["scheme"] = p["id"]
            elif target == "palette":
                p = self.pick("Shell colors (input + output)", catalog("palettes"), pv("palette"), current=comp["palette"])
                if p:
                    comp["palette"] = p["id"]
            elif target == "prompt":
                p = self.pick("Prompt (oh-my-posh)", catalog("prompts"), pv("prompt"),
                              custom_prompt="Type an oh-my-posh theme name (e.g. atomic, jandedobbeleer):", current=comp["prompt"])
                if p:
                    comp["prompt"] = p["id"]
            elif target == "font":
                p = self.pick("Font", fonts(), lambda it, cols: font_info(it, 42, 4, cols),
                              custom_prompt="Type an installed font face (e.g. Fira Code):", current=comp["font"])
                if p:
                    comp["font"] = p["id"]
            elif target == "opacity":
                v = self.adjust("Opacity", comp["opacity"], 30, 100, 5, "%")
                if v is not None:
                    comp["opacity"] = v
            elif target == "acrylic":
                comp["acrylic"] = not comp["acrylic"]
            elif target == "fontSize":
                v = self.adjust("Font size", comp["fontSize"], 8, 24, 1)
                if v is not None:
                    comp["fontSize"] = v
            elif target == "apply":
                return self.do_apply(comp)

    def doctor(self):
        icon = {"ok": f"{GREEN}✓", "info": f"{DIM}·", "warn": f"{YELLOW}!"}
        rows_ = doctor.checks()
        lw = max(len(r[1]) for r in rows_)
        lines = ["", f"  {WHITE}Doctor - setup check{RST}", rule(), ""]
        lines += [f"  {icon[s]} {WHITE}{label.ljust(lw)}{RST}  {GRAY}{detail}{RST}" for s, label, detail in rows_]
        return self.wait_back(lines)

    def reset(self):
        if self.choice(["Remove everything PoshPalette wrote?",
                        "Your own terminal and shell config stay exactly as they were."],
                       [("yes", "Reset", "Drop the managed blocks, generated files and the active theme."),
                        ("no", "Cancel", None)], default=1) != "yes":
            return None
        report = applier.reset()
        lines = ["", f"  {GREEN}✓ {WHITE}Reset to your own config{RST}", rule(), ""] + self.report_lines(report)
        return self.wait_back(lines)

    def menu(self, new_themes):
        items = [("1", "Simple mode", "Pick a full theme from a scrollable list", self.simple),
                 ("2", "Detail mode", "Compose scheme, colors, prompt, font", self.detail),
                 ("3", "Doctor", "Check terminal, shells, fonts, oh-my-posh", self.doctor),
                 ("4", "Reset", "Remove PoshPalette's changes", self.reset),
                 ("Q", "Quit", "Exit Posh Palette", None)]
        tw = max(len(i[1]) for i in items)
        texts = [f"[{k}] {t.ljust(tw)}   {d}" for k, t, d, _ in items]
        rw = max(width(t) for t in texts)
        idx = 0
        ver = version()
        while True:
            lines = ["", f"  {WHITE}>_  Posh Palette{RST}" + (f"  {DIM}v{ver}{RST}" if ver else ""), rule(),
                     f"  {DIM}Style all 4 layers: terminal · input · output · prompt{RST}"]
            if new_themes:
                lines.append(f"  {GREEN}+ {new_themes} new community theme{'s' if new_themes != 1 else ''} from GitHub{RST}")
            lines.append("")
            lines += [row(i == idx, texts[i], rw) for i in range(len(items))]
            lines += footer(["↑/↓ move", "Enter select", "Q quit"])
            self.scr.draw(lines)
            k = self.scr.key()
            run = None
            if k == "up":
                idx = (idx - 1) % len(items)
            elif k == "down":
                idx = (idx + 1) % len(items)
            elif k == "enter":
                run = items[idx]
            elif k == "esc":
                return
            else:
                run = next((i for i in items if i[0] == k.upper()), None) if len(k) == 1 else None
            if run:
                if run[3] is None or run[3]() == "quit":
                    return


def run(refresh=False):
    if not (sys.stdin.isatty() and sys.stdout.isatty()):
        print("posh-palette: the picker needs an interactive terminal. Try `posh-palette apply <theme>`.", file=sys.stderr)
        return 2
    with Screen() as scr:
        scr.draw(["", f"  {DIM}Checking for new themes…{RST}"])
        try:
            new = remote.update_catalog(force=refresh)
        except Exception:
            new = 0
        try:
            App(scr).menu(new)
        except KeyboardInterrupt:
            pass
    return 0
