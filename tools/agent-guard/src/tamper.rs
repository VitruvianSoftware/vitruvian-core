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

//! Self-protection: agents may not edit the installed guard, its policy or
//! log, the checkout's hook files, or agent-guard's entries in the backstop's
//! user files.

use crate::classify::{has, installer_args_ok, installer_problem, v, Context, Verdict};
use crate::invocations::{expand_path, Invocation, SHELLS};
use crate::paths::{basename, dirname, join, normpath, relpath};
use crate::pyutil::{chars, cs, is_python_prog, is_space, is_word, starts_at, word_boundary};
use crate::pyval::{dumps, loads, py_eq, PyVal};
use crate::scope::repo_root_of;

pub const INSTALL_DIR_REL: &str = ".local/share/agent-guard";
pub const STATE_DIR_REL: &str = ".local/state/agent-guard";

pub const PROTECTED_REPO_FILES: [&str; 6] = [
    ".claude/settings.json",
    ".claude/settings.local.json",
    ".claude/*.sh",
    ".agents/hooks.json",
    "tools/agent-guard/hook.sh",
    "tools/remote/setup.sh",
];

pub fn hook_files_note() -> String {
    format!(
        "Agents may not change agent-guard's wiring or the files that drive session \
start ({}): those files take effect before review. Changing them is James's \
call: ask him.",
        PROTECTED_REPO_FILES.join(", ")
    )
}

pub const USER_FILES_NOTE: &str =
    "Shell, Desktop Commander and Antigravity writes to ~/.claude/settings.json and \
~/.gemini/config/hooks.json are refused because they hold agent-guard's backstop. \
Change other settings there with the Edit tool (it may not touch agent-guard's entries \
or set disableAllHooks to true); the backstop itself changes only through \
`bazel run //tools/agent-guard:install`.";

const GUARD_JOB: &str = "Changing agent-guard is James's job, from his own terminal.";

const READERS: &[&str] = &[
    "cat",
    "head",
    "tail",
    "less",
    "more",
    "jq",
    "grep",
    "egrep",
    "fgrep",
    "rg",
    "ls",
    "wc",
    "stat",
    "file",
    "diff",
    "cmp",
    "shasum",
    "sha256sum",
    "md5",
    "md5sum",
    "tree",
    "bat",
    "sort",
    "uniq",
    "cut",
    "column",
    "awk",
    "realpath",
    "readlink",
    "test",
    "[",
    "echo",
    "printf",
    "python3",
    "python",
];

/// Is path one agents may not write: the guard's folders in HOME, or a hook file in a checkout?
pub fn guard_path(path: &str, home: &str) -> bool {
    let p = normpath(path);
    for rel in [INSTALL_DIR_REL, STATE_DIR_REL] {
        let base = normpath(&join(home, rel));
        if p == base || p.starts_with(&format!("{}/", base)) {
            return true;
        }
    }
    protected_repo_file(&p, true).is_some()
}

const USER_HOOK_FILES_REL: [&str; 2] = [".claude/settings.json", ".gemini/config/hooks.json"];

/// `_USER_HOOK_MARK.search(text)`.
pub fn user_hook_mark(text: &str) -> bool {
    [
        "agent-guard/agent_guard.py",
        "agent-guard/hook.py",
        "agent-guard/hook.sh",
        "agent-guard-backstop",
    ]
    .iter()
    .any(|m| text.contains(m))
}

/// The backstop file that path is (with folders: or holds), else None.
pub fn user_hook_file(path: &str, home: &str, folders: bool) -> Option<String> {
    let p = normpath(path);
    if !p.contains(".claude") && !p.contains(".gemini") {
        return None;
    }
    for rel in USER_HOOK_FILES_REL {
        let f = normpath(&join(home, rel));
        if p == f || (folders && p != normpath(home) && f.starts_with(&format!("{}/", p))) {
            return Some(f);
        }
    }
    None
}

/// agent-guard's part of a backstop file: what an edit must leave unchanged.
fn guard_entries(path: &str, data: Option<&PyVal>) -> Option<PyVal> {
    let Some(PyVal::Dict(items)) = data else {
        return None;
    };
    let marked = |v: &PyVal| user_hook_mark(&dumps(v, false));
    if path.ends_with("hooks.json") {
        return Some(PyVal::Dict(
            items
                .iter()
                .filter(|(name, spec)| name == "agent-guard" || marked(spec))
                .cloned()
                .collect(),
        ));
    }
    let Some(PyVal::Dict(hooks)) = data.unwrap().get("hooks") else {
        return Some(PyVal::Dict(vec![]));
    };
    let mut out = Vec::new();
    for (event, entries) in hooks {
        if let PyVal::List(list) = entries {
            if list.iter().any(marked) {
                out.push((
                    event.clone(),
                    PyVal::List(list.iter().filter(|e| marked(e)).cloned().collect()),
                ));
            }
        }
    }
    Some(PyVal::Dict(out))
}

