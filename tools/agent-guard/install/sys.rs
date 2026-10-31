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

//! What install.py got from the interpreter: its environment, where it runs
//! from, stdout and stderr, subprocesses with a timeout, temporary folders,
//! and OSError's wording.

use std::cell::RefCell;
use std::collections::BTreeMap;
use std::ffi::OsString;
use std::io::{Read, Write};
use std::os::unix::fs::DirBuilderExt;
use std::os::unix::process::ExitStatusExt;
use std::process::{Command, Stdio};
use std::sync::mpsc;
use std::time::{Duration, Instant};

use agent_guard::paths::{abspath, isdir, join};
use agent_guard::pyutil::py_repr_str;

/// Where output goes: the real stdout/stderr, or one buffer (the tests').
pub enum Sink {
    Real,
    /// Built by the tests only.
    #[cfg_attr(not(test), allow(dead_code))]
    Buffer(RefCell<String>),
}

/// A replacement for write_atomic, as a test installs one: Some(error) to fail a write.
pub type WriteHook = Box<dyn Fn(&str, &str) -> Option<String>>;

/// The process state install.py read from the interpreter, as one value so a
/// test can give each run its own (Rust tests share one process environment).
pub struct Ctx {
    /// `os.environ`.
    pub env: BTreeMap<OsString, OsString>,
    /// Where this installer runs from (`current_exe`).
    pub running_from: String,
    pub sink: Sink,
    pub write_hook: Option<WriteHook>,
}

impl Ctx {
    pub fn real() -> Ctx {
        let running_from = std::env::current_exe()
            .map(|p| abspath(&p.to_string_lossy()))
            .unwrap_or_default();
        Ctx {
            env: std::env::vars_os().collect(),
            running_from,
            sink: Sink::Real,
            write_hook: None,
        }
    }

    pub fn var(&self, name: &str) -> Option<String> {
        self.env
            .get(&OsString::from(name))
            .map(|v| v.to_string_lossy().into_owned())
    }

    /// `print(text)`.
    pub fn print(&self, text: &str) {
        match &self.sink {
            Sink::Real => {
                let mut out = std::io::stdout().lock();
                let _ = out.write_all(text.as_bytes());
                let _ = out.write_all(b"\n");
                let _ = out.flush();
            }
            Sink::Buffer(b) => {
                b.borrow_mut().push_str(text);
                b.borrow_mut().push('\n');
            }
        }
    }

    /// `sys.stderr.write(text)`.
    pub fn eprint(&self, text: &str) {
        match &self.sink {
            Sink::Real => {
                let _ = std::io::stderr().lock().write_all(text.as_bytes());
            }
            Sink::Buffer(b) => b.borrow_mut().push_str(text),
        }
    }

    /// `os.path.expanduser("~")`.
    pub fn home(&self) -> String {
        match self.var("HOME") {
            Some(h) => {
                let h = h.trim_end_matches('/');
                if h.is_empty() {
                    "/".into()
                } else {
                    h.to_string()
                }
            }
            None => agent_guard::paths::home_dir(),
        }
    }

    /// `tempfile.gettempdir()`.
    pub fn tempdir(&self) -> String {
        for name in ["TMPDIR", "TEMP", "TMP"] {
            if let Some(d) = self.var(name) {
                if !d.is_empty() && isdir(&d) {
                    return abspath(&d);
                }
            }
        }
        for d in ["/tmp", "/var/tmp", "/usr/tmp"] {
            if isdir(d) {
                return d.to_string();
            }
        }
        agent_guard::paths::getcwd()
    }
}

/// `tempfile.mkdtemp(prefix=prefix, dir=dir)`.
pub fn mkdtemp(dir: &str, prefix: &str) -> Result<String, String> {
    use std::collections::hash_map::RandomState;
    use std::hash::{BuildHasher, Hasher};
    const LETTERS: &[u8] = b"abcdefghijklmnopqrstuvwxyz0123456789_";
    for _ in 0..100 {
        let mut h = RandomState::new().build_hasher();
        h.write_u128(
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_nanos(),
        );
        let mut bits = h.finish();
        let name: String = (0..8)
            .map(|_| {
                let c = LETTERS[(bits % LETTERS.len() as u64) as usize] as char;
                bits /= LETTERS.len() as u64;
                c
            })
            .collect();
        let path = join(dir, &format!("{}{}", prefix, name));
        match std::fs::DirBuilder::new().mode(0o700).create(&path) {
            Ok(()) => return Ok(abspath(&path)),
            Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => continue,
            Err(e) => return Err(oserror(&e, &path, None)),
        }
    }
    Err(format!(
        "[Errno 17] No usable temporary directory name found: {}",
        py_repr_str(dir)
    ))
}

/// `str(OSError)` as Python words it: `[Errno N] strerror: 'file'`.
pub fn oserror(e: &std::io::Error, file: &str, file2: Option<&str>) -> String {
    let Some(code) = e.raw_os_error() else {
        return e.to_string();
    };
    let text = e.to_string();
    let strerror = match text.rfind(" (os error ") {
        Some(i) => text[..i].to_string(),
        None => text,
    };
    match file2 {
        Some(f2) => format!(
            "[Errno {}] {}: {} -> {}",
            code,
            strerror,
            py_repr_str(file),
            py_repr_str(f2)
        ),
        None => format!("[Errno {}] {}: {}", code, strerror, py_repr_str(file)),
    }
}

