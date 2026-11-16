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

//! The bridge to `desktop-commander`: runs the pinned package over stdio as
//! an MCP server and speaks JSON-RPC to it, one message per line.
//!
//! What spike D found, built in here:
//! - It starts commands as its own children, and they outlive it. So it runs
//!   in its own process group, and whenever it goes (stopped, crashed, or
//!   exited by itself) the whole group is killed.
//! - Its log messages arrive as `notifications/message`; they go to the log
//!   and are never taken for replies.
//! - Telemetry off (`DESKTOP_COMMANDER_DISABLE_TELEMETRY=1`), and its feature
//!   flag fetch pointed at a closed local port (`DC_FLAG_URL`).
//! - Its call log in `~/.claude-server-commander` holds full arguments, so
//!   that folder is made `0700` at start.
//!
//! Three threads per running server: one writes requests to its stdin, one
//! reads its stdout and routes replies by id, and one waits for it to exit
//! and then kills its group. Calls wait on a oneshot channel, so many can be
//! in flight at once.

use std::collections::HashMap;
use std::io::{BufRead, BufReader, Write};
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicI32, AtomicU64, Ordering};
use std::sync::mpsc;
use std::sync::{Arc, Condvar, Mutex};
use std::time::{Duration, Instant};

use serde_json::{json, Value};
use tokio::sync::oneshot;
use vitruvian_relay_protocol::{encode, CallResult, FrameError, ToRelay, ToolDef, MAX_FRAME_BYTES};

use crate::Result;

/// The oldest Node `desktop-commander` 0.3.1 runs on (its `engines`).
pub const MIN_NODE: (u32, u32) = (22, 12);
const NODE_ADVICE: &str = "desktop-commander needs Node.js 22.12 or newer. \
     Install it from https://nodejs.org (or `brew install node`), then try again.";

/// Where the pinned package's entry point sits in `vrelay`'s runfiles.
pub const DC_RUNFILE: &str = "_main/apps/suites/vitruvian-relay/connector/dc/node_modules/@wonderwhy-er/desktop-commander/dist/index.js";
/// Written by the installer (Task 9), relative to `HOME`.
pub const BRIDGE_JSON: &str = ".local/share/vrelay/bridge.json";
/// `desktop-commander`'s own folder, relative to `HOME`.
pub const DC_CONFIG_DIR: &str = ".claude-server-commander";

/// The truncation check measures the `result` frame Task 8 sends, with a
/// `call_id` this long standing in for the real one (the relay's are 32 hex
/// characters). Task 8 must not send a longer one.
pub const CALL_ID_RESERVE: usize = 256;

const INIT_TIMEOUT: Duration = Duration::from_secs(30);
const LIST_TIMEOUT: Duration = Duration::from_secs(30);
/// Each step of `stop`: after closing stdin, after SIGTERM.
const STOP_STEP: Duration = Duration::from_secs(2);
/// Longest notification or stray line copied into the log.
const MAX_LOG_LINE: usize = 2000;

const PROTOCOL_VERSION: &str = "2025-06-18";

/// Where the log lines go. `vrelay` writes them to stderr, which the
/// LaunchAgent sends to the connector log.
pub type Log = Arc<dyn Fn(&str) + Send + Sync>;

fn stderr_log() -> Log {
    Arc::new(|s: &str| eprintln!("vrelay: {s}"))
}

/// How to start `desktop-commander`: which `node`, and its `dist/index.js`.
#[derive(Debug, Clone, PartialEq, Eq, serde::Deserialize)]
pub struct BridgeCommand {
    pub node: PathBuf,
    pub entry: PathBuf,
}

impl BridgeCommand {
    /// Under `bazel run`: the pinned package from the runfiles and the `node`
    /// on `PATH`. Otherwise `~/.local/share/vrelay/bridge.json`, written by
    /// the installer.
    pub fn locate() -> Result<BridgeCommand> {
        let home = PathBuf::from(std::env::var("HOME").map_err(|_| "HOME is not set")?);
        let under_bazel = std::env::var_os("BUILD_WORKSPACE_DIRECTORY").is_some();
        let mut runfiles = Vec::new();
        if let Some(d) = std::env::var_os("RUNFILES_DIR") {
            runfiles.push(PathBuf::from(d));
        }
        if let Ok(exe) = std::env::current_exe() {
            let mut d = exe.into_os_string();
            d.push(".runfiles");
            runfiles.push(PathBuf::from(d));
        }
        let path = std::env::var("PATH").ok();
        locate_from(&home, under_bazel, &runfiles, path.as_deref())
    }
}

/// [`BridgeCommand::locate`] with its inputs given (for tests).
pub fn locate_from(
    home: &Path,
    under_bazel: bool,
    runfiles: &[PathBuf],
    path: Option<&str>,
) -> Result<BridgeCommand> {
    let from_runfiles = || -> Option<PathBuf> {
        runfiles
            .iter()
            .map(|d| d.join(DC_RUNFILE))
            .find(|p| p.is_file())
    };
    if under_bazel {
        if let Some(entry) = from_runfiles() {
            let node = find_on_path("node", path).ok_or(NODE_ADVICE)?;
            return Ok(BridgeCommand { node, entry });
        }
    }
    let bj = home.join(BRIDGE_JSON);
    match std::fs::read_to_string(&bj) {
        Ok(text) => {
            serde_json::from_str(&text).map_err(|e| format!("{}: {e}", bj.display()))
        }
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Err(format!(
            "cannot find desktop-commander: there is no {} (the installer writes it). \
             Install vrelay, or run it with `bazel run //apps/suites/vitruvian-relay/connector:vrelay`.",
            bj.display()
        )),
        Err(e) => Err(format!("read {}: {e}", bj.display())),
    }
}

fn find_on_path(name: &str, path: Option<&str>) -> Option<PathBuf> {
    use std::os::unix::fs::PermissionsExt;
    path?
        .split(':')
        .filter(|d| !d.is_empty())
        .map(|d| Path::new(d).join(name))
        .find(|p| {
            std::fs::metadata(p)
                .map(|m| m.is_file() && m.permissions().mode() & 0o111 != 0)
                .unwrap_or(false)
        })
}

