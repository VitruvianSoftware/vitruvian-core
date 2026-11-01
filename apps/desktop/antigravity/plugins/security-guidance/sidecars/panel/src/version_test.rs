// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT

use serde::de::{Deserialize, Deserializer, MapAccess, SeqAccess, Visitor};
use serde::ser::{Serialize, SerializeMap, SerializeSeq, Serializer};
use serde_json::Value;
use std::fmt;
use std::fs;
use std::path::PathBuf;

const PLUGIN_NAME: &str = "security-guidance";
const PKG: &str = "apps/desktop/antigravity/plugins/security-guidance";

#[derive(Debug, Clone, PartialEq)]
enum OrderedJson {
    Null,
    Bool(bool),
    Number(serde_json::Number),
    String(String),
    Array(Vec<OrderedJson>),
    Object(Vec<(String, OrderedJson)>),
}

impl<'de> Deserialize<'de> for OrderedJson {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        struct OrderedVisitor;
        impl<'de> Visitor<'de> for OrderedVisitor {
            type Value = OrderedJson;
            fn expecting(&self, f: &mut fmt::Formatter) -> fmt::Result {
                f.write_str("any valid JSON value")
            }
            fn visit_bool<E>(self, v: bool) -> Result<Self::Value, E> {
                Ok(OrderedJson::Bool(v))
            }
            fn visit_i64<E>(self, v: i64) -> Result<Self::Value, E> {
                Ok(OrderedJson::Number(v.into()))
            }
            fn visit_u64<E>(self, v: u64) -> Result<Self::Value, E> {
                Ok(OrderedJson::Number(v.into()))
            }
            fn visit_f64<E>(self, v: f64) -> Result<Self::Value, E> {
                Ok(serde_json::Number::from_f64(v)
                    .map(OrderedJson::Number)
                    .unwrap_or(OrderedJson::Null))
            }
            fn visit_str<E>(self, v: &str) -> Result<Self::Value, E>
            where
                E: serde::de::Error,
            {
                Ok(OrderedJson::String(v.to_owned()))
            }
            fn visit_string<E>(self, v: String) -> Result<Self::Value, E> {
                Ok(OrderedJson::String(v))
            }
            fn visit_none<E>(self) -> Result<Self::Value, E> {
                Ok(OrderedJson::Null)
            }
            fn visit_unit<E>(self) -> Result<Self::Value, E> {
                Ok(OrderedJson::Null)
            }
            fn visit_seq<A>(self, mut seq: A) -> Result<Self::Value, A::Error>
            where
                A: SeqAccess<'de>,
            {
                let mut vec = Vec::new();
                while let Some(elem) = seq.next_element()? {
                    vec.push(elem);
                }
                Ok(OrderedJson::Array(vec))
            }
            fn visit_map<A>(self, mut map: A) -> Result<Self::Value, A::Error>
            where
                A: MapAccess<'de>,
            {
                let mut vec = Vec::new();
                while let Some((k, v)) = map.next_entry()? {
                    vec.push((k, v));
                }
                Ok(OrderedJson::Object(vec))
            }
        }
        deserializer.deserialize_any(OrderedVisitor)
    }
}

impl Serialize for OrderedJson {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        match self {
            OrderedJson::Null => serializer.serialize_none(),
            OrderedJson::Bool(b) => serializer.serialize_bool(*b),
            OrderedJson::Number(n) => n.serialize(serializer),
            OrderedJson::String(s) => serializer.serialize_str(s),
            OrderedJson::Array(arr) => {
                let mut seq = serializer.serialize_seq(Some(arr.len()))?;
                for item in arr {
                    seq.serialize_element(item)?;
                }
                seq.end()
            }
            OrderedJson::Object(entries) => {
                let mut map = serializer.serialize_map(Some(entries.len()))?;
                for (k, v) in entries {
                    map.serialize_entry(k, v)?;
                }
                map.end()
            }
        }
    }
}

fn repo_path(rel: &str) -> PathBuf {
    let direct = PathBuf::from(rel);
    if direct.exists() {
        return direct;
    }
    if let Ok(srcdir) = std::env::var("TEST_SRCDIR") {
        let ws = std::env::var("TEST_WORKSPACE").unwrap_or_else(|_| "_main".to_string());
        let candidate = PathBuf::from(srcdir).join(ws).join(rel);
        if candidate.exists() {
            return candidate;
        }
    }
    direct
}

