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

use std::collections::HashSet;
use std::f64::consts::PI;
use std::io::Write;
use std::path::PathBuf;

use crate::tool_io::{
    decode_rgb, encode_jpeg, js_num, parallel_map, read_dotenv_lenient, to_fixed, CurlFetcher, Fetcher,
    HttpRequest, RgbImage, ToolContext, JPEG_QUALITY,
};

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
    "Usage: bazel run //apps/web/gods-eye-view:streetview_panorama -- --lat <lat> --lon <lon> [--zoom 0-5] [--radius m] [--outdir dir] [--key apikey]";

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

pub fn panorama_output_filename(lat: f64, lon: f64) -> String {
    format!("panorama_{}_{}.jpg", js_num(lat), js_num(lon))
}

/// Parse a Tiles API Street View metadata response.
pub fn parse_metadata(v: &serde_json::Value) -> Result<PanoMetadata, String> {
    let num = |k: &str| v.get(k).and_then(|x| x.as_f64());
    let pano_id = v
        .get("panoId")
        .and_then(|x| x.as_str())
        .ok_or_else(|| "metadata has no panoId".to_string())?
        .to_string();
    let links = v
        .get("links")
        .and_then(|l| l.as_array())
        .map(|arr| {
            arr.iter()
                .filter_map(|l| {
                    Some(PanoLink {
                        pano_id: l.get("panoId")?.as_str()?.to_string(),
                        heading: l.get("heading").and_then(|h| h.as_f64()).unwrap_or(0.0),
                        text: l.get("text").and_then(|t| t.as_str()).map(|t| t.to_string()),
                    })
                })
                .collect()
        })
        .unwrap_or_default();
    Ok(PanoMetadata {
        pano_id,
        lat: num("lat").unwrap_or(f64::NAN),
        lng: num("lng").unwrap_or(f64::NAN),
        image_width: num("imageWidth").unwrap_or(0.0) as u32,
        image_height: num("imageHeight").unwrap_or(0.0) as u32,
        tile_width: num("tileWidth").unwrap_or(0.0) as u32,
        tile_height: num("tileHeight").unwrap_or(0.0) as u32,
        heading: num("heading").unwrap_or(0.0),
        tilt: num("tilt").unwrap_or(0.0),
        date: v.get("date").and_then(|x| x.as_str()).map(|s| s.to_string()),
        copyright: v.get("copyright").and_then(|x| x.as_str()).map(|s| s.to_string()),
        links,
    })
}

struct Api<'a> {
    fetcher: &'a dyn Fetcher,
    api_key: &'a str,
    session: String,
}

pub fn create_session_request(api_key: &str) -> HttpRequest {
    HttpRequest::post_json(
        format!("{}/createSession?key={}", TILE_API, api_key),
        &serde_json::json!({ "mapType": "streetview", "language": "en-US", "region": "US" }),
    )
    .referer()
}

pub fn pano_ids_request(session: &str, api_key: &str, lat: f64, lng: f64, radius: u32) -> HttpRequest {
    HttpRequest::post_json(
        format!("{}/streetview/panoIds?session={}&key={}", TILE_API, session, api_key),
        &serde_json::json!({ "locations": [{ "lat": lat, "lng": lng }], "radius": radius }),
    )
    .referer()
}

pub fn metadata_url(session: &str, api_key: &str, pano_id: &str) -> String {
    format!(
        "{}/streetview/metadata?session={}&key={}&panoId={}",
        TILE_API, session, api_key, pano_id
    )
}

pub fn tile_url(session: &str, api_key: &str, pano_id: &str, z: u32, x: u32, y: u32) -> String {
    format!(
        "{}/streetview/tiles/{}/{}/{}?session={}&key={}&panoId={}",
        TILE_API, z, x, y, session, api_key, pano_id
    )
}

