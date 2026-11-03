# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

"""Paths and small helpers shared by every Harness² module.

Standard library only, Python 3.9 and later: the installed copy runs under
whatever `python3` Antigravity's hooks find, which on a bare Mac is the Xcode
command-line tools' 3.9.
"""

from __future__ import annotations

import json
import os
import tempfile
import time
from pathlib import Path
from typing import Any, Callable, Optional


def gemini_config() -> Path:
    """Antigravity's config folder (plugins, rules, config.json)."""
    return Path(os.environ.get("HARNESS2_CONFIG") or Path.home() / ".gemini" / "config")


def antigravity_home() -> Path:
    """Antigravity's data folder (brain/, hookify-rules.json)."""
    return Path(
        os.environ.get("HARNESS2_ANTIGRAVITY")
        or Path.home() / ".gemini" / "antigravity"
    )


def harness2_home() -> Path:
    """Harness² runtime data: state/, library/, runs/, events.jsonl."""
    return Path(os.environ.get("HARNESS2_HOME") or antigravity_home() / "harness2")


def plugin_dir() -> Path:
    """The installed plugin: the harness tree Harness² edits."""
    return gemini_config() / "plugins" / "harness2"


def state_dir() -> Path:
    return harness2_home() / "state"


def library_dir() -> Path:
    return harness2_home() / "library"


def runs_dir() -> Path:
    return harness2_home() / "runs"


def read_json(path: Path, default: Any = None) -> Any:
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def write_json(path: Path, data: Any, indent: int = 2) -> None:
    """Writes atomically (temp file + rename) so a reader never sees half a file."""
    path.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps(data, indent=indent, ensure_ascii=False) + "\n"
    _replace(path, text)


def _replace(path: Path, text: str, expect: Optional[str] = None) -> bool:
    """Atomically replaces `path` with `text`, keeping its permission bits.

    With `expect`, replaces only if the file still holds exactly that text
    (re-checked just before the rename) and returns False otherwise."""
    try:
        mode = os.stat(path).st_mode & 0o777
    except OSError:
        mode = 0o644
    fd, tmp = tempfile.mkstemp(prefix=".tmp-", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(text)
        os.chmod(tmp, mode)
        if expect is not None:
            try:
                now = path.read_text(encoding="utf-8")
            except OSError:
                now = None
            if now != expect:
                os.unlink(tmp)
                return False
        os.replace(tmp, path)
        return True
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def update_json(
    path: Path,
    change: Callable[[Any], Any],
    backup: Optional[Path] = None,
    tries: int = 10,
) -> Any:
    """Read-modify-write that does not lose a concurrent writer's change.

    Antigravity rewrites config.json and hookify-rules.json itself (for
    example when it notices a new plugin), so a plain read-then-write can
    silently undo its edit. This re-reads, re-applies `change` and retries if
    the file changed underneath. `backup`, if given, gets the exact text that
    was replaced. Raises ValueError if the file exists but is not JSON."""
    path.parent.mkdir(parents=True, exist_ok=True)
    for attempt in range(tries):
        try:
            raw: Optional[str] = path.read_text(encoding="utf-8")
        except FileNotFoundError:
            raw = None
        before = json.loads(raw) if raw is not None else None
        new = change(json.loads(raw) if raw is not None else None)
        if raw is not None and new == before:
            return new  # nothing to change: leave the file (and its formatting) alone
        text = json.dumps(new, indent=2, ensure_ascii=False) + "\n"
        if raw is None:
            if not path.exists():
                _replace(path, text)
                return new
            continue
        if _replace(path, text, expect=raw):
            if backup is not None:
                backup.write_text(raw, encoding="utf-8")
            return new
        time.sleep(0.05 * (attempt + 1))
    raise RuntimeError(f"{path} kept changing underneath; gave up after {tries} tries")


def safe_id(text: str) -> str:
    """A conversation id made safe to use as a file name."""
    keep = "".join(c for c in (text or "") if c.isalnum() or c in "-_.")
    return keep.strip(".")[:80] or "default"


def decode_arg(value: Any) -> Any:
    """Antigravity records tool arguments JSON-encoded (`"\\"inherit\\""`);
    hooks may see them raw. Decode one level when it looks encoded."""
    if isinstance(value, str):
        s = value.strip()
        if len(s) >= 2 and (s[0], s[-1]) in (('"', '"'), ("{", "}"), ("[", "]")):
            try:
                return json.loads(s)
            except ValueError:
                return value
        if s in ("true", "false"):
            return s == "true"
    return value


def normalize_args(args: Any) -> dict:
    if not isinstance(args, dict):
        return {}
    return {k: decode_arg(v) for k, v in args.items()}
