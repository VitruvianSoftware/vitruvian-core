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

//! Does a Cargo.lock still match its Cargo.toml files? Offline, no cargo.
//!
//! For every package of the workspace (members and the path dependencies
//! they reach) the lock must hold an entry with the manifest's name and
//! version, and that entry must lock exactly the dependencies the manifest
//! declares. The lock must hold no workspace package that no manifest
//! declares. This is what goes stale when a release bumps a version in
//! Cargo.toml (#4026), or someone edits a dependency list without
//! re-locking.
//!
//! Each declared dependency must also match what the lock holds for it: the
//! locked version meets the version requirement (`png = "0.18"` against a
//! locked 0.17.16 fails), and a git dependency's lock `source` names the same
//! repository and `rev`/`tag`/`branch`, and for a pinned `rev`, that commit
//! (#4172). Crates from a registry or git are not re-resolved: that needs the
//! network, and `bazel run //tools/crates:lock -- --check` does it.

use std::collections::{BTreeMap, BTreeSet, VecDeque};
use std::path::{Component, Path, PathBuf};

// ---------------------------------------------------------------------------
// A TOML subset: enough for Cargo.toml and Cargo.lock (tables, arrays of
// tables, dotted and quoted keys, strings, arrays, inline tables). Scalars
// that are not strings are kept as their text.

#[derive(Debug, Clone, PartialEq)]
pub enum Value {
    Str(String),
    Other(String),
    Array(Vec<Value>),
    Table(BTreeMap<String, Value>),
}

impl Value {
    fn get(&self, key: &str) -> Option<&Value> {
        match self {
            Value::Table(t) => t.get(key),
            _ => None,
        }
    }
    fn str(&self) -> Option<&str> {
        match self {
            Value::Str(s) => Some(s),
            _ => None,
        }
    }
    fn path(&self, keys: &[&str]) -> Option<&Value> {
        keys.iter().try_fold(self, |v, k| v.get(k))
    }
}

struct Parser<'a> {
    s: &'a [u8],
    i: usize,
}

pub fn parse_toml(text: &str) -> Result<Value, String> {
    let mut p = Parser {
        s: text.as_bytes(),
        i: 0,
    };
    let mut root = Value::Table(BTreeMap::new());
    let mut current: Vec<String> = Vec::new();
    loop {
        p.skip_blank_lines();
        if p.eof() {
            return Ok(root);
        }
        if p.peek() == b'[' {
            let array = p.s.get(p.i + 1) == Some(&b'[');
            p.i += if array { 2 } else { 1 };
            let keys = p.key()?;
            p.ws();
            let close: &[u8] = if array { b"]]" } else { b"]" };
            if !p.s[p.i..].starts_with(close) {
                return Err(p.err("expected ] after a table name"));
            }
            p.i += close.len();
            p.end_of_line()?;
            let parent = table_at(&mut root, &keys[..keys.len() - 1], &p)?;
            let last = keys.last().unwrap().clone();
            if array {
                match parent
                    .entry(last)
                    .or_insert_with(|| Value::Array(Vec::new()))
                {
                    Value::Array(items) => items.push(Value::Table(BTreeMap::new())),
                    _ => return Err(p.err("[[table]] names a key that is not an array")),
                }
            } else {
                match parent
                    .entry(last)
                    .or_insert_with(|| Value::Table(BTreeMap::new()))
                {
                    Value::Table(_) => {}
                    _ => return Err(p.err("[table] names a key that is not a table")),
                }
            }
            current = keys;
        } else {
            let keys = p.key()?;
            p.ws();
            if p.eof() || p.peek() != b'=' {
                return Err(p.err("expected ="));
            }
            p.i += 1;
            p.ws();
            let value = p.value()?;
            p.end_of_line()?;
            let table = table_at(&mut root, &current, &p)?;
            insert(table, &keys, value, &p)?;
        }
    }
}

/// The table a header path names; through an array of tables, its last one.
fn table_at<'v>(
    root: &'v mut Value,
    keys: &[String],
    p: &Parser,
) -> Result<&'v mut BTreeMap<String, Value>, String> {
    let mut v = root;
    for k in keys {
        let Value::Table(t) = v else {
            return Err(p.err("a key path runs through a value"));
        };
        v = t
            .entry(k.clone())
            .or_insert_with(|| Value::Table(BTreeMap::new()));
        if let Value::Array(items) = v {
            v = items
                .last_mut()
                .ok_or_else(|| p.err("an empty array of tables"))?;
        }
    }
    match v {
        Value::Table(t) => Ok(t),
        _ => Err(p.err("a key path names a value, not a table")),
    }
}

fn insert(
    table: &mut BTreeMap<String, Value>,
    keys: &[String],
    value: Value,
    p: &Parser,
) -> Result<(), String> {
    let (last, parents) = keys.split_last().unwrap();
    let mut t = table;
    for k in parents {
        match t
            .entry(k.clone())
            .or_insert_with(|| Value::Table(BTreeMap::new()))
        {
            Value::Table(next) => t = next,
            _ => return Err(p.err("a dotted key runs through a value")),
        }
    }
    t.insert(last.clone(), value);
    Ok(())
}

