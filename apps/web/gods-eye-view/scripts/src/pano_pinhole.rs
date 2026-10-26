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
use std::path::Path;

#[derive(Debug, Clone, PartialEq)]
pub struct PanoPinholeOpts {
    pub input: String,
    pub heading: f64,
    pub pitch: f64,
    pub roll: f64,
    pub hfov: f64,
    pub focal: Option<f64>,
    pub width: u32,
    pub height: u32,
    pub step: u32,
    pub all: bool,
    pub outdir: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct CameraFovMetrics {
    pub focal_px: f64,
    pub hfov_deg: f64,
    pub vfov_deg: f64,
    pub dfov_deg: f64,
    pub fov_label: String,
}

pub const HELP_TEXT: &str = "\
Usage: node tools/pano-pinhole.mjs --input <panorama.jpg> [options]

Required:
  --input    Equirectangular panorama image path

Camera:
  --heading  Compass heading degrees, 0=N 90=E (default: 0)
  --pitch    Pitch degrees, 0=horizon +up (default: 0)
  --roll     Roll degrees, +CW (default: 0)
  --hfov     Horizontal FOV degrees (default: 90)
  --focal    Focal length in pixels (overrides --hfov)

Output:
  --width    Output width pixels (default: 1920)
  --height   Output height pixels (default: 1080)
  --all      Render all compass headings (ignores --heading)
  --step     Heading step degrees for --all mode (default: 45)
  --outdir   Output directory (default: output/)";

pub fn parse_args(args: &[String]) -> Result<PanoPinholeOpts, String> {
    let mut input: Option<String> = None;
    let mut heading: f64 = 0.0;
    let mut pitch: f64 = 0.0;
    let mut roll: f64 = 0.0;
    let mut hfov: f64 = 90.0;
    let mut focal: Option<f64> = None;
    let mut width: u32 = 1920;
    let mut height: u32 = 1080;
    let mut step: u32 = 45;
    let mut all = false;
    let mut outdir = "output".to_string();

    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--help" => return Err(HELP_TEXT.to_string()),
            "--input" => {
                i += 1;
                input = args.get(i).cloned();
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
            "--roll" => {
                i += 1;
                roll = args
                    .get(i)
                    .ok_or_else(|| "Error: --roll requires a value.".to_string())?
                    .parse::<f64>()
                    .map_err(|_| "Error: invalid --roll value.".to_string())?;
            }
            "--hfov" => {
                i += 1;
                hfov = args
                    .get(i)
                    .ok_or_else(|| "Error: --hfov requires a value.".to_string())?
                    .parse::<f64>()
                    .map_err(|_| "Error: invalid --hfov value.".to_string())?;
            }
            "--focal" => {
                i += 1;
                focal = Some(
                    args.get(i)
                        .ok_or_else(|| "Error: --focal requires a value.".to_string())?
                        .parse::<f64>()
                        .map_err(|_| "Error: invalid --focal value.".to_string())?,
                );
            }
            "--width" => {
                i += 1;
                width = args
                    .get(i)
                    .ok_or_else(|| "Error: --width requires a value.".to_string())?
                    .parse::<u32>()
                    .map_err(|_| "Error: invalid --width value.".to_string())?;
            }
            "--height" => {
                i += 1;
                height = args
                    .get(i)
                    .ok_or_else(|| "Error: --height requires a value.".to_string())?
                    .parse::<u32>()
                    .map_err(|_| "Error: invalid --height value.".to_string())?;
            }
            "--step" => {
                i += 1;
                step = args
                    .get(i)
                    .ok_or_else(|| "Error: --step requires a value.".to_string())?
                    .parse::<u32>()
                    .map_err(|_| "Error: invalid --step value.".to_string())?;
            }
            "--all" => {
                all = true;
            }
            "--outdir" => {
                i += 1;
                outdir = args
                    .get(i)
                    .ok_or_else(|| "Error: --outdir requires a value.".to_string())?
                    .clone();
            }
            _ => {}
        }
        i += 1;
    }

    let input = match input {
        Some(s) if !s.is_empty() => s,
        _ => return Err("Error: --input is required.".into()),
    };

    Ok(PanoPinholeOpts {
        input,
        heading,
        pitch,
        roll,
        hfov,
        focal,
        width,
        height,
        step,
        all,
        outdir,
    })
}

