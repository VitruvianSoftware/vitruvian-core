// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT
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

//! Zero-dependency JSON Schema Draft 2020-12 validator and field-coverage
//! analyzer for `manifest.schema.json` and `messages.schema.json`.

use std::collections::BTreeSet;

use conformance_rs_lib::json::{self, Value};

/// Validates that `schema` is a well-formed Draft 2020-12 schema object whose
/// internal `$ref` targets all resolve in `$defs`.
pub fn check_schema(schema: &Value) -> Result<(), String> {
    if !schema.is_dict() {
        return Err("schema root is not an object".to_string());
    }
    let defs = schema.get("$defs");
    check_refs_recursive(schema, defs)
}

fn check_refs_recursive(node: &Value, defs: Option<&Value>) -> Result<(), String> {
    match node {
        Value::Obj(entries) => {
            for (k, v) in entries {
                if k == "$ref" {
                    let s = v
                        .as_str()
                        .ok_or_else(|| "$ref must be a string".to_string())?;
                    let name = s
                        .strip_prefix("#/$defs/")
                        .ok_or_else(|| format!("unsupported $ref format: {s}"))?;
                    if defs.and_then(|d| d.get(name)).is_none() {
                        return Err(format!("unresolved $ref: {s}"));
                    }
                } else {
                    check_refs_recursive(v, defs)?;
                }
            }
            Ok(())
        }
        Value::Arr(items) => {
            for item in items {
                check_refs_recursive(item, defs)?;
            }
            Ok(())
        }
        _ => Ok(()),
    }
}

/// Returns `true` if `instance` is valid against `schema` (where `schema` is also the root).
pub fn is_valid(schema: &Value, instance: &Value) -> bool {
    first_error(schema, instance, schema).is_none()
}

/// Returns `true` if `instance` is valid against `node` using `root` for `$defs`.
pub fn is_valid_with_root(node: &Value, instance: &Value, root: &Value) -> bool {
    first_error(node, instance, root).is_none()
}

/// Returns validation error messages for `instance` against `schema`.
pub fn iter_errors(schema: &Value, instance: &Value) -> Vec<String> {
    match first_error(schema, instance, schema) {
        Some(err) => vec![err],
        None => Vec::new(),
    }
}

fn as_f64(val: &Value) -> Option<f64> {
    match val {
        Value::Int(s) => s.parse::<f64>().ok(),
        Value::Float(f) => Some(*f),
        _ => None,
    }
}

fn matches_single_type(type_name: &str, instance: &Value) -> bool {
    match type_name {
        "null" => matches!(instance, Value::Null),
        "boolean" => matches!(instance, Value::Bool(_)),
        "string" => matches!(instance, Value::Str(_)),
        "array" => matches!(instance, Value::Arr(_)),
        "object" => matches!(instance, Value::Obj(_)),
        "number" => instance.is_number(),
        "integer" => instance.is_whole(),
        _ => false,
    }
}

fn is_ident_segment(s: &str) -> bool {
    !s.is_empty()
        && s.bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
}

/// Evaluates the regular expression patterns used in `manifest.schema.json` and
/// `messages.schema.json` without external regex crates.
pub fn matches_pattern(pattern: &str, text: &str) -> bool {
    match pattern {
        "^[A-Za-z0-9_-]+(\\.[A-Za-z0-9_-]+)+$" => {
            let parts: Vec<&str> = text.split('.').collect();
            parts.len() >= 2 && parts.into_iter().all(is_ident_segment)
        }
        "^[A-Za-z0-9_-]+(\\.[A-Za-z0-9_-]+)*$" => {
            let parts: Vec<&str> = text.split('.').collect();
            !parts.is_empty() && parts.into_iter().all(is_ident_segment)
        }
        "\\S" => text.chars().any(|c| !c.is_whitespace()),
        "^(?!\\.{1,2}(/|$))[^/]+(/(?!\\.{1,2}(/|$))[^/]+)*$" => {
            if text.is_empty() {
                return false;
            }
            for seg in text.split('/') {
                if seg.is_empty() || seg == "." || seg == ".." {
                    return false;
                }
            }
            true
        }
        "^[^\\u0000-\\u001f\\u007f-\\u009f]*$" => text.chars().all(|c| {
            let u = c as u32;
            !(u <= 0x1f || (0x7f..=0x9f).contains(&u))
        }),
        _ => false,
    }
}