impl Parser<'_> {
    fn eof(&self) -> bool {
        self.i >= self.s.len()
    }
    fn peek(&self) -> u8 {
        self.s[self.i]
    }
    fn err(&self, what: &str) -> String {
        let line = self.s[..self.i.min(self.s.len())]
            .iter()
            .filter(|&&c| c == b'\n')
            .count()
            + 1;
        format!("line {line}: {what}")
    }
    /// Spaces and tabs.
    fn ws(&mut self) {
        while !self.eof() && matches!(self.peek(), b' ' | b'\t') {
            self.i += 1;
        }
    }
    fn comment(&mut self) {
        if !self.eof() && self.peek() == b'#' {
            while !self.eof() && self.peek() != b'\n' {
                self.i += 1;
            }
        }
    }
    /// Whitespace, newlines and comments.
    fn skip_blank_lines(&mut self) {
        loop {
            self.ws();
            self.comment();
            if !self.eof() && matches!(self.peek(), b'\n' | b'\r') {
                self.i += 1;
            } else {
                return;
            }
        }
    }
    fn end_of_line(&mut self) -> Result<(), String> {
        self.ws();
        self.comment();
        if self.eof() || matches!(self.peek(), b'\n' | b'\r') {
            Ok(())
        } else {
            Err(self.err("unexpected text after a value"))
        }
    }
    /// A dotted key: `a`, `"a b".c`, `'x'`.
    fn key(&mut self) -> Result<Vec<String>, String> {
        let mut keys = Vec::new();
        loop {
            self.ws();
            if self.eof() {
                return Err(self.err("expected a key"));
            }
            let k = match self.peek() {
                b'"' | b'\'' => self.string()?,
                _ => {
                    let start = self.i;
                    while !self.eof()
                        && (self.peek().is_ascii_alphanumeric()
                            || matches!(self.peek(), b'_' | b'-'))
                    {
                        self.i += 1;
                    }
                    if start == self.i {
                        return Err(self.err("expected a key"));
                    }
                    String::from_utf8_lossy(&self.s[start..self.i]).into_owned()
                }
            };
            keys.push(k);
            self.ws();
            if !self.eof() && self.peek() == b'.' {
                self.i += 1;
            } else {
                return Ok(keys);
            }
        }
    }
    fn value(&mut self) -> Result<Value, String> {
        if self.eof() {
            return Err(self.err("expected a value"));
        }
        match self.peek() {
            b'"' | b'\'' => Ok(Value::Str(self.string()?)),
            b'[' => {
                self.i += 1;
                let mut items = Vec::new();
                loop {
                    self.skip_blank_lines();
                    if self.eof() {
                        return Err(self.err("unclosed array"));
                    }
                    if self.peek() == b']' {
                        self.i += 1;
                        return Ok(Value::Array(items));
                    }
                    items.push(self.value()?);
                    self.skip_blank_lines();
                    if !self.eof() && self.peek() == b',' {
                        self.i += 1;
                    }
                }
            }
            b'{' => {
                self.i += 1;
                let mut table = BTreeMap::new();
                loop {
                    self.ws();
                    if self.eof() {
                        return Err(self.err("unclosed inline table"));
                    }
                    if self.peek() == b'}' {
                        self.i += 1;
                        return Ok(Value::Table(table));
                    }
                    let keys = self.key()?;
                    self.ws();
                    if self.eof() || self.peek() != b'=' {
                        return Err(self.err("expected = in an inline table"));
                    }
                    self.i += 1;
                    self.ws();
                    let v = self.value()?;
                    insert(&mut table, &keys, v, self)?;
                    self.ws();
                    if !self.eof() && self.peek() == b',' {
                        self.i += 1;
                    }
                }
            }
            _ => {
                let start = self.i;
                while !self.eof()
                    && !matches!(
                        self.peek(),
                        b',' | b']' | b'}' | b'\n' | b'\r' | b'#' | b' ' | b'\t'
                    )
                {
                    self.i += 1;
                }
                if start == self.i {
                    return Err(self.err("expected a value"));
                }
                Ok(Value::Other(
                    String::from_utf8_lossy(&self.s[start..self.i]).into_owned(),
                ))
            }
        }
    }
    /// A basic or literal string, single- or multi-line.
    fn string(&mut self) -> Result<String, String> {
        let q = self.peek();
        let multi = self.s[self.i..].starts_with(if q == b'"' { b"\"\"\"" } else { b"'''" });
        self.i += if multi { 3 } else { 1 };
        if multi && self.s[self.i..].starts_with(b"\n") {
            self.i += 1;
        }
        let mut out = Vec::new();
        loop {
            if self.eof() {
                return Err(self.err("unclosed string"));
            }
            let c = self.peek();
            if c == q && (!multi || self.s[self.i..].starts_with(&[q, q, q])) {
                self.i += if multi { 3 } else { 1 };
                return Ok(String::from_utf8_lossy(&out).into_owned());
            }
            if c == b'\n' && !multi {
                return Err(self.err("newline in a string"));
            }
            if c == b'\\' && q == b'"' {
                self.i += 1;
                if self.eof() {
                    return Err(self.err("unclosed string"));
                }
                let e = self.peek();
                self.i += 1;
                match e {
                    b'n' => out.push(b'\n'),
                    b't' => out.push(b'\t'),
                    b'r' => out.push(b'\r'),
                    b'"' => out.push(b'"'),
                    b'\\' => out.push(b'\\'),
                    b'\n' if multi => {
                        while !self.eof() && matches!(self.peek(), b' ' | b'\t' | b'\n' | b'\r') {
                            self.i += 1;
                        }
                    }
                    // \uXXXX and the rest: keep them as written; no name or
                    // version this check compares uses them.
                    other => {
                        out.push(b'\\');
                        out.push(other);
                    }
                }
                continue;
            }
            out.push(c);
            self.i += 1;
        }
    }
}

// ---------------------------------------------------------------------------
// Semver requirements, as cargo reads them: `1.2`, `^1.2.3`, `~1.2`, `=1.2.3`,
// `>=1.2, <2`, `1.*`, `*`. A bare version is a caret requirement.

/// Whether `version` meets the requirement `req`. `None` when this cannot
/// tell (a pre-release, or syntax it does not know): the caller then trusts
/// the lock, since the full re-resolve (`:lock -- --check`) catches the rest.
pub fn req_matches(req: &str, version: &str) -> Option<bool> {
    let v = parse_version(version)?;
    let mut all = true;
    for comparator in req.split(',') {
        all &= comparator_matches(comparator.trim(), v)?;
    }
    Some(all)
}

fn parse_version(v: &str) -> Option<(u64, u64, u64)> {
    let parts: Vec<&str> = v.trim().split('.').collect();
    if parts.len() != 3 {
        return None; // includes a pre-release or build suffix with dots
    }
    // A pre-release or build suffix ("1.0.0-rc1", "1.0.0+x"): not compared.
    let num = |s: &str| s.parse::<u64>().ok();
    Some((num(parts[0])?, num(parts[1])?, num(parts[2])?))
}

fn comparator_matches(c: &str, (a, b, p): (u64, u64, u64)) -> Option<bool> {
    if c == "*" || c.is_empty() {
        return Some(true);
    }
    let (op, rest) = [">=", "<=", ">", "<", "=", "^", "~"]
        .iter()
        .find_map(|op| c.strip_prefix(op).map(|r| (*op, r.trim())))
        .unwrap_or(("", c));
    // Major, then optional minor and patch; a `*`/`x` ends the version.
    let mut nums: Vec<u64> = Vec::new();
    let mut wildcard = false;
    for part in rest.split('.') {
        if matches!(part, "*" | "x" | "X") {
            wildcard = true;
            break;
        }
        nums.push(part.parse().ok()?); // a pre-release suffix fails here
    }
    if nums.is_empty() || nums.len() > 3 {
        return if wildcard && nums.is_empty() && op.is_empty() {
            Some(true)
        } else {
            None
        };
    }
    let op = if op.is_empty() && wildcard { "=" } else { op };
    let (maj, min, pat) = (nums[0], nums.get(1).copied(), nums.get(2).copied());
    let have = (a, b, p);
    // The version cut to the precision the comparator names, and the bound.
    let (cut, bound) = match (min, pat) {
        (None, _) => ((a, 0, 0), (maj, 0, 0)),
        (Some(m), None) => ((a, b, 0), (maj, m, 0)),
        (Some(m), Some(q)) => (have, (maj, m, q)),
    };
    Some(match op {
        "=" => cut == bound,
        ">" => cut > bound,
        ">=" => cut >= bound,
        "<" => cut < bound,
        "<=" => cut <= bound,
        "~" => a == maj && min.map_or(true, |m| b == m && p >= pat.unwrap_or(0)),
        // "^" and a bare version.
        _ => match (maj, min, pat) {
            (0, None, _) => a == 0,
            (0, Some(0), None) => a == 0 && b == 0,
            (0, Some(0), Some(q)) => have == (0, 0, q),
            (0, Some(m), q) => a == 0 && b == m && p >= q.unwrap_or(0),
            (_, m, q) => a == maj && (b, p) >= (m.unwrap_or(0), q.unwrap_or(0)),
        },
    })
}

// ---------------------------------------------------------------------------
// The check.

