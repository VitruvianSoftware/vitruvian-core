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

//! The dashboard's sign-in: sessions kept in memory, the cookies around them,
//! and the PKCE pair that starts a sign-in.
//!
//! A restart signs everyone out (accepted for P2: signing in again is one
//! click). A session is not the token it came from: it lasts
//! [`DASHBOARD_SESSION_HOURS`], and holds the person's subject and the token
//! every form on the pages must send back (the CSRF token).

use std::collections::HashMap;
use std::sync::Mutex;

use base64::Engine as _;

use crate::random_bytes;

/// How long a person stays signed in to the dashboard.
pub const DASHBOARD_SESSION_HOURS: u64 = 12;
/// How long a sign-in may take, from the click on "Sign in" to the return.
pub const AUTH_COOKIE_SECS: u64 = 10 * 60;
pub const SESSION_COOKIE: &str = "vr_session";
pub const AUTH_COOKIE: &str = "vr_auth";

/// Sessions one person may hold at once (one per browser they use); past
/// this their oldest ends, so nobody can push out someone else's.
const MAX_SESSIONS_PER_SUBJECT: usize = 8;
/// A backstop on memory, only reachable with very many people.
const MAX_SESSIONS: usize = 4096;

fn b64url(bytes: &[u8]) -> String {
    base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(bytes)
}

/// 32 random bytes as base64url: what a session cookie holds.
fn random_token() -> String {
    b64url(&random_bytes::<32>())
}

/// What a request knows about the person behind it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SessionView {
    pub subject: String,
    /// Every form carries this back in a hidden field.
    pub csrf: String,
}

struct Entry {
    subject: String,
    csrf: String,
    expires_at: u64,
}

#[derive(Default)]
pub struct Sessions {
    inner: Mutex<HashMap<String, Entry>>,
}

impl Sessions {
    /// Starts a session for `subject` at `now` (seconds since the epoch);
    /// the value to put in the cookie.
    pub fn start(&self, subject: &str, now: u64) -> String {
        let id = random_token();
        let mut sessions = self.inner.lock().unwrap();
        sessions.retain(|_, e| e.expires_at > now);
        let oldest = |sessions: &HashMap<String, Entry>, only: Option<&str>| {
            sessions
                .iter()
                .filter(|(_, e)| only.is_none_or(|sub| e.subject == sub))
                .min_by_key(|(_, e)| e.expires_at)
                .map(|(k, _)| k.clone())
        };
        let theirs = sessions.values().filter(|e| e.subject == subject).count();
        if theirs >= MAX_SESSIONS_PER_SUBJECT {
            if let Some(k) = oldest(&sessions, Some(subject)) {
                sessions.remove(&k);
            }
        }
        if sessions.len() >= MAX_SESSIONS {
            if let Some(k) = oldest(&sessions, None) {
                sessions.remove(&k);
            }
        }
        sessions.insert(
            id.clone(),
            Entry {
                subject: subject.to_string(),
                csrf: random_token(),
                expires_at: now + DASHBOARD_SESSION_HOURS * 3600,
            },
        );
        id
    }

    /// The live session for a cookie value, or `None` (never started, ended,
    /// or past its hours).
    pub fn get(&self, id: &str, now: u64) -> Option<SessionView> {
        let mut sessions = self.inner.lock().unwrap();
        match sessions.get(id) {
            Some(e) if e.expires_at > now => Some(SessionView {
                subject: e.subject.clone(),
                csrf: e.csrf.clone(),
            }),
            Some(_) => {
                sessions.remove(id);
                None
            }
            None => None,
        }
    }

    pub fn end(&self, id: &str) {
        self.inner.lock().unwrap().remove(id);
    }

    /// Sessions held (tests).
    #[cfg(test)]
    pub fn count(&self) -> usize {
        self.inner.lock().unwrap().len()
    }
}

/// True when two secrets are equal, without stopping at the first byte that
/// differs.
pub fn same_secret(a: &str, b: &str) -> bool {
    a.len() == b.len()
        && a.bytes()
            .zip(b.bytes())
            .fold(0u8, |differ, (x, y)| differ | (x ^ y))
            == 0
}

// ------------------------------------------------------------------ cookies

/// The value of the cookie `name` in the request's `Cookie` headers.
pub fn cookie_value<'a>(headers: impl IntoIterator<Item = &'a str>, name: &str) -> Option<&'a str> {
    headers
        .into_iter()
        .flat_map(|h| h.split(';'))
        .filter_map(|pair| pair.trim().split_once('='))
        .find(|(k, _)| *k == name)
        .map(|(_, v)| v.trim())
        .filter(|v| !v.is_empty())
}

fn cookie(name: &str, value: &str, path: &str, max_age: u64, secure: bool) -> String {
    format!(
        "{name}={value}; HttpOnly;{} SameSite=Lax; Path={path}; Max-Age={max_age}",
        if secure { " Secure;" } else { "" },
    )
}

/// The `Set-Cookie` that signs a browser in. `secure` is true for every https
/// relay (a local run on http://localhost is the one exception).
pub fn session_cookie(value: &str, secure: bool) -> String {
    cookie(
        SESSION_COOKIE,
        value,
        "/",
        DASHBOARD_SESSION_HOURS * 3600,
        secure,
    )
}

/// Carries the sign-in's state and PKCE verifier from the click to the
/// return. Lax, so it comes back with the top-level redirect from the
/// identity service; only `/auth` sees it.
pub fn auth_cookie(pkce: &Pkce, secure: bool) -> String {
    cookie(
        AUTH_COOKIE,
        &format!("{}.{}", pkce.state, pkce.verifier),
        "/auth",
        AUTH_COOKIE_SECS,
        secure,
    )
}

