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
import struct
import tempfile
import unittest
import zipfile
from unittest import mock
from pathlib import Path

import bump
import catalog_rules
import catalogue

HERE = Path(__file__).resolve().parent
NOW = "2030-01-02T03:04:05Z"
HS = "dev.vitruvian.homespeaker"
BOT = "github-actions[bot]"
APP_INFO = HERE.parent / "apps/desktop/vitruvian/Resources/Info.plist"

ARM64, X86_64 = 0x0100000C, 0x01000007


def thin(cputype, minos=(14, 0, 0), command=0x32):
    """A fake 64-bit Mach-O header with one load command naming its oldest
    macOS: LC_BUILD_VERSION (0x32) or LC_VERSION_MIN_MACOSX (0x24); None for
    no such command."""
    raw = (minos[0] << 16) | (minos[1] << 8) | minos[2] if minos else 0
    if minos is None:
        cmd = struct.pack("<II", 0x19, 8)  # an LC_SEGMENT_64 stand-in, empty
    elif command == 0x32:
        cmd = struct.pack("<IIIIII", 0x32, 24, 1, raw, raw, 0)
    else:
        cmd = struct.pack("<IIII", 0x24, 16, raw, raw)
    header = struct.pack("<IiiIIIII", 0xFEEDFACF, cputype, 0, 2, 1, len(cmd), 0, 0)
    return header + cmd + b"\0" * 64


def fat(*slices):
    """A fake universal Mach-O holding each (cputype, thin bytes)."""
    offset, arches, body = 4096, b"", b""
    for cputype, data in slices:
        arches += struct.pack(">iiIII", cputype, 0, offset + len(body), len(data), 12)
        body += data
    head = struct.pack(">II", 0xCAFEBABE, len(slices)) + arches
    return head + b"\0" * (offset - len(head)) + body


UNIVERSAL = fat((X86_64, thin(X86_64)), (ARM64, thin(ARM64)))


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


