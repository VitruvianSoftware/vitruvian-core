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

//! One person can never reach another's computer or request (spec 7.4).
//!
//! Alice and Bob each have two computers, and both call one of theirs
//! "MacBook Pro". Every case asks the question as Alice and compares her
//! answer about something of Bob's with her answer about something that does
//! not exist: the same status, the same headers (the clock aside) and the same
//! bytes, so nothing she can ask tells her whether the thing is Bob's. Then it
//! checks Bob's side is as it was.
//!
//! Run in CI two ways. `:vitruvian_relay_isolation_test` must pass. The
//! `:vitruvian_relay_isolation_canary_test` builds the same tests against a
//! relay with its ownership check deliberately broken
//! (`--cfg relay_broken_ownership`, in `App::owned_device`) and must see this
//! file fail: a check that cannot fail proves nothing.
//!
//! The tests live in `mod isolation` so a failure is named `isolation::...`,
//! which is what `expect_failure.sh` looks for.

mod pg_support;
mod relay_support;

mod isolation {
    use std::sync::Arc;
    use std::time::Duration;

    use ring::signature::{Ed25519KeyPair, KeyPair};
    use serde_json::{json, Value};
    use vitruvian_relay::dashboard::form_encode;
    use vitruvian_relay::http::Timing;
    use vitruvian_relay::store::{ActivityRow, PgStore, Store};
    use vitruvian_relay_protocol::ToConnector;

    use crate::pg_support::{fresh_database, Database};
    use crate::relay_support::{
        b64, b64url, call_body, ed25519, hello, initialize_body, post, send, start_relay_with,
        tool, FakeDevice, Relay, Reply, ALICE, BOB, ISSUER, PUBLIC_URL, WAIT,
    };

    /// What a connector is told about a computer that is not its person's.
    const NOT_REGISTERED: &str = "not registered with your account";
    /// What an AI app is told about a request that is not its person's.
    const UNKNOWN_REQUEST: &str =
        "That request has finished or expired. Send the original request again.";

    // ------------------------------------------------------------ the world

    struct Device {
        id: String,
        key: Ed25519KeyPair,
    }

    struct Person {
        /// Both people call their first computer this.
        laptop: Device,
        other: Device,
    }

    struct World {
        relay: Arc<Relay>,
        /// A second way into the database, to look at what the relay stored.
        store: PgStore,
        _db: Database,
        alice: Person,
        bob: Person,
    }

    const SHARED_NAME: &str = "MacBook Pro";

    async fn world() -> World {
        world_with(Timing::default()).await
    }

    /// Timing for the tests that wait for an approval: the 10 s, 120 s and
    /// 300 s of production, a few hundred milliseconds or seconds here.
    fn approval_timing() -> Timing {
        Timing {
            approval_reply: Duration::from_millis(300),
            rejoin_window: Duration::from_secs(30),
            parked_result: Duration::from_secs(30),
            ..Timing::default()
        }
    }

    async fn person(relay: &Relay, sub: &'static str, other_name: &str) -> Person {
        let (laptop_key, other_key) = (ed25519(), ed25519());
        let laptop = relay.register(sub, &laptop_key, SHARED_NAME).await;
        let other = relay.register(sub, &other_key, other_name).await;
        Person {
            laptop: Device {
                id: laptop,
                key: laptop_key,
            },
            other: Device {
                id: other,
                key: other_key,
            },
        }
    }

    async fn world_with(timing: Timing) -> World {
        let db = fresh_database().await;
        let relay = Arc::new(start_relay_with(&db.url(), timing).await);
        let store = PgStore::connect(&db.url(), None, Arc::new(|_| {}))
            .await
            .expect("a store on the same database");
        let alice = person(&relay, ALICE, "Mac mini").await;
        let bob = person(&relay, BOB, "Studio").await;
        World {
            relay,
            store,
            _db: db,
            alice,
            bob,
        }
    }

    /// An id that is well formed and is nobody's.
    fn nobody() -> String {
        vitruvian_relay::uuid_v4()
    }

    /// What an answer is, minus the clock: status, headers and body, with each
    /// id in `ids` written as the name beside it (an answer about a computer
    /// repeats its id in a link; two ids must not make two answers differ).
    /// Because ids become `<id>`, a difference only in the id itself cannot
    /// show here; fine for UUIDs, which carry nothing.
    fn shape(r: &Reply, ids: &[(&str, &str)]) -> (u16, Vec<(String, String)>, String) {
        let name = |s: &str| {
            ids.iter()
                .fold(s.to_string(), |s, (id, name)| s.replace(id, name))
        };
        let mut headers: Vec<(String, String)> = r
            .headers
            .iter()
            .filter(|(k, _)| k.as_str() != "date")
            .map(|(k, v)| (k.to_string(), name(v.to_str().unwrap())))
            .collect();
        headers.sort();
        (r.status, headers, name(&r.body))
    }

    /// Alice's answer about `theirs` is her answer about an id that never
    /// was, and was a refusal.
    fn assert_same_as_missing(what: &str, theirs: &Reply, mine: &str, nothing: &Reply, no: &str) {
        assert_eq!(
            shape(theirs, &[(mine, "<id>")]),
            shape(nothing, &[(no, "<id>")]),
            "{what}: Alice's answer about Bob's differs from her answer about a computer \
             that does not exist"
        );
        assert_eq!(
            theirs.status, 404,
            "{what}: expected a refusal, got {}: {}",
            theirs.status, theirs.body
        );
    }

    /// An AI app's request in the 2026-07-28 style: one request on its own,
    /// no session.
    async fn modern_rpc(relay: &Relay, sub: &str, device: &str, mut body: Value) -> Reply {
        body["params"]["_meta"] = json!({
            "io.modelcontextprotocol/protocolVersion": "2026-07-28",
            "io.modelcontextprotocol/clientCapabilities": {},
            "io.modelcontextprotocol/clientInfo": {"name": "itest", "version": "0"},
        });
        send(
            relay.addr,
            "POST",
            &format!("/mcp/d/{device}"),
            &[
                ("authorization", format!("Bearer {}", relay.mcp_token(sub))),
                ("accept", "application/json, text/event-stream".to_string()),
                ("content-type", "application/json".to_string()),
                ("mcp-protocol-version", "2026-07-28".to_string()),
            ],
            &body.to_string(),
        )
        .await
    }

