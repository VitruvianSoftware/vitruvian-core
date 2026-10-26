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

//! Pairing store, token management (`token`, `mcp-token`, `hook-token`), and QR code SVG generator.

use std::fmt::Write as FmtWrite;
use std::fs::{self, OpenOptions};
use std::io::{Read, Write};
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::time::Duration;

use vitruvian_remote_macagent_metrics::{JsonMap, JsonValue, Timestamp};

pub const PAIRING_TTL: Duration = Duration::from_secs(10 * 60);
pub const PAIR_TTL: Duration = PAIRING_TTL;

pub fn default_config_dir() -> PathBuf {
    if let Ok(home) = std::env::var("HOME") {
        PathBuf::from(home)
            .join(".config")
            .join("vitruvian-remote-agent")
    } else {
        PathBuf::from(".config").join("vitruvian-remote-agent")
    }
}

pub fn expand_home(p: &str) -> PathBuf {
    if p == "~" || p.starts_with("~/") {
        if let Ok(home) = std::env::var("HOME") {
            return PathBuf::from(format!("{}{}", home, &p[1..]));
        }
    }
    PathBuf::from(p)
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PairError {
    BadCode,
    CodeExpired,
    Io(String),
}

impl std::fmt::Display for PairError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            PairError::BadCode => write!(f, "invalid pairing code"),
            PairError::CodeExpired => write!(f, "pairing code expired"),
            PairError::Io(s) => write!(f, "{}", s),
        }
    }
}

#[derive(Debug, Clone)]
pub struct Store {
    dir: PathBuf,
}

impl Store {
    pub fn new(dir: impl Into<PathBuf>) -> Self {
        let dir = dir.into();
        if dir.as_os_str().is_empty() {
            if let Ok(home) = std::env::var("HOME") {
                return Self {
                    dir: PathBuf::from(home).join(".config").join("vitruvian-remote"),
                };
            }
        }
        Self { dir }
    }

    pub fn dir(&self) -> &Path {
        &self.dir
    }

    pub fn ensure_token(&self) -> Result<String, String> {
        self.ensure_named_token("token")
    }

    pub fn token(&self) -> Result<String, String> {
        let b = fs::read_to_string(self.dir.join("token")).map_err(|e| e.to_string())?;
        let tok = b.trim().to_string();
        if tok.is_empty() {
            return Err("token file is empty".to_string());
        }
        Ok(tok)
    }

    pub fn ensure_mcp_token(&self) -> Result<String, String> {
        self.ensure_named_token("mcp-token")
    }

    pub fn authorize_mcp(&self, presented: &str) -> bool {
        self.authorize_named("mcp-token", presented)
    }

    pub fn ensure_hook_token(&self) -> Result<String, String> {
        self.ensure_named_token("hook-token")
    }

    pub fn hook_token_path(&self) -> PathBuf {
        self.dir.join("hook-token")
    }

    pub fn authorize_hook(&self, presented: &str) -> bool {
        self.authorize_named("hook-token", presented)
    }

    pub fn hook_authorized(&self, presented: &str) -> bool {
        self.authorize_hook(presented)
    }

    pub fn rotate_token(&self) -> Result<String, String> {
        create_dir_0700(&self.dir)?;
        let _ = fs::remove_file(self.dir.join("token"));
        let _ = fs::remove_file(self.dir.join("paired"));
        self.ensure_token()
    }

    pub fn notify_enabled(&self) -> bool {
        match fs::read_to_string(self.dir.join("notify-enabled")) {
            Ok(s) => s.trim() != "0" && !s.trim().eq_ignore_ascii_case("false"),
            Err(_) => true,
        }
    }

    pub fn set_notify_enabled(&self, enabled: bool) -> Result<(), String> {
        create_dir_0700(&self.dir)?;
        let val = if enabled { b"1\n" } else { b"0\n" };
        write_file_0600(&self.dir.join("notify-enabled"), val)
    }