def zip_of(manifest, extra=None, program=UNIVERSAL):
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as archive:
        if manifest is not None:
            archive.writestr("vitruvian-tool.json", json.dumps(manifest))
        archive.writestr("bin/tool", program)
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
        info = self.root / bump.APP_INFO
        info.parent.mkdir(parents=True)
        shutil.copy(APP_INFO, info)
        for path, data in catalogue.outputs(self.root).items():
            (self.root / path).parent.mkdir(parents=True, exist_ok=True)
            (self.root / path).write_bytes(data)
        self.release = self.dir / "release"
        self.release.mkdir()

    def publish(
        self,
        name,
        data,
        sidecar=True,
        digest=None,
        size=None,
        sidecar_text=None,
        uploader=BOT,
        sidecar_uploader=BOT,
    ):
        """Attaches `data` as `name`, with its .sha256, as a release does."""
        sha = hashlib.sha256(data).hexdigest()
        assets = [
            {
                "id": 1,
                "name": name,
                "size": len(data) if size is None else size,
                "digest": "sha256:" + sha if digest is None else digest,
                "uploader": {"login": uploader},
            }
        ]
        (self.release / name).write_bytes(data)
        if sidecar:
            text = sidecar_text if sidecar_text is not None else f"{sha}  {name}\n"
            (self.release / (name + ".sha256")).write_text(text)
            assets.append(
                {
                    "id": 2,
                    "name": name + ".sha256",
                    "size": len(text),
                    "uploader": {"login": sidecar_uploader},
                }
            )
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
        self.assertTrue(result["automerge"])
        self.assertIn("merges itself once **catalog-check** passes", result["body"])
        self.assertIn(bump.AUTOMERGE_MARK, result["body"])
        self.assertNotIn("needs-human", result["body"])
        self.assertIn(
            "(https://github.com/VitruvianSoftware/vitruvian-core/compare/"
            "home-speaker-v1.19.1...home-speaker-v1.20.0)",
            result["body"],
        )
        self.assertIn(
            "(https://github.com/VitruvianSoftware/vitruvian-core/releases/tag/"
            "home-speaker-v1.20.0)",
            result["body"],
        )
        self.assertIn("they do not prove the release's code is safe", result["body"])

    def test_floor_is_kept_and_a_newer_feature_is_a_note(self):
        manifest = manifest_for(HS, "1.20.0")
        manifest["contributes"]["status"] = {"placement": "island"}
        data = zip_of(manifest)
        self.f.publish("HomeSpeaker-1.20.0-tool.zip", data)
        status, result = self.f.run(HS, "home-speaker-v1.20.0")
        self.assertEqual(status, bump.OK, result)
        self.assertEqual(entry_of(self.f.catalog(), HS)["minimumAppVersion"], "3.45.0")
        self.assertIn("Oldest app version stays 3.45.0.", result["body"])
        self.assertIn("Vitruvian 3.48.0", result["body"])
        self.assertTrue(result["automerge"], "a floor note alone does not hold it")

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

    def test_a_new_service_holds_the_pull_request_for_a_person(self):
        """The guard: a tool that asks for more never merges itself."""
        self.publish_homespeaker(
            uses=["notify", "clipboard.read", "open", "keystrokes"]
        )
        status, result = self.f.run(HS, "home-speaker-v1.20.0")
        self.assertEqual(status, bump.OK, result)
        self.assertFalse(result["automerge"])
        self.assertIn("waits for a person** (label `needs-human`)", result["body"])
        self.assertIn(
            "It asks for a service it did not ask for before: `keystrokes`.",
            result["body"],
        )
        self.assertNotIn("merges itself", result["body"])
        self.assertNotIn(bump.AUTOMERGE_MARK, result["body"])

    def test_a_new_command_holds_the_pull_request_for_a_person(self):
        manifest = manifest_for(HS, "1.20.0")
        manifest["contributes"]["commands"].append(
            {"id": "shout", "title": {"en": "Shout"}, "surfaces": ["commandBar"]}
        )
        self.f.publish("HomeSpeaker-1.20.0-tool.zip", zip_of(manifest))
        status, result = self.f.run(HS, "home-speaker-v1.20.0")
        self.assertEqual(status, bump.OK, result)
        self.assertFalse(result["automerge"])
        self.assertIn("It offers new commands: `shout`.", result["body"])

    def held(self, manifest, *words):
        self.f.publish("HomeSpeaker-1.20.0-tool.zip", zip_of(manifest))
        status, result = self.f.run(HS, "home-speaker-v1.20.0")
        self.assertEqual(status, bump.OK, result)
        self.assertFalse(result["automerge"], result["body"])
        self.assertNotIn(bump.AUTOMERGE_MARK, result["body"])
        for text in words:
            self.assertIn(text, result["body"])
        return result

    def merges_itself(self, manifest):
        self.f.publish("HomeSpeaker-1.20.0-tool.zip", zip_of(manifest))
        status, result = self.f.run(HS, "home-speaker-v1.20.0")
        self.assertEqual(status, bump.OK, result)
        self.assertTrue(result["automerge"], result["body"])
        return result

    def test_taking_a_service_away_holds_the_pull_request(self):
        self.held(
            manifest_for(HS, "1.20.0", uses=["notify", "open"]),
            "It no longer asks for `clipboard.read`.",
        )
        self.assertEqual(entry_of(self.f.catalog(), HS)["uses"], ["notify", "open"])

    def test_taking_a_command_away_holds_the_pull_request(self):
        manifest = manifest_for(HS, "1.20.0")
        manifest["contributes"]["commands"] = [
            c for c in manifest["contributes"]["commands"] if c["id"] != "mute"
        ]
        self.held(manifest, "It no longer offers `mute`.")

    def test_reordered_panels_hold_the_pull_request(self):
        manifest = manifest_for(HS, "1.20.0")
        manifest["contributes"]["panels"].reverse()
        self.held(
            manifest,
            'Its panels changed from ["island", "settings"] to ["settings", "island"].',
        )

    def test_a_removed_panel_holds_the_pull_request(self):
        manifest = manifest_for(HS, "1.20.0")
        manifest["contributes"]["panels"] = manifest["contributes"]["panels"][:1]
        self.held(manifest, "Its panels changed")

    def test_another_publisher_holds_the_pull_request(self):
        self.held(
            manifest_for(HS, "1.20.0", publisher="Someone Else"),
            "It says it comes from 'Someone Else', not 'VitruvianSoftware'.",
        )

    def test_another_protocol_holds_the_pull_request(self):
        self.held(
            manifest_for(HS, "1.20.0", protocol="1"),
            "Its protocol changed from 2 to 1.",
        )

    def test_new_words_alone_merge_themselves(self):
        """Name, summary and command titles are text: the ruling lets them merge."""
        manifest = manifest_for(
            HS, "1.20.0", description={"en": "Speaks."}, name={"en": "Home Speaker"}
        )
        manifest["contributes"]["commands"][0]["title"] = {"en": "Say the clipboard"}
        result = self.merges_itself(manifest)
        self.assertIn("`name`, `summary`, `commands`", result["body"])
        self.assertEqual(entry_of(self.f.catalog(), HS)["summary"], {"en": "Speaks."})

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
        self.assertIn("did not ask for before: `clipboard.write`", result["body"])
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
        self.assertIn(
            "(https://github.com/VitruvianSoftware/vitruvian-tool-github/compare/"
            "v1.3.0...v1.4.1)",
            result["body"],
        )
        self.assertIn(sha[:8], result["body"])

    def test_already_listed_is_nothing_to_do(self):
        self.publish_homespeaker()
        self.f.run(HS, "home-speaker-v1.20.0")
        before = self.f.files()
        status, result = self.f.run(HS, "home-speaker-v1.20.0")
        self.assertEqual((status, result["status"]), (bump.OK, "current"))
        self.assertEqual(self.f.files(), before)

    # --- Refused, and nothing written ---------------------------------------

    def test_a_zip_someone_else_uploaded(self):
        """I1: the release workflow's account uploads the zip; anyone else's
        upload is refused, however well its checksums match."""
        data = zip_of(manifest_for(HS, "1.20.0"))
        self.f.publish("HomeSpeaker-1.20.0-tool.zip", data, uploader="someone")
        self.assert_refused(
            HS,
            "home-speaker-v1.20.0",
            "HomeSpeaker-1.20.0-tool.zip was uploaded by someone",
        )

    def test_a_checksum_someone_else_uploaded(self):
        data = zip_of(manifest_for(HS, "1.20.0"))
        self.f.publish("HomeSpeaker-1.20.0-tool.zip", data, sidecar_uploader="someone")
        self.assert_refused(
            HS, "home-speaker-v1.20.0", ".sha256 was uploaded by someone"
        )

    def test_a_program_for_a_newer_macos(self):
        """A Remote zip was built for macOS 27: it would install on 14 and fail."""
        program = fat((X86_64, thin(X86_64)), (ARM64, thin(ARM64, minos=(27, 0, 0))))
        self.f.publish(
            "HomeSpeaker-1.20.0-tool.zip",
            zip_of(manifest_for(HS, "1.20.0"), program=program),
        )
        self.assert_refused(
            HS,
            "home-speaker-v1.20.0",
            "bin/tool (arm64) needs macOS 27.0; the app runs on macOS 14.0",
        )

    def test_any_mach_o_in_the_zip_is_checked(self):
        library = thin(ARM64, minos=(15, 4, 0), command=0x24)
        self.f.publish(
            "HomeSpeaker-1.20.0-tool.zip",
            zip_of(manifest_for(HS, "1.20.0"), extra={"lib/helper.dylib": library}),
        )
        self.assert_refused(
            HS, "home-speaker-v1.20.0", "lib/helper.dylib (arm64) needs macOS 15.4"
        )

    def test_a_program_that_names_no_oldest_macos(self):
        program = fat((X86_64, thin(X86_64)), (ARM64, thin(ARM64, minos=None)))
        self.f.publish(
            "HomeSpeaker-1.20.0-tool.zip",
            zip_of(manifest_for(HS, "1.20.0"), program=program),
        )
        self.assert_refused(HS, "home-speaker-v1.20.0", "names no oldest macOS")

    def test_a_program_that_is_no_longer_universal(self):
        program = thin(ARM64)
        self.f.publish(
            "HomeSpeaker-1.20.0-tool.zip",
            zip_of(manifest_for(HS, "1.20.0"), program=program),
        )
        self.assert_refused(
            HS, "home-speaker-v1.20.0", "bin/tool is arm64, not universal"
        )

    def test_a_script_where_a_universal_program_was(self):
        self.f.publish(
            "HomeSpeaker-1.20.0-tool.zip",
            zip_of(manifest_for(HS, "1.20.0"), program=b"#!/bin/sh\necho hi\n"),
        )
        self.assert_refused(
            HS, "home-speaker-v1.20.0", "bin/tool is not a Mach-O, not universal"
        )

    def test_every_mach_o_must_be_universal(self):
        """Not just the program: an arm64-only helper would fail on Intel Macs."""
        self.f.publish(
            "HomeSpeaker-1.20.0-tool.zip",
            zip_of(manifest_for(HS, "1.20.0"), extra={"lib/helper.dylib": thin(ARM64)}),
        )
        self.assert_refused(
            HS, "home-speaker-v1.20.0", "lib/helper.dylib is arm64, not universal"
        )

    def test_a_short_fat_header_is_a_clean_refusal(self):
        stub = struct.pack(">II", 0xCAFEBABE, 2) + b"\0" * 8
        self.f.publish(
            "HomeSpeaker-1.20.0-tool.zip",
            zip_of(manifest_for(HS, "1.20.0"), extra={"lib/stub": stub}),
        )
        self.assert_refused(
            HS, "home-speaker-v1.20.0", "lib/stub is a Mach-O that cannot be read"
        )

    def test_a_zip_that_could_not_be_downloaded_is_not_a_refusal(self):
        """Round 3 B: a download blip retries; it opens no issue."""
        data = zip_of(manifest_for(HS, "1.20.0"))
        self.f.publish("HomeSpeaker-1.20.0-tool.zip", data)
        (self.f.release / "HomeSpeaker-1.20.0-tool.zip").unlink()
        before = self.f.files()
        status, result = self.f.run(HS, "home-speaker-v1.20.0")
        self.assertEqual((status, result["status"]), (bump.UNAVAILABLE, "unavailable"))
        self.assertNotIn("issue_title", result)
        self.assertEqual(self.f.files(), before)

    def test_a_checksum_that_could_not_be_downloaded_is_not_a_refusal(self):
        data = zip_of(manifest_for(HS, "1.20.0"))
        self.f.publish("HomeSpeaker-1.20.0-tool.zip", data)
        (self.f.release / "HomeSpeaker-1.20.0-tool.zip.sha256").unlink()
        status, result = self.f.run(HS, "home-speaker-v1.20.0")
        self.assertEqual((status, result["status"]), (bump.UNAVAILABLE, "unavailable"))
        self.assertIn(".sha256 could not be downloaded", result["message"])

    def test_a_refusal_names_the_issue_that_records_it(self):
        data = zip_of(manifest_for(HS, "1.20.0"))
        self.f.publish("HomeSpeaker-1.20.0-tool.zip", data, uploader="someone")
        status, result = self.f.run(HS, "home-speaker-v1.20.0")
        self.assertEqual(status, bump.REFUSED)
        self.assertEqual(
            result["issue_title"],
            "catalog-bump refused dev.vitruvian.homespeaker 1.20.0",
        )
        self.assertIn(
            "- HomeSpeaker-1.20.0-tool.zip was uploaded by someone",
            result["issue_body"],
        )
        self.assertIn("Close the issue to let it try again", result["issue_body"])

    def test_a_pre_release_version_is_refused(self):
        self.assert_refused(HS, "home-speaker-v1.21.0-rc.1", "X.Y.Z releases only")

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

    def test_a_skip_never_exits_as_bazel_or_argparse_fail(self):
        """I4: 2 is a usage error to Bazel and argparse, so it means nothing here."""
        self.assertNotIn(
            2,
            (bump.OK, bump.REFUSED, bump.NOT_READY, bump.NOT_LISTED, bump.UNAVAILABLE),
        )
        with self.assertRaises(SystemExit) as usage:
            bump.main(["bump", "--tag", "x"])
        self.assertEqual(usage.exception.code, 2)


