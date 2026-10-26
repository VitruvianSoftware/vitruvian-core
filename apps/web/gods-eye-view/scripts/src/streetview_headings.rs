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
    "Usage: node tools/streetview-headings.mjs --lat <lat> --lon <lon> [--fov 90] [--pitch 0] [--size 640x640] [--neighbors]";

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

/// Port of `loadApiKey` from `tools/streetview-headings.mjs`.
pub fn load_api_key(
    override_key: Option<&str>,
    environment: &HashMap<String, String>,
    dotenv_content: Option<&str>,
) -> Result<String, String> {
    if let Some(k) = override_key {
        if !k.trim().is_empty() {
            return Ok(k.to_string());
        }
    }
    let server_only = resolve_google_server_key(environment, &HashMap::new());
    if !server_only.is_empty() && environment.contains_key("GOOGLE_MAPS_SERVER_API_KEY") {
        let trimmed = environment
            .get("GOOGLE_MAPS_SERVER_API_KEY")
            .map(|s| s.trim())
            .unwrap_or("");
        if !trimmed.is_empty() {
            return Ok(trimmed.to_string());
        }
    }

    let mut from_dotenv = HashMap::new();
    if let Some(content) = dotenv_content {
        for line in content.lines() {
            let trimmed = line.trim();
            if trimmed.is_empty() || trimmed.starts_with('#') {
                continue;
            }
            if let Some(eq_idx) = trimmed.find('=') {
                let k = trimmed[..eq_idx].trim().to_string();
                let mut v = trimmed[eq_idx + 1..].trim().to_string();
                if (v.starts_with('"') && v.ends_with('"') && v.len() >= 2)
                    || (v.starts_with('\'') && v.ends_with('\'') && v.len() >= 2)
                {
                    v = v[1..v.len() - 1].to_string();
                }
                from_dotenv.insert(k, v);
            }
        }
    }

    let key = resolve_google_server_key(environment, &from_dotenv);
    if !key.is_empty() {
        return Ok(key);
    }
    Err(
        "No API key found. Set GOOGLE_MAPS_SERVER_API_KEY (or GOOGLE_MAPS_API_KEY) in .env or pass --key."
            .into(),
    )
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
    let start_paren = match jsonp_text.find('(') {
        Some(idx) => idx + 1,
        None => return Vec::new(),
    };
    let end_paren = match jsonp_text.rfind(')') {
        Some(idx) if idx >= start_paren => idx,
        _ => return Vec::new(),
    };
    let json_str = jsonp_text[start_paren..end_paren].trim();
    let data: serde_json::Value = match serde_json::from_str(json_str) {
        Ok(v) => v,
        Err(_) => return Vec::new(),
    };

    let links = match data
        .get(1)
        .and_then(|v| v.get(5))
        .and_then(|v| v.get(0))
        .and_then(|v| v.get(3))
        .and_then(|v| v.get(0))
        .and_then(|v| v.as_array())
    {
        Some(arr) if !arr.is_empty() => arr,
        _ => return Vec::new(),
    };

    let origin_lat = match links[0]
        .get(2)
        .and_then(|v| v.get(0))
        .and_then(|v| v.get(2))
        .and_then(|v| v.as_f64())
    {
        Some(lat) => lat,
        None => return Vec::new(),
    };
    let origin_lon = match links[0]
        .get(2)
        .and_then(|v| v.get(0))
        .and_then(|v| v.get(3))
        .and_then(|v| v.as_f64())
    {
        Some(lon) => lon,
        None => return Vec::new(),
    };

    let mut neighbors = Vec::new();
    for link in links.iter().skip(1) {
        let coord = match link.get(2).and_then(|v| v.get(0)) {
            Some(c) => c,
            None => continue,
        };
        let nlat = match coord.get(2).and_then(|v| v.as_f64()) {
            Some(v) => v,
            None => continue,
        };
        let nlon = match coord.get(3).and_then(|v| v.as_f64()) {
            Some(v) => v,
            None => continue,
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

    neighbors
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
        lat, lon, heading, pitch, fov, size, api_key
    )
}

pub fn heading_output_filename(lat: f64, lon: f64, heading: u32, name: &str) -> String {
    format!("sv_{:.6}_{:.6}_{:03}_{}.jpg", lat, lon, heading, name)
}

pub fn run(args: &[String]) -> Result<String, String> {
    if args.iter().any(|a| a == "--help") {
        return Ok(HELP_TEXT.to_string());
    }
    let opts = parse_args(args)?;
    let env_map: HashMap<String, String> = std::env::vars().collect();
    let dotenv = std::fs::read_to_string(".env").ok();
    let _api_key = load_api_key(opts.key.as_deref(), &env_map, dotenv.as_deref())?;
    let dirs = generate_heading_directions(opts.step);
    Ok(format!(
        "Street View Headings: {:.6}, {:.6} ({} headings, fov={}, pitch={}, size={})",
        opts.lat,
        opts.lon,
        dirs.len(),
        opts.fov,
        opts.pitch,
        opts.size
    ))
}
