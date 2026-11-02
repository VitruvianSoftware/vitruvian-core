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

//! Shared by the rust_tests of the Claude Code hooks in .claude/ (ported from
//! tools/ci/{block-queue-bypass,kube-setup,session-start}_test.sh): where the
//! repo's files are in the runfiles tree, a PATH with the hermetic jq (the
//! hooks need jq and the RBE image has none), and what .claude/settings.json
//! wires up.

#![allow(dead_code)]

use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use ci_testkit::TempDir;

/// A repo file in the runfiles tree, absolute (the test's cwd is the
/// workspace root of its runfiles). Not canonicalized: a hook that resolves
/// paths from its own location should see the repo layout, not the source
/// file a runfiles symlink points at.
pub fn repo(rel: &str) -> PathBuf {
    let p = std::env::current_dir().unwrap().join(rel);
    assert!(
        p.exists(),
        "{rel} is not in the test's runfiles: add it to data"
    );
    p
}

/// A directory holding only `jq` (the hermetic one from $JQ_BIN, else the
/// ambient one), to put in front of /usr/bin:/bin.
pub fn jq_dir(work: &TempDir) -> PathBuf {
    let dir = work.join("jq-bin");
    std::fs::create_dir_all(&dir).unwrap();
    let jq = match std::env::var("JQ_BIN") {
        Ok(j) => {
            let j = match j.strip_prefix("external/") {
                Some(rest) => format!("../{rest}"),
                None => j,
            };
            std::fs::canonicalize(&j).unwrap_or_else(|e| panic!("JQ_BIN={j}: {e}"))
        }
        Err(_) => PathBuf::from("/usr/bin/jq"),
    };
    let _ = std::fs::remove_file(dir.join("jq"));
    std::os::unix::fs::symlink(&jq, dir.join("jq")).unwrap();
    // Prove it runs: a hook that cannot find jq allows everything quietly.
    let o = Command::new(dir.join("jq"))
        .arg("--version")
        .output()
        .expect("run jq");
    assert!(o.status.success(), "the hermetic jq does not run");
    dir
}

/// Run jq `filter` over `input`, returning stdout.
pub fn jq(jq_dir: &Path, args: &[&str], input: &[u8]) -> String {
    use std::io::Write;
    let mut c = Command::new(jq_dir.join("jq"))
        .args(args)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .expect("spawn jq");
    c.stdin.take().unwrap().write_all(input).unwrap();
    let o = c.wait_with_output().unwrap();
    String::from_utf8_lossy(&o.stdout).into_owned()
}

/// The command hooks .claude/settings.json runs, by `jq` filter.
pub fn wired(jq_dir: &Path, filter: &str) -> String {
    let settings = std::fs::read(repo(".claude/settings.json")).unwrap();
    jq(jq_dir, &["-r", filter], &settings)
}

pub fn is_executable(p: &Path) -> bool {
    use std::os::unix::fs::PermissionsExt;
    std::fs::metadata(p)
        .map(|m| m.permissions().mode() & 0o111 != 0)
        .unwrap_or(false)
}

/// Proves a suite can fail: copies the real hook at `rel` into a temp dir,
/// replaces `from` (which must occur exactly once) with `to`, and re-runs this
/// test binary's `test` against that copy through $HOOK_UNDER_TEST. The
/// unbroken copy must pass and the broken one must fail, so the failure is the
/// planted break's, not the copy's. Nothing in .claude/ is ever edited.
pub fn planted_break_fails(rel: &str, from: &str, to: &str, test: &str) {
    if std::env::var_os("HOOK_UNDER_TEST").is_some() {
        return; // the child run of another planted-break check
    }
    let src = std::fs::read_to_string(repo(rel)).unwrap();
    assert_eq!(
        src.matches(from).count(),
        1,
        "{rel} no longer contains exactly one {from:?}: update the planted break"
    );
    let work = TempDir::new();
    let run = |name: &str, body: &str| {
        let copy = work.join(name);
        std::fs::write(&copy, body).unwrap();
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&copy, std::fs::Permissions::from_mode(0o755)).unwrap();
        Command::new(std::env::current_exe().unwrap())
            .args([test, "--exact", "--test-threads=1"])
            .env("HOOK_UNDER_TEST", &copy)
            .output()
            .expect("re-run the test binary")
    };
    let clean = run("clean.sh", &src);
    assert!(
        clean.status.success(),
        "{test} fails even on an unbroken copy of {rel}:\n{}",
        String::from_utf8_lossy(&clean.stdout)
    );
    let broken = run("broken.sh", &src.replacen(from, to, 1));
    let out = String::from_utf8_lossy(&broken.stdout);
    assert!(
        !broken.status.success() && out.contains(&format!("{test} ... FAILED")),
        "{test} still passes with {from:?} -> {to:?} planted in a copy of {rel}:\n{out}"
    );
}
