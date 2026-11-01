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

//! //tools/ci:session_start_test -- .claude/session-start.sh, the
//! SessionStart hook that runs cloud-bootstrap.sh, tailscale-up.sh and
//! kube-setup.sh in that order. The later steps need what the earlier ones
//! made (the tailscale binary, and the TS_AUTHKEY / LAB_SA_TOKEN
//! cloud-bootstrap fetches into session.env), and Claude Code runs an event's
//! hooks in parallel, so as three hooks they raced.
//!
//! Runs the real wrapper against fake steps that record when they start and
//! end, and checks: one step finishes before the next starts; each step sees
//! what the one before it wrote; a failing step does not stop the next; their
//! stdout comes through in order; it always exits 0. Then checks the wiring:
//! settings.json runs the wrapper, no SessionStart hook runs a step on its own
//! (that would race again), and every step the wrapper names exists. Ported
//! case for case from the former tools/ci/session-start_test.sh.

mod common;

use ci_testkit::{write_exe, TempDir};
use common::*;
use std::path::{Path, PathBuf};
use std::process::Command;

const WRAPPER: &str = ".claude/session-start.sh";
const STEPS: [&str; 3] = [
    "tools/cloud-bootstrap/cloud-bootstrap.sh",
    ".claude/tailscale-up.sh",
    ".claude/kube-setup.sh",
];

/// The wrapper under test: $HOOK_UNDER_TEST when set (a planted-break run
/// points it at a broken copy), else the repo's.
fn wrapper() -> PathBuf {
    match std::env::var_os("HOOK_UNDER_TEST") {
        Some(p) => p.into(),
        None => repo(WRAPPER),
    }
}

/// A copy of the repo layout the wrapper resolves its steps against, with
/// each step replaced by a fake that logs start/end; the first takes a moment
/// and then writes session.env, the next two log whether they could see it.
struct Tree {
    work: TempDir,
    tree: PathBuf,
    log: PathBuf,
    env_file: PathBuf,
}

impl Tree {
    fn new() -> Tree {
        let work = TempDir::new();
        let tree = work.join("tree");
        std::fs::create_dir_all(tree.join(".claude")).unwrap();
        std::fs::create_dir_all(tree.join("tools/cloud-bootstrap")).unwrap();
        std::fs::copy(wrapper(), tree.join(".claude/session-start.sh")).unwrap();
        let log = work.join("log");
        let env_file = work.join("session.env");
        let t = Tree {
            work,
            tree,
            log,
            env_file,
        };
        let seen = format!(
            "if [ -s \"{}\" ]; then echo \"  saw session.env\" >>\"{}\"; fi",
            t.env_file.display(),
            t.log.display()
        );
        t.fake_step(
            "tools/cloud-bootstrap/cloud-bootstrap.sh",
            "cloud-bootstrap",
            &format!(
                "sleep 1; echo TS_AUTHKEY=x >\"{}\"; echo 'cloud-bootstrap: out'",
                t.env_file.display()
            ),
        );
        t.fake_step(
            ".claude/tailscale-up.sh",
            "tailscale-up",
            &format!("{seen}; echo 'tailscale-up: out'"),
        );
        t.fake_step(
            ".claude/kube-setup.sh",
            "kube-setup",
            &format!("{seen}; echo 'kube-setup: out'"),
        );
        t
    }

    fn fake_step(&self, rel: &str, name: &str, body: &str) {
        write_exe(
            self.tree.join(rel),
            format!(
                "#!/usr/bin/env bash\necho \"start {name}\" >>\"{log}\"\n{body}\necho \"end {name}\" >>\"{log}\"\n",
                log = self.log.display()
            ),
        );
    }

    /// `cd / && bash <tree>/.claude/session-start.sh`
    fn run(&self) -> (String, i32) {
        let o = Command::new("bash")
            .arg(self.tree.join(".claude/session-start.sh"))
            .current_dir("/")
            .output()
            .unwrap();
        (
            String::from_utf8_lossy(&o.stdout).into_owned(),
            o.status.code().unwrap_or(-1),
        )
    }
}

#[test]
fn runs_the_steps_in_order() {
    let t = Tree::new();
    let (out, rc) = t.run();
    let want = "start cloud-bootstrap
end cloud-bootstrap
start tailscale-up
  saw session.env
end tailscale-up
start kube-setup
  saw session.env
end kube-setup
";
    let log = ci_testkit::read(&t.log);
    assert_eq!(log, want, "steps overlapped or ran out of order");
    assert_eq!(
        out, "cloud-bootstrap: out\ntailscale-up: out\nkube-setup: out\n",
        "their stdout comes through, in order"
    );
    assert_eq!(rc, 0, "exits 0");
    let _ = &t.work;
}

#[test]
fn a_failing_step_does_not_stop_the_rest() {
    let t = Tree::new();
    t.fake_step(".claude/tailscale-up.sh", "tailscale-up", "exit 3");
    let (_, rc) = t.run();
    let log = ci_testkit::read(&t.log);
    assert!(
        log.lines().any(|l| l == "end kube-setup"),
        "stopped after a failing step: {log}"
    );
    assert_eq!(rc, 0, "and the hook still exits 0");
}

#[test]
fn settings_json_runs_the_wrapper_and_no_step_on_its_own() {
    let work = TempDir::new();
    let jq_dir = jq_dir(&work);
    let hooks = wired(
        &jq_dir,
        r#".hooks.SessionStart[]?.hooks[]? | select(.type == "command") | .command"#,
    );
    assert!(
        hooks.contains(".claude/session-start.sh"),
        "settings.json does not run .claude/session-start.sh: '{hooks}'"
    );
    for step in STEPS {
        assert!(
            !hooks.contains(step),
            "settings.json runs {step} as its own hook, which races the others"
        );
    }
}

#[test]
fn the_wrapper_runs_every_step_which_exists_in_order() {
    let text = std::fs::read_to_string(wrapper()).unwrap();
    for step in STEPS {
        assert!(
            text.contains(&format!("\"${{root}}/{step}\"")) && is_executable(&repo(step)),
            "the wrapper does not run {step}, or it is missing or not executable"
        );
    }
    // grep -oE '"\$\{root\}/[^"]+"' | strip the quotes and the ${root}/ prefix
    let mut order = Vec::new();
    let mut rest = text.as_str();
    while let Some(i) = rest.find("\"${root}/") {
        let after = &rest[i + "\"${root}/".len()..];
        match after.find('"') {
            // grep is line-based: a match never spans a newline.
            Some(j) if j == 0 || after[..j].contains('\n') => {
                rest = after;
            }
            None => break,
            Some(j) => {
                order.push(&after[..j]);
                rest = &after[j + 1..];
            }
        }
    }
    assert_eq!(order, STEPS, "wrapper order");
    assert!(
        is_executable(Path::new(&repo(WRAPPER))),
        "wrapper is not executable"
    );
}
