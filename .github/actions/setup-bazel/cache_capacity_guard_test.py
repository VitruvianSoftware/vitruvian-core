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

CURRENT_HASH = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
OLDER_LINUX_HASH = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
OTHER_DARWIN_HASH = "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

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


def test_is_superseded_full_repo_cache_key():
    plat = "linux-x64"
    assert guard.is_superseded_full_repo_cache_key(
        f"setup-bazel-1-linux-x64-repository-full-{OLDER_LINUX_HASH}",
        plat,
        CURRENT_HASH,
    )
    # Same hash is not superseded.
    assert not guard.is_superseded_full_repo_cache_key(
        f"setup-bazel-1-linux-x64-repository-full-{CURRENT_HASH}",
        plat,
        CURRENT_HASH,
    )
    # Other platform full entry is not superseded for linux-x64.
    assert not guard.is_superseded_full_repo_cache_key(
        f"setup-bazel-1-darwin-arm64-repository-full-{OTHER_DARWIN_HASH}",
        plat,
        CURRENT_HASH,
    )
    # Legacy partial key is not matched as full.
    assert not guard.is_superseded_full_repo_cache_key(
        f"setup-bazel-1-linux-x64-repository-{OLDER_LINUX_HASH}",
        plat,
        CURRENT_HASH,
    )
    # Empty platform or hash never matches.
    assert not guard.is_superseded_full_repo_cache_key(
        f"setup-bazel-1-linux-x64-repository-full-{OLDER_LINUX_HASH}",
        "",
        CURRENT_HASH,
    )
    assert not guard.is_superseded_full_repo_cache_key(
        f"setup-bazel-1-linux-x64-repository-full-{OLDER_LINUX_HASH}",
        plat,
        "",
    )


def test_compute_needed_bytes_subtracts_legacy_and_same_platform_superseded():
    caches = list(SAMPLE_CACHES) + [
        {
            "id": 10,
            "key": f"setup-bazel-1-linux-x64-repository-full-{OLDER_LINUX_HASH}",
            "size_in_bytes": 1_000_000_000,
        },
        {
            "id": 11,
            "key": f"setup-bazel-1-darwin-arm64-repository-full-{OTHER_DARWIN_HASH}",
            "size_in_bytes": 2_000_000_000,
        },
        {
            "id": 12,
            "key": f"setup-bazel-1-linux-x64-repository-full-{CURRENT_HASH}",
            "size_in_bytes": 500_000_000,
        },
    ]
    total_active = MEASURED_ACTIVE_BYTES + 1_000_000_000
    (
        needed,
        legacy_bytes,
        matched_legacy,
        superseded_bytes,
        matched_superseded,
    ) = guard.compute_needed_bytes(
        total_active,
        caches,
        MEASURED_LINUX_ARCHIVE_BYTES,
        platform="linux-x64",
        current_lock_hash=CURRENT_HASH,
    )
    expected_legacy = MEASURED_LEGACY_LINUX_BYTES + MEASURED_LEGACY_DARWIN_BYTES
    expected_superseded = 1_000_000_000
    expected_needed = (
        total_active
        - expected_legacy
        - expected_superseded
        + MEASURED_LINUX_ARCHIVE_BYTES
    )
    assert legacy_bytes == expected_legacy
    assert len(matched_legacy) == 2
    assert superseded_bytes == expected_superseded
    assert matched_superseded == [
        (f"setup-bazel-1-linux-x64-repository-full-{OLDER_LINUX_HASH}", 1_000_000_000)
    ]
    assert needed == expected_needed
    assert needed == 8_666_141_376


def test_compute_needed_bytes_clamps_stale_usage():
    needed, legacy_bytes, _, superseded_bytes, _ = guard.compute_needed_bytes(
        1_000,
        SAMPLE_CACHES,
        5_000,
        platform="linux-x64",
        current_lock_hash=CURRENT_HASH,
    )
    assert legacy_bytes == MEASURED_LEGACY_LINUX_BYTES + MEASURED_LEGACY_DARWIN_BYTES
    assert superseded_bytes == 0
    assert needed == 5_000


