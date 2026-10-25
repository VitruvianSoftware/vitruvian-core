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

//! //tools/secret-scan in Rust: look for secrets with the same pinned
//! gitleaks and the same rules CI uses.
//!
//! The same modes, messages and exit codes as secret-scan.sh
//! (`:secret-scan-sh`): 0 nothing found, 1 something found, 2 the scan could
//! not run. A finding names the file, line, rule and commit, never the
//! secret: gitleaks runs with --redact, its own log goes to a private
//! temporary directory rather than the screen, and of its JSON report only
//! those four fields are read (serde ignores the rest).

use serde::Deserialize;
use std::fs::File;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

/// secret-scan.sh itself: its header comment is the --help text.
const SCRIPT: &str = include_str!("../secret-scan.sh");

const ADVICE: &str = "The secret itself is not printed. What to do:
  * A real secret: take it out of the file. If it was ever pushed, rotate it too.
  * A false positive that is safe by construction: add a scoped allowlist entry
    to .gitleaks.toml that says why, or put a `gitleaks:allow` comment on that line.
  * Already committed on this branch: fix it in a new commit and fold it in with
      bazel run //tools/git:commit -- --fixup <sha> <file>
      bazel run //tools/git:sync -- --autosquash
";

/// What `usage()` in secret-scan.sh prints: the lines from `# secret-scan.sh`
/// up to (not including) `set -euo`, with the leading `# ` taken off.
pub fn usage() -> String {
    let mut out = String::new();
    let mut inside = false;
    let mut kept: Vec<&str> = Vec::new();
    for line in SCRIPT.lines() {
        if !inside && line.starts_with("# secret-scan.sh") {
            inside = true;
        }
        if inside {
            kept.push(line);
            if line.starts_with("set -euo") {
                break;
            }
        }
    }
    kept.pop();
    for line in kept {
        // sed 's/^# \{0,1\}//'
        let l = match line.strip_prefix('#') {
            Some(rest) => rest.strip_prefix(' ').unwrap_or(rest),
            None => line,
        };
        out.push_str(l);
        out.push('\n');
    }
    out
}

/// One gitleaks finding: only the fields that may be shown.
#[derive(Debug, Deserialize)]
pub struct Finding {
    #[serde(rename = "File", default)]
    pub file: String,
    #[serde(rename = "StartLine", default)]
    pub start_line: i64,
    #[serde(rename = "RuleID", default)]
    pub rule_id: String,
    #[serde(rename = "Commit", default)]
    pub commit: String,
}

/// The report's lines as secret-scan.sh prints them.
pub fn format_findings(findings: &[Finding], what: &str) -> String {
    let mut s = format!(
        "secret-scan: gitleaks found {} possible secret(s) in {what}:\n",
        findings.len()
    );
    for f in findings {
        let commit = if f.commit.is_empty() {
            String::new()
        } else {
            format!(
                "  in commit {}",
                f.commit.chars().take(12).collect::<String>()
            )
        };
        s.push_str(&format!(
            "  {}:{}  (rule: {}){commit}\n",
            f.file, f.start_line, f.rule_id
        ));
    }
    s.push_str(ADVICE);
    s
}

#[derive(Debug, PartialEq)]
pub enum Mode {
    Staged,
    Range(String),
    Unpushed,
    Branch,
}

#[derive(Debug, PartialEq)]
pub enum Parsed {
    Run(Mode),
    Help,
    Usage(String),
}

pub fn parse_args(args: &[String]) -> Parsed {
    let mut mode = Mode::Branch;
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "-h" | "--help" => return Parsed::Help,
            "--staged" => mode = Mode::Staged,
            "--unpushed" => mode = Mode::Unpushed,
            "--branch" => mode = Mode::Branch,
            "--range" => {
                if i + 1 >= args.len() {
                    return Parsed::Usage(
                        "secret-scan: --range needs a range, e.g. --range origin/main..HEAD"
                            .to_string(),
                    );
                }
                mode = Mode::Range(args[i + 1].clone());
                i += 1;
            }
            other => {
                return Parsed::Usage(format!(
                    "secret-scan: unknown argument: {other} (see --help)"
                ))
            }
        }
        i += 1;
    }
    Parsed::Run(mode)
}

/// "the scan did not run": never report that as clean.
fn cant(msg: &str) -> i32 {
    let _ = std::io::stdout().flush();
    let _ = std::io::stderr().write_all(
        format!("secret-scan: {msg}\nsecret-scan: nothing was scanned, so this is NOT a clean result.\n").as_bytes(),
    );
    2
}

fn env_nonempty(name: &str) -> Option<String> {
    std::env::var(name).ok().filter(|v| !v.is_empty())
}

