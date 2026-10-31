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

//! install_test.py, ported: the per-user backstop against a temporary HOME
//! (install, migration from the old copied install, rollback, --uninstall),
//! an agent's install (checked, then logged), and --check against a
//! throwaway checkout wired like the real one. Same cases, same assertions;
//! the extra cases at the end cover what only the Rust port has.

use std::cell::RefCell;
use std::collections::BTreeMap;
use std::ffi::OsString;
use std::fs;

use agent_guard::paths::{exists, isdir, join};
use agent_guard::pyval::{loads, py_eq, s, PyVal};

use crate::installer::{self, agy_entry, backstop_command, backstop_main, claude_entries, is_ours};
use crate::pyjson::{dumps_indent, get_mut, set, PyErr};
use crate::sys::{Ctx, Sink};
use crate::testlib::{self, clean_env, git, read, tmpdir, write, Checkout};

/// The shape of James's real ~/.claude/settings.json hooks (commands shortened).
const EXISTING: &str = r#"{
  "effortLevel": "high",
  "permissions": {"allow": ["Bash"]},
  "hooks": {
    "PermissionRequest": [
      {"hooks": [{"type": "command", "command": "'/x/Tools/permission-hook'", "timeout": 150}]}
    ],
    "Stop": [
      {"hooks": [{"type": "command", "command": "/h/.claude/response-contract-stop.sh", "timeout": 10}]},
      {"hooks": [{"type": "command", "command": "\"/x/Tools/stop-hook\"", "timeout": 10}]}
    ],
    "UserPromptSubmit": [
      {"hooks": [{"type": "command", "command": "/h/.claude/response-contract.sh", "timeout": 5}]}
    ]
  },
  "remoteControlAtStartup": true
}"#;

/// ~/.gemini/config/hooks.json before agent-guard: one named, flat hook.
const EXISTING_GEMINI: &str = r#"{
  "response-contract": {
    "enabled": true,
    "PreInvocation": [
      {"type": "command", "command": "/h/.gemini/hooks/response-contract.py", "timeout": 5}
    ]
  }
}"#;

const ORIGIN: &str = "https://github.com/VitruvianSoftware/vitruvian-core.git";

fn existing() -> PyVal {
    loads(EXISTING).unwrap()
}

fn existing_gemini() -> PyVal {
    loads(EXISTING_GEMINI).unwrap()
}

/// `json.dump(v, fh, indent=2)`.
fn json_indent(v: &PyVal) -> String {
    dumps_indent(v, ": ", true)
}

fn load(path: &str) -> PyVal {
    loads(&read(path)).unwrap_or_else(|_| panic!("{} is not JSON", path))
}

#[track_caller]
fn assert_py_eq(a: &PyVal, b: &PyVal) {
    assert!(py_eq(a, b), "\n  {}\n!=\n  {}", a.py_repr(), b.py_repr());
}

fn list_of(v: Vec<PyVal>) -> PyVal {
    PyVal::List(v)
}

/// `len(glob.glob(path + ".agent-guard-*.bak"))`.
fn backups(path: &str) -> usize {
    let (dir, name) = agent_guard::paths::split(path);
    let prefix = format!("{}.agent-guard-", name);
    fs::read_dir(&dir)
        .map(|rd| {
            rd.flatten()
                .filter(|e| {
                    let n = e.file_name().to_string_lossy().into_owned();
                    n.starts_with(&prefix) && n.ends_with(".bak")
                })
                .count()
        })
        .unwrap_or(0)
}

/// What the retired installer left behind, written exactly as it wrote it.
fn old_install(home: &str) {
    let command = format!("/bin/sh {}/.local/share/agent-guard/hook.sh", home);
    let sp = join(home, ".claude/settings.json");
    let mut settings = load(&sp);
    let hooks = get_mut(&mut settings, "hooks").unwrap();
    if hooks.get("PreToolUse").is_none() {
        set(hooks, "PreToolUse", list_of(vec![]));
    }
    if let Some(PyVal::List(pre)) = get_mut(hooks, "PreToolUse") {
        pre.push(
            loads(&format!(
                r#"{{"matcher": {}, "hooks": [{{"type": "command", "command": {}, "timeout": 10, "onFailure": "block"}}]}}"#,
                agent_guard::pyval::dumps(&s(installer::COMMAND_MATCHER), false),
                agent_guard::pyval::dumps(&s(&command), false)
            ))
            .unwrap(),
        );
        pre.push(
            loads(&format!(
                r#"{{"matcher": {}, "hooks": [{{"type": "command", "command": {}, "timeout": 10}}]}}"#,
                agent_guard::pyval::dumps(&s(installer::FILE_MATCHER), false),
                agent_guard::pyval::dumps(&s(&command), false)
            ))
            .unwrap(),
        );
    }
    write(&sp, &(json_indent(&settings) + "\n"));
    let mut gemini = existing_gemini();
    set(&mut gemini, "agent-guard", agy_entry(&command));
    write(
        &join(home, ".gemini/config/hooks.json"),
        &(json_indent(&gemini) + "\n"),
    );
    let idir = join(home, ".local/share/agent-guard");
    fs::create_dir_all(&idir).unwrap();
    for name in [
        "agent_guard.py",
        "policy.json",
        "hook.py",
        "hook.sh",
        "VERSION.json",
    ] {
        write(&join(&idir, name), "# old copy\n");
    }
}

/// A temporary HOME holding EXISTING and EXISTING_GEMINI.
struct Base {
    home: String,
    settings: String,
    gemini: String,
    idir: String,
}

impl Base {
    fn new() -> Base {
        let home = tmpdir("agent-guard-home-");
        let b = Base {
            settings: join(&home, ".claude/settings.json"),
            gemini: join(&home, ".gemini/config/hooks.json"),
            idir: join(&home, ".local/share/agent-guard"),
            home,
        };
        write(&b.settings, &(json_indent(&existing()) + "\n"));
        write(&b.gemini, &(json_indent(&existing_gemini()) + "\n"));
        b
    }

