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

"""The Rust port of the catalog's tools, side by side with their scripts.

Every case runs the Python script and the Rust binary on identical copies
of the same inputs and compares what each did: the exit status, stdout,
stderr, and every file it wrote. Where Python dies with a traceback, the
port prints one too; only its last line (the exception) is compared.
"""

import base64
import hashlib
import http.server
import io
import json
import os
import shutil
import socket
import struct
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import urllib.request
import zipfile
from pathlib import Path

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
RUST = {
    name: os.environ[var]
    for name, var in (
        ("sign", "SIGN_RS"),
        ("check_downloads", "CHECK_DOWNLOADS_RS"),
        ("rehearse", "REHEARSE_RS"),
        ("bump", "BUMP_RS"),
    )
}
SCRIPT = {name: HERE / f"{name}.py" for name in RUST}
ENV = dict(os.environ, COLUMNS="80", LINES="24", PYTHONPATH=os.pathsep.join(sys.path))
ENV.pop("GITHUB_ACTIONS", None)
ENV.pop("BUILD_WORKSPACE_DIRECTORY", None)


def rust_path(name):
    path = Path(RUST[name])
    return str(path if path.is_absolute() else Path.cwd() / path)


def last_line(text):
    lines = text.rstrip("\n").split("\n")
    return lines[-1] if lines else ""


def shape(done):
    """What a run did, a traceback cut to the exception it names."""
    err = done.stderr
    if "Traceback (most recent call last):" in err:
        before = err.split("Traceback (most recent call last):")[0]
        err = before + "<traceback> " + last_line(err)
    return done.returncode, done.stdout, err


def run(name, args, cwd=None, env=None, stdin=None, side="both"):
    """Runs `name` as Python and as Rust: their two results."""
    env = dict(ENV, **(env or {}))
    out = {}
    for which, cmd in (
        ("py", [sys.executable, "-u", str(SCRIPT[name])]),
        ("rs", [rust_path(name)]),
    ):
        out[which] = subprocess.run(
            cmd + list(args),
            cwd=cwd,
            env=env,
            input=stdin,
            capture_output=True,
            text=True,
            timeout=60,
        )
    return out["py"], out["rs"]


def snapshot(folder):
    """Every file under `folder`, by its path from there, with its bytes."""
    folder = Path(folder)
    return {
        p.relative_to(folder).as_posix(): p.read_bytes()
        for p in sorted(folder.rglob("*"))
        if p.is_file()
    }


def new_key():
    raw = Ed25519PrivateKey.generate().private_bytes(
        serialization.Encoding.Raw,
        serialization.PrivateFormat.Raw,
        serialization.NoEncryption(),
    )
    public = (
        Ed25519PrivateKey.from_private_bytes(raw)
        .public_key()
        .public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
    )
    return base64.b64encode(raw).decode(), base64.b64encode(public).decode()


class Case(unittest.TestCase):
    maxDiff = None

    def tmp(self):
        d = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, d, True)
        return d

    def same(self, py, rs, what):
        self.assertEqual(shape(py), shape(rs), what)

    def twin(self, make, name, args_of, env_of=None, stdin=None, what=""):
        """Builds the same inputs twice with `make(folder)`, runs Python on
        one copy and Rust on the other, and compares runs and files."""
        results = {}
        for which, cmd in (
            ("py", [sys.executable, "-u", str(SCRIPT[name])]),
            ("rs", [rust_path(name)]),
        ):
            folder = self.tmp()
            make(folder)
            env = dict(ENV, **(env_of(folder) if env_of else {}))
            done = subprocess.run(
                cmd + [a.replace("{dir}", str(folder)) for a in args_of],
                cwd=folder,
                env=env,
                input=stdin,
                capture_output=True,
                text=True,
                timeout=60,
            )
            text = lambda s: s.replace(str(folder), "{dir}")
            done.stdout, done.stderr = text(done.stdout), text(done.stderr)
            results[which] = (shape(done), snapshot(folder))
        self.assertEqual(results["py"][0], results["rs"][0], what)
        self.assertEqual(
            sorted(results["py"][1]), sorted(results["rs"][1]), f"{what}: files"
        )
        for path in results["py"][1]:
            self.assertEqual(
                results["py"][1][path].decode("utf-8", "replace"),
                results["rs"][1][path].decode("utf-8", "replace"),
                f"{what}: {path}",
            )
        return results["py"][0]


# --- sign ---------------------------------------------------------------------


class SignParity(Case):
    def make(self, public, catalog=b'{"version": 1}\n'):
        def make(folder):
            (folder / "public-key.txt").write_text(public + "\n")
            (folder / "tools.json").write_bytes(catalog)

        return make

    def sign(
        self, private, public, args=None, what="", catalog=b'{"a": 1}\n', env=None
    ):
        args = args or [
            "--catalog",
            "{dir}/tools.json",
            "--public-key",
            "{dir}/public-key.txt",
            "--out",
            "{dir}/out",
        ]
        return self.twin(
            self.make(public, catalog),
            "sign",
            args,
            env_of=lambda f: dict({"CATALOG_SIGNING_KEY": private}, **(env or {})),
            what=what,
        )

    def test_a_good_key_signs_byte_for_byte(self):
        for i in range(12):
            private, public = new_key()
            data = os.urandom(i * 37) + "é tools\n".encode()
            rc, out, err = self.sign(private, public, catalog=data, what=f"key {i}")
            self.assertEqual(rc, 0, err)

    def test_refusals(self):
        private, public = new_key()
        other, _ = new_key()
        cases = {
            "empty": "",
            "not base64": "!!!!",
            "short": base64.b64encode(b"x" * 31).decode(),
            "long": base64.b64encode(b"x" * 33).decode(),
            "padding": "AAAA=",
            "excess padding": base64.b64encode(b"x" * 32).decode() + "==",
            "non-ascii": "é" * 44,
            "another key": other,
            "spaced": "  " + private + "\n",
        }
        for what, key in cases.items():
            with self.subTest(what):
                self.sign(key, public, what=what)

    def test_the_command_line(self):
        private, public = new_key()
        for args in (
            [],
            ["--help"],
            ["-h"],
            ["--out"],
            [
                "--ou",
                "{dir}/o",
                "--catalog",
                "{dir}/missing.json",
                "--public-key",
                "{dir}/public-key.txt",
            ],
            ["--out", "{dir}/o", "--bogus"],
            ["--out", "{dir}/o", "--public-key", "{dir}/nope.txt"],
            [
                "--out",
                "{dir}/o",
                "--key-env",
                "OTHER_KEY",
                "--catalog",
                "{dir}/tools.json",
                "--public-key",
                "{dir}/public-key.txt",
            ],
            [
                "--out=./rel/../rel2/",
                "--catalog={dir}/tools.json",
                "--public-key={dir}/public-key.txt",
            ],
        ):
            with self.subTest(args=args):
                self.sign(
                    private,
                    public,
                    args=args,
                    what=str(args),
                    env={"OTHER_KEY": private},
                )

    def test_a_relative_out_is_under_the_workspace(self):
        private, public = new_key()
        args = [
            "--catalog",
            "{dir}/tools.json",
            "--public-key",
            "{dir}/public-key.txt",
            "--out",
            "site/catalog",
        ]
        self.twin(
            self.make(public),
            "sign",
            args,
            env_of=lambda f: {
                "CATALOG_SIGNING_KEY": private,
                "BUILD_WORKSPACE_DIRECTORY": str(f / "ws"),
            },
            what="workspace",
        )

    def test_the_real_public_key_and_its_default_files(self):
        """With no flags each reads its own tools.json and public-key.txt; a
        key that is not the catalog's is refused by both."""
        private, _ = new_key()
        py, rs = run(
            "sign",
            ["--out", "/nonexistent/never"],
            env={"CATALOG_SIGNING_KEY": private},
        )
        self.same(py, rs, "defaults")
        self.assertEqual(py.returncode, 2)


