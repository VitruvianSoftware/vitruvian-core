// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

fn copy_dir_deref(src: &Path, dst: &Path) -> std::io::Result<()> {
    fs::create_dir_all(dst)?;
    for entry in fs::read_dir(src)? {
        let entry = entry?;
        let src_path = entry.path();
        let real = if src_path.is_symlink() {
            fs::canonicalize(&src_path)?
        } else {
            src_path.clone()
        };
        let dst_path = dst.join(entry.file_name());
        if real.is_dir() {
            copy_dir_deref(&real, &dst_path)?;
        } else {
            fs::copy(&real, &dst_path)?;
        }
    }
    Ok(())
}

fn make_scratch(prefix: &str) -> PathBuf {
    let base = env::var("TEST_TMPDIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| env::temp_dir());
    let id = std::process::id();
    let ts = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let dir = base.join(format!("{prefix}-{id}-{ts}"));
    fs::create_dir_all(&dir).expect("cannot create scratch dir");
    dir
}

pub struct ConformancePaths {
    pub manifest: PathBuf,
    pub conformance_bin: PathBuf,
    pub validate_bin: PathBuf,
}

pub fn resolve_paths(args: &[String]) -> ConformancePaths {
    let manifest = env::var("MANIFEST_PATH")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from(args.get(1).expect("missing manifest arg")));
    let conformance_bin = env::var("CONFORMANCE_BIN")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from(args.get(2).expect("missing conformance arg")));
    let validate_bin = env::var("VALIDATE_BIN")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from(args.get(3).expect("missing validate arg")));
    ConformancePaths {
        manifest,
        conformance_bin,
        validate_bin,
    }
}

pub fn run_conformance(paths: &ConformancePaths) -> i32 {
    let manifest = fs::canonicalize(&paths.manifest).expect("cannot resolve manifest path");
    let built = manifest.parent().expect("manifest has no parent directory");

    let scratch = make_scratch("conformance");
    let folder = scratch.join("github");
    copy_dir_deref(built, &folder).expect("cannot copy built folder");

    let validate_bin = fs::canonicalize(&paths.validate_bin).expect("cannot resolve validate bin");
    let conformance_bin =
        fs::canonicalize(&paths.conformance_bin).expect("cannot resolve conformance bin");

    let checks: Vec<(&str, Vec<&std::ffi::OsStr>)> = vec![
        (
            "validate",
            vec![
                validate_bin.as_os_str(),
                std::ffi::OsStr::new("validate"),
                folder.as_os_str(),
            ],
        ),
        (
            "conformance",
            vec![conformance_bin.as_os_str(), folder.as_os_str()],
        ),
    ];

    let mut failed = 0;
    for (name, cmd_parts) in &checks {
        let output = Command::new(cmd_parts[0])
            .args(&cmd_parts[1..])
            .env("HOME", &scratch)
            .output()
            .unwrap_or_else(|e| panic!("failed to run {name}: {e}"));
        let stdout = String::from_utf8_lossy(&output.stdout);
        let stderr = String::from_utf8_lossy(&output.stderr);
        println!(
            "--- {name}: exit {}\n{stdout}{stderr}",
            output.status.code().unwrap_or(-1)
        );
        if !output.status.success() {
            failed += 1;
        }
    }
    if failed > 0 {
        println!("{failed} of 2 checks failed");
        return 1;
    }
    println!("the built GitHub tool validates and passes the conformance script");
    0
}
