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
"""merge-queue-stats-rs, the Rust port, against merge_queue_stats.py: same
exit code, stdout, stderr and GitHub requests, on every input here.

    bazel test //tools/merge-queue-stats:merge_queue_stats_rs_parity_test

Both run as programs under the name merge_queue_stats.py, pointed by
GITHUB_API_URL at one fake GitHub API on localhost. Each run sends its own
token, which tells the server which made-up GitHub to answer from and lets
it log each program's requests (method, path, JSON body, headers) apart.

The inputs:
  * every timeline in merge_queue_stats_test.py: its calls to queue_times,
    ejections and report are recorded with their arguments and served back
    as GitHub's answers, so the whole report is compared, not the pieces;
  * pagination of all three listings, and GitHub failing in each way the
    script reports (HTTP errors, GraphQL errors, missing keys, a refused
    connection) or does not (bad JSON, wrong types, a bad API URL);
  * where the token comes from (GH_TOKEN, GITHUB_TOKEN, a fake gh, none);
  * command lines argparse treats specially, at several terminal widths,
    and a few hundred --since/--until values built from the pieces
    datetime.fromisoformat reads;
  * timelines built to break the counting (naive and offset timestamps,
    values of the wrong type, ties) and a hundred random ones.

When Python crashes, its traceback names its own files and lines, which
the port cannot have, so there the exception's class is compared.
"""

import copy
import datetime as dt
import http.server
import json
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest
from concurrent.futures import ThreadPoolExecutor
from urllib.parse import parse_qs, urlsplit

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import merge_queue_stats as m  # noqa: E402
import merge_queue_stats_test as mt  # noqa: E402

TRACEBACK = b"Traceback (most recent call last):"
REPO = "VitruvianSoftware/vitruvian-core"


def _binary():
    path = os.environ.get("MERGE_QUEUE_STATS_RS", "")
    if not path:
        raise unittest.SkipTest(
            "MERGE_QUEUE_STATS_RS is not set; run this under bazel test"
        )
    return os.path.abspath(path)


class Raw:
    """A response sent as it is: a status, bytes, and an optional reason."""

    def __init__(self, body=b"", status=200, reason=None):
        self.body, self.status, self.reason = body, status, reason


class World:
    """One made-up GitHub: answers keyed the way the script asks."""

    def __init__(self, pulls_pages=None, runs=None, commits=None):
        # graphql: json.dumps(after) -> response; runs: (status, page) ->
        # response; commits: page -> response.
        self.graphql = pulls_pages or {"null": page([])}
        self.runs = runs or {}
        self.commits = commits or {}


def page(nodes, has_next=False, cursor=None):
    return {
        "data": {
            "search": {
                "pageInfo": {"hasNextPage": has_next, "endCursor": cursor},
                "nodes": nodes,
            }
        }
    }


