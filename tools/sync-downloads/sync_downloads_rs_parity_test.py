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
"""sync-downloads-rs, the Rust port, against sync_downloads.py: same exit
code, stdout, stderr, catalog left behind and GitHub calls, on every input.

    bazel test //tools/sync-downloads:sync_downloads_rs_parity_test

Both run as programs under the name sync_downloads.py, with PATH holding
only a fake `which` and a fake `gh`. The fake gh answers `gh api <endpoint>`
from a folder of files (a missing file is a failed call) and logs each call.
The HTTPS fallback cannot reach anything: Python's urllib goes through a
proxy that refuses, and the port's curl is not on PATH. That fallback's
warning names the error in each program's own words, so there only the
words after the URL are masked.

The inputs:
  * every value sync_downloads_test.py passes to parse_semver and
    format_size, recorded by running that suite, then fed in as release
    tags (which tag wins) and asset sizes (what the catalog says);
  * hand-made releases for all eight products, in every mode (write,
    --dry-run, --check, already up to date), with the asset-name fallbacks,
    prereleases, beta tags, the matching-refs and releases-list paths;
  * inputs built to break them: bad JSON from gh, values of the wrong type,
    sizes at the rounding edges, tags full of regex template escapes,
    catalogs with CRLF, without products, over 200 lines (difflib's
    autojunk), missing, a directory, not UTF-8;
  * command lines argparse treats specially, at several terminal widths;
  * a few hundred random releases against random catalogs.

When Python crashes, its traceback names its own files and lines, which
the port cannot have, so there the exception's class is compared.
"""

import json
import os
import random
import shutil
import subprocess
import sys
import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import sync_downloads as sd  # noqa: E402
import sync_downloads_test as sdt  # noqa: E402

CATALOG = os.path.join(HERE, "testdata", "downloads.yml")
TRACEBACK = b"Traceback (most recent call last):"
CORE = "repos/VitruvianSoftware/vitruvian-core"

FAKE_WHICH = """#!/bin/sh
[ "$1" = gh ] && [ -x "$FAKEBIN/gh" ] && { echo "$FAKEBIN/gh"; exit 0; }
exit 1
"""

# `gh api <endpoint>`: the file at $FAKE_GH_DIR/<endpoint> (a trailing slash
# reads __index__), or a failure as gh reports a 404.
FAKE_GH = """#!/bin/sh
printf '%s\\n' "$2" >> "$FAKE_GH_LOG"
p="$FAKE_GH_DIR/$2"
case "$p" in */) p="${p}__index__";; esac
if [ "$1" = api ] && [ -f "$p" ]; then exec /bin/cat "$p"; fi
echo "gh: Not Found (HTTP 404)" >&2
exit 1
"""


def _binary():
    path = os.environ.get("SYNC_DOWNLOADS_RS", "")
    if not path:
        raise unittest.SkipTest(
            "SYNC_DOWNLOADS_RS is not set; run this under bazel test"
        )
    return os.path.abspath(path)


def read_catalog():
    with open(CATALOG, encoding="utf-8") as handle:
        return handle.read()


def asset(name, size, url=None):
    return {
        "name": name,
        "size": size,
        "browser_download_url": url
        if url is not None
        else f"https://example.test/download/{name}",
    }


def release(tag, assets=(), prerelease=False):
    return {"tag_name": tag, "prerelease": prerelease, "assets": list(assets)}


