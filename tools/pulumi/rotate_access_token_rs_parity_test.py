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
"""rotate-access-token, the Rust port, against rotate_access_token.py: same
exit code, stdout, stderr, Pulumi Cloud requests and gh calls, on every input
here.

    bazel test //tools/pulumi:rotate_access_token_rs_parity_test

Both run as programs under the name rotate_access_token.py, pointed by
PULUMI_API at one fake Pulumi Cloud on localhost, with a fake `gh` first on
PATH that logs its arguments and stdin. Each run signs in with its own
token, which tells the server which made-up Pulumi Cloud to answer from and
keeps each program's requests apart; the token the fake mints is that token
plus "~new", so the new token's calls are told apart too.

The inputs:
  * every case in rotate_access_token_test.py, run as a whole program;
  * where the operator's token comes from: the environment, pulumi login's
    credentials file, and that file missing, malformed or the wrong shape;
  * Pulumi Cloud failing on each call (HTTP errors, a refused connection,
    bodies that are not JSON or lack a key, a bad PULUMI_API) and gh failing
    or missing;
  * cleanup's prompts answered y, yes, YES, n, nothing, or not at all (EOF),
    and token lists built to break it;
  * command lines argparse treats specially, at several terminal widths.

When Python crashes, its traceback names its own files and lines, which the
port cannot have, so there the exception's class (the last line up to ':')
is compared, and that both print a traceback.
"""

import http.server
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
TRACEBACK = "Traceback (most recent call last):"
REPO = "VitruvianSoftware/vitruvian-core"
LABEL = f"github-actions: {REPO}"

FAKE_GH = """#!/bin/sh
# PATH holds only this script; the tools it uses are found here.
PATH=/usr/bin:/bin
{
  printf 'ARGV'
  for a in "$@"; do printf ' [%s]' "$a"; done
  printf '\\nSTDIN ['
  cat
  printf ']\\n'
} >> "$GH_LOG"
if [ -n "$GH_STDERR" ]; then printf '%b' "$GH_STDERR" >&2; fi
exit "${GH_EXIT:-0}"
"""


def _binary():
    path = os.environ.get("ROTATE_ACCESS_TOKEN_RS", "")
    if not path:
        raise unittest.SkipTest(
            "ROTATE_ACCESS_TOKEN_RS is not set; run this under bazel test"
        )
    return os.path.abspath(path)


class Raw:
    """A response sent as it is: a status and bytes."""

    def __init__(self, body=b"", status=200):
        self.body, self.status = body, status


def tok(id_, desc, created, last_used=0, **extra):
    t = {"id": id_, "description": desc, "created": created, "lastUsed": last_used}
    t.update(extra)
    return t


class World:
    """One made-up Pulumi Cloud.

    user / new_user: the login the operator's / the minted token signs in as.
    tokens: what GET /api/user/tokens lists.
    answers: {(method, path, who): Raw or JSON} overriding any answer; who is
    "op" or "new"; None matches both.
    """

    def __init__(self, tokens=(), user="ipv1337", new_user=None, answers=None):
        self.tokens = list(tokens)
        self.user = user
        self.new_user = user if new_user is None else new_user
        self.answers = answers or {}