/// `v22.12.0` → `(22, 12)`.
pub fn parse_node_version(s: &str) -> Option<(u32, u32)> {
    let mut it = s.trim().strip_prefix('v')?.split('.');
    let major = it.next()?.parse().ok()?;
    let minor = it.next()?.parse().ok()?;
    Some((major, minor))
}

pub fn node_ok(version: &str) -> bool {
    parse_node_version(version).is_some_and(|v| v >= MIN_NODE)
}

fn check_node(node: &Path) -> Result<()> {
    let out = Command::new(node)
        .arg("--version")
        .stdin(Stdio::null())
        .stderr(Stdio::null())
        .output()
        .map_err(|e| format!("cannot run {}: {e}. {NODE_ADVICE}", node.display()))?;
    let version = String::from_utf8_lossy(&out.stdout).trim().to_string();
    if out.status.success() && node_ok(&version) {
        Ok(())
    } else {
        Err(format!(
            "{} is Node.js {}. {NODE_ADVICE}",
            node.display(),
            if version.is_empty() {
                "of an unknown version"
            } else {
                version.as_str()
            }
        ))
    }
}

/// Makes `HOME/.claude-server-commander` mode 0700, creating it if missing.
/// `desktop-commander`'s call log there records every call's full arguments.
pub fn secure_dc_config_dir(home: &Path) -> Result<()> {
    use std::os::unix::fs::{DirBuilderExt, PermissionsExt};
    let dir = home.join(DC_CONFIG_DIR);
    match std::fs::DirBuilder::new().mode(0o700).create(&dir) {
        Ok(()) => return Ok(()),
        // Already there (or made a moment ago by someone else): tighten it.
        Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => {}
        Err(e) => return Err(format!("create {}: {e}", dir.display())),
    }
    let meta =
        std::fs::symlink_metadata(&dir).map_err(|e| format!("read {}: {e}", dir.display()))?;
    if !meta.is_dir() {
        return Err(format!("{} is not a folder", dir.display()));
    }
    std::fs::set_permissions(&dir, std::fs::Permissions::from_mode(0o700))
        .map_err(|e| format!("make {} private: {e}", dir.display()))
}

/// What a call returned. Task 8 wraps it, with the call id, into a
/// `CallResult`.
#[derive(Debug, Clone, PartialEq)]
pub struct BridgeOutput {
    /// MCP content items, as `desktop-commander` sent them.
    pub content: Value,
    pub is_error: bool,
    /// Cut to fit a 4 MiB frame (the text says how much was dropped).
    pub truncated: bool,
}

impl BridgeOutput {
    fn error(msg: impl Into<String>) -> BridgeOutput {
        BridgeOutput {
            content: json!([{"type": "text", "text": msg.into()}]),
            is_error: true,
            truncated: false,
        }
    }

    fn from_result(result: &Value) -> BridgeOutput {
        BridgeOutput {
            content: result.get("content").cloned().unwrap_or_else(|| json!([])),
            is_error: result
                .get("isError")
                .and_then(Value::as_bool)
                .unwrap_or(false),
            truncated: false,
        }
    }
}

/// How big the `result` frame for `out` is, or `None` if it fits.
fn overshoot(out: &BridgeOutput) -> Option<usize> {
    let frame = ToRelay::Result(CallResult {
        call_id: "c".repeat(CALL_ID_RESERVE),
        content: out.content.clone(),
        is_error: out.is_error,
        truncated: out.truncated,
    });
    match encode(&frame) {
        Ok(_) => None,
        Err(FrameError::TooLarge(n)) => Some(n - MAX_FRAME_BYTES),
        // Cannot happen for a Value; treat as needing everything cut.
        Err(FrameError::Json(_)) => Some(usize::MAX / 2),
    }
}

fn note(omitted: usize) -> String {
    format!("[output truncated by vrelay: {omitted} bytes omitted]")
}

fn floor_boundary(s: &str, mut i: usize) -> usize {
    i = i.min(s.len());
    while !s.is_char_boundary(i) {
        i -= 1;
    }
    i
}

/// Cuts `out` until its encoded `result` frame fits in `MAX_FRAME_BYTES`.
///
/// The size is measured on the encoded frame, not the raw text: JSON escaping
/// can double it (`"` and line breaks) or worse. Text items are cut from the
/// longest first and end with a note of how many bytes were dropped; an item
/// that is not text (an image) and still does not fit is replaced by a note.
pub fn fit_to_frame(mut out: BridgeOutput) -> BridgeOutput {
    if overshoot(&out).is_none() {
        return out;
    }
    out.truncated = true;
    if !out.content.is_array() {
        out.content = json!([out.content]);
    }
    // Each text item's original text and how many bytes of it are kept.
    let mut texts: HashMap<usize, (String, usize)> = HashMap::new();
    for _ in 0..64 {
        let Some(over) = overshoot(&out) else {
            return out;
        };
        let items = out.content.as_array_mut().expect("made an array above");
        for (i, item) in items.iter().enumerate() {
            if item.get("type").and_then(Value::as_str) == Some("text") && !texts.contains_key(&i) {
                if let Some(t) = item.get("text").and_then(Value::as_str) {
                    texts.insert(i, (t.to_string(), t.len()));
                }
            }
        }
        // The item with the most to give: a text is cut, anything else (an
        // image) is replaced by a note.
        let biggest = items
            .iter()
            .enumerate()
            .map(|(i, v)| match texts.get(&i) {
                Some((_, kept)) => (i, *kept, true),
                None => (
                    i,
                    serde_json::to_string(v).map(|s| s.len()).unwrap_or(0),
                    false,
                ),
            })
            .filter(|(_, n, _)| *n > 0)
            .max_by_key(|(_, n, _)| *n);
        match biggest {
            Some((i, _, true)) => {
                let (orig, kept) = texts.get_mut(&i).expect("a text item");
                // Every byte cut removes at least one encoded byte; the note
                // and its line break add at most 64.
                *kept = floor_boundary(orig, kept.saturating_sub(over + 64));
                let text = format!("{}\n{}", &orig[..*kept], note(orig.len() - *kept));
                items[i]["text"] = Value::String(text);
            }
            Some((i, n, false)) => {
                items[i] = json!({"type": "text", "text": note(n)});
                texts.insert(i, (String::new(), 0));
            }
            None => break,
        }
    }
    // Unreachable in practice; never send a frame that does not fit.
    let n = serde_json::to_string(&out.content)
        .map(|s| s.len())
        .unwrap_or(0);
    out.content = json!([{"type": "text", "text": note(n)}]);
    out
}

