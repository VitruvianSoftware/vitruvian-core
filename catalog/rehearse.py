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

"""A rehearsal of the catalog, served on this Mac, for the checks by hand.

    bazel run //catalog:rehearse

It makes a key for this run only, zips the SDK's reference tool at two
versions, signs a list, and serves it on http://127.0.0.1:8737. It prints the
command that opens a by-hand build of the app (made with
--define=vitruvian_sample_tool=true) pointed at it; a release build never
reads those two variables. Type a scenario's name and Return to change what
is served; each list is signed afresh, later than the one before, except
`rollback`, which serves the first list again.

Nothing here touches the real catalog, its key or the network beyond this Mac.
"""

import argparse
import base64
import hashlib
import http.server
import io
import json
import os
import sys
import threading
import zipfile
from datetime import datetime, timedelta, timezone
from pathlib import Path

import signing
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

TOOL_ID = "dev.vitruvian.reference"

SCENARIOS = {
    "install": "version 0.1.0 is listed: Install",
    "update": "version 0.2.0 is listed: Update available",
    "not-ours": "the list is signed with another key",
    "mismatch": "0.2.0 is listed with the checksum of 0.1.0",
    "not-the-tool": "0.3.0 is listed; its zip holds 0.2.0",
    "slip": "0.2.0's zip also holds ../escaped.txt",
    "unreachable": "0.2.0 is listed at an address that answers 404",
    "rollback": "the first list served, signed and older than the last",
}


def new_key():
    """A private key for this run, in base64, as CATALOG_SIGNING_KEY holds one."""
    raw = Ed25519PrivateKey.generate().private_bytes(
        serialization.Encoding.Raw,
        serialization.PrivateFormat.Raw,
        serialization.NoEncryption(),
    )
    return base64.b64encode(raw).decode("ascii")


def tool_zip(folder, version, extra=None):
    """The tool in `folder`, its manifest's version set to `version`, zipped
    the way the catalog asks: the manifest at the top, execute bits kept."""
    out = io.BytesIO()
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(Path(folder).rglob("*")):
            if path.is_dir() or "__pycache__" in path.parts:
                continue
            name = path.relative_to(folder).as_posix()
            data = path.read_bytes()
            if name == "vitruvian-tool.json":
                manifest = json.loads(data)
                manifest["version"] = version
                data = json.dumps(manifest, indent=2).encode()
            info = zipfile.ZipInfo(name)
            info.create_system = 3
            info.external_attr = (
                0o100755 if os.access(path, os.X_OK) else 0o100644
            ) << 16
            archive.writestr(info, data)
        for name, data in (extra or {}).items():
            info = zipfile.ZipInfo(name)
            info.create_system = 3
            info.external_attr = 0o100644 << 16
            archive.writestr(info, data)
    return out.getvalue()


def entry(manifest, version, url, data):
    return {
        "id": manifest["id"],
        "name": manifest["name"],
        "publisher": manifest["publisher"],
        "summary": manifest["description"],
        "version": version,
        "protocol": manifest["protocol"],
        "minimumAppVersion": "0.0.0",
        "source": "https://github.com/VitruvianSoftware/vitruvian-sdk",
        "download": {
            "url": url,
            "sha256": hashlib.sha256(data).hexdigest(),
            "size": len(data),
        },
        "uses": manifest.get("uses", []),
        "commands": [
            {"id": c["id"], "title": c["title"]}
            for c in manifest.get("contributes", {}).get("commands", [])
        ],
        "panels": [
            p["placement"] for p in manifest.get("contributes", {}).get("panels", [])
        ],
    }


