// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

//! Self-registered clients without a client table. A client id carries the
//! callback id Gemini gave and a signature over it; the secret is a signature
//! over the client id. A forged or edited id fails, so a flood of
//! registrations stores nothing.

use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use ring::hmac;

use super::seal::AppKeys;

/// The hosts Gemini calls back from, all under `.googleusercontent.com`.
const HOSTS: [&str; 3] = [
    "oauth-redirect",
    "oauth-redirect-sandbox",
    "oauth-redirect-test",
];
const SUFFIX: &str = ".googleusercontent.com";
const ID_PREFIX: &str = "user_bound_custom-mcp-";
const ID_LEN: usize = 24;
/// Gemini registers three hosts with two paths each.
const MAX_URIS: usize = 6;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RegisterError {
    /// No redirect URI at all.
    Empty,
    /// More than the six Gemini uses.
    TooMany,
    /// A URI that is not exactly one of Gemini's shapes.
    BadUri,
    /// URIs that carry different ids.
    MixedIds,
}

/// The id in `uri` if it is exactly
/// `https://<host>.googleusercontent.com/{r,a}/user_bound_custom-mcp-<24 hex>`
/// with nothing before, after or in between. Matched by shape: a URL parser
/// would be more lenient than this.
fn uri_id(uri: &str) -> Option<&str> {
    let rest = uri.strip_prefix("https://")?;
    let (host, path) = rest.split_once('/')?;
    let name = host.strip_suffix(SUFFIX)?;
    if !HOSTS.contains(&name) {
        return None;
    }
    let id = path
        .strip_prefix("r/")
        .or_else(|| path.strip_prefix("a/"))?
        .strip_prefix(ID_PREFIX)?;
    valid_id(id).then_some(id)
}

fn valid_id(id: &str) -> bool {
    id.len() == ID_LEN && id.bytes().all(|b| matches!(b, b'0'..=b'9' | b'a'..=b'f'))
}

/// The one id all of `uris` share, or why they are refused.
pub fn parse_registration(uris: &[String]) -> Result<String, RegisterError> {
    if uris.is_empty() {
        return Err(RegisterError::Empty);
    }
    if uris.len() > MAX_URIS {
        return Err(RegisterError::TooMany);
    }
    let mut shared: Option<&str> = None;
    for uri in uris {
        let id = uri_id(uri).ok_or(RegisterError::BadUri)?;
        match shared {
            None => shared = Some(id),
            Some(first) if first != id => return Err(RegisterError::MixedIds),
            Some(_) => {}
        }
    }
    Ok(shared.expect("a non-empty list gave an id").to_string())
}

/// The only redirect URI `/oauth/authorize` accepts for an id.
pub fn production_callback(id: &str) -> String {
    format!("https://oauth-redirect.googleusercontent.com/r/{ID_PREFIX}{id}")
}

impl AppKeys {
    fn mac_key(&self) -> hmac::Key {
        hmac::Key::new(hmac::HMAC_SHA256, &self.mac)
    }

    fn sign(&self, context: &str, value: &str) -> String {
        let tag = hmac::sign(&self.mac_key(), format!("{context}:{value}").as_bytes());
        URL_SAFE_NO_PAD.encode(tag.as_ref())
    }

    fn verify(&self, context: &str, value: &str, tag: &str) -> bool {
        let Ok(tag) = URL_SAFE_NO_PAD.decode(tag) else {
            return false;
        };
        hmac::verify(
            &self.mac_key(),
            format!("{context}:{value}").as_bytes(),
            &tag,
        )
        .is_ok()
    }

    /// `(client_id, client_secret)` for a callback id. Pure: the same id
    /// gives the same pair, and nothing is stored.
    pub fn issue_client(&self, id: &str) -> (String, String) {
        let client_id = format!("app.{id}.{}", self.sign("client", id));
        let secret = self.sign("secret", &client_id);
        (client_id, secret)
    }

    /// The callback id inside `client_id`, if this server issued it.
    pub fn client_callback_id(&self, client_id: &str) -> Option<String> {
        let rest = client_id.strip_prefix("app.")?;
        let (id, tag) = rest.split_once('.')?;
        (valid_id(id) && self.verify("client", id, tag)).then(|| id.to_string())
    }

    /// True if `secret` is the secret issued with `client_id` (compared in
    /// constant time).
    pub fn secret_ok(&self, client_id: &str, secret: &str) -> bool {
        self.client_callback_id(client_id).is_some() && self.verify("secret", client_id, secret)
    }
}

#[cfg(test)]
mod tests {
    use super::super::seal::test_keys;
    use super::*;

    const ID: &str = "089fb14b828289a2178722b6";

    fn six() -> Vec<String> {
        let mut out = Vec::new();
        for host in HOSTS {
            for kind in ["r", "a"] {
                out.push(format!(
                    "https://{host}.googleusercontent.com/{kind}/user_bound_custom-mcp-{ID}"
                ));
            }
        }
        out
    }

    fn one(uri: &str) -> Result<String, RegisterError> {
        parse_registration(&[uri.to_string()])
    }

    #[test]
    fn accepts_geminis_six_measured_uris() {
        let uris = six();
        assert_eq!(uris.len(), 6);
        assert_eq!(parse_registration(&uris), Ok(ID.to_string()));
        for uri in &uris {
            assert_eq!(one(uri), Ok(ID.to_string()), "{uri}");
        }
        assert_eq!(
            production_callback(ID),
            format!("https://oauth-redirect.googleusercontent.com/r/user_bound_custom-mcp-{ID}")
        );
        assert!(uris.contains(&production_callback(ID)));
    }

