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

"""//catalog:bump with no network: releases made in a folder, with fake zips
built here, and the real tools.json and sources.json copied beside them."""

import copy
import hashlib
import io
import json
import shutil
import tempfile
import unittest
import zipfile
from pathlib import Path

import bump
import catalog_rules
import catalogue

HERE = Path(__file__).resolve().parent
NOW = "2030-01-02T03:04:05Z"
HS = "dev.vitruvian.homespeaker"


def real_catalog():
    return json.loads((HERE / "tools.json").read_text(encoding="utf-8"))


def entry_of(catalog, tool_id):
    return next(t for t in catalog["tools"] if t["id"] == tool_id)


def manifest_for(tool_id, version, **changes):
    """A manifest that says what the real entry says, at `version`."""
    entry = entry_of(real_catalog(), tool_id)
    manifest = {
        "id": tool_id,
        "name": entry["name"],
        "description": entry["summary"],
        "version": version,
        "protocol": entry["protocol"],
        "publisher": entry["publisher"],
        "uses": list(entry["uses"]),
        "contributes": {
            "commands": [dict(c, surfaces=["commandBar"]) for c in entry["commands"]],
            "panels": [
                {"id": p, "title": {"en": "x"}, "placement": p}
                for p in entry.get("panels", [])
            ],
        },
        "runtime": {"kind": "external", "exec": "bin/tool"},
    }
    manifest.update(changes)
    return manifest


def zip_of(manifest, extra=None):
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as archive:
        if manifest is not None:
            archive.writestr("vitruvian-tool.json", json.dumps(manifest))
        archive.writestr("bin/tool", "#!/bin/sh\necho fake tool\n")
        for name, data in (extra or {}).items():
            archive.writestr(name, data)
    return buffer.getvalue()


class Fixture:
    """A repository (the catalog and the website's data) and a release
    folder, both in a temporary folder."""

    def __init__(self, test):
        self.dir = Path(tempfile.mkdtemp())
        test.addCleanup(shutil.rmtree, self.dir)
        self.root = self.dir / "repo"
        (self.root / "catalog").mkdir(parents=True)
        for name in (
            "tools.json",
            "catalog.schema.json",
            "public-key.txt",
            "sources.json",
        ):
            shutil.copy(HERE / name, self.root / "catalog" / name)
        for path, data in catalogue.outputs(self.root).items():
            (self.root / path).parent.mkdir(parents=True, exist_ok=True)
            (self.root / path).write_bytes(data)
        self.release = self.dir / "release"
        self.release.mkdir()

    def publish(
        self, name, data, sidecar=True, digest=None, size=None, sidecar_text=None
    ):
        """Attaches `data` as `name`, with its .sha256, as a release does."""
        sha = hashlib.sha256(data).hexdigest()
        assets = [
            {
                "id": 1,
                "name": name,
                "size": len(data) if size is None else size,
                "digest": "sha256:" + sha if digest is None else digest,
            }
        ]
        (self.release / name).write_bytes(data)
        if sidecar:
            text = sidecar_text if sidecar_text is not None else f"{sha}  {name}\n"
            (self.release / (name + ".sha256")).write_text(text)
            assets.append({"id": 2, "name": name + ".sha256", "size": len(text)})
        self.meta(assets=assets)
        return sha

    def meta(self, **fields):
        path = self.release / "release.json"
        meta = json.loads(path.read_text()) if path.exists() else {"draft": False}
        meta.update(fields)
        path.write_text(json.dumps(meta))

    def files(self):
        return {
            p: p.read_bytes()
            for p in (
                self.root / "catalog" / "tools.json",
                self.root / catalogue.DATA,
            )
        }

    def run(self, tool_id, tag):
        out = self.dir / "result.json"
        status = bump.main(
            [
                "--id",
                tool_id,
                "--tag",
                tag,
                "--release-dir",
                str(self.release),
                "--root",
                str(self.root),
                "--now",
                NOW,
                "--result-out",
                str(out),
            ]
        )
        return status, json.loads(out.read_text())

    def catalog(self):
        return json.loads((self.root / "catalog" / "tools.json").read_text())


