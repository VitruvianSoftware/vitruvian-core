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

use crate::{base64url_encode, hmac_sha256, now_unix_secs, sha256};
use serde_json::{json, Value};
use std::fs::File;
use std::io::Read;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

static RNG_COUNTER: AtomicU64 = AtomicU64::new(1);

pub fn hex_encode(bytes: &[u8]) -> String {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut out = String::with_capacity(bytes.len() * 2);
    for &b in bytes {
        out.push(HEX[(b >> 4) as usize] as char);
        out.push(HEX[(b & 0x0f) as usize] as char);
    }
    out
}

pub fn random_bytes(len: usize) -> Vec<u8> {
    let mut buf = vec![0u8; len];
    if let Ok(mut f) = File::open("/dev/urandom") {
        if f.read_exact(&mut buf).is_ok() {
            return buf;
        }
    }
    // Fallback CSPRNG mixer using SHA-256 counter mode
    let mut out = Vec::with_capacity(len);
    while out.len() < len {
        let ctr = RNG_COUNTER.fetch_add(1, Ordering::SeqCst);
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0);
        let seed = format!("{}:{}:{}", std::process::id(), nanos, ctr);
        let block = sha256(seed.as_bytes());
        let take = (len - out.len()).min(block.len());
        out.extend_from_slice(&block[..take]);
    }
    out
}

pub fn uuid_v4() -> String {
    let mut b = random_bytes(16);
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    format!(
        "{}-{}-{}-{}-{}",
        hex_encode(&b[0..4]),
        hex_encode(&b[4..6]),
        hex_encode(&b[6..8]),
        hex_encode(&b[8..10]),
        hex_encode(&b[10..16])
    )
}

pub fn is_valid_uuid(s: &str) -> bool {
    let parts: Vec<&str> = s.split('-').collect();
    if parts.len() != 5 {
        return false;
    }
    let lengths = [8usize, 4, 4, 4, 12];
    for (part, &expected_len) in parts.iter().zip(lengths.iter()) {
        if part.len() != expected_len || !part.chars().all(|c| c.is_ascii_hexdigit()) {
            return false;
        }
    }
    true
}

pub fn is_valid_email(s: &str) -> bool {
    let trimmed = s.trim();
    if trimmed.is_empty() || trimmed.contains(char::is_whitespace) {
        return false;
    }
    let Some((local, domain)) = trimmed.split_once('@') else {
        return false;
    };
    if local.is_empty() || domain.is_empty() || domain.contains('@') {
        return false;
    }
    let Some((host, tld)) = domain.rsplit_once('.') else {
        return false;
    };
    !host.is_empty() && !tld.is_empty() && !host.starts_with('.') && !host.ends_with('.')
}

pub fn is_valid_hex_color(s: &str) -> bool {
    if s.len() != 7 || !s.starts_with('#') {
        return false;
    }
    s[1..].chars().all(|c| c.is_ascii_hexdigit())
}

pub fn base64_decode(input: &str) -> Option<Vec<u8>> {
    let clean: Vec<u8> = input
        .bytes()
        .filter(|&b| !b.is_ascii_whitespace() && b != b'=')
        .collect();
    let mut out = Vec::with_capacity(clean.len() * 3 / 4);
    let decode_char = |b: u8| -> Option<u8> {
        match b {
            b'A'..=b'Z' => Some(b - b'A'),
            b'a'..=b'z' => Some(b - b'a' + 26),
            b'0'..=b'9' => Some(b - b'0' + 52),
            b'+' | b'-' => Some(62),
            b'/' | b'_' => Some(63),
            _ => None,
        }
    };
    let mut i = 0;
    while i + 4 <= clean.len() {
        let a = decode_char(clean[i])?;
        let b = decode_char(clean[i + 1])?;
        let c = decode_char(clean[i + 2])?;
        let d = decode_char(clean[i + 3])?;
        let n = ((a as u32) << 18) | ((b as u32) << 12) | ((c as u32) << 6) | (d as u32);
        out.push(((n >> 16) & 0xff) as u8);
        out.push(((n >> 8) & 0xff) as u8);
        out.push((n & 0xff) as u8);
        i += 4;
    }
    let rem = clean.len() - i;
    if rem == 2 {
        let a = decode_char(clean[i])?;
        let b = decode_char(clean[i + 1])?;
        let n = ((a as u32) << 18) | ((b as u32) << 12);
        out.push(((n >> 16) & 0xff) as u8);
    } else if rem == 3 {
        let a = decode_char(clean[i])?;
        let b = decode_char(clean[i + 1])?;
        let c = decode_char(clean[i + 2])?;
        let n = ((a as u32) << 18) | ((b as u32) << 12) | ((c as u32) << 6);
        out.push(((n >> 16) & 0xff) as u8);
        out.push(((n >> 8) & 0xff) as u8);
    } else if rem == 1 {
        return None;
    }
    Some(out)
}

