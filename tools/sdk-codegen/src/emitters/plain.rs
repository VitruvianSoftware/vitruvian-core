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

//! The plain form go.py and rust.py read (their `adapt`): each type a kind
//! name with its parts, each definition an entry of one shape.

use crate::json::Value;
use crate::model::{Definition, Kind, Method, Model, Type, PROTOCOL_VERSIONS};
use crate::pyerr::{key_error, PyErr, PyResult};

/// A KIND: `{"type": ..., "items"|"values"|"ref"|"enum": ...}`.
#[derive(Clone, Debug)]
pub struct PKind {
    pub ty: &'static str,
    pub items: Option<Box<PKind>>,
    pub values: Option<Box<PKind>>,
    pub reference: Option<String>,
    pub enum_values: Option<Vec<Value>>,
}

impl PKind {
    fn of(ty: &'static str) -> PKind {
        PKind {
            ty,
            items: None,
            values: None,
            reference: None,
            enum_values: None,
        }
    }

    pub fn reference(&self) -> &str {
        self.reference.as_deref().unwrap_or("")
    }

    /// The values a field's comment lists, if it lists any:
    /// `kind.get("enum") or kind["items"]["enum"]`.
    pub fn enum_listing(&self) -> PyResult<Option<Vec<Value>>> {
        let own = self.enum_values.is_some();
        let inner = self
            .items
            .as_ref()
            .map(|i| i.enum_values.is_some())
            .unwrap_or(false);
        if !own && !inner {
            return Ok(None);
        }
        if let Some(v) = &self.enum_values {
            if !v.is_empty() {
                return Ok(Some(v.clone()));
            }
        }
        let items = self.items.as_ref().ok_or_else(|| key_error("items"))?;
        let values = items
            .enum_values
            .as_ref()
            .ok_or_else(|| key_error("enum"))?;
        Ok(Some(values.clone()))
    }
}

pub fn kind(t: &Type) -> PKind {
    match t.kind {
        Kind::String | Kind::Boolean | Kind::Integer | Kind::Number => PKind::of(t.kind.as_str()),
        Kind::Array => PKind {
            items: Some(Box::new(kind(t.item.as_ref().unwrap()))),
            ..PKind::of("array")
        },
        Kind::Map => PKind {
            values: Some(Box::new(kind(t.item.as_ref().unwrap()))),
            ..PKind::of("map")
        },
        Kind::Object => PKind {
            values: Some(Box::new(PKind::of("any"))),
            ..PKind::of("map")
        },
        Kind::Ref => PKind {
            reference: t.reference.clone(),
            ..PKind::of("ref")
        },
        Kind::Enum => PKind {
            enum_values: Some(t.values.clone()),
            ..PKind::of("string")
        },
        Kind::Const => PKind::of("string"),
        Kind::Text => PKind::of("text"),
        Kind::Scalar | Kind::Any => PKind::of("any"),
    }
}

#[derive(Clone, Debug)]
pub struct PField {
    pub name: String,
    pub doc: String,
    pub required: bool,
    pub kind: PKind,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Shape {
    Text,
    Map,
    Struct,
}

#[derive(Clone, Debug)]
pub struct Entry {
    pub name: String,
    pub doc: String,
    pub shape: Shape,
    /// A map's values.
    pub values: Option<PKind>,
    /// Text's map of languages.
    pub languages: Option<String>,
    pub tag: Option<String>,
    pub variants: Vec<(String, String)>,
    pub fields: Vec<PField>,
}

fn entry(d: &Definition) -> Entry {
    let base = Entry {
        name: d.name.clone(),
        doc: d.description.clone(),
        shape: Shape::Struct,
        values: None,
        languages: None,
        tag: None,
        variants: Vec::new(),
        fields: Vec::new(),
    };
    match &d.alias {
        Some(a) if a.kind == Kind::Text => Entry {
            shape: Shape::Text,
            languages: a.reference.clone(),
            ..base
        },
        Some(a) => Entry {
            shape: Shape::Map,
            values: Some(kind(a.item.as_ref().unwrap())),
            ..base
        },
        None => Entry {
            tag: d.tag.clone(),
            variants: d.variants.clone(),
            fields: d
                .fields
                .iter()
                .map(|f| PField {
                    name: f.name.clone(),
                    doc: f.description.clone(),
                    required: f.required,
                    kind: kind(&f.ty),
                })
                .collect(),
            ..base
        },
    }
}

pub struct Plain {
    pub protocol: Value,
    pub versions: Vec<Value>,
    pub services: Vec<Value>,
    pub methods: Vec<Method>,
    pub types: Vec<Entry>,
}

/// `adapt(model)`.
pub fn adapt(model: &Model) -> PyResult<Plain> {
    let find = |name: &str| -> PyResult<Vec<Value>> {
        model
            .enums
            .iter()
            .find(|e| e.name == name)
            .map(|e| e.values.clone())
            .ok_or_else(|| PyErr::new("StopIteration", ""))
    };
    let services = find("Service")?;
    let versions = find(PROTOCOL_VERSIONS)?;
    Ok(Plain {
        protocol: model.protocol.clone(),
        versions,
        services,
        methods: model.methods.clone(),
        types: model
            .messages
            .iter()
            .chain(model.manifest.iter())
            .map(entry)
            .collect(),
    })
}
