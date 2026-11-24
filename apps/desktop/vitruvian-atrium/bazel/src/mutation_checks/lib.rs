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
    let unit_tests = "//apps/desktop/vitruvian-atrium:unit_tests";
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

/// One slice of the mutations: mutation `i` (in `MUTATIONS` order) belongs
/// to shard `i % count`. The whole list is `Shard::ALL`.
///
/// The list outgrew one CI job: 584 mutations at about 105 s each is some
/// 17 hours, and a macOS job may run for 5.5. Each scheduled run takes one
/// shard, so every mutation still runs, a shard at a time.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Shard {
    pub index: usize,
    pub count: usize,
}

impl Shard {
    pub const ALL: Shard = Shard { index: 0, count: 1 };

    /// Reads `K/N`, with `0 <= K < N`.
    pub fn parse(text: &str) -> Result<Shard, String> {
        let (k, n) = text
            .split_once('/')
            .ok_or_else(|| format!("--shard takes K/N, not {:?}", text))?;
        let index: usize = k
            .trim()
            .parse()
            .map_err(|_| format!("--shard: {:?} is not a number", k))?;
        let count: usize = n
            .trim()
            .parse()
            .map_err(|_| format!("--shard: {:?} is not a number", n))?;
        if count == 0 || index >= count {
            return Err(format!(
                "--shard {}/{}: K must be at least 0 and less than N",
                index, count
            ));
        }
        Ok(Shard { index, count })
    }

    pub fn holds(&self, position: usize) -> bool {
        position % self.count == self.index
    }

    pub fn select<'a>(&self, mutations: &'a [Mutation]) -> Vec<&'a Mutation> {
        mutations
            .iter()
            .enumerate()
            .filter(|(i, _)| self.holds(*i))
            .map(|(_, m)| m)
            .collect()
    }
}

/// The lines of a test run that say what failed: each failed check
/// (`File.swift:LINE: message`), each suite marked FAILED, and how the test
/// binary ended. The run's raw tail is mostly Bazel's progress on stderr,
/// which buries these (the 2026-11-22 run showed none of them).
pub fn failure_lines(output: &str) -> Vec<String> {
    let mut lines: Vec<String> = Vec::new();
    for line in output.lines() {
        let line = line.trim_end();
        let is_check = line.contains(".swift:")
            && line
                .split(".swift:")
                .nth(1)
                .map(|rest| {
                    let digits = rest.chars().take_while(|c| c.is_ascii_digit()).count();
                    digits > 0 && rest[digits..].starts_with(": ")
                })
                .unwrap_or(false)
            && !line.contains("warning:")
            && !line.contains("error:")
            && !line.contains("note:");
        let is_suite = line.contains(": FAILED (");
        let is_end = line.contains("the test binary was killed by signal")
            || line.contains("the test binary exited with status")
            || line.contains("suites reported a result")
            || line.contains("Fatal error")
            || line.contains("uncaught exception")
            || line.starts_with("crash report:");
        if (is_check || is_suite || is_end) && !lines.iter().any(|l| l == line) {
            lines.push(line.to_string());
        }
    }
    lines
}

fn tail(text: &str, chars: usize) -> String {
    let skip = text.chars().count().saturating_sub(chars);
    text.chars().skip(skip).collect()
}

/// Whether a mutated run failed the way its mutation says it must.
pub fn detected(status: i32, output: &str, diagnostic: &str) -> bool {
    status == 3 && output.contains("TESTS FAILED") && output.contains(diagnostic)
}

