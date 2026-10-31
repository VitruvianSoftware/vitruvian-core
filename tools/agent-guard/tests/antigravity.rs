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

//! AntigravityHookTest: agy's hook format end to end (decision JSON, the
//! location, the log). agy runs hooks in the folder holding hooks.json,
//! outside any repo, so each test runs from ~/.gemini/config.

use agent_guard::pyval::PyVal;

use crate::common::*;

const CONVERSATION: &str = "0f6c1d2e-3a4b-4c5d-8e9f-a0b1c2d3e4f5";

/// The PreToolUse payload agy 1.4.0 sends, captured live (paths faked). No
/// top-level cwd and no session_id: the directory is args.Cwd and the session
/// is conversationId.
fn agy_payload(
    command: Option<&str>,
    cwd: Option<&str>,
    workspace: Option<&[&str]>,
    tool: &str,
    args: Vec<(&str, PyVal)>,
) -> PyVal {
    let mut a: Vec<(String, PyVal)> = if tool == "run_command" {
        vec![
            ("CommandLine".into(), command.map(s).unwrap_or(PyVal::None)),
            ("Cwd".into(), cwd.map(s).unwrap_or(PyVal::None)),
            ("WaitMsBeforeAsync".into(), int(5000)),
            ("toolAction".into(), s("Running command")),
            ("toolSummary".into(), s("Run a command")),
        ]
    } else {
        vec![
            ("toolAction".into(), s("Doing it")),
            ("toolSummary".into(), s("Do it")),
        ]
    };
    for (k, v) in args {
        match a.iter_mut().find(|(have, _)| have == k) {
            Some(slot) => slot.1 = v,
            None => a.push((k.to_string(), v)),
        }
    }
    if cwd.is_none() {
        a.retain(|(k, _)| k != "Cwd");
    }
    let mut p = vec![
        (
            "toolCall",
            obj(vec![("name", s(tool)), ("args", PyVal::Dict(a))]),
        ),
        ("stepIdx", int(3)),
        ("conversationId", s(CONVERSATION)),
        (
            "transcriptPath",
            s("/fake/home/.gemini/antigravity-cli/brain/x/transcript.jsonl"),
        ),
        (
            "artifactDirectoryPath",
            s("/fake/home/.gemini/antigravity-cli/brain/x"),
        ),
        ("modelName", s("auto")),
    ];
    if let Some(w) = workspace {
        p.push(("workspacePaths", strs(w)));
    }
    obj(p)
}

fn run(command: &str, cwd: Option<&str>, workspace: Option<&[&str]>) -> PyVal {
    agy_payload(Some(command), cwd, workspace, "run_command", vec![])
}

fn tool(name: &str, workspace: Option<&[&str]>, args: Vec<(&str, PyVal)>) -> PyVal {
    agy_payload(None, None, workspace, name, args)
}

struct Agy {
    _cwd: CwdGuard,
    h: Harness,
}

impl Agy {
    fn new() -> Self {
        let h = Harness::new();
        let config = join(&h.fx.home, ".gemini/config");
        makedirs(&config);
        Agy {
            _cwd: CwdGuard::enter(&config),
            h,
        }
    }

    fn repo(&self) -> String {
        self.h.fx.repo.clone()
    }

    fn out(&self) -> String {
        self.h.fx.out.clone()
    }
}

#[test]
fn real_payload_go_vet_is_denied() {
    let t = Agy::new();
    let repo = t.repo();
    let out =
        t.h.hook(&run("go vet ./...", Some(&repo), Some(&[&repo])))
            .expect("an answer");
    let keys: Vec<String> = match &out {
        PyVal::Dict(items) => {
            let mut k: Vec<String> = items.iter().map(|(k, _)| k.clone()).collect();
            k.sort();
            k
        }
        other => panic!("{}", other.py_repr()),
    };
    assert_eq!(keys, vec!["decision", "reason"]);
    assert_eq!(st(&out, "decision"), "deny");
    assert!(st(&out, "reason").contains("bazel test"));
}

#[test]
fn real_payload_git_status_prints_nothing() {
    let t = Agy::new();
    let repo = t.repo();
    assert!(t
        .h
        .hook(&run("git status", Some(&repo), Some(&[&repo])))
        .is_none());
    assert_eq!(st(&t.h.last(), "decision"), "allow");
}

#[test]
fn log_names_the_directory_and_the_conversation() {
    let t = Agy::new();
    let repo = t.repo();
    t.h.hook(&run("go vet ./...", Some(&repo), Some(&[&repo])));
    let rec = t.h.last();
    assert_eq!(st(&rec, "agent"), "antigravity");
    assert_eq!(st(&rec, "tool"), "run_command");
    assert_eq!(st(&rec, "cwd"), repo);
    assert_eq!(st(&rec, "session"), CONVERSATION);
    assert_eq!(
        (st(&rec, "scope"), st(&rec, "decision")),
        ("inside".into(), "deny".into())
    );
}

