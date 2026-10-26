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

//! `jsonschema.Draft202012Validator.check_schema(schema)` from jsonschema
//! 4.26: the schema is validated against the 2020-12 meta-schema, with the
//! format checker jsonschema builds from what is installed (of the formats
//! the meta-schema names, only "regex" has a checker), and the first error
//! is raised as a SchemaError whose text is jsonschema's, word for word.
//!
//! The meta-schema is walked as jsonschema walks it: each keyword in the
//! order its object lists it, `$ref` resolved against the document it sits
//! in, `$dynamicRef: "#meta"` always the root meta-schema (the outermost in
//! the dynamic scope). One order is Python's to choose and not the port's:
//! `additionalProperties` visits the extra keys as a `set`, whose order
//! changes from run to run, so when two of them are wrong Python may report
//! either; this reports the first in the document.

use crate::json::{schema_eq, Value};
use crate::metaschema::DOCUMENTS;
use crate::pprint::pformat;
use crate::pyerr::PyErr;
use crate::pyre::{self, Refusal};
use crate::pystr;

const ROOT: &str = "https://json-schema.org/draft/2020-12/schema";

#[derive(Clone, Debug)]
enum Step {
    Key(String),
    Index(usize),
}

impl Step {
    fn repr(&self) -> String {
        match self {
            Step::Key(k) => pystr::repr_str(k),
            Step::Index(i) => i.to_string(),
        }
    }
}

/// One ValidationError, with the parts its text needs.
struct Failure {
    message: String,
    validator: Option<String>,
    schema: Option<Value>,
    instance: Option<Value>,
    /// Built innermost first; read reversed.
    path: Vec<Step>,
    schema_path: Vec<Step>,
    /// The exception the error was raised from: re.compile's re.error.
    cause: Option<PyErr>,
}

enum Outcome {
    Invalid(Failure),
    /// An exception that is not a validation error (re.compile's OverflowError).
    Crash(PyErr),
}

type Check = Result<(), Outcome>;

fn fail(message: String) -> Check {
    Err(Outcome::Invalid(Failure {
        message,
        validator: None,
        schema: None,
        instance: None,
        path: Vec::new(),
        schema_path: Vec::new(),
        cause: None,
    }))
}

struct Validator {
    docs: Vec<(String, Value)>,
}

fn index_as_index(steps: &[Step], container: &str) -> String {
    if steps.is_empty() {
        return container.to_string();
    }
    let parts: Vec<String> = steps.iter().map(|s| s.repr()).collect();
    format!("{}[{}]", container, parts.join("]["))
}

fn pretty(value: &Value) -> String {
    pformat(value, 72).replace('\n', "\n    ")
}

impl Failure {
    /// `str(SchemaError)`.
    fn render(&self) -> String {
        let mut schema_path: Vec<Step> = self.schema_path.iter().rev().cloned().collect();
        schema_path.pop();
        let path: Vec<Step> = self.path.iter().rev().cloned().collect();
        format!(
            "{}\n\nFailed validating {} in {}:\n    {}\n\nOn {}:\n    {}",
            self.message,
            pystr::repr_str(self.validator.as_deref().unwrap_or("")),
            index_as_index(&schema_path, "metaschema"),
            pretty(self.schema.as_ref().unwrap_or(&Value::Null)),
            index_as_index(&path, "schema"),
            pretty(self.instance.as_ref().unwrap_or(&Value::Null)),
        )
    }
}

fn is_type(instance: &Value, kind: &str) -> bool {
    match kind {
        "object" => matches!(instance, Value::Obj(_)),
        "array" => matches!(instance, Value::Arr(_)),
        "string" => matches!(instance, Value::Str(_)),
        "boolean" => matches!(instance, Value::Bool(_)),
        "null" => matches!(instance, Value::Null),
        "number" => instance.is_number(),
        "integer" => match instance {
            Value::Int(_) => true,
            Value::Float(f) => f.is_finite() && f.fract() == 0.0,
            _ => false,
        },
        _ => false,
    }
}

