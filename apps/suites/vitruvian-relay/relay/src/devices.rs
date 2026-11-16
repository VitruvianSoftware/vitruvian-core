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

//! Device records and where they are kept.
//!
//! P1 keeps them in a JSON file; P2 swaps the file for Postgres behind the same
//! `DeviceStore` trait.

use std::collections::BTreeMap;
use std::io;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DeviceRecord {
    pub device_id: String,
    pub owner_sub: String,
    pub public_key_ed25519: [u8; 32],
}

pub trait DeviceStore: Send + Sync {
    fn get(&self, id: &str) -> Option<DeviceRecord>;
    /// `Err` can mean the record was written but may not survive a crash
    /// (see `FileDeviceStore::put`); `get` tells the two apart.
    fn put(&self, rec: DeviceRecord) -> io::Result<()>;
    /// The device a person owns. P1 allows one per subject, so re-registering
    /// replaces its key and keeps its id.
    fn find_by_owner(&self, owner_sub: &str) -> Option<DeviceRecord>;
}

/// On disk the key is hex, so the file is readable and diffable.
#[derive(Clone, Serialize, Deserialize)]
struct StoredDevice {
    owner_sub: String,
    public_key_ed25519: String,
}

fn to_hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

fn from_hex_32(s: &str) -> Option<[u8; 32]> {
    if s.len() != 64 || !s.is_ascii() {
        return None;
    }
    let mut out = [0u8; 32];
    for (i, byte) in out.iter_mut().enumerate() {
        *byte = u8::from_str_radix(&s[i * 2..i * 2 + 2], 16).ok()?;
    }
    Some(out)
}

/// A JSON file, written to a temporary sibling (mode 0600), synced, renamed
/// into place, and the directory synced, so after a crash the file is either
/// the old version or the new one, not a mix. The whole map is read at open and kept in
/// memory; `put` writes through.
pub struct FileDeviceStore {
    path: PathBuf,
    devices: Mutex<BTreeMap<String, StoredDevice>>,
    /// Syncs the directory after the rename. A field so a test can make it fail.
    sync_dir: fn(&Path) -> io::Result<()>,
}

fn sync_dir(dir: &Path) -> io::Result<()> {
    std::fs::File::open(dir)?.sync_all()
}

impl FileDeviceStore {
    /// Opens the store. A missing file is an empty store; a file that exists
    /// but cannot be parsed is an error (never silently start empty over it).
    pub fn open(path: impl AsRef<Path>) -> io::Result<Self> {
        let path = path.as_ref().to_path_buf();
        let devices: BTreeMap<String, StoredDevice> = match std::fs::read(&path) {
            Ok(bytes) => serde_json::from_slice(&bytes)
                .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?,
            Err(e) if e.kind() == io::ErrorKind::NotFound => BTreeMap::new(),
            Err(e) => return Err(e),
        };
        // A bad key would make `get` quietly report the device as unknown, so
        // refuse to start instead, like a corrupt file.
        for (id, d) in &devices {
            if from_hex_32(&d.public_key_ed25519).is_none() {
                return Err(io::Error::new(
                    io::ErrorKind::InvalidData,
                    format!("device {id}: public key is not 64 hex characters"),
                ));
            }
        }
        Ok(Self {
            path,
            devices: Mutex::new(devices),
            sync_dir,
        })
    }
}

impl FileDeviceStore {
    /// `Err` means nothing changed on disk. `Ok(Some(e))` means the new file is
    /// in place but syncing the directory failed, so it may not survive a crash.
    fn write_atomically(&self, tmp: &Path, json: &[u8]) -> io::Result<Option<io::Error>> {
        use std::io::Write;
        let mut opts = std::fs::OpenOptions::new();
        opts.write(true).create(true).truncate(true);
        #[cfg(unix)]
        std::os::unix::fs::OpenOptionsExt::mode(&mut opts, 0o600);
        let mut f = opts.open(tmp)?;
        f.write_all(json)?;
        f.sync_all()?;
        drop(f);
        std::fs::rename(tmp, &self.path)?;
        // Make the rename itself durable.
        let dir = match self.path.parent() {
            Some(d) if !d.as_os_str().is_empty() => d,
            _ => Path::new("."),
        };
        Ok((self.sync_dir)(dir).err())
    }
}

impl DeviceStore for FileDeviceStore {
    fn get(&self, id: &str) -> Option<DeviceRecord> {
        let devices = self.devices.lock().unwrap();
        let d = devices.get(id)?;
        Some(DeviceRecord {
            device_id: id.to_string(),
            owner_sub: d.owner_sub.clone(),
            public_key_ed25519: from_hex_32(&d.public_key_ed25519)?,
        })
    }

    fn find_by_owner(&self, owner_sub: &str) -> Option<DeviceRecord> {
        let id = self
            .devices
            .lock()
            .unwrap()
            .iter()
            .find(|(_, d)| d.owner_sub == owner_sub)
            .map(|(id, _)| id.clone())?;
        self.get(&id)
    }