class Server:
    def __init__(self):
        self.worlds = {}
        self.logs = {}
        self.lock = threading.Lock()
        server = self

        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, format, *args):
                pass

            def _answer(self, method):
                auth = self.headers.get("Authorization", "")
                token = auth[len("token ") :] if auth.startswith("token ") else auth
                parts = token.split("~")
                case = parts[0]
                run = "~".join(parts[:2])
                who = "new" if len(parts) > 2 and parts[2] == "new" else "op"
                n = int(self.headers.get("Content-Length") or 0)
                raw = self.rfile.read(n) if n else b""
                with server.lock:
                    server.logs.setdefault(run, []).append(
                        (
                            method,
                            self.path,
                            raw.decode("utf-8", "replace"),
                            who,
                            auth.startswith("token "),
                            self.headers.get("Accept"),
                            self.headers.get("Content-Type"),
                        )
                    )
                    world = server.worlds.get(case)
                answer = server.route(world, method, self.path, who, token)
                if not isinstance(answer, Raw):
                    answer = Raw(json.dumps(answer).encode())
                self.send_response(answer.status)
                self.send_header("Content-Length", str(len(answer.body)))
                self.end_headers()
                self.wfile.write(answer.body)

            def do_GET(self):
                self._answer("GET")

            def do_POST(self):
                self._answer("POST")

            def do_DELETE(self):
                self._answer("DELETE")

        class Threading(http.server.ThreadingHTTPServer):
            request_queue_size = 256

        self.httpd = Threading(("127.0.0.1", 0), Handler)
        self.httpd.daemon_threads = True
        self.url = f"http://127.0.0.1:{self.httpd.server_address[1]}"
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()

    def close(self):
        self.httpd.shutdown()
        self.httpd.server_close()

    @staticmethod
    def route(world, method, path, who, token):
        if world is None:
            return Raw(b"no such world", 404)
        for key in ((method, path, who), (method, path, None)):
            if key in world.answers:
                return world.answers[key]
        if (method, path) == ("GET", "/api/user"):
            return {"githubLogin": world.new_user if who == "new" else world.user}
        if (method, path) == ("POST", "/api/user/tokens"):
            return {"id": "new-id", "tokenValue": token + "~new"}
        if (method, path) == ("GET", "/api/user/tokens"):
            return {"tokens": world.tokens}
        if method == "DELETE" and path.startswith("/api/user/tokens/"):
            return Raw(b"", 204)
        return Raw(b'{"message": "not found"}', 404)


class Case:
    """One run of both programs.

    args: the command line. env: extra environment (PULUMI_ACCESS_TOKEN set
    to "TOKEN" is replaced with the run's token). creds: the text of
    ~/.pulumi/credentials.json ({API} and {TOKEN} filled in), "DIR" for a
    directory there, or None for no file. stdin: what the prompts read.
    gh: None for no gh on PATH, else (exit code, stderr).
    """

    def __init__(
        self,
        name,
        args=(),
        world=None,
        env=None,
        creds=None,
        stdin=b"",
        gh=(0, ""),
        api=None,
    ):
        self.name = name
        self.args = list(args)
        self.world = world or World()
        self.env = {"PULUMI_ACCESS_TOKEN": "TOKEN"} if env is None else env
        self.creds = creds
        self.stdin = stdin
        self.gh = gh
        self.api = api


def compare_runs(test, case, py, rs):
    """Fail `test` unless the two runs agree. A run is a dict of exit code,
    stdout, stderr, requests and gh log."""
    for key in ("code", "stdout", "requests", "gh"):
        test.assertEqual(py[key], rs[key], f"{case.name}: {key} differs")
    if py["stderr"].startswith(TRACEBACK) or rs["stderr"].startswith(TRACEBACK):
        test.assertTrue(py["stderr"].startswith(TRACEBACK), f"{case.name}: py stderr")
        test.assertTrue(rs["stderr"].startswith(TRACEBACK), f"{case.name}: rs stderr")
        last = lambda s: s.rstrip("\n").rsplit("\n", 1)[-1].split(":", 1)[0]  # noqa: E731
        test.assertEqual(
            last(py["stderr"]), last(rs["stderr"]), f"{case.name}: exception class"
        )
    else:
        test.assertEqual(py["stderr"], rs["stderr"], f"{case.name}: stderr differs")


