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

//! Go's `os/exec` as the pipeline tools use it: `exec.CommandContext` with a
//! deadline or a cancelling interrupt, Go's `LookPath` over the caller's
//! PATH, and Go's error wording ("exit status 1", "signal: killed",
//! `exec: "bazel": executable file not found in $PATH`, "context deadline
//! exceeded").

use std::fmt;
use std::fs;
use std::io::{self, Read, Write};
use std::os::fd::AsFd;
use std::os::unix::fs::PermissionsExt;
use std::os::unix::process::{CommandExt, ExitStatusExt};
use std::process::{Command, ExitStatus, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::thread;
use std::time::{Duration, Instant};

use super::oserr;
use super::path;

/// A `context.Context`: no deadline, a deadline, and/or a flag an interrupt
/// sets (`signal.NotifyContext`).
#[derive(Clone, Copy, Default)]
pub struct Ctx {
    deadline: Option<Instant>,
    cancel: Option<&'static AtomicBool>,
}

impl Ctx {
    /// `context.Background()`.
    pub fn background() -> Ctx {
        Ctx::default()
    }

    /// `context.WithTimeout(ctx, time.Duration(secs)*time.Second)`. The
    /// multiplication wraps like Go's int64 arithmetic, and a timeout that
    /// is not positive has already expired.
    pub fn with_timeout_secs(secs: i64) -> Ctx {
        let nanos = secs.wrapping_mul(1_000_000_000);
        let now = Instant::now();
        let deadline = if nanos <= 0 {
            now
        } else {
            now.checked_add(Duration::from_nanos(nanos as u64))
                .unwrap_or(now + Duration::from_secs(86400 * 365 * 100))
        };
        Ctx {
            deadline: Some(deadline),
            cancel: None,
        }
    }

    /// A context cancelled when `flag` is set.
    pub fn with_cancel(flag: &'static AtomicBool) -> Ctx {
        Ctx {
            deadline: None,
            cancel: Some(flag),
        }
    }

    /// `ctx.Err()`, as text.
    pub fn err(&self) -> Option<&'static str> {
        if let Some(c) = self.cancel {
            if c.load(Ordering::SeqCst) {
                return Some("context canceled");
            }
        }
        if let Some(d) = self.deadline {
            if Instant::now() >= d {
                return Some("context deadline exceeded");
            }
        }
        None
    }

    fn cancellable(&self) -> bool {
        self.deadline.is_some() || self.cancel.is_some()
    }
}

static INTERRUPTED: AtomicBool = AtomicBool::new(false);

extern "C" fn on_interrupt(_sig: i32) {
    INTERRUPTED.store(true, Ordering::SeqCst);
}

extern "C" {
    fn signal(signum: i32, handler: usize) -> usize;
}

const SIGINT: i32 = 2;

/// `signal.NotifyContext(context.Background(), os.Interrupt)`: from now on
/// an interrupt cancels the returned context instead of ending the process.
pub fn notify_interrupt() -> Ctx {
    // SAFETY: the handler only stores to an atomic, which is
    // async-signal-safe.
    unsafe {
        signal(SIGINT, on_interrupt as extern "C" fn(i32) as usize);
    }
    Ctx::with_cancel(&INTERRUPTED)
}

/// Where one of the child's standard streams goes.
#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Io {
    /// Go's nil: the null device.
    Null,
    /// A bytes.Buffer: collected and returned.
    Capture,
    /// `os.Stdin` / `os.Stdout` / `os.Stderr` of this process.
    Stdin,
    Stdout,
    Stderr,
}

/// How a run ended when it did not succeed, worded as Go words it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ExecError {
    /// `exec.LookPath` found nothing; the name as given.
    NotFound(String),
    /// The context was done before the start (its Err text).
    Ctx(&'static str),
    /// Starting failed: the full Go message ("fork/exec ...", "chdir ...").
    Start(String),
    /// `*exec.ExitError` for a process that exited non-zero.
    ExitCode(i32),
    /// `*exec.ExitError` for a process ended by a signal.
    Signal { sig: i32, core: bool },
}

