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

use serde_json::json;
use std::collections::HashMap;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum UserinfoFetchMode {
    Direct,
    Proxy,
}

impl UserinfoFetchMode {
    pub const fn as_str(&self) -> &'static str {
        match self {
            UserinfoFetchMode::Direct => "direct",
            UserinfoFetchMode::Proxy => "proxy",
        }
    }
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct UserinfoRequestOptions {
    pub auth0_domain: Option<String>,
    pub zitadel_domain: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UserinfoRequestInit {
    pub method: Option<String>,
    pub headers: HashMap<String, String>,
    pub body: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UserinfoRequest {
    pub url: String,
    pub init: UserinfoRequestInit,
    pub mode: UserinfoFetchMode,
}

/// Decide HOW the browser fetches a provider's OIDC/userinfo profile after login.
///
/// LinkedIn (`api.linkedin.com`) sends NO `Access-Control-Allow-Origin` header,
/// so a direct cross-origin browser fetch is rejected by the browser. LinkedIn's
/// userinfo MUST be routed through `/api/explore` (`mode: Proxy`).
pub fn build_userinfo_request(
    provider: &str,
    token: &str,
    opts: &UserinfoRequestOptions,
) -> Result<UserinfoRequest, String> {
    let auth = format!("Bearer {token}");
    match provider {
        "github" => {
            let mut headers = HashMap::new();
            headers.insert("Authorization".to_string(), auth);
            headers.insert("X-GitHub-Api-Version".to_string(), "2022-11-28".to_string());
            Ok(UserinfoRequest {
                url: "https://api.github.com/user".to_string(),
                init: UserinfoRequestInit {
                    method: None,
                    headers,
                    body: None,
                },
                mode: UserinfoFetchMode::Direct,
            })
        }
        "google" => {
            let mut headers = HashMap::new();
            headers.insert("Authorization".to_string(), auth);
            Ok(UserinfoRequest {
                url: "https://www.googleapis.com/oauth2/v1/userinfo?alt=json".to_string(),
                init: UserinfoRequestInit {
                    method: None,
                    headers,
                    body: None,
                },
                mode: UserinfoFetchMode::Direct,
            })
        }
        "gitlab" => {
            let mut headers = HashMap::new();
            headers.insert("Authorization".to_string(), auth);
            Ok(UserinfoRequest {
                url: "https://gitlab.com/api/v4/user".to_string(),
                init: UserinfoRequestInit {
                    method: None,
                    headers,
                    body: None,
                },
                mode: UserinfoFetchMode::Direct,
            })
        }
        "auth0" => {
            let Some(domain) = opts.auth0_domain.as_deref().filter(|s| !s.is_empty()) else {
                return Err(
                    "Auth0 domain not found. Please log in again with your Auth0 domain."
                        .to_string(),
                );
            };
            let mut headers = HashMap::new();
            headers.insert("Authorization".to_string(), auth);
            Ok(UserinfoRequest {
                url: format!("https://{domain}/userinfo"),
                init: UserinfoRequestInit {
                    method: None,
                    headers,
                    body: None,
                },
                mode: UserinfoFetchMode::Direct,
            })
        }
        "zitadel" => {
            let Some(domain) = opts.zitadel_domain.as_deref().filter(|s| !s.is_empty()) else {
                return Err(
                    "Zitadel domain not found. Please log in again with your Zitadel domain."
                        .to_string(),
                );
            };
            let mut headers = HashMap::new();
            headers.insert("Authorization".to_string(), auth);
            Ok(UserinfoRequest {
                url: format!("https://{domain}/oidc/v1/userinfo"),
                init: UserinfoRequestInit {
                    method: None,
                    headers,
                    body: None,
                },
                mode: UserinfoFetchMode::Direct,
            })
        }
        "linkedin" => {
            let mut headers = HashMap::new();
            headers.insert("Content-Type".to_string(), "application/json".to_string());
            let body = json!({
                "provider": "linkedin",
                "accessToken": token,
                "endpoint": { "id": "userinfo", "method": "GET" },
            })
            .to_string();
            Ok(UserinfoRequest {
                url: "/api/explore".to_string(),
                init: UserinfoRequestInit {
                    method: Some("POST".to_string()),
                    headers,
                    body: Some(body),
                },
                mode: UserinfoFetchMode::Proxy,
            })
        }
        other => Err(format!("Unsupported provider: {other}")),
    }
}
