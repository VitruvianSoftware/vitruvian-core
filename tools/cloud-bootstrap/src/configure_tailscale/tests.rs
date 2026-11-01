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

//! Hermetic tests for //tools/cloud-bootstrap:configure-tailscale and the
//! Headscale / subnet-route behaviour it writes into .claude/tailscale-up.sh.
//! Ported from configure-tailscale_test.sh, every case kept:
//!   1. it writes the hook and --check passes on the written file;
//!   2. a Headscale pre-auth key (no tskey- prefix) gets
//!      --login-server=https://headscale.ipv1337.dev and --accept-routes=true;
//!   3. a commercial Tailscale key (tskey-*) with TS_LOGIN_SERVER unset gets
//!      no --login-server;
//!   4. an explicit TS_LOGIN_SERVER wins whatever the key prefix.
//! Cases 2-4 run against BOTH the freshly written hook and the checked-in
//! .claude/tailscale-up.sh, with fake tailscale/tailscaled/sudo on PATH. Added:
//! --check against the checked-in hook (the old header promised it but never
//! ran it), the CLI's error paths and messages, and the hook's two no-op exits.

use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::{AtomicUsize, Ordering};

const NAME: &str = "configure-tailscale";

fn env_path(var: &str) -> PathBuf {
    let rel = std::env::var_os(var).unwrap_or_else(|| panic!("{var} is not set by the rust_test"));
    fs::canonicalize(&rel).unwrap_or_else(|e| panic!("{var}={rel:?}: {e}"))
}

fn tool() -> PathBuf {
    env_path("BIN")
}

/// The checked-in .claude/tailscale-up.sh.
fn checked_in_hook() -> PathBuf {
    env_path("HOOK_FILE")
}

struct Tmp(PathBuf);

impl Tmp {
    fn new() -> Tmp {
        static N: AtomicUsize = AtomicUsize::new(0);
        let base = std::env::var_os("TEST_TMPDIR")
            .map(PathBuf::from)
            .unwrap_or_else(std::env::temp_dir);
        let p = base.join(format!(
            "ct-{}-{}",
            std::process::id(),
            N.fetch_add(1, Ordering::SeqCst)
        ));
        let _ = fs::remove_dir_all(&p);
        fs::create_dir_all(&p).unwrap();
        Tmp(fs::canonicalize(&p).unwrap())
    }
    fn join(&self, p: &str) -> PathBuf {
        self.0.join(p)
    }
}