def build(folder, base, private, scenario, when):
    """What the server serves for `scenario`, by path: the list, its
    signature and the zips. `base` is the server's address."""
    manifest = json.loads(
        (Path(folder) / "vitruvian-tool.json").read_text(encoding="utf-8")
    )
    zips = {
        "/downloads/reference-0.1.0.zip": tool_zip(folder, "0.1.0"),
        "/downloads/reference-0.2.0.zip": tool_zip(folder, "0.2.0"),
        "/downloads/reference-0.2.0-slip.zip": tool_zip(
            folder, "0.2.0", {"../escaped.txt": b"x"}
        ),
    }
    old, new, slip = zips.values()
    tools = {
        "install": entry(
            manifest, "0.1.0", base + "/downloads/reference-0.1.0.zip", old
        ),
        "update": entry(
            manifest, "0.2.0", base + "/downloads/reference-0.2.0.zip", new
        ),
        "not-ours": entry(
            manifest, "0.2.0", base + "/downloads/reference-0.2.0.zip", new
        ),
        "mismatch": dict(
            entry(manifest, "0.2.0", base + "/downloads/reference-0.2.0.zip", new),
            download={
                "url": base + "/downloads/reference-0.2.0.zip",
                "sha256": hashlib.sha256(old).hexdigest(),
                "size": len(new),
            },
        ),
        "not-the-tool": entry(
            manifest, "0.3.0", base + "/downloads/reference-0.2.0.zip", new
        ),
        "slip": entry(
            manifest, "0.2.0", base + "/downloads/reference-0.2.0-slip.zip", slip
        ),
        "unreachable": entry(manifest, "0.2.0", base + "/downloads/missing.zip", new),
    }
    listed = {
        "version": 1,
        "generated": when.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "tools": [tools[scenario]],
    }
    data = (json.dumps(listed, indent=2) + "\n").encode()
    key = new_key() if scenario == "not-ours" else private
    return dict(
        zips, **{"/tools.json": data, "/tools.json.sig": signing.sign(data, key)}
    )


class Rehearsal:
    def __init__(self, folder, base, private):
        self.folder, self.base, self.private = folder, base, private
        self.when = datetime.now(timezone.utc).replace(microsecond=0)
        self.lock = threading.Lock()
        self.first = None
        self.files = {}
        self.switch("install")

    def switch(self, scenario):
        with self.lock:
            if scenario == "rollback":
                files = dict(self.files, **self.first)
            else:
                self.when += timedelta(seconds=1)
                files = build(self.folder, self.base, self.private, scenario, self.when)
                if self.first is None:
                    self.first = {
                        path: files[path] for path in ("/tools.json", "/tools.json.sig")
                    }
            self.files = files

    def handler(self):
        rehearsal = self

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                with rehearsal.lock:
                    data = rehearsal.files.get(self.path)
                if data is None:
                    self.send_error(404)
                    return
                etag = '"' + hashlib.sha256(data).hexdigest()[:16] + '"'
                if self.headers.get("If-None-Match") == etag:
                    self.send_response(304)
                    self.send_header("ETag", etag)
                    self.end_headers()
                    return
                self.send_response(200)
                self.send_header("ETag", etag)
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            def log_message(self, form, *args):
                sys.stderr.write("served " + (form % args) + "\n")

        return Handler


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--port", type=int, default=8737)
    args = parser.parse_args(argv)
    workspace = Path(os.environ.get("BUILD_WORKSPACE_DIRECTORY", "."))
    folder = workspace / "packages/vitruvian-sdk/conformance/reference-tool"
    base = f"http://127.0.0.1:{args.port}"
    private = new_key()
    rehearsal = Rehearsal(folder, base, private)
    server = http.server.ThreadingHTTPServer(
        ("127.0.0.1", args.port), rehearsal.handler()
    )
    threading.Thread(target=server.serve_forever, daemon=True).start()
    bundle = workspace / "bazel-bin/apps/desktop/vitruvian/Vitruvian.zip"
    print(
        f"Serving a rehearsal catalog at {base}/tools.json, signed with a key for this run only."
    )
    print(
        "Quit Vitruvian, then open a by-hand build (made with --define=vitruvian_sample_tool=true) pointed at it:"
    )
    print(f"  ditto -x -k {bundle} /tmp/vitruvian")
    print(
        f"  open -n --env VITRUVIAN_CATALOGUE_URL={base}/tools.json "
        f"--env VITRUVIAN_CATALOGUE_KEY={signing.public_key_of(private)} /tmp/vitruvian/Vitruvian.app"
    )
    print("Scenarios (type one and press Return; Control-D ends):")
    for name, what in SCENARIOS.items():
        print(f"  {name:13} {what}")
    print("Now serving: install")
    for line in sys.stdin:
        name = line.strip()
        if name in SCENARIOS:
            rehearsal.switch(name)
            print(f"Now serving: {name}")
        elif name:
            print(f"No scenario {name!r}.")
    server.shutdown()
    return 0


if __name__ == "__main__":
    sys.exit(main())
