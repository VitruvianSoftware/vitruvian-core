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

"""Holds the Rust gen_tokens to gen_tokens.py, byte for byte.

Both run as programs - :gen_tokens-py (the script under Bazel's launcher,
which is what :gen_tokens was) and :gen_tokens (the port) - each in its own
directory with the same files at the same relative paths, so any path an
error names is the same. Per case, the exit code, stdout, stderr and every
file left in the directory (the generated Kotlin above all) must match:

  * the real tokens.json;
  * command lines argparse treats specially, at several terminal widths;
  * missing, unreadable, mis-encoded and misplaced files;
  * malformed JSON: hand-written, and tokens.json cut short and mutated;
  * token trees built to break the script at each step it takes (every
    lookup given every JSON type, aliases, the light overrides, the int()
    sort keys, the easing unpack), and the recursion limits on both sides;
  * every code point whose case mapping, printability, whitespace or digit
    value Python's str methods read.

When Python dies with an uncaught exception its traceback names its own
files and source lines, which the port cannot have. There both must print a
traceback, and its last line - the exception's class and message - must be
the same.

Also checks that src/unicode_tables.rs is what gen_unicode_tables.py makes
from this Python, and that a difference between the two runs is reported.
"""

import concurrent.futures
import copy
import json
import os
import random
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import gen_unicode_tables  # noqa: E402

TRACEBACK = "Traceback (most recent call last):\n"
ARGS = ["--tokens", "tokens.json", "--header", "header.txt", "--out", "out.kt"]
SIGMA = "Σ"


def _runfile(var):
    path = os.environ.get(var, "")
    if not path:
        raise unittest.SkipTest(f"{var} is not set; run this under bazel test")
    return os.path.abspath(path)


class Case:
    def __init__(
        self, name, tokens=None, *, args=None, files=None, env=None, prep=None, ok=False
    ):
        self.name = name
        # The case is there to exercise the success path: Python must exit 0.
        self.ok = ok
        self.args = ARGS if args is None else args
        self.files = {} if files is None else dict(files)
        if tokens is not None:
            self.files.setdefault(
                "tokens.json", tokens if isinstance(tokens, bytes) else tokens.encode()
            )
        self.files.setdefault("header.txt", HEADER)
        self.env = env or {}
        self.prep = prep


def dumps(tree, **kw):
    return json.dumps(tree, **kw)


def collect(d):
    """Every file and directory under d: relative path -> bytes, or None."""
    out = {}
    for root, dirs, files in os.walk(d):
        for name in dirs:
            out[os.path.relpath(os.path.join(root, name), d)] = None
        for name in files:
            p = os.path.join(root, name)
            os.chmod(p, 0o600)
            with open(p, "rb") as f:
                out[os.path.relpath(p, d)] = f.read()
    return out


def differences(py, rs):
    """What differs between two runs; empty when they agree."""
    problems = []
    for key in ("code", "stdout"):
        if py[key] != rs[key]:
            problems.append(f"{key}: py={_short(py[key])} rs={_short(rs[key])}")
    for name in sorted(set(py["files"]) | set(rs["files"])):
        a, b = py["files"].get(name, "<absent>"), rs["files"].get(name, "<absent>")
        if a == b:
            continue
        if isinstance(a, bytes) and isinstance(b, bytes):
            la, lb = a.split(b"\n"), b.split(b"\n")
            i = next(
                (i for i, (x, y) in enumerate(zip(la, lb)) if x != y),
                min(len(la), len(lb)),
            )
            a = la[i] if i < len(la) else "<end>"
            b = lb[i] if i < len(lb) else "<end>"
            problems.append(f"{name} line {i + 1}: py={_short(a)} rs={_short(b)}")
        else:
            problems.append(f"{name}: py={_short(a)} rs={_short(b)}")
    pe, re_ = py["stderr"], rs["stderr"]
    if pe.startswith(TRACEBACK) or re_.startswith(TRACEBACK):
        last = lambda s: s.rstrip("\n").rsplit("\n", 1)[-1]  # noqa: E731
        if not (pe.startswith(TRACEBACK) and re_.startswith(TRACEBACK)):
            problems.append(f"stderr: py={_short(pe)} rs={_short(re_)}")
        elif last(pe) != last(re_):
            problems.append(f"exception: py={_short(last(pe))} rs={_short(last(re_))}")
    elif pe != re_:
        problems.append(f"stderr: py={_short(pe)} rs={_short(re_)}")
    return problems


def _short(v):
    r = repr(v)
    return r if len(r) < 400 else r[:400] + "..."


with open(os.path.join(HERE, "kt_license_header.txt"), "rb") as _f:
    HEADER = _f.read()


