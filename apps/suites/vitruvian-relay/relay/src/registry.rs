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

//! Which devices are connected, and routing a call to one and back.

use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use tokio::sync::{mpsc, oneshot, Notify};
use vitruvian_relay_protocol::{Call, CallResult, ToConnector, ToolDef};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct ConnectionId(u64);

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CallError {
    /// No connection for the device when the call was made.
    Offline,
    /// The connection ended while the call was in flight.
    Disconnected,
    /// The device did not acknowledge receiving the call in time.
    NotReceived,
    /// The device did not answer within the call's deadline.
    Deadline,
    /// A call with this id is already in flight. Ids must be unique; the
    /// caller generates them, so this is a bug on the caller's side.
    Duplicate,
}

impl CallError {
    pub fn user_message(&self) -> &'static str {
        match self {
            CallError::Offline => "Your computer is offline.",
            CallError::Disconnected => "Your computer disconnected; try again.",
            CallError::NotReceived => "Your computer didn't answer in time; try again.",
            CallError::Deadline => "The command took too long.",
            CallError::Duplicate => "That command is already running.",
        }
    }
}

struct Connection {
    id: ConnectionId,
    tx: mpsc::Sender<ToConnector>,
    tools: Vec<ToolDef>,
    closer: Arc<Closer>,
}

/// Tells a session to end its connection now, without sending what is still
/// queued for it (see [`Registry::closer`]).
#[derive(Default)]
pub struct Closer {
    closed: AtomicBool,
    notify: Notify,
}

impl Closer {
    pub fn is_closed(&self) -> bool {
        self.closed.load(Ordering::SeqCst)
    }

    /// Resolves once the connection is to be closed.
    pub async fn closed(&self) {
        loop {
            let wait = self.notify.notified();
            tokio::pin!(wait);
            // Registered before the check, so a close between the two is
            // not missed.
            wait.as_mut().enable();
            if self.is_closed() {
                return;
            }
            wait.await;
        }
    }

    fn close(&self) {
        self.closed.store(true, Ordering::SeqCst);
        self.notify.notify_waiters();
    }
}

/// How long a `Cancel` may wait for room in a full connection queue before
/// the connection is closed instead.
pub const CANCEL_WAIT: Duration = Duration::from_secs(2);

struct Pending {
    conn_id: ConnectionId,
    /// Tells this entry apart from a later call that reused the same id after
    /// this one was forgotten, so a stale guard or deadline never removes it.
    token: u64,
    /// When the relay stops waiting for this call.
    deadline: Instant,
    /// Notified when the session finishes writing `Call` to the socket.
    written: Option<oneshot::Sender<()>>,
    /// Notified when the device acknowledges receipt of the call.
    ack: Option<oneshot::Sender<()>>,
    /// Whether `ack` has been received for this call.
    acked: bool,
    done: oneshot::Sender<Result<CallResult, CallError>>,
}

#[derive(Default)]
struct State {
    next_conn: u64,
    next_token: u64,
    devices: HashMap<String, Connection>,
    pending: HashMap<String, Pending>,
}

impl State {
    /// Ends a connection (if it is the current one) and fails what it had in
    /// flight. Dropping its `tx` closes the session's receiving side.
    fn drop_connection(&mut self, device_id: &str, only: Option<ConnectionId>) {
        match self.devices.get(device_id) {
            Some(c) if only.is_none_or(|id| id == c.id) => {}
            _ => return,
        }
        let conn = self.devices.remove(device_id).unwrap();
        let ids: Vec<String> = self
            .pending
            .iter()
            .filter(|(_, p)| p.conn_id == conn.id)
            .map(|(k, _)| k.clone())
            .collect();
        for id in ids {
            if let Some(p) = self.pending.remove(&id) {
                let _ = p.done.send(Err(CallError::Disconnected));
            }
        }
    }

    /// Removes the entry only if it is still the one with this token.
    fn forget(&mut self, call_id: &str, token: u64) -> bool {
        if self.pending.get(call_id).is_some_and(|p| p.token == token) {
            self.pending.remove(call_id);
            true
        } else {
            false
        }
    }
}

/// Cheap to clone; every clone shares the same state.
#[derive(Clone)]
pub struct Registry {
    state: Arc<Mutex<State>>,
    cancel_wait: Duration,
    ack_timeout: Duration,
}

impl Default for Registry {
    fn default() -> Self {
        Registry {
            state: Arc::default(),
            cancel_wait: CANCEL_WAIT,
            ack_timeout: Duration::from_secs(vitruvian_relay_protocol::ACK_SECS),
        }
    }
}

/// Forgets a call if its caller goes away (the HTTP request was dropped), and
/// tells the device to stop it.
struct PendingGuard<'a> {
    registry: &'a Registry,
    device_id: String,
    conn_id: ConnectionId,
    call_id: String,
    token: u64,
    tx: mpsc::Sender<ToConnector>,
    /// Whether the call went into the connection's queue.
    sent: &'a AtomicBool,
    armed: bool,
}

impl Drop for PendingGuard<'_> {
    fn drop(&mut self) {
        if self.armed
            && self
                .registry
                .state
                .lock()
                .unwrap()
                .forget(&self.call_id, self.token)
            && self.sent.load(Ordering::SeqCst)
        {
            self.registry.cancel(
                &self.device_id,
                self.conn_id,
                &self.tx,
                std::mem::take(&mut self.call_id),
            );
        }
    }
}

