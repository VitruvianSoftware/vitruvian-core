// Copyright (c) 2026 VitruvianSoftware
//
// SPDX-License-Identifier: MIT

//! Checks every plugin's hooks.json has the shape Antigravity loads.
//!
//! Antigravity's hook docs (embedded in its language server) say:
//! - PreToolUse and PostToolUse take groups: {"matcher": "<regex>", "hooks": [handler...]}.
//! - SessionStart, PreInvocation, PostInvocation and Stop take a flat list of
//!   handlers: [{"type": "command", "command": "...", "timeout": 5}].
//!
//! A file with one wrong entry is skipped whole (`agy plugin validate --strict`
//! then reports "hooks 0"), so every hook in it silently never runs. Until
//! this check existed, hookify, security-guidance, ralph-loop and
//! worktree-band shipped that way. `agy` is not available to Bazel, so this
//! checks the same rules.
//!
//! What a hook may answer also depends on the event. Captured with `agy -p`
//! and a logging hook for every event (2026-11-01): `{}` is harmless for
//! SessionStart, PreInvocation, PostInvocation, PostToolUse and Stop, but for
//! PreToolUse it DENIES the call (the step fails with "tool call denied by
//! pre-tool hook: "). So a script wired to PreToolUse must answer with a
//! "decision" even when rust-hook.sh falls back (no rustc, failed build).
//!
//! The files come from BUILD in $CONFORMANCE_FILES (every plugin's
//! :conformance_files); the hooks.json ones are checked, and the hook scripts
//! beside them are read for their fallbacks.

use serde_json::{json, Map, Value};
use std::fs;
use std::path::{Path, PathBuf};

const GROUPED: &[&str] = &["PreToolUse", "PostToolUse"];
const FLAT: &[&str] = &["SessionStart", "PreInvocation", "PostInvocation", "Stop"];

/// The first whitespace-separated word of a command: the script it runs.
fn first_word(command: &str) -> &str {
    command.split(char::is_whitespace).next().unwrap_or("")
}

/// Whether `pattern` would compile as a regex. Std-only on purpose (the
/// plugins' Rust is), so this catches the syntax errors that matter for a
/// matcher, not every corner of a full regex grammar: unbalanced groups or
/// classes, a dangling escape, and a quantifier with nothing to repeat.
/// Every real matcher is also pinned exactly in `expected()`.
fn regex_syntax_ok(pattern: &str) -> bool {
    let chars: Vec<char> = pattern.chars().collect();
    let mut depth = 0usize;
    // Whether the last thing read can take a quantifier.
    let mut repeatable = false;
    // Whether the last thing read was a quantifier (allows one lazy `?`).
    let mut after_quantifier = false;
    let mut i = 0;
    while i < chars.len() {
        let c = chars[i];
        match c {
            '\\' => {
                if i + 1 >= chars.len() {
                    return false;
                }
                i += 1;
                repeatable = true;
                after_quantifier = false;
            }
            '[' => {
                let mut j = i + 1;
                let mut closed = false;
                while j < chars.len() {
                    match chars[j] {
                        '\\' => j += 1,
                        ']' => {
                            closed = true;
                            break;
                        }
                        _ => {}
                    }
                    j += 1;
                }
                if !closed {
                    return false;
                }
                i = j;
                repeatable = true;
                after_quantifier = false;
            }
            '(' => {
                depth += 1;
                // Skip a group modifier: (?: (?= (?! (?<= (?<! (?<name>
                if chars.get(i + 1) == Some(&'?') {
                    i += 1;
                }
                repeatable = false;
                after_quantifier = false;
            }
            ')' => {
                if depth == 0 {
                    return false;
                }
                depth -= 1;
                repeatable = true;
                after_quantifier = false;
            }
            '|' => {
                repeatable = false;
                after_quantifier = false;
            }
            '*' | '+' | '?' => {
                if c == '?' && after_quantifier {
                    after_quantifier = false;
                } else if !repeatable {
                    return false;
                } else {
                    after_quantifier = true;
                }
                repeatable = false;
            }
            _ => {
                repeatable = true;
                after_quantifier = false;
            }
        }
        i += 1;
    }
    depth == 0
}

