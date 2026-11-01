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

//! Black-box guard for the preview-reaper binary. Stubs `gh`, `gcloud`,
//! `kubectl` and `curl` on PATH and asserts exactly which Cloud Run services,
//! namespaces and Neon branches get deleted, the TTL rule, the protected-name
//! exclusions, DRY_RUN, the four `key=value` lines the workflow appends to
//! $GITHUB_OUTPUT, and the Neon credential / missing-curl guards (#2159).
//!
//! The binary is the only thing under test, so it is addressed through
//! PREVIEW_REAPER_BIN. Any executable honouring the same contract can be
//! pointed at: that is how the shell original was proven equivalent before it
//! was removed.

use std::path::{Path, PathBuf};
use std::process::{Command, Output};

fn binary() -> PathBuf {
    let rel = std::env::var("PREVIEW_REAPER_BIN").expect("set by Bazel");
    std::env::current_dir().unwrap().join(rel)
}

/// 2023-11-14T22:13:20Z, the clock every case runs on.
const NOW: &str = "1700000000";

struct Fixture {
    work: PathBuf,
    stubs: PathBuf,
}

fn write_exec(path: &Path, body: &str) {
    use std::os::unix::fs::PermissionsExt;
    std::fs::write(path, body).unwrap();
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o755)).unwrap();
}

impl Fixture {
    fn new() -> Fixture {
        use std::sync::atomic::{AtomicU32, Ordering};
        static N: AtomicU32 = AtomicU32::new(0);
        let base = std::env::var("TEST_TMPDIR").unwrap_or_else(|_| "/tmp".into());
        let work = Path::new(&base).join(format!(
            "preview-reaper-{}-{}",
            std::process::id(),
            N.fetch_add(1, Ordering::SeqCst)
        ));
        let _ = std::fs::remove_dir_all(&work);
        let stubs = work.join("stubs");
        std::fs::create_dir_all(&stubs).unwrap();

        // gh: `gh pr view <n> ...` answers from STUB_PRS ("num:STATE:createdAt;...");
        // an unlisted PR fails, as an unreadable one would.
        write_exec(
            &stubs.join("gh"),
            r#"#!/usr/bin/env bash
if [ "${1:-}" = "pr" ] && [ "${2:-}" = "view" ]; then
  num="${3:-}"
  IFS=';' read -r -a items <<< "${STUB_PRS:-}"
  for item in "${items[@]}"; do
    IFS='|' read -r p_num p_state p_created <<< "$item"
    if [ "$p_num" = "$num" ]; then
      printf '{"state":"%s","createdAt":"%s"}\n' "$p_state" "$p_created"
      exit 0
    fi
  done
  exit 1
fi
exit 0
"#,
        );
        write_exec(
            &stubs.join("gcloud"),
            r#"#!/usr/bin/env bash
if [ "${1:-}" = "run" ] && [ "${2:-}" = "services" ] && [ "${3:-}" = "list" ]; then
  if [ -n "${STUB_CR_LIST_RC:-}" ]; then
    printf 'tabula-api-pr-101\t2023-11-14T10:00:00Z\n'
    echo "ERROR: (gcloud.run.services.list) PERMISSION_DENIED: run.services.list denied" >&2
    exit "$STUB_CR_LIST_RC"
  fi
  [ -n "${STUB_CR_LIST:-}" ] && { printf '%b' "$STUB_CR_LIST"; exit 0; }
  printf 'tabula-api-pr-101\t2023-11-14T10:00:00Z\n'
  printf 'tabula-api-pr-102\t2023-11-14T10:00:00Z\n'
  printf 'tabula-api-pr-103\t2023-11-14T20:00:00Z\n'
  printf 'tabula-api-pr-104\t2023-11-13T10:00:00Z\n'
  printf 'tabula-api-pr-200\t2023-11-14T20:00:00Z\n'
  printf 'tabula-api-dev\t2023-11-14T10:00:00Z\n'
  printf 'tabula-api-prod\t2023-11-14T10:00:00Z\n'
  exit 0
fi
if [ "${1:-}" = "run" ] && [ "${2:-}" = "services" ] && [ "${3:-}" = "delete" ]; then
  echo "${4:-}" >> "$CR_DELETED"
  exit "${STUB_CR_DELETE_RC:-0}"
fi
exit 0
"#,
        );
        write_exec(
            &stubs.join("kubectl"),
            r#"#!/usr/bin/env bash
if [ "${1:-}" = "config" ] && [ "${2:-}" = "current-context" ]; then
  [ -n "${STUB_K8S_NO_CONTEXT:-}" ] && { echo "error: current-context is not set" >&2; exit 1; }
  echo test-cluster
  exit 0
fi
if [ "${1:-}" = "get" ] && [ "${2:-}" = "namespaces" ]; then
  if [ -n "${STUB_K8S_LIST_RC:-}" ]; then
    printf 'pr-101\t2023-11-14T10:00:00Z\n'
    echo "error: You must be logged in to the server (Unauthorized)" >&2
    exit "$STUB_K8S_LIST_RC"
  fi
  [ -n "${STUB_K8S_LIST:-}" ] && { printf '%b' "$STUB_K8S_LIST"; exit 0; }
  printf 'pr-101\t2023-11-14T10:00:00Z\n'
  printf 'pr-102\t2023-11-14T10:00:00Z\n'
  printf 'pr-103\t2023-11-14T20:00:00Z\n'
  printf 'pr-104\t2023-11-13T10:00:00Z\n'
  printf 'pr-200\t2023-11-14T20:00:00Z\n'
  printf 'default\t2023-11-14T10:00:00Z\n'
  printf 'kube-system\t2023-11-14T10:00:00Z\n'
  printf 'argocd\t2023-11-14T10:00:00Z\n'
  exit 0
fi
if [ "${1:-}" = "delete" ] && [ "${2:-}" = "namespace" ]; then
  echo "${3:-}" >> "$K8S_DELETED"
  exit "${STUB_K8S_DELETE_RC:-0}"
fi
exit 0
"#,
        );
        write_exec(
            &stubs.join("curl"),
            r#"#!/usr/bin/env bash
# Every argv, one call per line: the API key must never be in one (ps shows
# argv to every local user). It is read from `--config -` on stdin instead,
# and a call that does not present it there is refused as the API would.
printf '%s\n' "$*" >> "$CURL_ARGV"
auth=""
case " $* " in *" --config - "*|*" -K - "*)
  cfg="$(cat)"
  printf '%s\n' "$cfg" >> "$CURL_CONFIG"
  case "$cfg" in *'header = "Authorization: Bearer test-key"'*) auth=ok ;; esac
  ;;
esac
if [ "$auth" != ok ]; then
  case " $* " in *" --fail-with-body "*) printf '{"message":"no API key"}' ;; esac
  exit 22