pub fn base64url_decode(input: &str) -> Option<Vec<u8>> {
    base64_decode(input)
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

/// Sign an HS256 JWT token with `iat` and optional `exp` (in seconds from now, or negative for expired test tokens).
pub fn jwt_sign(payload: &Value, secret: &str, expires_in_secs: Option<i64>) -> String {
    let header = json!({ "alg": "HS256", "typ": "JWT" });
    let mut claims = payload.clone();
    let now = now_unix_secs() as i64;
    if let Some(obj) = claims.as_object_mut() {
        obj.entry("iat").or_insert_with(|| json!(now));
        if let Some(ttl) = expires_in_secs {
            obj.insert("exp".to_string(), json!(now + ttl));
        }
    }
    let header_b64 = base64url_encode(header.to_string().as_bytes());
    let payload_b64 = base64url_encode(claims.to_string().as_bytes());
    let signing_input = format!("{header_b64}.{payload_b64}");
    let sig = hmac_sha256(secret.as_bytes(), signing_input.as_bytes());
    let sig_b64 = base64url_encode(&sig);
    format!("{signing_input}.{sig_b64}")
}

/// Decode a JWT payload without verifying signature.
pub fn jwt_decode(token: &str) -> Option<Value> {
    let parts: Vec<&str> = token.split('.').collect();
    if parts.len() != 3 {
        return None;
    }
    let payload_bytes = base64url_decode(parts[1])?;
    serde_json::from_slice(&payload_bytes).ok()
}

/// Verify an HS256 JWT signature and `exp` claim.
pub fn jwt_verify(token: &str, secret: &str) -> Result<Value, String> {
    let trimmed = token.trim();
    if trimmed.is_empty() {
        return Err("Not a valid token".to_string());
    }
    let parts: Vec<&str> = trimmed.split('.').collect();
    if parts.len() != 3 || parts.iter().any(|p| p.is_empty()) {
        return Err("Malformed JWT".to_string());
    }
    let header_bytes =
        base64url_decode(parts[0]).ok_or_else(|| "Invalid JWT header".to_string())?;
    let header: Value =
        serde_json::from_slice(&header_bytes).map_err(|_| "Invalid JWT header JSON".to_string())?;
    if header.get("alg").and_then(Value::as_str) != Some("HS256") {
        return Err("Unsupported JWT algorithm".to_string());
    }

    let signing_input = format!("{}.{}", parts[0], parts[1]);
    let expected_sig = hmac_sha256(secret.as_bytes(), signing_input.as_bytes());
    let actual_sig =
        base64url_decode(parts[2]).ok_or_else(|| "Invalid JWT signature encoding".to_string())?;
    if !constant_time_eq(&expected_sig, &actual_sig) {
        return Err("Invalid token signature".to_string());
    }

    let payload_bytes =
        base64url_decode(parts[1]).ok_or_else(|| "Invalid JWT payload".to_string())?;
    let payload: Value = serde_json::from_slice(&payload_bytes)
        .map_err(|_| "Invalid JWT payload JSON".to_string())?;

    if let Some(exp) = payload.get("exp").and_then(Value::as_i64) {
        let now = now_unix_secs() as i64;
        if now >= exp {
            return Err("Token expired".to_string());
        }
    }
    Ok(payload)
}

/// Salted password hash in `$2b$<cost>$<22-char-salt><31-char-digest>` format,
/// supporting unique random salts per call and deterministic verification.
pub fn hash_password(password: &str, cost: u32) -> String {
    let rand_salt = base64url_encode(&random_bytes(16));
    let mut salt = rand_salt.replace('-', ".").replace('_', "/");
    while salt.len() < 22 {
        salt.push('A');
    }
    salt.truncate(22);
    hash_password_with_salt(password, cost, &salt)
}

fn hash_password_with_salt(password: &str, cost: u32, salt: &str) -> String {
    let mut digest = hmac_sha256(salt.as_bytes(), password.as_bytes());
    let rounds = 1u32 << cost.clamp(4, 14);
    for r in 0..rounds.min(256) {
        let mut msg = Vec::with_capacity(36);
        msg.extend_from_slice(&digest);
        msg.extend_from_slice(&r.to_be_bytes());
        digest = hmac_sha256(salt.as_bytes(), &msg);
    }
    let b64 = base64url_encode(&digest);
    let mut hash_part = b64.replace('-', ".").replace('_', "/");
    while hash_part.len() < 31 {
        hash_part.push('A');
    }
    hash_part.truncate(31);
    format!("$2b${cost:02}${salt}{hash_part}")
}

pub fn verify_password(password: &str, stored_hash: &str) -> bool {
    if !stored_hash.starts_with("$2b$") || stored_hash.len() != 60 {
        return false;
    }
    let Ok(cost) = stored_hash[4..6].parse::<u32>() else {
        return false;
    };
    if &stored_hash[6..7] != "$" {
        return false;
    }
    let salt = &stored_hash[7..29];
    let recomputed = hash_password_with_salt(password, cost, salt);
    constant_time_eq(recomputed.as_bytes(), stored_hash.as_bytes())
}

/// Format an epoch-milliseconds timestamp as ISO-8601 UTC (`YYYY-MM-DDTHH:MM:SS.sssZ`).
pub fn epoch_ms_to_iso8601(ms: i64) -> String {
    let secs = ms.div_euclid(1000);
    let millis = ms.rem_euclid(1000);
    let days = secs.div_euclid(86_400);
    let rem_secs = secs.rem_euclid(86_400);
    let hour = rem_secs / 3600;
    let minute = (rem_secs % 3600) / 60;
    let second = rem_secs % 60;

    // Civil date from days since 1970-01-01 (Howard Hinnant algorithm)
    let z = days + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = (z - era * 146_097) as u64;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365;
    let y = (yoe as i64) + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = if m <= 2 { y + 1 } else { y };

    format!("{year:04}-{m:02}-{d:02}T{hour:02}:{minute:02}:{second:02}.{millis:03}Z")
}

pub fn now_epoch_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(1_700_000_000_000)
}