impl<'a> Api<'a> {
    fn find_pano_id(&self, lat: f64, lng: f64, radius: u32) -> Result<String, String> {
        let res = self
            .fetcher
            .fetch(&pano_ids_request(&self.session, self.api_key, lat, lng, radius))?;
        if !res.ok() {
            return Err(format!("panoIds search failed ({}): {}", res.status, res.text()));
        }
        res.json()?
            .get("panoIds")
            .and_then(|v| v.get(0))
            .and_then(|v| v.as_str())
            .filter(|s| !s.is_empty())
            .map(|s| s.to_string())
            .ok_or_else(|| {
                format!(
                    "No Street View panorama found within {}m of {}, {}",
                    radius,
                    js_num(lat),
                    js_num(lng)
                )
            })
    }

    fn get_metadata(&self, pano_id: &str) -> Result<PanoMetadata, String> {
        let res = self
            .fetcher
            .fetch(&HttpRequest::get(metadata_url(&self.session, self.api_key, pano_id)).referer())?;
        if !res.ok() {
            return Err(format!("metadata failed ({}): {}", res.status, res.text()));
        }
        parse_metadata(&res.json()?)
    }

    /// `None` for an empty edge tile (404 or 204), as in the JS tool.
    fn fetch_tile(&self, pano_id: &str, z: u32, x: u32, y: u32) -> Result<Option<Vec<u8>>, String> {
        let res = self
            .fetcher
            .fetch(&HttpRequest::get(tile_url(&self.session, self.api_key, pano_id, z, x, y)).referer())?;
        if res.status == 404 || res.status == 204 {
            return Ok(None);
        }
        if !res.ok() {
            return Err(format!("tile {}/{}/{} failed ({}): {}", z, x, y, res.status, res.text()));
        }
        Ok(Some(res.body))
    }
}

fn short_id(id: &str) -> String {
    id.chars().take(20).collect()
}

/// Probe the point and 8 offsets around it; stop at the first Google-owned
/// panorama, adding its linked Google panoramas, and pick the closest of
/// those. With none, the first panorama found.
fn select_panorama(api: &Api, opts: &StreetViewPanoramaOpts) -> Result<PanoMetadata, String> {
    let dist = |m: &PanoMetadata| planar_distance_m(opts.lat, opts.lon, m.lat, m.lng);
    let mut seen: HashSet<String> = HashSet::new();
    let mut google: Vec<PanoMetadata> = Vec::new();
    let mut fallback: Option<PanoMetadata> = None;

    for (lat, lng) in probe_points(opts.lat, opts.lon) {
        let p_id = match api.find_pano_id(lat, lng, opts.radius) {
            Ok(id) => id,
            Err(_) => continue,
        };
        if seen.contains(&p_id) {
            continue;
        }
        let candidate = api.get_metadata(&p_id)?;
        seen.insert(p_id.clone());
        println!(
            "  Probe {},{} \u{2192} {}\u{2026} {}m ({})",
            to_fixed(lat, 5),
            to_fixed(lng, 5),
            short_id(&p_id),
            to_fixed(dist(&candidate), 0),
            candidate.copyright.as_deref().unwrap_or("undefined")
        );
        if is_google_pano(candidate.copyright.as_deref()) {
            let links = candidate.links.clone();
            google.push(candidate);
            for link in links {
                if seen.contains(&link.pano_id) {
                    continue;
                }
                let linked = api.get_metadata(&link.pano_id)?;
                seen.insert(link.pano_id.clone());
                if is_google_pano(linked.copyright.as_deref()) {
                    println!(
                        "    Link {}\u{2026} {}m ({})",
                        short_id(&link.pano_id),
                        to_fixed(dist(&linked), 0),
                        linked.copyright.as_deref().unwrap_or("undefined")
                    );
                    google.push(linked);
                }
            }
            break;
        }
        if fallback.is_none() {
            fallback = Some(candidate);
        }
    }

    if !google.is_empty() {
        google.sort_by(|a, b| dist(a).partial_cmp(&dist(b)).unwrap_or(std::cmp::Ordering::Equal));
        let meta = google.into_iter().next().expect("not empty");
        println!(
            "  Selected: {}\u{2026} ({}m away)",
            short_id(&meta.pano_id),
            to_fixed(dist(&meta), 0)
        );
        return Ok(meta);
    }
    println!("  No Google pano found, using best available.");
    fallback.ok_or_else(|| {
        format!(
            "No Street View panorama found within {}m of {}, {}",
            opts.radius,
            js_num(opts.lat),
            js_num(opts.lon)
        )
    })
}