impl ExecError {
    /// Whether this is an `*exec.ExitError`.
    pub fn is_exit(&self) -> bool {
        matches!(self, ExecError::ExitCode(_) | ExecError::Signal { .. })
    }

    /// `ExitError.ExitCode()`: the status, or -1 for a signal.
    pub fn exit_code(&self) -> Option<i32> {
        match self {
            ExecError::ExitCode(c) => Some(*c),
            ExecError::Signal { .. } => Some(-1),
            _ => None,
        }
    }
}

impl fmt::Display for ExecError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ExecError::NotFound(name) => write!(
                f,
                "exec: {}: executable file not found in $PATH",
                super::quote::quote(name)
            ),
            ExecError::Ctx(s) => f.write_str(s),
            ExecError::Start(s) => f.write_str(s),
            ExecError::ExitCode(c) => write!(f, "exit status {c}"),
            ExecError::Signal { sig, core } => {
                write!(f, "signal: {}", signal_name(*sig))?;
                if *core {
                    f.write_str(" (core dumped)")?;
                }
                Ok(())
            }
        }
    }
}

/// Go's `exitCode` helper in verifiedrun: 0 on success, the exit status (or
/// -1 for a signal) for an ExitError, 1 for anything else.
pub fn exit_code(r: &Result<(), ExecError>) -> i32 {
    match r {
        Ok(()) => 0,
        Err(e) => e.exit_code().unwrap_or(1),
    }
}

/// `syscall.Signal.String()`.
pub fn signal_name(sig: i32) -> String {
    #[cfg(target_os = "macos")]
    const NAMES: &[&str] = &[
        "",
        "hangup",
        "interrupt",
        "quit",
        "illegal instruction",
        "trace/BPT trap",
        "abort trap",
        "EMT trap",
        "floating point exception",
        "killed",
        "bus error",
        "segmentation fault",
        "bad system call",
        "broken pipe",
        "alarm clock",
        "terminated",
        "urgent I/O condition",
        "suspended (signal)",
        "suspended",
        "continued",
        "child exited",
        "stopped (tty input)",
        "stopped (tty output)",
        "I/O possible",
        "cputime limit exceeded",
        "filesize limit exceeded",
        "virtual timer expired",
        "profiling timer expired",
        "window size changes",
        "information request",
        "user defined signal 1",
        "user defined signal 2",
    ];
    #[cfg(not(target_os = "macos"))]
    const NAMES: &[&str] = &[
        "",
        "hangup",
        "interrupt",
        "quit",
        "illegal instruction",
        "trace/breakpoint trap",
        "aborted",
        "bus error",
        "floating point exception",
        "killed",
        "user defined signal 1",
        "segmentation fault",
        "user defined signal 2",
        "broken pipe",
        "alarm clock",
        "terminated",
        "stack fault",
        "child exited",
        "continued",
        "stopped (signal)",
        "stopped",
        "stopped (tty input)",
        "stopped (tty output)",
        "urgent I/O condition",
        "CPU time limit exceeded",
        "file size limit exceeded",
        "virtual timer expired",
        "profiling timer expired",
        "window changed",
        "I/O possible",
        "power failure",
        "bad system call",
    ];
    if sig > 0 && (sig as usize) < NAMES.len() {
        NAMES[sig as usize].to_string()
    } else {
        format!("signal {sig}")
    }
}

/// `exec.LookPath(file)` against this process's PATH.
pub fn look_path(file: &str) -> Result<String, ExecError> {
    if file.contains('/') {
        return if is_executable(file) {
            Ok(file.to_string())
        } else {
            Err(ExecError::NotFound(file.to_string()))
        };
    }
    let path_env = std::env::var("PATH").unwrap_or_default();
    for d in path_env.split(':') {
        let d = if d.is_empty() { "." } else { d };
        let candidate = path::join(&[d, file]);
        if is_executable(&candidate) {
            return Ok(candidate);
        }
    }
    Err(ExecError::NotFound(file.to_string()))
}

