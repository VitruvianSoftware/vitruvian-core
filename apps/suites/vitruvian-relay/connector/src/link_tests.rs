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

//! `vrelay run` against an in-process fake relay (a tokio-tungstenite server),
//! a fake desktop-commander and a fake dialog.

use super::*;
use crate::keys::{load_or_create, sha256_hex};
use crate::state::{now_unix, save_device, save_tokens, test_dir, DeviceInfo, Tokens};
use crate::status::{link_state, Link as LinkState};
use futures_util::{SinkExt, StreamExt};
use serde_json::json;
use std::net::SocketAddr;
use std::os::unix::fs::PermissionsExt;
use std::sync::atomic::{AtomicU64, AtomicUsize};
use tokio::net::TcpListener;
use tokio::sync::mpsc::{unbounded_channel, UnboundedReceiver, UnboundedSender};
use tokio_tungstenite::tungstenite::handshake::server::{Request, Response};
use tokio_tungstenite::tungstenite::Message;
use vitruvian_relay_protocol::{
    decode_to_relay, encode, hello_message, Call, ToConnector, ToRelay,
};

/// The most any step may take before a test gives up. Only a failing test
/// waits this long; it is generous so 8 copies of the suite at once (a
/// loaded CI runner) do not fail on a slow step.
const WAIT: Duration = Duration::from_secs(15);

// ------------------------------------------------------------ the fake relay

struct FakeRelay {
    addr: SocketAddr,
    conns: UnboundedReceiver<FakeConn>,
}

/// One connector connection. Dropping it drops the socket (a link drop).
struct FakeConn {
    auth: String,
    from: UnboundedReceiver<ToRelay>,
    to: UnboundedSender<ToConnector>,
}

impl FakeRelay {
    async fn start() -> FakeRelay {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let (tx, conns) = unbounded_channel();
        tokio::spawn(async move {
            while let Ok((tcp, _)) = listener.accept().await {
                let tx = tx.clone();
                tokio::spawn(async move {
                    let auth = Arc::new(Mutex::new(String::new()));
                    let a = auth.clone();
                    // tungstenite's callback type, not ours.
                    #[allow(clippy::result_large_err)]
                    let cb = move |req: &Request, resp: Response| {
                        *a.lock().unwrap() = req
                            .headers()
                            .get("authorization")
                            .and_then(|v| v.to_str().ok())
                            .unwrap_or_default()
                            .to_string();
                        Ok(resp)
                    };
                    let Ok(ws) = tokio_tungstenite::accept_hdr_async(tcp, cb).await else {
                        return;
                    };
                    let (mut sink, mut stream) = ws.split();
                    let (from_tx, from) = unbounded_channel();
                    let (to, mut to_rx) = unbounded_channel::<ToConnector>();
                    let auth = auth.lock().unwrap().clone();
                    if tx.send(FakeConn { auth, from, to }).is_err() {
                        return;
                    }
                    loop {
                        tokio::select! {
                            f = to_rx.recv() => match f {
                                Some(f) => {
                                    if sink.send(Message::Text(encode(&f).unwrap())).await.is_err() {
                                        break;
                                    }
                                }
                                None => break,
                            },
                            m = stream.next() => match m {
                                Some(Ok(Message::Text(t))) => {
                                    let _ = from_tx.send(decode_to_relay(&t).unwrap());
                                }
                                Some(Ok(_)) => {}
                                _ => break,
                            },
                        }
                    }
                });
            }
        });
        FakeRelay { addr, conns }
    }

    fn url(&self) -> String {
        format!("http://{}", self.addr)
    }

    async fn next_conn(&mut self) -> FakeConn {
        tokio::time::timeout(WAIT, self.conns.recv())
            .await
            .expect("the connector connects")
            .unwrap()
    }

    /// Accepts the next connection, reads its hello and sends welcome.
    async fn welcome(&mut self) -> (FakeConn, Hello) {
        let mut c = self.next_conn().await;
        let hello = c.welcome().await;
        (c, hello)
    }
}

impl FakeConn {
    async fn welcome(&mut self) -> Hello {
        let hello = match self.recv_any().await {
            ToRelay::Hello(h) => h,
            other => panic!("first frame was {other:?}"),
        };
        self.send(ToConnector::Welcome {
            device_id: hello.device_id.clone(),
        });
        hello
    }

    fn send(&self, f: ToConnector) {
        self.to.send(f).unwrap();
    }

    async fn recv_any(&mut self) -> ToRelay {
        tokio::time::timeout(WAIT, self.from.recv())
            .await
            .expect("a frame from the connector")
            .expect("the link is up")
    }

    /// The next frame that is not a ping or pong.
    async fn recv(&mut self) -> ToRelay {
        loop {
            match self.recv_any().await {
                ToRelay::Ping { .. } | ToRelay::Pong { .. } => {}
                f => return f,
            }
        }
    }

    async fn result(&mut self) -> CallResult {
        match self.recv().await {
            ToRelay::Result(r) => r,
            other => panic!("expected a result, got {other:?}"),
        }
    }

    /// Nothing but pings for `d`.
    async fn quiet_for(&mut self, d: Duration) {
        let end = tokio::time::Instant::now() + d;
        loop {
            match tokio::time::timeout_at(end, self.from.recv()).await {
                Err(_) => return,
                Ok(Some(ToRelay::Ping { .. })) | Ok(Some(ToRelay::Pong { .. })) => {}
                Ok(other) => panic!("expected nothing, got {other:?}"),
            }
        }
    }

    fn call(&self, id: &str, tool: &str, args: Value) {
        self.send(ToConnector::Call(Call {
            call_id: id.into(),
            tool: tool.into(),
            arguments: args,
            deadline_ms: 30_000,
        }));
    }
}

// --------------------------------------------------- fake tools, dialog, token

fn tool(name: &str) -> ToolDef {
    ToolDef {
        name: name.into(),
        description: format!("{name} tool"),
        input_schema: json!({"type": "object"}),
    }
}

#[derive(Default)]
struct FakeTools {
    defs: Mutex<Vec<ToolDef>>,
    calls: Mutex<Vec<(String, Value)>>,
    deadlines: Mutex<Vec<Instant>>,
    /// If set, each call checks that this calls.log already holds its
    /// `running` line, and notes the answer.
    log_path: Mutex<Option<PathBuf>>,
    logged_first: Mutex<Vec<bool>>,
}

impl FakeTools {
    fn with(names: &[&str]) -> Arc<FakeTools> {
        let t = FakeTools::default();
        *t.defs.lock().unwrap() = names.iter().map(|n| tool(n)).collect();
        Arc::new(t)
    }
    fn count(&self) -> usize {
        self.calls.lock().unwrap().len()
    }
}

impl Tools for FakeTools {
    fn list(&self) -> impl Future<Output = Vec<ToolDef>> + Send {
        let defs = self.defs.lock().unwrap().clone();
        async move { defs }
    }

    fn call(
        &self,
        tool: &str,
        args: Value,
        deadline: Instant,
    ) -> impl Future<Output = BridgeOutput> + Send {
        self.deadlines.lock().unwrap().push(deadline);
        if let Some(p) = self.log_path.lock().unwrap().as_ref() {
            let text = std::fs::read_to_string(p).unwrap_or_default();
            let on_disk = text.lines().any(|l| {
                serde_json::from_str::<Value>(l)
                    .is_ok_and(|v| v["decision"] == "running" && v["arguments"] == args)
            });
            self.logged_first.lock().unwrap().push(on_disk);
        }
        self.calls
            .lock()
            .unwrap()
            .push((tool.to_string(), args.clone()));
        let text = format!("{tool} ran with {args}");
        let sleep = args.get("sleep_ms").and_then(Value::as_u64).unwrap_or(0);
        async move {
            tokio::time::sleep(Duration::from_millis(sleep)).await;
            BridgeOutput {
                content: json!([{"type": "text", "text": text}]),
                is_error: false,
                truncated: false,
            }
        }
    }
}

/// A dialog the test answers. It notes when the link asks it to close, and
/// still answers whatever the test sets afterwards (a late Allow).
#[derive(Default)]
struct FakeAsker {
    answer: Mutex<Option<Waited>>,
    opened: AtomicUsize,
    dismissed: AtomicUsize,
    summaries: Mutex<Vec<String>>,
}

impl FakeAsker {
    fn answering(a: Option<Waited>) -> Arc<FakeAsker> {
        let f = FakeAsker::default();
        *f.answer.lock().unwrap() = a;
        Arc::new(f)
    }
    fn set(&self, a: Waited) {
        *self.answer.lock().unwrap() = Some(a);
    }
}

impl Asker for FakeAsker {
    fn ask(&self, _tool: &str, summary: &str, _timeout: Duration, dismiss: &AtomicBool) -> Waited {
        self.summaries.lock().unwrap().push(summary.to_string());
        self.opened.fetch_add(1, Ordering::SeqCst);
        let start = Instant::now();
        let mut noted = false;
        loop {
            if !noted && dismiss.load(Ordering::SeqCst) {
                noted = true;
                self.dismissed.fetch_add(1, Ordering::SeqCst);
            }
            if let Some(a) = *self.answer.lock().unwrap() {
                return a;
            }
            if start.elapsed() > Duration::from_secs(8) {
                return Waited::TimedOut;
            }
            std::thread::sleep(Duration::from_millis(5));
        }
    }
}

