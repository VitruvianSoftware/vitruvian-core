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

//! The decision: policy and modes, `evaluate` for a shell command, and
//! `evaluate_tool` for a whole hook payload.

use std::collections::{HashMap, HashSet};

use crate::classify::GitProbe;
use crate::classify::{
    classify_tool, gh_target_repo, gh_url, is_vitruvian_core_slug, v, Context, Target, Verdict,
    GUARDRAIL, T_COMMIT, T_GITOPS, T_HELM, T_PR_ENQUEUE,
};
use crate::invocations::{expand_path, invocations, Invocation};
use crate::paths::{getcwd, home_dir, isabs, read_text_strict};
use crate::pyval::{dumps, loads, PyVal};
use crate::scope::repo_root_of;
use crate::shell::{PErr, MAX_COMMANDS};
use crate::tamper::{
    classify_guard_tamper, disables_all_hooks, guard_path, hook_files_note, protected_repo_file,
    user_file_change_problem, user_hook_file, user_hook_mark, USER_FILES_NOTE,
};

pub const VERSION: &str = "1.0.0";
pub const MODES: [&str; 3] = ["enforce", "warn", "off"];

/// Categories, in policy order, with what each covers.
pub const CATEGORIES: [(&str, &str); 27] = [
    ("git-commit", "git add / rm / mv / commit"),
    ("git-push", "git push"),
    ("git-history", "git rebase, merge, pull (except ff-only on the primary checkout), reset, cherry-pick, revert, am, bisect, tag"),
    ("git-stash", "git stash (anything but list/show)"),
    ("git-branch", "creating, switching, renaming or deleting branches"),
    ("git-worktree", "git worktree add/remove/prune/lock/unlock/move, and rm -r of a worktree"),
    ("git-other", "every other git verb that writes (config, remote, apply, clean, gc, clone, ...)"),
    ("gh-pr", "gh pr create/edit/comment/merge/ready/close/review, and the auto-merge MCP tool"),
    ("gh-run", "gh workflow run/enable/disable, gh run rerun/cancel/delete"),
    ("gh-api", "gh api writes and GraphQL mutations"),
    ("gh-other", "every other gh command that writes (release, secret, repo, label, ...)"),
    ("go", "go build/test/vet/run/install/generate/mod/get/fmt"),
    ("swift", "swift build/test/run/package, swiftc"),
    ("xcode", "xcodebuild, xcrun notarytool/stapler/altool/swift"),
    ("node", "npm/pnpm/npx/yarn/bun installs and runs"),
    ("cargo", "cargo build/test/run/publish/..."),
    ("gradle", "gradle and gradlew"),
    ("pytest", "pytest, python -m pytest"),
    ("lint", "linters and formatters run directly (gofmt, golangci-lint, ruff, eslint, prettier, ...)"),
    ("actionlint", "actionlint run directly"),
    ("secret-scan", "gitleaks run directly"),
    ("iac", "pulumi and terraform run directly"),
    ("kubectl", "kubectl writes (apply, delete, patch, edit, exec, rollout, scale, ...) and the kubernetes MCP write tools"),
    ("helm", "helm install/upgrade/uninstall/rollback"),
    ("bazel-cache", "deleting Bazel output bases (rm -r, bazel clean --expunge, --output_user_root/--output_base overrides)"),
    ("guard-config", "agents changing agent-guard itself, or the files that drive session start"),
    ("oversize", "a command too large to check in time (over 20,000 commands); split it up"),
];

/// Categories that apply wherever the agent is.
const GLOBAL_CATEGORIES: [&str; 2] = ["bazel-cache", "guard-config"];

pub type Modes = HashMap<String, String>;

pub fn all_enforce() -> Modes {
    CATEGORIES
        .iter()
        .map(|(c, _)| (c.to_string(), "enforce".to_string()))
        .collect()
}

fn mode_of(modes: &Modes, category: &str) -> String {
    modes
        .get(category)
        .cloned()
        .unwrap_or_else(|| "enforce".into())
}

