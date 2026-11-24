# Copyright (c) 2026 VitruvianSoftware
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

"""Compute exact actions/setup-go v7.1.0 cache keys and Go cache paths."""

from __future__ import annotations

import argparse
import hashlib
import os
import platform as py_platform
import re
import subprocess
import sys
from pathlib import Path
from typing import Iterable

RUNNER_ARCH_TO_NODE = {
    "X64": "x64",
    "ARM64": "arm64",
    "X86": "ia32",
    "ARM": "arm",
}

MACHINE_TO_NODE = {
    "x86_64": "x64",
    "amd64": "x64",
    "arm64": "arm64",
    "aarch64": "arm64",
    "i386": "ia32",
    "i686": "ia32",
}


def node_arch(runner_arch: str = "") -> str:
    """Map GitHub RUNNER_ARCH (or host machine) to Node process.arch."""
    key = runner_arch.strip().upper()
    if key in RUNNER_ARCH_TO_NODE:
        return RUNNER_ARCH_TO_NODE[key]
    mach = py_platform.machine().strip().lower()
    return MACHINE_TO_NODE.get(mach, mach)


def _segment_matches(pat_seg: str, name: str) -> bool:
    """Match one path segment with `*` and `?` wildcards (dot=true)."""
    if pat_seg == "*":
        return True
    out = ["^"]
    i = 0
    while i < len(pat_seg):
        ch = pat_seg[i]
        if ch == "*":
            out.append(".*")
        elif ch == "?":
            out.append(".")
        elif ch == "[" and "]" in pat_seg[i + 1 :]:
            end = pat_seg.index("]", i + 1)
            cls = pat_seg[i + 1 : end]
            if cls.startswith("!"):
                cls = "^" + cls[1:]
            out.append(f"[{cls}]")
            i = end
        else:
            out.append(re.escape(ch))
        i += 1
    out.append("$")
    return re.match("".join(out), name) is not None


def _match_segments(pat_segs: list[str], rel_segs: list[str]) -> bool:
    """Match segment list `pat_segs` (with `**`) against `rel_segs`."""
    pi = 0
    ri = 0
    star_pi: int | None = None
    star_ri = 0
    while ri < len(rel_segs):
        if pi < len(pat_segs) and pat_segs[pi] == "**":
            star_pi = pi
            star_ri = ri
            pi += 1
        elif pi < len(pat_segs) and _segment_matches(pat_segs[pi], rel_segs[ri]):
            pi += 1
            ri += 1
        elif star_pi is not None:
            pi = star_pi + 1
            star_ri += 1
            ri = star_ri
        else:
            return False
    while pi < len(pat_segs) and pat_segs[pi] == "**":
        pi += 1
    return pi == len(pat_segs)


def _has_wildcard(segment: str) -> bool:
    return any(ch in segment for ch in ("*", "?", "["))


def _parse_patterns(patterns_text: str) -> list[tuple[bool, list[str]]]:
    parsed: list[tuple[bool, list[str]]] = []
    for raw in patterns_text.replace("\r\n", "\n").replace("\r", "\n").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        negate = line.startswith("!")
        pat = line[1:] if negate else line
        pat = pat.replace("\\", "/")
        segs = [s for s in pat.split("/") if s and s != "."]
        if segs:
            parsed.append((negate, segs))
    return parsed


def _search_paths(
    patterns: list[tuple[bool, list[str]]], workspace: Path
) -> list[Path]:
    """Match `@actions/glob` `getSearchPaths`: unique non-descendant prefixes in order."""
    candidates: list[Path] = []
    for negate, segs in patterns:
        if negate:
            continue
        static: list[str] = []
        for seg in segs:
            if _has_wildcard(seg):
                break
            static.append(seg)
        sp = workspace.joinpath(*static) if static else workspace
        candidates.append(sp)

    candidate_strs = {os.path.normpath(str(c)) for c in candidates}
    result: list[Path] = []
    seen_included: set[str] = set()
    for sp in candidates:
        norm = os.path.normpath(str(sp))
        if norm in seen_included:
            continue
        has_ancestor = False
        parent = os.path.dirname(norm)
        while parent != norm:
            if parent in candidate_strs:
                has_ancestor = True
                break
            cur = parent
            parent = os.path.dirname(cur)
            if cur == parent:
                break
        if not has_ancestor:
            seen_included.add(norm)
            result.append(sp)
    return result


def _matches_any(rel_segs: list[str], patterns: list[tuple[bool, list[str]]]) -> bool:
    matched = False
    for negate, pat_segs in patterns:
        if _match_segments(pat_segs, rel_segs):
            matched = not negate
    return matched


def _partial_match(rel_segs: list[str], patterns: list[tuple[bool, list[str]]]) -> bool:
    for negate, pat_segs in patterns:
        if negate:
            continue
        # Any prefix of pat_segs up to `**` or matching len(rel_segs)
        if "**" in pat_segs:
            idx = pat_segs.index("**")
            if len(rel_segs) >= idx:
                if _match_segments(pat_segs[:idx], rel_segs[:idx]):
                    return True
            else:
                if _match_segments(pat_segs[: len(rel_segs)], rel_segs):
                    return True
        elif len(rel_segs) <= len(pat_segs):
            if _match_segments(pat_segs[: len(rel_segs)], rel_segs):
                return True
    return False