class MachOTest(unittest.TestCase):
    def test_reads_each_architecture_and_its_oldest_macos(self):
        self.assertEqual(
            bump.macho_slices(
                fat((X86_64, thin(X86_64, minos=(13, 5, 0))), (ARM64, thin(ARM64)))
            ),
            [("x86_64", (13, 5, 0)), ("arm64", (14, 0, 0))],
        )
        self.assertEqual(
            bump.macho_slices(thin(ARM64, minos=(12, 0, 1), command=0x24)),
            [("arm64", (12, 0, 1))],
        )

    def test_other_files_are_not_mach_o(self):
        self.assertIsNone(bump.macho_slices(b"#!/bin/sh\n"))
        java = struct.pack(">IHH", 0xCAFEBABE, 0, 65) + b"\0" * 32
        self.assertIsNone(bump.macho_slices(java))

    def test_a_broken_mach_o_is_an_error(self):
        broken = thin(ARM64)[:40]
        with self.assertRaises(ValueError):
            bump.macho_slices(broken)

    def test_the_app_runs_on_macos_14(self):
        self.assertEqual(bump.app_oldest_macos(HERE.parent), (14, 0, 0))


class WorkflowHelpersTest(unittest.TestCase):
    EMAIL = "314429222+vitruvian-wren-agent[bot]@users.noreply.github.com"

    def commit(self, sha, message, name="vitruvian-wren-agent[bot]"):
        return {
            "sha": sha,
            "commit": {
                "message": message,
                "author": {"name": name, "email": self.EMAIL},
            },
        }

    def workflows(self, version="1.20.0"):
        return self.commit(
            "a" * 40,
            "feat(catalog): HomeSpeaker 1.20.0\n\nWritten by catalog-bump.\n\n"
            f"Catalog-Bump: {HS}@{version}",
        )

    def test_the_workflows_own_commit_is_not_foreign(self):
        self.assertEqual(
            bump.foreign({"commits": [self.workflows()]}, HS, "1.20.0"), []
        )
        self.assertEqual(bump.foreign({"commits": []}, HS, "1.20.0"), [])

    def test_a_session_using_the_bots_email_is_still_a_person(self):
        """I3: agent sessions share the bot's email; only the trailer counts."""
        session = self.commit("b" * 40, "chore: raise the floor", name="wren")
        self.assertEqual(
            bump.foreign({"commits": [self.workflows(), session]}, HS, "1.20.0"),
            ["bbbbbbbbbbbb by wren"],
        )
        self.assertEqual(
            bump.foreign({"commits": [session]}, HS, "1.20.0"), ["bbbbbbbbbbbb by wren"]
        )

    def test_a_second_commit_is_foreign_even_with_the_trailer(self):
        second = dict(self.workflows(), sha="c" * 40)
        self.assertEqual(
            bump.foreign({"commits": [self.workflows(), second]}, HS, "1.20.0"),
            ["cccccccccccc by vitruvian-wren-agent[bot]"],
        )

    def test_another_versions_trailer_is_foreign(self):
        self.assertEqual(
            len(bump.foreign({"commits": [self.workflows("1.19.0")]}, HS, "1.20.0")), 1
        )

    def test_only_older_versions_are_replaced(self):
        pulls = [
            {"number": 1, "headRefName": f"catalog/bump-{HS}-1.19.0"},
            {"number": 2, "headRefName": f"catalog/bump-{HS}-1.21.0"},
            {"number": 3, "headRefName": f"catalog/bump-{HS}-1.20.0"},
            {"number": 4, "headRefName": "catalog/bump-dev.vitruvian.github-1.0.0"},
            {"number": 5, "headRefName": "feature/other"},
        ]
        self.assertEqual(bump.older(pulls, HS, "1.20.0"), [1])


