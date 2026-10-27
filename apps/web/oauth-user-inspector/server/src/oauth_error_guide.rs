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

use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::HashMap;

/// OAuth Error Code Detection and Troubleshooting Guide.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct OAuthErrorGuide {
    #[serde(rename = "errorCode")]
    pub error_code: String,
    pub title: String,
    pub description: String,
    pub troubleshooting: Vec<String>,
    #[serde(rename = "commonCauses")]
    pub common_causes: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct EnhancedOAuthError {
    pub error: String,
    #[serde(rename = "errorCode", skip_serializing_if = "Option::is_none")]
    pub error_code: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub guide: Option<OAuthErrorGuide>,
}

fn build_guides() -> Vec<OAuthErrorGuide> {
    vec![
        OAuthErrorGuide {
            error_code: "invalid_scope".to_string(),
            title: "Invalid Scope".to_string(),
            description: "The requested scope is invalid, unknown, or malformed.".to_string(),
            troubleshooting: vec![
                "Check that all requested scopes are supported by the OAuth provider".to_string(),
                "Verify scope names are spelled correctly (case-sensitive)".to_string(),
                "Remove any unsupported or deprecated scopes from your request".to_string(),
                "Consult the provider's documentation for valid scope values".to_string(),
            ],
            common_causes: vec![
                "Typo in scope name".to_string(),
                "Using deprecated or removed scopes".to_string(),
                "Requesting scopes not available to your application type".to_string(),
                "Mixing scopes from different OAuth versions".to_string(),
            ],
        },
        OAuthErrorGuide {
            error_code: "unauthorized_client".to_string(),
            title: "Unauthorized Client".to_string(),
            description:
                "The client is not authorized to request an access token using this method."
                    .to_string(),
            troubleshooting: vec![
                "Verify your Client ID and Client Secret are correct".to_string(),
                "Check that your application is properly registered with the OAuth provider"
                    .to_string(),
                "Ensure your redirect URI matches exactly what's registered".to_string(),
                "Confirm your application type supports the requested grant type".to_string(),
                "Check if your application needs approval from the OAuth provider".to_string(),
            ],
            common_causes: vec![
                "Incorrect Client ID or Client Secret".to_string(),
                "Application not approved or verified".to_string(),
                "Redirect URI mismatch".to_string(),
                "Using wrong grant type for application".to_string(),
                "Application suspended or disabled".to_string(),
            ],
        },
        OAuthErrorGuide {
            error_code: "access_denied".to_string(),
            title: "Access Denied".to_string(),
            description: "The resource owner or authorization server denied the request."
                .to_string(),
            troubleshooting: vec![
                "User may have clicked 'Cancel' or 'Deny' during authorization".to_string(),
                "Try the authorization flow again".to_string(),
                "Ensure you're requesting appropriate permissions for your use case".to_string(),
                "Check if the user account has sufficient privileges".to_string(),
                "Verify the application is approved for the requested scopes".to_string(),
            ],
            common_causes: vec![
                "User denied authorization".to_string(),
                "Requesting excessive permissions".to_string(),
                "User account restrictions".to_string(),
                "Application not trusted by user".to_string(),
                "Organizational policies blocking access".to_string(),
            ],
        },
        OAuthErrorGuide {
            error_code: "invalid_client".to_string(),
            title: "Invalid Client".to_string(),
            description: "Client authentication failed or client credentials are invalid."
                .to_string(),
            troubleshooting: vec![
                "Double-check your Client ID and Client Secret".to_string(),
                "Ensure credentials are not expired or revoked".to_string(),
                "Verify you're using the correct authentication method".to_string(),
                "Check if your application needs to be re-registered".to_string(),
                "Confirm your application is active and not suspended".to_string(),
            ],
            common_causes: vec![
                "Wrong Client ID or Client Secret".to_string(),
                "Expired client credentials".to_string(),
                "Application deleted or suspended".to_string(),
                "Incorrect authentication method".to_string(),
                "Client credentials leaked and revoked".to_string(),
            ],
        },
        OAuthErrorGuide {
            error_code: "invalid_grant".to_string(),
            title: "Invalid Grant".to_string(),
            description: "The provided authorization grant is invalid, expired, or revoked."
                .to_string(),
            troubleshooting: vec![
                "Authorization code may have expired (typically valid for 10 minutes)".to_string(),
                "Code may have already been used (codes are single-use)".to_string(),
                "Verify the redirect URI matches the one used in authorization".to_string(),
                "Check that the authorization code wasn't tampered with".to_string(),
                "Ensure system clocks are synchronized".to_string(),
            ],
            common_causes: vec![
                "Authorization code expired".to_string(),
                "Code already exchanged for token".to_string(),
                "Redirect URI mismatch".to_string(),
                "Clock skew between systems".to_string(),
                "Code parameter modified or corrupted".to_string(),
            ],
        },
        OAuthErrorGuide {
            error_code: "invalid_request".to_string(),
            title: "Invalid Request".to_string(),
            description:
                "The request is missing a required parameter, includes invalid values, or is malformed."
                    .to_string(),
            troubleshooting: vec![
                "Check that all required parameters are included".to_string(),
                "Verify parameter names and values are correct".to_string(),
                "Ensure proper encoding of special characters".to_string(),
                "Review the OAuth provider's API documentation".to_string(),
                "Check request content-type and format".to_string(),
            ],
            common_causes: vec![
                "Missing required parameters".to_string(),
                "Malformed parameter values".to_string(),
                "Incorrect content-type header".to_string(),
                "URL encoding issues".to_string(),
                "Using wrong parameter names".to_string(),
            ],
        },
        OAuthErrorGuide {
            error_code: "server_error".to_string(),
            title: "Server Error".to_string(),
            description: "The authorization server encountered an unexpected condition."
                .to_string(),
            troubleshooting: vec![
                "Wait a few minutes and retry the request".to_string(),
                "Check the OAuth provider's status page for outages".to_string(),
                "Verify your request is not malformed".to_string(),
                "Contact the OAuth provider if issue persists".to_string(),
                "Implement exponential backoff for retries".to_string(),
            ],
            common_causes: vec![
                "Temporary server overload".to_string(),
                "OAuth provider infrastructure issues".to_string(),
                "Database connectivity problems".to_string(),
                "Rate limiting on provider side".to_string(),
                "Maintenance windows".to_string(),
            ],
        },
        OAuthErrorGuide {
            error_code: "temporarily_unavailable".to_string(),
            title: "Temporarily Unavailable".to_string(),
            description:
                "The authorization server is currently unable to handle the request due to temporary overloading."
                    .to_string(),
            troubleshooting: vec![
                "Wait and retry after a brief delay".to_string(),
                "Implement exponential backoff strategy".to_string(),
                "Check if you're hitting rate limits".to_string(),
                "Monitor OAuth provider status pages".to_string(),
                "Consider caching tokens to reduce requests".to_string(),
            ],
            common_causes: vec![
                "Rate limiting exceeded".to_string(),
                "Server overload".to_string(),
                "Temporary maintenance".to_string(),
                "Traffic spikes".to_string(),
                "Resource exhaustion".to_string(),
            ],
        },
    ]
}

