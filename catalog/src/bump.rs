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

//! bump.py: updates one tool's catalog entry from one of its releases, and
//! the helpers the catalog workflows run (`plan`, `foreign`, `older`,
//! `arm`, `automerge`). Exit status: 0 done or nothing to do, 1 refused,
//! 10 not ready, 11 not listed, 12 GitHub did not hand over a file.

use std::path::{Path, PathBuf};

use crate::argparse::{Kind, Opt, Parser};
use crate::crypto::sha256;
use crate::here::TempDir;
use crate::json::{self, Dict, Value};
use crate::pyerr::{self, Crash, Res};
use crate::pyre::{self, Regex};
use crate::rules::{self, SemVer};
use crate::zip::{ZipFile, ZipInfo};
use crate::{catalogue, macho, plist, py, pypath, schema, timefmt};

pub const OK: i32 = 0;
pub const REFUSED: i32 = 1;
pub const NOT_READY: i32 = 10;
pub const NOT_LISTED: i32 = 11;
pub const UNAVAILABLE: i32 = 12;

pub const CATALOG: &str = "catalog/tools.json";
pub const SCHEMA: &str = "catalog/catalog.schema.json";
pub const SOURCES: &str = "catalog/sources.json";
pub const APP_INFO: &str = "apps/desktop/vitruvian/Resources/Info.plist";
pub const HOME_REPO: &str = "VitruvianSoftware/vitruvian-core";
pub const AUTOMERGE_MARK: &str = "<!-- catalog-bump: may merge itself -->";
pub const FOREIGN_MARK: &str = "<!-- catalog-bump: foreign commits -->";
pub const HELD_MARK: &str = "<!-- catalog-bump: held for a person -->";
pub const TRAILER: &str = "Catalog-Bump";
pub const HOLDS: [&str; 2] = ["needs-human", "do-not-automerge"];
pub const BUMP_FILES: [&str; 2] = [CATALOG, "apps/web/vitruviansoftware-dev/_data/tools.yml"];
pub const APP_AUTHORS: [&str; 2] = [
    "app/vitruvian-copybara-sync",
    "vitruvian-copybara-sync[bot]",
];
pub const MERGEABLE_TRIES: usize = 6;
pub const MERGEABLE_WAIT: u64 = 5;

fn branch_re() -> Regex {
    pyre::fixed(r"^catalog/bump-(?P<id>[a-z0-9.-]+)-(?P<version>[0-9]+\.[0-9]+\.[0-9]+)$")
}

/// Why bump stopped short of a bump.
#[derive(Debug)]
pub enum Stop {
    Refused(Vec<String>),
    NotReady(String),
    Unavailable(String),
    NotListed(String),
    Crash(Crash),
}

impl From<Crash> for Stop {
    fn from(c: Crash) -> Stop {
        Stop::Crash(c)
    }
}

type BRes<T> = Result<T, Stop>;

fn refused(reason: impl Into<String>) -> Stop {
    Stop::Refused(vec![reason.into()])
}

/// `notice(message)`.
pub fn notice(message: &str) {
    let prefix = match std::env::var_os("GITHUB_ACTIONS") {
        Some(v) if !v.is_empty() => "::notice::",
        _ => "",
    };
    println!("{}{}", prefix, message);
}

// --- The table of sources -----------------------------------------------------

/// `load_sources(path)`.
pub fn load_sources(path: &str) -> Res<Value> {
    let data = json::loads(&pyerr::read_text(path)?)?;
    let rows = py::get_or(&data, "sources", Value::List(vec![]))?;
    for row in rows.py_iter()? {
        for key in ["id", "repo", "tagPrefix", "asset", "uploader"] {
            let v = row.get_v(key)?;
            if !matches!(&v, Value::Str(s) if !s.is_empty()) {
                return Err(Crash::system_exit(format!(
                    "sources.json: a row has no {}: {}",
                    key,
                    row.repr()
                )));
            }
        }
        if !row
            .at("asset")?
            .as_str()
            .unwrap_or("")
            .contains("{version}")
        {
            return Err(Crash::system_exit(format!(
                "sources.json: {}'s asset has no {{version}}",
                row.at("id")?.py_str()
            )));
        }
        if !matches!(row.get_or("universal", Value::Bool(false))?, Value::Bool(_)) {
            return Err(Crash::system_exit(format!(
                "sources.json: {}'s universal is not true or false",
                row.at("id")?.py_str()
            )));
        }
        let workflow = row.get_v("releaseWorkflow")?;
        if !workflow.is_null() && !matches!(&workflow, Value::Str(s) if !s.is_empty()) {
            return Err(Crash::system_exit(format!(
                "sources.json: {}'s releaseWorkflow is not a workflow name",
                row.at("id")?.py_str()
            )));
        }
    }
    Ok(data)
}

/// A row's string field (load_sources checked it is one).
fn f(row: &Value, key: &str) -> String {
    row.field(key).map(|v| v.py_str()).unwrap_or_default()
}

/// `row_for(sources, tool_id)`.
pub fn row_for(sources: &Value, tool_id: &str) -> BRes<Value> {
    for row in sources.at("sources")?.py_iter()? {
        if json::py_eq(row.at("id")?, &json::s(tool_id)) {
            return Ok(row);
        }
    }
    Err(refused(format!(
        "{} has no row in catalog/sources.json, so no release updates it",
        tool_id
    )))
}

/// `version_of(row, tag)`.
pub fn version_of(row: &Value, tag: &str) -> Option<String> {
    let prefix = f(row, "tagPrefix");
    let version = tag.strip_prefix(prefix.as_str())?;
    rules::semver_str(version).map(|_| version.to_string())
}

fn semver_of(text: &str) -> Option<SemVer> {
    rules::semver_str(text)
}

pub fn asset_name(row: &Value, version: &str) -> String {
    f(row, "asset").replace("{version}", version)
}

pub fn download_url(row: &Value, tag: &str, version: &str) -> String {
    format!(
        "https://github.com/{}/releases/download/{}/{}",
        f(row, "repo"),
        tag,
        asset_name(row, version)
    )
}

pub fn branch_for(tool_id: &str, version: &str) -> String {
    format!("catalog/bump-{}-{}", tool_id, version)
}

// --- Where a release is read from ---------------------------------------------

/// `gh(args)`: its output, or None (having passed its stderr on) when it
/// fails.
pub fn gh(args: &[String]) -> Res<Option<Vec<u8>>> {
    let done = std::process::Command::new("gh")
        .args(args)
        .stdin(std::process::Stdio::inherit())
        .output()
        .map_err(|e| Crash::os(&e, "gh"))?;
    if !done.status.success() {
        eprint!("{}", String::from_utf8_lossy(&done.stderr));
        return Ok(None);
    }
    Ok(Some(done.stdout))
}

fn strings(args: &[&str]) -> Vec<String> {
    args.iter().map(|s| s.to_string()).collect()
}

/// Where a release's metadata and files come from.
pub trait Release {
    fn metadata(&self) -> Res<Option<Value>>;
    fn fetch(&self, asset: &Value) -> Res<Option<Vec<u8>>>;
}

pub struct GhRelease {
    pub repo: String,
    pub tag: String,
}

impl Release for GhRelease {
    fn metadata(&self) -> Res<Option<Value>> {
        gh_release(&self.repo, &self.tag)
    }

    fn fetch(&self, asset: &Value) -> Res<Option<Vec<u8>>> {
        gh(&strings(&[
            "api",
            "-H",
            "Accept: application/octet-stream",
            &format!(
                "repos/{}/releases/assets/{}",
                self.repo,
                asset.at("id")?.py_str()
            ),
        ]))
    }
}

pub struct FolderRelease {
    pub folder: String,
}

impl Release for FolderRelease {
    fn metadata(&self) -> Res<Option<Value>> {
        let path = pypath::join(&self.folder, "release.json");
        if !Path::new(&path).exists() {
            return Ok(None);
        }
        Ok(Some(json::loads(&pyerr::read_text(&path)?)?))
    }

    fn fetch(&self, asset: &Value) -> Res<Option<Vec<u8>>> {
        let name = match asset.at("name")? {
            Value::Str(s) => s.clone(),
            other => {
                return Err(Crash::new(
                    "TypeError",
                    format!(
                        "unsupported operand type(s) for /: 'PosixPath' and '{}'",
                        other.type_name()
                    ),
                ))
            }
        };
        let path = pypath::join(&self.folder, &name);
        if !Path::new(&path).exists() {
            return Ok(None);
        }
        Ok(Some(pyerr::read_bytes(&path)?))
    }
}

// --- Mach-O: which Macs a program runs on --------------------------------------

