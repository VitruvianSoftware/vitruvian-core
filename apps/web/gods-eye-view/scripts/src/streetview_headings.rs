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

use std::collections::{HashMap, HashSet};
use std::f64::consts::PI;
use std::path::{Path, PathBuf};

use crate::tool_io::{js_num, to_fixed, CurlFetcher, Fetcher, HttpRequest, ToolContext};

#[derive(Debug, Clone, PartialEq)]
pub struct StreetViewHeadingsOpts {
    pub lat: f64,
    pub lon: f64,
    pub fov: u32,
    pub pitch: i32,
    pub size: String,
    pub outdir: String,
    pub key: Option<String>,
    pub step: Option<u32>,
    pub neighbors: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HeadingDirection {
    pub name: String,
    pub heading: u32,
}

#[derive(Debug, Clone, PartialEq)]
pub struct NeighborLocation {
    pub lat: f64,
    pub lon: f64,
    pub street: Option<String>,
    pub dist: f64,
}

#[derive(Debug, Clone, PartialEq)]
pub struct StreetViewMetadata {
    pub pano_id: Option<String>,
    pub lat: f64,
    pub lng: f64,
}

pub const HELP_TEXT: &str =
    "Usage: bazel run //apps/web/gods-eye-view:streetview_headings -- --lat <lat> --lon <lon> [--fov 90] [--pitch 0] [--size 640x640] [--step 45] [--neighbors]";

pub fn parse_args(args: &[String]) -> Result<StreetViewHeadingsOpts, String> {
    let mut lat: Option<f64> = None;
    let mut lon: Option<f64> = None;
    let mut fov: u32 = 90;
    let mut pitch: i32 = 0;
    let mut size = "640x640".to_string();
    let mut outdir = "output".to_string();
    let mut key: Option<String> = None;
    let mut step: Option<u32> = None;
    let mut neighbors = false;

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
            "--fov" => {
                i += 1;
                fov = args
                    .get(i)
                    .ok_or_else(|| "Error: --fov requires a value.".to_string())?
                    .parse::<u32>()
                    .map_err(|_| "Error: invalid --fov value.".to_string())?;
            }
            "--pitch" => {
                i += 1;
                pitch = args
                    .get(i)
                    .ok_or_else(|| "Error: --pitch requires a value.".to_string())?
                    .parse::<i32>()
                    .map_err(|_| "Error: invalid --pitch value.".to_string())?;
            }
            "--size" => {
                i += 1;
                size = args
                    .get(i)
                    .ok_or_else(|| "Error: --size requires a value.".to_string())?
                    .clone();
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
            "--step" => {
                i += 1;
                step = Some(
                    args.get(i)
                        .ok_or_else(|| "Error: --step requires a value.".to_string())?
                        .parse::<u32>()
                        .map_err(|_| "Error: invalid --step value.".to_string())?,
                );
            }
            "--neighbors" => {
                neighbors = true;
            }
            _ => {}
        }
        i += 1;
    }

    let (lat, lon) = match (lat, lon) {
        (Some(a), Some(o)) => (a, o),
        _ => return Err("Error: --lat and --lon are required.".into()),
    };

    Ok(StreetViewHeadingsOpts {
        lat,
        lon,
        fov,
        pitch,
        size,
        outdir,
        key,
        step,
        neighbors,
    })
}

/// Port of `resolveGoogleServerKey` from `scripts/google-server-key.mjs`.
pub fn resolve_google_server_key(
    environment: &HashMap<String, String>,
    defaults: &HashMap<String, String>,
) -> String {
    let val = |name: &str| -> String {
        environment
            .get(name)
            .or_else(|| defaults.get(name))
            .map(|s| s.trim().to_string())
            .unwrap_or_default()
    };
    let s = val("GOOGLE_MAPS_SERVER_API_KEY");
    if !s.is_empty() {
        return s;
    }
    val("GOOGLE_MAPS_API_KEY")
}

