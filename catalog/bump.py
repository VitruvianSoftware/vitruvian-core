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

"""Updates one tool's catalog entry from one of its releases.

    bazel run //catalog:bump -- --id dev.vitruvian.homespeaker --tag home-speaker-v1.20.0
    bazel run //catalog:bump -- --id ... --tag ... --release-dir <folder>
    python3 catalog/bump.py plan --out plan.json

`bump` reads the release through `gh` (or, with --release-dir, from a folder
holding release.json and the files, which is how the tests run it). It
refuses, and writes nothing, unless: the zip and its .sha256 were uploaded by
the account sources.json names for the tool; the zip's size and SHA-256 are
the ones GitHub records for the file, and the SHA-256 is the one the .sha256
says; the zip is safe to unpack; every Mach-O in it runs on the oldest macOS
the app runs on (LSMinimumSystemVersion in the app's Info.plist), and the
tool's program is universal when sources.json says it has been; and its
manifest has the entry's id and the tag's version. Then it writes the new
version, download, size and SHA-256, copies what the README says an entry
copies from the manifest (the summary, the name, what it uses, its
commands...), sets `generated`, and rewrites the website's _data/tools.yml as
//tools/sync-site-tools:sync does. It never touches minimumAppVersion: when
the manifest declares something only newer apps draw, it says so in the pull
request's text. It never touches the signed copy the website serves;
catalog-publish writes that after the merge.

Its result (--result-out) says whether the pull request may merge itself:
not when the tool asks for a new service, offers a new command, or changes
the words or the protocol the app shows; then it names each.

`plan` asks GitHub for the newest release of each row of sources.json and
prints the ones that are newer than the catalog: what the hourly workflow
bumps. `foreign` and `older` help the workflow decide what it may push and
close. Standard library only, apart from `gh`, so they run without Bazel.

Exit status: 0 done or nothing to do, 1 refused, 10 the release is not ready
(no zip yet, a draft), 11 the tool is not listed yet. The workflow reads the
result's `status`, not the exit status.
"""

import argparse
import copy
import hashlib
import json
import os
import plistlib
import re
import struct
import subprocess
import sys
import tempfile
import zipfile
from datetime import datetime, timedelta, timezone
from pathlib import Path

import catalog_rules

OK, REFUSED, NOT_READY, NOT_LISTED = 0, 1, 10, 11

CATALOG = "catalog/tools.json"
SCHEMA = "catalog/catalog.schema.json"
SOURCES = "catalog/sources.json"
APP_INFO = "apps/desktop/vitruvian/Resources/Info.plist"
HOME_REPO = "VitruvianSoftware/vitruvian-core"
BOT_EMAIL = "314429222+vitruvian-wren-agent[bot]@users.noreply.github.com"
BRANCH = re.compile(r"^catalog/bump-[a-z0-9.-]+-[0-9]+\.[0-9]+\.[0-9]+$")

# What a manifest may declare that an app older than the version given does
# not draw, from packages/vitruvian-sdk/protocol/README.md and the app's
# CHANGELOG. Each is a note for a person, never a change to the floor.
FEATURES = [
    (
        "protocol 2",
        lambda m: m.get("protocol") == "2",
        "3.45.0",
        "an older app refuses the tool",
    ),
    (
        "a status mark on the closed island (`contributes.status`)",
        lambda m: "status" in m.get("contributes", {}),
        "3.48.0",
        "an older app ignores it and shows no mark",
    ),
    (
        "a preference drawn as a menu (`options`)",
        lambda m: any("options" in p for p in m.get("preferences", [])),
        "3.48.0",
        "an older app draws a text field",
    ),
    (
        "a few words beside the status (`contributes.status.activity`)",
        lambda m: bool(m.get("contributes", {}).get("status", {}).get("activity")),
        "3.50.0",
        "an older app leaves the words out",
    ),
]


class Refused(Exception):
    """A release that must not be listed: each reason, said plainly."""

    def __init__(self, reasons):
        super().__init__("; ".join(reasons))
        self.reasons = list(reasons)


class NotReady(Exception):
    """A release that is not ready to list yet, which is not a failure."""


class NotListed(Exception):
    """A tool the catalog does not list: the first listing is by hand."""


def notice(message):
    """A line the run's summary shows when it runs in GitHub Actions."""
    prefix = "::notice::" if os.environ.get("GITHUB_ACTIONS") else ""
    print(prefix + message)


# --- The table of sources -----------------------------------------------------