fi
if [[ "$*" == *"-X DELETE"* ]]; then
  echo "$*" | sed 's|.*/branches/||' | awk '{print $1}' >> "$NEON_DELETED"
  # A real curl only reports an HTTP error status when asked to (-f / --fail).
  if [ -n "${STUB_NEON_HTTP_ERROR:-}" ]; then
    case " $* " in *" -f "*|*" -sf "*|*" --fail "*) exit 22 ;; esac
  fi
  exit "${STUB_NEON_DELETE_RC:-0}"
fi
if [[ "$*" == *"api/v2/projects/test-proj/branches"* ]]; then
  printf '%s\n' "$@" > "$NEON_LIST_ARGS"
  # As a real curl does: a transport failure is only described on stderr
  # with -S (-s alone silences it), and an HTTP error status still exits 0
  # with the error body unless --fail / --fail-with-body asks otherwise.
  if [ -n "${STUB_NEON_LIST_CURL_RC:-}" ]; then
    case " $* " in *" -sS "*|*" -S "*|*" --show-error "*)
      echo "curl: (${STUB_NEON_LIST_CURL_RC}) Could not resolve host: console.neon.tech" >&2 ;;
    esac
    exit "$STUB_NEON_LIST_CURL_RC"
  fi
  if [ -n "${STUB_NEON_LIST_HTTP_ERROR:-}" ]; then
    case " $* " in
      *" --fail-with-body "*) printf '%s' "$STUB_NEON_LIST_HTTP_ERROR"; exit 22 ;;
      *" -f "*|*" -sf "*|*" --fail "*) exit 22 ;;
    esac
    printf '%s' "$STUB_NEON_LIST_HTTP_ERROR"
    exit 0
  fi
  [ -n "${STUB_NEON_JSON:-}" ] && { printf '%s' "$STUB_NEON_JSON"; exit 0; }
  cat <<'JSON'
{
  "branches": [
    {"id": "br-101", "name": "tabula-pr-101", "created_at": "2023-11-14T10:00:00Z", "primary": false},
    {"id": "br-102", "name": "tabula-pr-102", "created_at": "2023-11-14T10:00:00Z", "primary": false},
    {"id": "br-103", "name": "tabula-pr-103", "created_at": "2023-11-14T20:00:00Z", "primary": false},
    {"id": "br-104", "name": "tabula-pr-104", "created_at": "2023-11-13T10:00:00Z", "primary": false},
    {"id": "br-200", "name": "tabula-pr-200", "created_at": "2023-11-14T20:00:00Z", "primary": false},
    {"id": "br-main", "name": "main", "created_at": "2023-11-14T10:00:00Z", "primary": true},
    {"id": "br-300", "name": "tabula-pr-300", "created_at": "2023-11-14T10:00:00Z", "primary": true}
  ]
}
JSON
  exit 0
