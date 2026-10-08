"""Composition model: catalog loaders, the resolver, and the current composition.

Mirrors src/Theme.ps1 + src/Layers.ps1. A theme is a composition of slot
references (scheme / palette / prompt / font / opacity / acrylic / fontSize);
resolve() expands it into the flat shape the appliers write.
"""

import json
import os
from pathlib import Path

from . import DATA_ROOT
from .prompt import new_omp_config

KINDS = ("themes", "schemes", "palettes", "prompts")


def home():
    return Path(os.environ.get("HOME") or Path.home())


def user_root():
    """~/.poshpalette - shared with the PowerShell module (same current.json / cache)."""
    return home() / ".poshpalette"


def cache_root():
    return user_root() / "catalog"


def current_path():
    return user_root() / "current.json"


class CatalogError(LookupError):
    pass


# --- Catalog loaders ----------------------------------------------------------

def _catalog_files(kind):
    """(path, data) for every *.json entry of a kind, bundled first then the user
    cache, de-duped by id. Bundled wins on a clash, so the cache only adds."""
    seen = set()
    for root in (DATA_ROOT, cache_root()):
        d = root / kind
        if not d.is_dir():
            continue
        for f in sorted(d.glob("*.json")):
            try:
                data = json.loads(f.read_text(encoding="utf-8-sig"))
            except (OSError, ValueError):
                continue
            if not isinstance(data, dict) or not data.get("id") or data["id"] in seen:
                continue
            seen.add(data["id"])
            yield f, data


def catalog(kind):
    """Entries of schemes / palettes / prompts as dicts (the file data)."""
    return [data for _, data in _catalog_files(kind)]


def catalog_item(kind, id_):
    for data in catalog(kind):
        if data["id"] == id_:
            return data
    raise CatalogError(f"No '{kind}' entry with id '{id_}'.")


def fonts():
    return json.loads((DATA_ROOT / "fonts.json").read_text(encoding="utf-8-sig"))


def themes():
    """Compositions sorted by their curated 'order', unordered ones last, then name."""
    out = [dict(data, _path=str(f)) for f, data in _catalog_files("themes")]
    big = 1 << 31
    out.sort(key=lambda t: (t["order"] if t.get("order") is not None else big, t.get("name") or ""))
    return out


def find_theme(name_or_path):
    """A composition by id, name, or path to a theme JSON file."""
    p = Path(name_or_path).expanduser()
    if p.is_file():
        return json.loads(p.read_text(encoding="utf-8-sig"))
    for t in themes():
        if name_or_path in (t["id"], t.get("name")):
            return {k: v for k, v in t.items() if not k.startswith("_")}
    available = ", ".join(t["id"] for t in themes())
    raise CatalogError(f"Theme '{name_or_path}' not found. Available: {available}")


# --- Resolver -----------------------------------------------------------------

def resolve(comp):
    """Expand a composition into the applier shape:
    {name, terminal: {font, fontSize, opacity, useAcrylic, scheme}, psReadLine,
     psStyle, prompt: {generated, name, config} | {ohMyPoshTheme}}"""
    scheme = catalog_item("schemes", comp.get("scheme"))
    palette = catalog_item("palettes", comp.get("palette"))
    # A prompt may be a catalog id, or a bare oh-my-posh theme name typed directly.
    prompt = next((p for p in catalog("prompts") if p["id"] == comp.get("prompt")), None)
    # A font may be a fonts.json id or a literal font face.
    font = next((f for f in fonts() if f["id"] == comp.get("font")), None)
    if not font:
        f = comp.get("font")
        font = {"id": f, "name": f, "face": f, "nerd": f}

    scheme_block = dict(scheme.get("colors") or {})
    scheme_block["name"] = scheme.get("name")

    if prompt and prompt.get("generate"):
        prompt_block = {
            "generated": True,
            "name": f"pp-{prompt['id']}",
            "config": new_omp_config(scheme.get("colors") or {}, prompt.get("style") or "classic",
                                     prompt.get("gradient")),
        }
    elif prompt:
        prompt_block = {"ohMyPoshTheme": prompt.get("ohMyPoshTheme")}
    else:
        prompt_block = {"ohMyPoshTheme": comp.get("prompt")}

    # Fill the input roles a palette doesn't set from its own (contrast-checked)
    # roles, exactly like the PowerShell resolver. An explicit value always wins.
    prl = dict(palette.get("psReadLine") or {})
    derived = {
        "Keyword": prl.get("Operator"),
        "Type": prl.get("Parameter"),
        "Member": prl.get("Default"),
        "ContinuationPrompt": prl.get("Comment"),
    }
    for role, value in derived.items():
        if role not in prl and value:
            prl[role] = value

    def _or(key, default):
        v = comp.get(key)
        return default if v is None else v

    return {
        "name": comp.get("name"),
        "terminal": {
            "font": font.get("face"),
            "fontSize": _or("fontSize", 11),
            "opacity": _or("opacity", 100),
            "useAcrylic": bool(_or("acrylic", False)),
            "scheme": scheme_block,
        },
        "psReadLine": prl,
        "psStyle": dict(palette.get("psStyle") or {}),
        "prompt": prompt_block,
    }


# --- Current composition ------------------------------------------------------

def current_composition():
    """The composition behind the current look; the first bundled theme if none."""
    try:
        data = json.loads(current_path().read_text(encoding="utf-8-sig"))
        if isinstance(data, dict):
            return data
    except (OSError, ValueError):
        pass
    first = themes()[0]
    return {k: v for k, v in first.items() if not k.startswith("_")}


def save_current_composition(comp):
    p = current_path()
    p.parent.mkdir(parents=True, exist_ok=True)
    clean = {k: v for k, v in comp.items() if not k.startswith("_")}
    p.write_text(json.dumps(clean, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def forget_current_composition():
    try:
        current_path().unlink()
    except FileNotFoundError:
        pass
