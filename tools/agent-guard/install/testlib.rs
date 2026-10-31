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

//! testlib.py, for the installer's tests: a throwaway vitruvian-core
//! checkout with a real git history and an origin/main ref, wired the way
//! the repo is.
//!
//! The launcher in it is the repo's real hook.sh with its list of pythons
//! replaced (as testlib.py does) by a stub that stands in for python3 running
//! the guard, so these tests need neither python3 nor a compiled guard: what
//! they exercise is the installer and hook.sh, not the guard's decisions.
//! The repo's real .claude/settings.json and .agents/hooks.json are copied in
//! unchanged, so the wiring checks compare against the files as they are.

use std::collections::BTreeMap;
use std::ffi::OsString;
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::process::Command;

use agent_guard::paths::{exists, getcwd, join, realpath};
use agent_guard::pyval::{dict, loads, s, PyVal};

use crate::pyjson::{dumps_indent, get_mut, set};
use crate::sys::mkdtemp;

pub const GIT_ENV: [(&str, &str); 6] = [
    ("GIT_AUTHOR_NAME", "t"),
    ("GIT_AUTHOR_EMAIL", "t@example.com"),
    ("GIT_COMMITTER_NAME", "t"),
    ("GIT_COMMITTER_EMAIL", "t@example.com"),
    ("GIT_CONFIG_NOSYSTEM", "1"),
    ("GIT_CONFIG_GLOBAL", "/dev/null"),
];

/// A file from the test's runfiles (the repo's hook files, policy.json).
pub fn runfile(rel: &str) -> String {
    let mut bases = vec![getcwd()];
    for var in ["TEST_SRCDIR", "RUNFILES_DIR"] {
        if let Ok(d) = std::env::var(var) {
            bases.push(join(&d, "_main"));
        }
    }
    for base in &bases {
        let p = join(base, rel);
        if exists(&p) {
            return p;
        }
    }
    panic!("runfile {} not found under {:?}", rel, bases)
}

pub fn read(path: &str) -> String {
    fs::read_to_string(path).unwrap_or_else(|e| panic!("read {}: {}", path, e))
}

pub fn write(path: &str, text: &str) {
    if let Some(parent) = std::path::Path::new(path).parent() {
        fs::create_dir_all(parent).unwrap();
    }
    fs::write(path, text).unwrap_or_else(|e| panic!("write {}: {}", path, e));
}

/// A folder under /tmp, not TEST_TMPDIR: inside Bazel that sits below an
/// execroot whose MODULE.bazel would make the "outside" folders look inside.
pub fn tmpdir(prefix: &str) -> String {
    let base = if fs::metadata("/tmp").map(|m| m.is_dir()).unwrap_or(false) {
        "/tmp".to_string()
    } else {
        std::env::temp_dir().to_string_lossy().into_owned()
    };
    realpath(&mkdtemp(&base, prefix).unwrap())
}

/// Stands in for python3 running agent_guard.py. hook.sh runs it as
/// `"$py" -I -S -c "$boot" "$src"`, the tool call on stdin and
/// AGENT_GUARD_POLICY naming the policy it chose. It refuses `git stash`
/// (git-stash) and `go vet` (go) unless that policy puts the category in warn
/// or off mode, and answers in the caller's format (agy's has "toolCall").
const STUB_PYTHON: &str = r##"#!/bin/sh
src=$5
[ -s "$src/agent_guard.py" ] || { echo "stub python: no agent_guard.py in $src" >&2; exit 1; }
in=$(cat)
case $in in
*'git stash'*) cat=git-stash ;;
*'go vet'*) cat=go ;;
*) exit 0 ;;
esac
if tr -d ' \t\n' <"$AGENT_GUARD_POLICY" | grep -Eq "\"$cat\":\\{\"mode\":\"(warn|off)\""; then
  exit 0
fi
why="agent-guard (stub): $cat is refused"
case $in in
*'"toolCall"'*) printf '{"decision": "deny", "reason": "%s"}\n' "$why" ;;
*) printf '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "%s"}}\n' "$why" ;;
esac
"##;

/// hook.sh, with its list of pythons replaced.
pub fn launcher_text(pythons: &[String]) -> String {
    let text = read(&runfile("tools/agent-guard/hook.sh"));
    let begin = text
        .find("# --- pythons: begin")
        .expect("hook.sh lost its pythons block markers");
    let end_marker = "# --- pythons: end ---\n";
    let end = text[begin..]
        .find(end_marker)
        .expect("hook.sh lost its pythons block markers")
        + begin
        + end_marker.len();
    format!(
        "{}pythons=\"{}\"\n{}",
        &text[..begin],
        pythons.join(" "),
        &text[end..]
    )
}

pub fn git(cwd: &str, args: &[&str]) -> String {
    let out = Command::new("git")
        .arg("-C")
        .arg(cwd)
        .args(args)
        .envs(GIT_ENV)
        .output()
        .expect("git runs");
    assert!(
        out.status.success(),
        "git {:?} in {}: {}",
        args,
        cwd,
        String::from_utf8_lossy(&out.stderr)
    );
    String::from_utf8_lossy(&out.stdout).into_owned()
}

/// A fake checkout: MODULE.bazel, tools/agent-guard and both hook files,
/// committed, with refs/remotes/origin/main pointing at that commit.
pub struct Checkout {
    pub tmp: String,
    pub root: String,
    pub home: String,
    pub out: String,
    pub guard_dir: String,
    pub stub: String,
}

