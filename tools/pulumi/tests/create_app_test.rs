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

//! //tools/pulumi:create-app (the one-time GitHub App manifest bootstrap)
//! with stub `gh`, `open`, `timeout` and `nc`. The former create-app.sh had no
//! suite of its own; these cases pin its behaviour, including the parity gaps
//! fixed in the cutover (marked "gap").
//!
//! PATH is ONLY the stub dir plus a dir holding `bash` and `cat`, so the
//! machine's own nc/timeout/jq/open can never be picked up.

mod common;
use common::*;
use std::path::{Path, PathBuf};

const GH: &str = r#"#!/usr/bin/env bash
echo "$*" >>"$GH_LOG"
case "$*" in
  "auth status") exit "${AUTH_RC:-0}" ;;
  "api user --jq .login") echo octo; exit 0 ;;
  "api orgs/"*) exit "${ORG_RC:-0}" ;;
  "api --method POST /app-manifests/"*)
    [ "${CONV_RC:-0}" -eq 0 ] || { echo "HTTP 404" >&2; exit "$CONV_RC"; }
    printf '%s' "$CONVERSION"; exit 0 ;;
  "variable set "*) echo "gh-var $3=${@: -1}"; exit "${VARSET_RC:-0}" ;;
  "secret set "*) printf '%s=%s\n' "$3" "$(cat)" >>"$SECRETS_LOG"; exit "${SECSET_RC:-0}" ;;
esac
exit 0
"#;

const OPEN: &str = r#"#!/usr/bin/env bash
echo "$1" >>"$OPEN_LOG"
cat "$1" >"$OPEN_LOG.html"
echo opened
"#;

const CONVERSION: &str = r#"{"id": 123, "slug": "acme-pulumi", "pem": "-----BEGIN KEY-----\nabc\n-----END KEY-----", "client_id": "Iv1.client"}"#;

fn find_tool(name: &str) -> PathBuf {
    for d in ["/bin", "/usr/bin", "/usr/local/bin", "/opt/homebrew/bin"] {
        let p = Path::new(d).join(name);
        if p.is_file() {
            return p;
        }
    }
    panic!("{name} not found");
}

struct Fx {
    d: PathBuf,
    stubs: PathBuf,
    sys: PathBuf,
}

struct Res {
    rc: i32,
    out: String,
    err: String,
    gh: String,
    secrets: String,
    opened: String,
    html: String,
}

impl Fx {
    /// `listener`: Some(request line) installs stub timeout + nc that "receive"
    /// it; None leaves them off PATH, so the paste prompt is used.
    fn new(listener: Option<&str>) -> Fx {
        let d = tempdir("create-app");
        let stubs = d.join("stubs");
        let sys = d.join("sys");
        std::fs::create_dir_all(&sys).unwrap();
        for t in ["bash", "cat"] {
            std::os::unix::fs::symlink(find_tool(t), sys.join(t)).unwrap();
        }
        write_exec(&stubs.join("gh"), GH);
        write_exec(&stubs.join("open"), OPEN);
        if let Some(req) = listener {
            write_exec(
                &stubs.join("timeout"),
                "#!/usr/bin/env bash\nshift\nexec \"$@\"\n",
            );
            write_exec(
                &stubs.join("nc"),
                &format!("#!/usr/bin/env bash\nprintf '%s\\r\\nHost: localhost\\r\\n' '{req}'\n"),
            );
        }
        std::fs::create_dir_all(d.join("tmp")).unwrap();
        Fx { d, stubs, sys }
    }