def test_parse_limit_gb_var_validation():
    assert guard.parse_limit_gb_var("15") == (15, None)
    assert guard.parse_limit_gb_var(" 20 ") == (20, None)
    for bad in ("", "   ", None, "abc", "15.5", "0", "-5"):
        val, err = guard.parse_limit_gb_var(bad)
        assert val is None
        assert err is not None


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


def _run_guard_with_var(tmp_path, limit_gb_raw, handler_fn, archive_bytes="6000000000"):
    summary = tmp_path / "summary.md"
    output = tmp_path / "output.txt"
    with _MockGitHubServer(handler_fn) as api_url:
        rc = guard.main(
            [
                "--repo",
                "o/r",
                "--archive-bytes",
                str(archive_bytes),
                "--platform",
                "linux-x64",
                "--lock-hash",
                CURRENT_HASH,
                "--limit-gb",
                limit_gb_raw,
                "--api-url",
                api_url,
                "--token",
                "secret-tok",
                "--summary-file",
                str(summary),
                "--output-file",
                str(output),
            ]
        )
    return rc, summary, output


def test_main_skips_when_limit_var_missing(tmp_path, capsys):
    api_called = []

    def handle(path, _headers):
        api_called.append(path)
        return 500, {}, {}

    rc, summary, output = _run_guard_with_var(tmp_path, "", handle)
    captured = capsys.readouterr()
    assert rc == 0
    assert api_called == []
    assert "::warning::" in captured.out
    assert "skipped" in captured.out.lower()
    assert "missing or empty" in captured.out.lower()
    summary_lines = summary.read_text(encoding="utf-8").strip().splitlines()
    assert len(summary_lines) == 1
    assert "skipped" in summary_lines[0].lower()
    assert "missing or empty" in summary_lines[0].lower()
    assert "allow_save=false" in output.read_text(encoding="utf-8")


def test_main_skips_when_limit_var_not_an_integer(tmp_path, capsys):
    def handle(_path, _headers):
        raise AssertionError("API should not be called when limit var is invalid")

    rc, summary, output = _run_guard_with_var(tmp_path, "fifteen", handle)
    captured = capsys.readouterr()
    assert rc == 0
    assert "::warning::" in captured.out
    assert "not an integer" in captured.out.lower()
    summary_lines = summary.read_text(encoding="utf-8").strip().splitlines()
    assert len(summary_lines) == 1
    assert "skipped" in summary_lines[0].lower()
    assert "not an integer" in summary_lines[0].lower()
    assert "allow_save=false" in output.read_text(encoding="utf-8")


@pytest.mark.parametrize("bad_val", ["0", "-3"])
def test_main_skips_when_limit_var_zero_or_negative(tmp_path, capsys, bad_val):
    def handle(_path, _headers):
        raise AssertionError("API should not be called when limit var <= 0")

    rc, summary, output = _run_guard_with_var(tmp_path, bad_val, handle)
    captured = capsys.readouterr()
    assert rc == 0
    assert "::warning::" in captured.out
    assert "positive integer" in captured.out.lower()
    summary_lines = summary.read_text(encoding="utf-8").strip().splitlines()
    assert len(summary_lines) == 1
    assert "skipped" in summary_lines[0].lower()
    assert "positive integer" in summary_lines[0].lower()
    assert "allow_save=false" in output.read_text(encoding="utf-8")


def test_main_skips_when_limit_var_below_needed(tmp_path, capsys):
    def handle(path, _headers):
        if path == "/repos/o/r/actions/cache/usage":
            return 200, {}, {"active_caches_size_in_bytes": 5_000_000_000}
        if path.startswith("/repos/o/r/actions/caches"):
            return 200, {}, {"total_count": 0, "actions_caches": []}
        return 404, {}, {"message": "Not Found"}

    rc, summary, output = _run_guard_with_var(
        tmp_path, "10", handle, archive_bytes="6000000000"
    )
    captured = capsys.readouterr()
    assert rc == 0
    assert "::warning::" in captured.out
    assert "10000000000" in captured.out
    assert "11000000000" in captured.out
    summary_lines = summary.read_text(encoding="utf-8").strip().splitlines()
    assert len(summary_lines) == 1
    assert "skipped" in summary_lines[0].lower()
    assert "below needed" in summary_lines[0].lower()
    assert "allow_save=false" in output.read_text(encoding="utf-8")