/// Where a manifest says a dependency comes from.
#[derive(Debug, Clone, PartialEq)]
pub enum DepSource {
    /// crates.io or another registry.
    Registry,
    /// `path = "..."`: a package of the workspace.
    Path,
    /// `git = url`, with the `rev`, `tag` or `branch` it pins, if any, as
    /// cargo writes them in the lock's `source` query (`("rev", "abc")`).
    Git {
        url: String,
        reference: Option<(String, String)>,
    },
}

/// One dependency declaration of a manifest.
#[derive(Debug, Clone, PartialEq)]
pub struct Dep {
    /// The package name (after a `package = "..."` rename).
    pub package: String,
    /// The version requirement, if the manifest gives one.
    pub req: Option<String>,
    pub source: DepSource,
}

impl Dep {
    fn describe(&self) -> String {
        let mut out = self.package.clone();
        if let Some(req) = &self.req {
            out.push_str(&format!(" {req:?}"));
        }
        if let DepSource::Git { url, reference } = &self.source {
            out.push_str(&format!(" (git {url}"));
            if let Some((k, v)) = reference {
                out.push_str(&format!(", {k} = {v}"));
            }
            out.push(')');
        }
        out
    }
}

/// A package of the workspace, as its Cargo.toml declares it.
#[derive(Debug, PartialEq)]
pub struct LocalPackage {
    /// Repo-relative directory.
    pub dir: PathBuf,
    pub name: String,
    pub version: String,
    /// A workspace member: the root, a listed member, or a path dependency
    /// under the workspace root. Cargo locks dev-dependencies for members
    /// only.
    pub member: bool,
    /// Reached only through a `[patch]` `path =` entry. Cargo keeps an
    /// unused patch out of `[[package]]` (it goes in `[[patch.unused]]`).
    pub patch_only: bool,
    /// Every dependency declaration: normal and build, plus dev for members,
    /// on every target. Two aliases of one crate are two declarations.
    pub deps: Vec<Dep>,
}

/// The workspace whose root manifest is `lock_dir/Cargo.toml`.
#[derive(Debug, PartialEq)]
pub struct Workspace {
    pub packages: Vec<LocalPackage>,
    /// Package names the root's `[patch]` tables replace: their locked
    /// source is the patch's, not the one the dependency names.
    pub patched: BTreeSet<String>,
}

const DEP_TABLES: [&str; 3] = ["dependencies", "dev-dependencies", "build-dependencies"];

/// Lexically normalised `dir/rel` (no filesystem access).
pub fn join_normal(dir: &Path, rel: &str) -> PathBuf {
    let mut out: Vec<std::ffi::OsString> = Vec::new();
    for c in dir.join(rel).components() {
        match c {
            Component::CurDir => {}
            Component::ParentDir => {
                out.pop();
            }
            other => out.push(other.as_os_str().to_owned()),
        }
    }
    out.iter().collect()
}

fn dep_of(key: &str, spec: &Value) -> Dep {
    if let Value::Str(req) = spec {
        return Dep {
            package: key.to_string(),
            req: Some(req.clone()),
            source: DepSource::Registry,
        };
    }
    let field = |k: &str| spec.get(k).and_then(Value::str).map(str::to_string);
    let source = if spec.get("path").is_some() {
        DepSource::Path
    } else if let Some(url) = field("git") {
        DepSource::Git {
            url,
            reference: ["rev", "tag", "branch"]
                .iter()
                .find_map(|k| field(k).map(|v| (k.to_string(), v))),
        }
    } else {
        DepSource::Registry
    };
    Dep {
        package: field("package").unwrap_or_else(|| key.to_string()),
        req: field("version"),
        source,
    }
}

/// Every package of the workspace whose root manifest is `lock_dir/Cargo.toml`:
/// its members, the path dependencies they reach, and the root's `[patch]`
/// path entries. `read` reads a repo-relative file.
pub fn local_packages(
    lock_dir: &Path,
    read: &dyn Fn(&Path) -> Option<String>,
) -> Result<Workspace, String> {
    let load = |dir: &Path| -> Result<Value, String> {
        let file = dir.join("Cargo.toml");
        let text = read(&file).ok_or_else(|| format!("cannot read {}", file.display()))?;
        parse_toml(&text).map_err(|e| format!("{}: {e}", file.display()))
    };
    let root = load(lock_dir)?;
    let workspace = root.get("workspace");
    let excluded: Vec<PathBuf> = match workspace.and_then(|w| w.get("exclude")) {
        Some(Value::Array(list)) => list
            .iter()
            .filter_map(Value::str)
            .map(|e| join_normal(lock_dir, e))
            .collect(),
        _ => Vec::new(),
    };
    let inside =
        |dir: &Path| dir.starts_with(lock_dir) && !excluded.iter().any(|e| dir.starts_with(e));

    // (dir, member, patch_only)
    let mut queue: VecDeque<(PathBuf, bool, bool)> = VecDeque::new();
    if root.get("package").is_some() {
        queue.push_back((lock_dir.to_path_buf(), true, false));
    }
    if let Some(Value::Array(members)) = workspace.and_then(|w| w.get("members")) {
        for m in members {
            let m = m.str().ok_or("workspace members must be strings")?;
            if m.contains(['*', '?', '[']) {
                return Err(format!(
                    "{}: member {m:?} is a glob, which this check does not expand; list the members",
                    lock_dir.join("Cargo.toml").display()
                ));
            }
            queue.push_back((join_normal(lock_dir, m), true, false));
        }
    }
    if queue.is_empty() {
        return Err(format!(
            "{} has no [package] and no [workspace] members",
            lock_dir.join("Cargo.toml").display()
        ));
    }
    // `[patch.<source>] foo = { path = ... }`: a local package that is never a
    // member (cargo locks no dev-dependencies for it, even under the root).
    // Queued once the members' own graph is done, so a dir both reach is
    // taken as the members reach it.
    let mut patched = BTreeSet::new();
    let mut patch_dirs = Vec::new();
    if let Some(Value::Table(sources)) = root.get("patch") {
        for entries in sources.values() {
            let Value::Table(entries) = entries else {
                continue;
            };
            for (key, spec) in entries {
                patched.insert(dep_of(key, spec).package);
                if let Some(path) = spec.get("path").and_then(Value::str) {
                    patch_dirs.push(join_normal(lock_dir, path));
                }
            }
        }
    }

    // dir -> index in `out`, so a dir first reached as a non-member is redone
    // when a member reaches it.
    let mut seen: BTreeMap<PathBuf, usize> = BTreeMap::new();
    let mut out: Vec<LocalPackage> = Vec::new();
    loop {
        let Some((dir, member, patch_only)) = queue.pop_front().or_else(|| {
            let dirs = std::mem::take(&mut patch_dirs);
            queue.extend(dirs.into_iter().map(|d| (d, false, true)));
            queue.pop_front()
        }) else {
            break;
        };
        if let Some(&i) = seen.get(&dir) {
            if out[i].member || !member {
                continue;
            }
        }
        let manifest = if dir == lock_dir {
            root.clone()
        } else {
            load(&dir)?
        };
        let where_ = dir.join("Cargo.toml").display().to_string();
        let package = manifest
            .get("package")
            .ok_or_else(|| format!("{where_}: no [package]"))?;
        let name = package
            .get("name")
            .and_then(Value::str)
            .ok_or_else(|| format!("{where_}: no package name"))?
            .to_string();
        let version = match package.get("version") {
            None => "0.0.0".to_string(), // cargo's default since 1.75
            Some(Value::Str(v)) => v.clone(),
            Some(v) if v.get("workspace").is_some() => workspace
                .and_then(|w| w.path(&["package", "version"]))
                .and_then(Value::str)
                .ok_or_else(|| {
                    format!("{where_}: version.workspace but no [workspace.package] version")
                })?
                .to_string(),
            Some(_) => return Err(format!("{where_}: package version is not a string")),
        };

        // Cargo does not lock a non-member's dev-dependencies (#4172).
        let kinds: &[&str] = if member {
            &DEP_TABLES
        } else {
            &["dependencies", "build-dependencies"]
        };
        let mut tables: Vec<&Value> = kinds.iter().filter_map(|t| manifest.get(t)).collect();
        if let Some(Value::Table(targets)) = manifest.get("target") {
            for target in targets.values() {
                tables.extend(kinds.iter().filter_map(|t| target.get(t)));
            }
        }
        let mut deps = Vec::new();
        for table in tables {
            let Value::Table(entries) = table else {
                continue;
            };
            for (key, spec) in entries {
                // `foo = { workspace = true }` takes its source and rename
                // from [workspace.dependencies], relative to the root.
                let (spec, base) = if spec.get("workspace").is_some() {
                    let inherited = workspace
                        .and_then(|w| w.path(&["dependencies", key]))
                        .ok_or_else(|| {
                            format!("{where_}: {key} uses workspace = true but [workspace.dependencies] has no {key}")
                        })?;
                    (inherited, lock_dir)
                } else {
                    (spec, dir.as_path())
                };
                let dep = dep_of(key, spec);
                if !deps.contains(&dep) {
                    deps.push(dep);
                }
                if let Some(path) = spec.get("path").and_then(Value::str) {
                    let target = join_normal(base, path);
                    // A path dependency under the root is a member; one
                    // outside it, or reached from a non-member, is not.
                    let child_member = member && !patch_only && inside(&target);
                    queue.push_back((target, child_member, patch_only));
                }
            }
        }
        let package = LocalPackage {
            dir: dir.clone(),
            name,
            version,
            member,
            patch_only,
            deps,
        };
        match seen.get(&dir) {
            Some(&i) => out[i] = package,
            None => {
                seen.insert(dir, out.len());
                out.push(package);
            }
        }
    }
    Ok(Workspace {
        packages: out,
        patched,
    })
}

