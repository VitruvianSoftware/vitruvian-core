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
"""What the protocol's three files say, as plain values every emitter reads.

The schemas are written for people and for a validator. This turns them into
the few things a language needs: the objects the messages carry and the
manifest is made of, with their fields; the closed lists of names; and the
table of messages. An emitter never reads a schema itself, so a new emitter
sees exactly what the others see.

Anything in a schema this does not know how to turn into a type stops it,
with the place named: a new construct is a decision for every language, not
something one emitter should guess at.
"""

import json
import os
from dataclasses import dataclass
from typing import Dict, List, Optional, Tuple

# The objects in messages.schema.json that are the envelope, not a payload.
# Each kit writes the envelope by hand: it is the part every kit reads and
# writes before it knows which message it has.
ENVELOPE = ("id", "request", "notice", "result", "failure")

# A type's name in every language, where the schema's own name will not do:
# `error` and `empty` are words too common to stand alone, and the manifest's
# top level has no name of its own. These are the Swift names.
TITLES = {
    "empty": "EmptyObject",
    "error": "RPCErrorObject",
    "manifest": "ToolManifest",
}

# A closed list of names written inside a field. Each needs a name of its own
# in a language; a new one stops the generator until it is named here.
ENUMS = {
    ("manifest", "protocol"): "ProtocolVersion",
    ("manifest", "uses"): "Service",
    ("manifest", "activation"): "Activation",
    ("command", "surfaces"): "Surface",
    ("preference", "type"): "PreferenceType",
    ("keyEquivalent", "modifiers"): "Modifier",
    ("panel", "placement"): "PanelPlacement",
    ("panel", "kind"): "PanelKind",
    ("uiEventParams", "event"): "UIEventKind",
    ("textBlock", "style"): "TextStyle",
    ("buttonBlock", "style"): "ButtonStyle",
    ("fieldBlock", "kind"): "FieldKind",
    ("uiStatusParams", "state"): "StatusState",
    ("statusContribution", "placement"): "StatusPlacement",
    ("slotContribution", "placement"): "SlotPlacement",
    ("preference", "picker"): "PreferencePicker",
}

# The name of the one closed list that is the protocol's versions, in the
# manifest's `protocol`: every kit answers hello with the newest of them the
# app offers.
PROTOCOL_VERSIONS = "ProtocolVersion"


@dataclass(frozen=True)
class Type:
    """A field's type.

    kind is one of: string, boolean, integer, number; scalar (text, yes or
    no, or a number: what a preference holds); any (any JSON value); object
    (a JSON object with any fields); array (of `item`); map (text keys, each
    value an `item`); ref (the definition named `ref`); enum (one of
    `values`, named `name`); const (exactly `values[0]`); text (a string, or
    the map of languages that the definition named `ref` is: what a tool
    draws).
    """

    kind: str
    item: Optional["Type"] = None
    ref: Optional[str] = None
    name: Optional[str] = None
    values: Tuple[str, ...] = ()


@dataclass(frozen=True)
class Field:
    """One field of an object, by its name on the wire."""

    name: str
    type: Type
    required: bool
    description: str


@dataclass(frozen=True)
class Definition:
    """An object a message carries, or a part of the manifest.

    `alias` is set for a definition that is not an object with fields of its
    own, such as localized text, which is a map from a language to text.

    `tag` and `variants` are set for an object that is one of several kinds
    by the value of one of its fields, as a block of a page is by `type`:
    `variants` pairs each value of `tag` with the definition that holds that
    kind's own fields, beside the fields listed here, which every kind has.
    A value that is none of them is a kind of a later protocol, kept as it
    came.
    """

    name: str
    title: str
    description: str
    fields: Tuple[Field, ...]
    alias: Optional[Type] = None
    tag: Optional[str] = None
    variants: Tuple[Tuple[str, str], ...] = ()


@dataclass(frozen=True)
class Enum:
    name: str
    values: Tuple[str, ...]
    description: str


@dataclass(frozen=True)
class Method:
    """One row of methods.json."""

    method: str
    sender: str
    kind: str
    uses: Optional[str]
    params: Optional[str]
    result: Optional[str]

    @property
    def path(self) -> Tuple[str, ...]:
        """The method's name in parts: `notify/hud` is (notify, hud)."""
        return tuple(self.method.split("/"))


