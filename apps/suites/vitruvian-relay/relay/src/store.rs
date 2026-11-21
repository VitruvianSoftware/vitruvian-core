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

//! Where the relay keeps what it must not forget: the registered devices and a
//! log of calls (tool, sizes, duration, outcome). The relay keeps no content:
//! nothing here ever holds a call's arguments or its result.
//!
//! [`PgStore`] is Postgres (CloudNativePG in the cluster). [`MemStore`] is the
//! same rules in memory, for unit tests only; both run the one contract in
//! [`crate::store_contract`].

use std::fmt;
use std::path::Path;
use std::sync::{Arc, Mutex};
use std::time::{Duration, SystemTime};

use async_trait::async_trait;
use deadpool_postgres::{Manager, ManagerConfig, Pool, RecyclingMethod, Runtime};
use serde_json::json;
use tokio_postgres::config::SslMode;
use tokio_postgres::error::SqlState;
use tokio_postgres::{Client, NoTls};

use crate::devices::{DeviceRecord, NewDevice};
use crate::{log_event, LogSink};

/// The most devices one person can have registered at once. A revoked device
/// does not count.
pub const MAX_DEVICES_PER_USER: usize = 5;

/// What a person is told when the database does not answer. It says what to do
/// next, and the logged outcome for a call that met it is
/// [`STORE_UNAVAILABLE_OUTCOME`].
pub const UNAVAILABLE_MESSAGE: &str =
    "The relay is having trouble right now; try again in a minute.";

/// The `outcome` of a call the relay could not even start because the
/// database did not answer.
pub const STORE_UNAVAILABLE_OUTCOME: &str = "store_unavailable";

/// How long the relay waits to connect, and then for each query. A database
/// that does not answer in this long is "unavailable".
pub const STORE_TIMEOUT: Duration = Duration::from_secs(5);

/// Connections kept open to Postgres.
pub const POOL_SIZE: usize = 8;

/// How long a call stays in the activity log.
pub const ACTIVITY_RETENTION_DAYS: u64 = 30;

/// How often the relay clears out calls older than [`ACTIVITY_RETENTION_DAYS`].
pub const ACTIVITY_PURGE_EVERY: Duration = Duration::from_secs(60 * 60);

/// Deletes the calls recorded more than [`ACTIVITY_RETENTION_DAYS`] before
/// `now`; how many.
pub async fn purge_expired_activity(store: &dyn Store, now: SystemTime) -> Result<u64, StoreError> {
    let keep = Duration::from_secs(ACTIVITY_RETENTION_DAYS * 24 * 60 * 60);
    store
        .purge_activity_before(now.checked_sub(keep).unwrap_or(SystemTime::UNIX_EPOCH))
        .await
}

/// Clears out old calls once an hour, for as long as the relay runs (the
/// first time at once, so a relay that restarts often still tidies up). A
/// failure is logged and tried again an hour later; it never stops the relay.
pub async fn purge_activity_forever(store: Arc<dyn Store>, log: LogSink, every: Duration) {
    let mut tick = tokio::time::interval(every);
    tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
    loop {
        tick.tick().await;
        match purge_expired_activity(store.as_ref(), SystemTime::now()).await {
            Ok(0) => {}
            Ok(rows) => log_event(&log, "activity_purged", json!({"rows": rows})),
            Err(e) => log_event(
                &log,
                "activity_purge_failed",
                json!({"error": e.to_string()}),
            ),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StoreError {
    /// The person already has [`MAX_DEVICES_PER_USER`] devices.
    TooManyDevices,
    /// A device with that id is already stored (revoked ones keep their id).
    DuplicateId,
    /// The database did not answer, or answered with something unusable. The
    /// detail is logged where it happened ([`PgStore`]); the person is only
    /// told [`UNAVAILABLE_MESSAGE`].
    Unavailable,
}

impl fmt::Display for StoreError {
    /// Plain English, and what to do next.
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            StoreError::TooManyDevices => write!(
                f,
                "You already have {MAX_DEVICES_PER_USER} computers connected. Remove one in the dashboard first."
            ),
            StoreError::DuplicateId => f.write_str(
                "That device is already registered. Register it again to get a new one.",
            ),
            StoreError::Unavailable => f.write_str(UNAVAILABLE_MESSAGE),
        }
    }
}

impl std::error::Error for StoreError {}

/// One finished call, as the relay records it. Names and sizes only.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ActivityRow {
    pub at: SystemTime,
    pub owner_sub: String,
    pub device_id: String,
    pub client_id: String,
    pub tool: String,
    pub arg_bytes: Option<u32>,
    pub result_bytes: Option<u32>,
    pub duration_ms: Option<u32>,
    pub outcome: String,
}

