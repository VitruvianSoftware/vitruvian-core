# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

"""Verify bazel-repo-cache.yaml main gates, permissions isolation, needs, and concurrency."""

import os
import re
from pathlib import Path


def _resolve_workflow_path():
    env_path = os.environ.get("BAZEL_REPO_CACHE_WORKFLOW_PATH")
    if env_path and os.path.isfile(env_path):
        return Path(env_path)
    return (
        Path(__file__).resolve().parents[3] / ".github/workflows/bazel-repo-cache.yaml"
    )


def _split_workflow(text):
    """Return `(header_lines, jobs)` where `jobs` maps job id to its lines."""
    header = []
    jobs = {}
    in_jobs = False
    current_job = None

    for raw in text.splitlines():
        stripped = raw.strip()
        if not stripped or stripped.startswith("#"):
            continue
        indent = len(raw) - len(raw.lstrip(" "))
        if indent == 0:
            current_job = None
            if stripped == "jobs:":
                in_jobs = True
                continue
            in_jobs = False
            header.append(raw)
            continue
        if not in_jobs:
            header.append(raw)
            continue
        m = re.match(r"^  ([A-Za-z0-9_-]+):\s*$", raw)
        if m:
            current_job = m.group(1)
            jobs[current_job] = []
        elif current_job is not None:
            jobs[current_job].append(raw)

    return header, jobs


def _job_scalar(job_lines, key):
    prefix = f"    {key}:"
    for line in job_lines:
        if line.startswith(prefix):
            return line[len(prefix) :].split(" #", 1)[0].strip()
    return None


def _job_subblock(job_lines, key):
    header = f"    {key}:"
    block = []
    in_block = False
    for line in job_lines:
        indent = len(line) - len(line.lstrip(" "))
        if indent == 4:
            if line.strip() == header.strip():
                in_block = True
                continue
            if in_block:
                break
        elif in_block and indent >= 6:
            block.append(line.strip())
    return block


def _has_top_level_or(expr):
    depth = 0
    in_single = False
    i = 0
    while i < len(expr):
        ch = expr[i]
        if ch == "'":
            in_single = not in_single
        elif not in_single:
            if ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
            elif ch == "|" and depth == 0 and i + 1 < len(expr) and expr[i + 1] == "|":
                return True
        i += 1
    return False


def test_save_jobs_are_main_only_with_event_condition():
    _header, jobs = _split_workflow(
        _resolve_workflow_path().read_text(encoding="utf-8")
    )
    for job_id in ("warm-linux-save", "warm-macos-save"):
        assert job_id in jobs, f"missing required save job {job_id}"
        if_expr = _job_scalar(jobs[job_id], "if")
        assert if_expr, f"{job_id} must declare an if: gate"
        bare = if_expr.removeprefix("${{").removesuffix("}}").strip()
        assert "github.ref == 'refs/heads/main'" in bare, (
            f"{job_id} if: must require refs/heads/main, got {if_expr!r}"
        )
        assert not _has_top_level_or(bare), (
            f"{job_id} if: must not have a top-level || escape hatch: {if_expr!r}"
        )
        for ev in ("push", "schedule", "workflow_dispatch"):
            assert f"github.event_name == '{ev}'" in bare, (
                f"{job_id} if: missing event condition for {ev}: {if_expr!r}"
            )


def test_actions_write_restricted_to_save_jobs():
    header, jobs = _split_workflow(_resolve_workflow_path().read_text(encoding="utf-8"))
    assert not any(re.match(r"^\s*actions:\s*write\b", line) for line in header), (
        "top-level workflow permissions must not grant actions: write"
    )

    save_jobs = {"warm-linux-save", "warm-macos-save"}
    verify_jobs = [jid for jid in jobs if re.fullmatch(r"warm-.*-verify", jid)]
    assert set(verify_jobs) >= {"warm-linux-verify", "warm-macos-verify"}, (
        f"expected warm-linux-verify and warm-macos-verify, got {sorted(jobs)}"
    )

    for jid, jlines in jobs.items():
        perms = _job_subblock(jlines, "permissions")
        has_actions_write = any(re.fullmatch(r"actions:\s*write", p) for p in perms)
        if jid in save_jobs:
            assert has_actions_write, f"{jid} must grant actions: write in permissions"
            assert any(re.fullmatch(r"contents:\s*read", p) for p in perms), (
                f"{jid} must declare contents: read in permissions"
            )
        else:
            assert not has_actions_write, (
                f"{jid} must not grant actions: write in permissions: {perms!r}"
            )


def test_save_jobs_serialized_via_needs_and_not_cancelled():
    _header, jobs = _split_workflow(
        _resolve_workflow_path().read_text(encoding="utf-8")
    )
    linux_needs = _job_scalar(jobs["warm-linux-save"], "needs")
    linux_needs_block = _job_subblock(jobs["warm-linux-save"], "needs")
    assert linux_needs == "warm-macos-save" or any(
        line.lstrip("- ").strip() == "warm-macos-save" for line in linux_needs_block
    ), (
        f"warm-linux-save must declare needs: warm-macos-save, got {linux_needs!r} / {linux_needs_block!r}"
    )

    linux_if = _job_scalar(jobs["warm-linux-save"], "if") or ""
    assert "!cancelled()" in linux_if, (
        f"warm-linux-save if: must include !cancelled(): {linux_if!r}"
    )

    macos_needs = _job_scalar(jobs["warm-macos-save"], "needs")
    assert not macos_needs and not _job_subblock(jobs["warm-macos-save"], "needs"), (
        "warm-macos-save must not have needs"
    )


def test_save_jobs_have_distinct_per_platform_concurrency_groups():
    _header, jobs = _split_workflow(
        _resolve_workflow_path().read_text(encoding="utf-8")
    )
    expected = {
        "warm-linux-save": "bazel-repo-cache-save-linux",
        "warm-macos-save": "bazel-repo-cache-save-macos",
    }
    for jid, expected_group in expected.items():
        conc = _job_subblock(jobs[jid], "concurrency")
        assert f"group: {expected_group}" in conc, (
            f"{jid} concurrency must have group: {expected_group}, got {conc!r}"
        )
        assert "cancel-in-progress: false" in conc, (
            f"{jid} concurrency must set cancel-in-progress: false, got {conc!r}"
        )
