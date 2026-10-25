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

//! What release_scope.py decides, function for function: which products a
//! pull request releases, which of them it names, and what it says. Read
//! release_scope.py's docstring for why; this file follows its code.
//!
//! The regular expressions are matched by hand, each the way Python's `re`
//! matches it (Unicode `\w` and `\s`, `^` and `$` per line, `.` stopping at
//! a newline, re.IGNORECASE's extra case pairs), because the port takes no
//! crate for them.

use crate::pystr::{find_from, is_space, is_word, starts_with_at, PyStr};
use crate::pyval::{contains, join, set_of, Dict, Exc, PyVal};
use crate::timsort;
use crate::unicode_tables::IGNORECASE;

pub const CONFIG_NAME: &str = "release-please-config.json";
const ROOT_PATH: &str = ".";
const VISIBLE_BY_DEFAULT: [&str; 5] = ["feat", "feature", "fix", "perf", "revert"];
const QUIET_TYPES: &str = "chore, ci, test, docs, refactor, build, style";
/// The types release-please's own message split looks for (src/commit.ts).
const SPLIT_TYPES: [&str; 11] = [
    "feat", "fix", "docs", "style", "refactor", "perf", "test", "build", "ci", "chore", "revert",
];

fn py(s: &str) -> PyStr {
    PyStr::from(s)
}

fn misconfigured(text: PyStr) -> Exc {
    Exc::Misconfigured(text)
}

/// A pull request, its values as GitHub's JSON gave them.
#[derive(Clone, Debug)]
pub struct PullRequest {
    pub title: PyVal,
    pub body: PyVal,
    pub files: Vec<PyStr>,
    /// Each commit's whole message, oldest first.
    pub commits: Vec<PyVal>,
    pub author: PyVal,
    pub author_type: PyVal,
    pub head_ref: PyVal,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Message {
    pub kind: PyStr,
    pub scope: Option<PyStr>,
    pub breaking: bool,
    pub release_as: bool,
    pub header: PyStr,
}

#[derive(Clone, Debug)]
pub struct Component {
    pub name: PyVal,
    pub package_name: PyVal,
    pub path: PyStr,
    pub excludes: Vec<PyStr>,
    /// The commit types that release, as the config wrote them.
    pub visible: Vec<PyVal>,
    /// Every package path in the same config.
    pub siblings: Vec<PyStr>,
    pub config: PyStr,
}

#[derive(Clone, Debug, Default)]
pub struct Verdict {
    pub ok: bool,
    pub exempt: PyStr,
    pub subject: PyStr,
    pub one_commit: bool,
    /// name -> the files that release it, in the order judged.
    pub released: Vec<(PyVal, Vec<PyStr>)>,
    pub named: Vec<PyVal>,
    pub unnamed: Vec<PyVal>,
    /// Names on a Releases: line that no config has.
    pub unknown: Vec<PyStr>,
    /// Named on a Releases: line, not released.
    pub idle: Vec<PyVal>,
    /// name -> the commit line that releases it.
    pub why: Vec<(PyVal, PyStr)>,
    /// name -> its folder.
    pub paths: Vec<(PyVal, PyStr)>,
}

fn lookup<'a, T>(pairs: &'a [(PyVal, T)], key: &PyVal) -> &'a T {
    &pairs
        .iter()
        .find(|(k, _)| k.py_eq(key))
        .expect("judged names have entries")
        .1
}

impl Verdict {
    pub fn released_names(&self) -> Vec<PyVal> {
        self.released.iter().map(|(n, _)| n.clone()).collect()
    }

    pub fn files(&self, name: &PyVal) -> &Vec<PyStr> {
        lookup(&self.released, name)
    }
}

/// release-please's normalizePaths.
pub fn clean(path: &PyStr) -> PyStr {
    let mut p = path.strip();
    while p.starts_with("./") {
        p = p.slice(2, p.len());
    }
    let p = p.strip_chars("/");
    if p.is_empty() {
        py(ROOT_PATH)
    } else {
        p
    }
}