/// The pinned gitleaks and the rules, from the environment or runfiles.
pub fn locate_tools() -> (String, String) {
    let rf = runfiles::Runfiles::create().ok();
    let from_runfiles = |p: &str| -> String {
        rf.as_ref()
            .and_then(|r| runfiles::rlocation!(r, p))
            .map(|p| p.to_string_lossy().into_owned())
            .unwrap_or_default()
    };
    let gitleaks = env_nonempty("GITLEAKS")
        .unwrap_or_else(|| from_runfiles("multitool/tools/gitleaks/gitleaks"));
    let config =
        env_nonempty("GITLEAKS_CONFIG").unwrap_or_else(|| from_runfiles("_main/.gitleaks.toml"));
    (gitleaks, config)
}

fn is_executable(p: &str) -> bool {
    use std::os::unix::fs::PermissionsExt;
    std::fs::metadata(p)
        .map(|m| m.permissions().mode() & 0o111 != 0)
        .unwrap_or(false)
}

fn git_out(args: &[&str], quiet: bool) -> (bool, String) {
    let o = Command::new("git")
        .args(args)
        .stdin(Stdio::null())
        .stderr(if quiet {
            Stdio::null()
        } else {
            Stdio::inherit()
        })
        .output();
    match o {
        Ok(o) => {
            let mut s = String::from_utf8_lossy(&o.stdout).into_owned();
            while s.ends_with('\n') {
                s.pop();
            }
            (o.status.success(), s)
        }
        Err(_) => (false, String::new()),
    }
}