    fn ctx(&self, env: BTreeMap<OsString, OsString>, running_from: &str) -> Ctx {
        Ctx {
            env,
            running_from: running_from.to_string(),
            sink: Sink::Buffer(RefCell::new(String::new())),
            write_hook: None,
        }
    }

    fn plain_ctx(&self, extra: &[(&str, &str)]) -> Ctx {
        let mut env = clean_env();
        for (k, v) in extra {
            env.insert((*k).into(), (*v).into());
        }
        self.ctx(env, "/nonexistent/install")
    }

    fn argv(&self, args: &[&str], workspace: &str) -> Vec<String> {
        let mut argv: Vec<String> = vec![
            "--home".into(),
            self.home.clone(),
            "--workspace".into(),
            workspace.into(),
        ];
        argv.extend(args.iter().map(|a| a.to_string()));
        argv
    }

    /// install.main(["--home", HOME, "--workspace", workspace, *args]): (rc, stdout+stderr).
    fn run_main(&self, args: &[&str], workspace: &str) -> (i32, String) {
        self.run_in(&self.plain_ctx(&[]), args, workspace)
    }

    fn run_in(&self, ctx: &Ctx, args: &[&str], workspace: &str) -> (i32, String) {
        let rc = installer::main(ctx, &self.argv(args, workspace));
        (rc, output(ctx))
    }

    fn texts(&self) -> (String, String) {
        (read(&self.settings), read(&self.gemini))
    }

    fn ours(&self) -> PyVal {
        let settings = load(&self.settings);
        let pre = settings
            .get("hooks")
            .and_then(|h| h.get("PreToolUse"))
            .cloned()
            .unwrap_or(list_of(vec![]));
        let PyVal::List(entries) = pre else {
            panic!("PreToolUse is not a list")
        };
        list_of(
            entries
                .into_iter()
                .filter(|e| match e.get("hooks") {
                    Some(PyVal::List(hs)) => hs.iter().any(is_ours),
                    _ => false,
                })
                .collect(),
        )
    }
}

impl Drop for Base {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.home);
    }
}

fn output(ctx: &Ctx) -> String {
    match &ctx.sink {
        Sink::Buffer(b) => b.borrow().clone(),
        Sink::Real => String::new(),
    }
}

fn contains(out: &str, needle: &str) -> bool {
    out.contains(needle)
}

#[track_caller]
fn assert_in(needle: &str, out: &str) {
    assert!(contains(out, needle), "{:?} not in:\n{}", needle, out);
}

// --- UninstallTest ------------------------------------------------------------

#[test]
fn uninstall_removes_both_entries_and_the_copy_and_keeps_everything_else() {
    let b = Base::new();
    old_install(&b.home);
    let (rc, out) = b.run_main(&["--uninstall"], "");
    assert_eq!(rc, 0, "{}", out);
    assert_py_eq(&load(&b.settings), &existing());
    assert_py_eq(&load(&b.gemini), &existing_gemini());
    assert!(!exists(&b.idir));
    assert_eq!(backups(&b.settings), 1);
    assert_eq!(backups(&b.gemini), 1);
    assert_in("sessions started anywhere else are not", &out);
}

#[test]
fn uninstall_twice_changes_nothing_more() {
    let b = Base::new();
    old_install(&b.home);
    b.run_main(&["--uninstall"], "");
    let before = b.texts();
    let (rc, out) = b.run_main(&["--uninstall"], "");
    assert_eq!(rc, 0);
    assert_in("no agent-guard hook to remove", &out);
    assert_in("no per-user copy", &out);
    assert_eq!(b.texts(), before);
}

#[test]
fn uninstall_keeps_the_log() {
    let b = Base::new();
    old_install(&b.home);
    let log = join(&b.home, ".local/state/agent-guard/log.jsonl");
    write(&log, "{}\n");
    b.run_main(&["--uninstall"], "");
    assert!(exists(&log));
}

#[test]
fn uninstall_dry_run_writes_nothing() {
    let b = Base::new();
    old_install(&b.home);
    let before = b.texts();
    let (rc, out) = b.run_main(&["--uninstall", "--dry-run"], "");
    assert_eq!(rc, 0);
    assert_in("would remove", &out);
    assert_in("+++", &out);
    assert_eq!(b.texts(), before);
    assert!(isdir(&b.idir));
}