impl Drop for Tmp {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

struct Out {
    code: i32,
    stdout: String,
    stderr: String,
}

fn configure(args: &[&str], workspace: Option<&Path>) -> Out {
    let mut c = Command::new(tool());
    c.args(args).env_remove("BUILD_WORKSPACE_DIRECTORY");
    if let Some(w) = workspace {
        c.env("BUILD_WORKSPACE_DIRECTORY", w);
    }
    let o = c.output().expect("run configure-tailscale");
    Out {
        code: o.status.code().unwrap_or(128),
        stdout: String::from_utf8_lossy(&o.stdout).into_owned(),
        stderr: String::from_utf8_lossy(&o.stderr).into_owned(),
    }
}

fn write_exe(path: &Path, body: &str) {
    fs::write(path, body).unwrap();
    fs::set_permissions(path, fs::Permissions::from_mode(0o755)).unwrap();
}

/// A placeholder hook, as the old test started from.
fn stub(dir: &Tmp) -> PathBuf {
    let hook = dir.join("tailscale-up.sh");
    fs::write(&hook, "#!/usr/bin/env bash\n").unwrap();
    hook
}

// ---- generation and --check -------------------------------------------------

// Shell case 1: "writes tailscale-up.sh and --check passes on the generated file".
#[test]
fn writes_hook_and_check_passes_on_generated_file() {
    let t = Tmp::new();
    let hook = stub(&t);
    let s = hook.to_str().unwrap();
    let w = configure(&["--file", s], None);
    assert_eq!(w.code, 0, "write failed: {}{}", w.stdout, w.stderr);
    assert_eq!(w.stdout, format!("{NAME}: updated {s}\n"));
    let c = configure(&["--check", "--file", s], None);
    assert_eq!(
        c.code, 0,
        "--check failed on the file it wrote: {}{}",
        c.stdout, c.stderr
    );
    assert_eq!(c.stdout, format!("{NAME}: {s} is up to date\n"));
    let mode = fs::metadata(&hook).unwrap().permissions().mode();
    assert_eq!(
        mode & 0o111,
        0o111,
        "written hook is not executable: {mode:o}"
    );
}

#[test]
fn check_passes_against_checked_in_hook() {
    let real = checked_in_hook();
    let c = configure(&["--check", "--file", real.to_str().unwrap()], None);
    assert_eq!(
        c.code, 0,
        ".claude/tailscale-up.sh differs from what configure-tailscale writes:\n{}{}",
        c.stdout, c.stderr
    );
}

#[test]
fn generated_hook_is_byte_identical_to_checked_in_hook() {
    let t = Tmp::new();
    let hook = stub(&t);
    assert_eq!(configure(&["--file", hook.to_str().unwrap()], None).code, 0);
    assert_eq!(
        fs::read(&hook).unwrap(),
        fs::read(checked_in_hook()).unwrap()
    );
}

#[test]
fn check_on_stale_file_fails_with_diff_and_fix_command() {
    let t = Tmp::new();
    let hook = stub(&t);
    let s = hook.to_str().unwrap();
    let c = configure(&["--check", "--file", s], None);
    assert_eq!(
        c.code, 1,
        "stale file passed --check: {}{}",
        c.stdout, c.stderr
    );
    assert!(
        c.stderr.contains(&format!(
            "{NAME}: {s} is out of sync; run 'bazel run //tools/cloud-bootstrap:configure-tailscale'"
        )),
        "stderr: {}",
        c.stderr
    );
    assert!(
        c.stdout.contains("--- ") && c.stdout.contains("+++ "),
        "no unified diff: {}",
        c.stdout
    );
    assert!(
        c.stdout.contains("+--accept-routes=true") || c.stdout.contains("+\t--accept-routes=true"),
        "diff: {}",
        c.stdout
    );
    assert_eq!(
        fs::read_to_string(&hook).unwrap(),
        "#!/usr/bin/env bash\n",
        "--check must not write"
    );
}

/// The diff `--check` prints never goes through the shared temp directory.
/// A file at a guessable path there (it was `<tmp>/configure-tailscale-<pid>
/// .expected`, written with a plain create-or-truncate) lets another user
/// on the machine plant a symlink at that name and have the check overwrite
/// whatever it points at. TMPDIR here is a regular file, so any attempt to
/// create something under it fails, for root as well: the diff must still be
/// printed.
#[test]
fn check_diff_uses_no_temp_file() {
    let t = Tmp::new();
    let hook = stub(&t);
    let not_a_dir = t.join("tmpdir-is-a-file");
    fs::write(&not_a_dir, "not a directory\n").unwrap();
    let o = Command::new(tool())
        .args(["--check", "--file", hook.to_str().unwrap()])
        .env_remove("BUILD_WORKSPACE_DIRECTORY")
        .env("TMPDIR", &not_a_dir)
        .output()
        .expect("run configure-tailscale");
    let stdout = String::from_utf8_lossy(&o.stdout);
    assert_eq!(o.status.code(), Some(1), "stale file passed --check");
    assert!(
        stdout.contains("--- ") && stdout.contains("+++ "),
        "no unified diff without a usable temp dir: {stdout}"
    );
    assert!(
        stdout.contains("+--accept-routes=true") || stdout.contains("+\t--accept-routes=true"),
        "diff: {stdout}"
    );
    assert_eq!(fs::read_to_string(&not_a_dir).unwrap(), "not a directory\n");
}

/// The diff is fed the expected hook on its stdin and given no file but
/// the target: whatever the temp directory, a fixed path (`/tmp/…`) or any
/// other file written for diff to read shows up in diff's arguments. A fake
/// `diff` first on PATH records what it was given.
#[test]
fn check_diff_reads_the_expected_hook_from_stdin_not_a_file() {
    let t = Tmp::new();
    let hook = stub(&t);
    let bin = t.join("bin");
    fs::create_dir(&bin).unwrap();
    write_exe(
        &bin.join("diff"),
        "#!/bin/sh\nprintf '%s\\n' \"$@\" > \"$DIFF_ARGV\"\ncat > \"$DIFF_STDIN\"\nexit 1\n",
    );
    let path = format!(
        "{}:{}",
        bin.display(),
        std::env::var("PATH").unwrap_or_else(|_| "/usr/bin:/bin".into())
    );
    let o = Command::new(tool())
        .args(["--check", "--file", hook.to_str().unwrap()])
        .env_remove("BUILD_WORKSPACE_DIRECTORY")
        .env("PATH", path)
        .env("DIFF_ARGV", t.join("diff-argv"))
        .env("DIFF_STDIN", t.join("diff-stdin"))
        .output()
        .expect("run configure-tailscale");
    assert_eq!(o.status.code(), Some(1), "stale file passed --check");
    let argv = fs::read_to_string(t.join("diff-argv")).expect("diff was run");
    assert_eq!(
        argv.lines().collect::<Vec<_>>(),
        ["-u", hook.to_str().unwrap(), "-"],
        "diff must compare the target with stdin, not with a file written for it"
    );
    assert_eq!(
        fs::read(t.join("diff-stdin")).unwrap(),
        fs::read(checked_in_hook()).unwrap(),
        "diff's stdin is not the expected hook"
    );
}

/// `show_diff` writes no file at all, used by diff or not. A source check,
/// because a write that nothing reads leaves no trace a run can see.
#[test]
fn show_diff_writes_no_file() {
    let src = include_str!("lib.rs");
    let start = src.find("fn show_diff(").expect("show_diff is in lib.rs");
    let body = &src[start..];
    let body = &body[..body.find("\n}\n").expect("show_diff ends")];
    for writes in [
        "fs::write",
        "File::create",
        "OpenOptions",
        "create_new",
        "temp_dir",
        "TMPDIR",
        "/tmp",
        "tempfile",
        "mktemp",
    ] {
        assert!(
            !body.contains(writes),
            "show_diff uses `{writes}`; feed diff the expected text on stdin instead:\n{body}"
        );
    }
}

#[test]
fn unknown_argument_is_exit_2() {
    let c = configure(&["--bogus"], None);
    assert_eq!(c.code, 2);
    assert_eq!(c.stderr, format!("{NAME}: unknown argument: --bogus\n"));
}

#[test]
fn missing_target_file_is_exit_1() {
    let t = Tmp::new();
    let missing = t.join("nope.sh");
    let c = configure(&["--file", missing.to_str().unwrap()], None);
    assert_eq!(c.code, 1);
    assert_eq!(
        c.stderr,
        format!("{NAME}: target file not found: {}\n", missing.display())
    );
}

#[test]
fn default_target_is_workspace_claude_hook() {
    let t = Tmp::new();
    fs::create_dir_all(t.join(".claude")).unwrap();
    let hook = t.join(".claude/tailscale-up.sh");
    fs::write(&hook, "stale\n").unwrap();
    let w = configure(&[], Some(&t.0));
    assert_eq!(w.code, 0, "{}{}", w.stdout, w.stderr);
    assert_eq!(w.stdout, format!("{NAME}: updated {}\n", hook.display()));
    assert_eq!(configure(&["--check"], Some(&t.0)).code, 0);
}

// ---- executing the hook -----------------------------------------------------

const FAKE_TAILSCALE: &str = r#"#!/usr/bin/env bash
case "$1" in
status)
	# First call checks if already connected (return 1, unless
	# FAKE_TS_CONNECTED); later calls poll for tailscaled readiness (return 0).
	count_file="${FAKE_TS_DIR}/status_count"
	c=0
	[ -f "$count_file" ] && c="$(cat "$count_file")"
	c=$((c + 1))
	echo "$c" >"$count_file"
	if [ "$c" -eq 1 ] && [ -z "${FAKE_TS_CONNECTED:-}" ]; then
		exit 1
	fi
	exit 0
	;;
