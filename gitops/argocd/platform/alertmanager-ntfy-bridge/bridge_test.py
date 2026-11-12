# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

"""Tests for the alertmanager-ntfy-bridge server.py embedded in configmap.yaml.

The code under test is read straight out of the ConfigMap that Argo CD
deploys, so these tests cannot pass against a stale copy.
"""

import io
import json
import os
import pathlib
import tempfile
import types
import unittest
import urllib.error

CONFIGMAP = pathlib.Path(__file__).with_name("configmap.yaml")


def _load_server():
    """Extract the `server.py: |` block scalar and import it as a module."""
    lines = CONFIGMAP.read_text(encoding="utf-8").splitlines()
    start = next(i for i, l in enumerate(lines) if l.strip() == "server.py: |") + 1
    indent = len(lines[start]) - len(lines[start].lstrip())
    body = []
    for line in lines[start:]:
        if line.strip() and (len(line) - len(line.lstrip())) < indent:
            break
        body.append(line[indent:])
    module = types.ModuleType("bridge_server")
    exec(compile("\n".join(body), str(CONFIGMAP), "exec"), module.__dict__)
    return module


def _make_server(testcase):
    """Load server.py with test env and a fake urlopen that records requests."""
    tmp = tempfile.TemporaryDirectory()
    testcase.addCleanup(tmp.cleanup)
    pw = pathlib.Path(tmp.name) / "pw"
    pw.write_text("s3cret\n")
    env = {
        "NTFY_PASSWORD_FILE": str(pw),
        "NTFY_BASE_URL": "https://ntfy.example",
        "NTFY_TOPIC": "alerts",
    }
    saved = {k: os.environ.get(k) for k in env}
    os.environ.update(env)

    def restore():
        for k, v in saved.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v

    testcase.addCleanup(restore)
    mod = _load_server()
    mod.sent = []

    class Resp:
        def __init__(self, status):
            self.status = status

        def __enter__(self):
            return self

        def __exit__(self, *a):
            return False

    def fake_urlopen(req, timeout=None):
        mod.sent.append(req)
        code = getattr(mod, "next_status", 200)
        if code >= 400:
            raise urllib.error.HTTPError(req.full_url, code, "err", {}, io.BytesIO())
        return Resp(code)

    # urllib.request is the shared stdlib module, so put the real urlopen
    # back after each test.
    real_urlopen = mod.urllib.request.urlopen
    mod.urllib.request.urlopen = fake_urlopen
    testcase.addCleanup(setattr, mod.urllib.request, "urlopen", real_urlopen)
    return mod


def _group(status, alerts, key='{}/{}:{alertname="CNPGBackupStale", namespace="buzz"}'):
    return {
        "status": status,
        "groupKey": key,
        "groupLabels": {"alertname": "CNPGBackupStale", "namespace": "buzz"},
        "commonLabels": {"alertname": "CNPGBackupStale", "namespace": "buzz"},
        "alerts": alerts,
    }


def _alert(status, pod, severity="warning"):
    return {
        "status": status,
        "labels": {"alertname": "CNPGBackupStale", "namespace": "buzz", "pod": pod, "severity": severity},
        "annotations": {"summary": f"stale {pod}"},
    }


class BridgeTest(unittest.TestCase):
    def test_sequence_id_is_stable_per_group_and_differs_across_groups(self):
        server = _make_server(self)
        a = _group("firing", [_alert("firing", "p1")])
        b = _group("resolved", [_alert("resolved", "p1")])
        other = _group("firing", [_alert("firing", "p1")], key='{}/{}:{alertname="Other"}')
        assert server.sequence_id(a) == server.sequence_id(b)
        assert server.sequence_id(a) != server.sequence_id(other)
        sid = server.sequence_id(a)
        assert sid.startswith("am-") and len(sid) == 35
        assert all(c.isalnum() or c == "-" for c in sid)


    def test_firing_publishes_json_with_the_group_sequence_id(self):
        server = _make_server(self)
        payload = _group("firing", [_alert("firing", "p1", "page")])
        assert server.handle_alertmanager(payload) == 200
        (req,) = server.sent
        assert req.get_method() == "POST"
        assert req.full_url == "https://ntfy.example"
        body = json.loads(req.data)
        assert body["topic"] == "alerts"
        assert body["sequence_id"] == server.sequence_id(payload)
        assert body["priority"] == 5
        assert body["title"].startswith("[app] firing: CNPGBackupStale (1)")
        assert req.get_header("Authorization").startswith("Basic ")


    def test_refire_reuses_the_same_id_so_ntfy_replaces_it(self):
        server = _make_server(self)
        first = _group("firing", [_alert("firing", "p1")])
        again = _group("firing", [_alert("firing", "p1"), _alert("firing", "p2")])
        server.handle_alertmanager(first)
        server.handle_alertmanager(again)
        ids = [json.loads(r.data)["sequence_id"] for r in server.sent]
        assert ids[0] == ids[1]


    def test_partial_resolve_lists_only_alerts_still_firing(self):
        server = _make_server(self)
        payload = _group("firing", [_alert("resolved", "p1"), _alert("firing", "p2")])
        server.handle_alertmanager(payload)
        body = json.loads(server.sent[0].data)
        assert "p2" in body["message"] and "p1" not in body["message"]
        assert body["title"].endswith("(1)")


    def test_whole_group_resolved_deletes_that_notification(self):
        server = _make_server(self)
        payload = _group("resolved", [_alert("resolved", "p1")])
        assert server.handle_alertmanager(payload) == 200
        (req,) = server.sent
        assert req.get_method() == "DELETE"
        assert req.full_url == f"https://ntfy.example/alerts/{server.sequence_id(payload)}"
        assert req.data is None


    def test_delete_of_an_already_gone_notification_counts_as_success(self):
        server = _make_server(self)
        server.next_status = 404
        assert server.handle_alertmanager(_group("resolved", [_alert("resolved", "p1")])) == 200


    def test_delete_server_error_propagates_so_alertmanager_retries(self):
        server = _make_server(self)
        server.next_status = 500
        with self.assertRaises(urllib.error.HTTPError):
            server.handle_alertmanager(_group("resolved", [_alert("resolved", "p1")]))


if __name__ == "__main__":
    unittest.main()
