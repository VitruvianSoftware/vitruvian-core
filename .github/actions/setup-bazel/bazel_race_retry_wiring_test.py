# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

"""setup-bazel must install the repo contents cache race retry on the pool.

bazel_race_retry_test checks what the wrapper does; this checks that
setup-bazel still installs it, on the self-hosted runners that share the
cache, after Bazel itself is on PATH. Without it, a dependency bump that adds
repos fails merge-queue jobs again (#5536, queue run 45708649713).
"""

import os
from pathlib import Path

import yaml


def _steps():
    path = os.environ.get("SETUP_BAZEL_ACTION_PATH") or str(
        Path(__file__).resolve().parent / "action.yml"
    )
    doc = yaml.safe_load(Path(path).read_text(encoding="utf-8"))
    return doc["runs"]["steps"]


def _index(steps, pred, what):
    for i, step in enumerate(steps):
        if pred(step):
            return i
    raise AssertionError(f"setup-bazel has no {what} step")


def test_installs_race_retry_on_self_hosted_linux_after_bazel():
    steps = _steps()
    install = _index(
        steps,
        lambda s: 'bazel_race_retry.sh" install ' in str(s.get("run", "")),
        "bazel_race_retry.sh install",
    )
    setup = _index(
        steps,
        lambda s: str(s.get("uses", "")).startswith("bazel-contrib/setup-bazel@"),
        "bazel-contrib/setup-bazel",
    )
    assert install > setup, "the retry must be installed after Bazel is on PATH"

    cond = str(steps[install].get("if", ""))
    assert "runner.environment == 'self-hosted'" in cond, cond
    assert "runner.os == 'Linux'" in cond, cond
    assert "github-hosted" not in cond, cond
    assert "continue-on-error" not in steps[install], (
        "a failed install must fail the job, not leave it unprotected silently"
    )
    assert "${RUNNER_TEMP}" in steps[install]["run"], (
        "the shim dir must be per job (RUNNER_TEMP), never the shared cache volume"
    )
