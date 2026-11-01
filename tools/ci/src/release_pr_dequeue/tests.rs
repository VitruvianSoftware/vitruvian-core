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

//! Black-box tests for //tools/ci:release_pr_dequeue, which takes a
//! component's release PR out of the merge queue when main has gained a
//! change that PR does not list, so release-please can refresh it.
//! Runs the REAL binary with a fake `gh` (hermetic: no network, no token).
//! Ported case for case from the former release-pr-dequeue_test.sh, plus the
//! cases that suite never covered (required env, the exact GraphQL
//! arguments, a malformed PR row, a fork's PR filtered by the query).

use ci_testkit::{assert_has, assert_lacks, bin, read, write, write_exe, Output, Run, TempDir};

/// Answers each lookup from fixture files in $FX and logs every invocation
/// to $FAKE_GH_LOG, one argument per line between `--- call` markers (the
/// GraphQL query is multi-word, so a flat `$*` would hide argument bounds).
/// A missing fixture prints nothing; `<name>.rc` makes that call fail.
const FAKE_GH: &str = r#"#!/usr/bin/env bash
{ echo "--- call"; for a in "$@"; do printf '%s\n' "$a"; done; } >> "${FAKE_GH_LOG}"
echo "$*" >> "${FAKE_GH_LOG}.flat"
answer() { # <fixture name>
  if [ -f "${FX}/$1.rc" ]; then echo "gh: HTTP 502" >&2; exit 1; fi
  [ -f "${FX}/$1" ] && cat "${FX}/$1"
  exit 0
}
case "$1 $2" in
  "api graphql")
    case "$*" in
      *dequeuePullRequest*) answer dequeue ;;
      *pullRequests*) answer prs ;;
      *) echo "unexpected fake gh graphql call: $*" >&2; exit 99 ;;
    esac
    ;;
  api\ *)
    path="$2"
    case "$path" in
      */commits/*) answer parent ;;
      */commits\?sha=*)
        sha="${path#*commits?sha=}"
        answer "code.${sha%%&*}"
        ;;
      *) echo "unexpected fake gh api path: $path" >&2; exit 99 ;;
    esac
    ;;
  *) echo "unexpected fake gh invocation: $*" >&2; exit 99 ;;
esac
"#;

const LIST_QUERY: &str = "query($owner:String!,$name:String!,$branch:String!){repository(owner:$owner,name:$name){pullRequests(headRefName:$branch,states:OPEN,first:10){nodes{number id headRefOid isCrossRepository isInMergeQueue}}}}";
const LIST_JQ: &str = r#".data.repository.pullRequests.nodes | map(select(.isCrossRepository | not)) | .[0] // empty | "\(.number)\t\(.id)\t\(.headRefOid)\t\(.isInMergeQueue)""#;
const DEQUEUE_QUERY: &str =
    "mutation($id:ID!){dequeuePullRequest(input:{id:$id}){clientMutationId}}";

struct Dq {
    dir: TempDir,
}

struct Ran {
    o: Output,
    /// One `$*` line per gh call.
    flat: String,
    /// Each call's argv.
    calls: Vec<Vec<String>>,
}

impl Ran {
    fn show(&self) -> String {
        format!(
            "exit {}\n--- stdout\n{}--- stderr\n{}--- gh log\n{}",
            self.o.code, self.o.stdout, self.o.stderr, self.flat
        )
    }
    fn starts(&self, prefix: &str) -> bool {
        self.flat.lines().any(|l| l.starts_with(prefix))
    }
    fn dequeued(&self) -> bool {
        self.flat.lines().any(|l| {
            l.starts_with("api graphql -f id=PR_node42 ") && l.contains("dequeuePullRequest")
        })
    }
    fn warned(&self) -> bool {
        self.o
            .stdout
            .lines()
            .any(|l| l.starts_with("::warning title=release PR left in the queue::"))
    }
    fn code0(&self) {
        assert_eq!(
            self.o.code,
            0,
            "the dequeue step always exits 0\n{}",
            self.show()
        );
    }
    fn yes(&self, cond: bool, what: &str) {
        assert!(cond, "{what}\n{}", self.show());
    }
}

impl Dq {
    /// The shell suite's `fresh`: a QUEUED release PR built on main8 (app
    /// code app5); main is now main9 (app code app6).
    fn fresh() -> Dq {
        let dir = TempDir::new();
        write_exe(dir.join("bin/gh"), FAKE_GH);
        let d = Dq { dir };
        d.fx("prs", "42\tPR_node42\thead1\ttrue")
            .fx("parent", "main8")
            .fx("code.main8", "app5")
            .fx("code.main9", "app6");
        d
    }

