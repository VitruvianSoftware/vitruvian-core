// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

//! Generate Vitruvian's placeholder brand masters (`logo.png`,
//! `AppIcon-Default.png`, `AppIcon.icon/Assets/vitruvian-mark.svg`, and
//! `AppIcon.icon/icon.json`).
//!
//! Native Rust counterpart to `Resources/Brand/make_placeholder_brand.py`.

use std::env;
use std::ffi::{c_int, c_ulong};
use std::fs;
use std::path::{Path, PathBuf};

pub const SIZE: usize = 1024;
pub const RADIUS: f64 = 300.0;
pub const STROKE: f64 = 64.0;
pub const CENTER: (f64, f64) = (512.0, 452.0);
pub const SIDE: f64 = 2.0 * RADIUS * 0.85;
pub const BOTTOM: f64 = CENTER.1 + RADIUS;
pub const SQUARE_CENTER: (f64, f64) = (CENTER.0, BOTTOM - SIDE / 2.0);

#[link(name = "z")]
extern "C" {
    fn compress2(
        dest: *mut u8,
        dest_len: *mut c_ulong,
        source: *const u8,
        source_len: c_ulong,
        level: c_int,
    ) -> c_int;
}

#[inline]
pub fn clamp(x: f64, lo: f64, hi: f64) -> f64 {
    if x < lo {
        lo
    } else if x > hi {
        hi
    } else {
        x
    }
}

#[inline]
pub fn box_sdf(px: f64, py: f64, cx: f64, cy: f64, hw: f64, hh: f64, r: f64) -> f64 {
    let qx = (px - cx).abs() - (hw - r);
    let qy = (py - cy).abs() - (hh - r);
    let outside = qx.max(0.0).hypot(qy.max(0.0));
    outside + qx.max(qy).min(0.0) - r
}

#[inline]
pub fn mark_distance(px: f64, py: f64, scale: f64, origin: (f64, f64)) -> f64 {
    let x = origin.0 + (px - origin.0) / scale;
    let y = origin.1 + (py - origin.1) / scale;
    let ring = ((x - CENTER.0).hypot(y - CENTER.1) - RADIUS).abs() - STROKE / 2.0;
    let square = box_sdf(
        x,
        y,
        SQUARE_CENTER.0,
        SQUARE_CENTER.1,
        SIDE / 2.0,
        SIDE / 2.0,
        0.0,
    )
    .abs()
        - STROKE / 2.0;
    ring.min(square) * scale
}

pub fn crc32_ieee(data: &[u8]) -> u32 {
    let mut crc: u32 = 0xFFFF_FFFF;
    for &b in data {
        crc ^= b as u32;
        for _ in 0..8 {
            if (crc & 1) != 0 {
                crc = (crc >> 1) ^ 0xEDB8_8320;
            } else {
                crc >>= 1;
            }
        }
    }
    !crc
}

pub fn zlib_compress_level9(raw: &[u8]) -> Vec<u8> {
    let bound = raw.len() + (raw.len() >> 12) + (raw.len() >> 14) + (raw.len() >> 25) + 13;
    let mut out = vec![0u8; bound];
    let mut dest_len = bound as c_ulong;
    let rc = unsafe {
        compress2(
            out.as_mut_ptr(),
            &mut dest_len,
            raw.as_ptr(),
            raw.len() as c_ulong,
            9,
        )
    };
    assert_eq!(rc, 0, "zlib compress2 failed with code {}", rc);
    out.truncate(dest_len as usize);
    out
}

fn png_chunk(kind: &[u8; 4], data: &[u8]) -> Vec<u8> {
    let mut buf = Vec::with_capacity(12 + data.len());
    buf.extend_from_slice(&(data.len() as u32).to_be_bytes());
    buf.extend_from_slice(kind);
    buf.extend_from_slice(data);
    let crc = crc32_ieee(&buf[4..]);
    buf.extend_from_slice(&crc.to_be_bytes());
    buf
}

pub fn encode_png(size: usize, rows: &[Vec<u8>]) -> Vec<u8> {
    let mut raw = Vec::with_capacity(size * (1 + size * 4));
    for row in rows {
        raw.push(0u8);
        raw.extend_from_slice(row);
    }

    let mut header = Vec::with_capacity(13);
    header.extend_from_slice(&(size as u32).to_be_bytes());
    header.extend_from_slice(&(size as u32).to_be_bytes());
    header.extend_from_slice(&[8u8, 6u8, 0u8, 0u8, 0u8]);

    let compressed = zlib_compress_level9(&raw);
    let mut png = Vec::new();
    png.extend_from_slice(b"\x89PNG\r\n\x1a\n");
    png.extend_from_slice(&png_chunk(b"IHDR", &header));
    png.extend_from_slice(&png_chunk(b"IDAT", &compressed));
    png.extend_from_slice(&png_chunk(b"IEND", b""));
    png
}

