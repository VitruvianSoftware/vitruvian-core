# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

"""Tests for cache_prune.py."""

import http.server
import json
import os
import sys
import threading

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import cache_prune as prune

NEW_HASH = "1111111111111111111111111111111111111111111111111111111111111111"
OLD_HASH_1 = "2222222222222222222222222222222222222222222222222222222222222222"
OLD_HASH_2 = "3333333333333333333333333333333333333333333333333333333333333333"
DARWIN_HASH = "4444444444444444444444444444444444444444444444444444444444444444"


class FakeCacheApi:
    """In-memory fake GitHub cache API that records call ordering."""

    def __init__(self, confirm_responses, all_entries):
        self.confirm_responses = list(confirm_responses)
        self.all_entries = list(all_entries)
        self.calls = []
        self.deleted_ids = []

    def list_caches(self, key=None):
        self.calls.append(("list_caches", key))
        if key is not None:
            if self.confirm_responses:
                return self.confirm_responses.pop(0)
            return []
        return list(self.all_entries)

    def delete_cache(self, cache_id):
        self.calls.append(("delete_cache", cache_id))
        self.deleted_ids.append(cache_id)


def _sample_all_entries():
    return [
        {
            "id": 100,
            "key": f"setup-bazel-1-linux-x64-repository-full-{NEW_HASH}",
            "size_in_bytes": 6_000_000_000,
        },
        {
            "id": 101,
            "key": f"setup-bazel-1-linux-x64-repository-full-{OLD_HASH_1}",
            "size_in_bytes": 5_800_000_000,
        },
        {
            "id": 102,
            "key": f"setup-bazel-1-linux-x64-repository-full-{OLD_HASH_2}",
            "size_in_bytes": 5_700_000_000,
        },
        {
            "id": 201,
            "key": f"setup-bazel-1-darwin-arm64-repository-full-{DARWIN_HASH}",
            "size_in_bytes": 3_100_000_000,
        },
        {
            "id": 301,
            "key": f"setup-bazel-1-linux-x64-repository-{OLD_HASH_1}",
            "size_in_bytes": 4_000_000_000,
        },
        {
            "id": 302,
            "key": f"setup-bazel-1-darwin-arm64-repository-{DARWIN_HASH}",
            "size_in_bytes": 1_500_000_000,
        },
        {
            "id": 401,
            "key": "llvm-contents-v2-Linux-abc123",
            "size_in_bytes": 2_300_000_000,
        },
        {
            "id": 402,
            "key": "setup-bazel-1-linux-x64-bazelisk-021fd141",
            "size_in_bytes": 57_000_000,
        },
    ]


def test_confirm_before_delete_order_and_exact_targets():
    new_key = f"setup-bazel-1-linux-x64-repository-full-{NEW_HASH}"
    # Succeed on 2nd confirm attempt to exercise retry.
    api = FakeCacheApi(
        confirm_responses=[
            [],
            [{"id": 100, "key": new_key, "size_in_bytes": 6_000_000_000}],
        ],
        all_entries=_sample_all_entries(),
    )
    sleeps = []
    result = prune.confirm_and_prune_superseded_caches(
        api=api,
        platform="linux-x64",
        current_lock_hash=NEW_HASH,
        max_confirm_attempts=3,
        retry_delay_seconds=0.5,
        sleep_fn=sleeps.append,
    )

    assert result["confirmed"] is True
    assert result["errors"] == []
    assert sleeps == [0.5]
    # Exact superseded same-platform full keys deleted; new key, darwin keys,
    # legacy partial keys, and unrelated keys left untouched.
    assert api.deleted_ids == [101, 102]
    assert [cid for cid, _k, _s in result["deleted"]] == [101, 102]

    # Assert strict call ordering: confirm calls -> full list -> delete calls.
    first_delete_idx = next(
        i for i, c in enumerate(api.calls) if c[0] == "delete_cache"
    )
    confirm_indices = [
        i for i, c in enumerate(api.calls) if c == ("list_caches", new_key)
    ]
    full_list_idx = api.calls.index(("list_caches", None))
    assert confirm_indices == [0, 1]
    assert full_list_idx == 2
    assert all(ci < full_list_idx < first_delete_idx for ci in confirm_indices)


def test_no_delete_when_confirm_fails():
    new_key = f"setup-bazel-1-linux-x64-repository-full-{NEW_HASH}"
    # API returns only an older key, never the exact new_key.
    api = FakeCacheApi(
        confirm_responses=[
            [
                {
                    "id": 101,
                    "key": f"setup-bazel-1-linux-x64-repository-full-{OLD_HASH_1}",
                }
            ],
            [],
            [],
        ],
        all_entries=_sample_all_entries(),
    )
    sleeps = []
    result = prune.confirm_and_prune_superseded_caches(
        api=api,
        platform="linux-x64",
        current_lock_hash=NEW_HASH,
        max_confirm_attempts=3,
        retry_delay_seconds=1.0,
        sleep_fn=sleeps.append,
    )

    assert result["confirmed"] is False
    assert result["deleted"] == []
    assert "deleting nothing" in result["warning"]
    assert api.deleted_ids == []
    assert ("list_caches", None) not in api.calls
    assert api.calls == [
        ("list_caches", new_key),
        ("list_caches", new_key),
        ("list_caches", new_key),
    ]
    assert sleeps == [1.0, 1.0]


