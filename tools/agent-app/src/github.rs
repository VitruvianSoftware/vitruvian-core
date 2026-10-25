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

//! The `GitHub` class: a GET-only REST client where every failure is a
//! ReadError, never a default.

use crate::http;
use crate::json::{self, Value};
use crate::pyerr::Crash;
use crate::pystr;

/// Why a read failed: a ReadError (always fails the check), or an
/// exception the script does not catch.
#[derive(Debug, PartialEq)]
pub enum ReadFail {
    Read(String),
    Crash(Crash),
}

/// What the judging reads GitHub through, so tests can stand in for it.
pub trait Api {
    /// `-> (parsed JSON body, URL of the next page or None)`.
    fn get(&mut self, path_or_url: &str) -> Result<(Value, Option<String>), ReadFail>;
}

pub struct GitHub {
    token: String,
    api: String,
}

impl GitHub {
    pub fn new(token: &str, api: &str) -> GitHub {
        GitHub {
            token: token.to_string(),
            api: api.trim_end_matches('/').to_string(),
        }
    }
}

impl Api for GitHub {
    fn get(&mut self, path_or_url: &str) -> Result<(Value, Option<String>), ReadFail> {
        let url = if path_or_url.contains("://") {
            path_or_url.to_string()
        } else {
            format!("{}{}", self.api, path_or_url)
        };
        let headers = [
            // A header, never the URL: a token in a URL ends up in logs.
            ("Authorization", format!("Bearer {}", self.token)),
            ("Accept", "application/vnd.github+json".to_string()),
            ("X-GitHub-Api-Version", "2022-11-28".to_string()),
            (
                "User-Agent",
                "VitruvianSoftware/vitruvian-core agent-app permission-drift".to_string(),
            ),
        ];
        let response = match http::get(&url, &headers, 30) {
            Ok(r) => r,
            Err(http::Error::Http { code, body }) => {
                return Err(ReadFail::Read(format!(
                    "GET {}: HTTP {} {}",
                    short(&url),
                    code,
                    message(&body)
                )))
            }
            Err(http::Error::Os(reason)) => {
                return Err(ReadFail::Read(format!("GET {}: {}", short(&url), reason)))
            }
            Err(http::Error::Crash(c)) => return Err(ReadFail::Crash(c)),
        };
        let link = response.header("Link").unwrap_or("").to_string();
        let body = decode_json(&response.body)
            .map_err(|_| ReadFail::Read(format!("GET {}: the answer is not JSON", short(&url))))?;
        Ok((body, next_link(&link)))
    }
}

/// `https://api.github.com/apps/x -> /apps/x`, for messages.
pub fn short(url: &str) -> String {
    let after = match url.split_once("://") {
        Some((_, rest)) => rest,
        None => url,
    };
    let path = match after.split_once('/') {
        Some((_, rest)) => rest,
        None => after,
    };
    format!("/{}", path)
}

/// The error body's "message", or "" when there is none to read.
fn message(body: &[u8]) -> String {
    match decode_json(body) {
        Ok(v @ Value::Obj(_)) => v.get("message").map_or(String::new(), Value::py_str),
        _ => String::new(),
    }
}

/// The `rel="next"` URL of a Link header, as
/// `re.match(r'\s*<([^>]+)>\s*;\s*rel="next"', part)` finds it.
pub fn next_link(header: &str) -> Option<String> {
    for part in header.split(',') {
        let p = part.trim_start_matches(pystr::is_space);
        let Some(p) = p.strip_prefix('<') else {
            continue;
        };
        let Some(end) = p.find('>') else {
            continue;
        };
        if end == 0 {
            continue;
        }
        let rest = p[end + 1..].trim_start_matches(pystr::is_space);
        let Some(rest) = rest.strip_prefix(';') else {
            continue;
        };
        if rest
            .trim_start_matches(pystr::is_space)
            .starts_with("rel=\"next\"")
        {
            return Some(p[..end].to_string());
        }
    }
    None
}

