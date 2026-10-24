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

//! Everything adb-connect asks of the operating system, behind one trait
//! so the logic can be tested against scripted `adb`, `dns-sd` and
//! `tailscale` output.
//!
//! [`RealSystem`] reproduces what the Python tool's subprocess calls do:
//! `run_command` (`subprocess.run(..., capture_output=True, text=True,
//! timeout=...)`, 124 on timeout, 127 when the program is missing) and the
//! `dns-sd` pattern (`Popen`, `time.sleep`, `terminate()` = SIGTERM,
//! `communicate()`), including text-mode decoding (strict UTF-8, universal
//! newlines).

use crate::py::{raise, repr_str, universal_newlines, utf8_error};
use std::io::{ErrorKind, Read};
use std::net::{IpAddr, ToSocketAddrs};
use std::process::{Child, Command, Stdio};
use std::sync::mpsc;
use std::time::{Duration, Instant};

/// Skips the fixed mDNS waits and lets each `dns-sd` exit on its own
/// instead of being signalled. Only for tests that drive the binary with
/// scripted `dns-sd` stand-ins that print and exit; set to `1`.
pub const SKIP_MDNS_WAIT_ENV: &str = "ADB_CONNECT_RS_SKIP_MDNS_WAIT";

/// A `dns-sd` started in the background.
pub trait Pending {
    /// `proc.terminate(); stdout, _ = proc.communicate()`; None where the
    /// Python code's `except Exception` would swallow an error.
    fn finish(self: Box<Self>) -> Option<String>;
}

pub trait System {
    /// `run_command(cmd, timeout)`: `(exit code, stdout, stderr)`.
    fn run(&self, cmd: &[&str], timeout: Option<f64>) -> (i32, String, String);
    /// `subprocess.Popen(cmd, stdout=PIPE, stderr=PIPE, text=True)`, or
    /// None when that raises.
    fn spawn(&self, cmd: &[&str]) -> Option<Box<dyn Pending>>;
    /// `time.sleep(secs)` for a valid duration (see [`check_sleep`]).
    fn sleep(&self, secs: f64);
    /// `socket.gethostbyname(host)`, or None when it raises.
    fn gethostbyname(&self, host: &str) -> Option<String>;
}

/// Why `time.sleep(secs)` would raise, as `(exception, message)`.
pub fn check_sleep(secs: f64) -> Result<(), (&'static str, &'static str)> {
    if secs.is_nan() {
        Err(("ValueError", "Invalid value NaN (not a number)"))
    } else if secs < 0.0 {
        Err(("ValueError", "sleep length must be non-negative"))
    } else if secs > 9_223_372_036.854_775 {
        Err((
            "OverflowError",
            "timestamp too large to convert to C _PyTime_t",
        ))
    } else {
        Ok(())
    }
}

/// `time.sleep(secs)` where the Python code does not catch its errors.
pub fn sleep_or_raise(sys: &dyn System, secs: f64) {
    if let Err((kind, msg)) = check_sleep(secs) {
        raise(kind, msg);
    }
    sys.sleep(secs);
}

/// `time.sleep(secs)` inside a Python `try: ... except Exception:`;
/// false when it would have raised.
pub fn sleep_or_fail(sys: &dyn System, secs: f64) -> bool {
    if check_sleep(secs).is_err() {
        return false;
    }
    sys.sleep(secs);
    true
}

/// Text-mode decoding of child output: strict UTF-8 then universal
/// newlines. None means Python would raise UnicodeDecodeError.
pub fn decode_text(bytes: &[u8]) -> Option<String> {
    std::str::from_utf8(bytes).ok().map(universal_newlines)
}

/// The real system.
pub struct RealSystem {
    skip_mdns_wait: bool,
}

impl RealSystem {
    pub fn from_env() -> Self {
        RealSystem {
            skip_mdns_wait: std::env::var(SKIP_MDNS_WAIT_ENV).map_or(false, |v| v == "1"),
        }
    }
}

extern "C" {
    fn kill(pid: i32, sig: i32) -> i32;
}

