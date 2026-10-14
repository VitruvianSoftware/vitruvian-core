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

"""The permission drift check passes only when code and GitHub agree, and
never when GitHub could not be read. No test here touches the real GitHub: the
judging cases use a fake, and the HTTP client is run against a local server."""

import http.server
import json
import os
import tempfile
import threading
import unittest

import permission_drift as pd

HERE = os.path.dirname(os.path.abspath(__file__))
BASE = {
    "checks": "read",
    "contents": "write",
    "metadata": "read",
    "pull_requests": "write",
    "workflows": "write",
}
AGENTS = [("beacon", 101, 1001), ("wren", 104, 1004)]


def declared(**overrides):
    out = {"beacon": dict(BASE), "wren": dict(BASE, actions="write")}
    out.update(overrides)
    return out


def installation(name, app_id, inst_id, perms, slug=None):
    slug = slug or f"vitruvian-{name}-agent"
    return dict(id=inst_id, app_id=app_id, app_slug=slug, permissions=perms)


class FakeGitHub:
    """Answers by path from what a test put there. An unknown path is a 404,
    so a test that forgets an answer fails rather than reading as empty."""

    def __init__(self, installations, requested=None, errors=None):
        self.installations = installations
        self.requested = requested or {}
        self.errors = errors or {}
        self.calls = []

    def get(self, path):
        self.calls.append(path)
        for prefix, err in self.errors.items():
            if path.startswith(prefix):
                raise err
        if path.startswith("/orgs/VitruvianSoftware/installations"):
            return {
                "total_count": len(self.installations),
                "installations": self.installations,
            }, None
        if path.startswith("/apps/"):
            slug = path[len("/apps/") :]
            for inst in self.installations:
                if inst["app_slug"] == slug:
                    perms = self.requested.get(slug, inst["permissions"])
                    return {
                        "id": inst["app_id"],
                        "slug": slug,
                        "permissions": perms,
                    }, None
        raise pd.ReadError(f"GET {path}: HTTP 404 Not Found")


def live(beacon=None, wren=None, extra=()):
    return [
        installation("beacon", 101, 1001, beacon if beacon is not None else dict(BASE)),
        installation(
            "wren", 104, 1004, wren if wren is not None else dict(BASE, actions="write")
        ),
        installation(
            "sonarqubecloud", 9, 9, {"checks": "write"}, slug="sonarqubecloud"
        ),
        *extra,
    ]


def run(github, decl=None):
    code, lines = pd.check(AGENTS, decl or declared(), github)
    return code, "\n".join(lines)


def line_for(report, name):
    return next(line for line in report.splitlines() if f" {name} " in f"{line} ")


