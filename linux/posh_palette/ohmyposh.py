"""The oh-my-posh dependency. Only the prompt layer needs it, and the generated
init scripts are guarded with `command -v oh-my-posh`, so it's always optional."""

import os
import shutil
import subprocess

from .catalog import home

INSTALL_CMD = "curl -s https://ohmyposh.dev/install.sh | bash -s -- -d ~/.local/bin"


def path():
    found = shutil.which("oh-my-posh")
    if found:
        return found
    local = home() / ".local" / "bin" / "oh-my-posh"
    return str(local) if os.access(local, os.X_OK) else None


def version():
    p = path()
    if not p:
        return None
    try:
        return subprocess.run([p, "version"], capture_output=True, text=True, timeout=10).stdout.strip() or None
    except (OSError, subprocess.SubprocessError):
        return None


def uses_ohmyposh(theme):
    p = theme.get("prompt") or {}
    return bool(p.get("generated") or p.get("ohMyPoshTheme"))


def install():
    """Run the official per-user installer into ~/.local/bin (no root)."""
    (home() / ".local" / "bin").mkdir(parents=True, exist_ok=True)
    return subprocess.run(["bash", "-c", INSTALL_CMD]).returncode == 0 and bool(path())