/// `app_oldest_macos(root)`.
pub fn app_oldest_macos(root: &str) -> Res<macho::Version> {
    let path = pypath::join(root, APP_INFO);
    let data = pyerr::read_bytes(&path)?;
    let info = plist::load(&data).map_err(|m| Crash::from_text(&m))?;
    let text = info.get_or("LSMinimumSystemVersion", json::s(""))?;
    let text = py::want_str(&text, "split")?.to_string();
    let parts: Vec<&str> = text.split('.').collect();
    let digits = |p: &str| !p.is_empty() && p.chars().all(|c| c.is_ascii_digit());
    if !(1..=3).contains(&parts.len()) || !parts.iter().all(|p| digits(p)) {
        return Err(Crash::system_exit(format!(
            "{}: LSMinimumSystemVersion is {}",
            APP_INFO,
            crate::pystr::repr_str(&text)
        )));
    }
    let mut n = [0u32; 3];
    for (i, p) in parts.iter().enumerate() {
        n[i] = p.parse().unwrap_or(u32::MAX);
    }
    Ok((n[0], n[1], n[2]))
}

/// `binary_problems(row, archive, manifest, oldest)`.
pub fn binary_problems(
    row: &Value,
    archive: &ZipFile,
    manifest: &Value,
    oldest: macho::Version,
) -> Res<Vec<String>> {
    let mut found = Vec::new();
    let mut programs: Vec<(String, Vec<macho::Slice>)> = Vec::new();
    for info in archive.infolist() {
        if info.is_dir() {
            continue;
        }
        let data = read_entry(archive, info)?;
        match macho::macho_slices(&data) {
            Err(error) => {
                found.push(format!(
                    "{} is a Mach-O that cannot be read: {}",
                    info.filename, error
                ));
                continue;
            }
            Ok(Some(slices)) if !slices.is_empty() => {
                match programs.iter_mut().find(|(n, _)| *n == info.filename) {
                    Some(slot) => slot.1 = slices,
                    None => programs.push((info.filename.clone(), slices)),
                }
            }
            Ok(_) => {}
        }
    }
    programs.sort_by(|a, b| a.0.cmp(&b.0));
    for (name, slices) in &programs {
        for (arch, needs) in slices {
            match needs {
                None => found.push(format!("{} ({}) names no oldest macOS", name, arch)),
                Some(v) if *v > oldest => found.push(format!(
                    "{} ({}) needs macOS {}; the app runs on macOS {}, where it would install and fail",
                    name,
                    arch,
                    macho::version_text(*v),
                    macho::version_text(oldest)
                )),
                _ => {}
            }
        }
    }
    if row.get_v("universal")?.truthy() {
        let runtime = manifest.get_or("runtime", Value::Dict(Dict::new()))?;
        let program = runtime.get_or("exec", json::s(""))?;
        json::key(&program)?;
        let listed = match &program {
            Value::Str(p) => programs.iter().any(|(n, _)| n == p),
            _ => false,
        };
        if !listed {
            let shown = if program.truthy() {
                program.py_str()
            } else {
                "its program".into()
            };
            found.push(format!(
                "{} is not a Mach-O, not universal (x86_64 and arm64), as {}'s has been",
                shown,
                f(row, "id")
            ));
        }
        for (name, slices) in &programs {
            let mut archs: Vec<String> = slices.iter().map(|(a, _)| a.clone()).collect();
            archs.sort();
            archs.dedup();
            if !(archs.iter().any(|a| a == "x86_64") && archs.iter().any(|a| a == "arm64")) {
                found.push(format!(
                    "{} is {}, not universal (x86_64 and arm64), as {}'s programs have been",
                    name,
                    archs.join(", "),
                    f(row, "id")
                ));
            }
        }
    }
    Ok(found)
}

fn read_entry(archive: &ZipFile, info: &ZipInfo) -> Res<Vec<u8>> {
    archive.read(info).map_err(|m| Crash::from_text(&m))
}

// --- The checks ---------------------------------------------------------------

fn sidecar_re() -> Regex {
    pyre::fixed(r"^([0-9a-f]{64})\s+\*?(\S.*?)\s*$")
}

/// `checked_zip(row, tag, version, release, work, oldest)`: the release's
/// metadata, the zip's SHA-256, its size and its manifest.
pub fn checked_zip(
    row: &Value,
    tag: &str,
    version: &str,
    release: &dyn Release,
    work: &Path,
    oldest: macho::Version,
) -> BRes<(Value, String, usize, Value)> {
    let meta = match release.metadata()? {
        None => {
            return Err(Stop::NotReady(format!(
                "{} has no release tagged {}",
                f(row, "repo"),
                tag
            )))
        }
        Some(m) => m,
    };
    if meta.get_v("draft")?.truthy() || meta.get_v("prerelease")?.truthy() {
        return Err(Stop::NotReady(format!(
            "{} is a draft or a pre-release",
            tag
        )));
    }
    let mut assets: Vec<(json::Key, Value)> = Vec::new();
    for a in meta.get_or("assets", Value::List(vec![]))?.py_iter()? {
        let k = json::key(&a.get_v("name")?)?;
        match assets.iter_mut().find(|(ek, _)| *ek == k) {
            Some(slot) => slot.1 = a,
            None => assets.push((k, a)),
        }
    }
    let lookup = |n: &str| {
        assets
            .iter()
            .find(|(k, _)| *k == json::Key::Str(n.to_string()))
            .map(|(_, v)| v.clone())
    };
    let name = asset_name(row, version);
    let asset = match lookup(&name) {
        None => return Err(Stop::NotReady(format!("{} has no {} yet", tag, name))),
        Some(a) => a,
    };
    let mut reasons = Vec::new();
    let sidecar = lookup(&format!("{}.sha256", name));
    if sidecar.is_none() {
        reasons.push(format!(
            "{} has {} but no {}.sha256 to check it against",
            tag, name, name
        ));
    }
    let uploader = row.at("uploader")?.clone();
    for each in [Some(&asset), sidecar.as_ref()].into_iter().flatten() {
        let up = each.get_v("uploader")?;
        let up = if up.truthy() {
            up
        } else {
            Value::Dict(Dict::new())
        };
        let who = up.get_v("login")?;
        if !json::py_eq(&who, &uploader) {
            let shown = if who.truthy() {
                who.py_str()
            } else {
                "nobody GitHub names".into()
            };
            reasons.push(format!(
                "{} was uploaded by {}, not {}, who uploads {}'s releases",
                each.at("name")?.py_str(),
                shown,
                uploader.py_str(),
                f(row, "id")
            ));
        }
    }
    let digest = asset.get_v("digest")?;
    let digest = if digest.truthy() { digest } else { json::s("") };
    let digest = py::want_str(&digest, "startswith")?.to_string();
    if !digest.starts_with("sha256:") {
        let shown = if digest.is_empty() {
            "none".to_string()
        } else {
            digest.clone()
        };
        reasons.push(format!(
            "GitHub records no SHA-256 for {} ({})",
            name, shown
        ));
    }
    if !reasons.is_empty() {
        return Err(Stop::Refused(reasons));
    }
    let sidecar = sidecar.unwrap();
    let data = release.fetch(&asset)?;
    let side = release.fetch(&sidecar)?;
    let data =
        data.ok_or_else(|| Stop::Unavailable(format!("{} could not be downloaded", name)))?;
    let side =
        side.ok_or_else(|| Stop::Unavailable(format!("{}.sha256 could not be downloaded", name)))?;
    let sha = sha256::hexdigest(&data);
    let size = asset.get_v("size")?;
    if !json::py_eq(&Value::Int(data.len() as i128), &size) {
        reasons.push(format!(
            "{} is {} bytes, GitHub says {}",
            name,
            data.len(),
            size.py_str()
        ));
    }
    if sha != digest["sha256:".len()..] {
        reasons.push(format!(
            "{}'s SHA-256 is {}, GitHub says {}",
            name, sha, digest
        ));
    }
    let first_line = String::from_utf8_lossy(&side)
        .split('\n')
        .next()
        .unwrap_or("")
        .to_string();
    match sidecar_re().match_(&first_line) {
        None => reasons.push(format!("{}.sha256 is not `<sha256>  <file name>`", name)),
        Some(m) => {
            let said = m.group(1).unwrap_or_default();
            let file = m.group(2).unwrap_or_default();
            if said != sha {
                reasons.push(format!(
                    "{}.sha256 says {}, the zip's is {}",
                    name, said, sha
                ));
            }
            if pypath::basename(&file) != name {
                reasons.push(format!("{}.sha256 is the checksum of {}", name, file));
            }
        }
    }
    if !reasons.is_empty() {
        return Err(Stop::Refused(reasons));
    }

    let path = work.join(&name);
    std::fs::write(&path, &data).map_err(|e| pyerr::os_stop(&e, &path))?;
    let problems = rules::zip_problems(&path)?;
    if !problems.is_empty() {
        return Err(Stop::Refused(
            problems
                .into_iter()
                .map(|p| format!("{}: {}", name, p))
                .collect(),
        ));
    }
    let archive = rules::open_zip(&path)?
        .ok_or_else(|| Crash::new("zipfile.BadZipFile", "File is not a zip file"))?;
    let info = archive
        .getinfo("vitruvian-tool.json")
        .ok_or_else(|| Crash::key_error("vitruvian-tool.json"))?
        .clone();
    let raw = read_entry(&archive, &info)?;
    let manifest = match json::loads_bytes(&raw) {
        Ok(m) => m,
        Err(e) if e.is_value_error() => {
            return Err(refused(format!(
                "{}'s vitruvian-tool.json cannot be read: {}",
                name, e.msg
            )))
        }
        Err(e) => return Err(e.into()),
    };
    let id = manifest.get_v("id")?;
    if !json::py_eq(&id, row.at("id")?) {
        reasons.push(format!(
            "the manifest's id is {}, not {}",
            id.py_str(),
            f(row, "id")
        ));
    }
    let mv = manifest.get_v("version")?;
    if !json::py_eq(&mv, &json::s(version)) {
        reasons.push(format!(
            "the manifest's version is {}, the tag's is {}",
            mv.py_str(),
            version
        ));
    }
    reasons.extend(binary_problems(row, &archive, &manifest, oldest)?);
    if !reasons.is_empty() {
        return Err(Stop::Refused(reasons));
    }
    Ok((meta, sha, data.len(), manifest))
}

