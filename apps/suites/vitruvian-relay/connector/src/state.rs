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

use crate::Result;

pub fn now_unix() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

pub fn token_path(dir: &Path) -> PathBuf {
    dir.join("token.json")
}
pub fn device_path(dir: &Path) -> PathBuf {
    dir.join("device.json")
}
pub fn key_path(dir: &Path) -> PathBuf {
    dir.join("device.key")
}
pub fn status_path(dir: &Path) -> PathBuf {
    dir.join("status.json")
}

/// Makes sure the state directory exists and is private.
///
/// A new directory (and any missing parents) is created with mode 0700 from
/// the start, never made and then chmod'ed. An existing directory is left
/// alone if it is already closed to others. If it is more open, it is
/// tightened to 0700: `VRELAY_HOME` names the connector's own folder, so that
/// is the intended result. Its parents are never touched, and if the folder
/// is not ours the chmod fails and we report it rather than carry on.
pub fn ensure_dir(dir: &Path) -> Result<()> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::{DirBuilderExt, MetadataExt, PermissionsExt};
        match std::fs::metadata(dir) {
            Ok(meta) => {
                if meta.mode() & 0o077 != 0 {
                    std::fs::set_permissions(dir, std::fs::Permissions::from_mode(0o700))
                        .map_err(|e| format!("make {} private: {e}", dir.display()))?;
                }
                Ok(())
            }
            Err(_) => std::fs::DirBuilder::new()
                .recursive(true)
                .mode(0o700)
                .create(dir)
                .map_err(|e| format!("create {}: {e}", dir.display())),
        }
    }
    #[cfg(not(unix))]
    {
        std::fs::create_dir_all(dir).map_err(|e| format!("create {}: {e}", dir.display()))
    }
}

/// Writes `bytes` to `path` with mode 0600, atomically. The temp file has a
/// name no other writer or stray file can share (same directory, so the
/// rename is atomic), is created new with mode 0600 (so an old file's wider
/// mode can never carry over), and is synced before the rename. Two processes
/// saving the same file (`vrelay run` refreshing while `vrelay login` saves)
/// each write their own temp file; the last rename wins and neither is torn.
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
    }
    result
}

#[derive(Debug, Clone, PartialEq)]
pub struct Tokens {
    pub access_token: String,
    pub refresh_token: Option<String>,
    pub expires_at_unix: u64,
}

fn str_field(v: &Value, key: &str) -> Option<String> {
    v.get(key)
        .and_then(Value::as_str)
        .filter(|s| !s.is_empty())
        .map(str::to_string)
}

pub fn save_tokens(dir: &Path, t: &Tokens) -> Result<()> {
    let body = json!({
        "access_token": t.access_token,
        "refresh_token": t.refresh_token,
        "expires_at_unix": t.expires_at_unix,
    });
    write_private(&token_path(dir), body.to_string().as_bytes())
}

/// `Ok(None)` when nobody is signed in.
pub fn load_tokens(dir: &Path) -> Result<Option<Tokens>> {
    let path = token_path(dir);
    let text = match std::fs::read_to_string(&path) {
        Ok(t) => t,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(e) => return Err(format!("read {}: {e}", path.display())),
    };
    let v: Value = serde_json::from_str(&text).map_err(|e| format!("{}: {e}", path.display()))?;
    Ok(Some(Tokens {
        access_token: str_field(&v, "access_token")
            .ok_or_else(|| format!("{} has no access_token", path.display()))?,
        refresh_token: str_field(&v, "refresh_token"),
        expires_at_unix: v
            .get("expires_at_unix")
            .and_then(Value::as_u64)
            .ok_or_else(|| format!("{} has no expiry", path.display()))?,
    }))
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

/// Signs out: removes the token and the device record. The device key stays,
/// so signing in again re-registers the same key.
pub fn clear_sign_in(dir: &Path) -> Result<bool> {
    let mut removed = false;
    for p in [token_path(dir), device_path(dir)] {
        match std::fs::remove_file(&p) {
            Ok(()) => removed = true,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
            Err(e) => return Err(format!("remove {}: {e}", p.display())),
        }
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

    #[test]
    fn sign_out_removes_token_and_device_only() {
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
        assert!(key_path(&dir).exists());
        assert!(!clear_sign_in(&dir).unwrap());
    }
}