#[test]
fn uninstall_trims_a_group_shared_with_another_hook() {
    let b = Base::new();
    old_install(&b.home);
    let other = loads(r#"{"type": "command", "command": "/x/other-guard.sh"}"#).unwrap();
    let mut settings = load(&b.settings);
    if let Some(PyVal::List(pre)) = get_mut(get_mut(&mut settings, "hooks").unwrap(), "PreToolUse")
    {
        for entry in pre.iter_mut() {
            if let Some(PyVal::List(hs)) = get_mut(entry, "hooks") {
                hs.push(other.clone());
            }
        }
    }
    write(&b.settings, &json_indent(&settings));
    let mut g = load(&b.gemini);
    if let Some(PyVal::List(pre)) = get_mut(get_mut(&mut g, "agent-guard").unwrap(), "PreToolUse") {
        if let Some(PyVal::List(hs)) = get_mut(&mut pre[0], "hooks") {
            hs.push(other.clone());
        }
    }
    write(&b.gemini, &json_indent(&g));
    b.run_main(&["--uninstall"], "");
    let settings = load(&b.settings);
    let PyVal::List(pre) = settings
        .get("hooks")
        .unwrap()
        .get("PreToolUse")
        .unwrap()
        .clone()
    else {
        panic!()
    };
    let hooks: Vec<PyVal> = pre
        .iter()
        .map(|e| e.get("hooks").unwrap().clone())
        .collect();
    assert_py_eq(
        &list_of(hooks),
        &list_of(vec![
            list_of(vec![other.clone()]),
            list_of(vec![other.clone()]),
        ]),
    );
    let g = load(&b.gemini);
    let PyVal::List(gpre) = g
        .get("agent-guard")
        .unwrap()
        .get("PreToolUse")
        .unwrap()
        .clone()
    else {
        panic!()
    };
    assert_py_eq(gpre[0].get("hooks").unwrap(), &list_of(vec![other]));
}

#[test]
fn uninstall_keeps_the_desktop_apps_json_style() {
    let b = Base::new();
    old_install(&b.home);
    let styled = dumps_indent(&load(&b.settings), " : ", true).replace('/', "\\/");
    write(&b.settings, &styled);
    b.run_main(&["--uninstall"], "");
    let text = read(&b.settings);
    assert_in("\" : ", &text);
    assert_in("\\/", &text);
    assert_py_eq(&loads(&text).unwrap(), &existing());
}

#[test]
fn uninstall_a_broken_hooks_json_does_not_block_the_claude_side() {
    let b = Base::new();
    old_install(&b.home);
    write(&b.gemini, "{broken");
    let (rc, out) = b.run_main(&["--uninstall"], "");
    assert_eq!(rc, 0, "{}", out);
    assert_py_eq(&load(&b.settings), &existing());
    assert_eq!(read(&b.gemini), "{broken");
}

#[test]
fn uninstall_refused_inside_an_agent_session() {
    let b = Base::new();
    old_install(&b.home);
    for marker in [
        "CLAUDECODE",
        "ANTIGRAVITY_AGENT",
        "GEMINI_CLI",
        "ANTIGRAVITY_LS_ADDRESS",
    ] {
        let (rc, out) = b.run_in(&b.plain_ctx(&[(marker, "1")]), &["--uninstall"], "");
        assert_eq!(rc, 2, "{}", marker);
        assert_in(marker, &out);
        let (rc, _) = b.run_in(
            &b.plain_ctx(&[(marker, "1")]),
            &["--uninstall", "--dry-run"],
            "",
        );
        assert_eq!(rc, 0, "{}", marker);
    }
    assert!(isdir(&b.idir));
}

// --- InstallTest: the thin backstop, user entries that run the MAIN checkout's hook.sh

struct Inst {
    b: Base,
    co: Checkout,
    command: String,
}

impl Inst {
    fn new() -> Inst {
        let b = Base::new();
        let co = Checkout::new();
        let command = backstop_command(&co.root).unwrap();
        Inst { b, co, command }
    }

    /// Run the backstop's command the way the agents do.
    fn backstop(&self, payload: &PyVal) -> (i32, String, String) {
        let out = std::process::Command::new("/bin/sh")
            .arg("-c")
            .arg(&self.command)
            .current_dir(&self.b.home)
            .env_clear()
            .envs(clean_env())
            .env("HOME", &self.b.home)
            .stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped())
            .spawn()
            .and_then(|mut child| {
                use std::io::Write;
                child
                    .stdin
                    .take()
                    .unwrap()
                    .write_all(agent_guard::pyval::dumps(payload, false).as_bytes())?;
                child.wait_with_output()
            })
            .unwrap();
        (
            out.status.code().unwrap_or(-1),
            String::from_utf8_lossy(&out.stdout).trim().to_string(),
            String::from_utf8_lossy(&out.stderr).into_owned(),
        )
    }
}

#[test]
fn install_writes_both_entries_pointing_at_the_main_checkout() {
    let t = Inst::new();
    let (rc, out) = t.b.run_main(&[], &t.co.root);
    assert_eq!(rc, 0, "{}", out);
    assert_py_eq(&t.b.ours(), &claude_entries(&t.command));
    assert_eq!(backstop_main(&t.command), t.co.root);
    assert_py_eq(
        load(&t.b.gemini).get("agent-guard").unwrap(),
        &agy_entry(&t.command),
    );
    // Everything else is kept.
    let settings = load(&t.b.settings);
    let want = existing();
    if let PyVal::Dict(items) = &want {
        for (k, v) in items {
            if k != "hooks" {
                assert_py_eq(settings.get(k).unwrap(), v);
            }
        }
    }
    if let Some(PyVal::Dict(events)) = want.get("hooks") {
        for (event, entries) in events {
            assert_py_eq(settings.get("hooks").unwrap().get(event).unwrap(), entries);
        }
    }
    assert_py_eq(
        load(&t.b.gemini).get("response-contract").unwrap(),
        existing_gemini().get("response-contract").unwrap(),
    );
    assert_in("reinstall only if you move", &out);
}

#[test]
fn install_migrates_the_old_copy() {
    let t = Inst::new();
    old_install(&t.b.home);
    let (rc, out) = t.b.run_main(&[], &t.co.root);
    assert_eq!(rc, 0, "{}", out);
    assert_py_eq(&t.b.ours(), &claude_entries(&t.command));
    assert!(!read(&t.b.settings).contains(".local/share/agent-guard"));
    assert!(!read(&t.b.gemini).contains(".local/share/agent-guard"));
    assert!(!exists(&t.b.idir));
    assert_eq!(backups(&t.b.settings), 1);
    assert_in("removed the old per-user copy", &out);
}

#[test]
fn install_from_a_worktree_it_still_points_at_the_main_checkout() {
    let t = Inst::new();
    let wt = join(&t.co.tmp, "wt");
    git(&t.co.root, &["worktree", "add", "-q", "--detach", &wt]);
    let (rc, out) = t.b.run_main(&[], &wt);
    assert_eq!(rc, 0, "{}", out);
    assert_py_eq(&t.b.ours(), &claude_entries(&t.command));
}

