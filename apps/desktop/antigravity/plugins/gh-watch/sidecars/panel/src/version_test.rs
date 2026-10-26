// Copyright (c) 2026 VitruvianSoftware
//
// SPDX-License-Identifier: MIT

use serde::de::{MapAccess, SeqAccess, Visitor};
use serde::ser::{SerializeMap, SerializeSeq};
use serde::{Deserialize, Deserializer, Serialize, Serializer};
use serde_json::Value;
use std::fmt;
use std::fs;

const PKG: &str = "apps/desktop/antigravity/plugins/gh-watch";

fn read_file(rel: &str) -> String {
    let full = format!("{PKG}/{rel}");
    fs::read_to_string(&full)
        .or_else(|_| fs::read_to_string(rel))
        .unwrap_or_else(|e| panic!("failed to read {full}: {e}"))
}

#[derive(Clone, Debug)]
enum OrderedJson {
    Null,
    Bool(bool),
    Number(serde_json::Number),
    String(String),
    Array(Vec<OrderedJson>),
    Object(Vec<(String, OrderedJson)>),
}

impl Serialize for OrderedJson {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
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

impl<'de> Deserialize<'de> for OrderedJson {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
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
            fn visit_f64<E: serde::de::Error>(self, v: f64) -> Result<Self::Value, E> {
                serde_json::Number::from_f64(v)
                    .map(OrderedJson::Number)
                    .ok_or_else(|| E::custom("non-finite float"))
            }
            fn visit_str<E>(self, v: &str) -> Result<Self::Value, E> {
                Ok(OrderedJson::String(v.to_string()))
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
            fn visit_seq<A: SeqAccess<'de>>(self, mut seq: A) -> Result<Self::Value, A::Error> {
                let mut vec = Vec::new();
                while let Some(elem) = seq.next_element()? {
                    vec.push(elem);
                }
                Ok(OrderedJson::Array(vec))
            }
            fn visit_map<A: MapAccess<'de>>(self, mut map: A) -> Result<Self::Value, A::Error> {
                let mut entries = Vec::new();
                while let Some((k, v)) = map.next_entry()? {
                    entries.push((k, v));
                }
                Ok(OrderedJson::Object(entries))
            }
        }
        deserializer.deserialize_any(OrderedVisitor)
    }
}

fn release_please_layout(text: &str) -> String {
    let parsed: OrderedJson = serde_json::from_str(text).expect("valid JSON");
    format!(
        "{}\n",
        serde_json::to_string_pretty(&parsed).expect("pretty JSON")
    )
}

fn matches_heading(line: &str, v: &str) -> bool {
    line == format!("## {v}")
        || line.starts_with(&format!("## {v} ("))
        || line.starts_with(&format!("## [{v}]("))
}

fn is_semver(v: &str) -> bool {
    let parts: Vec<&str> = v.split('.').collect();
    parts.len() == 3
        && parts
            .iter()
            .all(|p| !p.is_empty() && p.chars().all(|c| c.is_ascii_digit()))
}

#[test]
fn plugin_json_carries_plain_semver_in_release_please_layout() {
    let raw = read_file("plugin.json");
    let val: Value = serde_json::from_str(&raw).unwrap();
    let version = val["version"].as_str().unwrap();
    assert!(is_semver(version), "expected x.y.z semver, got {version}");
    assert_eq!(raw, release_please_layout(&raw));
}

#[test]
fn changelog_newest_section_matches_plugin_json_and_is_non_empty() {
    let raw_plugin = read_file("plugin.json");
    let version = serde_json::from_str::<Value>(&raw_plugin).unwrap()["version"]
        .as_str()
        .unwrap()
        .to_string();
    let changelog = read_file("CHANGELOG.md");
    let lines: Vec<&str> = changelog.split('\n').collect();
    let first = lines.iter().find(|l| l.starts_with("## ")).copied();
    assert!(
        first.is_some_and(|l| matches_heading(l, &version)),
        "expected newest CHANGELOG heading to match {version}, got {first:?}"
    );
    let start = lines
        .iter()
        .position(|l| matches_heading(l, &version))
        .unwrap();
    let rest = &lines[start + 1..];
    let end = rest
        .iter()
        .position(|l| l.starts_with("## "))
        .unwrap_or(rest.len());
    let body = rest[..end].join("\n");
    assert!(
        !body.trim().is_empty(),
        "changelog section for {version} is empty"
    );
}

#[test]
fn panel_package_json_and_release_please_files_stay_in_lockstep() {
    let raw_plugin = read_file("plugin.json");
    let version = serde_json::from_str::<Value>(&raw_plugin).unwrap()["version"]
        .as_str()
        .unwrap()
        .to_string();
    let raw_pkg = read_file("sidecars/panel/package.json");
    let pkg_val: Value = serde_json::from_str(&raw_pkg).unwrap();
    assert_eq!(pkg_val["version"].as_str().unwrap(), version);
    assert_eq!(raw_pkg, release_please_layout(&raw_pkg));

    let manifest: Value =
        serde_json::from_str(&read_file(".release-please-manifest.json")).unwrap();
    assert_eq!(manifest[PKG].as_str().unwrap(), version);

    let config: Value = serde_json::from_str(&read_file("release-please-config.json")).unwrap();
    let pkg_cfg = &config["packages"][PKG];
    assert!(pkg_cfg.is_object());
    let mut extra_paths: Vec<String> = pkg_cfg["extra-files"]
        .as_array()
        .unwrap()
        .iter()
        .map(|e| e["path"].as_str().unwrap().to_string())
        .collect();
    extra_paths.sort();
    assert_eq!(
        extra_paths,
        vec!["plugin.json", "sidecars/panel/package.json"]
    );
}
