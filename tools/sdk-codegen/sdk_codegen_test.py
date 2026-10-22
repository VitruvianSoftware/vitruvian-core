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
"""The generator reads all of the protocol, and a change to it changes what it writes.

    sdk_codegen_test.py

Run from the repository's root, or by Bazel, which gives it the protocol's
files and the kits' generated files. It writes only in a temporary folder.
"""

import ast
import builtins
import json
import os
import re
import shutil
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import model  # noqa: E402
import sdk_codegen  # noqa: E402

PACKAGE = os.path.join("packages", "vitruvian-sdk")


def read(name):
    with open(os.path.join(PACKAGE, "protocol", name), encoding="utf-8") as handle:
        return json.load(handle)


class ModelTests(unittest.TestCase):
    def setUp(self):
        self.model = model.load(os.path.join(PACKAGE, "protocol"))

    def test_every_method_of_the_table_is_in_the_model(self):
        table = [row["method"] for row in read("methods.json")["methods"]]
        self.assertEqual([m.method for m in self.model.methods], table)
        for method in self.model.methods:
            for name in (method.params, method.result):
                if name is not None:
                    self.model.definition(name)

    def test_every_field_of_the_manifest_is_in_the_model(self):
        schema = read("manifest.schema.json")
        wanted = {("manifest", key) for key in schema["properties"]}
        for name, node in schema["$defs"].items():
            wanted |= {(name, key) for key in node.get("properties", {})}
        have = {(d.name, f.name) for d in self.model.manifest for f in d.fields}
        self.assertEqual(have, wanted)

    def test_every_payload_of_the_messages_is_in_the_model(self):
        schema = read("messages.schema.json")
        wanted = {
            (name, key)
            for name, node in schema["$defs"].items()
            if name not in model.ENVELOPE
            for key in node.get("properties", {})
        }
        have = {(d.name, f.name) for d in self.model.messages for f in d.fields}
        self.assertEqual(have, wanted)

    def test_protocol_2_is_in_the_model(self):
        """Each kind of block is a definition of its own, and uiBlock names
        them as its variants by the value of `type`; a tool's text is a
        string or a map of languages; the manifest has panels, a status and
        options on a preference; the six ui messages are in the table."""
        block = self.model.definition("uiBlock")
        self.assertEqual(block.tag, "type")
        self.assertEqual(
            [kind for kind, _ in block.variants],
            [
                "text",
                "heading",
                "row",
                "button",
                "toggle",
                "field",
                "list",
                "progress",
                "image",
                "divider",
                "link",
                "spacer",
                "choice",
                "chips",
            ],
        )
        for kind, name in block.variants:
            self.assertEqual(name, kind + "Block")
            self.assertIsNone(self.model.definition(name).alias)
        self.assertEqual(self.model.definition("uiText").alias.kind, "text")
        self.assertEqual(self.model.definition("uiText").alias.ref, "localizedText")
        self.assertEqual(self.model.title("uiTree"), "UITree")
        self.assertEqual(self.model.title("uiOpenParams"), "UIOpenParams")
        self.assertIn("panel", [d.name for d in self.model.manifest])
        self.assertIn(
            "panels", [f.name for f in self.model.definition("contributes").fields]
        )
        self.assertIn(
            "status", [f.name for f in self.model.definition("contributes").fields]
        )
        self.assertIn(
            "options", [f.name for f in self.model.definition("preference").fields]
        )
        self.assertIn(
            "slot", [f.name for f in self.model.definition("contributes").fields]
        )
        self.assertIn(
            "picker", [f.name for f in self.model.definition("preference").fields]
        )
        self.assertIn(
            "features",
            [f.name for f in self.model.definition("initializeParams").fields],
        )
        self.assertEqual(
            {e.name: e.values for e in self.model.enums if e.name.startswith("S")},
            {
                "Service": (
                    "notify",
                    "open",
                    "clipboard.read",
                    "clipboard.write",
                    "keystrokes",
                    "processes",
                    "storage",
                ),
                "SlotPlacement": ("agents",),
                "StatusPlacement": ("island",),
                "StatusState": ("none", "ok", "busy", "attention", "failure"),
                "Surface": ("commandBar", "radial", "quickPanel", "shortcut"),
            },
        )
        self.assertEqual(
            {e.name: e.values for e in self.model.enums if e.name.startswith("P")},
            {
                "PanelKind": ("blocks", "web"),
                "PanelPlacement": ("island", "settings", "window"),
                "PreferencePicker": ("folder",),
                "PreferenceType": ("string", "boolean", "integer", "number"),
                "ProtocolVersion": ("1", "2"),
            },
        )
        self.assertEqual(
            [m.method for m in self.model.methods if m.method.startswith("ui/")],
            [
                "ui/open",
                "ui/event",
                "ui/close",
                "ui/render",
                "ui/badge",
                "ui/status",
                "ui/slot",
                "ui/dock",
            ],
        )

    def test_a_variant_whose_kind_is_not_defined_stops_the_generator(self):
        node = {
            "type": "object",
            "required": ["type"],
            "properties": {"type": {"type": "string"}},
            "allOf": [
                {
                    "if": {"properties": {"type": {"const": "chart"}}},
                    "then": {"$ref": "#/$defs/chartBlock"},
                },
            ],
        }
        definition = model.definition_of("block", node, "here", {})
        self.assertEqual(definition.variants, (("chart", "chartBlock"),))
        with self.assertRaises(model.SchemaProblem) as raised:
            model.check_references((definition,), ())
        self.assertIn("chartBlock", str(raised.exception))

    def test_a_list_of_names_with_no_name_stops_the_generator(self):
        node = {"type": "object", "properties": {"color": {"enum": ["red", "blue"]}}}
        with self.assertRaises(model.SchemaProblem) as raised:
            model.definition_of("paint", node, "here", {})
        self.assertIn("add ('paint', 'color') to ENUMS", str(raised.exception))


class OutputTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.mkdtemp(prefix="sdk-codegen-")
        self.package = os.path.join(self.folder, "vitruvian-sdk")
        # Copied without their modes: Bazel hands them over read-only.
        shutil.copytree(
            os.path.join(PACKAGE, "protocol"),
            os.path.join(self.package, "protocol"),
            copy_function=shutil.copyfile,
        )
        for folder in ("kits", "go"):
            shutil.copytree(
                os.path.join(PACKAGE, folder),
                os.path.join(self.package, folder),
                copy_function=shutil.copyfile,
            )

    def tearDown(self):
        shutil.rmtree(self.folder, ignore_errors=True)

    def test_the_committed_files_are_what_it_writes(self):
        self.assertEqual(sdk_codegen.check(self.package), 0)

    def test_a_change_to_a_schema_changes_what_it_writes(self):
        before = sdk_codegen.generate(self.package)
        path = os.path.join(self.package, "protocol", "messages.schema.json")
        with open(path, encoding="utf-8") as handle:
            schema = json.load(handle)
        schema["$defs"]["notifyHUDParams"]["properties"]["seconds"] = {
            "description": "How long the message stays.",
            "type": "number",
        }
        with open(path, "w", encoding="utf-8") as handle:
            json.dump(schema, handle)
        after = sdk_codegen.generate(self.package)
        changed = sorted(p for p in after if after[p] != before[p])
        self.assertEqual(
            changed,
            [
                "go/toolkit/protocol_gen.go",
                "kits/python/vitruvian_tool_kit/generated/messages.py",
                "kits/python/vitruvian_tool_kit/generated/methods.py",
                "kits/rust/src/generated/mod.rs",
                "kits/typescript/src/generated/messages.ts",
            ],
        )
        self.assertIn("Seconds *float64", after["go/toolkit/protocol_gen.go"])
        self.assertIn(
            "pub seconds: Option<f64>", after["kits/rust/src/generated/mod.rs"]
        )
        self.assertIn(
            "seconds?: number;", after["kits/typescript/src/generated/messages.ts"]
        )
        self.assertIn(
            "seconds: Optional[float] = None",
            after["kits/python/vitruvian_tool_kit/generated/messages.py"],
        )
        self.assertEqual(
            sdk_codegen.check(self.package),
            1,
            "the committed files are now out of date",
        )

    def test_a_file_no_emitter_writes_is_caught(self):
        stray = os.path.join(
            self.package, "kits", "python", "vitruvian_tool_kit", "generated", "old.py"
        )
        with open(stray, "w", encoding="utf-8") as handle:
            handle.write("# left behind\n")
        self.assertEqual(sdk_codegen.check(self.package), 1)

    def test_the_python_it_writes_is_python_3_9(self):
        for path, text in sdk_codegen.generate(self.package).items():
            if path.endswith(".py"):
                ast.parse(text, filename=path, feature_version=(3, 9))

    def test_every_reader_the_manifest_files_call_is_imported(self):
        """The manifest's readers call the shared readers of messages.py and
        messages.ts, one for each kind of field. A kind the manifest had no
        field of before (a boolean, `contributes.status.activity`) must be
        imported too, or the file does not compile or run."""
        files = sdk_codegen.generate(self.package)
        tree = ast.parse(files["kits/python/vitruvian_tool_kit/generated/manifest.py"])
        imported = {
            alias.name
            for node in tree.body
            if isinstance(node, ast.ImportFrom)
            for alias in node.names
        }
        defined = {
            node.name
            for node in ast.walk(tree)
            if isinstance(node, (ast.ClassDef, ast.FunctionDef))
        }
        called = {
            node.func.id
            for node in ast.walk(tree)
            if isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
        }
        arguments = {
            argument.arg
            for node in ast.walk(tree)
            if isinstance(node, ast.FunctionDef)
            for argument in node.args.args
        }
        self.assertIn("_boolean", called, "contributes.status.activity is a boolean")
        self.assertEqual(
            sorted(called - imported - defined - arguments - set(dir(builtins))), []
        )

        text = files["kits/typescript/src/generated/manifest.ts"]
        head, _, body = text.partition('} from "./messages.js";')
        imported = set(re.findall(r"^  (?:type )?(\w+),$", head, re.MULTILINE))
        defined = set(re.findall(r"function (\w+)\(", body))
        called = set(re.findall(r"\b((?:expect|read)\w*)\(", body))
        self.assertIn(
            "expectBoolean", called, "contributes.status.activity is a boolean"
        )
        self.assertEqual(sorted(called - imported - defined), [])
        # And nothing is imported that the file never calls: the linter
        # fails an unused import.
        readers = {name for name in imported if re.match(r"(expect|read)\w*$", name)}
        self.assertEqual(sorted(readers - called), [])

    def test_every_name_a_python_call_uses_is_imported(self):
        """A call's arguments name their types, a closed list of names
        among them: each is imported from messages.py, so the file means
        what it says to a type checker and to `typing.get_type_hints`."""
        text = sdk_codegen.generate(self.package)[
            "kits/python/vitruvian_tool_kit/generated/methods.py"
        ]
        tree = ast.parse(text)
        imported = {
            alias.name
            for node in tree.body
            if isinstance(node, ast.ImportFrom)
            for alias in node.names
        }
        defined = {
            node.name
            for node in tree.body
            if isinstance(node, (ast.ClassDef, ast.FunctionDef))
        } | {
            target.id
            for node in tree.body
            if isinstance(node, (ast.Assign, ast.AnnAssign))
            for target in (
                node.targets if isinstance(node, ast.Assign) else [node.target]
            )
            if isinstance(target, ast.Name)
        }
        named = set()
        for node in ast.walk(tree):
            if isinstance(node, ast.FunctionDef):
                for argument in node.args.args:
                    if argument.annotation is not None:
                        named |= {
                            part.id
                            for part in ast.walk(argument.annotation)
                            if isinstance(part, ast.Name)
                        }
        self.assertIn("StatusState", named, "ui/status takes a closed list of names")
        self.assertEqual(
            sorted(named - imported - defined - {"str", "int", "bool", "float"}), []
        )

    def test_every_emitter_is_found(self):
        self.assertEqual(
            [e.NAME for e in sdk_codegen.emitters()],
            ["go", "python", "rust", "typescript"],
        )


if __name__ == "__main__":
    unittest.main()
