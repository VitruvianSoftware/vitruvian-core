# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

"""Tests for cache_capacity_guard.py and warm composite upload retry handling."""

import http.server
import json
import os
import re
import subprocess
import sys
import threading
from pathlib import Path

import pytest
import yaml

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import cache_capacity_guard as guard

# Exact live snapshot numbers from the binding ruling (never round).
LIVE_USAGE_BYTES = 10_602_162_673
LIVE_LEGACY_LINUX_BYTES = 5_810_848_856
LIVE_MACOS_ARCHIVE_BYTES = 1_711_935_488
LIVE_LINUX_ARCHIVE_BYTES = 6_334_521_344

CURRENT_HASH = "a" * 64
OLDER_LINUX_HASH_1 = "b" * 64
OLDER_LINUX_HASH_2 = "c" * 64
OTHER_DARWIN_HASH = "d" * 64
LIVE_LEGACY_LINUX_HASH = "39c2ecfd" + "0" * 56
LIVE_LEGACY_DARWIN_HASH = "39c2ecfd" + "1" * 56


def _live_caches():
    return [
        {
            "id": 10,
            "key": f"setup-bazel-1-linux-x64-repository-{LIVE_LEGACY_LINUX_HASH}",
            "size_in_bytes": LIVE_LEGACY_LINUX_BYTES,
        },
        {
            "id": 11,
            "key": "llvm-contents-v2-Linux-cf72627ff81aef34-39c2ecfd",
            "size_in_bytes": 2_340_676_605,
        },
        {
            "id": 12,
            "key": "setup-go-Linux-x64-go1.25.0-0123456789abcdef",
            "size_in_bytes": 2_278_144_667,
        },
        {
            "id": 13,
            "key": "setup-bazel-1-linux-x64-bazelisk-021fd14121db7b5b5d5160f63bacb0cc3ccc88e25b0a9e0086e812725e516e7d",
            "size_in_bytes": 57_086_589,
        },
        {
            "id": 14,
            "key": "setup-bazel-1-darwin-arm64-bazelisk-021fd14121db7b5b5d5160f63bacb0cc3ccc88e25b0a9e0086e812725e516e7d",
            "size_in_bytes": 115_389_651,
        },
    ]


class _MockGitHubServer:
    def __init__(self, handler_fn):
        class Handler(http.server.BaseHTTPRequestHandler):
            def _handle(self, method):
                status, headers, body = handler_fn(method, self.path, self.headers)
                self.send_response(status)
                for k, v in headers.items():
                    self.send_header(k, v)
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


def _run_guard_main(
    tmp_path,
    handler_fn,
    *,
    platform="linux-x64",
    archive_bytes="6000000000",
    limit_gb="15",
    ref="refs/heads/main",
    repo="o/r",
    token="secret-tok",
    lock_hash=CURRENT_HASH,
    sleeps=None,
):
    summary = tmp_path / "summary.md"
    output = tmp_path / "output.txt"
    with _MockGitHubServer(handler_fn) as api_url:
        rc = guard.main(
            [
                "--repo",
                repo,
                "--archive-bytes",
                str(archive_bytes),
                "--platform",
                platform,
                "--lock-hash",
                lock_hash,
                "--ref",
                ref,
                "--limit-gb",
                limit_gb,
                "--api-url",
                api_url,
                "--token",
                token,
                "--summary-file",
                str(summary),
                "--output-file",
                str(output),
            ],
            sleep_fn=(sleeps.append if sleeps is not None else lambda _s: None),
        )
    return rc, summary, output


