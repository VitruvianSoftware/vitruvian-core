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
"""Generate high-resolution Rolex Cosmograph Daytona PNG assets across 4 reference themes and true-black OLED AOD."""

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


THEMES = {
    "platinum": {
        "bezel_stops": ("#4E2F21", "#381F14", "#593626", "#2A160D", "#3D2216"),
        "ring_stops": ("#4A2B1D", "#331B11", "#583525", "#2B160D"),
        "dial_stops": ("#D2ECF5", "#B3D9E8", "#96C5D8", "#7BAFC4"),
        "subdial_stops": ("#D2ECF5", "#B3D9E8", "#96C5D8", "#7BAFC4"),
        "track_col": "#361D12",
        "text_col": "#24140C",
        "capsule_fill": "#2A160D",
        "daytona_red": "#C81D25",
        "paul_newman": False,
        "red_100": False,
    },
    "panda": {
        "bezel_stops": ("#2B3036", "#16191D", "#32383F", "#0D0F12", "#1C2024"),
        "ring_stops": ("#262A30", "#14171A", "#2E333A", "#0E1013"),
        "dial_stops": ("#FFFFFF", "#F6F9FB", "#EAEFF3", "#DCE4EA"),
        "subdial_stops": ("#FFFFFF", "#F6F9FB", "#EAEFF3", "#DCE4EA"),
        "track_col": "#181C20",
        "text_col": "#14181C",
        "capsule_fill": "#161A1E",
        "daytona_red": "#D41920",
        "paul_newman": False,
        "red_100": False,
    },
    "reverse_panda": {
        "bezel_stops": ("#2B3036", "#16191D", "#32383F", "#0D0F12", "#1C2024"),
        "ring_stops": ("#68737E", "#3E464E", "#7C8894", "#2B3137"),
        "dial_stops": ("#2A3036", "#1A1E22", "#111417", "#090B0D"),
        "subdial_stops": ("#F5F8FA", "#E4EBF0", "#D4DEE6", "#C2CFD9"),
        "track_col": "#DCE4EC",
        "text_col": "#EEF3F7",
        "capsule_fill": "#1A2026",
        "daytona_red": "#E62229",
        "paul_newman": False,
        "red_100": False,
    },
    "lemans": {
        "bezel_stops": ("#282626", "#151414", "#302D2D", "#0C0B0B", "#1C1A1A"),
        "ring_stops": ("#362822", "#1E1612", "#42312A", "#140E0B"),
        "dial_stops": ("#2B2928", "#1B1918", "#121010", "#0A0909"),
        "subdial_stops": ("#FCF8F0", "#F3EDE0", "#E7DFCE", "#D8CEB8"),
        "track_col": "#F0ECE1",
        "text_col": "#F5F2EB",
        "capsule_fill": "#1F1714",
        "daytona_red": "#E62229",
        "paul_newman": True,
        "red_100": True,
    },
}


