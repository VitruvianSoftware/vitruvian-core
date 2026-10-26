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

//! llvm-cache-stage.sh — move the extracted LLVM toolchain between the cache's
//! fixed stage folder and Bazel's contents cache.

use shell_compat::{basename, cat, err, out, status};
#[cfg(unix)]
use std::os::unix::ffi::OsStrExt;
use std::process::Command;

fn llvm_live_dir(contents: &[u8]) -> Option<Vec<u8>> {
    let pattern = cat(&[contents, b"/*/*/bin/clang"]);
    let pattern_s = match std::str::from_utf8(&pattern) {
        Ok(s) => s,
        Err(_) => return None,
    };
    for entry in glob_matches(pattern_s) {
        // entry = contents/<hash>/<candidate>/bin/clang
        // We want contents/<hash>
        let p = shell_compat::path(&entry);
        let hash_dir = p.parent()?.parent()?.parent()?;
        return Some(shell_compat::path_bytes(hash_dir));
    }
    None
}

fn glob_matches(pattern: &str) -> Vec<Vec<u8>> {
    let mut results = Vec::new();
    // Manual glob: walk contents/*/* looking for bin/clang
    let parts: Vec<&str> = pattern.splitn(2, "/*/*/").collect();
    if parts.len() != 2 {
        return results;
    }
    let base = parts[0];
    if let Ok(entries) = std::fs::read_dir(base) {
        for e in entries.flatten() {
            if e.path().is_dir() {
                if let Ok(subs) = std::fs::read_dir(e.path()) {
                    for s in subs.flatten() {
                        if s.path().is_dir() {
                            let clang = s.path().join("bin").join("clang");
                            if clang.exists() {
                                results.push(shell_compat::path_bytes(&clang));
                            }
                        }
                    }
                }
            }
        }
    }
    results
}

fn llvm_restore(stage: &[u8], contents: &[u8]) -> i32 {
    if !shell_compat::is_dir(stage) {
        return 0;
    }
    let _ = shell_compat::mkdir_p(contents);
    let mut restored = Vec::new();

    if let Ok(entries) = std::fs::read_dir(shell_compat::path(stage)) {
        for e in entries.flatten() {
            if !e.path().is_dir() {
                continue;
            }
            let name = e.path().file_name().unwrap().as_bytes().to_vec();
            let dest = cat(&[contents, b"/", &name]);
            if shell_compat::exists(&dest) {
                err(&cat(&[
                    b"llvm-cache-stage: ",
                    &dest,
                    b" already exists; leaving it\n",
                ]));
                restored = dest;
                continue;
            }
            if std::fs::rename(e.path(), shell_compat::path(&dest)).is_ok() {
                restored = dest;
            }
        }
    }

    let _ = std::fs::remove_dir_all(shell_compat::path(stage));
    if !restored.is_empty() {
        out(&cat(&[&restored, b"\n"]));
    }
    0
}

fn llvm_stage(stage: &[u8], contents: &[u8]) -> i32 {
    let live = match llvm_live_dir(contents) {
        Some(d) => d,
        None => {
            err(&cat(&[
                b"llvm-cache-stage: no extracted LLVM under ",
                contents,
                b"; nothing to stage\n",
            ]));
            return 0;
        }
    };

    let _ = std::fs::remove_dir_all(shell_compat::path(stage));
    let _ = shell_compat::mkdir_p(stage);

    let rc = status(
        94,
        Command::new("cp")
            .arg("-al")
            .arg(shell_compat::os(&live))
            .arg(shell_compat::os(&cat(&[stage, b"/"]))),
        false,
    );
    if rc != 0 {
        let _ = std::fs::remove_dir_all(shell_compat::path(stage));
        err(&cat(&[
            b"llvm-cache-stage: cannot hard-link ",
            &live,
            b" into ",
            stage,
            b" (different filesystems?); not staging rather than copying ~8GB\n",
        ]));
        return 1;
    }
    out(&cat(&[&basename(&live), b"\n"]));
    0
}

fn llvm_live(contents: &[u8]) -> i32 {
    if let Some(d) = llvm_live_dir(contents) {
        out(&cat(&[&d, b"\n"]));
    }
    0
}

pub fn run(args: &[Vec<u8>]) -> i32 {
    let cmd = args.first().map(|v| v.as_slice()).unwrap_or(b"");
    match cmd {
        b"restore" => {
            if args.len() != 3 {
                err(b"usage: llvm-cache-stage restore <stage> <contents>\n");
                return 2;
            }
            llvm_restore(&args[1], &args[2])
        }
        b"stage" => {
            if args.len() != 3 {
                err(b"usage: llvm-cache-stage stage <stage> <contents>\n");
                return 2;
            }
            llvm_stage(&args[1], &args[2])
        }
        b"live" => {
            if args.len() != 2 {
                err(b"usage: llvm-cache-stage live <contents>\n");
                return 2;
            }
            llvm_live(&args[1])
        }
        _ => {
            err(b"usage: llvm-cache-stage {restore|stage|live} ...\n");
            2
        }
    }
}
