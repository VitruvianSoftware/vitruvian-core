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

use serde_json::Value;
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Output, Stdio};
use std::sync::atomic::{AtomicUsize, Ordering};

static DIR_COUNTER: AtomicUsize = AtomicUsize::new(0);

fn bin_path() -> PathBuf {
    let raw = std::env::var("CI_INTEGRATION_BIN").expect("CI_INTEGRATION_BIN not set");
    let p = PathBuf::from(&raw);
    let abs = if p.is_absolute() {
        p
    } else {
        std::env::current_dir().unwrap().join(p)
    };
    assert!(abs.is_file(), "binary missing at {}", abs.display());
    abs
}

fn tempdir(tag: &str) -> PathBuf {
    let base = std::env::var("TEST_TMPDIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| std::env::temp_dir());
    let d = base.join(format!(
        "{tag}-{}-{}",
        std::process::id(),
        DIR_COUNTER.fetch_add(1, Ordering::SeqCst)
    ));
    let _ = fs::remove_dir_all(&d);
    fs::create_dir_all(&d).unwrap();
    d
}

fn install_fake_curl(dir: &Path) -> PathBuf {
    let script = dir.join("curl");
    let body = r#"#!/bin/sh
set -eu
n=0
if [ -f "$FAKE_STATE/count" ]; then
  n=$(cat "$FAKE_STATE/count")
fi
n=$((n + 1))
printf '%s' "$n" > "$FAKE_STATE/count"
printf '%s' "$*" > "$FAKE_STATE/call_${n}_argv"
printf '%s' "${SENTRY_TOKEN:-}" > "$FAKE_STATE/call_${n}_envtoken"
printf '%s' "${SENTRY_CI_TOKEN:-}" > "$FAKE_STATE/call_${n}_envcitoken"
cat > "$FAKE_STATE/call_${n}_stdin"

jar=$(sed -n 's/^cookie-jar = "\(.*\)"$/\1/p' "$FAKE_STATE/call_${n}_stdin")
if [ -n "$jar" ] && [ -f "$jar" ]; then
  ls -ld "$jar" > "$FAKE_STATE/call_${n}_jarmode"
fi

case "$FAKE_SCENARIO:$n" in
  create_ok:1)
    printf '[{"name":"vitruvian-ci","slug":"vitruvian-ci-pub","status":"unpublished","scopes":["org:read"]}]\n__sentry_pagerduty_install_status__200'
    ;;
  create_ok:2)
    printf '{"name":"vitruvian-ci","slug":"vitruvian-ci-abc123","status":"internal","scopes":["alerts:read","alerts:write","org:read","org:write","project:read","project:write","team:read","team:write"]}\n__sentry_pagerduty_install_status__201'
    ;;
  already_present:1)
    printf '[{"name":"vitruvian-ci","slug":"vitruvian-ci-111111","status":"internal","scopes":["team:write","team:read","project:write","project:read","org:write","org:read","alerts:write","alerts:read"]}]\n__sentry_pagerduty_install_status__200'
    ;;
  scope_update:1)
    printf '[{"name":"vitruvian-ci","slug":"vitruvian-ci-222222","status":"internal","scopes":["alerts:read","alerts:write","org:read","org:write","project:read"]}]\n__sentry_pagerduty_install_status__200'
    ;;
  scope_update:2)
    printf '{"name":"vitruvian-ci","slug":"vitruvian-ci-222222","status":"internal","scopes":["alerts:read","alerts:write","org:read","org:write","project:read","project:write","team:read","team:write"]}\n__sentry_pagerduty_install_status__200'
    ;;
  check_ok:1)
    printf '[{"id":"1","slug":"backstage"}]\n__sentry_pagerduty_install_status__200'
    ;;
  check_ok_scopes:1)
    printf '{"scopes":["project:read","org:read"]}\n__sentry_pagerduty_install_status__200'
    ;;
  check_denied_403:1)
    printf '{"detail":"You do not have permission to perform this action."}\n__sentry_pagerduty_install_status__403'
    ;;
  check_denied_401:1)
    printf '{"detail":"Invalid token"}\n__sentry_pagerduty_install_status__401'
    ;;
  echo_token_stderr:1)
    tok=$(sed -n 's/^header = "Authorization: Bearer \(.*\)"$/\1/p' "$FAKE_STATE/call_${n}_stdin")
    printf 'curl: failed auth header %s\n' "$tok" >&2
    exit 1
    ;;
  *)
    printf 'unexpected scenario/call %s:%s\n' "$FAKE_SCENARIO" "$n" >&2
    exit 1
    ;;
