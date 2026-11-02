// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

//! Black-box tests for //tools/ci:llvm_cache_stage, which moves the extracted
//! LLVM toolchain between the Actions cache's fixed stage folder and Bazel's
//! contents cache, so no file pins the content-hash folder name (#2456). Runs
//! the REAL binary on fake extractions. Ported case for case from the former
//! llvm-cache-stage_test.sh.
//!
//! The load-bearing case is the "toolchain moved" round trip: a cache saved
//! under one hash folder, then a build that extracts under a DIFFERENT one,
//! must stage the NEW folder for saving. A hand-pinned folder name got that
//! wrong for ~20 runs after #2419 and paid full LLVM extraction on every
//! Bazel lane.

use ci_testkit::{bin, read, write, Output, Run, TempDir};
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};

fn run(args: &[&Path]) -> Output {
    Run::new(&bin("BIN")).args(args).go()
}

fn run_str(args: &[&str]) -> Output {
    Run::new(&bin("BIN")).args(args).go()
}

fn line(o: &Output) -> String {
    o.stdout.trim_end_matches('\n').to_string()
}

/// A fake extraction: <contents>/<hash>/<candidate>/bin/clang plus the second
/// directory a real extraction materializes alongside it.
fn extract(contents: &Path, hash: &str) {
    write(contents.join(hash).join("cand1/bin/clang"), "clang\n");
    std::fs::create_dir_all(contents.join(hash).join("cand1.meta")).unwrap();
}

fn s(p: &Path) -> String {
    p.display().to_string()
}

struct Lane {
    _dir: TempDir,
    stage: PathBuf,
    contents: PathBuf,
}

impl Lane {
    fn new() -> Lane {
        let dir = TempDir::new();
        Lane {
            stage: dir.join("stage"),
            contents: dir.join("contents"),
            _dir: dir,
        }
    }
}

// --- 1. Miss: nothing restored, nothing left behind for the post step.
#[test]
fn restore_on_a_miss_prints_nothing_and_leaves_no_stage_folder() {
    let l = Lane::new();
    let o = run(&[Path::new("restore"), &l.stage, &l.contents]);
    assert_eq!(o.code, 0, "{o:?}");
    assert_eq!(line(&o), "", "restore on a miss printed something");
    assert!(!l.stage.exists(), "a stage folder exists after a miss");
}

// --- 2. Stage after a build: the live folder is hard-linked, not copied.
#[test]
fn stage_hard_links_the_live_folder_and_leaves_it_in_place() {
    let l = Lane::new();
    extract(&l.contents, "aaaa");
    let o = run(&[Path::new("stage"), &l.stage, &l.contents]);
    assert_eq!(o.code, 0, "{o:?}");
    assert_eq!(line(&o), "aaaa", "stage must print the live hash");
    let staged = l.stage.join("aaaa/cand1/bin/clang");
    let live = l.contents.join("aaaa/cand1/bin/clang");
    assert!(staged.is_file(), "the stage is missing bin/clang");
    assert!(
        live.is_file(),
        "stage removed the live tree later steps need"
    );
    assert_eq!(
        std::fs::metadata(&staged).unwrap().ino(),
        std::fs::metadata(&live).unwrap().ino(),
        "the staged file is a copy, not a hard link (that would copy ~8GB)"
    );
}

// --- 3. Next run restores it: moved into place under its own name.
#[test]
fn restore_moves_a_cached_folder_into_place_and_removes_the_stage() {
    let l = Lane::new();
    extract(&l.stage, "aaaa");
    let o = run(&[Path::new("restore"), &l.stage, &l.contents]);
    assert_eq!(o.code, 0, "{o:?}");
    assert_eq!(
        line(&o),
        s(&l.contents.join("aaaa")),
        "restore must print the restored folder"
    );
    assert!(
        l.contents.join("aaaa/cand1/bin/clang").is_file(),
        "the toolchain is not in contents"
    );
    assert!(
        !l.stage.exists(),
        "the emptied stage folder was left behind"
    );
}

// --- 4. THE CASE THAT BROKE (#2419/#2455): the toolchain moves to a new hash.
// Restored aaaa is ignored by Bazel, which extracts bbbb. Stage must pick bbbb.
#[test]
fn after_a_toolchain_move_stage_saves_the_new_folder() {
    let l = Lane::new();
    extract(&l.stage, "aaaa");
    assert_eq!(run(&[Path::new("restore"), &l.stage, &l.contents]).code, 0);
    // Bazel ignoring the restored folder: only bbbb holds a clang.
    std::fs::remove_dir_all(l.contents.join("aaaa/cand1")).unwrap();
    extract(&l.contents, "bbbb");
    let o = run(&[Path::new("stage"), &l.stage, &l.contents]);
    assert_eq!(
        line(&o),
        "bbbb",
        "stage picked the wrong folder after the toolchain moved"
    );
    assert!(
        !l.stage.join("aaaa").exists(),
        "the stale folder aaaa was staged"
    );
    let live = run(&[Path::new("live"), &l.contents]);
    assert_eq!(
        line(&live),
        s(&l.contents.join("bbbb")),
        "live must report the folder holding clang"
    );
}

// --- 5. Restore never clobbers a folder another cache layer already placed.
#[test]
fn restore_leaves_an_existing_folder_alone_and_still_reports_it() {
    let l = Lane::new();
    extract(&l.contents, "cccc");
    write(l.contents.join("cccc/marker"), "keep\n");
    write(l.stage.join("cccc/marker"), "stale\n");
    let o = run(&[Path::new("restore"), &l.stage, &l.contents]);
    assert_eq!(
        read(l.contents.join("cccc/marker")),
        "keep\n",
        "restore overwrote an existing folder"
    );
    assert_eq!(
        line(&o),
        s(&l.contents.join("cccc")),
        "restore must still report the folder"
    );
    assert!(
        o.stderr.contains("already exists"),
        "say why it was left: {:?}",
        o.stderr
    );
}

// --- 6. A lane that never extracted LLVM stages nothing.
#[test]
fn with_no_clang_nothing_is_staged() {
    let l = Lane::new();
    std::fs::create_dir_all(l.contents.join("other/x")).unwrap();
    let o = run(&[Path::new("stage"), &l.stage, &l.contents]);
    assert_eq!(line(&o), "", "staged something with no LLVM present");
    assert!(
        !l.stage.exists(),
        "a stage folder appeared with no LLVM present"
    );
    assert_eq!(
        line(&run(&[Path::new("live"), &l.contents])),
        "",
        "live reported a folder without clang"
    );
}

// --- 7. Bad usage fails, rather than silently doing nothing.
#[test]
fn a_missing_argument_fails() {
    let l = Lane::new();
    assert_ne!(
        run(&[Path::new("restore"), &l.stage]).code,
        0,
        "restore with a missing arg succeeded"
    );
    assert_ne!(
        run(&[Path::new("stage"), &l.stage]).code,
        0,
        "stage with a missing arg succeeded"
    );
    assert_ne!(
        run_str(&["live"]).code,
        0,
        "live with a missing arg succeeded"
    );
}

#[test]
fn an_unknown_subcommand_fails() {
    assert_ne!(run_str(&["bogus"]).code, 0, "unknown subcommand succeeded");
    assert_ne!(run_str(&[]).code, 0, "no subcommand succeeded");
}
