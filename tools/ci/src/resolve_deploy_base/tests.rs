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

//! Black-box guard for //tools/ci:resolve_deploy_base (#1351). A fake `gh`
//! (no network, no credentials) answers the run-history lookup. Pins the
//! FAIL-OPEN invariant: base_sha is empty on ANY lookup problem, so the caller
//! falls back to github.event.before instead of fabricating a wrong base.

use ci_testkit::{assert_has, bin, read, write_exe, Output, Run, TempDir};
use std::path::{Path, PathBuf};

// A query for the legacy workflow (`-w legacy.yaml`) answers from
// FAKE_LEGACY_OUT / FAKE_LEGACY_RC and is logged, so a test can tell whether
// it was consulted at all. Every call's argv is logged to FAKE_GH_ARGV.
const FAKE_GH: &str = r#"#!/usr/bin/env bash
echo "$*" >> "${FAKE_GH_ARGV:-/dev/null}"
wf=""
while [ $# -gt 0 ]; do
  if [ "$1" = "-w" ]; then wf="$2"; fi
  shift
done
if [ "$wf" = "legacy.yaml" ]; then
  echo "legacy" >> "${FAKE_GH_LOG:-/dev/null}"
  if [ "${FAKE_LEGACY_RC:-0}" != "0" ]; then
    echo "gh: HTTP 404 (legacy)" >&2
    exit "${FAKE_LEGACY_RC}"
  fi
  printf '%s' "${FAKE_LEGACY_OUT:-}"
  exit 0
fi
if [ "${FAKE_GH_RC:-0}" != "0" ]; then
  echo "gh: HTTP 502 (something went wrong)" >&2
  exit "${FAKE_GH_RC}"
fi
printf '%s' "${FAKE_GH_OUT:-}"
"#;

struct Fx {
    dir: TempDir,
    gh: PathBuf,
}

impl Fx {
    fn new() -> Fx {
        let dir = TempDir::new();
        let gh = dir.join("fake-gh");
        write_exe(&gh, FAKE_GH);
        Fx { dir, gh }
    }

    fn out(&self) -> PathBuf {
        self.dir.join("out")
    }

    /// The base run every case starts from (REPO set, GITHUB_REPOSITORY
    /// cleared, as the shell suite did), plus the case's own env.
    fn run(&self, envs: &[(&str, &str)]) -> (Output, String) {
        let _ = std::fs::remove_file(self.out());
        let mut r = Run::new(&bin("BIN"))
            .env("GITHUB_OUTPUT", self.out())
            .env("GH_BIN", &self.gh)
            .env("GITHUB_REPOSITORY", "")
            .env("REPO", "owner/repo")
            .env("WORKFLOW_FILE", "some-deploy.yaml");
        for (k, v) in envs {
            r = r.env(k, v);
        }
        let o = r.go();
        (o, base_sha(&self.out()))
    }
}

/// The `base_sha=` value written to GITHUB_OUTPUT.
fn base_sha(out: &Path) -> String {
    read(out)
        .lines()
        .filter_map(|l| l.strip_prefix("base_sha="))
        .collect::<Vec<_>>()
        .join("\n")
}

const WARN: &str = "::warning title=deploy-gate-durable-base-fallback::";

#[test]
fn happy_path_resolves_the_last_successful_push_runs_sha() {
    let fx = Fx::new();
    let (o, got) = fx.run(&[("FAKE_GH_OUT", "abc123def456")]);
    assert_eq!(got, "abc123def456", "{o:?}");
    assert_eq!(o.code, 0);
    assert_has(
        &o.stdout,
        "resolve-deploy-base: base_sha='abc123def456' (last successful push-triggered run of some-deploy.yaml)",
        "echoed verdict",
    );
}

#[test]
fn queries_exactly_the_push_success_history_of_the_workflow() {
    let fx = Fx::new();
    let argv = fx.dir.join("argv");
    let argv_s = argv.to_string_lossy().into_owned();
    fx.run(&[
        ("FAKE_GH_OUT", "abc"),
        ("FAKE_GH_ARGV", &argv_s),
        ("BRANCH", "rel"),
    ]);
    assert_eq!(
        read(&argv).trim_end(),
        "run list --repo owner/repo -w some-deploy.yaml -b rel -e push -s success -L 1 --json headSha --jq .[0].headSha // empty"
    );
    // BRANCH defaults to main.
    std::fs::remove_file(&argv).unwrap();
    fx.run(&[("FAKE_GH_OUT", "abc"), ("FAKE_GH_ARGV", &argv_s)]);
    assert_has(&read(&argv), " -b main ", "default branch");
}

#[test]
fn no_prior_successful_run_fails_open() {
    let fx = Fx::new();
    let (o, got) = fx.run(&[("FAKE_GH_OUT", "")]);
    assert_eq!(got, "");
    assert_eq!(o.code, 0);
    assert_has(
        &o.stdout,
        "no prior successful push-triggered run of some-deploy.yaml found",
        "reason",
    );
}

#[test]
fn gh_error_fails_open() {
    let fx = Fx::new();
    let (o, got) = fx.run(&[("FAKE_GH_RC", "1")]);
    assert_eq!(got, "");
    assert_eq!(o.code, 0);
    assert_has(
        &o.stdout,
        "gh run list failed (rc=1): gh: HTTP 502 (something went wrong)",
        "reason",
    );
}

#[test]
fn gh_error_also_warns_so_a_broken_lookup_is_audible() {
    let fx = Fx::new();
    let (o, _) = fx.run(&[("FAKE_GH_RC", "1")]);
    assert_has(&o.stdout, WARN, "warning annotation");
}

#[test]
fn own_success_wins_over_the_legacy_workflow() {
    let fx = Fx::new();
    let (_, got) = fx.run(&[
        ("FAKE_GH_OUT", "abc123def456"),
        ("LEGACY_WORKFLOW_FILE", "legacy.yaml"),
        ("FAKE_LEGACY_OUT", "0ld0ld"),
    ]);
    assert_eq!(got, "abc123def456");
}

#[test]
fn legacy_not_queried_once_the_workflow_has_its_own_success() {
    let fx = Fx::new();
    let log = fx.dir.join("gh.log");
    fx.run(&[
        ("FAKE_GH_OUT", "abc123def456"),
        ("LEGACY_WORKFLOW_FILE", "legacy.yaml"),
        ("FAKE_LEGACY_OUT", "0ld0ld"),
        ("FAKE_GH_LOG", &log.to_string_lossy()),
    ]);
    assert_eq!(read(&log), "", "legacy workflow was queried");
}

#[test]
fn no_own_success_resumes_from_the_legacy_workflow() {
    let fx = Fx::new();
    let (o, got) = fx.run(&[
        ("FAKE_GH_OUT", ""),
        ("LEGACY_WORKFLOW_FILE", "legacy.yaml"),
        ("FAKE_LEGACY_OUT", "0ld0ld"),
    ]);
    assert_eq!(got, "0ld0ld");
    assert_has(
        &o.stdout,
        "last successful push-triggered run of legacy.yaml, which delivered these units before it",
        "reason",
    );
}

#[test]
fn no_success_in_either_workflow_fails_open() {
    let fx = Fx::new();
    let (_, got) = fx.run(&[
        ("FAKE_GH_OUT", ""),
        ("LEGACY_WORKFLOW_FILE", "legacy.yaml"),
        ("FAKE_LEGACY_OUT", ""),
    ]);
    assert_eq!(got, "");
}

#[test]
fn legacy_lookup_error_fails_open_and_warns() {
    let fx = Fx::new();
    let (o, got) = fx.run(&[
        ("FAKE_GH_OUT", ""),
        ("LEGACY_WORKFLOW_FILE", "legacy.yaml"),
        ("FAKE_LEGACY_RC", "1"),
    ]);
    assert_eq!(got, "");
    assert_has(&o.stdout, WARN, "warning annotation");
    assert_has(
        &o.stdout,
        "gh run list for legacy.yaml failed (rc=1): gh: HTTP 404 (legacy)",
        "reason",
    );
}

#[test]
fn own_gh_error_does_not_consult_the_legacy_workflow() {
    let fx = Fx::new();
    let log = fx.dir.join("gh.log");
    let (_, got) = fx.run(&[
        ("FAKE_GH_RC", "1"),
        ("LEGACY_WORKFLOW_FILE", "legacy.yaml"),
        ("FAKE_LEGACY_OUT", "0ld0ld"),
        ("FAKE_GH_LOG", &log.to_string_lossy()),
    ]);
    assert_eq!(got, "");
    assert_eq!(
        read(&log),
        "",
        "legacy workflow was queried after an own error"
    );
}

#[test]
fn a_legacy_file_equal_to_the_workflow_is_not_queried_twice() {
    let fx = Fx::new();
    let log = fx.dir.join("gh.log");
    fx.run(&[
        ("WORKFLOW_FILE", "legacy.yaml"),
        ("LEGACY_WORKFLOW_FILE", "legacy.yaml"),
        ("FAKE_LEGACY_OUT", ""),
        ("FAKE_GH_LOG", &log.to_string_lossy()),
    ]);
    assert_eq!(read(&log).lines().count(), 1);
}

#[test]
fn repo_and_github_repository_both_unset_fails_open_with_the_reason() {
    let fx = Fx::new();
    let argv = fx.dir.join("argv");
    let (o, got) = fx.run(&[
        ("REPO", ""),
        ("GITHUB_REPOSITORY", ""),
        ("FAKE_GH_OUT", "abc"),
        ("FAKE_GH_ARGV", &argv.to_string_lossy()),
    ]);
    assert_eq!(got, "");
    assert_eq!(o.code, 0);
    assert_has(&o.stdout, "REPO/GITHUB_REPOSITORY unset", "reason");
    assert_eq!(read(&argv), "", "gh must not be called without a repo");
}

#[test]
fn repo_falls_back_to_github_repository() {
    let fx = Fx::new();
    let argv = fx.dir.join("argv");
    let (_, got) = fx.run(&[
        ("REPO", ""),
        ("GITHUB_REPOSITORY", "ambient/repo"),
        ("FAKE_GH_OUT", "abc"),
        ("FAKE_GH_ARGV", &argv.to_string_lossy()),
    ]);
    assert_eq!(got, "abc");
    assert_has(
        &read(&argv),
        "--repo ambient/repo ",
        "GITHUB_REPOSITORY fallback",
    );
}

#[test]
fn missing_workflow_file_is_a_caller_bug_not_a_fail_open() {
    let fx = Fx::new();
    let o = Run::new(&bin("BIN"))
        .env("GITHUB_OUTPUT", fx.out())
        .env("GH_BIN", &fx.gh)
        .env("REPO", "owner/repo")
        .env_remove("WORKFLOW_FILE")
        .go();
    assert_ne!(o.code, 0);
    assert_has(&o.stderr, "WORKFLOW_FILE must be set", "message");
    assert_eq!(read(fx.out()), "", "nothing may be emitted");
}

#[test]
fn bazel_run_acts_from_the_callers_directory() {
    // A relative GITHUB_OUTPUT lands in BUILD_WORKING_DIRECTORY, as the
    // script's `>>` did from the caller's cwd.
    let fx = Fx::new();
    let caller = TempDir::new();
    let elsewhere = TempDir::new();
    let o = Run::new(&bin("BIN"))
        .cwd(elsewhere.path())
        .env("BUILD_WORKING_DIRECTORY", caller.path())
        .env("GITHUB_OUTPUT", "out.txt")
        .env("GH_BIN", &fx.gh)
        .env("GITHUB_REPOSITORY", "")
        .env("REPO", "owner/repo")
        .env("WORKFLOW_FILE", "some-deploy.yaml")
        .env("FAKE_GH_OUT", "abc123")
        .go();
    assert_eq!(o.code, 0, "{o:?}");
    assert_eq!(base_sha(&caller.join("out.txt")), "abc123");
    assert!(!elsewhere.join("out.txt").exists());
}
