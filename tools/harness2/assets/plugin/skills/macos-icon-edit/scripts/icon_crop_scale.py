#!/usr/bin/env python3
# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT

"""Deterministic edits of an EXISTING icon's pixels: measure, strip a border, scale, pad.

  icon_crop_scale.py inspect IN.png
  icon_crop_scale.py crop-scale IN.png OUT.png [--content 824] [--canvas 1024]
                    [--tolerance 12] [--strip-color FFFFFF ...] [--no-square] [--keep-background]

`inspect` prints the canvas size, the content box (everything that is not
transparent and not border-coloured, reached from the edges) and its margins,
and whether it sits on the macOS grid (1024 canvas, 824 artwork, 100 margin).

`crop-scale` crops to the content box, makes the stripped border transparent,
scales the content to --content pixels (with `sips` when present, else a
bilinear fallback) and centres it on a transparent --canvas square. It never
writes IN, and it prints a JSON report you can quote to the user.

Python standard library only: Pillow is not installed on this Mac.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import zlib
from collections import deque

PNG_SIG = b"\x89PNG\r\n\x1a\n"


class Image:
    def __init__(self, w: int, h: int, rgba: bytearray):
        self.w, self.h, self.px = w, h, rgba


def _paeth(a: int, b: int, c: int) -> int:
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    return b if pb <= pc else c


def read_png(path: str) -> Image:
    with open(path, "rb") as f:
        data = f.read()
    if data[:8] != PNG_SIG:
        raise SystemExit(f"{path}: not a PNG")
    pos, idat, plte, trns = 8, [], b"", b""
    w = h = depth = ctype = interlace = 0
    while pos < len(data):
        length, kind = struct.unpack(">I4s", data[pos : pos + 8])
        chunk = data[pos + 8 : pos + 8 + length]
        pos += 12 + length
        if kind == b"IHDR":
            w, h, depth, ctype, _, _, interlace = struct.unpack(">IIBBBBB", chunk)
        elif kind == b"PLTE":
            plte = chunk
        elif kind == b"tRNS":
            trns = chunk
        elif kind == b"IDAT":
            idat.append(chunk)
        elif kind == b"IEND":
            break
    if interlace:
        raise SystemExit(
            f"{path}: interlaced PNG; run `sips -s format png {path} --out plain.png` first"
        )
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}.get(ctype)
    if channels is None or depth not in (8, 16) and not (ctype == 3 and depth == 8):
        raise SystemExit(
            f"{path}: unsupported PNG (colour type {ctype}, depth {depth})"
        )
    bps = depth // 8
    bpp = channels * bps
    stride = w * bpp
    raw = zlib.decompress(b"".join(idat))
    out = bytearray(w * h * 4)
    prev = bytearray(stride)
    p = 0
    for y in range(h):
        ft = raw[p]
        line = bytearray(raw[p + 1 : p + 1 + stride])
        p += 1 + stride
        if ft == 1:
            for i in range(bpp, stride):
                line[i] = (line[i] + line[i - bpp]) & 255
        elif ft == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 255
        elif ft == 3:
            for i in range(stride):
                left = line[i - bpp] if i >= bpp else 0
                line[i] = (line[i] + ((left + prev[i]) >> 1)) & 255
        elif ft == 4:
            for i in range(stride):
                left = line[i - bpp] if i >= bpp else 0
                upleft = prev[i - bpp] if i >= bpp else 0
                line[i] = (line[i] + _paeth(left, prev[i], upleft)) & 255
        o = y * w * 4
        if bps == 2:
            line8 = line[0::2]
        else:
            line8 = line
        if ctype == 6:
            out[o : o + w * 4] = line8
        elif ctype == 2:
            row = out
            for x in range(w):
                row[o + 4 * x : o + 4 * x + 3] = line8[3 * x : 3 * x + 3]
                row[o + 4 * x + 3] = 255
        elif ctype == 0:
            for x in range(w):
                g = line8[x]
                out[o + 4 * x : o + 4 * x + 4] = bytes((g, g, g, 255))
        elif ctype == 4:
            for x in range(w):
                g, a = line8[2 * x], line8[2 * x + 1]
                out[o + 4 * x : o + 4 * x + 4] = bytes((g, g, g, a))
        else:  # palette
            for x in range(w):
                i = line8[x]
                r, g, b = plte[3 * i : 3 * i + 3]
                a = trns[i] if i < len(trns) else 255
                out[o + 4 * x : o + 4 * x + 4] = bytes((r, g, b, a))
        prev = line
    return Image(w, h, out)


def write_png(path: str, img: Image) -> None:
    stride = img.w * 4
    rows = bytearray()
    prev = bytes(stride)
    for y in range(img.h):
        line = bytes(img.px[y * stride : (y + 1) * stride])
        up = bytes((a - b) & 255 for a, b in zip(line, prev))  # filter 2 (Up)
        rows += b"\x02" + up
        prev = line

    def chunk(kind: bytes, body: bytes) -> bytes:
        return (
            struct.pack(">I", len(body))
            + kind
            + body
            + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)
        )

    ihdr = struct.pack(">IIBBBBB", img.w, img.h, 8, 6, 0, 0, 0)
    blob = (
        PNG_SIG
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(bytes(rows), 9))
        + chunk(b"IEND", b"")
    )
    tmp = path + ".tmp"
    with open(tmp, "wb") as f:
        f.write(blob)
    os.replace(tmp, path)


def _hex(c: str) -> tuple:
    c = c.lstrip("#")
    if len(c) != 6:
        raise SystemExit(f"--strip-color {c!r}: want RRGGBB")
    return tuple(int(c[i : i + 2], 16) for i in (0, 2, 4))


def background_mask(
    img: Image, strip: list, tol: int, alpha_floor: int = 16
) -> bytearray:
    """1 for each pixel reachable from the edge through transparent or strip-coloured pixels."""
    w, h, px = img.w, img.h, img.px

    def is_bg(i: int) -> bool:
        o = 4 * i
        if px[o + 3] < alpha_floor:
            return True
        r, g, b = px[o], px[o + 1], px[o + 2]
        for sr, sg, sb in strip:
            if abs(r - sr) <= tol and abs(g - sg) <= tol and abs(b - sb) <= tol:
                return True
        return False

    mask = bytearray(w * h)
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            q.append(y * w + x)
    for y in range(h):
        for x in (0, w - 1):
            q.append(y * w + x)
    while q:
        i = q.popleft()
        if mask[i] or not is_bg(i):
            continue
        mask[i] = 1
        x, y = i % w, i // w
        if x > 0:
            q.append(i - 1)
        if x < w - 1:
            q.append(i + 1)
        if y > 0:
            q.append(i - w)
        if y < h - 1:
            q.append(i + w)
    return mask


def content_box(img: Image, mask: bytearray):
    w, h = img.w, img.h
    xs0, ys0, xs1, ys1 = w, h, -1, -1
    for y in range(h):
        row = mask[y * w : (y + 1) * w]
        if row.count(1) == w:
            continue
        x0 = row.find(0)
        x1 = w - 1 - row[::-1].find(0)
        xs0, xs1 = min(xs0, x0), max(xs1, x1)
        ys0 = min(ys0, y)
        ys1 = y
    if xs1 < 0:
        return None
    return xs0, ys0, xs1 + 1, ys1 + 1  # [x0, x1) x [y0, y1)


def strip_colours(img: Image, args) -> list:
    cols = [_hex(c) for c in (args.strip_color or [])]
    if not args.no_auto_bg:
        w, h, px = img.w, img.h, img.px
        for x, y in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):
            o = 4 * (y * w + x)
            if px[o + 3] >= 16:
                c = tuple(px[o : o + 3])
                if c not in cols:
                    cols.append(c)
    return cols


def measure(img: Image, args) -> dict:
    mask = background_mask(img, strip_colours(img, args), args.tolerance)
    box = content_box(img, mask)
    rep = {"canvas": [img.w, img.h]}
    if box is None:
        rep["content_box"] = None
        return rep
    x0, y0, x1, y1 = box
    rep.update(
        {
            "content_box": [x0, y0, x1, y1],
            "content_size": [x1 - x0, y1 - y0],
            "margins": {
                "left": x0,
                "top": y0,
                "right": img.w - x1,
                "bottom": img.h - y1,
            },
        }
    )
    cw, ch = x1 - x0, y1 - y0
    rep["macos_grid"] = (
        (img.w, img.h) == (1024, 1024) and abs(cw - 824) <= 4 and abs(ch - 824) <= 4
    )
    return rep, mask, box


def crop(img: Image, box: tuple, mask: bytearray, clear_bg: bool) -> Image:
    x0, y0, x1, y1 = box
    w = x1 - x0
    out = bytearray(w * (y1 - y0) * 4)
    for y in range(y0, y1):
        src = 4 * (y * img.w + x0)
        dst = 4 * ((y - y0) * w)
        out[dst : dst + 4 * w] = img.px[src : src + 4 * w]
        if clear_bg:
            for x in range(x0, x1):
                if mask[y * img.w + x]:
                    out[dst + 4 * (x - x0) + 3] = 0
    return Image(w, y1 - y0, out)


def square_box(box: tuple, w: int, h: int) -> tuple:
    x0, y0, x1, y1 = box
    side = max(x1 - x0, y1 - y0)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    nx0 = int(round(cx - side / 2))
    ny0 = int(round(cy - side / 2))
    nx0 = min(max(0, nx0), max(0, w - side))
    ny0 = min(max(0, ny0), max(0, h - side))
    return nx0, ny0, min(w, nx0 + side), min(h, ny0 + side)


def resize_bilinear(img: Image, nw: int, nh: int) -> Image:
    out = bytearray(nw * nh * 4)
    sx = img.w / nw
    sy = img.h / nh
    for y in range(nh):
        fy = max(0.0, (y + 0.5) * sy - 0.5)
        y0 = min(int(fy), img.h - 1)
        y1 = min(y0 + 1, img.h - 1)
        wy = fy - y0
        for x in range(nw):
            fx = max(0.0, (x + 0.5) * sx - 0.5)
            x0 = min(int(fx), img.w - 1)
            x1 = min(x0 + 1, img.w - 1)
            wx = fx - x0
            a = 4 * (y0 * img.w + x0)
            b = 4 * (y0 * img.w + x1)
            c = 4 * (y1 * img.w + x0)
            d = 4 * (y1 * img.w + x1)
            o = 4 * (y * nw + x)
            for k in range(4):
                top = img.px[a + k] * (1 - wx) + img.px[b + k] * wx
                bot = img.px[c + k] * (1 - wx) + img.px[d + k] * wx
                out[o + k] = int(top * (1 - wy) + bot * wy + 0.5)
    return Image(nw, nh, out)


def resize(img: Image, nw: int, nh: int, tmpdir: str) -> tuple:
    sips = shutil.which("sips") or (
        "/usr/bin/sips" if os.path.exists("/usr/bin/sips") else None
    )
    if sips:
        src = os.path.join(tmpdir, "content.png")
        dst = os.path.join(tmpdir, "scaled.png")
        write_png(src, img)
        r = subprocess.run(
            [sips, "-z", str(nh), str(nw), src, "--out", dst],
            capture_output=True,
            text=True,
        )
        if r.returncode == 0 and os.path.exists(dst):
            scaled = read_png(dst)
            if (scaled.w, scaled.h) == (nw, nh):
                return scaled, "sips"
    return resize_bilinear(img, nw, nh), "bilinear"


def pad(img: Image, canvas: int) -> Image:
    out = bytearray(canvas * canvas * 4)
    ox = (canvas - img.w) // 2
    oy = (canvas - img.h) // 2
    for y in range(img.h):
        src = 4 * y * img.w
        dst = 4 * ((y + oy) * canvas + ox)
        out[dst : dst + 4 * img.w] = img.px[src : src + 4 * img.w]
    return Image(canvas, canvas, out)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name in ("inspect", "crop-scale"):
        p = sub.add_parser(name)
        p.add_argument("input")
        if name == "crop-scale":
            p.add_argument("output")
            p.add_argument(
                "--content",
                type=int,
                default=824,
                help="artwork size in pixels (macOS grid: 824)",
            )
            p.add_argument(
                "--canvas",
                type=int,
                default=1024,
                help="canvas size in pixels (macOS: 1024)",
            )
            p.add_argument(
                "--no-square",
                action="store_true",
                help="keep the content box's own aspect",
            )
            p.add_argument(
                "--keep-background",
                action="store_true",
                help="do not make stripped border pixels transparent",
            )
            p.add_argument(
                "--force",
                action="store_true",
                help="allow OUT to be the same file as IN",
            )
        p.add_argument(
            "--tolerance",
            type=int,
            default=12,
            help="per-channel distance that still counts as border colour",
        )
        p.add_argument(
            "--strip-color",
            action="append",
            metavar="RRGGBB",
            help="a border colour to strip (repeatable)",
        )
        p.add_argument(
            "--no-auto-bg",
            action="store_true",
            help="do not treat the corner colours as border",
        )
    args = ap.parse_args(argv)

    img = read_png(args.input)
    measured = measure(img, args)
    if not isinstance(measured, tuple):
        print(
            json.dumps(
                {
                    "error": "no content found: the whole image is border or transparent",
                    **measured,
                }
            )
        )
        return 1
    rep, mask, box = measured
    rep["input"] = os.path.abspath(args.input)
    if args.cmd == "inspect":
        print(json.dumps(rep, indent=2))
        return 0

    if os.path.abspath(args.output) == os.path.abspath(args.input) and not args.force:
        raise SystemExit(
            "refusing to overwrite the input; write to a new file and compare first (or --force)"
        )
    if args.content > args.canvas:
        raise SystemExit("--content cannot exceed --canvas")
    cbox = box if args.no_square else square_box(box, img.w, img.h)
    content = crop(img, cbox, mask, not args.keep_background)
    if args.no_square:
        scale = args.content / max(content.w, content.h)
        nw, nh = max(1, round(content.w * scale)), max(1, round(content.h * scale))
    else:
        nw = nh = args.content
    with tempfile.TemporaryDirectory(prefix="icon-edit-") as tmp:
        scaled, method = resize(content, nw, nh, tmp)
    final = pad(scaled, args.canvas)
    write_png(args.output, final)
    check = read_png(args.output)
    rep.update(
        {
            "output": os.path.abspath(args.output),
            "cropped_box": list(cbox),
            "scaled_content": [nw, nh],
            "output_canvas": [check.w, check.h],
            "resample": method,
        }
    )
    print(json.dumps(rep, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
