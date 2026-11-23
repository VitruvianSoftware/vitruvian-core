#!/usr/bin/env python3
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

"""Assemble the exported vitruvian-sdk mirror layout from tools/copybara/copy.bara.sky
and run the mirror's Cargo checks against it.

Reads subtree, extra_exports, origin_only_exclude, _monorepo_only, and
export_transformations directly from copy.bara.sky (no duplicated paths or
rewrites) so any broken Copybara rewrite fails before merge.

Also guards vendor/vitruvian-pycompat/ against leaking monorepo-only files:
verifies that the assembled vendored tree matches EXPECTED_VENDORED_FILES
exactly and contains no *.sh or README* files.
"""

from __future__ import annotations

import argparse
import ast
import os
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path


EXPECTED_VENDORED_FILES: tuple[str, ...] = (
    "Cargo.toml",
    "src/argparse.rs",
    "src/http.rs",
    "src/json.rs",
    "src/lib.rs",
    "src/pyerr.rs",
    "src/pystr.rs",
    "src/unicode_tables.rs",
)


@dataclass(frozen=True)
class ReplaceRule:
    before: str
    after: str
    paths: list[str]
    regex_groups: dict[str, str]
    multiline: bool


def _eval_sky_expr(node: ast.AST, env: dict[str, object]) -> object:
    if isinstance(node, ast.Constant):
        return node.value
    if isinstance(node, ast.Name):
        if node.id not in env:
            raise ValueError(f"Unsupported identifier in copy.bara.sky: {node.id}")
        return env[node.id]
    if isinstance(node, ast.List):
        return [_eval_sky_expr(elt, env) for elt in node.elts]
    if isinstance(node, ast.Tuple):
        return tuple(_eval_sky_expr(elt, env) for elt in node.elts)
    if isinstance(node, ast.Dict):
        return {
            _eval_sky_expr(k, env): _eval_sky_expr(v, env)
            for k, v in zip(node.keys, node.values)
            if k is not None
        }
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
        left = _eval_sky_expr(node.left, env)
        right = _eval_sky_expr(node.right, env)
        return left + right  # type: ignore[operator]
    if isinstance(node, ast.Call):
        if (
            isinstance(node.func, ast.Name)
            and node.func.id == "glob"
            and len(node.args) == 1
        ):
            pats = _eval_sky_expr(node.args[0], env)
            if not isinstance(pats, list):
                raise ValueError("glob() expects a list")
            return [str(p) for p in pats]
        if (
            isinstance(node.func, ast.Attribute)
            and isinstance(node.func.value, ast.Name)
            and node.func.value.id == "core"
            and node.func.attr == "replace"
        ):
            kw = {
                k.arg: _eval_sky_expr(k.value, env)
                for k in node.keywords
                if k.arg is not None
            }
            return ReplaceRule(
                before=str(kw["before"]),
                after=str(kw["after"]),
                paths=[str(p) for p in kw.get("paths", [])],  # type: ignore[union-attr]
                regex_groups={
                    str(gk): str(gv)
                    for gk, gv in kw.get("regex_groups", {}).items()  # type: ignore[union-attr]
                },
                multiline=bool(kw.get("multiline", False)),
            )
    raise ValueError(f"Unsupported AST node in copy.bara.sky: {ast.dump(node)}")


