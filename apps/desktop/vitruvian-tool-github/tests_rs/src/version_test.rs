// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

use std::path::PathBuf;
use tests_rs_lib::version;

fn base_dir() -> PathBuf {
    if let Ok(runfiles) = std::env::var("RUNFILES_DIR") {
        let candidate = PathBuf::from(&runfiles).join("_main/apps/desktop/vitruvian-tool-github");
        if candidate.join("vitruvian-tool.json").exists() {
            return candidate;
        }
    }
    let manifest = std::env::current_dir().unwrap();
    if manifest.join("vitruvian-tool.json").exists() {
        return manifest;
    }
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .unwrap()
        .parent()
        .unwrap()
        .to_path_buf()
}

#[test]
fn version_checks_pass() {
    let base = base_dir();
    let problems = version::check_version(&base);
    if !problems.is_empty() {
        for p in &problems {
            eprintln!("{p}");
        }
        panic!("{} version problem(s)", problems.len());
    }
    println!("the tool's version is consistent across all files");
}