def full_releases(n=7):
    """A new release of every product, with every asset the script reads."""
    v = f"9.{n}.0"
    mb = 1024 * 1024
    return {
        "repos/VitruvianSoftware/nexus-agent/releases/latest": release(
            f"v{v}",
            [
                asset(f"NexusAgent-{v}-universal.dmg", int(8.4 * mb)),
                asset(f"NexusAgent-{v}-arm64.dmg", int(5.1 * mb)),
                asset(f"NexusAgent-{v}-x86_64.dmg", 12 * mb),
                asset(f"NexusAgent-{v}-universal.zip", 900 * 1024),
                asset(f"NexusAgent-{v}-universal.dmg.sha256", 64),
            ],
        ),
        f"{CORE}/git/matching-refs/tags/vitruvian-v": [
            {"ref": "refs/tags/vitruvian-v3.82.0"},
            {"ref": f"refs/tags/vitruvian-v{v}"},
            {"ref": "refs/tags/vitruvian-v99.0.0-beta.1"},
        ],
        f"{CORE}/releases/tags/vitruvian-v{v}": release(
            f"vitruvian-v{v}",
            [
                asset(f"Vitruvian-{v}-universal.dmg", 20 * mb),
                asset(f"Vitruvian-{v}-arm64.dmg", int(14.25 * mb)),
                asset(f"Vitruvian-{v}-x86_64.dmg", int(14.75 * mb)),
                asset(f"Vitruvian-{v}-universal.zip", 3 * mb + 1),
                asset(f"Vitruvian-{v}.dmg.sig", 10),
            ],
        ),
        f"{CORE}/git/matching-refs/tags/home-speaker-v": [
            {"ref": f"refs/tags/home-speaker-v{v}"},
            {"ref": "refs/tags/home-speaker-v1.2.3"},
        ],
        f"{CORE}/releases/tags/home-speaker-v{v}": release(
            f"home-speaker-v{v}",
            [
                asset(f"HomeSpeaker-{v}-universal.dmg", 2 * mb),
                asset(f"HomeSpeaker-{v}-universal.zip", 1536 * 1024),
                asset(f"HomeSpeaker-{v}-macOS.zip", 99),
            ],
        ),
        "repos/VitruvianSoftware/devx/releases/latest": release(f"vv{v}"),
        "repos/VitruvianSoftware/homelab/releases/latest": release(f"v{v}"),
        f"{CORE}/git/matching-refs/tags/gravastar-mouse-v": [
            {"ref": f"refs/tags/gravastar-mouse-v{v}"}
        ],
        f"{CORE}/releases/tags/gravastar-mouse-v{v}": release(f"gravastar-mouse-v{v}"),
        f"{CORE}/git/matching-refs/tags/esp32-s3-v": [
            {"ref": f"refs/tags/esp32-s3-v{v}"}
        ],
        f"{CORE}/releases/tags/esp32-s3-v{v}": release(
            f"esp32-s3-v{v}",
            [
                asset("esp32-s3-mac-controller.zip", 700 * 1024),
                asset("firmware.bin", 1300 * 1024),
                asset("bootloader.bin", 20 * 1024),
                asset("partitions.bin", 3 * 1024),
                asset("firmware.bin.sha256", 64),
            ],
        ),
        f"{CORE}/git/matching-refs/tags/android-remote-v": [
            {"ref": f"refs/tags/android-remote-v{v}"}
        ],
        f"{CORE}/releases/tags/android-remote-v{v}": release(
            f"android-remote-v{v}",
            [asset(f"remote-{v}.apk", 6 * mb), asset(f"remote-{v}.apk.sha256", 64)],
        ),
    }


class Harness:
    """Two copies of the tool, and a way to run them on the same inputs."""

    def __init__(self):
        self.tmp = tempfile.mkdtemp(prefix="sync-downloads-parity-")
        self.programs = {}
        for kind in ("py", "rs"):
            d = os.path.join(self.tmp, "bin-" + kind)
            os.makedirs(d)
            self.programs[kind] = os.path.join(d, "sync_downloads.py")
        shutil.copy(os.path.join(HERE, "sync_downloads.py"), self.programs["py"])
        shutil.copy(_binary(), self.programs["rs"])
        os.chmod(self.programs["rs"], 0o755)
        self.count = 0

    def close(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _new_dir(self):
        self.count += 1
        path = os.path.join(self.tmp, "case", str(self.count))
        os.makedirs(path)
        return path

    def run_one(self, kind, case):
        """Run one program on a case; everything it did, paths masked."""
        root = self._new_dir()
        work = os.path.join(root, "work")
        fakebin = os.path.join(root, "fakebin")
        ghdir = os.path.join(root, "gh")
        os.makedirs(work)
        os.makedirs(fakebin)
        os.makedirs(ghdir)
        log = os.path.join(root, "gh.log")
        open(log, "w").close()
        with open(os.path.join(fakebin, "which"), "w") as f:
            f.write(FAKE_WHICH)
        os.chmod(os.path.join(fakebin, "which"), 0o755)
        if case.get("gh", True):
            with open(os.path.join(fakebin, "gh"), "w") as f:
                f.write(FAKE_GH)
            os.chmod(os.path.join(fakebin, "gh"), 0o755)
        for name, body in case.get("git", {}).items():
            with open(os.path.join(fakebin, name), "w") as f:
                f.write(body)
            os.chmod(os.path.join(fakebin, name), 0o755)
        for endpoint, value in case.get("responses", {}).items():
            path = os.path.join(ghdir, endpoint)
            if endpoint.endswith("/"):
                path += "__index__"
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "wb") as f:
                f.write(
                    value if isinstance(value, bytes) else json.dumps(value).encode()
                )
        catalog = case.get("catalog")
        if isinstance(catalog, str):
            catalog = catalog.encode("utf-8")
        target = os.path.join(work, case.get("name", "downloads.yml"))
        if catalog is not None:
            with open(target, "wb") as f:
                f.write(catalog)
        if case.get("catalog_dir"):
            os.makedirs(target)
        args = [a.replace("{WORK}", work) for a in case.get("args", ["--file", target])]
        env = {
            "PATH": fakebin,
            "FAKEBIN": fakebin,
            "FAKE_GH_DIR": ghdir,
            "FAKE_GH_LOG": log,
            "PYTHONUTF8": "1",
            "PYTHONDONTWRITEBYTECODE": "1",
            "https_proxy": "http://127.0.0.1:9",
            "HTTPS_PROXY": "http://127.0.0.1:9",
        }
        for k, v in case.get("env", {}).items():
            env[k] = v.replace("{WORK}", work)
        argv = [self.programs[kind]] + args
        if kind == "py":
            # -S: the script needs only the standard library, and skipping
            # site keeps a few hundred runs inside a small test's minute.
            argv = [sys.executable, "-S"] + argv
        proc = subprocess.run(argv, cwd=work, env=env, capture_output=True, timeout=60)
        after = None
        if os.path.isfile(target):
            with open(target, "rb") as f:
                after = f.read()
        with open(log, "rb") as f:
            calls = f.read().decode("utf-8", "replace").splitlines()

        def mask(b):
            return b.replace(work.encode(), b"<WORK>")

        return {
            "code": proc.returncode,
            "stdout": mask(proc.stdout),
            "stderr": mask(proc.stderr),
            "catalog": after,
            "calls": calls,
        }


