// Copyright (c) 2026 VitruvianSoftware
//
// SPDX-License-Identifier: MIT

//! `bazel run //apps/antigravity:hooks-json-gen -- [--check|--write]` (see hooks_json_gen_lib.rs).

use std::path::Path;

fn main() {
    let workspace = match std::env::var("BUILD_WORKSPACE_DIRECTORY") {
        Ok(dir) if !dir.trim().is_empty() => dir,
        _ => {
            eprintln!(
                "error: BUILD_WORKSPACE_DIRECTORY is not set; run via `bazel run //apps/antigravity:hooks-json-gen -- [--check|--write]`"
            );
            std::process::exit(1);
        }
    };

    let args: Vec<String> = std::env::args().skip(1).collect();
    let mode = match args.as_slice() {
        [] => hooks_json_gen::Mode::Check,
        [flag] if flag == "--check" => hooks_json_gen::Mode::Check,
        [flag] if flag == "--write" => hooks_json_gen::Mode::Write,
        _ => {
            eprintln!("usage: hooks-json-gen [--check|--write]");
            std::process::exit(1);
        }
    };

    let code = hooks_json_gen::run_in_workspace(Path::new(&workspace), mode);
    std::process::exit(code);
}
