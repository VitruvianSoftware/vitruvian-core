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
    let raw = std::env::var("SEND_TEST_EVENT_BIN").expect("SEND_TEST_EVENT_BIN not set");
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
printf '%s' "${SENTRY_DSN:-}" > "$FAKE_STATE/call_${n}_envdsn"
cat > "$FAKE_STATE/call_${n}_stdin"

jar=$(sed -n 's/^cookie-jar = "\(.*\)"$/\1/p' "$FAKE_STATE/call_${n}_stdin")
if [ -n "$jar" ] && [ -f "$jar" ]; then
  ls -ld "$jar" > "$FAKE_STATE/call_${n}_jarmode"
fi

case "$FAKE_SCENARIO" in
  send_200)
    printf '{"id":"ok"}\n__sentry_pagerduty_install_status__200'
    ;;
  send_429)
    printf '{"detail":"rate limit exceeded"}\n__sentry_pagerduty_install_status__429'
    ;;
  echo_key_stderr)
    key=$(sed -n 's/^header = "X-Sentry-Auth: Sentry sentry_version=7, sentry_key=\([^,]*\),.*$/\1/p' "$FAKE_STATE/call_${n}_stdin")
    if [ -z "$key" ]; then
      printf 'missing X-Sentry-Auth header in stdin config\n' >&2
      exit 2
    fi
    printf 'curl: rejected key %s at endpoint\n' "$key" >&2
    exit 1
    ;;
  *)
    printf 'unexpected scenario %s\n' "$FAKE_SCENARIO" >&2
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
        .expect("failed to execute send-test-event")
}

#[test]
fn help_prints_usage_without_dsn() {
    let mut cmd = Command::new(bin_path());
    cmd.env_clear().arg("--help");
    let out = run_cmd(cmd);
    assert_eq!(out.status.code(), Some(0));
    let stdout = String::from_utf8_lossy(&out.stdout);
    assert!(stdout.contains("--dsn"), "{stdout}");
    assert!(stdout.contains("--level"), "{stdout}");
    assert!(stdout.contains("--message"), "{stdout}");
}

#[test]
fn invalid_dsn_or_level_exits_2_and_never_leaks_key() {
    let key = "secret_dsn_key_do_not_leak";
    let bad_dsns = [
        format!("http://{key}@sentry-ingest.ipv1337.dev/18"),
        "https://sentry-ingest.ipv1337.dev/18".to_string(),
        "https://@sentry-ingest.ipv1337.dev/18".to_string(),
        format!("https://{key}@sentry-ingest.ipv1337.dev"),
        format!("https://{key}@sentry-ingest.ipv1337.dev/18/"),
    ];
    for dsn in bad_dsns {
        let mut cmd = Command::new(bin_path());
        cmd.env_clear().args(["--dsn", &dsn]);
        let out = run_cmd(cmd);
        assert_eq!(out.status.code(), Some(2), "dsn={dsn}");
        let stderr = String::from_utf8_lossy(&out.stderr);
        let stdout = String::from_utf8_lossy(&out.stdout);
        assert!(!stderr.contains(key), "key leaked in stderr: {stderr}");
        assert!(!stdout.contains(key), "key leaked in stdout: {stdout}");
    }

    let mut bad_level = Command::new(bin_path());
    bad_level.env_clear().args([
        "--dsn",
        "https://abc123@sentry.example.com/1",
        "--level",
        "trace",
    ]);
    let out = run_cmd(bad_level);
    assert_eq!(out.status.code(), Some(2));
    assert!(String::from_utf8_lossy(&out.stderr).contains("--level"));
}

