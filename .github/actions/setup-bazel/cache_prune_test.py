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

NEW_HASH = "1" * 64
OLD_HASH_1 = "2" * 64
OLD_HASH_2 = "3" * 64
DARWIN_HASH = "4" * 64
LIVE_LEGACY_LINUX_HASH = "39c2ecfd" + "0" * 56


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
            return self.confirm_responses.pop(0) if self.confirm_responses else []
        return list(self.all_entries)

    def delete_cache(self, cache_id):
        self.calls.append(("delete_cache", cache_id))
        self.deleted_ids.append(cache_id)


def _sample_all_entries():
    return [
        {
            "id": 100,
            "key": f"setup-bazel-1-linux-x64-repository-full-{NEW_HASH}",
            "ref": "refs/heads/main",
            "size_in_bytes": 6_334_521_344,
        },
        {
            "id": 101,
            "key": f"setup-bazel-1-linux-x64-repository-full-{OLD_HASH_1}",
            "ref": "refs/heads/main",
            "size_in_bytes": 5_800_000_000,
        },
        {
            "id": 102,
            "key": f"setup-bazel-1-linux-x64-repository-full-{OLD_HASH_2}",
            "ref": "refs/heads/main",
            "size_in_bytes": 5_700_000_000,
        },
        {
            "id": 201,
            "key": f"setup-bazel-1-darwin-arm64-repository-full-{DARWIN_HASH}",
            "ref": "refs/heads/main",
            "size_in_bytes": 1_711_935_488,
        },
        {
            "id": 301,
            "key": f"setup-bazel-1-linux-x64-repository-{LIVE_LEGACY_LINUX_HASH}",
            "ref": "refs/heads/main",
            "size_in_bytes": 5_810_848_856,
        },
        {
            "id": 302,
            "key": f"setup-bazel-1-darwin-arm64-repository-{DARWIN_HASH}",
            "ref": "refs/heads/main",
            "size_in_bytes": 1_550_912_413,
        },
        {
            "id": 401,
            "key": "llvm-contents-v2-Linux-cf72627ff81aef34-39c2ecfd",
            "ref": "refs/heads/main",
            "size_in_bytes": 2_340_676_605,
        },
        {
            "id": 402,
            "key": "setup-go-Linux-x64-go1.25.0-0123456789abcdef",
            "ref": "refs/heads/main",
            "size_in_bytes": 2_278_144_667,
        },
        {
            "id": 403,
            "key": "setup-bazel-1-linux-x64-bazelisk-021fd14121db7b5b5d5160f63bacb0cc3ccc88e25b0a9e0086e812725e516e7d",
            "ref": "refs/heads/main",
            "size_in_bytes": 57_086_589,
        },
    ]


