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
"""Writes the Tools section of vitruviansoftware.dev from the SDK's own files.

    sync.py            writes the copies
    sync.py --check    fails when a copy is not what would be written

The site is built by Jekyll in safe mode in its own repository, so it cannot
read packages/vitruvian-sdk: the pages are copies, committed beside the
hand-written ones in apps/web/vitruviansoftware-dev/tools/. Each copy is its
source with a front matter added, its first heading taken as the page's
title, its links turned into links that work on the site, and the words after
a code fence's language dropped (the guide's test reads them; the site does
not). The code inside every fence is the source's, byte for byte, and this
script refuses to write a page where it is not. A test runs it with --check,
the way templates_in_sync_test holds `vitruvian-tool init`'s copies.

No version number is copied: a release changes none of these files, so a
release never makes the site stale.
"""

import json
import os
import re
import sys
from pathlib import Path

import catalogue
import registry

SDK = "packages/vitruvian-sdk"
SITE = "apps/web/vitruviansoftware-dev"
MIRROR = "https://github.com/VitruvianSoftware/vitruvian-sdk"

# Where a file of the SDK is on the site, for links between the copies.
ON_SITE = {
    "docs/writing-a-tool.md": "/tools/guide/",
    "protocol/README.md": "/tools/protocol/",
    "samples/hello-swift": "/tools/examples/swift/",
    "samples/hello-python": "/tools/examples/python/",
    "samples/hello-typescript": "/tools/examples/typescript/",
    "samples/hello-python-kit": "/tools/examples/python-kit/",
    "samples/hello-go": "/tools/examples/go/",
    "samples/hello-rust": "/tools/examples/rust/",
}

FENCE = re.compile(r"^(\s*)(```+)(.*)$")
LINK = re.compile(r"\[([^\]]*)\]\(([^)\s]+)\)")


def root():
    """The repository: where `bazel run` was started, else three folders up
    from this file, which is also where it is among a test's runfiles."""
    return os.environ.get("BUILD_WORKSPACE_DIRECTORY") or os.path.dirname(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    )


def read(base, path):
    with open(os.path.join(base, path), encoding="utf-8") as handle:
        return handle.read()


def fenced(text):
    """The body of every fenced block, in order."""
    bodies, body = [], None
    for line in text.split("\n"):
        if FENCE.match(line):
            if body is None:
                body = []
            else:
                bodies.append("\n".join(body))
                body = None
        elif body is not None:
            body.append(line)
    return bodies


def site_link(target, folder):
    """A link in an SDK file, as it must be on the site. A path whose last
    part has no dot is a folder: decided by the name, not the disk, so the
    test, which sees only some of the SDK's files, writes what a checkout
    writes."""
    if re.match(r"^[a-z]+:|^#|^/", target):
        return target
    path, _, anchor = target.partition("#")
    path = os.path.normpath(os.path.join(folder, path))
    if path.startswith(".."):
        raise SystemExit(f"a link leaves the SDK: {target} in {folder}")
    if path in ON_SITE:
        found = ON_SITE[path]
    else:
        kind = "blob" if "." in os.path.basename(path) else "tree"
        found = f"{MIRROR}/{kind}/main/{path}"
    return found + ("#" + anchor if anchor else "")


def link(text, target, folder):
    """A whole link. Text that is a relative path in code, as in
    [`../samples/hello-python`](../samples/hello-python), becomes the path
    from the SDK's root, which means something on the site."""
    if text.startswith("`../") and text.endswith("`"):
        inner = text[1:-1]
        shown = os.path.normpath(os.path.join(folder, inner))
        text = "`" + shown + ("/" if inner.endswith("/") else "") + "`"
    return f"[{text}]({site_link(target, folder)})"


