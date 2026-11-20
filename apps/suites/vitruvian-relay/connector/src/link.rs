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
//! every 20 s and asks for `status.json` to be rewritten; it never waits on
//! a call or on the disk. Each call runs in its own task (the "ask first"
//! dialog on a blocking thread), `status.json` and `calls.log` have writers
//! of their own, so pongs keep flowing while a dialog is open.
//!
//! What must never happen, and what stops it:
//! - **A call runs twice.** Ids are remembered for 10 minutes in memory, and
//!   in `seen_calls.jsonl` across a restart of vrelay. The id must be on
//!   disk (appended and synced) before the call can run; if that fails, the
//!   call is refused. A record that cannot be read at start is moved aside
//!   and every call is refused until its 10 minutes are over.
//! - **A call runs after a cancel, a dropped link or its deadline.** A call
//!   waiting at its dialog has its state changed under the same lock that
//!   the dialog's answer is checked under, so a late "Allow" finds it
//!   stopped. While a call is in flight the relay pings every 2 s; three
//!   silent intervals count as a drop, as they do on the relay's side. Any
//!   bytes from the relay count as life, even part of a large frame still
//!   arriving, and time this loop spends sending is not silence: it cannot
//!   read meanwhile.
//! - **A tool outside `no_prompt` runs without Allow.** `Rules::decide`
//!   picks; only `Run` skips the dialog.
//! - **A flood of calls.** At most 16 calls in flight and one dialog on
//!   screen; past that a call is refused at once. Results kept for repeats
//!   are capped by size; an evicted one is still never run again.

use std::collections::{HashMap, VecDeque};
use std::future::Future;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
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
    CALL_BUDGET_SECS, IN_CALL_PING_SECS, MAX_FRAME_BYTES, MAX_MISSED_PINGS, PING_SECS, PROTOCOL,
};

use crate::auth::{fresh_token_checked_from, RefreshError};
use crate::bridge::{Bridge, BridgeOutput, Log, CALL_ID_RESERVE};
use crate::config::{client_config, Config};
use crate::keys::sign_hello;
use crate::prompt::{summarize, Waited};
use crate::rules::{self, Decision, Rules};
use crate::state::{
    device_path, ensure_dir, load_device, parse_tokens, status_path, sync_dir, token_path,
    write_private, Tokens,
};

pub const DENIED: &str = "Denied on the computer.";
/// A pause landed (`vrelay pause`) while the call waited or before it started.
pub const PAUSED: &str = "Paused on the computer.";
pub const ALREADY_STARTED: &str =
    "This call already started before vrelay restarted; not run again.";
pub const NOT_RECORDED: &str = "vrelay could not record this call; not run.";
pub const NOT_LOGGED: &str = "vrelay could not write this call to its log; not run.";
pub const BLIND: &str = "vrelay could not read its record of started calls, so it runs no \
                         calls for 10 minutes after starting; not run.";
pub const BUSY: &str = "Too many calls are running on the computer; not run.";
pub const DIALOG_OPEN: &str = "Another call is waiting for an answer on the computer; not run.";
pub const EVICTED: &str =
    "This call already ran; its result is no longer kept, and it is not run again.";
const TIMED_OUT: &str = "No answer on the computer in time; not run.";
const CANCELLED: &str = "Cancelled before it was allowed; not run.";
const CANCELLED_EARLY: &str = "Cancelled before it started; not run.";
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
/// Rewrite `seen_calls.jsonl` without its expired ids after this many appends.
const COMPACT_EVERY: usize = 256;
/// Sending a frame may take `send_timeout` plus this long per byte (a floor
/// of 64 KB/s), so a 4 MiB result on a slow uplink is not cut off at 10 s.
const SEND_BYTES_PER_MS: usize = 64;

/// How often things happen, and the limits. Production uses
/// [`Timing::default`]; tests shrink it so the same code runs in
/// milliseconds.
#[derive(Debug, Clone)]
pub struct Timing {
    /// Ping the relay this often.
    pub ping_every: Duration,
    /// This many of our pings unanswered in a row ends the link; also this
    /// many silent `in_call_every` intervals while a call is in flight.
    pub max_missed: u32,
    /// The relay's ping interval while a call is in flight.
    pub in_call_every: Duration,
    /// Rewrite `status.json` at least this often.
    pub status_every: Duration,
    /// With no usable sign-in, look at `token.json` again this often.
    pub token_poll: Duration,
    /// Connected this long, the backoff starts again from 1 s.
    pub reset_after: Duration,
    /// Remember call ids this long.
    pub dedupe_window: Duration,
    /// Drop expired ids and results this often, calls or not.
    pub prune_every: Duration,
    /// One second of backoff.
    pub backoff_unit: Duration,
    pub connect_timeout: Duration,
    /// For a small frame; big ones get more (see `send_budget`).
    pub send_timeout: Duration,
    /// The relay's `welcome` must arrive within this of our `hello`.
    pub welcome_timeout: Duration,
    /// The longest an "ask first" dialog stays open.
    pub max_prompt: Duration,
    /// The longest a call may take, whatever its `deadline_ms` says.
    pub max_call: Duration,
    /// Calls waiting at a dialog or running, across connections.
    pub max_in_flight: usize,
    /// Dialogs on screen at once.
    pub max_dialogs: usize,
    /// Total size of the results kept for repeated ids.
    pub results_cap_bytes: usize,
    /// `calls.log` is rotated to `calls.log.1` past this size.
    pub log_max_bytes: u64,
    /// How long a call waits for its `running` line to be on disk.
    pub log_wait: Duration,
}

impl Default for Timing {
    fn default() -> Timing {
        Timing {
            ping_every: Duration::from_secs(PING_SECS),
            max_missed: MAX_MISSED_PINGS,
            in_call_every: Duration::from_secs(IN_CALL_PING_SECS),
            status_every: Duration::from_secs(20),
            token_poll: Duration::from_secs(10),
            reset_after: Duration::from_secs(60),
            dedupe_window: Duration::from_secs(600),
            prune_every: Duration::from_secs(60),
            backoff_unit: Duration::from_secs(1),
            connect_timeout: Duration::from_secs(30),
            send_timeout: Duration::from_secs(10),
            welcome_timeout: Duration::from_secs(20),
            max_prompt: crate::prompt::DEFAULT_TIMEOUT,
            max_call: Duration::from_secs(CALL_BUDGET_SECS),
            // desktop-commander serves calls over one stdio pipe, and an AI
            // app runs a handful at once; 16 is room to spare while keeping
            // well clear of tokio's 512 blocking threads.
            max_in_flight: 16,
            // One person answers one dialog at a time; stacked dialogs invite
            // an Allow meant for another.
            max_dialogs: 1,
            results_cap_bytes: 16 * 1024 * 1024,
            log_max_bytes: 10 * 1024 * 1024,
            log_wait: Duration::from_secs(10),
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

/// How long sending a frame of `bytes` may take.
pub fn send_budget(base: Duration, bytes: usize) -> Duration {
    base + Duration::from_millis((bytes / SEND_BYTES_PER_MS) as u64)
}

/// `https://relay` → `wss://relay/connect`. Plain `http` (→ `ws`, the token in
/// clear text) only for this machine itself, which is what the tests use.
pub fn connect_url(relay: &str) -> std::result::Result<String, String> {
    let relay = relay.trim_end_matches('/');
    if let Some(rest) = relay.strip_prefix("https://") {
        return Ok(format!("wss://{rest}/connect"));
    }
    if let Some(rest) = relay.strip_prefix("http://") {
        let authority = rest.split('/').next().unwrap_or("");
        let host = match authority.strip_prefix('[') {
            Some(v6) => v6.split(']').next().unwrap_or(""),
            None => authority.split(':').next().unwrap_or(""),
        };
        if matches!(host, "127.0.0.1" | "localhost" | "::1") {
            return Ok(format!("ws://{rest}/connect"));
        }
    }
    Err(format!(
        "the relay URL {relay} must start with https:// (http:// only for this machine)"
    ))
}

/// Asked at the last moment before a call is sent to the tool: is it still
/// wanted? (Not cancelled, the link not dropped, the deadline not passed.)
pub type StillWanted = Arc<dyn Fn() -> bool + Send + Sync>;

/// The tool side: `desktop-commander` through the bridge (fakes in tests).
pub trait Tools: Send + Sync + 'static {
    /// Every tool, unfiltered.
    fn list(&self) -> impl Future<Output = Vec<ToolDef>> + Send;
    /// Runs `tool`, but only if `wanted` still says yes once the tool side
    /// is ready to take it (after a restart of desktop-commander, say):
    /// `None` means it was not sent.
    fn call(
        &self,
        tool: &str,
        args: Value,
        deadline: Instant,
        wanted: StillWanted,
    ) -> impl Future<Output = Option<BridgeOutput>> + Send;
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
        wanted: StillWanted,
    ) -> impl Future<Output = Option<BridgeOutput>> + Send {
        Bridge::call_if(self, tool, args, deadline, move || wanted())
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

/// Why there is no token.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TokenError {
    /// Only `vrelay login` helps (a revoked or missing refresh token, a
    /// broken `token.json`). The link waits for `token.json` to change.
    SignInAgain(String),
    /// The issuer is out of reach; try again with the backoff.
    Unavailable(String),
}

/// Where the access token comes from. Blocking (a refresh is an HTTPS call).
pub trait TokenSource: Send + Sync + 'static {
    /// `Ok(None)`: nobody has signed in yet.
    fn token(&self) -> std::result::Result<Option<String>, TokenError>;
    /// Whether a sign-in is still there. Checked while connected, so that
    /// `vrelay logout` takes the link down instead of leaving it up until
    /// the relay closes it at the token's expiry. Cheap; never a refresh.
    fn signed_in(&self) -> bool {
        true
    }
}

/// Refreshes the tokens read from the given `token.json` bytes.
type Refresh =
    dyn Fn(&Config, &mut Tokens, &[u8]) -> std::result::Result<String, RefreshError> + Send + Sync;

/// `token.json`, refreshed (and saved) when it is close to expiry. Once the
/// issuer has said no, the same `token.json` is never sent to it again: the
/// answer stays "sign in again" until the file changes.
pub struct FileTokens {
    cfg: Config,
    refresh: Box<Refresh>,
    /// The `token.json` bytes that were refused, and why.
    parked: Mutex<Option<(Vec<u8>, String)>>,
}

impl FileTokens {
    pub fn new(cfg: Config) -> FileTokens {
        FileTokens::with_refresh(
            cfg,
            Box::new(|cfg, t, before| fresh_token_checked_from(cfg, t, Some(before))),
        )
    }