/// A reply from the server: the JSON-RPC `result`, or an error message.
type Reply = std::result::Result<Value, String>;

struct Pending {
    waiting: HashMap<u64, oneshot::Sender<Reply>>,
    /// Set once the server has exited; nothing new is accepted.
    dead: bool,
}

/// The leader's exit, seen by the waiter thread.
struct ExitState {
    /// The leader has been reaped: its group id may be reused, so no more
    /// signals to it. Set under this lock, with the reap.
    reaped: bool,
}

/// One running `desktop-commander`.
struct Proc {
    pid: i32,
    /// Lines for its stdin. Taking this closes stdin.
    writer: Arc<Mutex<Option<mpsc::Sender<String>>>>,
    pending: Arc<Mutex<Pending>>,
    exit: Arc<(Mutex<ExitState>, Condvar)>,
    next_id: Arc<AtomicU64>,
}

impl Proc {
    fn spawn(cmd: &BridgeCommand, log: &Log, next_id: Arc<AtomicU64>) -> Result<Proc> {
        let mut child = Command::new(&cmd.node)
            .arg(&cmd.entry)
            .env("DESKTOP_COMMANDER_DISABLE_TELEMETRY", "1")
            .env("DC_FLAG_URL", "http://127.0.0.1:9/")
            .process_group(0)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::inherit())
            .spawn()
            .map_err(|e| format!("start desktop-commander ({}): {e}", cmd.node.display()))?;
        let pid = child.id() as i32;
        let stdin = child.stdin.take().expect("piped");
        let stdout = child.stdout.take().expect("piped");

        let (tx, rx) = mpsc::channel::<String>();
        let writer = Arc::new(Mutex::new(Some(tx)));
        let pending = Arc::new(Mutex::new(Pending {
            waiting: HashMap::new(),
            dead: false,
        }));
        let exit = Arc::new((Mutex::new(ExitState { reaped: false }), Condvar::new()));

        std::thread::spawn(move || write_loop(stdin, rx));
        {
            let pending = pending.clone();
            let writer = writer.clone();
            let log = log.clone();
            std::thread::spawn(move || read_loop(stdout, &pending, &writer, &log));
        }
        {
            let pending = pending.clone();
            let writer = writer.clone();
            let exit = exit.clone();
            let log = log.clone();
            std::thread::spawn(move || wait_loop(child, &pending, &writer, &exit, &log));
        }
        Ok(Proc {
            pid,
            writer,
            pending,
            exit,
            next_id,
        })
    }

    fn is_dead(&self) -> bool {
        self.pending.lock().unwrap().dead
    }

    fn send_line(&self, msg: &Value) -> bool {
        let line = msg.to_string();
        match self.writer.lock().unwrap().as_ref() {
            Some(tx) => tx.send(line).is_ok(),
            None => false,
        }
    }

    /// Sends a request; the reply arrives on the returned channel.
    fn request(&self, method: &str, params: Value) -> Result<(u64, oneshot::Receiver<Reply>)> {
        let id = self.next_id.fetch_add(1, Ordering::Relaxed);
        let (tx, rx) = oneshot::channel();
        {
            let mut p = self.pending.lock().unwrap();
            if p.dead {
                return Err("desktop-commander is not running".into());
            }
            p.waiting.insert(id, tx);
        }
        let msg = json!({"jsonrpc": "2.0", "id": id, "method": method, "params": params});
        if !self.send_line(&msg) {
            self.forget(id);
            return Err("desktop-commander is not running".into());
        }
        Ok((id, rx))
    }

    fn notify(&self, method: &str, params: Value) {
        self.send_line(&json!({"jsonrpc": "2.0", "method": method, "params": params}));
    }

    fn forget(&self, id: u64) {
        self.pending.lock().unwrap().waiting.remove(&id);
    }

    /// Blocking request, for start-up outside any runtime.
    fn request_blocking(&self, method: &str, params: Value, timeout: Duration) -> Reply {
        let (id, mut rx) = self.request(method, params)?;
        let deadline = Instant::now() + timeout;
        loop {
            match rx.try_recv() {
                Ok(reply) => return reply,
                Err(oneshot::error::TryRecvError::Closed) => {
                    return Err("desktop-commander stopped".into())
                }
                Err(oneshot::error::TryRecvError::Empty) if Instant::now() < deadline => {
                    std::thread::sleep(Duration::from_millis(5))
                }
                Err(oneshot::error::TryRecvError::Empty) => {
                    self.forget(id);
                    return Err(format!("desktop-commander did not answer {method} in time"));
                }
            }
        }
    }

    async fn request_async(&self, method: &str, params: Value, deadline: Instant) -> Reply {
        let (id, rx) = self.request(method, params)?;
        match tokio::time::timeout_at(tokio::time::Instant::from_std(deadline), rx).await {
            Ok(Ok(reply)) => reply,
            Ok(Err(_)) => Err("desktop-commander stopped".into()),
            Err(_) => {
                self.forget(id);
                self.notify(
                    "notifications/cancelled",
                    json!({"requestId": id, "reason": "deadline passed"}),
                );
                Err(format!("desktop-commander did not answer {method} in time"))
            }
        }
    }

    /// Waits until the leader has been reaped, at most `d`.
    fn wait_exit(&self, d: Duration) -> bool {
        let (lock, cv) = &*self.exit;
        let st = lock.lock().unwrap();
        let (st, _) = cv.wait_timeout_while(st, d, |s| !s.reaped).unwrap();
        st.reaped
    }

    /// Signals the whole group, unless the leader is already reaped (then
    /// the waiter has killed the group, and its id may belong to someone
    /// else).
    fn signal_group(&self, sig: i32) {
        let st = self.exit.0.lock().unwrap();
        if !st.reaped {
            kill_group(self.pid, sig);
        }
    }

    /// Close stdin, wait 2 s; SIGTERM the group, wait 2 s; SIGKILL it.
    fn stop(&self) {
        self.writer.lock().unwrap().take();
        if self.wait_exit(STOP_STEP) {
            return;
        }
        self.signal_group(libc::SIGTERM);
        if self.wait_exit(STOP_STEP) {
            return;
        }
        self.signal_group(libc::SIGKILL);
        self.wait_exit(STOP_STEP);
    }
}