impl Registry {
    pub fn new() -> Self {
        Self::default()
    }

    /// A registry whose `Cancel`s wait `d` for room (tests).
    pub fn with_cancel_wait(d: Duration) -> Self {
        Registry {
            cancel_wait: d,
            ..Self::default()
        }
    }

    /// A registry whose calls wait `d` for the device's `Ack`.
    pub fn with_ack_timeout(d: Duration) -> Self {
        Registry {
            ack_timeout: d,
            ..Self::default()
        }
    }

    /// This registry (the same state), but its `Cancel`s wait `d` for room.
    #[cfg(test)]
    pub(crate) fn cancel_waiting(&self, d: Duration) -> Self {
        Registry {
            state: self.state.clone(),
            cancel_wait: d,
            ack_timeout: self.ack_timeout,
        }
    }

    /// Marks a call as written to the socket so the `ack_timeout` wait starts
    /// from socket transmission rather than queue wait time.
    pub fn call_written(&self, conn: ConnectionId, call_id: &str) {
        let mut st = self.state.lock().unwrap();
        if let Some(p) = st.pending.get_mut(call_id).filter(|p| p.conn_id == conn) {
            if let Some(tx) = p.written.take() {
                let _ = tx.send(());
            }
        }
    }

    /// Records the device's receipt `Ack` for a pending call on `conn`.
    /// Returns `true` only on the first valid `Ack` while the call is still
    /// pending, so the session sends `Start` once and never for a late `Ack`.
    pub fn ack(&self, conn: ConnectionId, call_id: &str) -> bool {
        let mut st = self.state.lock().unwrap();
        let Some(p) = st.pending.get_mut(call_id).filter(|p| p.conn_id == conn) else {
            return false;
        };
        if p.acked {
            return false;
        }
        p.acked = true;
        if let Some(tx) = p.ack.take() {
            let _ = tx.send(());
        }
        true
    }

    /// The session calls this just before it writes a call to the socket,
    /// which can be long after the call was queued. `false` means do not
    /// send it.
    ///
    /// - A call the relay has given up on (timed out, cancelled, failed with
    ///   its connection) is no longer pending: it is not sent.
    /// - Otherwise `deadline_ms` becomes the time left right now, less
    ///   `margin` (the time allowed for the frame to reach the device). The
    ///   device counts from when it gets the frame, so its deadline ends no
    ///   later than the relay's as long as the frame arrives within `margin`.
    /// - A call with no more than `margin` left could not arrive in time: it
    ///   is failed now (`Deadline`) and not sent.
    ///
    /// The match is by call id and connection. Ids are 128 random bits
    /// (`mcp.rs`), so a queued frame is never mistaken for a later call.
    pub fn release(&self, conn: ConnectionId, call: &mut Call, margin: Duration) -> bool {
        let mut st = self.state.lock().unwrap();
        let Some(p) = st.pending.get(&call.call_id).filter(|p| p.conn_id == conn) else {
            return false;
        };
        let left = p
            .deadline
            .saturating_duration_since(Instant::now())
            .saturating_sub(margin);
        // Whole milliseconds, rounded down: never more than is left.
        let ms = left.as_millis() as u64;
        if ms == 0 {
            if let Some(p) = st.pending.remove(&call.call_id) {
                let _ = p.done.send(Err(CallError::Deadline));
            }
            return false;
        }
        call.deadline_ms = ms;
        true
    }

    /// The handle the session for connection `id` watches: once it says
    /// closed, the session ends at once, sending nothing more.
    pub fn closer(&self, device_id: &str, id: ConnectionId) -> Option<Arc<Closer>> {
        let st = self.state.lock().unwrap();
        st.devices
            .get(device_id)
            .filter(|c| c.id == id)
            .map(|c| c.closer.clone())
    }

    /// Ends connection `id` now: its pending calls fail and its session
    /// stops without sending what is still queued.
    fn close_now(&self, device_id: &str, id: ConnectionId) {
        let mut st = self.state.lock().unwrap();
        if let Some(c) = st.devices.get(device_id).filter(|c| c.id == id) {
            c.closer.close();
        }
        st.drop_connection(device_id, Some(id));
    }

    /// Tells the device to stop a call the relay has given up on. That must
    /// never be lost: if the queue has no room, the cancel waits for it (in
    /// order, behind the call it cancels) for `cancel_wait`; failing that,
    /// the connection is closed, which the connector treats as a drop (it
    /// closes the call's dialog and does not start it).
    fn cancel(
        &self,
        device_id: &str,
        id: ConnectionId,
        tx: &mpsc::Sender<ToConnector>,
        call_id: String,
    ) {
        let frame = ToConnector::Cancel { call_id };
        let frame = match tx.try_send(frame) {
            Ok(()) => return,
            // The session is gone: so is the connection.
            Err(mpsc::error::TrySendError::Closed(_)) => return,
            Err(mpsc::error::TrySendError::Full(f)) => f,
        };
        let (reg, device, tx, wait) = (
            self.clone(),
            device_id.to_string(),
            tx.clone(),
            self.cancel_wait,
        );
        let closer = move |reg: &Registry| reg.close_now(&device, id);
        match tokio::runtime::Handle::try_current() {
            Ok(h) => {
                h.spawn(async move {
                    let sent =
                        matches!(tokio::time::timeout(wait, tx.send(frame)).await, Ok(Ok(())));
                    if !sent {
                        closer(&reg);
                    }
                });
            }
            // No runtime to wait in (shutting down): close at once.
            Err(_) => closer(&reg),
        }
    }