    pub fn with_refresh(cfg: Config, refresh: Box<Refresh>) -> FileTokens {
        FileTokens {
            cfg,
            refresh,
            parked: Mutex::new(None),
        }
    }
}

impl TokenSource for FileTokens {
    fn token(&self) -> std::result::Result<Option<String>, TokenError> {
        let bytes = match std::fs::read(token_path(&self.cfg.dir)) {
            Ok(b) => b,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
                *self.parked.lock().unwrap() = None;
                return Ok(None);
            }
            Err(e) => return Err(TokenError::Unavailable(format!("read token.json: {e}"))),
        };
        if let Some((b, why)) = self.parked.lock().unwrap().as_ref() {
            if *b == bytes {
                return Err(TokenError::SignInAgain(why.clone()));
            }
        }
        let park = |why: String| {
            *self.parked.lock().unwrap() = Some((bytes.clone(), why.clone()));
            Err(TokenError::SignInAgain(why))
        };
        // From the bytes just read, so the refresh can save over exactly
        // those and nothing newer.
        let mut t = match parse_tokens(&self.cfg.dir, &bytes) {
            Ok(t) => t,
            Err(e) => return park(format!("{} ({e})", crate::auth::SIGN_IN_AGAIN)),
        };
        match (self.refresh)(&self.cfg, &mut t, &bytes) {
            Ok(token) => {
                *self.parked.lock().unwrap() = None;
                Ok(Some(token))
            }
            Err(e @ RefreshError::Rejected(_)) => park(e.to_string()),
            Err(e @ RefreshError::Unavailable(_)) => Err(TokenError::Unavailable(e.to_string())),
        }
    }

    /// `token.json` is there (`vrelay logout` removes it).
    fn signed_in(&self) -> bool {
        token_path(&self.cfg.dir).exists()
    }
}

/// Test-only pauses at points a race could otherwise only hit by luck.
#[cfg(test)]
#[derive(Default, Clone)]
pub(crate) struct Hooks {
    /// After a call's id is on disk, before it runs (no dialog).
    pub before_run: Option<Gate>,
    /// After a call's id is on disk, before its dialog opens.
    pub before_ask: Option<Gate>,
    /// While set, the calls-log writer waits before each line.
    pub hold_log: Option<Arc<AtomicBool>>,
    /// The link loop, about to send the pong for a ping numbered below the
    /// first: it waits here as it would in a slow send (it reads nothing
    /// meanwhile).
    pub hold_pong: Option<(u64, Gate)>,
    /// Before a call's id is appended to `seen_calls.jsonl`.
    pub before_record: Option<Gate>,
    /// While set, appending an id fails (a full or broken disk).
    pub fail_record: Option<Arc<AtomicBool>>,
}

/// `reached` is notified when the task gets there; it then waits for `go`.
#[cfg(test)]
#[derive(Clone)]
pub(crate) struct Gate {
    pub reached: Arc<tokio::sync::Notify>,
    pub go: Arc<tokio::sync::Notify>,
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
    #[cfg(test)]
    pub(crate) hooks: Hooks,
}

// --------------------------------------------------------------- calls log

enum LogMsg {
    Line(String),
    /// Written and synced to disk before the answer is sent.
    Synced(
        String,
        std::sync::mpsc::Sender<std::result::Result<(), String>>,
    ),
    Flush(std::sync::mpsc::Sender<()>),
}

/// `calls.log`, written in order by a thread of its own so a slow disk
/// never holds up the link loop.
#[derive(Clone)]
struct CallLog {
    tx: std::sync::mpsc::Sender<LogMsg>,
}

impl CallLog {
    fn start(
        dir: PathBuf,
        max_bytes: u64,
        log: Log,
        #[cfg(test)] hold: Option<Arc<AtomicBool>>,
    ) -> CallLog {
        let (tx, rx) = std::sync::mpsc::channel::<LogMsg>();
        std::thread::spawn(move || {
            for msg in rx {
                match msg {
                    LogMsg::Line(line) => {
                        #[cfg(test)]
                        while hold.as_ref().is_some_and(|h| h.load(Ordering::SeqCst)) {
                            std::thread::sleep(Duration::from_millis(5));
                        }
                        if let Err(e) = append_log_line(&dir, max_bytes, &line, false) {
                            log(&format!("could not write the calls log: {e}"));
                        }
                    }
                    LogMsg::Synced(line, done) => {
                        #[cfg(test)]
                        while hold.as_ref().is_some_and(|h| h.load(Ordering::SeqCst)) {
                            std::thread::sleep(Duration::from_millis(5));
                        }
                        let r = append_log_line(&dir, max_bytes, &line, true);
                        if let Err(e) = &r {
                            log(&format!("could not write the calls log: {e}"));
                        }
                        let _ = done.send(r);
                    }
                    LogMsg::Flush(done) => {
                        let _ = done.send(());
                    }
                }
            }
        });
        CallLog { tx }
    }

    fn line(&self, v: Value) {
        let _ = self.tx.send(LogMsg::Line(v.to_string()));
    }

    /// Writes `v` (after every line sent before it) and syncs the file.
    /// Blocking; waits at most `limit`.
    fn line_synced(&self, v: Value, limit: Duration) -> std::result::Result<(), String> {
        let (tx, rx) = std::sync::mpsc::channel();
        self.tx
            .send(LogMsg::Synced(v.to_string(), tx))
            .map_err(|_| "the calls log writer has stopped".to_string())?;
        rx.recv_timeout(limit)
            .map_err(|_| format!("the calls log was not written within {limit:?}"))?
    }

    /// Waits (at most `limit`) until every line sent so far is written.
    fn flush(&self, limit: Duration) {
        let (tx, rx) = std::sync::mpsc::channel();
        if self.tx.send(LogMsg::Flush(tx)).is_ok() {
            let _ = rx.recv_timeout(limit);
        }
    }
}

/// Opens `path` for appending; a new file is created at mode 0600 (never
/// wider first, and its folder synced), an old one is tightened to 0600.
fn open_private_append(path: &Path) -> std::result::Result<std::fs::File, String> {
    use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
    let existed = path.exists();
    let f = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .mode(0o600)
        .open(path)
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
    if !existed {
        sync_dir(path);
    }
    Ok(f)
}