#[test]
fn install_a_write_error_puts_both_files_back() {
    let t = Inst::new();
    old_install(&t.b.home);
    let before = t.b.texts();
    let mut ctx = t.b.plain_ctx(&[]);
    let (gemini, old) = (t.b.gemini.clone(), before.1.clone());
    ctx.write_hook = Some(Box::new(move |path: &str, text: &str| {
        if path == gemini && text != old {
            Some("disk full".to_string())
        } else {
            None
        }
    }));
    let (rc, out) = t.b.run_in(&ctx, &[], &t.co.root);
    assert_eq!(rc, 4, "{}", out);
    assert_in("disk full", &out);
    assert_eq!(t.b.texts(), before);
    assert!(isdir(&t.b.idir));
}

#[test]
fn install_backstop_with_its_launcher_runs_the_guard() {
    let t = Inst::new();
    let (rc, out, err) = t.backstop(&testlib::claude("git stash", &t.co.root));
    assert_eq!(
        (rc, testlib::decision(&out, false).as_str()),
        (0, "deny"),
        "{}",
        err
    );
}

#[test]
fn install_backstop_without_its_launcher_refuses_only_vitruvian_core() {
    let t = Inst::new();
    fs::remove_file(join(&t.co.root, "tools/agent-guard/hook.sh")).unwrap();
    let wt = format!("{}-worktrees", t.co.root);
    for payload in [
        testlib::claude("ls", &t.co.root),
        testlib::claude("ls", &join(&t.co.root, "apps")),
        testlib::claude("ls", &join(&wt, "feat-x")),
        testlib::claude(&format!("cat {}/README.md", t.co.root), &t.b.home),
    ] {
        let (rc, out, err) = t.backstop(&payload);
        // Claude Code: exit 2 refuses the call, with stderr as the reason.
        assert_eq!((rc, out.as_str()), (2, ""), "{}", payload.py_repr());
        assert_in(&format!("launcher is missing from {}", t.co.root), &err);
        assert_in("James must reinstall", &err);
    }
    let (rc, out, _) = t.backstop(&testlib::agy("ls", &join(&t.co.root, "apps")));
    assert_eq!(rc, 0);
    let data = loads(&out).unwrap();
    assert_eq!(data.get("decision").and_then(|d| d.as_str()), Some("deny"));
    assert_in(
        "launcher is missing",
        data.get("reason").unwrap().as_str().unwrap(),
    );
    // Anything else, including a sibling folder with a longer name, goes through.
    for payload in [
        testlib::claude("ls", &t.b.home),
        testlib::claude("ls", &format!("{}-other", t.co.root)),
        testlib::agy("ls", &t.b.home),
    ] {
        let (rc, out, err) = t.backstop(&payload);
        assert_eq!((rc, out.as_str()), (0, ""), "{}", payload.py_repr());
        assert_in("allowing this call", &err);
    }
}

#[test]
fn install_idempotent() {
    let t = Inst::new();
    t.b.run_main(&[], &t.co.root);
    let before = t.b.texts();
    let (rc, out) = t.b.run_main(&[], &t.co.root);
    assert_eq!(rc, 0);
    assert_in("already installed", &out);
    assert_eq!(t.b.texts(), before);
    assert_eq!(backups(&t.b.settings), 1);
}

#[test]
fn install_dry_run_writes_nothing() {
    let t = Inst::new();
    old_install(&t.b.home);
    let before = t.b.texts();
    let (rc, out) = t.b.run_main(&["--dry-run"], &t.co.root);
    assert_eq!(rc, 0);
    assert_in("+++", &out);
    assert_in("would remove the old per-user copy", &out);
    assert_eq!(t.b.texts(), before);
    assert!(isdir(&t.b.idir));
}

#[test]
fn install_a_failing_self_test_puts_everything_back() {
    let t = Inst::new();
    old_install(&t.b.home);
    t.co.write(
        "tools/agent-guard/hook.sh",
        &testlib::launcher_text(&["/nonexistent/stand-in".into()]),
    );
    let before = t.b.texts();
    let (rc, out) = t.b.run_main(&[], &t.co.root);
    assert_eq!(rc, 4, "{}", out);
    assert_in(testlib::live_flavor().nothing_ran(), &out);
    assert_eq!(t.b.texts(), before);
    assert!(isdir(&t.b.idir));
}

#[test]
fn install_antigravity_absent_is_left_alone() {
    let t = Inst::new();
    fs::remove_dir_all(join(&t.b.home, ".gemini")).unwrap();
    let (rc, out) = t.b.run_main(&[], &t.co.root);
    assert_eq!(rc, 0, "{}", out);
    assert!(!exists(&join(&t.b.home, ".gemini")));
    assert_py_eq(&t.b.ours(), &claude_entries(&t.command));
}

#[test]
fn install_a_main_checkout_without_the_launcher_is_refused() {
    let t = Inst::new();
    fs::remove_file(join(&t.co.root, "tools/agent-guard/hook.sh")).unwrap();
    // install.py raises SystemExit here; main() prints it and exits 1.
    let ctx = t.b.plain_ctx(&[]);
    match installer::main_inner(&ctx, &t.b.argv(&[], &t.co.root)) {
        Err(PyErr::Exit(msg)) => assert_in("pull main there first", &msg),
        other => panic!("expected SystemExit, got {:?}", other),
    }
    let (rc, out) = t.b.run_main(&[], &t.co.root);
    assert_eq!(rc, 1);
    assert_in("pull main there first", &out);
}

#[test]
fn install_an_agent_may_not_aim_it_with_home_or_workspace() {
    let t = Inst::new();
    let ctx = t.b.plain_ctx(&[("CLAUDECODE", "1")]);
    let (rc, out) = t.b.run_in(&ctx, &[], &t.co.root);
    assert_eq!(rc, 2);
    assert_in("--home/--workspace", &out);
    assert_in("CLAUDECODE", &out);
    let (rc, _) = t.b.run_in(
        &t.b.plain_ctx(&[("CLAUDECODE", "1")]),
        &["--dry-run"],
        &t.co.root,
    );
    assert_eq!(rc, 0);
    assert_py_eq(&t.b.ours(), &list_of(vec![]));
}

