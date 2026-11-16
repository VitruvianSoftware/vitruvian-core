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

//! `vrelay run`: the WebSocket link from this Mac to the relay.
//!
//! One loop owns the socket. It reads frames, answers pings, pings the relay
//! every 20 s and writes `status.json`; it never waits on a call. Each call
//! runs in its own task (the "ask first" dialog on a blocking thread), so
//! pongs keep flowing while a dialog is open.
//!
//! What must never happen, and what stops it:
//! - **A call runs twice.** Ids are remembered for 10 minutes in memory, and
//!   in `seen_calls.jsonl` across a restart of vrelay.
//! - **A call runs after a cancel or a dropped link.** A call waiting at its
//!   dialog has its state changed under the same lock that the dialog's
//!   answer is checked under, so a late "Allow" finds it stopped.
//! - **A tool outside `no_prompt` runs without Allow.** `Rules::decide`
//!   picks; only `Run` skips the dialog.

use std::collections::HashMap;
use std::future::Future;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use futures_util::stream::SplitSink;
use futures_util::{SinkExt, StreamExt};
use ring::signature::Ed25519KeyPair;
use serde_json::{json, Value};
use tokio::net::TcpStream;
use tokio::sync::{mpsc, watch};
use tokio_tungstenite::tungstenite::client::IntoClientRequest;
use tokio_tungstenite::tungstenite::http::HeaderValue;
use tokio_tungstenite::tungstenite::protocol::WebSocketConfig;
use tokio_tungstenite::tungstenite::Message;
use tokio_tungstenite::{Connector, MaybeTlsStream, WebSocketStream};
use vitruvian_relay_protocol::{
    decode_to_connector, encode, Call, CallResult, Hello, ToConnector, ToRelay, ToolDef,
    MAX_FRAME_BYTES, MAX_MISSED_PINGS, PING_SECS, PROTOCOL,
};

use crate::auth::fresh_token;
use crate::bridge::{Bridge, BridgeOutput, Log, CALL_ID_RESERVE};
use crate::config::{client_config, Config};
use crate::keys::sign_hello;
use crate::prompt::{summarize, Waited};
use crate::rules::{self, Decision, Rules};
use crate::state::{ensure_dir, load_device, load_tokens, status_path, write_private};
use crate::Result;

pub const DENIED: &str = "Denied on the computer.";
pub const ALREADY_STARTED: &str =
    "This call already started before vrelay restarted; not run again.";
const TIMED_OUT: &str = "No answer on the computer in time; not run.";
const CANCELLED: &str = "Cancelled before it was allowed; not run.";
const DROPPED: &str =
    "The link to the relay dropped while this call waited for an answer; not run.";
const STOPPING: &str = "vrelay stopped while this call waited for an answer; not run.";
const ID_TOO_LONG: &str = "Refused on the computer: the call id is longer than 256 bytes; not run.";
const TOO_BIG: &str = "The result could not be sent: it does not fit in one frame.";

/// The local record of every call (spec §7.3), in the log directory.
pub const CALLS_LOG: &str = "calls.log";
/// Ids of calls started in the last 10 minutes, in the state directory.
pub const SEEN_CALLS: &str = "seen_calls.jsonl";
/// The longest wait between reconnect attempts, in backoff units (seconds).
pub const MAX_BACKOFF: u64 = 60;

/// How often things happen. Production uses [`Timing::default`]; tests
/// shrink it so the same code runs in milliseconds.
#[derive(Debug, Clone)]
pub struct Timing {
    /// Ping the relay this often.
    pub ping_every: Duration,
    /// This many of our pings unanswered in a row ends the link.
    pub max_missed: u32,
    /// Rewrite `status.json` at least this often.
    pub status_every: Duration,
    /// With no token yet, look for one this often.
    pub token_poll: Duration,
    /// Connected this long, the backoff starts again from 1 s.
    pub reset_after: Duration,
    /// Remember call ids this long.
    pub dedupe_window: Duration,
    /// One second of backoff.
    pub backoff_unit: Duration,
    pub connect_timeout: Duration,
    pub send_timeout: Duration,
    /// The relay's `welcome` must arrive within this of our `hello`.
    pub welcome_timeout: Duration,
    /// The longest an "ask first" dialog stays open.
    pub max_prompt: Duration,
}

impl Default for Timing {
    fn default() -> Timing {
        Timing {
            ping_every: Duration::from_secs(PING_SECS),
            max_missed: MAX_MISSED_PINGS,
            status_every: Duration::from_secs(20),
            token_poll: Duration::from_secs(10),
            reset_after: Duration::from_secs(60),
            dedupe_window: Duration::from_secs(600),
            backoff_unit: Duration::from_secs(1),
            connect_timeout: Duration::from_secs(30),
            send_timeout: Duration::from_secs(10),
            welcome_timeout: Duration::from_secs(20),
            max_prompt: crate::prompt::DEFAULT_TIMEOUT,
        }
    }
}

