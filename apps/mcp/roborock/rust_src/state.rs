// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
// SPDX-License-Identifier: MIT

//! What the daemon knows about the vacuum, and the loop that keeps it current.

use crate::auth;
use crate::config::{self, Credentials};
use crate::device::{DeviceError, RoborockVacuum, Vacuum};
use serde_json::{json, Map, Value};
use std::collections::VecDeque;
use std::fmt;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Condvar, Mutex};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

pub type Event = (String, Map<String, Value>);
pub type VacuumFactory = Arc<dyn Fn(&Credentials) -> Arc<dyn Vacuum> + Send + Sync>;

const PARKED_STATES: &[i64] = &[2, 3, 8, 100];
pub const SUBSCRIBER_BACKLOG: usize = 32;

static SUBSCRIBER_ID: AtomicU64 = AtomicU64::new(1);

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ServiceUnavailable {
    pub code: String,
    pub message: String,
}

impl ServiceUnavailable {
    pub fn new(code: impl Into<String>, message: impl Into<String>) -> Self {
        Self {
            code: code.into(),
            message: message.into(),
        }
    }
}

impl fmt::Display for ServiceUnavailable {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.message)
    }
}

impl std::error::Error for ServiceUnavailable {}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CommandError {
    Unavailable(ServiceUnavailable),
    Device(DeviceError),
}

impl fmt::Display for CommandError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Unavailable(u) => write!(f, "{u}"),
            Self::Device(d) => write!(f, "{d}"),
        }
    }
}

impl std::error::Error for CommandError {}

pub struct SubscriberQueue {
    id: u64,
    items: Mutex<VecDeque<Option<Event>>>,
    cv: Condvar,
}

impl SubscriberQueue {
    fn new() -> Self {
        Self {
            id: SUBSCRIBER_ID.fetch_add(1, Ordering::Relaxed),
            items: Mutex::new(VecDeque::with_capacity(SUBSCRIBER_BACKLOG)),
            cv: Condvar::new(),
        }
    }

    pub fn maxsize(&self) -> usize {
        SUBSCRIBER_BACKLOG
    }

    pub fn qsize(&self) -> usize {
        self.items.lock().unwrap_or_else(|e| e.into_inner()).len()
    }

    pub fn is_empty(&self) -> bool {
        self.qsize() == 0
    }

    pub fn get_nowait(&self) -> Option<Option<Event>> {
        self.items
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .pop_front()
    }

    pub fn get_timeout(&self, timeout: Duration) -> Result<Option<Event>, ()> {
        let mut guard = self.items.lock().unwrap_or_else(|e| e.into_inner());
        if let Some(ev) = guard.pop_front() {
            return Ok(ev);
        }
        let (mut guard, wait_res) = self
            .cv
            .wait_timeout(guard, timeout)
            .unwrap_or_else(|e| e.into_inner());
        if let Some(ev) = guard.pop_front() {
            Ok(ev)
        } else if wait_res.timed_out() {
            Err(())
        } else {
            Err(())
        }
    }

    fn offer(&self, event: Option<Event>) {
        let mut guard = self.items.lock().unwrap_or_else(|e| e.into_inner());
        if guard.len() >= SUBSCRIBER_BACKLOG {
            guard.pop_front();
        }
        guard.push_back(event);
        self.cv.notify_one();
    }
}

struct StoreInner {
    status: Map<String, Value>,
    map_png: Option<Vec<u8>>,
    map_digest: Option<String>,
    map_version: u64,
    subscribers: Vec<Arc<SubscriberQueue>>,
}

pub struct StateStore {
    inner: Mutex<StoreInner>,
}

impl Default for StateStore {
    fn default() -> Self {
        Self::new()
    }
}

impl StateStore {
    pub fn new() -> Self {
        let mut initial = Map::new();
        initial.insert("authenticated".to_string(), Value::Bool(false));
        initial.insert("connected".to_string(), Value::Bool(false));
        initial.insert("map_version".to_string(), Value::from(0u64));
        Self {
            inner: Mutex::new(StoreInner {
                status: initial,
                map_png: None,
                map_digest: None,
                map_version: 0,
                subscribers: Vec::new(),
            }),
        }
    }

    pub fn status(&self) -> Map<String, Value> {
        self.inner
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .status
            .clone()
    }