#[test]
fn install_uninstall_removes_the_backstop() {
    let t = Inst::new();
    t.b.run_main(&[], &t.co.root);
    let (rc, out) = t.b.run_main(&["--uninstall"], "");
    assert_eq!(rc, 0, "{}", out);
    assert_py_eq(&load(&t.b.settings), &existing());
    assert_py_eq(&load(&t.b.gemini), &existing_gemini());
    assert_in("sessions started anywhere else are not", &out);
}

#[test]
fn install_mode_is_gone() {
    let b = Base::new();
    let (rc, out) = b.run_main(&["--mode", "git-push=warn"], "");
    assert_eq!(rc, 2);
    assert_in("policy.json", &out);
}

// --- AgentInstallTest: an agent's install, from the real HOME (here a temp
// one) and the checkout `bazel run` ran in; checked, then logged.

/// Give a fake checkout the installer's own files and a GitHub origin, all on origin/main.
fn installable(co: Checkout) -> Checkout {
    co.write(
        "tools/agent-guard/install/main.rs",
        "// the installer's crate root\n",
    );
    co.write("tools/agent-guard/BUILD", "# the installer's BUILD\n");
    co.commit_to_main("installer");
    git(&co.root, &["remote", "add", "origin", ORIGIN]);
    co
}

/// Where `bazel run //tools/agent-guard:install` runs the binary from.
fn bazel_built(tmp: &str, target: &str) -> String {
    join(
        tmp,
        &format!(
            "execroot/_main/bazel-out/darwin_arm64-fastbuild/bin/tools/agent-guard/{}",
            target
        ),
    )
}

struct Agent {
    b: Base,
    co: Checkout,
    command: String,
}

impl Agent {
    fn new() -> Agent {
        let b = Base::new();
        let co = installable(Checkout::new());
        let command = backstop_command(&co.root).unwrap();
        agent_guard::scope::clear_caches();
        Agent { b, co, command }
    }

    fn env(&self, workspace: &str, marker: &str) -> BTreeMap<OsString, OsString> {
        let mut env = clean_env();
        for (k, v) in [
            ("HOME", self.b.home.as_str()),
            ("BUILD_WORKSPACE_DIRECTORY", workspace),
            ("CLAUDE_CODE_SESSION_ID", "session-under-test"),
            (marker, "1"),
        ] {
            env.insert(k.into(), v.into());
        }
        env
    }

    /// install.main(args) as `bazel run` would start it from workspace, in an agent session.
    fn run(
        &self,
        args: &[&str],
        workspace: &str,
        marker: &str,
        running_from: Option<&str>,
    ) -> (i32, String) {
        let exe = running_from
            .map(|r| r.to_string())
            .unwrap_or_else(|| bazel_built(&self.co.tmp, "install"));
        let ctx = self.b.ctx(self.env(workspace, marker), &exe);
        let argv: Vec<String> = args.iter().map(|a| a.to_string()).collect();
        let rc = installer::main(&ctx, &argv);
        (rc, output(&ctx))
    }

    fn agent(&self, args: &[&str]) -> (i32, String) {
        self.run(args, &self.co.root, "CLAUDECODE", None)
    }

    fn agent_in(&self, args: &[&str], workspace: &str) -> (i32, String) {
        self.run(args, workspace, "CLAUDECODE", None)
    }

    /// The agent-install lines in agent-guard's log.
    fn installs(&self) -> Vec<PyVal> {
        let path = join(&self.b.home, ".local/state/agent-guard/log.jsonl");
        if !exists(&path) {
            return Vec::new();
        }
        read(&path)
            .lines()
            .map(|l| loads(l).unwrap())
            .filter(|r| r.get("event").and_then(|e| e.as_str()) == Some("agent-install"))
            .collect()
    }

    #[track_caller]
    fn assert_refused(&self, rc: i32, out: &str, needle: &str) {
        assert_eq!(rc, 2, "{}", out);
        assert_in(needle, out);
        assert_in("CLAUDECODE", out);
        assert_py_eq(&self.b.ours(), &list_of(vec![]));
        assert_py_eq(&load(&self.b.settings), &existing());
        assert_py_eq(&load(&self.b.gemini), &existing_gemini());
        let installs = self.installs();
        let last = installs.last().expect("a logged install");
        assert_eq!(
            last.get("outcome").and_then(|v| v.as_str()),
            Some("refused")
        );
        assert_eq!(last.get("decision").and_then(|v| v.as_str()), Some("deny"));
        assert_in(needle, last.get("reason").and_then(|v| v.as_str()).unwrap());
    }
}

fn field<'a>(rec: &'a PyVal, key: &str) -> &'a str {
    rec.get(key).and_then(|v| v.as_str()).unwrap_or("<missing>")
}

