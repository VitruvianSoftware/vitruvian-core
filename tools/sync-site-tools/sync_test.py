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
import tempfile
import unittest
from pathlib import Path

import catalogue
import registry
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

    def test_no_copied_file_is_bumped_by_a_release(self):
        """A release bumps the version in each of release-please's
        extra-files. A copy of one of them is stale the moment the release's
        pull request opens, and that pull request is red until someone runs
        sync on a branch release-please rewrites: vitruvian-sdk 0.11.0."""
        config = json.loads(
            (ROOT / "packages/vitruvian-sdk/release-please-config.json").read_text(
                encoding="utf-8"
            )
        )
        bumped = {
            entry if isinstance(entry, str) else entry["path"]
            for entry in config["packages"]["packages/vitruvian-sdk"]["extra-files"]
        }
        self.assertEqual(
            sorted(bumped & set(sync.sources())),
            [],
            "a release bumps a file the site copies: the release's PR fails in_sync_test",
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

    def test_registry_discovers_all_plugins_and_renders_marketplaces(self):
        extensions = registry.discover_all(ROOT)
        ids = [ext["id"] for ext in extensions]
        for expected in (
            "ext-marketplace",
            "gh-watch",
            "worktree-band",
            "ralph-loop",
            "hookify",
            "security-guidance",
            "receipts-report",
            "live-context",
            "savvy-fleet",
            "mcp-roborock",
            "nexus-agent",
            "mcp-slack",
            "devx",
        ):
            self.assertIn(expected, ids)

        claude_mp = json.loads(
            registry.render_claude_marketplace_json(extensions).decode("utf-8")
        )
        claude_names = [p["name"] for p in claude_mp["plugins"]]
        self.assertIn("ext-marketplace", claude_names)
        self.assertIn("gh-watch", claude_names)
        self.assertIn("mcp-roborock", claude_names)

        ai_cat = json.loads(registry.render_ai_catalog_json(extensions).decode("utf-8"))
        self.assertEqual(len(ai_cat["extensions"]), len(extensions))

    def test_registry_ignores_release_please_version_bumps(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp_root = Path(tmp)
            pdir = tmp_root / "apps/desktop/antigravity/plugins/sample-ext"
            (pdir / ".claude-plugin").mkdir(parents=True)
            (pdir / "skills/sample-ext").mkdir(parents=True)
            (pdir / "skills/sample-ext/SKILL.md").write_text(
                "# skill\n", encoding="utf-8"
            )
            (pdir / ".claude-plugin/plugin.json").write_text(
                json.dumps({"name": "sample-ext", "description": "Sample"}),
                encoding="utf-8",
            )
            (pdir / "plugin.json").write_text(
                json.dumps(
                    {"name": "sample-ext", "version": "0.1.0", "description": "Sample"}
                ),
                encoding="utf-8",
            )
            before = registry.discover_plugin_dir(tmp_root, pdir, "antigravity")
            (pdir / "plugin.json").write_text(
                json.dumps(
                    {"name": "sample-ext", "version": "0.2.0", "description": "Sample"}
                ),
                encoding="utf-8",
            )
            after = registry.discover_plugin_dir(tmp_root, pdir, "antigravity")
            self.assertEqual(before, after)


if __name__ == "__main__":
    unittest.main()
