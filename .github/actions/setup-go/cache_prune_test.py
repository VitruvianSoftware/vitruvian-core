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

"""Tests for .github/actions/setup-go/cache_prune.py and go-cache.yaml parity."""

from __future__ import annotations

import http.server
import json
import os
from pathlib import Path
import re
import threading
import urllib.parse

import pytest

import cache_prune

_MIB = 1024 * 1024


def _resolve_go_cache_workflow_path() -> Path:
    env_path = os.environ.get("GO_CACHE_WORKFLOW_PATH")
    if env_path and os.path.isfile(env_path):
        return Path(env_path)
    return Path(__file__).resolve().parents[3] / ".github/workflows/go-cache.yaml"


class _MockGitHubServer:
    """Thread-safe local HTTP stub for GitHub Actions cache endpoints."""

    def __init__(
        self, pages: list[list[dict]], delete_fail_ids: set[int] | None = None
    ):
        self.pages = pages
        self.delete_fail_ids = delete_fail_ids or set()
        self.deleted_ids: list[int] = []
        self.get_calls = 0
        self._lock = threading.Lock()
        self._server = None
        self._thread = None

    def __enter__(self):
        parent = self

        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, format, *args):
                return

            def do_GET(self):
                parsed = urllib.parse.urlparse(self.path)
                qs = urllib.parse.parse_qs(parsed.query)
                page_idx = int(qs.get("page", ["1"])[0]) - 1
                with parent._lock:
                    parent.get_calls += 1
                    idx = min(page_idx, len(parent.pages) - 1) if parent.pages else 0
                    batch = parent.pages[idx] if parent.pages else []
                    total_count = sum(len(p) for p in parent.pages)
                body = json.dumps(
                    {"total_count": total_count, "actions_caches": batch}
                ).encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                if page_idx + 1 < len(parent.pages):
                    next_url = (
                        f"http://127.0.0.1:{parent._server.server_port}"
                        f"{parsed.path}?per_page=100&page={page_idx + 2}"
                    )
                    self.send_header("Link", f'<{next_url}>; rel="next"')
                self.end_headers()
                self.wfile.write(body)

            def do_DELETE(self):
                cid = int(self.path.rsplit("/", 1)[-1])
                with parent._lock:
                    if cid in parent.delete_fail_ids:
                        self.send_response(500)
                        self.end_headers()
                        self.wfile.write(b"server error")
                        return
                    parent.deleted_ids.append(cid)
                self.send_response(204)
                self.end_headers()

        self._server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self._thread = threading.Thread(target=self._server.serve_forever, daemon=True)
        self._thread.start()
        return self

    def __exit__(self, exc_type, exc, tb):
        if self._server is not None:
            self._server.shutdown()
            self._server.server_close()

    @property
    def api_url(self) -> str:
        assert self._server is not None
        return f"http://127.0.0.1:{self._server.server_port}"


def test_deletes_superseded_main_go_caches_and_keeps_active_and_other_refs():
    keep_a = "setup-go-Linux-x64-ubuntu26-go-1.26.10-activea"
    keep_b = "setup-go-Linux-x64-ubuntu26-go-1.26.10-activeb"
    stale = "setup-go-Linux-x64-ubuntu26-go-1.26.10-stale1"
    caches = [
        {"id": 1, "key": keep_a, "ref": "refs/heads/main", "size_in_bytes": 10 * _MIB},
        {"id": 2, "key": keep_b, "ref": "refs/heads/main", "size_in_bytes": 20 * _MIB},
        {"id": 3, "key": stale, "ref": "refs/heads/main", "size_in_bytes": 30 * _MIB},
        {
            "id": 4,
            "key": stale,
            "ref": "refs/pull/999/merge",
            "size_in_bytes": 40 * _MIB,
        },
        {
            "id": 5,
            "key": "llvm-contents-v2-Linux-abc-xyz",
            "ref": "refs/heads/main",
            "size_in_bytes": 50 * _MIB,
        },
    ]
    with _MockGitHubServer([caches]) as srv:
        api = cache_prune.GitHubCacheApi(srv.api_url, "o/r", "tok")
        res = cache_prune.confirm_and_prune_superseded_go_caches(
            api, [keep_a, keep_b], retry_delay_seconds=0
        )
        assert res["confirmed"] is True
        assert srv.deleted_ids == [3]
        assert res["freed_bytes"] == 30 * _MIB
        assert res["errors"] == []


