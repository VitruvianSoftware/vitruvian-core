# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

"""Tests for libxml2_debs.sh shared deb metadata and checksum verification."""

import hashlib
import os
import re
import subprocess
from pathlib import Path


def _resolve_script_path() -> Path:
    env_path = os.environ.get("LIBXML2_DEBS_SCRIPT")
    if env_path and os.path.isfile(env_path):
        return Path(env_path)
    return Path(__file__).resolve().parent / "libxml2_debs.sh"


def test_sha_key_has_two_sha256_digests():
    proc = subprocess.run(
        ["bash", str(_resolve_script_path()), "sha-key"],
        capture_output=True,
        text=True,
        check=True,
    )
    key = proc.stdout.strip()
    assert re.fullmatch(r"[0-9a-f]{64}-[0-9a-f]{64}", key), (
        f"unexpected sha-key: {key!r}"
    )


def test_fetch_reuses_valid_cached_files_without_network(tmp_path: Path):
    script = _resolve_script_path()
    text = script.read_text(encoding="utf-8")
    icu_bytes = b"fake-libicu74-deb"
    xml_bytes = b"fake-libxml2-deb"
    icu_sha = hashlib.sha256(icu_bytes).hexdigest()
    xml_sha = hashlib.sha256(xml_bytes).hexdigest()

    patched = script.parent / "patched.sh"
    # Run on a temp copy with known test sha256s and dead URLs so any network
    # attempt fails immediately.
    test_script = tmp_path / "libxml2_debs_test_copy.sh"
    modified = text
    modified = re.sub(
        r'LIBICU74_SHA256="[0-9a-f]+"',
        f'LIBICU74_SHA256="{icu_sha}"',
        modified,
    )
    modified = re.sub(
        r'LIBXML2_SHA256="[0-9a-f]+"',
        f'LIBXML2_SHA256="{xml_sha}"',
        modified,
    )
    modified = modified.replace("http://archive.ubuntu.com", "http://127.0.0.1:9")
    modified = modified.replace("http://security.ubuntu.com", "http://127.0.0.1:9")
    modified = modified.replace("http://azure.archive.ubuntu.com", "http://127.0.0.1:9")
    modified = modified.replace("https://snapshot.ubuntu.com", "http://127.0.0.1:9")
    test_script.write_text(modified, encoding="utf-8")

    cache_dir = tmp_path / "ci-debs"
    cache_dir.mkdir()
    (cache_dir / "libicu74.deb").write_bytes(icu_bytes)
    (cache_dir / "libxml2.deb").write_bytes(xml_bytes)

    proc = subprocess.run(
        ["bash", str(test_script), "fetch", str(cache_dir)],
        capture_output=True,
        text=True,
        check=False,
    )
    assert proc.returncode == 0, proc.stderr
    assert "Using verified libicu74.deb" in proc.stdout
    assert "Using verified libxml2.deb" in proc.stdout

    # Corrupting one cached file forces fallback download (which fails on dead URL).
    (cache_dir / "libxml2.deb").write_bytes(b"corrupted")
    bad_proc = subprocess.run(
        ["bash", str(test_script), "fetch", str(cache_dir)],
        capture_output=True,
        text=True,
        check=False,
    )
    assert bad_proc.returncode != 0
    assert not patched.exists()