fn under(file: &PyStr, path: &PyStr) -> bool {
    path.eq_str(ROOT_PATH) || {
        let mut prefix = path.clone();
        prefix.push_str("/");
        file.cps().starts_with(prefix.cps())
    }
}

fn dirname(p: &PyStr) -> PyStr {
    let cut = p
        .cps()
        .iter()
        .rposition(|&c| c == '/' as u32)
        .map_or(0, |i| i + 1);
    let head = p.slice(0, cut);
    if !head.is_empty() && head.cps().iter().any(|&c| c != '/' as u32) {
        let mut end = head.len();
        while end > 0 && head.cps()[end - 1] == '/' as u32 {
            end -= 1;
        }
        head.slice(0, end)
    } else {
        head
    }
}

fn basename(p: &PyStr) -> PyStr {
    let cut = p
        .cps()
        .iter()
        .rposition(|&c| c == '/' as u32)
        .map_or(0, |i| i + 1);
    p.slice(cut, p.len())
}

/// `sorted(values)`, by Python's `<`.
pub fn sorted(mut values: Vec<PyVal>) -> Result<Vec<PyVal>, Exc> {
    timsort::sort(&mut values, |a, b| a.lt(b))?;
    Ok(values)
}

/// Every product, from (config's path, the config).
pub fn load_components(mut configs: Vec<(PyStr, PyVal)>) -> Result<Vec<Component>, Exc> {
    configs.sort_by(|a, b| a.0.cmp(&b.0));
    let mut components = Vec::new();
    for (place, config) in &configs {
        let packages = config.get("packages")?;
        let packages = match &packages {
            PyVal::Dict(d) if !d.0.is_empty() => d,
            _ => {
                let mut msg = place.clone();
                msg.push_str(" has no packages");
                return Err(misconfigured(msg));
            }
        };
        let siblings: Vec<PyStr> = packages.0.iter().map(|(raw, _)| clean(raw)).collect();
        for (raw, package) in &packages.0 {
            let path = clean(raw);
            let mut sections = package.get("changelog-sections")?;
            if !sections.truthy() {
                sections = config.get("changelog-sections")?;
            }
            let visible = if sections.truthy() {
                let mut kinds = Vec::new();
                for s in sections.iterate()? {
                    if !s.get("hidden")?.truthy() {
                        let kind = s.index("type")?;
                        kind.check_hashable()?;
                        if !contains(&kinds, &kind) {
                            kinds.push(kind);
                        }
                    }
                }
                kinds
            } else {
                VISIBLE_BY_DEFAULT.iter().map(|k| PyVal::str(k)).collect()
            };
            let folder = if path.eq_str(ROOT_PATH) {
                dirname(place)
            } else {
                path.clone()
            };
            let name = package
                .get("component")?
                .or(package.get("package-name")?)
                .or(PyVal::Str(basename(&folder)));
            if !name.truthy() {
                let mut msg = place.clone();
                msg.push_str(": the package ");
                msg.push_py(raw);
                msg.push_str(" has no name");
                return Err(misconfigured(msg));
            }
            let package_name = package.get("package-name")?;
            let exclude_values = match package {
                PyVal::Dict(d) => match d.get("exclude-paths") {
                    Some(v) => v.iterate()?,
                    None => Vec::new(),
                },
                _ => Vec::new(),
            };
            let mut excludes = Vec::new();
            for e in &exclude_values {
                match e {
                    PyVal::Str(s) => excludes.push(clean(s)),
                    other => return Err(Exc::attribute(other, "strip")),
                }
            }
            components.push(Component {
                name,
                package_name,
                path,
                excludes,
                visible,
                siblings: siblings.clone(),
                config: place.clone(),
            });
        }
    }
    let names: Vec<PyVal> = components.iter().map(|c| c.name.clone()).collect();
    let repeated = names
        .iter()
        .filter(|n| names.iter().filter(|m| m.py_eq(n)).count() > 1)
        .cloned();
    let twice = sorted(set_of(repeated)?)?;
    if !twice.is_empty() {
        let mut msg = py("two release-please packages share a name: ");
        msg.push_py(&join(", ", &twice)?);
        return Err(misconfigured(msg));
    }
    Ok(components)
}

