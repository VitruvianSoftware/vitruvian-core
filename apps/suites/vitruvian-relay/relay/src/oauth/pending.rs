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

//! What the app sign-in holds in memory between its steps: sign-ins that
//! have been sent to the identity service, sign-ins waiting for the person
//! to press Allow, and the one-time codes that have been handed out.
//!
//! The relay is one process, so memory is enough: a restart in the middle
//! of a sign-in means the person starts again. Each table is bounded
//! ([`MAX_ENTRIES`], the oldest dropped to make room) and entries expire
//! ([`SIGN_IN_SECS`], [`CONSENT_SECS`], [`CODE_SECS`]), so open endpoints
//! cannot fill it. Every entry is removed when it is taken: a sign-in, a
//! consent and a code each work once.
//!
//! Nothing here is written to a log, and nothing that holds a token prints
//! it: the `Debug` of each entry names what it is and hides the rest.

use std::collections::{BTreeMap, HashMap};
use std::fmt;
use std::sync::Mutex;

use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use ring::digest;

use crate::dashboard::session::{same_secret, Pkce};
use crate::random_bytes;

/// Most entries each table holds. When full, the oldest goes.
pub const MAX_ENTRIES: usize = 2_000;
/// How long a sign-in may take, from `/oauth/authorize` to the return.
pub const SIGN_IN_SECS: u64 = 10 * 60;
/// How long a person has to press Allow or Deny.
pub const CONSENT_SECS: u64 = 5 * 60;
/// How long an app has to redeem a code.
pub const CODE_SECS: u64 = 60;

/// 32 random bytes as base64url: the browser-binding cookie, a form token or
/// a code.
pub(crate) fn random_token() -> String {
    URL_SAFE_NO_PAD.encode(random_bytes::<32>())
}

/// A table of entries by key, bounded and expiring. Every entry of one table
/// lives the same time, so the order they came in is the order they expire.
struct Table<T> {
    ttl: u64,
    by_key: HashMap<String, Slot<T>>,
    /// Insertion order: sequence number to key.
    order: BTreeMap<u64, String>,
    next: u64,
}

struct Slot<T> {
    seq: u64,
    expires_at: u64,
    value: T,
}

impl<T> Table<T> {
    fn new(ttl: u64) -> Self {
        Table {
            ttl,
            by_key: HashMap::new(),
            order: BTreeMap::new(),
            next: 0,
        }
    }

    /// Drops what has expired by `now`.
    fn prune(&mut self, now: u64) {
        while let Some((&seq, key)) = self.order.first_key_value() {
            let expired = self.by_key.get(key).is_none_or(|s| s.expires_at <= now);
            if !expired {
                break;
            }
            let key = key.clone();
            self.order.remove(&seq);
            self.by_key.remove(&key);
        }
    }

    fn insert(&mut self, key: String, value: T, now: u64) {
        self.prune(now);
        if let Some(old) = self.by_key.remove(&key) {
            self.order.remove(&old.seq);
        }
        while self.by_key.len() >= MAX_ENTRIES {
            let Some((_, oldest)) = self.order.pop_first() else {
                break;
            };
            self.by_key.remove(&oldest);
        }
        self.next += 1;
        self.order.insert(self.next, key.clone());
        self.by_key.insert(
            key,
            Slot {
                seq: self.next,
                expires_at: now + self.ttl,
                value,
            },
        );
    }

    /// Looks at the live entry for `key`.
    fn peek(&mut self, key: &str, now: u64) -> Option<&T> {
        self.prune(now);
        self.by_key.get(key).map(|s| &s.value)
    }

    /// Removes and returns the live entry for `key` if `allow` accepts it.
    /// The check and the removal are one step, so two requests cannot both
    /// take the same entry.
    fn take_if(&mut self, key: &str, now: u64, allow: impl FnOnce(&T) -> bool) -> Option<T> {
        self.prune(now);
        if !allow(&self.by_key.get(key)?.value) {
            return None;
        }
        let slot = self.by_key.remove(key)?;
        self.order.remove(&slot.seq);
        Some(slot.value)
    }