class FormatTest(unittest.TestCase):
    def test_tools_json_is_written_as_it_is_kept(self):
        raw = (HERE / "tools.json").read_text(encoding="utf-8")
        self.assertEqual(bump.dumps(json.loads(raw)) + "\n", raw)


class SourcesTest(unittest.TestCase):
    """sources.json and the catalog agree."""

    @classmethod
    def setUpClass(cls):
        cls.sources = bump.load_sources(HERE / "sources.json")
        cls.catalog = real_catalog()

    def test_every_entry_has_a_row_or_is_kept_by_hand(self):
        rows = {r["id"] for r in self.sources["sources"]}
        manual = set(self.sources["manual"])
        self.assertFalse(rows & manual, "an id is both in sources and manual")
        for tool in self.catalog["tools"]:
            self.assertIn(
                tool["id"],
                rows | manual,
                f"{tool['id']} is listed but sources.json has no row for it: add one, "
                "or name it under manual with the reason",
            )

    def test_rows_are_unique(self):
        ids = [r["id"] for r in self.sources["sources"]]
        self.assertEqual(len(ids), len(set(ids)))

    def test_each_listed_row_names_the_download_the_entry_has(self):
        """The hand-made entries are the evidence the table is right: each
        one's url is the one the row builds for its version."""
        listed = {t["id"]: t for t in self.catalog["tools"]}
        for row in self.sources["sources"]:
            entry = listed.get(row["id"])
            if entry is None:
                continue
            tag = row["tagPrefix"] + entry["version"]
            self.assertEqual(
                bump.download_url(row, tag, entry["version"]), entry["download"]["url"]
            )


