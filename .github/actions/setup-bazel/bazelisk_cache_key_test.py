# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

"""Tests verifying the bazelisk Actions cache key computed from .bazelversion."""

import hashlib
import os
from pathlib import Path

LIVE_BAZELISK_HASH = "021fd14121db7b5b5d5160f63bacb0cc3ccc88e25b0a9e0086e812725e516e7d"


def glob_hash_files_single(path):
    """Compute @actions/glob hashFiles() digest for a single matched file.

    Upstream `@actions/glob` computes SHA-256 over the raw 32-byte SHA-256
    digest of each matched file rather than hex-encoding intermediate digests.
    """
    raw_digest = hashlib.sha256(Path(path).read_bytes()).digest()
    return hashlib.sha256(raw_digest).hexdigest()


def bazelisk_cache_key(platform, arch, bazelversion_path, cache_version="1"):
    """Build the bazelisk Actions cache key matching setup-bazel config.js + post.js."""
    digest = glob_hash_files_single(bazelversion_path)
    return f"setup-bazel-{cache_version}-{platform}-{arch}-bazelisk-{digest}"


def _resolve_bazelversion_path():
    env_path = os.environ.get("BAZELVERSION_PATH")
    if env_path and os.path.isfile(env_path):
        return Path(env_path)
    return Path(__file__).resolve().parents[3] / ".bazelversion"


def test_bazelversion_matches_live_bazelisk_cache_key():
    bazelversion_path = _resolve_bazelversion_path()
    actual_hash = glob_hash_files_single(bazelversion_path)
    assert actual_hash == LIVE_BAZELISK_HASH
    assert (
        bazelisk_cache_key("linux", "x64", bazelversion_path)
        == f"setup-bazel-1-linux-x64-bazelisk-{LIVE_BAZELISK_HASH}"
    )
    assert (
        bazelisk_cache_key("darwin", "arm64", bazelversion_path)
        == f"setup-bazel-1-darwin-arm64-bazelisk-{LIVE_BAZELISK_HASH}"
    )
    plain_sha256 = hashlib.sha256(bazelversion_path.read_bytes()).hexdigest()
    assert plain_sha256 != LIVE_BAZELISK_HASH


def test_bazelisk_key_changes_when_bazelversion_changes(tmp_path):
    mutated = tmp_path / ".bazelversion"
    mutated.write_text("9.3.3", encoding="utf-8")
    assert glob_hash_files_single(mutated) != LIVE_BAZELISK_HASH
