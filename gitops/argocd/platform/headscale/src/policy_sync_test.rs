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

//! QA structural and behavioural tests for the Headscale `policy-sync` sidecar.

use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::{AtomicU64, Ordering};

use headscale_values::yaml::resolve_data_path;
use headscale_values::{
    load_docs, load_headscale_values, single_doc_of_kind, PKG_DIR, POLICY_CONFIGMAP_FILENAME,
    POLICY_CONFIGMAP_NAME, POLICY_FILENAME,
};

const FAKE_HEADSCALE_SH: &str = r#"#!/bin/sh
set -eu
printf '%s\n' "$*" >>"$STATE_DIR/calls.log"

if [ "$#" -eq 2 ] && [ "$1" = "policy" ] && [ "$2" = "get" ]; then
  if [ -f "$STATE_DIR/live.txt" ]; then
    # Real headscale prints stored p.Data via fmt.Println (one trailing '\n').
    cat "$STATE_DIR/live.txt"
    printf '\n'
    exit 0
  fi
  mode=""
  if [ -f "$STATE_DIR/mode" ]; then
    mode="$(cat "$STATE_DIR/mode")"
  fi
  case "$mode" in
    notfound)
      printf '%s\n' "Failed loading ACL Policy: loading ACL from database: acl policy not found" >&2
      exit 1
      ;;
    down)
      printf '%s\n' "Failed loading ACL Policy: connection refused" >&2
      exit 1
      ;;
    *)
      printf 'fake headscale: unexpected policy get mode: %s\n' "$mode" >&2
      exit 2
      ;;
  esac
fi

if [ "$#" -eq 4 ] && [ "$1" = "policy" ] && [ "$2" = "check" ] && [ "$3" = "-f" ]; then
  file="$4"
  if [ ! -r "$file" ]; then
    printf 'Error opening the policy file: %s\n' "$file" >&2
    exit 1
  fi
  if [ -f "$STATE_DIR/check_fail" ]; then
    printf '%s\n' "Error parsing the policy file: bad" >&2
    exit 1
  fi
  printf '%s\n' "Policy is valid"
  exit 0
fi

if [ "$#" -eq 4 ] && [ "$1" = "policy" ] && [ "$2" = "set" ] && [ "$3" = "-f" ]; then
  file="$4"
  if [ ! -r "$file" ]; then
    printf 'Error opening the policy file: %s\n' "$file" >&2
    exit 1
  fi
  if [ -f "$STATE_DIR/set_fail" ]; then
    printf '%s\n' "Failed to set ACL Policy: boom" >&2
    exit 1
  fi
  cp "$file" "$STATE_DIR/live.txt"
  printf '%s\n' "Policy updated."
  exit 0
fi

printf 'fake headscale: unexpected args: %s\n' "$*" >&2
exit 2
"#;

fn extract_sidecar_script() -> String {
    let hs = load_headscale_values();
    let cmd = hs
        .pointer("/sidecars/policy-sync/command")
        .and_then(|v| v.as_array())
        .expect("sidecars.policy-sync.command must be a YAML list");
    assert_eq!(
        cmd.len(),
        3,
        "sidecars.policy-sync.command must have 3 elements"
    );
    assert_eq!(cmd[0].as_str(), Some("/busybox/sh"));
    assert_eq!(cmd[1].as_str(), Some("-c"));
    let script = cmd[2]
        .as_str()
        .expect("sidecars.policy-sync.command[2] must be a script string");
    assert!(
        !script.trim().is_empty(),
        "sidecar script must not be empty"
    );
    script.to_string()
}

struct CaseEnv {
    root: PathBuf,
    bin_dir: PathBuf,
    state_dir: PathBuf,
    tmp_dir: PathBuf,
    policy_file: PathBuf,
}

struct RunResult {
    exit_code: Option<i32>,
    stdout: String,
    stderr: String,
    calls: Vec<String>,
}

