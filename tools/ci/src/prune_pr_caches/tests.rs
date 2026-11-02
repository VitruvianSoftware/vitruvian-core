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

//! Black-box tests for //tools/ci:prune_pr_caches, the Actions cache pruner
//! .github/workflows/prune-pr-caches.yaml runs. It DELETES, so the suite is
//! mostly negative: an open PR's cache, a branch cache, a live merge-queue
//! entry and anything whose state cannot be determined must all survive.
//! Runs the REAL binary with a fake `gh` (hermetic: no network, no token).
//! Ported case for case from the former prune-pr-caches_test.sh.

use ci_testkit::{assert_has, assert_lacks, bin, read, write, write_exe, Output, Run, TempDir};

/// The fake gh. Driven by:
///   $GH_STUB_DIR/listing.tsv  the cache listing (`id\tsize\tref` lines)
///   $GH_STUB_DIR/delete_rc    forced exit code for every DELETE
///   STUB_STATES               "num:STATE,..." for `gh pr view` (absent = gh fails)
///   STUB_BRANCHES             "key:gone|live|err,..." for `gh api .../branches/...`
/// and records, for the assertions:
///   $GH_STUB_DIR/deleted      the cache id of every DELETE, one per line
///   $GH_STUB_DIR/delete_paths the full API path of every DELETE
///   $GH_STUB_DIR/calls        every command line
const FAKE_GH: &str = r#"#!/usr/bin/env bash
W="$GH_STUB_DIR"
printf '%s\n' "$*" >>"$W/calls"
if [ "$1" = "api" ] && [ "${2:-}" = "--paginate" ]; then
  cat "$W/listing.tsv"
  exit 0
fi
if [ "$1" = "api" ] && [ "${2:-}" = "-X" ] && [ "${3:-}" = "DELETE" ]; then
  printf '%s\n' "$4" >>"$W/delete_paths"
  if [ -f "$W/delete_rc" ]; then exit "$(cat "$W/delete_rc")"; fi
  printf '%s\n' "${4##*/}" >>"$W/deleted"
  exit 0
fi
if [ "$1" = "api" ]; then
  for pair in ${STUB_BRANCHES//,/ }; do
    key="${pair%%:*}"
    case "$2" in *"$key"*)
      case "${pair#*:}" in
        gone) echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
        live) echo '{"name":"x"}'; exit 0 ;;
        err)  echo "error connecting to api.github.com" >&2; exit 1 ;;
        err5xx) echo "gh: Bad Gateway (HTTP 502): https://api.github.com/repos/o/r/branches/gh-readonly-queue/main/pr-4170-9f1c4040 not found upstream" >&2; exit 1 ;;
      esac ;;
    esac
  done
  echo '{"name":"x"}'; exit 0   # unknown branch -> looks alive -> must be kept
fi
if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
  for pair in ${STUB_STATES//,/ }; do
    case "$pair" in "$3":*) echo "${pair#*:}"; exit 0 ;; esac
  done
  exit 1   # unknown PR -> gh fails, the tool must not guess
fi
echo "unexpected gh invocation: $*" >&2
exit 99
"#;

const MIB: u64 = 1_048_576;

/// The shell suite's fixture: 8 entries, 36 MiB in all.
const LISTING: &str = "\
101\t1048576\trefs/pull/900/merge
102\t2097152\trefs/pull/901/merge
103\t3145728\trefs/heads/main
105\t5242880\trefs/heads/900
104\t4194304\trefs/pull/902/merge
106\t6291456\trefs/heads/gh-readonly-queue/main/pr-903-deadbeef
107\t7340032\trefs/heads/gh-readonly-queue/main/pr-904-cafebabe
108\t8388608\trefs/heads/gh-readonly-queue/main/pr-905-f00dface
";
// 105 lives on refs/heads/900 and "900" IS a merged PR in most cases below.
// Only the refs/pull/* filter can protect it; the unknown-state guard cannot,
// because the state DOES resolve. Without this row, dropping the filter is
// invisible.

struct Pruner {
    dir: TempDir,
}

impl Pruner {
    fn new() -> Pruner {
        Pruner::with_listing(LISTING)
    }

    fn with_listing(listing: &str) -> Pruner {
        let dir = TempDir::new();
        write_exe(dir.join("bin/gh"), FAKE_GH);
        write(dir.join("listing.tsv"), listing);
        Pruner { dir }
    }

