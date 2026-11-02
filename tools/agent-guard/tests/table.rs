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

//! DecisionTableTest: every row of testdata/decision_table.json (the table
//! agent_guard_test.py reads too) plus the generated oversize rows, and the
//! refusal messages. The fixture is not a real git checkout, so the
//! installer check is answered "fine" here; installer.rs checks it for real.

use std::collections::{BTreeMap, BTreeSet};

use agent_guard::guard::CATEGORIES;
use agent_guard::pyval::PyVal;

use crate::common::*;

pub struct Row {
    pub command: String,
    pub want: String,
    pub category: Option<String>,
    pub key: String,
}

/// The table: the JSON rows (a bare string there is a comment), then the
/// rows too big to spell out.
pub fn table() -> Vec<Row> {
    let data = from_json(&read(&runfile(
        "tools/agent-guard/testdata/decision_table.json",
    )));
    let mut rows = Vec::new();
    for item in items(&data) {
        match item {
            PyVal::Str(_) => continue,
            PyVal::List(r) => {
                assert_eq!(r.len(), 4, "row {}", item.py_repr());
                rows.push(Row {
                    command: text(&r[0]),
                    want: text(&r[1]),
                    category: match &r[2] {
                        PyVal::None => None,
                        other => Some(text(other)),
                    },
                    key: text(&r[3]),
                });
            }
            other => panic!("bad table entry {}", other.py_repr()),
        }
    }
    // Too many commands to check in time: refused inside the repo. Real
    // commands have tens; the cap is 20,000.
    let gen = |c: String, w: &str, cat: Option<&str>| Row {
        command: c,
        want: w.into(),
        category: cat.map(|x| x.to_string()),
        key: String::new(),
    };
    rows.push(gen("true; ".repeat(25000), D, Some("oversize")));
    rows.push(gen("echo `x`".repeat(25000), D, Some("oversize")));
    rows.push(gen("true; ".repeat(5000) + "git status", A, None));
    rows.push(gen("true; ".repeat(5000) + "git push", D, Some("git-push")));
    rows
}

fn short(s: &str) -> String {
    let c: Vec<char> = s.chars().collect();
    if c.len() > 160 {
        format!(
            "{:?}... ({} chars)",
            c[..160].iter().collect::<String>(),
            c.len()
        )
    } else {
        format!("{:?}", s)
    }
}

struct Setup {
    fx: Fixture,
    _installer: InstallerOverride,
    _lock: std::sync::RwLockReadGuard<'static, ()>,
}

fn setup() -> Setup {
    let lock = shared();
    Setup {
        fx: Fixture::new(),
        _installer: InstallerOverride::set(""),
        _lock: lock,
    }
}

#[test]
fn table_is_big_enough() {
    let _l = shared();
    assert!(table().len() >= 150, "{} rows", table().len());
}

#[test]
fn every_row() {
    let t = setup();
    let mut failures = Vec::new();
    for r in table() {
        let d = t.fx.run_with(&r.command, &r.key, None);
        if d.decision != r.want || d.category != r.category {
            failures.push(format!(
                "{} [{}]: want {}/{:?}, got {}/{:?}",
                short(&r.command),
                if r.key.is_empty() { "-" } else { &r.key },
                r.want,
                r.category,
                d.decision,
                d.category
            ));
        }
    }
    assert!(failures.is_empty(), "\n{}", failures.join("\n"));
}

#[test]
fn every_category_has_a_blocked_row() {
    let _l = shared();
    let covered: BTreeSet<String> = table()
        .into_iter()
        .filter(|r| r.want == D)
        .filter_map(|r| r.category)
        .collect();
    let missing: Vec<&str> = CATEGORIES
        .iter()
        .map(|(c, _)| *c)
        .filter(|c| !covered.contains(*c))
        .collect();
    assert!(missing.is_empty(), "no blocked row for {:?}", missing);
}

