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
"""generate_assets (Rust, :generate_assets) against generate_assets.py
(:generate_assets_py): same SVG to the renderer, same PNGs out.

    bazel test //apps/mobile/wearos/faces/daytona-platinum:generate_assets_rs_parity_test

Neither program draws pixels itself: each writes an SVG per asset and runs
rsvg-convert on it. So the test puts a stand-in rsvg-convert first on PATH
(both programs find the renderer through PATH). The stand-in keeps a copy
of every SVG it is handed and the size it was asked for, then runs the real
rsvg-convert when there is one. That gives two checks:

  * the SVG documents, byte for byte, and the -w/-h for every PNG. This
    half needs no renderer and always runs;
  * every PNG: a well-formed file (signature, IHDR, every chunk CRC, the
    zlib stream and its Adler-32, IEND), the expected size, and the same
    decoded RGBA pixels from both programs. This half needs a real
    rsvg-convert and is skipped, by name, without one.

Plus the command lines and exit codes, the default output directory under
BUILD_WORKSPACE_DIRECTORY, a renderer failure, and the time each takes
(written to the test's undeclared outputs as benchmark.txt).
"""

import json
import os
import shutil
import stat
import struct
import subprocess
import sys
import tempfile
import time
import unittest
import zlib

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
PACKAGE_REL = os.path.join("apps", "mobile", "wearos", "faces", "daytona-platinum")
DRAWABLE_REL = os.path.join("src", "main", "res", "drawable-nodpi")
DONE = b"Re-rendered all Daytona reference theme & OLED AOD PNG assets successfully.\n"

# Every PNG the generator writes and its size (watchface_test.py checks the
# committed copies against the same list).
EXPECTED = {
    **{
        name: 450
        for name in (
            "dial_interactive.png",
            "dial_ambient.png",
            "dial_ultra_ambient.png",
            "dial_expanded_interactive.png",
            "dial_expanded_ambient.png",
            "dial_expanded_ultra_ambient.png",
            "dial_panda_interactive.png",
            "dial_panda_expanded_interactive.png",
            "dial_revpanda_interactive.png",
            "dial_revpanda_expanded_interactive.png",
            "dial_lemans_interactive.png",
            "dial_lemans_expanded_interactive.png",
            "hand_hour.png",
            "hand_hour_aod.png",
            "hand_minute.png",
            "hand_minute_aod.png",
            "hand_second.png",
            "preview.png",
            "preview_circular.png",
        )
    },
    "subdial_hand.png": 88,
    "subdial_hand_expanded.png": 120,
    "unread_badge.png": 24,
}

SHIM = r"""
import json, os, shutil, sys

args = sys.argv[1:]
out = args[args.index("-o") + 1]
width = args[args.index("-w") + 1]
height = args[args.index("-h") + 1]
flags = {"-o", "-w", "-h"}
positional = [a for i, a in enumerate(args) if a not in flags and (i == 0 or args[i - 1] not in flags)]
(svg,) = positional
cap = os.environ["SHIM_CAPTURE_DIR"]
name = os.path.basename(out)
shutil.copyfile(svg, os.path.join(cap, name + ".svg"))
with open(os.path.join(cap, name + ".json"), "w") as f:
    json.dump({"w": width, "h": height, "svg": os.path.basename(svg)}, f)
if os.environ.get("SHIM_FAIL"):
    sys.stderr.write("rsvg-convert stand-in: failing on purpose\n")
    sys.exit(3)
real = os.environ.get("SHIM_REAL_RSVG")
if real:
    os.execv(real, [real] + args)
open(out, "wb").close()
"""


def find_real_rsvg():
    for cand in (
        shutil.which("rsvg-convert"),
        "/opt/homebrew/bin/rsvg-convert",
        "/usr/local/bin/rsvg-convert",
        "/usr/bin/rsvg-convert",
    ):
        if cand and os.access(cand, os.X_OK):
            return cand
    return None


def rlocation(env_var):
    path = os.environ[env_var]
    return path if os.path.isabs(path) else os.path.abspath(path)