def world_for(pulls, runs=(), reverts=(), per_page=50):
    """A GitHub that lists these pull requests, failed runs and reverts."""
    graphql = {}
    chunks = [pulls[i : i + per_page] for i in range(0, len(pulls), per_page)] or [[]]
    after = None
    for i, chunk in enumerate(chunks):
        last = i == len(chunks) - 1
        cursor = None if last else f"cursor-{i}"
        graphql[json.dumps(after)] = page(chunk, has_next=not last, cursor=cursor)
        after = cursor
    run_pages = {("failure", 1): {"workflow_runs": list(runs)}}
    commits = {1: [{"commit": {"message": r + "\n\nbody"}} for r in reverts]}
    return World(graphql, run_pages, commits)


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
                tok = auth[len("Bearer ") :] if auth.startswith("Bearer ") else auth
                case, _, kind = tok.rpartition(".")
                n = int(self.headers.get("Content-Length") or 0)
                raw = self.rfile.read(n) if n else b""
                try:
                    body = json.loads(raw) if raw else None
                except ValueError:
                    body = raw.decode("latin-1")
                with server.lock:
                    server.logs.setdefault(tok, []).append(
                        (
                            method,
                            self.path,
                            body,
                            case,
                            self.headers.get("Accept"),
                            self.headers.get("X-GitHub-Api-Version"),
                        )
                    )
                    world = server.worlds.get(case)
                answer = server.route(world, method, self.path, body)
                if not isinstance(answer, Raw):
                    answer = Raw(json.dumps(answer).encode())
                if answer.reason is None:
                    self.send_response(answer.status)
                else:
                    self.send_response(answer.status, answer.reason)
                self.send_header("Content-Length", str(len(answer.body)))
                self.end_headers()
                self.wfile.write(answer.body)

            def do_GET(self):
                self._answer("GET")

            def do_POST(self):
                self._answer("POST")

        class Threading(http.server.ThreadingHTTPServer):
            # The default backlog of 5 overflows when eight cases run at once.
            request_queue_size = 256

        self.httpd = Threading(("127.0.0.1", 0), Handler)
        self.httpd.daemon_threads = True
        self.url = f"http://127.0.0.1:{self.httpd.server_address[1]}"
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()

    def close(self):
        self.httpd.shutdown()
        self.httpd.server_close()

    @staticmethod
    def route(world, method, path, body):
        if world is None:
            return Raw(b"no such world", 404, "Not Found")
        parts = urlsplit(path)
        q = parse_qs(parts.query)
        if method == "POST" and parts.path.endswith("/graphql"):
            after = (
                (body or {}).get("variables", {}).get("after")
                if isinstance(body, dict)
                else None
            )
            return world.graphql.get(json.dumps(after), page([]))
        if parts.path.endswith("/actions/runs"):
            key = (q.get("status", [""])[0], int(q.get("page", ["1"])[0]))
            return world.runs.get(key, {"workflow_runs": []})
        if parts.path.endswith("/commits"):
            return world.commits.get(int(q.get("page", ["1"])[0]), [])
        return Raw(b"{}", 404, "Not Found")


def _exception(stderr):
    last = stderr.rstrip(b"\n").rsplit(b"\n", 1)[-1]
    return last.split(b":", 1)[0]


