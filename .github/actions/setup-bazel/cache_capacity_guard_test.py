# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

"""Tests for cache_capacity_guard.py."""

import http.server
import json
import os
import sys
import threading

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import cache_capacity_guard as guard

# Measured numbers from VitruvianSoftware/vitruvian-core on 2026-11-23.
MEASURED_ACTIVE_BYTES = 9_447_488_683
MEASURED_LEGACY_LINUX_BYTES = 5_382_975_054
MEASURED_LEGACY_DARWIN_BYTES = 1_550_912_413
MEASURED_LINUX_ARCHIVE_BYTES = 6_152_540_160  # 5.73 GiB

SAMPLE_CACHES = [
    {
        "id": 1,
        "key": "llvm-contents-v2-Linux-cf72627ff81aef34-0dbf7075",
        "size_in_bytes": 2_341_076_100,
    },
    {
        "id": 2,
        "key": "setup-bazel-1-linux-x64-repository-0dbf70751d7f1d8772a058a1747f614247d74caebfb5bc84964893c393c493cd",
        "size_in_bytes": MEASURED_LEGACY_LINUX_BYTES,
    },
    {
        "id": 3,
        "key": "setup-bazel-1-darwin-arm64-repository-0dbf70751d7f1d8772a058a1747f614247d74caebfb5bc84964893c393c493cd",
        "size_in_bytes": MEASURED_LEGACY_DARWIN_BYTES,
    },
    {
        "id": 4,
        "key": "setup-bazel-1-linux-x64-bazelisk-021fd14121db7b5b5d5160f63bacb0cc3ccc88e25b0a9e0086e812725e516e7d",
        "size_in_bytes": 57_086_589,
    },
]


def test_is_legacy_partial_repo_cache_key():
    assert guard.is_legacy_partial_repo_cache_key(
        "setup-bazel-1-linux-x64-repository-0dbf70751d7f1d87"
    )
    assert guard.is_legacy_partial_repo_cache_key(
        "setup-bazel-1-darwin-arm64-repository-deadbeef"
    )
    assert not guard.is_legacy_partial_repo_cache_key(
        "setup-bazel-1-linux-x64-repository-full-0dbf70751d7f1d87"
    )
    assert not guard.is_legacy_partial_repo_cache_key(
        "setup-bazel-1-darwin-arm64-repository-full-deadbeef"
    )
    assert not guard.is_legacy_partial_repo_cache_key(
        "setup-bazel-1-linux-x64-bazelisk-021fd141"
    )
    assert not guard.is_legacy_partial_repo_cache_key("llvm-contents-v2-Linux-abc")
    assert not guard.is_legacy_partial_repo_cache_key("pipeline-rdeps-map-v1-abc")


def test_compute_needed_bytes_exact_arithmetic():
    needed, legacy_bytes, matched = guard.compute_needed_bytes(
        MEASURED_ACTIVE_BYTES,
        SAMPLE_CACHES,
        MEASURED_LINUX_ARCHIVE_BYTES,
    )
    expected_legacy = MEASURED_LEGACY_LINUX_BYTES + MEASURED_LEGACY_DARWIN_BYTES
    expected_needed = (
        MEASURED_ACTIVE_BYTES - expected_legacy + MEASURED_LINUX_ARCHIVE_BYTES
    )
    assert legacy_bytes == expected_legacy
    assert len(matched) == 2
    assert needed == expected_needed
    assert needed == 8_666_141_376


def test_compute_needed_bytes_clamps_stale_usage():
    # Usage endpoint refreshes ~every 5 minutes; if legacy entries exceed
    # reported total_active_bytes, effective active clamps at 0.
    needed, legacy_bytes, _ = guard.compute_needed_bytes(
        1_000,
        SAMPLE_CACHES,
        5_000,
    )
    assert legacy_bytes == MEASURED_LEGACY_LINUX_BYTES + MEASURED_LEGACY_DARWIN_BYTES
    assert needed == 5_000