def load_sources(path):
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    rows = data.get("sources", [])
    for row in rows:
        for key in ("id", "repo", "tagPrefix", "asset", "uploader"):
            if not isinstance(row.get(key), str) or not row[key]:
                raise SystemExit(f"sources.json: a row has no {key}: {row}")
        if "{version}" not in row["asset"]:
            raise SystemExit(f"sources.json: {row['id']}'s asset has no {{version}}")
        if not isinstance(row.get("universal", False), bool):
            raise SystemExit(
                f"sources.json: {row['id']}'s universal is not true or false"
            )
    return data


def row_for(sources, tool_id):
    for row in sources["sources"]:
        if row["id"] == tool_id:
            return row
    raise Refused(
        [f"{tool_id} has no row in catalog/sources.json, so no release updates it"]
    )


def version_of(row, tag):
    """The version a tag names, or None when it is not this row's tag."""
    if not tag.startswith(row["tagPrefix"]):
        return None
    version = tag[len(row["tagPrefix"]) :]
    return version if catalog_rules.semver(version) else None


def is_prerelease(version):
    return catalog_rules.semver(version)[3] == 0


def asset_name(row, version):
    return row["asset"].replace("{version}", version)


def download_url(row, tag, version):
    return f"https://github.com/{row['repo']}/releases/download/{tag}/{asset_name(row, version)}"


def branch_for(tool_id, version):
    return f"catalog/bump-{tool_id}-{version}"


# --- Where a release is read from ---------------------------------------------


def gh(args, run=subprocess.run):
    """`gh` with these arguments: its output as bytes, or None when it fails."""
    done = run(["gh", *args], capture_output=True)
    if done.returncode != 0:
        sys.stderr.write(done.stderr.decode("utf-8", "replace"))
        return None
    return done.stdout


class GhRelease:
    """A release on GitHub, read through `gh`."""

    def __init__(self, repo, tag):
        self.repo, self.tag = repo, tag

    def metadata(self):
        return gh_release(self.repo, self.tag)

    def fetch(self, asset):
        """The bytes of one asset, by its id, so no name is read as a pattern."""
        return gh(
            [
                "api",
                "-H",
                "Accept: application/octet-stream",
                f"repos/{self.repo}/releases/assets/{asset['id']}",
            ]
        )


class FolderRelease:
    """A release kept in a folder: release.json, shaped like GitHub's answer,
    and each asset's file beside it."""

    def __init__(self, folder):
        self.folder = Path(folder)

    def metadata(self):
        path = self.folder / "release.json"
        if not path.exists():
            return None
        return json.loads(path.read_text(encoding="utf-8"))

    def fetch(self, asset):
        path = self.folder / asset["name"]
        return path.read_bytes() if path.exists() else None


# --- Mach-O: which Macs a program runs on --------------------------------------

FAT_MAGIC, FAT_MAGIC_64 = 0xCAFEBABE, 0xCAFEBABF
MH_MAGIC, MH_MAGIC_64 = 0xFEEDFACE, 0xFEEDFACF
LC_VERSION_MIN_MACOSX, LC_BUILD_VERSION = 0x24, 0x32
PLATFORM_MACOS = 1
CPU = {0x01000007: "x86_64", 0x0100000C: "arm64", 7: "i386", 12: "arm"}


def version_text(version):
    """14.0, 15.4, 13.5.1: as vtool -show-build says it."""
    major, minor, patch = version
    return f"{major}.{minor}" + (f".{patch}" if patch else "")


def macho_slices(data):
    """[(architecture, oldest macOS as (major, minor, patch) or None)] for a
    Mach-O, one per architecture; None when `data` is not a Mach-O. Raises
    ValueError for one that cannot be read."""
    if len(data) < 8:
        return None
    (big,) = struct.unpack(">I", data[:4])
    if big in (FAT_MAGIC, FAT_MAGIC_64):
        (count,) = struct.unpack(">I", data[4:8])
        if count == 0 or count > 32:
            return None  # 0xCAFEBABE is also a Java class file.
        size = 20 if big == FAT_MAGIC else 32
        slices = []
        for index in range(count):
            at = 8 + index * size
            if big == FAT_MAGIC:
                _, _, offset, length, _ = struct.unpack(">iiIII", data[at : at + 20])
            else:
                _, _, offset, length, _, _ = struct.unpack(
                    ">iiQQII", data[at : at + 32]
                )
            thin = thin_slice(data[offset : offset + length])
            if thin is None:
                raise ValueError(f"architecture {index} is not a Mach-O")
            slices.append(thin)
        return slices
    thin = thin_slice(data)
    return [thin] if thin else None


