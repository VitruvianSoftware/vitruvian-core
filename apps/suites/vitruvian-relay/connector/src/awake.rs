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

//! Keeps the Mac from sleeping while `vrelay run` is up, so a call from the
//! AI app does not hit a sleeping machine. It runs
//! `/usr/bin/caffeinate -is -w <vrelay's pid>`: `-i` and `-s` hold off idle
//! sleep (and system sleep on power), and `-w` makes caffeinate quit by
//! itself when vrelay does, even if vrelay is killed. The screen may still
//! sleep. The `keep_awake` rule turns it on and off.

use std::path::PathBuf;
use std::process::{Child, Command, Stdio};
use std::sync::Mutex;

use crate::Result;

/// The system's own caffeinate.
pub const CAFFEINATE: &str = "/usr/bin/caffeinate";

pub struct Awake {
    /// What to run; a test points it at a fake.
    binary: PathBuf,
    child: Mutex<Option<Child>>,
}

impl Awake {
    /// Not running yet; [`Awake::set`] starts it.
    pub fn new(binary: impl Into<PathBuf>) -> Awake {
        Awake {
            binary: binary.into(),
            child: Mutex::new(None),
        }
    }

    /// With the system's caffeinate.
    pub fn system() -> Awake {
        Awake::new(CAFFEINATE)
    }

    /// Starts or stops holding the Mac awake. Asking for what is already so
    /// does nothing, except that a caffeinate that has died is started again.
    pub fn set(&self, on: bool) -> Result<()> {
        let mut slot = self.child.lock().unwrap();
        if !on {
            if let Some(mut c) = slot.take() {
                let _ = c.kill();
                let _ = c.wait();
            }
            return Ok(());
        }
        if running(&mut slot) {
            return Ok(());
        }
        let child = Command::new(&self.binary)
            .args(["-is", "-w", &std::process::id().to_string()])
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .map_err(|e| {
                format!(
                    "could not keep this Mac awake ({}): {e}; set keep_awake = false \
                     in rules.toml to stop trying",
                    self.binary.display()
                )
            })?;
        *slot = Some(child);
        Ok(())
    }

    /// True while caffeinate is running.
    pub fn is_on(&self) -> bool {
        running(&mut self.child.lock().unwrap())
    }
}

/// Whether the child in `slot` is still alive (reaping it if it is not).
fn running(slot: &mut Option<Child>) -> bool {
    match slot {
        Some(c) => match c.try_wait() {
            Ok(None) => true,
            _ => {
                *slot = None;
                false
            }
        },
        None => false,
    }
}

impl Drop for Awake {
    fn drop(&mut self) {
        if let Some(mut c) = self.child.get_mut().unwrap().take() {
            let _ = c.kill();
            let _ = c.wait();
        }
    }
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use crate::state::test_dir;
    use std::os::unix::fs::PermissionsExt;
    use std::path::Path;
    use std::time::{Duration, Instant};

    /// A stand-in for caffeinate: records its arguments and its pid, then
    /// waits like the real one. Each file is written whole to a temporary
    /// name and renamed, so a test that sees the file sees all of it (a
    /// plain `>` creates it empty first, and a test reading in that moment
    /// got no pid).
    pub(crate) fn fake_caffeinate(dir: &Path) -> PathBuf {
        std::fs::create_dir_all(dir).unwrap();
        let bin = dir.join("caffeinate");
        std::fs::write(
            &bin,
            format!(
                "#!/bin/sh\necho $$ > '{pid}.tmp' && mv '{pid}.tmp' '{pid}'\n\
                 printf '%s\\n' \"$@\" > '{args}.tmp' && mv '{args}.tmp' '{args}'\n\
                 exec sleep 60\n",
                pid = dir.join("pid").display(),
                args = dir.join("args").display(),
            ),
        )
        .unwrap();
        std::fs::set_permissions(&bin, std::fs::Permissions::from_mode(0o755)).unwrap();
        bin
    }