# --- check-downloads ----------------------------------------------------------

MANIFEST = {
    "id": "dev.vitruvian.reference",
    "name": {"en": "Reference tool"},
    "description": {"en": "Says hello."},
    "version": "0.1.0",
    "protocol": "1",
    "publisher": "VitruvianSoftware",
    "uses": ["notify"],
    "contributes": {"commands": [{"id": "hello", "title": {"en": "Say hello"}}]},
    "runtime": {"kind": "external", "exec": "bin/tool"},
}


def make_zip(files, compression=zipfile.ZIP_STORED):
    """A zip of `files`: name to bytes, or to (bytes, Unix mode[, flags])."""
    out = io.BytesIO()
    with zipfile.ZipFile(out, "w", compression) as archive:
        for name, content in files.items():
            if not isinstance(content, tuple):
                content = (content, 0o100644)
            data, mode = content[:2]
            info = zipfile.ZipInfo(name)
            info.create_system = 3
            info.external_attr = mode << 16
            info.compress_type = compression
            archive.writestr(info, data)
    data = out.getvalue()
    return data


def tool_zip(manifest=MANIFEST, extra=None, compression=zipfile.ZIP_STORED):
    files = {
        "vitruvian-tool.json": json.dumps(manifest).encode(),
        "bin/tool": (b"#!/bin/sh\n", 0o100755),
        "share/": (b"", 0o40755),
        "share/readme.txt": b"hello\n" * 50,
    }
    files.update(extra or {})
    return make_zip(files, compression)


def encrypted(data):
    """The same zip with its first entry flagged encrypted."""
    data = bytearray(data)
    at = data.find(b"PK\x01\x02")
    data[at + 8] |= 1
    return bytes(data)


class Server:
    """Serves files from a dict on 127.0.0.1, with redirects."""

    def __init__(self, files):
        self.files = files
        outer = self

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                if self.path.startswith("/redirect/"):
                    self.send_response(302)
                    self.send_header("Location", self.path[len("/redirect") :])
                    self.end_headers()
                    return
                data = outer.files.get(self.path)
                if data is None:
                    self.send_error(404)
                    return
                self.send_response(200)
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            def log_message(self, *args):
                pass

        self.httpd = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()
        self.base = f"http://127.0.0.1:{self.httpd.server_address[1]}"

    def close(self):
        self.httpd.shutdown()


def entry_for(url, data, **changes):
    entry = {
        "id": "dev.vitruvian.reference",
        "name": {"en": "Reference tool"},
        "publisher": "VitruvianSoftware",
        "summary": {"en": "Says hello."},
        "version": "0.1.0",
        "protocol": "1",
        "minimumAppVersion": "3.43.0",
        "source": "https://github.com/VitruvianSoftware/vitruvian-sdk",
        "download": {
            "url": url,
            "sha256": hashlib.sha256(data).hexdigest(),
            "size": len(data),
        },
        "uses": ["notify"],
        "commands": [{"id": "hello", "title": {"en": "Say hello"}}],
    }
    entry.update(changes)
    return entry


def catalog(*tools, generated="2026-10-13T00:00:00Z"):
    return {"version": 1, "generated": generated, "tools": list(tools)}


VALIDATE = """#!{python}
import os, sys
from pathlib import Path
folder = Path(sys.argv[2])
names = sorted(p.relative_to(folder).as_posix() for p in folder.rglob("*"))
modes = [oct(os.stat(folder / n).st_mode & 0o777) for n in names]
print("validated", names, modes)
print("to stderr", file=sys.stderr)
sys.exit(int(os.environ.get("VALIDATE_STATUS", "0")))
"""


