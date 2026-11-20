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
    POLICY_CONFIGMAP_NAME, POLICY_FILENAME, POLICY_PAUSE_CONFIGMAP_NAME, POLICY_SYNC_METRICS_PORT,
    POLICY_SYNC_PORT_NAME, POLICY_SYNC_SERVICE_FILENAME, SOCKET_GID,
};

const FAKE_HEADSCALE_SH: &str = r#"#!/bin/sh
set -eu
printf '%s\n' "$*" >>"$STATE_DIR/calls.log"

if [ "$#" -eq 2 ] && [ "$1" = "policy" ] && [ "$2" = "get" ]; then
  if [ -f "$STATE_DIR/wait_httpd" ]; then
    i=0
    while [ ! -s "$STATE_DIR/httpd.args" ] && [ "$i" -lt 40 ]; do
      sleep 0.05 2>/dev/null || sleep 1
      i=$((i + 1))
    done
    rm -f "$STATE_DIR/wait_httpd"
  fi
  if [ -f "$STATE_DIR/live.txt" ]; then
    # Real headscale prints stored p.Data via fmt.Println (one trailing '\n').
    cat "$STATE_DIR/live.txt"
    printf '\n'
    if [ -f "$STATE_DIR/down_after_first_get" ]; then
      rm -f "$STATE_DIR/down_after_first_get" "$STATE_DIR/live.txt"
      printf 'down' >"$STATE_DIR/mode"
    fi
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
    pause_file: PathBuf,
}

struct Metrics {
    up: i64,
    last_success: i64,
    paused: i64,
}

struct RunResult {
    exit_code: Option<i32>,
    stdout: String,
    stderr: String,
    calls: Vec<String>,
    metrics: Metrics,
}