/// Port of `loadApiKey` from the former `tools/streetview-headings.mjs`.
///
/// The explicit CLI key wins. Otherwise a server key set in the environment
/// wins before `.env` is even read. Otherwise each variable takes the
/// environment's value over `.env`'s (an empty environment value still
/// overrides), and the server key is preferred over the browser key.
/// `read_dotenv` returns `Ok(None)` when there is no `.env`; any other read
/// failure is an error, as in the JS tool.
pub fn load_api_key(
    override_key: Option<&str>,
    environment: &HashMap<String, String>,
    read_dotenv: impl FnOnce() -> Result<Option<String>, String>,
) -> Result<String, String> {
    if let Some(k) = override_key {
        if !k.is_empty() {
            return Ok(k.to_string());
        }
    }
    let mut server_only = HashMap::new();
    if let Some(v) = environment.get("GOOGLE_MAPS_SERVER_API_KEY") {
        server_only.insert("GOOGLE_MAPS_SERVER_API_KEY".to_string(), v.clone());
    }
    let server_key = resolve_google_server_key(&server_only, &HashMap::new());
    if !server_key.is_empty() {
        return Ok(server_key);
    }
    let from_dotenv = match read_dotenv()? {
        Some(content) => crate::tool_io::parse_env(&content),
        None => HashMap::new(),
    };
    let key = resolve_google_server_key(environment, &from_dotenv);
    if !key.is_empty() {
        return Ok(key);
    }
    Err(
        "No API key found. Set GOOGLE_MAPS_SERVER_API_KEY (or GOOGLE_MAPS_API_KEY) in .env or pass --key."
            .into(),
    )
}

/// Read `.env` for [`load_api_key`]: missing is fine, unreadable is not.
pub fn read_dotenv_strict(path: &Path) -> Result<Option<String>, String> {
    match std::fs::read_to_string(path) {
        Ok(s) => Ok(Some(s)),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(_) => Err("Could not read the Street View tool environment file".into()),
    }
}

pub fn generate_heading_directions(step: Option<u32>) -> Vec<HeadingDirection> {
    let step = step.filter(|&s| s > 0).unwrap_or(45);
    let mut dirs = Vec::new();
    let mut h = 0u32;
    while h < 360 {
        let label = crate::pano_pinhole::compass_label(h);
        let name = if label.is_empty() {
            format!("H{}", h)
        } else {
            label.to_string()
        };
        dirs.push(HeadingDirection { name, heading: h });
        h += step;
    }
    dirs
}

/// Spherical Haversine distance in meters (`R = 6,371,000` m).
pub fn haversine_distance_m(lat1: f64, lon1: f64, lat2: f64, lon2: f64) -> f64 {
    let dlat = (lat2 - lat1) * PI / 180.0;
    let dlon = (lon2 - lon1) * PI / 180.0;
    let a = (dlat / 2.0).sin().powi(2)
        + (lat1 * PI / 180.0).cos() * (lat2 * PI / 180.0).cos() * (dlon / 2.0).sin().powi(2);
    6_371_000.0 * 2.0 * a.sqrt().atan2((1.0 - a).sqrt())
}

/// Strip JSONP wrapper `_ && _( ... )` and extract first-order neighbor locations within `max_dist_m`.
pub fn parse_neighbor_locations_jsonp(jsonp_text: &str, max_dist_m: f64) -> Vec<NeighborLocation> {
    parse_neighbor_locations(jsonp_text, max_dist_m).unwrap_or_default()
}

/// As [`parse_neighbor_locations_jsonp`], but says why nothing came back, with
/// the warning the JS tool printed.
pub fn parse_neighbor_locations(jsonp_text: &str, max_dist_m: f64) -> Result<Vec<NeighborLocation>, String> {
    const PARSE: &str = "  Warning: could not parse neighbor metadata";
    const EXTRACT: &str = "  Warning: could not extract neighbor links from metadata";
    // text.replace(/^[^(]*\(\s*/, '').replace(/\s*\)\s*;?\s*$/, '')
    let start = jsonp_text.find('(').map(|i| i + 1).unwrap_or(0);
    let mut body = jsonp_text[start..].trim_end();
    if let Some(b) = body.strip_suffix(';') {
        body = b.trim_end();
    }
    if let Some(b) = body.strip_suffix(')') {
        body = b;
    }
    let data: serde_json::Value = serde_json::from_str(body.trim()).map_err(|_| PARSE.to_string())?;

    let links = data
        .get(1)
        .and_then(|v| v.get(5))
        .and_then(|v| v.get(0))
        .and_then(|v| v.get(3))
        .and_then(|v| v.get(0))
        .and_then(|v| v.as_array())
        .filter(|arr| !arr.is_empty())
        .ok_or_else(|| EXTRACT.to_string())?;
    let origin = |i: usize| {
        links[0]
            .get(2)
            .and_then(|v| v.get(0))
            .and_then(|v| v.get(i))
            .and_then(|v| v.as_f64())
            .ok_or_else(|| EXTRACT.to_string())
    };
    let origin_lat = origin(2)?;
    let origin_lon = origin(3)?;

    let mut neighbors = Vec::new();
    for link in links.iter().skip(1) {
        let coord = match link.get(2).and_then(|v| v.get(0)) {
            Some(c) if !c.is_null() => c,
            _ => continue,
        };
        let (nlat, nlon) = match (
            coord.get(2).and_then(|v| v.as_f64()),
            coord.get(3).and_then(|v| v.as_f64()),
        ) {
            (Some(a), Some(b)) => (a, b),
            _ => continue,
        };
        let dist = haversine_distance_m(origin_lat, origin_lon, nlat, nlon);
        if dist > max_dist_m {
            continue;
        }
        let street = link
            .get(3)
            .and_then(|v| v.get(2))
            .and_then(|v| v.get(0))
            .and_then(|v| v.get(0))
            .and_then(|v| v.as_str())
            .map(|s| s.to_string());
        neighbors.push(NeighborLocation {
            lat: nlat,
            lon: nlon,
            street,
            dist,
        });
    }
    Ok(neighbors)
}

