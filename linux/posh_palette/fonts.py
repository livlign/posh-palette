"""Nerd Font detection and install (per-user, no root).

On Linux fontconfig can tell us for real whether a face is installed, so the
terminal layer only sets a font that exists and offers to fetch the rest from the
nerd-fonts releases into ~/.local/share/fonts.
"""

import io
import os
import shutil
import subprocess
import urllib.request
import zipfile
from pathlib import Path

from .catalog import fonts, home

NERD_URL = "https://github.com/ryanoasis/nerd-fonts/releases/{ver}/{asset}.zip"


def _norm(s):
    return "".join((s or "").split()).lower()


def installed_families():
    """Every family name fontconfig knows (None when fc-list isn't available)."""
    if not shutil.which("fc-list"):
        return None
    try:
        out = subprocess.run(["fc-list", ":", "family"], capture_output=True, text=True, timeout=10).stdout
    except (OSError, subprocess.SubprocessError):
        return None
    fams = set()
    for line in out.splitlines():
        for name in line.split(","):
            if name.strip():
                fams.add(name.strip())
    return fams


def is_installed(face, families=None):
    """True/False when fontconfig can answer; True when it can't (don't block)."""
    fams = installed_families() if families is None else families
    if fams is None:
        return True
    want = _norm(face)
    return any(_norm(f) == want for f in fams)


def lookup(name):
    """fonts.json entry by id / nerd asset / face / display name."""
    for f in fonts():
        if name in (f.get("id"), f.get("nerd"), f.get("face"), f.get("name")):
            return f
    return None


def font_dir():
    data = os.environ.get("XDG_DATA_HOME") or str(home() / ".local/share")
    return Path(data) / "fonts"


def install(name, version="latest", log=print):
    """Download a Nerd Font release asset and install its .ttf/.otf files."""
    entry = lookup(name)
    asset = entry["nerd"] if entry and entry.get("nerd") else name
    ver = "latest/download" if version == "latest" else f"download/{version}"
    url = NERD_URL.format(ver=ver, asset=asset)
    log(f"Downloading {asset} Nerd Font from nerd-fonts releases...")
    req = urllib.request.Request(url, headers={"User-Agent": "PoshPalette"})
    with urllib.request.urlopen(req, timeout=120) as r:
        data = r.read()
    dest = font_dir() / f"{asset}NerdFont"
    dest.mkdir(parents=True, exist_ok=True)
    count = 0
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        for member in z.namelist():
            base = os.path.basename(member)
            if not base.lower().endswith((".ttf", ".otf")) or base.startswith("."):
                continue
            with z.open(member) as src, open(dest / base, "wb") as out:
                shutil.copyfileobj(src, out)
            count += 1
    if not count:
        raise RuntimeError(f"No font files in {asset}.zip (is '{asset}' a valid Nerd Font name?).")
    if shutil.which("fc-cache"):
        subprocess.run(["fc-cache", "-f", str(dest)], capture_output=True, timeout=120)
    log(f"Installed {count} file(s) for {asset} into {dest}.")
    return dest


def any_nerd_font(families=None):
    fams = installed_families() if families is None else families
    if fams is None:
        return None
    return sorted(f for f in fams if "nerd font" in f.lower() or f.endswith(" NF") or " NF " in f)

