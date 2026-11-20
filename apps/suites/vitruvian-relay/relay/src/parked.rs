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

//! Calls that outlive the AI app's wait. Claude gives up on a `tools/call`
//! after about 15 s and sends the same call again; an approval dialog can
//! take longer than that. So a call runs on its own task, not inside the
//! HTTP request, and this table is how a request finds it again:
//!
//! - an identical request (same person, device, tool and arguments) while
//!   the call is open, or finished but not yet handed to anyone, joins it
//!   instead of starting a second one;
//! - a request id given out with the "waiting" reply lets the person fetch
//!   the result with the relay's `check_request` tool.
//!
//! Every call is entered here as it starts (so a retry can find it), and
//! leaves again when its answer is handed over, unless it was parked: its
//! request went away, or its id was given out. Parked results are kept for
//! `result_ttl` after they finish, then dropped.

use std::collections::HashMap;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex, Once, OnceLock};
use std::time::{Duration, Instant};

use ring::digest;
use serde_json::Value;
use tokio::sync::watch;
use tokio::task::AbortHandle;
use vitruvian_relay_protocol::{Call, CallResult};

use crate::random_id;
use crate::registry::{CallError, Registry};

/// What a call came to: the device's result, or why there is none.
pub type Outcome = Result<CallResult, CallError>;

/// The text for a request id that is unknown, expired or someone else's.
/// One text for all three, so an id says nothing about whose it is.
pub const UNKNOWN_REQUEST: &str =
    "That request has finished or expired. Send the original request again.";

/// Identifies "the same call again": a hash of the person, the device, the
/// tool and the arguments (keys sorted, so key order does not matter).
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct RejoinKey([u8; 32]);

impl RejoinKey {
    pub fn new(subject: &str, device_id: &str, tool: &str, arguments: &Value) -> Self {
        let mut ctx = digest::Context::new(&digest::SHA256);
        // Each part length-prefixed: no choice of parts can read as another.
        for part in [subject, device_id, tool, &canonical_json(arguments)] {
            ctx.update(&(part.len() as u64).to_be_bytes());
            ctx.update(part.as_bytes());
        }
        let mut key = [0u8; 32];
        key.copy_from_slice(ctx.finish().as_ref());
        RejoinKey(key)
    }
}

/// `v` as JSON text with every object's keys in sorted order, recursively.
pub fn canonical_json(v: &Value) -> String {
    fn write(v: &Value, out: &mut String) {
        match v {
            Value::Object(m) => {
                let mut keys: Vec<&String> = m.keys().collect();
                keys.sort();
                out.push('{');
                for (i, k) in keys.into_iter().enumerate() {
                    if i > 0 {
                        out.push(',');
                    }
                    out.push_str(&Value::String(k.clone()).to_string());
                    out.push(':');
                    write(&m[k], out);
                }
                out.push('}');
            }
            Value::Array(a) => {
                out.push('[');
                for (i, x) in a.iter().enumerate() {
                    if i > 0 {
                        out.push(',');
                    }
                    write(x, out);
                }
                out.push(']');
            }
            other => out.push_str(&other.to_string()),
        }
    }
    let mut out = String::new();
    write(v, &mut out);
    out
}

/// `r_` and 16 lowercase hex characters.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct RequestId(String);

impl RequestId {
    fn mint() -> Self {
        RequestId(format!("r_{}", &random_id()[..16]))
    }

