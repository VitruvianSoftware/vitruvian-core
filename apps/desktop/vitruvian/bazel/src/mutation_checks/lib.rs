// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

pub mod mutations;
pub use mutations::{Mutation, MUTATIONS};

use std::path::{Path, PathBuf};
use std::process::Command;

pub fn stale_fixtures(root: &Path) -> Vec<String> {
    stale_fixtures_for(root, MUTATIONS)
}

pub fn stale_fixtures_for(root: &Path, mutations: &[Mutation]) -> Vec<String> {
    let mut problems = Vec::new();
    for m in mutations {
        let path = root.join(m.relative);
        let content = match std::fs::read_to_string(&path) {
            Ok(c) => c,
            Err(_) => {
                problems.push(format!(
                    "{}: {} is not there (a new file must also be in the test's data)",
                    m.name, m.relative
                ));
                continue;
            }
        };
        let found = content.matches(m.before).count();
        if found != 1 {
            problems.push(format!(
                "{}: {} holds the quoted text {} times, not once",
                m.name, m.relative, found
            ));
        } else if m.before == m.after {
            problems.push(format!("{}: the mutation changes nothing", m.name));
        }
    }
    problems
}

pub fn check(root: &Path) -> i32 {
    let problems = stale_fixtures(root);
    if !problems.is_empty() {
        eprintln!(
            "These mutations in Tests/mutation_checks.py no longer match the source they quote.\n\
             Update each to plant the same regression in the code as it is now:\n  {}",
            problems.join("\n  ")
        );
        return 1;
    }
    println!(
        "MUTATION FIXTURES OK ({} mutations match their source)",
        MUTATIONS.len()
    );
    0
}

pub fn run(
    workspace: &Path,
    bazel_flags: &[String],
    test_arguments: &[String],
    timeout_secs: u64,
) -> Result<(i32, String), String> {
    let unit_tests = "//apps/desktop/vitruvian:unit_tests";
    let mut cmd = Command::new("bazel");
    cmd.arg("test")
        .arg("--config=macos-app")
        .arg("--nocache_test_results")
        .arg("--test_output=all");
    for flag in bazel_flags {
        cmd.arg(flag);
    }
    for arg in test_arguments {
        cmd.arg(format!("--test_arg={}", arg));
    }
    cmd.arg(unit_tests);
    cmd.current_dir(workspace);
    cmd.stdout(std::process::Stdio::piped());
    cmd.stderr(std::process::Stdio::piped());

    let child = cmd
        .spawn()
        .map_err(|e| format!("failed to start bazel: {}", e))?;

    let output = if timeout_secs > 0 {
        let start = std::time::Instant::now();
        let limit = std::time::Duration::from_secs(timeout_secs);
        let result = child.wait_with_output();
        if start.elapsed() > limit {
            return Err("Mutation run timed out; this is not a detected regression".to_string());
        }
        result.map_err(|e| format!("failed to wait for bazel: {}", e))?
    } else {
        child
            .wait_with_output()
            .map_err(|e| format!("failed to wait for bazel: {}", e))?
    };

    let combined = String::from_utf8_lossy(&output.stdout).to_string()
        + &String::from_utf8_lossy(&output.stderr);
    let code = output.status.code().unwrap_or(1);
    Ok((code, combined))
}

