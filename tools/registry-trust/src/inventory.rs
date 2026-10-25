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

//! Which packages this repository publishes, to which registry, from where:
//! inventory.py, ported. Nothing here is a list somebody keeps. Every
//! answer is read from a file that already has to be right for a release:
//! release-please's configs say what is released, the package file says
//! whether it is public, COMPONENTS in copy.bara.sky says which mirror
//! carries it, and the mirror's own workflows say which job publishes it
//! and in which environment. See inventory.py for the long form.

use std::collections::{BTreeMap, HashSet};
use std::fs;
use std::io::Write;

use crate::json::{self, get_or, Crash, Value};
use crate::py::{self, ReadError};
use crate::toml;

pub const COPYBARA: &str = "tools/copybara/copy.bara.sky";
pub const CONFIG: &str = "release-please-config.json";
/// Folders that hold other people's packages or build output, never ours.
const PRUNED: [&str; 5] = [".git", "node_modules", "scratchpad", "target", "dist"];

pub const REGISTRIES: [&str; 3] = ["npm", "pypi", "crates"];

/// The registry a package file belongs to, and the jsonpath of its own version.
fn file_kind(name: &str) -> Option<(&'static str, &'static str)> {
    match name {
        "package.json" => Some(("npm", "$.version")),
        "pyproject.toml" => Some(("pypi", "$.project.version")),
        "Cargo.toml" => Some(("crates", "$.package.version")),
        _ => None,
    }
}

/// The release-types whose version file is implied, not listed in extra-files.
fn implied(kind: &str) -> Option<&'static str> {
    match kind {
        "node" => Some("package.json"),
        "python" => Some("pyproject.toml"),
        "rust" => Some("Cargo.toml"),
        _ => None,
    }
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct Package {
    pub registry: String,
    pub name: String,
    pub version: String,
    pub file: String,
    pub path: String,
    pub config: String,
    pub owner: String,
    pub repo: String,
    pub workflow: String,
    pub job: String,
    pub environment: String,
    /// The name and version as the package file has them, which `--json`
    /// writes as they are (a version written as a number stays one).
    pub name_value: Value,
    pub version_value: Value,
}

impl Package {
    pub fn repository(&self) -> String {
        format!("{}/{}", self.owner, self.repo)
    }

    /// `package._asdict()`, in the namedtuple's field order.
    pub fn as_value(&self) -> Value {
        json::dict([
            ("registry", json::s(&self.registry)),
            ("name", self.name_value.clone()),
            ("version", self.version_value.clone()),
            ("file", json::s(&self.file)),
            ("path", json::s(&self.path)),
            ("config", json::s(&self.config)),
            ("owner", json::s(&self.owner)),
            ("repo", json::s(&self.repo)),
            ("workflow", json::s(&self.workflow)),
            ("job", json::s(&self.job)),
            ("environment", json::s(&self.environment)),
        ])
    }
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct Inventory {
    pub packages: Vec<Package>,
    pub skipped: Vec<(String, String)>,
    pub problems: Vec<String>,
}

fn read(root: &str, path: &str) -> Result<String, ReadError> {
    py::read_text(&py::join(root, path))
}

/// Every release-please-config.json under root, as paths relative to it,
/// sorted. A walk like os.walk's: symlinked folders are not entered, and
/// pruned folders are not either.
fn configs(root: &str) -> Vec<String> {
    fn walk(dir: &str, rel: &str, found: &mut Vec<String>) {
        let Ok(entries) = fs::read_dir(dir) else {
            return;
        };
        let mut folders = Vec::new();
        let mut has_config = false;
        for entry in entries.flatten() {
            let name = entry.file_name().to_string_lossy().into_owned();
            let full = format!("{dir}/{name}");
            let is_dir = fs::metadata(&full).map(|m| m.is_dir()).unwrap_or(false);
            if is_dir {
                let link = entry.file_type().map(|t| t.is_symlink()).unwrap_or(false);
                if !link && !PRUNED.contains(&name.as_str()) && !name.starts_with("bazel-") {
                    folders.push(name);
                }
            } else if name == CONFIG {
                has_config = true;
            }
        }
        if has_config {
            found.push(if rel.is_empty() {
                CONFIG.to_string()
            } else {
                format!("{rel}/{CONFIG}")
            });
        }
        folders.sort();
        for name in folders {
            let next_rel = if rel.is_empty() {
                name.clone()
            } else {
                format!("{rel}/{name}")
            };
            walk(&format!("{dir}/{name}"), &next_rel, found);
        }
    }
    let mut found = Vec::new();
    if fs::metadata(root).map(|m| m.is_dir()).unwrap_or(false) {
        walk(root, "", &mut found);
    }
    found.sort();
    found
}

fn line_starts(text: &[char]) -> impl Iterator<Item = usize> + '_ {
    (0..text.len()).filter(move |&i| i == 0 || text[i - 1] == '\n')
}

