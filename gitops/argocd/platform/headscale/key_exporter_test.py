# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

"""Tests for headscale-key-exporter's exporter.py, embedded in
configmap-key-exporter.yaml.

The code under test is read straight out of the ConfigMap Argo CD deploys, so
these cannot pass against a stale copy. The fake API answers are shaped like
Headscale v0.26.1's real /api/v1 JSON (camelCase, string ids, RFC 3339 times
with nanoseconds), captured from the live server on 2026-11-15.
"""

import datetime
import os
import pathlib
import tempfile
import types
import unittest
import urllib.error

CONFIGMAP = pathlib.Path(__file__).with_name("configmap-key-exporter.yaml")

NOW = datetime.datetime(2026, 11, 15, 9, 0, tzinfo=datetime.timezone.utc).timestamp()


def _load():
    lines = CONFIGMAP.read_text(encoding="utf-8").splitlines()
    start = next(i for i, l in enumerate(lines) if l.strip() == "exporter.py: |") + 1
    indent = len(lines[start]) - len(lines[start].lstrip())
    body = []
    for line in lines[start:]:
        if line.strip() and (len(line) - len(line.lstrip())) < indent:
            break
        body.append(line[indent:])
    mod = types.ModuleType("key_exporter")
    exec(compile("\n".join(body), str(CONFIGMAP), "exec"), mod.__dict__)
    return mod


def _user(uid, name, email=""):
    return {
        "id": uid,
        "name": name,
        "email": email,
        "createdAt": "2026-08-23T02:03:39.768585860Z",
    }


API = {
    "/api/v1/user": {
        "users": [_user("1", "james"), _user("2", "", "someone@example.com")]
    },
    "/api/v1/preauthkey?user=1": {
        "preAuthKeys": [
            # The CI key: reusable, ephemeral, tagged.
            {
                "user": _user("1", "james"),
                "id": "5",
                "key": "secret",
                "reusable": True,
                "ephemeral": True,
                "used": True,
                "expiration": "2027-11-14T19:28:04.779658781Z",
                "createdAt": "2026-11-14T19:28:04Z",
                "aclTags": ["tag:ci"],
            },
            # Already expired: must be left out.
            {
                "user": _user("1", "james"),
                "id": "1",
                "key": "secret",
                "reusable": True,
                "ephemeral": False,
                "used": False,
                "expiration": "2026-08-23T03:04:28.871891278Z",
                "createdAt": "2026-08-23T02:04:28Z",
                "aclTags": [],
            },
            # A spent single-use key: can never be used again, so left out.
            {
                "user": _user("1", "james"),
                "id": "6",
                "key": "secret",
                "reusable": False,
                "ephemeral": False,
                "used": True,
                "expiration": "2027-01-01T00:00:00Z",
                "createdAt": "2026-11-01T00:00:00Z",
                "aclTags": [],
            },
            # An unused single-use key: still live.
            {
                "user": _user("1", "james"),
                "id": "7",
                "key": "secret",
                "reusable": False,
                "ephemeral": False,
                "used": False,
                "expiration": "2026-12-01T00:00:00Z",
                "createdAt": "2026-11-01T00:00:00Z",
                "aclTags": ["tag:b", "tag:a"],
            },
        ]
    },
    "/api/v1/preauthkey?user=2": {"preAuthKeys": []},
    "/api/v1/apikey": {
        "apiKeys": [
            {
                "id": "1",
                "prefix": "sxHrjsz",
                "expiration": "2026-11-20T07:44:40.902400902Z",
                "lastSeen": None,
            },
            {
                "id": "2",
                "prefix": "XvPIK82",
                "expiration": "2026-10-25T23:02:09.509408976Z",
                "lastSeen": None,
            },
        ]
    },
    "/api/v1/node": {
        "nodes": [
            {
                "id": "8",
                "name": "nuc9i9",
                "givenName": "nuc9i9",
                "expiry": None,
                "user": _user("1", "james"),
            },
            {
                "id": "9",
                "name": "laptop",
                "givenName": "laptop",
                "expiry": "0001-01-01T00:00:00Z",
                "user": _user("2", "", "someone@example.com"),
            },
            {
                "id": "10",
                "name": "phone",
                "givenName": "phone",
                "expiry": "2026-12-15T00:00:00Z",
                "user": _user("2", "", "someone@example.com"),
            },
        ]
    },
}


def fetch(path):
    return API[path]


