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

//! The rules every [`Store`] must keep, as one body of checks. The unit test
//! runs it against [`crate::store::MemStore`]; the Postgres test
//! (`tests/store_pg.rs`, a `service_test` over a real database) runs it
//! against [`crate::store::PgStore`]. Test support only: nothing in the server
//! calls it.
//!
//! It uses owners and ids of its own (random), but `purge` counts rows in the
//! whole table, so give it a database that nothing else is writing to.

use std::time::{Duration, SystemTime, UNIX_EPOCH};

use crate::devices::NewDevice;
use crate::random_id;
use crate::store::{ActivityRow, Store, StoreError, MAX_DEVICES_PER_USER};

fn new_device(owner: &str, name: &str, key_byte: u8) -> NewDevice {
    NewDevice {
        device_id: random_id(),
        owner_sub: owner.to_string(),
        name: name.to_string(),
        public_key_ed25519: [key_byte; 32],
    }
}

/// A call row at `UNIX_EPOCH + secs` (far in the past, so `purge` can take
/// exactly these).
fn activity(owner: &str, device: &str, tool: &str, secs: u64) -> ActivityRow {
    ActivityRow {
        at: UNIX_EPOCH + Duration::from_secs(secs),
        owner_sub: owner.to_string(),
        device_id: device.to_string(),
        client_id: "claude".into(),
        tool: tool.to_string(),
        arg_bytes: Some(10),
        result_bytes: Some(20),
        duration_ms: Some(30),
        outcome: "ok".into(),
    }
}