class BumpTest(unittest.TestCase):
    def setUp(self):
        self.f = Fixture(self)

    def publish_homespeaker(self, version="1.20.0", **manifest_changes):
        data = zip_of(manifest_for(HS, version, **manifest_changes))
        name = f"HomeSpeaker-{version}-tool.zip"
        return name, data, self.f.publish(name, data)

    def assert_refused(self, tool_id, tag, words):
        before = self.f.files()
        status, result = self.f.run(tool_id, tag)
        self.assertEqual(status, bump.REFUSED, result)
        self.assertIn(words, result["message"])
        self.assertEqual(self.f.files(), before, "a refused bump wrote something")

    def test_bumps_only_the_entry_from_its_release(self):
        before = self.f.catalog()
        name, data, sha = self.publish_homespeaker()
        status, result = self.f.run(HS, "home-speaker-v1.20.0")
        self.assertEqual(status, bump.OK, result)
        after = self.f.catalog()

        expected = copy.deepcopy(before)
        hs = entry_of(expected, HS)
        hs["version"] = "1.20.0"
        hs["download"] = {
            "url": "https://github.com/VitruvianSoftware/vitruvian-core/releases/download/"
            f"home-speaker-v1.20.0/{name}",
            "sha256": sha,
            "size": len(data),
        }
        expected["generated"] = NOW
        self.assertEqual(after, expected)
        self.assertEqual(
            (self.f.root / catalogue.DATA).read_bytes(),
            catalogue.outputs(self.f.root)[catalogue.DATA],
        )
        self.assertEqual(result["title"], "feat(catalog): HomeSpeaker 1.20.0")
        self.assertEqual(
            result["branch"], "catalog/bump-dev.vitruvian.homespeaker-1.20.0"
        )
        self.assertIn("It offered 1.19.1", result["body"])
        self.assertNotIn("Also copied", result["body"])

    def test_floor_is_kept_and_a_newer_feature_is_a_note(self):
        manifest = manifest_for(HS, "1.20.0")
        manifest["contributes"]["status"] = {"placement": "island"}
        data = zip_of(manifest)
        self.f.publish("HomeSpeaker-1.20.0-tool.zip", data)
        status, result = self.f.run(HS, "home-speaker-v1.20.0")
        self.assertEqual(status, bump.OK, result)
        self.assertEqual(entry_of(self.f.catalog(), HS)["minimumAppVersion"], "3.45.0")
        self.assertIn(
            "Oldest app version stays 3.45.0; a person decides", result["body"]
        )
        self.assertIn("Vitruvian 3.48.0", result["body"])

    def test_no_note_when_the_floor_already_has_it(self):
        self.assertEqual(bump.floor_notes({"protocol": "2"}, "3.45.0"), [])
        self.assertEqual(
            len(
                bump.floor_notes(
                    {"contributes": {"status": {"activity": True}}}, "3.46.0"
                )
            ),
            2,
        )

    def test_what_the_manifest_says_is_copied_and_new_uses_are_flagged(self):
        manifest = manifest_for(
            HS,
            "1.20.0",
            description={"en": "Speaks."},
            uses=["notify", "clipboard.read", "open", "clipboard.write"],
        )
        self.f.publish("HomeSpeaker-1.20.0-tool.zip", zip_of(manifest))
        status, result = self.f.run(HS, "home-speaker-v1.20.0")
        self.assertEqual(status, bump.OK, result)
        hs = entry_of(self.f.catalog(), HS)
        self.assertEqual(hs["summary"], {"en": "Speaks."})
        self.assertEqual(
            hs["uses"], ["notify", "clipboard.read", "open", "clipboard.write"]
        )
        self.assertIn("`summary`, `uses`", result["body"])
        self.assertIn("now asks for `clipboard.write`", result["body"])
        self.assertEqual(catalog_rules.manifest_problems(hs, manifest), [])

    def test_uses_in_another_order_is_not_a_change(self):
        self.publish_homespeaker(uses=["open", "notify", "clipboard.read"])
        status, result = self.f.run(HS, "home-speaker-v1.20.0")
        self.assertEqual(status, bump.OK, result)
        self.assertEqual(
            entry_of(self.f.catalog(), HS)["uses"], ["notify", "clipboard.read", "open"]
        )

    def test_generated_always_moves_forward(self):
        self.assertEqual(
            bump.next_generated(
                "2030-01-02T03:04:05Z",
                bump.datetime(2020, 1, 1, tzinfo=bump.timezone.utc),
            ),
            "2030-01-02T03:04:06Z",
        )

    def test_a_mirror_release(self):
        data = zip_of(manifest_for("dev.vitruvian.github", "1.4.1"))
        sha = self.f.publish("github-tool-1.4.1.zip", data)
        status, result = self.f.run("dev.vitruvian.github", "v1.4.1")
        self.assertEqual(status, bump.OK, result)
        self.assertEqual(
            entry_of(self.f.catalog(), "dev.vitruvian.github")["download"]["url"],
            "https://github.com/VitruvianSoftware/vitruvian-tool-github/releases/download/v1.4.1/github-tool-1.4.1.zip",
        )
        self.assertIn("in VitruvianSoftware/vitruvian-tool-github", result["body"])
        self.assertIn(sha[:8], result["body"])

    def test_already_listed_is_nothing_to_do(self):
        self.publish_homespeaker()
        self.f.run(HS, "home-speaker-v1.20.0")
        before = self.f.files()
        status, result = self.f.run(HS, "home-speaker-v1.20.0")
        self.assertEqual((status, result["status"]), (bump.OK, "current"))
        self.assertEqual(self.f.files(), before)

    # --- Refused, and nothing written ---------------------------------------

    def test_github_digest_differs(self):
        data = zip_of(manifest_for(HS, "1.20.0"))
        self.f.publish("HomeSpeaker-1.20.0-tool.zip", data, digest="sha256:" + "0" * 64)
        self.assert_refused(HS, "home-speaker-v1.20.0", "GitHub says sha256:")

    def test_github_records_no_digest(self):
        data = zip_of(manifest_for(HS, "1.20.0"))
        self.f.publish("HomeSpeaker-1.20.0-tool.zip", data, digest="")
        self.assert_refused(HS, "home-speaker-v1.20.0", "GitHub records no SHA-256")

    def test_size_differs(self):
        data = zip_of(manifest_for(HS, "1.20.0"))
        self.f.publish("HomeSpeaker-1.20.0-tool.zip", data, size=len(data) + 1)
        self.assert_refused(HS, "home-speaker-v1.20.0", "GitHub says")

    def test_sidecar_differs(self):
        data = zip_of(manifest_for(HS, "1.20.0"))
        self.f.publish(
            "HomeSpeaker-1.20.0-tool.zip",
            data,
            sidecar_text=("1" * 64) + "  HomeSpeaker-1.20.0-tool.zip\n",
        )
        self.assert_refused(HS, "home-speaker-v1.20.0", ".sha256 says")

    def test_sidecar_names_another_file(self):
        data = zip_of(manifest_for(HS, "1.20.0"))
        sha = hashlib.sha256(data).hexdigest()
        self.f.publish(
            "HomeSpeaker-1.20.0-tool.zip", data, sidecar_text=f"{sha}  other.zip\n"
        )
        self.assert_refused(HS, "home-speaker-v1.20.0", "the checksum of other.zip")

    def test_no_sidecar(self):
        data = zip_of(manifest_for(HS, "1.20.0"))
        self.f.publish("HomeSpeaker-1.20.0-tool.zip", data, sidecar=False)
        self.assert_refused(
            HS, "home-speaker-v1.20.0", "no HomeSpeaker-1.20.0-tool.zip.sha256"
        )

    def test_manifest_version_is_not_the_tags(self):
        data = zip_of(manifest_for(HS, "1.19.9"))
        self.f.publish("HomeSpeaker-1.20.0-tool.zip", data)
        self.assert_refused(HS, "home-speaker-v1.20.0", "the tag's is 1.20.0")

    def test_manifest_id_is_not_the_entrys(self):
        data = zip_of(manifest_for(HS, "1.20.0", id="dev.vitruvian.other"))
        self.f.publish("HomeSpeaker-1.20.0-tool.zip", data)
        self.assert_refused(
            HS, "home-speaker-v1.20.0", "the manifest's id is dev.vitruvian.other"
        )

    def test_unsafe_zip(self):
        data = zip_of(manifest_for(HS, "1.20.0"), extra={"../escape": "x"})
        self.f.publish("HomeSpeaker-1.20.0-tool.zip", data)
        self.assert_refused(HS, "home-speaker-v1.20.0", "a part that is empty, . or ..")

    def test_zip_without_manifest(self):
        self.f.publish("HomeSpeaker-1.20.0-tool.zip", zip_of(None))
        self.assert_refused(HS, "home-speaker-v1.20.0", "no vitruvian-tool.json")

    def test_tag_of_another_tool(self):
        self.assert_refused(HS, "android-remote-v0.1.4", "is not a tag of")

    def test_older_than_listed(self):
        self.assert_refused(HS, "home-speaker-v1.0.0", "newer than 1.0.0")

    def test_same_version_other_zip(self):
        self.publish_homespeaker(version="1.19.1")
        self.assert_refused(HS, "home-speaker-v1.19.1", "with another download")

    def test_entry_kept_by_hand(self):
        self.assert_refused(
            "dev.vitruvian.reference", "v0.11.0", "no row in catalog/sources.json"
        )

    def test_a_manifest_the_schema_refuses(self):
        self.publish_homespeaker(name={"fr": "sans anglais"})
        self.assert_refused(HS, "home-speaker-v1.20.0", "schema:")

    # --- Skipped, not failed --------------------------------------------------

    def test_release_without_its_zip_is_skipped(self):
        self.f.meta(
            assets=[{"id": 9, "name": "HomeSpeaker-1.20.0-universal.dmg", "size": 1}]
        )
        before = self.f.files()
        status, result = self.f.run(HS, "home-speaker-v1.20.0")
        self.assertEqual((status, result["status"]), (bump.NOT_READY, "not-ready"))
        self.assertIn("no HomeSpeaker-1.20.0-tool.zip yet", result["message"])
        self.assertEqual(self.f.files(), before)

    def test_draft_is_skipped(self):
        self.publish_homespeaker()
        self.f.meta(draft=True)
        status, _ = self.f.run(HS, "home-speaker-v1.20.0")
        self.assertEqual(status, bump.NOT_READY)

    def test_no_release_is_skipped(self):
        status, _ = self.f.run(HS, "home-speaker-v1.20.0")
        self.assertEqual(status, bump.NOT_READY)

    def test_a_tool_not_listed_yet_is_skipped(self):
        data = zip_of(manifest_for(HS, "0.1.5", id="dev.vitruvian.remote"))
        self.f.publish("VitruvianRemote-0.1.5-tool.zip", data)
        before = self.f.files()
        status, result = self.f.run("dev.vitruvian.remote", "android-remote-v0.1.5")
        self.assertEqual((status, result["status"]), (bump.NOT_LISTED, "not-listed"))
        self.assertEqual(self.f.files(), before)


