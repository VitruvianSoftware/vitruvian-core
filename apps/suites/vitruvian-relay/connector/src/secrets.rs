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

//! Where vrelay keeps its two secrets: the sign-in (`tokens`, the token JSON)
//! and the device key (`device_key`, the 32-byte Ed25519 seed). On a Mac they
//! live in the login Keychain, so another program reading the state folder
//! finds nothing. `VRELAY_SECRETS=file` (and every other platform) keeps them
//! in the state folder as before: `token.json` and `device.key`, mode 0600.

use std::path::{Path, PathBuf};

use crate::state::{key_path, token_path, write_private};

/// The Keychain service name every vrelay secret is stored under.
pub const SERVICE: &str = "dev.vitruvian.vrelay";
/// The sign-in: the token JSON (`access_token`, `refresh_token`, `expires_at_unix`).
pub const TOKENS: &str = "tokens";
/// The device's 32-byte Ed25519 seed.
pub const DEVICE_KEY: &str = "device_key";

/// A secret store that failed, as a message for the person at the terminal.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SecretError(pub String);

impl std::fmt::Display for SecretError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}

impl std::error::Error for SecretError {}

impl From<SecretError> for String {
    fn from(e: SecretError) -> String {
        e.0
    }
}

impl From<String> for SecretError {
    fn from(s: String) -> SecretError {
        SecretError(s)
    }
}

/// One secret per account name. `get` of a secret that is not there is
/// `Ok(None)`, and so is `delete` of one: neither is an error.
pub trait SecretStore: Send + Sync {
    fn get(&self, account: &str) -> Result<Option<Vec<u8>>, SecretError>;
    fn set(&self, account: &str, value: &[u8]) -> Result<(), SecretError>;
    fn delete(&self, account: &str) -> Result<(), SecretError>;
}

/// The files the secrets lived in before the Keychain (and still do with
/// `VRELAY_SECRETS=file`): `token.json` and `device.key` in the state
/// folder, mode 0600, written atomically.
#[derive(Debug, Clone)]
pub struct FileSecrets {
    dir: PathBuf,
}

impl FileSecrets {
    pub fn new(dir: impl Into<PathBuf>) -> FileSecrets {
        FileSecrets { dir: dir.into() }
    }

    fn path(&self, account: &str) -> Result<PathBuf, SecretError> {
        match account {
            TOKENS => Ok(token_path(&self.dir)),
            DEVICE_KEY => Ok(key_path(&self.dir)),
            other => Err(SecretError(format!("no such secret: {other}"))),
        }
    }
}

impl SecretStore for FileSecrets {
    fn get(&self, account: &str) -> Result<Option<Vec<u8>>, SecretError> {
        let path = self.path(account)?;
        match std::fs::read(&path) {
            Ok(b) => Ok(Some(b)),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
            Err(e) => Err(SecretError(format!("read {}: {e}", path.display()))),
        }
    }

    fn set(&self, account: &str, value: &[u8]) -> Result<(), SecretError> {
        Ok(write_private(&self.path(account)?, value)?)
    }

    fn delete(&self, account: &str) -> Result<(), SecretError> {
        let path = self.path(account)?;
        match std::fs::remove_file(&path) {
            Ok(()) => Ok(()),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
            Err(e) => Err(SecretError(format!("remove {}: {e}", path.display()))),
        }
    }
}

/// The login Keychain, as generic passwords under one service name.
#[cfg(target_os = "macos")]
#[derive(Debug, Clone)]
pub struct KeychainSecrets {
    service: String,
}

#[cfg(target_os = "macos")]
impl Default for KeychainSecrets {
    fn default() -> Self {
        KeychainSecrets::new()
    }
}

#[cfg(target_os = "macos")]
impl KeychainSecrets {
    pub fn new() -> KeychainSecrets {
        KeychainSecrets::with_service(SERVICE)
    }

    /// Another service name, for tests that must not touch the real items.
    pub fn with_service(service: impl Into<String>) -> KeychainSecrets {
        KeychainSecrets {
            service: service.into(),
        }
    }
}

/// `errSecItemNotFound`.
#[cfg(target_os = "macos")]
const NOT_FOUND: i32 = -25300;