/// Fetch every tile of the zoom level's fixed grid, 6 at a time, and composite
/// them onto a black canvas.
fn stitch_panorama(api: &Api, meta: &PanoMetadata, zoom: u32) -> Result<RgbImage, String> {
    let grid = panorama_grid_dimensions(zoom, meta.tile_width, meta.tile_height);
    println!(
        "Panorama at zoom {}: grid {}x{} = {} tiles ({}x{}px)",
        zoom, grid.tiles_x, grid.tiles_y, grid.total_tiles, grid.canvas_width, grid.canvas_height
    );
    let mut queue = Vec::new();
    for y in 0..grid.tiles_y {
        for x in 0..grid.tiles_x {
            queue.push((x, y));
        }
    }
    let total = queue.len();
    let completed = std::sync::atomic::AtomicUsize::new(0);
    let fetched = parallel_map(&queue, TILE_CONCURRENCY, |&(x, y)| {
        let r = api.fetch_tile(&meta.pano_id, zoom, x, y);
        let done = completed.fetch_add(1, std::sync::atomic::Ordering::SeqCst) + 1;
        if done % 10 == 0 || done == total {
            print!("  Fetched {}/{} tiles\r", done, total);
            let _ = std::io::stdout().flush();
        }
        r
    });
    println!("  Fetched {}/{} tiles", total, total);

    println!(
        "Stitching {}x{} panorama...",
        grid.canvas_width, grid.canvas_height
    );
    let mut canvas = RgbImage::black(grid.canvas_width as usize, grid.canvas_height as usize);
    for (&(x, y), tile) in queue.iter().zip(fetched) {
        if let Some(bytes) = tile? {
            if bytes.is_empty() {
                continue;
            }
            let img = decode_rgb(&bytes).map_err(|e| format!("tile {}/{}/{}: {}", zoom, x, y, e))?;
            canvas.composite(
                &img,
                (x * meta.tile_width) as usize,
                (y * meta.tile_height) as usize,
            );
        }
    }
    Ok(canvas)
}

pub const TILE_CONCURRENCY: usize = 6;

