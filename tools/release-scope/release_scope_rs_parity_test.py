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
"""release_scope_rs, the Rust port, against release_scope.py: same exit code,
same stdout, same stderr, byte for byte, on every input here.

    bazel test //tools/release-scope:release_scope_rs_parity_test

Both run as programs, the way the workflow runs the script, each from a
folder of its own with aliases.json beside it and under the name
release_scope.py (so argparse's usage line reads the same). The inputs:

  * every case in release_scope_test.py. Its tests call the script's
    functions; each call to judge, main, messages and squash_message is
    recorded with its inputs and replayed through both command lines;
  * every pull request in testdata/, against the configs of 13 October 2026
    and against the SDK's config as it is now;
  * inputs built to break them: JSON that does not parse, files that are not
    UTF-8, values of the wrong type, lone surrogates, unusual command lines
    and terminal widths, odd trees of configs, and commit messages generated
    from the pieces the parser looks for.

When Python crashes (an uncaught exception), its traceback names its own
files and lines, which the port cannot have, so there the last line, the
exception, is compared.
"""

import contextlib
import copy
import io
import json
import os
import random
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import gen_unicode_tables  # noqa: E402
import release_scope as rs  # noqa: E402
import release_scope_test as rst  # noqa: E402

SDK, TOOL, APP = rst.SDK, rst.TOOL, rst.APP
TRACEBACK = b"Traceback (most recent call last):"


def _binary():
    path = os.environ.get("RELEASE_SCOPE_RS", "")
    if not path:
        raise unittest.SkipTest(
            "RELEASE_SCOPE_RS is not set; run this under bazel test"
        )
    return os.path.abspath(path)


def fixture(name):
    with open(os.path.join(HERE, "testdata", name), encoding="utf-8") as handle:
        return json.load(handle)


class Harness:
    """Two copies of the check, and the inputs to run them on."""

    def __init__(self):
        self.tmp = tempfile.mkdtemp(prefix="release-scope-parity-")
        self.dirs = {}
        for kind in ("py", "rs"):
            sub = os.path.join(self.tmp, kind, "sub")
            os.makedirs(sub)
            shutil.copy(os.path.join(HERE, "aliases.json"), sub)
            self.dirs[kind] = os.path.join(self.tmp, kind)
        shutil.copy(
            os.path.join(HERE, "release_scope.py"), os.path.join(self.dirs["py"], "sub")
        )
        program = os.path.join(self.dirs["rs"], "sub", "release_scope.py")
        shutil.copy(_binary(), program)
        os.chmod(program, 0o755)
        self.count = 0

    def case_dir(self):
        self.count += 1
        path = os.path.join(self.tmp, "cases", str(self.count))
        os.makedirs(path)
        return path

    def run(self, kind, args, env, timeout=60):
        if kind == "py":
            argv = [sys.executable, "sub/release_scope.py"] + args
        else:
            argv = ["sub/release_scope.py"] + args
        proc = subprocess.run(
            argv, cwd=self.dirs[kind], env=env, capture_output=True, timeout=timeout
        )
        out, err = proc.stdout, proc.stderr
        for d in self.dirs.values():
            out = out.replace(d.encode(), b"<HERE>")
            err = err.replace(d.encode(), b"<HERE>")
        return proc.returncode, out, err


def base_env(extra=None):
    env = {k: v for k, v in os.environ.items() if k not in ("COLUMNS", "LINES")}
    env.update(extra or {})
    return env


def same(py, rs_):
    """None when the two runs agree, else what differs."""
    if py[0] != rs_[0]:
        return f"exit {py[0]} (python) != {rs_[0]} (rust)"
    if py[1] != rs_[1]:
        return f"stdout differs:\n--- python\n{py[1]!r}\n--- rust\n{rs_[1]!r}"
    if py[2].startswith(TRACEBACK):
        last = lambda e: e.rstrip(b"\n").split(b"\n")[-1]  # noqa: E731
        if not rs_[2].startswith(TRACEBACK) or last(py[2]) != last(rs_[2]):
            return f"crash differs:\n--- python\n{py[2]!r}\n--- rust\n{rs_[2]!r}"
        return None
    if py[2] != rs_[2]:
        return f"stderr differs:\n--- python\n{py[2]!r}\n--- rust\n{rs_[2]!r}"
    return None


