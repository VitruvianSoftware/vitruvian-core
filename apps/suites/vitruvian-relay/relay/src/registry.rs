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

use tokio::sync::{mpsc, oneshot, watch, Notify};
use vitruvian_relay_protocol::{
    Call, CallResult, ToConnector, ToolDef, ACK_SECS, RECONNECT_GRACE_SECS,
};

/// How long the relay waits for the device's `Ack` after writing a `Call`.
pub const ACK_TIMEOUT: Duration = Duration::from_secs(ACK_SECS);

/// How long a call whose device link dropped waits for the device to come
/// back with its result, before it fails `Disconnected`.
pub const RECONNECT_GRACE: Duration = Duration::from_secs(RECONNECT_GRACE_SECS);

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
    /// The device the call was sent to: its result is accepted from that
    /// device's current connection, which after a dropped link is not the
    /// one the call went out on.
    device_id: String,
    /// The connection the call was sent on.
    conn_id: ConnectionId,
    /// Tells this entry apart from a later call that reused the same id after
    /// this one was forgotten, so a stale guard or deadline never removes it.
    token: u64,
    /// When the relay stops waiting for this call.
    deadline: Instant,
    /// Notified when the session finishes writing `Call` to the socket.
    written: Option<oneshot::Sender<()>>,
    /// Notified when the device acknowledges receipt of the call; `None`
    /// once it has (so a second `Ack` is told apart from the first).
    ack: Option<oneshot::Sender<()>>,
    /// Set to `true` when the device says an approval dialog is open for
    /// the call (`ToRelay::Pending`). `None` for a caller that does not care.
    approval: Option<watch::Sender<bool>>,
    done: oneshot::Sender<Result<CallResult, CallError>>,
}

/// The most `Cancel`s kept for one device that is not connected.
const MAX_OWED_CANCELS: usize = 256;

#[derive(Default)]
struct State {
    next_conn: u64,
    next_token: u64,
    devices: HashMap<String, Connection>,
    pending: HashMap<String, Pending>,
    /// `Cancel`s the relay owes a device it could not reach when it gave up
    /// on a call (the device had no connection, or its session was ending):
    /// sent on its next connection, until the call's own deadline. The
    /// device may still have the call (a dialog open, a command running);
    /// the relay must never fail a call without telling it.
    owed: HashMap<String, Vec<(String, Instant)>>,
}

impl State {
    /// Ends a connection (if it is the current one). Dropping its `tx`
    /// closes the session's receiving side.
    ///
    /// A call the device may have received is kept, to be answered over its
    /// next connection: `hold` says so, and the connection's id is returned
    /// for the caller to start the grace timer ([`Registry::hold`]). Without
    /// `hold`, or for a call that never reached the socket (there is nothing
    /// to wait for), the call fails `Disconnected` now.
    fn drop_connection(
        &mut self,
        device_id: &str,
        only: Option<ConnectionId>,
        hold: bool,
    ) -> Option<ConnectionId> {
        match self.devices.get(device_id) {
            Some(c) if only.is_none_or(|id| id == c.id) => {}
            _ => return None,
        }
        let conn = self.devices.remove(device_id).unwrap();
        let mut held = false;
        let ids: Vec<String> = self
            .pending
            .iter()
            .filter(|(_, p)| p.conn_id == conn.id)
            .map(|(k, _)| k.clone())
            .collect();
        for id in ids {
            if hold && self.pending.get(&id).is_some_and(|p| p.written.is_none()) {
                held = true;
            } else if let Some(p) = self.pending.remove(&id) {
                let _ = p.done.send(Err(CallError::Disconnected));
                // The device may have it (it was written): the connection is
                // gone, so the `Cancel` waits for the next one.
                if p.written.is_none() {
                    self.tell_to_stop(device_id, id, p.deadline);
                }
            }
        }
        held.then_some(conn.id)
    }

    /// Remembers a `Cancel` to send when the device next connects.
    fn owe(&mut self, device_id: &str, call_id: String, deadline: Instant) {
        let now = Instant::now();
        if deadline <= now {
            return;
        }
        let list = self.owed.entry(device_id.to_string()).or_default();
        list.retain(|(_, d)| *d > now);
        if list.len() >= MAX_OWED_CANCELS {
            list.remove(0);
        }
        list.push((call_id, deadline));
    }

