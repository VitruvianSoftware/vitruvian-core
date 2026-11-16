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
use std::sync::{Arc, Mutex};
use std::time::Duration;

use tokio::sync::{mpsc, oneshot};
use vitruvian_relay_protocol::{Call, CallResult, ToConnector, ToolDef};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct ConnectionId(u64);

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CallError {
    /// No connection for the device when the call was made.
    Offline,
    /// The connection ended while the call was in flight.
    Disconnected,
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
            CallError::Deadline => "The command took too long.",
            CallError::Duplicate => "That command is already running.",
        }
    }
}

struct Connection {
    id: ConnectionId,
    tx: mpsc::Sender<ToConnector>,
    tools: Vec<ToolDef>,
}

struct Pending {
    conn_id: ConnectionId,
    /// Tells this entry apart from a later call that reused the same id after
    /// this one was forgotten, so a stale guard or deadline never removes it.
    token: u64,
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
#[derive(Clone, Default)]
pub struct Registry {
    state: Arc<Mutex<State>>,
}

/// Forgets a call if its caller goes away (the HTTP request was dropped), and
/// tells the device to stop it.
struct PendingGuard<'a> {
    registry: &'a Registry,
    call_id: String,
    token: u64,
    tx: mpsc::Sender<ToConnector>,
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
        {
            let _ = self.tx.try_send(ToConnector::Cancel {
                call_id: self.call_id.clone(),
            });
        }
    }
}

impl Registry {
    pub fn new() -> Self {
        Self::default()
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
        st.devices
            .insert(device_id.to_string(), Connection { id, tx, tools });
        id
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

    pub fn update_tools(&self, device_id: &str, tools: Vec<ToolDef>) {
        if let Some(c) = self.state.lock().unwrap().devices.get_mut(device_id) {
            c.tools = tools;
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
        let call_id = call.call_id.clone();
        let deadline = Duration::from_millis(call.deadline_ms);
        let (done, mut rx) = oneshot::channel();
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
                    conn_id,
                    token,
                    done,
                },
            );
            (tx, token)
        };
        let mut guard = PendingGuard {
            registry: self,
            call_id: call_id.clone(),
            token,
            tx: tx.clone(),
            armed: true,
        };

        let outcome = tokio::time::timeout(deadline, async {
            // Wait for room in the queue, but give up the moment the
            // connection ends (which answers `rx`).
            tokio::select! {
                permit = tx.reserve() => match permit {
                    Ok(permit) => permit.send(ToConnector::Call(call)),
                    // The session's receiver is gone: the connection is dead.
                    Err(_) => return Err(CallError::Disconnected),
                },
                answer = &mut rx => return answer.unwrap_or(Err(CallError::Disconnected)),
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
                // If a result arrived at the same instant the deadline fired,
                // the deadline wins: the caller gets `Deadline`, the result is
                // dropped, and the device gets a `Cancel` for a call it has
                // already finished (harmless; it ignores unknown ids).
                if self.state.lock().unwrap().forget(&call_id, token) {
                    let _ = tx.try_send(ToConnector::Cancel { call_id });
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
        let h = spawn_call(&reg, "c1", 180_000);
        assert_eq!(expect_call(&mut rx).await.call_id, "c1");
        reg.complete(conn, result("c1", "hi"));
        assert_eq!(within(h).await.unwrap(), Ok(result("c1", "hi")));
    }

    #[tokio::test]
    async fn concurrent_calls_get_their_own_results() {
        let reg = Registry::new();
        let (tx, mut rx) = mpsc::channel(8);
        let conn = reg.connect("d1", vec![], tx);
        let h1 = spawn_call(&reg, "c1", 180_000);
        let h2 = spawn_call(&reg, "c2", 180_000);
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
        let h = spawn_call(&reg, "c1", 180_000);
        expect_call(&mut rx).await;
        let started = Instant::now();
        reg.disconnect("d1", conn);
        assert_eq!(within(h).await.unwrap(), Err(CallError::Disconnected));
        assert!(started.elapsed() < Duration::from_millis(100));
    }

    #[tokio::test]
    async fn call_to_offline_device_fails_fast() {
        let reg = Registry::new();
        let started = Instant::now();
        assert_eq!(
            within(reg.call("nobody", call("c1", 180_000))).await,
            Err(CallError::Offline)
        );
        assert!(started.elapsed() < Duration::from_millis(100));
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
        let h = spawn_call(&reg, "c1", 180_000);
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
        let h = spawn_call(&reg, "c2", 180_000);
        expect_call(&mut rx2).await;
        // A result for c2 reported by the old connection is ignored...
        reg.complete(old, result("c2", "from the old connection"));
        assert!(reg.in_flight("d1"));
        // ...and the new connection's own result is accepted.
        reg.complete(new, result("c2", "ok"));
        assert_eq!(within(h).await.unwrap(), Ok(result("c2", "ok")));
    }

    #[tokio::test]
    async fn update_tools_changes_the_list() {
        let reg = Registry::new();
        let (tx, _rx) = mpsc::channel(8);
        reg.connect("d1", vec![tool("a")], tx);
        assert_eq!(reg.tools("d1"), Some(vec![tool("a")]));
        reg.update_tools("d1", vec![tool("a"), tool("b")]);
        assert_eq!(reg.tools("d1"), Some(vec![tool("a"), tool("b")]));
        assert_eq!(reg.tools("other"), None);
    }

    #[tokio::test]
    async fn kick_fails_pending_calls() {
        let reg = Registry::new();
        let (tx, mut rx) = mpsc::channel(8);
        reg.connect("d1", vec![], tx);
        let h = spawn_call(&reg, "c1", 180_000);
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
        let h = spawn_call(&reg, "c1", 180_000);
        tokio::time::sleep(Duration::from_millis(20)).await;
        assert!(reg.in_flight("d1"));
        let started = Instant::now();
        reg.disconnect("d1", conn);
        assert_eq!(within(h).await.unwrap(), Err(CallError::Disconnected));
        assert!(started.elapsed() < Duration::from_millis(100));
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
        let first = spawn_call(&reg, "c1", 180_000);
        expect_call(&mut rx).await;
        assert_eq!(
            within(reg.call("d1", call("c1", 180_000))).await,
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
        let h = spawn_call(&reg, "c1", 180_000);
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
        rx.recv().await; // the cancel

        // disconnect
        let h = spawn_call(&reg, "c3", 180_000);
        expect_call(&mut rx).await;
        assert!(reg.in_flight("d1"));
        reg.disconnect("d1", conn);
        within(h).await.unwrap().unwrap_err();
        assert!(!reg.in_flight("d1"));
    }

    #[tokio::test]
    async fn dropping_the_caller_cancels_and_forgets_the_call() {
        let reg = Registry::new();
        let (tx, mut rx) = mpsc::channel(8);
        let conn = reg.connect("d1", vec![], tx);
        let h = spawn_call(&reg, "c1", 180_000);
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
        let h = spawn_call(&reg, "c1", 180_000);
        expect_call(&mut rx).await;
        reg.complete(conn, result("c1", "again"));
        assert_eq!(within(h).await.unwrap(), Ok(result("c1", "again")));
    }
}