def write(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if isinstance(data, bytes):
        with open(path, "wb") as handle:
            handle.write(data)
    else:
        with open(path, "w", encoding="utf-8", newline="") as handle:
            handle.write(data)


MISSING = object()
# Most cases' configs have none of the products aliases.json names.
NO_ALIASES = {"aliases": {}}


class Case:
    """One command line, its files, and the environments to run it in."""

    def __init__(
        self,
        harness,
        name,
        pr=MISSING,
        commits=MISSING,
        files=None,
        configs=None,
        aliases=NO_ALIASES,
        raw=None,
        argv=None,
        envs=None,
    ):
        self.name = name
        self.dir = harness.case_dir()
        raw = dict(raw or {})
        for key, value in (
            ("pr.json", pr),
            ("commits.json", commits),
            ("aliases.json", aliases),
        ):
            if value is not MISSING and key not in raw:
                raw[key] = json.dumps(value)
        if files is not None and "files.txt" not in raw:
            raw["files.txt"] = "".join(f + "\n" for f in files)
        for key, value in raw.items():
            write(os.path.join(self.dir, key), value)
        root = os.path.join(self.dir, "root")
        os.makedirs(root, exist_ok=True)
        for where, value in (configs or {}).items():
            # bytes are a file as written; anything else is its JSON.
            write(
                os.path.join(root, where),
                value if isinstance(value, bytes) else json.dumps(value),
            )
        p = lambda n: os.path.join(self.dir, n)  # noqa: E731
        if argv is None:
            argv = [
                "--pr-json",
                p("pr.json"),
                "--commits-json",
                p("commits.json"),
                "--files",
                p("files.txt"),
                "--repo-root",
                root,
            ]
            if "aliases.json" in raw:
                argv += ["--aliases", p("aliases.json")]
        self.argv = [a.replace("{DIR}", self.dir) for a in argv]
        self.envs = envs or [{}]
        # Moves aliases.json away from both programs while this case runs.
        self.hide_aliases = False


def pr_object(pull):
    return {
        "title": pull.title,
        "body": pull.body,
        "user": {"login": pull.author, "type": pull.author_type},
        "head": {"ref": pull.head_ref},
    }


def aliases_object(aliases):
    return {"aliases": {scope: {"components": list(t)} for scope, t in aliases.items()}}


def record_unit_tests():
    """Runs release_scope_test.py, recording what each test asks the script."""
    calls = []
    configs_of = {}
    real = {
        name: getattr(rs, name)
        for name in ("load_components", "judge", "main", "messages", "squash_message")
    }
    snapshots = tempfile.mkdtemp(prefix="release-scope-recorded-")

    def load_components(configs):
        components = real["load_components"](configs)
        configs_of[id(components)] = copy.deepcopy(configs)
        return components

    def judge(pull, components, aliases):
        calls.append(
            (
                "judge",
                copy.deepcopy(pull),
                copy.deepcopy(configs_of[id(components)]),
                copy.deepcopy(aliases),
            )
        )
        return real["judge"](pull, components, aliases)

    def main(argv: list[str]):
        # Its files are temporary; keep a copy of each for the replay.
        keep = os.path.join(snapshots, str(len(calls)))
        os.makedirs(keep)
        argv = list(argv)
        for i, arg in enumerate(argv[:-1]):
            if argv[i].startswith("--"):
                source = argv[i + 1]
                target = os.path.join(keep, argv[i].lstrip("-"))
                if os.path.isdir(source):
                    shutil.copytree(source, target, symlinks=True)
                elif os.path.exists(source):
                    shutil.copy(source, target)
                else:
                    continue
                argv[i + 1] = target
        calls.append(("main", argv))
        return real["main"](argv)

    def messages(message):
        calls.append(("messages", message))
        return real["messages"](message)

    def squash_message(pull):
        calls.append(("squash_message", copy.deepcopy(pull)))
        return real["squash_message"](pull)

    for name, fn in (
        ("load_components", load_components),
        ("judge", judge),
        ("main", main),
        ("messages", messages),
        ("squash_message", squash_message),
    ):
        setattr(rs, name, fn)
    try:
        suite = unittest.defaultTestLoader.loadTestsFromModule(rst)
        result = unittest.TestResult()
        with (
            contextlib.redirect_stdout(io.StringIO()),
            contextlib.redirect_stderr(io.StringIO()),
        ):
            suite.run(result)
    finally:
        for name, fn in real.items():
            setattr(rs, name, fn)
    return result, calls


ALL_FILES = [
    f"{SDK}/BUILD",
    f"{TOOL}/a",
    f"{APP}/a",
    "apps/mcp/slack/a",
    f"{SDK}/consumers/x",
]


def unit_cases(h, calls):
    cases = []
    for i, call in enumerate(calls):
        kind = call[0]
        if kind == "judge":
            _, pull, configs, aliases = call
            cases.append(
                Case(
                    h,
                    f"unit judge #{i}: {pull.title!r}",
                    pr=pr_object(pull),
                    commits=pull.commits,
                    files=pull.files,
                    configs=configs,
                    aliases=aliases_object(aliases),
                )
            )
        elif kind == "main":
            cases.append(Case(h, f"unit main #{i}", argv=call[1]))
        elif kind in ("messages", "squash_message"):
            if kind == "messages":
                pr, commits = {"title": "x", "body": ""}, [call[1]]
            else:
                pull = call[1]
                pr, commits = pr_object(pull), pull.commits
            cases.append(
                Case(
                    h,
                    f"unit {kind} #{i}",
                    pr=pr,
                    commits=commits,
                    files=ALL_FILES,
                    configs=rst.CONFIGS,
                    aliases=aliases_object(rst.ALIASES),
                )
            )
    return cases


def fixture_cases(h):
    cases = []
    before = fixture("configs-2026-10-13.json")
    with open(
        os.path.join(rst.ROOT, SDK, "release-please-config.json"), encoding="utf-8"
    ) as handle:
        live = dict(before, **{f"{SDK}/release-please-config.json": json.load(handle)})
    for name in sorted(os.listdir(os.path.join(HERE, "testdata"))):
        if not name.startswith("pr-"):
            continue
        data = fixture(name)
        for label, configs in (("13 October", before), ("now", live)):
            cases.append(
                Case(
                    h,
                    f"{name} against {label}",
                    pr=data["pull_request"],
                    commits=data["commits"],
                    files=data["files"],
                    configs=configs,
                    aliases=rst.read_aliases(),
                )
            )
            # And with the default aliases.json, the one beside the program.
            case = Case(
                h,
                f"{name} against {label}, default aliases",
                pr=data["pull_request"],
                commits=data["commits"],
                files=data["files"],
                configs=configs,
                aliases=MISSING,
            )
            cases.append(case)
    return cases


def baseline(number=3209):
    data = fixture(f"pr-{number}.json")
    return data["pull_request"], data["commits"], data["files"]


SMALL = {
    "a/release-please-config.json": {"packages": {"a": {"component": "alpha"}}},
    "b/release-please-config.json": {
        "packages": {"b": {"component": "beta", "package-name": "@x/beta"}}
    },
}
SMALL_FILES = ["a/x", "b/y"]


def broken_json_texts(rng):
    texts = [
        "",
        " ",
        "{",
        "}",
        "[",
        "]",
        "[1,]",
        '{"a" 1}',
        '{"a":1,}',
        '{"a":1 "b":2}',
        "[1 2]",
        '"\\u12"',
        '"\\u12345"',
        '"\\u12x4"',
        '"\\ud800\\u0041"',
        '"\\ud800\\uzzzz"',
        '"\\ud800\\udc00"',
        '"\\x"',
        '"a\x01b"',
        '"ab',
        '"ab\\',
        "﻿{}",
        "{}\r\n x",
        "{}\r x",
        "{}\n\n  x",
        "NaN",
        "-Infinity",
        "Infinity",
        "nul",
        "tru",
        "fals",
        "1e",
        "1e+",
        "1.",
        "1.e5",
        "-",
        "-x",
        "01",
        "00",
        "-0",
        "1" * 4300,
        "1" * 4301,
        "-" + "1" * 4301,
        "1." + "1" * 5000,
        "[" * 9997 + "]" * 9997,
        "[" * 9998 + "]" * 9998,
        '{"a":' * 9998 + "1" + "}" * 9998,
        "[" * 9997 + "{}" + "]" * 9997,
        "\t\n\r [1, 2] ",
        '{"a": [1, {"b": "\\n"}]}',
        "[1]]",
        '{"\\ud83d\\ude00": 1}',
        "\x00",
        "[\n\n\n1,\n2,\n]",
    ]
    valid = json.dumps(fixture("pr-3209.json"), indent=1)
    for _ in range(12):
        texts.append(valid[: rng.randrange(len(valid))])
    for _ in range(8):
        pos = rng.randrange(len(valid))
        texts.append(
            valid[:pos]
            + rng.choice(['"', ",", "]", "}", "\\", "\x02", "x", ":"])
            + valid[pos + 1 :]
        )
    return texts


def json_cases(h, rng):
    pr, commits, files = baseline()
    configs = fixture("configs-2026-10-13.json")
    cases = []
    for i, text in enumerate(broken_json_texts(rng)):
        raw = text.encode("utf-8", "surrogatepass")
        cases.append(
            Case(
                h,
                f"pr.json #{i} {text[:30]!r}",
                raw={"pr.json": raw},
                commits=commits,
                files=files,
                configs=configs,
            )
        )
        if i % 3 == 0:
            cases.append(
                Case(
                    h,
                    f"commits.json #{i}",
                    pr=pr,
                    raw={"commits.json": raw},
                    files=files,
                    configs=configs,
                )
            )
            cases.append(
                Case(
                    h,
                    f"aliases.json #{i}",
                    pr=pr,
                    commits=commits,
                    files=files,
                    configs=configs,
                    raw={"aliases.json": raw},
                )
            )
            broken = dict(configs)
            broken["apps/cli/devx/release-please-config.json"] = raw
            cases.append(
                Case(
                    h,
                    f"config #{i}",
                    pr=pr,
                    commits=commits,
                    files=files,
                    configs=broken,
                )
            )
    return cases


def encoding_cases(h):
    pr, commits, files = baseline()
    configs = fixture("configs-2026-10-13.json")
    body = "\n".join(files).encode() + b"\n"
    texts = {
        "invalid start": b"apps/x\xff\n" + body,
        "at a chunk edge": b"a" * 8192 + b"\xff\n" + body,
        "past a chunk": b"a" * 9000 + b"\xff\n" + body,
        # Positions no smaller chunk size would give: 4096 does not divide them.
        "inside the first chunk": b"a" * 5000 + b"\xff\n" + body,
        "inside the second chunk": b"a" * 12000 + b"\xff\n" + body,
        "split at 4096": b"a" * 4094 + b"\xe2\x82A\n" + body,
        "split at 16384": b"a" * 16382 + b"\xe2\x82A\n" + body,
        "split across chunks": b"a" * 8190 + b"\xe2\x82A\n" + body,
        "truncated at the end": body + b"\xe2\x82",
        "truncated at a chunk end": b"a" * 8191 + b"\xe2\x82",
        "surrogate bytes": body + b"\xed\xa0\x80\n",
        "overlong": body + b"\xc0\xaf\n",
        "four byte bad": body + b"\xf0\x90\x28\xbc\n",
        "f4 high": body + b"\xf4\x90\x80\x80\n",
        "bom": b"\xef\xbb\xbf" + body,
        "crlf": body.replace(b"\n", b"\r\n"),
        "cr": body.replace(b"\n", b"\r"),
        "unicode spaces": "　 ".encode()
        + body.replace(b"\n", " \n\x0b".encode())
        + " \n\x1c\n".encode(),
        "empty": b"",
        "blank lines": b"\n\n  \n\t\n" + body,
    }
    cases = [
        Case(
            h,
            f"files.txt {k}",
            pr=pr,
            commits=commits,
            raw={"files.txt": v},
            configs=configs,
        )
        for k, v in texts.items()
    ]
    pr_text = json.dumps(pr).encode()
    for k, v in {
        "pr bad byte": pr_text[:40] + b"\xff" + pr_text[40:],
        "pr truncated": pr_text + b"\xe2",
        "pr bom": b"\xef\xbb\xbf" + pr_text,
        "pr crlf": json.dumps(pr, indent=1).encode().replace(b"\n", b"\r\n") + b"x",
    }.items():
        cases.append(
            Case(
                h, k, raw={"pr.json": v}, commits=commits, files=files, configs=configs
            )
        )
    broken = dict(configs)
    broken["apps/cli/devx/release-please-config.json"] = b"\xef\xbb\xbf{}"
    cases.append(
        Case(h, "config bom", pr=pr, commits=commits, files=files, configs=broken)
    )
    broken = dict(configs)
    broken["apps/cli/devx/release-please-config.json"] = b'{"packages": "\xff"}'
    cases.append(
        Case(h, "config bad byte", pr=pr, commits=commits, files=files, configs=broken)
    )
    return cases


def config_with(package=None, config=None):
    value = {
        "packages": {"a": package if package is not None else {"component": "alpha"}}
    }
    value.update(config or {})
    return value


def type_cases(h):
    pr, commits, files = baseline()
    cases = []
    two = ["one", "two"]
    for label, value in [
        ("list", []),
        ("str", "x"),
        ("int", 1),
        ("null", None),
        ("float", 1.5),
        ("bool", True),
    ]:
        cases.append(
            Case(
                h,
                f"pr is {label}",
                pr=value,
                commits=commits,
                files=files,
                configs=SMALL,
            )
        )
        cases.append(
            Case(
                h,
                f"commits are {label}",
                pr=pr,
                commits=value,
                files=files,
                configs=SMALL,
            )
        )
        cases.append(
            Case(
                h,
                f"aliases are {label}",
                pr=pr,
                commits=commits,
                files=files,
                configs=SMALL,
                aliases=value,
            )
        )
        cases.append(
            Case(
                h,
                f"config is {label}",
                pr=pr,
                commits=commits,
                files=files,
                configs={"a/release-please-config.json": value},
            )
        )
    weird = [
        5,
        1.5e300,
        -0.0,
        True,
        [1, "a"],
        {"k": [None, 2.5, 1e16, 1e-5]},
        "",
        None,
        False,
        0,
        [],
        {},
        float("nan"),
        float("inf"),
        10**30,
        "\U0001f600x",
        'it\'s "q"',
    ]
    for value in weird:
        name = repr(value)[:40]
        for title_commits in (two, [], ["fix: one"]):
            cases.append(
                Case(
                    h,
                    f"title {name} with {len(title_commits)} commits",
                    pr=dict(pr, title=value),
                    commits=title_commits,
                    files=SMALL_FILES,
                    configs=SMALL,
                )
            )
        cases.append(
            Case(
                h,
                f"body {name}",
                pr=dict(pr, body=value),
                commits=two,
                files=SMALL_FILES,
                configs=SMALL,
            )
        )
        cases.append(
            Case(
                h,
                f"user {name}",
                pr=dict(pr, user=value),
                commits=two,
                files=SMALL_FILES,
                configs=SMALL,
            )
        )
        cases.append(
            Case(
                h,
                f"login {name}",
                pr=dict(
                    pr,
                    user={"login": value, "type": "Bot"},
                    head={"ref": "dependabot/x"},
                ),
                commits=two,
                files=SMALL_FILES,
                configs=SMALL,
            )
        )
        cases.append(
            Case(
                h,
                f"head {name}",
                pr=dict(pr, head=value),
                commits=two,
                files=SMALL_FILES,
                configs=SMALL,
            )
        )
        cases.append(
            Case(
                h,
                f"ref {name}",
                pr=dict(pr, head={"ref": value}),
                commits=two,
                files=SMALL_FILES,
                configs=SMALL,
            )
        )
        cases.append(
            Case(
                h,
                f"commit {name}",
                pr=pr,
                commits=[value],
                files=SMALL_FILES,
                configs=SMALL,
            )
        )
        cases.append(
            Case(
                h,
                f"commits [x, {name}]",
                pr=pr,
                commits=["fix: x", value],
                files=SMALL_FILES,
                configs=SMALL,
            )
        )
        for key in ("component", "package-name", "exclude-paths", "changelog-sections"):
            package = (
                {"component": "alpha", key: value}
                if key != "component"
                else {key: value}
            )
            configs = dict(
                SMALL, **{"a/release-please-config.json": config_with(package)}
            )
            cases.append(
                Case(
                    h,
                    f"{key} {name}",
                    pr=dict(pr, title="fix(beta): x"),
                    commits=two,
                    files=SMALL_FILES,
                    configs=configs,
                )
            )
        cases.append(
            Case(
                h,
                f"package {name}",
                pr=pr,
                commits=two,
                files=SMALL_FILES,
                configs={"a/release-please-config.json": {"packages": {"a": value}}},
            )
        )
        cases.append(
            Case(
                h,
                f"packages {name}",
                pr=pr,
                commits=two,
                files=SMALL_FILES,
                configs={"a/release-please-config.json": {"packages": value}},
            )
        )
        cases.append(
            Case(
                h,
                f"config changelog-sections {name}",
                pr=pr,
                commits=two,
                files=SMALL_FILES,
                configs={
                    "a/release-please-config.json": config_with(
                        config={"changelog-sections": value}
                    )
                },
            )
        )
        cases.append(
            Case(
                h,
                f"section {name}",
                pr=pr,
                commits=two,
                files=SMALL_FILES,
                configs={
                    "a/release-please-config.json": config_with(
                        {"component": "a", "changelog-sections": [value]}
                    )
                },
            )
        )
        cases.append(
            Case(
                h,
                f"section type {name}",
                pr=pr,
                commits=two,
                files=SMALL_FILES,
                configs={
                    "a/release-please-config.json": config_with(
                        {"component": "a", "changelog-sections": [{"type": value}]}
                    )
                },
            )
        )
        cases.append(
            Case(
                h,
                f"section hidden {name}",
                pr=dict(pr, title="fix: x"),
                commits=two,
                files=SMALL_FILES,
                configs={
                    "a/release-please-config.json": config_with(
                        {
                            "component": "a",
                            "changelog-sections": [{"type": "fix", "hidden": value}],
                        }
                    )
                },
            )
        )
        for shape in (
            {"aliases": value},
            {"aliases": {"x": value}},
            {"aliases": {"x": {"components": value}}},
            {"aliases": {"x": {"components": [value]}}},
        ):
            cases.append(
                Case(
                    h,
                    f"aliases {json.dumps(shape)[:50]}",
                    pr=pr,
                    commits=two,
                    files=SMALL_FILES,
                    configs=SMALL,
                    aliases=shape,
                )
            )
    # Names: repeated, of other types, in an order that must be sorted.
    many = {
        f"p{i}/release-please-config.json": {"packages": {f"p{i}": {"component": n}}}
        for i, n in enumerate(["b", 3, "a", 1.5, True, "c"])
    }
    cases.append(
        Case(
            h, "names of mixed types", pr=pr, commits=two, files=["p0/x"], configs=many
        )
    )
    big = {
        f"q{i:03}/release-please-config.json": {
            "packages": {
                f"q{i:03}": {"component": (i * 7919) % 97 if i % 13 else f"n{i}"}
            }
        }
        for i in range(90)
    }
    cases.append(
        Case(
            h,
            "ninety names of mixed types",
            pr=pr,
            commits=two,
            files=["q001/x"],
            configs=big,
        )
    )
    # One name that is text among numbers fails the sort on the first
    # comparison that meets it; where it sits decides which comparison that
    # is (the run count, the insertion, the merge) and so the message.
    shuffle = random.Random(3)
    for n in (20, 64, 65, 90, 130, 200):
        for at in sorted(
            {0, 1, n // 3, 31, 32, 44, 45, 46, 63, 64, n - 2, n - 1}
            - set(range(n, 1000))
        ):
            numbers = list(range(1, n + 1))
            shuffle.shuffle(numbers)
            if n >= 130:
                numbers[: n // 2] = sorted(numbers[: n // 2])
            names: list[object] = list(numbers)
            names[at] = "text"
            configs = {
                f"q{i:03}/release-please-config.json": {
                    "packages": {f"q{i:03}": {"component": v}}
                }
                for i, v in enumerate(names)
            }
            cases.append(
                Case(
                    h,
                    f"{n} names, text at {at}",
                    pr=pr,
                    commits=two,
                    files=["q001/x"],
                    configs=configs,
                )
            )
    ints = {
        f"q{i:03}/release-please-config.json": {
            "packages": {f"q{i:03}": {"component": (i * 7919) % 1000 + 1}}
        }
        for i in range(90)
    }
    cases.append(
        Case(
            h,
            "ninety numeric names",
            pr=dict(pr, title="fix: x"),
            commits=two,
            files=["q001/x", "q050/y"],
            configs=ints,
        )
    )
    for repeated in (
        ["a", "a"],
        [1, True],
        [1, 1.0, "x"],
        [[1], [1]],
        [2.5, 2.5],
        [{"a": 1}, {"a": 1}],
        ["z", "y", "z", "y"],
    ):
        configs = {
            f"p{i}/release-please-config.json": {
                "packages": {f"p{i}": {"component": n}}
            }
            for i, n in enumerate(repeated)
        }
        cases.append(
            Case(
                h,
                f"repeated names {repeated!r}",
                pr=pr,
                commits=two,
                files=SMALL_FILES,
                configs=configs,
            )
        )
    configs = dict(
        SMALL,
        **{
            "c/release-please-config.json": {
                "packages": {"c": {"component": "gamma", "package-name": [1]}}
            }
        },
    )
    cases.append(
        Case(
            h,
            "unhashable package-name",
            pr=pr,
            commits=two,
            files=SMALL_FILES,
            configs=configs,
        )
    )
    configs = dict(
        SMALL,
        **{
            "c/release-please-config.json": {
                "packages": {"c": {"component": 7, "package-name": "seven"}}
            }
        },
    )
    cases.append(
        Case(
            h,
            "numeric name released and declared",
            pr=dict(pr, title="fix: x", body="Releases: seven"),
            commits=two,
            files=SMALL_FILES + ["c/z"],
            configs=configs,
        )
    )
    cases.append(
        Case(
            h,
            "numeric name declared, not released",
            pr=dict(pr, title="fix(alpha): x", body="Releases: seven"),
            commits=two,
            files=["a/x"],
            configs=configs,
        )
    )
    cases.append(
        Case(
            h,
            "alias to a number",
            pr=dict(pr, title="fix(n): x"),
            commits=two,
            files=["c/z"],
            configs=configs,
            aliases={"aliases": {"n": {"components": [7]}}},
        )
    )
    cases.append(
        Case(
            h,
            "no name at the root",
            pr=pr,
            commits=two,
            files=SMALL_FILES,
            configs={"release-please-config.json": {"packages": {".": {}}}},
        )
    )
    cases.append(
        Case(
            h,
            "basename for a name",
            pr=dict(pr, title="fix(deep): x"),
            commits=two,
            files=["x/y/deep/f"],
            configs={
                "c/release-please-config.json": {"packages": {"./x//y/deep/": {}}}
            },
        )
    )
    cases.append(
        Case(
            h,
            "root package",
            pr=dict(pr, title="fix: x"),
            commits=two,
            files=["README.md", "a/b"],
            configs={"top/release-please-config.json": {"packages": {".": {}}}},
        )
    )
    return cases


def surrogate_cases(h, envs):
    cases = []
    two = ["one", "two"]
    for label, title in [
        ("lone high", "fix: x\ud800y"),
        ("escaped byte", "fix: x\udcffy"),
        ("run", "fix: \udcff𐀀\ud801"),
        ("pair", "fix: 😀"),
    ]:
        raw = json.dumps(
            {
                "title": title,
                "body": "",
                "user": {"login": "u", "type": "User"},
                "head": {"ref": "x"},
            },
            ensure_ascii=True,
        )
        cases.append(
            Case(
                h,
                f"surrogate title {label}",
                raw={"pr.json": raw},
                commits=two,
                files=SMALL_FILES,
                configs=SMALL,
                envs=envs,
            )
        )
        cases.append(
            Case(
                h,
                f"surrogate title {label}, passing",
                raw={"pr.json": raw.replace("fix:", "fix(alpha):")},
                commits=two,
                files=["a/x"],
                configs=SMALL,
                envs=envs,
            )
        )
    raw = json.dumps(
        {"aliases": {"\ud800": {"components": ["\udcff"]}}}, ensure_ascii=True
    )
    cases.append(
        Case(
            h,
            "surrogate in a message",
            pr={"title": "x"},
            commits=two,
            files=SMALL_FILES,
            configs=SMALL,
            raw={"aliases.json": raw},
            envs=envs,
        )
    )
    raw = json.dumps({"packages": {"a": {"component": "\ud800"}}}, ensure_ascii=True)
    cases.append(
        Case(
            h,
            "surrogate name",
            pr={"title": "fix: x"},
            commits=two,
            files=["a/x"],
            configs={"a/release-please-config.json": raw.encode()},
            envs=envs,
        )
    )
    return cases


TOKENS = [
    "--pr-json",
    "--pr",
    "--p",
    "--commits-json",
    "--c",
    "--files",
    "--f",
    "--repo-root",
    "--r",
    "--aliases",
    "--a",
    "-h",
    "--help",
    "--he",
    "-hx",
    "-h=x",
    "--help=x",
    "--help=",
    "--",
    "-",
    "-1",
    "-.5",
    "-x",
    "--zzz",
    "--x y",
    "--=x",
    "--files=",
    "-hh",
    "-h-",
    "-hfoo",
    "value",
    "{PR}",
    "{COMMITS}",
    "{FILES}",
    "{ROOT}",
    "{ALIASES}",
    "--pr-json={PR}",
    "--f={FILES}",
    "--a={ALIASES}",
    "",
]


def argv_cases(h, rng):
    pr, commits, files = baseline()
    cases = []
    good = [
        "--pr-json",
        "{PR}",
        "--commits-json",
        "{COMMITS}",
        "--files",
        "{FILES}",
        "--repo-root",
        "{ROOT}",
        "--aliases",
        "{ALIASES}",
    ]
    lists = [
        [],
        ["-h"],
        ["--help"],
        good,
        good + ["extra", "args"],
        good + ["--"],
        ["--"] + good,
        ["--pr={PR}", "--c", "{COMMITS}", "--fi={FILES}", "--rep", "{ROOT}"],
        good + ["--files"],
        good[:2],
        good + ["-hx"],
        good + ["--aliases", "{DIR}/nope.json"],
        good + ["--files", "{DIR}"],
        [
            "--pr-json",
            "{DIR}/nope",
            "--commits-json",
            "{COMMITS}",
            "--files",
            "{FILES}",
        ],
        ["--files", "{DIR}/nope", "--pr-json", "{DIR}/nope", "--commits-json", "x"],
    ]
    for _ in range(140):
        lists.append([rng.choice(TOKENS) for _ in range(rng.randrange(1, 9))])
    for i, tokens in enumerate(lists):
        argv = [
            t.replace("{PR}", "{DIR}/pr.json")
            .replace("{COMMITS}", "{DIR}/commits.json")
            .replace("{FILES}", "{DIR}/files.txt")
            .replace("{ROOT}", "{DIR}/root")
            .replace("{ALIASES}", "{DIR}/aliases.json")
            for t in tokens
        ]
        cases.append(
            Case(
                h,
                f"argv {argv}",
                pr=pr,
                commits=commits,
                files=files,
                configs=SMALL,
                argv=argv,
            )
        )
    widths = [
        "1",
        "10",
        "20",
        "24",
        "30",
        "40",
        "44",
        "50",
        "60",
        "79",
        "80",
        "81",
        "100",
        "200",
        " 90 ",
        "1_00",
        "x",
        "0",
        "-5",
        "٨٠",
        "1__0",
        "+70",
    ]
    for w in widths:
        for argv in (["-h"], ["--bogus"]):
            cases.append(
                Case(h, f"COLUMNS={w!r} {argv}", argv=argv, envs=[{"COLUMNS": w}])
            )
    return cases


def tree_cases(h):
    pr, commits, files = baseline()
    two = ["one", "two"]
    cases = []
    cases.append(
        Case(
            h,
            "no repo root",
            pr=pr,
            commits=commits,
            files=files,
            argv=[
                "--pr-json",
                "{DIR}/pr.json",
                "--commits-json",
                "{DIR}/commits.json",
                "--files",
                "{DIR}/files.txt",
                "--repo-root",
                "{DIR}/missing",
            ],
        )
    )
    cases.append(
        Case(
            h,
            "repo root is a file",
            pr=pr,
            commits=commits,
            files=files,
            argv=[
                "--pr-json",
                "{DIR}/pr.json",
                "--commits-json",
                "{DIR}/commits.json",
                "--files",
                "{DIR}/files.txt",
                "--repo-root",
                "{DIR}/pr.json",
            ],
        )
    )
    hidden = {
        f"{d}/x/release-please-config.json": {
            "packages": {"x": {"component": d.replace("/", "")}}
        }
        for d in (".git", "node_modules", "bazel-out", "a/node_modules", "a/bazel-bin")
    }
    cases.append(
        Case(
            h,
            "configs where the walk does not go",
            pr=pr,
            commits=two,
            files=SMALL_FILES,
            configs=hidden,
        )
    )
    cases.append(
        Case(
            h,
            "hidden configs and a real one",
            pr=dict(pr, title="fix: x"),
            commits=two,
            files=["x/y"],
            configs=dict(
                hidden,
                **{
                    "real/release-please-config.json": {
                        "packages": {"x": {"component": "real"}}
                    }
                },
            ),
        )
    )
    two_broken = {
        "b/release-please-config.json": b"{",
        "a/z/release-please-config.json": b"[",
        "a/release-please-config.json": b"x",
    }
    cases.append(
        Case(
            h,
            "the first broken config is the one reported",
            pr=pr,
            commits=two,
            files=SMALL_FILES,
            configs=two_broken,
        )
    )
    order = {
        "b/release-please-config.json": b"{",
        "a b/release-please-config.json": b"}",
        "a-b/release-please-config.json": b"]",
        "é/release-please-config.json": b"[",
        "A/release-please-config.json": b"x",
    }
    cases.append(
        Case(h, "walk order", pr=pr, commits=two, files=SMALL_FILES, configs=order)
    )
    case = Case(
        h,
        "links",
        pr=dict(pr, title="fix: x"),
        commits=two,
        files=["a/x", "l/y"],
        configs=SMALL,
    )
    root = os.path.join(case.dir, "root")
    os.symlink(os.path.join(root, "a"), os.path.join(root, "linked-dir"))
    os.makedirs(os.path.join(root, "l"))
    os.symlink(
        os.path.join(root, "b", "release-please-config.json"),
        os.path.join(root, "l", "release-please-config.json"),
    )
    cases.append(case)
    case = Case(
        h,
        "broken link to a config",
        pr=pr,
        commits=two,
        files=SMALL_FILES,
        configs=SMALL,
    )
    os.makedirs(os.path.join(case.dir, "root", "c"))
    os.symlink(
        os.path.join(case.dir, "nowhere"),
        os.path.join(case.dir, "root", "c", "release-please-config.json"),
    )
    cases.append(case)
    case = Case(
        h,
        "a folder named like a config",
        pr=dict(pr, title="fix: x"),
        commits=two,
        files=SMALL_FILES,
        configs=SMALL,
    )
    os.makedirs(os.path.join(case.dir, "root", "c", "release-please-config.json"))
    cases.append(case)
    if os.geteuid() != 0:
        case = Case(
            h,
            "an unreadable config",
            pr=pr,
            commits=two,
            files=SMALL_FILES,
            configs=SMALL,
        )
        os.chmod(os.path.join(case.dir, "root", "b", "release-please-config.json"), 0)
        cases.append(case)
        case = Case(
            h,
            "an unreadable folder",
            pr=dict(pr, title="fix: x"),
            commits=two,
            files=SMALL_FILES,
            configs=dict(SMALL, **{"z/release-please-config.json": b"{"}),
        )
        os.chmod(os.path.join(case.dir, "root", "z"), 0)
        cases.append(case)
    case = Case(
        h,
        "no aliases.json beside the program",
        pr=pr,
        commits=commits,
        files=files,
        configs=SMALL,
        aliases=MISSING,
    )
    case.hide_aliases = True
    cases.append(case)
    return cases


FRAGMENTS = [
    "feat",
    "fix",
    "chore",
    "docs",
    "perf",
    "revert",
    "feature",
    "ci",
    "refactor",
    "fixup",
    "Fix",
    "féat",
    "(alpha)",
    "(beta)",
    "(@x/beta)",
    "(a)",
    "()",
    "(a(b))",
    "(a)(b)",
    "(remote)",
    "(desktop)",
    "!",
    ":",
    ": ",
    " x",
    "x",
    "\n",
    "\n\n",
    "\r\n",
    "\r\n\r\n",
    "BREAKING CHANGE: y",
    "BREAKING-CHANGE: z",
    "BREAKING CHANGE:",
    "BREAKING CHANGE:\n\nlater",
    "Release-As: 2.0.0",
    "RELEASE-AS: 1",
    "releaſe-as: 1",
    "release-as:   ",
    "* fix(alpha): bullet",
    "BEGIN_NESTED_COMMIT\nfix(beta): nested\nEND_NESTED_COMMIT",
    "BEGIN_NESTED_COMMIT\n",
    "END_NESTED_COMMIT",
    "  fix(alpha): indented",
    "　",
    "\t",
    " ",
    "fix(alpha): y",
    "feat(beta)!: z",
    "chore(x): w",
]
BODIES = [
    "",
    "Releases: alpha",
    "Releases: `beta`, alpha\r\n",
    "Releases:alpha,beta",
    " \tReleases:  alpha \t\r",
    "Releases: @x/beta",
    "Releases: nope",
    "Releases: alpha nope alpha",
    "This Releases: beta",
    "Releases:\nalpha",
    "Releases:  beta",
    "Releases: alpha　beta",
    "releases: beta",
    "BEGIN_COMMIT_OVERRIDE\nfix(alpha): over\nEND_COMMIT_OVERRIDE",
    "BEGIN_COMMIT_OVERRIDE\n\nEND_COMMIT_OVERRIDE",
    "BEGIN_COMMIT_OVERRIDE fix: open",
    "x\nReleases: beta\nReleases: alpha\n",
    "Releases: x\r\r",
]
MESSAGE_CONFIGS = {
    "a/release-please-config.json": {
        "packages": {"a": {"component": "alpha"}, "a/inner": {"component": "inner"}}
    },
    "b/release-please-config.json": {
        "packages": {
            "b": {
                "component": "beta",
                "package-name": "@x/beta",
                "exclude-paths": ["b/skip", "./b/also/"],
            }
        }
    },
    "c/release-please-config.json": {
        "packages": {"c": {"component": "gamma"}},
        "changelog-sections": [
            {"type": "docs", "section": "D"},
            {"type": "fix", "hidden": True},
        ],
    },
}
MESSAGE_FILES = [
    "a/x",
    "a/inner/y",
    "b/z",
    "b/skip/w",
    "b/also/v",
    "c/u",
    "top",
    "a",
    "ab/x",
]


def message_cases(h, rng):
    cases = []
    for i in range(170):

        def random_message():
            return "".join(rng.choice(FRAGMENTS) for _ in range(rng.randrange(1, 10)))

        commits = [random_message() for _ in range(rng.choice([0, 1, 1, 2, 3]))]
        pr = {
            "title": random_message(),
            "body": rng.choice(BODIES) + rng.choice(["", "\n" + rng.choice(BODIES)]),
            "user": {"login": "u", "type": rng.choice(["User", "Bot"])},
            "head": {
                "ref": rng.choice(
                    ["x", "dependabot/y", "release-please--z", "renovate/q"]
                )
            },
        }
        files = rng.sample(MESSAGE_FILES, rng.randrange(1, len(MESSAGE_FILES)))
        cases.append(
            Case(
                h,
                f"message #{i}",
                pr=pr,
                commits=commits,
                files=files,
                configs=MESSAGE_CONFIGS,
                aliases={
                    "aliases": {
                        "remote": {"components": ["beta"]},
                        "desktop": {"components": ["alpha", "gamma"]},
                    }
                },
            )
        )
    # A footer the type does not release, in each spelling re.IGNORECASE takes.
    for footer in (
        "Release-As: 2.0.0",
        "RELEASE-AS: 2",
        "relea\u017fe-as: 2",
        "rel\u0130ase-as: 2",
        "release-as:",
        "release-as: \n\n x",
        " release-as: 2",
        "BREAKING CHANGE: y",
        "BREAKING-CHANGE:z",
        "BREAKING CHANGE:  \n",
        "x BREAKING-CHANGE: y",
    ):
        for commits in (
            [f"chore: x\n\n{footer}"],
            [f"chore: x\r\n\r\n{footer}", "two"],
        ):
            cases.append(
                Case(
                    h,
                    f"footer {footer!r}",
                    pr={"title": "chore(ci): x"},
                    commits=commits,
                    files=["a/x"],
                    configs=MESSAGE_CONFIGS,
                )
            )
    # Where release-please cuts one message into several decides which
    # commit a footer belongs to, and so whether the scoped one releases.
    for second in (
        "chore(alpha): y",
        "chore(alpha)!: y",
        "chore(a(b)): y",
        "chore(a)x): y",
        "chore(al\nx): y",
        "fixup(alpha): y",
        "feature(alpha): y",
        "chore(): y",
        "chore:y",
        "revert(alpha): y",
        "Chore(alpha): y",
        "chore(alpha) : y",
    ):
        for gap in ("\n\n", "\r\n\r\n", "\n\r\n", "\n\n\n", "\n", "\r\n\n"):
            message = f"chore: x{gap}{second}\n\nBREAKING CHANGE: z"
            cases.append(
                Case(
                    h,
                    f"split {message!r}",
                    pr={"title": "chore: t"},
                    commits=[message],
                    files=["a/x"],
                    configs=MESSAGE_CONFIGS,
                )
            )
    for nested in (
        "BEGIN_NESTED_COMMIT\nchore(alpha): n\n\nBREAKING CHANGE: q\nEND_NESTED_COMMIT",
        "BEGIN_NESTED_COMMIT\nchore(alpha): n\nEND_NESTED_COMMIT\nBREAKING CHANGE: q",
        "BEGIN_NESTED_COMMITchore(alpha)!: n",
        "END_NESTED_COMMIT\nchore(alpha)!: n",
    ):
        cases.append(
            Case(
                h,
                f"nested {nested!r}",
                pr={"title": "chore: t"},
                commits=[f"chore: x\n\n{nested}"],
                files=["a/x"],
                configs=MESSAGE_CONFIGS,
            )
        )
    many_files = [f"a/f{i}" for i in range(12)] + [f"b/g{i}" for i in range(5)]
    cases.append(
        Case(
            h,
            "long listings",
            pr={"title": "fix(beta): x"},
            commits=["a", "b"],
            files=many_files,
            configs=MESSAGE_CONFIGS,
        )
    )
    return cases


def stdout_envs(harness):
    """Locales in which Python writes stdout strictly, and leniently."""
    envs = [
        {"LC_ALL": "C"},
        {"PYTHONUTF8": "1"},
        {"PYTHONIOENCODING": "utf-8:backslashreplace"},
    ]
    for name in ("en_US.UTF-8", "C.UTF-8", "UTF-8"):
        probe = subprocess.run(
            [sys.executable, "-c", "import sys; print(sys.stdout.errors)"],
            env=base_env({"LC_ALL": name}),
            capture_output=True,
            text=True,
        )
        envs.append({"LC_ALL": name, "_expect": probe.stdout.strip()})
    return envs


class Parity(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.h = Harness()
        rng = random.Random(20261013)
        cls.unit_result, calls = record_unit_tests()
        cls.calls = calls
        cls.groups = {
            "release_scope_test.py": unit_cases(cls.h, calls),
            "testdata": fixture_cases(cls.h),
            "json": json_cases(cls.h, rng),
            "encoding": encoding_cases(cls.h),
            "types": type_cases(cls.h),
            "surrogates": surrogate_cases(
                cls.h,
                [
                    {k: v for k, v in e.items() if not k.startswith("_")}
                    for e in stdout_envs(cls.h)
                ],
            ),
            "argv": argv_cases(cls.h, rng),
            "trees": tree_cases(cls.h),
            "messages": message_cases(cls.h, rng),
        }

    @classmethod
    def tearDownClass(cls):
        for folder, dirs, _ in os.walk(cls.h.tmp):
            for d in dirs:
                path = os.path.join(folder, d)
                if not os.path.islink(path):
                    os.chmod(path, stat.S_IRWXU)
        for folder, _, files in os.walk(cls.h.tmp):
            for f in files:
                path = os.path.join(folder, f)
                if not os.path.islink(path):
                    os.chmod(path, stat.S_IRUSR | stat.S_IWUSR)
        shutil.rmtree(cls.h.tmp, ignore_errors=True)

    def check(self, group):
        cases = self.groups[group]
        self.assertTrue(cases, group)

        def one(case):
            results = []
            for extra in case.envs:
                env = base_env(extra)
                hidden = case.hide_aliases
                moved = []
                if hidden:
                    for d in self.h.dirs.values():
                        src = os.path.join(d, "sub", "aliases.json")
                        if os.path.exists(src):
                            os.rename(src, src + ".away")
                            moved.append(src)
                try:
                    py = self.h.run("py", case.argv, env)
                    rs_ = self.h.run("rs", case.argv, env)
                finally:
                    for src in moved:
                        os.rename(src + ".away", src)
                results.append((extra, py, rs_, same(py, rs_)))
            return case, results

        # The case that hides aliases.json must not run beside the others.
        plain = [c for c in cases if not c.hide_aliases]
        alone = [c for c in cases if c.hide_aliases]
        with ThreadPoolExecutor(max_workers=8) as pool:
            outcomes = list(pool.map(one, plain))
        outcomes += [one(c) for c in alone]
        failures = []
        codes = {}
        for case, results in outcomes:
            for extra, py, _, diff in results:
                codes[py[0]] = codes.get(py[0], 0) + 1
                if diff:
                    failures.append(f"{case.name} {extra or ''}: {diff}")
        print(
            f"{group}: {sum(len(r) for _, r in outcomes)} runs, python exit codes {dict(sorted(codes.items()))}",
            file=sys.stderr,
        )
        self.assertEqual(failures, [], "\n\n".join(failures[:5]))
        # Agreeing that nothing could be decided proves little: each group
        # must also reach the decision.
        self.assertTrue({0, 1} & set(codes), f"{group}: no case got past the inputs")
        return outcomes

    def test_the_python_suite_passes_and_was_recorded(self):
        r = self.unit_result
        self.assertTrue(r.wasSuccessful(), r.failures + r.errors)
        self.assertGreater(r.testsRun, 50)
        kinds = {c[0] for c in self.calls}
        self.assertEqual(kinds, {"judge", "main", "messages", "squash_message"})

    def test_release_scope_test_cases(self):
        outcomes = self.check("release_scope_test.py")
        exits = {results[0][1][0] for _, results in outcomes}
        self.assertEqual(exits, {0, 1, 2})

    def test_testdata_fixtures(self):
        outcomes = self.check("testdata")
        self.assertEqual(len(outcomes), 4 * 9)

    def test_json_that_does_not_parse(self):
        self.check("json")

    def test_files_that_are_not_utf8(self):
        self.check("encoding")

    def test_values_of_the_wrong_type(self):
        outcomes = self.check("types")
        crashes = {
            py[2].rstrip().split(b"\n")[-1].split(b":")[0]
            for _, results in outcomes
            for _, py, _, _ in results
            if py[2].startswith(TRACEBACK)
        }
        for kind in (b"AttributeError", b"TypeError", b"KeyError"):
            self.assertIn(kind, crashes)

    def test_lone_surrogates_in_each_locale(self):
        outcomes = self.check("surrogates")
        runs = [py for _, results in outcomes for _, py, _, _ in results]
        self.assertTrue(
            any(b"UnicodeEncodeError" in py[2] for py in runs),
            "no strict stdout crashed",
        )
        self.assertTrue(
            any(b"\xff" in py[1] for py in runs),
            "no surrogateescape stdout wrote a byte",
        )
        self.assertTrue(
            any(b"\\ud800" in py[2] for py in runs), "no backslashreplace on stderr"
        )

    def test_command_lines_and_widths(self):
        self.check("argv")

    def test_trees_of_configs(self):
        self.check("trees")

    def test_generated_commit_messages(self):
        self.check("messages")

    def test_the_unicode_tables_are_this_pythons(self):
        with open(
            os.path.join(HERE, "src", "unicode_tables.rs"), encoding="utf-8"
        ) as handle:
            self.assertEqual(
                handle.read(),
                gen_unicode_tables.render(),
                "regenerate src/unicode_tables.rs with gen_unicode_tables.py",
            )


if __name__ == "__main__":
    unittest.main()
