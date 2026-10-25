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

//! The two committed files, and the judging: permission_drift.py's
//! load_agents, load_declared, judge, check and _verdict.

use crate::github::{Api, ReadFail};
use crate::json::{dedup, py_eq, Value};
use crate::pyerr::{self, Crash};
use crate::pystr;

pub const ORG: &str = "VitruvianSoftware";
pub const LEVELS: [&str; 3] = ["read", "write", "admin"];

pub const OK: &str = "ok";
pub const PENDING: &str = "PENDING";
pub const DRIFT: &str = "DRIFT";
pub const MISSING: &str = "MISSING";
pub const UNLISTED: &str = "UNLISTED";
pub const UNREAD: &str = "NOT CHECKED";

/// One row of agents.tsv. The ids are Python ints, kept as their decimal
/// text, since agents.tsv sets no limit on their size.
#[derive(Clone, Debug, PartialEq)]
pub struct Agent {
    pub name: String,
    pub app_id: String,
    pub inst_id: String,
}

impl Agent {
    pub fn new(name: &str, app_id: u64, inst_id: u64) -> Agent {
        Agent {
            name: name.into(),
            app_id: app_id.to_string(),
            inst_id: inst_id.to_string(),
        }
    }
}

/// An agent's declared permissions, in file order.
pub type Perms = Vec<(String, String)>;
/// permissions.tsv: `{agent: {permission: level}}`, in file order.
pub type Declared = Vec<(String, Perms)>;

/// Why a file was not loaded: a FileError (exit 2), or a crash.
#[derive(Debug, PartialEq)]
pub enum LoadFail {
    File(String),
    Crash(Crash),
}

impl From<Crash> for LoadFail {
    fn from(c: Crash) -> LoadFail {
        LoadFail::Crash(c)
    }
}

/// `_rows`: (line number, tab-split columns) for every line that is not
/// blank or a comment. The file is read as Python's text mode reads it:
/// UTF-8, with universal newlines, then `str.splitlines()`.
fn rows(path: &str) -> Result<Vec<(usize, Vec<String>)>, LoadFail> {
    let bytes = std::fs::read(path).map_err(|e| {
        LoadFail::File(format!(
            "cannot read {}: {}",
            path,
            pyerr::os_error_with_name(&e, path)
        ))
    })?;
    let text = pyerr::decode_utf8(&bytes)?;
    let text = text.replace("\r\n", "\n").replace('\r', "\n");
    let mut out = Vec::new();
    for (i, line) in pystr::splitlines_keepends(&text).into_iter().enumerate() {
        let line = line.trim_end_matches(is_line_break);
        if !pystr::strip(line).is_empty() && !line.starts_with('#') {
            out.push((i + 1, line.split('\t').map(String::from).collect()));
        }
    }
    Ok(out)
}

fn is_line_break(c: char) -> bool {
    matches!(
        c as u32,
        0x0A | 0x0B | 0x0C | 0x0D | 0x1C | 0x1D | 0x1E | 0x85 | 0x2028 | 0x2029
    )
}

/// `str.isdigit()`: a decimal digit, or a digit that is not decimal (a
/// superscript, a circled digit...), which `int()` then refuses. Unicode
/// 15.0, as in Python 3.12.
fn is_digit_char(c: char) -> bool {
    pystr::decimal_value(c).is_some()
        || matches!(c as u32,
            0xB2..=0xB3 | 0xB9 | 0x1369..=0x1371 | 0x19DA | 0x2070 | 0x2074..=0x2079
            | 0x2080..=0x2089 | 0x2460..=0x2468 | 0x2474..=0x247C | 0x2488..=0x2490
            | 0x24EA | 0x24F5..=0x24FD | 0x24FF | 0x2776..=0x277E | 0x2780..=0x2788
            | 0x278A..=0x2792 | 0x10A40..=0x10A43 | 0x10E60..=0x10E68
            | 0x11052..=0x1105A | 0x1F100..=0x1F10A)
}

fn isdigit(s: &str) -> bool {
    !s.is_empty() && s.chars().all(is_digit_char)
}

