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
"""Tests for rotate_access_token.py: a fake Pulumi Cloud and a fake gh.

What matters: the new token is only stored after it proves it works, it is
never printed, and cleanup never deletes CI's current token or the one the
operator is signed in with.
"""

import io
import time
import unittest
from contextlib import redirect_stderr, redirect_stdout
from unittest import mock

import rotate_access_token as r

NEW = "pul-new-token-value-0123456789"
OLD = "pul-operator-token"


class FakeCloud:
    def __init__(self, tokens=None, new_user="ipv1337"):
        self.tokens = tokens or []
        self.new_user = new_user
        self.deleted = []
        self.created = []

    def __call__(self, token, method, path, body=None):
        if (method, path) == ("GET", "/api/user"):
            return {"githubLogin": self.new_user if token == NEW else "ipv1337"}
        if (method, path) == ("POST", "/api/user/tokens"):
            self.created.append(body)
            return {"id": "new-id", "tokenValue": NEW}
        if (method, path) == ("GET", "/api/user/tokens"):
            return {"tokens": self.tokens}
        if method == "DELETE":
            self.deleted.append(path.rsplit("/", 1)[1])
            return {}
        raise AssertionError(f"unexpected call {method} {path}")


def token(id_, desc, created, last_used=0):
    return {"id": id_, "description": desc, "created": created, "lastUsed": last_used}


def run(fn, *args, **kw):
    out, err = io.StringIO(), io.StringIO()
    with redirect_stdout(out), redirect_stderr(err):
        rc = fn(*args, **kw)
    return rc, out.getvalue() + err.getvalue()


class RotateTest(unittest.TestCase):
    def setUp(self):
        self.gh = mock.patch.object(
            r.subprocess, "run", return_value=mock.Mock(returncode=0, stderr="")
        )
        self.gh_run = self.gh.start()
        self.addCleanup(self.gh.stop)
        env = mock.patch.dict(r.os.environ, {"PULUMI_ACCESS_TOKEN": OLD})
        env.start()
        self.addCleanup(env.stop)

    def test_stores_new_token_in_both_stores_via_stdin(self):
        cloud = FakeCloud()
        with mock.patch.object(r, "api", cloud):
            rc, out = run(r.main, [])
        self.assertEqual(rc, 0)
        self.assertTrue(cloud.created[0]["description"].startswith(r.LABEL))
        calls = self.gh_run.call_args_list
        self.assertEqual(len(calls), 2)
        for call in calls:
            self.assertEqual(call.kwargs["input"], NEW)
            self.assertNotIn(NEW, call.args[0])  # never on the command line
        self.assertIn("--app", calls[1].args[0])
        self.assertNotIn(NEW, out)

    def test_does_not_store_a_token_that_signs_in_as_someone_else(self):
        cloud = FakeCloud(new_user="someone-else")
        with mock.patch.object(r, "api", cloud):
            rc, _ = run(r.main, [])
        self.assertEqual(rc, 1)
        self.gh_run.assert_not_called()

    def test_gh_failure_is_reported(self):
        self.gh_run.return_value = mock.Mock(returncode=1, stderr="nope")
        with mock.patch.object(r, "api", FakeCloud()):
            rc, out = run(r.main, [])
        self.assertEqual(rc, 1)
        self.assertNotIn(NEW, out)


class CleanupTest(unittest.TestCase):
    def setUp(self):
        env = mock.patch.dict(r.os.environ, {"PULUMI_ACCESS_TOKEN": OLD})
        env.start()
        self.addCleanup(env.stop)

    def cleanup(self, tokens, argv):
        cloud = FakeCloud(tokens)
        with mock.patch.object(r, "api", cloud):
            rc, out = run(r.main, ["--cleanup"] + argv)
        return rc, out, cloud.deleted

    def test_deletes_older_ci_tokens_and_keeps_the_newest(self):
        tokens = [
            token("a", f"{r.LABEL} (rotated 2026-01-01)", "2026-01-01"),
            token("b", f"{r.LABEL} (rotated 2026-06-01)", "2026-06-01"),
            token("c", "devcontainer", "2025-10-08"),
        ]
        _, _, deleted = self.cleanup(tokens, ["--yes"])
        self.assertEqual(deleted, ["a"])

    def test_never_deletes_unlabelled_tokens_unless_named(self):
        tokens = [token("c", "devcontainer", "2025-10-08")]
        _, out, deleted = self.cleanup(tokens, ["--yes"])
        self.assertEqual(deleted, [])
        self.assertIn("devcontainer", out)  # lists them so you can choose
        _, _, deleted = self.cleanup(tokens, ["--yes", "--delete-old", "c"])
        self.assertEqual(deleted, ["c"])

    def test_refuses_to_delete_the_current_ci_token(self):
        tokens = [token("b", f"{r.LABEL} (rotated 2026-06-01)", "2026-06-01")]
        rc, _, deleted = self.cleanup(tokens, ["--yes", "--delete-old", "b"])
        self.assertEqual(rc, 1)
        self.assertEqual(deleted, [])

    def test_skips_a_token_used_in_the_last_few_minutes(self):
        tokens = [
            token(
                "me",
                "Generated by pulumi login",
                "2025-10-08",
                last_used=time.time() - 10,
            )
        ]
        _, _, deleted = self.cleanup(tokens, ["--yes", "--delete-old", "me"])
        self.assertEqual(deleted, [])

    def test_unknown_id_fails(self):
        rc, _, deleted = self.cleanup([], ["--delete-old", "nope"])
        self.assertEqual(rc, 1)
        self.assertEqual(deleted, [])

    def test_asks_before_deleting(self):
        tokens = [
            token("a", f"{r.LABEL} (rotated 2026-01-01)", "2026-01-01"),
            token("b", f"{r.LABEL} (rotated 2026-06-01)", "2026-06-01"),
        ]
        cloud = FakeCloud(tokens)
        with mock.patch.object(r, "api", cloud):
            run(r.cleanup, OLD, [], False, ask=lambda _: "n")
        self.assertEqual(cloud.deleted, [])

    def test_delete_old_needs_cleanup(self):
        with self.assertRaises(SystemExit):
            run(r.main, ["--delete-old", "x"])


if __name__ == "__main__":
    unittest.main()