class CheckDownloadsParity(Case):
    def setUp(self):
        self.server = Server({})
        self.addCleanup(self.server.close)

    def check(self, head, base=None, files=None, what="", status="0", args=None):
        self.server.files.update(files or {})

        def make(folder):
            (folder / "head.json").write_text(json.dumps(head))
            if base is not None:
                (folder / "base.json").write_text(json.dumps(base))
            v = folder / "validate"
            v.write_text(VALIDATE.format(python=sys.executable))
            v.chmod(0o755)

        return self.twin(
            make,
            "check_downloads",
            args
            or [
                "--base",
                "{dir}/base.json",
                "--head",
                "{dir}/head.json",
                "--validate",
                "{dir}/validate",
            ],
            env_of=lambda f: {"VALIDATE_STATUS": status},
            what=what,
        )

    def url(self, name):
        return f"{self.server.base}/{name}"

    def test_good_and_unchanged(self):
        data = tool_zip()
        e = entry_for(self.url("good.zip"), data)
        rc, out, _ = self.check(
            catalog(e),
            catalog(generated="2026-10-12T00:00:00Z"),
            {"/good.zip": data},
            "good",
        )
        self.assertEqual(rc, 0, out)
        self.check(catalog(e), catalog(e), {}, "unchanged")
        self.check(catalog(e), None, {}, "no base file")
        rd = entry_for(self.url("redirect/good.zip"), data)
        self.check(catalog(rd), None, {}, "redirect")

    def test_deflated_zips_unpack_the_same(self):
        for level in (zipfile.ZIP_DEFLATED,):
            big = {"big.bin": os.urandom(5000) + b"a" * 70000, "x": b""}
            data = tool_zip(extra=big, compression=level)
            e = entry_for(self.url("deflated.zip"), data)
            self.check(catalog(e), None, {"/deflated.zip": data}, "deflated")

    def test_size_and_checksum(self):
        data = tool_zip()
        self.server.files["/z.zip"] = data
        wrong = entry_for(self.url("z.zip"), data)
        wrong["download"]["sha256"] = "0" * 64
        self.check(catalog(wrong), None, {}, "sha")
        small = entry_for(self.url("z.zip"), data)
        small["download"]["size"] = len(data) - 1
        self.check(catalog(small), None, {}, "smaller")
        big = entry_for(self.url("z.zip"), data)
        big["download"]["size"] = len(data) + 5
        self.check(catalog(big), None, {}, "bigger")
        self.check(catalog(entry_for(self.url("missing.zip"), data)), None, {}, "404")
        self.check(
            catalog(entry_for("gopher://x/y.zip", data)), None, {}, "unknown scheme"
        )
        self.check(catalog(entry_for("not a url", data)), None, {}, "no scheme")

    def test_unsafe_zips_are_never_unpacked(self):
        cases = {
            "../escaped": tool_zip(extra={"../escaped": b"x"}),
            "absolute": tool_zip(extra={"/tmp/escaped": b"x"}),
            "home": tool_zip(extra={"~/x": b"x"}),
            "link": tool_zip(extra={"bin/link": (b"/etc", 0o120777)}),
            "backslash": tool_zip(extra={"bin\\tool.exe": b"x"}),
            "dot": tool_zip(extra={"./a": b"x"}),
            "empty part": tool_zip(extra={"a//b": b"x"}),
            "nested manifest": make_zip(
                {"tool/vitruvian-tool.json": json.dumps(MANIFEST).encode()}
            ),
            "encrypted": encrypted(tool_zip()),
            "not a zip": b"this is not a zip at all",
            "empty": b"",
        }
        for what, data in cases.items():
            with self.subTest(what):
                e = entry_for(
                    self.url(f"{what}.zip".replace(" ", "-").replace("/", "_")), data
                )
                self.server.files[e["download"]["url"][len(self.server.base) :]] = data
                self.check(catalog(e), None, {}, what)

    def test_the_manifest_and_the_verdict(self):
        for what, manifest, changes in (
            ("version", dict(MANIFEST, version="0.2.0"), {}),
            ("uses", dict(MANIFEST, uses=["notify", "keystrokes"]), {}),
            ("panels", MANIFEST, {"panels": ["island"]}),
            ("name", dict(MANIFEST, name={"en": "Ünïcode"}), {}),
            (
                "commands",
                dict(
                    MANIFEST,
                    contributes={"commands": [{"id": "x", "title": {"en": "X"}}]},
                ),
                {},
            ),
        ):
            with self.subTest(what):
                data = tool_zip(manifest)
                e = entry_for(self.url(f"m-{what}.zip"), data, **changes)
                self.check(catalog(e), None, {f"/m-{what}.zip": data}, what)
        data = tool_zip()
        e = entry_for(self.url("refused.zip"), data)
        self.check(
            catalog(e), None, {"/refused.zip": data}, "validate refuses", status="3"
        )

    def test_generated_and_removals(self):
        data = tool_zip()
        e = entry_for(self.url("g.zip"), data)
        self.server.files["/g.zip"] = data
        base = catalog(
            dict(e, id="dev.vitruvian.gone"), generated="2026-10-12T00:00:00Z"
        )
        self.check(catalog(e, generated="2026-10-12T00:00:00Z"), base, {}, "not later")
        self.check(
            catalog(generated="2026-10-11T00:00:00Z"), base, {}, "removed, earlier"
        )
        self.check(
            catalog(generated="2026-10-13t00:00:00z"), base, {}, "lower-case time"
        )
        self.check(catalog(e, generated="nonsense"), base, {}, "no time")
        two = [
            entry_for(self.url("g.zip"), data, id=f"dev.vitruvian.t{i}")
            for i in range(3)
        ]
        self.check(catalog(*two), None, {}, "three entries")

    def test_the_command_line(self):
        for args in (
            [],
            ["--help"],
            ["--base", "x"],
            ["--head", "{dir}/missing.json", "--base", "b", "--validate", "v"],
        ):
            with self.subTest(args=args):
                self.check(catalog(), None, {}, str(args), args=args)


# --- rehearse -----------------------------------------------------------------


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def get(url, etag=None):
    request = urllib.request.Request(
        url, headers={"If-None-Match": etag} if etag else {}
    )
    try:
        with urllib.request.urlopen(request, timeout=10) as answer:
            return answer.status, dict(answer.headers), answer.read()
    except urllib.error.HTTPError as error:
        return error.code, dict(error.headers), error.read()