    fn run(&self, states: &str, branches: &str, args: &[&str], extra: &[(&str, &str)]) -> Output {
        let mut r = Run::new(&bin("BIN"))
            .env(
                "PATH",
                format!("{}:/usr/bin:/bin", self.dir.join("bin").display()),
            )
            .env("GH_STUB_DIR", self.dir.path())
            .env("REPO", "o/r")
            .env("STUB_STATES", states)
            .env("STUB_BRANCHES", branches)
            .env("TMPDIR", self.dir.path())
            .env_remove("GH")
            .env_remove("DRY_RUN")
            .args(args);
        for (k, v) in extra {
            r = r.env(k, v);
        }
        r.go()
    }

    /// Sorted ids the tool deleted, space-terminated like the shell suite's.
    fn deleted(&self) -> String {
        let mut ids: Vec<String> = read(self.dir.join("deleted"))
            .lines()
            .map(str::to_string)
            .collect();
        ids.sort();
        ids.iter().map(|i| format!("{i} ")).collect()
    }

    fn calls(&self) -> String {
        read(self.dir.join("calls"))
    }
}

fn out_value<'a>(o: &'a Output, key: &str) -> Option<&'a str> {
    o.stdout
        .lines()
        .find_map(|l| l.strip_prefix(&format!("{key}=")))
}

// --- deletes only closed/merged PR caches ----------------------------------

#[test]
fn deletes_merged_and_closed_and_keeps_open_main_and_branch() {
    let p = Pruner::new();
    let o = p.run("900:MERGED,901:OPEN,902:CLOSED", "", &[], &[]);
    assert_eq!(o.code, 0, "{o:?}");
    // Exact equality: an EXTRA delete of anything fails here.
    assert_eq!(
        p.deleted(),
        "101 104 ",
        "merged (101) and closed (104) deleted, nothing else: {o:?}"
    );
}

#[test]
fn main_cache_is_never_a_candidate() {
    let p = Pruner::new();
    p.run("900:MERGED,901:MERGED,902:MERGED", "", &[], &[]);
    assert_lacks(
        &p.deleted(),
        "103",
        "refs/heads/main cache must never be deleted",
    );
}

#[test]
fn branch_ref_is_excluded_by_path_not_by_pr_state() {
    let p = Pruner::new();
    p.run("900:MERGED,901:OPEN,902:CLOSED", "", &[], &[]);
    assert_lacks(
        &p.deleted(),
        "105",
        "refs/heads/900 collides with merged PR 900: the refs/pull filter is gone",
    );
    // Not even looked up as a PR: the filter, not the state guard, kept it.
    assert_eq!(
        p.calls()
            .lines()
            .filter(|l| l.starts_with("pr view 900 "))
            .count(),
        1,
        "PR 900 is looked up once, for refs/pull/900 only: {}",
        p.calls()
    );
}

#[test]
fn open_pr_keeps_its_cache() {
    let p = Pruner::new();
    let o = p.run("900:MERGED,901:OPEN,902:CLOSED", "", &[], &[]);
    assert_lacks(&p.deleted(), "102", "an OPEN PR's cache was deleted");
    assert_has(
        &o.stderr,
        "left 1 belonging to open PRs",
        "open PR is counted as kept",
    );
}

// --- an undeterminable PR state is left alone, not guessed -----------------

#[test]
fn unknown_pr_state_is_left_alone() {
    let p = Pruner::new();
    let o = p.run("900:MERGED", "", &[], &[]); // 901 and 902: gh pr view fails
    assert_eq!(o.code, 0, "{o:?}");
    assert_eq!(
        p.deleted(),
        "101 ",
        "only the confirmed-merged cache: {o:?}"
    );
    assert_has(
        &o.stderr,
        "PR #901: state unknown ('')",
        "unknown state is logged",
    );
}

#[test]
fn unrecognised_pr_state_string_is_left_alone() {
    let p = Pruner::new();
    p.run("900:MERGED,901:DRAFT,902:closed", "", &[], &[]);
    assert_eq!(p.deleted(), "101 ", "only an exact MERGED/CLOSED counts");
}

// --- single-PR mode touches only that PR -----------------------------------

#[test]
fn single_pr_mode_touches_only_that_pr() {
    let p = Pruner::new();
    let o = p.run("900:MERGED,901:MERGED,902:MERGED", "", &["902"], &[]);
    assert_eq!(o.code, 0, "{o:?}");
    assert_eq!(
        p.deleted(),
        "104 ",
        "on-close hook for 902 deleted only its own cache"
    );
    assert_lacks(
        &p.calls(),
        "pr view 900",
        "other PRs are not even looked up",
    );
}

#[test]
fn empty_pr_argument_sweeps_like_no_argument() {
    // The workflow's expression yields '' outside pull_request; the shell's
    // ${1:-} read an empty argument as "sweep everything".
    let p = Pruner::new();
    p.run("900:MERGED,901:OPEN,902:CLOSED", "", &[""], &[]);
    assert_eq!(p.deleted(), "101 104 ");
}

