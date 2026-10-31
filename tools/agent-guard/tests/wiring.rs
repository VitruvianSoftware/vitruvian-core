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

//! WiringTest (hook_test.py): the repo's own .claude/settings.json and
//! .agents/hooks.json, read from the runfiles; the test fails if agent-guard
//! is unwired from either. What the files must say is spelled out here (it
//! was install.py's claude_entries() / agy_entry() / check_wiring(); the Rust
//! installer is a binary the tests cannot link, so the check is ported).

use std::path::Path;

use agent_guard::guard::{command_fields, file_tool_fields, AGY_GIT_COMMIT, AGY_MANAGE_TASK, DC};
use agent_guard::pyval::{loads, py_eq, PyVal};

use crate::common::*;

pub const CLAUDE_COMMAND: &str = "/bin/sh \"$CLAUDE_PROJECT_DIR/tools/agent-guard/hook.sh\"";
pub const AGY_COMMAND: &str = "/bin/sh ../tools/agent-guard/hook.sh";
const CLAUDE_SETTINGS_REL: &str = ".claude/settings.json";
const AGY_HOOKS_REL: &str = ".agents/hooks.json";
const LAUNCHER_REL: &str = "tools/agent-guard/hook.sh";
const AGY_HOOK_NAME: &str = "agent-guard";
const HOOK_TIMEOUT: i64 = 10;

fn command_matcher() -> String {
    format!(
        "^(Bash|Monitor|mcp__terminal__run_in_terminal|{}(start_process|interact_with_process)\
|mcp__ccd_pr__set_auto_merge\
|mcp__(kubernetes|Kubernetes_MCP_Server)__(kubectl_(apply|create|delete|patch|scale|rollout|generic)\
|exec_in_pod|(install|upgrade|uninstall)_helm_chart|node_management))$",
        DC
    )
}

fn file_matcher() -> String {
    format!(
        "^(Edit|Write|MultiEdit|NotebookEdit|{}(write_file|edit_block|move_file|create_directory|write_pdf))$",
        DC
    )
}

pub const AGY_MATCHER: &str = "run_command|shell_exec|send_command_input|manage_task|git_commit\
|write_to_file|replace_file_content|multi_replace_file_content|notebook_edit";

/// Every tool agent_guard reads a command or a file path from (agent_guard.py's
/// COMMAND_FIELDS and FILE_TOOLS).
fn guard_tools() -> Vec<String> {
    let mut t: Vec<String> = [
        "Bash",
        "Monitor",
        "mcp__terminal__run_in_terminal",
        "run_command",
        "shell_exec",
        "send_command_input",
        "Edit",
        "Write",
        "MultiEdit",
        "NotebookEdit",
        "write_to_file",
        "replace_file_content",
        "multi_replace_file_content",
        "notebook_edit",
    ]
    .iter()
    .map(|x| x.to_string())
    .collect();
    for dc in [
        "start_process",
        "interact_with_process",
        "write_file",
        "edit_block",
        "move_file",
        "create_directory",
        "write_pdf",
    ] {
        t.push(format!("{}{}", DC, dc));
    }
    t
}

/// agent-guard's two PreToolUse entries.
pub fn claude_entries() -> PyVal {
    list(vec![
        obj(vec![
            ("matcher", s(&command_matcher())),
            (
                "hooks",
                list(vec![obj(vec![
                    ("type", s("command")),
                    ("command", s(CLAUDE_COMMAND)),
                    ("timeout", int(HOOK_TIMEOUT)),
                    ("onFailure", s("block")),
                ])]),
            ),
        ]),
        obj(vec![
            ("matcher", s(&file_matcher())),
            (
                "hooks",
                list(vec![obj(vec![
                    ("type", s("command")),
                    ("command", s(CLAUDE_COMMAND)),
                    ("timeout", int(HOOK_TIMEOUT)),
                ])]),
            ),
        ]),
    ])
}

/// agent-guard's named hook for agy, in the grouped shape PreToolUse needs.
pub fn agy_entry() -> PyVal {
    obj(vec![
        ("enabled", b(true)),
        (
            "PreToolUse",
            list(vec![obj(vec![
                ("matcher", s(AGY_MATCHER)),
                (
                    "hooks",
                    list(vec![obj(vec![
                        ("type", s("command")),
                        ("command", s(AGY_COMMAND)),
                        ("timeout", int(HOOK_TIMEOUT)),
                    ])]),
                ),
            ])]),
        ),
    ])
}