/// aliases.json as [(scope, [component, ...])].
pub fn load_aliases(raw: &PyVal) -> Result<Vec<(PyStr, Vec<PyVal>)>, Exc> {
    let wrap = |e: Exc| match e {
        Exc::KeyError(_) | Exc::TypeError(_) => {
            let mut msg = py("aliases.json is not {aliases: {scope: {components: [...]}}}: ");
            msg.push_py(&e.repr());
            misconfigured(msg)
        }
        other => other,
    };
    let aliases = raw.index("aliases").map_err(wrap)?;
    let entries = match &aliases {
        PyVal::Dict(d) => d,
        other => return Err(Exc::attribute(other, "items")),
    };
    let mut out = Vec::new();
    for (scope, entry) in &entries.0 {
        let components = entry.index("components").map_err(wrap)?;
        out.push((scope.clone(), components.iterate().map_err(wrap)?));
    }
    Ok(out)
}

/// From GitHub's pull request object, its commits' messages and its files.
pub fn pull_request(pr: &PyVal, commits: &PyVal, files: Vec<PyStr>) -> Result<PullRequest, Exc> {
    let empty = || PyVal::Dict(Dict::default());
    let title = pr.get("title")?.or(PyVal::str(""));
    let body = pr.get("body")?.or(PyVal::str(""));
    let commits = commits.iterate()?;
    let author = pr.get("user")?.or(empty()).get("login")?.or(PyVal::str(""));
    let author_type = pr.get("user")?.or(empty()).get("type")?.or(PyVal::str(""));
    let head_ref = pr.get("head")?.or(empty()).get("ref")?.or(PyVal::str(""));
    Ok(PullRequest {
        title,
        body,
        files,
        commits,
        author,
        author_type,
        head_ref,
    })
}

fn body_str(pull: &PullRequest) -> Result<&PyStr, Exc> {
    match &pull.body {
        PyVal::Str(b) => Ok(b),
        other => Err(Exc::attribute(other, "split")),
    }
}

fn strip_commit(c: &PyVal) -> Result<PyStr, Exc> {
    match c {
        PyVal::Str(s) => Ok(s.strip()),
        other => Err(Exc::attribute(other, "strip")),
    }
}

/// The commit message this pull request lands on main under.
pub fn squash_message(pull: &PullRequest) -> Result<PyVal, Exc> {
    let body = body_str(pull)?;
    let after = body
        .splitn("BEGIN_COMMIT_OVERRIDE", 1)
        .get(1)
        .cloned()
        .unwrap_or_default();
    let override_ = after.split("END_COMMIT_OVERRIDE")[0].strip();
    if !override_.is_empty() {
        return Ok(PyVal::Str(override_));
    }
    if pull.commits.len() == 1 {
        return Ok(PyVal::Str(strip_commit(&pull.commits[0])?));
    }
    if pull.commits.is_empty() {
        return Ok(pull.title.clone());
    }
    let mut message = match &pull.title {
        PyVal::Str(t) => t.clone(),
        PyVal::List(_) => {
            return Err(Exc::type_error(
                "can only concatenate list (not \"str\") to list",
            ))
        }
        other => {
            return Err(Exc::TypeError(py(&format!(
                "unsupported operand type(s) for +: '{}' and 'str'",
                other.type_name()
            ))))
        }
    };
    message.push_str("\n\n");
    let mut bullets = Vec::new();
    for c in &pull.commits {
        let mut bullet = py("* ");
        bullet.push_py(&strip_commit(c)?);
        bullets.push(bullet);
    }
    message.push_py(&PyStr::join("\n\n", &bullets));
    Ok(PyVal::Str(message))
}