def thin_slice(data):
    """(architecture, oldest macOS) of one architecture's Mach-O, or None."""
    if len(data) < 28:
        return None
    (magic,) = struct.unpack("<I", data[:4])
    if magic not in (MH_MAGIC, MH_MAGIC_64):
        return None
    cputype, _, _, ncmds, _, _ = struct.unpack("<iiIIII", data[4:28])
    at = 32 if magic == MH_MAGIC_64 else 28
    oldest = None
    for _ in range(ncmds):
        if at + 8 > len(data):
            raise ValueError("its load commands run past its end")
        cmd, cmdsize = struct.unpack("<II", data[at : at + 8])
        if cmdsize < 8 or at + cmdsize > len(data):
            raise ValueError("a load command has a bad size")
        if cmd == LC_BUILD_VERSION and cmdsize >= 16:
            platform, raw = struct.unpack("<II", data[at + 8 : at + 16])
            if platform == PLATFORM_MACOS:
                oldest = (raw >> 16, (raw >> 8) & 0xFF, raw & 0xFF)
        elif cmd == LC_VERSION_MIN_MACOSX and cmdsize >= 12 and oldest is None:
            (raw,) = struct.unpack("<I", data[at + 8 : at + 12])
            oldest = (raw >> 16, (raw >> 8) & 0xFF, raw & 0xFF)
        at += cmdsize
    return CPU.get(cputype, hex(cputype)), oldest


def app_oldest_macos(root):
    """The oldest macOS the app runs on, from its Info.plist."""
    with open(root / APP_INFO, "rb") as handle:
        text = plistlib.load(handle).get("LSMinimumSystemVersion", "")
    parts = text.split(".")
    if not 1 <= len(parts) <= 3 or not all(p.isdigit() for p in parts):
        raise SystemExit(f"{APP_INFO}: LSMinimumSystemVersion is {text!r}")
    return tuple(int(p) for p in (parts + ["0", "0"])[:3])


def binary_problems(row, archive, manifest, oldest):
    """Every Mach-O in the zip must run on `oldest`; the tool's program must
    be x86_64 and arm64 when the row says it has been."""
    found, programs = [], {}
    for info in archive.infolist():
        if info.is_dir():
            continue
        try:
            slices = macho_slices(archive.read(info))
        except ValueError as error:
            found.append(f"{info.filename} is a Mach-O that cannot be read: {error}")
            continue
        if slices:
            programs[info.filename] = slices
    for name, slices in sorted(programs.items()):
        for arch, needs in slices:
            if needs is None:
                found.append(f"{name} ({arch}) names no oldest macOS")
            elif needs > oldest:
                found.append(
                    f"{name} ({arch}) needs macOS {version_text(needs)}; the app runs "
                    f"on macOS {version_text(oldest)}, where it would install and fail"
                )
    if row.get("universal"):
        program = manifest.get("runtime", {}).get("exec", "")
        archs = sorted({arch for arch, _ in programs.get(program, [])})
        if not {"x86_64", "arm64"} <= set(archs):
            found.append(
                f"{program or 'its program'} is {', '.join(archs) or 'not a Mach-O'}, "
                f"not universal (x86_64 and arm64), as {row['id']}'s has been"
            )
    return found


# --- The checks ---------------------------------------------------------------

SIDECAR = re.compile(r"^([0-9a-f]{64})\s+\*?(\S.*?)\s*$")


