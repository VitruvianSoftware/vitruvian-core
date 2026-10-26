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

//! emitters/go.py: the protocol's types for the Go kit, as one file of
//! package toolkit, written the way gofumpt leaves it.

use super::plain::{adapt, Entry, PField, PKind, Shape};
use crate::json::Value;
use crate::model::{Model, LICENCE};
use crate::pyerr::{self, PyErr, PyResult};
use crate::pystr;
use crate::textwrap;
use std::collections::HashSet;

const OUTPUT: &str = "go/toolkit/protocol_gen.go";

/// notifyHUDParams -> NotifyHUDParams; url -> URL; uiBlock -> UIBlock.
pub fn exported(name: &str) -> String {
    match name {
        "id" => return "ID".into(),
        "url" => return "URL".into(),
        "pid" => return "PID".into(),
        "hud" => return "HUD".into(),
        "ui" => return "UI".into(),
        _ => {}
    }
    if name.starts_with("ui") && name.chars().nth(2).map(pystr::is_upper).unwrap_or(false) {
        return format!("UI{}", &name[2..]);
    }
    crate::model::capital_first(name)
}

fn method_name(method: &Value) -> PyResult<String> {
    match method {
        Value::Str(s) => Ok(format!(
            "Method{}",
            s.split('/').map(exported).collect::<Vec<_>>().join("")
        )),
        other => Err(pyerr::no_attribute(other, "split")),
    }
}

fn comment(text: &str, indent: &str) -> Vec<String> {
    let width = 78 - pystr::len(&pystr::expandtabs(indent, 8)) - 3;
    textwrap::wrap(text, width)
        .into_iter()
        .map(|line| format!("{}// {}", indent, line))
        .collect()
}

fn go_type(kind: &PKind, required: bool, maps: &HashSet<String>) -> String {
    let star = if required { "" } else { "*" };
    let plain = match kind.ty {
        "string" => Some("string"),
        "boolean" => Some("bool"),
        "integer" => Some("int"),
        "number" => Some("float64"),
        _ => None,
    };
    if let Some(p) = plain {
        return format!("{}{}", star, p);
    }
    match kind.ty {
        "any" => "any".into(),
        "array" => format!("[]{}", go_type(kind.items.as_ref().unwrap(), true, maps)),
        "map" => format!(
            "map[string]{}",
            go_type(kind.values.as_ref().unwrap(), true, maps)
        ),
        "text" => "UIText".into(),
        _ => {
            if maps.contains(kind.reference()) {
                exported(kind.reference())
            } else {
                format!("{}{}", star, exported(kind.reference()))
            }
        }
    }
}

fn joined(values: &[Value]) -> String {
    values
        .iter()
        .map(|v| v.py_str())
        .collect::<Vec<_>>()
        .join(", ")
}

fn field_doc(field: &PField) -> PyResult<String> {
    let mut doc = field.doc.clone();
    if let Some(values) = field.kind.enum_listing()? {
        doc.push_str(&format!(" One of: {}.", joined(&values)));
    }
    Ok(doc)
}

fn tag_of(field: &PField) -> String {
    format!(
        "{}{}",
        field.name,
        if field.required { "" } else { ",omitempty" }
    )
}

fn field_lines(field: &PField, maps: &HashSet<String>) -> PyResult<Vec<String>> {
    let doc = field_doc(field)?;
    let kind = go_type(&field.kind, field.required, maps);
    let mut lines = comment(&doc, "\t");
    lines.push(format!(
        "\t{} {} `json:\"{}\"`",
        exported(&field.name),
        kind,
        tag_of(field)
    ));
    Ok(lines)
}

fn doc_comment(name: &str, entry: &Entry) -> Vec<String> {
    if entry.doc.is_empty() {
        Vec::new()
    } else {
        comment(&format!("{}: {}", name, entry.doc), "")
    }
}