    #[cfg(test)]
    fn len(&self) -> usize {
        self.by_key.len()
    }
}

/// What the app asked for at `/oauth/authorize`, once it has been checked.
#[derive(Clone, PartialEq, Eq)]
pub struct AuthRequest {
    pub client_id: String,
    /// The app's redirect URI (always the production callback of its id).
    pub callback: String,
    /// The app's PKCE challenge, checked again when the code is redeemed.
    pub challenge: String,
    /// The MCP URL the app wants a token for.
    pub resource: String,
    /// The app's own `state`, returned to it unchanged.
    pub state: String,
    pub device_id: String,
}

impl fmt::Debug for AuthRequest {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("AuthRequest")
            .field("client_id", &self.client_id)
            .field("device_id", &self.device_id)
            .finish_non_exhaustive()
    }
}

/// A sign-in sent to the identity service.
struct SignIn {
    request: AuthRequest,
    /// The relay's own PKCE verifier for the identity service.
    verifier: String,
    /// The value of the browser-binding cookie that started it.
    browser: String,
}

/// What the relay's sign-in with the identity service started.
pub struct Started {
    /// The relay's own PKCE pair and `state`, for the identity service.
    pub pkce: Pkce,
    /// The value for the browser-binding cookie.
    pub browser: String,
}

/// A sign-in that came back and passed every check, waiting for the person
/// to press Allow or Deny. It holds the identity service's tokens until then.
pub struct Consent {
    pub request: AuthRequest,
    pub subject: String,
    pub device_name: String,
    /// The tokens the identity service gave, held for the code (or dropped).
    pub access_token: String,
    pub refresh_token: Option<String>,
    pub expires_in: u64,
    /// The token the Allow and Deny forms must send back.
    pub csrf: String,
}

impl fmt::Debug for Consent {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("Consent")
            .field("request", &self.request)
            .finish_non_exhaustive()
    }
}

/// What a one-time code stands for, until the app redeems it.
#[derive(Clone, PartialEq, Eq)]
pub struct IssuedCode {
    pub client_id: String,
    pub callback: String,
    pub challenge: String,
    pub resource: String,
    pub access_token: String,
    pub refresh_token: Option<String>,
    pub expires_in: u64,
    pub subject: String,
    pub device_id: String,
}

impl fmt::Debug for IssuedCode {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("IssuedCode")
            .field("client_id", &self.client_id)
            .field("device_id", &self.device_id)
            .finish_non_exhaustive()
    }
}

/// The key a code is stored under: its SHA-256, so the table never holds a
/// code itself.
fn code_key(code: &str) -> String {
    URL_SAFE_NO_PAD.encode(digest::digest(&digest::SHA256, code.as_bytes()))
}

pub struct Pending {
    sign_ins: Mutex<Table<SignIn>>,
    consents: Mutex<Table<Consent>>,
    codes: Mutex<Table<IssuedCode>>,
}

impl Default for Pending {
    fn default() -> Self {
        Pending {
            sign_ins: Mutex::new(Table::new(SIGN_IN_SECS)),
            consents: Mutex::new(Table::new(CONSENT_SECS)),
            codes: Mutex::new(Table::new(CODE_SECS)),
        }
    }
}

impl Pending {
    /// Records a checked `/oauth/authorize` request and makes the relay's
    /// own PKCE pair and browser-binding value for it. `now` is seconds
    /// since the epoch.
    pub fn begin(&self, request: AuthRequest, now: u64) -> Started {
        let pkce = Pkce::new();
        let browser = random_token();
        self.sign_ins.lock().unwrap().insert(
            pkce.state.clone(),
            SignIn {
                request,
                verifier: pkce.verifier.clone(),
                browser: browser.clone(),
            },
            now,
        );
        Started { pkce, browser }
    }