/// Where `^` matches under re.MULTILINE: the start, and after each newline.
fn line_starts(t: &[u32]) -> impl Iterator<Item = usize> + '_ {
    std::iter::once(0).chain(
        t.iter()
            .enumerate()
            .filter(|(_, &c)| c == 0x0A)
            .map(|(i, _)| i + 1),
    )
}

/// `\s*\S` from `at`: some character from there on is not whitespace.
fn something_after(t: &[u32], at: usize) -> bool {
    at <= t.len() && t[at..].iter().any(|&c| !is_space(c))
}

/// SPLIT's lookahead at q: `(?:feat|fix|...)(?:\(.*?\))?: `.
fn split_lookahead(t: &[u32], q: usize) -> bool {
    for kind in SPLIT_TYPES {
        if !starts_with_at(t, q, kind) {
            continue;
        }
        let r = q + kind.len();
        if r < t.len() && t[r] == '(' as u32 {
            let mut k = r + 1;
            while k < t.len() && t[k] != 0x0A {
                if t[k] == ')' as u32 && starts_with_at(t, k + 1, ": ") {
                    return true;
                }
                k += 1;
            }
        }
        if starts_with_at(t, r, ": ") {
            return true;
        }
    }
    false
}

/// SPLIT at i: `\r?\n\r?\n` then the lookahead; where the match ends.
fn split_match(t: &[u32], i: usize) -> Option<usize> {
    let n = t.len();
    for first_cr in [true, false] {
        let mut p = i;
        if first_cr {
            if p < n && t[p] == 0x0D {
                p += 1;
            } else {
                continue;
            }
        }
        if !(p < n && t[p] == 0x0A) {
            continue;
        }
        p += 1;
        for second_cr in [true, false] {
            let mut q = p;
            if second_cr {
                if q < n && t[q] == 0x0D {
                    q += 1;
                } else {
                    continue;
                }
            }
            if !(q < n && t[q] == 0x0A) {
                continue;
            }
            q += 1;
            if split_lookahead(t, q) {
                return Some(q);
            }
        }
    }
    None
}

/// `SPLIT.split(text)`.
fn split_commits(text: &PyStr) -> Vec<PyStr> {
    let t = text.cps();
    let mut out = Vec::new();
    let (mut last, mut i) = (0, 0);
    while i < t.len() {
        match split_match(t, i) {
            Some(end) => {
                out.push(text.slice(last, i));
                last = end;
                i = end;
            }
            None => i += 1,
        }
    }
    out.push(text.slice(last, t.len()));
    out
}

/// `HEADER.match(line)`: `^(?P<type>\w+)(?:\((?P<scope>[^()]*)\))?(?P<bang>!)?:\s*\S`.
fn header(line: &[u32]) -> Option<(PyStr, Option<PyStr>, bool)> {
    let n = line.len();
    let mut i = 0;
    while i < n && is_word(line[i]) {
        i += 1;
    }
    if i == 0 {
        return None;
    }
    let kind = PyStr(line[..i].to_vec());
    let tail = |p: usize| p < n && line[p] == ':' as u32 && something_after(line, p + 1);
    let rest = |p: usize| -> Option<bool> {
        if p < n && line[p] == '!' as u32 && tail(p + 1) {
            Some(true)
        } else if tail(p) {
            Some(false)
        } else {
            None
        }
    };
    if i < n && line[i] == '(' as u32 {
        let mut k = i + 1;
        while k < n && line[k] != '(' as u32 && line[k] != ')' as u32 {
            k += 1;
        }
        if k < n && line[k] == ')' as u32 {
            if let Some(bang) = rest(k + 1) {
                return Some((kind, Some(PyStr(line[i + 1..k].to_vec())), bang));
            }
        }
    }
    rest(i).map(|bang| (kind, None, bang))
}

