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

use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

fn script_path() -> PathBuf {
    let rel = std::env::var("SIGN_SCRIPT").expect("SIGN_SCRIPT env must be set");
    fs::canonicalize(rel).expect("canonicalize SIGN_SCRIPT")
}

fn entitlements_path() -> PathBuf {
    let rel = std::env::var("ENTITLEMENTS_PATH").expect("ENTITLEMENTS_PATH env must be set");
    fs::canonicalize(rel).expect("canonicalize ENTITLEMENTS_PATH")
}

fn scratch_dir(name: &str) -> PathBuf {
    let base = std::env::var("TEST_TMPDIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| std::env::temp_dir());
    let dir = base.join(name);
    let _ = fs::remove_dir_all(&dir);
    fs::create_dir_all(&dir).expect("create scratch dir");
    dir
}

fn write_exec(dir: &Path, name: &str, body: &str) {
    let p = dir.join(name);
    fs::write(&p, body).expect("write fake tool");
    fs::set_permissions(&p, fs::Permissions::from_mode(0o755)).expect("chmod fake tool");
}

fn create_fake_app(
    dir: &Path,
    bundle_name: &str,
    exec_name: &str,
    extra_macos_helper: bool,
) -> PathBuf {
    let app = dir.join(bundle_name);
    let contents = app.join("Contents");
    fs::create_dir_all(contents.join("MacOS")).unwrap();
    fs::create_dir_all(contents.join("Frameworks")).unwrap();
    fs::create_dir_all(contents.join("Resources")).unwrap();

    let plist = format!(
        r#"<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>{exec_name}</string>
    <key>CFBundleIdentifier</key>
    <string>com.vitruviansoftware.test</string>
</dict>
</plist>
"#
    );
    fs::write(contents.join("Info.plist"), plist).unwrap();

    let main_exe = contents.join("MacOS").join(exec_name);
    fs::write(&main_exe, b"FAKE_MACHO_MAIN").unwrap();
    fs::set_permissions(&main_exe, fs::Permissions::from_mode(0o755)).unwrap();

    if extra_macos_helper {
        let helper = contents.join("MacOS/auxiliary-helper");
        fs::write(&helper, b"FAKE_MACHO_HELPER").unwrap();
        fs::set_permissions(&helper, fs::Permissions::from_mode(0o755)).unwrap();
    }

    let dylib = contents.join("Frameworks/Nested.dylib");
    fs::write(&dylib, b"FAKE_MACHO_DYLIB").unwrap();
    fs::set_permissions(&dylib, fs::Permissions::from_mode(0o755)).unwrap();

    fs::write(contents.join("Resources/notes.txt"), b"plain text resource").unwrap();
    app
}

fn install_fake_signing_toolchain(fake_bin: &Path, slow_codesign: bool) {
    write_exec(
        fake_bin,
        "security",
        r#"#!/usr/bin/env bash
set -euo pipefail
echo "security $*" >> "${FAKE_LOG_DIR}/security.log"
sub="${1:-}"
case "${sub}" in
  list-keychains)
    if [ "${4:-}" = "-s" ]; then
      exit 0
    fi
    echo '    "/Users/runner/Library/Keychains/login.keychain-db"'
    ;;
  create-keychain)
    # args: create-keychain -p <pass> <kc_path>
    touch "$4"
    ;;
  delete-keychain)
    rm -f "${2:-}"
    ;;
  find-identity)
    echo '  1) 0123456789ABCDEF0123456789ABCDEF01234567 "Developer ID Application: Test Org (TEAMID1234)"'
    echo '     1 valid identities found'
    ;;
  *)
    ;;
