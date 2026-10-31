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
use std::io::Write;
use std::path::PathBuf;
use std::time::Instant;

use crate::tool_io::{
    decode_rgb, encode_jpeg, js_num, parallel_map, read_dotenv_lenient, to_fixed, CurlFetcher, Fetcher,
    HttpRequest, RgbImage, ToolContext, JPEG_QUALITY,
};

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
Usage: bazel run //apps/web/gods-eye-view:sat_ortho -- --lat <lat> --lon <lon> [options]

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
    (156_543.033_92 * (lat * PI / 180.0).cos()) / 2.0_f64.powi(zoom as i32)
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

    let output_filename = format!("sat_{}_{}_z{}_{}x{}.jpg", js_num(lat), js_num(lon), zoom, size, size);

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

pub const TILE_API: &str = "https://tile.googleapis.com/v1";

/// The 2D satellite tile session request (`createSession` in the JS tool).
pub fn create_session_request(api_key: &str) -> HttpRequest {
    HttpRequest::post_json(
        format!("{}/createSession?key={}", TILE_API, api_key),
        &serde_json::json!({ "mapType": "satellite", "language": "en-US", "region": "US" }),
    )
    .referer()
}

pub fn tile_url(zoom: u32, x: i64, y: i64, session: &str, api_key: &str) -> String {
    format!(
        "{}/2dtiles/{}/{}/{}?session={}&key={}",
        TILE_API, zoom, x, y, session, api_key
    )
}

fn create_session(fetcher: &dyn Fetcher, api_key: &str) -> Result<String, String> {
    let res = fetcher.fetch(&create_session_request(api_key))?;
    if !res.ok() {
        return Err(format!(
            "Failed to create tile session: {} {}",
            res.status,
            res.text()
        ));
    }
    res.json()?
        .get("session")
        .and_then(|v| v.as_str())
        .map(|s| s.to_string())
        .ok_or_else(|| "Failed to create tile session: no session in the response".to_string())
}

/// Fetch every tile, 8 at a time; a failed tile is a warning, as in the JS tool.
fn fetch_tiles(
    fetcher: &dyn Fetcher,
    coords: &[TileCoord],
    session: &str,
    api_key: &str,
) -> HashMap<(i64, i64), Vec<u8>> {
    let total = coords.len();
    let completed = std::sync::atomic::AtomicUsize::new(0);
    let results = parallel_map(coords, MAX_CONCURRENT, |c| {
        let req = HttpRequest::get(tile_url(c.zoom, c.x, c.y, session, api_key)).referer();
        let out = match fetcher.fetch(&req) {
            Ok(res) if res.ok() => Some(res.body),
            Ok(res) => {
                println!(
                    "    Warning: tile {}/{}/{} failed: Tile {}/{}/{} failed: {}",
                    c.zoom, c.x, c.y, c.zoom, c.x, c.y, res.status
                );
                None
            }
            Err(e) => {
                println!("    Warning: tile {}/{}/{} failed: {}", c.zoom, c.x, c.y, e);
                None
            }
        };
        let done = completed.fetch_add(1, std::sync::atomic::Ordering::SeqCst) + 1;
        if done % 10 == 0 || done == total {
            print!("\r    {}/{} tiles fetched", done, total);
            let _ = std::io::stdout().flush();
        }
        out
    });
    println!();
    coords
        .iter()
        .zip(results)
        .filter_map(|(c, r)| r.map(|b| ((c.x, c.y), b)))
        .collect()
}