def test_main_allows_when_limit_var_sufficient_with_superseded_and_pagination(
    tmp_path, capsys
):
    superseded_entry = {
        "id": 99,
        "key": f"setup-bazel-1-linux-x64-repository-full-{OLDER_LINUX_HASH}",
        "size_in_bytes": 2_000_000_000,
    }

    def handle(path, headers):
        assert headers.get("Authorization") == "Bearer secret-tok"
        if path == "/repos/o/r/actions/cache/usage":
            return (
                200,
                {},
                {"active_caches_size_in_bytes": MEASURED_ACTIVE_BYTES + 2_000_000_000},
            )
        if path == "/repos/o/r/actions/caches?per_page=100":
            return (
                200,
                {
                    "Link": f'<{api_url}/repos/o/r/actions/caches?per_page=100&page=2>; rel="next"'
                },
                {
                    "total_count": 3,
                    "actions_caches": [SAMPLE_CACHES[1], superseded_entry],
                },
            )
        if path == "/repos/o/r/actions/caches?per_page=100&page=2":
            return 200, {}, {"total_count": 3, "actions_caches": [SAMPLE_CACHES[2]]}
        return 404, {}, {"message": "Not Found"}

    summary = tmp_path / "summary.md"
    output = tmp_path / "output.txt"
    with _MockGitHubServer(handle) as api_url:
        rc = guard.main(
            [
                "--repo",
                "o/r",
                "--archive-bytes",
                str(MEASURED_LINUX_ARCHIVE_BYTES),
                "--platform",
                "linux-x64",
                "--lock-hash",
                CURRENT_HASH,
                "--limit-gb",
                "15",
                "--api-url",
                api_url,
                "--token",
                "secret-tok",
                "--summary-file",
                str(summary),
                "--output-file",
                str(output),
            ]
        )

    captured = capsys.readouterr()
    assert rc == 0
    assert "::warning::" not in captured.out
    assert "ALLOWED" in captured.out
    assert OLDER_LINUX_HASH in captured.out
    assert "8,666,141,376" in captured.out
    assert "15,000,000,000" in captured.out
    assert "ALLOWED" in summary.read_text(encoding="utf-8")
    assert "allow_save=true" in output.read_text(encoding="utf-8")


def test_main_retries_transient_usage_error_then_allows_save(tmp_path, capsys):
    usage_calls = []

    def handle(path, _headers):
        if path == "/repos/o/r/actions/cache/usage":
            usage_calls.append(path)
            if len(usage_calls) == 1:
                return 500, {}, {"message": "Transient Error"}
            return 200, {}, {"active_caches_size_in_bytes": 1_000_000_000}
        if path.startswith("/repos/o/r/actions/caches"):
            return 200, {}, {"total_count": 0, "actions_caches": []}
        return 404, {}, {"message": "Not Found"}

    summary = tmp_path / "summary.md"
    output = tmp_path / "output.txt"
    sleeps = []
    with _MockGitHubServer(handle) as api_url:
        rc = guard.main(
            [
                "--repo",
                "o/r",
                "--archive-bytes",
                "6000000000",
                "--platform",
                "linux-x64",
                "--lock-hash",
                CURRENT_HASH,
                "--limit-gb",
                "15",
                "--api-url",
                api_url,
                "--token",
                "secret-tok",
                "--summary-file",
                str(summary),
                "--output-file",
                str(output),
            ],
            sleep_fn=sleeps.append,
        )

    captured = capsys.readouterr()
    assert rc == 0
    assert len(usage_calls) == 2
    assert sleeps == [2.0]
    assert "::warning::" not in captured.out
    assert "ALLOWED" in captured.out
    assert "allow_save=true" in output.read_text(encoding="utf-8")