// --- the remaining-budget accounting is correct ----------------------------

#[test]
fn remaining_budget_accounting() {
    // 8 entries, 36 MiB. Deleting 101 (1 MiB) and 104 (4 MiB) leaves 6 / 31.
    let p = Pruner::new();
    let o = p.run("900:MERGED,901:OPEN,902:CLOSED", "", &[], &[]);
    assert_eq!(out_value(&o, "deleted"), Some("2"), "{o:?}");
    assert_eq!(out_value(&o, "freed_mib"), Some("5"), "{o:?}");
    assert_eq!(
        out_value(&o, "remaining_entries"),
        Some("6"),
        "counts every ref, not just the deleted ones: {o:?}"
    );
    assert_eq!(out_value(&o, "remaining_mib"), Some("31"), "36 - 5: {o:?}");
}

#[test]
fn output_is_github_output_shaped() {
    // Appended straight to $GITHUB_OUTPUT, which GitHub parses line by line.
    let p = Pruner::new();
    let o = p.run("900:MERGED,901:OPEN,902:CLOSED", "", &[], &[]);
    assert_eq!(
        o.stdout, "deleted=2\nfreed_mib=5\nremaining_entries=6\nremaining_mib=31\n",
        "exactly the four keys, one per line, nothing else on stdout"
    );
}

#[test]
fn mib_values_round_down() {
    let p = Pruner::with_listing(&format!(
        "1\t{}\trefs/pull/7/merge\n2\t{}\trefs/heads/main\n",
        2 * MIB - 1,
        MIB + 1
    ));
    let o = p.run("7:MERGED", "", &[], &[]);
    assert_eq!(out_value(&o, "freed_mib"), Some("1"), "{o:?}");
    assert_eq!(out_value(&o, "remaining_mib"), Some("1"), "{o:?}");
    assert_eq!(out_value(&o, "remaining_entries"), Some("1"), "{o:?}");
}

#[test]
fn failed_delete_is_not_counted() {
    let p = Pruner::new();
    write(p.dir.join("delete_rc"), "1");
    let o = p.run("900:MERGED,901:OPEN,902:CLOSED", "", &[], &[]);
    assert_eq!(o.code, 0, "a failed delete is logged, not fatal: {o:?}");
    assert_has(
        &o.stderr,
        "failed to delete cache 101 from refs/pull/900/merge",
        "logged",
    );
    assert_eq!(
        o.stdout, "deleted=0\nfreed_mib=0\nremaining_entries=8\nremaining_mib=36\n",
        "nothing reclaimed is reported as nothing reclaimed"
    );
}

// --- DRY_RUN deletes nothing -----------------------------------------------

#[test]
fn dry_run_deletes_nothing() {
    let p = Pruner::new();
    let o = p.run(
        "900:MERGED,901:MERGED,902:MERGED",
        "",
        &[],
        &[("DRY_RUN", "1")],
    );
    assert_eq!(o.code, 0, "{o:?}");
    assert_eq!(
        read(p.dir.join("delete_paths")),
        "",
        "DRY_RUN issued a DELETE"
    );
    assert_has(
        &o.stderr,
        "DRY_RUN would delete cache 101 (1MiB) from refs/pull/900/merge (PR MERGED)",
        "reported",
    );
    // Would-be totals, but the budget is left as it is.
    assert_eq!(
        o.stdout,
        "deleted=3\nfreed_mib=7\nremaining_entries=8\nremaining_mib=36\n"
    );
}

// --- merge-queue refs: only a CONFIRMED-deleted branch is swept ------------

#[test]
fn queue_cache_with_404_branch_is_deleted() {
    let p = Pruner::new();
    p.run(
        "900:MERGED,901:MERGED,902:MERGED",
        "pr-903:gone,pr-904:live,pr-905:err",
        &[],
        &[],
    );
    assert_has(&p.deleted(), "106", "orphaned queue cache 106");
}

#[test]
fn live_queue_entry_keeps_its_cache() {
    let p = Pruner::new();
    let o = p.run(
        "900:MERGED,901:MERGED,902:MERGED",
        "pr-903:gone,pr-904:live,pr-905:err",
        &[],
        &[],
    );
    assert_lacks(&p.deleted(), "107", "107's queue branch is still LIVE");
    assert_has(
        &o.stderr,
        "1 to live queue entries",
        "live entry counted as kept",
    );
}

