// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

//! How the release tools (publish, package_release, make_dmg, notarize and
//! the signing setups) run the commands they drive.
//!
//! Every external command goes through a [`Runner`], so a test can hand the
//! tools a [`FakeRunner`] that records each command and answers it, and so
//! pin the order and arguments of a release without codesign, hdiutil, gh
//! or Apple's notary service.

use std::cell::RefCell;
use std::collections::BTreeMap;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

/// One command to run.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct Cmd {
    pub program: String,
    pub args: Vec<String>,
    pub cwd: Option<PathBuf>,
    pub stdin: Option<Vec<u8>>,
}

impl Cmd {
    pub fn new(program: &str) -> Cmd {
        Cmd {
            program: program.to_string(),
            ..Cmd::default()
        }
    }

    pub fn arg<S: AsRef<str>>(mut self, a: S) -> Cmd {
        self.args.push(a.as_ref().to_string());
        self
    }

    pub fn args<I, S>(mut self, args: I) -> Cmd
    where
        I: IntoIterator<Item = S>,
        S: AsRef<str>,
    {
        for a in args {
            self.args.push(a.as_ref().to_string());
        }
        self
    }

    pub fn path(self, p: &Path) -> Cmd {
        self.arg(p.to_string_lossy())
    }

    pub fn cwd(mut self, dir: &Path) -> Cmd {
        self.cwd = Some(dir.to_path_buf());
        self
    }

    pub fn stdin(mut self, input: &str) -> Cmd {
        self.stdin = Some(input.as_bytes().to_vec());
        self
    }

    /// The command as one line, program and arguments joined by spaces.
    pub fn line(&self) -> String {
        let mut s = self.program.clone();
        for a in &self.args {
            s.push(' ');
            s.push_str(a);
        }
        s
    }
}

/// What a captured command printed, and how it ended.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct Out {
    pub code: i32,
    pub stdout: String,
    pub stderr: String,
}

impl Out {
    pub fn ok(stdout: &str) -> Out {
        Out {
            code: 0,
            stdout: stdout.to_string(),
            stderr: String::new(),
        }
    }

    pub fn fail(code: i32, stderr: &str) -> Out {
        Out {
            code,
            stdout: String::new(),
            stderr: stderr.to_string(),
        }
    }

    pub fn success(&self) -> bool {
        self.code == 0
    }
}

pub trait Runner {
    /// Runs with the terminal's output, as a shell script's plain command
    /// does, and returns its exit code (127 when it cannot start, 1 when a
    /// signal ended it).
    fn status(&mut self, cmd: &Cmd) -> i32;
    /// Runs and captures what it prints.
    fn output(&mut self, cmd: &Cmd) -> Out;
    /// Runs with the terminal's output for at most `limit`. `None` when it
    /// was still running then, and was killed.
    fn status_within(&mut self, cmd: &Cmd, limit: Duration) -> Option<i32>;
    fn sleep(&mut self, d: Duration);
    /// Whether `path` is a folder (a mount point, for make_dmg).
    fn is_dir(&mut self, path: &Path) -> bool {
        path.is_dir()
    }
}

/// Runs the commands for real.
#[derive(Debug, Default, Clone)]
pub struct SystemRunner {
    /// Variables set on every command, over the inherited environment.
    pub envs: BTreeMap<String, String>,
}

impl SystemRunner {
    pub fn new() -> SystemRunner {
        SystemRunner::default()
    }

    fn command(&self, cmd: &Cmd) -> Command {
        let mut c = Command::new(&cmd.program);
        c.args(&cmd.args);
        if let Some(dir) = &cmd.cwd {
            c.current_dir(dir);
        }
        for (k, v) in &self.envs {
            c.env(k, v);
        }
        c
    }
}

fn exit_code(status: std::process::ExitStatus) -> i32 {
    status.code().unwrap_or(1)
}

fn feed(child: &mut std::process::Child, input: &Option<Vec<u8>>) {
    if let (Some(bytes), Some(mut pipe)) = (input, child.stdin.take()) {
        let _ = pipe.write_all(bytes);
    }
}

impl Runner for SystemRunner {
    fn status(&mut self, cmd: &Cmd) -> i32 {
        let mut c = self.command(cmd);
        if cmd.stdin.is_some() {
            c.stdin(Stdio::piped());
        }
        match c.spawn() {
            Ok(mut child) => {
                feed(&mut child, &cmd.stdin);
                child.wait().map(exit_code).unwrap_or(1)
            }
            Err(e) => {
                eprintln!("{}: {}", cmd.program, e);
                127
            }
        }
    }

