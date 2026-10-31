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

//! The installer: install.py, function for function.
//!
//! Every function keeps its Python name and does what the Python one does,
//! down to the messages; see install.py's docstrings for the why. Where
//! install.py would raise, these return a PyErr of the same kind, caught (or
//! not) by the same callers.

use std::collections::BTreeMap;
use std::ffi::OsString;
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::time::Duration;

use agent_guard::classify::{gh_url, installer_problem, is_vitruvian_core_slug};
use agent_guard::hook::{now as log_now, write_log};
use agent_guard::paths::{basename, dirname, exists, isdir, isfile, join, realpath};
use agent_guard::pyutil::{is_space, py_repr_str, py_strip, take_chars, universal_newlines};
use agent_guard::pyval::{self, dict, loads, py_eq, s, JsonErr, PyVal};
use agent_guard::scope::names_vitruvian_core;
use agent_guard::tamper::{INSTALL_DIR_REL, STATE_DIR_REL};

use crate::argparse::{self, Parsed};
use crate::difflib::unified_diff;
use crate::pyjson::{
    decode_error, del, dumps_indent, empty_dict, get, get_mut, has_spaced_colon, iter, keys,
    no_attr, set, splitlines_keepends, PyErr, R,
};
use crate::shlex;
use crate::sys::{command_with_env, mkdtemp, oserror, oserror_kind, run, Ctx, RunErr};

// --- What the repo's hook files must say -------------------------------------
pub const CLAUDE_COMMAND: &str = "/bin/sh \"$CLAUDE_PROJECT_DIR/tools/agent-guard/hook.sh\"";
pub const AGY_COMMAND: &str = "/bin/sh ../tools/agent-guard/hook.sh";
pub const CLAUDE_SETTINGS_REL: &str = ".claude/settings.json";
pub const AGY_HOOKS_REL: &str = ".agents/hooks.json";
pub const LAUNCHER_REL: &str = "tools/agent-guard/hook.sh";

pub const COMMAND_MATCHER: &str = concat!(
    "^(Bash|Monitor",
    "|mcp__terminal__run_in_terminal",
    "|mcp__plugin_desktop-commander_desktop-commander__(start_process|interact_with_process)",
    "|mcp__ccd_pr__set_auto_merge",
    "|mcp__(kubernetes|Kubernetes_MCP_Server)__(kubectl_(apply|create|delete|patch|scale|rollout|generic)",
    "|exec_in_pod|(install|upgrade|uninstall)_helm_chart|node_management)",
    ")$"
);
pub const FILE_MATCHER: &str = concat!(
    "^(Edit|Write|MultiEdit|NotebookEdit",
    "|mcp__plugin_desktop-commander_desktop-commander__(write_file|edit_block|move_file|create_directory|write_pdf)",
    ")$"
);
pub const AGY_HOOK_NAME: &str = "agent-guard";
pub const AGY_MATCHER: &str = concat!(
    "run_command|shell_exec|send_command_input|manage_task|git_commit",
    "|write_to_file|replace_file_content|multi_replace_file_content|notebook_edit"
);
pub const HOOK_TIMEOUT: u64 = 10;

/// Environment markers that mean "this is an agent's shell, not James's".
pub const AGENT_MARKERS: [&str; 3] = ["CLAUDECODE", "ANTIGRAVITY_AGENT", "GEMINI_CLI"];

fn int(n: u64) -> PyVal {
    PyVal::Int(n.to_string())
}

/// agent-guard's two PreToolUse entries (.claude/settings.json, or the backstop's).
pub fn claude_entries(command: &str) -> PyVal {
    PyVal::List(vec![
        dict(vec![
            ("matcher", s(COMMAND_MATCHER)),
            (
                "hooks",
                PyVal::List(vec![dict(vec![
                    ("type", s("command")),
                    ("command", s(command)),
                    ("timeout", int(HOOK_TIMEOUT)),
                    ("onFailure", s("block")),
                ])]),
            ),
        ]),
        dict(vec![
            ("matcher", s(FILE_MATCHER)),
            (
                "hooks",
                PyVal::List(vec![dict(vec![
                    ("type", s("command")),
                    ("command", s(command)),
                    ("timeout", int(HOOK_TIMEOUT)),
                ])]),
            ),
        ]),
    ])
}

/// agent-guard's named hook for agy, in the grouped shape PreToolUse needs.
pub fn agy_entry(command: &str) -> PyVal {
    dict(vec![
        ("enabled", PyVal::Bool(true)),
        (
            "PreToolUse",
            PyVal::List(vec![dict(vec![
                ("matcher", s(AGY_MATCHER)),
                (
                    "hooks",
                    PyVal::List(vec![dict(vec![
                        ("type", s("command")),
                        ("command", s(command)),
                        ("timeout", int(HOOK_TIMEOUT)),
                    ])]),
                ),
            ])]),
        ),
    ])
}

// --- The per-user backstop ---------------------------------------------------
pub fn install_dir(home: &str) -> String {
    join(home, INSTALL_DIR_REL)
}

pub fn settings_path(home: &str) -> String {
    join(&join(home, ".claude"), "settings.json")
}

pub fn gemini_hooks_path(home: &str) -> String {
    join(&join(&join(home, ".gemini"), "config"), "hooks.json")
}

/// The environment variable that shows this is an agent session, if any.
pub fn agent_marker(env: &BTreeMap<OsString, OsString>) -> Option<String> {
    let nonempty = |name: &str| {
        env.get(&OsString::from(name))
            .map_or(false, |v| !v.is_empty())
    };
    for name in AGENT_MARKERS {
        if nonempty(name) {
            return Some(name.to_string());
        }
    }
    for (name, value) in env {
        let name = name.to_string_lossy();
        if name.starts_with("ANTIGRAVITY_") && !value.is_empty() {
            return Some(name.into_owned());
        }
    }
    None
}

/// `MARKER_RE.search(text)`: agent-guard/(agent_guard\.py|hook\.py|hook\.sh).
fn marker_re(text: &str) -> bool {
    [
        "agent-guard/agent_guard.py",
        "agent-guard/hook.py",
        "agent-guard/hook.sh",
    ]
    .iter()
    .any(|m| text.contains(m))
}

pub fn is_ours(handler: &PyVal) -> bool {
    match handler {
        PyVal::Dict(_) => {
            let cmd = handler.get("command").cloned().unwrap_or_else(|| s(""));
            marker_re(&cmd.py_str())
        }
        _ => false,
    }
}

fn hooks_list(entry: &PyVal) -> Option<&Vec<PyVal>> {
    match entry {
        PyVal::Dict(_) => match entry.get("hooks") {
            Some(PyVal::List(l)) => Some(l),
            _ => None,
        },
        _ => None,
    }
}

/// settings without any agent-guard handler; every other hook is kept as is.
pub fn strip_ours(settings: &PyVal) -> PyVal {
    let mut out = settings.clone();
    let Some(hooks @ PyVal::Dict(_)) = get_mut(&mut out, "hooks") else {
        return out;
    };
    let PyVal::Dict(items) = hooks else {
        unreachable!()
    };
    let mut new_items = Vec::new();
    for (event, entries) in std::mem::take(items) {
        let PyVal::List(list) = &entries else {
            new_items.push((event, entries));
            continue;
        };
        let mut kept = Vec::new();
        for entry in list {
            if let Some(hs) = hooks_list(entry) {
                let handlers: Vec<PyVal> = hs.iter().filter(|h| !is_ours(h)).cloned().collect();
                if handlers.is_empty() && hs.iter().any(is_ours) {
                    continue;
                }
                let mut e = entry.clone();
                set(&mut e, "hooks", PyVal::List(handlers));
                kept.push(e);
            } else {
                kept.push(entry.clone());
            }
        }
        if !kept.is_empty() {
            new_items.push((event, PyVal::List(kept)));
        } else if list.is_empty() {
            new_items.push((event, entries));
        }
    }
    let now_empty = new_items.is_empty();
    *items = new_items;
    if now_empty && settings.get("hooks").map_or(false, |h| h.truthy()) {
        del(&mut out, "hooks");
    }
    out
}