esac
"#,
    );

    let codesign_body = if slow_codesign {
        r#"#!/usr/bin/env bash
set -euo pipefail
echo "codesign $*" >> "${FAKE_LOG_DIR}/codesign.log"
if [ -n "${READY_FILE:-}" ] && [ ! -f "${READY_FILE}" ]; then
  kc_found="$(find "${RUNNER_TEMP}" -name 'vitruvian-code-signing.keychain-db' -print -quit)"
  wd_found="$(find "${RUNNER_TEMP}" -maxdepth 1 -type d -name 'vc-signing.*' -print -quit)"
  printf '%s\n%s\n' "${wd_found}" "${kc_found}" > "${READY_FILE}.tmp"
  mv "${READY_FILE}.tmp" "${READY_FILE}"
  sleep 2
fi
"#
    } else {
        r#"#!/usr/bin/env bash
set -euo pipefail
echo "codesign $*" >> "${FAKE_LOG_DIR}/codesign.log"
"#
    };
    write_exec(fake_bin, "codesign", codesign_body);

    // Multi-KB multi-line output on Mach-O files proves `sign-and-notarize.sh`
    // does not trip SIGPIPE under `set -euo pipefail` (no `file | grep -q`).
    write_exec(
        fake_bin,
        "file",
        r#"#!/usr/bin/env bash
set -euo pipefail
target="${!#}"
if head -c 10 "${target}" 2>/dev/null | grep -q '^FAKE_MACHO'; then
  for _ in $(seq 200); do
    echo "Mach-O universal binary with 2 architectures: [x86_64:Mach-O 64-bit executable x86_64] [arm64:Mach-O 64-bit executable arm64]"
  done
else
  echo "ASCII text"
fi
"#,
    );

    write_exec(
        fake_bin,
        "ditto",
        r#"#!/usr/bin/env bash
set -euo pipefail
dest="${!#}"
touch "${dest}"
"#,
    );

    write_exec(
        fake_bin,
        "xcrun",
        r#"#!/usr/bin/env bash
set -euo pipefail
echo "xcrun $*" >> "${FAKE_LOG_DIR}/xcrun.log"
if [ "${1:-}" = "notarytool" ] && [ "${2:-}" = "submit" ]; then
  echo "  id: 00000000-1111-2222-3333-444444444444"
  echo "  status: Accepted"
fi
"#,
    );

    write_exec(
        fake_bin,
        "spctl",
        r#"#!/usr/bin/env bash
set -euo pipefail
echo "spctl $*" >> "${FAKE_LOG_DIR}/spctl.log"
"#,
    );

    write_exec(
        fake_bin,
        "xattr",
        r#"#!/usr/bin/env bash
exit 0
"#,
    );
}

#[test]
fn no_arguments_prints_usage_and_exits_2() {
    let script = script_path();
    for args in [&[][..], &["apps"][..], &["dmgs"][..]] {
        let out = Command::new(&script)
            .args(args)
            .output()
            .expect("run sign-and-notarize.sh");
        assert_eq!(
            out.status.code(),
            Some(2),
            "args {:?} should exit 2, got {:?} (stderr: {})",
            args,
            out.status.code(),
            String::from_utf8_lossy(&out.stderr)
        );
        let stderr = String::from_utf8_lossy(&out.stderr);
        assert!(
            stderr.contains("Usage:"),
            "args {:?} stderr should contain Usage:, got: {}",
            args,
            stderr
        );
    }
}

#[test]
fn missing_secrets_fails_closed() {
    let dir = scratch_dir("missing_secrets");
    let app = create_fake_app(&dir, "Vitruvian Code.app", "VitruvianCode", false);
    let out = Command::new(script_path())
        .args(["apps", "--entitlements-app", app.to_str().unwrap()])
        .env("SIGNING", "developer-id")
        .env("GITHUB_ACTIONS", "true")
        .env("RUNNER_TEMP", &dir)
        .env("VITRUVIAN_CODE_ENTITLEMENTS", entitlements_path())
        .env_remove("VITRUVIAN_SIGNING_CERT_P12")
        .env_remove("VITRUVIAN_SIGNING_CERT_PASSWORD")
        .env_remove("VITRUVIAN_NOTARY_API_KEY_P8")
        .env_remove("VITRUVIAN_NOTARY_KEY_ID")
        .env_remove("VITRUVIAN_NOTARY_ISSUER_ID")
        .output()
        .expect("run sign-and-notarize.sh");

    assert_eq!(out.status.code(), Some(1));
    let stdout = String::from_utf8_lossy(&out.stdout);
    assert!(
        stdout.contains("::error::Missing required secret VITRUVIAN_SIGNING_CERT_P12"),
        "stdout: {}",
        stdout
    );
}