/// Seconds since the epoch.
pub type Clock = Arc<dyn Fn() -> u64 + Send + Sync>;
/// Given `cap`, a number in `0..=cap`.
pub type Rng = Arc<Mutex<dyn FnMut(u64) -> u64 + Send>>;

/// Reconnect delay for attempt `n` (from 0), in seconds: full jitter up to
/// `min(60, 2^n)`, never under 1. So the first retry is 1 s, none is 0 s,
/// and none is over 60 s.
pub fn backoff_secs(n: u32, rng: &mut dyn FnMut(u64) -> u64) -> u64 {
    let cap = if n >= 6 {
        MAX_BACKOFF
    } else {
        (1u64 << n).min(MAX_BACKOFF)
    };
    rng(cap).min(cap).max(1)
}

/// The production random source: `0..=cap` from the system's random source
/// (the longest wait if that fails).
pub fn system_rng(cap: u64) -> u64 {
    use ring::rand::SecureRandom;
    let mut b = [0u8; 8];
    match ring::rand::SystemRandom::new().fill(&mut b) {
        Ok(()) => u64::from_le_bytes(b) % (cap + 1),
        Err(_) => cap,
    }
}

/// `https://relay` → `wss://relay/connect` (`http` → `ws` for local tests).
pub fn connect_url(relay: &str) -> Result<String> {
    let relay = relay.trim_end_matches('/');
    if let Some(rest) = relay.strip_prefix("https://") {
        Ok(format!("wss://{rest}/connect"))
    } else if let Some(rest) = relay.strip_prefix("http://") {
        Ok(format!("ws://{rest}/connect"))
    } else {
        Err(format!("the relay URL {relay} must start with https://"))
    }
}

/// The tool side: `desktop-commander` through the bridge (fakes in tests).
pub trait Tools: Send + Sync + 'static {
    /// Every tool, unfiltered.
    fn list(&self) -> impl Future<Output = Vec<ToolDef>> + Send;
    fn call(
        &self,
        tool: &str,
        args: Value,
        deadline: Instant,
    ) -> impl Future<Output = BridgeOutput> + Send;
}

impl Tools for Bridge {
    fn list(&self) -> impl Future<Output = Vec<ToolDef>> + Send {
        self.tools()
    }

    fn call(
        &self,
        tool: &str,
        args: Value,
        deadline: Instant,
    ) -> impl Future<Output = BridgeOutput> + Send {
        Bridge::call(self, tool, args, deadline)
    }
}

/// The "ask first" dialog. Blocking: it runs on its own thread.
pub trait Asker: Send + Sync + 'static {
    /// Returns as soon as `dismiss` is set, closing the dialog.
    fn ask(&self, tool: &str, summary: &str, timeout: Duration, dismiss: &AtomicBool) -> Waited;
}

/// The real dialog (`osascript`).
pub struct Dialog;

impl Asker for Dialog {
    fn ask(&self, tool: &str, summary: &str, timeout: Duration, dismiss: &AtomicBool) -> Waited {
        crate::prompt::ask(tool, summary, timeout).wait_or_dismiss(dismiss)
    }
}

/// Where the access token comes from. Blocking (a refresh is an HTTPS call).
pub trait TokenSource: Send + Sync + 'static {
    /// `Ok(None)`: nobody has signed in yet.
    fn token(&self) -> Result<Option<String>>;
}

/// `token.json`, refreshed (and saved) when it is close to expiry.
pub struct FileTokens(pub Config);

impl TokenSource for FileTokens {
    fn token(&self) -> Result<Option<String>> {
        match load_tokens(&self.0.dir)? {
            None => Ok(None),
            Some(mut t) => fresh_token(&self.0, &mut t).map(Some),
        }
    }
}

/// Everything `vrelay run` needs.
pub struct Link<T, A, K> {
    /// The state directory (`device.json`, `status.json`, `seen_calls.jsonl`).
    pub dir: PathBuf,
    /// Where `calls.log` goes.
    pub log_dir: PathBuf,
    pub relay_url: String,
    pub tools: Arc<T>,
    pub asker: Arc<A>,
    pub tokens: Arc<K>,
    /// As loaded at start; `SIGHUP` reloads them.
    pub rules: Rules,
    pub key: Arc<Ed25519KeyPair>,
    pub timing: Timing,
    pub clock: Clock,
    pub rng: Rng,
    pub log: Log,
    /// For `wss://`. `None`: config.rs's shared client config.
    pub tls: Option<Arc<rustls::ClientConfig>>,
}

// ------------------------------------------------------------------- calls

/// Why a call waiting at its dialog will not run.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Stop {
    Cancelled,
    LinkDropped,
    Shutdown,
}

