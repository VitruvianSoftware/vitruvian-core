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

//! Did every released version come from the workflow, and not from a
//! person? check.py, ported; its docstring says why it exists. It asks npm,
//! crates.io and PyPI, in public and with no token, who published each
//! version, and holds that to bootstrap.tsv: the one version of a package
//! that may predate the workflow, with everything before it.
//!
//! Exit: 0 every version is the workflow's or recorded · 1 one or more are
//! not · 2 a registry could not be read, or bootstrap.tsv is wrong.

use std::collections::{HashMap, HashSet};
use std::io::Write;

use crate::http::{Answer, RegistryError};
use crate::inventory::{self, Package, REGISTRIES};
use crate::json::{self, get_or, or_empty, Crash, Value};
use crate::py::{self, ReadError};

pub const LEDGER: &str = "tools/registry-trust/bootstrap.tsv";

pub type Fetch<'a> = dyn FnMut(&str) -> Result<Answer, RegistryError> + 'a;

pub fn called(registry: &str) -> &'static str {
    match registry {
        "npm" => "npm",
        "pypi" => "PyPI",
        _ => "crates.io",
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Row {
    pub registry: String,
    pub package: String,
    pub version: String,
    pub date: String,
    pub why: String,
}

/// kind: workflow | person | silent (the registry says nothing) | foreign
#[derive(Clone, Debug, PartialEq)]
pub struct Version {
    pub number: String,
    /// Microseconds since the epoch, UTC.
    pub when: i128,
    pub kind: &'static str,
    pub who: String,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Outcome {
    pub package: Package,
    pub absent: bool,
    pub workflow: usize,
    pub history: usize,
    pub silent: usize,
    pub upto: Option<String>,
    pub offending: Vec<String>,
}

// --- the ledger -----------------------------------------------------------------

fn is_date(text: &str) -> bool {
    let b: Vec<char> = text.chars().collect();
    b.len() == 10
        && b.iter().enumerate().all(|(i, c)| {
            if i == 4 || i == 7 {
                *c == '-'
            } else {
                c.is_ascii_digit()
            }
        })
}

pub fn parse_ledger(text: &str) -> (Vec<Row>, Vec<String>) {
    let mut rows = Vec::new();
    let mut problems = Vec::new();
    let mut seen: HashMap<(String, String), usize> = HashMap::new();
    for (index, line) in text.split('\n').enumerate() {
        let number = index + 1;
        if py::strip(line).is_empty() || line.starts_with('#') {
            continue;
        }
        let fields: Vec<&str> = line.split('\t').collect();
        if fields.len() != 5 || !fields.iter().all(|f| !py::strip(f).is_empty()) {
            problems.push(format!(
                "line {number}: want 5 fields with tabs between (registry, package, version, date, why), each filled in"
            ));
            continue;
        }
        let f: Vec<String> = fields.iter().map(|f| py::strip(f).to_string()).collect();
        let row = Row {
            registry: f[0].clone(),
            package: f[1].clone(),
            version: f[2].clone(),
            date: f[3].clone(),
            why: f[4].clone(),
        };
        if !REGISTRIES.contains(&row.registry.as_str()) {
            problems.push(format!(
                "line {number}: {} is not one of {}",
                py::repr_str(&row.registry),
                REGISTRIES.join(", ")
            ));
            continue;
        }
        if !is_date(&row.date) {
            problems.push(format!(
                "line {number}: the date {} is not YYYY-MM-DD",
                py::repr_str(&row.date)
            ));
            continue;
        }
        let key = (row.registry.clone(), row.package.clone());
        if let Some(other) = seen.get(&key) {
            problems.push(format!(
                "line {number}: more than one row for {} {} (the other is line {other}). A package is bootstrapped once.",
                row.registry, row.package
            ));
            continue;
        }
        seen.insert(key, number);
        rows.push(row);
    }
    (rows, problems)
}

pub fn unknown_rows(rows: &[Row], packages: &[Package]) -> Vec<String> {
    let known: HashSet<(&str, &str)> = packages
        .iter()
        .map(|p| (p.registry.as_str(), p.name.as_str()))
        .collect();
    rows.iter()
        .filter(|r| !known.contains(&(r.registry.as_str(), r.package.as_str())))
        .map(|r| {
            format!(
                "{} {} has a row and is not in the inventory: take the row out, or put the package back under release-please",
                r.registry, r.package
            )
        })
        .collect()
}

// --- asking a registry ----------------------------------------------------------

/// What stops a check: a registry that gave no usable answer (exit 2), or
/// an answer the script would have crashed on (exit 1, its traceback).
#[derive(Debug, Clone, PartialEq)]
pub enum Fail {
    Registry(RegistryError),
    Crash(Crash),
}

impl From<RegistryError> for Fail {
    fn from(error: RegistryError) -> Fail {
        Fail::Registry(error)
    }
}

impl From<Crash> for Fail {
    fn from(crash: Crash) -> Fail {
        Fail::Crash(crash)
    }
}

fn get(fetch: &mut Fetch, url: &str, absent_ok: bool) -> Result<Option<Value>, Fail> {
    let (status, body) = fetch(url)?;
    if status == 404 && absent_ok {
        return Ok(None);
    }
    if status != 200 {
        return Err(RegistryError(format!(
            "{url} answered HTTP {status}; refusing to guess what is published"
        ))
        .into());
    }
    json::loads_bytes(&body)
        .map(Some)
        .map_err(|e| RegistryError(format!("{url} did not answer with JSON: {e}")).into())
}

fn days_from_civil(y: i64, m: i64, d: i64) -> i64 {
    let y = if m <= 2 { y - 1 } else { y };
    let era = if y >= 0 { y } else { y - 399 } / 400;
    let yoe = y - era * 400;
    let doy = (153 * (if m > 2 { m - 3 } else { m + 9 }) + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146097 + doe - 719468
}

/// `datetime.fromisoformat(text)` for the forms registries write, as
/// microseconds since the epoch. A time with no offset is read as UTC.
pub fn fromisoformat(text: &str) -> Result<i128, Crash> {
    let bad = || {
        Crash::new(
            "ValueError",
            format!("Invalid isoformat string: {}", py::repr_str(text)),
        )
    };
    let t: Vec<char> = text.chars().collect();
    let num = |a: usize, n: usize| -> Option<i64> {
        let s: String = t.get(a..a + n)?.iter().collect();
        s.chars()
            .all(|c| c.is_ascii_digit())
            .then(|| s.parse().ok())
            .flatten()
    };
    let year = num(0, 4).ok_or_else(bad)?;
    if t.get(4) != Some(&'-') || t.get(7) != Some(&'-') {
        return Err(bad());
    }
    let month = num(5, 2).filter(|m| (1..=12).contains(m)).ok_or_else(bad)?;
    let day = num(8, 2).ok_or_else(bad)?;
    let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;
    let days = [
        31,
        if leap { 29 } else { 28 },
        31,
        30,
        31,
        30,
        31,
        31,
        30,
        31,
        30,
        31,
    ][month as usize - 1];
    if year < 1 || day < 1 || day > days {
        return Err(bad());
    }
    let mut micros: i128 = days_from_civil(year, month, day) as i128 * 86_400_000_000;
    if t.len() == 10 {
        return Ok(micros);
    }
    let mut i = 11;
    let hour = num(i, 2).filter(|h| *h < 24).ok_or_else(bad)?;
    i += 2;
    let mut minute = 0;
    let mut second = 0;
    let mut fraction = 0;
    if t.get(i) == Some(&':') {
        minute = num(i + 1, 2).filter(|m| *m < 60).ok_or_else(bad)?;
        i += 3;
        if t.get(i) == Some(&':') {
            second = num(i + 1, 2).filter(|s| *s < 60).ok_or_else(bad)?;
            i += 3;
            if matches!(t.get(i), Some('.' | ',')) {
                let start = i + 1;
                let mut end = start;
                while t.get(end).is_some_and(|c| c.is_ascii_digit()) {
                    end += 1;
                }
                if end == start {
                    return Err(bad());
                }
                let digits: String = t[start..end.min(start + 6)].iter().collect();
                fraction = format!("{digits:0<6}").parse::<i64>().unwrap();
                i = end;
            }
        }
    }
    micros += ((hour * 3600 + minute * 60 + second) * 1_000_000 + fraction) as i128;
    match t.get(i) {
        None => Ok(micros),
        Some(&sign @ ('+' | '-')) => {
            let oh = num(i + 1, 2).filter(|h| *h < 24).ok_or_else(bad)?;
            let (om, rest) = if t.get(i + 3) == Some(&':') {
                (num(i + 4, 2).ok_or_else(bad)?, i + 6)
            } else {
                (num(i + 3, 2).ok_or_else(bad)?, i + 5)
            };
            if rest != t.len() || om >= 60 {
                return Err(bad());
            }
            let offset = ((oh * 3600 + om * 60) * 1_000_000) as i128;
            Ok(if sign == '+' {
                micros - offset
            } else {
                micros + offset
            })
        }
        _ => Err(bad()),
    }
}

/// `check._when(value)`: `value.replace("Z", "+00:00")`, then fromisoformat.
pub fn when(value: &Value) -> Result<i128, Crash> {
    fromisoformat(&value.str_for("replace")?.replace('Z', "+00:00"))
}

pub fn npm_versions(package: &Package, fetch: &mut Fetch) -> Result<Option<Vec<Version>>, Fail> {
    let url = format!(
        "https://registry.npmjs.org/{}",
        py::quote(&package.name, "@")
    );
    let Some(data) = get(fetch, &url, true)? else {
        return Ok(None);
    };
    let mut found = Vec::new();
    for (number, version) in get_or(&data, "versions", json::dict::<String>([]))?.items()? {
        let user = or_empty(version.pget("_npmUser")?);
        let trusted =
            or_empty(user.pget("trustedPublisher")?).pget("id")? == Some(&json::s("github"));
        let attested = or_empty(version.pget("dist")?)
            .pget("attestations")?
            .is_some_and(Value::truthy);
        let kind = if trusted && attested {
            "workflow"
        } else {
            "person"
        };
        let at = when(data.index("time")?.index(number)?)?;
        let who = get_or(&user, "name", json::s("?"))?.py_str();
        found.push(Version {
            number: number.clone(),
            when: at,
            kind,
            who,
        });
    }
    Ok(Some(found))
}

pub fn crates_versions(package: &Package, fetch: &mut Fetch) -> Result<Option<Vec<Version>>, Fail> {
    let base = format!("https://crates.io/api/v1/crates/{}/versions", package.name);
    let mut page = json::s("?per_page=100");
    let mut found = Vec::new();
    while page.truthy() {
        let Value::Str(next) = &page else {
            return Err(Crash::new(
                "TypeError",
                format!(
                    "can only concatenate str (not \"{}\") to str",
                    page.type_name()
                ),
            )
            .into());
        };
        let url = format!("{base}{next}");
        let Some(data) = get(fetch, &url, found.is_empty())? else {
            return Ok(None);
        };
        for version in data.index("versions")?.iterate()? {
            let trusted = version
                .pget("trustpub_data")?
                .cloned()
                .unwrap_or(Value::Null);
            let (kind, who) = if !trusted.truthy() {
                let who = get_or(
                    &or_empty(version.pget("published_by")?),
                    "login",
                    json::s("?"),
                )?;
                ("person", who)
            } else {
                let who = match trusted.pget("repository")? {
                    Some(r) if r.truthy() => r.clone(),
                    _ => get_or(&trusted, "project_path", json::s("?"))?,
                };
                let mine = trusted.pget("provider")? == Some(&json::s("github"))
                    && who.str_for("lower")?.to_lowercase() == package.repository().to_lowercase();
                (if mine { "workflow" } else { "foreign" }, who)
            };
            let number = version.index("num")?.py_str();
            let at = when(version.index("created_at")?)?;
            found.push(Version {
                number,
                when: at,
                kind,
                who: who.py_str(),
            });
        }
        page = get_or(&data, "meta", json::dict::<String>([]))?
            .pget("next_page")?
            .cloned()
            .unwrap_or(Value::Null);
    }
    Ok(Some(found))
}

pub fn pypi_versions(package: &Package, fetch: &mut Fetch) -> Result<Option<Vec<Version>>, Fail> {
    let url = format!("https://pypi.org/pypi/{}/json", package.name);
    let Some(data) = get(fetch, &url, true)? else {
        return Ok(None);
    };
    let mut found = Vec::new();
    for (number, files) in get_or(&data, "releases", json::dict::<String>([]))?.items()? {
        if !files.truthy() {
            continue;
        }
        let files = files.iterate()?;
        let mut kinds: Vec<&str> = Vec::new();
        let mut who = String::new();
        for file in &files {
            let filename = file.index("filename")?.py_str();
            let proof = get(
                fetch,
                &format!(
                    "https://pypi.org/integrity/{}/{number}/{filename}/provenance",
                    package.name
                ),
                true,
            )?;
            let bundles = get_or(
                &or_empty(proof.as_ref()),
                "attestation_bundles",
                Value::List(Vec::new()),
            )?;
            let mut publishers = Vec::new();
            for bundle in bundles.iterate()? {
                publishers.push(or_empty(bundle.pget("publisher")?));
            }
            if publishers.is_empty() {
                kinds.push("silent");
                continue;
            }
            for publisher in &publishers {
                let mine = publisher.pget("kind")? == Some(&json::s("GitHub"))
                    && get_or(publisher, "repository", json::s(""))?
                        .str_for("lower")?
                        .to_lowercase()
                        == package.repository().to_lowercase()
                    && publisher.pget("workflow")? == Some(&json::s(&package.workflow));
                kinds.push(if mine { "workflow" } else { "foreign" });
                if !mine {
                    let shown = |k: &str| -> Result<String, Crash> {
                        Ok(publisher
                            .pget(k)?
                            .map(Value::py_str)
                            .unwrap_or_else(|| "None".into()))
                    };
                    who = format!("{} {}", shown("repository")?, shown("workflow")?);
                }
            }
        }
        let kind = if kinds.contains(&"foreign") {
            "foreign"
        } else if kinds.iter().all(|k| *k == "workflow") {
            "workflow"
        } else {
            "silent"
        };
        let mut latest: Option<i128> = None;
        for file in &files {
            let at = when(file.index("upload_time_iso_8601")?)?;
            latest = Some(latest.map_or(at, |l| l.max(at)));
        }
        let Some(at) = latest else {
            return Err(Crash::new("ValueError", "max() iterable argument is empty").into());
        };
        found.push(Version {
            number: number.clone(),
            when: at,
            kind,
            who,
        });
    }
    Ok(Some(found))
}

fn versions_of(package: &Package, fetch: &mut Fetch) -> Result<Option<Vec<Version>>, Fail> {
    match package.registry.as_str() {
        "npm" => npm_versions(package, fetch),
        "crates" => crates_versions(package, fetch),
        _ => pypi_versions(package, fetch),
    }
}

// --- the rule -------------------------------------------------------------------

fn said(package: &Package, version: &Version) -> String {
    let place = format!("{} {} {}", package.registry, package.name, version.number);
    match version.kind {
        "person" => format!("{place}: published by a person ({}), not by the workflow", version.who),
        "foreign" => format!(
            "{place}: published from {}, not from {} {}",
            version.who,
            package.repository(),
            package.workflow
        ),
        _ => format!(
            "{place}: {} has no provenance for it, so nothing public says the workflow published it",
            called(&package.registry)
        ),
    }
}

pub fn check_one(package: &Package, row: Option<&Row>, fetch: &mut Fetch) -> Result<Outcome, Fail> {
    let Some(mut versions) = versions_of(package, fetch)? else {
        return Ok(Outcome {
            package: package.clone(),
            absent: true,
            workflow: 0,
            history: 0,
            silent: 0,
            upto: None,
            offending: Vec::new(),
        });
    };
    let mut offending = Vec::new();
    let mut cutoff: Option<i128> = None;
    if let Some(row) = row {
        match versions.iter().find(|v| v.number == row.version) {
            None => offending.push(format!(
                "{} {}: bootstrap.tsv records {}, which {} does not have",
                package.registry,
                package.name,
                row.version,
                called(&package.registry)
            )),
            Some(v) if v.kind == "workflow" => offending.push(format!(
                "{} {}: bootstrap.tsv records {}, which the workflow published: the row excuses nothing and must go",
                package.registry, package.name, row.version
            )),
            Some(v) => cutoff = Some(v.when),
        }
    }
    let (mut workflow, mut history, mut silent) = (0, 0, 0);
    versions.sort_by_key(|v| v.when);
    for version in &versions {
        if version.kind == "workflow" {
            workflow += 1;
        } else if version.kind != "foreign" && cutoff.is_some_and(|c| version.when <= c) {
            if version.kind == "silent" {
                silent += 1;
            } else {
                history += 1;
            }
        } else {
            offending.push(said(package, version));
        }
    }
    Ok(Outcome {
        package: package.clone(),
        absent: false,
        workflow,
        history,
        silent,
        upto: if cutoff.is_some() {
            row.map(|r| r.version.clone())
        } else {
            None
        },
        offending,
    })
}

pub fn check(packages: &[Package], rows: &[Row], fetch: &mut Fetch) -> Result<Vec<Outcome>, Fail> {
    let by_package: HashMap<(&str, &str), &Row> = rows
        .iter()
        .map(|r| ((r.registry.as_str(), r.package.as_str()), r))
        .collect();
    packages
        .iter()
        .map(|p| {
            check_one(
                p,
                by_package
                    .get(&(p.registry.as_str(), p.name.as_str()))
                    .copied(),
                fetch,
            )
        })
        .collect()
}

pub fn report(results: &[Outcome], out: &mut dyn Write) -> i32 {
    let offending: Vec<&String> = results.iter().flat_map(|r| &r.offending).collect();
    let none = || "None".to_string();
    for result in results {
        let package = &result.package;
        let label = format!("{} {}", package.registry, package.name);
        if result.absent {
            let _ = writeln!(out, "  --  {label}: not yet on the registry");
            continue;
        }
        let mut parts = vec![format!("{} by the workflow", result.workflow)];
        let upto = result.upto.clone().unwrap_or_else(none);
        if result.history > 0 {
            parts.push(format!(
                "{} before the workflow took over (to {upto}, recorded)",
                result.history
            ));
        }
        if result.silent > 0 {
            parts.push(format!(
                "{} not publicly verifiable (to {upto}, recorded): {} says nothing public about who published a file with no provenance",
                result.silent,
                called(&package.registry)
            ));
        }
        let mark = if !result.offending.is_empty() {
            "✗ "
        } else if result.silent > 0 {
            "?? "
        } else {
            "ok "
        };
        let _ = writeln!(out, "  {mark} {label}: {}", parts.join("; "));
    }
    let total = format!(
        "{} package(s): {} version(s) by the workflow, {} before the workflow took over, {} not publicly verifiable, {} not yet on a registry",
        results.len(),
        results.iter().map(|r| r.workflow).sum::<usize>(),
        results.iter().map(|r| r.history).sum::<usize>(),
        results.iter().map(|r| r.silent).sum::<usize>(),
        results.iter().filter(|r| r.absent).count()
    );
    if !offending.is_empty() {
        let _ = writeln!(
            out,
            "registry-trust: {} thing(s) the workflow did not publish:",
            offending.len()
        );
        for line in offending {
            let _ = writeln!(out, "  ✗ {line}");
        }
        let _ = writeln!(out, "registry-trust: {total}.");
        let _ = writeln!(
            out,
            "  A version a person published is not what the code built. See docs/engineering/registry-trust.md."
        );
        return 1;
    }
    let _ = writeln!(out, "registry-trust: {total}.");
    0
}

/// `check.main`.
pub fn main(
    argv: &[String],
    root: &str,
    fetch: &mut Fetch,
    out: &mut dyn Write,
    err: &mut dyn Write,
) -> i32 {
    if let Some(first) = argv.first() {
        let _ = writeln!(err, "registry-trust: unknown argument: {first}");
        return 2;
    }
    let crashed = |err: &mut dyn Write, crash: Crash| {
        let _ = write!(err, "{}", crash.traceback());
        1
    };
    let found = match inventory::load(root) {
        Ok(found) => found,
        Err(crash) => return crashed(err, crash),
    };
    let mut problems = found.problems.clone();
    let (rows, wrong) = match py::read_text(&py::join(root, LEDGER)) {
        Ok(text) => parse_ledger(&text),
        Err(ReadError::Os(..)) => (Vec::new(), vec![format!("{LEDGER} is missing")]),
        Err(decode @ ReadError::Decode(_)) => return crashed(err, Crash(decode.crash_line())),
    };
    problems.extend(wrong.iter().map(|p| format!("{LEDGER}: {p}")));
    problems.extend(
        unknown_rows(&rows, &found.packages)
            .iter()
            .map(|p| format!("{LEDGER}: {p}")),
    );
    if found.packages.is_empty() && problems.is_empty() {
        problems.push("the inventory is empty: release-please or the layout moved".into());
    }
    if !problems.is_empty() {
        for problem in problems {
            let _ = writeln!(err, "registry-trust: {problem}");
        }
        return 2;
    }
    match check(&found.packages, &rows, fetch) {
        Ok(results) => report(&results, out),
        Err(Fail::Registry(error)) => {
            let _ = writeln!(err, "registry-trust: {error}");
            2
        }
        Err(Fail::Crash(crash)) => crashed(err, crash),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;

    const PUBSUB: &str = "@vitruviansoftware/foundation-pubsub";
    const KIT: &str = "@vitruviansoftware/tool-kit";
    const CRATE: &str = "vitruvian-tool-kit";
    const NPM: &str = "https://registry.npmjs.org/";
    const CRATES: &str = "https://crates.io/api/v1/crates/";
    const PYPI: &str = "https://pypi.org/";

    fn recorded(name: &str) -> Value {
        let text = match name {
            "npm-foundation-pubsub.json" => include_str!("../testdata/npm-foundation-pubsub.json"),
            "npm-tool-kit.json" => include_str!("../testdata/npm-tool-kit.json"),
            "crates-vitruvian-tool-kit.json" => {
                include_str!("../testdata/crates-vitruvian-tool-kit.json")
            }
            "crates-bon-page1.json" => include_str!("../testdata/crates-bon-page1.json"),
            "pypi-vitruvian-tool-kit.json" => {
                include_str!("../testdata/pypi-vitruvian-tool-kit.json")
            }
            "pypi-provenance-sampleproject.json" => {
                include_str!("../testdata/pypi-provenance-sampleproject.json")
            }
            _ => panic!("{name}"),
        };
        json::loads(text).unwrap()
    }

    fn package_in(registry: &str, name: &str, repo: &str, workflow: &str) -> Package {
        let (owner, repo) = repo.split_once('/').unwrap();
        Package {
            registry: registry.into(),
            name: name.into(),
            version: "1.1.0".into(),
            file: "x".into(),
            path: "x".into(),
            config: "x".into(),
            owner: owner.into(),
            repo: repo.into(),
            workflow: workflow.into(),
            job: "job".into(),
            environment: String::new(),
            name_value: json::s(name),
            version_value: json::s("1.1.0"),
        }
    }

    fn package(registry: &str, name: &str) -> Package {
        package_in(
            registry,
            name,
            "VitruvianSoftware/vitruvian-sdk",
            "release.yml",
        )
    }

    fn row(registry: &str, name: &str, version: &str) -> Row {
        Row {
            registry: registry.into(),
            package: name.into(),
            version: version.into(),
            date: "2026-10-13".into(),
            why: "the first publish".into(),
        }
    }

    /// Answers by address, from what a test put there.
    #[derive(Default)]
    struct Registry {
        answers: HashMap<String, Answer>,
        asked: Vec<String>,
    }

    impl Registry {
        fn put(&mut self, url: &str, body: &Value, status: u16) {
            self.answers
                .insert(url.into(), (status, json::dumps(body).into_bytes()));
        }

        fn fetch(&mut self, url: &str) -> Result<Answer, RegistryError> {
            self.asked.push(url.into());
            Ok(self
                .answers
                .get(url)
                .cloned()
                .unwrap_or_else(|| panic!("the check asked for {url}, which no test recorded")))
        }
    }

    fn run(
        packages: &[Package],
        rows: &[Row],
        registry: &mut Registry,
    ) -> Result<(i32, String), Fail> {
        let results = check(packages, rows, &mut |u: &str| registry.fetch(u))?;
        let mut out = Vec::new();
        let code = report(&results, &mut out);
        Ok((code, String::from_utf8(out).unwrap()))
    }

    fn npm() -> Registry {
        let mut r = Registry::default();
        r.put(
            &format!("{NPM}@vitruviansoftware%2Ffoundation-pubsub"),
            &recorded("npm-foundation-pubsub.json"),
            200,
        );
        r.put(
            &format!("{NPM}@vitruviansoftware%2Ftool-kit"),
            &recorded("npm-tool-kit.json"),
            200,
        );
        r
    }

    fn remove(value: &mut Value, path: &[&str]) {
        let Value::Dict(d) = value else { panic!() };
        if path.len() == 1 {
            let kept: Vec<(String, Value)> = d
                .iter()
                .filter(|(k, _)| *k != path[0])
                .map(|(k, v)| (k.clone(), v.clone()))
                .collect();
            *d = json::Dict::new();
            for (k, v) in kept {
                d.insert(k, v);
            }
            return;
        }
        remove(d.get_mut(path[0]).unwrap(), &path[1..]);
    }

    #[test]
    fn npm_a_workflow_s_versions_pass_and_recorded_history_is_said() {
        let (code, out) = run(
            &[package("npm", PUBSUB)],
            &[row("npm", PUBSUB, "0.2.0")],
            &mut npm(),
        )
        .unwrap();
        assert_eq!(code, 0, "{out}");
        assert!(out.contains("1 by the workflow"));
        assert!(out.contains("2 before the workflow took over"));
    }

    #[test]
    fn npm_a_person_s_version_with_no_row_is_named() {
        let (code, out) = run(&[package("npm", PUBSUB)], &[], &mut npm()).unwrap();
        assert_eq!(code, 1);
        assert!(out.contains(&format!("npm {PUBSUB} 0.1.0")));
        assert!(out.contains(&format!("npm {PUBSUB} 0.2.0")));
        assert!(out.contains("ipv1337"));
        assert!(!out.contains(&format!("{PUBSUB} 0.4.1")));
    }

    #[test]
    fn npm_a_person_s_version_after_the_recorded_one_is_named() {
        let (code, out) = run(
            &[package("npm", PUBSUB)],
            &[row("npm", PUBSUB, "0.1.0")],
            &mut npm(),
        )
        .unwrap();
        assert_eq!(code, 1);
        assert!(out.contains(&format!("npm {PUBSUB} 0.2.0")));
        assert!(!out.contains(&format!("npm {PUBSUB} 0.1.0:")));
    }

    #[test]
    fn npm_an_earlier_person_s_version_is_history_of_the_recorded_one() {
        let (code, out) = run(
            &[package("npm", KIT)],
            &[row("npm", KIT, "1.1.0")],
            &mut npm(),
        )
        .unwrap();
        assert_eq!(code, 0, "{out}");
        assert!(out.contains("0 by the workflow"));
        assert!(out.contains("2 before the workflow took over"));
    }

    #[test]
    fn npm_half_the_proof_is_not_the_workflow() {
        for path in [
            ["versions", "0.4.1", "dist", "attestations"],
            ["versions", "0.4.1", "_npmUser", "trustedPublisher"],
        ] {
            let mut answer = recorded("npm-foundation-pubsub.json");
            remove(&mut answer, &path);
            let mut registry = npm();
            registry.put(
                &format!("{NPM}@vitruviansoftware%2Ffoundation-pubsub"),
                &answer,
                200,
            );
            let (code, out) = run(
                &[package("npm", PUBSUB)],
                &[row("npm", PUBSUB, "0.2.0")],
                &mut registry,
            )
            .unwrap();
            assert_eq!(code, 1);
            assert!(out.contains(&format!("npm {PUBSUB} 0.4.1")));
        }
    }

    #[test]
    fn npm_a_row_that_excuses_nothing_is_named() {
        let (code, out) = run(
            &[package("npm", PUBSUB)],
            &[row("npm", PUBSUB, "0.3.0")],
            &mut npm(),
        )
        .unwrap();
        assert_eq!(code, 1);
        assert!(out.contains("0.3.0, which npm does not have"));
        let (code, out) = run(
            &[package("npm", PUBSUB)],
            &[row("npm", PUBSUB, "0.4.1")],
            &mut npm(),
        )
        .unwrap();
        assert_eq!(code, 1);
        assert!(out.contains("0.4.1, which the workflow published"));
    }

    #[test]
    fn npm_absent_is_said_and_an_unclear_answer_is_not_guessed() {
        let mut registry = npm();
        registry.put(
            &format!("{NPM}@vitruviansoftware%2Fnew"),
            &json::dict([("error", json::s("Not found"))]),
            404,
        );
        let (code, out) = run(
            &[package("npm", "@vitruviansoftware/new")],
            &[],
            &mut registry,
        )
        .unwrap();
        assert_eq!(code, 0, "{out}");
        assert!(out.contains("not yet on the registry"));
        registry.put(
            &format!("{NPM}@vitruviansoftware%2Fnew"),
            &json::dict::<String>([]),
            503,
        );
        let Fail::Registry(error) = run(
            &[package("npm", "@vitruviansoftware/new")],
            &[],
            &mut registry,
        )
        .unwrap_err() else {
            panic!("not a registry error");
        };
        assert!(error.0.contains("503"));
    }

    fn crates() -> Registry {
        let mut r = Registry::default();
        r.put(
            &format!("{CRATES}vitruvian-tool-kit/versions?per_page=100"),
            &recorded("crates-vitruvian-tool-kit.json"),
            200,
        );
        r
    }

    fn one_page() -> Value {
        let mut page = recorded("crates-bon-page1.json");
        if let Value::Dict(d) = &mut page {
            if let Some(Value::Dict(meta)) = d.get_mut("meta") {
                meta.insert("next_page".into(), Value::Null);
            }
        }
        page
    }

    #[test]
    fn crates_the_recorded_first_publish_passes_and_without_a_row_is_named() {
        let (code, out) = run(
            &[package("crates", CRATE)],
            &[row("crates", CRATE, "1.1.0")],
            &mut crates(),
        )
        .unwrap();
        assert_eq!(code, 0, "{out}");
        assert!(out.contains("1 before the workflow took over"));
        let (code, out) = run(&[package("crates", CRATE)], &[], &mut crates()).unwrap();
        assert_eq!(code, 1);
        assert!(out.contains(&format!("crates {CRATE} 1.1.0")));
        assert!(out.contains("ipv1337"));
    }

    #[test]
    fn crates_a_trusted_upload_is_the_workflow_only_from_the_mirror() {
        let mut registry = crates();
        registry.put(
            &format!("{CRATES}bon/versions?per_page=100"),
            &one_page(),
            200,
        );
        let bon = package_in("crates", "bon", "elastio/bon", "release.yml");
        let (code, out) = run(&[bon], &[], &mut registry).unwrap();
        assert_eq!(code, 0, "{out}");
        assert!(out.contains("2 by the workflow"));
        let other = package_in("crates", "bon", "elastio/other", "release.yml");
        let (code, out) = run(&[other], &[], &mut registry).unwrap();
        assert_eq!(code, 1);
        assert!(out.contains("crates bon 3.10.2"));
        assert!(out.contains("elastio/bon"));
    }

    #[test]
    fn crates_every_page_of_versions_is_read() {
        let first = recorded("crates-bon-page1.json");
        let mut second = one_page();
        let Value::Dict(d) = &mut second else {
            panic!()
        };
        let Some(Value::List(versions)) = d.get("versions").cloned() else {
            panic!()
        };
        let Value::Dict(mut v) = versions[0].clone() else {
            panic!()
        };
        v.insert("num".into(), json::s("3.10.0"));
        v.insert("trustpub_data".into(), Value::Null);
        v.insert(
            "published_by".into(),
            json::dict([("login", json::s("someone"))]),
        );
        d.insert("versions".into(), Value::List(vec![Value::Dict(v)]));
        let mut registry = Registry::default();
        registry.put(&format!("{CRATES}bon/versions?per_page=100"), &first, 200);
        let next = first
            .get("meta")
            .unwrap()
            .get("next_page")
            .unwrap()
            .py_str();
        registry.put(&format!("{CRATES}bon/versions{next}"), &second, 200);
        let (code, out) = run(
            &[package_in("crates", "bon", "elastio/bon", "release.yml")],
            &[],
            &mut registry,
        )
        .unwrap();
        assert_eq!(code, 1);
        assert!(out.contains("crates bon 3.10.0"));
        assert!(out.contains("someone"));
    }

    const FILES: [&str; 6] = [
        "vitruvian_tool_kit-0.10.0-py3-none-any.whl",
        "vitruvian_tool_kit-0.10.0.tar.gz",
        "vitruvian_tool_kit-1.0.0-py3-none-any.whl",
        "vitruvian_tool_kit-1.0.0.tar.gz",
        "vitruvian_tool_kit-1.1.0-py3-none-any.whl",
        "vitruvian_tool_kit-1.1.0.tar.gz",
    ];

    fn provenance(name: &str) -> String {
        let version = name.split('-').nth(1).unwrap().trim_end_matches(".tar.gz");
        format!("{PYPI}integrity/vitruvian-tool-kit/{version}/{name}/provenance")
    }

    fn pypi() -> Registry {
        let mut r = Registry::default();
        r.put(
            &format!("{PYPI}pypi/vitruvian-tool-kit/json"),
            &recorded("pypi-vitruvian-tool-kit.json"),
            200,
        );
        for name in FILES {
            r.put(
                &provenance(name),
                &json::dict([("message", json::s("No provenance available"))]),
                404,
            );
        }
        r
    }

    fn attest(registry: &mut Registry, version: &str, repository: &str, workflow: &str) {
        let text = json::dumps(&recorded("pypi-provenance-sampleproject.json"))
            .replace("pypa/sampleproject", repository)
            .replace(
                "\"workflow\": \"release.yml\"",
                &format!("\"workflow\": \"{workflow}\""),
            );
        let answer = json::loads(&text).unwrap();
        for name in FILES.iter().filter(|n| n.contains(&format!("-{version}"))) {
            registry.put(&provenance(name), &answer, 200);
        }
    }

    #[test]
    fn pypi_no_provenance_is_not_verifiable_never_passed() {
        let (code, out) = run(
            &[package("pypi", CRATE)],
            &[row("pypi", CRATE, "1.1.0")],
            &mut pypi(),
        )
        .unwrap();
        assert_eq!(code, 0, "{out}");
        assert!(out.contains("3 not publicly verifiable"));
        assert!(out.contains("0 by the workflow"));
        assert!(out.contains("PyPI says nothing public about who published"));
        let (code, out) = run(&[package("pypi", CRATE)], &[], &mut pypi()).unwrap();
        assert_eq!(code, 1);
        for version in ["0.10.0", "1.0.0", "1.1.0"] {
            assert!(out.contains(&format!("pypi {CRATE} {version}")));
        }
        let (code, out) = run(
            &[package("pypi", CRATE)],
            &[row("pypi", CRATE, "1.0.0")],
            &mut pypi(),
        )
        .unwrap();
        assert_eq!(code, 1);
        assert!(out.contains(&format!("pypi {CRATE} 1.1.0")));
        assert!(!out.contains(&format!("pypi {CRATE} 1.0.0:")));
    }

    #[test]
    fn pypi_provenance_counts_only_from_the_mirror_s_workflow_for_every_file() {
        let mut registry = pypi();
        attest(
            &mut registry,
            "1.1.0",
            "VitruvianSoftware/vitruvian-sdk",
            "release.yml",
        );
        let (code, out) = run(
            &[package("pypi", CRATE)],
            &[row("pypi", CRATE, "1.0.0")],
            &mut registry,
        )
        .unwrap();
        assert_eq!(code, 0, "{out}");
        assert!(out.contains("1 by the workflow"));
        assert!(out.contains("2 not publicly verifiable"));
        registry.put(
            &provenance(FILES[5]),
            &json::dict([("message", json::s("none"))]),
            404,
        );
        let (code, out) = run(
            &[package("pypi", CRATE)],
            &[row("pypi", CRATE, "1.0.0")],
            &mut registry,
        )
        .unwrap();
        assert_eq!(code, 1);
        assert!(out.contains(&format!("pypi {CRATE} 1.1.0")));
    }

    #[test]
    fn pypi_provenance_from_elsewhere_is_named() {
        let mut registry = pypi();
        attest(&mut registry, "1.1.0", "someone/else", "release.yml");
        let (code, out) = run(
            &[package("pypi", CRATE)],
            &[row("pypi", CRATE, "1.1.0")],
            &mut registry,
        )
        .unwrap();
        assert_eq!(code, 1);
        assert!(out.contains("someone/else"));
        let mut registry = pypi();
        attest(
            &mut registry,
            "1.1.0",
            "VitruvianSoftware/vitruvian-sdk",
            "other.yml",
        );
        let (code, out) = run(
            &[package("pypi", CRATE)],
            &[row("pypi", CRATE, "1.1.0")],
            &mut registry,
        )
        .unwrap();
        assert_eq!(code, 1);
        assert!(out.contains("other.yml"));
    }

    #[test]
    fn the_summary_counts_each_kind_apart() {
        let mut registry = npm();
        registry.put(
            &format!("{PYPI}pypi/vitruvian-tool-kit/json"),
            &recorded("pypi-vitruvian-tool-kit.json"),
            200,
        );
        for name in FILES {
            registry.put(&provenance(name), &json::dict::<String>([]), 404);
        }
        let (code, out) = run(
            &[package("npm", PUBSUB), package("pypi", CRATE)],
            &[row("npm", PUBSUB, "0.2.0"), row("pypi", CRATE, "1.1.0")],
            &mut registry,
        )
        .unwrap();
        assert_eq!(code, 0, "{out}");
        let last = out.trim().lines().last().unwrap();
        assert!(last.contains("2 package(s)"));
        assert!(last.contains("1 version(s) by the workflow"));
        assert!(last.contains("2 before the workflow took over"));
        assert!(last.contains("3 not publicly verifiable"));
        assert!(!out.to_lowercase().contains("passed"));
    }

    const GOOD: &str = "npm\t@x/a\t1.0.0\t2026-10-13\tthe registry refuses a trusted publisher for a package that does not exist\n";

    #[test]
    fn a_ledger_row_is_five_fields_and_comments_are_skipped() {
        let (rows, problems) = parse_ledger(&format!("# registry\tpackage\n\n{GOOD}"));
        assert!(problems.is_empty());
        assert_eq!(rows.len(), 1);
        assert_eq!(
            (
                rows[0].registry.as_str(),
                rows[0].package.as_str(),
                rows[0].date.as_str()
            ),
            ("npm", "@x/a", "2026-10-13")
        );
    }

    #[test]
    fn two_rows_for_one_package_is_a_problem_and_two_registries_are_two_packages() {
        let (_, problems) = parse_ledger(&format!("{GOOD}{}", GOOD.replace("1.0.0", "1.1.0")));
        assert_eq!(problems.len(), 1);
        assert!(problems[0].contains("more than one row for npm @x/a"));
        let (rows, problems) = parse_ledger(&format!("{GOOD}{}", GOOD.replace("npm", "crates")));
        assert!(problems.is_empty());
        assert_eq!(rows.len(), 2);
    }

    #[test]
    fn a_ledger_row_with_a_field_wrong_is_a_problem() {
        for bad in [
            "npm\t@x/a\t1.0.0\t2026-10-13\n",
            "npm\t@x/a\t1.0.0\t2026-10-13\t \n",
            "gems\t@x/a\t1.0.0\t2026-10-13\twhy\n",
            "npm\t@x/a\t1.0.0\tyesterday\twhy\n",
            "npm @x/a 1.0.0 2026-10-13 why\n",
        ] {
            let (_, problems) = parse_ledger(bad);
            assert_eq!(problems.len(), 1, "{bad}");
            assert!(problems[0].contains("line 1"));
        }
        let (_, problems) = parse_ledger("gems\t@x/a\t1.0.0\t2026-10-13\twhy\n");
        assert_eq!(
            problems[0],
            "line 1: 'gems' is not one of npm, pypi, crates"
        );
    }

    #[test]
    fn a_row_for_a_package_not_in_the_inventory_is_a_problem() {
        let (rows, _) = parse_ledger(GOOD);
        let problems = unknown_rows(&rows, &[package("npm", "@x/b")]);
        assert_eq!(problems.len(), 1);
        assert!(problems[0].contains("npm @x/a"));
        assert!(unknown_rows(&rows, &[package("npm", "@x/a")]).is_empty());
    }

    #[test]
    fn the_real_ledger_is_well_formed_with_one_row_a_package() {
        let (rows, problems) = parse_ledger(include_str!("../bootstrap.tsv"));
        assert!(problems.is_empty(), "{problems:?}");
        let keys: HashSet<(String, String)> = rows
            .iter()
            .map(|r| (r.registry.clone(), r.package.clone()))
            .collect();
        assert_eq!(keys.len(), rows.len());
        let has = |r: &str, p: &str, v: &str| {
            rows.iter()
                .any(|x| x.registry == r && x.package == p && x.version == v)
        };
        assert!(has("npm", KIT, "1.1.0"));
        assert!(has("crates", CRATE, "1.1.0"));
    }

    #[test]
    fn times_compare_across_offsets_and_precisions() {
        let w = |t: &str| when(&json::s(t));
        assert_eq!(w("1970-01-01T00:00:00Z").unwrap(), 0);
        assert_eq!(
            w("2026-10-13T17:12:25.170450Z").unwrap(),
            w("2026-10-13T19:12:25.17045+02:00").unwrap()
        );
        assert_eq!(
            w("2026-10-13T17:12:25.1704509Z").unwrap(),
            w("2026-10-13T17:12:25.170450Z").unwrap()
        );
        assert!(
            w("2026-10-13T07:06:05.072465Z").unwrap() < w("2026-10-13T07:06:05.962874Z").unwrap()
        );
        assert_eq!(w("2026-10-13").unwrap(), w("2026-10-13T00:00Z").unwrap());
        assert_eq!(
            w("2026-02-30T00:00:00Z").unwrap_err().0,
            "ValueError: Invalid isoformat string: '2026-02-30T00:00:00+00:00'"
        );
        assert_eq!(
            when(&Value::Int("5".into())).unwrap_err().0,
            "AttributeError: 'int' object has no attribute 'replace'"
        );
    }
}