def load_sdk_export_spec(sky_path: Path) -> dict[str, object]:
    tree = ast.parse(sky_path.read_text(encoding="utf-8"), filename=str(sky_path))

    monorepo_only_fn: ast.FunctionDef | None = None
    components_node: ast.AST | None = None

    for stmt in tree.body:
        if isinstance(stmt, ast.FunctionDef) and stmt.name == "_monorepo_only":
            monorepo_only_fn = stmt
        elif isinstance(stmt, ast.Assign):
            for target in stmt.targets:
                if isinstance(target, ast.Name) and target.id == "COMPONENTS":
                    components_node = stmt.value

    if monorepo_only_fn is None or components_node is None:
        raise RuntimeError(
            f"Could not find _monorepo_only and COMPONENTS in {sky_path}"
        )

    def eval_monorepo_only(component: str) -> list[str]:
        for s in monorepo_only_fn.body:
            if isinstance(s, ast.Return) and s.value is not None:
                res = _eval_sky_expr(s.value, {"component": component})
                if isinstance(res, list):
                    return [str(x) for x in res]
        raise RuntimeError("Could not evaluate _monorepo_only return expression")

    if not isinstance(components_node, ast.List):
        raise RuntimeError("COMPONENTS is not a list")

    sdk_cfg: dict[str, object] | None = None
    for elt in components_node.elts:
        if not isinstance(elt, ast.Dict):
            continue
        is_sdk = False
        for k, v in zip(elt.keys, elt.values):
            if (
                isinstance(k, ast.Constant)
                and k.value == "name"
                and isinstance(v, ast.Constant)
                and v.value == "vitruvian-sdk"
            ):
                is_sdk = True
                break
        if is_sdk:
            evaluated = _eval_sky_expr(elt, {})
            if isinstance(evaluated, dict):
                sdk_cfg = evaluated
                break

    if sdk_cfg is None:
        raise RuntimeError(f"No vitruvian-sdk entry found in COMPONENTS of {sky_path}")

    subtree = str(sdk_cfg["subtree"])
    extra_exports = {
        str(k): str(v)
        for k, v in dict(sdk_cfg.get("extra_exports", {})).items()  # type: ignore[arg-type]
    }
    origin_only_exclude = [
        str(x)
        for x in list(sdk_cfg.get("origin_only_exclude", []))  # type: ignore[arg-type]
    ]
    transforms = list(sdk_cfg.get("export_transformations", []))  # type: ignore[arg-type]

    subtree_excludes = eval_monorepo_only(subtree) + origin_only_exclude
    extra_excludes: dict[str, list[str]] = {}
    for src in extra_exports:
        extra_excludes[src] = eval_monorepo_only(src) + [
            p for p in origin_only_exclude if p.startswith(src + "/")
        ]

    return {
        "subtree": subtree,
        "subtree_excludes": subtree_excludes,
        "extra_exports": extra_exports,
        "extra_excludes": extra_excludes,
        "transforms": transforms,
    }


def _glob_to_regex(pattern: str) -> re.Pattern[str]:
    parts = pattern.split("/")
    regex_parts: list[str] = ["^"]
    for idx, part in enumerate(parts):
        is_last = idx == len(parts) - 1
        if part == "**":
            if is_last:
                regex_parts.append("(?:.*)" if idx == 0 else "(?:/.*)?")
            elif idx == 0:
                regex_parts.append("(?:.+/)?")
            else:
                regex_parts.append("/(?:.+/)?")
        else:
            seg = "".join("[^/]*" if ch == "*" else re.escape(ch) for ch in part)
            if idx > 0 and parts[idx - 1] != "**":
                regex_parts.append("/")
            regex_parts.append(seg)
    regex_parts.append("$")
    return re.compile("".join(regex_parts))


def _matches_any(rel_path: str, patterns: list[re.Pattern[str]]) -> bool:
    return any(p.match(rel_path) is not None for p in patterns)


def _copy_filtered_tree(
    repo_root: Path,
    src_rel: str,
    dest_root: Path,
    exclude_patterns: list[str],
) -> int:
    src_dir = repo_root / src_rel
    if not src_dir.is_dir():
        raise RuntimeError(f"Source directory missing: {src_dir}")
    compiled = [_glob_to_regex(p) for p in exclude_patterns]
    copied = 0
    for root, dirs, files in os.walk(src_dir):
        # Skip local build/cache directories that never exist in a clean checkout.
        dirs[:] = sorted(
            d
            for d in dirs
            if d not in {"target", ".build", ".git", "__pycache__", "node_modules"}
        )
        root_path = Path(root)
        for fname in sorted(files):
            src_file = root_path / fname
            rel_inside = src_file.relative_to(src_dir).as_posix()
            repo_rel = f"{src_rel}/{rel_inside}"
            if _matches_any(repo_rel, compiled):
                continue
            dst_file = dest_root / rel_inside
            dst_file.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src_file, dst_file)
            copied += 1
    return copied


