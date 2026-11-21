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

//! The state directory and the files in it. Everything private is mode 0600
//! in a 0700 directory, written to a temp file and renamed so a crash never
//! leaves half a token.

use std::io::Write;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use serde_json::{json, Value};

use crate::secrets::{self, SecretStore};
use crate::Result;

pub fn now_unix() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

/// Where `token.json` is with `VRELAY_SECRETS=file` (and was before the
/// Keychain); read the sign-in through [`load_token_bytes`].
pub fn token_path(dir: &Path) -> PathBuf {
    dir.join("token.json")
}
pub fn device_path(dir: &Path) -> PathBuf {
    dir.join("device.json")
}
/// As [`token_path`]: the device key's file, read through `keys`.
pub fn key_path(dir: &Path) -> PathBuf {
    dir.join("device.key")
}
pub fn status_path(dir: &Path) -> PathBuf {
    dir.join("status.json")
}

/// Makes sure the state folder (or another of vrelay's own) exists and is
/// private. It follows a symlink: `VRELAY_HOME` may name a linked folder,
/// whose target is then made private. For a folder nobody chose by name
/// (the installer's log folder, desktop-commander's), use
/// [`ensure_private_dir`], which refuses a link.
///
/// A new folder (and any missing parents) is created with mode 0700 from
/// the start, never made and then chmod'ed. Several at once (or another
/// program making it meanwhile) all succeed. An existing folder is left
/// alone if it is already closed to others; if it is more open, it is
/// tightened to 0700. That is deliberate, and the one thing done to an
/// existing folder: `VRELAY_HOME` names the connector's own folder, so a
/// state folder someone left open to others (say, made by hand with the
/// usual 0755) is closed, not used as it is. Its parents are never touched.
/// Something there that is not a folder (`VRELAY_HOME` naming a file, say)
/// is an error naming it, never chmod'ed. If the folder is not ours the
/// chmod fails and that is reported rather than carried on from.
pub fn ensure_dir(dir: &Path) -> Result<()> {
    private_dir(dir, true)
}

/// [`ensure_dir`], but a symlink where the folder should be is an error,
/// never followed: making its target 0700 could change a folder elsewhere.
/// For `~/.claude-server-commander` and the installer's log folder.
pub fn ensure_private_dir(dir: &Path) -> Result<()> {
    private_dir(dir, false)
}

fn private_dir(dir: &Path, follow: bool) -> Result<()> {
    use std::os::unix::fs::{DirBuilderExt, MetadataExt, PermissionsExt};
    if !follow && std::fs::symlink_metadata(dir).is_ok_and(|m| m.file_type().is_symlink()) {
        return Err(format!(
            "{} is a symbolic link, not a folder; it is not followed",
            dir.display()
        ));
    }
    let made = std::fs::DirBuilder::new()
        .recursive(true)
        .mode(0o700)
        .create(dir);
    let meta = std::fs::metadata(dir);
    match (&made, &meta) {
        (_, Ok(m)) if !m.is_dir() => {
            return Err(format!("{} is not a folder", dir.display()));
        }
        (Err(e), _) => return Err(format!("create {}: {e}", dir.display())),
        (Ok(()), Err(e)) => return Err(format!("read {}: {e}", dir.display())),
        (Ok(()), Ok(_)) => {}
    }
    let mode = meta.map(|m| m.mode()).unwrap_or(0);
    if mode & 0o077 != 0 {
        std::fs::set_permissions(dir, std::fs::Permissions::from_mode(0o700))
            .map_err(|e| format!("make {} private: {e}", dir.display()))?;
    }
    Ok(())
}

