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

//! What every test module shares: the process lock, throwaway folders, the
//! fake checkout (agent_guard_test.py's Fixture), JSON builders and the hook
//! harness (its HookHarness).

#![allow(dead_code)]

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{RwLock, RwLockReadGuard, RwLockWriteGuard};

use agent_guard::classify::{GitProbe, INSTALLER_PROBLEM_OVERRIDE};
use agent_guard::gitstate::GitState;
use agent_guard::guard::{evaluate, Decision, Modes};
use agent_guard::pyval::{dumps, dumps_str, loads, PyVal};
use agent_guard::scope::{clear_caches, repo_root_of};

pub const A: &str = "allow";
pub const D: &str = "deny";

// --- The process lock ---------------------------------------------------------
// Rust runs tests on parallel threads, but environment variables and the
// working directory belong to the process. A test that changes either takes
// the lock exclusively; every other test takes it shared, so it never runs
// while the environment or the folder is someone else's. (The guard's own
// caches and the installer override are per thread, so they need no lock.)
static PROCESS: RwLock<()> = RwLock::new(());

pub fn shared() -> RwLockReadGuard<'static, ()> {
    PROCESS.read().unwrap_or_else(|e| e.into_inner())
}

pub fn exclusive() -> RwLockWriteGuard<'static, ()> {
    PROCESS.write().unwrap_or_else(|e| e.into_inner())
}

/// Sets environment variables and puts the old values back when dropped.
/// Only while holding `exclusive()`.
pub struct EnvGuard {
    old: Vec<(String, Option<String>)>,
}

impl EnvGuard {
    pub fn new() -> Self {
        EnvGuard { old: Vec::new() }
    }

    fn remember(&mut self, key: &str) {
        if !self.old.iter().any(|(k, _)| k == key) {
            self.old.push((key.to_string(), std::env::var(key).ok()));
        }
    }

    pub fn set(&mut self, key: &str, value: &str) {
        self.remember(key);
        std::env::set_var(key, value);
    }

    pub fn remove(&mut self, key: &str) {
        self.remember(key);
        std::env::remove_var(key);
    }
}

impl Drop for EnvGuard {
    fn drop(&mut self) {
        for (k, v) in self.old.drain(..).rev() {
            match v {
                Some(v) => std::env::set_var(&k, v),
                None => std::env::remove_var(&k),
            }
        }
    }
}

/// Changes the working directory and changes it back when dropped. Only
/// while holding `exclusive()`.
pub struct CwdGuard {
    old: PathBuf,
}

impl CwdGuard {
    pub fn enter(dir: &str) -> Self {
        let old = std::env::current_dir().expect("getcwd");
        std::env::set_current_dir(dir).expect("chdir");
        CwdGuard { old }
    }
}

impl Drop for CwdGuard {
    fn drop(&mut self) {
        let _ = std::env::set_current_dir(&self.old);
    }
}

/// Replaces installer_problem's answer on this thread while alive (the
/// Python DecisionTableTest patches installer_problem to return "").
pub struct InstallerOverride;

impl InstallerOverride {
    pub fn set(answer: &str) -> Self {
        let a = answer.to_string();
        INSTALLER_PROBLEM_OVERRIDE.with(|o| *o.borrow_mut() = Some(a));
        InstallerOverride
    }
}

impl Drop for InstallerOverride {
    fn drop(&mut self) {
        INSTALLER_PROBLEM_OVERRIDE.with(|o| *o.borrow_mut() = None);
    }
}

// --- Files --------------------------------------------------------------------

/// A file the test target carries (policy.json, the table, the hook files).
/// The test runs in the runfiles' _main folder; TEST_SRCDIR makes the path
/// absolute, so it holds even while a test has changed folder.
pub fn runfile(rel: &str) -> String {
    let base = match std::env::var("TEST_SRCDIR") {
        Ok(d) if !d.is_empty() && Path::new(&d).join("_main").is_dir() => {
            Path::new(&d).join("_main")
        }
        _ => std::env::current_dir().expect("getcwd"),
    };
    let p = base.join(rel);
    assert!(p.exists(), "runfile {} not found at {}", rel, p.display());
    p.to_string_lossy().into_owned()
}

/// The root the repo's own files are read from (testlib.REPO_FILES_ROOT).
pub fn repo_files_root() -> String {
    let settings = runfile(".claude/settings.json");
    Path::new(&settings)
        .parent()
        .and_then(|p| p.parent())
        .expect("root")
        .to_string_lossy()
        .into_owned()
}

static SEQ: AtomicUsize = AtomicUsize::new(0);