    fn run(&self, args: &[&str], stdin: &str, env: &[(&str, &str)]) -> Res {
        use std::io::Write;
        let mut c = cmd(
            &bin("CREATE_APP_BIN"),
            &format!("{}:{}", self.stubs.display(), self.sys.display()),
        );
        c.env("GH_LOG", self.d.join("gh.log"))
            .env("SECRETS_LOG", self.d.join("secrets.log"))
            .env("OPEN_LOG", self.d.join("open.log"))
            .env("CONVERSION", CONVERSION)
            .env("TMPDIR", self.d.join("tmp"))
            .args(args)
            .stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped());
        for (k, v) in env {
            c.env(k, v);
        }
        let mut child = c.spawn().unwrap();
        child
            .stdin
            .take()
            .unwrap()
            .write_all(stdin.as_bytes())
            .unwrap();
        let o = child.wait_with_output().unwrap();
        Res {
            rc: code(&o),
            out: stdout(&o),
            err: stderr(&o),
            gh: read(&self.d.join("gh.log")),
            secrets: read(&self.d.join("secrets.log")),
            opened: read(&self.d.join("open.log")).trim_end().to_string(),
            html: read(&self.d.join("open.log.html")),
        }
    }
}

#[test]
fn happy_path_listener_captures_code_and_sets_everything() {
    let fx = Fx::new(Some("GET /cb?code=abc123 HTTP/1.1"));
    let r = fx.run(&["acme"], "pul-tok\n", &[]);
    assert_eq!(r.rc, 0, "{}", r.err);
    assert!(
        r.out.contains("\u{2713} Target 'acme' is an organization."),
        "{}",
        r.out
    );
    assert!(
        r.gh.contains("api --method POST /app-manifests/abc123/conversions\n"),
        "{}",
        r.gh
    );
    assert!(
        r.out
            .contains("\u{2713} Created GitHub App 'acme-pulumi' (id: 123)."),
        "{}",
        r.out
    );
    assert!(
        r.gh.contains("variable set PULUMI_APP_ID --org acme --visibility all --body 123\n"),
        "{}",
        r.gh
    );
    assert!(
        r.gh.contains(
            "variable set PULUMI_APP_CLIENT_ID --org acme --visibility all --body Iv1.client\n"
        ),
        "{}",
        r.gh
    );
    assert_eq!(
        r.secrets,
        "APP_PRIVATE_KEY=-----BEGIN KEY-----\nabc\n-----END KEY-----\nPULUMI_ACCESS_TOKEN=pul-tok\n"
    );
    assert!(r.out.contains("\u{2713} Set PULUMI_ACCESS_TOKEN (secret)."));
    assert!(r
        .out
        .contains("    https://github.com/apps/acme-pulumi/installations/new\n"));
    assert!(
        !r.out.contains("BEGIN KEY") && !r.err.contains("BEGIN KEY"),
        "the PEM must never be echoed"
    );
    assert!(
        !r.out.contains("pul-tok") && !r.err.contains("pul-tok"),
        "the token must never be echoed"
    );
}