/// `_DISABLE_ALL_TRUE.search(text)`: `"disableAllHooks"\s*:\s*true\b`.
pub fn disables_all_hooks(text: &str) -> bool {
    let t = chars(text);
    let mut from = 0;
    while let Some(at) = crate::pyutil::find_str(&t, "\"disableAllHooks\"", from) {
        from = at + 1;
        let mut i = at + 17;
        while i < t.len() && is_space(t[i]) {
            i += 1;
        }
        if t.get(i) != Some(&':') {
            continue;
        }
        i += 1;
        while i < t.len() && is_space(t[i]) {
            i += 1;
        }
        if starts_at(&t, i, "true") && word_boundary(&t, i + 4) {
            return true;
        }
    }
    false
}

fn parse_or_none(text: &str) -> Option<PyVal> {
    match loads(text) {
        Ok(v) => Some(v),
        Err(crate::pyval::JsonErr::Value) => None,
        Err(crate::pyval::JsonErr::Recursion) => panic!("RecursionError"),
    }
}

/// Why writing `after` over `before` would break the backstop in path ("" if it would not).
pub fn user_file_change_problem(path: &str, before: Option<&str>, after: &str) -> String {
    let new = if crate::pyutil::py_strip(after).is_empty() {
        Some(PyVal::Dict(vec![]))
    } else {
        parse_or_none(after)
    };
    if let Some(n) = &new {
        if n.is_dict() && matches!(n.get("disableAllHooks"), Some(PyVal::Bool(true))) {
            return "it sets \"disableAllHooks\": true".into();
        }
    }
    let old = match before {
        Some(b) if !crate::pyutil::py_strip(b).is_empty() => parse_or_none(b),
        _ => Some(PyVal::Dict(vec![])),
    };
    let want = guard_entries(path, old.as_ref());
    let Some(want) = want.filter(|w| w.truthy()) else {
        return String::new(); // nothing of agent-guard's there to keep
    };
    let Some(new) = new else {
        return "the result is not valid JSON, so agent-guard's entries cannot be kept".into();
    };
    match guard_entries(path, Some(&new)) {
        Some(got) if py_eq(&got, &want) => String::new(),
        _ => "it removes or changes agent-guard's entries".into(),
    }
}

/// The PROTECTED_REPO_FILES entry that path is, or holds, inside a vitruvian-core checkout.
pub fn protected_repo_file(path: &str, folders: bool) -> Option<&'static str> {
    let p = normpath(path);
    if ![".claude", ".agents", "tools", "agent-guard", "hook"]
        .iter()
        .any(|part| p.contains(part))
    {
        return None; // fast path: most paths name none of them
    }
    let root = repo_root_of(&p)?;
    if p == root {
        return None;
    }
    let rel = relpath(&p, &root);
    let rel_dir = format!("{}/", rel);
    PROTECTED_REPO_FILES
        .iter()
        .find(|f| protected_match(&rel, f) || (folders && f.starts_with(&rel_dir)))
        .copied()
}

fn rpartition(s: &str) -> (&str, &str) {
    match s.rfind('/') {
        Some(i) => (&s[..i], &s[i + 1..]),
        None => ("", s),
    }
}

fn protected_match(rel: &str, pattern: &str) -> bool {
    if !pattern.contains('*') {
        return rel == pattern;
    }
    let (folder, name) = rpartition(pattern);
    let (rfolder, rname) = rpartition(rel);
    // fnmatchcase(rname, "*.sh"): the only wildcard pattern there is.
    let suffix = name.trim_start_matches('*');
    rfolder == folder && rname.ends_with(suffix)
}