/// MARKER_RE: `agent-guard/(agent_guard\.py|hook\.py|hook\.sh)`.
fn is_ours(handler: &PyVal) -> bool {
    match handler {
        PyVal::Dict(_) => {
            let c = handler
                .get("command")
                .map(|c| c.py_str())
                .unwrap_or_default();
            [
                "agent-guard/agent_guard.py",
                "agent-guard/hook.py",
                "agent-guard/hook.sh",
            ]
            .iter()
            .any(|m| c.contains(m))
        }
        _ => false,
    }
}

/// install.py's read_settings: {} for a missing or blank file, an error for
/// one that is not a JSON object.
fn read_settings(path: &str) -> Result<PyVal, String> {
    if !Path::new(path).exists() {
        return Ok(obj(vec![]));
    }
    let t = read(path);
    if t.trim().is_empty() {
        return Ok(obj(vec![]));
    }
    match loads(&t) {
        Ok(v) if v.is_dict() => Ok(v),
        Ok(_) => Err(format!("{} is not a JSON object", path)),
        Err(e) => Err(format!("{} is not valid JSON ({:?})", path, e)),
    }
}

/// Problems with agent-guard's entries in a checkout's two hook files.
pub fn check_wiring(workspace: &str) -> Vec<String> {
    let mut problems = Vec::new();
    let path = join(workspace, CLAUDE_SETTINGS_REL);
    let settings = read_settings(&path).unwrap_or_else(|e| {
        problems.push(e);
        obj(vec![])
    });
    if !matches!(settings.get("disableAllHooks"), Some(PyVal::Bool(false))) {
        problems.push(format!("{}: \"disableAllHooks\": false is missing", path));
    }
    let hooks = settings.get("hooks").filter(|h| h.is_dict());
    let entries: &[PyVal] = match hooks.and_then(|h| h.get("PreToolUse")) {
        Some(PyVal::List(e)) => e,
        _ => &[],
    };
    let ours: Vec<PyVal> = entries
        .iter()
        .filter(|e| match e.get("hooks") {
            Some(PyVal::List(hs)) => hs.iter().any(is_ours),
            _ => false,
        })
        .cloned()
        .collect();
    if !py_eq(&PyVal::List(ours), &claude_entries()) {
        problems.push(format!(
            "{}: agent-guard's two PreToolUse entries are missing or differ (want {})",
            path,
            to_json(&claude_entries())
        ));
    }
    let path = join(workspace, AGY_HOOKS_REL);
    let hooks_json = read_settings(&path).unwrap_or_else(|e| {
        problems.push(e);
        obj(vec![])
    });
    if !Path::new(&path).exists() {
        problems.push(format!("{} is missing", path));
    } else if !hooks_json
        .get(AGY_HOOK_NAME)
        .map_or(false, |v| py_eq(v, &agy_entry()))
    {
        problems.push(format!(
            "{}: the {:?} hook is missing or differs (want {})",
            path,
            AGY_HOOK_NAME,
            to_json(&agy_entry())
        ));
    }
    let launcher = join(workspace, LAUNCHER_REL);
    if !Path::new(&launcher).is_file() {
        problems.push(format!("{} is missing", launcher));
    }
    problems
}

// --- A matcher for the hook matchers -------------------------------------------
// They use only literals, groups, `|` and the two anchors; anything else is
// refused rather than guessed at.

enum Node {
    Lit(char),
    Start,
    End,
    Group(Vec<Vec<Node>>),
}

fn parse_alt(t: &[char], i: &mut usize) -> Vec<Vec<Node>> {
    let mut alts = vec![Vec::new()];
    while *i < t.len() {
        let c = t[*i];
        *i += 1;
        match c {
            '|' => alts.push(Vec::new()),
            ')' => return alts,
            '(' => {
                let g = parse_alt(t, i);
                alts.last_mut().unwrap().push(Node::Group(g));
            }
            '^' => alts.last_mut().unwrap().push(Node::Start),
            '$' => alts.last_mut().unwrap().push(Node::End),
            c if c.is_ascii_alphanumeric() || c == '_' || c == '-' => {
                alts.last_mut().unwrap().push(Node::Lit(c))
            }
            c => panic!("matcher uses {:?}, which this test does not understand", c),
        }
    }
    alts
}

/// Every end position `seq` can reach from `i`.
fn ends(seq: &[Node], t: &[char], i: usize) -> Vec<usize> {
    let Some((first, rest)) = seq.split_first() else {
        return vec![i];
    };
    let next: Vec<usize> = match first {
        Node::Lit(c) => {
            if t.get(i) == Some(c) {
                vec![i + 1]
            } else {
                vec![]
            }
        }
        Node::Start => {
            if i == 0 {
                vec![i]
            } else {
                vec![]
            }
        }
        Node::End => {
            if i == t.len() {
                vec![i]
            } else {
                vec![]
            }
        }
        Node::Group(alts) => alts.iter().flat_map(|a| ends(a, t, i)).collect(),
    };
    next.into_iter().flat_map(|j| ends(rest, t, j)).collect()
}