fi
exit 0
"#,
        );
        Fixture { work, stubs }
    }

    fn deleted(&self, name: &str) -> Vec<String> {
        let mut v: Vec<String> = std::fs::read_to_string(self.work.join(name))
            .unwrap_or_default()
            .lines()
            .map(|s| s.to_string())
            .collect();
        v.sort();
        v
    }

    /// Runs the binary with a clean environment: only the stubs plus the system
    /// tools the stubs and python3 need are on PATH, so nothing real is touched.
    fn run(&self, args: &[&str], envs: &[(&str, &str)]) -> Output {
        for f in [
            "cr_deleted",
            "k8s_deleted",
            "neon_deleted",
            "neon_list_args",
            "curl_argv",
            "curl_config",
        ] {
            let _ = std::fs::remove_file(self.work.join(f));
        }
        let path = format!(
            "{}:{}",
            self.stubs.display(),
            std::env::var("PATH").unwrap_or_else(|_| "/usr/bin:/bin".into())
        );
        let mut c = Command::new(binary());
        c.args(args)
            .env_clear()
            .env("PATH", path)
            .env("CR_DELETED", self.work.join("cr_deleted"))
            .env("K8S_DELETED", self.work.join("k8s_deleted"))
            .env("NEON_DELETED", self.work.join("neon_deleted"))
            .env("NEON_LIST_ARGS", self.work.join("neon_list_args"))
            .env("CURL_ARGV", self.work.join("curl_argv"))
            .env("CURL_CONFIG", self.work.join("curl_config"))
            .env("GCP_PROJECT", "test-gcp")
            .env("NEON_API_KEY", "test-key")
            .env("NEON_PROJECT_ID", "test-proj")
            .env("PREVIEW_TTL_HOURS", "24")
            .env("NOW_EPOCH", NOW)
            .env(
                "STUB_PRS",
                "101|MERGED|2023-11-14T17:13:20+00:00;102|CLOSED|2023-11-14T17:13:20+00:00;103|OPEN|2023-11-14T20:13:20+00:00;104|OPEN|2023-11-13T16:13:20+00:00;200|CLOSED|2023-11-14T21:13:20+00:00;300|CLOSED|2023-11-14T21:13:20+00:00",
            );
        for (k, v) in envs {
            c.env(k, v);
        }
        c.output().expect("binary runs")
    }
}

fn stdout(o: &Output) -> String {
    String::from_utf8_lossy(&o.stdout).into_owned()
}
fn stderr(o: &Output) -> String {
    String::from_utf8_lossy(&o.stderr).into_owned()
}

#[test]
fn targeted_pr_deletes_only_that_prs_resources_everywhere() {
    let f = Fixture::new();
    let o = f.run(&["200"], &[]);
    assert_eq!(o.status.code(), Some(0), "{}", stderr(&o));
    assert_eq!(f.deleted("cr_deleted"), ["tabula-api-pr-200"]);
    assert_eq!(f.deleted("k8s_deleted"), ["pr-200"]);
    assert_eq!(f.deleted("neon_deleted"), ["br-200"]);
    assert_eq!(
        stdout(&o),
        "reaped_cloudrun=1\nreaped_k8s=1\nreaped_neon=1\ntotal_reaped=3\n"
    );
    assert!(stderr(&o).contains(
        "preview-reaper: Summary: reaped 1 Cloud Run services, 1 K8s namespaces, 1 Neon branches (total 3)"
    ));
}

#[test]
fn sweep_reaps_merged_closed_and_expired_and_keeps_active() {
    // 101 MERGED, 102 CLOSED, 104 OPEN but 36h old (> 24h TTL), 200 CLOSED are
    // reaped; 103 is OPEN and 2h old, so it stays.
    let f = Fixture::new();
    let o = f.run(&[], &[]);
    assert_eq!(o.status.code(), Some(0), "{}", stderr(&o));
    let want = ["101", "102", "104", "200"];
    assert_eq!(
        f.deleted("cr_deleted"),
        want.map(|n| format!("tabula-api-pr-{n}"))
    );
    assert_eq!(f.deleted("k8s_deleted"), want.map(|n| format!("pr-{n}")));
    assert_eq!(f.deleted("neon_deleted"), want.map(|n| format!("br-{n}")));
    assert_eq!(
        stdout(&o),
        "reaped_cloudrun=4\nreaped_k8s=4\nreaped_neon=4\ntotal_reaped=12\n"
    );
    let e = stderr(&o);
    assert!(
        e.contains("preview-reaper: PR #101 is MERGED \u{2014} marked for reap"),
        "{e}"
    );
    assert!(
        e.contains("preview-reaper: PR #102 is CLOSED \u{2014} marked for reap"),
        "{e}"
    );
    assert!(
        e.contains("preview-reaper: PR #103 is OPEN and active (2h / 24h) \u{2014} preserving"),
        "{e}"
    );
    assert!(
        e.contains(
            "preview-reaper: PR #104 is OPEN but age (36h) exceeds TTL (24h) \u{2014} marked for reap"
        ),
        "{e}"
    );
}