#[test]
fn agent_installs_when_the_main_checkout_matches_origin_main() {
    let t = Agent::new();
    let (rc, out) = t.agent(&[]);
    assert_eq!(rc, 0, "{}", out);
    assert_py_eq(&t.b.ours(), &claude_entries(&t.command));
    assert_py_eq(
        load(&t.b.gemini).get("agent-guard").unwrap(),
        &agy_entry(&t.command),
    );
    let settings = load(&t.b.settings);
    if let Some(PyVal::Dict(events)) = existing().get("hooks") {
        for (event, entries) in events {
            assert_py_eq(settings.get("hooks").unwrap().get(event).unwrap(), entries);
        }
    }
    assert_eq!(backups(&t.b.settings), 1);
    let installs = t.installs();
    assert_eq!(installs.len(), 1);
    let rec = &installs[0];
    assert_eq!(
        ["outcome", "decision", "main", "marker", "session"].map(|k| field(rec, k).to_string()),
        [
            "installed",
            "allow",
            t.co.root.as_str(),
            "CLAUDECODE=1",
            "session-under-test"
        ]
        .map(|v| v.to_string())
    );
    assert_eq!(field(rec, "agent"), "claude-code");
    // Again: nothing changes, and it is logged again.
    let before = t.b.texts();
    let (rc, out) = t.agent(&[]);
    assert_eq!(rc, 0, "{}", out);
    assert_in("already installed", &out);
    assert_eq!(t.b.texts(), before);
    assert_eq!(t.installs().len(), 2);
}

#[test]
fn agent_from_a_worktree_it_installs_for_the_main_checkout() {
    let t = Agent::new();
    let wt = join(&t.co.tmp, "vitruvian-core-worktrees/feat-x");
    git(&t.co.root, &["worktree", "add", "-q", "--detach", &wt]);
    let (rc, out) = t.agent_in(&[], &wt);
    assert_eq!(rc, 0, "{}", out);
    assert_py_eq(&t.b.ours(), &claude_entries(&t.command));
}

#[test]
fn agent_an_antigravity_marker_is_logged_as_antigravity() {
    let t = Agent::new();
    let (rc, out) = t.run(&[], &t.co.root, "ANTIGRAVITY_AGENT", None);
    assert_eq!(rc, 0, "{}", out);
    let installs = t.installs();
    let rec = installs.last().unwrap();
    assert_eq!(
        (field(rec, "agent"), field(rec, "marker")),
        ("antigravity", "ANTIGRAVITY_AGENT=1")
    );
}

#[test]
fn agent_refused_when_hook_sh_differs_from_origin_main() {
    let t = Agent::new();
    t.co.append("tools/agent-guard/hook.sh", "# an unreviewed local edit\n");
    let (rc, out) = t.agent(&[]);
    t.assert_refused(rc, &out, "tools/agent-guard/hook.sh in the main checkout");
}

/// A clean worktree of t's checkout, so the guard's own check (the checkout
/// the installer runs from) passes and the installer's check of the main
/// checkout is the one that decides.
fn clean_worktree(t: &Agent) -> String {
    let wt = join(&t.co.tmp, "vitruvian-core-worktrees/feat-x");
    git(&t.co.root, &["worktree", "add", "-q", "--detach", &wt]);
    wt
}

#[test]
fn agent_refused_when_the_guard_differs_from_origin_main() {
    let t = Agent::new();
    let wt = clean_worktree(&t);
    t.co.append(
        "tools/agent-guard/src/lib.rs",
        "// an unreviewed local edit\n",
    );
    let (rc, out) = t.agent_in(&[], &wt);
    t.assert_refused(
        rc,
        &out,
        &format!(
            "tools/agent-guard/src/lib.rs in the main checkout {} differs",
            t.co.root
        ),
    );
}

#[test]
fn agent_refused_when_the_checkout_adds_a_guard_file() {
    let t = Agent::new();
    let wt = clean_worktree(&t);
    t.co.write("tools/agent-guard/src/extra.rs", "// not on main\n");
    let (rc, out) = t.agent_in(&[], &wt);
    t.assert_refused(
        rc,
        &out,
        &format!(
            "tools/agent-guard/src/extra.rs in the main checkout {} differs",
            t.co.root
        ),
    );
}

#[test]
fn agent_refused_when_main_has_no_guard() {
    let t = Agent::new();
    git(&t.co.root, &["rm", "-rq", "tools/agent-guard/src"]);
    git(&t.co.root, &["commit", "-qm", "drop", "--no-gpg-sign"]);
    git(
        &t.co.root,
        &["update-ref", "refs/remotes/origin/main", "HEAD"],
    );
    let (rc, out) = t.agent(&[]);
    t.assert_refused(rc, &out, "has no origin/main:tools/agent-guard/src");
}

#[test]
fn agent_refused_when_a_local_commit_is_ahead_of_origin_main() {
    let t = Agent::new();
    t.co.append("tools/agent-guard/hook.sh", "# committed, never merged\n");
    git(&t.co.root, &["commit", "-qam", "local", "--no-gpg-sign"]);
    let (rc, out) = t.agent(&[]);
    t.assert_refused(rc, &out, "differs from origin/main's");
}

#[test]
fn agent_refused_without_origin_main() {
    let t = Agent::new();
    git(
        &t.co.root,
        &["update-ref", "-d", "refs/remotes/origin/main"],
    );
    let (rc, out) = t.agent(&[]);
    t.assert_refused(rc, &out, "origin/main or its installer cannot be read");
}

#[test]
fn agent_refused_outside_any_checkout() {
    let t = Agent::new();
    let (rc, out) = t.agent_in(&[], &t.co.out);
    t.assert_refused(rc, &out, "vitruvian-core checkout");
}

#[test]
fn agent_refused_for_a_repo_that_is_not_vitruvian_core() {
    let t = Agent::new();
    t.co.write("MODULE.bazel", "module(name = \"something_else\")\n");
    t.co.commit_to_main("not vitruvian-core");
    let (rc, out) = t.agent(&[]);
    t.assert_refused(rc, &out, "not run from inside a vitruvian-core checkout");
}

#[test]
fn agent_refused_when_origin_is_not_vitruvian_core() {
    let t = Agent::new();
    for url in [
        "https://github.com/someone/vitruvian-core.git",
        "/tmp/a-local-fake",
    ] {
        git(&t.co.root, &["remote", "set-url", "origin", url]);
        let (rc, out) = t.agent(&[]);
        t.assert_refused(rc, &out, "not github.com/VitruvianSoftware/vitruvian-core");
    }
}