    fn output(&mut self, cmd: &Cmd) -> Out {
        let mut c = self.command(cmd);
        c.stdout(Stdio::piped()).stderr(Stdio::piped());
        c.stdin(if cmd.stdin.is_some() {
            Stdio::piped()
        } else {
            Stdio::null()
        });
        match c.spawn() {
            Ok(mut child) => {
                feed(&mut child, &cmd.stdin);
                match child.wait_with_output() {
                    Ok(o) => Out {
                        code: exit_code(o.status),
                        stdout: String::from_utf8_lossy(&o.stdout).to_string(),
                        stderr: String::from_utf8_lossy(&o.stderr).to_string(),
                    },
                    Err(e) => Out::fail(1, &e.to_string()),
                }
            }
            Err(e) => Out::fail(127, &format!("{}: {}", cmd.program, e)),
        }
    }

    fn status_within(&mut self, cmd: &Cmd, limit: Duration) -> Option<i32> {
        let mut c = self.command(cmd);
        if cmd.stdin.is_some() {
            c.stdin(Stdio::piped());
        }
        let mut child = match c.spawn() {
            Ok(child) => child,
            Err(_) => return Some(127),
        };
        feed(&mut child, &cmd.stdin);
        let started = Instant::now();
        loop {
            if let Ok(Some(status)) = child.try_wait() {
                return Some(exit_code(status));
            }
            if started.elapsed() >= limit {
                // As the script did: TERM, a second's grace, then KILL.
                let _ = Command::new("kill")
                    .args(["-TERM", &child.id().to_string()])
                    .stderr(Stdio::null())
                    .status();
                thread::sleep(Duration::from_secs(1));
                if !matches!(child.try_wait(), Ok(Some(_))) {
                    let _ = child.kill();
                }
                let _ = child.wait();
                return None;
            }
            thread::sleep(Duration::from_millis(200));
        }
    }

    fn sleep(&mut self, d: Duration) {
        thread::sleep(d);
    }
}

type Responder = Box<dyn FnMut(&Cmd) -> Out>;
type DirCheck = Box<dyn FnMut(&Path) -> bool>;

/// Records every command and answers it with `respond`. A command it is
/// asked to run with a time limit answers `None` (timed out) when the
/// responder's code is [`FakeRunner::TIMED_OUT`].
pub struct FakeRunner {
    pub calls: Vec<String>,
    pub cmds: Vec<Cmd>,
    pub slept: Duration,
    respond: Responder,
    dir_check: Option<DirCheck>,
}

impl FakeRunner {
    pub const TIMED_OUT: i32 = -999;

    pub fn new<F: FnMut(&Cmd) -> Out + 'static>(respond: F) -> FakeRunner {
        FakeRunner {
            calls: Vec::new(),
            cmds: Vec::new(),
            slept: Duration::ZERO,
            respond: Box::new(respond),
            dir_check: None,
        }
    }

    /// Answers `is_dir` with `check` instead of the filesystem.
    pub fn with_dirs<F: FnMut(&Path) -> bool + 'static>(mut self, check: F) -> FakeRunner {
        self.dir_check = Some(Box::new(check));
        self
    }

    /// A runner where every command succeeds and prints nothing.
    pub fn succeeding() -> FakeRunner {
        FakeRunner::new(|_| Out::ok(""))
    }

    fn answer(&mut self, cmd: &Cmd) -> Out {
        self.calls.push(cmd.line());
        self.cmds.push(cmd.clone());
        (self.respond)(cmd)
    }

    /// Index of the first recorded call that starts with `prefix`.
    pub fn position(&self, prefix: &str) -> Option<usize> {
        self.calls.iter().position(|c| c.starts_with(prefix))
    }

    pub fn count(&self, prefix: &str) -> usize {
        self.calls.iter().filter(|c| c.starts_with(prefix)).count()
    }
}

impl Runner for FakeRunner {
    fn status(&mut self, cmd: &Cmd) -> i32 {
        self.answer(cmd).code
    }

    fn output(&mut self, cmd: &Cmd) -> Out {
        self.answer(cmd)
    }

    fn status_within(&mut self, cmd: &Cmd, _limit: Duration) -> Option<i32> {
        let code = self.answer(cmd).code;
        if code == FakeRunner::TIMED_OUT {
            None
        } else {
            Some(code)
        }
    }