class Judging(unittest.TestCase):
    def test_match_passes(self):
        code, report = run(FakeGitHub(live()))
        self.assertEqual(code, 0, report)
        self.assertIn("2 Apps: 2 ok.", report)
        self.assertIn("actions=write", line_for(report, "wren"))

    def test_extra_permission_on_github_fails_naming_app_and_permission(self):
        code, report = run(FakeGitHub(live(beacon=dict(BASE, actions="write"))))
        self.assertEqual(code, 1, report)
        self.assertIn("DRIFT", line_for(report, "beacon"))
        self.assertIn("GitHub grants actions=write; permissions.tsv does not", report)
        self.assertTrue(line_for(report, "wren").lstrip().startswith("ok"))

    def test_missing_permission_fails(self):
        perms = dict(BASE)
        del perms["workflows"]
        code, report = run(FakeGitHub(live(beacon=perms)))
        self.assertEqual(code, 1, report)
        self.assertIn("DRIFT", line_for(report, "beacon"))
        self.assertIn(
            "permissions.tsv declares workflows=write; GitHub does not", report
        )

    def test_different_level_fails(self):
        code, report = run(FakeGitHub(live(wren=dict(BASE, actions="read"))))
        self.assertEqual(code, 1, report)
        self.assertIn("DRIFT", line_for(report, "wren"))
        self.assertIn(
            "actions: permissions.tsv declares write, GitHub grants read", report
        )

    def test_pending_request_the_code_already_declares_is_reported_as_pending(self):
        # The App's settings and the code say actions=write; the org has not accepted it.
        github = FakeGitHub(
            live(beacon=dict(BASE)),
            requested={"vitruvian-beacon-agent": dict(BASE, actions="write")},
        )
        code, report = run(github, declared(beacon=dict(BASE, actions="write")))
        self.assertEqual(code, 1, report)
        self.assertIn("PENDING", line_for(report, "beacon"))
        self.assertNotIn("DRIFT", report)
        self.assertIn("settings/installations/1001", report)
        self.assertIn(
            "the App's settings ask for actions=write; GitHub does not", report
        )

    def test_pending_request_the_code_does_not_declare_is_drift_and_names_the_request(
        self,
    ):
        github = FakeGitHub(
            live(), requested={"vitruvian-beacon-agent": dict(BASE, issues="write")}
        )
        code, report = run(github)
        self.assertEqual(code, 1, report)
        self.assertIn("DRIFT", line_for(report, "beacon"))
        self.assertIn("the App's settings ask for issues=write", report)
        self.assertIn("org has not accepted", report)

    def test_app_listed_in_code_but_not_installed_fails(self):
        installs = [i for i in live() if i["app_slug"] != "vitruvian-wren-agent"]
        code, report = run(FakeGitHub(installs))
        self.assertEqual(code, 1, report)
        self.assertIn("MISSING", line_for(report, "wren"))
        self.assertIn("installation 1004 is not on VitruvianSoftware", report)

    def test_no_installations_at_all_is_not_a_pass(self):
        code, report = run(FakeGitHub([]))
        self.assertEqual(code, 1, report)
        self.assertIn("2 MISSING", report)

    def test_installation_id_of_another_app_fails(self):
        installs = live()
        installs[1]["app_id"] = 999
        code, report = run(FakeGitHub(installs))
        self.assertEqual(code, 1, report)
        self.assertIn("belongs to App 999", report)

    def test_suspended_installation_fails(self):
        installs = live()
        installs[0]["suspended_at"] = "2026-10-01T00:00:00Z"
        code, report = run(FakeGitHub(installs))
        self.assertEqual(code, 1, report)
        self.assertIn("suspended", line_for(report, "beacon"))

    def test_agent_app_installed_but_not_listed_fails(self):
        extra = [installation("newbie", 200, 2000, dict(BASE))]
        code, report = run(FakeGitHub(live(extra=extra)))
        self.assertEqual(code, 1, report)
        self.assertIn("UNLISTED", line_for(report, "vitruvian-newbie-agent"))

    def test_other_apps_on_the_org_are_ignored(self):
        code, report = run(FakeGitHub(live()))
        self.assertEqual(code, 0, report)
        self.assertNotIn("sonarqubecloud", report)


class UnreadableGitHub(unittest.TestCase):
    """A read that failed must never look like a pass."""

    def test_403_on_installations_is_not_checked_for_every_app(self):
        err = pd.ReadError(
            "GET /orgs/VitruvianSoftware/installations: HTTP 403 Resource not accessible by integration"
        )
        code, report = run(FakeGitHub(live(), errors={"/orgs/": err}))
        self.assertEqual(code, 2, report)
        self.assertNotIn(" ok ", report)
        self.assertIn("2 NOT CHECKED", report)
        self.assertIn("NOT a pass", report)
        self.assertIn("org Administration read", report)

    def test_unreadable_app_settings_is_not_checked_even_if_the_grant_matches(self):
        err = pd.ReadError("GET /apps/vitruvian-wren-agent: HTTP 500")
        code, report = run(
            FakeGitHub(live(), errors={"/apps/vitruvian-wren-agent": err})
        )
        self.assertEqual(code, 2, report)
        self.assertIn("NOT CHECKED", line_for(report, "wren"))

    def test_apps_answer_for_a_different_app_is_not_trusted(self):
        class Wrong(FakeGitHub):
            def get(self, path):
                body, nxt = super().get(path)
                if path.startswith("/apps/"):
                    body = dict(body, id=1)
                return body, nxt

        code, report = run(Wrong(live()))
        self.assertEqual(code, 2, report)

    def test_a_page_not_followed_is_not_checked(self):
        class Short(FakeGitHub):
            def get(self, path):
                body, nxt = super().get(path)
                if path.startswith("/orgs/"):
                    body = dict(body, total_count=len(body["installations"]) + 1)
                return body, nxt

        code, report = run(Short(live()))
        self.assertEqual(code, 2, report)
        self.assertIn("counts 4 installations but 3 were read", report)


class Server(http.server.BaseHTTPRequestHandler):
    """A local stand-in for api.github.com, so the real client is exercised."""

    routes = {}

    def do_GET(self):  # noqa: N802 -- http.server's name
        status, body, headers = self.routes.get(
            self.path, (404, {"message": "Not Found"}, {})
        )
        Server.seen_auth = self.headers.get("Authorization")
        payload = body.encode() if isinstance(body, str) else json.dumps(body).encode()
        self.send_response(status)
        for key, value in headers.items():
            self.send_header(key, value.replace("BASE", self.server.base))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, *args):
        pass