def test_key_matchers_and_limit_parser():
    assert guard.is_legacy_partial_repo_cache_key(
        "setup-bazel-1-linux-x64-repository-0dbf70751d7f1d87", "linux-x64"
    )
    assert not guard.is_legacy_partial_repo_cache_key(
        "setup-bazel-1-linux-x64-repository-0dbf70751d7f1d87", "darwin-arm64"
    )
    assert not guard.is_legacy_partial_repo_cache_key(
        f"setup-bazel-1-linux-x64-repository-full-{CURRENT_HASH}", "linux-x64"
    )
    assert guard.is_superseded_full_repo_cache_key(
        f"setup-bazel-1-linux-x64-repository-full-{OLDER_LINUX_HASH_1}",
        "linux-x64",
        CURRENT_HASH,
    )
    assert not guard.is_superseded_full_repo_cache_key(
        f"setup-bazel-1-linux-x64-repository-full-{CURRENT_HASH}",
        "linux-x64",
        CURRENT_HASH,
    )
    assert not guard.is_superseded_full_repo_cache_key(
        f"setup-bazel-1-darwin-arm64-repository-full-{OTHER_DARWIN_HASH}",
        "linux-x64",
        CURRENT_HASH,
    )
    assert guard.parse_limit_gb_var("15") == (15, None)
    for bad in ("", "   ", None, "abc", "15.5", "0", "-5"):
        assert guard.parse_limit_gb_var(bad)[0] is None


def test_macos_first_fits_without_deletion(tmp_path, capsys):
    deletes = []

    def handle(method, path, _headers):
        if method == "GET" and path == "/repos/o/r/actions/cache/usage":
            return 200, {}, {"active_caches_size_in_bytes": LIVE_USAGE_BYTES}
        if method == "GET" and path.startswith("/repos/o/r/actions/caches"):
            return 200, {}, {"actions_caches": _live_caches()}
        if method == "DELETE":
            deletes.append(path)
            return 204, {}, None
        return 404, {}, {"message": "Not Found"}

    rc, _summary, output = _run_guard_main(
        tmp_path,
        handle,
        platform="darwin-arm64",
        archive_bytes=str(LIVE_MACOS_ARCHIVE_BYTES),
        limit_gb="15",
    )
    captured = capsys.readouterr()
    assert rc == 0
    assert deletes == []
    assert "allow_save=true" in output.read_text(encoding="utf-8")
    assert "real_peak=12314098161" in captured.out
    assert "::warning::" not in captured.out


def test_linux_next_deletes_only_linux_legacy_before_save(tmp_path, capsys):
    usage_after_macos = LIVE_USAGE_BYTES + LIVE_MACOS_ARCHIVE_BYTES
    assert usage_after_macos == 12_314_098_161

    caches = _live_caches() + [
        {
            "id": 15,
            "key": f"setup-bazel-1-darwin-arm64-repository-full-{CURRENT_HASH}",
            "size_in_bytes": LIVE_MACOS_ARCHIVE_BYTES,
        }
    ]
    calls = []

    def handle(method, path, _headers):
        calls.append((method, path))
        if method == "GET" and path == "/repos/o/r/actions/cache/usage":
            return 200, {}, {"active_caches_size_in_bytes": usage_after_macos}
        if method == "GET" and path.startswith("/repos/o/r/actions/caches"):
            return 200, {}, {"actions_caches": caches}
        if method == "DELETE" and path == "/repos/o/r/actions/caches/10":
            return 204, {}, None
        return 404, {}, {"message": "Not Found"}

    rc, _summary, output = _run_guard_main(
        tmp_path,
        handle,
        platform="linux-x64",
        archive_bytes=str(LIVE_LINUX_ARCHIVE_BYTES),
        limit_gb="15",
    )
    captured = capsys.readouterr()
    assert rc == 0
    assert "allow_save=true" in output.read_text(encoding="utf-8")
    assert [c for c in calls if c[0] == "DELETE"] == [
        ("DELETE", "/repos/o/r/actions/caches/10")
    ]
    expected_peak = (
        usage_after_macos - LIVE_LEGACY_LINUX_BYTES + LIVE_LINUX_ARCHIVE_BYTES
    )
    assert expected_peak == 12_837_770_649
    assert f"deleted={LIVE_LEGACY_LINUX_BYTES}" in captured.out
    assert f"real_peak={expected_peak}" in captured.out


