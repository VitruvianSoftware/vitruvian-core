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

//! HTML page for `GET /pair?code=NNNNNN` (the page a pairing QR code opens).

use crate::http_util::{url_encode, HttpRequest, HttpResponse};

/// Validates a 6-digit pairing code (`^[0-9]{6}$`).
pub fn is_valid_pair_code(code: &str) -> bool {
    code.len() == 6 && code.bytes().all(|b| b.is_ascii_digit())
}

/// Validates `host[:port]` (`^[A-Za-z0-9.-]{1,253}(:[0-9]{1,5})?$`).
pub fn is_valid_pair_host(host: &str) -> bool {
    let (h, p) = match host.rsplit_once(':') {
        Some((h_part, p_part)) => (h_part, Some(p_part)),
        None => (host, None),
    };
    if h.is_empty() || h.len() > 253 {
        return false;
    }
    if !h
        .bytes()
        .all(|b| b.is_ascii_alphanumeric() || b == b'.' || b == b'-')
    {
        return false;
    }
    if let Some(port) = p {
        if port.is_empty() || port.len() > 5 || !port.bytes().all(|b| b.is_ascii_digit()) {
            return false;
        }
    }
    true
}

/// `pair_app_link` is the `vitruvian-remote://pair` link the phone app parses.
/// Keys are sorted alphabetically (`code`, `name`, `url`) to match Go's `url.Values.Encode`.
pub fn pair_app_link(host: &str, code: &str, name: &str) -> String {
    let mut parts = Vec::with_capacity(3);
    parts.push(format!("code={}", url_encode(code)));
    if !name.is_empty() {
        parts.push(format!("name={}", url_encode(name)));
    }
    let full_url = format!("http://{host}");
    parts.push(format!("url={}", url_encode(&full_url)));
    format!("vitruvian-remote://pair?{}", parts.join("&"))
}

/// `pair_intent_link` turns the custom-scheme link into a Chrome `intent://` link.
pub fn pair_intent_link(app_link: &str) -> String {
    let rest = app_link
        .strip_prefix("vitruvian-remote://")
        .unwrap_or(app_link);
    format!("intent://{rest}#Intent;scheme=vitruvian-remote;package=dev.vitruvian.remote;end")
}

/// `pair_name` is the Mac's short hostname made safe for a link and a label.
pub fn pair_name(hostname: &str) -> String {
    let mut out = String::new();
    for ch in hostname.trim().chars() {
        if ch.is_ascii_alphanumeric() || ch == '-' {
            out.push(ch);
            if out.len() >= 32 {
                break;
            }
        }
    }
    out
}

pub fn handle_pair_page(req: &HttpRequest) -> HttpResponse {
    let hostname = crate::sampler::get_hostname();
    handle_pair_page_with_hostname(req, &hostname)
}

pub fn handle_pair_page_with_hostname(req: &HttpRequest, hostname: &str) -> HttpResponse {
    if req.method != "GET" {
        return HttpResponse::method_not_allowed("GET");
    }
    let code = req.query_param("code").unwrap_or_default();
    if !is_valid_pair_code(&code) {
        return HttpResponse::error(400, "code must be six digits");
    }
    let hdr_host = req.header("host");
    let host = if hdr_host.is_empty() {
        req.host.as_str()
    } else {
        hdr_host
    };
    if !is_valid_pair_host(host) {
        return HttpResponse::error(400, "unusable Host header");
    }
    let name = pair_name(hostname);
    let app = pair_app_link(host, &code, &name);
    let label = if name.is_empty() {
        "this Mac".to_string()
    } else {
        name
    };
    let spaced_code = format!("{} {}", &code[..3], &code[3..]);
    let html = render_pair_qr_html(&label, &pair_intent_link(&app), &spaced_code, &app);
    HttpResponse::html(200, &html)
        .with_header("Cache-Control", "no-store")
        .with_header(
            "Content-Security-Policy",
            "default-src 'none'; style-src 'unsafe-inline'",
        )
        .with_header("Referrer-Policy", "no-referrer")
}

fn render_pair_qr_html(
    label: &str,
    intent_link: &str,
    spaced_code: &str,
    app_link: &str,
) -> String {
    format!(
        "<!doctype html>\n\
<html lang=\"en\"><head><meta charset=\"utf-8\">\n\
<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n\
<title>Pair with {label_esc}</title>\n\
<style>\n\
:root{{color-scheme:light dark;--bg:#f6f5f2;--fg:#1d1d1f;--dim:#6b6b70;--accent:#343a5c}}\n\
@media (prefers-color-scheme:dark){{:root{{--bg:#141418;--fg:#f2f2f4;--dim:#a0a0a8;--accent:#8e97d6}}}}\n\
body{{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;background:var(--bg);color:var(--fg);font:16px/1.45 system-ui,sans-serif}}\n\
main{{max-width:22rem;padding:2rem 1.25rem;text-align:center}}\n\
h1{{font-size:1.35rem;margin:0 0 .5rem}}\n\
p{{color:var(--dim);margin:.5rem 0 1.5rem}}\n\
a.open{{display:block;padding:.95rem 1rem;border-radius:.75rem;background:var(--accent);color:#fff;text-decoration:none;font-weight:600}}\n\
code{{font-size:1.1rem;letter-spacing:.12em}}\n\
small{{display:block;margin-top:1.25rem;color:var(--dim)}}\n\
small a{{color:var(--dim)}}\n\
</style></head>\n\
<body><main>\n\
<a class=\"open\" href=\"{intent_esc}\">Open in Vitruvian Remote</a>\n\
<h1 style=\"margin-top:1.5rem\">Pair this phone with {label_esc}</h1>\n\
<p>The app will ask you to confirm. Code <code>{code_esc}</code>, valid for five minutes.</p>\n\
<small>Button does nothing? <a href=\"{app_esc}\">Try the direct link</a>, or install the Vitruvian Remote app first.</small>\n\
</main></body></html>\n",
        label_esc = html_escape(label),
        intent_esc = html_escape(intent_link),
        code_esc = html_escape(spaced_code),
        app_esc = html_escape(app_link),
    )
}

fn html_escape(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for ch in s.chars() {
        match ch {
            '&' => out.push_str("&amp;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            '"' => out.push_str("&quot;"),
            '\'' => out.push_str("&#39;"),
            c => out.push(c),
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_pair_app_link_matches_the_phones_parser() {
        let got = pair_app_link("100.124.228.116:7411", "482917", "atlas");
        let want = "vitruvian-remote://pair?code=482917&name=atlas&url=http%3A%2F%2F100.124.228.116%3A7411";
        assert_eq!(got, want);
    }

    #[test]
    fn test_pair_name_strips_anything_a_link_or_heading_should_not_carry() {
        for (in_s, want) in [
            ("atlas", "atlas"),
            ("Jamess-MacBook-Pro", "Jamess-MacBook-Pro"),
            ("bad<script>name", "badscriptname"),
            ("   ", ""),
            (
                "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            ),
        ] {
            assert_eq!(pair_name(in_s), want, "pair_name({in_s:?})");
        }
    }
}
