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

//! model.py: what the protocol's three files say, as the plain values every
//! emitter reads. Each step is taken in model.py's order, so a schema it
//! cannot read stops this at the same place, with the same exception.

use crate::fsio;
use crate::json::{self, py_eq, Value};
use crate::pyerr::{self, schema_problem, PyErr, PyResult};
use crate::pystr;
use crate::schema;

/// The objects in messages.schema.json that are the envelope, not a payload.
pub const ENVELOPE: [&str; 5] = ["id", "request", "notice", "result", "failure"];

/// A type's name where the schema's own will not do.
pub fn titles(name: &str) -> Option<&'static str> {
    match name {
        "empty" => Some("EmptyObject"),
        "error" => Some("RPCErrorObject"),
        "manifest" => Some("ToolManifest"),
        _ => None,
    }
}

/// The name of each closed list of names, by the definition and field it is in.
pub fn enum_name(owner: &str, field: &str) -> Option<&'static str> {
    Some(match (owner, field) {
        ("manifest", "protocol") => "ProtocolVersion",
        ("manifest", "uses") => "Service",
        ("manifest", "activation") => "Activation",
        ("command", "surfaces") => "Surface",
        ("preference", "type") => "PreferenceType",
        ("keyEquivalent", "modifiers") => "Modifier",
        ("panel", "placement") => "PanelPlacement",
        ("panel", "kind") => "PanelKind",
        ("uiEventParams", "event") => "UIEventKind",
        ("textBlock", "style") => "TextStyle",
        ("buttonBlock", "style") => "ButtonStyle",
        ("fieldBlock", "kind") => "FieldKind",
        ("uiStatusParams", "state") => "StatusState",
        ("statusContribution", "placement") => "StatusPlacement",
        ("slotContribution", "placement") => "SlotPlacement",
        ("preference", "picker") => "PreferencePicker",
        _ => return None,
    })
}

pub const PROTOCOL_VERSIONS: &str = "ProtocolVersion";

/// The MIT licence header model.py starts with, a line each, without its
/// comment marks: every generated file carries it.
pub const LICENCE: [&str; 19] = [
    "Copyright (c) 2026 VitruvianSoftware",
    "",
    "Permission is hereby granted, free of charge, to any person obtaining a copy",
    "of this software and associated documentation files (the \"Software\"), to deal",
    "in the Software without restriction, including without limitation the rights",
    "to use, copy, modify, merge, publish, distribute, sublicense, and/or sell",
    "copies of the Software, and to permit persons to whom the Software is",
    "furnished to do so, subject to the following conditions:",
    "",
    "The above copyright notice and this permission notice shall be included in",
    "all copies or substantial portions of the Software.",
    "",
    "THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR",
    "IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,",
    "FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE",
    "AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER",
    "LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,",
    "OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE",
    "SOFTWARE.",
];

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Kind {
    String,
    Boolean,
    Integer,
    Number,
    Scalar,
    Any,
    Object,
    Array,
    Map,
    Ref,
    Enum,
    Const,
    Text,
}

impl Kind {
    pub fn as_str(self) -> &'static str {
        match self {
            Kind::String => "string",
            Kind::Boolean => "boolean",
            Kind::Integer => "integer",
            Kind::Number => "number",
            Kind::Scalar => "scalar",
            Kind::Any => "any",
            Kind::Object => "object",
            Kind::Array => "array",
            Kind::Map => "map",
            Kind::Ref => "ref",
            Kind::Enum => "enum",
            Kind::Const => "const",
            Kind::Text => "text",
        }
    }
}

/// A field's type (model.Type).
#[derive(Clone, Debug)]
pub struct Type {
    pub kind: Kind,
    pub item: Option<Box<Type>>,
    pub reference: Option<String>,
    pub name: Option<String>,
    pub values: Vec<Value>,
}

impl Type {
    fn of(kind: Kind) -> Type {
        Type {
            kind,
            item: None,
            reference: None,
            name: None,
            values: Vec::new(),
        }
    }

    fn holding(kind: Kind, item: Type) -> Type {
        Type {
            item: Some(Box::new(item)),
            ..Type::of(kind)
        }
    }

    fn naming(kind: Kind, reference: String) -> Type {
        Type {
            reference: Some(reference),
            ..Type::of(kind)
        }
    }

