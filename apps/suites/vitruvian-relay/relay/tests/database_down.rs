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

//! The database going away and coming back, with the whole relay over HTTP and
//! a real PostgreSQL behind it (a `service_test`, `:database_down_test`).
//!
//! rules_itest cannot stop the Postgres service mid-test, so a small TCP proxy
//! (`pg_support::Proxy`) sits between the relay's store and the database.
//! Cutting the proxy is the database going down; opening it again is the
//! database coming back.

mod pg_support;
mod relay_support;

use std::sync::Arc;
use std::time::{Duration, Instant};

use base64::Engine as _;
use pg_support::{fresh_database, postgres_port, Mode, Proxy};
use relay_support::{post, start_relay, Relay, Reply, ALICE, MCP_CLIENT};
use serde_json::json;
use vitruvian_relay::store::{PgStore, Store};

/// What a person is told (spec: the store being down).
const MESSAGE: &str = "The relay is having trouble right now; try again in a minute.";

/// Alice's side of the relay, on the shared harness.
impl Relay {
    /// `POST /devices` as the connector does: with `existing`, that computer
    /// signing in again (the id is kept), otherwise a new one.
    async fn register_byte(&self, key_byte: u8, existing: Option<&str>) -> Reply {
        let key = base64::engine::general_purpose::STANDARD.encode([key_byte; 32]);
        let mut body = json!({"public_key": key});
        if let Some(id) = existing {
            body["device_id"] = json!(id);
        }
        self.register_body(ALICE, body).await
    }

    /// An AI app's session on `device`: its path and session id.
    async fn open_session(&self, device: &str) -> (String, String) {
        let session = self.session(ALICE, device).await;
        (format!("/mcp/d/{device}"), session)
    }

    async fn tools_call(&self, path: &str, session: &str, id: u64) -> Reply {
        post(
            self.addr,
            path,
            &self.mcp_token(ALICE),
            Some(session),
            json!({"jsonrpc": "2.0", "id": id, "method": "tools/call",
                   "params": {"name": "read_file", "arguments": {"path": "/top/secret"}}}),
        )
        .await
    }
}

fn text_of(r: &Reply) -> String {
    r.json()["result"]["content"][0]["text"]
        .as_str()
        .unwrap_or_default()
        .to_string()
}

/// With the database up and a device registered, a call reaches the device
/// lookup and answers (no computer is connected, so it says so).
async fn assert_calls_work(relay: &Relay, path: &str, session: &str, id: u64) {
    let r = relay.tools_call(path, session, id).await;
    assert_eq!(r.status, 200, "{}", r.body);
    // Which computer, and that it has never been seen (nothing has connected).
    assert_eq!(
        text_of(&r),
        "Your computer \"My Mac\" is offline (last seen never). \
         It may be asleep, shut down or off the network.",
        "{}",
        r.body
    );
}

/// How long the relay may take to say the database is down: the store's own
/// limit is 5 s (connect and query), and a cut road answers at once.
const WITHIN: Duration = Duration::from_secs(5);

#[tokio::test(flavor = "multi_thread")]
async fn database_down_fails_clearly_then_recovers() {
    let db = fresh_database().await;
    let proxy = Proxy::start(postgres_port()).await;
    let relay = start_relay(&db.url_at(proxy.port)).await;

    let r = relay.register_byte(1, None).await;
    assert_eq!(r.status, 200, "{}", r.body);
    let device = r.json()["device_id"].as_str().unwrap().to_string();
    let (path, session) = relay.open_session(&device).await;
    assert_calls_work(&relay, &path, &session, 1).await;

    // The database stops.
    proxy.set(Mode::Down);

    let started = Instant::now();
    let r = relay.tools_call(&path, &session, 2).await;
    assert!(started.elapsed() < WITHIN, "took {:?}", started.elapsed());
    assert_eq!(r.status, 200, "{}", r.body);
    assert_eq!(r.json()["result"]["isError"], true);
    assert_eq!(text_of(&r), MESSAGE);

    let started = Instant::now();
    let r = relay.register_byte(2, None).await;
    assert!(started.elapsed() < WITHIN, "took {:?}", started.elapsed());
    assert_eq!(r.status, 503, "{}", r.body);
    assert_eq!(r.body, MESSAGE);

    let logs = relay.logs();
    assert!(logs.contains("\"outcome\":\"store_unavailable\""), "{logs}");
    assert!(!logs.contains("/top/secret"), "arguments reached the log");

    // The database is back: the very next call works, with the same session.
    proxy.set(Mode::Open);
    assert_calls_work(&relay, &path, &session, 3).await;
    let r = relay.register_byte(3, Some(&device)).await;
    assert_eq!(r.status, 200, "{}", r.body);
    assert_eq!(
        r.json()["device_id"],
        device,
        "registering again keeps the device"
    );
}

/// The road is up but nothing comes back (a database that hangs, not one that
/// is gone): the store's 5 s limit turns that into the same message.
#[tokio::test(flavor = "multi_thread")]
async fn a_silent_database_gets_the_same_message_after_the_limit() {
    let db = fresh_database().await;
    let proxy = Proxy::start(postgres_port()).await;
    let relay = start_relay(&db.url_at(proxy.port)).await;
    let r = relay.register_byte(1, None).await;
    let device = r.json()["device_id"].as_str().unwrap().to_string();
    let (path, session) = relay.open_session(&device).await;

    proxy.set(Mode::Silent);
    let started = Instant::now();
    let r = relay.tools_call(&path, &session, 2).await;
    let took = started.elapsed();
    assert_eq!(text_of(&r), MESSAGE, "{}", r.body);
    // It waited for the limit rather than answering at once, and not longer
    // than it (one limit for the whole step; the upper bound leaves three
    // seconds of slack for a loaded machine, and two limits would be 10 s).
    assert!(
        took >= Duration::from_secs(4) && took < Duration::from_secs(8),
        "took {took:?}"
    );

    proxy.set(Mode::Open);
    assert_calls_work(&relay, &path, &session, 3).await;
}

