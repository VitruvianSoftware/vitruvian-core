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

//! catalog_rules.py: the rules of the tool catalog that JSON Schema cannot
//! say, and the checks the catalog's pull requests share: whether a zip is
//! safe to unpack, and whether a tool's manifest says what its entry copies.

use crate::json::{self, Value};
use crate::py;
use crate::pyerr::{os_stop, Res, Stop};
use crate::pystr::repr_str;
use crate::timefmt::{self, Stamp};
use crate::zip::ZipFile;
use std::cmp::Ordering;
use std::path::Path;

/// The most a tool's folder may hold, as the app counts it.
pub const FOLDER_BYTES: u64 = 256 * 1_048_576;
pub const FOLDER_ITEMS: usize = 10_000;

/// Where a download may come from.
pub const DOWNLOAD_PREFIXES: &[&str] = &["https://github.com/VitruvianSoftware/"];

const SEMVER: &str = r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?$";

/// `catalog_rules.load(path)`: the file's bytes and its data.
pub fn load(path: &Path) -> Res<(Vec<u8>, Value)> {
    let data = std::fs::read(path).map_err(|e| os_stop(&e, path))?;
    let value = json::loads_bytes(&data)?;
    Ok((data, value))
}

/// A version as semver sorts it: a pre-release before its release, its
/// identifiers compared as text.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SemVer {
    core: [String; 3],
    release: bool,
    pre: String,
}

fn num_cmp(a: &str, b: &str) -> Ordering {
    a.len().cmp(&b.len()).then_with(|| a.cmp(b))
}

impl Ord for SemVer {
    fn cmp(&self, other: &Self) -> Ordering {
        for i in 0..3 {
            let c = num_cmp(&self.core[i], &other.core[i]);
            if c != Ordering::Equal {
                return c;
            }
        }
        self.release
            .cmp(&other.release)
            .then_with(|| self.pre.cmp(&other.pre))
    }
}

impl PartialOrd for SemVer {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

impl SemVer {
    pub fn is_prerelease(&self) -> bool {
        !self.release
    }