up)
	printf '%s\n' "$*" >"${FAKE_TS_DIR}/up_args"
	exit 0
	;;
ip)
	echo "100.64.0.99"
	exit 0
	;;
esac
exit 0
"#;

struct Hooks {
    t: Tmp,
    hooks: Vec<(&'static str, PathBuf)>,
}

impl Hooks {
    /// Fake binaries plus the two hooks under test: freshly generated and checked in.
    fn new() -> Hooks {
        let t = Tmp::new();
        let fake = t.join("bin");
        fs::create_dir_all(&fake).unwrap();
        write_exe(&fake.join("tailscaled"), "#!/usr/bin/env bash\nexit 0\n");
        write_exe(&fake.join("tailscale"), FAKE_TAILSCALE);
        write_exe(&fake.join("sudo"), "#!/usr/bin/env bash\nexec \"$@\"\n");
        let generated = stub(&t);
        assert_eq!(
            configure(&["--file", generated.to_str().unwrap()], None).code,
            0
        );
        Hooks {
            t,
            hooks: vec![("generated", generated), ("checked-in", checked_in_hook())],
        }
    }

    /// Run `hook` with only `vars` (plus HOME/PATH/FAKE_TS_DIR) set, like
    /// `env -i`; returns (exit code, `tailscale up` argv or "" if not called).
    fn run(&self, hook: &Path, vars: &[(&str, &str)]) -> (i32, String) {
        let ts = self.t.join("ts");
        let home = self.t.join("home");
        let _ = fs::remove_dir_all(&ts);
        let _ = fs::remove_dir_all(&home);
        fs::create_dir_all(&ts).unwrap();
        fs::create_dir_all(&home).unwrap();
        let mut c = Command::new("bash");
        c.arg(hook)
            .env_clear()
            .env("HOME", &home)
            .env(
                "PATH",
                format!("{}:/usr/bin:/bin", self.t.join("bin").display()),
            )
            .env("FAKE_TS_DIR", &ts);
        for (k, v) in vars {
            c.env(k, v);
        }
        let o = c.output().expect("run the hook");
        let up = fs::read_to_string(ts.join("up_args")).unwrap_or_default();
        (o.status.code().unwrap_or(128), up)
    }
}

// Shell case 2: "headscale pre-auth key".
#[test]
fn headscale_key_selects_headscale_and_accepts_routes() {
    let h = Hooks::new();
    for (which, hook) in &h.hooks {
        let (rc, up) = h.run(
            hook,
            &[
                ("CLAUDE_CODE_REMOTE", "true"),
                (
                    "TS_AUTHKEY",
                    "8fe9eb83c4488690525e34b543b548ce1fbbdcf57db11331",
                ),
            ],
        );
        assert_eq!(rc, 0, "{which}: hook must exit 0");
        assert!(
            up.contains("--accept-routes=true"),
            "{which}: missing --accept-routes=true in: {up}"
        );
        assert!(
            up.contains("--login-server=https://headscale.ipv1337.dev"),
            "{which}: missing Headscale --login-server in: {up}"
        );
    }
}

// Shell case 3: "commercial tailscale key (tskey-*)".
#[test]
fn tskey_without_login_server_omits_login_server() {
    let h = Hooks::new();
    for (which, hook) in &h.hooks {
        let (rc, up) = h.run(
            hook,
            &[
                ("CLAUDE_CODE_REMOTE", "true"),
                ("TS_AUTHKEY", "tskey-auth-k123456CNTRL-abcdef"),
            ],
        );
        assert_eq!(rc, 0, "{which}: hook must exit 0");
        assert!(!up.is_empty(), "{which}: tailscale up was not called");
        assert!(
            !up.contains("--login-server="),
            "{which}: unexpected --login-server for tskey-*: {up}"
        );
        assert!(
            up.contains("--accept-routes=true"),
            "{which}: missing --accept-routes=true in: {up}"
        );
    }
}

// Shell case 4: "explicit TS_LOGIN_SERVER override".
#[test]
fn explicit_login_server_overrides() {
    let h = Hooks::new();
    for (which, hook) in &h.hooks {
        let (rc, up) = h.run(
            hook,
            &[
                ("CLAUDE_CODE_REMOTE", "true"),
                ("TS_AUTHKEY", "tskey-auth-k123456CNTRL-abcdef"),
                ("TS_LOGIN_SERVER", "https://custom.headscale.example"),
            ],
        );
        assert_eq!(rc, 0, "{which}: hook must exit 0");
        assert!(
            up.contains("--login-server=https://custom.headscale.example"),
            "{which}: missing explicit TS_LOGIN_SERVER in: {up}"
        );
    }
}

#[test]
fn hook_is_a_no_op_outside_cloud_sessions() {
    let h = Hooks::new();
    for (which, hook) in &h.hooks {
        let (rc, up) = h.run(hook, &[("TS_AUTHKEY", "tskey-auth-k123456CNTRL-abcdef")]);
        assert_eq!(rc, 0, "{which}");
        assert!(
            up.is_empty(),
            "{which}: tailscale up ran on a local checkout: {up}"
        );
    }
}

#[test]
fn hook_without_authkey_exits_0_without_joining() {
    let h = Hooks::new();
    for (which, hook) in &h.hooks {
        let (rc, up) = h.run(hook, &[("CLAUDE_CODE_REMOTE", "true")]);
        assert_eq!(rc, 0, "{which}: a missing key must never fail the session");
        assert!(
            up.is_empty(),
            "{which}: tailscale up ran without TS_AUTHKEY: {up}"
        );
    }
}

#[test]
fn hook_already_connected_does_not_rejoin() {
    let h = Hooks::new();
    for (which, hook) in &h.hooks {
        let (rc, up) = h.run(
            hook,
            &[
                ("CLAUDE_CODE_REMOTE", "true"),
                ("TS_AUTHKEY", "tskey-x"),
                ("FAKE_TS_CONNECTED", "1"),
            ],
        );
        assert_eq!(rc, 0, "{which}");
        assert!(
            up.is_empty(),
            "{which}: rejoined an already-connected tailnet: {up}"
        );
    }
}
