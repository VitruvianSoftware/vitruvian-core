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

/// Pure OAuth callback session resolution helper.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OAuthSessionInputs {
    pub url_provider: Option<String>,
    pub saved_provider: Option<String>,
    pub pkce_code_verifier: Option<String>,
    pub explicit_redirect_uri: Option<String>,
    pub saved_redirect_uri: Option<String>,
    pub origin: String,
    pub saved_client_id: Option<String>,
    pub saved_client_secret: Option<String>,
    pub saved_zitadel_domain: Option<String>,
    pub returned_state: Option<String>,
    pub expected_state: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ResolvedOAuthSession {
    pub provider: Option<String>,
    pub code_verifier: Option<String>,
    pub redirect_uri: String,
    pub client_id: Option<String>,
    pub client_secret: Option<String>,
    pub zitadel_domain: Option<String>,
    pub state_valid: bool,
}

fn non_empty(opt: Option<String>) -> Option<String> {
    opt.filter(|s| !s.is_empty())
}

pub fn resolve_oauth_session(inputs: OAuthSessionInputs) -> ResolvedOAuthSession {
    let provider = non_empty(inputs.url_provider).or_else(|| non_empty(inputs.saved_provider));
    let code_verifier = non_empty(inputs.pkce_code_verifier);
    let redirect_uri = non_empty(inputs.explicit_redirect_uri)
        .or_else(|| non_empty(inputs.saved_redirect_uri))
        .unwrap_or(inputs.origin);
    let client_id = non_empty(inputs.saved_client_id);
    let client_secret = non_empty(inputs.saved_client_secret);
    let zitadel_domain = non_empty(inputs.saved_zitadel_domain);

    let expected = non_empty(inputs.expected_state);
    let returned = non_empty(inputs.returned_state);

    let state_valid = match expected {
        None => true,
        Some(exp) => returned.as_deref() == Some(exp.as_str()),
    };

    ResolvedOAuthSession {
        provider,
        code_verifier,
        redirect_uri,
        client_id,
        client_secret,
        zitadel_domain,
        state_valid,
    }
}