fn starts_at(text: &[char], at: usize, word: &str) -> bool {
    let mut i = at;
    for c in word.chars() {
        if text.get(i) != Some(&c) {
            return false;
        }
        i += 1;
    }
    true
}

/// `re.findall(r"^<open>\n(.*?)^<close>", text, re.M | re.S)` where open and
/// close are literal: the text between each opening line and the first
/// closing line after it.
fn blocks(text: &[char], open: &str, close: &str, first_only: bool) -> Vec<String> {
    let open_nl = format!("{open}\n");
    let mut found = Vec::new();
    let mut from = 0;
    loop {
        let start = line_starts(text).filter(|&i| i >= from).find(|&i| {
            starts_at(text, i, &open_nl)
                && (i + open_nl.chars().count()..=text.len())
                    .any(|j| (j == 0 || text[j - 1] == '\n') && starts_at(text, j, close))
        });
        let Some(start) = start else {
            return found;
        };
        let body = start + open_nl.chars().count();
        let end = (body..=text.len())
            .find(|&j| (j == 0 || text[j - 1] == '\n') && starts_at(text, j, close))
            .unwrap();
        found.push(text[body..end].iter().collect());
        if first_only {
            return found;
        }
        from = end + close.chars().count();
    }
}

/// `[(subtree, owner, repo)]` from the text of copy.bara.sky, longest
/// subtree first.
pub fn mirrors_from(text: &str) -> Result<Vec<(String, String, String)>, String> {
    let kept: Vec<&str> = text
        .split('\n')
        .filter(|l| !py::lstrip(l).starts_with('#'))
        .collect();
    let text: Vec<char> = kept.join("\n").chars().collect();
    let prefix = "STANDALONE_SSH_PREFIX = \"git@github.com:";
    let owner = line_starts(&text).find_map(|i| {
        if !starts_at(&text, i, prefix) {
            return None;
        }
        let from = i + prefix.chars().count();
        let mut j = from;
        while j < text.len() && text[j] != '/' && text[j] != '"' {
            j += 1;
        }
        (j > from && starts_at(&text, j, "/\"")).then(|| text[from..j].iter().collect::<String>())
    });
    let block = blocks(&text, "COMPONENTS = [", "]", true);
    let (Some(owner), Some(block)) = (owner, block.first()) else {
        return Err(format!(
            "{COPYBARA} has no STANDALONE_SSH_PREFIX or no COMPONENTS list"
        ));
    };
    let block: Vec<char> = block.chars().collect();
    let mut found = Vec::new();
    for component in blocks(&block, "    {", "    }", false) {
        let component: Vec<char> = component.chars().collect();
        let mut keys: BTreeMap<&str, String> = BTreeMap::new();
        for i in line_starts(&component) {
            for key in ["name", "repo", "subtree"] {
                let lead = format!("        \"{key}\": \"");
                if !starts_at(&component, i, &lead) {
                    continue;
                }
                let from = i + lead.chars().count();
                let mut j = from;
                while j < component.len() && component[j] != '"' {
                    j += 1;
                }
                if j < component.len() {
                    keys.insert(key, component[from..j].iter().collect());
                }
            }
        }
        let Some(name) = keys.get("name").cloned() else {
            return Err(format!("{COPYBARA} has a component with no name"));
        };
        let subtree = keys.get("subtree").cloned().unwrap_or_else(|| name.clone());
        let repo = keys.get("repo").cloned().unwrap_or(name);
        found.push((subtree, owner.clone(), repo));
    }
    if found.is_empty() {
        return Err(format!("{COPYBARA} has an empty COMPONENTS list"));
    }
    found.sort_by_key(|m| std::cmp::Reverse(m.0.chars().count()));
    Ok(found)
}