/// Port of `main()` in the former `tools/streetview-panorama.mjs`; returns the
/// written panorama.
pub fn execute(
    opts: &StreetViewPanoramaOpts,
    ctx: &ToolContext,
    fetcher: &dyn Fetcher,
) -> Result<PathBuf, String> {
    let dotenv = read_dotenv_lenient(ctx);
    let api_key = crate::cesium_render::load_api_key(
        opts.key.as_deref(),
        ctx.env_var("GOOGLE_MAPS_API_KEY"),
        dotenv.as_deref(),
    )?;

    println!("\nStreet View Panorama Fetcher");
    println!("  Location: {}, {}", js_num(opts.lat), js_num(opts.lon));
    println!("  Zoom: {} (0=tiny, 5=full res 13312x6656)", opts.zoom);
    println!("  Radius: {}m\n", opts.radius);

    println!("Creating session...");
    let res = fetcher.fetch(&create_session_request(&api_key))?;
    if !res.ok() {
        return Err(format!("createSession failed ({}): {}", res.status, res.text()));
    }
    let session_data = res.json()?;
    let session = session_data
        .get("session")
        .and_then(|v| v.as_str())
        .ok_or_else(|| "createSession returned no session".to_string())?
        .to_string();
    let tile_dim = |k: &str| {
        session_data
            .get(k)
            .map(|v| v.to_string())
            .unwrap_or_else(|| "undefined".into())
    };
    println!(
        "  Session created (tile size: {}x{})\n",
        tile_dim("tileWidth"),
        tile_dim("tileHeight")
    );

    let api = Api {
        fetcher,
        api_key: &api_key,
        session,
    };

    println!(
        "Searching for Google panorama near {}, {}...",
        js_num(opts.lat),
        js_num(opts.lon)
    );
    let meta = select_panorama(&api, opts)?;

    println!("\nMetadata:");
    println!("  Panorama ID: {}", meta.pano_id);
    println!("  Location: {}, {}", js_num(meta.lat), js_num(meta.lng));
    println!("  Image size: {}x{}", meta.image_width, meta.image_height);
    println!("  Heading: {} degrees", js_num(meta.heading));
    println!("  Tilt: {} degrees", js_num(meta.tilt));
    println!(
        "  Date: {}",
        meta.date.as_deref().filter(|d| !d.is_empty()).unwrap_or("unknown")
    );
    println!("  Copyright: {}", meta.copyright.as_deref().unwrap_or("undefined"));
    if !meta.links.is_empty() {
        println!("  Links to {} adjacent panorama(s):", meta.links.len());
        for link in &meta.links {
            println!(
                "    - {} heading={} panoId={}",
                link.text.as_deref().filter(|t| !t.is_empty()).unwrap_or("unnamed"),
                to_fixed(link.heading, 1),
                link.pano_id
            );
        }
    }
    println!();
    println!(
        "  Distance from requested point: {}m\n",
        to_fixed(planar_distance_m(opts.lat, opts.lon, meta.lat, meta.lng), 1)
    );

    let pano = stitch_panorama(&api, &meta, opts.zoom)?;
    let jpeg = encode_jpeg(&pano, JPEG_QUALITY)?;

    let outdir = ctx.outdir(&opts.outdir);
    std::fs::create_dir_all(&outdir).map_err(|e| format!("{}: {}", outdir.display(), e))?;
    let pano_path = outdir.join(panorama_output_filename(opts.lat, opts.lon));
    std::fs::write(&pano_path, &jpeg).map_err(|e| format!("{}: {}", pano_path.display(), e))?;

    println!(
        "\nSaved: {} ({} MB)",
        pano_path.display(),
        to_fixed(jpeg.len() as f64 / 1024.0 / 1024.0, 2)
    );
    println!(
        "  Panorama: {}x{}, heading={}, tilt={}",
        pano.width,
        pano.height,
        to_fixed(meta.heading, 1),
        to_fixed(meta.tilt, 1)
    );
    Ok(pano_path)
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
    use crate::tool_io::{
        close, decode_rgb, ok_response, png_bytes, solid, status_response, test_context, HttpResponse, MockFetcher,
    };

    const LAT: f64 = 30.268066;
    const LON: f64 = -97.742813;

    fn args(list: &[&str]) -> Vec<String> {
        list.iter().map(|s| s.to_string()).collect()
    }

    fn colour(x: u32, y: u32) -> [u8; 3] {
        [(x * 60 + 15) as u8, (y * 100 + 30) as u8, 200]
    }

    fn meta_json(id: &str, lat: f64, lng: f64, copyright: &str, links: &str) -> String {
        format!(
            r#"{{"panoId":"{}","lat":{},"lng":{},"imageWidth":64,"imageHeight":32,"tileWidth":16,"tileHeight":16,"heading":87.25,"tilt":90.0,"date":"2024-05","copyright":"{}","links":[{}]}}"#,
            id, lat, lng, copyright, links
        )
    }

    /// The first probe finds a contributor pano; the second a Google pano
    /// linking to a closer Google pano, which wins. Tile (3,1) is an empty edge (404).
    fn google_fetcher() -> MockFetcher<impl Fn(&HttpRequest) -> Result<HttpResponse, String> + Sync> {
        MockFetcher::new(|req: &HttpRequest| {
            let u = req.url.as_str();
            if u.contains("/createSession") {
                return ok_response(r#"{"session":"S","expiry":"9","tileWidth":512,"tileHeight":512,"imageFormat":"jpeg"}"#);
            }
            if u.contains("/streetview/panoIds") {
                let body: serde_json::Value = serde_json::from_slice(req.body.as_ref().unwrap()).unwrap();
                let lat = body["locations"][0]["lat"].as_f64().unwrap();
                let id = if lat == LAT { "CONTRIB" } else { "GOOG1_ABCDEFGHIJKLMNOPQRSTUVWXYZ" };
                return ok_response(format!(r#"{{"panoIds":["{}"]}}"#, id));
            }
            if u.contains("panoId=CONTRIB") && u.contains("/metadata") {
                return ok_response(meta_json("CONTRIB", LAT, LON, "\u{a9} A Contributor", ""));
            }
            if u.contains("panoId=GOOG1_") && u.contains("/metadata") {
                return ok_response(meta_json(
                    "GOOG1_ABCDEFGHIJKLMNOPQRSTUVWXYZ",
                    LAT + 0.0003,
                    LON,
                    "\u{a9} 2024 Google",
                    r#"{"panoId":"GOOG2","heading":10.04,"text":"Congress Ave"},{"panoId":"CONTRIB","heading":190.0}"#,
                ));
            }
            if u.contains("panoId=GOOG2") && u.contains("/metadata") {
                return ok_response(meta_json("GOOG2", LAT + 0.00005, LON, "\u{a9} 2024 Google", ""));
            }
            if let Some(rest) = u.strip_prefix("https://tile.googleapis.com/v1/streetview/tiles/") {
                let p: Vec<u32> = rest.split('?').next().unwrap().split('/').map(|v| v.parse().unwrap()).collect();
                if (p[1], p[2]) == (3, 1) {
                    return status_response(404, "");
                }
                return ok_response(png_bytes(&solid(16, 16, colour(p[1], p[2]))));
            }
            status_response(500, "unexpected")
        })
    }

    #[test]
    fn picks_the_closest_google_pano_and_stitches_its_tiles() {
        let ctx = test_context("streetview_panorama_ok", &[("GOOGLE_MAPS_API_KEY", "K")]);
        let fetcher = google_fetcher();
        let opts = parse_args(&args(&["--lat", "30.268066", "--lon", "-97.742813", "--zoom", "2", "--outdir", "pano"])).unwrap();
        let path = execute(&opts, &ctx, &fetcher).unwrap();
        assert_eq!(path, ctx.project_root.join("pano").join("panorama_30.268066_-97.742813.jpg"));

        let calls = fetcher.calls();
        assert_eq!(calls[0].url, "https://tile.googleapis.com/v1/createSession?key=K");
        let body: serde_json::Value = serde_json::from_slice(calls[0].body.as_ref().unwrap()).unwrap();
        assert_eq!(body, serde_json::json!({"mapType": "streetview", "language": "en-US", "region": "US"}));

        // Two probes: the first is a contributor pano, the second Google's, so the search stops.
        let probes: Vec<serde_json::Value> = calls
            .iter()
            .filter(|c| c.url.contains("/panoIds"))
            .map(|c| {
                assert_eq!(c.url, "https://tile.googleapis.com/v1/streetview/panoIds?session=S&key=K");
                assert_eq!(c.method, "POST");
                serde_json::from_slice(c.body.as_ref().unwrap()).unwrap()
            })
            .collect();
        assert_eq!(
            probes,
            [
                serde_json::json!({"locations": [{"lat": LAT, "lng": LON}], "radius": 50}),
                serde_json::json!({"locations": [{"lat": LAT + 0.00027, "lng": LON}], "radius": 50}),
            ]
        );
        // CONTRIB is already seen, so only GOOG2 of the links is looked up.
        let metas: Vec<&str> = calls.iter().filter(|c| c.url.contains("/metadata")).map(|c| c.url.as_str()).collect();
        assert_eq!(
            metas,
            [
                "https://tile.googleapis.com/v1/streetview/metadata?session=S&key=K&panoId=CONTRIB",
                "https://tile.googleapis.com/v1/streetview/metadata?session=S&key=K&panoId=GOOG1_ABCDEFGHIJKLMNOPQRSTUVWXYZ",
                "https://tile.googleapis.com/v1/streetview/metadata?session=S&key=K&panoId=GOOG2",
            ]
        );
        // Zoom 2 is a 4x2 grid of the closest Google pano's tiles.
        let mut tiles: Vec<&str> = calls.iter().filter(|c| c.url.contains("/tiles/")).map(|c| c.url.as_str()).collect();
        tiles.sort();
        assert_eq!(tiles.len(), 8);
        assert_eq!(tiles[0], "https://tile.googleapis.com/v1/streetview/tiles/2/0/0?session=S&key=K&panoId=GOOG2");
        assert!(calls.iter().skip(1).all(|c| c.header_value("Referer") == Some("http://localhost:4173/")));

        let img = decode_rgb(&std::fs::read(&path).unwrap()).unwrap();
        assert_eq!((img.width, img.height), (64, 32));
        for y in 0..2u32 {
            for x in 0..4u32 {
                let want = if (x, y) == (3, 1) { [0, 0, 0] } else { colour(x, y) };
                let got = img.pixel((x * 16 + 8) as usize, (y * 16 + 8) as usize);
                assert!(close(got, want, 10), "tile {},{} = {:?}, want {:?}", x, y, got, want);
            }
        }
    }

    #[test]
    fn a_non_default_radius_reaches_every_pano_search() {
        let ctx = test_context("streetview_panorama_radius", &[("GOOGLE_MAPS_API_KEY", "K")]);
        let fetcher = google_fetcher();
        let opts = parse_args(&args(&["--lat", "30.268066", "--lon", "-97.742813", "--zoom", "0", "--radius", "120"])).unwrap();
        assert_eq!(opts.radius, 120);
        execute(&opts, &ctx, &fetcher).unwrap();
        let radii: Vec<serde_json::Value> = fetcher
            .calls()
            .iter()
            .filter(|c| c.url.contains("/panoIds"))
            .map(|c| serde_json::from_slice::<serde_json::Value>(c.body.as_ref().unwrap()).unwrap()["radius"].clone())
            .collect();
        assert_eq!(radii, [serde_json::json!(120), serde_json::json!(120)]);
    }

    #[test]
    fn falls_back_to_a_contributor_pano_and_fails_without_any() {
        let ctx = test_context("streetview_panorama_fallback", &[]);
        let contributor = MockFetcher::new(|req: &HttpRequest| {
            let u = req.url.as_str();
            if u.contains("/createSession") {
                ok_response(r#"{"session":"S"}"#)
            } else if u.contains("/panoIds") {
                ok_response(r#"{"panoIds":["C1"]}"#)
            } else if u.contains("/metadata") {
                ok_response(meta_json("C1", LAT, LON, "\u{a9} Someone", ""))
            } else {
                ok_response(png_bytes(&solid(16, 16, [10, 20, 30])))
            }
        });
        let opts = parse_args(&args(&["--lat", "30.268066", "--lon", "-97.742813", "--zoom", "0", "--key", "K"])).unwrap();
        let path = execute(&opts, &ctx, &contributor).unwrap();
        let img = decode_rgb(&std::fs::read(path).unwrap()).unwrap();
        assert_eq!((img.width, img.height), (16, 16));
        // Every probe resolves to the same pano: one metadata lookup, nine searches.
        let calls = contributor.calls();
        assert_eq!(calls.iter().filter(|c| c.url.contains("/panoIds")).count(), 9);
        assert_eq!(calls.iter().filter(|c| c.url.contains("/metadata")).count(), 1);

        let nothing = MockFetcher::new(|req: &HttpRequest| {
            if req.url.contains("/createSession") {
                ok_response(r#"{"session":"S"}"#)
            } else {
                ok_response(r#"{"panoIds":[]}"#)
            }
        });
        assert!(execute(&opts, &ctx, &nothing).unwrap_err().contains("No Street View panorama found within 50m"));

        let broken_tile = MockFetcher::new(|req: &HttpRequest| {
            let u = req.url.as_str();
            if u.contains("/createSession") {
                ok_response(r#"{"session":"S"}"#)
            } else if u.contains("/panoIds") {
                ok_response(r#"{"panoIds":["C1"]}"#)
            } else if u.contains("/metadata") {
                ok_response(meta_json("C1", LAT, LON, "\u{a9} 2020 Google", ""))
            } else {
                status_response(500, "boom")
            }
        });
        assert_eq!(execute(&opts, &ctx, &broken_tile).unwrap_err(), "tile 0/0/0 failed (500): boom");

        let refused = MockFetcher::new(|_: &HttpRequest| status_response(403, "nope"));
        assert_eq!(execute(&opts, &ctx, &refused).unwrap_err(), "createSession failed (403): nope");
        assert_eq!(
            parse_args(&args(&["--lat", "1", "--lon", "2", "--zoom", "6"])).unwrap_err(),
            "Error: --zoom must be between 0 and 5."
        );
    }
}