pub fn write_png(path: &Path, rows: &[Vec<u8>]) -> Result<(), String> {
    let bytes = encode_png(SIZE, rows);
    fs::write(path, bytes).map_err(|e| format!("failed to write {}: {}", path.display(), e))
}

#[inline]
pub fn round_half_to_even(x: f64) -> f64 {
    let r = x.round();
    if (x - r).abs() == 0.5 && (r as i64) % 2 != 0 {
        x - (r - x)
    } else {
        r
    }
}

pub fn render_logo_with_size(size: usize) -> Vec<Vec<u8>> {
    let mut rows = Vec::with_capacity(size);
    for j in 0..size {
        let mut row = vec![0u8; size * 4];
        let py = j as f64 + 0.5;
        for i in 0..size {
            let a = clamp(
                0.5 - mark_distance(i as f64 + 0.5, py, 1.0, (512.0, 512.0)),
                0.0,
                1.0,
            );
            if a != 0.0 {
                row[i * 4 + 3] = round_half_to_even(a * 255.0) as u8;
            }
        }
        rows.push(row);
    }
    rows
}

pub fn render_logo() -> Vec<Vec<u8>> {
    render_logo_with_size(SIZE)
}

pub fn render_icon_with_size(size: usize) -> Vec<Vec<u8>> {
    let half = 412.0;
    let corner = 185.0;
    let top = [36.0, 76.0, 140.0];
    let bottom = [12.0, 28.0, 62.0];
    let mut rows = Vec::with_capacity(size);

    for j in 0..size {
        let mut row = vec![0u8; size * 4];
        let py = j as f64 + 0.5;
        let t = clamp((py - 100.0) / 824.0, 0.0, 1.0);
        let bg = [
            top[0] + (bottom[0] - top[0]) * t,
            top[1] + (bottom[1] - top[1]) * t,
            top[2] + (bottom[2] - top[2]) * t,
        ];
        for i in 0..size {
            let px = i as f64 + 0.5;
            let d = box_sdf(px, py, 512.0, 512.0, half, half, corner);
            let shape = clamp(0.5 - d, 0.0, 1.0);
            let shadow = 0.32
                * clamp(
                    1.0 - box_sdf(px, py - 10.0, 512.0, 512.0, half, half, corner).max(0.0) / 28.0,
                    0.0,
                    1.0,
                );
            let mark = clamp(0.5 - mark_distance(px, py, 0.62, (512.0, 512.0)), 0.0, 1.0) * shape;
            let alpha = shape + shadow * (1.0 - shape);
            if alpha <= 0.0 {
                continue;
            }
            let o = i * 4;
            for k in 0..3 {
                let c_bg = (bg[k] * shape) / alpha;
                let c = c_bg * (1.0 - mark) + 255.0 * mark;
                row[o + k] = round_half_to_even(clamp(c, 0.0, 255.0)) as u8;
            }
            row[o + 3] = round_half_to_even(alpha * 255.0) as u8;
        }
        rows.push(row);
    }
    rows
}

pub fn render_icon() -> Vec<Vec<u8>> {
    render_icon_with_size(SIZE)
}

pub fn mark_svg() -> String {
    let s = STROKE;
    let x0 = SQUARE_CENTER.0 - SIDE / 2.0;
    let y0 = SQUARE_CENTER.1 - SIDE / 2.0;
    let left = CENTER.0 - RADIUS - s / 2.0;
    let right = CENTER.0 + RADIUS + s / 2.0;
    let top = CENTER.1 - RADIUS - s / 2.0;
    let bottom = BOTTOM + s / 2.0;
    let w = right - left;
    let h = bottom - top;
    format!(
        r##"<?xml version="1.0" encoding="UTF-8"?>
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- Copyright (C) 2026 VitruvianSoftware. Golden-Datum V mark; see make_placeholder_brand.py. -->
<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="{left} {top} {w} {h}">
  <g fill="none" stroke="#000" stroke-width="{s}">
    <circle cx="{cx}" cy="{cy}" r="{r}"/>
    <rect x="{x0}" y="{y0}" width="{side}" height="{side}"/>
    <line x1="257" y1="368" x2="767" y2="368" stroke-width="44"/>
    <path d="M294 260L{cx} {bottom_pt}L730 260" stroke-linecap="square" stroke-linejoin="miter"/>
    <circle cx="{cx}" cy="{cy}" r="42" fill="#d47657" stroke="none"/>
  </g>
</svg>
"##,
        w = w,
        h = h,
        left = left,
        top = top,
        s = s,
        cx = CENTER.0,
        cy = CENTER.1,
        r = RADIUS,
        x0 = x0,
        y0 = y0,
        side = SIDE,
        bottom_pt = BOTTOM,
    )
}

