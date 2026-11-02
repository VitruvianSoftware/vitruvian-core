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

//! Black-box tests for //tools/ci:notify_ci_issues, the ntfy poller that
//! .github/workflows/notify-ci-issues.yaml runs. Runs the REAL binary with a
//! fake `gh` (canned workflow-run JSON; the real `jq` does the filtering and
//! grouping, as on the runner) and a fake `curl` that records each ntfy POST
//! instead of sending it: no network, no credentials. Ported case for case
//! from the former notify-ci-issues_test.sh, plus the request shape (URL,
//! auth, headers, the full JSON body), the exact gh API queries, pagination,
//! the CUTOFF_MINUTES and QUEUE_BYPASS_ALLOW defaults, and a missing REPO.
//!
//! jq comes from $JQ_BIN when the rust_test passes it (Bazel's hermetic jq),
//! otherwise from PATH.

use ci_testkit::{assert_has, assert_lacks, bin, read, write_exe, Output, Run, TempDir};
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

/// `gh api <url> [--paginate]`, answered from env, every call logged to
/// $GH_STUB_DIR/gh.log as one `$*` line.
const FAKE_GH: &str = r#"#!/usr/bin/env bash
echo "$*" >> "$GH_STUB_DIR/gh.log"
empty='{"workflow_runs":[]}'
if [ "$1" = "api" ]; then
  case "$2" in
    *"status=waiting"*) printf '%s' "${FAKE_WAITING_JSON:-$empty}" ;;
    *"status=action_required"*) printf '%s' "${FAKE_ACTION_REQUIRED_JSON:-$empty}" ;;
    *"status=failure"*)
      # Per-repo answers so the mirror fan-out is observable. $FAKE_UNREADABLE
      # names a repo whose API call fails, as an unreachable mirror would.
      if [ -n "${FAKE_UNREADABLE:-}" ] && case "$2" in *"${FAKE_UNREADABLE}"*) true ;; *) false ;; esac; then
        echo "HTTP 404: Not Found" >&2; exit 1
      fi
      case "$2" in
        *"owner/repo"*) printf '%s' "${FAKE_FAILURE_JSON:-$empty}" ;;
        *) printf '%s' "${FAKE_MIRROR_FAILURE_JSON:-$empty}" ;;
      esac ;;
    *"/commits?sha=main"*)
      [ -n "${FAKE_COMMITS_FAIL:-}" ] && { echo "HTTP 502" >&2; exit 1; }
      printf '%s' "${FAKE_COMMITS_JSON:-[]}" ;;
    *"event=merge_group"*)
      # $FAKE_QUEUE_TESTED lists the shas the queue tested; $FAKE_QUEUE_UNREADABLE
      # names one whose lookup fails; $FAKE_QUEUE_COUNT overrides the count.
      sha="${2##*head_sha=}"; sha="${sha%%&*}"
      [ "${FAKE_QUEUE_UNREADABLE:-}" = "$sha" ] && { echo "HTTP 502" >&2; exit 1; }
      if [ -n "${FAKE_QUEUE_COUNT:-}" ]; then
        printf '{"total_count":%s,"workflow_runs":[]}' "$FAKE_QUEUE_COUNT"; exit 0
      fi
      case " ${FAKE_QUEUE_TESTED:-} " in
        *" $sha "*) printf '{"total_count":9,"workflow_runs":[]}' ;;
        *) printf '{"total_count":0,"workflow_runs":[]}' ;;
      esac ;;
    *) echo "unexpected gh api url: $2" >&2; exit 99 ;;
  esac
  exit 0
fi
echo "unexpected fake gh invocation: $*" >&2
exit 99
"#;

/// Records each POST: its arguments one per line (then a `--` separator) in
/// curl.argv, and its -d body in curl.bodies, one call per CALL in curl.log.
const FAKE_CURL: &str = r#"#!/usr/bin/env bash
W="$GH_STUB_DIR"
echo "CALL" >> "$W/curl.log"
body="" prev=""
for arg in "$@"; do
  [ "$prev" = "-d" ] && body="$arg"
  prev="$arg"
  [ "$arg" = "$body" ] && [ -n "$body" ] || printf '%s\n' "$arg" >> "$W/curl.argv"