/// Returns the first validation error when validating `instance` against `node`
/// with `$defs` looked up in `root`.
pub fn first_error(node: &Value, instance: &Value, root: &Value) -> Option<String> {
    if let Some(b) = node.as_bool() {
        return if b {
            None
        } else {
            Some("false schema always fails".to_string())
        };
    }

    // 1. $ref
    if let Some(ref_val) = node.get("$ref").and_then(|v| v.as_str()) {
        let def_name = ref_val.rsplit('/').next().unwrap_or(ref_val);
        let target = root
            .get("$defs")
            .and_then(|d| d.get(def_name))
            .or_else(|| node.get("$defs").and_then(|d| d.get(def_name)))?;
        if let Some(err) = first_error(target, instance, root) {
            return Some(err);
        }
    }

    // 2. type
    if let Some(type_val) = node.get("type") {
        let type_ok = match type_val {
            Value::Str(t) => matches_single_type(t, instance),
            Value::Arr(types) => types
                .iter()
                .filter_map(|t| t.as_str())
                .any(|t| matches_single_type(t, instance)),
            _ => false,
        };
        if !type_ok {
            return Some(format!(
                "{} is not of type {}",
                instance.py_repr(),
                type_val.py_repr()
            ));
        }
    }

    // 3. const
    if let Some(const_val) = node.get("const") {
        if !json::py_eq(instance, const_val) {
            return Some(format!("{} was expected", const_val.py_repr()));
        }
    }

    // 4. enum
    if let Some(enum_arr) = node.get("enum").and_then(|v| v.as_arr()) {
        if !enum_arr.iter().any(|item| json::py_eq(instance, item)) {
            return Some(format!(
                "{} is not one of {}",
                instance.py_repr(),
                node.get("enum").unwrap().py_repr()
            ));
        }
    }

    // 5. Numeric constraints: minimum, maximum
    if instance.is_number() {
        if let Some(val_f) = as_f64(instance) {
            if let Some(min_f) = node.get("minimum").and_then(as_f64) {
                if val_f < min_f {
                    return Some(format!(
                        "{} is less than the minimum of {}",
                        instance.py_repr(),
                        min_f
                    ));
                }
            }
            if let Some(max_f) = node.get("maximum").and_then(as_f64) {
                if val_f > max_f {
                    return Some(format!(
                        "{} is greater than the maximum of {}",
                        instance.py_repr(),
                        max_f
                    ));
                }
            }
        }
    }

    // 6. String constraints: maxLength, minLength, pattern
    if let Some(s) = instance.as_str() {
        let char_len = s.chars().count();
        if let Some(max_len) = node.get("maxLength").and_then(as_f64) {
            if (char_len as f64) > max_len {
                return Some(format!("{} is too long", instance.py_repr()));
            }
        }
        if let Some(min_len) = node.get("minLength").and_then(as_f64) {
            if (char_len as f64) < min_len {
                return Some(format!("{} is too short", instance.py_repr()));
            }
        }
        if let Some(pat) = node.get("pattern").and_then(|v| v.as_str()) {
            if !matches_pattern(pat, s) {
                return Some(format!("{} does not match {:?}", instance.py_repr(), pat));
            }
        }
    }

    // 7. Array constraints: minItems, maxItems, uniqueItems, items, contains/minContains/maxContains
    if let Some(arr) = instance.as_arr() {
        if let Some(min_items) = node.get("minItems").and_then(as_f64) {
            if (arr.len() as f64) < min_items {
                return Some(format!("{} is too short", instance.py_repr()));
            }
        }
        if let Some(max_items) = node.get("maxItems").and_then(as_f64) {
            if (arr.len() as f64) > max_items {
                return Some(format!("{} is too long", instance.py_repr()));
            }
        }
        if node.get("uniqueItems").and_then(|v| v.as_bool()) == Some(true) {
            for i in 0..arr.len() {
                for j in (i + 1)..arr.len() {
                    if json::py_eq(&arr[i], &arr[j]) {
                        return Some(format!("{} has non-unique elements", instance.py_repr()));
                    }
                }
            }
        }
        if let Some(item_schema) = node.get("items") {
            for item in arr {
                if let Some(err) = first_error(item_schema, item, root) {
                    return Some(err);
                }
            }
        }
        if let Some(contains_schema) = node.get("contains") {
            let match_count = arr
                .iter()
                .filter(|item| first_error(contains_schema, item, root).is_none())
                .count();
            let min_c = node
                .get("minContains")
                .and_then(as_f64)
                .map(|v| v as usize)
                .unwrap_or(1);
            if match_count < min_c {
                return Some(format!(
                    "{} does not contain enough matching items",
                    instance.py_repr()
                ));
            }
            if let Some(max_c) = node.get("maxContains").and_then(as_f64) {
                if match_count > (max_c as usize) {
                    return Some(format!(
                        "{} contains too many matching items",
                        instance.py_repr()
                    ));
                }
            }
        }
    }

    // 8. Object constraints: required, properties, additionalProperties
    if let Some(obj) = instance.as_obj() {
        if let Some(req_arr) = node.get("required").and_then(|v| v.as_arr()) {
            for req in req_arr {
                if let Some(req_key) = req.as_str() {
                    if !obj.iter().any(|(k, _)| k == req_key) {
                        return Some(format!("'{req_key}' is a required property"));
                    }
                }
            }
        }
        let props = node.get("properties");
        if let Some(props_obj) = props.and_then(|p| p.as_obj()) {
            for (prop_name, prop_schema) in props_obj {
                if let Some((_, val)) = obj.iter().find(|(k, _)| k == prop_name) {
                    if let Some(err) = first_error(prop_schema, val, root) {
                        return Some(err);
                    }
                }
            }
        }
        if let Some(add_props) = node.get("additionalProperties") {
            for (k, val) in obj {
                let in_props = props.and_then(|p| p.get(k)).is_some();
                if !in_props {
                    if let Some(err) = first_error(add_props, val, root) {
                        return Some(err);
                    }
                }
            }
        }
    }

    // 9. Combinators: allOf, anyOf, oneOf, not, if/then/else
    if let Some(all_of) = node.get("allOf").and_then(|v| v.as_arr()) {
        for sub in all_of {
            if let Some(err) = first_error(sub, instance, root) {
                return Some(err);
            }
        }
    }
    if let Some(any_of) = node.get("anyOf").and_then(|v| v.as_arr()) {
        if !any_of
            .iter()
            .any(|sub| first_error(sub, instance, root).is_none())
        {
            return Some(format!(
                "{} is not valid under any of the given schemas",
                instance.py_repr()
            ));
        }
    }
    if let Some(one_of) = node.get("oneOf").and_then(|v| v.as_arr()) {
        let valid_count = one_of
            .iter()
            .filter(|sub| first_error(sub, instance, root).is_none())
            .count();
        if valid_count != 1 {
            return Some(format!(
                "{} is not valid under exactly one of the given schemas",
                instance.py_repr()
            ));
        }
    }
    if let Some(not_schema) = node.get("not") {
        if first_error(not_schema, instance, root).is_none() {
            return Some(format!(
                "{} should not be valid under 'not' schema",
                instance.py_repr()
            ));
        }
    }
    if let Some(if_schema) = node.get("if") {
        if first_error(if_schema, instance, root).is_none() {
            if let Some(then_schema) = node.get("then") {
                if let Some(err) = first_error(then_schema, instance, root) {
                    return Some(err);
                }
            }
        } else if let Some(else_schema) = node.get("else") {
            if let Some(err) = first_error(else_schema, instance, root) {
                return Some(err);
            }
        }
    }

    None
}

