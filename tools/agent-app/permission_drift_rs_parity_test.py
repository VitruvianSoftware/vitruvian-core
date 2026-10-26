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

"""permission-drift, the Rust port, against permission_drift.py: same exit
code, stdout, stderr and GitHub requests, on every input here.

    bazel test //tools/agent-app:permission_drift_rs_parity_test

Both run as programs under the name permission_drift.py, pointed by
GITHUB_API_URL at one fake GitHub API on localhost. Each run sends its own
token, which tells the server which made-up GitHub to answer from and lets
it log each program's requests (path and headers) apart.

The inputs:
  * every scenario in permission_drift_test.py: its calls to run() are
    recorded, and the server answers by asking that test's own fake GitHub,
    so the whole report is compared. Where the fake raised no error, the
    program's report must also be the one the unit test judged in-process;
  * the local-server cases in it (403, not JSON, unreachable, pages);
  * GitHub answering in shapes built to break the judging: ids as floats,
    strings, lists; duplicate installations; nulls; odd slugs; redirects,
    redirect loops, encodings, HTTP errors with and without a message;
  * agents.tsv and permissions.tsv broken every way load_* checks, and in
    ways Python's text mode reads specially (CRLF, BOM, \\f, odd digits);
  * where the token comes from (GH_TOKEN, GITHUB_TOKEN, a fake gh, none),
    and command lines argparse treats specially, at several widths.

When Python crashes, its traceback names its own files and lines, which
the port cannot have, so there the exception's class is compared.
"""

import copy
import http.server
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import permission_drift as pd  # noqa: E402
import permission_drift_test as pt  # noqa: E402

TRACEBACK = b"Traceback (most recent call last):"
ORG_PATH = "/orgs/VitruvianSoftware/installations?per_page=100"


def _binary():
    path = os.environ.get("PERMISSION_DRIFT_RS", "")
    if not path:
        raise unittest.SkipTest(
            "PERMISSION_DRIFT_RS is not set; run this under bazel test"
        )
    return os.path.abspath(path)


class Raw:
    """A response sent as it is: status, body bytes, extra headers."""

    def __init__(self, body=b"", status=200, headers=None):
        self.body = body if isinstance(body, bytes) else json.dumps(body).encode()
        self.status, self.headers = status, headers or {}


class Routes:
    """A made-up GitHub that answers each path from a table."""

    def __init__(self, routes):
        self.routes = routes

    def answer(self, path, base):
        found = self.routes.get(path)
        if found is None:
            return Raw({"message": "Not Found"}, 404)
        return found(base) if callable(found) else found


class FromFake:
    """A made-up GitHub that is one of permission_drift_test.py's fakes:
    each request is answered by calling its get()."""

    def __init__(self, fake):
        self.fake = fake

    def answer(self, path, base):
        try:
            body, nxt = self.fake.get(path)
        except pd.ReadError as err:
            m = re.search(r"HTTP (\d+) ?(.*)$", str(err))
            if m:
                return Raw({"message": m.group(2)}, int(m.group(1)))
            return Raw({"message": str(err)}, 500)
        headers = {"Link": f'<{base}{nxt}>; rel="next"'} if nxt else {}
        return Raw(body, 200, headers)


class Server:
    def __init__(self):
        self.worlds, self.logs = {}, {}
        self.lock = threading.Lock()
        server = self

        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_GET(self):  # noqa: N802 -- http.server's name
                auth = self.headers.get("Authorization", "")
                tok = auth[len("Bearer ") :] if auth.startswith("Bearer ") else auth
                case = tok.rpartition(".")[0]
                with server.lock:
                    server.logs.setdefault(tok, []).append(
                        (
                            self.command,
                            self.path,
                            auth,
                            self.headers.get("Accept"),
                            self.headers.get("X-GitHub-Api-Version"),
                            self.headers.get("User-Agent"),
                            self.headers.get("Host"),
                        )
                    )
                    world = server.worlds.get(case)
                if world is None:
                    answer = Raw({"message": "no such world"}, 404)
                else:
                    answer = world.answer(self.path, server.url)
                self.send_response(answer.status)
                for k, v in answer.headers.items():
                    self.send_header(k, v.replace("BASE", server.url))
                self.send_header("Content-Length", str(len(answer.body)))
                self.end_headers()
                self.wfile.write(answer.body)

        class Threading(http.server.ThreadingHTTPServer):
            request_queue_size = 256

        self.httpd = Threading(("127.0.0.1", 0), Handler)
        self.httpd.daemon_threads = True
        self.url = f"http://127.0.0.1:{self.httpd.server_address[1]}"
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()

    def close(self):
        self.httpd.shutdown()
        self.httpd.server_close()


