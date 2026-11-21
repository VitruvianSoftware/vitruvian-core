// Copyright (c) 2026 VitruvianSoftware
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

//! Generates and verifies the `detect-macos` path filter in `.github/workflows/ci.yaml`
//! from the Bazel dependency graph of `macos-build`'s targets.

use std::collections::BTreeSet;
use std::fs;
use std::io::Write;
use std::process::Command;

pub const DEFAULT_WORKFLOW: &str = ".github/workflows/ci.yaml";
pub const BEGIN_MARKER: &str = "# BEGIN generated: macos-paths";
pub const END_MARKER: &str = "# END generated: macos-paths";
pub const FIX_COMMAND: &str =
    "bazel build //tools/ci:macos_paths && bazel-bin/tools/ci/macos_paths --write";

pub const FIXED_ENTRIES: &[&str] = &[
    ".xcode-version",
    ".github/actions/select-xcode/**",
    ".bazelrc",
    ".bazelversion",
    "MODULE.bazel",
    "MODULE.bazel.lock",
    ".github/workflows/ci.yaml",
];

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Mode {
    Print,
    Write,
    Check,
}

fn is_top_level_job_header(line: &str) -> bool {
    let Some(rest) = line.strip_prefix("  ") else {
        return false;
    };
    if rest.is_empty() || rest.starts_with(' ') || rest.starts_with('#') {
        return false;
    }
    let trimmed = rest.trim_end();
    trimmed.ends_with(':') && !trimmed.contains(' ')
}

fn strip_inline_comment(line: &str) -> &str {
    let bytes = line.as_bytes();
    let mut in_single = false;
    let mut in_double = false;
    for i in 0..bytes.len() {
        match bytes[i] {
            b'\'' if !in_double => in_single = !in_single,
            b'"' if !in_single => in_double = !in_double,
            b'#' if !in_single && !in_double && (i == 0 || bytes[i - 1].is_ascii_whitespace()) => {
                return &line[..i];
            }
            _ => {}
        }
    }
    line
}

/// Parses Bazel targets from `bazel build`, `bazel test`, and `bazel run` lines
/// inside the `macos-build:` job of `ci.yaml`.
pub fn parse_macos_build_targets(ci_yaml: &str) -> Result<Vec<String>, String> {
    let lines: Vec<&str> = ci_yaml.lines().collect();
    let start = lines
        .iter()
        .position(|l| l.trim_end() == "  macos-build:")
        .ok_or_else(|| "could not find `macos-build:` job in workflow".to_string())?;

    let mut section = Vec::new();
    for &line in &lines[start + 1..] {
        if is_top_level_job_header(line) {
            break;
        }
        let trimmed = line.trim();
        if !trimmed.is_empty() && !trimmed.starts_with('#') && !line.starts_with(' ') {
            break;
        }
        section.push(line);
    }

    let mut logical = Vec::new();
    let mut buf = String::new();
    for raw in section {
        let line = raw.trim_end_matches('\r');
        if buf.is_empty() && line.trim_start().starts_with('#') {
            continue;
        }
        if let Some(prefix) = line.trim_end().strip_suffix('\\') {
            buf.push_str(prefix);
            buf.push(' ');
            continue;
        }
        buf.push_str(line);
        logical.push(std::mem::take(&mut buf));
    }
    if !buf.is_empty() {
        logical.push(buf);
    }

    let mut targets = Vec::new();
    for line in logical {
        let code = strip_inline_comment(&line).trim();
        if code.is_empty() || code.starts_with('#') {
            continue;
        }
        let code = code.strip_prefix("- ").unwrap_or(code).trim_start();
        let code = code.strip_prefix("run:").unwrap_or(code).trim_start();
        let mut tokens = code.split_whitespace();
        let Some(cmd) = tokens.next() else {
            continue;
        };
        if cmd != "bazel" && cmd != "bazelisk" {
            continue;
        }
        let verb = tokens.find(|t| !t.starts_with('-'));
        if !matches!(verb, Some("build" | "test" | "run")) {
            continue;
        }
        for tok in tokens {
            if tok == "--" {
                break;
            }
            let clean = tok.trim_matches(|c| c == '\'' || c == '"');
            if clean.starts_with("//") && !targets.iter().any(|existing| existing == clean) {
                targets.push(clean.to_string());
            }
        }
    }

    if targets.is_empty() {
        return Err("found no Bazel targets in `macos-build:` job".to_string());
    }
    Ok(targets)
}