/// hooks.json without any agent-guard handler, grouped or flat.
pub fn strip_ours_gemini(hooks: &PyVal) -> PyVal {
    let mut out = hooks.clone();
    let mut drop_names = Vec::new();
    if let PyVal::Dict(items) = &mut out {
        for (name, spec) in items.iter_mut() {
            let PyVal::Dict(events) = spec else { continue };
            let mut removed = false;
            let mut new_events = Vec::new();
            for (event, entries) in std::mem::take(events) {
                let PyVal::List(list) = &entries else {
                    new_events.push((event, entries));
                    continue;
                };
                let mut kept = Vec::new();
                let mut changed = false;
                for entry in list {
                    if let Some(hs) = hooks_list(entry) {
                        let handlers: Vec<PyVal> =
                            hs.iter().filter(|h| !is_ours(h)).cloned().collect();
                        if handlers.len() != hs.len() {
                            changed = true;
                            if handlers.is_empty() {
                                continue;
                            }
                            let mut e = entry.clone();
                            set(&mut e, "hooks", PyVal::List(handlers));
                            kept.push(e);
                            continue;
                        }
                    } else if is_ours(entry) {
                        changed = true;
                        continue;
                    }
                    kept.push(entry.clone());
                }
                if changed {
                    removed = true;
                    if !kept.is_empty() {
                        new_events.push((event, PyVal::List(kept)));
                    }
                } else {
                    new_events.push((event, entries));
                }
            }
            *events = new_events;
            let any_list = events
                .iter()
                .any(|(_, v)| matches!(v, PyVal::List(l) if !l.is_empty()));
            if removed && !any_list {
                drop_names.push(name.clone());
            }
        }
    }
    for name in drop_names {
        del(&mut out, &name);
    }
    out
}

/// Serialise in the style the file already uses, so the diff is only our change.
pub fn dump(settings: &PyVal, like: &str) -> String {
    let sep = if has_spaced_colon(like) { " : " } else { ": " };
    let mut text = dumps_indent(settings, sep, false);
    if like.contains("\\/") {
        text = text.replace('/', "\\/");
    }
    if !like.is_empty() && !like.ends_with('\n') {
        text
    } else {
        text + "\n"
    }
}

fn read_error(e: &std::io::Error, path: &str) -> PyErr {
    PyErr::Other(oserror_kind(e), oserror(e, path, None))
}

/// `open(path, encoding="utf-8").read()`.
fn read_text(path: &str) -> R<String> {
    let bytes = fs::read(path).map_err(|e| read_error(&e, path))?;
    match String::from_utf8(bytes) {
        Ok(t) => Ok(universal_newlines(&t)),
        Err(e) => {
            let u = e.utf8_error();
            let at = u.valid_up_to();
            let b = e.as_bytes()[at];
            let why = match u.error_len() {
                None => "unexpected end of data",
                Some(_) if (0x80..0xc2).contains(&b) || b >= 0xf5 => "invalid start byte",
                Some(_) => "invalid continuation byte",
            };
            Err(PyErr::Other(
                "UnicodeDecodeError",
                format!(
                    "'utf-8' codec can't decode byte 0x{:02x} in position {}: {}",
                    b, at, why
                ),
            ))
        }
    }
}

pub fn read_settings(path: &str) -> R<(PyVal, String)> {
    if !exists(path) {
        return Ok((empty_dict(), String::new()));
    }
    let text = read_text(path)?;
    if py_strip(&text).is_empty() {
        return Ok((empty_dict(), text));
    }
    let data = match loads(&text) {
        Ok(d) => d,
        Err(JsonErr::Value) => {
            return Err(PyErr::Exit(format!(
                "agent-guard: {} is not valid JSON ({}); fix it first, nothing was changed",
                path,
                decode_error(&text)
            )))
        }
        Err(JsonErr::Recursion) => return Err(PyErr::Other(
            "RecursionError",
            "maximum recursion depth exceeded while decoding a JSON object from a unicode string"
                .into(),
        )),
    };
    if !data.is_dict() {
        return Err(PyErr::Exit(format!(
            "agent-guard: {} is not a JSON object; nothing was changed",
            path
        )));
    }
    Ok((data, text))
}

/// Write text to path through a temporary file; Err(str(OSError)).
pub fn write_atomic(ctx: &Ctx, path: &str, text: &str) -> Result<(), String> {
    if let Some(hook) = &ctx.write_hook {
        if let Some(err) = hook(path, text) {
            return Err(err);
        }
    }
    let tmp = format!("{}.agent-guard.tmp", path);
    let mode = if exists(path) {
        fs::metadata(path)
            .ok()
            .map(|m| m.permissions().mode() & 0o777)
    } else {
        None
    };
    fs::write(&tmp, text.as_bytes()).map_err(|e| oserror(&e, &tmp, None))?;
    if let Some(mode) = mode {
        fs::set_permissions(&tmp, fs::Permissions::from_mode(mode))
            .map_err(|e| oserror(&e, &tmp, None))?;
    }
    fs::rename(&tmp, path).map_err(|e| oserror(&e, &tmp, Some(path)))
}

/// `shutil.copy2(path, path.agent-guard-NOW.bak)`; Err(str(OSError)).
pub fn backup(path: &str, now: &str) -> Result<String, String> {
    let dest = format!("{}.agent-guard-{}.bak", path, now);
    fs::copy(path, &dest).map_err(|e| oserror(&e, path, None))?;
    if let Ok(meta) = fs::metadata(path) {
        if let (Ok(atime), Ok(mtime)) = (meta.accessed(), meta.modified()) {
            if let Ok(f) = fs::OpenOptions::new().write(true).open(&dest) {
                let _ = f.set_times(fs::FileTimes::new().set_accessed(atime).set_modified(mtime));
            }
        }
    }
    Ok(dest)
}

fn diff(old: &str, new: &str, name: &str) -> String {
    unified_diff(
        &splitlines_keepends(old),
        &splitlines_keepends(new),
        &format!("{} (now)", name),
        &format!("{} (after)", name),
    )
}

/// `['git', '-C', ...]` as Python's repr of the argument list.
fn argv_repr(argv: &[&str]) -> String {
    let items: Vec<String> = argv.iter().map(|a| py_repr_str(a)).collect();
    format!("[{}]", items.join(", "))
}

fn signal_name(sig: i32) -> String {
    let name = match sig {
        1 => "SIGHUP",
        2 => "SIGINT",
        3 => "SIGQUIT",
        6 => "SIGABRT",
        9 => "SIGKILL",
        11 => "SIGSEGV",
        13 => "SIGPIPE",
        14 => "SIGALRM",
        15 => "SIGTERM",
        _ => return format!("unknown signal {}", sig),
    };
    format!("<Signals.{}: {}>", name, sig)
}

