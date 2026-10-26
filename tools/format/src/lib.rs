// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT
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

//! Rust port of `tools/format/prettier_wrapper.sh`.
//!
//! Locates `prettier_bin` in runfiles (`prettier_bin_/prettier_bin` or via
//! recursive directory search), filters out symlink arguments (`-L "$arg"`),
//! and execs `prettier_bin` with the remaining arguments.

use std::fs;
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::Command;

pub fn find_prettier_recursive(dir: &Path) -> Option<PathBuf> {
    let entries = fs::read_dir(dir).ok()?;
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_file() && entry.file_name() == "prettier_bin" {
            return Some(path);
        }
        if path.is_dir() {
            if let Some(found) = find_prettier_recursive(&path) {
                return Some(found);
            }
        }
    }
    None
}

pub fn locate_prettier_bin(dir: &Path) -> Option<PathBuf> {
    let direct = dir.join("prettier_bin_/prettier_bin");
    if direct.is_file() {
        return Some(direct);
    }
    find_prettier_recursive(dir)
}

pub fn is_symlink_path(arg: &str) -> bool {
    fs::symlink_metadata(arg)
        .map(|m| m.file_type().is_symlink())
        .unwrap_or(false)
}

pub fn filter_non_symlink_args(args: &[String]) -> Vec<String> {
    args.iter()
        .filter(|arg| !is_symlink_path(arg))
        .cloned()
        .collect()
}

pub fn script_dir(argv0: &str) -> PathBuf {
    let p = Path::new(argv0);
    match p.parent() {
        Some(parent) if !parent.as_os_str().is_empty() => parent.to_path_buf(),
        _ => PathBuf::from("."),
    }
}

pub fn run(argv: &[String]) -> i32 {
    let argv0 = argv.first().map(String::as_str).unwrap_or(".");
    let dir = script_dir(argv0);
    let Some(prettier_bin) = locate_prettier_bin(&dir) else {
        eprintln!("ERROR: Could not find prettier_bin in {}", dir.display());
        return 1;
    };
    let rest = if argv.len() > 1 { &argv[1..] } else { &[] };
    let filtered = filter_non_symlink_args(rest);
    let err = Command::new(&prettier_bin).args(&filtered).exec();
    eprintln!("ERROR: Failed to exec {}: {err}", prettier_bin.display());
    1
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::env;
    use std::os::unix::fs::{symlink, PermissionsExt};
    use std::time::{SystemTime, UNIX_EPOCH};

    fn make_temp_dir(prefix: &str) -> PathBuf {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let dir = env::temp_dir().join(format!("{prefix}-{nanos}"));
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn locates_direct_prettier_bin() {
        let dir = make_temp_dir("prettier-direct");
        let sub = dir.join("prettier_bin_");
        fs::create_dir_all(&sub).unwrap();
        let bin = sub.join("prettier_bin");
        fs::write(&bin, "#!/bin/sh\n").unwrap();

        assert_eq!(locate_prettier_bin(&dir), Some(bin));
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn locates_fallback_prettier_bin_recursively() {
        let dir = make_temp_dir("prettier-fallback");
        let nested = dir.join("nested/custom");
        fs::create_dir_all(&nested).unwrap();
        let bin = nested.join("prettier_bin");
        fs::write(&bin, "#!/bin/sh\n").unwrap();

        assert_eq!(locate_prettier_bin(&dir), Some(bin));
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn returns_none_when_prettier_bin_missing() {
        let dir = make_temp_dir("prettier-missing");
        assert_eq!(locate_prettier_bin(&dir), None);
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn filters_out_symlinks_and_keeps_regular_files_and_flags() {
        let dir = make_temp_dir("prettier-symlinks");
        let real_file = dir.join("index.ts");
        let link_file = dir.join("link.ts");
        fs::write(&real_file, "const x = 1;\n").unwrap();
        symlink(&real_file, &link_file).unwrap();

        let args = vec![
            "--write".to_string(),
            real_file.to_string_lossy().into_owned(),
            link_file.to_string_lossy().into_owned(),
        ];
        let filtered = filter_non_symlink_args(&args);
        assert_eq!(
            filtered,
            vec![
                "--write".to_string(),
                real_file.to_string_lossy().into_owned(),
            ]
        );
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn executes_prettier_bin_with_filtered_args() {
        let dir = make_temp_dir("prettier-exec");
        let sub = dir.join("prettier_bin_");
        fs::create_dir_all(&sub).unwrap();
        let bin = sub.join("prettier_bin");
        fs::write(&bin, "#!/bin/sh\nprintf '%s\\n' \"$@\"\n").unwrap();
        fs::set_permissions(&bin, fs::Permissions::from_mode(0o755)).unwrap();

        let real_file = dir.join("a.json");
        let link_file = dir.join("b.json");
        fs::write(&real_file, "{}\n").unwrap();
        symlink(&real_file, &link_file).unwrap();

        let located = locate_prettier_bin(&dir).unwrap();
        let filtered = filter_non_symlink_args(&[
            "--check".to_string(),
            real_file.to_string_lossy().into_owned(),
            link_file.to_string_lossy().into_owned(),
        ]);
        let out = Command::new(&located).args(&filtered).output().unwrap();
        assert!(out.status.success());
        let lines: Vec<&str> = std::str::from_utf8(&out.stdout).unwrap().lines().collect();
        assert_eq!(lines, vec!["--check", &real_file.to_string_lossy()]);

        let _ = fs::remove_dir_all(&dir);
    }
}