    /// Registers a live connection. A newer connection for the same device
    /// replaces the old one; the old one's pending calls fail `Disconnected`.
    pub fn connect(
        &self,
        device_id: &str,
        tools: Vec<ToolDef>,
        tx: mpsc::Sender<ToConnector>,
    ) -> ConnectionId {
        let mut st = self.state.lock().unwrap();
        st.drop_connection(device_id, None);
        st.next_conn += 1;
        let id = ConnectionId(st.next_conn);
        st.devices.insert(
            device_id.to_string(),
            Connection {
                id,
                tx,
                tools,
                closer: Arc::default(),
            },
        );
        id
    }

    /// `connect`, but only if `still_valid` holds, checked under the
    /// registry's lock. A device registered again stores its new key and
    /// then calls `kick`, which takes the same lock; so a connection checked
    /// with the old key can never register after that kick, nor evict a
    /// connection made with the new key. `None` if the check fails (nothing
    /// is changed). Also returns the connection's [`Closer`], in the same
    /// step, so the session never has to look it up after a replacement
    /// could have removed it.
    pub fn connect_if(
        &self,
        device_id: &str,
        tools: Vec<ToolDef>,
        tx: mpsc::Sender<ToConnector>,
        still_valid: impl FnOnce() -> bool,
    ) -> Option<(ConnectionId, Arc<Closer>)> {
        let mut st = self.state.lock().unwrap();
        if !still_valid() {
            return None;
        }
        st.drop_connection(device_id, None);
        st.next_conn += 1;
        let id = ConnectionId(st.next_conn);
        let closer = Arc::<Closer>::default();
        st.devices.insert(
            device_id.to_string(),
            Connection {
                id,
                tx,
                tools,
                closer: closer.clone(),
            },
        );
        Some((id, closer))
    }

    /// Ends the connection `id`, if it is still the device's current one (a
    /// stale session ending late must not remove its replacement).
    pub fn disconnect(&self, device_id: &str, id: ConnectionId) {
        self.state
            .lock()
            .unwrap()
            .drop_connection(device_id, Some(id));
    }

    /// Closes the device's live connection, failing its pending calls.
    pub fn kick(&self, device_id: &str) {
        self.state.lock().unwrap().drop_connection(device_id, None);
    }

    /// The device's new tool list, from connection `conn`: only if that is
    /// still its current connection (a `tools_changed` read by a session
    /// that was just replaced must not overwrite its replacement's list).
    pub fn update_tools(&self, device_id: &str, conn: ConnectionId, tools: Vec<ToolDef>) {
        if let Some(c) = self.state.lock().unwrap().devices.get_mut(device_id) {
            if c.id == conn {
                c.tools = tools;
            }
        }
    }

    pub fn tools(&self, device_id: &str) -> Option<Vec<ToolDef>> {
        self.state
            .lock()
            .unwrap()
            .devices
            .get(device_id)
            .map(|c| c.tools.clone())
    }

    /// True while the device's current connection has a call in flight. The
    /// session uses it to ping every 2 s instead of every 20 s.
    pub fn in_flight(&self, device_id: &str) -> bool {
        let st = self.state.lock().unwrap();
        st.devices
            .get(device_id)
            .is_some_and(|c| st.pending.values().any(|p| p.conn_id == c.id))
    }

