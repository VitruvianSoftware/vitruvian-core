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

//! What the four Google imagery CLI tools (`pano_pinhole`, `sat_ortho`,
//! `streetview_headings`, `streetview_panorama`) share: HTTP through an
//! injectable [`Fetcher`] (curl in production, a mock in tests), image decode
//! and JPEG encode, JS-compatible number formatting for file names and URLs,
//! a dotenv reader that matches Node's `util.parseEnv`, and where the tools
//! read `.env` from and write `output/` to.

use std::collections::HashMap;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Mutex;

/// The Referer the JS tools sent with every Google request.
pub const REFERER: &str = "http://localhost:4173/";

#[derive(Debug, Clone, PartialEq)]
pub struct HttpRequest {
    pub method: String,
    pub url: String,
    pub headers: Vec<(String, String)>,
    pub body: Option<Vec<u8>>,
}

impl HttpRequest {
    pub fn get(url: impl Into<String>) -> Self {
        HttpRequest {
            method: "GET".into(),
            url: url.into(),
            headers: Vec::new(),
            body: None,
        }
    }

    pub fn post_json(url: impl Into<String>, body: &serde_json::Value) -> Self {
        HttpRequest {
            method: "POST".into(),
            url: url.into(),
            headers: vec![("Content-Type".into(), "application/json".into())],
            body: Some(body.to_string().into_bytes()),
        }
    }

    pub fn header(mut self, name: &str, value: &str) -> Self {
        self.headers.push((name.into(), value.into()));
        self
    }

    pub fn referer(self) -> Self {
        self.header("Referer", REFERER)
    }