/// Hands out `tok-1`, `tok-2`, ... (or nothing, while `none` is set; or
/// "sign in again", while `refused` is set). `asked` counts every call.
#[derive(Default)]
struct FakeTokens {
    n: AtomicUsize,
    asked: AtomicUsize,
    none: AtomicBool,
    refused: AtomicBool,
}

impl TokenSource for FakeTokens {
    fn token(&self) -> std::result::Result<Option<String>, TokenError> {
        self.asked.fetch_add(1, Ordering::SeqCst);
        if self.refused.load(Ordering::SeqCst) {
            return Err(TokenError::SignInAgain(
                "sign in again: invalid_grant".into(),
            ));
        }
        if self.none.load(Ordering::SeqCst) {
            return Ok(None);
        }
        Ok(Some(format!(
            "tok-{}",
            self.n.fetch_add(1, Ordering::SeqCst) + 1
        )))
    }
}

// ------------------------------------------------------------------ helpers

fn fast() -> Timing {
    Timing {
        ping_every: Duration::from_secs(60),
        max_missed: 3,
        status_every: Duration::from_millis(50),
        token_poll: Duration::from_millis(50),
        reset_after: Duration::from_secs(60),
        dedupe_window: Duration::from_secs(600),
        backoff_unit: Duration::from_millis(1),
        connect_timeout: WAIT,
        send_timeout: WAIT,
        welcome_timeout: WAIT,
        max_prompt: Duration::from_secs(60),
        // Off unless a test turns it on: most fakes send nothing while a
        // dialog is open.
        in_call_every: Duration::from_secs(60),
        prune_every: Duration::from_secs(60),
        max_call: Duration::from_secs(180),
        max_in_flight: 16,
        max_dialogs: 1,
        results_cap_bytes: 16 * 1024 * 1024,
        log_max_bytes: 10 * 1024 * 1024,
    }
}

/// The real clock, plus however far a test moves it on.
#[derive(Default)]
struct TestClock(AtomicU64);

impl TestClock {
    fn clock(self: &Arc<Self>) -> Clock {
        let me = self.clone();
        Arc::new(move || now_unix() + me.0.load(Ordering::SeqCst))
    }
    fn advance(&self, secs: u64) {
        self.0.fetch_add(secs, Ordering::SeqCst);
    }
}

fn gate() -> Gate {
    Gate {
        reached: Arc::new(tokio::sync::Notify::new()),
        go: Arc::new(tokio::sync::Notify::new()),
    }
}

fn registered(name: &str) -> PathBuf {
    let dir = test_dir(name);
    save_device(
        &dir,
        &DeviceInfo {
            device_id: "dev-1".into(),
            mcp_url: "https://relay.example/mcp/d/dev-1".into(),
        },
    )
    .unwrap();
    dir
}

struct Parts<A: Asker, K: TokenSource> {
    tools: Arc<FakeTools>,
    asker: Arc<A>,
    tokens: Arc<K>,
    rng: Rng,
    timing: Timing,
    rules: Rules,
    clock: Clock,
    hooks: Hooks,
}

fn parts() -> Parts<FakeAsker, FakeTokens> {
    Parts {
        tools: FakeTools::with(&["read_file", "start_process", "set_config_value"]),
        asker: FakeAsker::answering(Some(Waited::Allow)),
        tokens: Arc::new(FakeTokens::default()),
        rng: Arc::new(Mutex::new(|cap: u64| cap)),
        timing: fast(),
        rules: toml::from_str(crate::rules::DEFAULT_RULES).unwrap(),
        clock: Arc::new(now_unix),
        hooks: Hooks::default(),
    }
}

struct Running {
    task: tokio::task::JoinHandle<()>,
    reload: mpsc::Sender<()>,
    _shutdown: watch::Sender<bool>,
}

impl Drop for Running {
    fn drop(&mut self) {
        self.task.abort();
    }
}

fn start<A: Asker, K: TokenSource>(dir: &Path, url: &str, p: Parts<A, K>) -> Running {
    let link = Link {
        dir: dir.to_path_buf(),
        log_dir: dir.join("logs"),
        relay_url: url.to_string(),
        tools: p.tools,
        asker: p.asker,
        tokens: p.tokens,
        rules: p.rules,
        key: Arc::new(load_or_create(dir).unwrap()),
        timing: p.timing,
        clock: p.clock,
        rng: p.rng,
        log: Arc::new(|s: &str| eprintln!("link: {s}")),
        tls: None,
        hooks: p.hooks,
    };
    let (reload, reload_rx) = mpsc::channel(4);
    let (shutdown, shutdown_rx) = watch::channel(false);
    Running {
        task: tokio::spawn(link.run(reload_rx, shutdown_rx)),
        reload,
        _shutdown: shutdown,
    }
}

async fn until(what: &str, f: impl Fn() -> bool) {
    let end = Instant::now() + WAIT;
    while !f() {
        assert!(Instant::now() < end, "timed out waiting for {what}");
        tokio::time::sleep(Duration::from_millis(5)).await;
    }
}

fn text(r: &CallResult) -> String {
    r.content[0]["text"]
        .as_str()
        .unwrap_or_default()
        .to_string()
}

fn log_lines(dir: &Path) -> Vec<Value> {
    std::fs::read_to_string(dir.join("logs").join("calls.log"))
        .unwrap_or_default()
        .lines()
        .map(|l| serde_json::from_str(l).unwrap())
        .collect()
}

async fn until_logged(dir: &Path, decision: &str) -> Value {
    let end = Instant::now() + WAIT;
    loop {
        if let Some(l) = log_lines(dir)
            .into_iter()
            .find(|l| l["decision"] == decision)
        {
            return l;
        }
        assert!(Instant::now() < end, "no `{decision}` line in calls.log");
        tokio::time::sleep(Duration::from_millis(5)).await;
    }
}

// -------------------------------------------------------------------- tests

#[test]
fn production_values_are_pinned() {
    let t = Timing::default();
    assert_eq!(t.ping_every, Duration::from_secs(20));
    assert_eq!(t.max_missed, 3);
    assert_eq!(t.status_every, Duration::from_secs(20));
    assert_eq!(t.token_poll, Duration::from_secs(10));
    assert_eq!(t.reset_after, Duration::from_secs(60));
    assert_eq!(t.dedupe_window, Duration::from_secs(600));
    assert_eq!(t.backoff_unit, Duration::from_secs(1));
    assert_eq!(t.max_prompt, crate::prompt::DEFAULT_TIMEOUT);
    assert_eq!(DENIED, "Denied on the computer.");
    assert_eq!(
        ALREADY_STARTED,
        "This call already started before vrelay restarted; not run again."
    );
}