esac
"#;
    fs::write(&script, body).unwrap();
    fs::set_permissions(&script, fs::Permissions::from_mode(0o755)).unwrap();
    script
}

fn run_cmd(mut cmd: Command) -> Output {
    cmd.stdin(Stdio::null())
        .output()
        .expect("failed to execute ci-integration")
}

#[test]
fn help_prints_usage_without_tokens_or_removed_flags() {
    let mut cmd = Command::new(bin_path());
    cmd.env_clear().arg("--help");
    let out = run_cmd(cmd);
    assert_eq!(out.status.code(), Some(0));
    let stdout = String::from_utf8_lossy(&out.stdout);
    assert!(stdout.contains("--name"), "{stdout}");
    assert!(stdout.contains("--check"), "{stdout}");
    assert!(stdout.contains("SENTRY_TOKEN"), "{stdout}");
    assert!(stdout.contains("SENTRY_CI_TOKEN"), "{stdout}");
    assert!(!stdout.contains("--out"), "{stdout}");
    assert!(!stdout.contains("--force"), "{stdout}");
    assert!(!stdout.contains("--revoke-others"), "{stdout}");
    assert!(!stdout.contains("SENTRY_USER"), "{stdout}");
    assert!(!stdout.contains("SENTRY_PASSWORD"), "{stdout}");
}

#[test]
fn missing_or_invalid_tokens_and_removed_flags_fail_without_leaking_secrets() {
    for removed in ["--out", "--force", "--revoke-others"] {
        let mut cmd = Command::new(bin_path());
        cmd.env_clear().arg(removed);
        let out = run_cmd(cmd);
        assert_eq!(out.status.code(), Some(2));
    }

    let org_secret = "sntrys_org_token_do_not_echo";
    let mut org_tok = Command::new(bin_path());
    org_tok
        .env_clear()
        .env("SENTRY_CURL_BIN", "/nonexistent/curl")
        .env("SENTRY_TOKEN", org_secret);
    let out = run_cmd(org_tok);
    assert_ne!(out.status.code(), Some(0));
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert!(stderr.contains("sntryu_"), "{stderr}");
    assert!(!stderr.contains(org_secret));
    assert!(!String::from_utf8_lossy(&out.stdout).contains(org_secret));

    let mut missing_check = Command::new(bin_path());
    missing_check
        .env_clear()
        .env("SENTRY_CURL_BIN", "/nonexistent/curl")
        .arg("--check");
    let out = run_cmd(missing_check);
    assert_ne!(out.status.code(), Some(0));
    assert!(String::from_utf8_lossy(&out.stderr).contains("SENTRY_CI_TOKEN"));

    let bad_ci = "bad_ci_secret\nwith_newline";
    let mut bad_check = Command::new(bin_path());
    bad_check
        .env_clear()
        .env("SENTRY_CURL_BIN", "/nonexistent/curl")
        .env("SENTRY_CI_TOKEN", bad_ci)
        .arg("--check");
    let out = run_cmd(bad_check);
    assert_ne!(out.status.code(), Some(0));
    assert!(!String::from_utf8_lossy(&out.stderr).contains(bad_ci));
    assert!(!String::from_utf8_lossy(&out.stdout).contains(bad_ci));
}