class PlanTest(unittest.TestCase):
    def releases(self, repo):
        return {
            "VitruvianSoftware/vitruvian-core": [
                {"tag_name": "home-speaker-v1.21.0", "prerelease": True},
                {"tag_name": "home-speaker-v1.22.0", "draft": True},
                {"tag_name": "home-speaker-v1.20.0"},
                {"tag_name": "home-speaker-v1.19.1"},
                {"tag_name": "vitruvian-v9.0.0"},
                {"tag_name": "android-remote-v0.1.4"},
            ],
            "VitruvianSoftware/vitruvian-tool-github": [
                {"tag_name": "v1.4.1"},
                {"tag_name": "v1.10.0-rc.1", "prerelease": True},
                {"tag_name": "v1.3.0"},
            ],
        }[repo]

    def catalog_lists(self, versions):
        catalog = real_catalog()
        for tool_id, version in versions.items():
            entry_of(catalog, tool_id)["version"] = version
        return catalog

    def test_newer_published_releases_are_planned(self):
        catalog = self.catalog_lists({HS: "1.19.1", "dev.vitruvian.github": "1.3.0"})
        found = bump.plan(
            catalog,
            bump.load_sources(HERE / "sources.json"),
            self.releases,
            lambda b: None,
        )
        self.assertEqual(
            found,
            [
                {"id": HS, "tag": "home-speaker-v1.20.0"},
                {"id": "dev.vitruvian.github", "tag": "v1.4.1"},
            ],
        )

    def test_nothing_when_the_catalog_is_current(self):
        catalog = self.catalog_lists({HS: "1.20.0", "dev.vitruvian.github": "1.4.1"})
        found = bump.plan(
            catalog,
            bump.load_sources(HERE / "sources.json"),
            self.releases,
            lambda b: None,
        )
        self.assertEqual(found, [])

    def test_an_open_pull_request_is_left_alone_unless_it_conflicts(self):
        catalog = self.catalog_lists({HS: "1.19.1", "dev.vitruvian.github": "1.4.1"})
        branch = bump.branch_for(HS, "1.20.0")
        sources = bump.load_sources(HERE / "sources.json")
        open_one = {branch: {"number": 7, "mergeable": "MERGEABLE"}}
        self.assertEqual(bump.plan(catalog, sources, self.releases, open_one.get), [])
        stuck = {branch: {"number": 7, "mergeable": "CONFLICTING"}}
        self.assertEqual(
            bump.plan(catalog, sources, self.releases, stuck.get),
            [{"id": HS, "tag": "home-speaker-v1.20.0"}],
        )


if __name__ == "__main__":
    unittest.main()