    /// The sign-in the identity service sent back under `state`, once, and
    /// only to the browser that started it: `browser` must be the cookie
    /// value `begin` gave. A different browser gets `None` and leaves the
    /// sign-in for the right one.
    pub fn take_for_callback(
        &self,
        state: &str,
        browser: &str,
        now: u64,
    ) -> Option<(AuthRequest, String)> {
        self.sign_ins
            .lock()
            .unwrap()
            .take_if(state, now, |s| same_secret(&s.browser, browser))
            .map(|s| (s.request, s.verifier))
    }

    /// Holds a sign-in that is waiting for the person's decision, for the
    /// browser `browser` (a new one replaces an older one).
    pub fn put_consent(&self, browser: &str, consent: Consent, now: u64) {
        self.consents
            .lock()
            .unwrap()
            .insert(browser.to_string(), consent, now);
    }

    /// Looks at the waiting consent for `browser` without taking it: what
    /// the page shows. Returns what `f` makes of it.
    pub fn view_consent<R>(
        &self,
        browser: &str,
        now: u64,
        f: impl FnOnce(&Consent) -> R,
    ) -> Option<R> {
        self.consents.lock().unwrap().peek(browser, now).map(f)
    }

    /// Takes the waiting consent, once, if `csrf` is the form token it was
    /// shown with. Another token leaves it where it is.
    pub fn take_consent(&self, browser: &str, csrf: &str, now: u64) -> Option<Consent> {
        self.consents
            .lock()
            .unwrap()
            .take_if(browser, now, |c| same_secret(&c.csrf, csrf))
    }

    /// Stores what `code` stands for. Only the code's hash is kept.
    pub fn put_code(&self, code: &str, issued: IssuedCode, now: u64) {
        self.codes
            .lock()
            .unwrap()
            .insert(code_key(code), issued, now);
    }

    /// Redeems `code`: what it stood for, once, and only within
    /// [`CODE_SECS`] of being stored.
    pub fn take_code(&self, code: &str, now: u64) -> Option<IssuedCode> {
        self.codes
            .lock()
            .unwrap()
            .take_if(&code_key(code), now, |_| true)
    }

