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

//! UserFileToolTest: the backstop's user files. Other settings may change
//! through Claude Code's Edit, MultiEdit and Write; agent-guard's entries and
//! disableAllHooks may not; other tools may not write them at all.

use agent_guard::guard::DC;
use agent_guard::pyval::PyVal;

use crate::common::*;

const BACKSTOP_CMD: &str = "/bin/sh -c 'h=...' agent-guard-backstop /Users/j/vitruvian-core";

fn handler(command: &str) -> PyVal {
    obj(vec![("type", s("command")), ("command", s(command))])
}

fn user_settings() -> PyVal {
    obj(vec![
        ("effortLevel", s("high")),
        (
            "hooks",
            obj(vec![
                (
                    "PreToolUse",
                    list(vec![
                        obj(vec![
                            ("matcher", s("^(Bash)$")),
                            (
                                "hooks",
                                list(vec![obj(vec![
                                    ("type", s("command")),
                                    ("command", s(BACKSTOP_CMD)),
                                    ("onFailure", s("block")),
                                ])]),
                            ),
                        ]),
                        obj(vec![
                            ("matcher", s("^(Edit)$")),
                            ("hooks", list(vec![handler(BACKSTOP_CMD)])),
                        ]),
                    ]),
                ),
                (
                    "Stop",
                    list(vec![obj(vec![(
                        "hooks",
                        list(vec![handler("/h/stop.sh")]),
                    )])]),
                ),
            ]),
        ),
    ])
}

fn user_gemini() -> PyVal {
    obj(vec![
        (
            "agent-guard",
            obj(vec![
                ("enabled", b(true)),
                (
                    "PreToolUse",
                    list(vec![obj(vec![
                        ("matcher", s("run_command")),
                        ("hooks", list(vec![handler(BACKSTOP_CMD)])),
                    ])]),
                ),
            ]),
        ),
        (
            "response-contract",
            obj(vec![("enabled", b(true)), ("PreInvocation", list(vec![]))]),
        ),
    ])
}

struct Files {
    h: Harness,
    settings: String,
    gemini: String,
    text: String,
}

impl Files {
    fn new() -> Self {
        let h = Harness::new();
        let settings = join(&h.fx.home, ".claude/settings.json");
        let gemini = join(&h.fx.home, ".gemini/config/hooks.json");
        write(&settings, &to_json_indent(&user_settings(), 2));
        write(&gemini, &to_json_indent(&user_gemini(), 2));
        let text = read(&settings);
        Files {
            h,
            settings,
            gemini,
            text,
        }
    }

    fn decide(&self, tool: &str, tin: PyVal) -> String {
        match self.h.hook(&claude(tool, &self.h.fx.out, tin)) {
            Some(out) => st(at(&out, "hookSpecificOutput"), "permissionDecision"),
            None => A.to_string(),
        }
    }

    fn edit_in(&self, old: &str, new: &str, path: &str, replace_all: bool) -> String {
        let mut tin = vec![
            ("file_path", s(path)),
            ("old_string", s(old)),
            ("new_string", s(new)),
        ];
        if replace_all {
            tin.push(("replace_all", b(true)));
        }
        self.decide("Edit", obj(tin))
    }

    fn edit(&self, old: &str, new: &str) -> String {
        self.edit_in(old, new, &self.settings, false)
    }

    fn write_tool(&self, path: &str, content: &str) -> String {
        self.decide(
            "Write",
            obj(vec![("file_path", s(path)), ("content", s(content))]),
        )
    }
}

fn multi(path: &str, edits: &[(&str, &str)]) -> PyVal {
    obj(vec![
        ("file_path", s(path)),
        (
            "edits",
            list(
                edits
                    .iter()
                    .map(|(o, n)| obj(vec![("old_string", s(o)), ("new_string", s(n))]))
                    .collect(),
            ),
        ),
    ])
}

#[test]
fn edits_to_other_settings_are_allowed() {
    let f = Files::new();
    assert_eq!(
        f.edit("\"effortLevel\": \"high\"", "\"effortLevel\": \"low\""),
        A
    );
    assert_eq!(f.edit("\"/h/stop.sh\"", "\"/h/stop2.sh\""), A);
    assert_eq!(
        f.edit_in(
            "\"response-contract\": {",
            "\"other\": {}, \"response-contract\": {",
            &f.gemini,
            false
        ),
        A
    );
    assert_eq!(
        f.decide(
            "MultiEdit",
            multi(
                &f.settings,
                &[("\"high\"", "\"max\""), ("/h/stop.sh", "/h/s.sh")]
            )
        ),
        A
    );
}

#[test]
fn edits_that_remove_or_change_agent_guard_entries_are_refused() {
    let f = Files::new();
    assert_eq!(
        f.edit("\"onFailure\": \"block\"", "\"onFailure\": \"allow\""),
        D
    );
    assert_eq!(
        f.edit_in("agent-guard-backstop", "nothing", &f.settings, true),
        D
    );
    assert_eq!(
        f.edit("\"matcher\": \"^(Bash)$\"", "\"matcher\": \"^(Nothing)$\""),
        D
    );
    assert_eq!(
        f.edit_in(
            "\"enabled\": true,\n    \"PreToolUse\"",
            "\"enabled\": false,\n    \"PreToolUse\"",
            &f.gemini,
            false
        ),
        D
    );
    assert_eq!(
        f.decide(
            "MultiEdit",
            multi(
                &f.settings,
                &[
                    ("\"high\"", "\"max\""),
                    ("\"onFailure\": \"block\"", "\"x\": 1")
                ]
            )
        ),
        D
    );
    // Not found in the file (so it cannot be simulated) but aimed at our entries.
    assert_eq!(f.edit("tools/agent-guard/hook.sh gone", "x"), D);
}