/// `re.search(pattern, s)` for the two patterns the meta-schema has.
fn search(pattern: &str, s: &str) -> bool {
    let chars: Vec<char> = s.chars().collect();
    let mut ends = vec![chars.len()];
    if chars.last() == Some(&'\n') {
        ends.push(chars.len() - 1);
    }
    ends.iter().any(|&e| {
        let body = &chars[..e];
        match pattern {
            "^[^#]*#?$" => match body.iter().position(|&c| c == '#') {
                None => true,
                Some(p) => p == body.len() - 1,
            },
            "^[A-Za-z_][-A-Za-z0-9._]*$" => {
                !body.is_empty()
                    && (body[0].is_ascii_alphabetic() || body[0] == '_')
                    && body[1..]
                        .iter()
                        .all(|&c| c.is_ascii_alphanumeric() || "-._".contains(c))
            }
            other => panic!("the meta-schema has no pattern {other}"),
        }
    })
}

/// jsonschema's `_utils.uniq`, which comes to the same as no two equal.
fn uniq(items: &[Value]) -> bool {
    for (i, a) in items.iter().enumerate() {
        for b in &items[..i] {
            if schema_eq(a, b) {
                return false;
            }
        }
    }
    true
}

impl Validator {
    fn new() -> Validator {
        let docs = DOCUMENTS
            .iter()
            .map(|(id, text)| {
                (
                    id.to_string(),
                    crate::json::loads(text).expect("a meta-schema is JSON"),
                )
            })
            .collect();
        Validator { docs }
    }

    fn doc(&self, id: &str) -> &Value {
        &self
            .docs
            .iter()
            .find(|(k, _)| k == id)
            .expect("a known meta-schema")
            .1
    }

    /// The schema `reference` names, from the document `base`, and its document.
    fn resolve(&self, base: &str, reference: &str) -> (String, Value) {
        let (target, pointer) = match reference.split_once('#') {
            Some((t, p)) => (t, p),
            None => (reference, ""),
        };
        let doc_id = if target.is_empty() {
            base.to_string()
        } else {
            let dir = &base[..base.rfind('/').unwrap() + 1];
            format!("{}{}", dir, target)
        };
        let mut node = self.doc(&doc_id);
        for part in pointer.split('/').filter(|p| !p.is_empty()) {
            node = node.get(part).expect("a meta-schema pointer resolves");
        }
        (doc_id, node.clone())
    }

    /// `descend(instance, schema, path, schema_path)`: the first error.
    fn descend(
        &self,
        instance: &Value,
        schema: &Value,
        doc: &str,
        path: Option<Step>,
        schema_path: Option<Step>,
    ) -> Check {
        let items = match schema {
            Value::Bool(true) => return Ok(()),
            Value::Bool(false) => {
                return fail(format!(
                    "False schema does not allow {}",
                    instance.py_repr()
                ));
            }
            Value::Obj(items) => items,
            _ => return Ok(()),
        };
        for (k, v) in items {
            let result = self.keyword(k, v, instance, schema, doc);
            if let Err(Outcome::Invalid(mut f)) = result {
                if f.validator.is_none() {
                    f.validator = Some(k.clone());
                    f.schema = Some(schema.clone());
                    f.instance = Some(instance.clone());
                }
                if k != "$ref" && k != "if" {
                    f.schema_path.push(Step::Key(k.clone()));
                }
                if let Some(p) = &path {
                    f.path.push(p.clone());
                }
                if let Some(p) = &schema_path {
                    f.schema_path.push(p.clone());
                }
                return Err(Outcome::Invalid(f));
            }
            result?;
        }
        Ok(())
    }

