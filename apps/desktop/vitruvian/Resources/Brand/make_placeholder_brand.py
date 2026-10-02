#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 VitruvianSoftware

"""Generate Vitruvian's placeholder brand masters.

Upstream's brand artwork (the planet mark, its app icon and its Icon Composer
project) is reserved by its owner and is not licensed under the GPL, so it was
never imported. This draws an original stand-in: the square and circle of the
Vitruvian proportions, bottom-aligned as in Leonardo's drawing. Design should
replace it with real artwork. Keep the file names, which Tools/MakeIcon.swift
and build.sh read.

Writes, next to this script:
  logo.png             1024 px opaque mark on transparent: the menu bar template
                       glyph and BrandMark are cut from it
  AppIcon-Default.png  1024 px app icon (MakeIcon builds the .icns from it)
  AppIcon.icon/        Icon Composer project for the adaptive icon (build.sh's
                       optional actool step); Bazel uses AppIcon-Default.png

Standard library only, deterministic: rerunning reproduces the same bytes.

usage: python3 make_placeholder_brand.py
"""

import json
import math
import struct
import zlib
from pathlib import Path

SIZE = 1024
HERE = Path(__file__).resolve().parent

# The mark, in a 1024 x 1024 design space: a ring and a square outline whose
# bottom edges meet, with the square's side 0.85 of the circle's diameter.
RADIUS = 300.0
STROKE = 64.0
CENTER = (512.0, 452.0)
SIDE = 2 * RADIUS * 0.85
BOTTOM = CENTER[1] + RADIUS
SQUARE_CENTER = (CENTER[0], BOTTOM - SIDE / 2)


def clamp(x, lo=0.0, hi=1.0):
    return lo if x < lo else hi if x > hi else x


def box(px, py, cx, cy, hw, hh, r=0.0):
    """Signed distance to a (rounded) box centred on (cx, cy)."""
    qx = abs(px - cx) - (hw - r)
    qy = abs(py - cy) - (hh - r)
    outside = math.hypot(max(qx, 0.0), max(qy, 0.0))
    return outside + min(max(qx, qy), 0.0) - r


def mark_distance(px, py, scale=1.0, origin=(512.0, 512.0)):
    """Signed distance to the mark, scaled about origin."""
    # Map back into design space.
    x = origin[0] + (px - origin[0]) / scale
    y = origin[1] + (py - origin[1]) / scale
    ring = abs(math.hypot(x - CENTER[0], y - CENTER[1]) - RADIUS) - STROKE / 2
    square = abs(box(x, y, SQUARE_CENTER[0], SQUARE_CENTER[1], SIDE / 2, SIDE / 2)) - STROKE / 2
    return min(ring, square) * scale


def write_png(path, pixels):
    """pixels: list of rows, each a bytearray of RGBA."""
    raw = b"".join(b"\x00" + bytes(row) for row in pixels)

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    header = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0)
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )


def render_logo():
    rows = []
    for j in range(SIZE):
        row = bytearray(SIZE * 4)
        py = j + 0.5
        for i in range(SIZE):
            a = clamp(0.5 - mark_distance(i + 0.5, py))
            if a:
                row[i * 4 + 3] = round(a * 255)
        rows.append(row)
    return rows


def render_icon():
    # macOS icon grid: an 824 pt rounded square inset 100 pt, with a soft shadow.
    half, corner = 412.0, 185.0
    top, bottom = (36, 76, 140), (12, 28, 62)
    rows = []
    for j in range(SIZE):
        row = bytearray(SIZE * 4)
        py = j + 0.5
        t = clamp((py - 100) / 824)
        bg = [top[k] + (bottom[k] - top[k]) * t for k in range(3)]
        for i in range(SIZE):
            px = i + 0.5
            d = box(px, py, 512, 512, half, half, corner)
            shape = clamp(0.5 - d)
            shadow = 0.32 * clamp(1 - max(box(px, py - 10, 512, 512, half, half, corner), 0) / 28)
            mark = clamp(0.5 - mark_distance(px, py, scale=0.62)) * shape
            # Composite: shadow under the shape, then the white mark on top.
            alpha = shape + shadow * (1 - shape)
            if alpha <= 0:
                continue
            colour = [(c * shape) / alpha for c in bg]
            colour = [c * (1 - mark) + 255 * mark for c in colour]
            o = i * 4
            row[o : o + 3] = bytes(round(clamp(c, 0, 255)) for c in colour)
            row[o + 3] = round(alpha * 255)
        rows.append(row)
    return rows


def mark_svg():
    s = STROKE
    x0 = SQUARE_CENTER[0] - SIDE / 2
    y0 = SQUARE_CENTER[1] - SIDE / 2
    # Crop to the mark plus half a stroke so Icon Composer centres it.
    left, right = CENTER[0] - RADIUS - s / 2, CENTER[0] + RADIUS + s / 2
    top, bottom = CENTER[1] - RADIUS - s / 2, BOTTOM + s / 2
    w, h = right - left, bottom - top
    return (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        "<!-- SPDX-License-Identifier: GPL-3.0-or-later -->\n"
        "<!-- Copyright (C) 2026 VitruvianSoftware. Placeholder mark; see make_placeholder_brand.py. -->\n"
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{w:g}" height="{h:g}" '
        f'viewBox="{left:g} {top:g} {w:g} {h:g}">\n'
        f'  <g fill="none" stroke="#000" stroke-width="{s:g}">\n'
        f'    <circle cx="{CENTER[0]:g}" cy="{CENTER[1]:g}" r="{RADIUS:g}"/>\n'
        f'    <rect x="{x0:g}" y="{y0:g}" width="{SIDE:g}" height="{SIDE:g}"/>\n'
        "  </g>\n"
        "</svg>\n"
    )


def icon_composer_project():
    return {
        "fill-specializations": [
            {"value": {"linear-gradient": ["srgb:0.14118,0.29804,0.54902,1.00000", "srgb:0.04706,0.10980,0.24314,1.00000"]}},
        ],
        "groups": [
            {
                "layers": [
                    {
                        "fill": {"solid": "srgb:1.00000,1.00000,1.00000,1.00000"},
                        "image-name": "vitruvian-mark.svg",
                        "name": "VitruvianMark",
                        "position": {"scale": 1.0, "translation-in-points": [0, 0]},
                    }
                ],
                "name": "Mark",
                "shadow": {"kind": "neutral", "opacity": 0.5},
            }
        ],
        "supported-platforms": {"squares": ["macOS"]},
    }


def main():
    write_png(HERE / "logo.png", render_logo())
    write_png(HERE / "AppIcon-Default.png", render_icon())
    project = HERE / "AppIcon.icon"
    (project / "Assets").mkdir(parents=True, exist_ok=True)
    (project / "Assets" / "vitruvian-mark.svg").write_text(mark_svg())
    (project / "icon.json").write_text(json.dumps(icon_composer_project(), indent=2, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()
