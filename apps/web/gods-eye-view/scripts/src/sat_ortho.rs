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

use std::collections::HashMap;
use std::f64::consts::PI;

pub const TILE_SIZE: u32 = 256;
pub const MAX_CONCURRENT: usize = 8;

#[derive(Debug, Clone, PartialEq)]
pub struct SatOrthoOpts {
    pub lat: f64,
    pub lon: f64,
    pub zoom: u32,
    pub size: u32,
    pub outdir: String,
    pub key: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct TileCoord {
    pub zoom: u32,
    pub x: i64,
    pub y: i64,
}

#[derive(Debug, Clone, PartialEq)]
pub struct OrthoGridPlan {
    pub center_x: f64,
    pub center_y: f64,
    pub center_tile_x: i64,
    pub center_tile_y: i64,
    pub center_px_x: f64,
    pub center_px_y: f64,
    pub min_tile_x: i64,
    pub max_tile_x: i64,
    pub min_tile_y: i64,
    pub max_tile_y: i64,
    pub grid_w: u32,
    pub grid_h: u32,
    pub total_tiles: usize,
    pub stitch_w: u32,
    pub stitch_h: u32,
    pub crop_left: i64,
    pub crop_top: i64,
    pub mpp: f64,
    pub coverage_m: f64,
    pub nw_corner: (f64, f64),
    pub se_corner: (f64, f64),
    pub output_filename: String,
    pub tile_coords: Vec<TileCoord>,
}

pub const HELP_TEXT: &str = "\
Usage: node tools/sat-ortho.mjs --lat <lat> --lon <lon> [options]

Required:
  --lat      Center latitude
  --lon      Center longitude

Options:
  --zoom     Tile zoom level (default: 21)
  --size     Output square size in pixels (default: 2048)
  --outdir   Output directory (default: output/)
  --key      Google Maps API key";

pub fn parse_args(args: &[String]) -> Result<SatOrthoOpts, String> {
    let mut lat: Option<f64> = None;
    let mut lon: Option<f64> = None;
    let mut zoom: u32 = 21;
    let mut size: u32 = 2048;
    let mut outdir = "output".to_string();
    let mut key: Option<String> = None;

    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--help" => return Err(HELP_TEXT.to_string()),
            "--lat" => {
                i += 1;
                lat = Some(
                    args.get(i)
                        .ok_or_else(|| "Error: --lat requires a value.".to_string())?
                        .parse::<f64>()
                        .map_err(|_| "Error: invalid --lat value.".to_string())?,
                );
            }
            "--lon" => {
                i += 1;
                lon = Some(
                    args.get(i)
                        .ok_or_else(|| "Error: --lon requires a value.".to_string())?
                        .parse::<f64>()
                        .map_err(|_| "Error: invalid --lon value.".to_string())?,
                );
            }
            "--zoom" => {
                i += 1;
                zoom = args
                    .get(i)
                    .ok_or_else(|| "Error: --zoom requires a value.".to_string())?
                    .parse::<u32>()
                    .map_err(|_| "Error: invalid --zoom value.".to_string())?;
            }
            "--size" => {
                i += 1;
                size = args
                    .get(i)
                    .ok_or_else(|| "Error: --size requires a value.".to_string())?
                    .parse::<u32>()
                    .map_err(|_| "Error: invalid --size value.".to_string())?;
            }
            "--outdir" => {
                i += 1;
                outdir = args
                    .get(i)
                    .ok_or_else(|| "Error: --outdir requires a value.".to_string())?
                    .clone();
            }
            "--key" => {
                i += 1;
                key = Some(
                    args.get(i)
                        .ok_or_else(|| "Error: --key requires a value.".to_string())?
                        .clone(),
                );
            }
            _ => {}
        }
        i += 1;
    }

    let (lat, lon) = match (lat, lon) {
        (Some(a), Some(o)) => (a, o),
        _ => return Err("Error: --lat and --lon are required.".into()),
    };

    Ok(SatOrthoOpts {
        lat,
        lon,
        zoom,
        size,
        outdir,
        key,
    })
}

/// Convert lat/lon to fractional Web Mercator tile coordinates at a given zoom level.
pub fn lat_lon_to_tile(lat: f64, lon: f64, zoom: u32) -> (f64, f64) {
    let n = 2.0_f64.powi(zoom as i32);
    let x = ((lon + 180.0) / 360.0) * n;
    let lat_rad = lat * PI / 180.0;
    let y = (1.0 - (lat_rad.tan() + 1.0 / lat_rad.cos()).ln() / PI) / 2.0 * n;
    (x, y)
}

/// Convert tile x/y (integer) + pixel offset back to `(lat, lon)`.
pub fn tile_px_to_lat_lon(tile_x: i64, tile_y: i64, px_x: f64, px_y: f64, zoom: u32) -> (f64, f64) {
    let n = 2.0_f64.powi(zoom as i32);
    let ts = TILE_SIZE as f64;
    let lon = ((tile_x as f64 + px_x / ts) / n) * 360.0 - 180.0;
    let lat_rad = (PI * (1.0 - 2.0 * (tile_y as f64 + px_y / ts) / n))
        .sinh()
        .atan();
    let lat = lat_rad * 180.0 / PI;
    (lat, lon)
}

/// Compute meters per pixel at a given latitude and zoom.
pub fn meters_per_pixel(lat: f64, zoom: u32) -> f64 {
    (156_543.03392 * (lat * PI / 180.0).cos()) / 2.0_f64.powi(zoom as i32)
}