/// A policy whose shape breaks agent_guard.py's load_policy outright (it
/// raises AttributeError and the hook exits 1).
#[derive(Debug)]
pub struct PolicyCrash(pub String);

pub fn load_policy(path: Option<&str>) -> Result<Modes, PolicyCrash> {
    let mut modes = all_enforce();
    let Some(path) = path.filter(|p| !p.is_empty()) else {
        return Ok(modes);
    };
    let data = match std::fs::read(path)
        .ok()
        .and_then(|b| String::from_utf8(b).ok())
    {
        Some(text) => match loads(&crate::pyutil::universal_newlines(&text)) {
            Ok(d) => d,
            Err(crate::pyval::JsonErr::Value) => return Ok(modes),
            Err(crate::pyval::JsonErr::Recursion) => {
                return Err(PolicyCrash("RecursionError".into()))
            }
        },
        None => return Ok(modes), // a missing or broken policy means: enforce everything
    };
    let PyVal::Dict(_) = &data else {
        return Err(PolicyCrash(
            "AttributeError: policy is not an object".into(),
        ));
    };
    let default = match data.get("default_mode") {
        None => "enforce".to_string(),
        Some(PyVal::Str(s)) if MODES.contains(&s.as_str()) => s.clone(),
        Some(_) => "enforce".to_string(),
    };
    let cats = data
        .get("categories")
        .cloned()
        .unwrap_or(PyVal::Dict(vec![]));
    let cats = if cats.truthy() {
        cats
    } else {
        PyVal::Dict(vec![])
    };
    if !cats.is_dict() {
        return Err(PolicyCrash(
            "AttributeError: categories is not an object".into(),
        ));
    }
    for (c, _) in CATEGORIES {
        let entry = cats.get(c).cloned().unwrap_or(PyVal::Dict(vec![]));
        let mode = match &entry {
            PyVal::Dict(_) => entry.get("mode").cloned().unwrap_or(PyVal::None),
            other => other.clone(),
        };
        let m = match &mode {
            PyVal::Str(s) if MODES.contains(&s.as_str()) => s.clone(),
            _ => default.clone(),
        };
        modes.insert(c.to_string(), m);
    }
    Ok(modes)
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Decision {
    /// allow | deny | warn
    pub decision: String,
    pub category: Option<String>,
    pub message: String,
    /// inside | outside | unknown
    pub scope: String,
    pub op: String,
}

impl Decision {
    pub fn allow(scope: &str) -> Self {
        Decision {
            decision: "allow".into(),
            category: None,
            message: String::new(),
            scope: scope.into(),
            op: String::new(),
        }
    }

    fn of(kind: &str, verdict: &Verdict, message: String, scope: &str) -> Self {
        Decision {
            decision: kind.into(),
            category: Some(verdict.category.clone()),
            message,
            scope: scope.into(),
            op: verdict.op.clone(),
        }
    }
}

fn scope_name(inside: bool, cwd_known: bool) -> &'static str {
    if !cwd_known {
        "unknown"
    } else if inside {
        "inside"
    } else {
        "outside"
    }
}

fn enforce_or_warn(mode: &str) -> &'static str {
    if mode == "enforce" {
        "deny"
    } else {
        "warn"
    }
}