/// `re.match(pattern, name)`: anchored at the start.
fn re_match(pattern: &str, name: &str) -> bool {
    let p: Vec<char> = pattern.chars().collect();
    let mut i = 0;
    let alts = parse_alt(&p, &mut i);
    assert_eq!(i, p.len(), "unbalanced matcher {}", pattern);
    let t: Vec<char> = name.chars().collect();
    alts.iter().any(|a| !ends(a, &t, 0).is_empty())
}

// --- The tests -------------------------------------------------------------------

fn load(rel: &str) -> PyVal {
    from_json(&read(&join(&repo_files_root(), rel)))
}

#[test]
fn the_matcher_matcher_works() {
    let _l = shared();
    let m = command_matcher();
    assert!(re_match(&m, "Bash"));
    assert!(re_match(&m, "mcp__kubernetes__kubectl_apply"));
    assert!(re_match(
        &m,
        "mcp__Kubernetes_MCP_Server__upgrade_helm_chart"
    ));
    assert!(!re_match(&m, "Bashx"));
    assert!(!re_match(&m, "xBash"));
    assert!(!re_match(&m, "mcp__kubernetes__kubectl_get"));
    assert!(!re_match(&file_matcher(), "Read"));
    assert!(
        re_match("a|b", "bc"),
        "re.match is not a full match without $"
    );
}

#[test]
fn the_repo_is_wired() {
    let _l = shared();
    assert_eq!(check_wiring(&repo_files_root()), Vec::<String>::new());
}

#[test]
fn claude_entries_are_there_and_only_commands_fail_closed() {
    let _l = shared();
    let settings = load(".claude/settings.json");
    let entries = items(at(at(&settings, "hooks"), "PreToolUse"));
    let ours: Vec<PyVal> = entries
        .iter()
        .filter(|e| to_json(e).contains("agent-guard"))
        .cloned()
        .collect();
    assert!(
        py_eq(&PyVal::List(ours.clone()), &claude_entries()),
        "{}",
        to_json(&PyVal::List(ours.clone()))
    );
    let hook0 = &items(at(&ours[0], "hooks"))[0];
    assert_eq!(st(hook0, "onFailure"), "block");
    let hook1 = &items(at(&ours[1], "hooks"))[0];
    assert!(!hook1.has("onFailure"), "{}", hook1.py_repr());
    for e in &ours {
        assert_eq!(st(&items(at(e, "hooks"))[0], "command"), CLAUDE_COMMAND);
    }
}

#[test]
fn disable_all_hooks_is_pinned_false() {
    // Project settings outrank user settings, so this keeps a user-level
    // `"disableAllHooks": true` from switching the guard off in the repo.
    let _l = shared();
    assert!(matches!(
        load(".claude/settings.json").get("disableAllHooks"),
        Some(PyVal::Bool(false))
    ));
}

#[test]
fn block_queue_bypass_is_kept() {
    let _l = shared();
    let settings = load(".claude/settings.json");
    assert!(to_json(at(at(&settings, "hooks"), "PreToolUse")).contains("block-queue-bypass.sh"));
}

#[test]
fn agy_entry_is_grouped_and_runs_from_dot_agents() {
    let _l = shared();
    let hooks = load(".agents/hooks.json");
    let spec = at(&hooks, "agent-guard");
    assert!(at(spec, "enabled").truthy());
    let group = &items(at(spec, "PreToolUse"))[0];
    assert_eq!(st(group, "matcher"), AGY_MATCHER);
    assert_eq!(st(&items(at(group, "hooks"))[0], "command"), AGY_COMMAND);
    assert!(Path::new(&join(
        &repo_files_root(),
        ".agents/../tools/agent-guard/hook.sh"
    ))
    .is_file());
}

#[test]
fn matchers_cover_every_tool_the_guard_reads() {
    let _l = shared();
    let tools = guard_tools();
    // The list is the guard's: each is a tool it reads, and others are not.
    for t in &tools {
        assert!(
            command_fields(t).is_some() || file_tool_fields(t).is_some(),
            "{} is not a tool the guard reads",
            t
        );
    }
    assert!(command_fields("Read").is_none() && file_tool_fields("Read").is_none());
    let claude_tools = tools
        .iter()
        .filter(|t| !t.starts_with(|c: char| c.is_lowercase()) || t.starts_with("mcp__"));
    for t in claude_tools {
        assert!(
            re_match(&command_matcher(), t) || re_match(&file_matcher(), t),
            "{}",
            t
        );
    }
    let mut agy_tools: Vec<String> = tools
        .iter()
        .filter(|t| t.starts_with(|c: char| c.is_lowercase()) && !t.starts_with("mcp__"))
        .cloned()
        .collect();
    agy_tools.push(AGY_MANAGE_TASK.into());
    agy_tools.push(AGY_GIT_COMMIT.into());
    let agy: Vec<&str> = AGY_MATCHER.split('|').collect();
    for t in &agy_tools {
        assert!(agy.contains(&t.as_str()), "{}", t);
    }
}