const SIGTERM: i32 = 15;

fn terminate(child: &mut Child) {
    if matches!(child.try_wait(), Ok(None)) {
        if let Ok(pid) = i32::try_from(child.id()) {
            // SAFETY: kill(2) on our own child's pid, which has not been
            // reaped (try_wait just reported it running).
            unsafe {
                kill(pid, SIGTERM);
            }
        }
    }
}

struct RealPending {
    child: Child,
    signal: bool,
}

impl Pending for RealPending {
    fn finish(mut self: Box<Self>) -> Option<String> {
        if self.signal {
            terminate(&mut self.child);
        }
        let out = self.child.wait_with_output().ok()?;
        // communicate() decodes stderr too; a decode error there raises.
        decode_text(&out.stderr)?;
        decode_text(&out.stdout)
    }
}

fn reader<R: Read + Send + 'static>(mut pipe: R, tx: mpsc::Sender<(u8, Vec<u8>)>, tag: u8) {
    std::thread::spawn(move || {
        let mut buf = Vec::new();
        let _ = pipe.read_to_end(&mut buf);
        let _ = tx.send((tag, buf));
    });
}

impl System for RealSystem {
    fn run(&self, cmd: &[&str], timeout: Option<f64>) -> (i32, String, String) {
        let spawned = Command::new(cmd[0])
            .args(&cmd[1..])
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn();
        let mut child = match spawned {
            Ok(c) => c,
            Err(e) if e.kind() == ErrorKind::NotFound => {
                return (
                    127,
                    String::new(),
                    format!("[Errno 2] No such file or directory: {}", repr_str(cmd[0])),
                );
            }
            Err(e) if e.kind() == ErrorKind::PermissionDenied => raise(
                "PermissionError",
                format!("[Errno 13] Permission denied: {}", repr_str(cmd[0])),
            ),
            Err(e) => raise("OSError", e.to_string()),
        };
        let (tx, rx) = mpsc::channel();
        reader(child.stdout.take().expect("piped stdout"), tx.clone(), 1);
        reader(child.stderr.take().expect("piped stderr"), tx, 2);
        let deadline = timeout.map(|t| Instant::now() + Duration::from_secs_f64(t.max(0.0)));
        let mut stdout = None;
        let mut stderr = None;
        let mut status = None;
        loop {
            while let Ok((tag, buf)) = rx.try_recv() {
                if tag == 1 {
                    stdout = Some(buf);
                } else {
                    stderr = Some(buf);
                }
            }
            if status.is_none() {
                if let Ok(Some(st)) = child.try_wait() {
                    status = Some(st);
                }
            }
            if stdout.is_some() && stderr.is_some() && status.is_some() {
                break;
            }
            if let Some(d) = deadline {
                if Instant::now() >= d {
                    // subprocess.run: kill() then wait(), output discarded.
                    let _ = child.kill();
                    let _ = child.wait();
                    return (124, String::new(), "Command timed out".into());
                }
            }
            std::thread::sleep(Duration::from_millis(2));
        }
        let status = status.expect("set before break");
        let code = match status.code() {
            Some(c) => c,
            None => {
                use std::os::unix::process::ExitStatusExt;
                -status.signal().unwrap_or(0)
            }
        };
        let decode = |b: Option<Vec<u8>>| {
            let bytes = b.unwrap_or_default();
            match decode_text(&bytes) {
                Some(t) => t,
                None => raise("UnicodeDecodeError", utf8_error(&bytes).unwrap_or_default()),
            }
        };
        let out = decode(stdout);
        let err = decode(stderr);
        (code, out, err)
    }

    fn spawn(&self, cmd: &[&str]) -> Option<Box<dyn Pending>> {
        let child = Command::new(cmd[0])
            .args(&cmd[1..])
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .ok()?;
        Some(Box::new(RealPending {
            child,
            signal: !self.skip_mdns_wait,
        }))
    }

    fn sleep(&self, secs: f64) {
        if !self.skip_mdns_wait && secs > 0.0 {
            std::thread::sleep(Duration::from_secs_f64(secs));
        }
    }