/// Decide on one shell command. The first refused invocation wins.
pub fn evaluate(
    command: &str,
    cwd: &str,
    modes: Option<&Modes>,
    home: Option<&str>,
    git_state: Option<GitProbe>,
    cwd_known: bool,
) -> Decision {
    let default_modes;
    let modes = match modes.filter(|m| !m.is_empty()) {
        Some(m) => m,
        None => {
            default_modes = all_enforce();
            &default_modes
        }
    };
    let home_owned = match home.filter(|h| !h.is_empty()) {
        Some(h) => h.to_string(),
        None => home_dir(),
    };
    let home = home_owned.as_str();
    let ctx = Context::new(home, git_state);
    // With no known location, a root that counts as inside but names no checkout.
    let unknown: Option<String> = if cwd_known { None } else { Some(String::new()) };
    let mut any_inside = repo_root_of(cwd).is_some() || !cwd_known;
    let mut warned: Option<Decision> = None;
    let invs = match invocations(command, cwd, home) {
        Ok(i) => i,
        Err(PErr::TooComplex) | Err(PErr::Parse) => {
            let mode = mode_of(modes, "oversize");
            if !any_inside || mode == "off" {
                return Decision::allow(scope_name(any_inside, cwd_known));
            }
            let msg = format!(
                "Blocked by agent-guard: this command runs more than {} commands, too many to check \
within the hook's time limit. Split it into smaller commands. {}",
                MAX_COMMANDS, GUARDRAIL
            );
            return Decision {
                decision: enforce_or_warn(&mode).into(),
                category: Some("oversize".into()),
                message: msg,
                scope: scope_name(true, cwd_known).into(),
                op: "oversized command".into(),
            };
        }
    };
    if invs.iter().any(|i| i.hides_marker)
        && invs
            .iter()
            .any(|i| i.argv.iter().any(|w| w.contains("agent-guard")))
    {
        let mode = mode_of(modes, "guard-config");
        if mode != "off" {
            let vd = v(
                "guard-config",
                "hiding the agent session from agent-guard",
                None,
                "Unsetting CLAUDECODE (or an Antigravity/Gemini marker) around agent-guard is routing around it.",
            );
            return Decision::of(enforce_or_warn(&mode), &vd, vd.message(None), "outside");
        }
    }
    // (argv, cwd, redirects): the same command repeated is checked once.
    type Key = (Vec<String>, String, Vec<(String, String)>);
    let mut seen: HashSet<Key> = HashSet::new();
    for inv in &invs {
        // The same command repeated is checked once.
        if !seen.insert((inv.argv.clone(), inv.cwd.clone(), inv.redirects.clone())) {
            continue;
        }
        let mut verdict = classify_guard_tamper(inv, &ctx);
        let mut scope_dir = inv.cwd.clone();
        if verdict.is_none() {
            let (vd, dir) = classify_tool(inv, &ctx);
            verdict = vd;
            scope_dir = dir;
        }
        let mut root = repo_root_of(&scope_dir);
        if inv.prog() == "gh" {
            // A gh command names its repo with -R, a PR/issue URL or an API path.
            match gh_target_repo(&inv.argv[1..]) {
                Some(target) => {
                    root = if is_vitruvian_core_slug(&target) {
                        Some(repo_root_of(&scope_dir).unwrap_or_default())
                    } else {
                        None
                    };
                }
                None => {
                    if root.is_none() {
                        root = unknown.clone();
                    }
                }
            }
        } else if root.is_none() {
            root = unknown.clone();
        }
        if root.is_some() {
            any_inside = true;
        }
        let Some(verdict) = verdict else { continue };
        if root.is_none() && !GLOBAL_CATEGORIES.contains(&verdict.category.as_str()) {
            continue;
        }
        let mode = mode_of(modes, &verdict.category);
        if mode == "off" {
            continue;
        }
        let msg_root = match root.as_deref().filter(|r| !r.is_empty()) {
            Some(r) => Some(r.to_string()),
            None => repo_root_of(cwd),
        };
        let msg = verdict.message(msg_root.as_deref());
        let scope = scope_name(root.is_some(), cwd_known);
        if mode == "warn" {
            if warned.is_none() {
                warned = Some(Decision::of("warn", &verdict, msg, scope));
            }
            continue;
        }
        return Decision::of("deny", &verdict, msg, scope);
    }
    if let Some(w) = warned {
        return w;
    }
    Decision::allow(scope_name(any_inside, cwd_known))
}

/// Tools whose input carries a shell command, and the fields that may hold it.
pub fn command_fields(tool: &str) -> Option<&'static [&'static str]> {
    Some(match tool {
        "Bash" | "Monitor" | "mcp__terminal__run_in_terminal" => &["command"],
        "mcp__plugin_desktop-commander_desktop-commander__start_process" => &["command"],
        "mcp__plugin_desktop-commander_desktop-commander__interact_with_process" => &["input"],
        "run_command" => &["CommandLine"],
        "shell_exec" => &["Command", "command", "CommandLine"],
        "send_command_input" => &["Input", "input"],
        _ => return None,
    })
}

