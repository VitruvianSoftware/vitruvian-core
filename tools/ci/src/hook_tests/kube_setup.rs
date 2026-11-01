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

//! //tools/ci:kube_setup_test -- the last line .claude/kube-setup.sh prints:
//! whether the homelab apiserver actually answers. That line is the only
//! cluster status an agent sees at session start (Claude Code adds a
//! SessionStart hook's stdout to the session and hides stderr from a hook that
//! exits 0), and it once said "reachable" unconditionally while the tailnet had
//! rejected TS_AUTHKEY.
//!
//! Runs the real hook against fake `tailscale` and `kubectl` binaries and
//! checks, for each state, what it says on stdout: reachable only when kubectl
//! got an answer; otherwise NOT reachable with the reason; always exit 0; and
//! the ServiceAccount token never printed. Also checks it waits for a
//! tailscale-up.sh that is still joining, and that the session-start hook runs
//! it. Ported case for case from the former tools/ci/kube-setup_test.sh.

mod common;

use ci_testkit::{write_exe, TempDir};
use common::*;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

const HOOK: &str = ".claude/kube-setup.sh";
const TOKEN: &str = "fake-sa-token-0123456789";

/// The hook under test: $HOOK_UNDER_TEST when set (a planted-break run points
/// it at a broken copy), else the repo's.
fn hook() -> PathBuf {
    match std::env::var_os("HOOK_UNDER_TEST") {
        Some(p) => p.into(),
        None => repo(HOOK),
    }
}

const FAKE_TAILSCALE: &str = r#"#!/usr/bin/env bash
[ "$*" = "status --json" ] || { echo "fake tailscale: unexpected args: $*" >&2; exit 2; }
state="$(cat "${FAKE_TS_STATE}")"
if [ "${state}" = down ]; then echo "failed to connect to local tailscaled" >&2; exit 1; fi
printf '{\n  "Version": "1.98.9",\n  "BackendState": "%s",\n' "${state}"
if [ -n "${FAKE_TS_HEALTH:-}" ]; then
  printf '  "Health": [\n    "%s"\n  ],\n' "${FAKE_TS_HEALTH}"
else
  printf '  "Health": null,\n'
fi
printf '  "CurrentTailnet": null\n}\n'
"#;

const FAKE_KUBECTL: &str = r#"#!/usr/bin/env bash
echo "$*" >>"${FAKE_KUBECTL_CALLS}"
case "${FAKE_KUBECTL}" in
ok) echo '{"major": "1", "minor": "33"}' ;;
unauthorized) echo 'error: You must be logged in to the server (Unauthorized)' >&2; exit 1 ;;
unreachable)
  echo 'E1008 17:21:17.548509 2127 memcache.go:381] "Couldn'"'"'t get current server API group list"' >&2
  echo 'Unable to connect to the server: socks connect tcp 127.0.0.1:1055->k8s-api.lab.ipv1337.dev:6443: unknown error general SOCKS server failure' >&2
  exit 1 ;;
esac
"#;

struct Fixture {
    work: TempDir,
    fake: PathBuf,
    state_file: PathBuf,
    calls: PathBuf,
}

struct Ran {
    out: String,
    err: String,
    rc: i32,
}

impl Fixture {
    fn new() -> Fixture {
        let work = TempDir::new();
        let fake = work.join("bin");
        write_exe(fake.join("tailscale"), FAKE_TAILSCALE);
        write_exe(fake.join("kubectl"), FAKE_KUBECTL);
        // ssh present, so the hook does not try to apt-get it.
        write_exe(fake.join("ssh"), "#!/usr/bin/env bash\nexit 0\n");
        let state_file = work.join("ts-state");
        let calls = work.join("kubectl-calls");
        Fixture {
            work,
            fake,
            state_file,
            calls,
        }
    }

    fn calls(&self) -> String {
        ci_testkit::read(&self.calls)
    }

    /// The hook under `env -i` with the shell suite's environment, plus
    /// `extra` (an empty value overrides, as `VAR=` did there).
    fn command(&self, path: &str, answer: &str, extra: &[(&str, &str)]) -> Command {
        let home = self.work.join("home");
        let mut c = Command::new("bash");
        c.arg(hook())
            .env_clear()
            .env("HOME", &home)
            .env("PATH", path)
            .env("CLAUDE_CODE_REMOTE", "true")
            .env("LAB_SA_TOKEN", TOKEN)
            .env("TS_AUTHKEY", "tskey-fake")
            .env("FAKE_TS_STATE", &self.state_file)
            .env("FAKE_KUBECTL", answer)
            .env("FAKE_KUBECTL_CALLS", &self.calls);
        for (k, v) in extra {
            c.env(k, v);
        }
        c.stdin(Stdio::null());
        c
    }

