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

"""Verify Go cache warm jobs in go-cache.yaml match every ./.github/actions/setup-go consumer."""

from __future__ import annotations

from dataclasses import dataclass
import os
from pathlib import Path
import re

import cache_key

SETUP_GO_USES = "./.github/actions/setup-go"
GO_CACHE_WORKFLOW_NAME = "go-cache.yaml"
DEFAULT_CACHE_DEPENDENCY_PATH = cache_key.DEFAULT_DEPENDENCY_PATH
_GLOB_WILDCARDS = ("*", "?", "[")


@dataclass(frozen=True)
class SetupGoStep:
    """Parsed `./.github/actions/setup-go` invocation within a workflow job."""

    workflow: str
    job_id: str
    with_inputs: tuple[str, ...]
    go_version_file: str
    cache_dependency_paths: tuple[str, ...]
    mode: str

    @property
    def key_signature(self) -> tuple[str, tuple[str, ...]]:
        """Return `(go_version_file, cache_dependency_paths)` defining the cache key."""
        return (self.go_version_file, self.cache_dependency_paths)

    @property
    def label(self) -> str:
        """Return a human-readable `workflow::job_id` identifier."""
        return f"{self.workflow}::{self.job_id}"


def _resolve_action_path() -> Path:
    env_path = os.environ.get("SETUP_GO_ACTION_PATH")
    if env_path and os.path.isfile(env_path):
        return Path(env_path)
    return Path(__file__).resolve().parent / "action.yml"


def _resolve_repo_root_and_workflows() -> tuple[Path, list[Path]]:
    raw_workflows = os.environ.get("WORKFLOW_FILES", "").strip()
    if raw_workflows:
        paths = [Path(tok) for tok in raw_workflows.split()]
        missing = [str(p) for p in paths if not p.is_file()]
        assert not missing, f"WORKFLOW_FILES contains missing paths: {missing}"
        return Path.cwd(), sorted(paths, key=lambda p: p.name)
    repo_root = Path(__file__).resolve().parents[3]
    workflows_dir = repo_root / ".github" / "workflows"
    return repo_root, sorted(workflows_dir.glob("*.yaml"), key=lambda p: p.name)


def _strip_inline_comment(value: str) -> str:
    """Strip an unquoted trailing `# comment` from a YAML scalar expression."""
    in_single = False
    in_double = False
    i = 0
    while i < len(value):
        ch = value[i]
        if ch == "'" and not in_double:
            if in_single and i + 1 < len(value) and value[i + 1] == "'":
                i += 2
                continue
            in_single = not in_single
        elif ch == '"' and not in_single:
            if ch == '"' and i > 0 and value[i - 1] == "\\":
                i += 1
                continue
            in_double = not in_double
        elif ch == "#" and not in_single and not in_double:
            if i == 0 or value[i - 1].isspace():
                return value[:i].strip()
        i += 1
    return value.strip()


def _unquote(value: str) -> str:
    if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
        return value[1:-1]
    return value


def _parse_action_inputs(text: str) -> set[str]:
    """Parse top-level `inputs:` keys from `.github/actions/setup-go/action.yml`."""
    inputs: set[str] = set()
    in_inputs = False
    input_indent: int | None = None

    for raw in text.splitlines():
        stripped = raw.strip()
        if not stripped or stripped.startswith("#"):
            continue
        indent = len(raw) - len(raw.lstrip(" "))
        if indent == 0:
            in_inputs = stripped == "inputs:"
            input_indent = None
            continue
        if not in_inputs:
            continue
        if input_indent is None:
            input_indent = indent
        if indent == input_indent:
            m = re.match(r"^([A-Za-z0-9_-]+):\s*(?:#.*)?$", stripped)
            if m:
                inputs.add(m.group(1))
    return inputs