class Rehearsal:
    """A rehearse server, Python's or the port's, in a workspace of its own."""

    def __init__(self, cmd, workspace):
        self.port = free_port()
        self.base = f"http://127.0.0.1:{self.port}"
        self.proc = subprocess.Popen(
            cmd + ["--port", str(self.port)],
            env=dict(ENV, BUILD_WORKSPACE_DIRECTORY=str(workspace)),
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        self.banner = self.until("Now serving: install")

    def until(self, last):
        lines = []
        while True:
            line = self.proc.stdout.readline()
            if not line:
                raise AssertionError(
                    "rehearse ended: " + "".join(lines) + self.proc.stderr.read()
                )
            lines.append(line)
            if line.rstrip("\n") == last:
                return lines

    def say(self, text, until):
        self.proc.stdin.write(text + "\n")
        self.proc.stdin.flush()
        return self.until(until)

    def key(self):
        for line in self.banner:
            if "VITRUVIAN_CATALOGUE_KEY=" in line:
                return line.split("VITRUVIAN_CATALOGUE_KEY=")[1].split()[0]

    def close(self):
        self.proc.stdin.close()
        out = self.proc.stdout.read()
        self.proc.wait(timeout=10)
        err = self.proc.stderr.read()
        self.proc.stdout.close()
        self.proc.stderr.close()
        return self.proc.returncode, out, err


REFERENCE_MANIFEST = {
    "id": "dev.vitruvian.reference",
    "name": {"en": "Reference tool", "fr": "Outil de référence"},
    "description": {"en": "Says hello. ✓"},
    "version": "9.9.9",
    "protocol": "2",
    "publisher": "VitruvianSoftware",
    "uses": ["notify"],
    "contributes": {
        "commands": [
            {"id": "hello", "title": {"en": "Say hello"}, "surfaces": ["commandBar"]}
        ],
        "panels": [{"id": "p", "title": {"en": "P"}, "placement": "island"}],
    },
    "runtime": {"kind": "external", "exec": "bin/tool"},
}


def reference_workspace(folder):
    tool = folder / "packages/vitruvian-sdk/conformance/reference-tool"
    (tool / "bin").mkdir(parents=True)
    (tool / "__pycache__").mkdir()
    (tool / "a-b").mkdir()
    (tool / "vitruvian-tool.json").write_text(json.dumps(REFERENCE_MANIFEST))
    (tool / "bin/tool").write_bytes(b"#!/bin/sh\necho hi\n")
    (tool / "bin/tool").chmod(0o755)
    (tool / "__pycache__/x.pyc").write_bytes(b"\0")
    (tool / "a-b/c").write_text("dash")
    (tool / "a").write_text("plain")
    (tool / ".hidden").write_text("dot")
    (tool / "ünï.txt").write_text("unicode name")


SCENARIO_NAMES = [
    "install",
    "update",
    "not-ours",
    "mismatch",
    "not-the-tool",
    "slip",
    "unreachable",
    "rollback",
]


class RehearseParity(Case):
    PATHS = [
        "/tools.json",
        "/tools.json.sig",
        "/downloads/reference-0.1.0.zip",
        "/downloads/reference-0.2.0.zip",
        "/downloads/reference-0.2.0-slip.zip",
        "/downloads/missing.zip",
        "/nothing",
        "//tools.json",
    ]

    def test_serves_what_the_script_serves(self):
        import signing

        ws = self.tmp()
        reference_workspace(ws)
        servers = {
            "py": Rehearsal([sys.executable, "-u", str(SCRIPT["rehearse"])], ws),
            "rs": Rehearsal([rust_path("rehearse")], ws),
        }

        def norm(s, text):
            return text.replace(str(s.port), "PORT").replace(s.key(), "KEY")

        banners = {k: [norm(s, l) for l in s.banner] for k, s in servers.items()}
        self.assertEqual(banners["py"], banners["rs"])

        signer = {"list": "install"}

        def served(scenario):
            seen = {}
            for k, s in servers.items():
                pages = {}
                for path in self.PATHS:
                    code, headers, body = get(s.base + path)
                    if path == "/tools.json.sig" and code == 200:
                        tools = get(s.base + "/tools.json")[2]
                        good = signing.verify(tools, body, s.key())
                        # not-ours is signed with a key made for that list.
                        self.assertEqual(
                            good,
                            signer["list"] != "not-ours",
                            f"{k} {scenario}: signature",
                        )
                        body = b"<signature verifies: %s>" % str(good).encode()
                    if path in ("/tools.json", "//tools.json") and code == 200:
                        listed = json.loads(body)
                        listed["generated"] = "WHEN"
                        body = norm(s, json.dumps(listed, indent=2)).encode()
                    pages[path] = (
                        code,
                        headers.get("ETag") and "etag",
                        headers.get("Content-Type"),
                        body,
                    )
                    if code == 200:
                        again = get(s.base + path, headers["ETag"])
                        self.assertEqual(again[0], 304, f"{k} {path}: If-None-Match")
                seen[k] = pages
            self.assertEqual(seen["py"], seen["rs"], scenario)
            return seen

        first = served("install")
        for scenario in [
            "update",
            "not-ours",
            "nonsense",
            "",
            "mismatch",
            "not-the-tool",
            "slip",
            "unreachable",
            "rollback",
            "  install  ",
            "rollback",
        ]:
            outs = {}
            for k, s in servers.items():
                s.proc.stdin.write(scenario + "\n")
                s.proc.stdin.flush()
                if scenario.strip() in dict.fromkeys(
                    [
                        "update",
                        "not-ours",
                        "mismatch",
                        "not-the-tool",
                        "slip",
                        "unreachable",
                        "rollback",
                        "install",
                    ]
                ):
                    outs[k] = s.until(f"Now serving: {scenario.strip()}")
                elif scenario.strip():
                    outs[k] = [s.proc.stdout.readline()]
                else:
                    outs[k] = []
            self.assertEqual(outs["py"], outs["rs"], scenario)
            name = scenario.strip()
            if name == "rollback":
                signer["list"] = "install"
            elif name in SCENARIO_NAMES:
                signer["list"] = name
            served(scenario)
        # rollback serves the first list again, byte for byte.
        for s in servers.values():
            listed = json.loads(get(s.base + "/tools.json")[2])
            self.assertEqual(listed["tools"][0]["version"], "0.1.0")
        ends = {k: s.close() for k, s in servers.items()}
        self.assertEqual(ends["py"][:2], ends["rs"][:2])
        logs = {
            k: sorted(
                set(
                    l.split('"')[0] + (l.split('"')[2] if l.count('"') >= 2 else "")
                    for l in e[2].splitlines()
                )
            )
            for k, e in ends.items()
        }
        self.assertEqual(logs["py"], logs["rs"], "what each logged")
        self.assertTrue(first)

    def test_the_command_line(self):
        for args in (["--help"], ["--port", "x"], ["--port"], ["--bogus"]):
            with self.subTest(args=args):
                py, rs = run("rehearse", args)
                self.same(py, rs, str(args))
        empty = self.tmp()
        py, rs = run(
            "rehearse",
            ["--port", str(free_port())],
            env={"BUILD_WORKSPACE_DIRECTORY": str(empty)},
        )
        self.same(py, rs, "no reference tool")


# --- bump -----------------------------------------------------------------------

FROZEN = HERE / "testdata"
HS = "dev.vitruvian.homespeaker"
GH = "dev.vitruvian.github"
BOT = "github-actions[bot]"
ARM64, X86_64 = 0x0100000C, 0x01000007
NOW = "2030-01-02T03:04:05Z"


def thin(cputype, minos=(14, 0, 0), command=0x32, platform=1):
    raw = (minos[0] << 16) | (minos[1] << 8) | minos[2] if minos else 0
    if minos is None:
        cmd = struct.pack("<II", 0x19, 8)
    elif command == 0x32:
        cmd = struct.pack("<IIIIII", 0x32, 24, platform, raw, raw, 0)
    else:
        cmd = struct.pack("<IIII", 0x24, 16, raw, raw)
    header = struct.pack("<IiiIIIII", 0xFEEDFACF, cputype, 0, 2, 1, len(cmd), 0, 0)
    return header + cmd + b"\0" * 64


def fat(*slices, magic=0xCAFEBABE):
    offset, arches, body = 4096, b"", b""
    for cputype, data in slices:
        if magic == 0xCAFEBABE:
            arches += struct.pack(
                ">iiIII", cputype, 0, offset + len(body), len(data), 12
            )
        else:
            arches += struct.pack(
                ">iiQQII", cputype, 0, offset + len(body), len(data), 12, 0
            )
        body += data
    head = struct.pack(">II", magic, len(slices)) + arches
    return head + b"\0" * (offset - len(head)) + body


UNIVERSAL = fat((X86_64, thin(X86_64)), (ARM64, thin(ARM64)))


def frozen_entry(tool_id):
    tools = json.loads((FROZEN / "tools.json").read_text())["tools"]
    return next(t for t in tools if t["id"] == tool_id)


def manifest_for(tool_id, version, **changes):
    entry = frozen_entry(tool_id)
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


def zip_of(
    manifest,
    extra=None,
    program=UNIVERSAL,
    compression=zipfile.ZIP_STORED,
    raw_manifest=None,
):
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", compression) as archive:
        if raw_manifest is not None:
            archive.writestr("vitruvian-tool.json", raw_manifest)
        elif manifest is not None:
            archive.writestr("vitruvian-tool.json", json.dumps(manifest))
        archive.writestr("bin/tool", program)
        for name, data in (extra or {}).items():
            archive.writestr(name, data)
    return buffer.getvalue()


def repo(folder, info=None, tools=None, sources=None):
    root = folder / "repo"
    (root / "catalog").mkdir(parents=True)
    for name in ("catalog.schema.json", "public-key.txt"):
        shutil.copy(HERE / name, root / "catalog" / name)
    (root / "catalog/tools.json").write_bytes(
        tools or (FROZEN / "tools.json").read_bytes()
    )
    (root / "catalog/sources.json").write_bytes(
        sources or (FROZEN / "sources.json").read_bytes()
    )
    plist = root / "apps/desktop/vitruvian/Resources/Info.plist"
    plist.parent.mkdir(parents=True)
    plist.write_bytes(info or (FROZEN / "Info.plist").read_bytes())
    site = root / "apps/web/vitruviansoftware-dev/_data/tools.yml"
    site.parent.mkdir(parents=True)
    site.write_text("old\n")


def release(
    folder,
    name,
    data,
    sidecar=True,
    digest=None,
    size=None,
    sidecar_text=None,
    uploader=BOT,
    sidecar_uploader=BOT,
    meta=None,
    keep_file=True,
):
    rel = folder / "release"
    rel.mkdir(exist_ok=True)
    sha = hashlib.sha256(data).hexdigest()
    assets = [
        {
            "id": 1,
            "name": name,
            "size": len(data) if size is None else size,
            "digest": "sha256:" + sha if digest is None else digest,
            "uploader": {"login": uploader} if uploader is not None else None,
        }
    ]
    if keep_file:
        (rel / name).write_bytes(data)
    if sidecar:
        text = sidecar_text if sidecar_text is not None else f"{sha}  {name}\n"
        (rel / (name + ".sha256")).write_bytes(
            text.encode() if isinstance(text, str) else text
        )
        assets.append(
            {
                "id": 2,
                "name": name + ".sha256",
                "size": len(text),
                "uploader": {"login": sidecar_uploader},
            }
        )
    body = {"draft": False, "assets": assets, "html_url": "https://example.test/r"}
    body.update(meta or {})
    (rel / "release.json").write_text(json.dumps(body))


BUMP_ARGS = [
    "--release-dir",
    "{dir}/release",
    "--root",
    "{dir}/repo",
    "--now",
    NOW,
    "--result-out",
    "{dir}/result.json",
]


class BumpParity(Case):
    def bump(
        self,
        tool_id,
        tag,
        make_release,
        what,
        info=None,
        tools=None,
        sources=None,
        env=None,
        args=None,
    ):
        def make(folder):
            repo(folder, info, tools, sources)
            if make_release:
                make_release(folder)

        return self.twin(
            make,
            "bump",
            (args or ["--id", tool_id, "--tag", tag]) + BUMP_ARGS,
            env_of=(lambda f: env) if env else None,
            what=what,
        )

    def hs(self, version="1.20.0", manifest=None, **kw):
        name = f"HomeSpeaker-{version}-tool.zip"
        data = kw.pop("data", None) or zip_of(manifest or manifest_for(HS, version))
        return lambda folder: release(folder, name, data, **kw)

    def test_a_bump_and_the_pull_request_it_asks_for(self):
        rc, out, err = self.bump(HS, "home-speaker-v1.20.0", self.hs(), "plain bump")
        self.assertEqual(rc, 0, err)
        self.bump(
            HS,
            "home-speaker-v1.20.0",
            self.hs(),
            "on GitHub Actions",
            env={"GITHUB_ACTIONS": "true"},
        )
        self.bump(
            HS,
            "home-speaker-v1.20.0",
            self.hs(
                data=zip_of(
                    manifest_for(HS, "1.20.0"), compression=zipfile.ZIP_DEFLATED
                )
            ),
            "deflated",
        )
        self.bump(
            GH,
            "v1.4.0",
            lambda f: release(
                f, "github-tool-1.4.0.zip", zip_of(manifest_for(GH, "1.4.0"))
            ),
            "github",
        )

    def test_what_a_person_must_read(self):
        cases = {
            "new uses": dict(uses=["notify", "clipboard.read", "open", "keystrokes"]),
            "fewer uses": dict(uses=["notify"]),
            "reordered uses": dict(uses=["open", "notify", "clipboard.read"]),
            "protocol 2": dict(protocol="2"),
            "publisher": dict(publisher="Someone Else"),
            "name": dict(name={"en": "HomeSpeaker Pro", "fr": "HomeSpeaker"}),
            "summary": dict(description={"en": "New words."}),
            "status": dict(
                contributes={"commands": [], "status": {"activity": "Playing"}}
            ),
            "options": dict(preferences=[{"id": "x", "options": ["a"]}]),
            "panels": dict(
                contributes={"commands": [], "panels": [{"placement": "window"}]}
            ),
        }
        for what, changes in cases.items():
            with self.subTest(what):
                self.bump(
                    HS,
                    "home-speaker-v1.20.0",
                    self.hs(manifest=manifest_for(HS, "1.20.0", **changes)),
                    what,
                )

    def test_refusals_write_nothing(self):
        m = manifest_for(HS, "1.20.0")
        name = "HomeSpeaker-1.20.0-tool.zip"
        good = zip_of(m)
        cases = {
            "no sidecar": self.hs(sidecar=False),
            "uploader": self.hs(uploader="mallory"),
            "no uploader": self.hs(uploader=None),
            "sidecar uploader": self.hs(sidecar_uploader="mallory"),
            "no digest": self.hs(digest=""),
            "md5 digest": self.hs(digest="md5:abc"),
            "size": self.hs(size=5),
            "sha": self.hs(digest="sha256:" + "0" * 64),
            "sidecar format": self.hs(sidecar_text="nonsense\n"),
            "sidecar name": self.hs(
                sidecar_text=f"{hashlib.sha256(good).hexdigest()} *dir/other.zip\n"
            ),
            "sidecar star dir": self.hs(
                sidecar_text=f"{hashlib.sha256(good).hexdigest()} *dir/{name}  \r\n"
            ),
            "sidecar sha": self.hs(sidecar_text=f"{'1' * 64}  {name}\n"),
            "sidecar bytes": self.hs(sidecar_text=b"\xff\xfe" + b"x" * 64),
            "slip": self.hs(data=zip_of(m, {"../x": b"x"})),
            "no manifest": self.hs(data=zip_of(None)),
            "bad manifest": self.hs(data=zip_of(None, raw_manifest="{not json")),
            "bad manifest bytes": self.hs(data=zip_of(None, raw_manifest=b"\xff\x00")),
            "manifest list": self.hs(data=zip_of(None, raw_manifest="[1]")),
            "id": self.hs(manifest=manifest_for(HS, "1.20.0", id="dev.other")),
            "version": self.hs(manifest=manifest_for(HS, "1.21.0")),
            "too new": self.hs(
                data=zip_of(
                    m,
                    program=fat(
                        (X86_64, thin(X86_64, (15, 4, 1))), (ARM64, thin(ARM64))
                    ),
                )
            ),
            "version min": self.hs(
                data=zip_of(
                    m,
                    program=fat(
                        (X86_64, thin(X86_64, (13, 0, 0), 0x24)),
                        (ARM64, thin(ARM64, (14, 1, 0), 0x24)),
                    ),
                )
            ),
            "no oldest": self.hs(
                data=zip_of(
                    m, program=fat((X86_64, thin(X86_64, None)), (ARM64, thin(ARM64)))
                )
            ),
            "ios platform": self.hs(
                data=zip_of(
                    m,
                    program=fat(
                        (X86_64, thin(X86_64, platform=2)), (ARM64, thin(ARM64))
                    ),
                )
            ),
            "thin": self.hs(data=zip_of(m, program=thin(ARM64))),
            "fat64": self.hs(
                data=zip_of(
                    m,
                    program=fat((X86_64, thin(X86_64)), (7, thin(7)), magic=0xCAFEBABF),
                )
            ),
            "not a program": self.hs(data=zip_of(m, program=b"#!/bin/sh\n")),
            "java class": self.hs(
                data=zip_of(m, program=b"\xca\xfe\xba\xbe\x00\x00\x00\x34" + b"\0" * 40)
            ),
            "bad slice": self.hs(
                data=zip_of(
                    m,
                    program=struct.pack(">II", 0xCAFEBABE, 1)
                    + struct.pack(">iiIII", ARM64, 0, 99999, 10, 12),
                )
            ),
            "short arch list": self.hs(
                data=zip_of(m, program=struct.pack(">II", 0xCAFEBABE, 3) + b"\0" * 10)
            ),
            "bad load command": self.hs(
                data=zip_of(
                    m,
                    program=struct.pack(
                        "<IiiIIIII", 0xFEEDFACF, ARM64, 0, 2, 3, 0, 0, 0
                    )
                    + struct.pack("<II", 0x32, 4)
                    + b"\0" * 20,
                )
            ),
            "extra program": self.hs(
                data=zip_of(m, {"lib/x.dylib": thin(ARM64, (16, 0, 0))})
            ),
            "unavailable": self.hs(keep_file=False),
        }
        for what, make_release in cases.items():
            with self.subTest(what):
                self.bump(HS, "home-speaker-v1.20.0", make_release, what)

    def test_not_ready_not_listed_and_the_rest(self):
        self.bump(HS, "home-speaker-v1.20.0", None, "no release")
        self.bump(HS, "home-speaker-v1.20.0", self.hs(meta={"draft": True}), "draft")
        self.bump(
            HS, "home-speaker-v1.20.0", self.hs(meta={"prerelease": True}), "prerelease"
        )
        self.bump(
            HS,
            "home-speaker-v1.20.0",
            lambda f: release(f, "other.zip", b"x"),
            "no zip yet",
        )
        self.bump("dev.vitruvian.remote", "android-remote-v1.0.0", None, "not listed")
        self.bump("dev.nobody", "x-v1.0.0", None, "no row")
        self.bump(HS, "v1.20.0", None, "not its tag")
        self.bump(HS, "home-speaker-v1.20.0-beta.1", None, "prerelease tag")
        self.bump(HS, "home-speaker-v1.0.0", None, "older")
        tools = json.loads((FROZEN / "tools.json").read_text())
        entry = next(t for t in tools["tools"] if t["id"] == HS)
        data = zip_of(manifest_for(HS, "1.19.1"))
        url = f"https://github.com/VitruvianSoftware/vitruvian-core/releases/download/home-speaker-v1.19.1/HomeSpeaker-1.19.1-tool.zip"
        entry["download"] = {
            "url": url,
            "sha256": hashlib.sha256(data).hexdigest(),
            "size": len(data),
        }
        current = json.dumps(tools, indent=2).encode()
        mk = lambda f: release(f, "HomeSpeaker-1.19.1-tool.zip", data)
        self.bump(HS, "home-speaker-v1.19.1", mk, "current", tools=current)
        self.bump(HS, "home-speaker-v1.19.1", mk, "changed after listing")
        later = dict(tools, generated="2031-01-01T00:00:00Z")
        self.bump(
            HS,
            "home-speaker-v1.20.0",
            self.hs(),
            "generated moves on",
            tools=json.dumps(later).encode(),
        )
        bad = (
            (FROZEN / "Info.plist")
            .read_text()
            .replace("<string>14.0</string>", "<string>14.x</string>")
        )
        self.bump(
            HS,
            "home-speaker-v1.20.0",
            self.hs(),
            "bad plist version",
            info=bad.encode(),
        )
        newer = (
            (FROZEN / "Info.plist")
            .read_text()
            .replace("<string>14.0</string>", "<string>15.4.1</string>")
        )
        self.bump(
            HS, "home-speaker-v1.20.0", self.hs(), "newer floor", info=newer.encode()
        )
        self.bump(
            HS,
            "home-speaker-v1.20.0",
            self.hs(),
            "bad --now",
            args=["--id", HS, "--tag", "home-speaker-v1.20.0", "--now", "tomorrow"],
        )
        broken = json.dumps({"sources": [{"id": "x"}]}).encode()
        self.bump(HS, "home-speaker-v1.20.0", self.hs(), "bad sources", sources=broken)
        schema_bad = dict(tools, extra=1)
        self.bump(
            HS,
            "home-speaker-v1.20.0",
            self.hs(),
            "schema",
            tools=json.dumps(schema_bad).encode(),
        )

    def test_the_command_line(self):
        for args in (
            [],
            ["--help"],
            ["bump", "--id"],
            ["plan", "--help"],
            ["arm"],
            ["older", "--pulls"],
            ["--id", "x", "--tag", "y", "extra"],
            ["automerge", "--pr", "x"],
        ):
            with self.subTest(args=args):
                py, rs = run("bump", args)
                self.same(py, rs, str(args))


COMPARE_MINE = {
    "commits": [
        {
            "sha": "a" * 40,
            "commit": {
                "message": "feat: x\n\nCatalog-Bump: dev.vitruvian.homespeaker@1.20.0",
                "author": {"name": "bot"},
            },
        }
    ],
    "files": [{"filename": "catalog/tools.json"}],
}


class WorkflowHelpersParity(Case):
    def json_run(self, command, files, args):
        def make(folder):
            for name, value in files.items():
                (folder / name).write_text(
                    json.dumps(value) if not isinstance(value, str) else value
                )

        return self.twin(make, "bump", [command] + args, what=f"{command} {files}")

    def test_foreign(self):
        person = {
            "sha": "b" * 40,
            "commit": {"message": "fix", "author": {"name": "James"}},
        }
        for compare in (
            COMPARE_MINE,
            {"commits": []},
            {},
            {"commits": COMPARE_MINE["commits"] * 2},
            {"commits": COMPARE_MINE["commits"] + [person]},
            {"commits": [person]},
            {
                "commits": [
                    {
                        "sha": "c" * 40,
                        "commit": {
                            "message": "x\r\nCatalog-Bump: dev.vitruvian.homespeaker@1.20.0 ",
                            "author": {"name": "é"},
                        },
                    }
                ]
            },
            "not json",
            [1],
        ):
            self.json_run(
                "foreign",
                {"c.json": compare},
                ["--compare", "{dir}/c.json", "--id", HS, "--version", "1.20.0"],
            )

    def test_older(self):
        pulls = [
            {"number": 1, "headRefName": f"catalog/bump-{HS}-1.19.0"},
            {"number": 2, "headRefName": f"catalog/bump-{HS}-1.21.0"},
            {"number": 3, "headRefName": "feature/x"},
            {"number": 4, "headRefName": f"catalog/bump-{HS}-1.2.0"},
            {"number": 5, "headRefName": f"catalog/bump-{HS}-junk"},
        ]
        self.json_run(
            "older",
            {"p.json": pulls},
            ["--pulls", "{dir}/p.json", "--id", HS, "--version", "1.20.0"],
        )
        self.json_run(
            "older",
            {"p.json": pulls},
            ["--pulls", "{dir}/p.json", "--id", HS, "--version", "bad"],
        )
        self.json_run(
            "older",
            {"p.json": [{"number": 1}]},
            ["--pulls", "{dir}/p.json", "--id", HS, "--version", "1.0.0"],
        )

    def test_arm(self):
        good = {
            "state": "OPEN",
            "isDraft": False,
            "headRefName": f"catalog/bump-{HS}-1.20.0",
            "headRefOid": "abc",
            "author": {"login": "app/vitruvian-copybara-sync"},
            "labels": [],
            "body": "x\n<!-- catalog-bump: may merge itself -->\n",
            "autoMergeRequest": None,
        }
        armed = dict(good, autoMergeRequest={"enabledAt": "now"})
        many = dict(COMPARE_MINE, files=[{"filename": f"f{i}"} for i in range(25)])
        pulls = {
            "good": good,
            "armed": armed,
            "draft": dict(good, isDraft=True),
            "closed": dict(armed, state="CLOSED"),
            "branch": dict(good, headRefName="feature/x"),
            "author": dict(good, author={"login": "james"}),
            "no author": dict(armed, author=None),
            "held": dict(
                good, labels=[{"name": "needs-human"}, {"name": "do-not-automerge"}]
            ),
            "no mark": dict(good, body="nothing"),
            "no body": dict(armed, body=None),
            "moved": dict(good, headRefOid="def"),
        }
        compares = {
            "mine": COMPARE_MINE,
            "no files": {"commits": COMPARE_MINE["commits"]},
            "outside": dict(
                COMPARE_MINE,
                files=[{"filename": "x/y"}, {"filename": "catalog/tools.json"}, {}],
            ),
            "many": many,
            "foreign": {
                "commits": [
                    {
                        "sha": "d" * 40,
                        "commit": {"message": "x", "author": {"name": "p"}},
                    }
                ],
                "files": [],
            },
        }
        for p_name, pull in pulls.items():
            for c_name, compare in compares.items():
                for check in ("success", "pushed", "failure"):
                    with self.subTest(pull=p_name, compare=c_name, check=check):
                        self.json_run(
                            "arm",
                            {"p.json": pull, "c.json": compare},
                            [
                                "--pull",
                                "{dir}/p.json",
                                "--compare",
                                "{dir}/c.json",
                                "--tested-sha",
                                "abc",
                                "--check",
                                check,
                            ],
                        )


FAKE_GH = """#!{python}
import json, os, sys
args = sys.argv[1:]
with open(os.environ["FAKE_GH_LOG"], "a") as log:
    log.write(json.dumps(args) + "\\n")
answers = json.load(open(os.environ["FAKE_GH_ANSWERS"]))
key = " ".join(args)
for pattern, answer in answers:
    if pattern in key:
        sys.stdout.write(answer.get("stdout", ""))
        sys.stderr.write(answer.get("stderr", ""))
        sys.exit(answer.get("status", 0))
sys.stderr.write("fake gh: nothing for " + key + "\\n")
sys.exit(1)
"""


class GitHubParity(Case):
    """plan and automerge, with a fake `gh` that answers from a table and
    writes down every call: both must ask GitHub the same things."""

    def gh(self, command, args, answers, what):
        def make(folder):
            repo(folder)
            bin_dir = folder / "bin"
            bin_dir.mkdir()
            (bin_dir / "gh").write_text(FAKE_GH.format(python=sys.executable))
            (bin_dir / "gh").chmod(0o755)
            (folder / "answers.json").write_text(json.dumps(answers))

        return self.twin(
            make,
            "bump",
            [command] + args,
            env_of=lambda f: {
                "PATH": f"{f / 'bin'}{os.pathsep}{os.environ.get('PATH', '')}",
                "FAKE_GH_LOG": str(f / "gh.log"),
                "FAKE_GH_ANSWERS": str(f / "answers.json"),
                "GITHUB_REPOSITORY": "VitruvianSoftware/vitruvian-core",
            },
            what=what,
        )

    def release(self, name, draft=False):
        return {
            "stdout": json.dumps(
                {"draft": draft, "prerelease": False, "assets": [{"name": name}]}
            )
        }

    def test_plan(self):
        tags = {
            "stdout": "refs/tags/home-speaker-v1.19.0\nrefs/tags/home-speaker-v1.21.0\nrefs/tags/home-speaker-v1.20.0\nrefs/tags/home-speaker-v2.0.0-beta.1\nrefs/tags/home-speaker-vjunk\n"
        }
        gh_tags = {"stdout": "refs/tags/v1.3.0\nrefs/tags/v1.4.0\n"}
        base = [
            ["matching-refs/tags/home-speaker-v", tags],
            ["matching-refs/tags/v", gh_tags],
            [
                "releases/tags/home-speaker-v1.21.0",
                {"status": 1, "stderr": "gh: Not Found (HTTP 404)\n"},
            ],
            [
                "releases/tags/home-speaker-v1.20.0",
                self.release("HomeSpeaker-1.20.0-tool.zip"),
            ],
            ["releases/tags/v1.4.0", self.release("github-tool-1.4.0.zip")],
            ["issue list", {"stdout": "[]"}],
        ]
        pulls = {
            "none": {"stdout": "[]"},
            "open": {
                "stdout": json.dumps(
                    [
                        {"number": 7, "state": "OPEN", "mergeable": "MERGEABLE"},
                        {"number": 9, "state": "CLOSED", "mergeable": "UNKNOWN"},
                    ]
                )
            },
            "closed": {
                "stdout": json.dumps(
                    [{"number": 9, "state": "CLOSED", "mergeable": "UNKNOWN"}]
                )
            },
            "merged": {
                "stdout": json.dumps(
                    [{"number": 3, "state": "MERGED", "mergeable": "UNKNOWN"}]
                )
            },
            "conflicting": {
                "stdout": json.dumps(
                    [{"number": 8, "state": "OPEN", "mergeable": "CONFLICTING"}]
                )
            },
        }
        compare_mine = {"stdout": json.dumps(COMPARE_MINE)}
        compare_person = {
            "stdout": json.dumps(
                {
                    "commits": [
                        {
                            "sha": "e" * 40,
                            "commit": {"message": "x", "author": {"name": "James"}},
                        }
                    ]
                }
            )
        }
        for p_name, pull in pulls.items():
            for c_name, compare in (("mine", compare_mine), ("person", compare_person)):
                answers = base + [
                    ["pr list", pull],
                    ["/compare/", compare],
                    [
                        "--json comments",
                        {"stdout": json.dumps({"comments": [{"body": "hi"}]})},
                    ],
                    ["pr comment", {"stdout": ""}],
                ]
                with self.subTest(pull=p_name, compare=c_name):
                    self.gh(
                        "plan",
                        ["--root", "{dir}/repo", "--out", "{dir}/plan.json"],
                        answers,
                        f"plan {p_name} {c_name}",
                    )
        refused = (
            [
                [
                    "issue list",
                    {
                        "stdout": json.dumps(
                            [
                                {
                                    "title": "catalog-bump refused dev.vitruvian.homespeaker 1.20.0"
                                }
                            ]
                        )
                    },
                ]
            ]
            + base
            + [["pr list", pulls["none"]]]
        )
        self.gh("plan", ["--root", "{dir}/repo"], refused, "refused issue open")
        draft = (
            [["releases/tags/home-speaker-v1.20.0", self.release("x", draft=True)]]
            + base
            + [["pr list", pulls["none"]]]
        )
        self.gh("plan", ["--root", "{dir}/repo"], draft, "draft and no zip")
        broken = [["matching-refs", {"status": 1, "stderr": "boom\n"}]]
        self.gh("plan", ["--root", "{dir}/repo"], broken, "tags fail")
        bad_release = [
            [
                "releases/tags/home-speaker-v1.21.0",
                {"status": 1, "stderr": "server error\n"},
            ]
        ] + base
        self.gh("plan", ["--root", "{dir}/repo"], bad_release, "release fails")
        self.gh(
            "plan",
            ["--root", "{dir}/repo"],
            [["matching-refs", {"stdout": ""}], ["issue list", {"stdout": "[]"}]],
            "no tags",
        )
        self.gh(
            "plan",
            ["--root", "{dir}/repo"],
            [["matching-refs", {"stdout": ""}]],
            "env",
        )

    def test_automerge(self):
        good = {
            "state": "OPEN",
            "isDraft": False,
            "headRefName": f"catalog/bump-{HS}-1.20.0",
            "headRefOid": "abc",
            "author": {"login": "vitruvian-copybara-sync[bot]"},
            "labels": [],
            "body": "<!-- catalog-bump: may merge itself -->",
            "autoMergeRequest": None,
        }
        person = {
            "commits": [
                {"sha": "f" * 40, "commit": {"message": "x", "author": {"name": "p"}}}
            ],
            "files": [],
        }
        for what, pull, compare, comments in (
            ("arm", good, COMPARE_MINE, []),
            (
                "disarm",
                dict(good, autoMergeRequest={}, state="CLOSED"),
                COMPARE_MINE,
                [],
            ),
            ("hold", dict(good, autoMergeRequest={}), person, []),
            (
                "hold, said before",
                good,
                person,
                [{"body": "<!-- catalog-bump: held for a person --> x"}],
            ),
            ("leave", good, COMPARE_MINE, []),
        ):
            answers = [
                ["--json comments", {"stdout": json.dumps({"comments": comments})}],
                ["pr view", {"stdout": json.dumps(pull)}],
                ["/compare/", {"stdout": json.dumps(compare)}],
                ["pr merge", {"stdout": ""}],
                ["pr edit", {"stdout": ""}],
                ["pr comment", {"stdout": ""}],
            ]
            check = "pushed" if what == "leave" else "success"
            with self.subTest(what):
                self.gh(
                    "automerge",
                    [
                        "--pr",
                        "042",
                        "--tested-sha",
                        "abc",
                        "--check",
                        check,
                        "--base",
                        "main",
                    ],
                    answers,
                    what,
                )
        self.gh(
            "automerge",
            ["--pr", "1", "--tested-sha", "abc", "--check", "success"],
            [["pr view", {"status": 1, "stderr": "nope\n"}]],
            "view fails",
        )
        self.gh(
            "automerge",
            ["--pr", "1", "--tested-sha", "abc", "--check", "success"],
            [
                ["pr view", {"stdout": json.dumps(good)}],
                ["/compare/", {"stdout": json.dumps(COMPARE_MINE)}],
                ["pr merge", {"status": 1}],
            ],
            "arm fails",
        )

    def test_bump_through_gh(self):
        data = zip_of(manifest_for(HS, "1.20.0"))
        sha = hashlib.sha256(data).hexdigest()
        name = "HomeSpeaker-1.20.0-tool.zip"
        meta = {
            "draft": False,
            "assets": [
                {
                    "id": 11,
                    "name": name,
                    "size": len(data),
                    "digest": "sha256:" + sha,
                    "uploader": {"login": BOT},
                },
                {
                    "id": 12,
                    "name": name + ".sha256",
                    "size": 10,
                    "uploader": {"login": BOT},
                },
            ],
        }
        answers = [
            ["releases/tags/home-speaker-v1.20.0", {"stdout": json.dumps(meta)}],
            ["releases/assets/11", {"stdout": data.decode("latin-1")}],
            ["releases/assets/12", {"stdout": f"{sha}  {name}\n"}],
        ]
        # The fake writes text; latin-1 round-trips the zip's bytes only if
        # the fake's stdout encodes them back the same way.
        args = [
            "--id",
            HS,
            "--tag",
            "home-speaker-v1.20.0",
            "--root",
            "{dir}/repo",
            "--now",
            NOW,
            "--result-out",
            "{dir}/r.json",
        ]
        self.gh(
            "bump",
            args,
            answers[:1]
            + [["releases/assets/11", {"status": 1, "stderr": "rate limited\n"}]]
            + answers[2:],
            "asset fails",
        )
        self.gh(
            "bump",
            args,
            [["releases/tags", {"status": 1, "stderr": "HTTP 404: Not Found\n"}]],
            "no release on GitHub",
        )
        self.gh(
            "bump",
            args,
            [["releases/tags", {"status": 1, "stderr": "boom\n"}]],
            "GitHub fails",
        )


if __name__ == "__main__":
    unittest.main()