    /// What the dashboard has for a signed-in person.
    struct Browser {
        cookie: String,
        csrf: String,
    }

    fn set_cookie_pair(r: &Reply, name: &str) -> Option<String> {
        r.headers
            .get_all("set-cookie")
            .iter()
            .filter_map(|v| v.to_str().ok())
            .find(|c| c.starts_with(&format!("{name}=")))
            .map(|c| c.split(';').next().unwrap().to_string())
    }

    /// Signs in the way a browser does: `/auth/login`, then the callback with
    /// the state it was given and the cookie it set, the identity service
    /// (a stand-in) handing back `sub`'s token.
    async fn sign_in(relay: &Relay, sub: &str) -> Browser {
        let get = |path: String, cookie: Option<String>| {
            let headers: Vec<(&str, String)> = cookie.into_iter().map(|c| ("cookie", c)).collect();
            async move { send(relay.addr, "GET", &path, &headers, "").await }
        };
        let login = get("/auth/login".into(), None).await;
        assert_eq!(login.status, 303, "{}", login.body);
        let location = login.header("location").unwrap();
        let state = location
            .split_once('?')
            .and_then(|(_, q)| q.split('&').find_map(|p| p.strip_prefix("state=")))
            .expect("a state")
            .to_string();
        let auth = set_cookie_pair(&login, "vr_auth").expect("the sign-in is remembered");
        relay.tokens.give_token(&relay.dashboard_token(sub));
        let back = get(
            format!("/auth/callback?code=the-code&state={state}"),
            Some(auth),
        )
        .await;
        assert_eq!(back.status, 303, "{}", back.body);
        let cookie = set_cookie_pair(&back, "vr_session").expect("signed in");
        let page = get("/devices".into(), Some(cookie.clone())).await;
        assert_eq!(page.status, 200, "{}", page.body);
        let csrf = page
            .body
            .split("name=\"csrf\" value=\"")
            .nth(1)
            .and_then(|a| a.split('"').next())
            .expect("a form with a CSRF token")
            .to_string();
        Browser { cookie, csrf }
    }

    impl Browser {
        async fn get(&self, relay: &Relay, path: &str) -> Reply {
            send(
                relay.addr,
                "GET",
                path,
                &[("cookie", self.cookie.clone())],
                "",
            )
            .await
        }

        /// A form post as a page sends it.
        async fn post(&self, relay: &Relay, path: &str, fields: &[(&str, &str)]) -> Reply {
            let mut body: Vec<String> = fields
                .iter()
                .map(|(k, v)| format!("{}={}", form_encode(k), form_encode(v)))
                .collect();
            body.push(format!("csrf={}", form_encode(&self.csrf)));
            send(
                relay.addr,
                "POST",
                path,
                &[
                    ("cookie", self.cookie.clone()),
                    (
                        "content-type",
                        "application/x-www-form-urlencoded".to_string(),
                    ),
                    ("origin", PUBLIC_URL.to_string()),
                ],
                &body.join("&"),
            )
            .await
        }
    }

    fn text_of(r: &Reply) -> String {
        r.json()["result"]["content"][0]["text"]
            .as_str()
            .unwrap_or_else(|| panic!("no text: {}", r.body))
            .to_string()
    }

    /// The request id in a "waiting for you" reply.
    fn waiting_id(r: &Reply) -> String {
        let text = text_of(r);
        assert!(text.starts_with("Waiting for you to allow this"), "{text}");
        text.split("request_id \"")
            .nth(1)
            .and_then(|t| t.split('"').next())
            .unwrap_or_else(|| panic!("no request id in {text}"))
            .to_string()
    }

    fn check_body(rpc_id: u64, request_id: &str) -> Value {
        call_body(rpc_id, "check_request", json!({"request_id": request_id}))
    }

    /// A call is recorded just after its answer goes out.
    async fn activity_rows(store: &PgStore, sub: &str, at_least: usize) -> Vec<ActivityRow> {
        tokio::time::timeout(WAIT, async {
            loop {
                let rows = store.activity_of(sub, None, 50).await.unwrap();
                if rows.len() >= at_least {
                    return rows;
                }
                tokio::time::sleep(Duration::from_millis(20)).await;
            }
        })
        .await
        .expect("the calls were recorded")
    }

    /// Bob's computer is as he left it: still his, still named, still with his
    /// key, and his connector can still connect with that key.
    async fn assert_bobs_laptop_untouched(w: &World) {
        let rec = w
            .store
            .device(&w.bob.laptop.id)
            .await
            .unwrap()
            .expect("Bob's computer is still there, and not removed");
        assert_eq!(rec.owner_sub, BOB);
        assert_eq!(rec.name, SHARED_NAME);
        assert_eq!(
            rec.public_key_ed25519.as_slice(),
            w.bob.laptop.key.public_key().as_ref(),
            "Bob's key was replaced"
        );
        let token = w.relay.connector_token(BOB);
        let hello = hello(&w.bob.laptop.id, &w.bob.laptop.key, &token, vec![]);
        match w.relay.say_hello(&token, hello).await {
            Some(ToConnector::Welcome { device_id }) => assert_eq!(device_id, w.bob.laptop.id),
            other => panic!("Bob's computer can no longer connect: {other:?}"),
        }
    }

    // ------------------------------------------------------------- the tests