def _parse_with_block(with_lines: list[tuple[int, str]]) -> dict[str, list[str]]:
    """Parse a step's `with:` mapping into `{input_name: [values...]}`."""
    parsed: dict[str, list[str]] = {}
    key_indent: int | None = None
    i = 0
    while i < len(with_lines):
        indent, raw = with_lines[i]
        stripped = raw.strip()
        if not stripped or stripped.startswith("#"):
            i += 1
            continue
        if key_indent is None:
            key_indent = indent
        if indent != key_indent:
            i += 1
            continue

        m = re.match(r"^([A-Za-z0-9_-]+):(?:\s*(.*))?$", stripped)
        if not m:
            i += 1
            continue
        key = m.group(1)
        raw_val = m.group(2) or ""
        cleaned = _strip_inline_comment(raw_val)

        if re.fullmatch(r"[|>][+-]?\d*", cleaned):
            block_vals: list[str] = []
            i += 1
            while i < len(with_lines):
                sub_indent, sub_raw = with_lines[i]
                sub_stripped = sub_raw.strip()
                if not sub_stripped:
                    i += 1
                    continue
                if sub_indent <= key_indent:
                    break
                block_vals.append(sub_stripped)
                i += 1
            parsed[key] = block_vals
            continue

        scalar = _unquote(cleaned)
        parsed[key] = [scalar] if scalar else []
        i += 1

    return parsed


def _parse_single_step(
    workflow_name: str,
    job_id: str,
    step_lines: list[tuple[int, str]],
    step_indent: int,
) -> SetupGoStep | None:
    """Parse one workflow step dict; return `SetupGoStep` iff it uses `./.github/actions/setup-go`."""
    normalized: list[tuple[int, str]] = []
    first_indent, first_raw = step_lines[0]
    assert first_indent == step_indent
    after_dash = first_raw[step_indent + 1 :]
    first_key_indent = step_indent + 1 + (len(after_dash) - len(after_dash.lstrip(" ")))
    if after_dash.strip():
        normalized.append(
            (first_key_indent, (" " * first_key_indent) + after_dash.lstrip(" "))
        )

    for line_indent, line_raw in step_lines[1:]:
        normalized.append((line_indent, line_raw))

    uses_val = ""
    with_lines: list[tuple[int, str]] = []
    i = 0
    while i < len(normalized):
        indent, raw = normalized[i]
        stripped = raw.strip()
        if not stripped or stripped.startswith("#"):
            i += 1
            continue
        if indent != first_key_indent:
            i += 1
            continue
        m = re.match(r"^([A-Za-z0-9_-]+):(?:\s*(.*))?$", stripped)
        if not m:
            i += 1
            continue
        key = m.group(1)
        raw_val = m.group(2) or ""
        if key == "uses":
            uses_val = _unquote(_strip_inline_comment(raw_val))
        elif key == "with":
            i += 1
            while i < len(normalized):
                sub_indent, sub_raw = normalized[i]
                sub_stripped = sub_raw.strip()
                if (
                    sub_stripped
                    and not sub_stripped.startswith("#")
                    and sub_indent <= first_key_indent
                ):
                    break
                with_lines.append((sub_indent, sub_raw))
                i += 1
            continue
        i += 1

    if uses_val != SETUP_GO_USES:
        return None

    with_map = _parse_with_block(with_lines)
    go_version_files = with_map.get("go-version-file", [])
    go_version_file = go_version_files[0] if go_version_files else ""
    dep_paths = tuple(with_map.get("cache-dependency-path", []))
    if not dep_paths:
        dep_paths = (DEFAULT_CACHE_DEPENDENCY_PATH,)
    modes = with_map.get("mode", [])
    mode = modes[0] if modes else "auto"

    return SetupGoStep(
        workflow=workflow_name,
        job_id=job_id,
        with_inputs=tuple(with_map.keys()),
        go_version_file=go_version_file,
        cache_dependency_paths=dep_paths,
        mode=mode,
    )


