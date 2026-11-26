# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

"""Verify bazel-repo-cache.yaml main gates, permissions isolation, needs, concurrency, and bazel-repo-cache-warm composite guarantees."""

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


def _resolve_warm_action_path():
    env_path = os.environ.get("WARM_COMPOSITE_ACTION_PATH")
    if env_path and os.path.isfile(env_path):
        return Path(env_path)
    return (
        Path(__file__).resolve().parents[3]
        / ".github/actions/bazel-repo-cache-warm/action.yml"
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


# Pre-save deletion currently runs inside the capacity-guard step
# (`cache_capacity_guard.py`); any future dedicated pre-save-delete step must
# also be explicitly listed here.
ALLOWED_WARM_TOKEN_STEPS = frozenset(
    {
        "Check Actions cache capacity before saving",
        "Confirm saved cache and prune superseded same-platform entries",
    }
)


def _record_step_field(step, field_line, line_no):
    m = re.match(r"^(name|id|uses|if):\s*(.+?)\s*$", field_line)
    if not m:
        return
    key, raw_val = m.group(1), m.group(2)
    val = raw_val.split(" #", 1)[0].strip()
    if len(val) >= 2 and val[0] == val[-1] and val[0] in ("'", '"'):
        val = val[1:-1]
    if key == "uses":
        step["uses"] = val
        step["uses_line"] = line_no
    elif not step[key]:
        step[key] = val


def _split_composite_steps(text):
    """Split a composite action's `runs.steps` into step dicts with line bounds."""
    steps = []
    in_runs = False
    in_steps = False
    step_indent = None
    current = None

    for line_no, raw in enumerate(text.splitlines(), start=1):
        stripped = raw.strip()
        if not stripped or stripped.startswith("#"):
            if current is not None:
                current["lines"].append(raw)
            continue

        indent = len(raw) - len(raw.lstrip(" "))
        if indent == 0:
            in_runs = stripped == "runs:"
            in_steps = False
            step_indent = None
            current = None
            continue

        if not in_runs:
            continue

        if not in_steps:
            if stripped == "steps:":
                in_steps = True
            continue

        if step_indent is None:
            if stripped.startswith("- "):
                step_indent = indent
            elif indent <= 2:
                in_steps = False
                continue

        if indent < step_indent:
            in_steps = False
            current = None
            continue

        if indent == step_indent and stripped.startswith("- "):
            current = {
                "start_line": line_no,
                "name": "",
                "id": "",
                "uses": "",
                "uses_line": None,
                "if": "",
                "lines": [raw],
                "text": "",
            }
            steps.append(current)
            _record_step_field(current, stripped[2:].lstrip(), line_no)
            continue

        if current is not None:
            current["lines"].append(raw)
            if indent == step_indent + 2:
                _record_step_field(current, stripped, line_no)

    for step in steps:
        step["text"] = "\n".join(step["lines"])
    return steps


def _step_with_scalar(step, key):
    """Return the scalar value of `key:` inside a step's `with:` mapping, or None."""
    lines = step["lines"]
    if not lines:
        return None
    step_indent = len(lines[0]) - len(lines[0].lstrip(" "))
    with_indent = None
    prefix = f"{key}:"
    for raw in lines[1:]:
        stripped = raw.strip()
        if not stripped or stripped.startswith("#"):
            continue
        indent = len(raw) - len(raw.lstrip(" "))
        if with_indent is None:
            if indent == step_indent + 2 and stripped == "with:":
                with_indent = indent
            continue
        if indent <= with_indent:
            break
        if indent == with_indent + 2 and stripped.startswith(prefix):
            val = stripped[len(prefix) :].split(" #", 1)[0].strip()
            if len(val) >= 2 and val[0] == val[-1] and val[0] in ("'", '"'):
                val = val[1:-1]
            return val
    return None


def test_warm_composite_capacity_guard_precedes_every_save_step():
    steps = _split_composite_steps(
        _resolve_warm_action_path().read_text(encoding="utf-8")
    )
    guard_steps = [
        s
        for s in steps
        if "capacity" in s["name"].lower()
        or s["id"] == "capacity-guard"
        or "cache_capacity_guard.py" in s["text"]
    ]
    assert len(guard_steps) == 1, (
        f"expected exactly 1 capacity guard step, got {[(s['start_line'], s['name']) for s in guard_steps]}"
    )
    guard = guard_steps[0]

    save_steps = [s for s in steps if s["uses"].startswith("actions/cache/save@")]
    assert save_steps, "expected at least one actions/cache/save@ step"

    for save in save_steps:
        assert guard["start_line"] < save["start_line"], (
            f"capacity guard step '{guard['name']}' (line {guard['start_line']}) "
            f"must precede save step '{save['name']}' (line {save['start_line']})"
        )
        assert guard["start_line"] < save["uses_line"], (
            f"capacity guard step '{guard['name']}' (line {guard['start_line']}) "
            f"must precede save uses: line {save['uses_line']}"
        )


def test_warm_composite_prune_runs_only_after_save_steps():
    steps = _split_composite_steps(
        _resolve_warm_action_path().read_text(encoding="utf-8")
    )
    prune_steps = [
        s
        for s in steps
        if "prune" in s["name"].lower() or "cache_prune.py" in s["text"]
    ]
    assert prune_steps, "expected at least one prune step"

    save_steps = [s for s in steps if s["uses"].startswith("actions/cache/save@")]
    assert save_steps, "expected at least one actions/cache/save@ step"

    for prune in prune_steps:
        assert any(prune["start_line"] > save["start_line"] for save in save_steps), (
            f"prune step '{prune['name']}' (line {prune['start_line']}) "
            "must run after at least one actions/cache/save@ step"
        )
        for save in save_steps:
            assert prune["start_line"] > save["start_line"], (
                f"prune step '{prune['name']}' (line {prune['start_line']}) "
                f"must not precede save step '{save['name']}' (line {save['start_line']})"
            )


def test_warm_composite_github_token_restricted_to_guard_prune_and_pre_save_delete_steps():
    steps = _split_composite_steps(
        _resolve_warm_action_path().read_text(encoding="utf-8")
    )
    assert steps, "expected composite steps in bazel-repo-cache-warm/action.yml"
    step_names = {s["name"] for s in steps}
    assert ALLOWED_WARM_TOKEN_STEPS <= step_names, (
        f"missing allowed token steps {sorted(ALLOWED_WARM_TOKEN_STEPS - step_names)}"
    )

    for step in steps:
        if "GH_TOKEN" in step["text"] or "GITHUB_TOKEN" in step["text"]:
            assert step["name"] in ALLOWED_WARM_TOKEN_STEPS, (
                f"GH_TOKEN/GITHUB_TOKEN is allowed only on {sorted(ALLOWED_WARM_TOKEN_STEPS)}, "
                f"found in step '{step['name']}' (line {step['start_line']})"
            )


def test_warm_composite_save_steps_gated_on_save_mode_and_cache_miss():
    steps = _split_composite_steps(
        _resolve_warm_action_path().read_text(encoding="utf-8")
    )
    save_steps = [s for s in steps if s["uses"].startswith("actions/cache/save@")]
    assert save_steps, "expected at least one actions/cache/save@ step"

    for save in save_steps:
        if_expr = save["if"]
        assert if_expr, (
            f"save step '{save['name']}' (line {save['start_line']}) must declare an if: gate"
        )
        bare = if_expr.removeprefix("${{").removesuffix("}}").strip()
        norm = " ".join(bare.split()).replace('"', "'")
        assert "inputs.mode == 'save'" in norm, (
            f"save step '{save['name']}' (line {save['start_line']}) if: must require inputs.mode == 'save', got {if_expr!r}"
        )
        assert not _has_top_level_or(norm), (
            f"save step '{save['name']}' (line {save['start_line']}) if: must not have a top-level || escape hatch: {if_expr!r}"
        )
        if save["id"].startswith("gomod-"):
            expected_lookup = "steps.gomod-cache-lookup.outputs.cache-hit != 'true'"
        elif save["id"].startswith("debs-"):
            expected_lookup = "steps.debs-cache-lookup.outputs.cache-hit != 'true'"
        else:
            expected_lookup = "steps.cache-lookup.outputs.cache-hit != 'true'"
        assert expected_lookup in norm, (
            f"save step '{save['name']}' (line {save['start_line']}) if: must guard on {expected_lookup}, got {if_expr!r}"
        )


def test_warm_composite_bazelisk_setup_cache_save_gated_on_save_mode():
    steps = _split_composite_steps(
        _resolve_warm_action_path().read_text(encoding="utf-8")
    )
    setup_steps = [
        s for s in steps if s["uses"].startswith("bazel-contrib/setup-bazel@")
    ]
    assert len(setup_steps) == 1, (
        f"expected exactly 1 bazel-contrib/setup-bazel@ step, got {[(s['start_line'], s['name']) for s in setup_steps]}"
    )
    setup = setup_steps[0]
    cache_save = _step_with_scalar(setup, "cache-save")
    assert cache_save == "${{ inputs.mode == 'save' }}", (
        f"setup step '{setup['name']}' (line {setup['start_line']}) cache-save: must be "
        f"'${{{{ inputs.mode == 'save' }}}}', got {cache_save!r}"
    )
