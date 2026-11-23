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

//! A pipeline unit as the generator sees it, and loading units from
//! `.pipeline.json` files (`--units-dir`).

use std::collections::BTreeMap;

use serde::Serialize;

use crate::gostr;
use vitruvian_gojson::{parse, Dec};

pub const SCHEMA_VERSION: i64 = 1;

/// One unit. Serialised field for field as the Go struct's JSON tags.
#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct Unit {
    pub schema: i64,
    pub name: String,
    pub package: String,
    /// `None` is Go's nil slice, which serialises as `null`.
    pub test_targets: Option<Vec<String>>,
    pub tier: String,
    pub runner: String,
    pub persona: String,
    pub concurrency_group: String,
    pub timeout_minutes: i64,
    #[serde(skip_serializing_if = "BTreeMap::is_empty")]
    pub env: BTreeMap<String, String>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub depends_on: Vec<String>,
    #[serde(skip_serializing_if = "is_false")]
    pub needs_emulator: bool,
    #[serde(skip_serializing_if = "BTreeMap::is_empty")]
    pub artifacts: BTreeMap<String, String>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub build_flags: Vec<String>,
    #[serde(skip_serializing_if = "Vec::is_empty")]
    pub tags: Vec<String>,
}

fn is_false(b: &bool) -> bool {
    !*b
}

impl Unit {
    pub fn targets(&self) -> &[String] {
        self.test_targets.as_deref().unwrap_or(&[])
    }
}

const FIELDS: &[&str] = &[
    "schema",
    "name",
    "package",
    "test_targets",
    "tier",
    "runner",
    "persona",
    "concurrency_group",
    "timeout_minutes",
    "env",
    "depends_on",
    "needs_emulator",
    "artifacts",
    "build_flags",
    "tags",
];

/// Go's `json.Unmarshal(b, &u)` into the generator's Unit struct.
fn unmarshal_unit(b: &[u8]) -> Result<Unit, String> {
    let v = parse(b)?;
    let mut u = Unit::default();
    let mut depends: Option<Vec<String>> = None;
    let mut flags: Option<Vec<String>> = None;
    let mut tags: Option<Vec<String>> = None;
    let mut env: Option<BTreeMap<String, String>> = None;
    let mut artifacts: Option<BTreeMap<String, String>> = None;
    let mut d = Dec::new();
    d.object(&v, "Unit", "main.Unit", FIELDS, |d, name, val| match name {
        "schema" => d.int(val, &mut u.schema),
        "name" => d.string(val, &mut u.name),
        "package" => d.string(val, &mut u.package),
        "test_targets" => d.strings(val, &mut u.test_targets),
        "tier" => d.string(val, &mut u.tier),
        "runner" => d.string(val, &mut u.runner),
        "persona" => d.string(val, &mut u.persona),
        "concurrency_group" => d.string(val, &mut u.concurrency_group),
        "timeout_minutes" => d.int(val, &mut u.timeout_minutes),
        "env" => d.string_map(val, &mut env),
        "depends_on" => d.strings(val, &mut depends),
        "needs_emulator" => d.bool(val, &mut u.needs_emulator),
        "artifacts" => d.string_map(val, &mut artifacts),
        "build_flags" => d.strings(val, &mut flags),
        "tags" => d.strings(val, &mut tags),
        _ => unreachable!(),
    });
    d.finish()?;
    u.depends_on = depends.unwrap_or_default();
    u.build_flags = flags.unwrap_or_default();
    u.tags = tags.unwrap_or_default();
    u.env = env.unwrap_or_default();
    u.artifacts = artifacts.unwrap_or_default();
    Ok(u)
}

/// Go's `DecodeUnit`: unmarshal, validate, fill the defaults.
pub fn decode_unit(b: &[u8]) -> Result<Unit, String> {
    let mut u = unmarshal_unit(b).map_err(|e| format!("decode unit json: {e}"))?;
    if u.schema != SCHEMA_VERSION {
        return Err(format!(
            "unit {}: unsupported schema version {} (expected {})",
            gostr::quote(&u.name),
            u.schema,
            SCHEMA_VERSION
        ));
    }
    if gostr::trim_space(&u.name).is_empty() {
        return Err("unit name must not be empty".to_string());
    }
    if u.targets().is_empty() {
        return Err(format!(
            "unit {} has no test targets",
            gostr::quote(&u.name)
        ));
    }
    if u.runner.is_empty() {
        u.runner = "ubuntu-26.04".to_string();
    }
    if u.timeout_minutes <= 0 {
        u.timeout_minutes = 30;
    }
    if u.tier.is_empty() {
        u.tier = "L1".to_string();
    }
    if u.persona.is_empty() {
        u.persona = "all".to_string();
    }
    if u.concurrency_group.is_empty() {
        u.concurrency_group = format!("pipeline-{}", u.name);
    }
    Ok(u)
}

