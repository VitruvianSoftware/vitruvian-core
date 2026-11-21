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

//! The store against a real PostgreSQL: the same contract the in-memory store
//! passes (`vitruvian_relay::store_contract`), plus what only a database can
//! show: the schema, migrations that can run twice (or at once), the five-device
//! limit under a race, and no quiet fallback to plain text. Runs as a
//! `service_test` (`:store_pg_test`), which starts the database.

mod pg_support;

use std::sync::{Arc, Mutex};

use pg_support::fresh_database;
use vitruvian_relay::devices::NewDevice;
use vitruvian_relay::legacy_devices::{import_legacy_devices, Imported};
use vitruvian_relay::random_id;
use vitruvian_relay::store::{PgStore, Store, StoreError, MAX_DEVICES_PER_USER, SCHEMA_VERSION};
use vitruvian_relay::LogSink;

fn quiet() -> LogSink {
    Arc::new(|_| {})
}

fn recording() -> (LogSink, Arc<Mutex<Vec<String>>>) {
    let lines = Arc::new(Mutex::new(Vec::new()));
    let sink = lines.clone();
    (
        Arc::new(move |l| sink.lock().unwrap().push(l.to_string())),
        lines,
    )
}

fn device(owner: &str, key_byte: u8) -> NewDevice {
    NewDevice {
        device_id: random_id(),
        owner_sub: owner.into(),
        name: "Mac".into(),
        public_key_ed25519: [key_byte; 32],
    }
}

#[tokio::test]
async fn store_contract() {
    let db = fresh_database().await;
    let store = PgStore::connect(&db.url(), None, quiet()).await.unwrap();
    vitruvian_relay::store_contract::store_contract(&store).await;
}

#[tokio::test]
async fn migrations_are_idempotent() {
    let db = fresh_database().await;
    let first = PgStore::connect(&db.url(), None, quiet()).await.unwrap();
    let kept = device("alice", 1);
    first.insert_device(&kept).await.unwrap();

    // Again, and twice at once (two relays starting together).
    let url = db.url();
    let (a, b) = tokio::join!(
        PgStore::connect(&url, None, quiet()),
        PgStore::connect(&url, None, quiet())
    );
    let (a, b) = (a.unwrap(), b.unwrap());

    let sql = db.client().await;
    let versions: Vec<i32> = sql
        .query("SELECT version FROM schema_version ORDER BY version", &[])
        .await
        .unwrap()
        .iter()
        .map(|r| r.get(0))
        .collect();
    assert_eq!(
        versions,
        vec![SCHEMA_VERSION],
        "applied once, not once per start"
    );
    // Nothing was dropped or recreated.
    for store in [&first, &a, &b] {
        assert!(store.device(&kept.device_id).await.unwrap().is_some());
    }
    let tables: Vec<String> = sql
        .query(
            "SELECT table_name FROM information_schema.tables \
             WHERE table_schema = 'public' ORDER BY table_name",
            &[],
        )
        .await
        .unwrap()
        .iter()
        .map(|r| r.get(0))
        .collect();
    assert_eq!(tables, ["activity", "devices", "schema_version"]);
}

/// The relay keeps no content: the tables have nowhere to put arguments or
/// results. If a column is added, this is where someone has to say why.
#[tokio::test]
async fn the_tables_hold_no_content() {
    let db = fresh_database().await;
    PgStore::connect(&db.url(), None, quiet()).await.unwrap();
    let sql = db.client().await;
    let columns = |table: &'static str| {
        let sql = &sql;
        async move {
            sql.query(
                "SELECT column_name FROM information_schema.columns \
                 WHERE table_schema = 'public' AND table_name = $1 ORDER BY ordinal_position",
                &[&table],
            )
            .await
            .unwrap()
            .iter()
            .map(|r| r.get::<_, String>(0))
            .collect::<Vec<_>>()
        }
    };
    assert_eq!(
        columns("activity").await,
        [
            "id",
            "at",
            "owner_sub",
            "device_id",
            "client_id",
            "tool",
            "arg_bytes",
            "result_bytes",
            "duration_ms",
            "outcome"
        ]
    );
    assert_eq!(
        columns("devices").await,
        [
            "id",
            "owner_sub",
            "name",
            "public_key",
            "created_at",
            "last_seen",
            "revoked_at"
        ]
    );
}

/// Two registrations at once for one person cannot both take the last place.
#[tokio::test]
async fn the_device_limit_holds_when_inserts_race() {
    let db = fresh_database().await;
    let store = Arc::new(PgStore::connect(&db.url(), None, quiet()).await.unwrap());
    let mut tasks = Vec::new();
    for i in 0..(MAX_DEVICES_PER_USER * 2) {
        let store = store.clone();
        tasks.push(tokio::spawn(async move {
            store.insert_device(&device("alice", i as u8)).await
        }));
    }
    let mut ok = 0;
    let mut refused = 0;
    for t in tasks {
        match t.await.unwrap() {
            Ok(_) => ok += 1,
            Err(StoreError::TooManyDevices) => refused += 1,
            Err(e) => panic!("{e}"),
        }
    }
    assert_eq!((ok, refused), (MAX_DEVICES_PER_USER, MAX_DEVICES_PER_USER));
    assert_eq!(
        store.devices_of("alice").await.unwrap().len(),
        MAX_DEVICES_PER_USER
    );
}

