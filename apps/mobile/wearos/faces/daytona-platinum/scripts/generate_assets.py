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
"""Generate high-resolution Rolex Cosmograph Daytona Platinum (Ref. 126506) PNG assets."""

import math
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

BUILD_WORKSPACE = os.environ.get("BUILD_WORKSPACE_DIRECTORY")
if BUILD_WORKSPACE:
    PACKAGE_DIR = (
        Path(BUILD_WORKSPACE)
        / "apps"
        / "mobile"
        / "wearos"
        / "faces"
        / "daytona-platinum"
    )
else:
    PACKAGE_DIR = Path(__file__).resolve().parent.parent
DRAWABLE_DIR = str(PACKAGE_DIR / "src" / "main" / "res" / "drawable-nodpi")
SVG_DIR = tempfile.mkdtemp(prefix="daytona_svg_")
os.makedirs(DRAWABLE_DIR, exist_ok=True)


def svg_to_png(
    svg_name: str, png_path: str, width: int = 450, height: int = 450
) -> None:
    svg_path = os.path.join(SVG_DIR, svg_name)
    rsvg = shutil.which("rsvg-convert") or "/opt/homebrew/bin/rsvg-convert"
    subprocess.run(
        [rsvg, "-w", str(width), "-h", str(height), svg_path, "-o", png_path],
        check=True,
    )


def polar(cx: float, cy: float, r: float, angle_deg: float) -> tuple[float, float]:
    rad = math.radians(angle_deg - 90.0)
    return cx + r * math.cos(rad), cy + r * math.sin(rad)


