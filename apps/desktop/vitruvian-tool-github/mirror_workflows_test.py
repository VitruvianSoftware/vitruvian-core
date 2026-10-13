#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 VitruvianSoftware

"""The mirror's workflows release a version once, never 0.0.0, and write
nowhere they need not.

    mirror_workflows_test.py

.github/workflows/ci.yml and release.yml run only in
VitruvianSoftware/vitruvian-tool-github, so nothing in this repository runs
them. This test reads them as YAML and runs the `detect` step of release.yml,
the shell exactly as written, with bash and git, in a repository it makes in
a temporary folder, once for each kind of manifest. It runs the release
notes step the same way, with and without a CHANGELOG.md. It also holds what
limits the damage of a mistake: the workflows may only read; only the
release job may write, and only contents; no job asks for an identity token;
no checkout keeps its credentials; every action is pinned to a commit.
"""

import json
import os
import re
import subprocess
import sys
import tempfile

import yaml

HERE = os.path.dirname(os.path.abspath(__file__))
WORKFLOWS = os.path.join(HERE, ".github", "workflows")


def load(name):
    with open(os.path.join(WORKFLOWS, name), encoding="utf-8") as handle:
        return yaml.safe_load(handle)


def step(workflow, job, key, value):
    for candidate in workflow["jobs"][job]["steps"]:
        if candidate.get(key) == value:
            return candidate["run"]
    raise SystemExit(f"release.yml's {job} job has no step with {key} {value!r}")


def run_step(script, root, env):
    return subprocess.run(
        ["bash", "--noprofile", "--norc", "-eo", "pipefail", "-c", script],
        cwd=root,
        env={"PATH": os.environ.get("PATH", "/usr/bin:/bin"), **env},
        capture_output=True,
        text=True,
        timeout=30,
        check=False,
    )


def detect(script, manifest, tags=()):
    with tempfile.TemporaryDirectory(dir=os.environ.get("TEST_TMPDIR")) as root:

        def git(*words):
            subprocess.run(
                ["git", "-c", "user.name=t", "-c", "user.email=t@t", *words],
                cwd=root,
                check=True,
                capture_output=True,
            )

        git("init", "-q")
        if manifest is not None:
            with open(os.path.join(root, ".release-please-manifest.json"), "w") as f:
                json.dump({"apps/desktop/vitruvian-tool-github": manifest}, f)
        with open(os.path.join(root, "README.md"), "w") as f:
            f.write("x\n")
        git("add", "-A")
        git("commit", "-q", "-m", "m")
        for tag in tags:
            git("tag", tag)
        output = os.path.join(root, ".output")
        open(output, "w").close()
        done = run_step(script, root, {"GITHUB_OUTPUT": output})
        with open(output) as f:
            return done.returncode, f.read().strip(), done.stdout + done.stderr


def detect_problems(release):
    script = step(release, "detect", "id", "detect")
    problems = []
    for manifest, tags, status, wanted in [
        (None, (), 0, ""),
        ("0.0.0", (), 0, ""),
        ("1.0.0", (), 0, "version=1.0.0"),
        ("1.0.0", ("v1.0.0",), 0, ""),
        ("1.0.0", ("vitruvian-tool-github-v1.0.0",), 0, "version=1.0.0"),
        ("1.0", (), 1, ""),
    ]:
        got_status, got, printed = detect(script, manifest, tags)
        if (got_status, got) != (status, wanted):
            problems.append(
                f"detect with manifest {manifest} and tags {list(tags)}: exit {got_status} and {got!r}, "
                f"want exit {status} and {wanted!r}\n{printed}"
            )
    return problems


NO_CHANGES = "has no section for 1.0.0"
FIRST = "# Changelog\n\n## 1.0.0 (2026-11-02)\n\n\n### Features\n\n* the GitHub tool ([#1](https://x/1))\n"
LATER = (
    "# Changelog\n\n## [1.1.0](https://x/compare/v1.0.0...v1.1.0) (2026-12-01)\n\n\n### Features\n\n* later\n\n"
    "## [1.0.0](https://x/compare/v0.9.0...v1.0.0) (2026-11-02)\n\n\n### Bug Fixes\n\n* a fix in 1.0.0\n"
)


def notes_problems(release):
    script = step(release, "release", "name", "Write the release notes")
    problems = []
    for name, changelog, wanted, unwanted in [
        ("no CHANGELOG.md", None, [NO_CHANGES], []),
        ("a first release", FIRST, ["## Features", "the GitHub tool"], [NO_CHANGES]),
        (
            "a later release",
            LATER,
            ["## Bug Fixes", "a fix in 1.0.0"],
            [NO_CHANGES, "later"],
        ),
    ]:
        with tempfile.TemporaryDirectory(dir=os.environ.get("TEST_TMPDIR")) as root:
            if changelog is not None:
                with open(os.path.join(root, "CHANGELOG.md"), "w") as f:
                    f.write(changelog)
            done = run_step(
                script,
                root,
                {
                    "RUNNER_TEMP": root,
                    "V": "1.0.0",
                    "ASSET": "github-tool-1.0.0.zip",
                    "ASSET_SIZE": "1234",
                    "ASSET_SHA256": "ab" * 32,
                },
            )
            text = ""
            if os.path.exists(os.path.join(root, "notes.md")):
                with open(os.path.join(root, "notes.md")) as f:
                    text = f.read()
        if done.returncode != 0:
            problems.append(
                f"notes with {name}: exit {done.returncode}\n{done.stdout}{done.stderr}"
            )
            continue
        for line in ["Browse Tools", "`size`: 1234, `sha256`: " + "ab" * 32, *wanted]:
            if line not in text:
                problems.append(f"notes with {name}: no {line!r}\n{text}")
        for line in unwanted:
            if line in text:
                problems.append(f"notes with {name}: has {line!r}\n{text}")
    return problems


def limit_problems(name, workflow):
    problems = []
    if workflow.get("permissions") != {"contents": "read"}:
        problems.append(f"{name}: the workflow's permissions are not contents: read")
    for job_name, job in workflow["jobs"].items():
        writes = sorted(
            k for k, v in (job.get("permissions") or {}).items() if v == "write"
        )
        allowed = {("release.yml", "release"): ["contents"]}.get((name, job_name), [])
        if writes != allowed:
            problems.append(f"{name}: job {job_name} may write {writes}, not {allowed}")
        if "id-token" in (job.get("permissions") or {}):
            problems.append(
                f"{name}: job {job_name} asks for an identity token; nothing here publishes to a registry"
            )
        for item in job["steps"]:
            uses = item.get("uses")
            if not uses:
                continue
            if not re.fullmatch(r"[\w.-]+/[\w./-]+@[0-9a-f]{40}", uses):
                problems.append(f"{name}: {uses} is not pinned to a commit")
            if (
                uses.startswith("actions/checkout@")
                and (item.get("with") or {}).get("persist-credentials") is not False
            ):
                problems.append(
                    f"{name}: job {job_name} checks out with its credentials kept"
                )
    return problems


def main():
    release = load("release.yml")
    problems = detect_problems(release) + notes_problems(release)
    for name in ("ci.yml", "release.yml"):
        problems += limit_problems(name, load(name))
    for problem in problems:
        print(problem, file=sys.stderr)
    print("mirror workflows: " + ("FAILED" if problems else "OK"))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