pub const DC: &str = "mcp__plugin_desktop-commander_desktop-commander__";

/// Tools that write files, and the fields naming the files.
pub fn file_tool_fields(tool: &str) -> Option<&'static [&'static str]> {
    Some(match tool {
        "Edit" | "Write" | "MultiEdit" => &["file_path"],
        "NotebookEdit" => &["notebook_path"],
        "write_to_file" | "replace_file_content" | "multi_replace_file_content" => &["TargetFile"],
        "notebook_edit" => &["NotebookPath"],
        _ => match tool.strip_prefix(DC)? {
            "write_file" => &["path"],
            "edit_block" => &["file_path"],
            "move_file" => &["source", "destination"],
            "create_directory" => &["path"],
            "write_pdf" => &["path", "outputPath"],
            _ => return None,
        },
    })
}

pub const AGY_MANAGE_TASK: &str = "manage_task";
pub const AGY_GIT_COMMIT: &str = "git_commit";
pub const UNKNOWN_CWD: &str = "/nonexistent/agent-guard-unknown-cwd";

fn as_dict(v: Option<&PyVal>) -> PyVal {
    match v {
        Some(d @ PyVal::Dict(_)) => d.clone(),
        _ => PyVal::Dict(vec![]),
    }
}

/// `a or b` for two dict lookups.
fn or_get<'a>(d: &'a PyVal, a: &str, b: &str) -> Option<&'a PyVal> {
    match d.get(a) {
        Some(x) if x.truthy() => Some(x),
        _ => d.get(b),
    }
}

fn str_or_empty(v: Option<&PyVal>) -> String {
    match v {
        Some(x) if x.truthy() => x.py_str(),
        _ => String::new(),
    }
}

fn first_text(tin: &PyVal, fields: &[&str]) -> String {
    for f in fields {
        if let Some(x) = tin.get(f) {
            if x.truthy() {
                return x.py_str();
            }
        }
    }
    String::new()
}

/// (is Antigravity, tool name, tool arguments) from either hook format.
pub fn tool_call(payload: &PyVal) -> (bool, String, PyVal) {
    if payload.has("toolCall") {
        let call = as_dict(payload.get("toolCall"));
        let tool = str_or_empty(or_get(&call, "name", "toolName"));
        return (true, tool, as_dict(or_get(&call, "args", "arguments")));
    }
    (
        false,
        str_or_empty(payload.get("tool_name")),
        as_dict(payload.get("tool_input")),
    )
}

/// (directory the tool call runs in, whether the payload said so).
pub fn resolve_cwd(payload: &PyVal, home: &str) -> (String, bool) {
    let (antigravity, tool, tin) = tool_call(payload);
    if antigravity {
        let mut raw = str_or_empty(or_get(&tin, "Cwd", "cwd"));
        if raw.is_empty() {
            let spaces: Vec<String> = match payload.get("workspacePaths") {
                Some(PyVal::List(items)) => items
                    .iter()
                    .filter_map(|p| p.as_str().filter(|s| !s.is_empty()))
                    .map(|p| expand_path(p, "", home))
                    .filter(|p| isabs(p))
                    .collect(),
                _ => vec![],
            };
            raw = spaces
                .iter()
                .find(|p| repo_root_of(p).is_some())
                .cloned()
                .or_else(|| spaces.first().cloned())
                .unwrap_or_default();
        }
        let path = if raw.is_empty() {
            String::new()
        } else {
            expand_path(&raw, "", home)
        };
        if !isabs(&path) {
            // Missing, or relative to a directory nobody named: unknown.
            return (UNKNOWN_CWD.into(), false);
        }
        return (path, true);
    }
    let truthy = |x: Option<&PyVal>| x.filter(|v| v.truthy()).map(|v| v.py_str());
    let own = if tool == "mcp__terminal__run_in_terminal" {
        truthy(tin.get("cwd"))
    } else {
        None
    };
    let raw = own
        .or_else(|| truthy(payload.get("cwd")))
        .unwrap_or_else(getcwd);
    (expand_path(&raw, &getcwd(), home), true)
}