/// Go's `LoadUnits`: decode each file, sort by name, refuse a duplicate.
pub fn load_units(paths: &[String]) -> Result<Vec<Unit>, String> {
    let mut units = Vec::with_capacity(paths.len());
    for p in paths {
        let b = gostr::read_file(p).map_err(|e| format!("read unit {p}: {e}"))?;
        let u = decode_unit(&b).map_err(|e| format!("{p}: {e}"))?;
        units.push(u);
    }
    units.sort_by(|a, b| a.name.cmp(&b.name));
    for i in 1..units.len() {
        if units[i].name == units[i - 1].name {
            return Err(format!(
                "duplicate pipeline unit name {} — unit names must be unique repo-wide",
                gostr::quote(&units[i].name)
            ));
        }
    }
    Ok(units)
}

/// Go's `FindUnitFiles`: every `*.pipeline.json` under root, sorted.
pub fn find_unit_files(root: &str) -> Vec<String> {
    let mut paths = Vec::new();
    gostr::walk(root, &mut |path, is_dir, name| match is_dir {
        None => false,
        Some(true) => matches!(name, ".git" | "bazel-out" | "bazel-bin" | "node_modules"),
        Some(false) => {
            if name.ends_with(".pipeline.json") {
                paths.push(path.to_string());
            }
            false
        }
    });
    paths.sort();
    paths
}

/// Go's `json.MarshalIndent(v, "", "  ")`.
pub fn marshal_indent<T: Serialize>(v: &T) -> String {
    vitruvian_gojson::marshal_indent_string(v).expect(
        "no caller marshals a float; vitruvian_gojson rejects floats, see packages/gocompat/gojson/README.md",
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decode_fills_defaults() {
        let u = decode_unit(
            br#"{"schema": 1, "name": "vitruvian-tabs-api", "package": "apps/suites/vitruvian-tabs/api",
                "test_targets": [":integration_tests"], "persona": "backend"}"#,
        )
        .unwrap();
        assert_eq!(u.concurrency_group, "pipeline-vitruvian-tabs-api");
        assert_eq!(u.timeout_minutes, 30);
        assert_eq!(u.runner, "ubuntu-26.04");
        assert_eq!(u.tier, "L1");
    }

    #[test]
    fn decode_errors_match_go() {
        let cases: &[(&str, &str)] = &[
            (r#"{"schema": 2, "name": "foo", "test_targets": [":t"]}"#,
             "unit \"foo\": unsupported schema version 2 (expected 1)"),
            (r#"{"schema": 1, "name": " ", "test_targets": [":t"]}"#, "unit name must not be empty"),
            (r#"{"schema": 1, "name": "foo", "test_targets": []}"#, "unit \"foo\" has no test targets"),
            (r#"{"schema":"x"}"#,
             "decode unit json: json: cannot unmarshal string into Go struct field Unit.schema of type int"),
            (r#"{"schema":1.5}"#,
             "decode unit json: json: cannot unmarshal number 1.5 into Go struct field Unit.schema of type int"),
            (r#"{"schema":1,"name":"a","test_targets":["x"],"env":{"a":1}}"#,
             "decode unit json: json: cannot unmarshal number into Go struct field Unit.env of type string"),
            (r#"{"schema":1,"name":"a","test_targets":["x"],"env":123}"#,
             "decode unit json: json: cannot unmarshal number into Go struct field Unit.env of type map[string]string"),
            ("[]", "decode unit json: json: cannot unmarshal array into Go value of type main.Unit"),
            ("null", "unit \"\": unsupported schema version 0 (expected 1)"),
        ];
        for (input, want) in cases {
            assert_eq!(
                decode_unit(input.as_bytes()).unwrap_err(),
                *want,
                "input {input}"
            );
        }
    }

    #[test]
    fn keys_fold_and_maps_merge() {
        let u = decode_unit(
            "{\"\u{17f}chema\":1,\"NAME\":\"a\",\"t\u{0131}er\":\"L2\",\"test_targets\":[\"x\",\"y\"],\"test_targets\":[null],\
             \"artifacts\":{\"x\":\"y\"},\"artifacts\":{\"z\":\"w\",\"x\":null},\
             \"env\":{\"k\":\"v\"},\"env\":null}"
                .as_bytes(),
        )
        .unwrap();
        assert_eq!(u.name, "a");
        // Turkish dotless 'ı' (U+0131) does not SimpleFold to 'i', matching Go.
        assert_eq!(u.tier, "L1");
        // The second test_targets reuses the first's backing array.
        assert_eq!(u.test_targets, Some(vec!["x".to_string()]));
        assert_eq!(u.artifacts.get("x").map(String::as_str), Some(""));
        assert_eq!(u.artifacts.get("z").map(String::as_str), Some("w"));
        assert!(u.env.is_empty());
    }

    #[test]
    fn json_escapes_like_go() {
        assert_eq!(
            marshal_indent(&"<&>\u{2028}\u{2029}"),
            "\"\\u003c\\u0026\\u003e\\u2028\\u2029\""
        );
    }
}
