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

//! Helpers for the black-box tests of the tools/ci binaries.
//!
//! Each test runs the REAL binary as a subprocess, the way CI does, with fake
//! `gh`/`gcloud`/`curl` scripts first on PATH and throwaway git repos, so no
//! test needs the network or credentials. The binary's path comes from an
//! environment variable the rust_test sets with `$(rootpath ...)`.

use std::ffi::OsStr;
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicUsize, Ordering};

/// The binary under test, from `$(rootpath ...)` in env var `var`, made
/// absolute so a test can run it from any directory.
pub fn bin(var: &str) -> PathBuf {
    let rel = std::env::var_os(var)
        .unwrap_or_else(|| panic!("{var} is not set: the rust_test must pass $(rootpath ...)"));
    fs::canonicalize(&rel).unwrap_or_else(|e| panic!("{var}={}: {e}", Path::new(&rel).display()))
}

/// A directory removed when dropped. Lives under TEST_TMPDIR when Bazel
/// provides one.
pub struct TempDir(PathBuf);

impl TempDir {
    pub fn new() -> TempDir {
        static N: AtomicUsize = AtomicUsize::new(0);
        let base = std::env::var_os("TEST_TMPDIR")
            .map(PathBuf::from)
            .unwrap_or_else(std::env::temp_dir);
        let p = base.join(format!(
            "ci-testkit-{}-{}",
            std::process::id(),
            N.fetch_add(1, Ordering::SeqCst)
        ));
        let _ = fs::remove_dir_all(&p);
        fs::create_dir_all(&p).unwrap();
        // Canonical, so paths compare equal to what a child's `pwd -P` prints.
        TempDir(fs::canonicalize(&p).unwrap())
    }

    pub fn path(&self) -> &Path {
        &self.0
    }

    pub fn join<P: AsRef<Path>>(&self, p: P) -> PathBuf {
        self.0.join(p)
    }
}

impl Default for TempDir {
    fn default() -> Self {
        TempDir::new()
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

/// Write `contents` to `path` (creating parents).
pub fn write(path: impl AsRef<Path>, contents: impl AsRef<[u8]>) {
    let path = path.as_ref();
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).unwrap();
    }
    fs::write(path, contents).unwrap_or_else(|e| panic!("write {}: {e}", path.display()));
}

/// Write an executable (a fake `gh`, `gcloud`, ...).
pub fn write_exe(path: impl AsRef<Path>, contents: impl AsRef<[u8]>) {
    let path = path.as_ref();
    write(path, contents);
    fs::set_permissions(path, fs::Permissions::from_mode(0o755)).unwrap();
}

/// Read a file to a String, or "" when it does not exist.
pub fn read(path: impl AsRef<Path>) -> String {
    fs::read(path.as_ref())
        .map(|b| String::from_utf8_lossy(&b).into_owned())
        .unwrap_or_default()
}

/// `dir` prepended to the current PATH.
pub fn path_with(dir: &Path) -> String {
    format!(
        "{}:{}",
        dir.display(),
        std::env::var("PATH").unwrap_or_else(|_| "/usr/bin:/bin".into())
    )
}

/// What one run of the binary did.
#[derive(Debug)]
pub struct Output {
    pub code: i32,
    pub stdout: String,
    pub stderr: String,
}

impl Output {
    /// stdout then stderr, the way a test reading `2>&1` would see them
    /// (order between the two streams is not preserved).
    pub fn all(&self) -> String {
        format!("{}{}", self.stdout, self.stderr)
    }
}

/// A run of the binary under test: `Run::new(&bin).cwd(..).env(..).arg(..).go()`.
pub struct Run {
    cmd: Command,
    input: Option<Vec<u8>>,
}

impl Run {
    pub fn new(bin: &Path) -> Run {
        let mut cmd = Command::new(bin);
        // A test never wants the runner's own GitHub step files, nor a
        // `bazel run` working directory leaking in.
        for k in [
            "GITHUB_OUTPUT",
            "GITHUB_STEP_SUMMARY",
            "GITHUB_ENV",
            "BUILD_WORKING_DIRECTORY",
            "BUILD_WORKSPACE_DIRECTORY",
        ] {
            cmd.env_remove(k);
        }
        Run { cmd, input: None }
    }

    pub fn arg(mut self, a: impl AsRef<OsStr>) -> Run {
        self.cmd.arg(a);
        self
    }

