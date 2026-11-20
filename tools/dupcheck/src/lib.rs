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

//! `//tools/dupcheck`: detect duplicated shared-package code from git objects.

pub mod diff_mode;
pub mod families_mode;
pub mod git;
pub mod glob;
pub mod normalize;

use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

#[derive(Debug, Clone, PartialEq, Eq)]
enum Mode {
    Diff {
        base: String,
        head: String,
        strict: bool,
        allow: Vec<String>,
    },
    Families {
        git_ref: String,
    },
    Help,
}

fn usage() -> &'static str {
    "\
usage:
  dupcheck --diff <base>...<head> [--strict] [--allow <path-glob>]...
  dupcheck --families [--ref <commit>]
"
}

fn next_arg(args: &[String], idx: &mut usize, flag: &str) -> Result<String, String> {
    *idx += 1;
    args.get(*idx)
        .cloned()
        .ok_or_else(|| format!("missing value for {flag}"))
}

fn parse_args(args: &[String]) -> Result<Mode, String> {
    let mut diff_spec: Option<String> = None;
    let mut strict = false;
    let mut allow = Vec::new();
    let mut families = false;
    let mut git_ref: Option<String> = None;

    let mut i = 0;
    while i < args.len() {
        let arg = &args[i];
        if arg == "-h" || arg == "--help" {
            return Ok(Mode::Help);
        } else if arg == "--diff" {
            diff_spec = Some(next_arg(args, &mut i, "--diff")?);
        } else if let Some(val) = arg.strip_prefix("--diff=") {
            diff_spec = Some(val.to_string());
        } else if arg == "--strict" {
            strict = true;
        } else if arg == "--allow" {
            allow.push(next_arg(args, &mut i, "--allow")?);
        } else if let Some(val) = arg.strip_prefix("--allow=") {
            allow.push(val.to_string());
        } else if arg == "--families" {
            families = true;
        } else if arg == "--ref" {
            git_ref = Some(next_arg(args, &mut i, "--ref")?);
        } else if let Some(val) = arg.strip_prefix("--ref=") {
            git_ref = Some(val.to_string());
        } else {
            return Err(format!("unknown argument: {arg}"));
        }
        i += 1;
    }

    match (diff_spec, families) {
        (Some(_), true) => Err("choose either --diff or --families, not both".to_string()),
        (None, false) => {
            Err("missing mode: specify --diff <base>...<head> or --families".to_string())
        }
        (Some(spec), false) => {
            if git_ref.is_some() {
                return Err("--ref is only valid with --families".to_string());
            }
            let Some((base, head)) = spec.split_once("...") else {
                return Err(format!("--diff expects <base>...<head>, got '{spec}'"));
            };
            if base.is_empty() || head.is_empty() {
                return Err(format!("--diff expects <base>...<head>, got '{spec}'"));
            }
            Ok(Mode::Diff {
                base: base.to_string(),
                head: head.to_string(),
                strict,
                allow,
            })
        }
        (None, true) => {
            if strict || !allow.is_empty() {
                return Err("--strict and --allow are only valid with --diff".to_string());
            }
            Ok(Mode::Families {
                git_ref: git_ref.unwrap_or_else(|| "origin/main".to_string()),
            })
        }
    }
}

pub fn workspace_root() -> Result<PathBuf, String> {
    if let Ok(dir) = std::env::var("BUILD_WORKSPACE_DIRECTORY") {
        if !dir.is_empty() {
            return Ok(PathBuf::from(dir));
        }
    }
    let out = Command::new("git")
        .args(["rev-parse", "--show-toplevel"])
        .stdin(Stdio::null())
        .output()
        .map_err(|e| format!("failed to locate workspace root via git: {e}"))?;
    if out.status.success() {
        let top = String::from_utf8_lossy(&out.stdout)
            .trim_end_matches(['\r', '\n'])
            .to_string();
        if !top.is_empty() {
            return Ok(PathBuf::from(top));
        }
    }
    Ok(PathBuf::from("."))
}