    pub fn reference(&self) -> &str {
        self.reference.as_deref().unwrap_or("")
    }

    pub fn name(&self) -> &str {
        self.name.as_deref().unwrap_or("")
    }
}

/// The dataclass `==` of two Types.
pub fn type_eq(a: &Type, b: &Type) -> bool {
    a.kind == b.kind
        && match (&a.item, &b.item) {
            (None, None) => true,
            (Some(x), Some(y)) => type_eq(x, y),
            _ => false,
        }
        && a.reference == b.reference
        && a.name == b.name
        && values_eq(&a.values, &b.values)
}

fn values_eq(a: &[Value], b: &[Value]) -> bool {
    a.len() == b.len() && a.iter().zip(b).all(|(x, y)| py_eq(x, y))
}

#[derive(Clone, Debug)]
pub struct Field {
    pub name: String,
    pub ty: Type,
    pub required: bool,
    pub description: String,
}

fn field_eq(a: &Field, b: &Field) -> bool {
    a.name == b.name
        && type_eq(&a.ty, &b.ty)
        && a.required == b.required
        && a.description == b.description
}

#[derive(Clone, Debug)]
pub struct Definition {
    pub name: String,
    pub title: String,
    pub description: String,
    pub fields: Vec<Field>,
    pub alias: Option<Type>,
    pub tag: Option<String>,
    pub variants: Vec<(String, String)>,
}

#[derive(Clone, Debug)]
pub struct Enum {
    pub name: String,
    pub values: Vec<Value>,
    pub description: String,
}

/// One row of methods.json, its cells as JSON gave them.
#[derive(Clone, Debug)]
pub struct Method {
    pub method: Value,
    pub sender: Value,
    pub kind: Value,
    pub uses: Value,
    pub params: Option<String>,
    pub result: Option<String>,
}

impl Method {
    /// `method.path`: the name in parts, `notify/hud` is (notify, hud).
    pub fn path(&self) -> PyResult<Vec<String>> {
        match &self.method {
            Value::Str(s) => Ok(s.split('/').map(String::from).collect()),
            other => Err(pyerr::no_attribute(other, "split")),
        }
    }

    pub fn is(&self, sender: &str, kind: &str) -> bool {
        self.sender.as_str() == Some(sender) && self.kind.as_str() == Some(kind)
    }
}

#[derive(Clone, Debug)]
pub struct Model {
    pub protocol: Value,
    pub messages: Vec<Definition>,
    pub manifest: Vec<Definition>,
    pub enums: Vec<Enum>,
    pub methods: Vec<Method>,
}

impl Model {
    pub fn definition(&self, name: &str) -> PyResult<&Definition> {
        self.messages
            .iter()
            .chain(self.manifest.iter())
            .find(|d| d.name == name)
            .ok_or_else(|| pyerr::key_error(name))
    }

    pub fn title(&self, name: &str) -> PyResult<String> {
        Ok(self.definition(name)?.title.clone())
    }
}

/// uiTree -> UITree; empty -> EmptyObject.
pub fn title_of(name: &str) -> String {
    if let Some(t) = titles(name) {
        return t.to_string();
    }
    if name.starts_with("ui") && name.chars().nth(2).map(pystr::is_upper).unwrap_or(false) {
        return format!("UI{}", &name[2..]);
    }
    capital_first(name)
}

/// `name[:1].upper() + name[1:]`.
pub fn capital_first(name: &str) -> String {
    let mut chars = name.chars();
    match chars.next() {
        None => String::new(),
        Some(c) => format!("{}{}", pystr::upper_char(c), chars.as_str()),
    }
}

/// `node["$ref"].rsplit("/", 1)[-1]`.
fn last_part(reference: &Value) -> PyResult<String> {
    match reference {
        Value::Str(s) => Ok(s.rsplit('/').next().unwrap_or("").to_string()),
        other => Err(pyerr::no_attribute(other, "rsplit")),
    }
}

/// `node.get("description", "")`.
fn description(node: &Value) -> PyResult<String> {
    Ok(match pyerr::get(node, "description")? {
        None => String::new(),
        Some(v) => v.py_str(),
    })
}

pub type Enums = Vec<Enum>;

fn enum_slot<'a>(enums: &'a mut Enums, name: &str) -> Option<&'a mut Enum> {
    enums.iter_mut().find(|e| e.name == name)
}