    /// Entries held in each table (tests).
    #[cfg(test)]
    pub fn counts(&self) -> (usize, usize, usize) {
        (
            self.sign_ins.lock().unwrap().len(),
            self.consents.lock().unwrap().len(),
            self.codes.lock().unwrap().len(),
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn request(n: usize) -> AuthRequest {
        AuthRequest {
            client_id: format!("client-{n}"),
            callback: "https://oauth-redirect.googleusercontent.com/r/x".into(),
            challenge: "c".repeat(43),
            resource: "https://relay.example.test/mcp/app/dev-1".into(),
            state: "s".into(),
            device_id: "dev-1".into(),
        }
    }

    fn consent(csrf: &str) -> Consent {
        Consent {
            request: request(0),
            subject: "alice".into(),
            device_name: "Mac".into(),
            access_token: "ACCESS-SECRET".into(),
            refresh_token: Some("REFRESH-SECRET".into()),
            expires_in: 3600,
            csrf: csrf.into(),
        }
    }

    fn issued(n: usize) -> IssuedCode {
        IssuedCode {
            client_id: format!("client-{n}"),
            callback: "https://oauth-redirect.googleusercontent.com/r/x".into(),
            challenge: "CHALLENGE-VALUE".into(),
            resource: "https://relay.example.test/mcp/app/dev-1".into(),
            access_token: "ACCESS-SECRET".into(),
            refresh_token: Some("REFRESH-SECRET".into()),
            expires_in: 3600,
            subject: "alice".into(),
            device_id: "dev-1".into(),
        }
    }

    #[test]
    fn pending_is_bounded() {
        let p = Pending::default();
        let first = p.begin(request(0), 100);
        for n in 1..(MAX_ENTRIES + 50) {
            p.begin(request(n), 100);
        }
        for n in 0..(MAX_ENTRIES + 50) {
            p.put_consent(&format!("b{n}"), consent("t"), 100);
            p.put_code(&format!("code{n}"), issued(n), 100);
        }
        assert_eq!(p.counts(), (MAX_ENTRIES, MAX_ENTRIES, MAX_ENTRIES));
        // The oldest made room; the newest are kept.
        assert!(p
            .take_for_callback(&first.pkce.state, &first.browser, 101)
            .is_none());
        assert!(p.view_consent("b0", 101, |_| ()).is_none());
        assert!(p.take_code("code0", 101).is_none());
        let last = format!("{}", MAX_ENTRIES + 49);
        assert!(p.view_consent(&format!("b{last}"), 101, |_| ()).is_some());
        assert!(p.take_code(&format!("code{last}"), 101).is_some());
    }

    #[test]
    fn entries_expire_on_their_own_clocks() {
        let p = Pending::default();
        let s = p.begin(request(0), 1_000);
        p.put_consent("b", consent("t"), 1_000);
        p.put_code("code", issued(0), 1_000);
        // A code lives 60 s.
        assert!(p.take_code("code", 1_000 + CODE_SECS).is_none());
        p.put_code("code", issued(0), 1_000);
        assert!(p.take_code("code", 1_000 + CODE_SECS - 1).is_some());
        // A consent lives 5 minutes.
        assert!(p
            .view_consent("b", 1_000 + CONSENT_SECS - 1, |_| ())
            .is_some());
        assert!(p.take_consent("b", "t", 1_000 + CONSENT_SECS).is_none());
        // A sign-in lives 10 minutes.
        assert!(p
            .take_for_callback(&s.pkce.state, &s.browser, 1_000 + SIGN_IN_SECS)
            .is_none());
        assert_eq!(p.counts(), (0, 0, 0), "expired entries are dropped");
    }

    #[test]
    fn a_sign_in_comes_back_once_and_only_to_its_browser() {
        let p = Pending::default();
        let s = p.begin(request(7), 0);
        assert!(p.take_for_callback(&s.pkce.state, "other", 1).is_none());
        assert!(p.take_for_callback("other", &s.browser, 1).is_none());
        // The wrong browser did not use it up.
        let (req, verifier) = p
            .take_for_callback(&s.pkce.state, &s.browser, 2)
            .expect("the right browser gets it");
        assert_eq!(req.client_id, "client-7");
        assert_eq!(verifier, s.pkce.verifier);
        assert!(p.take_for_callback(&s.pkce.state, &s.browser, 3).is_none());
    }

    #[test]
    fn a_consent_is_taken_once_and_only_with_its_token() {
        let p = Pending::default();
        p.put_consent("b", consent("token"), 0);
        assert!(p.take_consent("b", "wrong", 1).is_none());
        assert!(p.take_consent("other", "token", 1).is_none());
        assert!(p.view_consent("b", 1, |c| c.subject.clone()).is_some());
        assert!(p.take_consent("b", "token", 2).is_some());
        assert!(p.take_consent("b", "token", 3).is_none());
    }

    #[test]
    fn a_code_redeems_once_and_is_stored_only_as_a_hash() {
        let p = Pending::default();
        p.put_code("the-code", issued(1), 0);
        let held: Vec<String> = p.codes.lock().unwrap().by_key.keys().cloned().collect();
        assert_eq!(held.len(), 1);
        assert!(!held[0].contains("the-code"));
        assert_eq!(held[0], code_key("the-code"));
        assert!(p.take_code("another", 1).is_none());
        assert_eq!(p.take_code("the-code", 1), Some(issued(1)));
        assert!(p.take_code("the-code", 2).is_none());
    }

    #[test]
    fn nothing_that_holds_a_token_prints_it() {
        let shown = format!(
            "{:?} {:?} {:?}",
            issued(1),
            consent("CSRF-SECRET"),
            request(1)
        );
        for secret in [
            "ACCESS-SECRET",
            "REFRESH-SECRET",
            "CHALLENGE-VALUE",
            "CSRF-SECRET",
        ] {
            assert!(!shown.contains(secret), "{secret} leaked: {shown}");
        }
    }
}