/// The exception class Python raises for an OSError with this errno.
pub fn oserror_kind(e: &std::io::Error) -> &'static str {
    match e.raw_os_error() {
        Some(2) => "FileNotFoundError",
        Some(13) | Some(1) => "PermissionError",
        Some(17) => "FileExistsError",
        Some(20) => "NotADirectoryError",
        Some(21) => "IsADirectoryError",
        _ => "OSError",
    }
}

pub struct Ran {
    /// The exit status, negative for a signal (Popen.returncode).
    pub code: i32,
    pub stdout: Vec<u8>,
    pub stderr: Vec<u8>,
}

pub enum RunErr {
    /// subprocess.TimeoutExpired
    Timeout,
    /// OSError starting it: (str(exc), its class)
    Os(String, &'static str),
}

/// `subprocess.run(argv, input=input, stdout=PIPE, stderr=PIPE, cwd=cwd, env=env, timeout=timeout)`.
pub fn run(
    mut cmd: Command,
    program: &str,
    input: Option<Vec<u8>>,
    timeout: Duration,
) -> Result<Ran, RunErr> {
    cmd.stdin(if input.is_some() {
        Stdio::piped()
    } else {
        Stdio::inherit()
    })
    .stdout(Stdio::piped())
    .stderr(Stdio::piped());
    let mut child = match cmd.spawn() {
        Ok(c) => c,
        Err(e) => return Err(RunErr::Os(oserror(&e, program, None), oserror_kind(&e))),
    };
    if let (Some(data), Some(mut stdin)) = (input, child.stdin.take()) {
        std::thread::spawn(move || {
            let _ = stdin.write_all(&data);
        });
    }
    let (tx, rx) = mpsc::channel::<(bool, Vec<u8>)>();
    for (is_out, pipe) in [
        (
            true,
            child
                .stdout
                .take()
                .map(|p| Box::new(p) as Box<dyn Read + Send>),
        ),
        (
            false,
            child
                .stderr
                .take()
                .map(|p| Box::new(p) as Box<dyn Read + Send>),
        ),
    ] {
        let tx = tx.clone();
        std::thread::spawn(move || {
            let mut buf = Vec::new();
            if let Some(mut p) = pipe {
                let _ = p.read_to_end(&mut buf);
            }
            let _ = tx.send((is_out, buf));
        });
    }
    drop(tx);
    let deadline = Instant::now() + timeout;
    let (mut stdout, mut stderr) = (None, None);
    let mut status = None;
    while stdout.is_none() || stderr.is_none() || status.is_none() {
        let left = deadline.saturating_duration_since(Instant::now());
        if left.is_zero() {
            let _ = child.kill();
            let _ = child.wait();
            return Err(RunErr::Timeout);
        }
        if stdout.is_none() || stderr.is_none() {
            match rx.recv_timeout(left.min(Duration::from_millis(20))) {
                Ok((true, b)) => stdout = Some(b),
                Ok((false, b)) => stderr = Some(b),
                Err(_) => {}
            }
        }
        if status.is_none() {
            match child.try_wait() {
                Ok(Some(s)) => status = Some(s),
                Ok(None) => {
                    if stdout.is_some() && stderr.is_some() {
                        std::thread::sleep(Duration::from_millis(2));
                    }
                }
                Err(_) => status = child.wait().ok(),
            }
        }
    }
    let status = status.unwrap();
    let code = status
        .code()
        .unwrap_or_else(|| -status.signal().unwrap_or(0));
    Ok(Ran {
        code,
        stdout: stdout.unwrap_or_default(),
        stderr: stderr.unwrap_or_default(),
    })
}

/// A Command running with exactly `env`.
pub fn command_with_env(program: &str, env: &BTreeMap<OsString, OsString>) -> Command {
    let mut cmd = Command::new(program);
    cmd.env_clear();
    cmd.envs(env.iter());
    cmd
}

/// `shutil.get_terminal_size().columns`.
pub fn terminal_columns(ctx: &Ctx) -> usize {
    if let Some(c) = ctx.var("COLUMNS") {
        if let Ok(n) = c.trim().parse::<i64>() {
            if n > 0 {
                return n as usize;
            }
        }
    }
    if let Sink::Buffer(_) = ctx.sink {
        return 80;
    }
    tty_columns().unwrap_or(80)
}

#[repr(C)]
struct WinSize {
    rows: u16,
    cols: u16,
    xpixel: u16,
    ypixel: u16,
}

extern "C" {
    fn ioctl(fd: i32, request: std::os::raw::c_ulong, ...) -> i32;
}

#[cfg(target_os = "macos")]
const TIOCGWINSZ: std::os::raw::c_ulong = 0x4008_7468;
#[cfg(not(target_os = "macos"))]
const TIOCGWINSZ: std::os::raw::c_ulong = 0x5413;

fn tty_columns() -> Option<usize> {
    let mut ws = WinSize {
        rows: 0,
        cols: 0,
        xpixel: 0,
        ypixel: 0,
    };
    // SAFETY: TIOCGWINSZ writes one winsize into the struct we pass.
    let rc = unsafe { ioctl(1, TIOCGWINSZ, &mut ws as *mut WinSize) };
    if rc == 0 && ws.cols > 0 {
        Some(ws.cols as usize)
    } else {
        None
    }
}
