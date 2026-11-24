# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

"""Verify that setup-bazel and bazel-repo-cache-warm never restore legacy partial keys."""

import os
from pathlib import Path

import yaml


def _resolve_path(env_var, fallback_rel):
    env_path = os.environ.get(env_var)
    if env_path and os.path.isfile(env_path):
        return Path(env_path)
    return Path(__file__).resolve().parents[3] / fallback_rel


def _load_steps(path):
    doc = yaml.safe_load(Path(path).read_text(encoding="utf-8"))
    assert isinstance(doc, dict), f"{path} did not parse to a YAML mapping"
    runs = doc.get("runs", {})
    assert isinstance(runs, dict), f"{path} missing 'runs' mapping"
    steps = runs.get("steps", [])
    assert isinstance(steps, list), f"{path} missing 'runs.steps' list"
    return steps


def _render_platform_exprs(template, platform_os, platform_arch):
    rendered = template
    rendered = rendered.replace(
        "${{ runner.os == 'macOS' && 'darwin' || 'linux' }}", platform_os
    )
    rendered = rendered.replace(
        "${{ runner.arch == 'ARM64' && 'arm64' || 'x64' }}", platform_arch
    )
    rendered = rendered.replace("${{ inputs.platform-os }}", platform_os)
    rendered = rendered.replace("${{ inputs.platform-arch }}", platform_arch)
    rendered = rendered.replace(
        "${{ hashFiles('MODULE.bazel', 'MODULE.bazel.lock', '.bazelversion') }}",
        "deadbeef",
    )
    return rendered


def _assert_safe_repo_restore_step(step, source_name):
    with_cfg = step.get("with") or {}
    assert isinstance(with_cfg, dict), f"{source_name}: 'with' must be a mapping"

    key = with_cfg.get("key")
    if key is not None:
        assert "-repository-full-" in str(key), (
            f"{source_name}: restore key {key!r} must contain '-repository-full-'"
        )

    raw_restore_keys = with_cfg.get("restore-keys")
    if raw_restore_keys is None:
        return []

    lines = [
        line.strip() for line in str(raw_restore_keys).splitlines() if line.strip()
    ]
    legacy_linux = "setup-bazel-1-linux-x64-repository-39c2ecfd"
    legacy_darwin = "setup-bazel-1-darwin-arm64-repository-39c2ecfd"
    for rk in lines:
        assert "-repository-full-" in rk, (
            f"{source_name}: restore-keys entry {rk!r} does not contain '-repository-full-'"
        )
        assert not rk.endswith("-repository-"), (
            f"{source_name}: restore-keys entry {rk!r} matches legacy '-repository-' prefix"
        )
        for pos, arch in (("linux", "x64"), ("darwin", "arm64")):
            rendered = _render_platform_exprs(rk, pos, arch)
            assert not legacy_linux.startswith(rendered), (
                f"{source_name}: restore-keys entry {rk!r} (rendered {rendered!r}) "
                f"would match legacy key {legacy_linux!r}"
            )
            assert not legacy_darwin.startswith(rendered), (
                f"{source_name}: restore-keys entry {rk!r} (rendered {rendered!r}) "
                f"would match legacy key {legacy_darwin!r}"
            )
    return lines


def test_setup_bazel_action_restore_keys_require_full_segment():
    path = _resolve_path(
        "SETUP_BAZEL_ACTION_PATH", ".github/actions/setup-bazel/action.yml"
    )
    steps = _load_steps(path)
    restore_steps = [
        s
        for s in steps
        if isinstance(s, dict)
        and (
            str(s.get("uses", "")).startswith("actions/cache/restore@")
            or "restore-keys" in (s.get("with") or {})
        )
    ]
    assert restore_steps, f"{path}: expected at least one actions/cache/restore step"

    all_restore_keys = []
    for step in restore_steps:
        all_restore_keys.extend(_assert_safe_repo_restore_step(step, str(path)))

    assert all_restore_keys, (
        f"{path}: expected non-empty restore-keys on repository cache restore step"
    )


def test_warm_composite_action_restore_keys_require_full_segment():
    path = _resolve_path(
        "WARM_COMPOSITE_ACTION_PATH",
        ".github/actions/bazel-repo-cache-warm/action.yml",
    )
    steps = _load_steps(path)
    restore_steps = [
        s
        for s in steps
        if isinstance(s, dict)
        and (
            str(s.get("uses", "")).startswith("actions/cache/restore@")
            or "restore-keys" in (s.get("with") or {})
        )
    ]
    assert restore_steps, f"{path}: expected at least one actions/cache/restore step"

    for step in restore_steps:
        _assert_safe_repo_restore_step(step, str(path))
