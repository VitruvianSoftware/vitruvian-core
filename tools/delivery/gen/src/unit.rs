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

//! One delivery() declaration, decoded from the JSON the macro writes
//! (tools/delivery/defs.bzl), with encoding/json's struct-decoding rules: an
//! exact key match first, then a case-insensitive one; unknown keys ignored;
//! `null` leaving a scalar field alone; the FIRST type error reported once the
//! whole value has been walked.
//!
//! Like the Go struct, this is deliberately not shared with
//! //tools/delivery/orchestrate: both decode the versioned on-disk contract
//! independently, so a macro change only one of them learned shows up as a
//! disagreement rather than a silent no-op.

use std::collections::BTreeMap;

use crate::gojson::{self, J};
use crate::gostd::{self, Value};

pub const SCHEMA_VERSION: i64 = 1;

#[derive(Clone, Debug, Default, PartialEq)]
pub struct Unit {
    pub schema: i64,
    pub name: String,
    pub kind: String,
    pub run: String,
    pub build: String,
    pub app: String,
    pub build_context: String,
    pub image_repository_path: String,
    pub shared_build: String,
    pub image_digest_output: String,
    pub environments: Vec<String>,
    pub github_environment: String,
    pub promotion: String,
    pub soak: bool,
    pub render: String,
    pub legacy_workflow: String,
    pub legacy_job: String,
    pub gate_var: String,
    pub companions: Vec<String>,
    pub extra_paths: Vec<String>,
    pub exclude_paths: Vec<String>,
    pub graph_targets: Vec<String>,
    pub preflight: String,
    pub package: String,
    pub workflow_inputs: BTreeMap<String, Value>,
    pub changelog_inputs: BTreeMap<String, Value>,
}

#[derive(Clone, Copy)]
enum FieldKind {
    Int,
    Str,
    Bool,
    StrSlice,
    AnyMap,
}

/// The struct's fields in declaration order, as `json:"..."` tags name them.
const FIELDS: &[(&str, FieldKind)] = &[
    ("schema", FieldKind::Int),
    ("name", FieldKind::Str),
    ("kind", FieldKind::Str),
    ("run", FieldKind::Str),
    ("build", FieldKind::Str),
    ("app", FieldKind::Str),
    ("build_context", FieldKind::Str),
    ("image_repository_path", FieldKind::Str),
    ("shared_build", FieldKind::Str),
    ("image_digest_output", FieldKind::Str),
    ("environments", FieldKind::StrSlice),
    ("github_environment", FieldKind::Str),
    ("promotion", FieldKind::Str),
    ("soak", FieldKind::Bool),
    ("render", FieldKind::Str),
    ("legacy_workflow", FieldKind::Str),
    ("legacy_job", FieldKind::Str),
    ("gate_var", FieldKind::Str),
    ("companions", FieldKind::StrSlice),
    ("extra_paths", FieldKind::StrSlice),
    ("exclude_paths", FieldKind::StrSlice),
    ("graph_targets", FieldKind::StrSlice),
    ("preflight", FieldKind::Str),
    ("package", FieldKind::Str),
    ("workflow_inputs", FieldKind::AnyMap),
    ("changelog_inputs", FieldKind::AnyMap),
];

struct Errs(Option<String>);

impl Errs {
    fn save(&mut self, value: &str, field: &str, ty: &str) {
        if self.0.is_none() {
            self.0 = Some(format!(
                "json: cannot unmarshal {} into Go struct field unit.{} of type {}",
                value, field, ty
            ));
        }
    }
}

impl Unit {
    fn str_field(&mut self, name: &str) -> &mut String {
        match name {
            "name" => &mut self.name,
            "kind" => &mut self.kind,
            "run" => &mut self.run,
            "build" => &mut self.build,
            "app" => &mut self.app,
            "build_context" => &mut self.build_context,
            "image_repository_path" => &mut self.image_repository_path,
            "shared_build" => &mut self.shared_build,
            "image_digest_output" => &mut self.image_digest_output,
            "github_environment" => &mut self.github_environment,
            "promotion" => &mut self.promotion,
            "render" => &mut self.render,
            "legacy_workflow" => &mut self.legacy_workflow,
            "legacy_job" => &mut self.legacy_job,
            "gate_var" => &mut self.gate_var,
            "preflight" => &mut self.preflight,
            "package" => &mut self.package,
            _ => unreachable!("{}", name),
        }
    }