    #[tokio::test(flavor = "multi_thread")]
    async fn mcp_initialize_tools_list_and_call_on_bobs_device() {
        let w = world().await;
        let mut bobs_computer = w
            .relay
            .connect(
                BOB,
                &w.bob.laptop.id,
                &w.bob.laptop.key,
                vec![tool("read_file")],
            )
            .await;
        let alices_session = w.relay.session(ALICE, &w.alice.laptop.id).await;

        // The owners get in, so the refusals below mean something.
        let own = w.relay.session(BOB, &w.bob.laptop.id).await;
        assert!(!own.is_empty());
        let r = modern_rpc(
            &w.relay,
            ALICE,
            &w.alice.laptop.id,
            json!({"jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": {}}),
        )
        .await;
        assert_eq!(r.status, 200, "{}", r.body);

        for theirs in [&w.bob.laptop.id, &w.bob.other.id] {
            let nowhere = nobody();
            let session = Some(alices_session.as_str());
            let list = json!({"jsonrpc": "2.0", "id": 1, "method": "tools/list"});
            let call = call_body(2, "read_file", json!({"path": "/bob/secret"}));
            let modern_list =
                json!({"jsonrpc": "2.0", "id": 3, "method": "tools/list", "params": {}});
            let modern_call = call_body(4, "read_file", json!({"path": "/bob/secret"}));
            for (what, session, body) in [
                ("initialize", None, initialize_body()),
                ("tools/list", session, list),
                ("tools/call", session, call),
            ] {
                let a = w.relay.rpc(ALICE, theirs, session, body.clone()).await;
                let b = w.relay.rpc(ALICE, &nowhere, session, body).await;
                assert_same_as_missing(what, &a, theirs, &b, &nowhere);
            }
            for (what, body) in [
                ("modern tools/list", modern_list),
                ("modern tools/call", modern_call),
            ] {
                let a = modern_rpc(&w.relay, ALICE, theirs, body.clone()).await;
                let b = modern_rpc(&w.relay, ALICE, &nowhere, body).await;
                assert_same_as_missing(what, &a, theirs, &b, &nowhere);
            }
        }
        // None of it reached Bob's computer.
        assert!(
            bobs_computer.gets_no_call(Duration::from_millis(300)).await,
            "a call from Alice reached Bob's computer"
        );
    }

    #[tokio::test(flavor = "multi_thread")]
    async fn protected_resource_metadata_for_bobs_device() {
        let w = world().await;
        let theirs = &w.bob.laptop.id;
        let nowhere = nobody();
        // Public: the same for a computer that exists, one that does not, and
        // whether or not a token comes with it.
        let ask = |id: String, token: Option<String>| {
            let relay = w.relay.clone();
            async move {
                let headers: Vec<(&str, String)> = token
                    .into_iter()
                    .map(|t| ("authorization", format!("Bearer {t}")))
                    .collect();
                send(
                    relay.addr,
                    "GET",
                    &format!("/.well-known/oauth-protected-resource/mcp/d/{id}"),
                    &headers,
                    "",
                )
                .await
            }
        };
        let alices_token = w.relay.mcp_token(ALICE);
        let a = ask(theirs.clone(), Some(alices_token.clone())).await;
        let b = ask(nowhere.clone(), Some(alices_token)).await;
        let c = ask(theirs.clone(), None).await;
        assert_eq!(a.status, 200, "{}", a.body);
        assert_eq!(
            shape(&a, &[(theirs, "<id>")]),
            shape(&b, &[(&nowhere, "<id>")])
        );
        assert_eq!(
            shape(&a, &[(theirs, "<id>")]),
            shape(&c, &[(theirs, "<id>")])
        );
        assert!(a.body.contains(theirs.as_str()), "it names the endpoint");

        // And with no token at all the endpoint asks for one the same way,
        // whether the computer exists or not.
        let body = initialize_body().to_string();
        let plain = |id: &str| {
            let relay = w.relay.clone();
            let (path, body) = (format!("/mcp/d/{id}"), body.clone());
            async move {
                send(
                    relay.addr,
                    "POST",
                    &path,
                    &[
                        ("content-type", "application/json".to_string()),
                        ("accept", "application/json, text/event-stream".to_string()),
                    ],
                    &body,
                )
                .await
            }
        };
        let (a, b) = (plain(theirs).await, plain(&nowhere).await);
        assert_eq!(a.status, 401, "{}", a.body);
        assert_eq!(
            shape(&a, &[(theirs, "<id>")]),
            shape(&b, &[(&nowhere, "<id>")])
        );
    }

    #[tokio::test(flavor = "multi_thread")]
    async fn hello_with_bobs_device_id() {
        let w = world().await;
        let token = w.relay.connector_token(ALICE);
        let alices_key = &w.alice.laptop.key;

        // The control: Alice's own computer, her own key, gets in.
        let own = hello(&w.alice.laptop.id, alices_key, &token, vec![]);
        match w.relay.say_hello(&token, own).await {
            Some(ToConnector::Welcome { .. }) => {}
            other => panic!("Alice's own computer was refused: {other:?}"),
        }

        // What a computer that does not exist is told.
        let said = w
            .relay
            .say_hello(&token, hello(&nobody(), alices_key, &token, vec![]))
            .await;
        let Some(ToConnector::Reject { reason }) = &said else {
            panic!("expected a reject, got {said:?}");
        };
        assert!(reason.contains(NOT_REGISTERED), "{reason}");

        // Bob's computer is told the same, whatever key signs for it: Alice's,
        // or Bob's own (a copy of it in her hands, signing for her token).
        let removed = &w.bob.other;
        assert!(w.relay.app.revoke(BOB, &removed.id).await.unwrap());
        for (what, id, key) in [
            ("Bob's id, Alice's key", &w.bob.laptop.id, alices_key),
            ("Bob's id, Bob's key", &w.bob.laptop.id, &w.bob.laptop.key),
            ("Bob's removed id, Bob's key", &removed.id, &removed.key),
        ] {
            let got = w
                .relay
                .say_hello(&token, hello(id, key, &token, vec![]))
                .await;
            assert_eq!(got, said, "{what}");
        }

        // Bob, for his own removed computer, is told it was removed: the
        // difference is who is asking, not whether the computer is real.
        let bobs_token = w.relay.connector_token(BOB);
        let got = w
            .relay
            .say_hello(
                &bobs_token,
                hello(&removed.id, &removed.key, &bobs_token, vec![]),
            )
            .await;
        match got {
            Some(ToConnector::Reject { reason }) => {
                assert!(reason.contains("was removed from your account"), "{reason}")
            }
            other => panic!("expected the removed answer, got {other:?}"),
        }
        assert_bobs_laptop_untouched(&w).await;
    }