def test_parse_limit_bytes_validation():
    assert guard.parse_limit_bytes({"max_cache_size_gb": 15}) == 15_000_000_000
    for bad in (
        None,
        [],
        {},
        {"max_cache_size_gb": None},
        {"max_cache_size_gb": "15"},
        {"max_cache_size_gb": True},
        {"max_cache_size_gb": 0},
        {"max_cache_size_gb": -5},
    ):
        with pytest.raises(ValueError):
            guard.parse_limit_bytes(bad)


def test_evaluate_capacity_refuses_below_limit():
    # Active 5 GB (no legacy) + 5.4 GB archive = 10.4 GB > 10 GB limit.
    ok, report = guard.evaluate_capacity(
        total_active_bytes=5_000_000_000,
        caches=[],
        archive_bytes=5_400_000_000,
        limit_gb=10,
    )
    assert not ok
    assert report["reason"] == "insufficient_capacity"
    assert report["limit_bytes"] == 10_000_000_000
    assert report["needed_bytes"] == 10_400_000_000
    assert "10000000000" in report["message"]
    assert "10400000000" in report["message"]
    assert "refused" in report["message"].lower()

    # Off-by-one byte over limit must also fail.
    ok_one, _ = guard.evaluate_capacity(
        total_active_bytes=1,
        caches=[],
        archive_bytes=10_000_000_000,
        limit_gb=10,
    )
    assert not ok_one


def test_evaluate_capacity_allows_at_or_above_limit():
    ok_exact, _ = guard.evaluate_capacity(
        total_active_bytes=4_000_000_000,
        caches=[],
        archive_bytes=6_000_000_000,
        limit_gb=10,
    )
    assert ok_exact

    ok_15gb, report = guard.evaluate_capacity(
        total_active_bytes=11_000_000_000,
        caches=SAMPLE_CACHES,
        archive_bytes=MEASURED_LINUX_ARCHIVE_BYTES,
        limit_gb=15,
    )
    assert ok_15gb
    assert report["reason"] == "ok"


def test_evaluate_capacity_refuses_unknown_limit():
    ok, report = guard.evaluate_capacity(
        total_active_bytes=1_000,
        caches=[],
        archive_bytes=1_000,
        limit_gb=None,
        limit_error="HTTP 402",
    )
    assert not ok
    assert report["reason"] == "limit_unknown"
    assert "unknown" in report["message"].lower()
    assert "refused" in report["message"].lower()


class _MockGitHubServer:
    def __init__(self, handler_fn):
        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                status, headers, body = handler_fn(self.path, self.headers)
                self.send_response(status)
                for k, v in headers.items():
                    self.send_header(k, v)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
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


def test_main_refuses_when_below_limit(tmp_path, capsys):
    summary = tmp_path / "summary.md"

    def handle(path, _headers):
        if path == "/repos/o/r/actions/cache/usage":
            return 200, {}, {"active_caches_size_in_bytes": 5_000_000_000}
        if path.startswith("/repos/o/r/actions/caches"):
            return 200, {}, {"total_count": 0, "actions_caches": []}
        if path == "/repos/o/r/actions/cache/storage-limit":
            return 200, {}, {"max_cache_size_gb": 10}
        return 404, {}, {"message": "Not Found"}

    with _MockGitHubServer(handle) as api_url:
        rc = guard.main(
            [
                "--repo",
                "o/r",
                "--archive-bytes",
                "6000000000",
                "--platform",
                "linux-x64",
                "--api-url",
                api_url,
                "--token",
                "test-token",
                "--summary-file",
                str(summary),
            ]
        )

    captured = capsys.readouterr()
    assert rc == 1
    assert "10000000000" in captured.err
    assert "11000000000" in captured.err
    assert "refused" in captured.err.lower()
    summary_text = summary.read_text(encoding="utf-8")
    assert "REFUSED" in summary_text
    assert "11,000,000,000" in summary_text
    assert "10,000,000,000" in summary_text