#[test]
fn transport_error_is_not_proof_of_deletion() {
    // A transport failure exits non-zero exactly like a 404. Testing the exit
    // code instead of matching the 404 would delete live queue caches on a
    // rate limit, and only this fails.
    let p = Pruner::new();
    let o = p.run(
        "900:MERGED,901:MERGED,902:MERGED",
        "pr-903:gone,pr-904:live,pr-905:err",
        &[],
        &[],
    );
    assert_lacks(
        &p.deleted(),
        "108",
        "a transport error was read as a deleted branch",
    );
    assert_has(&o.stderr, "existence undeterminable", "logged");
    // The whole set, so an extra delete anywhere fails too.
    assert_eq!(p.deleted(), "101 102 104 106 ");
}

#[test]
fn a_5xx_whose_message_contains_404_is_not_a_deleted_branch() {
    // gh puts the request URL in a 5xx error, and a queue branch's SHA can
    // contain "404" (and the body can say "not found"). Only gh's
    // "(HTTP 404)" status means the branch is gone.
    let p = Pruner::new();
    let o = p.run(
        "900:MERGED,901:MERGED,902:MERGED",
        "pr-905:err5xx",
        &[],
        &[],
    );
    assert_lacks(
        &p.deleted(),
        "108",
        "a 502 mentioning 404 was read as a deleted branch",
    );
    assert_has(&o.stderr, "existence undeterminable", "logged as unknown");
    assert_eq!(p.deleted(), "101 102 104 ");
}

#[test]
fn queue_branch_lookup_uses_the_branch_name() {
    let p = Pruner::new();
    p.run("", "pr-903:gone", &["903"], &[]);
    assert_has(
        &p.calls(),
        "api repos/o/r/branches/gh-readonly-queue/main/pr-903-deadbeef\n",
        "branches API is asked about the ref minus refs/heads/",
    );
}

#[test]
fn unrecognised_branch_is_assumed_alive() {
    let p = Pruner::new();
    p.run("900:MERGED,901:MERGED,902:MERGED", "", &[], &[]);
    assert_eq!(p.deleted(), "101 102 104 ", "no 404, no queue deletion");
}

#[test]
fn on_close_hook_sweeps_that_prs_queue_branches() {
    let p = Pruner::new();
    let o = p.run(
        "903:MERGED",
        "pr-903:gone,pr-904:live,pr-905:err",
        &["903"],
        &[],
    );
    assert_eq!(p.deleted(), "106 ", "only PR 903's queue cache: {o:?}");
}

// --- API shape, memoisation, setup errors ----------------------------------

#[test]
fn every_delete_targets_the_repos_cache_endpoint() {
    let p = Pruner::new();
    p.run("900:MERGED,901:OPEN,902:CLOSED", "pr-903:gone", &[], &[]);
    let mut paths: Vec<String> = read(p.dir.join("delete_paths"))
        .lines()
        .map(str::to_string)
        .collect();
    paths.sort();
    assert_eq!(
        paths,
        [
            "repos/o/r/actions/caches/101",
            "repos/o/r/actions/caches/104",
            "repos/o/r/actions/caches/106"
        ]
    );
}

#[test]
fn listing_is_paginated_with_the_tsv_projection() {
    let p = Pruner::new();
    p.run("", "", &[], &[]);
    assert_has(
        &p.calls(),
        "api --paginate repos/o/r/actions/caches?per_page=100 --jq .actions_caches[] | [.id, .size_in_bytes, .ref] | @tsv\n",
        "listing call",
    );
}

#[test]
fn pr_state_is_asked_once_per_pr() {
    let p = Pruner::with_listing(
        "1\t1\trefs/pull/7/merge\n2\t1\trefs/pull/7/merge\n3\t1\trefs/pull/7/merge\n",
    );
    p.run("7:MERGED", "", &[], &[]);
    assert_eq!(p.deleted(), "1 2 3 ");
    assert_eq!(
        p.calls()
            .lines()
            .filter(|l| l.starts_with("pr view 7 --repo o/r --json state --jq .state"))
            .count(),
        1,
        "{}",
        p.calls()
    );
}

#[test]
fn empty_listing_is_a_clean_no_op() {
    let p = Pruner::with_listing("");
    let o = p.run("", "", &[], &[]);
    assert_eq!(o.code, 0, "{o:?}");
    assert_eq!(o.stdout, "", "no outputs when there is nothing listed");
    assert_has(&o.stderr, "nothing to do", "logged");
}

#[test]
fn missing_gh_is_a_setup_error() {
    let p = Pruner::new();
    let o = p.run("", "", &[], &[("GH", "/nonexistent/gh")]);
    assert_eq!(o.code, 2, "{o:?}");
    assert_has(&o.stderr, "gh not found on PATH", "names the problem");
    assert_eq!(read(p.dir.join("calls")), "");
}