def checked_zip(row, tag, version, release, work, oldest):
    """The release, and its zip written into `work`, once every check passed:
    the release's metadata, the zip's SHA-256, size and manifest. Raises
    NotReady or Refused."""
    meta = release.metadata()
    if meta is None:
        raise NotReady(f"{row['repo']} has no release tagged {tag}")
    if meta.get("draft") or meta.get("prerelease"):
        raise NotReady(f"{tag} is a draft or a pre-release")
    assets = {a.get("name"): a for a in meta.get("assets", [])}
    name = asset_name(row, version)
    asset = assets.get(name)
    if asset is None:
        raise NotReady(f"{tag} has no {name} yet")
    reasons = []
    sidecar = assets.get(name + ".sha256")
    if sidecar is None:
        reasons.append(f"{tag} has {name} but no {name}.sha256 to check it against")
    for each in (asset, sidecar):
        who = ((each or {}).get("uploader") or {}).get("login")
        if each is not None and who != row["uploader"]:
            reasons.append(
                f"{each['name']} was uploaded by {who or 'nobody GitHub names'}, "
                f"not {row['uploader']}, who uploads {row['id']}'s releases"
            )
    digest = asset.get("digest") or ""
    if not digest.startswith("sha256:"):
        reasons.append(f"GitHub records no SHA-256 for {name} ({digest or 'none'})")
    if reasons:
        raise Refused(reasons)

    data = release.fetch(asset)
    if data is None:
        raise Refused([f"{name} could not be downloaded"])
    sha = hashlib.sha256(data).hexdigest()
    if len(data) != asset.get("size"):
        reasons.append(f"{name} is {len(data)} bytes, GitHub says {asset.get('size')}")
    if sha != digest[len("sha256:") :]:
        reasons.append(f"{name}'s SHA-256 is {sha}, GitHub says {digest}")
    side = release.fetch(sidecar)
    match = SIDECAR.match((side or b"").decode("utf-8", "replace").split("\n")[0])
    if not match:
        reasons.append(f"{name}.sha256 is not `<sha256>  <file name>`")
    else:
        if match.group(1) != sha:
            reasons.append(f"{name}.sha256 says {match.group(1)}, the zip's is {sha}")
        if os.path.basename(match.group(2)) != name:
            reasons.append(f"{name}.sha256 is the checksum of {match.group(2)}")
    if reasons:
        raise Refused(reasons)

    path = Path(work) / name
    path.write_bytes(data)
    problems = catalog_rules.zip_problems(path)
    if problems:
        raise Refused([f"{name}: {p}" for p in problems])
    with zipfile.ZipFile(path) as archive:
        try:
            manifest = json.loads(archive.read("vitruvian-tool.json"))
        except (KeyError, ValueError) as error:
            raise Refused([f"{name}'s vitruvian-tool.json cannot be read: {error}"])
        if manifest.get("id") != row["id"]:
            reasons.append(
                f"the manifest's id is {manifest.get('id')}, not {row['id']}"
            )
        if manifest.get("version") != version:
            reasons.append(
                f"the manifest's version is {manifest.get('version')}, the tag's is {version}"
            )
        reasons += binary_problems(row, archive, manifest, oldest)
    if reasons:
        raise Refused(reasons)
    return meta, sha, len(data), manifest


# --- The entry ----------------------------------------------------------------


def from_manifest(entry, manifest):
    """The fields an entry copies from its manifest (catalog/README.md), set
    to what the manifest says. Returns the names of the fields that changed.
    `uses` keeps the entry's order when only the order differs."""
    contributes = manifest.get("contributes", {})
    wanted = [
        ("name", manifest.get("name")),
        ("publisher", manifest.get("publisher")),
        ("protocol", manifest.get("protocol")),
        ("summary", manifest.get("description")),
        ("uses", list(manifest.get("uses", []))),
        (
            "commands",
            [
                {"id": c.get("id"), "title": c.get("title")}
                for c in contributes.get("commands", [])
            ],
        ),
    ]
    if "panels" in entry:
        wanted.append(
            ("panels", [p.get("placement") for p in contributes.get("panels", [])])
        )
    changed = []
    for field, value in wanted:
        same = (
            sorted(entry.get(field, [])) == sorted(value)
            if field == "uses"
            else entry.get(field) == value
        )
        if not same:
            entry[field] = value
            changed.append(field)
    return changed


def for_a_person(old, new, manifest):
    """Why the pull request must wait for a person, if it must: what the tool
    newly asks for or offers, or words and a protocol the app shows that
    changed. Taking something away, or a new version alone, is not a reason."""
    reasons = []
    added_uses = [u for u in new.get("uses", []) if u not in old.get("uses", [])]
    if added_uses:
        reasons.append(
            "It asks for a service it did not ask for before: "
            + ", ".join(f"`{u}`" for u in added_uses)
            + ". Read what its source does with it."
        )
    old_commands = {c["id"]: c for c in old.get("commands", [])}
    added = [c["id"] for c in new.get("commands", []) if c["id"] not in old_commands]
    if added:
        reasons.append(
            "It offers new commands: " + ", ".join(f"`{c}`" for c in added) + "."
        )
    retitled = [
        c["id"]
        for c in new.get("commands", [])
        if c["id"] in old_commands and old_commands[c["id"]]["title"] != c["title"]
    ]
    words = [f for f in ("name", "publisher", "summary") if old.get(f) != new.get(f)]
    words += [f"the title of `{c}`" for c in retitled]
    if old.get("panels") != new.get("panels") and "panels" in old:
        added_panels = [p for p in new["panels"] if p not in old["panels"]]
        if added_panels:
            words.append("its panels")
    if words:
        reasons.append(
            "The words or panels the app shows changed: " + ", ".join(words) + "."
        )
    if old.get("protocol") != new.get("protocol"):
        reasons.append(
            f"Its protocol changed from {old.get('protocol')} to {new.get('protocol')}."
        )
    if "panels" not in old and manifest.get("contributes", {}).get("panels"):
        reasons.append(
            "The manifest draws panels the entry does not list; add `panels` by hand "
            "if the catalog should show them."
        )
    return reasons