pub fn type_of(
    node: &Value,
    place: &str,
    owner: &str,
    field: &str,
    enums: &mut Enums,
) -> PyResult<Type> {
    if pyerr::contains(node, "$ref")? {
        return Ok(Type::naming(
            Kind::Ref,
            last_part(pyerr::getitem(node, "$ref")?)?,
        ));
    }
    if pyerr::contains(node, "const")? {
        let value = pyerr::getitem(node, "const")?.py_str();
        return Ok(Type {
            values: vec![Value::Str(value)],
            ..Type::of(Kind::Const)
        });
    }
    if pyerr::contains(node, "enum")? {
        let name = match enum_name(owner, field) {
            None => {
                return Err(schema_problem(format!(
                "{}: a list of names with no name of its own; add ({}, {}) to ENUMS in model.py",
                place,
                pystr::repr_str(owner),
                pystr::repr_str(field)
            )))
            }
            Some(n) => n,
        };
        let values = pyerr::iterate(pyerr::getitem(node, "enum")?)?;
        if let Some(existing) = enum_slot(enums, name) {
            if !values_eq(&existing.values, &values) {
                return Err(schema_problem(format!(
                    "{}: {} is named twice, with different names in it",
                    place, name
                )));
            }
        }
        let made = Enum {
            name: name.to_string(),
            values: values.clone(),
            description: description(node)?,
        };
        match enum_slot(enums, name) {
            Some(slot) => *slot = made,
            None => enums.push(made),
        }
        return Ok(Type {
            name: Some(name.to_string()),
            values,
            ..Type::of(Kind::Enum)
        });
    }
    let kind = match pyerr::get(node, "type")? {
        None => return Ok(Type::of(Kind::Any)),
        Some(k) => k,
    };
    if let Value::Arr(list) = kind {
        let mut names: Vec<String> = Vec::new();
        for v in list {
            match v {
                Value::Str(s) => names.push(s.clone()),
                _ => {
                    return Err(pyerr::type_error(
                        "'<' not supported between instances of a str and another type",
                    ))
                }
            }
        }
        names.sort();
        if names == ["boolean", "number", "string"] {
            return Ok(Type::of(Kind::Scalar));
        }
        return Err(schema_problem(format!(
            "{}: the type {} is not one the generator knows",
            place,
            kind.py_str()
        )));
    }
    match kind.as_str() {
        Some("string") => return Ok(Type::of(Kind::String)),
        Some("boolean") => return Ok(Type::of(Kind::Boolean)),
        Some("integer") => return Ok(Type::of(Kind::Integer)),
        Some("number") => return Ok(Type::of(Kind::Number)),
        Some("array") => {
            let empty = Value::Obj(Vec::new());
            let items = pyerr::get(node, "items")?.unwrap_or(&empty);
            let item = type_of(items, &format!("{}[]", place), owner, field, enums)?;
            return Ok(Type::holding(Kind::Array, item));
        }
        Some("object") => {
            if pyerr::get(node, "properties")?
                .map(|p| p.truthy())
                .unwrap_or(false)
            {
                return Err(schema_problem(format!(
                    "{}: an object with fields inside a field; make it a definition of its own",
                    place
                )));
            }
            if let Some(extra @ Value::Obj(_)) = pyerr::get(node, "additionalProperties")? {
                let item = type_of(extra, &format!("{}{{}}", place), owner, field, enums)?;
                return Ok(Type::holding(Kind::Map, item));
            }
            return Ok(Type::of(Kind::Object));
        }
        _ => {}
    }
    Err(schema_problem(format!(
        "{}: the type {} is not one the generator knows",
        place,
        kind.py_repr()
    )))
}