/// Notes each declared field `instance` uses, as `(definition, field)`.
/// Mirrors `cover(node, instance, root, seen, where)` in `protocol_examples_test.py`.
pub fn cover(
    node: &Value,
    instance: &Value,
    root: &Value,
    seen: &mut BTreeSet<(String, String)>,
    where_name: &str,
) {
    let mut current_node = node;
    let mut current_where = where_name.to_string();
    if let Some(ref_str) = current_node.get("$ref").and_then(|v| v.as_str()) {
        current_where = ref_str.rsplit('/').next().unwrap_or(ref_str).to_string();
        if let Some(target) = root.get("$defs").and_then(|d| d.get(&current_where)) {
            current_node = target;
        } else {
            return;
        }
    }
    if instance.is_dict() {
        if let Some(props) = current_node.get("properties").and_then(|p| p.as_obj()) {
            for (key, child) in props {
                if let Some(val) = instance.get(key) {
                    seen.insert((current_where.clone(), key.clone()));
                    cover(child, val, root, seen, &current_where);
                }
            }
        }
        // A block's own fields are in the definition its kind picks.
        if let Some(branches) = current_node.get("allOf").and_then(|a| a.as_arr()) {
            for branch in branches {
                let picked = branch
                    .get("if")
                    .and_then(|i| i.get("properties"))
                    .and_then(|p| p.get("type"));
                if let Some(const_val) = picked.and_then(|p| p.get("const")) {
                    if let Some(inst_type) = instance.get("type") {
                        if json::py_eq(inst_type, const_val) {
                            if let Some(then_node) = branch.get("then") {
                                cover(then_node, instance, root, seen, &current_where);
                            }
                        }
                    }
                }
            }
        }
    } else if let Some(items) = instance.as_arr() {
        if let Some(item_schema) = current_node.get("items") {
            for item in items {
                cover(item_schema, item, root, seen, &current_where);
            }
        }
    }
}