/// The main (primary) checkout of the repo `workspace` belongs to, even from a worktree.
pub fn main_checkout(ctx: &Ctx, workspace: &str) -> R<String> {
    let argv = [
        "git",
        "-C",
        workspace,
        "rev-parse",
        "--path-format=absolute",
        "--git-common-dir",
    ];
    let mut cmd = command_with_env("git", &ctx.env);
    cmd.args(&argv[1..]);
    let not_a_checkout = |why: String| {
        PyErr::Exit(format!(
            "agent-guard: {} is not a git checkout ({})",
            workspace, why
        ))
    };
    let common = match run(cmd, "git", None, Duration::from_secs(30)) {
        Err(RunErr::Timeout) => {
            return Err(not_a_checkout(format!(
                "Command '{}' timed out after 30 seconds",
                argv_repr(&argv)
            )))
        }
        Err(RunErr::Os(msg, _)) => return Err(not_a_checkout(msg)),
        Ok(r) if r.code < 0 => {
            return Err(not_a_checkout(format!(
                "Command '{}' died with {}.",
                argv_repr(&argv),
                signal_name(-r.code)
            )))
        }
        Ok(r) if r.code != 0 => {
            return Err(not_a_checkout(format!(
                "Command '{}' returned non-zero exit status {}.",
                argv_repr(&argv),
                r.code
            )))
        }
        Ok(r) => py_strip(&String::from_utf8_lossy(&r.stdout)).to_string(),
    };
    if basename(&common) != ".git" {
        return Err(PyErr::Exit(format!(
            "agent-guard: {} has no main checkout (git dir {})",
            workspace, common
        )));
    }
    let main = dirname(&common);
    if !isfile(&join(&main, LAUNCHER_REL)) {
        return Err(PyErr::Exit(format!(
            "agent-guard: the main checkout {} has no {} yet; pull main there first",
            main, LAUNCHER_REL
        )));
    }
    Ok(main)
}

/// The backstop's whole command, kept IN the settings entry so it cannot go
/// missing (install.py's BACKSTOP_SCRIPT, byte for byte). $1 is the main checkout.
pub const BACKSTOP_SCRIPT: &str = r#"h="$1/tools/agent-guard/hook.sh"; [ -f "$h" ] && exec /bin/sh "$h"; in=$(cat); why="agent-guard: its launcher is missing from $1 (tools/agent-guard/hook.sh); James must reinstall the backstop or restore the checkout"; case $in in *"$1"/*|*"$1"\"*|*"$1"-worktrees/*) case $in in *\"toolCall\"*) printf "{\"decision\":\"deny\",\"reason\":\"%s\"}\n" "$why"; exit 0;; esac; echo "$why" >&2; exit 2;; esac; echo "$why; allowing this call, which is not in vitruvian-core" >&2; exit 0"#;

pub fn backstop_command(main: &str) -> R<String> {
    if main
        .chars()
        .any(|c| matches!(c, '"' | '\\' | '\'' | '\n' | '$' | '`'))
    {
        return Err(PyErr::Exit(format!(
            "agent-guard: the main checkout's path {} has a quote, backslash, $ or backtick; \
the backstop cannot quote it safely",
            py_repr_str(main)
        )));
    }
    Ok(format!(
        "/bin/sh -c '{}' agent-guard-backstop {}",
        BACKSTOP_SCRIPT,
        shlex::quote(main)
    ))
}

/// The main checkout a backstop command runs (its last word), or "".
pub fn backstop_main(command: &str) -> String {
    match shlex::split(command) {
        Some(words) if words.len() >= 4 && words[words.len() - 2] == "agent-guard-backstop" => {
            words[words.len() - 1].clone()
        }
        _ => String::new(),
    }
}

/// settings with the backstop's two entries in place of any agent-guard entry.
pub fn with_ours(settings: &PyVal, command: &str) -> R<PyVal> {
    let mut out = strip_ours(settings);
    if out.get("hooks").is_none() {
        set(&mut out, "hooks", empty_dict());
    }
    let hooks = get_mut(&mut out, "hooks").unwrap();
    if !hooks.is_dict() {
        return Err(no_attr(hooks, "setdefault"));
    }
    if hooks.get("PreToolUse").is_none() {
        set(hooks, "PreToolUse", PyVal::List(Vec::new()));
    }
    match get_mut(hooks, "PreToolUse").unwrap() {
        PyVal::List(l) => {
            if let PyVal::List(ours) = claude_entries(command) {
                l.extend(ours);
            }
        }
        other => return Err(no_attr(other, "extend")),
    }
    Ok(out)
}

/// hooks.json with the backstop's named hook, kept where it already was.
pub fn gemini_with_ours(hooks: &PyVal, command: &str) -> PyVal {
    let stripped = strip_ours_gemini(hooks);
    let mut out = empty_dict();
    for name in keys(hooks) {
        if name == AGY_HOOK_NAME {
            set(&mut out, &name, agy_entry(command));
        } else if let Some(v) = stripped.get(&name) {
            set(&mut out, &name, v.clone());
        }
    }
    if out.get(AGY_HOOK_NAME).is_none() {
        set(&mut out, AGY_HOOK_NAME, agy_entry(command));
    }
    out
}

/// The agent-guard commands in the two user files: (Claude Code's, agy's).
pub fn backstop_commands(home: &str) -> R<(Vec<String>, Vec<String>)> {
    let mut found: [Vec<String>; 2] = [Vec::new(), Vec::new()];
    for (i, path) in [settings_path(home), gemini_hooks_path(home)]
        .iter()
        .enumerate()
    {
        let data = match read_settings(path) {
            Ok((d, _)) => d,
            Err(PyErr::Exit(_)) => continue,
            Err(e) => return Err(e),
        };
        let mut hs = Vec::new();
        handlers(&data, &mut hs);
        for h in hs {
            let cmd = h.get_or_none("command");
            if is_ours(&h) && !found[i].iter().any(|f| py_eq(&cmd, &s(f))) {
                found[i].push(cmd.py_str());
            }
        }
    }
    let [c, a] = found;
    Ok((c, a))
}

/// Every hook handler in a settings or hooks.json object, grouped or flat.
fn handlers(data: &PyVal, out: &mut Vec<PyVal>) {
    match data {
        PyVal::Dict(items) => {
            if data.has("command") && data.has("type") {
                out.push(data.clone());
            }
            for (_, v) in items {
                handlers(v, out);
            }
        }
        PyVal::List(l) => {
            for v in l {
                handlers(v, out);
            }
        }
        _ => {}
    }
}