/// Problems with one handler object; `at` names it in messages.
fn handler_problems(h: &Value, at: &str, plugin_dir: Option<&Path>) -> Vec<String> {
    let Some(obj) = h.as_object() else {
        return vec![format!("{at}: a handler must be an object")];
    };
    let mut out = Vec::new();
    if obj.contains_key("hooks") || obj.contains_key("matcher") {
        out.push(format!(
            "{at}: a handler, but has \"hooks\"/\"matcher\" (a group)"
        ));
    }
    if let Some(t) = obj.get("type") {
        if t.as_str() != Some("command") {
            out.push(format!("{at}: type must be \"command\""));
        }
    }
    match obj.get("command").and_then(Value::as_str) {
        Some(command) if !command.trim().is_empty() => {
            if let Some(dir) = plugin_dir {
                if command.starts_with("./") {
                    // Existence only: Bazel's copy drops the exec bit, which
                    // each plugin's own rust_hook_test checks on the source.
                    if !dir.join(first_word(command)).exists() {
                        out.push(format!("{at}: {command} does not exist"));
                    }
                }
            }
        }
        _ => out.push(format!("{at}: needs a \"command\" string")),
    }
    if let Some(t) = obj.get("timeout") {
        let whole_positive = t
            .as_f64()
            .map_or(false, |n| n.is_finite() && n.fract() == 0.0 && n > 0.0);
        if !whole_positive {
            out.push(format!(
                "{at}: timeout must be a positive whole number of seconds"
            ));
        }
    }
    out
}

/// Every reason Antigravity would reject this parsed hooks.json.
fn hooks_json_problems(doc: &Value, plugin_dir: Option<&Path>) -> Vec<String> {
    let Some(sets) = doc.as_object() else {
        return vec!["hooks.json must be an object of named hook sets".to_string()];
    };
    let mut out = Vec::new();
    for (set, events) in sets {
        let Some(events) = events.as_object() else {
            out.push(format!("{set}: must map event names to lists"));
            continue;
        };
        for (event, list) in events {
            let at = format!("{set}.{event}");
            let grouped = GROUPED.contains(&event.as_str());
            let flat = FLAT.contains(&event.as_str());
            if !grouped && !flat {
                out.push(format!("{at}: unknown event"));
                continue;
            }
            let list = match list.as_array() {
                Some(l) if !l.is_empty() => l,
                _ => {
                    out.push(format!("{at}: must be a non-empty list"));
                    continue;
                }
            };
            for (i, entry) in list.iter().enumerate() {
                let where_ = format!("{at}[{i}]");
                if flat {
                    out.extend(handler_problems(entry, &where_, plugin_dir));
                    continue;
                }
                let Some(hooks) = entry.get("hooks").and_then(Value::as_array) else {
                    out.push(format!(
                        "{where_}: {event} takes groups {{\"matcher\", \"hooks\": [...]}}"
                    ));
                    continue;
                };
                if let Some(matcher) = entry.get("matcher") {
                    match matcher.as_str() {
                        None => out.push(format!("{where_}: matcher must be a string")),
                        Some("*") => {}
                        Some(m) if !regex_syntax_ok(m) => {
                            out.push(format!("{where_}: matcher is not a valid regex"))
                        }
                        Some(_) => {}
                    }
                }
                if hooks.is_empty() {
                    out.push(format!("{where_}: hooks is empty"));
                }
                for (j, h) in hooks.iter().enumerate() {
                    out.extend(handler_problems(
                        h,
                        &format!("{where_}.hooks[{j}]"),
                        plugin_dir,
                    ));
                }
            }
        }
    }
    out
}

/// What a launcher stub hands to rust-hook.sh as its fallback answer.
#[derive(Debug, PartialEq)]
enum Fallback {
    /// The script does not go through rust-hook.sh.
    NotLauncher,
    /// It does, but no `'{...}'` line was found.
    Unreadable,
    /// The `'{...}'` line was there but is not JSON.
    Invalid(String),
    Json(Value),
}