    /// The tuple Python makes, written as Python prints it.
    pub fn repr(&self) -> String {
        format!(
            "({}, {}, {}, {}, {})",
            self.core[0],
            self.core[1],
            self.core[2],
            if self.release { 1 } else { 0 },
            repr_str(&self.pre)
        )
    }
}

/// `semver(text)` for a str.
pub fn semver_str(text: &str) -> Option<SemVer> {
    let m = crate::pyre::fixed(SEMVER).match_start(text)?;
    let pre = m.group(4);
    Some(SemVer {
        core: [m.group(1)?, m.group(2)?, m.group(3)?],
        release: pre.is_none(),
        pre: pre.map(|p| p[1..].to_string()).unwrap_or_default(),
    })
}

/// `semver(value)`: `text or ""` first, so None and "" are no version; a
/// truthy non-str is the TypeError `re.match` raises.
pub fn semver(v: &Value) -> Res<Option<SemVer>> {
    match v {
        Value::Str(s) => Ok(semver_str(s)),
        other if !other.truthy() => Ok(None),
        other => Err(Stop::crash(
            "TypeError",
            format!(
                "expected string or bytes-like object, got '{}'",
                other.type_name()
            ),
        )),
    }
}

/// `generated(catalog)`: when the list was written, or None.
pub fn generated(catalog: &Value) -> Option<Stamp> {
    match catalog.get("generated").ok().flatten() {
        Some(Value::Str(s)) => timefmt::parse(s),
        _ => None,
    }
}

/// The parts of `urllib.parse.urlsplit(url)` the rules read.
pub struct Split {
    pub scheme: String,
    pub netloc: String,
    pub path: String,
    pub query: String,
    pub fragment: String,
}

fn valid_ipv6(host: &str) -> bool {
    let host = host.split('%').next().unwrap_or("");
    if host.is_empty() {
        return false;
    }
    let (head, tail) = match host.find("::") {
        Some(i) => (&host[..i], Some(&host[i + 2..])),
        None => (host, None),
    };
    if tail.map_or(false, |t| t.contains("::")) {
        return false;
    }
    let groups = |s: &str| -> Option<usize> {
        if s.is_empty() {
            return Some(0);
        }
        let parts: Vec<&str> = s.split(':').collect();
        let mut n = 0;
        for (i, p) in parts.iter().enumerate() {
            if i == parts.len() - 1 && p.contains('.') {
                let v4: Vec<&str> = p.split('.').collect();
                if v4.len() != 4
                    || !v4
                        .iter()
                        .all(|o| !o.is_empty() && o.len() <= 3 && o.parse::<u8>().is_ok())
                {
                    return None;
                }
                n += 2;
            } else if p.is_empty() || p.len() > 4 || !p.chars().all(|c| c.is_ascii_hexdigit()) {
                return None;
            } else {
                n += 1;
            }
        }
        Some(n)
    };
    match (groups(head), tail.map(groups)) {
        (Some(h), None) => h == 8,
        (Some(h), Some(Some(t))) => h + t <= 7,
        _ => false,
    }
}

fn check_bracketed_netloc(netloc: &str) -> Res<()> {
    let invalid = || Stop::crash("ValueError", "Invalid IPv6 URL");
    let host_port = netloc.rsplit_once('@').map_or(netloc, |(_, h)| h);
    if let Some((before, bracketed)) = host_port.split_once('[') {
        if !before.is_empty() {
            return Err(invalid());
        }
        let (host, port) = bracketed.split_once(']').unwrap_or((bracketed, ""));
        if !port.is_empty() && !port.starts_with(':') {
            return Err(invalid());
        }
        if let Some(rest) = host.strip_prefix('v') {
            let ok = match rest.split_once('.') {
                Some((hex, after)) => {
                    !hex.is_empty()
                        && hex.chars().all(|c| c.is_ascii_hexdigit())
                        && !after.is_empty()
                }
                None => false,
            };
            if !ok {
                return Err(Stop::crash("ValueError", "IPvFuture address is invalid"));
            }
        } else if !valid_ipv6(host) {
            let v4 =
                host.split('.').count() == 4 && host.split('.').all(|o| o.parse::<u8>().is_ok());
            return Err(Stop::crash(
                "ValueError",
                if v4 {
                    "An IPv4 address cannot be in brackets".to_string()
                } else {
                    format!(
                        "{} does not appear to be an IPv4 or IPv6 address",
                        repr_str(host)
                    )
                },
            ));
        }
    }
    Ok(())
}

/// `urllib.parse.urlsplit(url)`, as Python 3.12 splits it.
pub fn urlsplit(url: &str) -> Res<Split> {
    let mut url: String = url
        .trim_start_matches(|c: char| (c as u32) <= 0x20)
        .chars()
        .filter(|c| !matches!(c, '\t' | '\r' | '\n'))
        .collect();
    let mut out = Split {
        scheme: String::new(),
        netloc: String::new(),
        path: String::new(),
        query: String::new(),
        fragment: String::new(),
    };
    if let Some(i) = url.find(':') {
        let first = url.chars().next().unwrap();
        if i > 0
            && first.is_ascii_alphabetic()
            && url[..i]
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || matches!(c, '+' | '-' | '.'))
        {
            out.scheme = url[..i].to_lowercase();
            url = url[i + 1..].to_string();
        }
    }
    if url.starts_with("//") {
        let delim = ['/', '?', '#']
            .iter()
            .filter_map(|c| url[2..].find(*c).map(|p| p + 2))
            .min()
            .unwrap_or(url.len());
        out.netloc = url[2..delim].to_string();
        url = url[delim..].to_string();
        let open = out.netloc.contains('[');
        let close = out.netloc.contains(']');
        if open != close {
            return Err(Stop::crash("ValueError", "Invalid IPv6 URL"));
        }
        if open && close {
            check_bracketed_netloc(&out.netloc)?;
        }
    }
    if let Some((u, f)) = url.split_once('#') {
        out.fragment = f.to_string();
        url = u.to_string();
    }
    if let Some((u, q)) = url.split_once('?') {
        out.query = q.to_string();
        url = u.to_string();
    }
    out.path = url;
    Ok(out)
}