done
printf -- '--\n' >> "$W/curl.argv"
printf '%s\n' "$body" >> "$W/curl.bodies"
exit "${FAKE_CURL_RC:-0}"
"#;

/// An ISO-8601 UTC timestamp `minutes` ago, the form GitHub's updated_at uses.
fn ago(minutes: u64) -> String {
    let secs = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
        - minutes * 60;
    let days = (secs / 86400) as i64;
    let (h, m, s) = ((secs / 3600) % 24, (secs / 60) % 60, secs % 60);
    // Howard Hinnant's civil_from_days.
    let z = days + 719468;
    let era = z.div_euclid(146097);
    let doe = z - era * 146097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let mo = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = yoe + era * 400 + i64::from(mo <= 2);
    format!("{y:04}-{mo:02}-{d:02}T{h:02}:{m:02}:{s:02}Z")
}

fn recent() -> String {
    ago(5)
}

fn stale() -> String {
    ago(60)
}

/// The directory holding Bazel's jq, when the rust_test passes $JQ_BIN (an
/// exec path, `external/...`, which the runfiles tree spells `../...`).
fn jq_dir() -> Option<PathBuf> {
    let raw = std::env::var("JQ_BIN").ok().filter(|v| !v.is_empty())?;
    let rel = match raw.strip_prefix("external/") {
        Some(rest) => format!("../{rest}"),
        None => raw,
    };
    let p = std::fs::canonicalize(&rel).unwrap_or_else(|e| panic!("JQ_BIN={rel}: {e}"));
    Some(p.parent().unwrap().to_path_buf())
}

struct Poll {
    dir: TempDir,
}

impl Poll {
    fn new() -> Poll {
        let dir = TempDir::new();
        write_exe(dir.join("bin/gh"), FAKE_GH);
        write_exe(dir.join("bin/curl"), FAKE_CURL);
        Poll { dir }
    }

    /// The shell suite's run(): a fixed env, then per-case overrides.
    fn run(&self, overrides: &[(&str, &str)]) -> Output {
        for f in ["gh.log", "curl.log", "curl.bodies", "curl.argv"] {
            let _ = std::fs::remove_file(self.dir.join(f));
        }
        let mut path = format!("{}", self.dir.join("bin").display());
        if let Some(j) = jq_dir() {
            path = format!("{path}:{}", j.display());
        }
        path = format!("{path}:{}", std::env::var("PATH").unwrap_or_default());
        let mut r = Run::new(&bin("BIN"))
            .env("PATH", path)
            .env("GH_STUB_DIR", self.dir.path())
            .env("REPO", "owner/repo")
            .env("GH_TOKEN", "x")
            .env("NTFY_PASSWORD", "secret");
        for k in [
            "MIRRORS",
            "CUTOFF_MINUTES",
            "QUEUE_BYPASS_ALLOW",
            "FAKE_WAITING_JSON",
            "FAKE_ACTION_REQUIRED_JSON",
            "FAKE_FAILURE_JSON",
            "FAKE_MIRROR_FAILURE_JSON",
            "FAKE_UNREADABLE",
            "FAKE_COMMITS_JSON",
            "FAKE_COMMITS_FAIL",
            "FAKE_QUEUE_TESTED",
            "FAKE_QUEUE_UNREADABLE",
            "FAKE_QUEUE_COUNT",
            "FAKE_CURL_RC",
        ] {
            r = r.env_remove(k);
        }
        for (k, v) in overrides {
            r = r.env(k, v);
        }
        r.go()
    }

    fn bodies(&self) -> String {
        read(self.dir.join("curl.bodies"))
    }

    fn posts(&self) -> usize {
        read(self.dir.join("curl.log")).lines().count()
    }

    fn gh_log(&self) -> String {
        read(self.dir.join("gh.log"))
    }

    fn curl_argv(&self) -> String {
        read(self.dir.join("curl.argv"))
    }
}

