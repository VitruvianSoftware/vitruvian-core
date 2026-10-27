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

use std::fmt;

/// Server-OWNED API Explorer endpoint table.
///
/// The frontend (`frontend/utils/apiEndpoints.ts`) advertises these same endpoints
/// for UX, but the server MUST NOT trust the URL the client sends — that is the
/// SSRF hole. Instead `/api/explore` looks the `(provider, endpointId)` pair up in
/// THIS table, which is the single source of truth for what host the server will
/// actually call:
///
/// - `Fixed` — `github`/`google`/`gitlab`/`linkedin`. The full provider API
///   URL is a hardcoded constant here; the client cannot influence the host.
/// - `Issuer` — `auth0`/`zitadel`. Only a relative `path` is fixed here;
///   the host is the user's IdP issuer domain, which the caller MUST validate
///   via `resolve_and_pin` before this URL is fetched.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ExploreEndpointKind {
    Fixed,
    Issuer,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ExploreEndpointDef {
    pub id: &'static str,
    pub method: &'static str,
    pub kind: ExploreEndpointKind,
    pub url: Option<&'static str>,
    pub path: Option<&'static str>,
}

impl ExploreEndpointDef {
    pub const fn fixed(id: &'static str, url: &'static str) -> Self {
        Self {
            id,
            method: "GET",
            kind: ExploreEndpointKind::Fixed,
            url: Some(url),
            path: None,
        }
    }

    pub const fn issuer(id: &'static str, path: &'static str) -> Self {
        Self {
            id,
            method: "GET",
            kind: ExploreEndpointKind::Issuer,
            url: None,
            path: Some(path),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum ExploreProvider {
    Github,
    Google,
    Gitlab,
    Auth0,
    Zitadel,
    Linkedin,
}

impl ExploreProvider {
    pub const ALL: &'static [ExploreProvider] = &[
        ExploreProvider::Github,
        ExploreProvider::Google,
        ExploreProvider::Gitlab,
        ExploreProvider::Auth0,
        ExploreProvider::Zitadel,
        ExploreProvider::Linkedin,
    ];

    pub const fn as_str(&self) -> &'static str {
        match self {
            ExploreProvider::Github => "github",
            ExploreProvider::Google => "google",
            ExploreProvider::Gitlab => "gitlab",
            ExploreProvider::Auth0 => "auth0",
            ExploreProvider::Zitadel => "zitadel",
            ExploreProvider::Linkedin => "linkedin",
        }
    }

    pub fn parse(s: &str) -> Option<Self> {
        match s {
            "github" => Some(ExploreProvider::Github),
            "google" => Some(ExploreProvider::Google),
            "gitlab" => Some(ExploreProvider::Gitlab),
            "auth0" => Some(ExploreProvider::Auth0),
            "zitadel" => Some(ExploreProvider::Zitadel),
            "linkedin" => Some(ExploreProvider::Linkedin),
            _ => None,
        }
    }
}

const GITHUB_ENDPOINTS: &[ExploreEndpointDef] = &[
    ExploreEndpointDef::fixed("user", "https://api.github.com/user"),
    ExploreEndpointDef::fixed("user_emails", "https://api.github.com/user/emails"),
    ExploreEndpointDef::fixed("user_repos", "https://api.github.com/user/repos"),
    ExploreEndpointDef::fixed("user_orgs", "https://api.github.com/user/orgs"),
    ExploreEndpointDef::fixed("user_followers", "https://api.github.com/user/followers"),
    ExploreEndpointDef::fixed("user_following", "https://api.github.com/user/following"),
];

const GOOGLE_ENDPOINTS: &[ExploreEndpointDef] = &[
    ExploreEndpointDef::fixed("userinfo", "https://www.googleapis.com/oauth2/v1/userinfo"),
    ExploreEndpointDef::fixed(
        "userinfo_v2",
        "https://www.googleapis.com/oauth2/v2/userinfo",
    ),
    ExploreEndpointDef::fixed(
        "people_me",
        "https://people.googleapis.com/v1/people/me?personFields=names,emailAddresses,photos,urls,organizations",
    ),
    ExploreEndpointDef::fixed(
        "gmail_profile",
        "https://gmail.googleapis.com/gmail/v1/users/me/profile",
    ),
];

const GITLAB_ENDPOINTS: &[ExploreEndpointDef] = &[
    ExploreEndpointDef::fixed("user", "https://gitlab.com/api/v4/user"),
    ExploreEndpointDef::fixed(
        "user_projects",
        "https://gitlab.com/api/v4/projects?membership=true",
    ),
    ExploreEndpointDef::fixed(
        "user_groups",
        "https://gitlab.com/api/v4/groups?min_access_level=10",
    ),
    ExploreEndpointDef::fixed("user_keys", "https://gitlab.com/api/v4/user/keys"),
];

const AUTH0_ENDPOINTS: &[ExploreEndpointDef] =
    &[ExploreEndpointDef::issuer("userinfo", "/userinfo")];

const ZITADEL_ENDPOINTS: &[ExploreEndpointDef] =
    &[ExploreEndpointDef::issuer("userinfo", "/oidc/v1/userinfo")];

const LINKEDIN_ENDPOINTS: &[ExploreEndpointDef] = &[ExploreEndpointDef::fixed(
    "userinfo",
    "https://api.linkedin.com/v2/userinfo",
)];

pub const EXPLORE_ENDPOINTS: &[(ExploreProvider, &'static [ExploreEndpointDef])] = &[
    (ExploreProvider::Github, GITHUB_ENDPOINTS),
    (ExploreProvider::Google, GOOGLE_ENDPOINTS),
    (ExploreProvider::Gitlab, GITLAB_ENDPOINTS),
    (ExploreProvider::Auth0, AUTH0_ENDPOINTS),
    (ExploreProvider::Zitadel, ZITADEL_ENDPOINTS),
    (ExploreProvider::Linkedin, LINKEDIN_ENDPOINTS),
];

pub fn endpoints_for_provider(provider: ExploreProvider) -> &'static [ExploreEndpointDef] {
    for (p, defs) in EXPLORE_ENDPOINTS {
        if *p == provider {
            return defs;
        }
    }
    &[]
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UnknownExploreEndpointError {
    pub message: String,
}

impl UnknownExploreEndpointError {
    pub fn new(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
        }
    }
}

impl fmt::Display for UnknownExploreEndpointError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.message)
    }
}

