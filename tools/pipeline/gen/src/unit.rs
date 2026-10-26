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

use crate::gojson::{fold_name, Json};
use crate::gostr;

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

/// A Go slice under decoding: its backing array outlives a shorter
/// re-decode, which a duplicate key can expose (`null` elements keep the
/// old value). `None` is nil.
#[derive(Default)]
struct GoSlice {
    backing: Vec<String>,
    len: usize,
    nil: bool,
}

impl GoSlice {
    fn nil() -> Self {
        GoSlice {
            nil: true,
            ..Default::default()
        }
    }
    fn get(&self) -> Option<Vec<String>> {
        if self.nil {
            None
        } else {
            Some(self.backing[..self.len].to_vec())
        }
    }
}

struct Decoder {
    err: Option<String>,
}

#[derive(Clone, Copy)]
enum Field {
    Schema,
    Name,
    Package,
    TestTargets,
    Tier,
    Runner,
    Persona,
    ConcurrencyGroup,
    TimeoutMinutes,
    Env,
    DependsOn,
    NeedsEmulator,
    Artifacts,
    BuildFlags,
    Tags,
}

const FIELDS: &[(&str, Field)] = &[
    ("schema", Field::Schema),
    ("name", Field::Name),
    ("package", Field::Package),
    ("test_targets", Field::TestTargets),
    ("tier", Field::Tier),
    ("runner", Field::Runner),
    ("persona", Field::Persona),
    ("concurrency_group", Field::ConcurrencyGroup),
    ("timeout_minutes", Field::TimeoutMinutes),
    ("env", Field::Env),
    ("depends_on", Field::DependsOn),
    ("needs_emulator", Field::NeedsEmulator),
    ("artifacts", Field::Artifacts),
    ("build_flags", Field::BuildFlags),
    ("tags", Field::Tags),
];

impl Decoder {
    fn type_error(&mut self, value: &str, field: &str, ty: &str) {
        if self.err.is_none() {
            self.err = Some(format!(
                "json: cannot unmarshal {value} into Go struct field Unit.{field} of type {ty}"
            ));
        }
    }

    fn string(&mut self, dst: &mut String, v: &Json, field: &str) {
        match v {
            Json::Str(s) => *dst = s.clone(),
            Json::Null => {}
            other => self.type_error(other.kind(), field, "string"),
        }
    }

    fn int(&mut self, dst: &mut i64, v: &Json, field: &str) {
        match v {
            Json::Num(s) => match s.parse::<i64>() {
                Ok(n) if !s.starts_with('+') => *dst = n,
                _ => self.type_error(&format!("number {s}"), field, "int"),
            },
            Json::Null => {}
            other => self.type_error(other.kind(), field, "int"),
        }
    }

    fn boolean(&mut self, dst: &mut bool, v: &Json, field: &str) {
        match v {
            Json::Bool(b) => *dst = *b,
            Json::Null => {}
            other => self.type_error(other.kind(), field, "bool"),
        }
    }

    fn slice(&mut self, dst: &mut GoSlice, v: &Json, field: &str) {
        match v {
            Json::Arr(items) => {
                dst.nil = false;
                for (i, item) in items.iter().enumerate() {
                    if i >= dst.backing.len() {
                        dst.backing.push(String::new());
                    }
                    let mut slot = std::mem::take(&mut dst.backing[i]);
                    self.string(&mut slot, item, field);
                    dst.backing[i] = slot;
                }
                if items.is_empty() {
                    // Go sets a fresh empty slice: the old backing is gone.
                    dst.backing.clear();
                }
                dst.len = items.len();
            }
            Json::Null => *dst = GoSlice::nil(),
            other => self.type_error(other.kind(), field, "[]string"),
        }
    }

    fn map(&mut self, dst: &mut Option<BTreeMap<String, String>>, v: &Json, field: &str) {
        match v {
            Json::Obj(kv) => {
                let m = dst.get_or_insert_with(BTreeMap::new);
                for (k, val) in kv {
                    let mut s = String::new();
                    self.string(&mut s, val, field);
                    m.insert(k.clone(), s);
                }
            }
            Json::Null => *dst = None,
            other => self.type_error(other.kind(), field, "map[string]string"),
        }
    }
}

