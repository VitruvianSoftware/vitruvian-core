// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

use std::collections::BTreeSet;
use std::env;
use std::fs;
use std::path::{Path, PathBuf};

pub const SUBDIRS: &[&str] = &["Sources", "Tests", "Resources", "Tools"];
pub const FILES: &[&str] = &["Package.swift", "build.sh", "UPSTREAM.md"];
pub const EXCLUDED_NAMES: &[&str] = &[".DS_Store"];

pub struct Config {
    pub check: bool,
    pub app_dir: Option<PathBuf>,
}

pub fn parse_args(args: &[String]) -> Result<Config, String> {
    let mut check = false;
    let mut app_dir = None;
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--check" => check = true,
            "--app-dir" => {
                i += 1;
                if i >= args.len() {
                    return Err("--app-dir requires a value".into());
                }
                app_dir = Some(PathBuf::from(&args[i]));
            }
            "-h" | "--help" => {
                return Err("Usage: sync_sources [--check] [--app-dir <path>]".into());
            }
            other => return Err(format!("unknown argument: {}", other)),
        }
        i += 1;
    }
    Ok(Config { check, app_dir })
}

pub fn iter_files(root: &Path) -> Vec<PathBuf> {
    let mut results = Vec::new();
    for subdir in SUBDIRS {
        let base = root.join(subdir);
        if !base.is_dir() {
            continue;
        }
        walk_dir(&base, root, &mut results);
    }
    for filename in FILES {
        let path = root.join(filename);
        if path.is_file() {
            results.push(PathBuf::from(filename));
        }
    }
    results.sort();
    results
}

fn walk_dir(dir: &Path, root: &Path, out: &mut Vec<PathBuf>) {
    let Ok(entries) = fs::read_dir(dir) else {
        return;
    };
    let mut paths: Vec<PathBuf> = entries.filter_map(|e| e.ok().map(|x| x.path())).collect();
    paths.sort();
    for p in paths {
        let name = p
            .file_name()
            .map(|n| n.to_string_lossy().to_string())
            .unwrap_or_default();
        if EXCLUDED_NAMES.contains(&name.as_str()) {
            continue;
        }
        if p.is_dir() {
            walk_dir(&p, root, out);
        } else if p.is_file() {
            if let Ok(rel) = p.strip_prefix(root) {
                out.push(rel.to_path_buf());
            }
        }
    }
}

pub fn copy_tree(src: &Path, dst: &Path) -> Result<usize, String> {
    for subdir in SUBDIRS {
        let target = dst.join(subdir);
        if target.exists() {
            fs::remove_dir_all(&target)
                .map_err(|e| format!("remove {}: {}", target.display(), e))?;
        }
    }
    let files = iter_files(src);
    for rel in &files {
        let s = src.join(rel);
        let d = dst.join(rel);
        if let Some(parent) = d.parent() {
            fs::create_dir_all(parent).map_err(|e| format!("mkdir {}: {}", parent.display(), e))?;
        }
        fs::copy(&s, &d).map_err(|e| format!("copy {}: {}", rel.display(), e))?;
    }
    Ok(files.len())
}

pub fn compare_trees(src: &Path, dst: &Path) -> Vec<String> {
    let src_files: BTreeSet<PathBuf> = iter_files(src).into_iter().collect();
    let dst_files: BTreeSet<PathBuf> = iter_files(dst).into_iter().collect();
    let mut diffs = Vec::new();

    for rel in src_files.difference(&dst_files) {
        diffs.push(format!("missing in destination: {}", rel.display()));
    }
    for rel in dst_files.difference(&src_files) {
        diffs.push(format!("extra in destination: {}", rel.display()));
    }
    for rel in src_files.intersection(&dst_files) {
        let s_bytes = fs::read(src.join(rel)).unwrap_or_default();
        let d_bytes = fs::read(dst.join(rel)).unwrap_or_default();
        if s_bytes != d_bytes {
            diffs.push(format!("differs: {}", rel.display()));
        }
    }
    diffs
}

pub fn run_cli(args: &[String]) -> i32 {
    let config = match parse_args(args) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("{}", e);
            return 2;
        }
    };
    let app_dir = config.app_dir.unwrap_or_else(|| {
        if let Ok(ws) = env::var("BUILD_WORKSPACE_DIRECTORY") {
            PathBuf::from(ws).join("apps/desktop/vitruvian")
        } else {
            env::current_dir().unwrap_or_else(|_| PathBuf::from("."))
        }
    });

    if config.check {
        let diffs = compare_trees(&app_dir, &app_dir);
        if !diffs.is_empty() {
            for line in diffs {
                eprintln!("{}", line);
            }
            return 1;
        }
        println!(
            "{} files verified in {}",
            iter_files(&app_dir).len(),
            app_dir.display()
        );
        return 0;
    }

    match copy_tree(&app_dir, &app_dir) {
        Ok(count) => {
            println!("Synced {} files in {}", count, app_dir.display());
            0
        }
        Err(e) => {
            eprintln!("{}", e);
            1
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_compare_and_copy_trees() {
        let tmp = env::temp_dir().join("test_vitruvian_sync_sources_rs");
        let _ = fs::remove_dir_all(&tmp);
        let src = tmp.join("src");
        let dst = tmp.join("dst");
        fs::create_dir_all(src.join("Sources/App")).unwrap();
        fs::create_dir_all(&dst).unwrap();

        fs::write(src.join("Sources/App/Main.swift"), "let x = 1\n").unwrap();
        fs::write(src.join("Sources/App/.DS_Store"), "junk").unwrap();
        fs::write(src.join("Package.swift"), "// swift-tools-version: 6.0\n").unwrap();

        let diffs = compare_trees(&src, &dst);
        assert_eq!(diffs.len(), 2);
        assert!(diffs
            .iter()
            .any(|d| d.contains("missing in destination: Package.swift")));
        assert!(diffs
            .iter()
            .any(|d| d.contains("missing in destination: Sources/App/Main.swift")));

        let copied = copy_tree(&src, &dst).unwrap();
        assert_eq!(copied, 2);
        assert!(!dst.join("Sources/App/.DS_Store").exists());
        assert!(compare_trees(&src, &dst).is_empty());

        fs::write(dst.join("Sources/App/Main.swift"), "let x = 2\n").unwrap();
        let diffs2 = compare_trees(&src, &dst);
        assert_eq!(diffs2, vec!["differs: Sources/App/Main.swift"]);

        let _ = fs::remove_dir_all(&tmp);
    }
}