/// Writes `bytes` to `path` with mode 0600, atomically. The temp file has a
/// name no other writer or stray file can share (same directory, so the
/// rename is atomic), is created new with mode 0600 (so an old file's wider
/// mode can never carry over), and is synced before the rename. Two processes
/// saving the same file (`vrelay run` refreshing while `vrelay login` saves)
/// each write their own temp file; the last rename wins and neither is torn.
/// The folder is synced after the rename.
pub fn write_private(path: &Path, bytes: &[u8]) -> Result<()> {
    use std::sync::atomic::{AtomicU64, Ordering};
    static COUNTER: AtomicU64 = AtomicU64::new(0);

    if let Some(dir) = path.parent() {
        ensure_dir(dir)?;
    }
    let name = path
        .file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_default();
    let mut attempt = 0;
    let (tmp, mut f) = loop {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.subsec_nanos())
            .unwrap_or(0);
        let tmp = path.with_file_name(format!(
            ".{name}.{}.{}.{nanos}.tmp",
            std::process::id(),
            COUNTER.fetch_add(1, Ordering::Relaxed)
        ));
        let mut opts = std::fs::OpenOptions::new();
        opts.write(true).create_new(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            opts.mode(0o600);
        }
        match opts.open(&tmp) {
            Ok(f) => break (tmp, f),
            Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists && attempt < 5 => attempt += 1,
            Err(e) => return Err(format!("write {}: {e}", tmp.display())),
        }
    };
    let result = f
        .write_all(bytes)
        .and_then(|_| f.sync_all())
        .map_err(|e| format!("write {}: {e}", tmp.display()))
        .and_then(|_| {
            std::fs::rename(&tmp, path).map_err(|e| format!("save {}: {e}", path.display()))
        });
    if result.is_err() {
        let _ = std::fs::remove_file(&tmp);
    } else {
        // The rename is only durable once the folder is synced too.
        sync_dir(path);
    }
    result
}