def test_main_refuses_on_http_402_storage_limit(tmp_path, capsys):
    summary = tmp_path / "summary.md"

    def handle(path, _headers):
        if path == "/repos/o/r/actions/cache/usage":
            return 200, {}, {"active_caches_size_in_bytes": 1_000_000_000}
        if path.startswith("/repos/o/r/actions/caches"):
            return 200, {}, {"total_count": 0, "actions_caches": []}
        if path == "/repos/o/r/actions/cache/storage-limit":
            return (
                402,
                {},
                {
                    "message": "Please ensure your account has a valid payment method on file to access this service.",
                    "status": "402",
                },
            )
        return 404, {}, {"message": "Not Found"}

    with _MockGitHubServer(handle) as api_url:
        rc = guard.main(
            [
                "--repo",
                "o/r",
                "--archive-bytes",
                "1000000000",
                "--platform",
                "linux-x64",
                "--api-url",
                api_url,
                "--token",
                "test-token",
                "--summary-file",
                str(summary),
            ]
        )

    captured = capsys.readouterr()
    assert rc == 1
    assert "unknown" in captured.err.lower()
    assert "refused" in captured.err.lower()
    assert "REFUSED" in summary.read_text(encoding="utf-8")


def test_main_paginates_caches_and_allows_when_limit_sufficient(tmp_path, capsys):
    summary = tmp_path / "summary.md"

    def handle(path, headers):
        assert headers.get("Authorization") == "Bearer secret-tok"
        if path == "/repos/o/r/actions/cache/usage":
            return 200, {}, {"active_caches_size_in_bytes": MEASURED_ACTIVE_BYTES}
        if path == "/repos/o/r/actions/caches?per_page=100":
            return (
                200,
                {
                    "Link": f'<{api_url}/repos/o/r/actions/caches?per_page=100&page=2>; rel="next"'
                },
                {"total_count": 2, "actions_caches": [SAMPLE_CACHES[1]]},
            )
        if path == "/repos/o/r/actions/caches?per_page=100&page=2":
            return 200, {}, {"total_count": 2, "actions_caches": [SAMPLE_CACHES[2]]}
        if path == "/repos/o/r/actions/cache/storage-limit":
            return 200, {}, {"max_cache_size_gb": 15}
        return 404, {}, {"message": "Not Found"}

    with _MockGitHubServer(handle) as api_url:
        rc = guard.main(
            [
                "--repo",
                "o/r",
                "--archive-bytes",
                str(MEASURED_LINUX_ARCHIVE_BYTES),
                "--platform",
                "linux-x64",
                "--api-url",
                api_url,
                "--token",
                "secret-tok",
                "--summary-file",
                str(summary),
            ]
        )

    captured = capsys.readouterr()
    assert rc == 0
    assert "ALLOWED" in captured.out
    assert "8,666,141,376" in captured.out
    assert "15,000,000,000" in captured.out
    assert "ALLOWED" in summary.read_text(encoding="utf-8")


def test_main_refuses_without_token_or_on_usage_error(tmp_path):
    summary = tmp_path / "summary.md"
    rc_no_tok = guard.main(
        [
            "--repo",
            "o/r",
            "--archive-bytes",
            "100",
            "--token",
            "",
            "--summary-file",
            str(summary),
        ]
    )
    assert rc_no_tok == 1

    def handle_usage_500(path, _headers):
        if path == "/repos/o/r/actions/cache/usage":
            return 500, {}, {"message": "Internal Error"}
        return 200, {}, {"max_cache_size_gb": 15}

    with _MockGitHubServer(handle_usage_500) as api_url:
        rc_usage_err = guard.main(
            [
                "--repo",
                "o/r",
                "--archive-bytes",
                "100",
                "--api-url",
                api_url,
                "--token",
                "tok",
                "--summary-file",
                str(summary),
            ]
        )
    assert rc_usage_err == 1
