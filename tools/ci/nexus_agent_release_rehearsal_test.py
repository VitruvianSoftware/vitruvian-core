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
"""The rehearsal of Nexus Agent's release runs the steps the release runs.

Two workflows hold the same steps:

- apps/desktop/nexus-agent/.github/workflows/release.yml is exported to the
  public mirror and builds, packages and publishes a release there. It never
  runs in this repository, and the mirror tags a release before it builds.
- .github/workflows/nexus-agent-mirror-toolchain.yaml rehearses its build and
  packaging here, on pull requests.

A rehearsal of different steps proves nothing about the release, and nothing
else would say they had drifted apart. So this compares, step by step, what
both run between `swift build` and the ZIP: the build command, what is
uploaded and where it is downloaded to, the `lipo` step, every bundle.sh call,
the DMGs and the ZIP. It reads the files as text; nothing is built.

Usage: nexus_agent_release_rehearsal_test.py <release.yml> <rehearsal.yaml>
"""

import difflib
import re
import sys

# Release job -> the rehearsal job that stands in for it.
JOBS = {"build-macos": "build", "package": "package"}

# The steps both files must have, in this order, with the same lines.
SHARED = {
    "build-macos": [
        "Build for ${{ matrix.arch }}",
        "Upload arch binary",
    ],
    "package": [
        "Download arm64 binary",
        "Download x86_64 binary",
        "Create universal binary",
        "Assemble .app bundles",
        "Install create-dmg",
        "Create DMGs",
        "Create ZIP for auto-updater",
    ],
}

# Steps only the release has: they publish, with the mirror's token.
RELEASE_ONLY = {"Upload release assets", "Update Homebrew Cask"}

# Steps only the rehearsal has: what it prints and what it checks.
REHEARSAL_ONLY = {
    "Show the toolchain the mirror builds with",
    "Run the tests",
    "Show what was downloaded",
    "Check the three apps",
    "Check the app inside the ZIP",
}

# Where the package is in this repository. The mirror has it at its root.
PACKAGE_PREFIX = "apps/desktop/nexus-agent/"

# Lines the rehearsal may add to a shared step: its artifacts are read once,
# minutes later, so they are not kept for the default ninety days.
REHEARSAL_EXTRA_LINES = {"retention-days: 1"}

CHECKOUT = "uses: actions/checkout"


def job_lines(text, job):
    """The lines of one job, without the line that names it."""
    lines = text.splitlines()
    try:
        start = lines.index("  %s:" % job)
    except ValueError:
        return None
    end = len(lines)
    for i in range(start + 1, len(lines)):
        if re.match(r"  \S", lines[i]):
            end = i
            break
    return lines[start + 1 : end]


def significant(lines):
    """Stripped lines, without blank ones and comments."""
    out = []
    for line in lines:
        stripped = line.strip()
        if stripped and not stripped.startswith("#"):
            out.append(stripped)
    return out


def split_job(lines):
    """A job's own settings, then its steps as (title, lines) in order."""
    header, steps, current = [], [], None
    in_steps = False
    for line in lines:
        if line == "    steps:":
            in_steps = True
            continue
        if not in_steps:
            header.append(line)
            continue
        if line.startswith("      - "):
            current = [line.replace("- ", "", 1)]
            steps.append(current)
        elif current is not None:
            current.append(line)
    titled = []
    for step in steps:
        body = significant(step)
        title = body[0]
        for entry in body:
            if entry.startswith("name: "):
                title = entry[len("name: ") :]
                break
        titled.append((title, body))
    return significant(header), titled


def normalise(body, rehearsal):
    """A step's lines with what may differ between the two files taken out."""
    out = []
    for line in body:
        if rehearsal:
            if line in REHEARSAL_EXTRA_LINES:
                continue
            line = line.replace(PACKAGE_PREFIX, "")
        # The mirror names an action's version by tag (`@v7`), this repository
        # by commit with the version in a comment (`@<commit> # v7.0.2`).
        # Which action it is, and its major version, must still match: a
        # major version is where an artifact's layout changes.
        line = re.sub(r"^(uses: [^@\s]+)@v(\d+)[.\d]*$", r"\1@v\2", line)
        line = re.sub(
            r"^(uses: [^@\s]+)@[0-9a-f]{40}\s+#\s*v(\d+)[.\d]*$", r"\1@v\2", line
        )
        # The release packages the version it detected, the rehearsal a
        # made-up one.
        line = re.sub(r'^VERSION=".*"$', 'VERSION="<version>"', line)
        out.append(line)
    return out


def setting(header, key):
    """The lines of a job's settings that start with `key`."""
    return [line for line in header if line.startswith(key)]