impl CaseEnv {
    fn new(case_name: &str) -> Self {
        static NEXT_ID: AtomicU64 = AtomicU64::new(0);
        let id = NEXT_ID.fetch_add(1, Ordering::Relaxed);
        let base = std::env::var_os("TEST_TMPDIR")
            .filter(|s| !s.is_empty())
            .map(PathBuf::from)
            .unwrap_or_else(std::env::temp_dir);
        let root = base.join(format!(
            "headscale-policy-sync-qa-{case_name}-{}-{id}",
            std::process::id()
        ));
        let _ = fs::remove_dir_all(&root);
        let bin_dir = root.join("bin");
        let state_dir = root.join("state");
        let tmp_dir = root.join("tmp");
        fs::create_dir_all(&bin_dir).expect("create bin dir");
        fs::create_dir_all(&state_dir).expect("create state dir");
        fs::create_dir_all(&tmp_dir).expect("create tmp dir");

        let fake_bin = bin_dir.join("headscale");
        fs::write(&fake_bin, FAKE_HEADSCALE_SH).expect("write fake headscale");
        let mut perms = fs::metadata(&fake_bin)
            .expect("stat fake headscale")
            .permissions();
        perms.set_mode(0o755);
        fs::set_permissions(&fake_bin, perms).expect("chmod fake headscale");

        let policy_file = root.join("policy.hujson");
        Self {
            root,
            bin_dir,
            state_dir,
            tmp_dir,
            policy_file,
        }
    }

    fn write_policy(&self, content: &str) {
        fs::write(&self.policy_file, content).expect("write temp policy file");
    }

    fn write_live(&self, content: &str) {
        fs::write(self.state_dir.join("live.txt"), content).expect("write state live.txt");
    }

    fn set_mode(&self, mode: &str) {
        fs::write(self.state_dir.join("mode"), mode).expect("write state mode");
    }

    fn set_flag(&self, name: &str) {
        fs::write(self.state_dir.join(name), "1").expect("write state flag");
    }

    fn live_path(&self) -> PathBuf {
        self.state_dir.join("live.txt")
    }

    fn snapshot_arg(&self) -> PathBuf {
        self.tmp_dir.join("policy.hujson")
    }

    fn clear_calls(&self) {
        let _ = fs::remove_file(self.state_dir.join("calls.log"));
    }

    fn run_once(&self) -> RunResult {
        self.run_once_with_policy_path(&self.policy_file)
    }

    fn run_once_with_policy_path(&self, policy_path: &Path) -> RunResult {
        let script = extract_sidecar_script();
        let cli_cfg = self.tmp_dir.join("cli.yaml");
        let orig_path = std::env::var("PATH").unwrap_or_default();
        let path_env = format!("{}:{orig_path}", self.bin_dir.display());

        let out = Command::new("sh")
            .arg("-c")
            .arg(&script)
            .env("PATH", path_env)
            .env("POLICY_FILE", policy_path)
            .env("TMP_DIR", &self.tmp_dir)
            .env("HEADSCALE_CONFIG", &cli_cfg)
            .env("POLICY_SYNC_ONCE", "1")
            .env("POLICY_SYNC_INTERVAL", "1")
            .env("STATE_DIR", &self.state_dir)
            .output()
            .expect("invoke sh -c <policy-sync script>");

        let cli_cfg_body =
            fs::read_to_string(&cli_cfg).expect("sidecar must write HEADSCALE_CONFIG");
        assert!(
            cli_cfg_body.contains("unix_socket: /var/run/headscale/headscale.sock"),
            "HEADSCALE_CONFIG missing unix_socket: {cli_cfg_body}"
        );

        let calls_path = self.state_dir.join("calls.log");
        let calls = if calls_path.exists() {
            fs::read_to_string(&calls_path)
                .expect("read calls.log")
                .lines()
                .map(str::to_string)
                .collect()
        } else {
            Vec::new()
        };

        RunResult {
            exit_code: out.status.code(),
            stdout: String::from_utf8_lossy(&out.stdout).into_owned(),
            stderr: String::from_utf8_lossy(&out.stderr).into_owned(),
            calls,
        }
    }
}

impl Drop for CaseEnv {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.root);
    }
}