    fn fx(&self, name: &str, contents: &str) -> &Dq {
        write(self.dir.join("fx").join(name), contents);
        self
    }

    fn fail(&self, name: &str) -> &Dq {
        self.fx(&format!("{name}.rc"), "")
    }

    fn base(&self) -> Run {
        let log = self.dir.join("log");
        write(&log, "");
        write(self.dir.join("log.flat"), "");
        Run::new(&bin("BIN"))
            .path_first(&self.dir.join("bin"))
            .env("GH_TOKEN", "x")
            .env("FAKE_GH_LOG", &log)
            .env("FX", self.dir.join("fx"))
            .env("REPO", "owner/repo")
            .env("COMPONENT", "vitruvian")
            .env("CODE_PATH", "apps/desktop/vitruvian")
            .env("MAIN_SHA", "main9")
    }

    fn finish(&self, o: Output) -> Ran {
        let raw = read(self.dir.join("log"));
        let mut calls: Vec<Vec<String>> = Vec::new();
        for l in raw.lines() {
            if l == "--- call" {
                calls.push(Vec::new());
            } else if let Some(c) = calls.last_mut() {
                c.push(l.to_string());
            }
        }
        Ran {
            o,
            flat: read(self.dir.join("log.flat")),
            calls,
        }
    }

    fn run(&self) -> Ran {
        let o = self.base().go();
        self.finish(o)
    }
}

// --- when it dequeues -------------------------------------------------------

#[test]
fn stale_queued_release_pr_is_dequeued() {
    let d = Dq::fresh();
    let r = d.run();
    r.code0();
    r.yes(r.dequeued(), "dequeued");
    r.yes(
        r.flat
            .contains("-f branch=release-please--branches--main--components--vitruvian "),
        "targets the component's release branch",
    );
    r.yes(
        r.starts("api repos/owner/repo/commits/head1 "),
        "reads the release commit",
    );
    r.yes(
        r.starts("api repos/owner/repo/commits?sha=main8&path=apps/desktop/vitruvian&per_page=1 "),
        "reads the code the PR lists",
    );
    r.yes(
        r.starts("api repos/owner/repo/commits?sha=main9&path=apps/desktop/vitruvian&per_page=1 "),
        "reads main's newest code",
    );
    assert_has(
        &r.o.stdout,
        "Queued release PR #42 releases app5, but main is at app6",
        "says why",
    );
    assert_has(
        &r.o.stdout,
        "Release PR #42 is out of the merge queue.",
        "says it is out",
    );
    r.yes(!r.warned(), "no warning on success");
}

#[test]
fn graphql_arguments_are_exact() {
    let d = Dq::fresh();
    let r = d.run();
    r.code0();
    let list: Vec<String> = [
        "api",
        "graphql",
        "-f",
        "owner=owner",
        "-f",
        "name=repo",
        "-f",
        "branch=release-please--branches--main--components--vitruvian",
        "-f",
        &format!("query={LIST_QUERY}"),
        "--jq",
        LIST_JQ,
    ]
    .iter()
    .map(|s| s.to_string())
    .collect();
    let dequeue: Vec<String> = [
        "api",
        "graphql",
        "-f",
        "id=PR_node42",
        "-f",
        &format!("query={DEQUEUE_QUERY}"),
    ]
    .iter()
    .map(|s| s.to_string())
    .collect();
    assert_eq!(
        r.calls.first(),
        Some(&list),
        "PR listing argv\n{}",
        r.show()
    );
    assert_eq!(r.calls.last(), Some(&dequeue), "dequeue argv\n{}", r.show());
}

// --- when it leaves the PR alone --------------------------------------------

#[test]
fn up_to_date_queued_release_pr_stays_queued() {
    let d = Dq::fresh();
    d.fx("code.main9", "app5");
    let r = d.run();
    r.code0();
    r.yes(!r.dequeued() && !r.warned(), "untouched, no warning");
    assert_has(
        &r.o.stdout,
        "Queued release PR #42 already releases app5",
        "says so",
    );
}

