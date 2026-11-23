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

use crate::json::{self, Value, ValueExt};
use crate::pyre;

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

type RefKey<'a> = (*const Value, &'a str);

pub struct Validator<'a> {
    root: &'a Value,
}

fn is_type(v: &Value, t: &str) -> bool {
    match t {
        "object" => matches!(v, Value::Obj(_)),
        "array" => matches!(v, Value::Arr(_)),
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
    json::schema_equal(a, b)
}

fn as_f64(v: &Value) -> Option<f64> {
    v.num_f64()
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
        self.descend(
            instance,
            self.root,
            &mut Vec::new(),
            &mut Vec::new(),
            &mut out,
        );
        out
    }

    fn resolve(&self, reference: &str) -> Option<&'a Value> {
        let pointer = reference.strip_prefix('#')?;
        let mut at = self.root;
        for part in pointer.split('/').skip(1) {
            let part = part.replace("~1", "/").replace("~0", "~");
            at = match at {
                Value::Obj(_) => at.field(&part)?,
                Value::Arr(items) => items.get(part.parse::<usize>().ok()?)?,
                _ => return None,
            };
        }
        Some(at)
    }

    fn valid(&self, instance: &Value, schema: &'a Value, active: &mut Vec<RefKey<'a>>) -> bool {
        let mut out = Vec::new();
        self.descend(instance, schema, &mut Vec::new(), active, &mut out);
        out.is_empty()
    }

    fn descend(
        &self,
        instance: &Value,
        schema: &'a Value,
        path: &mut Vec<Step>,
        active: &mut Vec<RefKey<'a>>,
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
            Value::Obj(items) => items,
            _ => return,
        };
        for (keyword, value) in items {
            match keyword.as_str() {
                "$ref" => {
                    if let Value::Str(r) = value {
                        if let Some(target) = self.resolve(r) {
                            let key = (instance as *const Value, r.as_str());
                            if active.contains(&key) {
                                add(
                                    out,
                                    path,
                                    format!("recursive $ref {} does not terminate", r),
                                );
                                return;
                            }
                            active.push(key);
                            let mut sub = path.clone();
                            self.descend(instance, target, &mut sub, active, out);
                            active.pop();
                        }
                    }
                }
                "type" => {
                    let types: Vec<String> = match value {
                        Value::Str(t) => vec![t.clone()],
                        Value::Arr(ts) => ts.iter().map(|t| t.py_str()).collect(),
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
                        Value::Arr(o) => o.clone(),
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
                    if let (Value::Obj(_), Value::Arr(names)) = (instance, value) {
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
                    if let (Value::Obj(_), Value::Obj(props)) = (instance, value) {
                        for (name, sub) in props {
                            if let Some(v) = instance.field(name) {
                                path.push(Step::Key(name.clone()));
                                self.descend(v, sub, path, active, out);
                                path.pop();
                            }
                        }
                    }
                }
                "patternProperties" => {
                    if let (Value::Obj(fields), Value::Obj(patterns)) = (instance, value) {
                        for (pattern, sub) in patterns {
                            let re = match pyre::compile(pattern) {
                                Ok(r) => r,
                                Err(_) => continue,
                            };
                            for (k, v) in fields {
                                if re.search(k).is_some() {
                                    path.push(Step::Key(k.clone()));
                                    self.descend(v, sub, path, active, out);
                                    path.pop();
                                }
                            }
                        }
                    }
                }
                "additionalProperties" => {
                    if let Value::Obj(fields) = instance {
                        let extras = self.additional(fields, items);
                        match value {
                            Value::Obj(_) => {
                                for k in &extras {
                                    path.push(Step::Key(k.clone()));
                                    let v = instance.field(k).unwrap();
                                    self.descend(v, value, path, active, out);
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
                                            Some(Value::Obj(p)) => {
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
                    if let Value::Obj(fields) = instance {
                        for (k, _) in fields {
                            self.descend(&Value::Str(k.clone()), value, path, active, out);
                        }
                    }
                }
                "items" => {
                    if let Value::Arr(elements) = instance {
                        let prefix = match schema.field("prefixItems") {
                            Some(Value::Arr(p)) => p.len(),
                            _ => 0,
                        };
                        if value == &Value::Bool(false) && elements.len() > prefix {
                            let extra = elements.len() - prefix;
                            let rest = if extra == 1 {
                                elements[prefix].clone()
                            } else {
                                Value::Arr(elements[prefix..].to_vec())
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
                                self.descend(e, value, path, active, out);
                                path.pop();
                            }
                        }
                    }
                }
                "prefixItems" => {
                    if let (Value::Arr(elements), Value::Arr(subs)) = (instance, value) {
                        for (i, (e, sub)) in elements.iter().zip(subs).enumerate() {
                            path.push(Step::Index(i));
                            self.descend(e, sub, path, active, out);
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
                    if let (Value::Arr(a), Some(limit)) = (instance, len_limit(value)) {
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
                    if let (Value::Obj(o), Some(limit)) = (instance, len_limit(value)) {
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
                    if let Value::Arr(a) = instance {
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
                    if let Value::Arr(subs) = value {
                        for sub in subs {
                            self.descend(instance, sub, path, active, out);
                        }
                    }
                }
                "anyOf" => {
                    if let Value::Arr(subs) = value {
                        if !subs.iter().any(|s| self.valid(instance, s, active)) {
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
                    if let Value::Arr(subs) = value {
                        let good: Vec<&Value> = subs
                            .iter()
                            .filter(|s| self.valid(instance, s, active))
                            .collect();
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
                    if self.valid(instance, value, active) {
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
                    let branch = if self.valid(instance, value, active) {
                        "then"
                    } else {
                        "else"
                    };
                    if let Some(sub) = schema.field(branch) {
                        self.descend(instance, sub, path, active, out);
                    }
                }
                "dependentRequired" => {
                    if let (Value::Obj(_), Value::Obj(deps)) = (instance, value) {
                        for (prop, needs) in deps {
                            if instance.field(prop).is_none() {
                                continue;
                            }
                            if let Value::Arr(needs) = needs {
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
            Some((_, Value::Obj(p))) => p
                .iter()
                .filter_map(|(k, _)| pyre::compile(k).ok())
                .collect(),
            _ => vec![],
        };
        fields
            .iter()
            .filter(|(k, _)| {
                let listed =
                    matches!(props, Some(Value::Obj(_)) if props.unwrap().field(k).is_some());
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

    #[test]
    fn recursive_ref_depth_cap_on_2mb_thread() {
        let handle = std::thread::Builder::new()
            .stack_size(2 * 1024 * 1024)
            .spawn(|| {
                let d = json::MAX_DEPTH;
                let inst_s = format!("{}1{}", "{\"a\":".repeat(d), "}".repeat(d));
                let inst = loads(&inst_s).unwrap();

                let simple_ref = loads(
                    r##"{"$defs":{"n":{"type":["object","integer"],"properties":{"a":{"$ref":"#/$defs/n"}}}},"$ref":"#/$defs/n"}"##,
                )
                .unwrap();
                assert!(Validator::new(&simple_ref).iter_errors(&inst).is_empty());

                let combinator_ref = loads(
                    r##"{"$defs":{"n":{"anyOf":[{"type":"integer"},{"type":"object","properties":{"a":{"$ref":"#/$defs/n"}}}]}},"$ref":"#/$defs/n"}"##,
                )
                .unwrap();
                assert!(Validator::new(&combinator_ref)
                    .iter_errors(&inst)
                    .is_empty());

                let over = format!("{}1{}", "{\"a\":".repeat(d + 1), "}".repeat(d + 1));
                let err = loads(&over).unwrap_err();
                assert_eq!(err.class, "RecursionError");
            })
            .unwrap();
        handle.join().unwrap();
    }

    fn on_2mb_thread<F: FnOnce() + Send + 'static>(f: F) {
        std::thread::Builder::new()
            .stack_size(2 * 1024 * 1024)
            .spawn(f)
            .unwrap()
            .join()
            .unwrap();
    }

    #[test]
    fn direct_ref_cycle_is_a_clean_error() {
        on_2mb_thread(|| {
            let errs = errors(
                r##"{"$defs":{"a":{"$ref":"#/$defs/a"}},"$ref":"#/$defs/a"}"##,
                "1",
            );
            assert_eq!(errs, vec![": recursive $ref #/$defs/a does not terminate"]);
        });
    }

    #[test]
    fn indirect_ref_cycle_is_a_clean_error() {
        on_2mb_thread(|| {
            let errs = errors(
                r##"{"$defs":{"a":{"$ref":"#/$defs/b"},"b":{"$ref":"#/$defs/a"}},"$ref":"#/$defs/a"}"##,
                "1",
            );
            assert_eq!(errs, vec![": recursive $ref #/$defs/a does not terminate"]);
        });
    }

    #[test]
    fn repeated_non_cyclic_ref_is_valid() {
        on_2mb_thread(|| {
            assert!(errors(
                r##"{"$defs":{"s":{"type":"string"}},"anyOf":[{"$ref":"#/$defs/s","minLength":5},{"$ref":"#/$defs/s"}]}"##,
                r#""hi""#,
            )
            .is_empty());
            assert!(errors(
                r##"{"$defs":{"s":{"type":"string"}},"type":"object","properties":{"a":{"$ref":"#/$defs/s"},"b":{"$ref":"#/$defs/s"}}}"##,
                r#"{"a":"x","b":"y"}"#,
            )
            .is_empty());
        });
    }

    #[test]
    fn recursive_tree_ref_is_valid() {
        on_2mb_thread(|| {
            assert!(errors(
                r##"{"$defs":{"n":{"type":"object","properties":{"c":{"$ref":"#/$defs/n"}}}},"$ref":"#/$defs/n"}"##,
                r#"{"c":{"c":{"c":{}}}}"#,
            )
            .is_empty());
        });
    }
}
