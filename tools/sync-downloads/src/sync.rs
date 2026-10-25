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

//! sync_downloads.py's logic: find each product's latest release, then
//! rewrite its version, download URLs and sizes in the catalog with the
//! script's own regular expressions, one substitution at a time.

use std::cmp::Ordering;
use std::io::Write;

use crate::difflib;
use crate::fetch;
use crate::json::Value;
use crate::pyerr::{self, Crash};
use crate::pyre;
use crate::pystr;

pub const DEFAULT_CATALOG: &str = "apps/web/vitruviansoftware-dev/_data/downloads.yml";

/// A non-negative integer of any size, as decimal digit values with no
/// leading zeros, ordered as numbers.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct BigNum(Vec<u8>);

impl BigNum {
    fn from_digits(digits: &[char]) -> BigNum {
        let mut v: Vec<u8> = digits
            .iter()
            .map(|c| pystr::decimal_value(*c).unwrap() as u8)
            .skip_while(|d| *d == 0)
            .collect();
        v.shrink_to_fit();
        BigNum(v)
    }

    pub fn zero() -> BigNum {
        BigNum(Vec::new())
    }

    pub fn to_u64(&self) -> u64 {
        self.0.iter().fold(0u64, |acc, d| {
            acc.saturating_mul(10).saturating_add(*d as u64)
        })
    }
}

impl Ord for BigNum {
    fn cmp(&self, other: &Self) -> Ordering {
        self.0
            .len()
            .cmp(&other.0.len())
            .then_with(|| self.0.cmp(&other.0))
    }
}

impl PartialOrd for BigNum {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

pub type Semver = (BigNum, BigNum, BigNum);

/// `parse_semver`: the first `(\d+)\.(\d+)(?:\.(\d+))?` in the tag.
pub fn parse_semver(tag: &str) -> Semver {
    let re = pyre::compile(r"(\d+)\.(\d+)(?:\.(\d+))?");
    let chars: Vec<char> = tag.chars().collect();
    match re.search(&chars) {
        None => (BigNum::zero(), BigNum::zero(), BigNum::zero()),
        Some(m) => {
            let group = |g: usize| match m.spans[g] {
                Some((a, b)) => BigNum::from_digits(&chars[a..b]),
                None => BigNum::zero(),
            };
            (group(1), group(2), group(3))
        }
    }
}

/// `format_size`, for whatever JSON value the release gives as a size.
pub fn format_size(v: &Value) -> Result<String, Crash> {
    let b = match v.as_f64() {
        Some(b) => b,
        None => {
            return Err(Crash::new(
                "TypeError",
                format!(
                    "'<' not supported between instances of '{}' and 'int'",
                    v.type_name()
                ),
            ))
        }
    };
    if b < 1024.0 * 1024.0 {
        let kb = b / 1024.0;
        if kb.is_infinite() {
            return Err(Crash::new(
                "OverflowError",
                "cannot convert float infinity to integer",
            ));
        }
        let r = pystr::round_half_even(kb);
        return Ok(format!("{} KB", fmt_int(r)));
    }
    let mb = b / (1024.0 * 1024.0);
    if mb < 10.0 || (mb * 10.0) % 10.0 != 0.0 {
        Ok(format!("{} MB", pystr::format_fixed(mb, 1)))
    } else {
        Ok(format!("{} MB", fmt_int(mb.trunc())))
    }
}

/// An integer-valued float printed as Python prints `int(x)`.
fn fmt_int(x: f64) -> String {
    let s = format!("{:.0}", x);
    if s == "-0" {
        "0".into()
    } else {
        s
    }
}

/// `get_latest_release`.
pub fn get_latest_release(
    repo: &str,
    tag_prefix: Option<&str>,
    token: Option<&str>,
) -> Result<Option<Value>, Crash> {
    if tag_prefix.map_or(true, |p| p.is_empty()) {
        let data = fetch::fetch_json(&format!("repos/{}/releases/latest", repo), token)?;
        if let Some(d) = &data {
            if d.truthy() && !pyerr::get_or(d, "prerelease", Value::Null)?.truthy() {
                return Ok(data);
            }
        }
    }
    let prefix = tag_prefix.unwrap_or("");
    let refs = fetch::fetch_json(
        &format!("repos/{}/git/matching-refs/tags/{}", repo, prefix),
        token,
    )?;
    let refs = match refs {
        Some(r) if r.truthy() => r,
        _ => {
            let releases =
                fetch::fetch_json(&format!("repos/{}/releases?per_page=50", repo), token)?;
            if let Some(rs) = releases {
                if rs.truthy() {
                    for r in pyerr::iterate(&rs)? {
                        if pyerr::get_or(&r, "prerelease", Value::Null)?.truthy() {
                            continue;
                        }
                        if prefix.is_empty() {
                            return Ok(Some(r));
                        }
                        let tag = pyerr::get_or(&r, "tag_name", Value::Str(String::new()))?;
                        if pyerr::as_str(&tag, "startswith")?.starts_with(prefix) {
                            return Ok(Some(r));
                        }
                    }
                }
            }
            return Ok(None);
        }
    };
    let mut valid: Vec<String> = Vec::new();
    for r in pyerr::iterate(&refs)? {
        let rf = pyerr::get_or(&r, "ref", Value::Str(String::new()))?;
        let name = pyerr::as_str(&rf, "replace")?.replace("refs/tags/", "");
        if name.to_lowercase().contains("beta") {
            continue;
        }
        if !prefix.is_empty() && !name.starts_with(prefix) {
            continue;
        }
        valid.push(name);
    }
    if valid.is_empty() {
        return Ok(None);
    }
    let mut keyed: Vec<(Semver, String)> =
        valid.into_iter().map(|t| (parse_semver(&t), t)).collect();
    // sort(reverse=True) is stable: equal versions keep their order.
    keyed.sort_by(|a, b| b.0.cmp(&a.0));
    let latest = &keyed[0].1;
    fetch::fetch_json(&format!("repos/{}/releases/tags/{}", repo, latest), token)
}

struct Catalog {
    content: String,
}

impl Catalog {
    fn sub(&mut self, pattern: &str, template: String) -> Result<(), Crash> {
        let re = pyre::compile(pattern);
        self.content =
            pyre::sub1(&re, &template, &self.content).map_err(|e| Crash::new(e.class, e.msg))?;
        Ok(())
    }