fn is_executable(p: &str) -> bool {
    match fs::metadata(p) {
        Ok(m) => !m.is_dir() && m.permissions().mode() & 0o111 != 0,
        Err(_) => false,
    }
}

/// One command, as an `exec.Cmd` would be set up.
pub struct Cmd {
    pub name: String,
    pub args: Vec<String>,
    /// cmd.Dir; empty means the current directory.
    pub dir: String,
    /// cmd.Env as "KEY=value" entries; None inherits this process's.
    pub env: Option<Vec<String>>,
    pub stdin: Io,
    pub stdout: Io,
    pub stderr: Io,
}

impl Cmd {
    pub fn new(name: &str, args: &[&str]) -> Cmd {
        Cmd {
            name: name.to_string(),
            args: args.iter().map(|s| s.to_string()).collect(),
            dir: String::new(),
            env: None,
            stdin: Io::Null,
            stdout: Io::Null,
            stderr: Io::Null,
        }
    }
}

/// What a finished (or failed) command left behind.
#[derive(Default)]
pub struct Output {
    pub stdout: Vec<u8>,
    pub stderr: Vec<u8>,
}

fn stdio_for(io: Io) -> io::Result<Stdio> {
    Ok(match io {
        Io::Null => Stdio::null(),
        Io::Capture => Stdio::piped(),
        Io::Stdin => Stdio::from(io::stdin().as_fd().try_clone_to_owned()?),
        Io::Stdout => Stdio::from(io::stdout().as_fd().try_clone_to_owned()?),
        Io::Stderr => Stdio::from(io::stderr().as_fd().try_clone_to_owned()?),
    })
}

fn status_result(st: ExitStatus) -> Result<(), ExecError> {
    if st.success() {
        return Ok(());
    }
    if let Some(c) = st.code() {
        return Err(ExecError::ExitCode(c));
    }
    if let Some(sig) = st.signal() {
        return Err(ExecError::Signal {
            sig,
            core: st.core_dumped(),
        });
    }
    Err(ExecError::ExitCode(-1))
}

/// `cmd.Run()` under `ctx`. The output is returned whatever the result, as
/// Go's buffers hold whatever was written before a failure.
pub fn run(cmd: &Cmd, ctx: &Ctx) -> (Result<(), ExecError>, Output) {
    let mut out = Output::default();
    let path = if cmd.name.contains('/') {
        cmd.name.clone()
    } else {
        match look_path(&cmd.name) {
            Ok(p) => p,
            Err(e) => return (Err(e), out),
        }
    };
    if let Some(e) = ctx.err() {
        return (Err(ExecError::Ctx(e)), out);
    }
    if !cmd.dir.is_empty() {
        if let Err(e) = fs::metadata(&cmd.dir) {
            return (
                Err(ExecError::Start(oserr::path_err("chdir", &cmd.dir, &e))),
                out,
            );
        }
    }
    let mut c = Command::new(&path);
    c.arg0(&cmd.name).args(&cmd.args);
    if !cmd.dir.is_empty() {
        c.current_dir(&cmd.dir);
    }
    if let Some(env) = &cmd.env {
        c.env_clear();
        for kv in env {
            if let Some((k, v)) = kv.split_once('=') {
                if !k.is_empty() {
                    c.env(k, v);
                }
            }
        }
    }
    let setup = (|| -> io::Result<()> {
        c.stdin(stdio_for(cmd.stdin)?);
        c.stdout(stdio_for(cmd.stdout)?);
        c.stderr(stdio_for(cmd.stderr)?);
        Ok(())
    })();
    if let Err(e) = setup {
        return (Err(ExecError::Start(e.to_string())), out);
    }
    let mut child = match c.spawn() {
        Ok(ch) => ch,
        Err(e) => {
            return (
                Err(ExecError::Start(oserr::path_err("fork/exec", &path, &e))),
                out,
            )
        }
    };
    let stdout_reader = child.stdout.take().map(|mut s| {
        thread::spawn(move || {
            let mut b = Vec::new();
            let _ = s.read_to_end(&mut b);
            b
        })
    });
    let stderr_reader = child.stderr.take().map(|mut s| {
        thread::spawn(move || {
            let mut b = Vec::new();
            let _ = s.read_to_end(&mut b);
            b
        })
    });
    let status = if ctx.cancellable() {
        let mut killed = false;
        let mut pause = Duration::from_millis(1);
        loop {
            match child.try_wait() {
                Ok(Some(st)) => break Ok(st),
                Ok(None) => {}
                Err(e) => break Err(e),
            }
            if !killed && ctx.err().is_some() {
                let _ = child.kill();
                killed = true;
            }
            thread::sleep(pause);
            pause = (pause * 2).min(Duration::from_millis(20));
        }
    } else {
        child.wait()
    };
    if let Some(h) = stdout_reader {
        out.stdout = h.join().unwrap_or_default();
    }
    if let Some(h) = stderr_reader {
        out.stderr = h.join().unwrap_or_default();
    }
    match status {
        Ok(st) => (status_result(st), out),
        Err(e) => (Err(ExecError::Start(e.to_string())), out),
    }
}