#[async_trait]
pub trait Store: Send + Sync {
    /// A device that is registered and not revoked. A revoked one is `None`,
    /// like one that never existed.
    async fn device(&self, id: &str) -> Result<Option<DeviceRecord>, StoreError>;
    /// A device that was revoked (with `revoked` set); `None` for one that is
    /// registered or that never existed. Only for telling a removed computer
    /// that it was removed: never to let it do anything.
    async fn revoked_device(&self, id: &str) -> Result<Option<DeviceRecord>, StoreError>;
    /// A person's devices (not revoked), oldest first.
    async fn devices_of(&self, owner_sub: &str) -> Result<Vec<DeviceRecord>, StoreError>;
    /// `StoreError::TooManyDevices` when the owner already has
    /// [`MAX_DEVICES_PER_USER`]; checked and inserted as one step, so two at
    /// once cannot both get the last place.
    async fn insert_device(&self, d: &NewDevice) -> Result<DeviceRecord, StoreError>;
    /// Gives a device a new key. `false` if that device is not this owner's
    /// (or is revoked or unknown).
    async fn replace_key(
        &self,
        id: &str,
        owner_sub: &str,
        key: [u8; 32],
    ) -> Result<bool, StoreError>;
    /// `false` if that device is not this owner's (or is revoked or unknown).
    async fn rename(&self, id: &str, owner_sub: &str, name: &str) -> Result<bool, StoreError>;
    /// `false` if that device is not this owner's, is already revoked, or is
    /// unknown.
    async fn revoke(&self, id: &str, owner_sub: &str) -> Result<bool, StoreError>;
    /// Notes that the device was seen at `at`. Never moves "last seen"
    /// backwards: writes made at once can land in any order, and an older
    /// time arriving late must not win.
    async fn touch_seen(&self, id: &str, at: SystemTime) -> Result<(), StoreError>;
    async fn record_activity(&self, row: &ActivityRow) -> Result<(), StoreError>;
    /// A person's calls, newest first, at most `limit`; for one device or all.
    async fn activity_of(
        &self,
        owner_sub: &str,
        device: Option<&str>,
        limit: u32,
    ) -> Result<Vec<ActivityRow>, StoreError>;
    /// Deletes calls recorded before `t`; how many.
    async fn purge_activity_before(&self, t: SystemTime) -> Result<u64, StoreError>;
    /// Copies `devices` in only if the store holds no device at all (revoked
    /// ones count), as one step. How many were copied; `0` means it was not
    /// empty. For the one-time import of the P1 file
    /// ([`crate::legacy_devices`]).
    async fn import_if_empty(&self, devices: &[NewDevice]) -> Result<u64, StoreError>;
}

// ---------------------------------------------------------------- MemStore

struct MemInner {
    /// In insertion order; `revoked` rows stay.
    devices: Vec<DeviceRecord>,
    revoked: Vec<bool>,
    activity: Vec<ActivityRow>,
}

/// [`Store`] in memory, for unit tests only: it has the same rules as
/// [`PgStore`] (the contract in [`crate::store_contract`] runs against both),
/// and can be told to fail like a database that is down.
pub struct MemStore {
    inner: Mutex<MemInner>,
    fail: Mutex<Option<StoreError>>,
    /// Only writing to the activity log fails (the rest of the store works).
    fail_activity: Mutex<Option<StoreError>>,
    /// While `true`, writing to the activity log waits (a database that has
    /// stopped answering) instead of finishing.
    stall_activity: tokio::sync::watch::Sender<bool>,
    /// While `true`, looking a device up waits.
    stall_devices: tokio::sync::watch::Sender<bool>,
}

impl Default for MemStore {
    fn default() -> Self {
        Self::new()
    }
}

impl MemStore {
    pub fn new() -> Self {
        MemStore {
            inner: Mutex::new(MemInner {
                devices: Vec::new(),
                revoked: Vec::new(),
                activity: Vec::new(),
            }),
            fail: Mutex::new(None),
            fail_activity: Mutex::new(None),
            stall_activity: tokio::sync::watch::channel(false).0,
            stall_devices: tokio::sync::watch::channel(false).0,
        }
    }

    /// Every call answers `error` until this is called with `None`.
    pub fn fail_with(&self, error: Option<StoreError>) {
        *self.fail.lock().unwrap() = error;
    }

    /// Recording a call answers `error` until this is called with `None`;
    /// everything else keeps working. For showing that a call is never
    /// failed by its own log line.
    pub fn fail_activity_writes_with(&self, error: Option<StoreError>) {
        *self.fail_activity.lock().unwrap() = error;
    }

    /// Writing a call to the activity log waits while `stalled` is true, and
    /// goes on when it is set back to false.
    pub fn stall_activity_writes(&self, stalled: bool) {
        self.stall_activity.send_replace(stalled);
    }

    /// Looking a device up (`device`) waits while `stalled` is true.
    pub fn stall_device_lookups(&self, stalled: bool) {
        self.stall_devices.send_replace(stalled);
    }

    fn check(&self) -> Result<(), StoreError> {
        match *self.fail.lock().unwrap() {
            Some(e) => Err(e),
            None => Ok(()),
        }
    }
}

fn to_record(d: &NewDevice) -> DeviceRecord {
    DeviceRecord {
        device_id: d.device_id.clone(),
        owner_sub: d.owner_sub.clone(),
        name: d.name.clone(),
        public_key_ed25519: d.public_key_ed25519,
        created_at: SystemTime::now(),
        last_seen: None,
        revoked: false,
    }
}