fn runs(entries: &[(&str, &str, &str)]) -> String {
    let items: Vec<String> = entries
        .iter()
        .map(|(name, url, at)| {
            format!(r#"{{"name":"{name}","html_url":"{url}","updated_at":"{at}"}}"#)
        })
        .collect();
    format!(r#"{{"workflow_runs":[{}]}}"#, items.join(","))
}

/// The bodies as parsed JSON-ish lines: jq pretty-prints, one key a line.
#[track_caller]
fn assert_body_has(p: &Poll, needle: &str, what: &str) {
    assert_has(&p.bodies(), needle, what);
}

// --- 1. runs waiting on a required-reviewer approval -----------------------

#[test]
fn waiting_recent_run_notifies_and_stale_run_is_filtered() {
    let p = Poll::new();
    let json = runs(&[
        ("tabula-deploy", "https://x/runs/1", &recent()),
        ("stale-workflow", "https://x/runs/2", &stale()),
    ]);
    let o = p.run(&[("FAKE_WAITING_JSON", &json)]);
    assert_eq!(o.code, 0, "{o:?}");
    assert_has(
        &o.stdout,
        "-> waiting: tabula-deploy (https://x/runs/1)",
        "recent picked up",
    );
    assert_lacks(&o.stdout, "stale-workflow", "stale filtered by cutoff");
    assert_eq!(p.posts(), 1, "{}", p.bodies());
}

#[test]
fn waiting_notification_payload_is_exact() {
    let p = Poll::new();
    let json = runs(&[("tabula-deploy", "https://x/runs/1", &recent())]);
    p.run(&[("FAKE_WAITING_JSON", &json)]);
    assert_eq!(
        p.bodies(),
        "{\n  \"topic\": \"vitruvian-alerts\",\n  \"title\": \"[ci] approval needed: tabula-deploy\",\n  \
         \"message\": \"Workflow run is waiting on a required-reviewer approval. https://x/runs/1\",\n  \
         \"priority\": 4,\n  \"tags\": [\n    \"hourglass_flowing_sand\",\n    \"ci\"\n  ],\n  \
         \"click\": \"https://x/runs/1\"\n}\n"
    );
}

/// The ntfy request itself: a dropped -f would hide a rejected push, a
/// dropped -u would post unauthenticated to a deny-all server.
#[test]
fn ntfy_request_shape_is_exact() {
    let p = Poll::new();
    let json = runs(&[("tabula-deploy", "https://x/runs/1", &recent())]);
    p.run(&[("FAKE_WAITING_JSON", &json)]);
    assert_eq!(
        p.curl_argv(),
        "-fsS\n-u\ngithub-actions:secret\n-H\nContent-Type: application/json\n-H\n\
         User-Agent: vitruvian-ci-notify/1.0\n-X\nPOST\nhttps://ntfy.ipv1337.dev\n-d\n--\n"
    );
}

/// --paginate prints one JSON object per page, back to back; every page counts.
#[test]
fn waiting_reads_every_page() {
    let p = Poll::new();
    let pages = format!(
        "{}{}",
        runs(&[("page-one", "https://x/runs/1", &recent())]),
        runs(&[("page-two", "https://x/runs/2", &recent())])
    );
    let o = p.run(&[("FAKE_WAITING_JSON", &pages)]);
    assert_has(&o.stdout, "waiting: page-one", "first page");
    assert_has(&o.stdout, "waiting: page-two", "second page");
    assert_eq!(p.posts(), 2);
}

// --- 2. runs blocked on "Approve and run", grouped by branch ---------------

#[test]
fn action_required_groups_by_branch_and_drops_stale() {
    let p = Poll::new();
    let (r, s) = (recent(), stale());
    let json = format!(
        r#"{{"workflow_runs":[
  {{"name":"a","head_branch":"feature-x","html_url":"https://x/runs/10","updated_at":"{r}"}},
  {{"name":"b","head_branch":"feature-x","html_url":"https://x/runs/11","updated_at":"{r}"}},
  {{"name":"c","head_branch":"feature-y","html_url":"https://x/runs/12","updated_at":"{s}"}}
]}}"#
    );
    let o = p.run(&[("FAKE_ACTION_REQUIRED_JSON", &json)]);
    assert_eq!(o.code, 0, "{o:?}");
    assert_has(
        &o.stdout,
        "action_required: 2 run(s) on feature-x (https://x/runs/10)",
        "grouped",
    );
    assert_lacks(&o.stdout, "feature-y", "stale branch dropped");
    assert_eq!(p.posts(), 1, "one alert for one ref");
    assert_body_has(
        &p,
        "\"title\": \"[ci] approval needed to start: feature-x\"",
        "title",
    );
    assert_body_has(
        &p,
        "\"message\": \"2 workflow run(s) on feature-x will not start until approved ('Approve and run'). \
         Required checks stay absent and the PR stays blocked until then. https://x/runs/10\"",
        "message",
    );
}