    pub fn map_png(&self) -> Option<Vec<u8>> {
        self.inner
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .map_png
            .clone()
    }

    pub fn map_version(&self) -> u64 {
        self.inner
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .map_version
    }

    pub fn set_status(&self, mut status: Map<String, Value>) -> bool {
        let mut guard = self.inner.lock().unwrap_or_else(|e| e.into_inner());
        status.insert("map_version".to_string(), Value::from(guard.map_version));
        let changed = without_timestamp(&status) != without_timestamp(&guard.status);
        guard.status = status.clone();
        let subs = guard.subscribers.clone();
        drop(guard);
        if changed {
            for sub in subs {
                sub.offer(Some(("status".to_string(), status.clone())));
            }
        }
        changed
    }

    pub fn set_map(&self, png: Option<&[u8]>) -> bool {
        let Some(bytes) = png.filter(|b| !b.is_empty()) else {
            return false;
        };
        let digest = config::sha256_hex(bytes);
        let mut guard = self.inner.lock().unwrap_or_else(|e| e.into_inner());
        if guard.map_digest.as_deref() == Some(digest.as_str()) {
            return false;
        }
        guard.map_png = Some(bytes.to_vec());
        guard.map_digest = Some(digest);
        guard.map_version += 1;
        let version = guard.map_version;
        guard
            .status
            .insert("map_version".to_string(), Value::from(version));
        let subs = guard.subscribers.clone();
        drop(guard);

        let mut payload = Map::new();
        payload.insert("version".to_string(), Value::from(version));
        for sub in subs {
            sub.offer(Some(("map".to_string(), payload.clone())));
        }
        true
    }

    pub fn subscribe(&self) -> Arc<SubscriberQueue> {
        let queue = Arc::new(SubscriberQueue::new());
        self.inner
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .subscribers
            .push(queue.clone());
        queue
    }

    pub fn unsubscribe(&self, queue: &Arc<SubscriberQueue>) {
        self.inner
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .subscribers
            .retain(|q| q.id != queue.id);
    }

    pub fn close(&self) {
        let subs = self
            .inner
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .subscribers
            .clone();
        for sub in subs {
            sub.offer(None);
        }
    }
}

fn without_timestamp(status: &Map<String, Value>) -> Map<String, Value> {
    let mut filtered = status.clone();
    filtered.remove("updated_at");
    filtered
}

#[derive(Clone)]
pub struct ServiceOptions {
    pub poll_parked: Duration,
    pub poll_active: Duration,
    pub map_parked: Duration,
    pub backoff_initial: Duration,
    pub backoff_max: Duration,
}

impl Default for ServiceOptions {
    fn default() -> Self {
        Self {
            poll_parked: Duration::from_secs(60),
            poll_active: Duration::from_secs(10),
            map_parked: Duration::from_secs(600),
            backoff_initial: Duration::from_secs(5),
            backoff_max: Duration::from_secs(300),
        }
    }
}

struct SharedServiceState {
    vacuum: Option<Arc<dyn Vacuum>>,
    unavailable: ServiceUnavailable,
    map_fetched_at: Option<Instant>,
}

struct WakeState {
    woken: bool,
    stopped: bool,
}

pub struct VacuumService {
    store: Arc<StateStore>,
    factory: VacuumFactory,
    options: ServiceOptions,
    shared: Arc<Mutex<SharedServiceState>>,
    command_lock: Arc<Mutex<()>>,
    wake: Arc<(Mutex<WakeState>, Condvar)>,
    worker: Mutex<Option<JoinHandle<()>>>,
}

impl VacuumService {
    pub fn new(
        store: Arc<StateStore>,
        vacuum_factory: Option<VacuumFactory>,
        options: ServiceOptions,
    ) -> Self {
        let factory = vacuum_factory.unwrap_or_else(|| {
            Arc::new(|creds: &Credentials| {
                let device_id = std::env::var(config::DEVICE_ENV)
                    .ok()
                    .filter(|s| !s.is_empty());
                Arc::new(RoborockVacuum::new(creds.clone(), device_id, None))
            })
        });
        Self {
            store,
            factory,
            options,
            shared: Arc::new(Mutex::new(SharedServiceState {
                vacuum: None,
                unavailable: ServiceUnavailable::new(
                    "not_connected",
                    "The daemon has not connected to the vacuum yet.",
                ),
                map_fetched_at: None,
            })),
            command_lock: Arc::new(Mutex::new(())),
            wake: Arc::new((
                Mutex::new(WakeState {
                    woken: false,
                    stopped: false,
                }),
                Condvar::new(),
            )),
            worker: Mutex::new(None),
        }
    }