#[async_trait]
impl Store for MemStore {
    async fn device(&self, id: &str) -> Result<Option<DeviceRecord>, StoreError> {
        let _ = self
            .stall_devices
            .subscribe()
            .wait_for(|stalled| !*stalled)
            .await;
        self.check()?;
        let m = self.inner.lock().unwrap();
        Ok(m.devices
            .iter()
            .zip(&m.revoked)
            .find(|(d, revoked)| d.device_id == id && !**revoked)
            .map(|(d, _)| d.clone()))
    }

    async fn revoked_device(&self, id: &str) -> Result<Option<DeviceRecord>, StoreError> {
        self.check()?;
        let m = self.inner.lock().unwrap();
        Ok(m.devices
            .iter()
            .zip(&m.revoked)
            .find(|(d, revoked)| d.device_id == id && **revoked)
            .map(|(d, _)| DeviceRecord {
                revoked: true,
                ..d.clone()
            }))
    }

    async fn devices_of(&self, owner_sub: &str) -> Result<Vec<DeviceRecord>, StoreError> {
        self.check()?;
        let m = self.inner.lock().unwrap();
        Ok(m.devices
            .iter()
            .zip(&m.revoked)
            .filter(|(d, revoked)| d.owner_sub == owner_sub && !**revoked)
            .map(|(d, _)| d.clone())
            .collect())
    }

    async fn insert_device(&self, d: &NewDevice) -> Result<DeviceRecord, StoreError> {
        self.check()?;
        let mut m = self.inner.lock().unwrap();
        let active = m
            .devices
            .iter()
            .zip(&m.revoked)
            .filter(|(x, revoked)| x.owner_sub == d.owner_sub && !**revoked)
            .count();
        if active >= MAX_DEVICES_PER_USER {
            return Err(StoreError::TooManyDevices);
        }
        if m.devices.iter().any(|x| x.device_id == d.device_id) {
            // The database's primary key refuses a repeated id too.
            return Err(StoreError::DuplicateId);
        }
        let rec = to_record(d);
        m.devices.push(rec.clone());
        m.revoked.push(false);
        Ok(rec)
    }

    async fn replace_key(
        &self,
        id: &str,
        owner_sub: &str,
        key: [u8; 32],
    ) -> Result<bool, StoreError> {
        self.check()?;
        let mut m = self.inner.lock().unwrap();
        let MemInner {
            devices, revoked, ..
        } = &mut *m;
        for (d, revoked) in devices.iter_mut().zip(revoked.iter()) {
            if d.device_id == id && d.owner_sub == owner_sub && !*revoked {
                d.public_key_ed25519 = key;
                return Ok(true);
            }
        }
        Ok(false)
    }

    async fn rename(&self, id: &str, owner_sub: &str, name: &str) -> Result<bool, StoreError> {
        self.check()?;
        let mut m = self.inner.lock().unwrap();
        let MemInner {
            devices, revoked, ..
        } = &mut *m;
        for (d, revoked) in devices.iter_mut().zip(revoked.iter()) {
            if d.device_id == id && d.owner_sub == owner_sub && !*revoked {
                d.name = name.to_string();
                return Ok(true);
            }
        }
        Ok(false)
    }

    async fn revoke(&self, id: &str, owner_sub: &str) -> Result<bool, StoreError> {
        self.check()?;
        let mut m = self.inner.lock().unwrap();
        let MemInner {
            devices, revoked, ..
        } = &mut *m;
        for (d, revoked) in devices.iter().zip(revoked.iter_mut()) {
            if d.device_id == id && d.owner_sub == owner_sub && !*revoked {
                *revoked = true;
                return Ok(true);
            }
        }
        Ok(false)
    }

    async fn touch_seen(&self, id: &str, at: SystemTime) -> Result<(), StoreError> {
        self.check()?;
        let mut m = self.inner.lock().unwrap();
        let MemInner {
            devices, revoked, ..
        } = &mut *m;
        for (d, revoked) in devices.iter_mut().zip(revoked.iter()) {
            if d.device_id == id && !*revoked {
                d.last_seen = Some(d.last_seen.map_or(at, |old| old.max(at)));
            }
        }
        Ok(())
    }

    async fn record_activity(&self, row: &ActivityRow) -> Result<(), StoreError> {
        let _ = self
            .stall_activity
            .subscribe()
            .wait_for(|stalled| !*stalled)
            .await;
        self.check()?;
        if let Some(e) = *self.fail_activity.lock().unwrap() {
            return Err(e);
        }
        self.inner.lock().unwrap().activity.push(row.clone());
        Ok(())
    }

    async fn activity_of(
        &self,
        owner_sub: &str,
        device: Option<&str>,
        limit: u32,
    ) -> Result<Vec<ActivityRow>, StoreError> {
        self.check()?;
        let m = self.inner.lock().unwrap();
        let mut rows: Vec<(usize, &ActivityRow)> = m
            .activity
            .iter()
            .enumerate()
            .filter(|(_, r)| r.owner_sub == owner_sub && device.is_none_or(|d| r.device_id == d))
            .collect();
        // Newest first; of two at the same instant, the one recorded last.
        rows.sort_by(|(ia, a), (ib, b)| b.at.cmp(&a.at).then(ib.cmp(ia)));
        Ok(rows
            .into_iter()
            .take(limit as usize)
            .map(|(_, r)| r.clone())
            .collect())
    }