/// Write (or update) the backstop; migrate and delete the old per-user copy.
pub fn install(ctx: &Ctx, home: &str, workspace: &str, now: &str, dry_run: bool) -> R<i32> {
    let main = main_checkout(ctx, workspace)?;
    let command = backstop_command(&main)?;
    let (sp, gp) = (settings_path(home), gemini_hooks_path(home));
    let (settings, old_text) = read_settings(&sp)?;
    let new_text = dump(&with_ours(&settings, &command)?, &old_text);
    let agy = isdir(&join(home, ".gemini"));
    let (mut g_old, mut g_new) = (String::new(), String::new());
    if agy {
        let (gemini, text) = read_settings(&gp)?;
        g_new = dump(&gemini_with_ours(&gemini, &command), &text);
        g_old = text;
    }
    let idir = install_dir(home);
    let mut changes = vec![(sp.clone(), old_text, new_text)];
    if agy {
        changes.push((gp.clone(), g_old, g_new));
    }
    changes.retain(|c| c.1 != c.2);
    if dry_run {
        ctx.print(&format!("backstop command: {}", command));
        for (path, old, new) in &changes {
            ctx.print(&diff(old, new, path));
        }
        if !agy {
            ctx.print("Antigravity: ~/.gemini not found, so its hooks are left alone");
        }
        if isdir(&idir) {
            ctx.print(&format!("would remove the old per-user copy {}", idir));
        }
        if changes.is_empty() && !isdir(&idir) {
            ctx.print("the backstop is already installed and up to date");
        }
        return Ok(0);
    }
    if changes.is_empty() && !isdir(&idir) {
        ctx.print(&format!(
            "the backstop is already installed and up to date ({})",
            command
        ));
        return Ok(0);
    }
    let mut backups = Vec::new();
    let existed: Vec<bool> = changes.iter().map(|c| exists(&c.0)).collect();
    let mut written: Vec<(usize, String)> = Vec::new();
    let put_back = |written: &[(usize, String)]| -> R<()> {
        for (i, old) in written {
            let path = &changes[*i].0;
            if existed[*i] {
                write_atomic(ctx, path, old).map_err(|e| PyErr::Other("OSError", e))?;
            } else if exists(path) {
                fs::remove_file(path)
                    .map_err(|e| PyErr::Other(oserror_kind(&e), oserror(&e, path, None)))?;
            }
        }
        Ok(())
    };
    let mut failure = None;
    for (i, (path, old, new)) in changes.iter().enumerate() {
        let parent = dirname(path);
        if let Err(e) = fs::create_dir_all(&parent) {
            failure = Some(oserror(&e, &parent, None));
            break;
        }
        if existed[i] {
            match backup(path, now) {
                Ok(b) => backups.push(b),
                Err(e) => {
                    failure = Some(e);
                    break;
                }
            }
        }
        written.push((i, old.clone()));
        if let Err(e) = write_atomic(ctx, path, new) {
            failure = Some(e);
            break;
        }
    }
    if let Some(exc) = failure {
        put_back(&written)?;
        ctx.eprint(&format!(
            "agent-guard: writing failed ({}); every file was put back as it was.\n",
            exc
        ));
        return Ok(4);
    }
    let mut problems = written_problems(home, &command, agy)?;
    if problems.is_empty() {
        problems = self_test_command(ctx, &command, home, agy)?;
    }
    if !problems.is_empty() {
        put_back(&written)?;
        for p in &problems {
            ctx.eprint(&format!("PROBLEM: {}\n", p));
        }
        ctx.eprint(
            "agent-guard: the backstop failed its self-test; both files were put back as \
they were and nothing was removed.\n",
        );
        return Ok(4);
    }
    for (path, _, _) in &changes {
        ctx.print(&format!("backstop written to {}", path));
    }
    if !backups.is_empty() {
        ctx.print(&format!("backups: {}", backups.join(", ")));
    }
    if isdir(&idir) {
        fs::remove_dir_all(&idir)
            .map_err(|e| PyErr::Other(oserror_kind(&e), oserror(&e, &idir, None)))?;
        ctx.print(&format!(
            "removed the old per-user copy {} (the log is kept)",
            idir
        ));
    }
    ctx.print(&format!(
        "backstop runs {}, which loads the guard from origin/main:",
        join(&main, LAUNCHER_REL)
    ));
    ctx.print(&format!(
        "guard updates arrive with a pull; reinstall only if you move {}.",
        main
    ));
    ctx.print(
        "If that file goes missing, calls in vitruvian-core are refused and every other \
repo's are let through.",
    );
    Ok(0)
}

/// `[e for e in entries if any(_is_ours(h) for h in e.get("hooks", []))]`,
/// with `isinstance(e, dict)` first where install.py checks it.
fn ours_in(entries: &PyVal, check_dict: bool) -> R<Vec<PyVal>> {
    let mut out = Vec::new();
    for e in iter(entries)? {
        if check_dict && !e.is_dict() {
            continue;
        }
        let hs = get(&e, "hooks")?
            .cloned()
            .unwrap_or(PyVal::List(Vec::new()));
        if iter(&hs)?.iter().any(is_ours) {
            out.push(e);
        }
    }
    Ok(out)
}

/// Run `body`, turning SystemExit and AttributeError into problems (as
/// `except (SystemExit, AttributeError) as exc: problems.append(str(exc))`).
fn catching(problems: &mut Vec<String>, body: impl FnOnce(&mut Vec<String>) -> R<()>) -> R<()> {
    match body(problems) {
        Ok(()) => Ok(()),
        Err(e @ (PyErr::Exit(_) | PyErr::Attr(_))) => {
            problems.push(e.text());
            Ok(())
        }
        Err(e) => Err(e),
    }
}

/// Read the files back: agent-guard's entries must be exactly the standard ones.
pub fn written_problems(home: &str, command: &str, agy: bool) -> R<Vec<String>> {
    let mut problems = Vec::new();
    catching(&mut problems, |problems| {
        let (settings, _) = read_settings(&settings_path(home))?;
        let hooks = match settings.get("hooks") {
            Some(h) if h.truthy() => h.clone(),
            _ => empty_dict(),
        };
        let pre = get(&hooks, "PreToolUse")?
            .cloned()
            .unwrap_or(PyVal::List(Vec::new()));
        let ours = ours_in(&pre, true)?;
        if !py_eq(&PyVal::List(ours), &claude_entries(command)) {
            problems.push(format!(
                "{} did not read back as the standard entries",
                settings_path(home)
            ));
        }
        if agy {
            let (hooks, _) = read_settings(&gemini_hooks_path(home))?;
            if !py_eq(&hooks.get_or_none(AGY_HOOK_NAME), &agy_entry(command)) {
                problems.push(format!(
                    "{} did not read back as the standard hook",
                    gemini_hooks_path(home)
                ));
            }
        }
        Ok(())
    })?;
    Ok(problems)
}

/// A stand-in checkout to aim the sample commands at.
fn scratch_checkout(ctx: &Ctx) -> R<String> {
    let scratch =
        mkdtemp(&ctx.tempdir(), "agent-guard-check-").map_err(|e| PyErr::Other("OSError", e))?;
    let module = join(&scratch, "MODULE.bazel");
    fs::write(&module, "module(name = \"vitruvian_core\")\n")
        .map_err(|e| PyErr::Other(oserror_kind(&e), oserror(&e, &module, None)))?;
    Ok(scratch)
}

/// Run a backstop command on sample calls, from folders outside any checkout.
pub fn self_test_command(ctx: &Ctx, command: &str, home: &str, agy: bool) -> R<Vec<String>> {
    let mut problems = Vec::new();
    let scratch = scratch_checkout(ctx)?;
    let hook_dir = match mkdtemp(&ctx.tempdir(), "agent-guard-check-hookdir-") {
        Ok(d) => d,
        Err(e) => {
            let _ = fs::remove_dir_all(&scratch);
            return Err(PyErr::Other("OSError", e));
        }
    };
    let result = (|| -> R<()> {
        let mut env = ctx.env.clone();
        env.insert("HOME".into(), home.into());
        env.remove(&OsString::from("AGENT_GUARD_POLICY"));
        env.remove(&OsString::from("CLAUDE_PROJECT_DIR"));
        let mut cases = vec![
            ("claude-code", "git status", "allow"),
            ("claude-code", "git stash", "deny"),
        ];
        if agy {
            cases.push(("antigravity", "git status", "allow"));
            cases.push(("antigravity", "go vet ./...", "deny"));
        }
        for (agent, sample, want) in cases {
            let payload = if agent == "antigravity" {
                agy_payload(sample, &scratch)
            } else {
                claude_payload(sample, &scratch)
            };
            let (got, _out, err) = run_hook(command, &payload, &hook_dir, &env)?;
            if got.as_deref() != Some(want) {
                problems.push(format!(
                    "the backstop ({}) said {} to `{}` ({} format), expected {}{}",
                    command,
                    got.as_deref().unwrap_or("nothing (it failed)"),
                    sample,
                    agent,
                    want,
                    if err.is_empty() {
                        String::new()
                    } else {
                        format!(": {}", err)
                    }
                ));
            }
        }
        Ok(())
    })();
    let _ = fs::remove_dir_all(&scratch);
    let _ = fs::remove_dir_all(&hook_dir);
    result?;
    Ok(problems)
}

