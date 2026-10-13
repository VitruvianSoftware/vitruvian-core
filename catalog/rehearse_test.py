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

"""The rehearsal's lists: each scenario is the case it says it is."""

import hashlib
import io
import json
import tempfile
import unittest
import zipfile
from datetime import datetime, timezone
from pathlib import Path

import catalog_rules
import rehearse
import signing

MANIFEST = {
    "id": "dev.vitruvian.reference",
    "name": {"en": "Reference tool"},
    "description": {"en": "Says hello."},
    "version": "0.1.0",
    "protocol": "1",
    "publisher": "VitruvianSoftware",
    "uses": ["notify"],
    "contributes": {"commands": [{"id": "hello", "title": {"en": "Say hello"}}]},
    "runtime": {"kind": "external", "exec": "bin/tool"},
}
BASE = "http://127.0.0.1:8737"
WHEN = datetime(2026, 10, 12, tzinfo=timezone.utc)


class RehearseTest(unittest.TestCase):
    def setUp(self):
        self.folder = Path(tempfile.mkdtemp())
        (self.folder / "bin").mkdir()
        (self.folder / "vitruvian-tool.json").write_text(
            json.dumps(MANIFEST), encoding="utf-8"
        )
        (self.folder / "bin/tool").write_text("#!/bin/sh\n", encoding="utf-8")
        (self.folder / "bin/tool").chmod(0o755)
        self.private = rehearse.new_key()
        self.public = signing.public_key_of(self.private)

    def served(self, scenario):
        files = rehearse.build(self.folder, BASE, self.private, scenario, WHEN)
        listed = json.loads(files["/tools.json"])
        tool = listed["tools"][0]
        path = tool["download"]["url"][len(BASE) :]
        return files, tool, files.get(path)

    def manifest_in(self, data):
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            return json.loads(archive.read("vitruvian-tool.json"))

    def test_every_scenario_is_what_it_says(self):
        self.assertEqual(
            set(rehearse.SCENARIOS) - {"rollback"},
            {
                "install",
                "update",
                "not-ours",
                "mismatch",
                "not-the-tool",
                "slip",
                "unreachable",
            },
        )
        for scenario in set(rehearse.SCENARIOS) - {"rollback"}:
            files, tool, data = self.served(scenario)
            with self.subTest(scenario):
                signed = signing.verify(
                    files["/tools.json"], files["/tools.json.sig"], self.public
                )
                self.assertEqual(signed, scenario != "not-ours")
                if scenario == "unreachable":
                    self.assertIsNone(data)
                    continue
                pinned = tool["download"]["sha256"] == hashlib.sha256(data).hexdigest()
                self.assertEqual(pinned, scenario != "mismatch")
                with tempfile.TemporaryDirectory() as work:
                    path = Path(work) / "download.zip"
                    path.write_bytes(data)
                    self.assertEqual(
                        catalog_rules.zip_problems(path) != [], scenario == "slip"
                    )
                    if scenario != "slip":
                        self.assertEqual(
                            self.manifest_in(data)["version"] == tool["version"],
                            scenario != "not-the-tool",
                        )

    def test_switching_signs_a_later_list_and_rollback_serves_the_first(self):
        rehearsal = rehearse.Rehearsal(self.folder, BASE, self.private)
        first = json.loads(rehearsal.files["/tools.json"])["generated"]
        rehearsal.switch("update")
        later = json.loads(rehearsal.files["/tools.json"])["generated"]
        self.assertLess(first, later)
        rehearsal.switch("rollback")
        self.assertEqual(json.loads(rehearsal.files["/tools.json"])["generated"], first)
        self.assertTrue(
            signing.verify(
                rehearsal.files["/tools.json"],
                rehearsal.files["/tools.json.sig"],
                self.public,
            )
        )


if __name__ == "__main__":
    unittest.main()