pub fn clear_session_cookie(secure: bool) -> String {
    cookie(SESSION_COOKIE, "", "/", 0, secure)
}

pub fn clear_auth_cookie(secure: bool) -> String {
    cookie(AUTH_COOKIE, "", "/auth", 0, secure)
}

// --------------------------------------------------------------------- PKCE

/// The secrets of one sign-in: `state` comes back on the return URL, and
/// `verifier` goes with the code to the token endpoint.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Pkce {
    pub state: String,
    pub verifier: String,
}

impl Pkce {
    pub fn new() -> Pkce {
        Pkce {
            state: b64url(&random_bytes::<16>()),
            verifier: b64url(&random_bytes::<32>()),
        }
    }

    /// Reads back what [`auth_cookie`] stored: `state.verifier`, each
    /// base64url (which has no `.`).
    pub fn from_cookie(value: &str) -> Option<Pkce> {
        let (state, verifier) = value.split_once('.')?;
        let ok = |s: &str| {
            !s.is_empty()
                && s.len() <= 128
                && s.bytes()
                    .all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_')
        };
        (ok(state) && ok(verifier)).then(|| Pkce {
            state: state.to_string(),
            verifier: verifier.to_string(),
        })
    }

    /// `code_challenge` for method S256: the base64url of the verifier's
    /// SHA-256.
    pub fn challenge(&self) -> String {
        challenge_for(&self.verifier)
    }
}

impl Default for Pkce {
    fn default() -> Self {
        Self::new()
    }
}

pub fn challenge_for(verifier: &str) -> String {
    b64url(ring::digest::digest(&ring::digest::SHA256, verifier.as_bytes()).as_ref())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_session_lasts_its_hours_and_then_is_gone() {
        let s = Sessions::default();
        let id = s.start("alice", 1_000);
        assert_eq!(id.len(), 43, "32 bytes as base64url: {id}");
        let seen = s.get(&id, 1_000 + 3600 * 12 - 1).expect("still signed in");
        assert_eq!(seen.subject, "alice");
        assert_eq!(seen.csrf.len(), 43);
        assert!(s.get(&id, 1_000 + 3600 * 12).is_none(), "12 hours is up");
        assert_eq!(s.count(), 0, "an expired session is dropped when seen");
        assert!(s.get("nope", 1_000).is_none());
    }

    #[test]
    fn ending_a_session_ends_only_that_one() {
        let s = Sessions::default();
        let (a, b) = (s.start("alice", 0), s.start("alice", 0));
        assert_ne!(a, b);
        assert_ne!(s.get(&a, 1).unwrap().csrf, s.get(&b, 1).unwrap().csrf);
        s.end(&a);
        assert!(s.get(&a, 1).is_none());
        assert!(s.get(&b, 1).is_some());
    }

    #[test]
    fn one_person_cannot_push_out_another() {
        let s = Sessions::default();
        let bob = s.start("bob", 0);
        let first = s.start("alice", 1);
        for t in 2..(2 + MAX_SESSIONS_PER_SUBJECT as u64) {
            s.start("alice", t);
        }
        assert!(s.get(&first, 2).is_none(), "alice's oldest made room");
        assert!(s.get(&bob, 2).is_some(), "bob's is untouched");
        assert_eq!(s.count(), MAX_SESSIONS_PER_SUBJECT + 1);
    }

    #[test]
    fn cookies_are_read_by_name() {
        let h = ["a=1; vr_session=abc; b=2", "vr_auth=x.y"];
        assert_eq!(cookie_value(h, "vr_session"), Some("abc"));
        assert_eq!(cookie_value(h, "vr_auth"), Some("x.y"));
        assert_eq!(cookie_value(h, "vr"), None);
        assert_eq!(cookie_value(["vr_session="], "vr_session"), None);
    }

    #[test]
    fn the_session_cookie_has_every_protection() {
        let c = session_cookie("abc", true);
        assert_eq!(
            c,
            "vr_session=abc; HttpOnly; Secure; SameSite=Lax; Path=/; Max-Age=43200"
        );
        assert!(!session_cookie("abc", false).contains("Secure"));
        assert!(clear_session_cookie(true).contains("Max-Age=0"));
        let p = Pkce::new();
        let a = auth_cookie(&p, true);
        assert!(a.starts_with(&format!(
            "vr_auth={}.{}; HttpOnly; Secure;",
            p.state, p.verifier
        )));
        assert!(a.contains("Max-Age=600") && a.contains("Path=/auth"), "{a}");
    }

    /// RFC 7636, appendix B.
    #[test]
    fn the_challenge_is_the_rfc_s256_of_the_verifier() {
        assert_eq!(
            challenge_for("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
            "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        );
    }

    #[test]
    fn the_auth_cookie_round_trips_and_refuses_junk() {
        let p = Pkce::new();
        assert_eq!(p.verifier.len(), 43);
        assert_eq!(
            Pkce::from_cookie(&format!("{}.{}", p.state, p.verifier)),
            Some(p)
        );
        for bad in ["", "a", "a.", ".b", "a b.c", "a.b.c<"] {
            assert_eq!(Pkce::from_cookie(bad), None, "{bad:?}");
        }
        assert!(same_secret("abc", "abc"));
        assert!(!same_secret("abc", "abd") && !same_secret("abc", "ab"));
    }
}
