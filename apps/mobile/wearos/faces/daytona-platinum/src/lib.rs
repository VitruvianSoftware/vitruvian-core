// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

//! scripts/generate_assets.py in Rust.
//!
//! The Python generator draws nothing itself: it writes one SVG document per
//! asset and hands each to `rsvg-convert` (librsvg) to rasterise. This port
//! does the same. It builds the same SVG documents, byte for byte (the same
//! geometry, the same float formatting as Python's `repr` and `:.Nf`), and
//! renders them with the same `rsvg-convert`, found the same way. Identical
//! SVG in, the same renderer, identical pixels out.
//!
//! Std only, no crates. Differences from the Python, all deliberate:
//! * `--out-dir DIR` writes the PNGs somewhere other than the package's
//!   `src/main/res/drawable-nodpi` (the default, as in the Python);
//! * the assets are rendered in parallel;
//! * the temporary SVG directory is removed afterwards (the Python leaks it).

use std::fmt::Write as _;
use std::io;
use std::path::{Path, PathBuf};
use std::process::Command;

/// The package, relative to the workspace root.
pub const PACKAGE_REL: &str = "apps/mobile/wearos/faces/daytona-platinum";
/// Where the PNGs go, relative to the package.
pub const DRAWABLE_REL: &str = "src/main/res/drawable-nodpi";
/// Where the Python looks for `rsvg-convert` when it is not on `PATH`.
pub const RSVG_FALLBACK: &str = "/opt/homebrew/bin/rsvg-convert";
/// The line the Python prints when it finishes.
pub const DONE_MESSAGE: &str =
    "Re-rendered all Daytona reference theme & OLED AOD PNG assets successfully.";

pub const USAGE: &str = "usage: generate_assets [-h] [--out-dir DIR]";

pub const HELP: &str = "usage: generate_assets [-h] [--out-dir DIR]

Generate the Rolex Cosmograph Daytona PNG assets (4 reference themes and
true-black OLED AOD) by rendering SVG with rsvg-convert.

options:
  -h, --help     show this help message and exit
  --out-dir DIR  write the PNGs here (default: the package's
                 src/main/res/drawable-nodpi, under
                 $BUILD_WORKSPACE_DIRECTORY when set)
";

// --- Python number formatting ------------------------------------------------

/// `repr(x)` (and so `f"{x}"`) for a Python float: the shortest string that
/// round-trips, always with a `.0` or an exponent, scientific notation below
/// 1e-4 and from 1e16.
pub fn py_repr(x: f64) -> String {
    if x.is_nan() {
        return "nan".to_string();
    }
    if x.is_infinite() {
        return if x > 0.0 { "inf" } else { "-inf" }.to_string();
    }
    if x == 0.0 {
        return if x.is_sign_negative() { "-0.0" } else { "0.0" }.to_string();
    }
    // `{:e}` gives the shortest round-trip digits: "2.255e2", "-1e-5".
    let sci = format!("{x:e}");
    let (mantissa, exp) = sci.split_once('e').expect("{:e} always has an exponent");
    let exp: i32 = exp.parse().expect("{:e} exponent is an integer");
    if (-4..16).contains(&exp) {
        let s = format!("{x}");
        if s.contains('.') {
            s
        } else {
            s + ".0"
        }
    } else {
        let sign = if exp < 0 { '-' } else { '+' };
        format!("{mantissa}e{sign}{:02}", exp.abs())
    }
}

/// `format(x, ".1f")`.
pub fn f1(x: f64) -> String {
    format!("{x:.1}")
}

/// `format(x, ".2f")`.
pub fn f2(x: f64) -> String {
    format!("{x:.2}")
}

/// `polar(cx, cy, r, angle_deg)`: 0 degrees is 12 o'clock, clockwise.
pub fn polar(cx: f64, cy: f64, r: f64, angle_deg: f64) -> (f64, f64) {
    // math.radians is x * (pi / 180), as is f64::to_radians.
    let rad = (angle_deg - 90.0).to_radians();
    (cx + r * rad.cos(), cy + r * rad.sin())
}