/// Grouping spans pages: the slurp is what makes group_by see them together.
#[test]
fn action_required_groups_across_pages() {
    let p = Poll::new();
    let r = recent();
    let page = |n: u32| {
        format!(
            r#"{{"workflow_runs":[{{"name":"w{n}","head_branch":"feature-x","html_url":"https://x/runs/{n}","updated_at":"{r}"}}]}}"#
        )
    };
    let o = p.run(&[(
        "FAKE_ACTION_REQUIRED_JSON",
        &format!("{}{}", page(1), page(2)),
    )]);
    assert_has(
        &o.stdout,
        "action_required: 2 run(s) on feature-x",
        "one group over two pages",
    );
    assert_eq!(p.posts(), 1);
}

// --- 3. push failures on main, here and on the mirrors ---------------------

#[test]
fn main_failure_notifies_at_priority_5() {
    let p = Poll::new();
    let o = p.run(&[(
        "FAKE_FAILURE_JSON",
        &runs(&[("ci", "https://x/runs/20", &recent())]),
    )]);
    assert_eq!(o.code, 0, "{o:?}");
    assert_has(
        &o.stdout,
        "-> failed on main: ci (https://x/runs/20)",
        "logged",
    );
    assert_body_has(&p, "\"title\": \"[ci] main broken: ci\"", "title");
    assert_body_has(&p, "\"priority\": 5", "priority");
    assert_body_has(
        &p,
        "\"message\": \"Failed on main after landing. https://x/runs/20\"",
        "message",
    );
    assert_body_has(&p, "\"red_circle\",\n    \"ci\"\n  ]", "tags");
}

#[test]
fn failed_ntfy_push_warns_but_exits_zero() {
    let p = Poll::new();
    let o = p.run(&[
        (
            "FAKE_FAILURE_JSON",
            &runs(&[("ci", "https://x/runs/20", &recent())]),
        ),
        ("FAKE_CURL_RC", "22"),
    ]);
    assert_eq!(o.code, 0, "{o:?}");
    assert_has(
        &o.stderr,
        "WARN: ntfy push failed for: [ci] main broken: ci",
        "warned",
    );
}

#[test]
fn failed_ntfy_body_build_warns_and_posts_nothing() {
    // Only the body build (`jq -n ...`) fails; every filter call reaches the
    // real jq, so the failure is still found and the notify is attempted.
    let p = Poll::new();
    let real = jq_dir()
        .map(|d| d.join("jq"))
        .or_else(|| {
            std::env::var("PATH")
                .unwrap_or_default()
                .split(':')
                .map(|d| PathBuf::from(d).join("jq"))
                .find(|j| j.is_file())
        })
        .expect("a real jq: $JQ_BIN or one on PATH");
    write_exe(
        p.dir.join("bin/jq"),
        format!(
            "#!/usr/bin/env bash\nif [ \"$1\" = -n ]; then echo 'jq: boom' >&2; exit 5; fi\nexec '{}' \"$@\"\n",
            real.display()
        ),
    );
    let o = p.run(&[(
        "FAKE_FAILURE_JSON",
        &runs(&[("ci", "https://x/runs/20", &recent())]),
    )]);
    assert_eq!(o.code, 0, "{o:?}");
    assert_has(
        &o.stdout,
        "-> failed on main: ci (https://x/runs/20)",
        "the failure was still found",
    );
    assert_has(
        &o.stderr,
        "WARN: ntfy push failed for: [ci] main broken: ci",
        "warned",
    );
    assert_eq!(p.posts(), 0, "no POST without a body");
}