def floor_notes(manifest, floor):
    """What the manifest declares that apps from before the current floor do
    not have, each with the version that has it."""
    notes = []
    for what, declared, since, older in FEATURES:
        if declared(manifest) and catalog_rules.semver(since) > catalog_rules.semver(
            floor
        ):
            notes.append(f"It declares {what}, which Vitruvian {since} draws; {older}.")
    return notes


def next_generated(previous, now):
    """Now, in UTC to the second, and always later than the list it replaces:
    the app refuses a list older than one it has seen."""
    stamp = now.astimezone(timezone.utc).replace(microsecond=0)
    before = catalog_rules.generated({"generated": previous})
    if before is not None and stamp <= before:
        stamp = before + timedelta(seconds=1)
    return stamp.strftime("%Y-%m-%dT%H:%M:%SZ")


# --- tools.json, written the way it is written by hand -------------------------


def dumps(value, indent=0):
    """JSON as tools.json is kept: two spaces, a list of plain values on one
    line, everything else one item a line, and every language as itself."""
    pad, inner = "  " * indent, "  " * (indent + 1)
    if isinstance(value, dict):
        if not value:
            return "{}"
        items = [
            f"{inner}{json.dumps(k, ensure_ascii=False)}: {dumps(v, indent + 1)}"
            for k, v in value.items()
        ]
        return "{\n" + ",\n".join(items) + "\n" + pad + "}"
    if isinstance(value, list):
        if all(not isinstance(v, (dict, list)) for v in value):
            return (
                "[" + ", ".join(json.dumps(v, ensure_ascii=False) for v in value) + "]"
            )
        items = [inner + dumps(v, indent + 1) for v in value]
        return "[\n" + ",\n".join(items) + "\n" + pad + "]"
    return json.dumps(value, ensure_ascii=False)


def schema_problems(root, catalog):
    from jsonschema import Draft202012Validator

    schema = json.loads((root / SCHEMA).read_text(encoding="utf-8"))
    return [
        f"schema: {'/'.join(map(str, e.path))}: {e.message}"
        for e in Draft202012Validator(schema).iter_errors(catalog)
    ]


def write_site(root):
    """_data/tools.yml, as //tools/sync-site-tools:sync writes it."""
    try:
        import catalogue
    except ImportError:
        sys.path.insert(0, str(root / "tools" / "sync-site-tools"))
        import catalogue
    for path, data in catalogue.outputs(root).items():
        (root / path).parent.mkdir(parents=True, exist_ok=True)
        (root / path).write_bytes(data)
        print(f"wrote {path}")


# --- bump ---------------------------------------------------------------------


def short(sha):
    return f"{sha[:8]}…{sha[-4:]}"