#[test]
fn summary() {
    // Printed so the test log carries the per-category counts.
    let _l = shared();
    let rows = table();
    let mut counts: BTreeMap<String, usize> = BTreeMap::new();
    for r in &rows {
        *counts
            .entry(r.category.clone().unwrap_or_else(|| "allowed".into()))
            .or_default() += 1;
    }
    eprintln!("\ndecision table: {} rows", rows.len());
    for (cat, n) in counts {
        eprintln!("  {:<14} {}", cat, n);
    }
}

#[test]
fn messages_name_the_replacement() {
    let t = setup();
    let cases = [
        ("git commit -m x", "bazel run //tools/git:commit"),
        ("git push", "bazel run //tools/git:push"),
        ("git rebase origin/main", "bazel run //tools/git:sync"),
        (
            "git worktree add ../x -b y",
            "bazel run //tools/worktree -- <branch>",
        ),
        ("git worktree add --detach /tmp/x HEAD", "--detach <ref>"),
        ("git worktree lock ../x", "--lock"),
        ("git worktree prune", "--prune"),
        ("gh pr create", "bazel run //tools/agent-app -- pr-create"),
        ("gitleaks detect", "bazel run //tools/secret-scan"),
        ("actionlint", "bazel run //tools/ci:actionlint"),
        ("rm -rf ~/.cache/bazel", "bazel run //tools/bazel-cache:gc"),
        ("go test ./...", "bazel test"),
        ("cargo update", "bazel run //tools/crates:lock"),
        ("cargo update -p ring", "bazel run //tools/crates:lock"),
        ("cargo generate-lockfile", "bazel run //tools/crates:lock"),
        ("cargo add serde", "bazel run //tools/crates:lock"),
        ("cargo remove serde", "bazel run //tools/crates:lock"),
        ("prettier --write .", "bazel run //tools/format"),
        ("kubectl apply -f x.yaml", "//tools/gitops"),
        (
            "gh run rerun 1 --failed",
            "bazel run //tools/agent-app -- run-rerun <run-id>",
        ),
        (
            "gh run cancel 1",
            "bazel run //tools/agent-app -- run-cancel <run-id>",
        ),
        (
            "gh workflow run ci.yaml",
            "bazel run //tools/agent-app -- workflow-run <file.yaml>",
        ),
    ];
    for (command, needle) in cases {
        let msg = t.fx.run(command).message;
        assert!(
            msg.contains(needle),
            "{}: {:?} not in {}",
            command,
            needle,
            msg
        );
        assert!(msg.contains("guardrail"), "{}: {}", command, msg);
    }
}

#[test]
fn cargo_lock_changes_point_at_crates_lock() {
    // //tools/crates:lock exists (#4016): a lock change must not send the
    // agent to James for a target that is already there (#4027).
    let t = setup();
    for command in [
        "cargo update",
        "cargo generate-lockfile",
        "cargo add serde",
        "cargo rm serde",
        // #4171: a toolchain wrapper, +toolchain and global flags are seen through.
        "rustup run stable cargo update",
        "rustup run --install nightly cargo add serde",
        "rustup -v run stable -- cargo generate-lockfile",
        "cargo +nightly update",
        "cargo --color never add serde",
        "cargo --color=never update",
        "cargo -v --offline --manifest-path x/Cargo.toml update",
        "cargo -Z unstable-options --config k=v -C dir update",
        "rustup +stable run stable cargo update",
        "rustup -v +nightly run nightly cargo add serde",
        "cargo -vC metadata update",
        "RUSTUP_FORCE_ARG0=cargo rustup update",
        "env RUSTUP_FORCE_ARG0=cargo rustup add serde",
    ] {
        let msg = t.fx.run(command).message;
        assert!(
            msg.contains("bazel run //tools/crates:lock"),
            "{}: {}",
            command,
            msg
        );
        assert!(msg.contains("--dir <path>"), "{}: {}", command, msg);
        assert!(
            !msg.contains("no target for it yet"),
            "{}: {}",
            command,
            msg
        );
    }
    for command in ["cargo add serde", "rustup run stable cargo add serde"] {
        let msg = t.fx.run(command).message;
        assert!(
            msg.contains("Edit the dependency in Cargo.toml"),
            "{}: {}",
            command,
            msg
        );
    }
    // The refusal names what was actually run, not a flag's value.
    let msg = t.fx.run("cargo --color never add serde").message;
    assert!(msg.contains("`cargo add`"), "{}", msg);
}

