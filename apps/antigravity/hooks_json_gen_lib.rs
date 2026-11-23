// Copyright (c) 2026 VitruvianSoftware
//
// SPDX-License-Identifier: MIT

//! Generates and drift-checks the plugin copies of the hooks JSON helper.
//!
//! Each Antigravity plugin installs standalone and compiles `hooks/src/*.rs`
//! on the user's machine with bare `rustc` (`hooks/rust-hook.sh`), so the
//! source file must be checked in inside every plugin that uses it. This
//! library keeps all copies generated from one source of truth.

use std::fs;
use std::io::ErrorKind;
use std::path::Path;

pub const SOURCE_PATH: &str = "apps/antigravity/hook_json_helper.rs";
pub const GENERATOR_TARGET: &str = "//apps/antigravity:hooks-json-gen";
pub const GENERATED_HEADER: &str = "// Generated from apps/antigravity/hook_json_helper.rs by //apps/antigravity:hooks-json-gen. Do not edit; run `bazel run //apps/antigravity:hooks-json-gen -- --write`.";
pub const PLUGIN_OUTPUTS: [&str; 4] = [
    "apps/antigravity/plugins/hookify/hooks/src/json.rs",
    "apps/antigravity/plugins/live-context/hooks/src/json.rs",
    "apps/antigravity/plugins/ralph-loop/hooks/src/json.rs",
    "apps/antigravity/plugins/security-guidance/hooks/src/json.rs",
];

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Mode {
    Check,
    Write,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Diff {
    pub missing: Vec<String>,
    pub different: Vec<String>,
    pub unchanged: usize,
}

impl Diff {
    pub fn is_clean(&self) -> bool {
        self.missing.is_empty() && self.different.is_empty()
    }
}

/// Prepends the generated-file header to the canonical JSON helper source.
pub fn render(source: &str) -> String {
    format!("{GENERATED_HEADER}\n\n{source}")
}

/// Reads the canonical source under `repo_root`, renders the expected output,
/// and compares every target path on disk.
pub fn check_in_root(repo_root: &Path) -> Result<(String, Diff), String> {
    let source_abs = repo_root.join(SOURCE_PATH);
    let source = fs::read_to_string(&source_abs)
        .map_err(|e| format!("failed to read {SOURCE_PATH}: {e}"))?;
    let expected = render(&source);

    let mut missing = Vec::new();
    let mut different = Vec::new();
    let mut unchanged = 0usize;

    for rel in PLUGIN_OUTPUTS {
        let path = repo_root.join(rel);
        match fs::read_to_string(&path) {
            Ok(actual) if actual == expected => unchanged += 1,
            Ok(_) => different.push(rel.to_string()),
            Err(e) if e.kind() == ErrorKind::NotFound => missing.push(rel.to_string()),
            Err(e) => return Err(format!("failed to read {rel}: {e}")),
        }
    }

    Ok((
        expected,
        Diff {
            missing,
            different,
            unchanged,
        },
    ))
}

/// Runs `--check` or `--write` against `repo_root` and returns a process exit code.
pub fn run_in_workspace(repo_root: &Path, mode: Mode) -> i32 {
    let (expected, diff) = match check_in_root(repo_root) {
        Ok(res) => res,
        Err(e) => {
            eprintln!("error: {e}");
            return 1;
        }
    };

    match mode {
        Mode::Check => {
            if diff.is_clean() {
                println!(
                    "hooks-json-gen: all {} generated files up to date",
                    PLUGIN_OUTPUTS.len()
                );
                0
            } else {
                for p in &diff.missing {
                    eprintln!("missing: {p}");
                }
                for p in &diff.different {
                    eprintln!("different: {p}");
                }
                eprintln!("run: bazel run {GENERATOR_TARGET} -- --write");
                1
            }
        }
        Mode::Write => {
            let mut written = 0usize;
            for rel in diff.missing.iter().chain(diff.different.iter()) {
                let full_path = repo_root.join(rel);
                if let Some(parent) = full_path.parent() {
                    if let Err(e) = fs::create_dir_all(parent) {
                        eprintln!("error creating directory {}: {e}", parent.display());
                        return 1;
                    }
                }
                if let Err(e) = fs::write(&full_path, &expected) {
                    eprintln!("error writing {rel}: {e}");
                    return 1;
                }
                written += 1;
            }
            println!("written {written}, unchanged {}", diff.unchanged);
            0
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;
    use std::sync::atomic::{AtomicU64, Ordering};

    struct TempDirGuard(PathBuf);

    impl TempDirGuard {
        fn new(label: &str) -> Self {
            static SEQ: AtomicU64 = AtomicU64::new(0);
            let id = SEQ.fetch_add(1, Ordering::Relaxed);
            let dir = std::env::temp_dir().join(format!(
                "hooks-json-gen-{label}-{}-{id}",
                std::process::id()
            ));
            let _ = fs::remove_dir_all(&dir);
            fs::create_dir_all(&dir).expect("create temp test dir");
            Self(dir)
        }
    }

    impl Drop for TempDirGuard {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    #[test]
    fn generated_copies_match_source_drift_test() {
        let source = fs::read_to_string(SOURCE_PATH)
            .unwrap_or_else(|e| panic!("{SOURCE_PATH} must exist in test runfiles: {e}"));
        let expected = render(&source);

        for rel in PLUGIN_OUTPUTS {
            let on_disk = fs::read_to_string(rel)
                .unwrap_or_else(|e| panic!("generated file missing {rel}: {e}"));
            assert_eq!(
                on_disk, expected,
                "generated file {rel} drifted from {SOURCE_PATH}; run `bazel run {GENERATOR_TARGET} -- --write`"
            );
        }

        let conformance_files = std::env::var("CONFORMANCE_FILES")
            .expect("CONFORMANCE_FILES must be set by BUILD for hooks_json_drift_test");
        let discovered: Vec<&str> = conformance_files
            .split_whitespace()
            .filter(|p| p.ends_with("/hooks/src/json.rs"))
            .collect();
        for path in &discovered {
            assert!(
                PLUGIN_OUTPUTS
                    .iter()
                    .any(|out| *path == *out || path.ends_with(&format!("/{out}"))),
                "unmanaged plugin JSON helper {path}; add it to PLUGIN_OUTPUTS in apps/antigravity/hooks_json_gen_lib.rs"
            );
        }
        assert_eq!(
            discovered.len(),
            PLUGIN_OUTPUTS.len(),
            "expected {} plugin json.rs files in CONFORMANCE_FILES, got {}: {discovered:?}",
            PLUGIN_OUTPUTS.len(),
            discovered.len()
        );
    }

    #[test]
    fn render_prepends_header_and_is_deterministic() {
        let sample = "// Copyright (c) 2026 VitruvianSoftware\npub fn hello() {}\n";
        let first = render(sample);
        let second = render(sample);
        assert_eq!(first, second);
        assert_eq!(first, format!("{GENERATED_HEADER}\n\n{sample}"));
    }

    #[test]
    fn check_and_write_detect_and_repair_drift() {
        let tmp = TempDirGuard::new("drift");
        let source_path = tmp.0.join(SOURCE_PATH);
        fs::create_dir_all(source_path.parent().unwrap()).unwrap();
        let sample = "// canonical\npub fn answer() -> i32 { 42 }\n";
        fs::write(&source_path, sample).unwrap();

        assert_eq!(run_in_workspace(&tmp.0, Mode::Check), 1);
        assert_eq!(run_in_workspace(&tmp.0, Mode::Write), 0);
        assert_eq!(run_in_workspace(&tmp.0, Mode::Check), 0);

        let first_out = tmp.0.join(PLUGIN_OUTPUTS[0]);
        let mut drifted = fs::read_to_string(&first_out).unwrap();
        drifted.push_str("// drifted\n");
        fs::write(&first_out, drifted).unwrap();

        assert_eq!(run_in_workspace(&tmp.0, Mode::Check), 1);
        let (_, diff) = check_in_root(&tmp.0).unwrap();
        assert_eq!(diff.missing, Vec::<String>::new());
        assert_eq!(diff.different, vec![PLUGIN_OUTPUTS[0].to_string()]);
        assert_eq!(diff.unchanged, PLUGIN_OUTPUTS.len() - 1);

        assert_eq!(run_in_workspace(&tmp.0, Mode::Write), 0);
        assert_eq!(run_in_workspace(&tmp.0, Mode::Check), 0);
        assert_eq!(fs::read_to_string(&first_out).unwrap(), render(sample));
    }
}