/// The fallback JSON a launcher stub hands to rust-hook.sh, if it is one: the
/// first line that is only `'{...}'` (surrounding whitespace allowed).
fn launcher_fallback(script_text: &str) -> Fallback {
    if !script_text.contains("rust-hook.sh") {
        return Fallback::NotLauncher;
    }
    for line in script_text.lines() {
        let t = line.trim();
        if t.len() >= 4 && t.starts_with("'{") && t.ends_with("}'") {
            let inner = &t[1..t.len() - 1];
            return match serde_json::from_str(inner) {
                Ok(v) => Fallback::Json(v),
                Err(e) => Fallback::Invalid(format!("{inner}: {e}")),
            };
        }
    }
    Fallback::Unreadable
}

/// Every handler object in one event's list (a group's hooks, or the entry).
fn handlers_of(entry: &Value) -> Vec<&Value> {
    match entry.get("hooks").and_then(Value::as_array) {
        Some(hooks) => hooks.iter().collect(),
        None => vec![entry],
    }
}

fn command_script(h: &Value) -> String {
    first_word(h.get("command").and_then(Value::as_str).unwrap_or("")).to_string()
}

/// Scripts wired to PreToolUse whose fallback would deny every tool call.
fn pre_tool_use_fallback_problems(
    doc: &Value,
    read_script: &dyn Fn(&str) -> String,
) -> Vec<String> {
    let mut out = Vec::new();
    let Some(sets) = doc.as_object() else {
        return out;
    };
    for (set, events) in sets {
        let Some(groups) = events.get("PreToolUse").and_then(Value::as_array) else {
            continue;
        };
        for group in groups {
            let Some(hooks) = group.get("hooks").and_then(Value::as_array) else {
                continue;
            };
            for h in hooks {
                let script = command_script(h);
                match launcher_fallback(&read_script(&script)) {
                    Fallback::NotLauncher => {}
                    Fallback::Unreadable => {
                        out.push(format!("{set}: {script} has no readable fallback JSON"))
                    }
                    Fallback::Invalid(e) => {
                        out.push(format!("{set}: {script} fallback is not JSON: {e}"))
                    }
                    Fallback::Json(fb) => {
                        if !fb.get("decision").map_or(false, Value::is_string) {
                            out.push(format!(
                                "{set}: {script} falls back to {fb}, which denies every tool call"
                            ));
                        }
                    }
                }
            }
        }
    }
    out
}

/// The events (with tool matcher, or null for a flat event) and per-script
/// fallback summary of a plugin, in the shape `expected()` pins.
fn wiring(doc: &Value, read_script: &dyn Fn(&str) -> String) -> Value {
    let mut events = Map::new();
    let mut fallbacks = Map::new();
    // serde_json sorts keys, so "last entry wins" below follows key order,
    // not file order. Every plugin has one hook set, so this never matters.
    for set in doc.as_object().into_iter().flat_map(|m| m.values()) {
        let Some(set) = set.as_object() else { continue };
        for (event, list) in set {
            let Some(list) = list.as_array() else {
                continue;
            };
            for entry in list {
                let grouped = entry.get("hooks").map_or(false, Value::is_array);
                let matcher = if grouped {
                    entry.get("matcher").cloned().unwrap_or_else(|| json!("*"))
                } else {
                    Value::Null
                };
                events.insert(event.clone(), matcher);
                for h in handlers_of(entry) {
                    let script = command_script(h);
                    let summary = match launcher_fallback(&read_script(&script)) {
                        Fallback::NotLauncher => Value::Null,
                        Fallback::Unreadable => json!("<no readable fallback>"),
                        Fallback::Invalid(e) => json!(format!("<invalid fallback: {e}>")),
                        Fallback::Json(fb) => {
                            if let Some(steps) = fb.get("injectSteps").and_then(Value::as_array) {
                                let first_key = steps
                                    .first()
                                    .and_then(Value::as_object)
                                    .and_then(|o| o.keys().next().cloned());
                                json!({ "injectSteps": first_key })
                            } else if let Some(d) = fb.as_object().and_then(|o| o.get("decision")) {
                                json!({ "decision": d })
                            } else {
                                fb
                            }
                        }
                    };
                    fallbacks.insert(script, summary);
                }
            }
        }
    }
    json!({ "events": events, "fallbacks": fallbacks })
}