/// text after Claude Code's Edit/MultiEdit edits, or None if one would not apply.
fn edited(text: &str, edits: &[PyVal]) -> Option<String> {
    let mut text = text.to_string();
    for e in edits {
        let old = str_or_empty(e.get("old_string"));
        let new = str_or_empty(e.get("new_string"));
        if old.is_empty() || !text.contains(&old) {
            return None;
        }
        text = if e.get("replace_all").map_or(false, |r| r.truthy()) {
            text.replace(&old, &new)
        } else {
            text.replacen(&old, &new, 1)
        };
    }
    Some(text)
}

fn guard_config_decision(mode: &str, op: &str, note: &str) -> Decision {
    let vd = v("guard-config", op, None, note);
    Decision::of(enforce_or_warn(mode), &vd, vd.message(None), "outside")
}

/// The decision on a file tool that touches a backstop user file, or None if it touches none.
fn user_file_tool_decision(
    tool: &str,
    tin: &PyVal,
    cwd: &str,
    home: &str,
    modes: &Modes,
) -> Option<(Decision, String, String)> {
    let mode = mode_of(modes, "guard-config");
    if mode == "off" {
        return None;
    }
    let mut hit = String::new();
    for f in file_tool_fields(tool)? {
        let raw = str_or_empty(tin.get(f));
        if !raw.is_empty()
            && user_hook_file(
                &expand_path(&raw, cwd, home),
                home,
                tool == format!("{}move_file", DC),
            )
            .is_some()
        {
            hit = expand_path(&raw, cwd, home);
            break;
        }
    }
    if hit.is_empty() {
        return None;
    }
    let note;
    if tool == "Edit" || tool == "MultiEdit" || tool == "Write" {
        let before = read_text_strict(&hit);
        let mut why = String::new();
        if tool == "Write" {
            why = user_file_change_problem(
                &hit,
                before.as_deref(),
                &str_or_empty(tin.get("content")),
            );
        } else {
            let edits_val: Vec<PyVal> = if tool == "MultiEdit" {
                // Any other truthy value iterates as keys or characters in
                // Python, none of them dicts.
                match tin.get("edits") {
                    Some(PyVal::List(l)) => l.clone(),
                    // A truthy number is not iterable: Python's TypeError.
                    Some(x @ (PyVal::Int(_) | PyVal::Float(_) | PyVal::Bool(_))) if x.truthy() => {
                        panic!("TypeError: edits is not iterable")
                    }
                    _ => vec![],
                }
            } else {
                vec![tin.clone()]
            };
            let edits: Vec<PyVal> = edits_val.into_iter().filter(|e| e.is_dict()).collect();
            if edits
                .iter()
                .any(|e| disables_all_hooks(&str_or_empty(e.get("new_string"))))
            {
                why = "it sets \"disableAllHooks\": true".into();
            } else {
                let after = before.as_deref().and_then(|b| edited(b, &edits));
                if let Some(after) = after {
                    why = user_file_change_problem(&hit, before.as_deref(), &after);
                } else if edits.iter().any(|e| {
                    let old = str_or_empty(e.get("old_string"));
                    user_hook_mark(&old) || old.contains("agent-guard")
                }) {
                    why = "it edits agent-guard's entries".into();
                }
            }
        }
        if why.is_empty() {
            return Some((Decision::allow("outside"), tool.to_string(), String::new()));
        }
        note = format!(
            "This {} of {} is refused: {}. Other settings there are yours to change; \
agent-guard's entries change only through `bazel run //tools/agent-guard:install`, \
and removing them is James's.",
            tool, hit, why
        );
    } else {
        note = USER_FILES_NOTE.to_string();
    }
    let d = guard_config_decision(
        &mode,
        &format!("{} of the backstop's user files", tool),
        &note,
    );
    Some((d, tool.to_string(), hit))
}