    fn keyword(&self, k: &str, v: &Value, instance: &Value, schema: &Value, doc: &str) -> Check {
        match k {
            "$ref" => {
                let (id, target) = self.resolve(doc, v.as_str().unwrap());
                self.descend(instance, &target, &id, None, None)
            }
            "$dynamicRef" => {
                let root = self.doc(ROOT).clone();
                self.descend(instance, &root, ROOT, None, None)
            }
            "allOf" => {
                if let Value::Arr(subs) = v {
                    for (i, sub) in subs.iter().enumerate() {
                        self.descend(instance, sub, doc, None, Some(Step::Index(i)))?;
                    }
                }
                Ok(())
            }
            "anyOf" => {
                if let Value::Arr(subs) = v {
                    for (i, sub) in subs.iter().enumerate() {
                        match self.descend(instance, sub, doc, None, Some(Step::Index(i))) {
                            Ok(()) => return Ok(()),
                            Err(Outcome::Crash(e)) => return Err(Outcome::Crash(e)),
                            Err(Outcome::Invalid(_)) => {}
                        }
                    }
                }
                fail(format!(
                    "{} is not valid under any of the given schemas",
                    instance.py_repr()
                ))
            }
            "type" => {
                let types: Vec<String> = match v {
                    Value::Str(s) => vec![s.clone()],
                    Value::Arr(a) => a
                        .iter()
                        .filter_map(|t| t.as_str().map(String::from))
                        .collect(),
                    _ => Vec::new(),
                };
                if types.iter().any(|t| is_type(instance, t)) {
                    return Ok(());
                }
                let reprs: Vec<String> = types.iter().map(|t| pystr::repr_str(t)).collect();
                fail(format!(
                    "{} is not of type {}",
                    instance.py_repr(),
                    reprs.join(", ")
                ))
            }
            "properties" => {
                if let (Value::Obj(_), Value::Obj(props)) = (instance, v) {
                    for (name, sub) in props {
                        if let Some(child) = instance.get(name) {
                            self.descend(
                                child,
                                sub,
                                doc,
                                Some(Step::Key(name.clone())),
                                Some(Step::Key(name.clone())),
                            )?;
                        }
                    }
                }
                Ok(())
            }
            "additionalProperties" => {
                if let Value::Obj(members) = instance {
                    let known = schema.get("properties");
                    for (name, child) in members {
                        if known.map(|p| p.has(name)).unwrap_or(false) {
                            continue;
                        }
                        if matches!(v, Value::Obj(_)) {
                            self.descend(child, v, doc, Some(Step::Key(name.clone())), None)?;
                        }
                    }
                }
                Ok(())
            }
            "propertyNames" => {
                if let Value::Obj(members) = instance {
                    for (name, _) in members {
                        self.descend(&Value::Str(name.clone()), v, doc, None, None)?;
                    }
                }
                Ok(())
            }
            "items" => {
                if let Value::Arr(elements) = instance {
                    for (i, element) in elements.iter().enumerate() {
                        self.descend(element, v, doc, Some(Step::Index(i)), None)?;
                    }
                }
                Ok(())
            }
            "minItems" => {
                if let (Value::Arr(elements), Value::Int(n)) = (instance, v) {
                    let n: usize = n.parse().unwrap();
                    if elements.len() < n {
                        let what = if n == 1 {
                            "should be non-empty"
                        } else {
                            "is too short"
                        };
                        return fail(format!("{} {}", instance.py_repr(), what));
                    }
                }
                Ok(())
            }
            "uniqueItems" => {
                if let (Value::Bool(true), Value::Arr(elements)) = (v, instance) {
                    if !uniq(elements) {
                        return fail(format!("{} has non-unique elements", instance.py_repr()));
                    }
                }
                Ok(())
            }
            "enum" => {
                if let Value::Arr(choices) = v {
                    if choices.iter().all(|c| !schema_eq(c, instance)) {
                        return fail(format!(
                            "{} is not one of {}",
                            instance.py_repr(),
                            v.py_repr()
                        ));
                    }
                }
                Ok(())
            }
            "minimum" => {
                if instance.is_number() && instance.sign() == Some(-1) {
                    return fail(format!(
                        "{} is less than the minimum of {}",
                        instance.py_repr(),
                        v.py_repr()
                    ));
                }
                Ok(())
            }
            "exclusiveMinimum" => {
                if instance.is_number() && matches!(instance.sign(), Some(-1) | Some(0)) {
                    return fail(format!(
                        "{} is less than or equal to the minimum of {}",
                        instance.py_repr(),
                        v.py_repr()
                    ));
                }
                Ok(())
            }
            "pattern" => {
                if let (Value::Str(s), Value::Str(p)) = (instance, v) {
                    if !search(p, s) {
                        return fail(format!(
                            "{} does not match {}",
                            instance.py_repr(),
                            pystr::repr_str(p)
                        ));
                    }
                }
                Ok(())
            }
            "format" => {
                if v.as_str() == Some("regex") {
                    if let Value::Str(s) = instance {
                        match pyre::compile(s) {
                            Ok(()) => {}
                            Err(Refusal::Error(message)) => {
                                let mut failure =
                                    fail(format!("{} is not a 'regex'", instance.py_repr()));
                                if let Err(Outcome::Invalid(f)) = &mut failure {
                                    f.cause = Some(PyErr::new("re.error", message));
                                }
                                return failure;
                            }
                            Err(Refusal::Crash(class, message)) => {
                                return Err(Outcome::Crash(PyErr::new(class, message)));
                            }
                        }
                    }
                }
                Ok(())
            }
            _ => Ok(()),
        }
    }
}