    /// Sends the call down the device's connection and waits for its result,
    /// its deadline, or the connection ending, whichever comes first. The
    /// deadline and a disconnect also cover a connection whose queue is full,
    /// so a stuck connection never leaves the caller hanging.
    pub async fn call(&self, device_id: &str, mut call: Call) -> Result<CallResult, CallError> {
        let call_id = call.call_id.clone();
        let deadline = Duration::from_millis(call.deadline_ms);
        let started = Instant::now();
        let sent = AtomicBool::new(false);
        let (done, mut rx) = oneshot::channel();
        let (written_tx, written_rx) = oneshot::channel();
        let (ack_tx, ack_rx) = oneshot::channel();
        let (tx, token, conn_id) = {
            let mut st = self.state.lock().unwrap();
            let conn = st.devices.get(device_id).ok_or(CallError::Offline)?;
            let (conn_id, tx) = (conn.id, conn.tx.clone());
            if st.pending.contains_key(&call_id) {
                return Err(CallError::Duplicate);
            }
            st.next_token += 1;
            let token = st.next_token;
            st.pending.insert(
                call_id.clone(),
                Pending {
                    conn_id,
                    token,
                    deadline: started + deadline,
                    written: Some(written_tx),
                    ack: Some(ack_tx),
                    acked: false,
                    done,
                },
            );
            (tx, token, conn_id)
        };
        let mut guard = PendingGuard {
            registry: self,
            device_id: device_id.to_string(),
            conn_id,
            call_id: call_id.clone(),
            token,
            tx: tx.clone(),
            sent: &sent,
            armed: true,
        };

        let outcome = tokio::time::timeout(deadline, async {
            // Wait for room in the queue, but give up the moment the
            // connection ends (which answers `rx`).
            tokio::select! {
                permit = tx.reserve() => match permit {
                    Ok(permit) => {
                        // What is left after waiting for room. The frame
                        // can still wait in the queue: the session sets the
                        // final value when it sends it (`release`).
                        let left = deadline.saturating_sub(started.elapsed());
                        call.deadline_ms = left.as_millis() as u64;
                        permit.send(ToConnector::Call(call));
                        sent.store(true, Ordering::SeqCst);
                    }
                    // The session's receiver is gone: the connection is dead.
                    Err(_) => return Err(CallError::Disconnected),
                },
                answer = &mut rx => return answer.unwrap_or(Err(CallError::Disconnected)),
            }
            // Wait for the session to write `Call` to the socket before
            // starting the ack countdown.
            tokio::select! {
                w = written_rx => {
                    if w.is_err() {
                        return rx.await.unwrap_or(Err(CallError::Disconnected));
                    }
                }
                answer = &mut rx => return answer.unwrap_or(Err(CallError::Disconnected)),
            }
            // Wait up to `ack_timeout` for the device to acknowledge receipt.
            let acked = tokio::select! {
                res = tokio::time::timeout(self.ack_timeout, ack_rx) => match res {
                    Ok(Ok(())) => true,
                    Ok(Err(_)) => return rx.await.unwrap_or(Err(CallError::Disconnected)),
                    Err(_) => false,
                },
                answer = &mut rx => return answer.unwrap_or(Err(CallError::Disconnected)),
            };
            if !acked {
                let timed_out = {
                    let mut st = self.state.lock().unwrap();
                    if st
                        .pending
                        .get(&call_id)
                        .is_some_and(|p| p.token == token && !p.acked)
                    {
                        st.pending.remove(&call_id);
                        true
                    } else {
                        false
                    }
                };
                if timed_out {
                    self.cancel(device_id, conn_id, &tx, call_id.clone());
                    return Err(CallError::NotReceived);
                }
            }
            // A dropped sender without an answer means the connection ended.
            rx.await.unwrap_or(Err(CallError::Disconnected))
        })
        .await;
        guard.armed = false;
        match outcome {
            Ok(result) => {
                // Dead-connection path (no answer through `rx`): clean up.
                if result.is_err() {
                    self.state.lock().unwrap().forget(&call_id, token);
                }
                result
            }
            Err(_) => {
                // `forget` only succeeds while the entry is still here. If
                // `complete` already took it (result and deadline at the same
                // instant), the caller still gets `Deadline` but no `Cancel` is
                // sent: the call is finished. If the result is still on its way
                // in, the entry is removed here, the late result is dropped, and
                // the device gets a `Cancel` for a call it may have finished
                // (harmless; it ignores unknown ids).
                // A call that never got into the queue needs no cancel.
                if self.state.lock().unwrap().forget(&call_id, token) && sent.load(Ordering::SeqCst)
                {
                    self.cancel(device_id, conn_id, &tx, call_id);
                }
                Err(CallError::Deadline)
            }
        }
    }