class Parity(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.programs = {
            "py": _runfile("GEN_TOKENS_PY"),
            "rs": _runfile("GEN_TOKENS_RS"),
        }
        with open(_runfile("TOKENS_JSON"), "rb") as f:
            cls.tokens_bytes = f.read()
        cls.tokens = json.loads(cls.tokens_bytes)
        cls.tmp = tempfile.mkdtemp()
        cls.env = dict(os.environ)
        for var in ("RUNFILES_DIR", "RUNFILES_MANIFEST_FILE", "TEST_SRCDIR"):
            if cls.env.get(var):
                cls.env[var] = os.path.abspath(cls.env[var])
        cls.env.pop("COLUMNS", None)
        cls.env.pop("LINES", None)
        cls.env["PYTHONDONTWRITEBYTECODE"] = "1"
        cls.count = 0

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)

    # -- running --------------------------------------------------------

    def run_one(self, kind, case, n):
        d = os.path.join(self.tmp, f"{n}-{kind}")
        os.makedirs(d)
        for rel, data in case.files.items():
            p = os.path.join(d, rel)
            if data is None:
                os.makedirs(p, exist_ok=True)
                continue
            os.makedirs(os.path.dirname(p), exist_ok=True)
            with open(p, "wb") as f:
                f.write(data)
        if case.prep:
            case.prep(d)
        env = dict(self.env)
        env.update(case.env)
        done = subprocess.run(
            [self.programs[kind]] + case.args,
            cwd=d,
            env=env,
            capture_output=True,
            timeout=300,
        )
        result = {
            "code": done.returncode,
            "stdout": done.stdout.decode("utf-8", "surrogateescape"),
            "stderr": done.stderr.decode("utf-8", "surrogateescape"),
            "files": collect(d),
        }
        shutil.rmtree(d, ignore_errors=True)
        return result

    def run_case(self, case):
        Parity.count += 1
        n = Parity.count
        return case, self.run_one("py", case, n), self.run_one("rs", case, n)

    def check(self, cases):
        self.assertTrue(cases)
        names = [c.name for c in cases]
        self.assertEqual(len(names), len(set(names)), "case names repeat")
        failures = []
        outcomes = {}
        workers = min(16, (os.cpu_count() or 2) * 2)
        with concurrent.futures.ThreadPoolExecutor(workers) as pool:
            for case, py, rs in pool.map(self.run_case, cases):
                problems = differences(py, rs)
                if case.ok and py["code"] != 0:
                    problems.append(
                        f"python failed on a case meant to pass: {_short(py['stderr'][-300:])}"
                    )
                if problems:
                    failures.append(f"{case.name}:\n    " + "\n    ".join(problems))
                last = py["stderr"].rstrip("\n").rsplit("\n", 1)[-1]
                how = f"exit {py['code']} " + (
                    last.split(":", 1)[0] if py["code"] == 1 else ""
                )
                outcomes[how] = outcomes.get(how, 0) + 1
        # The spread of what the cases did, so a run where every case failed
        # the same way (and so "matched") shows in the log.
        tally = ", ".join(f"{k.strip()}: {v}" for k, v in sorted(outcomes.items()))
        print(
            f"\n{self.id().rsplit('.', 1)[-1]}: {len(cases)} cases ({tally})",
            file=sys.stderr,
        )
        self.assertFalse(
            failures,
            f"{len(failures)} of {len(cases)} differ:\n" + "\n".join(failures[:15]),
        )

    # -- token trees ----------------------------------------------------

    def tree(self):
        return copy.deepcopy(self.tokens)

    def with_value(self, path, value):
        t = self.tree()
        node = t
        for part in path[:-1]:
            node = node[part]
        node[path[-1]] = value
        return dumps(t)

    def without(self, path):
        t = self.tree()
        node = t
        for part in path[:-1]:
            node = node[part]
        del node[path[-1]]
        return dumps(t)

    # -- the cases ------------------------------------------------------

    def test_real_tokens(self):
        cases = [
            Case("real", self.tokens_bytes, ok=True),
            Case("real ascii", dumps(self.tokens), ok=True),
            Case(
                "real overwrite", self.tokens_bytes, files={"out.kt": b"stale"}, ok=True
            ),
            Case(
                "real, equals syntax and abbreviations",
                self.tokens_bytes,
                args=["--tok=tokens.json", "--hea", "header.txt", "--o", "out.kt"],
                ok=True,
            ),
        ]
        self.check(cases)
        # And the output is the Kotlin, not two matching failures.
        _, py, _ = self.run_case(Case("real again", self.tokens_bytes))
        self.assertEqual(py["code"], 0)
        self.assertIn(b"public data class VitruvianColors(", py["files"]["out.kt"])

    def test_command_lines(self):
        lines = [
            [],
            ["-h"],
            ["--help"],
            ["-h", "--bogus"],
            ["--tokens"],
            ["--tokens", "tokens.json"],
            ["--tokens", "tokens.json", "--header", "header.txt"],
            ["--header", "header.txt", "--out", "out.kt"],
            ARGS + ["extra"],
            ARGS + ["--bogus"],
            ARGS + ["--bogus=1"],
            ARGS + ["-x"],
            ARGS + ["--"],
            ARGS + ["--", "x"],
            ["--h", "header.txt"],
            ["--tokens=", "--header=", "--out="],
            ["--tokens", "-x", "--header", "header.txt", "--out", "out.kt"],
            ["--tokens", "-1", "--header", "header.txt", "--out", "out.kt"],
            [
                "--tokens",
                "tokens.json",
                "--tokens",
                "nope",
                "--header",
                "header.txt",
                "--out",
                "out.kt",
            ],
            [
                "--tokens",
                "nope",
                "--tokens",
                "tokens.json",
                "--header",
                "header.txt",
                "--out",
                "out.kt",
            ],
            ["-htokens"],
            ["-", "x"],
            ["--tokens", "a b", "--header", "header.txt", "--out", "out.kt"],
            ["--toke", "tokens.json", "--he", "header.txt", "--ou", "out.kt"],
            ["--out", "out.kt", "--tokens", "tokens.json", "--header", "header.txt"],
            ["--Tokens", "tokens.json"],
            ["--tokens", "tokens.json", "--header", "header.txt", "--out"],
            ["é", "--out", "ü.kt"],
        ]
        cases = []
        for columns in (None, "10", "30", "50", "200", "0", "x"):
            env = {} if columns is None else {"COLUMNS": columns}
            for i, args in enumerate(lines):
                cases.append(
                    Case(
                        f"cli {columns} {i} {args}",
                        self.tokens_bytes,
                        args=args,
                        env=env,
                    )
                )
        self.check(cases)

    def test_files(self):
        t = self.tokens_bytes
        good = {"tokens.json": t}

        def unreadable(rel):
            return lambda d: os.chmod(os.path.join(d, rel), 0)

        def readonly_dir(rel):
            return lambda d: os.chmod(os.path.join(d, rel), stat.S_IRUSR | stat.S_IXUSR)

        cases = [
            Case("no tokens file", files={}, args=["--tokens", "nope.json"] + ARGS[2:]),
            Case("tokens is a dir", files={"tokens.json": None}),
            Case(
                "no header file",
                t,
                args=ARGS[:2] + ["--header", "nope.txt", "--out", "out.kt"],
            ),
            Case("header is a dir", files={**good, "header.txt": None}),
            Case(
                "out in a missing dir", t, args=ARGS[:4] + ["--out", "no/such/out.kt"]
            ),
            Case("out is a dir", t, files={**good, "out.kt": None}),
            Case(
                "out is a file's child",
                t,
                args=ARGS[:4] + ["--out", "header.txt/out.kt"],
            ),
            Case("empty paths", t, args=["--tokens", "", "--header", "", "--out", ""]),
            Case(
                "dotted paths",
                t,
                args=[
                    "--tokens",
                    "./tokens.json",
                    "--header",
                    ".//header.txt",
                    "--out",
                    "././out.kt",
                ],
            ),
            Case("trailing slash", t, args=["--tokens", "tokens.json/"] + ARGS[2:]),
            Case("double slash missing", t, args=["--tokens", "//no/such"] + ARGS[2:]),
            Case(
                "triple slash missing",
                t,
                args=["--tokens", "///no//such/./x"] + ARGS[2:],
            ),
            Case("quote in path", t, args=["--tokens", "it's.json"] + ARGS[2:]),
            Case("unicode path", t, args=["--tokens", "tökens​.json"] + ARGS[2:]),
            Case("tokens unreadable", t, prep=unreadable("tokens.json")),
            Case("header unreadable", t, prep=unreadable("header.txt")),
            Case(
                "out dir read-only",
                t,
                files={**good, "o": None},
                args=ARGS[:4] + ["--out", "o/out.kt"],
                prep=readonly_dir("o"),
            ),
            Case("out is tokens", t, args=ARGS[:4] + ["--out", "tokens.json"]),
            Case("out is header", t, args=ARGS[:4] + ["--out", "header.txt"]),
            Case("header empty", t, files={**good, "header.txt": b""}),
            Case("header crlf", t, files={**good, "header.txt": b"// a\r\n// b\r\n"}),
            Case("header cr", t, files={**good, "header.txt": b"// a\r// b\r\r\n\n"}),
            Case("header bom", t, files={**good, "header.txt": b"\xef\xbb\xbf// a\n"}),
            Case(
                "header unicode",
                t,
                files={**good, "header.txt": "// é ✓ 😀  \n".encode()},
            ),
            Case("tokens crlf", t.replace(b"\n", b"\r\n")),
            Case("tokens cr", t.replace(b"\n", b"\r")),
            Case("tokens bom", b"\xef\xbb\xbf" + t),
            Case("tokens empty", b""),
        ]
        for i, bad in enumerate(
            [
                b"\xff",
                b"\xfe",
                b"\x80",
                b"\xc0\xaf",
                b"\xc2",
                b"\xe2\x82",
                b"\xe2\x82x",
                b"\xe0\x80",
                b"\xed\xa0\x80",
                b"\xf0\x9f\x98",
                b"\xf4\x90\x80\x80",
                b"\xf5",
                b"a\xe2\x82\xac\xff",
                b"\xf0\x9f\x98\x80\xc3",
            ]
        ):
            cases.append(Case(f"tokens bad utf-8 {i}", t[:100] + bad + t[100:]))
            cases.append(
                Case(
                    f"header bad utf-8 {i}",
                    t,
                    files={**good, "header.txt": b"// x" + bad},
                )
            )
            cases.append(Case(f"crlf before bad utf-8 {i}", b"{\r\n\r\n" + bad))
        self.check(cases)

    def test_malformed_json(self):
        docs = [
            "",
            " ",
            "\n\n",
            "x",
            "{",
            "}",
            "[",
            "]",
            "[1,]",
            '{"a":1,}',
            "{,}",
            "[,]",
            "{'a': 1}",
            '{"a" 1}',
            '{"a":}',
            '{"a":1 "b":2}',
            "[1 2]",
            '{"a"',
            '{"a":',
            '{"a":1',
            "[1",
            "[1,",
            '"abc',
            '"a\\',
            '"\\x"',
            '"\\u12"',
            '"\\u12',
            '"\\u12345"',
            '"\\uzzzz"',
            '"\\ud83d"',
            '"\\ud83d\\u"',
            '"\\ud83d\\ude00"',
            '"\\ud83d\\ude00',
            '"\\ud83d\\uzzzz"',
            '"\\ud83d\\u0041"',
            '"\\ude00\\ud83d"',
            '"\\u00e9\\n\\t\\/\\b\\f\\r\\"\\\\"',
            '"a\nb"',
            '"\x00"',
            '"\x1f"',
            '"\x7f"',
            "\t\r\n []\t",
            "[] x",
            "[]]",
            "{}{}",
            "nul",
            "null",
            "nulll",
            "tru",
            "true",
            "fals",
            "false",
            "NaN",
            "NaNx",
            "Nan",
            "Infinity",
            "-Infinity",
            "-Inf",
            "infinity",
            "-",
            "-x",
            "--1",
            "+1",
            "01",
            "00",
            "-01",
            "1.",
            ".1",
            "1.e5",
            "1e",
            "1e+",
            "1e-",
            "1E5",
            "1e5x",
            "-0",
            "-0.0",
            "1.5e400",
            "-1e400",
            "1e-400",
            "123456789012345678901234567890",
            "1" * 4300,
            "1" * 4301,
            "-" + "1" * 4301,
            "1" * 4300 + ".5",
            "0.1e" + "9" * 30,
            "[1e999999999999999999999]",
            '{"a":1,"a":2}',
            '{"\\u0000":1}',
            " []",
            "[ ]",
            "﻿[]",
            "[﻿]",
            "[" * 3 + "]" * 2,
            '{"a":[{"b":[}]}',
            "[1,2,3,]",
            '{"":1}',
            '{"a":1,,"b":2}',
            "[01]",
            '["\\',
            "[-]",
            "[NaN, Infinity, -Infinity, -0, 0.5]",
            "1 2",
            "[\n1\n,\n]\n",
        ]
        cases = [Case(f"json {i} {d[:40]!r}", d) for i, d in enumerate(docs)]
        for depth in (9993, 9994, 9995):
            cases.append(Case(f"array nesting {depth}", "[" * depth + "]" * depth))
            cases.append(
                Case(
                    f"object nesting {depth}",
                    '{"a":' * (depth - 1) + "{}" + "}" * (depth - 1),
                )
            )
        cases.append(Case("nesting then bad", "[" * 9995))
        # tokens.json cut short, and with one character dropped or swapped.
        text = self.tokens_bytes.decode()
        for i in range(0, len(text), max(1, len(text) // 150)):
            cases.append(Case(f"cut {i}", text[:i]))
        rng = random.Random(1234)
        for k in range(250):
            i = rng.randrange(len(text))
            op = rng.choice(["drop", "dup", "swap", "insert"])
            if op == "drop":
                doc = text[:i] + text[i + 1 :]
            elif op == "dup":
                doc = text[:i] + text[i] + text[i:]
            elif op == "swap":
                doc = text[:i] + rng.choice('{}[]",:\\ 0a-e.') + text[i + 1 :]
            else:
                doc = (
                    text[:i]
                    + rng.choice(['"', "\\", "\x01", "\\u", ",", "}", "]", "\r\n", "é"])
                    + text[i:]
                )
            cases.append(Case(f"mutated {k} {op} {i}", doc))
        self.check(cases)

    def test_every_lookup_given_every_type(self):
        kinds = {
            "null": None,
            "true": True,
            "int": 7,
            "float": 1.5,
            "str": "13px",
            "empty str": "",
            "list": [],
            "list1": ["color"],
            "dict": {},
            "dict1": {"$value": "#ffffff"},
        }
        t = self.tokens
        paths = [[]]
        for key in (
            "color",
            "glass",
            "light",
            "space",
            "hit",
            "font",
            "motion",
            "shadow",
        ):
            paths.append([key])
        paths += [
            ["color", "bg"],
            ["color", "bg", "$value"],
            ["color", "accent", "100"],
            ["color", "accent", "100", "$value"],
            ["glass", "bg"],
            ["glass", "bg", "$value"],
            ["space", next(iter(t["space"]))],
            ["space", next(iter(t["space"])), "$value"],
            ["hit", next(iter(t["hit"]))],
            ["hit", next(iter(t["hit"])), "$value"],
            ["font", "size"],
            ["font", "size", next(iter(t["font"]["size"]))],
            ["font", "size", next(iter(t["font"]["size"])), "$value"],
            ["motion", "duration"],
            ["motion", "duration", next(iter(t["motion"]["duration"]))],
            ["motion", "duration", next(iter(t["motion"]["duration"])), "$value"],
            ["motion", "easing"],
            ["motion", "easing", next(iter(t["motion"]["easing"]))],
            ["motion", "easing", next(iter(t["motion"]["easing"])), "$value"],
            ["shadow", "sm"],
            ["shadow", "md", "$value"],
            ["shadow", "lg", "$value", "offsetY"],
        ]
        if "light" in t:
            first = next(iter(t["light"]))
            paths += [["light", first]]
        cases = []
        for path in paths:
            for name, value in kinds.items():
                doc = dumps(value) if not path else self.with_value(path, value)
                cases.append(Case(f"{'.'.join(path) or 'root'} = {name}", doc))
            if path and self._has(path):
                cases.append(Case(f"{'.'.join(path)} deleted", self.without(path)))
        self.check(cases)

    def _has(self, path):
        node = self.tokens
        for p in path:
            if not isinstance(node, dict) or p not in node:
                return False
            node = node[p]
        return True

    def test_colours_and_aliases(self):
        cases = []
        values = [
            "#abc",
            "##ffffff",
            "#ffffffff",
            "#FFFFFF80",
            "ffffff",
            "#gggggg",
            "#ßßßßßß",
            "#ﬃﬃ12",
            "#éééééé",
            "#1234567",
            "#",
            "",
            "{color.text}",
            "{color.accent.500}",
            "{glass.bg}",
            "{nope}",
            "{color.nope}",
            "{",
            "}",
            "{}",
            "{.}",
            "{color.bg}",
            "{color}",
            "{ color.text }",
            "{color..text}",
            "{color.text}}",
            "{{color.text}",
            "#\ud800\ud800\ud800",
            "#abcdef\udfff\udfff",
        ]
        for i, v in enumerate(values):
            cases.append(
                Case(f"bg {i} {v!r}", self.with_value(["color", "bg", "$value"], v))
            )
            cases.append(
                Case(f"glass {i} {v!r}", self.with_value(["glass", "bg", "$value"], v))
            )
        t = self.tree()
        t["color"]["bg"]["$value"] = "{a.b}"
        t["a"] = {"b": {"$value": "{a.c}"}, "c": {"$value": "{a.b}"}}
        cases.append(Case("alias cycle", dumps(t)))
        t = self.tree()
        t["color"]["bg"]["$value"] = "{a.b}"
        t["a"] = {"b": {"$value": 5}}
        cases.append(Case("alias to int", dumps(t)))
        t["a"] = {"b": {"$value": ["{x}"]}}
        cases.append(Case("alias to list", dumps(t)))
        t["a"] = {"b": {"$value": "{a.b"}}
        cases.append(Case("alias to half alias", dumps(t)))
        for n in (987, 988, 989):
            t = self.tree()
            t["color"]["bg"]["$value"] = "{z.0}"
            t["z"] = {str(i): {"$value": "{z.%d}" % (i + 1)} for i in range(n)}
            t["z"][str(n)] = {"$value": "#000000"}
            cases.append(Case(f"alias chain {n}", dumps(t)))
            t["light"] = {
                "color": {"bg": {"$value": "{color.z}"}, "z": {"$value": "{z.0}"}}
            }
            cases.append(Case(f"light alias chain {n}", dumps(t)))
        self.check(cases)

    def test_light_overrides(self):
        light_values = {
            "null": None,
            "int": 1,
            "float": 0.5,
            "true": True,
            "str has color": "xcolorx",
            "str": "x",
            "list with color": ["color"],
            "list": [1, "glass "],
            "empty": {},
            "color null": {"color": None},
            "color list": {"color": []},
            "color str": {"color": "s"},
            "color empty": {"color": {}},
            "glass only": {"glass": {"bg": {"$value": "#01020304"}}},
            "partial": {
                "color": {
                    "bg": {"$value": "#010203"},
                    "accent": {"100": {"$value": "#aabbcc"}},
                }
            },
            "alias inside": {
                "color": {
                    "bg": {"$value": "{color.text}"},
                    "text": {"$value": "#0a0b0c"},
                }
            },
            "alias outside": {"color": {"bg": {"$value": "{space.1}"}}},
            "alias to base path": {"color": {"bg": {"$value": "{color.accent.500}"}}},
            "alias missing": {"color": {"bg": {"$value": "{color.nope}"}}},
            "bad colour": {"color": {"bg": {"$value": "#12"}}},
            "value int": {"color": {"bg": {"$value": 3}}},
            "node list": {"color": {"bg": []}},
            "node str": {"color": {"bg": "x"}},
            "cycle": {
                "color": {"bg": {"$value": "{color.x}"}, "x": {"$value": "{color.bg}"}}
            },
        }
        cases = [
            Case(f"light {k}", self.with_value(["light"], v))
            for k, v in light_values.items()
        ]
        if "light" in self.tokens:
            cases.append(Case("light deleted", self.without(["light"])))
        self.check(cases)

    def test_numbered_scales(self):
        keyss = {
            "zero pad": ["01", "1", "001"],
            "spaces": [" 3 ", "\t2\n", " 1　"],
            "signs": ["+5", "-2", "0"],
            "underscores": ["1_0", "2"],
            "bad underscore": ["1__0"],
            "trailing underscore": ["1_"],
            "arabic": ["١", "٢٠"],
            "superscript": ["²"],
            "roman": ["Ⅻ"],
            "fraction": ["½"],
            "word": ["x"],
            "empty": [""],
            "null char": ["1\u0000"],
            "big": ["9" * 40, "1"],
            "too big": ["9" * 4301],
            "too big spaced": [" " + "9" * 4301 + " "],
            "too big junk": ["9" * 4301 + "x"],
            "too big underscored": ["1_" * 2200 + "1"],
            "long junk": ["x" * 300],
            "equal": ["2", "02", "+2", "1"],
            "negative zero": ["-0", "0"],
            "unicode space": [" 1 "],
            "fs": ["\u001c1"],
            "del": ["1\u007f"],
        }
        cases = []
        for scale in (["space"], ["hit"], ["motion", "duration"]):
            for name, keys in keyss.items():
                value = {
                    k: {
                        "$value": f"{i}px"
                        if scale != ["motion", "duration"]
                        else f"{i}ms"
                    }
                    for i, k in enumerate(keys)
                }
                cases.append(
                    Case(f"{'.'.join(scale)} {name}", self.with_value(scale, value))
                )
            containers = {
                "list ints": [1, 0],
                "list strs": ["1", "0"],
                "list bools": [True, False],
                "list floats": [1.5, 0.5],
                "list nan": [float("nan")],
                "list inf": [float("inf")],
                "list nested": [[1]],
                "list dict": [{}],
                "list null": [None],
                "list big": [10**30],
                "list negative": [-1, -2],
                "list values": [{"$value": "1px"}, 1],
                "list of entries": [{"$value": "3px"}, {"$value": "4px"}, 0],
                "str": "12",
                "empty str": "",
                "int": 5,
                "null": None,
                "float": 1.5,
                "values not str": {"1": {"$value": 1}},
                "values list": {"1": {"$value": ["px"]}},
                "value no unit": {"1": {"$value": "13"}},
                "value unit twice": {"1": {"$value": "13pxpx"}},
                "value ms px": {"1": {"$value": "13mspx"}},
                "entry str": {"1": "x"},
                "entry missing value": {"1": {}},
                "big float key": {"1e3": {"$value": "1px"}},
            }
            for name, value in containers.items():
                cases.append(
                    Case(f"{'.'.join(scale)} {name}", self.with_value(scale, value))
                )
        self.check(cases)

    def test_font_sizes(self):
        keys = [
            "a-b-c",
            "-x",
            "x-",
            "x--y",
            "-",
            "",
            "mobile-xl-2",
            "a-ß",
            "a-ǆx",
            "a-ʼn",
            "a-aΣ",
            "a-AΣ",
            "a-AΣA",
            "a-A'Σ'",
            "a-Σ",
            "a-ΣΣ",
            "a-İx",
            "a-ͅΣ",
            "a-x­Σ",
            "a-ﬁ",
            "a-ᾀ",
            "a-123",
            "a-é",
            "a-\ud800",
            "a-\udfffx",
        ]
        cases = []
        for i, k in enumerate(keys):
            cases.append(
                Case(
                    f"font size key {i} {k!r}",
                    self.with_value(["font", "size"], {k: {"$value": "13px"}}),
                )
            )
        values = [None, 13, "13", "13px", "px", "", "\ud800px", ["13px"]]
        for i, v in enumerate(values):
            cases.append(
                Case(
                    f"font size value {i} {v!r}",
                    self.with_value(["font", "size"], {"x": {"$value": v}}),
                )
            )
        for name, v in {
            "list": [],
            "str": "a",
            "null": None,
            "entry list": {"x": []},
            "entry null": {"x": None},
        }.items():
            cases.append(
                Case(f"font size {name}", self.with_value(["font", "size"], v))
            )
        self.check(cases)

    def test_easing(self):
        values = {
            "three": [0, 0, 1],
            "five": [0, 0, 1, 1, 2],
            "empty": [],
            "str4": "abcd",
            "str3": "abc",
            "str5": "abcde",
            "dict4": {"a": 1, "b": 2, "c": 3, "d": 4},
            "dict2": {"a": 1, "b": 2},
            "int": 4,
            "null": None,
            "float": 1.0,
            "true": True,
            "floats": [0.1, 1e16, 1e-5, -0.0],
            "ints": [10**30, -0, 1, 2],
            "consts": [float("nan"), float("inf"), float("-inf"), 5e-324],
            "mixed": [True, None, "x", 1.5],
            "nested": [[1, [2, "a"]], {"k": [None]}, {}, []],
            "quotes": ["it's", 'say "hi"', "both'\"", "\\"],
            "unprintable": ["\x00\x7f", "​­", "\ud800", "\U000e0001\n\t\r"],
            "nested strs": [
                ["\x00", "\ud800"],
                {"é": "é"},
                {"it's": 'a"b'},
                ["\U0001f600"],
            ],
            "raw surrogate": ["\udc80", 0, 0, 0],
        }
        cases = []
        k = next(iter(self.tokens["motion"]["easing"]))
        for name, v in values.items():
            cases.append(
                Case(
                    f"easing {name}",
                    self.with_value(["motion", "easing", k, "$value"], v),
                )
            )
            raw = json.loads(self.with_value(["motion", "easing", k, "$value"], v))
            # Unescaped: real UTF-8, or (for a surrogate) bytes that are not.
            text = dumps(raw, ensure_ascii=False).encode("utf-8", "surrogatepass")
            cases.append(Case(f"easing {name} unescaped", text))
        for name, v in {
            "list": [],
            "str": "x",
            "null": None,
            "entry list": {"x": []},
        }.items():
            cases.append(
                Case(
                    f"easing container {name}", self.with_value(["motion", "easing"], v)
                )
            )
        # As deep as json.loads lets a list sit under motion.easing.<k>.$value.
        for n in (9988, 9989):
            nested = "[" * n + "]" * n
            doc = self.with_value(["motion", "easing", k, "$value"], "@@").replace(
                '"@@"', f"[{nested}, 0, 0, 0]"
            )
            cases.append(Case(f"easing nested {n}", doc))
        self.check(cases)

    def test_surrogates_reach_the_output(self):
        t = self.tree()
        t["font"]["size"] = {
            "x-\ud800": {"$value": "1px"},
            "y\udc00\udc01": {"$value": "\ud800\ud801px"},
        }
        cases = [Case("surrogates in output", dumps(t))]
        t["font"]["size"] = {"x": {"$value": "1px"}}
        k = next(iter(t["motion"]["easing"]))
        t["motion"]["easing"][k]["$value"] = ["\udfff", 1, 2, 3]
        cases.append(Case("surrogate repr in output", dumps(t)))
        t = self.tree()
        t["color"]["bg"]["$value"] = "#\ud800\ud800\ud800\ud800\ud800\ud800"
        cases.append(Case("surrogate colour", dumps(t)))
        self.check(cases)

    # -- unicode sweeps -------------------------------------------------

    def interesting_code_points(self):
        out = []
        for c in range(0x110000):
            if 0xD800 <= c <= 0xDFFF:
                continue
            ch = chr(c)
            if (
                ch.upper() != ch
                or ch.lower() != ch
                or ch.capitalize() != ch
                or gen_unicode_tables.cased(c)
                or gen_unicode_tables.case_ignorable(c)
            ):
                out.append(c)
        return out

    def test_unicode_case_sweep(self):
        cps = self.interesting_code_points()
        self.assertGreater(len(cps), 3000)
        ignorable = [c for c in cps if gen_unicode_tables.case_ignorable(c)]
        cased = [c for c in cps if gen_unicode_tables.cased(c)]
        size = {}
        for c in cps:
            ch = chr(c)
            size[f"k-{ch}"] = {"$value": "1px"}
            size[f"k-a{ch}"] = {"$value": "1px"}
        for c in ignorable + cased[:: max(1, len(cased) // 400)]:
            ch = chr(c)
            for k in (
                f"k-A{ch}{SIGMA}",
                f"k-A{SIGMA}{ch}",
                f"k-A{SIGMA}{ch}A",
                f"k-{ch}{SIGMA}",
            ):
                size[k] = {"$value": "1px"}
        cases = []
        t = self.tree()
        t["font"]["size"] = size
        cases.append(Case("case sweep, escaped", dumps(t), ok=True))
        cases.append(Case("case sweep, utf-8", dumps(t, ensure_ascii=False), ok=True))
        # upper() through argb: six characters to a colour, every colour slot.
        uppers = [c for c in cps if chr(c).upper() != chr(c)]
        slots = [("color",) + tuple(p.split(".")[1:]) for p in self.colour_paths()]
        per = 6 * len(slots)
        for start in range(0, len(uppers), per):
            chunk = uppers[start : start + per]
            t = self.tree()
            for i, path in enumerate(slots):
                text = "".join(chr(c) for c in chunk[6 * i : 6 * i + 6])
                self._set_colour(t, path, "#" + (text + "abcdef")[:6])
            cases.append(
                Case(f"upper sweep {start}", dumps(t, ensure_ascii=False), ok=True)
            )
        self.check(cases)

    def colour_paths(self):
        import re

        with open(os.path.join(HERE, "gen_tokens.py"), encoding="utf-8") as f:
            src = f.read()
        return [
            p
            for p in re.findall(r'\("\w+", "([\w.-]+)"\)', src)
            if p.startswith("color.")
        ]

    def _set_colour(self, t, path, value):
        node = t
        for p in path:
            node = node.setdefault(p, {})
        node["$value"] = value

    def test_unicode_repr_and_int_sweep(self):
        # Every code point through repr(): str() of a list in the easing
        # curve reprs the strs in it (a bare str would print as itself).
        k = next(iter(self.tokens["motion"]["easing"]))
        step = 0x44000
        parts = [
            ["".join(chr(c) for c in range(lo, min(lo + step, 0x110000)))]
            for lo in range(0, 0x110000, step)
        ]
        self.assertEqual(len(parts), 4)
        value = ["path", ["mixed", 1, None, {"k'": ['"', "\\"]}]] + parts
        cases = [
            Case(
                "repr sweep",
                self.with_value(["motion", "easing", k, "$value"], parts),
                ok=True,
            ),
            Case(
                "repr nesting",
                self.with_value(["motion", "easing", k, "$value"], value[:4]),
                ok=True,
            ),
        ]
        # Every decimal digit and every space int() skips, as sort keys
        # (below 128 only ASCII whitespace is skipped: \x1c-\x1f are not).
        space = {}
        for c in range(0x110000):
            ch = chr(c)
            if ch.isdecimal():
                space[f"1{ch}"] = {"$value": f"{c}px"}
            elif ch.isspace() and (c >= 128 or ch in " \t\n\x0b\x0c\r"):
                space[f"{ch}1{ch}"] = {"$value": f"{c}px"}
        cases.append(Case("int sweep", self.with_value(["space"], space), ok=True))
        # And a few that int() refuses: other digits and numerics.
        for c in (0xB2, 0xB9, 0x2155, 0x216B, 0x3007, 0x1F100, 0x2460, 0x0F33, 0x19DA):
            cases.append(
                Case(
                    f"int refuses U+{c:04X}",
                    self.with_value(["space"], {f"1{chr(c)}": {"$value": "1px"}}),
                )
            )
        self.check(cases)

    # -- the harness itself ---------------------------------------------

    def test_unicode_tables_are_current(self):
        with open(
            os.path.join(HERE, "src", "unicode_tables.rs"), encoding="utf-8"
        ) as f:
            self.assertEqual(
                f.read(),
                gen_unicode_tables.render(),
                "regenerate src/unicode_tables.rs with gen_unicode_tables.py",
            )

    def test_differences_are_caught(self):
        base = {"code": 0, "stdout": "", "stderr": "", "files": {"out.kt": b"x"}}
        tb = TRACEBACK + "  File \"x\", line 1\nKeyError: 'a'\n"
        self.assertEqual(differences(base, dict(base)), [])
        for change in (
            {"code": 1},
            {"stdout": "x"},
            {"stderr": "x"},
            {"files": {"out.kt": b"y"}},
            {"files": {}},
        ):
            self.assertTrue(differences(base, {**base, **change}), change)
        a = {**base, "stderr": tb}
        self.assertEqual(
            differences(
                a, {**base, "stderr": tb.replace('"x", line 1', '"y", line 9')}
            ),
            [],
        )
        self.assertTrue(differences(a, {**base, "stderr": tb.replace("'a'", "'b'")}))
        self.assertTrue(differences(a, {**base, "stderr": "KeyError: 'a'\n"}))


if __name__ == "__main__":
    unittest.main()
