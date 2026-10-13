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

"""The rules of the tool catalog that JSON Schema cannot say, and the checks
the catalog's pull requests share: whether a zip is safe to unpack, and
whether a tool's manifest says what its entry copies.

Standard library only, so a contributor can run it with any Python 3.
"""

import json
import os
import re
import stat
import zipfile
from datetime import datetime, timezone
from urllib.parse import urlsplit

# The most a tool's folder may hold, as the app counts it (ToolLimits in the
# app, FolderLimits in the SDK): bytes, and files, folders and links together.
FOLDER_BYTES = 256 * 1_048_576
FOLDER_ITEMS = 10_000

# Where a download may come from. A host is added here, and to the pattern of
# `download.url` in catalog.schema.json, by a pull request James reviews.
DOWNLOAD_PREFIXES = ("https://github.com/VitruvianSoftware/",)

SEMVER = re.compile(
    r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?$"
)


def load(path):
    """The catalog file, as bytes and as data."""
    with open(path, "rb") as handle:
        data = handle.read()
    return data, json.loads(data)


def semver(text):
    """A version as a tuple that sorts like semver, or None. A pre-release
    sorts before its release; its identifiers compare as text."""
    match = SEMVER.match(text or "")
    if not match:
        return None
    core = tuple(int(part) for part in match.groups()[:3])
    pre = match.group(4)
    return core + ((0, pre[1:]) if pre else (1, ""))


def generated(catalog):
    """When the list was written, or None."""
    try:
        return datetime.strptime(catalog["generated"], "%Y-%m-%dT%H:%M:%SZ").replace(
            tzinfo=timezone.utc
        )
    except (KeyError, TypeError, ValueError):
        return None


def url_problems(where, url):
    """A download address must be https, from a listed place, with no
    segment that walks up or stands still, and nothing escaped."""
    problems = []
    parts = urlsplit(url or "")
    if not any((url or "").startswith(prefix) for prefix in DOWNLOAD_PREFIXES):
        problems.append(f"{where}: the download is not from a listed place ({url})")
    if parts.query or parts.fragment or "%" in (url or "") or "\\" in (url or ""):
        problems.append(
            f"{where}: the download address has a query, a fragment or an escape ({url})"
        )
    if any(segment in (".", "..") for segment in parts.path.split("/")):
        problems.append(
            f"{where}: the download address walks up or stands still ({url})"
        )
    return problems


def problems(catalog):
    """What is wrong with a catalog that already passed its schema."""
    found = []
    if generated(catalog) is None:
        found.append("generated is not a time in UTC, written 2026-11-02T10:00:00Z")
    seen = set()
    for index, tool in enumerate(catalog.get("tools", [])):
        where = f"tools[{index}] ({tool.get('id')})"
        if tool.get("id") in seen:
            found.append(f"{where}: the id is listed twice")
        seen.add(tool.get("id"))
        for field in ("version", "minimumAppVersion"):
            if semver(tool.get(field)) is None:
                found.append(f"{where}: {field} is not a version like 1.2.0")
        found.extend(url_problems(where, tool.get("download", {}).get("url")))
        commands = [command.get("id") for command in tool.get("commands", [])]
        if len(commands) != len(set(commands)):
            found.append(f"{where}: two commands share an id")
    return found


def changed(base, head):
    """The entries of `head` that are new, or differ from the same id in
    `base`: the ones whose download a pull request must check."""
    before = {tool["id"]: tool for tool in base.get("tools", [])}
    return [tool for tool in head.get("tools", []) if before.get(tool["id"]) != tool]


# --- A tool's zip -------------------------------------------------------------


def name_problem(name):
    """Why an entry's name would leave the folder it is unpacked in, or None."""
    if not name or "\x00" in name or "\\" in name:
        return "an empty name, a NUL or a backslash"
    if name.startswith("/") or name.startswith("~"):
        return "an absolute path"
    parts = name.rstrip("/").split("/")
    if any(part in ("", ".", "..") for part in parts):
        return "a part that is empty, . or .."
    return None


def zip_problems(path, folder_bytes=FOLDER_BYTES, folder_items=FOLDER_ITEMS):
    """What makes the zip at `path` unsafe or too large to unpack, read from
    its central directory before anything is written. The app makes the
    same checks (CatalogueArchive.vet) before it unpacks."""
    try:
        archive = zipfile.ZipFile(path)
    except (zipfile.BadZipFile, OSError):
        return ["it is not a zip"]
    found = []
    total = 0
    with archive:
        entries = archive.infolist()
        if len(entries) > folder_items:
            found.append(f"it holds {len(entries)} things, more than {folder_items}")
        for entry in entries:
            total += entry.file_size
            problem = name_problem(entry.filename)
            if problem:
                found.append(f"{entry.filename!r} has {problem}")
            mode = entry.external_attr >> 16
            if entry.create_system == 3 and stat.S_ISLNK(mode):
                found.append(f"{entry.filename!r} is a link")
            if entry.flag_bits & 0x1:
                found.append(f"{entry.filename!r} is encrypted")
        if total > folder_bytes:
            found.append(f"it unpacks to {total} bytes, more than {folder_bytes}")
        if "vitruvian-tool.json" not in archive.namelist():
            found.append("it has no vitruvian-tool.json at its top")
    return found


def unpack(path, folder):
    """Unpacks a zip that `zip_problems` passed, keeping each program's
    execute bit."""
    with zipfile.ZipFile(path) as archive:
        for entry in archive.infolist():
            written = archive.extract(entry, folder)
            mode = entry.external_attr >> 16
            if not entry.is_dir() and mode & 0o111:
                os.chmod(written, 0o755)


# --- The manifest against its entry -------------------------------------------


def manifest_problems(entry, manifest):
    """Where the tool's own manifest and the catalog's copy of it disagree."""
    found = []
    pairs = [
        ("id", manifest.get("id"), entry.get("id")),
        ("version", manifest.get("version"), entry.get("version")),
        ("protocol", manifest.get("protocol"), entry.get("protocol")),
        ("name", manifest.get("name"), entry.get("name")),
        ("publisher", manifest.get("publisher"), entry.get("publisher")),
        ("summary", manifest.get("description"), entry.get("summary")),
        ("uses", sorted(manifest.get("uses", [])), sorted(entry.get("uses", []))),
        (
            "commands",
            [
                {"id": c.get("id"), "title": c.get("title")}
                for c in manifest.get("contributes", {}).get("commands", [])
            ],
            entry.get("commands", []),
        ),
    ]
    for field, theirs, ours in pairs:
        if theirs != ours:
            found.append(
                f"{field}: the manifest says {json.dumps(theirs)}, the catalog says {json.dumps(ours)}"
            )
    return found