#[test]
fn relay_url_becomes_the_connect_url() {
    assert_eq!(
        connect_url("https://relay.ipv1337.dev").unwrap(),
        "wss://relay.ipv1337.dev/connect"
    );
    assert_eq!(
        connect_url("http://127.0.0.1:9").unwrap(),
        "ws://127.0.0.1:9/connect"
    );
    assert!(connect_url("ftp://x").is_err());
    // Plain http sends the token in clear text: this machine only.
    for ok in [
        "http://localhost:8080",
        "http://[::1]:9",
        "http://127.0.0.1",
    ] {
        assert!(connect_url(ok).is_ok(), "{ok}");
    }
    for bad in [
        "http://relay.ipv1337.dev",
        "http://127.0.0.1.evil.example",
        "http://localhost.evil.example:80",
        "http://10.0.0.1:9",
    ] {
        assert!(connect_url(bad).is_err(), "{bad}");
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn sends_hello_with_visible_tools_only() {
    let mut relay = FakeRelay::start().await;
    let dir = registered("l-hello");
    let _run = start(&dir, &relay.url(), parts());
    let (c, hello) = relay.welcome().await;
    assert_eq!(c.auth, "Bearer tok-1");
    assert_eq!(hello.device_id, "dev-1");
    assert_eq!(hello.protocol, vitruvian_relay_protocol::PROTOCOL);
    let names: Vec<_> = hello.tools.iter().map(|t| t.name.as_str()).collect();
    assert_eq!(names, ["read_file", "start_process"]);
    // The signature is over this token, with the device's own key.
    let key = load_or_create(&dir).unwrap();
    let sig =
        base64::Engine::decode(&base64::engine::general_purpose::STANDARD, &hello.sig).unwrap();
    let msg = hello_message("dev-1", hello.ts, &sha256_hex("tok-1"));
    ring::signature::UnparsedPublicKey::new(
        &ring::signature::ED25519,
        ring::signature::KeyPair::public_key(&key).as_ref(),
    )
    .verify(msg.as_bytes(), &sig)
    .unwrap();
    assert!(now_unix().abs_diff(hello.ts) < 5);
}

#[tokio::test(flavor = "multi_thread")]
async fn repeated_call_id_runs_once() {
    let mut relay = FakeRelay::start().await;
    let dir = registered("l-repeat");
    let p = parts();
    let tools = p.tools.clone();
    let _run = start(&dir, &relay.url(), p);
    let (mut c, _) = relay.welcome().await;
    let args = json!({"path": "/tmp/a", "sleep_ms": 200});
    c.call("c1", "read_file", args.clone());
    // While it runs, a repeat gets nothing.
    c.call("c1", "read_file", args.clone());
    let first = c.result().await;
    assert_eq!(first.call_id, "c1");
    assert!(!first.is_error, "{first:?}");
    // Once done, a repeat gets the stored result again.
    c.call("c1", "read_file", args.clone());
    let again = c.result().await;
    assert_eq!(again, first);
    c.quiet_for(Duration::from_millis(300)).await;
    assert_eq!(tools.count(), 1);
}

#[tokio::test(flavor = "multi_thread")]
async fn ask_first_denied_returns_error() {
    let mut relay = FakeRelay::start().await;
    let dir = registered("l-deny");
    let mut p = parts();
    p.asker = FakeAsker::answering(Some(Waited::Deny));
    let tools = p.tools.clone();
    let asker = p.asker.clone();
    let _run = start(&dir, &relay.url(), p);
    let (mut c, _) = relay.welcome().await;
    c.call("c1", "start_process", json!({"command": "rm -rf ~/x"}));
    let r = c.result().await;
    assert_eq!(r.call_id, "c1");
    assert!(r.is_error);
    assert_eq!(text(&r), DENIED);
    assert_eq!(tools.count(), 0);
    // The person saw what would run.
    assert!(
        asker.summaries.lock().unwrap()[0].contains("rm -rf ~/x"),
        "{:?}",
        asker.summaries.lock().unwrap()
    );
    until_logged(&dir, "denied").await;

    // A dialog that gives up is "timed out", and nothing runs either.
    asker.set(Waited::TimedOut);
    c.call("c2", "start_process", json!({"command": "ls"}));
    let r = c.result().await;
    assert!(r.is_error && text(&r).contains("No answer"), "{r:?}");
    assert_eq!(tools.count(), 0);
    until_logged(&dir, "timed out").await;
}

#[tokio::test(flavor = "multi_thread")]
async fn refused_calls_and_long_ids_never_run() {
    let mut relay = FakeRelay::start().await;
    let dir = registered("l-refuse");
    let p = parts();
    let tools = p.tools.clone();
    let asker = p.asker.clone();
    let _run = start(&dir, &relay.url(), p);
    let (mut c, _) = relay.welcome().await;
    c.call(
        "c1",
        "set_config_value",
        json!({"key": "allowedDirectories"}),
    );
    let r = c.result().await;
    assert!(
        r.is_error && text(&r).contains("not available remotely"),
        "{r:?}"
    );
    let long = "x".repeat(CALL_ID_RESERVE + 1);
    c.call(&long, "read_file", json!({"path": "/tmp/a"}));
    let r = c.result().await;
    assert_eq!(r.call_id, long);
    assert!(r.is_error && text(&r).contains("call id"), "{r:?}");
    // An id of exactly the limit is fine.
    let ok = "y".repeat(CALL_ID_RESERVE);
    c.call(&ok, "read_file", json!({"path": "/tmp/a"}));
    assert!(!c.result().await.is_error);
    assert_eq!(tools.count(), 1);
    assert_eq!(asker.opened.load(Ordering::SeqCst), 0);
    until_logged(&dir, "refused").await;
}

#[tokio::test(flavor = "multi_thread")]
async fn repeated_call_id_after_restart_is_refused() {
    let mut relay = FakeRelay::start().await;
    let dir = registered("l-restart");
    let p = parts();
    let tools = p.tools.clone();
    let run = start(&dir, &relay.url(), p);
    let (mut c, _) = relay.welcome().await;
    c.call("c1", "read_file", json!({"path": "/tmp/a"}));
    assert!(!c.result().await.is_error);
    assert_eq!(tools.count(), 1);
    // An id seen 11 minutes ago is past the window.
    let seen = dir.join("seen_calls.jsonl");
    let mut body = std::fs::read_to_string(&seen).unwrap();
    body.push_str(&format!(
        "{}\n",
        json!({"id": "old", "t": now_unix() - 660})
    ));
    std::fs::write(&seen, body).unwrap();

    // vrelay restarts (a new process: nothing in memory).
    drop(run);
    drop(c);
    let mut p = parts();
    p.tools = tools.clone();
    let _run = start(&dir, &relay.url(), p);
    let (mut c, _) = relay.welcome().await;
    c.call("c1", "read_file", json!({"path": "/tmp/a"}));
    let r = c.result().await;
    assert!(r.is_error);
    assert_eq!(text(&r), ALREADY_STARTED);
    assert_eq!(tools.count(), 1);
    c.call("old", "read_file", json!({"path": "/tmp/b"}));
    assert!(!c.result().await.is_error);
    assert_eq!(tools.count(), 2);
    // The file holds ids and times only, and the expired one is gone.
    let kept = std::fs::read_to_string(&seen).unwrap();
    assert_eq!(
        std::fs::metadata(&seen).unwrap().permissions().mode() & 0o777,
        0o600
    );
    assert!(!kept.contains("/tmp/a"), "{kept}");
    let lines: Vec<Value> = kept
        .lines()
        .map(|l| serde_json::from_str(l).unwrap())
        .collect();
    assert!(
        lines.iter().all(|l| l.as_object().unwrap().len() == 2),
        "{kept}"
    );
    assert_eq!(
        lines.iter().filter(|l| l["id"] == "old").count(),
        1,
        "{kept}"
    );
    assert!(
        lines
            .iter()
            .all(|l| l["t"].as_u64().unwrap() + 600 >= now_unix()),
        "{kept}"
    );
}

#[tokio::test(flavor = "multi_thread")]
async fn concurrent_calls_are_answered_by_id() {
    let mut relay = FakeRelay::start().await;
    let dir = registered("l-concurrent");
    let p = parts();
    let tools = p.tools.clone();
    let _run = start(&dir, &relay.url(), p);
    let (mut c, _) = relay.welcome().await;
    c.call("slow", "read_file", json!({"path": "/a", "sleep_ms": 400}));
    c.call("fast", "read_file", json!({"path": "/b", "sleep_ms": 10}));
    let first = c.result().await;
    let second = c.result().await;
    assert_eq!(first.call_id, "fast");
    assert!(text(&first).contains("/b"), "{first:?}");
    assert_eq!(second.call_id, "slow");
    assert!(text(&second).contains("/a"), "{second:?}");
    assert_eq!(tools.count(), 2);
}

#[tokio::test(flavor = "multi_thread")]
async fn cancel_during_prompt_never_runs() {
    let mut relay = FakeRelay::start().await;
    let dir = registered("l-cancel");
    let mut p = parts();
    p.asker = FakeAsker::answering(None);
    let tools = p.tools.clone();
    let asker = p.asker.clone();
    let _run = start(&dir, &relay.url(), p);
    let (mut c, _) = relay.welcome().await;
    c.call("c1", "start_process", json!({"command": "touch /tmp/x"}));
    until("the dialog", || asker.opened.load(Ordering::SeqCst) == 1).await;
    c.send(ToConnector::Cancel {
        call_id: "c1".into(),
    });
    until("the dismiss", || {
        asker.dismissed.load(Ordering::SeqCst) == 1
    })
    .await;
    // A late Allow changes nothing.
    asker.set(Waited::Allow);
    until_logged(&dir, "cancelled at prompt").await;
    c.quiet_for(Duration::from_millis(200)).await;
    assert_eq!(tools.count(), 0);
}

#[tokio::test(flavor = "multi_thread")]
async fn cancel_while_running_drops_the_result() {
    let mut relay = FakeRelay::start().await;
    let dir = registered("l-cancel-run");
    let p = parts();
    let tools = p.tools.clone();
    let _run = start(&dir, &relay.url(), p);
    let (mut c, _) = relay.welcome().await;
    c.call("c1", "read_file", json!({"path": "/a", "sleep_ms": 200}));
    until("the call to start", || tools.count() == 1).await;
    c.send(ToConnector::Cancel {
        call_id: "c1".into(),
    });
    let line = until_logged(&dir, "ran").await;
    assert_eq!(line["result_dropped"], true, "{line}");
    c.quiet_for(Duration::from_millis(200)).await;
}

#[tokio::test(flavor = "multi_thread")]
async fn pongs_flow_while_prompt_open() {
    // Production: the prompt is open up to 60 s while the relay pings every
    // 2 s and fails the call after 3 missed. Here: a ping every 100 ms for
    // 2 s with the dialog open throughout, each answered well inside the
    // relay's window (1 s, so a busy test machine does not flake it). A
    // link loop that waited on the dialog would answer none of them.
    let mut relay = FakeRelay::start().await;
    let dir = registered("l-pongs");
    let mut p = parts();
    p.asker = FakeAsker::answering(None);
    let asker = p.asker.clone();
    let _run = start(&dir, &relay.url(), p);
    let (mut c, _) = relay.welcome().await;
    c.call("c1", "start_process", json!({"command": "ls"}));
    until("the dialog", || asker.opened.load(Ordering::SeqCst) == 1).await;
    let every = Duration::from_millis(100);
    let window = Duration::from_secs(1);
    let open_since = Instant::now();
    for n in 1..=20u64 {
        let sent = Instant::now();
        c.send(ToConnector::Ping { n });
        loop {
            let left = window.saturating_sub(sent.elapsed());
            match tokio::time::timeout(left, c.from.recv()).await {
                Ok(Some(ToRelay::Pong { n: got })) if got == n => break,
                Ok(Some(ToRelay::Ping { .. })) => {}
                Ok(other) => panic!("ping {n}: got {other:?}"),
                Err(_) => panic!("ping {n} was not answered within {window:?}"),
            }
        }
        tokio::time::sleep(every.saturating_sub(sent.elapsed())).await;
    }
    // The dialog really was open the whole time.
    assert!(open_since.elapsed() >= Duration::from_secs(2));
    assert_eq!(asker.dismissed.load(Ordering::SeqCst), 0);
    asker.set(Waited::Deny);
    assert_eq!(text(&c.result().await), DENIED);
}

#[tokio::test(flavor = "multi_thread")]
async fn link_drop_dismisses_open_prompts() {
    let mut relay = FakeRelay::start().await;
    let dir = registered("l-drop");
    let mut p = parts();
    p.asker = FakeAsker::answering(None);
    let tools = p.tools.clone();
    let asker = p.asker.clone();
    let _run = start(&dir, &relay.url(), p);
    let (c, _) = relay.welcome().await;
    c.call("c1", "start_process", json!({"command": "touch /tmp/x"}));
    until("the dialog", || asker.opened.load(Ordering::SeqCst) == 1).await;
    drop(c);
    until("the dismiss", || {
        asker.dismissed.load(Ordering::SeqCst) == 1
    })
    .await;
    asker.set(Waited::Allow);
    until_logged(&dir, "link dropped at prompt").await;
    // It reconnects; the dropped call is not run, here or later.
    let (mut c, _) = relay.welcome().await;
    c.quiet_for(Duration::from_millis(200)).await;
    assert_eq!(tools.count(), 0);
}

#[test]
fn backoff_is_full_jitter_with_a_one_second_floor() {
    for n in 0..=20u32 {
        let cap = 60u64.min(1u64 << n.min(6));
        let mut asked = None;
        for pick in [0, 1, cap / 2, cap] {
            let d = backoff_secs(n, &mut |c| {
                asked = Some(c);
                pick
            });
            assert!((1..=cap).contains(&d), "n={n} pick={pick} -> {d}");
        }
        assert_eq!(asked, Some(cap), "n={n}");
    }
    assert_eq!(backoff_secs(0, &mut |c| c), 1);
    assert_eq!(backoff_secs(0, &mut |_| 0), 1);
    assert_eq!(backoff_secs(10, &mut |c| c), 60);
    // A random source that overshoots is clamped.
    assert_eq!(backoff_secs(3, &mut |_| 1000), 8);
    // The production source stays in range.
    for _ in 0..200 {
        let d = backoff_secs(4, &mut system_rng);
        assert!((1..=16).contains(&d));
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn reconnects_with_jittered_backoff() {
    let mut relay = FakeRelay::start().await;
    let dir = registered("l-backoff");
    let mut p = parts();
    let caps = Arc::new(Mutex::new(Vec::new()));
    let seen = caps.clone();
    p.rng = Arc::new(Mutex::new(move |cap: u64| {
        seen.lock().unwrap().push(cap);
        cap
    }));
    p.timing.reset_after = Duration::from_millis(100);
    let _run = start(&dir, &relay.url(), p);
    // Two quick drops in a row: the cap doubles.
    for _ in 0..2 {
        drop(relay.next_conn().await);
    }
    // Then a link that stays up long enough: the count starts again.
    let (c, _) = relay.welcome().await;
    tokio::time::sleep(Duration::from_millis(200)).await;
    drop(c);
    let _c = relay.next_conn().await;
    assert_eq!(*caps.lock().unwrap(), [1, 2, 1]);
}

#[tokio::test(flavor = "multi_thread")]
async fn waits_for_token_instead_of_exiting() {
    let mut relay = FakeRelay::start().await;
    let dir = test_dir("l-token-wait");
    let cfg = Config::from_lookup(|k| match k {
        "VRELAY_HOME" => Some(dir.display().to_string()),
        _ => None,
    });
    let p = parts();
    let real = Parts {
        tools: p.tools,
        asker: p.asker,
        tokens: Arc::new(FileTokens::new(cfg)),
        rng: p.rng,
        timing: p.timing,
        rules: p.rules,
        clock: p.clock,
        hooks: p.hooks,
    };
    let run = start(&dir, &relay.url(), real);
    until("waiting for sign-in", || {
        link_state(&dir, now_unix()) == LinkState::WaitingForSignIn
    })
    .await;
    tokio::time::sleep(Duration::from_millis(200)).await;
    assert!(!run.task.is_finished());
    assert!(relay.conns.try_recv().is_err(), "connected with no token");
    // `vrelay login` finishes: a token and a device appear.
    save_tokens(
        &dir,
        &Tokens {
            access_token: "file-token".into(),
            refresh_token: Some("r".into()),
            expires_at_unix: now_unix() + 3600,
        },
    )
    .unwrap();
    save_device(
        &dir,
        &DeviceInfo {
            device_id: "dev-1".into(),
            mcp_url: "u".into(),
        },
    )
    .unwrap();
    let (c, _) = relay.welcome().await;
    assert_eq!(c.auth, "Bearer file-token");
}

#[tokio::test(flavor = "multi_thread")]
async fn status_file_tracks_link_state() {
    let mut relay = FakeRelay::start().await;
    let dir = registered("l-status");
    let mut p = parts();
    let tokens = p.tokens.clone();
    // Slow enough retries to see "connecting" with a retry time, even on a
    // busy machine (the status writer keeps only the newest state).
    p.timing.backoff_unit = Duration::from_millis(1000);
    let _run = start(&dir, &relay.url(), p);
    let state = || link_state(&dir, now_unix());
    let mut c = relay.next_conn().await;
    let _hello = c.recv_any().await;
    until("connecting", || state() == LinkState::Connecting(None)).await;
    c.send(ToConnector::Welcome {
        device_id: "dev-1".into(),
    });
    until("connected", || state() == LinkState::Connected).await;
    let raw: Value =
        serde_json::from_slice(&std::fs::read(dir.join("status.json")).unwrap()).unwrap();
    assert!(raw["last_pong_unix"].as_u64().is_some(), "{raw}");
    // Signed out while the link is down.
    tokens.none.store(true, Ordering::SeqCst);
    drop(c);
    until("connecting after the drop", || {
        matches!(state(), LinkState::Connecting(Some(_)))
    })
    .await;
    until("waiting for sign-in", || {
        state() == LinkState::WaitingForSignIn
    })
    .await;
    // Kept fresh while waiting.
    let before = std::fs::read(dir.join("status.json")).unwrap();
    until("a rewrite", || {
        std::fs::read(dir.join("status.json")).unwrap() != before
    })
    .await;
}

#[tokio::test(flavor = "multi_thread")]
async fn refreshes_token_before_reconnect() {
    let mut relay = FakeRelay::start().await;
    let dir = registered("l-refresh");
    let p = parts();
    let tokens = p.tokens.clone();
    let _run = start(&dir, &relay.url(), p);
    let (c, h1) = relay.welcome().await;
    assert_eq!(c.auth, "Bearer tok-1");
    // The relay closes the socket when the token expires.
    drop(c);
    let (c, h2) = relay.welcome().await;
    assert_eq!(c.auth, "Bearer tok-2");
    assert_eq!(tokens.n.load(Ordering::SeqCst), 2);
    // Each hello is signed over its own token.
    assert_ne!(h1.sig, h2.sig);
    // A reject is a drop too, followed by a fresh token.
    c.send(ToConnector::Reject {
        reason: "device registered again".into(),
    });
    let (c, _) = relay.welcome().await;
    assert_eq!(c.auth, "Bearer tok-3");
}

#[tokio::test(flavor = "multi_thread")]
async fn missed_pings_trigger_reconnect() {
    let mut relay = FakeRelay::start().await;
    let dir = registered("l-missed");
    let mut p = parts();
    p.timing.ping_every = Duration::from_millis(50);
    let _run = start(&dir, &relay.url(), p);
    let (mut c, _) = relay.welcome().await;
    // The fake never answers. Three pings go out unanswered, then the link
    // gives up and dials again.
    let mut pings = 0;
    let mut next = None;
    let end = Instant::now() + WAIT;
    while next.is_none() {
        assert!(Instant::now() < end, "no reconnect");
        tokio::select! {
            f = c.from.recv() => match f {
                Some(ToRelay::Ping { .. }) => pings += 1,
                Some(other) => panic!("{other:?}"),
                None => {}
            },
            n = relay.conns.recv() => next = n,
        }
    }
    while let Ok(f) = c.from.try_recv() {
        assert!(matches!(f, ToRelay::Ping { .. }), "{f:?}");
        pings += 1;
    }
    assert_eq!(pings, 3);

    // Answered pings keep the link up.
    let mut c = next.unwrap();
    c.welcome().await;
    let end = Instant::now() + Duration::from_millis(500);
    while Instant::now() < end {
        if let Ok(Some(ToRelay::Ping { n })) =
            tokio::time::timeout(Duration::from_millis(20), c.from.recv()).await
        {
            c.send(ToConnector::Pong { n });
        }
    }
    assert!(
        relay.conns.try_recv().is_err(),
        "reconnected while pongs flowed"
    );
}

#[tokio::test(flavor = "multi_thread")]
async fn call_log_is_0600_and_has_arguments() {
    let mut relay = FakeRelay::start().await;
    let dir = registered("l-log");
    let _run = start(&dir, &relay.url(), parts());
    let (mut c, _) = relay.welcome().await;
    let args = json!({"path": "/Users/x/secret.txt", "offset": 3});
    c.call("c1", "read_file", args.clone());
    c.result().await;
    let start = until_logged(&dir, "running").await;
    assert_eq!(start["call_id"], "c1");
    assert_eq!(start["tool"], "read_file");
    assert_eq!(start["arguments"], args);
    assert_eq!(start["approval"], "no_prompt");
    assert!(start["t"].as_u64().is_some());
    let end = until_logged(&dir, "ran").await;
    assert_eq!(end["call_id"], "c1");
    assert_eq!(end["is_error"], false);
    let path = dir.join("logs").join("calls.log");
    assert_eq!(
        std::fs::metadata(&path).unwrap().permissions().mode() & 0o777,
        0o600
    );
    assert_eq!(
        std::fs::metadata(dir.join("logs"))
            .unwrap()
            .permissions()
            .mode()
            & 0o777,
        0o700
    );
}

#[tokio::test(flavor = "multi_thread")]
async fn sighup_reload_sends_tools_changed_and_keeps_rules_on_error() {
    let mut relay = FakeRelay::start().await;
    let dir = registered("l-reload");
    crate::rules::load(&dir).unwrap(); // writes the defaults
    let p = parts();
    let tools = p.tools.clone();
    let run = start(&dir, &relay.url(), p);
    let (mut c, _) = relay.welcome().await;
    // Pause: no tools visible.
    let path = crate::rules::rules_path(&dir);
    let rules = std::fs::read_to_string(&path).unwrap();
    std::fs::write(&path, rules.replace("paused = false", "paused = true")).unwrap();
    run.reload.send(()).await.unwrap();
    match c.recv().await {
        ToRelay::ToolsChanged { tools } => assert!(tools.is_empty()),
        other => panic!("{other:?}"),
    }
    c.call("c1", "read_file", json!({"path": "/a"}));
    assert!(text(&c.result().await).contains("paused"));
    // A broken file keeps the rules in use (still paused), and says nothing.
    std::fs::write(&path, "paused = [").unwrap();
    run.reload.send(()).await.unwrap();
    c.quiet_for(Duration::from_millis(200)).await;
    c.call("c2", "read_file", json!({"path": "/a"}));
    assert!(text(&c.result().await).contains("paused"));
    assert_eq!(tools.count(), 0);
}

// ------------------------------------------------------- fix round 1 tests

#[test]
fn production_limits_are_pinned() {
    let t = Timing::default();
    assert_eq!(t.in_call_every, Duration::from_secs(2));
    assert_eq!(t.prune_every, Duration::from_secs(60));
    assert_eq!(t.max_call, Duration::from_secs(180));
    assert_eq!(t.max_in_flight, 16);
    assert_eq!(t.max_dialogs, 1);
    assert_eq!(t.results_cap_bytes, 16 * 1024 * 1024);
    assert_eq!(t.log_max_bytes, 10 * 1024 * 1024);
}

#[test]
fn send_budget_grows_with_the_frame() {
    let base = Duration::from_secs(10);
    assert_eq!(send_budget(base, 100), base + Duration::from_millis(1));
    // A full 4 MiB frame gets about a minute more: 64 KB/s is enough.
    assert_eq!(
        send_budget(base, MAX_FRAME_BYTES),
        base + Duration::from_millis(65_536)
    );
}

#[tokio::test(flavor = "multi_thread")]
async fn a_call_whose_id_cannot_be_recorded_never_runs() {
    let mut relay = FakeRelay::start().await;
    let dir = registered("l-norecord");
    let p = parts();
    let tools = p.tools.clone();
    let _run = start(&dir, &relay.url(), p);
    let (mut c, _) = relay.welcome().await;
    // The record cannot be appended to (a folder in its place; this fails
    // even as root, where a read-only file would not).
    let seen = dir.join("seen_calls.jsonl");
    let _ = std::fs::remove_file(&seen);
    std::fs::create_dir(&seen).unwrap();
    c.call("c1", "read_file", json!({"path": "/a"}));
    let r = c.result().await;
    assert!(r.is_error);
    assert_eq!(text(&r), NOT_RECORDED);
    c.call("c2", "start_process", json!({"command": "ls"}));
    assert_eq!(text(&c.result().await), NOT_RECORDED);
    assert_eq!(tools.count(), 0);
    let line = until_logged(&dir, "refused").await;
    assert_eq!(line["reason"], "could not record the call");
}

#[tokio::test(flavor = "multi_thread")]
async fn an_unreadable_record_is_moved_aside_and_calls_refused_for_the_window() {
    for (name, damage) in [("garbled", 0), ("unreadable", 1)] {
        let mut relay = FakeRelay::start().await;
        let dir = registered(&format!("l-blind-{name}"));
        let seen = dir.join("seen_calls.jsonl");
        if damage == 0 {
            let line = json!({"id": "c1", "t": now_unix()});
            std::fs::write(&seen, format!("{line}\n{{\"id\": \"c2\", \"t\n")).unwrap();
        } else {
            std::fs::create_dir(&seen).unwrap();
        }
        let clock = Arc::new(TestClock::default());
        let mut p = parts();
        p.clock = clock.clock();
        let tools = p.tools.clone();
        let _run = start(&dir, &relay.url(), p);
        let (mut c, _) = relay.welcome().await;
        // Moved aside, not overwritten.
        let aside: Vec<_> = std::fs::read_dir(&dir)
            .unwrap()
            .map(|e| e.unwrap().file_name().to_string_lossy().into_owned())
            .filter(|n| n.starts_with("seen_calls.jsonl.corrupt-"))
            .collect();
        assert_eq!(aside.len(), 1, "{name}: {aside:?}");
        // Every id is refused, even one that was never seen.
        for id in ["c2", "new"] {
            c.call(id, "read_file", json!({"path": "/a"}));
            let r = c.result().await;
            assert_eq!(text(&r), BLIND, "{name} {id}");
        }
        assert_eq!(tools.count(), 0);
        // Once the window from start is over, calls run again.
        clock.advance(601);
        c.call("later", "read_file", json!({"path": "/a"}));
        assert!(!c.result().await.is_error, "{name}");
        assert_eq!(tools.count(), 1);
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn the_record_is_appended_not_rewritten() {
    use std::os::unix::fs::MetadataExt;
    let mut relay = FakeRelay::start().await;
    let dir = registered("l-append");
    let _run = start(&dir, &relay.url(), parts());
    let (mut c, _) = relay.welcome().await;
    let seen = dir.join("seen_calls.jsonl");
    c.call("c1", "read_file", json!({"path": "/a"}));
    c.result().await;
    let ino = std::fs::metadata(&seen).unwrap().ino();
    for id in ["c2", "c3"] {
        c.call(id, "read_file", json!({"path": "/a"}));
        c.result().await;
    }
    assert_eq!(std::fs::metadata(&seen).unwrap().ino(), ino);
    assert_eq!(std::fs::read_to_string(&seen).unwrap().lines().count(), 3);
}

#[tokio::test(flavor = "multi_thread")]
async fn expired_ids_leave_the_record_without_new_calls() {
    let mut relay = FakeRelay::start().await;
    let dir = registered("l-prune");
    let clock = Arc::new(TestClock::default());
    let mut p = parts();
    p.clock = clock.clock();
    p.timing.prune_every = Duration::from_millis(50);
    let _run = start(&dir, &relay.url(), p);
    let (mut c, _) = relay.welcome().await;
    c.call("c1", "read_file", json!({"path": "/a"}));
    c.result().await;
    let seen = dir.join("seen_calls.jsonl");
    assert!(std::fs::read_to_string(&seen).unwrap().contains("c1"));
    clock.advance(601);
    until("the record to drop c1", || {
        !std::fs::read_to_string(&seen)
            .unwrap_or_default()
            .contains("c1")
    })
    .await;
}

#[tokio::test(flavor = "multi_thread")]
async fn a_dialog_closes_when_its_call_deadline_passes() {
    let mut relay = FakeRelay::start().await;
    let dir = registered("l-deadline");
    let mut p = parts();
    p.asker = FakeAsker::answering(None);
    let tools = p.tools.clone();
    let asker = p.asker.clone();
    let _run = start(&dir, &relay.url(), p);
    let (mut c, _) = relay.welcome().await;
    c.send(ToConnector::Call(Call {
        call_id: "c1".into(),
        tool: "start_process".into(),
        arguments: json!({"command": "ls"}),
        deadline_ms: 300,
    }));
    until("the dialog", || asker.opened.load(Ordering::SeqCst) == 1).await;
    let opened = Instant::now();
    until("the dismiss", || {
        asker.dismissed.load(Ordering::SeqCst) == 1
    })
    .await;
    assert!(
        opened.elapsed() < Duration::from_secs(2),
        "{:?}",
        opened.elapsed()
    );
    // A late Allow changes nothing.
    asker.set(Waited::Allow);
    until_logged(&dir, "timed out").await;
    c.quiet_for(Duration::from_millis(200)).await;
    assert_eq!(tools.count(), 0);
}

#[tokio::test(flavor = "multi_thread")]
async fn a_silent_relay_during_a_call_drops_the_link() {
    // Production: 3 silent 2 s intervals while a call is in flight. Here
    // 100 ms intervals; idle silence (no call) is fine.
    let mut relay = FakeRelay::start().await;
    let dir = registered("l-silent");
    let mut p = parts();
    p.asker = FakeAsker::answering(None);
    p.timing.in_call_every = Duration::from_millis(100);
    let tools = p.tools.clone();
    let asker = p.asker.clone();
    let _run = start(&dir, &relay.url(), p);
    let (mut c, _) = relay.welcome().await;
    c.quiet_for(Duration::from_millis(500)).await;
    assert!(relay.conns.try_recv().is_err(), "dropped while idle");
    c.call("c1", "start_process", json!({"command": "ls"}));
    until("the dialog", || asker.opened.load(Ordering::SeqCst) == 1).await;
    let opened = Instant::now();
    // The fake relay goes quiet, socket still open.
    until("the dismiss", || {
        asker.dismissed.load(Ordering::SeqCst) == 1
    })
    .await;
    assert!(
        opened.elapsed() < Duration::from_secs(2),
        "{:?}",
        opened.elapsed()
    );
    asker.set(Waited::Allow);
    until_logged(&dir, "link dropped at prompt").await;
    let _next = relay.next_conn().await;
    assert_eq!(tools.count(), 0);
    drop(c);
}

#[tokio::test(flavor = "multi_thread")]
async fn extreme_frame_values_never_panic() {
    let mut relay = FakeRelay::start().await;
    let dir = registered("l-extreme");
    let p = parts();
    let tools = p.tools.clone();
    let _run = start(&dir, &relay.url(), p);
    let (mut c, _) = relay.welcome().await;
    for (id, deadline_ms) in [("max", u64::MAX), ("big", u64::MAX / 2)] {
        let before = Instant::now();
        c.send(ToConnector::Call(Call {
            call_id: id.into(),
            tool: "read_file".into(),
            arguments: json!({"path": "/a"}),
            deadline_ms,
        }));
        assert_eq!(c.result().await.call_id, id);
        let d = *tools.deadlines.lock().unwrap().last().unwrap();
        assert!(
            d <= before + Duration::from_secs(181),
            "{id}: deadline past the budget"
        );
    }
    // A zero deadline: already over, so it never runs (and nothing panics).
    c.send(ToConnector::Call(Call {
        call_id: "zero".into(),
        tool: "read_file".into(),
        arguments: json!({"path": "/a"}),
        deadline_ms: 0,
    }));
    for n in [0, u64::MAX] {
        c.send(ToConnector::Ping { n });
        match c.recv_any().await {
            ToRelay::Pong { n: got } => assert_eq!(got, n),
            other => panic!("{other:?}"),
        }
        c.send(ToConnector::Pong { n });
    }
    c.send(ToConnector::Cancel {
        call_id: "never-sent".into(),
    });
    c.send(ToConnector::Welcome {
        device_id: "again".into(),
    });
    // Still the same link, still working.
    c.call("after", "read_file", json!({"path": "/a"}));
    assert!(!c.result().await.is_error);
    assert!(relay.conns.try_recv().is_err(), "the link was dropped");
}

#[tokio::test(flavor = "multi_thread")]
async fn calls_in_flight_and_dialogs_are_capped() {
    let mut relay = FakeRelay::start().await;
    let dir = registered("l-caps");
    let mut p = parts();
    p.asker = FakeAsker::answering(None);
    p.timing.max_in_flight = 3;
    let tools = p.tools.clone();
    let asker = p.asker.clone();
    let _run = start(&dir, &relay.url(), p);
    let (mut c, _) = relay.welcome().await;
    c.call("ask1", "start_process", json!({"command": "ls"}));
    until("the dialog", || asker.opened.load(Ordering::SeqCst) == 1).await;
    // A second dialog is refused at once, not stacked.
    c.call("ask2", "start_process", json!({"command": "ls"}));
    let r = c.result().await;
    assert_eq!(
        (r.call_id.as_str(), text(&r).as_str()),
        ("ask2", DIALOG_OPEN)
    );
    // In flight: the dialog plus two slow reads; the next is refused.
    c.call("r1", "read_file", json!({"path": "/a", "sleep_ms": 500}));
    c.call("r2", "read_file", json!({"path": "/b", "sleep_ms": 500}));
    c.call("r3", "read_file", json!({"path": "/c"}));
    let r = c.result().await;
    assert_eq!((r.call_id.as_str(), text(&r).as_str()), ("r3", BUSY));
    assert_eq!(asker.opened.load(Ordering::SeqCst), 1);
    // A refused id was never recorded, so it can be sent again once there
    // is room.
    for _ in 0..2 {
        assert!(!c.result().await.is_error);
    }
    c.call("r3", "read_file", json!({"path": "/c"}));
    assert!(!c.result().await.is_error);
    assert_eq!(tools.count(), 3);
    asker.set(Waited::Deny);
    assert_eq!(text(&c.result().await), DENIED);
}

#[tokio::test(flavor = "multi_thread")]
async fn kept_results_are_capped_but_an_evicted_id_still_never_reruns() {
    let mut relay = FakeRelay::start().await;
    let dir = registered("l-evict");
    let mut p = parts();
    p.timing.results_cap_bytes = 150; // about two small results
    let tools = p.tools.clone();
    let _run = start(&dir, &relay.url(), p);
    let (mut c, _) = relay.welcome().await;
    for id in ["c1", "c2", "c3"] {
        c.call(id, "read_file", json!({"path": "/a"}));
        assert!(!c.result().await.is_error);
    }
    c.call("c1", "read_file", json!({"path": "/a"}));
    let r = c.result().await;
    assert_eq!((r.call_id.as_str(), text(&r).as_str()), ("c1", EVICTED));
    // The newest is still kept whole.
    c.call("c3", "read_file", json!({"path": "/a"}));
    assert!(text(&c.result().await).contains("ran with"));
    assert_eq!(tools.count(), 3);
}

#[tokio::test(flavor = "multi_thread")]
async fn the_log_has_a_line_as_soon_as_a_call_starts() {
    let mut relay = FakeRelay::start().await;
    let dir = registered("l-startline");
    let mut p = parts();
    p.asker = FakeAsker::answering(Some(Waited::Allow));
    let _run = start(&dir, &relay.url(), p);
    let (mut c, _) = relay.welcome().await;
    let args = json!({"command": "sleep 600; rm x", "sleep_ms": 1000});
    c.call("c1", "start_process", args.clone());
    // While it is still running.
    let line = until_logged(&dir, "running").await;
    assert_eq!(line["arguments"], args);
    assert_eq!(line["approval"], "allowed");
    assert!(log_lines(&dir).iter().all(|l| l["decision"] != "ran"));
    c.result().await;
    let end = until_logged(&dir, "ran").await;
    assert!(end.get("arguments").is_none(), "{end}");
}

#[tokio::test(flavor = "multi_thread")]
async fn tools_changed_after_welcome_only_when_the_visible_tools_differ() {
    for (change, expect) in [("no_prompt", false), ("paused", true)] {
        let mut relay = FakeRelay::start().await;
        let dir = registered(&format!("l-catchup-{change}"));
        crate::rules::load(&dir).unwrap();
        let run = start(&dir, &relay.url(), parts());
        let mut c = relay.next_conn().await;
        let hello = match c.recv_any().await {
            ToRelay::Hello(h) => h,
            other => panic!("{other:?}"),
        };
        // Reloaded between the hello and the welcome.
        let path = crate::rules::rules_path(&dir);
        let rules = std::fs::read_to_string(&path).unwrap();
        let edited = match change {
            "paused" => rules.replace("paused = false", "paused = true"),
            _ => rules.replace(
                "\"list_searches\"]",
                "\"list_searches\", \"start_process\"]",
            ),
        };
        assert_ne!(edited, rules);
        std::fs::write(&path, edited).unwrap();
        run.reload.send(()).await.unwrap();
        tokio::time::sleep(Duration::from_millis(200)).await;
        c.send(ToConnector::Welcome {
            device_id: hello.device_id.clone(),
        });
        if expect {
            match c.recv().await {
                ToRelay::ToolsChanged { tools } => assert!(tools.is_empty()),
                other => panic!("{other:?}"),
            }
        } else {
            c.quiet_for(Duration::from_millis(300)).await;
        }
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn a_cancel_before_a_run_starts_stops_it() {
    let mut relay = FakeRelay::start().await;
    let dir = registered("l-cancel-early");
    let mut p = parts();
    let g = gate();
    p.hooks.before_run = Some(g.clone());
    let tools = p.tools.clone();
    let _run = start(&dir, &relay.url(), p);
    let (mut c, _) = relay.welcome().await;
    c.call("c1", "read_file", json!({"path": "/a"}));
    tokio::time::timeout(WAIT, g.reached.notified())
        .await
        .unwrap();
    c.send(ToConnector::Cancel {
        call_id: "c1".into(),
    });
    // The link loop handles the cancel; a ping round trip shows it has.
    c.send(ToConnector::Ping { n: 7 });
    while !matches!(c.recv_any().await, ToRelay::Pong { n: 7 }) {}
    g.go.notify_one();
    until_logged(&dir, "cancelled before running").await;
    c.quiet_for(Duration::from_millis(200)).await;
    assert_eq!(tools.count(), 0);
}

#[tokio::test(flavor = "multi_thread")]
async fn a_call_stopped_before_its_dialog_opens_never_shows_one() {
    let mut relay = FakeRelay::start().await;
    let dir = registered("l-noflash");
    let mut p = parts();
    let g = gate();
    p.hooks.before_ask = Some(g.clone());
    let asker = p.asker.clone();
    let tools = p.tools.clone();
    let _run = start(&dir, &relay.url(), p);
    let (mut c, _) = relay.welcome().await;
    c.call("c1", "start_process", json!({"command": "ls"}));
    tokio::time::timeout(WAIT, g.reached.notified())
        .await
        .unwrap();
    c.send(ToConnector::Cancel {
        call_id: "c1".into(),
    });
    c.send(ToConnector::Ping { n: 7 });
    while !matches!(c.recv_any().await, ToRelay::Pong { n: 7 }) {}
    g.go.notify_one();
    until_logged(&dir, "cancelled at prompt").await;
    assert_eq!(asker.opened.load(Ordering::SeqCst), 0);
    assert_eq!(tools.count(), 0);
}

#[tokio::test(flavor = "multi_thread")]
async fn a_slow_log_disk_does_not_hold_up_the_link() {
    let mut relay = FakeRelay::start().await;
    let dir = registered("l-slowlog");
    let mut p = parts();
    let hold = Arc::new(AtomicBool::new(true));
    p.hooks.hold_log = Some(hold.clone());
    let _run = start(&dir, &relay.url(), p);
    let (mut c, _) = relay.welcome().await;
    // A refused call writes its log line straight away; the disk is stuck.
    c.call("c1", "set_config_value", json!({"key": "x"}));
    assert!(c.result().await.is_error);
    c.send(ToConnector::Ping { n: 9 });
    match c.recv_any().await {
        ToRelay::Pong { n } => assert_eq!(n, 9),
        other => panic!("{other:?}"),
    }
    assert!(log_lines(&dir).is_empty());
    hold.store(false, Ordering::SeqCst);
    until_logged(&dir, "refused").await;
}

#[tokio::test(flavor = "multi_thread")]
async fn a_slow_token_fetch_keeps_status_fresh_and_stops_promptly() {
    // Each status write reads the clock once, so counting clock reads during
    // a fetch counts the writes, whatever the machine's load.
    let reads = Arc::new(AtomicUsize::new(0));
    struct Slow {
        reads: Arc<AtomicUsize>,
        during: Mutex<Vec<usize>>,
        n: AtomicUsize,
        /// Ends the long fetch, so the test's runtime is not kept waiting.
        release: AtomicBool,
    }
    impl TokenSource for Slow {
        fn token(&self) -> std::result::Result<Option<String>, TokenError> {
            let first = self.n.fetch_add(1, Ordering::SeqCst) == 0;
            let at = self.reads.load(Ordering::SeqCst);
            let end = Instant::now() + Duration::from_secs(if first { 1 } else { 60 });
            while Instant::now() < end && !(self.release.load(Ordering::SeqCst) && !first) {
                std::thread::sleep(Duration::from_millis(10));
            }
            if first {
                self.during
                    .lock()
                    .unwrap()
                    .push(self.reads.load(Ordering::SeqCst) - at);
            }
            Ok(None)
        }
    }
    let dir = registered("l-slowtoken");
    let p = parts();
    let r = reads.clone();
    let slow = Arc::new(Slow {
        reads: reads.clone(),
        during: Mutex::new(Vec::new()),
        n: AtomicUsize::new(0),
        release: AtomicBool::new(false),
    });
    let parts = Parts {
        tools: p.tools,
        asker: p.asker,
        tokens: slow.clone(),
        rng: p.rng,
        timing: p.timing,
        rules: p.rules,
        clock: Arc::new(move || {
            r.fetch_add(1, Ordering::SeqCst);
            now_unix()
        }),
        hooks: p.hooks,
    };
    let run = start(&dir, "http://127.0.0.1:1", parts);
    // The first fetch (1 s, status rewritten every 50 ms) is done, and the
    // second (60 s, cut short at the end) has begun.
    until("the second fetch", || slow.n.load(Ordering::SeqCst) == 2).await;
    let during = slow.during.lock().unwrap()[0];
    assert!(during >= 5, "{during} status writes during a 1 s fetch");
    // Told to stop mid-fetch, it stops without waiting for the fetch.
    let _ = run._shutdown.send(true);
    let t = Instant::now();
    let task = &run.task;
    until("the link to stop", || task.is_finished()).await;
    assert!(t.elapsed() < Duration::from_secs(15), "{:?}", t.elapsed());
    slow.release.store(true, Ordering::SeqCst);
}

#[tokio::test(flavor = "multi_thread")]
async fn a_revoked_sign_in_waits_for_a_new_one_without_hammering() {
    let mut relay = FakeRelay::start().await;
    let dir = registered("l-revoked");
    let mut p = parts();
    let tokens = p.tokens.clone();
    tokens.refused.store(true, Ordering::SeqCst);
    p.timing.token_poll = Duration::from_millis(100);
    let _run = start(&dir, &relay.url(), p);
    until("waiting for sign-in", || {
        link_state(&dir, now_unix()) == LinkState::WaitingForSignIn
    })
    .await;
    assert!(crate::status::waiting_reason(&dir, now_unix())
        .unwrap()
        .contains("invalid_grant"));
    // At the poll interval (100 ms), not the 1 ms backoff of a failure.
    let before = tokens.asked.load(Ordering::SeqCst);
    let t = Instant::now();
    tokio::time::sleep(Duration::from_millis(500)).await;
    let asked = tokens.asked.load(Ordering::SeqCst) - before;
    let most = t.elapsed().as_millis() as usize / 100 + 2;
    assert!(asked <= most, "asked {asked} times in {:?}", t.elapsed());
    assert!(relay.conns.try_recv().is_err());
    // Signed in again.
    tokens.refused.store(false, Ordering::SeqCst);
    let _ = relay.welcome().await;
}

#[test]
fn file_tokens_stop_asking_once_the_issuer_says_no() {
    let dir = test_dir("l-filetokens");
    save_tokens(
        &dir,
        &Tokens {
            access_token: "a".into(),
            refresh_token: Some("r1".into()),
            expires_at_unix: 1,
        },
    )
    .unwrap();
    let cfg = Config::from_lookup(|k| (k == "VRELAY_HOME").then(|| dir.display().to_string()));
    let tries = Arc::new(AtomicUsize::new(0));
    let outage = Arc::new(AtomicBool::new(false));
    let (n, o) = (tries.clone(), outage.clone());
    let ft = FileTokens::with_refresh(
        cfg,
        Box::new(move |_, t| {
            n.fetch_add(1, Ordering::SeqCst);
            if o.load(Ordering::SeqCst) {
                Err(RefreshError::Unavailable("down".into()))
            } else if t.refresh_token.as_deref() == Some("r1") {
                Err(RefreshError::Rejected("invalid_grant".into()))
            } else {
                Ok("fresh".into())
            }
        }),
    );
    for _ in 0..3 {
        assert!(matches!(ft.token(), Err(TokenError::SignInAgain(_))));
    }
    assert_eq!(tries.load(Ordering::SeqCst), 1, "asked the issuer again");
    // `vrelay login` writes a new token.json: asked again, and it works.
    save_tokens(
        &dir,
        &Tokens {
            access_token: "a".into(),
            refresh_token: Some("r2".into()),
            expires_at_unix: 1,
        },
    )
    .unwrap();
    assert_eq!(ft.token(), Ok(Some("fresh".into())));
    // An outage is never parked: each try goes to the issuer.
    outage.store(true, Ordering::SeqCst);
    for _ in 0..2 {
        assert!(matches!(ft.token(), Err(TokenError::Unavailable(_))));
    }
    assert_eq!(tries.load(Ordering::SeqCst), 4);
    // No token.json: not signed in.
    std::fs::remove_file(dir.join("token.json")).unwrap();
    assert_eq!(ft.token(), Ok(None));
}

#[tokio::test(flavor = "multi_thread")]
async fn the_calls_log_rotates_and_every_file_is_0600() {
    let mut relay = FakeRelay::start().await;
    let dir = registered("l-rotate");
    let mut p = parts();
    p.timing.log_max_bytes = 600;
    let _run = start(&dir, &relay.url(), p);
    let (mut c, _) = relay.welcome().await;
    for i in 0..12 {
        c.call(&format!("c{i}"), "read_file", json!({"path": "/a"}));
        c.result().await;
    }
    // The last line written is c11's end; after it the writer is idle.
    let logs = dir.join("logs");
    until("the last line", || {
        log_lines(&dir)
            .last()
            .is_some_and(|l| l["call_id"] == "c11" && l["decision"] == "ran")
    })
    .await;
    assert!(logs.join("calls.log.1").exists());
    let mut names: Vec<_> = std::fs::read_dir(&logs)
        .unwrap()
        .map(|e| e.unwrap().file_name().to_string_lossy().into_owned())
        .collect();
    names.sort();
    assert_eq!(names, ["calls.log", "calls.log.1"]);
    for n in &names {
        let m = std::fs::metadata(logs.join(n)).unwrap();
        assert_eq!(m.permissions().mode() & 0o777, 0o600, "{n}");
        assert!(m.len() <= 600, "{n} is {} bytes", m.len());
    }
}

// ------------------------------------------------------- fix round 2 tests

#[tokio::test(flavor = "multi_thread")]
async fn cancelling_a_running_call_does_not_trip_the_silence_check() {
    // The relay stops its 2 s pings once it has no call pending: here a
    // cancelled call keeps running and another has been answered.
    let mut relay = FakeRelay::start().await;
    let dir = registered("l-silence-cancel");
    let mut p = parts();
    p.timing.in_call_every = Duration::from_millis(100);
    let tools = p.tools.clone();
    let _run = start(&dir, &relay.url(), p);
    let (mut c, _) = relay.welcome().await;
    c.call("slow", "read_file", json!({"path": "/a", "sleep_ms": 1500}));
    until("the slow call to start", || tools.count() == 1).await;
    c.send(ToConnector::Cancel {
        call_id: "slow".into(),
    });
    c.call("fast", "read_file", json!({"path": "/b"}));
    assert_eq!(c.result().await.call_id, "fast");
    // Silent for 8 intervals: the link stays up.
    c.quiet_for(Duration::from_millis(800)).await;
    assert!(relay.conns.try_recv().is_err(), "the link was dropped");
}

#[tokio::test(flavor = "multi_thread")]
async fn a_restart_inside_the_refusal_window_still_refuses() {
    let dir = registered("l-blind-restart");
    let line = json!({"id": "c1", "t": now_unix()});
    std::fs::write(dir.join("seen_calls.jsonl"), format!("not json\n{line}\n")).unwrap();
    let clock = Arc::new(TestClock::default());
    let run_once = |clock: &Arc<TestClock>| {
        let mut p = parts();
        p.clock = clock.clock();
        p
    };
    let mut relay = FakeRelay::start().await;
    let first = start(&dir, &relay.url(), run_once(&clock));
    let (mut c, _) = relay.welcome().await;
    c.call("c1", "read_file", json!({"path": "/a"}));
    assert_eq!(text(&c.result().await), BLIND);
    // vrelay restarts a minute later: still inside the window.
    drop(first);
    drop(c);
    clock.advance(60);
    let mut relay = FakeRelay::start().await;
    let second = start(&dir, &relay.url(), run_once(&clock));
    let (mut c, _) = relay.welcome().await;
    c.call("c1", "read_file", json!({"path": "/a"}));
    assert_eq!(text(&c.result().await), BLIND);
    // Restarted again after the window: calls run.
    drop(second);
    drop(c);
    clock.advance(541);
    let mut relay = FakeRelay::start().await;
    let p = run_once(&clock);
    let tools = p.tools.clone();
    let _third = start(&dir, &relay.url(), p);
    let (mut c, _) = relay.welcome().await;
    c.call("c1", "read_file", json!({"path": "/a"}));
    assert!(!c.result().await.is_error);
    assert_eq!(tools.count(), 1);
}

#[tokio::test(flavor = "multi_thread")]
async fn the_running_line_is_on_disk_before_the_tool_starts() {
    let mut relay = FakeRelay::start().await;
    let dir = registered("l-durable-line");
    let mut p = parts();
    let hold = Arc::new(AtomicBool::new(true));
    p.hooks.hold_log = Some(hold.clone());
    *p.tools.log_path.lock().unwrap() = Some(dir.join("logs").join("calls.log"));
    let tools = p.tools.clone();
    let _run = start(&dir, &relay.url(), p);
    let (mut c, _) = relay.welcome().await;
    c.call("c1", "read_file", json!({"path": "/a"}));
    // While the log cannot be written, the tool does not start.
    tokio::time::sleep(Duration::from_millis(300)).await;
    assert_eq!(tools.count(), 0);
    hold.store(false, Ordering::SeqCst);
    assert!(!c.result().await.is_error);
    assert_eq!(*tools.logged_first.lock().unwrap(), [true]);

    // A log that cannot be written at all: the call is refused, not run.
    let mut relay = FakeRelay::start().await;
    let dir = registered("l-nolog");
    std::fs::write(dir.join("logs"), b"not a folder").unwrap();
    let p = parts();
    let tools = p.tools.clone();
    let _run = start(&dir, &relay.url(), p);
    let (mut c, _) = relay.welcome().await;
    c.call("c1", "read_file", json!({"path": "/a"}));
    assert_eq!(text(&c.result().await), NOT_LOGGED);
    assert_eq!(tools.count(), 0);
}

#[tokio::test(flavor = "multi_thread")]
async fn a_call_past_its_deadline_never_reaches_the_tools() {
    let mut relay = FakeRelay::start().await;
    let dir = registered("l-late");
    let mut p = parts();
    let g = gate();
    p.hooks.before_run = Some(g.clone());
    let tools = p.tools.clone();
    let _run = start(&dir, &relay.url(), p);
    let (mut c, _) = relay.welcome().await;
    let call = |id: &str, tool: &str, deadline_ms| {
        ToConnector::Call(Call {
            call_id: id.into(),
            tool: tool.into(),
            arguments: json!({"path": "/a", "command": "ls"}),
            deadline_ms,
        })
    };
    // No prompt: its deadline passes while its id is being recorded.
    c.send(call("late", "read_file", 200));
    tokio::time::timeout(WAIT, g.reached.notified())
        .await
        .unwrap();
    tokio::time::sleep(Duration::from_millis(300)).await;
    g.go.notify_one();
    until_logged(&dir, "timed out").await;
    // Allowed, but already past its deadline.
    c.send(call("allowed", "start_process", 0));
    let end = Instant::now() + WAIT;
    while log_lines(&dir)
        .iter()
        .filter(|l| l["decision"] == "timed out")
        .count()
        < 2
    {
        assert!(Instant::now() < end, "no second `timed out`");
        tokio::time::sleep(Duration::from_millis(5)).await;
    }
    c.quiet_for(Duration::from_millis(200)).await;
    assert_eq!(tools.count(), 0);
}

#[tokio::test(flavor = "multi_thread")]
async fn the_record_is_tidied_again_once_the_refusal_window_ends() {
    let mut relay = FakeRelay::start().await;
    let dir = registered("l-blind-compact");
    std::fs::write(dir.join("seen_calls.jsonl"), "garbage\n{}\n").unwrap();
    let clock = Arc::new(TestClock::default());
    let mut p = parts();
    p.clock = clock.clock();
    p.timing.prune_every = Duration::from_millis(50);
    let _run = start(&dir, &relay.url(), p);
    let (mut c, _) = relay.welcome().await;
    clock.advance(601);
    c.call("c1", "read_file", json!({"path": "/a"}));
    assert!(!c.result().await.is_error);
    let seen = dir.join("seen_calls.jsonl");
    assert!(std::fs::read_to_string(&seen).unwrap().contains("c1"));
    clock.advance(601);
    until("c1 to leave the record", || {
        !std::fs::read_to_string(&seen)
            .unwrap_or_default()
            .contains("c1")
    })
    .await;
}

#[tokio::test(flavor = "multi_thread")]
async fn a_torn_last_line_is_dropped_but_any_other_bad_line_refuses() {
    let line = json!({"id": "c1", "t": now_unix()});
    // A power cut mid-append: the last line has no newline.
    let mut relay = FakeRelay::start().await;
    let dir = registered("l-torn");
    std::fs::write(
        dir.join("seen_calls.jsonl"),
        format!("{line}\n{{\"id\":\"c2\",\"t"),
    )
    .unwrap();
    let p = parts();
    let tools = p.tools.clone();
    let _run = start(&dir, &relay.url(), p);
    let (mut c, _) = relay.welcome().await;
    c.call("new", "read_file", json!({"path": "/a"}));
    assert!(!c.result().await.is_error);
    c.call("c1", "read_file", json!({"path": "/a"}));
    assert_eq!(text(&c.result().await), ALREADY_STARTED);
    assert_eq!(tools.count(), 1);
    assert!(open_window(&dir, now_unix(), Duration::from_secs(600)).is_none());

    // A bad line anywhere else, even with a good last line: refused.
    for body in [
        format!("{{\"id\":\"c2\",\"t\n{line}\n"),
        format!("{line}\nnot json\n{line}"),
    ] {
        let mut relay = FakeRelay::start().await;
        let dir = registered("l-torn-mid");
        std::fs::write(dir.join("seen_calls.jsonl"), body).unwrap();
        let _run = start(&dir, &relay.url(), parts());
        let (mut c, _) = relay.welcome().await;
        c.call("new", "read_file", json!({"path": "/a"}));
        assert_eq!(text(&c.result().await), BLIND);
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn a_refused_id_is_not_recorded_as_started() {
    let dir = registered("l-refused-norecord");
    // An id about to expire, so the prune timer rewrites the record below.
    let old = json!({"id": "old", "t": now_unix() - 590});
    std::fs::write(dir.join("seen_calls.jsonl"), format!("{old}\n")).unwrap();
    let clock = Arc::new(TestClock::default());
    let mut p = parts();
    p.clock = clock.clock();
    p.timing.prune_every = Duration::from_millis(50);
    let mut relay = FakeRelay::start().await;
    let first = start(&dir, &relay.url(), p);
    let (mut c, _) = relay.welcome().await;
    c.call("r1", "set_config_value", json!({"key": "x"}));
    let refused = text(&c.result().await);
    assert!(refused.contains("not available remotely"), "{refused}");
    c.call("ok", "read_file", json!({"path": "/a"}));
    c.result().await;
    // "old" expires; the record is rewritten from memory.
    clock.advance(20);
    let seen = dir.join("seen_calls.jsonl");
    until("the rewrite", || {
        !std::fs::read_to_string(&seen)
            .unwrap_or_default()
            .contains("old")
    })
    .await;
    let kept = std::fs::read_to_string(&seen).unwrap();
    assert!(kept.contains("\"ok\"") && !kept.contains("r1"), "{kept}");
    drop(first);
    drop(c);
    let mut p = parts();
    p.clock = clock.clock();
    let mut relay = FakeRelay::start().await;
    let _second = start(&dir, &relay.url(), p);
    let (mut c, _) = relay.welcome().await;
    c.call("r1", "set_config_value", json!({"key": "x"}));
    assert_eq!(text(&c.result().await), refused);
}
