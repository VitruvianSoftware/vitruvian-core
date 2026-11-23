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
exactly and contains no *.sh or README* files, and verifies that every concrete
Rust version installed by the mirror's workflows is at least as new as the
highest rust-version declared in any exported Cargo.toml.
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


_VERSION_RE = re.compile(r"^(\d+)\.(\d+)(?:\.(\d+))?$")
_RUST_CHANNELS = frozenset({"stable", "beta", "nightly"})
_GIT_SHA_RE = re.compile(r"^[0-9a-fA-F]{40}$")
_MATRIX_EXPR_RE = re.compile(r"^\$\{\{\s*matrix\.([A-Za-z0-9_-]+)\s*\}\}$")
_SHELL_VAR_RE = re.compile(
    r"^\$(?:\{([A-Za-z_][A-Za-z0-9_]*)\}|([A-Za-z_][A-Za-z0-9_]*))$"
)
_BLOCK_SCALAR_RE = re.compile(r"^[|>][+-]?\d*(?:\s+#.*)?$")
_CARGO_RUST_VERSION_RE = re.compile(r'^\s*rust-version\s*=\s*"([^"]+)"')
_RUSTUP_CMD_RE = re.compile(
    r"\brustup\s+(?:toolchain\s+(?:install|add)|default|override\s+set)(?:\s+([^;&|\n]*))?"
)
_RUSTUP_TOKEN_RE = re.compile(r'"[^"]*"|\'[^\']*\'|\$\{\{[^}]*\}\}|\S+')
_YAML_RUST_KEY_RE = re.compile(r"^(\s*)rust\s*:(.*)$")
_YAML_KEY_VAL_RE = re.compile(r"^([A-Za-z0-9_-]+)\s*:(.*)$")
_YAML_LIST_ITEM_RE = re.compile(r"^(\s*)-\s*(.+)$")
_FLOW_TOOLCHAIN_RE = re.compile(r"\btoolchain\s*:\s*([^,}]+)")


def parse_rust_version(raw: str) -> tuple[int, int, int] | None:
    """Parse a concrete Rust version (MAJOR.MINOR or MAJOR.MINOR.PATCH) into a tuple.

    Returns None for symbolic channels (e.g. 'stable') or shell/template expressions.
    """
    m = _VERSION_RE.match(raw.strip())
    if not m:
        return None
    return (int(m.group(1)), int(m.group(2)), int(m.group(3) or 0))


def _strip_yaml_comment(raw: str) -> str:
    in_single = False
    in_double = False
    for idx, ch in enumerate(raw):
        if ch == "'" and not in_double:
            in_single = not in_single
        elif ch == '"' and not in_single:
            in_double = not in_double
        elif ch == "#" and not in_single and not in_double:
            if idx == 0 or raw[idx - 1].isspace():
                return raw[:idx].rstrip()
    return raw.rstrip()


def _unquote(raw: str) -> str:
    s = raw.strip()
    if len(s) >= 2 and (
        (s[0] == '"' and s[-1] == '"') or (s[0] == "'" and s[-1] == "'")
    ):
        return s[1:-1]
    return s


def collect_cargo_rust_versions(
    root_dir: Path,
) -> list[tuple[str, str, tuple[int, int, int]]]:
    """Return (rel_path, raw_version, parsed_tuple) for every Cargo.toml rust-version."""
    found: list[tuple[str, str, tuple[int, int, int]]] = []
    for root, dirs, files in os.walk(root_dir):
        dirs[:] = sorted(
            d for d in dirs if d not in {"target", ".git", ".build", "node_modules"}
        )
        for fname in sorted(files):
            if fname != "Cargo.toml":
                continue
            fpath = Path(root) / fname
            rel = fpath.relative_to(root_dir).as_posix()
            for line in fpath.read_text(encoding="utf-8").splitlines():
                stripped = line.strip()
                if not stripped or stripped.startswith("#"):
                    continue
                m = _CARGO_RUST_VERSION_RE.match(line)
                if not m:
                    continue
                raw_ver = m.group(1).strip()
                parsed = parse_rust_version(raw_ver)
                if parsed is None:
                    raise RuntimeError(f"{rel}: unparseable rust-version {raw_ver!r}")
                found.append((rel, raw_ver, parsed))
    return found


