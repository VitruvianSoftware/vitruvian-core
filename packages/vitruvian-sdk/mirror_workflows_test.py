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
"""The mirror's workflows release a version once, never 0.0.0, and write
nowhere they need not.

    mirror_workflows_test.py

.github/workflows/ci.yml and release.yml run only in VitruvianSoftware/
vitruvian-sdk, so nothing in this repository runs them. This test reads them
as YAML and runs the `detect` step of release.yml, the shell exactly as
written, with bash and git, in a repository it makes in a temporary folder,
once for each kind of manifest. It runs the release notes step the same way,
with and without a CHANGELOG.md, since a first release can come before the
file does. It also holds what limits the damage of a
mistake: the workflow may only read; only the release job may write, and
only contents, and only the two jobs that publish a kit may ask for an
identity token; no checkout keeps its credentials; every action is pinned to
a commit.
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


def detect_step(release):
    for step in release["jobs"]["detect"]["steps"]:
        if step.get("id") == "detect":
            return step["run"]
    raise SystemExit("release.yml has no step with the id detect")


def detect(script, manifest, tags=()):
    """Runs the step in a new repository whose manifest says `manifest`
    (None: no manifest). Gives its exit status, what it wrote to
    GITHUB_OUTPUT, and what it printed."""
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
                json.dump({"packages/vitruvian-sdk": manifest}, f)
        with open(os.path.join(root, "README.md"), "w") as f:
            f.write("x\n")
        git("add", "-A")
        git("commit", "-q", "-m", "m")
        for tag in tags:
            git("tag", tag)
        output = os.path.join(root, ".output")
        open(output, "w").close()
        done = subprocess.run(
            ["bash", "--noprofile", "--norc", "-eo", "pipefail", "-c", script],
            cwd=root,
            env={
                "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
                "GITHUB_OUTPUT": output,
            },
            capture_output=True,
            text=True,
            timeout=30,
            check=False,
        )
        with open(output) as f:
            return done.returncode, f.read().strip(), done.stdout + done.stderr


def detect_problems(release):
    script = detect_step(release)
    problems = []
    for manifest, tags, status, wanted in [
        (None, (), 0, ""),
        ("0.0.0", (), 0, ""),
        ("0.9.0", (), 0, "version=0.9.0"),
        ("0.9.0", ("v0.9.0",), 0, ""),
        ("0.9.0", ("go/v0.9.0", "vitruvian-sdk-v0.9.0"), 0, "version=0.9.0"),
        ("0.9", (), 1, ""),
    ]:
        got_status, got, printed = detect(script, manifest, tags)
        if (got_status, got) != (status, wanted):
            problems.append(
                f"detect with manifest {manifest} and tags {list(tags)}: "
                f"exit {got_status} and {got!r}, want exit {status} and {wanted!r}\n{printed}"
            )
    return problems


NOTES_STEP = "Write the release notes"
NO_CHANGES = "has no section for 0.9.0"


def notes_step(release):
    for step in release["jobs"]["release"]["steps"]:
        if step.get("name") == NOTES_STEP:
            return step["run"]
    raise SystemExit(f"release.yml's release job has no step named {NOTES_STEP!r}")


def notes(script, changelog):
    """Runs the step for version 0.9.0 in a folder whose CHANGELOG.md says
    `changelog` (None: no CHANGELOG.md). Gives its exit status, the notes it
    wrote, and what it printed."""
    with tempfile.TemporaryDirectory(dir=os.environ.get("TEST_TMPDIR")) as root:
        if changelog is not None:
            with open(os.path.join(root, "CHANGELOG.md"), "w") as f:
                f.write(changelog)
        done = subprocess.run(
            ["bash", "--noprofile", "--norc", "-eo", "pipefail", "-c", script],
            cwd=root,
            env={
                "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
                "RUNNER_TEMP": root,
                "V": "0.9.0",
            },
            capture_output=True,
            text=True,
            timeout=30,
            check=False,
        )
        written = os.path.join(root, "notes.md")
        text = ""
        if os.path.exists(written):
            with open(written) as f:
                text = f.read()
        return done.returncode, text, done.stdout + done.stderr


# What release-please writes: a first release has no compare link, so no
# brackets; a later one has both.
FIRST = """# Changelog

## 0.9.0 (2026-10-13)


### Features

* **vitruvian-sdk:** publish the SDK, version 0.9.0 ([#1](https://x/1)) ([abc1234](https://x/c))
"""
LATER = """# Changelog

## [0.10.0](https://x/compare/v0.9.0...v0.10.0) (2026-11-01)


### Features

* the kits

## [0.9.0](https://x/compare/v0.8.0...v0.9.0) (2026-10-13)


### Bug Fixes

* a fix in 0.9.0

## 0.8.0 (2026-10-01)


### Features

* older work
"""
OTHER = """# Changelog

## 0.8.0 (2026-10-01)


### Features

* older work
"""


def notes_problems(release):
    script = notes_step(release)
    problems = []
    for name, changelog, wanted, unwanted in [
        ("no CHANGELOG.md", None, [NO_CHANGES], []),
        ("a first release", FIRST, ["## Features", "publish the SDK"], [NO_CHANGES]),
        (
            "a later release",
            LATER,
            ["## Bug Fixes", "a fix in 0.9.0"],
            [NO_CHANGES, "the kits", "older work"],
        ),
        ("no section for 0.9.0", OTHER, [NO_CHANGES], ["older work"]),
    ]:
        status, text, printed = notes(script, changelog)
        if status != 0:
            problems.append(f"notes with {name}: exit {status}\n{printed}")
            continue
        wanted = ["brew install VitruvianSoftware/tap/vitruvian-tool", *wanted]
        for line in wanted:
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
        allowed = {
            ("release.yml", "release"): ["contents"],
            # The kits publish by trusted publishing: the registry takes the
            # job's identity token in place of a secret, and nothing else.
            ("release.yml", "publish-npm-kit"): ["id-token"],
            ("release.yml", "publish-pypi-kit"): ["id-token"],
        }.get((name, job_name), [])
        if writes != allowed:
            problems.append(f"{name}: job {job_name} may write {writes}, not {allowed}")
        for step in job["steps"]:
            uses = step.get("uses")
            if not uses:
                continue
            if not re.fullmatch(r"[\w.-]+/[\w./-]+@[0-9a-f]{40}", uses):
                problems.append(f"{name}: {uses} is not pinned to a commit")
            if (
                uses.startswith("actions/checkout@")
                and (step.get("with") or {}).get("persist-credentials") is not False
            ):
                problems.append(
                    f"{name}: job {job_name} checks out with its credentials kept"
                )
    return problems


def main():
    release = load("release.yml")
    problems = detect_problems(release)
    problems += notes_problems(release)
    for name in ("ci.yml", "release.yml"):
        problems += limit_problems(name, load(name))
    for problem in problems:
        print(problem, file=sys.stderr)
    print("mirror workflows: " + ("FAILED" if problems else "OK"))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