class ArmTest(unittest.TestCase):
    """catalog-check arms auto-merge on a bump pull request, only when it passed
    and the branch holds nothing but catalog-bump's one commit."""

    SHA = "d" * 40

    def setUp(self):
        self.mine = {
            "commits": [WorkflowHelpersTest().workflows()],
            "files": [{"filename": f} for f in bump.BUMP_FILES],
        }

    def pull(self, **changes):
        pull = {
            "state": "OPEN",
            "isDraft": False,
            "headRefName": f"catalog/bump-{HS}-1.20.0",
            "headRefOid": self.SHA,
            "author": {"login": "app/vitruvian-copybara-sync"},
            "labels": [],
            "body": "text\n" + bump.AUTOMERGE_MARK + "\n",
            "autoMergeRequest": None,
        }
        pull.update(changes)
        return pull

    def arm(self, pull, check="success", sha=None, compare=None):
        return bump.arm(pull, compare or self.mine, sha or self.SHA, check)

    def test_arms_when_catalog_check_passed(self):
        self.assertEqual(self.arm(self.pull()), "arm")

    def test_never_arms_when_catalog_check_failed(self):
        self.assertTrue(self.arm(self.pull(), "failure").startswith("leave"))
        armed = self.pull(autoMergeRequest={"enabledBy": {}})
        self.assertEqual(self.arm(armed, "failure"), "disarm")
        self.assertTrue(self.arm(self.pull(), "cancelled").startswith("leave"))

    def test_a_held_pull_request_is_not_armed(self):
        for label in ("needs-human", "do-not-automerge"):
            held = self.pull(labels=[{"name": label}])
            self.assertTrue(self.arm(held).startswith("leave"))
            held["autoMergeRequest"] = {}
            self.assertEqual(self.arm(held), "disarm")

    def test_only_a_marked_pull_request_from_the_workflow_is_armed(self):
        for pull in (
            self.pull(body="no mark"),
            self.pull(author={"login": "james"}),
            self.pull(headRefName="feature/x"),
            self.pull(isDraft=True),
            self.pull(state="CLOSED"),
        ):
            self.assertTrue(self.arm(pull).startswith("leave"), pull)

    def test_a_moved_branch_waits_for_its_own_run(self):
        self.assertIn("moved", self.arm(self.pull(), sha="e" * 40))

    def test_an_armed_pull_request_is_not_armed_again(self):
        armed = self.pull(autoMergeRequest={"enabledBy": {}})
        self.assertEqual(self.arm(armed), "leave: auto-merge is already on")

    def persons(self):
        helpers = WorkflowHelpersTest()
        return {
            "commits": [
                helpers.workflows(),
                helpers.commit("b" * 40, "feat: ask for keystrokes", name="wren"),
            ]
        }

    def test_a_persons_commit_is_held_even_when_catalog_check_passed(self):
        """Round 3 (a): the body's verdict was for the workflow's change only."""
        verdict = self.arm(self.pull(), compare=self.persons())
        self.assertTrue(verdict.startswith("hold: "), verdict)
        self.assertIn("bbbbbbbbbbbb by wren", verdict)
        armed = self.pull(autoMergeRequest={"enabledBy": {}})
        self.assertTrue(self.arm(armed, compare=self.persons()).startswith("hold: "))

    def test_a_push_of_a_persons_commit_is_held_at_once(self):
        """Round 3 (b): on the push, before catalog-check has run on it."""
        armed = self.pull(autoMergeRequest={"enabledBy": {}})
        self.assertTrue(
            self.arm(armed, "pushed", compare=self.persons()).startswith("hold: ")
        )

    def test_a_push_of_the_workflows_own_commit_is_left_for_catalog_check(self):
        self.assertEqual(
            self.arm(self.pull(), "pushed"),
            "leave: catalog-bump's own commit; catalog-check decides",
        )

    def test_another_versions_commit_is_a_persons(self):
        helpers = WorkflowHelpersTest()
        other = {"commits": [helpers.workflows("1.19.0")]}
        self.assertTrue(self.arm(self.pull(), compare=other).startswith("hold: "))


