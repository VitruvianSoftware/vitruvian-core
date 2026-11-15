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
    let raw = std::env::var("PAGERDUTY_INSTALL_BIN").expect("PAGERDUTY_INSTALL_BIN not set");
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
cat > "$FAKE_STATE/call_${n}_stdin"

jar=$(sed -n 's/^cookie-jar = "\(.*\)"$/\1/p' "$FAKE_STATE/call_${n}_stdin")
if [ -n "$jar" ] && [ -f "$jar" ]; then
  ls -ld "$jar" > "$FAKE_STATE/call_${n}_jarmode"
  cat "$jar" > "$FAKE_STATE/call_${n}_jar_before"
fi

case "$FAKE_SCENARIO:$n" in
  install_success:1)
    printf '[]\n__sentry_pagerduty_install_status__200'
    ;;
  install_success:2)
    printf 'sentry.lab.ipv1337.dev\tFALSE\t/\tTRUE\t0\tsessionid\tdjango_sess_42\n' >> "$jar"
    printf '{}\n__sentry_pagerduty_install_status__200'
    ;;
  install_success:3)
    if ! grep -q 'django_sess_42' "$jar"; then
      printf 'missing session cookie on step 3\n' >&2
      exit 1
    fi
    printf '{}\n__sentry_pagerduty_install_status__200'
    ;;
  install_success:4)
    printf '[{"id":12,"name":"Vitruvian Software"}]\n__sentry_pagerduty_install_status__200'
    ;;
  already_installed:1)
    printf '[{"id":"7","name":"Vitruvian Software"}]\n__sentry_pagerduty_install_status__200'
    ;;
  initialize_403:1)
    printf '[]\n__sentry_pagerduty_install_status__200'
    ;;
  initialize_403:2)
    printf '{"detail":"Permission denied"}\n__sentry_pagerduty_install_status__403'
    ;;
  echo_token_stderr:1)
    tok=$(sed -n 's/^header = "Authorization: Bearer \(.*\)"$/\1/p' "$FAKE_STATE/call_${n}_stdin")
    if [ -z "$tok" ]; then
      printf 'missing bearer token in stdin config\n' >&2
      exit 2
    fi
    printf 'curl: auth header rejected for %s\n' "$tok" >&2
    exit 1
    ;;
  verify_empty:1)
    printf '[]\n__sentry_pagerduty_install_status__200'
    ;;
  verify_empty:2)
    printf '{}\n__sentry_pagerduty_install_status__200'
    ;;
  verify_empty:3)
    printf '{}\n__sentry_pagerduty_install_status__200'
    ;;
  verify_empty:4)
    printf '[]\n__sentry_pagerduty_install_status__200'
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
        .expect("failed to execute pagerduty-install")
}

#[test]
fn help_prints_usage_without_token_or_required_flags() {
    let mut cmd = Command::new(bin_path());
    cmd.env_clear().arg("--help");
    let out = run_cmd(cmd);
    assert_eq!(out.status.code(), Some(0));
    let stdout = String::from_utf8_lossy(&out.stdout);
    assert!(stdout.contains("--subdomain"), "{stdout}");
    assert!(stdout.contains("--name"), "{stdout}");
    assert!(stdout.contains("SENTRY_TOKEN"), "{stdout}");
}

#[test]
fn missing_or_non_user_token_fails_without_leaking_token() {
    let mut missing = Command::new(bin_path());
    missing.env_clear().args([
        "--subdomain",
        "vitruviansoftware",
        "--name",
        "Vitruvian Software",
    ]);
    let out = run_cmd(missing);
    assert_ne!(out.status.code(), Some(0));
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert!(stderr.contains("sentry.lab.ipv1337.dev"), "{stderr}");
    assert!(stderr.contains("SENTRY_TOKEN"), "{stderr}");

    let secret = "sntrys_org_token_do_not_echo";
    let mut org_tok = Command::new(bin_path());
    org_tok
        .env_clear()
        .env("SENTRY_CURL_BIN", "/nonexistent/curl")
        .env("SENTRY_TOKEN", secret)
        .args([
            "--subdomain",
            "vitruviansoftware",
            "--name",
            "Vitruvian Software",
        ]);
    let out = run_cmd(org_tok);
    assert_ne!(out.status.code(), Some(0));
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert!(stderr.contains("sntryu_"), "{stderr}");
    assert!(!stderr.contains(secret), "token leaked in stderr");
    assert!(
        !String::from_utf8_lossy(&out.stdout).contains(secret),
        "token leaked in stdout"
    );
}

