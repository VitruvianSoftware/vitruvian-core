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
// SPDX-License-Identifier: MIT

//! Turn a V1 vacuum's map (the `get_map_v1` reply) into a PNG.
//!
//! A port of what python-roborock 7.12.1 does with its default
//! `MapParserConfig` (`roborock/map/map_parser.py`): parse the blocks with
//! vacuum-map-parser-roborock 0.1.5's `RoborockMapDataParser`, colour the
//! floor plan with vacuum-map-parser-base 0.1.5's default palette (rooms in
//! the room colours, walls, carpets, removed areas), scale it 4x with
//! nearest-neighbour, then draw the charger, the cleaning path and the
//! vacuum. Pillow's anti-aliasing is not reproduced pixel for pixel; the
//! shapes, sizes, colours and layering are.

use std::f64::consts::PI;

pub const SCALE: u32 = 4;
const VACUUM_RADIUS: f64 = 6.0 * SCALE as f64;
const CHARGER_RADIUS: f64 = 6.0 * SCALE as f64;
const PATH_WIDTH: f64 = 1.0 * SCALE as f64;

type Rgba = [u8; 4];

const MAP_OUTSIDE: Rgba = [19, 87, 148, 255];
const MAP_INSIDE: Rgba = [32, 115, 185, 255];
const MAP_WALL: Rgba = [100, 196, 254, 255];
const MAP_WALL_V2: Rgba = [93, 109, 126, 255];
const GREY_WALL: Rgba = [93, 109, 126, 255];
const CARPETS: Rgba = [0xA9, 0xF7, 0xA9, 255];
const SCAN: Rgba = [0xDF, 0xDF, 0xDF, 255];
const UNKNOWN: Rgba = [0, 0, 0, 255];
const PATH: Rgba = [147, 194, 238, 255];
const CHARGER: Rgba = [0x66, 0xFE, 0xDA, 0x7F];
const ROBO: Rgba = [0xFF, 0xFF, 0xFF, 255];
const ROBO_OUTLINE: Rgba = [0, 0, 0, 255];

const ROOM_COLORS: [[u8; 3]; 32] = [
    [240, 178, 122],
    [133, 193, 233],
    [217, 136, 128],
    [52, 152, 219],
    [205, 97, 85],
    [243, 156, 18],
    [88, 214, 141],
    [245, 176, 65],
    [252, 212, 81],
    [72, 201, 176],
    [84, 153, 199],
    [133, 193, 233],
    [245, 176, 65],
    [82, 190, 128],
    [72, 201, 176],
    [165, 105, 189],
    [240, 178, 122],
    [133, 193, 233],
    [217, 136, 128],
    [52, 152, 219],
    [205, 97, 85],
    [243, 156, 18],
    [88, 214, 141],
    [245, 176, 65],
    [252, 212, 81],
    [72, 201, 176],
    [84, 153, 199],
    [133, 193, 233],
    [245, 176, 65],
    [82, 190, 128],
    [72, 201, 176],
    [165, 105, 189],
];