#[test]
fn protected_environments_are_never_targeted() {
    let f = Fixture::new();
    // PR lookups that succeed for everything would still never touch these.
    let o = f.run(&[], &[]);
    assert_eq!(o.status.code(), Some(0));
    let all = [
        f.deleted("cr_deleted"),
        f.deleted("k8s_deleted"),
        f.deleted("neon_deleted"),
    ]
    .concat()
    .join(" ");
    // br-300 is a PR-named branch of a CLOSED PR, but it is the primary branch.
    for protected in [
        "tabula-api-dev",
        "tabula-api-prod",
        "default",
        "kube-system",
        "argocd",
        "br-main",
        "br-300",
    ] {
        assert!(!all.contains(protected), "deleted {protected}: {all}");
    }
}

#[test]
fn dry_run_deletes_nothing_but_counts_what_it_would() {
    let f = Fixture::new();
    let o = f.run(&[], &[("DRY_RUN", "1")]);
    assert_eq!(o.status.code(), Some(0));
    assert!(!f.work.join("cr_deleted").exists());
    assert!(!f.work.join("k8s_deleted").exists());
    assert!(!f.work.join("neon_deleted").exists());
    assert_eq!(
        stdout(&o),
        "reaped_cloudrun=4\nreaped_k8s=4\nreaped_neon=4\ntotal_reaped=12\n"
    );
    let e = stderr(&o);
    assert!(
        e.contains("[DRY_RUN] Would delete Cloud Run service 'tabula-api-pr-101' (PR #101)"),
        "{e}"
    );
    assert!(
        e.contains("[DRY_RUN] Would delete K8s namespace 'pr-101' (PR #101)"),
        "{e}"
    );
    assert!(
        e.contains("[DRY_RUN] Would delete Neon branch 'tabula-pr-101' (br-101) (PR #101)"),
        "{e}"
    );
}

#[test]
fn stdout_is_exactly_the_four_github_output_lines() {
    let f = Fixture::new();
    let o = f.run(&[], &[]);
    let lines: Vec<String> = stdout(&o).lines().map(String::from).collect();
    assert_eq!(lines.len(), 4, "{lines:?}");
    for (line, key) in lines.iter().zip([
        "reaped_cloudrun",
        "reaped_k8s",
        "reaped_neon",
        "total_reaped",
    ]) {
        let (k, v) = line.split_once('=').expect("key=value");
        assert_eq!(k, key);
        assert!(
            !v.is_empty() && v.chars().all(|c| c.is_ascii_digit()),
            "{line}"
        );
    }
}

#[test]
fn a_failed_delete_is_a_warning_not_a_count() {
    let f = Fixture::new();
    let o = f.run(
        &["200"],
        &[("STUB_CR_DELETE_RC", "1"), ("STUB_NEON_DELETE_RC", "1")],
    );
    assert_eq!(o.status.code(), Some(0));
    assert_eq!(
        stdout(&o),
        "reaped_cloudrun=0\nreaped_k8s=1\nreaped_neon=0\ntotal_reaped=1\n"
    );
    let e = stderr(&o);
    assert!(
        e.contains("WARNING: Failed to delete Cloud Run service 'tabula-api-pr-200'"),
        "{e}"
    );
    assert!(
        e.contains("WARNING: Failed to delete Neon branch 'tabula-pr-200'"),
        "{e}"
    );
}

#[test]
fn an_unverifiable_pr_is_preserved() {
    // gh fails for every PR: nothing may be deleted on a sweep.
    let f = Fixture::new();
    let o = f.run(&[], &[("STUB_PRS", "")]);
    assert_eq!(o.status.code(), Some(0));
    assert!(!f.work.join("cr_deleted").exists());
    assert!(!f.work.join("k8s_deleted").exists());
    assert!(!f.work.join("neon_deleted").exists());
    assert!(stderr(&o)
        .contains("PR #101 state is UNKNOWN (unverifiable) \u{2014} preserving as fail-safe"));
    assert_eq!(
        stdout(&o),
        "reaped_cloudrun=0\nreaped_k8s=0\nreaped_neon=0\ntotal_reaped=0\n"
    );
}

#[test]
fn a_non_numeric_pr_argument_is_refused_with_status_2() {
    let f = Fixture::new();
    let o = f.run(&["abc"], &[]);
    assert_eq!(o.status.code(), Some(2));
    assert_eq!(stdout(&o), "");
    assert_eq!(
        stderr(&o),
        "preview-reaper: ERROR: PR number must be positive integer, got 'abc'\n"
    );
    assert!(!f.work.join("cr_deleted").exists());
}