#[test]
fn agent_refused_while_the_old_copy_is_installed() {
    let t = Agent::new();
    old_install(&t.b.home);
    let before = t.b.texts();
    let (rc, out) = t.agent(&[]);
    assert_eq!(rc, 2, "{}", out);
    assert_in("the first switch from it is James's", &out);
    assert_eq!(t.b.texts(), before);
    assert!(isdir(&t.b.idir));
    assert_eq!(field(t.installs().last().unwrap(), "outcome"), "refused");
}

#[test]
fn agent_refused_to_move_the_backstop_to_another_checkout() {
    let t = Agent::new();
    let other = installable(Checkout::new());
    let (rc, out) = t.agent_in(&[], &other.root);
    assert_eq!(rc, 0, "{}", out);
    let before = read(&t.b.settings);
    let (rc, out) = t.agent_in(&[], &t.co.root);
    assert_eq!(rc, 2, "{}", out);
    assert_in("moving it is James's", &out);
    assert_eq!(read(&t.b.settings), before);
}

#[test]
fn agent_an_edited_installer_in_a_worktree_is_refused() {
    let t = Agent::new();
    let wt = join(&t.co.tmp, "vitruvian-core-worktrees/feat-x");
    git(&t.co.root, &["worktree", "add", "-q", "--detach", &wt]);
    let main_rs = join(&wt, "tools/agent-guard/install/main.rs");
    write(&main_rs, &(read(&main_rs) + "// an agent's own edit\n"));
    let (rc, out) = t.agent_in(&[], &wt);
    t.assert_refused(
        rc,
        &out,
        &format!("tools/agent-guard/install/main.rs in {} differs", wt),
    );
}

#[test]
fn agent_refused_unless_run_from_bazels_runfiles() {
    let t = Agent::new();
    // Run directly, not as the binary Bazel built for :install.
    let direct = join(&t.co.root, "tools/agent-guard/install");
    let (rc, out) = t.run(&[], &t.co.root, "CLAUDECODE", Some(&direct));
    t.assert_refused(
        rc,
        &out,
        "is not the one `bazel run //tools/agent-guard:install` builds",
    );
    // Bazel-built, but another target's binary.
    let other = bazel_built(&t.co.tmp, "agent-guard");
    let (rc, out) = t.run(&[], &t.co.root, "CLAUDECODE", Some(&other));
    t.assert_refused(rc, &out, "is not the one");
}

#[test]
fn agent_uninstall_and_mode_are_refused() {
    let t = Agent::new();
    let (rc, out) = t.agent(&[]);
    assert_eq!(rc, 0, "{}", out);
    let installed = t.b.texts();
    let (rc, out) = t.agent(&["--uninstall"]);
    assert_eq!(rc, 2);
    assert_in("Removing the backstop is James's job", &out);
    let (rc, _) = t.agent(&["--mode", "git-push=off"]);
    assert_eq!(rc, 2);
    assert_eq!(t.b.texts(), installed);
}

#[test]
fn agent_dry_run_and_check_still_work_and_say_whether_an_agent_may_install() {
    let t = Agent::new();
    let (rc, out) = t.agent(&["--dry-run"]);
    assert_eq!(rc, 0, "{}", out);
    assert_in("an agent may run this install: yes", &out);
    assert_py_eq(&t.b.ours(), &list_of(vec![]));
    t.co.append("tools/agent-guard/hook.sh", "# edit\n");
    let (_, out) = t.agent(&["--dry-run"]);
    assert_in("an agent may run this install: no, ", &out);
    let (rc, out) = t.agent(&["--check"]);
    assert_eq!(rc, 1, "{}", out); // no backstop yet
    assert_in("(an agent may)", &out);
}

// --- CheckTest ------------------------------------------------------------------

struct Chk {
    b: Base,
    co: Checkout,
}

impl Chk {
    fn new() -> Chk {
        let b = Base::new();
        let co = Checkout::new();
        let (rc, out) = b.run_main(&[], &co.root);
        assert_eq!(rc, 0, "{}", out);
        Chk { b, co }
    }

    fn check(&self) -> (i32, String) {
        self.b.run_main(&["--check"], &self.co.root)
    }
}

#[test]
fn check_passes_with_the_repo_wired_and_the_backstop_installed() {
    let t = Chk::new();
    let (rc, out) = t.check();
    assert_eq!(rc, 0, "{}", out);
    assert_in("origin/main:", &out);
    assert_in("backstop runs", &out);
}

#[test]
fn check_fails_without_the_backstop() {
    let t = Chk::new();
    t.b.run_main(&["--uninstall"], "");
    let (rc, out) = t.check();
    assert_eq!(rc, 1);
    assert_in("unguarded", &out);
}

#[test]
fn check_fails_while_the_old_copy_is_installed() {
    let t = Chk::new();
    t.b.run_main(&["--uninstall"], "");
    old_install(&t.b.home);
    let (rc, out) = t.check();
    assert_eq!(rc, 1);
    assert_in("to migrate", &out);
}

#[test]
fn check_fails_when_the_main_checkout_moved() {
    let t = Chk::new();
    {
        let other = Checkout::new();
        t.b.run_main(&[], &other.root); // the backstop now points at `other`...
    } // ...which is then deleted
    let (rc, out) = t.check();
    assert_eq!(rc, 1);
    assert_in("did the main checkout move?", &out);
}

#[test]
fn check_says_when_the_working_copy_answered() {
    let t = Chk::new();
    git(
        &t.co.root,
        &["update-ref", "-d", "refs/remotes/origin/main"],
    );
    let (rc, out) = t.check();
    assert_eq!(rc, 0, "{}", out);
    assert_in("working-copy (no origin/main", &out);
}