#[test]
fn inside_out_signing_signs_other_macos_machos_and_skips_only_cfbundleexecutable() {
    let dir = scratch_dir("inside_out");
    let fake_bin = dir.join("fake_bin");
    let log_dir = dir.join("logs");
    let runner_temp = dir.join("runner_temp");
    fs::create_dir_all(&fake_bin).unwrap();
    fs::create_dir_all(&log_dir).unwrap();
    fs::create_dir_all(&runner_temp).unwrap();

    install_fake_signing_toolchain(&fake_bin, false);

    let app = create_fake_app(&dir, "Vitruvian Code.app", "VitruvianCode", true);
    let orig_path = std::env::var("PATH").unwrap_or_default();

    let out = Command::new(script_path())
        .args(["apps", "--entitlements-app", app.to_str().unwrap()])
        .env("PATH", format!("{}:{}", fake_bin.display(), orig_path))
        .env("FAKE_LOG_DIR", &log_dir)
        .env("RUNNER_TEMP", &runner_temp)
        .env("VITRUVIAN_CODE_ENTITLEMENTS", entitlements_path())
        .env("SIGNING", "developer-id")
        .env("VITRUVIAN_SIGNING_CERT_P12", "dGVzdC1wMTI=")
        .env("VITRUVIAN_SIGNING_CERT_PASSWORD", "test-pass")
        .env(
            "VITRUVIAN_NOTARY_API_KEY_P8",
            "-----BEGIN PRIVATE KEY-----\ntest\n-----END PRIVATE KEY-----",
        )
        .env("VITRUVIAN_NOTARY_KEY_ID", "KEYID12345")
        .env(
            "VITRUVIAN_NOTARY_ISSUER_ID",
            "00000000-0000-0000-0000-000000000000",
        )
        .output()
        .expect("run sign-and-notarize.sh");

    assert_eq!(
        out.status.code(),
        Some(0),
        "stdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&out.stdout),
        String::from_utf8_lossy(&out.stderr)
    );

    let codesign_log = fs::read_to_string(log_dir.join("codesign.log")).unwrap();
    let sign_lines: Vec<&str> = codesign_log
        .lines()
        .filter(|l| l.contains("--sign "))
        .collect();

    let helper_pos = sign_lines
        .iter()
        .position(|l| l.ends_with("Contents/MacOS/auxiliary-helper"))
        .expect("auxiliary Mach-O inside Contents/MacOS must be signed inside-out");
    let dylib_pos = sign_lines
        .iter()
        .position(|l| l.ends_with("Contents/Frameworks/Nested.dylib"))
        .expect("nested dylib must be signed inside-out");
    let bundle_pos = sign_lines
        .iter()
        .position(|l| l.ends_with("Vitruvian Code.app") && l.contains("--entitlements"))
        .expect("app bundle must be signed with entitlements");

    assert!(
        helper_pos < bundle_pos && dylib_pos < bundle_pos,
        "nested Mach-Os must be signed before the bundle: {:?}",
        sign_lines
    );
    assert!(
        !sign_lines
            .iter()
            .any(|l| l.ends_with("Contents/MacOS/VitruvianCode")),
        "CFBundleExecutable must be signed only with the bundle pass, not separately: {:?}",
        sign_lines
    );

    let leftovers: Vec<_> = fs::read_dir(&runner_temp)
        .unwrap()
        .filter_map(Result::ok)
        .collect();
    assert!(
        leftovers.is_empty(),
        "temporary signing directory must be cleaned up on exit, found: {:?}",
        leftovers
    );
}