/// Deduplicates candidate neighbor panoramas against the origin and previously seen `pano_id`s.
pub fn deduplicate_neighbors(
    origin_pano_id: Option<&str>,
    candidates: &[(NeighborLocation, StreetViewMetadata)],
) -> Vec<NeighborLocation> {
    let mut seen_panos: HashSet<String> = HashSet::new();
    if let Some(origin_id) = origin_pano_id {
        if !origin_id.is_empty() {
            seen_panos.insert(origin_id.to_string());
        }
    }

    let mut unique = Vec::new();
    for (neighbor, meta) in candidates {
        let pid = match meta.pano_id.as_deref() {
            Some(id) if !id.is_empty() => id,
            _ => continue,
        };
        if seen_panos.contains(pid) {
            continue;
        }
        seen_panos.insert(pid.to_string());
        unique.push(NeighborLocation {
            lat: meta.lat,
            lon: meta.lng,
            street: neighbor.street.clone(),
            dist: neighbor.dist,
        });
    }
    unique
}

pub fn streetview_static_url(
    lat: f64,
    lon: f64,
    heading: u32,
    pitch: i32,
    fov: u32,
    size: &str,
    api_key: &str,
) -> String {
    format!(
        "https://maps.googleapis.com/maps/api/streetview?location={},{}&heading={}&pitch={}&fov={}&size={}&source=outdoor&key={}",
        js_num(lat), js_num(lon), heading, pitch, fov, size, api_key
    )
}

pub fn streetview_metadata_url(lat: f64, lon: f64, api_key: &str) -> String {
    format!(
        "https://maps.googleapis.com/maps/api/streetview/metadata?location={},{}&source=outdoor&key={}",
        js_num(lat),
        js_num(lon),
        api_key
    )
}

/// Google's internal metadata endpoint the JS tool read neighbor panoramas from.
pub fn neighbor_search_url(lat: f64, lon: f64) -> String {
    format!(
        "https://maps.googleapis.com/maps/api/js/GeoPhotoService.SingleImageSearch?pb=!1m5!1sapiv3!5sUS!11m2!1m1!1b0!2m4!1m2!3d{}!4d{}!2d50!3m18!2m2!1sen!2sUS!9m1!1e2!11m12!1m3!1e2!2b1!3e2!1m3!1e3!2b1!3e2!1m3!1e10!2b1!3e2!4m6!1e1!1e2!1e3!1e4!1e8!1e6&callback=_",
        js_num(lat),
        js_num(lon)
    )
}

pub fn heading_output_filename(lat: f64, lon: f64, heading: u32, name: &str) -> String {
    format!(
        "sv_{}_{}_{:03}_{}.jpg",
        to_fixed(lat, 6),
        to_fixed(lon, 6),
        heading,
        name
    )
}

fn get_neighbor_locations(fetcher: &dyn Fetcher, lat: f64, lon: f64) -> Result<Vec<NeighborLocation>, String> {
    let res = fetcher.fetch(&HttpRequest::get(neighbor_search_url(lat, lon)))?;
    if !res.ok() {
        return Ok(Vec::new());
    }
    Ok(parse_neighbor_locations(&res.text(), 15.0).unwrap_or_else(|warning| {
        println!("{}", warning);
        Vec::new()
    }))
}