fn variant_struct(entry: &Entry, maps: &HashSet<String>) -> PyResult<Vec<String>> {
    let name = exported(&entry.name);
    let tag = entry.tag.clone().unwrap();
    let common: Vec<&PField> = entry.fields.iter().filter(|f| f.name != tag).collect();
    let tag_field = entry
        .fields
        .iter()
        .find(|f| f.name == tag)
        .ok_or_else(|| PyErr::new("StopIteration", ""))?;
    let mut lines = doc_comment(&name, entry);
    lines.push(format!("type {} struct {{", name));
    lines.extend(field_lines(tag_field, maps)?);
    for field in &common {
        lines.push(String::new());
        lines.extend(field_lines(field, maps)?);
    }
    lines.push(String::new());
    lines.push(format!(
        "\t// The kind's own fields: the one of these that {} names,",
        exported(&tag)
    ));
    lines.push("\t// or Other for a kind these types do not have, as it came.".into());
    for (value, reference) in &entry.variants {
        lines.push(format!(
            "\t{} *{} `json:\"-\"`",
            exported(value),
            exported(reference)
        ));
    }
    lines.push("\tOther map[string]any `json:\"-\"`".into());
    lines.push("}".into());
    lines.push(String::new());
    lines.push("// MarshalJSON writes the fields every kind has beside the kind's own.".into());
    lines.push(format!(
        "func (v {}) MarshalJSON() ([]byte, error) {{",
        name
    ));
    lines.push("\tvar own any = v.Other".into());
    lines.push(format!("\tswitch v.{} {{", exported(&tag)));
    for (value, _) in &entry.variants {
        lines.push(format!("\tcase \"{}\":", value));
        lines.push(format!("\t\town = v.{}", exported(value)));
    }
    for l in [
        "\t}",
        "\tfields := map[string]any{}",
        "\tif own != nil {",
        "\t\traw, err := json.Marshal(own)",
        "\t\tif err != nil {",
        "\t\t\treturn nil, err",
        "\t\t}",
        "\t\tif err := json.Unmarshal(raw, &fields); err != nil {",
        "\t\t\treturn nil, err",
        "\t\t}",
        "\t}",
    ] {
        lines.push(l.into());
    }
    lines.push(format!("\tfields[\"{}\"] = v.{}", tag, exported(&tag)));
    for field in &common {
        let go_name = exported(&field.name);
        if field.required {
            lines.push(format!("\tfields[\"{}\"] = v.{}", field.name, go_name));
            continue;
        }
        let star = if go_type(&field.kind, false, maps).starts_with('*') {
            "*"
        } else {
            ""
        };
        lines.push(format!("\tif v.{} != nil {{", go_name));
        lines.push(format!(
            "\t\tfields[\"{}\"] = {}v.{}",
            field.name, star, go_name
        ));
        lines.push("\t}".into());
    }
    lines.push("\treturn json.Marshal(fields)".into());
    lines.push("}".into());
    lines.push(String::new());
    lines.push(format!(
        "// UnmarshalJSON reads the kind {} names into its field, and any",
        exported(&tag)
    ));
    lines.push("// other kind into Other.".into());
    lines.push(format!(
        "func (v *{}) UnmarshalJSON(data []byte) error {{",
        name
    ));
    lines.push("\tvar head struct {".into());
    let mut all: Vec<&PField> = vec![tag_field];
    all.extend(common.iter().copied());
    for (number, field) in all.iter().enumerate() {
        if number > 0 {
            lines.push(String::new());
        }
        let kind = go_type(&field.kind, field.required, maps);
        lines.push(format!(
            "\t\t{} {} `json:\"{}\"`",
            exported(&field.name),
            kind,
            tag_of(field)
        ));
    }
    lines.push("\t}".into());
    lines.push("\tif err := json.Unmarshal(data, &head); err != nil {".into());
    lines.push("\t\treturn err".into());
    lines.push("\t}".into());
    let inits: Vec<String> = all
        .iter()
        .map(|f| format!("{}: head.{}", exported(&f.name), exported(&f.name)))
        .collect();
    lines.push(format!("\t*v = {}{{{}}}", name, inits.join(", ")));
    lines.push(format!("\tswitch v.{} {{", exported(&tag)));
    for (value, reference) in &entry.variants {
        lines.push(format!("\tcase \"{}\":", value));
        lines.push(format!(
            "\t\tv.{} = &{}{{}}",
            exported(value),
            exported(reference)
        ));
        lines.push(format!(
            "\t\treturn json.Unmarshal(data, v.{})",
            exported(value)
        ));
    }
    lines.push("\tdefault:".into());
    lines.push("\t\tif err := json.Unmarshal(data, &v.Other); err != nil {".into());
    lines.push("\t\t\treturn err".into());
    lines.push("\t\t}".into());
    for field in &all {
        lines.push(format!("\t\tdelete(v.Other, \"{}\")", field.name));
    }
    lines.push("\t\treturn nil".into());
    lines.push("\t}".into());
    lines.push("}".into());
    Ok(lines)
}