pub fn run(repo_root: &Path, args: &[String], out: &mut dyn Write, err: &mut dyn Write) -> i32 {
    let mode = match parse_args(args) {
        Ok(m) => m,
        Err(msg) => {
            let _ = writeln!(err, "dupcheck: {msg}");
            let _ = write!(err, "{}", usage());
            return 2;
        }
    };

    match mode {
        Mode::Help => {
            let _ = write!(out, "{}", usage());
            0
        }
        Mode::Diff {
            base,
            head,
            strict,
            allow,
        } => match diff_mode::run_diff(repo_root, &base, &head, &allow) {
            Ok(findings) => {
                for finding in &findings {
                    let _ = writeln!(out, "{}", finding.format_line());
                }
                if strict && !findings.is_empty() {
                    1
                } else {
                    0
                }
            }
            Err(msg) => {
                let _ = writeln!(err, "dupcheck: {msg}");
                2
            }
        },
        Mode::Families { git_ref } => match families_mode::run_families(repo_root, &git_ref) {
            Ok(rows) => {
                let _ = write!(out, "{}", families_mode::format_table(&rows));
                0
            }
            Err(msg) => {
                let _ = writeln!(err, "dupcheck: {msg}");
                2
            }
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU64, Ordering};

    struct TempRepo {
        path: PathBuf,
    }

    impl TempRepo {
        fn new(label: &str) -> Self {
            static SEQ: AtomicU64 = AtomicU64::new(0);
            let id = SEQ.fetch_add(1, Ordering::Relaxed);
            let path = std::env::temp_dir()
                .join(format!("dupcheck-e2e-{label}-{}-{id}", std::process::id()));
            let _ = std::fs::remove_dir_all(&path);
            std::fs::create_dir_all(&path).unwrap();
            let repo = Self { path };
            repo.git(&["init", "-q", "-b", "main"]);
            repo
        }

        fn git(&self, args: &[&str]) -> String {
            let out = Command::new("git")
                .current_dir(&self.path)
                .args(args)
                .stdin(Stdio::null())
                .output()
                .expect("spawn git");
            assert!(
                out.status.success(),
                "git {:?} failed:\nstdout: {}\nstderr: {}",
                args,
                String::from_utf8_lossy(&out.stdout),
                String::from_utf8_lossy(&out.stderr)
            );
            String::from_utf8_lossy(&out.stdout).trim().to_string()
        }

        fn write(&self, rel: &str, content: &str) {
            let full = self.path.join(rel);
            if let Some(parent) = full.parent() {
                std::fs::create_dir_all(parent).unwrap();
            }
            std::fs::write(full, content).unwrap();
        }

        fn commit_all(&self, msg: &str) -> String {
            self.git(&["add", "-A"]);
            self.git(&[
                "-c",
                "user.name=test",
                "-c",
                "user.email=test@example.com",
                "-c",
                "commit.gpgsign=false",
                "commit",
                "-q",
                "-m",
                msg,
            ]);
            self.git(&["rev-parse", "HEAD"])
        }

        fn run_cli(&self, args: &[&str]) -> (i32, String, String) {
            let argv: Vec<String> = args.iter().map(|s| (*s).to_string()).collect();
            let mut out = Vec::new();
            let mut err = Vec::new();
            let code = run(&self.path, &argv, &mut out, &mut err);
            (
                code,
                String::from_utf8_lossy(&out).into_owned(),
                String::from_utf8_lossy(&err).into_owned(),
            )
        }
    }

    impl Drop for TempRepo {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.path);
        }
    }

    fn helper_lines(count: usize) -> String {
        (1..=count)
            .map(|i| format!("    let shared_value_{i} = compute_step({i}, {i} + 1);"))
            .collect::<Vec<_>>()
            .join("\n")
            + "\n"
    }

    #[test]
    fn e2e_diff_15_lines_found_and_11_lines_ignored() {
        let repo = TempRepo::new("diff15");
        repo.write(
            "packages/mylib/catalog-info.yaml",
            "apiVersion: backstage.io/v1alpha1\nkind: Component\nmetadata:\n  name: mylib\n  annotations:\n    vitruvian.dev/bazel-target: //packages/mylib:mylib\nspec:\n  type: library\n",
        );
        repo.write(
            "packages/mylib/src/helper.rs",
            &format!("// shared helper\n{}", helper_lines(20)),
        );
        let base = repo.commit_all("add package");

        repo.write(
            "apps/demo/src/copy15.rs",
            &format!("// copied 15 lines\n{}", helper_lines(15)),
        );
        repo.write(
            "apps/demo/src/copy11.rs",
            &format!("// copied 11 lines\n{}", helper_lines(11)),
        );
        let head = repo.commit_all("add copies");

        let range = format!("{base}...{head}");
        let (code, stdout, stderr) = repo.run_cli(&["--diff", &range]);
        assert_eq!(code, 0, "stderr: {stderr}");
        assert_eq!(
            stdout.trim(),
            "apps/demo/src/copy15.rs:2-16 duplicates packages/mylib/src/helper.rs:2 (15 lines). Use //packages/mylib:mylib instead."
        );
        assert!(!stdout.contains("copy11.rs"));

        let (code_strict, stdout_strict, _) = repo.run_cli(&["--diff", &range, "--strict"]);
        assert_eq!(code_strict, 1);
        assert_eq!(stdout_strict, stdout);

        let (code_allowed, stdout_allowed, _) = repo.run_cli(&[
            "--diff",
            &range,
            "--strict",
            "--allow",
            "apps/demo/src/copy15.rs",
        ]);
        assert_eq!(code_allowed, 0);
        assert!(stdout_allowed.is_empty());
    }

    #[test]
    fn e2e_diff_allow_txt_and_missing_catalog_target() {
        let repo = TempRepo::new("allowtxt");
        repo.write("packages/nocat/src/lib.rs", &helper_lines(16));
        let base = repo.commit_all("add package without catalog");

        repo.write("apps/a/src/copy.rs", &helper_lines(14));
        let head1 = repo.commit_all("add copy");

        let range1 = format!("{base}...{head1}");
        let (code, stdout, stderr) = repo.run_cli(&["--diff", &range1, "--strict"]);
        assert_eq!(code, 1, "stderr: {stderr}");
        assert_eq!(
            stdout.trim(),
            "apps/a/src/copy.rs:1-14 duplicates packages/nocat/src/lib.rs:1 (14 lines). Use packages/nocat instead."
        );

        repo.write("tools/dupcheck/allow.txt", "# deliberate\napps/a/**\n");
        let head2 = repo.commit_all("allow apps/a");
        let range2 = format!("{base}...{head2}");
        let (code2, stdout2, stderr2) = repo.run_cli(&["--diff", &range2, "--strict"]);
        assert_eq!(code2, 0, "stderr: {stderr2}");
        assert!(stdout2.is_empty());
    }

    #[test]
    fn e2e_families_counts_and_exclusions() {
        let repo = TempRepo::new("families");
        repo.write(
            "packages/rust/vitruvian-pycompat/src/json.rs",
            "pub fn canonical() {}\n",
        );
        repo.write(
            "tools/reexport/src/json.rs",
            "pub use vitruvian_pycompat::json;\n",
        );
        repo.write(
            "tools/app1/src/json.rs",
            "\
// comment
pub struct S {
    #[cfg(test)]
    pub field: bool,
}
pub fn shared() {}
#[cfg(test)]
mod tests {
    pub fn test_only() {}
}
",
        );
        repo.write(
            "tools/app2/src/json.rs",
            "\
pub fn shared() {}
pub fn unique_to_app2() {}
",
        );
        repo.commit_all("families fixture");

        let (code, stdout, stderr) = repo.run_cli(&["--families", "--ref", "HEAD"]);
        assert_eq!(code, 0, "stderr: {stderr}");
        // app1 has 5 non-comment lines (kept indented #[cfg(test)] + field, dropped mod tests).
        // app2 has 2 lines. Both share `pub fn shared() {}` (2 lines total across files).
        assert!(stdout.contains("| `json` | 2 | 7 | 2 (28%) |"), "{stdout}");
        assert!(
            stdout.contains("| **Total** | **2** | **7** | **2 (28%)** |"),
            "{stdout}"
        );
    }
}