fn percent_decode(s: &str) -> String {
    let bytes = s.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'+' {
            out.push(b' ');
            i += 1;
        } else if bytes[i] == b'%' && i + 2 < bytes.len() {
            if let Ok(hex) = std::str::from_utf8(&bytes[i + 1..i + 3]) {
                if let Ok(val) = u8::from_str_radix(hex, 16) {
                    out.push(val);
                    i += 3;
                    continue;
                }
            }
            out.push(bytes[i]);
            i += 1;
        } else {
            out.push(bytes[i]);
            i += 1;
        }
    }
    String::from_utf8_lossy(&out).to_string()
}

fn parse_query_params(input: &str) -> HashMap<String, String> {
    let mut map = HashMap::new();
    for part in input.split('&') {
        if let Some((k, v)) = part.split_once('=') {
            map.insert(percent_decode(k), percent_decode(v));
        }
    }
    map
}

/// Detects OAuth error codes from error responses and provides troubleshooting guidance.
pub fn enhance_oauth_error(
    error_text: &str,
    _response_status: Option<u16>,
    _provider: Option<&str>,
) -> EnhancedOAuthError {
    let (error_code, error_description) = match serde_json::from_str::<Value>(error_text) {
        Ok(Value::Object(map)) => {
            let code = map
                .get("error")
                .and_then(Value::as_str)
                .or_else(|| map.get("error_code").and_then(Value::as_str))
                .or_else(|| map.get("code").and_then(Value::as_str))
                .unwrap_or("")
                .to_string();
            let desc = map
                .get("error_description")
                .and_then(Value::as_str)
                .or_else(|| map.get("message").and_then(Value::as_str))
                .or_else(|| map.get("description").and_then(Value::as_str))
                .unwrap_or(error_text)
                .to_string();
            (code, desc)
        }
        Ok(Value::String(s)) => (s.clone(), s),
        _ => {
            let params = parse_query_params(error_text);
            let err_field = params
                .get("error")
                .cloned()
                .or_else(|| params.get("error_description").cloned())
                .unwrap_or_else(|| error_text.to_string());
            let desc_field = params
                .get("error_description")
                .cloned()
                .unwrap_or_else(|| error_text.to_string());
            (err_field, desc_field)
        }
    };

    let guides = build_guides();
    let lower_code = error_code.to_ascii_lowercase();
    let guide = guides.into_iter().find(|g| g.error_code == lower_code);

    let error_msg = if !error_description.is_empty() {
        error_description
    } else if !error_code.is_empty() {
        format!("OAuth error: {error_code}")
    } else {
        "Authentication failed".to_string()
    };

    EnhancedOAuthError {
        error: error_msg,
        error_code: if error_code.is_empty() {
            None
        } else {
            Some(error_code)
        },
        guide,
    }
}

/// Checks if an error response indicates a known OAuth error pattern.
pub fn is_known_oauth_error(error_code: &str) -> bool {
    if error_code.is_empty() {
        return false;
    }
    let lower = error_code.to_ascii_lowercase();
    build_guides().iter().any(|g| g.error_code == lower)
}

/// Gets all available error guides (useful for documentation or testing).
pub fn get_all_error_guides() -> HashMap<String, OAuthErrorGuide> {
    build_guides()
        .into_iter()
        .map(|g| (g.error_code.clone(), g))
        .collect()
}