enum Phase {
    /// The dialog is open.
    Prompting {
        dismiss: Arc<AtomicBool>,
        stop: Option<Stop>,
    },
    /// In `desktop-commander`. A cancel only drops the result (P1 does not
    /// stop the command).
    Running { cancelled: bool },
    /// The result, kept to answer a repeat of the id.
    Done(CallResult),
}

struct Entry {
    at: Instant,
    /// The connection it came on.
    conn: u64,
    phase: Phase,
}

#[derive(Default)]
struct Calls {
    live: HashMap<String, Entry>,
    /// From `seen_calls.jsonl` at start: started by an earlier vrelay.
    before_restart: HashMap<String, u64>,
    /// What `seen_calls.jsonl` holds: (id, unix time started).
    seen: Vec<(String, u64)>,
}

impl Calls {
    fn prune(&mut self, now: Instant, now_unix: u64, window: Duration) {
        self.live.retain(|_, e| {
            !matches!(e.phase, Phase::Done(_)) || now.duration_since(e.at) <= window
        });
        let w = window.as_secs();
        self.seen.retain(|(_, t)| now_unix.saturating_sub(*t) <= w);
        self.before_restart
            .retain(|_, t| now_unix.saturating_sub(*t) <= w);
    }

    fn seen_body(&self) -> String {
        self.seen
            .iter()
            .map(|(id, t)| format!("{}\n", json!({"id": id, "t": t})))
            .collect()
    }
}

fn read_seen(path: &Path, now_unix: u64, window: Duration) -> Vec<(String, u64)> {
    let text = std::fs::read_to_string(path).unwrap_or_default();
    text.lines()
        .filter_map(|l| serde_json::from_str::<Value>(l).ok())
        .filter_map(|v| Some((v.get("id")?.as_str()?.to_string(), v.get("t")?.as_u64()?)))
        .filter(|(_, t)| now_unix.saturating_sub(*t) <= window.as_secs())
        .collect()
}

fn error_result(call_id: &str, text: &str) -> CallResult {
    CallResult {
        call_id: call_id.to_string(),
        content: json!([{"type": "text", "text": text}]),
        is_error: true,
        truncated: false,
    }
}

type Out = mpsc::UnboundedSender<ToRelay>;

/// What the link loop and the call tasks share.
struct Shared<T, A> {
    tools: Arc<T>,
    asker: Arc<A>,
    rules: Mutex<Rules>,
    calls: Mutex<Calls>,
    dir: PathBuf,
    log_dir: PathBuf,
    timing: Timing,
    clock: Clock,
    log: Log,
    /// Serialises writes to `calls.log`.
    log_lock: Mutex<()>,
    /// Serialises writes to `seen_calls.jsonl`.
    seen_lock: Mutex<()>,
    /// The connection that is up, for `tools_changed` after a reload.
    current: Mutex<Option<(u64, Out)>>,
    /// Bumped by every reload that loaded, so a connection whose `hello`
    /// was built before one (and welcomed after) can catch up.
    rules_gen: std::sync::atomic::AtomicU64,
}

impl<T: Tools, A: Asker> Shared<T, A> {
    fn log_call(&self, call_id: &str, tool: &str, args: &Value, decision: &str, extra: Value) {
        let mut line = json!({
            "t": (self.clock)(),
            "call_id": call_id,
            "tool": tool,
            "arguments": args,
            "decision": decision,
        });
        if let (Some(l), Value::Object(e)) = (line.as_object_mut(), extra) {
            l.extend(e);
        }
        let _guard = self.log_lock.lock().unwrap();
        if let Err(e) = append_private(&self.log_dir, CALLS_LOG, &line.to_string()) {
            (self.log)(&format!("could not write the calls log: {e}"));
        }
    }

    fn save_seen(&self, calls: &Calls) {
        let path = self.dir.join(SEEN_CALLS);
        if let Err(e) = write_private(&path, calls.seen_body().as_bytes()) {
            (self.log)(&format!("could not record started calls: {e}"));
        }
    }

    /// Writes `seen_calls.jsonl` off the link loop (it syncs to disk).
    /// Writers take turns, and each writes the list as it is then, so the
    /// last one to finish holds every id.
    async fn persist_seen(self: &Arc<Self>) {
        let me = self.clone();
        let _ = tokio::task::spawn_blocking(move || {
            let _turn = me.seen_lock.lock().unwrap();
            let body = me.calls.lock().unwrap().seen_body();
            if let Err(e) = write_private(&me.dir.join(SEEN_CALLS), body.as_bytes()) {
                (me.log)(&format!("could not record started calls: {e}"));
            }
        })
        .await;
    }