#[test]
fn cutoff_minutes_is_configurable() {
    let p = Poll::new();
    let json = runs(&[("tabula-deploy", "https://x/runs/1", &recent())]);
    let o = p.run(&[("FAKE_WAITING_JSON", &json), ("CUTOFF_MINUTES", "1")]);
    assert_eq!(o.code, 0, "{o:?}");
    assert_has(
        &o.stdout,
        "Checking for runs waiting on approval, updated since",
        "ran",
    );
    assert_lacks(
        &o.stdout,
        "waiting: tabula-deploy",
        "5-minute-old run excluded by a 1-minute cutoff",
    );
}

/// `${CUTOFF_MINUTES:-20}`: unset and empty both mean 20, so a 15-minute-old
/// run alerts and a 25-minute-old one does not.
#[test]
fn cutoff_minutes_defaults_to_twenty_when_unset_or_empty() {
    for empty in [false, true] {
        let p = Poll::new();
        let json = runs(&[
            ("fifteen", "https://x/runs/15", &ago(15)),
            ("twentyfive", "https://x/runs/25", &ago(25)),
        ]);
        let mut ov = vec![("FAKE_WAITING_JSON", json.as_str())];
        if empty {
            ov.push(("CUTOFF_MINUTES", ""));
        }
        let o = p.run(&ov);
        assert_has(&o.stdout, "waiting: fifteen", "inside the default window");
        assert_lacks(&o.stdout, "twentyfive", "outside the default window");
    }
}

#[test]
fn mirror_failure_notifies_naming_the_mirror() {
    let p = Poll::new();
    let o = p.run(&[
        ("MIRRORS", "VitruvianSoftware/mcp-slack"),
        (
            "FAKE_MIRROR_FAILURE_JSON",
            &runs(&[("Release", "https://x/mirror/9", &recent())]),
        ),
    ]);
    assert_eq!(o.code, 0, "{o:?}");
    assert_body_has(
        &p,
        "\"title\": \"[ci] mcp-slack broken: Release\"",
        "named by mirror",
    );
    assert_body_has(
        &p,
        "\"message\": \"Failed on VitruvianSoftware/mcp-slack's main after landing. This is an exported \
         mirror; the fix usually belongs in vitruvian-core. https://x/mirror/9\"",
        "says where the fix belongs",
    );
    assert_body_has(&p, "\"priority\": 4", "mirror priority");
    assert_body_has(&p, "\"mirror\"", "mirror tag");
}

#[test]
fn mirror_backlog_is_filtered_by_the_cutoff() {
    let p = Poll::new();
    p.run(&[
        ("MIRRORS", "VitruvianSoftware/mcp-slack"),
        (
            "FAKE_MIRROR_FAILURE_JSON",
            &runs(&[("Release", "https://x/mirror/8", &stale())]),
        ),
    ]);
    assert_eq!(p.bodies(), "", "no firehose from old failures");
}

#[test]
fn unreadable_mirror_warns_loudly_and_the_poll_continues() {
    let p = Poll::new();
    let o = p.run(&[
        (
            "MIRRORS",
            "VitruvianSoftware/mcp-slack VitruvianSoftware/devx",
        ),
        ("FAKE_UNREADABLE", "mcp-slack"),
        (
            "FAKE_MIRROR_FAILURE_JSON",
            &runs(&[("Release", "https://x/mirror/9", &recent())]),
        ),
    ]);
    assert_eq!(o.code, 0, "{o:?}");
    assert_has(
        &o.stderr,
        "WARN: cannot read VitruvianSoftware/mcp-slack's runs -- NOT watching it: HTTP 404",
        "loud",
    );
    assert_body_has(
        &p,
        "devx broken: Release",
        "the next mirror is still checked",
    );
}

#[test]
fn own_failure_is_not_mislabelled_as_a_mirror() {
    let p = Poll::new();
    p.run(&[
        ("MIRRORS", "VitruvianSoftware/mcp-slack"),
        (
            "FAKE_FAILURE_JSON",
            &runs(&[("CI", "https://x/own/7", &recent())]),
        ),
    ]);
    assert_body_has(&p, "main broken: CI", "own failure");
    assert_lacks(&p.bodies(), "exported mirror", "not a mirror");
}