pub async fn store_contract(store: &dyn Store) {
    let alice = format!("alice-{}", random_id());
    let bob = format!("bob-{}", random_id());

    // --- insert, get, devices_of
    assert_eq!(store.device("nope").await, Ok(None));
    assert_eq!(store.devices_of(&alice).await, Ok(vec![]));
    let d1 = new_device(&alice, "Work Mac", 1);
    let r1 = store.insert_device(&d1).await.unwrap();
    assert_eq!(
        (
            r1.device_id.as_str(),
            r1.owner_sub.as_str(),
            r1.name.as_str(),
            r1.public_key_ed25519,
            r1.last_seen,
            r1.revoked
        ),
        (
            d1.device_id.as_str(),
            alice.as_str(),
            "Work Mac",
            [1; 32],
            None,
            false
        )
    );
    let recent = SystemTime::now() - Duration::from_secs(300);
    assert!(r1.created_at > recent, "created_at is set by the store");
    assert_eq!(store.device(&d1.device_id).await, Ok(Some(r1.clone())));
    let d2 = new_device(&alice, "Home Mac", 2);
    store.insert_device(&d2).await.unwrap();
    let mine = store.devices_of(&alice).await.unwrap();
    assert_eq!(
        mine.iter().map(|d| d.name.as_str()).collect::<Vec<_>>(),
        ["Work Mac", "Home Mac"],
        "oldest first"
    );
    assert_eq!(store.devices_of(&bob).await, Ok(vec![]));
    // The same id twice is its own error, not "unavailable" and not a panic.
    assert_eq!(store.insert_device(&d1).await, Err(StoreError::DuplicateId));
    assert_eq!(
        store.devices_of(&alice).await.unwrap().len(),
        2,
        "the refused one added nothing"
    );

    // --- rename, only by the owner
    assert_eq!(
        store.rename(&d1.device_id, &alice, "Office").await,
        Ok(true)
    );
    assert_eq!(
        store.rename(&d1.device_id, &bob, "Mine now").await,
        Ok(false)
    );
    assert_eq!(store.rename("nope", &alice, "x").await, Ok(false));
    let renamed = store.device(&d1.device_id).await.unwrap().unwrap();
    assert_eq!(renamed.name, "Office");

    // --- replace_key, only by the owner
    assert_eq!(
        store.replace_key(&d1.device_id, &bob, [9; 32]).await,
        Ok(false),
        "someone else's device is not theirs to rekey"
    );
    assert_eq!(
        store
            .device(&d1.device_id)
            .await
            .unwrap()
            .unwrap()
            .public_key_ed25519,
        [1; 32]
    );
    assert_eq!(
        store.replace_key(&d1.device_id, &alice, [7; 32]).await,
        Ok(true)
    );
    assert_eq!(
        store
            .device(&d1.device_id)
            .await
            .unwrap()
            .unwrap()
            .public_key_ed25519,
        [7; 32]
    );
    assert_eq!(store.replace_key("nope", &alice, [7; 32]).await, Ok(false));

    // --- touch_seen
    let seen = SystemTime::now() - Duration::from_secs(60);
    store.touch_seen(&d1.device_id, seen).await.unwrap();
    let got = store
        .device(&d1.device_id)
        .await
        .unwrap()
        .unwrap()
        .last_seen;
    let got = got.expect("last_seen is set");
    // Postgres keeps microseconds.
    let off = got
        .duration_since(seen)
        .unwrap_or_else(|e| e.duration())
        .as_millis();
    assert!(off < 5, "last_seen is the time given ({off} ms off)");
    store.touch_seen("nope", seen).await.unwrap();
    // An older time arriving late (writes made at once land in any order)
    // does not move "last seen" back; a newer one does.
    store
        .touch_seen(&d1.device_id, seen - Duration::from_secs(600))
        .await
        .unwrap();
    let after_older = store
        .device(&d1.device_id)
        .await
        .unwrap()
        .unwrap()
        .last_seen
        .expect("still set");
    assert_eq!(after_older, got, "an older time moved last_seen back");
    let newer = seen + Duration::from_secs(30);
    store.touch_seen(&d1.device_id, newer).await.unwrap();
    let after_newer = store
        .device(&d1.device_id)
        .await
        .unwrap()
        .unwrap()
        .last_seen
        .unwrap();
    let off = after_newer
        .duration_since(newer)
        .unwrap_or_else(|e| e.duration())
        .as_millis();
    assert!(off < 5, "a newer time is taken ({off} ms off)");

    // --- revoke: only by the owner, and then invisible
    assert_eq!(store.revoke(&d2.device_id, &bob).await, Ok(false));
    assert_eq!(
        store
            .device(&d2.device_id)
            .await
            .unwrap()
            .map(|d| d.revoked),
        Some(false)
    );
    assert_eq!(
        store.revoked_device(&d2.device_id).await,
        Ok(None),
        "a registered device is not a revoked one"
    );
    assert_eq!(store.revoked_device("nope").await, Ok(None));
    assert_eq!(store.revoke(&d2.device_id, &alice).await, Ok(true));
    assert_eq!(store.device(&d2.device_id).await, Ok(None));
    let gone = store.revoked_device(&d2.device_id).await.unwrap().unwrap();
    assert_eq!(
        (gone.owner_sub.as_str(), gone.revoked),
        (alice.as_str(), true),
        "a revoked device can still be looked up, as revoked"
    );
    assert_eq!(
        store.devices_of(&alice).await.unwrap().len(),
        1,
        "a revoked device is not listed"
    );
    assert_eq!(
        store.revoke(&d2.device_id, &alice).await,
        Ok(false),
        "already revoked"
    );
    assert_eq!(
        store.insert_device(&d2).await,
        Err(StoreError::DuplicateId),
        "a revoked device keeps its id"
    );
    assert_eq!(store.rename(&d2.device_id, &alice, "x").await, Ok(false));
    assert_eq!(
        store.replace_key(&d2.device_id, &alice, [3; 32]).await,
        Ok(false)
    );

    // --- the sixth device: refused, and a revoked one does not count
    for i in 0..(MAX_DEVICES_PER_USER - 1) {
        store
            .insert_device(&new_device(&alice, &format!("extra {i}"), 4))
            .await
            .unwrap();
    }
    assert_eq!(
        store.devices_of(&alice).await.unwrap().len(),
        MAX_DEVICES_PER_USER
    );
    assert_eq!(
        store
            .insert_device(&new_device(&alice, "one too many", 5))
            .await,
        Err(StoreError::TooManyDevices)
    );
    // Someone else is not held to Alice's count.
    store
        .insert_device(&new_device(&bob, "Bob's Mac", 6))
        .await
        .unwrap();
    assert_eq!(store.revoke(&d1.device_id, &alice).await, Ok(true));
    store
        .insert_device(&new_device(&alice, "after a revoke", 5))
        .await
        .unwrap();

    // --- activity: newest first, limit, per device, per owner
    let dev_a = d1.device_id.as_str();
    let dev_b = d2.device_id.as_str();
    for (dev, tool, secs) in [
        (dev_a, "t1", 1000),
        (dev_b, "t2", 3000),
        (dev_a, "t3", 2000),
    ] {
        store
            .record_activity(&activity(&alice, dev, tool, secs))
            .await
            .unwrap();
    }
    store
        .record_activity(&activity(&bob, "bobs", "secret-free", 2500))
        .await
        .unwrap();
    let tools = |rows: &[ActivityRow]| rows.iter().map(|r| r.tool.clone()).collect::<Vec<_>>();
    assert_eq!(
        tools(&store.activity_of(&alice, None, 10).await.unwrap()),
        ["t2", "t3", "t1"]
    );
    assert_eq!(
        tools(&store.activity_of(&alice, None, 2).await.unwrap()),
        ["t2", "t3"],
        "limit"
    );
    assert_eq!(
        tools(&store.activity_of(&alice, Some(dev_a), 10).await.unwrap()),
        ["t3", "t1"],
        "one device"
    );
    assert_eq!(store.activity_of(&alice, None, 0).await, Ok(vec![]));
    assert_eq!(
        tools(&store.activity_of(&bob, None, 10).await.unwrap()),
        ["secret-free"],
        "nobody sees another person's calls"
    );
    let first = &store.activity_of(&alice, None, 1).await.unwrap()[0];
    assert_eq!(
        (
            first.arg_bytes,
            first.result_bytes,
            first.duration_ms,
            first.outcome.as_str()
        ),
        (Some(10), Some(20), Some(30), "ok")
    );
    assert_eq!(first.at, UNIX_EPOCH + Duration::from_secs(3000));
    // Sizes may be unknown.
    let mut unknown = activity(&alice, dev_a, "t4", 4000);
    unknown.arg_bytes = None;
    unknown.result_bytes = None;
    unknown.duration_ms = None;
    unknown.outcome = "store_unavailable".into();
    store.record_activity(&unknown).await.unwrap();
    assert_eq!(store.activity_of(&alice, None, 1).await, Ok(vec![unknown]));

    // --- purge: takes what is older than the time given, says how many
    let purged = store
        .purge_activity_before(UNIX_EPOCH + Duration::from_secs(2500))
        .await
        .unwrap();
    assert_eq!(purged, 2, "t1 (1000) and t3 (2000)");
    assert_eq!(
        tools(&store.activity_of(&alice, None, 10).await.unwrap()),
        ["t4", "t2"]
    );
    assert_eq!(
        store
            .purge_activity_before(UNIX_EPOCH + Duration::from_secs(2500))
            .await,
        Ok(0)
    );
}
