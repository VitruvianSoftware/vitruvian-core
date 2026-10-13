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

"""check_downloads.py with no network: each download is a zip made here."""

import copy
import hashlib
import io
import json
import unittest
import zipfile

import catalog_rules
import check_downloads

MANIFEST = {
    "id": "dev.vitruvian.reference",
    "name": {"en": "Reference tool"},
    "description": {"en": "Says hello."},
    "version": "0.1.0",
    "protocol": "1",
    "publisher": "VitruvianSoftware",
    "uses": ["notify"],
    "contributes": {
        "commands": [
            {"id": "hello", "title": {"en": "Say hello"}, "surfaces": ["commandBar"]}
        ]
    },
    "runtime": {"kind": "external", "exec": "bin/tool"},
}

URL = "https://github.com/VitruvianSoftware/vitruvian-sdk/releases/download/v0.9.0/reference-tool-0.1.0.zip"


def make_zip(files):
    """A zip of `files`: name to bytes, or to (bytes, Unix mode)."""
    out = io.BytesIO()
    with zipfile.ZipFile(out, "w") as archive:
        for name, content in files.items():
            data, mode = content if isinstance(content, tuple) else (content, 0o100644)
            info = zipfile.ZipInfo(name)
            info.create_system = 3
            info.external_attr = mode << 16
            archive.writestr(info, data)
    return out.getvalue()


def tool_zip(manifest=MANIFEST, extra=None):
    files = {
        "vitruvian-tool.json": json.dumps(manifest).encode(),
        "bin/tool": (b"#!/bin/sh\n", 0o100755),
    }
    files.update(extra or {})
    return make_zip(files)


def entry_for(data, **changes):
    entry = {
        "id": "dev.vitruvian.reference",
        "name": {"en": "Reference tool"},
        "publisher": "VitruvianSoftware",
        "summary": {"en": "Says hello."},
        "version": "0.1.0",
        "protocol": "1",
        "minimumAppVersion": "3.43.0",
        "source": "https://github.com/VitruvianSoftware/vitruvian-sdk",
        "download": {
            "url": URL,
            "sha256": hashlib.sha256(data).hexdigest(),
            "size": len(data),
        },
        "uses": ["notify"],
        "commands": [{"id": "hello", "title": {"en": "Say hello"}}],
    }
    entry.update(changes)
    return entry


def catalog(*tools, generated="2026-10-13T00:00:00Z"):
    return {"version": 1, "generated": generated, "tools": list(tools)}


BASE = catalog(generated="2026-10-12T00:00:00Z")


class CheckDownloadsTest(unittest.TestCase):
    def run_check(self, head, data, base=BASE):
        self.fetched = []
        self.validated = []

        def fetch(url, size):
            self.fetched.append(url)
            return data if len(data) <= size else None

        def validate(folder):
            self.validated.append(
                sorted(p.relative_to(folder).as_posix() for p in folder.rglob("*"))
            )
            return 0, "ok"

        return check_downloads.check(base, head, fetch, validate)

    def test_a_good_entry_passes(self):
        data = tool_zip()
        self.assertEqual(self.run_check(catalog(entry_for(data)), data), [])
        self.assertEqual(self.fetched, [URL])
        self.assertEqual(self.validated, [["bin", "bin/tool", "vitruvian-tool.json"]])

    def test_an_unchanged_entry_is_not_fetched(self):
        data = tool_zip()
        same = catalog(entry_for(data))
        self.assertEqual(self.run_check(same, data, base=copy.deepcopy(same)), [])
        self.assertEqual(self.fetched, [])

    def test_the_pinned_size_and_checksum(self):
        data = tool_zip()
        wrong_sum = entry_for(data)
        wrong_sum["download"]["sha256"] = "0" * 64
        self.assertIn("sha256", " ".join(self.run_check(catalog(wrong_sum), data)))
        smaller = entry_for(data)
        smaller["download"]["size"] = len(data) - 1
        self.assertIn(
            "could not be fetched, or is larger",
            " ".join(self.run_check(catalog(smaller), data)),
        )
        self.assertEqual(
            self.validated,
            [],
            "nothing is unpacked before the bytes are the pinned ones",
        )

    def test_a_zip_that_leaves_its_folder_is_never_unpacked(self):
        cases = {
            "../escaped": tool_zip(extra={"../escaped": b"x"}),
            "an absolute path": tool_zip(extra={"/tmp/escaped": b"x"}),
            "a link": tool_zip(extra={"bin/link": (b"/etc", 0o120777)}),
            "a backslash": tool_zip(extra={"bin\\tool.exe": b"x"}),
        }
        for reason, data in cases.items():
            with self.subTest(reason):
                self.assertNotEqual(
                    self.run_check(catalog(entry_for(data)), data), [], reason
                )
                self.assertEqual(self.validated, [], reason)

    def test_a_zip_with_its_manifest_in_a_folder_is_refused(self):
        data = make_zip({"tool/vitruvian-tool.json": json.dumps(MANIFEST).encode()})
        self.assertIn(
            "no vitruvian-tool.json at its top",
            " ".join(self.run_check(catalog(entry_for(data)), data)),
        )

    def test_the_manifest_must_be_what_the_entry_copies(self):
        newer = dict(MANIFEST, version="0.2.0")
        data = tool_zip(newer)
        found = " ".join(self.run_check(catalog(entry_for(data)), data))
        self.assertIn("version: the manifest says", found)
        more = dict(MANIFEST, uses=["notify", "keystrokes"])
        data = tool_zip(more)
        self.assertIn("uses:", " ".join(self.run_check(catalog(entry_for(data)), data)))

    def test_validate_is_the_judge_of_the_folder(self):
        data = tool_zip()
        found = check_downloads.check(
            BASE,
            catalog(entry_for(data)),
            lambda url, size: data,
            lambda folder: (1, "NOT OK   program: bin/tool is not executable"),
        )
        self.assertIn("vitruvian-tool validate refused it", " ".join(found))

    def test_generated_must_move_on(self):
        data = tool_zip()
        found = self.run_check(
            catalog(entry_for(data), generated="2026-10-12T00:00:00Z"), data
        )
        self.assertIn("generated is not later than main's", " ".join(found))

    def test_the_zip_rules_match_the_apps(self):
        self.assertIsNone(catalog_rules.name_problem("bin/tool"))
        self.assertIsNone(catalog_rules.name_problem("bin/"))
        for name in ["", "/abs", "~/x", "a/../b", "./a", "a//b", "a\\b", "a\x00b"]:
            with self.subTest(name=name):
                self.assertIsNotNone(catalog_rules.name_problem(name))


if __name__ == "__main__":
    unittest.main()
