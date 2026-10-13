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

"""The rules of the tool catalog that JSON Schema cannot say.

Standard library only, so a contributor can run it with any Python 3.
"""

import json
import re
from datetime import datetime, timezone
from urllib.parse import urlsplit

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
