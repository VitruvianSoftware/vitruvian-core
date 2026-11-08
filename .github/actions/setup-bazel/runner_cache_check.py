# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

"""Find and clear broken entries in the self-hosted runners' shared Bazel caches.

The vitruvian-queue runner pods share one NFS volume for Bazel's repository
cache (~/.cache/bazel-repo) and Bazelisk's binaries (~/.cache/bazelisk).
On 2026-11-08 the weekly cache GC deleted files out of cached repositories
and left them half-empty; every merge-queue job then failed with
"BUILD file not found" in @rules_python until someone cleared the cache by
hand. setup-bazel runs this before Bazel starts, so a broken entry is cleared
by the next job instead of failing every job.

What it checks:

* Repo contents cache (bazel-repo/contents). Bazel 9 keeps each cached repo
  as contents/<predeclared inputs hash>/<uuid>/ beside <uuid>.recorded_inputs,
  and writes the marker only after the directory is complete
  (LocalRepoContentsCache.moveToCache). The first time this script sees a
  complete entry it records the entry's file list (its manifest). Later runs
  check that every listed path is still there. Extra files are fine; a
  missing one means the entry is broken, so it is evicted the way Bazel's own
  GC does it: the marker first (Bazel stops using the entry), then the
  directory. Bazel then refetches the repo, from the download blobs in
  bazel-repo/content_addressable when they are there.

  The cache holds ~170k files, and walking all of them over NFS takes about
  2.5 minutes, so each run checks a random sample of entries within a time
  budget. Damage like 2026-11-08 hits most entries at once, so a sample finds
  it on the first run; when one run finds --escalate broken entries or more,
  the whole contents cache is moved aside in one rename (Bazel rebuilds it).

  A marker whose directory is gone is removed. A directory with no marker is
  a fetch still being moved in, and is left alone.

* Bazelisk binaries (bazelisk/downloads/sha256/<sha>/bin/bazel). The
  directory name is the binary's SHA-256; a mismatch removes that download
  so Bazelisk fetches it again. A read error only warns: on 2026-11-08 one
  was a passing NFS error and the file was fine.

The check never fails the job: every problem it hits is a warning.
"""

import argparse
import hashlib
import os
import random
import sys
import time
import uuid

STATE_DIR = "vitruvian-cache-check"
MARKER_SUFFIX = ".recorded_inputs"
BAZEL_TRASH = "_trash"
MANIFEST_HEADER = "# runner_cache_check manifest v1"


def warn(msg):
    print(f"::warning title=Runner cache check::{msg}", flush=True)


def info(msg):
    print(f"runner_cache_check: {msg}", flush=True)


def listing(root):
    """Every path under root, relative, directories with a trailing slash.

    Uses readdir only (no stat per file), which is what makes a check cheap
    enough to run before a job. Symlinks are listed, never followed.
    """
    out = set()
    stack = [""]
    while stack:
        rel = stack.pop()
        with os.scandir(os.path.join(root, rel) if rel else root) as it:
            for e in it:
                p = f"{rel}{e.name}"
                if e.is_dir(follow_symlinks=False):
                    out.add(p + "/")
                    stack.append(p + "/")
                else:
                    out.add(p)
    return out


def read_manifest(path):
    try:
        with open(path, encoding="utf-8", errors="surrogateescape") as f:
            lines = f.read().split("\n")
    except FileNotFoundError:
        return None
    if not lines or lines[0] != MANIFEST_HEADER:
        return None  # unknown or torn: treat as absent, it gets rewritten
    return {l for l in lines[1:] if l}


def write_manifest(path, paths):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = f"{path}.tmp-{uuid.uuid4().hex}"
    with open(tmp, "w", encoding="utf-8", errors="surrogateescape") as f:
        f.write(MANIFEST_HEADER + "\n")
        f.write("\n".join(sorted(paths)))
        f.write("\n")
    os.replace(tmp, path)


def remove_quietly(path):
    try:
        os.remove(path)
    except FileNotFoundError:
        pass


def rename_quietly(src, dst):
    try:
        os.rename(src, dst)
        return True
    except FileNotFoundError:
        return False