    fn slice_field(&mut self, name: &str) -> &mut Vec<String> {
        match name {
            "environments" => &mut self.environments,
            "companions" => &mut self.companions,
            "extra_paths" => &mut self.extra_paths,
            "exclude_paths" => &mut self.exclude_paths,
            "graph_targets" => &mut self.graph_targets,
            _ => unreachable!("{}", name),
        }
    }

    fn map_field(&mut self, name: &str) -> &mut BTreeMap<String, Value> {
        match name {
            "workflow_inputs" => &mut self.workflow_inputs,
            "changelog_inputs" => &mut self.changelog_inputs,
            _ => unreachable!("{}", name),
        }
    }
}

/// decode into an interface{} (valueInterface).
fn to_value(j: &J, field: &str, errs: &mut Errs) -> Value {
    match j {
        J::Null => Value::Null,
        J::Bool(b) => Value::Bool(*b),
        J::Num(s) => {
            let f: f64 = s.parse().unwrap_or(f64::INFINITY);
            if f.is_infinite() {
                errs.save(&format!("number {}", s), field, "float64");
                return Value::Null;
            }
            Value::Num(f)
        }
        J::Str(s) => Value::Str(s.clone()),
        J::Arr(a) => Value::Arr(a.iter().map(|v| to_value(v, field, errs)).collect()),
        J::Obj(kv) => {
            let mut m = BTreeMap::new();
            for (k, v) in kv {
                let v = to_value(v, field, errs);
                m.insert(k.clone(), v);
            }
            Value::Obj(m)
        }
    }
}

fn decode_string_into(j: &J, dst: &mut String, field: &str, ty: &str, errs: &mut Errs) {
    match j {
        J::Str(s) => *dst = s.clone(),
        J::Null => {}
        other => errs.save(&gojson::kind_word(other), field, ty),
    }
}

fn assign(u: &mut Unit, field: &'static str, kind: FieldKind, j: &J, errs: &mut Errs) {
    match kind {
        FieldKind::Int => match j {
            J::Num(s) => match s.parse::<i64>() {
                Ok(n) if !s.starts_with('+') => u.schema = n,
                _ => errs.save(&format!("number {}", s), field, "int"),
            },
            J::Null => {}
            other => errs.save(&gojson::kind_word(other), field, "int"),
        },
        FieldKind::Str => decode_string_into(j, u.str_field(field), field, "string", errs),
        FieldKind::Bool => match j {
            J::Bool(b) => u.soak = *b,
            J::Null => {}
            other => errs.save(&gojson::kind_word(other), field, "bool"),
        },
        FieldKind::StrSlice => match j {
            J::Null => u.slice_field(field).clear(),
            J::Arr(items) => {
                // Go decodes INTO the existing slice: element i starts as the
                // old element i (a `null` element leaves it), and the slice is
                // then cut to the new length.
                let old = std::mem::take(u.slice_field(field));
                let mut out = Vec::with_capacity(items.len());
                for (i, item) in items.iter().enumerate() {
                    let mut s = old.get(i).cloned().unwrap_or_default();
                    decode_string_into(item, &mut s, field, "string", errs);
                    out.push(s);
                }
                *u.slice_field(field) = out;
            }
            other => errs.save(&gojson::kind_word(other), field, "[]string"),
        },
        FieldKind::AnyMap => match j {
            J::Null => u.map_field(field).clear(),
            J::Obj(kv) => {
                // An existing map is reused, not replaced: a key repeated in
                // the document merges into it.
                for (k, v) in kv {
                    let v = to_value(v, field, errs);
                    u.map_field(field).insert(k.clone(), v);
                }
            }
            other => errs.save(&gojson::kind_word(other), field, "map[string]interface {}"),
        },
    }
}

/// json.Unmarshal(b, &u).
pub fn unmarshal(b: &[u8]) -> Result<Unit, String> {
    gojson::check_valid(b)?;
    let tree = gojson::parse(b);
    let mut u = Unit::default();
    let mut errs = Errs(None);
    match &tree {
        J::Obj(kv) => {
            for (key, val) in kv {
                let mut found = FIELDS.iter().find(|(n, _)| *n == key.as_str());
                if found.is_none() {
                    let folded = gojson::fold_name(key);
                    found = FIELDS
                        .iter()
                        .find(|(n, _)| n.to_ascii_uppercase() == folded);
                }
                if let Some((name, kind)) = found {
                    assign(&mut u, name, *kind, val, &mut errs);
                }
            }
        }
        J::Null => {}
        other => {
            return Err(format!(
                "json: cannot unmarshal {} into Go value of type main.unit",
                gojson::kind_word(other)
            ));
        }
    }
    match errs.0 {
        Some(e) => Err(e),
        None => Ok(u),
    }
}

