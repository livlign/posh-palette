"""Community catalog auto-refresh (port of src/Remote.ps1).

Pulls themes published on GitHub that aren't available locally - plus the
scheme / palette / prompt files they reference - into ~/.poshpalette/catalog/.
Throttled to once a day, time-boxed and best-effort: offline is never an error.
Shares its cache and .last-refresh stamp with the pwsh module.
"""

import json
import os
import re
import urllib.request
from datetime import datetime, timedelta, timezone

from .catalog import cache_root, catalog, themes

DEFAULT_REPO = "livlign/posh-palette"


def _get(url, timeout):
    headers = {"User-Agent": "PoshPalette", "Accept": "application/vnd.github+json"}
    if os.environ.get("GITHUB_TOKEN") and "api.github.com" in url:
        headers["Authorization"] = f"Bearer {os.environ['GITHUB_TOKEN']}"
    with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=timeout) as r:
        return r.read().decode("utf-8-sig")


def remote_catalog(kind="themes", repo=DEFAULT_REPO, branch="main", timeout=10):
    items = json.loads(_get(f"https://api.github.com/repos/{repo}/contents/{kind}?ref={branch}", timeout))
    return [{"id": i["name"][:-5], "kind": kind, "url": i["download_url"]}
            for i in items if i.get("name", "").endswith(".json")]


def _save(kind, entry, timeout, body=None):
    body = body if body is not None else _get(entry["url"], timeout)
    json.loads(body)   # validate before writing
    d = cache_root() / kind
    d.mkdir(parents=True, exist_ok=True)
    (d / f"{entry['id']}.json").write_text(body, encoding="utf-8")


def _parse_stamp(text):
    # pwsh writes 7 fractional digits ('o' format); fromisoformat wants <= 6.
    text = re.sub(r"(\.\d{6})\d+", r"\1", text.strip().replace("Z", "+00:00"))
    try:
        t = datetime.fromisoformat(text)
    except ValueError:
        return None
    return t if t.tzinfo else t.replace(tzinfo=timezone.utc)


def update_catalog(force=False, repo=DEFAULT_REPO, branch="main", timeout=5):
    """Returns the number of new themes added."""
    if os.environ.get("POSHPALETTE_NO_AUTOUPDATE") and not force:
        return 0
    root = cache_root()
    stamp = root / ".last-refresh"
    if not force and stamp.exists():
        last = _parse_stamp(stamp.read_text(encoding="utf-8-sig"))
        if last and datetime.now(timezone.utc) - last < timedelta(hours=24):
            return 0
    added = 0
    try:
        root.mkdir(parents=True, exist_ok=True)
        have_themes = {t["id"] for t in themes()}
        new = [t for t in remote_catalog("themes", repo, branch, timeout) if t["id"] not in have_themes]
        if new:
            rem = {k: {e["id"]: e for e in remote_catalog(k, repo, branch, timeout)} for k in ("schemes", "palettes", "prompts")}
            have = {k: {e["id"] for e in catalog(k)} for k in rem}
            for t in new:
                body = _get(t["url"], timeout)
                theme = json.loads(body)
                if not theme.get("id"):
                    continue
                for kind, dep in (("schemes", theme.get("scheme")), ("palettes", theme.get("palette")), ("prompts", theme.get("prompt"))):
                    if dep and dep not in have[kind] and dep in rem[kind]:
                        _save(kind, rem[kind][dep], timeout)
                        have[kind].add(dep)
                _save("themes", t, timeout, body)   # last, so it never lands without its layers
                added += 1
        stamp.write_text(datetime.now(timezone.utc).isoformat(), encoding="utf-8")
    except (OSError, ValueError, KeyError):
        pass   # offline / slow / rate-limited: non-fatal
    return added
