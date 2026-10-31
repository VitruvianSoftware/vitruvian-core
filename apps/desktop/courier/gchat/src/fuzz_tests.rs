// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-only

use std::collections::BTreeMap;

use url::Url;

use crate::channel::ChunkParser;
use crate::cookies::{normalize_user_agent, DomainCookieJar, ScopedCookie};
use crate::fmt::inbound::annotations_to_matrix_html;
use crate::fmt::outbound::matrix_html_to_annotations;
use crate::pb;
use crate::pblite::{decode_pblite, decode_pblite_dynamic, encode_pblite_dynamic};
use crate::DESCRIPTOR_POOL;

/// Single-input entrypoint for `cargo fuzz` target `fuzz_chunk_parser`.
pub fn fuzz_chunk_parser_once(data: &[u8]) -> bool {
    let mut parser = ChunkParser::new();
    let _ = parser.push_bytes(data);

    // Also feed in small slices derived from the input bytes.
    let mut sliced = ChunkParser::new();
    let mut idx = 0;
    while idx < data.len() {
        let step = ((data[idx] as usize) % 17).max(1);
        let end = (idx + step).min(data.len());
        if sliced.push_bytes(&data[idx..end]).is_err() {
            break;
        }
        idx = end;
    }
    true
}

/// Single-input entrypoint for `cargo fuzz` target `fuzz_pblite_event`.
pub fn fuzz_pblite_event_once(data: &[u8]) -> bool {
    let Ok(s) = std::str::from_utf8(data) else {
        return true;
    };
    let body = s.strip_prefix(")]}'\n").unwrap_or(s);
    let Ok(val) = serde_json::from_str::<serde_json::Value>(body) else {
        return true;
    };
    for msg_name in [
        "googlechat.StreamEventsResponse",
        "googlechat.Event",
        "googlechat.Message",
    ] {
        if let Some(desc) = DESCRIPTOR_POOL.get_message_by_name(msg_name) {
            if let Ok(dynamic) = decode_pblite_dynamic(&desc, &val, 0) {
                let _ = encode_pblite_dynamic(&dynamic);
            }
        }
    }
    if let Some(desc) = DESCRIPTOR_POOL.get_message_by_name("googlechat.StreamEventsResponse") {
        let _ = decode_pblite::<pb::StreamEventsResponse>(&desc, &val);
    }
    true
}

/// Single-input entrypoint for `cargo fuzz` target `fuzz_fmt_annotations`.
pub fn fuzz_fmt_annotations_once(data: &[u8]) -> bool {
    let s = String::from_utf8_lossy(data);
    if let Ok(out) = matrix_html_to_annotations(&s, Some(&s), true) {
        let round = annotations_to_matrix_html(&out.text, &out.annotations, &[]);
        assert!(std::str::from_utf8(round.body.as_bytes()).is_ok());
        if let Some(html) = round.formatted_body.as_ref() {
            assert!(std::str::from_utf8(html.as_bytes()).is_ok());
        }
    }

    // Also construct arbitrary synthetic Annotation spans from the byte stream to exercise
    // UTF-16 boundary clamping, negative indices, huge lengths, and surrogate-pair guards.
    let mut synth_anns = Vec::new();
    for chunk in data.chunks(5) {
        let start = chunk.first().map(|&b| (b as i32) - 16).unwrap_or(0);
        let length = chunk.get(1).map(|&b| (b as i32) - 8).unwrap_or(1);
        let fmt_code = chunk.get(2).map(|&b| (b % 12) as i32).unwrap_or(1);
        let color = chunk.get(3).and_then(|&b| {
            if b & 1 == 1 {
                Some(((b as i32) << 16) | 0x001122)
            } else {
                None
            }
        });
        let kind = chunk.get(4).copied().unwrap_or(0) % 4;
        let metadata = match kind {
            0 => Some(pb::annotation::Metadata::FormatMetadata(
                pb::FormatMetadata {
                    format_type: Some(fmt_code),
                    font_color: color,
                },
            )),
            1 => Some(pb::annotation::Metadata::UserMentionMetadata(
                pb::UserMentionMetadata {
                    id: Some(pb::UserId {
                        id: Some("112233445566778899001".to_string()),
                        r#type: Some(pb::UserType::Human as i32),
                    }),
                    r#type: Some(if fmt_code % 2 == 0 {
                        pb::user_mention_metadata::Type::Mention as i32
                    } else {
                        pb::user_mention_metadata::Type::MentionAll as i32
                    }),
                    display_name: Some("Alice Example".to_string()),
                    ..Default::default()
                },
            )),
            2 => Some(pb::annotation::Metadata::UrlMetadata(pb::UrlMetadata {
                url: Some(pb::Url {
                    url: Some("https://example.com/path?a=1&b=2".to_string()),
                }),
                ..Default::default()
            })),
            _ => Some(pb::annotation::Metadata::SlashCommandMetadata(
                pb::SlashCommandMetadata {
                    command_name: Some("/shrug".to_string()),
                    ..Default::default()
                },
            )),
        };
        synth_anns.push(pb::Annotation {
            r#type: Some(pb::AnnotationType::FormatData as i32),
            start_index: Some(start),
            length: Some(length),
            metadata,
            ..Default::default()
        });
    }
    let res = annotations_to_matrix_html(&s, &synth_anns, &[]);
    assert!(std::str::from_utf8(res.body.as_bytes()).is_ok());
    if let Some(html) = res.formatted_body.as_ref() {
        assert!(std::str::from_utf8(html.as_bytes()).is_ok());
    }
    true
}

