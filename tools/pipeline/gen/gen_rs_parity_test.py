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

"""//tools/pipeline/gen (Rust) against //tools/pipeline/gen:gen-go, side by side.

Every case builds a throwaway workspace (BUILD trees, .pipeline.json unit
directories, a pin manifest), runs both binaries with the same arguments,
environment and working directory, and requires the same exit code, stdout,
stderr and the same files left behind. Go's usage text names argv[0], so
that is masked; a Go panic prints a goroutine trace, so for a panic only its
first line and the exit code (2) are compared.

The cases: the real repository's .github/workflows/presubmit.yaml (every
format, --check against the committed file, and the `bazel run` path through
BUILD_WORKSPACE_DIRECTORY); every testdata fixture with every format and
filter; the scenarios of main_test.go and runner_test.go as unit files and
BUILD trees; and flag, decode, reader and pin-manifest error cases.
"""

import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest

HERE = os.getcwd()
GO = os.path.join(HERE, os.environ["GEN_GO"])
RS = os.path.join(HERE, os.environ["GEN_RS"])
PKG = os.path.join(HERE, "tools", "pipeline", "gen")
TESTDATA = os.path.join(PKG, "testdata")
FIXTURE_UNITS = os.path.join(TESTDATA, "units")
FIXTURE_PINS = os.path.join(TESTDATA, "action-pins.yml")
REPO_PINS = os.path.join(HERE, ".github", "actions", "pins", "action.yml")

SHA = "3d3c42e5aac5ba805825da76410c181273ba90b1"
PINNED = [
    "actions/checkout",
    "actions/setup-go",
    "actions/cache/restore",
    "actions/cache/save",
    "actions/upload-artifact",
]


def pins_text(actions=PINNED, sha=SHA, sep="\n"):
    return "".join(f"      - uses: {a}@{sha} # v1{sep}" for a in actions)


def source_workspace():
    """The checkout this test was built from, through the runfiles symlink.
    None when the runfiles are copies (remote execution)."""
    real = os.path.realpath(os.path.join(TESTDATA, "action-pins.yml"))
    ws = os.path.dirname(
        os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(real))))
    )
    if real == os.path.join(TESTDATA, "action-pins.yml"):
        return None
    if os.path.isfile(os.path.join(ws, "MODULE.bazel")) and os.path.isfile(
        os.path.join(ws, ".github", "workflows", "presubmit.yaml")
    ):
        return ws
    return None


def build(root, files):
    """Writes {relpath: str|bytes|None}; None makes a directory."""
    for rel, body in files.items():
        p = os.path.join(root, rel)
        if body is None:
            os.makedirs(p, exist_ok=True)
            continue
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "wb") as f:
            f.write(body if isinstance(body, bytes) else body.encode())


def snapshot(root):
    out = {}
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames.sort()
        for d in dirnames:
            out[os.path.relpath(os.path.join(dirpath, d), root) + "/"] = b""
        for n in sorted(filenames):
            p = os.path.join(dirpath, n)
            rel = os.path.relpath(p, root)
            try:
                with open(p, "rb") as f:
                    out[rel] = f.read()
            except OSError as e:
                out[rel] = f"<unreadable {e.errno}>".encode()
    return out


def unit_json(name, **kw):
    u = {"schema": 1, "name": name, "test_targets": [f"//{name}:t"]}
    u.update(kw)
    return json.dumps(u)


def unit_dir(units):
    return {f"units/{n}.pipeline.json": body for n, body in units.items()}


class Case:
    def __init__(
        self, name, files=None, args=(), env=None, cwd="", setup=None, base_env=True
    ):
        self.name = name
        self.files = files or {}
        self.args = list(args)
        self.env = env or {}
        self.cwd = cwd
        self.setup = setup
        self.base_env = base_env


SCRATCH = "{SCRATCH}"


def run_case(binary, case, scratch):
    if os.path.exists(scratch):
        for dirpath, dirnames, _ in os.walk(scratch):
            for d in dirnames:
                os.chmod(os.path.join(dirpath, d), 0o755)
        shutil.rmtree(scratch)
    os.makedirs(scratch)
    build(scratch, case.files)
    if case.setup:
        case.setup(scratch)
    env = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": scratch}
    for k in ("TEST_SRCDIR", "TEST_WORKSPACE"):
        if case.base_env and k in os.environ:
            env[k] = os.environ[k]
    for k, v in case.env.items():
        if v is None:
            env.pop(k, None)
        else:
            env[k] = v.replace(SCRATCH, scratch)
    cwd = os.path.join(scratch, case.cwd) if not os.path.isabs(case.cwd) else case.cwd
    env["PWD"] = cwd
    args = [a.replace(SCRATCH, scratch) for a in case.args]
    p = subprocess.run(
        [binary] + args, cwd=cwd, env=env, capture_output=True, timeout=300
    )
    stderr = p.stderr.replace(binary.encode(), b"<argv0>")
    if p.returncode == 2 and stderr.startswith(b"panic: "):
        stderr = stderr.split(b"\n", 1)[0] + b"\n<goroutine trace>"
    files = snapshot(scratch)
    return p.returncode, p.stdout, stderr, files


