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

//! InstallerSourceTest: an agent may run the installer only from a checkout
//! where its sources (install.py, agent_guard.py, BUILD, and every file under
//! tools/agent-guard/src and tools/agent-guard/install) are origin/main's and
//! no bazelrc sets run_under: an edited installer would otherwise run with
//! James's HOME. Against a real git checkout.

use agent_guard::classify::installer_problem;
use agent_guard::gitstate::GitState;
use agent_guard::guard::{evaluate, Decision};
use agent_guard::scope::clear_caches;

use crate::common::*;

const COMMANDS: [&str; 6] = [
    "bazel run //tools/agent-guard:install",
    "bazel run //tools/agent-guard:install -- --check",
    "bazel run //tools/agent-guard:install -- --dry-run",
    "bazel run //tools/agent-guard:install -- --uninstall --dry-run",
    "python3 tools/agent-guard/install.py --check",
    "bazel-bin/tools/agent-guard/install --dry-run",
];

/// The Rust installer, which must be held to the same rule.
const RS_COMMANDS: [&str; 4] = [
    "bazel run //tools/agent-guard:install_rs",
    "bazel run //tools/agent-guard:install_rs -- --check",
    "bazel run //tools/agent-guard:install_rs -- --uninstall --dry-run",
    "bazel-bin/tools/agent-guard/install_rs --dry-run",
];

struct Repo {
    tmp: TempDir,
    repo: String,
    home: String,
    _lock: std::sync::RwLockReadGuard<'static, ()>,
}

impl Repo {
    fn new() -> Self {
        let lock = shared();
        let tmp = realpath(&mkdtemp("agent-guard-installer-"));
        let repo = join(&tmp, "vitruvian-core");
        let home = join(&tmp, "home");
        makedirs(&home);
        let r = Repo {
            tmp: TempDir(tmp),
            repo,
            home,
            _lock: lock,
        };
        let files = [
            ("MODULE.bazel", "module(name = \"vitruvian_core\")\n"),
            (
                ".bazelrc",
                "try-import %workspace%/user.bazelrc\nbuild --jobs=4\n# run_under in a comment is fine\n",
            ),
            ("tools/agent-guard/install.py", "print('installer')\n"),
            ("tools/agent-guard/agent_guard.py", "# guard\n"),
            (
                "tools/agent-guard/BUILD",
                "py_binary(name = \"install\", main = \"install.py\")\n",
            ),
            ("tools/agent-guard/src/lib.rs", "// guard\n"),
            ("tools/agent-guard/install/main.rs", "// installer\n"),
        ];
        for (rel, text) in files {
            r.write(rel, text, None);
        }
        r.git(&["init", "-q", "-b", "main"], None);
        r.git(&["add", "-A"], None);
        r.git(&["commit", "-qm", "init", "--no-gpg-sign"], None);
        r.git(&["update-ref", "refs/remotes/origin/main", "HEAD"], None);
        clear_caches();
        r
    }

    fn write(&self, rel: &str, text: &str, root: Option<&str>) {
        write(&join(root.unwrap_or(&self.repo), rel), text);
    }

    fn git(&self, args: &[&str], cwd: Option<&str>) {
        git(cwd.unwrap_or(&self.repo), args, true);
    }

    fn decide(&self, command: &str, cwd: Option<&str>) -> Decision {
        evaluate(
            command,
            cwd.unwrap_or(&self.repo),
            None,
            Some(&self.home),
            probe(GitState::default()),
            true,
        )
    }

    fn assert_these(&self, commands: &[&str], want: &str, cwd: Option<&str>, needle: &str) {
        for command in commands {
            let d = self.decide(command, cwd);
            assert_eq!(d.decision, want, "{}: {}", command, d.message);
            if want == D {
                assert_eq!(d.category.as_deref(), Some("guard-config"), "{}", command);
                assert!(
                    d.message.contains(needle),
                    "{}: {:?} not in {}",
                    command,
                    needle,
                    d.message
                );
            }
        }
    }

    fn assert_all(&self, want: &str, cwd: Option<&str>, needle: &str) {
        self.assert_these(&COMMANDS, want, cwd, needle);
    }
}

impl Drop for Repo {
    fn drop(&mut self) {
        clear_caches();
        let _ = &self.tmp;
    }
}

#[test]
fn allowed_when_the_installer_is_origin_mains() {
    let r = Repo::new();
    assert_eq!(installer_problem(&r.repo, &r.home), "");
    r.assert_all(A, None, "");
}

