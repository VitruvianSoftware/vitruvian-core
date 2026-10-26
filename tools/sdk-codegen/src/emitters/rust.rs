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

//! emitters/rust.py: the protocol's types for the Rust kit, as one module,
//! written the way rustfmt leaves it.

use super::plain::{adapt, Entry, PField, PKind, Shape};
use crate::json::Value;
use crate::model::{Model, LICENCE};
use crate::pyerr::{self, PyResult};
use crate::pystr;
use crate::textwrap;

const OUTPUT: &str = "kits/rust/src/generated/mod.rs";
const KEYWORDS: [&str; 9] = [
    "type", "use", "mod", "fn", "struct", "enum", "impl", "match", "ref",
];

/// `re.findall(r"[A-Z]+(?=[A-Z][a-z])|[A-Z]?[a-z0-9]+|[A-Z]+", name)`.
pub fn words(name: &str) -> Vec<String> {
    let c: Vec<char> = name.chars().collect();
    let up = |i: usize| c.get(i).map(|x| x.is_ascii_uppercase()).unwrap_or(false);
    let low = |i: usize| c.get(i).map(|x| x.is_ascii_lowercase()).unwrap_or(false);
    let lowdig = |i: usize| {
        c.get(i)
            .map(|x| x.is_ascii_lowercase() || x.is_ascii_digit())
            .unwrap_or(false)
    };
    let mut out = Vec::new();
    let mut i = 0;
    while i < c.len() {
        let mut end = None;
        // [A-Z]+(?=[A-Z][a-z]), backing off the run until the lookahead holds.
        if up(i) {
            let mut j = i;
            while up(j) {
                j += 1;
            }
            let mut e = j;
            while e > i {
                if up(e) && low(e + 1) {
                    end = Some(e);
                    break;
                }
                e -= 1;
            }
        }
        // [A-Z]?[a-z0-9]+
        if end.is_none() {
            let start = if up(i) && lowdig(i + 1) { i + 1 } else { i };
            if lowdig(start) {
                let mut j = start;
                while lowdig(j) {
                    j += 1;
                }
                end = Some(j);
            }
        }
        // [A-Z]+
        if end.is_none() && up(i) {
            let mut j = i;
            while up(j) {
                j += 1;
            }
            end = Some(j);
        }
        match end {
            Some(e) => {
                out.push(c[i..e].iter().collect());
                i = e;
            }
            None => i += 1,
        }
    }
    out
}

/// notifyHUDParams -> NotifyHudParams.
pub fn type_name(name: &str) -> String {
    words(name)
        .iter()
        .map(|w| {
            let mut chars = w.chars();
            let first = chars
                .next()
                .map(|c| c.to_ascii_uppercase().to_string())
                .unwrap_or_default();
            format!("{}{}", first, chars.as_str().to_ascii_lowercase())
        })
        .collect()
}

/// protocolVersions -> protocol_versions; type -> r#type.
pub fn field_name(name: &str) -> String {
    let snake: Vec<String> = words(name).iter().map(|w| w.to_ascii_lowercase()).collect();
    let snake = snake.join("_");
    if KEYWORDS.contains(&snake.as_str()) {
        format!("r#{}", snake)
    } else {
        snake
    }
}

/// clipboard/readText -> CLIPBOARD_READ_TEXT.
fn constant(method: &Value) -> PyResult<String> {
    match method {
        Value::Str(s) => Ok(s
            .split('/')
            .flat_map(words)
            .map(|w| w.to_ascii_uppercase())
            .collect::<Vec<_>>()
            .join("_")),
        other => Err(pyerr::no_attribute(other, "split")),
    }
}

fn comment(text: &str, indent: &str) -> Vec<String> {
    textwrap::wrap(text, 80 - pystr::len(indent) - 4)
        .into_iter()
        .map(|line| format!("{}/// {}", indent, line))
        .collect()
}

fn rust_type(kind: &PKind) -> String {
    match kind.ty {
        "string" => "String".into(),
        "boolean" => "bool".into(),
        "integer" => "i64".into(),
        "number" => "f64".into(),
        "any" => "Value".into(),
        "array" => format!("Vec<{}>", rust_type(kind.items.as_ref().unwrap())),
        "map" => {
            let values = kind.values.as_ref().unwrap();
            if values.ty == "any" {
                "Map<String, Value>".into()
            } else {
                format!("BTreeMap<String, {}>", rust_type(values))
            }
        }
        "text" => "UiText".into(),
        _ => type_name(kind.reference()),
    }
}

fn field_lines(field: &PField) -> PyResult<Vec<String>> {
    let mut doc = field.doc.clone();
    if let Some(values) = field.kind.enum_listing()? {
        let listed: Vec<String> = values.iter().map(|v| v.py_str()).collect();
        doc.push_str(&format!(" One of: {}.", listed.join(", ")));
    }
    let mut lines = comment(&doc, "    ");
    let rust = field_name(&field.name);
    let mut options: Vec<String> = Vec::new();
    if rust.strip_prefix("r#").unwrap_or(&rust) != field.name {
        options.push(format!("rename = \"{}\"", field.name));
    }
    let mut kind = rust_type(&field.kind);
    if !field.required {
        options.push("default, skip_serializing_if = \"Option::is_none\"".into());
        kind = format!("Option<{}>", kind);
    }
    if !options.is_empty() {
        lines.push(format!("    #[serde({})]", options.join(", ")));
    }
    lines.push(format!("    pub {}: {},", rust, kind));
    Ok(lines)
}