    pub fn args<I, S>(mut self, args: I) -> Run
    where
        I: IntoIterator<Item = S>,
        S: AsRef<OsStr>,
    {
        self.cmd.args(args);
        self
    }

    pub fn env(mut self, k: impl AsRef<OsStr>, v: impl AsRef<OsStr>) -> Run {
        self.cmd.env(k, v);
        self
    }

    pub fn env_remove(mut self, k: impl AsRef<OsStr>) -> Run {
        self.cmd.env_remove(k);
        self
    }

    /// Put `dir` first on PATH (where the fakes live).
    pub fn path_first(self, dir: &Path) -> Run {
        let p = path_with(dir);
        self.env("PATH", p)
    }

    pub fn cwd(mut self, dir: impl AsRef<Path>) -> Run {
        self.cmd.current_dir(dir);
        self
    }

    pub fn stdin(mut self, input: impl AsRef<[u8]>) -> Run {
        self.input = Some(input.as_ref().to_vec());
        self
    }

    /// Like `go`, but kills the binary and returns None when it has not
    /// finished within `limit`: a hang becomes a test failure, not a stuck test.
    pub fn go_within(mut self, limit: std::time::Duration) -> Option<Output> {
        use std::io::{Read, Write};
        self.cmd
            .stdin(if self.input.is_some() {
                Stdio::piped()
            } else {
                Stdio::null()
            })
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        let mut child = self.cmd.spawn().expect("spawn the binary under test");
        if let Some(input) = self.input.take() {
            let mut si = child.stdin.take().unwrap();
            std::thread::spawn(move || {
                let _ = si.write_all(&input);
            });
        }
        let mut so = child.stdout.take().unwrap();
        let mut se = child.stderr.take().unwrap();
        let out_t = std::thread::spawn(move || {
            let mut b = Vec::new();
            let _ = so.read_to_end(&mut b);
            b
        });
        let err_t = std::thread::spawn(move || {
            let mut b = Vec::new();
            let _ = se.read_to_end(&mut b);
            b
        });
        let start = std::time::Instant::now();
        let status = loop {
            if let Some(st) = child.try_wait().unwrap() {
                break st;
            }
            if start.elapsed() > limit {
                let _ = child.kill();
                let _ = child.wait();
                return None;
            }
            std::thread::sleep(std::time::Duration::from_millis(20));
        };
        Some(Output {
            code: status.code().unwrap_or(128),
            stdout: String::from_utf8_lossy(&out_t.join().unwrap()).into_owned(),
            stderr: String::from_utf8_lossy(&err_t.join().unwrap()).into_owned(),
        })
    }

    pub fn go(mut self) -> Output {
        use std::io::Write;
        self.cmd
            .stdin(if self.input.is_some() {
                Stdio::piped()
            } else {
                Stdio::null()
            })
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        let mut child = self.cmd.spawn().expect("spawn the binary under test");
        if let Some(input) = self.input.take() {
            let mut si = child.stdin.take().unwrap();
            std::thread::spawn(move || {
                let _ = si.write_all(&input);
            });
        }
        let o = child.wait_with_output().unwrap();
        Output {
            code: o.status.code().unwrap_or(128),
            stdout: String::from_utf8_lossy(&o.stdout).into_owned(),
            stderr: String::from_utf8_lossy(&o.stderr).into_owned(),
        }
    }
}

/// `git -C dir args...`; panics with git's stderr when it fails. Returns the
/// trimmed stdout. Commits get a fixed identity and no signing.
pub fn git(dir: &Path, args: &[&str]) -> String {
    let o = Command::new("git")
        .arg("-C")
        .arg(dir)
        .args([
            "-c",
            "user.email=t@t",
            "-c",
            "user.name=t",
            "-c",
            "commit.gpgsign=false",
            "-c",
            "init.defaultBranch=main",
        ])
        .args(args)
        .env("GIT_CONFIG_NOSYSTEM", "1")
        .env("GIT_CONFIG_GLOBAL", "/dev/null")
        .output()
        .expect("run git");
    if !o.status.success() {
        panic!(
            "git {:?} in {}: {}",
            args,
            dir.display(),
            String::from_utf8_lossy(&o.stderr)
        );
    }
    String::from_utf8_lossy(&o.stdout).trim_end().to_string()
}

