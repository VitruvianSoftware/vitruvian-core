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

//! ScopeTest and ModesTest: where the guard applies, and the policy's
//! enforce / warn / off modes.

use std::collections::BTreeSet;

use agent_guard::gitstate::GitState;
use agent_guard::guard::{evaluate, load_policy, Modes, CATEGORIES, UNKNOWN_CWD};
use agent_guard::hook::default_policy_path;
use agent_guard::pyval::PyVal;

use crate::common::*;

fn all(mode: &str) -> Modes {
    CATEGORIES
        .iter()
        .map(|(c, _)| (c.to_string(), mode.to_string()))
        .collect()
}

// --- ScopeTest ----------------------------------------------------------------

#[test]
fn oversize_outside_is_allowed() {
    let _l = shared();
    let fx = Fixture::new();
    let d = fx.run_with(&"true; ".repeat(25000), "out", None);
    assert_eq!(d.decision, "allow");
}

#[test]
fn outside_vitruvian_core_is_allowed() {
    let _l = shared();
    let fx = Fixture::new();
    for command in [
        "git push",
        "git commit -am x",
        "go test ./...",
        "pnpm install",
        "gh pr merge 1 --auto",
        "kubectl apply -f x",
    ] {
        let d = fx.run_with(command, "out", None);
        assert_eq!(d.decision, "allow", "{}", command);
        assert_eq!(d.scope, "outside", "{}", command);
    }
}

#[test]
fn other_bazel_repo_is_outside() {
    let _l = shared();
    let fx = Fixture::new();
    let other = join(&fx.tmp, "abrialcode");
    write(
        &join(&other, "MODULE.bazel"),
        "module(name = \"abrialcode\")\n",
    );
    let d = evaluate(
        "git push",
        &other,
        None,
        Some(&fx.home),
        probe(GitState::default()),
        true,
    );
    assert_eq!(d.decision, "allow");
}

#[test]
fn worktree_and_subdirectory_are_inside() {
    let _l = shared();
    let fx = Fixture::new();
    for cwd in [fx.wt.clone(), join(&fx.repo, "src")] {
        let d = evaluate(
            "git push",
            &cwd,
            None,
            Some(&fx.home),
            probe(GitState::default()),
            true,
        );
        assert_eq!(d.decision, "deny", "{}", cwd);
        assert_eq!(d.scope, "inside", "{}", cwd);
    }
}

#[test]
fn cd_out_of_the_repo_leaves_scope() {
    let _l = shared();
    let fx = Fixture::new();
    assert_eq!(fx.run("cd {out} && git push").decision, "allow");
}

#[test]
fn inside_allowed_is_reported_inside() {
    let _l = shared();
    let fx = Fixture::new();
    assert_eq!(fx.run("git status").scope, "inside");
}

#[test]
fn unknown_location_is_enforced() {
    let _l = shared();
    let fx = Fixture::new();
    let run = |command: &str| {
        evaluate(
            command,
            UNKNOWN_CWD,
            None,
            Some(&fx.home),
            probe(GitState {
                primary: true,
                ..GitState::default()
            }),
            false,
        )
    };
    for command in ["go vet ./...", "git push", "cd /tmp && git commit -m x"] {
        let d = run(command);
        assert_eq!(
            (d.decision.as_str(), d.scope.as_str()),
            ("deny", "unknown"),
            "{}",
            command
        );
    }
    assert_eq!(run(&"true; ".repeat(25000)).decision, "deny");
    let d = run("git status");
    assert_eq!(
        (d.decision.as_str(), d.scope.as_str()),
        ("allow", "unknown")
    );
    assert_eq!(run("gh pr merge 1 -R someone/else").decision, "allow");
}

// --- ModesTest ----------------------------------------------------------------

#[test]
fn enforce_warn_off() {
    let _l = shared();
    let fx = Fixture::new();
    let base = all("enforce");
    assert_eq!(fx.run_with("git push", "", Some(&base)).decision, "deny");
    let mut warn = base.clone();
    warn.insert("git-push".into(), "warn".into());
    let d = fx.run_with("git push", "", Some(&warn));
    assert_eq!(d.decision, "warn");
    assert_eq!(d.category.as_deref(), Some("git-push"));
    let mut off = base;
    off.insert("git-push".into(), "off".into());
    assert_eq!(fx.run_with("git push", "", Some(&off)).decision, "allow");
}

#[test]
fn a_later_enforced_segment_beats_an_earlier_warning() {
    let _l = shared();
    let fx = Fixture::new();
    let mut modes = all("enforce");
    modes.insert("git-commit".into(), "warn".into());
    let d = fx.run_with("git commit -m x && git push", "", Some(&modes));
    assert_eq!(
        (d.decision.as_str(), d.category.as_deref()),
        ("deny", Some("git-push"))
    );
}

#[test]
fn policy_file() {
    let _l = shared();
    let fx = Fixture::new();
    let path = join(&fx.tmp, "policy.json");
    let policy = obj(vec![
        ("default_mode", s("warn")),
        (
            "categories",
            obj(vec![
                ("go", obj(vec![("mode", s("off"))])),
                ("git-push", s("enforce")),
            ]),
        ),
    ]);
    std::fs::write(&path, to_json(&policy)).unwrap();
    let modes = load_policy(Some(&path)).expect("policy loads");
    assert_eq!(modes["go"], "off");
    assert_eq!(modes["git-push"], "enforce");
    assert_eq!(modes["git-commit"], "warn");
}

#[test]
fn broken_or_missing_policy_enforces_everything() {
    let _l = shared();
    let fx = Fixture::new();
    let path = join(&fx.tmp, "broken.json");
    std::fs::write(&path, "{not json").unwrap();
    for p in [path, join(&fx.tmp, "missing.json")] {
        let modes = load_policy(Some(&p)).expect("no crash");
        let values: BTreeSet<&String> = modes.values().collect();
        assert_eq!(
            values.into_iter().collect::<Vec<_>>(),
            vec!["enforce"],
            "{}",
            p
        );
    }
}

#[test]
fn shipped_policy_enforces_every_category() {
    let _l = shared();
    let path = default_policy_path();
    // A missing file would also load as "enforce everything": insist on the real one.
    assert!(std::path::Path::new(&path).is_file(), "{} is missing", path);
    let modes = load_policy(Some(&path)).expect("policy loads");
    let want: BTreeSet<String> = CATEGORIES.iter().map(|(c, _)| c.to_string()).collect();
    let got: BTreeSet<String> = modes.keys().cloned().collect();
    assert_eq!(got, want);
    let values: BTreeSet<&String> = modes.values().collect();
    assert_eq!(values.into_iter().collect::<Vec<_>>(), vec!["enforce"]);
    let data = from_json(&read(&path));
    let keys: BTreeSet<String> = match at(&data, "categories") {
        PyVal::Dict(items) => items.iter().map(|(k, _)| k.clone()).collect(),
        other => panic!("categories is {}", other.py_repr()),
    };
    assert_eq!(keys, want);
    // And it is the policy the target ships.
    assert_eq!(read(&path), read(&runfile("tools/agent-guard/policy.json")));
}