#[test]
fn fake_curl_full_install_verifies_argv_0600_cookie_jar_session_and_cleanup() {
    let work = tempdir("install-ok");
    let bin_dir = work.join("bin");
    let state_dir = work.join("state");
    let tmp_dir = work.join("tmp");
    fs::create_dir_all(&bin_dir).unwrap();
    fs::create_dir_all(&state_dir).unwrap();
    fs::create_dir_all(&tmp_dir).unwrap();
    install_fake_curl(&bin_dir);

    let token = "sntryu_fake_user_token_98765";
    let path_env = format!("{}:/bin:/usr/bin", bin_dir.display());
    let mut cmd = Command::new(bin_path());
    cmd.env_clear()
        .env("PATH", path_env)
        .env("TMPDIR", &tmp_dir)
        .env("SENTRY_TOKEN", token)
        .env("FAKE_STATE", &state_dir)
        .env("FAKE_SCENARIO", "install_success")
        .args([
            "--subdomain",
            "vitruviansoftware",
            "--name",
            "Vitruvian Software",
        ]);
    let out = run_cmd(cmd);
    assert_eq!(
        out.status.code(),
        Some(0),
        "stderr: {}",
        String::from_utf8_lossy(&out.stderr)
    );
    assert_eq!(
        String::from_utf8_lossy(&out.stdout),
        "installed: id=12 name=Vitruvian Software\n"
    );
    assert!(out.stderr.is_empty());

    assert_eq!(fs::read_to_string(state_dir.join("count")).unwrap(), "4");

    for call in 1..=4 {
        let argv = fs::read_to_string(state_dir.join(format!("call_{call}_argv"))).unwrap();
        assert_eq!(argv, "-q -sS -K -", "call {call} exposed unexpected argv");
        assert!(!argv.contains(token));
        let env_token =
            fs::read_to_string(state_dir.join(format!("call_{call}_envtoken"))).unwrap();
        assert!(
            env_token.is_empty(),
            "call {call}: SENTRY_TOKEN leaked into curl's environment"
        );

        let jarmode = fs::read_to_string(state_dir.join(format!("call_{call}_jarmode"))).unwrap();
        assert!(
            jarmode.starts_with("-rw-------"),
            "cookie jar on call {call} must be mode 0600, got: {jarmode}"
        );

        let cfg = fs::read_to_string(state_dir.join(format!("call_{call}_stdin"))).unwrap();
        assert!(
            cfg.contains(&format!("header = \"Authorization: Bearer {token}\"")),
            "call {call} missing Authorization header in stdin config"
        );
    }

    // Verify step 2 -> step 3 session cookie propagation and exact payloads.
    let jar_before_3 = fs::read_to_string(state_dir.join("call_3_jar_before")).unwrap();
    assert!(jar_before_3.contains("django_sess_42"));

    let cfg2 = fs::read_to_string(state_dir.join("call_2_stdin")).unwrap();
    assert!(cfg2.contains("request = \"POST\""));
    assert!(
        cfg2.contains(r#"data-binary = "{\"action\":\"initialize\",\"provider\":\"pagerduty\"}""#)
    );

    let cfg3 = fs::read_to_string(state_dir.join("call_3_stdin")).unwrap();
    let data_line = cfg3
        .lines()
        .find(|l| l.starts_with("data-binary = "))
        .expect("step 3 missing data-binary");
    let quoted = data_line.strip_prefix("data-binary = ").unwrap();
    let raw_payload: String = serde_json::from_str(quoted).unwrap();
    assert_eq!(
        raw_payload,
        r#"{"config":"{\"account\":{\"subdomain\":\"vitruviansoftware\",\"name\":\"Vitruvian Software\"},\"integration_keys\":[]}"}"#
    );
    let parsed_outer: Value = serde_json::from_str(&raw_payload).unwrap();
    assert!(parsed_outer["config"].is_string());

    // Temp directory holding the cookie jar must be cleaned up on exit.
    if !tmp_dir.to_string_lossy().contains('=') {
        assert_eq!(fs::read_dir(&tmp_dir).unwrap().count(), 0);
    }
}

#[test]
fn fake_curl_already_installed_and_error_exit_clean_up_temp_dir() {
    // 1. Idempotent already-installed path
    let work = tempdir("already");
    let bin_dir = work.join("bin");
    let state_dir = work.join("state");
    let tmp_dir = work.join("tmp");
    fs::create_dir_all(&bin_dir).unwrap();
    fs::create_dir_all(&state_dir).unwrap();
    fs::create_dir_all(&tmp_dir).unwrap();
    install_fake_curl(&bin_dir);

    let path_env = format!("{}:/bin:/usr/bin", bin_dir.display());
    let mut cmd = Command::new(bin_path());
    cmd.env_clear()
        .env("PATH", &path_env)
        .env("TMPDIR", &tmp_dir)
        .env("SENTRY_TOKEN", "sntryu_fake_user_token")
        .env("FAKE_STATE", &state_dir)
        .env("FAKE_SCENARIO", "already_installed")
        .args([
            "--subdomain",
            "vitruviansoftware",
            "--name",
            "Vitruvian Software",
        ]);
    let out = run_cmd(cmd);
    assert_eq!(out.status.code(), Some(0));
    assert_eq!(
        String::from_utf8_lossy(&out.stdout),
        "already installed: id=7 name=Vitruvian Software\n"
    );
    assert_eq!(fs::read_to_string(state_dir.join("count")).unwrap(), "1");
    if !tmp_dir.to_string_lossy().contains('=') {
        assert_eq!(fs::read_dir(&tmp_dir).unwrap().count(), 0);
    }

    // 2. Non-zero error path (403 on initialize) also removes temp dir
    let work_err = tempdir("err403");
    let bin_err = work_err.join("bin");
    let state_err = work_err.join("state");
    let tmp_err = work_err.join("tmp");
    fs::create_dir_all(&bin_err).unwrap();
    fs::create_dir_all(&state_err).unwrap();
    fs::create_dir_all(&tmp_err).unwrap();
    install_fake_curl(&bin_err);

    let path_err = format!("{}:/bin:/usr/bin", bin_err.display());
    let mut cmd_err = Command::new(bin_path());
    cmd_err
        .env_clear()
        .env("PATH", path_err)
        .env("TMPDIR", &tmp_err)
        .env("SENTRY_TOKEN", "sntryu_fake_user_token")
        .env("FAKE_STATE", &state_err)
        .env("FAKE_SCENARIO", "initialize_403")
        .args([
            "--subdomain",
            "vitruviansoftware",
            "--name",
            "Vitruvian Software",
        ]);
    let out_err = run_cmd(cmd_err);
    assert_ne!(out_err.status.code(), Some(0));
    let stderr = String::from_utf8_lossy(&out_err.stderr);
    assert!(stderr.contains("403"), "{stderr}");
    assert!(stderr.contains("Permission denied"), "{stderr}");
    assert!(stderr.contains("org:integrations"), "{stderr}");
    if !tmp_err.to_string_lossy().contains('=') {
        assert_eq!(fs::read_dir(&tmp_err).unwrap().count(), 0);
    }
}

#[test]
fn missing_curl_binary_fails_without_leaking_token_and_cleans_up_tmpdir() {
    let work = tempdir("missing-curl");
    let tmp_dir = work.join("tmp");
    fs::create_dir_all(&tmp_dir).unwrap();
    let missing_curl = work.join("does-not-exist-curl");
    let token = "sntryu_secret_missing_curl_token_42";

    let mut cmd = Command::new(bin_path());
    cmd.env_clear()
        .env("TMPDIR", &tmp_dir)
        .env("SENTRY_CURL_BIN", &missing_curl)
        .env("SENTRY_TOKEN", token)
        .args([
            "--subdomain",
            "vitruviansoftware",
            "--name",
            "Vitruvian Software",
        ]);
    let out = run_cmd(cmd);
    assert_ne!(out.status.code(), Some(0));

    let stdout = String::from_utf8_lossy(&out.stdout);
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert!(stderr.contains("failed to start"), "{stderr}");
    assert!(!stderr.contains(token), "token leaked in stderr: {stderr}");
    assert!(!stdout.contains(token), "token leaked in stdout: {stdout}");
    if !tmp_dir.to_string_lossy().contains('=') {
        assert_eq!(fs::read_dir(&tmp_dir).unwrap().count(), 0);
    }
}

#[test]
fn fake_curl_token_in_stderr_is_redacted() {
    let work = tempdir("redact-stderr");
    let bin_dir = work.join("bin");
    let state_dir = work.join("state");
    let tmp_dir = work.join("tmp");
    fs::create_dir_all(&bin_dir).unwrap();
    fs::create_dir_all(&state_dir).unwrap();
    fs::create_dir_all(&tmp_dir).unwrap();
    install_fake_curl(&bin_dir);

    let token = "sntryu_secret_stderr_echo_token_99";
    let path_env = format!("{}:/bin:/usr/bin", bin_dir.display());
    let mut cmd = Command::new(bin_path());
    cmd.env_clear()
        .env("PATH", path_env)
        .env("TMPDIR", &tmp_dir)
        .env("SENTRY_TOKEN", token)
        .env("FAKE_STATE", &state_dir)
        .env("FAKE_SCENARIO", "echo_token_stderr")
        .args([
            "--subdomain",
            "vitruviansoftware",
            "--name",
            "Vitruvian Software",
        ]);
    let out = run_cmd(cmd);
    assert_ne!(out.status.code(), Some(0));

    let stdout = String::from_utf8_lossy(&out.stdout);
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert!(!stderr.contains(token), "token leaked in stderr: {stderr}");
    assert!(!stdout.contains(token), "token leaked in stdout: {stdout}");
    assert!(stderr.contains("<redacted>"), "{stderr}");
    if !tmp_dir.to_string_lossy().contains('=') {
        assert_eq!(fs::read_dir(&tmp_dir).unwrap().count(), 0);
    }
}

#[test]
fn fake_curl_step_four_empty_list_fails_with_still_missing() {
    let work = tempdir("verify-empty");
    let bin_dir = work.join("bin");
    let state_dir = work.join("state");
    let tmp_dir = work.join("tmp");
    fs::create_dir_all(&bin_dir).unwrap();
    fs::create_dir_all(&state_dir).unwrap();
    fs::create_dir_all(&tmp_dir).unwrap();
    install_fake_curl(&bin_dir);

    let path_env = format!("{}:/bin:/usr/bin", bin_dir.display());
    let mut cmd = Command::new(bin_path());
    cmd.env_clear()
        .env("PATH", path_env)
        .env("TMPDIR", &tmp_dir)
        .env("SENTRY_TOKEN", "sntryu_fake_user_token_verify")
        .env("FAKE_STATE", &state_dir)
        .env("FAKE_SCENARIO", "verify_empty")
        .args([
            "--subdomain",
            "vitruviansoftware",
            "--name",
            "Vitruvian Software",
        ]);
    let out = run_cmd(cmd);
    assert_eq!(out.status.code(), Some(1));
    assert!(out.stdout.is_empty());

    let stderr = String::from_utf8_lossy(&out.stderr);
    assert!(stderr.contains("still missing"), "{stderr}");
    assert_eq!(fs::read_to_string(state_dir.join("count")).unwrap(), "4");
    if !tmp_dir.to_string_lossy().contains('=') {
        assert_eq!(fs::read_dir(&tmp_dir).unwrap().count(), 0);
    }
}