/// The workflow passes MIRRORS as a folded YAML block; any run of spaces,
/// tabs or newlines separates entries, and each gets exactly one query.
#[test]
fn mirrors_split_on_any_whitespace() {
    let p = Poll::new();
    p.run(&[("MIRRORS", "  VitruvianSoftware/a \n\tVitruvianSoftware/b  ")]);
    let log = p.gh_log();
    let fails: Vec<&str> = log
        .lines()
        .filter(|l| l.contains("status=failure"))
        .collect();
    assert_eq!(
        fails,
        vec![
            "api repos/owner/repo/actions/runs?branch=main&event=push&status=failure&per_page=20 --paginate",
            "api repos/VitruvianSoftware/a/actions/runs?branch=main&event=push&status=failure&per_page=20 --paginate",
            "api repos/VitruvianSoftware/b/actions/runs?branch=main&event=push&status=failure&per_page=20 --paginate",
        ],
        "{log}"
    );
}

/// The exact queries: the approval checks stay on REPO and paginate, and the
/// commit list is bounded by the same cutoff.
#[test]
fn gh_queries_are_exact() {
    let p = Poll::new();
    let o = p.run(&[("MIRRORS", "VitruvianSoftware/m")]);
    let log = p.gh_log();
    let lines: Vec<&str> = log.lines().collect();
    assert_eq!(
        lines[0],
        "api repos/owner/repo/actions/runs?status=waiting&per_page=50 --paginate"
    );
    assert_eq!(
        lines[1],
        "api repos/owner/repo/actions/runs?status=action_required&per_page=50 --paginate"
    );
    assert_eq!(lines.len(), 5, "{log}");
    let cutoff = o
        .stdout
        .lines()
        .next()
        .and_then(|l| l.strip_prefix("Checking for runs waiting on approval, updated since "))
        .and_then(|l| l.strip_suffix("..."))
        .expect("cutoff in the first line")
        .to_string();
    assert_eq!(
        lines[4],
        format!("api repos/owner/repo/commits?sha=main&since={cutoff}&per_page=50")
    );
    assert_eq!(cutoff.len(), 20, "ISO-8601 Z form: {cutoff}");
}

// --- 4. commits on main the merge queue never tested -----------------------

const COMMITS: &str = r#"[
  {"sha":"aaaaaaaaa1","html_url":"https://x/c/a","author":{"login":"ipv1337"},"commit":{"message":"feat: went through the queue\n\nbody"}},
  {"sha":"bbbbbbbbb2","html_url":"https://x/c/b","author":{"login":"vitruvian-beacon-agent[bot]"},"commit":{"message":"feat(desktop): merged directly\n\nbody"}},
  {"sha":"ccccccccc3","html_url":"https://x/c/c","author":{"login":"vitruvian-copybara-sync[bot]"},"commit":{"message":"sync: allowed to skip"}},
  {"sha":"ddddddddd4","html_url":"https://x/c/d","author":null,"commit":{"author":{"name":"Someone"},"message":"chore: lookup fails"}}
]"#;

#[test]
fn only_the_untested_commit_notifies_with_subject_and_author() {
    let p = Poll::new();
    let o = p.run(&[
        ("FAKE_COMMITS_JSON", COMMITS),
        ("FAKE_QUEUE_TESTED", "aaaaaaaaa1"),
        ("FAKE_QUEUE_UNREADABLE", "ddddddddd4"),
    ]);
    assert_eq!(o.code, 0, "{o:?}");
    assert_eq!(p.posts(), 1, "{}", p.bodies());
    assert_body_has(
        &p,
        "\"title\": \"[ci] merged past the queue: bbbbbbbbb\"",
        "title",
    );
    assert_body_has(
        &p,
        "\"message\": \"This commit is on main but the merge queue never tested it: feat(desktop): merged \
         directly (author vitruvian-beacon-agent[bot]). It was merged directly. Check main's status. https://x/c/b\"",
        "message",
    );
    assert_has(
        &o.stdout,
        "-> merged past the queue: bbbbbbbbb feat(desktop): merged directly (https://x/c/b)",
        "logged",
    );
    assert_has(
        &p.gh_log(),
        "api repos/owner/repo/actions/runs?event=merge_group&head_sha=bbbbbbbbb2&per_page=1\n",
        "exact queue lookup",
    );
}