pub fn mirrors(root: &str) -> Result<Vec<(String, String, String)>, String> {
    let text = read(root, COPYBARA).map_err(|e| e.to_string())?;
    mirrors_from(&text)
}

fn wb_before(line: &[char], i: usize) -> bool {
    i == 0 || !py::is_word(line[i - 1])
}

fn wb_after(line: &[char], j: usize) -> bool {
    j >= line.len() || !py::is_word(line[j])
}

fn skip_space(line: &[char], mut i: usize) -> usize {
    while i < line.len() && py::is_space(line[i]) {
        i += 1;
    }
    i
}

/// `\b<first>\s+<second>\b` somewhere in the line.
fn two_words(line: &[char], first: &str, second: &str) -> bool {
    let n = first.chars().count();
    (0..line.len()).any(|i| {
        if !starts_at(line, i, first) || !wb_before(line, i) {
            return false;
        }
        let j = skip_space(line, i + n);
        j > i + n && starts_at(line, j, second) && wb_after(line, j + second.chars().count())
    })
}

/// `\bnpm(?:\s+|["']\s*,\s*["'])publish\b`: `npm publish`, or how a
/// script spells it, `"npm", "publish"`.
fn npm_publishes(line: &[char]) -> bool {
    if two_words(line, "npm", "publish") {
        return true;
    }
    let quote = |c: Option<&char>| matches!(c, Some('"' | '\''));
    (0..line.len()).any(|i| {
        if !starts_at(line, i, "npm") || !wb_before(line, i) || !quote(line.get(i + 3)) {
            return false;
        }
        let j = skip_space(line, i + 4);
        if line.get(j) != Some(&',') {
            return false;
        }
        let k = skip_space(line, j + 1);
        quote(line.get(k)) && starts_at(line, k + 1, "publish") && wb_after(line, k + 8)
    })
}

/// What a job runs to publish to a registry.
pub fn publishes(registry: &str, line: &str) -> bool {
    let chars: Vec<char> = line.chars().collect();
    match registry {
        "npm" => npm_publishes(&chars),
        "pypi" => {
            two_words(&chars, "uv", "publish")
                || two_words(&chars, "twine", "upload")
                || line.contains("gh-action-pypi-publish@")
        }
        "crates" => two_words(&chars, "cargo", "publish"),
        _ => false,
    }
}

/// `^( +)([A-Za-z0-9_-]+):\s*$`: (indent, key).
fn job_key(line: &str) -> Option<(usize, &str)> {
    let spaces = line.len() - line.trim_start_matches(' ').len();
    if spaces == 0 {
        return None;
    }
    let rest = &line[spaces..];
    let end = rest
        .find(|c: char| !(c.is_ascii_alphanumeric() || c == '_' || c == '-'))
        .unwrap_or(rest.len());
    if end == 0 {
        return None;
    }
    let after = rest[end..].strip_prefix(':')?;
    after
        .chars()
        .all(py::is_space)
        .then_some((spaces, &rest[..end]))
}

/// `[(job, environment)]` of the jobs in one workflow that publish.
pub fn publishing_jobs(text: &str, registry: &str) -> Vec<(String, String)> {
    let lines = text.split('\n').filter(|l| !py::lstrip(l).starts_with('#'));
    let mut jobs: Vec<(String, Vec<&str>)> = Vec::new();
    let mut inside = false;
    let mut indent: Option<usize> = None;
    for line in lines {
        if let Some(rest) = line.strip_prefix("jobs:") {
            if rest.chars().all(py::is_space) {
                inside = true;
                continue;
            }
        }
        if !inside || py::strip(line).is_empty() {
            continue;
        }
        if !line.starts_with(' ') {
            break;
        }
        let key = job_key(line);
        if indent.is_none() {
            if let Some((spaces, _)) = key {
                indent = Some(spaces);
            }
        }
        match key {
            Some((spaces, name)) if Some(spaces) == indent => {
                jobs.push((name.to_string(), Vec::new()))
            }
            _ => {
                if let Some(last) = jobs.last_mut() {
                    last.1.push(line);
                }
            }
        }
    }
    jobs.into_iter()
        .filter(|(_, body)| body.iter().any(|l| publishes(registry, l)))
        .map(|(name, body)| (name, environment(&body)))
        .collect()
}

