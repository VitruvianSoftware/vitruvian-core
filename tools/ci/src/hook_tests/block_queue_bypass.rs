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

//! //tools/ci:block_queue_bypass_test -- .claude/block-queue-bypass.sh, the
//! Claude Code hook that refuses commands which land a change on main without
//! the merge queue. Feeds it the same JSON payload Claude Code sends and checks
//! the decision; also checks the hook is wired into .claude/settings.json (a
//! correct script that nothing calls protects nothing). Ported case for case
//! from the former tools/ci/block-queue-bypass_test.sh.

mod common;

use ci_testkit::{Run, TempDir};
use common::*;
use std::path::Path;

const HOOK: &str = ".claude/block-queue-bypass.sh";

/// The hook's stdout for `payload`, and its exit code.
fn run_hook(jq_dir: &Path, payload: &[u8]) -> (i32, String) {
    let o = Run::new(Path::new("bash"))
        .arg(hook())
        .env("PATH", format!("{}:/usr/bin:/bin", jq_dir.display()))
        .stdin(payload)
        .go();
    (o.code, o.stdout)
}

/// The hook under test: $HOOK_UNDER_TEST when set (a planted-break run points
/// it at a broken copy), else the repo's.
fn hook() -> std::path::PathBuf {
    match std::env::var_os("HOOK_UNDER_TEST") {
        Some(p) => p.into(),
        None => repo(HOOK),
    }
}