class RealClient(unittest.TestCase):
    def setUp(self):
        self.httpd = http.server.HTTPServer(("127.0.0.1", 0), Server)
        self.httpd.base = f"http://127.0.0.1:{self.httpd.server_port}"
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()
        self.github = pd.GitHub("sekrit", api=self.httpd.base)

    def tearDown(self):
        self.httpd.shutdown()
        self.httpd.server_close()

    def test_403_is_a_read_error_that_fails_the_check(self):
        Server.routes = {
            "/orgs/VitruvianSoftware/installations?per_page=100": (
                403,
                {"message": "Resource not accessible by integration"},
                {},
            )
        }
        code, lines = pd.check(AGENTS, declared(), self.github)
        report = "\n".join(lines)
        self.assertEqual(code, 2, report)
        self.assertIn("HTTP 403 Resource not accessible by integration", report)
        self.assertEqual(Server.seen_auth, "Bearer sekrit")

    def test_answer_that_is_not_json_is_a_read_error(self):
        Server.routes = {"/apps/x": (200, "<html>", {})}
        with self.assertRaises(pd.ReadError):
            self.github.get("/apps/x")

    def test_unreachable_host_is_a_read_error(self):
        dead = pd.GitHub("t", api="http://127.0.0.1:1")
        with self.assertRaises(pd.ReadError):
            dead.get("/apps/x")

    def test_follows_pages_and_passes_on_a_match(self):
        installs = live()
        Server.routes = {
            "/orgs/VitruvianSoftware/installations?per_page=100": (
                200,
                {"total_count": 3, "installations": installs[:2]},
                {
                    "Link": '<BASE/orgs/VitruvianSoftware/installations?per_page=100&page=2>; rel="next"'
                },
            ),
            "/orgs/VitruvianSoftware/installations?per_page=100&page=2": (
                200,
                {"total_count": 3, "installations": installs[2:]},
                {},
            ),
        }
        for inst in installs:
            Server.routes[f"/apps/{inst['app_slug']}"] = (
                200,
                {"id": inst["app_id"], "permissions": inst["permissions"]},
                {},
            )
        code, lines = pd.check(AGENTS, declared(), self.github)
        self.assertEqual(code, 0, "\n".join(lines))


class Files(unittest.TestCase):
    def write(self, text):
        handle = tempfile.NamedTemporaryFile("w", suffix=".tsv", delete=False)
        handle.write(text)
        handle.close()
        self.addCleanup(os.unlink, handle.name)
        return handle.name

    def test_the_committed_files_are_consistent(self):
        # Offline guard on the real files: every agent declares its permissions,
        # every row names a known agent, every level is one GitHub uses.
        agents = pd.load_agents(os.path.join(HERE, "agents.tsv"))
        decl = pd.load_declared(os.path.join(HERE, "permissions.tsv"), agents)
        self.assertEqual({a for a, _, _ in agents}, set(decl))
        for name, perms in decl.items():
            self.assertEqual(
                perms.get("metadata"),
                "read",
                f"{name} lacks metadata=read, which GitHub always grants",
            )

    def test_bad_level_is_rejected(self):
        path = self.write("beacon\tcontents\twirte\nwren\tcontents\twrite\n")
        with self.assertRaisesRegex(pd.FileError, "wirte"):
            pd.load_declared(path, AGENTS)

    def test_duplicate_permission_is_rejected(self):
        path = self.write(
            "beacon\tcontents\twrite\nbeacon\tcontents\tread\nwren\tcontents\twrite\n"
        )
        with self.assertRaisesRegex(pd.FileError, "twice"):
            pd.load_declared(path, AGENTS)

    def test_agent_with_no_rows_is_rejected(self):
        path = self.write("beacon\tcontents\twrite\n")
        with self.assertRaisesRegex(pd.FileError, "no permissions declared for wren"):
            pd.load_declared(path, AGENTS)

    def test_row_for_unknown_agent_is_rejected(self):
        path = self.write(
            "beacon\tcontents\twrite\nwren\tcontents\twrite\nghost\tcontents\twrite\n"
        )
        with self.assertRaisesRegex(pd.FileError, "'ghost' is not in agents.tsv"):
            pd.load_declared(path, AGENTS)

    def test_bad_file_exits_2_before_reading_github(self):
        path = self.write("beacon\tcontents\twirte\n")
        self.assertEqual(
            pd.main(
                ["--agents", os.path.join(HERE, "agents.tsv"), "--permissions", path]
            ),
            2,
        )


if __name__ == "__main__":
    unittest.main()
