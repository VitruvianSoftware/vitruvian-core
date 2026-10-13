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
import json
import os
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

    def test_every_emitter_is_found(self):
        self.assertEqual(
            [e.NAME for e in sdk_codegen.emitters()],
            ["go", "python", "rust", "typescript"],
        )


if __name__ == "__main__":
    unittest.main()