def test_does_not_fit_even_after_all_replaced_deletes_nothing_and_skips(
    tmp_path, capsys
):
    caches = [
        {
            "id": 10,
            "key": f"setup-bazel-1-linux-x64-repository-{LIVE_LEGACY_LINUX_HASH}",
            "size_in_bytes": 2_000_000_000,
        },
        {
            "id": 11,
            "key": f"setup-bazel-1-linux-x64-repository-full-{OLDER_LINUX_HASH_1}",
            "size_in_bytes": 1_000_000_000,
        },
    ]
    deletes = []

    def handle(method, path, _headers):
        if method == "GET" and path == "/repos/o/r/actions/cache/usage":
            return 200, {}, {"active_caches_size_in_bytes": 12_500_000_000}
        if method == "GET" and path.startswith("/repos/o/r/actions/caches"):
            return 200, {}, {"actions_caches": caches}
        if method == "DELETE":
            deletes.append(path)
            return 204, {}, None
        return 404, {}, {"message": "Not Found"}

    # Even deleting all 3 GB of replaced leaves 12.5 - 3.0 + 6.0 = 15.5 GB > 15 GB.
    rc, summary, output = _run_guard_main(
        tmp_path,
        handle,
        platform="linux-x64",
        archive_bytes="6000000000",
        limit_gb="15",
    )
    captured = capsys.readouterr()
    assert rc == 0
    assert deletes == []
    assert "allow_save=false" in output.read_text(encoding="utf-8")
    assert "::warning::" in captured.out
    assert "deleting nothing" in captured.out.lower()
    summary_lines = summary.read_text(encoding="utf-8").strip().splitlines()
    assert len(summary_lines) == 1
    assert "skipped" in summary_lines[0].lower()


def test_deletes_only_as_needed_legacy_first_then_largest_superseded():
    caches = [
        {
            "id": 21,
            "key": f"setup-bazel-1-linux-x64-repository-full-{OLDER_LINUX_HASH_2}",
            "size_in_bytes": 1_000_000_000,
        },
        {
            "id": 20,
            "key": f"setup-bazel-1-linux-x64-repository-full-{OLDER_LINUX_HASH_1}",
            "size_in_bytes": 3_000_000_000,
        },
        {
            "id": 10,
            "key": f"setup-bazel-1-linux-x64-repository-{LIVE_LEGACY_LINUX_HASH}",
            "size_in_bytes": 4_000_000_000,
        },
    ]

    # Case A: legacy (4 GB) alone reduces 12 + 6 - 4 = 14 GB <= 15 GB; superseded entries untouched.
    deleted_a = []
    ok_a, rep_a = guard.prepare_capacity_for_save(
        total_active_bytes=12_000_000_000,
        caches=caches,
        archive_bytes=6_000_000_000,
        limit_gb_raw="15",
        platform="linux-x64",
        current_lock_hash=CURRENT_HASH,
        delete_fn=deleted_a.append,
    )
    assert ok_a is True
    assert deleted_a == [10]
    assert rep_a["real_peak_bytes"] == 14_000_000_000

    # Case B: legacy (4 GB) + largest superseded (3 GB) reduces 15 + 6 - 7 = 14 GB <= 15 GB; 1 GB untouched.
    deleted_b = []
    ok_b, rep_b = guard.prepare_capacity_for_save(
        total_active_bytes=15_000_000_000,
        caches=caches,
        archive_bytes=6_000_000_000,
        limit_gb_raw="15",
        platform="linux-x64",
        current_lock_hash=CURRENT_HASH,
        delete_fn=deleted_b.append,
    )
    assert ok_b is True
    assert deleted_b == [10, 20]
    assert rep_b["real_peak_bytes"] == 14_000_000_000