pub fn run_mutation_suite(
    workspace: &Path,
    root: &Path,
    bazel_flags: &[String],
) -> Result<(), String> {
    let paths: std::collections::BTreeSet<&str> = MUTATIONS.iter().map(|m| m.relative).collect();
    let output = Command::new("git")
        .args(["status", "--porcelain", "--"])
        .args(paths.iter())
        .current_dir(root)
        .output()
        .map_err(|e| format!("git status failed: {}", e))?;
    let dirty = String::from_utf8_lossy(&output.stdout);
    if !dirty.is_empty() {
        return Err(format!(
            "Commit or stash these first; the checks edit them in place:\n{}",
            dirty
        ));
    }

    let stale = stale_fixtures(root);
    if !stale.is_empty() {
        return Err(format!(
            "Mutation fixtures need updating:\n  {}",
            stale.join("\n  ")
        ));
    }

    println!("Checking the unmodified baseline…");
    let (status, output_text) = run(workspace, bazel_flags, &[], 3600)?;
    if status != 0 || !output_text.contains("TESTS OK") {
        let tail: String = output_text
            .chars()
            .rev()
            .take(12000)
            .collect::<String>()
            .chars()
            .rev()
            .collect();
        return Err(format!("Baseline failed:\n{}", tail));
    }

    for m in MUTATIONS {
        let path = root.join(m.relative);
        let original = std::fs::read_to_string(&path)
            .map_err(|e| format!("failed to read {}: {}", m.relative, e))?;
        if original.matches(m.before).count() != 1 {
            return Err(format!("Mutation fixture needs updating: {}", m.name));
        }
        println!("Checking: {}…", m.name);
        let mutated = original.replacen(m.before, m.after, 1);
        std::fs::write(&path, &mutated)
            .map_err(|e| format!("failed to write {}: {}", m.relative, e))?;

        let result = run(
            workspace,
            bazel_flags,
            &[format!("--suite={}", m.group)],
            1800,
        );

        std::fs::write(&path, &original)
            .map_err(|e| format!("failed to restore {}: {}", m.relative, e))?;

        let (status, output_text) = result?;
        if status != 3
            || !output_text.contains("TESTS FAILED")
            || !output_text.contains(m.diagnostic)
        {
            let tail: String = output_text
                .chars()
                .rev()
                .take(12000)
                .collect::<String>()
                .chars()
                .rev()
                .collect();
            return Err(format!(
                "Mutation was not caught by its intended assertion: {}\n{}",
                m.name, tail
            ));
        }
        println!("DETECTED: {}", m.name);
    }

    println!(
        "MUTATION CHECKS OK ({} regressions detected)",
        MUTATIONS.len()
    );
    Ok(())
}

