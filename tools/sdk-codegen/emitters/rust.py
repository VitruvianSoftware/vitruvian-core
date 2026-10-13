# Copyright (c) 2026 VitruvianSoftware
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
"""Rust: the protocol's types for the Rust kit, as one module.

    emit(model, licence) -> {path inside packages/vitruvian-sdk: text}

The same contract as go.py: `model` is what model.load returns, `licence`
the MIT text a line each. The module is `vitruvian_tool_kit::generated`, and
the crate re-exports all of it at its root.

Each type derives serde's Serialize and Deserialize, which is its JSON pair.
A field the schema does not require is an Option, left out of the JSON when
it is None. The file is written the way rustfmt leaves it.
"""

import re
import textwrap

from model import licence as licence_lines

OUTPUT = "kits/rust/src/generated/mod.rs"


# Stage B1's generator hands an emitter its dataclass model (model.Model) and
# nothing else, and the licence comes from model.licence(). The code below
# was written against the plain dict of Stage B2's plan; this maps one to the
# other, and nothing else here reads the dataclasses.
NAME = "rust"


def adapt(model):
    """B1's Model as the plain dict the code below reads."""

    def kind(type_):
        if type_.kind in ("string", "boolean", "integer", "number"):
            return {"type": type_.kind}
        if type_.kind == "array":
            return {"type": "array", "items": kind(type_.item)}
        if type_.kind == "map":
            return {"type": "map", "values": kind(type_.item)}
        if type_.kind == "object":
            return {"type": "map", "values": {"type": "any"}}
        if type_.kind == "ref":
            return {"type": "ref", "ref": type_.ref}
        if type_.kind == "enum":
            return {"type": "string", "enum": list(type_.values)}
        if type_.kind == "const":
            return {"type": "string"}
        return {"type": "any"}

    def entry(definition):
        if definition.alias is not None:
            return {
                "name": definition.name,
                "doc": definition.description,
                "shape": "map",
                "values": kind(definition.alias.item),
            }
        return {
            "name": definition.name,
            "doc": definition.description,
            "shape": "struct",
            "fields": [
                {
                    "name": field.name,
                    "doc": field.description,
                    "required": field.required,
                    "kind": kind(field.type),
                }
                for field in definition.fields
            ],
        }

    services = next(list(e.values) for e in model.enums if e.name == "Service")
    return {
        "protocol": model.protocol,
        "services": services,
        "methods": [
            {
                "method": m.method,
                "sender": m.sender,
                "kind": m.kind,
                "uses": m.uses,
                "params": m.params,
                "result": m.result,
            }
            for m in model.methods
        ],
        "messageTypes": [entry(d) for d in model.messages],
        "manifestTypes": [entry(d) for d in model.manifest],
    }


KEYWORDS = {"type", "use", "mod", "fn", "struct", "enum", "impl", "match", "ref"}


def words(name):
    """notifyHUDParams -> notify, HUD, Params."""
    return re.findall(r"[A-Z]+(?=[A-Z][a-z])|[A-Z]?[a-z0-9]+|[A-Z]+", name)


def type_name(name):
    """notifyHUDParams -> NotifyHudParams, as Rust writes an acronym."""
    return "".join(word[:1].upper() + word[1:].lower() for word in words(name))


def field_name(name):
    """protocolVersions -> protocol_versions; type -> r#type."""
    snake = "_".join(word.lower() for word in words(name))
    return "r#" + snake if snake in KEYWORDS else snake


def constant(method):
    """clipboard/readText -> CLIPBOARD_READ_TEXT."""
    return "_".join(word.upper() for part in method.split("/") for word in words(part))


def comment(text, indent=""):
    return [
        indent + "/// " + line for line in textwrap.wrap(text, 80 - len(indent) - 4)
    ]