def decode_png(data, label):
    """Check a PNG is well formed and return (width, height, RGBA bytes)."""
    if data[:8] != PNG_SIGNATURE:
        raise AssertionError(f"{label}: bad PNG signature")
    pos, chunks = 8, []
    while pos < len(data):
        if pos + 12 > len(data):
            raise AssertionError(f"{label}: truncated chunk at {pos}")
        (length,) = struct.unpack(">I", data[pos : pos + 4])
        ctype = data[pos + 4 : pos + 8]
        body = data[pos + 8 : pos + 8 + length]
        (crc,) = struct.unpack(">I", data[pos + 8 + length : pos + 12 + length])
        if zlib.crc32(ctype + body) & 0xFFFFFFFF != crc:
            raise AssertionError(f"{label}: bad CRC on {ctype!r} chunk")
        chunks.append((ctype, body))
        pos += 12 + length
    if not chunks or chunks[0][0] != b"IHDR" or len(chunks[0][1]) != 13:
        raise AssertionError(f"{label}: first chunk is not a 13-byte IHDR")
    if chunks[-1] != (b"IEND", b""):
        raise AssertionError(f"{label}: does not end with an empty IEND")
    width, height, depth, ctype, comp, filt, interlace = struct.unpack(
        ">IIBBBBB", chunks[0][1]
    )
    if (depth, comp, filt, interlace) != (8, 0, 0, 0) or ctype not in (2, 6):
        raise AssertionError(
            f"{label}: unsupported PNG format depth={depth} colour={ctype} interlace={interlace}"
        )
    # zlib.decompress checks the stream's Adler-32.
    raw = zlib.decompress(b"".join(body for t, body in chunks if t == b"IDAT"))
    bpp = 4 if ctype == 6 else 3
    stride = width * bpp
    if len(raw) != height * (stride + 1):
        raise AssertionError(
            f"{label}: IDAT holds {len(raw)} bytes, want {height * (stride + 1)}"
        )
    out = bytearray(height * stride)
    prev = bytearray(stride)
    for y in range(height):
        ftype = raw[y * (stride + 1)]
        line = bytearray(raw[y * (stride + 1) + 1 : (y + 1) * (stride + 1)])
        for i in range(stride):
            a = line[i - bpp] if i >= bpp else 0
            b = prev[i]
            c = prev[i - bpp] if i >= bpp else 0
            if ftype == 0:
                pred = 0
            elif ftype == 1:
                pred = a
            elif ftype == 2:
                pred = b
            elif ftype == 3:
                pred = (a + b) >> 1
            elif ftype == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pred = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
            else:
                raise AssertionError(f"{label}: bad filter type {ftype} on row {y}")
            line[i] = (line[i] + pred) & 0xFF
        out[y * stride : (y + 1) * stride] = line
        prev = line
    if ctype == 2:
        rgb, out = out, bytearray()
        for i in range(0, len(rgb), 3):
            out += rgb[i : i + 3] + b"\xff"
    return width, height, bytes(out)


class Run:
    """One run of one generator through the stand-in renderer."""

    def __init__(self, root, label):
        self.root = os.path.join(root, label)
        self.capture = os.path.join(self.root, "capture")
        self.shim_dir = os.path.join(self.root, "bin")
        self.tmp = os.path.join(self.root, "tmp")
        for d in (self.capture, self.shim_dir, self.tmp):
            os.makedirs(d)
        shim_py = os.path.join(self.shim_dir, "shim.py")
        with open(shim_py, "w") as f:
            f.write(SHIM)
        wrapper = os.path.join(self.shim_dir, "rsvg-convert")
        with open(wrapper, "w") as f:
            f.write(f'#!/bin/sh\nexec "{sys.executable}" "{shim_py}" "$@"\n')
        os.chmod(
            wrapper,
            os.stat(wrapper).st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH,
        )

    def env(self, real_rsvg, fail=False, workspace=None):
        env = dict(os.environ)
        env["PATH"] = self.shim_dir + os.pathsep + env.get("PATH", "/bin:/usr/bin")
        env["SHIM_CAPTURE_DIR"] = self.capture
        env["TMPDIR"] = self.tmp
        env.pop("SHIM_FAIL", None)
        env.pop("SHIM_REAL_RSVG", None)
        env.pop("BUILD_WORKSPACE_DIRECTORY", None)
        if fail:
            env["SHIM_FAIL"] = "1"
        if real_rsvg:
            env["SHIM_REAL_RSVG"] = real_rsvg
        if workspace:
            env["BUILD_WORKSPACE_DIRECTORY"] = workspace
        return env

    def svgs(self):
        out = {}
        for name in EXPECTED:
            with open(os.path.join(self.capture, name + ".svg"), "rb") as f:
                svg = f.read()
            with open(os.path.join(self.capture, name + ".json")) as f:
                meta = json.load(f)
            out[name] = (svg, meta["w"], meta["h"])
        return out

    def captured_names(self):
        return {
            n[: -len(".svg")] for n in os.listdir(self.capture) if n.endswith(".svg")
        }