#[allow(clippy::too_many_arguments)]
fn fetch_headings_for_location(
    fetcher: &dyn Fetcher,
    lat: f64,
    lon: f64,
    label: &str,
    directions: &[HeadingDirection],
    opts: &StreetViewHeadingsOpts,
    api_key: &str,
    outdir: &Path,
    written: &mut Vec<PathBuf>,
) -> Result<(), String> {
    println!("\n  [{}] {}, {}", label, to_fixed(lat, 6), to_fixed(lon, 6));
    for dir in directions {
        let url = streetview_static_url(lat, lon, dir.heading, opts.pitch, opts.fov, &opts.size, api_key);
        let res = fetcher.fetch(&HttpRequest::get(url).referer())?;
        if !res.ok() {
            println!("    {} ({}): FAILED {}", dir.name, dir.heading, res.status);
            continue;
        }
        let out_path = outdir.join(heading_output_filename(lat, lon, dir.heading, &dir.name));
        std::fs::write(&out_path, &res.body).map_err(|e| format!("{}: {}", out_path.display(), e))?;
        println!(
            "    {} ({}): {} KB",
            dir.name,
            dir.heading,
            to_fixed(res.body.len() as f64 / 1024.0, 1)
        );
        written.push(out_path);
    }
    Ok(())
}

fn metadata(fetcher: &dyn Fetcher, lat: f64, lon: f64, api_key: &str) -> Result<Option<serde_json::Value>, String> {
    let res = fetcher.fetch(&HttpRequest::get(streetview_metadata_url(lat, lon, api_key)).referer())?;
    if !res.ok() {
        return Ok(None);
    }
    res.json().map(Some)
}

/// Port of `main()` in the former `tools/streetview-headings.mjs`; returns the
/// images written.
pub fn execute(
    opts: &StreetViewHeadingsOpts,
    ctx: &ToolContext,
    fetcher: &dyn Fetcher,
) -> Result<Vec<PathBuf>, String> {
    let dotenv_path = ctx.dotenv_path();
    let api_key = load_api_key(opts.key.as_deref(), &ctx.env, || read_dotenv_strict(&dotenv_path))?;

    let outdir = ctx.outdir(&opts.outdir);
    std::fs::create_dir_all(&outdir).map_err(|e| format!("{}: {}", outdir.display(), e))?;

    let directions = generate_heading_directions(opts.step);
    println!("\nStreet View Headings");
    println!("  Location: {}, {}", js_num(opts.lat), js_num(opts.lon));
    println!("  FOV: {}, Pitch: {}, Size: {}", opts.fov, opts.pitch, opts.size);
    println!("  Neighbors: {}", if opts.neighbors { "yes" } else { "no" });

    let mut written = Vec::new();
    fetch_headings_for_location(
        fetcher, opts.lat, opts.lon, "origin", &directions, opts, &api_key, &outdir, &mut written,
    )?;

    if opts.neighbors {
        println!("\nFetching neighbor locations...");
        let neighbors = get_neighbor_locations(fetcher, opts.lat, opts.lon)?;
        if neighbors.is_empty() {
            println!("  No neighbors found.");
        } else {
            println!(
                "  Raw neighbors: {} (deduplicating via metadata...)",
                neighbors.len()
            );
            let origin_pano = metadata(fetcher, opts.lat, opts.lon, &api_key)?
                .and_then(|m| m.get("pano_id").and_then(|v| v.as_str()).map(|s| s.to_string()));
            let mut candidates = Vec::new();
            for n in &neighbors {
                let meta = match metadata(fetcher, n.lat, n.lon, &api_key)? {
                    Some(m) => m,
                    None => continue,
                };
                let pano_id = meta.get("pano_id").and_then(|v| v.as_str()).map(|s| s.to_string());
                let loc = meta.get("location");
                let snapped = StreetViewMetadata {
                    pano_id,
                    lat: loc.and_then(|l| l.get("lat")).and_then(|v| v.as_f64()).unwrap_or(f64::NAN),
                    lng: loc.and_then(|l| l.get("lng")).and_then(|v| v.as_f64()).unwrap_or(f64::NAN),
                };
                candidates.push((n.clone(), snapped));
            }
            let unique = deduplicate_neighbors(origin_pano.as_deref(), &candidates);

            println!("  Unique neighbors: {}", unique.len());
            for n in &unique {
                let street = n.street.as_ref().filter(|s| !s.is_empty()).map(|s| format!(" ({})", s)).unwrap_or_default();
                println!(
                    "    {}, {}  {}m{}",
                    to_fixed(n.lat, 6),
                    to_fixed(n.lon, 6),
                    to_fixed(n.dist, 1),
                    street
                );
            }
            for (i, n) in unique.iter().enumerate() {
                let label = n
                    .street
                    .clone()
                    .filter(|s| !s.is_empty())
                    .unwrap_or_else(|| format!("neighbor-{}", i + 1));
                fetch_headings_for_location(
                    fetcher, n.lat, n.lon, &label, &directions, opts, &api_key, &outdir, &mut written,
                )?;
            }
        }
    }

    println!("\nDone.");
    Ok(written)
}