/// Syncs the folder holding `path`, so a create or rename in it survives a
/// power cut. Best effort: some file systems refuse to sync a folder.
pub fn sync_dir(path: &Path) {
    if let Some(dir) = path.parent() {
        if let Ok(d) = std::fs::File::open(dir) {
            let _ = d.sync_all();
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct Tokens {
    pub access_token: String,
    pub refresh_token: Option<String>,
    pub expires_at_unix: u64,
}

/// A non-empty string field of a JSON object.
pub(crate) fn str_field(v: &Value, key: &str) -> Option<String> {
    v.get(key)
        .and_then(Value::as_str)
        .filter(|s| !s.is_empty())
        .map(str::to_string)
}

/// What the sign-in is called in messages: `token.json` once, now whichever
/// store holds it.
const SIGN_IN: &str = "the saved sign-in";

pub fn save_tokens(dir: &Path, t: &Tokens) -> Result<()> {
    let body = json!({
        "access_token": t.access_token,
        "refresh_token": t.refresh_token,
        "expires_at_unix": t.expires_at_unix,
    });
    Ok(secrets::for_dir(dir).set(secrets::TOKENS, body.to_string().as_bytes())?)
}

/// The saved sign-in exactly as stored (the token JSON), `Ok(None)` when
/// nobody is signed in.
pub fn load_token_bytes(dir: &Path) -> Result<Option<Vec<u8>>> {
    Ok(secrets::for_dir(dir).get(secrets::TOKENS)?)
}

/// `Ok(None)` when nobody is signed in.
pub fn load_tokens(dir: &Path) -> Result<Option<Tokens>> {
    match load_token_bytes(dir)? {
        Some(bytes) => parse_tokens(&bytes).map(Some),
        None => Ok(None),
    }
}

/// The saved sign-in's contents (`bytes`, already read) as tokens.
pub fn parse_tokens(bytes: &[u8]) -> Result<Tokens> {
    let v: Value = serde_json::from_slice(bytes).map_err(|e| format!("{SIGN_IN}: {e}"))?;
    Ok(Tokens {
        access_token: str_field(&v, "access_token")
            .ok_or_else(|| format!("{SIGN_IN} has no access_token"))?,
        refresh_token: str_field(&v, "refresh_token"),
        expires_at_unix: v
            .get("expires_at_unix")
            .and_then(Value::as_u64)
            .ok_or_else(|| format!("{SIGN_IN} has no expiry"))?,
    })
}

#[derive(Debug, Clone, PartialEq)]
pub struct DeviceInfo {
    pub device_id: String,
    pub mcp_url: String,
}

pub fn save_device(dir: &Path, d: &DeviceInfo) -> Result<()> {
    let body = json!({"device_id": d.device_id, "mcp_url": d.mcp_url});
    write_private(&device_path(dir), body.to_string().as_bytes())
}

pub fn load_device(dir: &Path) -> Option<DeviceInfo> {
    let v: Value = serde_json::from_slice(&std::fs::read(device_path(dir)).ok()?).ok()?;
    Some(DeviceInfo {
        device_id: str_field(&v, "device_id")?,
        mcp_url: str_field(&v, "mcp_url")?,
    })
}

/// `vrelay.log`, where launchd sends the agent's stdout and stderr. launchd
/// never rotates it.
pub const AGENT_LOG: &str = "vrelay.log";
/// `vrelay.log` is cut back once past this (the old part kept as
/// `vrelay.log.1`), like `calls.log`.
pub const AGENT_LOG_MAX_BYTES: u64 = 10 * 1024 * 1024;

/// Keeps the log behind file descriptor `fd` under `max_bytes`: once it is
/// past that, its contents are copied to `<path>.1` (replacing an older
/// one) and it is emptied, so writes go on from its start. Only when `fd`
/// is that very file (`path`), opened for appending (as launchd opens
/// `StandardErrorPath`; anything else would leave a hole). True if it was
/// cut back.
// The `stat` field types differ between macOS and Linux, so a cast that is
// needed on one is a no-op on the other.
#[allow(clippy::unnecessary_cast)]
pub fn cap_log(fd: i32, path: &Path, max_bytes: u64) -> Result<bool> {
    use std::os::unix::fs::MetadataExt;
    // SAFETY: fstat and fcntl on a descriptor we were given; `st` is plain
    // memory fstat fills in.
    let (st, flags) = unsafe {
        let mut st: libc::stat = std::mem::zeroed();
        if libc::fstat(fd, &mut st) != 0 {
            return Ok(false);
        }
        (st, libc::fcntl(fd, libc::F_GETFL))
    };
    let Ok(named) = std::fs::metadata(path) else {
        return Ok(false);
    };
    let same = named.dev() == st.st_dev as u64 && named.ino() == st.st_ino as u64;
    let size = st.st_size as u64;
    if !same || flags < 0 || flags & libc::O_APPEND == 0 || size <= max_bytes {
        return Ok(false);
    }
    let old = path.with_file_name(format!(
        "{}.1",
        path.file_name().unwrap_or_default().to_string_lossy()
    ));
    std::fs::copy(path, &old).map_err(|e| format!("keep {}: {e}", old.display()))?;
    // SAFETY: truncating a descriptor we were given.
    if unsafe { libc::ftruncate(fd, 0) } != 0 {
        return Err(format!(
            "empty {}: {}",
            path.display(),
            std::io::Error::last_os_error()
        ));
    }
    Ok(true)
}

/// Held while the sign-in files change: `vrelay logout` removing them, and a
/// refresh writing its new token. An advisory `flock` on
/// `.signin.lock` in the state folder; released when dropped.
pub struct SignInLock(#[allow(dead_code)] std::fs::File);

pub fn sign_in_lock(dir: &Path) -> Result<SignInLock> {
    use std::os::unix::fs::OpenOptionsExt;
    use std::os::unix::io::AsRawFd;
    ensure_dir(dir)?;
    let path = dir.join(".signin.lock");
    let f = std::fs::OpenOptions::new()
        .create(true)
        .truncate(false)
        .write(true)
        .mode(0o600)
        .open(&path)
        .map_err(|e| format!("open {}: {e}", path.display()))?;
    loop {
        // SAFETY: flock on a descriptor we own.
        if unsafe { libc::flock(f.as_raw_fd(), libc::LOCK_EX) } == 0 {
            return Ok(SignInLock(f));
        }
        let e = std::io::Error::last_os_error();
        if e.raw_os_error() != Some(libc::EINTR) {
            return Err(format!("lock {}: {e}", path.display()));
        }
    }
}

/// Saves a refreshed token, but only if the saved sign-in still holds what the
/// refresh started from (`before`): if `vrelay logout` removed it, or a new
/// `vrelay login` replaced it, while the refresh was out, the result is
/// discarded (false) rather than undoing either. Under [`sign_in_lock`].
pub fn save_tokens_if_unchanged(dir: &Path, before: &[u8], t: &Tokens) -> Result<bool> {
    let _lock = sign_in_lock(dir)?;
    match load_token_bytes(dir) {
        Ok(Some(now)) if now == before => {
            save_tokens(dir, t)?;
            Ok(true)
        }
        _ => Ok(false),
    }
}

/// `vrelay login`'s save of a new sign-in, under [`sign_in_lock`]: a
/// refresh that has checked `token.json` and is about to write finishes
/// first, and this lands last.
pub fn save_new_sign_in(dir: &Path, t: &Tokens) -> Result<()> {
    let _lock = sign_in_lock(dir)?;
    save_tokens(dir, t)
}

/// `vrelay login`'s save of the device record, under [`sign_in_lock`].
pub fn save_new_device(dir: &Path, d: &DeviceInfo) -> Result<()> {
    let _lock = sign_in_lock(dir)?;
    save_device(dir, d)
}

/// Signs out: removes the token, the device key and the device record.
/// Signing in again makes a new key and registers a new computer (the old one
/// stays in the person's list until they remove it). Under [`sign_in_lock`], so a refresh finishing at
/// the same moment cannot write the token back. Any `token.json` or
/// `device.key` left from before the Keychain goes too.
pub fn clear_sign_in(dir: &Path) -> Result<bool> {
    let _lock = sign_in_lock(dir)?;
    let store = secrets::for_dir(dir);
    let files = secrets::FileSecrets::new(dir);
    let mut removed = false;
    for account in [secrets::TOKENS, secrets::DEVICE_KEY] {
        if store.get(account)?.is_some() {
            removed = true;
        }
        store.delete(account)?;
        // Leftover files (a no-op with the file store, which just did it).
        files.delete(account)?;
    }
    let p = device_path(dir);
    match std::fs::remove_file(&p) {
        Ok(()) => removed = true,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
        Err(e) => return Err(format!("remove {}: {e}", p.display())),
    }
    Ok(removed)
}

#[cfg(test)]
pub(crate) fn test_dir(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("vrelay-test-{}-{name}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    dir
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::PermissionsExt;

    fn mode(p: &Path) -> u32 {
        std::fs::metadata(p).unwrap().permissions().mode() & 0o777
    }

    #[test]
    fn token_file_is_0600() {
        let dir = test_dir("token");
        let t = Tokens {
            access_token: "a".into(),
            refresh_token: Some("r".into()),
            expires_at_unix: 42,
        };
        save_tokens(&dir, &t).unwrap();
        assert_eq!(mode(&token_path(&dir)), 0o600);
        assert_eq!(mode(&dir), 0o700);
        assert_eq!(load_tokens(&dir).unwrap(), Some(t.clone()));
        // Saving again (a refresh) keeps the mode.
        save_tokens(&dir, &t).unwrap();
        assert_eq!(mode(&token_path(&dir)), 0o600);
    }

    #[test]
    fn a_stray_wide_temp_file_cannot_widen_the_token() {
        let dir = test_dir("stray");
        ensure_dir(&dir).unwrap();
        for stray in ["token.tmp", "token.json.tmp"] {
            let p = dir.join(stray);
            std::fs::write(&p, b"old").unwrap();
            std::fs::set_permissions(&p, std::fs::Permissions::from_mode(0o666)).unwrap();
        }
        write_private(&token_path(&dir), b"{}").unwrap();
        assert_eq!(mode(&token_path(&dir)), 0o600);
    }

    #[test]
    fn concurrent_writers_never_corrupt_the_file() {
        let dir = test_dir("concurrent");
        ensure_dir(&dir).unwrap();
        let path = token_path(&dir);
        let handles: Vec<_> = (0..6usize)
            .map(|i| {
                let path = path.clone();
                std::thread::spawn(move || {
                    // Different lengths, so a shared temp file would leave a torn tail.
                    let body = format!("{{\"w\":{i}}}{}", " ".repeat(i * 500));
                    for _ in 0..60 {
                        write_private(&path, body.as_bytes()).unwrap();
                        let read = std::fs::read_to_string(&path).unwrap();
                        let v: serde_json::Value = serde_json::from_str(&read).expect("whole file");
                        assert!(v.get("w").is_some());
                    }
                })
            })
            .collect();
        for h in handles {
            h.join().unwrap();
        }
        // No temp files left behind.
        let left: Vec<_> = std::fs::read_dir(&dir)
            .unwrap()
            .map(|e| e.unwrap().file_name())
            .collect();
        assert_eq!(left.len(), 1, "{left:?}");
    }

    #[test]
    fn ensure_dir_is_0700_new_and_leaves_existing_parents_alone() {
        let parent = test_dir("dirs");
        std::fs::create_dir_all(&parent).unwrap();
        std::fs::set_permissions(&parent, std::fs::Permissions::from_mode(0o755)).unwrap();
        let state = parent.join("vrelay");
        ensure_dir(&state).unwrap();
        assert_eq!(mode(&state), 0o700);
        assert_eq!(mode(&parent), 0o755);
        // An existing state dir that is too open is tightened (it is ours).
        std::fs::set_permissions(&state, std::fs::Permissions::from_mode(0o755)).unwrap();
        ensure_dir(&state).unwrap();
        assert_eq!(mode(&state), 0o700);
        // A state dir inside a missing parent chain is created 0700 too.
        let deep = parent.join("a/b");
        ensure_dir(&deep).unwrap();
        assert_eq!(mode(&deep), 0o700);
    }

    /// Final review M6: the agent's log (launchd's, never rotated) is cut
    /// back past its limit, the old part kept once, and writing carries on.
    #[test]
    fn the_agent_log_is_capped() {
        use std::io::Write;
        use std::os::unix::io::AsRawFd;
        let dir = test_dir("agent-log");
        ensure_dir(&dir).unwrap();
        let path = dir.join(AGENT_LOG);
        let mut f = std::fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(&path)
            .unwrap();
        f.write_all(&[b'a'; 100]).unwrap();
        assert!(!cap_log(f.as_raw_fd(), &path, 100).unwrap(), "at the limit");
        f.write_all(b"b").unwrap();
        assert!(cap_log(f.as_raw_fd(), &path, 100).unwrap());
        assert_eq!(std::fs::metadata(&path).unwrap().len(), 0);
        assert_eq!(std::fs::read(dir.join("vrelay.log.1")).unwrap().len(), 101);
        f.write_all(b"next").unwrap();
        assert_eq!(std::fs::read(&path).unwrap(), b"next");
        // Not that file, or not appending: left alone.
        let other = dir.join("other.log");
        std::fs::write(&other, [b'x'; 200]).unwrap();
        assert!(!cap_log(f.as_raw_fd(), &other, 100).unwrap());
        let g = std::fs::OpenOptions::new()
            .write(true)
            .open(&other)
            .unwrap();
        assert!(!cap_log(g.as_raw_fd(), &other, 100).unwrap());
        assert_eq!(std::fs::metadata(&other).unwrap().len(), 200);
    }

    /// Last review L1: `vrelay login` saves its new sign-in under the
    /// sign-in lock, so a refresh holding it (between its check and its
    /// write) finishes first and the login's save lands last.
    #[test]
    fn a_new_sign_in_waits_for_the_sign_in_lock() {
        let dir = test_dir("signin-lock");
        ensure_dir(&dir).unwrap();
        let t = Tokens {
            access_token: "login".into(),
            refresh_token: None,
            expires_at_unix: 1,
        };
        let held = sign_in_lock(&dir).unwrap();
        let d = dir.clone();
        let t2 = t.clone();
        let login = std::thread::spawn(move || save_new_sign_in(&d, &t2));
        std::thread::sleep(std::time::Duration::from_millis(300));
        assert!(!token_path(&dir).exists(), "saved while the lock was held");
        drop(held);
        login.join().unwrap().unwrap();
        assert_eq!(load_tokens(&dir).unwrap(), Some(t));
    }

    /// Re-review N5: the log folder and desktop-commander's folder must not
    /// be symlinks (a link would have its target made 0700); the state
    /// folder may be one (`VRELAY_HOME` naming a linked folder), followed
    /// on purpose.
    #[test]
    fn a_symlinked_folder_is_refused_except_the_state_folder() {
        let root = test_dir("dirs-link");
        let target = root.join("target");
        std::fs::create_dir_all(&target).unwrap();
        std::fs::set_permissions(&target, std::fs::Permissions::from_mode(0o755)).unwrap();
        let link = root.join("link");
        std::os::unix::fs::symlink(&target, &link).unwrap();
        let e = ensure_private_dir(&link).unwrap_err();
        assert!(e.contains("symbolic link"), "{e}");
        assert_eq!(mode(&target), 0o755, "the link's target was changed");
        ensure_dir(&link).unwrap();
        assert_eq!(mode(&target), 0o700);
        // A real folder is fine either way.
        let real = root.join("real");
        ensure_private_dir(&real).unwrap();
        assert_eq!(mode(&real), 0o700);
    }

    /// Final-wave deferred item 5a: `VRELAY_HOME` naming a file is a clear
    /// error, and the file is left as it was.
    #[test]
    fn a_file_where_the_folder_should_be_is_a_clear_error() {
        let parent = test_dir("dirs-file");
        std::fs::create_dir_all(&parent).unwrap();
        let file = parent.join("vrelay");
        std::fs::write(&file, b"x").unwrap();
        std::fs::set_permissions(&file, std::fs::Permissions::from_mode(0o644)).unwrap();
        let e = ensure_dir(&file).unwrap_err();
        assert!(e.contains("is not a folder"), "{e}");
        assert_eq!(mode(&file), 0o644);
        // And so is a file further up the path.
        let e = ensure_dir(&file.join("sub")).unwrap_err();
        assert!(e.contains("create") || e.contains("not a folder"), "{e}");
    }

    #[test]
    fn sign_out_removes_token_key_and_device_record() {
        let dir = test_dir("signout");
        save_tokens(
            &dir,
            &Tokens {
                access_token: "a".into(),
                refresh_token: None,
                expires_at_unix: 1,
            },
        )
        .unwrap();
        save_device(
            &dir,
            &DeviceInfo {
                device_id: "d".into(),
                mcp_url: "u".into(),
            },
        )
        .unwrap();
        write_private(&key_path(&dir), &[7; 32]).unwrap();
        assert!(clear_sign_in(&dir).unwrap());
        assert!(load_tokens(&dir).unwrap().is_none());
        assert!(load_device(&dir).is_none());
        assert!(!key_path(&dir).exists(), "the device key was kept");
        assert!(!clear_sign_in(&dir).unwrap());
    }
}