def test_never_deletes_other_platform_entry():
    caches = [
        {
            "id": 10,
            "key": f"setup-bazel-1-linux-x64-repository-{LIVE_LEGACY_LINUX_HASH}",
            "size_in_bytes": LIVE_LEGACY_LINUX_BYTES,
        },
        {
            "id": 11,
            "key": f"setup-bazel-1-linux-x64-repository-full-{OLDER_LINUX_HASH_1}",
            "size_in_bytes": 4_000_000_000,
        },
        {
            "id": 20,
            "key": f"setup-bazel-1-darwin-arm64-repository-{LIVE_LEGACY_DARWIN_HASH}",
            "size_in_bytes": 1_000_000_000,
        },
        {
            "id": 21,
            "key": f"setup-bazel-1-darwin-arm64-repository-full-{OTHER_DARWIN_HASH}",
            "size_in_bytes": 500_000_000,
        },
    ]

    # Darwin only has 1.5 GB replaceable; Linux has 9.8 GB replaceable.
    # 14.5 + 2.0 - 1.5 = 15.0 GB? Wait: use 14.6 + 2.0 = 16.6 -> needs 1.6 GB > 1.5 GB Darwin replaceable.
    # If Darwin ever touched Linux's legacy entry it would falsely fit; must NOT fit and must delete NOTHING.
    deleted_darwin = []
    ok_d, _rep_d = guard.prepare_capacity_for_save(
        total_active_bytes=14_600_000_000,
        caches=caches,
        archive_bytes=2_000_000_000,
        limit_gb_raw="15",
        platform="darwin-arm64",
        current_lock_hash=CURRENT_HASH,
        delete_fn=deleted_darwin.append,
    )
    assert ok_d is False
    assert deleted_darwin == []

    # Linux save deletes only Linux legacy (id=10), never Darwin's entries (ids 20, 21).
    deleted_linux = []
    ok_l, _rep_l = guard.prepare_capacity_for_save(
        total_active_bytes=12_314_098_161,
        caches=caches,
        archive_bytes=LIVE_LINUX_ARCHIVE_BYTES,
        limit_gb_raw="15",
        platform="linux-x64",
        current_lock_hash=CURRENT_HASH,
        delete_fn=deleted_linux.append,
    )
    assert ok_l is True
    assert deleted_linux == [10]


def _resolve_warm_action_path():
    env_path = os.environ.get("WARM_COMPOSITE_ACTION_PATH")
    if env_path and os.path.isfile(env_path):
        return Path(env_path)
    return (
        Path(__file__).resolve().parents[3]
        / ".github/actions/bazel-repo-cache-warm/action.yml"
    )


def _eval_gha_expr(expr, step_outcomes):
    s = expr.strip()
    if s.startswith("${{") and s.endswith("}}"):
        s = s[3:-2].strip()
    s = s.replace("inputs.mode", "'save'")
    s = s.replace("inputs.platform-os", "'linux'")
    s = s.replace("steps.cache-lookup.outputs.cache-hit", "'false'")
    s = s.replace("steps.gomod-cache-lookup.outputs.cache-hit", "'true'")
    s = s.replace("steps.debs-cache-lookup.outputs.cache-hit", "'true'")
    s = s.replace("steps.capacity-guard.outputs.allow_save", "'true'")

    def repl_outcome(m):
        return repr(step_outcomes.get(m.group(1), "skipped"))

    s = re.sub(r"steps\.([A-Za-z0-9_-]+)\.outcome", repl_outcome, s)
    s = s.replace("&&", " and ").replace("||", " or ")
    return bool(eval(s, {"__builtins__": {}}, {}))