/// One line to `calls.log`, rotating it to `calls.log.1` (replacing an older
/// one) first if the line would take it past `max_bytes`.
fn append_log_line(
    dir: &Path,
    max_bytes: u64,
    line: &str,
    sync: bool,
) -> std::result::Result<(), String> {
    ensure_dir(dir)?;
    let path = dir.join(CALLS_LOG);
    let size = std::fs::metadata(&path).map(|m| m.len()).unwrap_or(0);
    if size > 0 && size + line.len() as u64 + 1 > max_bytes {
        let old = dir.join(format!("{CALLS_LOG}.1"));
        std::fs::rename(&path, &old).map_err(|e| format!("rotate {}: {e}", path.display()))?;
    }
    let mut f = open_private_append(&path)?;
    f.write_all(format!("{line}\n").as_bytes())
        .and_then(|_| if sync { f.sync_data() } else { Ok(()) })
        .map_err(|e| format!("write {}: {e}", path.display()))
}

/// What happens to a call once its dialog has ended: `None` runs it, else
/// (log decision, result text, whether to send that result). `in_time`: the
/// call's deadline has not passed. Past it the relay has failed the call, or
/// will within the transit margin it subtracted from `deadline_ms` (about
/// 6 s), and answers with its own deadline error, so nothing is sent: a
/// dialog that answers in the same instant the deadline fires must not
/// depend on which of the two won.
fn prompt_refusal(
    stop: Option<Stop>,
    waited: Waited,
    in_time: bool,
) -> Option<(&'static str, &'static str, bool)> {
    match (stop, waited) {
        (Some(Stop::Cancelled), _) => Some(("cancelled at prompt", CANCELLED, false)),
        (Some(Stop::LinkDropped), _) => Some(("link dropped at prompt", DROPPED, false)),
        (Some(Stop::Shutdown), _) => Some(("link dropped at prompt", STOPPING, false)),
        (Some(Stop::Expired), _) => Some(("timed out", TIMED_OUT, false)),
        // The relay still waits on it: say why.
        (Some(Stop::Paused), _) => Some(("paused at prompt", PAUSED, true)),
        (None, Waited::Allow) if in_time => None,
        // The dialog's own limit can end before the call's deadline: the
        // relay still waits then, so it is told.
        (None, Waited::Allow) | (None, Waited::TimedOut) => Some(("timed out", TIMED_OUT, in_time)),
        (None, Waited::Deny) | (None, Waited::Dismissed) => Some(("denied", DENIED, in_time)),
    }
}

// ------------------------------------------------------------------- calls

/// Why a call waiting at its dialog will not run.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Stop {
    Cancelled,
    LinkDropped,
    Shutdown,
    /// Its deadline passed: the relay has given up on it.
    Expired,
    /// `vrelay pause` (the rules now say paused).
    Paused,
}

enum Phase {
    /// The dialog is (about to be) open.
    Prompting {
        dismiss: Arc<AtomicBool>,
        stop: Option<Stop>,
    },
    /// In `desktop-commander` (or about to be). A cancel or a pause before
    /// it starts stops it; after, a cancel only drops the result and a pause
    /// lets it finish (P1 does not stop the command). `started` turns true
    /// at the last check before the tool is sent the call.
    Running { cancelled: bool, started: bool },
    /// The result, kept to answer a repeat of the id.
    Done(CallResult),
    /// Done, but its result was dropped to save memory. A repeat gets
    /// [`EVICTED`].
    Evicted,
}

struct Entry {
    at: Instant,
    /// The call's deadline (clamped to the call budget).
    deadline: Instant,
    /// The connection it came on.
    conn: u64,
    phase: Phase,
}

#[derive(Default)]
struct Calls {
    live: HashMap<String, Entry>,
    /// From `seen_calls.jsonl` at start: started by an earlier vrelay.
    before_restart: HashMap<String, u64>,
    /// What `seen_calls.jsonl` should hold: (id, unix time started).
    seen: Vec<(String, u64)>,
    /// Appends since `seen_calls.jsonl` was last rewritten.
    appended: usize,
    /// The record could not be read at start: refuse every call until then.
    blind_until: Option<u64>,
    /// Ids of `Done` entries, oldest first, and the bytes their results hold.
    done_order: VecDeque<String>,
    stored_bytes: usize,
}

fn result_bytes(r: &CallResult) -> usize {
    serde_json::to_string(&r.content)
        .map(|s| s.len())
        .unwrap_or(0)
        + r.call_id.len()
}

impl Calls {
    /// Forgets results and ids older than the window. True if `seen` shrank.
    fn prune(&mut self, now: Instant, now_unix: u64, window: Duration) -> bool {
        let mut freed = 0;
        self.live.retain(|_, e| {
            let keep = !matches!(e.phase, Phase::Done(_) | Phase::Evicted)
                || now.saturating_duration_since(e.at) <= window;
            if !keep {
                if let Phase::Done(r) = &e.phase {
                    freed += result_bytes(r);
                }
            }
            keep
        });
        self.stored_bytes = self.stored_bytes.saturating_sub(freed);
        let live = &self.live;
        self.done_order.retain(|id| live.contains_key(id));
        let w = window.as_secs();
        let before = self.seen.len();
        self.seen.retain(|(_, t)| now_unix.saturating_sub(*t) <= w);
        self.before_restart
            .retain(|_, t| now_unix.saturating_sub(*t) <= w);
        self.seen.len() != before
    }

    /// Stores `r` as the call's result, then drops the oldest results'
    /// payloads while the total is over `cap` (their ids stay).
    fn finish(&mut self, id: &str, r: CallResult, cap: usize) {
        let Some(e) = self.live.get_mut(id) else {
            return;
        };
        self.stored_bytes += result_bytes(&r);
        e.phase = Phase::Done(r);
        self.done_order.push_back(id.to_string());
        while self.stored_bytes > cap {
            let Some(old) = self.done_order.pop_front() else {
                break;
            };
            if let Some(e) = self.live.get_mut(&old) {
                if let Phase::Done(r) = &e.phase {
                    self.stored_bytes = self.stored_bytes.saturating_sub(result_bytes(r));
                    e.phase = Phase::Evicted;
                }
            }
        }
    }

    fn in_flight(&self) -> usize {
        self.live
            .values()
            .filter(|e| matches!(e.phase, Phase::Prompting { .. } | Phase::Running { .. }))
            .count()
    }

    /// Whether the relay is still waiting on a call from this connection,
    /// and so pinging every 2 s: not once it was cancelled (it keeps running
    /// here, but the relay forgot it), stopped at its dialog, answered, or
    /// past its deadline.
    fn relay_waiting_on(&self, conn: u64, now: Instant) -> bool {
        self.live.values().any(|e| {
            e.conn == conn
                && now < e.deadline
                && matches!(
                    e.phase,
                    Phase::Prompting { stop: None, .. }
                        | Phase::Running {
                            cancelled: false,
                            ..
                        }
                )
        })
    }

    fn dialogs(&self) -> usize {
        self.live
            .values()
            .filter(|e| matches!(e.phase, Phase::Prompting { stop: None, .. }))
            .count()
    }

    fn seen_body(&self) -> String {
        self.seen
            .iter()
            .map(|(id, t)| format!("{}\n", json!({"id": id, "t": t})))
            .collect()
    }
}

/// What `seen_calls.jsonl` says at start.
enum SeenFile {
    Read(Vec<(String, u64)>),
    /// Missing, or empty.
    None,
    /// It could not be read, or a line is not an id record. Any id could
    /// be in what was lost.
    Unreadable(String),
}

fn read_seen(path: &Path) -> SeenFile {
    let text = match std::fs::read_to_string(path) {
        Ok(t) => t,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return SeenFile::None,
        Err(e) => return SeenFile::Unreadable(e.to_string()),
    };
    let mut out = Vec::new();
    let lines: Vec<&str> = text.split('\n').collect();
    let last = lines.len() - 1;
    for (i, l) in lines.iter().enumerate() {
        if l.trim().is_empty() {
            continue;
        }
        let rec = serde_json::from_str::<Value>(l)
            .ok()
            .and_then(|v| Some((v.get("id")?.as_str()?.to_string(), v.get("t")?.as_u64()?)));
        match rec {
            Some(r) => out.push(r),
            // Each id is one `write` of the record plus its newline, synced
            // before the call runs. A last line with no newline is an append
            // that never finished: that call never ran, so the line can go.
            None if i == last => {}
            None => return SeenFile::Unreadable(format!("line {} is not an id record", i + 1)),
        }
    }
    SeenFile::Read(out)
}

