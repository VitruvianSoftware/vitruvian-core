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
//! re-locking. Crates from a registry or git are not re-resolved: that needs
//! the network, and `bazel run //tools/crates:lock -- --check` does it.

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
// The check.

/// A package of the workspace, as its Cargo.toml declares it.
#[derive(Debug, PartialEq)]
pub struct LocalPackage {
    /// Repo-relative directory.
    pub dir: PathBuf,
    pub name: String,
    pub version: String,
    /// Package names (after `package = "..."` renames) of every dependency:
    /// normal, dev and build, on every target.
    pub deps: BTreeSet<String>,
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

/// Every package of the workspace whose root manifest is `lock_dir/Cargo.toml`:
/// its members, and the path dependencies they reach. `read` reads a
/// repo-relative file.
pub fn local_packages(
    lock_dir: &Path,
    read: &dyn Fn(&Path) -> Option<String>,
) -> Result<Vec<LocalPackage>, String> {
    let load = |dir: &Path| -> Result<Value, String> {
        let file = dir.join("Cargo.toml");
        let text = read(&file).ok_or_else(|| format!("cannot read {}", file.display()))?;
        parse_toml(&text).map_err(|e| format!("{}: {e}", file.display()))
    };
    let root = load(lock_dir)?;
    let workspace = root.get("workspace");

    let mut queue: VecDeque<PathBuf> = VecDeque::new();
    if root.get("package").is_some() {
        queue.push_back(lock_dir.to_path_buf());
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
            queue.push_back(join_normal(lock_dir, m));
        }
    }
    if queue.is_empty() {
        return Err(format!(
            "{} has no [package] and no [workspace] members",
            lock_dir.join("Cargo.toml").display()
        ));
    }

    let mut seen = BTreeSet::new();
    let mut out = Vec::new();
    while let Some(dir) = queue.pop_front() {
        if !seen.insert(dir.clone()) {
            continue;
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

        let mut tables: Vec<&Value> = DEP_TABLES.iter().filter_map(|t| manifest.get(t)).collect();
        if let Some(Value::Table(targets)) = manifest.get("target") {
            for target in targets.values() {
                tables.extend(DEP_TABLES.iter().filter_map(|t| target.get(t)));
            }
        }
        let mut deps = BTreeSet::new();
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
                let package_name = spec.get("package").and_then(Value::str).unwrap_or(key);
                deps.insert(package_name.to_string());
                if let Some(path) = spec.get("path").and_then(Value::str) {
                    queue.push_back(join_normal(base, path));
                }
            }
        }
        out.push(LocalPackage {
            dir,
            name,
            version,
            deps,
        });
    }
    Ok(out)
}

/// A Cargo.lock entry with no `source`: a package of the workspace.
#[derive(Debug)]
struct LockedLocal {
    name: String,
    version: String,
    deps: BTreeSet<String>,
}

fn locked_locals(lock: &Value) -> Vec<LockedLocal> {
    let Some(Value::Array(packages)) = lock.get("package") else {
        return Vec::new();
    };
    packages
        .iter()
        .filter(|p| p.get("source").is_none())
        .map(|p| LockedLocal {
            name: p.get("name").and_then(Value::str).unwrap_or("").to_string(),
            version: p
                .get("version")
                .and_then(Value::str)
                .unwrap_or("")
                .to_string(),
            deps: match p.get("dependencies") {
                // "serde", "rand 0.8.5" or "foo 1.0.0 (registry+...)".
                Some(Value::Array(d)) => d
                    .iter()
                    .filter_map(Value::str)
                    .filter_map(|s| s.split_whitespace().next())
                    .map(str::to_string)
                    .collect(),
                _ => BTreeSet::new(),
            },
        })
        .collect()
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
    let locked = locked_locals(&lock);
    let packages = local_packages(lock_dir, read)?;

    let mut problems = Vec::new();
    for p in &packages {
        let manifest = p.dir.join("Cargo.toml").display().to_string();
        let same_name: Vec<&LockedLocal> = locked.iter().filter(|l| l.name == p.name).collect();
        let Some(entry) = same_name.iter().find(|l| l.version == p.version) else {
            match same_name.first() {
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
        for d in p.deps.difference(&entry.deps) {
            problems.push(format!(
                "{} depends on {d} ({manifest}), but Cargo.lock does not lock it",
                p.name
            ));
        }
        for d in entry.deps.difference(&p.deps) {
            problems.push(format!(
                "Cargo.lock locks {d} for {}, which {manifest} no longer declares",
                p.name
            ));
        }
    }
    for l in &locked {
        if !packages.iter().any(|p| p.name == l.name) {
            problems.push(format!(
                "Cargo.lock holds {} {}, which no Cargo.toml of this workspace declares",
                l.name, l.version
            ));
        }
    }
    Ok(problems)
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