/// The CLI: `--help` text, or fetch and save.
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
    use crate::tool_io::{ok_response, status_response, test_context, test_dir, MockFetcher};

    fn env(pairs: &[(&str, &str)]) -> HashMap<String, String> {
        pairs.iter().map(|(k, v)| (k.to_string(), v.to_string())).collect()
    }

    fn load(override_key: Option<&str>, path: &Path, environment: &[(&str, &str)]) -> Result<String, String> {
        load_api_key(override_key, &env(environment), || read_dotenv_strict(path))
    }

    /// Moved from src/googleServerKey.test.mjs ("the Street View tool resolves
    /// per-variable overrides before preferring the server key") when
    /// tools/streetview-headings.mjs became this module: same cases, same file.
    #[test]
    fn resolves_per_variable_overrides_before_preferring_the_server_key() {
        let root = test_dir("streetview_key");
        let env_path = root.join(".env");
        std::fs::write(
            &env_path,
            "GOOGLE_MAPS_API_KEY=file-browser\nGOOGLE_MAPS_SERVER_API_KEY=\"file-server\" # separate key\n",
        )
        .unwrap();
        assert_eq!(load(None, &env_path, &[("GOOGLE_MAPS_API_KEY", "shell-browser")]).unwrap(), "file-server");
        assert_eq!(load(None, &env_path, &[("GOOGLE_MAPS_SERVER_API_KEY", "shell-server")]).unwrap(), "shell-server");
        assert_eq!(load(None, &env_path, &[("GOOGLE_MAPS_SERVER_API_KEY", "")]).unwrap(), "file-browser");
        assert_eq!(load(Some("explicit-key"), &env_path, &[]).unwrap(), "explicit-key");
        // A server key in the environment wins before .env is read at all.
        assert_eq!(load(None, &root, &[("GOOGLE_MAPS_SERVER_API_KEY", "shell-server")]).unwrap(), "shell-server");
        std::fs::write(&env_path, "GOOGLE_MAPS_API_KEY=file-browser\n").unwrap();
        assert_eq!(load(None, &env_path, &[]).unwrap(), "file-browser");
        std::fs::write(&env_path, "").unwrap();
        assert!(load(None, &env_path, &[]).unwrap_err().contains("No API key found"));
        // Missing .env is no key; an unreadable one is an error.
        assert!(load(None, &root.join("absent"), &[]).unwrap_err().contains("No API key found"));
        assert_eq!(
            load(None, &root, &[]).unwrap_err(),
            "Could not read the Street View tool environment file"
        );
    }

    fn jsonp() -> String {
        // Origin, a neighbour ~8 m north, a second ~8 m south (resolving to the
        // origin's panorama), and one 200 m away.
        r#"_ && _([null,[null,null,null,null,null,[[null,null,null,[[[null,null,[[null,null,30.268066,-97.742813]]],[null,null,[[null,null,30.268140,-97.742813]],[null,null,[["Congress Ave"]]]],[null,null,[[null,null,30.267990,-97.742813]]],[null,null,[[null,null,30.270000,-97.742813]],[null,null,[["Far St"]]]]]]]]]])"#.to_string()
    }

    #[test]
    fn fetches_each_heading_then_unique_neighbours() {
        let ctx = test_context("streetview_headings_ok", &[("GOOGLE_MAPS_SERVER_API_KEY", "srv")]);
        let fetcher = MockFetcher::new(|req: &HttpRequest| {
            let u = &req.url;
            if u.contains("GeoPhotoService.SingleImageSearch") {
                return ok_response(jsonp());
            }
            if u.contains("/streetview/metadata?location=30.268066,-97.742813&") {
                return ok_response(r#"{"status":"OK","pano_id":"P0","location":{"lat":30.268066,"lng":-97.742813}}"#);
            }
            if u.contains("/streetview/metadata?location=30.26814,-97.742813&") {
                return ok_response(r#"{"status":"OK","pano_id":"P1","location":{"lat":30.2681449,"lng":-97.7428101}}"#);
            }
            if u.contains("/streetview/metadata?location=30.26799,-97.742813&") {
                return ok_response(r#"{"status":"OK","pano_id":"P0","location":{"lat":30.268066,"lng":-97.742813}}"#);
            }
            if u.contains("/maps/api/streetview?") {
                if u.contains("location=30.268066,-97.742813&heading=180&") {
                    return status_response(403, "");
                }
                return ok_response(format!("JPEG {}", u).into_bytes());
            }
            status_response(404, "")
        });
        let opts = parse_args(
            &["--lat", "30.268066", "--lon", "-97.742813", "--step", "90", "--pitch", "-10", "--neighbors", "--outdir", "sv"]
                .iter()
                .map(|s| s.to_string())
                .collect::<Vec<_>>(),
        )
        .unwrap();
        let written = execute(&opts, &ctx, &fetcher).unwrap();
        let names: Vec<String> = written
            .iter()
            .map(|p| p.file_name().unwrap().to_string_lossy().into_owned())
            .collect();
        assert_eq!(
            names,
            [
                "sv_30.268066_-97.742813_000_N.jpg",
                "sv_30.268066_-97.742813_090_E.jpg",
                "sv_30.268066_-97.742813_270_W.jpg",
                "sv_30.268145_-97.742810_000_N.jpg",
                "sv_30.268145_-97.742810_090_E.jpg",
                "sv_30.268145_-97.742810_180_S.jpg",
                "sv_30.268145_-97.742810_270_W.jpg",
            ]
        );
        assert!(written.iter().all(|p| p.starts_with(ctx.project_root.join("sv"))));
        // The image body is written as fetched.
        let first = std::fs::read_to_string(&written[0]).unwrap();
        assert_eq!(
            first,
            "JPEG https://maps.googleapis.com/maps/api/streetview?location=30.268066,-97.742813&heading=0&pitch=-10&fov=90&size=640x640&source=outdoor&key=srv"
        );

        let calls = fetcher.calls();
        let static_calls: Vec<&HttpRequest> = calls.iter().filter(|c| c.url.contains("/maps/api/streetview?")).collect();
        assert_eq!(static_calls.len(), 8);
        assert!(static_calls.iter().all(|c| c.header_value("Referer") == Some("http://localhost:4173/")));
        let geo = calls.iter().find(|c| c.url.contains("GeoPhotoService")).unwrap();
        assert!(geo.url.contains("!3d30.268066!4d-97.742813!2d50!"));
        assert!(geo.url.ends_with("&callback=_"));
        assert_eq!(geo.header_value("Referer"), None);
        // Origin metadata, then each of the two near neighbours; the far one is never looked up.
        let meta: Vec<&str> = calls
            .iter()
            .filter(|c| c.url.contains("/streetview/metadata"))
            .map(|c| c.url.as_str())
            .collect();
        assert_eq!(
            meta,
            [
                "https://maps.googleapis.com/maps/api/streetview/metadata?location=30.268066,-97.742813&source=outdoor&key=srv",
                "https://maps.googleapis.com/maps/api/streetview/metadata?location=30.26814,-97.742813&source=outdoor&key=srv",
                "https://maps.googleapis.com/maps/api/streetview/metadata?location=30.26799,-97.742813&source=outdoor&key=srv",
            ]
        );
    }

    #[test]
    fn without_neighbors_only_the_origin_is_fetched_and_metadata_errors_surface() {
        let ctx = test_context("streetview_headings_plain", &[]);
        let fetcher = MockFetcher::new(|_: &HttpRequest| ok_response("x"));
        let opts = parse_args(&["--lat", "1", "--lon", "2", "--key", "k"].iter().map(|s| s.to_string()).collect::<Vec<_>>()).unwrap();
        let written = execute(&opts, &ctx, &fetcher).unwrap();
        assert_eq!(written.len(), 8);
        assert_eq!(fetcher.calls().len(), 8);
        assert!(written[1].ends_with("sv_1.000000_2.000000_045_NE.jpg"));

        // A neighbour search that is not JSONP gives no neighbours, not an error.
        assert!(parse_neighbor_locations("<html>", 15.0).unwrap_err().contains("could not parse"));
        assert!(parse_neighbor_locations("_([1])", 15.0).unwrap_err().contains("could not extract"));
    }
}