    #[tokio::test(flavor = "multi_thread")]
    async fn register_with_bobs_device_id() {
        let w = world().await;
        let theirs = w.bob.laptop.id.clone();
        let nowhere = nobody();

        // Alice, signing in "again" on what she says is computer `id`, with a
        // new key and a new name she asks to be used.
        let register = |id: String| {
            let relay = w.relay.clone();
            async move {
                relay
                    .register_body(
                        ALICE,
                        json!({"public_key": b64(ed25519().public_key().as_ref()),
                               "name": "Hijacked", "rename": true, "device_id": id}),
                    )
                    .await
            }
        };
        let a = register(theirs.clone()).await;
        let b = register(nowhere.clone()).await;
        assert_eq!(a.status, 200, "{}", a.body);
        // Either way she is registering a new computer of her own: a new id
        // that is neither Bob's nor the one she named.
        let (new_a, new_b) = (
            a.json()["device_id"].as_str().unwrap().to_string(),
            b.json()["device_id"].as_str().unwrap().to_string(),
        );
        for (id, named) in [(&new_a, &theirs), (&new_b, &nowhere)] {
            assert_ne!(id, named);
            assert_ne!(id, &w.bob.other.id);
        }
        assert_eq!(
            shape(&a, &[(&new_a, "<new>"), (&theirs, "<named>")]),
            shape(&b, &[(&new_b, "<new>"), (&nowhere, "<named>")])
        );
        // Bob's computer is as it was, and the two new ones are Alice's.
        assert_bobs_laptop_untouched(&w).await;
        let alices = w.store.devices_of(ALICE).await.unwrap();
        assert_eq!(alices.len(), 4, "{alices:?}");
        for id in [&new_a, &new_b] {
            let rec = alices.iter().find(|d| &d.device_id == id).unwrap();
            assert_eq!(
                (rec.owner_sub.as_str(), rec.name.as_str()),
                (ALICE, "Hijacked")
            );
        }
        assert_eq!(w.store.devices_of(BOB).await.unwrap().len(), 2);
    }

    #[tokio::test(flavor = "multi_thread")]
    async fn dashboard_device_page_rename_remove_for_bobs_device() {
        let w = world().await;
        let alice = sign_in(&w.relay, ALICE).await;

        // The control: her own computer's page opens.
        let own = alice
            .get(&w.relay, &format!("/devices/{}", w.alice.laptop.id))
            .await;
        assert_eq!(own.status, 200, "{}", own.body);
        assert!(own.body.contains(SHARED_NAME));

        for theirs in [&w.bob.laptop.id, &w.bob.other.id] {
            let nowhere = nobody();
            for (what, method, path, fields) in [
                ("the page", "GET", "", vec![]),
                ("rename", "POST", "/rename", vec![("name", "Hijacked")]),
                ("remove", "POST", "/remove", vec![]),
            ] {
                let go = |id: &str| {
                    let (relay, alice, path, fields) = (
                        w.relay.clone(),
                        &alice,
                        format!("/devices/{id}{path}"),
                        fields.clone(),
                    );
                    async move {
                        match method {
                            "GET" => alice.get(&relay, &path).await,
                            _ => alice.post(&relay, &path, &fields).await,
                        }
                    }
                };
                let (a, b) = (go(theirs).await, go(&nowhere).await);
                assert_same_as_missing(what, &a, theirs, &b, &nowhere);
            }
            // Asking for another's computer's activity is the same.
            let a = alice
                .get(&w.relay, &format!("/activity?device={theirs}"))
                .await;
            let b = alice
                .get(&w.relay, &format!("/activity?device={nowhere}"))
                .await;
            assert_same_as_missing("activity of the computer", &a, theirs, &b, &nowhere);
        }
        assert_bobs_laptop_untouched(&w).await;
        let other = w.store.device(&w.bob.other.id).await.unwrap().unwrap();
        assert_eq!(
            (other.owner_sub.as_str(), other.name.as_str()),
            (BOB, "Studio")
        );
    }

    #[tokio::test(flavor = "multi_thread")]
    async fn activity_lists_only_own_rows() {
        let w = world().await;
        let (alice_session, bob_session, bob_other_session) = (
            w.relay.session(ALICE, &w.alice.laptop.id).await,
            w.relay.session(BOB, &w.bob.laptop.id).await,
            w.relay.session(BOB, &w.bob.other.id).await,
        );
        // No computer is connected, so each call is answered "offline", and
        // each is recorded against its person.
        let r = w
            .relay
            .rpc(
                ALICE,
                &w.alice.laptop.id,
                Some(&alice_session),
                call_body(1, "alice_tool", json!({})),
            )
            .await;
        assert_eq!(r.status, 200, "{}", r.body);
        for (device, session) in [
            (&w.bob.laptop.id, &bob_session),
            (&w.bob.other.id, &bob_other_session),
        ] {
            let r = w
                .relay
                .rpc(
                    BOB,
                    device,
                    Some(session),
                    call_body(1, "bob_tool", json!({})),
                )
                .await;
            assert_eq!(r.status, 200, "{}", r.body);
        }
        activity_rows(&w.store, ALICE, 1).await;
        activity_rows(&w.store, BOB, 2).await;

        let alice = sign_in(&w.relay, ALICE).await;
        let page = alice.get(&w.relay, "/activity").await;
        assert_eq!(page.status, 200, "{}", page.body);
        assert!(page.body.contains("alice_tool"), "{}", page.body);
        for bobs in [
            "bob_tool",
            "Studio",
            w.bob.laptop.id.as_str(),
            w.bob.other.id.as_str(),
            "bob",
        ] {
            assert!(!page.body.contains(bobs), "Alice's page shows {bobs:?}");
        }
        // Her own computer's filter lists her row; her list of computers is
        // hers.
        let mine = alice
            .get(&w.relay, &format!("/activity?device={}", w.alice.laptop.id))
            .await;
        assert!(mine.body.contains("alice_tool"), "{}", mine.body);
        let devices = alice.get(&w.relay, "/devices").await;
        assert!(devices.body.contains(&w.alice.other.id));
        assert!(!devices.body.contains("Studio"));
        assert!(!devices.body.contains(&w.bob.laptop.id));

        // And the same from the other side: Bob sees his two and none of hers.
        let bob = sign_in(&w.relay, BOB).await;
        let page = bob.get(&w.relay, "/activity").await;
        assert_eq!(page.body.matches("bob_tool").count(), 2, "{}", page.body);
        assert!(!page.body.contains("alice_tool"));
        assert!(!page.body.contains(&w.alice.laptop.id));
        // The store agrees: every row it holds for a person is that person's.
        for (sub, n) in [(ALICE, 1), (BOB, 2)] {
            let rows = w.store.activity_of(sub, None, 50).await.unwrap();
            assert_eq!(rows.len(), n, "{rows:?}");
            assert!(rows.iter().all(|r| r.owner_sub == sub), "{rows:?}");
        }
    }