/// Problems with the per-user backstop (empty: fine).
pub fn check_backstop(ctx: &Ctx, home: &str) -> R<Vec<String>> {
    let mut problems = Vec::new();
    let (claude_cmds, agy_cmds) = backstop_commands(home)?;
    let all: Vec<String> = claude_cmds.iter().chain(agy_cmds.iter()).cloned().collect();
    let agy = isdir(&join(home, ".gemini"));
    let fix = "run `bazel run //tools/agent-guard:install` (an agent may)";
    let james = "run `bazel run //tools/agent-guard:install` from your own terminal";
    if isdir(&install_dir(home)) || all.iter().any(|c| c.contains(INSTALL_DIR_REL)) {
        problems.push(format!(
            "the old per-user copy ({}) is still installed: {} to migrate",
            install_dir(home),
            james
        ));
        return Ok(problems);
    }
    if claude_cmds.is_empty() || (agy && agy_cmds.is_empty()) {
        problems.push(format!(
            "no per-user backstop in {}: sessions started outside vitruvian-core are unguarded; {}",
            if claude_cmds.is_empty() {
                settings_path(home)
            } else {
                gemini_hooks_path(home)
            },
            fix
        ));
        return Ok(problems);
    }
    let mut seen: Vec<&String> = Vec::new();
    for cmd in &all {
        if seen.contains(&cmd) {
            continue;
        }
        seen.push(cmd);
        let main = backstop_main(cmd);
        let launcher = if main.is_empty() {
            String::new()
        } else {
            join(&main, LAUNCHER_REL)
        };
        if main.is_empty() {
            problems.push(format!(
                "the backstop's command is not one this installer writes: {} again",
                fix
            ));
        } else if !isfile(&launcher) {
            problems.push(format!(
                "the backstop runs {}, which is gone (did the main checkout move?): calls in \
vitruvian-core are refused until you {} again",
                launcher,
                james.splitn(2, "run ").nth(1).unwrap_or("")
            ));
        }
    }
    catching(&mut problems, |problems| {
        let (settings, _) = read_settings(&settings_path(home))?;
        let hooks = settings.get("hooks").cloned().unwrap_or_else(empty_dict);
        let pre = get(&hooks, "PreToolUse")?
            .cloned()
            .unwrap_or(PyVal::List(Vec::new()));
        if !py_eq(
            &PyVal::List(ours_in(&pre, false)?),
            &claude_entries(&claude_cmds[0]),
        ) {
            problems.push(format!(
                "the backstop's entries in {} differ from the installer's: {}",
                settings_path(home),
                fix
            ));
        }
        if agy {
            let (hooks, _) = read_settings(&gemini_hooks_path(home))?;
            if !py_eq(&hooks.get_or_none(AGY_HOOK_NAME), &agy_entry(&agy_cmds[0])) {
                problems.push(format!(
                    "the backstop's hook in {} differs from the installer's: {}",
                    gemini_hooks_path(home),
                    fix
                ));
            }
        }
        Ok(())
    })?;
    if problems.is_empty() {
        problems.extend(self_test_command(ctx, &claude_cmds[0], home, agy)?);
    }
    Ok(problems)
}

/// Remove the backstop (or the old copy) and only agent-guard's entries from both user files.
pub fn uninstall(ctx: &Ctx, home: &str, now: &str, dry_run: bool) -> R<i32> {
    let os_err = |e: String| PyErr::Other("OSError", e);
    let sp = settings_path(home);
    let (settings, old_text) = read_settings(&sp)?;
    let new = strip_ours(&settings);
    let changed = !py_eq(&new, &settings);
    let new_text = if changed {
        dump(&new, &old_text)
    } else {
        old_text.clone()
    };
    let gp = gemini_hooks_path(home);
    let gemini = match read_settings(&gp) {
        Ok(g) => Some(g),
        Err(PyErr::Exit(msg)) => {
            ctx.eprint(&format!("{}; leaving it alone\n", msg));
            None
        }
        Err(e) => return Err(e),
    };
    let mut g_changed = false;
    let mut g_new_text = String::new();
    if let Some((g_data, g_old)) = &gemini {
        let g_new = strip_ours_gemini(g_data);
        g_changed = !py_eq(&g_new, g_data);
        g_new_text = if g_changed {
            dump(&g_new, g_old)
        } else {
            g_old.clone()
        };
    }
    let idir = install_dir(home);
    if dry_run {
        ctx.print(&if changed {
            diff(&old_text, &new_text, &sp)
        } else {
            format!("{}: no agent-guard hook to remove", sp)
        });
        if let Some((_, g_old)) = &gemini {
            ctx.print(&if g_changed {
                diff(g_old, &g_new_text, &gp)
            } else {
                format!("{}: no agent-guard hook to remove", gp)
            });
        }
        ctx.print(&if isdir(&idir) {
            format!("would remove {}", idir)
        } else {
            format!("no per-user copy at {}", idir)
        });
        return Ok(0);
    }
    if changed {
        let b = backup(&sp, now).map_err(os_err)?;
        write_atomic(ctx, &sp, &new_text).map_err(os_err)?;
        ctx.print(&format!(
            "removed the agent-guard hooks from {}, other hooks kept (backup: {})",
            sp, b
        ));
    } else {
        ctx.print(&format!("{}: no agent-guard hook to remove", sp));
    }
    if gemini.is_some() {
        if g_changed {
            let b = backup(&gp, now).map_err(os_err)?;
            write_atomic(ctx, &gp, &g_new_text).map_err(os_err)?;
            ctx.print(&format!(
                "removed the agent-guard hook from {}, other hooks kept (backup: {})",
                gp, b
            ));
        } else {
            ctx.print(&format!("{}: no agent-guard hook to remove", gp));
        }
    }
    if isdir(&idir) {
        fs::remove_dir_all(&idir)
            .map_err(|e| PyErr::Other(oserror_kind(&e), oserror(&e, &idir, None)))?;
        ctx.print(&format!(
            "removed {} (the log in ~/{} is kept)",
            idir, STATE_DIR_REL
        ));
    } else {
        ctx.print(&format!("no per-user copy at {}", idir));
    }
    ctx.print(
        "the backstop is gone: sessions started inside vitruvian-core are still guarded by its own \
hook files, sessions started anywhere else are not.",
    );
    Ok(0)
}

// --- Agents installing -------------------------------------------------------
fn git_out(ctx: &Ctx, cwd: &str, args: &[&str]) -> Option<Vec<u8>> {
    let mut cmd = command_with_env("git", &ctx.env);
    cmd.arg("-C").arg(cwd).args(args);
    match run(cmd, "git", None, Duration::from_secs(30)) {
        Ok(r) if r.code == 0 => Some(r.stdout),
        _ => None,
    }
}

