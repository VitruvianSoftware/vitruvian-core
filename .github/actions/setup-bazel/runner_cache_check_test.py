# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

"""Tests for runner_cache_check.py against fake caches laid out as Bazel 9 and
Bazelisk lay them out on the vitruvian-queue runners' shared volume."""

import hashlib
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import runner_cache_check as rcc

DAY = 24 * 60 * 60


def put(root, rel, data=b"x", age_days=0):
    p = os.path.join(root, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "wb") as f:
        f.write(data)
    if age_days:
        t = time.time() - age_days * DAY
        os.utime(p, (t, t))
    return p


def cached_repo(cache, entry_hash, entry_id, files, marker=True):
    """A repo contents cache entry: <hash>/<uuid>/... plus <uuid>.recorded_inputs."""
    base = os.path.join(cache, "contents", entry_hash, entry_id)
    for rel, age in files.items():
        put(base, rel, age_days=age)
    if marker:
        put(cache, f"contents/{entry_hash}/{entry_id}.recorded_inputs", b"inputs")
    return base


RULES_PYTHON = {
    "BUILD.bazel": 400,
    "MODULE.bazel": 400,
    "python/config_settings/BUILD.bazel": 400,
    "python/private/py_library.bzl": 400,
    "python/private/recent.bzl": 1,
}


def run(cache, **kw):
    args = [
        "--repo-cache",
        str(cache),
        "--seed",
        "1",
        "--budget-seconds",
        str(kw.pop("budget", 30)),
    ]
    for k, v in kw.items():
        args += [f"--{k.replace('_', '-')}", str(v)]
    return rcc.main(args)


def marker(base):
    return base + ".recorded_inputs"


def test_a_healthy_repo_is_recorded_then_kept(tmp_path):
    repo = cached_repo(tmp_path, "aa", "id1", RULES_PYTHON)
    first = run(tmp_path)
    assert first.recorded == 1 and not first.evicted
    second = run(tmp_path)
    assert second.checked == 1 and not second.evicted
    assert os.path.isfile(os.path.join(repo, "python/config_settings/BUILD.bazel"))
    assert os.path.isfile(marker(repo))


def test_2026_11_08_damage_is_cleared(tmp_path):
    """The old GC deleted every file older than 14 days out of cached repos."""
    broken = cached_repo(tmp_path, "aa", "id1", RULES_PYTHON)
    healthy = cached_repo(tmp_path, "bb", "id2", {"BUILD.bazel": 1, "defs.bzl": 1})
    run(tmp_path)  # records both
    cutoff = time.time() - 14 * DAY
    for top, _, files in os.walk(os.path.join(tmp_path, "contents")):
        for f in files:
            p = os.path.join(top, f)
            if os.path.getmtime(p) < cutoff:
                os.remove(p)
    assert not os.path.exists(
        os.path.join(broken, "python/config_settings/BUILD.bazel")
    )

    result = run(tmp_path)

    assert result.evicted == ["aa/id1"]
    assert not os.path.exists(marker(broken)), "Bazel must stop finding the broken repo"
    assert not os.path.exists(broken), "the broken repo is cleared"
    assert os.path.isfile(marker(healthy)) and os.path.isdir(healthy), (
        "only the broken repo goes"
    )
    assert not os.path.exists(
        os.path.join(tmp_path, rcc.STATE_DIR, "manifests", "aa", "id1")
    )
    # The next run records the refetched repo afresh and keeps it.
    cached_repo(tmp_path, "aa", "id3", RULES_PYTHON)
    assert run(tmp_path).recorded == 1


def test_extra_files_are_not_damage(tmp_path):
    repo = cached_repo(tmp_path, "aa", "id1", RULES_PYTHON)
    run(tmp_path)
    put(repo, "python/private/__pycache__/py_library.cpython-314.pyc")
    assert not run(tmp_path).evicted


def test_a_missing_directory_is_damage(tmp_path):
    repo = cached_repo(tmp_path, "aa", "id1", RULES_PYTHON)
    run(tmp_path)
    for f in ("python/config_settings/BUILD.bazel",):
        os.remove(os.path.join(repo, f))
    os.rmdir(os.path.join(repo, "python/config_settings"))
    assert run(tmp_path).evicted == ["aa/id1"]


def test_a_marker_without_its_directory_is_removed(tmp_path):
    put(tmp_path, "contents/aa/id1.recorded_inputs", b"inputs")
    result = run(tmp_path)
    assert result.evicted == ["aa/id1"]
    assert not os.path.exists(os.path.join(tmp_path, "contents/aa/id1.recorded_inputs"))