class ActingGitHub:
    """Records what automerge does, for one pull request."""

    def __init__(self, pull, compare):
        self.pull, self.compare_answer = pull, compare
        self.actions, self.comments = [], []

    def pull_view(self, number):
        return self.pull

    def compare(self, head, base="main"):
        self.actions.append(("compare", base, head))
        return self.compare_answer

    def enable_auto(self, number, sha):
        self.actions.append(("arm", sha))

    def disable_auto(self, number):
        self.actions.append(("disarm",))

    def add_label(self, number, label):
        self.actions.append(("label", label))

    def comment_once(self, number, mark, text):
        if any(mark in c for c in self.comments):
            return False
        self.comments.append(mark + "\n" + text)
        return True


class BumpFilesTest(unittest.TestCase):
    """Round 4: a bump changes tools.json and the site's tools.yml, nothing
    else. Even the workflow's own trailer commit is held if it changes more
    (a session that amends it, say)."""

    def setUp(self):
        self.helper = ArmTest()
        self.helper.setUp()
        self.mine, self.pull, self.arm = (
            self.helper.mine,
            self.helper.pull,
            self.helper.arm,
        )

    def changed(self, *names):
        return dict(self.mine, files=[{"filename": n} for n in names])

    def test_a_branch_that_changes_a_workflow_is_held(self):
        compare = self.changed(*bump.BUMP_FILES, ".github/workflows/catalog-check.yaml")
        verdict = self.arm(self.pull(), compare=compare)
        self.assertTrue(verdict.startswith("hold: "), verdict)
        self.assertIn("`.github/workflows/catalog-check.yaml`", verdict)
        self.assertTrue(
            self.arm(self.pull(), "pushed", compare=compare).startswith("hold: ")
        )

    def test_a_branch_that_changes_the_bump_code_is_held(self):
        verdict = self.arm(
            self.pull(), compare=self.changed(bump.CATALOG, "catalog/bump.py")
        )
        self.assertIn("`catalog/bump.py`", verdict)

    def test_only_one_of_the_two_files_is_fine(self):
        self.assertEqual(
            self.arm(self.pull(), compare=self.changed(bump.CATALOG)), "arm"
        )

    def test_no_file_list_is_held(self):
        verdict = self.arm(self.pull(), compare={"commits": self.mine["commits"]})
        self.assertTrue(verdict.startswith("hold: "), verdict)

    def test_too_many_files_to_list_is_held(self):
        compare = self.changed(*([bump.CATALOG] * 300))
        self.assertIn("300 files or more", self.arm(self.pull(), compare=compare))