    fn sleep(&mut self, d: Duration) {
        self.slept += d;
    }

    fn is_dir(&mut self, path: &Path) -> bool {
        match &mut self.dir_check {
            Some(check) => check(path),
            None => path.is_dir(),
        }
    }
}

/// Runs `cmd` with the terminal's output; a failure is its exit code, as
/// `set -e` stops a script with the failing command's code.
pub fn run(r: &mut dyn Runner, cmd: &Cmd) -> Result<(), i32> {
    match r.status(cmd) {
        0 => Ok(()),
        code => Err(code),
    }
}

/// Runs `cmd` captured; a failure is its exit code.
pub fn capture(r: &mut dyn Runner, cmd: &Cmd) -> Result<String, i32> {
    let out = r.output(cmd);
    if out.success() {
        Ok(out.stdout)
    } else {
        Err(if out.code == 0 { 1 } else { out.code })
    }
}

/// A new private (0700) folder under `parent`, like `mktemp -d`.
pub fn make_temp_dir(parent: &Path, prefix: &str) -> std::io::Result<PathBuf> {
    thread_local!(static SEQ: RefCell<u64> = const { RefCell::new(0) });
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    let seq = SEQ.with(|s| {
        let mut s = s.borrow_mut();
        *s += 1;
        *s
    });
    let dir = parent.join(format!(
        "{}.{}.{}.{}",
        prefix,
        std::process::id(),
        nanos,
        seq
    ));
    let mut b = fs::DirBuilder::new();
    #[cfg(unix)]
    {
        use std::os::unix::fs::DirBuilderExt;
        b.mode(0o700);
    }
    b.create(&dir)?;
    Ok(dir)
}

/// Writes `bytes` to a new file readable by its owner alone (umask 077).
pub fn write_private(path: &Path, bytes: &[u8]) -> std::io::Result<()> {
    let _ = fs::remove_file(path);
    let mut o = fs::OpenOptions::new();
    o.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        o.mode(0o600);
    }
    let mut f = o.open(path)?;
    f.write_all(bytes)
}

/// Removes a folder when dropped, as a script's `trap … EXIT` does.
pub struct TempDir(pub PathBuf);

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

/// The temp folder a script's `mktemp` uses: `$TMPDIR`, else `/tmp`.
pub fn temp_root() -> PathBuf {
    std::env::var_os("TMPDIR")
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/tmp"))
}

/// Decodes standard base64, as `base64 --decode` does; whitespace is
/// skipped and anything else outside the alphabet is an error.
pub fn decode_base64(input: &str) -> Result<Vec<u8>, String> {
    let mut out = Vec::new();
    let mut buf: u32 = 0;
    let mut bits: u8 = 0;
    for b in input.bytes() {
        if b.is_ascii_whitespace() || b == b'=' {
            continue;
        }
        let val = match b {
            b'A'..=b'Z' => b - b'A',
            b'a'..=b'z' => b - b'a' + 26,
            b'0'..=b'9' => b - b'0' + 52,
            b'+' => 62,
            b'/' => 63,
            _ => return Err(format!("invalid base64 byte: 0x{:02x}", b)),
        };
        buf = (buf << 6) | (val as u32);
        bits += 6;
        if bits >= 8 {
            bits -= 8;
            out.push(((buf >> bits) & 0xff) as u8);
        }
    }
    Ok(out)
}

/// The first `Developer ID Application` identity in `security find-identity
/// -v -p codesigning` output, as `grep … | head -1 | sed -E 's/.*"(.*)".*/\1/'`.
pub fn developer_id_from_listing(listing: &str) -> Option<String> {
    let line = listing
        .lines()
        .find(|l| l.contains("Developer ID Application"))?;
    let first = line.find('"')?;
    let last = line.rfind('"')?;
    if last <= first {
        return None;
    }
    let id = &line[first + 1..last];
    if id.is_empty() {
        None
    } else {
        Some(id.to_string())
    }
}

/// The installed Developer ID identity, if there is one.
pub fn detect_developer_id(r: &mut dyn Runner) -> Option<String> {
    let out = r.output(&Cmd::new("security").args(["find-identity", "-v", "-p", "codesigning"]));
    developer_id_from_listing(&out.stdout)
}