def _apply_replace(dest_dir: Path, rule: ReplaceRule) -> int:
    if rule.regex_groups:
        raise RuntimeError(
            f"regex_groups in core.replace is not supported by this checker: {rule}"
        )
    patterns = [_glob_to_regex(p) for p in rule.paths]
    matched_files = 0
    replaced_files = 0
    for root, dirs, files in os.walk(dest_dir):
        dirs[:] = sorted(d for d in dirs if d not in {"target", ".git"})
        for fname in sorted(files):
            fpath = Path(root) / fname
            rel = fpath.relative_to(dest_dir).as_posix()
            if not _matches_any(rel, patterns):
                continue
            matched_files += 1
            text = fpath.read_text(encoding="utf-8")
            if rule.before in text:
                fpath.write_text(
                    text.replace(rule.before, rule.after), encoding="utf-8"
                )
                replaced_files += 1
    if matched_files == 0:
        raise RuntimeError(f"core.replace paths {rule.paths!r} matched 0 files")
    if replaced_files == 0:
        raise RuntimeError(
            f"core.replace failed to find {rule.before!r} in matched files {rule.paths!r}"
        )
    return replaced_files


def verify_vendored_pycompat(dest_dir: Path) -> None:
    """Verify vendor/vitruvian-pycompat/ matches EXPECTED_VENDORED_FILES with no leaks."""
    vendored_dir = dest_dir / "vendor" / "vitruvian-pycompat"
    if not vendored_dir.is_dir():
        raise RuntimeError(
            f"vendor/vitruvian-pycompat/ directory missing; expected {list(EXPECTED_VENDORED_FILES)}"
        )

    actual_files = sorted(
        p.relative_to(vendored_dir).as_posix()
        for p in vendored_dir.rglob("*")
        if p.is_file() or p.is_symlink()
    )
    expected_files = sorted(EXPECTED_VENDORED_FILES)

    extra = sorted(set(actual_files) - set(expected_files))
    missing = sorted(set(expected_files) - set(actual_files))
    forbidden = sorted(
        rel
        for rel in actual_files
        if Path(rel).name.endswith(".sh") or Path(rel).name.startswith("README")
    )

    errors: list[str] = []
    if extra or missing:
        errors.append(
            "assembled vendor/vitruvian-pycompat/ file list differs from EXPECTED_VENDORED_FILES"
        )
        if extra:
            errors.append(
                "unexpected files in vendor/vitruvian-pycompat/ (not in EXPECTED_VENDORED_FILES): "
                + ", ".join(extra)
            )
        if missing:
            errors.append(
                "missing files from EXPECTED_VENDORED_FILES (absent in vendor/vitruvian-pycompat/): "
                + ", ".join(missing)
            )
    if forbidden:
        errors.append(
            "forbidden *.sh or README* files found under vendor/vitruvian-pycompat/: "
            + ", ".join(forbidden)
        )

    if errors:
        raise RuntimeError(
            "vendor/vitruvian-pycompat/ guard failed:\n" + "\n".join(errors)
        )

    print(
        f"verified vendor/vitruvian-pycompat/ ({len(actual_files)} expected files, no *.sh or README* leaks)"
    )


def assemble_exported_tree(repo_root: Path, dest_dir: Path) -> None:
    sky_path = repo_root / "tools" / "copybara" / "copy.bara.sky"
    spec = load_sdk_export_spec(sky_path)

    subtree = str(spec["subtree"])
    subtree_excludes: list[str] = spec["subtree_excludes"]  # type: ignore[assignment]
    extra_exports: dict[str, str] = spec["extra_exports"]  # type: ignore[assignment]
    extra_excludes: dict[str, list[str]] = spec["extra_excludes"]  # type: ignore[assignment]
    transforms: list[ReplaceRule] = spec["transforms"]  # type: ignore[assignment]

    n_sdk = _copy_filtered_tree(repo_root, subtree, dest_dir, subtree_excludes)
    print(f"assembled {subtree}/ -> <mirror>/ ({n_sdk} files)")

    for src_rel, dst_rel in extra_exports.items():
        n_extra = _copy_filtered_tree(
            repo_root, src_rel, dest_dir / dst_rel, extra_excludes[src_rel]
        )
        print(f"assembled {src_rel}/ -> <mirror>/{dst_rel}/ ({n_extra} files)")

    for rule in transforms:
        n_rep = _apply_replace(dest_dir, rule)
        print(
            f"applied core.replace ({rule.before!r} -> {rule.after!r}) to {n_rep} file(s)"
        )

    verify_vendored_pycompat(dest_dir)


def _resolve_tool(env_var: str, expected_name: str) -> str | None:
    raw = os.environ.get(env_var, "").strip()
    if not raw:
        return None
    candidates = raw.split()
    for c in candidates:
        if os.path.basename(c) == expected_name and os.path.exists(c):
            return os.path.abspath(c)
    for c in candidates:
        if os.path.exists(c):
            return os.path.abspath(c)
    raise RuntimeError(f"{env_var}={raw!r} did not resolve to an existing file")