def compare(release_text, rehearsal_text):
    """Every way the two files differ where they must not. Empty when in step."""
    problems = []
    for release_job, rehearsal_job in JOBS.items():
        sides = {}
        for name, text, job, only in (
            ("release.yml", release_text, release_job, RELEASE_ONLY),
            ("the rehearsal", rehearsal_text, rehearsal_job, REHEARSAL_ONLY),
        ):
            lines = job_lines(text, job)
            if lines is None:
                problems.append("%s has no job `%s`" % (name, job))
                continue
            header, steps = split_job(lines)
            kept = [
                (title, body)
                for title, body in steps
                if title not in only and not title.startswith(CHECKOUT)
            ]
            titles = [title for title, _ in kept]
            if titles != SHARED[release_job]:
                problems.append(
                    "%s, job `%s`: the steps are\n    %s\n  expected\n    %s\n"
                    "  A step added to one file belongs in the other too, and in "
                    "the lists at the top of this test."
                    % (name, job, titles, SHARED[release_job])
                )
            sides[name] = (header, dict(kept))
        if len(sides) != 2:
            continue
        release_header, release_steps = sides["release.yml"]
        rehearsal_header, rehearsal_steps = sides["the rehearsal"]

        for key in ("runs-on:", "arch:"):
            ours, theirs = setting(rehearsal_header, key), setting(release_header, key)
            if ours != theirs:
                problems.append(
                    "job `%s`: release.yml has %s, the rehearsal's `%s` has %s"
                    % (release_job, theirs, rehearsal_job, ours)
                )

        for title in SHARED[release_job]:
            if title not in release_steps or title not in rehearsal_steps:
                continue
            want = normalise(release_steps[title], rehearsal=False)
            got = normalise(rehearsal_steps[title], rehearsal=True)
            if want != got:
                diff = "\n".join(
                    difflib.unified_diff(
                        want, got, "release.yml", "the rehearsal", lineterm="", n=1
                    )
                )
                problems.append("step `%s` differs:\n%s" % (title, diff))
    return problems


def looked_at_what_matters(release_text):
    """Problems when the lines this test exists for were not among those read.

    A comparison of two empty lists passes. This makes sure the release's own
    steps were found and hold the build command, the uploaded paths, the
    download targets and the three bundle.sh calls.
    """
    problems = []
    found = {}
    for job in JOBS:
        lines = job_lines(release_text, job)
        if lines is not None:
            found.update(dict(split_job(lines)[1]))

    def body(title):
        return found.get(title, [])

    def expect(what, ok):
        if not ok:
            problems.append("release.yml: did not find %s" % what)

    expect(
        "the `swift build` line",
        "swift build -c release --arch ${{ matrix.arch }}"
        in body("Build for ${{ matrix.arch }}"),
    )
    upload = body("Upload arch binary")
    paths = []
    if "path: |" in upload:
        for line in upload[upload.index("path: |") + 1 :]:
            if ":" in line:
                break
            paths.append(line)
    expect(
        "two uploaded paths, the executable and the resource folder", len(paths) == 2
    )
    expect(
        "`if-no-files-found: error` on the upload",
        "if-no-files-found: error" in upload,
    )
    for arch in ("arm64", "x86_64"):
        expect(
            "where the %s artifact is downloaded to" % arch,
            "path: /tmp/%s" % arch in body("Download %s binary" % arch),
        )
    expect(
        "the `lipo -create` line",
        any(
            line.startswith("lipo -create") for line in body("Create universal binary")
        ),
    )
    calls = [
        line
        for line in body("Assemble .app bundles")
        if line.startswith("macos/scripts/bundle.sh ")
    ]
    expect("three bundle.sh calls", len(calls) == 3)
    return problems


def main(argv):
    if len(argv) != 3:
        print(__doc__)
        return 2
    with open(argv[1], encoding="utf-8") as handle:
        release_text = handle.read()
    with open(argv[2], encoding="utf-8") as handle:
        rehearsal_text = handle.read()

    problems = looked_at_what_matters(release_text) + compare(
        release_text, rehearsal_text
    )
    if problems:
        print(
            "The release (%s) and its rehearsal (%s) are out of step:\n"
            % (argv[1], argv[2])
        )
        for problem in problems:
            print("- " + problem + "\n")
        print(
            "Make the same change in both files. The rehearsal may differ only "
            "in the path to the package (%s), in pinning actions to commits, "
            "and in the version it packages." % PACKAGE_PREFIX
        )
        return 1
    shared = sum(len(steps) for steps in SHARED.values())
    print("in step: %d shared steps in %d jobs" % (shared, len(JOBS)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