    fn version(&mut self, id: &str, tag: &str) -> Result<(), Crash> {
        self.sub(
            &format!(r#"(id:\s*{}[\s\S]*?version:\s*")[^"]+(")"#, id),
            format!("\\g<1>{}\\g<2>", tag),
        )
    }

    /// The url and size lines under a label, inside the block that starts
    /// with `scope` (a regex prefix such as `id:\s*home-speaker[\s\S]*?`).
    fn asset(&mut self, scope: &str, label: &str, url: &str, size: &str) -> Result<(), Crash> {
        self.sub(
            &format!(
                r"({}label:\s*{}[\s\S]*?url:\s*)[^\n]+([\s\S]*?size:\s*)[^\n]+",
                scope, label
            ),
            format!("\\g<1>{}\\g<2>{}", url, size),
        )
    }

    fn releases_url(&mut self, id: &str, tag_name: &str) -> Result<(), Crash> {
        self.sub(
            &format!(
                r"(id:\s*{}[\s\S]*?releases_url:\s*https://github.com/VitruvianSoftware/vitruvian-core/releases/tag/)[^\n]+",
                id
            ),
            format!("\\g<1>{}", tag_name),
        )
    }
}

fn say(line: &str) {
    let mut out = std::io::stdout().lock();
    let _ = writeln!(out, "{}", line);
}

fn str_of(v: &Value, key: &str, method: &str) -> Result<String, Crash> {
    let got = pyerr::get_or(v, key, Value::Str(String::new()))?;
    Ok(pyerr::as_str(&got, method)?.to_string())
}

fn assets(rel: &Value) -> Result<Vec<Value>, Crash> {
    pyerr::iterate(&pyerr::get_or(rel, "assets", Value::Arr(vec![]))?)
}

/// name, then (size, url): the script skips checksums before it formats.
struct Asset {
    name: Value,
    size: String,
    url: String,
}

fn read_asset(a: &Value, skip_signatures: bool) -> Result<Option<Asset>, Crash> {
    let name = pyerr::get_or(a, "name", Value::Str(String::new()))?;
    if skip_signatures {
        let n = pyerr::as_str(&name, "endswith")?;
        if n.ends_with(".sha256") || n.ends_with(".sig") {
            return Ok(None);
        }
    }
    let size = format_size(&pyerr::get_or(a, "size", Value::Int("0".into()))?)?;
    let url = pyerr::get_or(a, "browser_download_url", Value::Str(String::new()))?.py_str();
    Ok(Some(Asset { name, size, url }))
}

fn name_str(a: &Asset) -> &str {
    match &a.name {
        Value::Str(s) => s,
        _ => "",
    }
}

/// `sync_catalog`: the exit code, or the exception.
pub fn sync_catalog(
    path: &str,
    dry_run: bool,
    check: bool,
    token: Option<&str>,
) -> Result<i32, Crash> {
    if !std::path::Path::new(path).exists() {
        eprintln!("Error: Catalog file not found at {}", path);
        return Ok(1);
    }
    let bytes = std::fs::read(path).map_err(|e| Crash::os(&e, Some(path)))?;
    let text = String::from_utf8(bytes).map_err(|e| {
        Crash::new(
            "UnicodeDecodeError",
            format!(
                "'utf-8' codec can't decode byte at position {}: invalid utf-8",
                e.utf8_error().valid_up_to()
            ),
        )
    })?;
    // Text mode reads every line ending as \n.
    let original = text.replace("\r\n", "\n").replace('\r', "\n");
    let mut cat = Catalog {
        content: original.clone(),
    };

    say("=== DISCOVERING LATEST RELEASES ===");

    const CORE: &str = "VitruvianSoftware/vitruvian-core";
    const DMG_LABELS: [(&str, &str); 4] = [
        ("arm64.dmg", "Apple Silicon DMG"),
        ("universal.dmg", "Universal DMG"),
        ("x86_64.dmg", "Intel x86_64 DMG"),
        ("universal.zip", "Universal ZIP"),
    ];

    // 1. NexusAgent
    if let Some(rel) = get_latest_release("VitruvianSoftware/nexus-agent", None, token)? {
        if rel.truthy() {
            let tag = str_of(&rel, "tag_name", "lstrip")?
                .trim_start_matches('v')
                .to_string();
            say(&format!("✓ NexusAgent: v{}", tag));
            cat.version("nexus-agent", &tag)?;
            for a in assets(&rel)? {
                let Some(asset) = read_asset(&a, true)? else {
                    continue;
                };
                let name = name_str(&asset);
                if let Some((_, label)) =
                    DMG_LABELS.iter().find(|(needle, _)| name.contains(needle))
                {
                    cat.asset("", label, &asset.url, &asset.size)?;
                }
            }
        }
    }

    // 2. Vitruvian Desktop
    if let Some(rel) = get_latest_release(CORE, Some("vitruvian-v"), token)? {
        if rel.truthy() {
            let tag = str_of(&rel, "tag_name", "replace")?.replace("vitruvian-v", "");
            say(&format!("✓ Vitruvian Desktop: v{}", tag));
            cat.version("vitruvian-desktop", &tag)?;
            let list = assets(&rel)?;
            let mut has_universal_dmg = false;
            for a in &list {
                let name = pyerr::get_or(a, "name", Value::Str(String::new()))?;
                if pyerr::contains(&name, "universal.dmg")? {
                    has_universal_dmg = true;
                    break;
                }
            }
            let scope = r"id:\s*vitruvian-desktop[\s\S]*?";
            for a in list {
                let Some(asset) = read_asset(&a, true)? else {
                    continue;
                };
                let name = name_str(&asset);
                let label = if name.contains("arm64.dmg") {
                    Some("Apple Silicon DMG")
                } else if name.contains("universal.dmg")
                    // With no universal.dmg in the release, a plain .dmg is it.
                    || (!has_universal_dmg
                        && name.ends_with(".dmg")
                        && !name.contains("arm64")
                        && !name.contains("x86_64")
                        && !name.contains("beta"))
                {
                    Some("Universal DMG")
                } else if name.contains("x86_64.dmg") {
                    Some("Intel x86_64 DMG")
                } else if name.contains("universal.zip") {
                    Some("Universal ZIP")
                } else {
                    None
                };
                if let Some(label) = label {
                    cat.asset(scope, label, &asset.url, &asset.size)?;
                }
            }
        }
    }

    // 3. HomeSpeaker
    if let Some(rel) = get_latest_release(CORE, Some("home-speaker-v"), token)? {
        if rel.truthy() {
            let tag = str_of(&rel, "tag_name", "replace")?.replace("home-speaker-v", "");
            say(&format!("✓ HomeSpeaker: v{}", tag));
            cat.version("home-speaker", &tag)?;
            let list = assets(&rel)?;
            let mut has_universal_zip = false;
            for a in &list {
                let name = pyerr::get_or(a, "name", Value::Str(String::new()))?;
                if pyerr::contains(&name, "universal.zip")? {
                    has_universal_zip = true;
                    break;
                }
            }
            let scope = r"id:\s*home-speaker[\s\S]*?";
            for a in list {
                let Some(asset) = read_asset(&a, true)? else {
                    continue;
                };
                let name = name_str(&asset);
                let label =
                    if let Some((_, label)) = DMG_LABELS.iter().find(|(n, _)| name.contains(n)) {
                        Some(*label)
                    } else if !has_universal_zip && name.ends_with("-macOS.zip") {
                        Some("Universal ZIP")
                    } else {
                        None
                    };
                if let Some(label) = label {
                    cat.asset(scope, label, &asset.url, &asset.size)?;
                }
            }
        }
    }

    // 4. devx and 5. homelab: the version only.
    for (repo, id) in [
        ("VitruvianSoftware/devx", "devx"),
        ("VitruvianSoftware/homelab", "homelab"),
    ] {
        if let Some(rel) = get_latest_release(repo, None, token)? {
            if rel.truthy() {
                let tag = str_of(&rel, "tag_name", "lstrip")?
                    .trim_start_matches('v')
                    .to_string();
                say(&format!("✓ {}: v{}", id, tag));
                cat.version(id, &tag)?;
            }
        }
    }

    // 6. gravastar-mouse
    if let Some(rel) = get_latest_release(CORE, Some("gravastar-mouse-v"), token)? {
        if rel.truthy() {
            let tag_name = str_of(&rel, "tag_name", "replace")?;
            let ver = tag_name.replace("gravastar-mouse-v", "");
            say(&format!("✓ gravastar-mouse: v{}", ver));
            cat.version("gravastar-mouse", &ver)?;
            cat.releases_url("gravastar-mouse", &tag_name)?;
        }
    }

    // 7. esp32-s3
    if let Some(rel) = get_latest_release(CORE, Some("esp32-s3-v"), token)? {
        if rel.truthy() {
            let tag_name = str_of(&rel, "tag_name", "replace")?;
            let ver = tag_name.replace("esp32-s3-v", "");
            say(&format!("✓ esp32-s3: v{}", ver));
            cat.version("esp32-s3", &ver)?;
            cat.releases_url("esp32-s3", &tag_name)?;
            for a in assets(&rel)? {
                let asset = read_asset(&a, false)?.unwrap();
                let label = match &asset.name {
                    Value::Str(n) if n == "esp32-s3-mac-controller.zip" => {
                        Some("Mac Controller ZIP")
                    }
                    Value::Str(n) if n == "firmware.bin" => Some("Firmware Binary"),
                    Value::Str(n) if n == "bootloader.bin" => Some("Bootloader Binary"),
                    Value::Str(n) if n == "partitions.bin" => Some("Partition Table"),
                    _ => None,
                };
                if let Some(label) = label {
                    cat.asset("", label, &asset.url, &asset.size)?;
                }
            }
        }
    }

    // 8. android-remote
    if let Some(rel) = get_latest_release(CORE, Some("android-remote-v"), token)? {
        if rel.truthy() {
            let tag_name = str_of(&rel, "tag_name", "replace")?;
            let ver = tag_name.replace("android-remote-v", "");
            say(&format!("✓ Vitruvian Remote: v{}", ver));
            cat.version("android-remote", &ver)?;
            cat.releases_url("android-remote", &tag_name)?;
            for a in assets(&rel)? {
                let Some(asset) = read_asset(&a, true)? else {
                    continue;
                };
                if name_str(&asset).ends_with(".apk") {
                    cat.asset(
                        r"id:\s*android-remote[\s\S]*?",
                        "Android APK",
                        &asset.url,
                        &asset.size,
                    )?;
                }
            }
        }
    }

    if original == cat.content {
        say("\nAll package versions and download URLs are already up to date.");
        return Ok(0);
    }

    let diff = difflib::unified_diff(
        &pystr::splitlines_keepends(&original),
        &pystr::splitlines_keepends(&cat.content),
        &format!("a/{}", path),
        &format!("b/{}", path),
    );

    if check {
        say("\nCatalog is out of date! Diff:");
        say(&diff);
        return Ok(1);
    }
    if dry_run {
        say("\nDry-run mode. Proposed diff:");
        say(&diff);
        return Ok(0);
    }
    std::fs::write(path, cat.content.as_bytes()).map_err(|e| Crash::os(&e, Some(path)))?;
    say(&format!("\nSuccessfully updated {}", path));
    Ok(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn semver(tag: &str) -> (u64, u64, u64) {
        let (a, b, c) = parse_semver(tag);
        (a.to_u64(), b.to_u64(), c.to_u64())
    }

    // The cases in sync_downloads_test.py.
    #[test]
    fn test_parse_semver() {
        assert_eq!(semver("v1.2.3"), (1, 2, 3));
        assert_eq!(semver("home-speaker-v1.11.0"), (1, 11, 0));
        assert_eq!(semver("vitruvian-v3.37.1"), (3, 37, 1));
        assert_eq!(semver("nexus-agent-1.20.1"), (1, 20, 1));
        assert_eq!(semver("0.1.2"), (0, 1, 2));
        assert_eq!(semver("no-numbers"), (0, 0, 0));
    }

    #[test]
    fn parse_semver_edges() {
        assert_eq!(semver("v1.2"), (1, 2, 0));
        assert_eq!(semver("v1.2."), (1, 2, 0));
        assert_eq!(semver("x1.y2.3.4"), (2, 3, 4));
        assert_eq!(semver("v\u{0661}.\u{0662}"), (1, 2, 0));
        assert!(parse_semver("v99999999999999999999.0") > parse_semver("v9999999999999999999.0"));
    }

    fn size(n: f64) -> String {
        format_size(&Value::Float(n)).unwrap()
    }

    #[test]
    fn test_format_size_kilobytes() {
        assert_eq!(
            format_size(&Value::Int((500 * 1024).to_string())).unwrap(),
            "500 KB"
        );
        assert_eq!(
            format_size(&Value::Int((994 * 1024).to_string())).unwrap(),
            "994 KB"
        );
    }

    #[test]
    fn test_format_size_megabytes() {
        assert_eq!(
            format_size(&Value::Int((4 * 1024 * 1024).to_string())).unwrap(),
            "4.0 MB"
        );
        assert_eq!(
            format_size(&Value::Int((10 * 1024 * 1024).to_string())).unwrap(),
            "10 MB"
        );
        let n = (78.3f64 * 1024.0 * 1024.0) as i64;
        assert_eq!(format_size(&Value::Int(n.to_string())).unwrap(), "78.3 MB");
    }

    #[test]
    fn format_size_edges() {
        assert_eq!(size(512.0), "0 KB"); // 0.5 rounds to even
        assert_eq!(size(1536.0), "2 KB");
        assert_eq!(size(2560.0), "2 KB");
        assert_eq!(size(-512.0), "0 KB");
        assert_eq!(size(f64::NAN), "nan MB");
        assert_eq!(size(f64::INFINITY), "inf MB");
        assert_eq!(size(25.0 * 1024.0 * 1024.0), "25 MB");
        assert_eq!(size(25.5 * 1024.0 * 1024.0), "25.5 MB");
        assert_eq!(format_size(&Value::Bool(true)).unwrap(), "0 KB");
        assert_eq!(format_size(&Value::Null).unwrap_err().class, "TypeError");
        assert_eq!(
            format_size(&Value::Float(f64::NEG_INFINITY))
                .unwrap_err()
                .class,
            "OverflowError"
        );
    }
}