/// `url_problems(where, url)`.
pub fn url_problems(place: &str, url: &Value) -> Res<Vec<String>> {
    let text = match url {
        Value::Str(s) => s.clone(),
        other if !other.truthy() => String::new(),
        other => {
            return Err(Stop::crash(
                "AttributeError",
                format!("'{}' object has no attribute 'decode'", other.type_name()),
            ))
        }
    };
    let shown = url.py_str();
    let mut problems = Vec::new();
    let parts = urlsplit(&text)?;
    if !DOWNLOAD_PREFIXES.iter().any(|p| text.starts_with(p)) {
        problems.push(format!(
            "{}: the download is not from a listed place ({})",
            place, shown
        ));
    }
    if !parts.query.is_empty()
        || !parts.fragment.is_empty()
        || text.contains('%')
        || text.contains('\\')
    {
        problems.push(format!(
            "{}: the download address has a query, a fragment or an escape ({})",
            place, shown
        ));
    }
    if parts.path.split('/').any(|s| s == "." || s == "..") {
        problems.push(format!(
            "{}: the download address walks up or stands still ({})",
            place, shown
        ));
    }
    Ok(problems)
}

/// `problems(catalog)`: what is wrong with a catalog that passed its schema.
pub fn problems(catalog: &Value) -> Res<Vec<String>> {
    let mut found = Vec::new();
    if generated(catalog).is_none() {
        found.push("generated is not a time in UTC, written 2026-11-02T10:00:00Z".to_string());
    }
    let mut seen: Vec<Value> = Vec::new();
    let tools = py::get_or(catalog, "tools", Value::List(vec![]))?;
    for (index, tool) in py::iterate(&tools)?.iter().enumerate() {
        let id = py::get_null(tool, "id")?;
        let place = format!("tools[{}] ({})", index, id.py_str());
        py::hashable(&id)?;
        if seen.iter().any(|s| py::eq(s, &id)) {
            found.push(format!("{}: the id is listed twice", place));
        }
        seen.push(id.clone());
        for field in ["version", "minimumAppVersion"] {
            if semver(&py::get_null(tool, field)?)?.is_none() {
                found.push(format!("{}: {} is not a version like 1.2.0", place, field));
            }
        }
        let download = py::get_or(tool, "download", Value::Dict(json::Dict::new()))?;
        found.extend(url_problems(&place, &py::get_null(&download, "url")?)?);
        let mut commands = Vec::new();
        for command in py::iterate(&py::get_or(tool, "commands", Value::List(vec![]))?)? {
            commands.push(py::get_null(&command, "id")?);
        }
        if commands.len() != py::set_len(&commands)? {
            found.push(format!("{}: two commands share an id", place));
        }
    }
    Ok(found)
}

/// `changed(base, head)`: the entries of `head` that are new, or differ from
/// the same id in `base`.
pub fn changed(base: &Value, head: &Value) -> Res<Vec<Value>> {
    let mut before: Vec<(Value, Value)> = Vec::new();
    for tool in py::iterate(&py::get_or(base, "tools", Value::List(vec![]))?)? {
        let id = py::index(&tool, "id")?.clone();
        py::hashable(&id)?;
        match before.iter_mut().find(|(k, _)| py::eq(k, &id)) {
            Some(slot) => slot.1 = tool,
            None => before.push((id, tool)),
        }
    }
    let mut out = Vec::new();
    for tool in py::iterate(&py::get_or(head, "tools", Value::List(vec![]))?)? {
        let id = py::index(&tool, "id")?.clone();
        py::hashable(&id)?;
        let same = before
            .iter()
            .find(|(k, _)| py::eq(k, &id))
            .map_or(false, |(_, t)| py::eq(t, &tool));
        if !same {
            out.push(tool);
        }
    }
    Ok(out)
}

/// `name_problem(name)`: why an entry's name would leave its folder.
pub fn name_problem(name: &str) -> Option<&'static str> {
    if name.is_empty() || name.contains('\0') || name.contains('\\') {
        return Some("an empty name, a NUL or a backslash");
    }
    if name.starts_with('/') || name.starts_with('~') {
        return Some("an absolute path");
    }
    if name
        .trim_end_matches('/')
        .split('/')
        .any(|p| p.is_empty() || p == "." || p == "..")
    {
        return Some("a part that is empty, . or ..");
    }
    None
}

