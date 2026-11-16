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
    output_within_using(cmd, timeout, limit, leader_state)
}

/// What a check on the leader found.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Leader {
    Running,
    /// Exited, its zombie still held: the group id is still ours.
    Exited,
    /// Reaped by someone else (`ECHILD`): its id may already be reused.
    Gone,
}

/// Checks the leader with `waitid(WNOWAIT)`, which reports an exit but
/// leaves the zombie, so the group id stays ours. Interrupted by a signal
/// (another child's `SIGCHLD`, common when many run at once), it asks again.
/// `ECHILD` means someone else reaped it: [`Leader::Gone`]. Any other error
/// counts as still running, so the time limit decides, and the leader is
/// still unreaped when the group is killed.
pub(crate) fn leader_state(pid: i32) -> Leader {
    leader_state_with(pid, waitid_nowait)
}

/// One `waitid(P_PID, pid, WEXITED | WNOHANG | WNOWAIT)`: the exited
/// child's pid (0 while it runs), or the error number.
pub(crate) type WaitId = fn(i32) -> std::result::Result<i32, i32>;

fn waitid_nowait(pid: i32) -> std::result::Result<i32, i32> {
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
        Ok(si_pid)
    } else {
        Err(std::io::Error::last_os_error()
            .raw_os_error()
            .unwrap_or(libc::EIO))
    }
}

/// [`leader_state`] with the system call given (tests stand in for an
/// interrupted one).
pub(crate) fn leader_state_with(pid: i32, waitid: WaitId) -> Leader {
    loop {
        match waitid(pid) {
            Ok(0) => return Leader::Running,
            Ok(_) => return Leader::Exited,
            Err(libc::EINTR) => continue,
            Err(libc::ECHILD) => return Leader::Gone,
            Err(_) => return Leader::Running,
        }
    }
}

/// Kills process group `pgid` (a leader we started with `process_group(0)`
/// and have not reaped), so a child holding a pipe dies with it. Only after
/// [`may_kill_group_after`] says the id is still ours.
pub(crate) fn kill_group(pgid: i32, sig: i32) {
    if pgid > 1 {
        // SAFETY: a plain syscall on a group we created; no memory is touched.
        unsafe {
            libc::kill(-pgid, sig);
        }
    }
}

/// The one rule, shared with the bridge's own wait (`bridge::wait_loop`):
/// only an exit seen with the zombie still held, or a leader not yet
/// reaped, makes the group id ours to signal. After an error the leader may
/// be gone and its id reused.
pub(crate) fn may_kill_group_after(waited: &std::io::Result<()>) -> bool {
    waited.is_ok()
}

/// [`output_within`] with the leader check given (tests stand in for a
/// leader someone else reaped).
pub(crate) fn output_within_using(
    cmd: &mut Command,
    timeout: Duration,
    limit: u64,
    check: fn(i32) -> Leader,
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
    // Ok(true): exited, held. Ok(false): timed out, still unreaped.
    // Err: gone, reaped elsewhere.
    let waited: std::io::Result<bool> = loop {
        match check(pid) {
            Leader::Exited => break Ok(true),
            Leader::Gone => {
                break Err(std::io::Error::other(format!(
                    "pid {pid} was reaped by someone else; not signalling its group"
                )))
            }
            Leader::Running if Instant::now() >= deadline => break Ok(false),
            Leader::Running => std::thread::sleep(Duration::from_millis(10)),
        }
    };
    let held = match &waited {
        Ok(_) => Ok(()),
        Err(_) => Err(std::io::Error::from_raw_os_error(libc::ECHILD)),
    };
    if may_kill_group_after(&held) {
        // Whatever is left in its group dies with it, which also closes any
        // pipe a child kept open.
        kill_group(pid, libc::SIGKILL);
    }
    let status = child.wait();
    // When gone, the drain threads are left: a child may still hold the pipe.
    let exited = waited?;
    let status = status?;
    let stdout = out.join().unwrap_or_default();
    let stderr = err.join().unwrap_or_default();
    Ok(exited.then_some(Output {
        status,
        stdout,
        stderr,
    }))
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
    /// A signal landing during the check (another child's `SIGCHLD`) makes
    /// waitid fail with `EINTR`: that is asked again, never read as an exit,
    /// a reap elsewhere or a run.
    #[test]
    fn an_interrupted_check_is_asked_again() {
        use std::sync::atomic::{AtomicU32, Ordering};
        static CALLS: AtomicU32 = AtomicU32::new(0);
        fn flaky(_: i32) -> std::result::Result<i32, i32> {
            match CALLS.fetch_add(1, Ordering::SeqCst) {
                0 | 1 => Err(libc::EINTR),
                _ => Ok(4242),
            }
        }
        assert_eq!(leader_state_with(99, flaky), Leader::Exited);
        assert_eq!(CALLS.load(Ordering::SeqCst), 3);
        assert_eq!(leader_state_with(99, |_| Ok(0)), Leader::Running);
        assert_eq!(leader_state_with(99, |_| Err(libc::ECHILD)), Leader::Gone);
        assert_eq!(leader_state_with(99, |_| Err(libc::EINVAL)), Leader::Running);
    }

    #[test]
    fn a_leader_reaped_elsewhere_is_gone() {
        // pid 1 is not our child: waitid fails with ECHILD.
        assert_eq!(leader_state(1), Leader::Gone);
        let gone = Err(std::io::Error::from_raw_os_error(libc::ECHILD));
        assert!(!may_kill_group_after(&gone));
        assert!(may_kill_group_after(&Ok(())));
    }

    #[test]
    fn a_gone_leader_never_gets_its_group_signalled() {
        let dir = test_dir("proc-gone");
        // Its child stays in the group; a group kill would end it.
        let s = script(
            &dir,
            "sleep 30 &\necho $! > \"$(dirname \"$0\")/child\"\nsleep 1",
        );
        let t = Instant::now();
        let r = output_within_using(&mut Command::new(&s), Duration::from_secs(20), 1024, |_| {
            Leader::Gone
        });
        assert!(r.is_err(), "{r:?}");
        assert!(t.elapsed() < Duration::from_secs(10), "{:?}", t.elapsed());
        let child: i32 = std::fs::read_to_string(dir.join("child"))
            .unwrap()
            .trim()
            .parse()
            .unwrap();
        // A killed child can linger a moment as a zombie: watch it for a
        // while rather than look once.
        let died = (0..25).any(|_| {
            std::thread::sleep(Duration::from_millis(20));
            // SAFETY: signal 0 only checks the pid exists.
            unsafe { libc::kill(child, 0) != 0 }
        });
        // SAFETY: our own test child.
        unsafe { libc::kill(child, libc::SIGKILL) };
        assert!(!died, "the group was signalled");
    }
}