class Parity(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = Server()
        cls.tmp = tempfile.mkdtemp(prefix="merge-queue-stats-parity-")
        cls.programs = {}
        for kind in ("py", "rs"):
            d = os.path.join(cls.tmp, kind)
            os.makedirs(d)
            cls.programs[kind] = os.path.join(d, "merge_queue_stats.py")
        shutil.copy(os.path.join(HERE, "merge_queue_stats.py"), cls.programs["py"])
        shutil.copy(_binary(), cls.programs["rs"])
        os.chmod(cls.programs["rs"], 0o755)
        cls.fakebin = os.path.join(cls.tmp, "fakebin")
        os.makedirs(cls.fakebin)
        cls.count = 0
        cls.count_lock = threading.Lock()

    @classmethod
    def tearDownClass(cls):
        cls.server.close()
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def _case_id(self):
        with self.count_lock:
            type(self).count += 1
            return f"case{type(self).count}"

    def run_one(self, kind, case, case_id):
        env = {
            "PATH": case.get("path", "/nonexistent"),
            "PYTHONUTF8": "1",
            "PYTHONDONTWRITEBYTECODE": "1",
            "GITHUB_API_URL": case.get("api", self.server.url),
        }
        token = case.get("token", "default")
        if token is not None:
            env["GH_TOKEN"] = f"{case_id}.{kind}"
        if case.get("api") is None and "api" in case:
            del env["GITHUB_API_URL"]
        env.update(case.get("env", {}))
        for k, v in list(env.items()):
            env[k] = v.replace("{TOKEN}", f"{case_id}.{kind}")
        argv = [self.programs[kind]] + case["args"]
        if kind == "py":
            # -S: the script needs only the standard library, and skipping
            # site keeps several hundred runs inside a small test's minute.
            argv = [sys.executable, "-S"] + argv
        proc = subprocess.run(argv, env=env, capture_output=True, timeout=60)
        with self.server.lock:
            log = self.server.logs.pop(f"{case_id}.{kind}", [])
        return {
            "code": proc.returncode,
            "stdout": proc.stdout,
            "stderr": proc.stderr,
            "log": log,
        }

    def run_case(self, case):
        case_id = self._case_id()
        with self.server.lock:
            self.server.worlds[case_id] = case.get("world", World())
        py = self.run_one("py", case, case_id)
        rs = self.run_one("rs", case, case_id)
        return py, rs

    def check(self, case, py, rs):
        what = f"{case.get('label', '')}: {case['args']}"
        mask = case.get("mask")
        if mask:
            for r in (py, rs):
                r["stdout"] = mask(r["stdout"])
                r["log"] = [mask(repr(e).encode()) for e in r["log"]]
        self.assertEqual(py["code"], rs["code"], f"{what}\npy={py}\nrs={rs}")
        self.assertEqual(
            py["stdout"],
            rs["stdout"],
            f"{what}\npy={py['stdout']!r}\nrs={rs['stdout']!r}",
        )
        self.assertEqual(py["log"], rs["log"], what)
        if TRACEBACK in py["stderr"]:
            self.assertIn(
                TRACEBACK, rs["stderr"], f"{what}\n{py['stderr']!r}\n{rs['stderr']!r}"
            )
            self.assertEqual(
                _exception(py["stderr"]),
                _exception(rs["stderr"]),
                f"{what}\n{py['stderr']!r}\n{rs['stderr']!r}",
            )
        else:
            self.assertEqual(py["stderr"], rs["stderr"], what)

    def compare_many(self, cases):
        with ThreadPoolExecutor(8) as pool:
            results = list(pool.map(self.run_case, cases))
        for case, (py, rs) in zip(cases, results):
            self.check(case, py, rs)
        return results

    # -- the unit tests' own timelines ---------------------------------

    def recorded_calls(self):
        """Run merge_queue_stats_test.py, recording each call it makes."""
        calls = []
        names = ("queue_times", "ejections", "report", "percentile")
        originals = {n: getattr(m, n) for n in names}

        def recorder(name):
            def call(*args):
                calls.append((name, copy.deepcopy(args)))
                return originals[name](*args)

            return call

        for n in names:
            setattr(m, n, recorder(n))
        try:
            suite = unittest.defaultTestLoader.loadTestsFromModule(mt)
            with open(os.devnull, "w") as devnull:
                result = unittest.TextTestRunner(stream=devnull).run(suite)
            self.assertTrue(result.wasSuccessful())
        finally:
            for n, fn in originals.items():
                setattr(m, n, fn)
        return calls

    def test_unit_test_timelines(self):
        cases = []
        seen = 0
        for name, args in self.recorded_calls():
            if name == "percentile":
                values, fraction = args
                # A percentile is printed for 0.5 and 0.9 of last-entry
                # times: make PRs whose waits are these values, in minutes.
                pulls = [
                    mt.pr(
                        (mt.SINCE + dt.timedelta(days=1, minutes=v)).strftime(
                            "%Y-%m-%dT%H:%M:%SZ"
                        ),
                        mt.added(
                            (mt.SINCE + dt.timedelta(days=1)).strftime(
                                "%Y-%m-%dT%H:%M:%SZ"
                            )
                        ),
                    )
                    for v in values
                ]
                cases.append(
                    {
                        "label": f"percentile {values}",
                        "world": world_for(pulls),
                        "args": self.window(),
                    }
                )
                continue
            seen += 1
            if name == "report":
                repo, since, until, pulls, runs, reverts = args
            else:
                pulls, since, until = args
                repo, runs, reverts = REPO, [], []
            cases.append(
                {
                    "label": name,
                    "world": world_for(pulls, runs, reverts),
                    "args": [
                        "--since",
                        since.strftime("%Y-%m-%dT%H:%M:%S"),
                        "--until",
                        until.strftime("%Y-%m-%dT%H:%M:%S"),
                        "--repo",
                        repo,
                    ],
                }
            )
        self.assertGreaterEqual(seen, 4)
        self.compare_many(cases)

    @staticmethod
    def window(since="2026-10-05", until="2026-10-19"):
        return ["--since", since, "--until", until]

    # -- the listings and their pages ----------------------------------

    def test_pagination(self):
        pulls = [
            mt.pr(
                f"2026-10-{6 + i % 10:02d}T0{i % 10}:30:00Z",
                mt.added(f"2026-10-{6 + i % 10:02d}T0{i % 10}:{i % 30:02d}:00Z"),
            )
            for i in range(120)
        ]
        w = world_for(pulls, per_page=50)
        runs = [{"name": f"wf{i % 7}", "conclusion": "failure"} for i in range(100)]
        w.runs = {
            ("failure", 1): {"workflow_runs": runs},
            ("failure", 2): {"workflow_runs": runs[:3]},
            ("timed_out", 1): {
                "workflow_runs": [{"name": "wf9", "conclusion": "timed_out"}] * 100
            },
            ("timed_out", 2): {"workflow_runs": []},
        }
        w.commits = {
            1: [
                {"commit": {"message": 'Revert "a"\r\nx' if i % 9 == 0 else "feat: x"}}
                for i in range(100)
            ],
            2: [
                {"commit": {"message": "Revert b\u2028tail"}},
                {"commit": {"message": "Revert"}},
            ],
        }
        # Cursors of every JSON type go back to GitHub as they came.
        odd = World(
            {
                "null": page([], True, 7),
                "7": page([], True, {"a": [1, "\u00e9"]}),
                json.dumps({"a": [1, "\u00e9"]}): page([], True, ""),
                '""': page([{}], False, None),
            }
        )
        self.compare_many(
            [
                {"label": "pages", "world": w, "args": self.window()},
                {"label": "cursors", "world": odd, "args": self.window()},
            ]
        )

    # -- GitHub failing -------------------------------------------------

    def test_failures(self):
        good = world_for(
            [mt.pr("2026-10-10T00:10:00Z", mt.added("2026-10-10T00:00:00Z"))]
        )

        def with_graphql(answer):
            return World({"null": answer})

        def with_runs(answer):
            w = world_for([])
            w.runs = {("failure", 1): answer}
            return w

        def with_commits(answer):
            w = world_for([])
            w.commits = {1: answer}
            return w

        worlds = {
            "http 500": with_graphql(Raw(b"oops", 500)),
            "http 404 custom reason": with_graphql(Raw(b"{}", 404, "Gone Fishing")),
            "graphql errors": with_graphql(
                {"errors": [{"message": "it's bad", "n": 1.5, "x": None}]}
            ),
            "graphql error string": with_graphql({"errors": "plain"}),
            "graphql errors empty": with_graphql(
                {
                    "errors": [],
                    "data": {
                        "search": {"pageInfo": {"hasNextPage": False}, "nodes": []}
                    },
                }
            ),
            "no data": with_graphql({}),
            "data null": with_graphql({"data": None}),
            "no search": with_graphql({"data": {}}),
            "no nodes": with_graphql(
                {"data": {"search": {"pageInfo": {"hasNextPage": False}}}}
            ),
            "nodes dict": with_graphql(
                {
                    "data": {
                        "search": {
                            "pageInfo": {"hasNextPage": False},
                            "nodes": {"k": 1},
                        }
                    }
                }
            ),
            "nodes int": with_graphql(
                {"data": {"search": {"pageInfo": {"hasNextPage": False}, "nodes": 3}}}
            ),
            "no pageInfo": with_graphql({"data": {"search": {"nodes": []}}}),
            "list body": with_graphql([1, 2]),
            "bad json": with_graphql(Raw(b"{not json")),
            "empty body": with_graphql(Raw(b"")),
            "bom": with_graphql(Raw(b"\xef\xbb\xbf" + json.dumps(page([])).encode())),
            "utf-16": with_graphql(Raw(json.dumps(page([])).encode("utf-16"))),
            "utf-16-le": with_graphql(Raw(json.dumps(page([])).encode("utf-16-le"))),
            "not utf-8": with_graphql(Raw(b'{"a": "\xff"}')),
            "no workflow_runs": with_runs({}),
            "runs list": with_runs([]),
            "workflow_runs dict": with_runs({"workflow_runs": {"name": 1}}),
            "workflow_runs int": with_runs({"workflow_runs": 5}),
            "runs 503": with_runs(Raw(b"", 503)),
            "commits dict": with_commits({"message": "x"}),
            "commit without message": with_commits([{"commit": {}}]),
            "commit without commit": with_commits([{}]),
            "commit message int": with_commits([{"commit": {"message": 4}}]),
            "commits int": with_commits(7),
            "commits 401": with_commits(Raw(b"", 401)),
            "good": good,
        }
        cases = [
            {"label": k, "world": w, "args": self.window()} for k, w in worlds.items()
        ]
        cases += [
            {"label": "refused", "api": "http://127.0.0.1:9", "args": self.window()},
            {"label": "empty api", "api": "", "args": self.window()},
            {"label": "no scheme", "api": "localhost", "args": self.window()},
            {
                "label": "trailing slash",
                "api": self.server.url + "/",
                "world": good,
                "args": self.window(),
            },
            {
                "label": "api path",
                "api": self.server.url + "/api/v3",
                "world": good,
                "args": self.window(),
            },
        ]
        self.compare_many(cases)

    def test_tokens(self):
        gh_ok = os.path.join(self.tmp, "gh-ok")
        gh_bad = os.path.join(self.tmp, "gh-bad")
        for d, body in (
            (gh_ok, '#!/bin/sh\nprintf "  %s\\n" "$CASE_TOKEN"\n'),
            (gh_bad, "#!/bin/sh\nexit 1\n"),
        ):
            os.makedirs(d, exist_ok=True)
            with open(os.path.join(d, "gh"), "w") as f:
                f.write(body)
            os.chmod(os.path.join(d, "gh"), 0o755)
        good = world_for(
            [mt.pr("2026-10-10T00:10:00Z", mt.added("2026-10-10T00:00:00Z"))]
        )
        cases = [
            {"label": "no token", "token": None, "args": self.window()},
            {
                "label": "empty GH_TOKEN",
                "token": None,
                "env": {"GH_TOKEN": ""},
                "args": self.window(),
            },
            {
                "label": "GITHUB_TOKEN",
                "token": None,
                "env": {"GITHUB_TOKEN": "{TOKEN}"},
                "world": good,
                "args": self.window(),
            },
            {
                "label": "gh",
                "token": None,
                "path": gh_ok,
                "env": {"CASE_TOKEN": "{TOKEN}"},
                "world": good,
                "args": self.window(),
            },
            {"label": "gh fails", "token": None, "path": gh_bad, "args": self.window()},
        ]
        self.compare_many(cases)

    # -- command lines --------------------------------------------------

    def test_command_lines(self):
        lines = [
            [],
            ["-h"],
            ["--help"],
            ["--he"],
            ["-hx"],
            ["--since"],
            ["--since", "2026-10-05"] + ["--until", "nope"],
            ["--since", "bad"],
            ["--since=2026-10-05", "--until=2026-10-19"],
            ["--s", "2026-10-05", "--u", "2026-10-19", "--r", "o/r"],
            ["--since", "2026-10-05", "--until", "2026-10-19", "extra"],
            ["--since", "2026-10-05", "--until", "2026-10-19", "--", "--repo"],
            ["--until", "2026-10-19"],
            ["--bogus"],
            ["--since", "bad", "-h"],
            ["-h", "--since", "bad"],
            ["--repo"],
            ["--since", "2026-10-05", "--until", "2026-10-19", "--repo", ""],
            ["--since", "2026-10-05", "--since", "2026-10-06", "--until", "2026-10-19"],
            ["--since", "-1"],
            ["--=1"],
            ["--since", "2026-10-05", "--until", "2026-10-19", "--repo=a b/c"],
            ["--since", "2026-10-05", "--until", "2026-10-19", "--repo=\u00e9/x"],
            ["--since", "2026-10-05", "--until", "2026-10-19", "--repo=o/r#frag"],
            ["--since", "2026-10-05", "--until", "2026-10-19", "--repo=o/r?x=1"],
        ]
        # Every line at the default width; the ones that print usage or help
        # at other widths too, since argparse wraps to the terminal.
        wraps = [
            [],
            ["-h"],
            ["--he"],
            ["-hx"],
            ["--since"],
            ["--since", "bad"],
            ["--bogus"],
            ["--=1"],
        ]
        cases = []
        for args in lines:
            widths = (None, "20", "50", "100", "1", "x") if args in wraps else (None,)
            for columns in widths:
                env = {} if columns is None else {"COLUMNS": columns}
                cases.append({"label": f"cols={columns}", "args": args, "env": env})
        self.compare_many(cases)

    def test_until_defaults_to_now(self):
        stamp = re.compile(
            rb"\d{4}-\d\d-\d\d[ T]\d\d:\d\d(:\d\d)?Z?|\d{4}-\d\d-\d\dT\d\d%3A\d\d%3A\d\dZ|\d+\.\d/day"
        )
        case = {
            "label": "now",
            "args": ["--since", "2026-10-05"],
            "mask": lambda b: stamp.sub(b"<T>", b),
        }
        self.compare_many([case])

    def test_isoformat_values(self):
        values = [
            "2026-10-05",
            "20261005",
            "2026-W41",
            "2026-W41-1",
            "2026W411",
            "2026W41",
            "2026-W53",
            "2020-W53-7",
            "2025-W53",
            "2026-W00",
            "2026-W41-8",
            "9999-W52-7",
            "9999-W53",
            "2026-10-05T12",
            "2026-10-05T1230",
            "2026-10-05T12:30",
            "2026-10-05T12:30:15",
            "2026-10-05T12:30:15.5",
            "2026-10-05T12:30:15,123456789",
            "2026-10-05 12:30",
            "2026-10-05x12:30",
            "2026-10-05\u00e912:30",
            "2026-10-05\U0001f60012:30",
            "2026-10-05\u00e9\u00e912:30",
            "2026-10-05T12:30Z",
            "2026-10-05T12:30+05:00",
            "2026-10-05T12:30-0530",
            "2026-10-05T12:30+05",
            "2026-10-05T12:30+05:30:10.5",
            "2026-10-05T12:30+23:59",
            "2026-10-05T12:30+24:00",
            "2026-10-05T12:30+05:99",
            "2026-10-05T24:00",
            "2026-10-05T23:59:60",
            "2026-02-30",
            "2024-02-29",
            "2023-02-29",
            "2026-10-5",
            "2026-1005",
            "202610-05",
            "2026-10-05T",
            "2026-10-05T12:3",
            "2026-10-05T12:30:1",
            "2026-10-05T12:30:15.",
            "2026-10-05Z",
            "2026-10-05T12Z",
            "2026-10-05T12.5",
            "2026-10-05T12:30:15:00",
            "2026-10-05T1230150",
            "2026-10-05T12301500",
            "2026-W41-112",
            "2026-W41-1T12",
            "2026-W411T12",
            "2026W41T12",
            "2026W4112",
            "2026-W41T12",
            "2026-W41-1-12",
            "2026-10-05T12+05.5",
            "2026-10-05T12-05",
            "2026-10-05T12:30Zx",
            "2026-10-05T12:30+05:30Z",
            "2026-10-05T+05",
            "2026-10-05TZ",
            "2026-10-05T12:30z",
            " 2026-10-05",
            "2026-10-05 ",
            "\uff12\uff10\uff12\uff16-10-05",
            "1000-01-01",
            "9999-12-31T23:59:59.999999",
            "2026-10",
            "2026-1",
            "202",
            "",
            "2026-10-05T12:30:15.000001-00:00:00.000001",
            "2026-10-05T00:00-23:59:59.999999",
        ]
        rng = random.Random(7)
        pieces = [
            "2026",
            "-",
            "10",
            "05",
            "W",
            "41",
            "1",
            "T",
            " ",
            ":",
            "12",
            "30",
            "15",
            ".",
            ",",
            "5",
            "123456",
            "Z",
            "+",
            "-",
            "05",
            "00",
            "x",
            "9",
        ]
        curated = list(values)
        for _ in range(80):
            values.append(
                "".join(rng.choice(pieces) for _ in range(rng.randint(3, 10)))
            )
        # ISO week dates, where the date ends depends on what follows.
        values += [
            "2026-W41-1012:00",
            "2026-W41-1112",
            "2026-W41-11230",
            "2026W41112",
            "2026W411T1230",
        ]
        for _ in range(60):
            v = (
                rng.choice(["2026-W", "2026W", "2020-W", "2015-W"])
                + rng.choice(["41", "53", "01", "00", "5"])
                + "".join(
                    rng.choice(["-", "1", "7", "12", ":", "T", "0", "Z", "+05"])
                    for _ in range(rng.randint(0, 6))
                )
            )
            values.append(v)
        for _ in range(60):
            v = (
                "2026-10-05"
                + rng.choice(["T", " ", "x", ""])
                + "".join(rng.choice(pieces[8:]) for _ in range(rng.randint(0, 8)))
            )
            values.append(v)
        good = world_for(
            [mt.pr("2026-10-10T00:10:00Z", mt.added("2026-10-10T00:00:00Z"))]
        )
        cases = []
        # Both options go through the same type; --until gets the hand-picked
        # values, --since every one.
        for v in values:
            cases.append(
                {
                    "label": f"since {v!r}",
                    "world": good,
                    "args": ["--since", v, "--until", "2026-10-19T00:00"],
                }
            )
        for v in curated:
            cases.append(
                {
                    "label": f"until {v!r}",
                    "world": good,
                    "args": ["--since", "2026-10-01", "--until", v],
                }
            )
        self.compare_many(cases)

    # -- timelines built to break the counting --------------------------

    def test_odd_timelines(self):
        added, removed, pr = mt.added, mt.removed, mt.pr
        bot = m.QUEUE_BOT

        def nodes(*events):
            return {
                "number": 1,
                "mergedAt": "2026-10-10T01:00:00Z",
                "timelineItems": {"nodes": list(events)},
            }

        timelines = {
            "naive merge": [pr("2026-10-10T01:00:00", added("2026-10-10T00:00:00Z"))],
            "naive added": [pr("2026-10-10T01:00:00Z", added("2026-10-10T00:00:00"))],
            "naive removal": [
                pr(None, removed("2026-10-10T00:00:00", "failed_checks"))
            ],
            "offsets": [
                pr(
                    "2026-10-10T06:00:00+05:00",
                    added("2026-10-09T23:00:00-01:00"),
                    added("2026-10-10T00:15:00.250000Z"),
                )
            ],
            "tie minutes": [
                pr("2026-10-10T00:10:15Z", added("2026-10-10T00:00:00Z")),
                pr("2026-10-10T00:10:45Z", added("2026-10-10T00:00:00Z")),
            ],
            "bad merge time": [pr("yesterday", added("2026-10-10T00:00:00Z"))],
            "merge time int": [pr(5)],
            "no timeline": [{"mergedAt": "2026-10-10T01:00:00Z"}],
            "no timeline unmerged": [{"mergedAt": None}],
            "pr list": [["x"]],
            "pr string": ["x"],
            "event string": [nodes("x")],
            "no createdAt": [nodes({"__typename": "AddedToMergeQueueEvent"})],
            "reasons": [
                nodes(
                    removed("2026-10-10T00:01:00Z", "  "),
                    removed("2026-10-10T00:02:00Z", None),
                    removed("2026-10-10T00:03:00Z", "MERGED"),
                    removed("2026-10-10T00:04:00Z", " merged\u3000"),
                    removed("2026-10-10T00:05:00Z", "\u00e9chec"),
                    removed("2026-10-10T00:06:00Z", "b"),
                    removed("2026-10-10T00:07:00Z", "a"),
                    removed("2026-10-10T00:08:00Z", "b"),
                    removed("2026-10-10T00:09:00Z", "a"),
                    removed("2026-10-10T00:10:00Z", "\x1cz\x1f"),
                )
            ],
            "reason int": [nodes(removed("2026-10-10T00:01:00Z", 5))],
            "actors": [
                nodes(
                    {
                        "__typename": "RemovedFromMergeQueueEvent",
                        "createdAt": "2026-10-10T00:01:00Z",
                        "reason": "x",
                        "actor": None,
                    },
                    {
                        "__typename": "RemovedFromMergeQueueEvent",
                        "createdAt": "2026-10-10T00:01:00Z",
                        "reason": "x",
                    },
                    {
                        "__typename": "RemovedFromMergeQueueEvent",
                        "createdAt": "2026-10-10T00:01:00Z",
                        "reason": "x",
                        "actor": {"login": None},
                    },
                    {
                        "__typename": "RemovedFromMergeQueueEvent",
                        "createdAt": "2026-10-10T00:01:00Z",
                        "reason": "y",
                        "actor": {"login": bot},
                    },
                )
            ],
            "actor string": [
                nodes(
                    {
                        "__typename": "RemovedFromMergeQueueEvent",
                        "createdAt": "2026-10-10T00:01:00Z",
                        "reason": "x",
                        "actor": "bot",
                    }
                )
            ],
            "window edges": [
                pr("2026-10-05T00:00:00Z", added("2026-10-04T23:00:00Z")),
                pr("2026-10-19T00:00:00Z", added("2026-10-18T23:00:00Z")),
                pr(
                    "2026-10-18T23:59:59.999999Z",
                    added("2026-10-18T23:00:00Z"),
                    removed("2026-10-05T00:00:00Z", "a"),
                    removed("2026-10-19T00:00:00Z", "b"),
                ),
            ],
            "many": [
                pr(
                    f"2026-10-10T{h:02d}:{(h * 7) % 60:02d}:00Z",
                    added("2026-10-10T00:00:00Z"),
                )
                for h in range(1, 24)
            ],
        }
        runs_sets = {
            "run names": [
                {"name": 1, "conclusion": "failure"},
                {"name": 1.0, "conclusion": "failure"},
                {"name": True, "conclusion": "timed_out"},
                {"name": None, "conclusion": "failure"},
                {"name": "CI", "conclusion": "failure"},
                {"name": "B", "conclusion": "failure"},
                {"name": "B", "conclusion": "failure"},
                {"name": "x", "conclusion": ["failure"]},
                {"conclusion": "success"},
            ],
            "run name list": [{"name": [1], "conclusion": "failure"}],
            "run no name": [{"conclusion": "failure"}],
            "run string": ["x"],
        }
        cases = [
            {"label": k, "world": world_for(v), "args": self.window()}
            for k, v in timelines.items()
        ]
        cases += [
            {"label": k, "world": world_for([], runs=v), "args": self.window()}
            for k, v in runs_sets.items()
        ]
        cases += [
            {
                "label": "backwards window",
                "world": world_for(timelines["many"]),
                "args": self.window("2026-10-19", "2026-10-05"),
            },
            {
                "label": "empty window",
                "world": world_for(timelines["many"]),
                "args": self.window("2026-10-10", "2026-10-10"),
            },
            {
                "label": "huge window",
                "world": world_for(timelines["many"]),
                "args": self.window("1000-01-01", "9999-12-31T23:59:59.999999"),
            },
            {
                "label": "tiny window",
                "world": world_for(timelines["many"]),
                "args": self.window(
                    "2026-10-10T00:00:00", "2026-10-10T00:00:00.000001"
                ),
            },
        ]
        self.compare_many(cases)

    def test_random_timelines(self):
        rng = random.Random(20261019)
        reasons = [
            "failed_checks",
            "checks_timed_out",
            "merged",
            "dequeued",
            " merged ",
            "",
            None,
            "MERGE_CONFLICT",
        ]
        who = [m.QUEUE_BOT, m.QUEUE_BOT, "james", None]
        base = dt.datetime(2026, 10, 3, tzinfo=dt.timezone.utc)

        def at():
            t = base + dt.timedelta(
                seconds=rng.randint(0, 20 * 86400),
                microseconds=rng.choice([0, 0, 0, 250000, 1]),
            )
            offset = rng.choice([None, None, 0, 330, -420])
            if offset is None:
                return (
                    t.strftime("%Y-%m-%dT%H:%M:%S")
                    + (f".{t.microsecond:06d}" if t.microsecond else "")
                    + "Z"
                )
            tz = dt.timezone(dt.timedelta(minutes=offset))
            return t.astimezone(tz).isoformat()

        cases = []
        for n in range(60):
            pulls = []
            for _ in range(rng.randint(0, 25)):
                events = []
                for _ in range(rng.randint(0, 6)):
                    if rng.random() < 0.5:
                        events.append(mt.added(at()))
                    else:
                        events.append(
                            mt.removed(at(), rng.choice(reasons), who=rng.choice(who))
                        )
                pulls.append(mt.pr(at() if rng.random() < 0.8 else None, *events))
            runs = [
                {
                    "name": rng.choice(["CI", "Presubmit", "Delivery", "Images"]),
                    "conclusion": rng.choice(["failure", "timed_out", "success", None]),
                }
                for _ in range(rng.randint(0, 12))
            ]
            reverts = [f'Revert "feat: {i}"' for i in range(rng.randint(0, 3))]
            cases.append(
                {
                    "label": f"random {n}",
                    "world": world_for(pulls, runs, reverts),
                    "args": self.window(),
                }
            )
        self.compare_many(cases)


if __name__ == "__main__":
    unittest.main()
