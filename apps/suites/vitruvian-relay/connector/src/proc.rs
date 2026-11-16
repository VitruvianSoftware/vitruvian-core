// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

//! Running a short helper command (`node --version`, the installer's search
//! check) with a time limit. It runs in its own process group, and whatever
//! it started dies with it: on time-out, and also once it exits, so a child
//! left holding its output pipe cannot hang the caller.

use std::io::Read;
use std::os::unix::process::CommandExt;
use std::process::{Command, Output, Stdio};
use std::time::{Duration, Instant};

/// `cmd`'s output, or `None` if it did not exit within `timeout` (it and its
/// group are then killed). At most `limit` bytes of each stream are kept.
/// stdin is closed. An error only if it cannot be started.
pub fn output_within(
    cmd: &mut Command,
    timeout: Duration,
    limit: u64,
) -> std::io::Result<Option<Output>> {
    let mut child = cmd
        .process_group(0)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()?;
    let pid = child.id() as i32;
    let drain = |r: Option<Box<dyn Read + Send>>| {
        std::thread::spawn(move || {
            let mut buf = Vec::new();
            if let Some(r) = r {
                let _ = r.take(limit).read_to_end(&mut buf);
            }
            buf
        })
    };
    let out = drain(
        child
            .stdout
            .take()
            .map(|r| Box::new(r) as Box<dyn Read + Send>),
    );
    let err = drain(
        child
            .stderr
            .take()
            .map(|r| Box::new(r) as Box<dyn Read + Send>),
    );
    let deadline = Instant::now() + timeout;
    let exited = loop {
        if leader_exited(pid) {
            break true;
        }
        if Instant::now() >= deadline {
            break false;
        }
        std::thread::sleep(Duration::from_millis(10));
    };
    // The leader is not reaped yet (an exited one is a zombie), so its
    // process group id cannot have been reused: kill whatever is left in it,
    // which also closes any pipe a child kept open.
    if pid > 1 {
        // SAFETY: a plain syscall on a group we created.
        unsafe {
            libc::kill(-pid, libc::SIGKILL);
        }
    }
    let status = child.wait()?;
    let stdout = out.join().unwrap_or_default();
    let stderr = err.join().unwrap_or_default();
    Ok(exited.then_some(Output {
        status,
        stdout,
        stderr,
    }))
}

/// Has `pid` exited? `waitid(WNOWAIT)` reports it but leaves the zombie,
/// so the group stays ours to kill. Interrupted by a signal (another
/// child's `SIGCHLD`, common when many run at once), it asks again;
/// `ECHILD` (someone else reaped it) counts as exited; any other error as
/// still running, so the time limit, not a hasty kill, decides.
fn leader_exited(pid: i32) -> bool {
    loop {
        // SAFETY: `info` is plain zeroed memory that waitid fills in.
        let (ret, si_pid) = unsafe {
            let mut info: libc::siginfo_t = std::mem::zeroed();
            let ret = libc::waitid(
                libc::P_PID,
                pid as libc::id_t,
                &mut info,
                libc::WEXITED | libc::WNOHANG | libc::WNOWAIT,
            );
            #[cfg(target_os = "macos")]
            let si_pid = info.si_pid;
            #[cfg(not(target_os = "macos"))]
            let si_pid = info.si_pid();
            (ret, si_pid)
        };
        if ret == 0 {
            return si_pid != 0;
        }
        match std::io::Error::last_os_error().raw_os_error() {
            Some(libc::EINTR) => continue,
            Some(libc::ECHILD) => return true,
            _ => return false,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::state::test_dir;
    use std::os::unix::fs::PermissionsExt;
    use std::time::Instant;

    fn script(dir: &std::path::Path, body: &str) -> std::path::PathBuf {
        std::fs::create_dir_all(dir).unwrap();
        let p = dir.join("s.sh");
        std::fs::write(&p, format!("#!/bin/sh\n{body}\n")).unwrap();
        std::fs::set_permissions(&p, std::fs::Permissions::from_mode(0o755)).unwrap();
        p
    }

    fn gone_soon(pid: i32) -> bool {
        let until = Instant::now() + Duration::from_secs(3);
        while Instant::now() < until {
            // SAFETY: signal 0 only checks the pid exists.
            if unsafe { libc::kill(pid, 0) } != 0 {
                return true;
            }
            std::thread::sleep(Duration::from_millis(20));
        }
        false
    }

    #[test]
    fn output_and_status_come_back() {
        let s = script(&test_dir("proc-out"), "echo out; echo err >&2; exit 3");
        let o = output_within(&mut Command::new(&s), Duration::from_secs(10), 1024)
            .unwrap()
            .unwrap();
        assert_eq!(o.status.code(), Some(3));
        assert_eq!(o.stdout, b"out\n");
        assert_eq!(o.stderr, b"err\n");
    }

    #[test]
    fn output_is_capped() {
        let s = script(&test_dir("proc-cap"), "echo 0123456789");
        let o = output_within(&mut Command::new(&s), Duration::from_secs(10), 4)
            .unwrap()
            .unwrap();
        assert_eq!(o.stdout, b"0123");
    }

    #[test]
    fn a_hang_is_cut_off_with_its_children() {
        let dir = test_dir("proc-hang");
        let s = script(
            &dir,
            "sleep 30 &\necho $! > \"$(dirname \"$0\")/child\"\nsleep 30",
        );
        let t = Instant::now();
        let o = output_within(&mut Command::new(&s), Duration::from_secs(4), 1024).unwrap();
        assert!(o.is_none());
        // Cut off near the limit, not after the script's 30 s.
        assert!(t.elapsed() < Duration::from_secs(15), "{:?}", t.elapsed());
        let child: i32 = std::fs::read_to_string(dir.join("child"))
            .unwrap()
            .trim()
            .parse()
            .unwrap();
        assert!(gone_soon(child));
    }

    #[test]
    fn a_child_left_holding_the_pipe_does_not_hang_it() {
        let dir = test_dir("proc-linger");
        // Exits at once, but its child keeps stdout open for 30 s.
        let s = script(
            &dir,
            "sleep 30 &\necho $! > \"$(dirname \"$0\")/child\"\necho done",
        );
        let t = Instant::now();
        let o = output_within(&mut Command::new(&s), Duration::from_secs(20), 1024)
            .unwrap()
            .unwrap();
        assert!(t.elapsed() < Duration::from_secs(5), "{:?}", t.elapsed());
        assert!(o.status.success());
        assert_eq!(o.stdout, b"done\n");
        let child: i32 = std::fs::read_to_string(dir.join("child"))
            .unwrap()
            .trim()
            .parse()
            .unwrap();
        assert!(gone_soon(child));
    }

    #[test]
    fn a_missing_command_is_an_error() {
        assert!(output_within(
            &mut Command::new("/nonexistent/x"),
            Duration::from_secs(1),
            10
        )
        .is_err());
    }
}