fn read_file(rel: &str) -> String {
    let full = format!("{PKG}/{rel}");
    fs::read_to_string(repo_path(&full)).unwrap_or_else(|e| panic!("failed to read {full}: {e}"))
}

fn read_plugin_version() -> (String, String, Value) {
    let text = read_file("plugin.json");
    let parsed: Value = serde_json::from_str(&text).expect("valid plugin.json");
    let version = parsed
        .get("version")
        .and_then(|v| v.as_str())
        .expect("version string in plugin.json")
        .to_string();
    (text, version, parsed)
}

fn is_semver(v: &str) -> bool {
    let parts: Vec<&str> = v.split('.').collect();
    parts.len() == 3
        && parts
            .iter()
            .all(|p| !p.is_empty() && p.chars().all(|c| c.is_ascii_digit()))
}

fn format_pretty_json(text: &str) -> String {
    let ordered: OrderedJson = serde_json::from_str(text).expect("valid JSON");
    format!(
        "{}\n",
        serde_json::to_string_pretty(&ordered).expect("pretty JSON")
    )
}

#[test]
fn plugin_json_carries_a_semver_version_in_release_please_layout() {
    let (plugin_text, version, _) = read_plugin_version();
    assert!(is_semver(&version), "expected X.Y.Z, got {version}");
    assert_eq!(plugin_text, format_pretty_json(&plugin_text));
}

#[test]
fn changelog_top_section_matches_plugin_json_and_is_not_empty() {
    let (_, version, _) = read_plugin_version();
    let changelog = read_file("CHANGELOG.md");
    let headings: Vec<(usize, &str)> = changelog
        .lines()
        .enumerate()
        .filter(|(_, line)| line.starts_with("## "))
        .collect();
    assert!(
        !headings.is_empty(),
        "CHANGELOG.md has no ## version heading"
    );
    let (first_idx, first_line) = headings[0];
    let matches = first_line == format!("## {version}")
        || first_line.starts_with(&format!("## {version} ("))
        || first_line.starts_with(&format!("## [{version}]("));
    assert!(
        matches,
        "top heading \"{first_line}\" does not match plugin.json {version}"
    );
    let end_idx = headings
        .get(1)
        .map(|(idx, _)| *idx)
        .unwrap_or_else(|| changelog.lines().count());
    let body: String = changelog
        .lines()
        .skip(first_idx + 1)
        .take(end_idx.saturating_sub(first_idx + 1))
        .collect::<Vec<_>>()
        .join("\n");
    assert!(
        !body.trim().is_empty(),
        "top changelog section has no release notes"
    );
}

#[test]
fn sidecars_panel_package_json_is_at_the_same_version_in_release_please_layout() {
    let (_, version, _) = read_plugin_version();
    let panel_text = read_file("sidecars/panel/package.json");
    let panel: Value = serde_json::from_str(&panel_text).expect("valid package.json");
    assert_eq!(
        panel.get("version").and_then(|v| v.as_str()),
        Some(version.as_str())
    );
    assert_eq!(panel_text, format_pretty_json(&panel_text));
}

#[test]
fn release_please_manifest_records_the_same_version_for_plugin() {
    let (_, version, _) = read_plugin_version();
    let manifest: Value =
        serde_json::from_str(&read_file(".release-please-manifest.json")).unwrap();
    assert_eq!(
        manifest.get(PKG).and_then(|v| v.as_str()),
        Some(version.as_str())
    );
}

#[test]
fn release_please_config_bumps_both_versioned_json_files_together() {
    let config: Value = serde_json::from_str(&read_file("release-please-config.json")).unwrap();
    let entry = config
        .get("packages")
        .and_then(|p| p.get(PKG))
        .unwrap_or_else(|| panic!("missing {PLUGIN_NAME} package in release-please-config.json"));
    let mut extra: Vec<&str> = entry
        .get("extra-files")
        .and_then(|v| v.as_array())
        .map(|arr| {
            arr.iter()
                .filter_map(|f| f.get("path").and_then(|v| v.as_str()))
                .collect()
        })
        .unwrap_or_default();
    extra.sort_unstable();
    assert_eq!(extra, vec!["plugin.json", "sidecars/panel/package.json"]);
}