pub fn compass_label(heading: u32) -> &'static str {
    match heading {
        0 => "N",
        15 => "NNE",
        30 => "NNE2",
        45 => "NE",
        60 => "ENE",
        75 => "ENE2",
        90 => "E",
        105 => "ESE",
        120 => "ESE2",
        135 => "SE",
        150 => "SSE",
        165 => "SSE2",
        180 => "S",
        195 => "SSW",
        210 => "SSW2",
        225 => "SW",
        240 => "WSW",
        255 => "WSW2",
        270 => "W",
        285 => "WNW",
        300 => "WNW2",
        315 => "NW",
        330 => "NNW",
        345 => "NNW2",
        _ => "",
    }
}

pub fn compass_label_string(heading: f64) -> String {
    if heading.fract() == 0.0 && heading >= 0.0 && heading < 360.0 {
        let h = heading as u32;
        let known = compass_label(h);
        if !known.is_empty() {
            return known.to_string();
        }
        return format!("H{}", h);
    }
    format!("H{}", heading)
}

/// Sample the equirectangular panorama at fractional pixel coords `(u, v)`
/// using bilinear interpolation. Wraps horizontally for panorama continuity.
pub fn sample_bilinear(buf: &[u8], p_w: usize, p_h: usize, mut u: f64, mut v: f64) -> [u8; 3] {
    let w_f = p_w as f64;
    let h_f = p_h as f64;

    u = ((u % w_f) + w_f) % w_f;
    v = v.clamp(0.0, (h_f - 1.001).max(0.0));

    let x0 = u.floor() as usize;
    let y0 = v.floor() as usize;
    let x1 = (x0 + 1) % p_w;
    let y1 = (y0 + 1).min(p_h - 1);

    let fx = u - x0 as f64;
    let fy = v - y0 as f64;

    let i00 = (y0 * p_w + x0) * 3;
    let i10 = (y0 * p_w + x1) * 3;
    let i01 = (y1 * p_w + x0) * 3;
    let i11 = (y1 * p_w + x1) * 3;

    let w00 = (1.0 - fx) * (1.0 - fy);
    let w10 = fx * (1.0 - fy);
    let w01 = (1.0 - fx) * fy;
    let w11 = fx * fy;

    let r =
        buf[i00] as f64 * w00 + buf[i10] as f64 * w10 + buf[i01] as f64 * w01 + buf[i11] as f64 * w11;
    let g = buf[i00 + 1] as f64 * w00
        + buf[i10 + 1] as f64 * w10
        + buf[i01 + 1] as f64 * w01
        + buf[i11 + 1] as f64 * w11;
    let b = buf[i00 + 2] as f64 * w00
        + buf[i10 + 2] as f64 * w10
        + buf[i01 + 2] as f64 * w01
        + buf[i11 + 2] as f64 * w11;

    [
        r.round().clamp(0.0, 255.0) as u8,
        g.round().clamp(0.0, 255.0) as u8,
        b.round().clamp(0.0, 255.0) as u8,
    ]
}

/// Build a 3x3 rotation matrix `R = Ry(heading) * Rx(-pitch) * Rz(roll)`.
pub fn build_rotation_matrix(heading_rad: f64, pitch_rad: f64, roll_rad: f64) -> [[f64; 3]; 3] {
    let ch = heading_rad.cos();
    let sh = heading_rad.sin();
    let cp = (-pitch_rad).cos();
    let sp = (-pitch_rad).sin();
    let cr = roll_rad.cos();
    let sr = roll_rad.sin();

    [
        [ch * cr + sh * sp * sr, -ch * sr + sh * sp * cr, sh * cp],
        [cp * sr, cp * cr, -sp],
        [-sh * cr + ch * sp * sr, sh * sr + ch * sp * cr, ch * cp],
    ]
}

#[inline]
pub fn rotate_vec(mat: &[[f64; 3]; 3], x: f64, y: f64, z: f64) -> [f64; 3] {
    [
        mat[0][0] * x + mat[0][1] * y + mat[0][2] * z,
        mat[1][0] * x + mat[1][1] * y + mat[1][2] * z,
        mat[2][0] * x + mat[2][1] * y + mat[2][2] * z,
    ]
}