/// `zipfile.ZipFile(path)`, or Ok(None) where Python raises BadZipFile or
/// OSError (which zip_problems reads as "not a zip").
pub fn open_zip(path: &Path) -> Res<Option<ZipFile>> {
    let data = match std::fs::read(path) {
        Ok(d) => d,
        Err(_) => return Ok(None),
    };
    match ZipFile::new(data) {
        Ok(z) => Ok(Some(z)),
        Err(m) if m.starts_with("UnicodeDecodeError") => Err(Stop::from_text(&m)),
        Err(_) => Ok(None),
    }
}

fn is_link(mode: u32) -> bool {
    mode & 0o170000 == 0o120000
}

/// `zip_problems(path)`: what makes the zip unsafe or too large to unpack,
/// read from its central directory.
pub fn zip_problems(path: &Path) -> Res<Vec<String>> {
    let archive = match open_zip(path)? {
        Some(a) => a,
        None => return Ok(vec!["it is not a zip".to_string()]),
    };
    let mut found = Vec::new();
    let entries = archive.infolist();
    if entries.len() > FOLDER_ITEMS {
        found.push(format!(
            "it holds {} things, more than {}",
            entries.len(),
            FOLDER_ITEMS
        ));
    }
    let mut total: u64 = 0;
    for entry in entries {
        total += entry.file_size;
        if let Some(problem) = name_problem(&entry.filename) {
            found.push(format!("{} has {}", repr_str(&entry.filename), problem));
        }
        let mode = entry.external_attr >> 16;
        if entry.create_system == 3 && is_link(mode) {
            found.push(format!("{} is a link", repr_str(&entry.filename)));
        }
        if entry.flag_bits & 0x1 != 0 {
            found.push(format!("{} is encrypted", repr_str(&entry.filename)));
        }
    }
    if total > FOLDER_BYTES {
        found.push(format!(
            "it unpacks to {} bytes, more than {}",
            total, FOLDER_BYTES
        ));
    }
    if !archive
        .namelist()
        .iter()
        .any(|n| n == "vitruvian-tool.json")
    {
        found.push("it has no vitruvian-tool.json at its top".to_string());
    }
    Ok(found)
}

/// `unpack(path, folder)`: a zip zip_problems passed, each program keeping
/// its execute bit.
pub fn unpack(path: &Path, folder: &Path) -> Res<()> {
    let archive = match open_zip(path)? {
        Some(a) => a,
        None => return Err(Stop::crash("zipfile.BadZipFile", "File is not a zip file")),
    };
    for entry in archive.infolist() {
        let written = archive
            .extract(entry, folder)
            .map_err(|e| os_stop(&e, folder))?;
        let mode = entry.external_attr >> 16;
        if !entry.is_dir() && mode & 0o111 != 0 {
            set_mode(&written, 0o755).map_err(|e| os_stop(&e, &written))?;
        }
    }
    Ok(())
}

#[cfg(unix)]
pub fn set_mode(path: &Path, mode: u32) -> std::io::Result<()> {
    use std::os::unix::fs::PermissionsExt;
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(mode))
}

#[cfg(not(unix))]
pub fn set_mode(_path: &Path, _mode: u32) -> std::io::Result<()> {
    Ok(())
}

/// `[{"id": c.get("id"), "title": c.get("title")} for c in ...]` over a
/// manifest's `contributes.commands`.
pub fn manifest_commands(manifest: &Value) -> Res<Value> {
    let contributes = py::get_or(manifest, "contributes", Value::Dict(json::Dict::new()))?;
    let mut out = Vec::new();
    for c in py::iterate(&py::get_or(&contributes, "commands", Value::List(vec![]))?)? {
        out.push(py::obj(vec![
            ("id", py::get_null(&c, "id")?),
            ("title", py::get_null(&c, "title")?),
        ]));
    }
    Ok(Value::List(out))
}

/// `[p.get("placement") for p in manifest.get("contributes", {}).get("panels", [])]`.
pub fn manifest_panels(manifest: &Value) -> Res<Value> {
    let contributes = py::get_or(manifest, "contributes", Value::Dict(json::Dict::new()))?;
    let mut out = Vec::new();
    for p in py::iterate(&py::get_or(&contributes, "panels", Value::List(vec![]))?)? {
        out.push(py::get_null(&p, "placement")?);
    }
    Ok(Value::List(out))
}