class ParseTime(unittest.TestCase):
    def setUp(self):
        self.m = _load()

    def test_nanoseconds_and_z(self):
        got = self.m.parse_time("2027-11-14T19:28:04.779658781Z")
        want = datetime.datetime(
            2027, 11, 14, 19, 28, 4, 779658, tzinfo=datetime.timezone.utc
        )
        self.assertAlmostEqual(got, want.timestamp(), places=5)

    def test_no_fraction_and_offset(self):
        self.assertEqual(
            self.m.parse_time("2026-12-01T01:00:00+01:00"),
            datetime.datetime(2026, 12, 1, tzinfo=datetime.timezone.utc).timestamp(),
        )

    def test_never_values(self):
        for v in (None, "", "0001-01-01T00:00:00Z"):
            self.assertIsNone(self.m.parse_time(v), v)


class Collect(unittest.TestCase):
    def setUp(self):
        self.m = _load()
        self.creds = {
            (l["kind"], l["id"]): (l, e) for l, e in self.m.collect(fetch, NOW)
        }

    def test_ci_key_reported_with_its_expiry(self):
        labels, exp = self.creds[("preauthkey", "5")]
        self.assertEqual(labels["name"], "tag:ci")
        self.assertEqual(labels["user"], "james")
        self.assertEqual(labels["reusable"], "true")
        self.assertEqual(labels["ephemeral"], "true")
        self.assertAlmostEqual(exp, self.m.parse_time("2027-11-14T19:28:04.779658781Z"))

    def test_expired_and_spent_keys_left_out(self):
        self.assertNotIn(("preauthkey", "1"), self.creds)
        self.assertNotIn(("preauthkey", "6"), self.creds)
        self.assertNotIn(("apikey", "2"), self.creds)

    def test_unused_single_use_key_kept_with_sorted_tags(self):
        labels, _ = self.creds[("preauthkey", "7")]
        self.assertEqual(labels["name"], "tag:a,tag:b")
        self.assertEqual(labels["reusable"], "false")

    def test_api_key_named_by_prefix(self):
        labels, _ = self.creds[("apikey", "1")]
        self.assertEqual(labels["name"], "sxHrjsz")

    def test_only_nodes_with_a_real_expiry(self):
        self.assertNotIn(("node", "8"), self.creds)
        self.assertNotIn(("node", "9"), self.creds)
        labels, _ = self.creds[("node", "10")]
        self.assertEqual(labels["name"], "phone")
        # An OIDC login has no name: its id, never its email (/metrics is open).
        self.assertEqual(labels["user"], "2")

    def test_the_api_key_itself_never_appears(self):
        for labels, _ in self.creds.values():
            self.assertNotIn("secret", labels.values())

    def test_no_email_in_any_label(self):
        for labels, _ in self.creds.values():
            for v in labels.values():
                self.assertNotIn("@", v)

    def test_an_unreadable_record_is_skipped_not_fatal(self):
        api = dict(API)
        api["/api/v1/apikey"] = {
            "apiKeys": [
                {"id": "9", "prefix": "badtime", "expiration": "not a time"},
                {
                    "id": "1",
                    "prefix": "sxHrjsz",
                    "expiration": "2026-11-20T07:44:40.902400902Z",
                },
            ]
        }
        skipped = [0]
        got = {
            (l["kind"], l["id"])
            for l, _ in self.m.collect(lambda p: api[p], NOW, skipped)
        }
        self.assertEqual(skipped, [1])
        self.assertIn(("apikey", "1"), got)
        self.assertIn(("preauthkey", "5"), got)
        self.assertNotIn(("apikey", "9"), got)

    def test_preauth_keys_asked_for_by_user_id(self):
        # Headscale v0.26 takes the numeric id; ?user=<name> is a 400.
        seen = []
        self.m.collect(lambda p: (seen.append(p), API[p])[1], NOW)
        self.assertIn("/api/v1/preauthkey?user=1", seen)
        self.assertIn("/api/v1/preauthkey?user=2", seen)