/// `Draft202012Validator.check_schema(schema)`.
pub fn check_schema(schema: &Value) -> Result<(), PyErr> {
    let validator = Validator::new();
    let root = validator.doc(ROOT).clone();
    match validator.descend(schema, &root, ROOT, None, None) {
        Ok(()) => Ok(()),
        Err(Outcome::Crash(e)) => Err(e),
        Err(Outcome::Invalid(f)) => {
            let mut e = PyErr::new("jsonschema.exceptions.SchemaError", f.render());
            e.cause = f.cause.map(Box::new);
            Err(e)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::json::loads;

    fn error(text: &str) -> String {
        check_schema(&loads(text).unwrap()).unwrap_err().message
    }

    #[test]
    fn a_good_schema_passes() {
        for text in [
            "true",
            "{}",
            r#"{"type": "object", "properties": {"a": {"type": ["string", "null"]}}, "$defs": {"b": {"enum": [1, true]}}}"#,
            r##"{"$id": "x#", "$anchor": "a_b", "pattern": "^a+$", "patternProperties": {"^x": true}}"##,
            r#"{"minItems": 1.0}"#,
        ] {
            assert!(check_schema(&loads(text).unwrap()).is_ok(), "{text}");
        }
    }

    #[test]
    fn a_bad_type_reads_as_jsonschema_says() {
        assert_eq!(
            error(r#"{"$defs": {"x": {"type": "foo"}}}"#),
            "'foo' is not valid under any of the given schemas\n\nFailed validating 'anyOf' in metaschema['allOf'][0]['properties']['$defs']['additionalProperties']['$dynamicRef']['allOf'][3]['properties']['type']:\n    {'anyOf': [{'$ref': '#/$defs/simpleTypes'},\n               {'type': 'array',\n                'items': {'$ref': '#/$defs/simpleTypes'},\n                'minItems': 1,\n                'uniqueItems': True}]}\n\nOn schema['$defs']['x']['type']:\n    'foo'"
        );
    }

    #[test]
    fn other_keywords() {
        assert_eq!(
            error(r#"{"pattern": "("}"#),
            "'(' is not a 'regex'\n\nFailed validating 'format' in metaschema['allOf'][3]['properties']['pattern']:\n    {'type': 'string', 'format': 'regex'}\n\nOn schema['pattern']:\n    '('"
        );
        assert_eq!(
            error(r#"{"minItems": -1}"#),
            "-1 is less than the minimum of 0\n\nFailed validating 'minimum' in metaschema['allOf'][3]['properties']['minItems']:\n    {'type': 'integer', 'minimum': 0}\n\nOn schema['minItems']:\n    -1"
        );
        assert!(error(r#"{"allOf": []}"#).starts_with("[] should be non-empty\n"));
        assert!(error(r##"{"$id": "a#b"}"##).starts_with("'a#b' does not match '^[^#]*#?$'\n"));
        assert!(error(r#"{"required": ["a", "a"]}"#)
            .starts_with("['a', 'a'] has non-unique elements\n"));
        assert!(error(r#"{"multipleOf": 0}"#)
            .starts_with("0 is less than or equal to the minimum of 0\n"));
        assert!(error(r#"{"$anchor": "1a"}"#).starts_with("'1a' does not match"));
        assert!(error(r#"{"$vocabulary": {"x": 1}}"#).starts_with("1 is not of type 'boolean'\n"));
        assert!(error(r#"{"patternProperties": {"(": {}}}"#)
            .contains("On schema['patternProperties']:\n    '('"));
        assert!(error("3").starts_with("3 is not of type 'object', 'boolean'\n"));
        assert_eq!(
            check_schema(&loads(r#"{"pattern": "a{9999999999}"}"#).unwrap())
                .unwrap_err()
                .render(),
            "OverflowError: the repetition number is too large"
        );
    }
}
