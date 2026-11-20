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
use std::sync::Arc;

use crate::state::{key_path, token_path, write_private};

/// The Keychain service name every vrelay secret is stored under.
pub const SERVICE: &str = "dev.vitruvian.vrelay";
/// The sign-in: the token JSON (`access_token`, `refresh_token`, `expires_at_unix`).
pub const TOKENS: &str = "tokens";
/// The device's 32-byte Ed25519 seed.
pub const DEVICE_KEY: &str = "device_key";

/// What to do about a Keychain that will not answer: appended to its errors.
pub const KEYCHAIN_NEXT_STEP: &str = "unlock your login Keychain and restart vrelay";

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
                "read {account} from the Keychain: {e}; {KEYCHAIN_NEXT_STEP}"
            ))),
        }
    }

    fn set(&self, account: &str, value: &[u8]) -> Result<(), SecretError> {
        security_framework::passwords::set_generic_password(&self.service, account, value).map_err(
            |e| {
                SecretError(format!(
                    "save {account} in the Keychain: {e}; {KEYCHAIN_NEXT_STEP}"
                ))
            },
        )
    }

    fn delete(&self, account: &str) -> Result<(), SecretError> {
        match security_framework::passwords::delete_generic_password(&self.service, account) {
            Ok(()) => Ok(()),
            Err(e) if e.code() == NOT_FOUND => Ok(()),
            Err(e) => Err(SecretError(format!(
                "remove {account} from the Keychain: {e}; {KEYCHAIN_NEXT_STEP}"
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
/// deletes the files. In two steps: first every file is saved in the store
/// and read back, and only when all of them are there are the files deleted.
/// If the store already holds a secret, it wins (the file is a stale copy,
/// for example from a crash between the save and the delete) and the file is
/// just removed.
///
/// On an error the files stay the only copy: whatever this call had saved
/// in the store is removed again (otherwise the run that carries on with the
/// files would refresh the sign-in there, and the next start would find an
/// older one in the store winning over it). A secret whose file was already
/// deleted is complete in the store and stays. Nothing to move is not an
/// error.
pub fn migrate_files_to(store: &dyn SecretStore, dir: &Path) -> Result<Migrated, SecretError> {
    migrate_between(&FileSecrets::new(dir), store)
}

fn migrate_between(
    files: &dyn SecretStore,
    store: &dyn SecretStore,
) -> Result<Migrated, SecretError> {
    let mut moved = Migrated::default();
    // Accounts whose file is to go, and those this call saved in the store.
    let mut to_delete = Vec::new();
    let mut saved: Vec<&str> = Vec::new();
    let mut copy = || -> Result<(), SecretError> {
        for account in [TOKENS, DEVICE_KEY] {
            let Some(bytes) = files.get(account)? else {
                continue;
            };
            if store.get(account)?.is_none() {
                saved.push(account);
                store.set(account, &bytes)?;
                if store.get(account)?.as_deref() != Some(bytes.as_slice()) {
                    return Err(SecretError(format!(
                        "the saved {account} did not read back; its file is kept"
                    )));
                }
                match account {
                    TOKENS => moved.tokens = true,
                    _ => moved.device_key = true,
                }
            }
            to_delete.push(account);
        }
        Ok(())
    };
    let mut result = copy();
    let mut deleted: Vec<&str> = Vec::new();
    if result.is_ok() {
        for account in &to_delete {
            if let Err(e) = files.delete(account) {
                result = Err(e);
                break;
            }
            deleted.push(account);
        }
    }
    if let Err(e) = result {
        for account in saved.iter().filter(|a| !deleted.contains(a)) {
            let _ = store.delete(account);
        }
        return Err(e);
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

/// Opens `keychain` as the store for the state folder `dir`: any
/// `token.json` or `device.key` left from before it is moved in first, so
/// the device keeps its key and the person stays signed in.
///
/// If that move fails, the files stay the source of truth for this run
/// (`FileSecrets`) and `log` says what to do; the move is tried again at the
/// next start. Using the Keychain anyway would find no device key there and
/// make a new one, orphaning the registered device.
pub fn open_with(
    keychain: Arc<dyn SecretStore>,
    dir: &Path,
    log: &dyn Fn(&str),
) -> Arc<dyn SecretStore> {
    match migrate_files_to(&*keychain, dir) {
        Ok(m) => {
            if m.any() {
                log(&format!(
                    "moved the sign-in and device key from {} into the Keychain",
                    dir.display()
                ));
            }
            keychain
        }
        Err(e) => {
            log(&format!(
                "could not move the sign-in and device key into the Keychain ({e}); \
                 using the files in {} for now. Unlock your login Keychain and \
                 restart vrelay to try again.",
                dir.display()
            ));
            Arc::new(FileSecrets::new(dir))
        }
    }
}

/// The store chosen for each state folder, so it is opened (and any move out
/// of files done) once per process.
#[cfg_attr(not(target_os = "macos"), allow(dead_code))]
#[derive(Default)]
struct Chosen(std::sync::Mutex<std::collections::HashMap<PathBuf, Arc<dyn SecretStore>>>);

#[cfg_attr(not(target_os = "macos"), allow(dead_code))]
impl Chosen {
    fn get_or_open(
        &self,
        dir: &Path,
        open: impl FnOnce() -> Arc<dyn SecretStore>,
    ) -> Arc<dyn SecretStore> {
        self.0
            .lock()
            .unwrap()
            .entry(dir.to_path_buf())
            .or_insert_with(open)
            .clone()
    }
}

/// The store for the state folder `dir`, chosen (and any move out of files
/// done) once per process: later calls get the same store, so a Keychain
/// that is slow or refusing is not asked again on every token read.
///
/// Test builds always use the files: a test must never reach the login
/// Keychain's real items.
pub fn for_dir(dir: &Path) -> Arc<dyn SecretStore> {
    #[cfg(all(target_os = "macos", not(test)))]
    {
        static CHOSEN: std::sync::OnceLock<Chosen> = std::sync::OnceLock::new();
        let env = std::env::var("VRELAY_SECRETS").ok();
        if backend(env.as_deref(), true) == Backend::Keychain {
            return CHOSEN.get_or_init(Chosen::default).get_or_open(dir, || {
                open_with(Arc::new(KeychainSecrets::new()), dir, &|m| {
                    eprintln!("vrelay: {m}")
                })
            });
        }
    }
    Arc::new(FileSecrets::new(dir))
}

/// [`for_dir`] for the state folder the environment names (`VRELAY_HOME`).
pub fn from_env() -> Arc<dyn SecretStore> {
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

    /// Review: if the move into the Keychain fails, the files stay the
    /// source of truth for the run. The Keychain is never used then: it would
    /// find no device key and make a new one, orphaning the registered device.
    #[test]
    fn failed_migration_keeps_using_the_files() {
        /// Reads fine and finds nothing; every save is refused.
        struct DeniesSaves;
        impl SecretStore for DeniesSaves {
            fn get(&self, _: &str) -> Result<Option<Vec<u8>>, SecretError> {
                Ok(None)
            }
            fn set(&self, _: &str, _: &[u8]) -> Result<(), SecretError> {
                Err(SecretError("access denied".into()))
            }
            fn delete(&self, _: &str) -> Result<(), SecretError> {
                Ok(())
            }
        }
        let dir = test_dir("secrets-failed-migration");
        let files = FileSecrets::new(&dir);
        let seed = [9u8; 32];
        files.set(DEVICE_KEY, &seed).unwrap();
        files.set(TOKENS, br#"{"access_token":"a"}"#).unwrap();
        let lines = Mutex::new(Vec::new());
        let store = open_with(Arc::new(DeniesSaves), &dir, &|m| {
            lines.lock().unwrap().push(m.to_string())
        });
        // The files are used, and the person is told what to do.
        let said = lines.lock().unwrap().join("\n");
        assert!(said.contains("access denied"), "{said}");
        assert!(
            said.contains("Unlock your login Keychain and restart vrelay"),
            "{said}"
        );
        assert_eq!(store.get(DEVICE_KEY).unwrap(), Some(seed.to_vec()));
        // The device key in use is the registered one: no new seed is made.
        let key = crate::keys::load_or_create_in(&*store).unwrap();
        let registered = ring::signature::Ed25519KeyPair::from_seed_unchecked(&seed).unwrap();
        assert_eq!(
            ring::signature::KeyPair::public_key(&key).as_ref(),
            ring::signature::KeyPair::public_key(&registered).as_ref()
        );
        // Nothing was deleted or rewritten.
        assert_eq!(std::fs::read(key_path(&dir)).unwrap(), seed);
        assert_eq!(
            std::fs::read(token_path(&dir)).unwrap(),
            br#"{"access_token":"a"}"#
        );
    }

    /// Review round 2: a move that saves the sign-in and then fails on the
    /// device key must not leave the sign-in in the store, or the run that
    /// carries on with the files would refresh it there and the next start
    /// would find the store's older copy winning.
    #[test]
    fn failed_migration_rolls_back_what_it_saved() {
        /// Takes the first secret saved, refuses the device key.
        struct TakesTokensOnly(Mem);
        impl SecretStore for TakesTokensOnly {
            fn get(&self, a: &str) -> Result<Option<Vec<u8>>, SecretError> {
                self.0.get(a)
            }
            fn set(&self, a: &str, v: &[u8]) -> Result<(), SecretError> {
                if a == DEVICE_KEY {
                    return Err(SecretError("access denied".into()));
                }
                self.0.set(a, v)
            }
            fn delete(&self, a: &str) -> Result<(), SecretError> {
                self.0.delete(a)
            }
        }
        let dir = test_dir("secrets-rollback");
        let files = FileSecrets::new(&dir);
        files.set(TOKENS, br#"{"access_token":"a"}"#).unwrap();
        files.set(DEVICE_KEY, &[3; 32]).unwrap();
        let store = TakesTokensOnly(Mem::default());
        assert!(migrate_files_to(&store, &dir).is_err());
        assert_eq!(
            store.get(TOKENS).unwrap(),
            None,
            "the sign-in stayed behind"
        );
        assert_eq!(store.get(DEVICE_KEY).unwrap(), None);
        // The files are untouched, and the one copy.
        assert_eq!(
            std::fs::read(token_path(&dir)).unwrap(),
            br#"{"access_token":"a"}"#
        );
        assert_eq!(std::fs::read(key_path(&dir)).unwrap(), [3; 32]);
        // A secret the store already held is not this call's to remove.
        let held = TakesTokensOnly(Mem::default());
        held.set(TOKENS, b"newer").unwrap();
        assert!(migrate_files_to(&held, &dir).is_err());
        assert_eq!(held.get(TOKENS).unwrap(), Some(b"newer".to_vec()));
    }

    /// A delete that fails after both are saved: what is left in a file is
    /// taken out of the store again; what was already deleted stays there.
    #[test]
    fn a_failed_file_delete_rolls_back_the_secrets_still_in_files() {
        /// Files that will not delete the device key.
        struct KeepsKey(Mem);
        impl SecretStore for KeepsKey {
            fn get(&self, a: &str) -> Result<Option<Vec<u8>>, SecretError> {
                self.0.get(a)
            }
            fn set(&self, a: &str, v: &[u8]) -> Result<(), SecretError> {
                self.0.set(a, v)
            }
            fn delete(&self, a: &str) -> Result<(), SecretError> {
                if a == DEVICE_KEY {
                    return Err(SecretError("cannot remove".into()));
                }
                self.0.delete(a)
            }
        }
        let files = KeepsKey(Mem::default());
        files.set(TOKENS, b"{}").unwrap();
        files.set(DEVICE_KEY, &[4; 32]).unwrap();
        let store = Mem::default();
        assert!(migrate_between(&files, &store).is_err());
        // The sign-in moved for good; the key is still only in its file.
        assert_eq!(store.get(TOKENS).unwrap(), Some(b"{}".to_vec()));
        assert_eq!(files.get(TOKENS).unwrap(), None);
        assert_eq!(store.get(DEVICE_KEY).unwrap(), None);
        assert_eq!(files.get(DEVICE_KEY).unwrap(), Some(vec![4; 32]));
    }

    /// A move that fails half way leaves every file where it was, not the
    /// device key in the Keychain and the sign-in still in a file.
    #[test]
    fn a_move_that_fails_part_way_deletes_nothing() {
        /// Takes the first secret saved, refuses the second.
        struct TakesOne(Mem);
        impl SecretStore for TakesOne {
            fn get(&self, a: &str) -> Result<Option<Vec<u8>>, SecretError> {
                self.0.get(a)
            }
            fn set(&self, a: &str, v: &[u8]) -> Result<(), SecretError> {
                if a == DEVICE_KEY {
                    return Err(SecretError("access denied".into()));
                }
                self.0.set(a, v)
            }
            fn delete(&self, a: &str) -> Result<(), SecretError> {
                self.0.delete(a)
            }
        }
        let dir = test_dir("secrets-half-migration");
        let files = FileSecrets::new(&dir);
        files.set(TOKENS, b"{}").unwrap();
        files.set(DEVICE_KEY, &[3; 32]).unwrap();
        assert!(migrate_files_to(&TakesOne(Mem::default()), &dir).is_err());
        assert!(token_path(&dir).exists(), "the sign-in file was deleted");
        assert!(key_path(&dir).exists());
    }

    /// Review: the store is opened (and the move done) once per folder, not on
    /// every token read.
    #[test]
    fn the_store_is_chosen_once_per_folder() {
        let chosen = Chosen::default();
        let opened = std::sync::atomic::AtomicUsize::new(0);
        let open = || -> Arc<dyn SecretStore> {
            opened.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
            Arc::new(Mem::default())
        };
        let a = chosen.get_or_open(Path::new("/a"), open);
        a.set(TOKENS, b"x").unwrap();
        let again = chosen.get_or_open(Path::new("/a"), open);
        assert_eq!(
            again.get(TOKENS).unwrap(),
            Some(b"x".to_vec()),
            "a new store"
        );
        assert_eq!(opened.load(std::sync::atomic::Ordering::SeqCst), 1);
        chosen.get_or_open(Path::new("/b"), open);
        assert_eq!(opened.load(std::sync::atomic::Ordering::SeqCst), 2);
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