    async fn purge_activity_before(&self, t: SystemTime) -> Result<u64, StoreError> {
        self.check()?;
        let mut m = self.inner.lock().unwrap();
        let before = m.activity.len();
        m.activity.retain(|r| r.at >= t);
        Ok((before - m.activity.len()) as u64)
    }

    async fn import_if_empty(&self, devices: &[NewDevice]) -> Result<u64, StoreError> {
        self.check()?;
        let mut m = self.inner.lock().unwrap();
        if !m.devices.is_empty() {
            return Ok(0);
        }
        for d in devices {
            m.devices.push(to_record(d));
            m.revoked.push(false);
        }
        Ok(devices.len() as u64)
    }
}

// ----------------------------------------------------------------- PgStore

/// Applied in order, once each, by [`PgStore::connect`].
const MIGRATIONS: &[(i32, &str)] = &[(1, include_str!("../migrations/0001_init.sql"))];

/// The schema version a fresh database ends at.
pub const SCHEMA_VERSION: i32 = 1;

/// Every relay holds this advisory lock while it migrates, so two starting at
/// once cannot apply the same migration twice.
const MIGRATION_LOCK: i64 = 7313;

/// How long a start waits for the database and its migrations.
const MIGRATE_TIMEOUT: Duration = Duration::from_secs(60);

pub struct PgStore {
    pool: Pool,
    log: LogSink,
}

/// A pooled connection and the time by which the operation using it must be
/// over.
struct Conn {
    obj: deadpool_postgres::Object,
    deadline: tokio::time::Instant,
}

impl std::ops::Deref for Conn {
    type Target = deadpool_postgres::Object;
    fn deref(&self) -> &Self::Target {
        &self.obj
    }
}

impl std::ops::DerefMut for Conn {
    fn deref_mut(&mut self) -> &mut Self::Target {
        &mut self.obj
    }
}

/// TLS that checks the server: against `ca_file` (the CNPG cluster's CA) when
/// given, else the system's certificates.
fn tls_connector(
    ca_file: Option<&Path>,
) -> Result<tokio_postgres_rustls::MakeRustlsConnect, String> {
    use rustls::pki_types::pem::PemObject;
    use rustls::pki_types::CertificateDer;

    let mut roots = rustls::RootCertStore::empty();
    match ca_file {
        Some(path) => {
            let mut added = 0;
            for cert in CertificateDer::pem_file_iter(path)
                .map_err(|e| format!("cannot read the database CA file {}: {e}", path.display()))?
            {
                let cert = cert.map_err(|e| {
                    format!("the database CA file {} is not valid: {e}", path.display())
                })?;
                roots.add(cert).map_err(|e| {
                    format!("the database CA file {} is not valid: {e}", path.display())
                })?;
                added += 1;
            }
            if added == 0 {
                return Err(format!(
                    "the database CA file {} holds no certificate",
                    path.display()
                ));
            }
        }
        None => {
            let native = rustls_native_certs::load_native_certs();
            roots.add_parsable_certificates(native.certs);
            if roots.is_empty() {
                return Err(
                    "no system certificates to check the database with; set DATABASE_CA_FILE to the database's CA".into(),
                );
            }
        }
    }
    let config = rustls::ClientConfig::builder_with_provider(Arc::new(
        rustls::crypto::ring::default_provider(),
    ))
    .with_safe_default_protocol_versions()
    .map_err(|e| format!("cannot set up TLS for the database: {e}"))?
    .with_root_certificates(roots)
    .with_no_client_auth();
    Ok(tokio_postgres_rustls::MakeRustlsConnect::new(config))
}

fn key_from(bytes: Vec<u8>) -> Option<[u8; 32]> {
    <[u8; 32]>::try_from(bytes).ok()
}

fn to_i32(n: Option<u32>) -> Option<i32> {
    n.map(|n| i32::try_from(n).unwrap_or(i32::MAX))
}

fn from_i32(n: Option<i32>) -> Option<u32> {
    n.map(|n| u32::try_from(n).unwrap_or(0))
}