class Parity(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.binary = _binary()
        cls.tmp = tempfile.mkdtemp()
        cls.programs = {}
        for kind in ("py", "rs"):
            d = os.path.join(cls.tmp, kind)
            os.makedirs(d)
            cls.programs[kind] = os.path.join(d, "rotate_access_token.py")
        shutil.copy(os.path.join(HERE, "rotate_access_token.py"), cls.programs["py"])
        shutil.copy(cls.binary, cls.programs["rs"])
        os.chmod(cls.programs["rs"], 0o755)
        cls.ghbin = os.path.join(cls.tmp, "ghbin")
        cls.nobin = os.path.join(cls.tmp, "nobin")
        os.makedirs(cls.ghbin)
        os.makedirs(cls.nobin)
        gh = os.path.join(cls.ghbin, "gh")
        with open(gh, "w") as f:
            f.write(FAKE_GH)
        os.chmod(gh, os.stat(gh).st_mode | stat.S_IEXEC)
        cls.server = Server()
        cls.counter = 0
        cls.counter_lock = threading.Lock()

    @classmethod
    def tearDownClass(cls):
        cls.server.close()
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def run_one(self, kind, case, case_id, api):
        token = f"{case_id}~{kind}"
        home = os.path.join(self.tmp, f"{case_id}-{kind}")
        os.makedirs(home)
        if case.creds is not None:
            os.makedirs(os.path.join(home, ".pulumi"))
            path = os.path.join(home, ".pulumi", "credentials.json")
            if case.creds == "DIR":
                os.makedirs(path)
            else:
                with open(path, "w", encoding="utf-8") as f:
                    f.write(case.creds.replace("{API}", api).replace("{TOKEN}", token))
        gh_log = os.path.join(home, "gh.log")
        env = {
            "PATH": self.ghbin if case.gh is not None else self.nobin,
            "HOME": home,
            "PULUMI_API": api,
            "GH_LOG": gh_log,
            "PYTHONUTF8": "1",
            "PYTHONDONTWRITEBYTECODE": "1",
        }
        if case.gh is not None:
            env["GH_EXIT"] = str(case.gh[0])
            env["GH_STDERR"] = case.gh[1]
        for k, v in case.env.items():
            env[k] = token if v == "TOKEN" else v
        cmd = [self.programs[kind]] + case.args
        if kind == "py":
            cmd = [sys.executable] + cmd
        done = subprocess.run(
            cmd, input=case.stdin, capture_output=True, env=env, timeout=60
        )
        gh = ""
        if os.path.exists(gh_log):
            with open(gh_log, encoding="utf-8") as f:
                gh = f.read()
        with self.server.lock:
            requests = list(self.server.logs.get(token, []))
        # The token itself differs between the runs; what was done with it
        # must not.
        mark = f"{case_id}~{kind}"
        return {
            "code": done.returncode,
            "stdout": done.stdout.decode("utf-8", "replace").replace(mark, "TOKEN"),
            "stderr": done.stderr.decode("utf-8", "replace").replace(mark, "TOKEN"),
            "requests": requests,
            "gh": gh.replace(mark, "TOKEN"),
        }

    def run_case(self, case):
        with self.counter_lock:
            Parity.counter += 1
            case_id = f"c{Parity.counter}"
        with self.server.lock:
            self.server.worlds[case_id] = case.world
        api = case.api or self.server.url
        py = self.run_one("py", case, case_id, api)
        rs = self.run_one("rs", case, case_id, api)
        return case, py, rs

    def check(self, cases):
        with ThreadPoolExecutor(max_workers=8) as pool:
            results = list(pool.map(self.run_case, cases))
        for case, py, rs in results:
            with self.subTest(case.name):
                compare_runs(self, case, py, rs)
        return results

    # ----------------------------------------------------------------------

    def test_rotate_cases_from_the_unit_tests(self):
        results = self.check(
            [
                Case("stores new token in both stores via stdin"),
                Case(
                    "new token signs in as someone else",
                    world=World(new_user="someone-else"),
                ),
                Case("gh failure is reported", gh=(1, "nope\n")),
            ]
        )
        # The cases did what the unit tests say, not merely the same thing.
        (_, ok, _), (_, other, _), (_, gh_fail, _) = results
        self.assertEqual(ok["code"], 0)
        self.assertEqual(ok["gh"].count("STDIN [TOKEN~new]"), 2)
        self.assertIn("[--app] [dependabot]", ok["gh"])
        self.assertNotIn("~new", ok["stdout"] + ok["stderr"])
        self.assertEqual(other["code"], 1)
        self.assertEqual(other["gh"], "")
        self.assertEqual(gh_fail["code"], 1)
        self.assertIn("gh could not store PULUMI_ACCESS_TOKEN: nope", gh_fail["stderr"])

    def test_rotate_edges(self):
        e404 = Raw(b'{"message": "nope"}', 404)
        self.check(
            [
                Case("gh stderr with CRLF and padding", gh=(3, "  bad\\r\\nworse \\n")),
                Case("gh missing from PATH", gh=None),
                Case(
                    "ROTATE_REPO override",
                    env={"PULUMI_ACCESS_TOKEN": "TOKEN", "ROTATE_REPO": "acme/thing"},
                ),
                Case(
                    "empty ROTATE_REPO",
                    env={"PULUMI_ACCESS_TOKEN": "TOKEN", "ROTATE_REPO": ""},
                ),
                Case(
                    "401 on whoami",
                    world=World(answers={("GET", "/api/user", "op"): Raw(b"", 401)}),
                ),
                Case(
                    "500 on mint",
                    world=World(
                        answers={("POST", "/api/user/tokens", None): Raw(b"x", 500)}
                    ),
                ),
                Case(
                    "403 when the new token signs in",
                    world=World(answers={("GET", "/api/user", "new"): Raw(b"", 403)}),
                ),
                Case(
                    "whoami body not JSON",
                    world=World(answers={("GET", "/api/user", None): Raw(b"<html>")}),
                ),
                Case(
                    "whoami empty body",
                    world=World(answers={("GET", "/api/user", None): Raw(b"")}),
                ),
                Case(
                    "whoami lacks githubLogin",
                    world=World(answers={("GET", "/api/user", None): {"login": "x"}}),
                ),
                Case(
                    "whoami answers a list",
                    world=World(answers={("GET", "/api/user", None): ["x"]}),
                ),
                Case(
                    "whoami login is a number",
                    world=World(
                        answers={("GET", "/api/user", None): {"githubLogin": 7}}
                    ),
                ),
                Case(
                    "whoami login int vs float",
                    world=World(
                        answers={
                            ("GET", "/api/user", "op"): {"githubLogin": 7},
                            ("GET", "/api/user", "new"): {"githubLogin": 7.0},
                        }
                    ),
                ),
                Case("unicode login", world=World(user="jérôme \U0001f600")),
                Case(
                    "mint lacks tokenValue",
                    world=World(
                        answers={("POST", "/api/user/tokens", None): {"id": "x"}}
                    ),
                ),
                Case(
                    "mint lacks id",
                    world=World(
                        answers={
                            ("POST", "/api/user/tokens", None): {"tokenValue": "zz"}
                        }
                    ),
                ),
                Case(
                    "mint answers a number",
                    world=World(answers={("POST", "/api/user/tokens", None): 5}),
                ),
                Case(
                    "mint body utf-16",
                    world=World(
                        answers={
                            ("POST", "/api/user/tokens", None): Raw(
                                '{"id": 1, "tokenValue": "q"}'.encode("utf-16")
                            )
                        }
                    ),
                ),
                Case(
                    "404 everywhere",
                    world=World(answers={("GET", "/api/user", None): e404}),
                ),
                Case("unreachable API", api="http://127.0.0.1:1"),
                Case("API without a scheme", api="api.example"),
                Case("API with an unknown scheme", api="gopher://x"),
                Case("API with no host", api="http://"),
                Case("API with a space", api="http://127.0.0.1:1/a b"),
            ]
        )

    def test_operator_token_sources(self):
        good = '{"accessTokens": {"{API}": "{TOKEN}"}}'
        self.check(
            [
                Case("credentials file", env={}, creds=good),
                Case(
                    "credentials file, empty env token",
                    env={"PULUMI_ACCESS_TOKEN": ""},
                    creds=good,
                ),
                Case(
                    "env token wins over the file",
                    creds='{"accessTokens": {"{API}": "wrong"}}',
                ),
                Case("no credentials file", env={}),
                Case("credentials is a directory", env={}, creds="DIR"),
                Case("credentials not JSON", env={}, creds="{nope"),
                Case("credentials with a BOM", env={}, creds="﻿" + good),
                Case("credentials lack accessTokens", env={}, creds="{}"),
                Case(
                    "credentials lack this API",
                    env={},
                    creds='{"accessTokens": {"https://other": "x"}}',
                ),
                Case("credentials are a list", env={}, creds="[1]"),
                Case("accessTokens is null", env={}, creds='{"accessTokens": null}'),
                Case("accessTokens is a string", env={}, creds='{"accessTokens": "x"}'),
                Case(
                    "token is a number", env={}, creds='{"accessTokens": {"{API}": 5}}'
                ),
                Case("token has a newline", env={"PULUMI_ACCESS_TOKEN": "a\nb"}),
                Case("token is not latin-1", env={"PULUMI_ACCESS_TOKEN": "€"}),
            ]
        )

    def test_cleanup_cases_from_the_unit_tests(self):
        a = tok("a", f"{LABEL} (rotated 2026-01-01)", "2026-01-01")
        b = tok("b", f"{LABEL} (rotated 2026-06-01)", "2026-06-01")
        c = tok("c", "devcontainer", "2025-10-08")
        me = tok(
            "me", "Generated by pulumi login", "2025-10-08", last_used=time.time() - 10
        )
        results = self.check(
            [
                Case(
                    "deletes older CI tokens, keeps the newest",
                    ["--cleanup", "--yes"],
                    World([a, b, c]),
                ),
                Case(
                    "never deletes unlabelled tokens",
                    ["--cleanup", "--yes"],
                    World([c]),
                ),
                Case(
                    "deletes an unlabelled token when named",
                    ["--cleanup", "--yes", "--delete-old", "c"],
                    World([c]),
                ),
                Case(
                    "refuses the current CI token",
                    ["--cleanup", "--yes", "--delete-old", "b"],
                    World([b]),
                ),
                Case(
                    "skips a recently used token",
                    ["--cleanup", "--yes", "--delete-old", "me"],
                    World([me]),
                ),
                Case(
                    "unknown id fails", ["--cleanup", "--delete-old", "nope"], World([])
                ),
                Case(
                    "asks before deleting: n",
                    ["--cleanup"],
                    World([a, b]),
                    stdin=b"n\n",
                ),
                Case("--delete-old needs --cleanup", ["--delete-old", "x"]),
            ]
        )
        deletes = [
            [r[1] for r in py["requests"] if r[0] == "DELETE"] for _, py, _ in results
        ]
        self.assertEqual(
            deletes,
            [["/api/user/tokens/a"], [], ["/api/user/tokens/c"], [], [], [], [], []],
        )
        self.assertEqual(results[-1][1]["code"], 2)

    def test_cleanup_edges(self):
        now = time.time()
        lab = lambda d: f"{LABEL} (rotated {d})"  # noqa: E731
        a = tok("a", lab("2026-01-01"), "2026-01-01T00:00:00Z")
        b = tok("b", lab("2026-06-01"), "2026-06-01T00:00:00Z")
        z = tok("z", lab("2025-01-01"), "2025-01-01")
        c = tok("c", "devcontainer", "2025-10-08")
        u = tok("ué", "café \U0001f600", "éééééééééééé")
        three = [b, a, z]
        cases = [
            Case(f"answer {ans!r}", ["--cleanup"], World(three), stdin=ans)
            for ans in (
                b"y\n",
                b"yes\n",
                b"  YES \r\n",
                b"Y",
                b"\n",
                b"no\n",
                b"y\rn\r",
                b"y\nn\n",
                b"n\ny\n",
            )
        ]
        cases += [
            Case("EOF at the first prompt", ["--cleanup"], World(three), stdin=b""),
            Case("EOF at the second prompt", ["--cleanup"], World(three), stdin=b"y\n"),
            Case("nothing to delete with one CI token", ["--cleanup"], World([b, c])),
            Case("nothing labelled: lists tokens", ["--cleanup"], World([c, u])),
            Case("nothing at all", ["--cleanup"], World([])),
            Case(
                "several unknown ids, sorted",
                [
                    "--cleanup",
                    "--delete-old",
                    "zz",
                    "--delete-old",
                    "aa",
                    "--delete-old=zz",
                ],
                World([c]),
            ),
            Case(
                "named older CI token is deleted twice",
                ["--cleanup", "--yes", "--delete-old", "a"],
                World(three),
            ),
            Case(
                "named token and listing with unicode",
                ["--cleanup", "--yes", "--delete-old", "ué"],
                World([u]),
            ),
            Case(
                "old lastUsed float",
                ["--cleanup", "--yes"],
                World([tok("o", lab("1"), "1", last_used=now - 1000.5), b]),
            ),
            Case(
                "lastUsed just inside the window",
                ["--cleanup", "--yes"],
                World([tok("o", lab("1"), "1", last_used=now - 200), b]),
            ),
            Case(
                "lastUsed in the future",
                ["--cleanup", "--yes"],
                World([tok("o", lab("1"), "1", last_used=now + 5000), b]),
            ),
            Case(
                "lastUsed is a string",
                ["--cleanup", "--yes"],
                World([tok("o", lab("1"), "1", last_used="soon"), b]),
            ),
            Case(
                "lastUsed is false",
                ["--cleanup", "--yes"],
                World([tok("o", lab("1"), "1", last_used=False), b]),
            ),
            Case(
                "404 on DELETE",
                ["--cleanup", "--yes"],
                World(
                    three,
                    answers={("DELETE", "/api/user/tokens/z", None): Raw(b"", 404)},
                ),
            ),
            Case(
                "DELETE answers JSON",
                ["--cleanup", "--yes"],
                World(
                    three,
                    answers={("DELETE", "/api/user/tokens/z", None): {"ok": True}},
                ),
            ),
            Case(
                "DELETE answers garbage",
                ["--cleanup", "--yes"],
                World(
                    three, answers={("DELETE", "/api/user/tokens/z", None): Raw(b"??")}
                ),
            ),
            Case(
                "500 on listing",
                ["--cleanup"],
                World(answers={("GET", "/api/user/tokens", None): Raw(b"", 500)}),
            ),
            Case(
                "listing lacks tokens",
                ["--cleanup"],
                World(answers={("GET", "/api/user/tokens", None): {}}),
            ),
            Case(
                "tokens is null",
                ["--cleanup"],
                World(answers={("GET", "/api/user/tokens", None): {"tokens": None}}),
            ),
            Case(
                "tokens is an empty dict",
                ["--cleanup"],
                World(answers={("GET", "/api/user/tokens", None): {"tokens": {}}}),
            ),
            Case(
                "token lacks id",
                ["--cleanup"],
                World([{"description": "x", "created": "1"}]),
            ),
            Case(
                "token lacks created",
                ["--cleanup"],
                World([{"id": "x", "description": "x"}]),
            ),
            Case(
                "token lacks description",
                ["--cleanup", "--yes"],
                World([{"id": "x", "created": "2020-01-01"}]),
            ),
            Case(
                "description is null",
                ["--cleanup"],
                World([{"id": "x", "description": None, "created": "1"}]),
            ),
            Case("token is a string", ["--cleanup"], World(["abc"])),
            Case(
                "id is a number",
                ["--cleanup", "--yes"],
                World([tok(5, lab("1"), "1"), b]),
            ),
            Case("id is a list", ["--cleanup"], World([tok(["x"], "d", "1")])),
            Case(
                "created is a number", ["--cleanup"], World([tok("x", "d", 20251008)])
            ),
            Case(
                "created is a list",
                ["--cleanup"],
                World([tok("x", "d", list(range(12)))]),
            ),
            Case(
                "created numbers sort",
                ["--cleanup", "--yes"],
                World(
                    [
                        tok("p", lab("2"), 2),
                        tok("q", lab("1"), 1.5),
                        tok("r", lab("3"), True),
                    ]
                ),
            ),
            Case(
                "created of mixed types",
                ["--cleanup", "--yes"],
                World([tok("p", lab("2"), 2), tok("q", lab("1"), "1")]),
            ),
            Case(
                "ties keep list order",
                ["--cleanup", "--yes"],
                World(
                    [
                        tok("p", lab("x"), "2026"),
                        tok("q", lab("y"), "2026"),
                        tok("r", lab("z"), "2026"),
                    ]
                ),
            ),
            Case(
                "label is a prefix only",
                ["--cleanup", "--yes"],
                World(
                    [
                        tok("p", "x " + lab("1"), "1"),
                        tok("q", LABEL + "x", "2"),
                        tok("r", LABEL, "3"),
                    ]
                ),
            ),
            Case(
                "ROTATE_REPO changes the label",
                ["--cleanup", "--yes"],
                World(three),
                env={"PULUMI_ACCESS_TOKEN": "TOKEN", "ROTATE_REPO": "acme/thing"},
            ),
            Case("unreachable API on cleanup", ["--cleanup"], api="http://127.0.0.1:1"),
        ]
        self.check(cases)

    def test_command_lines(self):
        lines = [
            ["-h"],
            ["--help"],
            ["--cleanup", "-h", "--bogus"],
            ["--bogus"],
            ["extra"],
            ["--delete-old"],
            ["--delete-old", "--yes"],
            ["--delete-old", "x", "--yes"],
            ["--cleanup=1"],
            ["--yes=no"],
            ["--cl", "--y"],
            ["--d", "x"],
            ["--", "--cleanup"],
            ["-x"],
            ["--cleanup", "--delete-old", "-5"],
            ["--cleanup", "--delete-old=", "--yes"],
        ]
        cases = []
        for args in lines:
            for cols in (None, "40", "200"):
                env = {"PULUMI_ACCESS_TOKEN": "TOKEN"}
                if cols:
                    env.update(COLUMNS=cols, LINES="24")
                cases.append(Case(f"{args} at {cols}", args, World([]), env=env))
        self.check(cases)


class Comparison(unittest.TestCase):
    """The comparison has teeth: differing runs fail it."""

    def test_differences_are_caught(self):
        base = {"code": 0, "stdout": "a\n", "stderr": "", "requests": [], "gh": ""}
        case = Case("x")

        class Probe(unittest.TestCase):
            def runTest(self):
                pass

        probe = Probe()
        compare_runs(probe, case, base, dict(base))
        for key, value in (
            ("code", 1),
            ("stdout", "b\n"),
            ("stderr", "  ✗ x\n"),
            ("requests", [("GET", "/", "", "op", True, None, None)]),
            ("gh", "ARGV\n"),
        ):
            with self.assertRaises(AssertionError, msg=key):
                compare_runs(probe, case, base, dict(base, **{key: value}))
        crash = lambda cls: dict(base, stderr=f"{TRACEBACK}\n  x\n{cls}: m\n")  # noqa: E731
        compare_runs(probe, case, crash("KeyError"), crash("KeyError"))
        with self.assertRaises(AssertionError):
            compare_runs(probe, case, crash("KeyError"), crash("TypeError"))
        with self.assertRaises(AssertionError):
            compare_runs(
                probe, case, crash("KeyError"), dict(base, stderr="KeyError: m\n")
            )


if __name__ == "__main__":
    unittest.main()