fn assert_signal_exits_and_cleans_up(sig_flag: &str, expected_code: i32, dir_name: &str) {
    let dir = scratch_dir(dir_name);
    let fake_bin = dir.join("fake_bin");
    let log_dir = dir.join("logs");
    let runner_temp = dir.join("runner_temp");
    let ready_file = dir.join("ready.txt");
    fs::create_dir_all(&fake_bin).unwrap();
    fs::create_dir_all(&log_dir).unwrap();
    fs::create_dir_all(&runner_temp).unwrap();

    install_fake_signing_toolchain(&fake_bin, true);
    let app = create_fake_app(&dir, "Vitruvian Code.app", "VitruvianCode", false);
    let orig_path = std::env::var("PATH").unwrap_or_default();

    let mut child = Command::new(script_path())
        .args(["apps", "--entitlements-app", app.to_str().unwrap()])
        .env("PATH", format!("{}:{}", fake_bin.display(), orig_path))
        .env("FAKE_LOG_DIR", &log_dir)
        .env("RUNNER_TEMP", &runner_temp)
        .env("READY_FILE", &ready_file)
        .env("VITRUVIAN_CODE_ENTITLEMENTS", entitlements_path())
        .env("SIGNING", "developer-id")
        .env("VITRUVIAN_SIGNING_CERT_P12", "dGVzdC1wMTI=")
        .env("VITRUVIAN_SIGNING_CERT_PASSWORD", "test-pass")
        .env(
            "VITRUVIAN_NOTARY_API_KEY_P8",
            "-----BEGIN PRIVATE KEY-----\ntest\n-----END PRIVATE KEY-----",
        )
        .env("VITRUVIAN_NOTARY_KEY_ID", "KEYID12345")
        .env(
            "VITRUVIAN_NOTARY_ISSUER_ID",
            "00000000-0000-0000-0000-000000000000",
        )
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("spawn sign-and-notarize.sh");

    let deadline = Instant::now() + Duration::from_secs(10);
    while !ready_file.exists() {
        assert!(
            Instant::now() < deadline,
            "timed out waiting for sign-and-notarize.sh to create temporary keychain"
        );
        std::thread::sleep(Duration::from_millis(25));
    }

    let recorded = fs::read_to_string(&ready_file).unwrap();
    let mut lines = recorded.lines();
    let observed_work_dir = PathBuf::from(lines.next().unwrap_or(""));
    let observed_keychain = PathBuf::from(lines.next().unwrap_or(""));
    assert!(
        !observed_work_dir.as_os_str().is_empty() && !observed_keychain.as_os_str().is_empty(),
        "mid-run work dir and temporary keychain should have been created: {:?}",
        recorded
    );

    let kill_status = Command::new("kill")
        .args([sig_flag, &child.id().to_string()])
        .status()
        .expect("send signal");
    assert!(kill_status.success(), "kill {} failed", sig_flag);

    let status = child.wait().expect("wait for sign-and-notarize.sh");
    assert_eq!(
        status.code(),
        Some(expected_code),
        "signal {} must exit {}, got {:?}",
        sig_flag,
        expected_code,
        status
    );

    assert!(
        !observed_work_dir.exists(),
        "scratch directory {} must be removed on {}",
        observed_work_dir.display(),
        sig_flag
    );
    assert!(
        !observed_keychain.exists(),
        "temporary keychain {} must be removed on {}",
        observed_keychain.display(),
        sig_flag
    );
    let security_log = fs::read_to_string(log_dir.join("security.log")).unwrap();
    assert!(
        security_log.contains("security delete-keychain"),
        "cleanup must delete temporary keychain on {}: {}",
        sig_flag,
        security_log
    );
}

#[test]
fn sigterm_exits_143_and_cleans_up_keychain_and_scratch_dir() {
    assert_signal_exits_and_cleans_up("-TERM", 143, "sigterm_cleanup");
}

#[test]
fn sigint_exits_130_and_cleans_up_keychain_and_scratch_dir() {
    assert_signal_exits_and_cleans_up("-INT", 130, "sigint_cleanup");
}