/// The name of a moved-aside record: `seen_calls.jsonl.corrupt-<unix time>`.
const CORRUPT: &str = ".corrupt-";

/// The end of a refusal window opened by an unreadable record, if one is
/// still open: the newest `seen_calls.jsonl.corrupt-<ts>` with `ts` less
/// than a window ago (a `ts` in the future counts as now).
fn open_window(dir: &Path, now_unix: u64, window: Duration) -> Option<u64> {
    let prefix = format!("{SEEN_CALLS}{CORRUPT}");
    std::fs::read_dir(dir)
        .ok()?
        .filter_map(|e| e.ok())
        .filter_map(|e| {
            e.file_name()
                .to_str()?
                .strip_prefix(&prefix)?
                .parse::<u64>()
                .ok()
        })
        .map(|ts| ts.min(now_unix) + window.as_secs())
        .filter(|until| now_unix < *until)
        .max()
}

/// Deletes the moved-aside records whose refusal window is over: every id
/// in them is older than the window, so they mark nothing any more.
/// Returns how many went.
fn remove_expired_records(dir: &Path, now_unix: u64, window: Duration) -> usize {
    let prefix = format!("{SEEN_CALLS}{CORRUPT}");
    let Ok(entries) = std::fs::read_dir(dir) else {
        return 0;
    };
    let mut gone = 0;
    for e in entries.filter_map(|e| e.ok()) {
        let name = e.file_name();
        let Some(ts) = name
            .to_str()
            .and_then(|n| n.strip_prefix(&prefix))
            .and_then(|t| t.parse::<u64>().ok())
        else {
            continue;
        };
        if ts.min(now_unix) + window.as_secs() <= now_unix && std::fs::remove_file(e.path()).is_ok()
        {
            gone += 1;
        }
    }
    gone
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
    timing: Timing,
    clock: Clock,
    log: Log,
    calls_log: CallLog,
    /// Serialises writes to `seen_calls.jsonl`.
    seen_lock: Mutex<()>,
    /// The connection that is up, for `tools_changed` after a reload.
    current: Mutex<Option<(u64, Out)>>,
    /// Bumped by every reload that loaded, so a connection whose `hello`
    /// was built before one (and welcomed after) can catch up.
    rules_gen: AtomicU64,
    /// What `status.json` says about the rules in use: paused, the loaded
    /// file's SHA-256, and why the last reload failed (if it did).
    rules_state: Arc<Mutex<Value>>,
    /// Reloads handled so far.
    reloads: AtomicU64,
    /// Nudged by a reload (`SIGHUP`, as `vrelay reload`, `pause`, `resume`
    /// and `logout` send): rewrite the status at once and check that the
    /// sign-in is still there.
    check_now: Arc<tokio::sync::Notify>,
    #[cfg(test)]
    hooks: Hooks,
}

/// `reloads` counts the reloads handled, so `vrelay reload` can tell the
/// answer to its own signal from an earlier one's.
fn rules_state(r: &Rules, reloads: u64, error: Option<&str>) -> Value {
    let mut v = json!({"paused": r.paused, "sha256": r.source_sha256, "reloads": reloads});
    if let (Some(e), Some(o)) = (error, v.as_object_mut()) {
        o.insert("reload_error".into(), json!(e));
    }
    v
}

impl<T: Tools, A: Asker> Shared<T, A> {
    fn log_line(
        &self,
        call_id: &str,
        tool: &str,
        args: Option<&Value>,
        decision: &str,
        extra: Value,
    ) {
        let mut line = json!({
            "t": (self.clock)(),
            "call_id": call_id,
            "tool": tool,
            "decision": decision,
        });
        if let Some(l) = line.as_object_mut() {
            if let Some(a) = args {
                l.insert("arguments".into(), a.clone());
            }
            if let Value::Object(e) = extra {
                l.extend(e);
            }
        }
        self.calls_log.line(line);
    }

    /// A call's one line: what it was and what happened.
    fn log_call(&self, call_id: &str, tool: &str, args: &Value, decision: &str, extra: Value) {
        self.log_line(call_id, tool, Some(args), decision, extra);
    }

    /// Rewrites `seen_calls.jsonl` with what is in memory. Blocking.
    fn compact_seen(&self) -> std::result::Result<(), String> {
        let _turn = self.seen_lock.lock().unwrap();
        let body = {
            let mut calls = self.calls.lock().unwrap();
            match calls.blind_until {
                // Inside the window the unreadable file may not have been
                // moved aside, and may hold ids: never overwrite it. Every id
                // it held is older than the window, so after it the file
                // can be rewritten as usual.
                Some(until) if (self.clock)() < until => return Ok(()),
                Some(_) => calls.blind_until = None,
                None => {}
            }
            calls.appended = 0;
            calls.seen_body()
        };
        write_private(&self.dir.join(SEEN_CALLS), body.as_bytes())
    }

    /// Appends one id to `seen_calls.jsonl` and syncs it (and, every so
    /// often, rewrites the file without expired ids). Off the link loop.
    /// An error (or a panic) means the id is not safely on disk.
    async fn record(self: &Arc<Self>, id: String, t: u64) -> std::result::Result<(), String> {
        #[cfg(test)]
        if let Some(g) = self.hooks.before_record.clone() {
            g.reached.notify_one();
            g.go.notified().await;
        }
        let me = self.clone();
        tokio::task::spawn_blocking(move || {
            let compact = {
                let _turn = me.seen_lock.lock().unwrap();
                #[cfg(test)]
                if me
                    .hooks
                    .fail_record
                    .as_ref()
                    .is_some_and(|f| f.load(Ordering::SeqCst))
                {
                    return Err("test hook: the disk is full".to_string());
                }
                let path = me.dir.join(SEEN_CALLS);
                let mut f = open_private_append(&path)?;
                f.write_all(format!("{}\n", json!({"id": id, "t": t})).as_bytes())
                    .and_then(|_| f.sync_data())
                    .map_err(|e| format!("write {}: {e}", path.display()))?;
                // Kept for rewrites only now that it is on disk, and still
                // under the turn a rewrite takes: no rewrite can come
                // between the append and this.
                let mut calls = me.calls.lock().unwrap();
                calls.seen.push((id, t));
                calls.appended += 1;
                calls.appended >= COMPACT_EVERY
            };
            if compact {
                if let Err(e) = me.compact_seen() {
                    (me.log)(&format!("could not tidy the record of started calls: {e}"));
                }
            }
            Ok(())
        })
        .await
        .map_err(|e| format!("the record task failed: {e}"))?
    }

    /// The id could not be recorded: the call is refused, never run.
    fn refuse_unrecorded(&self, call_id: &str, tool: &str, args: &Value, why: &str, out: &Out) {
        (self.log)(&format!("call {call_id}: not recorded, so not run: {why}"));
        let r = error_result(call_id, NOT_RECORDED);
        {
            let mut calls = self.calls.lock().unwrap();
            calls.seen.retain(|(id, _)| id != call_id);
            calls.finish(call_id, r.clone(), self.timing.results_cap_bytes);
        }
        self.log_call(
            call_id,
            tool,
            args,
            "refused",
            json!({"reason": "could not record the call"}),
        );
        let _ = out.send(ToRelay::Result(r));
    }