    /// A `call` frame. Decides at once; the dialog and the tool run in tasks.
    fn on_call(self: &Arc<Self>, call: Call, conn: u64, out: &Out) {
        let Call {
            call_id,
            tool,
            arguments,
            deadline_ms,
        } = call;
        let received = Instant::now();
        let deadline = received + Duration::from_millis(deadline_ms);
        if call_id.len() > CALL_ID_RESERVE {
            let shown: String = call_id.chars().take(64).collect();
            self.log_call(
                &shown,
                &tool,
                &arguments,
                "refused",
                json!({"reason": "call id over 256 bytes", "call_id_bytes": call_id.len()}),
            );
            let _ = out.send(ToRelay::Result(error_result(&call_id, ID_TOO_LONG)));
            return;
        }
        let now_unix = (self.clock)();
        let mut calls = self.calls.lock().unwrap();
        calls.prune(received, now_unix, self.timing.dedupe_window);
        if let Some(e) = calls.live.get(&call_id) {
            // A repeat: the stored result again, or nothing while it runs.
            if let Phase::Done(r) = &e.phase {
                let _ = out.send(ToRelay::Result(r.clone()));
            }
            return;
        }
        if calls.before_restart.contains_key(&call_id) {
            let r = error_result(&call_id, ALREADY_STARTED);
            calls.live.insert(
                call_id.clone(),
                Entry {
                    at: received,
                    conn,
                    phase: Phase::Done(r.clone()),
                },
            );
            drop(calls);
            self.log_call(
                &call_id,
                &tool,
                &arguments,
                "refused",
                json!({"reason": "already started before vrelay restarted"}),
            );
            let _ = out.send(ToRelay::Result(r));
            return;
        }
        // Recorded, and on disk before anything can run (below).
        calls.seen.push((call_id.clone(), now_unix));
        let decision = self.rules.lock().unwrap().decide(&tool, &arguments);
        let phase = match &decision {
            Decision::Refuse(why) => Phase::Done(error_result(
                &call_id,
                &format!("Refused on the computer: {why}."),
            )),
            Decision::Run => Phase::Running { cancelled: false },
            Decision::AskFirst => Phase::Prompting {
                dismiss: Arc::new(AtomicBool::new(false)),
                stop: None,
            },
        };
        let dismiss = match &phase {
            Phase::Prompting { dismiss, .. } => Some(dismiss.clone()),
            _ => None,
        };
        let refused = match &phase {
            Phase::Done(r) => Some(r.clone()),
            _ => None,
        };
        calls.live.insert(
            call_id.clone(),
            Entry {
                at: received,
                conn,
                phase,
            },
        );
        drop(calls);
        match decision {
            Decision::Refuse(why) => {
                self.log_call(
                    &call_id,
                    &tool,
                    &arguments,
                    "refused",
                    json!({"reason": why}),
                );
                if let Some(r) = refused {
                    let _ = out.send(ToRelay::Result(r));
                }
                let me = self.clone();
                tokio::spawn(async move { me.persist_seen().await });
            }
            Decision::Run => {
                let me = self.clone();
                let out = out.clone();
                tokio::spawn(async move {
                    me.persist_seen().await;
                    me.run_tool(call_id, tool, arguments, deadline, out).await;
                });
            }
            Decision::AskFirst => {
                let me = self.clone();
                let out = out.clone();
                let dismiss = dismiss.expect("set for AskFirst");
                tokio::spawn(async move {
                    me.persist_seen().await;
                    me.ask_then_run(call_id, tool, arguments, deadline, dismiss, out)
                        .await;
                });
            }
        }
    }

    async fn ask_then_run(
        self: Arc<Self>,
        call_id: String,
        tool: String,
        args: Value,
        deadline: Instant,
        dismiss: Arc<AtomicBool>,
        out: Out,
    ) {
        let summary = summarize(&tool, &args);
        let timeout = self
            .timing
            .max_prompt
            .min(deadline.saturating_duration_since(Instant::now()));
        let asker = self.asker.clone();
        let t = tool.clone();
        let waited =
            tokio::task::spawn_blocking(move || asker.ask(&t, &summary, timeout, &dismiss))
                .await
                .unwrap_or(Waited::Deny);
        // The answer is checked, and the call moved on, under the lock that a
        // cancel or a link drop takes: a late Allow finds it stopped.
        let refusal = {
            let mut calls = self.calls.lock().unwrap();
            let Some(entry) = calls.live.get_mut(&call_id) else {
                return;
            };
            let stop = match &entry.phase {
                Phase::Prompting { stop, .. } => *stop,
                _ => return,
            };
            let refusal = match (stop, waited) {
                (Some(Stop::Cancelled), _) => Some(("cancelled at prompt", CANCELLED, false)),
                (Some(Stop::LinkDropped), _) => Some(("link dropped at prompt", DROPPED, false)),
                (Some(Stop::Shutdown), _) => Some(("link dropped at prompt", STOPPING, false)),
                (None, Waited::Allow) if Instant::now() < deadline => None,
                (None, Waited::Allow) | (None, Waited::TimedOut) => {
                    Some(("timed out", TIMED_OUT, true))
                }
                (None, Waited::Deny) | (None, Waited::Dismissed) => Some(("denied", DENIED, true)),
            };
            entry.phase = match refusal {
                None => Phase::Running { cancelled: false },
                Some((_, text, _)) => Phase::Done(error_result(&call_id, text)),
            };
            refusal
        };
        match refusal {
            None => self.run_tool(call_id, tool, args, deadline, out).await,
            Some((decision, text, send)) => {
                self.log_call(&call_id, &tool, &args, decision, json!({}));
                // After a cancel or a drop the relay has already failed the
                // call: nothing to send.
                if send {
                    let _ = out.send(ToRelay::Result(error_result(&call_id, text)));
                }
            }
        }
    }