#[test]
fn unreadable_queue_lookup_is_a_warning_never_a_bypass() {
    let p = Poll::new();
    let o = p.run(&[
        ("FAKE_COMMITS_JSON", COMMITS),
        ("FAKE_QUEUE_TESTED", "aaaaaaaaa1 bbbbbbbbb2"),
        ("FAKE_QUEUE_UNREADABLE", "ddddddddd4"),
    ]);
    assert_has(
        &o.stderr,
        "WARN: cannot tell whether ddddddddd went through the merge queue",
        "warned",
    );
    assert_eq!(p.posts(), 0, "{}", p.bodies());
}

/// The script's `^[0-9]+$`: a count that is not plain digits is unreadable.
#[test]
fn non_numeric_queue_count_is_a_warning_never_a_bypass() {
    for count in ["null", "-1", "1.5", "true"] {
        let p = Poll::new();
        let o = p.run(&[
            ("FAKE_COMMITS_JSON", COMMITS),
            ("FAKE_QUEUE_COUNT", count),
            ("QUEUE_BYPASS_ALLOW", ""),
        ]);
        assert_eq!(p.posts(), 0, "{count}: {}", p.bodies());
        assert_has(&o.stderr, "WARN: cannot tell whether aaaaaaaaa", count);
    }
}

#[test]
fn emptied_allow_list_makes_the_sync_app_commit_notify() {
    let p = Poll::new();
    p.run(&[
        ("FAKE_COMMITS_JSON", COMMITS),
        ("FAKE_QUEUE_TESTED", "aaaaaaaaa1 bbbbbbbbb2 ddddddddd4"),
        ("QUEUE_BYPASS_ALLOW", ""),
    ]);
    assert_body_has(
        &p,
        "merged past the queue: ccccccccc",
        "sync app no longer exempt",
    );
    assert_eq!(p.posts(), 1);
}

/// `${QUEUE_BYPASS_ALLOW-...}`: unset means the sync app; the exemption is a
/// whole-login match, not a substring.
#[test]
fn allow_list_default_and_whole_login_match() {
    let p = Poll::new();
    p.run(&[
        ("FAKE_COMMITS_JSON", COMMITS),
        ("FAKE_QUEUE_TESTED", "aaaaaaaaa1 bbbbbbbbb2 ddddddddd4"),
    ]);
    assert_eq!(p.posts(), 0, "unset exempts the sync app: {}", p.bodies());

    let p = Poll::new();
    p.run(&[
        ("FAKE_COMMITS_JSON", COMMITS),
        ("FAKE_QUEUE_TESTED", "aaaaaaaaa1 bbbbbbbbb2 ddddddddd4"),
        ("QUEUE_BYPASS_ALLOW", "copybara-sync[bot] someone-else"),
    ]);
    assert_body_has(
        &p,
        "merged past the queue: ccccccccc",
        "a partial login is not a match",
    );
}

#[test]
fn unreadable_commit_list_warns_and_exits_zero() {
    let p = Poll::new();
    let o = p.run(&[("FAKE_COMMITS_FAIL", "1")]);
    assert_eq!(o.code, 0, "{o:?}");
    assert_has(
        &o.stderr,
        "WARN: cannot list owner/repo's recent commits -- NOT watching for queue bypasses: HTTP 502",
        "loud",
    );
    assert_eq!(p.posts(), 0);
}

// --- quiet and misconfigured runs ------------------------------------------

#[test]
fn nothing_recent_is_silent() {
    let p = Poll::new();
    let o = p.run(&[]);
    assert_eq!(o.code, 0, "{o:?}");
    assert_eq!(p.posts(), 0);
    assert_eq!(o.stderr, "", "no warnings on a quiet run");
}

#[test]
fn missing_repo_fails_before_any_query() {
    for empty in [false, true] {
        let p = Poll::new();
        let mut r = Run::new(&bin("BIN"))
            .path_first(&p.dir.join("bin"))
            .env("GH_STUB_DIR", p.dir.path());
        r = if empty {
            r.env("REPO", "")
        } else {
            r.env_remove("REPO")
        };
        let o = r.go();
        assert_eq!(o.code, 1, "{o:?}");
        assert_has(&o.stderr, "REPO must be set", "says what is missing");
        assert_eq!(p.gh_log(), "", "no gh calls");
    }
}