/// Collapses a main-repo Bazel package into a `dorny/paths-filter` glob.
/// Each package maps to its own path (`<package>/**`), never to its app or
/// package root: a package's `/**` already covers its own files and its
/// non-package subdirectories, and a sibling package under the same app must
/// not start a Mac build (the Android remote is `apps/mobile/vitruvian-remote`,
/// its Mac app is `.../macmenu`). `tools/**` stays whole: it is the fixed
/// toolchain surface. Returns `None` for empty strings and external repo
/// labels (`@repo//...`).
pub fn collapse_package(pkg: &str) -> Option<String> {
    let trimmed = pkg.trim();
    if trimmed.is_empty() || trimmed.starts_with('@') {
        return None;
    }
    let clean = trimmed.strip_prefix("//").unwrap_or(trimmed);
    if clean.is_empty() {
        return None;
    }
    let segs: Vec<&str> = clean.split('/').collect();
    let glob = match segs.first() {
        Some(&"tools") => "tools/**".to_string(),
        _ => format!("{clean}/**"),
    };
    Some(glob)
}

/// True when `narrow` is a `<dir>/**` glob strictly inside another `<dir>/**`
/// glob (for example `packages/swift/SentryLite/**` inside `packages/swift/**`).
fn is_covered_by(narrow: &str, broad: &str) -> bool {
    match (narrow.strip_suffix("/**"), broad.strip_suffix("/**")) {
        (Some(n), Some(b)) => n != b && n.starts_with(&format!("{b}/")),
        _ => false,
    }
}

/// Builds the sorted, deduplicated list of globs from queried packages and `FIXED_ENTRIES`.
pub fn build_globs<I, S>(packages: I) -> Vec<String>
where
    I: IntoIterator<Item = S>,
    S: AsRef<str>,
{
    let mut set = BTreeSet::new();
    for entry in FIXED_ENTRIES {
        set.insert((*entry).to_string());
    }
    for pkg in packages {
        if let Some(glob) = collapse_package(pkg.as_ref()) {
            set.insert(glob);
        }
    }
    // Drop any glob a broader glob in the list already covers.
    let all: Vec<String> = set.iter().cloned().collect();
    set.into_iter()
        .filter(|g| !all.iter().any(|other| is_covered_by(g, other)))
        .collect()
}

/// Runs `bazel query 'deps(set(<targets>))' --output package` and returns stdout lines.
pub fn query_packages(bazel: &str, targets: &[String]) -> Result<Vec<String>, String> {
    if targets.is_empty() {
        return Err("cannot query an empty target list".to_string());
    }
    let expr = format!("deps(set({}))", targets.join(" "));
    let output = Command::new(bazel)
        .args(["query", "--noshow_progress", "--output=package", &expr])
        .output()
        .map_err(|e| format!("failed to run `{bazel} query`: {e}"))?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!(
            "`{bazel} query` exited with {}: {}",
            output
                .status
                .code()
                .map_or_else(|| "signal".to_string(), |c| c.to_string()),
            stderr.trim()
        ));
    }
    let stdout = String::from_utf8_lossy(&output.stdout);
    Ok(stdout.lines().map(|l| l.trim().to_string()).collect())
}

fn find_marker_bounds(lines: &[&str]) -> Result<(usize, usize), String> {
    let begins: Vec<usize> = lines
        .iter()
        .enumerate()
        .filter(|(_, l)| l.trim() == BEGIN_MARKER)
        .map(|(i, _)| i)
        .collect();
    let ends: Vec<usize> = lines
        .iter()
        .enumerate()
        .filter(|(_, l)| l.trim() == END_MARKER)
        .map(|(i, _)| i)
        .collect();

    if begins.len() != 1 || ends.len() != 1 {
        return Err(format!(
            "expected exactly one `{BEGIN_MARKER}` and one `{END_MARKER}` (found {} begin, {} end)",
            begins.len(),
            ends.len()
        ));
    }
    let begin = begins[0];
    let end = ends[0];
    if begin >= end {
        return Err(format!(
            "`{BEGIN_MARKER}` (line {}) must appear before `{END_MARKER}` (line {})",
            begin + 1,
            end + 1
        ));
    }
    Ok((begin, end))
}