// --- The entry ----------------------------------------------------------------

fn d_get<'a>(d: &'a Value, key: &str) -> Option<&'a Value> {
    d.field(key)
}

/// `from_manifest(entry, manifest)`: sets what an entry copies from its
/// manifest; the names of the fields that changed.
pub fn from_manifest(entry: &mut Value, manifest: &Value) -> Res<Vec<String>> {
    let contributes = manifest.get_or("contributes", Value::Dict(Dict::new()))?;
    let mut commands = Vec::new();
    for c in contributes
        .get_or("commands", Value::List(vec![]))?
        .py_iter()?
    {
        commands.push(json::dict(vec![
            ("id", c.get_v("id")?),
            ("title", c.get_v("title")?),
        ]));
    }
    let mut wanted: Vec<(&str, Value)> = vec![
        ("name", manifest.get_v("name")?),
        ("publisher", manifest.get_v("publisher")?),
        ("protocol", manifest.get_v("protocol")?),
        ("summary", manifest.get_v("description")?),
        (
            "uses",
            Value::List(manifest.get_or("uses", Value::List(vec![]))?.py_iter()?),
        ),
        ("commands", Value::List(commands)),
    ];
    if d_get(entry, "panels").is_some() {
        let mut panels = Vec::new();
        for p in contributes
            .get_or("panels", Value::List(vec![]))?
            .py_iter()?
        {
            panels.push(p.get_v("placement")?);
        }
        wanted.push(("panels", Value::List(panels)));
    }
    let mut changed = Vec::new();
    for (field, value) in wanted {
        let same = if field == "uses" {
            let mine = entry.get_or("uses", Value::List(vec![]))?.py_iter()?;
            let a = json::py_sorted(&mine)?;
            let b = json::py_sorted(value.as_list().unwrap())?;
            json::py_eq(&Value::List(a), &Value::List(b))
        } else {
            json::py_eq(&entry.get_v(field)?, &value)
        };
        if !same {
            if let Value::Dict(d) = entry {
                d.insert(field, value);
            }
            changed.push(field.to_string());
        }
    }
    Ok(changed)
}

fn ticks(items: &[Value]) -> String {
    items
        .iter()
        .map(|u| format!("`{}`", u.py_str()))
        .collect::<Vec<_>>()
        .join(", ")
}

/// `for_a_person(old, new, manifest)`: why the pull request waits.
pub fn for_a_person(old: &Value, new: &Value, manifest: &Value) -> Res<Vec<String>> {
    let mut reasons = Vec::new();
    let old_uses = old.get_or("uses", Value::List(vec![]))?;
    let new_uses = new.get_or("uses", Value::List(vec![]))?;
    let mut added = Vec::new();
    for u in new_uses.py_iter()? {
        if !old_uses.py_contains(&u)? {
            added.push(u);
        }
    }
    let mut removed = Vec::new();
    for u in old_uses.py_iter()? {
        if !new_uses.py_contains(&u)? {
            removed.push(u);
        }
    }
    if !added.is_empty() {
        reasons.push(format!(
            "It asks for a service it did not ask for before: {}. Read what its source does with it.",
            ticks(&added)
        ));
    }
    if !removed.is_empty() {
        reasons.push(format!("It no longer asks for {}.", ticks(&removed)));
    }
    let ids = |v: &Value| -> Res<Vec<Value>> {
        let mut out = Vec::new();
        for c in v.get_or("commands", Value::List(vec![]))?.py_iter()? {
            out.push(c.at("id")?.clone());
        }
        Ok(out)
    };
    let old_ids = Value::List(ids(old)?);
    let new_ids = Value::List(ids(new)?);
    let added: Vec<Value> = new_ids
        .as_list()
        .unwrap()
        .iter()
        .filter(|c| !old_ids.py_contains(c).unwrap_or(false))
        .cloned()
        .collect();
    let removed: Vec<Value> = old_ids
        .as_list()
        .unwrap()
        .iter()
        .filter(|c| !new_ids.py_contains(c).unwrap_or(false))
        .cloned()
        .collect();
    if !added.is_empty() {
        reasons.push(format!("It offers new commands: {}.", ticks(&added)));
    }
    if !removed.is_empty() {
        reasons.push(format!("It no longer offers {}.", ticks(&removed)));
    }
    if let Some(old_panels) = d_get(old, "panels") {
        let new_panels = new.get_v("panels")?;
        if !json::py_eq(old_panels, &new_panels) {
            reasons.push(format!(
                "Its panels changed from {} to {}.",
                json::dumps_plain(old_panels),
                json::dumps_plain(&new_panels)
            ));
        }
    }
    if !json::py_eq(&old.get_v("protocol")?, &new.get_v("protocol")?) {
        reasons.push(format!(
            "Its protocol changed from {} to {}.",
            old.get_v("protocol")?.py_str(),
            new.get_v("protocol")?.py_str()
        ));
    }
    if !json::py_eq(&old.get_v("publisher")?, &new.get_v("publisher")?) {
        reasons.push(format!(
            "It says it comes from {}, not {}. Check that is who made it.",
            new.get_v("publisher")?.repr(),
            old.get_v("publisher")?.repr()
        ));
    }
    if d_get(old, "panels").is_none()
        && manifest
            .get_or("contributes", Value::Dict(Dict::new()))?
            .get_v("panels")?
            .truthy()
    {
        reasons.push(
            "The manifest draws panels the entry does not list; add `panels` by hand if the catalog should show them."
                .into(),
        );
    }
    Ok(reasons)
}

/// `floor_notes(manifest, floor)`.
pub fn floor_notes(manifest: &Value, floor: &Value) -> Res<Vec<String>> {
    let mut notes = Vec::new();
    // Python evaluates each feature's lambda in turn, then compares.
    let m = manifest;
    let checks: [&dyn Fn() -> Res<bool>; 4] = [
        &|| Ok(json::py_eq(&m.get_v("protocol")?, &json::s("2"))),
        &|| {
            m.get_or("contributes", Value::Dict(Dict::new()))?
                .contains_str("status")
        },
        &|| {
            for p in m.get_or("preferences", Value::List(vec![]))?.py_iter()? {
                if p.contains_str("options")? {
                    return Ok(true);
                }
            }
            Ok(false)
        },
        &|| {
            Ok(m.get_or("contributes", Value::Dict(Dict::new()))?
                .get_or("status", Value::Dict(Dict::new()))?
                .get_v("activity")?
                .truthy())
        },
    ];
    let meta = [
        ("protocol 2", "3.45.0", "an older app refuses the tool"),
        (
            "a status mark on the closed island (`contributes.status`)",
            "3.48.0",
            "an older app ignores it and shows no mark",
        ),
        (
            "a preference drawn as a menu (`options`)",
            "3.48.0",
            "an older app draws a text field",
        ),
        (
            "a few words beside the status (`contributes.status.activity`)",
            "3.50.0",
            "an older app leaves the words out",
        ),
    ];
    for (check, (what, since, older)) in checks.iter().zip(meta) {
        if check()? {
            let floor_v = rules::semver(floor)?.ok_or_else(|| {
                Crash::new(
                    "TypeError",
                    "'>' not supported between instances of 'tuple' and 'NoneType'",
                )
            })?;
            if semver_of(since).unwrap() > floor_v {
                notes.push(format!(
                    "It declares {}, which Vitruvian {} draws; {}.",
                    what, since, older
                ));
            }
        }
    }
    Ok(notes)
}