fn variants_of(node: &Value, place: &str) -> PyResult<(Option<String>, Vec<(String, String)>)> {
    let mut tag: Option<String> = None;
    let mut found = Vec::new();
    let rules = match pyerr::get(node, "allOf")? {
        None => Vec::new(),
        Some(r) => pyerr::iterate(r)?,
    };
    let empty = Value::Obj(Vec::new());
    for rule in &rules {
        let condition_of = pyerr::get(rule, "if")?.unwrap_or(&empty);
        let condition = pyerr::get(condition_of, "properties")?
            .unwrap_or(&empty)
            .clone();
        let then = pyerr::get(rule, "then")?.unwrap_or(&empty).clone();
        let members = match &condition {
            Value::Obj(m) => m.clone(),
            other => pyerr::iterate(other)?
                .into_iter()
                .map(|k| (k.py_str(), Value::Null))
                .collect(),
        };
        if members.len() != 1 || !pyerr::contains(&then, "$ref")? {
            continue;
        }
        let (field, value) = &members[0];
        if !pyerr::contains(value, "const")? {
            continue;
        }
        if let Some(t) = &tag {
            if t != field {
                return Err(schema_problem(format!(
                    "{}: kinds told apart by {} and by {}",
                    place, t, field
                )));
            }
        }
        tag = Some(field.clone());
        found.push((
            pyerr::getitem(value, "const")?.py_str(),
            last_part(pyerr::getitem(&then, "$ref")?)?,
        ));
    }
    Ok((tag, found))
}

pub fn definition_of(
    name: &str,
    node: &Value,
    place: &str,
    enums: &mut Enums,
) -> PyResult<Definition> {
    let desc = description(node)?;
    let plain = |fields: Vec<Field>, alias: Option<Type>| Definition {
        name: name.to_string(),
        title: title_of(name),
        description: desc.clone(),
        fields,
        alias,
        tag: None,
        variants: Vec::new(),
    };
    if pyerr::contains(node, "oneOf")? && !pyerr::contains(node, "type")? {
        let choices = pyerr::iterate(pyerr::getitem(node, "oneOf")?)?;
        let string_only = Value::Obj(vec![("type".into(), Value::Str("string".into()))]);
        if choices.len() == 2
            && py_eq(&choices[0], &string_only)
            && pyerr::contains(&choices[1], "$ref")?
        {
            let reference = last_part(pyerr::getitem(&choices[1], "$ref")?)?;
            return Ok(plain(Vec::new(), Some(Type::naming(Kind::Text, reference))));
        }
        return Err(schema_problem(format!(
            "{}: a choice of types the generator does not know",
            place
        )));
    }
    let is_object = pyerr::get(node, "type")?.and_then(|t| t.as_str()) == Some("object");
    if is_object && !pyerr::contains(node, "properties")? {
        if let Some(extra @ Value::Obj(_)) = pyerr::get(node, "additionalProperties")? {
            let alias = Type::holding(Kind::Map, type_of(extra, place, name, "*", enums)?);
            return Ok(plain(Vec::new(), Some(alias)));
        }
        return Ok(plain(Vec::new(), None));
    }
    if !is_object {
        return Err(schema_problem(format!(
            "{}: a definition that is not an object",
            place
        )));
    }
    let required: Vec<Value> = match pyerr::get(node, "required")? {
        None => Vec::new(),
        Some(r) => pyerr::iterate(r)?,
    };
    let mut fields = Vec::new();
    for (key, child) in pyerr::items(pyerr::getitem(node, "properties")?)? {
        let ty = type_of(child, &format!("{}.{}", place, key), name, key, enums)?;
        let is_required = required.iter().any(|r| r.as_str() == Some(key));
        fields.push(Field {
            name: key.clone(),
            ty,
            required: is_required,
            description: description(child)?,
        });
    }
    let (tag, variants) = variants_of(node, place)?;
    if let Some(t) = &tag {
        if !fields.iter().any(|f| &f.name == t) {
            return Err(schema_problem(format!(
                "{}: the kinds are told apart by {}, which is no field",
                place, t
            )));
        }
    }
    Ok(Definition {
        tag,
        variants,
        ..plain(fields, None)
    })
}

pub fn check_references(messages: &[Definition], manifest: &[Definition]) -> PyResult<()> {
    let all: Vec<&Definition> = messages.iter().chain(manifest.iter()).collect();
    let known = |name: &str| all.iter().any(|d| d.name == name);
    for definition in &all {
        let mut parts: Vec<Option<&Type>> = vec![definition.alias.as_ref()];
        for field in &definition.fields {
            parts.push(Some(&field.ty));
            parts.push(field.ty.item.as_deref());
        }
        for part in parts.into_iter().flatten() {
            if matches!(part.kind, Kind::Ref | Kind::Text) && !known(part.reference()) {
                return Err(schema_problem(format!(
                    "{}: no definition {}",
                    definition.name,
                    part.reference()
                )));
            }
        }
        for (value, reference) in &definition.variants {
            if !known(reference) {
                return Err(schema_problem(format!(
                    "{}: no definition {} for {}",
                    definition.name, reference, value
                )));
            }
            if !messages.is_empty() {
                let target = all.iter().find(|d| &d.name == reference).unwrap();
                if target.alias.is_some() {
                    return Err(schema_problem(format!(
                        "{}: {}, the kind {}, is not an object",
                        definition.name, reference, value
                    )));
                }
            }
        }
    }
    Ok(())
}