    /// Bob's call is waiting for him to allow it on his Mac. His computer
    /// (which answers when told to), the call it was sent, the request id Bob
    /// was given, and Bob's session.
    async fn bobs_request_waiting(
        w: &World,
    ) -> (FakeDevice, vitruvian_relay_protocol::Call, String, String) {
        let mut bobs_computer = w
            .relay
            .connect(
                BOB,
                &w.bob.laptop.id,
                &w.bob.laptop.key,
                vec![tool("start_process")],
            )
            .await;
        let bob_session = w.relay.session(BOB, &w.bob.laptop.id).await;
        let relay = w.relay.clone();
        let (bob_id, sess) = (w.bob.laptop.id.clone(), bob_session.clone());
        let first = tokio::spawn(async move {
            relay
                .rpc(
                    BOB,
                    &bob_id,
                    Some(&sess),
                    call_body(1, "start_process", json!({"command": "ls"})),
                )
                .await
        });
        let call = bobs_computer.next_call().await;
        bobs_computer.pending(&call.call_id);
        let id = waiting_id(&first.await.unwrap());
        (bobs_computer, call, id, bob_session)
    }

    /// Bob finishes it, and still gets his result: nothing Alice tried took it.
    async fn assert_bob_still_gets_his_result(
        w: &World,
        computer: &FakeDevice,
        call: &vitruvian_relay_protocol::Call,
        id: &str,
        bob_session: &str,
    ) {
        computer.reply(&call.call_id, "bob's listing");
        let r = w
            .relay
            .rpc(BOB, &w.bob.laptop.id, Some(bob_session), check_body(9, id))
            .await;
        assert_eq!(text_of(&r), "bob's listing");
    }

    /// Alice asks for Bob's request by id on HER OWN computer's endpoint: the
    /// request ownership check (`Mcp::owned_request`) alone decides this.
    #[tokio::test(flavor = "multi_thread")]
    async fn check_request_with_bobs_request_id() {
        let w = world_with(approval_timing()).await;
        let (bobs_computer, call, id, bob_session) = bobs_request_waiting(&w).await;
        let alice_session = w.relay.session(ALICE, &w.alice.laptop.id).await;

        let ask = |request_id: &str, n: u64| {
            w.relay.rpc(
                ALICE,
                &w.alice.laptop.id,
                Some(&alice_session),
                check_body(n, request_id),
            )
        };
        let theirs = ask(&id, 2).await;
        let nothing = ask("r_0123456789abcdef", 2).await;
        assert_eq!(text_of(&theirs), UNKNOWN_REQUEST);
        assert_eq!(shape(&theirs, &[]), shape(&nothing, &[]));
        // Twice, and the same: asking does not change what she is told.
        let again = ask(&id, 3).await;
        assert_eq!(text_of(&again), UNKNOWN_REQUEST);

        assert_bob_still_gets_his_result(&w, &bobs_computer, &call, &id, &bob_session).await;
    }

    /// Alice asks on Bob's computer's endpoint, where his request lives: she
    /// is refused like for any computer that is not hers (the device ownership
    /// check, `App::owned_device`).
    #[tokio::test(flavor = "multi_thread")]
    async fn check_request_on_bobs_device_endpoint() {
        let w = world_with(approval_timing()).await;
        let (bobs_computer, call, id, bob_session) = bobs_request_waiting(&w).await;
        let alice_session = w.relay.session(ALICE, &w.alice.laptop.id).await;

        let nowhere = nobody();
        let a = w
            .relay
            .rpc(
                ALICE,
                &w.bob.laptop.id,
                Some(&alice_session),
                check_body(3, &id),
            )
            .await;
        let b = w
            .relay
            .rpc(ALICE, &nowhere, Some(&alice_session), check_body(3, &id))
            .await;
        assert_same_as_missing(
            "check_request on Bob's endpoint",
            &a,
            &w.bob.laptop.id,
            &b,
            &nowhere,
        );

        assert_bob_still_gets_his_result(&w, &bobs_computer, &call, &id, &bob_session).await;
    }

    #[tokio::test(flavor = "multi_thread")]
    async fn rejoin_never_crosses_people() {
        let w = world_with(approval_timing()).await;
        let tools = || vec![tool("start_process")];
        let mut alices_computer = w
            .relay
            .connect(ALICE, &w.alice.laptop.id, &w.alice.laptop.key, tools())
            .await;
        let mut bobs_computer = w
            .relay
            .connect(BOB, &w.bob.laptop.id, &w.bob.laptop.key, tools())
            .await;
        let (alice_session, bob_session) = (
            w.relay.session(ALICE, &w.alice.laptop.id).await,
            w.relay.session(BOB, &w.bob.laptop.id).await,
        );

        // The very same tool and arguments from both people.
        let run = |sub: &'static str, device: &str, session: &str, n: u64| {
            let (relay, device, session) =
                (w.relay.clone(), device.to_string(), session.to_string());
            tokio::spawn(async move {
                relay
                    .rpc(
                        sub,
                        &device,
                        Some(&session),
                        call_body(n, "start_process", json!({"command": "ls", "args": ["-l"]})),
                    )
                    .await
            })
        };
        let first_alice = run(ALICE, &w.alice.laptop.id, &alice_session, 1);
        let alices_call = alices_computer.next_call().await;
        alices_computer.pending(&alices_call.call_id);
        let alices_id = waiting_id(&first_alice.await.unwrap());

        // Bob's identical call is his own: it reaches his computer.
        let first_bob = run(BOB, &w.bob.laptop.id, &bob_session, 1);
        let bobs_call = bobs_computer.next_call().await;
        bobs_computer.pending(&bobs_call.call_id);
        let bobs_id = waiting_id(&first_bob.await.unwrap());
        assert_ne!(alices_id, bobs_id, "two people got one request");
        assert_ne!(alices_call.call_id, bobs_call.call_id);

        // Run twice: each person's identical retry rejoins their own, and
        // neither computer is asked again.
        let again_alice = run(ALICE, &w.alice.laptop.id, &alice_session, 2);
        let again_bob = run(BOB, &w.bob.laptop.id, &bob_session, 2);
        assert_eq!(waiting_id(&again_alice.await.unwrap()), alices_id);
        assert_eq!(waiting_id(&again_bob.await.unwrap()), bobs_id);
        assert!(
            alices_computer
                .gets_no_call(Duration::from_millis(300))
                .await
        );
        assert!(bobs_computer.gets_no_call(Duration::from_millis(300)).await);