@dataclass(frozen=True)
class Model:
    protocol: str
    messages: Tuple[Definition, ...]
    manifest: Tuple[Definition, ...]
    enums: Tuple[Enum, ...]
    methods: Tuple[Method, ...]

    def definition(self, name: str) -> Definition:
        for definition in self.messages + self.manifest:
            if definition.name == name:
                return definition
        raise KeyError(name)

    def title(self, name: str) -> str:
        return self.definition(name).title


def licence() -> List[str]:
    """The MIT licence header this file starts with, without its comment marks.

    Every generated file carries it, in its own language's comments.
    """
    with open(__file__, encoding="utf-8") as handle:
        lines = handle.read().split("\n")
    out = []
    for line in lines:
        if line.startswith("#!"):
            continue
        if not line.startswith("#"):
            break
        out.append(line[2:] if line.startswith("# ") else line[1:])
    return out


def title_of(name: str) -> str:
    """uiTree -> UITree, as the Swift types write the initialism; empty -> EmptyObject."""
    if name in TITLES:
        return TITLES[name]
    if name.startswith("ui") and name[2:3].isupper():
        return "UI" + name[2:]
    return name[:1].upper() + name[1:]


class SchemaProblem(Exception):
    """Something in a schema the generator does not know how to turn into a type."""


def type_of(node: Dict, where: str, owner: str, field: str, enums: Dict) -> Type:
    if "$ref" in node:
        return Type("ref", ref=node["$ref"].rsplit("/", 1)[-1])
    if "const" in node:
        return Type("const", values=(str(node["const"]),))
    if "enum" in node:
        name = ENUMS.get((owner, field))
        if name is None:
            raise SchemaProblem(
                f"{where}: a list of names with no name of its own; add ({owner!r}, {field!r}) to ENUMS in model.py"
            )
        values = tuple(node["enum"])
        if name in enums and enums[name].values != values:
            raise SchemaProblem(
                f"{where}: {name} is named twice, with different names in it"
            )
        enums[name] = Enum(name, values, node.get("description", ""))
        return Type("enum", name=name, values=values)
    kind = node.get("type")
    if kind is None:
        return Type("any")
    if isinstance(kind, list):
        if sorted(kind) == ["boolean", "number", "string"]:
            return Type("scalar")
        raise SchemaProblem(f"{where}: the type {kind} is not one the generator knows")
    if kind in ("string", "boolean", "integer", "number"):
        return Type(kind)
    if kind == "array":
        items = node.get("items", {})
        return Type("array", item=type_of(items, where + "[]", owner, field, enums))
    if kind == "object":
        if node.get("properties"):
            raise SchemaProblem(
                f"{where}: an object with fields inside a field; make it a definition of its own"
            )
        extra = node.get("additionalProperties")
        if isinstance(extra, dict):
            return Type("map", item=type_of(extra, where + "{}", owner, field, enums))
        return Type("object")
    raise SchemaProblem(f"{where}: the type {kind!r} is not one the generator knows")


def variants_of(
    node: Dict, where: str
) -> Tuple[Optional[str], Tuple[Tuple[str, str], ...]]:
    """The kinds an object's `allOf` names: each `if` on one field's value,
    `then` a definition. Any other rule in `allOf` is for a validator, not
    a type, and is left alone."""
    tag, found = None, []
    for rule in node.get("allOf", []):
        condition = rule.get("if", {}).get("properties", {})
        then = rule.get("then", {})
        if len(condition) != 1 or "$ref" not in then:
            continue
        ((field, value),) = condition.items()
        if "const" not in value:
            continue
        if tag not in (None, field):
            raise SchemaProblem(f"{where}: kinds told apart by {tag} and by {field}")
        tag = field
        found.append((str(value["const"]), then["$ref"].rsplit("/", 1)[-1]))
    return tag, tuple(found)


def definition_of(name: str, node: Dict, where: str, enums: Dict) -> Definition:
    description = node.get("description", "")
    if "oneOf" in node and "type" not in node:
        # Text a tool draws: a string, or the map of languages a manifest's
        # text is.
        choices = node["oneOf"]
        if (
            len(choices) == 2
            and choices[0] == {"type": "string"}
            and "$ref" in choices[1]
        ):
            ref = choices[1]["$ref"].rsplit("/", 1)[-1]
            return Definition(
                name, title_of(name), description, (), Type("text", ref=ref)
            )
        raise SchemaProblem(f"{where}: a choice of types the generator does not know")
    if node.get("type") == "object" and "properties" not in node:
        extra = node.get("additionalProperties")
        if isinstance(extra, dict):
            alias = Type("map", item=type_of(extra, where, name, "*", enums))
            return Definition(name, title_of(name), description, (), alias)
        return Definition(name, title_of(name), description, ())
    if node.get("type") != "object":
        raise SchemaProblem(f"{where}: a definition that is not an object")
    required = set(node.get("required", []))
    fields = tuple(
        Field(
            key,
            type_of(child, f"{where}.{key}", name, key, enums),
            key in required,
            child.get("description", ""),
        )
        for key, child in node["properties"].items()
    )
    tag, variants = variants_of(node, where)
    if tag is not None and tag not in {field.name for field in fields}:
        raise SchemaProblem(
            f"{where}: the kinds are told apart by {tag}, which is no field"
        )
    return Definition(name, title_of(name), description, fields, None, tag, variants)