fn structure(entry: &Entry, maps: &HashSet<String>) -> PyResult<Vec<String>> {
    let name = exported(&entry.name);
    let mut lines = doc_comment(&name, entry);
    match entry.shape {
        Shape::Text => {
            lines.extend(comment(
                "A string, or a map from a language tag to a string.",
                "",
            ));
            lines.push(format!("type {} = any", name));
            return Ok(lines);
        }
        Shape::Map => {
            lines.push(format!(
                "type {} map[string]{}",
                name,
                go_type(entry.values.as_ref().unwrap(), true, maps)
            ));
            return Ok(lines);
        }
        Shape::Struct => {}
    }
    if !entry.variants.is_empty() {
        return variant_struct(entry, maps);
    }
    if entry.fields.is_empty() {
        lines.push(format!("type {} struct{{}}", name));
        return Ok(lines);
    }
    lines.push(format!("type {} struct {{", name));
    for (number, field) in entry.fields.iter().enumerate() {
        if number > 0 {
            lines.push(String::new());
        }
        lines.extend(field_lines(field, maps)?);
    }
    lines.push("}".into());
    let filled: Vec<&PField> = entry
        .fields
        .iter()
        .filter(|f| f.required && (f.kind.ty == "array" || f.kind.ty == "map"))
        .collect();
    if !filled.is_empty() {
        lines.push(String::new());
        lines.push(format!(
            "// MarshalJSON writes {} with an empty list or map, not null, for",
            name
        ));
        lines.push("// one left nil.".into());
        lines.push(format!(
            "func (v {}) MarshalJSON() ([]byte, error) {{",
            name
        ));
        lines.push(format!("\ttype plain {}", name));
        for field in filled {
            let kind = go_type(&field.kind, true, maps);
            lines.push(format!("\tif v.{} == nil {{", exported(&field.name)));
            lines.push(format!("\t\tv.{} = {}{{}}", exported(&field.name), kind));
            lines.push("\t}".into());
        }
        lines.push("\treturn json.Marshal(plain(v))".into());
        lines.push("}".into());
    }
    Ok(lines)
}

fn aligned(rows: &[(String, String)]) -> PyResult<Vec<String>> {
    let width = rows
        .iter()
        .map(|(n, _)| pystr::len(n))
        .max()
        .ok_or_else(|| PyErr::new("ValueError", "max() iterable argument is empty"))?;
    Ok(rows
        .iter()
        .map(|(n, v)| format!("\t{} = {}", pystr::ljust(n, width), v))
        .collect())
}