#[test]
fn missing_cwd_falls_back_to_the_workspaces() {
    // Without the fallback the guard would judge ~/.gemini/config and allow.
    let t = Agy::new();
    let (repo, outside) = (t.repo(), t.out());
    let out =
        t.h.hook(&run("go vet ./...", None, Some(&[&repo, &outside])))
            .expect("an answer");
    assert_eq!(st(&out, "decision"), "deny");
    assert_eq!(st(&t.h.last(), "cwd"), repo);
    // Any workspace inside vitruvian-core puts the call inside, not just the first.
    let out =
        t.h.hook(&run("git push", None, Some(&["/tmp", &repo])))
            .expect("an answer");
    assert_eq!(st(&out, "decision"), "deny");
    assert!(st(&out, "reason").contains("//tools/git:push"));
    assert_eq!(st(&t.h.last(), "cwd"), repo);
    // No workspace inside: the first one decides.
    assert!(t
        .h
        .hook(&run("go vet ./...", None, Some(&[&outside, "/tmp"])))
        .is_none());
    let rec = t.h.last();
    assert_eq!(
        (st(&rec, "scope"), st(&rec, "cwd")),
        ("outside".into(), outside)
    );
}

#[test]
fn cwd_wins_over_workspace_paths() {
    let t = Agy::new();
    let (repo, outside) = (t.repo(), t.out());
    assert!(t
        .h
        .hook(&run("go vet ./...", Some(&outside), Some(&[&repo])))
        .is_none());
    let out =
        t.h.hook(&run("go vet ./...", Some(&repo), Some(&[&outside])))
            .expect("an answer");
    assert_eq!(st(&out, "decision"), "deny");
}

#[test]
fn no_location_at_all_is_enforced() {
    let t = Agy::new();
    let none: Option<&[&str]> = None;
    let empty: &[&str] = &[];
    let blank: &[&str] = &[""];
    for workspace in [none, Some(empty), Some(blank)] {
        let out =
            t.h.hook(&run("go vet ./...", None, workspace))
                .expect("an answer");
        assert_eq!(st(&out, "decision"), "deny", "{:?}", workspace);
        let rec = t.h.last();
        assert_eq!(
            (st(&rec, "scope"), st(&rec, "cwd")),
            ("unknown".into(), String::new()),
            "{:?}",
            workspace
        );
    }
    // Read-only commands still pass, and a gh call naming another repo is
    // still out of scope.
    assert!(t.h.hook(&run("git status", None, None)).is_none());
    assert!(t
        .h
        .hook(&run("gh pr merge 1 -R someone/else", None, None))
        .is_none());
}

#[test]
fn a_relative_cwd_is_unknown_not_the_hooks_folder() {
    let t = Agy::new();
    let out =
        t.h.hook(&run("go vet ./...", Some("some/dir"), None))
            .expect("an answer");
    assert_eq!(st(&out, "decision"), "deny");
    assert_eq!(st(&t.h.last(), "scope"), "unknown");
}

#[test]
fn other_command_tools() {
    let t = Agy::new();
    let (repo, outside) = (t.repo(), t.out());
    let cases: Vec<(&str, Vec<(&str, PyVal)>)> = vec![
        ("shell_exec", vec![("Command", s("go test ./..."))]),
        ("shell_exec", vec![("command", s("go test ./..."))]),
        (
            "send_command_input",
            vec![("Input", s("go test ./...")), ("CommandId", s("c1"))],
        ),
        (
            "manage_task",
            vec![
                ("Action", s("send_input")),
                ("TaskId", s("t1")),
                ("Input", s("go test ./...")),
            ],
        ),
    ];
    for (name, args) in cases {
        let out =
            t.h.hook(&tool(name, Some(&[&repo]), args.clone()))
                .expect("an answer");
        assert_eq!(st(&out, "decision"), "deny", "{}", name);
        assert_eq!(
            opt_st(&t.h.last(), "category").as_deref(),
            Some("go"),
            "{}",
            name
        );
        assert!(
            t.h.hook(&tool(name, Some(&[&outside]), args)).is_none(),
            "{}",
            name
        );
    }
    let before = t.h.log().len();
    assert!(t
        .h
        .hook(&tool(
            "manage_task",
            Some(&[&repo]),
            vec![("Action", s("kill")), ("TaskId", s("t1"))]
        ))
        .is_none());
    assert_eq!(t.h.log().len(), before);
}