#[test]
fn part_a_values_structure_and_configmap_binding() {
    assert!(
        resolve_data_path(PKG_DIR, "applicationset.yaml").is_file(),
        "applicationset.yaml data dependency must resolve"
    );
    let hs = load_headscale_values();

    // 1. sidecars.policy-sync command & securityContext.
    let sidecar = hs
        .pointer("/sidecars/policy-sync")
        .expect("missing sidecars.policy-sync");
    let _script = extract_sidecar_script();

    let sc = sidecar
        .get("securityContext")
        .expect("missing sidecars.policy-sync.securityContext");
    assert_eq!(sc.get("runAsNonRoot").and_then(|v| v.as_bool()), Some(true));
    assert_eq!(
        sc.get("readOnlyRootFilesystem").and_then(|v| v.as_bool()),
        Some(true)
    );
    assert_eq!(
        sc.get("allowPrivilegeEscalation").and_then(|v| v.as_bool()),
        Some(false)
    );
    let dropped: Vec<&str> = sc
        .pointer("/capabilities/drop")
        .and_then(|v| v.as_array())
        .expect("missing securityContext.capabilities.drop")
        .iter()
        .filter_map(|v| v.as_str())
        .collect();
    assert!(
        dropped.contains(&"ALL"),
        "capabilities.drop must contain ALL, got {dropped:?}"
    );
    assert_eq!(sc.get("runAsGroup").and_then(|v| v.as_i64()), Some(0));

    // 2. persistence.socket & sidecar socket mount.
    assert_eq!(
        hs.pointer("/persistence/socket/type")
            .and_then(|v| v.as_str()),
        Some("emptyDir")
    );
    assert_eq!(
        hs.pointer("/persistence/socket/mountPath")
            .and_then(|v| v.as_str()),
        Some("/var/run/headscale")
    );

    let mounts = sidecar
        .get("volumeMounts")
        .and_then(|v| v.as_array())
        .expect("missing sidecars.policy-sync.volumeMounts");
    let find_mount = |name: &str| {
        mounts
            .iter()
            .find(|m| m.get("name").and_then(|v| v.as_str()) == Some(name))
    };

    let socket_mount = find_mount("socket").expect("sidecar must mount volume 'socket'");
    assert_eq!(
        socket_mount.get("mountPath").and_then(|v| v.as_str()),
        Some("/var/run/headscale")
    );

    // 3. persistence.policy & sidecar directory mount (readOnly, NO subPath).
    assert_eq!(
        hs.pointer("/persistence/policy/type")
            .and_then(|v| v.as_str()),
        Some("configMap")
    );
    assert_eq!(
        hs.pointer("/persistence/policy/name")
            .and_then(|v| v.as_str()),
        Some(POLICY_CONFIGMAP_NAME)
    );
    let policy_mount = find_mount("policy").expect("sidecar must mount volume 'policy'");
    let policy_mount_obj = policy_mount
        .as_object()
        .expect("policy volumeMount must be a mapping");
    assert_eq!(
        policy_mount_obj.get("mountPath").and_then(|v| v.as_str()),
        Some("/etc/headscale-policy")
    );
    assert_eq!(
        policy_mount_obj.get("readOnly").and_then(|v| v.as_bool()),
        Some(true)
    );
    assert!(
        !policy_mount_obj.contains_key("subPath") && !policy_mount_obj.contains_key("subPathExpr"),
        "policy mount must not use subPath/subPathExpr so kubelet refreshes ConfigMap updates: {policy_mount:?}"
    );

    // 4. automountServiceAccountToken is false.
    assert_eq!(
        hs.get("automountServiceAccountToken")
            .and_then(|v| v.as_bool()),
        Some(false)
    );

    // 5. env.HEADSCALE_UNIX_SOCKET_PERMISSION is the string "0770" (not an integer).
    let sock_perm = hs
        .pointer("/env/HEADSCALE_UNIX_SOCKET_PERMISSION")
        .expect("missing env.HEADSCALE_UNIX_SOCKET_PERMISSION");
    assert!(
        sock_perm.is_string(),
        "HEADSCALE_UNIX_SOCKET_PERMISSION must be a quoted YAML string, got {sock_perm:?}"
    );
    assert_eq!(sock_perm.as_str(), Some("0770"));

    // 6. env.HEADSCALE_POLICY_MODE is database.
    assert_eq!(
        hs.pointer("/env/HEADSCALE_POLICY_MODE")
            .and_then(|v| v.as_str()),
        Some("database")
    );

    // Shipped ConfigMap manifest ties to persistence.policy.name in namespace headscale.
    let cm_docs = load_docs(POLICY_CONFIGMAP_FILENAME);
    assert_eq!(
        cm_docs.len(),
        1,
        "configmap-policy.yaml must contain exactly one document"
    );
    let cm = single_doc_of_kind(&cm_docs, "ConfigMap");
    assert_eq!(
        cm.pointer("/metadata/name").and_then(|v| v.as_str()),
        Some(POLICY_CONFIGMAP_NAME)
    );
    assert_eq!(
        cm.pointer("/metadata/namespace").and_then(|v| v.as_str()),
        Some("headscale")
    );
    assert!(
        cm.pointer(&format!("/data/{POLICY_FILENAME}"))
            .is_some_and(|v| v.is_string()),
        "ConfigMap headscale-policy must carry data[{POLICY_FILENAME:?}]"
    );
}