/// A job's `environment:`, written as a name or as a mapping with one.
fn environment(body: &[&str]) -> String {
    let depth = body.iter().map(|l| py::indent_of(l)).min().unwrap_or(0);
    for (index, line) in body.iter().enumerate() {
        let spaces = line.len() - line.trim_start_matches(' ').len();
        let Some(rest) = line[spaces..].strip_prefix("environment:") else {
            continue;
        };
        if spaces != depth {
            continue;
        }
        let value = py::strip(rest);
        if !value.is_empty() {
            return py::strip_quotes(value).to_string();
        }
        for inner in &body[index + 1..] {
            if py::indent_of(inner) <= depth {
                break;
            }
            let trimmed = py::lstrip(inner);
            if trimmed.len() == inner.len() {
                continue;
            }
            if let Some(name) = trimmed.strip_prefix("name:") {
                return py::strip_quotes(py::strip(name)).to_string();
            }
        }
    }
    String::new()
}

enum Describe {
    Os,
    Value(String),
    Crash(Crash),
}

impl From<Crash> for Describe {
    fn from(crash: Crash) -> Describe {
        Describe::Crash(crash)
    }
}

type Described = (
    &'static str,
    Option<Value>,
    Option<Value>,
    Option<&'static str>,
);

fn empty() -> Value {
    Value::Dict(json::Dict::new())
}

/// (registry, name, version, why it is not published or None).
fn describe(root: &str, path: &str) -> Result<Described, Describe> {
    let (registry, _) = file_kind(py::basename(path)).unwrap();
    let text = match read(root, path) {
        Ok(text) => text,
        Err(ReadError::Os(..)) => return Err(Describe::Os),
        Err(ReadError::Decode(m)) => return Err(Describe::Value(m)),
    };
    if registry == "npm" {
        let data = json::loads(&text).map_err(|e| Describe::Value(e.0))?;
        let why = data
            .pget("private")?
            .is_some_and(Value::truthy)
            .then_some("\"private\": true");
        return Ok((
            registry,
            data.pget("name")?.cloned(),
            data.pget("version")?.cloned(),
            why,
        ));
    }
    let data = toml::loads(&text).map_err(|e| Describe::Value(e.0))?;
    if registry == "crates" {
        let package = get_or(&data, "package", empty())?;
        let publish = get_or(&package, "publish", Value::Bool(true))?;
        let off = publish == Value::Bool(false) || publish == Value::List(Vec::new());
        let why = off.then_some("publish = false");
        return Ok((
            registry,
            package.pget("name")?.cloned(),
            package.pget("version")?.cloned(),
            why,
        ));
    }
    let project = get_or(&data, "project", empty())?;
    let mut private = false;
    for classifier in get_or(&project, "classifiers", Value::List(Vec::new()))?.iterate()? {
        if classifier.str_for("startswith")?.starts_with("Private ::") {
            private = true;
            break;
        }
    }
    let why = private.then_some("a Private :: classifier");
    Ok((
        registry,
        project.pget("name")?.cloned(),
        project.pget("version")?.cloned(),
        why,
    ))
}