#[test]
fn merges_point_at_pr_enqueue() {
    let t = setup();
    let msg = t.fx.run("gh pr merge 3 --squash --auto").message;
    assert!(
        msg.contains("bazel run //tools/agent-app -- pr-enqueue"),
        "{}",
        msg
    );
    // pr-enqueue exists: the advice must not call it unbuilt.
    assert!(!msg.contains("not in this checkout yet"), "{}", msg);
}

#[test]
fn message_says_when_there_is_no_target() {
    let t = setup();
    let msg = t.fx.run("git reset --hard HEAD~1").message;
    assert!(msg.contains("no target for it yet"), "{}", msg);
    assert!(msg.contains("James"), "{}", msg);
}

#[test]
fn run_commands_point_at_agent_app() {
    // agent-app has run-rerun, run-cancel and workflow-run (wren only);
    // deleting runs and enabling or disabling workflows still have no target.
    let t = setup();
    for command in [
        "gh run rerun 1",
        "gh run cancel 1",
        "gh workflow run ci.yaml",
    ] {
        let msg = t.fx.run(command).message;
        assert!(msg.contains("//tools/agent-app --"), "{}: {}", command, msg);
        assert!(
            msg.contains("Only wren's App has Actions write"),
            "{}: {}",
            command,
            msg
        );
        assert!(
            !msg.contains("no target for it yet"),
            "{}: {}",
            command,
            msg
        );
    }
    let msg = t.fx.run("gh workflow run ci.yaml").message;
    assert!(msg.contains("workflow-allowlist.txt"), "{}", msg);
    for command in [
        "gh run delete 1",
        "gh workflow enable ci.yaml",
        "gh workflow disable ci.yaml",
    ] {
        let msg = t.fx.run(command).message;
        assert!(msg.contains("no target for it yet"), "{}: {}", command, msg);
        assert!(
            msg.contains("nothing that deletes runs or enables or disables"),
            "{}: {}",
            command,
            msg
        );
    }
}

#[test]
fn pending_target_is_flagged_until_it_lands() {
    let t = setup();
    let msg = t.fx.run("git push").message;
    assert!(msg.contains("not in this checkout yet"), "{}", msg);
    write(
        &join(&t.fx.repo, "tools/git/BUILD"),
        "sh_binary(name = \"push\")\n",
    );
    let msg = t.fx.run("git push").message;
    assert!(!msg.contains("not in this checkout yet"), "{}", msg);
}

#[test]
fn merge_commit_points_at_concluding_merge() {
    let t = setup();
    let msg = t.fx.run_with("git commit", "merging", None).message;
    assert!(msg.contains("//tools/git:commit"), "{}", msg);
    assert!(msg.contains("concludes"), "{}", msg);
}

/// PendingTargetsTest.test_existing_targets_are_not_called_pending.
#[test]
fn existing_targets_are_not_called_pending() {
    let t = setup();
    for command in [
        "gh pr create --title x",
        "gh pr merge 1 --auto",
        "gh run rerun 1",
        "gh run cancel 1",
        "gh workflow run ci.yaml",
        "git worktree add --detach /tmp/x HEAD",
        "git worktree lock ../x",
    ] {
        let msg = t.fx.run(command).message;
        assert!(
            !msg.contains("not in this checkout yet"),
            "{}: {}",
            command,
            msg
        );
        assert!(msg.contains("//tools/"), "{}: {}", command, msg);
    }
}