#[test]
fn case_a_missing_policy_file_skips_without_calling_headscale() {
    let env = CaseEnv::new("case-a-missing");
    let missing = env.root.join("does-not-exist.hujson");

    let res = env.run_once_with_policy_path(&missing);
    assert_eq!(res.exit_code, Some(0), "stderr: {}", res.stderr);
    assert!(
        res.calls.is_empty(),
        "expected no headscale calls when policy file is missing, got {:?}",
        res.calls
    );
    assert!(
        res.stdout.contains("not readable yet"),
        "stdout: {}",
        res.stdout
    );
}

#[test]
fn case_b_live_equals_file_byte_for_byte_is_in_sync() {
    let env = CaseEnv::new("case-b-in-sync");
    let policy = "// mesh policy\n{\n  \"acls\": []\n}\n";
    env.write_policy(policy);
    env.write_live(policy);

    let res = env.run_once();
    assert_eq!(res.exit_code, Some(0), "stderr: {}", res.stderr);
    assert_eq!(res.calls, vec!["policy get"]);
    assert!(res.stdout.contains("in sync"), "stdout: {}", res.stdout);
}

#[test]
fn case_c_file_with_extra_trailing_newlines_treated_as_in_sync() {
    let env = CaseEnv::new("case-c-trailing-nl");
    let live = "{\n  \"acls\": []\n}\n";
    let file_with_extra_nl = "{\n  \"acls\": []\n}\n\n";
    env.write_live(live);
    env.write_policy(file_with_extra_nl);

    let res = env.run_once();
    assert_eq!(res.exit_code, Some(0), "stderr: {}", res.stderr);
    assert_eq!(res.calls, vec!["policy get"]);
    assert!(res.stdout.contains("in sync"), "stdout: {}", res.stdout);
    assert_eq!(fs::read_to_string(env.live_path()).unwrap(), live);
}

#[test]
fn case_d_notfound_runs_get_check_set_and_populates_live() {
    let env = CaseEnv::new("case-d-notfound");
    let policy = "{\n  \"acls\": [\n    {\"action\": \"accept\", \"src\": [\"james@\"], \"dst\": [\"*:*\"]}\n  ]\n}\n";
    env.write_policy(policy);
    env.set_mode("notfound");

    let snap = env.snapshot_arg();
    let res = env.run_once();
    assert_eq!(res.exit_code, Some(0), "stderr: {}", res.stderr);
    assert_eq!(
        res.calls,
        vec![
            "policy get".to_string(),
            format!("policy check -f {}", snap.display()),
            format!("policy set -f {}", snap.display()),
        ]
    );
    assert!(res.stdout.contains("applied"), "stdout: {}", res.stdout);
    assert_eq!(fs::read_to_string(env.live_path()).unwrap(), policy);
}

#[test]
fn case_e_live_differs_runs_get_check_set_and_updates_live() {
    let env = CaseEnv::new("case-e-diff");
    let old_live = "{\n  \"acls\": []\n}\n";
    let new_policy = "{\n  \"acls\": [\n    {\"action\": \"accept\", \"src\": [\"james@\"], \"dst\": [\"*:*\"]}\n  ]\n}\n";
    env.write_live(old_live);
    env.write_policy(new_policy);

    let snap = env.snapshot_arg();
    let res = env.run_once();
    assert_eq!(res.exit_code, Some(0), "stderr: {}", res.stderr);
    assert_eq!(
        res.calls,
        vec![
            "policy get".to_string(),
            format!("policy check -f {}", snap.display()),
            format!("policy set -f {}", snap.display()),
        ]
    );
    assert!(res.stdout.contains("applied"), "stdout: {}", res.stdout);
    assert_eq!(fs::read_to_string(env.live_path()).unwrap(), new_policy);
}