impl std::error::Error for UnknownExploreEndpointError {}

/// Resolve a `(provider, endpoint_id)` — and, for issuer providers, the validated
/// `issuer_domain` — to the ABSOLUTE URL the server will fetch.
///
/// Throws `UnknownExploreEndpointError` for any provider/endpointId not in the
/// table, or for an issuer endpoint called without an `issuer_domain`.
pub fn resolve_explore_target(
    provider: &str,
    endpoint_id: &str,
    issuer_domain: Option<&str>,
) -> Result<String, UnknownExploreEndpointError> {
    let Some(prov) = ExploreProvider::parse(provider) else {
        return Err(UnknownExploreEndpointError::new(format!(
            "unknown provider: {provider}"
        )));
    };
    let list = endpoints_for_provider(prov);
    let Some(def) = list.iter().find(|d| d.id == endpoint_id) else {
        return Err(UnknownExploreEndpointError::new(format!(
            "unknown endpoint '{endpoint_id}' for provider '{provider}'"
        )));
    };

    match def.kind {
        ExploreEndpointKind::Fixed => {
            let Some(url) = def.url else {
                return Err(UnknownExploreEndpointError::new(format!(
                    "endpoint '{endpoint_id}' for provider '{provider}' has no url"
                )));
            };
            Ok(url.to_string())
        }
        ExploreEndpointKind::Issuer => {
            let Some(domain) = issuer_domain.filter(|s| !s.is_empty()) else {
                return Err(UnknownExploreEndpointError::new(format!(
                    "issuer domain required for provider '{provider}'"
                )));
            };
            let Some(path) = def.path else {
                return Err(UnknownExploreEndpointError::new(format!(
                    "endpoint '{endpoint_id}' for provider '{provider}' has no path"
                )));
            };
            Ok(format!("https://{domain}{path}"))
        }
    }
}