    fn default_path(&self) -> String {
        format!("{}:/usr/bin:/bin", self.fake.display())
    }

    /// run_hook <tailscale state> <kubectl answer> [VAR=value...]
    fn run(&self, state: &str, answer: &str, extra: &[(&str, &str)]) -> Ran {
        self.run_on(&self.default_path(), state, answer, extra)
    }

    fn run_on(&self, path: &str, state: &str, answer: &str, extra: &[(&str, &str)]) -> Ran {
        std::fs::write(&self.state_file, format!("{state}\n")).unwrap();
        std::fs::write(&self.calls, "").unwrap();
        let home = self.work.join("home");
        let _ = std::fs::remove_dir_all(&home);
        std::fs::create_dir_all(&home).unwrap();
        exec(self.command(path, answer, extra))
    }
}

fn exec(mut c: Command) -> Ran {
    let o = c.output().expect("run the hook");
    Ran {
        out: String::from_utf8_lossy(&o.stdout).into_owned(),
        err: String::from_utf8_lossy(&o.stderr).into_owned(),
        rc: o.status.code().unwrap_or(-1),
    }
}

/// verdict <label> <want: reachable|unreachable> [text the line must contain]
fn verdict(r: &Ran, label: &str, reachable: bool, detail: &str) {
    let line = r
        .out
        .lines()
        .filter(|l| l.starts_with("kube-setup: kubeconfig written"))
        .last()
        .unwrap_or("");
    assert_eq!(
        r.rc, 0,
        "{label}: exit {}, want 0 (a hook failure must never block the session)",
        r.rc
    );
    let ok = if reachable {
        line.contains("apiserver reachable via SOCKS5")
    } else {
        line.contains("apiserver is NOT reachable")
    };
    let want = if reachable {
        "reachable"
    } else {
        "unreachable"
    };
    let shown = if line.is_empty() { "<nothing>" } else { line };
    assert!(
        ok,
        "{label}: want {want}, stdout said: {shown}\nstderr: {}",
        r.err
    );
    assert!(
        detail.is_empty() || line.contains(detail),
        "{label}: the line does not say '{detail}': {line}"
    );
    assert!(
        !format!("{}{}", r.out, r.err).contains(TOKEN),
        "{label}: printed the ServiceAccount token"
    );
}

#[test]
fn tailnet_up_apiserver_answers_reachable_with_a_bounded_probe() {
    let f = Fixture::new();
    let r = f.run("Running", "ok", &[]);
    verdict(&r, "tailnet up, apiserver answers: reachable", true, "");
    let calls = f.calls();
    assert!(
        calls.contains("--request-timeout") && calls.contains("get --raw=/version"),
        "unexpected probe: {calls}"
    );
}

#[test]
fn revoked_auth_key_not_reachable_with_tailscaleds_error_and_no_probe() {
    let f = Fixture::new();
    let r = f.run(
        "NeedsLogin",
        "ok",
        &[(
            "FAKE_TS_HEALTH",
            "You are logged out. The last login error was: invalid key: API key does not exist",
        )],
    );
    verdict(
        &r,
        "revoked auth key: NOT reachable, with tailscaled's error",
        false,
        "invalid key: API key does not exist",
    );
    assert!(
        f.calls().is_empty(),
        "probed the apiserver with the tailnet logged out"
    );
}

#[test]
fn tailnet_stopped_not_reachable() {
    let f = Fixture::new();
    let r = f.run("Stopped", "ok", &[]);
    verdict(
        &r,
        "tailnet stopped: NOT reachable",
        false,
        "the tailnet is Stopped",
    );
}

#[test]
fn no_tailscaled_not_reachable() {
    let f = Fixture::new();
    let r = f.run("down", "ok", &[]);
    verdict(
        &r,
        "no tailscaled: NOT reachable",
        false,
        "tailscaled is not running",
    );
}

#[test]
fn no_tailscaled_and_no_auth_key_says_ts_authkey_is_not_set() {
    let f = Fixture::new();
    let r = f.run("down", "ok", &[("TS_AUTHKEY", "")]);
    verdict(
        &r,
        "no tailscaled and no auth key: says TS_AUTHKEY is not set",
        false,
        "TS_AUTHKEY is not set",
    );
}