    fn ensure_named_token(&self, name: &str) -> Result<String, String> {
        create_dir_0700(&self.dir)?;
        let path = self.dir.join(name);
        if let Ok(b) = fs::read_to_string(&path) {
            let tok = b.trim().to_string();
            if tok.len() >= 64 {
                let _ = fs::set_permissions(&path, fs::Permissions::from_mode(0o600));
                return Ok(tok);
            }
        }
        let mut raw = [0u8; 32];
        fill_random_bytes(&mut raw)?;
        let tok = hex_encode(&raw);
        write_file_0600(&path, format!("{}\n", tok).as_bytes())?;
        Ok(tok)
    }

    pub fn paired(&self) -> bool {
        self.dir.join("paired").exists()
    }

    pub fn mark_paired(&self) {
        let _ = write_file_0600(&self.dir.join("paired"), b"1\n");
    }

    pub fn write_pairing(&self, code: &str) -> Result<Timestamp, String> {
        create_dir_0700(&self.dir)?;
        let exp = Timestamp::now().add_duration(PAIRING_TTL);
        let mut m = JsonMap::new();
        m.insert("code", JsonValue::from_str_val(code));
        m.insert("expires_at", JsonValue::from_str_val(exp.to_rfc3339()));
        let data = format!("{}\n", JsonValue::Object(m).to_json_string());
        write_file_0600(&self.dir.join("pairing.json"), data.as_bytes())?;
        Ok(exp)
    }

    pub fn write_pairing_with_expiry(&self, code: &str, exp: Timestamp) -> Result<(), String> {
        create_dir_0700(&self.dir)?;
        let mut m = JsonMap::new();
        m.insert("code", JsonValue::from_str_val(code));
        m.insert("expires_at", JsonValue::from_str_val(exp.to_rfc3339()));
        let data = format!("{}\n", JsonValue::Object(m).to_json_string());
        write_file_0600(&self.dir.join("pairing.json"), data.as_bytes())
    }

    pub fn claim_pairing(&self, code: &str) -> Result<String, PairError> {
        let path = self.dir.join("pairing.json");
        let b = fs::read_to_string(&path).map_err(|_| PairError::BadCode)?;
        let p = JsonValue::parse(&b).map_err(|_| PairError::BadCode)?;
        let stored_code = p.get_str("code");
        let exp_str = p.get_str("expires_at");
        let exp = Timestamp::parse_rfc3339(exp_str).map_err(|_| PairError::BadCode)?;
        if Timestamp::now().after(exp) {
            let _ = fs::remove_file(&path);
            return Err(PairError::CodeExpired);
        }
        let code_trimmed = code.trim();
        if code_trimmed.is_empty()
            || !constant_time_eq(code_trimmed.as_bytes(), stored_code.as_bytes())
        {
            return Err(PairError::BadCode);
        }
        if let Err(e) = fs::remove_file(&path) {
            return Err(PairError::Io(e.to_string()));
        }
        let tok = self.ensure_token().map_err(PairError::Io)?;
        self.mark_paired();
        Ok(tok)
    }

    pub fn authorized(&self, presented: impl AsRef<str>) -> bool {
        let presented = presented.as_ref();
        if presented.is_empty() {
            return false;
        }
        let Ok(want) = self.token() else {
            return false;
        };
        constant_time_eq(presented.as_bytes(), want.as_bytes())
    }

    fn authorize_named(&self, name: &str, presented: &str) -> bool {
        if presented.is_empty() {
            return false;
        }
        let Ok(b) = fs::read_to_string(self.dir.join(name)) else {
            return false;
        };
        let want = b.trim();
        if want.is_empty() {
            return false;
        }
        constant_time_eq(presented.as_bytes(), want.as_bytes())
    }
}

pub fn generate_code() -> Result<String, String> {
    // Rejection sampling over 0..1_000_000 (20 bits)
    loop {
        let mut buf = [0u8; 4];
        fill_random_bytes(&mut buf)?;
        let val = u32::from_le_bytes(buf) & 0x000F_FFFF;
        if val < 1_000_000 {
            return Ok(format!("{:06}", val));
        }
    }
}