def _walk_dfs(
    search_path: Path, workspace: Path, patterns: list[tuple[bool, list[str]]]
) -> Iterable[Path]:
    """Walk `search_path` in `@actions/glob` DFS entry order."""
    stack = [search_path]
    while stack:
        item = stack.pop()
        try:
            st = os.lstat(item)
        except OSError:
            continue
        try:
            rel = item.relative_to(workspace)
            rel_segs = list(rel.parts)
        except ValueError:
            rel_segs = []

        if rel_segs:
            is_match = _matches_any(rel_segs, patterns)
            is_partial = is_match or _partial_match(rel_segs, patterns)
            if not is_match and not is_partial:
                continue

        if os.path.isdir(item):
            if rel_segs and not (
                _matches_any(rel_segs, patterns) or _partial_match(rel_segs, patterns)
            ):
                continue
            try:
                children = sorted(os.listdir(item))
            except OSError:
                continue
            for name in reversed(children):
                stack.append(item / name)
        elif os.path.isfile(item):
            if rel_segs and _matches_any(rel_segs, patterns):
                yield item


def hash_file_contents_in_order(contents: Iterable[bytes]) -> str:
    """Compute `@actions/glob` `hashFiles` double-SHA-256 over ordered file bytes."""
    outer = hashlib.sha256()
    count = 0
    for data in contents:
        outer.update(hashlib.sha256(data).digest())
        count += 1
    return outer.hexdigest() if count > 0 else ""


def glob_hash_files(patterns_text: str, workspace: Path) -> tuple[str, int]:
    """Compute `@actions/glob` `hashFiles()` digest for `patterns_text` under `workspace`."""
    resolved_ws = workspace.resolve()
    patterns = _parse_patterns(patterns_text)
    if not patterns:
        return "", 0

    outer = hashlib.sha256()
    count = 0
    for sp in _search_paths(patterns, workspace):
        for matched in _walk_dfs(sp, workspace, patterns):
            try:
                resolved = matched.resolve()
                resolved.relative_to(resolved_ws)
            except (OSError, ValueError):
                continue
            if not resolved.is_file():
                continue
            outer.update(hashlib.sha256(resolved.read_bytes()).digest())
            count += 1
    return (outer.hexdigest(), count) if count > 0 else ("", 0)


def build_cache_key(
    runner_os: str,
    arch: str,
    image_os: str | None,
    go_version: str,
    file_hash: str,
) -> str:
    """Construct the exact `actions/setup-go` v7.1.0 cache primary key."""
    linux_version = (
        f"{image_os if image_os is not None else 'undefined'}-"
        if runner_os == "Linux"
        else ""
    )
    return f"setup-go-{runner_os}-{arch}-{linux_version}go-{go_version}-{file_hash}"


def resolve_go_cache_paths(
    gomodcache_env: str = "", gocache_env: str = ""
) -> tuple[str, str]:
    """Return `(GOMODCACHE, GOCACHE)` in `actions/setup-go` `package-managers.ts` order."""
    gomodcache = (
        gomodcache_env.strip()
        or subprocess.check_output(["go", "env", "GOMODCACHE"], text=True).strip()
    )
    gocache = (
        gocache_env.strip()
        or subprocess.check_output(["go", "env", "GOCACHE"], text=True).strip()
    )
    return gomodcache, gocache


def _write_github_output(output_path: Path, values: dict[str, str]) -> None:
    with output_path.open("a", encoding="utf-8") as fh:
        for k, v in values.items():
            fh.write(f"{k}={v}\n")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Compute actions/setup-go cache key and paths"
    )
    parser.add_argument(
        "--github-output", required=True, help="Path to GITHUB_OUTPUT file"
    )
    args = parser.parse_args(argv)

    workspace = Path(os.environ.get("GITHUB_WORKSPACE") or ".").resolve()
    dep_pattern = os.environ.get("CACHE_DEPENDENCY_PATH", "").strip() or "go.mod"
    file_hash, count = glob_hash_files(dep_pattern, workspace)

    gomodcache, gocache = resolve_go_cache_paths(
        os.environ.get("GOMODCACHE_OUT", ""),
        os.environ.get("GOCACHE_OUT", ""),
    )

    if not file_hash:
        print(
            f"::warning::No dependency files matched {dep_pattern!r}; skipping Go cache restore/save",
            file=sys.stderr,
        )
        _write_github_output(
            Path(args.github_output),
            {"key": "", "gomodcache": gomodcache, "gocache": gocache},
        )
        return 0

    runner_os = os.environ.get("RUNNER_OS", "").strip()
    arch = node_arch(os.environ.get("RUNNER_ARCH", ""))
    image_os = os.environ.get("ImageOS")
    go_version = os.environ.get("GO_VERSION", "").strip()
    key = build_cache_key(runner_os, arch, image_os, go_version, file_hash)

    print(f"Go cache key ({count} dependency file(s)): {key}")
    _write_github_output(
        Path(args.github_output),
        {"key": key, "gomodcache": gomodcache, "gocache": gocache},
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