fn read(folder: &str, name: &str) -> PyResult<Value> {
    json::loads(&fsio::read_text(&fsio::join(folder, name))?)
}

fn optional_name(row: &Value, key: &str) -> PyResult<Value> {
    Ok(pyerr::getitem(row, key)?.clone())
}

/// `model.load(protocol_folder)`.
pub fn load(protocol_folder: &str) -> PyResult<Model> {
    let messages_schema = read(protocol_folder, "messages.schema.json")?;
    let manifest_schema = read(protocol_folder, "manifest.schema.json")?;
    for s in [&messages_schema, &manifest_schema] {
        schema::check_schema(s)?;
    }
    let table = read(protocol_folder, "methods.json")?;
    let mut enums: Enums = Vec::new();

    let mut messages = Vec::new();
    for (name, node) in pyerr::items(pyerr::getitem(&messages_schema, "$defs")?)? {
        if ENVELOPE.contains(&name.as_str()) {
            continue;
        }
        let place = format!("messages.schema.json#/$defs/{}", name);
        messages.push(definition_of(name, node, &place, &mut enums)?);
    }
    let top = Value::Obj(
        pyerr::items(&manifest_schema)?
            .iter()
            .filter(|(k, _)| k != "$defs")
            .cloned()
            .collect(),
    );
    let mut manifest = vec![definition_of(
        "manifest",
        &top,
        "manifest.schema.json",
        &mut enums,
    )?];
    for (name, node) in pyerr::items(pyerr::getitem(&manifest_schema, "$defs")?)? {
        let place = format!("manifest.schema.json#/$defs/{}", name);
        manifest.push(definition_of(name, node, &place, &mut enums)?);
    }
    for definition in &manifest {
        if let Some(twin) = messages.iter().find(|d| d.name == definition.name) {
            let alias_same = match (&twin.alias, &definition.alias) {
                (None, None) => true,
                (Some(a), Some(b)) => type_eq(a, b),
                _ => false,
            };
            let fields_same = twin.fields.len() == definition.fields.len()
                && twin
                    .fields
                    .iter()
                    .zip(&definition.fields)
                    .all(|(a, b)| field_eq(a, b));
            if !(alias_same && fields_same) {
                return Err(schema_problem(format!(
                    "manifest.schema.json#/$defs/{}: defined by both schemas, differently",
                    definition.name
                )));
            }
        }
    }
    manifest.retain(|d| !messages.iter().any(|m| m.name == d.name));

    let rows = pyerr::iterate(pyerr::getitem(&table, "methods")?)?;
    let mut raw = Vec::new();
    for row in &rows {
        raw.push((
            optional_name(row, "method")?,
            optional_name(row, "sender")?,
            optional_name(row, "kind")?,
            optional_name(row, "uses")?,
            optional_name(row, "params")?,
            optional_name(row, "result")?,
        ));
    }
    let protocol = pyerr::getitem(&table, "protocol")?.clone();
    enums.sort_by(|a, b| a.name.cmp(&b.name));
    check_references(&messages, &manifest)?;
    let known = |name: &str| {
        messages
            .iter()
            .chain(manifest.iter())
            .any(|d| d.name == name)
    };
    let mut methods = Vec::new();
    for (method, sender, kind, uses, params, result) in raw {
        let mut names: Vec<Option<String>> = Vec::new();
        for value in [&params, &result] {
            match value {
                Value::Null => names.push(None),
                Value::Str(s) if known(s) => names.push(Some(s.clone())),
                other => {
                    pyerr::hashable(other)?;
                    return Err(schema_problem(format!(
                        "methods.json: {} names {}, which no schema defines",
                        method.py_str(),
                        other.py_str()
                    )));
                }
            }
        }
        methods.push(Method {
            method,
            sender,
            kind,
            uses,
            params: names[0].clone(),
            result: names[1].clone(),
        });
    }
    Ok(Model {
        protocol,
        messages,
        manifest,
        enums,
        methods,
    })
}

