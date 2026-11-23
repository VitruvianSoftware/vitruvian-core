// Copyright (c) 2026 VitruvianSoftware
//
// SPDX-License-Identifier: MIT

//! Generates and drift-checks the shared Antigravity plugin hook files.
//!
//! Each Antigravity plugin installs standalone and compiles `hooks/src/*.rs`
//! on the user's machine with bare `rustc` (`hooks/rust-hook.sh`), so the
//! shared launcher, its test script, and the JSON helper must be checked in
//! inside every plugin that uses them. This library keeps all copies
//! generated from single sources of truth under `apps/antigravity/`.

use std::collections::HashSet;
use std::fs;
use std::io::ErrorKind;
use std::path::Path;

pub const GENERATOR_TARGET: &str = "//apps/antigravity:hooks-gen";

pub const ALL_PLUGINS: [&str; 9] = [
    "ext-marketplace",
    "gh-watch",
    "hookify",
    "live-context",
    "ralph-loop",
    "receipts-report",
    "savvy-fleet",
    "security-guidance",
    "worktree-band",
];

pub const JSON_HELPER_PLUGINS: [&str; 4] =
    ["hookify", "live-context", "ralph-loop", "security-guidance"];

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FileKind {
    Rust,
    Shell,
}

impl FileKind {
    pub const fn is_executable(self) -> bool {
        matches!(self, Self::Shell)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct GeneratedGroup {
    pub source: &'static str,
    pub plugin_rel_path: &'static str,
    pub kind: FileKind,
    pub plugins: &'static [&'static str],
}

pub const GROUPS: [GeneratedGroup; 3] = [
    GeneratedGroup {
        source: "apps/antigravity/hook_json_helper.rs",
        plugin_rel_path: "hooks/src/json.rs",
        kind: FileKind::Rust,
        plugins: &JSON_HELPER_PLUGINS,
    },
    GeneratedGroup {
        source: "apps/antigravity/hook_rust_hook.sh",
        plugin_rel_path: "hooks/rust-hook.sh",
        kind: FileKind::Shell,
        plugins: &ALL_PLUGINS,
    },
    GeneratedGroup {
        source: "apps/antigravity/hook_rust_hook_test.sh",
        plugin_rel_path: "hooks/rust-hook_test.sh",
        kind: FileKind::Shell,
        plugins: &ALL_PLUGINS,
    },
];

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Mode {
    Check,
    Write,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ExpectedOutput {
    pub rel_path: String,
    pub content: String,
    pub executable: bool,
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

pub fn total_outputs() -> usize {
    GROUPS.iter().map(|g| g.plugins.len()).sum()
}

pub fn output_path(plugin: &str, plugin_rel_path: &str) -> String {
    format!("apps/antigravity/plugins/{plugin}/{plugin_rel_path}")
}

pub fn generated_header(source: &str, kind: FileKind) -> String {
    let comment = match kind {
        FileKind::Rust => "//",
        FileKind::Shell => "#",
    };
    format!(
        "{comment} Generated from {source} by {GENERATOR_TARGET}. Do not edit; run `bazel run {GENERATOR_TARGET} -- --write`."
    )
}

/// Inserts the generated-file header into `source`.
///
/// Rust sources receive the header on line 1; shell sources keep their `#!`
/// shebang on line 1 and receive the header on line 2.
pub fn render(source: &str, source_path: &str, kind: FileKind) -> Result<String, String> {
    let header = generated_header(source_path, kind);
    match kind {
        FileKind::Rust => Ok(format!("{header}\n\n{source}")),
        FileKind::Shell => {
            let Some((first_line, rest)) = source.split_once('\n') else {
                return Err(format!(
                    "{source_path}: shell source must start with a #! shebang line"
                ));
            };
            if !first_line.starts_with("#!") {
                return Err(format!("{source_path}: line 1 must be a #! shebang"));
            }
            Ok(format!("{first_line}\n{header}\n{rest}"))
        }
    }
}

#[cfg(unix)]
fn has_owner_exec(path: &Path) -> Result<bool, std::io::Error> {
    use std::os::unix::fs::PermissionsExt;
    let mode = fs::metadata(path)?.permissions().mode();
    Ok(mode & 0o100 != 0)
}

#[cfg(not(unix))]
fn has_owner_exec(_path: &Path) -> Result<bool, std::io::Error> {
    Ok(true)
}

#[cfg(unix)]
fn ensure_executable(path: &Path) -> Result<(), std::io::Error> {
    use std::os::unix::fs::PermissionsExt;
    let mut perms = fs::metadata(path)?.permissions();
    perms.set_mode(0o755);
    fs::set_permissions(path, perms)
}

#[cfg(not(unix))]
fn ensure_executable(_path: &Path) -> Result<(), std::io::Error> {
    Ok(())
}

/// Reads each canonical source under `repo_root`, renders the expected outputs,
/// and compares every target path (contents and executable bit) on disk.
pub fn check_in_root(repo_root: &Path) -> Result<(Vec<ExpectedOutput>, Diff), String> {
    let mut outputs = Vec::with_capacity(total_outputs());
    let mut missing = Vec::new();
    let mut different = Vec::new();
    let mut unchanged = 0usize;

    for group in GROUPS {
        let source_abs = repo_root.join(group.source);
        let source = fs::read_to_string(&source_abs)
            .map_err(|e| format!("failed to read {}: {e}", group.source))?;
        let expected = render(&source, group.source, group.kind)?;
        let executable = group.kind.is_executable();

        for plugin in group.plugins {
            let rel = output_path(plugin, group.plugin_rel_path);
            let path = repo_root.join(&rel);
            match fs::read_to_string(&path) {
                Ok(actual) => {
                    let exec_ok = if executable {
                        has_owner_exec(&path).map_err(|e| format!("failed to stat {rel}: {e}"))?
                    } else {
                        true
                    };
                    if actual == expected && exec_ok {
                        unchanged += 1;
                    } else {
                        different.push(rel.clone());
                    }
                }
                Err(e) if e.kind() == ErrorKind::NotFound => missing.push(rel.clone()),
                Err(e) => return Err(format!("failed to read {rel}: {e}")),
            }
            outputs.push(ExpectedOutput {
                rel_path: rel,
                content: expected.clone(),
                executable,
            });
        }
    }

    Ok((
        outputs,
        Diff {
            missing,
            different,
            unchanged,
        },
    ))
}

/// Runs `--check` or `--write` against `repo_root` and returns a process exit code.
pub fn run_in_workspace(repo_root: &Path, mode: Mode) -> i32 {
    let (outputs, diff) = match check_in_root(repo_root) {
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
                    "hooks-gen: all {} generated files up to date",
                    outputs.len()
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
            let dirty: HashSet<&str> = diff
                .missing
                .iter()
                .chain(diff.different.iter())
                .map(String::as_str)
                .collect();
            let mut written = 0usize;
            for out in &outputs {
                if !dirty.contains(out.rel_path.as_str()) {
                    continue;
                }
                let full_path = repo_root.join(&out.rel_path);
                if let Some(parent) = full_path.parent() {
                    if let Err(e) = fs::create_dir_all(parent) {
                        eprintln!("error creating directory {}: {e}", parent.display());
                        return 1;
                    }
                }
                if let Err(e) = fs::write(&full_path, &out.content) {
                    eprintln!("error writing {}: {e}", out.rel_path);
                    return 1;
                }
                if out.executable {
                    if let Err(e) = ensure_executable(&full_path) {
                        eprintln!("error setting mode 0755 on {}: {e}", out.rel_path);
                        return 1;
                    }
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
            let dir =
                std::env::temp_dir().join(format!("hooks-gen-{label}-{}-{id}", std::process::id()));
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
        let conformance_files = std::env::var("CONFORMANCE_FILES")
            .expect("CONFORMANCE_FILES must be set by BUILD for hooks_drift_test");

        for group in GROUPS {
            let source = fs::read_to_string(group.source)
                .unwrap_or_else(|e| panic!("{} must exist in test runfiles: {e}", group.source));
            let expected = render(&source, group.source, group.kind)
                .unwrap_or_else(|e| panic!("render {}: {e}", group.source));

            for plugin in group.plugins {
                let rel = output_path(plugin, group.plugin_rel_path);
                let on_disk = fs::read_to_string(&rel)
                    .unwrap_or_else(|e| panic!("generated file missing {rel}: {e}"));
                assert_eq!(
                    on_disk, expected,
                    "generated file {rel} drifted from {}; run `bazel run {GENERATOR_TARGET} -- --write`",
                    group.source
                );
            }

            let suffix = format!("/{}", group.plugin_rel_path);
            let discovered: Vec<&str> = conformance_files
                .split_whitespace()
                .filter(|p| p.ends_with(&suffix))
                .collect();
            for path in &discovered {
                assert!(
                    group.plugins.iter().any(|plugin| {
                        let out = output_path(plugin, group.plugin_rel_path);
                        *path == out || path.ends_with(&format!("/{out}"))
                    }),
                    "unmanaged plugin file {path}; add it to GROUPS in apps/antigravity/hooks_gen_lib.rs"
                );
            }
            assert_eq!(
                discovered.len(),
                group.plugins.len(),
                "expected {} plugin {} files in CONFORMANCE_FILES, got {}: {discovered:?}",
                group.plugins.len(),
                group.plugin_rel_path,
                discovered.len()
            );
        }
    }

    #[test]
    fn render_headers_are_deterministic_and_preserve_shebang() {
        let rust_sample = "// Copyright (c) 2026 VitruvianSoftware\npub fn hello() {}\n";
        let rust_first = render(rust_sample, "apps/antigravity/a.rs", FileKind::Rust).unwrap();
        let rust_second = render(rust_sample, "apps/antigravity/a.rs", FileKind::Rust).unwrap();
        assert_eq!(rust_first, rust_second);
        assert_eq!(
            rust_first,
            format!(
                "{}\n\n{rust_sample}",
                generated_header("apps/antigravity/a.rs", FileKind::Rust)
            )
        );

        let shell_sample = "#!/bin/sh\n# Copyright (c) 2026 VitruvianSoftware\necho ok\n";
        let shell_first = render(shell_sample, "apps/antigravity/a.sh", FileKind::Shell).unwrap();
        let shell_second = render(shell_sample, "apps/antigravity/a.sh", FileKind::Shell).unwrap();
        assert_eq!(shell_first, shell_second);
        let lines: Vec<&str> = shell_first.lines().collect();
        assert_eq!(lines[0], "#!/bin/sh");
        assert_eq!(
            lines[1],
            generated_header("apps/antigravity/a.sh", FileKind::Shell)
        );
        assert_eq!(lines[2], "# Copyright (c) 2026 VitruvianSoftware");
        assert_eq!(lines[3], "echo ok");

        assert!(render(
            "echo no shebang\n",
            "apps/antigravity/bad.sh",
            FileKind::Shell
        )
        .is_err());
    }

    #[test]
    fn check_and_write_detect_and_repair_drift() {
        let tmp = TempDirGuard::new("drift");
        let rust_sample = "// canonical\npub fn answer() -> i32 { 42 }\n";
        let sh_sample = "#!/bin/sh\n# canonical\necho ok\n";
        let test_sample = "#!/bin/sh\n# canonical test\necho pass\n";

        let samples = [
            (GROUPS[0].source, rust_sample),
            (GROUPS[1].source, sh_sample),
            (GROUPS[2].source, test_sample),
        ];
        for (src_rel, body) in samples {
            let p = tmp.0.join(src_rel);
            fs::create_dir_all(p.parent().unwrap()).unwrap();
            fs::write(&p, body).unwrap();
        }

        assert_eq!(run_in_workspace(&tmp.0, Mode::Check), 1);
        assert_eq!(run_in_workspace(&tmp.0, Mode::Write), 0);
        assert_eq!(run_in_workspace(&tmp.0, Mode::Check), 0);

        let json_out_rel = output_path(JSON_HELPER_PLUGINS[0], GROUPS[0].plugin_rel_path);
        let sh_out_rel = output_path(ALL_PLUGINS[0], GROUPS[1].plugin_rel_path);
        let test_out_rel = output_path(ALL_PLUGINS[1], GROUPS[2].plugin_rel_path);

        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let sh_mode = fs::metadata(tmp.0.join(&sh_out_rel))
                .unwrap()
                .permissions()
                .mode();
            assert_eq!(sh_mode & 0o777, 0o755);

            let mut perms = fs::metadata(tmp.0.join(&test_out_rel))
                .unwrap()
                .permissions();
            perms.set_mode(0o644);
            fs::set_permissions(tmp.0.join(&test_out_rel), perms).unwrap();
        }

        let mut drifted_json = fs::read_to_string(tmp.0.join(&json_out_rel)).unwrap();
        drifted_json.push_str("// drifted\n");
        fs::write(tmp.0.join(&json_out_rel), drifted_json).unwrap();

        let mut drifted_sh = fs::read_to_string(tmp.0.join(&sh_out_rel)).unwrap();
        drifted_sh.push_str("# drifted\n");
        fs::write(tmp.0.join(&sh_out_rel), drifted_sh).unwrap();

        assert_eq!(run_in_workspace(&tmp.0, Mode::Check), 1);
        let (_, diff) = check_in_root(&tmp.0).unwrap();
        assert_eq!(diff.missing, Vec::<String>::new());
        #[cfg(unix)]
        {
            assert_eq!(
                diff.different,
                vec![
                    json_out_rel.clone(),
                    sh_out_rel.clone(),
                    test_out_rel.clone()
                ]
            );
            assert_eq!(diff.unchanged, total_outputs() - 3);
        }

        assert_eq!(run_in_workspace(&tmp.0, Mode::Write), 0);
        assert_eq!(run_in_workspace(&tmp.0, Mode::Check), 0);
        assert_eq!(
            fs::read_to_string(tmp.0.join(&sh_out_rel)).unwrap(),
            render(sh_sample, GROUPS[1].source, FileKind::Shell).unwrap()
        );
        #[cfg(unix)]
        {
            assert!(has_owner_exec(&tmp.0.join(&test_out_rel)).unwrap());
        }
    }
}