#[test]
fn manage_task_send_input_as_captured() {
    // Captured live from agy 1.4.2 on 2026-10-17 (paths and ids faked): the
    // model started `cat` with run_command, then sent it a line. No Cwd, so
    // the workspace paths say where it runs.
    let t = Agy::new();
    let repo = t.repo();
    let payload = |input: &str| {
        obj(vec![
            (
                "toolCall",
                obj(vec![
                    ("name", s("manage_task")),
                    (
                        "args",
                        obj(vec![
                            ("Action", s("send_input")),
                            ("Input", s(input)),
                            ("TaskId", s("task-3")),
                            ("toolAction", s("Sending input to background cat process")),
                            ("toolSummary", s("Send input to cat")),
                        ]),
                    ),
                ]),
            ),
            ("stepIdx", int(2)),
            ("conversationId", s(CONVERSATION)),
            (
                "transcriptPath",
                s("/fake/home/.gemini/antigravity-cli/brain/x/transcript.jsonl"),
            ),
            (
                "artifactDirectoryPath",
                s("/fake/home/.gemini/antigravity-cli/brain/x"),
            ),
            ("modelName", s("auto")),
            ("workspacePaths", strs(&[&repo])),
        ])
    };
    assert!(t.h.hook(&payload("hello cat\n")).is_none());
    let out = t.h.hook(&payload("git push\n")).expect("an answer");
    assert_eq!(st(&out, "decision"), "deny");
    assert!(st(&out, "reason").contains("//tools/git:push"));
}

#[test]
fn git_commit_tool_is_a_commit() {
    let t = Agy::new();
    let (repo, outside) = (t.repo(), t.out());
    let args = || vec![("CommitMessage", s("fix things"))];
    let out =
        t.h.hook(&tool("git_commit", Some(&[&repo]), args()))
            .expect("an answer");
    assert_eq!(st(&out, "decision"), "deny");
    assert!(st(&out, "reason").contains("//tools/git:commit"));
    let rec = t.h.last();
    assert_eq!(
        (opt_st(&rec, "category"), st(&rec, "tool")),
        (Some("git-commit".into()), "git_commit".into())
    );
    assert!(st(&rec, "command").contains("fix things"));
    assert!(t
        .h
        .hook(&tool("git_commit", Some(&[&outside]), args()))
        .is_none());
    let out =
        t.h.hook(&tool("git_commit", None, args()))
            .expect("an answer");
    assert_eq!(st(&out, "decision"), "deny");
    assert_eq!(st(&t.h.last(), "scope"), "unknown");
}

#[test]
fn file_tools_cannot_touch_the_guard() {
    let t = Agy::new();
    let repo = t.repo();
    let guard = join(&t.h.fx.home, ".local/share/agent-guard/policy.json");
    let mine = join(&repo, "src/main.go");
    for (name, field) in [
        ("write_to_file", "TargetFile"),
        ("replace_file_content", "TargetFile"),
        ("multi_replace_file_content", "TargetFile"),
        ("notebook_edit", "NotebookPath"),
    ] {
        let out =
            t.h.hook(&tool(name, Some(&[&repo]), vec![(field, s(&guard))]))
                .expect("an answer");
        assert_eq!(st(&out, "decision"), "deny", "{}", name);
        assert_eq!(
            opt_st(&t.h.last(), "category").as_deref(),
            Some("guard-config"),
            "{}",
            name
        );
        assert!(
            t.h.hook(&tool(name, Some(&[&repo]), vec![(field, s(&mine))]))
                .is_none(),
            "{}",
            name
        );
    }
}

#[test]
fn file_tools_cannot_touch_the_hook_files() {
    let t = Agy::new();
    let repo = t.repo();
    for rel in [
        ".agents/hooks.json",
        ".claude/settings.json",
        "tools/agent-guard/hook.sh",
        "tools/remote/setup.sh",
    ] {
        let path = join(&repo, rel);
        let out =
            t.h.hook(&tool(
                "write_to_file",
                Some(&[&repo]),
                vec![("TargetFile", s(&path))],
            ))
            .expect("an answer");
        assert_eq!(st(&out, "decision"), "deny", "{}", rel);
        assert!(st(&out, "reason").contains("James's call"), "{}", rel);
    }
    // And through agy's shell, wherever the command says it runs.
    let out =
        t.h.hook(&run(
            "sed -i '' s/a/b/ tools/remote/setup.sh",
            Some(&repo),
            Some(&[&repo]),
        ))
        .expect("an answer");
    assert_eq!(st(&out, "decision"), "deny");
    assert!(st(&out, "reason").contains("session start"));
}

#[test]
fn warn_mode_prints_nothing() {
    let t = Agy::new();
    let repo = t.repo();
    t.h.set_mode("go", "warn");
    assert!(t.h.hook(&run("go vet ./...", Some(&repo), None)).is_none());
    assert_eq!(st(&t.h.last(), "decision"), "warn");
}
