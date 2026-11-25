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

"""Tests verifying actions/setup-go cache key construction and composite wiring."""

from __future__ import annotations

import hashlib
import os
from pathlib import Path

import cache_key

LIVE_GO_TEST_INFRA_HASH = (
    "56396d1630370b5bc60d0eb9cee9520acb68ef9bc7a1c475ee72b384ce3019ea"
)
LIVE_GO_TEST_INFRA_KEY = (
    f"setup-go-Linux-x64-ubuntu26-go-1.26.10-{LIVE_GO_TEST_INFRA_HASH}"
)
LIVE_CACHE_VERSION = "1cb9802e5b5c597f946446bf4b3344ff6eb214d674e7138050afa0c8b9619604"


def _resolve_action_path() -> Path:
    env_path = os.environ.get("SETUP_GO_ACTION_PATH")
    if env_path and os.path.isfile(env_path):
        return Path(env_path)
    return Path(__file__).resolve().parent / "action.yml"


def _resolve_go_cache_workflow_path() -> Path:
    env_path = os.environ.get("GO_CACHE_WORKFLOW_PATH")
    if env_path and os.path.isfile(env_path):
        return Path(env_path)
    return Path(__file__).resolve().parents[3] / ".github/workflows/go-cache.yaml"


def test_build_cache_key_matches_setup_go_format():
    linux_key = cache_key.build_cache_key(
        runner_os="Linux",
        arch="x64",
        image_os="ubuntu26",
        go_version="1.26.10",
        file_hash=LIVE_GO_TEST_INFRA_HASH,
    )
    assert linux_key == LIVE_GO_TEST_INFRA_KEY
    assert linux_key.endswith(f"-{LIVE_GO_TEST_INFRA_HASH}")

    macos_key = cache_key.build_cache_key(
        runner_os="macOS",
        arch="arm64",
        image_os=None,
        go_version="1.26.10",
        file_hash="deadbeef",
    )
    assert macos_key == "setup-go-macOS-arm64-go-1.26.10-deadbeef"


def test_actions_cache_version_matches_live_gomodcache_gocache_order():
    # @actions/cache v6 keys cache versions on path order + zstd-without-long + 1.0.
    version_input = (
        "/home/runner/go/pkg/mod|/home/runner/.cache/go-build|zstd-without-long|1.0"
    )
    assert (
        hashlib.sha256(version_input.encode("utf-8")).hexdigest() == LIVE_CACHE_VERSION
    )


def test_glob_hash_files_double_sha256_and_dfs_pattern_order(tmp_path: Path):
    # Create directories where DFS entry sort ('a' before 'a-b') differs from
    # full-path string sort ('a-b/go.sum' < 'a/go.sum' if '/' vs '-' = 47 vs 45).
    (tmp_path / "infra" / "a").mkdir(parents=True)
    (tmp_path / "infra" / "a-b").mkdir(parents=True)
    (tmp_path / "examples" / "x").mkdir(parents=True)

    f_a = tmp_path / "infra" / "a" / "go.sum"
    f_ab = tmp_path / "infra" / "a-b" / "go.sum"
    f_ex = tmp_path / "examples" / "x" / "go.sum"
    f_a.write_bytes(b"mod-a\n")
    f_ab.write_bytes(b"mod-ab\n")
    f_ex.write_bytes(b"mod-ex\n")

    patterns = "infra/**/go.sum\nexamples/**/go.sum\n"
    digest, count = cache_key.glob_hash_files(patterns, tmp_path)
    assert count == 3

    # Pattern 1 ("infra") precedes pattern 2 ("examples"); inside "infra",
    # entry "a" sorts before "a-b" in readdir DFS order.
    expected = cache_key.hash_file_contents_in_order(
        [b"mod-a\n", b"mod-ab\n", b"mod-ex\n"]
    )
    assert digest == expected

    # Plain SHA-256 of concatenated bytes must differ from @actions/glob double-SHA-256.
    plain = hashlib.sha256(b"mod-a\nmod-ab\nmod-ex\n").hexdigest()
    assert digest != plain

    # Negation drops excluded file.
    digest_excl, count_excl = cache_key.glob_hash_files(
        patterns + "!infra/a-b/go.sum\n", tmp_path
    )
    assert count_excl == 2
    assert digest_excl == cache_key.hash_file_contents_in_order(
        [b"mod-a\n", b"mod-ex\n"]
    )


def test_main_writes_key_and_cache_paths_in_exact_order(tmp_path: Path, monkeypatch):
    go_mod = tmp_path / "go.mod"
    go_mod.write_text("module example.com/test\n\ngo 1.26.10\n", encoding="utf-8")
    out_file = tmp_path / "github_output.txt"

    monkeypatch.setenv("GITHUB_WORKSPACE", str(tmp_path))
    monkeypatch.setenv("RUNNER_OS", "Linux")
    monkeypatch.setenv("RUNNER_ARCH", "X64")
    monkeypatch.setenv("ImageOS", "ubuntu26")
    monkeypatch.setenv("GO_VERSION", "1.26.10")
    monkeypatch.setenv("GOMODCACHE_OUT", "/home/runner/go/pkg/mod")
    monkeypatch.setenv("GOCACHE_OUT", "/home/runner/.cache/go-build")
    monkeypatch.delenv("CACHE_DEPENDENCY_PATH", raising=False)

    rc = cache_key.main(["--github-output", str(out_file)])
    assert rc == 0

    lines = dict(
        line.split("=", 1)
        for line in out_file.read_text(encoding="utf-8").splitlines()
        if "=" in line
    )
    expected_hash, _ = cache_key.glob_hash_files("go.mod", tmp_path)
    assert lines["key"] == f"setup-go-Linux-x64-ubuntu26-go-1.26.10-{expected_hash}"
    assert lines["gomodcache"] == "/home/runner/go/pkg/mod"
    assert lines["gocache"] == "/home/runner/.cache/go-build"