/// decodeUnit: parse one *.delivery.json and check the invariants the
/// renderer relies on. Every failure is a hard error rather than a skip: a
/// unit that silently vanished is indistinguishable from one never declared
/// (#1794).
pub fn decode_unit(b: &[u8]) -> Result<Unit, String> {
    let u = unmarshal(b).map_err(|e| format!("decode: {}", e))?;
    if u.schema != SCHEMA_VERSION {
        return Err(format!(
            "unit {}: schema {}, this generator understands {} — regenerate after updating tools/delivery/gen for the new macro contract",
            gostd::q(&u.name),
            u.schema,
            SCHEMA_VERSION
        ));
    }
    if u.name.is_empty() {
        return Err("unit has no name".into());
    }
    if u.run.is_empty() {
        return Err(format!("unit {} has no run target", gostd::q(&u.name)));
    }
    if u.environments.is_empty() {
        return Err(format!(
            "unit {} has an empty environment ladder",
            gostd::q(&u.name)
        ));
    }
    Ok(u)
}

/// loadUnits: read, decode, sort by name, refuse duplicate names.
pub fn load_units(paths: &[String]) -> Result<Vec<Unit>, String> {
    let mut units = Vec::with_capacity(paths.len());
    for p in paths {
        let b = gostd::read_file(p).map_err(|(e, _)| format!("read {}: {}", p, e))?;
        let u = decode_unit(&b).map_err(|e| format!("{}: {}", p, e))?;
        units.push(u);
    }
    units.sort_by(|a, b| a.name.cmp(&b.name));
    for i in 1..units.len() {
        if units[i].name == units[i - 1].name {
            return Err(format!(
                "duplicate delivery unit name {} — unit names must be unique repo-wide",
                gostd::q(&units[i].name)
            ));
        }
    }
    Ok(units)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_drift() {
        for (json, want) in [
            (
                r#"{"schema":2,"name":"x","run":"//a:b","environments":["development"]}"#,
                "schema 2",
            ),
            (
                r#"{"schema":1,"run":"//a:b","environments":["development"]}"#,
                "no name",
            ),
            (
                r#"{"schema":1,"name":"x","environments":["development"]}"#,
                "no run target",
            ),
            (
                r#"{"schema":1,"name":"x","run":"//a:b"}"#,
                "empty environment ladder",
            ),
            ("{", "decode"),
        ] {
            let err = decode_unit(json.as_bytes()).unwrap_err();
            assert!(err.contains(want), "{} -> {}", json, err);
        }
    }

    #[test]
    fn type_errors_name_the_field() {
        assert_eq!(
            unmarshal(br#"{"schema":"1"}"#).unwrap_err(),
            "json: cannot unmarshal string into Go struct field unit.schema of type int"
        );
        assert_eq!(
            unmarshal(br#"{"schema":1.5}"#).unwrap_err(),
            "json: cannot unmarshal number 1.5 into Go struct field unit.schema of type int"
        );
        assert_eq!(
            unmarshal(br#"{"environments":["a",1]}"#).unwrap_err(),
            "json: cannot unmarshal number into Go struct field unit.environments of type string"
        );
        assert_eq!(
            unmarshal(b"[]").unwrap_err(),
            "json: cannot unmarshal array into Go value of type main.unit"
        );
        assert_eq!(
            unmarshal(br#"{"workflow_inputs":{"a":1e400}}"#).unwrap_err(),
            "json: cannot unmarshal number 1e400 into Go struct field unit.workflow_inputs of type float64"
        );
    }

    #[test]
    fn keys_match_case_insensitively_exact_first() {
        let u = unmarshal(
            "{\"NAME\":\"a\",\"name\":\"b\",\"Run\":\"r\",\"\u{212a}ind\":\"k\"}".as_bytes(),
        )
        .unwrap();
        assert_eq!(u.name, "b");
        assert_eq!(u.run, "r");
        assert_eq!(u.kind, "k");
    }
}