/// `next_generated(previous, now)`.
pub fn next_generated(previous: &Value, now: i64) -> Res<String> {
    let mut stamp = now;
    if let Some(before) = rules::generated(&json::dict(vec![("generated", previous.clone())])) {
        if stamp <= before {
            stamp = before + 1;
        }
    }
    if stamp >= 253402300800 {
        return Err(Crash::new("OverflowError", "date value out of range"));
    }
    Ok(timefmt::format(stamp))
}

// --- tools.json, written the way it is written by hand -------------------------

/// `dumps(value)`: tools.json's own layout.
pub fn dumps(value: &Value, indent: usize) -> String {
    let pad = "  ".repeat(indent);
    let inner = "  ".repeat(indent + 1);
    match value {
        Value::Dict(d) => {
            if d.is_empty() {
                return "{}".into();
            }
            let items: Vec<String> = d
                .iter()
                .map(|(k, v)| {
                    format!(
                        "{}{}: {}",
                        inner,
                        json::quote(k, false),
                        dumps(v, indent + 1)
                    )
                })
                .collect();
            format!("{{\n{}\n{}}}", items.join(",\n"), pad)
        }
        Value::List(l) => {
            if l.iter()
                .all(|v| !matches!(v, Value::Dict(_) | Value::List(_)))
            {
                let items: Vec<String> = l.iter().map(|v| json::dumps(v, None, false)).collect();
                return format!("[{}]", items.join(", "));
            }
            let items: Vec<String> = l
                .iter()
                .map(|v| format!("{}{}", inner, dumps(v, indent + 1)))
                .collect();
            format!("[\n{}\n{}]", items.join(",\n"), pad)
        }
        other => json::dumps(other, None, false),
    }
}

/// `schema_problems(root, catalog)`.
pub fn schema_problems(root: &str, catalog: &Value) -> Res<Vec<String>> {
    let schema_doc = json::loads(&pyerr::read_text(&pypath::join(root, SCHEMA))?)?;
    Ok(schema::Validator::new(&schema_doc)
        .iter_errors(catalog)
        .into_iter()
        .map(|e| format!("schema: {}: {}", e.path_text(), e.message))
        .collect())
}

/// `write_site(root)`.
pub fn write_site(root: &str) -> Res<()> {
    for (path, data) in catalogue::outputs(Path::new(root))? {
        let full = pypath::join(root, &path);
        if let Some(parent) = Path::new(&full).parent() {
            std::fs::create_dir_all(parent).map_err(|e| pyerr::os_stop(&e, parent))?;
        }
        pyerr::write_bytes(&full, &data)?;
        println!("wrote {}", path);
    }
    Ok(())
}

// --- bump ---------------------------------------------------------------------

pub fn short(sha: &str) -> String {
    let c: Vec<char> = sha.chars().collect();
    let head: String = c.iter().take(8).collect();
    let tail: String = c[c.len().saturating_sub(4)..].iter().collect();
    format!("{}…{}", head, tail)
}

#[allow(clippy::too_many_arguments)]
fn body_for(
    row: &Value,
    tag: &str,
    entry: &Value,
    previous: &str,
    size: usize,
    sha: &str,
    changed: &[String],
    notes: &[String],
    waits: &[String],
    links: (&str, &str),
) -> Res<String> {
    let name = py::path(entry, &["name", "en"])?.py_str();
    let version = entry.at("version")?.py_str();
    let (release_url, compare_url) = links;
    let mut lines = vec![
        format!(
            "The tool catalog now offers {} {}. It offered {}.",
            name, version, previous
        ),
        String::new(),
    ];
    if !waits.is_empty() {
        lines.push("**This one waits for a person** (label `needs-human`):".into());
        lines.push(String::new());
        lines.extend(waits.iter().map(|r| format!("- {}", r)));
        lines.push(String::new());
    } else {
        lines.push("Nothing a person must read changed, so it merges itself once **catalog-check** passes on it and its other checks are green.".into());
        lines.push(String::new());
        lines.push(AUTOMERGE_MARK.into());
        lines.push(String::new());
    }
    lines.push(format!(
        "- **The release:** [{}]({}). **What changed in the source:** [{}{}...{}]({}).",
        tag,
        release_url,
        f(row, "tagPrefix"),
        previous,
        tag,
        compare_url
    ));
    lines.push(format!(
        "- **The download:** `{}`, {} bytes, SHA-256 `{}`, uploaded by `{}`.",
        asset_name(row, &version),
        size,
        short(sha),
        f(row, "uploader")
    ));
    if !changed.is_empty() {
        let fields: Vec<String> = changed.iter().map(|f| format!("`{}`", f)).collect();
        lines.push(format!(
            "- **Also copied from the tool's manifest**, as an entry says what its manifest says: {}.",
            fields.join(", ")
        ));
    }
    let floor = entry.at("minimumAppVersion")?.py_str();
    if !notes.is_empty() {
        lines.push(format!(
            "- **Oldest app version stays {}.** {}",
            floor,
            notes.join(" ")
        ));
    } else {
        lines.push(format!(
            "- **Oldest app version stays {}:** the manifest declares nothing an app that old lacks.",
            floor
        ));
    }
    for l in [
        "- **Website data:** `_data/tools.yml` is regenerated, as `bazel run //tools/sync-site-tools:sync` writes it.",
        "",
        "**What the checks prove, and what they don't:** they prove this is the file the release's own workflow uploaded, unchanged, and that it is a tool for every Mac the app runs on; they do not prove the release's code is safe, which is what the source link above is for.",
        "",
        "Checked by `bazel run //catalog:bump` before this opened: the uploader; the zip's size and SHA-256 against GitHub's record and the release's `.sha256`; a zip that unpacks safely; each program's oldest macOS and its architectures; the manifest's id and version; the catalog's schema and rules. **catalog-check** downloads it again and runs `vitruvian-tool validate`; auto-merge is armed only once that passes.",
        "",
        "After the merge, catalog-publish signs the list and opens the pull request for the website. Opened by the catalog-bump workflow.",
    ] {
        lines.push(l.into());
    }
    Ok(lines.join("\n") + "\n")
}