def body_for(row, tag, entry, previous, size, sha, changed, notes, waits, links):
    name = entry["name"]["en"]
    release_url, compare_url = links
    lines = [
        f"The tool catalog now offers {name} {entry['version']}. It offered {previous}.",
        "",
    ]
    if waits:
        lines += ["**This one waits for a person** (label `needs-human`):", ""]
        lines += [f"- {reason}" for reason in waits]
        lines.append("")
    else:
        lines += [
            "Nothing it asks for or shows changed, so it merges itself once its "
            "checks pass.",
            "",
        ]
    lines += [
        f"- **The release:** [{tag}]({release_url}). **What changed in the "
        f"source:** [{row['tagPrefix']}{previous}...{tag}]({compare_url}).",
        f"- **The download:** `{asset_name(row, entry['version'])}`, {size} bytes, "
        f"SHA-256 `{short(sha)}`, uploaded by `{row['uploader']}`.",
    ]
    if changed:
        lines.append(
            "- **Also copied from the tool's manifest**, as an entry says what its "
            f"manifest says: {', '.join(f'`{f}`' for f in changed)}."
        )
    floor = entry["minimumAppVersion"]
    if notes:
        lines.append(f"- **Oldest app version stays {floor}.** " + " ".join(notes))
    else:
        lines.append(
            f"- **Oldest app version stays {floor}:** the manifest declares nothing "
            "an app that old lacks."
        )
    lines += [
        "- **Website data:** `_data/tools.yml` is regenerated, as "
        "`bazel run //tools/sync-site-tools:sync` writes it.",
        "",
        "**What the checks prove, and what they don't:** they prove this is the "
        "file the release's own workflow uploaded, unchanged, and that it is a "
        "tool for every Mac the app runs on; they do not prove the release's code "
        "is safe, which is what the source link above is for.",
        "",
        "Checked by `bazel run //catalog:bump` before this opened: the uploader; "
        "the zip's size and SHA-256 against GitHub's record and the release's "
        "`.sha256`; a zip that unpacks safely; each program's oldest macOS and "
        "its architectures; the manifest's id and version; the catalog's schema "
        "and rules. **catalog-check** downloads it again and runs "
        "`vitruvian-tool validate`.",
        "",
        "After the merge, catalog-publish signs the list and opens the pull request "
        "for the website. Opened by the catalog-bump workflow.",
    ]
    return "\n".join(lines) + "\n"


def bump(root, sources, tool_id, tag, release, now):
    """Updates the entry in root's tools.json and tools.yml. Returns what the
    pull request needs; raises Refused, NotReady or NotListed."""
    row = row_for(sources, tool_id)
    version = version_of(row, tag)
    if version is None:
        raise Refused(
            [
                f"{tag} is not a tag of {tool_id}: its tags are {row['tagPrefix']}<version>"
            ]
        )
    _, catalog = catalog_rules.load(root / CATALOG)
    index = next(
        (i for i, t in enumerate(catalog["tools"]) if t["id"] == tool_id), None
    )
    if index is None:
        raise NotListed(
            f"{tool_id} is not in the catalog yet; listing it the first time is a "
            "pull request by hand (catalog/README.md)"
        )
    entry = catalog["tools"][index]
    previous = entry["version"]
    if not BRANCH.match(branch_for(tool_id, version)):
        raise Refused(
            [
                f"{branch_for(tool_id, version)} is not a bump branch: X.Y.Z releases only"
            ]
        )
    if catalog_rules.semver(version) < catalog_rules.semver(previous):
        raise Refused([f"the catalog lists {previous}, newer than {version}"])

    oldest = app_oldest_macos(root)
    with tempfile.TemporaryDirectory() as work:
        meta, sha, size, manifest = checked_zip(
            row, tag, version, release, work, oldest
        )

    url = download_url(row, tag, version)
    if version == previous:
        if entry["download"] == {"url": url, "sha256": sha, "size": size}:
            return {"status": "current", "id": tool_id, "version": version}
        raise Refused(
            [
                f"the catalog lists {version} with another download; the release's "
                "zip changed after it was listed, or the entry was edited by hand"
            ]
        )

    new = copy.deepcopy(entry)
    new["version"] = version
    new["download"] = {"url": url, "sha256": sha, "size": size}
    changed = from_manifest(new, manifest)
    catalog["tools"][index] = new
    catalog["generated"] = next_generated(catalog["generated"], now)

    problems = (
        schema_problems(root, catalog)
        + catalog_rules.problems(catalog)
        + catalog_rules.manifest_problems(new, manifest)
    )
    if problems:
        raise Refused(problems)

    (root / CATALOG).write_text(dumps(catalog) + "\n", encoding="utf-8")
    print(f"wrote {CATALOG}: {tool_id} {previous} -> {version}")
    write_site(root)
    waits = for_a_person(entry, new, manifest)
    links = (
        meta.get("html_url") or f"https://github.com/{row['repo']}/releases/tag/{tag}",
        f"https://github.com/{row['repo']}/compare/{row['tagPrefix']}{previous}...{tag}",
    )
    notes = floor_notes(manifest, new["minimumAppVersion"])
    return {
        "status": "bumped",
        "id": tool_id,
        "version": version,
        "previous": previous,
        "tag": tag,
        "branch": branch_for(tool_id, version),
        "title": f"feat(catalog): {new['name']['en']} {version}",
        "automerge": not waits,
        "body": body_for(
            row, tag, new, previous, size, sha, changed, notes, waits, links
        ),
    }