def _simulate_upload_phase(tmp_path, attempt_outcomes):
    doc = yaml.safe_load(_resolve_warm_action_path().read_text(encoding="utf-8"))
    steps = doc["runs"]["steps"]
    outcomes = {}
    save_attempts = []
    backoffs = []
    warnings = []
    prune_ran = False
    job_failed = False

    in_upload_phase = False
    for step in steps:
        sid = step.get("id", "")
        uses = str(step.get("uses", ""))
        run_cmd = str(step.get("run", ""))
        if uses.startswith("actions/cache/save@"):
            in_upload_phase = True
        if not in_upload_phase:
            continue
        cond = step.get("if")
        if cond is not None and not _eval_gha_expr(str(cond), outcomes):
            if sid:
                outcomes[sid] = "skipped"
            continue
        if uses.startswith("actions/cache/save@"):
            idx = len(save_attempts)
            outcome = (
                attempt_outcomes[idx] if idx < len(attempt_outcomes) else "failure"
            )
            save_attempts.append(sid or f"save-{idx}")
            if sid:
                outcomes[sid] = outcome
            if outcome != "success" and step.get("continue-on-error") is not True:
                job_failed = True
                break
        elif "sleep " in run_cmd:
            backoffs.append(run_cmd.strip())
        elif "cache-save-warn" == sid or "::warning::" in run_cmd:
            summary = tmp_path / "upload-summary.md"
            env = dict(os.environ)
            env.update(
                {
                    "PLATFORM_OS": "linux",
                    "PLATFORM_ARCH": "x64",
                    "GITHUB_STEP_SUMMARY": str(summary),
                }
            )
            proc = subprocess.run(
                ["bash", "-euo", "pipefail", "-c", run_cmd],
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )
            if proc.returncode != 0:
                job_failed = True
            warnings.append(
                (
                    proc.stdout,
                    summary.read_text(encoding="utf-8") if summary.exists() else "",
                )
            )
        elif "cache_prune.py" in run_cmd:
            prune_ran = True

    return {
        "job_failed": job_failed,
        "save_attempts": save_attempts,
        "backoffs": backoffs,
        "warnings": warnings,
        "prune_ran": prune_ran,
    }


def test_upload_retry_transient_failure_then_succeeds(tmp_path):
    res = _simulate_upload_phase(tmp_path, ["failure", "success"])
    assert res["job_failed"] is False
    assert len(res["save_attempts"]) == 2
    assert len(res["backoffs"]) == 1
    assert res["warnings"] == []
    assert res["prune_ran"] is True


def test_upload_retry_persistent_failure_warns_and_does_not_fail_job(tmp_path):
    res = _simulate_upload_phase(tmp_path, ["failure", "failure", "failure"])
    assert res["job_failed"] is False
    assert len(res["save_attempts"]) >= 2
    assert len(res["backoffs"]) == len(res["save_attempts"]) - 1
    assert res["prune_ran"] is False
    assert len(res["warnings"]) == 1
    out, summary_text = res["warnings"][0]
    assert "::warning::" in out
    assert "no full cache until the next run" in out
    assert "no full cache until the next run" in summary_text


@pytest.mark.parametrize("limit_gb", ["", "fifteen", "0", "-3"])
def test_main_skips_when_limit_var_missing_or_invalid(tmp_path, capsys, limit_gb):
    rc, summary, output = _run_guard_main(
        tmp_path,
        lambda *_a: (_ for _ in ()).throw(AssertionError("API should not be called")),
        limit_gb=limit_gb,
    )
    assert rc == 0
    assert "::warning::" in capsys.readouterr().out
    assert "allow_save=false" in output.read_text(encoding="utf-8")
    assert "skipped" in summary.read_text(encoding="utf-8").lower()


def test_main_refuses_non_main_ref(tmp_path, capsys):
    rc, summary, output = _run_guard_main(
        tmp_path,
        lambda *_a: (_ for _ in ()).throw(AssertionError("API should not be called")),
        ref="refs/pull/5433/merge",
    )
    assert rc == 0
    assert "non-main ref" in capsys.readouterr().out
    assert "allow_save=false" in output.read_text(encoding="utf-8")
    assert "non-main ref" in summary.read_text(encoding="utf-8")


