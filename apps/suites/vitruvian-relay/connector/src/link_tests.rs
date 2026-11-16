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
use std::sync::atomic::AtomicUsize;
use tokio::net::TcpListener;
use tokio::sync::mpsc::{unbounded_channel, UnboundedReceiver, UnboundedSender};
use tokio_tungstenite::tungstenite::handshake::server::{Request, Response};
use tokio_tungstenite::tungstenite::Message;
use vitruvian_relay_protocol::{
    decode_to_relay, encode, hello_message, Call, ToConnector, ToRelay,
};

const WAIT: Duration = Duration::from_secs(5);

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
        _deadline: Instant,
    ) -> impl Future<Output = BridgeOutput> + Send {
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

/// Hands out `tok-1`, `tok-2`, ... (or nothing, while `none` is set).
#[derive(Default)]
struct FakeTokens {
    n: AtomicUsize,
    none: AtomicBool,
}

impl TokenSource for FakeTokens {
    fn token(&self) -> Result<Option<String>> {
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
}

fn parts() -> Parts<FakeAsker, FakeTokens> {
    Parts {
        tools: FakeTools::with(&["read_file", "start_process", "set_config_value"]),
        asker: FakeAsker::answering(Some(Waited::Allow)),
        tokens: Arc::new(FakeTokens::default()),
        rng: Arc::new(Mutex::new(|cap: u64| cap)),
        timing: fast(),
        rules: toml::from_str(crate::rules::DEFAULT_RULES).unwrap(),
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
        clock: Arc::new(now_unix),
        rng: p.rng,
        log: Arc::new(|s: &str| eprintln!("link: {s}")),
        tls: None,
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
    // Up long enough: the count starts again.
    let (c, _) = relay.welcome().await;
    tokio::time::sleep(Duration::from_millis(200)).await;
    drop(c);
    // Then two quick drops in a row: the cap doubles each time.
    for _ in 0..2 {
        drop(relay.next_conn().await);
    }
    let _c = relay.next_conn().await;
    assert_eq!(*caps.lock().unwrap(), [1, 2, 4]);
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
        tokens: Arc::new(FileTokens(cfg)),
        rng: p.rng,
        timing: p.timing,
        rules: p.rules,
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
    let line = until_logged(&dir, "ran").await;
    assert_eq!(line["call_id"], "c1");
    assert_eq!(line["tool"], "read_file");
    assert_eq!(line["arguments"], args);
    assert!(line["t"].as_u64().is_some());
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
