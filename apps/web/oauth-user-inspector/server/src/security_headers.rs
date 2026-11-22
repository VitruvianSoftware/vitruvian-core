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

/// Content-Security-Policy for the OAuth User Inspector SPA.
///
/// The design system's stylesheet (`frontend/design-system/tokens.css`) loads
/// IBM Plex Sans and JetBrains Mono from Google Fonts: the stylesheet comes
/// from fonts.googleapis.com and the font files from fonts.gstatic.com. Both
/// hosts are allowed here, and nothing else is. Without them the browser
/// blocks the fonts and the site falls back to system fonts. The
/// `csp_allows_every_stylesheet_import` test fails if the stylesheet imports
/// from a host this policy does not allow.
pub const CONTENT_SECURITY_POLICY: &str = "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; img-src 'self' https: data:; font-src 'self' https://fonts.gstatic.com; connect-src 'self' https:; frame-ancestors 'none'; base-uri 'self'; form-action 'self'; object-src 'none'";

pub const STRICT_TRANSPORT_SECURITY: &str = "max-age=31536000; includeSubDomains";
pub const X_CONTENT_TYPE_OPTIONS: &str = "nosniff";
pub const REFERRER_POLICY: &str = "no-referrer";
pub const X_FRAME_OPTIONS: &str = "DENY";
pub const CROSS_ORIGIN_OPENER_POLICY: &str = "same-origin";

/// Return the canonical set of baseline HTTP security headers.
pub fn default_security_headers() -> Vec<(String, String)> {
    vec![
        (
            "Content-Security-Policy".to_string(),
            CONTENT_SECURITY_POLICY.to_string(),
        ),
        (
            "Strict-Transport-Security".to_string(),
            STRICT_TRANSPORT_SECURITY.to_string(),
        ),
        (
            "X-Content-Type-Options".to_string(),
            X_CONTENT_TYPE_OPTIONS.to_string(),
        ),
        ("Referrer-Policy".to_string(), REFERRER_POLICY.to_string()),
        ("X-Frame-Options".to_string(), X_FRAME_OPTIONS.to_string()),
        (
            "Cross-Origin-Opener-Policy".to_string(),
            CROSS_ORIGIN_OPENER_POLICY.to_string(),
        ),
    ]
}