def test_main_retries_transient_usage_error_and_skips_on_persistent_error(tmp_path):
    usage_calls = []
    sleeps = []

    def handle_ok(method, path, _headers):
        if method == "GET" and path == "/repos/o/r/actions/cache/usage":
            usage_calls.append(path)
            if len(usage_calls) == 1:
                return 500, {}, {"message": "Transient"}
            return 200, {}, {"active_caches_size_in_bytes": 1_000_000_000}
        if method == "GET" and path.startswith("/repos/o/r/actions/caches"):
            return 200, {}, {"actions_caches": []}
        return 404, {}, {}

    rc, _s, out = _run_guard_main(tmp_path, handle_ok, sleeps=sleeps)
    assert rc == 0
    assert len(usage_calls) == 2
    assert sleeps == [2.0]
    assert "allow_save=true" in out.read_text(encoding="utf-8")

    sleeps2 = []
    rc2, _s2, out2 = _run_guard_main(
        tmp_path,
        lambda *_a: (500, {}, {"message": "Down"}),
        sleeps=sleeps2,
    )
    assert rc2 == 0
    assert sleeps2 == [2.0, 4.0]
    assert "allow_save=false" in out2.read_text(encoding="utf-8")


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
    rc, _summary, output = _run_guard_main(
        tmp_path,
        lambda *_a: (200, {}, {}),
        repo=repo,
        token=token,
        archive_bytes=archive_bytes,
    )
    assert rc == 1
    assert "::error::" in capsys.readouterr().err
    assert "allow_save=false" in output.read_text(encoding="utf-8")


def test_gomod_and_debs_key_matchers_capacity_and_priority():
    assert guard.is_superseded_gomod_cache_key(
        f"bazel-gomod-1-linux-x64-{OLDER_LINUX_HASH_1}",
        "linux-x64",
        CURRENT_HASH,
    )
    assert not guard.is_superseded_gomod_cache_key(
        f"bazel-gomod-1-linux-x64-{CURRENT_HASH}",
        "linux-x64",
        CURRENT_HASH,
    )
    assert not guard.is_superseded_gomod_cache_key(
        f"bazel-gomod-1-darwin-arm64-{OTHER_DARWIN_HASH}",
        "linux-x64",
        CURRENT_HASH,
    )
    assert guard.is_superseded_debs_cache_key(
        "ci-debs-1-linux-x64-oldsha",
        "linux-x64",
        "newsha",
    )
    assert not guard.is_superseded_debs_cache_key(
        "ci-debs-1-linux-x64-newsha",
        "linux-x64",
        "newsha",
    )

    caches = [
        {
            "id": 10,
            "key": f"setup-bazel-1-linux-x64-repository-{LIVE_LEGACY_LINUX_HASH}",
            "size_in_bytes": 1_000_000_000,
        },
        {
            "id": 11,
            "key": f"setup-bazel-1-linux-x64-repository-full-{OLDER_LINUX_HASH_1}",
            "size_in_bytes": 1_000_000_000,
        },
        {
            "id": 12,
            "key": f"bazel-gomod-1-linux-x64-{OLDER_LINUX_HASH_1}",
            "size_in_bytes": 500_000_000,
        },
        {
            "id": 13,
            "key": "ci-debs-1-linux-x64-oldsha",
            "size_in_bytes": 12_000_000,
        },
        {
            "id": 14,
            "key": f"bazel-gomod-1-darwin-arm64-{OTHER_DARWIN_HASH}",
            "size_in_bytes": 9_000_000_000,
        },
    ]

    # Needed = 5_000_000_000 + 500_000_000 + 10_000_000 = 5_510_000_000.
    # Usage = 12_000_000_000 -> total 17_510_000_000 > 15_000_000_000 (need 2_510_000_000 deleted).
    # Should delete id=10 (1B), id=11 (1B), id=12 (500M), id=13 (12M) -> 2_512_000_000 deleted,
    # real_peak = 14_998_000_000 <= 15_000_000_000, and never touch darwin id=14.
    deleted = []
    ok, report = guard.prepare_capacity_for_save(
        total_active_bytes=12_000_000_000,
        caches=caches,
        archive_bytes=5_000_000_000,
        limit_gb_raw="15",
        platform="linux-x64",
        current_lock_hash=CURRENT_HASH,
        gomod_bytes=500_000_000,
        debs_bytes=10_000_000,
        current_gomod_hash=CURRENT_HASH,
        current_debs_hash="newsha",
        delete_fn=deleted.append,
    )
    assert ok is True
    assert deleted == [10, 11, 12, 13]
    assert report["needed_bytes"] == 5_510_000_000
    assert report["real_peak_bytes"] == 14_998_000_000

    # If gomod + debs push over limit even after deleting all replaceable Linux entries, skip and delete nothing.
    deleted_overflow = []
    ok_ov, _rep_ov = guard.prepare_capacity_for_save(
        total_active_bytes=12_100_000_000,
        caches=caches,
        archive_bytes=5_000_000_000,
        limit_gb_raw="15",
        platform="linux-x64",
        current_lock_hash=CURRENT_HASH,
        gomod_bytes=500_000_000,
        debs_bytes=10_000_000,
        current_gomod_hash=CURRENT_HASH,
        current_debs_hash="newsha",
        delete_fn=deleted_overflow.append,
    )
    assert ok_ov is False
    assert deleted_overflow == []


