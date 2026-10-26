// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

use std::path::PathBuf;
use tests_rs_lib::mirror_workflows;

fn workflows_dir() -> PathBuf {
    if let Ok(runfiles) = std::env::var("RUNFILES_DIR") {
        let candidate = PathBuf::from(&runfiles)
            .join("_main/apps/desktop/vitruvian-tool-github/.github/workflows");
        if candidate.join("release.yml").exists() {
            return candidate;
        }
    }
    let cwd = std::env::current_dir().unwrap();
    let candidate = cwd.join(".github/workflows");
    if candidate.join("release.yml").exists() {
        return candidate;
    }
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .unwrap()
        .parent()
        .unwrap()
        .join(".github/workflows")
}

#[test]
fn detect_step_cases() {
    let dir = workflows_dir();
    let release = mirror_workflows::load_workflow(&dir.join("release.yml"));
    let problems = mirror_workflows::detect_problems(&release);
    if !problems.is_empty() {
        for p in &problems {
            eprintln!("{p}");
        }
        panic!("{} detect problem(s)", problems.len());
    }
}

#[test]
fn release_notes_cases() {
    let dir = workflows_dir();
    let release = mirror_workflows::load_workflow(&dir.join("release.yml"));
    let problems = mirror_workflows::notes_problems(&release);
    if !problems.is_empty() {
        for p in &problems {
            eprintln!("{p}");
        }
        panic!("{} notes problem(s)", problems.len());
    }
}

#[test]
fn workflow_limits() {
    let dir = workflows_dir();
    let mut problems = Vec::new();
    for name in ["ci.yml", "release.yml"] {
        let wf = mirror_workflows::load_workflow(&dir.join(name));
        problems.extend(mirror_workflows::limit_problems(name, &wf));
    }
    if !problems.is_empty() {
        for p in &problems {
            eprintln!("{p}");
        }
        panic!("{} limit problem(s)", problems.len());
    }
    println!("mirror workflows: OK");
}