/// `re.finditer(r"(~|\$\{?HOME\}?|/)[^\s'\"=]*agent-guard[^\s'\"]*", word)`.
fn guard_mentions(word: &str) -> Vec<String> {
    let t = chars(word);
    let class_a = |c: char| !(is_space(c) || c == '\'' || c == '"' || c == '=');
    let class_b = |c: char| !(is_space(c) || c == '\'' || c == '"');
    let lit: Vec<char> = "agent-guard".chars().collect();
    let mut out = Vec::new();
    let mut s = 0;
    while s < t.len() {
        let a = match t[s] {
            '~' | '/' => Some(s + 1),
            '$' => {
                let mut j = s + 1;
                if t.get(j) == Some(&'{') && starts_at(&t, j + 1, "HOME") {
                    j += 5;
                    Some(if t.get(j) == Some(&'}') { j + 1 } else { j })
                } else if starts_at(&t, j, "HOME") {
                    j += 4;
                    Some(if t.get(j) == Some(&'}') { j + 1 } else { j })
                } else {
                    None
                }
            }
            _ => None,
        };
        if let Some(a) = a {
            let mut m = a;
            while m < t.len() && class_a(t[m]) {
                m += 1;
            }
            let mut found = None;
            if m >= a + lit.len() {
                for q in (a..=m - lit.len()).rev() {
                    if t[q..q + lit.len()] == lit[..] {
                        found = Some(q);
                        break;
                    }
                }
            }
            if let Some(q) = found {
                let mut e = q + lit.len();
                while e < t.len() && class_b(t[e]) {
                    e += 1;
                }
                out.push(cs(&t[s..e]));
                s = e;
                continue;
            }
        }
        s += 1;
    }
    out
}

fn mentions_guard(word: &str, cwd: &str, home: &str) -> bool {
    if !word.contains("agent-guard") {
        return false;
    }
    guard_mentions(word)
        .iter()
        .any(|m| guard_path(&expand_path(m, cwd, home), home))
}

/// `_PY_LITERAL.finditer(text)`: `(['\"])((?:(?!\1).){1,500}?)\1` -> (start, end, inner).
fn py_literals(t: &[char]) -> Vec<(usize, usize, String)> {
    let mut out = Vec::new();
    let mut s = 0;
    while s < t.len() {
        let q = t[s];
        if q == '\'' || q == '"' {
            let mut j = s + 1;
            let mut ok = false;
            while j < t.len() && j - s - 1 <= 500 {
                let c = t[j];
                if c == q {
                    ok = j > s + 1;
                    break;
                }
                if c == '\n' {
                    break;
                }
                j += 1;
            }
            if ok {
                out.push((s, j + 1, cs(&t[s + 1..j])));
                s = j + 1;
                continue;
            }
        }
        s += 1;
    }
    out
}

fn rstrip_ws(t: &[char]) -> &[char] {
    let mut e = t.len();
    while e > 0 && is_space(t[e - 1]) {
        e -= 1;
    }
    &t[..e]
}

/// Does `before` end with `\b<name>\(\s*$` for one of names?
fn ends_with_call(before: &[char], names: &[&str]) -> bool {
    let b = rstrip_ws(before);
    if b.last() != Some(&'(') {
        return false;
    }
    let b = &b[..b.len() - 1];
    names.iter().any(|name| {
        let n: Vec<char> = name.chars().collect();
        b.len() >= n.len() && b[b.len() - n.len()..] == n[..] && word_boundary(b, b.len() - n.len())
    })
}

const PY_WRITE_FIRST: &[&str] = &[
    "rmtree",
    "remove",
    "unlink",
    "rmdir",
    "removedirs",
    "rename",
    "renames",
    "replace",
    "move",
    "chmod",
    "chown",
    "truncate",
    "makedirs",
    "mkdir",
    "symlink",
    "link",
    "utime",
    "chflags",
];

/// `_PY_WRITE_SECOND.search(before)`:
/// `\b(copy\w*|move|rename|renames|replace|symlink|link)\(\s*(['\"])[^'\"]*\2\s*,\s*$`.
fn py_write_second(before: &[char]) -> bool {
    let b = rstrip_ws(before);
    if b.last() != Some(&',') {
        return false;
    }
    let b = rstrip_ws(&b[..b.len() - 1]);
    let Some(&close) = b.last() else { return false };
    if close != '\'' && close != '"' {
        return false;
    }
    let inner = &b[..b.len() - 1];
    let Some(open) = inner.iter().rposition(|&c| c == '\'' || c == '"') else {
        return false;
    };
    if inner[open] != close {
        return false;
    }
    let b = rstrip_ws(&inner[..open]);
    if b.last() != Some(&'(') {
        return false;
    }
    let b = &b[..b.len() - 1];
    let mut start = b.len();
    while start > 0 && is_word(b[start - 1]) {
        start -= 1;
    }
    let name = cs(&b[start..]);
    name.starts_with("copy")
        || ["move", "rename", "renames", "replace", "symlink", "link"].contains(&name.as_str())
}

