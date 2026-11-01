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

//! `bazel run //tools/crates:check`: every committed Cargo.lock matches its
//! Cargo.toml files (see fresh.rs). Offline; tidy-check runs it on every PR.

use std::path::{Path, PathBuf};
use std::process::Command;

use crates_lock::fresh::{lock_problems, relock_hint};

fn main() {
    std::process::exit(match run() {
        Ok(code) => code,
        Err(message) => {
            eprintln!("crates:check: {message}");
            1
        }
    });
}

fn run() -> Result<i32, String> {
    let repo = std::env::var_os("BUILD_WORKSPACE_DIRECTORY")
        .map(PathBuf::from)
        .ok_or("run this with `bazel run //tools/crates:check`")?;
    // The committed locks, so a scratch or vendored one cannot fail the check.
    let out = Command::new("git")
        .args(["ls-files", "-z", "--", "*Cargo.lock"])
        .current_dir(&repo)
        .output()
        .map_err(|e| format!("cannot run git: {e}"))?;
    if !out.status.success() {
        return Err(format!(
            "git ls-files failed: {}",
            String::from_utf8_lossy(&out.stderr).trim()
        ));
    }
    let mut lock_dirs: Vec<PathBuf> = String::from_utf8_lossy(&out.stdout)
        .split('\0')
        .map(Path::new)
        .filter(|p| p.file_name().map_or(false, |n| n == "Cargo.lock"))
        .map(|p| p.parent().unwrap_or(Path::new("")).to_path_buf())
        .collect();
    lock_dirs.sort();
    if lock_dirs.is_empty() {
        return Err("git ls-files found no Cargo.lock".into());
    }

    let read = |p: &Path| std::fs::read_to_string(repo.join(p)).ok();
    let mut failed = 0;
    for dir in &lock_dirs {
        let lock = dir.join("Cargo.lock");
        match lock_problems(dir, &read) {
            Ok(problems) if problems.is_empty() => println!("ok    {}", lock.display()),
            Ok(problems) => {
                failed += 1;
                println!("STALE {}", lock.display());
                for p in &problems {
                    println!("        {p}");
                }
                println!("      re-lock: {}", relock_hint(dir));
            }
            Err(e) => {
                failed += 1;
                println!("ERROR {}: {e}", lock.display());
            }
        }
    }
    if failed > 0 {
        eprintln!(
            "crates:check: {failed} of {} Cargo.lock files do not match their Cargo.toml files.",
            lock_dirs.len()
        );
        return Ok(1);
    }
    println!(
        "crates:check: all {} Cargo.lock files match their Cargo.toml files.",
        lock_dirs.len()
    );
    Ok(0)
}
