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
// SPDX-License-Identifier: MIT

//! Paths, credential storage, and legacy migration.

use serde_json::{Map, Value};
use std::env;
use std::fmt;
use std::fs::{self, OpenOptions, Permissions};
use std::io::{Read, Write};
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

pub const DAEMON_HOST: &str = "127.0.0.1";
pub const DEFAULT_DAEMON_PORT: u16 = 8765;

pub const HOME_ENV: &str = "VITRUVIAN_ROBOROCK_HOME";
pub const PORT_ENV: &str = "VITRUVIAN_ROBOROCK_PORT";
pub const DEVICE_ENV: &str = "VITRUVIAN_ROBOROCK_DEVICE";

pub const CREDENTIALS_VERSION: u32 = 1;
const PRIVATE_FILE: u32 = 0o600;
const PRIVATE_DIR: u32 = 0o700;

static TEMP_COUNTER: AtomicU64 = AtomicU64::new(1);

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ConfigError(pub String);

impl ConfigError {
    pub fn new(msg: impl Into<String>) -> Self {
        Self(msg.into())
    }
}

impl fmt::Display for ConfigError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

impl std::error::Error for ConfigError {}

pub fn expand_tilde(raw: &str) -> PathBuf {
    if raw == "~" {
        if let Ok(home) = env::var("HOME") {
            return PathBuf::from(home);
        }
    } else if let Some(rest) = raw.strip_prefix("~/") {
        if let Ok(home) = env::var("HOME") {
            return PathBuf::from(home).join(rest);
        }
    }
    PathBuf::from(raw)
}

pub fn config_dir() -> PathBuf {
    if let Ok(override_dir) = env::var(HOME_ENV) {
        if !override_dir.is_empty() {
            return expand_tilde(&override_dir);
        }
    }
    let base = env::var("XDG_CONFIG_HOME")
        .ok()
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "~/.config".to_string());
    expand_tilde(&base).join("vitruvian").join("roborock")
}

pub fn credentials_path() -> PathBuf {
    config_dir().join("credentials.json")
}

pub fn token_path() -> PathBuf {
    config_dir().join("daemon-token")
}

pub fn cache_path() -> PathBuf {
    config_dir().join("cache").join("home.json")
}

pub fn log_path() -> PathBuf {
    config_dir().join("daemon.log")
}

pub fn legacy_credentials_path() -> PathBuf {
    expand_tilde("~/.roborock")
}