fn kill_group(pgid: i32, sig: i32) {
    if pgid > 1 {
        // SAFETY: a plain syscall on a group we created; no memory is touched.
        unsafe {
            libc::kill(-pgid, sig);
        }
    }
}

fn write_loop(mut stdin: std::process::ChildStdin, rx: mpsc::Receiver<String>) {
    for line in rx {
        if stdin
            .write_all(line.as_bytes())
            .and_then(|_| stdin.write_all(b"\n"))
            .and_then(|_| stdin.flush())
            .is_err()
        {
            break;
        }
    }
    // Dropping stdin closes it.
}

fn cut_for_log(s: &str) -> String {
    let end = floor_boundary(s, MAX_LOG_LINE);
    if end < s.len() {
        format!("{}… ({} more bytes)", &s[..end], s.len() - end)
    } else {
        s.to_string()
    }
}

fn read_loop(
    stdout: std::process::ChildStdout,
    pending: &Mutex<Pending>,
    writer: &Mutex<Option<mpsc::Sender<String>>>,
    log: &Log,
) {
    let mut r = BufReader::new(stdout);
    let mut buf = Vec::new();
    loop {
        buf.clear();
        match r.read_until(b'\n', &mut buf) {
            Ok(0) | Err(_) => return,
            Ok(_) => {}
        }
        let line = String::from_utf8_lossy(&buf);
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        let Ok(msg) = serde_json::from_str::<Value>(line) else {
            log(&format!(
                "desktop-commander wrote a non-JSON line: {}",
                cut_for_log(line)
            ));
            continue;
        };
        let id = msg.get("id");
        match (msg.get("method").and_then(Value::as_str), id) {
            // A notification (`notifications/message` and the like): a log.
            (Some(method), None) => {
                let params = msg.get("params").map(Value::to_string).unwrap_or_default();
                log(&format!(
                    "desktop-commander {method}: {}",
                    cut_for_log(&params)
                ));
            }
            // A request from the server: we offer no client features.
            (Some(method), Some(id)) => {
                log(&format!("desktop-commander asked for {method}; refused"));
                let reply = json!({"jsonrpc": "2.0", "id": id,
                    "error": {"code": -32601, "message": "not supported by vrelay"}});
                if let Some(tx) = writer.lock().unwrap().as_ref() {
                    let _ = tx.send(reply.to_string());
                }
            }
            // A reply to one of ours.
            (None, Some(id)) => {
                let Some(id) = id.as_u64() else {
                    log("desktop-commander replied with an id we never sent");
                    continue;
                };
                let tx = pending.lock().unwrap().waiting.remove(&id);
                let reply = match (msg.get("result"), msg.get("error")) {
                    (Some(r), _) => Ok(r.clone()),
                    (None, Some(e)) => Err(e
                        .get("message")
                        .and_then(Value::as_str)
                        .map(str::to_string)
                        .unwrap_or_else(|| e.to_string())),
                    (None, None) => Err("desktop-commander sent an empty reply".into()),
                };
                if let Some(tx) = tx {
                    let _ = tx.send(reply);
                }
            }
            (None, None) => {
                log(&format!("desktop-commander sent: {}", cut_for_log(line)));
            }
        }
    }
}

/// Has `pid` exited? Blocks until it has, leaving the zombie in place
/// (`WNOWAIT`), so the group id cannot be reused before the group is killed.
fn wait_exited_no_reap(pid: i32) {
    loop {
        // SAFETY: `info` is plain zeroed memory that waitid fills in.
        let ret = unsafe {
            let mut info: libc::siginfo_t = std::mem::zeroed();
            libc::waitid(
                libc::P_PID,
                pid as libc::id_t,
                &mut info,
                libc::WEXITED | libc::WNOWAIT,
            )
        };
        if ret == 0 {
            return;
        }
        if std::io::Error::last_os_error().raw_os_error() != Some(libc::EINTR) {
            return;
        }
    }
}

fn wait_loop(
    mut child: Child,
    pending: &Mutex<Pending>,
    writer: &Mutex<Option<mpsc::Sender<String>>>,
    exit: &(Mutex<ExitState>, Condvar),
    log: &Log,
) {
    let pid = child.id() as i32;
    wait_exited_no_reap(pid);
    let status = {
        let mut st = exit.0.lock().unwrap();
        // Whatever it started dies with it, then the leader is reaped.
        kill_group(pid, libc::SIGKILL);
        let status = child.wait();
        st.reaped = true;
        status
    };
    writer.lock().unwrap().take();
    let waiting = {
        let mut p = pending.lock().unwrap();
        p.dead = true;
        std::mem::take(&mut p.waiting)
    };
    if !waiting.is_empty() {
        log(&format!(
            "desktop-commander exited ({}) with {} call(s) in flight; it restarts on the next call",
            status
                .map(|s| s.to_string())
                .unwrap_or_else(|e| e.to_string()),
            waiting.len()
        ));
    }
    for (_, tx) in waiting {
        let _ = tx.send(Err(
            "desktop-commander stopped during this call; it restarts on the next one".into(),
        ));
    }
    exit.1.notify_all();
}

fn initialize_params() -> Value {
    json!({
        "protocolVersion": PROTOCOL_VERSION,
        "capabilities": {},
        "clientInfo": {"name": "vrelay", "version": env!("CARGO_PKG_VERSION")},
    })
}