def make_dial_svg(
    ambient: bool = False,
    expanded: bool = False,
    theme_key: str = "platinum",
    ultra_aod: bool = False,
) -> str:
    cx, cy = 225.0, 225.0
    theme = THEMES[theme_key]
    b0, b1, b2, b3, b4 = theme["bezel_stops"]
    r0, r1, r2, r3 = theme["ring_stops"]
    d0, d1, d2, d3 = theme["dial_stops"]
    s0, s1, s2, s3 = theme["subdial_stops"]

    elems = []
    elems.append(f"""<defs>
      <!-- Platinum outer rim metallic gradient -->
      <linearGradient id="platinumRim" x1="0%" y1="0%" x2="100%" y2="100%">
        <stop offset="0%" stop-color="#F5F7FA"/>
        <stop offset="25%" stop-color="#CDD4DC"/>
        <stop offset="50%" stop-color="#FFFFFF"/>
        <stop offset="75%" stop-color="#9BA4B0"/>
        <stop offset="100%" stop-color="#E2E7EC"/>
      </linearGradient>

      <!-- Cerachrom Ceramic Bezel Gradient -->
      <linearGradient id="cerachromBezel" x1="15%" y1="5%" x2="85%" y2="95%">
        <stop offset="0%" stop-color="{b0}"/>
        <stop offset="28%" stop-color="{b1}"/>
        <stop offset="52%" stop-color="{b2}"/>
        <stop offset="78%" stop-color="{b3}"/>
        <stop offset="100%" stop-color="{b4}"/>
      </linearGradient>

      <!-- Subdial Snailed Ring Gradient -->
      <linearGradient id="chestnutRing" x1="0%" y1="0%" x2="100%" y2="100%">
        <stop offset="0%" stop-color="{r0}"/>
        <stop offset="45%" stop-color="{r1}"/>
        <stop offset="65%" stop-color="{r2}"/>
        <stop offset="100%" stop-color="{r3}"/>
      </linearGradient>

      <!-- Main Sunray Dial Base -->
      <radialGradient id="iceBlueBase" cx="50%" cy="46%" r="54%">
        <stop offset="0%" stop-color="{d0}"/>
        <stop offset="45%" stop-color="{d1}"/>
        <stop offset="82%" stop-color="{d2}"/>
        <stop offset="100%" stop-color="{d3}"/>
      </radialGradient>

      <!-- Subdial Center Disc Base -->
      <radialGradient id="subdialCenterBase" cx="50%" cy="46%" r="54%">
        <stop offset="0%" stop-color="{s0}"/>
        <stop offset="45%" stop-color="{s1}"/>
        <stop offset="82%" stop-color="{s2}"/>
        <stop offset="100%" stop-color="{s3}"/>
      </radialGradient>

      <!-- Sunray Conic-like Sheen Overlay -->
      <linearGradient id="sunrayHighlight1" x1="18%" y1="8%" x2="82%" y2="92%">
        <stop offset="0%" stop-color="#FFFFFF" stop-opacity="0.24"/>
        <stop offset="42%" stop-color="#D8F0F8" stop-opacity="0.05"/>
        <stop offset="50%" stop-color="#FFFFFF" stop-opacity="0.30"/>
        <stop offset="58%" stop-color="#87B8CB" stop-opacity="0.06"/>
        <stop offset="100%" stop-color="#FFFFFF" stop-opacity="0.18"/>
      </linearGradient>

      <linearGradient id="sunrayHighlight2" x1="85%" y1="12%" x2="15%" y2="88%">
        <stop offset="0%" stop-color="#1E3F4F" stop-opacity="0.16"/>
        <stop offset="48%" stop-color="#FFFFFF" stop-opacity="0.12"/>
        <stop offset="52%" stop-color="#1E3F4F" stop-opacity="0.18"/>
        <stop offset="100%" stop-color="#24485A" stop-opacity="0.14"/>
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
            # 2. Cerachrom Tachymeter Bezel (r=186 to 222)
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
                lbl_col = (
                    "#E62229" if (theme["red_100"] and label == "100") else "#E8EEF2"
                )
                elems.append(
                    f'<text x="{tx:.2f}" y="{ty:.2f}" fill="{lbl_col}" font-family="Helvetica Neue, Arial, sans-serif" '
                    f'font-size="8.8" font-weight="800" text-anchor="middle" dominant-baseline="central" '
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
        # True #000000 OLED Black background for maximum battery conservation (0% pixel power on background)
        elems.append(f'<circle cx="{cx}" cy="{cy}" r="225" fill="#000000"/>')
        if not ultra_aod:
            elems.append(
                f'<circle cx="{cx}" cy="{cy}" r="{dial_r}" fill="#000000" stroke="#224452" stroke-width="0.8" stroke-opacity="0.55"/>'
            )

    # 3. Outer Railway Minute & 1/5th-Second Chronograph Track
    if not ambient:
        track_col = theme["track_col"]
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
            tick_col = (
                theme["daytona_red"]
                if (is_five and theme["paul_newman"])
                else track_col
            )
            elems.append(
                f'<line x1="{x1:.2f}" y1="{y1:.2f}" x2="{x2:.2f}" y2="{y2:.2f}" stroke="{tick_col}" stroke-width="{sw}"/>'
            )
    elif not ultra_aod:
        # In AOD Chromalight mode, only draw sparse 60 minute/second ticks in dim Chromalight
        for step in range(60):
            angle = step * 6.0
            is_five = step % 5 == 0
            r_out = track_r_out
            r_in = track_r_in_five if is_five else track_r_in_sec
            sw = 1.2 if is_five else 0.6
            col = "#5AC8E0" if is_five else "#2B5D6E"
            x1, y1 = polar(cx, cy, r_in, angle)
            x2, y2 = polar(cx, cy, r_out, angle)
            elems.append(
                f'<line x1="{x1:.2f}" y1="{y1:.2f}" x2="{x2:.2f}" y2="{y2:.2f}" stroke="{col}" stroke-width="{sw}" stroke-opacity="0.7"/>'
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
        if not ambient:
            elems.append(
                f'<g transform="translate({hx:.2f},{hy:.2f}) rotate({angle:.1f})">'
                f'<rect x="{-width / 2 - 1.1:.2f}" y="{-length / 2 - 1.1:.2f}" width="{width + 2.2:.2f}" height="{length + 2.2:.2f}" rx="1.2" fill="#1C2D36" fill-opacity="0.45"/>'
                f'<rect x="{-width / 2:.2f}" y="{-length / 2:.2f}" width="{width:.2f}" height="{length:.2f}" rx="0.9" fill="url(#whiteGold)"/>'
                f'<rect x="{-width / 2 + 1.3:.2f}" y="{-length / 2 + 1.3:.2f}" width="{width - 2.6:.2f}" height="{length - 2.6:.2f}" rx="0.4" fill="url(#diamondFacet)"/>'
                f'<line x1="{-width / 2 + 1.3:.2f}" y1="0" x2="{width / 2 - 1.3:.2f}" y2="0" stroke="#99BCCB" stroke-width="0.6" stroke-opacity="0.7"/>'
                f"</g>"
            )
        else:
            # Glowing Rolex Chromalight blue-cyan lume markers on pure #000000 black
            elems.append(
                f'<g transform="translate({hx:.2f},{hy:.2f}) rotate({angle:.1f})">'
                f'<rect x="{-width / 2:.2f}" y="{-length / 2:.2f}" width="{width:.2f}" height="{length:.2f}" rx="0.9" fill="#000000" stroke="#3A7C91" stroke-width="0.8"/>'
                f'<rect x="{-width / 2 + 1.3:.2f}" y="{-length / 2 + 1.3:.2f}" width="{width - 2.6:.2f}" height="{length - 2.6:.2f}" rx="0.4" fill="#7CE8FF" fill-opacity="0.88"/>'
                f"</g>"
            )

    # 5. Applied 12 o'clock Rolex 5-Pointed Coronet & Dial Signature
    coronet_fill = "#F4F7FA" if not ambient else "#000000"
    coronet_stroke = "#2A363E" if not ambient else "#7CE8FF"
    coronet_y = 58 if expanded else 84
    sig_offset = -20 if expanded else 0
    elems.append(f"""
    <g transform="translate(225, {coronet_y})">
      <ellipse cx="0" cy="10.5" rx="9.2" ry="2.7" fill="none" stroke="{coronet_stroke if ambient else coronet_fill}" stroke-width="1.4"/>
      <path d="M -9.2,8.5 L -12.5,-4.5 L -6.0,4.5 L -5.5,-9.5 L 0,3.5 L 5.5,-9.5 L 6.0,4.5 L 12.5,-4.5 L 9.2,8.5 Z"
            fill="{coronet_fill}" stroke="{coronet_stroke}" stroke-width="0.9" stroke-linejoin="round"/>
      <circle cx="-13.0" cy="-6.2" r="1.8" fill="{coronet_stroke if ambient else coronet_fill}" stroke="{coronet_stroke}" stroke-width="0.5"/>
      <circle cx="-6.0" cy="-11.5" r="2.0" fill="{coronet_stroke if ambient else coronet_fill}" stroke="{coronet_stroke}" stroke-width="0.5"/>
      <circle cx="0.0" cy="-13.5" r="2.2" fill="{coronet_stroke if ambient else coronet_fill}" stroke="{coronet_stroke}" stroke-width="0.5"/>
      <circle cx="6.0" cy="-11.5" r="2.0" fill="{coronet_stroke if ambient else coronet_fill}" stroke="{coronet_stroke}" stroke-width="0.5"/>
      <circle cx="13.0" cy="-6.2" r="1.8" fill="{coronet_stroke if ambient else coronet_fill}" stroke="{coronet_stroke}" stroke-width="0.5"/>
    </g>""")

    text_col = theme["text_col"] if not ambient else "#5AC8E0"
    if not ambient:
        elems.append(f"""
        <text x="225" y="{113.5 + sig_offset}" fill="{text_col}" font-family="Georgia, 'Times New Roman', serif" font-size="{14.4 if expanded else 13.2}" font-weight="700" letter-spacing="2.2" text-anchor="middle">ROLEX</text>
        <text x="225" y="{123.5 + sig_offset}" fill="{text_col}" font-family="Helvetica Neue, Arial, sans-serif" font-size="{6.8 if expanded else 6.2}" font-weight="700" letter-spacing="0.9" text-anchor="middle">OYSTER PERPETUAL</text>
        <text x="225" y="{132.0 + sig_offset}" fill="{text_col}" font-family="Helvetica Neue, Arial, sans-serif" font-size="{6.2 if expanded else 5.8}" font-weight="600" letter-spacing="0.6" text-anchor="middle">SUPERLATIVE CHRONOMETER</text>
        <text x="225" y="{139.8 + sig_offset}" fill="{text_col}" font-family="Helvetica Neue, Arial, sans-serif" font-size="{6.0 if expanded else 5.6}" font-weight="600" letter-spacing="0.7" text-anchor="middle">OFFICIALLY CERTIFIED</text>
        <text x="225" y="{148.5 + sig_offset}" fill="{text_col}" font-family="Helvetica Neue, Arial, sans-serif" font-size="{7.6 if expanded else 7.0}" font-weight="700" letter-spacing="1.4" text-anchor="middle">COSMOGRAPH</text>
        """)
    elif not ultra_aod:
        elems.append(f"""
        <text x="225" y="{114 + sig_offset}" fill="{text_col}" fill-opacity="0.75" font-family="Georgia, 'Times New Roman', serif" font-size="{14.4 if expanded else 13.2}" font-weight="700" letter-spacing="2.2" text-anchor="middle">ROLEX</text>
        <text x="225" y="{126 + sig_offset}" fill="{text_col}" fill-opacity="0.65" font-family="Helvetica Neue, Arial, sans-serif" font-size="{7.4 if expanded else 6.8}" font-weight="700" letter-spacing="1.2" text-anchor="middle">COSMOGRAPH</text>
        """)

    # 6. Three Snailed Subdial Rings (9 o'clock, 3 o'clock, 6 o'clock)
    if expanded:
        subdials = [
            (112.0, 220.0, ["60", "20", "40"], "LEFT"),
            (338.0, 220.0, ["30", "10", "20"], "RIGHT"),
            (225.0, 326.0, ["60", "20", "40"], "BOTTOM"),
        ]
    else:
        subdials = [
            (130.0, 225.0, ["60", "20", "40"], "LEFT"),
            (320.0, 225.0, ["30", "10", "20"], "RIGHT"),
            (225.0, 314.0, ["60", "20", "40"], "BOTTOM"),
        ]

    if not (ambient and ultra_aod):
        daytona_red = theme["daytona_red"] if not ambient else "#C83238"
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
                        f'<circle cx="{scx}" cy="{scy}" r="{sr:.1f}" fill="none" stroke="#180C06" stroke-width="0.45" stroke-opacity="0.55"/>'
                    )
                elems.append(
                    f'<circle cx="{scx}" cy="{scy}" r="{inner_r + 1.2}" fill="url(#platinumRim)"/>'
                )
                elems.append(
                    f'<circle cx="{scx}" cy="{scy}" r="{inner_r}" fill="url(#subdialCenterBase)"/>'
                )
                elems.append(
                    f'<circle cx="{scx}" cy="{scy}" r="{inner_r}" fill="url(#sunrayHighlight1)"/>'
                )

                for t in range(12):
                    ang = t * 30.0
                    if t % 4 == 0:
                        continue
                    tx1, ty1 = polar(scx, scy, outer_r - 1.0, ang)
                    tx2, ty2 = polar(
                        scx, scy, outer_r - (5.5 if expanded else 4.5), ang
                    )
                    elems.append(
                        f'<line x1="{tx1:.2f}" y1="{ty1:.2f}" x2="{tx2:.2f}" y2="{ty2:.2f}" stroke="#E8EEF2" stroke-width="{1.15 if expanded else 0.95}" stroke-opacity="0.85"/>'
                    )
                    if theme["paul_newman"]:
                        lx, ly = polar(
                            scx, scy, outer_r - (6.8 if expanded else 5.5), ang
                        )
                        sq = 2.6 if expanded else 2.0
                        elems.append(
                            f'<rect x="{lx - sq / 2:.2f}" y="{ly - sq / 2:.2f}" width="{sq:.2f}" height="{sq:.2f}" '
                            f'fill="#F5F2EB" transform="rotate({ang:.1f} {lx:.2f} {ly:.2f})"/>'
                        )

                for ang, num in zip((0.0, 120.0, 240.0), labels):
                    nx, ny = polar(scx, scy, mid_r, ang)
                    elems.append(
                        f'<text x="{nx:.2f}" y="{ny:.2f}" fill="#F2F6F9" font-family="Helvetica Neue, Arial, sans-serif" '
                        f'font-size="{9.8 if expanded else 7.4}" font-weight="700" text-anchor="middle" dominant-baseline="central">{num}</text>'
                    )
            else:
                # True #000000 OLED Black inside subdials with thin Chromalight rings (zero lit fill pixels!)
                elems.append(
                    f'<circle cx="{scx}" cy="{scy}" r="{outer_r}" fill="#000000" stroke="#2B5D6E" stroke-width="0.9" stroke-opacity="0.75"/>'
                )
                elems.append(
                    f'<circle cx="{scx}" cy="{scy}" r="{inner_r}" fill="#000000" stroke="#3A7C91" stroke-width="0.8" stroke-opacity="0.65"/>'
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
        cap_fill = theme["capsule_fill"]
        elems.append(f"""
        <!-- Top GMT / World Clock curved capsule under COSMOGRAPH -->
        <g transform="translate(225, {cap_y})">
          <rect x="{-cap_w / 2}" y="{-cap_h / 2}" width="{cap_w}" height="{cap_h}" rx="{cap_h / 2}" fill="{cap_fill}" fill-opacity="0.92" stroke="url(#platinumRim)" stroke-width="0.9"/>
        </g>
        <!-- Left 7:30 Sunrise/Solar capsule (cleanly outside both 9 and 6 subdials) -->
        <g transform="translate({solar_cx}, {solar_cy})">
          <rect x="{-solar_w / 2}" y="{-solar_h / 2}" width="{solar_w}" height="{solar_h}" rx="{solar_h / 2}" fill="{cap_fill}" fill-opacity="0.92" stroke="url(#platinumRim)" stroke-width="0.9"/>
        </g>
        <!-- Right 4:30 Platinum Cyclops Date window (cleanly outside both 3 and 6 subdials) -->
        <g transform="translate({date_cx}, {date_cy})">
          <rect x="{-date_w / 2}" y="{-date_h / 2}" width="{date_w}" height="{date_h}" rx="4" fill="url(#platinumRim)" stroke="#24140C" stroke-width="0.7"/>
          <rect x="{-date_in_w / 2}" y="{-date_in_h / 2}" width="{date_in_w}" height="{date_in_h}" rx="2.5" fill="#F4F8FA"/>
        </g>
        """)
        elems.append(
            f'<text x="225" y="{swiss_y}" fill="{text_col}" font-family="Helvetica Neue, Arial, sans-serif" '
            'font-size="5.8" font-weight="700" letter-spacing="1.2" text-anchor="middle">SWISS  ♛  MADE</text>'
        )

    return f'<svg xmlns="http://www.w3.org/2000/svg" width="450" height="450" viewBox="0 0 450 450">{"".join(elems)}</svg>'


def make_hour_hand_svg(ambient: bool = False) -> str:
    if ambient:
        # Hollow skeletonized Chromalight AOD hand (pure #000000 interior + cyan Chromalight outline/lume)
        return """<svg xmlns="http://www.w3.org/2000/svg" width="450" height="450" viewBox="0 0 450 450">
          <polygon points="225,114 218.5,126 219.5,246 225,252 230.5,246 231.5,126" fill="#000000" stroke="#7CE8FF" stroke-width="1.3"/>
          <rect x="222.2" y="130" width="5.6" height="76" rx="1.2" fill="#7CE8FF" fill-opacity="0.90"/>
          <circle cx="225" cy="225" r="9.5" fill="#000000" stroke="#7CE8FF" stroke-width="1.2"/>
        </svg>"""
    lume = "#F7FBFF"
    metal_left = "#E8EEF2"
    metal_right = "#8E99A4"
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="450" height="450" viewBox="0 0 450 450">
      <defs>
        <filter id="handShadow" x="-20%" y="-20%" width="140%" height="140%">
          <feDropShadow dx="1.5" dy="2.5" stdDeviation="2.2" flood-color="#000000" flood-opacity="0.45"/>
        </filter>
      </defs>
      <g filter="url(#handShadow)">
        <polygon points="225,252 219.5,244 221,225 225,225" fill="{metal_left}"/>
        <polygon points="225,252 230.5,244 229,225 225,225" fill="{metal_right}"/>
        <polygon points="225,114 218.5,126 219.5,225 225,225" fill="{metal_left}"/>
        <polygon points="225,114 231.5,126 230.5,225 225,225" fill="{metal_right}"/>
        <rect x="222.0" y="130" width="6.0" height="78" rx="1.2" fill="{lume}"/>
        <circle cx="225" cy="225" r="10.5" fill="{metal_left}" stroke="#4A555E" stroke-width="1.0"/>
      </g>
    </svg>"""


def make_minute_hand_svg(ambient: bool = False) -> str:
    if ambient:
        # Hollow skeletonized Chromalight AOD minute hand
        return """<svg xmlns="http://www.w3.org/2000/svg" width="450" height="450" viewBox="0 0 450 450">
          <polygon points="225,60 220.0,76 220.8,248 225,258 229.2,248 230.0,76" fill="#000000" stroke="#7CE8FF" stroke-width="1.3"/>
          <rect x="222.5" y="78" width="5.0" height="126" rx="1.2" fill="#7CE8FF" fill-opacity="0.90"/>
          <circle cx="225" cy="225" r="8.0" fill="#000000" stroke="#7CE8FF" stroke-width="1.2"/>
        </svg>"""
    lume = "#F7FBFF"
    metal_left = "#F0F4F8"
    metal_right = "#838E99"
    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="450" height="450" viewBox="0 0 450 450">
      <defs>
        <filter id="minShadow" x="-20%" y="-20%" width="140%" height="140%">
          <feDropShadow dx="2.0" dy="3.0" stdDeviation="2.5" flood-color="#000000" flood-opacity="0.48"/>
        </filter>
      </defs>
      <g filter="url(#minShadow)">
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


def make_unread_badge_svg() -> str:
    """24x24 glowing ruby notification jewel set in a 950 platinum collet."""
    return """<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">
      <defs>
        <radialGradient id="rubyGlow" cx="42%" cy="38%" r="55%">
          <stop offset="0%" stop-color="#FF7A82"/>
          <stop offset="45%" stop-color="#E61E28"/>
          <stop offset="85%" stop-color="#9E0B12"/>
          <stop offset="100%" stop-color="#5E0408"/>
        </radialGradient>
      </defs>
      <circle cx="12" cy="12" r="9.5" fill="#E8EEF2" stroke="#24140C" stroke-width="0.9"/>
      <circle cx="12" cy="12" r="7.5" fill="url(#rubyGlow)"/>
      <circle cx="9.8" cy="9.5" r="2.1" fill="#FFFFFF" fill-opacity="0.65"/>
    </svg>"""


def make_preview_svg() -> str:
    base = make_dial_svg(ambient=False, expanded=True, theme_key="platinum").replace(
        "</svg>", ""
    )
    extra = """
      <!-- Preview sample complication text inside the expanded 120px subdials and apertures -->
      <text x="225" y="150.5" fill="#E8EEF2" font-family="Helvetica Neue, Arial, sans-serif" font-size="10.5" font-weight="700" text-anchor="middle" dominant-baseline="central">AMS 15:10</text>
      <text x="112" y="208" fill="#24140C" font-family="Helvetica Neue, Arial, sans-serif" font-size="16.5" font-weight="800" text-anchor="middle">75</text>
      <text x="112" y="236" fill="#C81D25" font-family="Helvetica Neue, Arial, sans-serif" font-size="10.5" font-weight="800" text-anchor="middle">♥ 83%</text>
      <text x="338" y="208" fill="#24140C" font-family="Helvetica Neue, Arial, sans-serif" font-size="16.5" font-weight="800" text-anchor="middle">71°</text>
      <text x="338" y="234" fill="#381F14" font-family="Helvetica Neue, Arial, sans-serif" font-size="9.2" font-weight="700" text-anchor="middle">WEATHER</text>
      <text x="225" y="314" fill="#24140C" font-family="Helvetica Neue, Arial, sans-serif" font-size="15.5" font-weight="800" text-anchor="middle">8,420</text>
      <text x="225" y="340" fill="#381F14" font-family="Helvetica Neue, Arial, sans-serif" font-size="9.2" font-weight="700" text-anchor="middle">STEPS</text>
      <text x="124" y="320.5" fill="#E8EEF2" font-family="Helvetica Neue, Arial, sans-serif" font-size="9.2" font-weight="700" text-anchor="middle" dominant-baseline="central">☀ 6:07P</text>
      <text x="326" y="320.5" fill="#24140C" font-family="Helvetica Neue, Arial, sans-serif" font-size="10.0" font-weight="800" text-anchor="middle" dominant-baseline="central">SAT 24</text>
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


dial_variants = [
    ("dial_interactive", False, False, "platinum", False),
    ("dial_ambient", True, False, "platinum", False),
    ("dial_ultra_ambient", True, False, "platinum", True),
    ("dial_expanded_interactive", False, True, "platinum", False),
    ("dial_expanded_ambient", True, True, "platinum", False),
    ("dial_expanded_ultra_ambient", True, True, "platinum", True),
    ("dial_panda_interactive", False, False, "panda", False),
    ("dial_panda_expanded_interactive", False, True, "panda", False),
    ("dial_revpanda_interactive", False, False, "reverse_panda", False),
    ("dial_revpanda_expanded_interactive", False, True, "reverse_panda", False),
    ("dial_lemans_interactive", False, False, "lemans", False),
    ("dial_lemans_expanded_interactive", False, True, "lemans", False),
]

for name, is_amb, is_exp, theme_id, is_ultra in dial_variants:
    svg_file = f"{name}.svg"
    with open(os.path.join(SVG_DIR, svg_file), "w") as f:
        f.write(
            make_dial_svg(
                ambient=is_amb,
                expanded=is_exp,
                theme_key=theme_id,
                ultra_aod=is_ultra,
            )
        )
    svg_to_png(svg_file, os.path.join(DRAWABLE_DIR, f"{name}.png"), 450, 450)

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
with open(os.path.join(SVG_DIR, "unread_badge.svg"), "w") as f:
    f.write(make_unread_badge_svg())
with open(os.path.join(SVG_DIR, "preview.svg"), "w") as f:
    f.write(make_preview_svg())

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
svg_to_png("unread_badge.svg", os.path.join(DRAWABLE_DIR, "unread_badge.png"), 24, 24)
svg_to_png("preview.svg", os.path.join(DRAWABLE_DIR, "preview.png"), 450, 450)
svg_to_png("preview.svg", os.path.join(DRAWABLE_DIR, "preview_circular.png"), 450, 450)

print("Re-rendered all Daytona reference theme & OLED AOD PNG assets successfully.")