#[cfg(target_os = "macos")]
impl SecretStore for KeychainSecrets {
    fn get(&self, account: &str) -> Result<Option<Vec<u8>>, SecretError> {
        match security_framework::passwords::get_generic_password(&self.service, account) {
            Ok(v) => Ok(Some(v)),
            Err(e) if e.code() == NOT_FOUND => Ok(None),
            Err(e) => Err(SecretError(format!(
                "read {account} from the Keychain: {e}"
            ))),
        }
    }

    fn set(&self, account: &str, value: &[u8]) -> Result<(), SecretError> {
        security_framework::passwords::set_generic_password(&self.service, account, value)
            .map_err(|e| SecretError(format!("save {account} in the Keychain: {e}")))
    }

    fn delete(&self, account: &str) -> Result<(), SecretError> {
        match security_framework::passwords::delete_generic_password(&self.service, account) {
            Ok(()) => Ok(()),
            Err(e) if e.code() == NOT_FOUND => Ok(()),
            Err(e) => Err(SecretError(format!(
                "remove {account} from the Keychain: {e}"
            ))),
        }
    }
}

/// What [`migrate_files_to`] moved.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct Migrated {
    pub tokens: bool,
    pub device_key: bool,
}

impl Migrated {
    pub fn any(&self) -> bool {
        self.tokens || self.device_key
    }
}

/// Moves a state folder's `token.json` and `device.key` into `store`, then
/// deletes the files. A file is deleted only once the store reads back what
/// was in it. If the store already holds that secret, it wins (the file is a
/// stale copy, for example from a crash between the save and the delete) and
/// the file is just removed. Nothing to move is not an error.
pub fn migrate_files_to(store: &dyn SecretStore, dir: &Path) -> Result<Migrated, SecretError> {
    let files = FileSecrets::new(dir);
    let mut moved = Migrated::default();
    for account in [TOKENS, DEVICE_KEY] {
        let Some(bytes) = files.get(account)? else {
            continue;
        };
        let did = match store.get(account)? {
            Some(_) => false,
            None => {
                store.set(account, &bytes)?;
                if store.get(account)?.as_deref() != Some(bytes.as_slice()) {
                    return Err(SecretError(format!(
                        "the saved {account} did not read back; its file is kept"
                    )));
                }
                true
            }
        };
        files.delete(account)?;
        match account {
            TOKENS => moved.tokens = did,
            _ => moved.device_key = did,
        }
    }
    Ok(moved)
}

/// Which store `VRELAY_SECRETS` (and the platform) selects.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Backend {
    Keychain,
    File,
}

/// `VRELAY_SECRETS=file` selects the files; anything else (or nothing) the
/// Keychain, where there is one.
pub fn backend(env: Option<&str>, macos: bool) -> Backend {
    if macos && env.map(str::trim) != Some("file") {
        Backend::Keychain
    } else {
        Backend::File
    }
}

/// The store for the state folder `dir`. With the Keychain, any `token.json`
/// or `device.key` left from before it is moved in first, so the device
/// keeps its key and the person stays signed in.
///
/// Test builds always use the files: a test must never reach the login
/// Keychain's real items.
pub fn for_dir(dir: &Path) -> Box<dyn SecretStore> {
    #[cfg(all(target_os = "macos", not(test)))]
    {
        let env = std::env::var("VRELAY_SECRETS").ok();
        if backend(env.as_deref(), true) == Backend::Keychain {
            let store = KeychainSecrets::new();
            match migrate_files_to(&store, dir) {
                Ok(m) if m.any() => eprintln!(
                    "vrelay: moved the sign-in and device key from {} into the Keychain",
                    dir.display()
                ),
                Ok(_) => {}
                Err(e) => eprintln!("vrelay: could not move secrets into the Keychain: {e}"),
            }
            return Box::new(store);
        }
    }
    Box::new(FileSecrets::new(dir))
}

