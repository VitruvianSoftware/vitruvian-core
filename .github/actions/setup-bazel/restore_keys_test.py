# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

"""Verify restore-key order in setup-bazel and lookup-only key in bazel-repo-cache-warm."""

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


def _find_restore_steps(path):
    return [
        s
        for s in _load_steps(path)
        if isinstance(s, dict)
        and (
            str(s.get("uses", "")).startswith("actions/cache/restore@")
            or "restore-keys" in (s.get("with") or {})
        )
    ]


def test_setup_bazel_action_restore_keys_exact_order_and_same_platform_legacy_last():
    path = _resolve_path(
        "SETUP_BAZEL_ACTION_PATH", ".github/actions/setup-bazel/action.yml"
    )
    restore_steps = _find_restore_steps(path)
    assert len(restore_steps) == 1, (
        f"{path}: expected 1 restore step, got {len(restore_steps)}"
    )

    with_cfg = restore_steps[0].get("with") or {}
    exact_key = str(with_cfg.get("key") or "").strip()
    raw_restore_keys = with_cfg.get("restore-keys")
    assert raw_restore_keys is not None, f"{path}: expected non-empty restore-keys"

    restore_keys = [
        line.strip() for line in str(raw_restore_keys).splitlines() if line.strip()
    ]
    assert len(restore_keys) == 2, (
        f"{path}: expected exactly 2 restore-keys [full_prefix, legacy_prefix], got {restore_keys!r}"
    )

    full_prefix, legacy_prefix = restore_keys
    assert exact_key.split("-repository-full-")[0] == legacy_prefix.removesuffix(
        "-repository-"
    ), (
        f"{path}: legacy prefix {legacy_prefix!r} must use the exact same platform "
        f"expression as exact key {exact_key!r}"
    )
    assert full_prefix.endswith("-repository-full-"), (
        f"{path}: first restore-key must be the '-repository-full-' prefix, got {full_prefix!r}"
    )
    assert (
        legacy_prefix.endswith("-repository-")
        and "-repository-full-" not in legacy_prefix
    ), (
        f"{path}: last restore-key must be the same-platform legacy '-repository-' prefix, "
        f"got {legacy_prefix!r}"
    )

    lookup_order = [exact_key, full_prefix, legacy_prefix]
    for pos, arch in (("linux", "x64"), ("darwin", "arm64")):
        rendered = [_render_platform_exprs(k, pos, arch) for k in lookup_order]
        expected = [
            f"setup-bazel-1-{pos}-{arch}-repository-full-deadbeef",
            f"setup-bazel-1-{pos}-{arch}-repository-full-",
            f"setup-bazel-1-{pos}-{arch}-repository-",
        ]
        assert rendered == expected, (
            f"{path}: lookup order for {pos}-{arch} must be {expected!r}, got {rendered!r}"
        )
        other_pos, other_arch = (
            ("darwin", "arm64") if pos == "linux" else ("linux", "x64")
        )
        other_legacy = f"setup-bazel-1-{other_pos}-{other_arch}-repository-39c2ecfd"
        same_legacy = f"setup-bazel-1-{pos}-{arch}-repository-39c2ecfd"
        assert same_legacy.startswith(rendered[-1])
        assert not other_legacy.startswith(rendered[-1])


def test_warm_composite_action_lookup_has_no_restore_keys():
    path = _resolve_path(
        "WARM_COMPOSITE_ACTION_PATH",
        ".github/actions/bazel-repo-cache-warm/action.yml",
    )
    restore_steps = _find_restore_steps(path)
    assert restore_steps, f"{path}: expected at least one actions/cache/restore step"
    for step in restore_steps:
        with_cfg = step.get("with") or {}
        key = str(with_cfg.get("key") or "")
        assert "-repository-full-" in key, (
            f"{path}: lookup key {key!r} must contain '-repository-full-'"
        )
        assert not with_cfg.get("restore-keys"), (
            f"{path}: lookup-only step must not define restore-keys"
        )