    pub fn header_value(&self, name: &str) -> Option<&str> {
        self.headers
            .iter()
            .find(|(k, _)| k.eq_ignore_ascii_case(name))
            .map(|(_, v)| v.as_str())
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct HttpResponse {
    pub status: u16,
    pub body: Vec<u8>,
}

impl HttpResponse {
    pub fn ok(&self) -> bool {
        (200..300).contains(&self.status)
    }

    pub fn text(&self) -> String {
        String::from_utf8_lossy(&self.body).into_owned()
    }

    pub fn json(&self) -> Result<serde_json::Value, String> {
        serde_json::from_slice(&self.body).map_err(|e| format!("invalid JSON response: {}", e))
    }
}

/// One HTTP exchange. `Err` is a transport failure (no status), as a rejected
/// `fetch()` was in the JS tools; an HTTP error status is an `Ok` response.
pub trait Fetcher: Sync {
    fn fetch(&self, req: &HttpRequest) -> Result<HttpResponse, String>;
}

/// Production fetcher: runs `curl`, as `tle_mirror` does. The request goes to
/// curl as a config file on stdin (`-K -`), so the API key in the URL is never
/// on a command line where `ps` would show it.
pub struct CurlFetcher;

/// Quote a value for a curl config file.
fn curl_config_quote(value: &str) -> String {
    let mut out = String::with_capacity(value.len() + 2);
    out.push('"');
    for c in value.chars() {
        match c {
            '\\' => out.push_str("\\\\"),
            '"' => out.push_str("\\\""),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            _ => out.push(c),
        }
    }
    out.push('"');
    out
}

/// The curl config [`CurlFetcher`] sends for `req`. Public for its test.
pub fn curl_config(req: &HttpRequest) -> Result<String, String> {
    let mut cfg = String::new();
    cfg.push_str(&format!("url = {}\n", curl_config_quote(&req.url)));
    cfg.push_str(&format!("request = {}\n", curl_config_quote(&req.method)));
    for (k, v) in &req.headers {
        cfg.push_str(&format!("header = {}\n", curl_config_quote(&format!("{}: {}", k, v))));
    }
    if let Some(body) = &req.body {
        let text = std::str::from_utf8(body).map_err(|_| "request body is not UTF-8".to_string())?;
        cfg.push_str(&format!("data-binary = {}\n", curl_config_quote(text)));
    }
    Ok(cfg)
}

/// The arguments [`CurlFetcher`] runs curl with; the request itself goes in on
/// stdin as a config file (`-K -`), so the API key never reaches the process
/// list. `-q` has to be the first argument: it stops curl reading the user's
/// ~/.curlrc, where a `verbose` line would print the request, key included,
/// into the error we surface. `--proto`/`--proto-redir` keep every request and
/// redirect on HTTPS.
pub const CURL_ARGS: &[&str] = &[
    "-q",
    "--proto",
    "=https",
    "--proto-redir",
    "=https",
    "-sS",
    "-L",
    "--max-time",
    "120",
    "-o",
    "-",
    "-w",
    "\n%{http_code}",
    "-K",
    "-",
];

/// Split curl's `--write-out "\n%{http_code}"` trailer off a binary body.
pub fn split_curl_output(stdout: &[u8]) -> Result<HttpResponse, String> {
    let nl = stdout
        .iter()
        .rposition(|&b| b == b'\n')
        .ok_or_else(|| "fetch failed: no HTTP status from curl".to_string())?;
    let status = std::str::from_utf8(&stdout[nl + 1..])
        .ok()
        .and_then(|s| s.trim().parse::<u16>().ok())
        .ok_or_else(|| "fetch failed: no HTTP status from curl".to_string())?;
    if status == 0 {
        return Err("fetch failed".into());
    }
    Ok(HttpResponse {
        status,
        body: stdout[..nl].to_vec(),
    })
}

impl Fetcher for CurlFetcher {
    fn fetch(&self, req: &HttpRequest) -> Result<HttpResponse, String> {
        let cfg = curl_config(req)?;
        let mut child = Command::new("curl")
            .args(CURL_ARGS)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .map_err(|e| format!("fetch failed: could not run curl: {}", e))?;
        child
            .stdin
            .take()
            .ok_or_else(|| "fetch failed: curl stdin".to_string())?
            .write_all(cfg.as_bytes())
            .map_err(|e| format!("fetch failed: {}", e))?;
        let output = child
            .wait_with_output()
            .map_err(|e| format!("fetch failed: {}", e))?;
        if !output.status.success() {
            let err = String::from_utf8_lossy(&output.stderr);
            return Err(format!("fetch failed: {}", err.trim()));
        }
        split_curl_output(&output.stdout)
    }
}

/// Test fetcher: answers every request with `handler` and records it.
pub struct MockFetcher<F: Fn(&HttpRequest) -> Result<HttpResponse, String> + Sync> {
    pub handler: F,
    pub calls: Mutex<Vec<HttpRequest>>,
}

impl<F: Fn(&HttpRequest) -> Result<HttpResponse, String> + Sync> MockFetcher<F> {
    pub fn new(handler: F) -> Self {
        MockFetcher {
            handler,
            calls: Mutex::new(Vec::new()),
        }
    }

    pub fn calls(&self) -> Vec<HttpRequest> {
        self.calls.lock().unwrap().clone()
    }
}

impl<F: Fn(&HttpRequest) -> Result<HttpResponse, String> + Sync> Fetcher for MockFetcher<F> {
    fn fetch(&self, req: &HttpRequest) -> Result<HttpResponse, String> {
        self.calls.lock().unwrap().push(req.clone());
        (self.handler)(req)
    }
}

/// Run `f` over `items` on up to `concurrency` threads, as the JS tools' worker
/// pools did; results come back in `items` order.
pub fn parallel_map<T: Sync, R: Send>(
    items: &[T],
    concurrency: usize,
    f: impl Fn(&T) -> R + Sync,
) -> Vec<R> {
    let next = AtomicUsize::new(0);
    let results: Mutex<Vec<Option<R>>> = Mutex::new((0..items.len()).map(|_| None).collect());
    let workers = concurrency.max(1).min(items.len().max(1));
    std::thread::scope(|scope| {
        for _ in 0..workers {
            scope.spawn(|| loop {
                let i = next.fetch_add(1, Ordering::SeqCst);
                if i >= items.len() {
                    break;
                }
                let r = f(&items[i]);
                results.lock().unwrap()[i] = Some(r);
            });
        }
    });
    results
        .into_inner()
        .unwrap()
        .into_iter()
        .map(|r| r.expect("every item is processed"))
        .collect()
}

// ---------------------------------------------------------------------------
// Images
// ---------------------------------------------------------------------------

/// An 8-bit RGB raster, row-major, 3 bytes per pixel.
#[derive(Debug, Clone, PartialEq)]
pub struct RgbImage {
    pub width: usize,
    pub height: usize,
    pub data: Vec<u8>,
}

impl RgbImage {
    pub fn black(width: usize, height: usize) -> Self {
        RgbImage {
            width,
            height,
            data: vec![0u8; width * height * 3],
        }
    }

    pub fn pixel(&self, x: usize, y: usize) -> [u8; 3] {
        let i = (y * self.width + x) * 3;
        [self.data[i], self.data[i + 1], self.data[i + 2]]
    }

    /// Draw `src` with its top-left corner at (`left`, `top`), clipped to this
    /// canvas (sharp's `composite` with an opaque overlay).
    pub fn composite(&mut self, src: &RgbImage, left: usize, top: usize) {
        if left >= self.width || top >= self.height {
            return;
        }
        let w = src.width.min(self.width - left);
        let h = src.height.min(self.height - top);
        for row in 0..h {
            let s = row * src.width * 3;
            let d = ((top + row) * self.width + left) * 3;
            self.data[d..d + w * 3].copy_from_slice(&src.data[s..s + w * 3]);
        }
    }

    /// A `width` x `height` region at (`left`, `top`); errors when it does not
    /// fit, as sharp's `extract` does ("bad extract area").
    pub fn extract(&self, left: usize, top: usize, width: usize, height: usize) -> Result<RgbImage, String> {
        if left + width > self.width || top + height > self.height {
            return Err(format!(
                "extract_area: bad extract area ({}x{} at {},{} in {}x{})",
                width, height, left, top, self.width, self.height
            ));
        }
        let mut out = RgbImage::black(width, height);
        for row in 0..height {
            let s = ((top + row) * self.width + left) * 3;
            let d = row * width * 3;
            out.data[d..d + width * 3].copy_from_slice(&self.data[s..s + width * 3]);
        }
        Ok(out)
    }
}

/// Decode any JPEG or PNG to RGB, dropping alpha (sharp's `removeAlpha().raw()`).
pub fn decode_rgb(bytes: &[u8]) -> Result<RgbImage, String> {
    let img = image::load_from_memory(bytes).map_err(|e| format!("could not decode image: {}", e))?;
    let rgb = img.to_rgb8();
    Ok(RgbImage {
        width: rgb.width() as usize,
        height: rgb.height() as usize,
        data: rgb.into_raw(),
    })
}

pub fn read_rgb(path: &Path) -> Result<RgbImage, String> {
    let bytes = std::fs::read(path).map_err(|e| format!("Input file is missing: {} ({})", path.display(), e))?;
    decode_rgb(&bytes).map_err(|e| format!("{}: {}", path.display(), e))
}

/// JPEG-encode `img` at `quality` (the JS tools used sharp's `jpeg({ quality: 92 })`).
pub fn encode_jpeg(img: &RgbImage, quality: u8) -> Result<Vec<u8>, String> {
    let mut out = Vec::new();
    let mut enc = image::codecs::jpeg::JpegEncoder::new_with_quality(&mut out, quality);
    enc.encode(
        &img.data,
        img.width as u32,
        img.height as u32,
        image::ExtendedColorType::Rgb8,
    )
    .map_err(|e| format!("could not encode JPEG: {}", e))?;
    Ok(out)
}

pub const JPEG_QUALITY: u8 = 92;

// ---------------------------------------------------------------------------
// Numbers, as JavaScript prints them
// ---------------------------------------------------------------------------

/// `String(n)` in JavaScript, for finite `n`: shortest round-trip digits, no
/// exponent from 1e-6 up to 1e21, and `-0` prints as `0`. File names and URLs
/// the JS tools built with template strings use this.
pub fn js_num(n: f64) -> String {
    if n.is_nan() {
        return "NaN".into();
    }
    if n.is_infinite() {
        return if n > 0.0 { "Infinity".into() } else { "-Infinity".into() };
    }
    if n == 0.0 {
        return "0".into();
    }
    let abs = n.abs();
    if (1e-6..1e21).contains(&abs) {
        return format!("{}", n);
    }
    // Exponent form: Rust prints `1e-7` / `1.5e21`; JS prints `1e-7` / `1.5e+21`.
    let s = format!("{:e}", n);
    match s.split_once('e') {
        Some((mant, exp)) if !exp.starts_with('-') => format!("{}e+{}", mant, exp),
        _ => s,
    }
}

/// `n.toFixed(digits)` in JavaScript for the magnitudes these tools print.
pub fn to_fixed(n: f64, digits: usize) -> String {
    let s = format!("{:.*}", digits, n);
    // JS never prints "-0.0": toFixed of a value that rounds to zero keeps the
    // sign only when the number itself is negative and non-zero.
    if n == 0.0 && s.starts_with('-') {
        return s[1..].to_string();
    }
    s
}

// ---------------------------------------------------------------------------
// dotenv, as Node's util.parseEnv reads it
// ---------------------------------------------------------------------------

/// Parse dotenv text the way Node's `util.parseEnv` does: `export ` prefixes,
/// `'`, `"` and `` ` `` quoted values (double quotes expand `\n`, quoted values
/// may span lines), and unquoted values end at a `#`. Later keys win.
pub fn parse_env(content: &str) -> HashMap<String, String> {
    let mut out = HashMap::new();
    let text = content.replace("\r\n", "\n").replace('\r', "\n");
    let mut rest: &str = &text;
    while !rest.is_empty() {
        let (line, after) = match rest.find('\n') {
            Some(i) => (&rest[..i], &rest[i + 1..]),
            None => (rest, ""),
        };
        rest = after;
        let mut line = line.trim_start();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        if let Some(stripped) = line.strip_prefix("export ") {
            line = stripped.trim_start();
        }
        let eq = match line.find('=') {
            Some(i) => i,
            None => continue,
        };
        let key = line[..eq].trim().to_string();
        if key.is_empty() {
            continue;
        }
        let value_part = line[eq + 1..].trim_start();
        let first = value_part.chars().next();
        let value = match first {
            Some(q @ ('"' | '\'' | '`')) => {
                let body = &value_part[1..];
                if let Some(end) = body.find(q) {
                    body[..end].to_string()
                } else {
                    // A quoted value may continue on the following lines.
                    let mut joined = body.to_string();
                    let mut closed = None;
                    let mut cursor = rest;
                    while !cursor.is_empty() {
                        let (l, a) = match cursor.find('\n') {
                            Some(i) => (&cursor[..i], &cursor[i + 1..]),
                            None => (cursor, ""),
                        };
                        joined.push('\n');
                        if let Some(end) = l.find(q) {
                            joined.push_str(&l[..end]);
                            closed = Some(a);
                            break;
                        }
                        joined.push_str(l);
                        cursor = a;
                    }
                    match closed {
                        Some(a) => {
                            rest = a;
                            joined
                        }
                        // Unterminated: Node keeps the raw remainder of the line.
                        None => value_part.trim_end().to_string(),
                    }
                }
            }
            _ => match value_part.find('#') {
                Some(i) => value_part[..i].trim().to_string(),
                None => value_part.trim().to_string(),
            },
        };
        let value = if first == Some('"') {
            value.replace("\\n", "\n")
        } else {
            value
        };
        out.insert(key, value);
    }
    out
}

// ---------------------------------------------------------------------------
// Where the tools run
// ---------------------------------------------------------------------------

/// Where a tool reads `.env` and writes `--outdir` (`project_root`, the JS
/// tools' `projectRoot()`), and what a relative `--input` is relative to (`cwd`).
#[derive(Debug, Clone, PartialEq)]
pub struct ToolContext {
    pub project_root: PathBuf,
    pub cwd: PathBuf,
    pub env: HashMap<String, String>,
}

impl ToolContext {
    /// `GEV_PROJECT_ROOT`, else the app folder: under `bazel run` that is
    /// `$BUILD_WORKSPACE_DIRECTORY/apps/web/gods-eye-view`, since the binary
    /// itself sits in bazel-out. Relative paths resolve against the directory
    /// `bazel run` was started from (`BUILD_WORKING_DIRECTORY`).
    pub fn from_process() -> Self {
        let env: HashMap<String, String> = std::env::vars().collect();
        let non_empty = |k: &str| env.get(k).filter(|v| !v.is_empty()).map(PathBuf::from);
        let cwd = non_empty("BUILD_WORKING_DIRECTORY")
            .unwrap_or_else(|| std::env::current_dir().unwrap_or_default());
        let (_, project_root) = crate::dev_helpers::roots_from(
            non_empty("BUILD_WORKSPACE_DIRECTORY"),
            std::env::current_exe().ok(),
            cwd.clone(),
            non_empty("GEV_PROJECT_ROOT"),
        );
        ToolContext {
            project_root,
            cwd,
            env,
        }
    }

    pub fn env_var(&self, name: &str) -> Option<&str> {
        self.env.get(name).map(|s| s.as_str())
    }

    pub fn dotenv_path(&self) -> PathBuf {
        self.project_root.join(".env")
    }

    /// `--outdir`, resolved against the project root (`resolve(PROJECT_ROOT, outdir)`).
    pub fn outdir(&self, outdir: &str) -> PathBuf {
        self.project_root.join(outdir)
    }

    pub fn input_path(&self, input: &str) -> PathBuf {
        self.cwd.join(input)
    }
}

/// The `.env` of the project, or `None` when there is none or it is unreadable
/// (the JS `sat-ortho`/`streetview-panorama` key loaders ignored read errors).
pub fn read_dotenv_lenient(ctx: &ToolContext) -> Option<String> {
    std::fs::read_to_string(ctx.dotenv_path()).ok()
}

/// What a bin does with a tool's result: print it, exit 1 on error.
pub fn exit_with(result: Result<Option<String>, String>) -> ! {
    match result {
        Ok(Some(text)) => {
            println!("{}", text);
            std::process::exit(0)
        }
        Ok(None) => std::process::exit(0),
        Err(e) => {
            if e.starts_with("Error:") {
                eprintln!("{}", e);
            } else {
                eprintln!("\nError: {}", e);
            }
            std::process::exit(1)
        }
    }
}

/// A fresh directory under the test temp dir.
#[cfg(test)]
pub fn test_dir(name: &str) -> PathBuf {
    let base = std::env::var_os("TEST_TMPDIR")
        .map(PathBuf::from)
        .unwrap_or_else(std::env::temp_dir);
    let dir = base.join(format!("gev_{}_{}", name, std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

/// PNG-encode `img` (lossless, so tests can feed exact pixels to a tool).
#[cfg(test)]
pub fn png_bytes(img: &RgbImage) -> Vec<u8> {
    use image::ImageEncoder;
    let mut out = Vec::new();
    image::codecs::png::PngEncoder::new(&mut out)
        .write_image(
            &img.data,
            img.width as u32,
            img.height as u32,
            image::ExtendedColorType::Rgb8,
        )
        .unwrap();
    out
}

#[cfg(test)]
pub fn solid(width: usize, height: usize, rgb: [u8; 3]) -> RgbImage {
    RgbImage {
        width,
        height,
        data: rgb.iter().copied().cycle().take(width * height * 3).collect(),
    }
}

/// Every channel of `got` is within `tol` of `want`.
#[cfg(test)]
pub fn close(got: [u8; 3], want: [u8; 3], tol: u8) -> bool {
    got.iter().zip(want.iter()).all(|(g, w)| g.abs_diff(*w) <= tol)
}

#[cfg(test)]
pub fn ok_response(body: impl Into<Vec<u8>>) -> Result<HttpResponse, String> {
    Ok(HttpResponse {
        status: 200,
        body: body.into(),
    })
}

#[cfg(test)]
pub fn status_response(status: u16, body: &str) -> Result<HttpResponse, String> {
    Ok(HttpResponse {
        status,
        body: body.as_bytes().to_vec(),
    })
}

/// A context rooted in a fresh temp dir with only `env` set.
#[cfg(test)]
pub fn test_context(name: &str, env: &[(&str, &str)]) -> ToolContext {
    let dir = test_dir(name);
    let project_root = dir.join("project");
    std::fs::create_dir_all(&project_root).unwrap();
    ToolContext {
        project_root,
        cwd: dir,
        env: env.iter().map(|(k, v)| (k.to_string(), v.to_string())).collect(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn js_num_matches_javascript_string_conversion() {
        assert_eq!(js_num(30.266476), "30.266476");
        assert_eq!(js_num(-97.73719), "-97.73719");
        assert_eq!(js_num(30.0), "30");
        assert_eq!(js_num(-0.0), "0");
        assert_eq!(js_num(0.1 + 0.2), "0.30000000000000004");
        assert_eq!(js_num(1e-7), "1e-7");
        assert_eq!(js_num(1.5e-7), "1.5e-7");
        assert_eq!(js_num(0.0000015), "0.0000015");
        assert_eq!(js_num(123456789012345680000.0), "123456789012345680000");
        assert_eq!(js_num(1.5e21), "1.5e+21");
        assert_eq!(js_num(0.000001), "0.000001");
        assert_eq!(to_fixed(-0.0000001, 1), "-0.0");
        assert_eq!(to_fixed(30.2664764, 6), "30.266476");
    }

    #[test]
    fn parse_env_matches_node_parse_env() {
        let env = parse_env(
            "# comment\nGOOGLE_MAPS_API_KEY=file-browser\nGOOGLE_MAPS_SERVER_API_KEY=\"file-server\" # separate key\nexport A='single # kept'\nB=plain value # comment\nC=\"multi\nline\"\nD=\"esc\\nnl\"\nE=\nF=abc#def\nG = spaced \nH=\"unterminated\nI=after\n",
        );
        // Expected values are what `node -e 'util.parseEnv(...)'` returns.
        assert_eq!(env["F"], "abc");
        assert_eq!(env["G"], "spaced");
        assert_eq!(env["H"], "\"unterminated");
        assert_eq!(env["I"], "after");
        assert_eq!(env["GOOGLE_MAPS_API_KEY"], "file-browser");
        assert_eq!(env["GOOGLE_MAPS_SERVER_API_KEY"], "file-server");
        assert_eq!(env["A"], "single # kept");
        assert_eq!(env["B"], "plain value");
        assert_eq!(env["C"], "multi\nline");
        assert_eq!(env["D"], "esc\nnl");
        assert_eq!(env["E"], "");
    }

    #[test]
    fn curl_config_quotes_and_status_split() {
        let req = HttpRequest::post_json("https://x.test/a?key=k\"1", &serde_json::json!({"a": "b"})).referer();
        let cfg = curl_config(&req).unwrap();
        assert!(cfg.contains("url = \"https://x.test/a?key=k\\\"1\"\n"));
        assert!(cfg.contains("request = \"POST\"\n"));
        assert!(cfg.contains("header = \"Content-Type: application/json\"\n"));
        assert!(cfg.contains("header = \"Referer: http://localhost:4173/\"\n"));
        assert!(cfg.contains("data-binary = \"{\\\"a\\\":\\\"b\\\"}\"\n"));

        let mut out = vec![0xFFu8, b'\n', 0x00, 0x10];
        out.extend_from_slice(b"\n404");
        let res = split_curl_output(&out).unwrap();
        assert_eq!(res.status, 404);
        assert_eq!(res.body, vec![0xFF, b'\n', 0x00, 0x10]);
        assert!(split_curl_output(b"\n000").is_err());
    }

    /// `-q` must come first or curl reads the user's ~/.curlrc, where a
    /// `verbose` line would print the request, API key included, into the
    /// error we surface. Every fetch is HTTPS, redirects included.
    #[test]
    fn curl_ignores_curlrc_and_stays_on_https() {
        assert_eq!(CURL_ARGS[0], "-q");
        assert_eq!(CURL_ARGS.iter().filter(|a| **a == "-q").count(), 1);
        let pair = |flag: &str| CURL_ARGS.windows(2).any(|w| w[0] == flag && w[1] == "=https");
        assert!(pair("--proto"), "{:?}", CURL_ARGS);
        assert!(pair("--proto-redir"), "{:?}", CURL_ARGS);
        assert!(CURL_ARGS.ends_with(&["-K", "-"]));
    }

    #[test]
    fn composite_clips_and_extract_checks_bounds() {
        let mut canvas = RgbImage::black(4, 4);
        let tile = RgbImage {
            width: 3,
            height: 3,
            data: vec![9u8; 27],
        };
        canvas.composite(&tile, 2, 2);
        assert_eq!(canvas.pixel(3, 3), [9, 9, 9]);
        assert_eq!(canvas.pixel(1, 1), [0, 0, 0]);
        assert!(canvas.extract(1, 1, 4, 1).is_err());
        assert_eq!(canvas.extract(2, 2, 2, 2).unwrap().data, vec![9u8; 12]);
    }

    #[test]
    fn parallel_map_keeps_order() {
        let items: Vec<u32> = (0..50).collect();
        let out = parallel_map(&items, 8, |i| i * 2);
        assert_eq!(out, (0..50).map(|i| i * 2).collect::<Vec<_>>());
    }
}