    async fn run_tool(
        self: Arc<Self>,
        call_id: String,
        tool: String,
        args: Value,
        deadline: Instant,
        out: Out,
    ) {
        let started = Instant::now();
        let output = self.tools.call(&tool, args.clone(), deadline).await;
        let r = CallResult {
            call_id: call_id.clone(),
            content: output.content,
            is_error: output.is_error,
            truncated: output.truncated,
        };
        let cancelled = {
            let mut calls = self.calls.lock().unwrap();
            match calls.live.get_mut(&call_id) {
                Some(e) => {
                    let c = matches!(e.phase, Phase::Running { cancelled: true });
                    e.phase = Phase::Done(r.clone());
                    c
                }
                None => false,
            }
        };
        self.log_call(
            &call_id,
            &tool,
            &args,
            "ran",
            json!({
                "is_error": r.is_error,
                "truncated": r.truncated,
                "ms": started.elapsed().as_millis() as u64,
                "result_dropped": cancelled,
            }),
        );
        if !cancelled && out.send(ToRelay::Result(r)).is_err() {
            (self.log)(&format!(
                "call {call_id}: the link dropped before its result could be sent"
            ));
        }
    }

    fn on_cancel(&self, call_id: &str) {
        let mut calls = self.calls.lock().unwrap();
        let Some(e) = calls.live.get_mut(call_id) else {
            return;
        };
        match &mut e.phase {
            Phase::Prompting { dismiss, stop } if stop.is_none() => {
                *stop = Some(Stop::Cancelled);
                dismiss.store(true, Ordering::SeqCst);
            }
            Phase::Running { cancelled } => {
                *cancelled = true;
                (self.log)(&format!(
                    "call {call_id} was cancelled while running: its result will be dropped \
                     (the command itself is not stopped)"
                ));
            }
            _ => {}
        }
    }

    /// Closes every open dialog (of one connection, or all) and marks those
    /// calls stopped, so a later Allow cannot run them.
    fn stop_prompts(&self, conn: Option<u64>, why: Stop) {
        let mut calls = self.calls.lock().unwrap();
        for e in calls.live.values_mut() {
            if conn.is_some_and(|c| c != e.conn) {
                continue;
            }
            if let Phase::Prompting { dismiss, stop } = &mut e.phase {
                if stop.is_none() {
                    *stop = Some(why);
                    dismiss.store(true, Ordering::SeqCst);
                }
            }
        }
    }

    /// `SIGHUP`: re-read the rules. A file that does not load keeps the
    /// rules in use.
    async fn reload(&self) {
        let tools = self.tools.list().await;
        let current = self.rules.lock().unwrap().clone();
        match rules::reload(&self.dir, &current, &tools) {
            Err(e) => (self.log)(&format!("rules not reloaded, keeping the ones in use: {e}")),
            Ok(r) => {
                let visible = r.rules.visible(&tools);
                *self.rules.lock().unwrap() = r.rules;
                self.rules_gen.fetch_add(1, Ordering::SeqCst);
                (self.log)("rules reloaded");
                if r.visible_changed {
                    if let Some((_, out)) = self.current.lock().unwrap().as_ref() {
                        let _ = out.send(ToRelay::ToolsChanged { tools: visible });
                    }
                }
            }
        }
    }
}

/// Appends one line to a user-only file, created at mode 0600 (never wider
/// first), in a 0700 directory.
fn append_private(dir: &Path, name: &str, line: &str) -> Result<()> {
    use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
    ensure_dir(dir)?;
    let path = dir.join(name);
    let mut f = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .mode(0o600)
        .open(&path)
        .map_err(|e| format!("open {}: {e}", path.display()))?;
    let mode = f
        .metadata()
        .map_err(|e| format!("{}: {e}", path.display()))?
        .permissions()
        .mode();
    if mode & 0o077 != 0 {
        f.set_permissions(std::fs::Permissions::from_mode(0o600))
            .map_err(|e| format!("make {} private: {e}", path.display()))?;
    }
    f.write_all(format!("{line}\n").as_bytes())
        .map_err(|e| format!("write {}: {e}", path.display()))
}

// ------------------------------------------------------------------ status