/// A `[[package]]` of Cargo.lock.
#[derive(Debug)]
struct Locked {
    name: String,
    version: String,
    /// None: a package of the workspace.
    source: Option<String>,
    /// As cargo writes them: "serde", "rand 0.8.5" or
    /// "foo 1.0.0 (registry+...)".
    deps: Vec<String>,
}

fn locked_packages(lock: &Value) -> Vec<Locked> {
    let Some(Value::Array(packages)) = lock.get("package") else {
        return Vec::new();
    };
    let field = |p: &Value, k: &str| p.get(k).and_then(Value::str).map(str::to_string);
    packages
        .iter()
        .map(|p| Locked {
            name: field(p, "name").unwrap_or_default(),
            version: field(p, "version").unwrap_or_default(),
            source: field(p, "source"),
            deps: match p.get("dependencies") {
                Some(Value::Array(d)) => d
                    .iter()
                    .filter_map(Value::str)
                    .map(str::to_string)
                    .collect(),
                _ => Vec::new(),
            },
        })
        .collect()
}

/// A dependency of a locked package: its name, and the package it names, if
/// the lock names exactly one.
fn resolve<'l>(dep: &str, all: &'l [Locked]) -> (String, Option<&'l Locked>) {
    let mut parts = dep.splitn(3, ' ');
    let name = parts.next().unwrap_or("").to_string();
    let version = parts.next();
    let source = parts
        .next()
        .map(|s| s.trim_start_matches('(').trim_end_matches(')'));
    let mut hits = all.iter().filter(|l| {
        l.name == name
            && version.map_or(true, |v| l.version == v)
            && source.map_or(true, |s| l.source.as_deref() == Some(s))
    });
    let one = match (hits.next(), hits.next()) {
        (Some(l), None) => Some(l),
        _ => None,
    };
    (name, one)
}

