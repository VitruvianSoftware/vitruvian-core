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

//! Black-box tests for //tools/ci:actionlint: it fails on what the required
//! actionlint check fails on (a broken expression, a shellcheck warning in a
//! `run:` block, an action not pinned to a SHA), passes a clean workflow, and
//! runs the actionlint version the workflow pins. Real pinned binaries,
//! throwaway repos. Ported case for case from the former actionlint_test.sh.

use ci_testkit::{assert_has, bin, git, write, Output, Run, TempDir};
use std::path::{Path, PathBuf};

const SHA: &str = "0123456789abcdef0123456789abcdef01234567";

fn good() -> String {
    format!(
        "on: push
permissions: {{}}
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@{SHA} # v4
      - run: echo \"$GITHUB_SHA\""
    )
}

struct Sandbox {
    work: TempDir,
}

impl Sandbox {
    fn new() -> Sandbox {
        let work = TempDir::new();
        std::fs::create_dir_all(work.join("home")).unwrap();
        Sandbox { work }
    }

    /// A repo under the sandbox holding one workflow, `w.yaml`.
    fn repo(&self, name: &str, body: &str) -> PathBuf {
        let dir = self.work.join(name);
        write(dir.join(".github/workflows/w.yaml"), format!("{body}\n"));
        git(&dir, &["init", "-q", "."]);
        dir
    }

    fn run(&self) -> Run {
        Run::new(&bin("BIN"))
            .cwd(self.work.path())
            .env("HOME", self.work.join("home"))
            .env("GIT_CONFIG_NOSYSTEM", "1")
    }

    fn lint(&self, repo: &Path) -> Output {
        self.run().env("BUILD_WORKSPACE_DIRECTORY", repo).go()
    }
}

// Shell case 1: "a clean, pinned workflow passes".
#[test]
fn clean_pinned_workflow_passes() {
    let s = Sandbox::new();
    let o = s.lint(&s.repo("good", &good()));
    assert_eq!(o.code, 0, "a clean workflow failed\n{}", o.all());
    assert_has(&o.all(), "pinned to a commit SHA", "pin-check success line");
}

// Shell case 2: "a broken expression fails, naming the file".
#[test]
fn broken_expression_fails_naming_the_file() {
    let s = Sandbox::new();
    let body = format!(
        "{}\n      - run: echo ${{{{ github.no_such_context.x }}}}",
        good()
    );
    let o = s.lint(&s.repo("expr", &body));
    assert_eq!(o.code, 1, "a broken expression passed\n{}", o.all());
    assert_has(&o.all(), "w.yaml", "file name");
    assert_has(&o.all(), "no_such_context", "bad context");
}

// Shell case 3: "a shellcheck warning in a run: block fails (shellcheck is wired in)".
#[test]
fn shellcheck_warning_in_run_block_fails() {
    let s = Sandbox::new();
    let body = format!("{}\n      - run: unused_var=1", good());
    let o = s.lint(&s.repo("sc", &body));
    assert_eq!(o.code, 1, "shellcheck did not run\n{}", o.all());
    assert_has(&o.all(), "SC2034", "shellcheck code");
}

// Shell case 4: "an info-level shellcheck note passes, as in CI (--severity=warning)".
#[test]
fn info_level_shellcheck_note_passes() {
    let s = Sandbox::new();
    let body = format!("{}\n      - run: echo $HOME", good());
    let o = s.lint(&s.repo("info", &body));
    assert_eq!(o.code, 0, "an info-level note failed\n{}", o.all());
}

// Shell case 5: "an action pinned to a tag fails and is named".
#[test]
fn tag_pinned_action_fails_and_is_named() {
    let s = Sandbox::new();
    let body = format!("{}\n      - uses: actions/setup-go@v5", good());
    let o = s.lint(&s.repo("tag", &body));
    assert_eq!(o.code, 1, "a tag-pinned action passed\n{}", o.all());
    assert_has(&o.all(), "pinned to a full commit SHA", "pin-check failure");
    assert_has(&o.all(), "setup-go@v5", "offending action");
}

// Shell case 6: "a missing actionlint is exit 2, not a pass".
#[test]
fn missing_actionlint_is_exit_2_not_a_pass() {
    let s = Sandbox::new();
    let repo = s.repo("good", &good());
    let o = s
        .run()
        .env("ACTIONLINT", s.work.join("nope"))
        .env("BUILD_WORKSPACE_DIRECTORY", &repo)
        .go();
    assert_eq!(o.code, 2, "a missing actionlint\n{}", o.all());
    assert_has(&o.all(), "nothing was checked", "refusal");
}

// Shell case 7: "tools.lock.json pins actionlint v<ver>, the version the
// workflow downloads". Every actionlint URL in the lockfile must be at the
// workflow's ACTIONLINT_VERSION, and the linux_amd64 one must be present.
#[test]
fn lockfile_pins_the_workflow_actionlint_version() {
    let workflow = std::fs::read_to_string(bin("WORKFLOW")).unwrap();
    let lock = std::fs::read_to_string(bin("LOCK")).unwrap();
    let wf_ver = workflow
        .lines()
        .find_map(|l| {
            let rest = l.trim_start().strip_prefix("ACTIONLINT_VERSION:")?;
            let v: String = rest
                .trim_start()
                .chars()
                .take_while(|c| c.is_ascii_digit() || *c == '.')
                .collect();
            Some(v)
        })
        .unwrap_or_default();
    assert!(!wf_ver.is_empty(), "no ACTIONLINT_VERSION in the workflow");
    let amd64 = format!(
        "rhysd/actionlint/releases/download/v{wf_ver}/actionlint_{wf_ver}_linux_amd64.tar.gz"
    );
    let at_ver = format!("rhysd/actionlint/releases/download/v{wf_ver}/");
    let count = |needle: &str| lock.lines().filter(|l| l.contains(needle)).count();
    assert!(
        lock.contains(&amd64),
        "tools.lock.json has no {amd64}: workflow v{wf_ver}. Update both together."
    );
    assert_eq!(
        count(&at_ver),
        count("rhysd/actionlint/releases/download/"),
        "actionlint pins drifted: workflow v{wf_ver}, but tools.lock.json has other versions. Update both together."
    );
}
