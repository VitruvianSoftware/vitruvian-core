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

//! The device's Ed25519 key. The seed lives in the secret store (the
//! Keychain, or `device.key` with mode 0600 under `VRELAY_SECRETS=file`); the
//! relay holds the public half and checks the signature in each `hello`.

use std::path::Path;

use base64::Engine;
use ring::rand::{SecureRandom, SystemRandom};
use ring::signature::{Ed25519KeyPair, KeyPair};
use vitruvian_relay_protocol::hello_message;

use crate::secrets::{self, SecretStore, DEVICE_KEY};
use crate::state::ensure_dir;
use crate::Result;

const SEED_LEN: usize = 32;

/// Loads the key, or creates it on first use. A key of the wrong size is
/// an error, never silently replaced (that would orphan the registered device).
pub fn load_or_create(dir: &Path) -> Result<Ed25519KeyPair> {
    ensure_dir(dir)?;
    load_or_create_in(&*secrets::for_dir(dir))
}

/// [`load_or_create`] with the store given.
pub fn load_or_create_in(store: &dyn SecretStore) -> Result<Ed25519KeyPair> {
    let seed = match store.get(DEVICE_KEY)? {
        Some(bytes) => bytes,
        None => {
            let mut seed = [0u8; SEED_LEN];
            SystemRandom::new()
                .fill(&mut seed)
                .map_err(|_| "the system random source failed".to_string())?;
            store.set(DEVICE_KEY, &seed)?;
            seed.to_vec()
        }
    };
    if seed.len() != SEED_LEN {
        return Err(format!(
            "the saved device key is {} bytes, expected {SEED_LEN}; remove it (`vrelay logout`) and sign in again to make a new device key",
            seed.len()
        ));
    }
    Ed25519KeyPair::from_seed_unchecked(&seed)
        .map_err(|e| format!("the saved device key is not usable: {e}"))
}

pub fn public_key_b64(key: &Ed25519KeyPair) -> String {
    base64::engine::general_purpose::STANDARD.encode(key.public_key().as_ref())
}

pub fn sha256_hex(data: &str) -> String {
    vitruvian_relay_protocol::hex(
        ring::digest::digest(&ring::digest::SHA256, data.as_bytes()).as_ref(),
    )
}

/// Base64 of the signature over the protocol's `hello_message`, which binds
/// `sha256(token)` so a signature cannot be replayed with another token.
pub fn sign_hello(key: &Ed25519KeyPair, device_id: &str, ts: u64, token: &str) -> String {
    let msg = hello_message(device_id, ts, &sha256_hex(token));
    base64::engine::general_purpose::STANDARD.encode(key.sign(msg.as_bytes()).as_ref())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::state::{key_path, test_dir, write_private};
    use std::os::unix::fs::PermissionsExt;

    #[test]
    fn key_file_is_0600_and_reused() {
        let dir = test_dir("key");
        let a = load_or_create(&dir).unwrap();
        let mode = std::fs::metadata(key_path(&dir))
            .unwrap()
            .permissions()
            .mode()
            & 0o777;
        assert_eq!(mode, 0o600);
        let b = load_or_create(&dir).unwrap();
        assert_eq!(a.public_key().as_ref(), b.public_key().as_ref());
    }

    #[test]
    fn a_key_file_of_the_wrong_size_is_refused_not_replaced() {
        let dir = test_dir("badkey");
        write_private(&key_path(&dir), b"short").unwrap();
        assert!(load_or_create(&dir).unwrap_err().contains("expected 32"));
        assert_eq!(std::fs::read(key_path(&dir)).unwrap(), b"short");
    }

    #[test]
    fn sign_hello_verifies_with_public_key() {
        let dir = test_dir("sign");
        let key = load_or_create(&dir).unwrap();
        let sig = sign_hello(&key, "dev-1", 1700000000, "tok");
        let sig = base64::engine::general_purpose::STANDARD
            .decode(sig)
            .unwrap();
        let pk = ring::signature::UnparsedPublicKey::new(
            &ring::signature::ED25519,
            key.public_key().as_ref(),
        );
        let msg = hello_message("dev-1", 1700000000, &sha256_hex("tok"));
        pk.verify(msg.as_bytes(), &sig).unwrap();
        // A different token, device or time does not verify.
        for other in [
            hello_message("dev-1", 1700000000, &sha256_hex("other")),
            hello_message("dev-2", 1700000000, &sha256_hex("tok")),
            hello_message("dev-1", 1700000001, &sha256_hex("tok")),
        ] {
            assert!(pk.verify(other.as_bytes(), &sig).is_err());
        }
    }

    #[test]
    fn sha256_hex_matches_a_known_digest() {
        assert_eq!(
            sha256_hex("abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
    }
}
