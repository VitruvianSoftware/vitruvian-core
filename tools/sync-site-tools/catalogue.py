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

"""The catalog's part of the website: `_data/tools.yml`, which the page
tools/catalog.html lists, written from catalog/tools.json.

The signed files the app reads (/tools/catalog/tools.json and .sig) are not
written here: they need the signing key, and the workflow catalog-publish
writes them after a change merges.
"""

import json

CATALOG = "catalog/tools.json"
PUBLIC_KEY = "catalog/public-key.txt"
DATA = "apps/web/vitruviansoftware-dev/_data/tools.yml"

# What a tool says it uses, in the words the app's agreement sheet uses
# (ExternalToolStrings, in English).
USES = {
    "notify": "Show messages and play the alert sound",
    "open": "Open links",
    "clipboard.read": "Read the clipboard",
    "clipboard.write": "Write to the clipboard",
    "keystrokes": "Paste and press menu commands in other apps",
    "processes": "End other programs",
    "storage": "Save its own settings",
}


def size(count):
    """Bytes as a person reads them: 4 KB, 1.8 MB."""
    if count < 1_048_576:
        return f"{max(1, round(count / 1024))} KB"
    return f"{count / 1_048_576:.1f} MB"


def scalar(value):
    """A YAML scalar: JSON's double-quoted string is one."""
    return json.dumps(value, ensure_ascii=False)


def render(catalog, public_key):
    lines = [
        "# Written by tools/sync-site-tools from catalog/tools.json. Do not edit:",
        "#   bazel run //tools/sync-site-tools:sync",
        f"generated: {scalar(catalog['generated'])}",
        f"public_key: {scalar(public_key)}",
    ]
    tools = catalog.get("tools", [])
    if not tools:
        lines.append("tools: []")
    else:
        lines.append("tools:")
    for tool in tools:
        lines += [
            f"  - id: {scalar(tool['id'])}",
            f"    name: {scalar(tool['name']['en'])}",
            f"    publisher: {scalar(tool['publisher'])}",
            f"    summary: {scalar(tool['summary']['en'])}",
            f"    version: {scalar(tool['version'])}",
            f"    source: {scalar(tool['source'])}",
            f"    download: {scalar(tool['download']['url'])}",
            f"    size: {scalar(size(tool['download']['size']))}",
            f"    sha256: {scalar(tool['download']['sha256'])}",
        ]
        uses = [USES[name] for name in tool.get("uses", []) if name in USES]
        lines.append("    uses: []" if not uses else "    uses:")
        lines += [f"      - {scalar(words)}" for words in uses]
    return ("\n".join(lines) + "\n").encode("utf-8")


def outputs(root):
    """Each file this part of the site is made of, by its path from the
    repository's root, and what it must hold."""
    catalog = json.loads((root / CATALOG).read_text(encoding="utf-8"))
    public_key = (root / PUBLIC_KEY).read_text(encoding="ascii").strip()
    return {DATA: render(catalog, public_key)}