class Parity(unittest.TestCase):
    cases_run = 0

    def check(self, cases):
        failures = []
        root = tempfile.mkdtemp(prefix="gen-parity-")
        scratch = os.path.join(root, "ws")
        try:
            for c in cases:
                go = run_case(GO, c, scratch)
                rs = run_case(RS, c, scratch)
                Parity.cases_run += 1
                if go != rs:
                    labels = ("exit code", "stdout", "stderr", "files")
                    diff = [
                        f"{l}: go={g!r:.600} rs={r!r:.600}"
                        for l, g, r in zip(labels, go, rs)
                        if g != r
                    ]
                    failures.append(f"{c.name}:\n  " + "\n  ".join(diff))
        finally:
            for dirpath, dirnames, _ in os.walk(root):
                for d in dirnames:
                    os.chmod(os.path.join(dirpath, d), 0o755)
            shutil.rmtree(root, ignore_errors=True)
        self.assertEqual(failures, [], "\n".join(failures))

    # ---- the real repository ------------------------------------------

    def test_real_repository(self):
        ws = source_workspace()
        if ws is None:
            print(
                "note: source checkout not reachable from the runfiles; real-repo cases skipped",
                file=sys.stderr,
            )
            self.skipTest("source checkout not reachable")
        committed = os.path.join(ws, ".github", "workflows", "presubmit.yaml")
        cases = []
        for fmt in ("workflow", "matrix", "json", "dag"):
            cases.append(
                Case(
                    f"repo --format={fmt}", args=["--repo-root", ws, f"--format={fmt}"]
                )
            )
        cases += [
            Case(
                "repo --check committed presubmit.yaml",
                args=[
                    "--repo-root",
                    ws,
                    "--format=workflow",
                    "--output-file",
                    committed,
                    "--check",
                ],
            ),
            Case(
                "repo via BUILD_WORKSPACE_DIRECTORY (bazel run), --check relative path",
                args=[
                    "--format=workflow",
                    "--output-file=.github/workflows/presubmit.yaml",
                    "--check",
                ],
                env={"BUILD_WORKSPACE_DIRECTORY": ws},
            ),
            Case(
                "repo write to scratch (format from .yaml suffix)",
                args=[
                    "--repo-root",
                    ws,
                    "--output-file",
                    SCRATCH + "/out/presubmit.yaml",
                ],
                env={"BUILD_WORKSPACE_DIRECTORY": ws},
            ),
            Case(
                "repo matrix L1 backend",
                args=["--repo-root", ws, "--tier=L1", "--persona=backend"],
            ),
        ]
        self.check(cases)
        # And the Rust binary regenerates the committed file exactly.
        p = subprocess.run(
            [RS, "--repo-root", ws, "--format=workflow"],
            capture_output=True,
            env={"PATH": os.environ.get("PATH", ""), "BUILD_WORKSPACE_DIRECTORY": ws},
        )
        self.assertEqual(p.returncode, 0, p.stderr)
        with open(committed, "rb") as f:
            self.assertEqual(
                p.stdout,
                f.read(),
                "Rust output differs from the committed presubmit.yaml",
            )

    # ---- testdata fixtures --------------------------------------------

    def fixture_files(self, pins=None):
        files = {}
        for n in sorted(os.listdir(FIXTURE_UNITS)):
            with open(os.path.join(FIXTURE_UNITS, n), "rb") as f:
                files["units/" + n] = f.read()
        with open(pins or FIXTURE_PINS, "rb") as f:
            files[".github/actions/pins/action.yml"] = f.read()
        return files

    def test_fixtures(self):
        files = self.fixture_files()
        env = {"BUILD_WORKSPACE_DIRECTORY": SCRATCH}
        cases = []
        for fmt in ("workflow", "matrix", "json", "dag", "bogus", ""):
            cases.append(
                Case(
                    f"fixtures --format={fmt}",
                    files,
                    ["--units-dir=units", f"--format={fmt}"],
                    env,
                )
            )
        for tier in ("L0", "L1", "L2", "L3", "all", "", "nope"):
            for persona in (
                "frontend",
                "backend",
                "infra",
                "platform",
                "security",
                "docs",
                "all",
                "",
            ):
                cases.append(
                    Case(
                        f"fixtures tier={tier} persona={persona}",
                        files,
                        ["--units-dir", "units", "--tier", tier, "--persona", persona],
                        env,
                    )
                )
        with open(os.path.join(TESTDATA, "golden.presubmit.yaml"), "rb") as f:
            golden = f.read()
        with open(os.path.join(TESTDATA, "golden.matrix.json"), "rb") as f:
            golden_matrix = f.read()
        files_golden = dict(
            files,
            **{"golden.presubmit.yaml": golden, "golden.matrix.json": golden_matrix},
        )
        cases += [
            Case(
                "fixtures --check golden presubmit",
                files_golden,
                ["--units-dir=units", "--output-file=golden.presubmit.yaml", "--check"],
                env,
            ),
            Case(
                "fixtures --check golden matrix",
                files_golden,
                [
                    "--units-dir=units",
                    "--format=matrix",
                    "--output-file=golden.matrix.json",
                    "--check",
                ],
                env,
            ),
            Case(
                "fixtures --check stale",
                dict(files, **{"p.yaml": "stale\n"}),
                ["--units-dir=units", "--output-file=p.yaml", "--check"],
                env,
            ),
            Case(
                "fixtures --check missing file",
                files,
                ["--units-dir=units", "--output-file=absent.yaml", "--check"],
                env,
            ),
            Case(
                "fixtures --check without --output-file",
                files,
                ["--units-dir=units", "--check"],
                env,
            ),
            Case(
                "fixtures --check=false writes",
                files,
                ["--units-dir=units", "--output-file=w.yml", "--check=false"],
                env,
            ),
            Case(
                "fixtures write nested",
                files,
                [
                    "--units-dir=units",
                    "--format=json",
                    "--output-file=a/b/c/units.json",
                ],
                env,
            ),
            Case(
                "fixtures write dag absolute",
                files,
                [
                    "--units-dir",
                    SCRATCH + "/units",
                    "--format=dag",
                    "--output-file",
                    SCRATCH + "/dag.txt",
                ],
                env,
            ),
            Case(
                "fixtures write over existing",
                dict(files, **{"o.yaml": "old"}),
                ["--units-dir=units", "--output-file=o.yaml"],
                env,
            ),
            Case(
                "fixtures repo-root + relative units-dir",
                files,
                ["--repo-root", SCRATCH, "--units-dir", "units", "--format=dag"],
                {},
            ),
            Case(
                "fixtures from cwd (no repo root)",
                files,
                ["--units-dir", "units", "--format=json"],
                {},
                cwd="",
            ),
            Case(
                "fixtures workflow, pins from the runfiles",
                files,
                ["--units-dir=units", "--format=workflow"],
                {},
            ),
        ]
        # Every fixture alone: units with dependencies then fail the DAG.
        for n in sorted(os.listdir(FIXTURE_UNITS)):
            one = {
                k: v
                for k, v in files.items()
                if not k.startswith("units/") or k == "units/" + n
            }
            cases.append(
                Case(
                    f"fixture alone {n}",
                    one,
                    ["--units-dir=units", "--format=workflow"],
                    env,
                )
            )
        self.check(cases)
        # The Rust workflow is the golden file byte for byte (TestGoldenPresubmitValidation).
        tmp = tempfile.mkdtemp()
        try:
            build(tmp, files)
            p = subprocess.run(
                [RS, "--units-dir", os.path.join(tmp, "units"), "--format=workflow"],
                capture_output=True,
                env={"BUILD_WORKSPACE_DIRECTORY": tmp, "PATH": "/usr/bin:/bin"},
            )
            self.assertEqual(p.stdout, golden)
            p = subprocess.run(
                [RS, "--units-dir", os.path.join(tmp, "units")], capture_output=True
            )
            self.assertEqual(json.loads(p.stdout), json.loads(golden_matrix))
        finally:
            shutil.rmtree(tmp)

    # ---- main_test.go / runner_test.go scenarios as unit files ----------

    def test_unit_file_scenarios(self):
        env = {"BUILD_WORKSPACE_DIRECTORY": SCRATCH}
        pins = {".github/actions/pins/action.yml": pins_text()}
        base = dict(
            package="a",
            tier="L1",
            runner="ubuntu-26.04",
            persona="all",
            timeout_minutes=10,
        )
        scen = {
            "gated on the plan": {
                "alpha": unit_json("alpha", **base),
                "beta": unit_json("beta", depends_on=["alpha"], **base),
            },
            "gate evaluates upstream results": {"alpha": unit_json("alpha", **base)},
            "release, queue and fast-lane plan": {
                "alpha": unit_json("alpha", **base),
                "beta": unit_json("beta", **base),
            },
            "emulator": {
                "with-emulator": unit_json(
                    "with-emulator",
                    package="apps/mobile/android-remote",
                    test_targets=["//apps/mobile/android-remote:boot_smoke"],
                    persona="frontend",
                    timeout_minutes=45,
                    needs_emulator=True,
                ),
                "without-emulator": unit_json(
                    "without-emulator",
                    package="apps/mobile/android-remote",
                    test_targets=["//apps/mobile/android-remote:lib"],
                    persona="frontend",
                    timeout_minutes=30,
                ),
            },
            "artifacts": {
                "with-artifacts": unit_json(
                    "with-artifacts",
                    test_targets=["//apps/mobile/android-remote:app"],
                    artifacts={
                        "zebra": "z.txt",
                        "alpha": "apps/mobile/android-remote/app.apk",
                    },
                ),
                "without-artifacts": unit_json("without-artifacts"),
            },
            "build flags and env": {
                "remote": unit_json(
                    "remote",
                    artifacts={"apk": "bazel-bin/app.apk"},
                    build_flags=[
                        "--fat_apk_cpu=arm64-v8a,x86_64",
                        '--x="q"\\',
                        "tab\there",
                    ],
                    env={
                        "ANDROID_NDK_HOME": "${{ env.ANDROID_NDK_ROOT }}",
                        "Q": 'a"b\\c\nd',
                        "U": "é  <&>",
                    },
                ),
            },
            "runners": {
                r: unit_json(r, runner=r)
                for r in (
                    "xcode-27",
                    "macos-latest",
                    "macos-26",
                    "ubuntu-26.04",
                    "ubuntu-latest",
                )
            },
            "mac with artifacts": {
                "m": unit_json(
                    "m", runner="macos-15", artifacts={"a": "b"}, needs_emulator=True
                )
            },
            "diamond dag": {
                "a": unit_json("a"),
                "b": unit_json("b", depends_on=["a"]),
                "c": unit_json("c", depends_on=["a"]),
                "d": unit_json("d", depends_on=["c", "b", "b"]),
                "e": unit_json("e"),
            },
            "cycle": {
                "unit-a": unit_json("unit-a", depends_on=["unit-b"]),
                "unit-b": unit_json("unit-b", depends_on=["unit-c"]),
                "unit-c": unit_json("unit-c", depends_on=["unit-a"]),
            },
            "self dependency": {"s": unit_json("s", depends_on=["s"])},
            "missing dependency": {
                "unit-a": unit_json("unit-a", depends_on=["non-existent-unit"])
            },
            "duplicate name": {"x1": unit_json("dup"), "x2": unit_json("dup")},
            "invalid schema": {
                "foo": '{"schema": 2, "name": "foo", "test_targets": [":test"]}'
            },
            "empty name": {
                "foo": '{"schema": 1, "name": "", "test_targets": [":test"]}'
            },
            "blank name": {
                "foo": '{"schema": 1, "name": " \\t", "test_targets": [":test"]}'
            },
            "empty targets": {
                "foo": '{"schema": 1, "name": "foo", "test_targets": []}'
            },
            "defaults filled": {
                "d": '{"schema": 1, "name": "d", "test_targets": [":t"], "timeout_minutes": -4}'
            },
            "tags and concurrency group": {
                "t": unit_json("t", tags=["a", "b"], concurrency_group="custom")
            },
            "html escaping": {
                "h": unit_json("h<&>", package="p ", test_targets=["//a:<b>"])
            },
            "unicode name": {"u": unit_json("ünï-cödé​")},
        }
        cases = []
        for name, units in scen.items():
            for fmt in ("workflow", "matrix", "json", "dag"):
                cases.append(
                    Case(
                        f"{name} --format={fmt}",
                        dict(pins, **unit_dir(units)),
                        ["--units-dir=units", f"--format={fmt}"],
                        env,
                    )
                )
        self.check(cases)

    def test_json_decoding(self):
        env = {"BUILD_WORKSPACE_DIRECTORY": SCRATCH}
        docs = [
            '{"schema":"x"}',
            '{"schema":1.5}',
            '{"schema":1e0}',
            '{"schema":99999999999999999999}',
            '{"schema":-1}',
            '{"schema":true}',
            '{"schema":[1]}',
            '{"schema":{}}',
            "null",
            "[]",
            '"x"',
            "1",
            "true",
            '{"schema":1,"name":"a","test_targets":["x"],"env":{"a":1}}',
            '{"schema":1,"name":"a","test_targets":["x",2]}',
            '{"schema":1,"name":{"a":1},"test_targets":["x"]}',
            '{"schema":1,"name":"a","test_targets":"x"}',
            '{"schema":1,"name":"a","test_targets":["x"],"env":[1]}',
            '{"schema":1,"name":"a","test_targets":["x"],"needs_emulator":1}',
            '{"schema":1,"name":"a","test_targets":["x"],"needs_emulator":true}',
            '{"schema":1,"name":"a","test_targets":["x"],"tags":[1]}',
            '{"schema":1,"name":"a","test_targets":null}',
            '{"schema":1,"name":"a","test_targets":["x"],"depends_on":null,"env":null}',
            '{"ſchema":1,"NAME":"a","Test_Targets":["x"],"env":{"b":null},"artifacts":{"x":"y"},"artifacts":{"z":"w"}}',
            '{"schema":1,"name":"a","test_targets":["x","y","z"],"test_targets":[null,"q"]}',
            '{"schema":1,"name":"a","test_targets":["x","y"],"test_targets":[],"test_targets":[null]}',
            '{"schema":1,"name":"a","name":"b","test_targets":["x"],"unknown":{"deep":[1,{"a":null}]}}',
            '{"schema":1,"name":"\\u00e9\\ud83d\\ude00\\ud800x\\/\\b\\f\\n\\r\\t\\"\\\\","test_targets":["x"]}',
            '{"schema":1,"name":"\\udc00\\ud800\\u0041","test_targets":["x"]}',
            "",
            "  ",
            '{"a" 1}',
            '{"a":1 "b"}',
            "[1 2]",
            "tru",
            "fals",
            "nul",
            "nulx",
            "trux",
            '{"a":"\\q"}',
            '{"a":"\\u12g4"}',
            "-",
            "1.",
            "1e",
            "1e+",
            "{,",
            '{"a":1,}',
            "01",
            "{} x",
            '{"a":"\x01"}',
            "{'a':1}",
            '{"a":-x}',
            "[",
            '{"a":',
            '{"a":[}',
            "[1,]",
            "﻿{}",
            '{"a":1}}',
            "[" * 10001 + "]" * 10001,
        ]
        cases = []
        for i, d in enumerate(docs):
            cases.append(
                Case(
                    f"json doc {i}: {d[:60]!r}",
                    {"units/u.pipeline.json": d},
                    ["--units-dir=units", "--format=json"],
                    env,
                )
            )
        raw = [
            b'{"schema":1,"name":"a\xffb\xc3","test_targets":["x"]}',
            b'{"schema":1,"name":"\xe2\x82","test_targets":["x"]}',
            b"\xff",
            b'{"\xff":1}',
        ]
        for i, d in enumerate(raw):
            cases.append(
                Case(
                    f"json raw bytes {i}",
                    {"units/u.pipeline.json": d},
                    ["--units-dir=units", "--format=json"],
                    env,
                )
            )
        self.check(cases)

    # ---- BUILD-file discovery (the default mode) ------------------------

    def test_build_discovery(self):
        pins = {".github/actions/pins/action.yml": pins_text()}
        env = {"BUILD_WORKSPACE_DIRECTORY": SCRATCH}
        unit = lambda body: (
            'load("//tools/pipeline:defs.bzl", "pipeline_unit")\n\npipeline_unit(\n'
            + body
            + ")\n"
        )
        trees = {
            "artifacts from BUILD content": {
                "apps/mobile/android-remote/BUILD": unit(
                    '    name = "remote",\n    artifacts = {"android-remote-apk": "bazel-bin/apps/mobile/android-remote/app.apk"},\n'
                    '    persona = "frontend",\n    runner = "ubuntu-26.04",\n    test_targets = [\n        ":app",\n        ":lib",\n    ],\n'
                    '    tier = "L1",\n    timeout_minutes = 30,\n'
                )
            },
            "no artifacts": {
                "pkg/BUILD": unit(
                    '    name = "plain",\n    test_targets = [":lib"],\n    tier = "L1",\n'
                )
            },
            "build flags": {
                "pkg/BUILD": unit(
                    '    name = "remote",\n    artifacts = {"apk": "bazel-bin/app.apk"},\n'
                    '    build_flags = ["--fat_apk_cpu=arm64-v8a,x86_64"],\n    test_targets = [":app"],\n    tier = "L1",\n'
                )
            },
            "parentheses in comments": {
                "pkg/BUILD": unit(
                    '    name = "remote",\n    # NDK 29.0.14206865 (the version installed when this landed) decides ABIs.\n'
                    '    artifacts = {"apk": "apps/x/app.apk"},\n    test_targets = [\n        ":app",\n        ":lib",\n    ],\n    tier = "L1",\n'
                )
            },
            "hash inside strings": {
                "pkg/BUILD": unit(
                    '    name = "u",\n    env = {"REF": "main#head"},\n    test_targets = [":t"],\n    tier = "L1",\n'
                )
            },
            "env": {
                "pkg/BUILD": unit(
                    '    name = "remote",\n    env = {"ANDROID_NDK_HOME": "${{ env.ANDROID_NDK_ROOT }}"},\n    test_targets = [":app"],\n    tier = "L1",\n'
                )
            },
            "root package, BUILD.bazel, nested and deps": {
                "BUILD.bazel": unit(
                    '    name = "root",\n    test_targets = [":t", "//x:y"],\n'
                ),
                "a/b/c/BUILD": unit(
                    '    name = "deep",\n    test_targets = [":t"],\n    depends_on = ["root"],\n    needs_emulator = False,\n'
                ),
                "a/BUILD": 'pipeline_unit(name = \'single\', test_targets = [r\'//raw\\path\', b"""tri\nple""", "esc\\n\\t\\q\\\n"], runner = "xcode-27",)\n',
            },
            "skipped directories": {
                ".git/BUILD": unit('    name = "git",\n'),
                "node_modules/x/BUILD": unit('    name = "nm",\n'),
                ".claude/BUILD": unit('    name = "cl",\n'),
                "bazel-out/BUILD": unit('    name = "bo",\n'),
                "tools/bazel-cache/BUILD": unit(
                    '    name = "kept",\n    test_targets = [":t"],\n'
                ),
                "BUILD.txt": unit('    name = "nope",\n'),
            },
            "not calls": {
                "p/BUILD": "def pipeline_unit(name):\n    pass\nx.pipeline_unit(name = 1)\n# pipeline_unit(\n'pipeline_unit('\n"
            },
            "duplicate across files": {
                "a/BUILD": unit('    name = "dup",\n    test_targets = [":t"],\n'),
                "b/BUILD": unit('    name = "dup",\n    test_targets = [":t"],\n'),
                "c/BUILD": unit(
                    '    name = "bad",\n    tier = 1,\n    test_targets = [":t"],\n'
                ),
            },
            "glob test_targets": {
                "p/BUILD": unit('    name = "u",\n    test_targets = glob(["*"]),\n')
            },
            "missing targets": {"p/BUILD": unit('    name = "u",\n')},
            "name not a string": {
                "p/BUILD": unit('    name = NAME,\n    test_targets = [":t"],\n')
            },
            "positional argument": {
                "p/BUILD": 'pipeline_unit("u", test_targets = [":t"])\n'
            },
            "star argument": {"p/BUILD": "pipeline_unit(**kw)\n"},
            "unclosed string": {"p/BUILD": unit('    name = "u",\n    tier = "L1\n')},
            "unclosed string unnamed": {
                "p/BUILD": "pipeline_unit(\n    tier = 'L1\n)\n"
            },
            "never closed triple string": {
                "p/BUILD": 'pipeline_unit(name = "u", tier = """abc' + "x" * 40 + "\n"
            },
            "unclosed prefixed string": {
                "p/BUILD": 'pipeline_unit(name = "u", tier = r"abc\n)\n'
            },
            "unclosed call": {
                "p/BUILD": 'pipeline_unit(\n    name = "u",\n    test_targets = [":t"],\n'
            },
            "mismatched bracket": {
                "p/BUILD": 'pipeline_unit(name = "u", test_targets = [":t"]]\n'
            },
            "stray closer": {
                "p/BUILD": 'x = 1)\npipeline_unit(name = "u", test_targets = [":t"])\n'
            },
            "bad tier": {
                "p/BUILD": unit(
                    '    name = "u",\n    tier = L1,\n    test_targets = [":t"],\n'
                )
            },
            "bad timeout": {
                "p/BUILD": unit(
                    '    name = "u",\n    timeout_minutes = "30",\n    test_targets = [":t"],\n'
                )
            },
            "bad timeout float": {
                "p/BUILD": unit(
                    '    name = "u",\n    timeout_minutes = 1.5,\n    test_targets = [":t"],\n'
                )
            },
            "bad emulator": {
                "p/BUILD": unit(
                    '    name = "u",\n    needs_emulator = 1,\n    test_targets = [":t"],\n'
                )
            },
            "bad list entry": {
                "p/BUILD": unit('    name = "u",\n    test_targets = [":t", TARGET],\n')
            },
            "concatenated list": {
                "p/BUILD": unit(
                    '    name = "u",\n    test_targets = [":a"] + [":b"],\n'
                )
            },
            "bad dict": {
                "p/BUILD": unit(
                    '    name = "u",\n    env = {"A": 1},\n    test_targets = [":t"],\n'
                )
            },
            "dict not literal": {
                "p/BUILD": unit(
                    '    name = "u",\n    artifacts = ARTS,\n    test_targets = [":t"],\n'
                )
            },
            "dict bad pair": {
                "p/BUILD": unit(
                    '    name = "u",\n    env = {"A": "b": "c"},\n    test_targets = [":t"],\n'
                )
            },
            "many errors": {
                f"p{i}/BUILD": unit(f'    name = "u{i}",\n') for i in range(5)
            },
            "dependency missing": {
                "p/BUILD": unit(
                    '    name = "u",\n    depends_on = ["ghost"],\n    test_targets = [":t"],\n'
                )
            },
            "line continuation and operators": {
                "p/BUILD": 'x = 1 \\\n  + 2\nif a == b: pass\npipeline_unit(\n  name = "u",  # )\n  test_targets = [":t",],\n  env = {"k": "v",},\n  timeout_minutes = 007,\n)\n'
            },
            "no units at all": {"p/BUILD": "cc_library(name = 'x')\n"},
            "invalid utf-8 in a clipped string": {
                "p/BUILD": b'pipeline_unit(name = "u", tier = "\xe2\x82\xac\xe2\x82\xac\xe2\x82\xac\xe2\x82\xac\xe2\x82\xac\xe2\x82\xac\xe2\x82\xac\xe2\x82\xac\xe2\x82\xac\xe2\x82\xac\n'
            },
        }
        cases = []
        for name, tree in trees.items():
            for fmt in ("workflow", "json"):
                cases.append(
                    Case(
                        f"discover {name} --format={fmt}",
                        dict(pins, **tree),
                        [f"--format={fmt}"],
                        env,
                    )
                )
        cases.append(
            Case(
                "discover with --repo-root, no BUILD_WORKSPACE_DIRECTORY",
                dict(pins, **trees["root package, BUILD.bazel, nested and deps"]),
                ["--repo-root", SCRATCH, "--format=dag"],
                {},
            )
        )
        cases.append(
            Case(
                "discover from cwd",
                dict(pins, **trees["env"]),
                ["--format=json"],
                {},
                cwd="pkg",
            )
        )
        cases.append(
            Case(
                "discover nonexistent repo root",
                pins,
                ["--repo-root", SCRATCH + "/nope", "--format=json"],
                env,
            )
        )
        cases.append(
            Case(
                "discover unclean repo root",
                dict(pins, **trees["skipped directories"]),
                ["--repo-root", SCRATCH + "/./", "--format=json"],
                env,
            )
        )

        def unreadable(root):
            os.chmod(os.path.join(root, "p", "BUILD"), 0)

        def unlistable(root):
            os.chmod(os.path.join(root, "q"), 0)

        if os.geteuid() != 0:
            cases.append(
                Case(
                    "discover unreadable BUILD",
                    dict(pins, **{"p/BUILD": "x"}),
                    ["--format=json"],
                    env,
                    setup=unreadable,
                )
            )
            cases.append(
                Case(
                    "discover unlistable directory",
                    dict(pins, **{"q/BUILD": unit('    name = "q",\n')}),
                    ["--format=json"],
                    env,
                    setup=unlistable,
                )
            )
        self.check(cases)

    # ---- flags ------------------------------------------------------------

    def test_flags(self):
        files = dict(self.fixture_files())
        env = {"BUILD_WORKSPACE_DIRECTORY": SCRATCH}
        arg_sets = [
            ["-h"],
            ["-help"],
            ["--help"],
            ["-x"],
            ["--nope=1"],
            ["-format"],
            ["--units-dir"],
            ["-check=maybe"],
            ["---x"],
            ["-=x"],
            ["--units-dir=units", "--", "-x"],
            ["--units-dir=units", "positional", "-x"],
            ["-units-dir", "units", "-format", "dag", "-tier", "L1"],
            ["--units-dir=units", "--format=dag", "--format=json"],
            ["--units-dir=units", "-check", "-check=0"],
            ["--units-dir=units", "-"],
            ["--units-dir=units", "--check=T", "--output-file=x.yaml"],
        ]
        cases = [Case(f"flags {a}", files, a, env) for a in arg_sets]
        self.check(cases)

    def test_units_dir_edge_cases(self):
        env = {"BUILD_WORKSPACE_DIRECTORY": SCRATCH}
        pins = {".github/actions/pins/action.yml": pins_text()}
        cases = [
            Case(
                "units-dir missing", pins, ["--units-dir=absent", "--format=json"], env
            ),
            Case(
                "units-dir missing workflow",
                pins,
                ["--units-dir=absent", "--format=workflow"],
                env,
            ),
            Case(
                "units-dir empty matrix",
                dict(pins, **{"u/": None}),
                ["--units-dir=u"],
                env,
            ),
            Case(
                "units-dir plain .json fallback",
                dict(
                    pins,
                    **{
                        "u/b.json": unit_json("b"),
                        "u/a.json": unit_json("a"),
                        "u/c.txt": "x",
                        "u/sub/d.json": unit_json("d"),
                    },
                ),
                ["--units-dir=u", "--format=json"],
                env,
            ),
            Case(
                "units-dir json fallback is a directory",
                dict(pins, **{"u/x.json/": None}),
                ["--units-dir=u"],
                env,
            ),
            Case(
                "units-dir nested and skipped",
                dict(
                    pins,
                    **{
                        "u/a/x.pipeline.json": unit_json("x"),
                        "u/node_modules/y.pipeline.json": unit_json("y"),
                        "u/.git/z.pipeline.json": unit_json("z"),
                        "u/bazel-out/w.pipeline.json": unit_json("w"),
                        "u/b/bazel-bin/v.pipeline.json": unit_json("v"),
                        "u/c/q.pipeline.json.bak": "x",
                    },
                ),
                ["--units-dir=u", "--format=dag"],
                env,
            ),
            Case(
                "units-dir is a file",
                dict(pins, **{"u.pipeline.json": unit_json("solo")}),
                ["--units-dir=u.pipeline.json", "--format=json"],
                env,
            ),
            Case(
                "units-dir unit is a directory",
                dict(
                    pins,
                    **{"u/d.pipeline.json/": None, "u/a.pipeline.json": unit_json("a")},
                ),
                ["--units-dir=u", "--format=json"],
                env,
            ),
            Case(
                "units-dir unclean absolute",
                dict(pins, **{"u/a.pipeline.json": unit_json("a")}),
                ["--units-dir", SCRATCH + "/u/../u/", "--format=json"],
                env,
            ),
            Case(
                "output-file parent is a file",
                dict(pins, **{"u/a.pipeline.json": unit_json("a"), "f": "x"}),
                ["--units-dir=u", "--output-file=f/out.json", "--format=json"],
                env,
            ),
            Case(
                "output-file is a directory",
                dict(pins, **{"u/a.pipeline.json": unit_json("a"), "d/": None}),
                ["--units-dir=u", "--output-file=d", "--format=json"],
                env,
            ),
            Case(
                "check output-file is a directory",
                dict(pins, **{"u/a.pipeline.json": unit_json("a"), "d/": None}),
                ["--units-dir=u", "--output-file=d", "--format=json", "--check"],
                env,
            ),
        ]
        if os.geteuid() != 0:

            def unreadable(root):
                os.chmod(os.path.join(root, "u", "a.pipeline.json"), 0)

            cases.append(
                Case(
                    "units-dir unreadable unit",
                    dict(pins, **{"u/a.pipeline.json": unit_json("a")}),
                    ["--units-dir=u", "--format=json"],
                    env,
                    setup=unreadable,
                )
            )
        self.check(cases)

    # ---- the pin manifest ---------------------------------------------------

    def test_pins(self):
        units = unit_dir({"a": unit_json("a", artifacts={"x": "y"})})
        args = ["--units-dir=units", "--format=workflow"]
        env = {"BUILD_WORKSPACE_DIRECTORY": SCRATCH}
        variants = {
            "crlf": pins_text(sep="\r\n"),
            "no comments": "".join(f"uses: {a}@{SHA}\n" for a in PINNED),
            "comment spacing": "".join(
                f"  -   uses:   {a}@{SHA}#   v1.2.3  extra  \n" for a in PINNED
            ),
            "trailing space is not a pin": pins_text()
            + f"uses: actions/other@{SHA} \n",
            "no final newline": pins_text().rstrip("\n"),
            "invalid sha": pins_text() + "      - uses: actions/bad@v4 # v4\n",
            "uppercase sha": pins_text() + f"uses: actions/up@{SHA.upper()}\n",
            "duplicate": pins_text() + f"uses: actions/checkout@{SHA}\n",
            "zero pins": "name: pins\nruns:\n  using: composite\n",
            "empty": "",
            "unpinned action": pins_text(actions=PINNED[:1]),
            "unpinned upload": pins_text(actions=PINNED[:4]),
            "too long line": pins_text() + "#" * 70000 + "\n",
            "local uses ignored": pins_text() + "uses: ./.github/actions/x\n",
        }
        cases = [
            Case(
                f"pins {n}",
                dict(units, **{".github/actions/pins/action.yml": body}),
                args,
                env,
            )
            for n, body in variants.items()
        ]
        cases += [
            Case(
                "pins manifest missing (panic)",
                units,
                args,
                {"BUILD_WORKSPACE_DIRECTORY": None},
                base_env=False,
            ),
            Case(
                "pins manifest is a directory",
                dict(units, **{".github/actions/pins/action.yml/": None}),
                args,
                env,
            ),
            Case(
                "pins found by walking up from cwd",
                dict(
                    units,
                    **{
                        "sub/dir/": None,
                        ".github/actions/pins/action.yml": pins_text(),
                    },
                ),
                ["--units-dir", SCRATCH + "/units", "--format=workflow"],
                {},
                cwd="sub/dir",
                base_env=False,
            ),
            Case(
                "pins via TEST_SRCDIR/TEST_WORKSPACE",
                dict(units, **{"rf/ws/.github/actions/pins/action.yml": pins_text()}),
                args + ["--repo-root", SCRATCH],
                {"TEST_SRCDIR": SCRATCH + "/rf", "TEST_WORKSPACE": "ws"},
                base_env=False,
            ),
            Case(
                "pins via TEST_SRCDIR root",
                dict(units, **{"rf/.github/actions/pins/action.yml": pins_text()}),
                args + ["--repo-root", SCRATCH],
                {"TEST_SRCDIR": SCRATCH + "/rf"},
                base_env=False,
            ),
            Case(
                "matrix needs no pins", units, ["--units-dir=units"], {}, base_env=False
            ),
            Case(
                "DAG error before pins",
                unit_dir({"a": unit_json("a", depends_on=["z"])}),
                args,
                {},
                base_env=False,
            ),
        ]
        self.check(cases)

    @classmethod
    def tearDownClass(cls):
        print(f"gen parity: {cls.cases_run} cases compared", file=sys.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