// --- Themes ------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Theme {
    pub bezel_stops: [&'static str; 5],
    pub ring_stops: [&'static str; 4],
    pub dial_stops: [&'static str; 4],
    pub subdial_stops: [&'static str; 4],
    pub track_col: &'static str,
    pub text_col: &'static str,
    pub capsule_fill: &'static str,
    pub daytona_red: &'static str,
    pub paul_newman: bool,
    pub red_100: bool,
}

pub const PLATINUM: Theme = Theme {
    bezel_stops: ["#4E2F21", "#381F14", "#593626", "#2A160D", "#3D2216"],
    ring_stops: ["#4A2B1D", "#331B11", "#583525", "#2B160D"],
    dial_stops: ["#D2ECF5", "#B3D9E8", "#96C5D8", "#7BAFC4"],
    subdial_stops: ["#D2ECF5", "#B3D9E8", "#96C5D8", "#7BAFC4"],
    track_col: "#361D12",
    text_col: "#24140C",
    capsule_fill: "#2A160D",
    daytona_red: "#C81D25",
    paul_newman: false,
    red_100: false,
};

pub const PANDA: Theme = Theme {
    bezel_stops: ["#2B3036", "#16191D", "#32383F", "#0D0F12", "#1C2024"],
    ring_stops: ["#262A30", "#14171A", "#2E333A", "#0E1013"],
    dial_stops: ["#FFFFFF", "#F6F9FB", "#EAEFF3", "#DCE4EA"],
    subdial_stops: ["#FFFFFF", "#F6F9FB", "#EAEFF3", "#DCE4EA"],
    track_col: "#181C20",
    text_col: "#14181C",
    capsule_fill: "#161A1E",
    daytona_red: "#D41920",
    paul_newman: false,
    red_100: false,
};

pub const REVERSE_PANDA: Theme = Theme {
    bezel_stops: ["#2B3036", "#16191D", "#32383F", "#0D0F12", "#1C2024"],
    ring_stops: ["#68737E", "#3E464E", "#7C8894", "#2B3137"],
    dial_stops: ["#2A3036", "#1A1E22", "#111417", "#090B0D"],
    subdial_stops: ["#F5F8FA", "#E4EBF0", "#D4DEE6", "#C2CFD9"],
    track_col: "#DCE4EC",
    text_col: "#EEF3F7",
    capsule_fill: "#1A2026",
    daytona_red: "#E62229",
    paul_newman: false,
    red_100: false,
};

pub const LEMANS: Theme = Theme {
    bezel_stops: ["#282626", "#151414", "#302D2D", "#0C0B0B", "#1C1A1A"],
    ring_stops: ["#362822", "#1E1612", "#42312A", "#140E0B"],
    dial_stops: ["#2B2928", "#1B1918", "#121010", "#0A0909"],
    subdial_stops: ["#FCF8F0", "#F3EDE0", "#E7DFCE", "#D8CEB8"],
    track_col: "#F0ECE1",
    text_col: "#F5F2EB",
    capsule_fill: "#1F1714",
    daytona_red: "#E62229",
    paul_newman: true,
    red_100: true,
};

/// The Python `THEMES` dict.
pub fn theme(key: &str) -> Option<&'static Theme> {
    match key {
        "platinum" => Some(&PLATINUM),
        "panda" => Some(&PANDA),
        "reverse_panda" => Some(&REVERSE_PANDA),
        "lemans" => Some(&LEMANS),
        _ => None,
    }
}

// --- SVG documents -----------------------------------------------------------

const TACHY_MARKS: [(f64, &str); 18] = [
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
];

fn dial_defs(theme: &Theme) -> String {
    let [b0, b1, b2, b3, b4] = theme.bezel_stops;
    let [r0, r1, r2, r3] = theme.ring_stops;
    let [d0, d1, d2, d3] = theme.dial_stops;
    let [s0, s1, s2, s3] = theme.subdial_stops;
    format!(
        r##"<defs>
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
    </defs>"##
    )
}

/// `make_dial_svg(ambient, expanded, theme_key, ultra_aod)`.
pub fn dial_svg(ambient: bool, expanded: bool, theme: &Theme, ultra_aod: bool) -> String {
    let (cx, cy) = (225.0_f64, 225.0_f64);
    let (pcx, pcy) = (py_repr(cx), py_repr(cy));
    let mut s = String::with_capacity(96 * 1024);
    s.push_str(&dial_defs(theme));

    let dial_r = if expanded { 220.5 } else { 184.0 };
    let track_r_out = if expanded { 216.5 } else { 181.0 };
    let track_r_in_sec = if expanded { 209.0 } else { 173.5 };
    let track_r_in_five = if expanded { 207.0 } else { 171.5 };
    let track_r_in_sub = if expanded { 212.0 } else { 176.5 };
    let pdial_r = py_repr(dial_r);

    // `write!` into a String cannot fail.
    macro_rules! out {
        ($($arg:tt)*) => { let _ = write!(s, $($arg)*); };
    }

    if !ambient {
        // 1. Outer 950 Platinum case lip
        out!(r##"<circle cx="{pcx}" cy="{pcy}" r="225" fill="url(#platinumRim)"/>"##);
        out!(r##"<circle cx="{pcx}" cy="{pcy}" r="222.5" fill="#1C100B"/>"##);

        if !expanded {
            // 2. Cerachrom Tachymeter Bezel
            out!(r##"<circle cx="{pcx}" cy="{pcy}" r="221.5" fill="url(#cerachromBezel)"/>"##);
            out!(
                r##"<circle cx="{pcx}" cy="{pcy}" r="220.5" fill="none" stroke="#7A523E" stroke-width="0.8" stroke-opacity="0.55"/>"##
            );

            for (idx, ch) in "UNITS PER HOUR".chars().enumerate() {
                let ang = 17.5 + idx as f64 * 1.95;
                let (ux, uy) = polar(cx, cy, 204.5, ang);
                let (ux, uy, ang) = (f2(ux), f2(uy), f1(ang));
                out!(
                    r##"<text x="{ux}" y="{uy}" fill="#E8EEF2" font-family="Helvetica Neue, Arial, sans-serif" font-size="6.4" font-weight="700" text-anchor="middle" dominant-baseline="central" transform="rotate({ang} {ux} {uy})">{ch}</text>"##
                );
            }

            for deg in (56..348).step_by(4) {
                let deg = f64::from(deg);
                if TACHY_MARKS.iter().any(|&(a, _)| (deg - a).abs() < 2.2) {
                    continue;
                }
                let (x1, y1) = polar(cx, cy, 188.0, deg);
                let (x2, y2) = polar(cx, cy, 192.0, deg);
                let (x1, y1, x2, y2) = (f2(x1), f2(y1), f2(x2), f2(y2));
                out!(
                    r##"<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="#D8DFE5" stroke-width="1.0" stroke-opacity="0.65"/>"##
                );
            }

            for &(angle, label) in &TACHY_MARKS {
                let (dx, dy) = polar(cx, cy, 191.5, angle);
                let (dx, dy) = (f2(dx), f2(dy));
                out!(r##"<circle cx="{dx}" cy="{dy}" r="1.7" fill="#E8EEF2"/>"##);
                let (tx, ty) = polar(cx, cy, 204.5, angle);
                let rot = if angle <= 95.0 || angle >= 265.0 {
                    angle
                } else {
                    angle + 180.0
                };
                let lbl_col = if theme.red_100 && label == "100" {
                    "#E62229"
                } else {
                    "#E8EEF2"
                };
                let (tx, ty, rot) = (f2(tx), f2(ty), f1(rot));
                out!(
                    r##"<text x="{tx}" y="{ty}" fill="{lbl_col}" font-family="Helvetica Neue, Arial, sans-serif" font-size="8.8" font-weight="800" text-anchor="middle" dominant-baseline="central" transform="rotate({rot} {tx} {ty})">{label}</text>"##
                );
            }

            s.push_str(r##"<polygon points="225,189.5 220.2,199 229.8,199" fill="#E8EEF2"/>"##);
            out!(r##"<circle cx="{pcx}" cy="{pcy}" r="186.5" fill="url(#platinumRim)"/>"##);
        }

        out!(r##"<circle cx="{pcx}" cy="{pcy}" r="{pdial_r}" fill="url(#iceBlueBase)"/>"##);
        out!(r##"<circle cx="{pcx}" cy="{pcy}" r="{pdial_r}" fill="url(#sunrayHighlight1)"/>"##);
        out!(r##"<circle cx="{pcx}" cy="{pcy}" r="{pdial_r}" fill="url(#sunrayHighlight2)"/>"##);

        for i in (0..360).step_by(2) {
            let (x2, y2) = polar(cx, cy, dial_r, f64::from(i));
            let (op, col) = if i % 4 == 0 {
                ("0.045", "#FFFFFF")
            } else {
                ("0.025", "#2B5669")
            };
            let (x2, y2) = (f2(x2), f2(y2));
            out!(
                r##"<line x1="{pcx}" y1="{pcy}" x2="{x2}" y2="{y2}" stroke="{col}" stroke-width="0.7" stroke-opacity="{op}"/>"##
            );
        }

        out!(r##"<circle cx="{pcx}" cy="{pcy}" r="{pdial_r}" fill="url(#rehautShadow)"/>"##);
    } else {
        // True #000000 OLED Black background
        out!(r##"<circle cx="{pcx}" cy="{pcy}" r="225" fill="#000000"/>"##);
        if !ultra_aod {
            out!(
                r##"<circle cx="{pcx}" cy="{pcy}" r="{pdial_r}" fill="#000000" stroke="#224452" stroke-width="0.8" stroke-opacity="0.55"/>"##
            );
        }
    }

    // 3. Outer Railway Minute & 1/5th-Second Chronograph Track
    if !ambient {
        let track_col = theme.track_col;
        let (pout, psec) = (py_repr(track_r_out), py_repr(track_r_in_sec));
        out!(
            r##"<circle cx="{pcx}" cy="{pcy}" r="{pout}" fill="none" stroke="{track_col}" stroke-width="0.9" stroke-opacity="0.85"/>"##
        );
        out!(
            r##"<circle cx="{pcx}" cy="{pcy}" r="{psec}" fill="none" stroke="{track_col}" stroke-width="0.7" stroke-opacity="0.75"/>"##
        );

        for step in 0..300_u32 {
            let angle = f64::from(step) * 1.2;
            let is_five = step % 25 == 0;
            let is_sec = step % 5 == 0;
            let r_in = if is_five {
                track_r_in_five
            } else if is_sec {
                track_r_in_sec
            } else {
                track_r_in_sub
            };
            let sw = if is_five {
                1.6
            } else if is_sec {
                1.0
            } else {
                0.55
            };
            let (x1, y1) = polar(cx, cy, r_in, angle);
            let (x2, y2) = polar(cx, cy, track_r_out, angle);
            let tick_col = if is_five && theme.paul_newman {
                theme.daytona_red
            } else {
                track_col
            };
            let (x1, y1, x2, y2, sw) = (f2(x1), f2(y1), f2(x2), f2(y2), py_repr(sw));
            out!(
                r##"<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{tick_col}" stroke-width="{sw}"/>"##
            );
        }
    } else if !ultra_aod {
        // AOD Chromalight: sparse 60 minute/second ticks
        for step in 0..60_u32 {
            let angle = f64::from(step) * 6.0;
            let is_five = step % 5 == 0;
            let r_in = if is_five {
                track_r_in_five
            } else {
                track_r_in_sec
            };
            let (sw, col) = if is_five {
                (1.2, "#5AC8E0")
            } else {
                (0.6, "#2B5D6E")
            };
            let (x1, y1) = polar(cx, cy, r_in, angle);
            let (x2, y2) = polar(cx, cy, track_r_out, angle);
            let (x1, y1, x2, y2, sw) = (f2(x1), f2(y1), f2(x2), f2(y2), py_repr(sw));
            out!(
                r##"<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{col}" stroke-width="{sw}" stroke-opacity="0.7"/>"##
            );
        }
    }

    // 4. Applied Baguette Diamond / Chromalight Hour Markers (1..11)
    for hr in 1..12_u32 {
        let angle = f64::from(hr) * 30.0;
        let is_subdial_hr = matches!(hr, 3 | 6 | 9);
        let (length, width, r_center) = match (expanded, is_subdial_hr) {
            (true, true) => (14.0, 6.8, 196.0),
            (true, false) => (22.0, 7.6, 190.0),
            (false, true) => (10.0, 6.2, 165.0),
            (false, false) => (19.5, 7.0, 156.5),
        };
        let (hx, hy) = polar(cx, cy, r_center, angle);
        let (hx, hy, ang) = (f2(hx), f2(hy), f1(angle));
        let hw = -width / 2.0;
        let hl = -length / 2.0;
        if !ambient {
            let (ox, oy, ow, oh) = (
                f2(hw - 1.1),
                f2(hl - 1.1),
                f2(width + 2.2),
                f2(length + 2.2),
            );
            let (mx, my, mw, mh) = (f2(hw), f2(hl), f2(width), f2(length));
            let (ix, iy, iw, ih) = (
                f2(hw + 1.3),
                f2(hl + 1.3),
                f2(width - 2.6),
                f2(length - 2.6),
            );
            let lx2 = f2(width / 2.0 - 1.3);
            out!(
                r##"<g transform="translate({hx},{hy}) rotate({ang})"><rect x="{ox}" y="{oy}" width="{ow}" height="{oh}" rx="1.2" fill="#1C2D36" fill-opacity="0.45"/><rect x="{mx}" y="{my}" width="{mw}" height="{mh}" rx="0.9" fill="url(#whiteGold)"/><rect x="{ix}" y="{iy}" width="{iw}" height="{ih}" rx="0.4" fill="url(#diamondFacet)"/><line x1="{ix}" y1="0" x2="{lx2}" y2="0" stroke="#99BCCB" stroke-width="0.6" stroke-opacity="0.7"/></g>"##
            );
        } else {
            let (mx, my, mw, mh) = (f2(hw), f2(hl), f2(width), f2(length));
            let (ix, iy, iw, ih) = (
                f2(hw + 1.3),
                f2(hl + 1.3),
                f2(width - 2.6),
                f2(length - 2.6),
            );
            out!(
                r##"<g transform="translate({hx},{hy}) rotate({ang})"><rect x="{mx}" y="{my}" width="{mw}" height="{mh}" rx="0.9" fill="#000000" stroke="#3A7C91" stroke-width="0.8"/><rect x="{ix}" y="{iy}" width="{iw}" height="{ih}" rx="0.4" fill="#7CE8FF" fill-opacity="0.88"/></g>"##
            );
        }
    }

    // 5. Applied 12 o'clock Rolex 5-Pointed Coronet & Dial Signature
    let coronet_fill = if ambient { "#000000" } else { "#F4F7FA" };
    let coronet_stroke = if ambient { "#7CE8FF" } else { "#2A363E" };
    let ring = if ambient {
        coronet_stroke
    } else {
        coronet_fill
    };
    let coronet_y: i32 = if expanded { 58 } else { 84 };
    let sig_offset: i32 = if expanded { -20 } else { 0 };
    out!(
        r##"
    <g transform="translate(225, {coronet_y})">
      <ellipse cx="0" cy="10.5" rx="9.2" ry="2.7" fill="none" stroke="{ring}" stroke-width="1.4"/>
      <path d="M -9.2,8.5 L -12.5,-4.5 L -6.0,4.5 L -5.5,-9.5 L 0,3.5 L 5.5,-9.5 L 6.0,4.5 L 12.5,-4.5 L 9.2,8.5 Z"
            fill="{coronet_fill}" stroke="{coronet_stroke}" stroke-width="0.9" stroke-linejoin="round"/>
      <circle cx="-13.0" cy="-6.2" r="1.8" fill="{ring}" stroke="{coronet_stroke}" stroke-width="0.5"/>
      <circle cx="-6.0" cy="-11.5" r="2.0" fill="{ring}" stroke="{coronet_stroke}" stroke-width="0.5"/>
      <circle cx="0.0" cy="-13.5" r="2.2" fill="{ring}" stroke="{coronet_stroke}" stroke-width="0.5"/>
      <circle cx="6.0" cy="-11.5" r="2.0" fill="{ring}" stroke="{coronet_stroke}" stroke-width="0.5"/>
      <circle cx="13.0" cy="-6.2" r="1.8" fill="{ring}" stroke="{coronet_stroke}" stroke-width="0.5"/>
    </g>"##
    );

    let text_col = if ambient { "#5AC8E0" } else { theme.text_col };
    let sig = f64::from(sig_offset);
    let pick = |a: f64, b: f64| py_repr(if expanded { a } else { b });
    if !ambient {
        let (y1, y2, y3, y4, y5) = (
            py_repr(113.5 + sig),
            py_repr(123.5 + sig),
            py_repr(132.0 + sig),
            py_repr(139.8 + sig),
            py_repr(148.5 + sig),
        );
        let (fs1, fs2, fs3, fs4, fs5) = (
            pick(14.4, 13.2),
            pick(6.8, 6.2),
            pick(6.2, 5.8),
            pick(6.0, 5.6),
            pick(7.6, 7.0),
        );
        out!(
            r##"
        <text x="225" y="{y1}" fill="{text_col}" font-family="Georgia, 'Times New Roman', serif" font-size="{fs1}" font-weight="700" letter-spacing="2.2" text-anchor="middle">ROLEX</text>
        <text x="225" y="{y2}" fill="{text_col}" font-family="Helvetica Neue, Arial, sans-serif" font-size="{fs2}" font-weight="700" letter-spacing="0.9" text-anchor="middle">OYSTER PERPETUAL</text>
        <text x="225" y="{y3}" fill="{text_col}" font-family="Helvetica Neue, Arial, sans-serif" font-size="{fs3}" font-weight="600" letter-spacing="0.6" text-anchor="middle">SUPERLATIVE CHRONOMETER</text>
        <text x="225" y="{y4}" fill="{text_col}" font-family="Helvetica Neue, Arial, sans-serif" font-size="{fs4}" font-weight="600" letter-spacing="0.7" text-anchor="middle">OFFICIALLY CERTIFIED</text>
        <text x="225" y="{y5}" fill="{text_col}" font-family="Helvetica Neue, Arial, sans-serif" font-size="{fs5}" font-weight="700" letter-spacing="1.4" text-anchor="middle">COSMOGRAPH</text>
        "##
        );
    } else if !ultra_aod {
        // Python adds an int offset to int literals here: these print as ints.
        let (y1, y2) = (114 + sig_offset, 126 + sig_offset);
        let (fs1, fs2) = (pick(14.4, 13.2), pick(7.4, 6.8));
        out!(
            r##"
        <text x="225" y="{y1}" fill="{text_col}" fill-opacity="0.75" font-family="Georgia, 'Times New Roman', serif" font-size="{fs1}" font-weight="700" letter-spacing="2.2" text-anchor="middle">ROLEX</text>
        <text x="225" y="{y2}" fill="{text_col}" fill-opacity="0.65" font-family="Helvetica Neue, Arial, sans-serif" font-size="{fs2}" font-weight="700" letter-spacing="1.2" text-anchor="middle">COSMOGRAPH</text>
        "##
        );
    }

    // 6. Three Snailed Subdial Rings (9 o'clock, 3 o'clock, 6 o'clock)
    let subdials: [(f64, f64, [&str; 3]); 3] = if expanded {
        [
            (112.0, 220.0, ["60", "20", "40"]),
            (338.0, 220.0, ["30", "10", "20"]),
            (225.0, 326.0, ["60", "20", "40"]),
        ]
    } else {
        [
            (130.0, 225.0, ["60", "20", "40"]),
            (320.0, 225.0, ["30", "10", "20"]),
            (225.0, 314.0, ["60", "20", "40"]),
        ]
    };

    if !(ambient && ultra_aod) {
        let daytona_red = if ambient {
            "#C83238"
        } else {
            theme.daytona_red
        };
        let bottom_cy = if expanded { 326.0 } else { 314.0 };
        let daytona_r = if expanded { 68.0 } else { 52.0 };
        let fs = pick(9.8, 8.2);
        for (idx, ch) in "DAYTONA".chars().enumerate() {
            let ang = -24.0 + idx as f64 * 8.0;
            let (dx, dy) = polar(225.0, bottom_cy, daytona_r, ang);
            let (dx, dy, ang) = (f2(dx), f2(dy), f1(ang));
            out!(
                r##"<text x="{dx}" y="{dy}" fill="{daytona_red}" font-family="Helvetica Neue, Arial, sans-serif" font-size="{fs}" font-weight="800" text-anchor="middle" dominant-baseline="central" transform="rotate({ang} {dx} {dy})">{ch}</text>"##
            );
        }

        for &(scx, scy, labels) in &subdials {
            let outer_r = if expanded { 60.0 } else { 44.5 };
            let inner_r = if expanded { 44.0 } else { 31.0 };
            let mid_r = (outer_r + inner_r) / 2.0;
            let (pscx, pscy) = (py_repr(scx), py_repr(scy));
            let (pouter, pinner) = (py_repr(outer_r), py_repr(inner_r));

            if !ambient {
                let rim = py_repr(outer_r + 1.5);
                out!(r##"<circle cx="{pscx}" cy="{pscy}" r="{rim}" fill="url(#platinumRim)"/>"##);
                out!(
                    r##"<circle cx="{pscx}" cy="{pscy}" r="{pouter}" fill="url(#chestnutRing)"/>"##
                );
                let snail_steps = if expanded { 7 } else { 5 };
                for step_i in 1..snail_steps {
                    let sr = f1(outer_r - f64::from(step_i) * 2.2);
                    out!(
                        r##"<circle cx="{pscx}" cy="{pscy}" r="{sr}" fill="none" stroke="#180C06" stroke-width="0.45" stroke-opacity="0.55"/>"##
                    );
                }
                let inner_rim = py_repr(inner_r + 1.2);
                out!(
                    r##"<circle cx="{pscx}" cy="{pscy}" r="{inner_rim}" fill="url(#platinumRim)"/>"##
                );
                out!(
                    r##"<circle cx="{pscx}" cy="{pscy}" r="{pinner}" fill="url(#subdialCenterBase)"/>"##
                );
                out!(
                    r##"<circle cx="{pscx}" cy="{pscy}" r="{pinner}" fill="url(#sunrayHighlight1)"/>"##
                );

                let tick_sw = pick(1.15, 0.95);
                for t in 0..12_u32 {
                    if t % 4 == 0 {
                        continue;
                    }
                    let ang = f64::from(t) * 30.0;
                    let (tx1, ty1) = polar(scx, scy, outer_r - 1.0, ang);
                    let (tx2, ty2) =
                        polar(scx, scy, outer_r - if expanded { 5.5 } else { 4.5 }, ang);
                    let (tx1, ty1, tx2, ty2) = (f2(tx1), f2(ty1), f2(tx2), f2(ty2));
                    out!(
                        r##"<line x1="{tx1}" y1="{ty1}" x2="{tx2}" y2="{ty2}" stroke="#E8EEF2" stroke-width="{tick_sw}" stroke-opacity="0.85"/>"##
                    );
                    if theme.paul_newman {
                        let (lx, ly) =
                            polar(scx, scy, outer_r - if expanded { 6.8 } else { 5.5 }, ang);
                        let sq = if expanded { 2.6 } else { 2.0 };
                        let (rx, ry, psq) = (f2(lx - sq / 2.0), f2(ly - sq / 2.0), f2(sq));
                        let (lx, ly, ang) = (f2(lx), f2(ly), f1(ang));
                        out!(
                            r##"<rect x="{rx}" y="{ry}" width="{psq}" height="{psq}" fill="#F5F2EB" transform="rotate({ang} {lx} {ly})"/>"##
                        );
                    }
                }

                let num_fs = pick(9.8, 7.4);
                for (ang, num) in [0.0, 120.0, 240.0].into_iter().zip(labels) {
                    let (nx, ny) = polar(scx, scy, mid_r, ang);
                    let (nx, ny) = (f2(nx), f2(ny));
                    out!(
                        r##"<text x="{nx}" y="{ny}" fill="#F2F6F9" font-family="Helvetica Neue, Arial, sans-serif" font-size="{num_fs}" font-weight="700" text-anchor="middle" dominant-baseline="central">{num}</text>"##
                    );
                }
            } else {
                // True #000000 OLED Black inside subdials with thin Chromalight rings
                out!(
                    r##"<circle cx="{pscx}" cy="{pscy}" r="{pouter}" fill="#000000" stroke="#2B5D6E" stroke-width="0.9" stroke-opacity="0.75"/>"##
                );
                out!(
                    r##"<circle cx="{pscx}" cy="{pscy}" r="{pinner}" fill="#000000" stroke="#3A7C91" stroke-width="0.8" stroke-opacity="0.65"/>"##
                );
            }
        }
    }

    // 7. Recessed Apertures for World Clock, Sunrise, and Date
    if !ambient {
        // Integers, as in the Python; `/ 2` there is true division (a float).
        let sel = |a: i32, b: i32| if expanded { a } else { b };
        let half = |v: i32| py_repr(f64::from(v) / 2.0);
        let neg_half = |v: i32| py_repr(f64::from(-v) / 2.0);
        let (cap_y, cap_w, cap_h) = (sel(150, 166), sel(114, 96), sel(24, 18));
        let (solar_cx, solar_cy, solar_w, solar_h) =
            (sel(124, 138), sel(320, 294), sel(60, 52), sel(24, 20));
        let (date_cx, date_cy, date_w, date_h) =
            (sel(326, 312), sel(320, 294), sel(58, 50), sel(24, 21));
        let date_in_w = sel(53, 45);
        let date_in_h: f64 = if expanded { 19.4 } else { 16.4 };
        let swiss_y = sel(403, 381);
        let cap_fill = theme.capsule_fill;
        let (cap_x, cap_yy, cap_rx) = (neg_half(cap_w), neg_half(cap_h), half(cap_h));
        let (solar_x, solar_y, solar_rx) = (neg_half(solar_w), neg_half(solar_h), half(solar_h));
        let (date_x, date_y) = (neg_half(date_w), neg_half(date_h));
        let (date_in_x, date_in_y) = (neg_half(date_in_w), py_repr(-date_in_h / 2.0));
        let pdate_in_h = py_repr(date_in_h);
        out!(
            r##"
        <!-- Top GMT / World Clock curved capsule under COSMOGRAPH -->
        <g transform="translate(225, {cap_y})">
          <rect x="{cap_x}" y="{cap_yy}" width="{cap_w}" height="{cap_h}" rx="{cap_rx}" fill="{cap_fill}" fill-opacity="0.92" stroke="url(#platinumRim)" stroke-width="0.9"/>
        </g>
        <!-- Left 7:30 Sunrise/Solar capsule (cleanly outside both 9 and 6 subdials) -->
        <g transform="translate({solar_cx}, {solar_cy})">
          <rect x="{solar_x}" y="{solar_y}" width="{solar_w}" height="{solar_h}" rx="{solar_rx}" fill="{cap_fill}" fill-opacity="0.92" stroke="url(#platinumRim)" stroke-width="0.9"/>
        </g>
        <!-- Right 4:30 Platinum Cyclops Date window (cleanly outside both 3 and 6 subdials) -->
        <g transform="translate({date_cx}, {date_cy})">
          <rect x="{date_x}" y="{date_y}" width="{date_w}" height="{date_h}" rx="4" fill="url(#platinumRim)" stroke="#24140C" stroke-width="0.7"/>
          <rect x="{date_in_x}" y="{date_in_y}" width="{date_in_w}" height="{pdate_in_h}" rx="2.5" fill="#F4F8FA"/>
        </g>
        "##
        );
        out!(
            r##"<text x="225" y="{swiss_y}" fill="{text_col}" font-family="Helvetica Neue, Arial, sans-serif" font-size="5.8" font-weight="700" letter-spacing="1.2" text-anchor="middle">SWISS  ♛  MADE</text>"##
        );
    }

    format!(
        r##"<svg xmlns="http://www.w3.org/2000/svg" width="450" height="450" viewBox="0 0 450 450">{s}</svg>"##
    )
}

/// `make_hour_hand_svg(ambient)`.
pub fn hour_hand_svg(ambient: bool) -> &'static str {
    if ambient {
        return r##"<svg xmlns="http://www.w3.org/2000/svg" width="450" height="450" viewBox="0 0 450 450">
          <polygon points="225,114 218.5,126 219.5,246 225,252 230.5,246 231.5,126" fill="#000000" stroke="#7CE8FF" stroke-width="1.3"/>
          <rect x="222.2" y="130" width="5.6" height="76" rx="1.2" fill="#7CE8FF" fill-opacity="0.90"/>
          <circle cx="225" cy="225" r="9.5" fill="#000000" stroke="#7CE8FF" stroke-width="1.2"/>
        </svg>"##;
    }
    r##"<svg xmlns="http://www.w3.org/2000/svg" width="450" height="450" viewBox="0 0 450 450">
      <defs>
        <filter id="handShadow" x="-20%" y="-20%" width="140%" height="140%">
          <feDropShadow dx="1.5" dy="2.5" stdDeviation="2.2" flood-color="#000000" flood-opacity="0.45"/>
        </filter>
      </defs>
      <g filter="url(#handShadow)">
        <polygon points="225,252 219.5,244 221,225 225,225" fill="#E8EEF2"/>
        <polygon points="225,252 230.5,244 229,225 225,225" fill="#8E99A4"/>
        <polygon points="225,114 218.5,126 219.5,225 225,225" fill="#E8EEF2"/>
        <polygon points="225,114 231.5,126 230.5,225 225,225" fill="#8E99A4"/>
        <rect x="222.0" y="130" width="6.0" height="78" rx="1.2" fill="#F7FBFF"/>
        <circle cx="225" cy="225" r="10.5" fill="#E8EEF2" stroke="#4A555E" stroke-width="1.0"/>
      </g>
    </svg>"##
}

/// `make_minute_hand_svg(ambient)`.
pub fn minute_hand_svg(ambient: bool) -> &'static str {
    if ambient {
        return r##"<svg xmlns="http://www.w3.org/2000/svg" width="450" height="450" viewBox="0 0 450 450">
          <polygon points="225,60 220.0,76 220.8,248 225,258 229.2,248 230.0,76" fill="#000000" stroke="#7CE8FF" stroke-width="1.3"/>
          <rect x="222.5" y="78" width="5.0" height="126" rx="1.2" fill="#7CE8FF" fill-opacity="0.90"/>
          <circle cx="225" cy="225" r="8.0" fill="#000000" stroke="#7CE8FF" stroke-width="1.2"/>
        </svg>"##;
    }
    r##"<svg xmlns="http://www.w3.org/2000/svg" width="450" height="450" viewBox="0 0 450 450">
      <defs>
        <filter id="minShadow" x="-20%" y="-20%" width="140%" height="140%">
          <feDropShadow dx="2.0" dy="3.0" stdDeviation="2.5" flood-color="#000000" flood-opacity="0.48"/>
        </filter>
      </defs>
      <g filter="url(#minShadow)">
        <polygon points="225,258 220.2,248 221.5,225 225,225" fill="#F0F4F8"/>
        <polygon points="225,258 229.8,248 228.5,225 225,225" fill="#838E99"/>
        <polygon points="225,60 220.0,76 220.8,225 225,225" fill="#F0F4F8"/>
        <polygon points="225,60 230.0,76 229.2,225 225,225" fill="#838E99"/>
        <rect x="222.4" y="78" width="5.2" height="128" rx="1.2" fill="#F7FBFF"/>
        <circle cx="225" cy="225" r="8.5" fill="#F0F4F8" stroke="#3F4850" stroke-width="1.0"/>
      </g>
    </svg>"##
}

/// `make_second_hand_svg()`.
pub const SECOND_HAND_SVG: &str = r##"<svg xmlns="http://www.w3.org/2000/svg" width="450" height="450" viewBox="0 0 450 450">
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
    </svg>"##;

/// `make_subdial_hand_svg()`: 88x88, centred at (44, 44), pointing up.
pub const SUBDIAL_HAND_SVG: &str = r##"<svg xmlns="http://www.w3.org/2000/svg" width="88" height="88" viewBox="0 0 88 88">
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
    </svg>"##;

/// `make_subdial_hand_expanded_svg()`: 120x120, centred at (60, 60).
pub const SUBDIAL_HAND_EXPANDED_SVG: &str = r##"<svg xmlns="http://www.w3.org/2000/svg" width="120" height="120" viewBox="0 0 120 120">
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
    </svg>"##;

/// `make_unread_badge_svg()`: a 24x24 ruby jewel in a platinum collet.
pub const UNREAD_BADGE_SVG: &str = r##"<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">
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
    </svg>"##;

const PREVIEW_EXTRA: &str = r##"
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
    </svg>"##;

/// `make_preview_svg()`: the expanded platinum dial with sample hands and
/// complication text drawn on.
pub fn preview_svg() -> String {
    let base = dial_svg(false, true, &PLATINUM, false).replace("</svg>", "");
    base + PREVIEW_EXTRA
}

// --- The asset list ----------------------------------------------------------

/// One PNG to render: the SVG it comes from, its file name and its size.
#[derive(Debug, Clone, PartialEq)]
pub struct Asset {
    pub svg_name: String,
    pub png_name: String,
    pub size: u32,
    pub svg: String,
}

/// `dial_variants` in the Python: (name, ambient, expanded, theme, ultra_aod).
pub const DIAL_VARIANTS: [(&str, bool, bool, &str, bool); 12] = [
    ("dial_interactive", false, false, "platinum", false),
    ("dial_ambient", true, false, "platinum", false),
    ("dial_ultra_ambient", true, false, "platinum", true),
    ("dial_expanded_interactive", false, true, "platinum", false),
    ("dial_expanded_ambient", true, true, "platinum", false),
    ("dial_expanded_ultra_ambient", true, true, "platinum", true),
    ("dial_panda_interactive", false, false, "panda", false),
    (
        "dial_panda_expanded_interactive",
        false,
        true,
        "panda",
        false,
    ),
    (
        "dial_revpanda_interactive",
        false,
        false,
        "reverse_panda",
        false,
    ),
    (
        "dial_revpanda_expanded_interactive",
        false,
        true,
        "reverse_panda",
        false,
    ),
    ("dial_lemans_interactive", false, false, "lemans", false),
    (
        "dial_lemans_expanded_interactive",
        false,
        true,
        "lemans",
        false,
    ),
];

fn asset(svg_name: &str, png_name: &str, size: u32, svg: String) -> Asset {
    Asset {
        svg_name: svg_name.to_string(),
        png_name: png_name.to_string(),
        size,
        svg,
    }
}

/// Every PNG the Python writes, in the order it writes them (22: 12 dials,
/// 5 hands, 2 subdial hands, the unread badge and two previews).
pub fn assets() -> Vec<Asset> {
    let mut out = Vec::with_capacity(22);
    for &(name, ambient, expanded, theme_key, ultra) in &DIAL_VARIANTS {
        let t = theme(theme_key).expect("DIAL_VARIANTS names known themes");
        out.push(asset(
            &format!("{name}.svg"),
            &format!("{name}.png"),
            450,
            dial_svg(ambient, expanded, t, ultra),
        ));
    }
    let preview = preview_svg();
    out.extend([
        asset(
            "hand_hour.svg",
            "hand_hour.png",
            450,
            hour_hand_svg(false).into(),
        ),
        asset(
            "hand_hour_aod.svg",
            "hand_hour_aod.png",
            450,
            hour_hand_svg(true).into(),
        ),
        asset(
            "hand_minute.svg",
            "hand_minute.png",
            450,
            minute_hand_svg(false).into(),
        ),
        asset(
            "hand_minute_aod.svg",
            "hand_minute_aod.png",
            450,
            minute_hand_svg(true).into(),
        ),
        asset(
            "hand_second.svg",
            "hand_second.png",
            450,
            SECOND_HAND_SVG.into(),
        ),
        asset(
            "subdial_hand.svg",
            "subdial_hand.png",
            88,
            SUBDIAL_HAND_SVG.into(),
        ),
        asset(
            "subdial_hand_expanded.svg",
            "subdial_hand_expanded.png",
            120,
            SUBDIAL_HAND_EXPANDED_SVG.into(),
        ),
        asset(
            "unread_badge.svg",
            "unread_badge.png",
            24,
            UNREAD_BADGE_SVG.into(),
        ),
        asset("preview.svg", "preview.png", 450, preview.clone()),
        asset("preview.svg", "preview_circular.png", 450, preview),
    ]);
    out
}

// --- Command line ------------------------------------------------------------

#[derive(Debug, PartialEq, Eq)]
pub enum Cli {
    Help,
    Run { out_dir: Option<PathBuf> },
}

/// Parse the arguments after the program name. `Err` is the message for a
/// usage error (exit 2).
pub fn parse_args<I: IntoIterator<Item = String>>(args: I) -> Result<Cli, String> {
    let mut out_dir = None;
    let mut it = args.into_iter();
    while let Some(arg) = it.next() {
        match arg.as_str() {
            "-h" | "--help" => return Ok(Cli::Help),
            "--out-dir" => match it.next() {
                Some(v) if !v.is_empty() => out_dir = Some(PathBuf::from(v)),
                _ => return Err("argument --out-dir: expected one argument".into()),
            },
            _ => {
                if let Some(v) = arg.strip_prefix("--out-dir=") {
                    if v.is_empty() {
                        return Err("argument --out-dir: expected one argument".into());
                    }
                    out_dir = Some(PathBuf::from(v));
                } else {
                    return Err(format!("unrecognized arguments: {arg}"));
                }
            }
        }
    }
    Ok(Cli::Run { out_dir })
}

/// The Python's DRAWABLE_DIR: under $BUILD_WORKSPACE_DIRECTORY when
/// `bazel run` set it, otherwise relative to the current directory (the
/// Python uses its own file's location; a binary has none to use).
pub fn default_out_dir(build_workspace: Option<&str>) -> PathBuf {
    let rel = Path::new(PACKAGE_REL).join(DRAWABLE_REL);
    match build_workspace {
        Some(ws) if !ws.is_empty() => Path::new(ws).join(rel),
        _ => rel,
    }
}

/// `shutil.which("rsvg-convert") or "/opt/homebrew/bin/rsvg-convert"`.
pub fn find_rsvg(path_var: Option<&str>) -> PathBuf {
    let path_var = path_var.unwrap_or("/bin:/usr/bin");
    for dir in path_var.split(':').filter(|d| !d.is_empty()) {
        let cand = Path::new(dir).join("rsvg-convert");
        if is_executable(&cand) {
            return cand;
        }
    }
    PathBuf::from(RSVG_FALLBACK)
}

fn is_executable(p: &Path) -> bool {
    use std::os::unix::fs::PermissionsExt;
    std::fs::metadata(p)
        .map(|m| m.is_file() && m.permissions().mode() & 0o111 != 0)
        .unwrap_or(false)
}

/// A temporary directory removed on drop.
struct TempDir(PathBuf);

impl TempDir {
    fn new(prefix: &str) -> io::Result<Self> {
        let base = std::env::temp_dir();
        let pid = std::process::id();
        for attempt in 0..1000_u32 {
            let nanos = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.subsec_nanos())
                .unwrap_or(0);
            let p = base.join(format!("{prefix}{pid}_{nanos}_{attempt}"));
            match std::fs::create_dir(&p) {
                Ok(()) => return Ok(TempDir(p)),
                Err(e) if e.kind() == io::ErrorKind::AlreadyExists => continue,
                Err(e) => return Err(e),
            }
        }
        Err(io::Error::new(
            io::ErrorKind::AlreadyExists,
            "no free temp dir name",
        ))
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

/// Write every SVG, then render every PNG into `out_dir` with `rsvg`.
pub fn generate(out_dir: &Path, rsvg: &Path) -> Result<(), String> {
    std::fs::create_dir_all(out_dir)
        .map_err(|e| format!("cannot create {}: {e}", out_dir.display()))?;
    let svg_dir =
        TempDir::new("daytona_svg_").map_err(|e| format!("cannot create temp dir: {e}"))?;
    let assets = assets();
    for a in &assets {
        let p = svg_dir.0.join(&a.svg_name);
        std::fs::write(&p, &a.svg).map_err(|e| format!("cannot write {}: {e}", p.display()))?;
    }
    let results: Vec<Result<(), String>> = std::thread::scope(|scope| {
        let handles: Vec<_> = assets
            .iter()
            .map(|a| {
                let svg_path = svg_dir.0.join(&a.svg_name);
                let png_path = out_dir.join(&a.png_name);
                scope.spawn(move || render(rsvg, &svg_path, &png_path, a.size))
            })
            .collect();
        handles
            .into_iter()
            .map(|h| {
                h.join()
                    .unwrap_or_else(|_| Err("render thread panicked".into()))
            })
            .collect()
    });
    let errors: Vec<String> = results.into_iter().filter_map(Result::err).collect();
    if errors.is_empty() {
        Ok(())
    } else {
        Err(errors.join("\n"))
    }
}

fn render(rsvg: &Path, svg: &Path, png: &Path, size: u32) -> Result<(), String> {
    let size = size.to_string();
    let status = Command::new(rsvg)
        .args(["-w", &size, "-h", &size])
        .arg(svg)
        .arg("-o")
        .arg(png)
        .status()
        .map_err(|e| format!("cannot run {}: {e}", rsvg.display()))?;
    if status.success() {
        Ok(())
    } else {
        Err(format!(
            "{} failed ({status}) rendering {}",
            rsvg.display(),
            png.display()
        ))
    }
}

/// The whole program; returns the exit code.
pub fn run<I: IntoIterator<Item = String>>(args: I) -> i32 {
    match parse_args(args) {
        Ok(Cli::Help) => {
            print!("{HELP}");
            0
        }
        Err(msg) => {
            eprintln!("{USAGE}\ngenerate_assets: error: {msg}");
            2
        }
        Ok(Cli::Run { out_dir }) => {
            let ws = std::env::var("BUILD_WORKSPACE_DIRECTORY").ok();
            let out_dir = out_dir.unwrap_or_else(|| default_out_dir(ws.as_deref()));
            let path_var = std::env::var("PATH").ok();
            let rsvg = find_rsvg(path_var.as_deref());
            match generate(&out_dir, &rsvg) {
                Ok(()) => {
                    println!("{DONE_MESSAGE}");
                    0
                }
                Err(msg) => {
                    eprintln!("generate_assets: {msg}");
                    1
                }
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn py_repr_matches_python() {
        let cases: &[(f64, &str)] = &[
            (225.0, "225.0"),
            (184.0, "184.0"),
            (220.5, "220.5"),
            (0.55, "0.55"),
            (-57.0, "-57.0"),
            (-9.7, "-9.7"),
            (93.5, "93.5"),
            (139.8 - 20.0, "119.80000000000001"),
            (31.0 + 1.2, "32.2"),
            (0.1 + 0.2, "0.30000000000000004"),
            (1e16, "1e+16"),
            (1.5e-5, "1.5e-05"),
            (0.0001, "0.0001"),
            (-0.0, "-0.0"),
            (0.0, "0.0"),
            (123456789012345.0, "123456789012345.0"),
        ];
        for &(x, want) in cases {
            assert_eq!(py_repr(x), want, "repr({x:?})");
        }
    }

    #[test]
    fn fixed_formats_match_python() {
        assert_eq!(f2(225.0), "225.00");
        assert_eq!(f2(-4.6), "-4.60");
        assert_eq!(f2(0.125), "0.12"); // exact tie rounds to even
        assert_eq!(f2(0.375), "0.38");
        assert_eq!(f1(-24.0), "-24.0");
        assert_eq!(f1(0.25), "0.2");
    }

    #[test]
    fn polar_zero_degrees_is_twelve_oclock() {
        let (x, y) = polar(225.0, 225.0, 100.0, 0.0);
        assert!((x - 225.0).abs() < 1e-9);
        assert!((y - 125.0).abs() < 1e-9);
        let (x, y) = polar(225.0, 225.0, 100.0, 90.0);
        assert!((x - 325.0).abs() < 1e-9);
        assert!((y - 225.0).abs() < 1e-9);
    }

    #[test]
    fn themes_resolve() {
        for key in ["platinum", "panda", "reverse_panda", "lemans"] {
            assert!(theme(key).is_some(), "{key}");
        }
        assert!(theme("nope").is_none());
        assert!(LEMANS.paul_newman && LEMANS.red_100);
    }

    #[test]
    fn assets_match_python_list() {
        let a = assets();
        assert_eq!(a.len(), 22);
        let mut names: Vec<_> = a.iter().map(|x| x.png_name.as_str()).collect();
        names.sort_unstable();
        names.dedup();
        assert_eq!(names.len(), 22, "PNG names are unique");
        for x in &a {
            assert!(x
                .svg
                .starts_with("<svg xmlns=\"http://www.w3.org/2000/svg\""));
            assert!(x.svg.ends_with("</svg>"));
            assert!(x.svg.contains(&format!("width=\"{}\"", x.size)));
        }
        let sizes = |n: &str| a.iter().find(|x| x.png_name == n).map(|x| x.size);
        assert_eq!(sizes("subdial_hand.png"), Some(88));
        assert_eq!(sizes("subdial_hand_expanded.png"), Some(120));
        assert_eq!(sizes("unread_badge.png"), Some(24));
    }

    #[test]
    fn dial_variants_differ_where_they_should() {
        let full = dial_svg(false, false, &PLATINUM, false);
        assert!(full.contains("UNITS") || full.contains(">U<"));
        assert!(full.contains("cerachromBezel)"));
        let expanded = dial_svg(false, true, &PLATINUM, false);
        assert!(!expanded.contains("url(#cerachromBezel)"));
        let ultra = dial_svg(true, false, &PLATINUM, true);
        assert!(
            !ultra.contains(">D</text>"),
            "ultra AOD has no DAYTONA text"
        );
        let lemans = dial_svg(false, false, &LEMANS, false);
        assert!(lemans.contains("fill=\"#E62229\""), "red 100 on Le Mans");
        assert!(
            lemans.contains("fill=\"#F5F2EB\" transform"),
            "Paul Newman squares"
        );
    }

    #[test]
    fn preview_is_expanded_dial_plus_extras() {
        let p = preview_svg();
        let base = dial_svg(false, true, &PLATINUM, false);
        assert!(p.starts_with(base.strip_suffix("</svg>").unwrap()));
        assert_eq!(p.matches("</svg>").count(), 1);
        assert!(p.ends_with("    </svg>"));
    }

    #[test]
    fn parse_args_cases() {
        let v = |a: &[&str]| parse_args(a.iter().map(|s| s.to_string()));
        assert_eq!(v(&[]), Ok(Cli::Run { out_dir: None }));
        assert_eq!(v(&["-h"]), Ok(Cli::Help));
        assert_eq!(v(&["--help"]), Ok(Cli::Help));
        assert_eq!(
            v(&["--out-dir", "/x"]),
            Ok(Cli::Run {
                out_dir: Some("/x".into())
            })
        );
        assert_eq!(
            v(&["--out-dir=/y"]),
            Ok(Cli::Run {
                out_dir: Some("/y".into())
            })
        );
        assert!(v(&["--out-dir"]).is_err());
        assert!(v(&["--out-dir="]).is_err());
        assert!(v(&["--bogus"]).is_err());
        assert!(v(&["positional"]).is_err());
    }

    #[test]
    fn default_out_dir_follows_build_workspace() {
        assert_eq!(
            default_out_dir(Some("/ws")),
            PathBuf::from(
                "/ws/apps/mobile/wearos/faces/daytona-platinum/src/main/res/drawable-nodpi"
            )
        );
        assert_eq!(
            default_out_dir(None),
            PathBuf::from("apps/mobile/wearos/faces/daytona-platinum/src/main/res/drawable-nodpi")
        );
        assert_eq!(default_out_dir(Some("")), default_out_dir(None));
    }

    #[test]
    fn find_rsvg_falls_back() {
        assert_eq!(
            find_rsvg(Some("/definitely/not/here")),
            PathBuf::from(RSVG_FALLBACK)
        );
        assert_eq!(find_rsvg(Some("")), PathBuf::from(RSVG_FALLBACK));
    }

    #[test]
    fn generate_reports_renderer_failure() {
        let out = TempDir::new("daytona_test_out_").unwrap();
        let err = generate(&out.0, Path::new("/definitely/not/rsvg-convert")).unwrap_err();
        assert!(err.contains("cannot run"), "{err}");
    }
}