#[tokio::test]
async fn the_p1_file_is_imported_once_into_an_empty_database() {
    let db = fresh_database().await;
    let store = PgStore::connect(&db.url(), None, quiet()).await.unwrap();
    let dir = std::env::var_os("TEST_TMPDIR")
        .map(std::path::PathBuf::from)
        .unwrap_or_else(std::env::temp_dir)
        .join(format!("relay-pg-import-{}", random_id()));
    std::fs::create_dir_all(&dir).unwrap();
    let file = dir.join("devices.json");
    std::fs::write(
        &file,
        format!(
            r#"{{"james-mac":{{"owner_sub":"james","public_key_ed25519":"{}"}}}}"#,
            "0a".repeat(32)
        ),
    )
    .unwrap();

    assert_eq!(
        import_legacy_devices(&store, &file).await.unwrap(),
        Imported::Copied(1)
    );
    let d = store.device("james-mac").await.unwrap().expect("imported");
    assert_eq!(
        (d.owner_sub.as_str(), d.public_key_ed25519),
        ("james", [10; 32])
    );
    // A restart: the table has a row, so the file is left alone.
    assert_eq!(
        import_legacy_devices(&store, &file).await.unwrap(),
        Imported::TableNotEmpty
    );
    assert_eq!(store.devices_of("james").await.unwrap().len(), 1);
    // The file itself is never touched.
    assert!(file.exists());
}

/// Anything but `sslmode=disable` means TLS that is checked, and there is no
/// quiet fallback to plain text: this server has no TLS, so each is refused.
#[tokio::test]
async fn tls_is_required_unless_the_url_turns_it_off() {
    const CA: &str = "-----BEGIN CERTIFICATE-----
MIIBZzCCAQygAwIBAgIUOiG0CoIQWfYfNdBK0YCyf32fW3gwCgYIKoZIzj0EAwIw
GDEWMBQGA1UEAwwNcmVsYXktdGVzdC1jYTAgFw0yNjExMjEwODAzMzRaGA8yMTI2
MTAyODA4MDMzNFowGDEWMBQGA1UEAwwNcmVsYXktdGVzdC1jYTBZMBMGByqGSM49
AgEGCCqGSM49AwEHA0IABM7P2LLo5Rnzol7XMnw3Rz9Xl5XAc4kz/uVlq0wLIJ/9
4HzEnX0k5qzDbxQBD4EXwVjSVjPXWh8eVPeEdYmryS6jMjAwMB0GA1UdDgQWBBR0
DDC4HVcdzPK4erLXbtm0Y/evVTAPBgNVHRMBAf8EBTADAQH/MAoGCCqGSM49BAMC
A0kAMEYCIQDpSb4ugaMT4kxFHQSo+rV+86/e59EaDxJ4ETI3SOtBUgIhAMylImP3
92mZ1jLiBK4vGsqFIJ/d3r+fg+yC7w/tRI8+
-----END CERTIFICATE-----
";
    let db = fresh_database().await;
    let dir = std::env::var_os("TEST_TMPDIR")
        .map(std::path::PathBuf::from)
        .unwrap_or_else(std::env::temp_dir)
        .join(format!("relay-pg-ca-{}", random_id()));
    std::fs::create_dir_all(&dir).unwrap();
    let ca = dir.join("ca.crt");
    std::fs::write(&ca, CA).unwrap();

    let plain = db.url();
    let base = plain.split('?').next().unwrap().to_string();
    assert!(PgStore::connect(&plain, None, quiet()).await.is_ok());
    for url in [
        base.clone(),
        format!("{base}?sslmode=require"),
        // `prefer` would fall back to plain text in a stock client.
        format!("{base}?sslmode=prefer"),
    ] {
        let (log, lines) = recording();
        let err = PgStore::connect(&url, Some(&ca), log)
            .await
            .err()
            .unwrap_or_else(|| panic!("{url} must not connect without TLS"));
        assert!(err.contains("cannot reach the database"), "{err}");
        assert!(
            !err.contains("CA file"),
            "failed for the wrong reason: {err}"
        );
        let logged = lines.lock().unwrap().join("\n");
        assert!(!logged.contains("postgres@"), "{logged}");
    }
}

/// The migration lock is held only while migrating: after the store is up,
/// another session can take it at once (a lock kept by a pooled connection
/// would block the next relay's start).
#[tokio::test]
async fn the_migration_lock_is_released_after_migrating() {
    let db = fresh_database().await;
    let _store = PgStore::connect(&db.url(), None, quiet()).await.unwrap();
    let sql = db.client().await;
    let got: bool = sql
        .query_one("SELECT pg_try_advisory_lock(7313)", &[])
        .await
        .unwrap()
        .get(0);
    assert!(
        got,
        "the migration lock is still held after the store started"
    );
}

/// A release that does not work cleanly is visible in the log, and the
/// connection is closed, not handed back to the pool (the store carries on).
#[tokio::test]
async fn a_failed_lock_release_is_logged_and_the_connection_dropped() {
    let db = fresh_database().await;
    let (log, lines) = recording();
    let store = PgStore::connect(&db.url(), None, log).await.unwrap();
    assert!(
        lines.lock().unwrap().is_empty(),
        "a clean start logs no warning"
    );

    // A connection that does not hold the lock: unlocking says `false`.
    assert!(!store.release_unheld_migration_lock().await);
    let logged = lines.lock().unwrap().join("\n");
    assert!(logged.contains("migration_lock_warning"), "{logged}");
    assert!(logged.contains("not held"), "{logged}");

    // The store still works (a fresh connection is made as needed).
    assert_eq!(store.device("nobody").await, Ok(None));
}