/// A new empty folder under /tmp (not TEST_TMPDIR: inside Bazel that sits
/// below an execroot whose MODULE.bazel would make "outside" look inside).
pub fn mkdtemp(prefix: &str) -> String {
    let base = if is_writable_dir("/tmp") {
        "/tmp".to_string()
    } else {
        std::env::temp_dir().to_string_lossy().into_owned()
    };
    let nanos = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.subsec_nanos())
        .unwrap_or(0);
    loop {
        let n = SEQ.fetch_add(1, Ordering::SeqCst);
        let p = format!(
            "{}/{}{}-{}-{:x}",
            base,
            prefix,
            std::process::id(),
            n,
            nanos
        );
        match std::fs::create_dir(&p) {
            Ok(()) => return p,
            Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => continue,
            Err(e) => panic!("mkdtemp {}: {}", p, e),
        }
    }
}

fn is_writable_dir(p: &str) -> bool {
    let probe = format!("{}/.agent-guard-probe-{}", p, std::process::id());
    let ok = std::fs::write(&probe, b"").is_ok();
    let _ = std::fs::remove_file(&probe);
    ok
}

pub fn realpath(p: &str) -> String {
    std::fs::canonicalize(p)
        .expect("realpath")
        .to_string_lossy()
        .into_owned()
}

pub fn join(a: &str, b: &str) -> String {
    Path::new(a).join(b).to_string_lossy().into_owned()
}

pub fn dirname(p: &str) -> String {
    Path::new(p)
        .parent()
        .map(|d| d.to_string_lossy().into_owned())
        .unwrap_or_default()
}

pub fn makedirs(p: &str) {
    std::fs::create_dir_all(p).unwrap_or_else(|e| panic!("mkdir {}: {}", p, e));
}

/// Write a file, creating its folder.
pub fn write(path: &str, text: &str) {
    makedirs(&dirname(path));
    std::fs::write(path, text).unwrap_or_else(|e| panic!("write {}: {}", path, e));
}

pub fn read(path: &str) -> String {
    std::fs::read_to_string(path).unwrap_or_else(|e| panic!("read {}: {}", path, e))
}

/// Removes a folder tree when dropped.
pub struct TempDir(pub String);

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

// --- git ----------------------------------------------------------------------

/// GIT_TEST_ENV: a fixed identity and no user or system config.
pub const GIT_TEST_ENV: [(&str, &str); 6] = [
    ("GIT_AUTHOR_NAME", "t"),
    ("GIT_AUTHOR_EMAIL", "t@e"),
    ("GIT_COMMITTER_NAME", "t"),
    ("GIT_COMMITTER_EMAIL", "t@e"),
    ("GIT_CONFIG_GLOBAL", "/dev/null"),
    ("GIT_CONFIG_NOSYSTEM", "1"),
];

/// `git -C dir args...` with GIT_TEST_ENV; panics on failure when `check`.
pub fn git(dir: &str, args: &[&str], check: bool) -> std::process::Output {
    let mut cmd = Command::new("git");
    cmd.arg("-C").arg(dir).args(args);
    for (k, v) in GIT_TEST_ENV {
        cmd.env(k, v);
    }
    let out = cmd.output().expect("run git");
    if check && !out.status.success() {
        panic!(
            "git {:?} in {} failed: {}",
            args,
            dir,
            String::from_utf8_lossy(&out.stderr)
        );
    }
    out
}

pub fn have_git() -> bool {
    Command::new("git")
        .arg("--version")
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false)
}

// --- JSON ---------------------------------------------------------------------

pub fn s(v: &str) -> PyVal {
    PyVal::Str(v.to_string())
}

pub fn int(v: i64) -> PyVal {
    PyVal::Int(v.to_string())
}

pub fn b(v: bool) -> PyVal {
    PyVal::Bool(v)
}

pub fn list(items: Vec<PyVal>) -> PyVal {
    PyVal::List(items)
}

pub fn obj(items: Vec<(&str, PyVal)>) -> PyVal {
    PyVal::Dict(items.into_iter().map(|(k, v)| (k.to_string(), v)).collect())
}

pub fn strs(items: &[&str]) -> PyVal {
    PyVal::List(items.iter().map(|x| s(x)).collect())
}

/// `dict(d, key=value)`: replaced where it is, or added at the end.
pub fn with_key(d: &PyVal, key: &str, value: PyVal) -> PyVal {
    let PyVal::Dict(items) = d else {
        panic!("not a dict: {}", d.py_repr())
    };
    let mut items = items.clone();
    match items.iter_mut().find(|(k, _)| k == key) {
        Some(slot) => slot.1 = value,
        None => items.push((key.to_string(), value)),
    }
    PyVal::Dict(items)
}

/// `{k: v for k, v in d.items() if k != key}`.
pub fn without_key(d: &PyVal, key: &str) -> PyVal {
    let PyVal::Dict(items) = d else {
        panic!("not a dict: {}", d.py_repr())
    };
    PyVal::Dict(items.iter().filter(|(k, _)| k != key).cloned().collect())
}

