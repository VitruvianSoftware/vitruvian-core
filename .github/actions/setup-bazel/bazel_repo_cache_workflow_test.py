# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

"""Verify bazel-repo-cache.yaml save job ordering and per-platform concurrency."""

import os
from pathlib import Path

import yaml


def _resolve_workflow_path():
    env_path = os.environ.get("BAZEL_REPO_CACHE_WORKFLOW_PATH")
    if env_path and os.path.isfile(env_path):
        return Path(env_path)
    return (
        Path(__file__).resolve().parents[3] / ".github/workflows/bazel-repo-cache.yaml"
    )


def test_save_jobs_serialized_without_shared_cancellation():
    doc = yaml.safe_load(_resolve_workflow_path().read_text(encoding="utf-8"))
    jobs = doc["jobs"]
    linux_save = jobs["warm-linux-save"]
    macos_save = jobs["warm-macos-save"]

    needs = linux_save.get("needs")
    assert needs == "warm-macos-save" or (
        isinstance(needs, list) and "warm-macos-save" in needs
    ), f"warm-linux-save must depend on warm-macos-save, got {needs!r}"
    assert not macos_save.get("needs"), (
        f"warm-macos-save must not have needs: {macos_save.get('needs')!r}"
    )

    linux_if = str(linux_save.get("if", ""))
    macos_if = str(macos_save.get("if", ""))
    assert "!cancelled()" in linux_if
    assert "github.ref == 'refs/heads/main'" in linux_if
    assert "github.ref == 'refs/heads/main'" in macos_if
    for ev in ("push", "schedule", "workflow_dispatch"):
        assert ev in linux_if
        assert ev in macos_if

    linux_conc = linux_save.get("concurrency") or {}
    macos_conc = macos_save.get("concurrency") or {}
    assert linux_conc == {
        "group": "bazel-repo-cache-save-linux",
        "cancel-in-progress": False,
    }, f"unexpected warm-linux-save concurrency: {linux_conc!r}"
    assert macos_conc == {
        "group": "bazel-repo-cache-save-macos",
        "cancel-in-progress": False,
    }, f"unexpected warm-macos-save concurrency: {macos_conc!r}"
    assert linux_conc["group"] != macos_conc["group"]
    assert "bazel-repo-cache-save" not in (linux_conc["group"], macos_conc["group"])