#[test]
fn manifest_form_posts_least_privilege_manifest() {
    let fx = Fx::new(Some("GET /cb?code=abc HTTP/1.1"));
    let r = fx.run(&["acme"], "\n", &[]);
    assert!(
        r.html
            .contains(r#"action="https://github.com/organizations/acme/settings/apps/new""#),
        "{}",
        r.html
    );
    assert!(r.html.contains(r#""name": "acme-pulumi""#));
    assert!(r
        .html
        .contains(r#""redirect_url": "http://localhost:8723/cb""#));
    assert!(
        r.html.contains(r#""administration": "write""#) && r.html.contains(r#""contents": "read""#)
    );
    assert!(r.html.contains(r#""default_events": []"#));
}

#[test]
fn personal_account_uses_user_endpoint() {
    let fx = Fx::new(Some("GET /cb?code=abc HTTP/1.1"));
    let r = fx.run(&["octo"], "\n", &[("ORG_RC", "1")]);
    assert!(r
        .out
        .contains("\u{2713} Target 'octo' treated as a personal account."));
    assert!(
        r.html
            .contains(r#"action="https://github.com/settings/apps/new""#),
        "{}",
        r.html
    );
}

#[test]
fn owner_prompt_defaults_to_gh_user() {
    let fx = Fx::new(Some("GET /cb?code=abc HTTP/1.1"));
    let r = fx.run(&[], "\n\n", &[]);
    assert_eq!(r.rc, 0, "{}", r.err);
    assert!(r.gh.contains("api orgs/octo\n"), "{}", r.gh);
}

#[test]
fn paste_path_when_no_listener() {
    let fx = Fx::new(None);
    let r = fx.run(&["acme"], "pasted-code\n\n", &[]);
    assert_eq!(r.rc, 0, "{}", r.err);
    assert!(r
        .out
        .contains("copy the 'code=' value from the address bar"));
    assert!(
        r.gh.contains("/app-manifests/pasted-code/conversions"),
        "{}",
        r.gh
    );
    assert!(
        r.out.contains("! Skipped PULUMI_ACCESS_TOKEN."),
        "{}",
        r.out
    );
}

#[test]
fn no_code_exits_1() {
    let fx = Fx::new(None);
    let r = fx.run(&["acme"], "", &[]);
    assert_eq!(r.rc, 1);
    assert!(r.err.contains("! No code captured"), "{}", r.err);
}

#[test]
fn failed_exchange_exits_1() {
    let fx = Fx::new(Some("GET /cb?code=abc HTTP/1.1"));
    let r = fx.run(&["acme"], "\n", &[("CONV_RC", "1")]);
    assert_eq!(r.rc, 1);
    assert!(r.err.contains("! Failed to exchange the code"), "{}", r.err);
}

// gap: `CONVERSION="$(gh api ...)"` captures stdout only; gh's own error
// (e.g. the HTTP status) is still shown.
#[test]
fn gap_exchange_error_from_gh_is_shown() {
    let fx = Fx::new(Some("GET /cb?code=abc HTTP/1.1"));
    let r = fx.run(&["acme"], "\n", &[("CONV_RC", "1")]);
    assert!(r.err.contains("HTTP 404"), "{}", r.err);
}

#[test]
fn conversion_without_pem_exits_1() {
    let fx = Fx::new(Some("GET /cb?code=abc HTTP/1.1"));
    let r = fx.run(
        &["acme"],
        "\n",
        &[("CONVERSION", r#"{"id": 1, "slug": "s"}"#)],
    );
    assert_eq!(r.rc, 1);
    assert!(
        r.err.contains("! Conversion did not return an App id/pem"),
        "{}",
        r.err
    );
}

#[test]
fn missing_client_id_warns_and_continues() {
    let fx = Fx::new(Some("GET /cb?code=abc HTTP/1.1"));
    let r = fx.run(
        &["acme"],
        "\n",
        &[(
            "CONVERSION",
            r#"{"id": 1, "slug": "s", "pem": "P", "client_id": null}"#,
        )],
    );
    assert_eq!(r.rc, 0, "{}", r.err);
    assert!(
        r.err.contains(
            "! Conversion returned no client_id. Read it from 'gh api /apps/s --jq .client_id'"
        ),
        "{}",
        r.err
    );
    assert!(!r.gh.contains("PULUMI_APP_CLIENT_ID"));
}

#[test]
fn missing_gh_exits_1() {
    let fx = Fx::new(None);
    std::fs::remove_file(fx.stubs.join("gh")).unwrap();
    let r = fx.run(&["acme"], "", &[]);
    assert_eq!(r.rc, 1);
    assert!(r.err.contains("! gh CLI not found."), "{}", r.err);
}

#[test]
fn unauthenticated_gh_exits_1() {
    let fx = Fx::new(None);
    let r = fx.run(&["acme"], "", &[("AUTH_RC", "1")]);
    assert_eq!(r.rc, 1);
    assert!(r.err.contains("! gh is not authenticated."), "{}", r.err);
}

#[test]
fn html_file_is_removed_on_exit() {
    let fx = Fx::new(Some("GET /cb?code=abc HTTP/1.1"));
    let r = fx.run(&["acme"], "\n", &[]);
    assert!(!r.opened.is_empty());
    assert!(
        !Path::new(&r.opened).exists(),
        "{} was left behind",
        r.opened
    );
}

// gap: the shell takes the LAST `[?&]code=` on the request line
// (`sed 's/.*[?&]code=\([^ &]*\).*/\1/'`, greedy), and only after ? or &.
#[test]
fn gap_code_is_the_last_query_code_param() {
    let fx = Fx::new(Some("GET /cb?xcode=bad&code=good HTTP/1.1"));
    let r = fx.run(&["acme"], "\n", &[]);
    assert!(r.gh.contains("/app-manifests/good/conversions"), "{}", r.gh);
}

// Same rule end to end when `code=` itself repeats: the last one wins.
#[test]
fn gap_code_is_the_last_of_repeated_code_params() {
    let fx = Fx::new(Some("GET /cb?code=one&code=two HTTP/1.1"));
    let r = fx.run(&["acme"], "\n", &[]);
    assert!(r.gh.contains("/app-manifests/two/conversions"), "{}", r.gh);
    assert!(!r.gh.contains("/app-manifests/one/"), "{}", r.gh);
}

fn assert_code_rejected(r: &Res) {
    assert_eq!(r.rc, 1, "out: {}\nerr: {}", r.out, r.err);
    assert!(
        r.err.contains("! That is not a GitHub App manifest code"),
        "{}",
        r.err
    );
    assert!(
        !r.gh.contains("app-manifests"),
        "gh was called with the bad code: {}",
        r.gh
    );
    assert!(!r.gh.contains("variable set") && r.secrets.is_empty());
}

// The code goes into the `gh api` request path, so anything but
// [A-Za-z0-9_-] (a path step, a query, a slash) is refused before gh runs.
#[test]
fn malicious_code_from_listener_is_rejected_before_gh() {
    for req in [
        "GET /cb?code=../../user HTTP/1.1",
        "GET /cb?code=abc/../../orgs/acme HTTP/1.1",
        "GET /cb?code=abc?x=1 HTTP/1.1",
        "GET /cb?code=..%2F..%2Fuser HTTP/1.1",
    ] {
        let fx = Fx::new(Some(req));
        let r = fx.run(&["acme"], "\n", &[]);
        assert_code_rejected(&r);
    }
}

#[test]
fn malicious_or_oversized_pasted_code_is_rejected_before_gh() {
    let long = "a".repeat(129);
    for code in ["../user", "a b", "a/b", "a?b", "a\u{1b}[2Jb", long.as_str()] {
        let fx = Fx::new(None);
        let r = fx.run(&["acme"], &format!("{code}\n\n"), &[]);
        assert_code_rejected(&r);
    }
    // The longest code accepted is 128 characters.
    let fx = Fx::new(None);
    let ok = "A-_9".repeat(32);
    let r = fx.run(&["acme"], &format!("{ok}\n\n"), &[]);
    assert_eq!(r.rc, 0, "{}", r.err);
    assert!(r.gh.contains(&format!("/app-manifests/{ok}/conversions")));
}

/// A pseudo-terminal pair, so the token prompt really runs `stty -echo`.
mod pty {
    use std::os::raw::{c_char, c_int};
    extern "C" {
        fn grantpt(fd: c_int) -> c_int;
        fn unlockpt(fd: c_int) -> c_int;
        fn ptsname(fd: c_int) -> *mut c_char;
        fn tcgetattr(fd: c_int, t: *mut u8) -> c_int;
        pub fn kill(pid: c_int, sig: c_int) -> c_int;
        pub fn signal(sig: c_int, handler: usize) -> usize;
    }

    #[cfg(target_os = "macos")]
    const O_NOCTTY: i32 = 0x20000;
    #[cfg(not(target_os = "macos"))]
    const O_NOCTTY: i32 = 0o400;

    /// Opaque, over-sized storage for `struct termios` (72 bytes on macOS,
    /// 60 on glibc): compared whole, so no field layout is assumed.
    pub type Termios = [u64; 32];

    pub fn termios(f: &std::fs::File) -> Termios {
        use std::os::fd::AsRawFd;
        let mut t: Termios = [0; 32];
        // SAFETY: t is larger than any platform's struct termios.
        let rc = unsafe { tcgetattr(f.as_raw_fd(), t.as_mut_ptr() as *mut u8) };
        assert_eq!(rc, 0, "tcgetattr: {}", std::io::Error::last_os_error());
        t
    }

    /// (master, slave)
    pub fn open() -> (std::fs::File, std::fs::File) {
        use std::os::fd::AsRawFd;
        use std::os::unix::fs::OpenOptionsExt;
        let master = std::fs::OpenOptions::new()
            .read(true)
            .write(true)
            .custom_flags(O_NOCTTY)
            .open("/dev/ptmx")
            .expect("open /dev/ptmx");
        let fd = master.as_raw_fd();
        // SAFETY: plain libc calls on a descriptor we own; ptsname's buffer
        // is copied out before anything else can call it.
        let name = unsafe {
            assert_eq!(grantpt(fd), 0, "grantpt");
            assert_eq!(unlockpt(fd), 0, "unlockpt");
            let p = ptsname(fd);
            assert!(!p.is_null(), "ptsname");
            std::ffi::CStr::from_ptr(p).to_string_lossy().into_owned()
        };
        let slave = std::fs::OpenOptions::new()
            .read(true)
            .write(true)
            .custom_flags(O_NOCTTY)
            .open(&name)
            .unwrap_or_else(|e| panic!("open {name}: {e}"));
        (master, slave)
    }
}

/// create-app with stdin on the pty's slave side, run until its token
/// prompt has turned echo off (the slave's settings differ from `before`).
fn spawn_at_token_prompt(
    fx: &Fx,
    slave: &std::fs::File,
    before: &pty::Termios,
) -> std::process::Child {
    use std::os::unix::process::CommandExt;
    std::os::unix::fs::symlink(find_tool("stty"), fx.sys.join("stty")).unwrap();
    let mut c = cmd(
        &bin("CREATE_APP_BIN"),
        &format!("{}:{}", fx.stubs.display(), fx.sys.display()),
    );
    c.env("GH_LOG", fx.d.join("gh.log"))
        .env("SECRETS_LOG", fx.d.join("secrets.log"))
        .env("OPEN_LOG", fx.d.join("open.log"))
        .env("CONVERSION", CONVERSION)
        .env("TMPDIR", fx.d.join("tmp"))
        .arg("acme")
        .stdin(slave.try_clone().unwrap())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::piped());
    // SAFETY: signal() is async-signal-safe. A test runner that ignores
    // SIGINT would otherwise hand that on and the child would never die.
    unsafe {
        c.pre_exec(|| {
            pty::signal(2, 0);
            Ok(())
        });
    }
    let child = c.spawn().unwrap();
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(30);
    while pty::termios(slave) == *before {
        assert!(
            std::time::Instant::now() < deadline,
            "echo was never turned off at the token prompt"
        );
        std::thread::sleep(std::time::Duration::from_millis(20));
    }
    child
}

// Ctrl-C at the hidden token prompt must not leave the terminal without
// echo: the terminal settings are put back, then the process still dies
// of the SIGINT (so callers see an interrupt, not a clean exit).
#[test]
fn interrupt_at_token_prompt_restores_terminal_echo() {
    use std::os::unix::process::ExitStatusExt;
    let fx = Fx::new(Some("GET /cb?code=abc HTTP/1.1"));
    let (_master, slave) = pty::open();
    let before = pty::termios(&slave);
    let child = spawn_at_token_prompt(&fx, &slave, &before);
    // SAFETY: plain kill(2) on our own child.
    assert_eq!(unsafe { pty::kill(child.id() as i32, 2) }, 0);
    let o = child.wait_with_output().unwrap();

    assert_eq!(o.status.signal(), Some(2), "{:?} {}", o.status, stderr(&o));
    assert!(
        pty::termios(&slave) == before,
        "terminal settings (echo) were not restored after Ctrl-C"
    );
    assert!(read(&fx.d.join("secrets.log"))
        .lines()
        .all(|l| !l.starts_with("PULUMI_ACCESS_TOKEN")));
}

// The normal path: a token typed at the hidden prompt is stored, and the
// terminal is left exactly as it was found (echo back on).
#[test]
fn typed_token_restores_terminal_echo() {
    use std::io::Write;
    let fx = Fx::new(Some("GET /cb?code=abc HTTP/1.1"));
    let (mut master, slave) = pty::open();
    let before = pty::termios(&slave);
    let child = spawn_at_token_prompt(&fx, &slave, &before);
    master.write_all(b"pul-tok\n").unwrap();
    let o = child.wait_with_output().unwrap();

    assert_eq!(code(&o), 0, "{}", stderr(&o));
    assert!(
        read(&fx.d.join("secrets.log")).contains("PULUMI_ACCESS_TOKEN=pul-tok\n"),
        "{}",
        read(&fx.d.join("secrets.log"))
    );
    assert!(
        pty::termios(&slave) == before,
        "terminal settings (echo) were not restored after the token was read"
    );
}

// gap: the shell's temp file comes from mktemp (random, created exclusively),
// not a guessable pid-based name another user could pre-create as a symlink.
#[test]
fn gap_html_temp_file_is_unpredictable() {
    let fx = Fx::new(Some("GET /cb?code=abc HTTP/1.1"));
    let r = fx.run(&["acme"], "\n", &[]);
    let name = Path::new(&r.opened)
        .file_name()
        .unwrap()
        .to_string_lossy()
        .into_owned();
    let mid = name
        .strip_prefix("pulumi-create-app.")
        .and_then(|s| s.strip_suffix(".html"))
        .unwrap_or_else(|| panic!("unexpected name {name}"));
    assert_eq!(mid.len(), 6, "{name}");
    assert!(mid.chars().all(|c| c.is_ascii_alphanumeric()), "{name}");
    assert!(mid.parse::<u64>().is_err(), "looks like a pid: {name}");
    assert!(
        r.opened
            .starts_with(&fx.d.join("tmp").display().to_string()),
        "{}",
        r.opened
    );
}

// gap: under `set -euo pipefail` a failing gh write exits with gh's status.
#[test]
fn gap_gh_write_exit_code_propagates() {
    let fx = Fx::new(Some("GET /cb?code=abc HTTP/1.1"));
    let r = fx.run(&["acme"], "\n", &[("VARSET_RC", "4")]);
    assert_eq!(r.rc, 4);
    let fx = Fx::new(Some("GET /cb?code=abc HTTP/1.1"));
    let r = fx.run(&["acme"], "\n", &[("SECSET_RC", "6")]);
    assert_eq!(r.rc, 6);
}

// gap: `open`'s own output is not hidden by the shell.
#[test]
fn gap_open_output_is_shown() {
    let fx = Fx::new(Some("GET /cb?code=abc HTTP/1.1"));
    let r = fx.run(&["acme"], "\n", &[]);
    assert!(r.out.contains("opened\n"), "{}", r.out);
}

// gap: `read -rs` strips surrounding blanks from the token, like every other read.
#[test]
fn gap_token_is_trimmed_like_read() {
    let fx = Fx::new(Some("GET /cb?code=abc HTTP/1.1"));
    let r = fx.run(&["acme"], "  pul-tok \t\n", &[]);
    assert!(
        r.secrets.contains("PULUMI_ACCESS_TOKEN=pul-tok\n"),
        "{}",
        r.secrets
    );
}

// Deliberate divergence: the shell needed jq to parse the conversion; the
// Rust port parses JSON itself, so a machine without jq is not refused.
#[test]
fn jq_is_not_required() {
    let fx = Fx::new(Some("GET /cb?code=abc HTTP/1.1"));
    let r = fx.run(&["acme"], "\n", &[]);
    assert_eq!(r.rc, 0, "{}", r.err);
    assert!(!r.err.contains("jq not found"), "{}", r.err);
}