/// `[(release-please path, version file)]` one config names.
pub fn version_files(config_path: &str, config: &Value) -> Result<Vec<(String, String)>, Crash> {
    let mut found = Vec::new();
    let packages = get_or(config, "packages", empty())?;
    for (path, package) in packages.items()? {
        let base = if path == "." {
            py::dirname(config_path)
        } else {
            path.clone()
        };
        let kind = get_or(
            package,
            "release-type",
            config.pget("release-type")?.cloned().unwrap_or(Value::Null),
        )?;
        if matches!(kind, Value::List(_) | Value::Dict(_)) {
            return Err(Crash::new(
                "TypeError",
                format!("unhashable type: '{}'", kind.type_name()),
            ));
        }
        if let Some(file) = kind.as_str().and_then(implied) {
            found.push((base.clone(), py::normpath(&py::join(&base, file))));
        }
        let extras = get_or(
            package,
            "extra-files",
            get_or(config, "extra-files", Value::List(Vec::new()))?,
        )?;
        for extra in extras.iterate()? {
            if !matches!(extra, Value::Dict(_)) {
                continue;
            }
            let Value::Str(path) = get_or(&extra, "path", json::s(""))? else {
                let other = get_or(&extra, "path", json::s(""))?;
                return Err(Crash::new(
                    "TypeError",
                    format!(
                        "expected str, bytes or os.PathLike object, not {}",
                        other.type_name()
                    ),
                ));
            };
            let Some((_, jsonpath)) = file_kind(py::basename(&path)) else {
                continue;
            };
            if extra.pget("jsonpath")? == Some(&json::s(jsonpath)) {
                found.push((base.clone(), py::normpath(&py::join(&base, &path))));
            }
        }
    }
    Ok(found)
}

pub fn load(root: &str) -> Result<Inventory, Crash> {
    let mut inventory = Inventory::default();
    let components = match mirrors(root) {
        Ok(components) => components,
        Err(error) => {
            inventory.problems.push(error);
            return Ok(inventory);
        }
    };
    let mut workflows: BTreeMap<String, Vec<(String, String)>> = BTreeMap::new();
    let mut seen: HashSet<String> = HashSet::new();
    for config_path in configs(root) {
        let config = match read(root, &config_path) {
            Ok(text) => json::loads(&text).map_err(|e| e.0),
            Err(ReadError::Decode(m)) => Err(m),
            Err(os @ ReadError::Os(..)) => return Err(Crash(os.crash_line())),
        };
        let config = match config {
            Ok(config) => config,
            Err(error) => {
                inventory
                    .problems
                    .push(format!("{config_path} is not JSON: {error}"));
                continue;
            }
        };
        for (path, file) in version_files(&config_path, &config)? {
            if !seen.insert(file.clone()) {
                continue;
            }
            let (registry, name, version, why) = match describe(root, &file) {
                Ok(found) => found,
                Err(Describe::Os) => {
                    inventory
                        .problems
                        .push(format!("{config_path} releases {file}, which is not there"));
                    continue;
                }
                Err(Describe::Value(error)) => {
                    inventory
                        .problems
                        .push(format!("{file} cannot be read: {error}"));
                    continue;
                }
                Err(Describe::Crash(crash)) => return Err(crash),
            };
            if let Some(why) = why {
                inventory
                    .skipped
                    .push((file, format!("not published: {why}")));
                continue;
            }
            let truthy = |v: &Option<Value>| v.as_ref().is_some_and(Value::truthy);
            if !truthy(&name) || !truthy(&version) {
                inventory
                    .problems
                    .push(format!("{file} has no name or no version"));
                continue;
            }
            let (name_value, version_value) = (name.unwrap(), version.unwrap());
            let (name, version) = (name_value.py_str(), version_value.py_str());
            let Some((subtree, owner, repo)) = components
                .iter()
                .find(|m| file.starts_with(&format!("{}/", m.0)))
                .cloned()
            else {
                inventory
                    .skipped
                    .push((file, format!("no mirror in {COPYBARA} carries it")));
                continue;
            };
            if !workflows.contains_key(&subtree) {
                let texts = workflows_of(root, &subtree)?;
                workflows.insert(subtree.clone(), texts);
            }
            let jobs: Vec<(String, String, String)> = workflows[&subtree]
                .iter()
                .flat_map(|(workflow, text)| {
                    publishing_jobs(text, registry)
                        .into_iter()
                        .map(move |(job, env)| (workflow.clone(), job, env))
                })
                .collect();
            if jobs.is_empty() {
                inventory.skipped.push((
                    file,
                    format!("no job in {owner}/{repo}'s workflows publishes to {registry}"),
                ));
                continue;
            }
            if jobs.len() > 1 {
                let place: Vec<String> =
                    jobs.iter().map(|(w, j, _)| format!("{w} ({j})")).collect();
                inventory.problems.push(format!(
                    "{name} ({file}): more than one job publishes to {registry}: {}. A registry trusts one workflow; which one is it?",
                    place.join(", ")
                ));
                continue;
            }
            let (workflow, job, environment) = jobs.into_iter().next().unwrap();
            inventory.packages.push(Package {
                registry: registry.to_string(),
                name,
                version,
                file,
                path,
                config: config_path.clone(),
                owner,
                repo,
                workflow,
                job,
                environment,
                name_value,
                version_value,
            });
        }
    }
    inventory.packages.sort_by(|a, b| {
        let index = |p: &Package| REGISTRIES.iter().position(|r| *r == p.registry);
        (index(a), &a.name).cmp(&(index(b), &b.name))
    });
    inventory.skipped.sort();
    Ok(inventory)
}