/// Single-input entrypoint for `cargo fuzz` target `fuzz_cookies`.
pub fn fuzz_cookies_once(data: &[u8]) -> bool {
    let s = String::from_utf8_lossy(data);
    let _ = normalize_user_agent(Some(&s));

    let mut base = BTreeMap::new();
    base.insert("OSID".to_string(), "o1".to_string());
    base.insert("COMPASS".to_string(), "c1".to_string());
    base.insert("SID".to_string(), "s1".to_string());
    base.insert("HSID".to_string(), "h1".to_string());
    base.insert("SSID".to_string(), "ss1".to_string());
    base.insert("SAPISID".to_string(), "sap1".to_string());

    if let Ok(jar) = DomainCookieJar::from_flat_cookie_map(&base) {
        let _ = jar.cookie_header_for_host("chat.google.com");
        let _ = jar.cookie_header_for_host("clients6.google.com");
        let _ = jar.cookie_header_for_host("lh3.googleusercontent.com");
        if let Ok(u) = Url::parse("https://chat.google.com/u/0/api/get_self_user_status?alt=proto")
        {
            let _ = jar.cookie_header_for_url(&u);
        }
    }

    let mut arbitrary = BTreeMap::new();
    let mut scoped = Vec::new();
    for (idx, line) in s.lines().enumerate() {
        if let Some((k, v)) = line.split_once('=') {
            let name = k.trim().to_string();
            let value = v.trim().to_string();
            arbitrary.insert(name.clone(), value.clone());
            scoped.push(ScopedCookie {
                name,
                value,
                domain: if idx % 2 == 0 {
                    "chat.google.com".to_string()
                } else {
                    ".google.com".to_string()
                },
                path: "/".to_string(),
            });
        }
    }
    let _ = DomainCookieJar::from_flat_cookie_map(&arbitrary);
    let _ = DomainCookieJar::from_scoped_cookies(scoped);
    true
}

/// Deterministic Xorshift64 PRNG for bounded, reproducible property/fuzz runs in `cargo test` and Bazel CI.
pub struct Xorshift64(u64);

impl Xorshift64 {
    pub fn new(seed: u64) -> Self {
        Self(seed.max(1))
    }

    pub fn next_u64(&mut self) -> u64 {
        let mut x = self.0;
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        self.0 = x;
        x
    }

