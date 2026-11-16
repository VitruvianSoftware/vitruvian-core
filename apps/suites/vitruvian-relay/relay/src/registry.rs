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
}

impl CallError {
    pub fn user_message(&self) -> &'static str {
        match self {
            CallError::Offline => "Your computer is offline.",
            CallError::Disconnected => "Your computer disconnected; try again.",
            CallError::Deadline => "The command took too long.",
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
    done: oneshot::Sender<Result<CallResult, CallError>>,
}

#[derive(Default)]
struct State {
    next_conn: u64,
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
    tx: mpsc::Sender<ToConnector>,
    armed: bool,
}

impl Drop for PendingGuard<'_> {
    fn drop(&mut self) {
        if self.armed {
            self.registry
                .state
                .lock()
                .unwrap()
                .pending
                .remove(&self.call_id);
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

    /// Sends the call down the device's connection and waits for its result,
    /// its deadline, or the connection ending, whichever comes first.
    pub async fn call(&self, device_id: &str, call: Call) -> Result<CallResult, CallError> {
        let call_id = call.call_id.clone();
        let deadline = Duration::from_millis(call.deadline_ms);
        let (done, rx) = oneshot::channel();
        let tx = {
            let mut st = self.state.lock().unwrap();
            let conn = st.devices.get(device_id).ok_or(CallError::Offline)?;
            let (conn_id, tx) = (conn.id, conn.tx.clone());
            st.pending
                .insert(call_id.clone(), Pending { conn_id, done });
            tx
        };
        let mut guard = PendingGuard {
            registry: self,
            call_id: call_id.clone(),
            tx: tx.clone(),
            armed: true,
        };

        if tx.send(ToConnector::Call(call)).await.is_err() {
            // The session's receiver is gone: the connection is already dead.
            return Err(CallError::Disconnected);
        }
        let outcome = tokio::time::timeout(deadline, rx).await;
        guard.armed = false;
        match outcome {
            Ok(Ok(result)) => result,
            // The sender was dropped without an answer.
            Ok(Err(_)) => Err(CallError::Disconnected),
            Err(_) => {
                self.state.lock().unwrap().pending.remove(&call_id);
                let _ = tx.try_send(ToConnector::Cancel { call_id });
                Err(CallError::Deadline)
            }
        }
    }

    /// Hands a device's result to the caller waiting for it. A result nobody is
    /// waiting for (late, repeated, or cancelled) is dropped.
    pub fn complete(&self, result: CallResult) {
        let pending = self.state.lock().unwrap().pending.remove(&result.call_id);
        if let Some(p) = pending {
            let _ = p.done.send(Ok(result));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use tokio::time::Instant;

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
        match rx.recv().await.expect("frame") {
            ToConnector::Call(c) => c,
            other => panic!("expected call, got {other:?}"),
        }
    }

    #[tokio::test(start_paused = true)]
    async fn call_returns_device_result() {
        let reg = Registry::new();
        let (tx, mut rx) = mpsc::channel(8);
        reg.connect("d1", vec![], tx);
        let r = reg.clone();
        let h = tokio::spawn(async move { r.call("d1", call("c1", 180_000)).await });
        let sent = expect_call(&mut rx).await;
        assert_eq!(sent.call_id, "c1");
        reg.complete(result("c1", "hi"));
        assert_eq!(h.await.unwrap(), Ok(result("c1", "hi")));
    }

    #[tokio::test(start_paused = true)]
    async fn concurrent_calls_get_their_own_results() {
        let reg = Registry::new();
        let (tx, mut rx) = mpsc::channel(8);
        reg.connect("d1", vec![], tx);
        let (r1, r2) = (reg.clone(), reg.clone());
        let h1 = tokio::spawn(async move { r1.call("d1", call("c1", 180_000)).await });
        let h2 = tokio::spawn(async move { r2.call("d1", call("c2", 180_000)).await });
        expect_call(&mut rx).await;
        expect_call(&mut rx).await;
        reg.complete(result("c2", "second"));
        reg.complete(result("c1", "first"));
        assert_eq!(h1.await.unwrap(), Ok(result("c1", "first")));
        assert_eq!(h2.await.unwrap(), Ok(result("c2", "second")));
    }

    #[tokio::test(start_paused = true)]
    async fn pending_call_fails_when_device_drops() {
        let reg = Registry::new();
        let (tx, mut rx) = mpsc::channel(8);
        let conn = reg.connect("d1", vec![], tx);
        let r = reg.clone();
        let started = Instant::now();
        // A long deadline: only the disconnect can end this call quickly.
        let h = tokio::spawn(async move { r.call("d1", call("c1", 180_000)).await });
        expect_call(&mut rx).await;
        reg.disconnect("d1", conn);
        assert_eq!(h.await.unwrap(), Err(CallError::Disconnected));
        assert!(started.elapsed() < Duration::from_millis(100));
    }

    #[tokio::test(start_paused = true)]
    async fn call_to_offline_device_fails_fast() {
        let reg = Registry::new();
        let started = Instant::now();
        assert_eq!(
            reg.call("nobody", call("c1", 180_000)).await,
            Err(CallError::Offline)
        );
        assert!(started.elapsed() < Duration::from_millis(100));
    }

    #[tokio::test(start_paused = true)]
    async fn deadline_expiry_sends_cancel() {
        let reg = Registry::new();
        let (tx, mut rx) = mpsc::channel(8);
        reg.connect("d1", vec![], tx);
        let r = reg.clone();
        let h = tokio::spawn(async move { r.call("d1", call("c1", 5_000)).await });
        expect_call(&mut rx).await;
        assert_eq!(h.await.unwrap(), Err(CallError::Deadline));
        assert_eq!(
            rx.recv().await,
            Some(ToConnector::Cancel {
                call_id: "c1".into()
            })
        );
        // A late result for the cancelled call is ignored, not a panic.
        reg.complete(result("c1", "late"));
    }

    #[tokio::test(start_paused = true)]
    async fn reconnect_replaces_old_connection() {
        let reg = Registry::new();
        let (tx1, mut rx1) = mpsc::channel(8);
        let old = reg.connect("d1", vec![tool("old")], tx1);
        let r = reg.clone();
        let h = tokio::spawn(async move { r.call("d1", call("c1", 180_000)).await });
        expect_call(&mut rx1).await;

        let (tx2, mut rx2) = mpsc::channel(8);
        reg.connect("d1", vec![tool("new")], tx2);
        // The old connection's call fails and its channel closes.
        assert_eq!(h.await.unwrap(), Err(CallError::Disconnected));
        assert!(rx1.recv().await.is_none());
        assert_eq!(reg.tools("d1").unwrap()[0].name, "new");

        // The old session ending late must not remove the new connection.
        reg.disconnect("d1", old);
        assert!(reg.tools("d1").is_some());

        // New calls go to the new connection.
        let r = reg.clone();
        let h = tokio::spawn(async move { r.call("d1", call("c2", 180_000)).await });
        expect_call(&mut rx2).await;
        reg.complete(result("c2", "ok"));
        assert_eq!(h.await.unwrap(), Ok(result("c2", "ok")));
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

    #[tokio::test(start_paused = true)]
    async fn kick_fails_pending_calls() {
        let reg = Registry::new();
        let (tx, mut rx) = mpsc::channel(8);
        reg.connect("d1", vec![], tx);
        let r = reg.clone();
        let h = tokio::spawn(async move { r.call("d1", call("c1", 180_000)).await });
        expect_call(&mut rx).await;
        reg.kick("d1");
        assert_eq!(h.await.unwrap(), Err(CallError::Disconnected));
        assert!(rx.recv().await.is_none());
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
}