class AutomergeTest(unittest.TestCase):
    """What the catalog-check jobs do with a decision."""

    def setUp(self):
        self.arm = ArmTest()
        self.arm.setUp()

    def run_it(self, pull, compare, check="success"):
        github = ActingGitHub(pull, compare)
        decision = bump.automerge(github, 7, ArmTest.SHA, check)
        return decision, github

    def test_arms_only_at_the_tested_commit(self):
        """Round 3, Minor A: --match-head-commit, so a later push is not armed."""
        decision, github = self.run_it(self.arm.pull(), self.arm.mine)
        self.assertEqual(decision, "arm")
        self.assertIn(("arm", ArmTest.SHA), github.actions)
        self.assertIn(("compare", "main", ArmTest.SHA), github.actions)

    def test_a_persons_commit_is_disarmed_labelled_and_said_once(self):
        armed = self.arm.pull(autoMergeRequest={"enabledBy": {}})
        decision, github = self.run_it(armed, self.arm.persons())
        self.assertTrue(decision.startswith("hold: "))
        self.assertEqual(github.actions[1:], [("disarm",), ("label", "needs-human")])
        bump.automerge(github, 7, ArmTest.SHA, "success")
        self.assertEqual(len(github.comments), 1)
        self.assertTrue(github.comments[0].startswith(bump.HELD_MARK))
        self.assertNotIn(("arm", ArmTest.SHA), github.actions)

    def test_a_push_of_a_persons_commit_disarms_at_once(self):
        armed = self.arm.pull(autoMergeRequest={"enabledBy": {}})
        _, github = self.run_it(armed, self.arm.persons(), check="pushed")
        self.assertIn(("disarm",), github.actions)
        self.assertIn(("label", "needs-human"), github.actions)

    def test_a_push_of_the_workflows_commit_does_nothing(self):
        _, github = self.run_it(self.arm.pull(), self.arm.mine, check="pushed")
        self.assertEqual([a for a in github.actions if a[0] != "compare"], [])

    def test_a_failed_check_disarms(self):
        armed = self.arm.pull(autoMergeRequest={"enabledBy": {}})
        _, github = self.run_it(armed, self.arm.mine, check="failure")
        self.assertEqual(github.actions[1:], [("disarm",)])


