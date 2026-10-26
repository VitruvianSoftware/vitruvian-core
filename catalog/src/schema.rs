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

//! `jsonschema.Draft202012Validator(schema).iter_errors(instance)`, for the
//! keywords a schema like catalog.schema.json uses, with jsonschema 4.26's
//! messages (which quote the instance with Python's repr) and its order:
//! each schema's keywords in the order the schema writes them, `$ref`
//! among them.

use crate::json::Value;
use crate::{py, pyre};

#[derive(Clone, Debug, PartialEq)]
pub enum Step {
    Key(String),
    Index(usize),
}

#[derive(Clone, Debug, PartialEq)]
pub struct Error {
    /// Where in the instance (jsonschema's `error.path`).
    pub path: Vec<Step>,
    pub message: String,
}

impl Error {
    /// `'/'.join(map(str, e.path))`.
    pub fn path_text(&self) -> String {
        self.path
            .iter()
            .map(|s| match s {
                Step::Key(k) => k.clone(),
                Step::Index(i) => i.to_string(),
            })
            .collect::<Vec<_>>()
            .join("/")
    }
}

fn add(out: &mut Vec<Error>, path: &[Step], message: String) {
    out.push(Error {
        path: path.to_vec(),
        message,
    });
}

pub struct Validator<'a> {
    root: &'a Value,
}

fn is_type(v: &Value, t: &str) -> bool {
    match t {
        "object" => matches!(v, Value::Dict(_)),
        "array" => matches!(v, Value::List(_)),
        "string" => matches!(v, Value::Str(_)),
        "boolean" => matches!(v, Value::Bool(_)),
        "null" => matches!(v, Value::Null),
        "number" => matches!(v, Value::Int(_) | Value::Float(_)),
        "integer" => match v {
            Value::Int(_) => true,
            Value::Float(f) => f.is_finite() && f.fract() == 0.0,
            _ => false,
        },
        _ => false,
    }
}

/// jsonschema's `equal`: like ==, except that True is not 1 and False is
/// not 0, at any depth.
fn equal(a: &Value, b: &Value) -> bool {
    match (a, b) {
        (Value::Bool(x), Value::Bool(y)) => x == y,
        (Value::Bool(_), _) | (_, Value::Bool(_)) => false,
        (Value::List(x), Value::List(y)) => {
            x.len() == y.len() && x.iter().zip(y).all(|(p, q)| equal(p, q))
        }
        (Value::Dict(x), Value::Dict(y)) => {
            x.len() == y.len()
                && x.iter()
                    .all(|(k, v)| match y.iter().find(|(yk, _)| yk == k) {
                        Some((_, w)) => equal(v, w),
                        None => false,
                    })
        }
        _ => py::eq(a, b),
    }
}

fn as_f64(v: &Value) -> Option<f64> {
    match v {
        Value::Int(s) => Some(*s as f64),
        Value::Float(f) => Some(*f),
        _ => None,
    }
}

fn len_limit(v: &Value) -> Option<usize> {
    as_f64(v).map(|f| if f < 0.0 { 0 } else { f as usize })
}

impl<'a> Validator<'a> {
    pub fn new(root: &'a Value) -> Validator<'a> {
        Validator { root }
    }

    /// Every error, in jsonschema's order.
    pub fn iter_errors(&self, instance: &Value) -> Vec<Error> {
        let mut out = Vec::new();
        self.descend(instance, self.root, &mut Vec::new(), &mut out);
        out
    }

    fn resolve(&self, reference: &str) -> Option<&'a Value> {
        let pointer = reference.strip_prefix('#')?;
        let mut at = self.root;
        for part in pointer.split('/').skip(1) {
            let part = part.replace("~1", "/").replace("~0", "~");
            at = match at {
                Value::Dict(_) => at.field(&part)?,
                Value::List(items) => items.get(part.parse::<usize>().ok()?)?,
                _ => return None,
            };
        }
        Some(at)
    }

    fn valid(&self, instance: &Value, schema: &Value) -> bool {
        let mut out = Vec::new();
        self.descend(instance, schema, &mut Vec::new(), &mut out);
        out.is_empty()
    }

