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
"""The generated types read every example the protocol calls valid, and give
back what they read.

protocol/examples/ is what the schemas and the Swift types are both held to
(protocol_examples_test.py, ProtocolExamplesTests.swift). Reading the same
files here holds the generated Python to them too: a field the generator
dropped or misnamed fails here, by the example's own words.
"""

import json
import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
PROTOCOL = os.path.join(HERE, "..", "..", "..", "protocol")

from vitruvian_tool_kit import METHODS, ShapeError, ToolManifest  # noqa: E402
from vitruvian_tool_kit.generated import messages  # noqa: E402


def load(name):
    with open(os.path.join(PROTOCOL, name), encoding="utf-8") as handle:
        return json.load(handle)


def type_named(name):
    title = {"empty": "EmptyObject", "error": "RPCErrorObject"}.get(
        name, name[:1].upper() + name[1:]
    )
    return getattr(messages, title)


class GeneratedTests(unittest.TestCase):
    def test_every_valid_message_reads_and_writes_back(self):
        """What is written back is what was read, less a field the schema does
        not name: the protocol says such a field is ignored."""
        table = {m.method: m for m in METHODS}
        named = {
            name: set(node.get("properties", {}))
            for name, node in load("messages.schema.json")["$defs"].items()
        }

        def known(name, value):
            return {key: item for key, item in value.items() if key in named[name]}

        read = 0
        for example in load("examples/messages.json")["examples"]:
            if not example["valid"]:
                continue
            message = example["message"]
            row = table.get(example.get("answers", message.get("method")))
            if row is None:
                continue
            with self.subTest(example["about"]):
                if "method" in message and row.params:
                    value = type_named(row.params).from_json(message.get("params"))
                    self.assertEqual(
                        value.to_json(), known(row.params, message["params"])
                    )
                    read += 1
                elif "result" in message:
                    value = type_named(row.result).from_json(message["result"])
                    self.assertEqual(
                        value.to_json(), known(row.result, message["result"])
                    )
                    read += 1
        self.assertGreater(read, 20)

    def test_a_wrong_field_is_named(self):
        with self.assertRaises(ShapeError) as raised:
            messages.NotifyHUDParams.from_json({"icon": "x", "message": 3})
        self.assertEqual(raised.exception.where, "notifyHUDParams.message")

    def test_every_valid_manifest_reads(self):
        examples = load("examples/manifests.json")
        read = 0
        for example in examples["examples"]:
            if not example["valid"]:
                continue
            manifest = dict(examples["base"])
            for key, value in example["change"].items():
                if value is None:
                    manifest.pop(key, None)
                else:
                    manifest[key] = value
            with self.subTest(example["about"]):
                ToolManifest.from_json(manifest)
                read += 1
        self.assertGreater(read, 5)


if __name__ == "__main__":
    unittest.main()