def make_dial_svg(ambient: bool = False, expanded: bool = False) -> str:
    cx, cy = 225.0, 225.0
    elems = []

    elems.append("""<defs>
      <!-- Platinum outer rim metallic gradient -->
      <linearGradient id="platinumRim" x1="0%" y1="0%" x2="100%" y2="100%">
        <stop offset="0%" stop-color="#F5F7FA"/>
        <stop offset="25%" stop-color="#CDD4DC"/>
        <stop offset="50%" stop-color="#FFFFFF"/>
        <stop offset="75%" stop-color="#9BA4B0"/>
        <stop offset="100%" stop-color="#E2E7EC"/>
      </linearGradient>

      <!-- Chestnut Brown Cerachrom Ceramic Bezel Gradient -->
      <linearGradient id="cerachromBezel" x1="15%" y1="5%" x2="85%" y2="95%">
        <stop offset="0%" stop-color="#4E2F21"/>
        <stop offset="28%" stop-color="#381F14"/>
        <stop offset="52%" stop-color="#593626"/>
        <stop offset="78%" stop-color="#2A160D"/>
        <stop offset="100%" stop-color="#3D2216"/>
      </linearGradient>

      <!-- Chestnut Brown Subdial Snailed Ring Gradient -->
      <linearGradient id="chestnutRing" x1="0%" y1="0%" x2="100%" y2="100%">
        <stop offset="0%" stop-color="#4A2B1D"/>
        <stop offset="45%" stop-color="#331B11"/>
        <stop offset="65%" stop-color="#583525"/>
        <stop offset="100%" stop-color="#2B160D"/>
      </linearGradient>

      <!-- Ice Blue Sunray Dial Base -->
      <radialGradient id="iceBlueBase" cx="50%" cy="46%" r="54%">
        <stop offset="0%" stop-color="#D2ECF5"/>
        <stop offset="45%" stop-color="#B3D9E8"/>
        <stop offset="82%" stop-color="#96C5D8"/>
        <stop offset="100%" stop-color="#7BAFC4"/>
      </radialGradient>

      <!-- Sunray Conic-like Sheen Overlay -->
      <linearGradient id="sunrayHighlight1" x1="18%" y1="8%" x2="82%" y2="92%">
        <stop offset="0%" stop-color="#FFFFFF" stop-opacity="0.28"/>
        <stop offset="42%" stop-color="#D8F0F8" stop-opacity="0.06"/>
        <stop offset="50%" stop-color="#FFFFFF" stop-opacity="0.34"/>
        <stop offset="58%" stop-color="#87B8CB" stop-opacity="0.08"/>
        <stop offset="100%" stop-color="#FFFFFF" stop-opacity="0.22"/>
      </linearGradient>

      <linearGradient id="sunrayHighlight2" x1="85%" y1="12%" x2="15%" y2="88%">
        <stop offset="0%" stop-color="#1E3F4F" stop-opacity="0.18"/>
        <stop offset="48%" stop-color="#FFFFFF" stop-opacity="0.14"/>
        <stop offset="52%" stop-color="#1E3F4F" stop-opacity="0.20"/>
        <stop offset="100%" stop-color="#24485A" stop-opacity="0.16"/>
      </linearGradient>

      <!-- Diamond Baguette Facet Gradient -->
      <linearGradient id="diamondFacet" x1="0%" y1="0%" x2="100%" y2="100%">
        <stop offset="0%" stop-color="#FFFFFF"/>
        <stop offset="35%" stop-color="#E6F4FA"/>
        <stop offset="50%" stop-color="#FFFFFF"/>
        <stop offset="70%" stop-color="#B8D2DE"/>
        <stop offset="100%" stop-color="#F7FCFF"/>
      </linearGradient>

      <!-- White Gold Surround Bezel -->
      <linearGradient id="whiteGold" x1="0%" y1="0%" x2="100%" y2="100%">
        <stop offset="0%" stop-color="#F2F5F8"/>
        <stop offset="45%" stop-color="#9AA3AE"/>
        <stop offset="55%" stop-color="#FFFFFF"/>
        <stop offset="100%" stop-color="#6A737D"/>
      </linearGradient>

      <!-- Inner Rehaut Shadow -->
      <radialGradient id="rehautShadow" cx="50%" cy="50%" r="50%">
        <stop offset="86%" stop-color="#000000" stop-opacity="0.0"/>
        <stop offset="95%" stop-color="#0E1D26" stop-opacity="0.22"/>
        <stop offset="100%" stop-color="#071117" stop-opacity="0.58"/>
      </radialGradient>

      <!-- Curved path for red DAYTONA arc above 6 o'clock subdial (center 225,314, r=53) -->
      <path id="daytonaArc" d="M 176,262 A 53,53 0 0,1 274,262" />
      <!-- Curved path for UNITS PER HOUR at 1 o'clock on Cerachrom bezel -->
      <path id="unitsArc" d="M 275,32 A 202,202 0 0,1 356,74" />
    </defs>""")

    dial_r = 220.5 if expanded else 184.0
    track_r_out = 216.5 if expanded else 181.0
    track_r_in_sec = 209.0 if expanded else 173.5
    track_r_in_five = 207.0 if expanded else 171.5
    track_r_in_sub = 212.0 if expanded else 176.5

    if not ambient:
        # 1. Outer 950 Platinum case lip
        elems.append(f'<circle cx="{cx}" cy="{cy}" r="225" fill="url(#platinumRim)"/>')
        elems.append(f'<circle cx="{cx}" cy="{cy}" r="222.5" fill="#1C100B"/>')

        if not expanded:
            # 2. Chestnut Brown Cerachrom Tachymeter Bezel (r=186 to 222)
            elems.append(
                f'<circle cx="{cx}" cy="{cy}" r="221.5" fill="url(#cerachromBezel)"/>'
            )
            elems.append(
                f'<circle cx="{cx}" cy="{cy}" r="220.5" fill="none" stroke="#7A523E" stroke-width="0.8" stroke-opacity="0.55"/>'
            )

            tachy_marks = [
                (54.0, "400"),
                (72.0, "300"),
                (90.0, "240"),
                (108.0, "200"),
                (120.0, "180"),
                (135.0, "160"),
                (154.3, "140"),
                (166.2, "130"),
                (180.0, "120"),
                (196.4, "110"),
                (216.0, "100"),
                (240.0, "90"),
                (254.1, "85"),
                (270.0, "80"),
                (288.0, "75"),
                (308.6, "70"),
                (332.3, "65"),
                (348.0, "60"),
            ]

            for idx, ch in enumerate("UNITS PER HOUR"):
                ang = 17.5 + idx * 1.95
                ux, uy = polar(cx, cy, 204.5, ang)
                elems.append(
                    f'<text x="{ux:.2f}" y="{uy:.2f}" fill="#E8EEF2" font-family="Helvetica Neue, Arial, sans-serif" '
                    f'font-size="6.4" font-weight="700" text-anchor="middle" dominant-baseline="central" '
                    f'transform="rotate({ang:.1f} {ux:.2f} {uy:.2f})">{ch}</text>'
                )

            for deg in range(56, 348, 4):
                if any(abs(deg - a) < 2.2 for a, _ in tachy_marks):
                    continue
                x1, y1 = polar(cx, cy, 188.0, deg)
                x2, y2 = polar(cx, cy, 192.0, deg)
                elems.append(
                    f'<line x1="{x1:.2f}" y1="{y1:.2f}" x2="{x2:.2f}" y2="{y2:.2f}" stroke="#D8DFE5" stroke-width="1.0" stroke-opacity="0.65"/>'
                )

            for angle, label in tachy_marks:
                dx, dy = polar(cx, cy, 191.5, angle)
                elems.append(
                    f'<circle cx="{dx:.2f}" cy="{dy:.2f}" r="1.7" fill="#E8EEF2"/>'
                )
                tx, ty = polar(cx, cy, 204.5, angle)
                rot = angle if (angle <= 95 or angle >= 265) else angle + 180
                elems.append(
                    f'<text x="{tx:.2f}" y="{ty:.2f}" fill="#E8EEF2" font-family="Helvetica Neue, Arial, sans-serif" '
                    f'font-size="8.8" font-weight="700" text-anchor="middle" dominant-baseline="central" '
                    f'transform="rotate({rot:.1f} {tx:.2f} {ty:.2f})">{label}</text>'
                )

            elems.append(
                '<polygon points="225,189.5 220.2,199 229.8,199" fill="#E8EEF2"/>'
            )

            elems.append(
                f'<circle cx="{cx}" cy="{cy}" r="186.5" fill="url(#platinumRim)"/>'
            )

        elems.append(
            f'<circle cx="{cx}" cy="{cy}" r="{dial_r}" fill="url(#iceBlueBase)"/>'
        )
        elems.append(
            f'<circle cx="{cx}" cy="{cy}" r="{dial_r}" fill="url(#sunrayHighlight1)"/>'
        )
        elems.append(
            f'<circle cx="{cx}" cy="{cy}" r="{dial_r}" fill="url(#sunrayHighlight2)"/>'
        )

        for i in range(0, 360, 2):
            x2, y2 = polar(cx, cy, dial_r, i)
            op = 0.045 if (i % 4 == 0) else 0.025
            col = "#FFFFFF" if (i % 4 == 0) else "#2B5669"
            elems.append(
                f'<line x1="{cx}" y1="{cy}" x2="{x2:.2f}" y2="{y2:.2f}" stroke="{col}" stroke-width="0.7" stroke-opacity="{op}"/>'
            )

        elems.append(
            f'<circle cx="{cx}" cy="{cy}" r="{dial_r}" fill="url(#rehautShadow)"/>'
        )
    else:
        elems.append(f'<circle cx="{cx}" cy="{cy}" r="224" fill="#000000"/>')
        if not expanded:
            elems.append(
                f'<circle cx="{cx}" cy="{cy}" r="220" fill="none" stroke="#3A2218" stroke-width="2.0" stroke-opacity="0.7"/>'
            )
        elems.append(
            f'<circle cx="{cx}" cy="{cy}" r="{dial_r + 1.0}" fill="#050B0E" stroke="#4A5A64" stroke-width="1.2" stroke-opacity="0.6"/>'
        )

    # 3. Outer Railway Minute & 1/5th-Second Chronograph Track
    track_col = "#361D12" if not ambient else "#557A89"
    elems.append(
        f'<circle cx="{cx}" cy="{cy}" r="{track_r_out}" fill="none" stroke="{track_col}" stroke-width="0.9" stroke-opacity="0.85"/>'
    )
    elems.append(
        f'<circle cx="{cx}" cy="{cy}" r="{track_r_in_sec}" fill="none" stroke="{track_col}" stroke-width="0.7" stroke-opacity="0.75"/>'
    )

    for step in range(300):
        angle = step * 1.2
        is_five = step % 25 == 0
        is_sec = step % 5 == 0
        r_out = track_r_out
        r_in = (
            track_r_in_five
            if is_five
            else (track_r_in_sec if is_sec else track_r_in_sub)
        )
        sw = 1.6 if is_five else (1.0 if is_sec else 0.55)
        x1, y1 = polar(cx, cy, r_in, angle)
        x2, y2 = polar(cx, cy, r_out, angle)
        elems.append(
            f'<line x1="{x1:.2f}" y1="{y1:.2f}" x2="{x2:.2f}" y2="{y2:.2f}" stroke="{track_col}" stroke-width="{sw}"/>'
        )

    # 4. Applied Baguette Diamond / Chromalight Hour Markers (1..11)
    for hr in range(1, 12):
        angle = hr * 30.0
        is_subdial_hr = hr in (3, 6, 9)
        if expanded:
            length = 14.0 if is_subdial_hr else 22.0
            width = 7.6 if not is_subdial_hr else 6.8
            r_center = 196.0 if is_subdial_hr else 190.0
        else:
            length = 10.0 if is_subdial_hr else 19.5
            width = 7.0 if not is_subdial_hr else 6.2
            r_center = 165.0 if is_subdial_hr else 156.5
        hx, hy = polar(cx, cy, r_center, angle)
        lume_col = "#7CE8FF" if ambient else "url(#diamondFacet)"
        border_col = "#3A6073" if ambient else "url(#whiteGold)"
        elems.append(
            f'<g transform="translate({hx:.2f},{hy:.2f}) rotate({angle:.1f})">'
            f'<rect x="{-width / 2 - 1.1:.2f}" y="{-length / 2 - 1.1:.2f}" width="{width + 2.2:.2f}" height="{length + 2.2:.2f}" rx="1.2" fill="#1C2D36" fill-opacity="0.45"/>'
            f'<rect x="{-width / 2:.2f}" y="{-length / 2:.2f}" width="{width:.2f}" height="{length:.2f}" rx="0.9" fill="{border_col}"/>'
            f'<rect x="{-width / 2 + 1.3:.2f}" y="{-length / 2 + 1.3:.2f}" width="{width - 2.6:.2f}" height="{length - 2.6:.2f}" rx="0.4" fill="{lume_col}"/>'
            f'<line x1="{-width / 2 + 1.3:.2f}" y1="0" x2="{width / 2 - 1.3:.2f}" y2="0" stroke="#99BCCB" stroke-width="0.6" stroke-opacity="0.7"/>'
            f"</g>"
        )

    # 5. Applied 12 o'clock Rolex 5-Pointed Coronet & Dial Signature
    coronet_fill = "#F4F7FA" if not ambient else "#8CA4B0"
    coronet_stroke = "#2A363E" if not ambient else "#3A4E59"
    coronet_y = 58 if expanded else 84
    sig_offset = -20 if expanded else 0
    elems.append(f"""
    <g transform="translate(225, {coronet_y})">
      <ellipse cx="0" cy="10.5" rx="9.2" ry="2.7" fill="none" stroke="{coronet_fill}" stroke-width="1.8"/>
      <ellipse cx="0" cy="10.5" rx="9.2" ry="2.7" fill="none" stroke="{coronet_stroke}" stroke-width="0.5"/>
      <path d="M -9.2,8.5 L -12.5,-4.5 L -6.0,4.5 L -5.5,-9.5 L 0,3.5 L 5.5,-9.5 L 6.0,4.5 L 12.5,-4.5 L 9.2,8.5 Z"
            fill="{coronet_fill}" stroke="{coronet_stroke}" stroke-width="0.7" stroke-linejoin="round"/>
      <circle cx="-13.0" cy="-6.2" r="1.8" fill="{coronet_fill}" stroke="{coronet_stroke}" stroke-width="0.5"/>
      <circle cx="-6.0" cy="-11.5" r="2.0" fill="{coronet_fill}" stroke="{coronet_stroke}" stroke-width="0.5"/>
      <circle cx="0.0" cy="-13.5" r="2.2" fill="{coronet_fill}" stroke="{coronet_stroke}" stroke-width="0.5"/>
      <circle cx="6.0" cy="-11.5" r="2.0" fill="{coronet_fill}" stroke="{coronet_stroke}" stroke-width="0.5"/>
      <circle cx="13.0" cy="-6.2" r="1.8" fill="{coronet_fill}" stroke="{coronet_stroke}" stroke-width="0.5"/>
    </g>""")

    text_col = "#24140C" if not ambient else "#8FA8B5"
    if not ambient:
        elems.append(f"""
        <text x="225" y="{113.5 + sig_offset}" fill="{text_col}" font-family="Georgia, 'Times New Roman', serif" font-size="{14.4 if expanded else 13.2}" font-weight="700" letter-spacing="2.2" text-anchor="middle">ROLEX</text>
        <text x="225" y="{123.5 + sig_offset}" fill="{text_col}" font-family="Helvetica Neue, Arial, sans-serif" font-size="{6.8 if expanded else 6.2}" font-weight="700" letter-spacing="0.9" text-anchor="middle">OYSTER PERPETUAL</text>
        <text x="225" y="{132.0 + sig_offset}" fill="{text_col}" font-family="Helvetica Neue, Arial, sans-serif" font-size="{6.2 if expanded else 5.8}" font-weight="600" letter-spacing="0.6" text-anchor="middle">SUPERLATIVE CHRONOMETER</text>
        <text x="225" y="{139.8 + sig_offset}" fill="{text_col}" font-family="Helvetica Neue, Arial, sans-serif" font-size="{6.0 if expanded else 5.6}" font-weight="600" letter-spacing="0.7" text-anchor="middle">OFFICIALLY CERTIFIED</text>
        <text x="225" y="{148.5 + sig_offset}" fill="{text_col}" font-family="Helvetica Neue, Arial, sans-serif" font-size="{7.6 if expanded else 7.0}" font-weight="700" letter-spacing="1.4" text-anchor="middle">COSMOGRAPH</text>
        """)
    else:
        elems.append(f"""
        <text x="225" y="{114 + sig_offset}" fill="{text_col}" font-family="Georgia, 'Times New Roman', serif" font-size="{14.4 if expanded else 13.2}" font-weight="700" letter-spacing="2.2" text-anchor="middle">ROLEX</text>
        <text x="225" y="{126 + sig_offset}" fill="{text_col}" font-family="Helvetica Neue, Arial, sans-serif" font-size="{7.4 if expanded else 6.8}" font-weight="700" letter-spacing="1.2" text-anchor="middle">COSMOGRAPH</text>
        """)

    # 6. Three Snailed Chestnut-Brown Subdial Rings (9 o'clock, 3 o'clock, 6 o'clock)
    if expanded:
        subdials = [
            (
                112.0,
                220.0,
                ["60", "20", "40"],
                "LEFT",
            ),  # Expanded 9 o'clock register (r_outer=60, r_inner=44)
            (
                338.0,
                220.0,
                ["30", "10", "20"],
                "RIGHT",
            ),  # Expanded 3 o'clock register (r_outer=60, r_inner=44)
            (
                225.0,
                326.0,
                ["60", "20", "40"],
                "BOTTOM",
            ),  # Expanded 6 o'clock register (r_outer=60, r_inner=44)
        ]
    else:
        subdials = [
            (
                130.0,
                225.0,
                ["60", "20", "40"],
                "LEFT",
            ),  # Standard 9 o'clock register (r_outer=44.5, r_inner=31)
            (
                320.0,
                225.0,
                ["30", "10", "20"],
                "RIGHT",
            ),  # Standard 3 o'clock register (r_outer=44.5, r_inner=31)
            (
                225.0,
                314.0,
                ["60", "20", "40"],
                "BOTTOM",
            ),  # Standard 6 o'clock register (r_outer=44.5, r_inner=31)
        ]

    daytona_red = "#C81D25" if not ambient else "#9E2A2F"
    bottom_cy = 326.0 if expanded else 314.0
    daytona_r = 68.0 if expanded else 52.0
    for idx, ch in enumerate("DAYTONA"):
        ang = -24.0 + idx * 8.0
        dx, dy = polar(225.0, bottom_cy, daytona_r, ang)
        elems.append(
            f'<text x="{dx:.2f}" y="{dy:.2f}" fill="{daytona_red}" font-family="Helvetica Neue, Arial, sans-serif" '
            f'font-size="{9.8 if expanded else 8.2}" font-weight="800" text-anchor="middle" dominant-baseline="central" '
            f'transform="rotate({ang:.1f} {dx:.2f} {dy:.2f})">{ch}</text>'
        )

    for scx, scy, labels, pos in subdials:
        outer_r = 60.0 if expanded else 44.5
        inner_r = 44.0 if expanded else 31.0
        mid_r = (outer_r + inner_r) / 2.0

        if not ambient:
            elems.append(
                f'<circle cx="{scx}" cy="{scy}" r="{outer_r + 1.5}" fill="url(#platinumRim)"/>'
            )
            elems.append(
                f'<circle cx="{scx}" cy="{scy}" r="{outer_r}" fill="url(#chestnutRing)"/>'
            )
            snail_steps = 7 if expanded else 5
            for step_i in range(1, snail_steps):
                sr = outer_r - step_i * 2.2
                elems.append(
                    f'<circle cx="{scx}" cy="{scy}" r="{sr:.1f}" fill="none" stroke="#221008" stroke-width="0.45" stroke-opacity="0.6"/>'
                )
            elems.append(
                f'<circle cx="{scx}" cy="{scy}" r="{inner_r + 1.2}" fill="url(#platinumRim)"/>'
            )
            elems.append(
                f'<circle cx="{scx}" cy="{scy}" r="{inner_r}" fill="url(#iceBlueBase)"/>'
            )
            elems.append(
                f'<circle cx="{scx}" cy="{scy}" r="{inner_r}" fill="url(#sunrayHighlight1)"/>'
            )
        else:
            elems.append(
                f'<circle cx="{scx}" cy="{scy}" r="{outer_r}" fill="#170E0A" stroke="#5A3A2B" stroke-width="1.2"/>'
            )
            elems.append(
                f'<circle cx="{scx}" cy="{scy}" r="{inner_r}" fill="#050B0E" stroke="#3B525E" stroke-width="0.9"/>'
            )

        for t in range(12):
            ang = t * 30.0
            if t % 4 == 0:
                continue
            tx1, ty1 = polar(scx, scy, outer_r - 1.0, ang)
            tx2, ty2 = polar(scx, scy, outer_r - (5.5 if expanded else 4.5), ang)
            elems.append(
                f'<line x1="{tx1:.2f}" y1="{ty1:.2f}" x2="{tx2:.2f}" y2="{ty2:.2f}" stroke="#E8EEF2" stroke-width="{1.15 if expanded else 0.95}" stroke-opacity="0.85"/>'
            )

        for ang, num in zip((0.0, 120.0, 240.0), labels):
            nx, ny = polar(scx, scy, mid_r, ang)
            elems.append(
                f'<text x="{nx:.2f}" y="{ny:.2f}" fill="#F2F6F9" font-family="Helvetica Neue, Arial, sans-serif" '
                f'font-size="{9.8 if expanded else 7.4}" font-weight="700" text-anchor="middle" dominant-baseline="central">{num}</text>'
            )

    # 7. Clean, Non-Overlapping Recessed Apertures for World Clock, Sunrise, and Date
    if not ambient:
        cap_y = 150 if expanded else 166
        cap_w = 114 if expanded else 96
        cap_h = 24 if expanded else 18
        solar_cx = 124 if expanded else 138
        solar_cy = 320 if expanded else 294
        solar_w = 60 if expanded else 52
        solar_h = 24 if expanded else 20
        date_cx = 326 if expanded else 312
        date_cy = 320 if expanded else 294
        date_w = 58 if expanded else 50
        date_h = 24 if expanded else 21
        date_in_w = 53 if expanded else 45
        date_in_h = 19.4 if expanded else 16.4
        swiss_y = 403 if expanded else 381
        elems.append(f"""
        <!-- Top GMT / World Clock curved capsule under COSMOGRAPH -->
        <g transform="translate(225, {cap_y})">
          <rect x="{-cap_w / 2}" y="{-cap_h / 2}" width="{cap_w}" height="{cap_h}" rx="{cap_h / 2}" fill="#2A160D" fill-opacity="0.90" stroke="url(#platinumRim)" stroke-width="0.9"/>
        </g>
        <!-- Left 7:30 Sunrise/Solar capsule (cleanly outside both 9 and 6 subdials) -->
        <g transform="translate({solar_cx}, {solar_cy})">
          <rect x="{-solar_w / 2}" y="{-solar_h / 2}" width="{solar_w}" height="{solar_h}" rx="{solar_h / 2}" fill="#2A160D" fill-opacity="0.90" stroke="url(#platinumRim)" stroke-width="0.9"/>
        </g>
        <!-- Right 4:30 Platinum Cyclops Date window (cleanly outside both 3 and 6 subdials) -->
        <g transform="translate({date_cx}, {date_cy})">
          <rect x="{-date_w / 2}" y="{-date_h / 2}" width="{date_w}" height="{date_h}" rx="4" fill="url(#platinumRim)" stroke="#24140C" stroke-width="0.7"/>
          <rect x="{-date_in_w / 2}" y="{-date_in_h / 2}" width="{date_in_w}" height="{date_in_h}" rx="2.5" fill="#F4F8FA"/>
        </g>
        """)
        elems.append(
            f'<text x="225" y="{swiss_y}" fill="#24140C" font-family="Helvetica Neue, Arial, sans-serif" '
            'font-size="5.8" font-weight="700" letter-spacing="1.2" text-anchor="middle">SWISS  ♛  MADE</text>'
        )

    return f'<svg xmlns="http://www.w3.org/2000/svg" width="450" height="450" viewBox="0 0 450 450">{"".join(elems)}</svg>'