/// `d[key]`, panicking like a KeyError.
pub fn at<'a>(v: &'a PyVal, key: &str) -> &'a PyVal {
    v.get(key)
        .unwrap_or_else(|| panic!("KeyError {:?} in {}", key, v.py_repr()))
}

pub fn at_mut<'a>(v: &'a mut PyVal, key: &str) -> &'a mut PyVal {
    let repr = v.py_repr();
    match v {
        PyVal::Dict(items) => items
            .iter_mut()
            .find(|(k, _)| k == key)
            .map(|(_, v)| v)
            .unwrap_or_else(|| panic!("KeyError {:?} in {}", key, repr)),
        _ => panic!("not a dict: {}", repr),
    }
}

pub fn idx_mut(v: &mut PyVal, i: usize) -> &mut PyVal {
    match v {
        PyVal::List(items) => &mut items[i],
        other => panic!("not a list: {}", other.py_repr()),
    }
}

pub fn items(v: &PyVal) -> &[PyVal] {
    match v {
        PyVal::List(items) => items,
        other => panic!("not a list: {}", other.py_repr()),
    }
}

pub fn text(v: &PyVal) -> String {
    match v {
        PyVal::Str(x) => x.clone(),
        other => panic!("not a string: {}", other.py_repr()),
    }
}

/// `d[key]` as a string.
pub fn st(v: &PyVal, key: &str) -> String {
    text(at(v, key))
}

/// `d[key]` as a string, or None if the value is null.
pub fn opt_st(v: &PyVal, key: &str) -> Option<String> {
    match at(v, key) {
        PyVal::None => None,
        other => Some(text(other)),
    }
}

/// `json.dumps(value)`.
pub fn to_json(v: &PyVal) -> String {
    dumps(v, false)
}

/// `json.dumps(value, indent=n)`: Python's layout, as the files the user-file
/// tests edit by exact text are written with it.
pub fn to_json_indent(v: &PyVal, n: usize) -> String {
    fn go(v: &PyVal, n: usize, level: usize, out: &mut String) {
        let pad = |l: usize| " ".repeat(n * l);
        match v {
            PyVal::List(items) if !items.is_empty() => {
                out.push_str("[\n");
                for (i, item) in items.iter().enumerate() {
                    if i > 0 {
                        out.push_str(",\n");
                    }
                    out.push_str(&pad(level + 1));
                    go(item, n, level + 1, out);
                }
                out.push('\n');
                out.push_str(&pad(level));
                out.push(']');
            }
            PyVal::Dict(items) if !items.is_empty() => {
                out.push_str("{\n");
                for (i, (k, item)) in items.iter().enumerate() {
                    if i > 0 {
                        out.push_str(",\n");
                    }
                    out.push_str(&pad(level + 1));
                    dumps_str(k, out);
                    out.push_str(": ");
                    go(item, n, level + 1, out);
                }
                out.push('\n');
                out.push_str(&pad(level));
                out.push('}');
            }
            other => out.push_str(&dumps(other, false)),
        }
    }
    let mut out = String::new();
    go(v, n, 0, &mut out);
    out
}

pub fn from_json(t: &str) -> PyVal {
    loads(t).unwrap_or_else(|e| panic!("bad JSON ({:?}): {:.200}", e, t))
}

// --- The fake checkout --------------------------------------------------------

/// The git states the table's keys name.
pub fn git_states(repo: &str) -> HashMap<&'static str, GitState> {
    let conflicted = vec![join(&join(repo, "src"), "conflicted.go")];
    let base = GitState::default();
    let primary = GitState {
        primary: true,
        ..base.clone()
    };
    let mut m = HashMap::new();
    m.insert("", primary.clone());
    m.insert("primary", primary.clone());
    m.insert(
        "worktree",
        GitState {
            primary: false,
            ..base.clone()
        },
    );
    m.insert(
        "merging",
        GitState {
            merge: true,
            unmerged: conflicted.clone(),
            ..base.clone()
        },
    );
    m.insert(
        "rebasing",
        GitState {
            rebase: true,
            unmerged: conflicted.clone(),
            ..base.clone()
        },
    );
    m.insert(
        "picking",
        GitState {
            cherry_pick: true,
            unmerged: conflicted,
            ..base
        },
    );
    m.insert("out", primary);
    m
}

pub fn probe(state: GitState) -> Option<GitProbe> {
    Some(Box::new(move |_d: &str| state.clone()))
}

/// agent_guard_test.py's Fixture: {repo} a fake vitruvian-core checkout,
/// {wt} a linked worktree of it, {out} a folder outside it, {home} the HOME.
pub struct Fixture {
    pub tmp: String,
    pub home: String,
    pub repo: String,
    pub wt: String,
    pub out: String,
    pub states: HashMap<&'static str, GitState>,
}