def test_main_skips_with_warning_on_persistent_usage_error(tmp_path, capsys):
    usage_calls = []

    def handle(path, _headers):
        if path == "/repos/o/r/actions/cache/usage":
            usage_calls.append(path)
            return 500, {}, {"message": "Internal Error"}
        return 200, {}, {}

    summary = tmp_path / "summary.md"
    output = tmp_path / "output.txt"
    sleeps = []
    with _MockGitHubServer(handle) as api_url:
        rc = guard.main(
            [
                "--repo",
                "o/r",
                "--archive-bytes",
                "100",
                "--platform",
                "linux-x64",
                "--limit-gb",
                "15",
                "--api-url",
                api_url,
                "--token",
                "tok",
                "--summary-file",
                str(summary),
                "--output-file",
                str(output),
            ],
            sleep_fn=sleeps.append,
        )

    captured = capsys.readouterr()
    assert rc == 0
    assert len(usage_calls) == 3
    assert sleeps == [2.0, 4.0]
    assert "::warning::" in captured.out
    assert "skipped" in captured.out.lower()
    summary_lines = summary.read_text(encoding="utf-8").strip().splitlines()
    assert len(summary_lines) == 1
    assert "skipped" in summary_lines[0].lower()
    assert "allow_save=false" in output.read_text(encoding="utf-8")


def test_main_skips_with_warning_on_persistent_list_caches_error(tmp_path, capsys):
    caches_calls = []

    def handle(path, _headers):
        if path == "/repos/o/r/actions/cache/usage":
            return 200, {}, {"active_caches_size_in_bytes": 1_000_000_000}
        if path.startswith("/repos/o/r/actions/caches"):
            caches_calls.append(path)
            return 502, {}, {"message": "Bad Gateway"}
        return 404, {}, {"message": "Not Found"}

    summary = tmp_path / "summary.md"
    output = tmp_path / "output.txt"
    sleeps = []
    with _MockGitHubServer(handle) as api_url:
        rc = guard.main(
            [
                "--repo",
                "o/r",
                "--archive-bytes",
                "100",
                "--platform",
                "linux-x64",
                "--limit-gb",
                "15",
                "--api-url",
                api_url,
                "--token",
                "tok",
                "--summary-file",
                str(summary),
                "--output-file",
                str(output),
            ],
            sleep_fn=sleeps.append,
        )

    captured = capsys.readouterr()
    assert rc == 0
    assert len(caches_calls) == 3
    assert sleeps == [2.0, 4.0]
    assert "::warning::" in captured.out
    assert "skipped" in captured.out.lower()
    summary_lines = summary.read_text(encoding="utf-8").strip().splitlines()
    assert len(summary_lines) == 1
    assert "skipped" in summary_lines[0].lower()
    assert "allow_save=false" in output.read_text(encoding="utf-8")


@pytest.mark.parametrize(
    ("repo", "token", "archive_bytes"),
    [
        ("", "tok", "100"),
        ("noslash", "tok", "100"),
        ("o/r", "", "100"),
        ("o/r", "tok", ""),
        ("o/r", "tok", "not-a-number"),
        ("o/r", "tok", "-5"),
    ],
)
def test_main_exits_1_on_wiring_bugs(tmp_path, capsys, repo, token, archive_bytes):
    summary = tmp_path / "summary.md"
    output = tmp_path / "output.txt"
    rc = guard.main(
        [
            "--repo",
            repo,
            "--archive-bytes",
            archive_bytes,
            "--limit-gb",
            "15",
            "--token",
            token,
            "--summary-file",
            str(summary),
            "--output-file",
            str(output),
        ]
    )
    captured = capsys.readouterr()
    assert rc == 1
    assert "::error::" in captured.err
    assert "allow_save=false" in output.read_text(encoding="utf-8")