/// `status.json`, in the format `vrelay status` reads (status.rs). Written
/// by a task of its own ([`status_writer`]), so a slow disk never holds up
/// the link loop; the newest state always wins.
struct Status {
    tx: watch::Sender<Option<String>>,
    clock: Clock,
    state: &'static str,
    last_pong: Option<u64>,
    next_retry: Option<u64>,
}

impl Status {
    fn set(&mut self, state: &'static str, next_retry: Option<u64>) {
        self.state = state;
        self.next_retry = next_retry;
        self.write();
    }

    fn write(&self) {
        let body = json!({
            "state": self.state,
            "updated_unix": (self.clock)(),
            "last_pong_unix": self.last_pong,
            "next_retry_unix": self.next_retry,
        });
        let _ = self.tx.send(Some(body.to_string()));
    }
}

async fn status_writer(dir: PathBuf, log: Log, mut rx: watch::Receiver<Option<String>>) {
    while rx.changed().await.is_ok() {
        let Some(body) = rx.borrow_and_update().clone() else {
            continue;
        };
        let (dir, log) = (dir.clone(), log.clone());
        let _ = tokio::task::spawn_blocking(move || {
            if let Err(e) = write_private(&status_path(&dir), body.as_bytes()) {
                log(&format!("could not write the status file: {e}"));
            }
        })
        .await;
    }
}

// -------------------------------------------------------------------- link

type Ws = WebSocketStream<MaybeTlsStream<TcpStream>>;
type Sink = SplitSink<Ws, Message>;

/// Resolves once `stop` says so; never if its sender is gone.
async fn stopped(stop: &mut watch::Receiver<bool>) {
    loop {
        if *stop.borrow_and_update() {
            return;
        }
        if stop.changed().await.is_err() {
            std::future::pending::<()>().await;
        }
    }
}

async fn send(
    sink: &mut Sink,
    frame: &ToRelay,
    timeout: Duration,
) -> std::result::Result<(), String> {
    let text = match (encode(frame), frame) {
        (Ok(t), _) => t,
        (Err(_), ToRelay::Result(r)) => encode(&ToRelay::Result(error_result(&r.call_id, TOO_BIG)))
            .map_err(|e| e.to_string())?,
        (Err(e), _) => return Err(e.to_string()),
    };
    match tokio::time::timeout(timeout, sink.send(Message::Text(text))).await {
        Ok(Ok(())) => Ok(()),
        Ok(Err(e)) => Err(format!("send failed: {e}")),
        Err(_) => Err("send timed out".into()),
    }
}

/// Our pings: three unanswered in a row and the link is dead. Any frame from
/// the relay counts as an answer.
#[derive(Default)]
struct Beat {
    n: u64,
    awaiting: bool,
    missed: u32,
}

impl Beat {
    fn heard(&mut self) {
        self.awaiting = false;
        self.missed = 0;
    }
}

impl<T: Tools, A: Asker, K: TokenSource> Link<T, A, K> {
    /// Runs until `shutdown` turns true. Never gives up on the relay.
    pub async fn run(self, mut reload: mpsc::Receiver<()>, mut shutdown: watch::Receiver<bool>) {
        let now_unix = (self.clock)();
        let seen = read_seen(
            &self.dir.join(SEEN_CALLS),
            now_unix,
            self.timing.dedupe_window,
        );
        let calls = Calls {
            live: HashMap::new(),
            before_restart: seen.iter().cloned().collect(),
            seen,
        };
        let shared = Arc::new(Shared {
            tools: self.tools.clone(),
            asker: self.asker.clone(),
            rules: Mutex::new(self.rules.clone()),
            calls: Mutex::new(calls),
            dir: self.dir.clone(),
            log_dir: self.log_dir.clone(),
            timing: self.timing.clone(),
            clock: self.clock.clone(),
            log: self.log.clone(),
            log_lock: Mutex::new(()),
            seen_lock: Mutex::new(()),
            current: Mutex::new(None),
            rules_gen: std::sync::atomic::AtomicU64::new(0),
        });
        // Expired ids leave the file now.
        shared.save_seen(&shared.calls.lock().unwrap());
        let r = shared.clone();
        let reloader = tokio::spawn(async move {
            while reload.recv().await.is_some() {
                r.reload().await;
            }
        });
        let (status_tx, status_rx) = watch::channel(None);
        let writer = tokio::spawn(status_writer(self.dir.clone(), self.log.clone(), status_rx));
        let mut status = Status {
            tx: status_tx,
            clock: self.clock.clone(),
            state: "connecting",
            last_pong: None,
            next_retry: None,
        };
        let mut attempt: u32 = 0;
        let mut conn: u64 = 0;
        loop {
            if *shutdown.borrow() {
                break;
            }
            let tokens = self.tokens.clone();
            let token = tokio::task::spawn_blocking(move || tokens.token())
                .await
                .unwrap_or_else(|e| Err(format!("the token check failed: {e}")));
            let (token, device) = match (token, load_device(&self.dir)) {
                (Ok(Some(t)), Some(d)) => (t, d),
                (Ok(_), _) => {
                    status.set("waiting_for_sign_in", None);
                    if self
                        .pause(self.timing.token_poll, &status, &mut shutdown)
                        .await
                    {
                        break;
                    }
                    continue;
                }
                (Err(e), _) => {
                    (self.log)(&format!("no usable token: {e}"));
                    if self.backoff(&mut attempt, &mut status, &mut shutdown).await {
                        break;
                    }
                    continue;
                }
            };
            status.last_pong = None;
            status.set("connecting", None);
            conn += 1;
            let up = match self.connect(&token).await {
                Err(e) => {
                    (self.log)(&format!("could not reach the relay: {e}"));
                    None
                }
                Ok(ws) => {
                    let gen = shared.rules_gen.load(Ordering::SeqCst);
                    let hello = self.hello(&shared, &device.device_id, &token).await;
                    let (up, shut) =
                        session(&shared, ws, conn, hello, gen, &mut status, &mut shutdown).await;
                    if shut {
                        break;
                    }
                    up
                }
            };
            if up.is_some_and(|d| d >= self.timing.reset_after) {
                attempt = 0;
            }
            if self.backoff(&mut attempt, &mut status, &mut shutdown).await {
                break;
            }
        }
        shared.stop_prompts(None, Stop::Shutdown);
        reloader.abort();
        // So `vrelay status` says stopped at once, not after a minute: after
        // the last pending write.
        drop(status);
        let _ = writer.await;
        let _ = std::fs::remove_file(status_path(&self.dir));
    }