    fn descend(
        &self,
        instance: &Value,
        schema: &Value,
        path: &mut Vec<Step>,
        out: &mut Vec<Error>,
    ) {
        let items = match schema {
            Value::Bool(true) => return,
            Value::Bool(false) => {
                out.push(Error {
                    path: path.clone(),
                    message: format!("False schema does not allow {}", instance.py_repr()),
                });
                return;
            }
            Value::Dict(items) => items,
            _ => return,
        };
        for (keyword, value) in items {
            match keyword.as_str() {
                "$ref" => {
                    if let Value::Str(r) = value {
                        if let Some(target) = self.resolve(r) {
                            let mut sub = path.clone();
                            self.descend(instance, target, &mut sub, out);
                        }
                    }
                }
                "type" => {
                    let types: Vec<String> = match value {
                        Value::Str(t) => vec![t.clone()],
                        Value::List(ts) => ts.iter().map(|t| t.py_str()).collect(),
                        _ => vec![],
                    };
                    if !types.iter().any(|t| is_type(instance, t)) {
                        let reprs: Vec<String> =
                            types.iter().map(|t| crate::pystr::repr_str(t)).collect();
                        add(
                            out,
                            path,
                            format!("{} is not of type {}", instance.py_repr(), reprs.join(", ")),
                        );
                    }
                }
                "const" => {
                    if !equal(instance, value) {
                        add(out, path, format!("{} was expected", value.py_repr()));
                    }
                }
                "enum" => {
                    let options = match value {
                        Value::List(o) => o.clone(),
                        _ => vec![],
                    };
                    if options.iter().all(|o| !equal(o, instance)) {
                        add(
                            out,
                            path,
                            format!("{} is not one of {}", instance.py_repr(), value.py_repr()),
                        );
                    }
                }
                "required" => {
                    if let (Value::Dict(_), Value::List(names)) = (instance, value) {
                        for name in names {
                            if let Value::Str(n) = name {
                                if instance.field(n).is_none() {
                                    add(
                                        out,
                                        path,
                                        format!("{} is a required property", name.py_repr()),
                                    );
                                }
                            }
                        }
                    }
                }
                "properties" => {
                    if let (Value::Dict(_), Value::Dict(props)) = (instance, value) {
                        for (name, sub) in props {
                            if let Some(v) = instance.field(name) {
                                path.push(Step::Key(name.clone()));
                                self.descend(v, sub, path, out);
                                path.pop();
                            }
                        }
                    }
                }
                "patternProperties" => {
                    if let (Value::Dict(fields), Value::Dict(patterns)) = (instance, value) {
                        for (pattern, sub) in patterns {
                            let re = match pyre::compile(pattern) {
                                Ok(r) => r,
                                Err(_) => continue,
                            };
                            for (k, v) in fields {
                                if re.search(k).is_some() {
                                    path.push(Step::Key(k.clone()));
                                    self.descend(v, sub, path, out);
                                    path.pop();
                                }
                            }
                        }
                    }
                }
                "additionalProperties" => {
                    if let Value::Dict(fields) = instance {
                        let extras = self.additional(&fields.0, &items.0);
                        match value {
                            Value::Dict(_) => {
                                for k in &extras {
                                    path.push(Step::Key(k.clone()));
                                    self.descend(instance.field(k).unwrap(), value, path, out);
                                    path.pop();
                                }
                            }
                            Value::Bool(false) if !extras.is_empty() => {
                                let mut sorted = extras.clone();
                                sorted.sort();
                                let reprs: Vec<String> =
                                    sorted.iter().map(|k| crate::pystr::repr_str(k)).collect();
                                let message = if items.iter().any(|(k, _)| k == "patternProperties")
                                {
                                    let mut pats: Vec<String> =
                                        match schema.field("patternProperties") {
                                            Some(Value::Dict(p)) => {
                                                p.iter().map(|(k, _)| k.clone()).collect()
                                            }
                                            _ => vec![],
                                        };
                                    pats.sort();
                                    let pats: Vec<String> =
                                        pats.iter().map(|k| crate::pystr::repr_str(k)).collect();
                                    format!(
                                        "{} {} not match any of the regexes: {}",
                                        reprs.join(", "),
                                        if sorted.len() == 1 { "does" } else { "do" },
                                        pats.join(", ")
                                    )
                                } else {
                                    format!(
                                        "Additional properties are not allowed ({} {} unexpected)",
                                        reprs.join(", "),
                                        if sorted.len() == 1 { "was" } else { "were" }
                                    )
                                };
                                add(out, path, message);
                            }
                            _ => {}
                        }
                    }
                }
                "propertyNames" => {
                    if let Value::Dict(fields) = instance {
                        for (k, _) in fields {
                            self.descend(&Value::Str(k.clone()), value, path, out);
                        }
                    }
                }
                "items" => {
                    if let Value::List(elements) = instance {
                        let prefix = match schema.field("prefixItems") {
                            Some(Value::List(p)) => p.len(),
                            _ => 0,
                        };
                        if value == &Value::Bool(false) && elements.len() > prefix {
                            let extra = elements.len() - prefix;
                            let rest = if extra == 1 {
                                elements[prefix].clone()
                            } else {
                                Value::List(elements[prefix..].to_vec())
                            };
                            add(
                                out,
                                path,
                                format!(
                                    "Expected at most {} {} but found {} extra: {}",
                                    prefix,
                                    if prefix == 1 { "item" } else { "items" },
                                    extra,
                                    rest.py_repr()
                                ),
                            );
                        } else {
                            for (i, e) in elements.iter().enumerate().skip(prefix) {
                                path.push(Step::Index(i));
                                self.descend(e, value, path, out);
                                path.pop();
                            }
                        }
                    }
                }
                "prefixItems" => {
                    if let (Value::List(elements), Value::List(subs)) = (instance, value) {
                        for (i, (e, sub)) in elements.iter().zip(subs).enumerate() {
                            path.push(Step::Index(i));
                            self.descend(e, sub, path, out);
                            path.pop();
                        }
                    }
                }
                "pattern" => {
                    if let (Value::Str(s), Value::Str(p)) = (instance, value) {
                        if let Ok(re) = pyre::compile(p) {
                            if re.search(s).is_none() {
                                add(
                                    out,
                                    path,
                                    format!(
                                        "{} does not match {}",
                                        instance.py_repr(),
                                        value.py_repr()
                                    ),
                                );
                            }
                        }
                    }
                }
                "minLength" | "maxLength" => {
                    if let (Value::Str(s), Some(limit)) = (instance, len_limit(value)) {
                        let n = s.chars().count();
                        if keyword == "minLength" && n < limit {
                            let words = if limit == 1 {
                                "should be non-empty"
                            } else {
                                "is too short"
                            };
                            add(out, path, format!("{} {}", instance.py_repr(), words));
                        }
                        if keyword == "maxLength" && n > limit {
                            let words = if limit == 0 {
                                "is expected to be empty"
                            } else {
                                "is too long"
                            };
                            add(out, path, format!("{} {}", instance.py_repr(), words));
                        }
                    }
                }
                "minItems" | "maxItems" => {
                    if let (Value::List(a), Some(limit)) = (instance, len_limit(value)) {
                        if keyword == "minItems" && a.len() < limit {
                            let words = if limit == 1 {
                                "should be non-empty"
                            } else {
                                "is too short"
                            };
                            add(out, path, format!("{} {}", instance.py_repr(), words));
                        }
                        if keyword == "maxItems" && a.len() > limit {
                            let words = if limit == 0 {
                                "is expected to be empty"
                            } else {
                                "is too long"
                            };
                            add(out, path, format!("{} {}", instance.py_repr(), words));
                        }
                    }
                }
                "minProperties" | "maxProperties" => {
                    if let (Value::Dict(o), Some(limit)) = (instance, len_limit(value)) {
                        if keyword == "minProperties" && o.len() < limit {
                            let words = if limit == 1 {
                                "should be non-empty"
                            } else {
                                "does not have enough properties"
                            };
                            add(out, path, format!("{} {}", instance.py_repr(), words));
                        }
                        if keyword == "maxProperties" && o.len() > limit {
                            let words = if limit == 0 {
                                "is expected to be empty"
                            } else {
                                "has too many properties"
                            };
                            add(out, path, format!("{} {}", instance.py_repr(), words));
                        }
                    }
                }
                "uniqueItems" => {
                    if let Value::List(a) = instance {
                        if value.truthy() && !unique(a) {
                            add(
                                out,
                                path,
                                format!("{} has non-unique elements", instance.py_repr()),
                            );
                        }
                    }
                }
                "minimum" | "maximum" | "exclusiveMinimum" | "exclusiveMaximum" => {
                    if is_type(instance, "number") {
                        if let (Some(x), Some(m)) = (as_f64(instance), as_f64(value)) {
                            let (bad, words) = match keyword.as_str() {
                                "minimum" => (x < m, "is less than the minimum of"),
                                "maximum" => (x > m, "is greater than the maximum of"),
                                "exclusiveMinimum" => {
                                    (x <= m, "is less than or equal to the minimum of")
                                }
                                _ => (x >= m, "is greater than or equal to the maximum of"),
                            };
                            if bad {
                                add(
                                    out,
                                    path,
                                    format!("{} {} {}", instance.py_repr(), words, value.py_repr()),
                                );
                            }
                        }
                    }
                }
                "allOf" => {
                    if let Value::List(subs) = value {
                        for sub in subs {
                            self.descend(instance, sub, path, out);
                        }
                    }
                }
                "anyOf" => {
                    if let Value::List(subs) = value {
                        if !subs.iter().any(|s| self.valid(instance, s)) {
                            add(
                                out,
                                path,
                                format!(
                                    "{} is not valid under any of the given schemas",
                                    instance.py_repr()
                                ),
                            );
                        }
                    }
                }
                "oneOf" => {
                    if let Value::List(subs) = value {
                        let good: Vec<&Value> =
                            subs.iter().filter(|s| self.valid(instance, s)).collect();
                        if good.is_empty() {
                            add(
                                out,
                                path,
                                format!(
                                    "{} is not valid under any of the given schemas",
                                    instance.py_repr()
                                ),
                            );
                        } else if good.len() > 1 {
                            let reprs: Vec<String> = good.iter().map(|g| g.py_repr()).collect();
                            add(
                                out,
                                path,
                                format!(
                                    "{} is valid under each of {}",
                                    instance.py_repr(),
                                    reprs.join(", ")
                                ),
                            );
                        }
                    }
                }
                "not" => {
                    if self.valid(instance, value) {
                        add(
                            out,
                            path,
                            format!(
                                "{} should not be valid under {}",
                                instance.py_repr(),
                                value.py_repr()
                            ),
                        );
                    }
                }
                "if" => {
                    let branch = if self.valid(instance, value) {
                        "then"
                    } else {
                        "else"
                    };
                    if let Some(sub) = schema.field(branch) {
                        self.descend(instance, sub, path, out);
                    }
                }
                "dependentRequired" => {
                    if let (Value::Dict(_), Value::Dict(deps)) = (instance, value) {
                        for (prop, needs) in deps {
                            if instance.field(prop).is_none() {
                                continue;
                            }
                            if let Value::List(needs) = needs {
                                for each in needs {
                                    if let Value::Str(n) = each {
                                        if instance.field(n).is_none() {
                                            add(
                                                out,
                                                path,
                                                format!(
                                                    "{} is a dependency of {}",
                                                    each.py_repr(),
                                                    crate::pystr::repr_str(prop)
                                                ),
                                            );
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                _ => {}
            }
        }
    }

    /// jsonschema's `find_additional_properties`.
    fn additional(&self, fields: &[(String, Value)], schema: &[(String, Value)]) -> Vec<String> {
        let props = schema
            .iter()
            .find(|(k, _)| k == "properties")
            .map(|(_, v)| v);
        let patterns: Vec<pyre::Regex> = match schema.iter().find(|(k, _)| k == "patternProperties")
        {
            Some((_, Value::Dict(p))) => p
                .iter()
                .filter_map(|(k, _)| pyre::compile(k).ok())
                .collect(),
            _ => vec![],
        };
        fields
            .iter()
            .filter(|(k, _)| {
                let listed =
                    matches!(props, Some(Value::Dict(_)) if props.unwrap().field(k).is_some());
                !listed && !patterns.iter().any(|re| re.search(k).is_some())
            })
            .map(|(k, _)| k.clone())
            .collect()
    }
}

/// jsonschema's `uniq`.
fn unique(items: &[Value]) -> bool {
    for (i, a) in items.iter().enumerate() {
        if items[i + 1..].iter().any(|b| equal(a, b)) {
            return false;
        }
    }
    true
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::json::loads;

    fn errors(schema: &str, instance: &str) -> Vec<String> {
        let schema = loads(schema).unwrap();
        Validator::new(&schema)
            .iter_errors(&loads(instance).unwrap())
            .iter()
            .map(|e| format!("{}: {}", e.path_text(), e.message))
            .collect()
    }

    #[test]
    fn messages_are_jsonschemas() {
        let schema = r##"{"type": "object", "required": ["a", "b"], "additionalProperties": false,
            "properties": {"a": {"$ref": "#/$defs/v"}, "n": {"type": "integer", "minimum": 1},
            "u": {"type": "array", "uniqueItems": true, "maxItems": 2, "items": {"enum": ["x", "y"]}}},
            "$defs": {"v": {"type": "string", "pattern": "^[0-9]+$", "maxLength": 3}}}"##;
        assert_eq!(
            errors(
                schema,
                r#"{"a": "12345", "n": 0, "u": ["x", "x", "z"], "q": 1}"#
            ),
            vec![
                ": 'b' is a required property",
                ": Additional properties are not allowed ('q' was unexpected)",
                "a: '12345' is too long",
                "n: 0 is less than the minimum of 1",
                "u: ['x', 'x', 'z'] has non-unique elements",
                "u: ['x', 'x', 'z'] is too long",
                "u/2: 'z' is not one of ['x', 'y']",
            ]
        );
        assert_eq!(
            errors(schema, r#"{"a": "x1", "b": 1, "n": 1.0}"#),
            vec![
                ": Additional properties are not allowed ('b' was unexpected)",
                "a: 'x1' does not match '^[0-9]+$'",
            ]
        );
        assert_eq!(errors(r#"{"const": 1}"#, "true"), vec![": 1 was expected"]);
        assert_eq!(
            errors(r#"{"type": "integer"}"#, "true"),
            vec![": True is not of type 'integer'"]
        );
    }
}