fn room_color(room: u32) -> Rgba {
    // Rooms 1..=32 index the table; 0 (and anything past 32) wraps like
    // ColorsPalette.get_room_color.
    let n = ROOM_COLORS.len() as i64;
    let mut id = room as i64;
    if id > n || id < 1 {
        id = (id - 1).rem_euclid(n) + 1;
    }
    let c = ROOM_COLORS[(id - 1) as usize];
    [c[0], c[1], c[2], 255]
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MapError(pub String);

impl std::fmt::Display for MapError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Point {
    pub x: f64,
    pub y: f64,
    pub a: Option<f64>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ImageBlock {
    pub top: i64,
    pub left: i64,
    pub height: usize,
    pub width: usize,
    pub pixels: Vec<u8>,
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct MapData {
    pub image: Option<ImageBlock>,
    pub charger: Option<Point>,
    pub vacuum: Option<Point>,
    pub path: Vec<Point>,
    pub carpet: Vec<bool>,
    pub removed: Vec<bool>,
}

fn u16_at(d: &[u8], at: usize) -> Result<u32, MapError> {
    d.get(at..at + 2)
        .map(|b| u16::from_le_bytes([b[0], b[1]]) as u32)
        .ok_or_else(|| MapError("Failed to parse map data".into()))
}

fn u32_at(d: &[u8], at: usize) -> Result<u32, MapError> {
    d.get(at..at + 4)
        .map(|b| u32::from_le_bytes([b[0], b[1], b[2], b[3]]))
        .ok_or_else(|| MapError("Failed to parse map data".into()))
}

fn bytes_at(d: &[u8], start: usize, len: usize) -> &[u8] {
    let s = start.min(d.len());
    let e = start.saturating_add(len).min(d.len());
    &d[s..e]
}

fn object_position(len: usize, data: &[u8]) -> Result<Point, MapError> {
    let x = u32_at(data, 0)? as f64;
    let y = u32_at(data, 4)? as f64;
    let mut a = None;
    if len > 8 {
        let mut v = u32_at(data, 8)? as i64;
        if v > 0xFF {
            v = (v & 0xFF) - 256;
        }
        a = Some(v as f64);
    }
    Ok(Point { x, y, a })
}

/// `RoborockMapDataParser.parse`, for the blocks the default drawing uses.
pub fn parse(raw: &[u8]) -> Result<MapData, MapError> {
    let mut map = MapData::default();
    let mut pos = u16_at(raw, 0x02)? as usize;
    while pos < raw.len() {
        let header_len = u16_at(raw, pos + 0x02)? as usize;
        let header = bytes_at(raw, pos, header_len);
        let block_type = u16_at(header, 0x00)?;
        let data_len = u32_at(header, 0x04)? as usize;
        let data_start = pos + header_len;
        let data = bytes_at(raw, data_start, data_len);
        match block_type {
            1 => map.charger = Some(object_position(data_len, data)?),
            2 => {
                map.image = Some(ImageBlock {
                    top: u32_at(header, header_len - 16)? as i64,
                    left: u32_at(header, header_len - 12)? as i64,
                    height: u32_at(header, header_len - 8)? as usize,
                    width: u32_at(header, header_len - 4)? as usize,
                    pixels: data.to_vec(),
                })
            }
            3 => {
                // Path points start right after the 0x14-byte header; the
                // header's data length is the byte length of the points.
                let start = pos + 0x14;
                let mut points = Vec::new();
                let mut p = start;
                while p < start + data_len {
                    points.push(Point {
                        x: u16_at(raw, p)? as f64,
                        y: u16_at(raw, p + 2)? as f64,
                        a: None,
                    });
                    p += 4;
                }
                map.path = points;
            }
            8 => map.vacuum = Some(object_position(data_len, data)?),
            17 => {
                map.carpet = data.iter().map(|v| v & 1 != 0).collect();
                map.removed = data.iter().map(|v| v & (8 | 16) != 0).collect();
            }
            _ => {}
        }
        // The Python parser advances by the header length read as one byte.
        let step = data_len + header.get(2).copied().unwrap_or(0) as usize;
        if step == 0 {
            break;
        }
        pos += step;
    }
    Ok(map)
}

struct Canvas {
    w: usize,
    h: usize,
    px: Vec<Rgba>,
}

impl Canvas {
    fn new(w: usize, h: usize, fill: Rgba) -> Self {
        Self {
            w,
            h,
            px: vec![fill; w * h],
        }
    }

    fn get(&self, x: usize, y: usize) -> Rgba {
        self.px[y * self.w + x]
    }

    fn put(&mut self, x: i64, y: i64, c: Rgba) {
        if x >= 0 && y >= 0 && (x as usize) < self.w && (y as usize) < self.h {
            let i = y as usize * self.w + x as usize;
            self.px[i] = c;
        }
    }

    /// `Image.alpha_composite(self, layer)`.
    fn composite(&mut self, layer: &Canvas) {
        for (dst, src) in self.px.iter_mut().zip(layer.px.iter()) {
            let sa = src[3] as f64 / 255.0;
            if sa == 0.0 {
                continue;
            }
            let da = dst[3] as f64 / 255.0;
            let oa = sa + da * (1.0 - sa);
            for i in 0..3 {
                let v = (src[i] as f64 * sa + dst[i] as f64 * da * (1.0 - sa)) / oa;
                dst[i] = v.round().clamp(0.0, 255.0) as u8;
            }
            dst[3] = (oa * 255.0).round() as u8;
        }
    }

    fn ellipse(&mut self, cx: f64, cy: f64, r: f64, outline: Option<Rgba>, fill: Option<Rgba>) {
        let (x0, x1) = ((cx - r).floor() as i64, (cx + r).ceil() as i64);
        let (y0, y1) = ((cy - r).floor() as i64, (cy + r).ceil() as i64);
        for y in y0..=y1 {
            for x in x0..=x1 {
                let d = ((x as f64 - cx).powi(2) + (y as f64 - cy).powi(2)).sqrt();
                if d > r {
                    continue;
                }
                if d > r - 1.0 {
                    if let Some(c) = outline {
                        self.put(x, y, c);
                        continue;
                    }
                }
                if let Some(c) = fill {
                    self.put(x, y, c);
                }
            }
        }
    }

    /// Pillow's pieslice: angles in degrees, clockwise from 3 o'clock.
    fn pieslice(&mut self, cx: f64, cy: f64, r: f64, start: f64, end: f64, c: Rgba) {
        let norm = |a: f64| a.rem_euclid(360.0);
        let (s, mut e) = (norm(start), norm(end));
        if e <= s {
            e += 360.0;
        }
        for y in (cy - r).floor() as i64..=(cy + r).ceil() as i64 {
            for x in (cx - r).floor() as i64..=(cx + r).ceil() as i64 {
                let (dx, dy) = (x as f64 - cx, y as f64 - cy);
                if (dx * dx + dy * dy).sqrt() > r {
                    continue;
                }
                let mut ang = norm(dy.atan2(dx).to_degrees());
                if ang < s {
                    ang += 360.0;
                }
                if ang <= e {
                    self.put(x, y, c);
                }
            }
        }
    }

    /// A straight segment `width` pixels thick, flat-ended, like ImageDraw.line.
    fn line(&mut self, x0: f64, y0: f64, x1: f64, y1: f64, width: f64, c: Rgba) {
        let half = (width / 2.0).max(0.5);
        let (dx, dy) = (x1 - x0, y1 - y0);
        let len2 = dx * dx + dy * dy;
        let minx = x0.min(x1) - half;
        let maxx = x0.max(x1) + half;
        let miny = y0.min(y1) - half;
        let maxy = y0.max(y1) + half;
        for y in miny.floor() as i64..=maxy.ceil() as i64 {
            for x in minx.floor() as i64..=maxx.ceil() as i64 {
                let (px, py) = (x as f64, y as f64);
                let t = if len2 == 0.0 {
                    0.0
                } else {
                    ((px - x0) * dx + (py - y0) * dy) / len2
                };
                if !(0.0..=1.0).contains(&t) {
                    continue;
                }
                let (qx, qy) = (x0 + t * dx, y0 + t * dy);
                if ((px - qx).powi(2) + (py - qy).powi(2)).sqrt() <= half {
                    self.put(x, y, c);
                }
            }
        }
    }
}

struct Dims {
    top: f64,
    left: f64,
    height: f64,
}

impl Dims {
    /// `ImageDimensions.to_img` after `_map_to_image` (map units are 1/50 px).
    fn to_img(&self, p: Point) -> (f64, f64) {
        let (x, y) = (p.x / 50.0, p.y / 50.0);
        (
            (x - self.left) * SCALE as f64,
            (self.height - (y - self.top) - 1.0) * SCALE as f64,
        )
    }
}

fn floor_plan(map: &MapData, img: &ImageBlock) -> Canvas {
    let (w, h) = (img.width, img.height);
    let mut c = Canvas::new(w, h, [0, 0, 0, 0]);
    for img_y in 0..h {
        for img_x in 0..w {
            let idx = img_x + w * img_y;
            let pixel = img.pixels.get(idx).copied().unwrap_or(0);
            let (x, y) = (img_x, h - img_y - 1);
            let color = if map.removed.get(idx).copied().unwrap_or(false) {
                MAP_OUTSIDE
            } else if map.carpet.get(idx).copied().unwrap_or(false) && (x + y) % 2 == 1 {
                CARPETS
            } else {
                match pixel {
                    0x00 => MAP_OUTSIDE,
                    0x01 => MAP_WALL,
                    0xFF => MAP_INSIDE,
                    0x07 => SCAN,
                    p => match p & 0x07 {
                        0 => GREY_WALL,
                        1 => MAP_WALL_V2,
                        7 => room_color((p as u32) >> 3),
                        _ => UNKNOWN,
                    },
                }
            };
            c.put(x as i64, y as i64, color);
        }
    }
    // Nearest-neighbour upscale.
    let s = SCALE as usize;
    let mut big = Canvas::new(w * s, h * s, [0, 0, 0, 0]);
    for y in 0..h * s {
        for x in 0..w * s {
            big.px[y * big.w + x] = c.get(x / s, y / s);
        }
    }
    big
}

fn draw_charger(canvas: &mut Canvas, dims: &Dims, p: Point) {
    // Translucent, so drawn on its own layer and composited.
    let (x, y) = dims.to_img(p);
    let angle = -p.a.unwrap_or(0.0);
    let mut layer = Canvas::new(canvas.w, canvas.h, [255, 255, 255, 0]);
    layer.pieslice(x, y, CHARGER_RADIUS, angle + 90.0, angle - 90.0, CHARGER);
    canvas.composite(&layer);
}

fn draw_path(canvas: &mut Canvas, dims: &Dims, path: &[Point]) {
    for pair in path.windows(2) {
        let (sx, sy) = dims.to_img(pair[0]);
        let (ex, ey) = dims.to_img(pair[1]);
        canvas.line(sx, sy, ex, ey, PATH_WIDTH, PATH);
    }
}

fn draw_vacuum(canvas: &mut Canvas, dims: &Dims, p: Point) {
    let a = p.a.unwrap_or(0.0);
    let (px, py) = dims.to_img(p);
    let r = VACUUM_RADIUS;
    let rs = r / 16.0;
    canvas.ellipse(px, py, r, Some(ROBO_OUTLINE), Some(ROBO));
    if r >= 8.0 {
        canvas.ellipse(px, py, rs * 14.0, Some(ROBO_OUTLINE), None);
    }
    let (a1, a2) = ((a + 104.0) / 180.0 * PI, (a - 104.0) / 180.0 * PI);
    let r2 = rs * 13.0;
    canvas.line(
        px - r2 * a1.cos(),
        py + r2 * a1.sin(),
        px - r2 * a2.cos(),
        py + r2 * a2.sin(),
        1.0,
        ROBO_OUTLINE,
    );
    let angle = a / 180.0 * PI;
    let (x, y) = (px + rs * 3.0 * angle.cos(), py - rs * 3.0 * angle.sin());
    canvas.ellipse(x, y, rs * 4.0, Some(ROBO_OUTLINE), Some(ROBO));
    let half = [
        ((ROBO_OUTLINE[0] as u16 + ROBO[0] as u16) / 2) as u8,
        ((ROBO_OUTLINE[1] as u16 + ROBO[1] as u16) / 2) as u8,
        ((ROBO_OUTLINE[2] as u16 + ROBO[2] as u16) / 2) as u8,
        255,
    ];
    let (x, y) = (px + rs * 10.0 * angle.cos(), py - rs * 10.0 * angle.sin());
    canvas.ellipse(x, y, rs * 2.0, Some(half), Some(half));
}

/// "NO MAP" on the outside colour, as `create_empty_map_image` draws it.
fn empty_map() -> Canvas {
    const GLYPHS: [(char, [u8; 7]); 5] = [
        ('N', [0x11, 0x19, 0x15, 0x13, 0x11, 0x11, 0x11]),
        ('O', [0x0E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E]),
        ('M', [0x11, 0x1B, 0x15, 0x15, 0x11, 0x11, 0x11]),
        ('A', [0x0E, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11]),
        ('P', [0x1E, 0x11, 0x11, 0x1E, 0x10, 0x10, 0x10]),
    ];
    let mut c = Canvas::new(300, 200, MAP_OUTSIDE);
    let text = "NO MAP";
    let width = text.len() as i64 * 6 - 1;
    let (x0, y0) = ((300 - width) / 2, (200 - 7) / 2);
    // The outside colour is dark, so the text is white.
    for (i, ch) in text.chars().enumerate() {
        let Some((_, rows)) = GLYPHS.iter().find(|(g, _)| *g == ch) else {
            continue;
        };
        for (row, bits) in rows.iter().enumerate() {
            for col in 0..5 {
                if bits & (0x10 >> col) != 0 {
                    c.put(
                        x0 + i as i64 * 6 + col,
                        y0 + row as i64,
                        [255, 255, 255, 255],
                    );
                }
            }
        }
    }
    c
}

fn render(map: &MapData) -> Result<Canvas, MapError> {
    let img = map
        .image
        .as_ref()
        .ok_or_else(|| MapError("Failed to render map image".into()))?;
    if img.width == 0 || img.height == 0 {
        return Ok(empty_map());
    }
    let mut canvas = floor_plan(map, img);
    let dims = Dims {
        top: img.top as f64,
        left: img.left as f64,
        height: img.height as f64,
    };
    // The default drawables, in DEFAULT_DRAWABLES order.
    if let Some(c) = map.charger {
        draw_charger(&mut canvas, &dims, c);
    }
    draw_path(&mut canvas, &dims, &map.path);
    if let Some(v) = map.vacuum {
        draw_vacuum(&mut canvas, &dims, v);
    }
    Ok(canvas)
}

fn encode_png(c: &Canvas) -> Result<Vec<u8>, MapError> {
    let mut out = Vec::new();
    {
        let mut enc = png::Encoder::new(&mut out, c.w as u32, c.h as u32);
        enc.set_color(png::ColorType::Rgba);
        enc.set_depth(png::BitDepth::Eight);
        let mut writer = enc
            .write_header()
            .map_err(|e| MapError(format!("PNG encoding failed: {e}")))?;
        let flat: Vec<u8> = c.px.iter().flatten().copied().collect();
        writer
            .write_image_data(&flat)
            .map_err(|e| MapError(format!("PNG encoding failed: {e}")))?;
    }
    Ok(out)
}

/// Parse the (already decrypted and decompressed) map and render the PNG.
pub fn map_png(raw: &[u8]) -> Result<Vec<u8>, MapError> {
    let map = parse(raw)?;
    encode_png(&render(&map)?)
}

#[cfg(test)]
pub mod tests {
    use super::*;

    fn block(kind: u16, header_extra: &[u8], data: &[u8]) -> Vec<u8> {
        let header_len = 8 + header_extra.len();
        let mut b = Vec::new();
        b.extend_from_slice(&kind.to_le_bytes());
        b.extend_from_slice(&(header_len as u16).to_le_bytes());
        b.extend_from_slice(&(data.len() as u32).to_le_bytes());
        b.extend_from_slice(header_extra);
        b.extend_from_slice(data);
        b
    }

    /// A tiny map: a 4x3 floor plan with room 1 and a wall, a charger, the
    /// vacuum and a two-point path.
    pub fn sample_map() -> Vec<u8> {
        let mut raw = vec![0u8; 0x14];
        raw[0x02] = 0x14; // map header length
        let mut img_header = Vec::new();
        for v in [
            10u32, /* top */
            20,    /* left */
            3,     /* height */
            4,     /* width */
        ] {
            img_header.extend_from_slice(&v.to_le_bytes());
        }
        let room1 = (1u8 << 3) | 7;
        let pixels = [
            0x01, 0x01, 0x01, 0x01, //
            0x01, room1, room1, 0x01, //
            0x00, 0x00, 0x00, 0xFF,
        ];
        raw.extend(block(2, &img_header, &pixels));
        let pos = |x: u32, y: u32, a: Option<u32>| {
            let mut d = Vec::new();
            d.extend_from_slice(&x.to_le_bytes());
            d.extend_from_slice(&y.to_le_bytes());
            if let Some(a) = a {
                d.extend_from_slice(&a.to_le_bytes());
            }
            d
        };
        raw.extend(block(1, &[], &pos(21 * 50, 11 * 50, None)));
        raw.extend(block(8, &[], &pos(22 * 50, 11 * 50, Some(90))));
        // Path: header is 0x14 bytes (8 + 12 extra), points follow it.
        let mut path_extra = Vec::new();
        for v in [2u32, 4, 0] {
            path_extra.extend_from_slice(&v.to_le_bytes());
        }
        let mut pts = Vec::new();
        for (x, y) in [(20u16 * 50, 10u16 * 50), (23 * 50, 12 * 50)] {
            pts.extend_from_slice(&x.to_le_bytes());
            pts.extend_from_slice(&y.to_le_bytes());
        }
        raw.extend(block(3, &path_extra, &pts));
        raw
    }

    #[test]
    fn parses_the_blocks_the_drawing_needs() {
        let map = parse(&sample_map()).unwrap();
        let img = map.image.as_ref().unwrap();
        assert_eq!((img.top, img.left, img.height, img.width), (10, 20, 3, 4));
        assert_eq!(map.charger.unwrap().x, 1050.0);
        assert_eq!(map.vacuum.unwrap().a, Some(90.0));
        assert_eq!(map.path.len(), 2);
        assert_eq!(map.path[1].x, 1150.0);
    }

    #[test]
    fn renders_a_scaled_png_with_rooms_flipped_upright() {
        let map = parse(&sample_map()).unwrap();
        // The floor plan alone: the vacuum (radius 24) would cover this tiny map.
        let canvas = floor_plan(&map, map.image.as_ref().unwrap());
        assert_eq!((canvas.w, canvas.h), (16, 12));
        // Raw row 0 (walls) is drawn at the bottom; raw row 2 at the top.
        assert_eq!(canvas.get(0, 11), MAP_WALL);
        assert_eq!(canvas.get(0, 0), MAP_OUTSIDE);
        // Room 1's colour on raw row 1 -> image row 1 -> scaled rows 4..8.
        assert_eq!(canvas.get(5, 5)[..3], ROOM_COLORS[0]);
        let png = map_png(&sample_map()).unwrap();
        assert_eq!(&png[..8], b"\x89PNG\r\n\x1a\n");
    }

    #[test]
    fn the_vacuum_is_drawn_over_the_floor_plan() {
        let map = parse(&sample_map()).unwrap();
        let canvas = render(&map).unwrap();
        let dims = Dims {
            top: 10.0,
            left: 20.0,
            height: 3.0,
        };
        let (vx, vy) = dims.to_img(map.vacuum.unwrap());
        // The vacuum's body is white where the floor plan had a room.
        assert_eq!(canvas.get(vx as usize, vy as usize), ROBO);
    }

    #[test]
    fn the_charger_is_blended_over_the_floor_not_painted_on() {
        let map = parse(&sample_map()).unwrap();
        let mut canvas = floor_plan(&map, map.image.as_ref().unwrap());
        let dims = Dims {
            top: 10.0,
            left: 20.0,
            height: 3.0,
        };
        let (cx, cy) = dims.to_img(map.charger.unwrap());
        // With no angle the half disc faces left; (cx-3, cy) is wall.
        let (x, y) = (cx as usize - 3, cy as usize);
        assert_eq!(canvas.get(x, y), MAP_WALL);
        let right_before = canvas.get(cx as usize + 3, y);
        draw_charger(&mut canvas, &dims, map.charger.unwrap());
        let px = canvas.get(x, y);
        assert_eq!(px[3], 255, "composited onto an opaque floor stays opaque");
        assert_ne!(px, MAP_WALL);
        assert_ne!(px, CHARGER);
        // The right half is not drawn.
        assert_eq!(canvas.get(cx as usize + 3, y), right_before);
    }

    #[test]
    fn a_map_without_an_image_block_is_an_error() {
        let mut raw = vec![0u8; 0x14];
        raw[0x02] = 0x14;
        assert!(map_png(&raw).is_err());
    }

    #[test]
    fn room_colours_wrap_past_32() {
        assert_eq!(room_color(33), room_color(1));
        assert_eq!(room_color(0), room_color(32));
    }
}