    pub fn next_bytes(&mut self, max_len: usize) -> Vec<u8> {
        let len = (self.next_u64() as usize) % (max_len + 1);
        let mut out = Vec::with_capacity(len);
        while out.len() < len {
            let w = self.next_u64().to_le_bytes();
            let take = (len - out.len()).min(8);
            out.extend_from_slice(&w[..take]);
        }
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fuzz_chunk_parser_never_panics_on_adversarial_and_random_inputs() {
        let seeds: &[&[u8]] = &[
            b"",
            b"\n",
            b"0\n",
            b"99999999999999999999999999999999999\n[]",
            b"-1\n[]",
            b"5\n\xF0\x9F\x91\x8B!", // 2 UTF-16 units ("👋") + 1 ("!") = 3 < 5 (partial)
            b"3\n\xF0\x9F\x91\x8B!", // exact 3 UTF-16 units
            b"12\n[[1,[\"noop\"]]]4\n[[]]",
            b"\xFF\xFE\xFD\n[[1]]",
        ];
        for seed in seeds {
            assert!(fuzz_chunk_parser_once(seed));
        }

        let mut rng = Xorshift64::new(0xC001_BEEF_1234_5678);
        for _ in 0..500 {
            let buf = rng.next_bytes(512);
            assert!(fuzz_chunk_parser_once(&buf));
        }
    }

    #[test]
    fn fuzz_pblite_event_never_panics_on_deep_and_malformed_json() {
        let deep_open = "[".repeat(256);
        let deep_close = "]".repeat(256);
        let deep = format!("{deep_open}1{deep_close}");
        let seeds: Vec<&[u8]> = vec![
            b"",
            b")]}'\n",
            b")]}'\n[[[[null,[[1,[\"noop\"]]]]]]]",
            b"[null,1,-99999999999999999999999999,\"NaN\",\"Infinity\",\"-Infinity\",{\"15\":{\"1\":\"x\"}}]",
            b"{\"1\": [1, 2, 3], \"999999\": null}",
            deep.as_bytes(),
        ];
        for seed in seeds {
            assert!(fuzz_pblite_event_once(seed));
        }

        let mut rng = Xorshift64::new(0xDEAD_C0DE_8765_4321);
        for _ in 0..500 {
            let buf = rng.next_bytes(512);
            assert!(fuzz_pblite_event_once(&buf));
        }
    }

    #[test]
    fn fuzz_fmt_annotations_never_splits_surrogate_pairs_or_panics() {
        let seeds = [
            "",
            "Hello 👋🏼🇵🇱👨‍👩‍👧‍👦 *bold* _italic_ ~strike~ `code`",
            "<b>unclosed <i>tags <a href=\"javascript:alert(1)\">click</a> <font color=\"#123456\">c</font>",
            "<pre><code>fn main() { println!(\"<>&\"); }</code></pre>",
            "<blockquote>nested<blockquote>quote</blockquote></blockquote>",
            "<ul><li>item 1</li><li>item 2</li></ul><ol><li>one</li></ol>",
            "@all <a href=\"https://matrix.to/#/@gchat_112233445566778899001:courier.local\">Alice</a>",
        ];
        for seed in seeds {
            assert!(fuzz_fmt_annotations_once(seed.as_bytes()));
        }

        let mut rng = Xorshift64::new(0xFACE_CAFE_1122_3344);
        for _ in 0..500 {
            let buf = rng.next_bytes(256);
            assert!(fuzz_fmt_annotations_once(&buf));
        }
    }

    #[test]
    fn fuzz_cookies_never_panics_on_arbitrary_headers_and_maps() {
        let seeds: &[&[u8]] = &[
            b"",
            b"OSID=deleted; Max-Age=0; Path=/\nCOMPASS=new-compass; Path=/; Secure; HttpOnly",
            b"SID=; Expires=Thu, 01 Jan 1970 00:00:00 GMT\n__Secure-1PSID=sec1; Secure",
            b"===; ; ; Max-Age=-999999999999999999999999999",
        ];
        for seed in seeds {
            assert!(fuzz_cookies_once(seed));
        }

        let mut rng = Xorshift64::new(0xABCD_EF01_2345_6789);
        for _ in 0..500 {
            let buf = rng.next_bytes(256);
            assert!(fuzz_cookies_once(&buf));
        }
    }
}
