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
use std::os::unix::fs::{MetadataExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::process::{Command, Output, Stdio};
use std::sync::atomic::{AtomicUsize, Ordering};

static DIR_COUNTER: AtomicUsize = AtomicUsize::new(0);

fn bin_path() -> PathBuf {
    let raw = std::env::var("CI_TOKEN_BIN").expect("CI_TOKEN_BIN not set");
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
  create_ok:1)
    printf '[{"name":"vitruvian-ci","slug":"vitruvian-ci-pub","status":"unpublished","scopes":["org:read"]}]\n__sentry_pagerduty_install_status__200'
    ;;
  create_ok:2)
    printf '{"name":"vitruvian-ci","slug":"vitruvian-ci-abc123","status":"internal","scopes":["alerts:read","alerts:write","org:read","org:write","project:read","project:write","team:read","team:write"]}\n__sentry_pagerduty_install_status__201'
    ;;
  create_ok:3)
    printf '{"id":"901","token":"sntrya_created_secret_token_xyz"}\n__sentry_pagerduty_install_status__201'
    ;;
  already_present:1)
    printf '[{"name":"vitruvian-ci","slug":"vitruvian-ci-111111","status":"internal","scopes":["team:write","team:read","project:write","project:read","org:write","org:read","alerts:write","alerts:read"]}]\n__sentry_pagerduty_install_status__200'
    ;;
  already_present:2)
    printf '{"id":"902","token":"sntrya_present_secret_token_abc"}\n__sentry_pagerduty_install_status__201'
    ;;
  scope_update:1)
    printf '[{"name":"vitruvian-ci","slug":"vitruvian-ci-222222","status":"internal","scopes":["alerts:read","alerts:write","org:read","org:write","project:read"]}]\n__sentry_pagerduty_install_status__200'
    ;;
  scope_update:2)
    printf '{"name":"vitruvian-ci","slug":"vitruvian-ci-222222","status":"internal","scopes":["alerts:read","alerts:write","org:read","org:write","project:read","project:write","team:read","team:write"]}\n__sentry_pagerduty_install_status__200'
    ;;
  scope_update:3)
    printf '{"id":"903","token":"sntrya_updated_secret_token_def"}\n__sentry_pagerduty_install_status__201'
    ;;
  revoke_others:1)
    printf '[{"name":"vitruvian-ci","slug":"vitruvian-ci-333333","status":"internal","scopes":["alerts:read","alerts:write","org:read","org:write","project:read","project:write","team:read","team:write"]}]\n__sentry_pagerduty_install_status__200'
    ;;
  revoke_others:2)
    printf '{"id":"42","token":"sntrya_new_rotated_token_42"}\n__sentry_pagerduty_install_status__201'
    ;;
  revoke_others:3)
    printf '[{"id":"10","token":null},{"id":"42","token":null},{"id":99,"token":null}]\n__sentry_pagerduty_install_status__200'
    ;;
  revoke_others:4)
    printf '\n__sentry_pagerduty_install_status__204'
    ;;
  revoke_others:5)
    printf '\n__sentry_pagerduty_install_status__204'
    ;;
  token_403:1)
    printf '[{"name":"vitruvian-ci","slug":"vitruvian-ci-555555","status":"internal","scopes":["alerts:read","alerts:write","org:read","org:write","project:read","project:write","team:read","team:write"]}]\n__sentry_pagerduty_install_status__200'
    ;;
  token_403:2)
    printf '{"detail":"Authentication credentials were not provided."}\n__sentry_pagerduty_install_status__403'
    ;;
  masked_token:1)
    printf '[{"name":"vitruvian-ci","slug":"vitruvian-ci-666666","status":"internal","scopes":["alerts:read","alerts:write","org:read","org:write","project:read","project:write","team:read","team:write"]}]\n__sentry_pagerduty_install_status__200'
    ;;
  masked_token:2)
    printf '{"id":"88","token":"****************************************************************"}\n__sentry_pagerduty_install_status__201'
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
        .expect("failed to execute ci-token")
}