def check_references(messages, manifest) -> None:
    """Every definition a field, an alias or a variant names exists."""
    known = {definition.name for definition in messages + manifest}
    for definition in messages + manifest:
        parts = [definition.alias]
        for field in definition.fields:
            parts += [field.type, field.type.item]
        for part in parts:
            if (
                part is not None
                and part.kind in ("ref", "text")
                and part.ref not in known
            ):
                raise SchemaProblem(f"{definition.name}: no definition {part.ref}")
        for value, ref in definition.variants:
            if ref not in known:
                raise SchemaProblem(
                    f"{definition.name}: no definition {ref} for {value}"
                )
            if (
                messages
                and ref in known
                and next(d for d in messages + manifest if d.name == ref).alias
                is not None
            ):
                raise SchemaProblem(
                    f"{definition.name}: {ref}, the kind {value}, is not an object"
                )


def load(protocol_folder: str) -> Model:
    """Reads the three files in `protocol_folder` (packages/vitruvian-sdk/protocol)."""

    def read(name):
        with open(os.path.join(protocol_folder, name), encoding="utf-8") as handle:
            return json.load(handle)

    messages_schema = read("messages.schema.json")
    manifest_schema = read("manifest.schema.json")
    # A schema that is not JSON Schema is stopped here, before anything is read from it.
    from jsonschema import Draft202012Validator

    for schema in (messages_schema, manifest_schema):
        Draft202012Validator.check_schema(schema)
    table = read("methods.json")
    enums: Dict[str, Enum] = {}

    messages = tuple(
        definition_of(name, node, f"messages.schema.json#/$defs/{name}", enums)
        for name, node in messages_schema["$defs"].items()
        if name not in ENVELOPE
    )
    top = {key: value for key, value in manifest_schema.items() if key != "$defs"}
    manifest = (definition_of("manifest", top, "manifest.schema.json", enums),) + tuple(
        definition_of(name, node, f"manifest.schema.json#/$defs/{name}", enums)
        for name, node in manifest_schema["$defs"].items()
    )
    # A definition both schemas make, such as localized text, is one type:
    # the messages' copy, which the manifest's types then name.
    by_name = {definition.name: definition for definition in messages}
    for definition in manifest:
        twin = by_name.get(definition.name)
        if twin is not None and (twin.alias, twin.fields) != (
            definition.alias,
            definition.fields,
        ):
            raise SchemaProblem(
                f"manifest.schema.json#/$defs/{definition.name}: defined by both schemas, differently"
            )
    manifest = tuple(d for d in manifest if d.name not in by_name)
    methods = tuple(
        Method(
            row["method"],
            row["sender"],
            row["kind"],
            row["uses"],
            row["params"],
            row["result"],
        )
        for row in table["methods"]
    )
    model = Model(
        table["protocol"],
        messages,
        manifest,
        tuple(enums[name] for name in sorted(enums)),
        methods,
    )
    check_references(messages, manifest)
    known = {definition.name for definition in messages + manifest}
    for method in methods:
        for name in (method.params, method.result):
            if name is not None and name not in known:
                raise SchemaProblem(
                    f"methods.json: {method.method} names {name}, which no schema defines"
                )
    return model


def camel_to_snake(name: str) -> str:
    """protocolVersions -> protocol_versions; notifyHUD -> notify_hud."""
    out: List[str] = []
    for index, char in enumerate(name):
        if char.isupper() and index > 0:
            before = name[index - 1]
            after = name[index + 1] if index + 1 < len(name) else ""
            if (
                before.islower()
                or before.isdigit()
                or (after.islower() and before.isupper())
            ):
                out.append("_")
        out.append(char.lower())
    return "".join(out)