def page(front, body):
    """A page: its front matter, then its body, which Liquid leaves alone."""
    if "{% endraw" in body:
        raise SystemExit("a source holds `{% endraw`, which would end the raw block")
    lines = ["---"] + [f"{key}: {value}" for key, value in front] + ["---"]
    lines += [
        "{%- comment -%}",
        "  Written by tools/sync-site-tools/sync.py from packages/vitruvian-sdk.",
        "  Do not edit it: change the source, then run",
        "    bazel run //tools/sync-site-tools:sync",
        "{%- endcomment -%}",
        "{% raw %}",
        body.rstrip("\n"),
        "{% endraw %}",
    ]
    return "\n".join(lines) + "\n"


def from_markdown(base, source, permalink, description):
    """A page made of one Markdown file of the SDK."""
    text = read(os.path.join(base, SDK), source)
    first, _, rest = text.partition("\n")
    if not first.startswith("# "):
        raise SystemExit(f"{source} does not start with a `# ` heading")
    folder = os.path.dirname(source)
    out, inside = [], False
    for line in rest.lstrip("\n").split("\n"):
        match = FENCE.match(line)
        if match:
            if not inside:
                language = match.group(3).strip().split(" ")[0]
                line = match.group(1) + match.group(2) + language
            inside = not inside
        elif not inside:
            line = LINK.sub(lambda m: link(m.group(1), m.group(2), folder), line)
        out.append(line)
    body = "\n".join(out)
    if fenced(body) != fenced(rest):
        raise SystemExit(f"the code in {source} would not be copied byte for byte")
    front = [
        ("layout", "tools"),
        ("title", json.dumps(first[2:].strip())),
        ("description", json.dumps(description)),
        ("permalink", permalink),
        ("source", f"{SDK}/{source}"),
    ]
    return page(front, body), body


def methods_table(base):
    """Every message of the protocol, from methods.json."""
    table = json.loads(read(os.path.join(base, SDK), "protocol/methods.json"))
    rows = [
        "## Every message, from `methods.json`",
        "",
        "| Message | Sent by | Kind | In `uses` |",
        "|---|---|---|---|",
    ]
    for row in table["methods"]:
        uses = f"`{row['uses']}`" if row["uses"] else ""
        rows.append(f"| `{row['method']}` | {row['sender']} | {row['kind']} | {uses} |")
    return "\n".join(rows)


# The examples made of a sample's files: the sample's folder, its files in
# the order shown, and what is said above them.
EXAMPLES = [
    (
        "swift",
        "An example in Swift",
        "samples/hello-swift",
        [("vitruvian-tool.json", "json"), ("main.swift", "swift")],
        "A tool written with the Swift kit: it says hello, and counts with a "
        "preference the person can change in Settings.",
        "`vitruvian-tool init <folder> --template swift` starts a new tool from "
        "a copy of this one, as a Swift package that depends on the published "
        "SDK. Its `build.sh` builds the program into `tool/bin/tool`, and "
        "`tool/` is the folder you add to Vitruvian.",
    ),
    (
        "python",
        "An example in Python",
        "samples/hello-python",
        [("vitruvian-tool.json", "json"), ("bin/tool.py", "python")],
        "A tool in plain Python with nothing else: it says hello, and copies the time.",
        "`vitruvian-tool init <folder>` starts a new tool from a copy of this "
        "one. The folder runs as it is: add it to Vitruvian.",
    ),
]

# The kit samples' examples are pages of their own: each sample's README.md,
# which guide_test holds to the guide's rules, copied as the guide is.
KIT_EXAMPLES = [
    (
        "typescript",
        "samples/hello-typescript",
        "A tool written with the TypeScript kit: plain JavaScript that Node "
        "runs as it is, which says hello and counts with a preference.",
    ),
    (
        "python-kit",
        "samples/hello-python-kit",
        "A tool written with the Python kit, installed into the tool's own "
        "folder, which says hello and counts with a preference.",
    ),
    (
        "go",
        "samples/hello-go",
        "A tool written with the Go kit: it says hello, and counts with a "
        "preference the person can change in Settings.",
    ),
    (
        "rust",
        "samples/hello-rust",
        "A tool written with the Rust kit: it says hello, and counts with a "
        "preference the person can change in Settings.",
    ),
]