/// `_PY_PATH_WRITE.match(after)`.
fn py_path_write(after: &[char]) -> bool {
    let skip = |mut i: usize| {
        while i < after.len() && is_space(after[i]) {
            i += 1;
        }
        i
    };
    let mut i = skip(0);
    if after.get(i) != Some(&')') {
        return false;
    }
    i = skip(i + 1);
    if after.get(i) != Some(&'.') {
        return false;
    }
    i = skip(i + 1);
    for m in [
        "write_text",
        "write_bytes",
        "unlink",
        "rmdir",
        "mkdir",
        "touch",
        "rename",
        "replace",
        "chmod",
        "symlink_to",
        "hardlink_to",
    ] {
        if starts_at(after, i, m) {
            return true;
        }
    }
    if starts_at(after, i, "open(") {
        let j = skip(i + 5);
        if matches!(after.get(j), Some('\'') | Some('"'))
            && matches!(after.get(j + 1), Some('w') | Some('a') | Some('x'))
        {
            return true;
        }
    }
    false
}

/// `re.match(r"^\s*,\s*(mode\s*=\s*)?['\"][^'\"]*[wax+]", after)`.
fn open_mode_writes(after: &[char]) -> bool {
    let skip = |mut i: usize| {
        while i < after.len() && is_space(after[i]) {
            i += 1;
        }
        i
    };
    let mut i = skip(0);
    if after.get(i) != Some(&',') {
        return false;
    }
    i = skip(i + 1);
    if starts_at(after, i, "mode") {
        let j = skip(i + 4);
        if after.get(j) == Some(&'=') {
            i = skip(j + 1);
        }
    }
    if !matches!(after.get(i), Some('\'') | Some('"')) {
        return false;
    }
    let mut j = i + 1;
    while j < after.len() && after[j] != '\'' && after[j] != '"' {
        if "wax+".contains(after[j]) {
            return true;
        }
        j += 1;
    }
    false
}

/// The protected path literal that Python code writes, moves or deletes, or "".
fn python_writes(text: &str, protected: &dyn Fn(&str) -> bool) -> String {
    let t = chars(text);
    for (start, end, lit) in py_literals(&t) {
        if !protected(&lit) {
            continue;
        }
        let before = &t[start.saturating_sub(120)..start];
        let after = &t[end..(end + 40).min(t.len())];
        if ends_with_call(before, &["open"]) && open_mode_writes(after) {
            return lit;
        }
        if ends_with_call(before, PY_WRITE_FIRST) || py_write_second(before) {
            return lit;
        }
        if ends_with_call(before, &["Path"]) && py_path_write(after) {
            return lit;
        }
    }
    String::new()
}

/// `_HOOK_FILE_HINT.search(word)`.
fn hook_file_hint(word: &str) -> bool {
    [
        ".claude",
        ".agents",
        "settings",
        "hooks.json",
        "hook.sh",
        "tools",
    ]
    .iter()
    .any(|h| word.contains(h))
}

/// `_PATHISH.finditer(word)`: runs of `[^\s'\"=,;:()<>|&`]`.
fn pathish(word: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut cur = String::new();
    for c in word.chars() {
        if is_space(c) || "'\"=,;:()<>|&`".contains(c) {
            if !cur.is_empty() {
                out.push(std::mem::take(&mut cur));
            }
        } else {
            cur.push(c);
        }
    }
    if !cur.is_empty() {
        out.push(cur);
    }
    out
}

fn mentions_hook_file(word: &str, cwd: &str, home: &str, folders: bool) -> bool {
    if !hook_file_hint(word) {
        return false;
    }
    pathish(word)
        .iter()
        .any(|m| protected_repo_file(&expand_path(m, cwd, home), folders).is_some())
}

const REMOVERS: &[&str] = &[
    "rm", "rmdir", "mv", "unlink", "trash", "srm", "chmod", "chown", "chflags", "find",
];
const BAZELS: &[&str] = &["bazel", "bazelisk", "aspect", "ibazel"];
const COPIERS: &[&str] = &["cp", "rsync", "scp", "ditto", "install"];
const OTHER_USER_FILE_WRITERS: &[&str] = &[
    "tee", "ln", "touch", "truncate", "sed", "perl", "ruby", "sponge", "patch", "ed", "ex",
];