/// `bump(root, sources, tool_id, tag, release, now)`.
pub fn bump(
    root: &str,
    sources: &Value,
    tool_id: &str,
    tag: &str,
    release: &dyn Release,
    now: i64,
) -> BRes<Value> {
    let row = row_for(sources, tool_id)?;
    let version = match version_of(&row, tag) {
        None => {
            return Err(refused(format!(
                "{} is not a tag of {}: its tags are {}<version>",
                tag,
                tool_id,
                f(&row, "tagPrefix")
            )))
        }
        Some(v) => v,
    };
    let (_, mut catalog) = rules::load(Path::new(&pypath::join(root, CATALOG)))?;
    let mut index = None;
    for (i, t) in catalog.at("tools")?.py_iter()?.iter().enumerate() {
        if json::py_eq(t.at("id")?, &json::s(tool_id)) {
            index = Some(i);
            break;
        }
    }
    let index = match index {
        None => {
            return Err(Stop::NotListed(format!(
                "{} is not in the catalog yet; listing it the first time is a pull request by hand (catalog/README.md)",
                tool_id
            )))
        }
        Some(i) => i,
    };
    let entry = catalog.at("tools")?.as_list().unwrap()[index].clone();
    let previous_v = entry.at("version")?.clone();
    let previous = previous_v.py_str();
    if branch_re().match_(&branch_for(tool_id, &version)).is_none() {
        return Err(refused(format!(
            "{} is not a bump branch: X.Y.Z releases only",
            branch_for(tool_id, &version)
        )));
    }
    let prev_semver = rules::semver(&previous_v)?.ok_or_else(|| {
        Crash::new(
            "TypeError",
            "'<' not supported between instances of 'tuple' and 'NoneType'",
        )
    })?;
    if semver_of(&version).unwrap() < prev_semver {
        return Err(refused(format!(
            "the catalog lists {}, newer than {}",
            previous, version
        )));
    }

    let oldest = app_oldest_macos(root)?;
    let (meta, sha, size, manifest) = {
        let work = TempDir::new().map_err(|e| Crash::os(&e, "tmp"))?;
        checked_zip(&row, tag, &version, release, work.path(), oldest)?
    };

    let url = download_url(&row, tag, &version);
    let download = json::dict(vec![
        ("url", json::s(&url)),
        ("sha256", json::s(&sha)),
        ("size", Value::Int(size as i128)),
    ]);
    if version == previous && matches!(previous_v, Value::Str(_)) {
        if json::py_eq(entry.at("download")?, &download) {
            return Ok(json::dict(vec![
                ("status", json::s("current")),
                ("id", json::s(tool_id)),
                ("version", json::s(&version)),
            ]));
        }
        return Err(refused(format!(
            "the catalog lists {} with another download; the release's zip changed after it was listed, or the entry was edited by hand",
            version
        )));
    }

    let mut new = entry.clone();
    if let Value::Dict(d) = &mut new {
        d.insert("version", json::s(&version));
        d.insert("download", download);
    }
    let changed = from_manifest(&mut new, &manifest)?;
    if let Value::Dict(c) = &mut catalog {
        if let Some(Value::List(tools)) = c.get_mut("tools") {
            tools[index] = new.clone();
        }
        let next = next_generated(&c.at("generated")?.clone(), now)?;
        c.insert("generated", json::s(next));
    }

    let mut problems = schema_problems(root, &catalog)?;
    problems.extend(rules::problems(&catalog)?);
    problems.extend(rules::manifest_problems(&new, &manifest)?);
    if !problems.is_empty() {
        return Err(Stop::Refused(problems));
    }

    pyerr::write_bytes(
        &pypath::join(root, CATALOG),
        (dumps(&catalog, 0) + "\n").as_bytes(),
    )?;
    println!("wrote {}: {} {} -> {}", CATALOG, tool_id, previous, version);
    write_site(root)?;
    let waits = for_a_person(&entry, &new, &manifest)?;
    let html = meta.get_v("html_url")?;
    let release_url = if html.truthy() {
        html.py_str()
    } else {
        format!(
            "https://github.com/{}/releases/tag/{}",
            f(&row, "repo"),
            tag
        )
    };
    let compare_url = format!(
        "https://github.com/{}/compare/{}{}...{}",
        f(&row, "repo"),
        f(&row, "tagPrefix"),
        previous,
        tag
    );
    let notes = floor_notes(&manifest, new.at("minimumAppVersion")?)?;
    let body = body_for(
        &row,
        tag,
        &new,
        &previous,
        size,
        &sha,
        &changed,
        &notes,
        &waits,
        (&release_url, &compare_url),
    )?;
    Ok(json::dict(vec![
        ("status", json::s("bumped")),
        ("id", json::s(tool_id)),
        ("version", json::s(&version)),
        ("previous", json::s(&previous)),
        ("tag", json::s(tag)),
        ("branch", json::s(branch_for(tool_id, &version))),
        (
            "title",
            json::s(format!(
                "feat(catalog): {} {}",
                py::path(&new, &["name", "en"])?.py_str(),
                version
            )),
        ),
        ("automerge", Value::Bool(waits.is_empty())),
        ("body", json::s(body)),
    ]))
}

// --- plan ---------------------------------------------------------------------

pub fn refused_title(tool_id: &str, version: &str) -> String {
    format!("catalog-bump refused {} {}", tool_id, version)
}

/// What plan and automerge ask GitHub.
pub trait GitHub {
    fn tags(&self, repo: &str, prefix: &str) -> Res<Vec<String>>;
    fn release(&self, repo: &str, tag: &str) -> Res<Option<Value>>;
    fn pull(&self, branch: &str) -> Res<Value>;
    fn compare(&self, head: &str, base: &str) -> Res<Value>;
    fn pull_view(&self, number: &str) -> Res<Value>;
    fn enable_auto(&self, number: &str, sha: &str) -> Res<()>;
    fn disable_auto(&self, number: &str) -> Res<()>;
    fn add_label(&self, number: &str, label: &str) -> Res<()>;
    fn refused_open(&self, title: &str) -> Res<bool>;
    fn comment_once(&self, number: &str, mark: &str, text: &str) -> Res<bool>;
}

/// `settle_mergeable(pull, fetch, sleep)`.
pub fn settle_mergeable(
    mut pull: Value,
    fetch: &dyn Fn() -> Res<Value>,
    sleep: &dyn Fn(u64),
) -> Res<Value> {
    for _ in 0..MERGEABLE_TRIES {
        if !pull.truthy()
            || !json::py_eq(&pull.get_v("state")?, &json::s("OPEN"))
            || !json::py_eq(&pull.get_v("mergeable")?, &json::s("UNKNOWN"))
        {
            break;
        }
        sleep(MERGEABLE_WAIT);
        pull = fetch()?;
    }
    Ok(pull)
}

fn str_is(v: &Value, s: &str) -> bool {
    json::py_eq(v, &json::s(s))
}

/// `plan(catalog, sources, github)`.
pub fn plan(
    catalog: &Value,
    sources: &Value,
    github: &dyn GitHub,
    sleep: &dyn Fn(u64),
) -> Res<Vec<Value>> {
    let mut listed: Vec<(json::Key, Value)> = Vec::new();
    for t in catalog.at("tools")?.py_iter()? {
        let k = json::key(t.at("id")?)?;
        match listed.iter_mut().find(|(ek, _)| *ek == k) {
            Some(slot) => slot.1 = t,
            None => listed.push((k, t)),
        }
    }
    let mut found = Vec::new();
    for row in sources.at("sources")?.py_iter()? {
        let id = f(&row, "id");
        let entry = match listed
            .iter()
            .find(|(k, _)| *k == json::Key::Str(id.clone()))
        {
            None => {
                notice(&format!(
                    "{} is not in the catalog yet: the first listing is by hand.",
                    id
                ));
                continue;
            }
            Some((_, e)) => e.clone(),
        };
        let floor = rules::semver(entry.at("version")?)?;
        let mut versions: Vec<(SemVer, String, String)> = Vec::new();
        for tag in github.tags(&f(&row, "repo"), &f(&row, "tagPrefix"))? {
            if let Some(v) = version_of(&row, &tag) {
                let key = semver_of(&v).unwrap();
                if !key.is_prerelease() {
                    versions.push((key, v, tag));
                }
            }
        }
        // sorted(..., reverse=True): stable, so equal keys keep their order.
        versions.sort_by(|a, b| b.cmp(a));
        let mut newest = None;
        for (key, version, tag) in &versions {
            let floor = floor.clone().ok_or_else(|| {
                Crash::new(
                    "TypeError",
                    "'<=' not supported between instances of 'tuple' and 'NoneType'",
                )
            })?;
            if *key <= floor {
                break;
            }
            let release = github.release(&f(&row, "repo"), tag)?;
            if let Some(r) = release {
                if r.truthy() && !r.get_v("draft")?.truthy() && !r.get_v("prerelease")?.truthy() {
                    newest = Some((tag.clone(), version.clone(), r));
                    break;
                }
            }
        }
        let (tag, version, release) = match newest {
            None => {
                println!(
                    "{}: the catalog lists {}, the newest release.",
                    id,
                    entry.at("version")?.py_str()
                );
                continue;
            }
            Some(n) => n,
        };
        let zip_name = asset_name(&row, &version);
        let mut names = Vec::new();
        for a in release.get_or("assets", Value::List(vec![]))?.py_iter()? {
            names.push(json::key(&a.get_v("name")?)?);
        }
        if !names.contains(&json::Key::Str(zip_name.clone())) {
            notice(&format!(
                "{}: {} has no {} yet; skipped.",
                id, tag, zip_name
            ));
            continue;
        }
        if github.refused_open(&refused_title(&id, &version))? {
            notice(&format!(
                "{} {}: refused before, and its issue '{}' is open; skipped. Close the issue to try again.",
                id,
                version,
                refused_title(&id, &version)
            ));
            continue;
        }
        let branch = branch_for(&id, &version);
        let pull = settle_mergeable(github.pull(&branch)?, &|| github.pull(&branch), sleep)?;
        let state = if pull.truthy() {
            pull.get_v("state")?
        } else {
            Value::Null
        };
        let number = || -> Res<String> { Ok(pull.at("number")?.py_str()) };
        if str_is(&state, "OPEN") && str_is(&pull.get_v("mergeable")?, "UNKNOWN") {
            notice(&format!(
                "{} {}: GitHub still has not said whether #{} merges after {} seconds; left alone, the next run looks again.",
                id,
                version,
                number()?,
                MERGEABLE_TRIES as u64 * MERGEABLE_WAIT
            ));
            continue;
        }
        if str_is(&state, "OPEN") && !str_is(&pull.get_v("mergeable")?, "CONFLICTING") {
            println!("{} {}: pull request #{} is open.", id, version, number()?);
            continue;
        }
        if str_is(&state, "CLOSED") || str_is(&state, "MERGED") {
            notice(&format!(
                "{} {}: pull request #{} was {}; skipped. Reopen it, or run catalog-bump by hand with the tag.",
                id,
                version,
                number()?,
                if str_is(&state, "CLOSED") { "closed without merging" } else { "merged" }
            ));
            continue;
        }
        if str_is(&state, "OPEN") {
            let others = foreign(&github.compare(&branch, "main")?, &id, &version)?;
            if !others.is_empty() {
                github.comment_once(
                    &number()?,
                    FOREIGN_MARK,
                    &format!(
                        "This pull request no longer merges with main, and its branch holds commits catalog-bump did not write: {}. catalog-bump will not rebuild it over them. Rebase it by hand, or close it and run catalog-bump with the tag {}.",
                        others.join(", "),
                        tag
                    ),
                )?;
                notice(&format!(
                    "{} {}: #{} has a person's commits and no longer merges; left for a person.",
                    id,
                    version,
                    number()?
                ));
                continue;
            }
        }
        println!(
            "{}: {} is newer than the catalog's {}.",
            id,
            tag,
            entry.at("version")?.py_str()
        );
        found.push(json::dict(vec![
            ("id", json::s(&id)),
            ("tag", json::s(&tag)),
        ]));
    }
    Ok(found)
}