    /// Waits `d`, keeping the status file fresh. True if told to stop.
    async fn pause(
        &self,
        d: Duration,
        status: &Status,
        shutdown: &mut watch::Receiver<bool>,
    ) -> bool {
        let end = tokio::time::Instant::now() + d;
        loop {
            let now = tokio::time::Instant::now();
            if now >= end {
                return false;
            }
            let step = (end - now).min(self.timing.status_every);
            tokio::select! {
                _ = tokio::time::sleep(step) => status.write(),
                _ = stopped(shutdown) => return true,
            }
        }
    }

    async fn backoff(
        &self,
        attempt: &mut u32,
        status: &mut Status,
        shutdown: &mut watch::Receiver<bool>,
    ) -> bool {
        let secs = {
            let mut rng = self.rng.lock().unwrap();
            backoff_secs(*attempt, &mut *rng)
        };
        *attempt = attempt.saturating_add(1);
        let wait = self.timing.backoff_unit * secs as u32;
        let ceil = wait.as_secs() + u64::from(wait.subsec_nanos() > 0);
        status.last_pong = None;
        status.set("connecting", Some((self.clock)() + ceil));
        (self.log)(&format!("reconnecting in {wait:?}"));
        self.pause(wait, status, shutdown).await
    }

    async fn connect(&self, token: &str) -> std::result::Result<Ws, String> {
        let url = connect_url(&self.relay_url)?;
        let mut req = url
            .as_str()
            .into_client_request()
            .map_err(|e| format!("{url}: {e}"))?;
        let bearer = HeaderValue::from_str(&format!("Bearer {token}"))
            .map_err(|_| "the token is not a valid header value".to_string())?;
        req.headers_mut().insert("authorization", bearer);
        let connector = if url.starts_with("wss://") {
            Connector::Rustls(self.tls.clone().unwrap_or_else(client_config))
        } else {
            Connector::Plain
        };
        let config = WebSocketConfig {
            max_message_size: Some(MAX_FRAME_BYTES),
            max_frame_size: Some(MAX_FRAME_BYTES),
            ..Default::default()
        };
        let dial = tokio_tungstenite::connect_async_tls_with_config(
            req,
            Some(config),
            true,
            Some(connector),
        );
        match tokio::time::timeout(self.timing.connect_timeout, dial).await {
            Err(_) => Err("timed out".into()),
            Ok(Err(tokio_tungstenite::tungstenite::Error::Http(resp))) => Err(format!(
                "the relay refused the link (HTTP {})",
                resp.status()
            )),
            Ok(Err(e)) => Err(e.to_string()),
            Ok(Ok((ws, _))) => Ok(ws),
        }
    }

    async fn hello(&self, shared: &Shared<T, A>, device_id: &str, token: &str) -> Hello {
        let all = self.tools.list().await;
        let tools = shared.rules.lock().unwrap().visible(&all);
        let ts = (self.clock)();
        Hello {
            device_id: device_id.to_string(),
            connector_version: env!("CARGO_PKG_VERSION").to_string(),
            protocol: PROTOCOL,
            ts,
            sig: sign_hello(&self.key, device_id, ts, token),
            tools,
        }
    }
}