fn parse_metrics_file(raw: &str) -> Metrics {
    for secret_needle in ["acls", "tag:ci", "james@", "policy.hujson"] {
        assert!(
            !raw.contains(secret_needle),
            "metrics file must never leak policy content ({secret_needle}): {raw}"
        );
    }
    let mut up = None;
    let mut last_success = None;
    let mut paused = None;
    for metric_name in [
        "headscale_policy_sync_up",
        "headscale_policy_sync_last_success_timestamp_seconds",
        "headscale_policy_sync_paused",
    ] {
        assert!(
            raw.contains(&format!("# HELP {metric_name} ")),
            "missing HELP for {metric_name}: {raw}"
        );
        assert!(
            raw.contains(&format!("# TYPE {metric_name} gauge")),
            "missing TYPE gauge for {metric_name}: {raw}"
        );
    }
    for line in raw.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let mut parts = line.split_whitespace();
        let name = parts.next().expect("metric name");
        let val: i64 = parts
            .next()
            .expect("metric value")
            .parse()
            .unwrap_or_else(|e| panic!("invalid metric value on '{line}': {e}"));
        assert!(parts.next().is_none(), "unexpected trailing tokens: {line}");
        match name {
            "headscale_policy_sync_up" => up = Some(val),
            "headscale_policy_sync_last_success_timestamp_seconds" => last_success = Some(val),
            "headscale_policy_sync_paused" => paused = Some(val),
            other => panic!("unexpected metric '{other}' in:\n{raw}"),
        }
    }
    Metrics {
        up: up.expect("missing headscale_policy_sync_up"),
        last_success: last_success
            .expect("missing headscale_policy_sync_last_success_timestamp_seconds"),
        paused: paused.expect("missing headscale_policy_sync_paused"),
    }
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
        let pause_file = root.join("paused");
        Self {
            root,
            bin_dir,
            state_dir,
            tmp_dir,
            policy_file,
            pause_file,
        }
    }

    fn write_pause_marker(&self, content: &str) {
        fs::write(&self.pause_file, content).expect("write pause marker");
    }

    fn remove_pause_marker(&self) {
        let _ = fs::remove_file(&self.pause_file);
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
        self.run_with_extra_env(policy_path, &[("POLICY_SYNC_ONCE", "1")])
    }

    fn run_with_extra_env(&self, policy_path: &Path, extra_env: &[(&str, &str)]) -> RunResult {
        let script = extract_sidecar_script();
        let cli_cfg = self.tmp_dir.join("cli.yaml");
        let metrics_dir = self.tmp_dir.join("metrics");
        let orig_path = std::env::var("PATH").unwrap_or_default();
        let path_env = format!("{}:{orig_path}", self.bin_dir.display());

        let mut cmd = Command::new("sh");
        cmd.arg("-c")
            .arg(&script)
            .env("PATH", path_env)
            .env("POLICY_FILE", policy_path)
            .env("PAUSE_FILE", &self.pause_file)
            .env("TMP_DIR", &self.tmp_dir)
            .env("METRICS_DIR", &metrics_dir)
            .env("HEADSCALE_CONFIG", &cli_cfg)
            .env("POLICY_SYNC_INTERVAL", "0")
            .env("STATE_DIR", &self.state_dir);
        for (k, v) in extra_env {
            cmd.env(k, v);
        }
        let out = cmd.output().expect("invoke sh -c <policy-sync script>");

        let cli_cfg_body =
            fs::read_to_string(&cli_cfg).expect("sidecar must write HEADSCALE_CONFIG");
        assert!(
            cli_cfg_body.contains("unix_socket: /var/run/headscale/headscale.sock"),
            "HEADSCALE_CONFIG missing unix_socket: {cli_cfg_body}"
        );

        let metrics_file = metrics_dir.join("metrics");
        assert!(
            !metrics_dir.join("metrics.tmp").exists(),
            "metrics.tmp must be atomically renamed away after write_metrics"
        );
        let metrics_raw =
            fs::read_to_string(&metrics_file).expect("sidecar must write atomic metrics file");
        let metrics = parse_metrics_file(&metrics_raw);

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
            metrics,
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
    let fs_group = hs
        .pointer("/podSecurityContext/fsGroup")
        .and_then(|v| v.as_i64())
        .expect("missing podSecurityContext.fsGroup");
    assert_eq!(fs_group, SOCKET_GID);
    assert_ne!(fs_group, 0);
    assert_eq!(
        sc.get("runAsGroup").and_then(|v| v.as_i64()),
        Some(fs_group),
        "sidecar runAsGroup must match pod fsGroup"
    );
    let supp_groups: Vec<i64> = hs
        .pointer("/podSecurityContext/supplementalGroups")
        .and_then(|v| v.as_array())
        .expect("missing podSecurityContext.supplementalGroups")
        .iter()
        .filter_map(|v| v.as_i64())
        .collect();
    assert!(
        supp_groups.contains(&fs_group),
        "podSecurityContext.supplementalGroups must include {fs_group}, got {supp_groups:?}"
    );

    let ports = sidecar
        .get("ports")
        .and_then(|v| v.as_array())
        .expect("sidecars.policy-sync must declare ports");
    assert!(
        ports.iter().any(|p| {
            p.get("name").and_then(|v| v.as_str()) == Some(POLICY_SYNC_PORT_NAME)
                && p.get("containerPort").and_then(|v| v.as_i64()) == Some(POLICY_SYNC_METRICS_PORT)
        }),
        "sidecar ports must expose {POLICY_SYNC_PORT_NAME} on {POLICY_SYNC_METRICS_PORT}: {ports:?}"
    );

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

    // 3. persistence.policy, persistence.pause & sidecar directory mounts (readOnly, optional, NO subPath).
    for (key, cm_name) in [
        ("policy", POLICY_CONFIGMAP_NAME),
        ("pause", POLICY_PAUSE_CONFIGMAP_NAME),
    ] {
        assert_eq!(
            hs.pointer(&format!("/persistence/{key}/type"))
                .and_then(|v| v.as_str()),
            Some("custom")
        );
        assert_eq!(
            hs.pointer(&format!("/persistence/{key}/volumeSpec/configMap/name"))
                .and_then(|v| v.as_str()),
            Some(cm_name)
        );
        assert_eq!(
            hs.pointer(&format!("/persistence/{key}/volumeSpec/configMap/optional"))
                .and_then(|v| v.as_bool()),
            Some(true)
        );
    }
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

    let pause_mount = find_mount("pause").expect("sidecar must mount volume 'pause'");
    let pause_mount_obj = pause_mount
        .as_object()
        .expect("pause volumeMount must be a mapping");
    assert_eq!(
        pause_mount_obj.get("mountPath").and_then(|v| v.as_str()),
        Some("/etc/headscale-policy-pause")
    );
    assert_eq!(
        pause_mount_obj.get("readOnly").and_then(|v| v.as_bool()),
        Some(true)
    );
    assert!(
        !pause_mount_obj.contains_key("subPath") && !pause_mount_obj.contains_key("subPathExpr"),
        "pause mount must not use subPath/subPathExpr so kubelet refreshes ConfigMap updates: {pause_mount:?}"
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

    // Metrics Service follows service-key-exporter's kubernetes-service-endpoints pattern.
    let svc_docs = load_docs(POLICY_SYNC_SERVICE_FILENAME);
    let svc = single_doc_of_kind(&svc_docs, "Service");
    assert_eq!(
        svc.pointer("/metadata/name").and_then(|v| v.as_str()),
        Some("headscale-policy-sync")
    );
    assert_eq!(
        svc.pointer("/metadata/namespace").and_then(|v| v.as_str()),
        Some("headscale")
    );
    assert_eq!(
        svc.pointer("/metadata/annotations/prometheus.io~1scrape")
            .and_then(|v| v.as_str()),
        Some("true")
    );
    assert_eq!(
        svc.pointer("/metadata/annotations/prometheus.io~1port")
            .and_then(|v| v.as_str()),
        Some("9102")
    );
    assert_eq!(
        svc.pointer("/metadata/annotations/prometheus.io~1path")
            .and_then(|v| v.as_str()),
        Some("/metrics")
    );
    assert_eq!(
        svc.pointer("/spec/selector/app.kubernetes.io~1name")
            .and_then(|v| v.as_str()),
        Some("headscale")
    );
    assert_eq!(
        svc.pointer("/spec/selector/app.kubernetes.io~1instance")
            .and_then(|v| v.as_str()),
        Some("headscale")
    );
    let svc_ports = svc
        .pointer("/spec/ports")
        .and_then(|v| v.as_array())
        .expect("service-policy-sync missing spec.ports");
    assert_eq!(svc_ports.len(), 1);
    assert_eq!(
        svc_ports[0].get("port").and_then(|v| v.as_i64()),
        Some(POLICY_SYNC_METRICS_PORT)
    );
    assert_eq!(
        svc_ports[0].get("targetPort").and_then(|v| v.as_str()),
        Some(POLICY_SYNC_PORT_NAME)
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
        res.stdout
            .contains("policy-sync: policy file absent, skipping"),
        "stdout: {}",
        res.stdout
    );
    assert_eq!(res.metrics.up, 1);
    assert!(res.metrics.last_success > 0);
    assert_eq!(res.metrics.paused, 0);
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
    assert_eq!(res.metrics.up, 1);
    assert!(res.metrics.last_success > 0);
    assert_eq!(res.metrics.paused, 0);
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
    assert_eq!(res.metrics.up, 1);
    assert!(res.metrics.last_success > 0);
    assert_eq!(res.metrics.paused, 0);
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
    assert_eq!(res.metrics.up, 1);
    assert!(res.metrics.last_success > 0);
    assert_eq!(res.metrics.paused, 0);
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
    assert_eq!(res.metrics.up, 1);
    assert!(res.metrics.last_success > 0);
    assert_eq!(res.metrics.paused, 0);
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
    assert_eq!(res.metrics.up, 0);
    assert_eq!(res.metrics.last_success, 0);
    assert_eq!(res.metrics.paused, 0);
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
    assert_eq!(res.metrics.up, 0);
    assert_eq!(res.metrics.last_success, 0);
    assert_eq!(res.metrics.paused, 0);
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
    assert_eq!(res.metrics.up, 0);
    assert_eq!(res.metrics.last_success, 0);
    assert_eq!(res.metrics.paused, 0);
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
    assert_eq!(first.metrics.up, 1);
    assert!(first.metrics.last_success > 0);
    assert_eq!(first.metrics.paused, 0);

    env.clear_calls();
    let second = env.run_once();
    assert_eq!(second.exit_code, Some(0), "stderr: {}", second.stderr);
    assert_eq!(second.calls, vec!["policy get"]);
    assert!(
        second.stdout.contains("in sync"),
        "stdout: {}",
        second.stdout
    );
    assert_eq!(second.metrics.up, 1);
    assert!(second.metrics.last_success > 0);
    assert_eq!(second.metrics.paused, 0);
}

#[test]
fn case_j_pause_marker_skips_without_calling_headscale() {
    let env = CaseEnv::new("case-j-pause");
    let old_live = "{\n  \"acls\": []\n}\n";
    let new_policy =
        "{\n  \"acls\": [\n    {\"action\": \"accept\", \"src\": [\"james@\"], \"dst\": [\"*:*\"]}\n  ]\n}\n";
    env.write_live(old_live);
    env.write_policy(new_policy);
    env.write_pause_marker("");

    let paused = env.run_once();
    assert_eq!(paused.exit_code, Some(0), "stderr: {}", paused.stderr);
    assert!(
        paused.calls.is_empty(),
        "expected no headscale calls while paused, got {:?}",
        paused.calls
    );
    assert!(
        paused.stdout.contains("policy-sync: paused"),
        "stdout: {}",
        paused.stdout
    );
    assert_eq!(fs::read_to_string(env.live_path()).unwrap(), old_live);
    assert_eq!(paused.metrics.paused, 1);
    assert_eq!(paused.metrics.up, 0);
    assert_eq!(paused.metrics.last_success, 0);

    env.remove_pause_marker();
    let resumed = env.run_once();
    assert_eq!(resumed.exit_code, Some(0), "stderr: {}", resumed.stderr);
    assert_eq!(resumed.calls.len(), 3, "calls: {:?}", resumed.calls);
    assert!(
        resumed.stdout.contains("applied"),
        "stdout: {}",
        resumed.stdout
    );
    assert_eq!(fs::read_to_string(env.live_path()).unwrap(), new_policy);
    assert_eq!(resumed.metrics.paused, 0);
    assert_eq!(resumed.metrics.up, 1);
    assert!(resumed.metrics.last_success > 0);
}

#[test]
fn case_k_metrics_preserve_last_success_on_later_failure_and_survive_httpd_failure() {
    // 1. Tick 1 succeeds (`in sync`), Tick 2 fails (`not ready`): up=0, last_success preserved > 0.
    let env = CaseEnv::new("case-k-preserve");
    let policy =
        "{\n  \"acls\": [{\"action\": \"accept\", \"src\": [\"james@\"], \"dst\": [\"*:*\"]}]\n}\n";
    env.write_policy(policy);
    env.write_live(policy);
    env.set_flag("down_after_first_get");

    let multi = env.run_with_extra_env(&env.policy_file, &[("POLICY_SYNC_MAX_LOOPS", "2")]);
    assert_eq!(multi.exit_code, Some(0), "stderr: {}", multi.stderr);
    assert_eq!(multi.calls, vec!["policy get", "policy get"]);
    assert!(multi.stdout.contains("in sync"), "stdout: {}", multi.stdout);
    assert!(
        multi.stdout.contains("headscale not ready"),
        "stdout: {}",
        multi.stdout
    );
    assert_eq!(multi.metrics.up, 0);
    assert!(
        multi.metrics.last_success > 0,
        "last_success must retain tick 1 timestamp after tick 2 failure"
    );
    assert_eq!(multi.metrics.paused, 0);

    // 2. Fake httpd that records arguments and exits 1 immediately: loop still runs and emits metrics.
    let fake_httpd = env.bin_dir.join("fake-httpd");
    let httpd_args = env.state_dir.join("httpd.args");
    fs::write(
        &fake_httpd,
        format!(
            "#!/bin/sh\nprintf '%s\\n' \"$*\" > '{}.tmp' && mv -f '{}.tmp' '{}'\nexit 1\n",
            httpd_args.display(),
            httpd_args.display(),
            httpd_args.display()
        ),
    )
    .unwrap();
    let mut perms = fs::metadata(&fake_httpd).unwrap().permissions();
    perms.set_mode(0o755);
    fs::set_permissions(&fake_httpd, perms).unwrap();

    env.write_live(policy);
    env.set_flag("wait_httpd");
    let dying_httpd = env.run_with_extra_env(
        &env.policy_file,
        &[
            ("POLICY_SYNC_ONCE", "1"),
            ("HTTPD_BIN", fake_httpd.to_str().unwrap()),
        ],
    );
    assert_eq!(
        dying_httpd.exit_code,
        Some(0),
        "stderr: {}",
        dying_httpd.stderr
    );
    assert_eq!(dying_httpd.metrics.up, 1);
    assert!(dying_httpd.metrics.last_success > 0);
    assert_eq!(dying_httpd.metrics.paused, 0);
    let recorded_httpd = fs::read_to_string(&httpd_args).unwrap();
    assert!(
        recorded_httpd.contains("-f -p 9102 -h "),
        "unexpected httpd args: {recorded_httpd}"
    );

    // 3. Absent httpd binary: loop still runs and emits metrics cleanly.
    let missing_httpd = env.root.join("nonexistent-httpd");
    let no_httpd = env.run_with_extra_env(
        &env.policy_file,
        &[
            ("POLICY_SYNC_ONCE", "1"),
            ("HTTPD_BIN", missing_httpd.to_str().unwrap()),
        ],
    );
    assert_eq!(no_httpd.exit_code, Some(0), "stderr: {}", no_httpd.stderr);
    assert_eq!(no_httpd.metrics.up, 1);
    assert!(no_httpd.metrics.last_success > 0);
    assert_eq!(no_httpd.metrics.paused, 0);
}