#[test]
fn disable_all_hooks_true_is_refused_false_is_fine() {
    let f = Files::new();
    assert_eq!(
        f.edit(
            "\"effortLevel\": \"high\"",
            "\"effortLevel\": \"high\", \"disableAllHooks\": true"
        ),
        D
    );
    assert_eq!(
        f.edit(
            "\"effortLevel\": \"high\"",
            "\"disableAllHooks\":true,\"effortLevel\": \"high\""
        ),
        D
    );
    assert_eq!(
        f.edit(
            "\"effortLevel\": \"high\"",
            "\"disableAllHooks\": false, \"effortLevel\": \"high\""
        ),
        A
    );
    let data = with_key(&user_settings(), "disableAllHooks", b(true));
    assert_eq!(f.write_tool(&f.settings, &to_json(&data)), D);
    let data = with_key(&user_settings(), "disableAllHooks", b(false));
    assert_eq!(f.write_tool(&f.settings, &to_json(&data)), A);
    // Flipping an existing false to true with an edit that names only the value.
    write(
        &f.settings,
        &to_json_indent(&with_key(&user_settings(), "disableAllHooks", b(false)), 2),
    );
    assert_eq!(f.edit("false", "true"), D);
    assert_eq!(f.edit("false", "false "), A);
}

#[test]
fn write_must_keep_the_same_entries() {
    let f = Files::new();
    let kept = with_key(
        &with_key(&user_settings(), "effortLevel", s("low")),
        "model",
        s("x"),
    );
    assert_eq!(f.write_tool(&f.settings, &to_json_indent(&kept, 4)), A);
    let stop = at(at(&user_settings(), "hooks"), "Stop").clone();
    let dropped = with_key(&user_settings(), "hooks", obj(vec![("Stop", stop)]));
    for content in [to_json(&dropped), "{}".to_string(), "{not json".to_string()] {
        assert_eq!(f.write_tool(&f.settings, &content), D, "{}", content);
    }
    let g2 = without_key(&user_gemini(), "agent-guard");
    assert_eq!(f.write_tool(&f.gemini, &to_json(&g2)), D);
    assert_eq!(
        f.write_tool(
            &f.gemini,
            &to_json(&with_key(&user_gemini(), "extra", obj(vec![])))
        ),
        A
    );
}

#[test]
fn write_with_no_entries_to_keep_is_allowed() {
    let f = Files::new();
    std::fs::remove_file(&f.settings).unwrap();
    assert_eq!(f.write_tool(&f.settings, "{\"a\": 1}"), A);
    assert_eq!(f.write_tool(&f.settings, "{\"disableAllHooks\": true}"), D);
}

#[test]
fn other_tools_may_not_write_them() {
    let f = Files::new();
    let dc = |t: &str| format!("{}{}", DC, t);
    let cases = [
        (
            dc("write_file"),
            obj(vec![("path", s(&f.settings)), ("content", s(&f.text))]),
        ),
        (
            dc("edit_block"),
            obj(vec![
                ("file_path", s(&f.gemini)),
                ("old_string", s("a")),
                ("new_string", s("b")),
            ]),
        ),
        (
            dc("move_file"),
            obj(vec![
                ("source", s(&f.settings)),
                ("destination", s("/tmp/x")),
            ]),
        ),
        (
            dc("move_file"),
            obj(vec![("source", s("/tmp/x")), ("destination", s(&f.gemini))]),
        ),
        (
            dc("move_file"),
            obj(vec![
                ("source", s(&dirname(&f.settings))),
                ("destination", s("/tmp/x")),
            ]),
        ),
    ];
    for (tool, tin) in cases {
        assert_eq!(f.decide(&tool, tin), D, "{}", tool);
    }
    let out =
        f.h.hook(&obj(vec![
            (
                "toolCall",
                obj(vec![
                    ("name", s("write_to_file")),
                    (
                        "args",
                        obj(vec![("TargetFile", s(&f.gemini)), ("CodeContent", s("{}"))]),
                    ),
                ]),
            ),
            ("workspacePaths", strs(&[&f.h.fx.out])),
        ]))
        .expect("an answer");
    assert_eq!(st(&out, "decision"), "deny");
}

#[test]
fn the_refusal_says_what_to_do() {
    let f = Files::new();
    let out =
        f.h.hook(&claude(
            "Edit",
            &f.h.fx.out,
            obj(vec![
                ("file_path", s(&f.settings)),
                ("old_string", s("\"onFailure\": \"block\"")),
                ("new_string", s("\"onFailure\": \"allow\"")),
            ]),
        ))
        .expect("an answer");
    let msg = st(at(&out, "hookSpecificOutput"), "permissionDecisionReason");
    assert!(
        msg.contains("removes or changes agent-guard's entries"),
        "{}",
        msg
    );
    assert!(
        msg.contains("bazel run //tools/agent-guard:install"),
        "{}",
        msg
    );
    assert_eq!(
        opt_st(&f.h.last(), "category").as_deref(),
        Some("guard-config")
    );
}

/// The settings file is written in Python's json.dump(indent=2) layout, which
/// the edits above match by exact text.
#[test]
fn settings_are_written_in_pythons_layout() {
    let f = Files::new();
    assert!(f.text.starts_with("{\n  \"effortLevel\": \"high\",\n  \"hooks\": {\n    \"PreToolUse\": [\n      {\n        \"matcher\": \"^(Bash)$\","), "{}", f.text);
    assert!(read(&f.gemini).contains("\"enabled\": true,\n    \"PreToolUse\""));
    assert!(read(&f.gemini).contains("\"PreInvocation\": []"));
}