/// Extracts the YAML list entries between `BEGIN_MARKER` and `END_MARKER`.
pub fn extract_marker_entries(content: &str) -> Result<Vec<String>, String> {
    let lines: Vec<&str> = content.lines().collect();
    let (begin, end) = find_marker_bounds(&lines)?;
    let mut entries = Vec::new();
    for &line in &lines[begin + 1..end] {
        let t = line.trim();
        if t.is_empty() || t.starts_with('#') {
            continue;
        }
        let item = t.strip_prefix("- ").unwrap_or(t).trim();
        let clean = item.trim_matches(|c| c == '\'' || c == '"');
        if !clean.is_empty() {
            entries.push(clean.to_string());
        }
    }
    Ok(entries)
}

/// Rewrites only the lines between `BEGIN_MARKER` and `END_MARKER`, preserving indentation.
pub fn rewrite_marker_block(content: &str, globs: &[String]) -> Result<String, String> {
    let lines: Vec<&str> = content.lines().collect();
    let (begin, end) = find_marker_bounds(&lines)?;
    let begin_line = lines[begin];
    let indent_len = begin_line.len() - begin_line.trim_start().len();
    let indent = &begin_line[..indent_len];

    let mut out: Vec<String> = Vec::with_capacity(lines.len() + globs.len());
    for &l in &lines[..=begin] {
        out.push(l.to_string());
    }
    for g in globs {
        out.push(format!("{indent}- '{g}'"));
    }
    for &l in &lines[end..] {
        out.push(l.to_string());
    }
    let mut joined = out.join("\n");
    if content.ends_with('\n') {
        joined.push('\n');
    }
    Ok(joined)
}

fn usage() -> &'static str {
    "Usage: macos_paths [--write | --check] [--workflow <path>] [--bazel <bin>]\n"
}

pub fn run_with_query<F>(
    args: &[String],
    out: &mut dyn Write,
    err: &mut dyn Write,
    query_fn: F,
) -> i32
where
    F: FnOnce(&str, &[String]) -> Result<Vec<String>, String>,
{
    let mut mode = Mode::Print;
    let mut workflow = DEFAULT_WORKFLOW.to_string();
    let mut bazel = "bazel".to_string();

    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--write" => {
                if mode == Mode::Check {
                    let _ = writeln!(err, "macos_paths: cannot pass both --write and --check");
                    return 2;
                }
                mode = Mode::Write;
            }
            "--check" => {
                if mode == Mode::Write {
                    let _ = writeln!(err, "macos_paths: cannot pass both --write and --check");
                    return 2;
                }
                mode = Mode::Check;
            }
            "--workflow" => {
                i += 1;
                if i >= args.len() {
                    let _ = writeln!(err, "macos_paths: --workflow requires a path");
                    return 2;
                }
                workflow = args[i].clone();
            }
            "--bazel" => {
                i += 1;
                if i >= args.len() {
                    let _ = writeln!(err, "macos_paths: --bazel requires a binary");
                    return 2;
                }
                bazel = args[i].clone();
            }
            "-h" | "--help" => {
                let _ = write!(out, "{}", usage());
                return 0;
            }
            other => {
                let _ = writeln!(err, "macos_paths: unknown argument `{other}`");
                let _ = write!(err, "{}", usage());
                return 2;
            }
        }
        i += 1;
    }

    let content = match fs::read_to_string(&workflow) {
        Ok(c) => c,
        Err(e) => {
            let _ = writeln!(err, "macos_paths: failed to read `{workflow}`: {e}");
            return 1;
        }
    };

    let targets = match parse_macos_build_targets(&content) {
        Ok(t) => t,
        Err(e) => {
            let _ = writeln!(err, "macos_paths: {e}");
            return 1;
        }
    };

    let packages = match query_fn(&bazel, &targets) {
        Ok(p) => p,
        Err(e) => {
            let _ = writeln!(err, "macos_paths: {e}");
            return 1;
        }
    };

    let globs = build_globs(packages);

    match mode {
        Mode::Print => {
            for g in &globs {
                let _ = writeln!(out, "- '{g}'");
            }
            0
        }
        Mode::Write => {
            let updated = match rewrite_marker_block(&content, &globs) {
                Ok(u) => u,
                Err(e) => {
                    let _ = writeln!(err, "macos_paths: {e}");
                    return 1;
                }
            };
            if let Err(e) = fs::write(&workflow, updated) {
                let _ = writeln!(err, "macos_paths: failed to write `{workflow}`: {e}");
                return 1;
            }
            let _ = writeln!(
                out,
                "macos_paths: updated `{workflow}` ({} entries)",
                globs.len()
            );
            0
        }
        Mode::Check => {
            let expected = match rewrite_marker_block(&content, &globs) {
                Ok(u) => u,
                Err(e) => {
                    let _ = writeln!(err, "macos_paths: {e}");
                    return 1;
                }
            };
            if content == expected {
                let _ = writeln!(
                    out,
                    "macos_paths: `{workflow}` is up to date ({} entries)",
                    globs.len()
                );
                return 0;
            }

            let _ = writeln!(
                err,
                "macos_paths: `{workflow}` detect-macos filter drifted from the Bazel graph."
            );
            if let Ok(actual) = extract_marker_entries(&content) {
                let actual_set: BTreeSet<&str> = actual.iter().map(String::as_str).collect();
                let expected_set: BTreeSet<&str> = globs.iter().map(String::as_str).collect();
                for missing in expected_set.difference(&actual_set) {
                    let _ = writeln!(err, "  missing: {missing}");
                }
                for extra in actual_set.difference(&expected_set) {
                    let _ = writeln!(err, "  extra:   {extra}");
                }
            }
            let _ = writeln!(err, "Fix by running:\n  {FIX_COMMAND}");
            1
        }
    }
}