/// What each plugin's hooks must be wired to, and what each hook answers
/// when it cannot run. Pinned exactly: dropping a tool from a guard's matcher,
/// or softening a guard's fallback, must fail here and be a deliberate change.
/// Tool names are those Antigravity sends (captured from `agy -p` and desktop
/// transcripts): write_file and edit_file (Path/Content/Target/Replacement);
/// write_to_file, replace_file_content and multi_replace_file_content
/// (TargetFile/...); run_command (CommandLine); manage_task (CLI) and
/// send_command_input (desktop), which type Input into a running shell.
fn expected() -> Value {
    json!({
        "ext-marketplace": {
            "events": { "PostToolUse": "run_command" },
            "fallbacks": { "./hooks/note-plugin-cmd.sh": {} },
        },
        "gh-watch": {
            "events": { "PostToolUse": "run_command" },
            "fallbacks": { "./hooks/note-pr-create.sh": {} },
        },
        "hookify": {
            "events": { "PreToolUse": "*", "Stop": null },
            "fallbacks": { "./hooks/evaluate-rules.sh": { "decision": "ask" } },
        },
        "live-context": {
            "events": { "PreInvocation": null, "Stop": null },
            "fallbacks": {
                "./hooks/inject-live-context.sh": { "injectSteps": "ephemeralMessage" },
                "./hooks/verify-response-shape.sh": { "decision": "allow" },
            },
        },
        "ralph-loop": {
            "events": { "Stop": null },
            "fallbacks": { "./hooks/ralph-stop.sh": { "decision": "allow" } },
        },
        "receipts-report": {
            "events": { "PostInvocation": null },
            "fallbacks": { "./hooks/record-turn.sh": {} },
        },
        "savvy-fleet": {
            "events": { "PostToolUse": "invoke_subagent|send_message" },
            "fallbacks": { "./hooks/track-subagent.sh": {} },
        },
        "security-guidance": {
            "events": {
                "PreToolUse": "write_file|edit_file|write_to_file|replace_file_content|multi_replace_file_content|run_command|manage_task|send_command_input",
                "Stop": null,
            },
            "fallbacks": { "./hooks/security-check.sh": { "decision": "ask" } },
        },
        "worktree-band": {
            "events": { "SessionStart": null },
            "fallbacks": {
                "./hooks/session-worktree.sh": { "injectSteps": "ephemeralMessage" },
            },
        },
    })
}

/// Every hooks.json named in $CONFORMANCE_FILES.
fn hooks_files() -> Vec<PathBuf> {
    let files = std::env::var("CONFORMANCE_FILES")
        .expect("CONFORMANCE_FILES is set by BUILD to every plugin's :conformance_files");
    files
        .split_whitespace()
        .filter(|f| f.ends_with("/hooks.json"))
        .map(PathBuf::from)
        .collect()
}

fn plugin_name(file: &Path) -> String {
    file.parent()
        .and_then(Path::file_name)
        .and_then(|n| n.to_str())
        .unwrap_or("")
        .to_string()
}

fn read_doc(file: &Path) -> Value {
    let text = fs::read_to_string(file).unwrap_or_else(|e| panic!("{}: {e}", file.display()));
    serde_json::from_str(&text).unwrap_or_else(|e| panic!("{}: not JSON: {e}", file.display()))
}

/// Reads a script relative to the plugin folder holding `file`.
fn script_reader(file: &Path) -> impl Fn(&str) -> String {
    let dir = file.parent().unwrap_or(Path::new("")).to_path_buf();
    move |script: &str| {
        let path = dir.join(script);
        fs::read_to_string(&path).unwrap_or_else(|e| panic!("{}: {e}", path.display()))
    }
}

#[test]
fn every_plugins_hooks_json_was_given() {
    let n = hooks_files().len();
    assert!(n >= 9, "expected the nine plugins, got {n}");
}