def _extract_rustup_versions(cmd_tail: str) -> list[str]:
    tokens = _RUSTUP_TOKEN_RE.findall(cmd_tail)
    versions: list[str] = []
    skip_next = False
    value_flags = {"--profile", "-c", "--component", "-t", "--target"}
    for tok in tokens:
        if tok in {"&&", "||", ";", "|"}:
            break
        if skip_next:
            skip_next = False
            continue
        if tok in value_flags:
            skip_next = True
            continue
        if tok.startswith("-"):
            continue
        versions.append(_unquote(tok))
    return versions


def _scan_workflow_rust_setups(
    root_dir: Path,
) -> tuple[list[tuple[str, int, str, tuple[int, int, int]]], int, list[str]]:
    """Scan mirror workflows for Rust toolchain setups in fail-closed mode.

    Returns ``(concrete_versions, setup_count, errors)`` where:
    - ``concrete_versions`` holds ``(rel_path, line_no, raw_version, parsed_tuple)``.
    - ``setup_count`` counts all recognised concrete, channel, or resolved setups.
    - ``errors`` lists every unparseable or unsupported Rust setup with file and line.
    """
    workflows_dir = root_dir / ".github" / "workflows"
    if not workflows_dir.is_dir():
        raise RuntimeError(f"Mirror workflows directory missing: {workflows_dir}")

    workflow_files = sorted(
        p
        for p in workflows_dir.iterdir()
        if p.is_file() and p.suffix in {".yml", ".yaml"}
    )
    concrete_versions: list[tuple[str, int, str, tuple[int, int, int]]] = []
    setup_count = 0
    errors: list[str] = []

    for wf_path in workflow_files:
        rel = wf_path.relative_to(root_dir).as_posix()
        lines = wf_path.read_text(encoding="utf-8").splitlines()

        has_rust_matrix = False
        pending_matrix_refs: list[tuple[int, str, str]] = []
        pending_env_refs: list[tuple[int, str, str, dict[str, str]]] = []
        in_rust_list_indent: int | None = None
        in_block_scalar_indent: int | None = None
        block_scalar_is_run = False

        # Indent-scoped non-step env blocks (workflow/job level), plus per-step env.
        outer_env_scopes: list[tuple[int, dict[str, str]]] = []
        in_outer_env_indent: int | None = None

        step_indent: int | None = None
        uses_line: int | None = None
        uses_raw: str | None = None
        in_with_indent: int | None = None
        toolchain_line: int | None = None
        toolchain_raw: str | None = None
        in_step_env_indent: int | None = None
        step_env: dict[str, str] = {}

        def _combined_env() -> dict[str, str]:
            merged: dict[str, str] = {}
            for _, scope_vars in outer_env_scopes:
                merged.update(scope_vars)
            merged.update(step_env)
            return merged

        def _record_rust_value(
            line_no: int,
            raw_val: str,
            context: str,
            *,
            allow_matrix: bool,
            env_map: dict[str, str] | None,
        ) -> None:
            nonlocal setup_count
            val = _unquote(raw_val).strip()
            parsed = parse_rust_version(val)
            if parsed is not None:
                concrete_versions.append((rel, line_no, val, parsed))
                setup_count += 1
                return
            if val in _RUST_CHANNELS:
                setup_count += 1
                return
            if allow_matrix:
                matrix_m = _MATRIX_EXPR_RE.match(val)
                if matrix_m:
                    pending_matrix_refs.append((line_no, matrix_m.group(1), val))
                    return
            if env_map is not None:
                env_m = _SHELL_VAR_RE.match(val)
                if env_m:
                    var_name = env_m.group(1) or env_m.group(2)
                    pending_env_refs.append((line_no, var_name, val, dict(env_map)))
                    return
            errors.append(
                f"{rel}:{line_no}: unparseable Rust version/toolchain {val!r} in {context}"
            )

        def _scan_run_line(line_no: int, text: str, env_map: dict[str, str]) -> None:
            cleaned = _strip_yaml_comment(text)
            for rustup_m in _RUSTUP_CMD_RE.finditer(cleaned):
                tail = rustup_m.group(1) or ""
                args = _extract_rustup_versions(tail)
                if not args:
                    errors.append(
                        f"{rel}:{line_no}: rustup command has no toolchain argument: {cleaned.strip()!r}"
                    )
                    continue
                for arg in args:
                    _record_rust_value(
                        line_no,
                        arg,
                        "rustup command",
                        allow_matrix=True,
                        env_map=env_map,
                    )

        def _flush_step() -> None:
            nonlocal setup_count, step_indent, uses_line, uses_raw
            nonlocal in_with_indent, toolchain_line, toolchain_raw
            nonlocal in_step_env_indent, step_env

            if uses_raw is not None and uses_line is not None:
                uses_val = _unquote(_strip_yaml_comment(uses_raw)).strip()
                if "@" in uses_val:
                    action_name, ref = uses_val.split("@", 1)
                else:
                    action_name, ref = uses_val, ""
                action_lower = action_name.strip().lower()
                ref = ref.strip()

                if action_lower == "dtolnay/rust-toolchain":
                    has_toolchain = toolchain_raw is not None
                    parsed_ref = parse_rust_version(ref)
                    if parsed_ref is not None:
                        concrete_versions.append((rel, uses_line, ref, parsed_ref))
                        setup_count += 1
                    elif ref in _RUST_CHANNELS:
                        setup_count += 1
                    elif has_toolchain and (
                        ref == "master" or _GIT_SHA_RE.match(ref) is not None
                    ):
                        pass
                    else:
                        errors.append(
                            f"{rel}:{uses_line}: unparseable dtolnay/rust-toolchain ref {ref!r} in {uses_val!r}"
                        )

                    if has_toolchain and toolchain_line is not None:
                        assert toolchain_raw is not None
                        tc_val = _unquote(_strip_yaml_comment(toolchain_raw)).strip()
                        _record_rust_value(
                            toolchain_line,
                            tc_val,
                            "dtolnay/rust-toolchain with.toolchain",
                            allow_matrix=True,
                            env_map=None,
                        )
                elif "toolchain" in action_lower:
                    errors.append(
                        f"{rel}:{uses_line}: unsupported Rust toolchain action {uses_val!r}"
                    )

            step_indent = None
            uses_line = None
            uses_raw = None
            in_with_indent = None
            toolchain_line = None
            toolchain_raw = None
            in_step_env_indent = None
            step_env = {}

        def _handle_step_key(
            key: str, raw_val: str, line_no: int, block_indent: int
        ) -> None:
            nonlocal uses_line, uses_raw, in_with_indent
            nonlocal toolchain_line, toolchain_raw, in_step_env_indent
            nonlocal in_block_scalar_indent, block_scalar_is_run

            stripped_val = raw_val.strip()
            if key == "uses":
                uses_line = line_no
                uses_raw = raw_val
            elif key == "run":
                if _BLOCK_SCALAR_RE.match(stripped_val):
                    in_block_scalar_indent = block_indent
                    block_scalar_is_run = True
                else:
                    _scan_run_line(
                        line_no,
                        _unquote(_strip_yaml_comment(raw_val)),
                        _combined_env(),
                    )
            elif key == "with":
                cleaned_val = _strip_yaml_comment(raw_val).strip()
                if not cleaned_val:
                    in_with_indent = block_indent
                elif cleaned_val.startswith("{") and cleaned_val.endswith("}"):
                    flow_m = _FLOW_TOOLCHAIN_RE.search(cleaned_val[1:-1])
                    if flow_m:
                        toolchain_line = line_no
                        toolchain_raw = flow_m.group(1)
            elif key == "env":
                cleaned_val = _strip_yaml_comment(raw_val).strip()
                if not cleaned_val:
                    in_step_env_indent = block_indent
            elif _BLOCK_SCALAR_RE.match(stripped_val):
                in_block_scalar_indent = block_indent
                block_scalar_is_run = False

        for line_no, line in enumerate(lines, start=1):
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue

            indent = len(line) - len(line.lstrip(" "))

            if in_block_scalar_indent is not None:
                if indent > in_block_scalar_indent:
                    if block_scalar_is_run:
                        _scan_run_line(line_no, line, _combined_env())
                    continue
                in_block_scalar_indent = None
                block_scalar_is_run = False

            if in_with_indent is not None and indent <= in_with_indent:
                in_with_indent = None
            if in_step_env_indent is not None and indent <= in_step_env_indent:
                in_step_env_indent = None
            if in_outer_env_indent is not None and indent <= in_outer_env_indent:
                in_outer_env_indent = None
            while outer_env_scopes and indent <= outer_env_scopes[-1][0]:
                outer_env_scopes.pop()
            if in_rust_list_indent is not None and indent <= in_rust_list_indent:
                in_rust_list_indent = None
            if step_indent is not None and indent <= step_indent:
                _flush_step()

            if in_rust_list_indent is not None:
                item_m = _YAML_LIST_ITEM_RE.match(line)
                if item_m:
                    val = _unquote(_strip_yaml_comment(item_m.group(2)))
                    has_rust_matrix = True
                    _record_rust_value(
                        line_no,
                        val,
                        "rust matrix",
                        allow_matrix=False,
                        env_map=None,
                    )
                    continue
                in_rust_list_indent = None

            if in_with_indent is not None:
                kv_m = _YAML_KEY_VAL_RE.match(stripped)
                if kv_m:
                    if kv_m.group(1) == "toolchain":
                        toolchain_line = line_no
                        toolchain_raw = kv_m.group(2)
                    elif _BLOCK_SCALAR_RE.match(kv_m.group(2).strip()):
                        in_block_scalar_indent = indent
                        block_scalar_is_run = False
                continue

            if in_step_env_indent is not None:
                kv_m = _YAML_KEY_VAL_RE.match(stripped)
                if kv_m:
                    if _BLOCK_SCALAR_RE.match(kv_m.group(2).strip()):
                        in_block_scalar_indent = indent
                        block_scalar_is_run = False
                    else:
                        step_env[kv_m.group(1)] = _unquote(
                            _strip_yaml_comment(kv_m.group(2))
                        ).strip()
                continue

            if in_outer_env_indent is not None and outer_env_scopes:
                kv_m = _YAML_KEY_VAL_RE.match(stripped)
                if kv_m:
                    if _BLOCK_SCALAR_RE.match(kv_m.group(2).strip()):
                        in_block_scalar_indent = indent
                        block_scalar_is_run = False
                    else:
                        outer_env_scopes[-1][1][kv_m.group(1)] = _unquote(
                            _strip_yaml_comment(kv_m.group(2))
                        ).strip()
                continue

            item_m = _YAML_LIST_ITEM_RE.match(line)
            if item_m:
                step_indent = indent
                body = item_m.group(2).strip()
                kv_m = _YAML_KEY_VAL_RE.match(body)
                if kv_m:
                    _handle_step_key(kv_m.group(1), kv_m.group(2), line_no, indent)
                continue

            kv_m = _YAML_KEY_VAL_RE.match(stripped)
            if not kv_m:
                continue
            key, raw_val = kv_m.group(1), kv_m.group(2)

            if step_indent is not None and indent > step_indent:
                _handle_step_key(key, raw_val, line_no, indent)
                continue

            if key == "rust":
                rest = _strip_yaml_comment(raw_val).strip()
                if not rest:
                    in_rust_list_indent = indent
                elif rest.startswith("[") and rest.endswith("]"):
                    inner = rest[1:-1]
                    parts = [p.strip() for p in inner.split(",") if p.strip()]
                    if parts:
                        has_rust_matrix = True
                    for part in parts:
                        _record_rust_value(
                            line_no,
                            part,
                            "rust matrix",
                            allow_matrix=False,
                            env_map=None,
                        )
                else:
                    has_rust_matrix = True
                    _record_rust_value(
                        line_no,
                        rest,
                        "rust matrix",
                        allow_matrix=False,
                        env_map=None,
                    )
            elif key == "env":
                cleaned_val = _strip_yaml_comment(raw_val).strip()
                if not cleaned_val:
                    in_outer_env_indent = indent
                    outer_env_scopes.append((indent, {}))
            elif _BLOCK_SCALAR_RE.match(raw_val.strip()):
                in_block_scalar_indent = indent
                block_scalar_is_run = False

        _flush_step()

        for line_no, matrix_key, raw_expr in pending_matrix_refs:
            if matrix_key == "rust" and has_rust_matrix:
                setup_count += 1
            else:
                errors.append(
                    f"{rel}:{line_no}: Rust toolchain reference {raw_expr!r} requires a 'rust:' matrix in {rel}"
                )

        for line_no, var_name, raw_expr, env_snap in pending_env_refs:
            if var_name in env_snap:
                resolved = env_snap[var_name]
                parsed = parse_rust_version(resolved)
                if parsed is not None:
                    concrete_versions.append((rel, line_no, resolved, parsed))
                    setup_count += 1
                elif resolved in _RUST_CHANNELS:
                    setup_count += 1
                else:
                    matrix_m = _MATRIX_EXPR_RE.match(resolved)
                    if matrix_m and matrix_m.group(1) == "rust" and has_rust_matrix:
                        setup_count += 1
                    else:
                        errors.append(
                            f"{rel}:{line_no}: unresolvable Rust env variable {raw_expr!r} (={resolved!r})"
                        )
            elif var_name == "RUST" and has_rust_matrix:
                setup_count += 1
            else:
                errors.append(
                    f"{rel}:{line_no}: unresolvable Rust env variable {raw_expr!r} (no matching env or 'rust:' matrix)"
                )

    return concrete_versions, setup_count, errors


