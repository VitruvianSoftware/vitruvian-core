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
if [ "${1:-}" = "get" ] && [ "${2:-}" = "namespaces" ]; then
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
  exit 0
fi
exit 0
"#,
        );
        write_exec(
            &stubs.join("curl"),
            r#"#!/usr/bin/env bash
if [[ "$*" == *"-X DELETE"* ]]; then
  echo "$*" | sed 's|.*/branches/||' | awk '{print $1}' >> "$NEON_DELETED"
  exit "${STUB_NEON_DELETE_RC:-0}"
fi
if [[ "$*" == *"api/v2/projects/test-proj/branches"* ]]; then
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
        for f in ["cr_deleted", "k8s_deleted", "neon_deleted"] {
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
fn a_neon_branch_name_with_an_earlier_non_numeric_pr_marker_still_matches() {
    // "xpr-abc-pr-200": the first "pr-" is not followed by digits; the pattern
    // `pr-([0-9]+)` still finds the later one.
    let f = Fixture::new();
    let o = {
        // Replace the curl stub's branch list with one such branch.
        write_exec(
            &f.stubs.join("curl"),
            r#"#!/usr/bin/env bash
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