/// owner/name of the main checkout's origin, as configured (no insteadOf rewriting).
pub fn origin_slug(ctx: &Ctx, main: &str) -> String {
    let url = git_out(ctx, main, &["config", "--get", "remote.origin.url"]).unwrap_or_default();
    let url = String::from_utf8_lossy(&url);
    match gh_url(py_strip(&url)) {
        Some((owner, name)) => {
            let name = name.strip_suffix(".git").unwrap_or(&name).to_string();
            format!("{}/{}", owner, name)
        }
        None => String::new(),
    }
}

/// Why this is not the installer `bazel run` builds from workspace ("" if it is).
///
/// install.py checked it ran from `<...>/install.runfiles/` as a link to the
/// workspace's own install.py. A compiled binary carries no link back to its
/// sources, so the honest equivalent is what `bazel run` itself leaves:
/// BUILD_WORKSPACE_DIRECTORY names this workspace, and the program is the
/// one Bazel built for :install_rs (`.../bazel-out/<config>/bin/tools/
/// agent-guard/install_rs`). Like install.py's check this is the second line:
/// the guard's installer_problem (every installer source in the checkout is
/// origin/main's, no run_under) is the first.
pub fn runfiles_problem(ctx: &Ctx, workspace: &str) -> String {
    let exe = realpath(&ctx.running_from);
    let built = match exe.rfind("/bazel-out/") {
        Some(i) => match exe[i + "/bazel-out/".len()..].split_once('/') {
            Some((config, rest)) => {
                !config.is_empty() && rest == "bin/tools/agent-guard/install_rs"
            }
            None => false,
        },
        None => false,
    };
    let bwd = ctx.var("BUILD_WORKSPACE_DIRECTORY").unwrap_or_default();
    if !built || bwd.is_empty() || realpath(&bwd) != realpath(workspace) {
        return format!(
            "this installer ({}) is not the one `bazel run //tools/agent-guard:install` builds from {}",
            ctx.running_from, workspace
        );
    }
    String::new()
}

/// (the main checkout, "") if an agent may install the backstop, else (main or None, why not).
pub fn agent_check(ctx: &Ctx, home: &str, workspace: &str) -> R<(Option<String>, String)> {
    if workspace.is_empty() {
        return Ok((
            None,
            "run it through `bazel run` (no checkout given)".into(),
        ));
    }
    let mut why = runfiles_problem(ctx, workspace);
    if why.is_empty() {
        why = installer_problem(workspace, home);
    }
    if !why.is_empty() {
        return Ok((None, why));
    }
    let main = match main_checkout(ctx, workspace) {
        Ok(m) => m,
        Err(PyErr::Exit(msg)) => return Ok((None, msg)),
        Err(e) => return Err(e),
    };
    let refuse = |why: String| Ok((Some(main.clone()), why));
    // (a) The real vitruvian-core: a primary checkout declaring the module,
    // with origin on GitHub's VitruvianSoftware/vitruvian-core.
    if !isdir(&join(&main, ".git")) {
        return refuse(format!(
            "{} is not a primary checkout (no .git folder)",
            main
        ));
    }
    // OSError reads as "" (install.py's except OSError); a decode error escapes.
    let module = match read_text(&join(&main, "MODULE.bazel")) {
        Ok(text) => text,
        Err(e @ PyErr::Other("UnicodeDecodeError", _)) => return Err(e),
        Err(_) => String::new(),
    };
    if !names_vitruvian_core(&module) {
        return refuse(format!(
            "{} is not a vitruvian-core checkout (its MODULE.bazel)",
            main
        ));
    }
    let slug = origin_slug(ctx, &main);
    if !is_vitruvian_core_slug(&slug) {
        return refuse(format!(
            "{}'s origin is {}, not github.com/VitruvianSoftware/vitruvian-core",
            main,
            if slug.is_empty() {
                "missing or not GitHub"
            } else {
                &slug
            }
        ));
    }
    // (b) What the backstop will run is what main has reviewed.
    for rel in [LAUNCHER_REL, "tools/agent-guard/agent_guard.py"] {
        let Some(want) = git_out(
            ctx,
            &main,
            &["cat-file", "blob", &format!("origin/main:{}", rel)],
        ) else {
            return refuse(format!(
                "{} has no origin/main:{} to compare with; `git fetch` there first",
                main, rel
            ));
        };
        let have = fs::read(join(&main, rel)).ok();
        if have.as_ref() != Some(&want) {
            return refuse(format!(
                "{} in the main checkout {} differs from origin/main's; the backstop would \
run unreviewed code. Bring that checkout up to date with main first",
                rel, main
            ));
        }
    }
    // The first switch from the old copied install, and moving the backstop
    // to another checkout, are James's.
    let (claude_cmds, agy_cmds) = backstop_commands(home)?;
    let all: Vec<String> = claude_cmds.into_iter().chain(agy_cmds).collect();
    if isdir(&install_dir(home)) || all.iter().any(|c| c.contains(INSTALL_DIR_REL)) {
        return refuse(format!(
            "the old copied install ({}) is still in place; the first switch from it is \
James's, from his own terminal",
            install_dir(home)
        ));
    }
    for cmd in &all {
        let current = backstop_main(cmd);
        if !current.is_empty() && current != main {
            return refuse(format!(
                "the backstop runs the checkout {}, not {}; moving it is James's, from his \
own terminal",
                current, main
            ));
        }
    }
    Ok((Some(main.clone()), String::new()))
}

/// One line in agent-guard's log for each install an agent runs.
pub fn log_agent_install(
    ctx: &Ctx,
    home: &str,
    marker: &str,
    main: Option<&str>,
    outcome: &str,
    why: &str,
) {
    let agent = if marker == "CLAUDECODE" {
        "claude-code"
    } else if marker.starts_with("ANTIGRAVITY_") {
        "antigravity"
    } else {
        "gemini-cli"
    };
    let marker_value = ctx.var(marker).unwrap_or_default();
    let session = ctx
        .var("CLAUDE_CODE_SESSION_ID")
        .filter(|v| !v.is_empty())
        .unwrap_or_else(|| marker_value.clone());
    write_log(
        home,
        &dict(vec![
            ("ts", s(&log_now())),
            ("agent", s(agent)),
            ("event", s("agent-install")),
            ("tool", s("install.py")),
            ("category", s("guard-config")),
            ("op", s("bazel run //tools/agent-guard:install")),
            (
                "decision",
                s(if outcome == "refused" {
                    "deny"
                } else {
                    "allow"
                }),
            ),
            ("outcome", s(outcome)),
            ("reason", s(&take_chars(why, 500))),
            ("main", s(main.unwrap_or(""))),
            (
                "marker",
                s(&format!("{}={}", marker, take_chars(&marker_value, 64))),
            ),
            ("session", s(&take_chars(&session, 64))),
            ("source", s("install.py")),
        ]),
    );
}

pub fn agent_install(ctx: &Ctx, home: &str, workspace: &str, now: &str, marker: &str) -> R<i32> {
    let (main, why) = agent_check(ctx, home, workspace)?;
    if !why.is_empty() {
        log_agent_install(ctx, home, marker, main.as_deref(), "refused", &why);
        ctx.eprint(&format!(
            "agent-guard: not installing the backstop from an agent session ({} is set): {}.\n",
            marker, why
        ));
        return Ok(2);
    }
    let rc = match install(ctx, home, workspace, now, false) {
        Ok(rc) => rc,
        Err(PyErr::Exit(msg)) => {
            log_agent_install(ctx, home, marker, main.as_deref(), "failed", &msg);
            return Err(PyErr::Exit(msg));
        }
        Err(e) => return Err(e),
    };
    let outcome = if rc == 0 {
        "installed".to_string()
    } else {
        format!("failed (rc {})", rc)
    };
    log_agent_install(ctx, home, marker, main.as_deref(), &outcome, "");
    Ok(rc)
}