def example(base, language, title, folder, files, description, how):
    parts = [
        how,
        "",
        f"This is [`{folder}`]({MIRROR}/tree/main/{folder}) of the SDK, as it is. "
        "The conformance script runs it in the SDK's tests.",
    ]
    sources = []
    for name, fence in files:
        text = read(os.path.join(base, SDK, folder), name)
        if "```" in text or not text.endswith("\n"):
            raise SystemExit(f"{folder}/{name} cannot be put in a fenced block")
        sources.append(text[:-1])
        parts += ["", f"`{name}`:", "", f"```{fence}", text[:-1], "```"]
    body = "\n".join(parts)
    if fenced(body) != sources:
        raise SystemExit(f"the code in {folder} would not be copied byte for byte")
    front = [
        ("layout", "tools"),
        ("title", json.dumps(title)),
        ("description", json.dumps(description)),
        ("permalink", f"/tools/examples/{language}/"),
        ("source", f"{SDK}/{folder}"),
    ]
    return page(front, body)


def sources():
    """Every file of the SDK a copy is made from, by its path in the SDK."""
    found = ["docs/writing-a-tool.md", "protocol/README.md", "protocol/methods.json"]
    for _language, _title, folder, files, *_ in EXAMPLES:
        found += [f"{folder}/{name}" for name, _fence in files]
    for _language, folder, _description in KIT_EXAMPLES:
        found.append(f"{folder}/README.md")
    return found


def pages(base):
    """Every copy: its path in the site, and its text."""
    guide, _ = from_markdown(
        base,
        "docs/writing-a-tool.md",
        "/tools/guide/",
        "From nothing to a working tool in ten minutes, then the manifest, "
        "every message, the limits, and how to find out why a tool does not work.",
    )
    protocol, body = from_markdown(
        base,
        "protocol/README.md",
        "/tools/protocol/",
        "How Vitruvian and a tool talk: one JSON message per line over the "
        "tool's standard input and output.",
    )
    protocol = protocol.replace(
        body.rstrip("\n") + "\n{% endraw %}",
        body.rstrip("\n") + "\n\n" + methods_table(base) + "\n{% endraw %}",
    )
    found = {
        "tools/guide.md": guide,
        "tools/protocol.md": protocol,
    }
    for language, *rest in EXAMPLES:
        found[f"tools/examples/{language}.md"] = example(base, language, *rest)
    for language, folder, description in KIT_EXAMPLES:
        found[f"tools/examples/{language}.md"], _ = from_markdown(
            base, f"{folder}/README.md", f"/tools/examples/{language}/", description
        )
    return found


# The other parts of the section. Each is a module with `outputs(root)`: every
# file it makes, by its path from the repository's root, and the bytes it must
# hold. A part is added here, and its sources and outputs to the data of
# in_sync_test in BUILD.
PARTS = [catalogue, registry]


def wanted(base):
    """Every file the section is made of, by its path from the repository's
    root, and the bytes it must hold: the copies, then each part's files."""
    files = {
        f"{SITE}/{path}": text.encode("utf-8") for path, text in pages(base).items()
    }
    for part in PARTS:
        files.update(part.outputs(Path(base)))
    return files


def stale(base):
    """The paths whose committed bytes are not what would be written."""
    return sorted(
        path
        for path, data in wanted(base).items()
        if not os.path.isfile(os.path.join(base, path))
        or Path(base, path).read_bytes() != data
    )


def main(arguments):
    base = root()
    if "--check" in arguments:
        behind = stale(base)
        for path in behind:
            print(f"{path} is not what sync.py writes", file=sys.stderr)
        print(
            "site tools: "
            + (
                "OUT OF SYNC, run bazel run //tools/sync-site-tools:sync"
                if behind
                else "in sync"
            )
        )
        return 1 if behind else 0
    for path, data in sorted(wanted(base).items()):
        target = os.path.join(base, path)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        with open(target, "wb") as handle:
            handle.write(data)
        print(f"wrote {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