impl Checkout {
    pub fn new() -> Checkout {
        Checkout::with_pythons(None)
    }

    /// pythons: hook.sh's list (default: the stub).
    pub fn with_pythons(pythons: Option<Vec<String>>) -> Checkout {
        let tmp = tmpdir("agent-guard-checkout-");
        let co = Checkout {
            root: join(&tmp, "vitruvian-core"),
            home: join(&tmp, "home"),
            out: join(&tmp, "elsewhere"),
            guard_dir: join(&tmp, "vitruvian-core/tools/agent-guard"),
            stub: join(&tmp, "stub-python3"),
            tmp,
        };
        for d in [&co.guard_dir, &co.home, &co.out] {
            fs::create_dir_all(d).unwrap();
        }
        write(&co.stub, STUB_PYTHON);
        fs::set_permissions(&co.stub, fs::Permissions::from_mode(0o755)).unwrap();
        co.write("MODULE.bazel", "module(name = \"vitruvian_core\")\n");
        let pythons = pythons.unwrap_or_else(|| vec![co.stub.clone()]);
        co.write("tools/agent-guard/hook.sh", &launcher_text(&pythons));
        co.write(
            "tools/agent-guard/agent_guard.py",
            "# Stands in for the guard: the tests' stub python answers instead.\n",
        );
        co.write(
            "tools/agent-guard/policy.json",
            &read(&runfile("tools/agent-guard/policy.json")),
        );
        for rel in [".claude/settings.json", ".agents/hooks.json"] {
            co.write(rel, &read(&runfile(rel)));
        }
        git(&co.root, &["init", "-q", "-b", "main"]);
        git(&co.root, &["add", "-A"]);
        git(&co.root, &["commit", "-q", "-m", "init", "--no-gpg-sign"]);
        git(
            &co.root,
            &["update-ref", "refs/remotes/origin/main", "HEAD"],
        );
        co
    }

    pub fn write(&self, rel: &str, text: &str) {
        write(&join(&self.root, rel), text);
    }

    pub fn append(&self, rel: &str, text: &str) {
        let path = join(&self.root, rel);
        let mut have = read(&path);
        have.push_str(text);
        write(&path, &have);
    }

    pub fn set_policy(&self, modes: &[(&str, &str)], commit: bool) {
        let mut data = loads(&read(&runfile("tools/agent-guard/policy.json"))).unwrap();
        let cats = get_mut(&mut data, "categories").unwrap();
        for (cat, mode) in modes {
            set(get_mut(cats, cat).unwrap(), "mode", s(mode));
        }
        self.write(
            "tools/agent-guard/policy.json",
            &(dumps_indent(&data, ": ", true) + "\n"),
        );
        if commit {
            self.commit_to_main("policy");
        }
    }

    pub fn commit_to_main(&self, message: &str) {
        git(&self.root, &["add", "-A"]);
        git(
            &self.root,
            &["commit", "-q", "-m", message, "--no-gpg-sign"],
        );
        git(
            &self.root,
            &["update-ref", "refs/remotes/origin/main", "HEAD"],
        );
    }
}

impl Drop for Checkout {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.tmp);
    }
}

/// The test process's environment without anything that would make a run
/// an agent's, or aim it: each test adds what it needs.
pub fn clean_env() -> BTreeMap<OsString, OsString> {
    std::env::vars_os()
        .filter(|(k, _)| {
            let k = k.to_string_lossy();
            !(["CLAUDECODE", "ANTIGRAVITY_AGENT", "GEMINI_CLI"].contains(&k.as_ref())
                || k.starts_with("ANTIGRAVITY_")
                || k.starts_with("AGENT_GUARD_")
                || k == "BUILD_WORKSPACE_DIRECTORY"
                || k == "CLAUDE_PROJECT_DIR"
                || k == "CLAUDE_CODE_SESSION_ID")
        })
        .collect()
}

/// Claude Code's PreToolUse payload for Bash.
pub fn claude(command: &str, cwd: &str) -> PyVal {
    dict(vec![
        ("session_id", s("test")),
        ("cwd", s(cwd)),
        ("hook_event_name", s("PreToolUse")),
        ("tool_name", s("Bash")),
        ("tool_input", dict(vec![("command", s(command))])),
    ])
}

/// agy 1.4.0's real PreToolUse payload for run_command (no top-level cwd).
pub fn agy(command: &str, cwd: &str) -> PyVal {
    dict(vec![
        (
            "toolCall",
            dict(vec![
                ("name", s("run_command")),
                (
                    "args",
                    dict(vec![
                        ("CommandLine", s(command)),
                        ("Cwd", s(cwd)),
                        ("WaitMsBeforeAsync", PyVal::Int("5000".into())),
                    ]),
                ),
            ]),
        ),
        ("stepIdx", PyVal::Int("0".into())),
        ("conversationId", s("test")),
        ("workspacePaths", PyVal::List(vec![s(cwd)])),
    ])
}

pub fn decision(out: &str, antigravity: bool) -> String {
    if out.is_empty() {
        return "allow".into();
    }
    let data = loads(out).expect("hook JSON");
    let v = if antigravity {
        data.get("decision")
    } else {
        data.get("hookSpecificOutput")
            .and_then(|h| h.get("permissionDecision"))
    };
    v.and_then(|v| v.as_str()).expect("a decision").to_string()
}