fn parse_tools(list: &Value) -> Vec<ToolDef> {
    list.get("tools")
        .and_then(Value::as_array)
        .map(|ts| {
            ts.iter()
                .filter_map(|t| {
                    Some(ToolDef {
                        name: t.get("name")?.as_str()?.to_string(),
                        description: t
                            .get("description")
                            .and_then(Value::as_str)
                            .unwrap_or_default()
                            .to_string(),
                        input_schema: t
                            .get("inputSchema")
                            .cloned()
                            .unwrap_or_else(|| json!({"type": "object"})),
                    })
                })
                .collect()
        })
        .unwrap_or_default()
}

/// Appends one page of `tools/list` to `all`; returns the next cursor.
fn add_page(all: &mut Vec<Value>, page: &Value) -> Option<String> {
    if let Some(ts) = page.get("tools").and_then(Value::as_array) {
        all.extend(ts.iter().cloned());
    }
    page.get("nextCursor")
        .and_then(Value::as_str)
        .filter(|c| !c.is_empty())
        .map(str::to_string)
}

const MAX_PAGES: usize = 50;

fn cursor_params(cursor: &Option<String>) -> Value {
    match cursor {
        Some(c) => json!({"cursor": c}),
        None => json!({}),
    }
}

/// `desktop-commander` over stdio. Restarts on the next call after it dies.
pub struct Bridge {
    cmd: BridgeCommand,
    log: Log,
    proc: tokio::sync::Mutex<Option<Arc<Proc>>>,
    /// The last tool list seen, for when a fresh one cannot be had.
    tools: Mutex<Vec<ToolDef>>,
    next_id: Arc<AtomicU64>,
    pid: AtomicI32,
}

impl Bridge {
    /// Checks Node, makes `~/.claude-server-commander` private, starts
    /// `desktop-commander`, and does the MCP handshake. Logs go to stderr.
    pub fn start(cmd: &BridgeCommand) -> Result<Bridge> {
        Bridge::start_with_log(cmd, stderr_log())
    }

    pub fn start_with_log(cmd: &BridgeCommand, log: Log) -> Result<Bridge> {
        check_node(&cmd.node)?;
        if let Some(home) = std::env::var_os("HOME") {
            secure_dc_config_dir(Path::new(&home))?;
        }
        let next_id = Arc::new(AtomicU64::new(1));
        let proc = Arc::new(Proc::spawn(cmd, &log, next_id.clone())?);
        let started = (|| -> Result<Vec<ToolDef>> {
            proc.request_blocking("initialize", initialize_params(), INIT_TIMEOUT)?;
            proc.notify("notifications/initialized", json!({}));
            let mut all = Vec::new();
            let mut cursor = None;
            for _ in 0..MAX_PAGES {
                let page =
                    proc.request_blocking("tools/list", cursor_params(&cursor), LIST_TIMEOUT)?;
                cursor = add_page(&mut all, &page);
                if cursor.is_none() {
                    break;
                }
            }
            Ok(parse_tools(&json!({"tools": all})))
        })();
        let tools = match started {
            Ok(t) => t,
            Err(e) => {
                proc.stop();
                return Err(format!("desktop-commander did not start: {e}"));
            }
        };
        Ok(Bridge {
            cmd: cmd.clone(),
            log,
            pid: AtomicI32::new(proc.pid),
            proc: tokio::sync::Mutex::new(Some(proc)),
            tools: Mutex::new(tools),
            next_id,
        })
    }

    /// The running server, starting a fresh one if the last one died.
    async fn running(&self) -> Result<Arc<Proc>> {
        let mut slot = self.proc.lock().await;
        if let Some(p) = slot.as_ref() {
            if !p.is_dead() {
                return Ok(p.clone());
            }
        }
        (self.log)("starting desktop-commander again");
        let p = Arc::new(Proc::spawn(&self.cmd, &self.log, self.next_id.clone())?);
        let init = p
            .request_async(
                "initialize",
                initialize_params(),
                Instant::now() + INIT_TIMEOUT,
            )
            .await;
        if let Err(e) = init {
            let dead = p.clone();
            tokio::task::spawn_blocking(move || dead.stop());
            return Err(format!("desktop-commander did not start: {e}"));
        }
        p.notify("notifications/initialized", json!({}));
        self.pid.store(p.pid, Ordering::Relaxed);
        *slot = Some(p.clone());
        Ok(p)
    }

    /// `desktop-commander`'s own `tools/list` result, unfiltered (all pages
    /// joined into one `tools` array).
    pub async fn tools_raw(&self) -> Result<Value> {
        let p = self.running().await?;
        let mut all = Vec::new();
        let mut cursor = None;
        for _ in 0..MAX_PAGES {
            let page = p
                .request_async(
                    "tools/list",
                    cursor_params(&cursor),
                    Instant::now() + LIST_TIMEOUT,
                )
                .await?;
            cursor = add_page(&mut all, &page);
            if cursor.is_none() {
                break;
            }
        }
        Ok(json!({"tools": all}))
    }

    /// Every tool `desktop-commander` offers, unfiltered (the caller applies
    /// the rules). If it cannot answer, the last list seen.
    pub async fn tools(&self) -> Vec<ToolDef> {
        match self.tools_raw().await {
            Ok(raw) => {
                let tools = parse_tools(&raw);
                *self.tools.lock().unwrap() = tools.clone();
                tools
            }
            Err(e) => {
                (self.log)(&format!("tools/list failed, using the last list: {e}"));
                self.tools.lock().unwrap().clone()
            }
        }
    }

    /// Runs one tool. Never fails as such: a crash, a timeout or a refusal
    /// comes back as an error result. The output is cut to fit one frame.
    pub async fn call(&self, tool: &str, args: Value, deadline: Instant) -> BridgeOutput {
        let p = match self.running().await {
            Ok(p) => p,
            Err(e) => return BridgeOutput::error(e),
        };
        let reply = p
            .request_async(
                "tools/call",
                json!({"name": tool, "arguments": args}),
                deadline,
            )
            .await;
        match reply {
            Ok(result) => fit_to_frame(BridgeOutput::from_result(&result)),
            Err(e) => fit_to_frame(BridgeOutput::error(e)),
        }
    }