/// Composite the fetched tiles onto a black `stitch_w` x `stitch_h` canvas and
/// crop the `size` x `size` square centred on the target.
pub fn stitch_and_crop(
    grid: &OrthoGridPlan,
    tiles: &HashMap<(i64, i64), Vec<u8>>,
    size: u32,
) -> Result<RgbImage, String> {
    let ts = TILE_SIZE as usize;
    let mut canvas = RgbImage::black(grid.stitch_w as usize, grid.stitch_h as usize);
    for ty in grid.min_tile_y..=grid.max_tile_y {
        for tx in grid.min_tile_x..=grid.max_tile_x {
            if let Some(bytes) = tiles.get(&(tx, ty)) {
                let tile = decode_rgb(bytes).map_err(|e| format!("tile {},{}: {}", tx, ty, e))?;
                let left = (tx - grid.min_tile_x) as usize * ts;
                let top = (ty - grid.min_tile_y) as usize * ts;
                canvas.composite(&tile, left, top);
            }
        }
    }
    canvas.extract(
        grid.crop_left.max(0) as usize,
        grid.crop_top.max(0) as usize,
        size as usize,
        size as usize,
    )
}

/// Port of `main()` in the former `tools/sat-ortho.mjs`; returns the written path.
pub fn execute(opts: &SatOrthoOpts, ctx: &ToolContext, fetcher: &dyn Fetcher) -> Result<PathBuf, String> {
    let dotenv = read_dotenv_lenient(ctx);
    let api_key = crate::cesium_render::load_api_key(
        opts.key.as_deref(),
        ctx.env_var("GOOGLE_MAPS_API_KEY"),
        dotenv.as_deref(),
    )?;

    let grid = compute_ortho_grid(opts.lat, opts.lon, opts.zoom, opts.size);
    println!("\nSatellite Ortho Stitcher");
    println!("  Center   : {}, {}", js_num(opts.lat), js_num(opts.lon));
    println!("  Zoom     : {}", opts.zoom);
    println!("  Output   : {}x{} px", opts.size, opts.size);
    println!("  GSD      : ~{} cm/pixel", to_fixed(grid.mpp * 100.0, 1));
    println!(
        "  Coverage : ~{}m x {}m",
        to_fixed(grid.coverage_m, 0),
        to_fixed(grid.coverage_m, 0)
    );
    println!(
        "  Grid     : {}x{} = {} tiles",
        grid.grid_w, grid.grid_h, grid.total_tiles
    );
    println!(
        "  Tile range: x=[{}, {}] y=[{}, {}]",
        grid.min_tile_x, grid.max_tile_x, grid.min_tile_y, grid.max_tile_y
    );

    println!("\nCreating tile session...");
    let session = create_session(fetcher, &api_key)?;

    println!(
        "  Fetching {} tiles (concurrency: {})...",
        grid.total_tiles, MAX_CONCURRENT
    );
    let t0 = Instant::now();
    let tiles = fetch_tiles(fetcher, &grid.tile_coords, &session, &api_key);
    println!(
        "    Fetched {}/{} tiles in {}s",
        tiles.len(),
        grid.total_tiles,
        to_fixed(t0.elapsed().as_secs_f64(), 2)
    );
    if tiles.is_empty() {
        return Err("Error: No tiles fetched.".into());
    }

    println!("\nStitching...");
    let cropped = stitch_and_crop(&grid, &tiles, opts.size)?;
    let jpeg = encode_jpeg(&cropped, JPEG_QUALITY)?;

    let outdir = ctx.outdir(&opts.outdir);
    std::fs::create_dir_all(&outdir).map_err(|e| format!("{}: {}", outdir.display(), e))?;
    let out_path = outdir.join(&grid.output_filename);
    std::fs::write(&out_path, jpeg).map_err(|e| format!("{}: {}", out_path.display(), e))?;

    println!("\nSaved: {}", out_path.display());
    println!("  Size     : {}x{}", opts.size, opts.size);
    println!("  GSD      : ~{} cm/pixel", to_fixed(grid.mpp * 100.0, 1));
    println!(
        "  Coverage : ~{}m x {}m",
        to_fixed(grid.coverage_m, 0),
        to_fixed(grid.coverage_m, 0)
    );
    println!("  Tiles    : {}", tiles.len());
    println!("  Time     : {}s", to_fixed(t0.elapsed().as_secs_f64(), 2));
    println!(
        "  NW corner: {}, {}",
        to_fixed(grid.nw_corner.0, 6),
        to_fixed(grid.nw_corner.1, 6)
    );
    println!(
        "  SE corner: {}, {}",
        to_fixed(grid.se_corner.0, 6),
        to_fixed(grid.se_corner.1, 6)
    );
    Ok(out_path)
}