fn hook_file_nonwriter(prog: &str) -> bool {
    SHELLS.contains(&prog) || BAZELS.contains(&prog) || ["git", "gh", "source", "."].contains(&prog)
}

fn user_file_writer(prog: &str) -> bool {
    REMOVERS.contains(&prog) || COPIERS.contains(&prog) || OTHER_USER_FILE_WRITERS.contains(&prog)
}

/// The paths a program may write: all its arguments, except a copier's sources.
fn written_words(argv: &[String]) -> Vec<String> {
    if !COPIERS.contains(&basename(&argv[0])) {
        return argv[1..].to_vec();
    }
    let mut dests: Vec<String> = Vec::new();
    let mut plain: Vec<String> = Vec::new();
    let mut i = 1;
    while i < argv.len() {
        let a = &argv[i];
        if (a == "-t" || a == "--target-directory") && i + 1 < argv.len() {
            dests.push(argv[i + 1].clone());
            i += 2;
            continue;
        }
        if let Some(d) = a.strip_prefix("--target-directory=") {
            dests.push(d.to_string());
        } else if !a.starts_with('-') {
            plain.push(a.clone());
        }
        i += 1;
    }
    if dests.is_empty() {
        if let Some(last) = plain.pop() {
            dests.push(last);
        }
    }
    let mut out = dests.clone();
    for d in &dests {
        for src in &plain {
            out.push(format!(
                "{}/{}",
                d.trim_end_matches('/'),
                basename(src.trim_end_matches('/'))
            ));
        }
    }
    out
}

/// `_INSTALLER_RE.search(w)`: agent-guard/install, install.py or install_rs.
fn is_installer_path(w: &str) -> bool {
    let core = w.strip_suffix('\n').unwrap_or(w);
    for tail in [
        "agent-guard/install",
        "agent-guard/install.py",
        "agent-guard/install_rs",
    ] {
        if let Some(head) = core.strip_suffix(tail) {
            if head.is_empty() || head.ends_with('/') {
                return true;
            }
        }
    }
    false
}

/// The installer run directly (not via bazel): (does it write, its path), or None.
fn installer_run(inv: &Invocation) -> Option<(bool, String)> {
    let argv = &inv.argv;
    for (i, w) in argv.iter().enumerate() {
        if !is_installer_path(w) {
            continue;
        }
        let direct = i == 0;
        let via_python = i > 0
            && is_python_prog(basename(&argv[0]))
            && argv[1..i].iter().all(|a| a.starts_with('-'));
        if direct || via_python {
            let rest = &argv[i + 1..];
            return Some((rest.is_empty() || !installer_args_ok(rest), w.clone()));
        }
    }
    None
}