/// One connection, from `hello` to the drop. Returns how long it was up
/// after `welcome` (if it got that far) and whether vrelay is stopping.
async fn session<T: Tools, A: Asker>(
    shared: &Arc<Shared<T, A>>,
    ws: Ws,
    conn: u64,
    hello: Hello,
    rules_gen: u64,
    status: &mut Status,
    shutdown: &mut watch::Receiver<bool>,
) -> (Option<Duration>, bool) {
    let t = shared.timing.clone();
    let log = shared.log.clone();
    let clock = shared.clock.clone();
    let (mut sink, mut stream) = ws.split();
    if let Err(e) = send(&mut sink, &ToRelay::Hello(hello), t.send_timeout).await {
        log(&format!("link down: {e}"));
        return (None, false);
    }
    let (out, mut out_rx) = mpsc::unbounded_channel::<ToRelay>();
    let mut welcomed: Option<Instant> = None;
    let welcome_by = tokio::time::sleep(t.welcome_timeout);
    tokio::pin!(welcome_by);
    let start = tokio::time::Instant::now();
    let mut pings = tokio::time::interval_at(start + t.ping_every, t.ping_every);
    pings.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
    let mut refresh = tokio::time::interval_at(start + t.status_every, t.status_every);
    refresh.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
    let mut beat = Beat::default();
    let mut shut = false;
    let why: String = loop {
        tokio::select! {
            _ = &mut welcome_by, if welcomed.is_none() => break "no welcome from the relay".into(),
            _ = stopped(shutdown) => {
                shut = true;
                break "vrelay is stopping".into();
            }
            _ = pings.tick() => {
                if beat.awaiting {
                    beat.missed += 1;
                    if beat.missed >= t.max_missed {
                        break format!("{} pings unanswered", beat.missed);
                    }
                }
                beat.n += 1;
                beat.awaiting = true;
                if let Err(e) = send(&mut sink, &ToRelay::Ping { n: beat.n }, t.send_timeout).await {
                    break e;
                }
            }
            _ = refresh.tick() => status.write(),
            Some(f) = out_rx.recv() => {
                if let Err(e) = send(&mut sink, &f, t.send_timeout).await {
                    break e;
                }
            }
            msg = stream.next() => {
                let text = match msg {
                    None => break "the relay closed the link".into(),
                    Some(Err(e)) => break format!("read failed: {e}"),
                    Some(Ok(Message::Text(text))) => text,
                    Some(Ok(Message::Close(c))) => {
                        break match c {
                            Some(c) => format!("the relay closed the link ({}: {})", u16::from(c.code), c.reason),
                            None => "the relay closed the link".into(),
                        };
                    }
                    Some(Ok(_)) => {
                        beat.heard();
                        continue;
                    }
                };
                beat.heard();
                match decode_to_connector(&text) {
                    // Size only: a bad frame may hold arguments.
                    Err(_) => log(&format!("ignored a bad frame ({} bytes)", text.len())),
                    Ok(ToConnector::Welcome { .. }) => {
                        if welcomed.is_none() {
                            welcomed = Some(Instant::now());
                            status.last_pong = Some(clock());
                            status.set("connected", None);
                            *shared.current.lock().unwrap() = Some((conn, out.clone()));
                            log("connected to the relay");
                            // Rules reloaded after the hello was built: send
                            // the tools they show now.
                            if shared.rules_gen.load(Ordering::SeqCst) != rules_gen {
                                let s = shared.clone();
                                let out = out.clone();
                                tokio::spawn(async move {
                                    let all = s.tools.list().await;
                                    let tools = s.rules.lock().unwrap().visible(&all);
                                    let _ = out.send(ToRelay::ToolsChanged { tools });
                                });
                            }
                        }
                    }
                    Ok(ToConnector::Reject { reason }) => {
                        break format!("the relay refused the link: {reason}");
                    }
                    Ok(ToConnector::Ping { n }) => {
                        if let Err(e) = send(&mut sink, &ToRelay::Pong { n }, t.send_timeout).await {
                            break e;
                        }
                    }
                    Ok(ToConnector::Pong { .. }) => {
                        status.last_pong = Some(clock());
                        status.write();
                    }
                    Ok(ToConnector::Call(c)) => {
                        if welcomed.is_some() {
                            shared.on_call(c, conn, &out);
                        } else {
                            log("ignored a call that came before welcome");
                        }
                    }
                    Ok(ToConnector::Cancel { call_id }) => shared.on_cancel(&call_id),
                }
            }
        }
    };
    {
        let mut cur = shared.current.lock().unwrap();
        if cur.as_ref().is_some_and(|(c, _)| *c == conn) {
            *cur = None;
        }
    }
    shared.stop_prompts(Some(conn), Stop::LinkDropped);
    log(&format!("link down: {why}"));
    let _ = tokio::time::timeout(Duration::from_secs(1), sink.close()).await;
    (welcomed.map(|w| w.elapsed()), shut)
}

#[cfg(test)]
#[path = "link_tests.rs"]
mod tests;