def _parse_setup_go_steps(workflow_name: str, text: str) -> list[SetupGoStep]:
    """Extract all `./.github/actions/setup-go` steps from a GitHub Actions workflow."""
    results: list[SetupGoStep] = []
    in_jobs = False
    job_indent: int | None = None
    job_child_indent: int | None = None
    current_job: str | None = None
    in_steps = False
    steps_indent: int | None = None
    step_indent: int | None = None
    current_step: list[tuple[int, str]] | None = None

    def flush_step() -> None:
        nonlocal current_step
        if current_step and current_job is not None and step_indent is not None:
            parsed = _parse_single_step(
                workflow_name, current_job, current_step, step_indent
            )
            if parsed is not None:
                results.append(parsed)
        current_step = None

    for raw in text.splitlines():
        stripped = raw.strip()
        indent = len(raw) - len(raw.lstrip(" "))

        if not stripped or stripped.startswith("#"):
            if in_steps and current_step is not None:
                current_step.append((indent, raw))
            continue

        if indent == 0:
            flush_step()
            current_job = None
            job_indent = None
            job_child_indent = None
            in_steps = False
            steps_indent = None
            step_indent = None
            in_jobs = _strip_inline_comment(stripped) == "jobs:"
            continue

        if not in_jobs:
            continue

        if job_indent is None:
            m = re.match(r"^([A-Za-z0-9_-]+):\s*(?:#.*)?$", stripped)
            if m:
                job_indent = indent
                current_job = m.group(1)
            continue

        if indent < job_indent:
            flush_step()
            current_job = None
            job_child_indent = None
            in_steps = False
            steps_indent = None
            step_indent = None
            continue

        if indent == job_indent:
            flush_step()
            job_child_indent = None
            in_steps = False
            steps_indent = None
            step_indent = None
            m = re.match(r"^([A-Za-z0-9_-]+):\s*(?:#.*)?$", stripped)
            current_job = m.group(1) if m else None
            continue

        if current_job is None:
            continue

        if job_child_indent is None:
            job_child_indent = indent

        if in_steps and steps_indent is not None and indent <= steps_indent:
            flush_step()
            in_steps = False
            steps_indent = None
            step_indent = None

        if not in_steps:
            if (
                indent == job_child_indent
                and _strip_inline_comment(stripped) == "steps:"
            ):
                in_steps = True
                steps_indent = indent
                step_indent = None
            continue

        if step_indent is None:
            if stripped == "-" or stripped.startswith("- "):
                step_indent = indent
            else:
                continue

        if indent == step_indent and (stripped == "-" or stripped.startswith("- ")):
            flush_step()
            current_step = [(indent, raw)]
        elif current_step is not None:
            current_step.append((indent, raw))

    flush_step()
    return results


def _load_parsed_state() -> tuple[Path, set[str], list[SetupGoStep], list[SetupGoStep]]:
    repo_root, workflow_paths = _resolve_repo_root_and_workflows()
    action_inputs = _parse_action_inputs(
        _resolve_action_path().read_text(encoding="utf-8")
    )

    warm_steps: list[SetupGoStep] = []
    consumer_steps: list[SetupGoStep] = []
    found_warm_workflow = False

    for wf_path in workflow_paths:
        steps = _parse_setup_go_steps(wf_path.name, wf_path.read_text(encoding="utf-8"))
        if wf_path.name == GO_CACHE_WORKFLOW_NAME:
            found_warm_workflow = True
            warm_steps.extend(steps)
        else:
            consumer_steps.extend(steps)

    assert found_warm_workflow, (
        f"Missing {GO_CACHE_WORKFLOW_NAME} among discovered workflows"
    )
    assert warm_steps, f"No {SETUP_GO_USES} steps found in {GO_CACHE_WORKFLOW_NAME}"
    assert consumer_steps, f"No consumer {SETUP_GO_USES} steps found in workflows"
    return repo_root, action_inputs, warm_steps, consumer_steps


def test_composite_inputs_match_consumer_and_warm_usage():
    _repo_root, composite_inputs, warm_steps, consumer_steps = _load_parsed_state()
    assert {"go-version-file", "cache-dependency-path", "mode"} <= composite_inputs, (
        f"Composite action missing expected inputs; found {sorted(composite_inputs)}"
    )

    used_consumer_inputs: set[str] = set()
    for step in consumer_steps:
        unknown = set(step.with_inputs) - composite_inputs
        assert not unknown, (
            f"Consumer {step.label} passes unknown setup-go inputs {sorted(unknown)}; "
            f"composite declares {sorted(composite_inputs)}"
        )
        used_consumer_inputs.update(step.with_inputs)

    for step in warm_steps:
        unknown = set(step.with_inputs) - composite_inputs
        assert not unknown, (
            f"Warm job {step.label} passes unknown setup-go inputs {sorted(unknown)}; "
            f"composite declares {sorted(composite_inputs)}"
        )

    expected_consumer_inputs = {"go-version-file", "cache-dependency-path"}
    assert expected_consumer_inputs <= used_consumer_inputs, (
        f"Expected consumers to exercise {sorted(expected_consumer_inputs)}, "
        f"got {sorted(used_consumer_inputs)}"
    )


