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

//! The server key, and what is derived from it: one key to sign client
//! credentials and a separate one to seal tokens. Nothing prints a key.

use base64::engine::general_purpose::{STANDARD, URL_SAFE_NO_PAD};
use base64::Engine;
use ring::aead::{Aad, LessSafeKey, Nonce, UnboundKey, AES_256_GCM, NONCE_LEN};
use ring::hkdf;

const CLIENT_LABEL: &[u8] = b"relay-app-client";
const SEAL_LABEL: &[u8] = b"relay-app-seal";

/// The two keys derived from `APP_SIGNIN_KEY`.
#[derive(Clone, PartialEq, Eq)]
pub struct AppKeys {
    pub(super) mac: [u8; 32],
    seal: [u8; 32],
}

impl std::fmt::Debug for AppKeys {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("AppKeys(<hidden>)")
    }
}

struct Len32;

impl hkdf::KeyType for Len32 {
    fn len(&self) -> usize {
        32
    }
}

fn derive(prk: &hkdf::Prk, label: &'static [u8]) -> [u8; 32] {
    let mut out = [0u8; 32];
    let info = [label];
    prk.expand(&info, Len32)
        .and_then(|okm| okm.fill(&mut out))
        .expect("HKDF-SHA256 can always give 32 bytes");
    out
}

impl AppKeys {
    /// From the base64 text of exactly 32 random bytes. The error never says
    /// what the key was.
    pub fn from_b64(raw: &str) -> Result<AppKeys, String> {
        let bytes = STANDARD
            .decode(raw.trim())
            .map_err(|_| "APP_SIGNIN_KEY is not valid base64".to_string())?;
        if bytes.len() != 32 {
            return Err(format!(
                "APP_SIGNIN_KEY must be 32 bytes, got {}",
                bytes.len()
            ));
        }
        let prk = hkdf::Salt::new(hkdf::HKDF_SHA256, &[]).extract(&bytes);
        Ok(AppKeys {
            mac: derive(&prk, CLIENT_LABEL),
            seal: derive(&prk, SEAL_LABEL),
        })
    }

    fn aead(&self) -> LessSafeKey {
        LessSafeKey::new(UnboundKey::new(&AES_256_GCM, &self.seal).expect("a 32 byte AES-256 key"))
    }

    /// Encrypts and authenticates `plaintext` for one client: only the same
    /// client id opens it. Output is URL-safe base64 of nonce, ciphertext, tag.
    pub fn seal(&self, client_id: &str, plaintext: &[u8]) -> String {
        let nonce_bytes = crate::random_bytes::<NONCE_LEN>();
        let mut buf = plaintext.to_vec();
        self.aead()
            .seal_in_place_append_tag(
                Nonce::assume_unique_for_key(nonce_bytes),
                Aad::from(client_id.as_bytes()),
                &mut buf,
            )
            .expect("sealing a short buffer cannot fail");
        let mut out = nonce_bytes.to_vec();
        out.extend_from_slice(&buf);
        URL_SAFE_NO_PAD.encode(out)
    }

    /// The plaintext, or None if the value was altered, was not made by this
    /// server, or was sealed for a different client.
    pub fn open(&self, client_id: &str, sealed: &str) -> Option<Vec<u8>> {
        let raw = URL_SAFE_NO_PAD.decode(sealed).ok()?;
        if raw.len() < NONCE_LEN + AES_256_GCM.tag_len() {
            return None;
        }
        let (nonce, body) = raw.split_at(NONCE_LEN);
        let nonce = Nonce::try_assume_unique_for_key(nonce).ok()?;
        let mut buf = body.to_vec();
        let plain = self
            .aead()
            .open_in_place(nonce, Aad::from(client_id.as_bytes()), &mut buf)
            .ok()?;
        Some(plain.to_vec())
    }
}

#[cfg(test)]
pub(crate) fn test_keys() -> AppKeys {
    AppKeys::from_b64(&STANDARD.encode([7u8; 32])).unwrap()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn key_must_be_32_bytes_of_base64() {
        assert!(AppKeys::from_b64("not base64!").is_err());
        assert!(AppKeys::from_b64(&STANDARD.encode([1u8; 31])).is_err());
        assert!(AppKeys::from_b64(&STANDARD.encode([1u8; 33])).is_err());
        assert!(AppKeys::from_b64(&STANDARD.encode([1u8; 32])).is_ok());
    }

    #[test]
    fn keys_never_print() {
        assert_eq!(format!("{:?}", test_keys()), "AppKeys(<hidden>)");
    }

    #[test]
    fn the_two_derived_keys_differ() {
        let k = test_keys();
        assert_ne!(k.mac, k.seal);
    }

    #[test]
    fn sealed_value_opens_only_for_its_client() {
        let k = test_keys();
        let sealed = k.seal("app.a.b", b"refresh me");
        assert_eq!(k.open("app.a.b", &sealed), Some(b"refresh me".to_vec()));
        assert_eq!(k.open("app.a.c", &sealed), None);
        // A different server key cannot open it either.
        let other = AppKeys::from_b64(&STANDARD.encode([8u8; 32])).unwrap();
        assert_eq!(other.open("app.a.b", &sealed), None);
    }

    #[test]
    fn the_same_text_seals_differently_each_time() {
        let k = test_keys();
        assert_ne!(k.seal("c", b"x"), k.seal("c", b"x"));
    }

    #[test]
    fn tampered_seal_is_refused() {
        let k = test_keys();
        let sealed = k.seal("c", b"payload");
        let mut raw = URL_SAFE_NO_PAD.decode(&sealed).unwrap();
        for i in [0, NONCE_LEN, raw.len() - 1] {
            let original = raw[i];
            raw[i] ^= 1;
            assert_eq!(k.open("c", &URL_SAFE_NO_PAD.encode(&raw)), None, "byte {i}");
            raw[i] = original;
        }
        assert_eq!(k.open("c", ""), None);
        assert_eq!(k.open("c", "AAAA"), None);
        assert_eq!(k.open("c", "***"), None);
        assert_eq!(k.open("c", &sealed[..sealed.len() - 4]), None);
    }
}