/// `BREAKING.search(text)`: `^BREAKING[ -]CHANGE:\s*\S`, multiline.
fn breaking_footer(t: &[u32]) -> bool {
    line_starts(t).any(|p| {
        starts_with_at(t, p, "BREAKING")
            && p + 8 < t.len()
            && (t[p + 8] == ' ' as u32 || t[p + 8] == '-' as u32)
            && starts_with_at(t, p + 9, "CHANGE:")
            && something_after(t, p + 16)
    })
}

/// `RELEASE_AS.search(text)`: `^release-as:\s*\S`, multiline, any case.
fn release_as_footer(t: &[u32]) -> bool {
    let matches = |c: u32, p: char| -> bool {
        match IGNORECASE.iter().find(|(letter, _)| *letter == p) {
            Some((_, set)) => set.contains(&c),
            None => c == p as u32,
        }
    };
    line_starts(t).any(|p| {
        let pattern: Vec<char> = "release-as:".chars().collect();
        p + pattern.len() <= t.len()
            && pattern
                .iter()
                .enumerate()
                .all(|(k, &pc)| matches(t[p + k], pc))
            && something_after(t, p + pattern.len())
    })
}

/// The conventional commits release-please would read in one message.
pub fn messages(message: &PyVal) -> Result<Vec<Message>, Exc> {
    let message = match message {
        PyVal::Str(m) => m,
        other => return Err(Exc::attribute(other, "split")),
    };
    let parts = message.split("BEGIN_NESTED_COMMIT");
    let mut first = parts[0].clone();
    let mut nested = Vec::new();
    for part in &parts[1..] {
        let pieces = part.split("END_NESTED_COMMIT");
        nested.push(pieces[0].clone());
        first.push_py(&PyStr::join("END_NESTED_COMMIT", &pieces[1..]));
    }
    let mut texts: Vec<PyStr> = split_commits(&first)
        .into_iter()
        .filter(|t| !t.is_empty())
        .collect();
    texts.extend(nested);
    let mut found = Vec::new();
    for text in &texts {
        let lines = text.strip().split("\n");
        let Some((kind, scope, bang)) = header(lines[0].cps()) else {
            continue; // release-please cannot parse it, and skips it whole
        };
        let breaking = breaking_footer(text.cps()) || text.contains("BREAKING-CHANGE:");
        found.push(Message {
            kind,
            scope,
            breaking: bang || breaking,
            release_as: release_as_footer(text.cps()),
            header: lines[0].strip(),
        });
        for line in &lines[1..] {
            if let Some((kind, scope, bang)) = header(line.cps()) {
                found.push(Message {
                    kind,
                    scope,
                    breaking: bang,
                    release_as: false,
                    header: line.strip(),
                });
            }
        }
    }
    Ok(found)
}

fn exempt(pull: &PullRequest) -> Result<PyStr, Exc> {
    let head = match &pull.head_ref {
        PyVal::Str(h) => h,
        other => return Err(Exc::attribute(other, "startswith")),
    };
    if head.starts_with("release-please--") {
        let mut msg = py("release-please's own pull request (its branch is ");
        msg.push_py(head);
        msg.push_str(")");
        return Ok(msg);
    }
    if pull.author_type.py_eq(&PyVal::str("Bot"))
        && (head.starts_with("dependabot/") || head.starts_with("renovate/"))
    {
        let mut msg = py("a dependency bot's pull request (");
        msg.push_py(&pull.author.py_str());
        msg.push_str(" on ");
        msg.push_py(head);
        msg.push_str("), which nobody can retitle");
        return Ok(msg);
    }
    Ok(PyStr::new())
}

