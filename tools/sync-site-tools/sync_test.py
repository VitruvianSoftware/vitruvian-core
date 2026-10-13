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

"""The Tools section of the website is what sync.py writes, and the catalog's
part of it says what catalog/tools.json says."""

import json
import unittest
from pathlib import Path

import catalogue
import sync

ROOT = Path(".")

ENTRY = {
    "id": "dev.vitruvian.reference",
    "name": {"en": "Reference tool", "fr": "Outil de référence"},
    "publisher": "VitruvianSoftware",
    "summary": {"en": "Says “hello”."},
    "version": "0.1.0",
    "protocol": "1",
    "minimumAppVersion": "3.43.0",
    "source": "https://github.com/VitruvianSoftware/vitruvian-sdk",
    "download": {
        "url": "https://github.com/VitruvianSoftware/x/releases/download/v1/x.zip",
        "sha256": "ab" * 32,
        "size": 1834021,
    },
    "uses": ["notify", "storage"],
    "commands": [],
}


class InSyncTest(unittest.TestCase):
    def test_the_committed_files_are_what_sync_writes(self):
        self.assertEqual(
            sync.stale(ROOT), [], "run: bazel run //tools/sync-site-tools:sync"
        )

    def test_an_entry_as_the_page_reads_it(self):
        text = catalogue.render(
            {"generated": "2026-11-02T10:00:00Z", "tools": [ENTRY]}, "KEY="
        ).decode()
        self.assertEqual(
            text.splitlines()[2:],
            [
                'generated: "2026-11-02T10:00:00Z"',
                'public_key: "KEY="',
                "tools:",
                '  - id: "dev.vitruvian.reference"',
                '    name: "Reference tool"',
                '    publisher: "VitruvianSoftware"',
                '    summary: "Says “hello”."',
                '    version: "0.1.0"',
                '    source: "https://github.com/VitruvianSoftware/vitruvian-sdk"',
                '    download: "https://github.com/VitruvianSoftware/x/releases/download/v1/x.zip"',
                '    size: "1.7 MB"',
                '    sha256: "' + "ab" * 32 + '"',
                "    uses:",
                '      - "Show messages and play the alert sound"',
                '      - "Save its own settings"',
            ],
        )
        self.assertIn(
            "tools: []",
            catalogue.render(
                {"generated": "2026-11-02T10:00:00Z", "tools": []}, "K"
            ).decode(),
        )
        self.assertEqual(catalogue.size(4000), "4 KB")

    def test_every_service_has_its_words(self):
        schema = json.loads(
            (ROOT / "catalog/catalog.schema.json").read_text(encoding="utf-8")
        )
        services = schema["$defs"]["tool"]["properties"]["uses"]["items"]["enum"]
        self.assertEqual(sorted(catalogue.USES), sorted(services))


if __name__ == "__main__":
    unittest.main()