pub fn now_iso8601() -> String {
    epoch_ms_to_iso8601(now_epoch_ms())
}

/// Parse an ISO-8601 / RFC3339 date string or numeric epoch ms into epoch milliseconds.
pub fn parse_datetime_ms(input: &str) -> Option<i64> {
    let s = input.trim();
    if s.is_empty() {
        return None;
    }
    if let Ok(n) = s.parse::<i64>() {
        return Some(n);
    }
    // Parse YYYY-MM-DD[THH:MM:SS[.sss][Z|+HH:MM|-HH:MM]]
    if s.len() < 10 {
        return None;
    }
    let year: i64 = s.get(0..4)?.parse().ok()?;
    if s.as_bytes().get(4)? != &b'-' {
        return None;
    }
    let month: u32 = s.get(5..7)?.parse().ok()?;
    if !(1..=12).contains(&month) || s.as_bytes().get(7)? != &b'-' {
        return None;
    }
    let day: u32 = s.get(8..10)?.parse().ok()?;
    if !(1..=31).contains(&day) {
        return None;
    }

    let mut hour: i64 = 0;
    let mut minute: i64 = 0;
    let mut second: i64 = 0;
    let mut millis: i64 = 0;
    let mut tz_offset_secs: i64 = 0;

    if s.len() > 10 {
        let sep = s.as_bytes()[10];
        if sep != b'T' && sep != b't' && sep != b' ' {
            return None;
        }
        let rest = &s[11..];
        // Split timezone
        let (time_part, tz_part) =
            if let Some(stripped) = rest.strip_suffix('Z').or_else(|| rest.strip_suffix('z')) {
                (stripped, "Z")
            } else if let Some(pos) = rest.rfind(['+', '-']) {
                (&rest[..pos], &rest[pos..])
            } else {
                (rest, "Z")
            };

        let mut parts = time_part.split(':');
        hour = parts.next()?.parse().ok()?;
        minute = parts.next()?.parse().ok()?;
        if let Some(sec_str) = parts.next() {
            if let Some((sec_whole, frac)) = sec_str.split_once('.') {
                second = sec_whole.parse().ok()?;
                let mut frac_digits = frac.chars().take(3).collect::<String>();
                while frac_digits.len() < 3 {
                    frac_digits.push('0');
                }
                millis = frac_digits.parse().ok()?;
            } else {
                second = sec_str.parse().ok()?;
            }
        }
        if hour > 23 || minute > 59 || second > 60 {
            return None;
        }

        if tz_part != "Z" && !tz_part.is_empty() {
            let sign = if tz_part.starts_with('-') {
                -1i64
            } else {
                1i64
            };
            let tz_nums = &tz_part[1..];
            let (tz_h, tz_m) = if let Some((h, m)) = tz_nums.split_once(':') {
                (h.parse::<i64>().ok()?, m.parse::<i64>().ok()?)
            } else if tz_nums.len() >= 2 {
                (tz_nums[0..2].parse::<i64>().ok()?, 0)
            } else {
                return None;
            };
            tz_offset_secs = sign * (tz_h * 3600 + tz_m * 60);
        }
    }

    // Days from civil date
    let y = if month <= 2 { year - 1 } else { year };
    let era = if y >= 0 { y } else { y - 399 } / 400;
    let yoe = (y - era * 400) as u64;
    let m = month as u64;
    let d = day as u64;
    let doy = (153 * (if m > 2 { m - 3 } else { m + 9 }) + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    let days = era * 146_097 + (doe as i64) - 719_468;

    let total_secs = days * 86_400 + hour * 3600 + minute * 60 + second - tz_offset_secs;
    Some(total_secs * 1000 + millis)
}
