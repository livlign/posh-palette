"""Managed blocks and backups - the same safety model as the pwsh module.

Every edit to a file the user owns (shell rc, terminal config) lives inside one
marker-delimited block, so re-applying replaces it cleanly and removing it is a
full revert. The file is backed up to <file>.poshpalette-<stamp>.bak the first
time its content actually changes in a run.
"""

import os
import re
import shutil
import time
from pathlib import Path

BLOCK_START = "# >>> PoshPalette >>>"
BLOCK_END = "# <<< PoshPalette <<<"
_BLOCK_RE = re.compile(r"\n?" + re.escape(BLOCK_START) + r".*?" + re.escape(BLOCK_END) + r"\n?", re.S)


def backup(path):
    path = Path(path)
    if not path.is_file():
        return None
    dest = path.with_name(f"{path.name}.poshpalette-{time.strftime('%Y%m%d-%H%M%S')}.bak")
    shutil.copy2(path, dest)
    return dest


def write_text(path, text):
    """Atomic write that keeps the file's mode. Resolves symlinks first so a
    dotfile managed by stow/chezmoi keeps pointing at the same target."""
    path = Path(path)
    if path.is_symlink():
        path = path.resolve()
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f".{path.name}.pp-tmp")
    tmp.write_text(text, encoding="utf-8")
    if path.exists():
        shutil.copymode(path, tmp)
    os.replace(tmp, path)


def read_text(path):
    try:
        return Path(path).read_text(encoding="utf-8")
    except FileNotFoundError:
        return ""


def render_block(body):
    return f"{BLOCK_START}\n# Managed by PoshPalette - re-run `palette` to change, `palette reset` to remove.\n{body.rstrip()}\n{BLOCK_END}\n"


def with_block(text, body, position="end"):
    """Return text with the managed block set to body (replacing any existing one)."""
    block = render_block(body)
    if BLOCK_START in text and BLOCK_END in text:
        return _BLOCK_RE.sub(lambda m: ("\n" if m.group(0).startswith("\n") else "") + block, text, count=1)
    if position == "start":
        return block + ("\n" + text if text else "")
    text = text.rstrip("\n")
    return (text + "\n\n" if text else "") + block


def without_block(text):
    if BLOCK_START not in text:
        return text
    out = _BLOCK_RE.sub("\n", text).strip("\n")
    return out + "\n" if out else ""


def has_block(path):
    return BLOCK_START in read_text(path)


def upsert_block(path, body, position="end", dry_run=False):
    """Set the managed block in a file. Returns True if the file changed."""
    old = read_text(path)
    new = with_block(old, body, position)
    if new == old:
        return False
    if not dry_run:
        backup(path)
        write_text(path, new)
    return True


def remove_block(path, dry_run=False):
    """Drop the managed block from a file. Returns True if there was one."""
    old = read_text(path)
    new = without_block(old)
    if new == old:
        return False
    if not dry_run:
        backup(path)
        write_text(path, new)
    return True


def write_generated(path, text, dry_run=False):
    """Write a file PoshPalette owns outright (no backup needed). True if changed."""
    if read_text(path) == text:
        return False
    if not dry_run:
        write_text(path, text)
    return True