    /// The running server's process id (its group id too), if any.
    pub fn pid(&self) -> Option<i32> {
        Some(self.pid.load(Ordering::Relaxed)).filter(|p| *p > 0)
    }

    /// Stops `desktop-commander` and everything it started: close stdin,
    /// wait 2 s, SIGTERM the group, wait 2 s, SIGKILL it. Blocks for up to
    /// about 6 s; from async code, call it on a blocking thread.
    pub fn stop(mut self) {
        if let Some(p) = self.proc.get_mut().take() {
            p.stop();
        }
    }
}

impl Drop for Bridge {
    /// Dropped without `stop` (a panic, an early return): kill the group at
    /// once rather than leave commands running.
    fn drop(&mut self) {
        if let Some(p) = self.proc.get_mut().take() {
            p.writer.lock().unwrap().take();
            p.signal_group(libc::SIGKILL);
        }
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    use crate::state::test_dir;
    use serde_json::json;
    use std::os::unix::fs::PermissionsExt;
    use std::sync::Mutex as StdMutex;

    fn runfile(rel: &str) -> PathBuf {
        let base = std::env::var("TEST_SRCDIR").expect("run under bazel test");
        PathBuf::from(base).join("_main").join(rel)
    }

    /// The fake server as the "node", and the test's folder as its entry.
    fn fake(name: &str) -> (BridgeCommand, PathBuf) {
        let dir = test_dir(name);
        std::fs::create_dir_all(&dir).unwrap();
        let cmd = BridgeCommand {
            node: runfile("apps/suites/vitruvian-relay/connector/fake_mcp"),
            entry: dir.clone(),
        };
        (cmd, dir)
    }

    fn logged() -> (Log, Arc<StdMutex<Vec<String>>>) {
        let lines = Arc::new(StdMutex::new(Vec::new()));
        let l2 = lines.clone();
        let log: Log = Arc::new(move |s: &str| l2.lock().unwrap().push(s.to_string()));
        (log, lines)
    }

    fn soon() -> Instant {
        Instant::now() + Duration::from_secs(20)
    }

    fn text_of(out: &BridgeOutput) -> String {
        out.content[0]["text"]
            .as_str()
            .unwrap_or_default()
            .to_string()
    }

    fn read_pid(dir: &Path, file: &str) -> i32 {
        for _ in 0..100 {
            if let Ok(t) = std::fs::read_to_string(dir.join(file)) {
                if let Ok(p) = t.trim().parse() {
                    return p;
                }
            }
            std::thread::sleep(Duration::from_millis(50));
        }
        panic!("no {file}");
    }

    fn pid_gone(pid: i32) -> bool {
        for _ in 0..60 {
            // SAFETY: signal 0 only checks that the process exists.
            if unsafe { libc::kill(pid, 0) } != 0 {
                return true;
            }
            std::thread::sleep(Duration::from_millis(50));
        }
        false
    }

    #[tokio::test]
    async fn lists_tools() {
        let (cmd, _dir) = fake("b-list");
        let b = Bridge::start(&cmd).unwrap();
        let tools = b.tools().await;
        let names: Vec<_> = tools.iter().map(|t| t.name.as_str()).collect();
        assert_eq!(names, ["echo", "set_config_value", "start_process"]);
        assert_eq!(
            tools[2].input_schema["properties"]["command"]["type"],
            "string"
        );
        // It was started with telemetry off and the flag fetch pointed at a
        // closed local port (the fake echoes both in a description).
        assert_eq!(tools[0].description, "env 1 http://127.0.0.1:9/");
        let raw = b.tools_raw().await.unwrap();
        assert_eq!(raw["tools"].as_array().unwrap().len(), 3);
        let out = b.call("echo", json!({}), soon()).await;
        assert!(!out.is_error && !out.truncated);
        assert_eq!(text_of(&out), "ok");
        b.stop();
    }

    #[tokio::test]
    async fn notifications_are_logged_not_returned() {
        let (cmd, _dir) = fake("b-notify");
        let (log, lines) = logged();
        let b = Bridge::start_with_log(&cmd, log).unwrap();
        let out = b.call("notify", json!({}), soon()).await;
        assert_eq!(text_of(&out), "after note");
        assert!(!out.is_error);
        let lines = lines.lock().unwrap().clone();
        assert!(
            lines.iter().any(|l| l.contains("working on it")),
            "{lines:?}"
        );
        assert!(
            lines.iter().any(|l| l.contains("fake started")),
            "{lines:?}"
        );
        b.stop();
    }

    #[tokio::test]
    async fn json_rpc_error_is_an_error_result() {
        let (cmd, _dir) = fake("b-fail");
        let b = Bridge::start(&cmd).unwrap();
        let out = b.call("fail", json!({}), soon()).await;
        assert!(out.is_error);
        assert!(text_of(&out).contains("it broke"), "{}", text_of(&out));
        b.stop();
    }

    #[tokio::test]
    async fn crash_kills_group_and_restarts() {
        let (cmd, dir) = fake("b-crash");
        let b = Bridge::start(&cmd).unwrap();
        let first = read_pid(&dir, "fake.pid");
        let call = b.call("hang", json!({}), soon());
        let killer = async {
            let sleep_pid = loop {
                if let Ok(t) = std::fs::read_to_string(dir.join("sleep.pid")) {
                    if let Ok(p) = t.trim().parse::<i32>() {
                        break p;
                    }
                }
                tokio::time::sleep(Duration::from_millis(20)).await;
            };
            // SAFETY: plain signal to the fake server we started.
            unsafe { libc::kill(first, libc::SIGKILL) };
            sleep_pid
        };
        let t = Instant::now();
        let (out, sleep_pid) = tokio::join!(call, killer);
        assert!(out.is_error, "{out:?}");
        assert!(t.elapsed() < Duration::from_secs(5), "{:?}", t.elapsed());
        // The command the fake had started died with its group.
        assert!(pid_gone(sleep_pid), "sleep {sleep_pid} outlived the crash");
        // The next call starts a fresh server and works.
        let out = b.call("echo", json!({}), soon()).await;
        assert!(!out.is_error, "{out:?}");
        assert_eq!(text_of(&out), "ok");
        assert_ne!(read_pid(&dir, "fake.pid"), first);
        b.stop();
    }

    #[tokio::test]
    async fn exit_on_its_own_fails_the_call_and_restarts() {
        let (cmd, _dir) = fake("b-exit");
        let b = Bridge::start(&cmd).unwrap();
        let out = b.call("exit", json!({}), soon()).await;
        assert!(out.is_error, "{out:?}");
        let out = b.call("echo", json!({}), soon()).await;
        assert_eq!(text_of(&out), "ok");
        b.stop();
    }

    #[tokio::test]
    async fn deadline_fails_the_call_without_killing_the_server() {
        let (cmd, dir) = fake("b-deadline");
        let b = Bridge::start(&cmd).unwrap();
        let pid = read_pid(&dir, "fake.pid");
        let t = Instant::now();
        let out = b
            .call(
                "hang",
                json!({}),
                Instant::now() + Duration::from_millis(300),
            )
            .await;
        assert!(out.is_error && text_of(&out).contains("time"), "{out:?}");
        assert!(t.elapsed() < Duration::from_secs(3));
        let out = b.call("echo", json!({}), soon()).await;
        assert_eq!(text_of(&out), "ok");
        assert_eq!(read_pid(&dir, "fake.pid"), pid);
        b.stop();
    }

    #[tokio::test]
    async fn stop_kills_children() {
        let (cmd, dir) = fake("b-stop");
        let b = Bridge::start(&cmd).unwrap();
        let out = b.call("spawn", json!({}), soon()).await;
        assert_eq!(text_of(&out), "spawned");
        let sleep_pid = read_pid(&dir, "sleep.pid");
        let fake_pid = read_pid(&dir, "fake.pid");
        let t = Instant::now();
        b.stop();
        // Closing stdin is enough for a well-behaved server.
        assert!(t.elapsed() < Duration::from_secs(2), "{:?}", t.elapsed());
        assert!(pid_gone(fake_pid), "server outlived stop");
        assert!(pid_gone(sleep_pid), "child {sleep_pid} outlived stop");
    }

    #[tokio::test]
    async fn stop_escalates_when_the_server_ignores_stdin_and_term() {
        let (cmd, dir) = fake("b-stubborn");
        std::fs::write(dir.join("stubborn"), "").unwrap();
        let b = Bridge::start(&cmd).unwrap();
        let out = b.call("spawn", json!({}), soon()).await;
        assert_eq!(text_of(&out), "spawned");
        let sleep_pid = read_pid(&dir, "sleep.pid");
        let fake_pid = read_pid(&dir, "fake.pid");
        let t = Instant::now();
        b.stop();
        // 2 s for stdin, 2 s for SIGTERM, then SIGKILL.
        let took = t.elapsed();
        assert!(took >= Duration::from_secs(4), "{took:?}");
        assert!(took < Duration::from_secs(7), "{took:?}");
        assert!(pid_gone(fake_pid), "server outlived stop");
        assert!(pid_gone(sleep_pid), "child {sleep_pid} outlived stop");
    }

    #[tokio::test]
    async fn oversized_result_is_truncated_with_note() {
        let (cmd, _dir) = fake("b-big");
        let b = Bridge::start(&cmd).unwrap();
        let out = b.call("big", json!({}), soon()).await;
        assert!(out.truncated, "not marked truncated");
        assert!(!out.is_error);
        let text = text_of(&out);
        // The raw text (3,000,000 characters) was under 4 MiB; escaped, it
        // was not. The frame Task 8 sends is what has to fit.
        assert!(text.len() < 3_000_000, "{}", text.len());
        assert!(text.len() > 1_000_000, "cut far too much: {}", text.len());
        assert!(text.starts_with("\"\n\"\n"), "{:?}", &text[..8]);
        let note = text.rsplit("\n").next().unwrap();
        assert!(
            note.starts_with("[output truncated by vrelay: ") && note.ends_with(" bytes omitted]"),
            "{note:?}"
        );
        let omitted: usize = note
            .trim_start_matches("[output truncated by vrelay: ")
            .trim_end_matches(" bytes omitted]")
            .parse()
            .unwrap();
        assert_eq!(omitted, 3_000_000 - text.len() + note.len() + 1);
        let frame = ToRelay::Result(CallResult {
            call_id: "c".repeat(CALL_ID_RESERVE),
            content: out.content.clone(),
            is_error: out.is_error,
            truncated: out.truncated,
        });
        let encoded = encode(&frame).expect("frame fits");
        assert!(encoded.len() <= MAX_FRAME_BYTES);
        b.stop();
    }

    #[test]
    fn fit_leaves_small_output_alone_and_drops_big_non_text() {
        let small = BridgeOutput {
            content: json!([{"type": "text", "text": "hi"}]),
            is_error: false,
            truncated: false,
        };
        assert_eq!(fit_to_frame(small.clone()), small);
        // An image too big for a frame is replaced by a note.
        let img = BridgeOutput {
            content: json!([
                {"type": "text", "text": "a picture"},
                {"type": "image", "mimeType": "image/png", "data": "A".repeat(MAX_FRAME_BYTES)}
            ]),
            is_error: false,
            truncated: false,
        };
        let out = fit_to_frame(img);
        assert!(out.truncated);
        let s = serde_json::to_string(&out.content).unwrap();
        assert!(s.len() < MAX_FRAME_BYTES);
        assert!(s.contains("[output truncated by vrelay: "), "{s}");
        assert_eq!(out.content[0]["text"], "a picture");
    }

    #[test]
    fn old_node_is_refused() {
        let dir = test_dir("b-oldnode");
        std::fs::create_dir_all(&dir).unwrap();
        let node = dir.join("node");
        std::fs::write(&node, "#!/bin/sh\necho v22.11.9\n").unwrap();
        std::fs::set_permissions(&node, std::fs::Permissions::from_mode(0o755)).unwrap();
        let cmd = BridgeCommand {
            node: node.clone(),
            entry: dir.join("never-started.js"),
        };
        let err = Bridge::start(&cmd).err().expect("old node accepted");
        assert!(err.contains("22.12"), "{err}");
        assert!(err.contains("v22.11.9"), "{err}");
        assert!(err.contains("nodejs.org"), "{err}");
        // Missing node: same advice.
        let cmd = BridgeCommand {
            node: dir.join("no-such-node"),
            entry: dir.join("never-started.js"),
        };
        let err = Bridge::start(&cmd).err().expect("missing node accepted");
        assert!(err.contains("22.12") && err.contains("nodejs.org"), "{err}");
        // Versions are compared as numbers, not text.
        assert_eq!(parse_node_version("v22.12.0"), Some((22, 12)));
        assert_eq!(parse_node_version("v26.1.3\n"), Some((26, 1)));
        assert_eq!(parse_node_version("v9.99.0"), Some((9, 99)));
        assert_eq!(parse_node_version("nope"), None);
        assert!(node_ok("v22.12.0") && node_ok("v23.0.0") && node_ok("v100.0.0"));
        assert!(!node_ok("v22.11.0") && !node_ok("v9.99.0") && !node_ok("junk"));
    }

    #[test]
    fn dc_config_dir_is_0700() {
        let home = test_dir("b-dcdir");
        std::fs::create_dir_all(&home).unwrap();
        let mode = |p: &Path| std::fs::metadata(p).unwrap().permissions().mode() & 0o777;
        // Created private when missing.
        secure_dc_config_dir(&home).unwrap();
        let d = home.join(".claude-server-commander");
        assert_eq!(mode(&d), 0o700);
        // Tightened when desktop-commander made it with the usual 0755.
        std::fs::set_permissions(&d, std::fs::Permissions::from_mode(0o755)).unwrap();
        secure_dc_config_dir(&home).unwrap();
        assert_eq!(mode(&d), 0o700);
        // Several starts at once (or desktop-commander making it meanwhile)
        // all succeed.
        let race = test_dir("b-dcdir-race");
        std::fs::create_dir_all(&race).unwrap();
        let handles: Vec<_> = (0..8)
            .map(|_| {
                let r = race.clone();
                std::thread::spawn(move || secure_dc_config_dir(&r))
            })
            .collect();
        for h in handles {
            h.join().unwrap().unwrap();
        }
        assert_eq!(mode(&race.join(".claude-server-commander")), 0o700);
        // A file in the way is an error, not something to chmod.
        let clash = test_dir("b-dcdir-file");
        std::fs::create_dir_all(&clash).unwrap();
        std::fs::write(clash.join(".claude-server-commander"), "").unwrap();
        assert!(secure_dc_config_dir(&clash).is_err());
        // Its call log keeps its own mode; nobody else can reach it anyway.
        std::fs::write(d.join("claude_tool_call.log"), "x").unwrap();
        secure_dc_config_dir(&home).unwrap();
        assert_eq!(mode(&d), 0o700);
    }

    /// The saved tool list (what the prompt and rules tests check against)
    /// is for the version actually pinned. A bump fails here until
    /// `vrelay tools --raw` is saved again for it. Reading the manifest also
    /// makes a change under dc/ run these tests in CI.
    #[test]
    fn pinned_package_matches_the_saved_tool_list() {
        let pkg: Value = serde_json::from_str(
            &std::fs::read_to_string(runfile(
                "apps/suites/vitruvian-relay/connector/dc/package.json",
            ))
            .unwrap(),
        )
        .unwrap();
        let deps = pkg["dependencies"].as_object().unwrap();
        assert_eq!(deps.len(), 1, "{deps:?}");
        assert_eq!(deps["@wonderwhy-er/desktop-commander"], "0.3.1");
        assert!(
            runfile("apps/suites/vitruvian-relay/connector/testdata/dc-0.3.1-tools.json").is_file()
        );
    }

    #[test]
    fn locate_prefers_runfiles_under_bazel_run_and_bridge_json_otherwise() {
        let home = test_dir("b-locate");
        let rf = home.join("runfiles");
        let entry = rf.join(DC_RUNFILE);
        std::fs::create_dir_all(entry.parent().unwrap()).unwrap();
        std::fs::write(&entry, "").unwrap();
        let path_dir = home.join("bin");
        std::fs::create_dir_all(&path_dir).unwrap();
        let node = path_dir.join("node");
        std::fs::write(&node, "#!/bin/sh\n").unwrap();
        std::fs::set_permissions(&node, std::fs::Permissions::from_mode(0o755)).unwrap();
        let path = format!("/nonexistent:{}", path_dir.display());
        // Under bazel run: the pinned package and the node on PATH.
        let c = locate_from(&home, true, std::slice::from_ref(&rf), Some(&path)).unwrap();
        assert_eq!(c.entry, entry);
        assert_eq!(c.node, node);
        // Installed: bridge.json, written by the installer.
        let bj = home.join(".local/share/vrelay/bridge.json");
        std::fs::create_dir_all(bj.parent().unwrap()).unwrap();
        std::fs::write(
            &bj,
            r#"{"node": "/opt/n/bin/node", "entry": "/opt/dc/dist/index.js"}"#,
        )
        .unwrap();
        let c = locate_from(&home, false, std::slice::from_ref(&rf), Some(&path)).unwrap();
        assert_eq!(c.node, PathBuf::from("/opt/n/bin/node"));
        assert_eq!(c.entry, PathBuf::from("/opt/dc/dist/index.js"));
        // Neither: an error that says what to do.
        std::fs::remove_file(&bj).unwrap();
        let err = locate_from(&home, false, &[], Some(&path)).unwrap_err();
        assert!(err.contains("bridge.json"), "{err}");
        // A broken bridge.json is an error, not a silent fallback.
        std::fs::write(&bj, "{").unwrap();
        assert!(locate_from(&home, false, &[rf], Some(&path)).is_err());
    }
}
