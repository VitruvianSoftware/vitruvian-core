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
"""The protocol's examples, judged by its schemas.

Three things are checked, and the Swift tests check the same three against the
Swift types (Tests/VitruvianToolProtocolTests/ProtocolExamplesTests.swift), so
the schemas and the types cannot drift apart unnoticed:

  1. every example the files call valid passes its schema, and every example
     they call invalid fails it;
  2. the valid examples between them use every field the schemas declare, so
     a field one side has and the other lacks shows up as a failure there;
  3. methods.json and messages.schema.json name the same messages.
"""

import json
import os
import sys

from jsonschema import Draft202012Validator

HERE = os.path.dirname(os.path.abspath(__file__))
ENVELOPES = ("request", "notice", "result", "failure")
REFUSALS_WITH_DATA = (-32001, -32003)


def load(name):
    with open(os.path.join(HERE, name), encoding="utf-8") as handle:
        return json.load(handle)


def cover(node, instance, root, seen, where):
    """Notes each declared field `instance` uses, as (definition, field)."""
    if "$ref" in node:
        where = node["$ref"].rsplit("/", 1)[-1]
        node = root["$defs"][where]
    if isinstance(instance, dict):
        for key, child in node.get("properties", {}).items():
            if key in instance:
                seen.add((where, key))
                cover(child, instance[key], root, seen, where)
    elif isinstance(instance, list) and "items" in node:
        for item in instance:
            cover(node["items"], item, root, seen, where)


def declared(root, top):
    """Every (definition, field) the schema declares."""
    pairs = {(top, key) for key in root.get("properties", {})}
    for name, node in root.get("$defs", {}).items():
        pairs |= {(name, key) for key in node.get("properties", {})}
    return pairs


def unused(root, top, seen):
    return [
        f"no valid example uses {where}.{key}"
        for where, key in sorted(declared(root, top) - seen)
    ]


def manifest_problems():
    schema = load("manifest.schema.json")
    Draft202012Validator.check_schema(schema)
    validator = Draft202012Validator(schema)
    file = load("examples/manifests.json")
    problems, seen = [], set()
    for example in file["examples"]:
        manifest = dict(file["base"])
        for key, value in example["change"].items():
            if value is None:
                manifest.pop(key, None)
            else:
                manifest[key] = value
        accepted = validator.is_valid(manifest)
        expected = example["valid"] or example.get("schema") is False
        if accepted != expected:
            problems.append(
                f"manifest '{example['about']}': the schema says {accepted}, the example {expected}"
            )
        if example["valid"]:
            cover(schema, manifest, schema, seen, "manifest")
        elif "problem" not in example:
            problems.append(
                f"manifest '{example['about']}': an invalid example names its problem"
            )
    reference = load("../conformance/reference-tool/vitruvian-tool.json")
    if not validator.is_valid(reference):
        problems.append("the reference tool's manifest does not pass the schema")
    return problems + unused(schema, "manifest", seen)


def kind_of(message):
    if "method" in message:
        return "request" if "id" in message else "notice"
    return "failure" if "error" in message else "result"


def message_problems():
    schema = load("messages.schema.json")
    Draft202012Validator.check_schema(schema)
    whole = Draft202012Validator(schema)
    table = {row["method"]: row for row in load("methods.json")["methods"]}
    problems, seen, shown, answered = [], set(), set(), set()

    def part(name):
        return Draft202012Validator(
            {"$ref": f"#/$defs/{name}", "$defs": schema["$defs"]}
        )

    for example in load("examples/messages.json")["examples"]:
        message, about = example["message"], example["about"]
        accepted = whole.is_valid(message)
        kind = kind_of(message)
        row = table.get(example.get("answers", message.get("method")))
        if accepted and kind == "result":
            accepted = part(row["result"]).is_valid(message["result"])
        if accepted != example["valid"]:
            problems.append(
                f"message '{about}': the schema says {accepted}, the example {example['valid']}"
            )
        if not example["valid"]:
            continue
        cover(schema, message, schema, seen, "message")
        cover({"$ref": f"#/$defs/{kind}"}, message, schema, seen, kind)
        if kind in ("request", "notice") and row:
            shown.add(row["method"])
            if row["kind"] != kind:
                problems.append(
                    f"message '{about}': methods.json calls {row['method']} a {row['kind']}"
                )
            if row["params"]:
                cover(
                    {"$ref": f"#/$defs/{row['params']}"},
                    message["params"],
                    schema,
                    seen,
                    row["params"],
                )
        if kind == "result":
            answered.add(row["method"])
            cover(
                {"$ref": f"#/$defs/{row['result']}"},
                message["result"],
                schema,
                seen,
                row["result"],
            )
        if kind == "failure" and message["error"]["code"] in REFUSALS_WITH_DATA:
            cover(
                {"$ref": "#/$defs/refusalData"},
                message["error"]["data"],
                schema,
                seen,
                "refusalData",
            )

    for method, row in table.items():
        if method not in shown:
            problems.append(f"no valid example shows {method}")
        if row["kind"] == "request" and method not in answered:
            problems.append(f"no valid example answers {method}")
        if (row["kind"] == "request") != (row["result"] is not None):
            problems.append(f"{method}: a request has a result and a notice has none")
        for name in (row["params"], row["result"]):
            if name and name not in schema["$defs"]:
                problems.append(
                    f"{method}: messages.schema.json has no definition {name}"
                )
    named = {
        name
        for row in table.values()
        for name in (row["params"], row["result"])
        if name
    }
    for name in schema["$defs"]:
        if name.endswith(("Params", "Result")) and name not in named:
            problems.append(f"methods.json names no message that carries {name}")
    for envelope in ("request", "notice"):
        bound = {
            branch["if"]["properties"]["method"]["const"]: branch["then"]["properties"][
                "params"
            ]["$ref"]
            for branch in schema["$defs"][envelope]["allOf"]
        }
        wanted = {
            method: f"#/$defs/{row['params']}"
            for method, row in table.items()
            if row["kind"] == envelope and row["params"]
        }
        if bound != wanted:
            problems.append(
                f"the {envelope} definition ties methods to params otherwise than methods.json does"
            )
    return problems + unused(schema, "message", seen)


def main():
    problems = manifest_problems() + message_problems()
    for problem in problems:
        print(problem, file=sys.stderr)
    print("protocol examples: " + ("FAILED" if problems else "OK"))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