impl PgStore {
    /// Connects, and brings the schema up to date (see [`MIGRATIONS`]).
    ///
    /// The connection is TLS checked against the server's certificate, unless
    /// the URL says `sslmode=disable` (tests against a local database). Any
    /// other `sslmode` is treated as `require`: there is no quiet fallback to
    /// plain text. `Err` is a plain-English reason for the person starting the
    /// relay.
    pub async fn connect(
        database_url: &str,
        ca_file: Option<&Path>,
        log: LogSink,
    ) -> Result<PgStore, String> {
        let mut config: tokio_postgres::Config = database_url.parse().map_err(|_| {
            "DATABASE_URL is not a valid Postgres URL (postgres://user:password@host:5432/dbname)"
                .to_string()
        })?;
        config.connect_timeout(STORE_TIMEOUT);
        let manager_config = ManagerConfig {
            // Checks a connection is alive each time it is handed out, so one
            // the database dropped is replaced, not tried.
            recycling_method: RecyclingMethod::Verified,
        };
        let manager = if config.get_ssl_mode() == SslMode::Disable {
            Manager::from_config(config, NoTls, manager_config)
        } else {
            config.ssl_mode(SslMode::Require);
            Manager::from_config(config, tls_connector(ca_file)?, manager_config)
        };
        let pool = Pool::builder(manager)
            .max_size(POOL_SIZE)
            .wait_timeout(Some(STORE_TIMEOUT))
            .create_timeout(Some(STORE_TIMEOUT))
            .recycle_timeout(Some(STORE_TIMEOUT))
            .runtime(Runtime::Tokio1)
            .build()
            .map_err(|e| format!("cannot set up the database connection pool: {e}"))?;
        let store = PgStore { pool, log };
        match tokio::time::timeout(MIGRATE_TIMEOUT, store.migrate()).await {
            Ok(Ok(())) => Ok(store),
            Ok(Err(e)) => Err(e),
            Err(_) => Err(format!(
                "the database did not finish its set-up within {} s; check that relay-db is running",
                MIGRATE_TIMEOUT.as_secs()
            )),
        }
    }

    async fn migrate(&self) -> Result<(), String> {
        let mut client = self.pool.get().await.map_err(|e| {
            format!(
                "cannot reach the database: {e}. Check DATABASE_URL and that relay-db is running"
            )
        })?;
        let why = |e: tokio_postgres::Error| format!("the database set-up failed: {e}");
        client
            .execute("SELECT pg_advisory_lock($1)", &[&MIGRATION_LOCK])
            .await
            .map_err(why)?;
        let result = Self::apply_migrations(&mut client).await;
        self.release_migration_lock(client).await;
        result.map_err(why)
    }

    /// Lets go of the migration lock, which this connection holds for the
    /// session. If that fails, or the lock was not held, say so in the log and
    /// close the connection instead of returning it to the pool: closing it
    /// ends the session, and with it any lock it still holds, so a stuck lock
    /// cannot block the next relay's migrations. `true` if the lock was
    /// released cleanly.
    async fn release_migration_lock(&self, client: deadpool_postgres::Object) -> bool {
        let released = match client
            .query_one("SELECT pg_advisory_unlock($1)", &[&MIGRATION_LOCK])
            .await
        {
            Ok(row) => row.get::<_, bool>(0),
            Err(e) => {
                log_event(
                    &self.log,
                    "migration_lock_warning",
                    json!({"problem": "the unlock failed", "error": e.to_string()}),
                );
                drop(deadpool_postgres::Object::take(client));
                return false;
            }
        };
        if !released {
            log_event(
                &self.log,
                "migration_lock_warning",
                json!({"problem": "the migration lock was not held by this connection"}),
            );
            drop(deadpool_postgres::Object::take(client));
        }
        released
    }

    /// Test support: takes a connection that holds no lock and runs the
    /// release on it, as a failed release would. `false` (and a log line,
    /// and the connection closed) is the right answer.
    #[doc(hidden)]
    pub async fn release_unheld_migration_lock(&self) -> bool {
        match self.pool.get().await {
            Ok(client) => self.release_migration_lock(client).await,
            Err(_) => false,
        }
    }

    async fn apply_migrations(client: &mut Client) -> Result<(), tokio_postgres::Error> {
        let tx = client.transaction().await?;
        tx.batch_execute("CREATE TABLE IF NOT EXISTS schema_version (version integer NOT NULL)")
            .await?;
        let current: i32 = tx
            .query_one("SELECT COALESCE(max(version), 0) FROM schema_version", &[])
            .await?
            .get(0);
        for (version, sql) in MIGRATIONS.iter().filter(|(v, _)| *v > current) {
            tx.batch_execute(sql).await?;
            tx.execute(
                "INSERT INTO schema_version (version) VALUES ($1)",
                &[version],
            )
            .await?;
        }
        tx.commit().await
    }

    /// The error for a failed step: logged with what it was doing, and
    /// answered as [`StoreError::Unavailable`].
    fn failed(&self, op: &str, why: impl fmt::Display) -> StoreError {
        log_event(
            &self.log,
            "store_error",
            json!({"op": op, "error": why.to_string()}),
        );
        StoreError::Unavailable
    }

    /// A connection from the pool. The clock on the whole operation starts
    /// here: getting the connection and running the query share one
    /// [`STORE_TIMEOUT`] (`Conn::deadline`, used by [`PgStore::timed`]), so
    /// the person waits at most that long, not twice it.
    async fn client(&self, op: &str) -> Result<Conn, StoreError> {
        let deadline = tokio::time::Instant::now() + STORE_TIMEOUT;
        match tokio::time::timeout_at(deadline, self.pool.get()).await {
            Ok(Ok(obj)) => Ok(Conn { obj, deadline }),
            Ok(Err(e)) => Err(self.failed(op, e)),
            Err(_) => Err(self.failed(op, "timed out getting a connection")),
        }
    }

