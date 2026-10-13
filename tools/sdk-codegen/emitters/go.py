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
"""Go: the protocol's types for the Go kit, as one file of package toolkit.

    emit(model, licence) -> {path inside packages/vitruvian-sdk: text}

`model` is what model.load returns (its docstring lists every key read
here); `licence` is the package's MIT text, a line each, with no comment
marks. Nothing else is read, so the module drops into any generator that
hands it those two.

The file is written the way gofumpt leaves it, so the formatter and the
drift test never disagree. A struct with a list or a map it must carry gets
a MarshalJSON that writes an empty one, not null, for a value left nil: JSON
has no nil list, and the schema refuses null.
"""

import textwrap

from model import licence as licence_lines

OUTPUT = "go/toolkit/protocol_gen.go"


# Stage B1's generator hands an emitter its dataclass model (model.Model) and
# nothing else, and the licence comes from model.licence(). The code below
# was written against the plain dict of Stage B2's plan; this maps one to the
# other, and nothing else here reads the dataclasses.
NAME = "go"


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


# Whole names Go writes in capitals.
INITIALISMS = {"id": "ID", "url": "URL", "pid": "PID", "hud": "HUD"}


def exported(name):
    """notifyHUDParams -> NotifyHUDParams; url -> URL."""
    return INITIALISMS.get(name, name[:1].upper() + name[1:])


def method_name(method):
    """notify/hud -> MethodNotifyHUD."""
    return "Method" + "".join(exported(part) for part in method.split("/"))


def comment(text, indent=""):
    """A doc comment, wrapped to 78 columns counting a tab as eight."""
    width = 78 - len(indent.expandtabs(8)) - 3
    return [indent + "// " + line for line in textwrap.wrap(text, width)]


def go_type(kind, required, maps):
    """The Go type of a KIND; `maps` names the TYPEs that are maps."""
    plain = {
        "string": "string",
        "boolean": "bool",
        "integer": "int",
        "number": "float64",
    }
    if kind["type"] in plain:
        return ("" if required else "*") + plain[kind["type"]]
    if kind["type"] == "any":
        return "any"
    if kind["type"] == "array":
        return "[]" + go_type(kind["items"], True, maps)
    if kind["type"] == "map":
        return "map[string]" + go_type(kind["values"], True, maps)
    if kind["ref"] in maps:
        return exported(kind["ref"])
    return ("" if required else "*") + exported(kind["ref"])


def struct(entry, maps):
    name = exported(entry["name"])
    lines = comment(f"{name}: {entry['doc']}") if entry["doc"] else []
    if entry["shape"] == "map":
        return lines + [
            f"type {name} map[string]{go_type(entry['values'], True, maps)}"
        ]
    if not entry["fields"]:
        return lines + [f"type {name} struct{{}}"]
    lines.append(f"type {name} struct {{")
    for number, field in enumerate(entry["fields"]):
        if number:
            lines.append("")
        doc = field["doc"]
        if "enum" in field["kind"] or "enum" in field["kind"].get("items", {}):
            values = field["kind"].get("enum") or field["kind"]["items"]["enum"]
            doc += " One of: " + ", ".join(str(value) for value in values) + "."
        lines += comment(doc, "\t")
        tag = field["name"] + ("" if field["required"] else ",omitempty")
        kind = go_type(field["kind"], field["required"], maps)
        lines.append(f'\t{exported(field["name"])} {kind} `json:"{tag}"`')
    lines.append("}")
    filled = [
        field
        for field in entry["fields"]
        if field["required"] and field["kind"]["type"] in ("array", "map")
    ]
    if filled:
        lines += [
            "",
            f"// MarshalJSON writes {name} with an empty list or map, not null, for",
            "// one left nil.",
            f"func (v {name}) MarshalJSON() ([]byte, error) {{",
            f"\ttype plain {name}",
        ]
        for field in filled:
            kind = go_type(field["kind"], True, maps)
            lines += [
                f"\tif v.{exported(field['name'])} == nil {{",
                f"\t\tv.{exported(field['name'])} = {kind}{{}}",
                "\t}",
            ]
        lines += ["\treturn json.Marshal(plain(v))", "}"]
    return lines


def aligned(rows, indent="\t"):
    """`name = value` rows lined up at the equals sign, as gofmt does."""
    width = max(len(name) for name, _ in rows)
    return [f"{indent}{name.ljust(width)} = {value}" for name, value in rows]


def emit(model, licence=None):
    if licence is None:
        licence = licence_lines()
    if not isinstance(model, dict):
        model = adapt(model)
    types = model["messageTypes"] + model["manifestTypes"]
    maps = {entry["name"] for entry in types if entry["shape"] == "map"}

    def named(definition):
        return '""' if definition is None else f'"{exported(definition)}"'

    lines = ["// " + line if line else "//" for line in licence]
    lines += [
        "",
        "// Code generated by tools/sdk-codegen from protocol/*.json. DO NOT EDIT.",
        "",
        "package toolkit",
        "",
        'import "encoding/json"',
        "",
        "// ProtocolVersion is the version of the protocol these types are.",
        f'const ProtocolVersion = "{model["protocol"]}"',
        "",
        "// The name of each message on the link.",
        "const (",
    ]
    lines += aligned(
        [(method_name(row["method"]), f'"{row["method"]}"') for row in model["methods"]]
    )
    lines += [
        ")",
        "",
        "// Services are the names a manifest's `uses` may list.",
        "var Services = []string{"
        + ", ".join(f'"{service}"' for service in model["services"])
        + "}",
        "",
        "// Method is one row of methods.json: who sends the message, whether it",
        "// is a request (answered) or a notice, the service the tool's manifest",
        "// must list in `uses` for it, and the Go types of what it carries. An",
        "// empty Uses, Params or Result means none.",
        "type Method struct {",
    ]
    columns = ["Name", "Sender", "Kind", "Uses", "Params", "Result"]
    width = max(len(column) for column in columns)
    lines += [f"\t{column.ljust(width)} string" for column in columns]
    lines += [
        "}",
        "",
        "// Methods is every message of the protocol.",
        "var Methods = []Method{",
    ]
    for row in model["methods"]:
        lines.append(
            f'\t{{Name: {method_name(row["method"])}, Sender: "{row["sender"]}", '
            f'Kind: "{row["kind"]}", Uses: "{row["uses"] or ""}", '
            f"Params: {named(row['params'])}, Result: {named(row['result'])}}},"
        )
    lines.append("}")
    for entry in types:
        lines += [""] + struct(entry, maps)
    lines += [
        "",
        "// roundTrip reads raw as the protocol type with this name and writes it",
        "// back. The kit's tests hold the types to the protocol's examples with it.",
        "func roundTrip(name string, raw []byte) ([]byte, bool, error) {",
        "\tvar value any",
        "\tswitch name {",
    ]
    for entry in types:
        lines += [
            f'\tcase "{exported(entry["name"])}":',
            f"\t\tvalue = &{exported(entry['name'])}{{}}",
        ]
    lines += [
        "\tdefault:",
        "\t\treturn nil, false, nil",
        "\t}",
        "\tif err := json.Unmarshal(raw, value); err != nil {",
        "\t\treturn nil, true, err",
        "\t}",
        "\tout, err := json.Marshal(value)",
        "\treturn out, true, err",
        "}",
    ]
    return {OUTPUT: "\n".join(lines) + "\n"}