class GhCallTest(unittest.TestCase):
    def test_arming_names_the_commit_github_must_still_hold(self):
        """Minor A: GitHub refuses to arm if the head moved after the check."""
        with mock.patch.object(bump, "gh", return_value=b"") as gh:
            bump.GitHub().enable_auto(7, "f" * 40)
        args = gh.call_args.args[0]
        self.assertEqual(args[:4], ["pr", "merge", "7", "--squash"])
        self.assertIn("--auto", args)
        self.assertEqual(args[args.index("--match-head-commit") + 1], "f" * 40)


class FakeGitHub:
    def __init__(self, test):
        self.test = test
        self.comments = {}

    def tags(self, repo, prefix):
        return [t for t in self.test.TAGS[repo] if t.startswith(prefix)]

    def release(self, repo, tag):
        return self.test.releases.get(tag)

    def pull(self, branch):
        return self.test.pulls.get(branch)

    def compare(self, branch):
        return self.test.compares.get(branch, {"commits": []})

    def refused_open(self, title):
        return title in self.test.issues

    def comment_once(self, number, mark, text):
        bodies = self.comments.setdefault(number, [])
        if any(mark in b for b in bodies):
            return False
        bodies.append(mark + "\n" + text)
        return True


class PlanTest(unittest.TestCase):
    TAGS = {
        "VitruvianSoftware/vitruvian-core": [
            "home-speaker-v1.19.1",
            "home-speaker-v1.20.0",
            "home-speaker-v1.21.0",
            "home-speaker-v1.22.0-rc.1",
            "android-remote-v0.1.4",
        ],
        "VitruvianSoftware/vitruvian-tool-github": ["v1.3.0", "v1.4.1", "v1.10.0-rc.1"],
    }

    def setUp(self):
        self.releases = {
            "home-speaker-v1.19.1": {
                "assets": [{"name": "HomeSpeaker-1.19.1-tool.zip"}]
            },
            "home-speaker-v1.20.0": {
                "assets": [{"name": "HomeSpeaker-1.20.0-tool.zip"}]
            },
            "home-speaker-v1.21.0": {"prerelease": True, "assets": []},
            "home-speaker-v1.22.0-rc.1": {
                "assets": [{"name": "HomeSpeaker-1.22.0-rc.1-tool.zip"}]
            },
            "v1.3.0": {"assets": [{"name": "github-tool-1.3.0.zip"}]},
            "v1.4.1": {"assets": [{"name": "github-tool-1.4.1.zip"}]},
            "v1.10.0-rc.1": {"assets": [{"name": "github-tool-1.10.0-rc.1.zip"}]},
        }
        self.pulls = {}
        self.compares = {}
        self.issues = set()
        self.github = FakeGitHub(self)

    def plan(self, versions):
        catalog = real_catalog()
        for tool_id, version in versions.items():
            entry_of(catalog, tool_id)["version"] = version
        return bump.plan(catalog, bump.load_sources(HERE / "sources.json"), self.github)

    def test_newer_published_releases_are_planned(self):
        """A pre-release flag and an -rc version (M2) are both passed over."""
        self.assertEqual(
            self.plan({HS: "1.19.1", "dev.vitruvian.github": "1.3.0"}),
            [
                {"id": HS, "tag": "home-speaker-v1.20.0"},
                {"id": "dev.vitruvian.github", "tag": "v1.4.1"},
            ],
        )

    def test_nothing_when_the_catalog_is_current(self):
        self.assertEqual(self.plan({HS: "1.20.0", "dev.vitruvian.github": "1.4.1"}), [])

    def test_a_release_with_no_zip_yet_costs_no_bump(self):
        """M1: skipped in the plan, before any Bazel job."""
        self.releases["v1.4.1"]["assets"] = []
        self.assertEqual(self.plan({HS: "1.20.0", "dev.vitruvian.github": "1.3.0"}), [])

    def test_an_open_pull_request_is_left_alone_unless_it_conflicts(self):
        branch = bump.branch_for(HS, "1.20.0")
        self.pulls[branch] = {"number": 7, "state": "OPEN", "mergeable": "MERGEABLE"}
        self.assertEqual(self.plan({HS: "1.19.1", "dev.vitruvian.github": "1.4.1"}), [])
        self.pulls[branch]["mergeable"] = "CONFLICTING"
        self.assertEqual(
            self.plan({HS: "1.19.1", "dev.vitruvian.github": "1.4.1"}),
            [{"id": HS, "tag": "home-speaker-v1.20.0"}],
        )

    def test_a_pull_request_closed_without_merging_is_not_opened_again(self):
        """I2: a person said no; the next hour does not ask again."""
        branch = bump.branch_for(HS, "1.20.0")
        self.pulls[branch] = {"number": 7, "state": "CLOSED", "mergeable": "UNKNOWN"}
        self.assertEqual(self.plan({HS: "1.19.1", "dev.vitruvian.github": "1.4.1"}), [])
        self.pulls[branch]["state"] = "MERGED"
        self.assertEqual(self.plan({HS: "1.19.1", "dev.vitruvian.github": "1.4.1"}), [])

    def test_a_refused_version_is_skipped_while_its_issue_is_open(self):
        """Refused once: one red run and an issue, then no Bazel run each hour."""
        self.issues.add("catalog-bump refused dev.vitruvian.homespeaker 1.20.0")
        self.assertEqual(self.plan({HS: "1.19.1", "dev.vitruvian.github": "1.4.1"}), [])
        self.issues.clear()
        self.assertEqual(
            self.plan({HS: "1.19.1", "dev.vitruvian.github": "1.4.1"}),
            [{"id": HS, "tag": "home-speaker-v1.20.0"}],
        )

    def test_a_conflicting_branch_with_a_persons_commit_is_left_and_said_once(self):
        """I3 in the plan: seconds an hour, no Bazel, and one comment."""
        branch = bump.branch_for(HS, "1.20.0")
        self.pulls[branch] = {"number": 7, "state": "OPEN", "mergeable": "CONFLICTING"}
        helpers = WorkflowHelpersTest()
        self.compares[branch] = {
            "commits": [helpers.workflows(), helpers.commit("b" * 40, "raise floor")]
        }
        versions = {HS: "1.19.1", "dev.vitruvian.github": "1.4.1"}
        self.assertEqual(self.plan(versions), [])
        self.assertEqual(self.plan(versions), [])
        self.assertEqual(len(self.github.comments[7]), 1)
        self.assertIn("bbbbbbbbbbbb", self.github.comments[7][0])
        self.assertTrue(self.github.comments[7][0].startswith(bump.FOREIGN_MARK))

    def test_a_conflicting_branch_with_only_the_workflows_commit_is_rebuilt(self):
        branch = bump.branch_for(HS, "1.20.0")
        self.pulls[branch] = {"number": 7, "state": "OPEN", "mergeable": "CONFLICTING"}
        self.compares[branch] = {"commits": [WorkflowHelpersTest().workflows()]}
        self.assertEqual(
            self.plan({HS: "1.19.1", "dev.vitruvian.github": "1.4.1"}),
            [{"id": HS, "tag": "home-speaker-v1.20.0"}],
        )
        self.assertEqual(self.github.comments, {})


if __name__ == "__main__":
    unittest.main()
