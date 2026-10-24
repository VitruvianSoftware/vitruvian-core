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

//! Git state (for in-progress merges, rebases and cherry-picks), and running
//! git with a time limit.

use std::io::{Read, Write};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

use crate::paths::{exists, join, normpath, nul_check, realpath};
use crate::pyutil::py_splitlines;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct GitState {
    pub merge: bool,
    pub rebase: bool,
    pub cherry_pick: bool,
    /// Absolute paths of conflicted files.
    pub unmerged: Vec<String>,
    pub primary: bool,
}

impl Default for GitState {
    fn default() -> Self {
        GitState {
            merge: false,
            rebase: false,
            cherry_pick: false,
            unmerged: vec![],
            primary: true,
        }
    }
}

impl GitState {
    pub fn in_progress(&self) -> bool {
        self.merge || self.rebase || self.cherry_pick
    }
}

/// Run a command; (exit success, stdout) or None if it could not run in time.
pub fn run_with_timeout(
    mut cmd: Command,
    input: Option<&[u8]>,
    timeout: Duration,
) -> Option<(bool, Vec<u8>)> {
    cmd.stdout(Stdio::piped()).stderr(Stdio::null());
    cmd.stdin(if input.is_some() {
        Stdio::piped()
    } else {
        Stdio::null()
    });
    let mut child = cmd.spawn().ok()?;
    if let Some(data) = input {
        let mut stdin = child.stdin.take()?;
        let data = data.to_vec();
        std::thread::spawn(move || {
            let _ = stdin.write_all(&data);
        });
    }
    let mut stdout = child.stdout.take()?;
    let reader = std::thread::spawn(move || {
        let mut buf = Vec::new();
        let _ = stdout.read_to_end(&mut buf);
        buf
    });
    let deadline = Instant::now() + timeout;
    let status = loop {
        match child.try_wait() {
            Ok(Some(s)) => break s,
            Ok(None) => {
                if Instant::now() >= deadline {
                    let _ = child.kill();
                    let _ = child.wait();
                    return None;
                }
                std::thread::sleep(Duration::from_millis(2));
            }
            Err(_) => return None,
        }
    };
    let out = reader.join().ok()?;
    Some((status.success(), out))
}

fn git(cwd: &str, args: &[String]) -> Option<String> {
    // Python's subprocess refuses an argument with a NUL byte (ValueError).
    nul_check(cwd);
    let mut cmd = Command::new("git");
    cmd.arg("-C")
        .arg(cwd)
        .args(args)
        .env("GIT_OPTIONAL_LOCKS", "0");
    let (ok, out) = run_with_timeout(cmd, None, Duration::from_secs(3))?;
    if !ok {
        return None;
    }
    Some(String::from_utf8_lossy(&out).into_owned())
}

/// Ask git where its state files live (worktree aware) and which exist.
pub fn probe_git_state(cwd: &str) -> GitState {
    let names = [
        "MERGE_HEAD",
        "REBASE_HEAD",
        "rebase-merge",
        "rebase-apply",
        "CHERRY_PICK_HEAD",
    ];
    let mut args: Vec<String> = [
        "rev-parse",
        "--path-format=absolute",
        "--show-toplevel",
        "--git-dir",
        "--git-common-dir",
    ]
    .iter()
    .map(|s| s.to_string())
    .collect();
    for n in names {
        args.push("--git-path".into());
        args.push(n.into());
    }
    let Some(out) = git(cwd, &args) else {
        return GitState::default();
    };
    let lines = py_splitlines(&out);
    if lines.len() < 3 + names.len() {
        return GitState::default();
    }
    let (top, git_dir, common) = (&lines[0], &lines[1], &lines[2]);
    let path = |k: usize| &lines[3 + k];
    let mut st = GitState {
        merge: exists(path(0)),
        rebase: exists(path(1)) || exists(path(2)) || exists(path(3)),
        cherry_pick: exists(path(4)),
        unmerged: vec![],
        primary: normpath(git_dir) == normpath(common),
    };
    if st.in_progress() {
        if let Some(listing) = git(top, &["ls-files".into(), "-u".into(), "-z".into()]) {
            let mut files: Vec<String> = Vec::new();
            for rec in listing.split('\0') {
                if let Some((_, name)) = rec.split_once('\t') {
                    files.push(realpath(&join(top, name)));
                }
            }
            files.sort();
            files.dedup();
            st.unmerged = files;
        }
    }
    st
}