/// `int(s)` for a string `isdigit()` accepted: its decimal text, or the
/// ValueError for a digit that is not decimal.
fn py_int(s: &str) -> Result<String, Crash> {
    let mut out = String::new();
    for c in s.chars() {
        match pystr::decimal_value(c) {
            Some(d) => out.push(char::from_digit(d, 10).unwrap()),
            None => {
                return Err(Crash::new(
                    "ValueError",
                    format!(
                        "invalid literal for int() with base 10: {}",
                        pystr::repr_str(s)
                    ),
                ))
            }
        }
    }
    let trimmed = out.trim_start_matches('0');
    Ok(if trimmed.is_empty() {
        "0".into()
    } else {
        trimmed.into()
    })
}

/// agents.tsv -> agents, in file order.
pub fn load_agents(path: &str) -> Result<Vec<Agent>, LoadFail> {
    let mut agents = Vec::new();
    for (number, cols) in rows(path)? {
        if cols.len() < 3 || !cols[..3].iter().all(|c| !pystr::strip(c).is_empty()) {
            return Err(LoadFail::File(format!(
                "{}:{}: want agent, app_id, installation_id",
                path, number
            )));
        }
        let name = pystr::strip(&cols[0]);
        let app_id = pystr::strip(&cols[1]);
        let inst_id = pystr::strip(&cols[2]);
        if !(isdigit(app_id) && isdigit(inst_id)) {
            return Err(LoadFail::File(format!(
                "{}:{}: app_id and installation_id must be numbers",
                path, number
            )));
        }
        agents.push(Agent {
            name: name.into(),
            app_id: py_int(app_id)?,
            inst_id: py_int(inst_id)?,
        });
    }
    if agents.is_empty() {
        return Err(LoadFail::File(format!("{}: no agents listed", path)));
    }
    Ok(agents)
}

/// permissions.tsv -> declared, checked against agents.
pub fn load_declared(path: &str, agents: &[Agent]) -> Result<Declared, LoadFail> {
    let mut declared: Declared = Vec::new();
    for (number, cols) in rows(path)? {
        if cols.len() != 3 {
            return Err(LoadFail::File(format!(
                "{}:{}: want agent, permission, level",
                path, number
            )));
        }
        let name = pystr::strip(&cols[0]).to_string();
        let perm = pystr::strip(&cols[1]).to_string();
        let level = pystr::strip(&cols[2]).to_string();
        if !agents.iter().any(|a| a.name == name) {
            return Err(LoadFail::File(format!(
                "{}:{}: '{}' is not in agents.tsv",
                path, number, name
            )));
        }
        if !LEVELS.contains(&level.as_str()) {
            return Err(LoadFail::File(format!(
                "{}:{}: level '{}' is not one of {}",
                path,
                number,
                level,
                LEVELS.join(", ")
            )));
        }
        let idx = match declared.iter().position(|(n, _)| *n == name) {
            Some(i) => i,
            None => {
                declared.push((name.clone(), Vec::new()));
                declared.len() - 1
            }
        };
        let perms = &mut declared[idx].1;
        if perms.iter().any(|(p, _)| *p == perm) {
            return Err(LoadFail::File(format!(
                "{}:{}: {} declares {} twice",
                path, number, name, perm
            )));
        }
        perms.push((perm, level));
    }
    let undeclared: Vec<&str> = agents
        .iter()
        .filter(|a| !declared.iter().any(|(n, _)| *n == a.name))
        .map(|a| a.name.as_str())
        .collect();
    if !undeclared.is_empty() {
        return Err(LoadFail::File(format!(
            "{}: no permissions declared for {}",
            path,
            undeclared.join(", ")
        )));
    }
    Ok(declared)
}

// --------------------------------------------------------------------------
// GitHub.
// --------------------------------------------------------------------------

/// `d.get(key)` on a dict, None (JSON null) when it is missing.
fn field(v: &Value, key: &str) -> Value {
    v.get(key).cloned().unwrap_or(Value::Null)
}

fn int(text: &str) -> Value {
    Value::Int(text.into())
}