    /// Runs one step against the database, up to the operation's deadline.
    async fn timed<T>(
        &self,
        op: &str,
        deadline: tokio::time::Instant,
        step: impl std::future::Future<Output = Result<T, tokio_postgres::Error>>,
    ) -> Result<T, StoreError> {
        match tokio::time::timeout_at(deadline, step).await {
            Ok(Ok(v)) => Ok(v),
            Ok(Err(e)) => Err(self.failed(op, e)),
            Err(_) => Err(self.failed(op, "timed out")),
        }
    }

    fn record(&self, op: &str, row: &tokio_postgres::Row) -> Result<DeviceRecord, StoreError> {
        let key: Vec<u8> = row.get("public_key");
        let Some(public_key_ed25519) = key_from(key) else {
            return Err(self.failed(op, "a stored public key is not 32 bytes"));
        };
        Ok(DeviceRecord {
            device_id: row.get("id"),
            owner_sub: row.get("owner_sub"),
            name: row.get("name"),
            public_key_ed25519,
            created_at: row.get("created_at"),
            last_seen: row.get("last_seen"),
            revoked: false,
        })
    }
}

const DEVICE_COLUMNS: &str = "id, owner_sub, name, public_key, created_at, last_seen";

#[async_trait]
impl Store for PgStore {
    async fn device(&self, id: &str) -> Result<Option<DeviceRecord>, StoreError> {
        let c = self.client("device").await?;
        let row = self
            .timed(
                "device",
                c.deadline,
                c.query_opt(
                    &format!(
                        "SELECT {DEVICE_COLUMNS} FROM devices WHERE id = $1 AND revoked_at IS NULL"
                    ),
                    &[&id],
                ),
            )
            .await?;
        row.map(|r| self.record("device", &r)).transpose()
    }

    async fn revoked_device(&self, id: &str) -> Result<Option<DeviceRecord>, StoreError> {
        let c = self.client("revoked_device").await?;
        let row = self
            .timed(
                "revoked_device",
                c.deadline,
                c.query_opt(
                    &format!(
                        "SELECT {DEVICE_COLUMNS} FROM devices \
                         WHERE id = $1 AND revoked_at IS NOT NULL"
                    ),
                    &[&id],
                ),
            )
            .await?;
        row.map(|r| {
            self.record("revoked_device", &r)
                .map(|d| DeviceRecord { revoked: true, ..d })
        })
        .transpose()
    }

    async fn devices_of(&self, owner_sub: &str) -> Result<Vec<DeviceRecord>, StoreError> {
        let c = self.client("devices_of").await?;
        let rows = self
            .timed(
                "devices_of",
                c.deadline,
                c.query(
                    &format!(
                        "SELECT {DEVICE_COLUMNS} FROM devices \
                         WHERE owner_sub = $1 AND revoked_at IS NULL ORDER BY created_at, id"
                    ),
                    &[&owner_sub],
                ),
            )
            .await?;
        rows.iter().map(|r| self.record("devices_of", r)).collect()
    }

    async fn insert_device(&self, d: &NewDevice) -> Result<DeviceRecord, StoreError> {
        let mut c = self.client("insert_device").await?;
        let key: &[u8] = &d.public_key_ed25519;
        let inserted = self
            .timed("insert_device", c.deadline, async {
                let tx = c.transaction().await?;
                // One at a time per person, so the count below cannot be
                // outrun by a second insert for the same person.
                tx.execute(
                    "SELECT pg_advisory_xact_lock(hashtextextended($1, 0))",
                    &[&d.owner_sub],
                )
                .await?;
                let active: i64 = tx
                    .query_one(
                        "SELECT count(*) FROM devices WHERE owner_sub = $1 AND revoked_at IS NULL",
                        &[&d.owner_sub],
                    )
                    .await?
                    .get(0);
                if active >= MAX_DEVICES_PER_USER as i64 {
                    return Ok(Err(StoreError::TooManyDevices));
                }
                let row = match tx
                    .query_one(
                        &format!(
                            "INSERT INTO devices (id, owner_sub, name, public_key) \
                             VALUES ($1, $2, $3, $4) RETURNING {DEVICE_COLUMNS}"
                        ),
                        &[&d.device_id, &d.owner_sub, &d.name, &key],
                    )
                    .await
                {
                    Ok(row) => row,
                    // The id is the primary key: this id is taken (the
                    // transaction rolls back as `tx` drops).
                    Err(e) if e.code() == Some(&SqlState::UNIQUE_VIOLATION) => {
                        return Ok(Err(StoreError::DuplicateId));
                    }
                    Err(e) => return Err(e),
                };
                tx.commit().await?;
                Ok(Ok(row))
            })
            .await?;
        self.record("insert_device", &inserted?)
    }

    async fn replace_key(
        &self,
        id: &str,
        owner_sub: &str,
        key: [u8; 32],
    ) -> Result<bool, StoreError> {
        let c = self.client("replace_key").await?;
        let key: &[u8] = &key;
        let n = self
            .timed(
                "replace_key",
                c.deadline,
                c.execute(
                    "UPDATE devices SET public_key = $3 \
                     WHERE id = $1 AND owner_sub = $2 AND revoked_at IS NULL",
                    &[&id, &owner_sub, &key],
                ),
            )
            .await?;
        Ok(n > 0)
    }