/// `json.load` on a response: bytes in whichever UTF the start suggests.
fn decode_json(body: &[u8]) -> Result<Value, Crash> {
    let units = |b: &[u8], n: usize, be: bool| -> Vec<u32> {
        b.chunks(n)
            .filter(|c| c.len() == n)
            .map(|c| {
                c.iter().enumerate().fold(0u32, |acc, (i, x)| {
                    let shift = if be { (n - 1 - i) * 8 } else { i * 8 };
                    acc | (*x as u32) << shift
                })
            })
            .collect()
    };
    let bad = |what: &str| {
        Crash::new(
            "UnicodeDecodeError",
            format!("'{}' codec can't decode bytes", what),
        )
    };
    let text = if body.starts_with(&[0, 0, 0xFE, 0xFF]) || body.starts_with(&[0xFF, 0xFE, 0, 0]) {
        let be = body[0] == 0;
        utf32(&units(&body[4..], 4, be)).ok_or_else(|| bad("utf-32"))?
    } else if body.starts_with(&[0xFE, 0xFF]) || body.starts_with(&[0xFF, 0xFE]) {
        let be = body[0] == 0xFE;
        String::from_utf16(
            &units(&body[2..], 2, be)
                .iter()
                .map(|u| *u as u16)
                .collect::<Vec<_>>(),
        )
        .map_err(|_| bad("utf-16"))?
    } else if let Some(rest) = body.strip_prefix(&[0xEF, 0xBB, 0xBF]) {
        String::from_utf8(rest.to_vec()).map_err(|_| bad("utf-8"))?
    } else if body.len() >= 4 && body[0] == 0 {
        if body[1] != 0 {
            String::from_utf16(
                &units(body, 2, true)
                    .iter()
                    .map(|u| *u as u16)
                    .collect::<Vec<_>>(),
            )
            .map_err(|_| bad("utf-16-be"))?
        } else {
            utf32(&units(body, 4, true)).ok_or_else(|| bad("utf-32-be"))?
        }
    } else if body.len() >= 4 && body[1] == 0 {
        if body[2] != 0 || body[3] != 0 {
            String::from_utf16(
                &units(body, 2, false)
                    .iter()
                    .map(|u| *u as u16)
                    .collect::<Vec<_>>(),
            )
            .map_err(|_| bad("utf-16-le"))?
        } else {
            utf32(&units(body, 4, false)).ok_or_else(|| bad("utf-32-le"))?
        }
    } else if body.len() == 2 && (body[0] == 0 || body[1] == 0) {
        let be = body[0] == 0;
        String::from_utf16(
            &units(body, 2, be)
                .iter()
                .map(|u| *u as u16)
                .collect::<Vec<_>>(),
        )
        .map_err(|_| bad("utf-16"))?
    } else {
        String::from_utf8(body.to_vec()).map_err(|_| bad("utf-8"))?
    };
    json::loads(&text).map_err(|e| Crash::new("json.decoder.JSONDecodeError", e.to_string()))
}

fn utf32(units: &[u32]) -> Option<String> {
    units.iter().map(|u| char::from_u32(*u)).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn short_paths() {
        assert_eq!(short("https://api.github.com/apps/x"), "/apps/x");
        assert_eq!(
            short("http://127.0.0.1:1/orgs/O/installations?per_page=100"),
            "/orgs/O/installations?per_page=100"
        );
        assert_eq!(short("http://host"), "/host");
        assert_eq!(short("/apps/x"), "/apps/x");
    }

    #[test]
    fn links() {
        let h = r#"<https://x/a?page=1>; rel="prev", <https://x/a?page=3>; rel="next""#;
        assert_eq!(next_link(h).as_deref(), Some("https://x/a?page=3"));
        assert_eq!(next_link(r#"<u> ; rel="next""#).as_deref(), Some("u"));
        assert_eq!(next_link(r#"<>; rel="next""#), None);
        assert_eq!(next_link(r#"<u>; rel="last""#), None);
        assert_eq!(next_link(""), None);
    }

    #[test]
    fn json_in_any_utf() {
        assert_eq!(decode_json(b"\xef\xbb\xbf[]").unwrap(), Value::Arr(vec![]));
        assert_eq!(
            decode_json(b"[\x001\x00]\x00").unwrap(),
            json::loads("[1]").unwrap()
        );
        assert!(decode_json(b"<html>").is_err());
        assert!(decode_json(b"").is_err());
        assert_eq!(message(br#"{"message": "Not Found"}"#), "Not Found");
        assert_eq!(message(br#"{"message": null}"#), "None");
        assert_eq!(message(b"[1]"), "");
        assert_eq!(message(b"nope"), "");
    }
}