/// The files that make release-please keep this commit for the component.
fn files_released(component: &Component, files: &[PyStr]) -> Vec<PyStr> {
    let owned: Vec<PyStr> = if component.path.eq_str(ROOT_PATH) {
        files.to_vec()
    } else {
        let mut longest_first: Vec<&PyStr> = component
            .siblings
            .iter()
            .filter(|p| !p.eq_str(ROOT_PATH))
            .collect();
        longest_first.sort_by_key(|p| std::cmp::Reverse(p.len()));
        files
            .iter()
            .filter(|f| {
                f.cps().contains(&('/' as u32))
                    && longest_first
                        .iter()
                        .find(|p| under(f, p))
                        .map_or(false, |p| **p == component.path)
            })
            .cloned()
            .collect()
    };
    if owned.is_empty() {
        return Vec::new();
    }
    if component.excludes.is_empty() {
        return owned;
    }
    files
        .iter()
        .filter(|f| under(f, &component.path))
        .filter(|f| !component.excludes.iter().any(|e| under(f, e)))
        .cloned()
        .collect()
}

/// `RELEASES_LINE.findall(body)`: `^[ \t]*Releases:[ \t]*(\S.*?)[ \t]*\r?$`.
fn releases_lines(body: &PyStr) -> Vec<PyStr> {
    let t = body.cps();
    let blank = |c: u32| c == ' ' as u32 || c == '\t' as u32;
    let mut out = Vec::new();
    for p in line_starts(t) {
        let mut i = p;
        while i < t.len() && blank(t[i]) {
            i += 1;
        }
        if !starts_with_at(t, i, "Releases:") {
            continue;
        }
        i += "Releases:".len();
        while i < t.len() && blank(t[i]) {
            i += 1;
        }
        if i >= t.len() || is_space(t[i]) {
            continue;
        }
        let start = i;
        let line_end = find_from(t, &[0x0A], start).unwrap_or(t.len());
        let mut end = line_end;
        if end > start + 1 && t[end - 1] == 0x0D {
            end -= 1;
        }
        while end > start + 1 && blank(t[end - 1]) {
            end -= 1;
        }
        out.push(body.slice(start, end));
    }
    out
}

/// `re.split(r"[,\s]+", text)`, the empty pieces dropped.
fn names_on(text: &PyStr) -> Vec<PyStr> {
    let mut out = Vec::new();
    let mut current = PyStr::new();
    for &c in text.cps() {
        if c == ',' as u32 || is_space(c) {
            if !current.is_empty() {
                out.push(std::mem::take(&mut current));
            }
        } else {
            current.push(c);
        }
    }
    if !current.is_empty() {
        out.push(current);
    }
    out
}

