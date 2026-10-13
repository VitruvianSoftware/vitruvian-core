#!/usr/bin/env python3
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

"""Fetches each new or changed entry of the catalog and checks it, as the app
would before it offers the tool, and then some.

    check_downloads.py --base <tools.json on main> --head catalog/tools.json \
        --validate <path to vitruvian-tool>

For each entry that is new, or differs from the same id on main: the download
is fetched, refused past its pinned size, and its size and SHA-256 compared
with the entry; the zip is read and refused when an entry would leave its
folder, is a link or is encrypted, or when it is too large; it is unpacked,
`vitruvian-tool validate` is run on it (which reads the manifest and the
folder and runs nothing), and the manifest is compared with the entry. Also:
`generated` must be later than main's whenever the tools changed.

Run by .github/workflows/catalog-check.yaml on a pull request that changes
catalog/. It needs the network; //catalog:check_downloads_test checks the
same code with none.
"""

import argparse
import hashlib
import json
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

import catalog_rules


def fetch(url, size):
    """The bytes at `url`, or None past `size` bytes or on any error."""
    try:
        with urllib.request.urlopen(url, timeout=60) as answer:
            data = answer.read(size + 1)
    except OSError:
        return None
    return data if len(data) <= size else None


def validate(tool, folder):
    """Runs `vitruvian-tool validate` on `folder`: its exit status and what it said."""
    done = subprocess.run(
        [tool, "validate", str(folder)], capture_output=True, text=True, timeout=120
    )
    return done.returncode, done.stdout + done.stderr


def check_entry(entry, fetch, validate):
    """Every problem with one entry's download."""
    data = fetch(entry["download"]["url"], entry["download"]["size"])
    if data is None:
        return ["the download could not be fetched, or is larger than its size"]
    problems = []
    if len(data) != entry["download"]["size"]:
        problems.append(
            f"the download is {len(data)} bytes, the entry says {entry['download']['size']}"
        )
    digest = hashlib.sha256(data).hexdigest()
    if digest != entry["download"]["sha256"]:
        problems.append(
            f"the download's sha256 is {digest}, the entry says {entry['download']['sha256']}"
        )
    if problems:
        return problems
    with tempfile.TemporaryDirectory() as work:
        zip_path = Path(work) / "download.zip"
        zip_path.write_bytes(data)
        problems = catalog_rules.zip_problems(zip_path)
        if problems:
            return problems
        folder = Path(work) / "tool"
        catalog_rules.unpack(zip_path, folder)
        status, said = validate(folder)
        if status != 0:
            return [f"vitruvian-tool validate refused it:\n{said}"]
        manifest = json.loads(
            (folder / "vitruvian-tool.json").read_text(encoding="utf-8")
        )
        return catalog_rules.manifest_problems(entry, manifest)


def check(base, head, fetch, validate):
    """Every problem with the entries `head` adds or changes, by entry."""
    found = []
    changed = catalog_rules.changed(base, head)
    removed = {tool["id"] for tool in base.get("tools", [])} - {
        tool["id"] for tool in head.get("tools", [])
    }
    if (changed or removed) and catalog_rules.generated(head) is not None:
        before = catalog_rules.generated(base)
        if before is not None and catalog_rules.generated(head) <= before:
            found.append(f"generated is not later than main's ({base['generated']})")
    for entry in changed:
        found.extend(
            f"{entry['id']} {entry['version']}: {problem}"
            for problem in check_entry(entry, fetch, validate)
        )
    return found


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--base", type=Path, required=True, help="tools.json as it is on main"
    )
    parser.add_argument(
        "--head", type=Path, required=True, help="tools.json as the pull request has it"
    )
    parser.add_argument("--validate", required=True, help="the vitruvian-tool command")
    args = parser.parse_args(argv)
    base = (
        json.loads(args.base.read_text(encoding="utf-8"))
        if args.base.exists()
        else {"tools": []}
    )
    head = json.loads(args.head.read_text(encoding="utf-8"))
    for entry in catalog_rules.changed(base, head):
        print(f"checking {entry['id']} {entry['version']}: {entry['download']['url']}")
    problems = check(base, head, fetch, lambda folder: validate(args.validate, folder))
    for problem in problems:
        print(f"NOT OK   {problem}")
    if not problems:
        print("ok       every new or changed entry is the tool its download holds")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