#[test]
fn case_f_check_fail_prevents_set_and_leaves_live_unchanged() {
    let env = CaseEnv::new("case-f-check-fail");
    let old_live = "{\n  \"acls\": []\n}\n";
    let bad_policy = "{\n  \"acls\": [broken\n}\n";
    env.write_live(old_live);
    env.write_policy(bad_policy);
    env.set_flag("check_fail");

    let snap = env.snapshot_arg();
    let res = env.run_once();
    assert_eq!(res.exit_code, Some(0), "stderr: {}", res.stderr);
    assert_eq!(
        res.calls,
        vec![
            "policy get".to_string(),
            format!("policy check -f {}", snap.display()),
        ]
    );
    assert!(
        res.stdout.contains("check FAILED"),
        "stdout: {}",
        res.stdout
    );
    assert_eq!(fs::read_to_string(env.live_path()).unwrap(), old_live);
}

#[test]
fn case_g_set_fail_attempts_set_after_check_and_leaves_live_unchanged() {
    let env = CaseEnv::new("case-g-set-fail");
    let old_live = "{\n  \"acls\": []\n}\n";
    let new_policy = "{\n  \"acls\": [\n    {\"action\": \"accept\", \"src\": [\"james@\"], \"dst\": [\"*:*\"]}\n  ]\n}\n";
    env.write_live(old_live);
    env.write_policy(new_policy);
    env.set_flag("set_fail");

    let snap = env.snapshot_arg();
    let res = env.run_once();
    assert_eq!(res.exit_code, Some(0), "stderr: {}", res.stderr);
    assert_eq!(
        res.calls,
        vec![
            "policy get".to_string(),
            format!("policy check -f {}", snap.display()),
            format!("policy set -f {}", snap.display()),
        ]
    );
    assert!(res.stdout.contains("set FAILED"), "stdout: {}", res.stdout);
    assert_eq!(fs::read_to_string(env.live_path()).unwrap(), old_live);
}

#[test]
fn case_h_mode_down_reports_not_ready_and_skips_check_and_set() {
    let env = CaseEnv::new("case-h-down");
    env.write_policy("{\n  \"acls\": []\n}\n");
    env.set_mode("down");

    let res = env.run_once();
    assert_eq!(res.exit_code, Some(0), "stderr: {}", res.stderr);
    assert_eq!(res.calls, vec!["policy get"]);
    assert!(res.stdout.contains("not ready"), "stdout: {}", res.stdout);
    assert!(!env.live_path().exists());
}

#[test]
fn case_i_comment_and_no_trailing_newline_round_trips_in_sync() {
    let env = CaseEnv::new("case-i-roundtrip");
    let policy_no_nl =
        "// comment line without trailing newline\n{\n  \"acls\": [\n    {\"action\": \"accept\", \"src\": [\"james@\"], \"dst\": [\"*:*\"]}\n  ]\n}";
    assert!(!policy_no_nl.ends_with('\n'));
    env.write_policy(policy_no_nl);
    env.set_mode("notfound");

    let snap = env.snapshot_arg();
    let first = env.run_once();
    assert_eq!(first.exit_code, Some(0), "stderr: {}", first.stderr);
    assert_eq!(
        first.calls,
        vec![
            "policy get".to_string(),
            format!("policy check -f {}", snap.display()),
            format!("policy set -f {}", snap.display()),
        ]
    );
    assert!(first.stdout.contains("applied"), "stdout: {}", first.stdout);
    assert_eq!(fs::read_to_string(env.live_path()).unwrap(), policy_no_nl);

    env.clear_calls();
    let second = env.run_once();
    assert_eq!(second.exit_code, Some(0), "stderr: {}", second.stderr);
    assert_eq!(second.calls, vec!["policy get"]);
    assert!(
        second.stdout.contains("in sync"),
        "stdout: {}",
        second.stdout
    );
}