fn doc_of(entry: &Entry) -> Vec<String> {
    if entry.doc.is_empty() {
        Vec::new()
    } else {
        comment(&entry.doc, "")
    }
}

fn text_item(entry: &Entry) -> Vec<String> {
    let name = type_name(&entry.name);
    let languages = type_name(entry.languages.as_deref().unwrap_or(""));
    let mut lines = doc_of(entry);
    lines.extend(
        [
            "#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]".to_string(),
            "#[serde(untagged)]".into(),
            format!("pub enum {} {{", name),
            "    /// The words, whatever the language.".into(),
            "    Plain(String),".into(),
            "    /// One entry per language, with English under `en`.".into(),
            format!("    Languages({}),", languages),
            "}".into(),
            "".into(),
            format!("impl Default for {} {{", name),
            "    fn default() -> Self {".into(),
            format!("        {}::Plain(String::new())", name),
            "    }".into(),
            "}".into(),
            "".into(),
            format!("impl From<&str> for {} {{", name),
            "    fn from(text: &str) -> Self {".into(),
            format!("        {}::Plain(text.to_string())", name),
            "    }".into(),
            "}".into(),
            "".into(),
            format!("impl From<String> for {} {{", name),
            "    fn from(text: String) -> Self {".into(),
            format!("        {}::Plain(text)", name),
            "    }".into(),
            "}".into(),
        ]
        .into_iter(),
    );
    lines
}

fn variant_item(entry: &Entry) -> PyResult<Vec<String>> {
    let name = type_name(&entry.name);
    let tag = entry.tag.clone().unwrap();
    let content = format!("{}Content", name);
    let mut lines = doc_of(entry);
    lines.push("#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]".into());
    lines.push(format!("pub struct {} {{", name));
    for field in entry.fields.iter().filter(|f| f.name != tag) {
        lines.extend(field_lines(field)?);
    }
    lines.push(format!(
        "    /// The kind, as `{}` names it, with its own fields.",
        tag
    ));
    lines.push("    #[serde(flatten)]".into());
    lines.push(format!("    pub content: {},", content));
    lines.push("}".into());
    lines.push(String::new());
    lines.push(format!(
        "/// What a {} is: one of the kinds these types have, by `{}`, or",
        name, tag
    ));
    lines.push(format!(
        "/// another kind kept as it came, `{}` included.",
        tag
    ));
    lines.push("#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]".into());
    lines.push(format!("#[serde(tag = \"{}\")]", tag));
    lines.push(format!("pub enum {} {{", content));
    for (value, reference) in &entry.variants {
        lines.push(format!("    #[serde(rename = \"{}\")]", value));
        lines.push(format!(
            "    {}({}),",
            type_name(value),
            type_name(reference)
        ));
    }
    lines.push("    /// A kind these types do not have, from a later protocol.".into());
    lines.push("    #[serde(untagged)]".into());
    lines.push("    Other(Map<String, Value>),".into());
    lines.push("}".into());
    Ok(lines)
}

fn item(entry: &Entry) -> PyResult<Vec<String>> {
    let name = type_name(&entry.name);
    let mut lines = doc_of(entry);
    match entry.shape {
        Shape::Text => return Ok(text_item(entry)),
        Shape::Map => {
            lines.push(format!(
                "pub type {} = BTreeMap<String, {}>;",
                name,
                rust_type(entry.values.as_ref().unwrap())
            ));
            return Ok(lines);
        }
        Shape::Struct => {}
    }
    if !entry.variants.is_empty() {
        return variant_item(entry);
    }
    lines.push("#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]".into());
    if entry.fields.is_empty() {
        lines.push(format!("pub struct {} {{}}", name));
        return Ok(lines);
    }
    lines.push(format!("pub struct {} {{", name));
    for field in &entry.fields {
        lines.extend(field_lines(field)?);
    }
    lines.push("}".into());
    Ok(lines)
}

fn optional(value: &Value) -> String {
    match value {
        Value::Null => "None".into(),
        other => format!("Some(\"{}\")", other.py_str()),
    }
}

fn named(definition: &Option<String>) -> String {
    match definition {
        None => "None".into(),
        Some(d) => format!("Some(\"{}\")", type_name(d)),
    }
}