// --- --check ------------------------------------------------------------------
/// Problems with agent-guard's entries in the checkout's two hook files (empty: fine).
pub fn check_wiring(workspace: &str) -> R<Vec<String>> {
    let mut problems = Vec::new();
    let path = join(workspace, CLAUDE_SETTINGS_REL);
    let settings = match read_settings(&path) {
        Ok((d, _)) => d,
        Err(PyErr::Exit(msg)) => {
            problems.push(msg);
            empty_dict()
        }
        Err(e) => return Err(e),
    };
    if !matches!(settings.get("disableAllHooks"), Some(PyVal::Bool(false))) {
        problems.push(format!("{}: \"disableAllHooks\": false is missing", path));
    }
    let hooks = match settings.get("hooks") {
        Some(h @ PyVal::Dict(_)) => h.clone(),
        _ => empty_dict(),
    };
    let entries = match hooks.get("PreToolUse") {
        Some(l @ PyVal::List(_)) => l.clone(),
        _ => PyVal::List(Vec::new()),
    };
    let ours = ours_in(&entries, true)?;
    if !py_eq(&PyVal::List(ours), &claude_entries(CLAUDE_COMMAND)) {
        problems.push(format!(
            "{}: agent-guard's two PreToolUse entries are missing or differ from the installer's \
claude_entries() (want {})",
            path,
            pyval::dumps(&claude_entries(CLAUDE_COMMAND), false)
        ));
    }
    let path = join(workspace, AGY_HOOKS_REL);
    let hooks_json = match read_settings(&path) {
        Ok((d, _)) => d,
        Err(PyErr::Exit(msg)) => {
            problems.push(msg);
            empty_dict()
        }
        Err(e) => return Err(e),
    };
    if !exists(&path) {
        problems.push(format!("{} is missing", path));
    } else if !py_eq(
        &hooks_json.get_or_none(AGY_HOOK_NAME),
        &agy_entry(AGY_COMMAND),
    ) {
        problems.push(format!(
            "{}: the {} hook is missing or differs from the installer's agy_entry() (want {})",
            path,
            py_repr_str(AGY_HOOK_NAME),
            pyval::dumps(&agy_entry(AGY_COMMAND), false)
        ));
    }
    if !isfile(&join(workspace, LAUNCHER_REL)) {
        problems.push(format!("{} is missing", join(workspace, LAUNCHER_REL)));
    }
    Ok(problems)
}

/// agy 1.4.0's real PreToolUse payload shape: no top-level cwd or session_id.
pub fn agy_payload(command: &str, cwd: &str) -> PyVal {
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
                        ("WaitMsBeforeAsync", int(5000)),
                        ("toolAction", s("Running command")),
                        ("toolSummary", s("agent-guard check")),
                    ]),
                ),
            ]),
        ),
        ("stepIdx", int(0)),
        ("conversationId", s("agent-guard-check")),
        ("workspacePaths", PyVal::List(vec![s(cwd)])),
        ("transcriptPath", s(&join(cwd, "transcript.jsonl"))),
        ("artifactDirectoryPath", s(cwd)),
        ("modelName", s("auto")),
    ])
}

pub fn claude_payload(command: &str, cwd: &str) -> PyVal {
    dict(vec![
        ("session_id", s("agent-guard-check")),
        ("transcript_path", s(&join(cwd, "transcript.jsonl"))),
        ("cwd", s(cwd)),
        ("permission_mode", s("default")),
        ("hook_event_name", s("PreToolUse")),
        ("tool_name", s("Bash")),
        (
            "tool_input",
            dict(vec![
                ("command", s(command)),
                ("description", s("agent-guard check")),
            ]),
        ),
        ("tool_use_id", s("toolu_agent_guard_check")),
    ])
}

/// The last n characters of text (`text[-n:]`).
fn last_chars(text: &str, n: usize) -> String {
    let count = text.chars().count();
    text.chars().skip(count.saturating_sub(n)).collect()
}

/// (decision or None if the hook failed, raw stdout, stderr), run as the agent runs it.
pub fn run_hook(
    command: &str,
    payload: &PyVal,
    cwd: &str,
    env: &BTreeMap<OsString, OsString>,
) -> R<(Option<String>, String, String)> {
    let mut cmd = command_with_env("/bin/sh", env);
    cmd.arg("-c").arg(command).current_dir(cwd);
    let input = pyval::dumps(payload, false).into_bytes();
    let r = match run(
        cmd,
        "/bin/sh",
        Some(input),
        Duration::from_secs(HOOK_TIMEOUT),
    ) {
        Ok(r) => r,
        Err(RunErr::Timeout) => {
            return Ok((
                None,
                String::new(),
                format!("timed out after {}s", HOOK_TIMEOUT),
            ))
        }
        Err(RunErr::Os(_, kind)) => {
            // Popen reports a missing cwd as that folder.
            return Err(PyErr::Other(
                kind,
                format!("[Errno 2] No such file or directory: {}", py_repr_str(cwd)),
            ));
        }
    };
    let out = py_strip(&String::from_utf8_lossy(&r.stdout)).to_string();
    let err = py_strip(&String::from_utf8_lossy(&r.stderr)).to_string();
    if r.code != 0 {
        let tail = last_chars(&err, 400);
        return Ok((None, out, format!("exit {}: {}", r.code, tail)));
    }
    if out.is_empty() {
        return Ok((Some("allow".into()), out, err));
    }
    let not_json = |out: String, err: String| {
        let why = format!(
            "printed something that is not hook JSON: {}",
            py_repr_str(&take_chars(&out, 200))
        );
        let _ = err;
        Ok((None, out, why))
    };
    let data = match loads(&out) {
        Ok(d) => d,
        Err(JsonErr::Value) => return not_json(out, err),
        Err(JsonErr::Recursion) => return Err(PyErr::Other(
            "RecursionError",
            "maximum recursion depth exceeded while decoding a JSON object from a unicode string"
                .into(),
        )),
    };
    let decision = if payload.has("toolCall") {
        match &data {
            PyVal::Dict(_) => data.get("decision").cloned(),
            _ => None,
        }
    } else {
        match data.get("hookSpecificOutput") {
            Some(inner @ PyVal::Dict(_)) => inner.get("permissionDecision").cloned(),
            _ => None,
        }
    };
    match decision {
        Some(d) => Ok((Some(d.py_str()), out, err)),
        None => not_json(out, err),
    }
}

/// `re.search(r"not origin/main's copy: (.*)|agent-guard: running (origin/main:\S+)", err)`.
fn answered_by(err: &str) -> Option<String> {
    let t: Vec<char> = err.chars().collect();
    let a: Vec<char> = "not origin/main's copy: ".chars().collect();
    let b: Vec<char> = "agent-guard: running origin/main:".chars().collect();
    for i in 0..t.len() {
        if t[i..].starts_with(&a) {
            let start = i + a.len();
            let end = t[start..]
                .iter()
                .position(|&c| c == '\n')
                .map_or(t.len(), |p| start + p);
            return Some(t[start..end].iter().collect());
        }
        if t[i..].starts_with(&b) {
            let from = i + "agent-guard: running ".chars().count();
            let mut end = i + b.len();
            while end < t.len() && !is_space(t[end]) {
                end += 1;
            }
            if end > i + b.len() {
                return Some(t[from..end].iter().collect());
            }
        }
    }
    None
}