    /// Tells the device to stop a call the relay has failed: now, on its
    /// current connection, if there is room; else when it next connects.
    fn tell_to_stop(&mut self, device_id: &str, call_id: String, deadline: Instant) {
        let frame = ToConnector::Cancel {
            call_id: call_id.clone(),
        };
        if self
            .devices
            .get(device_id)
            .is_some_and(|c| c.tx.try_send(frame).is_ok())
        {
            return;
        }
        self.owe(device_id, call_id, deadline);
    }

    /// Sends a freshly connected device the `Cancel`s it is owed, as many as
    /// the connection's queue has room for. Returns the ones that did not
    /// fit (still owed, in order) for the caller to send as room frees
    /// ([`Registry::send_leftovers`]): up to [`MAX_OWED_CANCELS`] can be
    /// owed, more than the queue holds.
    fn send_owed(&mut self, device_id: &str) -> Vec<(String, Instant)> {
        let Some(list) = self.owed.remove(device_id) else {
            return Vec::new();
        };
        let now = Instant::now();
        let Some(c) = self.devices.get(device_id) else {
            return Vec::new();
        };
        let mut left = Vec::new();
        for (call_id, deadline) in list {
            if deadline <= now {
                continue;
            }
            // Once one does not fit, the rest wait behind it, in order.
            if !left.is_empty() {
                left.push((call_id, deadline));
                continue;
            }
            match c.tx.try_send(ToConnector::Cancel {
                call_id: call_id.clone(),
            }) {
                Ok(()) => {}
                // A closed queue is a dead connection: the leftovers go
                // through `cancel`, which owes them again.
                Err(_) => left.push((call_id, deadline)),
            }
        }
        left
    }