def test_every_consumer_has_exact_warm_job_match():
    _repo_root, _inputs, warm_steps, consumer_steps = _load_parsed_state()

    warm_by_sig: dict[tuple[str, tuple[str, ...]], SetupGoStep] = {}
    for warm in warm_steps:
        assert warm.mode == "save", (
            f"Warm job {warm.label} must use mode: save, got {warm.mode!r}"
        )
        sig = warm.key_signature
        assert sig not in warm_by_sig, (
            f"Duplicate warm job key signature {sig!r} in {warm.label} and {warm_by_sig[sig].label}"
        )
        warm_by_sig[sig] = warm

    for consumer in consumer_steps:
        assert consumer.key_signature in warm_by_sig, (
            f"Consumer {consumer.label} has no matching warm job in {GO_CACHE_WORKFLOW_NAME}: "
            f"go-version-file={consumer.go_version_file!r}, "
            f"cache-dependency-path={list(consumer.cache_dependency_paths)!r}. "
            f"Available warm signatures: "
            f"{[(w.job_id, w.key_signature) for w in warm_steps]}"
        )


def test_every_warm_job_matches_at_least_one_consumer():
    _repo_root, _inputs, warm_steps, consumer_steps = _load_parsed_state()
    consumer_sigs = {c.key_signature for c in consumer_steps}

    for warm in warm_steps:
        assert warm.key_signature in consumer_sigs, (
            f"Warm job {warm.label} does not match any consumer in .github/workflows: "
            f"go-version-file={warm.go_version_file!r}, "
            f"cache-dependency-path={list(warm.cache_dependency_paths)!r}. "
            f"Consumer signatures: "
            f"{[(c.label, c.key_signature) for c in consumer_steps]}"
        )


def test_all_referenced_go_paths_exist_in_repo():
    repo_root, _inputs, warm_steps, consumer_steps = _load_parsed_state()

    for step in [*warm_steps, *consumer_steps]:
        assert step.go_version_file, f"{step.label} must set go-version-file"
        assert not any(ch in step.go_version_file for ch in _GLOB_WILDCARDS), (
            f"{step.label} go-version-file must be a concrete file, got {step.go_version_file!r}"
        )
        version_target = repo_root / step.go_version_file
        assert version_target.is_file(), (
            f"{step.label} go-version-file {step.go_version_file!r} does not exist at {version_target}"
        )

        for pat in step.cache_dependency_paths:
            assert not pat.startswith("!"), (
                f"{step.label} unexpected negation-only pattern {pat!r}"
            )
            if any(ch in pat for ch in _GLOB_WILDCARDS):
                matches = [p for p in repo_root.glob(pat) if p.is_file()]
                assert matches, (
                    f"{step.label} cache-dependency-path glob {pat!r} matched 0 files under {repo_root}"
                )
            else:
                target = repo_root / pat
                assert target.is_file(), (
                    f"{step.label} cache-dependency-path {pat!r} does not exist at {target}"
                )


def test_parser_handles_comments_multiline_four_space_indent_and_run_blocks():
    sample = """
jobs:
    four-space-job:
        runs-on: ubuntu-26.04
        steps:
            - name: Fake run mentioning setup-go
              run: |
                echo "uses: ./.github/actions/setup-go"
            - uses: ./.github/actions/setup-go
              with:
                go-version-file: go.mod # inline comment
                # comment between inputs
                cache-dependency-path: |
                  infrastructure/pulumi/**/go.sum
                  packages/pulumi/examples/**/go.sum
            - uses: ./.github/actions/setup-go
              with:
                go-version-file: apps/cli/vitruvian-devx/go.mod
"""
    steps = _parse_setup_go_steps("sample.yaml", sample)
    assert len(steps) == 2
    assert steps[0].key_signature == (
        "go.mod",
        ("infrastructure/pulumi/**/go.sum", "packages/pulumi/examples/**/go.sum"),
    )
    assert steps[1].key_signature == (
        "apps/cli/vitruvian-devx/go.mod",
        (DEFAULT_CACHE_DEPENDENCY_PATH,),
    )