    /// Drops expired ids and results, and keeps `seen_calls.jsonl` tidy.
    async fn prune_now(self: &Arc<Self>) {
        let shrank = {
            let mut calls = self.calls.lock().unwrap();
            calls.prune(Instant::now(), (self.clock)(), self.timing.dedupe_window)
        };
        if shrank {
            let me = self.clone();
            let _ = tokio::task::spawn_blocking(move || {
                if let Err(e) = me.compact_seen() {
                    (me.log)(&format!("could not tidy the record of started calls: {e}"));
                }
            })
            .await;
        }
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
        // Never more than the call budget, and never an overflow.
        let budget = Duration::from_millis(deadline_ms).min(self.timing.max_call);
        let deadline = received.checked_add(budget).unwrap_or(received);
        let refuse = |id: &str, text: &str, reason: &str| {
            self.log_call(id, &tool, &arguments, "refused", json!({"reason": reason}));
            let _ = out.send(ToRelay::Result(error_result(id, text)));
        };
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
        let cap = self.timing.results_cap_bytes;
        let mut calls = self.calls.lock().unwrap();
        calls.prune(received, now_unix, self.timing.dedupe_window);
        if let Some(e) = calls.live.get(&call_id) {
            // A repeat: the stored result again, or nothing while it runs.
            match &e.phase {
                Phase::Done(r) => {
                    let _ = out.send(ToRelay::Result(r.clone()));
                }
                Phase::Evicted => {
                    let _ = out.send(ToRelay::Result(error_result(&call_id, EVICTED)));
                }
                _ => {}
            }
            return;
        }
        if calls.blind_until.is_some_and(|u| now_unix < u) {
            drop(calls);
            return refuse(
                &call_id,
                BLIND,
                "the record of started calls was unreadable",
            );
        }
        if calls.before_restart.contains_key(&call_id) {
            calls.live.insert(
                call_id.clone(),
                Entry {
                    at: received,
                    deadline,
                    conn,
                    phase: Phase::Running {
                        cancelled: false,
                        started: false,
                    },
                },
            );
            calls.finish(&call_id, error_result(&call_id, ALREADY_STARTED), cap);
            drop(calls);
            return refuse(
                &call_id,
                ALREADY_STARTED,
                "already started before vrelay restarted",
            );
        }
        let decision = self.rules.lock().unwrap().decide(&tool, &arguments);
        if !matches!(decision, Decision::Refuse(_)) {
            if calls.in_flight() >= self.timing.max_in_flight {
                drop(calls);
                return refuse(&call_id, BUSY, "too many calls in flight");
            }
            if decision == Decision::AskFirst && calls.dialogs() >= self.timing.max_dialogs {
                drop(calls);
                return refuse(&call_id, DIALOG_OPEN, "another dialog is open");
            }
        }
        // Only a call that will run goes into the record (a refused one
        // never ran, so a later repeat must not be told it "already
        // started"), and only once its own append has succeeded (`record`):
        // a rewrite of the file meanwhile writes only recorded ids.
        let dismiss = Arc::new(AtomicBool::new(false));
        let phase = match &decision {
            Decision::AskFirst => Phase::Prompting {
                dismiss: dismiss.clone(),
                stop: None,
            },
            _ => Phase::Running {
                cancelled: false,
                started: false,
            },
        };
        calls.live.insert(
            call_id.clone(),
            Entry {
                at: received,
                deadline,
                conn,
                phase,
            },
        );
        if let Decision::Refuse(why) = decision {
            let r = error_result(&call_id, &format!("Refused on the computer: {why}."));
            calls.finish(&call_id, r.clone(), cap);
            drop(calls);
            self.log_call(
                &call_id,
                &tool,
                &arguments,
                "refused",
                json!({"reason": why}),
            );
            let _ = out.send(ToRelay::Result(r));
            return;
        }
        drop(calls);
        let me = self.clone();
        let out = out.clone();
        tokio::spawn(async move {
            // On disk before anything can run.
            if let Err(e) = me.record(call_id.clone(), now_unix).await {
                me.refuse_unrecorded(&call_id, &tool, &arguments, &e, &out);
                return;
            }
            match decision {
                Decision::AskFirst => {
                    #[cfg(test)]
                    if let Some(g) = me.hooks.before_ask.clone() {
                        g.reached.notify_one();
                        g.go.notified().await;
                    }
                    me.ask_then_run(call_id, tool, arguments, deadline, dismiss, out)
                        .await
                }
                _ => {
                    #[cfg(test)]
                    if let Some(g) = me.hooks.before_run.clone() {
                        g.reached.notify_one();
                        g.go.notified().await;
                    }
                    me.run_tool(call_id, tool, arguments, deadline, "no_prompt", out)
                        .await
                }
            }
        });
    }