pub fn run(args: &[String]) -> i32 {
    let mut stdout = std::io::stdout().lock();
    let mut stderr = std::io::stderr().lock();
    if std::env::var_os("BUILD_WORKSPACE_DIRECTORY").is_some() {
        let _ = writeln!(
            stderr,
            "macos_paths: do not invoke via `bazel run` because it runs `bazel query` itself. Run:\n  {FIX_COMMAND}"
        );
        return 2;
    }
    run_with_query(args, &mut stdout, &mut stderr, query_packages)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;
    use std::sync::atomic::{AtomicUsize, Ordering};

    struct TempFile {
        dir: PathBuf,
        path: PathBuf,
    }

    impl TempFile {
        fn new(name: &str, contents: &str) -> Self {
            static COUNTER: AtomicUsize = AtomicUsize::new(0);
            let base = std::env::var_os("TEST_TMPDIR")
                .map(PathBuf::from)
                .unwrap_or_else(std::env::temp_dir);
            let dir = base.join(format!(
                "macos-paths-test-{}-{}",
                std::process::id(),
                COUNTER.fetch_add(1, Ordering::SeqCst)
            ));
            fs::create_dir_all(&dir).unwrap();
            let path = dir.join(name);
            fs::write(&path, contents).unwrap();
            Self { dir, path }
        }
    }

    impl Drop for TempFile {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.dir);
        }
    }

    const SAMPLE_CI: &str = "\
name: CI
jobs:
  detect-macos:
    steps:
      - uses: dorny/paths-filter@abc
        with:
          filters: |
            macos:
              # Explanatory comment kept outside markers.
              # BEGIN generated: macos-paths
              - 'stale/entry/**'
              # END generated: macos-paths

  macos-build:
    needs: [queued, fast-lane, detect-macos]
    runs-on: xcode-27
    steps:
      - name: Build macOS app
        run: |
          cache=()
          bazel build \"${cache[@]}\" --config=macos-app //apps/desktop/vitruvian-code/... //apps/desktop/vitruvian-code/macos:VitruvianCode
          bazel test \"${cache[@]}\" --config=macos-app //apps/desktop/vitruvian-code/macos:VitruvianCodeTests
          bazel test \"${cache[@]}\" --config=macos-app --test_env=REQUIRE_BASH32=1 //tools/desktop-package:package-desktop_test
          bazel run \"${cache[@]}\" //apps/desktop/vitruvian-speaker:publish -- --dry-run
          bazel build \"${cache[@]}\" --config=macos-app \\
            //apps/mobile/vitruvian-remote/macmenu:VitruvianRemote \\
            //apps/desktop/vitruvian-atrium:VitruvianAtrium # trailing comment

  build-macos:
    needs: [macos-build]
    steps:
      - run: bazel build //should/not/be/parsed:target