fn apply_mode(vd: &Verdict, modes: &Modes, in_scope: bool, root: Option<&str>) -> Decision {
    let scope = if in_scope { "inside" } else { "outside" };
    if !in_scope {
        return Decision::allow(scope);
    }
    let mode = mode_of(modes, &vd.category);
    if mode == "off" {
        return Decision::allow(scope);
    }
    Decision::of(enforce_or_warn(&mode), vd, vd.message(root), scope)
}

/// `^mcp__(kubernetes|Kubernetes_MCP_Server)__(.+)$` -> group 2.
fn k8s_tool(tool: &str) -> Option<String> {
    let rest = tool
        .strip_prefix("mcp__kubernetes__")
        .or_else(|| tool.strip_prefix("mcp__Kubernetes_MCP_Server__"))?;
    let core = rest.strip_suffix('\n').unwrap_or(rest);
    if core.is_empty() || core.contains('\n') {
        return None;
    }
    Some(core.to_string())
}

fn without_keys(d: &PyVal, drop: &[&str]) -> PyVal {
    match d {
        PyVal::Dict(items) => PyVal::Dict(
            items
                .iter()
                .filter(|(k, _)| !drop.contains(&k.as_str()))
                .cloned()
                .collect(),
        ),
        other => other.clone(),
    }
}