def _mask_fetch_warnings(stderr):
    """Keep each fallback warning up to its URL: the error is in each
    program's own words (urllib through a refusing proxy, curl not found)."""
    out = []
    for line in stderr.split(b"\n"):
        if line.startswith(b"Warning: Failed to fetch https://api.github.com/"):
            url = line[len(b"Warning: Failed to fetch ") :].split(b": ", 1)[0]
            line = b"Warning: Failed to fetch " + url + b": <error>"
        out.append(line)
    return b"\n".join(out)


def _exception(stderr):
    last = stderr.rstrip(b"\n").rsplit(b"\n", 1)[-1]
    return last.split(b":", 1)[0]


class Parity(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.h = Harness()

    @classmethod
    def tearDownClass(cls):
        cls.h.close()

    def compare(self, case, label=""):
        with ThreadPoolExecutor(2) as pool:
            py_f = pool.submit(self.h.run_one, "py", case)
            rs_f = pool.submit(self.h.run_one, "rs", case)
            py, rs = py_f.result(), rs_f.result()
        what = f"{label or case.get('label', '')}: args={case.get('args')}"
        self.assertEqual(py["code"], rs["code"], f"{what}\npy={py}\nrs={rs}")
        self.assertEqual(py["stdout"], rs["stdout"], what)
        self.assertEqual(py["calls"], rs["calls"], what)
        self.assertEqual(py["catalog"], rs["catalog"], what)
        if TRACEBACK in py["stderr"]:
            self.assertIn(
                TRACEBACK, rs["stderr"], f"{what}\n{py['stderr']!r}\n{rs['stderr']!r}"
            )
            self.assertEqual(
                _exception(py["stderr"]),
                _exception(rs["stderr"]),
                f"{what}\n{py['stderr']!r}\n{rs['stderr']!r}",
            )
        else:
            self.assertEqual(
                _mask_fetch_warnings(py["stderr"]),
                _mask_fetch_warnings(rs["stderr"]),
                what,
            )
        return py

    def compare_many(self, cases):
        with ThreadPoolExecutor(8) as pool:
            futures = [
                pool.submit(
                    lambda c: (self.h.run_one("py", c), self.h.run_one("rs", c)), c
                )
                for c in cases
            ]
            results = [f.result() for f in futures]
        for case, (py, rs) in zip(cases, results):
            what = f"{case.get('label', '')}: args={case.get('args')}"
            for key in ("code", "stdout", "calls", "catalog"):
                self.assertEqual(py[key], rs[key], f"{what} [{key}]\npy={py}\nrs={rs}")
            if TRACEBACK in py["stderr"]:
                self.assertEqual(
                    _exception(py["stderr"]), _exception(rs["stderr"]), what
                )
            else:
                self.assertEqual(
                    _mask_fetch_warnings(py["stderr"]),
                    _mask_fetch_warnings(rs["stderr"]),
                    what,
                )
        return results

    # -- the unit tests' own inputs ------------------------------------

    def recorded_inputs(self):
        """Run sync_downloads_test.py, recording what it hands the script."""
        seen = {"parse_semver": [], "format_size": []}
        originals = {name: getattr(sdt, name) for name in seen}

        def recorder(name):
            def call(*args):
                seen[name].append(args[0])
                return originals[name](*args)

            return call

        for name in seen:
            setattr(sdt, name, recorder(name))
        try:
            suite = unittest.defaultTestLoader.loadTestsFromModule(sdt)
            with open(os.devnull, "w") as devnull:
                result = unittest.TextTestRunner(stream=devnull).run(suite)
            self.assertTrue(result.wasSuccessful())
        finally:
            for name, fn in originals.items():
                setattr(sdt, name, fn)
        self.assertTrue(seen["parse_semver"] and seen["format_size"])
        return seen

    def test_unit_test_sizes(self):
        """Each size the unit tests format, as a nexus-agent download."""
        sizes = self.recorded_inputs()["format_size"]
        cases = []
        for size in sizes:
            responses = {
                "repos/VitruvianSoftware/nexus-agent/releases/latest": release(
                    "v2.0.0", [asset("N-arm64.dmg", size)]
                )
            }
            cases.append(
                {
                    "label": f"size {size}",
                    "catalog": read_catalog(),
                    "responses": responses,
                }
            )
        for size, (py, _) in zip(sizes, self.compare_many(cases)):
            self.assertIn(f"size: {sd.format_size(size)}".encode(), py["catalog"])

    def test_unit_test_tags(self):
        """The unit tests' tags, in several orders: the same one wins."""
        tags = self.recorded_inputs()["parse_semver"]
        rng = random.Random(3)
        cases = []
        for i in range(3):
            order = tags[:]
            rng.shuffle(order)
            responses = {
                "repos/VitruvianSoftware/nexus-agent/releases/latest": release(
                    "v0", prerelease=True
                ),
                "repos/VitruvianSoftware/nexus-agent/git/matching-refs/tags/": [
                    {"ref": "refs/tags/" + t} for t in order
                ],
            }
            for t in tags:
                responses[f"repos/VitruvianSoftware/nexus-agent/releases/tags/{t}"] = (
                    release(t)
                )
            cases.append(
                {
                    "label": f"tag order {i}",
                    "catalog": read_catalog(),
                    "responses": responses,
                }
            )
        for py, _ in self.compare_many(cases):
            wanted = max(tags, key=sd.parse_semver)
            self.assertIn(
                f"repos/VitruvianSoftware/nexus-agent/releases/tags/{wanted}",
                py["calls"],
            )

    # -- whole runs --------------------------------------------------------

    def test_every_mode(self):
        catalog = read_catalog()
        responses = full_releases()
        written = self.compare(
            {"label": "write", "catalog": catalog, "responses": responses}
        )
        self.assertEqual(written["code"], 0)
        self.assertNotEqual(written["catalog"], catalog.encode())
        target = ["--file", "{WORK}/downloads.yml"]
        modes = [
            ["--dry-run"],
            ["--check"],
            ["--check", "--dry-run"],
            ["--dry"],
            ["--c"],
        ]
        cases = [
            {
                "label": "mode",
                "catalog": catalog,
                "responses": responses,
                "args": target + a,
            }
            for a in modes
        ]
        # Run again on what it wrote: nothing left to change.
        for args in ([], ["--check"], ["--dry-run"]):
            cases.append(
                {
                    "label": "up to date",
                    "catalog": written["catalog"],
                    "responses": responses,
                    "args": target + args,
                }
            )
        results = self.compare_many(cases)
        self.assertIn(b"already up to date", results[-3][0]["stdout"])

    def test_nothing_found(self):
        nulls = {k: None for k in full_releases()}
        self.compare_many(
            [
                {"label": "all 404", "catalog": read_catalog(), "responses": {}},
                {"label": "no gh", "catalog": read_catalog(), "gh": False},
                {"label": "nulls", "catalog": read_catalog(), "responses": nulls},
            ]
        )

    def test_release_paths(self):
        nexus = "repos/VitruvianSoftware/nexus-agent"
        cases = [
            # A prerelease as latest: every tag, beta ones dropped, ties stable.
            {
                f"{nexus}/releases/latest": release("v5.0.0", prerelease=True),
                f"{nexus}/git/matching-refs/tags/": [
                    {"ref": "refs/tags/v1.2"},
                    {"ref": "refs/tags/v1.2.0"},
                    {"ref": "refs/tags/v3.0.0-BETA"},
                    {"ref": "refs/tags/x"},
                ],
                f"{nexus}/releases/tags/v1.2": release(
                    "v1.2", [asset("a-arm64.dmg", 5)]
                ),
            },
            # No refs: the release list, prereleases and other prefixes skipped.
            {
                f"{CORE}/git/matching-refs/tags/vitruvian-v": [],
                f"{CORE}/releases?per_page=50": [
                    release("vitruvian-v9.0.0", prerelease=True),
                    release("home-speaker-v2.0.0"),
                    release(
                        "vitruvian-v8.0.0", [asset("Vitruvian-8.dmg", 4 * 1024 * 1024)]
                    ),
                ],
            },
            # Refs only of the wrong prefix or beta: nothing.
            {
                f"{CORE}/git/matching-refs/tags/home-speaker-v": [
                    {"ref": "refs/tags/home-speaker-v2-beta"},
                    {"ref": "refs/tags/other-v1.0.0"},
                ],
            },
            # Falsy latest, then refs, then the tagged release is null.
            {
                f"{nexus}/releases/latest": {},
                f"{nexus}/git/matching-refs/tags/": [{"ref": "refs/tags/v2.0.0"}],
            },
            # Vitruvian with no universal.dmg: a plain .dmg is the universal one.
            {
                f"{CORE}/git/matching-refs/tags/vitruvian-v": [
                    {"ref": "refs/tags/vitruvian-v4.0.0"}
                ],
                f"{CORE}/releases/tags/vitruvian-v4.0.0": release(
                    "vitruvian-v4.0.0",
                    [
                        asset("Vitruvian-beta.dmg", 1),
                        asset("Vitruvian-4.0.0.dmg", 30 * 1024 * 1024),
                        asset("Vitruvian-arm64-extra.dmg", 2),
                    ],
                ),
            },
            # HomeSpeaker with no universal.zip: the -macOS.zip.
            {
                f"{CORE}/git/matching-refs/tags/home-speaker-v": [
                    {"ref": "refs/tags/home-speaker-v3.1.4"}
                ],
                f"{CORE}/releases/tags/home-speaker-v3.1.4": release(
                    "home-speaker-v3.1.4",
                    [asset("HomeSpeaker-3.1.4-macOS.zip", 1024 * 1024 * 10.5)],
                ),
            },
            # Names that are lists or dicts: membership, not substrings.
            {
                f"{CORE}/git/matching-refs/tags/vitruvian-v": [
                    {"ref": "refs/tags/vitruvian-v4.0.0"}
                ],
                f"{CORE}/releases/tags/vitruvian-v4.0.0": release(
                    "vitruvian-v4.0.0",
                    [{"name": ["universal.dmg"]}],
                ),
            },
        ]
        self.compare_many(
            [
                {"label": f"path {i}", "catalog": read_catalog(), "responses": r}
                for i, r in enumerate(cases)
            ]
        )

    def test_bad_values(self):
        nexus = "repos/VitruvianSoftware/nexus-agent/releases/latest"
        esp = f"{CORE}/releases/tags/esp32-s3-v1.0.0"
        esp_refs = {
            f"{CORE}/git/matching-refs/tags/esp32-s3-v": [
                {"ref": "refs/tags/esp32-s3-v1.0.0"}
            ]
        }
        values: list = [
            release("v1", [asset("x-arm64.dmg", None)]),
            release("v1", [asset("x-arm64.dmg", "12")]),
            release("v1", [asset("x-arm64.dmg", [1])]),
            release("v1", [asset("x-arm64.dmg", True)]),
            release("v1", [asset("x-arm64.dmg", 1.5e300)]),
            release("v1", [asset("x-arm64.dmg", 123456789012345678)]),
            release("v1", [asset("x-arm64.dmg", -1)]),
            release("v1", [asset("x-arm64.dmg", 512)]),
            release("v1", [asset("x-arm64.dmg", 1536)]),
            release("v1", [asset("x-arm64.dmg", 1048575)]),
            release("v1", [asset("x-arm64.dmg", 10 * 1024 * 1024 + 1)]),
            release(
                "v1",
                [asset("x-arm64.dmg", 5, url=None) | {"browser_download_url": None}],
            ),
            release("v1", [asset("x-arm64.dmg", 5, url=7)]),
            release("v1", [asset("x-arm64.dmg", 5, url=[1, "a", None, 2.5])]),
            release("v1", [asset("x-arm64.dmg", 5, url={"k": "it's"})]),
            release("v1", [asset(None, 5)]),
            release("v1", [asset(3, 5)]),
            release("v1", ["not-a-dict"]),
            {"tag_name": "v1", "assets": "abc"},
            {"tag_name": "v1", "assets": 5},
            {"tag_name": 7},
            {"tag_name": None, "assets": []},
            {"assets": [asset("x-arm64.dmg", 1)]},
            ["a", "list"],
            "a string",
            42,
        ]
        cases = [
            {
                "label": f"nexus {v!r}"[:80],
                "catalog": read_catalog(),
                "responses": {nexus: v},
            }
            for v in values
        ]
        for v in values[:12:2]:
            if isinstance(v, dict) and isinstance(v.get("assets"), list):
                responses: dict = dict(esp_refs)
                responses[esp] = {
                    "tag_name": "esp32-s3-v1.0.0",
                    "assets": [{**a, "name": "firmware.bin"} for a in v["assets"]],
                }
                cases.append(
                    {"label": "esp", "catalog": read_catalog(), "responses": responses}
                )
        for raw in (
            b"not json",
            b"",
            b"[1,]",
            b"\xff\xfe",
            b'{"tag_name": "v1", "assets": NaN}',
            b"NaN",
        ):
            cases.append(
                {
                    "label": f"raw {raw!r}",
                    "catalog": read_catalog(),
                    "responses": {nexus: raw},
                }
            )
        nan_size = (
            b'{"tag_name": "v1", "assets": [{"name": "a-arm64.dmg", "size": NaN}]}'
        )
        inf_size = b'{"tag_name": "v1", "assets": [{"name": "a-arm64.dmg", "size": -Infinity}]}'
        cases.append(
            {
                "label": "nan size",
                "catalog": read_catalog(),
                "responses": {nexus: nan_size},
            }
        )
        cases.append(
            {
                "label": "-inf size",
                "catalog": read_catalog(),
                "responses": {nexus: inf_size},
            }
        )
        refs = "repos/VitruvianSoftware/nexus-agent/git/matching-refs/tags/"
        for bad_refs in ([{"ref": 5}], ["x"], {"a": 1}, [{}], 7):
            cases.append(
                {
                    "label": f"refs {bad_refs!r}",
                    "catalog": read_catalog(),
                    "responses": {
                        nexus: release("v1", prerelease=True),
                        refs: bad_refs,
                    },
                }
            )
        self.compare_many(cases)

    def test_template_escapes(self):
        """Tags and URLs go into re.sub's replacement as written, so their
        backslashes are template escapes."""
        nexus = "repos/VitruvianSoftware/nexus-agent/releases/latest"
        mouse_refs = f"{CORE}/git/matching-refs/tags/gravastar-mouse-v"
        tags = [
            r"v1\n2",
            r"v1\t\a\b\f\v\r",
            r"v\g<0>",
            r"v\g<1>",
            r"v\g<2>",
            r"v\g<3>",
            r"v\g<00002>",
            r"v\g<name>",
            r"v\g<na me>",
            r"v\g<>",
            r"v\g<1",
            r"v\g1",
            r"v\1\2",
            r"v\3",
            r"v\10",
            r"v\101",
            r"v\0",
            r"v\07x",
            r"v\400",
            r"v\q",
            r"v\%",
            "v\\",
            "v\\\\",
        ]
        # Every escape as a version; a few as a URL and in the releases_url
        # pattern, which has one group, not two, so \g<2> fails there.
        one_group = {r"v\g<1>", r"v\g<2>", r"v\1\2", r"v\101", r"v\q", "v\\"}
        cases = []
        for t in tags:
            cases.append(
                {
                    "label": t,
                    "catalog": read_catalog(),
                    "responses": {nexus: release(t)},
                }
            )
            if t not in one_group:
                continue
            cases.append(
                {
                    "label": "url " + t,
                    "catalog": read_catalog(),
                    "responses": {
                        nexus: release("v1", [asset("a-arm64.dmg", 9, url=t)])
                    },
                }
            )
            mouse_tag = "gravastar-mouse-v" + t[1:]
            cases.append(
                {
                    "label": "mouse " + t,
                    "catalog": read_catalog(),
                    "responses": {
                        mouse_refs: [{"ref": "refs/tags/" + mouse_tag}],
                        f"{CORE}/releases/tags/{mouse_tag}": release(mouse_tag),
                    },
                }
            )
        self.compare_many(cases)

    def test_catalogs(self):
        base = read_catalog()
        responses = full_releases(3)
        lines = base.splitlines(keepends=True)
        filler = "".join(
            ("    - repeated line\n" if i % 3 else f"    - filler {i}\n")
            for i in range(400)
        )
        catalogs = {
            "crlf": base.replace("\n", "\r\n"),
            "cr": base.replace("\n", "\r"),
            "no trailing newline": base.rstrip("\n"),
            "empty": "",
            "no products": "categories: []\n",
            "half": "".join(lines[: len(lines) // 2]),
            "reversed blocks": "".join(reversed(lines)),
            "long (autojunk)": filler + base + filler,
            "interleaved": "".join(
                line + ("  # note\n" if i % 2 else "\n") for i, line in enumerate(lines)
            ),
            "unicode": base.replace(
                "Desktop & Menu Bar Apps", "Desktop \u2028 apps \u00e9\x0c"
            ),
            "empty version": base.replace('version: "1.31.1"', 'version: ""'),
        }
        cases = [
            {"label": k, "catalog": v, "responses": responses}
            for k, v in catalogs.items()
        ]
        cases += [
            {
                "label": k + " dry",
                "catalog": catalogs[k],
                "responses": responses,
                "args": ["--dry-run", "--file", "{WORK}/downloads.yml"],
            }
            for k in (
                "crlf",
                "no trailing newline",
                "long (autojunk)",
                "reversed blocks",
            )
        ]
        cases += [
            {"label": "missing", "responses": responses},
            {"label": "directory", "catalog_dir": True, "responses": responses},
            {
                "label": "not utf-8",
                "catalog": b"id: devx\n\xff\xfe\n",
                "responses": responses,
            },
        ]
        self.compare_many(cases)

    def test_paths(self):
        cat = read_catalog()
        work = {"BUILD_WORKSPACE_DIRECTORY": "{WORK}"}
        git_ok = {"git": '#!/bin/sh\necho "$CASE_WORK"\n'}
        git_bad = {"git": "#!/bin/sh\nexit 1\n"}
        rel = ["--file", "downloads.yml"]
        cases = [
            {"label": "relative, workspace", "args": rel, "env": work},
            {
                "label": "relative, workspace/",
                "args": rel,
                "env": {"BUILD_WORKSPACE_DIRECTORY": "{WORK}/"},
            },
            {"label": "relative, no git", "args": rel},
            {"label": "relative, git fails", "args": rel, "git": git_bad},
            {
                "label": "relative, git ok",
                "args": rel,
                "git": git_ok,
                "env": {"CASE_WORK": "{WORK}"},
            },
            {"label": "default path", "args": [], "env": work},
            {"label": "empty path", "args": ["--file="], "env": work},
            {
                "label": "token",
                "args": ["--token", "t0k", "--file", "{WORK}/downloads.yml"],
                "gh": False,
                "env": {"GH_TOKEN": "x"},
            },
        ]
        for c in cases:
            c["catalog"] = cat
            c["responses"] = full_releases(5)
        self.compare_many(cases)

    def test_command_lines(self):
        lines = [
            ["-h"],
            ["--help"],
            ["--he"],
            ["--h"],
            ["-hx"],
            ["-hh"],
            ["-h=x"],
            ["--help=x"],
            ["--check=1"],
            ["--dry-run=", "--file={WORK}/downloads.yml"],
            ["--file"],
            ["--file", "--check"],
            ["--file", "-x"],
            ["--file", "-5", "--dry-run"],
            ["--fi={WORK}/downloads.yml", "--d"],
            ["--bogus"],
            ["--bogus", "-h"],
            ["positional"],
            ["--", "--check"],
            ["--=x"],
            ["--", "-h"],
            ["-x", "y"],
            ["-"],
            ["", "--check"],
            ["--token"],
            ["--token=", "--file", "{WORK}/downloads.yml"],
            ["--file", "{WORK}/downloads.yml", "--file", "{WORK}/other.yml"],
            ["-c"],
            ["--check", "x y"],
            ["-h", "--file"],
            ["--file", "a b", "-h"],
        ]
        # Every line at the default width; the ones that print usage or help
        # at other widths too, since argparse wraps to the terminal.
        wraps = [
            ["-h"],
            ["--he"],
            ["-hx"],
            ["--file"],
            ["--bogus"],
            ["--=x"],
            ["--check=1"],
            ["positional"],
        ]
        cases = []
        for args in lines:
            widths = (None, "20", "57", "100", "1", "abc") if args in wraps else (None,)
            for columns in widths:
                env = {"BUILD_WORKSPACE_DIRECTORY": "{WORK}"}
                if columns is not None:
                    env["COLUMNS"] = columns
                # No catalog: argparse is what is under test, and a run that
                # gets past it stops at "not found" before any fetch.
                cases.append(
                    {
                        "label": f"cols={columns}",
                        "args": args,
                        "env": env,
                        "responses": {},
                    }
                )
        self.compare_many(cases)

    def test_random(self):
        rng = random.Random(20261024)
        base = read_catalog()
        names = [
            "X-arm64.dmg",
            "X-universal.dmg",
            "X-x86_64.dmg",
            "X-universal.zip",
            "X.dmg",
            "X-beta.dmg",
            "X-macOS.zip",
            "X.apk",
            "X.dmg.sha256",
            "X.sig",
            "firmware.bin",
            "bootloader.bin",
            "partitions.bin",
            "esp32-s3-mac-controller.zip",
            "other.txt",
        ]
        sizes = [
            0,
            1,
            511,
            512,
            513,
            1023,
            1024,
            1536,
            2560,
            1048575,
            1048576,
            10 * 1048576,
            int(9.95 * 1048576),
            int(99.99 * 1048576),
            123456789,
            7.5,
            2**40,
        ]
        products = [
            ("repos/VitruvianSoftware/nexus-agent", None, "v"),
            (CORE, "vitruvian-v", "vitruvian-v"),
            (CORE, "home-speaker-v", "home-speaker-v"),
            ("repos/VitruvianSoftware/devx", None, "v"),
            ("repos/VitruvianSoftware/homelab", None, "v"),
            (CORE, "gravastar-mouse-v", "gravastar-mouse-v"),
            (CORE, "esp32-s3-v", "esp32-s3-v"),
            (CORE, "android-remote-v", "android-remote-v"),
        ]
        lines = base.splitlines(keepends=True)
        cases = []
        for n in range(30):
            responses = {}
            for repo, prefix, tag_prefix in products:
                if rng.random() < 0.15:
                    continue
                tags = [
                    f"{tag_prefix}{rng.randint(0, 12)}.{rng.randint(0, 40)}"
                    + (f".{rng.randint(0, 9)}" if rng.random() < 0.8 else "")
                    + ("-beta.1" if rng.random() < 0.1 else "")
                    for _ in range(rng.randint(1, 4))
                ]
                assets = [
                    asset(
                        rng.choice(names).replace("X", f"P{rng.randint(1, 3)}"),
                        rng.choice(sizes),
                    )
                    for _ in range(rng.randint(0, 6))
                ]
                if prefix is None:
                    rel = release(tags[0], assets, prerelease=rng.random() < 0.2)
                    responses[f"{repo}/releases/latest"] = rel
                    if rel["prerelease"]:
                        responses[f"{repo}/git/matching-refs/tags/"] = [
                            {"ref": "refs/tags/" + t} for t in tags
                        ]
                        for t in tags:
                            responses[f"{repo}/releases/tags/{t}"] = release(t, assets)
                else:
                    if rng.random() < 0.2:
                        responses[f"{repo}/releases?per_page=50"] = [
                            release(t, assets) for t in tags
                        ]
                    else:
                        responses[f"{repo}/git/matching-refs/tags/{prefix}"] = [
                            {"ref": "refs/tags/" + t} for t in tags
                        ]
                        for t in tags:
                            responses[f"{repo}/releases/tags/{t}"] = release(t, assets)
            # A catalog with some lines dropped, duplicated or moved.
            mutated = list(lines)
            for _ in range(rng.randint(0, 6)):
                op = rng.random()
                i = rng.randrange(len(mutated))
                if op < 0.4:
                    del mutated[i]
                elif op < 0.8:
                    mutated.insert(rng.randrange(len(mutated)), mutated[i])
                else:
                    mutated[i] = mutated[i].replace(":", ": ", 1)
            mode = rng.choice([[], ["--dry-run"], ["--check"]])
            cases.append(
                {
                    "label": f"random {n}",
                    "catalog": "".join(mutated),
                    "responses": responses,
                    "args": ["--file", "{WORK}/downloads.yml"] + mode,
                }
            )
        self.compare_many(cases)


if __name__ == "__main__":
    unittest.main()
