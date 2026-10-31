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
use std::path::{Path, PathBuf};
use std::time::Instant;

use crate::tool_io::{encode_jpeg, read_rgb, to_fixed, RgbImage, ToolContext, JPEG_QUALITY};

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
Usage: bazel run //apps/web/gods-eye-view:pano_pinhole -- --input <panorama.jpg> [options]

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
    if heading.fract() == 0.0 && (0.0..360.0).contains(&heading) {
        let h = heading as u32;
        let known = compass_label(h);
        if !known.is_empty() {
            return known.to_string();
        }
        return format!("H{}", h);
    }
    format!("H{}", crate::tool_io::js_num(heading))
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
    // basename(input, extname(input)): a leading dot is part of the name.
    let base = Path::new(input_path)
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or("panorama");
    let stem = match base.rfind('.') {
        Some(i) if i > 0 => &base[..i],
        _ => base,
    };
    let compass = compass_label_string(heading);
    format!(
        "pinhole_{}_h{}_p{}_{}_{}x{}_{}.jpg",
        stem,
        num_label(heading),
        num_label(pitch),
        fov_label,
        out_w,
        out_h,
        compass
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

/// Number or text as the JS tool's template strings printed it (`p${pitch}`).
fn num_label(v: f64) -> String {
    crate::tool_io::js_num(v)
}

/// Render every requested view of `opts.input` into `opts.outdir`; returns the
/// written paths. Port of `main()` in the former `tools/pano-pinhole.mjs`.
pub fn execute(opts: &PanoPinholeOpts, ctx: &ToolContext) -> Result<Vec<PathBuf>, String> {
    let metrics = compute_camera_fovs(opts.width, opts.height, opts.hfov, opts.focal);
    let focal_px = metrics.focal_px;
    let headings = headings_for_opts(opts);

    println!("\nPano \u{2192} Pinhole Renderer");
    println!("  Input    : {}", opts.input);
    if opts.all {
        println!(
            "  Mode     : all headings ({} views, step {}\u{b0})",
            headings.len(),
            opts.step
        );
    } else {
        println!("  Mode     : heading {}\u{b0}", num_label(opts.heading));
    }
    println!("  Pitch    : {}\u{b0}", num_label(opts.pitch));
    if opts.roll != 0.0 {
        println!("  Roll     : {}\u{b0}", num_label(opts.roll));
    }
    println!(
        "  HFOV     : {}\u{b0} (focal \u{2248} {} px)",
        to_fixed(metrics.hfov_deg, 1),
        to_fixed(focal_px, 1)
    );
    println!("  Output   : {}x{}", opts.width, opts.height);

    println!("\nLoading panorama...");
    let pano = read_rgb(&ctx.input_path(&opts.input))?;
    println!("  Panorama : {}x{}", pano.width, pano.height);

    let outdir = ctx.outdir(&opts.outdir);
    std::fs::create_dir_all(&outdir).map_err(|e| format!("{}: {}", outdir.display(), e))?;

    let out_w = opts.width as usize;
    let out_h = opts.height as usize;
    println!("\nRendering {} view(s)...", headings.len());
    let t0 = Instant::now();
    let mut written = Vec::new();
    for &heading in &headings {
        let t1 = Instant::now();
        let data = render_view(
            &pano.data,
            pano.width,
            pano.height,
            heading,
            opts.pitch,
            opts.roll,
            focal_px,
            out_w,
            out_h,
        );
        let render_ms = t1.elapsed().as_millis();
        let out_name = build_pinhole_output_name(
            &opts.input,
            heading,
            opts.pitch,
            &metrics.fov_label,
            opts.width,
            opts.height,
        );
        let out_path = outdir.join(&out_name);
        let jpeg = encode_jpeg(
            &RgbImage {
                width: out_w,
                height: out_h,
                data,
            },
            JPEG_QUALITY,
        )?;
        std::fs::write(&out_path, jpeg).map_err(|e| format!("{}: {}", out_path.display(), e))?;
        let compass = compass_label_string(heading);
        println!(
            "  {:<4} ({:>3}\u{b0}): {}  ({}ms)",
            compass,
            num_label(heading),
            out_name,
            render_ms
        );
        written.push(out_path);
    }

    println!(
        "\n  Total: {} images in {}s",
        headings.len(),
        to_fixed(t0.elapsed().as_secs_f64(), 2)
    );
    println!("  Horizontal FOV : {}\u{b0}", to_fixed(metrics.hfov_deg, 1));
    println!("  Vertical FOV   : {}\u{b0}", to_fixed(metrics.vfov_deg, 1));
    println!("  Diagonal FOV   : {}\u{b0}", to_fixed(metrics.dfov_deg, 1));
    println!("  Focal length   : {} px", to_fixed(focal_px, 1));
    Ok(written)
}

/// The CLI: `--help` text, or render and print progress.
pub fn run(args: &[String]) -> Result<Option<String>, String> {
    if args.iter().any(|a| a == "--help") {
        return Ok(Some(HELP_TEXT.to_string()));
    }
    let opts = parse_args(args)?;
    execute(&opts, &ToolContext::from_process())?;
    Ok(None)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tool_io::{close, decode_rgb, png_bytes, test_context};

    pub const RED: [u8; 3] = [255, 0, 0];
    pub const GREEN: [u8; 3] = [0, 255, 0];
    pub const BLUE: [u8; 3] = [0, 0, 255];
    pub const YELLOW: [u8; 3] = [255, 255, 0];
    pub const WHITE: [u8; 3] = [255, 255, 255];
    pub const MAGENTA: [u8; 3] = [255, 0, 255];

    /// A 720x360 equirectangular panorama in the tool's convention (centre
    /// column = north, +90 east): north red, east green, south blue, west
    /// yellow, 45 degrees either side of each; above 67.5 degrees white, below
    /// -67.5 magenta.
    pub fn synthetic_pano() -> RgbImage {
        let (w, h) = (720usize, 360usize);
        let mut img = RgbImage::black(w, h);
        for y in 0..h {
            let lat = 90.0 - (y as f64 + 0.5) / h as f64 * 180.0;
            for x in 0..w {
                let lon = ((x as f64 + 0.5) / w as f64 * 2.0 - 1.0) * 180.0;
                let c = if lat > 67.5 {
                    WHITE
                } else if lat < -67.5 {
                    MAGENTA
                } else if (-45.0..45.0).contains(&lon) {
                    RED
                } else if (45.0..135.0).contains(&lon) {
                    GREEN
                } else if (-135.0..-45.0).contains(&lon) {
                    YELLOW
                } else {
                    BLUE
                };
                let i = (y * w + x) * 3;
                img.data[i..i + 3].copy_from_slice(&c);
            }
        }
        img
    }

    fn args(list: &[&str]) -> Vec<String> {
        list.iter().map(|s| s.to_string()).collect()
    }

    fn render(ctx: &ToolContext, extra: &[&str]) -> Vec<PathBuf> {
        let mut a = vec!["--input", "pano.png", "--width", "64", "--height", "48", "--hfov", "60", "--outdir", "out"];
        a.extend_from_slice(extra);
        execute(&parse_args(&args(&a)).unwrap(), ctx).unwrap()
    }

    fn setup(name: &str) -> ToolContext {
        let ctx = test_context(name, &[]);
        std::fs::write(ctx.cwd.join("pano.png"), png_bytes(&synthetic_pano())).unwrap();
        ctx
    }

    #[test]
    fn all_headings_look_at_the_matching_compass_quadrant() {
        let ctx = setup("pinhole_all");
        let written = render(&ctx, &["--all", "--step", "90"]);
        let names: Vec<String> = written
            .iter()
            .map(|p| p.file_name().unwrap().to_string_lossy().into_owned())
            .collect();
        assert_eq!(
            names,
            [
                "pinhole_pano_h0_p0_fov60_64x48_N.jpg",
                "pinhole_pano_h90_p0_fov60_64x48_E.jpg",
                "pinhole_pano_h180_p0_fov60_64x48_S.jpg",
                "pinhole_pano_h270_p0_fov60_64x48_W.jpg",
            ]
        );
        // --outdir resolves against the project root, --input against cwd.
        assert!(written.iter().all(|p| p.starts_with(ctx.project_root.join("out"))));
        for (path, want) in written.iter().zip([RED, GREEN, BLUE, YELLOW]) {
            let img = decode_rgb(&std::fs::read(path).unwrap()).unwrap();
            assert_eq!((img.width, img.height), (64, 48));
            // A 60 x 47 degree view at the horizon stays inside one quadrant.
            for y in (0..48).step_by(7) {
                for x in (0..64).step_by(7) {
                    assert!(
                        close(img.pixel(x, y), want, 12),
                        "{}: pixel ({},{}) = {:?}, want {:?}",
                        path.display(),
                        x,
                        y,
                        img.pixel(x, y),
                        want
                    );
                }
            }
        }
    }

    #[test]
    fn east_is_to_the_right_and_pitch_looks_up_and_down() {
        let ctx = setup("pinhole_axes");
        // Facing north-east: north (red) on the left, east (green) on the right.
        let ne = render(&ctx, &["--heading", "45"]);
        let img = decode_rgb(&std::fs::read(&ne[0]).unwrap()).unwrap();
        assert!(close(img.pixel(8, 24), RED, 12), "left {:?}", img.pixel(8, 24));
        assert!(close(img.pixel(56, 24), GREEN, 12), "right {:?}", img.pixel(56, 24));
        assert!(ne[0].ends_with("pinhole_pano_h45_p0_fov60_64x48_NE.jpg"));

        let up = render(&ctx, &["--pitch", "85"]);
        let img = decode_rgb(&std::fs::read(&up[0]).unwrap()).unwrap();
        assert!(close(img.pixel(32, 24), WHITE, 12), "up {:?}", img.pixel(32, 24));

        let down = render(&ctx, &["--pitch", "-85"]);
        assert!(down[0].ends_with("pinhole_pano_h0_p-85_fov60_64x48_N.jpg"));
        let img = decode_rgb(&std::fs::read(&down[0]).unwrap()).unwrap();
        assert!(close(img.pixel(32, 24), MAGENTA, 12), "down {:?}", img.pixel(32, 24));

        // Pitched up 60 degrees, the top of the frame reaches the zenith band
        // and the bottom stays on the horizon colour.
        let tilt = render(&ctx, &["--pitch", "60"]);
        let img = decode_rgb(&std::fs::read(&tilt[0]).unwrap()).unwrap();
        assert!(close(img.pixel(32, 1), WHITE, 12), "top {:?}", img.pixel(32, 1));
        assert!(close(img.pixel(32, 46), RED, 12), "bottom {:?}", img.pixel(32, 46));
    }

    #[test]
    fn focal_overrides_hfov_in_the_name_and_the_view() {
        let ctx = setup("pinhole_focal");
        // f = 8 px on a 64 px frame is a ~152 degree view: both edges leave north.
        let out = render(&ctx, &["--focal", "8"]);
        assert!(out[0].ends_with("pinhole_pano_h0_p0_f8_64x48_N.jpg"));
        let img = decode_rgb(&std::fs::read(&out[0]).unwrap()).unwrap();
        assert!(close(img.pixel(32, 24), RED, 12));
        assert!(close(img.pixel(1, 24), YELLOW, 12), "left {:?}", img.pixel(1, 24));
        assert!(close(img.pixel(62, 24), GREEN, 12), "right {:?}", img.pixel(62, 24));
    }

    /// Byte-for-byte parity with the JS tool's projection. Each row is
    /// (heading, pitch, roll, hfov, width, height, expected RGB hex): the
    /// output of `renderView` in the former tools/pano-pinhole.mjs (run under
    /// node 26 before it was deleted) for the formula-defined 64x32 panorama
    /// below. Same rotation, interpolation, wrap/clamp and rounding, so the
    /// raw renders are identical; only the JPEG encoder differs.
    #[test]
    fn render_matches_the_js_tool_byte_for_byte() {
        let (pw, ph) = (64usize, 32usize);
        let mut pano = vec![0u8; pw * ph * 3];
        for y in 0..ph {
            for x in 0..pw {
                for c in 0..3 {
                    pano[(y * pw + x) * 3 + c] = ((x * 7 + y * 13 + c * 50 + ((x ^ y) & 5) * 9) % 256) as u8;
                }
            }
        }
        let cases: [(f64, f64, f64, f64, usize, usize, &str); 4] = [
            (37.0, 12.0, 5.0, 75.0, 16, 12, "83b5e76d9fd16fa1d36fa1d372a4d683b5899fd103a4d608aadc1899cbb594c6f8a1d32ea4d608cc3b30db0d3fe4164887b9b77eb0bc75a7d97baddf7dafe193c572aadc0eaee012b6e81a9fd1cda1d371a7d912b3e517d14635e51749ec1e5096c854a0d2229bcd5c94c6948dbfc8a6d85fb4e618bbed1fc1f325a9db7aabdd1cb3e517baec1edd5841ee2052f12355aadc3eb0e214b3e517b3e517bcee20a2d4b9abdd31b4e618bdef21c09524c49328ce9532d78d3bde3142df1143e31547b7e923bcee20bef022c4f328c1f326a9db4faadc16b0e214b7e91bde1642e91b4ded1f51f6285ae31547de1042e41648c49028c9ba2dcae22ecdb231ce5532b1e315b8ea1cbeec22c39827ed2153b32456c02e60c13163d82254e91b4ded1f51cb292fcd1031d8163cdb233fd35537c0f224c5e329ca822ecd083aa82a5c0335670335670e4072862c5edc2456f82d5fb8dd1cc2d426c4c228ce4832d9363db289448e7c46d117498d1b4d353466283769274577154678093a6c5e3163f93062c1f325c5ce29cb632fcf1d339d1b4d4a2f613f3567843a6c48386aee2052f72a5cf0295b2f376917497b3554866f598bccac30d15b35d6083ada0c3e452c5e093b6d0f4173154779573f71f73062dc3062333a6c153a6c23558736689a396b9dd9283ddb0d3fdf1143e61b4d333a6c16487a1a4c7e2052841c4b7d2737693f3f710f41731446782c5e904072a44072a4dd0f41e7194bec1e50ce2557294e801e508227598b2b5d8f20528412447616487a194b7d1f51833567994678aa4d7fb1"),
            (270.0, -30.0, 0.0, 90.0, 12, 8, "184a7c194b7d2e60924e80b25486b85a8cbe4d7fb15284b66fa1d38abcee8dbff199cb321c4e80295b8d2d5f915f91c3699bcd6b9dcf5a8cbe6698ca8cbef098cac6a4d6089ed0342a5c8e3466983f71a36d9fd17baddf80b2e46d9fd17aacdea8da67aee012b5e719a3d5904375a75688ba6a9cce689acc6a9cce7badd7a9db17b5e71998ca86a3d507b5e219b3a2175385b773a5d782b4e689bbed81b3e590c2f4c3f427cf0933b0e214b6e81acb782fde10424e80b27aacde8ec0d29acc20a4d67ac04359bbe61fcf8733c9a82dc9db2dd91f51f12355588abc74a6d87caee08bbdefc6f62ad80a3cc6a72aeb6c539d31635f3759ba2c5e97356776a8da94c6dc88baeb96c8facab82ee91b4dd90b3d0b3d6f134577f5285ad725579d2f61"),
            (0.0, 88.0, -20.0, 120.0, 10, 10, "cf5833afac1398cab37caee05789bb2d5f911b4d7f2f61932e60921a4c7ee21446ce533296c8737dafe14b7daf1b427407396b1f51831e5082dc2d5fd63b3ad25436b9eb1d80b2e416487a294e80333a6c253d6fe7194bea1c4ecbc72fb7e91bb6e84976a8da9379abf32557c1a225c7f62bd13335eb1d4fe21d4fcebe32c9cf2daddf116b9dcf8bbde290c2c4b87c1cdf1143ec1e500b3d6f0e3567d6b63ade1042e315474678aa8abcee9dcf82a6d80abed222872f619b2658ed1f51ec1e502153854476a85c8ec0a5d7379acce8addf111042741042743062943062942f6193588abc5e90c2a1d305b6e81ac1f0252f61934476a8487aac2d5f913f71a375a7d96799cb7eb0e2b6e81ab3e5173567994779ab4c7eb04072a45c8ec081b3e57aacde86b8c5a5d77d9ed09f"),
            (181.5, 0.0, 0.0, 40.0, 9, 7, "6395c76698ca6c9ed09e5e90db0d3fe11345e6184aed1f51e214466c9ed070a2d476a8daa8689ae51749ec1e50f02254f7295bec1e507caea884b6b586b8bab3738beb1d4fed1f51f7295bf92b5ddc2759a8da0ca6d80ab0e214c28226d40638e01244de1042e91b4d892f61acde10b6e81ab9eb1dcb8c2fe21446e41648ef2153f1235593396bb9eb1dbdef21c49328d63d3aeb1d4ff22456f6285a942e604f4375c4ef28c7ac2bce3932b11345a6285af32e60a5326439386a1b4d7f"),
        ];
        for (heading, pitch, roll, hfov, w, h, hex) in cases {
            let focal = compute_camera_fovs(w as u32, h as u32, hfov, None).focal_px;
            let got = render_view(&pano, pw, ph, heading, pitch, roll, focal, w, h)
                .iter()
                .fold(String::new(), |mut acc, b| {
                    use std::fmt::Write;
                    let _ = write!(acc, "{:02x}", b);
                    acc
                });
            assert_eq!(got, hex, "heading {} pitch {} roll {} hfov {}", heading, pitch, roll, hfov);
        }
    }

    #[test]
    fn samples_bilinearly_wrapping_east_west_and_clamping_at_the_poles() {
        // 2x2: row 0 = [0, 100], row 1 = [200, 40] (grey).
        let buf = [0, 0, 0, 100, 100, 100, 200, 200, 200, 40, 40, 40];
        assert_eq!(sample_bilinear(&buf, 2, 2, 0.0, 0.0), [0, 0, 0]);
        assert_eq!(sample_bilinear(&buf, 2, 2, 0.5, 0.0), [50, 50, 50]);
        // Past the last column the sample blends back into column 0.
        assert_eq!(sample_bilinear(&buf, 2, 2, 1.25, 0.0), [75, 75, 75]);
        assert_eq!(sample_bilinear(&buf, 2, 2, -0.75, 0.0), [75, 75, 75]);
        // Below the last row clamps to h - 1.001, as the JS did.
        assert_eq!(sample_bilinear(&buf, 2, 2, 0.0, 5.0), [200, 200, 200]);
        assert_eq!(sample_bilinear(&buf, 2, 2, 0.5, 0.5), [85, 85, 85]);
    }

    #[test]
    fn output_names_follow_the_js_template() {
        assert_eq!(
            build_pinhole_output_name("output/panorama_30.266476_-97.73719.jpg", 270.0, -10.0, "fov90", 1920, 1080),
            "pinhole_panorama_30.266476_-97.73719_h270_p-10_fov90_1920x1080_W.jpg"
        );
        assert_eq!(
            build_pinhole_output_name("/abs/p.jpeg", 12.5, 2.5, "f800", 640, 480),
            "pinhole_p_h12.5_p2.5_f800_640x480_H12.5.jpg"
        );
        assert_eq!(
            build_pinhole_output_name(".hidden", 360.0, -0.0, "fov90", 1, 1),
            "pinhole_.hidden_h360_p0_fov90_1x1_H360.jpg"
        );
    }

    #[test]
    fn a_missing_input_is_an_error() {
        let ctx = test_context("pinhole_missing", &[]);
        let opts = parse_args(&args(&["--input", "nope.jpg"])).unwrap();
        assert!(execute(&opts, &ctx).unwrap_err().contains("nope.jpg"));
        assert_eq!(parse_args(&args(&[])).unwrap_err(), "Error: --input is required.");
    }
}
