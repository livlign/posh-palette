"""Command line: `posh-palette` (or the `palette` shell function).

  palette                         the interactive picker
  palette apply <theme>           apply a full theme by id / name / path
  palette scheme|colors|prompt|font <id>    swap one layer, keep the rest
  palette set --opacity 90 --font-size 12 --blur on
  palette list [themes|schemes|palettes|prompts|fonts]
  palette reset                   remove everything PoshPalette wrote
  palette doctor                  check terminal, shells, fonts, oh-my-posh
  palette osc <scheme>            recolor just this terminal session
  palette import <file> --save    import an iTerm2/base16/WT/Ghostty/kitty scheme
  palette font-install <id>       install a Nerd Font (per-user)
  palette refresh                 pull new community themes now
"""

import argparse
import json
import sys

from . import apply as applier
from . import doctor, fonts, importer, remote, terminals, version
from .catalog import (CatalogError, catalog, catalog_item, current_composition, find_theme,
                      fonts as font_catalog, resolve, save_current_composition, themes)
from .colors import is_dark, osc_sequence

_TTY = sys.stdout.isatty()


def c(code, text):
    return f"\x1b[{code}m{text}\x1b[0m" if _TTY else text


def print_report(report, title=None):
    if title:
        print(c("36", title))
    icon = {"ok": c("32", "✓"), "info": c("90", "·"), "warn": c("33", "!")}
    for status, text in report.lines:
        print(f"  {icon[status]} {text}")


def tty_ask(question, detail):
    print(f"\n  {c('33', question)}\n  {c('90', detail)}")
    try:
        return input("  Install? [y/N] ").strip().lower() in ("y", "yes")
    except EOFError:
        return False


def _apply(comp, dry_run, yes):
    theme = resolve(comp)
    interactive = sys.stdin.isatty() and sys.stdout.isatty()
    ask = (lambda q, d: True) if yes else (tty_ask if interactive else None)
    report = applier.apply_theme(theme, ask=ask, dry_run=dry_run)
    print_report(report, f"{'[dry-run] ' if dry_run else ''}Applying '{theme.get('name') or comp.get('scheme')}'...")
    if not dry_run:
        save_current_composition(comp)
        print(c("36", "Done.") + " Run `palette` from a wired shell to load it here, or open a new shell.")


def cmd_apply(a):
    _apply(find_theme(a.theme), a.dry_run, a.yes)


def cmd_layer(a):
    comp = current_composition()
    comp.setdefault("name", "Custom")
    if a.cmd == "scheme":
        catalog_item("schemes", a.id)
        comp["scheme"] = a.id
    elif a.cmd == "colors":
        catalog_item("palettes", a.id)
        comp["palette"] = a.id
    elif a.cmd == "prompt":
        comp["prompt"] = a.id      # catalog id or an oh-my-posh theme name
    elif a.cmd == "font":
        comp["font"] = a.id        # fonts.json id or a font face
    _apply(comp, a.dry_run, a.yes)


def cmd_set(a):
    comp = current_composition()
    comp.setdefault("name", "Custom")
    if a.opacity is not None:
        comp["opacity"] = a.opacity
    if a.font_size is not None:
        comp["fontSize"] = a.font_size
    if a.blur is not None:
        comp["acrylic"] = a.blur == "on"
    for k in ("scheme", "palette", "prompt", "font"):
        v = getattr(a, k)
        if v:
            if k in ("scheme", "palette"):
                catalog_item(k + "s", v)
            comp[k] = v
    _apply(comp, a.dry_run, a.yes)


def cmd_list(a):
    kind = a.kind
    if kind == "fonts":
        fams = fonts.installed_families()
        rows = [(f["id"], f["name"], "installed" if fams is not None and fonts.is_installed(f["face"], fams) else "")
                for f in font_catalog()]
    elif kind == "themes":
        rows = []
        for t in themes():
            try:
                tone = "dark" if is_dark(catalog_item("schemes", t["scheme"])["colors"]["background"]) else "light"
            except (LookupError, KeyError):
                tone = ""
            rows.append((t["id"], t.get("name") or "", tone))
    else:
        rows = [(e["id"], e.get("name") or "", "") for e in catalog(kind)]
    if a.json:
        print(json.dumps([{"id": r[0], "name": r[1], "tag": r[2]} for r in rows], indent=2))
        return
    w = max((len(r[0]) for r in rows), default=0)
    cur = current_composition()
    slot = {"themes": None, "schemes": "scheme", "palettes": "palette", "prompts": "prompt", "fonts": "font"}[kind]
    for id_, name, tag in rows:
        mark = c("32", "●") if slot and cur.get(slot) == id_ else " "
        print(f" {mark} {id_.ljust(w)}  {name}" + (f"  {c('90', tag)}" if tag else ""))


def cmd_reset(a):
    print_report(applier.reset(dry_run=a.dry_run), f"{'[dry-run] ' if a.dry_run else ''}Removing PoshPalette's changes...")


def cmd_doctor(a):
    icon = {"ok": c("32", "✓"), "info": c("90", "·"), "warn": c("33", "!")}
    rows = doctor.checks()
    w = max(len(r[1]) for r in rows)
    print(c("36", f"Posh Palette {version() or ''} - setup check"))
    for s, label, detail in rows:
        print(f"  {icon[s]} {label.ljust(w)}  {detail}")
    return 1 if any(s == "warn" for s, _, _ in rows) and a.strict else 0