    /// `set(true)`, tried again while another thread's fork still holds the
    /// script open for writing (ETXTBSY, a test-only hazard).
    pub(crate) fn start_awake(a: &Awake) {
        for _ in 0..50 {
            match a.set(true) {
                Ok(()) => return,
                Err(e) if e.contains("busy") => std::thread::sleep(Duration::from_millis(50)),
                Err(e) => panic!("{e}"),
            }
        }
        panic!("the fake caffeinate stayed busy");
    }

    pub(crate) fn wait_for(what: &str, f: impl Fn() -> bool) {
        let end = Instant::now() + Duration::from_secs(10);
        while !f() {
            assert!(Instant::now() < end, "timed out waiting for {what}");
            std::thread::sleep(Duration::from_millis(10));
        }
    }

    fn alive(pid: i32) -> bool {
        // SAFETY: signal 0 only checks that the process exists.
        unsafe { libc::kill(pid, 0) == 0 }
    }

    #[test]
    fn keep_awake_starts_caffeinate_and_stops_it() {
        let dir = test_dir("awake");
        let awake = Awake::new(fake_caffeinate(&dir));
        assert!(!awake.is_on());
        start_awake(&awake);
        assert!(awake.is_on());
        let args = dir.join("args");
        wait_for("the arguments", || {
            std::fs::read_to_string(&args).is_ok_and(|s| s.ends_with('\n'))
        });
        assert_eq!(
            std::fs::read_to_string(&args).unwrap(),
            format!("-is\n-w\n{}\n", std::process::id())
        );
        let pid: i32 = std::fs::read_to_string(dir.join("pid"))
            .unwrap()
            .trim()
            .parse()
            .unwrap();
        assert!(alive(pid));
        // Asking again changes nothing: the same process.
        awake.set(true).unwrap();
        assert!(alive(pid));
        // The setting flipped and reloaded: it stops.
        awake.set(false).unwrap();
        assert!(!awake.is_on());
        wait_for("caffeinate to stop", || !alive(pid));
        // And back on: a new one.
        start_awake(&awake);
        assert!(awake.is_on());
    }

    #[test]
    fn dropping_it_stops_caffeinate() {
        let dir = test_dir("awake-drop");
        let awake = Awake::new(fake_caffeinate(&dir));
        start_awake(&awake);
        wait_for("the pid", || dir.join("pid").exists());
        let pid: i32 = std::fs::read_to_string(dir.join("pid"))
            .unwrap()
            .trim()
            .parse()
            .unwrap();
        drop(awake);
        wait_for("caffeinate to stop", || !alive(pid));
    }

    #[test]
    fn a_caffeinate_that_cannot_start_is_an_error_not_a_crash() {
        let awake = Awake::new("/nonexistent/caffeinate");
        let e = awake.set(true).unwrap_err();
        assert!(e.contains("could not keep this Mac awake"), "{e}");
        assert!(e.contains("set keep_awake = false in rules.toml"), "{e}");
        assert!(!awake.is_on());
        awake.set(false).unwrap();
    }

    #[test]
    fn a_caffeinate_that_died_is_started_again() {
        let dir = test_dir("awake-died");
        let awake = Awake::new(fake_caffeinate(&dir));
        start_awake(&awake);
        wait_for("the pid", || dir.join("pid").exists());
        let pid: i32 = std::fs::read_to_string(dir.join("pid"))
            .unwrap()
            .trim()
            .parse()
            .unwrap();
        // SAFETY: a plain signal to the fake we started.
        unsafe { libc::kill(pid, libc::SIGKILL) };
        wait_for("it to be seen as off", || !awake.is_on());
        let _ = std::fs::remove_file(dir.join("pid"));
        start_awake(&awake);
        wait_for("the new pid", || dir.join("pid").exists());
        assert!(awake.is_on());
    }
}