    /// A device connected: its calls held from an earlier connection move
    /// to the new one, and wait on for the result or their own deadline.
    /// The grace period only decides how long a call waits for a device
    /// that has not come back.
    fn rebind(&mut self, device_id: &str, conn: ConnectionId) {
        for p in self.pending.values_mut() {
            if p.device_id == device_id {
                p.conn_id = conn;
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
    reconnect_grace: Duration,
}

impl Default for Registry {
    fn default() -> Self {
        Registry {
            state: Arc::default(),
            cancel_wait: CANCEL_WAIT,
            ack_timeout: ACK_TIMEOUT,
            reconnect_grace: RECONNECT_GRACE,
        }
    }
}

/// Forgets a call if its caller goes away (the future running it is dropped:
/// stopped by a cancel from the AI app), and tells the device to stop it. An
/// AI app that merely gives up on its HTTP request does not drop the call:
/// `mcp.rs` runs it on its own task and parks it (`parked.rs`).
struct PendingGuard<'a> {
    registry: &'a Registry,
    device_id: String,
    call_id: String,
    token: u64,
    deadline: Instant,
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
                std::mem::take(&mut self.call_id),
                self.deadline,
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

    /// A registry whose calls wait `ack_timeout` for the device's `Ack`, and
    /// hold a call `reconnect_grace` after its link drops.
    pub fn with_timeouts(ack_timeout: Duration, reconnect_grace: Duration) -> Self {
        Registry {
            ack_timeout,
            reconnect_grace,
            ..Self::default()
        }
    }

    /// A registry whose calls wait `d` for the device's `Ack`.
    #[cfg(test)]
    pub(crate) fn with_ack_timeout(d: Duration) -> Self {
        Self::with_timeouts(d, RECONNECT_GRACE)
    }

    /// A registry that holds a call `d` after its link drops (tests).
    #[cfg(test)]
    pub(crate) fn with_reconnect_grace(d: Duration) -> Self {
        Self::with_timeouts(ACK_TIMEOUT, d)
    }

    /// This registry (the same state), but its `Cancel`s wait `d` for room.
    #[cfg(test)]
    pub(crate) fn cancel_waiting(&self, d: Duration) -> Self {
        Registry {
            cancel_wait: d,
            ..self.clone()
        }
    }

    /// Starts the grace period for the calls `drop_connection` kept: those
    /// still waiting for the device when it ends fail `Disconnected`.
    fn hold(&self, held: Option<ConnectionId>) {
        let Some(id) = held else { return };
        if self.reconnect_grace.is_zero() {
            return self.expire(id);
        }
        match tokio::runtime::Handle::try_current() {
            Ok(h) => {
                let (reg, grace) = (self.clone(), self.reconnect_grace);
                h.spawn(async move {
                    tokio::time::sleep(grace).await;
                    reg.expire(id);
                });
            }
            // No runtime to wait in (shutting down): nothing can answer.
            Err(_) => self.expire(id),
        }
    }

    /// Fails what is still pending on connection `id`, which has been gone
    /// for the whole grace period without its device coming back (a device
    /// that did has had its calls moved to its new connection).
    fn expire(&self, id: ConnectionId) {
        let mut st = self.state.lock().unwrap();
        let ids: Vec<String> = st
            .pending
            .iter()
            .filter(|(_, p)| p.conn_id == id)
            .map(|(k, _)| k.clone())
            .collect();
        for call_id in ids {
            if let Some(p) = st.pending.remove(&call_id) {
                let _ = p.done.send(Err(CallError::Disconnected));
                if p.written.is_none() {
                    st.tell_to_stop(&p.device_id, call_id, p.deadline);
                }
            }
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
        match p.ack.take() {
            Some(tx) => {
                let _ = tx.send(());
                true
            }
            None => false,
        }
    }

    /// The device says an approval dialog is open for a pending call on
    /// `conn`: whoever watches the call is told ([`Registry::call_watching`]).
    /// `false` for a call that is not pending on that connection.
    pub fn pending(&self, conn: ConnectionId, call_id: &str) -> bool {
        let st = self.state.lock().unwrap();
        let Some(p) = st.pending.get(call_id).filter(|p| p.conn_id == conn) else {
            return false;
        };
        if let Some(tx) = &p.approval {
            tx.send_replace(true);
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

    /// Ends connection `id` now: its pending calls fail (nothing is held)
    /// and its session stops without sending what is still queued.
    fn close_now(&self, device_id: &str, id: ConnectionId) {
        let mut st = self.state.lock().unwrap();
        if let Some(c) = st.devices.get(device_id).filter(|c| c.id == id) {
            c.closer.close();
        }
        st.drop_connection(device_id, Some(id), false);
    }

    /// Tells the device to stop a call the relay has given up on. That must
    /// never be lost. It goes on the device's current connection, which is
    /// not necessarily the one the call went out on; with none (or one
    /// whose session is ending) it waits for the device's next connection.
    /// If the queue has no room, the cancel waits for it (in order, behind
    /// the call it cancels) for `cancel_wait`; failing that, the connection
    /// is closed, which the connector treats as a drop, and the cancel
    /// waits for the next connection.
    fn cancel(&self, device_id: &str, call_id: String, deadline: Instant) {
        let (id, tx) = {
            let mut st = self.state.lock().unwrap();
            match st.devices.get(device_id).map(|c| (c.id, c.tx.clone())) {
                Some(c) => c,
                None => {
                    st.owe(device_id, call_id, deadline);
                    return;
                }
            }
        };
        let frame = ToConnector::Cancel {
            call_id: call_id.clone(),
        };
        let frame = match tx.try_send(frame) {
            Ok(()) => return,
            // The session is gone: so is the connection.
            Err(mpsc::error::TrySendError::Closed(_)) => {
                self.state.lock().unwrap().owe(device_id, call_id, deadline);
                return;
            }
            Err(mpsc::error::TrySendError::Full(f)) => f,
        };
        let (reg, device, wait) = (self.clone(), device_id.to_string(), self.cancel_wait);
        let closer = move |reg: &Registry| {
            reg.close_now(&device, id);
            reg.state
                .lock()
                .unwrap()
                .tell_to_stop(&device, call_id, deadline);
        };
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

    /// Sends the owed `Cancel`s that did not fit in a new connection's queue,
    /// each as room frees (`cancel` waits for it, and closes a connection
    /// that never makes any, owing the rest again).
    fn send_leftovers(&self, device_id: &str, left: Vec<(String, Instant)>) {
        for (call_id, deadline) in left {
            self.cancel(device_id, call_id, deadline);
        }
    }

    /// Registers a live connection. A newer connection for the same device
    /// replaces the old one; the calls the old one carried (and any held
    /// from an earlier drop) move to the new one and wait there.
    pub fn connect(
        &self,
        device_id: &str,
        tools: Vec<ToolDef>,
        tx: mpsc::Sender<ToConnector>,
    ) -> ConnectionId {
        let mut st = self.state.lock().unwrap();
        st.drop_connection(device_id, None, true);
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
        st.rebind(device_id, id);
        let left = st.send_owed(device_id);
        drop(st);
        self.send_leftovers(device_id, left);
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
        st.drop_connection(device_id, None, true);
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
        st.rebind(device_id, id);
        let left = st.send_owed(device_id);
        drop(st);
        self.send_leftovers(device_id, left);
        Some((id, closer))
    }

    /// Ends the connection `id`, if it is still the device's current one (a
    /// stale session ending late must not remove its replacement). Its
    /// pending calls wait for the device to reconnect (`RECONNECT_GRACE`).
    pub fn disconnect(&self, device_id: &str, id: ConnectionId) {
        let held = self
            .state
            .lock()
            .unwrap()
            .drop_connection(device_id, Some(id), true);
        self.hold(held);
    }

    /// Closes the device's live connection, failing its pending calls now
    /// (the device was registered again: nothing is held for it).
    pub fn kick(&self, device_id: &str) {
        self.state
            .lock()
            .unwrap()
            .drop_connection(device_id, None, false);
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
    pub async fn call(&self, device_id: &str, call: Call) -> Result<CallResult, CallError> {
        self.call_watching(device_id, call, None).await
    }

    /// [`Registry::call`], and `approval` is set to `true` when the device
    /// reports an approval dialog open for the call ([`Registry::pending`]).
    pub async fn call_watching(
        &self,
        device_id: &str,
        mut call: Call,
        approval: Option<watch::Sender<bool>>,
    ) -> Result<CallResult, CallError> {
        let call_id = call.call_id.clone();
        let deadline = Duration::from_millis(call.deadline_ms);
        let started = Instant::now();
        let sent = AtomicBool::new(false);
        let (done, mut rx) = oneshot::channel();
        let (written_tx, written_rx) = oneshot::channel();
        let (ack_tx, ack_rx) = oneshot::channel();
        let (tx, token) = {
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
                    device_id: device_id.to_string(),
                    conn_id,
                    token,
                    deadline: started + deadline,
                    written: Some(written_tx),
                    ack: Some(ack_tx),
                    approval,
                    done,
                },
            );
            (tx, token)
        };
        let mut guard = PendingGuard {
            registry: self,
            device_id: device_id.to_string(),
            call_id: call_id.clone(),
            token,
            deadline: started + deadline,
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
                        .is_some_and(|p| p.token == token && p.ack.is_some())
                    {
                        st.pending.remove(&call_id);
                        true
                    } else {
                        false
                    }
                };
                if timed_out {
                    self.cancel(device_id, call_id.clone(), started + deadline);
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
                    self.cancel(device_id, call_id, started + deadline);
                }
                Err(CallError::Deadline)
            }
        }
    }

    /// Hands a device's result to the caller waiting for it. `conn` is the
    /// connection the result arrived on: it must be the device's current one
    /// (an old one that outlived a reconnect is dropped). The call itself
    /// may have gone out on an earlier connection of the same device, one
    /// that dropped and came back.
    ///
    /// `true` if the session should send `ResultAck`: the result was handed
    /// over, or nobody holds the call any more (a repeat of a result already
    /// taken, or for a call the relay gave up on), so the device can stop
    /// keeping it. `false` for a result that came on a connection that is
    /// not the device's, or for a call that belongs to another device.
    pub fn complete(&self, device_id: &str, conn: ConnectionId, result: CallResult) -> bool {
        let mut st = self.state.lock().unwrap();
        if st.devices.get(device_id).is_none_or(|c| c.id != conn) {
            return false;
        }
        match st.pending.get(&result.call_id) {
            Some(p) if p.device_id != device_id => false,
            Some(_) => {
                if let Some(p) = st.pending.remove(&result.call_id) {
                    let _ = p.done.send(Ok(result));
                }
                true
            }
            None => true,
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
        reg.complete("d1", conn, result("c1", "hi"));
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
        reg.complete("d1", conn, result("c2", "second"));
        reg.complete("d1", conn, result("c1", "first"));
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
        reg.complete("d1", conn, result("c1", "late"));
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
        reg.complete("d1", old, result("c2", "from the old connection"));
        assert!(reg.in_flight("d1"));
        // ...and the new connection's own result is accepted.
        reg.complete("d1", new, result("c2", "ok"));
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
        reg.complete("d1", conn, result("c1", "one"));
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
        reg.complete("d1", conn, result("c1", "x"));
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
        reg.complete("d1", conn, result("c1", "ok"));
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
        reg.complete("d1", new, result("c3", "ok"));
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
        reg.complete("d1", conn, result("c1", "again"));
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
        reg.complete("d1", conn, result("c1", "ok"));
        assert_eq!(within(h).await.unwrap(), Ok(result("c1", "ok")));
    }
    /// Connects `d1`, sends one call to it and marks it written and acked,
    /// as a device that has the call and is running it.
    async fn running_call(
        reg: &Registry,
        id: &str,
        deadline_ms: u64,
    ) -> (
        ConnectionId,
        mpsc::Receiver<ToConnector>,
        tokio::task::JoinHandle<Result<CallResult, CallError>>,
    ) {
        let (tx, mut rx) = mpsc::channel(8);
        let conn = reg.connect("d1", vec![], tx);
        let h = spawn_call(reg, id, deadline_ms);
        let c = expect_call(&mut rx).await;
        reg.call_written(conn, &c.call_id);
        assert!(reg.ack(conn, &c.call_id));
        (conn, rx, h)
    }

    #[tokio::test]
    async fn a_dropped_connection_holds_its_calls_for_the_grace_period() {
        let reg = Registry::with_reconnect_grace(Duration::from_millis(300));
        let (old, _rx_old, mut h) = running_call(&reg, "c1", BUDGET_MS).await;
        reg.disconnect("d1", old);
        // Not failed yet: the device may be back within the grace.
        assert!(
            tokio::time::timeout(Duration::from_millis(100), &mut h)
                .await
                .is_err(),
            "the call failed before the grace was over"
        );
        // Past it, it fails.
        assert_eq!(within(h).await.unwrap(), Err(CallError::Disconnected));
        assert!(!reg.in_flight("d1"));
    }

    #[tokio::test]
    async fn a_held_call_gets_its_result_from_the_new_connection() {
        let reg = Registry::with_reconnect_grace(Duration::from_secs(30));
        let (old, _rx_old, h) = running_call(&reg, "c1", BUDGET_MS).await;
        reg.disconnect("d1", old);
        let (tx, _rx_new) = mpsc::channel(8);
        let new = reg.connect("d1", vec![], tx);
        assert!(reg.complete("d1", new, result("c1", "survived")));
        assert_eq!(within(h).await.unwrap(), Ok(result("c1", "survived")));
        // A repeat finds nobody waiting, but is still acknowledged so the
        // device stops sending it.
        assert!(reg.complete("d1", new, result("c1", "survived")));
    }

    #[tokio::test]
    async fn a_replaced_connection_holds_its_calls_for_the_new_one() {
        let reg = Registry::with_reconnect_grace(Duration::from_secs(30));
        let (_old, _rx_old, h) = running_call(&reg, "c1", BUDGET_MS).await;
        // The device dials again before the relay noticed the old link die.
        let (tx, _rx_new) = mpsc::channel(8);
        let new = reg.connect("d1", vec![], tx);
        assert!(reg.complete("d1", new, result("c1", "ok")));
        assert_eq!(within(h).await.unwrap(), Ok(result("c1", "ok")));
    }

    #[tokio::test]
    async fn a_result_is_accepted_only_from_the_devices_own_current_connection() {
        let reg = Registry::with_reconnect_grace(Duration::from_secs(30));
        let (old, _rx_old, mut h) = running_call(&reg, "c1", BUDGET_MS).await;
        let (tx, _rx_other) = mpsc::channel(8);
        let other = reg.connect("d2", vec![], tx);
        // Another device cannot answer this device's call.
        assert!(!reg.complete("d2", other, result("c1", "not yours")));
        // Nor can the device's own dropped connection.
        reg.disconnect("d1", old);
        assert!(!reg.complete("d1", old, result("c1", "from the dead")));
        assert!(
            tokio::time::timeout(Duration::from_millis(100), &mut h)
                .await
                .is_err(),
            "a refused result must leave the call waiting"
        );
        let (tx, _rx_new) = mpsc::channel(8);
        let new = reg.connect("d1", vec![], tx);
        assert!(reg.complete("d1", new, result("c1", "mine")));
        assert_eq!(within(h).await.unwrap(), Ok(result("c1", "mine")));
    }

    #[tokio::test]
    async fn a_call_that_never_reached_the_socket_fails_at_once_when_the_link_drops() {
        let reg = Registry::with_reconnect_grace(Duration::from_secs(30));
        let (tx, mut rx) = mpsc::channel(8);
        let conn = reg.connect("d1", vec![], tx);
        let h = spawn_call(&reg, "c1", BUDGET_MS);
        expect_call(&mut rx).await;
        // Never `call_written`: the device cannot have it.
        reg.disconnect("d1", conn);
        assert_eq!(within(h).await.unwrap(), Err(CallError::Disconnected));
    }

    #[tokio::test]
    async fn kick_does_not_hold_calls() {
        let reg = Registry::with_reconnect_grace(Duration::from_secs(30));
        let (_conn, _rx, h) = running_call(&reg, "c1", BUDGET_MS).await;
        reg.kick("d1");
        assert_eq!(within(h).await.unwrap(), Err(CallError::Disconnected));
    }

    #[tokio::test]
    async fn a_held_calls_deadline_still_applies() {
        let reg = Registry::with_reconnect_grace(Duration::from_secs(30));
        let (old, _rx_old, h) = running_call(&reg, "c1", 100).await;
        reg.disconnect("d1", old);
        assert_eq!(within(h).await.unwrap(), Err(CallError::Deadline));
        assert!(!reg.in_flight("d1"));
    }

    #[tokio::test]
    async fn giving_up_on_a_held_call_cancels_it_on_the_new_connection() {
        let reg = Registry::with_reconnect_grace(Duration::from_secs(30));
        let (old, _rx_old, h) = running_call(&reg, "c1", BUDGET_MS).await;
        reg.disconnect("d1", old);
        let (tx, mut rx_new) = mpsc::channel(8);
        reg.connect("d1", vec![], tx);
        h.abort();
        assert_eq!(
            within(rx_new.recv()).await,
            Some(ToConnector::Cancel {
                call_id: "c1".into()
            })
        );
    }

    #[test]
    fn production_defaults_are_the_protocol_values() {
        assert_eq!(ACK_TIMEOUT, Duration::from_secs(5));
        assert_eq!(RECONNECT_GRACE, Duration::from_secs(10));
        let reg = Registry::new();
        assert_eq!(reg.ack_timeout, ACK_TIMEOUT);
        assert_eq!(reg.reconnect_grace, RECONNECT_GRACE);
    }

    #[tokio::test]
    async fn a_reconnected_devices_held_calls_outlast_the_grace_period() {
        let reg = Registry::with_reconnect_grace(Duration::from_millis(200));
        let (old, _rx_old, mut h) = running_call(&reg, "c1", BUDGET_MS).await;
        reg.disconnect("d1", old);
        let (tx, mut rx_new) = mpsc::channel(8);
        let new = reg.connect("d1", vec![], tx);
        // Well past the grace: the device is back, so the call still waits.
        assert!(
            tokio::time::timeout(Duration::from_millis(600), &mut h)
                .await
                .is_err(),
            "the call failed although the device had reconnected"
        );
        assert!(reg.in_flight("d1"));
        // Nothing was cancelled either.
        assert!(rx_new.try_recv().is_err());
        assert!(reg.complete("d1", new, result("c1", "late but real")));
        assert_eq!(within(h).await.unwrap(), Ok(result("c1", "late but real")));
    }

    #[tokio::test]
    async fn a_call_failed_while_the_device_was_away_is_cancelled_when_it_returns() {
        let reg = Registry::with_reconnect_grace(Duration::from_millis(100));
        let (old, _rx_old, h) = running_call(&reg, "c1", BUDGET_MS).await;
        reg.disconnect("d1", old);
        // The device stays away past the grace: the call fails.
        assert_eq!(within(h).await.unwrap(), Err(CallError::Disconnected));
        // When it comes back it is told to drop the call, and the call is
        // not brought back to life.
        let (tx, mut rx_new) = mpsc::channel(8);
        let new = reg.connect("d1", vec![], tx);
        assert_eq!(
            within(rx_new.recv()).await,
            Some(ToConnector::Cancel {
                call_id: "c1".into()
            })
        );
        assert!(!reg.in_flight("d1"));
        // Its result is refused (nobody waits) but acknowledged.
        assert!(reg.complete("d1", new, result("c1", "too late")));
    }

    #[tokio::test]
    async fn kick_and_close_send_cancel_to_current_connection() {
        // kick: the device is registered again; the calls fail, and the
        // device (when it connects) is told to stop them.
        let reg = Registry::with_reconnect_grace(Duration::from_secs(30));
        let (_conn, _rx, h) = running_call(&reg, "c1", BUDGET_MS).await;
        reg.kick("d1");
        assert_eq!(within(h).await.unwrap(), Err(CallError::Disconnected));
        let (tx, mut rx_new) = mpsc::channel(8);
        reg.connect("d1", vec![], tx);
        assert_eq!(
            within(rx_new.recv()).await,
            Some(ToConnector::Cancel {
                call_id: "c1".into()
            })
        );

        // close: a cancel that finds no room closes the connection; the
        // call it was for, and the others on it, are cancelled on the
        // device's next connection.
        let reg = Registry::with_cancel_wait(Duration::from_millis(100));
        let (tx, _rx) = mpsc::channel(1);
        let conn = reg.connect("d1", vec![], tx);
        let closer = reg.closer("d1", conn).unwrap();
        // The call fills the queue, and nothing ever drains it.
        let h = spawn_call(&reg, "c1", BUDGET_MS);
        tokio::time::sleep(Duration::from_millis(30)).await;
        h.abort();
        within(closer.closed()).await;
        let (tx, mut rx_new) = mpsc::channel(8);
        reg.connect("d1", vec![], tx);
        assert_eq!(
            within(rx_new.recv()).await,
            Some(ToConnector::Cancel {
                call_id: "c1".into()
            })
        );
        // Not twice.
        tokio::time::sleep(Duration::from_millis(50)).await;
        assert!(rx_new.try_recv().is_err());
    }

    #[tokio::test]
    async fn a_cancel_owed_to_an_absent_device_lapses_with_the_calls_deadline() {
        let reg = Registry::with_reconnect_grace(Duration::from_millis(50));
        let (old, _rx_old, h) = running_call(&reg, "c1", 300).await;
        reg.disconnect("d1", old);
        assert_eq!(within(h).await.unwrap(), Err(CallError::Disconnected));
        // Past the call's own deadline the device has dropped it anyway.
        tokio::time::sleep(Duration::from_millis(400)).await;
        let (tx, mut rx_new) = mpsc::channel(8);
        reg.connect("d1", vec![], tx);
        tokio::time::sleep(Duration::from_millis(50)).await;
        assert!(rx_new.try_recv().is_err());
    }

    async fn until(f: impl Fn() -> bool) {
        within(async {
            while !f() {
                tokio::time::sleep(Duration::from_millis(5)).await;
            }
        })
        .await
    }

    /// Task 3 review: up to 256 cancels can be owed to a device that is away,
    /// but a connection's queue holds 64 (`CONNECTION_QUEUE`). The ones that
    /// do not fit when it comes back must wait for room, not be dropped.
    #[tokio::test]
    async fn owed_cancels_beyond_the_queue_are_sent_as_room_frees() {
        const OWED: usize = 200;
        let reg = Registry::new();
        let (tx, mut rx) = mpsc::channel(OWED);
        let conn = reg.connect("d1", vec![], tx);
        let ids: Vec<String> = (0..OWED).map(|i| format!("c{i}")).collect();
        let handles: Vec<_> = ids
            .iter()
            .map(|id| spawn_call(&reg, id, BUDGET_MS))
            .collect();
        for _ in 0..OWED {
            let c = expect_call(&mut rx).await;
            reg.call_written(conn, &c.call_id);
        }
        // The link drops, and the callers go away while it is down: the
        // device is owed a cancel for each.
        reg.disconnect("d1", conn);
        for h in &handles {
            h.abort();
        }
        until(|| {
            reg.state
                .lock()
                .unwrap()
                .owed
                .get("d1")
                .map_or(0, |l| l.len())
                == OWED
        })
        .await;
        // It comes back on a connection whose queue holds 64. Nothing reads
        // it yet, so most of the cancels cannot be sent now.
        let (tx, mut rx) = mpsc::channel(64);
        reg.connect("d1", vec![], tx);
        tokio::time::sleep(Duration::from_millis(100)).await;
        let mut got = Vec::new();
        while got.len() < OWED {
            match within(rx.recv()).await {
                Some(ToConnector::Cancel { call_id }) => got.push(call_id),
                other => panic!("expected a cancel, got {other:?}"),
            }
        }
        let (mut got, mut want) = (got, ids);
        got.sort();
        want.sort();
        assert_eq!(got, want, "every owed cancel arrives, once");
        tokio::time::sleep(Duration::from_millis(50)).await;
        assert!(rx.try_recv().is_err());
    }
}