fn home() -> String {
    std::env::var("GITHUB_REPOSITORY").unwrap_or_else(|_| HOME_REPO.into())
}

/// `gh_release(repo, tag)`.
pub fn gh_release(repo: &str, tag: &str) -> Res<Option<Value>> {
    let done = std::process::Command::new("gh")
        .args(["api", &format!("repos/{}/releases/tags/{}", repo, tag)])
        .stdin(std::process::Stdio::inherit())
        .output()
        .map_err(|e| Crash::os(&e, "gh"))?;
    if done.status.success() {
        return Ok(Some(json::loads_bytes(&done.stdout)?));
    }
    let both: Vec<u8> = [done.stdout.clone(), done.stderr.clone()].concat();
    if both.windows(9).any(|w| w == b"Not Found") {
        return Ok(None);
    }
    eprint!("{}", String::from_utf8_lossy(&done.stderr));
    Err(Crash::system_exit(format!(
        "could not read the release {} of {}",
        tag, repo
    )))
}

fn gh_json(args: &[String], what: &str) -> Res<Value> {
    match gh(args)? {
        None => Err(Crash::system_exit(format!("could not {}", what))),
        Some(out) => json::loads_bytes(&out),
    }
}

/// The GitHub `gh` reaches.
pub struct Gh;

impl Gh {
    fn act(&self, args: &[String], what: &str) -> Res<()> {
        let mut all = args.to_vec();
        all.push("--repo".into());
        all.push(home());
        match gh(&all)? {
            None => Err(Crash::system_exit(format!("could not {}", what))),
            Some(_) => Ok(()),
        }
    }
}

impl GitHub for Gh {
    fn tags(&self, repo: &str, prefix: &str) -> Res<Vec<String>> {
        let out = gh(&strings(&[
            "api",
            "--paginate",
            "--jq",
            ".[].ref",
            &format!("repos/{}/git/matching-refs/tags/{}", repo, prefix),
        ]))?;
        let out = match out {
            None => {
                return Err(Crash::system_exit(format!(
                    "could not list the tags of {}",
                    repo
                )))
            }
            Some(o) => pyerr::decode_utf8_py(&o, false)?,
        };
        Ok(out
            .split(crate::pystr::is_space)
            .filter(|l| l.starts_with("refs/tags/"))
            .map(|l| l["refs/tags/".len()..].to_string())
            .collect())
    }

    fn release(&self, repo: &str, tag: &str) -> Res<Option<Value>> {
        gh_release(repo, tag)
    }

    fn pull(&self, branch: &str) -> Res<Value> {
        let pulls = gh_json(
            &strings(&[
                "pr",
                "list",
                "--repo",
                &home(),
                "--head",
                branch,
                "--state",
                "all",
                "--json",
                "number,state,mergeable",
            ]),
            &format!("list the pull requests from {}", branch),
        )?;
        let mut items = pulls.py_iter()?;
        // sorted(key=number, reverse=True), stable.
        let mut err = None;
        items.sort_by(|a, b| {
            let (x, y) = match (a.at("number"), b.at("number")) {
                (Ok(x), Ok(y)) => (x.clone(), y.clone()),
                (Err(e), _) | (_, Err(e)) => {
                    err.get_or_insert(e);
                    return std::cmp::Ordering::Equal;
                }
            };
            if json::py_lt(&x, &y).unwrap_or(false) {
                std::cmp::Ordering::Greater
            } else if json::py_lt(&y, &x).unwrap_or(false) {
                std::cmp::Ordering::Less
            } else {
                std::cmp::Ordering::Equal
            }
        });
        if let Some(e) = err {
            return Err(e);
        }
        Ok(items.into_iter().next().unwrap_or(Value::Null))
    }

    fn compare(&self, head: &str, base: &str) -> Res<Value> {
        gh_json(
            &strings(&[
                "api",
                &format!("repos/{}/compare/{}...{}", home(), base, head),
            ]),
            &format!("compare {}", head),
        )
    }

    fn pull_view(&self, number: &str) -> Res<Value> {
        gh_json(
            &strings(&[
                "pr",
                "view",
                number,
                "--repo",
                &home(),
                "--json",
                "state,isDraft,headRefName,headRefOid,author,labels,body,autoMergeRequest",
            ]),
            &format!("read #{}", number),
        )
    }

    fn enable_auto(&self, number: &str, sha: &str) -> Res<()> {
        self.act(
            &strings(&[
                "pr",
                "merge",
                number,
                "--squash",
                "--auto",
                "--match-head-commit",
                sha,
            ]),
            &format!("arm auto-merge on #{}", number),
        )
    }

    fn disable_auto(&self, number: &str) -> Res<()> {
        self.act(
            &strings(&["pr", "merge", number, "--disable-auto"]),
            &format!("disarm #{}", number),
        )
    }

    fn add_label(&self, number: &str, label: &str) -> Res<()> {
        self.act(
            &strings(&["pr", "edit", number, "--add-label", label]),
            &format!("label #{}", number),
        )
    }

    fn refused_open(&self, title: &str) -> Res<bool> {
        let issues = gh_json(
            &strings(&[
                "issue",
                "list",
                "--repo",
                &home(),
                "--state",
                "open",
                "--search",
                &format!("in:title \"{}\"", title),
                "--json",
                "title",
            ]),
            "list the open issues",
        )?;
        for issue in issues.py_iter()? {
            if str_is(issue.at("title")?, title) {
                return Ok(true);
            }
        }
        Ok(false)
    }

    fn comment_once(&self, number: &str, mark: &str, text: &str) -> Res<bool> {
        let pull = gh_json(
            &strings(&[
                "pr",
                "view",
                number,
                "--repo",
                &home(),
                "--json",
                "comments",
            ]),
            &format!("read #{}", number),
        )?;
        for c in pull.get_or("comments", Value::List(vec![]))?.py_iter()? {
            if c.get_or("body", json::s(""))?.contains_str(mark)? {
                return Ok(false);
            }
        }
        let body = format!("{}\n{}", mark, text);
        if gh(&strings(&[
            "pr",
            "comment",
            number,
            "--repo",
            &home(),
            "--body",
            &body,
        ]))?
        .is_none()
        {
            return Err(Crash::system_exit(format!(
                "could not comment on #{}",
                number
            )));
        }
        Ok(true)
    }
}

// --- What the workflow may push, close and merge ------------------------------

pub fn trailer(tool_id: &str, version: &str) -> String {
    format!("{}: {}@{}", TRAILER, tool_id, version)
}

fn splitlines(text: &str) -> Vec<String> {
    crate::pystr::splitlines_keepends(text)
        .into_iter()
        .map(|l| {
            let mut l = l;
            if l.ends_with("\r\n") {
                l.truncate(l.len() - 2);
            } else if let Some(c) = l.chars().last() {
                if matches!(
                    c as u32,
                    0x0A | 0x0B | 0x0C | 0x0D | 0x1C | 0x1D | 0x1E | 0x85 | 0x2028 | 0x2029
                ) {
                    l.truncate(l.len() - c.len_utf8());
                }
            }
            l
        })
        .collect()
}

/// `foreign(compare, tool_id, version)`.
pub fn foreign(compare: &Value, tool_id: &str, version: &str) -> Res<Vec<String>> {
    let commits = compare.get_or("commits", Value::List(vec![]))?.py_iter()?;
    let mine = trailer(tool_id, version);
    let mut marked = Vec::new();
    for c in &commits {
        let message = py::path(c, &["commit", "message"])?;
        let message = py::want_str(message, "splitlines")?;
        if splitlines(message).iter().any(|l| *l == mine) {
            marked.push(c.clone());
        }
    }
    if commits.len() <= 1 && marked.len() == commits.len() {
        return Ok(vec![]);
    }
    let first = marked.first();
    let mut out = Vec::new();
    for c in &commits {
        if first.map_or(false, |m| json::py_eq(m, c)) {
            continue;
        }
        let sha = c.at("sha")?.py_str();
        let short: String = sha.chars().take(12).collect();
        out.push(format!(
            "{} by {}",
            short,
            py::path(c, &["commit", "author", "name"])?.py_str()
        ));
    }
    Ok(out)
}