def make_hour_hand_svg(ambient: bool = False) -> str:
    lume = "#7CE8FF" if ambient else "#F7FBFF"
    metal_left = "#E8EEF2" if not ambient else "#9BB0BC"
    metal_right = "#8E99A4" if not ambient else "#5A6D78"
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="450" height="450" viewBox="0 0 450 450">
      <defs>
        <filter id="handShadow" x="-20%" y="-20%" width="140%" height="140%">
          <feDropShadow dx="1.5" dy="2.5" stdDeviation="2.2" flood-color="#000000" flood-opacity="0.45"/>
        </filter>
      </defs>
      <g filter="{"none" if ambient else "url(#handShadow)"}">
        <polygon points="225,252 219.5,244 221,225 225,225" fill="{metal_left}"/>
        <polygon points="225,252 230.5,244 229,225 225,225" fill="{metal_right}"/>
        <polygon points="225,114 218.5,126 219.5,225 225,225" fill="{metal_left}"/>
        <polygon points="225,114 231.5,126 230.5,225 225,225" fill="{metal_right}"/>
        <rect x="222.0" y="130" width="6.0" height="78" rx="1.2" fill="{lume}"/>
        <circle cx="225" cy="225" r="10.5" fill="{metal_left}" stroke="#4A555E" stroke-width="1.0"/>
      </g>
    </svg>"""


def make_minute_hand_svg(ambient: bool = False) -> str:
    lume = "#7CE8FF" if ambient else "#F7FBFF"
    metal_left = "#F0F4F8" if not ambient else "#A7BCC8"
    metal_right = "#838E99" if not ambient else "#566873"
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="450" height="450" viewBox="0 0 450 450">
      <defs>
        <filter id="minShadow" x="-20%" y="-20%" width="140%" height="140%">
          <feDropShadow dx="2.0" dy="3.0" stdDeviation="2.5" flood-color="#000000" flood-opacity="0.48"/>
        </filter>
      </defs>
      <g filter="{"none" if ambient else "url(#minShadow)"}">
        <polygon points="225,258 220.2,248 221.5,225 225,225" fill="{metal_left}"/>
        <polygon points="225,258 229.8,248 228.5,225 225,225" fill="{metal_right}"/>
        <polygon points="225,60 220.0,76 220.8,225 225,225" fill="{metal_left}"/>
        <polygon points="225,60 230.0,76 229.2,225 225,225" fill="{metal_right}"/>
        <rect x="222.4" y="78" width="5.2" height="128" rx="1.2" fill="{lume}"/>
        <circle cx="225" cy="225" r="8.5" fill="{metal_left}" stroke="#3F4850" stroke-width="1.0"/>
      </g>
    </svg>"""


def make_second_hand_svg() -> str:
    return """<svg xmlns="http://www.w3.org/2000/svg" width="450" height="450" viewBox="0 0 450 450">
      <defs>
        <filter id="secShadow" x="-20%" y="-20%" width="140%" height="140%">
          <feDropShadow dx="1.5" dy="2.5" stdDeviation="1.8" flood-color="#000000" flood-opacity="0.40"/>
        </filter>
      </defs>
      <g filter="url(#secShadow)">
        <polygon points="225,274 220.5,260 225,246 229.5,260" fill="none" stroke="#E8EEF2" stroke-width="1.8"/>
        <line x1="225" y1="246" x2="225" y2="50" stroke="#E8EEF2" stroke-width="1.8"/>
        <polygon points="225,46 221.8,58 228.2,58" fill="#C81D25"/>
        <circle cx="225" cy="225" r="5.5" fill="#E8EEF2" stroke="#5A6570" stroke-width="1.0"/>
        <circle cx="225" cy="225" r="2.0" fill="#9AA4AE"/>
      </g>
    </svg>"""


def make_subdial_hand_svg() -> str:
    """88x88 subdial needle centered at (44, 44) pointing up to (44, 10)."""
    return """<svg xmlns="http://www.w3.org/2000/svg" width="88" height="88" viewBox="0 0 88 88">
      <defs>
        <filter id="subShadow" x="-20%" y="-20%" width="140%" height="140%">
          <feDropShadow dx="0.8" dy="1.2" stdDeviation="1.0" flood-color="#000000" flood-opacity="0.40"/>
        </filter>
      </defs>
      <g filter="url(#subShadow)">
        <polygon points="44,10 41.8,18 42.6,51 45.4,51 46.2,18" fill="#F2F6FA" stroke="#361D12" stroke-width="0.5"/>
        <circle cx="44" cy="44" r="3.8" fill="#E4EBF0" stroke="#2B160D" stroke-width="0.8"/>
        <circle cx="44" cy="44" r="1.4" fill="#7C8792"/>
      </g>
    </svg>"""


def make_subdial_hand_expanded_svg() -> str:
    """120x120 expanded subdial needle centered at (60, 60) pointing up to (60, 12)."""
    return """<svg xmlns="http://www.w3.org/2000/svg" width="120" height="120" viewBox="0 0 120 120">
      <defs>
        <filter id="subShadowExp" x="-20%" y="-20%" width="140%" height="140%">
          <feDropShadow dx="1.0" dy="1.5" stdDeviation="1.2" flood-color="#000000" flood-opacity="0.42"/>
        </filter>
      </defs>
      <g filter="url(#subShadowExp)">
        <polygon points="60,12 57.0,23 58.1,70 61.9,70 63.0,23" fill="#F2F6FA" stroke="#361D12" stroke-width="0.65"/>
        <circle cx="60" cy="60" r="5.0" fill="#E4EBF0" stroke="#2B160D" stroke-width="1.0"/>
        <circle cx="60" cy="60" r="1.9" fill="#7C8792"/>
      </g>
    </svg>"""


def make_preview_svg() -> str:
    base = make_dial_svg(ambient=False).replace("</svg>", "")
    extra = """
      <!-- Preview sample complication text inside the subdials and apertures -->
      <text x="225" y="166.5" fill="#E8EEF2" font-family="Helvetica Neue, Arial, sans-serif" font-size="9.0" font-weight="700" text-anchor="middle" dominant-baseline="central">AMS 15:10</text>
      <text x="130" y="218" fill="#24140C" font-family="Helvetica Neue, Arial, sans-serif" font-size="12.5" font-weight="800" text-anchor="middle">75</text>
      <text x="130" y="230" fill="#C81D25" font-family="Helvetica Neue, Arial, sans-serif" font-size="7.0" font-weight="800" text-anchor="middle">♥ 83%</text>
      <text x="320" y="218" fill="#24140C" font-family="Helvetica Neue, Arial, sans-serif" font-size="12.5" font-weight="800" text-anchor="middle">56°</text>
      <text x="320" y="230" fill="#381F14" font-family="Helvetica Neue, Arial, sans-serif" font-size="6.8" font-weight="700" text-anchor="middle">WEATHER</text>
      <text x="225" y="308" fill="#24140C" font-family="Helvetica Neue, Arial, sans-serif" font-size="12.0" font-weight="800" text-anchor="middle">8,420</text>
      <text x="225" y="320" fill="#381F14" font-family="Helvetica Neue, Arial, sans-serif" font-size="6.8" font-weight="700" text-anchor="middle">STEPS</text>
      <text x="138" y="294.5" fill="#E8EEF2" font-family="Helvetica Neue, Arial, sans-serif" font-size="8.2" font-weight="700" text-anchor="middle" dominant-baseline="central">☀ 7:03A</text>
      <text x="312" y="294.5" fill="#24140C" font-family="Helvetica Neue, Arial, sans-serif" font-size="9.0" font-weight="800" text-anchor="middle" dominant-baseline="central">SAT 24</text>
      <g transform="rotate(305 225 225)">
        <polygon points="225,114 218.5,126 219.5,248 230.5,248 231.5,126" fill="#E8EEF2" stroke="#4A555E" stroke-width="0.8"/>
        <rect x="222.0" y="130" width="6.0" height="78" rx="1.2" fill="#FFFFFF"/>
      </g>
      <g transform="rotate(60 225 225)">
        <polygon points="225,60 220.0,76 220.8,254 229.2,254 230.0,76" fill="#F0F4F8" stroke="#3F4850" stroke-width="0.8"/>
        <rect x="222.4" y="78" width="5.2" height="128" rx="1.2" fill="#FFFFFF"/>
      </g>
      <g transform="rotate(186 225 225)">
        <line x1="225" y1="265" x2="225" y2="50" stroke="#E8EEF2" stroke-width="1.8"/>
        <polygon points="225,46 221.8,58 228.2,58" fill="#C81D25"/>
        <circle cx="225" cy="225" r="6" fill="#E8EEF2" stroke="#3F4850" stroke-width="1.0"/>
      </g>
    </svg>"""
    return base + extra


with open(os.path.join(SVG_DIR, "dial_interactive.svg"), "w") as f:
    f.write(make_dial_svg(ambient=False, expanded=False))
with open(os.path.join(SVG_DIR, "dial_ambient.svg"), "w") as f:
    f.write(make_dial_svg(ambient=True, expanded=False))
with open(os.path.join(SVG_DIR, "dial_expanded_interactive.svg"), "w") as f:
    f.write(make_dial_svg(ambient=False, expanded=True))
with open(os.path.join(SVG_DIR, "dial_expanded_ambient.svg"), "w") as f:
    f.write(make_dial_svg(ambient=True, expanded=True))
with open(os.path.join(SVG_DIR, "hand_hour.svg"), "w") as f:
    f.write(make_hour_hand_svg(ambient=False))
with open(os.path.join(SVG_DIR, "hand_hour_aod.svg"), "w") as f:
    f.write(make_hour_hand_svg(ambient=True))
with open(os.path.join(SVG_DIR, "hand_minute.svg"), "w") as f:
    f.write(make_minute_hand_svg(ambient=False))
with open(os.path.join(SVG_DIR, "hand_minute_aod.svg"), "w") as f:
    f.write(make_minute_hand_svg(ambient=True))
with open(os.path.join(SVG_DIR, "hand_second.svg"), "w") as f:
    f.write(make_second_hand_svg())
with open(os.path.join(SVG_DIR, "subdial_hand.svg"), "w") as f:
    f.write(make_subdial_hand_svg())
with open(os.path.join(SVG_DIR, "subdial_hand_expanded.svg"), "w") as f:
    f.write(make_subdial_hand_expanded_svg())
with open(os.path.join(SVG_DIR, "preview.svg"), "w") as f:
    f.write(make_preview_svg())

svg_to_png(
    "dial_interactive.svg", os.path.join(DRAWABLE_DIR, "dial_interactive.png"), 450, 450
)
svg_to_png("dial_ambient.svg", os.path.join(DRAWABLE_DIR, "dial_ambient.png"), 450, 450)
svg_to_png(
    "dial_expanded_interactive.svg",
    os.path.join(DRAWABLE_DIR, "dial_expanded_interactive.png"),
    450,
    450,
)
svg_to_png(
    "dial_expanded_ambient.svg",
    os.path.join(DRAWABLE_DIR, "dial_expanded_ambient.png"),
    450,
    450,
)
svg_to_png("hand_hour.svg", os.path.join(DRAWABLE_DIR, "hand_hour.png"), 450, 450)
svg_to_png(
    "hand_hour_aod.svg", os.path.join(DRAWABLE_DIR, "hand_hour_aod.png"), 450, 450
)
svg_to_png("hand_minute.svg", os.path.join(DRAWABLE_DIR, "hand_minute.png"), 450, 450)
svg_to_png(
    "hand_minute_aod.svg", os.path.join(DRAWABLE_DIR, "hand_minute_aod.png"), 450, 450
)
svg_to_png("hand_second.svg", os.path.join(DRAWABLE_DIR, "hand_second.png"), 450, 450)
svg_to_png("subdial_hand.svg", os.path.join(DRAWABLE_DIR, "subdial_hand.png"), 88, 88)
svg_to_png(
    "subdial_hand_expanded.svg",
    os.path.join(DRAWABLE_DIR, "subdial_hand_expanded.png"),
    120,
    120,
)
svg_to_png("preview.svg", os.path.join(DRAWABLE_DIR, "preview.png"), 450, 450)
svg_to_png("preview.svg", os.path.join(DRAWABLE_DIR, "preview_circular.png"), 450, 450)

print("Re-rendered refined Daytona PNG assets successfully.")
