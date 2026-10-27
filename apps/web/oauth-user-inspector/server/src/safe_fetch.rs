// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT
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

use serde::de::DeserializeOwned;
use serde_json::Value;
use std::collections::HashMap;
use std::fmt;
use std::net::{IpAddr, Ipv4Addr, Ipv6Addr, ToSocketAddrs};
use std::process::Command;

/// Error raised for any policy violation or transport failure when talking to an
/// upstream OAuth / API server. `Display` / `message()` is always a generic string
/// safe to return to the browser; `reason` carries the specific diagnostic for
/// server-side logs only (never serialize `reason` into an HTTP response).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UpstreamError {
    pub message: String,
    pub reason: String,
}

impl UpstreamError {
    pub fn new(reason: impl Into<String>) -> Self {
        Self {
            message: "Upstream request failed".to_string(),
            reason: reason.into(),
        }
    }

    pub fn message(&self) -> &str {
        &self.message
    }
}

impl fmt::Display for UpstreamError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.message)
    }
}

impl std::error::Error for UpstreamError {}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LookupAddress {
    pub address: String,
    pub family: u8,
}

impl LookupAddress {
    pub fn v4(address: impl Into<String>) -> Self {
        Self {
            address: address.into(),
            family: 4,
        }
    }

    pub fn v6(address: impl Into<String>) -> Self {
        Self {
            address: address.into(),
            family: 6,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ParsedUrl {
    pub raw: String,
    pub protocol: String,
    pub hostname: String,
    pub port: u16,
    pub pathname: String,
    pub search: String,
}

impl ParsedUrl {
    pub fn parse(raw_url: &str) -> Result<Self, UpstreamError> {
        let trimmed = raw_url.trim();
        let Some(scheme_end) = trimmed.find("://") else {
            return Err(UpstreamError::new("Invalid upstream URL"));
        };
        let scheme = &trimmed[..scheme_end];
        if scheme.is_empty()
            || !scheme
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || c == '+' || c == '-' || c == '.')
        {
            return Err(UpstreamError::new("Invalid upstream URL"));
        }
        let protocol = format!("{}:", scheme.to_ascii_lowercase());
        let after_scheme = &trimmed[scheme_end + 3..];
        if after_scheme.is_empty() {
            return Err(UpstreamError::new("Invalid upstream URL"));
        }

        // Split authority from path/query/fragment
        let authority_end = after_scheme
            .find(['/', '?', '#'])
            .unwrap_or(after_scheme.len());
        let authority = &after_scheme[..authority_end];
        let rest = &after_scheme[authority_end..];

        if authority.is_empty()
            || authority.contains('@')
            || authority.contains(char::is_whitespace)
        {
            return Err(UpstreamError::new("Invalid upstream URL"));
        }

        // Parse host and optional port from authority
        let (hostname, port_opt) = if authority.starts_with('[') {
            let Some(close_bracket) = authority.find(']') else {
                return Err(UpstreamError::new("Invalid upstream URL"));
            };
            let host = &authority[1..close_bracket];
            let port_part = &authority[close_bracket + 1..];
            let port = if port_part.is_empty() {
                None
            } else if let Some(p_str) = port_part.strip_prefix(':') {
                let p = p_str
                    .parse::<u16>()
                    .map_err(|_| UpstreamError::new("Invalid upstream URL"))?;
                Some(p)
            } else {
                return Err(UpstreamError::new("Invalid upstream URL"));
            };
            (host.to_ascii_lowercase(), port)
        } else if let Some((h, p_str)) = authority.rsplit_once(':') {
            if h.contains(':') {
                // Unbracketed IPv6 in URL is invalid
                return Err(UpstreamError::new("Invalid upstream URL"));
            }
            let p = if p_str.is_empty() {
                None
            } else {
                Some(
                    p_str
                        .parse::<u16>()
                        .map_err(|_| UpstreamError::new("Invalid upstream URL"))?,
                )
            };
            (h.to_ascii_lowercase(), p)
        } else {
            (authority.to_ascii_lowercase(), None)
        };

        if hostname.is_empty() {
            return Err(UpstreamError::new("Invalid upstream URL"));
        }

        let default_port = match protocol.as_str() {
            "https:" => 443,
            "http:" => 80,
            _ => 443,
        };
        let port = port_opt.unwrap_or(default_port);

        // Strip fragment (#...)
        let without_fragment = match rest.find('#') {
            Some(idx) => &rest[..idx],
            None => rest,
        };

        let (pathname, search) = match without_fragment.find('?') {
            Some(q_idx) => {
                let p = &without_fragment[..q_idx];
                let q = &without_fragment[q_idx..];
                (
                    if p.is_empty() {
                        "/".to_string()
                    } else {
                        p.to_string()
                    },
                    q.to_string(),
                )
            }
            None => (
                if without_fragment.is_empty() {
                    "/".to_string()
                } else {
                    without_fragment.to_string()
                },
                String::new(),
            ),
        };

        Ok(Self {
            raw: trimmed.to_string(),
            protocol,
            hostname,
            port,
            pathname,
            search,
        })
    }
}

fn is_denied_ipv4(ip: Ipv4Addr) -> bool {
    let o = ip.octets();
    // 0.0.0.0/8 — "this network" (RFC 1122)
    if o[0] == 0 {
        return true;
    }
    // 10.0.0.0/8 — RFC 1918
    if o[0] == 10 {
        return true;
    }
    // 100.64.0.0/10 — CGNAT / Tailscale (RFC 6598)
    if o[0] == 100 && (o[1] & 0xc0) == 64 {
        return true;
    }
    // 127.0.0.0/8 — loopback
    if o[0] == 127 {
        return true;
    }
    // 169.254.0.0/16 — link-local + cloud metadata (169.254.169.254)
    if o[0] == 169 && o[1] == 254 {
        return true;
    }
    // 172.16.0.0/12 — RFC 1918
    if o[0] == 172 && (o[1] & 0xf0) == 16 {
        return true;
    }
    // 192.0.0.0/24 — IETF protocol assignments
    if o[0] == 192 && o[1] == 0 && o[2] == 0 {
        return true;
    }
    // 192.0.2.0/24 — TEST-NET-1
    if o[0] == 192 && o[1] == 0 && o[2] == 2 {
        return true;
    }
    // 192.88.99.0/24 — 6to4 relay anycast
    if o[0] == 192 && o[1] == 88 && o[2] == 99 {
        return true;
    }
    // 192.168.0.0/16 — RFC 1918
    if o[0] == 192 && o[1] == 168 {
        return true;
    }
    // 198.18.0.0/15 — benchmarking
    if o[0] == 198 && (o[1] & 0xfe) == 18 {
        return true;
    }
    // 198.51.100.0/24 — TEST-NET-2
    if o[0] == 198 && o[1] == 51 && o[2] == 100 {
        return true;
    }
    // 203.0.113.0/24 — TEST-NET-3
    if o[0] == 203 && o[1] == 0 && o[2] == 113 {
        return true;
    }
    // 224.0.0.0/4 — multicast
    if (o[0] & 0xf0) == 224 {
        return true;
    }
    // 240.0.0.0/4 — reserved / future use + 255.255.255.255/32 broadcast
    if (o[0] & 0xf0) == 240 {
        return true;
    }
    false
}

fn is_denied_ipv6(ip: Ipv6Addr) -> bool {
    if let Some(mapped_v4) = ip.to_ipv4_mapped() {
        return is_denied_ipv4(mapped_v4);
    }
    if let Some(compat_v4) = ip.to_ipv4() {
        return is_denied_ipv4(compat_v4);
    }
    let s = ip.segments();
    // ::/128 — unspecified
    if ip.is_unspecified() {
        return true;
    }
    // ::1/128 — loopback
    if ip.is_loopback() {
        return true;
    }
    // 64:ff9b::/96 — NAT64 well-known prefix
    if s[0] == 0x0064 && s[1] == 0xff9b && s[2] == 0 && s[3] == 0 && s[4] == 0 && s[5] == 0 {
        return true;
    }
    // 100::/64 — discard-only (RFC 6666)
    if s[0] == 0x0100 && s[1] == 0 && s[2] == 0 && s[3] == 0 {
        return true;
    }
    // 2001::/32 — Teredo
    if s[0] == 0x2001 && s[1] == 0x0000 {
        return true;
    }
    // 2001:db8::/32 — documentation
    if s[0] == 0x2001 && s[1] == 0x0db8 {
        return true;
    }
    // 2002::/16 — 6to4
    if s[0] == 0x2002 {
        return true;
    }
    // fc00::/7 — unique-local (fc00:: / fd00::)
    if (s[0] & 0xfe00) == 0xfc00 {
        return true;
    }
    // fe80::/10 — link-local
    if (s[0] & 0xffc0) == 0xfe80 {
        return true;
    }
    // ff00::/8 — multicast
    if (s[0] & 0xff00) == 0xff00 {
        return true;
    }
    false
}

/// Return `true` iff `address` is a globally routable unicast IP (v4 or v6).
/// Handles IPv4-mapped IPv6 (`::ffff:a.b.c.d` and `::ffff:xxxx:yyyy`) by
/// extracting and checking the embedded IPv4 address.
pub fn vet_address(address: &str) -> bool {
    let bare = address.split('%').next().unwrap_or(address);
    let Ok(ip) = bare.parse::<IpAddr>() else {
        return false;
    };
    match ip {
        IpAddr::V4(v4) => !is_denied_ipv4(v4),
        IpAddr::V6(v6) => !is_denied_ipv6(v6),
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ResolvedPin {
    pub url: ParsedUrl,
    pub hostname: String,
    pub port: u16,
    pub path_with_query: String,
    pub address: String,
    pub family: u8,
}

pub fn default_dns_lookup(hostname: &str) -> Result<Vec<LookupAddress>, String> {
    let addrs = (hostname, 443u16)
        .to_socket_addrs()
        .map_err(|e| e.to_string())?;
    let mut out = Vec::new();
    for sock in addrs {
        match sock.ip() {
            IpAddr::V4(v4) => out.push(LookupAddress::v4(v4.to_string())),
            IpAddr::V6(v6) => out.push(LookupAddress::v6(v6.to_string())),
        }
    }
    Ok(out)
}

/// Parse `raw_url`, enforce `https:`, resolve all A/AAAA records via `lookup`,
/// and reject the host if ANY record falls in a non-public range (defends against
/// split-horizon / round-robin records that mix one public IP with `127.0.0.1`).
/// Returns the first vetted record for socket pinning.
pub fn resolve_and_pin_with<F>(raw_url: &str, lookup: F) -> Result<ResolvedPin, UpstreamError>
where
    F: FnOnce(&str) -> Result<Vec<LookupAddress>, String>,
{
    let url = ParsedUrl::parse(raw_url)?;
    if url.protocol != "https:" {
        return Err(UpstreamError::new(format!(
            "Only https:// upstream URLs are allowed (got {})",
            url.protocol
        )));
    }
    let hostname = url.hostname.clone();
    let records =
        lookup(&hostname).map_err(|e| UpstreamError::new(format!("DNS lookup failed: {e}")))?;

    if records.is_empty() {
        return Err(UpstreamError::new("DNS lookup returned no addresses"));
    }

    for rec in &records {
        if !vet_address(&rec.address) {
            return Err(UpstreamError::new(format!(
                "Blocked IP address {} for {}",
                rec.address, hostname
            )));
        }
    }

    let first = &records[0];
    let path_with_query = format!("{}{}", url.pathname, url.search);
    let port = url.port;

    Ok(ResolvedPin {
        url,
        hostname,
        port,
        path_with_query,
        address: first.address.clone(),
        family: first.family,
    })
}

pub fn resolve_and_pin(raw_url: &str) -> Result<ResolvedPin, UpstreamError> {
    resolve_and_pin_with(raw_url, default_dns_lookup)
}

/// Default `User-Agent` attached to every outbound request when the caller does
/// not supply one. Several OAuth/API providers (notably GitHub's REST + GraphQL
/// APIs) reject requests with no `User-Agent` header with `403 Forbidden`.
pub const SAFE_FETCH_USER_AGENT: &str = "oauth-user-inspector";

/// Return a shallow copy of `headers` with `User-Agent: oauth-user-inspector`
/// populated unless a `user-agent` header (any case) is already present.
pub fn with_default_user_agent(headers: &HashMap<String, String>) -> HashMap<String, String> {
    let mut out = headers.clone();
    let has_ua = out.keys().any(|k| k.eq_ignore_ascii_case("user-agent"));
    if !has_ua {
        out.insert("User-Agent".to_string(), SAFE_FETCH_USER_AGENT.to_string());
    }
    out
}

/// Return a shallow copy of `headers` with `Content-Length` set to the UTF-8
/// byte length of `body` when `body` is non-empty and neither `Content-Length`
/// nor `Transfer-Encoding` is already set.
///
/// Several strict OAuth token endpoints (Google, Microsoft, LinkedIn) reject
/// POST bodies served with `Transfer-Encoding: chunked` and no `Content-Length`
/// with `411 Length Required` or `400 invalid_request`.
pub fn with_content_length(
    headers: &HashMap<String, String>,
    body: Option<&str>,
) -> HashMap<String, String> {
    let mut out = headers.clone();
    let Some(b) = body else {
        return out;
    };
    if b.is_empty() {
        return out;
    }
    let has_framing = out.keys().any(|k| {
        k.eq_ignore_ascii_case("content-length") || k.eq_ignore_ascii_case("transfer-encoding")
    });
    if !has_framing {
        out.insert("Content-Length".to_string(), b.len().to_string());
    }
    out
}

#[derive(Debug, Clone)]
pub struct SafeFetchOptions {
    pub method: String,
    pub headers: HashMap<String, String>,
    pub body: Option<String>,
    pub timeout_ms: u64,
    pub max_bytes: usize,
}

impl Default for SafeFetchOptions {
    fn default() -> Self {
        Self {
            method: "GET".to_string(),
            headers: HashMap::new(),
            body: None,
            timeout_ms: 10_000,
            max_bytes: 2 * 1024 * 1024,
        }
    }
}

#[derive(Debug, Clone)]
pub struct SafeFetchResponse {
    pub status: u16,
    pub status_text: String,
    pub headers: HashMap<String, String>,
    pub body: String,
}

impl SafeFetchResponse {
    pub fn ok(&self) -> bool {
        (200..300).contains(&self.status)
    }

    pub fn header(&self, name: &str) -> Option<&str> {
        let lower = name.to_ascii_lowercase();
        self.headers
            .iter()
            .find(|(k, _)| k.to_ascii_lowercase() == lower)
            .map(|(_, v)| v.as_str())
    }

    pub fn text(&self) -> &str {
        &self.body
    }

    pub fn json<T: DeserializeOwned>(&self) -> Result<T, serde_json::Error> {
        serde_json::from_str(&self.body)
    }

    pub fn json_value(&self) -> Result<Value, serde_json::Error> {
        serde_json::from_str(&self.body)
    }
}

/// Perform an HTTPS request with SSRF protections:
/// - `https:` only
/// - DNS resolved once, vetted against private/metadata/reserved ranges, and
///   pinned via `curl --resolve <host>:<port>:<ip>` so TLS SNI + cert verification
///   use `hostname` while the TCP socket connects to the vetted IP.
/// - Redirects disabled (`3xx` raises `UpstreamError`).
/// - Hard timeout (`timeout_ms`) and response size cap (`max_bytes`).
pub fn safe_fetch(
    raw_url: &str,
    opts: &SafeFetchOptions,
) -> Result<SafeFetchResponse, UpstreamError> {
    let pin = resolve_and_pin(raw_url)?;
    let headers = with_content_length(
        &with_default_user_agent(&opts.headers),
        opts.body.as_deref(),
    );

    let timeout_secs = (opts.timeout_ms as f64 / 1000.0).max(1.0);
    let resolve_entry = format!("{}:{}:{}", pin.hostname, pin.port, pin.address);

    let mut cmd = Command::new("curl");
    cmd.arg("--silent")
        .arg("--show-error")
        .arg("--include")
        .arg("--proto")
        .arg("=https")
        .arg("--max-time")
        .arg(format!("{timeout_secs:.2}"))
        .arg("--max-filesize")
        .arg(opts.max_bytes.to_string())
        .arg("--resolve")
        .arg(&resolve_entry)
        .arg("-X")
        .arg(&opts.method);

    for (k, v) in &headers {
        cmd.arg("-H").arg(format!("{k}: {v}"));
    }

    if let Some(body) = &opts.body {
        cmd.arg("--data-raw").arg(body);
    }

    cmd.arg(&pin.url.raw);

    let output = cmd
        .output()
        .map_err(|e| UpstreamError::new(format!("Upstream request failed: {e}")))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        if output.status.code() == Some(63) {
            return Err(UpstreamError::new(format!(
                "Upstream response exceeded {} bytes",
                opts.max_bytes
            )));
        }
        return Err(UpstreamError::new(format!(
            "Upstream request failed: {}",
            stderr.trim()
        )));
    }

    parse_raw_http_response(&output.stdout, opts.max_bytes)
}

fn split_once_header_body(s: &str) -> Option<(&str, &str)> {
    if let Some((h, b)) = s.split_once("\r\n\r\n") {
        Some((h, b))
    } else {
        s.split_once("\n\n")
    }
}

fn parse_raw_http_response(
    raw: &[u8],
    max_bytes: usize,
) -> Result<SafeFetchResponse, UpstreamError> {
    let text = String::from_utf8_lossy(raw);
    let mut remainder: &str = &text;

    loop {
        let (header_block, body_str) = split_once_header_body(remainder)
            .ok_or_else(|| UpstreamError::new("Malformed upstream HTTP response"))?;

        let mut lines = header_block.lines();
        let status_line = lines
            .next()
            .ok_or_else(|| UpstreamError::new("Empty upstream status line"))?;
        let mut parts = status_line.splitn(3, ' ');
        let _http_ver = parts.next();
        let status_code: u16 = parts
            .next()
            .and_then(|s| s.parse().ok())
            .ok_or_else(|| UpstreamError::new("Invalid upstream status code"))?;
        let status_text = parts.next().unwrap_or("").trim().to_string();

        if (100..200).contains(&status_code) {
            remainder = body_str;
            continue;
        }

        if body_str.len() > max_bytes {
            return Err(UpstreamError::new(format!(
                "Upstream response exceeded {max_bytes} bytes"
            )));
        }

        if (300..400).contains(&status_code) {
            return Err(UpstreamError::new(format!(
                "Redirect blocked (status {status_code})"
            )));
        }

        let mut headers = HashMap::new();
        for line in lines {
            if let Some((k, v)) = line.split_once(':') {
                headers.insert(k.trim().to_ascii_lowercase(), v.trim().to_string());
            }
        }

        return Ok(SafeFetchResponse {
            status: status_code,
            status_text,
            headers,
            body: body_str.to_string(),
        });
    }
}
