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

//! Shared helpers for the integration suites: each suite runs one of the
//! tool binaries as a subprocess, with stub programs (`pulumi`, `gcloud`,
//! `gh`, `sleep`, ...) on a private PATH so every external call is
//! observable without touching a real backend.

#![allow(dead_code)]

use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Output, Stdio};
use std::sync::atomic::{AtomicUsize, Ordering};

/// The binary under test, from the env var the BUILD file sets to its
/// `$(rootpath ...)`. Relative paths resolve against the test's working
/// directory (the runfiles tree under `bazel test`).
pub fn bin(var: &str) -> PathBuf {
    let raw = std::env::var(var).unwrap_or_else(|_| panic!("{var} is not set"));
    let p = PathBuf::from(&raw);
    let p = if p.is_absolute() {
        p
    } else {
        std::env::current_dir().unwrap().join(p)
    };
    assert!(p.is_file(), "{var}={raw} does not exist");
    p
}

static N: AtomicUsize = AtomicUsize::new(0);

/// A fresh, empty directory under $TEST_TMPDIR (or the system temp dir).
pub fn tempdir(tag: &str) -> PathBuf {
    let base = std::env::var("TEST_TMPDIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| std::env::temp_dir());
    let d = base.join(format!(
        "{tag}-{}-{}",
        std::process::id(),
        N.fetch_add(1, Ordering::SeqCst)
    ));
    let _ = std::fs::remove_dir_all(&d);
    std::fs::create_dir_all(&d).unwrap();
    d
}

/// Write an executable file (a stub program) and return its path.
pub fn write_exec(path: &Path, body: &str) -> PathBuf {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).unwrap();
    }
    std::fs::write(path, body).unwrap();
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o755)).unwrap();
    path.to_path_buf()
}

pub fn read(path: &Path) -> String {
    std::fs::read_to_string(path).unwrap_or_default()
}

/// A command for `bin` with an EMPTY environment plus `PATH`. Tests add what
/// they need, so nothing leaks in from the machine running the suite.
pub fn cmd(bin: &Path, path: &str) -> Command {
    let mut c = Command::new(bin);
    c.env_clear().env("PATH", path).stdin(Stdio::null());
    c
}

pub fn run(mut c: Command) -> Output {
    c.output().expect("spawn binary under test")
}

pub fn code(o: &Output) -> i32 {
    o.status.code().unwrap_or(-1)
}

pub fn stdout(o: &Output) -> String {
    String::from_utf8_lossy(&o.stdout).into_owned()
}

pub fn stderr(o: &Output) -> String {
    String::from_utf8_lossy(&o.stderr).into_owned()
}