    /// Marks a call waiting at its dialog as stopped (if it still is) and
    /// closes the dialog.
    fn stop_one(&self, call_id: &str, why: Stop) {
        let mut calls = self.calls.lock().unwrap();
        if let Some(Entry {
            phase: Phase::Prompting { dismiss, stop },
            ..
        }) = calls.live.get_mut(call_id)
        {
            if stop.is_none() {
                *stop = Some(why);
                dismiss.store(true, Ordering::SeqCst);
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
        // Stopped before its dialog opened (a cancel, a drop): never show it.
        let stopped_early = {
            let calls = self.calls.lock().unwrap();
            match calls.live.get(&call_id).map(|e| &e.phase) {
                Some(Phase::Prompting { stop, .. }) => stop.is_some(),
                _ => return,
            }
        };
        let waited = if stopped_early {
            Waited::Dismissed
        } else {
            let summary = summarize(&tool, &args);
            let timeout = self
                .timing
                .max_prompt
                .min(deadline.saturating_duration_since(Instant::now()));
            let asker = self.asker.clone();
            let t = tool.clone();
            let mut dialog =
                tokio::task::spawn_blocking(move || asker.ask(&t, &summary, timeout, &dismiss));
            // The dialog never outlives the call's deadline: by then the
            // relay has given up on it.
            tokio::select! {
                w = &mut dialog => w.unwrap_or(Waited::Deny),
                _ = tokio::time::sleep_until(tokio::time::Instant::from_std(deadline)) => {
                    self.stop_one(&call_id, Stop::Expired);
                    dialog.await.unwrap_or(Waited::Deny)
                }
            }
        };
        // The answer is checked, and the call moved on, under the lock that a
        // cancel, a drop or the deadline takes: a late Allow finds it stopped.
        let refusal = {
            let mut calls = self.calls.lock().unwrap();
            let Some(entry) = calls.live.get_mut(&call_id) else {
                return;
            };
            let stop = match &entry.phase {
                Phase::Prompting { stop, .. } => *stop,
                _ => return,
            };
            let refusal = prompt_refusal(stop, waited, Instant::now() < deadline);
            match refusal {
                None => {
                    entry.phase = Phase::Running {
                        cancelled: false,
                        started: false,
                    }
                }
                Some((_, text, _)) => calls.finish(
                    &call_id,
                    error_result(&call_id, text),
                    self.timing.results_cap_bytes,
                ),
            }
            refusal
        };
        match refusal {
            None => {
                self.run_tool(call_id, tool, args, deadline, "allowed", out)
                    .await
            }
            Some((decision, text, send)) => {
                self.log_call(&call_id, &tool, &args, decision, json!({}));
                // After a cancel, a drop or the deadline the relay has
                // already failed the call: nothing to send.
                if send {
                    let _ = out.send(ToRelay::Result(error_result(&call_id, text)));
                }
            }
        }
    }

    /// Whether the call may still start: not cancelled, not past its
    /// deadline (the relay has given up on it), and the rules not paused
    /// since it was cleared. If not, it is finished here and logged; only a
    /// pause sends its answer (the relay still waits on that call). Checked
    /// under the lock a cancel takes, and the rules are read under it too,
    /// so a pause applied after this says yes finds the call `started`.
    /// `last`: the check just before the tool is sent the call.
    fn may_start(
        &self,
        call_id: &str,
        tool: &str,
        args: &Value,
        deadline: Instant,
        last: bool,
        out: &Out,
    ) -> bool {
        let mut calls = self.calls.lock().unwrap();
        let paused = self.rules.lock().unwrap().paused;
        let stop = match calls.live.get_mut(call_id).map(|e| &mut e.phase) {
            Some(Phase::Running {
                cancelled: true, ..
            }) => ("cancelled before running", CANCELLED_EARLY, false),
            Some(Phase::Running { .. }) if paused => ("paused before running", PAUSED, true),
            Some(Phase::Running { started, .. }) if Instant::now() < deadline => {
                *started |= last;
                return true;
            }
            Some(Phase::Running { .. }) => ("timed out", TIMED_OUT, false),
            _ => return false,
        };
        let r = error_result(call_id, stop.1);
        calls.finish(call_id, r.clone(), self.timing.results_cap_bytes);
        drop(calls);
        self.log_call(call_id, tool, args, stop.0, json!({}));
        if stop.2 {
            let _ = out.send(ToRelay::Result(r));
        }
        false
    }

    /// The rules just became paused: close every open dialog (those calls
    /// are refused) and log the calls already running, which keep running
    /// (P1 does not stop a command). A call cleared but not started is
    /// refused at its last check (`may_start`).
    fn on_paused(&self) {
        let mut running = Vec::new();
        {
            let mut calls = self.calls.lock().unwrap();
            for (id, e) in calls.live.iter_mut() {
                match &mut e.phase {
                    Phase::Prompting { dismiss, stop } if stop.is_none() => {
                        *stop = Some(Stop::Paused);
                        dismiss.store(true, Ordering::SeqCst);
                    }
                    Phase::Running {
                        cancelled: false,
                        started: true,
                    } => running.push(id.clone()),
                    _ => {}
                }
            }
        }
        for id in running {
            (self.log)(&format!(
                "call {id} was already running when vrelay was paused: it keeps running \
                 (the command is not stopped)"
            ));
            self.calls_log.line(json!({
                "t": (self.clock)(),
                "call_id": id,
                "decision": "running when paused",
                "note": "it keeps running; the command is not stopped",
            }));
        }
    }

    async fn run_tool(
        self: Arc<Self>,
        call_id: String,
        tool: String,
        args: Value,
        deadline: Instant,
        approval: &'static str,
        out: Out,
    ) {
        let cap = self.timing.results_cap_bytes;
        if !self.may_start(&call_id, &tool, &args, deadline, false, &out) {
            return;
        }
        // On disk before it starts, so a command cut off by a crash, a
        // SIGKILL or a power cut still has a line.
        let line = json!({
            "t": (self.clock)(),
            "call_id": call_id,
            "tool": tool,
            "decision": "running",
            "arguments": args,
            "approval": approval,
        });
        let log = self.calls_log.clone();
        let wait = self.timing.log_wait;
        let written = tokio::task::spawn_blocking(move || log.line_synced(line, wait))
            .await
            .unwrap_or_else(|e| Err(format!("the log task failed: {e}")));
        if let Err(e) = written {
            (self.log)(&format!("call {call_id}: not logged, so not run: {e}"));
            let r = error_result(&call_id, NOT_LOGGED);
            self.calls.lock().unwrap().finish(&call_id, r.clone(), cap);
            // The `running` line may still be written once the disk recovers
            // (it waits in the writer's queue): this line, behind it, says the
            // call did not run after all.
            self.log_call(
                &call_id,
                &tool,
                &args,
                "refused",
                json!({"reason": "could not write the calls log"}),
            );
            let _ = out.send(ToRelay::Result(r));
            return;
        }
        // A cancel or the deadline may have come while the line was synced,
        // or may yet come while desktop-commander restarts: the bridge asks
        // again just before it sends the call.
        let me = self.clone();
        let (id, t, a, o) = (call_id.clone(), tool.clone(), args.clone(), out.clone());
        let wanted: StillWanted = Arc::new(move || me.may_start(&id, &t, &a, deadline, true, &o));
        let started = Instant::now();
        let Some(output) = self.tools.call(&tool, args, deadline, wanted).await else {
            return;
        };
        let r = CallResult {
            call_id: call_id.clone(),
            content: output.content,
            is_error: output.is_error,
            truncated: output.truncated,
        };
        let cancelled = {
            let mut calls = self.calls.lock().unwrap();
            let c = matches!(
                calls.live.get(&call_id).map(|e| &e.phase),
                Some(Phase::Running {
                    cancelled: true,
                    ..
                })
            );
            calls.finish(&call_id, r.clone(), cap);
            c
        };
        self.log_line(
            &call_id,
            &tool,
            None,
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
            Phase::Running { cancelled, .. } => {
                *cancelled = true;
                (self.log)(&format!(
                    "call {call_id} was cancelled: it will not start, or if it already has, \
                     its result is dropped (the command itself is not stopped)"
                ));
            }
            _ => {}
        }
    }

    /// Closes every open dialog (of one connection, or all) and marks those
    /// calls stopped, so a later Allow cannot run them. A call cleared to
    /// run that has not started yet is stopped too (one already running
    /// keeps running, but its result has nowhere to go).
    fn stop_prompts(&self, conn: Option<u64>, why: Stop) {
        let mut calls = self.calls.lock().unwrap();
        for e in calls.live.values_mut() {
            if conn.is_some_and(|c| c != e.conn) {
                continue;
            }
            match &mut e.phase {
                Phase::Prompting { dismiss, stop } if stop.is_none() => {
                    *stop = Some(why);
                    dismiss.store(true, Ordering::SeqCst);
                }
                Phase::Running { cancelled, .. } => *cancelled = true,
                _ => {}
            }
        }
    }

    /// `SIGHUP`: re-read the rules. A file that does not load keeps the
    /// rules in use.
    async fn reload(&self) {
        let tools = self.tools.list().await;
        let current = self.rules.lock().unwrap().clone();
        let n = self.reloads.fetch_add(1, Ordering::SeqCst) + 1;
        match rules::reload(&self.dir, &current, &tools) {
            Err(e) => {
                (self.log)(&format!("rules not reloaded, keeping the ones in use: {e}"));
                *self.rules_state.lock().unwrap() = rules_state(&current, n, Some(&e));
            }
            Ok(r) => {
                let visible = r.rules.visible(&tools);
                // Only when it becomes paused: a reload while already
                // paused has nothing new to close or log.
                let paused = r.rules.paused && !current.paused;
                *self.rules_state.lock().unwrap() = rules_state(&r.rules, n, None);
                *self.rules.lock().unwrap() = r.rules;
                if paused {
                    self.on_paused();
                }
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
    reason: Option<String>,
    /// Why the relay last refused the link (`reject`), until a link is
    /// welcomed again: `vrelay status` shows it, as it does a refused
    /// sign-in, instead of "connecting" for ever.
    refused: Option<String>,
    /// The rules in use (shared with the reloader).
    rules: Arc<Mutex<Value>>,
    /// The reloader's nudge (`Shared::check_now`).
    check_now: Arc<tokio::sync::Notify>,
}

impl Status {
    fn set(&mut self, state: &'static str, next_retry: Option<u64>) {
        self.state = state;
        self.next_retry = next_retry;
        self.reason = None;
        self.write();
    }

    fn waiting(&mut self, reason: Option<String>) {
        self.state = "waiting_for_sign_in";
        self.next_retry = None;
        self.reason = reason;
        self.write();
    }

    fn write(&self) {
        let mut body = json!({
            "state": self.state,
            "updated_unix": (self.clock)(),
            "last_pong_unix": self.last_pong,
            "next_retry_unix": self.next_retry,
            // So `vrelay reload` (and pause, resume, logout) can signal it,
            // and check first that the pid is still this process.
            "pid": std::process::id(),
            "pid_start": own_start(),
            "rules": self.rules.lock().unwrap().clone(),
        });
        if let Some(o) = body.as_object_mut() {
            if let Some(r) = &self.reason {
                o.insert("reason".into(), json!(r));
            }
            if let Some(r) = &self.refused {
                o.insert("refused".into(), json!(r));
            }
        }
        let _ = self.tx.send(Some(body.to_string()));
    }
}

/// This process's start time (`proc::process_start`), looked up once.
fn own_start() -> Option<u64> {
    static START: std::sync::OnceLock<Option<u64>> = std::sync::OnceLock::new();
    *START.get_or_init(|| crate::proc::process_start(std::process::id() as i32))
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

type Ws = WebSocketStream<MaybeTlsStream<Counted<TcpStream>>>;
type Sink = SplitSink<Ws, Message>;

/// What the socket under the WebSocket has read: how many bytes, and when
/// the last ones came. So the link knows the relay is there while a large
/// frame is still on its way (the relay does the same: `SeenIo` in
/// relay/src/http.rs).
pub(crate) struct ReadMeter {
    bytes: AtomicU64,
    /// Milliseconds after `since` of the last read that returned bytes.
    last_ms: AtomicU64,
    since: Instant,
}

impl ReadMeter {
    fn new() -> ReadMeter {
        ReadMeter {
            bytes: AtomicU64::new(0),
            last_ms: AtomicU64::new(0),
            since: Instant::now(),
        }
    }

    fn bytes(&self) -> u64 {
        self.bytes.load(Ordering::Relaxed)
    }

    /// When bytes last arrived (`since` if none have).
    fn last(&self) -> Instant {
        self.since + Duration::from_millis(self.last_ms.load(Ordering::Relaxed))
    }
}

pub(crate) struct Counted<S> {
    inner: S,
    meter: Arc<ReadMeter>,
}

impl<S: tokio::io::AsyncRead + Unpin> tokio::io::AsyncRead for Counted<S> {
    fn poll_read(
        mut self: std::pin::Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
        buf: &mut tokio::io::ReadBuf<'_>,
    ) -> std::task::Poll<std::io::Result<()>> {
        let before = buf.filled().len();
        let r = std::pin::Pin::new(&mut self.inner).poll_read(cx, buf);
        let n = buf.filled().len() - before;
        if n > 0 {
            let m = &self.meter;
            m.bytes.fetch_add(n as u64, Ordering::Relaxed);
            m.last_ms
                .fetch_max(m.since.elapsed().as_millis() as u64, Ordering::Relaxed);
        }
        r
    }
}

impl<S: tokio::io::AsyncWrite + Unpin> tokio::io::AsyncWrite for Counted<S> {
    fn poll_write(
        mut self: std::pin::Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
        buf: &[u8],
    ) -> std::task::Poll<std::io::Result<usize>> {
        std::pin::Pin::new(&mut self.inner).poll_write(cx, buf)
    }

    fn poll_flush(
        mut self: std::pin::Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
    ) -> std::task::Poll<std::io::Result<()>> {
        std::pin::Pin::new(&mut self.inner).poll_flush(cx)
    }

    fn poll_shutdown(
        mut self: std::pin::Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
    ) -> std::task::Poll<std::io::Result<()>> {
        std::pin::Pin::new(&mut self.inner).poll_shutdown(cx)
    }

    fn poll_write_vectored(
        mut self: std::pin::Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
        bufs: &[std::io::IoSlice<'_>],
    ) -> std::task::Poll<std::io::Result<usize>> {
        std::pin::Pin::new(&mut self.inner).poll_write_vectored(cx, bufs)
    }

    fn is_write_vectored(&self) -> bool {
        self.inner.is_write_vectored()
    }
}

/// When the relay was last heard from, for the in-call silence check. Time
/// the link loop spends sending is not counted: it cannot read meanwhile,
/// so whatever the relay sent then is still waiting to be read.
struct Silence {
    last: Instant,
}

impl Silence {
    fn heard(&mut self) {
        self.last = Instant::now();
    }

    /// Bytes read from the socket count from when they came, even part of a
    /// frame not yet whole.
    fn saw(&mut self, read: &ReadMeter) {
        self.last = self.last.max(read.last());
    }

    /// The loop just spent `spent` sending.
    fn sent(&mut self, spent: Duration) {
        self.last = (self.last + spent).min(Instant::now());
    }

    fn silent_for(&self) -> Duration {
        self.last.elapsed()
    }
}

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
    let budget = send_budget(timeout, text.len());
    match tokio::time::timeout(budget, sink.send(Message::Text(text))).await {
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
        let window = self.timing.dedupe_window;
        let path = self.dir.join(SEEN_CALLS);
        let mut calls = Calls::default();
        match read_seen(&path) {
            SeenFile::None => {}
            SeenFile::Read(seen) => {
                let seen: Vec<_> = seen
                    .into_iter()
                    .filter(|(_, t)| now_unix.saturating_sub(*t) <= window.as_secs())
                    .collect();
                calls.before_restart = seen.iter().cloned().collect();
                calls.seen = seen;
            }
            SeenFile::Unreadable(why) => {
                // Keeping the lines that parse could let an id in a damaged
                // line run twice; refusing every call for one window cannot.
                let aside = self.dir.join(format!("{SEEN_CALLS}{CORRUPT}{now_unix}"));
                let moved = std::fs::rename(&path, &aside);
                // The moved file is the durable mark of the window (below):
                // make the rename survive a power cut.
                sync_dir(&aside);
                (self.log)(&format!(
                    "{SEEN_CALLS} is unreadable ({why}); moved to {} ({}); refusing calls for {} s",
                    aside.display(),
                    match &moved {
                        Ok(()) => "done".to_string(),
                        Err(e) => format!("failed: {e}"),
                    },
                    window.as_secs()
                ));
                calls.blind_until = Some(now_unix + window.as_secs());
            }
        }
        // Records whose window is over mark nothing; they would pile up.
        let gone = remove_expired_records(&self.dir, now_unix, window);
        if gone > 0 {
            (self.log)(&format!(
                "deleted {gone} old unreadable record(s) of started calls"
            ));
        }
        // A window opened by an earlier vrelay still holds: the moved-aside
        // file's name says when it began.
        if let Some(until) = open_window(&self.dir, now_unix, window) {
            if calls.blind_until.is_none_or(|u| u < until) {
                (self.log)(&format!(
                    "a record of started calls was unreadable at an earlier start; \
                     refusing calls for {} s more",
                    until - now_unix
                ));
                calls.blind_until = Some(until);
            }
        }
        let calls_log = CallLog::start(
            self.log_dir.clone(),
            self.timing.log_max_bytes,
            self.log.clone(),
            #[cfg(test)]
            self.hooks.hold_log.clone(),
        );
        let shared = Arc::new(Shared {
            tools: self.tools.clone(),
            asker: self.asker.clone(),
            rules: Mutex::new(self.rules.clone()),
            calls: Mutex::new(calls),
            dir: self.dir.clone(),
            timing: self.timing.clone(),
            clock: self.clock.clone(),
            log: self.log.clone(),
            calls_log: calls_log.clone(),
            seen_lock: Mutex::new(()),
            current: Mutex::new(None),
            rules_gen: AtomicU64::new(0),
            rules_state: Arc::new(Mutex::new(rules_state(&self.rules, 0, None))),
            reloads: AtomicU64::new(0),
            check_now: Arc::new(tokio::sync::Notify::new()),
            #[cfg(test)]
            hooks: self.hooks.clone(),
        });
        // Expired ids leave the file now (not if it was unreadable).
        if let Err(e) = shared.compact_seen() {
            (self.log)(&format!("could not tidy the record of started calls: {e}"));
        }
        let r = shared.clone();
        let reloader = tokio::spawn(async move {
            while reload.recv().await.is_some() {
                r.reload().await;
                r.check_now.notify_one();
            }
        });
        let p = shared.clone();
        let every = self.timing.prune_every;
        let pruner = tokio::spawn(async move {
            let mut tick = tokio::time::interval_at(tokio::time::Instant::now() + every, every);
            loop {
                tick.tick().await;
                p.prune_now().await;
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
            reason: None,
            refused: None,
            rules: shared.rules_state.clone(),
            check_now: shared.check_now.clone(),
        };
        let mut attempt: u32 = 0;
        let mut conn: u64 = 0;
        let mut last_refusal: Option<String> = None;
        loop {
            if *shutdown.borrow() {
                break;
            }
            let tokens = self.tokens.clone();
            let fetch = tokio::task::spawn_blocking(move || tokens.token());
            let Some(token) = self.guarded(fetch, &status, &mut shutdown).await else {
                break;
            };
            let token = token.unwrap_or_else(|e| Err(TokenError::Unavailable(e.to_string())));
            let (token, device) = match (token, load_device(&self.dir)) {
                (Ok(Some(t)), Some(d)) => (t, d),
                (Ok(_), _) => {
                    status.waiting(None);
                    if self
                        .pause(self.timing.token_poll, &status, &mut shutdown)
                        .await
                    {
                        break;
                    }
                    continue;
                }
                // The sign-in is over: wait for `vrelay login` like with no
                // token at all, instead of asking the issuer again and again.
                (Err(TokenError::SignInAgain(why)), _) => {
                    if last_refusal.as_deref() != Some(why.as_str()) {
                        (self.log)(&format!("waiting for a new sign-in: {why}"));
                        last_refusal = Some(why.clone());
                    }
                    status.waiting(Some(why));
                    if self
                        .pause(self.timing.token_poll, &status, &mut shutdown)
                        .await
                    {
                        break;
                    }
                    continue;
                }
                (Err(TokenError::Unavailable(e)), _) => {
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
            let Some(dialed) = self
                .guarded(self.connect(&token), &status, &mut shutdown)
                .await
            else {
                break;
            };
            let up = match dialed {
                Err(e) => {
                    (self.log)(&format!("could not reach the relay: {e}"));
                    None
                }
                Ok((ws, read)) => {
                    let gen = shared.rules_gen.load(Ordering::SeqCst);
                    let Some(hello) = self
                        .guarded(
                            self.hello(&shared, &device.device_id, &token),
                            &status,
                            &mut shutdown,
                        )
                        .await
                    else {
                        break;
                    };
                    let tokens = self.tokens.clone();
                    let dir = self.dir.clone();
                    let signed_in = move || tokens.signed_in() && device_path(&dir).exists();
                    let dialed = Dialed {
                        ws,
                        read,
                        conn,
                        hello,
                        rules_gen: gen,
                    };
                    let (up, shut) =
                        session(&shared, dialed, &signed_in, &mut status, &mut shutdown).await;
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
        pruner.abort();
        // So `vrelay status` says stopped at once, not after a minute: after
        // the last pending write.
        drop(status);
        let _ = writer.await;
        let _ = std::fs::remove_file(status_path(&self.dir));
        let l = calls_log.clone();
        let _ = tokio::task::spawn_blocking(move || l.flush(Duration::from_secs(2))).await;
    }

    /// Runs `fut`, keeping the status file fresh meanwhile. `None` if told
    /// to stop first (`fut` is dropped; a blocking task finishes on its own).
    async fn guarded<F: Future>(
        &self,
        fut: F,
        status: &Status,
        shutdown: &mut watch::Receiver<bool>,
    ) -> Option<F::Output> {
        tokio::pin!(fut);
        let every = self.timing.status_every;
        let mut tick = tokio::time::interval_at(tokio::time::Instant::now() + every, every);
        loop {
            tokio::select! {
                v = &mut fut => return Some(v),
                _ = tick.tick() => status.write(),
                // A reload: say so now, not at the next tick.
                _ = status.check_now.notified() => status.write(),
                _ = stopped(shutdown) => return None,
            }
        }
    }

    /// Waits `d`, keeping the status file fresh. True if told to stop.
    async fn pause(
        &self,
        d: Duration,
        status: &Status,
        shutdown: &mut watch::Receiver<bool>,
    ) -> bool {
        self.guarded(tokio::time::sleep(d), status, shutdown)
            .await
            .is_none()
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

    /// The WebSocket, and what has been read from under it.
    async fn connect(&self, token: &str) -> std::result::Result<(Ws, Arc<ReadMeter>), String> {
        let url = connect_url(&self.relay_url)?;
        let mut req = url
            .as_str()
            .into_client_request()
            .map_err(|e| format!("{url}: {e}"))?;
        let host = req
            .uri()
            .host()
            .ok_or_else(|| format!("{url}: no host"))?
            .trim_start_matches('[')
            .trim_end_matches(']')
            .to_string();
        let port = req
            .uri()
            .port_u16()
            .unwrap_or(if url.starts_with("wss://") { 443 } else { 80 });
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
        let read = Arc::new(ReadMeter::new());
        let meter = read.clone();
        let dial = async move {
            let tcp = TcpStream::connect((host.as_str(), port))
                .await
                .map_err(|e| format!("connect to {host}:{port}: {e}"))?;
            let _ = tcp.set_nodelay(true);
            let tcp = Counted { inner: tcp, meter };
            tokio_tungstenite::client_async_tls_with_config(req, tcp, Some(config), Some(connector))
                .await
                .map_err(|e| match e {
                    tokio_tungstenite::tungstenite::Error::Http(resp) => {
                        format!("the relay refused the link (HTTP {})", resp.status())
                    }
                    e => e.to_string(),
                })
        };
        match tokio::time::timeout(self.timing.connect_timeout, dial).await {
            Err(_) => Err("timed out".into()),
            Ok(Err(e)) => Err(e),
            Ok(Ok((ws, _))) => Ok((ws, read)),
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
/// A connection made, its `hello` ready to send.
struct Dialed {
    ws: Ws,
    read: Arc<ReadMeter>,
    /// Its number, for the calls that come on it.
    conn: u64,
    hello: Hello,
    /// The reload count when the hello's tool list was built.
    rules_gen: u64,
}

async fn session<T: Tools, A: Asker>(
    shared: &Arc<Shared<T, A>>,
    dialed: Dialed,
    signed_in: &(dyn Fn() -> bool + Send + Sync),
    status: &mut Status,
    shutdown: &mut watch::Receiver<bool>,
) -> (Option<Duration>, bool) {
    let Dialed {
        ws,
        read,
        conn,
        hello,
        rules_gen,
    } = dialed;
    let t = shared.timing.clone();
    let log = shared.log.clone();
    let clock = shared.clock.clone();
    let hello_tools = hello.tools.clone();
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
    let mut in_call = tokio::time::interval_at(start + t.in_call_every, t.in_call_every);
    in_call.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
    let silent_limit = t.in_call_every * t.max_missed.max(1);
    let mut silence = Silence {
        last: Instant::now(),
    };
    // Bytes read when our last ping went out: any since answer it.
    let mut read_at_ping = read.bytes();
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
                let now_read = read.bytes();
                if now_read != read_at_ping {
                    beat.heard();
                }
                read_at_ping = now_read;
                if beat.awaiting {
                    beat.missed += 1;
                    if beat.missed >= t.max_missed {
                        break format!("{} pings unanswered", beat.missed);
                    }
                }
                beat.n = beat.n.wrapping_add(1);
                beat.awaiting = true;
                let at = Instant::now();
                if let Err(e) = send(&mut sink, &ToRelay::Ping { n: beat.n }, t.send_timeout).await {
                    break e;
                }
                silence.sent(at.elapsed());
            }
            // While a call is in flight the relay pings every 2 s and drops
            // the call after 3 missed: go down as quickly, so no dialog
            // outlives a link the relay has already given up on.
            _ = in_call.tick() => {
                silence.saw(&read);
                if silence.silent_for() >= silent_limit
                    && shared.calls.lock().unwrap().relay_waiting_on(conn, Instant::now())
                {
                    break format!("nothing from the relay for {silent_limit:?} during a call");
                }
            }
            // `vrelay logout` removed the sign-in: the link goes down now,
            // not when the relay closes it at the token's expiry.
            _ = refresh.tick() => {
                if !signed_in() {
                    break "signed out on this Mac (vrelay logout)".into();
                }
                status.write();
            }
            _ = shared.check_now.notified() => {
                if !signed_in() {
                    break "signed out on this Mac (vrelay logout)".into();
                }
                status.write();
            }
            Some(f) = out_rx.recv() => {
                let at = Instant::now();
                if let Err(e) = send(&mut sink, &f, t.send_timeout).await {
                    break e;
                }
                // Whatever the relay sent meanwhile is still unread.
                silence.sent(at.elapsed());
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
                        silence.heard();
                        continue;
                    }
                };
                beat.heard();
                silence.heard();
                match decode_to_connector(&text) {
                    // Size only: a bad frame may hold arguments.
                    Err(_) => log(&format!("ignored a bad frame ({} bytes)", text.len())),
                    Ok(ToConnector::Welcome { .. }) => {
                        if welcomed.is_none() {
                            welcomed = Some(Instant::now());
                            status.last_pong = Some(clock());
                            status.refused = None;
                            status.set("connected", None);
                            *shared.current.lock().unwrap() = Some((conn, out.clone()));
                            log("connected to the relay");
                            // Rules reloaded after the hello was built: send
                            // the tools they show now, if those differ.
                            if shared.rules_gen.load(Ordering::SeqCst) != rules_gen {
                                let s = shared.clone();
                                let out = out.clone();
                                let sent = hello_tools.clone();
                                tokio::spawn(async move {
                                    let all = s.tools.list().await;
                                    let tools = s.rules.lock().unwrap().visible(&all);
                                    if tools != sent {
                                        let _ = out.send(ToRelay::ToolsChanged { tools });
                                    }
                                });
                            }
                        }
                    }
                    Ok(ToConnector::Reject { reason }) => {
                        // Cut: it is shown to the person, and came from afar.
                        status.refused = Some(reason.chars().take(300).collect());
                        break format!("the relay refused the link: {reason}");
                    }
                    Ok(ToConnector::Ping { n }) => {
                        let at = Instant::now();
                        #[cfg(test)]
                        if let Some((below, g)) = shared.hooks.hold_pong.clone() {
                            if n < below {
                                g.reached.notify_one();
                                g.go.notified().await;
                            }
                        }
                        if let Err(e) = send(&mut sink, &ToRelay::Pong { n }, t.send_timeout).await {
                            break e;
                        }
                        silence.sent(at.elapsed());
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
                    Ok(ToConnector::Start { .. } | ToConnector::ResultAck { .. }) => {}
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