def _exception(stderr):
    last = stderr.rstrip(b"\n").rsplit(b"\n", 1)[-1]
    return last.split(b":", 1)[0]


def _read(name):
    with open(os.path.join(HERE, name), encoding="utf-8") as f:
        return f.read()


def agents_tsv(agents=pt.AGENTS):
    return "".join(f"{n}\t{a}\t{i}\n" for n, a, i in agents)


def permissions_tsv(decl):
    return "".join(
        f"{name}\t{perm}\t{level}\n"
        for name, perms in decl.items()
        for perm, level in perms.items()
    )


def inst(name, app_id, inst_id, perms=None, **extra):
    out = pt.installation(name, app_id, inst_id, perms or dict(pt.BASE))
    out.update(extra)
    return out


def org(installs, total=None):
    return Raw(
        {
            "total_count": len(installs) if total is None else total,
            "installations": installs,
        }
    )


def apps_for(installs, requested=None):
    """The /apps/{slug} answers that agree with these installations."""
    routes = {}
    for i in installs:
        if isinstance(i, dict) and isinstance(i.get("app_slug"), str):
            perms = (requested or {}).get(i["app_slug"], i.get("permissions"))
            routes[f"/apps/{i['app_slug']}"] = Raw(
                {"id": i.get("app_id"), "permissions": perms}
            )
    return routes


def world(installs, requested=None, **routes):
    table = {ORG_PATH: org(installs)}
    table.update(apps_for(installs, requested))
    table.update(routes)
    return Routes(table)


