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

//! The Keychain store against the real login Keychain. macOS only, and run by
//! hand (`bazel test //apps/suites/vitruvian-relay/connector:keychain_test`):
//! CI's Linux runners have no Keychain. It uses its own service name, so it
//! never touches the items a signed-in vrelay keeps, and removes what it makes.
#![cfg(target_os = "macos")]

use vitruvian_relay_connector::secrets::{
    migrate_files_to, FileSecrets, KeychainSecrets, SecretStore, DEVICE_KEY, TOKENS,
};

/// A service name no other run (or vrelay itself) shares.
fn service(name: &str) -> String {
    format!("dev.vitruvian.vrelay.test.{name}.{}", std::process::id())
}

#[test]
fn keychain_round_trip() {
    let store = KeychainSecrets::with_service(service("round-trip"));
    // Clean slate, and deleting what is not there is fine.
    store.delete(TOKENS).unwrap();
    store.delete(DEVICE_KEY).unwrap();
    assert_eq!(store.get(TOKENS).unwrap(), None);

    store.set(TOKENS, br#"{"access_token":"a"}"#).unwrap();
    assert_eq!(
        store.get(TOKENS).unwrap(),
        Some(br#"{"access_token":"a"}"#.to_vec())
    );
    // Setting again replaces it; binary values (the 32-byte seed) survive.
    store.set(TOKENS, b"two").unwrap();
    assert_eq!(store.get(TOKENS).unwrap(), Some(b"two".to_vec()));
    let seed: Vec<u8> = (0u8..32).map(|i| i.wrapping_mul(9)).collect();
    store.set(DEVICE_KEY, &seed).unwrap();
    assert_eq!(store.get(DEVICE_KEY).unwrap(), Some(seed));

    store.delete(TOKENS).unwrap();
    store.delete(DEVICE_KEY).unwrap();
    assert_eq!(store.get(TOKENS).unwrap(), None);
    assert_eq!(store.get(DEVICE_KEY).unwrap(), None);
}

#[test]
fn files_move_into_the_keychain() {
    let dir = std::env::temp_dir().join(format!("vrelay-keychain-test-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    let files = FileSecrets::new(&dir);
    files.set(TOKENS, b"{}").unwrap();
    files.set(DEVICE_KEY, &[5; 32]).unwrap();
    let store = KeychainSecrets::with_service(service("migrate"));
    let moved = migrate_files_to(&store, &dir).unwrap();
    assert!(moved.tokens && moved.device_key);
    assert_eq!(store.get(DEVICE_KEY).unwrap(), Some(vec![5; 32]));
    assert_eq!(files.get(TOKENS).unwrap(), None);
    store.delete(TOKENS).unwrap();
    store.delete(DEVICE_KEY).unwrap();
    let _ = std::fs::remove_dir_all(&dir);
}
