# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

"""`harness2 install`: puts the live harness2 plugin (and hookify) in ~/.gemini/config.

Code the tool owns (lib/, hooks/, hooks.json, plugin.json, the harness2
skill) is always refreshed. The editable surface (rules/, other skills/,
scripts/, sub_agents/, guardrails.json, hookify-rules.json) is only SEEDED
when missing, because after the first distill it is the evolved harness and
reinstalling must not throw that away (`--reseed` overwrites it, after a
backup). config.json keeps every key it had; it is backed up first.
"""

from __future__ import annotations

import datetime as _dt
import json
import os
import shutil
import stat
import subprocess
import time
from pathlib import Path
from typing import List, Optional

from common import (
    antigravity_home,
    gemini_config,
    harness2_home,
    library_dir,
    plugin_dir,
    read_json,
    update_json,
)

HERE = Path(__file__).resolve().parent
ASSETS = HERE / "assets"
LIB_MODULES = (
    "common.py",
    "constraints.py",
    "trajectory.py",
    "library.py",
    "validator.py",
    "runtime_hooks.py",
    "prompts.py",
    "installer.py",
    "cli.py",
)
OWNED = ("hooks", "hooks.json", "plugin.json", "skills/harness2")
EDITABLE = (
    "rules",
    "skills",
    "scripts",
    "sub_agents",
    "guardrails.json",
    "hookify-rules.json",
)
HOOKIFY_FALLBACK_MARK = "hookify could not run its rules"


def _stamp() -> str:
    return _dt.datetime.now().strftime("%Y%m%dT%H%M%S")


def _copy(src: Path, dst: Path) -> None:
    """Copies a file or tree, following symlinks (Bazel runfiles are symlinks)."""
    if src.is_dir():
        if dst.exists():
            shutil.rmtree(dst)
        shutil.copytree(
            src,
            dst,
            symlinks=False,
            ignore=shutil.ignore_patterns("__pycache__", "*.pyc"),
        )
    else:
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src, dst)
        mode = os.stat(src).st_mode
        os.chmod(dst, 0o755 if mode & stat.S_IXUSR or dst.suffix == ".sh" else 0o644)


def _fix_modes(root: Path) -> None:
    for p in root.rglob("*"):
        if p.is_file() and (
            p.suffix == ".sh" or p.parent.name == "scripts" and p.suffix == ".py"
        ):
            os.chmod(p, 0o755)


def install_plugin(reseed: bool = False, log=print) -> Path:
    dest = plugin_dir()
    src = ASSETS / "plugin"
    if not src.is_dir():
        raise SystemExit(f"harness2: plugin assets missing at {src}")
    if reseed and dest.exists():
        backup = harness2_home() / "backups" / f"plugin-{_stamp()}"
        backup.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(dest, backup, symlinks=True)
        log(f"backed up the current harness to {backup}")
    dest.mkdir(parents=True, exist_ok=True)

    for rel in OWNED:
        _copy(src / rel, dest / rel)
    lib = dest / "lib"
    lib.mkdir(exist_ok=True)
    for m in LIB_MODULES:
        _copy(HERE / m, lib / m)

    seeded = []
    for rel in EDITABLE:
        s = src / rel
        if s.is_dir():
            for f in sorted(p for p in s.rglob("*") if p.is_file()):
                r = f.relative_to(src)
                if str(r).startswith("skills/harness2/"):
                    continue
                d = dest / r
                if reseed or not d.exists():
                    _copy(f, d)
                    seeded.append(str(r))
        elif s.exists() and (reseed or not (dest / rel).exists()):
            _copy(s, dest / rel)
            seeded.append(rel)
    _fix_modes(dest)
    log(
        f"plugin installed at {dest} ({len(seeded)} editable file(s) seeded{': ' + ', '.join(seeded) if seeded else ''})"
    )
    return dest


def enable_plugins(names: List[str], log=print) -> None:
    cfg = gemini_config() / "config.json"
    changed: List[str] = []

    def change(data):
        changed.clear()
        if data is None:
            data = {}
        if not isinstance(data, dict):
            raise SystemExit(f"harness2: {cfg} is not a JSON object; not touching it")
        plugins = data.setdefault("plugins", {})
        for n in names:
            entry = plugins.get(n) if isinstance(plugins.get(n), dict) else {}
            if entry.get("enabled") is not True:
                entry["enabled"] = True
                changed.append(n)
            plugins[n] = entry
        return data

    backup = cfg.with_name(f"config.json.harness2-{_stamp()}.bak")
    try:
        update_json(cfg, change, backup=backup)
    except ValueError:
        raise SystemExit(f"harness2: {cfg} is not valid JSON; not touching it")
    if not changed:
        log(f"config.json: {', '.join(names)} already enabled")
        return
    log(
        f"config.json: enabled {', '.join(changed)}; every other key kept (previous file: {backup.name})"
    )


def hookify_source(explicit: Optional[str]) -> Optional[Path]:
    cands = []
    if explicit:
        cands.append(Path(explicit))
    ws = os.environ.get("BUILD_WORKSPACE_DIRECTORY")
    if ws:
        cands.append(Path(ws) / "apps/desktop/antigravity/plugins/hookify")
    for c in cands:
        if (c / "hooks.json").is_file():
            return c
    return None