#[test]
fn cloud_run_is_skipped_without_a_project() {
    let f = Fixture::new();
    let o = f.run(&["200"], &[("GCP_PROJECT", "")]);
    assert_eq!(o.status.code(), Some(0));
    assert!(stderr(&o)
        .contains("gcloud not found or GCP_PROJECT unset \u{2014} skipping Cloud Run reap"));
    assert!(!f.work.join("cr_deleted").exists());
    assert_eq!(f.deleted("k8s_deleted"), ["pr-200"]);
}

#[test]
fn missing_neon_credentials_warn_loudly_and_annotate_in_actions() {
    let f = Fixture::new();
    let o = f.run(&[], &[("NEON_API_KEY", ""), ("GITHUB_ACTIONS", "true")]);
    assert_eq!(o.status.code(), Some(0));
    let e = stderr(&o);
    assert!(e.contains("WARNING: Neon credentials missing"), "{e}");
    assert!(
        e.contains("::warning title=Neon Branch Reap Skipped::"),
        "{e}"
    );
    assert!(!f.work.join("neon_deleted").exists());
}

#[test]
fn a_missing_curl_fails_the_run_and_prints_no_summary() {
    let f = Fixture::new();
    let o = f.run(
        &[],
        &[
            ("CURL", "nonexistent-curl-command"),
            ("GITHUB_ACTIONS", "true"),
        ],
    );
    assert_ne!(o.status.code(), Some(0));
    let e = stderr(&o);
    assert!(
        e.contains("ERROR: curl binary 'nonexistent-curl-command' not found"),
        "{e}"
    );
    assert!(
        e.contains(
            "::error title=Neon Reaper Error::curl binary 'nonexistent-curl-command' not found"
        ),
        "{e}"
    );
    // The original aborted here (set -e): no summary, no output lines for the
    // workflow to publish alongside a red step.
    assert_eq!(stdout(&o), "");
    assert!(!e.contains("Summary:"), "{e}");
}

#[test]
fn a_neon_listing_the_api_rejects_fails_the_run_and_deletes_no_branch() {
    // A 401 must not read as "no branches": curl exits 0 on an HTTP error
    // unless told to fail, and the error body parses as an empty list.
    let f = Fixture::new();
    let o = f.run(
        &[],
        &[
            (
                "STUB_NEON_LIST_HTTP_ERROR",
                r#"{"code":"","message":"authorization failed"}"#,
            ),
            ("GITHUB_ACTIONS", "true"),
        ],
    );
    let e = stderr(&o);
    assert_eq!(o.status.code(), Some(1), "{e}");
    assert!(
        e.contains("ERROR: could not list Neon branches (curl exit 22)"),
        "{e}"
    );
    assert!(e.contains("authorization failed"), "{e}");
    assert!(
        e.contains("::error title=Neon Reaper Error::could not list Neon branches (curl exit 22)"),
        "{e}"
    );
    assert!(!e.contains("test-key"), "the API key leaked: {e}");
    assert!(!f.work.join("neon_deleted").exists());
    // What was reaped before the failure is still reported.
    assert_eq!(
        stdout(&o),
        "reaped_cloudrun=4\nreaped_k8s=4\nreaped_neon=0\ntotal_reaped=8\n"
    );
}

#[test]
fn a_neon_listing_curl_cannot_make_fails_the_run_with_curls_reason() {
    let f = Fixture::new();
    let o = f.run(&["200"], &[("STUB_NEON_LIST_CURL_RC", "6")]);
    let e = stderr(&o);
    assert_eq!(o.status.code(), Some(1), "{e}");
    assert!(
        e.contains("ERROR: could not list Neon branches (curl exit 6)"),
        "{e}"
    );
    assert!(e.contains("Could not resolve host"), "{e}");
    assert!(!f.work.join("neon_deleted").exists());
}

#[test]
fn the_neon_listing_asks_curl_to_fail_on_http_errors_and_say_why() {
    let f = Fixture::new();
    let o = f.run(&["200"], &[]);
    assert_eq!(o.status.code(), Some(0), "{}", stderr(&o));
    let args = std::fs::read_to_string(f.work.join("neon_list_args")).unwrap();
    let args: Vec<&str> = args.lines().collect();
    assert!(args.contains(&"-sS"), "{args:?}");
    assert!(args.contains(&"--fail-with-body"), "{args:?}");
}

#[test]
fn a_neon_branch_name_with_an_earlier_non_numeric_pr_marker_still_matches() {
    // "xpr-abc-pr-200": the first "pr-" is not followed by digits; the pattern
    // `pr-([0-9]+)` still finds the later one.
    let f = Fixture::new();
    let o = {
        // Replace the curl stub's branch list with one such branch.
        write_exec(
            &f.stubs.join("curl"),
            r#"#!/usr/bin/env bash
cat >/dev/null # the --config on stdin
if [[ "$*" == *"-X DELETE"* ]]; then
  echo "$*" | sed 's|.*/branches/||' | awk '{print $1}' >> "$NEON_DELETED"
  exit 0
fi
echo '{"branches":[{"id":"br-x","name":"xpr-abc-pr-200","created_at":"2023-11-14T20:00:00Z","primary":false}]}'
"#,
        );
        f.run(&["200"], &[])
    };
    assert_eq!(o.status.code(), Some(0), "{}", stderr(&o));
    assert_eq!(f.deleted("neon_deleted"), ["br-x"]);
}

