#!/usr/bin/env python3
"""Fail if the web gallery's theme cards drift from the palette JSON source.

The gallery (docs/themes.html) embeds a hand-maintained snapshot of each theme's
syntax colors as CSS variables, so the mini-terminal cards can render without
loading the module. That snapshot has drifted from palettes/*.json before (it's
what PRs #16 and #17 fixed), because nothing enforced "site == reality" that
CONTRIBUTING.md asks for. This check enforces it in CI.

For each theme card it compares the syntax-color vars against the palette the
theme composition references. It intentionally does NOT check:
  - --c-bg / --c-fg  (sourced from the scheme, not the palette)
  - --c-accent / --c-glow  (curated per-card design values, by design)
These are the same boundaries PR #16 established.

Exit 0 = in sync. Exit 1 = drift found (prints each offending value).
No third-party dependencies; runs on a stock python3.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HTML = ROOT / "docs" / "themes.html"

# gallery CSS var -> (palette section, key)
VARMAP = {
    "--c-cmd":   ("psReadLine", "Command"),
    "--c-param": ("psReadLine", "Parameter"),
    "--c-str":   ("psReadLine", "String"),
    "--c-op":    ("psReadLine", "Operator"),
    "--c-var":   ("psReadLine", "Variable"),
    "--c-num":   ("psReadLine", "Number"),
    "--c-com":   ("psReadLine", "Comment"),
    "--c-err":   ("psReadLine", "Error"),
    "--c-dir":   ("psStyle", "Directory"),  # falls back to Command if absent
}


def load_palette(theme_id):
    """Resolve the palette a theme card should mirror, via its composition."""
    theme_file = ROOT / "themes" / f"{theme_id}.json"
    if not theme_file.exists():
        return None, f"no themes/{theme_id}.json for gallery card '{theme_id}'"
    palette_id = json.loads(theme_file.read_text()).get("palette", theme_id)
    palette_file = ROOT / "palettes" / f"{palette_id}.json"
    if not palette_file.exists():
        return None, f"theme '{theme_id}' references missing palette '{palette_id}'"
    return json.loads(palette_file.read_text()), None


def expected(pal, section, key):
    if section == "psStyle":
        directory = (pal.get("psStyle") or {}).get("Directory")
        return directory or pal["psReadLine"].get("Command")
    return pal["psReadLine"].get(key)


def main():
    html = HTML.read_text()
    # Each THEMES entry:  "id":{name:...,\n  "--c-bg":...,...,"--c-glow":"rgba(...)"}
    # The value object has no nested braces (rgba() uses parens), so a non-greedy
    # match to the first "}" captures the whole card. Don't require a trailing
    # comma - the last entry in the map has none (e.g. high-contrast).
    cards = re.finditer(r'"([a-z0-9-]+)":\{name:.*?\n\s*("--c-bg".*?\})', html, re.S)

    problems = []
    checked = 0
    for m in cards:
        theme_id, block = m.group(1), m.group(2)
        pal, err = load_palette(theme_id)
        if err:
            problems.append(err)
            continue
        have = dict(re.findall(r'"(--c-[a-z]+)":"(#[0-9A-Fa-f]{6})"', block))
        checked += 1
        for var, (section, key) in VARMAP.items():
            want = expected(pal, section, key)
            got = have.get(var)
            if want and got and got.lower() != want.lower():
                problems.append(
                    f"{theme_id}: {var} card={got} palette={want}"
                )

    if problems:
        print("Gallery cards drifted from palette JSON source:\n")
        for p in problems:
            print(f"  {p}")
        print(
            f"\n{len(problems)} issue(s) across {checked} cards checked.\n"
            "Regenerate the affected --c-* vars in docs/themes.html from the "
            "palette JSON (see CONTRIBUTING.md > Keep the gallery in sync)."
        )
        return 1

    print(f"Gallery in sync: {checked} theme cards match their palette JSON.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