#[test]
fn fake_curl_send_200_verifies_argv_headers_envelope_and_cleanup() {
    let work = tempdir("send-ok");
    let bin_dir = work.join("bin");
    let state_dir = work.join("state");
    let tmp_dir = work.join("tmp");
    fs::create_dir_all(&bin_dir).unwrap();
    fs::create_dir_all(&state_dir).unwrap();
    fs::create_dir_all(&tmp_dir).unwrap();
    install_fake_curl(&bin_dir);

    let key = "f5f0bc21a4b8f3f1c63fb5f684e070ca";
    let dsn = format!("https://{key}@sentry-ingest.ipv1337.dev/18");
    let path_env = format!("{}:/bin:/usr/bin", bin_dir.display());
    let mut cmd = Command::new(bin_path());
    cmd.env_clear()
        .env("PATH", path_env)
        .env("TMPDIR", &tmp_dir)
        .env("SENTRY_TOKEN", "should_not_leak_to_curl")
        .env("SENTRY_DSN", &dsn)
        .env("FAKE_STATE", &state_dir)
        .env("FAKE_SCENARIO", "send_200")
        .args(["--dsn", &dsn]);

    let out = run_cmd(cmd);
    assert_eq!(
        out.status.code(),
        Some(0),
        "stderr: {}",
        String::from_utf8_lossy(&out.stderr)
    );
    assert!(out.stderr.is_empty());

    let stdout = String::from_utf8(out.stdout).unwrap();
    let trimmed = stdout.trim_end_matches('\n');
    assert!(
        trimmed.starts_with("sent: event_id="),
        "unexpected stdout: {stdout}"
    );
    assert!(
        trimmed.ends_with(" project=18 host=sentry-ingest.ipv1337.dev"),
        "unexpected stdout: {stdout}"
    );
    let event_id = trimmed
        .strip_prefix("sent: event_id=")
        .unwrap()
        .split_whitespace()
        .next()
        .unwrap();
    assert_eq!(event_id.len(), 32);
    assert!(event_id
        .bytes()
        .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b)));

    assert_eq!(fs::read_to_string(state_dir.join("count")).unwrap(), "1");
    let argv = fs::read_to_string(state_dir.join("call_1_argv")).unwrap();
    assert_eq!(argv, "-q -sS -K -");
    assert!(!argv.contains(key));

    assert!(fs::read_to_string(state_dir.join("call_1_envtoken"))
        .unwrap()
        .is_empty());
    assert!(fs::read_to_string(state_dir.join("call_1_envdsn"))
        .unwrap()
        .is_empty());

    let jarmode = fs::read_to_string(state_dir.join("call_1_jarmode")).unwrap();
    assert!(jarmode.starts_with("-rw-------"), "{jarmode}");

    let cfg = fs::read_to_string(state_dir.join("call_1_stdin")).unwrap();
    assert!(
        cfg.contains("url = \"https://sentry-ingest.ipv1337.dev/api/18/envelope/\""),
        "{cfg}"
    );
    assert!(cfg.contains("request = \"POST\""), "{cfg}");
    assert!(
        cfg.contains(&format!(
            "header = \"X-Sentry-Auth: Sentry sentry_version=7, sentry_key={key}, sentry_client=vitruvian-send-test-event/1.0\""
        )),
        "{cfg}"
    );
    assert!(
        cfg.contains("header = \"Content-Type: application/x-sentry-envelope\""),
        "{cfg}"
    );
    assert!(
        cfg.contains("header = \"User-Agent: sentry.rust/0.35.0\""),
        "{cfg}"
    );

    let data_line = cfg
        .lines()
        .find(|l| l.starts_with("data-binary = "))
        .expect("missing data-binary");
    let quoted = data_line.strip_prefix("data-binary = ").unwrap();
    let envelope: String = serde_json::from_str(quoted).unwrap();
    let env_lines: Vec<&str> = envelope.lines().collect();
    assert_eq!(env_lines.len(), 3, "envelope: {envelope}");

    let header: Value = serde_json::from_str(env_lines[0]).unwrap();
    assert_eq!(header["event_id"], event_id);
    assert_eq!(header["dsn"], dsn);
    assert!(header["sent_at"].as_str().unwrap().ends_with('Z'));

    let item_header: Value = serde_json::from_str(env_lines[1]).unwrap();
    assert_eq!(item_header["type"], "event");

    let payload: Value = serde_json::from_str(env_lines[2]).unwrap();
    assert_eq!(payload["event_id"], event_id);
    assert_eq!(payload["timestamp"], header["sent_at"]);
    assert_eq!(payload["level"], "fatal");
    assert_eq!(payload["platform"], "other");
    assert_eq!(payload["logger"], "vitruvian.send-test-event");
    assert!(payload["message"]["formatted"]
        .as_str()
        .unwrap()
        .starts_with("PagerDuty test page from //tools/sentry:send-test-event at "));
    assert_eq!(
        payload["fingerprint"],
        serde_json::json!(["vitruvian-send-test-event", event_id])
    );
    assert_eq!(payload["tags"]["vitruvian.test"], "pagerduty");

    if !tmp_dir.to_string_lossy().contains('=') {
        assert_eq!(fs::read_dir(&tmp_dir).unwrap().count(), 0);
    }
}