#[test]
fn a_neon_delete_the_api_rejects_is_not_counted_as_reaped() {
    // curl exits 0 on an HTTP 4xx/5xx unless told to fail; the stub models that.
    let f = Fixture::new();
    let o = f.run(&["200"], &[("STUB_NEON_HTTP_ERROR", "1")]);
    assert_eq!(o.status.code(), Some(0));
    assert_eq!(
        stdout(&o),
        "reaped_cloudrun=1\nreaped_k8s=1\nreaped_neon=0\ntotal_reaped=2\n"
    );
    assert!(
        stderr(&o).contains("WARNING: Failed to delete Neon branch 'tabula-pr-200'"),
        "{}",
        stderr(&o)
    );
}

#[test]
fn a_failed_namespace_delete_is_not_counted_as_reaped() {
    let f = Fixture::new();
    let o = f.run(&["200"], &[("STUB_K8S_DELETE_RC", "1")]);
    assert_eq!(
        stdout(&o),
        "reaped_cloudrun=1\nreaped_k8s=0\nreaped_neon=1\ntotal_reaped=2\n"
    );
    assert!(
        stderr(&o).contains("WARNING: Failed to delete K8s namespace 'pr-200'"),
        "{}",
        stderr(&o)
    );
}

#[test]
fn unreadable_creation_timestamps_are_never_reaped_and_never_panic() {
    // pr-101 is MERGED, so a readable timestamp would be reaped. Each of these
    // must be skipped with a warning instead: a truncated one (which used to
    // panic), junk, impossible fields, and the year-1 date a lenient parser
    // would have produced.
    for bad in [
        "2026-10-31T",
        "garbage",
        "2023-13-45T99:99:99Z",
        "2023-02-30T10:00:00Z",
        "0001-01-01T00:00:00Z",
        "2023-11-14T10:00Z+99",
        "2023-11-14",
        "2023-11-14T10:00:00.Z",
    ] {
        let f = Fixture::new();
        let cr = format!("tabula-api-pr-101\\t{bad}\\n");
        let k8s = format!("pr-101\\t{bad}\\n");
        let neon = format!(
            r#"{{"branches":[{{"id":"br-101","name":"tabula-pr-101","created_at":"{bad}","primary":false}}]}}"#
        );
        let o = f.run(
            &[],
            &[
                ("STUB_CR_LIST", &cr),
                ("STUB_K8S_LIST", &k8s),
                ("STUB_NEON_JSON", &neon),
            ],
        );
        assert_eq!(o.status.code(), Some(0), "{bad}: {}", stderr(&o));
        assert!(!f.work.join("cr_deleted").exists(), "{bad}");
        assert!(!f.work.join("k8s_deleted").exists(), "{bad}");
        assert!(!f.work.join("neon_deleted").exists(), "{bad}");
        assert_eq!(
            stdout(&o),
            "reaped_cloudrun=0\nreaped_k8s=0\nreaped_neon=0\ntotal_reaped=0\n",
            "{bad}"
        );
        let e = stderr(&o);
        assert!(e.contains("unreadable creation timestamp"), "{bad}: {e}");
        assert!(!e.contains("panicked"), "{bad}: {e}");
    }
}

#[test]
fn readable_timestamp_shapes_still_reap() {
    // Fractional seconds, an explicit offset and a space separator all parse.
    let f = Fixture::new();
    let cr = "tabula-api-pr-101\\t2023-11-14T10:00:00.123456Z\\n";
    let k8s = "pr-101\\t2023-11-14T12:00:00+02:00\\n";
    let neon = r#"{"branches":[{"id":"br-101","name":"tabula-pr-101","created_at":"2023-11-14 10:00:00","primary":false}]}"#;
    let o = f.run(
        &[],
        &[
            ("STUB_CR_LIST", cr),
            ("STUB_K8S_LIST", k8s),
            ("STUB_NEON_JSON", neon),
        ],
    );
    assert_eq!(
        stdout(&o),
        "reaped_cloudrun=1\nreaped_k8s=1\nreaped_neon=1\ntotal_reaped=3\n",
        "{}",
        stderr(&o)
    );
}