pub fn compute_camera_fovs(
    width: u32,
    height: u32,
    hfov_deg: f64,
    focal_override: Option<f64>,
) -> CameraFovMetrics {
    let w = width as f64;
    let h = height as f64;
    let focal_px = match focal_override {
        Some(f) => f,
        None => {
            let hfov_rad = hfov_deg * PI / 180.0;
            (w / 2.0) / (hfov_rad / 2.0).tan()
        }
    };
    let fov_label = match focal_override {
        Some(f) => format!("f{}", f.round() as i64),
        None => format!("fov{}", hfov_deg.round() as i64),
    };
    let computed_hfov = 2.0 * ((w / 2.0) / focal_px).atan() * 180.0 / PI;
    let vfov_deg = 2.0 * ((h / 2.0) / focal_px).atan() * 180.0 / PI;
    let diag_px = (w * w + h * h).sqrt();
    let dfov_deg = 2.0 * ((diag_px / 2.0) / focal_px).atan() * 180.0 / PI;

    CameraFovMetrics {
        focal_px,
        hfov_deg: computed_hfov,
        vfov_deg,
        dfov_deg,
        fov_label,
    }
}

pub fn headings_for_opts(opts: &PanoPinholeOpts) -> Vec<f64> {
    if opts.all {
        let step = opts.step.max(1);
        let mut list = Vec::new();
        let mut h = 0u32;
        while h < 360 {
            list.push(h as f64);
            h += step;
        }
        list
    } else {
        vec![opts.heading]
    }
}

pub fn build_pinhole_output_name(
    input_path: &str,
    heading: f64,
    pitch: f64,
    fov_label: &str,
    out_w: u32,
    out_h: u32,
) -> String {
    let p = Path::new(input_path);
    let stem = p
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("panorama");
    let compass = compass_label_string(heading);
    let h_str = if heading.fract() == 0.0 {
        format!("{:.0}", heading)
    } else {
        format!("{}", heading)
    };
    let p_str = if pitch.fract() == 0.0 {
        format!("{:.0}", pitch)
    } else {
        format!("{}", pitch)
    };
    format!(
        "pinhole_{}_h{}_p{}_{}_{}x{}_{}.jpg",
        stem, h_str, p_str, fov_label, out_w, out_h, compass
    )
}

/// Renders a single pinhole view from an equirectangular RGB panorama buffer.
#[allow(clippy::too_many_arguments)]
pub fn render_view(
    pano_buf: &[u8],
    p_w: usize,
    p_h: usize,
    heading: f64,
    pitch: f64,
    roll: f64,
    focal_px: f64,
    out_w: usize,
    out_h: usize,
) -> Vec<u8> {
    let heading_rad = heading * PI / 180.0;
    let pitch_rad = pitch * PI / 180.0;
    let roll_rad = roll * PI / 180.0;
    let mat = build_rotation_matrix(heading_rad, pitch_rad, roll_rad);

    let mut out_buf = vec![0u8; out_w * out_h * 3];
    let half_w = out_w as f64 / 2.0;
    let half_h = out_h as f64 / 2.0;
    let p_w_f = p_w as f64;
    let p_h_f = p_h as f64;

    for py in 0..out_h {
        let cam_y = -(py as f64 - half_h + 0.5);
        for px in 0..out_w {
            let cam_x = px as f64 - half_w + 0.5;
            let cam_z = focal_px;

            let len = (cam_x * cam_x + cam_y * cam_y + cam_z * cam_z).sqrt();
            let nx = cam_x / len;
            let ny = cam_y / len;
            let nz = cam_z / len;

            let [wx, wy, wz] = rotate_vec(&mat, nx, ny, nz);

            let lon = wx.atan2(wz);
            let lat = wy.clamp(-1.0, 1.0).asin();

            let u = ((lon / PI + 1.0) / 2.0) * p_w_f;
            let v = (0.5 - lat / PI) * p_h_f;

            let [r, g, b] = sample_bilinear(pano_buf, p_w, p_h, u, v);
            let out_idx = (py * out_w + px) * 3;
            out_buf[out_idx] = r;
            out_buf[out_idx + 1] = g;
            out_buf[out_idx + 2] = b;
        }
    }

    out_buf
}

pub fn run(args: &[String]) -> Result<String, String> {
    if args.iter().any(|a| a == "--help") {
        return Ok(HELP_TEXT.to_string());
    }
    let opts = parse_args(args)?;
    let metrics = compute_camera_fovs(opts.width, opts.height, opts.hfov, opts.focal);
    let headings = headings_for_opts(&opts);
    Ok(format!(
        "Pano -> Pinhole Renderer: input={}, views={}, hfov={:.1} deg (focal={:.1} px), out={}x{}",
        opts.input,
        headings.len(),
        metrics.hfov_deg,
        metrics.focal_px,
        opts.width,
        opts.height
    ))
}