pub fn emit(model: &Model) -> PyResult<Vec<(String, String)>> {
    let plain = adapt(model)?;
    let maps: HashSet<String> = plain
        .types
        .iter()
        .filter(|e| e.shape != Shape::Struct)
        .map(|e| e.name.clone())
        .collect();
    let named = |d: &Option<String>| match d {
        None => "\"\"".to_string(),
        Some(d) => format!("\"{}\"", exported(d)),
    };
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
        "package toolkit".into(),
        "".into(),
        "import \"encoding/json\"".into(),
        "".into(),
        "// ProtocolVersion is the version of the protocol these types are.".into(),
        format!("const ProtocolVersion = \"{}\"", plain.protocol.py_str()),
        "".into(),
        "// ProtocolVersions are the versions a tool of these types speaks, oldest".into(),
        "// first: a later version only adds to the one before it, so the tool".into(),
        "// answers hello with the newest of them the app offers.".into(),
        format!("var ProtocolVersions = []string{{{}}}", versions.join(", ")),
        "".into(),
        "// The name of each message on the link.".into(),
        "const (".into(),
    ] {
        lines.push(l);
    }
    let mut rows = Vec::new();
    for row in &plain.methods {
        rows.push((
            method_name(&row.method)?,
            format!("\"{}\"", row.method.py_str()),
        ));
    }
    lines.extend(aligned(&rows)?);
    let services: Vec<String> = plain
        .services
        .iter()
        .map(|v| format!("\"{}\"", v.py_str()))
        .collect();
    for l in [
        ")".to_string(),
        "".into(),
        "// Services are the names a manifest's `uses` may list.".into(),
        format!("var Services = []string{{{}}}", services.join(", ")),
        "".into(),
        "// Method is one row of methods.json: who sends the message, whether it".into(),
        "// is a request (answered) or a notice, the service the tool's manifest".into(),
        "// must list in `uses` for it, and the Go types of what it carries. An".into(),
        "// empty Uses, Params or Result means none.".into(),
        "type Method struct {".into(),
    ] {
        lines.push(l);
    }
    for column in ["Name", "Sender", "Kind", "Uses", "Params", "Result"] {
        lines.push(format!("\t{} string", pystr::ljust(column, 6)));
    }
    lines.push("}".into());
    lines.push(String::new());
    lines.push("// Methods is every message of the protocol.".into());
    lines.push("var Methods = []Method{".into());
    for row in &plain.methods {
        let uses = if row.uses.truthy() {
            row.uses.py_str()
        } else {
            String::new()
        };
        lines.push(format!(
            "\t{{Name: {}, Sender: \"{}\", Kind: \"{}\", Uses: \"{}\", Params: {}, Result: {}}},",
            method_name(&row.method)?,
            row.sender.py_str(),
            row.kind.py_str(),
            uses,
            named(&row.params),
            named(&row.result)
        ));
    }
    lines.push("}".into());
    for entry in &plain.types {
        lines.push(String::new());
        lines.extend(structure(entry, &maps)?);
    }
    for l in [
        "",
        "// roundTrip reads raw as the protocol type with this name and writes it",
        "// back. The kit's tests hold the types to the protocol's examples with it.",
        "func roundTrip(name string, raw []byte) ([]byte, bool, error) {",
        "\tvar value any",
        "\tswitch name {",
    ] {
        lines.push(l.into());
    }
    for entry in &plain.types {
        let made = if entry.shape == Shape::Text {
            format!("new({})", exported(&entry.name))
        } else {
            format!("&{}{{}}", exported(&entry.name))
        };
        lines.push(format!("\tcase \"{}\":", exported(&entry.name)));
        lines.push(format!("\t\tvalue = {}", made));
    }
    for l in [
        "\tdefault:",
        "\t\treturn nil, false, nil",
        "\t}",
        "\tif err := json.Unmarshal(raw, value); err != nil {",
        "\t\treturn nil, true, err",
        "\t}",
        "\tout, err := json.Marshal(value)",
        "\treturn out, true, err",
        "}",
    ] {
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
    fn names() {
        assert_eq!(exported("notifyHUDParams"), "NotifyHUDParams");
        assert_eq!(exported("url"), "URL");
        assert_eq!(exported("uiBlock"), "UIBlock");
        assert_eq!(
            method_name(&Value::Str("notify/hud".into())).unwrap(),
            "MethodNotifyHUD"
        );
        assert_eq!(
            method_name(&Value::Int("3".into())).unwrap_err().render(),
            "AttributeError: 'int' object has no attribute 'split'"
        );
    }

    #[test]
    fn comments_wrap_at_78_columns() {
        let text = "word ".repeat(30);
        for line in comment(&text, "\t") {
            assert!(pystr::len(&pystr::expandtabs(&line, 8)) <= 78, "{line}");
        }
        assert_eq!(comment("", ""), Vec::<String>::new());
    }

    #[test]
    fn aligned_rows() {
        let rows = vec![
            ("A".to_string(), "1".to_string()),
            ("Bcd".to_string(), "2".to_string()),
        ];
        assert_eq!(aligned(&rows).unwrap(), vec!["\tA   = 1", "\tBcd = 2"]);
        assert!(aligned(&[]).is_err());
    }
}