    pub fn start(&self) {
        let mut worker_guard = self.worker.lock().unwrap_or_else(|e| e.into_inner());
        if worker_guard.is_some() {
            return;
        }
        {
            let mut wake_guard = self.wake.0.lock().unwrap_or_else(|e| e.into_inner());
            wake_guard.stopped = false;
            wake_guard.woken = false;
        }
        let store = self.store.clone();
        let factory = self.factory.clone();
        let options = self.options.clone();
        let shared = self.shared.clone();
        let wake = self.wake.clone();
        let handle = thread::spawn(move || {
            run_service_loop(store, factory, options, shared, wake);
        });
        *worker_guard = Some(handle);
    }

    pub fn stop(&self) {
        let handle = self.worker.lock().unwrap_or_else(|e| e.into_inner()).take();
        if let Some(h) = handle {
            {
                let mut wake_guard = self.wake.0.lock().unwrap_or_else(|e| e.into_inner());
                wake_guard.stopped = true;
                wake_guard.woken = true;
                self.wake.1.notify_all();
            }
            let _ = h.join();
        }
    }

    pub fn reload(&self) {
        self.stop();
        self.start();
    }

    pub fn command(
        &self,
        action: &str,
        params: Option<&Map<String, Value>>,
    ) -> Result<Value, CommandError> {
        let _cmd_guard = self.command_lock.lock().unwrap_or_else(|e| e.into_inner());
        let (vacuum, unavailable) = {
            let guard = self.shared.lock().unwrap_or_else(|e| e.into_inner());
            (guard.vacuum.clone(), guard.unavailable.clone())
        };
        let Some(vacuum) = vacuum else {
            return Err(CommandError::Unavailable(unavailable));
        };
        let result = vacuum
            .command(action, params)
            .map_err(CommandError::Device)?;
        {
            let mut wake_guard = self.wake.0.lock().unwrap_or_else(|e| e.into_inner());
            wake_guard.woken = true;
            self.wake.1.notify_all();
        }
        Ok(result)
    }
}

impl Drop for VacuumService {
    fn drop(&mut self) {
        self.stop();
    }
}

fn run_service_loop(
    store: Arc<StateStore>,
    factory: VacuumFactory,
    options: ServiceOptions,
    shared: Arc<Mutex<SharedServiceState>>,
    wake: Arc<(Mutex<WakeState>, Condvar)>,
) {
    let mut backoff = options.backoff_initial;
    loop {
        if is_stopped(&wake) {
            return;
        }
        let credentials = match auth::require_credentials() {
            Ok(c) => c,
            Err(err) => {
                set_offline(&store, &shared, "not_authenticated", err.message(), false);
                return;
            }
        };
        let vacuum = (factory)(&credentials);
        let connect_res = vacuum.connect();
        match connect_res {
            Ok(()) => {
                let store_for_push = store.clone();
                vacuum.on_update(Arc::new(move |snapshot| {
                    store_for_push.set_status(online_status(snapshot));
                }));
                {
                    let mut guard = shared.lock().unwrap_or_else(|e| e.into_inner());
                    guard.vacuum = Some(vacuum.clone());
                }
                poll_loop(&store, &options, &shared, &wake, &vacuum);
                {
                    let mut guard = shared.lock().unwrap_or_else(|e| e.into_inner());
                    guard.vacuum = None;
                }
                let _ = vacuum.close();
                return;
            }
            Err(err) => {
                set_offline(&store, &shared, "not_connected", err.message(), true);
                {
                    let mut guard = shared.lock().unwrap_or_else(|e| e.into_inner());
                    guard.vacuum = None;
                }
                let _ = vacuum.close();
            }
        }
        if wait_or_stopped(&wake, backoff) {
            return;
        }
        backoff = std::cmp::min(backoff.saturating_mul(2), options.backoff_max);
    }
}