pub fn daemon_port() -> Result<u16, ConfigError> {
    let raw = match env::var(PORT_ENV) {
        Ok(val) if !val.is_empty() => val,
        _ => return Ok(DEFAULT_DAEMON_PORT),
    };
    let port: i64 = raw
        .parse()
        .map_err(|_| ConfigError::new(format!("{PORT_ENV} must be a port number, got {raw:?}")))?;
    if !(1..=65535).contains(&port) {
        return Err(ConfigError::new(format!(
            "{PORT_ENV} must be between 1 and 65535, got {port}"
        )));
    }
    Ok(port as u16)
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Credentials {
    pub email: String,
    pub user_data: Map<String, Value>,
    pub base_url: Option<String>,
    pub migrated_from: Option<String>,
    pub extra: Map<String, Value>,
}

impl Credentials {
    pub fn new(email: impl Into<String>, user_data: Map<String, Value>) -> Self {
        Self {
            email: email.into(),
            user_data,
            base_url: None,
            migrated_from: None,
            extra: Map::new(),
        }
    }

    pub fn with_base_url(mut self, base_url: impl Into<String>) -> Self {
        let s = base_url.into();
        self.base_url = if s.is_empty() { None } else { Some(s) };
        self
    }

    pub fn with_migrated_from(mut self, migrated_from: impl Into<String>) -> Self {
        let s = migrated_from.into();
        self.migrated_from = if s.is_empty() { None } else { Some(s) };
        self
    }

    pub fn to_json(&self) -> Value {
        let mut doc = self.extra.clone();
        doc.insert("version".to_string(), Value::from(CREDENTIALS_VERSION));
        doc.insert("email".to_string(), Value::from(self.email.clone()));
        doc.insert(
            "user_data".to_string(),
            Value::Object(self.user_data.clone()),
        );
        if let Some(ref base_url) = self.base_url {
            if !base_url.is_empty() {
                doc.insert("base_url".to_string(), Value::from(base_url.clone()));
            }
        }
        if let Some(ref migrated_from) = self.migrated_from {
            if !migrated_from.is_empty() {
                doc.insert(
                    "migrated_from".to_string(),
                    Value::from(migrated_from.clone()),
                );
            }
        }
        Value::Object(doc)
    }

    pub fn from_json(doc: &Value) -> Result<Self, ConfigError> {
        let obj = doc
            .as_object()
            .ok_or_else(|| ConfigError::new("credentials file is not a JSON object"))?;
        let email = obj
            .get("email")
            .and_then(|v| v.as_str())
            .filter(|s| !s.is_empty())
            .ok_or_else(|| ConfigError::new("credentials file is missing 'email' or 'user_data'"))?
            .to_string();
        let user_data = obj
            .get("user_data")
            .and_then(|v| v.as_object())
            .filter(|m| !m.is_empty())
            .ok_or_else(|| ConfigError::new("credentials file is missing 'email' or 'user_data'"))?
            .clone();
        let base_url = obj
            .get("base_url")
            .and_then(|v| v.as_str())
            .filter(|s| !s.is_empty())
            .map(ToString::to_string);
        let migrated_from = obj
            .get("migrated_from")
            .and_then(|v| v.as_str())
            .filter(|s| !s.is_empty())
            .map(ToString::to_string);

        let mut extra = Map::new();
        for (k, v) in obj {
            if !matches!(
                k.as_str(),
                "version" | "email" | "user_data" | "base_url" | "migrated_from"
            ) {
                extra.insert(k.clone(), v.clone());
            }
        }

        Ok(Self {
            email,
            user_data,
            base_url,
            migrated_from,
            extra,
        })
    }
}

pub fn ensure_private_dir(path: &Path) -> Result<PathBuf, ConfigError> {
    fs::create_dir_all(path)
        .map_err(|e| ConfigError::new(format!("cannot create {}: {e}", path.display())))?;
    let meta = fs::metadata(path)
        .map_err(|e| ConfigError::new(format!("cannot stat {}: {e}", path.display())))?;
    if (meta.permissions().mode() & 0o777) != PRIVATE_DIR {
        fs::set_permissions(path, Permissions::from_mode(PRIVATE_DIR))
            .map_err(|e| ConfigError::new(format!("cannot chmod {}: {e}", path.display())))?;
    }
    Ok(path.to_path_buf())
}

pub fn write_private(path: &Path, data: &[u8]) -> Result<(), ConfigError> {
    let parent = path
        .parent()
        .ok_or_else(|| ConfigError::new(format!("no parent directory for {}", path.display())))?;
    ensure_private_dir(parent)?;
    let file_name = path
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("roborock");
    let pid = std::process::id();
    let seq = TEMP_COUNTER.fetch_add(1, Ordering::Relaxed);
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    let tmp = parent.join(format!(".{file_name}.{pid}.{seq}.{nanos}"));

    let write_res = (|| -> Result<(), std::io::Error> {
        let mut file = OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(PRIVATE_FILE)
            .open(&tmp)?;
        file.set_permissions(Permissions::from_mode(PRIVATE_FILE))?;
        file.write_all(data)?;
        file.flush()?;
        file.sync_all()?;
        drop(file);
        fs::rename(&tmp, path)?;
        Ok(())
    })();

    if let Err(err) = write_res {
        let _ = fs::remove_file(&tmp);
        return Err(ConfigError::new(format!(
            "cannot write {}: {err}",
            path.display()
        )));
    }
    Ok(())
}

fn tighten(path: &Path) {
    if let Ok(meta) = fs::metadata(path) {
        if (meta.permissions().mode() & 0o777) != PRIVATE_FILE {
            let _ = fs::set_permissions(path, Permissions::from_mode(PRIVATE_FILE));
        }
    }
}

pub fn save_credentials(credentials: &Credentials) -> Result<PathBuf, ConfigError> {
    let path = credentials_path();
    let mut rendered = serde_json::to_string_pretty(&credentials.to_json())
        .map_err(|e| ConfigError::new(format!("cannot serialize credentials: {e}")))?;
    rendered.push('\n');
    write_private(&path, rendered.as_bytes())?;
    Ok(path)
}

pub fn load_credentials() -> Result<Option<Credentials>, ConfigError> {
    load_credentials_with_options(true)
}

pub fn load_credentials_with_options(migrate: bool) -> Result<Option<Credentials>, ConfigError> {
    let path = credentials_path();
    if path.is_file() {
        tighten(&path);
        let text = fs::read_to_string(&path)
            .map_err(|e| ConfigError::new(format!("cannot read {}: {e}", path.display())))?;
        let doc: Value = serde_json::from_str(&text)
            .map_err(|e| ConfigError::new(format!("cannot read {}: {e}", path.display())))?;
        return Credentials::from_json(&doc).map(Some);
    }
    if migrate {
        return migrate_legacy_credentials();
    }
    Ok(None)
}

pub fn migrate_legacy_credentials() -> Result<Option<Credentials>, ConfigError> {
    let legacy = legacy_credentials_path();
    if !legacy.is_file() {
        return Ok(None);
    }
    let text = match fs::read_to_string(&legacy) {
        Ok(t) => t,
        Err(_) => return Ok(None),
    };
    let doc: Value = match serde_json::from_str(&text) {
        Ok(v) => v,
        Err(_) => return Ok(None),
    };
    let obj = match doc.as_object() {
        Some(o) => o,
        None => return Ok(None),
    };
    let user_data = obj
        .get("userData")
        .or_else(|| obj.get("user_data"))
        .and_then(|v| v.as_object());
    let email = obj.get("email").and_then(|v| v.as_str());
    let (user_data, email) = match (user_data, email) {
        (Some(ud), Some(em)) if !em.is_empty() => (ud, em),
        _ => return Ok(None),
    };
    let has_rriot = match user_data.get("rriot") {
        Some(Value::Object(m)) => !m.is_empty(),
        Some(Value::String(s)) => !s.is_empty(),
        Some(Value::Bool(b)) => *b,
        _ => false,
    };
    if !has_rriot {
        return Ok(None);
    }
    let credentials = Credentials::new(email, user_data.clone())
        .with_migrated_from(legacy.to_string_lossy().into_owned());
    save_credentials(&credentials)?;
    Ok(Some(credentials))
}

pub fn clear_credentials() -> bool {
    let path = credentials_path();
    if path.is_file() {
        let _ = fs::remove_file(&path);
        return true;
    }
    false
}

pub fn load_or_create_token() -> Result<String, ConfigError> {
    let path = token_path();
    if path.is_file() {
        tighten(&path);
        if let Ok(text) = fs::read_to_string(&path) {
            let trimmed = text.trim();
            if !trimmed.is_empty() {
                return Ok(trimmed.to_string());
            }
        }
    }
    let token = generate_urlsafe_token(32);
    write_private(&path, format!("{token}\n").as_bytes())?;
    Ok(token)
}

pub fn read_token() -> Option<String> {
    let path = token_path();
    if !path.is_file() {
        return None;
    }
    fs::read_to_string(&path)
        .ok()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
}

pub fn mask_email(email: &str) -> String {
    let Some((name, domain)) = email.split_once('@') else {
        return "***".to_string();
    };
    if domain.is_empty() {
        return "***".to_string();
    }
    let prefix: String = name.chars().take(1).collect();
    format!("{prefix}***@{domain}")
}

fn generate_urlsafe_token(num_bytes: usize) -> String {
    let mut buf = vec![0u8; num_bytes];
    if let Ok(mut f) = fs::File::open("/dev/urandom") {
        let _ = f.read_exact(&mut buf);
    } else {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(123456789);
        let seq = TEMP_COUNTER.fetch_add(1, Ordering::Relaxed);
        let seed = format!("{nanos}-{seq}-{}", std::process::id());
        let digest = sha256_bytes(seed.as_bytes());
        for (i, b) in buf.iter_mut().enumerate() {
            *b = digest[i % digest.len()];
        }
    }
    base64url_encode(&buf)
}

pub fn base64_encode(data: &[u8]) -> String {
    encode_base64_alphabet(
        data,
        b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/",
        true,
    )
}

pub fn base64url_encode(data: &[u8]) -> String {
    encode_base64_alphabet(
        data,
        b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_",
        false,
    )
}

fn encode_base64_alphabet(data: &[u8], alphabet: &[u8; 64], pad: bool) -> String {
    let mut out = String::with_capacity((data.len() + 2) / 3 * 4);
    for chunk in data.chunks(3) {
        let b0 = chunk[0] as u32;
        let b1 = if chunk.len() > 1 { chunk[1] as u32 } else { 0 };
        let b2 = if chunk.len() > 2 { chunk[2] as u32 } else { 0 };
        let triple = (b0 << 16) | (b1 << 8) | b2;

        out.push(alphabet[((triple >> 18) & 0x3F) as usize] as char);
        out.push(alphabet[((triple >> 12) & 0x3F) as usize] as char);
        if chunk.len() > 1 {
            out.push(alphabet[((triple >> 6) & 0x3F) as usize] as char);
        } else if pad {
            out.push('=');
        }
        if chunk.len() > 2 {
            out.push(alphabet[(triple & 0x3F) as usize] as char);
        } else if pad {
            out.push('=');
        }
    }
    out
}

pub fn base64_decode(input: &str) -> Result<Vec<u8>, String> {
    let mut out = Vec::with_capacity(input.len() * 3 / 4);
    let mut buf = 0u32;
    let mut bits = 0u32;
    for ch in input.bytes() {
        if ch == b'=' || ch.is_ascii_whitespace() {
            continue;
        }
        let val = match ch {
            b'A'..=b'Z' => ch - b'A',
            b'a'..=b'z' => ch - b'a' + 26,
            b'0'..=b'9' => ch - b'0' + 52,
            b'+' | b'-' => 62,
            b'/' | b'_' => 63,
            _ => return Err(format!("invalid base64 byte: {ch}")),
        };
        buf = (buf << 6) | (val as u32);
        bits += 6;
        if bits >= 8 {
            bits -= 8;
            out.push(((buf >> bits) & 0xFF) as u8);
        }
    }
    Ok(out)
}

pub fn sha256_hex(data: &[u8]) -> String {
    let digest = sha256_bytes(data);
    let mut hex = String::with_capacity(64);
    for b in digest {
        use fmt::Write;
        let _ = write!(&mut hex, "{b:02x}");
    }
    hex
}

pub fn sha256_bytes(data: &[u8]) -> [u8; 32] {
    const K: [u32; 64] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4,
        0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe,
        0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f,
        0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
        0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc,
        0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
        0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116,
        0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7,
        0xc67178f2,
    ];
    let mut h: [u32; 8] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab,
        0x5be0cd19,
    ];

    let bit_len = (data.len() as u64) * 8;
    let mut padded = data.to_vec();
    padded.push(0x80);
    while (padded.len() % 64) != 56 {
        padded.push(0);
    }
    padded.extend_from_slice(&bit_len.to_be_bytes());

    for chunk in padded.chunks_exact(64) {
        let mut w = [0u32; 64];
        for (i, word) in chunk.chunks_exact(4).enumerate() {
            w[i] = u32::from_be_bytes([word[0], word[1], word[2], word[3]]);
        }
        for i in 16..64 {
            let s0 = w[i - 15].rotate_right(7) ^ w[i - 15].rotate_right(18) ^ (w[i - 15] >> 3);
            let s1 = w[i - 2].rotate_right(17) ^ w[i - 2].rotate_right(19) ^ (w[i - 2] >> 10);
            w[i] = w[i - 16]
                .wrapping_add(s0)
                .wrapping_add(w[i - 7])
                .wrapping_add(s1);
        }

        let mut a = h[0];
        let mut b = h[1];
        let mut c = h[2];
        let mut d = h[3];
        let mut e = h[4];
        let mut f = h[5];
        let mut g = h[6];
        let mut hh = h[7];

        for i in 0..64 {
            let s1 = e.rotate_right(6) ^ e.rotate_right(11) ^ e.rotate_right(25);
            let ch = (e & f) ^ ((!e) & g);
            let temp1 = hh
                .wrapping_add(s1)
                .wrapping_add(ch)
                .wrapping_add(K[i])
                .wrapping_add(w[i]);
            let s0 = a.rotate_right(2) ^ a.rotate_right(13) ^ a.rotate_right(22);
            let maj = (a & b) ^ (a & c) ^ (b & c);
            let temp2 = s0.wrapping_add(maj);

            hh = g;
            g = f;
            f = e;
            e = d.wrapping_add(temp1);
            d = c;
            c = b;
            b = a;
            a = temp1.wrapping_add(temp2);
        }

        h[0] = h[0].wrapping_add(a);
        h[1] = h[1].wrapping_add(b);
        h[2] = h[2].wrapping_add(c);
        h[3] = h[3].wrapping_add(d);
        h[4] = h[4].wrapping_add(e);
        h[5] = h[5].wrapping_add(f);
        h[6] = h[6].wrapping_add(g);
        h[7] = h[7].wrapping_add(hh);
    }

    let mut out = [0u8; 32];
    for (i, word) in h.iter().enumerate() {
        out[i * 4..(i + 1) * 4].copy_from_slice(&word.to_be_bytes());
    }
    out
}