/// `{file name: text}` of a subtree's .github/workflows, in name order.
fn workflows_of(root: &str, subtree: &str) -> Result<Vec<(String, String)>, Crash> {
    let folder = py::join(root, &format!("{subtree}/.github/workflows"));
    let mut names: Vec<String> = match fs::read_dir(folder) {
        Ok(entries) => entries
            .flatten()
            .map(|e| e.file_name().to_string_lossy().into_owned())
            .collect(),
        Err(_) => Vec::new(),
    };
    names.sort();
    let mut found = Vec::new();
    for name in names
        .into_iter()
        .filter(|n| n.ends_with(".yml") || n.ends_with(".yaml"))
    {
        let text = read(root, &format!("{subtree}/.github/workflows/{name}"))
            .map_err(|e| Crash(e.crash_line()))?;
        found.push((name, text));
    }
    Ok(found)
}

/// `inventory.root_folder()`.
pub fn root_folder(env: &[(String, String)]) -> String {
    match env.iter().find(|(k, _)| k == "BUILD_WORKSPACE_DIRECTORY") {
        Some((_, v)) if !v.is_empty() => v.clone(),
        _ => std::env::current_dir()
            .map(|p| p.to_string_lossy().into_owned())
            .unwrap_or_else(|_| ".".into()),
    }
}

/// `inventory.main`: the inventory, as words, or `--json`.
pub fn main(argv: &[String], root: &str, out: &mut dyn Write, err: &mut dyn Write) -> i32 {
    let found = match load(root) {
        Ok(found) => found,
        Err(crash) => {
            let _ = write!(err, "{}", crash.traceback());
            return 1;
        }
    };
    for problem in &found.problems {
        let _ = writeln!(err, "registry-trust: {problem}");
    }
    if !found.problems.is_empty() {
        return 2;
    }
    if argv.iter().any(|a| a == "--json") {
        let list = Value::List(found.packages.iter().map(Package::as_value).collect());
        let _ = writeln!(out, "{}", json::dumps_indented(&list, 2));
        return 0;
    }
    for registry in REGISTRIES {
        let mine: Vec<&Package> = found
            .packages
            .iter()
            .filter(|p| p.registry == registry)
            .collect();
        let _ = writeln!(out, "{registry}: {} package(s)", mine.len());
        for p in mine {
            let environment = if p.environment.is_empty() {
                String::new()
            } else {
                format!(" environment {}", p.environment)
            };
            let _ = writeln!(
                out,
                "  {} {}  <- {}\n      published by {} {} (job {}){environment}",
                p.name,
                p.version,
                p.file,
                p.repository(),
                p.workflow,
                p.job
            );
        }
    }
    if argv.iter().any(|a| a == "--all") {
        let _ = writeln!(out, "left out: {} released file(s)", found.skipped.len());
        for (file, why) in &found.skipped {
            let _ = writeln!(out, "  {file}: {why}");
        }
    }
    0
}

#[cfg(test)]
pub mod tests {
    use super::*;

    const REAL_COPYBARA: &str = include_str!("../../copybara/copy.bara.sky");