#[test]
fn unqueued_release_pr_needs_nothing_and_no_further_lookups() {
    let d = Dq::fresh();
    d.fx("prs", "42\tPR_node42\thead1\tfalse");
    let r = d.run();
    r.code0();
    r.yes(
        !r.dequeued() && !r.starts("api repos/"),
        "no further lookups",
    );
    assert_has(
        &r.o.stdout,
        "Release PR #42 is not in the merge queue",
        "says so",
    );
}

#[test]
fn no_open_release_pr_is_a_clean_no_op() {
    let d = Dq::fresh();
    d.fx("prs", "");
    let r = d.run();
    r.code0();
    r.yes(!r.dequeued(), "not dequeued");
    assert_has(&r.o.stdout, "nothing to dequeue", "says so");
    assert_eq!(r.calls.len(), 1, "one lookup\n{}", r.show());
}

#[test]
fn malformed_pr_row_is_left_alone_and_exits_0() {
    // A row missing its fields (no queue flag) must neither crash nor dequeue.
    let d = Dq::fresh();
    d.fx("prs", "42");
    let r = d.run();
    r.code0();
    r.yes(!r.dequeued() && !r.starts("api repos/"), "untouched");
}

// --- a failed lookup never dequeues and never fails the release run ---------

#[test]
fn failed_lookup_warns_and_leaves_the_pr_queued() {
    for broken in ["prs", "parent", "code.main8", "code.main9"] {
        let d = Dq::fresh();
        d.fail(broken);
        let r = d.run();
        r.code0();
        r.yes(
            !r.dequeued() && r.warned(),
            &format!("failed lookup '{broken}'"),
        );
        assert_has(
            &r.o.stdout,
            "gh: HTTP 502",
            &format!("{broken}: gh's error is shown"),
        );
    }
}

#[test]
fn empty_answer_warns_and_leaves_the_pr_queued() {
    for empty in ["parent", "code.main8", "code.main9"] {
        let d = Dq::fresh();
        d.fx(empty, "");
        let r = d.run();
        r.code0();
        r.yes(
            !r.dequeued() && r.warned(),
            &format!("empty answer '{empty}'"),
        );
    }
}

#[test]
fn refused_dequeue_warns_and_does_not_claim_success() {
    let d = Dq::fresh();
    d.fail("dequeue");
    let r = d.run();
    r.code0();
    r.yes(r.dequeued() && r.warned(), "tried, then warned");
    assert_has(
        &r.o.stdout,
        "could not dequeue #42: gh: HTTP 502",
        "names the failure",
    );
    assert_lacks(&r.o.stdout, "is out of the merge queue", "no success claim");
}

// --- required environment -------------------------------------------------

#[test]
fn missing_or_empty_required_env_fails_before_any_gh_call() {
    for var in ["REPO", "COMPONENT", "CODE_PATH", "MAIN_SHA"] {
        for unset in [true, false] {
            let d = Dq::fresh();
            let b = d.base();
            let b = if unset {
                b.env_remove(var)
            } else {
                b.env(var, "")
            };
            let o = b.go();
            assert_eq!(o.code, 1, "{var} unset={unset}: {o:?}");
            assert_has(&o.stderr, &format!("{var} must be set"), var);
            assert_eq!(read(d.dir.join("log.flat")), "", "{var}: no gh call");
        }
    }
}

// --- the release workflow runs it before release-please ---------------------

/// The workflow is read from the test's runfiles (data //:workflow_files),
/// so this checks the real file, not a frozen copy.
#[test]
fn vitruvian_release_dequeues_before_release_please() {
    let root = std::env::var("TEST_SRCDIR").expect("TEST_SRCDIR (run under bazel test)");
    let ws = std::env::var("TEST_WORKSPACE").unwrap_or_else(|_| "_main".into());
    let wf = std::path::Path::new(&root)
        .join(ws)
        .join(".github/workflows/vitruvian-release.yaml");
    let text = std::fs::read_to_string(&wf).unwrap_or_else(|e| {
        panic!(
            "{}: {e} (needs data = [\"//:workflow_files\"])",
            wf.display()
        )
    });
    let at = |needle: &str| text.lines().position(|l| l.contains(needle));
    let dequeue = at("tool: release_pr_dequeue");
    let release = at("uses: googleapis/release-please-action@");
    assert!(
        matches!((dequeue, release), (Some(a), Some(b)) if a < b),
        "vitruvian-release.yaml must build and run release_pr_dequeue before release-please \
         (dequeue line {dequeue:?}, release-please line {release:?})"
    );
    assert!(
        !text.contains("release-pr-dequeue.sh"),
        "the retired script is still referenced"
    );
}