/// The CLI: `--help` text, or fetch, stitch and save.
pub fn run(args: &[String]) -> Result<Option<String>, String> {
    if args.iter().any(|a| a == "--help") {
        return Ok(Some(HELP_TEXT.to_string()));
    }
    let opts = parse_args(args)?;
    execute(&opts, &ToolContext::from_process(), &CurlFetcher)?;
    Ok(None)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tool_io::{close, ok_response, png_bytes, solid, status_response, test_context, MockFetcher};

    const LAT: f64 = 30.266476;
    const LON: f64 = -97.73719;

    fn args(list: &[&str]) -> Vec<String> {
        list.iter().map(|s| s.to_string()).collect()
    }

    /// A colour unique to each tile of the grid.
    fn tile_colour(grid: &OrthoGridPlan, x: i64, y: i64) -> [u8; 3] {
        let dx = (x - grid.min_tile_x) as u8;
        let dy = (y - grid.min_tile_y) as u8;
        [dx * 40 + 20, dy * 40 + 20, 128]
    }

    /// Parse `/2dtiles/{z}/{x}/{y}?...` out of a tile URL.
    fn tile_xy(url: &str) -> Option<(i64, i64)> {
        let path = url.strip_prefix("https://tile.googleapis.com/v1/2dtiles/")?;
        let path = path.split('?').next()?;
        let parts: Vec<i64> = path.split('/').map(|p| p.parse().unwrap()).collect();
        Some((parts[1], parts[2]))
    }

    #[test]
    fn fetches_the_grid_stitches_and_crops_centred_on_the_target() {
        let ctx = test_context("sat_ortho_ok", &[]);
        std::fs::write(ctx.project_root.join(".env"), "# keys\nGOOGLE_MAPS_API_KEY=dotenv-key\n").unwrap();
        let grid = compute_ortho_grid(LAT, LON, 21, 512);
        // A tile inside the crop: the target is never on its tile's far edge.
        let failing = (grid.center_tile_x + 1, grid.center_tile_y + 1);
        let fetcher = MockFetcher::new(|req: &HttpRequest| {
            if req.url.contains("/createSession") {
                return ok_response(r#"{"session":"sess-1","expiry":"1"}"#);
            }
            match tile_xy(&req.url) {
                Some(xy) if xy == failing => status_response(403, "denied"),
                Some((x, y)) => ok_response(png_bytes(&solid(256, 256, tile_colour(&grid, x, y)))),
                None => status_response(404, ""),
            }
        });
        let opts = parse_args(&args(&[
            "--lat", "30.266476", "--lon", "-97.73719", "--size", "512", "--outdir", "out",
        ]))
        .unwrap();
        let path = execute(&opts, &ctx, &fetcher).unwrap();
        assert_eq!(
            path,
            ctx.project_root.join("out").join("sat_30.266476_-97.73719_z21_512x512.jpg")
        );

        let calls = fetcher.calls();
        let session = &calls[0];
        assert_eq!(session.method, "POST");
        assert_eq!(session.url, "https://tile.googleapis.com/v1/createSession?key=dotenv-key");
        assert_eq!(session.header_value("Referer"), Some("http://localhost:4173/"));
        assert_eq!(session.header_value("Content-Type"), Some("application/json"));
        let body: serde_json::Value = serde_json::from_slice(session.body.as_ref().unwrap()).unwrap();
        assert_eq!(body, serde_json::json!({"mapType": "satellite", "language": "en-US", "region": "US"}));

        let mut tile_urls: Vec<String> = calls[1..].iter().map(|c| c.url.clone()).collect();
        tile_urls.sort();
        let mut expected: Vec<String> = grid
            .tile_coords
            .iter()
            .map(|c| format!("https://tile.googleapis.com/v1/2dtiles/21/{}/{}?session=sess-1&key=dotenv-key", c.x, c.y))
            .collect();
        expected.sort();
        assert_eq!(tile_urls, expected);
        assert!(calls[1..].iter().all(|c| c.method == "GET" && c.header_value("Referer") == Some(REFERER_FOR_TEST)));

        let img = crate::tool_io::decode_rgb(&std::fs::read(&path).unwrap()).unwrap();
        assert_eq!((img.width, img.height), (512, 512));
        // Each sampled output pixel shows the tile its stitched position falls in.
        let ts = TILE_SIZE as i64;
        for oy in (4..512).step_by(37) {
            for ox in (4..512).step_by(37) {
                let sx = grid.crop_left + ox as i64;
                let sy = grid.crop_top + oy as i64;
                if sx % ts < 6 || sx % ts > ts - 6 || sy % ts < 6 || sy % ts > ts - 6 {
                    continue; // JPEG blurs tile seams
                }
                let (tx, ty) = (grid.min_tile_x + sx / ts, grid.min_tile_y + sy / ts);
                let want = if (tx, ty) == failing { [0, 0, 0] } else { tile_colour(&grid, tx, ty) };
                assert!(close(img.pixel(ox, oy), want, 10), "({},{}) = {:?}, want {:?} from tile {},{}", ox, oy, img.pixel(ox, oy), want, tx, ty);
            }
        }
        // The failed tile is black in the output.
        let fx = ((failing.0 - grid.min_tile_x) * ts - grid.crop_left + ts / 2).clamp(0, 511) as usize;
        let fy = ((failing.1 - grid.min_tile_y) * ts - grid.crop_top + ts / 2).clamp(0, 511) as usize;
        assert!(close(img.pixel(fx, fy), [0, 0, 0], 10), "failed tile at ({},{}) = {:?}", fx, fy, img.pixel(fx, fy));
        // The target sits at the centre: the centre pixel is in the centre tile.
        assert!(close(img.pixel(256, 256), tile_colour(&grid, grid.center_tile_x, grid.center_tile_y), 10));
    }

    const REFERER_FOR_TEST: &str = "http://localhost:4173/";

    #[test]
    fn session_failure_no_tiles_and_no_key_are_errors() {
        let opts = parse_args(&args(&["--lat", "30", "--lon", "-97", "--size", "256", "--key", "k"])).unwrap();
        let ctx = test_context("sat_ortho_err", &[]);

        let refused = MockFetcher::new(|_: &HttpRequest| status_response(403, "API key not valid"));
        assert_eq!(
            execute(&opts, &ctx, &refused).unwrap_err(),
            "Failed to create tile session: 403 API key not valid"
        );

        let no_tiles = MockFetcher::new(|req: &HttpRequest| {
            if req.url.contains("/createSession") {
                ok_response(r#"{"session":"s"}"#)
            } else {
                Err("fetch failed".into())
            }
        });
        assert_eq!(execute(&opts, &ctx, &no_tiles).unwrap_err(), "Error: No tiles fetched.");

        let keyless = parse_args(&args(&["--lat", "30", "--lon", "-97"])).unwrap();
        let never = MockFetcher::new(|_: &HttpRequest| status_response(500, ""));
        assert!(execute(&keyless, &ctx, &never).unwrap_err().contains("No API key found"));
        assert!(never.calls().is_empty());

        // The environment key wins over .env, the flag over both.
        let env_ctx = test_context("sat_ortho_env", &[("GOOGLE_MAPS_API_KEY", "env-key")]);
        let seen = MockFetcher::new(|_: &HttpRequest| status_response(403, ""));
        let _ = execute(&keyless, &env_ctx, &seen);
        assert!(seen.calls()[0].url.ends_with("?key=env-key"));
    }
}