/// A fresh repo at `dir` with one empty commit; returns its sha.
pub fn git_init(dir: &Path) -> String {
    fs::create_dir_all(dir).unwrap();
    git(dir, &["init", "-q", "."]);
    git(dir, &["commit", "-q", "--allow-empty", "-m", "init"]);
    git(dir, &["rev-parse", "HEAD"])
}

/// Write `contents` at `rel` in `repo`, commit it with `msg`; returns the sha.
pub fn commit_file(repo: &Path, rel: &str, contents: &str, msg: &str) -> String {
    write(repo.join(rel), contents);
    git(repo, &["add", "--", rel]);
    git(repo, &["commit", "-q", "-m", msg]);
    git(repo, &["rev-parse", "HEAD"])
}

/// Assert `hay` contains `needle`, showing both on failure.
#[track_caller]
pub fn assert_has(hay: &str, needle: &str, what: &str) {
    assert!(
        hay.contains(needle),
        "{what}: missing {needle:?}\n--- got ---\n{hay}"
    );
}

/// Assert `hay` does not contain `needle`.
#[track_caller]
pub fn assert_lacks(hay: &str, needle: &str, what: &str) {
    assert!(
        !hay.contains(needle),
        "{what}: unexpected {needle:?}\n--- got ---\n{hay}"
    );
}

/// One job of a workflow file, as the fast-lane and fast-pass guards read it:
/// its id, its `needs:` line, and its `if:` condition folded onto one line.
#[derive(Debug)]
pub struct WorkflowJob {
    pub id: String,
    pub needs: String,
    pub cond: String,
}

/// The jobs under `jobs:` in a workflow, read line by line: a job starts at a
/// two-space `id:` line, `needs:` and `if:` are four-space keys, and an `if:`
/// carries on through its six-space continuation lines.
pub fn workflow_jobs(yaml: &str) -> Vec<WorkflowJob> {
    let mut jobs = Vec::new();
    let mut in_jobs = false;
    let mut in_if = false;
    let mut cur: Option<WorkflowJob> = None;
    for line in yaml.lines() {
        if line.starts_with("jobs:") {
            in_jobs = true;
            continue;
        }
        if !in_jobs {
            continue;
        }
        let two = line.strip_prefix("  ").unwrap_or("");
        if !two.starts_with(' ')
            && two.ends_with(':')
            && two.len() > 1
            && two[..two.len() - 1]
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-')
        {
            jobs.extend(cur.take());
            cur = Some(WorkflowJob {
                id: two[..two.len() - 1].to_string(),
                needs: String::new(),
                cond: String::new(),
            });
            in_if = false;
            continue;
        }
        let Some(job) = cur.as_mut() else { continue };
        if line.starts_with("    needs:") {
            job.needs = line.to_string();
            in_if = false;
        } else if line.starts_with("    if:") {
            job.cond = line.to_string();
            in_if = true;
        } else if in_if && line.starts_with("      ") {
            job.cond.push(' ');
            job.cond.push_str(line);
        } else if line.starts_with("    ")
            && line[4..].starts_with(|c: char| c.is_ascii_lowercase())
        {
            in_if = false;
        }
    }
    jobs.extend(cur);
    jobs
}

/// The text of one job (its id line up to the next job's), or "" when absent.
pub fn workflow_job_text(yaml: &str, id: &str) -> String {
    let header = format!("  {id}:");
    let mut out = String::new();
    let mut on = false;
    for line in yaml.lines() {
        if on {
            let two = line.strip_prefix("  ").unwrap_or("");
            if !two.is_empty() && !two.starts_with(' ') && two.ends_with(':') {
                break;
            }
            out.push_str(line);
            out.push('\n');
        } else if line == header {
            on = true;
        }
    }
    out
}

/// True when `name` appears in `hay` as a whole job id: not part of a longer
/// id made of letters and dashes (the shell suites' `(^|[^a-z-])name([^a-z-]|$)`).
pub fn names_job(hay: &str, name: &str) -> bool {
    let b = hay.as_bytes();
    let edge = |c: u8| !(c.is_ascii_lowercase() || c == b'-');
    let mut from = 0;
    while let Some(i) = hay[from..].find(name) {
        let s = from + i;
        let e = s + name.len();
        if (s == 0 || edge(b[s - 1])) && (e == b.len() || edge(b[e])) {
            return true;
        }
        from = s + 1;
    }
    false
}