    fn gethostbyname(&self, host: &str) -> Option<String> {
        match host {
            "" => return Some("0.0.0.0".into()),
            "<broadcast>" => return Some("255.255.255.255".into()),
            _ => {}
        }
        if let Ok(IpAddr::V4(v4)) = host.parse::<IpAddr>() {
            return Some(v4.to_string());
        }
        (host, 0u16)
            .to_socket_addrs()
            .ok()?
            .find_map(|a| match a.ip() {
                IpAddr::V4(v4) => Some(v4.to_string()),
                IpAddr::V6(_) => None,
            })
    }
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

/// `os.get_terminal_size(1).columns`, None when stdout is not a terminal.
pub fn stdout_tty_columns() -> Option<u16> {
    let mut ws = WinSize {
        rows: 0,
        cols: 0,
        xpixel: 0,
        ypixel: 0,
    };
    // SAFETY: TIOCGWINSZ writes one `struct winsize` (four u16s, matching
    // WinSize's C layout) through the pointer, which outlives the call.
    let rc = unsafe { ioctl(1, TIOCGWINSZ, &mut ws as *mut WinSize) };
    if rc == 0 {
        Some(ws.cols)
    } else {
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn run_reports_missing_program_like_python() {
        let sys = RealSystem {
            skip_mdns_wait: false,
        };
        let (code, out, err) = sys.run(&["adb-connect-no-such-program"], Some(1.0));
        assert_eq!(code, 127);
        assert_eq!(out, "");
        assert_eq!(
            err,
            "[Errno 2] No such file or directory: 'adb-connect-no-such-program'"
        );
    }

    #[test]
    fn run_captures_output_and_exit_code() {
        let sys = RealSystem {
            skip_mdns_wait: false,
        };
        let (code, out, err) = sys.run(
            &["/bin/sh", "-c", "printf 'a\\r\\nb'; printf e >&2; exit 3"],
            Some(5.0),
        );
        assert_eq!((code, out.as_str(), err.as_str()), (3, "a\nb", "e"));
    }

    #[test]
    fn run_times_out_with_124() {
        let sys = RealSystem {
            skip_mdns_wait: false,
        };
        let started = Instant::now();
        let res = sys.run(&["/bin/sh", "-c", "exec sleep 5"], Some(0.2));
        assert_eq!(res, (124, String::new(), "Command timed out".to_string()));
        assert!(started.elapsed() < Duration::from_secs(3));
    }

    #[test]
    fn pending_is_terminated_and_its_output_kept() {
        let sys = RealSystem {
            skip_mdns_wait: false,
        };
        let started = Instant::now();
        let p = sys
            .spawn(&["/bin/sh", "-c", "echo browsing; exec sleep 30"])
            .expect("spawned");
        sys.sleep(0.2);
        assert_eq!(p.finish().as_deref(), Some("browsing\n"));
        assert!(started.elapsed() < Duration::from_secs(10));
        assert!(sys.spawn(&["adb-connect-no-such-program"]).is_none());
    }

    #[test]
    fn sleep_validation_matches_time_sleep() {
        assert!(check_sleep(0.0).is_ok());
        assert_eq!(
            check_sleep(-1.0).unwrap_err().1,
            "sleep length must be non-negative"
        );
        assert_eq!(check_sleep(f64::NAN).unwrap_err().0, "ValueError");
        assert_eq!(check_sleep(f64::INFINITY).unwrap_err().0, "OverflowError");
        assert_eq!(decode_text(b"\xff"), None);
    }

    #[test]
    fn gethostbyname_special_cases() {
        let sys = RealSystem {
            skip_mdns_wait: false,
        };
        assert_eq!(sys.gethostbyname("").as_deref(), Some("0.0.0.0"));
        assert_eq!(sys.gethostbyname("10.1.2.3").as_deref(), Some("10.1.2.3"));
        assert_eq!(sys.gethostbyname("localhost").as_deref(), Some("127.0.0.1"));
    }
}