def cmd_osc(a):
    item = catalog_item("schemes", a.scheme)
    seq = osc_sequence(item["colors"])
    if a.show_bytes:
        print(seq.replace("\x1b", "\\e"))
        return
    if not a.force and not terminals.osc_capable():
        print("Terminal can't take OSC colors here (tmux/screen/dumb). Re-run with --force to try anyway.", file=sys.stderr)
        return 1
    with open("/dev/tty", "w", encoding="utf-8") as tty:
        tty.write(seq)
    print(c("32", f"  Applied scheme '{item['name']}' to this session via OSC.") + c("90", " (Open a new window to revert.)"))


def cmd_import(a):
    scheme, dest = importer.import_scheme(a.path, a.id, a.name, a.format, a.save)
    if dest:
        print(c("32", f"Imported scheme '{scheme['id']}' -> {dest}"))
        try:
            if catalog_item("schemes", scheme["id"]) != scheme:
                print(c("33", f"  Note: a bundled scheme is also called '{scheme['id']}' and wins; re-import with --id."))
        except CatalogError:
            pass
    else:
        print(json.dumps(scheme, indent=2))


def cmd_font_install(a):
    fonts.install(a.name, a.version)


def cmd_refresh(a):
    n = remote.update_catalog(force=True)
    print(f"{n} new theme{'s' if n != 1 else ''} pulled from GitHub." if n else "No new themes (or offline).")


def cmd_ui(a):
    from . import tui
    return tui.run(refresh=a.refresh)


def build_parser():
    p = argparse.ArgumentParser(prog="palette", description="Posh Palette - theme your terminal and shell in one go.")
    p.add_argument("--version", action="version", version=f"posh-palette {version() or '?'}")
    p.add_argument("--refresh", action="store_true", help="check GitHub for new themes before opening the picker")
    sub = p.add_subparsers(dest="cmd", metavar="<command>")

    def with_apply_flags(sp):
        sp.add_argument("--dry-run", action="store_true", help="show what would change, write nothing")
        sp.add_argument("-y", "--yes", action="store_true", help="install a missing font / oh-my-posh without asking")
        return sp

    sp = with_apply_flags(sub.add_parser("apply", help="apply a full theme"))
    sp.add_argument("theme", help="theme id, name, or path to a theme JSON")
    sp.set_defaults(fn=cmd_apply)

    for name, helptext in (("scheme", "swap the terminal color scheme"), ("colors", "swap input + output colors"),
                           ("prompt", "swap the prompt (catalog id or oh-my-posh theme name)"),
                           ("font", "swap the terminal font (fonts.json id or a font face)")):
        sp = with_apply_flags(sub.add_parser(name, help=helptext))
        sp.add_argument("id")
        sp.set_defaults(fn=cmd_layer)

    sp = with_apply_flags(sub.add_parser("set", help="change several slots / window settings at once"))
    sp.add_argument("--scheme")
    sp.add_argument("--palette")
    sp.add_argument("--prompt")
    sp.add_argument("--font")
    sp.add_argument("--opacity", type=int, choices=range(10, 101), metavar="10-100")
    sp.add_argument("--font-size", type=int, choices=range(6, 33), metavar="6-32")
    sp.add_argument("--blur", choices=("on", "off"))
    sp.set_defaults(fn=cmd_set)

    sp = sub.add_parser("list", help="list catalog entries")
    sp.add_argument("kind", nargs="?", default="themes", choices=("themes", "schemes", "palettes", "prompts", "fonts"))
    sp.add_argument("--json", action="store_true")
    sp.set_defaults(fn=cmd_list)

    sp = sub.add_parser("reset", aliases=["restore"], help="remove everything PoshPalette wrote")
    sp.add_argument("--dry-run", action="store_true")
    sp.set_defaults(fn=cmd_reset)

    sp = sub.add_parser("doctor", help="check terminal, shells, fonts, oh-my-posh")
    sp.add_argument("--strict", action="store_true", help="exit 1 if anything needs fixing")
    sp.set_defaults(fn=cmd_doctor)

    sp = sub.add_parser("osc", help="recolor only this terminal session from a scheme")
    sp.add_argument("scheme")
    sp.add_argument("--show-bytes", action="store_true", help="print the escapes instead of applying")
    sp.add_argument("--force", action="store_true")
    sp.set_defaults(fn=cmd_osc)

    sp = sub.add_parser("import", help="import a scheme (iTerm2, base16, Windows Terminal, Ghostty, kitty)")
    sp.add_argument("path")
    sp.add_argument("--id")
    sp.add_argument("--name")
    sp.add_argument("--format", default="auto", choices=("auto", "iterm", "base16", "wt", "ghostty", "kitty"))
    sp.add_argument("--save", action="store_true", help="add it to your catalog (~/.poshpalette/catalog/schemes)")
    sp.set_defaults(fn=cmd_import)

    sp = sub.add_parser("font-install", help="install a Nerd Font into ~/.local/share/fonts")
    sp.add_argument("name", help="fonts.json id (e.g. jetbrains) or a nerd-fonts asset name")
    sp.add_argument("--version", default="latest")
    sp.set_defaults(fn=cmd_font_install)

    sp = sub.add_parser("refresh", help="pull new community themes from GitHub now")
    sp.set_defaults(fn=cmd_refresh)
    return p


def main(argv=None):
    args = build_parser().parse_args(argv)
    try:
        if not args.cmd:
            return cmd_ui(args) or 0
        return args.fn(args) or 0
    except (CatalogError, ValueError, OSError) as e:
        print(f"posh-palette: {e}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        return 130