#[test]
fn unwiring_either_file_is_caught() {
    let _l = shared();
    let root = repo_files_root();
    let tmp = TempDir(mkdtemp("agent-guard-wiring-"));
    let dir = tmp.0.clone();
    let fresh = || {
        let _ = std::fs::remove_dir_all(&dir);
        for rel in [CLAUDE_SETTINGS_REL, AGY_HOOKS_REL, LAUNCHER_REL] {
            write(&join(&dir, rel), &read(&join(&root, rel)));
        }
        assert_eq!(check_wiring(&dir), Vec::<String>::new());
    };
    let edit = |rel: &str, change: &dyn Fn(&mut PyVal)| {
        let path = join(&dir, rel);
        let mut data = from_json(&read(&path));
        change(&mut data);
        std::fs::write(&path, to_json(&data)).unwrap();
    };
    fn pre(d: &mut PyVal) -> &mut PyVal {
        at_mut(at_mut(d, "hooks"), "PreToolUse")
    }
    fn drop_at(d: &mut PyVal, i: usize) {
        match pre(d) {
            PyVal::List(l) => {
                l.remove(i);
            }
            other => panic!("{}", other.py_repr()),
        }
    }
    fn pop_key(d: &mut PyVal, key: &str) {
        match d {
            PyVal::Dict(items) => {
                let n = items.len();
                items.retain(|(k, _)| k != key);
                assert_eq!(items.len(), n - 1, "no {} to drop", key);
            }
            other => panic!("{}", other.py_repr()),
        }
    }
    let claude_mutations: Vec<(&str, Box<dyn Fn(&mut PyVal)>)> = vec![
        ("command-tool entry removed", Box::new(|d| drop_at(d, 1))),
        ("file-tool entry removed", Box::new(|d| drop_at(d, 2))),
        (
            "onFailure dropped",
            Box::new(|d| {
                let h = idx_mut(at_mut(idx_mut(pre(d), 1), "hooks"), 0);
                pop_key(h, "onFailure")
            }),
        ),
        (
            "matcher narrowed",
            Box::new(|d| *at_mut(idx_mut(pre(d), 1), "matcher") = s("Bash")),
        ),
        ("all hooks removed", Box::new(|d| pop_key(d, "hooks"))),
        (
            "disableAllHooks dropped",
            Box::new(|d| pop_key(d, "disableAllHooks")),
        ),
        (
            "disableAllHooks true",
            Box::new(|d| *at_mut(d, "disableAllHooks") = b(true)),
        ),
    ];
    for (name, change) in &claude_mutations {
        fresh();
        edit(CLAUDE_SETTINGS_REL, change.as_ref());
        assert_ne!(check_wiring(&dir), Vec::<String>::new(), "{}", name);
    }
    let agy_mutations: Vec<(&str, Box<dyn Fn(&mut PyVal)>)> = vec![
        ("entry removed", Box::new(|d| pop_key(d, "agent-guard"))),
        (
            "disabled",
            Box::new(|d| *at_mut(at_mut(d, "agent-guard"), "enabled") = b(false)),
        ),
        (
            "flat shape (agy ignores it)",
            Box::new(|d| {
                *at_mut(at_mut(d, "agent-guard"), "PreToolUse") = list(vec![obj(vec![
                    ("matcher", s(AGY_MATCHER)),
                    ("type", s("command")),
                    ("command", s(AGY_COMMAND)),
                ])])
            }),
        ),
        (
            "absolute path",
            Box::new(|d| {
                let g = idx_mut(at_mut(at_mut(d, "agent-guard"), "PreToolUse"), 0);
                *at_mut(idx_mut(at_mut(g, "hooks"), 0), "command") = s("/bin/sh /x/hook.sh")
            }),
        ),
    ];
    for (name, change) in &agy_mutations {
        fresh();
        edit(AGY_HOOKS_REL, change.as_ref());
        assert_ne!(check_wiring(&dir), Vec::<String>::new(), "{}", name);
    }
    fresh();
    std::fs::remove_file(join(&dir, AGY_HOOKS_REL)).unwrap();
    assert_ne!(check_wiring(&dir), Vec::<String>::new());
}
