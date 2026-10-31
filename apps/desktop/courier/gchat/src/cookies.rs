// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-only

use crate::GChatError;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use url::Url;

pub const DEFAULT_MACOS_SAFARI_UA: &str =
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3 Safari/605.1.15";

pub const REQUIRED_CHAT_COOKIES: &[&str] = &["COMPASS", "OSID"];
pub const REQUIRED_GOOGLE_COOKIES: &[&str] = &["SID", "HSID", "SSID"];
pub const OPTIONAL_GOOGLE_COOKIES: &[&str] =
    &["APISID", "SAPISID", "__Secure-1PSID", "__Secure-3PSID"];

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct ScopedCookie {
    pub name: String,
    pub value: String,
    pub domain: String,
    #[serde(default = "default_cookie_path")]
    pub path: String,
}

fn default_cookie_path() -> String {
    "/".to_string()
}

fn normalize_domain(domain: &str) -> String {
    domain.trim().trim_start_matches('.').to_ascii_lowercase()
}

fn clean_cookie_value(raw: &str) -> String {
    let trimmed = raw.trim();
    if trimmed.len() >= 2
        && ((trimmed.starts_with('"') && trimmed.ends_with('"'))
            || (trimmed.starts_with('\'') && trimmed.ends_with('\'')))
    {
        trimmed[1..trimmed.len() - 1].trim().to_string()
    } else {
        trimmed.to_string()
    }
}

fn has_invalid_cookie_chars(s: &str) -> bool {
    s.chars()
        .any(|c| c == ';' || (c as u32) < 0x20 || (c as u32) == 0x7f)
}

#[derive(Clone, Debug)]
pub struct DomainCookieJar {
    cookies: Vec<ScopedCookie>,
    #[cfg(any(test, feature = "test-loopback"))]
    allow_loopback_for_test: bool,
}

impl DomainCookieJar {
    pub fn from_scoped_cookies(cookies: Vec<ScopedCookie>) -> Result<Self, GChatError> {
        let mut normalized = Vec::with_capacity(cookies.len());
        for c in cookies {
            let name = c.name.trim().to_string();
            let value = clean_cookie_value(&c.value);
            let domain = normalize_domain(&c.domain);
            if name.is_empty() || value.is_empty() {
                continue;
            }
            if has_invalid_cookie_chars(&name) || has_invalid_cookie_chars(&value) {
                return Err(GChatError::CookieValidation(format!(
                    "cookie {name} contains invalid control or separator characters"
                )));
            }
            if domain != "chat.google.com" && domain != "google.com" {
                continue;
            }
            let path = if c.path.trim().is_empty() {
                "/".to_string()
            } else {
                c.path.trim().to_string()
            };
            if let Some(existing) = normalized.iter_mut().find(|existing: &&mut ScopedCookie| {
                existing.name == name && existing.domain == domain
            }) {
                existing.value = value;
                existing.path = path;
            } else {
                normalized.push(ScopedCookie {
                    name,
                    value,
                    domain,
                    path,
                });
            }
        }

        let mut missing = Vec::new();
        for &req_chat in REQUIRED_CHAT_COOKIES {
            let found = normalized.iter().any(|c| {
                c.name == req_chat && c.domain == "chat.google.com" && !c.value.is_empty()
            });
            if !found {
                missing.push(format!("{req_chat} (chat.google.com)"));
            }
        }
        for &req_google in REQUIRED_GOOGLE_COOKIES {
            let found = normalized
                .iter()
                .any(|c| c.name == req_google && c.domain == "google.com" && !c.value.is_empty());
            if !found {
                missing.push(format!("{req_google} (.google.com)"));
            }
        }

        if !missing.is_empty() {
            return Err(GChatError::CookieValidation(format!(
                "missing required cookies: {}",
                missing.join(", ")
            )));
        }

        Ok(Self {
            cookies: normalized,
            #[cfg(any(test, feature = "test-loopback"))]
            allow_loopback_for_test: false,
        })
    }