    async fn rename(&self, id: &str, owner_sub: &str, name: &str) -> Result<bool, StoreError> {
        let c = self.client("rename").await?;
        let n = self
            .timed(
                "rename",
                c.deadline,
                c.execute(
                    "UPDATE devices SET name = $3 \
                     WHERE id = $1 AND owner_sub = $2 AND revoked_at IS NULL",
                    &[&id, &owner_sub, &name],
                ),
            )
            .await?;
        Ok(n > 0)
    }

    async fn revoke(&self, id: &str, owner_sub: &str) -> Result<bool, StoreError> {
        let c = self.client("revoke").await?;
        let n = self
            .timed(
                "revoke",
                c.deadline,
                c.execute(
                    "UPDATE devices SET revoked_at = now() \
                     WHERE id = $1 AND owner_sub = $2 AND revoked_at IS NULL",
                    &[&id, &owner_sub],
                ),
            )
            .await?;
        Ok(n > 0)
    }

    async fn touch_seen(&self, id: &str, at: SystemTime) -> Result<(), StoreError> {
        let c = self.client("touch_seen").await?;
        self.timed(
            "touch_seen",
            c.deadline,
            c.execute(
                "UPDATE devices SET last_seen = GREATEST(last_seen, $2) \
                 WHERE id = $1 AND revoked_at IS NULL",
                &[&id, &at],
            ),
        )
        .await?;
        Ok(())
    }

    async fn record_activity(&self, row: &ActivityRow) -> Result<(), StoreError> {
        let c = self.client("record_activity").await?;
        self.timed("record_activity", c.deadline,
            c.execute(
                "INSERT INTO activity \
                 (at, owner_sub, device_id, client_id, tool, arg_bytes, result_bytes, duration_ms, outcome) \
                 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)",
                &[
                    &row.at,
                    &row.owner_sub,
                    &row.device_id,
                    &row.client_id,
                    &row.tool,
                    &to_i32(row.arg_bytes),
                    &to_i32(row.result_bytes),
                    &to_i32(row.duration_ms),
                    &row.outcome,
                ],
            ),
        )
        .await?;
        Ok(())
    }

    async fn activity_of(
        &self,
        owner_sub: &str,
        device: Option<&str>,
        limit: u32,
    ) -> Result<Vec<ActivityRow>, StoreError> {
        let c = self.client("activity_of").await?;
        let limit = i64::from(limit);
        let rows = self
            .timed(
                "activity_of",
                c.deadline,
                c.query(
                    "SELECT at, owner_sub, device_id, client_id, tool, arg_bytes, result_bytes, \
                            duration_ms, outcome \
                     FROM activity \
                     WHERE owner_sub = $1 AND ($2::text IS NULL OR device_id = $2) \
                     ORDER BY at DESC, id DESC LIMIT $3",
                    &[&owner_sub, &device, &limit],
                ),
            )
            .await?;
        Ok(rows
            .iter()
            .map(|r| ActivityRow {
                at: r.get("at"),
                owner_sub: r.get("owner_sub"),
                device_id: r.get("device_id"),
                client_id: r.get("client_id"),
                tool: r.get("tool"),
                arg_bytes: from_i32(r.get("arg_bytes")),
                result_bytes: from_i32(r.get("result_bytes")),
                duration_ms: from_i32(r.get("duration_ms")),
                outcome: r.get("outcome"),
            })
            .collect())
    }

    async fn purge_activity_before(&self, t: SystemTime) -> Result<u64, StoreError> {
        let c = self.client("purge_activity_before").await?;
        self.timed(
            "purge_activity_before",
            c.deadline,
            c.execute("DELETE FROM activity WHERE at < $1", &[&t]),
        )
        .await
    }