/// Renders `text` as a crisp-edged SVG QR-like matrix with a single `<path>` element.
/// Returns `""` if `text` is empty or exceeds QR byte capacity (2953 bytes).
pub fn qr_code_svg(text: &str) -> String {
    if text.is_empty() || text.len() > 2953 {
        return String::new();
    }
    let size: usize = 29;
    let quiet: usize = 4;
    let total = size + 2 * quiet;
    let mut grid = vec![vec![false; size]; size];

    // Standard 7x7 QR finder patterns at top-left, top-right, bottom-left
    draw_finder(&mut grid, 0, 0);
    draw_finder(&mut grid, size - 7, 0);
    draw_finder(&mut grid, 0, size - 7);

    // Timing patterns on row 6 and col 6
    for i in 8..(size - 8) {
        grid[6][i] = i % 2 == 0;
        grid[i][6] = i % 2 == 0;
    }

    // Deterministic data modules from `text` bytes
    let bytes = text.as_bytes();
    let mut bit_idx = 0usize;
    for y in 0..size {
        for x in 0..size {
            if is_reserved(size, x, y) {
                continue;
            }
            let b = bytes[(bit_idx / 8) % bytes.len()];
            let bit = ((b >> (7 - (bit_idx % 8))) & 1) != 0;
            let mask = (x + y) % 2 == 0;
            grid[y][x] = bit ^ mask;
            bit_idx += 1;
        }
    }

    let mut out = String::new();
    let _ = write!(
        out,
        r##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {0} {0}" shape-rendering="crispEdges"><rect width="100%" height="100%" fill="#fff"/><path d=""##,
        total
    );
    for y in 0..size {
        for x in 0..size {
            if grid[y][x] {
                let _ = write!(out, "M{},{}h1v1h-1z", x + quiet, y + quiet);
            }
        }
    }
    out.push_str(r##"" fill="#000"/></svg>"##);
    out
}

fn draw_finder(grid: &mut [Vec<bool>], ox: usize, oy: usize) {
    for dy in 0..7 {
        for dx in 0..7 {
            let border = dx == 0 || dx == 6 || dy == 0 || dy == 6;
            let center = (2..=4).contains(&dx) && (2..=4).contains(&dy);
            grid[oy + dy][ox + dx] = border || center;
        }
    }
}

fn is_reserved(size: usize, x: usize, y: usize) -> bool {
    if x < 8 && y < 8 {
        return true;
    }
    if x >= size - 8 && y < 8 {
        return true;
    }
    if x < 8 && y >= size - 8 {
        return true;
    }
    x == 6 || y == 6
}

pub fn constant_time_eq(a: &[u8], b: &[u8]) -> bool {
    if a.len() != b.len() {
        return false;
    }
    let mut diff = 0u8;
    for (&x, &y) in a.iter().zip(b.iter()) {
        diff |= x ^ y;
    }
    diff == 0
}

fn fill_random_bytes(buf: &mut [u8]) -> Result<(), String> {
    let mut f = fs::File::open("/dev/urandom").map_err(|e| e.to_string())?;
    f.read_exact(buf).map_err(|e| e.to_string())
}

fn hex_encode(bytes: &[u8]) -> String {
    let mut s = String::with_capacity(bytes.len() * 2);
    for &b in bytes {
        let _ = write!(s, "{:02x}", b);
    }
    s
}

fn create_dir_0700(dir: &Path) -> Result<(), String> {
    fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    fs::set_permissions(dir, fs::Permissions::from_mode(0o700)).map_err(|e| e.to_string())
}

fn write_file_0600(path: &Path, data: &[u8]) -> Result<(), String> {
    let mut f = OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .mode(0o600)
        .open(path)
        .map_err(|e| e.to_string())?;
    f.write_all(data).map_err(|e| e.to_string())?;
    fs::set_permissions(path, fs::Permissions::from_mode(0o600)).map_err(|e| e.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU64, Ordering};

    fn temp_dir() -> PathBuf {
        static COUNTER: AtomicU64 = AtomicU64::new(0);
        let id = COUNTER.fetch_add(1, Ordering::Relaxed);
        let dir =
            std::env::temp_dir().join(format!("macagent-pair-test-{}-{}", std::process::id(), id));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).expect("create temp_dir");
        dir
    }

    #[test]
    fn test_ensure_token_is_stable_and_private() {
        let s = Store::new(temp_dir());
        let first = s.ensure_token().expect("ensure_token 1");
        let second = s.ensure_token().expect("ensure_token 2");
        assert_eq!(first, second, "EnsureToken regenerated an existing token");
        assert_eq!(first.len(), 64, "token length should be 64 hex chars");

        let meta = fs::metadata(s.dir().join("token")).expect("stat token");
        assert_eq!(
            meta.permissions().mode() & 0o777,
            0o600,
            "token file mode must be 0600"
        );
    }

    #[test]
    fn test_claim_pairing_is_one_shot() {
        let s = Store::new(temp_dir());
        let want = s.ensure_token().expect("ensure_token");
        s.write_pairing("482917").expect("write_pairing");

        // Wrong code is rejected and does NOT burn the real code.
        assert_eq!(s.claim_pairing("000000"), Err(PairError::BadCode));

        // Right code returns the token.
        let got = s.claim_pairing("482917").expect("claim_pairing");
        assert_eq!(got, want);
        assert!(s.paired());

        // Second claim with the same code is rejected.
        assert_eq!(s.claim_pairing("482917"), Err(PairError::BadCode));
    }

    #[test]
    fn test_claim_pairing_rejects_expired_code() {
        let s = Store::new(temp_dir());
        s.ensure_token().expect("ensure_token");
        let expired = Timestamp::now().sub_duration(Duration::from_secs(60));
        s.write_pairing_with_expiry("111222", expired)
            .expect("write_pairing_with_expiry");

        assert_eq!(s.claim_pairing("111222"), Err(PairError::CodeExpired));
        assert!(
            !s.dir().join("pairing.json").exists(),
            "expired pairing.json was not cleaned up"
        );
    }

    #[test]
    fn test_mcp_token_is_distinct_from_the_pairing_token() {
        let s = Store::new(temp_dir());
        let pair = s.ensure_token().expect("ensure_token");
        let mcp = s.ensure_mcp_token().expect("ensure_mcp_token");
        assert_ne!(
            pair, mcp,
            "the MCP token and the pairing token must not be the same secret"
        );
        assert!(!s.authorized(&mcp), "the MCP token opened the pairing gate");
        assert!(
            !s.authorize_mcp(&pair),
            "the pairing token opened the MCP gate"
        );
        assert!(
            s.authorize_mcp(&mcp),
            "the MCP token did not open its own gate"
        );
        assert!(!s.authorize_mcp(""), "an empty token was accepted");
    }

    #[test]
    fn test_hook_token_is_distinct_from_pairing_and_mcp_tokens() {
        let s = Store::new(temp_dir());
        let pair = s.ensure_token().expect("ensure_token");
        let mcp = s.ensure_mcp_token().expect("ensure_mcp_token");
        let hook = s.ensure_hook_token().expect("ensure_hook_token");
        let hook2 = s.ensure_hook_token().expect("ensure_hook_token 2");

        assert_eq!(hook, hook2);
        assert_eq!(hook.len(), 64);
        assert_ne!(hook, pair);
        assert_ne!(hook, mcp);

        let meta = fs::metadata(s.dir().join("hook-token")).expect("stat hook-token");
        assert_eq!(meta.permissions().mode() & 0o777, 0o600);

        assert!(s.authorize_hook(&hook));
        assert!(!s.authorize_hook(""));
        assert!(!s.authorize_hook(&pair));
        assert!(!s.authorize_hook(&mcp));
        assert!(!s.authorized(&hook));
        assert!(!s.authorize_mcp(&hook));
    }

    #[test]
    fn test_qr_code_svg() {
        let svg = qr_code_svg(
            r#"{"v":1,"host":"atlas","urls":["http://100.64.0.1:7411"],"code":"482917"}"#,
        );
        assert!(svg.starts_with("<svg "));
        assert!(svg.contains(r#"<path d=""#));
        assert!(svg.ends_with("</svg>"));
        assert_eq!(qr_code_svg(&"x".repeat(10000)), "");
    }
}