def test_extra_prefixed_cache_guard_cli(tmp_path, capsys):
    prefix = "android-emulator-sdk-v1-Linux-X64-api35-system-images_android-35_google_atd_x86_64-rev-"
    keep_key = f"{prefix}pt37.0.1-emu37.1.11-plat2-img9"
    superseded_key = f"{prefix}pt36.0.0-emu36.1.0-plat1-img8"
    pr_key = f"{prefix}pt35.0.0-emu35.1.0-plat1-img7"
    unrelated_key = "setup-bazel-1-linux-x64-repository-full-" + CURRENT_HASH

    # Delimited prefix check: -rev- and undelimited prefixes must never bleed across sibling coordinates.
    assert not guard.is_superseded_prefixed_cache_key(
        {
            "id": 200,
            "ref": "refs/heads/main",
            "key": "android-emulator-sdk-v1-Linux-ARM64-api35-system-images_android-35_google_apis_arm64-v8a-rev-pt37.0.1-emu37.1.11-plat2-img9",
        },
        "android-emulator-sdk-v1-Linux-ARM64-api35-system-images_android-35_google_apis_arm64-rev-",
        "android-emulator-sdk-v1-Linux-ARM64-api35-system-images_android-35_google_apis_arm64-rev-pt37.0.1-emu37.1.11-plat2-img9",
    )
    assert not guard.is_superseded_prefixed_cache_key(
        {
            "id": 202,
            "ref": "refs/heads/main",
            "key": "android-emulator-sdk-v1-Linux-X64-api35-system-images_android-35_google_apis_x86_64-rev-pt37.0.1-emu37.1.11-plat2-img9",
        },
        "android-emulator-sdk-v1-Linux-X64-api35-system-images_android-35_google_apis_x86",
        "android-emulator-sdk-v1-Linux-X64-api35-system-images_android-35_google_apis_x86-rev-pt37.0.1-emu37.1.11-plat2-img9",
    )
    assert guard.is_superseded_prefixed_cache_key(
        {
            "id": 201,
            "ref": "refs/heads/main",
            "key": superseded_key,
        },
        prefix.rstrip("-"),
        keep_key,
    )

    # 1. Fits directly without deletions.
    deleted_fit = []

    def handle_fit(method, path, _headers):
        if method == "GET" and path.endswith("/actions/cache/usage"):
            return 200, {}, {"active_caches_size_in_bytes": 16_100_000_000}
        if method == "GET" and "/actions/caches" in path:
            return 200, {}, {"actions_caches": []}
        if method == "DELETE":
            deleted_fit.append(int(path.rsplit("/", 1)[-1]))
            return 204, {}, None
        raise AssertionError(f"unexpected {method} {path}")

    summary1 = tmp_path / "sum1.md"
    output1 = tmp_path / "out1.txt"
    with _MockGitHubServer(handle_fit) as api_url:
        rc = guard.main(
            [
                "--repo",
                "o/r",
                "--platform",
                "android-emulator-Linux-X64",
                "--ref",
                "refs/heads/main",
                "--api-url",
                api_url,
                "--token",
                "tok",
                "--archive-bytes",
                "0",
                "--extra-bytes",
                "1300000000",
                "--extra-prefix",
                prefix,
                "--extra-keep-key",
                keep_key,
                "--limit-gb",
                "20",
                "--summary-file",
                str(summary1),
                "--output-file",
                str(output1),
            ],
            sleep_fn=lambda _s: None,
        )
    assert rc == 0
    assert deleted_fit == []
    assert "allow_save=true" in output1.read_text(encoding="utf-8")
    assert "extra=1300000000" in capsys.readouterr().out

    # 2. Over limit: deletes only superseded refs/heads/main entry matching extra-prefix,
    #    never PR ref, never keep-key, never unrelated cache.
    deleted_prune = []
    caches = [
        {
            "id": 101,
            "ref": "refs/heads/main",
            "key": keep_key,
            "size_in_bytes": 1_300_000_000,
        },
        {
            "id": 102,
            "ref": "refs/heads/main",
            "key": superseded_key,
            "size_in_bytes": 1_300_000_000,
        },
        {
            "id": 103,
            "ref": "refs/pull/999/merge",
            "key": pr_key,
            "size_in_bytes": 1_300_000_000,
        },
        {
            "id": 104,
            "ref": "refs/heads/main",
            "key": unrelated_key,
            "size_in_bytes": 6_000_000_000,
        },
    ]

    def handle_over(method, path, _headers):
        if method == "GET" and path.endswith("/actions/cache/usage"):
            return 200, {}, {"active_caches_size_in_bytes": 19_200_000_000}
        if method == "GET" and "/actions/caches" in path:
            return 200, {}, {"actions_caches": caches}
        if method == "DELETE":
            deleted_prune.append(int(path.rsplit("/", 1)[-1]))
            return 204, {}, None
        raise AssertionError(f"unexpected {method} {path}")

    summary2 = tmp_path / "sum2.md"
    output2 = tmp_path / "out2.txt"
    with _MockGitHubServer(handle_over) as api_url:
        rc2 = guard.main(
            [
                "--repo",
                "o/r",
                "--platform",
                "android-emulator-Linux-X64",
                "--ref",
                "refs/heads/main",
                "--api-url",
                api_url,
                "--token",
                "tok",
                "--archive-bytes",
                "0",
                "--extra-bytes",
                "1300000000",
                "--extra-prefix",
                prefix,
                "--extra-keep-key",
                keep_key,
                "--limit-gb",
                "20",
                "--summary-file",
                str(summary2),
                "--output-file",
                str(output2),
            ],
            sleep_fn=lambda _s: None,
        )
    assert rc2 == 0
    assert deleted_prune == [102]
    assert "allow_save=true" in output2.read_text(encoding="utf-8")

    # 3. Still over limit even after considering superseded entries -> delete nothing, allow_save=false.
    deleted_overflow = []

    def handle_overflow(method, path, _headers):
        if method == "GET" and path.endswith("/actions/cache/usage"):
            return 200, {}, {"active_caches_size_in_bytes": 20_500_000_000}
        if method == "GET" and "/actions/caches" in path:
            return 200, {}, {"actions_caches": caches}
        if method == "DELETE":
            deleted_overflow.append(int(path.rsplit("/", 1)[-1]))
            return 204, {}, None
        raise AssertionError(f"unexpected {method} {path}")

    summary3 = tmp_path / "sum3.md"
    output3 = tmp_path / "out3.txt"
    with _MockGitHubServer(handle_overflow) as api_url:
        rc3 = guard.main(
            [
                "--repo",
                "o/r",
                "--platform",
                "android-emulator-Linux-X64",
                "--ref",
                "refs/heads/main",
                "--api-url",
                api_url,
                "--token",
                "tok",
                "--archive-bytes",
                "0",
                "--extra-bytes",
                "1300000000",
                "--extra-prefix",
                prefix,
                "--extra-keep-key",
                keep_key,
                "--limit-gb",
                "20",
                "--summary-file",
                str(summary3),
                "--output-file",
                str(output3),
            ],
            sleep_fn=lambda _s: None,
        )
    assert rc3 == 0
    assert deleted_overflow == []
    assert "allow_save=false" in output3.read_text(encoding="utf-8")