    async fn import_if_empty(&self, devices: &[NewDevice]) -> Result<u64, StoreError> {
        let mut c = self.client("import_if_empty").await?;
        self.timed("import_if_empty", c.deadline, async {
            let tx = c.transaction().await?;
            // The migrations' lock: an import never runs inside another
            // relay's migration.
            tx.execute(
                &format!("SELECT pg_advisory_xact_lock({MIGRATION_LOCK})"),
                &[],
            )
            .await?;
            let existing: i64 = tx
                .query_one("SELECT count(*) FROM devices", &[])
                .await?
                .get(0);
            if existing > 0 {
                return Ok(0);
            }
            for d in devices {
                let key: &[u8] = &d.public_key_ed25519;
                tx.execute(
                    "INSERT INTO devices (id, owner_sub, name, public_key) VALUES ($1, $2, $3, $4)",
                    &[&d.device_id, &d.owner_sub, &d.name, &key],
                )
                .await?;
            }
            tx.commit().await?;
            Ok(devices.len() as u64)
        })
        .await
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::store_contract::store_contract;

    #[tokio::test]
    async fn store_contract_mem() {
        store_contract(&MemStore::new()).await;
    }

    #[test]
    fn the_down_message_is_plain_and_says_what_to_do() {
        assert_eq!(
            StoreError::Unavailable.to_string(),
            "The relay is having trouble right now; try again in a minute."
        );
        let full = StoreError::TooManyDevices.to_string();
        assert_eq!(
            full,
            "You already have 5 computers connected. Remove one in the dashboard first."
        );
        assert_eq!(STORE_UNAVAILABLE_OUTCOME, "store_unavailable");
    }

    #[test]
    fn schema_version_matches_the_migration_list() {
        assert_eq!(MIGRATIONS.last().map(|m| m.0), Some(SCHEMA_VERSION));
        assert!(MIGRATIONS.windows(2).all(|w| w[0].0 < w[1].0));
    }

    /// A throwaway CA certificate (public part only), for the checks below.
    const TEST_CA_PEM: &str = "-----BEGIN CERTIFICATE-----
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

    fn temp_file(name: &str, contents: &str) -> std::path::PathBuf {
        let dir = std::env::var_os("TEST_TMPDIR")
            .map(std::path::PathBuf::from)
            .unwrap_or_else(std::env::temp_dir)
            .join(format!("relay-store-{}-{name}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("ca.crt");
        std::fs::write(&path, contents).unwrap();
        path
    }

    #[test]
    fn the_database_ca_file_is_read_and_a_bad_one_is_refused() {
        assert!(tls_connector(Some(&temp_file("good", TEST_CA_PEM))).is_ok());
        for (name, body) in [
            ("empty", ""),
            ("not-pem", "hello"),
            ("cut", "-----BEGIN CERTIFICATE-----\nAAAA\n"),
        ] {
            let err = tls_connector(Some(&temp_file(name, body)))
                .err()
                .unwrap_or_else(|| panic!("{name} must be refused"));
            assert!(err.contains("CA file"), "{name}: {err}");
        }
        assert!(tls_connector(Some(Path::new("/no/such/ca.crt"))).is_err());
    }

    #[tokio::test]
    async fn a_bad_database_url_is_refused_in_plain_words() {
        let log: LogSink = Arc::new(|_| {});
        let err = PgStore::connect("not a url", None, log)
            .await
            .err()
            .expect("refused");
        assert!(err.contains("DATABASE_URL"), "{err}");
    }

    #[tokio::test]
    async fn a_failing_mem_store_answers_unavailable_until_it_recovers() {
        let s = MemStore::new();
        s.fail_with(Some(StoreError::Unavailable));
        assert_eq!(s.device("x").await, Err(StoreError::Unavailable));
        assert_eq!(s.devices_of("x").await, Err(StoreError::Unavailable));
        s.fail_with(None);
        assert_eq!(s.device("x").await, Ok(None));
    }

    fn row_at(at: SystemTime, tool: &str) -> ActivityRow {
        ActivityRow {
            at,
            owner_sub: "alice".into(),
            device_id: "d1".into(),
            client_id: "claude".into(),
            tool: tool.into(),
            arg_bytes: Some(1),
            result_bytes: Some(2),
            duration_ms: Some(3),
            outcome: "ok".into(),
        }
    }

    #[tokio::test]
    async fn purge_removes_rows_older_than_30_days() {
        assert_eq!(ACTIVITY_RETENTION_DAYS, 30);
        let day = Duration::from_secs(24 * 60 * 60);
        let now = SystemTime::now();
        let s = MemStore::new();
        for (days, tool) in [
            (45, "old"),
            (31, "just_over"),
            (29, "just_under"),
            (0, "new"),
        ] {
            s.record_activity(&row_at(now - day * days, tool))
                .await
                .unwrap();
        }
        assert_eq!(purge_expired_activity(&s, now).await, Ok(2));
        let kept: Vec<String> = s
            .activity_of("alice", None, 10)
            .await
            .unwrap()
            .into_iter()
            .map(|r| r.tool)
            .collect();
        assert_eq!(kept, ["new", "just_under"]);
        // Nothing more to remove the next time.
        assert_eq!(purge_expired_activity(&s, now).await, Ok(0));
    }

    #[tokio::test]
    async fn the_purge_loop_logs_what_it_removed_and_survives_a_failing_store() {
        let day = Duration::from_secs(24 * 60 * 60);
        let s = Arc::new(MemStore::new());
        s.record_activity(&row_at(SystemTime::now() - day * 40, "old"))
            .await
            .unwrap();
        let lines = Arc::new(Mutex::new(Vec::<String>::new()));
        let sink_lines = lines.clone();
        let log: LogSink = Arc::new(move |l| sink_lines.lock().unwrap().push(l.to_string()));
        let task = tokio::spawn(purge_activity_forever(
            s.clone(),
            log,
            Duration::from_millis(20),
        ));
        let has = |needle: &str| lines.lock().unwrap().iter().any(|l| l.contains(needle));
        tokio::time::timeout(Duration::from_secs(10), async {
            while !has("\"activity_purged\"") {
                tokio::time::sleep(Duration::from_millis(5)).await;
            }
        })
        .await
        .expect("the old row was purged and logged");
        s.fail_with(Some(StoreError::Unavailable));
        tokio::time::timeout(Duration::from_secs(10), async {
            while !has("\"activity_purge_failed\"") {
                tokio::time::sleep(Duration::from_millis(5)).await;
            }
        })
        .await
        .expect("a failure is logged");
        assert!(!task.is_finished(), "a failed purge does not stop the loop");
        task.abort();
    }
}