def test_confirm_before_delete_order_and_exact_targets():
    new_key = f"setup-bazel-1-linux-x64-repository-full-{NEW_HASH}"
    api = FakeCacheApi(
        confirm_responses=[
            [],
            [
                {
                    "id": 100,
                    "key": new_key,
                    "ref": "refs/heads/main",
                    "size_in_bytes": 6_334_521_344,
                }
            ],
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
    assert api.deleted_ids == [101, 102, 301]
    assert [cid for cid, _k, _s in result["deleted"]] == [101, 102, 301]
    assert api.calls == [
        ("list_caches", new_key),
        ("list_caches", new_key),
        ("list_caches", None),
        ("delete_cache", 101),
        ("delete_cache", 102),
        ("delete_cache", 301),
    ]


def test_confirm_requires_main_ref():
    new_key = f"setup-bazel-1-linux-x64-repository-full-{NEW_HASH}"
    main_api = FakeCacheApi(
        confirm_responses=[
            [
                {
                    "id": 100,
                    "key": new_key,
                    "ref": "refs/heads/main",
                    "size_in_bytes": 100,
                }
            ]
        ],
        all_entries=_sample_all_entries(),
    )
    main_res = prune.confirm_and_prune_superseded_caches(
        api=main_api,
        platform="linux-x64",
        current_lock_hash=NEW_HASH,
        max_confirm_attempts=1,
        retry_delay_seconds=0.0,
        sleep_fn=lambda _s: None,
    )
    assert main_res["confirmed"] is True
    assert main_api.deleted_ids == [101, 102, 301]

    for bad_entry in (
        {
            "id": 100,
            "key": new_key,
            "ref": "refs/heads/some-branch",
            "size_in_bytes": 100,
        },
        {"id": 100, "key": new_key, "size_in_bytes": 100},
    ):
        branch_api = FakeCacheApi(
            confirm_responses=[[bad_entry]],
            all_entries=_sample_all_entries(),
        )
        branch_res = prune.confirm_and_prune_superseded_caches(
            api=branch_api,
            platform="linux-x64",
            current_lock_hash=NEW_HASH,
            max_confirm_attempts=1,
            retry_delay_seconds=0.0,
            sleep_fn=lambda _s: None,
        )
        assert branch_res["confirmed"] is False
        assert branch_res["deleted"] == []
        assert branch_api.deleted_ids == []
        assert ("list_caches", None) not in branch_api.calls


def test_other_platform_legacy_untouched():
    linux_new_key = f"setup-bazel-1-linux-x64-repository-full-{NEW_HASH}"
    linux_api = FakeCacheApi(
        confirm_responses=[
            [{"id": 100, "key": linux_new_key, "ref": "refs/heads/main"}]
        ],
        all_entries=_sample_all_entries(),
    )
    linux_res = prune.confirm_and_prune_superseded_caches(
        api=linux_api,
        platform="linux-x64",
        current_lock_hash=NEW_HASH,
        max_confirm_attempts=1,
        retry_delay_seconds=0.0,
        sleep_fn=lambda _s: None,
    )
    assert linux_res["confirmed"] is True
    assert linux_api.deleted_ids == [101, 102, 301]

    darwin_new_hash = "5" * 64
    darwin_new_key = f"setup-bazel-1-darwin-arm64-repository-full-{darwin_new_hash}"
    darwin_api = FakeCacheApi(
        confirm_responses=[
            [{"id": 200, "key": darwin_new_key, "ref": "refs/heads/main"}]
        ],
        all_entries=_sample_all_entries(),
    )
    darwin_res = prune.confirm_and_prune_superseded_caches(
        api=darwin_api,
        platform="darwin-arm64",
        current_lock_hash=darwin_new_hash,
        max_confirm_attempts=1,
        retry_delay_seconds=0.0,
        sleep_fn=lambda _s: None,
    )
    assert darwin_res["confirmed"] is True
    assert darwin_api.deleted_ids == [201, 302]


def test_no_delete_when_confirm_fails():
    new_key = f"setup-bazel-1-linux-x64-repository-full-{NEW_HASH}"
    api = FakeCacheApi(
        confirm_responses=[
            [
                {
                    "id": 101,
                    "key": f"setup-bazel-1-linux-x64-repository-full-{OLD_HASH_1}",
                    "ref": "refs/heads/main",
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
            def _handle(self, method):
                status, body = handler_fn(method, self.path, self.headers)
                self.send_response(status)
                if body is not None:
                    self.send_header("Content-Type", "application/json")
                self.end_headers()
                if body is not None:
                    self.wfile.write(json.dumps(body).encode("utf-8"))

            def do_GET(self):
                self._handle("GET")

            def do_DELETE(self):
                self._handle("DELETE")

            def log_message(self, format, *args):
                pass

        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)

    def __enter__(self):
        self.thread.start()
        return f"http://127.0.0.1:{self.server.server_address[1]}"

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.server.shutdown()
        self.server.server_close()


def _run_main_with_server(tmp_path, handle, max_attempts="2", delay="0.1", sleeps=None):
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
                max_attempts,
                "--retry-delay-seconds",
                delay,
            ],
            sleep_fn=(sleeps.append if sleeps is not None else lambda _s: None),
        )
    return rc, summary


def test_main_warns_and_exits_0_on_delete_failure(tmp_path, capsys):
    new_key = f"setup-bazel-1-linux-x64-repository-full-{NEW_HASH}"
    requests = []

    def handle(method, path, _headers):
        requests.append((method, path))
        if method == "GET" and "key=" in path:
            return 200, {
                "total_count": 1,
                "actions_caches": [
                    {
                        "id": 100,
                        "key": new_key,
                        "ref": "refs/heads/main",
                        "size_in_bytes": 6_000_000_000,
                    }
                ],
            }
        if method == "GET":
            return 200, {
                "total_count": len(_sample_all_entries()),
                "actions_caches": _sample_all_entries(),
            }
        if method == "DELETE" and path == "/repos/o/r/actions/caches/101":
            return 500, {"message": "Delete failed"}
        if method == "DELETE" and path in (
            "/repos/o/r/actions/caches/102",
            "/repos/o/r/actions/caches/301",
        ):
            return 204, None
        return 404, {"message": "Not Found"}

    rc, _ = _run_main_with_server(tmp_path, handle)
    captured = capsys.readouterr()
    assert rc == 0
    assert "::warning::" in captured.out
    assert "Failed to delete cache id=101" in captured.out
    assert [r for r in requests if r[0] == "DELETE"] == [
        ("DELETE", "/repos/o/r/actions/caches/101"),
        ("DELETE", "/repos/o/r/actions/caches/102"),
        ("DELETE", "/repos/o/r/actions/caches/301"),
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
                    {
                        "id": 100,
                        "key": new_key,
                        "ref": "refs/heads/main",
                        "size_in_bytes": 6_000_000_000,
                    }
                ],
            }
        return 500, {"message": "List failed"}

    rc, summary = _run_main_with_server(tmp_path, handle)
    captured = capsys.readouterr()
    assert rc == 0
    assert "::warning::" in captured.out
    assert "Failed to list caches for pruning" in captured.out
    assert not any(m == "DELETE" for m, _p in requests)
    assert "warning(s)" in summary.read_text(encoding="utf-8")


def test_main_warns_and_exits_0_when_confirm_fails_with_api_error(tmp_path, capsys):
    requests = []
    sleeps = []

    def handle(method, path, _headers):
        requests.append((method, path))
        return 500, {"message": "API blip"}

    rc, summary = _run_main_with_server(
        tmp_path, handle, max_attempts="2", delay="0.5", sleeps=sleeps
    )
    captured = capsys.readouterr()
    assert rc == 0
    assert "::warning::" in captured.out
    assert "deleting nothing" in captured.out
    assert sleeps == [0.5]
    assert all(m == "GET" and "key=" in p for m, p in requests)
    assert not any(m == "DELETE" for m, _p in requests)
    assert "deleting nothing" in summary.read_text(encoding="utf-8")