#[test]
fn an_edited_install_py_is_refused() {
    let r = Repo::new();
    r.write(
        "tools/agent-guard/install.py",
        "print('anything I like')\n",
        None,
    );
    r.assert_all(
        D,
        None,
        &format!("tools/agent-guard/install.py in {} differs", r.repo),
    );
}

#[test]
fn an_edited_build_or_guard_is_refused() {
    let r = Repo::new();
    for rel in [
        "tools/agent-guard/BUILD",
        "tools/agent-guard/agent_guard.py",
    ] {
        r.write(rel, "# changed\n", None);
        r.assert_all(D, None, rel);
        r.git(&["checkout", "--", rel], None);
    }
    r.assert_all(A, None, "");
}

#[test]
fn a_committed_but_unmerged_edit_is_refused() {
    let r = Repo::new();
    r.write("tools/agent-guard/install.py", "print('mine')\n", None);
    r.git(&["commit", "-qam", "mine", "--no-gpg-sign"], None);
    r.assert_all(D, None, "differs from origin/main's");
}

#[test]
fn an_edited_installer_in_a_worktree_is_refused_there_only() {
    let r = Repo::new();
    let wt = join(&r.tmp.0, "vitruvian-core-worktrees/feat-x");
    r.git(&["worktree", "add", "-q", "--detach", &wt], None);
    r.write("tools/agent-guard/install.py", "print('mine')\n", Some(&wt));
    r.assert_all(D, Some(&wt), &format!("install.py in {} differs", wt));
    r.assert_all(A, None, "");
}

#[test]
fn no_origin_main_is_refused() {
    let r = Repo::new();
    r.git(&["update-ref", "-d", "refs/remotes/origin/main"], None);
    r.assert_all(D, None, "origin/main or its installer cannot be read");
}

#[test]
fn run_under_in_any_bazelrc_is_refused() {
    let r = Repo::new();
    r.write(
        "user.bazelrc",
        "run --run_under='env -u CLAUDECODE'\n",
        None,
    );
    r.assert_all(D, None, "user.bazelrc sets run_under");
    std::fs::remove_file(join(&r.repo, "user.bazelrc")).unwrap();
    r.write(".bazelrc", "run --script_path=/tmp/x.sh\n", Some(&r.home));
    r.assert_all(D, None, ".bazelrc sets run_under or script_path");
}

#[test]
fn outside_a_checkout_is_refused() {
    let r = Repo::new();
    let d = r.decide("bazel run //tools/agent-guard:install", Some(&r.home));
    assert_eq!(d.decision, D, "{}", d.message);
    assert!(
        d.message
            .contains("not run from inside a vitruvian-core checkout"),
        "{}",
        d.message
    );
}

// The Rust installer is built from every file under src/ and install/, so
// each of those is held to origin/main too, and :install_rs is an installer.

#[test]
fn an_edited_file_under_src_is_refused() {
    let r = Repo::new();
    r.write("tools/agent-guard/src/lib.rs", "// anything I like\n", None);
    let needle = format!("tools/agent-guard/src/lib.rs in {} differs", r.repo);
    r.assert_all(D, None, &needle);
    r.assert_these(&RS_COMMANDS, D, None, &needle);
    r.git(&["checkout", "--", "tools/agent-guard/src/lib.rs"], None);
    r.assert_all(A, None, "");
}

#[test]
fn an_added_file_under_install_is_refused() {
    let r = Repo::new();
    r.write("tools/agent-guard/install/extra.rs", "// mine\n", None);
    let needle = format!("tools/agent-guard/install/extra.rs in {} differs", r.repo);
    r.assert_all(D, None, &needle);
    r.assert_these(&RS_COMMANDS, D, None, &needle);
    std::fs::remove_file(join(&r.repo, "tools/agent-guard/install/extra.rs")).unwrap();
    r.assert_all(A, None, "");
}

#[test]
fn install_rs_is_treated_like_install() {
    let r = Repo::new();
    r.assert_these(&RS_COMMANDS, A, None, "");
    r.write("tools/agent-guard/install.py", "print('mine')\n", None);
    r.assert_these(
        &RS_COMMANDS,
        D,
        None,
        &format!("tools/agent-guard/install.py in {} differs", r.repo),
    );
    let d = r.decide("bazel run //tools/agent-guard:install_rs", Some(&r.home));
    assert_eq!(d.decision, D, "{}", d.message);
    assert!(
        d.message
            .contains("not run from inside a vitruvian-core checkout"),
        "{}",
        d.message
    );
}