#[test]
fn create_path_creates_app_with_eight_scopes_prints_ui_link_and_protects_token() {
    let work = tempdir("create-ok");
    let bin_dir = work.join("bin");
    let state_dir = work.join("state");
    let tmp_dir = work.join("tmp");
    fs::create_dir_all(&bin_dir).unwrap();
    fs::create_dir_all(&state_dir).unwrap();
    fs::create_dir_all(&tmp_dir).unwrap();
    install_fake_curl(&bin_dir);

    let caller_tok = "sntryu_caller_secret_create_123";
    let mut cmd = Command::new(bin_path());
    cmd.env_clear()
        .env("PATH", format!("{}:/bin:/usr/bin", bin_dir.display()))
        .env("TMPDIR", &tmp_dir)
        .env("SENTRY_TOKEN", caller_tok)
        .env("FAKE_STATE", &state_dir)
        .env("FAKE_SCENARIO", "create_ok")
        .args(["--name", "vitruvian-ci"]);
    let out = run_cmd(cmd);
    assert_eq!(
        out.status.code(),
        Some(0),
        "stderr: {}",
        String::from_utf8_lossy(&out.stderr)
    );
    assert!(out.stderr.is_empty());

    let stdout = String::from_utf8(out.stdout).unwrap();
    assert_eq!(
        stdout,
        "created: slug=vitruvian-ci-abc123 scopes=alerts:read,alerts:write,org:read,org:write,project:read,project:write,team:read,team:write ui=https://sentry.lab.ipv1337.dev/settings/sentry/developer-settings/vitruvian-ci-abc123/\n"
    );
    assert!(!stdout.contains(caller_tok));
    assert_eq!(fs::read_to_string(state_dir.join("count")).unwrap(), "2");

    for call in 1..=2 {
        assert_eq!(
            fs::read_to_string(state_dir.join(format!("call_{call}_argv"))).unwrap(),
            "-q -sS -K -"
        );
        assert!(
            fs::read_to_string(state_dir.join(format!("call_{call}_envtoken")))
                .unwrap()
                .is_empty()
        );
        assert!(
            fs::read_to_string(state_dir.join(format!("call_{call}_envcitoken")))
                .unwrap()
                .is_empty()
        );
        let jarmode = fs::read_to_string(state_dir.join(format!("call_{call}_jarmode"))).unwrap();
        assert!(jarmode.starts_with("-rw-------"), "{jarmode}");
    }

    let cfg2 = fs::read_to_string(state_dir.join("call_2_stdin")).unwrap();
    assert!(cfg2.contains("request = \"POST\""));
    assert!(cfg2.contains("url = \"https://sentry.lab.ipv1337.dev/api/0/sentry-apps/\""));
    let data_line = cfg2
        .lines()
        .find(|l| l.starts_with("data-binary = "))
        .unwrap();
    let raw_payload: String =
        serde_json::from_str(data_line.strip_prefix("data-binary = ").unwrap()).unwrap();
    let payload: Value = serde_json::from_str(&raw_payload).unwrap();
    assert_eq!(payload["name"], "vitruvian-ci");
    assert_eq!(payload["organization"], "sentry");
    assert_eq!(payload["isInternal"], true);
    assert_eq!(payload["verifyInstall"], false);
    assert_eq!(payload["events"], serde_json::json!([]));
    assert_eq!(payload["author"], "Vitruvian Software");
    assert_eq!(
        payload["overview"],
        "CI applies infrastructure/pulumi/platform/sentry and infrastructure/pulumi/platform/sentry-pagerduty. Managed by //tools/sentry:ci-integration."
    );
    assert_eq!(
        payload["scopes"],
        serde_json::json!([
            "alerts:read",
            "alerts:write",
            "org:read",
            "org:write",
            "project:read",
            "project:write",
            "team:read",
            "team:write"
        ])
    );

    if !tmp_dir.to_string_lossy().contains('=') {
        assert_eq!(fs::read_dir(&tmp_dir).unwrap().count(), 0);
    }
}

#[test]
fn already_present_path_skips_create_and_put() {
    let work = tempdir("present-ok");
    let bin_dir = work.join("bin");
    let state_dir = work.join("state");
    let tmp_dir = work.join("tmp");
    fs::create_dir_all(&bin_dir).unwrap();
    fs::create_dir_all(&state_dir).unwrap();
    fs::create_dir_all(&tmp_dir).unwrap();
    install_fake_curl(&bin_dir);

    let caller = "sntryu_present_caller";
    let mut cmd = Command::new(bin_path());
    cmd.env_clear()
        .env("PATH", format!("{}:/bin:/usr/bin", bin_dir.display()))
        .env("TMPDIR", &tmp_dir)
        .env("SENTRY_TOKEN", caller)
        .env("FAKE_STATE", &state_dir)
        .env("FAKE_SCENARIO", "already_present");
    let out = run_cmd(cmd);
    assert_eq!(out.status.code(), Some(0));
    assert!(out.stderr.is_empty());
    assert_eq!(fs::read_to_string(state_dir.join("count")).unwrap(), "1");
    let stdout = String::from_utf8(out.stdout).unwrap();
    assert_eq!(
        stdout,
        "unchanged: slug=vitruvian-ci-111111 scopes=alerts:read,alerts:write,org:read,org:write,project:read,project:write,team:read,team:write ui=https://sentry.lab.ipv1337.dev/settings/sentry/developer-settings/vitruvian-ci-111111/\n"
    );
    assert!(!stdout.contains(caller));
}