        // Each is answered by their own computer's result.
        alices_computer.reply(&alices_call.call_id, "alice's listing");
        bobs_computer.reply(&bobs_call.call_id, "bob's listing");
        let a = w
            .relay
            .rpc(
                ALICE,
                &w.alice.laptop.id,
                Some(&alice_session),
                check_body(3, &alices_id),
            )
            .await;
        let b = w
            .relay
            .rpc(
                BOB,
                &w.bob.laptop.id,
                Some(&bob_session),
                check_body(3, &bobs_id),
            )
            .await;
        assert_eq!(text_of(&a), "alice's listing");
        assert_eq!(text_of(&b), "bob's listing");
    }

    #[tokio::test(flavor = "multi_thread")]
    async fn same_names_stay_separate() {
        let w = world().await;
        let (alice, bob) = (sign_in(&w.relay, ALICE).await, sign_in(&w.relay, BOB).await);
        let listed = |page: &Reply, id: &str| page.body.contains(&format!("/devices/{id}"));

        // Two people, one name: each list has only that person's computers.
        let (a, b) = (
            alice.get(&w.relay, "/devices").await,
            bob.get(&w.relay, "/devices").await,
        );
        for page in [&a, &b] {
            assert!(page.body.contains(SHARED_NAME), "{}", page.body);
        }
        assert!(listed(&a, &w.alice.laptop.id) && listed(&a, &w.alice.other.id));
        assert!(!listed(&a, &w.bob.laptop.id) && !listed(&a, &w.bob.other.id));
        assert!(listed(&b, &w.bob.laptop.id) && listed(&b, &w.bob.other.id));
        assert!(!listed(&b, &w.alice.laptop.id) && !listed(&b, &w.alice.other.id));

        // Each is told about their own "MacBook Pro", never the other's.
        let offline = format!("Your computer \"{SHARED_NAME}\" is offline");
        for (sub, device) in [(ALICE, &w.alice.laptop.id), (BOB, &w.bob.laptop.id)] {
            let session = w.relay.session(sub, device).await;
            let r = w
                .relay
                .rpc(
                    sub,
                    device,
                    Some(&session),
                    call_body(1, "read_file", json!({})),
                )
                .await;
            assert!(text_of(&r).starts_with(&offline), "{}", r.body);
        }

        // Alice renames hers; Bob's keeps its name. A new name is not a new
        // person's computer.
        let r = alice
            .post(
                &w.relay,
                &format!("/devices/{}/rename", w.alice.laptop.id),
                &[("name", "Work Mac")],
            )
            .await;
        assert_eq!(r.status, 303, "{}", r.body);
        let mine = w.store.device(&w.alice.laptop.id).await.unwrap().unwrap();
        assert_eq!(mine.name, "Work Mac");
        let bobs = w.store.device(&w.bob.laptop.id).await.unwrap().unwrap();
        assert_eq!(bobs.name, SHARED_NAME);
        let b = bob.get(&w.relay, "/devices").await;
        assert!(b.body.contains(SHARED_NAME) && !b.body.contains("Work Mac"));

        // Back to the same name, then she removes hers. Bob's is not
        // removed with it: not by name, not by anything else.
        let back = format!("/devices/{}/rename", w.alice.laptop.id);
        let r = alice.post(&w.relay, &back, &[("name", SHARED_NAME)]).await;
        assert_eq!(r.status, 303, "{}", r.body);
        let r = alice
            .post(
                &w.relay,
                &format!("/devices/{}/remove", w.alice.laptop.id),
                &[],
            )
            .await;
        assert_eq!(r.status, 303, "{}", r.body);
        assert!(w.store.device(&w.alice.laptop.id).await.unwrap().is_none());
        assert_bobs_laptop_untouched(&w).await;
        let own = w
            .relay
            .rpc(BOB, &w.bob.laptop.id, None, initialize_body())
            .await;
        assert_eq!(own.status, 200, "{}", own.body);
        let gone = w
            .relay
            .rpc(ALICE, &w.alice.laptop.id, None, initialize_body())
            .await;
        assert_eq!(gone.status, 404, "{}", gone.body);

        // She registers a new "MacBook Pro": a new computer, hers alone.
        let fresh = w.relay.register(ALICE, &ed25519(), SHARED_NAME).await;
        assert_ne!(fresh, w.bob.laptop.id);
        assert_ne!(fresh, w.alice.laptop.id);
        let rec = w.store.device(&fresh).await.unwrap().unwrap();
        assert_eq!(
            (rec.owner_sub.as_str(), rec.name.as_str()),
            (ALICE, SHARED_NAME)
        );
        assert_eq!(w.store.devices_of(BOB).await.unwrap().len(), 2);
        assert_bobs_laptop_untouched(&w).await;
    }

    // ------------------------------------------- through the app sign-in path
    //
    // Gemini signs itself up with the relay, sends the person to sign in and
    // allow it, and redeems a code for a token. Every step here is a real HTTP
    // request to the started relay; the only stand-in is the identity service
    // (its token endpoint, and the key set the relay checks tokens against).

    /// The id Google puts in the callback it registers (a made-up one).
    const GEMINI_ID: &str = "089fb14b828289a2178722b6";
    const VERIFIER: &str = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk";
    const APP_STATE: &str = "gemini-state-123";

    fn gemini_callbacks() -> Vec<String> {
        let mut out = Vec::new();
        for host in [
            "oauth-redirect",
            "oauth-redirect-sandbox",
            "oauth-redirect-test",
        ] {
            for kind in ["r", "a"] {
                out.push(format!(
                    "https://{host}.googleusercontent.com/{kind}/user_bound_custom-mcp-{GEMINI_ID}"
                ));
            }
        }
        out
    }

    /// The value of `key` in the query of `url`. Only for values that need no
    /// decoding (the ones the relay makes: codes and states).
    fn query_param(url: &str, key: &str) -> Option<String> {
        url.split_once('?')?
            .1
            .split('&')
            .find_map(|p| p.strip_prefix(&format!("{key}=")))
            .map(String::from)
    }

    /// What registering gave the app.
    struct GeminiApp {
        client_id: String,
        client_secret: String,
        redirect_uri: String,
    }

    async fn register_gemini(relay: &Relay) -> GeminiApp {
        let body = json!({
            "client_name": "Google",
            "redirect_uris": gemini_callbacks(),
            "token_endpoint_auth_method": "client_secret_post",
            "grant_types": ["authorization_code", "refresh_token"],
            "response_types": ["code"],
        });
        let r = send(
            relay.addr,
            "POST",
            "/oauth/register",
            &[
                ("content-type", "application/json".to_string()),
                ("cf-connecting-ip", "203.0.113.7".to_string()),
            ],
            &body.to_string(),
        )
        .await;
        assert_eq!(r.status, 201, "{}", r.body);
        let doc = r.json();
        GeminiApp {
            client_id: doc["client_id"].as_str().unwrap().to_string(),
            client_secret: doc["client_secret"].as_str().unwrap().to_string(),
            redirect_uri: doc["redirect_uris"][0].as_str().unwrap().to_string(),
        }
    }

    /// A browser part-way through allowing an app: the cookie that ties its
    /// sign-in to it, and the token the consent page's form carries.
    struct AtConsent {
        cookie: String,
        csrf: String,
    }

    /// The first half of the person's part: Gemini sends them to
    /// `/oauth/authorize` for `device`, they sign in at the identity service
    /// (a stand-in that knows them as `sub`), and land on the consent page.
    async fn reach_consent(relay: &Relay, app: &GeminiApp, sub: &str, device: &str) -> AtConsent {
        let challenge =
            b64url(ring::digest::digest(&ring::digest::SHA256, VERIFIER.as_bytes()).as_ref());
        let query: Vec<String> = [
            ("client_id", app.client_id.as_str()),
            ("redirect_uri", app.redirect_uri.as_str()),
            ("response_type", "code"),
            ("code_challenge", challenge.as_str()),
            ("code_challenge_method", "S256"),
            ("resource", &format!("{PUBLIC_URL}/mcp/app/{device}")),
            ("state", APP_STATE),
            ("scope", "mcp:tools"),
        ]
        .iter()
        .map(|(k, v)| format!("{k}={}", form_encode(v)))
        .collect();
        let start = send(
            relay.addr,
            "GET",
            &format!("/oauth/authorize?{}", query.join("&")),
            &[("cf-connecting-ip", "203.0.113.8".to_string())],
            "",
        )
        .await;
        assert_eq!(start.status, 303, "{}", start.body);
        let to_identity = start.header("location").unwrap();
        assert!(to_identity.starts_with(ISSUER), "{to_identity}");
        let state = query_param(&to_identity, "state").expect("state is sent");
        let cookie = set_cookie_pair(&start, "vr_oauth").expect("the sign-in is tied to a browser");

        relay.tokens.give_token(&relay.apps_token(sub));
        let back = send(
            relay.addr,
            "GET",
            &format!("/oauth/callback?code=the-code&state={state}"),
            &[("cookie", cookie.clone())],
            "",
        )
        .await;
        assert_eq!(back.status, 303, "{}", back.body);
        assert_eq!(back.header("location").as_deref(), Some("/oauth/consent"));
        let page = send(
            relay.addr,
            "GET",
            "/oauth/consent",
            &[("cookie", cookie.clone())],
            "",
        )
        .await;
        assert_eq!(page.status, 200, "{}", page.body);
        let csrf = page
            .body
            .split("name=\"csrf\" value=\"")
            .nth(1)
            .and_then(|a| a.split('"').next())
            .expect("the page has a form with a token")
            .to_string();
        AtConsent { cookie, csrf }
    }

    /// Posts the consent form: `cookie` is the browser's, `csrf` the token it
    /// carries.
    async fn decide(relay: &Relay, cookie: Option<&str>, csrf: &str, decision: &str) -> Reply {
        let mut headers = vec![
            (
                "content-type",
                "application/x-www-form-urlencoded".to_string(),
            ),
            ("origin", PUBLIC_URL.to_string()),
        ];
        if let Some(c) = cookie {
            headers.push(("cookie", c.to_string()));
        }
        send(
            relay.addr,
            "POST",
            "/oauth/consent",
            &headers,
            &format!("decision={decision}&csrf={}", form_encode(csrf)),
        )
        .await
    }

    /// Allow, then trade the code for a token as Gemini does; the token.
    async fn allow_and_redeem(relay: &Relay, app: &GeminiApp, browser: &AtConsent) -> String {
        let r = decide(relay, Some(&browser.cookie), &browser.csrf, "allow").await;
        assert_eq!(r.status, 303, "{}", r.body);
        let to = r.header("location").unwrap();
        assert!(to.starts_with(&app.redirect_uri), "{to}");
        assert_eq!(query_param(&to, "state").as_deref(), Some(APP_STATE));
        let code = query_param(&to, "code").expect("a code");
        let form: Vec<String> = [
            ("grant_type", "authorization_code"),
            ("code", code.as_str()),
            ("redirect_uri", app.redirect_uri.as_str()),
            ("code_verifier", VERIFIER),
            ("client_id", app.client_id.as_str()),
            ("client_secret", app.client_secret.as_str()),
        ]
        .iter()
        .map(|(k, v)| format!("{k}={}", form_encode(v)))
        .collect();
        let r = send(
            relay.addr,
            "POST",
            "/oauth/token",
            &[(
                "content-type",
                "application/x-www-form-urlencoded".to_string(),
            )],
            &form.join("&"),
        )
        .await;
        assert_eq!(r.status, 200, "{}", r.body);
        r.json()["access_token"]
            .as_str()
            .expect("a token")
            .to_string()
    }

    /// `tools/call` on `path` with `token`, answered by `computer`.
    async fn call_through(
        relay: &Relay,
        path: &str,
        token: &str,
        session: &str,
        computer: &mut FakeDevice,
        reply: &str,
    ) -> Reply {
        let (addr, path, token, session) = (
            relay.addr,
            path.to_string(),
            token.to_string(),
            session.to_string(),
        );
        let asked = tokio::spawn(async move {
            post(
                addr,
                &path,
                &token,
                Some(&session),
                call_body(7, "read_file", json!({"path": "/notes"})),
            )
            .await
        });
        let call = computer.next_call().await;
        computer.reply(&call.call_id, reply);
        asked.await.unwrap()
    }

    #[tokio::test(flavor = "multi_thread")]
    async fn gemini_flow_reaches_only_own_computer() {
        let w = world().await;
        let mut alices_computer = w
            .relay
            .connect(
                ALICE,
                &w.alice.laptop.id,
                &w.alice.laptop.key,
                vec![tool("read_file")],
            )
            .await;
        let mut bobs_computer = w
            .relay
            .connect(
                BOB,
                &w.bob.laptop.id,
                &w.bob.laptop.key,
                vec![tool("read_file")],
            )
            .await;

        // Alice connects Gemini to her laptop.
        let gemini = register_gemini(&w.relay).await;
        let consent = reach_consent(&w.relay, &gemini, ALICE, &w.alice.laptop.id).await;
        let token = allow_and_redeem(&w.relay, &gemini, &consent).await;

        // Her own computer works, end to end.
        let own_path = format!("/mcp/app/{}", w.alice.laptop.id);
        let r = post(w.relay.addr, &own_path, &token, None, initialize_body()).await;
        assert_eq!(r.status, 200, "{}", r.body);
        let session = r.session().expect("a session id");
        let r = call_through(
            &w.relay,
            &own_path,
            &token,
            &session,
            &mut alices_computer,
            "alice's notes",
        )
        .await;
        assert_eq!(text_of(&r), "alice's notes");

        // Bob's computers answer her exactly as a computer that does not exist.
        for theirs in [&w.bob.laptop.id, &w.bob.other.id] {
            let nowhere = nobody();
            let session = Some(session.as_str());
            for (what, session, body) in [
                ("initialize", None, initialize_body()),
                (
                    "tools/list",
                    session,
                    json!({"jsonrpc": "2.0", "id": 1, "method": "tools/list"}),
                ),
                (
                    "tools/call",
                    session,
                    call_body(2, "read_file", json!({"path": "/bob/secret"})),
                ),
            ] {
                let a = post(
                    w.relay.addr,
                    &format!("/mcp/app/{theirs}"),
                    &token,
                    session,
                    body.clone(),
                )
                .await;
                let b = post(
                    w.relay.addr,
                    &format!("/mcp/app/{nowhere}"),
                    &token,
                    session,
                    body,
                )
                .await;
                assert_same_as_missing(what, &a, theirs, &b, &nowhere);
            }
        }
        assert!(
            bobs_computer.gets_no_call(Duration::from_millis(300)).await,
            "a call through Alice's Gemini token reached Bob's computer"
        );
    }

    #[tokio::test(flavor = "multi_thread")]
    async fn claude_on_device_url_is_unchanged() {
        let w = world().await;
        let mut computer = w
            .relay
            .connect(
                ALICE,
                &w.alice.laptop.id,
                &w.alice.laptop.key,
                vec![tool("read_file")],
            )
            .await;

        // The relay is an authorization server for Gemini; Claude does not
        // notice. Its token still works on the device URL...
        let session = w.relay.session(ALICE, &w.alice.laptop.id).await;
        let r = call_through(
            &w.relay,
            &format!("/mcp/d/{}", w.alice.laptop.id),
            &w.relay.mcp_token(ALICE),
            &session,
            &mut computer,
            "alice's notes",
        )
        .await;
        assert_eq!(text_of(&r), "alice's notes");

        // ...and the URL still tells Claude to sign in at Zitadel.
        let path = format!(
            "/.well-known/oauth-protected-resource/mcp/d/{}",
            w.alice.laptop.id
        );
        let prm = send(w.relay.addr, "GET", &path, &[], "").await;
        assert_eq!(prm.status, 200, "{}", prm.body);
        let doc = prm.json();
        assert_eq!(
            doc["resource"],
            format!("{PUBLIC_URL}/mcp/d/{}", w.alice.laptop.id)
        );
        assert_eq!(doc["authorization_servers"], json!([ISSUER]));
        let challenge = send(
            w.relay.addr,
            "POST",
            &format!("/mcp/d/{}", w.alice.laptop.id),
            &[
                ("content-type", "application/json".to_string()),
                ("accept", "application/json, text/event-stream".to_string()),
            ],
            &initialize_body().to_string(),
        )
        .await;
        assert_eq!(challenge.status, 401, "{}", challenge.body);
        let www = challenge.header("www-authenticate").expect("a challenge");
        assert!(
            www.contains(&format!("/mcp/d/{}", w.alice.laptop.id)) && !www.contains("/mcp/app/"),
            "{www}"
        );
    }

    #[tokio::test(flavor = "multi_thread")]
    async fn consent_from_another_browser_issues_nothing() {
        let w = world().await;
        let gemini = register_gemini(&w.relay).await;
        // Alice's link, with her consent page open in her browser.
        let alices = reach_consent(&w.relay, &gemini, ALICE, &w.alice.laptop.id).await;

        // Someone else's browser has her page's token (say it was shown to
        // them) but not her cookie: no cookie at all, a made-up one, and one
        // from a sign-in they started themselves.
        let theirs = reach_consent(&w.relay, &gemini, BOB, &w.bob.laptop.id).await;
        let attempts = [
            None,
            Some("vr_oauth=made-up".to_string()),
            Some(theirs.cookie.clone()),
        ];
        for cookie in attempts {
            let r = decide(&w.relay, cookie.as_deref(), &alices.csrf, "allow").await;
            assert!(
                (400..500).contains(&r.status),
                "{cookie:?}: {} {}",
                r.status,
                r.body
            );
            assert!(
                r.header("location").is_none(),
                "{cookie:?}: sent on to {:?}",
                r.header("location")
            );
        }
        // Nor does the page itself open without the cookie.
        let page = send(w.relay.addr, "GET", "/oauth/consent", &[], "").await;
        assert_ne!(page.status, 200);
        assert!(!page.body.contains(&alices.csrf));

        // Alice's own browser is untouched and can still finish: exactly one
        // code, which her app can redeem, and not a second.
        let token = allow_and_redeem(&w.relay, &gemini, &alices).await;
        let own = post(
            w.relay.addr,
            &format!("/mcp/app/{}", w.alice.laptop.id),
            &token,
            None,
            initialize_body(),
        )
        .await;
        assert_eq!(own.status, 200, "{}", own.body);
        let again = decide(&w.relay, Some(&alices.cookie), &alices.csrf, "allow").await;
        assert!(again.header("location").is_none(), "{}", again.body);
    }
}