#[test]
fn check_fails_when_an_entry_is_removed() {
    let t = Chk::new();
    let path = join(&t.co.root, ".claude/settings.json");
    let mut settings = load(&path);
    if let Some(PyVal::List(pre)) = get_mut(get_mut(&mut settings, "hooks").unwrap(), "PreToolUse")
    {
        pre.truncate(2);
    }
    write(&path, &agent_guard::pyval::dumps(&settings, false));
    let (rc, out) = t.check();
    assert_eq!(rc, 1);
    assert_in(".claude/settings.json", &out);
    fs::remove_file(join(&t.co.root, ".agents/hooks.json")).unwrap();
    let (_, out) = t.check();
    assert_in(".agents/hooks.json is missing", &out);
}

#[test]
fn check_fails_when_the_launcher_does_not_work() {
    let t = Chk::new();
    t.co.write(
        "tools/agent-guard/hook.sh",
        &testlib::launcher_text(&["/nonexistent/stand-in".into()]),
    );
    // The Rust launcher reuses the guard it built at install time: without
    // that, nothing it tries can build one.
    let cache = join(&t.b.home, ".local/state/agent-guard/cache");
    if exists(&cache) {
        fs::remove_dir_all(&cache).unwrap();
    }
    let (rc, out) = t.check();
    assert_eq!(rc, 1);
    assert_in(testlib::live_flavor().nothing_ran(), &out);
}

#[test]
fn check_fails_when_the_guard_lets_things_through() {
    let t = Chk::new();
    t.co.set_policy(&[("go", "off")], true);
    let (rc, out) = t.check();
    assert_eq!(rc, 1);
    assert_in("go vet", &out);
}

#[test]
fn check_needs_a_checkout() {
    let b = Base::new();
    let (rc, _) = b.run_main(&["--check"], "");
    assert_eq!(rc, 2);
}

// --- Beyond install_test.py -----------------------------------------------------

/// The repo's own hook files, as they are, carry exactly the entries the installer expects.
#[test]
fn the_repos_hook_files_are_wired_as_the_installer_expects() {
    let root = testlib::runfile("tools/agent-guard/hook.sh");
    let root = root.trim_end_matches("/tools/agent-guard/hook.sh");
    assert_eq!(installer::check_wiring(root).unwrap(), Vec::<String>::new());
}

/// A Bazel run from one checkout may not vouch for another (the Rust
/// runfiles check: BUILD_WORKSPACE_DIRECTORY must be the workspace).
#[test]
fn agent_dry_run_for_another_checkout_says_an_agent_may_not() {
    let t = Agent::new();
    let other = installable(Checkout::new());
    let (rc, out) = t.agent(&["--dry-run", "--workspace", &other.root]);
    assert_eq!(rc, 0, "{}", out);
    assert_in("an agent may run this install: no, this installer (", &out);
    assert_in(&format!("builds from {}", other.root), &out);
}

#[test]
fn invalid_json_is_refused_with_pythons_message_and_nothing_changes() {
    let t = Inst::new();
    write(&t.b.settings, "{broken");
    let (rc, out) = t.b.run_main(&[], &t.co.root);
    assert_eq!(rc, 1);
    assert_eq!(
        out,
        format!(
            "agent-guard: {} is not valid JSON (Expecting property name enclosed in double quotes: \
line 1 column 2 (char 1)); fix it first, nothing was changed\n",
            t.b.settings
        )
    );
    assert_eq!(read(&t.b.settings), "{broken");
}

/// Install then uninstall puts the file back byte for byte, in either JSON style.
#[test]
fn install_and_uninstall_round_trip_byte_for_byte() {
    let t = Inst::new();
    let mut desktop = existing();
    set(&mut desktop, "url", s("https://example.com/x"));
    for text in [
        json_indent(&existing()) + "\n",
        dumps_indent(&desktop, " : ", false).replace('/', "\\/"),
    ] {
        write(&t.b.settings, &text);
        let (rc, out) = t.b.run_main(&[], &t.co.root);
        assert_eq!(rc, 0, "{}", out);
        assert_ne!(read(&t.b.settings), text);
        let (rc, out) = t.b.run_main(&["--uninstall"], "");
        assert_eq!(rc, 0, "{}", out);
        assert_eq!(read(&t.b.settings), text);
    }
}

#[test]
fn usage_errors_and_abbreviations_are_argparses() {
    let b = Base::new();
    let (rc, out) = b.run_main(&["--bogus"], "");
    assert_eq!(rc, 2);
    assert!(
        out.starts_with("usage: bazel run //tools/agent-guard:install -- [-h]"),
        "{}",
        out
    );
    assert!(
        out.ends_with(
            "bazel run //tools/agent-guard:install --: error: unrecognized arguments: --bogus\n"
        ),
        "{}",
        out
    );
    let (rc, out) = b.run_main(&["--h"], "");
    assert_eq!(rc, 2);
    assert_in(
        "error: ambiguous option: --h could match --help, --home",
        &out,
    );
    let (rc, out) = b.run_main(&["--uninst", "--dry"], "");
    assert_eq!(rc, 0, "{}", out);
    assert_in("no per-user copy at", &out);
    let (rc, out) = b.run_main(&["--help"], "");
    assert_eq!(rc, 0);
    assert_in(
        "  --dry-run    print what would change, write nothing\n",
        &out,
    );
}

/// install.py crashes (AttributeError) on a settings file whose "hooks" is
/// not an object; the port fails the same way, before writing anything.
#[test]
fn a_hooks_value_that_is_not_an_object_fails_like_python() {
    let t = Inst::new();
    write(&t.b.settings, "{\"hooks\": null}\n");
    let (rc, out) = t.b.run_main(&[], &t.co.root);
    assert_eq!(rc, 1);
    assert_in(
        "AttributeError: 'NoneType' object has no attribute 'setdefault'",
        &out,
    );
    assert_eq!(read(&t.b.settings), "{\"hooks\": null}\n");
}