pub fn judge(
    pull: &PullRequest,
    components: &[Component],
    aliases: &[(PyStr, Vec<PyVal>)],
) -> Result<Verdict, Exc> {
    let mut by_name: Vec<PyVal> = Vec::new();
    for c in components {
        c.name.check_hashable()?;
        if !contains(&by_name, &c.name) {
            by_name.push(c.name.clone());
        }
    }
    for (scope, targets) in aliases {
        let mut missing = Vec::new();
        for t in targets {
            t.check_hashable()?;
            if !contains(&by_name, t) {
                missing.push(t.clone());
            }
        }
        if !missing.is_empty() {
            let mut msg = py("aliases.json: ");
            msg.push_py(scope);
            msg.push_str(" means ");
            msg.push_py(&join(", ", &missing)?);
            msg.push_str(", which no release-please config has");
            return Err(misconfigured(msg));
        }
    }
    let exempt = exempt(pull)?;
    if !exempt.is_empty() {
        return Ok(Verdict {
            ok: true,
            exempt,
            ..Verdict::default()
        });
    }

    let message = squash_message(pull)?;
    let found = messages(&message)?;
    let message = message.as_str().expect("messages() took it as a str");
    let body = body_str(pull)?;
    let mut verdict = Verdict {
        ok: true,
        subject: message.split("\n")[0].clone(),
        one_commit: pull.commits.len() == 1 && !body.contains("BEGIN_COMMIT_OVERRIDE"),
        ..Verdict::default()
    };

    let mut declared = Vec::new();
    for line in releases_lines(body) {
        declared.extend(names_on(&line.replace("`", "")));
    }
    let mut by_package: Vec<(PyVal, PyVal)> = Vec::new();
    for c in components {
        if c.package_name.truthy() {
            c.package_name.check_hashable()?;
            match by_package
                .iter_mut()
                .find(|(k, _)| k.py_eq(&c.package_name))
            {
                Some(slot) => slot.1 = c.name.clone(),
                None => by_package.push((c.package_name.clone(), c.name.clone())),
            }
        }
    }
    let mut declared_names: Vec<PyVal> = Vec::new();
    for name in declared {
        let as_val = PyVal::Str(name.clone());
        let found_name = if contains(&by_name, &as_val) {
            Some(as_val)
        } else {
            by_package
                .iter()
                .find(|(k, _)| k.py_eq(&as_val))
                .map(|(_, v)| v.clone())
        };
        match found_name {
            Some(n) => {
                if !contains(&declared_names, &n) {
                    declared_names.push(n);
                }
            }
            None => {
                if !verdict.unknown.contains(&name) {
                    verdict.unknown.push(name);
                }
            }
        }
    }

    let mut order: Vec<usize> = (0..components.len()).collect();
    timsort::sort(&mut order, |a, b| {
        components[*a].name.lt(&components[*b].name)
    })?;
    for &i in &order {
        let component = &components[i];
        let releasing: Vec<&Message> = found
            .iter()
            .filter(|m| {
                m.breaking
                    || m.release_as
                    || contains(&component.visible, &PyVal::Str(m.kind.clone()))
            })
            .collect();
        if releasing.is_empty() {
            continue;
        }
        let files = files_released(component, &pull.files);
        if files.is_empty() {
            continue;
        }
        verdict.released.push((component.name.clone(), files));
        verdict
            .paths
            .push((component.name.clone(), component.path.clone()));
        verdict
            .why
            .push((component.name.clone(), releasing[0].header.clone()));
        let scopes: Vec<PyVal> = releasing
            .iter()
            .filter_map(|m| m.scope.clone().filter(|s| !s.is_empty()).map(PyVal::Str))
            .collect();
        let named = contains(&declared_names, &component.name)
            || contains(&scopes, &component.name)
            || (component.package_name.truthy() && contains(&scopes, &component.package_name))
            || scopes.iter().any(|scope| {
                aliases
                    .iter()
                    .find(|(s, _)| PyVal::Str(s.clone()).py_eq(scope))
                    .map_or(false, |(_, targets)| contains(targets, &component.name))
            });
        if named {
            verdict.named.push(component.name.clone());
        } else {
            verdict.unnamed.push(component.name.clone());
        }
    }

    let released = verdict.released_names();
    verdict.idle = sorted(
        declared_names
            .into_iter()
            .filter(|n| !contains(&released, n))
            .collect(),
    )?;
    verdict.ok = verdict.unnamed.is_empty() && verdict.unknown.is_empty();
    Ok(verdict)
}

fn listing(verdict: &Verdict, names: &[PyVal], limit: usize, lines: &mut Vec<PyStr>) {
    for name in names {
        let files = verdict.files(name);
        let mut head = py("  ");
        head.push_py(&name.py_str());
        head.push_str("   (its folder is ");
        head.push_py(lookup(&verdict.paths, name));
        head.push_str(")");
        lines.push(head);
        for f in files.iter().take(limit) {
            let mut line = py("      ");
            line.push_py(f);
            lines.push(line);
        }
        if files.len() > limit {
            lines.push(py(&format!("      ... and {} more", files.len() - limit)));
        }
    }
}

