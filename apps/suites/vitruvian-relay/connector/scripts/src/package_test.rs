// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

//! The installer's placement against the real pinned desktop-commander:
//! copied out of the runfiles the way `:install` copies it, the copy stands
//! alone (no link back into Bazel's output tree) and holds a pinned `rg`
//! for this platform that runs. Builds `layout.rs` on its own, so only a
//! change to it or to the package (dc/) runs this test and its npm fetch.

#![allow(dead_code)]

#[path = "layout.rs"]
mod layout;

use std::path::{Path, PathBuf};

fn runfiles() -> PathBuf {
    std::env::var_os("RUNFILES_DIR")
        .or_else(|| std::env::var_os("TEST_SRCDIR"))
        .map(PathBuf::from)
        .expect("run under bazel test")
}

fn assert_self_contained(root: &Path, dir: &Path) {
    for e in std::fs::read_dir(dir).unwrap() {
        let p = e.unwrap().path();
        let m = std::fs::symlink_metadata(&p).unwrap();
        if m.file_type().is_symlink() {
            let t = std::fs::read_link(&p).unwrap();
            assert!(t.is_relative(), "{} -> {}", p.display(), t.display());
            let real = std::fs::canonicalize(&p)
                .unwrap_or_else(|e| panic!("{} -> {}: {e}", p.display(), t.display()));
            assert!(
                real.starts_with(root),
                "{} -> {}",
                p.display(),
                real.display()
            );
        } else if m.is_dir() {
            assert_self_contained(root, &p);
        }
    }
}

#[test]
fn the_installed_copy_carries_a_working_rg() {
    let src = runfiles().join("_main/apps/suites/vitruvian-relay/connector/dc/node_modules");
    assert!(src
        .join(layout::DC_PACKAGE)
        .join(layout::DC_ENTRY)
        .is_file());
    let tmp = std::env::var_os("TEST_TMPDIR")
        .map(PathBuf::from)
        .unwrap_or_else(std::env::temp_dir)
        .join(format!("vrelay-package-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&tmp);
    std::fs::create_dir_all(&tmp).unwrap();
    let dst = tmp.join("node_modules");
    layout::copy_tree(&src, &dst).unwrap();
    let root = std::fs::canonicalize(&dst).unwrap();
    assert_self_contained(&root, &dst);
    assert!(dst
        .join(layout::DC_PACKAGE)
        .join(layout::DC_ENTRY)
        .is_file());
    let platform = layout::rg_platform().expect("a platform @vscode/ripgrep ships");
    let rg = layout::find_rg(&dst, &platform).unwrap();
    let out = std::process::Command::new(&rg)
        .arg("--version")
        .output()
        .unwrap();
    assert!(out.status.success(), "{}", rg.display());
    let v = String::from_utf8_lossy(&out.stdout);
    assert!(v.starts_with("ripgrep "), "{v}");
    let _ = std::fs::remove_dir_all(&tmp);
}