class Parity(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = Server()
        cls.tmp = tempfile.mkdtemp(prefix="permission-drift-parity-")
        cls.programs = {}
        for kind in ("py", "rs"):
            d = os.path.join(cls.tmp, kind)
            os.makedirs(d)
            cls.programs[kind] = os.path.join(d, "permission_drift.py")
            # The default files sit beside each program, as they do in git.
            for f in ("agents.tsv", "permissions.tsv"):
                shutil.copy(os.path.join(HERE, f), d)
        shutil.copy(os.path.join(HERE, "permission_drift.py"), cls.programs["py"])
        shutil.copy(_binary(), cls.programs["rs"])
        os.chmod(cls.programs["rs"], 0o755)
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

    def _files(self, case, case_dir):
        """Write the case's files; --agents/--permissions point at them."""
        args = list(case.get("args", []))
        files = case.get("files", {})
        if (
            "agents" not in files
            and "permissions" not in files
            and case.get("default_files")
        ):
            return args
        agents = files.get("agents", agents_tsv())
        perms = files.get("permissions", permissions_tsv(pt.declared()))
        paths = {}
        for name, content in (("agents", agents), ("permissions", perms)):
            p = os.path.join(case_dir, f"{name}.tsv")
            if content is not None:
                with open(p, "wb") as f:
                    f.write(content if isinstance(content, bytes) else content.encode())
            paths[name] = p
        for name, p in paths.items():
            args = [a.replace("{" + name.upper() + "}", p) for a in args]
        if not case.get("raw_args"):
            args = [
                "--agents",
                paths["agents"],
                "--permissions",
                paths["permissions"],
            ] + args
        return args

    def run_one(self, kind, case, case_id):
        case_dir = os.path.join(self.tmp, case_id)
        os.makedirs(case_dir, exist_ok=True)
        args = self._files(case, case_dir)
        tok = f"{case_id}.{kind}"
        bindir = os.path.join(case_dir, "bin")
        if case.get("gh") is not None:
            os.makedirs(bindir, exist_ok=True)
            gh = os.path.join(bindir, "gh")
            with open(gh, "w") as f:
                f.write(case["gh"])
            os.chmod(gh, case.get("gh_mode", 0o755))
        env = {
            "PATH": bindir if case.get("gh") is not None else "/nonexistent",
            "PYTHONUTF8": "1",
            "PYTHONDONTWRITEBYTECODE": "1",
            "GITHUB_API_URL": self.server.url,
            "GH_TOKEN": tok,
            "FAKE_GH_TOKEN": tok,
            "COLUMNS": "80",
        }
        for k, v in case.get("env", {}).items():
            if v is None:
                env.pop(k, None)
            else:
                env[k] = (
                    v.replace("{TOKEN}", tok)
                    .replace("{CASE}", case_dir)
                    .replace("{API}", self.server.url)
                )
        argv = [self.programs[kind]] + [a.replace("{CASE}", case_dir) for a in args]
        if kind == "py":
            # -S: the script needs only the standard library.
            argv = [sys.executable, "-S"] + argv
        proc = subprocess.run(argv, env=env, capture_output=True, timeout=60)
        with self.server.lock:
            log = self.server.logs.pop(tok, [])
        # The token names the program; the rest of the request must match.
        log = [tuple(str(x).replace(tok, "TOKEN") for x in e) for e in log]
        return {
            "code": proc.returncode,
            "stdout": proc.stdout,
            "stderr": proc.stderr,
            "log": log,
        }

    def run_case(self, case):
        case_id = self._case_id()
        with self.server.lock:
            self.server.worlds[case_id] = case.get("world", world(pt.live()))
        py = self.run_one("py", case, case_id)
        rs = self.run_one("rs", case, case_id)
        return py, rs

    def check(self, case, py, rs):
        what = f"{case.get('label', '')}: {case.get('args', [])}"
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
            self.assertEqual(
                py["stderr"],
                rs["stderr"],
                f"{what}\npy={py['stderr']!r}\nrs={rs['stderr']!r}",
            )

    def compare_many(self, cases):
        with ThreadPoolExecutor(8) as pool:
            results = list(pool.map(self.run_case, cases))
        for case, (py, rs) in zip(cases, results):
            with self.subTest(case.get("label")):
                self.check(case, py, rs)
        return results

    # -- the checks themselves can fail --------------------------------

    def test_a_difference_fails_the_comparison(self):
        base = {"code": 0, "stdout": b"x", "stderr": b"", "log": []}
        for key, other in (
            ("code", 1),
            ("stdout", b"y"),
            ("stderr", b"e"),
            ("log", [1]),
        ):
            with self.assertRaises(AssertionError):
                self.check({}, base, dict(base, **{key: other}))
        crash = dict(base, stderr=TRACEBACK + b"\n  ...\nKeyError: 'x'\n")
        with self.assertRaises(AssertionError):
            self.check({}, crash, dict(crash, stderr=TRACEBACK + b"\nTypeError: x\n"))

    # -- the unit tests' own scenarios ----------------------------------

    def recorded_runs(self):
        """Run permission_drift_test.py's judging tests, recording each
        run(github, decl) with what the in-process check returned."""
        calls = []
        original = pt.run

        def recorder(github, decl=None):
            snapshot = copy.deepcopy(github)
            failed = []
            real_get = github.get

            def get(path):
                try:
                    return real_get(path)
                except pd.ReadError:
                    failed.append(path)
                    raise

            github.get = get
            code, report = original(github, decl)
            calls.append((snapshot, decl or pt.declared(), code, report, bool(failed)))
            return code, report

        pt.run = recorder
        try:
            suite = unittest.TestSuite()
            loader = unittest.TestLoader()
            for cls in (pt.Judging, pt.UnreadableGitHub):
                suite.addTests(loader.loadTestsFromTestCase(cls))
            result = unittest.TestResult()
            suite.run(result)
        finally:
            pt.run = original
        self.assertTrue(result.wasSuccessful(), result.failures + result.errors)
        self.assertEqual(
            len(calls), 16, "a scenario in permission_drift_test.py was not recorded"
        )
        return calls

    def test_every_scenario_in_the_unit_tests(self):
        calls = self.recorded_runs()
        cases = [
            {
                "label": f"unit scenario {n}",
                "world": FromFake(fake),
                "files": {"permissions": permissions_tsv(decl)},
            }
            for n, (fake, decl, _, _, _) in enumerate(calls)
        ]
        results = self.compare_many(cases)
        for (fake, decl, code, report, failed), (py, _) in zip(calls, results):
            # The replay is the scenario: same verdict as the unit test saw.
            self.assertEqual(py["code"], code, report)
            if not failed:
                self.assertEqual(
                    py["stdout"].decode(),
                    f"(reading GitHub as GH_TOKEN)\n{report}\n",
                )

    def test_the_local_server_cases_in_the_unit_tests(self):
        installs = pt.live()
        paged = {
            ORG_PATH: Raw(
                {"total_count": 3, "installations": installs[:2]},
                headers={"Link": f'<BASE{ORG_PATH}&page=2>; rel="next"'},
            ),
            ORG_PATH + "&page=2": Raw(
                {"total_count": 3, "installations": installs[2:]}
            ),
        }
        paged.update(apps_for(installs))
        self.compare_many(
            [
                {
                    "label": "403",
                    "world": Routes(
                        {
                            ORG_PATH: Raw(
                                {"message": "Resource not accessible by integration"},
                                403,
                            )
                        }
                    ),
                },
                {"label": "not json", "world": Routes({ORG_PATH: Raw(b"<html>")})},
                {
                    "label": "unreachable",
                    "env": {"GITHUB_API_URL": "http://127.0.0.1:1"},
                },
                {"label": "pages", "world": Routes(paged)},
            ]
        )

    # -- GitHub's answers -----------------------------------------------

    def test_answers_built_to_break_the_judging(self):
        L = pt.live
        B = dict(pt.BASE)

        def with_(i, **kw):
            out = L()
            out[i].update(kw)
            return out

        dup = L() + [inst("beacon", 101, 1001, dict(B, issues="write"))]
        apps_none = with_(0, app_slug=None)
        cases = [
            ("match", world(L())),
            ("ids as floats", world(with_(0, id=1001.0, app_id=101.0))),
            ("id as a string", world(with_(0, id="1001"))),
            ("id true", world(with_(0, id=True))),
            ("id as a list", world(with_(0, id=[1001]))),
            ("id as a dict", world(with_(1, id={"a": 1}))),
            ("an installation that is a string", world(L() + ["x"])),
            ("an installation that is null", world([None] + L())),
            ("the last of two equal ids wins", world(dup)),
            ("app id missing", world(with_(0, app_id=None))),
            ("app id another", world(with_(0, app_id=5, app_slug="other"))),
            ("suspended", world(with_(0, suspended_at="2026-10-01T00:00:00Z"))),
            ("suspended 0", world(with_(0, suspended_at=0))),
            ("suspended true", world(with_(0, suspended_at=True))),
            ("suspended empty", world(with_(0, suspended_at=""))),
            ("permissions null", world(with_(0, permissions=None))),
            ("permissions list", world(with_(0, permissions=["a"]))),
            ("a null permission", world(with_(0, permissions=dict(B, actions=None)))),
            (
                "values that are not strings",
                world(
                    with_(
                        0,
                        permissions=dict(
                            B, actions=1, issues={"x": [1, 2.5]}, admin=True, n=1e100
                        ),
                    )
                ),
            ),
            (
                "unicode permission",
                world(
                    with_(
                        1,
                        permissions=dict(B, actions="write", **{"é": "read", "Z": "x"}),
                    )
                ),
            ),
            (
                "slug null",
                world(apps_none, **{"/apps/None": Raw({"id": 101, "permissions": B})}),
            ),
            (
                "slug with a newline",
                world(L() + [inst("x", 300, 3000, app_slug="vitruvian-x-agent\n")]),
            ),
            ("slug an int", world(L() + [inst("x", 300, 3000, app_slug=5)])),
            ("slug zero", world(L() + [inst("x", 300, 3000, app_slug=0)])),
            ("slug empty list", world(L() + [inst("x", 300, 3000, app_slug=[])])),
            ("unlisted", world(L() + [inst("newbie", 200, 2000)])),
            ("unlisted no id", world(L() + [{"app_slug": "vitruvian-q-agent"}])),
            ("unlisted id a list", world(L() + [inst("q", [1], 2000)])),
            ("listed by float", world(L() + [inst("again", 104.0, 2000)])),
            (
                "near slug",
                world(
                    L()
                    + [
                        inst("x", 1, 2, app_slug="vitruvian--agent"),
                        inst("y", 1, 3, app_slug="vitruvian-A-agent"),
                        inst("z", 1, 4, app_slug="vitruvian-a-b-agent"),
                    ]
                ),
            ),
            (
                "total missing",
                Routes({ORG_PATH: Raw({"installations": L()}), **apps_for(L())}),
            ),
            ("total float", Routes({ORG_PATH: org(L(), total=3.0), **apps_for(L())})),
            ("total string", Routes({ORG_PATH: org(L(), total="3"), **apps_for(L())})),
            ("total true", Routes({ORG_PATH: org([], total=False), **apps_for(L())})),
            ("installations missing", Routes({ORG_PATH: Raw({"total_count": 0})})),
            (
                "installations a dict",
                Routes({ORG_PATH: Raw({"total_count": 0, "installations": {}})}),
            ),
            ("answer a list", Routes({ORG_PATH: Raw([])})),
            ("answer empty", Routes({ORG_PATH: Raw(b"")})),
            (
                "answer with a BOM",
                Routes(
                    {
                        ORG_PATH: Raw(
                            b"\xef\xbb\xbf"
                            + json.dumps(
                                {"total_count": 0, "installations": []}
                            ).encode()
                        )
                    }
                ),
            ),
            (
                "answer in utf-16",
                Routes(
                    {
                        ORG_PATH: Raw(
                            json.dumps({"total_count": 0, "installations": []}).encode(
                                "utf-16-le"
                            )
                        )
                    }
                ),
            ),
            ("answer bad utf-8", Routes({ORG_PATH: Raw(b'{"a": "\xff"}')})),
            (
                "answer NaN",
                Routes({ORG_PATH: Raw(b'{"total_count": NaN, "installations": []}')}),
            ),
            ("404 bare", Routes({})),
            ("404 no body", Routes({ORG_PATH: Raw(b"", 404)})),
            ("500 null message", Routes({ORG_PATH: Raw({"message": None}, 500)})),
            ("401 list body", Routes({ORG_PATH: Raw([1], 401)})),
            ("502 html", Routes({ORG_PATH: Raw(b"<html>", 502)})),
            ("message a number", Routes({ORG_PATH: Raw({"message": 5}, 422)})),
            (
                "app 500",
                world(
                    L(), **{"/apps/vitruvian-wren-agent": Raw({"message": "boom"}, 500)}
                ),
            ),
            ("app 404", world(L(), **{"/apps/vitruvian-wren-agent": Raw(b"", 404)})),
            (
                "app no permissions",
                world(L(), **{"/apps/vitruvian-wren-agent": Raw({"id": 104})}),
            ),
            (
                "app permissions a list",
                world(
                    L(),
                    **{
                        "/apps/vitruvian-wren-agent": Raw(
                            {"id": 104, "permissions": []}
                        )
                    },
                ),
            ),
            (
                "app id missing",
                world(L(), **{"/apps/vitruvian-wren-agent": Raw({"permissions": B})}),
            ),
            (
                "app id float",
                world(
                    L(),
                    **{
                        "/apps/vitruvian-wren-agent": Raw(
                            {"id": 104.0, "permissions": dict(B, actions="write")}
                        )
                    },
                ),
            ),
            (
                "app id string",
                world(
                    L(),
                    **{
                        "/apps/vitruvian-wren-agent": Raw(
                            {"id": "104", "permissions": B}
                        )
                    },
                ),
            ),
            (
                "app answer a list",
                world(L(), **{"/apps/vitruvian-wren-agent": Raw([])}),
            ),
            (
                "app not json",
                world(L(), **{"/apps/vitruvian-wren-agent": Raw(b"nope")}),
            ),
            (
                "pending and drift together",
                world(
                    L(beacon=dict(B, actions="read")),
                    requested={
                        "vitruvian-beacon-agent": dict(
                            B, actions="write", issues="write"
                        )
                    },
                ),
            ),
            (
                "an int granted, the same float asked for",
                world(
                    L(beacon=dict(B, actions=1)),
                    requested={"vitruvian-beacon-agent": dict(B, actions=1.0)},
                ),
            ),
            (
                "requested drops one",
                world(L(), requested={"vitruvian-wren-agent": dict(B)}),
            ),
            (
                "pages relative",
                Routes(
                    {
                        ORG_PATH: Raw(
                            {"total_count": 3, "installations": L()[:1]},
                            headers={"Link": '</p2>; rel="next", </last>; rel="last"'},
                        ),
                        "/p2": Raw(
                            {"total_count": 3, "installations": L()[1:]},
                            headers={"Link": '<BASE/p3>; rel="prev"'},
                        ),
                        **apps_for(L()),
                    }
                ),
            ),
            (
                "a page that fails",
                Routes(
                    {
                        ORG_PATH: Raw(
                            {"total_count": 3, "installations": []},
                            headers={"Link": '<BASE/p2>; rel="next"'},
                        )
                    }
                ),
            ),
            (
                "redirect",
                Routes(
                    {
                        ORG_PATH: Raw(b"", 301, {"Location": "/moved"}),
                        "/moved": org(L()),
                        **apps_for(L()),
                    }
                ),
            ),
            (
                "redirect absolute",
                Routes(
                    {
                        ORG_PATH: Raw(b"", 307, {"Location": "BASE/moved?x=1"}),
                        "/moved?x=1": org(L()),
                        **apps_for(L()),
                    }
                ),
            ),
            (
                "redirect relative",
                Routes(
                    {
                        ORG_PATH: Raw(b"", 302, {"Location": "moved"}),
                        "/orgs/VitruvianSoftware/moved": org(L()),
                        **apps_for(L()),
                    }
                ),
            ),
            (
                "redirect loop",
                Routes(
                    {ORG_PATH: Raw({"message": "loop"}, 302, {"Location": ORG_PATH})}
                ),
            ),
            (
                "redirect chain too long",
                Routes(
                    {
                        ORG_PATH: Raw(b"", 302, {"Location": "/r0"}),
                        **{
                            f"/r{i}": Raw(
                                {"message": f"r{i}"}, 302, {"Location": f"/r{i + 1}"}
                            )
                            for i in range(12)
                        },
                    }
                ),
            ),
            (
                "redirect to file",
                Routes(
                    {
                        ORG_PATH: Raw(
                            {"message": "no"}, 302, {"Location": "file:///etc/passwd"}
                        )
                    }
                ),
            ),
            (
                "redirect without location",
                Routes({ORG_PATH: Raw({"message": "where"}, 302)}),
            ),
            ("304", Routes({ORG_PATH: Raw(b"", 304)})),
        ]
        self.compare_many([{"label": label, "world": w} for label, w in cases])

    def test_api_urls_orgs_and_names(self):
        long_agents = [
            ("beacon", 101, 1001),
            ("wren", 104, 1004),
            ("ñandú-with-a-long-name", 7, 7),
        ]
        decl = dict(pt.declared(), **{"ñandú-with-a-long-name": dict(pt.BASE)})
        self.compare_many(
            [
                {"label": "trailing slashes", "env": {"GITHUB_API_URL": "{API}///"}},
                {"label": "empty api", "env": {"GITHUB_API_URL": ""}},
                {"label": "no scheme", "env": {"GITHUB_API_URL": "localhost:1"}},
                {"label": "gopher", "env": {"GITHUB_API_URL": "gopher://x"}},
                {"label": "no host", "env": {"GITHUB_API_URL": "http://"}},
                {"label": "bad port", "env": {"GITHUB_API_URL": "http://127.0.0.1:x"}},
                {
                    "label": "org",
                    "args": ["--org", "Other"],
                    "world": Routes(
                        {
                            "/orgs/Other/installations?per_page=100": org(pt.live()),
                            **apps_for(pt.live()),
                        }
                    ),
                },
                {"label": "org with a space", "args": ["--org", "a b"]},
                {"label": "org not ascii", "args": ["--org", "é"]},
                {
                    "label": "wide names",
                    "files": {
                        "agents": agents_tsv(long_agents),
                        "permissions": permissions_tsv(decl),
                    },
                },
            ]
        )

    # -- the two files ----------------------------------------------------

    def test_files(self):
        A = agents_tsv()
        P = permissions_tsv(pt.declared())
        cases = [
            (
                "committed files",
                {
                    "agents": _read("agents.tsv"),
                    "permissions": _read("permissions.tsv"),
                },
            ),
            ("missing agents", {"agents": None}),
            ("missing permissions", {"permissions": None}),
            ("empty agents", {"agents": ""}),
            ("comments only", {"agents": "# x\n\n   \n"}),
            ("two columns", {"agents": "beacon\t101\n"}),
            ("blank column", {"agents": "beacon\t \t1001\n"}),
            ("extra columns", {"agents": A.replace("\n", "\textra\tmore\n")}),
            ("not numbers", {"agents": "beacon\tx\t1001\n"}),
            ("negative", {"agents": "beacon\t-1\t1001\n"}),
            ("superscript", {"agents": "beacon\t\u00b2\t1001\n"}),
            ("circled", {"agents": "beacon\t101\t\u2460\n"}),
            (
                "arabic digits",
                {"agents": "beacon\t\u0661\u0660\u0661\t1001\nwren\t104\t1004\n"},
            ),
            ("leading zeros", {"agents": "beacon\t000101\t01001\nwren\t104\t1004\n"}),
            (
                "huge ids",
                {"agents": "beacon\t101\t1001\nwren\t104\t" + "9" * 40 + "\n"},
            ),
            ("spaces around", {"agents": " beacon \t 101 \t 1001 \nwren\t104\t1004\n"}),
            ("indented comment", {"agents": "  # not a comment\t1\t2\n" + A}),
            (
                "crlf",
                {
                    "agents": A.replace("\n", "\r\n"),
                    "permissions": P.replace("\n", "\r\n"),
                },
            ),
            ("cr only", {"agents": A.replace("\n", "\r")}),
            ("form feed", {"agents": A.replace("\n", "\x0c")}),
            ("line separator", {"agents": A.replace("\n", "\u2028")}),
            ("bom", {"agents": "\ufeff" + A}),
            ("bad utf-8", {"agents": b"beacon\t101\t1001\n\xff\n"}),
            ("duplicate agent rows", {"agents": A + "beacon\t101\t1001\n"}),
            ("trailing tab", {"permissions": P.replace("\n", "\t\n", 1)}),
            ("two columns of permissions", {"permissions": "beacon\tcontents\n"}),
            ("unknown agent", {"permissions": P + "ghost\tcontents\twrite\n"}),
            ("bad level", {"permissions": "beacon\tcontents\twirte\n"}),
            ("bad level case", {"permissions": "beacon\tcontents\tWrite\n"}),
            ("duplicate permission", {"permissions": P + "beacon\tcontents\tread\n"}),
            ("undeclared", {"permissions": "beacon\tcontents\twrite\n"}),
            ("undeclared two", {"agents": A + "pace\t1\t2\n", "permissions": "x\n"}),
            ("permissions empty", {"permissions": ""}),
            ("agents a directory", {"agents": None, "_dir": "agents"}),
        ]
        out = []
        for label, files in cases:
            case = {
                "label": label,
                "files": {k: v for k, v in files.items() if not k.startswith("_")},
            }
            if files.get("_dir"):
                case["raw_args"] = True
                case["args"] = ["--agents", "{CASE}", "--permissions", "{PERMISSIONS}"]
            out.append(case)
        # The unit test's: a bad file exits 2 before reading GitHub.
        out.append(
            {
                "label": "bad file first",
                "files": {"permissions": "beacon\tcontents\twirte\n"},
                "world": None,
            }
        )
        results = self.compare_many(out)
        for case, (py, _) in zip(out, results):
            if case["label"] == "bad file first":
                self.assertEqual(py["code"], 2)
                self.assertEqual(py["log"], [])

    def test_default_files(self):
        ws = os.path.join(self.tmp, "ws")
        os.makedirs(os.path.join(ws, "tools", "agent-app"), exist_ok=True)
        for f in ("agents.tsv", "permissions.tsv"):
            shutil.copy(os.path.join(HERE, f), os.path.join(ws, "tools", "agent-app"))
        self.compare_many(
            [
                {"label": "beside the program", "default_files": True},
                {
                    "label": "workspace",
                    "default_files": True,
                    "env": {"BUILD_WORKSPACE_DIRECTORY": ws},
                },
                {
                    "label": "workspace slash",
                    "default_files": True,
                    "env": {"BUILD_WORKSPACE_DIRECTORY": ws + "/"},
                },
                {
                    "label": "workspace missing",
                    "default_files": True,
                    "env": {"BUILD_WORKSPACE_DIRECTORY": "/no/such/ws"},
                },
                {
                    "label": "workspace empty",
                    "default_files": True,
                    "env": {"BUILD_WORKSPACE_DIRECTORY": ""},
                },
            ]
        )

    # -- the token and the command line ---------------------------------

    def test_tokens(self):
        gh_ok = '#!/bin/sh\nprintf "  %s\\n" "$FAKE_GH_TOKEN"\n'
        cases = [
            ("GH_TOKEN", {}),
            ("GITHUB_TOKEN", {"env": {"GH_TOKEN": None, "GITHUB_TOKEN": "{TOKEN}"}}),
            ("empty GH_TOKEN", {"env": {"GH_TOKEN": "", "GITHUB_TOKEN": "{TOKEN}"}}),
            ("gh login", {"env": {"GH_TOKEN": None}, "gh": gh_ok}),
            (
                "gh fails",
                {
                    "env": {"GH_TOKEN": None},
                    "gh": "#!/bin/sh\necho token\necho no >&2\nexit 1\n",
                },
            ),
            (
                "gh says nothing",
                {"env": {"GH_TOKEN": None}, "gh": "#!/bin/sh\necho '  '\n"},
            ),
            (
                "gh bad utf-8",
                {"env": {"GH_TOKEN": None}, "gh": "#!/bin/sh\nprintf '\\377'\n"},
            ),
            (
                "gh bad utf-8 on stderr",
                {
                    "env": {"GH_TOKEN": None},
                    "gh": "#!/bin/sh\necho \"$FAKE_GH_TOKEN\"\nprintf '\\377' >&2\n",
                },
            ),
            (
                "gh not executable",
                {
                    "env": {"GH_TOKEN": None},
                    "gh": "#!/bin/sh\necho x\n",
                    "gh_mode": 0o644,
                },
            ),
            ("no gh", {"env": {"GH_TOKEN": None}}),
            ("token with a newline", {"env": {"GH_TOKEN": "{TOKEN}\nx"}}),
            ("token with a folded newline", {"env": {"GH_TOKEN": "{TOKEN}\n x"}}),
            ("token not latin-1", {"env": {"GH_TOKEN": "{TOKEN}\u20ac"}}),
            ("token latin-1", {"env": {"GH_TOKEN": "{TOKEN}\u00e9"}}),
        ]
        self.compare_many([dict(c, label=label) for label, c in cases])

    def test_command_lines(self):
        cases = []
        for cols in ("40", "80", "200"):
            for args in (
                ["-h"],
                ["--help"],
                ["--agents"],
                ["--bogus"],
                ["extra"],
                ["--org"],
                ["--he"],
            ):
                cases.append(
                    {"label": f"cli {cols}", "args": args, "env": {"COLUMNS": cols}}
                )
        cases += [
            {
                "label": "abbreviated",
                "raw_args": True,
                "args": ["--ag", "{AGENTS}", "--perm", "{PERMISSIONS}"],
            },
            {
                "label": "equals",
                "raw_args": True,
                "args": ["--agents={AGENTS}", "--permissions={PERMISSIONS}"],
            },
            {
                "label": "repeated",
                "raw_args": True,
                "args": [
                    "--agents",
                    "/nope",
                    "--agents",
                    "{AGENTS}",
                    "--permissions",
                    "{PERMISSIONS}",
                ],
            },
            {
                "label": "dashes",
                "raw_args": True,
                "args": ["--agents", "{AGENTS}", "--", "x"],
            },
            {"label": "empty path", "raw_args": True, "args": ["--agents", ""]},
            {"label": "ambiguous", "args": ["--o"]},
        ]
        self.compare_many(cases)


if __name__ == "__main__":
    unittest.main()