def rust_type(kind, maps):
    plain = {"string": "String", "boolean": "bool", "integer": "i64", "number": "f64"}
    if kind["type"] in plain:
        return plain[kind["type"]]
    if kind["type"] == "any":
        return "Value"
    if kind["type"] == "array":
        return f"Vec<{rust_type(kind['items'], maps)}>"
    if kind["type"] == "map":
        if kind["values"]["type"] == "any":
            return "Map<String, Value>"
        return f"BTreeMap<String, {rust_type(kind['values'], maps)}>"
    return type_name(kind["ref"])


def item(entry, maps):
    name = type_name(entry["name"])
    lines = comment(entry["doc"]) if entry["doc"] else []
    if entry["shape"] == "map":
        return lines + [
            f"pub type {name} = BTreeMap<String, {rust_type(entry['values'], maps)}>;"
        ]
    lines.append("#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]")
    if not entry["fields"]:
        return lines + [f"pub struct {name} {{}}"]
    lines.append(f"pub struct {name} {{")
    for field in entry["fields"]:
        doc = field["doc"]
        if "enum" in field["kind"] or "enum" in field["kind"].get("items", {}):
            values = field["kind"].get("enum") or field["kind"]["items"]["enum"]
            doc += " One of: " + ", ".join(str(value) for value in values) + "."
        lines += comment(doc, "    ")
        rust = field_name(field["name"])
        options = []
        if rust.removeprefix("r#") != field["name"]:
            options.append(f'rename = "{field["name"]}"')
        kind = rust_type(field["kind"], maps)
        if not field["required"]:
            options.append('default, skip_serializing_if = "Option::is_none"')
            kind = f"Option<{kind}>"
        if options:
            lines.append(f"    #[serde({', '.join(options)})]")
        lines.append(f"    pub {rust}: {kind},")
    lines.append("}")
    return lines


def emit(model, licence=None):
    if licence is None:
        licence = licence_lines()
    if not isinstance(model, dict):
        model = adapt(model)
    types = model["messageTypes"] + model["manifestTypes"]
    maps = {entry["name"] for entry in types if entry["shape"] == "map"}

    def optional(value):
        return "None" if value is None else f'Some("{value}")'

    def named(definition):
        return optional(None if definition is None else type_name(definition))

    lines = ["// " + line if line else "//" for line in licence]
    lines += [
        "",
        "// Code generated by tools/sdk-codegen from protocol/*.json. DO NOT EDIT.",
        "",
        "//! The protocol's messages and manifest, as Rust types.",
        "",
        "use serde::{Deserialize, Serialize};",
        "use serde_json::{Map, Value};",
        "use std::collections::BTreeMap;",
        "",
        "/// The version of the protocol these types are.",
        f'pub const PROTOCOL_VERSION: &str = "{model["protocol"]}";',
        "",
        "/// The name of each message on the link.",
        "pub mod methods {",
    ]
    lines += [
        f'    pub const {constant(row["method"])}: &str = "{row["method"]}";'
        for row in model["methods"]
    ]
    lines += [
        "}",
        "",
        "/// The names a manifest's `uses` may list.",
        "pub const SERVICES: &[&str] = &[",
    ]
    lines += [f'    "{service}",' for service in model["services"]]
    lines += [
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
    ]
    for row in model["methods"]:
        lines += [
            "    Method {",
            f"        name: methods::{constant(row['method'])},",
            f'        sender: "{row["sender"]}",',
            f'        kind: "{row["kind"]}",',
            f"        uses: {optional(row['uses'])},",
            f"        params: {named(row['params'])},",
            f"        result: {named(row['result'])},",
            "    },",
        ]
    lines.append("];")
    for entry in types:
        lines += [""] + item(entry, maps)
    lines += [
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
    ]
    for entry in types:
        lines.append(
            f'        "{type_name(entry["name"])}" => again::<{type_name(entry["name"])}>(value),'
        )
    lines += ["        _ => return None,", "    })", "}"]
    return {OUTPUT: "\n".join(lines) + "\n"}