/// `%XX` escapes decoded; anything else, `+` included, kept as written. A
/// version 4 Cargo.lock percent-encodes a git `branch`/`tag`/`rev`
/// (`release/1.0` is written `release%2F1.0`); version 3 writes it as is.
pub fn percent_decode(s: &str) -> String {
    let b = s.as_bytes();
    let mut out = Vec::with_capacity(b.len());
    let mut i = 0;
    while i < b.len() {
        let hex = |c: u8| (c as char).to_digit(16);
        if b[i] == b'%' && i + 2 < b.len() {
            if let (Some(h), Some(l)) = (hex(b[i + 1]), hex(b[i + 2])) {
                out.push((h * 16 + l) as u8);
                i += 3;
                continue;
            }
        }
        out.push(b[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

/// `https://github.com/a/b.git/` and `https://github.com/a/b` are one repo.
fn same_repo(a: &str, b: &str) -> bool {
    let norm = |u: &str| {
        let u = u.trim_end_matches('/');
        u.strip_suffix(".git").unwrap_or(u).to_ascii_lowercase()
    };
    norm(a) == norm(b)
}

/// Whether the locked package `l` (None: the lock names it ambiguously) can
/// be what `d` asks for.
fn satisfies(d: &Dep, l: Option<&Locked>, patched: &BTreeSet<String>) -> bool {
    let Some(l) = l else {
        return true;
    };
    if let Some(req) = &d.req {
        if req_matches(req, &l.version) == Some(false) {
            return false;
        }
    }
    if patched.contains(&d.package) {
        return true; // the patch's source, whatever the dependency names
    }
    let source = l.source.as_deref();
    match &d.source {
        DepSource::Path => source.is_none(),
        DepSource::Registry => source.map_or(false, |s| {
            s.starts_with("registry+") || s.starts_with("sparse+")
        }),
        DepSource::Git { url, reference } => {
            let Some(rest) = source.and_then(|s| s.strip_prefix("git+")) else {
                return false;
            };
            let (base, commit) = rest.split_once('#').unwrap_or((rest, ""));
            let (locked_url, query) = base.split_once('?').unwrap_or((base, ""));
            if !same_repo(locked_url, url) {
                return false;
            }
            let locked_ref = query.split('&').find_map(|kv| {
                let (k, v) = kv.split_once('=')?;
                matches!(k, "rev" | "tag" | "branch").then(|| (k.to_string(), percent_decode(v)))
            });
            if locked_ref != *reference {
                return false;
            }
            // A pinned commit must be the commit the lock holds.
            match reference {
                Some((k, rev)) if k == "rev" && rev.chars().all(|c| c.is_ascii_hexdigit()) => {
                    commit
                        .to_ascii_lowercase()
                        .starts_with(&rev.to_ascii_lowercase())
                }
                _ => true,
            }
        }
    }
}

fn describe_locked(l: Option<&Locked>, name: &str) -> String {
    match l {
        None => name.to_string(),
        Some(l) => match l.source.as_deref() {
            Some(s) if s.starts_with("git+") => format!("{} {} ({s})", l.name, l.version),
            _ => format!("{} {}", l.name, l.version),
        },
    }
}

/// Every way `lock_dir/Cargo.lock` disagrees with the workspace's manifests.
/// Empty: in step.
pub fn lock_problems(
    lock_dir: &Path,
    read: &dyn Fn(&Path) -> Option<String>,
) -> Result<Vec<String>, String> {
    let lock_file = lock_dir.join("Cargo.lock");
    let lock_text =
        read(&lock_file).ok_or_else(|| format!("cannot read {}", lock_file.display()))?;
    let lock = parse_toml(&lock_text).map_err(|e| format!("{}: {e}", lock_file.display()))?;
    let all = locked_packages(&lock);
    let unused_patches: Vec<(String, String)> = match lock.path(&["patch", "unused"]) {
        Some(Value::Array(list)) => list
            .iter()
            .map(|p| {
                let f = |k| p.get(k).and_then(Value::str).unwrap_or("").to_string();
                (f("name"), f("version"))
            })
            .collect(),
        _ => Vec::new(),
    };
    let Workspace { packages, patched } = local_packages(lock_dir, read)?;

    let mut problems = Vec::new();
    for p in &packages {
        let manifest = p.dir.join("Cargo.toml").display().to_string();
        let same_name: Vec<&Locked> = all
            .iter()
            .filter(|l| l.source.is_none() && l.name == p.name)
            .collect();
        let Some(entry) = same_name.iter().find(|l| l.version == p.version) else {
            match same_name.first() {
                None if p.patch_only
                    && unused_patches
                        .iter()
                        .any(|(n, v)| *n == p.name && *v == p.version) => {}
                None => problems.push(format!(
                    "{} {} ({manifest}) is not in Cargo.lock",
                    p.name, p.version
                )),
                Some(l) => problems.push(format!(
                    "{} is {} in {manifest} but {} in Cargo.lock",
                    p.name, p.version, l.version
                )),
            }
            continue;
        };

        // Per package name: every declaration has a locked package that
        // meets it, and every locked package meets some declaration. Two
        // aliases of one crate are two declarations (#4172). Overlapping
        // ones (`rand = "0.8"` beside an alias at `"<=0.9"`) are not
        // re-resolved: one locked rand 0.8.5 meets both, though cargo might
        // now pick two. That is `bazel run //tools/crates:lock -- --check`'s
        // job.
        let locked: Vec<(String, Option<&Locked>)> =
            entry.deps.iter().map(|d| resolve(d, &all)).collect();
        let names: BTreeSet<&str> = p
            .deps
            .iter()
            .map(|d| d.package.as_str())
            .chain(locked.iter().map(|(n, _)| n.as_str()))
            .collect();
        for name in names {
            let decls: Vec<&Dep> = p.deps.iter().filter(|d| d.package == name).collect();
            let held: Vec<Option<&Locked>> = locked
                .iter()
                .filter(|(n, _)| n == name)
                .map(|(_, l)| *l)
                .collect();
            let mut used = vec![false; held.len()];
            let mut unmet = Vec::new();
            for d in &decls {
                let mut met = false;
                for (i, l) in held.iter().enumerate() {
                    if satisfies(d, *l, &patched) {
                        used[i] = true;
                        met = true;
                    }
                }
                if !met {
                    unmet.push(*d);
                }
            }
            for d in &unmet {
                if held.is_empty() {
                    problems.push(format!(
                        "{} depends on {name} ({manifest}), but Cargo.lock does not lock it",
                        p.name
                    ));
                } else {
                    let locks: Vec<String> =
                        held.iter().map(|l| describe_locked(*l, name)).collect();
                    problems.push(format!(
                        "{} depends on {} ({manifest}), but Cargo.lock locks {}",
                        p.name,
                        d.describe(),
                        locks.join(", ")
                    ));
                }
            }
            if !unmet.is_empty() {
                continue; // the unused locked versions are named above
            }
            for (l, _) in held.iter().zip(&used).filter(|(_, u)| !**u) {
                if decls.is_empty() {
                    problems.push(format!(
                        "Cargo.lock locks {name} for {}, which {manifest} no longer declares",
                        p.name
                    ));
                } else {
                    problems.push(format!(
                        "Cargo.lock locks {} for {}, which {manifest} no longer declares",
                        describe_locked(*l, name),
                        p.name
                    ));
                }
            }
        }
    }
    for l in all.iter().filter(|l| l.source.is_none()) {
        if !packages.iter().any(|p| p.name == l.name) {
            problems.push(format!(
                "Cargo.lock holds {} {}, which no Cargo.toml of this workspace declares",
                l.name, l.version
            ));
        }
    }
    Ok(problems)
}

/// The manifests (repo-relative Cargo.toml paths) that no lock checks:
/// neither the root of a workspace with a Cargo.lock nor a package one of
/// those workspaces holds. `covered` is every such root and package dir.
/// Such a manifest is never checked at all, as
/// apps/web/oauth-user-inspector/server was before it had a lock (#4172).
pub fn unlocked_manifests(manifests: &[PathBuf], covered: &BTreeSet<PathBuf>) -> Vec<PathBuf> {
    manifests
        .iter()
        .filter(|m| !covered.contains(m.parent().unwrap_or(Path::new(""))))
        .cloned()
        .collect()
}

/// The re-lock command for the lock in `lock_dir`.
pub fn relock_hint(lock_dir: &Path) -> String {
    if lock_dir.as_os_str().is_empty() {
        "bazel run //tools/crates:lock".to_string()
    } else {
        format!(
            "bazel run //tools/crates:lock -- --dir {}",
            lock_dir.display()
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;

    fn files(list: &[(&str, &str)]) -> HashMap<PathBuf, String> {
        list.iter()
            .map(|(p, b)| (PathBuf::from(p), b.to_string()))
            .collect()
    }

    fn problems(list: &[(&str, &str)], dir: &str) -> Vec<String> {
        let fs = files(list);
        lock_problems(Path::new(dir), &|p: &Path| fs.get(p).cloned()).unwrap()
    }

    const ROOT: &str = r#"
[workspace]
resolver = "2"
members = [
    "kits/rust",   # the kit
    "samples/hello",
]
"#;
    const KIT: &str = r#"
[package]
name = "tool-kit"
version = "1.9.0"
description = """
A kit.
"""

[dependencies]
serde = { version = "1.0.190", features = ["derive"] }
serde_json = "1"
"#;
    const HELLO: &str = r#"
[package]
name = "hello"
version = "0.1.0"

[dependencies]
tool-kit = { version = "1.9.0", path = "../../kits/rust" }

[target.'cfg(unix)'.dev-dependencies]
rand_alias = { package = "rand", version = "0.8" }
"#;
    const LOCK: &str = r#"
# This file is automatically @generated by Cargo.
version = 4

[[package]]
name = "hello"
version = "0.1.0"
dependencies = [
 "rand",
 "tool-kit",
]

[[package]]
name = "rand"
version = "0.8.5"
source = "registry+https://github.com/rust-lang/crates.io-index"

[[package]]
name = "serde"
version = "1.0.200"
source = "registry+https://github.com/rust-lang/crates.io-index"

[[package]]
name = "serde_json"
version = "1.0.1"
source = "registry+https://github.com/rust-lang/crates.io-index"
dependencies = [
 "serde",
]

[[package]]
name = "tool-kit"
version = "1.9.0"
dependencies = [
 "serde",
 "serde_json",
]
"#;

    fn workspace(kit: &str, hello: &str, lock: &str) -> Vec<String> {
        problems(
            &[
                ("Cargo.toml", ROOT),
                ("kits/rust/Cargo.toml", kit),
                ("samples/hello/Cargo.toml", hello),
                ("Cargo.lock", lock),
            ],
            "",
        )
    }

    #[test]
    fn a_lock_in_step_has_no_problems() {
        assert_eq!(workspace(KIT, HELLO, LOCK), Vec::<String>::new());
    }

    #[test]
    fn a_version_bumped_without_relocking_is_caught() {
        // What release-please did to the root lock (#4026).
        let bumped = KIT.replace("version = \"1.9.0\"", "version = \"1.10.0\"");
        assert_eq!(
            workspace(&bumped, HELLO, LOCK),
            vec!["tool-kit is 1.10.0 in kits/rust/Cargo.toml but 1.9.0 in Cargo.lock".to_string()]
        );
    }

    #[test]
    fn an_added_or_removed_dependency_is_caught() {
        let added = KIT.replace("serde_json = \"1\"", "serde_json = \"1\"\nlog = \"0.4\"");
        assert_eq!(
            workspace(&added, HELLO, LOCK),
            vec![
                "tool-kit depends on log (kits/rust/Cargo.toml), but Cargo.lock does not lock it"
                    .to_string()
            ]
        );
        let removed = KIT.replace("serde_json = \"1\"\n", "");
        assert_eq!(
            workspace(&removed, HELLO, LOCK),
            vec!["Cargo.lock locks serde_json for tool-kit, which kits/rust/Cargo.toml no longer declares".to_string()]
        );
    }

    #[test]
    fn a_renamed_or_dropped_member_is_caught() {
        let renamed = HELLO.replace("name = \"hello\"", "name = \"hi\"");
        assert_eq!(
            workspace(KIT, &renamed, LOCK),
            vec![
                "hi 0.1.0 (samples/hello/Cargo.toml) is not in Cargo.lock".to_string(),
                "Cargo.lock holds hello 0.1.0, which no Cargo.toml of this workspace declares"
                    .to_string(),
            ]
        );
    }

    #[test]
    fn path_dependencies_outside_the_members_are_followed() {
        // verification's shape: the root is a package with a path dep.
        let list = [
            (
                "v/Cargo.toml",
                "[workspace]\n\n[package]\nname = \"v\"\n\n[dependencies]\nc = { path = \"cargo/c\" }\n",
            ),
            ("v/cargo/c/Cargo.toml", "[package]\nname = \"c\"\nversion = \"0.2.0\"\n"),
            (
                "v/Cargo.lock",
                "version = 4\n\n[[package]]\nname = \"c\"\nversion = \"0.1.0\"\n\n[[package]]\nname = \"v\"\nversion = \"0.0.0\"\ndependencies = [\"c\"]\n",
            ),
        ];
        assert_eq!(
            problems(&list, "v"),
            vec!["c is 0.2.0 in v/cargo/c/Cargo.toml but 0.1.0 in Cargo.lock".to_string()]
        );
    }

    #[test]
    fn workspace_inheritance_is_followed() {
        let list = [
            (
                "Cargo.toml",
                "[workspace]\nmembers = [\"a\"]\n[workspace.package]\nversion = \"2.0.0\"\n[workspace.dependencies]\nlogger = { package = \"log\", version = \"0.4\" }\n",
            ),
            (
                "a/Cargo.toml",
                "[package]\nname = \"a\"\nversion.workspace = true\n\n[dependencies]\nlogger.workspace = true\n",
            ),
            (
                "Cargo.lock",
                "[[package]]\nname = \"a\"\nversion = \"2.0.0\"\ndependencies = [\n \"log 0.4.21 (registry+https://x)\",\n]\n",
            ),
        ];
        assert_eq!(problems(&list, ""), Vec::<String>::new());
    }

    #[test]
    fn git_and_registry_packages_are_not_workspace_packages() {
        let list = [
            (
                "Cargo.toml",
                "[package]\nname = \"ffi\"\nversion = \"0.0.0\"\n[dependencies]\nsig = { git = \"https://x\", rev = \"abc\" }\n",
            ),
            (
                "Cargo.lock",
                "[[package]]\nname = \"ffi\"\nversion = \"0.0.0\"\ndependencies = [\"sig\"]\n\n[[package]]\nname = \"sig\"\nversion = \"0.1.0\"\nsource = \"git+https://x?rev=abc#abc\"\n",
            ),
        ];
        assert_eq!(problems(&list, ""), Vec::<String>::new());
    }

    #[test]
    fn reads_version_requirements_as_cargo_does() {
        let yes = [
            ("0.17", "0.17.16"),
            ("^1.2.3", "1.9.0"),
            ("1", "1.0.1"),
            ("0.0.3", "0.0.3"),
            ("~1.2", "1.2.9"),
            ("~1.2.3", "1.2.4"),
            ("=1.2.3", "1.2.3"),
            (">=1.2, <2", "1.5.0"),
            ("1.*", "1.7.0"),
            ("*", "9.9.9"),
            ("> 1.2", "1.3.0"),
            ("<=1.2", "1.2.7"),
        ];
        for (req, v) in yes {
            assert_eq!(req_matches(req, v), Some(true), "{req} vs {v}");
        }
        let no = [
            ("0.18", "0.17.16"),
            ("0.17", "0.18.0"),
            ("^1.2.3", "1.2.2"),
            ("1", "2.0.0"),
            ("0.0.3", "0.0.4"),
            ("~1.2", "1.3.0"),
            ("=1.2.3", "1.2.4"),
            (">=1.2, <2", "2.0.0"),
            ("1.2.*", "1.3.0"),
            ("> 1.2", "1.2.9"),
        ];
        for (req, v) in no {
            assert_eq!(req_matches(req, v), Some(false), "{req} vs {v}");
        }
        // Pre-releases and unknown syntax: no verdict, so no false failure.
        assert_eq!(req_matches("1.0.0-rc.1", "1.0.0-rc.1"), None);
        assert_eq!(req_matches("1", "1.0.0-beta"), None);
        assert_eq!(req_matches("what", "1.0.0"), None);
    }

    #[test]
    fn a_registry_requirement_changed_without_relocking_is_caught() {
        // `png = "0.17"` -> `"0.18"` (#4172): same name, so only the
        // version tells.
        let bumped = HELLO.replace("version = \"0.8\"", "version = \"0.9\"");
        assert_eq!(
            workspace(KIT, &bumped, LOCK),
            vec!["hello depends on rand \"0.9\" (samples/hello/Cargo.toml), but Cargo.lock locks rand 0.8.5".to_string()]
        );
        let kit = KIT.replace("serde_json = \"1\"", "serde_json = \"2\"");
        assert_eq!(
            workspace(&kit, HELLO, LOCK),
            vec!["tool-kit depends on serde_json \"2\" (kits/rust/Cargo.toml), but Cargo.lock locks serde_json 1.0.1".to_string()]
        );
    }

    fn git_lock(source: &str) -> String {
        format!("[[package]]\nname = \"ffi\"\nversion = \"0.0.0\"\ndependencies = [\"sig\"]\n\n[[package]]\nname = \"sig\"\nversion = \"0.1.0\"\nsource = \"{source}\"\n")
    }

    fn git_problems(spec: &str, source: &str) -> Vec<String> {
        let manifest = format!(
            "[package]\nname = \"ffi\"\nversion = \"0.0.0\"\n[dependencies]\nsig = {spec}\n"
        );
        problems(
            &[("Cargo.toml", &manifest), ("Cargo.lock", &git_lock(source))],
            "",
        )
    }

    #[test]
    fn a_git_source_changed_without_relocking_is_caught() {
        const SHA: &str = "8fc2113bda042fc972a166a24b974b0d34155c6c";
        let locked = format!("git+https://github.com/s/l?rev={SHA}#{SHA}");
        let pinned = format!("{{ git = \"https://github.com/s/l\", rev = \"{SHA}\" }}");
        assert_eq!(git_problems(&pinned, &locked), Vec::<String>::new());
        // `.git` and a trailing slash name the same repository.
        let dotgit = format!("{{ git = \"https://github.com/s/l.git/\", rev = \"{SHA}\" }}");
        assert_eq!(git_problems(&dotgit, &locked), Vec::<String>::new());
        // A short rev matches the commit it abbreviates.
        let short =
            "git+https://github.com/s/l?rev=8fc2113#8fc2113bda042fc972a166a24b974b0d34155c6c";
        assert_eq!(
            git_problems(
                "{ git = \"https://github.com/s/l\", rev = \"8fc2113\" }",
                short
            ),
            Vec::<String>::new()
        );

        let moved = "{ git = \"https://github.com/s/l\", rev = \"1234abcd\" }";
        assert_eq!(
            git_problems(moved, &locked),
            vec![format!("ffi depends on sig (git https://github.com/s/l, rev = 1234abcd) (Cargo.toml), but Cargo.lock locks sig 0.1.0 ({locked})")]
        );
        // The rev in the query matches but the locked commit is another one.
        let other = format!("git+https://github.com/s/l?rev=8fc2113#1234{}", &SHA[4..]);
        assert_eq!(
            git_problems(
                "{ git = \"https://github.com/s/l\", rev = \"8fc2113\" }",
                &other
            )
            .len(),
            1
        );
        // tag -> branch, a new repository, and dropping the pin.
        let tagged = "git+https://github.com/s/l?tag=v5#abc";
        assert_eq!(
            git_problems("{ git = \"https://github.com/s/l\", tag = \"v5\" }", tagged),
            Vec::<String>::new()
        );
        assert_eq!(
            git_problems("{ git = \"https://github.com/s/l\", tag = \"v6\" }", tagged).len(),
            1
        );
        assert_eq!(
            git_problems(
                "{ git = \"https://github.com/s/l\", branch = \"v5\" }",
                tagged
            )
            .len(),
            1
        );
        assert_eq!(
            git_problems(
                "{ git = \"https://github.com/fork/l\", tag = \"v5\" }",
                tagged
            )
            .len(),
            1
        );
        assert_eq!(
            git_problems("{ git = \"https://github.com/s/l\" }", tagged).len(),
            1
        );
        assert_eq!(
            git_problems(
                "{ git = \"https://github.com/s/l\" }",
                "git+https://github.com/s/l#abc"
            ),
            Vec::<String>::new()
        );
        // A registry dependency now taken from git, and back.
        assert_eq!(git_problems("\"0.1\"", tagged).len(), 1);
        assert_eq!(
            git_problems(
                "{ git = \"https://github.com/s/l\", tag = \"v5\" }",
                "registry+https://github.com/rust-lang/crates.io-index"
            )
            .len(),
            1
        );
    }

    #[test]
    fn a_git_ref_cargo_percent_encodes_is_decoded() {
        // Both from cargo 1.99.1 (`bazel run //tools/crates:lock`) locking
        // `log = { git = "https://github.com/rust-lang/log", branch =
        // "fix/lifetime-rules" }`: a version 3 lock writes the branch as is,
        // a version 4 lock percent-encodes it (#4200 review).
        const COMMIT: &str = "956640dca67d9f36be6b5aaaca941729fa757791";
        let spec =
            "{ git = \"https://github.com/rust-lang/log\", branch = \"fix/lifetime-rules\" }";
        for query in ["branch=fix/lifetime-rules", "branch=fix%2Flifetime-rules"] {
            let source = format!("git+https://github.com/rust-lang/log?{query}#{COMMIT}");
            assert_eq!(
                git_problems(spec, &source),
                Vec::<String>::new(),
                "{source}"
            );
        }
        // Still compared after decoding.
        let other = format!("git+https://github.com/rust-lang/log?branch=fix%2Fother#{COMMIT}");
        assert_eq!(git_problems(spec, &other).len(), 1);
        // Any reserved character, in a tag too; `+` stays `+`.
        let tag = "git+https://github.com/s/l?tag=v1%2Bbuild%2Fx#abc";
        assert_eq!(
            git_problems(
                "{ git = \"https://github.com/s/l\", tag = \"v1+build/x\" }",
                tag
            ),
            Vec::<String>::new()
        );
        assert_eq!(percent_decode("a%2fb%2Bc+d%zz%"), "a/b+c+d%zz%");
    }

    // The shape cargo 1.9x locks (`bazel run //tools/crates:lock` on this
    // tree, #4172): `outside` is a path dependency outside the workspace root
    // and `pp` a [patch] path crate, so neither is a member and cargo locks
    // neither one's dev-dependencies; `inner` is a path dependency under the
    // root, so it is a member and its dev-dependency is locked.
    const EDGE_ROOT: &str =
        "[workspace]\nresolver = \"2\"\nmembers = [\"a\"]\n\n[patch.crates-io]\npp = { path = \"pp\" }\n";
    const EDGE_A: &str = "[package]\nname = \"a\"\nversion = \"0.1.0\"\n[dependencies]\noutside = { path = \"../../outside\" }\ninner = { path = \"../inner\" }\npp = \"0.1\"\n";
    const EDGE_LOCK: &str = r#"version = 3

[[package]]
name = "a"
version = "0.1.0"
dependencies = [
 "inner",
 "outside",
 "pp",
]

[[package]]
name = "inner"
version = "0.1.0"
dependencies = [
 "innerdev",
]

[[package]]
name = "innerdev"
version = "0.1.0"

[[package]]
name = "outside"
version = "0.1.0"

[[package]]
name = "pp"
version = "0.1.0"
"#;

    fn edge(pp: &str, lock: &str) -> Vec<String> {
        let leaf = |n: &str| format!("[package]\nname = \"{n}\"\nversion = \"0.1.0\"\n");
        let with_dev = |n: &str, d: &str| {
            format!(
                "{}[dev-dependencies]\n{d} = {{ path = \"../{d}\" }}\n",
                leaf(n)
            )
        };
        problems(
            &[
                ("s/ws/Cargo.toml", EDGE_ROOT),
                ("s/ws/a/Cargo.toml", EDGE_A),
                ("s/outside/Cargo.toml", &with_dev("outside", "outdev")),
                ("s/outdev/Cargo.toml", &leaf("outdev")),
                ("s/ws/inner/Cargo.toml", &with_dev("inner", "innerdev")),
                ("s/ws/innerdev/Cargo.toml", &leaf("innerdev")),
                ("s/ws/pp/Cargo.toml", pp),
                ("s/ws/ppdev/Cargo.toml", &leaf("ppdev")),
                ("s/ws/Cargo.lock", lock),
            ],
            "s/ws",
        )
    }

    const EDGE_PP: &str = "[package]\nname = \"pp\"\nversion = \"0.1.0\"\n[dev-dependencies]\nppdev = { path = \"../ppdev\" }\n";

    #[test]
    fn non_members_and_path_patches_are_not_false_failures() {
        assert_eq!(edge(EDGE_PP, EDGE_LOCK), Vec::<String>::new());
        // A member's dev-dependency is still required.
        let no_innerdev = EDGE_LOCK.replace(" \"innerdev\",\n", "");
        assert_eq!(
            edge(EDGE_PP, &no_innerdev),
            vec!["inner depends on innerdev (s/ws/inner/Cargo.toml), but Cargo.lock does not lock it".to_string()]
        );
        // A path patch is still a local package: its version is checked.
        let bumped = EDGE_PP.replace("0.1.0", "0.2.0");
        assert_eq!(
            edge(&bumped, EDGE_LOCK),
            vec!["pp is 0.2.0 in s/ws/pp/Cargo.toml but 0.1.0 in Cargo.lock".to_string()]
        );
        // An unused patch is in [[patch.unused]], not [[package]].
        let unused = EDGE_LOCK.replace(" \"pp\",\n", "").replace(
            "[[package]]\nname = \"pp\"\nversion = \"0.1.0\"\n",
            "[[patch.unused]]\nname = \"pp\"\nversion = \"0.1.0\"\n",
        );
        let a = EDGE_A.replace("pp = \"0.1\"\n", "");
        let fs = files(&[
            ("Cargo.toml", EDGE_ROOT),
            ("a/Cargo.toml", &a.replace("../../outside", "../o")),
            ("o/Cargo.toml", "[package]\nname = \"outside\"\nversion = \"0.1.0\"\n"),
            ("inner/Cargo.toml", "[package]\nname = \"inner\"\nversion = \"0.1.0\"\n[dependencies]\ninnerdev = { path = \"../innerdev\" }\n"),
            ("innerdev/Cargo.toml", "[package]\nname = \"innerdev\"\nversion = \"0.1.0\"\n"),
            ("pp/Cargo.toml", EDGE_PP),
            ("Cargo.lock", &unused),
        ]);
        assert_eq!(
            lock_problems(Path::new(""), &|p: &Path| fs.get(p).cloned()).unwrap(),
            Vec::<String>::new()
        );
    }

    fn alias_problems(manifest_deps: &str, lock_deps: &str, lock_versions: &[&str]) -> Vec<String> {
        let manifest = format!(
            "[package]\nname = \"x\"\nversion = \"0.0.0\"\n[dependencies]\n{manifest_deps}"
        );
        let mut lock = format!(
            "[[package]]\nname = \"x\"\nversion = \"0.0.0\"\ndependencies = [{lock_deps}]\n"
        );
        for v in lock_versions {
            lock.push_str(&format!("\n[[package]]\nname = \"rand\"\nversion = \"{v}\"\nsource = \"registry+https://github.com/rust-lang/crates.io-index\"\n"));
        }
        problems(&[("Cargo.toml", &manifest), ("Cargo.lock", &lock)], "")
    }

    #[test]
    fn two_aliases_of_one_crate_are_checked_apart() {
        let both = "rand07 = { package = \"rand\", version = \"0.7\" }\nrand = \"0.8\"\n";
        let locked_both = "\"rand 0.7.3\", \"rand 0.8.5\"";
        assert_eq!(
            alias_problems(both, locked_both, &["0.7.3", "0.8.5"]),
            Vec::<String>::new()
        );
        // One alias dropped: its version stays locked.
        assert_eq!(
            alias_problems("rand = \"0.8\"\n", locked_both, &["0.7.3", "0.8.5"]),
            vec![
                "Cargo.lock locks rand 0.7.3 for x, which Cargo.toml no longer declares"
                    .to_string()
            ]
        );
        // One alias added: the lock has no version for it.
        assert_eq!(
            alias_problems(both, "\"rand\"", &["0.8.5"]),
            vec![
                "x depends on rand \"0.7\" (Cargo.toml), but Cargo.lock locks rand 0.8.5"
                    .to_string()
            ]
        );
    }

    #[test]
    fn a_manifest_no_lock_covers_is_reported() {
        let paths = |v: &[&str]| v.iter().map(PathBuf::from).collect::<Vec<_>>();
        let manifests = paths(&[
            "Cargo.toml",
            "kits/rust/Cargo.toml",
            "apps/web/oauth-user-inspector/server/Cargo.toml",
        ]);
        let mut covered: BTreeSet<PathBuf> = paths(&["", "kits/rust"]).into_iter().collect();
        assert_eq!(
            unlocked_manifests(&manifests, &covered),
            paths(&["apps/web/oauth-user-inspector/server/Cargo.toml"])
        );
        covered.insert(PathBuf::from("apps/web/oauth-user-inspector/server"));
        assert_eq!(
            unlocked_manifests(&manifests, &covered),
            Vec::<PathBuf>::new()
        );
    }

    #[test]
    fn globbed_members_are_refused_not_skipped() {
        let fs = files(&[
            ("Cargo.toml", "[workspace]\nmembers = [\"crates/*\"]\n"),
            ("Cargo.lock", ""),
        ]);
        let err = lock_problems(Path::new(""), &|p: &Path| fs.get(p).cloned()).unwrap_err();
        assert!(err.contains("glob"), "{err}");
    }

    #[test]
    fn parses_the_toml_cargo_writes() {
        let v = parse_toml(
            "a = 'lit'\n\"q.k\" = \"x\\\"y\" # c\n[t.u]\nb = [1, 2,\n  # c\n 3]\nc = { d = { e = \"f\" } }\n",
        )
        .unwrap();
        assert_eq!(v.get("a"), Some(&Value::Str("lit".into())));
        assert_eq!(v.get("q.k"), Some(&Value::Str("x\"y".into())));
        assert_eq!(
            v.path(&["t", "u", "c", "d", "e"]).and_then(Value::str),
            Some("f")
        );
        assert!(matches!(v.path(&["t", "u", "b"]), Some(Value::Array(a)) if a.len() == 3));
        assert!(parse_toml("a = \"open\n").is_err());
        assert!(parse_toml("a = 1 b = 2\n").is_err());
    }

    #[test]
    fn hints_name_the_lock() {
        assert_eq!(relock_hint(Path::new("")), "bazel run //tools/crates:lock");
        assert_eq!(
            relock_hint(Path::new("apps/mcp/slack/rs")),
            "bazel run //tools/crates:lock -- --dir apps/mcp/slack/rs"
        );
    }
}