/// `older(pulls, tool_id, version)`.
pub fn older(pulls: &Value, tool_id: &str, version: &str) -> Res<Vec<String>> {
    let prefix = format!("catalog/bump-{}-", tool_id);
    let mine = semver_of(version);
    let mut found = Vec::new();
    for pull in pulls.py_iter()? {
        let head = pull.at("headRefName")?;
        let head = py::want_str(head, "startswith")?;
        let theirs = head.strip_prefix(prefix.as_str()).and_then(semver_of);
        if let Some(t) = theirs {
            let m = mine.clone().ok_or_else(|| {
                Crash::new(
                    "TypeError",
                    "'<' not supported between instances of 'tuple' and 'NoneType'",
                )
            })?;
            if t < m {
                found.push(pull.at("number")?.py_str());
            }
        }
    }
    Ok(found)
}

/// `arm(pull, compare, tested_sha, check)`.
pub fn arm(pull: &Value, compare: &Value, tested_sha: &str, check: &str) -> Res<String> {
    let armed = !pull.get_v("autoMergeRequest")?.is_null();
    let mut labels = Vec::new();
    for label in pull.get_or("labels", Value::List(vec![]))?.py_iter()? {
        let k = json::key(label.at("name")?)?;
        if !labels.contains(&k) {
            labels.push(k);
        }
    }
    let stop = |why: &str| -> String {
        if armed {
            "disarm".into()
        } else {
            format!("leave: {}", why)
        }
    };
    if !str_is(&pull.get_v("state")?, "OPEN") || pull.get_v("isDraft")?.truthy() {
        return Ok(stop("it is not an open, ready pull request"));
    }
    let head = pull.get_or("headRefName", json::s(""))?;
    let head = match &head {
        Value::Str(s) => s.clone(),
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
    let branch = match branch_re().match_(&head) {
        None => return Ok(stop("it is not a catalog/bump-<id>-<version> branch")),
        Some(m) => m,
    };
    let author = pull.get_v("author")?;
    let author = if author.truthy() {
        author
    } else {
        Value::Dict(Dict::new())
    };
    let login = author.get_v("login")?;
    if !APP_AUTHORS.iter().any(|a| str_is(&login, a)) {
        return Ok(stop("catalog-bump did not open it"));
    }
    let others = foreign(
        compare,
        &branch.name("id").unwrap(),
        &branch.name("version").unwrap(),
    )?;
    if !others.is_empty() {
        return Ok(format!(
            "hold: its branch holds commits catalog-bump did not write: {}",
            others.join(", ")
        ));
    }
    let files = match compare.field("files") {
        None => {
            if compare.as_dict().is_none() {
                compare.contains_str("files")?;
            }
            return Ok("hold: GitHub did not say which files the branch changes".into());
        }
        Some(f) => f.clone(),
    };
    let file_list = files.py_iter()?;
    let mut outside = Vec::new();
    for fl in &file_list {
        let name = fl.get_v("filename")?;
        if !BUMP_FILES.iter().any(|b| str_is(&name, b)) {
            outside.push(fl.get_or("filename", json::s("?"))?);
        }
    }
    let outside = json::py_sorted(&outside)?;
    if !outside.is_empty() || file_list.len() >= 300 {
        let listed: Vec<String> = outside
            .iter()
            .take(20)
            .map(|f| format!("`{}`", f.py_str()))
            .collect();
        let listed = if listed.is_empty() {
            "300 files or more".to_string()
        } else {
            listed.join(", ")
        };
        return Ok(format!(
            "hold: a bump changes only {}; this branch also changes {}",
            BUMP_FILES
                .iter()
                .map(|f| format!("`{}`", f))
                .collect::<Vec<_>>()
                .join(" and "),
            listed
        ));
    }
    if check == "pushed" {
        return Ok("leave: catalog-bump's own commit; catalog-check decides".into());
    }
    if check != "success" {
        return Ok(stop(&format!("catalog-check ended {}", check)));
    }
    if !str_is(&pull.get_v("headRefOid")?, tested_sha) {
        return Ok("leave: the branch moved since catalog-check ran; that run decides".into());
    }
    let mut held: Vec<String> = HOLDS
        .iter()
        .filter(|h| labels.contains(&json::Key::Str(h.to_string())))
        .map(|h| h.to_string())
        .collect();
    held.sort();
    if !held.is_empty() {
        return Ok(stop(&format!("it is held: {}", held.join(", "))));
    }
    let body = pull.get_v("body")?;
    let body = if body.truthy() { body } else { json::s("") };
    if !body.contains_str(AUTOMERGE_MARK)? {
        return Ok(stop(
            "catalog-bump did not mark it as one that may merge itself",
        ));
    }
    if armed {
        return Ok("leave: auto-merge is already on".into());
    }
    Ok("arm".into())
}

/// `automerge(github, number, tested_sha, check, base)`.
pub fn automerge(
    github: &dyn GitHub,
    number: &str,
    tested_sha: &str,
    check: &str,
    base: &str,
) -> Res<String> {
    let pull = github.pull_view(number)?;
    let head = pull.get_or("headRefOid", json::s(""))?.py_str();
    let compare = github.compare(&head, base)?;
    let decision = arm(&pull, &compare, tested_sha, check)?;
    if decision == "arm" {
        github.enable_auto(number, tested_sha)?;
    } else if decision == "disarm" {
        github.disable_auto(number)?;
    } else if let Some(why) = decision.strip_prefix("hold: ") {
        if !pull.get_v("autoMergeRequest")?.is_null() {
            github.disable_auto(number)?;
        }
        github.add_label(number, "needs-human")?;
        github.comment_once(
            number,
            HELD_MARK,
            &format!(
                "This pull request will not merge itself: {}. Auto-merge is off and it is labelled needs-human; a person decides.",
                why
            ),
        )?;
    }
    Ok(decision)
}

// --- The command --------------------------------------------------------------

/// `workspace(given)`.
pub fn workspace(given: Option<&str>) -> String {
    if let Some(g) = given.filter(|g| !g.is_empty()) {
        return pypath::norm(g);
    }
    if let Ok(w) = std::env::var("BUILD_WORKSPACE_DIRECTORY") {
        if !w.is_empty() {
            return pypath::norm(&w);
        }
    }
    let here: PathBuf = crate::here::catalog_dir();
    here.parent()
        .map(|p| p.to_string_lossy().into_owned())
        .unwrap_or_else(|| ".".into())
}

/// `refusal(sources, tool_id, tag, reasons)`.
pub fn refusal(sources: &Value, tool_id: &str, tag: &str, reasons: &[String]) -> Res<Value> {
    let version = match row_for(sources, tool_id) {
        Ok(row) => version_of(&row, tag).unwrap_or_else(|| tag.to_string()),
        Err(Stop::Crash(c)) => return Err(c),
        Err(_) => tag.to_string(),
    };
    let mut lines = vec![
        format!(
            "catalog-bump refused to list `{}` from the release `{}`:",
            tool_id, tag
        ),
        String::new(),
    ];
    lines.extend(reasons.iter().map(|r| format!("- {}", r)));
    lines.push(String::new());
    lines.push("While this issue is open, the hourly run skips this version, and no pull request is opened for it. Close the issue to let it try again (for example once the release's files are fixed).".into());
    Ok(json::dict(vec![
        ("status", json::s("refused")),
        ("id", json::s(tool_id)),
        ("tag", json::s(tag)),
        ("version", json::s(&version)),
        ("message", json::s(reasons.join("; "))),
        (
            "reasons",
            Value::List(reasons.iter().map(json::s).collect()),
        ),
        ("issue_title", json::s(refused_title(tool_id, &version))),
        ("issue_body", json::s(lines.join("\n") + "\n")),
    ]))
}

fn val(s: &'static str, dest: &'static str, required: bool, help: Option<&str>) -> Opt {
    Opt {
        strings: vec![s],
        dest,
        kind: Kind::Value,
        help: help.map(String::from),
        required,
    }
}

fn subparser(command: &str) -> Parser {
    let opts = match command {
        "bump" => vec![
            val(
                "--id",
                "id",
                true,
                Some("the catalog entry, e.g. dev.vitruvian.homespeaker"),
            ),
            val(
                "--tag",
                "tag",
                true,
                Some("the release, e.g. home-speaker-v1.20.0"),
            ),
            val(
                "--release-dir",
                "release_dir",
                false,
                Some("read the release from this folder, not GitHub"),
            ),
            val(
                "--result-out",
                "result_out",
                false,
                Some("write what the pull request needs here, as JSON"),
            ),
            val(
                "--now",
                "now",
                false,
                Some("the time to set generated to (tests)"),
            ),
            val(
                "--root",
                "root",
                false,
                Some("the repository (default: where bazel run started)"),
            ),
        ],
        "plan" => vec![
            val("--out", "out", false, Some("write the list here, as JSON")),
            val(
                "--root",
                "root",
                false,
                Some("the repository (default: this file's)"),
            ),
        ],
        "foreign" => vec![
            val(
                "--compare",
                "compare",
                true,
                Some("GitHub's compare, as JSON"),
            ),
            val("--id", "id", true, None),
            val("--version", "version", true, None),
        ],
        "arm" => vec![
            val(
                "--pull",
                "pull",
                true,
                Some("gh pr view --json ..., as JSON"),
            ),
            val(
                "--compare",
                "compare",
                true,
                Some("compare main...head, as JSON"),
            ),
            val("--tested-sha", "tested_sha", true, None),
            val(
                "--check",
                "check",
                true,
                Some("catalog-check's result, or pushed"),
            ),
        ],
        "automerge" => vec![
            val("--pr", "pr", true, None),
            val("--tested-sha", "tested_sha", true, None),
            val(
                "--check",
                "check",
                true,
                Some("catalog-check's result, or pushed"),
            ),
            val("--base", "base", false, None),
        ],
        _ => vec![
            val(
                "--pulls",
                "pulls",
                true,
                Some("gh pr list --json number,headRefName"),
            ),
            val("--id", "id", true, None),
            val("--version", "version", true, None),
        ],
    };
    let mut all = vec![Opt::help()];
    all.extend(opts);
    Parser {
        prog: format!("bump.py {}", command),
        description: None,
        opts: all,
    }
}

const COMMANDS: [&str; 6] = ["bump", "plan", "foreign", "older", "arm", "automerge"];

fn main_parser() -> Parser {
    Parser {
        prog: "bump.py".into(),
        description: None,
        opts: vec![Opt::help()],
    }
}

/// `main(argv)`.
pub fn main(argv: &[String]) -> i32 {
    let mut argv = argv.to_vec();
    if argv.is_empty() || !COMMANDS.contains(&argv[0].as_str()) {
        argv.insert(0, "bump".into());
    }
    let command = argv[0].clone();
    let p = subparser(&command);
    let int = |dest: &str, v: &str| {
        if dest == "pr" {
            crate::argparse::py_int(v).map(|_| ()).ok_or("int")
        } else {
            Ok(())
        }
    };
    let values = match p.parse_known(&argv[1..], &int) {
        Ok((v, extras)) => {
            if !extras.is_empty() {
                let mut e = main_parser().unrecognized(&extras);
                e.stderr = e.stderr.replacen(
                    "usage: bump.py [-h]\n",
                    "usage: bump.py [-h] {bump,plan,foreign,arm,automerge,older} ...\n",
                    1,
                );
                eprint!("{}", e.stderr);
                return e.code;
            }
            v
        }
        Err(exit) => {
            print!("{}", exit.stdout);
            eprint!("{}", exit.stderr);
            return exit.code;
        }
    };
    match run(&command, &values) {
        Ok(code) => code,
        Err(c) => pyerr::finish(&c),
    }
}

fn read_json_arg(path: &str) -> Res<Value> {
    json::loads(&pyerr::read_text(&pypath::norm(path))?)
}

fn run(command: &str, args: &crate::argparse::Values) -> Res<i32> {
    let v = |k: &str| args.value(k).map(String::from);
    match command {
        "foreign" => {
            let compare = read_json_arg(&v("compare").unwrap())?;
            for line in foreign(&compare, &v("id").unwrap(), &v("version").unwrap())? {
                println!("{}", line);
            }
            return Ok(OK);
        }
        "arm" => {
            let pull = read_json_arg(&v("pull").unwrap())?;
            let compare = read_json_arg(&v("compare").unwrap())?;
            println!(
                "{}",
                arm(
                    &pull,
                    &compare,
                    &v("tested_sha").unwrap(),
                    &v("check").unwrap()
                )?
            );
            return Ok(OK);
        }
        "automerge" => {
            let pr = crate::argparse::py_int(&v("pr").unwrap())
                .unwrap_or(0)
                .to_string();
            let base = v("base").unwrap_or_else(|| "main".into());
            let decision = automerge(
                &Gh,
                &pr,
                &v("tested_sha").unwrap(),
                &v("check").unwrap(),
                &base,
            )?;
            println!("#{}: {}", pr, decision);
            return Ok(OK);
        }
        "older" => {
            let pulls = read_json_arg(&v("pulls").unwrap())?;
            for n in older(&pulls, &v("id").unwrap(), &v("version").unwrap())? {
                println!("{}", n);
            }
            return Ok(OK);
        }
        _ => {}
    }
    let root = workspace(args.value("root"));
    let sources = load_sources(&pypath::join(&root, SOURCES))?;
    if command == "plan" {
        let (_, catalog) = rules::load(Path::new(&pypath::join(&root, CATALOG)))?;
        let found = plan(&catalog, &sources, &Gh, &|s| {
            std::thread::sleep(std::time::Duration::from_secs(s))
        })?;
        let text = json::dumps_plain(&Value::List(found));
        if let Some(out) = v("out").filter(|o| !o.is_empty()) {
            pyerr::write_bytes(&pypath::norm(&out), (text.clone() + "\n").as_bytes())?;
        }
        println!("{}", text);
        return Ok(OK);
    }
    let id = v("id").unwrap();
    let tag = v("tag").unwrap();
    let release: Box<dyn Release> = match v("release_dir").filter(|d| !d.is_empty()) {
        Some(d) => Box::new(FolderRelease {
            folder: pypath::norm(&d),
        }),
        None => {
            let row = match row_for(&sources, &id) {
                Ok(r) => r,
                Err(Stop::Refused(r)) => return Err(Crash::system_exit(r.join("; "))),
                Err(Stop::Crash(c)) => return Err(c),
                Err(_) => unreachable!(),
            };
            Box::new(GhRelease {
                repo: f(&row, "repo"),
                tag: tag.clone(),
            })
        }
    };
    let now = match v("now").filter(|n| !n.is_empty()) {
        Some(n) => timefmt::parse(&n).ok_or_else(|| {
            Crash::new(
                "ValueError",
                format!(
                    "time data {} does not match format '%Y-%m-%dT%H:%M:%SZ'",
                    crate::pystr::repr_str(&n)
                ),
            )
        })?,
        None => timefmt::now(),
    };
    let (result, status) = match bump(&root, &sources, &id, &tag, release.as_ref(), now) {
        Ok(r) => (r, OK),
        Err(Stop::NotReady(why)) => {
            notice(&format!("{} {}: skipped, {}.", id, tag, why));
            (
                json::dict(vec![
                    ("status", json::s("not-ready")),
                    ("message", json::s(why)),
                ]),
                NOT_READY,
            )
        }
        Err(Stop::Unavailable(why)) => {
            eprintln!("NOT OK   {} {}: {}; try again later.", id, tag, why);
            (
                json::dict(vec![
                    ("status", json::s("unavailable")),
                    ("message", json::s(why)),
                ]),
                UNAVAILABLE,
            )
        }
        Err(Stop::NotListed(why)) => {
            notice(&format!("{}: skipped, {}.", id, why));
            (
                json::dict(vec![
                    ("status", json::s("not-listed")),
                    ("message", json::s(why)),
                ]),
                NOT_LISTED,
            )
        }
        Err(Stop::Refused(reasons)) => {
            for reason in &reasons {
                eprintln!("NOT OK   {} {}: {}", id, tag, reason);
            }
            eprintln!("Nothing was written.");
            (refusal(&sources, &id, &tag, &reasons)?, REFUSED)
        }
        Err(Stop::Crash(c)) => return Err(c),
    };
    if result
        .field("status")
        .map_or(false, |s| str_is(s, "current"))
    {
        println!("{}: the catalog already lists {}. Nothing to do.", id, tag);
    }
    if let Some(out) = v("result_out").filter(|o| !o.is_empty()) {
        pyerr::write_bytes(
            &pypath::norm(&out),
            (json::dumps(&result, Some(2), false) + "\n").as_bytes(),
        )?;
    }
    Ok(status)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn branch_and_tag_helpers() {
        assert_eq!(
            branch_for("dev.vitruvian.homespeaker", "1.20.0"),
            "catalog/bump-dev.vitruvian.homespeaker-1.20.0"
        );
        let row = json::loads(r#"{"tagPrefix": "home-speaker-v"}"#).unwrap();
        assert_eq!(
            version_of(&row, "home-speaker-v1.20.0"),
            Some("1.20.0".to_string())
        );
        assert_eq!(version_of(&row, "v1.20.0"), None);
    }
}
