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
//! What testing desktop-commander found (spike D of
//! docs/superpowers/plans/2026-11-09-relay-p0-spikes.md), built in here:
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
use std::ffi::OsString;
use std::io::{BufRead, BufReader, Read, Write};
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::mpsc;
use std::sync::{Arc, Condvar, Mutex};
use std::time::{Duration, Instant};

use serde_json::{json, Value};
use tokio::sync::{oneshot, watch};
use vitruvian_relay_protocol::{encode, CallResult, FrameError, ToRelay, ToolDef, MAX_FRAME_BYTES};

use crate::proc::{kill_group, may_kill_group_after};
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

/// desktop-commander 0.3.1's integrity, as pinned and tested in spike D
/// (docs/superpowers/plans/2026-11-09-relay-p0-spikes.md).
pub const DC_INTEGRITY: &str = "sha512-cx7KTscLF951adHmDLVCDIVTqJ/Bg1LtdRILZoo5wa/UMeyOfMAuOJOEBulNMKBKb5Xd3nHDQnB9aXroN9Fw5A==";

/// Longest line read from desktop-commander's stdout. A reply over 4 MiB is
/// cut to fit a frame anyway, and a JSON line is about the size of the frame
/// it becomes (both escape the same characters), so keeping more than 4x the
/// frame buys nothing. A longer line is read through and dropped, never held
/// whole: memory per line stays under twice this.
pub const MAX_LINE: usize = 4 * MAX_FRAME_BYTES;

/// How long `node --version` may take (a version-manager shim can hang).
const NODE_VERSION_TIMEOUT: Duration = Duration::from_secs(10);
const INIT_TIMEOUT: Duration = Duration::from_secs(30);
const LIST_TIMEOUT: Duration = Duration::from_secs(30);
/// Each step of `stop`: after closing stdin, after SIGTERM.
const STOP_STEP: Duration = Duration::from_secs(2);

/// The bridge's limits. Production uses [`Limits::default`]; tests shrink
/// them so the same code paths run in a fraction of the time.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct Limits {
    pub max_line: usize,
    pub init_timeout: Duration,
    pub stop_step: Duration,
}

impl Default for Limits {
    fn default() -> Limits {
        Limits {
            max_line: MAX_LINE,
            init_timeout: INIT_TIMEOUT,
            stop_step: STOP_STEP,
        }
    }
}
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
        let home = dc_home(std::env::var_os("HOME"))?;
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

/// The first executable `name` in a `PATH`-style list.
pub fn find_on_path(name: &str, path: Option<&str>) -> Option<PathBuf> {
    all_on_path(name, path).into_iter().next()
}

