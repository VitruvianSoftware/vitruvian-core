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

    /// [`Cmd::line`] with secrets hidden; see [`redact_args`].
    pub fn redacted_line(&self) -> String {
        let mut s = self.program.clone();
        for a in redact_args(&self.program, &self.args) {
            s.push(' ');
            s.push_str(&a);
        }
        s
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
    /// does, and returns its exit code (127 when it cannot start, 128+N
    /// when signal N ended it).
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
    /// Writes `text` to the tool's stderr: where a captured command's own
    /// error goes when it fails, as a script let it through to the log.
    fn report(&mut self, text: &str) {
        eprint!("{}", text);
    }
    /// The secret values in play (from the environment), hidden wherever
    /// they turn up in what the tools report.
    fn secrets(&self) -> Vec<String> {
        Vec::new()
    }
}

/// Runs the commands for real.
#[derive(Debug, Default, Clone)]
pub struct SystemRunner {
    /// Variables set on every command, over the inherited environment.
    pub envs: BTreeMap<String, String>,
    /// Secret values hidden from what the tools report; see [`env_secrets`].
    pub secrets: Vec<String>,
}

impl SystemRunner {
    pub fn new() -> SystemRunner {
        SystemRunner::default()
    }

    /// A runner that hides the secrets this process's environment holds.
    pub fn from_env() -> SystemRunner {
        let env: BTreeMap<String, String> = std::env::vars().collect();
        SystemRunner {
            secrets: env_secrets(&env),
            ..SystemRunner::default()
        }
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

/// The exit code a shell would report: the program's own, or 128+N when
/// signal N ended it.
fn exit_code(status: std::process::ExitStatus) -> i32 {
    if let Some(code) = status.code() {
        return code;
    }
    #[cfg(unix)]
    {
        use std::os::unix::process::ExitStatusExt;
        if let Some(sig) = status.signal() {
            return 128 + sig;
        }
    }
    1
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

    fn secrets(&self) -> Vec<String> {
        self.secrets.clone()
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
    /// Each command run with a time limit, and the limit it was given.
    pub limits: Vec<(String, Duration)>,
    /// What the tool wrote through [`Runner::report`].
    pub stderr: String,
    /// What [`Runner::secrets`] answers.
    pub secrets: Vec<String>,
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
            limits: Vec::new(),
            stderr: String::new(),
            secrets: Vec::new(),
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

    fn status_within(&mut self, cmd: &Cmd, limit: Duration) -> Option<i32> {
        self.limits.push((cmd.line(), limit));
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

    fn report(&mut self, text: &str) {
        self.stderr.push_str(text);
    }

    fn secrets(&self) -> Vec<String> {
        self.secrets.clone()
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

/// Runs `cmd` captured; a failure is its exit code. A failure also writes
/// which command failed and what it printed to stderr, so the log says why
/// (a script's `$(…)` let that stderr through).
pub fn capture(r: &mut dyn Runner, cmd: &Cmd) -> Result<String, i32> {
    let out = r.output(cmd);
    if out.success() {
        return Ok(out.stdout);
    }
    let code = if out.code == 0 { 1 } else { out.code };
    let mut text = format!("✗ `{}` failed (exit {})\n", cmd.redacted_line(), code);
    text.push_str(&out.stderr);
    if !out.stderr.is_empty() && !out.stderr.ends_with('\n') {
        text.push('\n');
    }
    report_redacted(r, &text);
    Err(code)
}

/// Reports `text` with every secret the runner knows of hidden, so a
/// command's own error output cannot echo one into the log.
pub fn report_redacted(r: &mut dyn Runner, text: &str) {
    let secrets = r.secrets();
    r.report(&redact_known(text, &secrets));
}

pub const REDACTED: &str = "<redacted>";

/// Flags whose next argument is a secret, for any program.
const SECRET_FLAGS: [&str; 6] = [
    "--password",
    "--passphrase",
    "--token",
    "--secret",
    "--api-key",
    "--client-secret",
];

/// `security`'s flags that carry a password, by subcommand. Elsewhere the
/// same letters are not secrets: `import -k` is the keychain path and
/// `find-identity -p` a policy name.
const SECURITY_SECRET_FLAGS: [(&str, &str); 6] = [
    ("create-keychain", "-p"),
    ("unlock-keychain", "-p"),
    ("set-key-partition-list", "-k"),
    ("import", "-P"),
    ("export", "-P"),
    ("set-keychain-password", "-p"),
];

/// Whether a variable, flag or header name names a secret. Precise on
/// purpose: a name holding a secret word as a whole word (`token`,
/// `password`, …), or `api`/`access`/`private`/`secret` followed by `key`.
/// `key` alone is not one: `keychain`, `key-id` and `cache_key` stay.
pub fn is_secret_name(name: &str) -> bool {
    let lower = name.to_ascii_lowercase();
    let words: Vec<&str> = lower
        .split(|c: char| !c.is_ascii_alphanumeric())
        .filter(|w| !w.is_empty())
        .collect();
    const WHOLE: [&str; 9] = [
        "token",
        "secret",
        "password",
        "passwd",
        "passphrase",
        "authorization",
        "credential",
        "credentials",
        "apikey",
    ];
    if words.iter().any(|w| WHOLE.contains(w)) {
        return true;
    }
    words
        .windows(2)
        .any(|p| p[1] == "key" && matches!(p[0], "api" | "access" | "private" | "secret"))
}

/// The values of the environment's secrets: every variable whose name
/// [`is_secret_name`], plus the base64 p12 and its password.
pub fn env_secrets(env: &BTreeMap<String, String>) -> Vec<String> {
    let mut v: Vec<String> = env
        .iter()
        .filter(|(k, val)| {
            !val.is_empty()
                && (is_secret_name(k)
                    || matches!(k.as_str(), "SIGNING_CERT_P12" | "NOTARY_API_KEY_P8"))
        })
        .map(|(_, val)| val.clone())
        .collect();
    v.sort();
    v.dedup();
    v
}

/// `text` with every exact occurrence of a known secret hidden, longest
/// first. Values under 4 characters are skipped: hiding them would shred
/// ordinary words and they are not real secrets.
pub fn redact_known(text: &str, secrets: &[String]) -> String {
    let mut sorted: Vec<&String> = secrets.iter().filter(|s| s.len() >= 4).collect();
    sorted.sort_by_key(|s| std::cmp::Reverse(s.len()));
    let mut out = text.to_string();
    for s in sorted {
        out = out.replace(s.as_str(), REDACTED);
    }
    out
}

/// The arguments of `program` with secrets replaced by `<redacted>`, one
/// argument at a time (so a secret holding a space is hidden whole): the
/// argument after a secret flag, the value of a `NAME=value` whose name
/// [`is_secret_name`], an `Authorization:` header's value, a URL's
/// credentials and an openssl `pass:` value.
pub fn redact_args(program: &str, args: &[String]) -> Vec<String> {
    let base = Path::new(program)
        .file_name()
        .map(|f| f.to_string_lossy().to_string())
        .unwrap_or_default();
    let sub = args.first().map(String::as_str).unwrap_or("");
    let security_flag: Option<&str> = if base == "security" {
        SECURITY_SECRET_FLAGS
            .iter()
            .find(|(s, _)| *s == sub)
            .map(|(_, f)| *f)
    } else {
        None
    };
    let mut out = Vec::with_capacity(args.len());
    let mut hide_next = false;
    for a in args {
        if hide_next {
            out.push(REDACTED.to_string());
            hide_next = false;
            continue;
        }
        hide_next = SECRET_FLAGS.contains(&a.as_str()) || security_flag == Some(a.as_str());
        out.push(redact_arg(a));
    }
    out
}

fn redact_arg(arg: &str) -> String {
    let lower = arg.to_ascii_lowercase();
    if let Some(i) = lower.find("authorization:") {
        return format!("{} {}", &arg[..i + "authorization:".len()], REDACTED);
    }
    if lower.starts_with("pass:") {
        return format!("pass:{}", REDACTED);
    }
    if let Some(scheme_end) = arg.find("://") {
        let rest = &arg[scheme_end + 3..];
        let host_end = rest.find('/').unwrap_or(rest.len());
        if let Some(at) = rest[..host_end].rfind('@') {
            let user = match rest[..at].find(':') {
                Some(colon) => format!("{}:{}", &rest[..colon], REDACTED),
                // `https://TOKEN@host`: the whole userinfo is the secret.
                None => REDACTED.to_string(),
            };
            return format!("{}{}{}", &arg[..scheme_end + 3], user, &rest[at..]);
        }
        return arg.to_string();
    }
    // The name before each `=` is what follows the previous one, so
    // `--remote_header=x-buildbuddy-api-key=V` is judged by
    // `x-buildbuddy-api-key`.
    let mut start = 0;
    for (i, _) in arg.match_indices('=') {
        if is_secret_name(&arg[start..i]) {
            return format!("{}={}", &arg[..i], REDACTED);
        }
        start = i + 1;
    }
    arg.to_string()
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

/// Paths removed if SIGHUP, SIGINT or SIGTERM ends the process: the
/// notary key and the signing certificates, which a script's `trap … EXIT`
/// removed on Ctrl-C or a cancelled CI job and a `Drop` never sees.
#[cfg(unix)]
mod on_signal {
    use std::ffi::CString;
    use std::os::raw::{c_char, c_int};
    use std::os::unix::ffi::OsStrExt;
    use std::path::Path;
    use std::ptr;
    use std::sync::atomic::{AtomicPtr, Ordering};
    use std::sync::Once;

    const SLOTS: usize = 16;
    const SIGNALS: [c_int; 3] = [1, 2, 15]; // SIGHUP, SIGINT, SIGTERM
    const SIG_DFL: usize = 0;

    #[allow(clippy::declare_interior_mutable_const)]
    const EMPTY: AtomicPtr<c_char> = AtomicPtr::new(ptr::null_mut());
    static PATHS: [AtomicPtr<c_char>; SLOTS] = [EMPTY; SLOTS];
    static INSTALL: Once = Once::new();

    extern "C" {
        fn signal(sig: c_int, handler: usize) -> usize;
        fn raise(sig: c_int) -> c_int;
        fn unlink(path: *const c_char) -> c_int;
        fn rmdir(path: *const c_char) -> c_int;
    }

    // Only async-signal-safe calls: unlink, rmdir, signal, raise.
    extern "C" fn handle(sig: c_int) {
        // Files first, so the folders that held them are empty for rmdir.
        for slot in PATHS.iter().rev() {
            let p = slot.load(Ordering::SeqCst);
            if !p.is_null() {
                unsafe {
                    if unlink(p) != 0 {
                        rmdir(p);
                    }
                }
            }
        }
        // Then die of the same signal, so the exit status says so (128+N).
        unsafe {
            signal(sig, SIG_DFL);
            raise(sig);
        }
    }

    /// Removes `path` if a signal ends the process, until dropped.
    pub struct Guard(usize);

    impl Drop for Guard {
        fn drop(&mut self) {
            let p = PATHS[self.0].swap(ptr::null_mut(), Ordering::SeqCst);
            if !p.is_null() {
                drop(unsafe { CString::from_raw(p) });
            }
        }
    }

    pub fn remove(path: &Path) -> Option<Guard> {
        INSTALL.call_once(|| {
            for sig in SIGNALS {
                unsafe {
                    signal(sig, handle as extern "C" fn(c_int) as usize);
                }
            }
        });
        let c = CString::new(path.as_os_str().as_bytes()).ok()?.into_raw();
        for (i, slot) in PATHS.iter().enumerate() {
            if slot
                .compare_exchange(ptr::null_mut(), c, Ordering::SeqCst, Ordering::SeqCst)
                .is_ok()
            {
                return Some(Guard(i));
            }
        }
        drop(unsafe { CString::from_raw(c) });
        None
    }
}

/// Removes `path` (a file, or an empty folder) if SIGHUP, SIGINT or
/// SIGTERM ends the process before the returned guard is dropped. Register
/// a folder before the files in it.
pub struct SignalCleanup {
    #[cfg(unix)]
    _guard: Option<on_signal::Guard>,
}

pub fn remove_on_signal(path: &Path) -> SignalCleanup {
    SignalCleanup {
        #[cfg(unix)]
        _guard: on_signal::remove(path),
    }
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
    fn a_failed_capture_reports_which_command_and_its_stderr() {
        let mut r = FakeRunner::new(|_| Out::fail(1, "gh: API rate limit exceeded (HTTP 403)\n"));
        assert_eq!(
            capture(
                &mut r,
                &Cmd::new("gh").args(["api", "repos/x/y/compare/a...b"])
            ),
            Err(1)
        );
        assert!(
            r.stderr.contains("gh api repos/x/y/compare/a...b"),
            "names the command: {:?}",
            r.stderr
        );
        assert!(
            r.stderr.contains("gh: API rate limit exceeded (HTTP 403)"),
            "passes its stderr through: {:?}",
            r.stderr
        );
        // A success prints nothing of its own.
        let mut ok = FakeRunner::succeeding();
        capture(&mut ok, &Cmd::new("true")).unwrap();
        assert_eq!(ok.stderr, "");
    }

    #[test]
    fn a_failed_capture_never_reports_a_secret_on_its_command_line() {
        let mut r = FakeRunner::new(|_| Out::fail(2, "boom\n"));
        let _ = capture(
            &mut r,
            &Cmd::new("bazel").args([
                "cquery",
                "--remote_header=x-buildbuddy-api-key=bb_SECRET",
                "//a:b",
            ]),
        );
        assert!(!r.stderr.contains("bb_SECRET"), "{:?}", r.stderr);
        assert!(
            r.stderr.contains("x-buildbuddy-api-key=<redacted>"),
            "{:?}",
            r.stderr
        );
    }

    fn red(program: &str, args: &[&str]) -> String {
        Cmd::new(program).args(args).redacted_line()
    }

    #[test]
    fn the_redactions_from_the_first_review_still_hold() {
        assert_eq!(
            red(
                "bazel",
                &["build", "--remote_header=x-buildbuddy-api-key=abc=", "//x"]
            ),
            "bazel build --remote_header=x-buildbuddy-api-key=<redacted> //x"
        );
        assert_eq!(
            red(
                "git",
                &[
                    "clone",
                    "https://x-access-token:ghs_abc@github.com/o/r.git",
                    "dir"
                ]
            ),
            "git clone https://x-access-token:<redacted>@github.com/o/r.git dir"
        );
        assert_eq!(
            red("env", &["TOKEN=t1", "PASSWORD=p2", "SECRET=s3"]),
            "env TOKEN=<redacted> PASSWORD=<redacted> SECRET=<redacted>"
        );
        assert_eq!(
            red(
                "security",
                &[
                    "set-key-partition-list",
                    "-S",
                    "apple:",
                    "-s",
                    "-k",
                    "kcpass",
                    "/tmp/k.keychain"
                ]
            ),
            "security set-key-partition-list -S apple: -s -k <redacted> /tmp/k.keychain"
        );
        assert_eq!(
            red("tool", &["--password", "hunter2", "x"]),
            "tool --password <redacted> x"
        );
    }

    #[test]
    fn a_secret_holding_a_space_is_hidden_whole() {
        let mut r = FakeRunner::new(|_| Out::fail(1, "nope\n"));
        let _ = capture(
            &mut r,
            &Cmd::new("tool").args(["--password", "correct horse battery", "--token=staple two"]),
        );
        assert!(!r.stderr.contains("horse"), "{:?}", r.stderr);
        assert!(!r.stderr.contains("battery"), "{:?}", r.stderr);
        assert!(!r.stderr.contains("two"), "{:?}", r.stderr);
        assert!(
            r.stderr
                .contains("tool --password <redacted> --token=<redacted>"),
            "{:?}",
            r.stderr
        );
    }

    #[test]
    fn headers_bare_url_tokens_openssl_pass_and_client_secret_are_hidden() {
        let mut r = FakeRunner::new(|_| Out::fail(1, "nope\n"));
        let _ = capture(
            &mut r,
            &Cmd::new("curl").args([
                "-H",
                "Authorization: Bearer abc123def",
                "https://ghp_TOKENVALUE@github.com/o/r.git",
            ]),
        );
        let _ = capture(
            &mut r,
            &Cmd::new("openssl").args(["pkcs12", "-passout", "pass:p12-PASS", "-out", "id.p12"]),
        );
        let _ = capture(
            &mut r,
            &Cmd::new("tool").args(["--client-secret", "cs-VALUE", "--client-secret=cs-OTHER"]),
        );
        for leaked in [
            "abc123def",
            "ghp_TOKENVALUE",
            "p12-PASS",
            "cs-VALUE",
            "cs-OTHER",
        ] {
            assert!(
                !r.stderr.contains(leaked),
                "{} leaked: {:?}",
                leaked,
                r.stderr
            );
        }
        assert!(
            r.stderr
                .contains("-H Authorization: <redacted> https://<redacted>@github.com/o/r.git"),
            "{:?}",
            r.stderr
        );
        assert!(
            r.stderr.contains("-passout pass:<redacted> -out id.p12"),
            "{:?}",
            r.stderr
        );
        assert!(
            r.stderr
                .contains("--client-secret <redacted> --client-secret=<redacted>"),
            "{:?}",
            r.stderr
        );
    }

    #[test]
    fn a_failed_commands_stderr_hides_the_secrets_in_play() {
        let mut r = FakeRunner::new(|_| {
            Out::fail(
                1,
                "fatal: could not read from https://x-access-token:tok-SECRET-123@github.com\nbad key bb_KEY_VALUE\n",
            )
        });
        r.secrets = env_secrets(
            &[
                ("HOMEBREW_TAP_TOKEN", "tok-SECRET-123"), // gitleaks:allow (made-up test value)
                ("BUILDBUDDY_API_KEY", "bb_KEY_VALUE"),
                ("GRADE", "beta"),
            ]
            .iter()
            .map(|(k, v)| (k.to_string(), v.to_string()))
            .collect(),
        );
        // A positional secret no flag rule knows about is still hidden.
        let _ = capture(&mut r, &Cmd::new("tool").args(["bb_KEY_VALUE"]));
        assert!(!r.stderr.contains("tok-SECRET-123"), "{:?}", r.stderr);
        assert!(!r.stderr.contains("bb_KEY_VALUE"), "{:?}", r.stderr);
        assert!(
            r.stderr.contains("✗ `tool <redacted>` failed"),
            "{:?}",
            r.stderr
        );
        assert!(r.stderr.contains("bad key <redacted>"), "{:?}", r.stderr);
    }

    #[test]
    fn env_secrets_are_the_secret_variables_values_only() {
        let env: BTreeMap<String, String> = [
            ("BUILDBUDDY_API_KEY", "bb"),
            ("HOMEBREW_TAP_TOKEN", "tok"),
            ("SIGNING_CERT_P12", "p12b64"),
            ("SIGNING_CERT_PASSWORD", "pw"),
            ("NOTARY_API_KEY_P8", "p8b64"),
            ("NOTARY_KEY_ID", "KEYID"),
            ("NOTARY_ISSUER_ID", "issuer"),
            ("GH_TOKEN", "ghs"),
            ("GRADE", "beta"),
            ("RUNNER_TEMP", "/tmp/r"),
            ("EMPTY_TOKEN", ""),
        ]
        .iter()
        .map(|(k, v)| (k.to_string(), v.to_string()))
        .collect();
        assert_eq!(
            env_secrets(&env),
            vec!["bb", "ghs", "p12b64", "p8b64", "pw", "tok"]
        );
        // Short values are left in text; long ones are hidden everywhere.
        assert_eq!(
            redact_known("pw tok p12b64 p12b64", &env_secrets(&env)),
            "pw tok <redacted> <redacted>"
        );
    }

    #[test]
    fn non_secrets_are_left_alone() {
        let mut r = FakeRunner::new(|_| Out::fail(1, "nope\n"));
        let cmds = [
            Cmd::new("security").args([
                "import",
                "/r/c.p12",
                "-k",
                "/r/ci.keychain",
                "-P",
                "p12pass",
                "-T",
                "/usr/bin/codesign",
            ]),
            Cmd::new("security").args(["find-identity", "-v", "-p", "codesigning"]),
            Cmd::new("tool").args([
                "cache_key=abc",
                "--keychain=/r/k.keychain",
                "--key-id=KEYID",
                "keyfile=/x/AuthKey.p8",
            ]),
            Cmd::new("ditto").args(["-c", "-k", "--keepParent", "a", "b"]),
            Cmd::new("gh").args([
                "api",
                "-X",
                "PATCH",
                "repos/o/r/git/refs/tags/t",
                "-f",
                "sha=abc",
                "-F",
                "force=true",
            ]),
        ];
        for c in &cmds {
            let _ = capture(&mut r, c);
        }
        for kept in [
            "security import /r/c.p12 -k /r/ci.keychain -P <redacted> -T /usr/bin/codesign",
            "security find-identity -v -p codesigning",
            "tool cache_key=abc --keychain=/r/k.keychain --key-id=KEYID keyfile=/x/AuthKey.p8",
            "ditto -c -k --keepParent a b",
            "gh api -X PATCH repos/o/r/git/refs/tags/t -f sha=abc -F force=true",
        ] {
            assert!(
                r.stderr.contains(kept),
                "expected `{}` in {:?}",
                kept,
                r.stderr
            );
        }
    }

    #[test]
    fn a_command_killed_by_a_signal_reports_128_plus_the_signal_as_a_shell_does() {
        let mut r = SystemRunner::new();
        let killed = Cmd::new("sh").args(["-c", "kill -TERM $$"]);
        assert_eq!(r.status(&killed), 128 + 15);
        assert_eq!(r.output(&killed).code, 128 + 15);
        assert_eq!(
            r.status_within(&killed, Duration::from_secs(10)),
            Some(128 + 15)
        );
    }

    #[test]
    fn a_timed_out_command_that_ignores_term_is_killed_and_reaped() {
        let root = make_temp_dir(&std::env::temp_dir(), "release_exec_hung").unwrap();
        let _guard = TempDir(root.clone());
        let pidfile = root.join("pid");
        // A child that shrugs off TERM, as a hung osascript can.
        let script = format!(
            "trap '' TERM; echo $$ > '{}'; while :; do sleep 1; done",
            pidfile.display()
        );
        let (tx, rx) = std::sync::mpsc::channel();
        thread::spawn(move || {
            let mut r = SystemRunner::new();
            let _ = tx.send(r.status_within(
                &Cmd::new("sh").args(["-c", &script]),
                Duration::from_secs(1),
            ));
        });
        let result = rx.recv_timeout(Duration::from_secs(15));
        let pid = fs::read_to_string(&pidfile).expect("the child wrote its pid");
        let pid = pid.trim().to_string();
        if result.is_err() {
            // Don't leave the loop running after a failed test.
            let _ = Command::new("sh")
                .args(["-c", &format!("kill -KILL {}", pid)])
                .status();
            panic!("status_within never returned: the child that ignores TERM was not killed");
        }
        assert_eq!(result.unwrap(), None, "reported as timed out");
        let pid = pid.as_str();
        // `kill -0` succeeds for a live process and for an unreaped zombie
        // alike, so it fails only once the child is dead and waited for.
        let alive = Command::new("sh")
            .args(["-c", &format!("kill -0 {} 2>/dev/null", pid)])
            .status()
            .unwrap()
            .success();
        if alive {
            let _ = Command::new("sh")
                .args(["-c", &format!("kill -KILL {}", pid)])
                .status();
            panic!("pid {} is still there after the timeout", pid);
        }
    }

    #[test]
    fn the_fake_runner_records_each_time_limit() {
        let mut r = FakeRunner::succeeding();
        r.status_within(&Cmd::new("osascript"), Duration::from_secs(25));
        assert_eq!(
            r.limits,
            vec![("osascript".to_string(), Duration::from_secs(25))]
        );
    }

    /// Run in a child process by the test below: writes a secret, asks for
    /// it to be removed on a signal, says it is ready, and waits.
    #[test]
    #[ignore]
    fn signal_cleanup_child() {
        let Some(dir) = std::env::var_os("SIGNAL_CLEANUP_DIR") else {
            return;
        };
        let dir = PathBuf::from(dir);
        let work = dir.join("work");
        fs::create_dir(&work).unwrap();
        let _d = remove_on_signal(&work);
        let key = work.join("AuthKey.p8");
        write_private(&key, b"secret").unwrap();
        let _k = remove_on_signal(&key);
        fs::write(dir.join("ready"), b"").unwrap();
        thread::sleep(Duration::from_secs(30));
    }

    #[test]
    fn a_signal_removes_the_secret_files_and_ends_with_that_signal() {
        use std::os::unix::process::ExitStatusExt;
        for (sig, name) in [(15, "TERM"), (2, "INT")] {
            let dir = make_temp_dir(&std::env::temp_dir(), "release_exec_signal").unwrap();
            let _guard = TempDir(dir.clone());
            let mut child = Command::new(std::env::current_exe().unwrap())
                .args([
                    "--exact",
                    "tests::signal_cleanup_child",
                    "--ignored",
                    "--nocapture",
                ])
                .env("SIGNAL_CLEANUP_DIR", &dir)
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .spawn()
                .unwrap();
            let started = Instant::now();
            while !dir.join("ready").exists() {
                if started.elapsed() > Duration::from_secs(20) {
                    let _ = child.kill();
                    panic!("the child never got ready");
                }
                thread::sleep(Duration::from_millis(20));
            }
            assert!(dir.join("work/AuthKey.p8").exists());
            Command::new("sh")
                .args(["-c", &format!("kill -{} {}", name, child.id())])
                .status()
                .unwrap();
            let status = child.wait().unwrap();
            assert_eq!(
                status.signal(),
                Some(sig),
                "SIG{} ends it: {:?}",
                name,
                status
            );
            assert!(
                !dir.join("work/AuthKey.p8").exists(),
                "SIG{} left the key behind",
                name
            );
            assert!(
                !dir.join("work").exists(),
                "SIG{} left the key's folder behind",
                name
            );
        }
    }

    #[test]
    fn a_dropped_cleanup_forgets_its_path() {
        let dir = make_temp_dir(&std::env::temp_dir(), "release_exec_forget").unwrap();
        let _guard = TempDir(dir.clone());
        // Every slot is free again once its guard is gone.
        for _ in 0..64 {
            let g = remove_on_signal(&dir.join("x"));
            #[cfg(unix)]
            assert!(g._guard.is_some());
            drop(g);
        }
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
