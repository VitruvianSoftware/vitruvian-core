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

"""catalog/tools.json against its schema and its rules, with no network.

Run by `bazel test //catalog:catalog_test`, on every pull request. The check
that fetches each changed entry's download is .github/workflows/catalog-check.yaml.
"""

import copy
import json
import re
import unittest
from pathlib import Path

import catalog_rules
from jsonschema import Draft202012Validator

HERE = Path(__file__).resolve().parent

GOOD = {
    "id": "dev.vitruvian.reference",
    "name": {"en": "Reference tool"},
    "publisher": "VitruvianSoftware",
    "summary": {"en": "Says hello. The smallest tool that speaks protocol 1."},
    "version": "0.1.0",
    "protocol": "1",
    "minimumAppVersion": "3.43.0",
    "source": "https://github.com/VitruvianSoftware/vitruvian-sdk",
    "download": {
        "url": "https://github.com/VitruvianSoftware/vitruvian-sdk/releases/download/v0.9.0/reference-tool-0.1.0.zip",
        "sha256": "0" * 64,
        "size": 4096,
    },
    "uses": ["notify"],
    "commands": [{"id": "hello", "title": {"en": "Say hello"}}],
}


def catalog_with(*tools):
    return {"version": 1, "generated": "2026-10-12T00:00:00Z", "tools": list(tools)}


def entry(**changes):
    tool = copy.deepcopy(GOOD)
    for path, value in changes.items():
        target = tool
        keys = path.split("__")
        for key in keys[:-1]:
            target = target[key]
        target[keys[-1]] = value
    return tool


class CatalogTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.schema = json.loads(
            (HERE / "catalog.schema.json").read_text(encoding="utf-8")
        )
        cls.validator = Draft202012Validator(cls.schema)

    def refused(self, catalog):
        """Every reason the schema or the rules give, as one list."""
        found = [error.message for error in self.validator.iter_errors(catalog)]
        return found or catalog_rules.problems(catalog)

    def test_the_catalog_is_well_formed(self):
        _, catalog = catalog_rules.load(HERE / "tools.json")
        self.assertEqual(self.refused(catalog), [])

    def test_the_schema_is_a_schema(self):
        Draft202012Validator.check_schema(self.schema)

    def test_a_good_entry_passes(self):
        self.assertEqual(self.refused(catalog_with(GOOD)), [])
        self.assertEqual(
            self.refused(catalog_with(entry(panels=["island", "settings"]))), []
        )

    def test_each_rule_refuses(self):
        cases = {
            "an id with no dot": entry(id="reference"),
            "a version that is not semver": entry(version="1.0"),
            "an app version that is not semver": entry(minimumAppVersion="3.43"),
            "a protocol the app has not": entry(protocol="3"),
            "a summary with no English": entry(summary={"fr": "Bonjour"}),
            "a download over http": entry(
                download__url=GOOD["download"]["url"].replace("https", "http")
            ),
            "a download from another owner": entry(
                download__url="https://github.com/someone/tool/releases/download/v1/tool.zip"
            ),
            "a download that walks up": entry(
                download__url="https://github.com/VitruvianSoftware/x/releases/download/../../someone/t.zip"
            ),
            "a download that is no zip": entry(
                download__url=GOOD["download"]["url"][:-4] + ".tar.gz"
            ),
            "a checksum in capitals": entry(download__sha256="A" * 64),
            "a checksum too short": entry(download__sha256="0" * 63),
            "an empty download": entry(download__size=0),
            "a download over 256 MB": entry(download__size=268435457),
            "a service the protocol has not": entry(uses=["camera"]),
            "a panel placement the protocol has not": entry(panels=["menubar"]),
            "a panel placement listed twice": entry(panels=["island", "island"]),
            "a field the schema does not name": entry(homepage="https://example.com"),
            "two commands with one id": entry(
                commands=[
                    {"id": "hello", "title": {"en": "A"}},
                    {"id": "hello", "title": {"en": "B"}},
                ]
            ),
        }
        for reason, tool in cases.items():
            with self.subTest(reason):
                self.assertNotEqual(self.refused(catalog_with(tool)), [], reason)
        twice = catalog_with(GOOD, copy.deepcopy(GOOD))
        self.assertIn("listed twice", " ".join(self.refused(twice)))
        undated = catalog_with(GOOD)
        undated["generated"] = "yesterday"
        self.assertNotEqual(self.refused(undated), [])

    def test_the_app_is_built_with_this_key(self):
        swift = Path(
            "apps/desktop/vitruvian/Sources/Vitruvian/Services/Platform/External/Catalogue/CatalogueSigning.swift"
        )
        found = re.search(
            r'package static let publicKey = "([^"]*)"',
            swift.read_text(encoding="utf-8"),
        )
        self.assertIsNotNone(found, "CatalogueSigning.swift declares publicKey")
        self.assertEqual(
            found.group(1),
            (HERE / "public-key.txt").read_text(encoding="ascii").strip(),
        )

    def test_versions_sort_as_semver(self):
        order = ["0.9.0", "1.0.0-beta", "1.0.0", "1.0.1", "1.10.0", "2.0.0"]
        self.assertEqual(sorted(order, key=catalog_rules.semver), order)
        self.assertIsNone(catalog_rules.semver("01.0.0"))

    def test_only_new_or_changed_entries_are_fetched(self):
        newer = entry(version="0.2.0")
        other = entry(id="dev.vitruvian.other")
        self.assertEqual(
            catalog_rules.changed(catalog_with(GOOD), catalog_with(GOOD, other)),
            [other],
        )
        self.assertEqual(
            catalog_rules.changed(catalog_with(GOOD), catalog_with(newer)), [newer]
        )
        self.assertEqual(
            catalog_rules.changed(catalog_with(GOOD), catalog_with(GOOD)), []
        )


if __name__ == "__main__":
    unittest.main()