/// Decide on a hook payload. Returns (decision, tool name, command text for the log).
pub fn evaluate_tool(
    payload: &PyVal,
    modes: &Modes,
    home: &str,
    git_state: Option<GitProbe>,
) -> (Decision, String, String) {
    let (_antigravity, tool, tin) = tool_call(payload);
    let (cwd, cwd_known) = resolve_cwd(payload, home);

    let mut fields: Option<&[&str]> = command_fields(&tool);
    if tool == AGY_MANAGE_TASK {
        fields = if tin.get_or_none("Action").py_str() == "send_input" {
            Some(&["Input", "input"])
        } else {
            None
        };
        if fields.is_none() {
            return (
                Decision::allow(scope_name(false, cwd_known)),
                tool,
                String::new(),
            );
        }
    }
    if let Some(fields) = fields {
        let text = first_text(&tin, fields);
        let d = evaluate(&text, &cwd, Some(modes), Some(home), git_state, cwd_known);
        return (d, tool, text);
    }

    if let Some(ffields) = file_tool_fields(&tool) {
        if let Some(user) = user_file_tool_decision(&tool, &tin, &cwd, home, modes) {
            return user;
        }
        let path = ffields
            .iter()
            .map(|f| str_or_empty(tin.get(f)))
            .find(|p| !p.is_empty() && guard_path(&expand_path(p, &cwd, home), home))
            .unwrap_or_default();
        let gc = modes.get("guard-config").cloned();
        if !path.is_empty() && gc.as_deref() != Some("off") {
            let (op, note) = if protected_repo_file(&expand_path(&path, &cwd, home), true).is_some()
            {
                (
                    format!("{} of agent-guard's hook files", tool),
                    hook_files_note(),
                )
            } else {
                (
                    format!("{} of agent-guard files", tool),
                    "Changing agent-guard is James's job, from his own terminal.".to_string(),
                )
            };
            let vd = v("guard-config", &op, None, &note);
            let kind = if gc.as_deref() == Some("enforce") {
                "deny"
            } else {
                "warn"
            };
            let d = Decision::of(kind, &vd, vd.message(None), "outside");
            return (d, tool, path);
        }
        return (Decision::allow("outside"), tool, String::new());
    }

    if tool == AGY_GIT_COMMIT {
        let in_scope = repo_root_of(&cwd).is_some() || !cwd_known;
        let vd = v(
            "git-commit",
            "git commit (Antigravity git_commit tool)",
            Some(T_COMMIT),
            "",
        );
        let mut d = apply_mode(&vd, modes, in_scope, repo_root_of(&cwd).as_deref());
        if !cwd_known {
            d.scope = "unknown".into();
        }
        let text = format!(
            "git_commit {}",
            dumps(&without_keys(&tin, &["toolAction", "toolSummary"]), true)
        );
        return (d, tool, text);
    }

    let mut in_scope = repo_root_of(&cwd).is_some();
    if tool == "mcp__ccd_pr__set_auto_merge" {
        let url = str_or_empty(tin.get("url"));
        if let Some((o, n)) = gh_url(&url) {
            in_scope = is_vitruvian_core_slug(&format!("{}/{}", o, n));
        }
        if !tin.get("enabled").map_or(false, |e| e.truthy()) {
            let scope = if in_scope { "inside" } else { "outside" };
            return (
                Decision::allow(scope),
                tool,
                format!("set_auto_merge enabled=false {}", url),
            );
        }
        let vd = v(
            "gh-pr",
            "auto-merge (ccd_pr set_auto_merge)",
            Some(T_PR_ENQUEUE),
            "It arms auto-merge through the merge queue.",
        );
        let d = apply_mode(&vd, modes, in_scope, repo_root_of(&cwd).as_deref());
        return (d, tool, format!("set_auto_merge enabled=true {}", url));
    }

    if let Some(name) = k8s_tool(&tool) {
        let text = format!("{} {}", name, dumps(&tin, true));
        let verdict: Option<Verdict> = if name == "kubectl_generic" {
            let mut argv = vec!["kubectl".to_string(), str_or_empty(tin.get("command"))];
            if tin.get("subCommand").map_or(false, |s| s.truthy()) {
                argv.push(tin.get_or_none("subCommand").py_str());
            }
            let ctx = Context::new(home, git_state);
            classify_tool(&Invocation::new(argv, &cwd, vec![]), &ctx).0
        } else if name == "kubectl_rollout"
            && ["status", "history"].contains(&str_or_empty(tin.get("subCommand")).as_str())
        {
            None
        } else if [
            "kubectl_apply",
            "kubectl_delete",
            "kubectl_patch",
            "kubectl_create",
            "kubectl_scale",
            "kubectl_rollout",
            "exec_in_pod",
            "node_management",
        ]
        .contains(&name.as_str())
        {
            let verb = name.replace("kubectl_", "").replace("_in_pod", "");
            let target: Option<Target> =
                if ["apply", "delete", "patch", "create"].contains(&verb.as_str()) {
                    Some(T_GITOPS)
                } else {
                    None
                };
            Some(v("kubectl", &format!("kubectl {} (MCP)", verb), target, ""))
        } else if name.ends_with("_helm_chart") {
            Some(v(
                "helm",
                &format!("helm {} (MCP)", name.split('_').next().unwrap_or("")),
                Some(T_HELM),
                "",
            ))
        } else {
            None
        };
        let Some(vd) = verdict.filter(|_| in_scope) else {
            return (
                Decision::allow(if in_scope { "inside" } else { "outside" }),
                tool,
                text,
            );
        };
        return (apply_mode(&vd, modes, in_scope, None), tool, text);
    }

    (
        Decision::allow(if in_scope { "inside" } else { "outside" }),
        tool,
        String::new(),
    )
}

/// The hook's stdout JSON, or None to print nothing (allow).
pub fn render(decision: &Decision, antigravity: bool) -> Option<PyVal> {
    use crate::pyval::{dict, s};
    if decision.decision == "deny" {
        if antigravity {
            return Some(dict(vec![
                ("decision", s("deny")),
                ("reason", s(&decision.message)),
            ]));
        }
        return Some(dict(vec![(
            "hookSpecificOutput",
            dict(vec![
                ("hookEventName", s("PreToolUse")),
                ("permissionDecision", s("deny")),
                ("permissionDecisionReason", s(&decision.message)),
            ]),
        )]));
    }
    if decision.decision == "warn" {
        if antigravity {
            return None;
        }
        let warning = format!(
            "agent-guard warning (this category is in warn mode, so the command runs): {}",
            decision.message
        );
        return Some(dict(vec![(
            "hookSpecificOutput",
            dict(vec![
                ("hookEventName", s("PreToolUse")),
                ("additionalContext", s(&warning)),
            ]),
        )]));
    }
    None
}