/// Every `(definition, field)` the schema declares.
pub fn declared(root: &Value, top: &str) -> BTreeSet<(String, String)> {
    let mut pairs = BTreeSet::new();
    if let Some(props) = root.get("properties").and_then(|p| p.as_obj()) {
        for (key, _) in props {
            pairs.insert((top.to_string(), key.clone()));
        }
    }
    if let Some(defs) = root.get("$defs").and_then(|d| d.as_obj()) {
        for (name, node) in defs {
            if let Some(props) = node.get("properties").and_then(|p| p.as_obj()) {
                for (key, _) in props {
                    pairs.insert((name.clone(), key.clone()));
                }
            }
        }
    }
    pairs
}

/// Returns a problem string for each declared `(definition, field)` not in `seen`.
pub fn unused(root: &Value, top: &str, seen: &BTreeSet<(String, String)>) -> Vec<String> {
    declared(root, top)
        .difference(seen)
        .map(|(where_name, key)| format!("no valid example uses {where_name}.{key}"))
        .collect()
}

/// The fields of an example that the schema does not name.
pub fn unknown_fields(value: &Value, schema: &Value, defs: &Value, path: &str) -> Vec<String> {
    let mut cur = schema;
    while let Some(ref_str) = cur.get("$ref").and_then(|v| v.as_str()) {
        let name = ref_str.rsplit('/').next().unwrap_or(ref_str);
        match defs.get(name) {
            Some(target) => cur = target,
            None => break,
        }
    }
    let mut found = Vec::new();
    if let Some(entries) = value.as_obj() {
        if let Some(props) = cur.get("properties") {
            for (key, inner) in entries {
                if let Some(prop_schema) = props.get(key) {
                    found.extend(unknown_fields(
                        inner,
                        prop_schema,
                        defs,
                        &format!("{path}{key}."),
                    ));
                } else {
                    found.push(format!("{path}{key}"));
                }
            }
        }
    } else if let Some(items) = value.as_arr() {
        if let Some(item_schema) = cur.get("items") {
            for inner in items {
                found.extend(unknown_fields(inner, item_schema, defs, path));
            }
        }
    }
    found
}