/// Every App installation on the org, following pages, counted.
pub fn org_installations(api: &mut dyn Api, org: &str) -> Result<Vec<Value>, ReadFail> {
    let mut url = Some(format!("/orgs/{}/installations?per_page=100", org));
    let mut found = Vec::new();
    let mut total = Value::Null;
    while let Some(u) = url.take() {
        let (body, next) = api.get(&u)?;
        let list = match (&body, body.get("installations")) {
            (Value::Obj(_), Some(Value::Arr(items))) => items.clone(),
            _ => {
                return Err(ReadFail::Read(format!(
                    "/orgs/{}/installations: no installations list in the answer",
                    org
                )))
            }
        };
        total = field(&body, "total_count");
        found.extend(list);
        url = next.filter(|n| !n.is_empty());
    }
    // A page we failed to follow would silently drop Apps, and a dropped App
    // reads as MISSING, or worse, an unlisted one is never seen.
    if !py_eq(&total, &int(&found.len().to_string())) {
        return Err(ReadFail::Read(format!(
            "/orgs/{}/installations: GitHub counts {} installations but {} were read",
            org,
            total.py_str(),
            found.len()
        )));
    }
    Ok(found)
}

pub fn requested_permissions(
    api: &mut dyn Api,
    slug: &str,
    app_id: &str,
) -> Result<Value, ReadFail> {
    let (body, _) = api.get(&format!("/apps/{}", slug))?;
    let perms = match (&body, body.get("permissions")) {
        (Value::Obj(_), Some(p @ Value::Obj(_))) => p.clone(),
        _ => {
            return Err(ReadFail::Read(format!(
                "/apps/{}: no permissions in the answer",
                slug
            )))
        }
    };
    let id = field(&body, "id");
    if !py_eq(&id, &int(app_id)) {
        return Err(ReadFail::Read(format!(
            "/apps/{}: answer is App {}, expected {}",
            slug,
            id.py_str(),
            app_id
        )));
    }
    Ok(perms)
}

// --------------------------------------------------------------------------
// Judging.
// --------------------------------------------------------------------------

type Who = (&'static str, &'static str);
// Who says what, in the words the report uses.
const CODE: Who = ("permissions.tsv", "declares");
const GRANT: Who = ("GitHub", "grants");
const ASK: Who = ("the App's settings", "ask for");

/// A permission set as `.get()` sees it: a JSON null reads as absent.
type Set = Vec<(String, Value)>;

fn as_set(perms: &Perms) -> Set {
    perms
        .iter()
        .map(|(k, v)| (k.clone(), Value::Str(v.clone())))
        .collect()
}

fn lookup<'a>(set: &'a Set, key: &str) -> Option<&'a Value> {
    set.iter()
        .find(|(k, _)| k == key)
        .map(|(_, v)| v)
        .filter(|v| **v != Value::Null)
}

/// One plain sentence for every permission where two sets disagree.
fn differences(a: Who, a_set: &Set, b: Who, b_set: &Set) -> Vec<String> {
    let ((a_name, a_verb), (b_name, b_verb)) = (a, b);
    let mut keys: Vec<&String> = a_set.iter().chain(b_set).map(|(k, _)| k).collect();
    keys.sort();
    keys.dedup();
    let mut lines = Vec::new();
    for perm in keys {
        match (lookup(a_set, perm), lookup(b_set, perm)) {
            (None, None) => {}
            (None, Some(y)) => lines.push(format!(
                "{} {} {}={}; {} does not",
                b_name,
                b_verb,
                perm,
                y.py_str(),
                a_name
            )),
            (Some(x), None) => lines.push(format!(
                "{} {} {}={}; {} does not",
                a_name,
                a_verb,
                perm,
                x.py_str(),
                b_name
            )),
            (Some(x), Some(y)) if py_eq(x, y) => {}
            (Some(x), Some(y)) => lines.push(format!(
                "{}: {} {} {}, {} {} {}",
                perm,
                a_name,
                a_verb,
                x.py_str(),
                b_name,
                b_verb,
                y.py_str()
            )),
        }
    }
    lines
}

/// What the App's settings ask for: read, or the ReadError message.
pub enum Requested {
    Read(Value),
    Unread(String),
}