/// `strings.TrimSpace` over captured bytes.
pub fn trim_space(b: &[u8]) -> String {
    String::from_utf8_lossy(b)
        .trim_matches(go_space)
        .to_string()
}

/// The characters `strings.TrimSpace` removes (Unicode White_Space).
pub fn go_space(c: char) -> bool {
    matches!(
        c,
        '\t' | '\n' | '\x0b' | '\x0c' | '\r' | ' ' | '\u{85}' | '\u{a0}' | '\u{1680}' | '\u{2000}'
            ..='\u{200a}' | '\u{2028}' | '\u{2029}' | '\u{202f}' | '\u{205f}' | '\u{3000}'
    )
}

/// `strings.TrimSpace`.
pub fn go_trim(s: &str) -> &str {
    s.trim_matches(go_space)
}

/// Write to stderr, ignoring failures, as `fmt.Fprint(os.Stderr, ...)` does.
pub fn eprint(s: &str) {
    let _ = io::stderr().write_all(s.as_bytes());
}

/// Write to stdout, ignoring failures.
pub fn print(s: &str) {
    let mut o = io::stdout().lock();
    let _ = o.write_all(s.as_bytes());
    let _ = o.flush();
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn errors_read_like_go() {
        assert_eq!(ExecError::ExitCode(3).to_string(), "exit status 3");
        assert_eq!(
            ExecError::Signal {
                sig: 9,
                core: false
            }
            .to_string(),
            "signal: killed"
        );
        assert_eq!(
            ExecError::NotFound("bazel".into()).to_string(),
            "exec: \"bazel\": executable file not found in $PATH"
        );
    }

    #[test]
    fn runs_and_captures() {
        let mut c = Cmd::new("sh", &["-c", "echo out; echo err >&2; exit 3"]);
        c.stdout = Io::Capture;
        c.stderr = Io::Capture;
        let (r, o) = run(&c, &Ctx::background());
        assert_eq!(r, Err(ExecError::ExitCode(3)));
        assert_eq!(o.stdout, b"out\n");
        assert_eq!(o.stderr, b"err\n");
    }

    #[test]
    fn expired_context_never_starts() {
        let c = Cmd::new("true", &[]);
        let (r, _) = run(&c, &Ctx::with_timeout_secs(0));
        assert_eq!(r, Err(ExecError::Ctx("context deadline exceeded")));
    }

    #[test]
    fn missing_program_and_dir() {
        let (r, _) = run(&Cmd::new("no-such-program-xyz", &[]), &Ctx::background());
        assert_eq!(
            r.unwrap_err().to_string(),
            "exec: \"no-such-program-xyz\": executable file not found in $PATH"
        );
        let mut c = Cmd::new("true", &[]);
        c.dir = "/no/such/dir".into();
        let (r, _) = run(&c, &Ctx::background());
        assert_eq!(
            r.unwrap_err().to_string(),
            "chdir /no/such/dir: no such file or directory"
        );
    }
}