/// Every executable `name` in a `PATH`-style list, in order, each once.
pub fn all_on_path(name: &str, path: Option<&str>) -> Vec<PathBuf> {
    use std::os::unix::fs::PermissionsExt;
    let mut found: Vec<PathBuf> = Vec::new();
    for d in path.unwrap_or("").split(':').filter(|d| !d.is_empty()) {
        let p = Path::new(d).join(name);
        let ok = std::fs::metadata(&p)
            .map(|m| m.is_file() && m.permissions().mode() & 0o111 != 0)
            .unwrap_or(false);
        if ok && !found.contains(&p) {
            found.push(p);
        }
    }
    found
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

/// An error, saying how to get one, unless `node` is Node 22.12 or newer.
pub fn check_node(node: &Path) -> Result<()> {
    check_node_with(node, NODE_VERSION_TIMEOUT)
}

/// Runs `node --version` for at most `timeout` ([`crate::proc::output_within`]:
/// its own process group, killed past that).
fn check_node_with(node: &Path, timeout: Duration) -> Result<()> {
    let out = crate::proc::output_within(Command::new(node).arg("--version"), timeout, 256)
        .map_err(|e| format!("cannot run {}: {e}. {NODE_ADVICE}", node.display()))?
        .ok_or_else(|| {
            format!(
                "{} --version did not answer in {} s. {NODE_ADVICE}",
                node.display(),
                timeout.as_secs_f32()
            )
        })?;
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

/// The home folder desktop-commander will use, found the way Node's
/// `os.homedir()` finds it: `HOME`, else the user database.
pub fn dc_home(env_home: Option<OsString>) -> Result<PathBuf> {
    if let Some(h) = env_home.filter(|h| !h.is_empty()) {
        return Ok(PathBuf::from(h));
    }
    // SAFETY: getpwuid returns static storage or null; it is read at once.
    let dir = unsafe {
        let pw = libc::getpwuid(libc::getuid());
        if pw.is_null() || (*pw).pw_dir.is_null() {
            None
        } else {
            Some(
                std::ffi::CStr::from_ptr((*pw).pw_dir)
                    .to_string_lossy()
                    .into_owned(),
            )
        }
    };
    dir.filter(|d| !d.is_empty())
        .map(PathBuf::from)
        .ok_or_else(|| "cannot find the home folder: HOME is not set and the user has none".into())
}

/// Makes `HOME/.claude-server-commander` mode 0700, creating it if missing.
/// `desktop-commander`'s call log there records every call's full arguments.
pub fn secure_dc_config_dir(home: &Path) -> Result<()> {
    crate::state::ensure_private_dir(&home.join(DC_CONFIG_DIR))
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

    fn from_result(mut result: Value) -> BridgeOutput {
        BridgeOutput {
            content: result
                .get_mut("content")
                .map(Value::take)
                .unwrap_or_else(|| json!([])),
            is_error: result
                .get("isError")
                .and_then(Value::as_bool)
                .unwrap_or(false),
            truncated: false,
        }
    }
}

/// The encoded size of the `result` frame for `out`, measured with
/// `protocol::encode` on the real frame type. The content is moved in and
/// back out, never copied.
fn frame_len(out: &mut BridgeOutput) -> usize {
    let frame = ToRelay::Result(CallResult {
        call_id: "c".repeat(CALL_ID_RESERVE),
        content: out.content.take(),
        is_error: out.is_error,
        truncated: out.truncated,
    });
    let n = match encode(&frame) {
        Ok(s) => s.len(),
        Err(FrameError::TooLarge(n)) => n,
        // Cannot happen for a Value; treat as far too big.
        Err(FrameError::Json(_)) => usize::MAX / 2,
    };
    if let ToRelay::Result(r) = frame {
        out.content = r.content;
    }
    n
}

/// How many bytes `c` takes inside a JSON string, as serde_json writes it.
fn json_char_len(c: char) -> usize {
    match c {
        '"' | '\\' | '\n' | '\r' | '\t' | '\u{8}' | '\u{c}' => 2,
        c if (c as u32) < 0x20 => 6,
        c => c.len_utf8(),
    }
}

/// The encoded length of `s` as a JSON string, quotes included.
fn json_str_len(s: &str) -> usize {
    2 + s.chars().map(json_char_len).sum::<usize>()
}

/// Writes nothing; counts what serde_json would write.
struct Count(usize);
impl Write for Count {
    fn write(&mut self, b: &[u8]) -> std::io::Result<usize> {
        self.0 += b.len();
        Ok(b.len())
    }
    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}

fn encoded_len(v: &Value) -> usize {
    let mut c = Count(0);
    let _ = serde_json::to_writer(&mut c, v);
    c.0
}

fn note(omitted: usize) -> String {
    format!("[output truncated by vrelay: {omitted} bytes omitted]")
}

/// Room left for the line break and note after a cut text (the note is
/// under 64 bytes for any size that fits in memory).
const NOTE_ROOM: usize = 2 + 64;

fn floor_boundary(s: &str, mut i: usize) -> usize {
    i = i.min(s.len());
    while !s.is_char_boundary(i) {
        i -= 1;
    }
    i
}

/// Cuts `text` in place so its encoded form shrinks by at least `need`
/// bytes (or to nothing), keeping whole characters. Returns the bytes of
/// the original text that were dropped.
fn cut_text(text: &mut String, need: usize) -> usize {
    let target = json_str_len(text).saturating_sub(need + NOTE_ROOM);
    let mut enc = 2;
    let mut keep = 0;
    for (i, c) in text.char_indices() {
        let n = json_char_len(c);
        if enc + n > target {
            break;
        }
        enc += n;
        keep = i + c.len_utf8();
    }
    let keep = floor_boundary(text, keep);
    let omitted = text.len() - keep;
    text.truncate(keep);
    omitted
}

/// Cuts `out` until its encoded `result` frame fits in `MAX_FRAME_BYTES`.
///
/// The size is measured on the encoded frame, not the raw text: JSON escaping
/// can double it (`"` and line breaks) or worse. The overshoot is shared out
/// from the biggest item down, each text cut by exactly what it must give up
/// (escaping counted), ending with a note of how many bytes were dropped; an
/// item that is not text (an image) is replaced by a note. One encode per
/// pass; the second pass is a check.
pub fn fit_to_frame(mut out: BridgeOutput) -> BridgeOutput {
    let total = frame_len(&mut out);
    if total <= MAX_FRAME_BYTES {
        return out;
    }
    out.truncated = true;
    if !out.content.is_array() {
        out.content = json!([out.content.take()]);
    }
    let original = encoded_len(&out.content);
    // Bytes already dropped from each text item, by index.
    let mut dropped: HashMap<usize, usize> = HashMap::new();
    let mut over = total - MAX_FRAME_BYTES;
    let passes = out.content.as_array().map_or(0, Vec::len) + 2;
    for _ in 0..passes {
        let items = out.content.as_array_mut().expect("made an array above");
        // Biggest first.
        let mut order: Vec<(usize, usize)> = items
            .iter()
            .enumerate()
            .map(|(i, v)| (i, encoded_len(v)))
            .collect();
        order.sort_by_key(|o| std::cmp::Reverse(o.1));
        let mut need = over;
        for (i, size) in order {
            if need == 0 {
                break;
            }
            let item = &mut items[i];
            let is_text = item.get("type").and_then(Value::as_str) == Some("text")
                && item.get("text").is_some_and(Value::is_string);
            if is_text {
                let Some(Value::String(t)) = item.get_mut("text") else {
                    unreachable!()
                };
                // Take off an earlier note before cutting again.
                let prior = dropped.get(&i).copied().unwrap_or(0);
                if prior > 0 {
                    if let Some(pos) = t.rfind('\n') {
                        t.truncate(pos);
                    }
                }
                let before = json_str_len(t);
                let cut = cut_text(t, need);
                let total_dropped = prior + cut;
                if total_dropped > 0 {
                    t.push('\n');
                    t.push_str(&note(total_dropped));
                    dropped.insert(i, total_dropped);
                }
                let after = json_str_len(t);
                need = need.saturating_sub(before.saturating_sub(after));
            } else if size > NOTE_ROOM + 32 {
                *item = json!({"type": "text", "text": note(size)});
                need = need.saturating_sub(size - encoded_len(item));
            }
        }
        let n = frame_len(&mut out);
        if n <= MAX_FRAME_BYTES {
            return out;
        }
        over = n - MAX_FRAME_BYTES;
    }
    // Unreachable in practice; never send a frame that does not fit.
    out.content = json!([{"type": "text", "text": note(original)}]);
    out
}

/// Why a request got no usable `result`.
#[derive(Debug)]
enum Fail {
    Msg(String),
    /// The reply line was this many bytes, over the cap (the second
    /// number, [`MAX_LINE`] in production); none was kept.
    TooBig(usize, usize),
}

impl From<String> for Fail {
    fn from(s: String) -> Fail {
        Fail::Msg(s)
    }
}

impl From<&str> for Fail {
    fn from(s: &str) -> Fail {
        Fail::Msg(s.into())
    }
}

impl std::fmt::Display for Fail {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Fail::Msg(m) => f.write_str(m),
            Fail::TooBig(n, cap) => write!(
                f,
                "desktop-commander's reply was {n} bytes, over vrelay's {} MiB limit for one \
                 message, so none of it was kept.\n{}",
                cap / (1024 * 1024),
                note(*n)
            ),
        }
    }
}

/// A reply from the server: the JSON-RPC `result`, or why not.
type Reply = std::result::Result<Value, Fail>;

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
    limits: Limits,
}