/// `-> (state, [detail lines])` for one App. `inst` is the org installation
/// with this id; `requested` is None only when there is nothing to ask.
pub fn judge(
    app_id: &str,
    inst_id: &str,
    declared: &Perms,
    inst: Option<&Value>,
    requested: Option<&Requested>,
    org: &str,
) -> (&'static str, Vec<String>) {
    let inst = match inst {
        None => {
            return (
                MISSING,
                vec![format!(
                    "installation {} is not on {}: the App is not installed, or agents.tsv has a stale id",
                    inst_id, org
                )],
            )
        }
        Some(i) => i,
    };
    if !py_eq(&field(inst, "app_id"), &int(app_id)) {
        return (
            MISSING,
            vec![format!(
                "installation {} belongs to App {} ({}), not {}: agents.tsv is wrong",
                inst_id,
                field(inst, "app_id").py_str(),
                field(inst, "app_slug").py_str(),
                app_id
            )],
        );
    }
    let suspended = field(inst, "suspended_at");
    if suspended.truthy() {
        return (
            MISSING,
            vec![format!(
                "installation {} is suspended since {}: the App can do nothing",
                inst_id,
                suspended.py_str()
            )],
        );
    }
    let granted: Set = match inst.get("permissions") {
        Some(Value::Obj(items)) => dedup(items),
        _ => {
            return (
                UNREAD,
                vec![format!(
                    "installation {}: GitHub gave no permissions for it",
                    inst_id
                )],
            )
        }
    };
    let code = as_set(declared);
    let mut details = differences(CODE, &code, GRANT, &granted);
    let requested: Set = match requested {
        Some(Requested::Read(Value::Obj(items))) => dedup(items),
        Some(Requested::Unread(err)) => {
            details.push(format!("could not read what the App asks for: {}", err));
            return (UNREAD, details);
        }
        _ => unreachable!("an installed App's requested permissions are always read"),
    };

    let asks_beyond_code = differences(CODE, &code, ASK, &requested);
    let unaccepted = differences(GRANT, &granted, ASK, &requested);
    let accept_at = format!(
        "accept at https://github.com/organizations/{}/settings/installations/{}",
        org, inst_id
    );

    if details.is_empty() && asks_beyond_code.is_empty() && unaccepted.is_empty() {
        let mut items = granted.clone();
        items.sort_by(|x, y| x.0.cmp(&y.0));
        let line: Vec<String> = items
            .iter()
            .map(|(k, v)| format!("{}={}", k, v.py_str()))
            .collect();
        return (OK, vec![line.join(" ")]);
    }
    if !unaccepted.is_empty() && asks_beyond_code.is_empty() {
        // The code and the App's settings agree; only the org's click is missing.
        let mut lines = vec![format!(
            "waiting for the org to accept a change ({}):",
            accept_at
        )];
        lines.extend(unaccepted.iter().map(|l| format!("  {}", l)));
        return (PENDING, lines);
    }
    if unaccepted.is_empty() {
        // Settings and grant agree with each other, so one set of lines says it.
        return (DRIFT, details);
    }
    details.extend(asks_beyond_code);
    details.push(format!(
        "and the org has not accepted what the App's settings ask for ({})",
        accept_at
    ));
    (DRIFT, details)
}

/// `^vitruvian-[a-z0-9-]+-agent$`, where `$` also matches before a final
/// newline.
fn agent_slug(slug: &str) -> bool {
    let s = slug.strip_suffix('\n').unwrap_or(slug);
    match s
        .strip_prefix("vitruvian-")
        .and_then(|r| r.strip_suffix("-agent"))
    {
        Some(mid) => {
            !mid.is_empty()
                && mid
                    .chars()
                    .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-')
        }
        None => false,
    }
}