pub fn icon_composer_project_json() -> &'static str {
    r#"{
  "fill-specializations": [
    {
      "value": {
        "linear-gradient": [
          "srgb:0.14118,0.29804,0.54902,1.00000",
          "srgb:0.04706,0.10980,0.24314,1.00000"
        ]
      }
    }
  ],
  "groups": [
    {
      "layers": [
        {
          "fill": {
            "solid": "srgb:1.00000,1.00000,1.00000,1.00000"
          },
          "image-name": "vitruvian-mark.svg",
          "name": "VitruvianMark",
          "position": {
            "scale": 1.0,
            "translation-in-points": [
              0,
              0
            ]
          }
        }
      ],
      "name": "Mark",
      "shadow": {
        "kind": "neutral",
        "opacity": 0.5
      }
    }
  ],
  "supported-platforms": {
    "squares": [
      "macOS"
    ]
  }
}
"#
}

pub fn generate_brand_assets(out_dir: &Path) -> Result<(), String> {
    fs::create_dir_all(out_dir)
        .map_err(|e| format!("failed to create {}: {}", out_dir.display(), e))?;
    write_png(&out_dir.join("logo.png"), &render_logo())?;
    write_png(&out_dir.join("AppIcon-Default.png"), &render_icon())?;
    let project = out_dir.join("AppIcon.icon");
    let assets = project.join("Assets");
    fs::create_dir_all(&assets)
        .map_err(|e| format!("failed to create {}: {}", assets.display(), e))?;
    fs::write(assets.join("vitruvian-mark.svg"), mark_svg())
        .map_err(|e| format!("failed to write vitruvian-mark.svg: {}", e))?;
    fs::write(project.join("icon.json"), icon_composer_project_json())
        .map_err(|e| format!("failed to write icon.json: {}", e))?;
    Ok(())
}

pub fn run_cli(args: &[String]) -> i32 {
    let mut out_dir: Option<PathBuf> = None;
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--out-dir" => {
                i += 1;
                if i >= args.len() {
                    eprintln!("--out-dir requires a value");
                    return 2;
                }
                out_dir = Some(PathBuf::from(&args[i]));
            }
            "-h" | "--help" => {
                eprintln!("usage: make_placeholder_brand [--out-dir <folder>]");
                return 2;
            }
            other => {
                eprintln!("unknown argument: {}", other);
                return 2;
            }
        }
        i += 1;
    }

    let dir = out_dir.unwrap_or_else(|| {
        if let Ok(ws) = env::var("BUILD_WORKSPACE_DIRECTORY") {
            PathBuf::from(ws).join("apps/desktop/vitruvian/Resources/Brand")
        } else {
            PathBuf::from("apps/desktop/vitruvian/Resources/Brand")
        }
    });

    match generate_brand_assets(&dir) {
        Ok(()) => 0,
        Err(e) => {
            eprintln!("{}", e);
            1
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_svg_and_icon_json_match_committed_brand_assets() {
        let brand_dir = Path::new("apps/desktop/vitruvian/Resources/Brand");
        if brand_dir.join("AppIcon.icon/icon.json").exists() {
            let committed_json =
                fs::read_to_string(brand_dir.join("AppIcon.icon/icon.json")).unwrap();
            assert_eq!(icon_composer_project_json(), committed_json);
        }
        if brand_dir
            .join("AppIcon.icon/Assets/vitruvian-mark.svg")
            .exists()
        {
            let committed_svg =
                fs::read_to_string(brand_dir.join("AppIcon.icon/Assets/vitruvian-mark.svg"))
                    .unwrap();
            assert_eq!(mark_svg(), committed_svg);
        }
    }

    #[test]
    fn test_sdf_and_png_encoding() {
        assert_eq!(clamp(-1.0, 0.0, 1.0), 0.0);
        assert_eq!(clamp(2.0, 0.0, 1.0), 1.0);
        assert_eq!(clamp(0.5, 0.0, 1.0), 0.5);

        // Center of the circle is at (512, 452), radius 300 -> distance from ring at (512, 152) is -STROKE/2 = -32
        let d_ring = mark_distance(512.0, 152.0, 1.0, (512.0, 512.0));
        assert!((d_ring - (-32.0)).abs() < 1e-9);

        // Encode a small 16x16 PNG and verify valid PNG signature, IHDR, IDAT, IEND chunks
        let rows = vec![vec![0u8; 16 * 4]; 16];
        let png = encode_png(16, &rows);
        assert!(png.starts_with(b"\x89PNG\r\n\x1a\n"));
        assert!(png.ends_with(b"IEND\xae\x42\x60\x82"));
    }
}