def test_composite_action_wiring():
    text = _resolve_action_path().read_text(encoding="utf-8")
    assert "cache: false" in text
    assert "mode:" in text
    assert "SETUP_GO_MODE: ${{ inputs.mode }}" in text
    assert "actions/cache/restore@55cc8345863c7cc4c66a329aec7e433d2d1c52a9" in text
    assert "actions/cache@55cc8345863c7cc4c66a329aec7e433d2d1c52a9" in text
    assert (
        "(github.ref != 'refs/heads/main' || inputs.mode == 'restore') && steps.cache-key.outputs.key != ''"
        in text
    )
    assert (
        "github.ref == 'refs/heads/main' && inputs.mode != 'restore' && steps.cache-key.outputs.key != ''"
        in text
    )
    gomod_idx = text.index("steps.cache-key.outputs.gomodcache")
    gocache_idx = text.index("steps.cache-key.outputs.gocache")
    assert gomod_idx < gocache_idx
    assert "GOPROXY=https://proxy.golang.org|direct" in text
    assert "GITHUB_ENV" in text
    assert "${GOPROXY:-}" in text


def _run_main_with_go_version(
    tmp_path: Path, monkeypatch, go_version: str, mode: str = "auto"
):
    go_mod = tmp_path / "go.mod"
    go_mod.write_text("module example.com/test\n\ngo 1.26.10\n", encoding="utf-8")
    out_file = tmp_path / "github_output.txt"
    out_file.unlink(missing_ok=True)

    monkeypatch.setenv("GITHUB_WORKSPACE", str(tmp_path))
    monkeypatch.setenv("RUNNER_OS", "Linux")
    monkeypatch.setenv("RUNNER_ARCH", "X64")
    monkeypatch.setenv("ImageOS", "ubuntu26")
    monkeypatch.setenv("GO_VERSION", go_version)
    monkeypatch.setenv("SETUP_GO_MODE", mode)
    monkeypatch.setenv("GOMODCACHE_OUT", "/home/runner/go/pkg/mod")
    monkeypatch.setenv("GOCACHE_OUT", "/home/runner/.cache/go-build")
    monkeypatch.delenv("CACHE_DEPENDENCY_PATH", raising=False)

    rc = cache_key.main(["--github-output", str(out_file)])
    return rc, out_file


def test_go_version_rejects_newline_and_writes_no_output(
    tmp_path: Path, monkeypatch, capsys
):
    for bad in ("1.26.10\n", "1.26.10\nevil=1", "1.26.10\r", "1.26.10\r\nevil=1"):
        rc, out_file = _run_main_with_go_version(tmp_path, monkeypatch, bad)
        assert rc != 0
        assert not out_file.exists() or out_file.read_text(encoding="utf-8") == ""
        err = capsys.readouterr().err
        assert "Invalid GO_VERSION" in err


def test_go_version_rejects_spaces_and_empty(tmp_path: Path, monkeypatch, capsys):
    for bad in ("", "   ", " 1.26.10", "1.26.10 ", "1.26 10", "1.26.10;id"):
        rc, out_file = _run_main_with_go_version(tmp_path, monkeypatch, bad)
        assert rc != 0
        assert not out_file.exists() or out_file.read_text(encoding="utf-8") == ""
        err = capsys.readouterr().err
        assert "Invalid GO_VERSION" in err


def test_go_version_accepts_valid_and_validates_mode(tmp_path: Path, monkeypatch):
    rc, out_file = _run_main_with_go_version(
        tmp_path, monkeypatch, "1.26.10", mode="save"
    )
    assert rc == 0
    text = out_file.read_text(encoding="utf-8")
    assert "key=setup-go-Linux-x64-ubuntu26-go-1.26.10-" in text

    rc_bad_mode, out_bad = _run_main_with_go_version(
        tmp_path, monkeypatch, "1.26.10", mode="invalid"
    )
    assert rc_bad_mode != 0
    assert not out_bad.exists() or out_bad.read_text(encoding="utf-8") == ""


def test_go_cache_warm_workflow_wiring():
    text = _resolve_go_cache_workflow_path().read_text(encoding="utf-8")
    non_comment = "\n".join(
        line for line in text.splitlines() if not line.lstrip().startswith("#")
    )
    assert "push:" in non_comment
    assert "branches: [main]" in non_comment
    assert "schedule:" in non_comment
    assert "workflow_dispatch:" in non_comment
    assert "queued" not in non_comment
    for job_id in (
        "warm-go-lint-devx:",
        "warm-go-test-infra:",
        "warm-example-build:",
        "warm-pagerduty:",
        "warm-stripe:",
        "warm-sentry:",
    ):
        assert job_id in non_comment
    assert non_comment.count("uses: ./.github/actions/setup-go") == 6
    assert non_comment.count("mode: save") == 6
    assert non_comment.count("github.ref == 'refs/heads/main'") == 6