    fn put(&self, rec: DeviceRecord) -> io::Result<()> {
        let mut devices = self.devices.lock().unwrap();
        let mut next = devices.clone();
        next.insert(
            rec.device_id,
            StoredDevice {
                owner_sub: rec.owner_sub,
                public_key_ed25519: to_hex(&rec.public_key_ed25519),
            },
        );
        let json = serde_json::to_vec_pretty(&next)
            .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
        let mut tmp = self.path.clone().into_os_string();
        tmp.push(".tmp");
        let tmp = PathBuf::from(tmp);
        let dir_sync_error = match self.write_atomically(&tmp, &json) {
            Ok(e) => e,
            Err(e) => {
                let _ = std::fs::remove_file(&tmp);
                return Err(e);
            }
        };
        // The file on disk is now the new one, so memory must match it even if
        // the directory sync failed; otherwise `get` would disagree with what a
        // restart loads. The sync failure is still reported to the caller.
        *devices = next;
        match dir_sync_error {
            None => Ok(()),
            Some(e) => Err(e),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU32, Ordering};

    fn temp_path(name: &str) -> PathBuf {
        static N: AtomicU32 = AtomicU32::new(0);
        let dir = std::env::var_os("TEST_TMPDIR")
            .map(PathBuf::from)
            .unwrap_or_else(std::env::temp_dir)
            .join(format!(
                "relay-devices-{}-{}-{name}",
                std::process::id(),
                N.fetch_add(1, Ordering::SeqCst)
            ));
        std::fs::create_dir_all(&dir).unwrap();
        dir.join("devices.json")
    }

    fn rec(id: &str, byte: u8) -> DeviceRecord {
        DeviceRecord {
            device_id: id.into(),
            owner_sub: format!("sub-{id}"),
            public_key_ed25519: [byte; 32],
        }
    }

    #[test]
    fn file_store_round_trips_and_survives_restart() {
        let path = temp_path("restart");
        let store = FileDeviceStore::open(&path).unwrap();
        assert_eq!(store.get("d1"), None);
        store.put(rec("d1", 7)).unwrap();
        store.put(rec("d2", 9)).unwrap();
        assert_eq!(store.get("d1"), Some(rec("d1", 7)));

        // A fresh store over the same file sees both records.
        let reopened = FileDeviceStore::open(&path).unwrap();
        assert_eq!(reopened.get("d1"), Some(rec("d1", 7)));
        assert_eq!(reopened.get("d2"), Some(rec("d2", 9)));
        assert_eq!(reopened.get("nope"), None);

        // Putting an existing id replaces it; no temp file is left behind.
        reopened.put(rec("d1", 8)).unwrap();
        assert_eq!(
            FileDeviceStore::open(&path).unwrap().get("d1"),
            Some(rec("d1", 8))
        );
        assert!(!path.with_file_name("devices.json.tmp").exists());
    }

    #[test]
    fn find_by_owner_returns_that_owners_device() {
        let store = FileDeviceStore::open(temp_path("owner")).unwrap();
        assert_eq!(store.find_by_owner("sub-d1"), None);
        store.put(rec("d1", 1)).unwrap();
        store.put(rec("d2", 2)).unwrap();
        assert_eq!(store.find_by_owner("sub-d2"), Some(rec("d2", 2)));
        assert_eq!(store.find_by_owner("sub-d1"), Some(rec("d1", 1)));
        assert_eq!(store.find_by_owner("nobody"), None);
    }

    #[test]
    fn invalid_key_in_the_file_refuses_to_load() {
        for bad in ["zz", &"g".repeat(64), &"ab".repeat(31)] {
            let path = temp_path("badkey");
            std::fs::write(
                &path,
                format!(r#"{{"d1":{{"owner_sub":"s","public_key_ed25519":"{bad}"}}}}"#),
            )
            .unwrap();
            assert!(FileDeviceStore::open(&path).is_err(), "{bad}");
        }
    }

    #[cfg(unix)]
    #[test]
    fn store_file_is_private() {
        use std::os::unix::fs::PermissionsExt;
        let path = temp_path("mode");
        let store = FileDeviceStore::open(&path).unwrap();
        store.put(rec("d1", 1)).unwrap();
        let mode = std::fs::metadata(&path).unwrap().permissions().mode() & 0o777;
        assert_eq!(mode, 0o600);
    }

    #[test]
    fn failed_write_leaves_no_temp_file_and_keeps_memory_unchanged() {
        let path = temp_path("failed");
        let store = FileDeviceStore::open(&path).unwrap();
        store.put(rec("d1", 1)).unwrap();
        // Make the rename fail: the target is now a non-empty directory.
        std::fs::remove_file(&path).unwrap();
        std::fs::create_dir(&path).unwrap();
        std::fs::write(path.join("x"), "x").unwrap();
        assert!(store.put(rec("d2", 2)).is_err());
        assert!(!path.with_file_name("devices.json.tmp").exists());
        assert_eq!(store.get("d2"), None);
        assert_eq!(store.get("d1"), Some(rec("d1", 1)));
    }

    #[test]
    fn directory_sync_failure_is_reported_but_memory_matches_disk() {
        let path = temp_path("dirsync");
        let mut store = FileDeviceStore::open(&path).unwrap();
        store.sync_dir = |_| Err(io::Error::other("sync failed"));
        assert!(store.put(rec("d1", 1)).is_err());
        // The record is on disk and in memory alike.
        assert_eq!(store.get("d1"), Some(rec("d1", 1)));
        assert_eq!(
            FileDeviceStore::open(&path).unwrap().get("d1"),
            Some(rec("d1", 1))
        );
    }

    #[test]
    fn corrupt_file_is_an_error_not_an_empty_store() {
        let path = temp_path("corrupt");
        std::fs::write(&path, "not json").unwrap();
        assert!(FileDeviceStore::open(&path).is_err());
    }
}