/// Go's `json.Unmarshal(b, &u)` into the generator's Unit struct.
fn unmarshal_unit(b: &[u8]) -> Result<Unit, String> {
    let j = crate::gojson::parse(b)?;
    let mut u = Unit::default();
    let pairs = match j {
        Json::Null => return Ok(u),
        Json::Obj(kv) => kv,
        other => {
            return Err(format!(
                "json: cannot unmarshal {} into Go value of type main.Unit",
                other.kind()
            ))
        }
    };
    let mut d = Decoder { err: None };
    let mut targets = GoSlice::nil();
    let mut depends = GoSlice::nil();
    let mut flags = GoSlice::nil();
    let mut tags = GoSlice::nil();
    let mut env: Option<BTreeMap<String, String>> = None;
    let mut artifacts: Option<BTreeMap<String, String>> = None;
    for (key, v) in &pairs {
        let field = FIELDS.iter().find(|(n, _)| n == key).or_else(|| {
            let folded = fold_name(key);
            FIELDS.iter().find(|(n, _)| fold_name(n) == folded)
        });
        let Some((name, f)) = field else { continue };
        match f {
            Field::Schema => d.int(&mut u.schema, v, name),
            Field::Name => d.string(&mut u.name, v, name),
            Field::Package => d.string(&mut u.package, v, name),
            Field::TestTargets => d.slice(&mut targets, v, name),
            Field::Tier => d.string(&mut u.tier, v, name),
            Field::Runner => d.string(&mut u.runner, v, name),
            Field::Persona => d.string(&mut u.persona, v, name),
            Field::ConcurrencyGroup => d.string(&mut u.concurrency_group, v, name),
            Field::TimeoutMinutes => d.int(&mut u.timeout_minutes, v, name),
            Field::Env => d.map(&mut env, v, name),
            Field::DependsOn => d.slice(&mut depends, v, name),
            Field::NeedsEmulator => d.boolean(&mut u.needs_emulator, v, name),
            Field::Artifacts => d.map(&mut artifacts, v, name),
            Field::BuildFlags => d.slice(&mut flags, v, name),
            Field::Tags => d.slice(&mut tags, v, name),
        }
    }
    if let Some(e) = d.err {
        return Err(e);
    }
    u.test_targets = targets.get();
    u.depends_on = depends.get().unwrap_or_default();
    u.build_flags = flags.get().unwrap_or_default();
    u.tags = tags.get().unwrap_or_default();
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

/// Go's JSON escaping on top of serde_json's: `<`, `>`, `&`, U+2028 and
/// U+2029 are written as `\u` escapes. In serialised JSON these can only
/// occur inside strings, so a textual pass is exact.
pub fn go_html_escape(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '<' => out.push_str("\\u003c"),
            '>' => out.push_str("\\u003e"),
            '&' => out.push_str("\\u0026"),
            '\u{2028}' => out.push_str("\\u2028"),
            '\u{2029}' => out.push_str("\\u2029"),
            c => out.push(c),
        }
    }
    out
}

/// Go's `json.MarshalIndent(v, "", "  ")`.
pub fn marshal_indent<T: Serialize>(v: &T) -> String {
    let s = serde_json::to_string_pretty(v).expect("serialising plain data cannot fail");
    go_html_escape(&s)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decode_fills_defaults() {
        let u = decode_unit(
            br#"{"schema": 1, "name": "tabula-api", "package": "tabula/api",
                "test_targets": [":integration_tests"], "persona": "backend"}"#,
        )
        .unwrap();
        assert_eq!(u.concurrency_group, "pipeline-tabula-api");
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
            "{\"\u{17f}chema\":1,\"NAME\":\"a\",\"test_targets\":[\"x\",\"y\"],\"test_targets\":[null],\
             \"artifacts\":{\"x\":\"y\"},\"artifacts\":{\"z\":\"w\"}}"
                .as_bytes(),
        )
        .unwrap();
        assert_eq!(u.name, "a");
        // The second test_targets reuses the first's backing array.
        assert_eq!(u.test_targets, Some(vec!["x".to_string()]));
        assert_eq!(u.artifacts.len(), 2);
    }

    #[test]
    fn json_escapes_like_go() {
        assert_eq!(
            go_html_escape("\"<&>\u{2028}\""),
            "\"\\u003c\\u0026\\u003e\\u2028\""
        );
    }
}