# --- plan ---------------------------------------------------------------------


def plan(catalog, sources, list_tags, get_release, find_pull):
    """The rows whose newest published release is newer than their entry,
    has its zip, and has no pull request for it: none open that still merges
    (one that no longer merges is rebuilt), and none closed (a person said
    no; reopening it, or a run by hand, brings it back)."""
    listed = {t["id"]: t for t in catalog["tools"]}
    found = []
    for row in sources["sources"]:
        entry = listed.get(row["id"])
        if entry is None:
            notice(
                f"{row['id']} is not in the catalog yet: the first listing is by hand."
            )
            continue
        floor = catalog_rules.semver(entry["version"])
        versions = sorted(
            (
                (catalog_rules.semver(v), v, tag)
                for tag in list_tags(row["repo"], row["tagPrefix"])
                for v in [version_of(row, tag)]
                if v and not is_prerelease(v)
            ),
            reverse=True,
        )
        newest = None
        for key, version, tag in versions:
            if key <= floor:
                break
            release = get_release(row["repo"], tag)
            if release and not release.get("draft") and not release.get("prerelease"):
                newest = (tag, version, release)
                break
        if newest is None:
            print(
                f"{row['id']}: the catalog lists {entry['version']}, the newest release."
            )
            continue
        tag, version, release = newest
        if asset_name(row, version) not in {
            a.get("name") for a in release.get("assets", [])
        }:
            notice(
                f"{row['id']}: {tag} has no {asset_name(row, version)} yet; skipped."
            )
            continue
        pull = find_pull(branch_for(row["id"], version))
        state = (pull or {}).get("state")
        if state == "OPEN" and pull.get("mergeable") != "CONFLICTING":
            print(f"{row['id']} {version}: pull request #{pull['number']} is open.")
            continue
        if state in ("CLOSED", "MERGED"):
            notice(
                f"{row['id']} {version}: pull request #{pull['number']} was "
                f"{'closed without merging' if state == 'CLOSED' else 'merged'}; "
                "skipped. Reopen it, or run catalog-bump by hand with the tag."
            )
            continue
        print(f"{row['id']}: {tag} is newer than the catalog's {entry['version']}.")
        found.append({"id": row["id"], "tag": tag})
    return found


def gh_tags(repo, prefix):
    out = gh(
        [
            "api",
            "--paginate",
            "--jq",
            ".[].ref",
            f"repos/{repo}/git/matching-refs/tags/{prefix}",
        ]
    )
    if out is None:
        raise SystemExit(f"could not list the tags of {repo}")
    return [
        line.removeprefix("refs/tags/")
        for line in out.decode("utf-8").split()
        if line.startswith("refs/tags/")
    ]


def gh_release(repo, tag):
    """A release's metadata, or None when the tag has no release."""
    done = subprocess.run(
        ["gh", "api", f"repos/{repo}/releases/tags/{tag}"], capture_output=True
    )
    if done.returncode == 0:
        return json.loads(done.stdout)
    if b"Not Found" in done.stdout + done.stderr:
        return None
    sys.stderr.write(done.stderr.decode("utf-8", "replace"))
    raise SystemExit(f"could not read the release {tag} of {repo}")


def gh_pull(branch):
    """The newest pull request from `branch`, open, closed or merged."""
    repo = os.environ.get("GITHUB_REPOSITORY", HOME_REPO)
    out = gh(
        [
            "pr",
            "list",
            "--repo",
            repo,
            "--head",
            branch,
            "--state",
            "all",
            "--json",
            "number,state,mergeable",
        ]
    )
    if out is None:
        raise SystemExit(f"could not list the pull requests of {repo}")
    pulls = sorted(json.loads(out), key=lambda p: p["number"], reverse=True)
    return pulls[0] if pulls else None


# --- What the workflow may push and close -------------------------------------


def foreign(compare, bot_email=BOT_EMAIL):
    """The commits on a bump branch (GitHub's compare of main...branch) that
    the workflow did not write: a person's, which a rebuild must not erase."""
    return [
        f"{c['sha'][:12]} by {c['commit']['author']['name']}"
        for c in compare.get("commits", [])
        if c["commit"]["author"]["email"] != bot_email
    ]