/// The 5 s limit covers getting a connection AND the query together. Here each
/// answer from the database is 4.6 s late, so getting a connection (the pool
/// checks an idle one first) takes about 4.6 s and the query as long again:
/// each is under 5 s alone, together they are not. The person must still hear
/// within one limit (about 5 s), not after a limit per step (a connection
/// that takes 4.6 s, then a query that gets its own 5 s: about 9.6 s). The
/// bound sits in the middle, [`SLOW_BOUND`]: 2.3 s above the right answer and
/// 2.3 s below the wrong one. A wider gap is not possible: the two differ by
/// the delay, which must stay under the 5 s limit for each step to be fine
/// alone.
const SLOW_DELAY: Duration = Duration::from_millis(4600);
const SLOW_BOUND: Duration = Duration::from_millis(7300);

#[tokio::test(flavor = "multi_thread")]
async fn a_slow_database_is_given_one_limit_in_all_not_one_per_step() {
    let db = fresh_database().await;
    let proxy = Proxy::start(postgres_port()).await;
    let relay = start_relay(&db.url_at(proxy.port)).await;
    let r = relay.register_byte(1, None).await;
    let device = r.json()["device_id"].as_str().unwrap().to_string();
    let (path, session) = relay.open_session(&device).await;
    // Warm: the pool now holds a connection through the proxy.
    assert_calls_work(&relay, &path, &session, 1).await;

    proxy.set(Mode::Slow(SLOW_DELAY));
    let started = Instant::now();
    let r = relay.tools_call(&path, &session, 2).await;
    let took = started.elapsed();
    assert_eq!(text_of(&r), MESSAGE, "{}", r.body);
    assert!(
        took >= Duration::from_secs(4) && took < SLOW_BOUND,
        "took {took:?}"
    );

    // Fast again: works.
    proxy.set(Mode::Open);
    assert_calls_work(&relay, &path, &session, 3).await;
}

/// Calls are kept in the database, not in the relay: one that was recorded by
/// a relay that has since stopped is there for the next one, and the rows hold
/// no content (no column has what the call asked for).
#[tokio::test(flavor = "multi_thread")]
async fn activity_survives_restart() {
    let db = fresh_database().await;
    let first = start_relay(&db.url()).await;
    let r = first.register_byte(1, None).await;
    assert_eq!(r.status, 200, "{}", r.body);
    let device = r.json()["device_id"].as_str().unwrap().to_string();
    let (path, session) = first.open_session(&device).await;
    // `tools_call` asks for /top/secret.
    assert_calls_work(&first, &path, &session, 1).await;

    // The row is written just after the answer goes out.
    let client = db.client().await;
    let rows = async {
        loop {
            let n: i64 = client
                .query_one("SELECT count(*) FROM activity", &[])
                .await
                .unwrap()
                .get(0);
            if n >= 1 {
                return n;
            }
            tokio::time::sleep(Duration::from_millis(20)).await;
        }
    };
    tokio::time::timeout(Duration::from_secs(10), rows)
        .await
        .expect("the call was recorded");

    // The relay stops; another one starts on the same database.
    first.server.abort();
    drop(first);
    let second = start_relay(&db.url()).await;
    let store = PgStore::connect(&db.url(), None, Arc::new(|_| {}))
        .await
        .expect("a store on the same database");
    let kept = store.activity_of(ALICE, None, 10).await.unwrap();
    assert_eq!(kept.len(), 1, "{kept:?}");
    let row = &kept[0];
    assert_eq!(
        (
            row.tool.as_str(),
            row.outcome.as_str(),
            row.device_id.as_str()
        ),
        ("read_file", "offline", device.as_str())
    );
    assert_eq!(row.owner_sub, ALICE);
    assert_eq!(row.client_id, MCP_CLIENT);
    assert!(row.arg_bytes.is_some_and(|n| n > 0));
    assert!(row.duration_ms.is_some());

    // The second relay carries on (same device, new session) and adds to it.
    let (path2, session2) = second.open_session(&device).await;
    assert_calls_work(&second, &path2, &session2, 1).await;
    let both = async {
        loop {
            let rows = store.activity_of(ALICE, None, 10).await.unwrap();
            if rows.len() >= 2 {
                return rows;
            }
            tokio::time::sleep(Duration::from_millis(20)).await;
        }
    };
    let both = tokio::time::timeout(Duration::from_secs(10), both)
        .await
        .expect("the second relay recorded its call");
    assert!(both[0].at >= both[1].at, "newest first");

    // No column holds the arguments: look at every row as text, the way
    // someone running psql would.
    let dump: Vec<String> = client
        .query("SELECT a::text FROM activity a", &[])
        .await
        .unwrap()
        .iter()
        .map(|r| r.get(0))
        .collect();
    assert_eq!(dump.len(), 2);
    assert!(
        dump.iter().all(|row| !row.contains("secret")),
        "arguments reached the database: {dump:?}"
    );
}
