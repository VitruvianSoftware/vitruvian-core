// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT

//! Tests for the vitruvian-queue-cache GC CronJob (`cache-gc-cronjob.yaml`).
//!
//! They take the script out of the CronJob's `args` and run it with bash
//! against a fake cache, pointed there with `CACHE_ROOT` and with
//! `WATERMARK_KB` set so the prune branch runs or not.
//!
//! The rule they hold: only download blobs under `bazel-repo/content_addressable`
//! are pruned. Files under `bazel-repo/contents` (Bazel's repo contents cache)
//! keep their upstream archives' mtimes, so a per-file mtime sweep there guts
//! repos that are in use. That broke every merge-queue job on 2026-11-08.

#![cfg(test)]

use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{Duration, SystemTime};

const MANIFEST: &str = "gitops/argocd/platform/actions-runners-manifests/cache-gc-cronjob.yaml";
const DAY: u64 = 24 * 60 * 60;

fn manifest_path() -> PathBuf {
    for p in [
        PathBuf::from(MANIFEST),
        PathBuf::from("cache-gc-cronjob.yaml"),
    ] {
        if p.is_file() {
            return p;
        }
    }
    if let Ok(srcdir) = std::env::var("TEST_SRCDIR") {
        let ws = std::env::var("TEST_WORKSPACE").unwrap_or_else(|_| "_main".to_string());
        let p = Path::new(&srcdir).join(ws).join(MANIFEST);
        if p.is_file() {
            return p;
        }
    }
    panic!("cannot find {MANIFEST}");
}

/// The block scalar under the container's `args: - |`, dedented.
fn gc_script() -> String {
    let raw = fs::read_to_string(manifest_path()).expect("read manifest");
    let lines: Vec<&str> = raw.lines().collect();
    let start = lines
        .windows(2)
        .position(|w| w[0].trim() == "args:" && w[1].trim() == "- |")
        .expect("the CronJob has an `args: - |` script")
        + 2;
    let marker_indent = lines[start - 1].len() - lines[start - 1].trim_start().len();
    let body: Vec<&str> = lines[start..]
        .iter()
        .take_while(|l| l.trim().is_empty() || l.len() - l.trim_start().len() > marker_indent)
        .copied()
        .collect();
    let indent = body
        .iter()
        .filter(|l| !l.trim().is_empty())
        .map(|l| l.len() - l.trim_start().len())
        .min()
        .expect("script is not empty");
    body.iter()
        .map(|l| if l.len() >= indent { &l[indent..] } else { "" })
        .collect::<Vec<_>>()
        .join("\n")
}

fn scratch(name: &str) -> PathBuf {
    let base = std::env::var("TEST_TMPDIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| std::env::temp_dir());
    let dir = base.join(format!("cache-gc-{name}-{}", std::process::id()));
    let _ = fs::remove_dir_all(&dir);
    fs::create_dir_all(&dir).expect("create scratch dir");
    dir
}

fn write(root: &Path, rel: &str, age_days: u64) -> PathBuf {
    let p = root.join(rel);
    fs::create_dir_all(p.parent().unwrap()).unwrap();
    fs::write(&p, b"x").unwrap();
    let mtime = SystemTime::now() - Duration::from_secs(age_days * DAY);
    fs::File::options()
        .write(true)
        .open(&p)
        .unwrap()
        .set_modified(mtime)
        .unwrap();
    p
}

/// A fake cache: an old and a new download blob, and an old file inside a
/// cached repository, as the contents cache holds them after extraction.
struct FakeCache {
    root: PathBuf,
    old_blob: PathBuf,
    new_blob: PathBuf,
    repo_file: PathBuf,
}

fn fake_cache(name: &str) -> FakeCache {
    let root = scratch(name);
    FakeCache {
        old_blob: write(&root, "bazel-repo/content_addressable/sha256/aa/file", 30),
        new_blob: write(&root, "bazel-repo/content_addressable/sha256/bb/file", 1),
        repo_file: write(
            &root,
            "bazel-repo/contents/0123abcd/python/config_settings/BUILD.bazel",
            400,
        ),
        root,
    }
}

fn run_gc(root: &Path, watermark_kb: &str) {
    let out = Command::new("bash")
        .arg("-c")
        .arg(gc_script())
        .env("CACHE_ROOT", root)
        .env("WATERMARK_KB", watermark_kb)
        .output()
        .expect("run bash");
    assert!(
        out.status.success(),
        "GC script failed: {}\n{}",
        String::from_utf8_lossy(&out.stdout),
        String::from_utf8_lossy(&out.stderr)
    );
}

#[test]
fn above_watermark_prunes_old_blobs_and_never_touches_repo_contents() {
    let c = fake_cache("above");
    run_gc(&c.root, "0");
    assert!(
        !c.old_blob.exists(),
        "a download blob older than 14 days is pruned"
    );
    assert!(c.new_blob.exists(), "a recent download blob is kept");
    assert!(
        c.repo_file.exists(),
        "a file inside the repo contents cache is never deleted, however old its mtime"
    );
    assert!(
        c.root.join("bazel-repo/contents/0123abcd/python").is_dir(),
        "the cached repo's directories are kept"
    );
}

#[test]
fn below_watermark_prunes_nothing() {
    let c = fake_cache("below");
    run_gc(&c.root, "999999999");
    assert!(c.old_blob.exists());
    assert!(c.new_blob.exists());
    assert!(c.repo_file.exists());
}

#[test]
fn no_cache_dir_is_not_an_error() {
    run_gc(&scratch("empty"), "0");
}