#[test]
fn fake_curl_path_prefix_and_custom_level_and_message() {
    let work = tempdir("send-prefix");
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
        .env("FAKE_STATE", &state_dir)
        .env("FAKE_SCENARIO", "send_200")
        .args([
            "--dsn",
            "https://abcdef0123456789@sentry.example.com/sub/path/42",
            "--level",
            "warning",
            "--message",
            "Synthetic page",
        ]);
    let out = run_cmd(cmd);
    assert_eq!(
        out.status.code(),
        Some(0),
        "stderr: {}",
        String::from_utf8_lossy(&out.stderr)
    );

    let cfg = fs::read_to_string(state_dir.join("call_1_stdin")).unwrap();
    assert!(
        cfg.contains("url = \"https://sentry.example.com/sub/path/api/42/envelope/\""),
        "{cfg}"
    );
    let data_line = cfg
        .lines()
        .find(|l| l.starts_with("data-binary = "))
        .unwrap();
    let envelope: String =
        serde_json::from_str(data_line.strip_prefix("data-binary = ").unwrap()).unwrap();
    let payload: Value = serde_json::from_str(envelope.lines().nth(2).unwrap()).unwrap();
    assert_eq!(payload["level"], "warning");
    assert_eq!(payload["message"]["formatted"], "Synthetic page");
}

#[test]
fn fake_curl_non_2xx_prints_status_and_body_and_redacts_key_on_curl_error() {
    let work = tempdir("send-429");
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
        .env("FAKE_STATE", &state_dir)
        .env("FAKE_SCENARIO", "send_429")
        .args(["--dsn", "https://pubkey429@sentry.example.com/42"]);
    let out = run_cmd(cmd);
    assert_ne!(out.status.code(), Some(0));
    assert!(out.stdout.is_empty());
    let stderr = String::from_utf8_lossy(&out.stderr);
    assert!(stderr.contains("429"), "{stderr}");
    assert!(stderr.contains("rate limit exceeded"), "{stderr}");
    if !tmp_dir.to_string_lossy().contains('=') {
        assert_eq!(fs::read_dir(&tmp_dir).unwrap().count(), 0);
    }

    let work2 = tempdir("send-redact");
    let bin2 = work2.join("bin");
    let state2 = work2.join("state");
    let tmp2 = work2.join("tmp");
    fs::create_dir_all(&bin2).unwrap();
    fs::create_dir_all(&state2).unwrap();
    fs::create_dir_all(&tmp2).unwrap();
    install_fake_curl(&bin2);

    let secret_key = "pub_secret_echo_check";
    let mut cmd2 = Command::new(bin_path());
    cmd2.env_clear()
        .env("PATH", format!("{}:/bin:/usr/bin", bin2.display()))
        .env("TMPDIR", &tmp2)
        .env("FAKE_STATE", &state2)
        .env("FAKE_SCENARIO", "echo_key_stderr")
        .args([
            "--dsn",
            &format!("https://{secret_key}@sentry.example.com/42"),
        ]);
    let out2 = run_cmd(cmd2);
    assert_ne!(out2.status.code(), Some(0));
    let stderr2 = String::from_utf8_lossy(&out2.stderr);
    assert!(!stderr2.contains(secret_key), "key leaked: {stderr2}");
    assert!(stderr2.contains("<redacted>"), "{stderr2}");
    if !tmp2.to_string_lossy().contains('=') {
        assert_eq!(fs::read_dir(&tmp2).unwrap().count(), 0);
    }
}