";

    #[test]
    fn collapses_packages_and_drops_external_repos() {
        assert_eq!(
            collapse_package("apps/desktop/vitruvian-code/macos").as_deref(),
            Some("apps/desktop/vitruvian-code/macos/**")
        );
        assert_eq!(
            collapse_package("apps/mobile/vitruvian-remote/macmenu").as_deref(),
            Some("apps/mobile/vitruvian-remote/macmenu/**")
        );
        assert_eq!(
            collapse_package("packages/swift/SentryLite").as_deref(),
            Some("packages/swift/SentryLite/**")
        );
        assert_eq!(
            collapse_package("packages/vitruvian-sdk/consumers").as_deref(),
            Some("packages/vitruvian-sdk/consumers/**")
        );
        assert_eq!(
            collapse_package("packages/peripherals").as_deref(),
            Some("packages/peripherals/**")
        );
        assert_eq!(collapse_package("tools/apple").as_deref(), Some("tools/**"));
        assert_eq!(
            collapse_package("tools/swift-test-preferences").as_deref(),
            Some("tools/**")
        );
        assert_eq!(collapse_package("@rules_swift//swift"), None);
        assert_eq!(collapse_package("@@apple_support+//xcode"), None);
        assert_eq!(collapse_package(""), None);
    }

    #[test]
    fn package_under_an_app_never_widens_to_the_app_root() {
        // The Android remote shares an app root with its Mac app. A change to
        // the Android-only side must not match the Mac filter.
        let globs = build_globs(["apps/mobile/vitruvian-remote/macmenu"]);
        assert!(globs.contains(&"apps/mobile/vitruvian-remote/macmenu/**".to_string()));
        assert!(
            !globs.contains(&"apps/mobile/vitruvian-remote/**".to_string()),
            "app root must not appear: {globs:?}"
        );
        let android_only = "apps/mobile/vitruvian-remote/android/app/build.gradle";
        assert!(!globs.iter().any(|g| g
            .strip_suffix("/**")
            .is_some_and(|d| android_only.starts_with(&format!("{d}/")))));
    }

    #[test]
    fn build_globs_drops_packages_covered_by_a_broader_glob() {
        let globs = build_globs(["packages/swift", "packages/swift/SentryLite"]);
        assert!(globs.contains(&"packages/swift/**".to_string()));
        assert!(!globs.contains(&"packages/swift/SentryLite/**".to_string()));

        let narrow = build_globs(["packages/swift/SentryLite"]);
        assert!(narrow.contains(&"packages/swift/SentryLite/**".to_string()));
        assert!(!narrow.contains(&"packages/swift/**".to_string()));
    }

    #[test]
    fn build_globs_includes_fixed_entries_sorted_and_deduped() {
        let globs = build_globs::<_, &str>([]);
        for fixed in FIXED_ENTRIES {
            assert!(
                globs.iter().any(|g| g == fixed),
                "missing fixed entry {fixed}: {globs:?}"
            );
        }
        let mut sorted = globs.clone();
        sorted.sort();
        sorted.dedup();
        assert_eq!(globs, sorted);

        let with_pkgs = build_globs([
            "@apple_support//lib",
            "apps/desktop/vitruvian-code/macos",
            "apps/desktop/vitruvian-code/src",
            "packages/swift/SentryLite",
            "tools/apple",
            "tools/doctor",
        ]);
        assert_eq!(
            with_pkgs.iter().filter(|g| *g == "tools/**").count(),
            1,
            "tools/** should be deduped"
        );
        assert_eq!(
            with_pkgs
                .iter()
                .filter(|g| *g == "apps/desktop/vitruvian-code/macos/**")
                .count(),
            1
        );
        assert!(with_pkgs.contains(&"packages/swift/SentryLite/**".to_string()));
    }

    #[test]
    fn parses_targets_only_from_macos_build_and_stops_at_double_dash() {
        let targets = parse_macos_build_targets(SAMPLE_CI).unwrap();
        assert_eq!(
            targets,
            vec![
                "//apps/desktop/vitruvian-code/...",
                "//apps/desktop/vitruvian-code/macos:VitruvianCode",
                "//apps/desktop/vitruvian-code/macos:VitruvianCodeTests",
                "//tools/desktop-package:package-desktop_test",
                "//apps/desktop/vitruvian-speaker:publish",
                "//apps/mobile/vitruvian-remote/macmenu:VitruvianRemote",
                "//apps/desktop/vitruvian-atrium:VitruvianAtrium",
            ]
        );

        let with_run_arg = "\
jobs:
  macos-build:
    steps:
      - run: bazel run //apps/desktop/vitruvian-speaker:publish -- //not/a/target:x
  build-macos:
    steps: []
";
        assert_eq!(
            parse_macos_build_targets(with_run_arg).unwrap(),
            vec!["//apps/desktop/vitruvian-speaker:publish"]
        );
    }

    #[test]
    fn rewrite_marker_block_is_idempotent_and_preserves_surrounding_comments() {
        let globs = build_globs(["packages/swift/SentryLite", "tools/apple"]);
        let once = rewrite_marker_block(SAMPLE_CI, &globs).unwrap();
        assert!(once.contains("# Explanatory comment kept outside markers."));
        assert!(!once.contains("stale/entry/**"));
        assert!(once.contains("\n              - 'packages/swift/SentryLite/**'\n"));
        assert!(once.contains("\n              - 'tools/**'\n"));

        let twice = rewrite_marker_block(&once, &globs).unwrap();
        assert_eq!(once, twice);

        assert!(rewrite_marker_block("no markers here", &globs).is_err());
    }

    #[test]
    fn write_then_check_passes_and_drift_fails_with_fix_command() {
        let tf = TempFile::new("ci.yaml", SAMPLE_CI);
        let wf = tf.path.to_string_lossy().into_owned();
        let fake_pkgs = || {
            Ok(vec![
                "@platforms//os".to_string(),
                "apps/desktop/vitruvian-atrium".to_string(),
                "packages/swift/SentryLite".to_string(),
                "packages/vitruvian-sdk".to_string(),
                "tools/apple".to_string(),
            ])
        };

        // Initial check fails because committed block has stale/entry/**.
        let mut out = Vec::new();
        let mut err = Vec::new();
        let code = run_with_query(
            &["--check".into(), "--workflow".into(), wf.clone()],
            &mut out,
            &mut err,
            |_, _| fake_pkgs(),
        );
        assert_eq!(code, 1);
        let err_s = String::from_utf8_lossy(&err);
        assert!(err_s.contains(FIX_COMMAND), "missing fix command: {err_s}");

        // --write updates the file.
        out.clear();
        err.clear();
        let code = run_with_query(
            &["--write".into(), "--workflow".into(), wf.clone()],
            &mut out,
            &mut err,
            |_, _| fake_pkgs(),
        );
        assert_eq!(code, 0, "stderr: {}", String::from_utf8_lossy(&err));
        let written = fs::read_to_string(&tf.path).unwrap();

        // --write a second time leaves bytes unchanged.
        out.clear();
        err.clear();
        let code = run_with_query(
            &["--write".into(), "--workflow".into(), wf.clone()],
            &mut out,
            &mut err,
            |_, _| fake_pkgs(),
        );
        assert_eq!(code, 0);
        assert_eq!(written, fs::read_to_string(&tf.path).unwrap());

        // --check now passes.
        out.clear();
        err.clear();
        let code = run_with_query(
            &["--check".into(), "--workflow".into(), wf.clone()],
            &mut out,
            &mut err,
            |_, _| fake_pkgs(),
        );
        assert_eq!(code, 0, "stderr: {}", String::from_utf8_lossy(&err));

        // Removing a generated line causes --check to fail and print FIX_COMMAND.
        let drifted = written.replace("              - 'packages/swift/SentryLite/**'\n", "");
        assert_ne!(drifted, written);
        fs::write(&tf.path, drifted).unwrap();

        out.clear();
        err.clear();
        let code = run_with_query(
            &["--check".into(), "--workflow".into(), wf],
            &mut out,
            &mut err,
            |_, _| fake_pkgs(),
        );
        assert_eq!(code, 1);
        let err_s = String::from_utf8_lossy(&err);
        assert!(
            err_s.contains("missing: packages/swift/SentryLite/**"),
            "{err_s}"
        );
        assert!(err_s.contains(FIX_COMMAND), "missing fix command: {err_s}");
    }
}