    /// An id as a caller wrote it (not checked: an unknown one is simply
    /// not in the table).
    pub fn parse(s: &str) -> Self {
        RequestId(s.to_string())
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

/// How a call ended, and when.
#[derive(Debug)]
pub struct Finished {
    pub result: Outcome,
    pub at: Instant,
}

struct Inner {
    request_id: OnceLock<RequestId>,
    approval: watch::Receiver<bool>,
    done: watch::Receiver<Option<Arc<Finished>>>,
    /// Requests waiting on the call right now.
    attached: AtomicUsize,
    abort: AbortHandle,
}

/// A call running on its own task. Cheap to clone; every clone is the same
/// call.
#[derive(Clone)]
pub struct CallHandle {
    inner: Arc<Inner>,
}

impl CallHandle {
    /// Starts `call` on `device_id`, on a task of its own: the request that
    /// started it can go away and the call carries on. One request is
    /// attached to it.
    pub fn start(registry: &Registry, device_id: &str, call: Call) -> CallHandle {
        let (approval_tx, approval) = watch::channel(false);
        let (done_tx, done) = watch::channel(None);
        let (registry, device_id) = (registry.clone(), device_id.to_string());
        let task = tokio::spawn(async move {
            let result = registry
                .call_watching(&device_id, call, Some(approval_tx))
                .await;
            let _ = done_tx.send(Some(Arc::new(Finished {
                result,
                at: Instant::now(),
            })));
        });
        CallHandle {
            inner: Arc::new(Inner {
                request_id: OnceLock::new(),
                approval,
                done,
                attached: AtomicUsize::new(1),
                abort: task.abort_handle(),
            }),
        }
    }

    /// The id given when the call was parked.
    pub fn request_id(&self) -> Option<&RequestId> {
        self.inner.request_id.get()
    }

    /// Resolves when the call has ended.
    pub async fn finished(&self) -> Arc<Finished> {
        let mut rx = self.inner.done.clone();
        let seen = rx
            .wait_for(|v| v.is_some())
            .await
            .ok()
            .and_then(|v| v.clone());
        seen.unwrap_or_else(|| {
            // The task ended without an answer: it was stopped.
            Arc::new(Finished {
                result: Err(CallError::Disconnected),
                at: Instant::now(),
            })
        })
    }

    /// Resolves when the device reports an approval dialog open for the
    /// call; never, for a call that ends without one.
    pub async fn approval_open(&self) {
        let mut rx = self.inner.approval.clone();
        let open = rx.wait_for(|open| *open).await.is_ok();
        if !open {
            std::future::pending::<()>().await;
        }
    }

    /// The call's end, if it has ended.
    pub fn peek(&self) -> Option<Arc<Finished>> {
        self.inner.done.borrow().clone()
    }

    fn attach(&self) {
        self.inner.attached.fetch_add(1, Ordering::SeqCst);
    }

    /// A request stops waiting and leaves the call running. The count
    /// of requests still attached.
    pub fn detach(&self) -> usize {
        self.inner
            .attached
            .fetch_sub(1, Ordering::SeqCst)
            .saturating_sub(1)
    }

    /// Stops the call (the device is told to cancel it).
    fn stop(&self) {
        self.inner.abort.abort();
    }
}

struct Entry {
    subject: String,
    device_id: String,
    key: RejoinKey,
    handle: CallHandle,
    /// When the call was made.
    started_at: Instant,
    /// Its request went away, or its id was given out: it stays until its
    /// result expires, even once delivered.
    kept: bool,
    delivered: bool,
}

#[derive(Default)]
struct Table {
    by_id: HashMap<RequestId, Entry>,
    /// The newest call for each key.
    by_key: HashMap<RejoinKey, RequestId>,
}

impl Table {
    fn remove(&mut self, id: &RequestId) {
        if let Some(e) = self.by_id.remove(id) {
            if self.by_key.get(&e.key) == Some(id) {
                self.by_key.remove(&e.key);
            }
        }
    }

    /// Drops results that have been kept past `ttl`.
    fn sweep(&mut self, now: Instant, ttl: Duration) {
        let expired: Vec<RequestId> = self
            .by_id
            .iter()
            .filter(|(_, e)| {
                e.handle
                    .peek()
                    .is_some_and(|f| now.saturating_duration_since(f.at) >= ttl)
            })
            .map(|(id, _)| id.clone())
            .collect();
        for id in expired {
            self.remove(&id);
        }
    }

    fn insert(
        &mut self,
        key: RejoinKey,
        subject: &str,
        device_id: &str,
        handle: CallHandle,
    ) -> RequestId {
        let id = RequestId::mint();
        let _ = handle.inner.request_id.set(id.clone());
        self.by_key.insert(key.clone(), id.clone());
        self.by_id.insert(
            id.clone(),
            Entry {
                subject: subject.to_string(),
                device_id: device_id.to_string(),
                key,
                handle,
                started_at: Instant::now(),
                kept: false,
                delivered: false,
            },
        );
        id
    }

    /// The call a request with `key` joins, if there is one: not yet handed
    /// over, inside the window, and not a call that failed before the
    /// device answered (a retry should try again, not hear the failure
    /// twice).
    fn rejoinable(&self, key: &RejoinKey, now: Instant, window: Duration) -> Option<&Entry> {
        let e = self.by_id.get(self.by_key.get(key)?)?;
        let fresh = now.saturating_duration_since(e.started_at) < window;
        let usable = e.handle.peek().is_none_or(|f| f.result.is_ok());
        (!e.delivered && fresh && usable).then_some(e)
    }
}

/// A request id that is the caller's (see [`ParkedCalls::owned`]).
pub struct Owned {
    pub id: RequestId,
    /// The device the request was made on.
    pub device_id: String,
    handle: CallHandle,
}

impl Owned {
    pub fn handle(&self) -> &CallHandle {
        &self.handle
    }
}

/// A result on its way to the AI app. It counts as handed over (never
/// joined again, and dropped from the table unless parked) only when
/// [`Delivery::commit`] is called, which the HTTP layer does once the
/// response carrying it has been written out. A response that never gets
/// that far (the AI app is gone) is dropped uncommitted, and the result stays
/// for the app's retry.
pub struct Delivery {
    parked: ParkedCalls,
    id: RequestId,
}

impl Delivery {
    pub fn commit(self) {
        self.parked.mark_delivered(&self.id);
    }
}

/// What `take` found.
#[derive(Debug)]
pub enum Fetch {
    Done(Outcome),
    Waiting,
    Unknown,
}

/// What a request got from [`ParkedCalls::join_or_park`].
pub struct Joined {
    pub handle: CallHandle,
    pub request_id: RequestId,
    /// It joined a call another request started.
    pub rejoined: bool,
}

/// The calls that can be rejoined or fetched. Cheap to clone.
#[derive(Clone)]
pub struct ParkedCalls {
    table: Arc<Mutex<Table>>,
    rejoin_window: Duration,
    result_ttl: Duration,
    sweeper: Arc<Once>,
}

impl ParkedCalls {
    pub fn new(rejoin_window: Duration, result_ttl: Duration) -> Self {
        ParkedCalls {
            table: Arc::new(Mutex::new(Table::default())),
            rejoin_window,
            result_ttl,
            sweeper: Arc::new(Once::new()),
        }
    }

    /// Starts the task that drops results when they expire even if nobody
    /// asks again. Started on the first entry, not in `new`, so it is
    /// always inside the runtime that serves requests whatever built this.
    fn ensure_sweeper(&self) {
        self.sweeper.call_once(|| {
            let Ok(rt) = tokio::runtime::Handle::try_current() else {
                return;
            };
            let (weak, ttl) = (Arc::downgrade(&self.table), self.result_ttl);
            let every = ttl.clamp(Duration::from_millis(10), Duration::from_secs(30));
            rt.spawn(async move {
                loop {
                    tokio::time::sleep(every).await;
                    let Some(table) = weak.upgrade() else { break };
                    table.lock().unwrap().sweep(Instant::now(), ttl);
                }
            });
        });
    }

    /// Enters `call` so a retry can find it and returns its request id.
    pub fn park(
        &self,
        key: RejoinKey,
        subject: &str,
        device_id: &str,
        call: CallHandle,
    ) -> RequestId {
        self.ensure_sweeper();
        let mut t = self.table.lock().unwrap();
        t.sweep(Instant::now(), self.result_ttl);
        t.insert(key, subject, device_id, call)
    }

    /// The call an identical request joins: unfinished, or finished with
    /// the device's answer and not yet handed over, within
    /// `REJOIN_WINDOW_SECS`. The caller is counted as attached to it.
    pub fn rejoin(&self, key: &RejoinKey) -> Option<CallHandle> {
        let mut t = self.table.lock().unwrap();
        let now = Instant::now();
        t.sweep(now, self.result_ttl);
        let handle = t.rejoinable(key, now, self.rejoin_window)?.handle.clone();
        handle.attach();
        Some(handle)
    }

    /// [`ParkedCalls::rejoin`], or else enter the call `start` makes, as one
    /// step: two identical requests at once start one call between them.
    pub fn join_or_park(
        &self,
        key: RejoinKey,
        subject: &str,
        device_id: &str,
        start: impl FnOnce() -> CallHandle,
    ) -> Joined {
        self.ensure_sweeper();
        let mut t = self.table.lock().unwrap();
        let now = Instant::now();
        t.sweep(now, self.result_ttl);
        if let Some(e) = t.rejoinable(&key, now, self.rejoin_window) {
            let handle = e.handle.clone();
            handle.attach();
            let request_id = handle
                .request_id()
                .cloned()
                .expect("a parked call has an id");
            return Joined {
                handle,
                request_id,
                rejoined: true,
            };
        }
        let handle = start();
        let request_id = t.insert(key, subject, device_id, handle.clone());
        Joined {
            handle,
            request_id,
            rejoined: false,
        }
    }

    /// The request `id` if it is `subject`'s: the one lookup behind
    /// everything that names a request by id. Someone else's id, an expired
    /// one and one that never was are all `None`.
    pub fn owned(&self, subject: &str, id: &RequestId) -> Option<Owned> {
        let mut t = self.table.lock().unwrap();
        t.sweep(Instant::now(), self.result_ttl);
        match t.by_id.get(id) {
            Some(e) if e.subject == subject => Some(Owned {
                id: id.clone(),
                device_id: e.device_id.clone(),
                handle: e.handle.clone(),
            }),
            _ => None,
        }
    }

    /// The result of request `id`, for `subject`, waiting up to `wait` for it.
    /// Taking does not hand the result over (see [`Delivery`]): that is for
    /// whoever sends it.
    pub async fn take(&self, subject: &str, id: &RequestId, wait: Duration) -> Fetch {
        let Some(owned) = self.owned(subject, id) else {
            return Fetch::Unknown;
        };
        let finished = match owned.handle.peek() {
            Some(f) => f,
            None => match tokio::time::timeout(wait, owned.handle.finished()).await {
                Ok(f) => f,
                Err(_) => return Fetch::Waiting,
            },
        };
        Fetch::Done(finished.result.clone())
    }

    /// A [`Delivery`] for `id`: commit it once the answer has been written.
    pub fn delivery(&self, id: &RequestId) -> Delivery {
        Delivery {
            parked: self.clone(),
            id: id.clone(),
        }
    }

    /// The answer has gone to a request: the call is not rejoined again.
    /// Dropped from the table unless it was parked.
    pub fn mark_delivered(&self, id: &RequestId) {
        let mut t = self.table.lock().unwrap();
        let Some(e) = t.by_id.get_mut(id) else { return };
        e.delivered = true;
        if !e.kept {
            t.remove(id);
        }
    }

    /// The call stays until its result expires: its request went away, or
    /// its id was given out.
    pub fn keep(&self, id: &RequestId) {
        if let Some(e) = self.table.lock().unwrap().by_id.get_mut(id) {
            e.kept = true;
        }
    }

    /// A request cancelled its wait. The call is stopped, and forgotten,
    /// unless another request has joined it. Under the table's lock all the
    /// way, as joining is: a request cannot join a call that is about to be
    /// stopped.
    pub fn cancel(&self, id: &RequestId, handle: &CallHandle) {
        let mut t = self.table.lock().unwrap();
        if handle.detach() > 0 {
            return;
        }
        handle.stop();
        t.remove(id);
    }

    /// Entries held (tests).
    #[cfg(test)]
    pub(crate) fn len(&self) -> usize {
        self.table.lock().unwrap().by_id.len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use tokio::sync::mpsc;
    use vitruvian_relay_protocol::ToConnector;

    #[test]
    fn canonical_json_sorts_keys_at_every_depth() {
        let a = json!({"b": 1, "a": {"y": [1, {"d": 1, "c": 2}], "x": null}});
        let b = json!({"a": {"x": null, "y": [1, {"c": 2, "d": 1}]}, "b": 1});
        assert_eq!(canonical_json(&a), canonical_json(&b));
        assert_eq!(
            canonical_json(&a),
            r#"{"a":{"x":null,"y":[1,{"c":2,"d":1}]},"b":1}"#
        );
        // Order inside an array is meaning, not noise.
        assert_ne!(
            canonical_json(&json!([1, 2])),
            canonical_json(&json!([2, 1]))
        );
    }

    #[test]
    fn a_key_names_person_device_tool_and_arguments() {
        let k = |s: &str, d: &str, t: &str, a: Value| RejoinKey::new(s, d, t, &a);
        let base = k("alice", "d1", "run", json!({"a": 1, "b": 2}));
        assert_eq!(base, k("alice", "d1", "run", json!({"b": 2, "a": 1})));
        assert_ne!(base, k("bob", "d1", "run", json!({"a": 1, "b": 2})));
        assert_ne!(base, k("alice", "d2", "run", json!({"a": 1, "b": 2})));
        assert_ne!(base, k("alice", "d1", "walk", json!({"a": 1, "b": 2})));
        assert_ne!(base, k("alice", "d1", "run", json!({"a": 1, "b": 3})));
        // Moving a character between two parts is a different call.
        assert_ne!(
            k("alice", "d1", "run", json!({})),
            k("alice", "d", "1run", json!({}))
        );
    }

    #[test]
    fn request_ids_are_r_and_sixteen_lowercase_hex() {
        for _ in 0..50 {
            let id = RequestId::mint();
            let s = id.as_str();
            assert_eq!(s.len(), 18, "{s}");
            assert!(s.starts_with("r_"), "{s}");
            assert!(
                s[2..]
                    .bytes()
                    .all(|c| matches!(c, b'0'..=b'9' | b'a'..=b'f')),
                "{s}"
            );
        }
        assert_ne!(RequestId::mint(), RequestId::mint());
    }

    fn registry() -> (
        Registry,
        crate::registry::ConnectionId,
        mpsc::Receiver<ToConnector>,
    ) {
        let reg = Registry::new();
        let (tx, rx) = mpsc::channel(64);
        let conn = reg.connect("d1", vec![], tx);
        (reg, conn, rx)
    }

    fn call(id: &str) -> Call {
        Call {
            call_id: id.into(),
            tool: "t".into(),
            arguments: json!({}),
            deadline_ms: 60_000,
        }
    }

    fn key(n: u32) -> RejoinKey {
        RejoinKey::new("alice", "d1", "t", &json!({"n": n}))
    }

    fn result(id: &str) -> CallResult {
        CallResult {
            call_id: id.into(),
            content: json!([{"type": "text", "text": "ok"}]),
            is_error: false,
            truncated: false,
        }
    }

    fn parked(window_ms: u64, ttl_ms: u64) -> ParkedCalls {
        ParkedCalls::new(
            Duration::from_millis(window_ms),
            Duration::from_millis(ttl_ms),
        )
    }

    #[tokio::test]
    async fn an_open_call_is_joined_and_a_delivered_one_is_not() {
        let (reg, _conn, _rx) = registry();
        let parked = parked(120_000, 300_000);
        let h = CallHandle::start(&reg, "d1", call("c1"));
        let id = parked.park(key(1), "alice", "d1", h.clone());
        let joined = parked.rejoin(&key(1)).expect("an open call is joined");
        assert_eq!(joined.request_id(), Some(&id));
        assert!(parked.rejoin(&key(2)).is_none(), "another call is not");
        assert!(
            parked
                .rejoin(&RejoinKey::new("bob", "d1", "t", &json!({"n": 1})))
                .is_none(),
            "another person's is not"
        );
        // Handed over: never joined again, and (not parked) not kept.
        parked.mark_delivered(&id);
        assert!(parked.rejoin(&key(1)).is_none());
        assert_eq!(parked.len(), 0);
    }

    #[tokio::test]
    async fn a_finished_undelivered_call_is_joined_unless_it_failed() {
        let (reg, conn, mut rx) = registry();
        let parked = parked(120_000, 300_000);
        let h = CallHandle::start(&reg, "d1", call("c1"));
        parked.park(key(1), "alice", "d1", h.clone());
        let ToConnector::Call(c) = rx.recv().await.unwrap() else {
            panic!()
        };
        reg.complete("d1", conn, result(&c.call_id));
        h.finished().await;
        assert!(parked.rejoin(&key(1)).is_some(), "the answer is still ours");
        // A call that failed before the device answered is retried afresh.
        let h2 = CallHandle::start(&reg, "nowhere", call("c2"));
        parked.park(key(2), "alice", "nowhere", h2.clone());
        h2.finished().await;
        assert!(parked.rejoin(&key(2)).is_none());
    }

    #[tokio::test]
    async fn the_rejoin_window_ends() {
        let (reg, _conn, _rx) = registry();
        let parked = parked(50, 300_000);
        let h = CallHandle::start(&reg, "d1", call("c1"));
        parked.park(key(1), "alice", "d1", h);
        assert!(parked.rejoin(&key(1)).is_some());
        tokio::time::sleep(Duration::from_millis(80)).await;
        assert!(parked.rejoin(&key(1)).is_none());
    }

    #[tokio::test]
    async fn identical_requests_at_once_start_one_call() {
        let (reg, _conn, _rx) = registry();
        let parked = parked(120_000, 300_000);
        let started = AtomicUsize::new(0);
        let start = || {
            started.fetch_add(1, Ordering::SeqCst);
            CallHandle::start(&reg, "d1", call(&random_id()))
        };
        let a = parked.join_or_park(key(1), "alice", "d1", start);
        let b = parked.join_or_park(key(1), "alice", "d1", start);
        assert_eq!(started.load(Ordering::SeqCst), 1);
        assert!(!a.rejoined && b.rejoined);
        assert_eq!(a.request_id, b.request_id);
    }

    #[tokio::test]
    async fn take_is_for_the_owner_and_waits_up_to_the_wait() {
        let (reg, conn, mut rx) = registry();
        let parked = parked(120_000, 300_000);
        let h = CallHandle::start(&reg, "d1", call("c1"));
        let id = parked.park(key(1), "alice", "d1", h);
        // Its id was given out, as a waiting reply does.
        parked.keep(&id);
        let wait = Duration::from_millis(30);
        assert!(matches!(
            parked.take("alice", &id, wait).await,
            Fetch::Waiting
        ));
        // Bob's try with Alice's id, and a made-up id, look the same.
        assert!(matches!(
            parked.take("bob", &id, wait).await,
            Fetch::Unknown
        ));
        assert!(matches!(
            parked
                .take("alice", &RequestId::parse("r_0000000000000000"), wait)
                .await,
            Fetch::Unknown
        ));
        let ToConnector::Call(c) = rx.recv().await.unwrap() else {
            panic!()
        };
        reg.complete("d1", conn, result(&c.call_id));
        match parked.take("alice", &id, wait).await {
            Fetch::Done(Ok(r)) => assert_eq!(r.content[0]["text"], "ok"),
            other => panic!("{other:?}"),
        }
        // Taking is not handing over: a retry still joins until the answer
        // has been written out. Then it is no longer joined, still fetchable.
        assert!(parked.rejoin(&key(1)).is_some());
        parked.delivery(&id).commit();
        assert!(parked.rejoin(&key(1)).is_none());
        assert!(matches!(
            parked.take("alice", &id, wait).await,
            Fetch::Done(_)
        ));
    }

    #[tokio::test]
    async fn a_delivery_dropped_uncommitted_leaves_the_result_for_the_retry() {
        let (reg, conn, mut rx) = registry();
        let parked = parked(120_000, 300_000);
        let h = CallHandle::start(&reg, "d1", call("c1"));
        let id = parked.park(key(1), "alice", "d1", h.clone());
        let ToConnector::Call(c) = rx.recv().await.unwrap() else {
            panic!()
        };
        reg.complete("d1", conn, result(&c.call_id));
        h.finished().await;
        // The answer was handed to a socket that never got it out.
        drop(parked.delivery(&id));
        assert!(parked.rejoin(&key(1)).is_some());
        parked.delivery(&id).commit();
        assert!(parked.rejoin(&key(1)).is_none());
        assert_eq!(parked.len(), 0, "an unparked call leaves with its delivery");
    }

    #[tokio::test]
    async fn only_the_owner_gets_a_request_and_its_device() {
        let (reg, _conn, _rx) = registry();
        let parked = parked(120_000, 300_000);
        let h = CallHandle::start(&reg, "d1", call("c1"));
        let id = parked.park(key(1), "alice", "d1", h);
        let mine = parked.owned("alice", &id).expect("the owner's");
        assert_eq!(mine.device_id, "d1");
        assert!(parked.owned("bob", &id).is_none());
        assert!(parked
            .owned("alice", &RequestId::parse("r_0000000000000000"))
            .is_none());
    }

    #[test]
    fn the_sweeper_starts_inside_the_runtime_whatever_built_the_table() {
        // Built outside any runtime, as `App::new` could be.
        let parked = parked(120_000, 100);
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();
        rt.block_on(async {
            let (reg, conn, mut rx) = registry();
            let h = CallHandle::start(&reg, "d1", call("c1"));
            let id = parked.park(key(1), "alice", "d1", h.clone());
            parked.keep(&id);
            let ToConnector::Call(c) = rx.recv().await.unwrap() else {
                panic!()
            };
            reg.complete("d1", conn, result(&c.call_id));
            h.finished().await;
            assert_eq!(parked.len(), 1);
            // Nobody asks again: the sweeper alone drops it.
            tokio::time::sleep(Duration::from_millis(400)).await;
            assert_eq!(parked.len(), 0);
        });
    }

    /// A request joining a call while another cancels it: the call is never
    /// stopped under the one that joined. (A stress run: the race it guards
    /// needs a thread to be preempted between two steps, so this cannot make
    /// it happen on demand; before `cancel` held the table's lock throughout
    /// it failed within a few hundred rounds.)
    #[tokio::test(flavor = "multi_thread", worker_threads = 4)]
    async fn a_cancel_never_stops_a_call_another_request_just_joined() {
        let (reg, _conn, _rx) = registry();
        let parked = parked(120_000, 300_000);
        for n in 0..400 {
            let h = CallHandle::start(&reg, "d1", call(&format!("c{n}")));
            let k = key(1000 + n);
            let id = parked.park(k.clone(), "alice", "d1", h.clone());
            let (p2, k2) = (parked.clone(), k.clone());
            let joiner = tokio::spawn(async move { p2.rejoin(&k2) });
            let (p3, h3, id3) = (parked.clone(), h.clone(), id.clone());
            let canceller = tokio::spawn(async move { p3.cancel(&id3, &h3) });
            let joined = joiner.await.unwrap();
            canceller.await.unwrap();
            if let Some(j) = joined {
                for _ in 0..5 {
                    tokio::task::yield_now().await;
                }
                assert!(
                    !j.inner.abort.is_finished(),
                    "round {n}: the call was stopped under the request that joined it"
                );
                parked.cancel(&id, &j);
            }
        }
    }

    #[tokio::test]
    async fn a_kept_result_is_dropped_after_its_ttl() {
        let (reg, conn, mut rx) = registry();
        let parked = parked(120_000, 100);
        let h = CallHandle::start(&reg, "d1", call("c1"));
        let id = parked.park(key(1), "alice", "d1", h.clone());
        parked.keep(&id);
        let ToConnector::Call(c) = rx.recv().await.unwrap() else {
            panic!()
        };
        reg.complete("d1", conn, result(&c.call_id));
        h.finished().await;
        let wait = Duration::from_millis(10);
        assert!(matches!(
            parked.take("alice", &id, wait).await,
            Fetch::Done(_)
        ));
        // Gone by itself (the sweeper), not only when asked.
        tokio::time::sleep(Duration::from_millis(400)).await;
        assert_eq!(parked.len(), 0);
        assert!(matches!(
            parked.take("alice", &id, wait).await,
            Fetch::Unknown
        ));
    }

    #[tokio::test]
    async fn cancel_stops_the_call_unless_another_request_joined() {
        let (reg, _conn, mut rx) = registry();
        let parked = parked(120_000, 300_000);
        let h = CallHandle::start(&reg, "d1", call("c1"));
        let id = parked.park(key(1), "alice", "d1", h.clone());
        let ToConnector::Call(c) = rx.recv().await.unwrap() else {
            panic!()
        };
        let other = parked.rejoin(&key(1)).unwrap();
        parked.cancel(&id, &h);
        assert!(reg.in_flight("d1"), "the second request still wants it");
        parked.cancel(&id, &other);
        assert_eq!(
            tokio::time::timeout(Duration::from_secs(5), rx.recv())
                .await
                .unwrap(),
            Some(ToConnector::Cancel { call_id: c.call_id })
        );
        assert_eq!(parked.len(), 0);
    }
}
