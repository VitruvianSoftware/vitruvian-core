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

//! HookIOTest: hook::main end to end on Claude Code's and Antigravity's
//! payloads, with a private HOME and policy: what it prints, and the log.

use std::os::unix::fs::PermissionsExt;

use agent_guard::guard::DC;
use agent_guard::hook::{log_path, main};

use crate::common::*;

fn mode_of(path: &str) -> u32 {
    std::fs::metadata(path).unwrap().permissions().mode() & 0o777
}

#[test]
fn deny_uses_the_pretooluse_protocol_and_logs() {
    let h = Harness::new();
    let out = h
        .hook(&obj(vec![
            ("tool_name", s("Bash")),
            ("cwd", s(&h.fx.repo)),
            ("session_id", s("s1")),
            (
                "tool_input",
                obj(vec![(
                    "command",
                    s("GH_TOKEN=ghs_abcdefghijklmnopqrstuvwxyz0123 git push"),
                )]),
            ),
        ]))
        .expect("an answer");
    let hso = at(&out, "hookSpecificOutput");
    assert_eq!(st(hso, "hookEventName"), "PreToolUse");
    assert_eq!(st(hso, "permissionDecision"), "deny");
    assert!(st(hso, "permissionDecisionReason").contains("//tools/git:push"));
    let rec = h.last();
    assert_eq!(
        (
            st(&rec, "decision"),
            opt_st(&rec, "category"),
            st(&rec, "scope")
        ),
        ("deny".into(), Some("git-push".into()), "inside".into())
    );
    assert!(
        !st(&rec, "command").contains("ghs_"),
        "{}",
        st(&rec, "command")
    );
    for key in ["ts", "cwd", "category", "decision", "command"] {
        assert!(rec.has(key), "{} missing from {}", key, rec.py_repr());
    }
}

#[test]
fn allow_prints_nothing_and_logs() {
    let h = Harness::new();
    assert!(h.hook(&bash(&h.fx.repo, "git status")).is_none());
    assert_eq!(st(&h.last(), "decision"), "allow");
}

#[test]
fn outside_is_allowed_and_logged() {
    let h = Harness::new();
    assert!(h.hook(&bash(&h.fx.out, "git push")).is_none());
    let rec = h.last();
    assert_eq!(
        (st(&rec, "decision"), st(&rec, "scope")),
        ("allow".into(), "outside".into())
    );
}

#[test]
fn long_commands_are_truncated() {
    let h = Harness::new();
    h.hook(&bash(&h.fx.repo, &format!("echo {}", "x".repeat(5000))));
    assert!(st(&h.last(), "command").chars().count() < 1100);
}

#[test]
fn warn_mode_adds_context() {
    let h = Harness::new();
    h.set_mode("git-push", "warn");
    let out = h.hook(&bash(&h.fx.repo, "git push")).expect("an answer");
    let hso = at(&out, "hookSpecificOutput");
    assert!(!hso.has("permissionDecision"), "{}", hso.py_repr());
    assert!(st(hso, "additionalContext").contains("warn mode"));
    assert_eq!(st(&h.last(), "decision"), "warn");
}

#[test]
fn terminal_panel_uses_its_own_cwd() {
    let h = Harness::new();
    let p = claude(
        "mcp__terminal__run_in_terminal",
        &h.fx.out,
        obj(vec![("command", s("git push")), ("cwd", s(&h.fx.repo))]),
    );
    assert_eq!(h.decision_of(&p), "deny");
}

#[test]
fn monitor_and_desktop_commander() {
    let h = Harness::new();
    for (tool, field) in [
        ("Monitor", "command"),
        (
            "mcp__plugin_desktop-commander_desktop-commander__start_process",
            "command",
        ),
        (
            "mcp__plugin_desktop-commander_desktop-commander__interact_with_process",
            "input",
        ),
    ] {
        let p = claude(tool, &h.fx.repo, obj(vec![(field, s("go test ./..."))]));
        assert_eq!(h.decision_of(&p), "deny", "{}", tool);
    }
}

#[test]
fn auto_merge_tool() {
    let h = Harness::new();
    let url = "https://github.com/VitruvianSoftware/vitruvian-core/pull/1";
    let tool = "mcp__ccd_pr__set_auto_merge";
    let p = claude(
        tool,
        &h.fx.out,
        obj(vec![("enabled", b(true)), ("url", s(url))]),
    );
    assert_eq!(h.decision_of(&p), "deny");
    let p = claude(
        tool,
        &h.fx.out,
        obj(vec![("enabled", b(false)), ("url", s(url))]),
    );
    assert!(h.hook(&p).is_none());
    let p = claude(
        tool,
        &h.fx.out,
        obj(vec![
            ("enabled", b(true)),
            ("url", s("https://github.com/x/other/pull/1")),
        ]),
    );
    assert!(h.hook(&p).is_none());
}