/// `manifest_problems(entry, manifest)`: where the tool's own manifest and
/// the catalog's copy of it disagree.
pub fn manifest_problems(entry: &Value, manifest: &Value) -> Res<Vec<String>> {
    let sorted_list = |v: Value| -> Res<Value> { Ok(Value::List(py::sorted(&py::iterate(&v)?)?)) };
    let mut pairs: Vec<(&str, Value, Value)> = vec![
        (
            "id",
            py::get_null(manifest, "id")?,
            py::get_null(entry, "id")?,
        ),
        (
            "version",
            py::get_null(manifest, "version")?,
            py::get_null(entry, "version")?,
        ),
        (
            "protocol",
            py::get_null(manifest, "protocol")?,
            py::get_null(entry, "protocol")?,
        ),
        (
            "name",
            py::get_null(manifest, "name")?,
            py::get_null(entry, "name")?,
        ),
        (
            "publisher",
            py::get_null(manifest, "publisher")?,
            py::get_null(entry, "publisher")?,
        ),
        (
            "summary",
            py::get_null(manifest, "description")?,
            py::get_null(entry, "summary")?,
        ),
    ];
    let theirs_uses = sorted_list(py::get_or(manifest, "uses", Value::List(vec![]))?)?;
    let ours_uses = sorted_list(py::get_or(entry, "uses", Value::List(vec![]))?)?;
    pairs.push(("uses", theirs_uses, ours_uses));
    pairs.push((
        "commands",
        manifest_commands(manifest)?,
        py::get_or(entry, "commands", Value::List(vec![]))?,
    ));
    if py::contains(entry, &py::s("panels"))? {
        pairs.push((
            "panels",
            manifest_panels(manifest)?,
            py::get_null(entry, "panels")?,
        ));
    }
    let mut found = Vec::new();
    for (field, theirs, ours) in pairs {
        if !py::eq(&theirs, &ours) {
            found.push(format!(
                "{}: the manifest says {}, the catalog says {}",
                field,
                json::dumps_plain(&theirs),
                json::dumps_plain(&ours)
            ));
        }
    }
    Ok(found)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::json::loads;

    #[test]
    fn versions_sort_as_semver() {
        let order = [
            "0.9.0",
            "1.0.0-alpha",
            "1.0.0-beta",
            "1.0.0",
            "1.2.0",
            "1.10.0",
            "10.0.0",
        ];
        let parsed: Vec<SemVer> = order.iter().map(|v| semver_str(v).unwrap()).collect();
        let mut sorted = parsed.clone();
        sorted.sort();
        assert_eq!(sorted, parsed);
        assert!(semver_str("01.0.0").is_none());
        assert!(semver_str("1.0.0\n").is_some());
        assert!(semver(&Value::Null).unwrap().is_none());
        assert!(semver(&loads("3").unwrap()).is_err());
        assert_eq!(
            semver_str("1.2.3-rc.1").unwrap().repr(),
            "(1, 2, 3, 0, 'rc.1')"
        );
    }

    #[test]
    fn zip_names() {
        assert!(name_problem("bin/tool").is_none());
        assert!(name_problem("bin/").is_none());
        for name in ["", "/abs", "~/x", "a/../b", "./a", "a//b", "a\\b", "a\0b"] {
            assert!(name_problem(name).is_some(), "{:?}", name);
        }
    }

    #[test]
    fn urls() {
        let place = "tools[0] (x)";
        let ok = py::s("https://github.com/VitruvianSoftware/a/releases/download/v1/a.zip");
        assert!(url_problems(place, &ok).unwrap().is_empty());
        let bad = py::s("https://example.com/a/../b.zip?x#y");
        assert_eq!(url_problems(place, &bad).unwrap().len(), 3);
        assert_eq!(url_problems(place, &Value::Null).unwrap().len(), 1);
        assert!(urlsplit("https://[::1/x").is_err());
        assert!(urlsplit("https://[::1]:80/x").is_ok());
        assert!(urlsplit("https://[1.2.3.4]/x").is_err());
    }

    #[test]
    fn changed_entries() {
        let base = loads(r#"{"tools": [{"id": "a", "v": 1}, {"id": "b", "v": 1}]}"#).unwrap();
        let head = loads(r#"{"tools": [{"id": "a", "v": 1.0}, {"id": "b", "v": 2}, {"id": "c"}]}"#)
            .unwrap();
        let c = changed(&base, &head).unwrap();
        assert_eq!(c.len(), 2);
    }
}