def run(cmd, env, cwd=None):
    start = time.perf_counter()
    proc = subprocess.run(cmd, env=env, cwd=cwd, capture_output=True, timeout=240)
    return proc, time.perf_counter() - start


class GenerateAssetsParityTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.py_bin = rlocation("GENERATE_ASSETS_PY")
        cls.rs_bin = rlocation("GENERATE_ASSETS_RS")
        cls.real_rsvg = find_real_rsvg()
        cls.root = tempfile.mkdtemp(
            prefix="daytona_parity_", dir=os.environ.get("TEST_TMPDIR")
        )

        if cls.real_rsvg:
            # Warm fontconfig's cache so neither timed run pays for it.
            warm = os.path.join(cls.root, "warm.svg")
            with open(warm, "w") as f:
                f.write(
                    '<svg xmlns="http://www.w3.org/2000/svg" width="8" height="8">'
                    '<text x="0" y="8" font-family="Helvetica Neue">x</text></svg>'
                )
            subprocess.run(
                [cls.real_rsvg, warm, "-o", warm + ".png"],
                check=True,
                capture_output=True,
                timeout=120,
            )

        cls.py = Run(cls.root, "py")
        py_ws = os.path.join(cls.root, "py_ws")
        cls.py_out = os.path.join(py_ws, PACKAGE_REL, DRAWABLE_REL)
        cls.py_proc, cls.py_secs = run(
            [cls.py_bin], cls.py.env(cls.real_rsvg, workspace=py_ws)
        )

        cls.rs = Run(cls.root, "rs")
        cls.rs_out = os.path.join(cls.root, "rs_out")
        cls.rs_proc, cls.rs_secs = run(
            [cls.rs_bin, "--out-dir", cls.rs_out], cls.rs.env(cls.real_rsvg)
        )

        report = (
            f"renderer: {cls.real_rsvg or 'none (stand-in writes empty files)'}\n"
            f"generate_assets.py: {cls.py_secs:.3f}s\n"
            f"generate_assets (Rust): {cls.rs_secs:.3f}s\n"
            f"speed-up: {cls.py_secs / cls.rs_secs:.2f}x\n"
        )
        sys.stderr.write(report)
        outputs = os.environ.get("TEST_UNDECLARED_OUTPUTS_DIR")
        if outputs:
            with open(os.path.join(outputs, "benchmark.txt"), "w") as f:
                f.write(report)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.root, ignore_errors=True)

    def test_both_succeed_with_the_same_output(self):
        for label, proc in (("python", self.py_proc), ("rust", self.rs_proc)):
            self.assertEqual(
                proc.returncode,
                0,
                f"{label} failed:\n{proc.stderr.decode(errors='replace')}",
            )
        self.assertEqual(self.py_proc.stdout, DONE)
        self.assertEqual(self.rs_proc.stdout, self.py_proc.stdout)
        self.assertEqual(self.rs_proc.stderr, b"")

    def test_svg_documents_are_byte_identical(self):
        self.assertEqual(self.py.captured_names(), set(EXPECTED))
        self.assertEqual(self.rs.captured_names(), set(EXPECTED))
        py, rs = self.py.svgs(), self.rs.svgs()
        for name, size in sorted(EXPECTED.items()):
            with self.subTest(png=name):
                py_svg, py_w, py_h = py[name]
                rs_svg, rs_w, rs_h = rs[name]
                self.assertEqual((py_w, py_h), (str(size), str(size)))
                self.assertEqual((rs_w, rs_h), (py_w, py_h))
                if rs_svg != py_svg:
                    at = (
                        next(
                            i for i, (a, b) in enumerate(zip(py_svg, rs_svg)) if a != b
                        )
                        if any(a != b for a, b in zip(py_svg, rs_svg))
                        else min(len(py_svg), len(rs_svg))
                    )
                    self.fail(
                        f"{name}: SVG differs at byte {at} (python {len(py_svg)} bytes, rust {len(rs_svg)})\n"
                        f"python: {py_svg[max(0, at - 80) : at + 80]!r}\n"
                        f"rust:   {rs_svg[max(0, at - 80) : at + 80]!r}"
                    )

    def test_pngs_are_valid_and_pixel_identical(self):
        if not self.real_rsvg:
            self.skipTest(
                "no rsvg-convert on this host: SVG parity checked, pixels not"
            )
        self.assertEqual(sorted(os.listdir(self.py_out)), sorted(EXPECTED))
        self.assertEqual(sorted(os.listdir(self.rs_out)), sorted(EXPECTED))
        for name, size in sorted(EXPECTED.items()):
            with self.subTest(png=name):
                with open(os.path.join(self.py_out, name), "rb") as f:
                    py_png = f.read()
                with open(os.path.join(self.rs_out, name), "rb") as f:
                    rs_png = f.read()
                py_w, py_h, py_px = decode_png(py_png, f"python {name}")
                rs_w, rs_h, rs_px = decode_png(rs_png, f"rust {name}")
                self.assertEqual((py_w, py_h), (size, size))
                self.assertEqual((rs_w, rs_h), (py_w, py_h))
                if rs_px != py_px:
                    diff = sum(
                        1
                        for i in range(0, len(py_px), 4)
                        if py_px[i : i + 4] != rs_px[i : i + 4]
                    )
                    self.fail(f"{name}: {diff} of {py_w * py_h} pixels differ")
                # Not required, but expected: the same renderer on the same SVG.
                self.assertEqual(
                    rs_png, py_png, f"{name}: same pixels, different file bytes"
                )

    def test_default_out_dir_is_under_build_workspace(self):
        r = Run(self.root, "rs_default")
        ws = os.path.join(self.root, "rs_ws")
        proc, _ = run([self.rs_bin], r.env(None, workspace=ws), cwd=self.root)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(
            sorted(os.listdir(os.path.join(ws, PACKAGE_REL, DRAWABLE_REL))),
            sorted(EXPECTED),
        )

    def test_out_dir_equals_form(self):
        r = Run(self.root, "rs_equals")
        out = os.path.join(self.root, "rs_equals_out")
        proc, _ = run([self.rs_bin, f"--out-dir={out}"], r.env(None))
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(sorted(os.listdir(out)), sorted(EXPECTED))

    def test_help(self):
        for flag in ("-h", "--help"):
            proc, _ = run([self.rs_bin, flag], dict(os.environ))
            self.assertEqual(proc.returncode, 0)
            self.assertTrue(
                proc.stdout.startswith(b"usage: generate_assets [-h] [--out-dir DIR]\n")
            )
            self.assertIn(b"--out-dir DIR", proc.stdout)
            self.assertEqual(proc.stderr, b"")

    def test_usage_errors_exit_2_and_write_nothing(self):
        for args in (["--bogus"], ["stray"], ["--out-dir"], ["--out-dir="]):
            with self.subTest(args=args):
                r = Run(self.root, "usage_" + str(abs(hash(tuple(args)))))
                proc, _ = run(
                    [self.rs_bin] + args,
                    r.env(None, workspace=os.path.join(r.root, "ws")),
                )
                self.assertEqual(proc.returncode, 2)
                self.assertEqual(proc.stdout, b"")
                self.assertTrue(proc.stderr.startswith(b"usage: generate_assets"))
                self.assertIn(b"generate_assets: error: ", proc.stderr)
                self.assertEqual(r.captured_names(), set(), "nothing was rendered")
                self.assertFalse(os.path.exists(os.path.join(r.root, "ws")))

    def test_renderer_failure_fails_both(self):
        py = Run(self.root, "py_fail")
        py_proc, _ = run(
            [self.py_bin],
            py.env(None, fail=True, workspace=os.path.join(py.root, "ws")),
        )
        rs = Run(self.root, "rs_fail")
        rs_proc, _ = run(
            [self.rs_bin, "--out-dir", os.path.join(rs.root, "out")],
            rs.env(None, fail=True),
        )
        self.assertEqual(py_proc.returncode, 1)
        self.assertEqual(rs_proc.returncode, py_proc.returncode)
        self.assertNotIn(DONE, py_proc.stdout)
        self.assertEqual(rs_proc.stdout, b"")
        self.assertIn(b"rsvg-convert", rs_proc.stderr)
        self.assertIn(b"failed", rs_proc.stderr)


if __name__ == "__main__":
    unittest.main()