def install_hookify(src: Optional[Path], log=print) -> Optional[Path]:
    dest = gemini_config() / "plugins" / "hookify"
    if (dest / "hooks.json").is_file():
        log(f"hookify already installed at {dest}")
        return dest
    if src is None:
        log(
            "hookify: source not found (run through `bazel run //tools/harness2 -- install`, or pass --hookify-src); skipped"
        )
        return None
    shutil.copytree(
        src,
        dest,
        symlinks=False,
        ignore=shutil.ignore_patterns("bazel-*", "__pycache__"),
    )
    log(f"hookify installed at {dest} from {src}")
    return dest


def prewarm_hookify(dest: Optional[Path], wait_s: int = 120, log=print) -> bool:
    """Builds hookify's Rust hook now, so Antigravity's first tool calls do not
    get its fallback ("ask" on every call) while rustc runs."""
    if dest is None:
        return False
    hook = dest / "hooks" / "evaluate-rules.sh"
    if not hook.is_file():
        return False
    payload = json.dumps(
        {"toolCall": {"name": "read_file", "args": {"Path": "/dev/null"}}}
    )
    deadline = time.time() + wait_s
    while True:
        try:
            r = subprocess.run(
                ["/bin/sh", str(hook)],
                input=payload,
                capture_output=True,
                text=True,
                timeout=30,
                cwd=str(dest),
            )
            out = r.stdout.strip()
        except (OSError, subprocess.TimeoutExpired):
            out = ""
        if out and HOOKIFY_FALLBACK_MARK not in out:
            log(f"hookify hook built and answering: {out[:120]}")
            return True
        if time.time() > deadline:
            log(
                "hookify: its Rust hook is still building (or cannot build); until it does, hookify asks before each tool call. See ~/.cache/antigravity-plugins."
            )
            return False
        time.sleep(3)


def merge_hookify_rules(plugin: Path, log=print) -> None:
    """Puts the harness's `harness2-*` hookify rules into the global rules file."""
    ours = read_json(plugin / "hookify-rules.json", {}) or {}
    rules = ours.get("rules", []) if isinstance(ours, dict) else []
    target = antigravity_home() / "hookify-rules.json"
    kept: List[dict] = []

    def change(current):
        if current is None:
            current = {"rules": []}
        if isinstance(current, list):
            current = {"rules": current}
        kept[:] = [
            r
            for r in current.get("rules", [])
            if not str(r.get("name", "")).startswith("harness2-")
        ]
        current["rules"] = kept + rules
        return current

    try:
        update_json(
            target,
            change,
            backup=target.with_name(f"hookify-rules.json.harness2-{_stamp()}.bak"),
        )
    except ValueError:
        log(f"hookify rules: {target} is not valid JSON; not touching it")
        return
    log(
        f"hookify rules: {len(rules)} harness2 rule(s) in {target} ({len(kept)} other rule(s) kept)"
    )


def install_wrapper(log=print) -> Path:
    bindir = Path(os.environ.get("HARNESS2_BIN") or Path.home() / ".local" / "bin")
    bindir.mkdir(parents=True, exist_ok=True)
    w = bindir / "harness2"
    w.write_text(
        "#!/bin/sh\n"
        "# Copyright (c) 2026 VitruvianSoftware\n"
        "# SPDX-License-Identifier: MIT\n"
        "# Installed by `bazel run //tools/harness2 -- install`: runs the installed Harness² CLI.\n"
        f'exec python3 "{plugin_dir() / "lib" / "cli.py"}" "$@"\n',
        encoding="utf-8",
    )
    os.chmod(w, 0o755)
    log(f"wrapper installed at {w}")
    return w


def seed_library(log=print) -> None:
    import library

    root = library_dir()
    root.mkdir(parents=True, exist_ok=True)
    src_root = ASSETS / "library"
    ids = {e.get("id") for e in library.load_index(root)["entries"]}
    for entry in sorted(p for p in src_root.iterdir() if p.is_dir()):
        if entry.name in ids or (root / entry.name).exists():
            continue
        md = (entry / "EXPERIENCE.md").read_text(encoding="utf-8")
        kws = [
            "icon",
            "image",
            "border",
            "crop",
            "resize",
            "upscale",
            "enlarge",
            "scale",
            "png",
            "pixel",
            "squircle",
            "margin",
        ]
        library.add_entry(
            md, plugin_dir(), entry.name, root=root, keywords=kws, entry_id=entry.name
        )
        log(f"library: seeded {entry.name}")


def install(
    reseed: bool = False,
    hookify_src: Optional[str] = None,
    prewarm: bool = True,
    log=print,
) -> int:
    import validator

    plugin = install_plugin(reseed=reseed, log=log)
    hk = install_hookify(hookify_source(hookify_src), log=log)
    enable_plugins(["harness2"] + (["hookify"] if hk else []), log=log)
    merge_hookify_rules(plugin, log=log)
    install_wrapper(log=log)
    seed_library(log=log)
    for d in ("state", "runs"):
        (harness2_home() / d).mkdir(parents=True, exist_ok=True)
    if prewarm and hk:
        prewarm_hookify(hk, log=log)
    problems = validator.validate_tree(plugin) + validator.validate_library(
        library_dir()
    )
    if problems:
        log("VALIDATION FAILED:\n  " + "\n  ".join(problems))
        return 1
    log("validation: harness and library pass all four rules")
    return 0