/// `CFBundleShortVersionString` of an Info.plist, read with PlistBuddy as
/// the scripts read it.
pub fn plist_short_version(r: &mut dyn Runner, plist: &Path) -> Result<String, i32> {
    let v = capture(
        r,
        &Cmd::new("/usr/libexec/PlistBuddy")
            .args(["-c", "Print CFBundleShortVersionString"])
            .path(plist),
    )?;
    let v = v.trim().to_string();
    if v.is_empty() {
        eprintln!("✗ {} has no CFBundleShortVersionString", plist.display());
        return Err(1);
    }
    Ok(v)
}

/// The package folder (`apps/desktop/vitruvian`) under the workspace that
/// `bazel run` was started in, else the git checkout, else the current
/// folder.
pub fn workspace_root() -> PathBuf {
    if let Some(w) = std::env::var_os("BUILD_WORKSPACE_DIRECTORY").filter(|v| !v.is_empty()) {
        return PathBuf::from(w);
    }
    if let Ok(o) = Command::new("git")
        .args(["rev-parse", "--show-toplevel"])
        .output()
    {
        if o.status.success() {
            let s = String::from_utf8_lossy(&o.stdout).trim().to_string();
            if !s.is_empty() {
                return PathBuf::from(s);
            }
        }
    }
    std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."))
}

pub const PKG_REL: &str = "apps/desktop/vitruvian";

pub fn package_dir() -> PathBuf {
    workspace_root().join(PKG_REL)
}

/// A path given on the command line, made absolute against the folder
/// `bazel run` was started from (its runfiles folder is no one's cwd).
pub fn user_path(arg: &str) -> PathBuf {
    let p = PathBuf::from(arg);
    if p.is_absolute() {
        return p;
    }
    let base = std::env::var_os("BUILD_WORKING_DIRECTORY")
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
        .or_else(|| std::env::current_dir().ok())
        .unwrap_or_else(|| PathBuf::from("."));
    base.join(p)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn developer_id_is_the_first_developer_id_application_line() {
        let listing = "  1) AAAA \"Apple Development: Someone (X)\"\n  2) BBBB \"Developer ID Application: Vitruvian Software (TEAM123)\"\n  3) CCCC \"Developer ID Application: Other (T2)\"\n     3 valid identities found\n";
        assert_eq!(
            developer_id_from_listing(listing).as_deref(),
            Some("Developer ID Application: Vitruvian Software (TEAM123)")
        );
        assert_eq!(
            developer_id_from_listing("0 valid identities found\n"),
            None
        );
    }

    #[test]
    fn base64_decodes_like_base64_decode() {
        assert_eq!(decode_base64("aGVs\nbG8=").unwrap(), b"hello");
        assert!(decode_base64("a*b").is_err());
    }

    #[test]
    fn capture_returns_the_failing_code() {
        let mut r = FakeRunner::new(|c| {
            if c.program == "bad" {
                Out::fail(3, "nope")
            } else {
                Out::ok("yes\n")
            }
        });
        assert_eq!(capture(&mut r, &Cmd::new("good")).unwrap(), "yes\n");
        assert_eq!(capture(&mut r, &Cmd::new("bad")), Err(3));
        assert_eq!(r.calls, vec!["good", "bad"]);
    }

    #[test]
    fn private_files_and_dirs_are_owner_only() {
        let root = make_temp_dir(&std::env::temp_dir(), "release_exec_test").unwrap();
        let _guard = TempDir(root.clone());
        let f = root.join("secret");
        write_private(&f, b"x").unwrap();
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            assert_eq!(
                fs::metadata(&f).unwrap().permissions().mode() & 0o777,
                0o600
            );
            assert_eq!(
                fs::metadata(&root).unwrap().permissions().mode() & 0o777,
                0o700
            );
        }
    }

    #[test]
    fn system_runner_reports_exit_codes_and_timeouts() {
        let mut r = SystemRunner::new();
        assert_eq!(r.status(&Cmd::new("sh").args(["-c", "exit 4"])), 4);
        let out = r.output(&Cmd::new("sh").args(["-c", "cat; echo err >&2"]).stdin("in"));
        assert_eq!(
            (out.code, out.stdout.as_str(), out.stderr.as_str()),
            (0, "in", "err\n")
        );
        assert_eq!(
            r.status_within(&Cmd::new("sleep").arg("5"), Duration::from_millis(300)),
            None
        );
        assert_eq!(r.status(&Cmd::new("/nonexistent/program")), 127);
    }
}