    pub fn from_flat_cookie_map(map: &BTreeMap<String, String>) -> Result<Self, GChatError> {
        let mut scoped = Vec::with_capacity(map.len());
        for (name, value) in map {
            let domain = if REQUIRED_CHAT_COOKIES.contains(&name.as_str()) {
                "chat.google.com"
            } else {
                ".google.com"
            };
            scoped.push(ScopedCookie {
                name: name.clone(),
                value: value.clone(),
                domain: domain.to_string(),
                path: "/".to_string(),
            });
        }
        Self::from_scoped_cookies(scoped)
    }

    #[cfg(any(test, feature = "test-loopback"))]
    pub fn with_loopback_for_test(mut self, allow: bool) -> Self {
        self.allow_loopback_for_test = allow;
        self
    }

    pub fn cookie_header_for_host(&self, raw_host: &str) -> Option<String> {
        let host = raw_host
            .trim_matches(|c| c == '[' || c == ']')
            .to_ascii_lowercase();
        if host == "googleusercontent.com"
            || host.ends_with(".googleusercontent.com")
            || host == "ggpht.com"
            || host.ends_with(".ggpht.com")
        {
            return None;
        }
        let is_chat_host = host == "chat.google.com";
        let is_google_host = host == "google.com" || host.ends_with(".google.com");
        if !is_chat_host && !is_google_host {
            return None;
        }

        let mut pairs = Vec::new();
        for c in &self.cookies {
            if c.domain == "chat.google.com" && is_chat_host {
                pairs.push(format!("{}={}", c.name, c.value));
            } else if c.domain == "google.com" && is_google_host {
                pairs.push(format!("{}={}", c.name, c.value));
            }
        }
        if pairs.is_empty() {
            None
        } else {
            Some(pairs.join("; "))
        }
    }

    pub fn cookie_header_for_url(&self, url: &Url) -> Option<String> {
        if url.scheme() != "https" {
            return None;
        }
        self.cookie_header_for_host(url.host_str()?)
    }

    pub(crate) fn cookie_header_for_request(&self, url: &Url) -> Option<String> {
        if let Some(h) = self.cookie_header_for_url(url) {
            return Some(h);
        }
        #[cfg(any(test, feature = "test-loopback"))]
        if self.allow_loopback_for_test && (url.scheme() == "https" || url.scheme() == "http") {
            let host = url.host_str()?;
            if host == "127.0.0.1" || host == "localhost" || host == "::1" {
                return self.cookie_header_for_host("chat.google.com");
            }
            return self.cookie_header_for_host(host);
        }
        None
    }

    pub fn cookies(&self) -> &[ScopedCookie] {
        &self.cookies
    }
}