#[test]
fn kubernetes_mcp() {
    let h = Harness::new();
    let repo = h.fx.repo.clone();
    let p = claude(
        "mcp__kubernetes__kubectl_apply",
        &repo,
        obj(vec![("manifest", s("x"))]),
    );
    assert_eq!(h.decision_of(&p), "deny");
    let p = claude(
        "mcp__kubernetes__kubectl_generic",
        &repo,
        obj(vec![
            ("command", s("rollout")),
            ("subCommand", s("restart")),
        ]),
    );
    assert_eq!(h.decision_of(&p), "deny");
    let p = claude(
        "mcp__kubernetes__kubectl_generic",
        &repo,
        obj(vec![("command", s("get"))]),
    );
    assert!(h.hook(&p).is_none());
    let p = claude(
        "mcp__kubernetes__kubectl_rollout",
        &repo,
        obj(vec![("subCommand", s("status"))]),
    );
    assert!(h.hook(&p).is_none());
}

#[test]
fn log_is_private() {
    let h = Harness::new();
    h.hook(&bash(&h.fx.repo, "git status"));
    let path = log_path(&h.fx.home);
    let dir = dirname(&path);
    assert_eq!(mode_of(&dir), 0o700);
    assert_eq!(mode_of(&path), 0o600);
    // An existing loose directory and file are tightened.
    std::fs::set_permissions(&dir, std::fs::Permissions::from_mode(0o755)).unwrap();
    std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o644)).unwrap();
    h.hook(&bash(&h.fx.repo, "git status"));
    assert_eq!(mode_of(&dir), 0o700);
    assert_eq!(mode_of(&path), 0o600);
}

#[test]
fn desktop_commander_cannot_touch_the_session_start_scripts() {
    let h = Harness::new();
    for rel in ["tools/remote/setup.sh"] {
        let path = join(&h.fx.repo, rel);
        for (tool, tin) in [
            (
                "write_file",
                obj(vec![("path", s(&path)), ("content", s("exit 0"))]),
            ),
            (
                "edit_block",
                obj(vec![
                    ("file_path", s(&path)),
                    ("old_string", s("a")),
                    ("new_string", s("b")),
                ]),
            ),
            (
                "move_file",
                obj(vec![("source", s(&path)), ("destination", s("/tmp/x"))]),
            ),
            (
                "move_file",
                obj(vec![("source", s("/tmp/x")), ("destination", s(&path))]),
            ),
        ] {
            let p = claude(&format!("{}{}", DC, tool), &h.fx.repo, tin);
            assert_eq!(h.decision_of(&p), "deny", "{} {}", tool, rel);
            assert_eq!(
                opt_st(&h.last(), "category").as_deref(),
                Some("guard-config")
            );
        }
        // A shell write through Desktop Commander's process tools too.
        let p = claude(
            &format!("{}start_process", DC),
            &h.fx.repo,
            obj(vec![("command", s(&format!("echo 'exit 0' > {}", path)))]),
        );
        assert_eq!(h.decision_of(&p), "deny");
    }
}

#[test]
fn desktop_commander_file_tools_cannot_touch_the_guard() {
    let h = Harness::new();
    let guard = join(&h.fx.home, ".local/share/agent-guard");
    let g = |rest: &str| s(&format!("{}{}", guard, rest));
    for (tool, tin) in [
        (
            "write_file",
            obj(vec![("path", g("/policy.json")), ("content", s("{}"))]),
        ),
        (
            "edit_block",
            obj(vec![
                ("file_path", g("/agent_guard.py")),
                ("old_string", s("a")),
                ("new_string", s("b")),
            ]),
        ),
        (
            "move_file",
            obj(vec![
                ("source", s("/tmp/x")),
                ("destination", g("/hook.py")),
            ]),
        ),
        (
            "move_file",
            obj(vec![
                ("source", g("/hook.py")),
                ("destination", s("/tmp/x")),
            ]),
        ),
        ("create_directory", obj(vec![("path", g("/sub"))])),
        (
            "write_pdf",
            obj(vec![
                ("path", s("/tmp/a.pdf")),
                ("content", s("x")),
                ("outputPath", g("/x.pdf")),
            ]),
        ),
    ] {
        let p = claude(&format!("{}{}", DC, tool), &h.fx.out, tin);
        assert_eq!(h.decision_of(&p), "deny", "{}", tool);
    }
    let p = claude(
        &format!("{}write_file", DC),
        &h.fx.repo,
        obj(vec![
            ("path", s(&join(&h.fx.repo, "x.txt"))),
            ("content", s("x")),
        ]),
    );
    assert!(h.hook(&p).is_none());
}