impl Proc {
    fn spawn(
        cmd: &BridgeCommand,
        log: &Log,
        next_id: Arc<AtomicU64>,
        limits: Limits,
    ) -> Result<Proc> {
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
            std::thread::spawn(move || read_loop(stdout, &pending, &writer, &log, limits.max_line));
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
            limits,
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
    fn request(
        &self,
        method: &str,
        params: Value,
    ) -> std::result::Result<(u64, oneshot::Receiver<Reply>), Fail> {
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
                    return Err(format!("desktop-commander did not answer {method} in time").into());
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
                Err(format!("desktop-commander did not answer {method} in time").into())
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
        let step = self.limits.stop_step;
        self.writer.lock().unwrap().take();
        if self.wait_exit(step) {
            return;
        }
        self.signal_group(libc::SIGTERM);
        if self.wait_exit(step) {
            return;
        }
        self.signal_group(libc::SIGKILL);
        self.wait_exit(step);
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

/// One line from desktop-commander's stdout.
enum Line {
    Text(Vec<u8>),
    /// Over [`MAX_LINE`]: read through and dropped. Its first and last bytes
    /// are kept to find the request id.
    TooLong {
        len: usize,
        head: Vec<u8>,
        tail: Vec<u8>,
    },
    Eof,
}

const KEEP_ENDS: usize = 1024;

/// Reads lines with a hard cap: a line over [`MAX_LINE`] is streamed past,
/// never held whole.
struct LineReader<R> {
    r: BufReader<R>,
    cap: usize,
    peak: usize,
}

impl<R: Read> LineReader<R> {
    fn new(r: R, cap: usize) -> Self {
        LineReader {
            r: BufReader::with_capacity(64 * 1024, r),
            cap,
            peak: 0,
        }
    }

    /// The most bytes a line buffer has held.
    #[cfg(test)]
    fn peak_buffer(&self) -> usize {
        self.peak
    }

    fn next_line(&mut self) -> Line {
        let mut buf: Vec<u8> = Vec::new();
        let mut len = 0usize;
        let mut long: Option<(Vec<u8>, Vec<u8>)> = None;
        loop {
            let (used, done) = {
                let avail = match self.r.fill_buf() {
                    Ok(a) => a,
                    Err(e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
                    Err(_) => &[][..],
                };
                if avail.is_empty() {
                    // The end: a last line without a break still counts.
                    return match long {
                        Some((head, tail)) => Line::TooLong { len, head, tail },
                        None if len > 0 => Line::Text(buf),
                        None => Line::Eof,
                    };
                }
                let (chunk, done) = match avail.iter().position(|b| *b == b'\n') {
                    Some(i) => (&avail[..i], true),
                    None => (avail, false),
                };
                len += chunk.len();
                match long.as_mut() {
                    None if buf.len() + chunk.len() <= self.cap => {
                        buf.extend_from_slice(chunk);
                        self.peak = self.peak.max(buf.capacity());
                    }
                    None => {
                        // Over the cap: keep the ends, free the rest.
                        let mut head = buf[..buf.len().min(KEEP_ENDS)].to_vec();
                        let room = KEEP_ENDS - head.len();
                        head.extend_from_slice(&chunk[..chunk.len().min(room)]);
                        let mut tail = Vec::new();
                        keep_tail(&mut tail, &buf);
                        keep_tail(&mut tail, chunk);
                        buf = Vec::new();
                        long = Some((head, tail));
                    }
                    Some((_, tail)) => keep_tail(tail, chunk),
                }
                (chunk.len() + usize::from(done), done)
            };
            self.r.consume(used);
            if done {
                return match long {
                    Some((head, tail)) => Line::TooLong { len, head, tail },
                    None => Line::Text(buf),
                };
            }
        }
    }
}

fn keep_tail(tail: &mut Vec<u8>, more: &[u8]) {
    let more = &more[more.len().saturating_sub(KEEP_ENDS)..];
    tail.extend_from_slice(more);
    if tail.len() > KEEP_ENDS {
        tail.drain(..tail.len() - KEEP_ENDS);
    }
}

fn parse_id_at(s: &[u8]) -> Option<u64> {
    let digits: Vec<u8> = s
        .iter()
        .take_while(|b| b.is_ascii_digit())
        .copied()
        .collect();
    std::str::from_utf8(&digits).ok()?.parse().ok()
}

/// The request id of a reply too long to parse. The MCP SDK writes a result
/// as `{"result":…,"jsonrpc":"2.0","id":N}` and an error as
/// `{"jsonrpc":"2.0","id":N,"error":…}`, so the id is at the very end or the
/// very start; anywhere else it could be part of the content.
fn too_long_id(head: &[u8], tail: &[u8]) -> Option<u64> {
    let t = tail.trim_ascii_end();
    if let Some(body) = t.strip_suffix(b"}") {
        if let Some(pos) = body.windows(5).rposition(|w| w == b"\"id\":") {
            let digits = &body[pos + 5..];
            if !digits.is_empty() && digits.iter().all(u8::is_ascii_digit) {
                return parse_id_at(digits);
            }
        }
    }
    for prefix in [&b"{\"jsonrpc\":\"2.0\",\"id\":"[..], &b"{\"id\":"[..]] {
        if let Some(rest) = head.strip_prefix(prefix) {
            return parse_id_at(rest);
        }
    }
    None
}

/// A too-long line that is a notification (a log): nobody waits for it.
fn is_notification_head(head: &[u8]) -> bool {
    head.starts_with(b"{\"jsonrpc\":\"2.0\",\"method\":") || head.starts_with(b"{\"method\":")
}

fn read_loop(
    stdout: std::process::ChildStdout,
    pending: &Mutex<Pending>,
    writer: &Mutex<Option<mpsc::Sender<String>>>,
    log: &Log,
    max_line: usize,
) {
    let mut r = LineReader::new(stdout, max_line);
    loop {
        let buf = match r.next_line() {
            Line::Eof => return,
            Line::Text(b) => b,
            Line::TooLong { len, head, tail } => {
                log(&format!(
                    "desktop-commander wrote a {len}-byte line, over vrelay's {max_line}-byte limit; dropped it"
                ));
                if is_notification_head(&head) {
                    continue;
                }
                // Only the call it names is failed. No id, or a call already
                // given up on: no call is failed (a guess could report a call
                // that ran as failed, and a retry would run it twice); the
                // right call then ends at its own deadline.
                let tx = too_long_id(&head, &tail)
                    .and_then(|id| pending.lock().unwrap().waiting.remove(&id));
                match tx {
                    Some(tx) => {
                        let _ = tx.send(Err(Fail::TooBig(len, max_line)));
                    }
                    None => log("no waiting call matches that line; no call was failed"),
                }
                continue;
            }
        };
        let line = String::from_utf8_lossy(&buf);
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        let Ok(mut msg) = serde_json::from_str::<Value>(line) else {
            log(&format!(
                "desktop-commander wrote a non-JSON line: {}",
                cut_for_log(line)
            ));
            continue;
        };
        let id = msg.get("id").cloned();
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
                let reply = match (msg.get_mut("result").map(Value::take), msg.get("error")) {
                    (Some(r), _) => Ok(r),
                    (None, Some(e)) => Err(Fail::Msg(
                        e.get("message")
                            .and_then(Value::as_str)
                            .map(str::to_string)
                            .unwrap_or_else(|| e.to_string()),
                    )),
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

/// Blocks until `pid` has exited, leaving the zombie in place (`WNOWAIT`),
/// so the group id cannot be reused before the group is killed. An error
/// (other than EINTR) means the exit cannot be watched: ECHILD when someone
/// else reaped it, for instance with SIGCHLD ignored.
fn wait_exited_no_reap(pid: i32) -> std::io::Result<()> {
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
            return Ok(());
        }
        let e = std::io::Error::last_os_error();
        if e.raw_os_error() != Some(libc::EINTR) {
            return Err(e);
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
    let waited = wait_exited_no_reap(pid);
    if let Err(e) = &waited {
        log(&format!(
            "cannot watch desktop-commander (pid {pid}): {e}; not signalling its group, \
             so anything it started may still run"
        ));
    }
    let status = {
        let mut st = exit.0.lock().unwrap();
        // Whatever it started dies with it, then the leader is reaped.
        if may_kill_group_after(&waited) {
            kill_group(pid, libc::SIGKILL);
        }
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

/// The outcome of a restart, shared by every call waiting on it.
type Started = Option<std::result::Result<Arc<Proc>, String>>;

/// Who is running, and any restart under way. A plain mutex, never held
/// across an await, so `stop` and drop never wait on a restart.
struct State {
    proc: Option<Arc<Proc>>,
    /// A restart under way; later calls join it instead of starting another.
    starting: Option<watch::Receiver<Started>>,
    /// The server that restart spawned, so `stop` can kill it at once.
    starting_proc: Option<Arc<Proc>>,
    stopped: bool,
}

type Slot = Arc<Mutex<State>>;

/// `desktop-commander` over stdio. Restarts on the next call after it dies.
pub struct Bridge {
    cmd: BridgeCommand,
    log: Log,
    slot: Slot,
    /// The last tool list seen, for when a fresh one cannot be had.
    tools: Mutex<Vec<ToolDef>>,
    next_id: Arc<AtomicU64>,
    limits: Limits,
    /// Test hook: the next restart task panics before it reports.
    #[cfg(test)]
    panic_next_restart: Arc<std::sync::atomic::AtomicBool>,
}

/// Kills a server now: no grace. The waiter thread then reaps it and fails
/// whatever was waiting on it.
fn kill_now(p: &Proc) {
    p.writer.lock().unwrap().take();
    p.signal_group(libc::SIGKILL);
}

/// One restart: spawn, `initialize`, then publish the result to every
/// waiting call. It runs to its own time limit even if its callers leave,
/// so a later call finds it running, but nothing queues behind it.
async fn restart(
    slot: Slot,
    tx: watch::Sender<Started>,
    cmd: BridgeCommand,
    log: Log,
    next_id: Arc<AtomicU64>,
    limits: Limits,
    #[cfg(test)] panic_now: bool,
) {
    #[cfg(test)]
    if panic_now {
        panic!("test hook: the restart task dies before it reports");
    }
    log("starting desktop-commander again");
    let result: std::result::Result<Arc<Proc>, String> = async {
        let p = Arc::new(Proc::spawn(&cmd, &log, next_id, limits)?);
        {
            let mut st = slot.lock().unwrap();
            if st.stopped {
                drop(st);
                kill_now(&p);
                return Err("the bridge is stopped".to_string());
            }
            st.starting_proc = Some(p.clone());
        }
        let init = p
            .request_async(
                "initialize",
                initialize_params(),
                Instant::now() + limits.init_timeout,
            )
            .await;
        if let Err(e) = init {
            let dead = p.clone();
            tokio::task::spawn_blocking(move || dead.stop());
            return Err(format!("desktop-commander did not start: {e}"));
        }
        p.notify("notifications/initialized", json!({}));
        Ok(p)
    }
    .await;
    let result = {
        let mut st = slot.lock().unwrap();
        st.starting = None;
        st.starting_proc = None;
        match result {
            Ok(p) if st.stopped => {
                kill_now(&p);
                Err("the bridge is stopped".to_string())
            }
            Ok(p) => {
                st.proc = Some(p.clone());
                Ok(p)
            }
            Err(e) => Err(e),
        }
    };
    let _ = tx.send(Some(result));
}

impl Bridge {
    /// Checks Node, makes `~/.claude-server-commander` private, starts
    /// `desktop-commander`, and does the MCP handshake. Logs go to stderr.
    pub fn start(cmd: &BridgeCommand) -> Result<Bridge> {
        Bridge::start_with_log(cmd, stderr_log())
    }

    pub fn start_with_log(cmd: &BridgeCommand, log: Log) -> Result<Bridge> {
        Bridge::start_limited(cmd, log, Limits::default())
    }

    pub(crate) fn start_limited(cmd: &BridgeCommand, log: Log, limits: Limits) -> Result<Bridge> {
        check_node(&cmd.node)?;
        secure_dc_config_dir(&dc_home(std::env::var_os("HOME"))?)?;
        let next_id = Arc::new(AtomicU64::new(1));
        let proc = Arc::new(Proc::spawn(cmd, &log, next_id.clone(), limits)?);
        let started = (|| -> std::result::Result<Vec<ToolDef>, Fail> {
            proc.request_blocking("initialize", initialize_params(), limits.init_timeout)?;
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
            slot: Arc::new(Mutex::new(State {
                proc: Some(proc),
                starting: None,
                starting_proc: None,
                stopped: false,
            })),
            tools: Mutex::new(tools),
            next_id,
            limits,
            #[cfg(test)]
            panic_next_restart: Arc::new(std::sync::atomic::AtomicBool::new(false)),
        })
    }

    /// The running server, starting a fresh one if the last one died. Waits
    /// no later than `deadline`. At most one restart runs: later calls join
    /// it. A call whose deadline has already passed starts nothing.
    async fn running(&self, deadline: Instant) -> Result<Arc<Proc>> {
        let mut rx = {
            let mut st = self.slot.lock().unwrap();
            if let Some(p) = st.proc.as_ref() {
                if !p.is_dead() {
                    return Ok(p.clone());
                }
            }
            if st.stopped {
                return Err("the bridge is stopped".into());
            }
            match st.starting.as_ref() {
                Some(rx) => rx.clone(),
                None => {
                    if Instant::now() >= deadline {
                        return Err(
                            "desktop-commander is not running and this call's time is up".into(),
                        );
                    }
                    let (tx, rx) = watch::channel(None);
                    st.starting = Some(rx.clone());
                    tokio::spawn(restart(
                        self.slot.clone(),
                        tx,
                        self.cmd.clone(),
                        self.log.clone(),
                        self.next_id.clone(),
                        self.limits,
                        #[cfg(test)]
                        self.panic_next_restart.swap(false, Ordering::SeqCst),
                    ));
                    rx
                }
            }
        };
        let waited = tokio::time::timeout_at(
            tokio::time::Instant::from_std(deadline),
            rx.wait_for(Option::is_some),
        )
        .await
        .map(|r| r.map(|v| v.clone()));
        match waited {
            Ok(Ok(v)) => v.unwrap_or_else(|| Err("no restart result".into())),
            Ok(Err(_)) => {
                // The restart task died without reporting (a panic, or its
                // runtime went away). Forget it, so the next call can try
                // again instead of joining a dead restart for ever.
                let orphan = {
                    let mut st = self.slot.lock().unwrap();
                    if st.starting.as_ref().is_some_and(|s| s.same_channel(&rx)) {
                        st.starting = None;
                        st.starting_proc.take()
                    } else {
                        None
                    }
                };
                if let Some(p) = orphan {
                    kill_now(&p);
                }
                (self.log)(
                    "a desktop-commander restart died without a result; the next call retries",
                );
                Err("desktop-commander's restart failed; try again".into())
            }
            Err(_) => Err(
                "desktop-commander was starting again and was not ready in time for this call"
                    .into(),
            ),
        }
    }

    /// `desktop-commander`'s own `tools/list` result, unfiltered (all pages
    /// joined into one `tools` array).
    pub async fn tools_raw(&self) -> Result<Value> {
        let deadline = Instant::now() + LIST_TIMEOUT;
        let p = self.running(deadline).await?;
        let mut all = Vec::new();
        let mut cursor = None;
        for _ in 0..MAX_PAGES {
            let page = p
                .request_async("tools/list", cursor_params(&cursor), deadline)
                .await
                .map_err(|e| e.to_string())?;
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

    /// Runs one tool, all of it (a restart included) by `deadline`. Never
    /// fails as such: a crash, a timeout or a refusal comes back as an error
    /// result. The output is cut to fit one frame.
    pub async fn call(&self, tool: &str, args: Value, deadline: Instant) -> BridgeOutput {
        self.call_if(tool, args, deadline, || true)
            .await
            .unwrap_or_else(|| BridgeOutput::error("not sent"))
    }

    /// [`call`](Self::call), but `wanted` is asked once desktop-commander is
    /// ready (a restart can take seconds), just before the request is
    /// written: if it says no, nothing is sent and the answer is `None`.
    pub async fn call_if(
        &self,
        tool: &str,
        args: Value,
        deadline: Instant,
        wanted: impl Fn() -> bool,
    ) -> Option<BridgeOutput> {
        let p = match self.running(deadline).await {
            Ok(p) => p,
            Err(e) => return Some(BridgeOutput::error(e)),
        };
        if !wanted() {
            return None;
        }
        let reply = p
            .request_async(
                "tools/call",
                json!({"name": tool, "arguments": args}),
                deadline,
            )
            .await;
        Some(match reply {
            Ok(result) => fit_to_frame(BridgeOutput::from_result(result)),
            Err(e @ Fail::TooBig(..)) => BridgeOutput {
                truncated: true,
                ..BridgeOutput::error(e.to_string())
            },
            Err(e) => fit_to_frame(BridgeOutput::error(e.to_string())),
        })
    }

    /// Marks the bridge stopped and kills any restart under way at once,
    /// without waiting for it. Never blocks.
    pub(crate) fn abandon_starts(&self) {
        let starting = {
            let mut st = self.slot.lock().unwrap();
            st.stopped = true;
            st.starting_proc.take()
        };
        if let Some(p) = starting {
            kill_now(&p);
        }
    }

    fn take_proc(&self) -> Option<Arc<Proc>> {
        self.abandon_starts();
        self.slot.lock().unwrap().proc.take()
    }

    /// Stops `desktop-commander` and everything it started: close stdin,
    /// wait 2 s, SIGTERM the group, wait 2 s, SIGKILL it. A restart under way
    /// is killed at once. Blocks for up to about 6 s; from async code, call
    /// it on a blocking thread.
    pub fn stop(self) {
        if let Some(p) = self.take_proc() {
            p.stop();
        }
    }
}

impl Drop for Bridge {
    /// Dropped without `stop` (a panic, an early return): kill the group at
    /// once rather than leave commands running. Never waits.
    fn drop(&mut self) {
        if let Some(p) = self.take_proc() {
            kill_now(&p);
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

    /// Small limits, so the slow paths (a too-long line, a slow start, the
    /// stop escalation) run in well under a second each.
    const FAST: Limits = Limits {
        max_line: 1024 * 1024,
        init_timeout: Duration::from_secs(5),
        stop_step: Duration::from_millis(200),
    };
    /// A line just over FAST's cap.
    const HUGE: usize = 2 * 1024 * 1024;

    fn quiet() -> Log {
        Arc::new(|_: &str| {})
    }

    #[test]
    fn production_limits_are_the_documented_ones() {
        let l = Limits::default();
        assert_eq!(l.max_line, 16 * 1024 * 1024);
        assert_eq!(l.init_timeout, Duration::from_secs(30));
        assert_eq!(l.stop_step, Duration::from_secs(2));
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
        let b = Bridge::start_limited(&cmd, quiet(), FAST).unwrap();
        let out = b.call("spawn", json!({}), soon()).await;
        assert_eq!(text_of(&out), "spawned");
        let sleep_pid = read_pid(&dir, "sleep.pid");
        let fake_pid = read_pid(&dir, "fake.pid");
        let t = Instant::now();
        b.stop();
        // One step for stdin, one for SIGTERM, then SIGKILL (2 s each in
        // production, 200 ms here).
        let took = t.elapsed();
        assert!(took >= 2 * FAST.stop_step, "{took:?}");
        assert!(took < Duration::from_secs(2), "{took:?}");
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

    /// A reader that yields `n` bytes of `q`, then `rest`, without ever
    /// holding the `q`s in memory.
    struct Gen {
        left: usize,
        rest: std::io::Cursor<Vec<u8>>,
    }

    impl std::io::Read for Gen {
        fn read(&mut self, buf: &mut [u8]) -> std::io::Result<usize> {
            if self.left > 0 {
                let n = buf.len().min(self.left);
                buf[..n].fill(b'q');
                self.left -= n;
                return Ok(n);
            }
            self.rest.read(buf)
        }
    }

    #[test]
    fn line_reader_never_buffers_a_line_past_the_cap() {
        let cap = 1024 * 1024;
        let huge = 4 * cap;
        let mut r = LineReader::new(
            Gen {
                left: huge,
                rest: std::io::Cursor::new(b"tail\"id\":7}\n{\"next\":1}\npartial".to_vec()),
            },
            cap,
        );
        match r.next_line() {
            Line::TooLong { len, tail, .. } => {
                assert_eq!(len, huge + "tail\"id\":7}".len());
                assert!(
                    tail.ends_with(b"\"id\":7}"),
                    "{:?}",
                    String::from_utf8_lossy(&tail)
                );
            }
            _ => panic!("expected TooLong"),
        }
        // Memory stayed bounded by the cap, not the line.
        assert!(r.peak_buffer() <= 2 * cap, "{}", r.peak_buffer());
        // The reader is still in step: the next line is whole.
        match r.next_line() {
            Line::Text(t) => assert_eq!(t, b"{\"next\":1}"),
            _ => panic!("expected the next line"),
        }
        // A last line without a line break still comes out, then the end.
        match r.next_line() {
            Line::Text(t) => assert_eq!(t, b"partial"),
            _ => panic!("expected the partial line"),
        }
        assert!(matches!(r.next_line(), Line::Eof));
    }

    #[test]
    fn too_long_reply_id_is_found_at_either_end() {
        assert_eq!(
            too_long_id(
                b"{\"result\":{\"x",
                b"q\"}]},\"jsonrpc\":\"2.0\",\"id\":42}"
            ),
            Some(42)
        );
        assert_eq!(
            too_long_id(b"{\"jsonrpc\":\"2.0\",\"id\":9,\"error\":{\"m", b"qq\"}}"),
            Some(9)
        );
        // An "id" inside the content does not count.
        assert_eq!(
            too_long_id(b"{\"result\":{\"content\":[{\"id\":3,", b"qqq\"}]}}"),
            None
        );
        assert!(is_notification_head(
            b"{\"jsonrpc\":\"2.0\",\"method\":\"notifications/message\""
        ));
        assert!(!is_notification_head(b"{\"result\":{"));
    }

    #[tokio::test]
    async fn a_line_over_the_cap_fails_its_call_and_the_bridge_carries_on() {
        let (cmd, dir) = fake("b-huge");
        std::fs::write(dir.join("huge_bytes"), HUGE.to_string()).unwrap();
        let (log, lines) = logged();
        let b = Bridge::start_limited(&cmd, log, FAST).unwrap();
        let pid = read_pid(&dir, "fake.pid");
        let out = b.call("huge", json!({}), soon()).await;
        assert!(out.is_error && out.truncated, "{out:?}");
        let text = text_of(&out);
        assert!(text.contains("[output truncated by vrelay: "), "{text}");
        // The whole line: the text plus the JSON around it (under 100 bytes).
        let n: usize = text
            .split("reply was ")
            .nth(1)
            .and_then(|r| r.split(' ').next())
            .and_then(|n| n.parse().ok())
            .expect("the size is reported");
        assert!(n > HUGE && n < HUGE + 100, "{text}");
        // Same server, still answering.
        let out = b.call("echo", json!({}), soon()).await;
        assert_eq!(text_of(&out), "ok");
        assert_eq!(read_pid(&dir, "fake.pid"), pid);
        assert!(
            lines
                .lock()
                .unwrap()
                .iter()
                .any(|l| l.contains("over vrelay's")),
            "not logged"
        );
        b.stop();
    }

    #[tokio::test]
    async fn a_line_over_the_cap_without_an_id_fails_no_call() {
        let (cmd, dir) = fake("b-huge-noid");
        std::fs::write(dir.join("huge_bytes"), HUGE.to_string()).unwrap();
        let b = Bridge::start_limited(&cmd, quiet(), FAST).unwrap();
        // Nobody can tell whose it is, so no call is failed by it: the call
        // ends at its own deadline, as an honest timeout.
        let t = Instant::now();
        let out = b
            .call(
                "huge_noid",
                json!({}),
                Instant::now() + Duration::from_secs(1),
            )
            .await;
        assert!(out.is_error && !out.truncated, "{out:?}");
        assert!(text_of(&out).contains("in time"), "{}", text_of(&out));
        assert!(t.elapsed() >= Duration::from_secs(1), "{:?}", t.elapsed());
        let out = b.call("echo", json!({}), soon()).await;
        assert_eq!(text_of(&out), "ok");
        b.stop();
    }

    #[tokio::test]
    async fn a_huge_reply_for_a_forgotten_call_leaves_other_calls_alone() {
        let (cmd, dir) = fake("b-huge-late");
        std::fs::write(dir.join("huge_bytes"), HUGE.to_string()).unwrap();
        std::fs::write(dir.join("late"), "0.6").unwrap();
        let b = Bridge::start_limited(&cmd, quiet(), FAST).unwrap();
        // A gives up before its huge reply comes; B is still waiting when it
        // does, and must get its own real answer.
        let a = b.call(
            "huge_late",
            json!({}),
            Instant::now() + Duration::from_millis(300),
        );
        let c = async {
            tokio::time::sleep(Duration::from_millis(100)).await;
            b.call("echo", json!({}), soon()).await
        };
        let (a, c) = tokio::join!(a, c);
        assert!(a.is_error && text_of(&a).contains("in time"), "{a:?}");
        assert!(!c.is_error && !c.truncated, "{c:?}");
        assert_eq!(text_of(&c), "ok");
        b.stop();
    }

    fn spawns(dir: &Path) -> usize {
        std::fs::read_to_string(dir.join("spawns"))
            .map(|s| s.lines().count())
            .unwrap_or(0)
    }

    #[tokio::test]
    async fn one_restart_serves_every_caller_and_stale_ones_start_nothing() {
        let (cmd, dir) = fake("b-onestart");
        // The 200 ms init limit is for the restart below; on a loaded
        // machine the first start can miss it, so it gets a few tries.
        let limits = Limits {
            init_timeout: Duration::from_millis(200),
            ..FAST
        };
        let b = (0..10)
            .find_map(|_| Bridge::start_limited(&cmd, quiet(), limits).ok())
            .expect("the fake server starts");
        let base = spawns(&dir);
        let out = b.call("exit", json!({}), soon()).await;
        assert!(out.is_error);
        std::fs::write(dir.join("hang_init"), "").unwrap();
        // Twenty calls arrive while the restart hangs; all give up.
        let calls: Vec<_> = (0..20)
            .map(|_| {
                b.call(
                    "echo",
                    json!({}),
                    Instant::now() + Duration::from_millis(300),
                )
            })
            .collect();
        for out in futures_join_all(calls).await {
            assert!(out.is_error, "{out:?}");
        }
        // Long after every deadline, at most the one restart ever ran.
        // (Queued restarts would run one per 200 ms init limit by now.) On a
        // loaded machine its shell can be stopped by the init limit before
        // it writes its spawns line, so "none" is a pass too.
        tokio::time::sleep(Duration::from_millis(1200)).await;
        let after = spawns(&dir);
        assert!(
            after <= base + 1,
            "restarts were queued for callers that left: {after} > {}",
            base + 1
        );
        // A call whose deadline has already passed starts nothing at all.
        let out = b.call("echo", json!({}), Instant::now()).await;
        assert!(out.is_error);
        tokio::time::sleep(Duration::from_millis(300)).await;
        assert_eq!(spawns(&dir), after);
        b.stop();
    }

    async fn futures_join_all<F: std::future::Future>(fs: Vec<F>) -> Vec<F::Output> {
        let mut set = Vec::new();
        for f in fs {
            set.push(Box::pin(f));
        }
        let mut out = Vec::new();
        // Poll them together so they overlap.
        let mut pending: Vec<_> = set.into_iter().map(Some).collect();
        let mut results: Vec<Option<F::Output>> = (0..pending.len()).map(|_| None).collect();
        std::future::poll_fn(|cx| {
            let mut all = true;
            for (i, slot) in pending.iter_mut().enumerate() {
                if let Some(f) = slot.as_mut() {
                    match f.as_mut().poll(cx) {
                        std::task::Poll::Ready(v) => {
                            results[i] = Some(v);
                            *slot = None;
                        }
                        std::task::Poll::Pending => all = false,
                    }
                }
            }
            if all {
                std::task::Poll::Ready(())
            } else {
                std::task::Poll::Pending
            }
        })
        .await;
        for r in results {
            out.push(r.unwrap());
        }
        out
    }

    #[tokio::test]
    async fn a_restart_that_dies_does_not_wedge_the_bridge() {
        let (cmd, dir) = fake("b-deadrestart");
        let b = Bridge::start_limited(&cmd, quiet(), FAST).unwrap();
        let out = b.call("exit", json!({}), soon()).await;
        assert!(out.is_error);
        // The restart task panics before it reports.
        b.panic_next_restart.store(true, Ordering::SeqCst);
        let out = b.call("echo", json!({}), soon()).await;
        assert!(out.is_error, "{out:?}");
        assert_eq!(spawns(&dir), 1);
        // The next call does not join the dead restart: it starts afresh.
        let out = b.call("echo", json!({}), soon()).await;
        assert_eq!(text_of(&out), "ok", "{out:?}");
        assert_eq!(spawns(&dir), 2);
        b.stop();
    }

    #[tokio::test]
    async fn stop_during_a_restart_returns_at_once_and_kills_it() {
        let (cmd, dir) = fake("b-stopstart");
        let b = Arc::new(Bridge::start_limited(&cmd, quiet(), FAST).unwrap());
        let out = b.call("exit", json!({}), soon()).await;
        assert!(out.is_error);
        std::fs::write(dir.join("hang_init"), "").unwrap();
        let b2 = b.clone();
        let call = tokio::spawn(async move { b2.call("echo", json!({}), soon()).await });
        // The restart is under way, hanging in initialize.
        // (Yield while waiting: the restart runs on this test's runtime.)
        let mut init_sleep = None;
        for _ in 0..200 {
            if let Ok(t) = std::fs::read_to_string(dir.join("init_sleep.pid")) {
                init_sleep = t.trim().parse::<i32>().ok();
                if init_sleep.is_some() {
                    break;
                }
            }
            tokio::time::sleep(Duration::from_millis(20)).await;
        }
        let init_sleep = init_sleep.expect("the restart reached initialize");
        let restarting = read_pid(&dir, "fake.pid");
        let t = Instant::now();
        b.abandon_starts();
        assert!(
            t.elapsed() < Duration::from_millis(100),
            "{:?}",
            t.elapsed()
        );
        // What the restart started is killed, and its caller hears at once.
        let out = tokio::time::timeout(Duration::from_secs(3), call)
            .await
            .expect("the waiting call returned")
            .unwrap();
        assert!(out.is_error, "{out:?}");
        assert!(pid_gone(restarting), "restarting server outlived stop");
        assert!(pid_gone(init_sleep), "its child outlived stop");
        // Nothing starts after a stop.
        let out = b.call("echo", json!({}), soon()).await;
        assert!(out.is_error);
        assert_eq!(spawns(&dir), 2);
    }

    /// Final review I2: a call that waits for a restart asks whether it is
    /// still wanted once the server is ready, and sends nothing if not.
    #[tokio::test]
    async fn a_call_no_longer_wanted_after_a_restart_is_never_sent() {
        let (cmd, dir) = fake("b-wanted");
        let b = Bridge::start_limited(&cmd, quiet(), FAST).unwrap();
        let out = b.call("exit", json!({}), soon()).await;
        assert!(out.is_error);
        // The next start takes a second; the call is cancelled meanwhile.
        std::fs::write(dir.join("slow_init"), "1").unwrap();
        let wanted = Arc::new(std::sync::atomic::AtomicBool::new(true));
        let w = wanted.clone();
        let flip = tokio::spawn(async move {
            tokio::time::sleep(Duration::from_millis(300)).await;
            w.store(false, Ordering::SeqCst);
        });
        let w = wanted.clone();
        let out = b
            .call_if("spawn", json!({}), soon(), move || w.load(Ordering::SeqCst))
            .await;
        flip.await.unwrap();
        assert!(out.is_none(), "{out:?}");
        // `spawn` writes sleep.pid when it runs: it never did.
        tokio::time::sleep(Duration::from_millis(300)).await;
        assert!(!dir.join("sleep.pid").exists(), "the call was sent");
        assert_eq!(spawns(&dir), 2, "the restart itself went ahead");
        // Still wanted: it runs.
        let out = b.call_if("echo", json!({}), soon(), || true).await;
        assert_eq!(text_of(&out.unwrap()), "ok");
        b.stop();
    }

    #[tokio::test]
    async fn the_deadline_covers_a_restart() {
        let (cmd, dir) = fake("b-slowinit");
        let b = Bridge::start_limited(&cmd, quiet(), FAST).unwrap();
        // It dies; the next start takes 1 s to answer initialize.
        let out = b.call("exit", json!({}), soon()).await;
        assert!(out.is_error);
        std::fs::write(dir.join("slow_init"), "1").unwrap();
        let short = || Instant::now() + Duration::from_millis(300);
        let t = Instant::now();
        let (a, c) = tokio::join!(
            b.call("echo", json!({}), short()),
            b.call("echo", json!({}), short())
        );
        assert!(
            t.elapsed() < Duration::from_millis(900),
            "{:?}",
            t.elapsed()
        );
        assert!(a.is_error && c.is_error, "{a:?} {c:?}");
        assert!(text_of(&a).contains("in time"), "{}", text_of(&a));
        // The start carried on without them; a later call finds it running.
        let out = b.call("echo", json!({}), soon()).await;
        assert_eq!(text_of(&out), "ok", "{out:?}");
        b.stop();
    }

    #[test]
    fn fitting_carries_the_overshoot_across_items() {
        // 120 items of 60 KB of `"`: about 14 MB encoded. Most of it should
        // survive, not collapse into one note.
        let item = "\"".repeat(60_000);
        let content: Vec<Value> = (0..120)
            .map(|_| json!({"type": "text", "text": item}))
            .collect();
        let out = fit_to_frame(BridgeOutput {
            content: Value::Array(content),
            is_error: false,
            truncated: false,
        });
        assert!(out.truncated);
        let items = out.content.as_array().unwrap();
        assert_eq!(items.len(), 120);
        let frame = ToRelay::Result(CallResult {
            call_id: "c".repeat(CALL_ID_RESERVE),
            content: out.content.clone(),
            is_error: false,
            truncated: true,
        });
        let n = encode(&frame).expect("fits").len();
        assert!(n > MAX_FRAME_BYTES - 64 * 1024, "kept only {n} bytes");
    }

    #[test]
    fn cutting_multibyte_text_lands_on_a_character_boundary() {
        // 4-byte characters that JSON does not escape: the cut point falls
        // inside one unless it is moved back to a boundary.
        let text = "😀".repeat(MAX_FRAME_BYTES / 4 + 1000) + "x";
        let out = fit_to_frame(BridgeOutput {
            content: json!([{"type": "text", "text": text}]),
            is_error: false,
            truncated: false,
        });
        let t = out.content[0]["text"].as_str().unwrap();
        let (kept, note) = t.rsplit_once('\n').unwrap();
        assert!(kept.chars().all(|c| c == '😀'));
        let omitted: usize = note
            .trim_start_matches("[output truncated by vrelay: ")
            .trim_end_matches(" bytes omitted]")
            .parse()
            .unwrap();
        assert_eq!(omitted + kept.len(), text.len());
    }

    #[test]
    fn content_that_is_not_a_list_is_wrapped_then_cut() {
        let out = fit_to_frame(BridgeOutput {
            content: json!("z".repeat(MAX_FRAME_BYTES + 10)),
            is_error: false,
            truncated: false,
        });
        assert!(out.truncated);
        let items = out.content.as_array().expect("a list");
        assert_eq!(items.len(), 1);
        assert!(items[0]["text"]
            .as_str()
            .unwrap()
            .starts_with("[output truncated by vrelay: "));
    }

    #[test]
    fn a_wait_error_does_not_signal_the_group() {
        // pid 1 is not our child: waitid fails with ECHILD.
        let r = wait_exited_no_reap(1);
        assert_eq!(
            r.as_ref().err().and_then(|e| e.raw_os_error()),
            Some(libc::ECHILD)
        );
        assert!(!may_kill_group_after(&r));
        assert!(may_kill_group_after(&Ok(())));
    }

    #[test]
    fn a_hanging_node_does_not_hang_the_start() {
        let dir = test_dir("b-hangnode");
        std::fs::create_dir_all(&dir).unwrap();
        let node = dir.join("node");
        std::fs::write(
            &node,
            "#!/bin/sh\nsleep 30 &\necho $! > \"$(dirname \"$0\")/child\"\nsleep 30\n",
        )
        .unwrap();
        std::fs::set_permissions(&node, std::fs::Permissions::from_mode(0o755)).unwrap();
        // Long enough for a loaded machine to start the script (it writes
        // the child's pid first), short enough to show the hang is cut off.
        let t = Instant::now();
        let err = check_node_with(&node, Duration::from_millis(1500)).unwrap_err();
        assert!(t.elapsed() < Duration::from_secs(5), "{:?}", t.elapsed());
        assert!(
            err.contains("did not answer") && err.contains("nodejs.org"),
            "{err}"
        );
        // Its child died with it.
        assert!(pid_gone(read_pid(&dir, "child")));
    }

    #[test]
    fn home_falls_back_to_the_user_database() {
        // SAFETY: getpwuid returns a pointer into static storage, read at once.
        let pw_dir = unsafe {
            let pw = libc::getpwuid(libc::getuid());
            assert!(!pw.is_null());
            std::ffi::CStr::from_ptr((*pw).pw_dir)
                .to_string_lossy()
                .into_owned()
        };
        assert_eq!(dc_home(None).unwrap(), PathBuf::from(&pw_dir));
        assert_eq!(dc_home(Some("".into())).unwrap(), PathBuf::from(&pw_dir));
        assert_eq!(dc_home(Some("/x/y".into())).unwrap(), PathBuf::from("/x/y"));
    }

    /// The lock pins the version the code was checked against, with the
    /// checksum tested in spike D (docs/superpowers/plans/2026-11-09-relay-p0-spikes.md).
    #[test]
    fn dc_lock_pins_0_3_1_with_the_known_checksum() {
        let lock = std::fs::read_to_string(runfile(
            "apps/suites/vitruvian-relay/connector/dc/pnpm-lock.yaml",
        ))
        .unwrap();
        assert!(
            lock.contains(
                "  .:\n    dependencies:\n      '@wonderwhy-er/desktop-commander':\n        specifier: 0.3.1\n        version: 0.3.1\n"
            ),
            "the importer does not pin 0.3.1"
        );
        let entry = format!(
            "  '@wonderwhy-er/desktop-commander@0.3.1':\n    resolution: {{integrity: {DC_INTEGRITY}}}\n"
        );
        assert!(
            lock.contains(&entry),
            "integrity differs from {DC_INTEGRITY}"
        );
        assert_eq!(lock.matches("'@wonderwhy-er/desktop-commander@").count(), 2);
    }
}