class Render(unittest.TestCase):
    def setUp(self):
        self.m = _load()

    def test_escape(self):
        self.assertEqual(self.m.escape('a"b'), 'a\\"b')
        self.assertEqual(self.m.escape("a\\b"), "a\\\\b")
        self.assertEqual(self.m.escape("a\nb"), "a\\nb")
        self.assertEqual(self.m.escape(5), "5")

    def test_unreadable_count_is_exposed(self):
        self.assertIn(
            "headscale_key_exporter_unreadable_records 2\n",
            self.m.render([], True, 0, 2),
        )

    def test_exposition_format(self):
        out = self.m.render(
            [({"kind": "apikey", "id": "1", "name": 'a"b\\c', "user": ""}, 1.5)],
            True,
            10,
        )
        self.assertIn(
            'headscale_credential_expiration_timestamp_seconds{id="1",kind="apikey",name="a\\"b\\\\c",user=""} 1.5',
            out,
        )
        self.assertIn("headscale_key_exporter_up 1\n", out)
        self.assertIn(
            "headscale_key_exporter_last_success_timestamp_seconds 10.0\n", out
        )
        self.assertTrue(out.endswith("\n"))


class Refresh(unittest.TestCase):
    def setUp(self):
        self.m = _load()
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.keyfile = pathlib.Path(tmp.name) / "api-key"
        self.m.API_KEY_FILE = str(self.keyfile)

    def test_no_key_yet_is_down_not_a_crash(self):
        s = self.m.State()
        s.refresh(now=NOW)
        self.assertFalse(s.up)
        self.assertIn("headscale_key_exporter_up 0", s.metrics())

    def test_success_then_401_keeps_last_good_list(self):
        self.keyfile.write_text("k\n")
        calls = {"n": 0}

        def fake_get(path, api_key):
            self.assertEqual(api_key, "k")
            calls["n"] += 1
            if calls["n"] > 6:
                raise urllib.error.HTTPError(path, 401, "Unauthorized", {}, None)
            return API[path]

        self.m.get = fake_get
        s = self.m.State()
        s.refresh(now=NOW)
        self.assertTrue(s.up)
        good = len(s.credentials)
        self.assertGreater(good, 0)
        s.refresh(now=NOW + 300)
        self.assertFalse(s.up)
        self.assertEqual(
            len(s.credentials), good, "a failed read must not drop the expiry series"
        )
        self.assertEqual(s.last_success, NOW)

    def _fail_with(self, exc):
        self.keyfile.write_text("k")

        def fake_get(path, api_key):
            raise exc

        self.m.get = fake_get
        s = self.m.State()
        s.refresh(now=NOW)
        return s

    def test_server_error_is_down(self):
        s = self._fail_with(urllib.error.HTTPError("u", 503, "Unavailable", {}, None))
        self.assertFalse(s.up)

    def test_timeout_is_down(self):
        s = self._fail_with(TimeoutError("timed out"))
        self.assertFalse(s.up)

    def test_network_error_is_down(self):
        s = self._fail_with(urllib.error.URLError("connection refused"))
        self.assertFalse(s.up)

    def test_bad_json_is_down(self):
        s = self._fail_with(ValueError("Expecting value"))
        self.assertFalse(s.up)

    def test_unreadable_record_keeps_up_and_counts_it(self):
        self.keyfile.write_text("k")
        api = dict(API)
        api["/api/v1/node"] = {"nodes": [{"id": "1", "name": "x", "expiry": "garbage"}]}
        self.m.get = lambda p, k: api[p]
        s = self.m.State()
        s.refresh(now=NOW)
        self.assertTrue(s.up)
        self.assertIn("headscale_key_exporter_unreadable_records 1\n", s.metrics())

    def test_whole_read_has_a_deadline(self):
        self.keyfile.write_text("k")
        self.m.get = lambda p, k: API[p]
        # The deadline is set at 0; the third request sees the clock past it.
        ticks = iter([0, 0, 0] + [10_000] * 20)
        s = self.m.State()
        s.refresh(now=NOW, clock=lambda: next(ticks))
        self.assertFalse(s.up, "a read past REFRESH_BUDGET_SECONDS must fail, not hang")

    def test_unreadable_key_file_does_not_kill_the_loop(self):
        # A directory where the key should be: open() fails with an error
        # that is not "not there yet", and even root cannot read past it (a
        # chmod 0 file would be skipped on CI, which runs as root).
        self.keyfile.mkdir()
        s = self.m.State()
        s.up = True
        self.m.refresh_once(s)  # must not raise
        self.assertFalse(s.up)

    def test_refresh_once_survives_anything(self):
        s = self.m.State()
        s.up = True

        def boom(*a, **k):
            raise RuntimeError("bug")

        s.refresh = boom
        self.m.refresh_once(s)
        self.assertFalse(s.up)


if __name__ == "__main__":
    unittest.main()