#[test]
fn file_tools_cannot_edit_the_installed_guard() {
    let h = Harness::new();
    let target = join(&h.fx.home, ".local/share/agent-guard/policy.json");
    let p = claude(
        "Write",
        &h.fx.out,
        obj(vec![("file_path", s(&target)), ("content", s("{}"))]),
    );
    assert_eq!(h.decision_of(&p), "deny");
    let p = claude(
        "Edit",
        &h.fx.repo,
        obj(vec![(
            "file_path",
            s(&join(&h.fx.repo, "tools/agent-guard/policy.json")),
        )]),
    );
    assert!(h.hook(&p).is_none());
}

#[test]
fn file_tools_cannot_touch_the_hook_files() {
    let h = Harness::new();
    for tool in ["Write", "Edit", "MultiEdit"] {
        for rel in [
            ".claude/settings.json",
            ".claude/settings.local.json",
            ".claude/block-queue-bypass.sh",
            ".claude/session-start.sh",
            ".agents/hooks.json",
            "tools/agent-guard/hook.sh",
            "tools/remote/setup.sh",
        ] {
            for root in [h.fx.repo.clone(), h.fx.wt.clone()] {
                let p = claude(tool, &root, obj(vec![("file_path", s(&join(&root, rel)))]));
                assert_eq!(h.decision_of(&p), "deny", "{} {}", tool, rel);
            }
        }
        // Relative paths count too, and the log names the file.
        let p = claude(
            tool,
            &h.fx.repo,
            obj(vec![("file_path", s(".agents/hooks.json"))]),
        );
        assert_eq!(h.decision_of(&p), "deny");
        assert_eq!(
            opt_st(&h.last(), "category").as_deref(),
            Some("guard-config")
        );
    }
    // The guard's source and policy are fine to edit: they only take effect
    // once merged, because hook.sh runs origin/main's copy.
    for rel in [
        "tools/agent-guard/agent_guard.py",
        "tools/agent-guard/policy.json",
        ".claude/notes.md",
        "tools/cloud-bootstrap/cloud-bootstrap_test.sh",
        "tools/cloud-bootstrap/README.md",
        "tools/remote/setup_test.sh",
    ] {
        let p = claude(
            "Edit",
            &h.fx.repo,
            obj(vec![("file_path", s(&join(&h.fx.repo, rel)))]),
        );
        assert!(h.hook(&p).is_none(), "{}", rel);
    }
    // Outside a vitruvian-core checkout the same names are someone else's.
    let p = claude(
        "Write",
        &h.fx.out,
        obj(vec![(
            "file_path",
            s(&join(&h.fx.out, ".claude/settings.json")),
        )]),
    );
    assert!(h.hook(&p).is_none());
}

#[test]
fn log_records_which_copy_decided() {
    let mut h = Harness::new();
    h.env.set("AGENT_GUARD_SOURCE", "origin/main:abc");
    h.hook(&bash(&h.fx.repo, "git status"));
    h.env.remove("AGENT_GUARD_SOURCE");
    assert_eq!(st(&h.last(), "source"), "origin/main:abc");
    h.hook(&bash(&h.fx.repo, "git status"));
    assert_eq!(st(&h.last(), "source"), "");
}

#[test]
fn antigravity_format() {
    let h = Harness::new();
    let agy = |cmd: &str| {
        obj(vec![(
            "toolCall",
            obj(vec![
                ("name", s("run_command")),
                (
                    "args",
                    obj(vec![("CommandLine", s(cmd)), ("Cwd", s(&h.fx.repo))]),
                ),
            ]),
        )])
    };
    let out = h.hook(&agy("git stash")).expect("an answer");
    assert_eq!(st(&out, "decision"), "deny");
    assert!(st(&out, "reason").contains("stash"));
    assert!(h.hook(&agy("git status")).is_none());
    assert_eq!(st(&h.last(), "agent"), "antigravity");
}

#[test]
fn garbage_input_is_allowed() {
    let _h = Harness::new();
    let out = main(&[], b"not json");
    assert_eq!(out.code, 0);
    assert_eq!(out.stdout, "");
}