def test_a_repo_still_being_moved_in_is_left_alone(tmp_path):
    """Bazel renames the directory in first and the marker last."""
    repo = cached_repo(tmp_path, "aa", "id1", RULES_PYTHON, marker=False)
    result = run(tmp_path)
    assert result.recorded == 0 and not result.evicted
    assert os.path.isdir(repo)
    assert not os.path.exists(
        os.path.join(tmp_path, rcc.STATE_DIR, "manifests", "aa", "id1")
    )


def test_wide_damage_moves_the_whole_contents_cache_aside(tmp_path):
    for i in range(5):
        cached_repo(tmp_path, f"h{i}", f"id{i}", RULES_PYTHON)
    run(tmp_path)
    for i in range(5):
        os.remove(os.path.join(tmp_path, f"contents/h{i}/id{i}/MODULE.bazel"))

    result = run(tmp_path, escalate=3)

    assert result.escalated
    assert not os.path.exists(os.path.join(tmp_path, "contents")), "Bazel recreates it"
    assert not os.listdir(os.path.join(tmp_path, rcc.STATE_DIR, "trash")), (
        "emptied within budget"
    )


def test_manifests_of_entries_bazel_collected_are_dropped(tmp_path):
    repo = cached_repo(tmp_path, "aa", "id1", RULES_PYTHON)
    cached_repo(tmp_path, "bb", "id2", RULES_PYTHON)
    run(tmp_path)
    # Bazel's own GC: marker first, then the directory into contents/_trash.
    os.remove(marker(repo))
    os.rename(repo, os.path.join(tmp_path, "contents", "_trash"))
    os.rename(
        os.path.join(tmp_path, "contents", "bb"), os.path.join(tmp_path, "gone-bb")
    )

    result = run(tmp_path)

    assert not result.evicted
    manifests = os.path.join(tmp_path, rcc.STATE_DIR, "manifests")
    assert not os.path.exists(os.path.join(manifests, "aa", "id1"))
    assert not os.path.exists(os.path.join(manifests, "bb"))


def test_the_budget_bounds_the_sample(tmp_path):
    for i in range(20):
        cached_repo(tmp_path, f"h{i:02d}", "id", {"BUILD.bazel": 1})
    result = run(tmp_path, budget=0)
    assert result.recorded == 0 and result.checked == 0


def test_no_caches_is_not_an_error(tmp_path):
    result = rcc.main(
        [
            "--repo-cache",
            str(tmp_path / "nope"),
            "--bazelisk-cache",
            str(tmp_path / "nope2"),
        ]
    )
    assert not result.evicted


def test_unexpected_errors_never_fail_the_job(tmp_path, monkeypatch, capsys):
    cached_repo(tmp_path, "aa", "id1", RULES_PYTHON)

    def boom(*_):
        raise PermissionError("denied")

    monkeypatch.setattr(rcc, "listing", boom)
    run(tmp_path)
    assert "stopped early: PermissionError" in capsys.readouterr().out


def bazelisk_binary(home, data):
    digest = hashlib.sha256(data).hexdigest()
    return digest, put(home, f"downloads/sha256/{digest}/bin/bazel", data)


def test_a_corrupt_bazelisk_binary_is_removed(tmp_path):
    _, good = bazelisk_binary(tmp_path, b"bazel 9.3.0")
    _, bad = bazelisk_binary(tmp_path, b"bazel 9.2.0")
    with open(bad, "r+b") as f:
        f.truncate(3)
    rcc.main(["--bazelisk-cache", str(tmp_path)])
    assert os.path.isfile(good)
    assert not os.path.exists(bad)


def test_a_dry_run_writes_and_clears_nothing(tmp_path):
    repo = cached_repo(tmp_path, "aa", "id1", RULES_PYTHON)
    run(tmp_path)
    os.remove(os.path.join(repo, "MODULE.bazel"))
    cached_repo(tmp_path, "bb", "id2", RULES_PYTHON)
    before = sorted(p for p, _, _ in os.walk(tmp_path))

    result = rcc.main(["--repo-cache", str(tmp_path), "--dry-run"])

    assert result.evicted == ["aa/id1"]
    assert os.path.isfile(marker(repo))
    assert sorted(p for p, _, _ in os.walk(tmp_path)) == before