/// [`for_dir`] for the state folder the environment names (`VRELAY_HOME`).
pub fn from_env() -> Box<dyn SecretStore> {
    for_dir(&crate::config::Config::from_env().dir)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::state::test_dir;
    use std::collections::HashMap;
    use std::os::unix::fs::PermissionsExt;
    use std::sync::Mutex;

    /// A store in memory, for the migration's other side.
    #[derive(Default)]
    struct Mem(Mutex<HashMap<String, Vec<u8>>>);

    impl SecretStore for Mem {
        fn get(&self, a: &str) -> Result<Option<Vec<u8>>, SecretError> {
            Ok(self.0.lock().unwrap().get(a).cloned())
        }
        fn set(&self, a: &str, v: &[u8]) -> Result<(), SecretError> {
            self.0.lock().unwrap().insert(a.into(), v.to_vec());
            Ok(())
        }
        fn delete(&self, a: &str) -> Result<(), SecretError> {
            self.0.lock().unwrap().remove(a);
            Ok(())
        }
    }

    #[test]
    fn file_secrets_round_trip_privately() {
        let dir = test_dir("secrets-file");
        let s = FileSecrets::new(&dir);
        assert_eq!(s.get(TOKENS).unwrap(), None);
        s.set(TOKENS, b"one").unwrap();
        s.set(TOKENS, b"two").unwrap();
        assert_eq!(s.get(TOKENS).unwrap(), Some(b"two".to_vec()));
        // The P1 layout: the same file names, mode 0600.
        assert_eq!(std::fs::read(token_path(&dir)).unwrap(), b"two");
        s.set(DEVICE_KEY, &[7; 32]).unwrap();
        let mode = std::fs::metadata(key_path(&dir))
            .unwrap()
            .permissions()
            .mode()
            & 0o777;
        assert_eq!(mode, 0o600);
        s.delete(TOKENS).unwrap();
        s.delete(TOKENS).unwrap();
        assert_eq!(s.get(TOKENS).unwrap(), None);
        assert!(s.get("nope").is_err());
    }

    #[test]
    fn migrate_moves_token_and_key_then_deletes_files() {
        let from = test_dir("secrets-migrate-from");
        let to = test_dir("secrets-migrate-to");
        let old = FileSecrets::new(&from);
        old.set(TOKENS, br#"{"access_token":"a"}"#).unwrap();
        old.set(DEVICE_KEY, &[9; 32]).unwrap();
        let target = FileSecrets::new(&to);
        let m = migrate_files_to(&target, &from).unwrap();
        assert_eq!(
            m,
            Migrated {
                tokens: true,
                device_key: true
            }
        );
        assert_eq!(
            target.get(TOKENS).unwrap(),
            Some(br#"{"access_token":"a"}"#.to_vec())
        );
        assert_eq!(target.get(DEVICE_KEY).unwrap(), Some(vec![9; 32]));
        assert!(!token_path(&from).exists());
        assert!(!key_path(&from).exists());
        // Nothing left to move the second time.
        assert_eq!(
            migrate_files_to(&target, &from).unwrap(),
            Migrated::default()
        );
    }

    #[test]
    fn migrate_keeps_what_the_store_already_holds() {
        let from = test_dir("secrets-migrate-held");
        FileSecrets::new(&from).set(DEVICE_KEY, &[1; 32]).unwrap();
        let store = Mem::default();
        store.set(DEVICE_KEY, &[2; 32]).unwrap();
        let m = migrate_files_to(&store, &from).unwrap();
        assert!(!m.any());
        assert_eq!(store.get(DEVICE_KEY).unwrap(), Some(vec![2; 32]));
        assert!(!key_path(&from).exists(), "the stale copy stays behind");
    }

    #[test]
    fn migrate_keeps_the_file_when_the_store_will_not_take_it() {
        struct Broken;
        impl SecretStore for Broken {
            fn get(&self, _: &str) -> Result<Option<Vec<u8>>, SecretError> {
                Ok(None)
            }
            fn set(&self, _: &str, _: &[u8]) -> Result<(), SecretError> {
                Ok(()) // says yes, keeps nothing
            }
            fn delete(&self, _: &str) -> Result<(), SecretError> {
                Ok(())
            }
        }
        let from = test_dir("secrets-migrate-broken");
        FileSecrets::new(&from).set(TOKENS, b"{}").unwrap();
        let e = migrate_files_to(&Broken, &from).unwrap_err();
        assert!(e.0.contains("did not read back"), "{e}");
        assert!(token_path(&from).exists(), "the only copy was deleted");
    }

    #[test]
    fn the_environment_picks_the_store() {
        assert_eq!(backend(None, true), Backend::Keychain);
        assert_eq!(backend(Some(""), true), Backend::Keychain);
        assert_eq!(backend(Some("keychain"), true), Backend::Keychain);
        assert_eq!(backend(Some("file"), true), Backend::File);
        assert_eq!(backend(Some(" file "), true), Backend::File);
        // No Keychain elsewhere.
        assert_eq!(backend(None, false), Backend::File);
        assert_eq!(backend(Some("keychain"), false), Backend::File);
    }
}