/// "deny", "allow" or "error" for one command text.
fn decision(jq_dir: &Path, command: &str) -> String {
    let payload = jq(
        jq_dir,
        &["-Rs", r#"{tool_name: "Bash", tool_input: {command: .}}"#],
        command.as_bytes(),
    );
    let (code, out) = run_hook(jq_dir, payload.as_bytes());
    if code != 0 {
        return "error".into();
    }
    if out.is_empty() {
        return "allow".into();
    }
    jq(
        jq_dir,
        &["-r", ".hookSpecificOutput.permissionDecision"],
        out.as_bytes(),
    )
    .trim_end()
    .to_string()
}

fn expect_all(want: &str, cases: &[(&str, &str)]) {
    let work = TempDir::new();
    let jq_dir = jq_dir(&work);
    let mut fails = Vec::new();
    for (label, command) in cases {
        let got = decision(&jq_dir, command);
        if got == want {
            println!("  ✓ {want}: {label}");
        } else {
            fails.push(format!("{label} -> got {got}, want {want}: {command}"));
        }
    }
    assert!(
        fails.is_empty(),
        "{} check(s) FAILED:\n{}",
        fails.len(),
        fails.join("\n")
    );
}

// The command texts are assembled from parts so this file never contains them
// whole: the very hook under test reads tool input, and a session editing this
// file would otherwise trip it.
const MERGE: &str = concat!("gh pr ", "merge");
const ADMIN: &str = concat!("--", "admin");

#[test]
fn refuses_ways_past_the_merge_queue() {
    let c = |s: &str| s.replace("{M}", MERGE).replace("{A}", ADMIN);
    let cases: Vec<(String, String)> = vec![
        ("gh pr merge --admin".into(), c("{M} 2881 {A} --squash")),
        (
            "--admin anywhere in the command".into(),
            c("{M} --squash {A} 2881 -R VitruvianSoftware/vitruvian-core"),
        ),
        ("after cd &&".into(), c("cd /tmp/x && {M} 5 {A}")),
        ("on a later line".into(), c("echo start\n{M} 5 {A}\necho done")),
        ("with an env prefix".into(), c("GH_TOKEN=abc {M} 5 {A}")),
        ("inside $( )".into(), c("out=$({M} 5 {A})")),
        (
            "REST merge, -X PUT".into(),
            "gh api -X PUT repos/o/r/pulls/12/merge -f merge_method=squash".into(),
        ),
        (
            "REST merge, --method PUT".into(),
            "gh api --method PUT repos/o/r/pulls/12/merge".into(),
        ),
        (
            "GraphQL mergePullRequest".into(),
            r#"gh api graphql -f query="mutation { mergePullRequest(input: {pullRequestId: \"x\"}) { clientMutationId } }""#.into(),
        ),
        ("push to main".into(), "git push origin main".into()),
        ("push HEAD:main".into(), "git push origin HEAD:main".into()),
        ("push to refs/heads/main".into(), "git push origin fix/thing:refs/heads/main".into()),
        ("forced push to main".into(), "git push --force origin +HEAD:main".into()),
        ("git -C <dir> push main".into(), "git -C /repo push origin main".into()),
    ];
    let refs: Vec<(&str, &str)> = cases
        .iter()
        .map(|(a, b)| (a.as_str(), b.as_str()))
        .collect();
    assert_eq!(refs.len(), 14);
    expect_all("deny", &refs);
}

#[test]
fn allows_the_normal_path_and_look_alikes() {
    let body = format!(
        "gh pr create --title x --body-file - <<'B'\nNever run `{MERGE} {ADMIN}` on this repo.\nB"
    );
    let queue = format!("{MERGE} 2885 -R VitruvianSoftware/vitruvian-core --squash");
    let cases: Vec<(&str, &str)> = vec![
        ("gh pr merge (adds to the queue)", &queue),
        (
            "reading a PR's merge status",
            "gh api repos/o/r/pulls/12/merge",
        ),
        (
            "GraphQL enqueuePullRequest",
            r#"gh api graphql -f query="mutation { enqueuePullRequest(input: {pullRequestId: \"x\"}) { clientMutationId } }""#,
        ),
        ("push a branch", "git push -u origin ci/some-branch"),
        ("branch name ending in /main", "git push origin fix/main"),
        (
            "branch name starting with main",
            "git push origin main-menu-fix",
        ),
        ("fetch main", "git fetch origin main"),
        ("a PR body that mentions the command", &body),
        ("unrelated command", "bazel test //..."),
        ("empty command", ""),
    ];
    assert_eq!(cases.len(), 10);
    expect_all("allow", &cases);
}

#[test]
fn unreadable_payload_allows_and_exits_0() {
    let work = TempDir::new();
    let jq_dir = jq_dir(&work);
    let (code, out) = run_hook(&jq_dir, b"not json");
    assert!(
        code == 0 && out.is_empty(),
        "unreadable payload: rc={code} out={out}"
    );
}

#[test]
fn the_refusal_says_what_to_do_instead() {
    let work = TempDir::new();
    let jq_dir = jq_dir(&work);
    let cmd = format!("{MERGE} 1 {ADMIN}");
    let payload = jq(
        &jq_dir,
        &["-Rs", "{tool_input: {command: .}}"],
        cmd.as_bytes(),
    );
    let (_, out) = run_hook(&jq_dir, payload.as_bytes());
    let why = jq(
        &jq_dir,
        &["-r", ".hookSpecificOutput.permissionDecisionReason"],
        out.as_bytes(),
    );
    // The shell's `*"merge queue"*"gh pr merge <number>"*`: both, in that order.
    let want = format!("{MERGE} <number>");
    let ok = why
        .find("merge queue")
        .map_or(false, |i| why[i + "merge queue".len()..].contains(&want));
    assert!(ok, "unhelpful reason: {why}");
}

#[test]
fn settings_json_runs_the_hook_before_every_bash_command() {
    let work = TempDir::new();
    let jq_dir = jq_dir(&work);
    let wired = wired(
        &jq_dir,
        r#".hooks.PreToolUse[]? | select(.matcher == "Bash") | .hooks[] | select(.type == "command") | .command"#,
    );
    assert!(
        wired.contains(".claude/block-queue-bypass.sh"),
        "hook is not wired into .claude/settings.json: '{wired}'"
    );
}

#[test]
fn hook_script_is_executable() {
    assert!(is_executable(&repo(HOOK)), "hook script is not executable");
}