    /// Hands a device's result to the caller waiting for it. `conn` is the
    /// connection the result arrived on: a result from any other connection
    /// (an old one that outlived a reconnect) is dropped, as is one nobody is
    /// waiting for (late, repeated, or cancelled).
    pub fn complete(&self, conn: ConnectionId, result: CallResult) {
        let mut st = self.state.lock().unwrap();
        if st
            .pending
            .get(&result.call_id)
            .is_some_and(|p| p.conn_id == conn)
        {
            if let Some(p) = st.pending.remove(&result.call_id) {
                let _ = p.done.send(Ok(result));
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use std::time::Instant;

    /// A call given the whole budget.
    const BUDGET_MS: u64 = vitruvian_relay_protocol::CALL_BUDGET_SECS * 1000;

    // Real time, not tokio's paused clock: `test-util` would unify into the
    // production build through the crate hub. Deadlines here are either short
    // or never reached; a hang shows up as the outer `within` timing out.
    async fn within<T>(f: impl std::future::Future<Output = T>) -> T {
        tokio::time::timeout(Duration::from_secs(5), f)
            .await
            .expect("hung")
    }

    fn call(id: &str, deadline_ms: u64) -> Call {
        Call {
            call_id: id.into(),
            tool: "read_file".into(),
            arguments: json!({"path": "/tmp/x"}),
            deadline_ms,
        }
    }

    fn result(id: &str, text: &str) -> CallResult {
        CallResult {
            call_id: id.into(),
            content: json!([{"type": "text", "text": text}]),
            is_error: false,
            truncated: false,
        }
    }

    fn tool(name: &str) -> ToolDef {
        ToolDef {
            name: name.into(),
            description: "d".into(),
            input_schema: json!({"type": "object"}),
        }
    }

    async fn expect_call(rx: &mut mpsc::Receiver<ToConnector>) -> Call {
        match within(rx.recv()).await.expect("frame") {
            ToConnector::Call(c) => c,
            other => panic!("expected call, got {other:?}"),
        }
    }

    fn spawn_call(
        reg: &Registry,
        id: &str,
        deadline_ms: u64,
    ) -> tokio::task::JoinHandle<Result<CallResult, CallError>> {
        let (r, id) = (reg.clone(), id.to_string());
        tokio::spawn(async move { r.call("d1", call(&id, deadline_ms)).await })
    }

    #[tokio::test]
    async fn call_returns_device_result() {
        let reg = Registry::new();
        let (tx, mut rx) = mpsc::channel(8);
        let conn = reg.connect("d1", vec![], tx);
        let h = spawn_call(&reg, "c1", BUDGET_MS);
        assert_eq!(expect_call(&mut rx).await.call_id, "c1");
        reg.complete(conn, result("c1", "hi"));
        assert_eq!(within(h).await.unwrap(), Ok(result("c1", "hi")));
    }

    #[tokio::test]
    async fn concurrent_calls_get_their_own_results() {
        let reg = Registry::new();
        let (tx, mut rx) = mpsc::channel(8);
        let conn = reg.connect("d1", vec![], tx);
        let h1 = spawn_call(&reg, "c1", BUDGET_MS);
        let h2 = spawn_call(&reg, "c2", BUDGET_MS);
        expect_call(&mut rx).await;
        expect_call(&mut rx).await;
        reg.complete(conn, result("c2", "second"));
        reg.complete(conn, result("c1", "first"));
        assert_eq!(within(h1).await.unwrap(), Ok(result("c1", "first")));
        assert_eq!(within(h2).await.unwrap(), Ok(result("c2", "second")));
    }

    #[tokio::test]
    async fn pending_call_fails_when_device_drops() {
        let reg = Registry::new();
        let (tx, mut rx) = mpsc::channel(8);
        let conn = reg.connect("d1", vec![], tx);
        // A long deadline: only the disconnect can end this call quickly.
        let h = spawn_call(&reg, "c1", BUDGET_MS);
        expect_call(&mut rx).await;
        let started = Instant::now();
        reg.disconnect("d1", conn);
        assert_eq!(within(h).await.unwrap(), Err(CallError::Disconnected));
        // 1 s, not 100 ms: shared CI runners stall; still far below the call budget.
        assert!(started.elapsed() < Duration::from_secs(1));
    }

    #[tokio::test]
    async fn call_to_offline_device_fails_fast() {
        let reg = Registry::new();
        let started = Instant::now();
        assert_eq!(
            within(reg.call("nobody", call("c1", BUDGET_MS))).await,
            Err(CallError::Offline)
        );
        // 1 s, not 100 ms: shared CI runners stall; still far below the call budget.
        assert!(started.elapsed() < Duration::from_secs(1));
    }

    #[tokio::test]
    async fn deadline_expiry_sends_cancel() {
        let reg = Registry::new();
        let (tx, mut rx) = mpsc::channel(8);
        let conn = reg.connect("d1", vec![], tx);
        let h = spawn_call(&reg, "c1", 50);
        expect_call(&mut rx).await;
        assert_eq!(within(h).await.unwrap(), Err(CallError::Deadline));
        assert_eq!(
            within(rx.recv()).await,
            Some(ToConnector::Cancel {
                call_id: "c1".into()
            })
        );
        // A late result for the cancelled call is ignored, not a panic.
        reg.complete(conn, result("c1", "late"));
        assert!(!reg.in_flight("d1"));
    }

    #[tokio::test]
    async fn reconnect_replaces_old_connection() {
        let reg = Registry::new();
        let (tx1, mut rx1) = mpsc::channel(8);
        let old = reg.connect("d1", vec![tool("old")], tx1);
        let h = spawn_call(&reg, "c1", BUDGET_MS);
        expect_call(&mut rx1).await;

        let (tx2, mut rx2) = mpsc::channel(8);
        let new = reg.connect("d1", vec![tool("new")], tx2);
        // The old connection's call fails and its channel closes.
        assert_eq!(within(h).await.unwrap(), Err(CallError::Disconnected));
        assert!(within(rx1.recv()).await.is_none());
        assert_eq!(reg.tools("d1").unwrap()[0].name, "new");

        // The old session ending late must not remove the new connection.
        reg.disconnect("d1", old);
        assert!(reg.tools("d1").is_some());

        // New calls go to the new connection.
        let h = spawn_call(&reg, "c2", BUDGET_MS);
        expect_call(&mut rx2).await;
        // A result for c2 reported by the old connection is ignored...
        reg.complete(old, result("c2", "from the old connection"));
        assert!(reg.in_flight("d1"));
        // ...and the new connection's own result is accepted.
        reg.complete(new, result("c2", "ok"));
        assert_eq!(within(h).await.unwrap(), Ok(result("c2", "ok")));
    }

    #[tokio::test]
    async fn connect_if_leaves_everything_alone_when_the_check_fails() {
        let reg = Registry::new();
        let (tx1, _rx1) = mpsc::channel(8);
        reg.connect("d1", vec![tool("live")], tx1);
        let (tx2, _rx2) = mpsc::channel(8);
        assert!(reg
            .connect_if("d1", vec![tool("stale")], tx2, || false)
            .is_none());
        assert_eq!(reg.tools("d1"), Some(vec![tool("live")]));
        let (tx3, _rx3) = mpsc::channel(8);
        assert!(reg
            .connect_if("d1", vec![tool("ok")], tx3, || true)
            .is_some());
        assert_eq!(reg.tools("d1"), Some(vec![tool("ok")]));
    }

    #[tokio::test]
    async fn update_tools_changes_the_list() {
        let reg = Registry::new();
        let (tx, _rx) = mpsc::channel(8);
        let conn = reg.connect("d1", vec![tool("a")], tx);
        assert_eq!(reg.tools("d1"), Some(vec![tool("a")]));
        reg.update_tools("d1", conn, vec![tool("a"), tool("b")]);
        assert_eq!(reg.tools("d1"), Some(vec![tool("a"), tool("b")]));
        assert_eq!(reg.tools("other"), None);
    }

    /// Final review M1: a replaced connection's late `tools_changed` leaves
    /// its replacement's list alone.
    #[tokio::test]
    async fn a_stale_connection_cannot_change_the_new_ones_tools() {
        let reg = Registry::new();
        let (tx, _rx) = mpsc::channel(8);
        let old = reg.connect("d1", vec![tool("a")], tx);
        let (tx2, _rx2) = mpsc::channel(8);
        let new = reg.connect("d1", vec![tool("new")], tx2);
        reg.update_tools("d1", old, vec![tool("stale")]);
        assert_eq!(reg.tools("d1"), Some(vec![tool("new")]));
        reg.update_tools("d1", new, vec![tool("newer")]);
        assert_eq!(reg.tools("d1"), Some(vec![tool("newer")]));
    }

    #[tokio::test]
    async fn kick_fails_pending_calls() {
        let reg = Registry::new();
        let (tx, mut rx) = mpsc::channel(8);
        reg.connect("d1", vec![], tx);
        let h = spawn_call(&reg, "c1", BUDGET_MS);
        expect_call(&mut rx).await;
        reg.kick("d1");
        assert_eq!(within(h).await.unwrap(), Err(CallError::Disconnected));
        assert!(within(rx.recv()).await.is_none());
        assert_eq!(reg.tools("d1"), None);
    }

    #[test]
    fn user_messages_are_the_spec_text() {
        assert_eq!(
            CallError::Offline.user_message(),
            "Your computer is offline."
        );
        assert_eq!(
            CallError::Disconnected.user_message(),
            "Your computer disconnected; try again."
        );
        assert_eq!(
            CallError::NotReceived.user_message(),
            "Your computer didn't answer in time; try again."
        );
        assert_eq!(
            CallError::Deadline.user_message(),
            "The command took too long."
        );
    }

    // A connection whose channel is already full (capacity 1, one frame queued).
    async fn full_connection(reg: &Registry) -> (ConnectionId, mpsc::Receiver<ToConnector>) {
        let (tx, rx) = mpsc::channel(1);
        tx.send(ToConnector::Ping { n: 0 }).await.unwrap();
        (reg.connect("d1", vec![], tx), rx)
    }

    #[tokio::test]
    async fn disconnect_wakes_a_call_blocked_on_a_full_channel() {
        let reg = Registry::new();
        let (conn, _rx) = full_connection(&reg).await;
        let h = spawn_call(&reg, "c1", BUDGET_MS);
        tokio::time::sleep(Duration::from_millis(20)).await;
        assert!(reg.in_flight("d1"));
        let started = Instant::now();
        reg.disconnect("d1", conn);
        assert_eq!(within(h).await.unwrap(), Err(CallError::Disconnected));
        // 1 s, not 100 ms: shared CI runners stall; still far below the call budget.
        assert!(started.elapsed() < Duration::from_secs(1));
    }

    #[tokio::test]
    async fn deadline_applies_to_a_call_blocked_on_a_full_channel() {
        let reg = Registry::new();
        let (_conn, _rx) = full_connection(&reg).await;
        let h = spawn_call(&reg, "c1", 50);
        assert_eq!(within(h).await.unwrap(), Err(CallError::Deadline));
        assert!(!reg.in_flight("d1"));
    }

    #[tokio::test]
    async fn duplicate_call_id_is_refused_and_leaves_the_first_alone() {
        let reg = Registry::new();
        let (tx, mut rx) = mpsc::channel(8);
        let conn = reg.connect("d1", vec![], tx);
        let first = spawn_call(&reg, "c1", BUDGET_MS);
        expect_call(&mut rx).await;
        assert_eq!(
            within(reg.call("d1", call("c1", BUDGET_MS))).await,
            Err(CallError::Duplicate)
        );
        // The first call is still pending and no extra frame went out.
        assert!(reg.in_flight("d1"));
        assert!(rx.try_recv().is_err());
        reg.complete(conn, result("c1", "one"));
        assert_eq!(within(first).await.unwrap(), Ok(result("c1", "one")));
    }

    #[tokio::test]
    async fn in_flight_tracks_the_call_lifecycle() {
        let reg = Registry::new();
        assert!(!reg.in_flight("d1"));
        let (tx, mut rx) = mpsc::channel(8);
        let conn = reg.connect("d1", vec![], tx);
        assert!(!reg.in_flight("d1"));

        // complete
        let h = spawn_call(&reg, "c1", BUDGET_MS);
        expect_call(&mut rx).await;
        assert!(reg.in_flight("d1"));
        reg.complete(conn, result("c1", "x"));
        within(h).await.unwrap().unwrap();
        assert!(!reg.in_flight("d1"));

        // deadline
        let h = spawn_call(&reg, "c2", 30);
        expect_call(&mut rx).await;
        assert!(reg.in_flight("d1"));
        assert_eq!(within(h).await.unwrap(), Err(CallError::Deadline));
        assert!(!reg.in_flight("d1"));
        within(rx.recv()).await; // the cancel

        // disconnect
        let h = spawn_call(&reg, "c3", BUDGET_MS);
        expect_call(&mut rx).await;
        assert!(reg.in_flight("d1"));
        reg.disconnect("d1", conn);
        within(h).await.unwrap().unwrap_err();
        assert!(!reg.in_flight("d1"));
    }

    #[tokio::test]
    async fn a_call_that_waited_for_room_carries_the_time_left() {
        let reg = Registry::new();
        let (_conn, mut rx) = full_connection(&reg).await;
        let h = spawn_call(&reg, "c1", 1_000);
        tokio::time::sleep(Duration::from_millis(300)).await;
        rx.recv().await; // makes room
        let c = expect_call(&mut rx).await;
        assert!(
            c.deadline_ms > 0 && c.deadline_ms <= 700,
            "{}",
            c.deadline_ms
        );
        assert_eq!(within(h).await.unwrap(), Err(CallError::Deadline));
        // It was queued, so it is cancelled.
        assert_eq!(
            within(rx.recv()).await,
            Some(ToConnector::Cancel {
                call_id: "c1".into()
            })
        );
    }

    #[tokio::test]
    async fn a_call_that_never_got_room_is_not_cancelled() {
        let reg = Registry::with_cancel_wait(Duration::from_millis(100));
        let (conn, mut rx) = full_connection(&reg).await;
        let h = spawn_call(&reg, "c1", 50);
        assert_eq!(within(h).await.unwrap(), Err(CallError::Deadline));
        tokio::time::sleep(Duration::from_millis(200)).await;
        assert_eq!(rx.recv().await, Some(ToConnector::Ping { n: 0 }));
        assert!(rx.try_recv().is_err(), "nothing else queued");
        assert!(!reg.closer("d1", conn).unwrap().is_closed());
    }

    #[tokio::test]
    async fn a_give_up_with_a_full_queue_waits_for_room_for_its_cancel() {
        let reg = Registry::with_cancel_wait(Duration::from_secs(5));
        let (tx, mut rx) = mpsc::channel(1);
        let conn = reg.connect("d1", vec![], tx.clone());
        let h = spawn_call(&reg, "c1", 100);
        // Queued, but the session is busy: then the queue is full.
        tokio::time::sleep(Duration::from_millis(30)).await;
        assert_eq!(within(h).await.unwrap(), Err(CallError::Deadline));
        // The cancel is waiting for room, not given up on.
        tokio::time::sleep(Duration::from_millis(200)).await;
        assert!(!reg.closer("d1", conn).unwrap().is_closed());
        // Room appears: the call, then its cancel, in that order.
        assert_eq!(expect_call(&mut rx).await.call_id, "c1");
        assert_eq!(
            within(rx.recv()).await,
            Some(ToConnector::Cancel {
                call_id: "c1".into()
            })
        );
        assert!(!reg.closer("d1", conn).unwrap().is_closed());
    }

    #[tokio::test]
    async fn a_cancel_that_finds_no_room_closes_the_connection() {
        for caller_leaves in [false, true] {
            let reg = Registry::with_cancel_wait(Duration::from_millis(100));
            let (tx, _rx) = mpsc::channel(1);
            let conn = reg.connect("d1", vec![], tx.clone());
            let closer = reg.closer("d1", conn).unwrap();
            // The call fills the queue, and nothing ever drains it.
            let h = spawn_call(&reg, "c1", if caller_leaves { BUDGET_MS } else { 100 });
            tokio::time::sleep(Duration::from_millis(30)).await;
            if caller_leaves {
                h.abort();
            } else {
                assert_eq!(within(h).await.unwrap(), Err(CallError::Deadline));
            }
            within(closer.closed()).await;
            assert!(reg.tools("d1").is_none(), "the connection is gone");
            assert_eq!(
                within(reg.call("d1", call("c2", 1_000))).await,
                Err(CallError::Offline)
            );
        }
    }

    #[tokio::test]
    async fn release_stamps_a_pending_call_with_the_time_left_less_the_margin() {
        let reg = Registry::new();
        let (tx, mut rx) = mpsc::channel(8);
        let conn = reg.connect("d1", vec![], tx);
        let h = spawn_call(&reg, "c1", 10_000);
        let mut c = expect_call(&mut rx).await;
        tokio::time::sleep(Duration::from_millis(300)).await;
        assert!(reg.release(conn, &mut c, Duration::from_secs(2)));
        // 10 s, less the 0.3 s waited, less the 2 s margin.
        assert!(
            (3_000..=7_700).contains(&c.deadline_ms),
            "{}",
            c.deadline_ms
        );
        reg.complete(conn, result("c1", "ok"));
        assert_eq!(within(h).await.unwrap(), Ok(result("c1", "ok")));
    }

    #[tokio::test]
    async fn release_refuses_a_call_the_relay_gave_up_on() {
        // Timed out.
        let reg = Registry::new();
        let (tx, mut rx) = mpsc::channel(8);
        let conn = reg.connect("d1", vec![], tx);
        let h = spawn_call(&reg, "c1", 50);
        let mut c = expect_call(&mut rx).await;
        assert_eq!(within(h).await.unwrap(), Err(CallError::Deadline));
        assert!(!reg.release(conn, &mut c, Duration::ZERO));
        within(rx.recv()).await; // its cancel

        // The caller went away.
        let h = spawn_call(&reg, "c2", BUDGET_MS);
        let mut c = expect_call(&mut rx).await;
        h.abort();
        let _ = h.await;
        assert!(!reg.release(conn, &mut c, Duration::ZERO));
        within(rx.recv()).await; // its cancel

        // Its connection was dropped (kicked, replaced or closed); the id is
        // never sent on the old connection, nor taken for the new one's.
        let h = spawn_call(&reg, "c3", BUDGET_MS);
        let mut c = expect_call(&mut rx).await;
        reg.kick("d1");
        assert_eq!(within(h).await.unwrap(), Err(CallError::Disconnected));
        assert!(!reg.release(conn, &mut c, Duration::ZERO));
        let (tx2, mut rx2) = mpsc::channel(8);
        let new = reg.connect("d1", vec![], tx2);
        let h = spawn_call(&reg, "c3", BUDGET_MS);
        let mut c_new = expect_call(&mut rx2).await;
        assert!(!reg.release(conn, &mut c, Duration::ZERO));
        assert!(reg.release(new, &mut c_new, Duration::ZERO));
        reg.complete(new, result("c3", "ok"));
        assert_eq!(within(h).await.unwrap(), Ok(result("c3", "ok")));
    }

    #[tokio::test]
    async fn release_fails_a_call_that_has_no_more_than_the_margin_left() {
        let reg = Registry::new();
        let (tx, mut rx) = mpsc::channel(8);
        let conn = reg.connect("d1", vec![], tx);
        let h = spawn_call(&reg, "c1", 10_000);
        let mut c = expect_call(&mut rx).await;
        let started = Instant::now();
        assert!(!reg.release(conn, &mut c, Duration::from_secs(10)));
        // The caller is told now, and nothing is sent to stop a call the
        // device never got.
        assert_eq!(within(h).await.unwrap(), Err(CallError::Deadline));
        assert!(started.elapsed() < Duration::from_secs(5));
        assert!(!reg.in_flight("d1"));
        tokio::time::sleep(Duration::from_millis(50)).await;
        assert!(rx.try_recv().is_err(), "no cancel");
    }

    #[tokio::test]
    async fn dropping_the_caller_cancels_and_forgets_the_call() {
        let reg = Registry::new();
        let (tx, mut rx) = mpsc::channel(8);
        let conn = reg.connect("d1", vec![], tx);
        let h = spawn_call(&reg, "c1", BUDGET_MS);
        expect_call(&mut rx).await;
        assert!(reg.in_flight("d1"));
        h.abort();
        assert_eq!(
            within(rx.recv()).await,
            Some(ToConnector::Cancel {
                call_id: "c1".into()
            })
        );
        assert!(!reg.in_flight("d1"));
        // The id is free again.
        let h = spawn_call(&reg, "c1", BUDGET_MS);
        expect_call(&mut rx).await;
        reg.complete(conn, result("c1", "again"));
        assert_eq!(within(h).await.unwrap(), Ok(result("c1", "again")));
    }

    #[tokio::test]
    async fn unacked_written_call_fails_not_received_and_cancels() {
        let reg = Registry::with_ack_timeout(Duration::from_millis(100));
        let (tx, mut rx) = mpsc::channel(8);
        let conn = reg.connect("d1", vec![], tx);
        let h = spawn_call(&reg, "c1", BUDGET_MS);
        let c = expect_call(&mut rx).await;
        reg.call_written(conn, &c.call_id);
        assert_eq!(within(h).await.unwrap(), Err(CallError::NotReceived));
        assert_eq!(
            within(rx.recv()).await,
            Some(ToConnector::Cancel {
                call_id: "c1".into()
            })
        );
        assert!(!reg.ack(conn, "c1"));
        assert!(!reg.in_flight("d1"));
    }

    #[tokio::test]
    async fn acked_written_call_waits_for_result() {
        let reg = Registry::with_ack_timeout(Duration::from_millis(100));
        let (tx, mut rx) = mpsc::channel(8);
        let conn = reg.connect("d1", vec![], tx);
        let h = spawn_call(&reg, "c1", BUDGET_MS);
        let c = expect_call(&mut rx).await;
        reg.call_written(conn, &c.call_id);
        assert!(reg.ack(conn, "c1"));
        assert!(!reg.ack(conn, "c1"));
        tokio::time::sleep(Duration::from_millis(200)).await;
        reg.complete(conn, result("c1", "ok"));
        assert_eq!(within(h).await.unwrap(), Ok(result("c1", "ok")));
    }
}