def collect_workflow_rust_versions(
    root_dir: Path,
) -> list[tuple[str, int, str, tuple[int, int, int]]]:
    """Return (rel_path, line_no, raw_version, parsed_tuple) from mirror workflows.

    Fails closed if any workflow uses an unparseable or unsupported Rust setup.
    """
    wf_versions, _setup_count, errors = _scan_workflow_rust_setups(root_dir)
    if errors:
        raise RuntimeError(
            "mirror workflow Rust version check failed:\n" + "\n".join(errors)
        )
    return wf_versions


def verify_workflow_rust_versions(dest_dir: Path) -> None:
    """Verify every concrete Rust version in mirror workflows >= max Cargo.toml rust-version.

    Prevents mirror CI jobs from installing a Rust floor older than the MSRV
    declared in exported Cargo.toml manifests (as happened when Cargo.toml moved
    to 1.98 while ci.yml/kits.yml still installed 1.75.0). Fails closed on any
    unparseable or unsupported Rust toolchain setup.
    """
    cargo_versions = collect_cargo_rust_versions(dest_dir)
    if not cargo_versions:
        raise RuntimeError(
            f"No rust-version entries found in Cargo.toml under {dest_dir}"
        )

    wf_versions, setup_count, errors = _scan_workflow_rust_setups(dest_dir)

    req_cargo, req_str, req_tuple = max(cargo_versions, key=lambda item: item[2])
    for rel_wf, line_no, ver_str, ver_tuple in wf_versions:
        if ver_tuple < req_tuple:
            errors.append(
                f"{rel_wf}:{line_no}: Rust version {ver_str} is lower than required rust-version {req_str} (from {req_cargo})"
            )

    if errors:
        raise RuntimeError(
            "mirror workflow Rust version check failed:\n" + "\n".join(errors)
        )

    if setup_count == 0:
        raise RuntimeError(
            f"No Rust toolchain setup found in .github/workflows under {dest_dir}"
        )

    print(
        f"verified workflow Rust versions ({len(wf_versions)} concrete version(s) >= {req_str}, {setup_count} setup(s))"
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
    verify_workflow_rust_versions(dest_dir)


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
    # and the exported mirror's kits.yml Rust sample check, plus the vendored
    # pycompat crate's own unit tests (without the excluded golden fixture).
    _run(
        [
            cargo_bin,
            "test",
            "--offline",
            "--manifest-path",
            "vendor/vitruvian-pycompat/Cargo.toml",
        ],
        cwd=export_dir,
        env=env,
    )
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
    parser.add_argument(
        "--check-rust-versions",
        type=Path,
        default=None,
        help="Run only the workflow Rust version floor check against an already-assembled export directory.",
    )
    args = parser.parse_args(argv)

    repo_root = Path(
        os.environ.get("BUILD_WORKSPACE_DIRECTORY") or os.getcwd()
    ).resolve()

    try:
        if args.check_rust_versions is not None:
            verify_workflow_rust_versions(args.check_rust_versions.resolve())
            return 0

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