pub fn normalize_user_agent(raw: Option<&str>) -> String {
    let Some(s) = raw else {
        return DEFAULT_MACOS_SAFARI_UA.to_string();
    };
    let trimmed = s.trim();
    if trimmed.is_empty() || trimmed.len() > 512 {
        return DEFAULT_MACOS_SAFARI_UA.to_string();
    }
    if trimmed
        .chars()
        .any(|c| (c as u32) < 0x20 || (c as u32) == 0x7f)
    {
        return DEFAULT_MACOS_SAFARI_UA.to_string();
    }
    trimmed.to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn five_required_cookies() -> Vec<ScopedCookie> {
        vec![
            ScopedCookie {
                name: "COMPASS".to_string(),
                value: "dynamite-ui=compass+val%2B/=".to_string(),
                domain: "chat.google.com".to_string(),
                path: "/".to_string(),
            },
            ScopedCookie {
                name: "OSID".to_string(),
                value: "osid+val%2B/=".to_string(),
                domain: "chat.google.com".to_string(),
                path: "/".to_string(),
            },
            ScopedCookie {
                name: "SID".to_string(),
                value: "sid+val%2B/=".to_string(),
                domain: ".google.com".to_string(),
                path: "/".to_string(),
            },
            ScopedCookie {
                name: "HSID".to_string(),
                value: "hsid_val".to_string(),
                domain: ".google.com".to_string(),
                path: "/".to_string(),
            },
            ScopedCookie {
                name: "SSID".to_string(),
                value: "ssid_val".to_string(),
                domain: ".google.com".to_string(),
                path: "/".to_string(),
            },
        ]
    }

    #[test]
    fn test_cookie_jar_validates_required_five_cookies_and_scopes_by_host() {
        for missing_idx in 0..5 {
            let mut subset = five_required_cookies();
            subset.remove(missing_idx);
            assert!(
                DomainCookieJar::from_scoped_cookies(subset).is_err(),
                "expected error when missing required cookie at index {missing_idx}"
            );
        }

        let mut wrong_scope = five_required_cookies();
        wrong_scope[0].domain = ".google.com".to_string();
        assert!(
            DomainCookieJar::from_scoped_cookies(wrong_scope).is_err(),
            "COMPASS on .google.com instead of chat.google.com must be rejected"
        );

        let mut with_optional = five_required_cookies();
        for name in ["APISID", "SAPISID", "__Secure-1PSID", "__Secure-3PSID"] {
            with_optional.push(ScopedCookie {
                name: name.to_string(),
                value: format!("{name}_val"),
                domain: ".google.com".to_string(),
                path: "/".to_string(),
            });
        }
        let jar = DomainCookieJar::from_scoped_cookies(with_optional)
            .expect("valid five required + optional cookies");

        let chat_url =
            Url::parse("https://chat.google.com/u/0/api/get_self_user_status?alt=proto").unwrap();
        let header = jar
            .cookie_header_for_url(&chat_url)
            .expect("chat.google.com must receive cookies");
        for expected in [
            "COMPASS=dynamite-ui=compass+val%2B/=",
            "OSID=osid+val%2B/=",
            "SID=sid+val%2B/=",
            "HSID=hsid_val",
            "SSID=ssid_val",
            "APISID=APISID_val",
            "SAPISID=SAPISID_val",
            "__Secure-1PSID=__Secure-1PSID_val",
            "__Secure-3PSID=__Secure-3PSID_val",
        ] {
            assert!(
                header.contains(expected),
                "expected cookie {expected} in header: {header}"
            );
        }

        let google_url = Url::parse("https://clients6.google.com/upload/").unwrap();
        let google_header = jar
            .cookie_header_for_url(&google_url)
            .expect("*.google.com must receive google.com cookies");
        assert!(!google_header.contains("COMPASS="));
        assert!(!google_header.contains("OSID="));
        assert!(google_header.contains("SID=sid+val%2B/="));

        let guc_url = Url::parse("https://lh3.googleusercontent.com/a/avatar").unwrap();
        assert_eq!(jar.cookie_header_for_url(&guc_url), None);

        let loopback_url = Url::parse("http://127.0.0.1:8080/u/0/mole/world").unwrap();
        assert_eq!(
            jar.cookie_header_for_request(&loopback_url),
            None,
            "default DomainCookieJar must never attach cookies to loopback"
        );
    }

    #[test]
    fn test_normalize_user_agent_rejects_control_chars_and_defaults_to_safari() {
        assert_eq!(normalize_user_agent(None), DEFAULT_MACOS_SAFARI_UA);
        assert_eq!(normalize_user_agent(Some("")), DEFAULT_MACOS_SAFARI_UA);
        assert_eq!(normalize_user_agent(Some("   ")), DEFAULT_MACOS_SAFARI_UA);
        assert_eq!(
            normalize_user_agent(Some("Mozilla/5.0\r\nX-Injected: pwn")),
            DEFAULT_MACOS_SAFARI_UA
        );
        assert_eq!(
            normalize_user_agent(Some("Mozilla/5.0\0bad")),
            DEFAULT_MACOS_SAFARI_UA
        );
        let too_long = "A".repeat(513);
        assert_eq!(
            normalize_user_agent(Some(&too_long)),
            DEFAULT_MACOS_SAFARI_UA
        );
        let custom = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_4) CustomSafari/605.1.15";
        assert_eq!(normalize_user_agent(Some(custom)), custom);
    }
}