def test_main_refuses_non_main_ref(tmp_path, capsys):
    summary = tmp_path / "summary.md"
    rc = prune.main(
        [
            "--repo",
            "o/r",
            "--platform",
            "linux-x64",
            "--lock-hash",
            NEW_HASH,
            "--ref",
            "refs/pull/5433/merge",
            "--token",
            "tok",
            "--summary-file",
            str(summary),
        ]
    )
    captured = capsys.readouterr()
    assert rc == 0
    assert "::warning::" in captured.out
    assert "non-main ref" in captured.out
    assert "non-main ref" in summary.read_text(encoding="utf-8")


class _MockGitHubCacheServer:
    def __init__(self, handler_fn):
        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                status, body = handler_fn("GET", self.path, self.headers)
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps(body).encode("utf-8"))

            def do_DELETE(self):
                status, body = handler_fn("DELETE", self.path, self.headers)
                self.send_response(status)
                if body is not None:
                    self.send_header("Content-Type", "application/json")
                self.end_headers()
                if body is not None:
                    self.wfile.write(json.dumps(body).encode("utf-8"))

            def log_message(self, format, *args):
                pass

        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.port = self.server.server_address[1]
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)

    def __enter__(self):
        self.thread.start()
        return f"http://127.0.0.1:{self.port}"

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.server.shutdown()
        self.server.server_close()


def test_main_warns_and_exits_0_on_delete_failure(tmp_path, capsys):
    new_key = f"setup-bazel-1-linux-x64-repository-full-{NEW_HASH}"
    requests = []

    def handle(method, path, _headers):
        requests.append((method, path))
        if method == "GET" and "key=" in path:
            return 200, {
                "total_count": 1,
                "actions_caches": [
                    {"id": 100, "key": new_key, "size_in_bytes": 6_000_000_000}
                ],
            }
        if method == "GET":
            return 200, {
                "total_count": len(_sample_all_entries()),
                "actions_caches": _sample_all_entries(),
            }
        if method == "DELETE" and path == "/repos/o/r/actions/caches/101":
            return 500, {"message": "Delete failed"}
        if method == "DELETE" and path == "/repos/o/r/actions/caches/102":
            return 204, None
        return 404, {"message": "Not Found"}

    summary = tmp_path / "summary.md"
    sleeps = []
    with _MockGitHubCacheServer(handle) as api_url:
        rc = prune.main(
            [
                "--repo",
                "o/r",
                "--platform",
                "linux-x64",
                "--lock-hash",
                NEW_HASH,
                "--ref",
                "refs/heads/main",
                "--api-url",
                api_url,
                "--token",
                "tok",
                "--summary-file",
                str(summary),
                "--max-confirm-attempts",
                "2",
                "--retry-delay-seconds",
                "0.1",
            ],
            sleep_fn=sleeps.append,
        )

    captured = capsys.readouterr()
    assert rc == 0
    assert "::warning::" in captured.out
    assert "Failed to delete cache id=101" in captured.out
    assert requests[0][0] == "GET" and "key=" in requests[0][1]
    assert requests[1] == ("GET", "/repos/o/r/actions/caches?per_page=100")
    assert [r for r in requests if r[0] == "DELETE"] == [
        ("DELETE", "/repos/o/r/actions/caches/101"),
        ("DELETE", "/repos/o/r/actions/caches/102"),
    ]


def test_main_warns_and_exits_0_on_post_confirm_list_failure(tmp_path, capsys):
    new_key = f"setup-bazel-1-linux-x64-repository-full-{NEW_HASH}"
    requests = []

    def handle(method, path, _headers):
        requests.append((method, path))
        if method == "GET" and "key=" in path:
            return 200, {
                "total_count": 1,
                "actions_caches": [
                    {"id": 100, "key": new_key, "size_in_bytes": 6_000_000_000}
                ],
            }
        if method == "GET":
            return 500, {"message": "List failed"}
        return 500, {"message": "Unexpected"}

    summary = tmp_path / "summary.md"
    with _MockGitHubCacheServer(handle) as api_url:
        rc = prune.main(
            [
                "--repo",
                "o/r",
                "--platform",
                "linux-x64",
                "--lock-hash",
                NEW_HASH,
                "--ref",
                "refs/heads/main",
                "--api-url",
                api_url,
                "--token",
                "tok",
                "--summary-file",
                str(summary),
                "--max-confirm-attempts",
                "2",
                "--retry-delay-seconds",
                "0.1",
            ],
            sleep_fn=lambda _s: None,
        )

    captured = capsys.readouterr()
    assert rc == 0
    assert "::warning::" in captured.out
    assert "Failed to list caches for pruning" in captured.out
    assert not any(m == "DELETE" for m, _p in requests)
    assert "warning(s)" in summary.read_text(encoding="utf-8")


def test_main_warns_and_exits_0_when_confirm_fails_with_api_error(tmp_path, capsys):
    requests = []

    def handle(method, path, _headers):
        requests.append((method, path))
        return 500, {"message": "API blip"}

    summary = tmp_path / "summary.md"
    sleeps = []
    with _MockGitHubCacheServer(handle) as api_url:
        rc = prune.main(
            [
                "--repo",
                "o/r",
                "--platform",
                "linux-x64",
                "--lock-hash",
                NEW_HASH,
                "--ref",
                "refs/heads/main",
                "--api-url",
                api_url,
                "--token",
                "tok",
                "--summary-file",
                str(summary),
                "--max-confirm-attempts",
                "2",
                "--retry-delay-seconds",
                "0.5",
            ],
            sleep_fn=sleeps.append,
        )

    captured = capsys.readouterr()
    assert rc == 0
    assert "::warning::" in captured.out
    assert "deleting nothing" in captured.out
    assert sleeps == [0.5]
    assert all(m == "GET" and "key=" in p for m, p in requests)
    assert not any(m == "DELETE" for m, _p in requests)
    assert "deleting nothing" in summary.read_text(encoding="utf-8")