pub fn classify_guard_tamper(inv: &Invocation, ctx: &Context) -> Option<Verdict> {
    let home = ctx.home.as_str();
    let run = installer_run(inv);
    if let Some((false, path)) = &run {
        let why = installer_problem(&dirname(&expand_path(path, &inv.cwd, home)), home);
        if !why.is_empty() {
            return Some(v(
                "guard-config",
                "running the agent-guard installer directly",
                None,
                &format!(
                    "Agents may run the installer only as origin/main has it: {}.",
                    why
                ),
            ));
        }
    }
    if let Some((true, _)) = run {
        return Some(v(
            "guard-config",
            "running the agent-guard installer directly",
            Some(crate::classify::Target {
                use_: "bazel run //tools/agent-guard:install",
                pending: None,
            }),
            "Agents install the backstop only through that target, which checks the main \
checkout first; `--dry-run` and `--check` are fine directly. Removing it \
(--uninstall) is James's, from his own terminal.",
        ));
    }
    for (op, target) in &inv.redirects {
        let path = expand_path(target, &inv.cwd, home);
        if op != "<" && user_hook_file(&path, home, false).is_some() {
            return Some(v(
                "guard-config",
                "writing the backstop's user files",
                None,
                USER_FILES_NOTE,
            ));
        }
        if op != "<" && guard_path(&path, home) {
            if protected_repo_file(&path, true).is_some() {
                return Some(v(
                    "guard-config",
                    "writing agent-guard's hook files",
                    None,
                    &hook_files_note(),
                ));
            }
            return Some(v(
                "guard-config",
                "writing agent-guard files",
                None,
                GUARD_JOB,
            ));
        }
    }
    let prog = inv.prog();
    let args = &inv.argv[1..];
    if READERS.contains(&prog) || is_python_prog(prog) {
        if is_python_prog(prog) {
            // python -c that WRITES one of the guard's files: refuse. Naming one
            // only as something to read or copy from is fine.
            let text = args.join(" ");
            let hit = python_writes(&text, &|p: &str| {
                guard_path(&expand_path(p, &inv.cwd, home), home)
            });
            if hit.is_empty()
                && !python_writes(&text, &|p: &str| {
                    user_hook_file(&expand_path(p, &inv.cwd, home), home, false).is_some()
                })
                .is_empty()
            {
                return Some(v(
                    "guard-config",
                    "writing the backstop's user files",
                    None,
                    USER_FILES_NOTE,
                ));
            }
            if !hit.is_empty() {
                let hook = protected_repo_file(&expand_path(&hit, &inv.cwd, home), true).is_some();
                return Some(v(
                    "guard-config",
                    if hook {
                        "writing agent-guard's hook files"
                    } else {
                        "writing agent-guard files"
                    },
                    None,
                    &if hook {
                        hook_files_note()
                    } else {
                        GUARD_JOB.to_string()
                    },
                ));
            }
        }
        return None;
    }
    if prog == "sed"
        && !has(args, &["-i", "--in-place"])
        && !args.iter().any(|a| a.starts_with("-i"))
    {
        return None;
    }
    if prog == "find" && !inv.argv.iter().any(|a| a == "-delete" || a == "-exec") {
        return None;
    }
    if BAZELS.contains(&prog) {
        // Its arguments are labels and the target's own arguments. What a
        // target does is out of sight by design; the installer is judged in
        // classify_bazel.
        return None;
    }
    let written = written_words(&inv.argv);
    if written.iter().any(|w| mentions_guard(w, &inv.cwd, home)) {
        return Some(v(
            "guard-config",
            &format!("{} on agent-guard files", prog),
            None,
            GUARD_JOB,
        ));
    }
    if !hook_file_nonwriter(prog)
        && written
            .iter()
            .any(|w| mentions_hook_file(w, &inv.cwd, home, REMOVERS.contains(&prog)))
    {
        return Some(v(
            "guard-config",
            &format!("{} on agent-guard's hook files", prog),
            None,
            &hook_files_note(),
        ));
    }
    let in_place = !(prog == "perl" || prog == "ruby")
        || args.iter().any(|a| {
            a.starts_with("-i")
                || (a.starts_with('-') && a[1..].contains('i') && !a.starts_with("--"))
        });
    if user_file_writer(prog) && in_place {
        let folders = REMOVERS.contains(&prog);
        let hit = written.iter().any(|w| {
            (w.contains(".claude")
                || w.contains(".gemini")
                || w.contains("settings")
                || w.contains("hooks.json"))
                && pathish(w).iter().any(|m| {
                    user_hook_file(&expand_path(m, &inv.cwd, home), home, folders).is_some()
                })
        });
        if hit {
            return Some(v(
                "guard-config",
                &format!("{} on the backstop's user files", prog),
                None,
                USER_FILES_NOTE,
            ));
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn python_write_shapes() {
        let p = |s: &str| s.contains("hook.sh");
        assert_eq!(python_writes("open('x/hook.sh', 'w')", &p), "x/hook.sh");
        assert_eq!(python_writes("open('x/hook.sh').read()", &p), "");
        assert_eq!(
            python_writes("shutil.copy('a', 'x/hook.sh')", &p),
            "x/hook.sh"
        );
        assert_eq!(python_writes("shutil.copy('x/hook.sh', 'b')", &p), "");
        assert_eq!(
            python_writes("Path('x/hook.sh').write_text('')", &p),
            "x/hook.sh"
        );
        assert_eq!(python_writes("os.remove(\"x/hook.sh\")", &p), "x/hook.sh");
    }

    #[test]
    fn mentions() {
        assert_eq!(
            guard_mentions("--x=~/.local/share/agent-guard/policy.json"),
            vec!["~/.local/share/agent-guard/policy.json"]
        );
        assert_eq!(
            guard_mentions("${HOME}/a/agent-guard/b agent-guard"),
            vec!["${HOME}/a/agent-guard/b"]
        );
        assert!(
            disables_all_hooks("{\"disableAllHooks\" :true}")
                && !disables_all_hooks("\"disableAllHooks\": trueish")
        );
    }
}
