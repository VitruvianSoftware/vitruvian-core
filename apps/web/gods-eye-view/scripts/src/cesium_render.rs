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

use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RenderMode {
    Direct,
    LookAt,
}

impl RenderMode {
    pub fn as_str(&self) -> &'static str {
        match self {
            RenderMode::Direct => "direct",
            RenderMode::LookAt => "lookat",
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct CesiumRenderOpts {
    pub lat: Option<f64>,
    pub lon: Option<f64>,
    pub lookat_lat: Option<f64>,
    pub lookat_lon: Option<f64>,
    pub heading: f64,
    pub pitch: f64,
    pub height: f64,
    pub fov: f64,
    pub width: u32,
    pub height_px: u32,
    pub sse: f64,
    pub timeout: u32,
    pub outdir: String,
    pub key: Option<String>,
    pub mode: RenderMode,
}

#[derive(Debug, Clone, PartialEq)]
pub enum AssetRoute {
    NoContent,
    File(PathBuf),
    NotFound,
}

#[derive(Debug, Clone, PartialEq)]
pub struct CesiumRenderPlan {
    pub mode: RenderMode,
    pub render_url: String,
    pub output_filename: String,
    pub output_path: PathBuf,
    pub viewport_width: u32,
    pub viewport_height: u32,
    pub sse_ladder: Vec<f64>,
    pub chromium_args: Vec<&'static str>,
}

pub const HELP_TEXT: &str = "\
Usage:
  Direct:  node tools/cesium-render.mjs --lat <lat> --lon <lon> [options]
  LookAt:  node tools/cesium-render.mjs --lookat-lat <lat> --lookat-lon <lon> [options]

Position (pick one pair):
  --lat        Camera latitude (direct mode)
  --lon        Camera longitude (direct mode)
  --lookat-lat Target latitude to look at (computes camera position)
  --lookat-lon Target longitude to look at (computes camera position)

Camera:
  --heading    Compass heading (default: 0)
  --pitch      Camera pitch (default: -10, must be <0 for lookat mode)
  --height     Meters above ground (default: 8)
  --fov        Vertical FOV degrees (default: 60)

Output:
  --width      Image width (default: 1280)
  --height-px  Image height (default: 720)
  --sse        Screen space error, lower=sharper (default: 2)
  --timeout    Timeout seconds (default: 30)
  --outdir     Output dir (default: output/)
  --key        Google Maps API key";

pub fn parse_args(args: &[String]) -> Result<CesiumRenderOpts, String> {
    let mut lat: Option<f64> = None;
    let mut lon: Option<f64> = None;
    let mut lookat_lat: Option<f64> = None;
    let mut lookat_lon: Option<f64> = None;
    let mut heading: f64 = 0.0;
    let mut pitch: f64 = -10.0;
    let mut height: f64 = 8.0;
    let mut fov: f64 = 60.0;
    let mut width: u32 = 1280;
    let mut height_px: u32 = 720;
    let mut sse: f64 = 2.0;
    let mut timeout: u32 = 30;
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
            "--lookat-lat" => {
                i += 1;
                lookat_lat = Some(
                    args.get(i)
                        .ok_or_else(|| "Error: --lookat-lat requires a value.".to_string())?
                        .parse::<f64>()
                        .map_err(|_| "Error: invalid --lookat-lat value.".to_string())?,
                );
            }
            "--lookat-lon" => {
                i += 1;
                lookat_lon = Some(
                    args.get(i)
                        .ok_or_else(|| "Error: --lookat-lon requires a value.".to_string())?
                        .parse::<f64>()
                        .map_err(|_| "Error: invalid --lookat-lon value.".to_string())?,
                );
            }
            "--heading" => {
                i += 1;
                heading = args
                    .get(i)
                    .ok_or_else(|| "Error: --heading requires a value.".to_string())?
                    .parse::<f64>()
                    .map_err(|_| "Error: invalid --heading value.".to_string())?;
            }
            "--pitch" => {
                i += 1;
                pitch = args
                    .get(i)
                    .ok_or_else(|| "Error: --pitch requires a value.".to_string())?
                    .parse::<f64>()
                    .map_err(|_| "Error: invalid --pitch value.".to_string())?;
            }
            "--height" => {
                i += 1;
                height = args
                    .get(i)
                    .ok_or_else(|| "Error: --height requires a value.".to_string())?
                    .parse::<f64>()
                    .map_err(|_| "Error: invalid --height value.".to_string())?;
            }
            "--fov" => {
                i += 1;
                fov = args
                    .get(i)
                    .ok_or_else(|| "Error: --fov requires a value.".to_string())?
                    .parse::<f64>()
                    .map_err(|_| "Error: invalid --fov value.".to_string())?;
            }
            "--width" => {
                i += 1;
                width = args
                    .get(i)
                    .ok_or_else(|| "Error: --width requires a value.".to_string())?
                    .parse::<u32>()
                    .map_err(|_| "Error: invalid --width value.".to_string())?;
            }
            "--height-px" => {
                i += 1;
                height_px = args
                    .get(i)
                    .ok_or_else(|| "Error: --height-px requires a value.".to_string())?
                    .parse::<u32>()
                    .map_err(|_| "Error: invalid --height-px value.".to_string())?;
            }
            "--sse" => {
                i += 1;
                sse = args
                    .get(i)
                    .ok_or_else(|| "Error: --sse requires a value.".to_string())?
                    .parse::<f64>()
                    .map_err(|_| "Error: invalid --sse value.".to_string())?;
            }
            "--timeout" => {
                i += 1;
                timeout = args
                    .get(i)
                    .ok_or_else(|| "Error: --timeout requires a value.".to_string())?
                    .parse::<u32>()
                    .map_err(|_| "Error: invalid --timeout value.".to_string())?;
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

    let has_direct = lat.is_some() && lon.is_some();
    let has_lookat = lookat_lat.is_some() && lookat_lon.is_some();
    let has_partial_direct = lat.is_some() != lon.is_some();
    let has_partial_lookat = lookat_lat.is_some() != lookat_lon.is_some();

    if has_partial_direct {
        return Err("Error: --lat and --lon must both be provided.".into());
    }
    if has_partial_lookat {
        return Err("Error: --lookat-lat and --lookat-lon must both be provided.".into());
    }
    if has_direct && has_lookat {
        return Err("Error: Use --lat/--lon OR --lookat-lat/--lookat-lon, not both.".into());
    }
    if !has_direct && !has_lookat {
        return Err(
            "Error: Provide --lat/--lon (direct) or --lookat-lat/--lookat-lon (look-at).".into(),
        );
    }

    let mode = if has_lookat {
        if pitch >= 0.0 {
            return Err(
                "Error: --pitch must be negative in lookat mode (camera looks down at target)."
                    .into(),
            );
        }
        RenderMode::LookAt
    } else {
        RenderMode::Direct
    };

    Ok(CesiumRenderOpts {
        lat,
        lon,
        lookat_lat,
        lookat_lon,
        heading,
        pitch,
        height,
        fov,
        width,
        height_px,
        sse,
        timeout,
        outdir,
        key,
        mode,
    })
}

pub fn load_api_key(
    override_key: Option<&str>,
    env_key: Option<&str>,
    dotenv_content: Option<&str>,
) -> Result<String, String> {
    if let Some(k) = override_key {
        if !k.trim().is_empty() {
            return Ok(k.to_string());
        }
    }
    if let Some(k) = env_key {
        if !k.trim().is_empty() {
            return Ok(k.to_string());
        }
    }
    if let Some(content) = dotenv_content {
        for line in content.lines() {
            let trimmed = line.trim();
            if trimmed.starts_with('#') || !trimmed.contains('=') {
                continue;
            }
            if let Some(eq_idx) = trimmed.find('=') {
                let k = trimmed[..eq_idx].trim();
                let v = trimmed[eq_idx + 1..].trim();
                if k == "GOOGLE_MAPS_API_KEY" && !v.is_empty() {
                    return Ok(v.to_string());
                }
            }
        }
    }
    Err("Error: No API key found. Set GOOGLE_MAPS_API_KEY in .env or pass --key.".into())
}

pub fn mime_type_for_path(path: &str) -> &'static str {
    let ext = path.rfind('.').map(|idx| &path[idx..]).unwrap_or("");
    match ext {
        ".html" => "text/html",
        ".js" => "application/javascript",
        ".css" => "text/css",
        ".json" => "application/json",
        ".png" => "image/png",
        ".jpg" => "image/jpeg",
        ".gif" => "image/gif",
        ".svg" => "image/svg+xml",
        ".wasm" => "application/wasm",
        ".glb" => "model/gltf-binary",
        _ => "application/octet-stream",
    }
}

pub fn resolve_asset_route(pathname: &str, cesium_root: &Path, render_html: &Path) -> AssetRoute {
    if pathname == "/favicon.ico" {
        AssetRoute::NoContent
    } else if pathname == "/" || pathname == "/index.html" {
        AssetRoute::File(render_html.to_path_buf())
    } else if let Some(rest) = pathname.strip_prefix("/cesium/") {
        if rest.split('/').any(|seg| seg == "..") {
            return AssetRoute::NotFound;
        }
        AssetRoute::File(cesium_root.join(rest))
    } else {
        AssetRoute::NotFound
    }
}

pub fn chromium_launch_args() -> Vec<&'static str> {
    vec![
        "--no-sandbox",
        "--disable-setuid-sandbox",
        "--use-gl=angle",
        "--use-angle=swiftshader",
        "--disable-dev-shm-usage",
        "--disable-web-security",
        "--disable-background-timer-throttling",
        "--disable-renderer-backgrounding",
    ]
}

pub fn progressive_sse_ladder(target_sse: f64) -> Vec<f64> {
    let base_steps = [16.0, 12.0, 8.0, 6.0, 4.0];
    let mut ladder: Vec<f64> = base_steps
        .iter()
        .copied()
        .filter(|&s| s > target_sse)
        .collect();
    ladder.push(target_sse);
    ladder
}

fn fmt_num(n: f64) -> String {
    if n.fract() == 0.0 {
        format!("{:.0}", n)
    } else {
        format!("{}", n)
    }
}

pub fn build_render_url(port: u16, opts: &CesiumRenderOpts, api_key: &str) -> String {
    let mut params = vec![
        format!("heading={}", fmt_num(opts.heading)),
        format!("pitch={}", fmt_num(opts.pitch)),
        format!("height={}", fmt_num(opts.height)),
        format!("fov={}", fmt_num(opts.fov)),
        format!("sse={}", fmt_num(opts.sse)),
        format!("key={}", api_key),
        format!("mode={}", opts.mode.as_str()),
    ];
    match opts.mode {
        RenderMode::LookAt => {
            params.push(format!("targetLat={}", fmt_num(opts.lookat_lat.unwrap_or(0.0))));
            params.push(format!("targetLon={}", fmt_num(opts.lookat_lon.unwrap_or(0.0))));
        }
        RenderMode::Direct => {
            params.push(format!("lat={}", fmt_num(opts.lat.unwrap_or(0.0))));
            params.push(format!("lon={}", fmt_num(opts.lon.unwrap_or(0.0))));
        }
    }
    format!("http://127.0.0.1:{}/?{}", port, params.join("&"))
}

pub fn build_output_filename(opts: &CesiumRenderOpts) -> String {
    let (file_lat, file_lon, prefix) = match opts.mode {
        RenderMode::LookAt => (
            opts.lookat_lat.unwrap_or(0.0),
            opts.lookat_lon.unwrap_or(0.0),
            "cesium_lookat",
        ),
        RenderMode::Direct => (
            opts.lat.unwrap_or(0.0),
            opts.lon.unwrap_or(0.0),
            "cesium",
        ),
    };
    format!(
        "{}_{}_{}_h{}_p{}_{}m_{}x{}.jpg",
        prefix,
        fmt_num(file_lat),
        fmt_num(file_lon),
        fmt_num(opts.heading),
        fmt_num(opts.pitch),
        fmt_num(opts.height),
        opts.width,
        opts.height_px
    )
}

/// Computes the camera (lat, lon, slant_distance_m) in look-at mode so the target
/// point is centered at the given negative pitch and height above ground.
pub fn compute_lookat_camera_offset(
    target_lat: f64,
    target_lon: f64,
    heading_deg: f64,
    pitch_deg: f64,
    height_m: f64,
) -> (f64, f64, f64) {
    let pitch_rad = (-pitch_deg).to_radians().max(1e-6);
    let ground_dist_m = height_m / pitch_rad.tan();
    let slant_dist_m = (ground_dist_m * ground_dist_m + height_m * height_m).sqrt();

    // Camera stands behind the heading direction (heading + 180 deg)
    let back_azimuth_rad = (heading_deg + 180.0).to_radians();
    let d_north = ground_dist_m * back_azimuth_rad.cos();
    let d_east = ground_dist_m * back_azimuth_rad.sin();

    let d_lat = d_north / 111_320.0;
    let d_lon = d_east / (111_320.0 * target_lat.to_radians().cos().abs().max(1e-6));

    (target_lat + d_lat, target_lon + d_lon, slant_dist_m)
}

pub fn build_render_plan(
    opts: &CesiumRenderOpts,
    api_key: &str,
    port: u16,
    project_root: &Path,
) -> CesiumRenderPlan {
    let output_filename = build_output_filename(opts);
    let output_path = project_root.join(&opts.outdir).join(&output_filename);
    CesiumRenderPlan {
        mode: opts.mode,
        render_url: build_render_url(port, opts, api_key),
        output_filename,
        output_path,
        viewport_width: opts.width,
        viewport_height: opts.height_px,
        sse_ladder: progressive_sse_ladder(opts.sse),
        chromium_args: chromium_launch_args(),
    }
}

pub fn run(args: &[String]) -> Result<String, String> {
    if args.iter().any(|a| a == "--help") {
        return Ok(HELP_TEXT.to_string());
    }
    let opts = parse_args(args)?;
    let env_key = std::env::var("GOOGLE_MAPS_API_KEY").ok();
    let dotenv_content = std::fs::read_to_string(".env").ok();
    let api_key = load_api_key(
        opts.key.as_deref(),
        env_key.as_deref(),
        dotenv_content.as_deref(),
    )?;
    let plan = build_render_plan(&opts, &api_key, 0, Path::new("."));
    Ok(format!(
        "Cesium 3D Renderer [{}] -> {}",
        plan.mode.as_str(),
        plan.output_filename
    ))
}