/// Run the checkout's launcher on real payloads. (problems, the sources that answered)
pub fn self_test(ctx: &Ctx, workspace: &str, home: &str) -> R<(Vec<String>, Vec<String>)> {
    let mut problems = Vec::new();
    let mut sources: Vec<String> = Vec::new();
    let scratch = scratch_checkout(ctx)?;
    let result = (|| -> R<()> {
        let mut env = ctx.env.clone();
        env.insert("HOME".into(), home.into());
        env.insert("CLAUDE_PROJECT_DIR".into(), workspace.into());
        env.insert("AGENT_GUARD_ANNOUNCE".into(), "1".into());
        env.remove(&OsString::from("AGENT_GUARD_POLICY"));
        let agy_dir = join(workspace, ".agents");
        let cases = [
            (
                "claude-code",
                CLAUDE_COMMAND,
                workspace.to_string(),
                "git status",
                "allow",
            ),
            (
                "claude-code",
                CLAUDE_COMMAND,
                workspace.to_string(),
                "git stash",
                "deny",
            ),
            (
                "antigravity",
                AGY_COMMAND,
                agy_dir.clone(),
                "git status",
                "allow",
            ),
            (
                "antigravity",
                AGY_COMMAND,
                agy_dir.clone(),
                "go vet ./...",
                "deny",
            ),
        ];
        for (agent, command, cwd, sample, want) in cases {
            let payload = if agent == "antigravity" {
                agy_payload(sample, &scratch)
            } else {
                claude_payload(sample, &scratch)
            };
            let (got, _out, err) = run_hook(command, &payload, &cwd, &env)?;
            if let Some(src) = answered_by(&err) {
                if !sources.contains(&src) {
                    sources.push(src);
                }
            }
            match got {
                None => problems.push(format!(
                    "the launcher failed on `{}` ({} format): {}",
                    sample, agent, err
                )),
                Some(g) if g != want => problems.push(format!(
                    "the launcher said {} to `{}` ({} format), expected {} \
(is that category in warn or off mode in policy.json?)",
                    g, sample, agent, want
                )),
                _ => {}
            }
        }
        Ok(())
    })();
    let _ = fs::remove_dir_all(&scratch);
    result?;
    Ok((problems, sources))
}

pub fn check(ctx: &Ctx, workspace: &str, home: &str) -> R<i32> {
    let mut problems = check_wiring(workspace)?;
    let mut sources = Vec::new();
    if problems.is_empty() {
        let (more, srcs) = self_test(ctx, workspace, home)?;
        problems.extend(more);
        sources = srcs;
    }
    problems.extend(check_backstop(ctx, home)?);
    if !problems.is_empty() {
        for p in &problems {
            ctx.print(&format!("PROBLEM: {}", p));
        }
        return Ok(1);
    }
    let first = backstop_commands(home)?
        .0
        .into_iter()
        .next()
        .unwrap_or_default();
    ctx.print(&format!(
        "agent-guard is wired into {} and {}, and the per-user backstop runs {}. Both allow \
`git status` and refuse `git stash` (Claude Code's payload) and `go vet` (agy's).",
        CLAUDE_SETTINGS_REL,
        AGY_HOOKS_REL,
        join(&backstop_main(&first), LAUNCHER_REL)
    ));
    ctx.print(&format!(
        "guard that answered: {}",
        if sources.is_empty() {
            "unknown".to_string()
        } else {
            sources.join(", ")
        }
    ));
    Ok(0)
}

/// `datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")`.
fn backup_stamp() -> String {
    let t: Vec<char> = log_now().chars().collect(); // 2026-10-30T12:34:56.123456Z
    let pick = |a: usize, b: usize| t[a..b].iter().collect::<String>();
    format!(
        "{}{}{}T{}{}{}Z",
        pick(0, 4),
        pick(5, 7),
        pick(8, 10),
        pick(11, 13),
        pick(14, 16),
        pick(17, 19)
    )
}

/// install.py's main(), Python exceptions and all.
pub fn main_inner(ctx: &Ctx, argv: &[String]) -> R<i32> {
    let args = match argparse::parse(ctx, argv) {
        Parsed::Run(a) => a,
        Parsed::Exit(rc) => return Ok(rc),
    };
    let home = match &args.home {
        Some(h) if !h.is_empty() => h.clone(),
        _ => ctx.home(),
    };
    let workspace = match &args.workspace {
        Some(w) if !w.is_empty() => w.clone(),
        _ => ctx.var("BUILD_WORKSPACE_DIRECTORY").unwrap_or_default(),
    };
    if !args.mode.is_empty() {
        ctx.eprint(
            "agent-guard: --mode is gone. Modes live in tools/agent-guard/policy.json and take \
effect when a change to it merges to main.\n",
        );
        return Ok(2);
    }
    if args.check {
        if workspace.is_empty() {
            ctx.eprint("agent-guard: run this through `bazel run` (no checkout given)\n");
            return Ok(2);
        }
        return check(ctx, &workspace, &home);
    }
    let marker = agent_marker(&ctx.env);
    if let Some(m) = &marker {
        if args.uninstall && !args.dry_run {
            ctx.eprint(&format!(
                "agent-guard: refusing to uninstall inside an agent session ({} is set).\n\
Removing the backstop is James's job, from his own terminal. Agents may \
install, --check and --dry-run.\n",
                m
            ));
            return Ok(2);
        }
        let aimed = args.home.as_deref().map_or(false, |h| !h.is_empty())
            || args.workspace.as_deref().map_or(false, |w| !w.is_empty());
        if !args.uninstall && !args.dry_run && aimed {
            ctx.eprint(&format!(
                "agent-guard: refusing --home/--workspace inside an agent session ({} is set): \
an agent installs only for its own HOME, from the checkout `bazel run` ran in.\n",
                m
            ));
            return Ok(2);
        }
    }
    let now = backup_stamp();
    if args.uninstall {
        return uninstall(ctx, &home, &now, args.dry_run);
    }
    if workspace.is_empty() {
        ctx.eprint("agent-guard: run this through `bazel run` (no checkout given)\n");
        return Ok(2);
    }
    if let Some(m) = &marker {
        if !args.dry_run {
            return agent_install(ctx, &home, &workspace, &now, m);
        }
    }
    let rc = install(ctx, &home, &workspace, &now, args.dry_run)?;
    if marker.is_some() {
        let (_main, why) = agent_check(ctx, &home, &workspace)?;
        ctx.print(&format!(
            "an agent may run this install: {}",
            if why.is_empty() {
                "yes".to_string()
            } else {
                format!("no, {}", why)
            }
        ));
    }
    Ok(rc)
}

/// The exit status, with what Python prints for an exception that escapes main().
pub fn main(ctx: &Ctx, argv: &[String]) -> i32 {
    match main_inner(ctx, argv) {
        Ok(rc) => rc,
        Err(PyErr::Exit(msg)) => {
            ctx.eprint(&format!("{}\n", msg));
            1
        }
        Err(e) => {
            ctx.eprint(&format!(
                "Traceback (most recent call last):\n  File \"tools/agent-guard/install\", in main\n{}\n",
                e.last_line()
            ));
            1
        }
    }
}