#[test]
fn scope_update_path_puts_scopes_and_prints_ui_link() {
    let work = tempdir("scope-update");
    let bin_dir = work.join("bin");
    let state_dir = work.join("state");
    let tmp_dir = work.join("tmp");
    fs::create_dir_all(&bin_dir).unwrap();
    fs::create_dir_all(&state_dir).unwrap();
    fs::create_dir_all(&tmp_dir).unwrap();
    install_fake_curl(&bin_dir);

    let caller = "sntryu_update_caller";
    let mut cmd = Command::new(bin_path());
    cmd.env_clear()
        .env("PATH", format!("{}:/bin:/usr/bin", bin_dir.display()))
        .env("TMPDIR", &tmp_dir)
        .env("SENTRY_TOKEN", caller)
        .env("FAKE_STATE", &state_dir)
        .env("FAKE_SCENARIO", "scope_update");
    let out = run_cmd(cmd);
    assert_eq!(out.status.code(), Some(0));
    assert!(out.stderr.is_empty());
    assert_eq!(fs::read_to_string(state_dir.join("count")).unwrap(), "2");

    let cfg2 = fs::read_to_string(state_dir.join("call_2_stdin")).unwrap();
    assert!(cfg2.contains("request = \"PUT\""));
    assert!(cfg2.contains(
        "url = \"https://sentry.lab.ipv1337.dev/api/0/sentry-apps/vitruvian-ci-222222/\""
    ));
    let data_line = cfg2
        .lines()
        .find(|l| l.starts_with("data-binary = "))
        .unwrap();
    let raw_payload: String =
        serde_json::from_str(data_line.strip_prefix("data-binary = ").unwrap()).unwrap();
    let payload: Value = serde_json::from_str(&raw_payload).unwrap();
    assert_eq!(
        payload["scopes"],
        serde_json::json!([
            "alerts:read",
            "alerts:write",
            "org:read",
            "org:write",
            "project:read",
            "project:write",
            "team:read",
            "team:write"
        ])
    );

    let stdout = String::from_utf8(out.stdout).unwrap();
    assert_eq!(
        stdout,
        "updated: slug=vitruvian-ci-222222 scopes=alerts:read,alerts:write,org:read,org:write,project:read,project:write,team:read,team:write ui=https://sentry.lab.ipv1337.dev/settings/sentry/developer-settings/vitruvian-ci-222222/\n"
    );
    assert!(!stdout.contains(caller));
}

#[test]
fn check_ok_verifies_ci_token_without_exposing_secret() {
    let work = tempdir("check-ok");
    let bin_dir = work.join("bin");
    let state_dir = work.join("state");
    let tmp_dir = work.join("tmp");
    fs::create_dir_all(&bin_dir).unwrap();
    fs::create_dir_all(&state_dir).unwrap();
    fs::create_dir_all(&tmp_dir).unwrap();
    install_fake_curl(&bin_dir);

    let ci_tok = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
    let mut cmd = Command::new(bin_path());
    cmd.env_clear()
        .env("PATH", format!("{}:/bin:/usr/bin", bin_dir.display()))
        .env("TMPDIR", &tmp_dir)
        .env("SENTRY_CI_TOKEN", ci_tok)
        .env("FAKE_STATE", &state_dir)
        .env("FAKE_SCENARIO", "check_ok")
        .arg("--check");
    let out = run_cmd(cmd);
    assert_eq!(out.status.code(), Some(0));
    assert!(out.stderr.is_empty());
    assert_eq!(String::from_utf8(out.stdout).unwrap(), "ok\n");

    assert_eq!(fs::read_to_string(state_dir.join("count")).unwrap(), "1");
    assert_eq!(
        fs::read_to_string(state_dir.join("call_1_argv")).unwrap(),
        "-q -sS -K -"
    );
    assert!(fs::read_to_string(state_dir.join("call_1_envcitoken"))
        .unwrap()
        .is_empty());
    let cfg1 = fs::read_to_string(state_dir.join("call_1_stdin")).unwrap();
    assert!(cfg1.contains("request = \"GET\""));
    assert!(cfg1
        .contains("url = \"https://sentry.lab.ipv1337.dev/api/0/organizations/sentry/projects/\""));
    assert!(cfg1.contains(&format!("header = \"Authorization: Bearer {ci_tok}\"")));

    // Also cover optional scopes printed when returned by the endpoint.
    let state_scopes = work.join("state_scopes");
    fs::create_dir_all(&state_scopes).unwrap();
    let mut cmd_scopes = Command::new(bin_path());
    cmd_scopes
        .env_clear()
        .env("PATH", format!("{}:/bin:/usr/bin", bin_dir.display()))
        .env("TMPDIR", &tmp_dir)
        .env("SENTRY_CI_TOKEN", ci_tok)
        .env("FAKE_STATE", &state_scopes)
        .env("FAKE_SCENARIO", "check_ok_scopes")
        .arg("--check");
    let out_scopes = run_cmd(cmd_scopes);
    assert_eq!(out_scopes.status.code(), Some(0));
    assert_eq!(
        String::from_utf8(out_scopes.stdout).unwrap(),
        "ok scopes=org:read,project:read\n"
    );

    if !tmp_dir.to_string_lossy().contains('=') {
        assert_eq!(fs::read_dir(&tmp_dir).unwrap().count(), 0);
    }
}