#[test]
fn help_prints_usage_without_token_or_required_flags() {
    let mut cmd = Command::new(bin_path());
    cmd.env_clear().arg("--help");
    let out = run_cmd(cmd);
    assert_eq!(out.status.code(), Some(0));
    let stdout = String::from_utf8_lossy(&out.stdout);
    assert!(stdout.contains("--name"), "{stdout}");
    assert!(stdout.contains("--out"), "{stdout}");
    assert!(stdout.contains("--revoke-others"), "{stdout}");
    assert!(stdout.contains("SENTRY_TOKEN"), "{stdout}");
    assert!(!stdout.contains("SENTRY_USER"), "{stdout}");
    assert!(!stdout.contains("SENTRY_PASSWORD"), "{stdout}");
}

#[test]
fn missing_or_non_user_token_fails_without_leaking_token_and_ignores_user_password() {
    let work = tempdir("token-guard");
    let out_file = work.join("ci_token");
    let pass_probe = "ignored_password_should_never_auth";
    let mut missing = Command::new(bin_path());
    missing
        .env_clear()
        .env("SENTRY_CURL_BIN", "/nonexistent/curl")
        .env("SENTRY_USER", "admin@ipv1337.dev")
        .env("SENTRY_PASSWORD", pass_probe)
        .args([
            "--name",
            "vitruvian-ci",
            "--out",
            out_file.to_str().unwrap(),
        ]);
    let out = run_cmd(missing);
    assert_ne!(out.status.code(), Some(0));
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert!(stderr.contains("SENTRY_TOKEN"), "{stderr}");
    assert!(!stderr.contains(pass_probe), "{stderr}");
    assert!(!out_file.exists());

    let org_secret = "sntrys_org_token_do_not_echo";
    let mut org_tok = Command::new(bin_path());
    org_tok
        .env_clear()
        .env("SENTRY_CURL_BIN", "/nonexistent/curl")
        .env("SENTRY_TOKEN", org_secret)
        .args([
            "--name",
            "vitruvian-ci",
            "--out",
            out_file.to_str().unwrap(),
        ]);
    let out = run_cmd(org_tok);
    assert_ne!(out.status.code(), Some(0));
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert!(stderr.contains("sntryu_"), "{stderr}");
    assert!(!stderr.contains(org_secret));
    assert!(!String::from_utf8_lossy(&out.stdout).contains(org_secret));
}