pub fn run_mutation_suite(
    workspace: &Path,
    root: &Path,
    bazel_flags: &[String],
    shard: Shard,
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

    let selected = shard.select(MUTATIONS);
    if shard != Shard::ALL {
        println!(
            "Shard {}/{}: {} of {} mutations",
            shard.index,
            shard.count,
            selected.len(),
            MUTATIONS.len()
        );
    }

    println!("Checking the unmodified baseline…");
    let (status, output_text) = run(workspace, bazel_flags, &[], 3600)?;
    if status != 0 || !output_text.contains("TESTS OK") {
        return Err(format!(
            "Baseline failed:\n{}\n{}",
            failure_lines(&output_text).join("\n"),
            tail(&output_text, 12000)
        ));
    }

    // Keep going past a mutation that is not caught, so one run names every
    // weak test in its shard rather than one a week.
    let mut missed: Vec<String> = Vec::new();
    for m in &selected {
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
        if detected(status, &output_text, m.diagnostic) {
            println!("DETECTED: {}", m.name);
            continue;
        }
        let failures = failure_lines(&output_text);
        println!("NOT CAUGHT: {}", m.name);
        println!("  expected a failure containing: {}", m.diagnostic);
        println!("  bazel exit status: {}", status);
        if failures.is_empty() {
            println!("  no failed check was reported; the end of the run:");
            println!("{}", tail(&output_text, 4000));
        } else {
            println!("  what failed instead:");
            for line in &failures {
                println!("    {}", line);
            }
        }
        missed.push(m.name.to_string());
    }

    if !missed.is_empty() {
        return Err(format!(
            "{} of {} mutations were not caught by their intended assertion:\n  {}",
            missed.len(),
            selected.len(),
            missed.join("\n  ")
        ));
    }
    println!(
        "MUTATION CHECKS OK ({} regressions detected)",
        selected.len()
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
    let root = workspace.join("apps/desktop/vitruvian-atrium");
    let mut shard = Shard::ALL;
    let mut bazel_flags: Vec<String> = Vec::new();
    for arg in args {
        if let Some(value) = arg.strip_prefix("--shard=") {
            match Shard::parse(value) {
                Ok(s) => shard = s,
                Err(e) => {
                    eprintln!("{}", e);
                    return 1;
                }
            }
        } else {
            bazel_flags.push(arg.clone());
        }
    }

    match run_mutation_suite(&workspace, &root, &bazel_flags, shard) {
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
            584,
            "expected 584 mutations from the Python source"
        );
    }

    #[test]
    fn mutations_first_entry() {
        let first = &MUTATIONS[0];
        assert_eq!(first.name, "call audio protection is absent by default");
        assert_eq!(first.group, "mixer");
        assert_eq!(
            first.relative,
            "Sources/VitruvianAtrium/Core/Audio/MixerRoutingSupport.swift"
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

    #[test]
    fn shard_parse_accepts_k_of_n() {
        assert_eq!(Shard::parse("0/1"), Ok(Shard::ALL));
        assert_eq!(Shard::parse("3/4"), Ok(Shard { index: 3, count: 4 }));
    }

    #[test]
    fn shard_parse_refuses_out_of_range_and_garbage() {
        for bad in ["4/4", "0/0", "1", "a/2", "1/b", "-1/2", ""] {
            assert!(Shard::parse(bad).is_err(), "accepted {:?}", bad);
        }
    }

    #[test]
    fn shards_cover_every_mutation_exactly_once() {
        for count in [1, 2, 4, 7] {
            let mut seen = std::collections::HashMap::new();
            for index in 0..count {
                for m in (Shard { index, count }).select(MUTATIONS) {
                    *seen.entry(m.name).or_insert(0) += 1;
                }
            }
            assert_eq!(seen.len(), MUTATIONS.len(), "{} shards miss some", count);
            assert!(
                seen.values().all(|&n| n == 1),
                "{} shards repeat some",
                count
            );
        }
    }

    #[test]
    fn shards_are_even() {
        let count = 4;
        let sizes: Vec<usize> = (0..count)
            .map(|index| Shard { index, count }.select(MUTATIONS).len())
            .collect();
        assert!(sizes.iter().max().unwrap() - sizes.iter().min().unwrap() <= 1);
    }

    #[test]
    fn cli_refuses_a_bad_shard() {
        assert_eq!(run_cli(&["--shard=5/4".to_string()]), 1);
    }

    #[test]
    fn failure_lines_keep_checks_suites_and_endings() {
        let output = "\
(15:56:21) INFO: From Compiling Swift module //apps/desktop/vitruvian-atrium:VitruvianAtriumServices:
Sources/VitruvianAtrium/Services/PointerTapRunLoop.swift:51:13: warning: mutation of captured var
recording: FAILED (212 checks, 3.10s)
/private/var/tmp/Tests/RecorderWriterTests.swift:34: recorder writer fixture failed: boom
/private/var/tmp/Tests/RecorderWriterTests.swift:34: recorder writer fixture failed: boom
the test binary was killed by signal 6
TESTS FAILED: the failed checks are listed under their suites above
(15:56:34) [47 / 48] 1 / 1 tests, 1 failed;  1 action
";
        assert_eq!(
            failure_lines(output),
            vec![
                "recording: FAILED (212 checks, 3.10s)",
                "/private/var/tmp/Tests/RecorderWriterTests.swift:34: recorder writer fixture failed: boom",
                "the test binary was killed by signal 6",
            ]
        );
    }

    #[test]
    fn detected_needs_status_3_the_summary_and_the_diagnostic() {
        let out = "x.swift:1: writer dropped required microphone fixture sample\nTESTS FAILED: …";
        let diag = "writer dropped required microphone fixture sample";
        assert!(detected(3, out, diag));
        assert!(!detected(1, out, diag));
        assert!(!detected(3, "TESTS FAILED", diag));
        assert!(!detected(
            3,
            "writer dropped required microphone fixture sample",
            diag
        ));
    }

    #[test]
    fn tail_keeps_the_last_characters() {
        assert_eq!(tail("abcdef", 3), "def");
        assert_eq!(tail("ab", 3), "ab");
        assert_eq!(tail("é€ab", 3), "€ab");
    }
}