/// protocolVersions -> protocol_versions; notifyHUD -> notify_hud.
pub fn camel_to_snake(name: &str) -> String {
    let chars: Vec<char> = name.chars().collect();
    let mut out = String::new();
    for (index, &c) in chars.iter().enumerate() {
        if pystr::is_upper(c) && index > 0 {
            let before = chars[index - 1];
            let after = chars.get(index + 1).copied();
            if pystr::is_lower(before)
                || pystr::is_digit(before)
                || (after.map(pystr::is_lower).unwrap_or(false) && pystr::is_upper(before))
            {
                out.push('_');
            }
        }
        out.push_str(&pystr::lower_char(c));
    }
    out
}

/// The error a model reports for a problem it found itself, for the tests.
pub fn is_schema_problem(e: &PyErr) -> bool {
    e.class == "model.SchemaProblem"
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::json::loads;

    #[test]
    fn names() {
        assert_eq!(title_of("uiTree"), "UITree");
        assert_eq!(title_of("ui"), "Ui");
        assert_eq!(title_of("uiopen"), "Uiopen");
        assert_eq!(title_of("empty"), "EmptyObject");
        assert_eq!(title_of("notifyHUDParams"), "NotifyHUDParams");
        assert_eq!(title_of(""), "");
        assert_eq!(camel_to_snake("protocolVersions"), "protocol_versions");
        assert_eq!(camel_to_snake("notifyHUD"), "notify_hud");
        assert_eq!(camel_to_snake("UIEventKind"), "ui_event_kind");
        assert_eq!(camel_to_snake("readText2Go"), "read_text2_go");
    }

    #[test]
    fn a_variant_whose_kind_is_not_defined_stops_the_generator() {
        let node = loads(
            r##"{"type": "object", "required": ["type"], "properties": {"type": {"type": "string"}},
                "allOf": [{"if": {"properties": {"type": {"const": "chart"}}}, "then": {"$ref": "#/$defs/chartBlock"}}]}"##,
        )
        .unwrap();
        let definition = definition_of("block", &node, "here", &mut Vec::new()).unwrap();
        assert_eq!(
            definition.variants,
            vec![("chart".to_string(), "chartBlock".to_string())]
        );
        let e = check_references(&[definition], &[]).unwrap_err();
        assert!(is_schema_problem(&e));
        assert!(e.message.contains("chartBlock"));
    }

    #[test]
    fn a_list_of_names_with_no_name_stops_the_generator() {
        let node =
            loads(r#"{"type": "object", "properties": {"color": {"enum": ["red", "blue"]}}}"#)
                .unwrap();
        let e = definition_of("paint", &node, "here", &mut Vec::new()).unwrap_err();
        assert!(
            e.message.contains("add ('paint', 'color') to ENUMS"),
            "{}",
            e.message
        );
    }

    #[test]
    fn types() {
        let mut enums = Vec::new();
        let t =
            |text: &str, enums: &mut Enums| type_of(&loads(text).unwrap(), "w", "o", "f", enums);
        assert_eq!(
            t(r#"{"type": ["string", "number", "boolean"]}"#, &mut enums)
                .unwrap()
                .kind,
            Kind::Scalar
        );
        assert_eq!(
            t(r#"{"type": ["string", "null"]}"#, &mut enums)
                .unwrap_err()
                .message,
            "w: the type ['string', 'null'] is not one the generator knows"
        );
        assert_eq!(
            t(r#"{"type": "null"}"#, &mut enums).unwrap_err().message,
            "w: the type 'null' is not one the generator knows"
        );
        let map = t(
            r#"{"type": "object", "additionalProperties": {"type": "integer"}}"#,
            &mut enums,
        )
        .unwrap();
        assert_eq!(map.kind, Kind::Map);
        assert_eq!(map.item.unwrap().kind, Kind::Integer);
        assert_eq!(
            t(r#"{"const": 2.0}"#, &mut enums).unwrap().values[0].py_str(),
            "2.0"
        );
        assert_eq!(
            t("true", &mut enums).unwrap_err().render(),
            "TypeError: argument of type 'bool' is not iterable"
        );
        assert_eq!(t("{}", &mut enums).unwrap().kind, Kind::Any);
    }
}