#[test]
fn token_rejected_blames_lab_sa_token() {
    let f = Fixture::new();
    let r = f.run("Running", "unauthorized", &[]);
    verdict(
        &r,
        "token rejected: NOT reachable, blames LAB_SA_TOKEN",
        false,
        "rejected LAB_SA_TOKEN",
    );
}

#[test]
fn apiserver_silent_not_reachable_with_kubectls_error() {
    let f = Fixture::new();
    let r = f.run("Running", "unreachable", &[]);
    verdict(
        &r,
        "tailnet up, apiserver silent: NOT reachable, with kubectl's error",
        false,
        "general SOCKS server failure",
    );
}

#[test]
fn no_tailscale_binary_not_reachable() {
    let f = Fixture::new();
    assert!(
        !Path::new("/usr/bin/tailscale").exists() && !Path::new("/bin/tailscale").exists(),
        "cannot hide tailscale: it is in /usr/bin or /bin on this machine"
    );
    let nots = f.work.join("no-tailscale");
    std::fs::create_dir_all(&nots).unwrap();
    for t in ["kubectl", "ssh"] {
        std::fs::copy(f.fake.join(t), nots.join(t)).unwrap();
    }
    let r = f.run_on(
        &format!("{}:/usr/bin:/bin", nots.display()),
        "Running",
        "ok",
        &[],
    );
    verdict(
        &r,
        "no tailscale binary: NOT reachable",
        false,
        "tailscale is not installed",
    );
}

#[test]
fn waits_for_a_tailscale_up_that_is_still_joining() {
    let f = Fixture::new();
    let joiner_script = f.work.join("tailscale-up.sh");
    std::fs::write(
        &joiner_script,
        format!("sleep 2\necho Running >\"{}\"\n", f.state_file.display()),
    )
    .unwrap();
    std::fs::write(&f.state_file, "NeedsLogin\n").unwrap();
    std::fs::write(&f.calls, "").unwrap();
    std::fs::create_dir_all(f.work.join("home")).unwrap();
    let start = Instant::now();
    // `(sleep 0.2; bash tailscale-up.sh) &`: the process the hook's pgrep
    // looks for is `bash <dir>/tailscale-up.sh`.
    let js = joiner_script.clone();
    let joiner = std::thread::spawn(move || {
        std::thread::sleep(Duration::from_millis(200));
        Command::new("bash").arg(&js).status().unwrap()
    });
    std::thread::sleep(Duration::from_millis(500));
    // The hook finds the joiner with pgrep. Where pgrep is missing or cannot
    // see this process (the remote executor's sandbox did not show it), the
    // hook's answer says nothing about the hook: say so instead.
    let seen = Command::new("pgrep")
        .args(["-f", r"^([^ ]*/)?(ba)?sh [^ ]*/tailscale-up\.sh$"])
        .stdout(Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false);
    assert!(
        seen,
        "pgrep cannot see the joining tailscale-up.sh here (no procps, or a hidden process table); \
         run //tools/ci:kube_setup_join_test where the hook runs, as repo-guards-test.yaml does"
    );
    let r = exec(f.command(&f.default_path(), "ok", &[]));
    joiner.join().unwrap();
    verdict(&r, "reports reachable once the join finishes", true, "");
    let waited = start.elapsed().as_secs();
    assert!(waited < 30, "and does not wait past it: waited {waited}s");
}

#[test]
fn the_session_start_hook_runs_it() {
    // settings.json runs .claude/session-start.sh, which runs this hook last
    // (//tools/ci:session_start_test checks that wrapper's order).
    let work = TempDir::new();
    let jq_dir = jq_dir(&work);
    let wired = wired(
        &jq_dir,
        r#".hooks.SessionStart[]?.hooks[]? | select(.type == "command") | .command"#,
    );
    let wrapper = std::fs::read_to_string(repo(".claude/session-start.sh")).unwrap();
    assert!(
        wired.contains(".claude/session-start.sh")
            && wrapper.contains(r#""${root}/.claude/kube-setup.sh""#),
        "nothing runs it at session start: settings.json has '{wired}'"
    );
}

#[test]
fn hook_script_is_executable() {
    assert!(is_executable(&repo(HOOK)), "hook script is not executable");
}