#[test]
fn create_path_writes_0600_token_creates_0700_parents_and_cleans_up() {
    let work = tempdir("create-ok");
    let bin_dir = work.join("bin");
    let state_dir = work.join("state");
    let tmp_dir = work.join("tmp");
    let out_file = work.join("nested/secrets/ci_token");
    fs::create_dir_all(&bin_dir).unwrap();
    fs::create_dir_all(&state_dir).unwrap();
    fs::create_dir_all(&tmp_dir).unwrap();
    install_fake_curl(&bin_dir);

    let caller_tok = "sntryu_caller_secret_create_123";
    let minted_tok = "sntrya_created_secret_token_xyz";
    let mut cmd = Command::new(bin_path());
    cmd.env_clear()
        .env("PATH", format!("{}:/bin:/usr/bin", bin_dir.display()))
        .env("TMPDIR", &tmp_dir)
        .env("SENTRY_TOKEN", caller_tok)
        .env("FAKE_STATE", &state_dir)
        .env("FAKE_SCENARIO", "create_ok")
        .args([
            "--name",
            "vitruvian-ci",
            "--out",
            out_file.to_str().unwrap(),
        ]);
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
        format!(
            "token written: {} app=vitruvian-ci-abc123 scopes=alerts:read,alerts:write,org:read,org:write,project:read,project:write,team:read,team:write\n",
            out_file.display()
        )
    );
    assert!(!stdout.contains(minted_tok));
    assert!(!stdout.contains(caller_tok));

    assert_eq!(fs::read_to_string(&out_file).unwrap(), minted_tok);
    assert_eq!(fs::metadata(&out_file).unwrap().mode() & 0o777, 0o600);
    assert_eq!(
        fs::metadata(out_file.parent().unwrap()).unwrap().mode() & 0o777,
        0o700
    );
    assert_eq!(fs::read_to_string(state_dir.join("count")).unwrap(), "3");

    for call in 1..=3 {
        assert_eq!(
            fs::read_to_string(state_dir.join(format!("call_{call}_argv"))).unwrap(),
            "-q -sS -K -"
        );
        assert!(
            fs::read_to_string(state_dir.join(format!("call_{call}_envtoken")))
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
        "CI applies infrastructure/pulumi/platform/sentry and infrastructure/pulumi/platform/sentry-pagerduty. Managed by //tools/sentry:ci-token."
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
    let out_file = work.join("ci_token");
    fs::create_dir_all(&bin_dir).unwrap();
    fs::create_dir_all(&state_dir).unwrap();
    fs::create_dir_all(&tmp_dir).unwrap();
    install_fake_curl(&bin_dir);

    let mut cmd = Command::new(bin_path());
    cmd.env_clear()
        .env("PATH", format!("{}:/bin:/usr/bin", bin_dir.display()))
        .env("TMPDIR", &tmp_dir)
        .env("SENTRY_TOKEN", "sntryu_present_caller")
        .env("FAKE_STATE", &state_dir)
        .env("FAKE_SCENARIO", "already_present")
        .args([
            "--name",
            "vitruvian-ci",
            "--out",
            out_file.to_str().unwrap(),
        ]);
    let out = run_cmd(cmd);
    assert_eq!(out.status.code(), Some(0));
    assert_eq!(fs::read_to_string(state_dir.join("count")).unwrap(), "2");
    assert_eq!(
        fs::read_to_string(&out_file).unwrap(),
        "sntrya_present_secret_token_abc"
    );
    assert_eq!(fs::metadata(&out_file).unwrap().mode() & 0o777, 0o600);
}

#[test]
fn scope_update_path_puts_scopes_then_mints_token() {
    let work = tempdir("scope-update");
    let bin_dir = work.join("bin");
    let state_dir = work.join("state");
    let tmp_dir = work.join("tmp");
    let out_file = work.join("ci_token");
    fs::create_dir_all(&bin_dir).unwrap();
    fs::create_dir_all(&state_dir).unwrap();
    fs::create_dir_all(&tmp_dir).unwrap();
    install_fake_curl(&bin_dir);

    let mut cmd = Command::new(bin_path());
    cmd.env_clear()
        .env("PATH", format!("{}:/bin:/usr/bin", bin_dir.display()))
        .env("TMPDIR", &tmp_dir)
        .env("SENTRY_TOKEN", "sntryu_update_caller")
        .env("FAKE_STATE", &state_dir)
        .env("FAKE_SCENARIO", "scope_update")
        .args([
            "--name",
            "vitruvian-ci",
            "--out",
            out_file.to_str().unwrap(),
        ]);
    let out = run_cmd(cmd);
    assert_eq!(out.status.code(), Some(0));
    assert_eq!(fs::read_to_string(state_dir.join("count")).unwrap(), "3");

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
    assert_eq!(
        fs::read_to_string(&out_file).unwrap(),
        "sntrya_updated_secret_token_def"
    );
}

#[test]
fn out_file_refuses_overwrite_before_network_and_force_replaces_with_0600() {
    let work = tempdir("overwrite");
    let bin_dir = work.join("bin");
    let state_dir = work.join("state");
    let tmp_dir = work.join("tmp");
    let out_file = work.join("existing_token");
    fs::create_dir_all(&bin_dir).unwrap();
    fs::create_dir_all(&state_dir).unwrap();
    fs::create_dir_all(&tmp_dir).unwrap();
    install_fake_curl(&bin_dir);

    fs::write(&out_file, "old_secret_keep").unwrap();
    fs::set_permissions(&out_file, fs::Permissions::from_mode(0o644)).unwrap();

    // Without --force: fails before invoking curl.
    let mut cmd_no_force = Command::new(bin_path());
    cmd_no_force
        .env_clear()
        .env("PATH", format!("{}:/bin:/usr/bin", bin_dir.display()))
        .env("TMPDIR", &tmp_dir)
        .env("SENTRY_TOKEN", "sntryu_overwrite_caller")
        .env("FAKE_STATE", &state_dir)
        .env("FAKE_SCENARIO", "already_present")
        .args([
            "--name",
            "vitruvian-ci",
            "--out",
            out_file.to_str().unwrap(),
        ]);
    let out = run_cmd(cmd_no_force);
    assert_ne!(out.status.code(), Some(0));
    assert!(!state_dir.join("count").exists(), "curl must not be called");
    assert_eq!(fs::read_to_string(&out_file).unwrap(), "old_secret_keep");

    // With --force: replaces file atomically with mode 0600.
    let mut cmd_force = Command::new(bin_path());
    cmd_force
        .env_clear()
        .env("PATH", format!("{}:/bin:/usr/bin", bin_dir.display()))
        .env("TMPDIR", &tmp_dir)
        .env("SENTRY_TOKEN", "sntryu_overwrite_caller")
        .env("FAKE_STATE", &state_dir)
        .env("FAKE_SCENARIO", "already_present")
        .args([
            "--name",
            "vitruvian-ci",
            "--out",
            out_file.to_str().unwrap(),
            "--force",
        ]);
    let out_force = run_cmd(cmd_force);
    assert_eq!(out_force.status.code(), Some(0));
    assert_eq!(
        fs::read_to_string(&out_file).unwrap(),
        "sntrya_present_secret_token_abc"
    );
    assert_eq!(fs::metadata(&out_file).unwrap().mode() & 0o777, 0o600);
}

#[test]
fn revoke_others_deletes_all_but_newly_minted_token_id() {
    let work = tempdir("revoke");
    let bin_dir = work.join("bin");
    let state_dir = work.join("state");
    let tmp_dir = work.join("tmp");
    let out_file = work.join("ci_token");
    fs::create_dir_all(&bin_dir).unwrap();
    fs::create_dir_all(&state_dir).unwrap();
    fs::create_dir_all(&tmp_dir).unwrap();
    install_fake_curl(&bin_dir);

    let mut cmd = Command::new(bin_path());
    cmd.env_clear()
        .env("PATH", format!("{}:/bin:/usr/bin", bin_dir.display()))
        .env("TMPDIR", &tmp_dir)
        .env("SENTRY_TOKEN", "sntryu_revoke_caller")
        .env("FAKE_STATE", &state_dir)
        .env("FAKE_SCENARIO", "revoke_others")
        .args([
            "--name",
            "vitruvian-ci",
            "--out",
            out_file.to_str().unwrap(),
            "--revoke-others",
        ]);
    let out = run_cmd(cmd);
    assert_eq!(
        out.status.code(),
        Some(0),
        "stderr: {}",
        String::from_utf8_lossy(&out.stderr)
    );
    assert_eq!(fs::read_to_string(state_dir.join("count")).unwrap(), "5");

    let cfg4 = fs::read_to_string(state_dir.join("call_4_stdin")).unwrap();
    assert!(cfg4.contains("request = \"DELETE\""));
    assert!(cfg4.contains("/api/0/sentry-apps/vitruvian-ci-333333/api-tokens/10/"));

    let cfg5 = fs::read_to_string(state_dir.join("call_5_stdin")).unwrap();
    assert!(cfg5.contains("request = \"DELETE\""));
    assert!(cfg5.contains("/api/0/sentry-apps/vitruvian-ci-333333/api-tokens/99/"));

    assert_eq!(
        fs::read_to_string(&out_file).unwrap(),
        "sntrya_new_rotated_token_42"
    );
}

#[test]
fn secrets_never_appear_in_stdout_stderr_argv_or_child_env_including_errors() {
    // 1. HTTP 403 on /api-tokens/ prints status + detail + mint limitation without request headers or token.
    let work = tempdir("err-403");
    let bin_dir = work.join("bin");
    let state_dir = work.join("state");
    let tmp_dir = work.join("tmp");
    let out_file = work.join("ci_token");
    fs::create_dir_all(&bin_dir).unwrap();
    fs::create_dir_all(&state_dir).unwrap();
    fs::create_dir_all(&tmp_dir).unwrap();
    install_fake_curl(&bin_dir);

    let caller = "sntryu_secret_403_token";
    let mut cmd = Command::new(bin_path());
    cmd.env_clear()
        .env("PATH", format!("{}:/bin:/usr/bin", bin_dir.display()))
        .env("TMPDIR", &tmp_dir)
        .env("SENTRY_TOKEN", caller)
        .env("FAKE_STATE", &state_dir)
        .env("FAKE_SCENARIO", "token_403")
        .args([
            "--name",
            "vitruvian-ci",
            "--out",
            out_file.to_str().unwrap(),
        ]);
    let out = run_cmd(cmd);
    assert_ne!(out.status.code(), Some(0));
    assert!(out.stdout.is_empty());
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert!(stderr.contains("403"), "{stderr}");
    assert!(
        stderr.contains("Authentication credentials were not provided."),
        "{stderr}"
    );
    assert!(
        stderr.contains("SessionNoAuthTokenAuthentication"),
        "{stderr}"
    );
    assert!(
        stderr.contains("session-based login that the lead has not yet approved"),
        "{stderr}"
    );
    assert!(!stderr.contains("SENTRY_USER"), "{stderr}");
    assert!(!stderr.contains("SENTRY_PASSWORD"), "{stderr}");
    assert!(!stderr.contains("Authorization:"), "{stderr}");
    assert!(!stderr.contains(caller), "{stderr}");
    assert!(!out_file.exists());
    if !tmp_dir.to_string_lossy().contains('=') {
        assert_eq!(fs::read_dir(&tmp_dir).unwrap().count(), 0);
    }

    // 2. Masked token response is rejected without creating --out.
    let work_mask = tempdir("masked");
    let bin_mask = work_mask.join("bin");
    let state_mask = work_mask.join("state");
    let tmp_mask = work_mask.join("tmp");
    let out_mask_file = work_mask.join("ci_token");
    fs::create_dir_all(&bin_mask).unwrap();
    fs::create_dir_all(&state_mask).unwrap();
    fs::create_dir_all(&tmp_mask).unwrap();
    install_fake_curl(&bin_mask);

    let mut cmd_mask = Command::new(bin_path());
    cmd_mask
        .env_clear()
        .env("PATH", format!("{}:/bin:/usr/bin", bin_mask.display()))
        .env("TMPDIR", &tmp_mask)
        .env("SENTRY_TOKEN", caller)
        .env("FAKE_STATE", &state_mask)
        .env("FAKE_SCENARIO", "masked_token")
        .args([
            "--name",
            "vitruvian-ci",
            "--out",
            out_mask_file.to_str().unwrap(),
        ]);
    let out_mask = run_cmd(cmd_mask);
    assert_ne!(out_mask.status.code(), Some(0));
    assert!(String::from_utf8_lossy(&out_mask.stderr).contains("masked"));
    assert!(!out_mask_file.exists());

    // 3. Curl stderr echoing bearer token is redacted.
    let work_red = tempdir("redact");
    let bin_red = work_red.join("bin");
    let state_red = work_red.join("state");
    let tmp_red = work_red.join("tmp");
    let out_red_file = work_red.join("ci_token");
    fs::create_dir_all(&bin_red).unwrap();
    fs::create_dir_all(&state_red).unwrap();
    fs::create_dir_all(&tmp_red).unwrap();
    install_fake_curl(&bin_red);

    let leak_probe = "sntryu_secret_stderr_probe_777";
    let mut cmd_red = Command::new(bin_path());
    cmd_red
        .env_clear()
        .env("PATH", format!("{}:/bin:/usr/bin", bin_red.display()))
        .env("TMPDIR", &tmp_red)
        .env("SENTRY_TOKEN", leak_probe)
        .env("FAKE_STATE", &state_red)
        .env("FAKE_SCENARIO", "echo_token_stderr")
        .args([
            "--name",
            "vitruvian-ci",
            "--out",
            out_red_file.to_str().unwrap(),
        ]);
    let out_red = run_cmd(cmd_red);
    assert_ne!(out_red.status.code(), Some(0));
    let stderr_red = String::from_utf8_lossy(&out_red.stderr);
    assert!(!stderr_red.contains(leak_probe), "{stderr_red}");
    assert!(stderr_red.contains("<redacted>"), "{stderr_red}");
}