class Check:
    def __init__(
        self, repo_cache, bazelisk_cache, budget, escalate, rng, dry_run=False
    ):
        self.repo_cache = repo_cache
        self.bazelisk_cache = bazelisk_cache
        self.contents = os.path.join(repo_cache, "contents") if repo_cache else None
        self.state = os.path.join(repo_cache, STATE_DIR) if repo_cache else None
        self.manifests = os.path.join(self.state, "manifests") if self.state else None
        self.trash = os.path.join(self.state, "trash") if self.state else None
        self.started = time.monotonic()
        self.deadline = self.started + budget
        self.escalate = escalate
        self.rng = rng
        self.dry_run = dry_run
        self.verb = "would clear" if dry_run else "cleared"
        self.checked = 0
        self.recorded = 0
        self.evicted = []
        self.escalated = False

    def time_left(self):
        return self.deadline - time.monotonic()

    # --- repo contents cache -------------------------------------------------

    def evict(self, entry_hash, entry_id, why):
        """Evict one cached repo the way Bazel's GC does: marker, then dir.

        Lock-free: Bazel servers hold a shared lock on contents/gc_lock while
        they use the cache, so with several runners busy an exclusive lock
        would rarely be had. Removing the marker hides the entry from new
        lookups; a build already using it was failing on the missing files.
        """
        base = os.path.join(self.contents, entry_hash, entry_id)
        if not self.dry_run:
            try:
                os.remove(base + MARKER_SUFFIX)
            except FileNotFoundError:
                return  # Bazel's GC or another runner got there first
            os.makedirs(self.trash, exist_ok=True)
            rename_quietly(base, os.path.join(self.trash, uuid.uuid4().hex))
            remove_quietly(os.path.join(self.manifests, entry_hash, entry_id))
        self.evicted.append(f"{entry_hash}/{entry_id}")
        warn(f"{self.verb} broken cached repo contents/{entry_hash}/{entry_id}: {why}")

    def check_entry_dir(self, entry_hash):
        entry_dir = os.path.join(self.contents, entry_hash)
        try:
            names = set(os.listdir(entry_dir))
        except (FileNotFoundError, NotADirectoryError):
            return
        ids = [n[: -len(MARKER_SUFFIX)] for n in names if n.endswith(MARKER_SUFFIX)]
        for entry_id in ids:
            manifest_path = os.path.join(self.manifests, entry_hash, entry_id)
            repo_dir = os.path.join(entry_dir, entry_id)
            if entry_id not in names or not os.path.isdir(repo_dir):
                self.evict(entry_hash, entry_id, "its marker has no directory")
                continue
            try:
                current = listing(repo_dir)
            except FileNotFoundError:
                continue  # evicted by Bazel's GC or another runner meanwhile
            expected = read_manifest(manifest_path)
            if expected is None:
                if not self.dry_run:
                    write_manifest(manifest_path, current)
                self.recorded += 1
                continue
            self.checked += 1
            missing = expected - current
            if missing:
                sample = ", ".join(sorted(missing)[:3])
                self.evict(
                    entry_hash,
                    entry_id,
                    f"{len(missing)} file(s) missing, e.g. {sample}",
                )
        # Manifests of entries that are gone (Bazel GC, eviction elsewhere).
        if self.dry_run:
            return
        try:
            for name in os.listdir(os.path.join(self.manifests, entry_hash)):
                if ".tmp-" in name or name + MARKER_SUFFIX not in names:
                    remove_quietly(os.path.join(self.manifests, entry_hash, name))
        except FileNotFoundError:
            pass

    def move_contents_aside(self):
        if not self.dry_run:
            os.makedirs(self.trash, exist_ok=True)
            tag = f"{time.strftime('%Y%m%dT%H%M%SZ', time.gmtime())}-{uuid.uuid4().hex[:8]}"
            rename_quietly(self.contents, os.path.join(self.trash, f"contents-{tag}"))
            rename_quietly(self.manifests, os.path.join(self.trash, f"manifests-{tag}"))
        self.escalated = True
        warn(
            f"{len(self.evicted)} broken cached repos in one sample: "
            f"{'would move' if self.dry_run else 'moved'} the whole "
            "repo contents cache aside; Bazel rebuilds it, mostly from the local download blobs"
        )

    def check_contents(self):
        if not self.contents or not os.path.isdir(self.contents):
            return
        hashes = [h for h in os.listdir(self.contents) if h != BAZEL_TRASH]
        self.rng.shuffle(hashes)
        for h in hashes:
            if self.time_left() <= 0:
                break
            self.check_entry_dir(h)
            if len(self.evicted) >= self.escalate:
                self.move_contents_aside()
                return
        # Manifest directories whose entry directory is gone altogether.
        if not self.dry_run and self.manifests and os.path.isdir(self.manifests):
            live = set(hashes)
            stale = [h for h in os.listdir(self.manifests) if h not in live]
            if stale:
                os.makedirs(self.trash, exist_ok=True)
            for h in stale:
                rename_quietly(
                    os.path.join(self.manifests, h),
                    os.path.join(self.trash, uuid.uuid4().hex),
                )

    # --- bazelisk --------------------------------------------------------------

    def check_bazelisk(self):
        if not self.bazelisk_cache:
            return
        sha_dir = os.path.join(self.bazelisk_cache, "downloads", "sha256")
        try:
            digests = os.listdir(sha_dir)
        except FileNotFoundError:
            return
        for digest in digests:
            binary = os.path.join(sha_dir, digest, "bin", "bazel")
            if not os.path.isfile(binary):
                continue
            h = hashlib.sha256()
            try:
                with open(binary, "rb") as f:
                    for chunk in iter(lambda: f.read(1 << 20), b""):
                        h.update(chunk)
            except OSError as e:
                warn(
                    f"could not read Bazelisk's {digest[:12]} binary ({e}); left it in place"
                )
                continue
            if h.hexdigest() != digest:
                if not self.dry_run:
                    remove_quietly(binary)
                warn(
                    f"{'would remove' if self.dry_run else 'removed'} Bazelisk's {digest[:12]} binary: its SHA-256 no longer matches; Bazelisk downloads it again"
                )

    # --- our trash -------------------------------------------------------------

    def empty_trash(self, share):
        """Delete what earlier runs moved aside, within part of the budget."""
        if self.dry_run or not self.trash or not os.path.isdir(self.trash):
            return
        stop = time.monotonic() + max(0.0, self.time_left()) * share
        for top, dirs, files in os.walk(self.trash, topdown=False):
            for name in files:
                if time.monotonic() > stop:
                    return
                try:
                    os.unlink(os.path.join(top, name))
                except OSError:
                    pass
            for name in dirs:
                p = os.path.join(top, name)
                try:
                    if os.path.islink(p):
                        os.unlink(p)
                    else:
                        os.rmdir(p)
                except OSError:
                    pass

    def run(self):
        # A quarter of the budget at most for leftovers, so checking always gets time.
        self.empty_trash(share=0.25)
        self.check_bazelisk()
        self.check_contents()
        self.empty_trash(share=1.0)
        info(
            f"checked {self.checked} cached repos, recorded {self.recorded} new ones, "
            f"{self.verb} {len(self.evicted)}"
            + (" and the whole contents cache" if self.escalated else "")
            + f", {time.monotonic() - self.started:.1f} s"
        )


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--repo-cache", help="Bazel --repository_cache directory")
    p.add_argument(
        "--bazelisk-cache", help="Bazelisk's cache directory (BAZELISK_HOME)"
    )
    p.add_argument("--budget-seconds", type=float, default=20.0)
    p.add_argument(
        "--escalate",
        type=int,
        default=3,
        help="broken entries in one run that mean the whole cache is damaged",
    )
    p.add_argument("--seed", type=int, help="fix the sample order (tests)")
    p.add_argument(
        "--dry-run", action="store_true", help="report only: write and clear nothing"
    )
    args = p.parse_args(argv)
    check = Check(
        args.repo_cache,
        args.bazelisk_cache,
        args.budget_seconds,
        max(1, args.escalate),
        random.Random(args.seed),
        dry_run=args.dry_run,
    )
    try:
        check.run()
    except Exception as e:  # noqa: BLE001 -- never fail the job over the check itself
        warn(f"the cache check stopped early: {type(e).__name__}: {e}")
    return check


if __name__ == "__main__":
    main()
    sys.exit(0)