#[test]
fn check_denied_403_and_401_exit_nonzero_and_never_leak_token_or_headers() {
    for (scenario, expected_status) in [("check_denied_403", "403"), ("check_denied_401", "401")] {
        let work = tempdir(scenario);
        let bin_dir = work.join("bin");
        let state_dir = work.join("state");
        let tmp_dir = work.join("tmp");
        fs::create_dir_all(&bin_dir).unwrap();
        fs::create_dir_all(&state_dir).unwrap();
        fs::create_dir_all(&tmp_dir).unwrap();
        install_fake_curl(&bin_dir);

        let ci_tok = "ci_denied_secret_probe_999";
        let mut cmd = Command::new(bin_path());
        cmd.env_clear()
            .env("PATH", format!("{}:/bin:/usr/bin", bin_dir.display()))
            .env("TMPDIR", &tmp_dir)
            .env("SENTRY_CI_TOKEN", ci_tok)
            .env("FAKE_STATE", &state_dir)
            .env("FAKE_SCENARIO", scenario)
            .arg("--check");
        let out = run_cmd(cmd);
        assert_ne!(out.status.code(), Some(0));
        let stdout = String::from_utf8(out.stdout).unwrap();
        let stderr = String::from_utf8(out.stderr).unwrap();
        assert_eq!(stdout, "denied\n");
        assert!(stderr.contains(expected_status), "{stderr}");
        assert!(!stderr.contains("Authorization:"), "{stderr}");
        assert!(!stderr.contains(ci_tok), "{stderr}");
        assert!(!stdout.contains(ci_tok), "{stdout}");
        if !tmp_dir.to_string_lossy().contains('=') {
            assert_eq!(fs::read_dir(&tmp_dir).unwrap().count(), 0);
        }
    }

    // Curl stderr echoing the Bearer token is scrubbed in both reconcile and --check modes.
    for (env_name, extra_arg) in [("SENTRY_TOKEN", None), ("SENTRY_CI_TOKEN", Some("--check"))] {
        let work_red = tempdir(&format!("redact-{env_name}"));
        let bin_red = work_red.join("bin");
        let state_red = work_red.join("state");
        let tmp_red = work_red.join("tmp");
        fs::create_dir_all(&bin_red).unwrap();
        fs::create_dir_all(&state_red).unwrap();
        fs::create_dir_all(&tmp_red).unwrap();
        install_fake_curl(&bin_red);

        let leak_probe = if env_name == "SENTRY_TOKEN" {
            "sntryu_secret_stderr_probe_777"
        } else {
            "ci_secret_stderr_probe_888"
        };
        let mut cmd_red = Command::new(bin_path());
        cmd_red
            .env_clear()
            .env("PATH", format!("{}:/bin:/usr/bin", bin_red.display()))
            .env("TMPDIR", &tmp_red)
            .env(env_name, leak_probe)
            .env("FAKE_STATE", &state_red)
            .env("FAKE_SCENARIO", "echo_token_stderr");
        if let Some(arg) = extra_arg {
            cmd_red.arg(arg);
        }
        let out_red = run_cmd(cmd_red);
        assert_ne!(out_red.status.code(), Some(0));
        let stderr_red = String::from_utf8_lossy(&out_red.stderr);
        let stdout_red = String::from_utf8_lossy(&out_red.stdout);
        assert!(!stderr_red.contains(leak_probe), "{stderr_red}");
        assert!(!stdout_red.contains(leak_probe), "{stdout_red}");
        assert!(!stderr_red.contains("Authorization:"), "{stderr_red}");
        assert!(stderr_red.contains("<redacted>"), "{stderr_red}");
        assert!(fs::read_to_string(state_red.join("call_1_envtoken"))
            .unwrap()
            .is_empty());
        assert!(fs::read_to_string(state_red.join("call_1_envcitoken"))
            .unwrap()
            .is_empty());
    }
}