    #[test]
    fn refuses_other_host() {
        for host in [
            "evil.example.com",
            "accounts.google.com",
            "googleusercontent.com",
        ] {
            let uri = format!("https://{host}/r/user_bound_custom-mcp-{ID}");
            assert_eq!(one(&uri), Err(RegisterError::BadUri), "{host}");
        }
    }

    #[test]
    fn refuses_lookalike_host() {
        for host in [
            "oauth-redirect.googleusercontent.com.evil.com",
            "evil-oauth-redirect.googleusercontent.com",
            "oauth-redirect-x.googleusercontent.com",
            "oauth-redirect.googleusercontent.com@evil.com",
            "oauth-redirect.googleusercontent.com:8443",
            "x.oauth-redirect.googleusercontent.com",
            "OAUTH-REDIRECT.googleusercontent.com",
            "oauth-redirect.googleusercontent.comevil.com",
        ] {
            let uri = format!("https://{host}/r/user_bound_custom-mcp-{ID}");
            assert_eq!(one(&uri), Err(RegisterError::BadUri), "{host}");
        }
    }

    #[test]
    fn refuses_http() {
        let uri =
            format!("http://oauth-redirect.googleusercontent.com/r/user_bound_custom-mcp-{ID}");
        assert_eq!(one(&uri), Err(RegisterError::BadUri));
    }

    #[test]
    fn refuses_query_or_fragment() {
        let base = production_callback(ID);
        for suffix in ["?x=1", "#frag", "/", "/extra", "%20", " ", "\n"] {
            assert_eq!(
                one(&format!("{base}{suffix}")),
                Err(RegisterError::BadUri),
                "{suffix:?}"
            );
        }
        for path in [
            "/x/user_bound_custom-mcp-",
            "/r/user_bound_custom-mcp-089FB14B828289A2178722B6",
            "/r/user_bound_custom-mcp-089fb14b828289a2178722b",
            "/r/user_bound_custom-mcp-089fb14b828289a2178722b6a",
            "/r/user_bound_custom-mcp-089fb14b828289a2178722bz",
            "/r/custom-mcp-089fb14b828289a2178722b6",
            "//r/user_bound_custom-mcp-089fb14b828289a2178722b6",
        ] {
            let uri = format!("https://oauth-redirect.googleusercontent.com{path}");
            assert_eq!(one(&uri), Err(RegisterError::BadUri), "{path}");
        }
    }

    #[test]
    fn refuses_mixed_ids() {
        let other = "0123456789abcdef01234567";
        let mut uris = six();
        uris[3] = uris[3].replace(ID, other);
        assert_eq!(parse_registration(&uris), Err(RegisterError::MixedIds));
    }

    #[test]
    fn refuses_empty() {
        assert_eq!(parse_registration(&[]), Err(RegisterError::Empty));
        assert_eq!(one(""), Err(RegisterError::BadUri));
    }

    #[test]
    fn refuses_more_than_six() {
        let mut uris = six();
        // Duplicates count toward the cap: it limits the list, not distinct URIs.
        uris.push(uris[0].clone());
        assert_eq!(parse_registration(&uris), Err(RegisterError::TooMany));
    }

    #[test]
    fn clients_are_issued_without_storage() {
        let keys = test_keys();
        let (client_id, secret) = keys.issue_client(ID);
        assert!(client_id.starts_with(&format!("app.{ID}.")));
        assert_eq!(keys.issue_client(ID), (client_id.clone(), secret.clone()));
        assert_eq!(keys.client_callback_id(&client_id), Some(ID.to_string()));
        assert!(keys.secret_ok(&client_id, &secret));
    }

    #[test]
    fn forged_client_id_is_refused() {
        let keys = test_keys();
        let (client_id, _) = keys.issue_client(ID);
        let tag = client_id.rsplit('.').next().unwrap();
        let other = "0123456789abcdef01234567";
        // The signature of one id on another.
        assert_eq!(keys.client_callback_id(&format!("app.{other}.{tag}")), None);
        assert_eq!(keys.client_callback_id(&format!("app.{ID}.")), None);
        assert_eq!(keys.client_callback_id(&format!("app.{ID}.AAAA")), None);
        assert_eq!(keys.client_callback_id(&format!("app.{ID}")), None);
        assert_eq!(keys.client_callback_id(&format!("x.{ID}.{tag}")), None);
        assert_eq!(keys.client_callback_id(""), None);
        // Issued under another server key.
        let elsewhere =
            AppKeys::from_b64(&base64::engine::general_purpose::STANDARD.encode([9u8; 32]))
                .unwrap();
        let (foreign, secret) = elsewhere.issue_client(ID);
        assert_eq!(keys.client_callback_id(&foreign), None);
        assert!(!keys.secret_ok(&foreign, &secret));
    }

    #[test]
    fn secret_is_bound_to_client() {
        let keys = test_keys();
        let (a, secret_a) = keys.issue_client(ID);
        let (b, secret_b) = keys.issue_client("0123456789abcdef01234567");
        assert!(keys.secret_ok(&a, &secret_a));
        assert!(keys.secret_ok(&b, &secret_b));
        assert!(!keys.secret_ok(&a, &secret_b));
        assert!(!keys.secret_ok(&b, &secret_a));
        assert!(!keys.secret_ok(&a, ""));
        assert!(!keys.secret_ok(&a, "***"));
        // The client id is not its own secret, nor is its signature.
        assert!(!keys.secret_ok(&a, &a));
        assert!(!keys.secret_ok(&a, a.rsplit('.').next().unwrap()));
        // A secret does not work for a forged id.
        assert!(!keys.secret_ok("app.nonsense", &secret_a));
    }
}