pub type Results = Vec<(String, &'static str, Vec<String>)>;

/// `-> (exit code, report lines)`, or the exception that stops the script.
pub fn check(
    agents: &[Agent],
    declared: &Declared,
    api: &mut dyn Api,
    org: &str,
) -> Result<(i32, Vec<String>), Crash> {
    let mut results: Results = Vec::new();
    let installations = match org_installations(api, org) {
        Ok(i) => i,
        Err(ReadFail::Crash(c)) => return Err(c),
        Err(ReadFail::Read(err)) => {
            let hint = if err.contains(" 403 ") || err.contains(" 404 ") {
                " -- listing an org's App installations needs org Administration read: an org owner's gh login, or the vitruviansoftware-pulumi App token (an agent's own GH_TOKEN cannot; unset it to use your gh login)"
            } else {
                ""
            };
            for a in agents {
                results.push((
                    a.name.clone(),
                    UNREAD,
                    vec!["the org's App installations could not be read (above)".into()],
                ));
            }
            return Ok(verdict(
                &results,
                org,
                &[
                    format!(
                        "Could not read the org's App installations: {}{}",
                        err, hint
                    ),
                    String::new(),
                ],
            ));
        }
    };

    // {inst.get("id"): inst}: the last installation with an id wins it.
    for inst in &installations {
        if !inst.is_obj() {
            return Err(Crash::no_get(inst));
        }
        let id = field(inst, "id");
        if matches!(id, Value::Arr(_) | Value::Obj(_)) {
            return Err(Crash::unhashable(&id));
        }
    }
    for a in agents {
        let inst = installations
            .iter()
            .rev()
            .find(|i| py_eq(&field(i, "id"), &int(&a.inst_id)));
        let mut requested = None;
        if let Some(i) = inst {
            if py_eq(&field(i, "app_id"), &int(&a.app_id)) {
                let slug = field(i, "app_slug").py_str();
                requested = Some(match requested_permissions(api, &slug, &a.app_id) {
                    Ok(p) => Requested::Read(p),
                    Err(ReadFail::Read(m)) => Requested::Unread(m),
                    Err(ReadFail::Crash(c)) => return Err(c),
                });
            }
        }
        let perms = &declared
            .iter()
            .find(|(n, _)| *n == a.name)
            .expect("load_declared checked every agent has rows")
            .1;
        let (state, details) = judge(&a.app_id, &a.inst_id, perms, inst, requested.as_ref(), org);
        results.push((a.name.clone(), state, details));
    }

    for inst in &installations {
        let slug = match field(inst, "app_slug") {
            v if !v.truthy() => String::new(),
            Value::Str(s) => s,
            other => {
                return Err(Crash::new(
                    "TypeError",
                    format!(
                        "expected string or bytes-like object, got '{}'",
                        other.type_name()
                    ),
                ))
            }
        };
        if !agent_slug(&slug) {
            continue;
        }
        let app = field(inst, "app_id");
        if matches!(app, Value::Arr(_) | Value::Obj(_)) {
            return Err(Crash::unhashable(&app));
        }
        if !agents.iter().any(|a| py_eq(&app, &int(&a.app_id))) {
            results.push((
                slug,
                UNLISTED,
                vec![format!(
                    "App {} is installed (installation {}) but not in agents.tsv",
                    app.py_str(),
                    field(inst, "id").py_str()
                )],
            ));
        }
    }
    Ok(verdict(&results, org, &[]))
}

fn verdict(results: &Results, org: &str, preamble: &[String]) -> (i32, Vec<String>) {
    let width = results
        .iter()
        .map(|(n, _, _)| n.chars().count())
        .max()
        .unwrap_or(0);
    let mut lines = vec![
        format!(
            "Agent App permissions: tools/agent-app/permissions.tsv vs GitHub ({})",
            org
        ),
        String::new(),
    ];
    lines.extend(preamble.iter().cloned());
    for (name, state, details) in results {
        // One detail fits on the App's line; more go underneath it.
        let inline = if details.len() == 1 { &details[0] } else { "" };
        let line = format!(
            "  {:<11} {:<width$}  {}",
            state,
            name,
            inline,
            width = width
        );
        lines.push(line.trim_end_matches(pystr::is_space).to_string());
        if details.len() > 1 {
            for d in details {
                lines.push(format!("  {:<11} {:<width$}  {}", "", "", d, width = width));
            }
        }
    }
    let order = [OK, PENDING, DRIFT, MISSING, UNLISTED, UNREAD];
    let count = |s: &str| results.iter().filter(|(_, st, _)| *st == s).count();
    let summary: Vec<String> = order
        .iter()
        .filter(|s| count(s) > 0)
        .map(|s| format!("{} {}", count(s), s))
        .collect();
    lines.push(String::new());
    lines.push(format!("{} Apps: {}.", results.len(), summary.join(", ")));
    if count(UNREAD) > 0 {
        lines.push("NOT a pass: GitHub could not be read for every App.".into());
        return (2, lines);
    }
    if order.iter().any(|s| *s != OK && count(s) > 0) {
        lines
            .push("How to fix: tools/agent-app/README.md, 'Changing an App's permissions'.".into());
        return (1, lines);
    }
    (0, lines)
}