/// What the check prints.
pub fn report(verdict: &Verdict) -> Result<PyStr, Exc> {
    if !verdict.exempt.is_empty() {
        let mut out = py("release-scope: not judged. This is ");
        out.push_py(&verdict.exempt);
        out.push_str(".");
        return Ok(out);
    }
    let mut out: Vec<PyStr> = Vec::new();
    let line = |parts: &[&PyStr]| {
        let mut s = PyStr::new();
        for p in parts {
            s.push_py(p);
        }
        s
    };
    if verdict.ok {
        if !verdict.released.is_empty() {
            out.push(line(&[
                &py("release-scope: OK. Merging this proposes a release of: "),
                &join(", ", &verdict.released_names())?,
                &py(". Each is named by the title's scope or a Releases: line."),
            ]));
        } else {
            out.push(py("release-scope: OK. Merging this releases nothing."));
        }
        out.push(line(&[&py("  It lands on main as: "), &verdict.subject]));
        if !verdict.idle.is_empty() {
            out.push(line(&[
                &py("  Note: the Releases: line names "),
                &join(", ", &verdict.idle)?,
                &py(", which this pull request would not release."),
            ]));
        }
        return Ok(PyStr::join("\n", &out));
    }

    out.push(py("release-scope: FAILED."));
    if !verdict.unnamed.is_empty() {
        out.push(py(""));
        out.push(py(
            "Merging this pull request would release a product it does not name.",
        ));
        out.push(py(""));
        out.push(line(&[&py("It lands on main as:  "), &verdict.subject]));
        if verdict.one_commit {
            out.push(py(
                "(It has one commit, so GitHub lands it under that commit's message, not the pull request's title.)",
            ));
        }
        out.push(py(""));
        out.push(py(
            "release-please proposes a release of every product that has a changed file in its",
        ));
        out.push(line(&[
            &py("folder when the commit's type is one that releases. This one's is: "),
            lookup(&verdict.why, &verdict.unnamed[0]),
        ]));
        out.push(py(""));
        out.push(py("Would be released, and NOT named:"));
        listing(verdict, &verdict.unnamed, 8, &mut out);
        if !verdict.named.is_empty() {
            out.push(py(""));
            out.push(py("Would be released, and named (fine):"));
            listing(verdict, &verdict.named, 3, &mut out);
        }
        for text in [
            "",
            "A release with nothing in it publishes the same code again under a new version, or",
            "offers every user an update that changes nothing. Three ways out:",
            "",
            "  1. Split it. Move the files listed above into a pull request of their own, titled",
            "     for that product (or with a type that does not release, if that is what it is).",
            "",
            "  2. If nothing a user of any product gets changes, use a type that does not release:",
        ] {
            out.push(py(text));
        }
        out.push(py(&format!("     {}.", QUIET_TYPES)));
        for text in [
            "",
            "  3. If it truly changes each of these products, say so. Put this line, on its own, in",
            "     the pull request's description:",
            "",
        ] {
            out.push(py(text));
        }
        out.push(line(&[
            &py("         Releases: "),
            &join(", ", &sorted(verdict.released_names())?)?,
        ]));
        out.push(py(""));
        if verdict.one_commit {
            out.push(py(
                "For 1 or 2 with one commit, change the commit's message (the title alone is not",
            ));
            out.push(py(
                "what lands), or push a second commit and the title is used. This check runs again",
            ));
            out.push(py(
                "when the title or the description is edited and when commits are pushed.",
            ));
        } else {
            out.push(py(
                "This check runs again when the title or the description is edited and when commits are pushed.",
            ));
        }
    }
    if !verdict.unknown.is_empty() {
        out.push(py(""));
        out.push(line(&[
            &py("The Releases: line names "),
            &PyStr::join(", ", &verdict.unknown),
            &py(", which no release-please config has."),
        ]));
        out.push(py(
            "Use a product's component name, as in its release-please-config.json.",
        ));
    }
    Ok(PyStr::join("\n", &out))
}