fn git_quiet_ok(args: &[&str]) -> bool {
    Command::new("git")
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

/// A private temporary directory, removed when dropped (secret-scan.sh's
/// `trap 'rm -rf "${tmp}"' EXIT`).
struct TempDir(PathBuf);

impl TempDir {
    fn new() -> std::io::Result<Self> {
        use std::os::unix::fs::DirBuilderExt;
        let base = std::env::temp_dir();
        let pid = std::process::id();
        let nanos = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.subsec_nanos())
            .unwrap_or(0);
        for n in 0..100u32 {
            let p = base.join(format!("secret-scan.{pid}.{nanos}.{n}"));
            match std::fs::DirBuilder::new().mode(0o700).create(&p) {
                Ok(()) => return Ok(TempDir(p)),
                Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => continue,
                Err(e) => return Err(e),
            }
        }
        Err(std::io::Error::new(
            std::io::ErrorKind::AlreadyExists,
            "no free temporary name",
        ))
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

fn exit_code(status: std::process::ExitStatus) -> i32 {
    use std::os::unix::process::ExitStatusExt;
    status
        .code()
        .unwrap_or_else(|| 128 + status.signal().unwrap_or(0))
}

/// Runs the scan; returns the exit code.
pub fn run(args: &[String], gitleaks: &str, config: &str) -> i32 {
    let mode = match parse_args(args) {
        Parsed::Help => {
            let _ = std::io::stdout().write_all(usage().as_bytes());
            return 0;
        }
        Parsed::Usage(msg) => {
            eprintln!("{msg}");
            return 2;
        }
        Parsed::Run(m) => m,
    };

    if gitleaks.is_empty() || !is_executable(gitleaks) {
        return cant("cannot find the pinned gitleaks. Run it as: bazel run //tools/secret-scan");
    }
    if config.is_empty() || !Path::new(config).is_file() {
        return cant("cannot find .gitleaks.toml. Run it as: bazel run //tools/secret-scan");
    }

    // The tree to scan: the one `bazel run` was started from.
    let here = env_nonempty("BUILD_WORKSPACE_DIRECTORY")
        .unwrap_or_else(|| git_out(&["rev-parse", "--show-toplevel"], true).1);
    if here.is_empty() || !git_quiet_ok(&["-C", &here, "rev-parse", "--git-dir"]) {
        return cant("not inside a git repository");
    }
    if std::env::set_current_dir(&here).is_err() {
        return cant("not inside a git repository");
    }

    let (what, log_opts) = match &mode {
        Mode::Staged => ("the staged changes".to_string(), String::new()),
        Mode::Range(r) => (format!("the commits in {r}"), r.clone()),
        Mode::Unpushed => (
            "the commits not yet on origin".to_string(),
            "HEAD --not --remotes=origin".to_string(),
        ),
        Mode::Branch => {
            let Some(base_ref) = ["origin/main", "main"].into_iter().find(|r| {
                git_quiet_ok(&[
                    "rev-parse",
                    "--verify",
                    "--quiet",
                    &format!("{r}^{{commit}}"),
                ])
            }) else {
                return cant("there is no origin/main or main to compare with. Name a range instead: bazel run //tools/secret-scan -- --range <a..b>");
            };
            let (ok, base) = git_out(&["merge-base", base_ref, "HEAD"], false);
            if !ok {
                return cant(&format!("HEAD shares no history with {base_ref}"));
            }
            if git_out(&["rev-parse", "HEAD"], false).1 == base {
                println!(
                    "secret-scan: this branch has no commits of its own yet; nothing to scan."
                );
                return 0;
            }
            (
                format!("the commits on this branch that {base_ref} does not have"),
                format!("{base}..HEAD"),
            )
        }
    };

    let tmp = match TempDir::new() {
        Ok(t) => t,
        Err(e) => return cant(&format!("cannot make a temporary directory: {e}")),
    };
    let report = tmp.0.join("report.json");
    let log = tmp.0.join("gitleaks.log");

    let mut cmd = Command::new(gitleaks);
    cmd.args([
        "git",
        "--no-banner",
        "--no-color",
        "--redact",
        "--log-level",
        "error",
        "--exit-code",
        "99",
    ])
    .arg("--config")
    .arg(config)
    .args(["--report-format", "json", "--report-path"])
    .arg(&report);
    if mode == Mode::Staged {
        cmd.args(["--pre-commit", "--staged"]);
    } else {
        cmd.arg(format!("--log-opts={log_opts}"));
    }
    cmd.arg(".");

    // gitleaks' own output goes to a file, not the screen: even redacted,
    // its log line quotes the text around a finding.
    let rc = match File::create(&log).and_then(|f| Ok((f.try_clone()?, f))) {
        Ok((out, errf)) => match cmd.stdin(Stdio::null()).stdout(out).stderr(errf).status() {
            Ok(s) => exit_code(s),
            Err(e) => {
                let _ = std::fs::write(&log, format!("{gitleaks}: {e}\n"));
                if e.kind() == std::io::ErrorKind::NotFound {
                    127
                } else {
                    126
                }
            }
        },
        Err(e) => return cant(&format!("cannot write the gitleaks log: {e}")),
    };

    match rc {
        0 => {
            println!("secret-scan: no secrets found in {what}.");
            0
        }
        99 => {
            let mut findings: Vec<Finding> = std::fs::read(&report)
                .ok()
                .and_then(|b| serde_json::from_slice(&b).ok())
                .unwrap_or_default();
            // gitleaks reports findings in whatever order its workers finish
            // (secret-scan.sh prints them so); sorted, the output is stable.
            findings.sort_by(|a, b| {
                (&a.file, a.start_line, &a.rule_id, &a.commit).cmp(&(
                    &b.file,
                    b.start_line,
                    &b.rule_id,
                    &b.commit,
                ))
            });
            let _ = std::io::stderr().write_all(format_findings(&findings, &what).as_bytes());
            1
        }
        _ => {
            // Not a verdict: show gitleaks' own words (it failed before
            // scanning, so they hold no finding).
            let text = std::fs::read(&log).unwrap_or_default();
            let text = String::from_utf8_lossy(&text);
            let lines: Vec<&str> = text.lines().collect();
            let start = lines.len().saturating_sub(20);
            let mut s = String::new();
            for l in &lines[start..] {
                s.push_str("  gitleaks: ");
                s.push_str(l);
                s.push('\n');
            }
            let _ = std::io::stderr().write_all(s.as_bytes());
            cant(&format!("gitleaks failed to run (exit {rc})."))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn a(v: &[&str]) -> Vec<String> {
        v.iter().map(|s| s.to_string()).collect()
    }

    #[test]
    fn args() {
        assert_eq!(parse_args(&a(&[])), Parsed::Run(Mode::Branch));
        assert_eq!(parse_args(&a(&["--staged"])), Parsed::Run(Mode::Staged));
        assert_eq!(
            parse_args(&a(&["--range", "a..b"])),
            Parsed::Run(Mode::Range("a..b".into()))
        );
        assert_eq!(
            parse_args(&a(&["--staged", "--unpushed"])),
            Parsed::Run(Mode::Unpushed)
        );
        assert_eq!(
            parse_args(&a(&["--bogus", "-h"])),
            Parsed::Usage("secret-scan: unknown argument: --bogus (see --help)".into())
        );
        assert_eq!(parse_args(&a(&["-h", "--bogus"])), Parsed::Help);
        assert!(matches!(parse_args(&a(&["--range"])), Parsed::Usage(_)));
    }

    #[test]
    fn usage_is_the_script_header() {
        let u = usage();
        assert!(u.starts_with("secret-scan.sh — look for secrets"));
        assert!(u.contains(
            "Exit codes: 0 nothing found, 1 something found, 2 the scan could not run.\n"
        ));
        assert!(!u.contains("set -euo"));
    }

    #[test]
    fn report_reads_only_the_shown_fields() {
        let json = r#"[{"File":"a.txt","StartLine":2,"RuleID":"generic-api-key","Commit":"0123456789abcdef","Secret":"REDACTED","Match":"x"},
                       {"File":"b.txt","StartLine":5,"RuleID":"r","Commit":""}]"#;
        let f: Vec<Finding> = serde_json::from_str(json).unwrap();
        let s = format_findings(&f, "the staged changes");
        assert!(s.starts_with(
            "secret-scan: gitleaks found 2 possible secret(s) in the staged changes:\n"
        ));
        assert!(s.contains("  a.txt:2  (rule: generic-api-key)  in commit 0123456789ab\n"));
        assert!(s.contains("  b.txt:5  (rule: r)\n"));
        assert!(!s.contains("REDACTED"));
    }
}