    #[test]
    fn every_component_of_the_real_copybara_file_is_read() {
        let declared = REAL_COPYBARA
            .lines()
            .filter(|l| l.trim().starts_with("\"standalone_rev_id\":"))
            .count();
        let found = mirrors_from(REAL_COPYBARA).unwrap();
        assert!(declared > 10);
        assert_eq!(found.len(), declared);
        let has = |s: &str, o: &str, r: &str| found.contains(&(s.into(), o.into(), r.into()));
        assert!(has(
            "packages/vitruvian-sdk",
            "VitruvianSoftware",
            "vitruvian-sdk"
        ));
        assert!(has(
            "packages/pulumi/library",
            "VitruvianSoftware",
            "pulumi-library"
        ));
        assert!(has(
            "apps/desktop/nexus-agent",
            "VitruvianSoftware",
            "nexus-agent"
        ));
        let lengths: Vec<usize> = found.iter().map(|m| m.0.len()).collect();
        assert!(
            lengths.windows(2).all(|w| w[0] >= w[1]),
            "longest subtree first"
        );
    }

    #[test]
    fn a_copybara_file_with_no_components_is_an_error() {
        let error = mirrors_from("STANDALONE_SSH_PREFIX = \"git@github.com:X/\"\n").unwrap_err();
        assert!(error.contains("no COMPONENTS list"), "{error}");
        let error =
            mirrors_from("STANDALONE_SSH_PREFIX = \"git@github.com:X/\"\nCOMPONENTS = [\n]\n")
                .unwrap_err();
        assert!(error.contains("empty COMPONENTS list"), "{error}");
        let error = mirrors_from("STANDALONE_SSH_PREFIX = \"git@github.com:X/\"\nCOMPONENTS = [\n    {\n        \"repo\": \"r\",\n    },\n]\n").unwrap_err();
        assert!(error.contains("component with no name"), "{error}");
    }

    #[test]
    fn a_publish_command_is_found_however_a_script_spells_it() {
        assert!(publishes("npm", "        run: npm publish --access public"));
        assert!(publishes("npm", "subprocess.run([\"npm\", \"publish\"])"));
        assert!(publishes("npm", "subprocess.run(['npm' , 'publish'])"));
        assert!(!publishes("npm", "pnpm publish"));
        assert!(!publishes("npm", "npm publisher"));
        assert!(!publishes("npm", "npm run publish"));
        assert!(publishes(
            "pypi",
            "run: uv publish --trusted-publishing always"
        ));
        assert!(publishes("pypi", "twine upload dist/*"));
        assert!(publishes(
            "pypi",
            "uses: pypa/gh-action-pypi-publish@release/v1"
        ));
        assert!(publishes("crates", "run: cargo  publish"));
        assert!(!publishes("crates", "run: cargo publish_all"));
    }

    #[test]
    fn the_environment_is_the_job_s_own_not_a_step_s() {
        let workflow = "jobs:\n  a:\n    steps:\n      - env:\n          environment: no\n        run: cargo publish\n    environment: crates-io\n  b:\n    environment:\n      name: \"pypi\"\n      url: x\n    steps:\n      - run: uv publish\n  c:\n    steps:\n      - run: npm publish\n";
        assert_eq!(
            publishing_jobs(workflow, "crates"),
            [("a".to_string(), "crates-io".to_string())]
        );
        assert_eq!(
            publishing_jobs(workflow, "pypi"),
            [("b".to_string(), "pypi".to_string())]
        );
        assert_eq!(
            publishing_jobs(workflow, "npm"),
            [("c".to_string(), String::new())]
        );
    }

    #[test]
    fn a_dependency_s_version_is_a_sample_not_a_package() {
        let config = json::loads(
            r#"{"release-type": "simple", "packages": {"p": {"extra-files": [
                "x.swift",
                {"path": "ts/package.json", "jsonpath": "$.version"},
                {"path": "s/package.json", "jsonpath": "$.dependencies['k']"},
                {"path": "rs/Cargo.toml", "jsonpath": "$.package.version"}
            ]}, ".": {"release-type": "node"}}}"#,
        )
        .unwrap();
        assert_eq!(
            version_files("a/release-please-config.json", &config).unwrap(),
            [
                ("p".to_string(), "p/ts/package.json".to_string()),
                ("p".to_string(), "p/rs/Cargo.toml".to_string()),
                ("a".to_string(), "a/package.json".to_string()),
            ]
        );
    }
}