def _run(cmd: list[str], cwd: Path, env: dict[str, str]) -> None:
    print(f"+ (cd {cwd} && {' '.join(cmd)})", flush=True)
    subprocess.run(cmd, cwd=cwd, env=env, check=True)


def run_mirror_cargo_checks(export_dir: Path) -> None:
    cargo_bin = _resolve_tool("REAL_CARGO", "cargo") or shutil.which("cargo")
    rustc_bin = _resolve_tool("REAL_RUSTC", "rustc")
    rustdoc_bin = _resolve_tool("REAL_RUSTDOC", "rustdoc")
    if not cargo_bin:
        raise RuntimeError(
            "cargo binary not found (set REAL_CARGO or put cargo on PATH)"
        )

    env = os.environ.copy()
    extra_dirs: list[str] = []
    if rustc_bin:
        env["RUSTC"] = rustc_bin
        extra_dirs.append(os.path.dirname(rustc_bin))
    if rustdoc_bin:
        env["RUSTDOC"] = rustdoc_bin
        extra_dirs.append(os.path.dirname(rustdoc_bin))
    if extra_dirs:
        extra_dirs.append(os.path.dirname(cargo_bin))
        env["PATH"] = (
            os.pathsep.join(dict.fromkeys(extra_dirs))
            + os.pathsep
            + env.get("PATH", "")
        )

    # Mirrors .github/workflows/vitruvian-sdk-mirror-checks.yaml lines 78-87
    # and the exported mirror's kits.yml Rust sample check.
    _run(
        [cargo_bin, "test", "--locked", "--manifest-path", "verification/Cargo.toml"],
        cwd=export_dir,
        env=env,
    )
    _run(
        [
            cargo_bin,
            "run",
            "--locked",
            "--manifest-path",
            "verification/Cargo.toml",
            "--bin",
            "sync-templates",
            "--",
            "--check",
        ],
        cwd=export_dir,
        env=env,
    )
    _run(
        [
            cargo_bin,
            "build",
            "--release",
            "--manifest-path",
            "samples/hello-rust/Cargo.toml",
        ],
        cwd=export_dir,
        env=env,
    )

    with tempfile.TemporaryDirectory(prefix="sdk-export-sample-") as sample_tmp:
        sample_dir = Path(sample_tmp) / "hello-rust"
        bin_dir = sample_dir / "bin"
        bin_dir.mkdir(parents=True, exist_ok=True)
        # In the exported layout (no monorepo workspace above it), Cargo builds into
        # samples/hello-rust/target/release/tool.
        built_tool = (
            export_dir / "samples" / "hello-rust" / "target" / "release" / "tool"
        )
        if not built_tool.is_file():
            raise RuntimeError(f"Expected built sample binary missing: {built_tool}")
        shutil.copy2(built_tool, bin_dir / "tool")
        shutil.copy2(
            export_dir / "samples" / "hello-rust" / "vitruvian-tool.json",
            sample_dir / "vitruvian-tool.json",
        )
        _run(
            [
                cargo_bin,
                "run",
                "--locked",
                "--manifest-path",
                "verification/Cargo.toml",
                "--bin",
                "conformance",
                "--",
                str(sample_dir),
                "--expect-refusal",
            ],
            cwd=export_dir,
            env=env,
        )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--export-only",
        type=Path,
        default=None,
        help="Assemble the exported tree into this directory and exit without running Cargo.",
    )
    args = parser.parse_args(argv)

    repo_root = Path(
        os.environ.get("BUILD_WORKSPACE_DIRECTORY") or os.getcwd()
    ).resolve()

    try:
        if args.export_only is not None:
            dest = args.export_only.resolve()
            if dest.exists():
                shutil.rmtree(dest)
            dest.mkdir(parents=True, exist_ok=True)
            assemble_exported_tree(repo_root, dest)
            return 0

        with tempfile.TemporaryDirectory(prefix="vitruvian-sdk-export-") as tmp:
            export_dir = Path(tmp) / "vitruvian-sdk"
            export_dir.mkdir(parents=True, exist_ok=True)
            assemble_exported_tree(repo_root, export_dir)
            run_mirror_cargo_checks(export_dir)
        return 0
    except RuntimeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
