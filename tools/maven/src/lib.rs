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

//! Guards the shared Maven lock file (`maven_install.json`) against
//! placeholder-version artifacts — published jars that deliberately contain no
//! classes (such as `9999.0-empty-to-avoid-conflict-with-guava`).
//!
//! Matches `no_empty_placeholder_jars.sh` byte for byte on stdout, stderr, and
//! exit code.

use std::fs;
use std::io::Write;
use std::path::Path;

/// Substrings that only ever appear in a placeholder version string.
pub const PLACEHOLDERS: &[&str] = &["empty-to-avoid-conflict"];

/// Resolve `LOCK_FILE` via Bazel runfiles (matching `rlocation "${LOCK_FILE}"`).
pub fn resolve_lock_path(lock_file: &str) -> String {
    if lock_file.is_empty() {
        return String::new();
    }
    if lock_file.starts_with('/') {
        return lock_file.to_string();
    }
    if let Ok(rf) = runfiles::Runfiles::create() {
        if let Some(p) = runfiles::rlocation!(rf, lock_file) {
            if p.exists() {
                return p.to_string_lossy().into_owned();
            }
        }
    }
    if let Ok(rf_dir) = std::env::var("RUNFILES_DIR") {
        if !rf_dir.is_empty() {
            let candidate = Path::new(&rf_dir).join(lock_file);
            if candidate.exists() {
                return candidate.to_string_lossy().into_owned();
            }
        }
    }
    if let Ok(manifest) = std::env::var("RUNFILES_MANIFEST_FILE") {
        if !manifest.is_empty() {
            if let Ok(contents) = fs::read_to_string(&manifest) {
                let prefix = format!("{lock_file} ");
                for line in contents.lines() {
                    if let Some(target) = line.strip_prefix(&prefix) {
                        if Path::new(target).exists() {
                            return target.to_string();
                        }
                        break;
                    }
                }
            }
        }
    }
    String::new()
}

/// Find all offending lines in `content` across all configured `PLACEHOLDERS`,
/// stripping leading whitespace on each matching line just like:
/// `grep -F "${marker}" <<<"$(cat "${lock_path}")" | sed 's/^[[:space:]]*//'`
pub fn find_offenders(content: &str) -> Vec<String> {
    // Command substitution `$(cat ...)` strips trailing newlines, and `<<<`
    // appends a single newline.
    let trimmed_end = content.trim_end_matches('\n');
    if trimmed_end.is_empty() {
        return Vec::new();
    }
    let lines: Vec<&str> = trimmed_end.split('\n').collect();
    let mut offenders = Vec::new();
    for marker in PLACEHOLDERS {
        for line in &lines {
            if line.contains(marker) {
                let stripped = line.trim_start_matches(|c: char| c.is_ascii_whitespace());
                if !stripped.is_empty() {
                    offenders.push(stripped.to_string());
                }
            }
        }
    }
    offenders
}

/// Format the failure message for a single offending line.
pub fn format_offender_error(offender: &str) -> String {
    format!(
        "FAIL: {offender}\n\
         \x20     pins a placeholder version whose jar contains no classes.\n\
         \x20     Anything whose supertype lives in that jar will compile and\n\
         \x20     then fail to resolve at runtime. State the real version in\n\
         \x20     MODULE.bazel (version_conflict_policy = \"pinned\" makes a\n\
         \x20     directly-declared version win) and re-pin with:\n\
         \x20       bazel run @unpinned_maven//:pin\n"
    )
}

/// Check the lock file at `lock_path`, writing output to `stdout` and `stderr`,
/// and returning the process exit code (`0` on clean, `1` on error or finding).
pub fn check_lock_path<W1: Write, W2: Write>(
    lock_path: &str,
    stdout: &mut W1,
    stderr: &mut W2,
) -> i32 {
    if lock_path.is_empty() || !Path::new(lock_path).is_file() {
        let _ = writeln!(stderr, "ERROR: cannot read the lock file at '{lock_path}'");
        return 1;
    }
    let content = match fs::read_to_string(lock_path) {
        Ok(c) => c,
        Err(_) => {
            let _ = writeln!(stderr, "ERROR: cannot read the lock file at '{lock_path}'");
            return 1;
        }
    };
    let offenders = find_offenders(&content);
    if offenders.is_empty() {
        let _ = writeln!(
            stdout,
            "ok: no placeholder-version artifacts in the Maven lock file"
        );
        0
    } else {
        for offender in &offenders {
            let _ = stderr.write_all(format_offender_error(offender).as_bytes());
        }
        1
    }
}

/// Entrypoint using the `LOCK_FILE` environment variable and standard streams.
pub fn run() -> i32 {
    let lock_file = std::env::var("LOCK_FILE").unwrap_or_default();
    let lock_path = resolve_lock_path(&lock_file);
    let mut stdout = std::io::stdout().lock();
    let mut stderr = std::io::stderr().lock();
    check_lock_path(&lock_path, &mut stdout, &mut stderr)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn clean_lockfile_passes() {
        let content = r#"{
  "artifacts": {
    "com.google.guava:listenablefuture": {
      "version": "1.0"
    }
  }
}
"#;
        assert!(find_offenders(content).is_empty());
    }

    #[test]
    fn placeholder_version_detected_and_trimmed() {
        let content = r#"{
  "artifacts": {
    "com.google.guava:listenablefuture": {
      "version": "9999.0-empty-to-avoid-conflict-with-guava"
    }
  }
}
"#;
        let offenders = find_offenders(content);
        assert_eq!(
            offenders,
            vec![r#""version": "9999.0-empty-to-avoid-conflict-with-guava""#]
        );
    }

    #[test]
    fn check_lock_path_missing_file_errors() {
        let mut out = Vec::new();
        let mut err = Vec::new();
        let rc = check_lock_path("/nonexistent/maven_install.json", &mut out, &mut err);
        assert_eq!(rc, 1);
        assert!(out.is_empty());
        assert_eq!(
            String::from_utf8(err).unwrap(),
            "ERROR: cannot read the lock file at '/nonexistent/maven_install.json'\n"
        );
    }

    #[test]
    fn check_lock_path_clean_and_offending_files() {
        let dir = std::env::temp_dir().join(format!("maven_test_{}", std::process::id()));
        let _ = fs::create_dir_all(&dir);
        let clean_path = dir.join("clean.json");
        let bad_path = dir.join("bad.json");

        fs::write(&clean_path, "{\n  \"version\": \"1.0\"\n}\n").unwrap();
        fs::write(
            &bad_path,
            "{\n    \"version\": \"9999.0-empty-to-avoid-conflict-with-guava\"\n}\n",
        )
        .unwrap();

        let mut out = Vec::new();
        let mut err = Vec::new();
        let rc = check_lock_path(clean_path.to_str().unwrap(), &mut out, &mut err);
        assert_eq!(rc, 0);
        assert_eq!(
            String::from_utf8(out).unwrap(),
            "ok: no placeholder-version artifacts in the Maven lock file\n"
        );
        assert!(err.is_empty());

        let mut out2 = Vec::new();
        let mut err2 = Vec::new();
        let rc2 = check_lock_path(bad_path.to_str().unwrap(), &mut out2, &mut err2);
        assert_eq!(rc2, 1);
        assert!(out2.is_empty());
        let err_str = String::from_utf8(err2).unwrap();
        assert!(err_str
            .starts_with("FAIL: \"version\": \"9999.0-empty-to-avoid-conflict-with-guava\"\n"));
        assert!(err_str.contains("bazel run @unpinned_maven//:pin"));

        let _ = fs::remove_dir_all(&dir);
    }
}