def older(pulls, tool_id, version):
    """The open bump pull requests for an older version of the same tool."""
    prefix = f"catalog/bump-{tool_id}-"
    mine = catalog_rules.semver(version)
    found = []
    for pull in pulls:
        head = pull["headRefName"]
        theirs = (
            catalog_rules.semver(head[len(prefix) :])
            if head.startswith(prefix)
            else None
        )
        if theirs is not None and theirs < mine:
            found.append(pull["number"])
    return found


# --- The command --------------------------------------------------------------


def workspace(given):
    if given:
        return Path(given)
    if os.environ.get("BUILD_WORKSPACE_DIRECTORY"):
        return Path(os.environ["BUILD_WORKSPACE_DIRECTORY"])
    return Path(__file__).resolve().parent.parent


def main(argv=None, list_tags=gh_tags, get_release=gh_release, find_pull=gh_pull):
    argv = list(sys.argv[1:] if argv is None else argv)
    if not argv or argv[0] not in ("bump", "plan", "foreign", "older"):
        argv.insert(0, "bump")
    parser = argparse.ArgumentParser(
        description="Updates one tool's catalog entry from one of its releases."
    )
    commands = parser.add_subparsers(dest="command", required=True)
    one = commands.add_parser("bump", help="update one entry from one release")
    one.add_argument(
        "--id", required=True, help="the catalog entry, e.g. dev.vitruvian.homespeaker"
    )
    one.add_argument(
        "--tag", required=True, help="the release, e.g. home-speaker-v1.20.0"
    )
    one.add_argument(
        "--release-dir", help="read the release from this folder, not GitHub"
    )
    one.add_argument(
        "--result-out", help="write what the pull request needs here, as JSON"
    )
    one.add_argument("--now", help="the time to set generated to (tests)")
    one.add_argument("--root", help="the repository (default: where bazel run started)")
    many = commands.add_parser("plan", help="which releases are newer than the catalog")
    many.add_argument("--out", help="write the list here, as JSON")
    many.add_argument("--root", help="the repository (default: this file's)")
    mine = commands.add_parser("foreign", help="commits on a branch a person wrote")
    mine.add_argument("--compare", required=True, help="GitHub's compare, as JSON")
    old = commands.add_parser("older", help="open bump PRs for older versions")
    old.add_argument(
        "--pulls", required=True, help="gh pr list --json number,headRefName"
    )
    old.add_argument("--id", required=True)
    old.add_argument("--version", required=True)
    args = parser.parse_args(argv)

    if args.command == "foreign":
        for line in foreign(json.loads(Path(args.compare).read_text(encoding="utf-8"))):
            print(line)
        return OK
    if args.command == "older":
        pulls = json.loads(Path(args.pulls).read_text(encoding="utf-8"))
        for number in older(pulls, args.id, args.version):
            print(number)
        return OK

    root = workspace(args.root)
    sources = load_sources(root / SOURCES)

    if args.command == "plan":
        _, catalog = catalog_rules.load(root / CATALOG)
        found = plan(catalog, sources, list_tags, get_release, find_pull)
        if args.out:
            Path(args.out).write_text(json.dumps(found) + "\n", encoding="utf-8")
        print(json.dumps(found))
        return OK

    release = (
        FolderRelease(args.release_dir)
        if args.release_dir
        else GhRelease(row_for_or_exit(sources, args.id)["repo"], args.tag)
    )
    now = (
        datetime.strptime(args.now, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
        if args.now
        else datetime.now(timezone.utc)
    )
    try:
        result = bump(root, sources, args.id, args.tag, release, now)
        status = OK
    except NotReady as why:
        notice(f"{args.id} {args.tag}: skipped, {why}.")
        result, status = {"status": "not-ready", "message": str(why)}, NOT_READY
    except NotListed as why:
        notice(f"{args.id}: skipped, {why}.")
        result, status = {"status": "not-listed", "message": str(why)}, NOT_LISTED
    except Refused as why:
        for reason in why.reasons:
            print(f"NOT OK   {args.id} {args.tag}: {reason}", file=sys.stderr)
        print("Nothing was written.", file=sys.stderr)
        result, status = {"status": "refused", "message": str(why)}, REFUSED
    if result.get("status") == "current":
        print(f"{args.id}: the catalog already lists {args.tag}. Nothing to do.")
    if args.result_out:
        Path(args.result_out).write_text(
            json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
    return status


def row_for_or_exit(sources, tool_id):
    try:
        return row_for(sources, tool_id)
    except Refused as why:
        raise SystemExit(str(why))


if __name__ == "__main__":
    sys.exit(main())