fn poll_loop(
    store: &Arc<StateStore>,
    options: &ServiceOptions,
    shared: &Arc<Mutex<SharedServiceState>>,
    wake: &Arc<(Mutex<WakeState>, Condvar)>,
    vacuum: &Arc<dyn Vacuum>,
) {
    loop {
        {
            let mut wake_guard = wake.0.lock().unwrap_or_else(|e| e.into_inner());
            if wake_guard.stopped {
                return;
            }
            wake_guard.woken = false;
        }
        if vacuum.credentials_rejected() {
            set_offline(
                store,
                shared,
                "not_authenticated",
                "Roborock rejected the stored login. Run `rrctl setup` to log in again.",
                false,
            );
            return;
        }
        let mut active = false;
        match vacuum.status() {
            Ok(snapshot) => {
                active = is_active(&snapshot);
                store.set_status(online_status(snapshot));
                refresh_map(store, options, shared, vacuum, active);
            }
            Err(err) => {
                let mut current = store.status();
                current.insert("connected".to_string(), Value::Bool(false));
                current.insert("error".to_string(), Value::String(err.to_string()));
                current.insert("updated_at".to_string(), Value::from(now_epoch_secs()));
                store.set_status(current);
            }
        }
        let wait_dur = if active {
            options.poll_active
        } else {
            options.poll_parked
        };
        if wait_or_stopped(wake, wait_dur) {
            return;
        }
    }
}

fn refresh_map(
    store: &Arc<StateStore>,
    options: &ServiceOptions,
    shared: &Arc<Mutex<SharedServiceState>>,
    vacuum: &Arc<dyn Vacuum>,
    active: bool,
) {
    let now = Instant::now();
    {
        let mut guard = shared.lock().unwrap_or_else(|e| e.into_inner());
        if store.map_png().is_some() && !active {
            if let Some(prev) = guard.map_fetched_at {
                if now.duration_since(prev) < options.map_parked {
                    return;
                }
            }
        }
        guard.map_fetched_at = Some(now);
    }
    if let Ok(png) = vacuum.map_png() {
        store.set_map(png.as_deref());
    }
}

fn online_status(mut snapshot: Map<String, Value>) -> Map<String, Value> {
    snapshot.insert("authenticated".to_string(), Value::Bool(true));
    snapshot.insert("connected".to_string(), Value::Bool(true));
    snapshot.insert("error".to_string(), Value::Null);
    snapshot.insert("updated_at".to_string(), json!(now_epoch_secs()));
    snapshot
}

fn set_offline(
    store: &Arc<StateStore>,
    shared: &Arc<Mutex<SharedServiceState>>,
    code: &str,
    message: &str,
    authenticated: bool,
) {
    {
        let mut guard = shared.lock().unwrap_or_else(|e| e.into_inner());
        guard.vacuum = None;
        guard.unavailable = ServiceUnavailable::new(code, message);
    }
    let mut status = Map::new();
    status.insert("authenticated".to_string(), Value::Bool(authenticated));
    status.insert("connected".to_string(), Value::Bool(false));
    status.insert("error".to_string(), Value::String(message.to_string()));
    status.insert("updated_at".to_string(), json!(now_epoch_secs()));
    if !authenticated {
        status.insert(
            "hint".to_string(),
            Value::String(auth::SETUP_HINT.to_string()),
        );
    }
    store.set_status(status);
}

fn is_active(snapshot: &Map<String, Value>) -> bool {
    let in_returning = snapshot
        .get("in_returning")
        .and_then(|v| v.as_bool())
        .unwrap_or(false);
    if in_returning {
        return true;
    }
    if let Some(state_code) = snapshot.get("state_code").and_then(|v| v.as_i64()) {
        !PARKED_STATES.contains(&state_code)
    } else {
        false
    }
}

fn is_stopped(wake: &Arc<(Mutex<WakeState>, Condvar)>) -> bool {
    wake.0.lock().unwrap_or_else(|e| e.into_inner()).stopped
}

fn wait_or_stopped(wake: &Arc<(Mutex<WakeState>, Condvar)>, duration: Duration) -> bool {
    let mut guard = wake.0.lock().unwrap_or_else(|e| e.into_inner());
    if guard.stopped {
        return true;
    }
    if guard.woken {
        guard.woken = false;
        return guard.stopped;
    }
    let (guard, _) = wake
        .1
        .wait_timeout(guard, duration)
        .unwrap_or_else(|e| e.into_inner());
    guard.stopped
}

fn now_epoch_secs() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs_f64())
        .unwrap_or(0.0)
}