pub fn compute_ortho_grid(lat: f64, lon: f64, zoom: u32, size: u32) -> OrthoGridPlan {
    let ts = TILE_SIZE as f64;
    let mpp = meters_per_pixel(lat, zoom);
    let coverage_m = mpp * size as f64;

    let (center_x, center_y) = lat_lon_to_tile(lat, lon, zoom);
    let center_tile_x = center_x.floor() as i64;
    let center_tile_y = center_y.floor() as i64;
    let center_px_x = (center_x - center_tile_x as f64) * ts;
    let center_px_y = (center_y - center_tile_y as f64) * ts;

    let half_size = size as f64 / 2.0;
    let tiles_left = ((half_size - center_px_x) / ts).ceil() as i64 + 1;
    let tiles_right = ((half_size - (ts - center_px_x)) / ts).ceil() as i64 + 1;
    let tiles_up = ((half_size - center_px_y) / ts).ceil() as i64 + 1;
    let tiles_down = ((half_size - (ts - center_px_y)) / ts).ceil() as i64 + 1;

    let min_tile_x = center_tile_x - tiles_left;
    let max_tile_x = center_tile_x + tiles_right;
    let min_tile_y = center_tile_y - tiles_up;
    let max_tile_y = center_tile_y + tiles_down;

    let grid_w = (max_tile_x - min_tile_x + 1) as u32;
    let grid_h = (max_tile_y - min_tile_y + 1) as u32;
    let total_tiles = (grid_w * grid_h) as usize;

    let stitch_w = grid_w * TILE_SIZE;
    let stitch_h = grid_h * TILE_SIZE;

    let crop_left =
        ((center_tile_x - min_tile_x) as f64 * ts + center_px_x - half_size).round() as i64;
    let crop_top =
        ((center_tile_y - min_tile_y) as f64 * ts + center_px_y - half_size).round() as i64;

    let nw_corner = tile_px_to_lat_lon(min_tile_x, min_tile_y, crop_left as f64, crop_top as f64, zoom);
    let se_corner = tile_px_to_lat_lon(
        min_tile_x,
        min_tile_y,
        (crop_left + size as i64) as f64,
        (crop_top + size as i64) as f64,
        zoom,
    );

    let mut tile_coords = Vec::with_capacity(total_tiles);
    for ty in min_tile_y..=max_tile_y {
        for tx in min_tile_x..=max_tile_x {
            tile_coords.push(TileCoord { zoom, x: tx, y: ty });
        }
    }

    let output_filename = format!("sat_{}_{}_z{}_{}x{}.jpg", lat, lon, zoom, size, size);

    OrthoGridPlan {
        center_x,
        center_y,
        center_tile_x,
        center_tile_y,
        center_px_x,
        center_px_y,
        min_tile_x,
        max_tile_x,
        min_tile_y,
        max_tile_y,
        grid_w,
        grid_h,
        total_tiles,
        stitch_w,
        stitch_h,
        crop_left,
        crop_top,
        mpp,
        coverage_m,
        nw_corner,
        se_corner,
        output_filename,
        tile_coords,
    }
}

/// Stitches raw 256x256 RGB tiles into a full grid and crops the centered `size x size` region.
pub fn stitch_and_crop_rgb_tiles(
    grid: &OrthoGridPlan,
    tiles: &HashMap<(i64, i64), Vec<u8>>,
    size: u32,
) -> Vec<u8> {
    let stitch_w = grid.stitch_w as usize;
    let stitch_h = grid.stitch_h as usize;
    let ts = TILE_SIZE as usize;
    let mut canvas = vec![0u8; stitch_w * stitch_h * 3];

    for ty in grid.min_tile_y..=grid.max_tile_y {
        for tx in grid.min_tile_x..=grid.max_tile_x {
            if let Some(tile_buf) = tiles.get(&(tx, ty)) {
                if tile_buf.len() < ts * ts * 3 {
                    continue;
                }
                let left = (tx - grid.min_tile_x) as usize * ts;
                let top = (ty - grid.min_tile_y) as usize * ts;
                for row in 0..ts {
                    let dst_y = top + row;
                    let dst_start = (dst_y * stitch_w + left) * 3;
                    let src_start = row * ts * 3;
                    canvas[dst_start..dst_start + ts * 3]
                        .copy_from_slice(&tile_buf[src_start..src_start + ts * 3]);
                }
            }
        }
    }

    let out_size = size as usize;
    let crop_x = grid.crop_left.max(0) as usize;
    let crop_y = grid.crop_top.max(0) as usize;
    let mut cropped = vec![0u8; out_size * out_size * 3];

    for row in 0..out_size {
        let src_y = crop_y + row;
        if src_y >= stitch_h {
            break;
        }
        let avail_w = out_size.min(stitch_w.saturating_sub(crop_x));
        let src_start = (src_y * stitch_w + crop_x) * 3;
        let dst_start = row * out_size * 3;
        cropped[dst_start..dst_start + avail_w * 3]
            .copy_from_slice(&canvas[src_start..src_start + avail_w * 3]);
    }

    cropped
}

pub fn run(args: &[String]) -> Result<String, String> {
    if args.iter().any(|a| a == "--help") {
        return Ok(HELP_TEXT.to_string());
    }
    let opts = parse_args(args)?;
    let _api_key = crate::cesium_render::load_api_key(
        opts.key.as_deref(),
        std::env::var("GOOGLE_MAPS_API_KEY").ok().as_deref(),
        std::fs::read_to_string(".env").ok().as_deref(),
    )?;
    let grid = compute_ortho_grid(opts.lat, opts.lon, opts.zoom, opts.size);
    Ok(format!(
        "Satellite Ortho Stitcher: {} ({}x{} tiles, GSD ~{:.1} cm/px)",
        grid.output_filename,
        grid.grid_w,
        grid.grid_h,
        grid.mpp * 100.0
    ))
}