pub fn emit(model: &Model) -> PyResult<Vec<(String, String)>> {
    let plain = adapt(model)?;
    let mut lines: Vec<String> = LICENCE
        .iter()
        .map(|l| {
            if l.is_empty() {
                "//".to_string()
            } else {
                format!("// {}", l)
            }
        })
        .collect();
    let versions: Vec<String> = plain
        .versions
        .iter()
        .map(|v| format!("\"{}\"", v.py_str()))
        .collect();
    for l in [
        "".to_string(),
        "// Code generated by tools/sdk-codegen from protocol/*.json. DO NOT EDIT.".into(),
        "".into(),
        "//! The protocol's messages and manifest, as Rust types.".into(),
        "".into(),
        "use serde::{Deserialize, Serialize};".into(),
        "use serde_json::{Map, Value};".into(),
        "use std::collections::BTreeMap;".into(),
        "".into(),
        "/// The version of the protocol these types are.".into(),
        format!(
            "pub const PROTOCOL_VERSION: &str = \"{}\";",
            plain.protocol.py_str()
        ),
        "".into(),
        "/// The versions a tool of these types speaks, oldest first: a later".into(),
        "/// version only adds to the one before it, so the tool answers hello".into(),
        "/// with the newest of them the app offers.".into(),
        format!(
            "pub const PROTOCOL_VERSIONS: &[&str] = &[{}];",
            versions.join(", ")
        ),
        "".into(),
        "/// The name of each message on the link.".into(),
        "pub mod methods {".into(),
    ] {
        lines.push(l);
    }
    for row in &plain.methods {
        lines.push(format!(
            "    pub const {}: &str = \"{}\";",
            constant(&row.method)?,
            row.method.py_str()
        ));
    }
    for l in [
        "}",
        "",
        "/// The names a manifest's `uses` may list.",
        "pub const SERVICES: &[&str] = &[",
    ] {
        lines.push(l.into());
    }
    for service in &plain.services {
        lines.push(format!("    \"{}\",", service.py_str()));
    }
    for l in [
        "];",
        "",
        "/// One row of methods.json: who sends the message, whether it is a",
        "/// request (answered) or a notice, the service the tool's manifest must",
        "/// list in `uses` for it, and the Rust types of what it carries.",
        "#[derive(Clone, Copy, Debug, PartialEq, Eq)]",
        "pub struct Method {",
        "    pub name: &'static str,",
        "    pub sender: &'static str,",
        "    pub kind: &'static str,",
        "    pub uses: Option<&'static str>,",
        "    pub params: Option<&'static str>,",
        "    pub result: Option<&'static str>,",
        "}",
        "",
        "/// Every message of the protocol.",
        "pub const METHODS: &[Method] = &[",
    ] {
        lines.push(l.into());
    }
    for row in &plain.methods {
        lines.push("    Method {".into());
        lines.push(format!(
            "        name: methods::{},",
            constant(&row.method)?
        ));
        lines.push(format!("        sender: \"{}\",", row.sender.py_str()));
        lines.push(format!("        kind: \"{}\",", row.kind.py_str()));
        lines.push(format!("        uses: {},", optional(&row.uses)));
        lines.push(format!("        params: {},", named(&row.params)));
        lines.push(format!("        result: {},", named(&row.result)));
        lines.push("    },".into());
    }
    lines.push("];".into());
    for entry in &plain.types {
        lines.push(String::new());
        lines.extend(item(entry)?);
    }
    for l in [
        "",
        "/// Reads `value` as the protocol type named `name` and writes it back,",
        "/// or None for a name that is no type here. The kit's tests hold the",
        "/// types to the protocol's examples with it.",
        "#[doc(hidden)]",
        "pub fn round_trip(name: &str, value: &Value) -> Option<serde_json::Result<Value>> {",
        "    fn again<T: serde::de::DeserializeOwned + Serialize>(",
        "        value: &Value,",
        "    ) -> serde_json::Result<Value> {",
        "        serde_json::to_value(serde_json::from_value::<T>(value.clone())?)",
        "    }",
        "    Some(match name {",
    ] {
        lines.push(l.into());
    }
    for entry in &plain.types {
        let n = type_name(&entry.name);
        lines.push(format!("        \"{}\" => again::<{}>(value),", n, n));
    }
    for l in ["        _ => return None,", "    })", "}"] {
        lines.push(l.into());
    }
    Ok(vec![(
        OUTPUT.to_string(),
        format!("{}\n", lines.join("\n")),
    )])
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn words_split_as_the_pattern_does() {
        assert_eq!(words("notifyHUDParams"), vec!["notify", "HUD", "Params"]);
        assert_eq!(words("URLField"), vec!["URL", "Field"]);
        assert_eq!(words("readText"), vec!["read", "Text"]);
        assert_eq!(words("ABC"), vec!["ABC"]);
        assert_eq!(words("a1B2"), vec!["a1", "B2"]);
        assert_eq!(words("x-y_z\u{e9}"), vec!["x", "y", "z"]);
        assert_eq!(type_name("notifyHUDParams"), "NotifyHudParams");
        assert_eq!(field_name("type"), "r#type");
        assert_eq!(field_name("dataFolder"), "data_folder");
        assert_eq!(
            constant(&Value::Str("clipboard/readText".into())).unwrap(),
            "CLIPBOARD_READ_TEXT"
        );
    }
}
