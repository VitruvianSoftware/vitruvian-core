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

use std::f64::consts::PI;

pub const TILE_API: &str = "https://tile.googleapis.com/v1";
pub const PROBE_OFFSET_DEG: f64 = 0.00027;

#[derive(Debug, Clone, PartialEq)]
pub struct StreetViewPanoramaOpts {
    pub lat: f64,
    pub lon: f64,
    pub zoom: u32,
    pub radius: u32,
    pub outdir: String,
    pub key: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PanoramaGrid {
    pub zoom: u32,
    pub tiles_x: u32,
    pub tiles_y: u32,
    pub total_tiles: u32,
    pub canvas_width: u32,
    pub canvas_height: u32,
}

#[derive(Debug, Clone, PartialEq)]
pub struct PanoLink {
    pub pano_id: String,
    pub heading: f64,
    pub text: Option<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct PanoMetadata {
    pub pano_id: String,
    pub lat: f64,
    pub lng: f64,
    pub image_width: u32,
    pub image_height: u32,
    pub tile_width: u32,
    pub tile_height: u32,
    pub heading: f64,
    pub tilt: f64,
    pub date: Option<String>,
    pub copyright: Option<String>,
    pub links: Vec<PanoLink>,
}

pub const HELP_TEXT: &str =
    "Usage: node tools/streetview-panorama.mjs --lat <lat> --lon <lon> [--zoom 0-5] [--radius m] [--outdir dir] [--key apikey]";

pub fn parse_args(args: &[String]) -> Result<StreetViewPanoramaOpts, String> {
    let mut lat: Option<f64> = None;
    let mut lon: Option<f64> = None;
    let mut zoom: i32 = 3;
    let mut radius: u32 = 50;
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
                    .parse::<i32>()
                    .map_err(|_| "Error: invalid --zoom value.".to_string())?;
            }
            "--radius" => {
                i += 1;
                radius = args
                    .get(i)
                    .ok_or_else(|| "Error: --radius requires a value.".to_string())?
                    .parse::<u32>()
                    .map_err(|_| "Error: invalid --radius value.".to_string())?;
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

    if !(0..=5).contains(&zoom) {
        return Err("Error: --zoom must be between 0 and 5.".into());
    }

    Ok(StreetViewPanoramaOpts {
        lat,
        lon,
        zoom: zoom as u32,
        radius,
        outdir,
        key,
    })
}

pub fn panorama_grid_dimensions(zoom: u32, tile_width: u32, tile_height: u32) -> PanoramaGrid {
    let tiles_x = 2u32.pow(zoom);
    let tiles_y = if zoom == 0 { 1 } else { 2u32.pow(zoom - 1) };
    let total_tiles = tiles_x * tiles_y;
    let canvas_width = tiles_x * tile_width;
    let canvas_height = tiles_y * tile_height;
    PanoramaGrid {
        zoom,
        tiles_x,
        tiles_y,
        total_tiles,
        canvas_width,
        canvas_height,
    }
}

pub fn probe_points(lat: f64, lon: f64) -> Vec<(f64, f64)> {
    let d = PROBE_OFFSET_DEG;
    vec![
        (lat, lon),
        (lat + d, lon),
        (lat - d, lon),
        (lat, lon + d),
        (lat, lon - d),
        (lat + d * 2.0, lon),
        (lat - d * 2.0, lon),
        (lat, lon + d * 2.0),
        (lat, lon - d * 2.0),
    ]
}

pub fn planar_distance_m(target_lat: f64, target_lon: f64, cand_lat: f64, cand_lon: f64) -> f64 {
    let dy = (cand_lat - target_lat) * 111_320.0;
    let dx = (cand_lon - target_lon) * 111_320.0 * (target_lat * PI / 180.0).cos();
    (dy * dy + dx * dx).sqrt()
}

pub fn is_google_pano(copyright: Option<&str>) -> bool {
    copyright.map(|c| c.contains("Google")).unwrap_or(false)
}

/// Selects the closest Google-owned panorama from `candidates`, or the first contributor fallback.
pub fn select_best_panorama(
    target_lat: f64,
    target_lon: f64,
    candidates: &[PanoMetadata],
) -> Option<PanoMetadata> {
    let mut google_panos: Vec<PanoMetadata> = candidates
        .iter()
        .filter(|m| is_google_pano(m.copyright.as_deref()))
        .cloned()
        .collect();

    if !google_panos.is_empty() {
        google_panos.sort_by(|a, b| {
            let da = planar_distance_m(target_lat, target_lon, a.lat, a.lng);
            let db = planar_distance_m(target_lat, target_lon, b.lat, b.lng);
            da.partial_cmp(&db).unwrap_or(std::cmp::Ordering::Equal)
        });
        return google_panos.into_iter().next();
    }

    candidates.first().cloned()
}

/// Stitches available `(x, y, rgb_bytes)` tiles onto a black equirectangular canvas.
pub fn stitch_panorama_rgb_tiles(
    grid: &PanoramaGrid,
    tile_width: u32,
    tile_height: u32,
    tiles: &[(u32, u32, Vec<u8>)],
) -> Vec<u8> {
    let w = grid.canvas_width as usize;
    let h = grid.canvas_height as usize;
    let tw = tile_width as usize;
    let th = tile_height as usize;
    let mut canvas = vec![0u8; w * h * 3];

    for (tx, ty, buf) in tiles {
        if *tx >= grid.tiles_x || *ty >= grid.tiles_y {
            continue;
        }
        if buf.len() < tw * th * 3 {
            continue;
        }
        let left = *tx as usize * tw;
        let top = *ty as usize * th;
        for row in 0..th {
            let dst_y = top + row;
            let dst_start = (dst_y * w + left) * 3;
            let src_start = row * tw * 3;
            canvas[dst_start..dst_start + tw * 3]
                .copy_from_slice(&buf[src_start..src_start + tw * 3]);
        }
    }

    canvas
}

pub fn panorama_output_filename(lat: f64, lon: f64) -> String {
    format!("panorama_{}_{}.jpg", lat, lon)
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
    let grid = panorama_grid_dimensions(opts.zoom, 512, 512);
    Ok(format!(
        "Street View Panorama Fetcher: {} (zoom={}, grid={}x{}={} tiles)",
        panorama_output_filename(opts.lat, opts.lon),
        opts.zoom,
        grid.tiles_x,
        grid.tiles_y,
        grid.total_tiles
    ))
}