pub fn run_cli(args: &[String]) -> i32 {
    if args.first().map(|s| s.as_str()) == Some("--check") {
        if args.len() != 3 || args.get(1).map(|s| s.as_str()) != Some("--app-dir") {
            eprintln!("usage: mutation_checks --check --app-dir <folder>");
            return 1;
        }
        return check(Path::new(&args[2]));
    }

    let workspace = std::env::var("BUILD_WORKSPACE_DIRECTORY")
        .map(PathBuf::from)
        .unwrap_or_else(|_| {
            Path::new(file!())
                .canonicalize()
                .unwrap_or_default()
                .ancestors()
                .nth(5)
                .unwrap_or(Path::new("."))
                .to_path_buf()
        });
    let root = workspace.join("apps/desktop/vitruvian");
    let bazel_flags: Vec<String> = args.to_vec();

    match run_mutation_suite(&workspace, &root, &bazel_flags) {
        Ok(()) => 0,
        Err(e) => {
            eprintln!("{}", e);
            1
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::sync::atomic::{AtomicU64, Ordering};

    static COUNTER: AtomicU64 = AtomicU64::new(0);

    fn make_temp_dir() -> PathBuf {
        let id = COUNTER.fetch_add(1, Ordering::SeqCst);
        let dir = std::env::temp_dir().join(format!(
            "mutation_checks_test_{}_{}",
            std::process::id(),
            id
        ));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).expect("failed to create temp dir");
        dir
    }

    #[test]
    fn stale_fixtures_valid() {
        let dir = make_temp_dir();
        fs::write(dir.join("src.swift"), "prefix BEFORE_TEXT suffix").unwrap();

        let mutations = &[Mutation {
            name: "test mutation",
            group: "test",
            relative: "src.swift",
            before: "BEFORE_TEXT",
            after: "AFTER_TEXT",
            diagnostic: "should fail",
        }];

        let problems = stale_fixtures_for(&dir, mutations);
        assert!(
            problems.is_empty(),
            "expected no problems, got: {:?}",
            problems
        );
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn stale_fixtures_missing_file() {
        let dir = make_temp_dir();

        let mutations = &[Mutation {
            name: "missing file mutation",
            group: "test",
            relative: "does_not_exist.swift",
            before: "anything",
            after: "something",
            diagnostic: "irrelevant",
        }];

        let problems = stale_fixtures_for(&dir, mutations);
        assert_eq!(problems.len(), 1);
        assert!(problems[0].contains("is not there"));
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn stale_fixtures_zero_occurrences() {
        let dir = make_temp_dir();
        fs::write(dir.join("src.swift"), "nothing matching here").unwrap();

        let mutations = &[Mutation {
            name: "zero match",
            group: "test",
            relative: "src.swift",
            before: "NONEXISTENT",
            after: "REPLACEMENT",
            diagnostic: "irrelevant",
        }];

        let problems = stale_fixtures_for(&dir, mutations);
        assert_eq!(problems.len(), 1);
        assert!(problems[0].contains("0 times"));
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn stale_fixtures_two_occurrences() {
        let dir = make_temp_dir();
        fs::write(dir.join("src.swift"), "TEXT TEXT").unwrap();

        let mutations = &[Mutation {
            name: "two matches",
            group: "test",
            relative: "src.swift",
            before: "TEXT",
            after: "OTHER",
            diagnostic: "irrelevant",
        }];

        let problems = stale_fixtures_for(&dir, mutations);
        assert_eq!(problems.len(), 1);
        assert!(problems[0].contains("2 times"));
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn stale_fixtures_before_equals_after() {
        let dir = make_temp_dir();
        fs::write(dir.join("src.swift"), "some SAME text").unwrap();

        let mutations = &[Mutation {
            name: "noop mutation",
            group: "test",
            relative: "src.swift",
            before: "SAME",
            after: "SAME",
            diagnostic: "irrelevant",
        }];

        let problems = stale_fixtures_for(&dir, mutations);
        assert_eq!(problems.len(), 1);
        assert!(problems[0].contains("changes nothing"));
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn cli_check_missing_app_dir_arg() {
        let code = run_cli(&["--check".to_string()]);
        assert_eq!(code, 1);
    }

    #[test]
    fn cli_check_wrong_second_arg() {
        let code = run_cli(&[
            "--check".to_string(),
            "--wrong".to_string(),
            "/tmp".to_string(),
        ]);
        assert_eq!(code, 1);
    }

    #[test]
    fn mutations_count() {
        assert_eq!(
            MUTATIONS.len(),
            573,
            "expected 573 mutations from the Python source"
        );
    }

    #[test]
    fn mutations_first_entry() {
        let first = &MUTATIONS[0];
        assert_eq!(first.name, "call audio protection is absent by default");
        assert_eq!(first.group, "mixer");
        assert_eq!(
            first.relative,
            "Sources/Vitruvian/Core/Audio/MixerRoutingSupport.swift"
        );
    }

    #[test]
    fn mutations_last_entry() {
        let last = &MUTATIONS[MUTATIONS.len() - 1];
        assert_eq!(
            last.name,
            "capturing the Spaces drag refuses the middle button"
        );
        assert_eq!(last.group, "pointer-input");
    }

    #[test]
    fn mutations_no_empty_names() {
        for m in MUTATIONS {
            assert!(!m.name.is_empty(), "mutation has empty name");
            assert!(!m.group.is_empty(), "mutation {} has empty group", m.name);
            assert!(
                !m.relative.is_empty(),
                "mutation {} has empty relative",
                m.name
            );
            assert!(
                !m.diagnostic.is_empty(),
                "mutation {} has empty diagnostic",
                m.name
            );
        }
    }

    #[test]
    fn mutations_unique_names() {
        let mut seen = std::collections::HashSet::new();
        for m in MUTATIONS {
            assert!(seen.insert(m.name), "duplicate mutation name: {}", m.name);
        }
    }
}