def test_fails_closed_when_any_keep_key_is_missing():
    keep_a = "setup-go-Linux-x64-ubuntu26-go-1.26.10-activea"
    keep_b = "setup-go-Linux-x64-ubuntu26-go-1.26.10-missingb"
    stale = "setup-go-Linux-x64-ubuntu26-go-1.26.10-stale1"
    caches = [
        {"id": 1, "key": keep_a, "ref": "refs/heads/main", "size_in_bytes": 10 * _MIB},
        {"id": 3, "key": stale, "ref": "refs/heads/main", "size_in_bytes": 30 * _MIB},
    ]
    sleeps: list[float] = []
    with _MockGitHubServer([caches]) as srv:
        api = cache_prune.GitHubCacheApi(srv.api_url, "o/r", "tok")
        res = cache_prune.confirm_and_prune_superseded_go_caches(
            api,
            [keep_a, keep_b],
            max_confirm_attempts=3,
            retry_delay_seconds=0.5,
            sleep_fn=sleeps.append,
        )
        assert res["confirmed"] is False
        assert keep_b in res["warning"]
        assert srv.deleted_ids == []
        assert len(sleeps) == 2


def test_confirms_on_second_attempt():
    keep = "setup-go-Linux-x64-ubuntu26-go-1.26.10-active"
    stale = "setup-go-Linux-x64-ubuntu26-go-1.26.10-stale"

    class FlakyApi:
        def __init__(self):
            self.calls = 0
            self.deleted = []

        def list_caches(self):
            self.calls += 1
            if self.calls == 1:
                return [
                    {
                        "id": 2,
                        "key": stale,
                        "ref": "refs/heads/main",
                        "size_in_bytes": 5 * _MIB,
                    }
                ]
            return [
                {
                    "id": 1,
                    "key": keep,
                    "ref": "refs/heads/main",
                    "size_in_bytes": 5 * _MIB,
                },
                {
                    "id": 2,
                    "key": stale,
                    "ref": "refs/heads/main",
                    "size_in_bytes": 5 * _MIB,
                },
            ]

        def delete_cache(self, cid):
            self.deleted.append(cid)

    api = FlakyApi()
    res = cache_prune.confirm_and_prune_superseded_go_caches(
        api, [keep], max_confirm_attempts=3, retry_delay_seconds=0
    )
    assert res["confirmed"] is True
    assert api.calls == 2
    assert api.deleted == [2]


def test_paginates_across_more_than_100_entries():
    keep = "setup-go-Linux-x64-ubuntu26-go-1.26.10-active"
    page1 = [
        {
            "id": i,
            "key": f"setup-go-Linux-x64-ubuntu26-go-1.26.10-old{i}",
            "ref": "refs/heads/main",
            "size_in_bytes": _MIB,
        }
        for i in range(1, 101)
    ]
    page2 = [
        {"id": 101, "key": keep, "ref": "refs/heads/main", "size_in_bytes": _MIB},
        {
            "id": 102,
            "key": "setup-go-Linux-x64-ubuntu26-go-1.26.10-old102",
            "ref": "refs/heads/main",
            "size_in_bytes": _MIB,
        },
    ]
    with _MockGitHubServer([page1, page2]) as srv:
        api = cache_prune.GitHubCacheApi(srv.api_url, "o/r", "tok")
        res = cache_prune.confirm_and_prune_superseded_go_caches(
            api, [keep], retry_delay_seconds=0
        )
        assert res["confirmed"] is True
        assert len(srv.deleted_ids) == 101
        assert 101 not in srv.deleted_ids
        assert 102 in srv.deleted_ids