impl Fixture {
    pub fn new() -> Self {
        let tmp = mkdtemp("agent-guard-test-");
        let home = join(&tmp, "home");
        let repo = join(&tmp, "vitruvian-core");
        let wt = join(&join(&tmp, "vitruvian-core-worktrees"), "feat-x");
        let out = join(&tmp, "elsewhere");
        for d in [&home, &out, &join(&repo, "src"), &wt] {
            std::fs::create_dir_all(d).unwrap();
        }
        for root in [&repo, &wt] {
            write(
                &join(root, "MODULE.bazel"),
                "module(\n    name = \"vitruvian_core\",\n)\n",
            );
            write(&join(root, "README.md"), "hi\n");
        }
        std::fs::create_dir(join(&repo, ".git")).unwrap();
        write(
            &join(&wt, ".git"),
            &format!("gitdir: {}/.git/worktrees/feat-x\n", repo),
        );
        write(&join(&join(&repo, "src"), "main.go"), "package main\n");
        let states = git_states(&repo);
        clear_caches();
        let fx = Fixture {
            tmp,
            home,
            repo,
            wt,
            out,
            states,
        };
        assert!(
            repo_root_of(&fx.out).is_none(),
            "fixture's outside dir {} is inside a vitruvian-core checkout",
            fx.out
        );
        fx
    }

    pub fn fmt(&self, t: &str) -> String {
        t.replace("{repo}", &self.repo)
            .replace("{wt}", &self.wt)
            .replace("{out}", &self.out)
            .replace("{home}", &self.home)
    }

    pub fn run_with(&self, command: &str, key: &str, modes: Option<&Modes>) -> Decision {
        let cwd = if key == "out" { &self.out } else { &self.repo };
        let state = self
            .states
            .get(key)
            .unwrap_or_else(|| panic!("no git state {:?}", key))
            .clone();
        evaluate(
            &self.fmt(command),
            cwd,
            modes,
            Some(&self.home),
            probe(state),
            true,
        )
    }

    pub fn run(&self, command: &str) -> Decision {
        self.run_with(command, "", None)
    }
}

impl Drop for Fixture {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.tmp);
    }
}

// --- The hook harness ---------------------------------------------------------

/// Runs hook::main on a payload with a private HOME and policy
/// (HookHarness). Holds the process lock for its whole life.
pub struct Harness {
    pub fx: Fixture,
    pub policy: String,
    pub env: EnvGuard,
    _lock: RwLockWriteGuard<'static, ()>,
}

impl Harness {
    pub fn new() -> Self {
        let lock = exclusive();
        let fx = Fixture::new();
        let policy = join(&fx.tmp, "policy.json");
        std::fs::copy(agent_guard::hook::default_policy_path(), &policy)
            .expect("copy the shipped policy");
        let mut env = EnvGuard::new();
        env.set("AGENT_GUARD_HOME", &fx.home);
        env.set("AGENT_GUARD_POLICY", &policy);
        Harness {
            fx,
            policy,
            env,
            _lock: lock,
        }
    }

    /// The hook's answer, or None if it printed nothing.
    pub fn hook(&self, payload: &PyVal) -> Option<PyVal> {
        let out = agent_guard::hook::main(&[], to_json(payload).as_bytes());
        assert_eq!(out.code, 0, "hook exited {}: {}", out.code, out.stderr);
        let t = out.stdout.trim();
        if t.is_empty() {
            None
        } else {
            Some(from_json(t))
        }
    }

    /// hookSpecificOutput.permissionDecision of a Claude Code answer.
    pub fn decision_of(&self, payload: &PyVal) -> String {
        let out = self
            .hook(payload)
            .unwrap_or_else(|| panic!("no answer for {}", payload.py_repr()));
        st(at(&out, "hookSpecificOutput"), "permissionDecision")
    }

    pub fn log(&self) -> Vec<PyVal> {
        read(&agent_guard::hook::log_path(&self.fx.home))
            .lines()
            .map(from_json)
            .collect()
    }

    pub fn last(&self) -> PyVal {
        self.log().pop().expect("an empty log")
    }

    /// The policy file with one category's mode changed.
    pub fn set_mode(&self, category: &str, mode: &str) {
        let mut p = from_json(&read(&self.policy));
        let entry = at_mut(at_mut(&mut p, "categories"), category);
        *at_mut(entry, "mode") = s(mode);
        std::fs::write(&self.policy, to_json(&p)).unwrap();
    }
}

/// A Claude Code payload: tool, cwd, tool_input.
pub fn claude(tool: &str, cwd: &str, tool_input: PyVal) -> PyVal {
    obj(vec![
        ("tool_name", s(tool)),
        ("cwd", s(cwd)),
        ("tool_input", tool_input),
    ])
}

pub fn bash(cwd: &str, command: &str) -> PyVal {
    claude("Bash", cwd, obj(vec![("command", s(command))]))
}