#[test]
fn every_hooks_json_has_the_shape_antigravity_loads() {
    let mut problems = Vec::new();
    for file in hooks_files() {
        let plugin = plugin_name(&file);
        let doc = read_doc(&file);
        let read = script_reader(&file);
        for p in hooks_json_problems(&doc, file.parent()) {
            problems.push(format!("{plugin}/hooks.json: {p}"));
        }
        for p in pre_tool_use_fallback_problems(&doc, &read) {
            problems.push(format!("{plugin}/hooks.json: {p}"));
        }
    }
    assert!(problems.is_empty(), "{}", problems.join("\n"));
}

#[test]
fn every_plugin_is_wired_as_pinned_in_expected() {
    let files = hooks_files();
    let expected = expected();
    let mut seen: Vec<String> = files.iter().map(|f| plugin_name(f)).collect();
    seen.sort();
    let mut want: Vec<String> = expected.as_object().unwrap().keys().cloned().collect();
    want.sort();
    assert_eq!(seen, want, "plugins given vs plugins pinned in expected()");
    for file in &files {
        let plugin = plugin_name(file);
        let got = wiring(&read_doc(file), &script_reader(file));
        assert_eq!(got, expected[&plugin], "{plugin}");
    }
}

#[test]
fn a_pre_tool_use_fallback_without_a_decision_is_rejected() {
    let doc = json!({
        "s": { "PreToolUse": [{ "matcher": "*", "hooks": [{ "command": "./h.sh" }] }] },
    });
    let stub = |fallback: &'static str| {
        move |_: &str| {
            format!("exec \"$(dirname \"$0\")/rust-hook.sh\" c main.rs \\\n\t'{fallback}'\n")
        }
    };
    assert_ne!(
        pre_tool_use_fallback_problems(&doc, &stub("{}")),
        Vec::<String>::new()
    );
    assert_eq!(
        pre_tool_use_fallback_problems(&doc, &stub(r#"{"decision":"ask","reason":"x"}"#)),
        Vec::<String>::new()
    );
}

#[test]
fn the_check_rejects_the_shapes_that_got_hooks_skipped() {
    let handler = json!({ "type": "command", "command": "x", "timeout": 5 });
    let none: Vec<String> = Vec::new();
    // Stop/SessionStart grouped like a tool event: the bug this test exists for.
    assert_ne!(
        hooks_json_problems(
            &json!({ "s": { "Stop": [{ "matcher": "*", "hooks": [handler] }] } }),
            None
        ),
        none
    );
    assert_ne!(
        hooks_json_problems(
            &json!({ "s": { "SessionStart": [{ "hooks": [handler] }] } }),
            None
        ),
        none
    );
    // A tool event given bare handlers.
    assert_ne!(
        hooks_json_problems(&json!({ "s": { "PreToolUse": [handler] } }), None),
        none
    );
    assert_ne!(
        hooks_json_problems(&json!({ "s": { "Bogus": [handler] } }), None),
        none
    );
    assert_ne!(
        hooks_json_problems(
            &json!({ "s": { "PreToolUse": [{ "matcher": "(", "hooks": [handler] }] } }),
            None
        ),
        none
    );
    // And accepts the right ones.
    assert_eq!(
        hooks_json_problems(
            &json!({
                "s": {
                    "Stop": [handler],
                    "PreToolUse": [{ "matcher": "run_command|edit_file", "hooks": [handler] }],
                },
            }),
            None
        ),
        none
    );
}

#[test]
fn the_regex_check_accepts_valid_matchers_and_rejects_broken_ones() {
    for ok in [
        "run_command",
        "run_command|edit_file",
        "invoke_subagent|send_message",
        "a(b|c)*",
        "(?:write|edit)_file",
        "[)(]",
        r"\(",
        "a*?",
        "",
    ] {
        assert!(regex_syntax_ok(ok), "{ok:?} should be valid");
    }
    for bad in ["(", ")", "a(b", "[a", r"a\", "*", "a**", "(*a)", "a|+b"] {
        assert!(!regex_syntax_ok(bad), "{bad:?} should be invalid");
    }
}