def test_continues_after_delete_error_and_records_warning():
    keep = "setup-go-Linux-x64-ubuntu26-go-1.26.10-active"
    caches = [
        {"id": 1, "key": keep, "ref": "refs/heads/main", "size_in_bytes": _MIB},
        {
            "id": 2,
            "key": "setup-go-old-1",
            "ref": "refs/heads/main",
            "size_in_bytes": _MIB,
        },
        {
            "id": 3,
            "key": "setup-go-old-2",
            "ref": "refs/heads/main",
            "size_in_bytes": _MIB,
        },
    ]
    with _MockGitHubServer([caches], delete_fail_ids={2}) as srv:
        api = cache_prune.GitHubCacheApi(srv.api_url, "o/r", "tok")
        res = cache_prune.confirm_and_prune_superseded_go_caches(
            api, [keep], retry_delay_seconds=0
        )
        assert res["confirmed"] is True
        assert srv.deleted_ids == [3]
        assert len(res["errors"]) == 1
        assert "id=2" in res["errors"][0]


def test_main_refuses_non_main_ref_and_invalid_keep_keys(tmp_path: Path, capsys):
    rc_non_main = cache_prune.main(
        [
            "--repo",
            "o/r",
            "--ref",
            "refs/pull/1/merge",
            "--token",
            "tok",
            "--keep-key",
            "setup-go-ok",
        ]
    )
    assert rc_non_main == 0
    assert "Refusing to prune Go caches" in capsys.readouterr().out

    for bad_key in ("", "llvm-contents-v2-foo"):
        rc_bad = cache_prune.main(
            [
                "--repo",
                "o/r",
                "--ref",
                "refs/heads/main",
                "--token",
                "tok",
                "--keep-key",
                bad_key,
            ]
        )
        assert rc_bad == 1
        assert "invalid keep-key" in capsys.readouterr().err

    summary = tmp_path / "summary.md"
    with _MockGitHubServer(
        [
            [
                {
                    "id": 1,
                    "key": "setup-go-keep",
                    "ref": "refs/heads/main",
                    "size_in_bytes": 2 * _MIB,
                },
                {
                    "id": 2,
                    "key": "setup-go-old",
                    "ref": "refs/heads/main",
                    "size_in_bytes": 3 * _MIB,
                },
            ]
        ]
    ) as srv:
        rc_ok = cache_prune.main(
            [
                "--repo",
                "o/r",
                "--api-url",
                srv.api_url,
                "--ref",
                "refs/heads/main",
                "--token",
                "tok",
                "--summary-file",
                str(summary),
                "--keep-key",
                "setup-go-keep",
                "--retry-delay-seconds",
                "0",
            ]
        )
        assert rc_ok == 0
        assert srv.deleted_ids == [2]
        assert "| superseded entries pruned | 1 (3 MiB) |" in summary.read_text(
            encoding="utf-8"
        )


def test_go_cache_workflow_passes_every_warm_job_key_to_prune_superseded():
    text = _resolve_go_cache_workflow_path().read_text(encoding="utf-8")
    warm_jobs = re.findall(r"(?m)^  (warm-[a-z0-9-]+):$", text)
    assert len(warm_jobs) >= 6, f"expected >= 6 warm jobs, got {warm_jobs}"

    prune_idx = text.index("\n  prune-superseded:")
    prune_block = text[prune_idx:]

    for job in warm_jobs:
        job_start = text.index(f"\n  {job}:")
        next_job_match = re.search(r"(?m)^  [a-z0-9-]+:$", text[job_start + 5 :])
        job_end = (
            job_start + 5 + next_job_match.start() if next_job_match else len(text)
        )
        job_block = text[job_start:job_end]
        assert "cache-key: ${{ steps.setup-go.outputs.cache-key }}" in job_block, (
            f"{job} must export outputs.cache-key from steps.setup-go"
        )
        assert re.search(rf"\b{re.escape(job)}\b", prune_block), (
            f"prune-superseded must depend on {job}"
        )
        assert f"needs.{job}.outputs.cache-key" in prune_block, (
            f"prune-superseded must pass needs.{job}.outputs.cache-key via --keep-key"
        )
