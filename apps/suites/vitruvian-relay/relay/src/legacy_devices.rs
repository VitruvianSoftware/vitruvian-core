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

//! REMOVE IN TASK 13 (with the `/data` volume and `DATA_DIR`'s successor
//! `LEGACY_DEVICES_FILE`).
//!
//! P1 kept devices in `/data/devices.json` on a volume. P2 keeps them in
//! Postgres, and this reads the old file once, at start, so the one device
//! already registered (and its id, which the connector has saved) carries over.
//! It only ever reads the file; it never writes or deletes it.

use std::collections::BTreeMap;
use std::io;
use std::path::Path;

use serde::Deserialize;

use crate::devices::{NewDevice, DEFAULT_DEVICE_NAME};
use crate::store::{Store, StoreError};

/// On disk the key is hex.
#[derive(Deserialize)]
struct StoredDevice {
    owner_sub: String,
    public_key_ed25519: String,
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

/// The devices in the file. `Ok(None)` if there is no file. A file that
/// exists but cannot be read, parsed or holds a bad key is an error: never
/// skip over it and start empty.
pub fn read_devices_json(path: &Path) -> io::Result<Option<Vec<NewDevice>>> {
    let bytes = match std::fs::read(path) {
        Ok(b) => b,
        Err(e) if e.kind() == io::ErrorKind::NotFound => return Ok(None),
        Err(e) => return Err(e),
    };
    let stored: BTreeMap<String, StoredDevice> = serde_json::from_slice(&bytes)
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
    let mut out = Vec::new();
    for (id, d) in stored {
        let Some(key) = from_hex_32(&d.public_key_ed25519) else {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                format!("device {id}: public key is not 64 hex characters"),
            ));
        };
        out.push(NewDevice {
            device_id: id,
            owner_sub: d.owner_sub,
            name: DEFAULT_DEVICE_NAME.to_string(),
            public_key_ed25519: key,
        });
    }
    Ok(Some(out))
}

/// What the import did.
#[derive(Debug, PartialEq, Eq)]
pub enum Imported {
    /// No file: nothing to carry over.
    NoFile,
    /// The devices table already has rows (a previous start imported, or
    /// people registered since): the file is left alone.
    TableNotEmpty,
    /// This many devices were copied in.
    Copied(u64),
}

/// Copies the file's devices into the store, once: only if the file exists and
/// the store holds no devices at all (the check and the copy are one step in
/// the store, so a half-finished import cannot leave a partial table).
pub async fn import_legacy_devices(store: &dyn Store, path: &Path) -> Result<Imported, String> {
    let devices = match read_devices_json(path) {
        Ok(Some(d)) => d,
        Ok(None) => return Ok(Imported::NoFile),
        Err(e) => {
            return Err(format!(
            "cannot read the old device file {}: {e}. Fix or remove it, then start the relay again",
            path.display()
        ))
        }
    };
    match store.import_if_empty(&devices).await {
        Ok(0) if !devices.is_empty() => Ok(Imported::TableNotEmpty),
        Ok(n) => Ok(Imported::Copied(n)),
        Err(StoreError::Unavailable) => Err(
            "cannot copy the old devices into the database: it is not answering. Check that relay-db is running, then start the relay again".into(),
        ),
        Err(e) => Err(format!("cannot copy the old devices into the database: {e}")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::store::MemStore;
    use std::path::PathBuf;
    use std::sync::atomic::{AtomicU32, Ordering};

    fn temp_path(name: &str) -> PathBuf {
        static N: AtomicU32 = AtomicU32::new(0);
        let dir = std::env::var_os("TEST_TMPDIR")
            .map(PathBuf::from)
            .unwrap_or_else(std::env::temp_dir)
            .join(format!(
                "relay-legacy-{}-{}-{name}",
                std::process::id(),
                N.fetch_add(1, Ordering::SeqCst)
            ));
        std::fs::create_dir_all(&dir).unwrap();
        dir.join("devices.json")
    }

    fn good_file(path: &Path) {
        std::fs::write(
            path,
            format!(
                r#"{{"d1":{{"owner_sub":"sub-1","public_key_ed25519":"{}"}}}}"#,
                "07".repeat(32)
            ),
        )
        .unwrap();
    }

    #[test]
    fn reads_the_p1_file() {
        let path = temp_path("read");
        assert_eq!(read_devices_json(&path).unwrap(), None);
        good_file(&path);
        let got = read_devices_json(&path).unwrap().unwrap();
        assert_eq!(
            got,
            vec![NewDevice {
                device_id: "d1".into(),
                owner_sub: "sub-1".into(),
                name: DEFAULT_DEVICE_NAME.into(),
                public_key_ed25519: [7; 32],
            }]
        );
    }

    #[test]
    fn a_bad_key_or_a_corrupt_file_is_an_error_not_an_empty_list() {
        for bad in ["zz", &"g".repeat(64), &"ab".repeat(31)] {
            let path = temp_path("badkey");
            std::fs::write(
                &path,
                format!(r#"{{"d1":{{"owner_sub":"s","public_key_ed25519":"{bad}"}}}}"#),
            )
            .unwrap();
            assert!(read_devices_json(&path).is_err(), "{bad}");
        }
        let path = temp_path("corrupt");
        std::fs::write(&path, "not json").unwrap();
        assert!(read_devices_json(&path).is_err());
    }

    #[tokio::test]
    async fn imports_once_into_an_empty_store_and_keeps_the_id() {
        let path = temp_path("import");
        let store = MemStore::new();
        assert_eq!(
            import_legacy_devices(&store, &path).await.unwrap(),
            Imported::NoFile
        );
        good_file(&path);
        assert_eq!(
            import_legacy_devices(&store, &path).await.unwrap(),
            Imported::Copied(1)
        );
        let d = store.device("d1").await.unwrap().unwrap();
        assert_eq!(
            (d.owner_sub.as_str(), d.public_key_ed25519),
            ("sub-1", [7; 32])
        );
        // A second start finds devices already there and leaves everything.
        assert_eq!(
            import_legacy_devices(&store, &path).await.unwrap(),
            Imported::TableNotEmpty
        );
        assert_eq!(store.devices_of("sub-1").await.unwrap().len(), 1);
    }

    #[tokio::test]
    async fn does_not_import_over_devices_registered_since() {
        let path = temp_path("not-empty");
        good_file(&path);
        let store = MemStore::new();
        store
            .insert_device(&NewDevice {
                device_id: "new".into(),
                owner_sub: "sub-2".into(),
                name: "x".into(),
                public_key_ed25519: [1; 32],
            })
            .await
            .unwrap();
        assert_eq!(
            import_legacy_devices(&store, &path).await.unwrap(),
            Imported::TableNotEmpty
        );
        assert!(store.device("d1").await.unwrap().is_none());
    }

    #[tokio::test]
    async fn an_unreadable_file_stops_the_import_with_a_plain_message() {
        let path = temp_path("bad-import");
        std::fs::write(&path, "not json").unwrap();
        let err = import_legacy_devices(&MemStore::new(), &path)
            .await
            .unwrap_err();
        assert!(err.contains("Fix or remove it"), "{err}");
    }
}