#[test]
fn an_open_prs_age_is_computed_from_its_utc_instant_not_its_local_clock() {
    // Clock: 2023-11-14T22:13:20Z. The services carry no timestamp of their own,
    // so each PR's createdAt decides, and both are written with a +14:00 offset.
    //   PR 400: 2023-11-14T21:13:20+14:00 = 2023-11-14T07:13:20Z -> 15h old, kept.
    //   PR 401: 2023-11-14T09:13:20+14:00 = 2023-11-13T19:13:20Z -> 27h old, reaped.
    // Reading the offset with the wrong sign puts both in the future, so 401 would
    // be kept and 400 would report a negative age.
    let f = Fixture::new();
    let o = f.run(
        &[],
        &[
            (
                "STUB_CR_LIST",
                "tabula-api-pr-400\\t\\ntabula-api-pr-401\\t\\n",
            ),
            ("STUB_K8S_LIST", "default\\t\\n"),
            ("STUB_NEON_JSON", r#"{"branches":[]}"#),
            (
                "STUB_PRS",
                "400|OPEN|2023-11-14T21:13:20+14:00;401|OPEN|2023-11-14T09:13:20+14:00",
            ),
        ],
    );
    assert_eq!(o.status.code(), Some(0), "{}", stderr(&o));
    assert_eq!(
        f.deleted("cr_deleted"),
        ["tabula-api-pr-401"],
        "{}",
        stderr(&o)
    );
    let e = stderr(&o);
    assert!(
        e.contains("PR #400 is OPEN and active (15h / 24h) \u{2014} preserving"),
        "{e}"
    );
    assert!(
        e.contains("PR #401 is OPEN but age (27h) exceeds TTL (24h) \u{2014} marked for reap"),
        "{e}"
    );
}

#[test]
fn a_cloud_run_listing_gcloud_cannot_make_fails_the_run_and_deletes_no_service() {
    // A gcloud that fails (no credentials, an API outage) must not read as
    // "no services": that is a green run that reaps nothing, forever.
    let f = Fixture::new();
    let o = f.run(&[], &[("STUB_CR_LIST_RC", "1"), ("GITHUB_ACTIONS", "true")]);
    let e = stderr(&o);
    assert_eq!(o.status.code(), Some(1), "{e}");
    assert!(
        e.contains("ERROR: could not list Cloud Run services (gcloud exit 1)"),
        "{e}"
    );
    assert!(e.contains("PERMISSION_DENIED"), "{e}");
    assert!(
        e.contains(
            "::error title=Preview Reaper Error::could not list Cloud Run services (gcloud exit 1)"
        ),
        "{e}"
    );
    // Not even what it printed before failing is acted on.
    assert!(!f.work.join("cr_deleted").exists());
    // The other providers still run and are reported.
    assert_eq!(
        stdout(&o),
        "reaped_cloudrun=0\nreaped_k8s=4\nreaped_neon=4\ntotal_reaped=8\n"
    );
}

#[test]
fn a_namespace_listing_kubectl_cannot_make_fails_the_run_and_deletes_no_namespace() {
    let f = Fixture::new();
    let o = f.run(
        &[],
        &[("STUB_K8S_LIST_RC", "1"), ("GITHUB_ACTIONS", "true")],
    );
    let e = stderr(&o);
    assert_eq!(o.status.code(), Some(1), "{e}");
    assert!(
        e.contains("ERROR: could not list K8s namespaces (kubectl exit 1)"),
        "{e}"
    );
    assert!(e.contains("Unauthorized"), "{e}");
    assert!(
        e.contains(
            "::error title=Preview Reaper Error::could not list K8s namespaces (kubectl exit 1)"
        ),
        "{e}"
    );
    assert!(!f.work.join("k8s_deleted").exists());
    assert_eq!(
        stdout(&o),
        "reaped_cloudrun=4\nreaped_k8s=0\nreaped_neon=4\ntotal_reaped=8\n"
    );
}

#[test]
fn a_neon_listing_that_is_not_a_branch_list_fails_the_run() {
    // A proxy's HTML error page, a truncated body, or JSON without
    // `branches` arrives with HTTP 200: it is a failure to list, never an
    // empty list.
    for body in [
        "<html><body>502 Bad Gateway</body></html>",
        r#"{"branches": [{"id": "br-101", "name""#,
        r#"{"message": "maintenance"}"#,
        r#"{"branches": "none"}"#,
        r#"{"branches": ["br-101"]}"#,
    ] {
        let f = Fixture::new();
        let o = f.run(&[], &[("STUB_NEON_JSON", body), ("GITHUB_ACTIONS", "true")]);
        let e = stderr(&o);
        assert_eq!(o.status.code(), Some(1), "{body}: {e}");
        assert!(
            e.contains("ERROR: could not read the Neon branch list:"),
            "{body}: {e}"
        );
        assert!(
            e.contains("::error title=Neon Reaper Error::could not read the Neon branch list"),
            "{body}: {e}"
        );
        assert!(!f.work.join("neon_deleted").exists(), "{body}");
        assert_eq!(
            stdout(&o),
            "reaped_cloudrun=4\nreaped_k8s=4\nreaped_neon=0\ntotal_reaped=8\n",
            "{body}"
        );
    }
}

#[test]
fn an_empty_neon_branch_list_is_not_a_failure() {
    let f = Fixture::new();
    let o = f.run(&[], &[("STUB_NEON_JSON", r#"{"branches": []}"#)]);
    assert_eq!(o.status.code(), Some(0), "{}", stderr(&o));
    assert!(stdout(&o).contains("reaped_neon=0\n"), "{}", stdout(&o));
}

#[test]
fn the_neon_api_key_is_never_on_a_command_line() {
    // List and delete both run; the key reaches curl only on its stdin.
    let f = Fixture::new();
    let o = f.run(&[], &[]);
    let e = stderr(&o);
    assert_eq!(o.status.code(), Some(0), "{e}");
    assert!(stdout(&o).contains("reaped_neon=4\n"), "{}", stdout(&o));
    let argv = std::fs::read_to_string(f.work.join("curl_argv")).unwrap();
    assert_eq!(argv.lines().count(), 5, "one list and four deletes: {argv}");
    assert!(
        !argv.contains("test-key"),
        "the API key is in curl's argv: {argv}"
    );
    assert!(!argv.contains("Authorization"), "{argv}");
    let config = std::fs::read_to_string(f.work.join("curl_config")).unwrap();
    assert_eq!(
        config
            .matches("header = \"Authorization: Bearer test-key\"")
            .count(),
        5,
        "{config}"
    );
}

#[test]
fn a_neon_api_key_is_quoted_for_curls_config_syntax() {
    // A key holding `"` or `\` must not end the quoted value early, and a
    // trailing newline (as a secret written with `echo` carries) is dropped.
    let f = Fixture::new();
    let o = f.run(&["200"], &[("NEON_API_KEY", "a\"b\\c\n")]);
    // The stub only accepts `test-key`, so the listing is refused: what
    // matters here is what was sent.
    assert_eq!(o.status.code(), Some(1), "{}", stderr(&o));
    let config = std::fs::read_to_string(f.work.join("curl_config")).unwrap();
    assert_eq!(config, "header = \"Authorization: Bearer a\\\"b\\\\c\"\n");
}

#[test]
fn a_neon_api_key_with_a_line_break_inside_is_refused_unsent() {
    // A line break inside the key would start a second curl option.
    let f = Fixture::new();
    let o = f.run(
        &["200"],
        &[("NEON_API_KEY", "abc\nurl = \"https://evil.example\"")],
    );
    let e = stderr(&o);
    assert_eq!(o.status.code(), Some(1), "{e}");
    assert!(
        e.contains("ERROR: NEON_API_KEY holds a control character"),
        "{e}"
    );
    assert!(!e.contains("evil.example"), "{e}");
    assert!(!f.work.join("curl_config").exists());
    assert!(!f.work.join("curl_argv").exists());
}

#[test]
fn kubectl_without_a_cluster_configured_is_skipped_not_failed() {
    // A hosted runner has kubectl but no kubeconfig: that is "no cluster
    // here", like a missing GCP_PROJECT, not a failed listing.
    let f = Fixture::new();
    let o = f.run(&[], &[("STUB_K8S_NO_CONTEXT", "1")]);
    let e = stderr(&o);
    assert_eq!(o.status.code(), Some(0), "{e}");
    assert!(
        e.contains("kubectl not found or has no current context"),
        "{e}"
    );
    assert!(!f.work.join("k8s_deleted").exists());
    assert_eq!(
        stdout(&o),
        "reaped_cloudrun=4\nreaped_k8s=0\nreaped_neon=4\ntotal_reaped=8\n"
    );
}

#[test]
fn a_neon_api_key_with_a_trailing_newline_is_still_redacted() {
    // A secret written with `echo` ends in a newline. The key curl sends is
    // trimmed, so an API echoing it back shows it without the newline: the
    // redaction must look for the same trimmed key, or it never matches.
    for key in ["test-key\n", "test-key\r\n", " test-key \n"] {
        let f = Fixture::new();
        let o = f.run(
            &["200"],
            &[
                ("NEON_API_KEY", key),
                (
                    "STUB_NEON_LIST_HTTP_ERROR",
                    r#"{"message":"key test-key is not allowed here"}"#,
                ),
            ],
        );
        let e = stderr(&o);
        assert_eq!(o.status.code(), Some(1), "{key:?}: {e}");
        assert!(
            e.contains("ERROR: could not list Neon branches (curl exit 22)"),
            "{key:?}: {e}"
        );
        assert!(!e.contains("test-key"), "{key:?}: the API key leaked: {e}");
        assert!(
            e.contains("key <redacted> is not allowed here"),
            "{key:?}: {e}"
        );
    }
}
