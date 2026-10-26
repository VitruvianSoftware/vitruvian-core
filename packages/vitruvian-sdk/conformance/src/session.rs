// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

//! Tool process lifecycle (`Link`), JSON-RPC session runner (`Run`), and
//! temporary data directory management.

use std::collections::{HashMap, HashSet};
use std::fs;
use std::io::{self, BufRead, BufReader, Write};
use std::path::{Path, PathBuf};
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::mpsc::{self, Receiver, RecvTimeoutError};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use crate::json::{self, Value};
use crate::protocol::{
    check_params, gated_spec, is_text, is_tree, kind_of, misnamed, newer_than, service_spec,
    Failure, MsgKind, ANSWER_SECONDS, EXIT_SECONDS, FEATURES, FIRST_ANSWER_SECONDS, INVALID_PARAMS,
    MAX_LINE_BYTES, MAX_STATUS_AFTER_REFUSAL, METHOD_NOT_FOUND, NOT_IN_USES, UNAVAILABLE, VERSIONS,
};
use crate::pystr;

/// Abstract message transport so unit tests (`the_hello`, `a_line_always_waiting`)
/// can substitute an in-memory link without spawning a child process.
pub trait Transport {
    fn send(&mut self, message: &Value) -> Result<(), Failure>;
    fn receive(
        &mut self,
        deadline: Instant,
        seconds: u64,
        leaving: bool,
    ) -> Result<Option<Value>, Failure>;
    fn close_stdin(&mut self) {}
    fn wait_exit(&mut self, _timeout: Duration) -> Result<i32, Failure> {
        Ok(0)
    }
    fn close(&mut self) {}
}

fn read_bounded_line<R: BufRead>(reader: &mut R, limit: usize) -> io::Result<Vec<u8>> {
    let mut out = Vec::new();
    while out.len() < limit {
        let buf = match reader.fill_buf() {
            Ok([]) => break,
            Ok(b) => b,
            Err(e) if e.kind() == io::ErrorKind::Interrupted => continue,
            Err(e) => return Err(e),
        };
        let remaining = limit - out.len();
        let window = &buf[..buf.len().min(remaining)];
        if let Some(pos) = window.iter().position(|&b| b == b'\n') {
            out.extend_from_slice(&window[..=pos]);
            reader.consume(pos + 1);
            break;
        } else {
            let n = window.len();
            out.extend_from_slice(window);
            reader.consume(n);
        }
    }
    Ok(out)
}

fn is_blank_line(line: &[u8]) -> bool {
    line.iter()
        .all(|b| matches!(b, b' ' | b'\t' | b'\n' | b'\r' | 0x0b | 0x0c))
}

/// The tool's process, with its standard output read a line at a time.
pub struct Link {
    process: Child,
    stdin: Option<ChildStdin>,
    lines: Receiver<Vec<u8>>,
    done_rx: Receiver<()>,
    reader: Option<JoinHandle<()>>,
}

impl Link {
    pub fn spawn(command: &[String], folder: &Path) -> io::Result<Self> {
        let (prog, args) = command
            .split_first()
            .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "empty command"))?;
        let mut process = Command::new(prog)
            .args(args)
            .current_dir(folder)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .spawn()?;
        let stdin = process.stdin.take();
        let stdout = process.stdout.take().expect("stdout piped");
        let (line_tx, line_rx) = mpsc::channel();
        let (done_tx, done_rx) = mpsc::sync_channel(1);
        let reader = thread::spawn(move || {
            let mut reader = BufReader::with_capacity(64 * 1024, stdout);
            loop {
                let line = read_bounded_line(&mut reader, MAX_LINE_BYTES + 2).unwrap_or_default();
                let is_eof = line.is_empty();
                let _ = line_tx.send(line);
                if is_eof {
                    break;
                }
            }
            let _ = done_tx.send(());
        });
        Ok(Self {
            process,
            stdin,
            lines: line_rx,
            done_rx,
            reader: Some(reader),
        })
    }
}

impl Transport for Link {
    fn send(&mut self, message: &Value) -> Result<(), Failure> {
        let mut bytes = message.dumps_compact().into_bytes();
        bytes.push(b'\n');
        let stdin = self
            .stdin
            .as_mut()
            .ok_or_else(|| Failure::new("the tool closed its input"))?;
        stdin
            .write_all(&bytes)
            .and_then(|_| stdin.flush())
            .map_err(|_| Failure::new("the tool closed its input"))
    }

    fn receive(
        &mut self,
        deadline: Instant,
        seconds: u64,
        leaving: bool,
    ) -> Result<Option<Value>, Failure> {
        loop {
            let timeout = deadline.saturating_duration_since(Instant::now());
            let line = match self.lines.recv_timeout(timeout) {
                Ok(l) => l,
                Err(RecvTimeoutError::Timeout | RecvTimeoutError::Disconnected) => {
                    if leaving {
                        return Ok(None);
                    }
                    return Err(Failure::new(format!(
                        "no answer within {} seconds",
                        seconds
                    )));
                }
            };
            if line.is_empty() {
                if leaving {
                    return Ok(None);
                }
                return Err(Failure::new("the tool exited"));
            }
            if !line.ends_with(b"\n") {
                return Err(Failure::new("a line longer than 1 MB, or one cut short"));
            }
            if is_blank_line(&line) {
                continue;
            }
            match json::loads_bytes(&line) {
                Ok(val) => return Ok(Some(val)),
                Err(_) => {
                    let prefix = &line[..line.len().min(80)];
                    return Err(Failure::new(format!(
                        "a line that is not JSON: {}",
                        pystr::repr_bytes(prefix)
                    )));
                }
            }
        }
    }

    fn close_stdin(&mut self) {
        drop(self.stdin.take());
    }

    fn wait_exit(&mut self, timeout: Duration) -> Result<i32, Failure> {
        let deadline = Instant::now() + timeout;
        let mut sleep_dur = Duration::from_micros(250);
        loop {
            match self.process.try_wait() {
                Ok(Some(status)) => return Ok(exit_code(status)),
                Ok(None) => {
                    let now = Instant::now();
                    if now >= deadline {
                        return Err(Failure::new(format!(
                            "still running {} seconds after shutdown",
                            EXIT_SECONDS
                        )));
                    }
                    let rem = deadline - now;
                    thread::sleep(sleep_dur.min(rem));
                    if sleep_dur < Duration::from_millis(2) {
                        sleep_dur = (sleep_dur * 2).min(Duration::from_millis(2));
                    }
                }
                Err(_) => {
                    return Err(Failure::new(format!(
                        "still running {} seconds after shutdown",
                        EXIT_SECONDS
                    )))
                }
            }
        }
    }

    fn close(&mut self) {
        if let Ok(None) = self.process.try_wait() {
            let _ = self.process.kill();
        }
        let _ = self.process.wait();
        drop(self.stdin.take());
        // The reader stops at the end of the tool's output. It is not waited
        // for longer than EXIT_SECONDS: a program the tool started may hold the pipe.
        if self
            .done_rx
            .recv_timeout(Duration::from_secs(EXIT_SECONDS))
            .is_ok()
        {
            if let Some(handle) = self.reader.take() {
                let _ = handle.join();
            }
        }
    }
}

impl Drop for Link {
    fn drop(&mut self) {
        self.close();
    }
}

#[cfg(unix)]
fn exit_code(status: std::process::ExitStatus) -> i32 {
    use std::os::unix::process::ExitStatusExt;
    status
        .code()
        .unwrap_or_else(|| -status.signal().unwrap_or(1))
}

#[cfg(not(unix))]
fn exit_code(status: std::process::ExitStatus) -> i32 {
    status.code().unwrap_or(1)
}

/// One tool put through the checks.
pub struct Run<L: Transport> {
    pub link: L,
    pub data_folder: String,
    pub features: Option<Vec<String>>,
    pub shows_status: bool,
    pub shows_activity: bool,
    pub has_slot: bool,
    pub docked: usize,
    pub statuses: Vec<String>,
    pub status_refused: usize,
    pub drew_choice: bool,
    pub uses: HashSet<String>,
    pub commands: Vec<String>,
    pub protocol: Option<String>,
    pub panels: Vec<Value>,
    pub rendered: HashMap<String, Value>,
    pub values: HashMap<String, Value>,
    pub next_id: i64,
    pub refused: usize,
}

impl<L: Transport> Run<L> {
    pub fn new(
        link: L,
        manifest: &Value,
        data_folder: impl Into<String>,
        features: Option<Vec<String>>,
    ) -> Self {
        let contributes = manifest.get("contributes");
        let shows_status = contributes.is_some_and(|c| c.has("status"));
        let shows_activity = contributes
            .and_then(|c| c.get("status"))
            .and_then(|s| s.get("activity"))
            .and_then(|a| a.as_bool())
            == Some(true);
        let has_slot = contributes.is_some_and(|c| c.has("slot"));
        let uses = manifest
            .get("uses")
            .and_then(|u| u.as_arr())
            .map(|arr| {
                arr.iter()
                    .filter_map(|v| v.as_str().map(String::from))
                    .collect()
            })
            .unwrap_or_default();
        let commands = contributes
            .and_then(|c| c.get("commands"))
            .and_then(|cmds| cmds.as_arr())
            .map(|arr| {
                arr.iter()
                    .filter_map(|c| c.get("id").and_then(|id| id.as_str()).map(String::from))
                    .collect()
            })
            .unwrap_or_default();
        let protocol = manifest
            .get("protocol")
            .and_then(|p| p.as_str())
            .map(String::from);
        let panels = contributes
            .and_then(|c| c.get("panels"))
            .and_then(|p| p.as_arr())
            .map(|s| s.to_vec())
            .unwrap_or_default();
        let mut values = HashMap::new();
        if let Some(prefs) = manifest.get("preferences").and_then(|p| p.as_arr()) {
            for p in prefs {
                if let (Some(id), Some(def)) =
                    (p.get("id").and_then(|k| k.as_str()), p.get("default"))
                {
                    values.insert(id.to_string(), def.clone());
                }
            }
        }
        Self {
            link,
            data_folder: data_folder.into(),
            features,
            shows_status,
            shows_activity,
            has_slot,
            docked: 0,
            statuses: Vec::new(),
            status_refused: 0,
            drew_choice: false,
            uses,
            commands,
            protocol,
            panels,
            rendered: HashMap::new(),
            values,
            next_id: 0,
            refused: 0,
        }
    }

    pub fn default_features() -> Option<Vec<String>> {
        Some(FEATURES.iter().map(|s| (*s).to_string()).collect())
    }

    pub fn has_feature(&self, feat: &str) -> bool {
        self.features
            .as_ref()
            .is_some_and(|list| list.iter().any(|f| f == feat))
    }

    pub fn request(&mut self, method: &str, params: Value) -> Result<Value, Failure> {
        self.next_id += 1;
        let id = Value::Int(self.next_id.to_string());
        let msg = Value::Obj(vec![
            ("jsonrpc".into(), Value::Str("2.0".into())),
            ("id".into(), id.clone()),
            ("method".into(), Value::Str(method.into())),
            ("params".into(), params),
        ]);
        self.link.send(&msg)?;
        Ok(id)
    }

    pub fn fail(
        &mut self,
        request: &Value,
        code: i64,
        message: &str,
        data: Option<Value>,
    ) -> Result<(), Failure> {
        let mut error = vec![
            ("code".into(), Value::Int(code.to_string())),
            ("message".into(), Value::Str(message.into())),
        ];
        if let Some(d) = data {
            error.push(("data".into(), d));
        }
        let id = request.get("id").cloned().unwrap_or(Value::Null);
        let msg = Value::Obj(vec![
            ("jsonrpc".into(), Value::Str("2.0".into())),
            ("id".into(), id),
            ("error".into(), Value::Obj(error)),
        ]);
        self.link.send(&msg)
    }

    /// Answers one request from the tool as the app would.
    pub fn serve(&mut self, request: &Value, refuse_all: bool) -> Result<(), Failure> {
        let method = request
            .get("method")
            .and_then(|m| m.as_str())
            .unwrap_or("")
            .to_string();
        let empty = Value::Obj(Vec::new());
        let params = request.get("params").unwrap_or(&empty);
        if method == "ui/status" {
            return self.status(request, refuse_all);
        }
        if let Some((feature, instead)) = gated_spec(&method) {
            if !self.has_feature(feature) {
                self.fail(request, METHOD_NOT_FOUND, "method not found", None)?;
                return Err(Failure::new(format!(
                    "{} to an app whose hello does not name {}. That app answers it with -32601: ask what the app has first, and {}",
                    method, feature, instead
                )));
            }
        }
        if method == "ui/dock" {
            return self.dock(request, refuse_all);
        }
        let (service, mut result) = match service_spec(&method) {
            Some(spec) => spec,
            None => return self.fail(request, METHOD_NOT_FOUND, "method not found", None),
        };
        if !self.uses.contains(service) {
            self.refused += 1;
            return self.fail(
                request,
                NOT_IN_USES,
                "not listed in uses",
                Some(Value::Obj(vec![(
                    "service".into(),
                    Value::Str(service.into()),
                )])),
            );
        }
        if refuse_all {
            self.refused += 1;
            return self.fail(request, UNAVAILABLE, "not available right now", None);
        }
        if service == "storage" {
            let key = params.get("key").and_then(|k| k.as_str()).unwrap_or("");
            if !self.values.contains_key(key) {
                return self.fail(
                    request,
                    INVALID_PARAMS,
                    "not a preference the manifest declares",
                    None,
                );
            }
            if method == "storage/set" {
                let val = params.get("value").cloned().unwrap_or(Value::Null);
                self.values.insert(key.to_string(), val);
            } else {
                let stored = self.values.get(key).cloned().unwrap_or(Value::Null);
                result = Value::Obj(vec![("value".into(), stored)]);
            }
        }
        let id = request.get("id").cloned().unwrap_or(Value::Null);
        self.link.send(&Value::Obj(vec![
            ("jsonrpc".into(), Value::Str("2.0".into())),
            ("id".into(), id),
            ("result".into(), result),
        ]))
    }

    /// Answers `ui/status` as the app would.
    pub fn status(&mut self, request: &Value, refuse_all: bool) -> Result<(), Failure> {
        if self.features.is_none() {
            self.status_refused += 1;
            self.fail(request, METHOD_NOT_FOUND, "unknown method", None)?;
            if self.status_refused > MAX_STATUS_AFTER_REFUSAL {
                return Err(Failure::new(format!(
                    "the tool went on sending ui/status to an app that answered it with -32601: {} times. Ask what the app has first, or stop at the first refusal",
                    self.status_refused
                )));
            }
            return Ok(());
        }
        if !self.shows_status {
            self.fail(
                request,
                INVALID_PARAMS,
                "the manifest declares no status",
                None,
            )?;
            return Err(Failure::new(
                "ui/status from a tool whose manifest declares no status. The app answers it with -32602: add `contributes.status`",
            ));
        }
        if refuse_all {
            self.refused += 1;
            return self.fail(request, UNAVAILABLE, "not available right now", None);
        }
        let empty = Value::Obj(Vec::new());
        let params = request.get("params").unwrap_or(&empty);
        if let Some(state) = params.get("state").and_then(|s| s.as_str()) {
            self.statuses.push(state.to_string());
        }
        let id = request.get("id").cloned().unwrap_or(Value::Null);
        self.link.send(&Value::Obj(vec![
            ("jsonrpc".into(), Value::Str("2.0".into())),
            ("id".into(), id),
            ("result".into(), Value::Obj(Vec::new())),
        ]))?;
        let words = params.has("activity") || params.has("since");
        if words && !self.shows_activity {
            return Err(Failure::new(
                "ui/status with words from a tool whose manifest does not declare them. The app draws the mark and leaves the words out: add \"activity\": true to contributes.status",
            ));
        }
        Ok(())
    }

    /// Answers `ui/dock` as the app would.
    pub fn dock(&mut self, request: &Value, refuse_all: bool) -> Result<(), Failure> {
        if !self.has_slot {
            self.fail(
                request,
                INVALID_PARAMS,
                "the manifest declares no slot",
                None,
            )?;
            return Err(Failure::new(
                "ui/dock from a tool whose manifest declares no slot. The app answers it with -32602: add `contributes.slot`",
            ));
        }
        if refuse_all {
            self.refused += 1;
            return self.fail(request, UNAVAILABLE, "not available right now", None);
        }
        self.docked += 1;
        let id = request.get("id").cloned().unwrap_or(Value::Null);
        self.link.send(&Value::Obj(vec![
            ("jsonrpc".into(), Value::Str("2.0".into())),
            ("id".into(), id),
            ("result".into(), Value::Obj(Vec::new())),
        ]))
    }

    /// Plays the app until the tool answers request `request_id`.
    pub fn answer(
        &mut self,
        request_id: &Value,
        seconds: u64,
        refuse_all: bool,
    ) -> Result<(MsgKind, Value), Failure> {
        let deadline = Instant::now() + Duration::from_secs(seconds);
        loop {
            let message = self
                .link
                .receive(deadline, seconds, false)?
                .ok_or_else(|| Failure::new("the tool exited"))?;
            let kind = kind_of(&message)?;
            if matches!(kind, MsgKind::Request | MsgKind::Notice) {
                check_params(&message)?;
            }
            if kind == MsgKind::Notice
                && message.get("method").and_then(|m| m.as_str()) == Some("ui/render")
            {
                if let Some(params) = message.get("params") {
                    self.render(params)?;
                }
            }
            if kind == MsgKind::Request {
                self.serve(&message, refuse_all)?;
            } else if matches!(kind, MsgKind::Result | MsgKind::Failure) {
                let msg_id = message.get("id").unwrap_or(&Value::Null);
                if !json::py_eq(msg_id, request_id) {
                    return Err(Failure::new(format!(
                        "an answer to a request that was not waiting: {}",
                        message.py_repr()
                    )));
                }
                return Ok((kind, message));
            }
        }
    }

    /// A page the tool sent unprompted: for a panel its manifest declares.
    pub fn render(&mut self, params: &Value) -> Result<(), Failure> {
        let panel = params.get("panel").and_then(|p| p.as_str()).unwrap_or("");
        let declared = self
            .panels
            .iter()
            .any(|p| p.get("id").and_then(|id| id.as_str()) == Some(panel));
        if !declared {
            return Err(Failure::new(format!(
                "ui/render for a panel the manifest does not declare: {}",
                panel
            )));
        }
        let tree = params.get("tree").cloned().unwrap_or(Value::Null);
        if let Some(wrong) = misnamed(&tree, panel) {
            return Err(Failure::new(wrong));
        }
        self.rendered.insert(panel.to_string(), tree);
        Ok(())
    }

    /// What `initialize` carries. An app before 3.48 has no `features`.
    pub fn hello(&self) -> Value {
        let versions = Value::Arr(VERSIONS.iter().map(|v| Value::Str((*v).into())).collect());
        let mut items = vec![
            ("protocolVersions".into(), versions),
            ("language".into(), Value::Str("en-US".into())),
            ("dataFolder".into(), Value::Str(self.data_folder.clone())),
        ];
        if let Some(feats) = &self.features {
            items.push((
                "features".into(),
                Value::Arr(feats.iter().map(|f| Value::Str(f.clone())).collect()),
            ));
        }
        Value::Obj(items)
    }

    pub fn handshake(&mut self) -> Result<String, Failure> {
        let hello = self.hello();
        let sent = self.request("initialize", hello)?;
        let deadline = Instant::now() + Duration::from_secs(FIRST_ANSWER_SECONDS);
        let message = self
            .link
            .receive(deadline, FIRST_ANSWER_SECONDS, false)?
            .ok_or_else(|| Failure::new("the tool exited"))?;
        let kind = kind_of(&message)?;
        if kind != MsgKind::Result || !message.get("id").is_some_and(|id| json::py_eq(id, &sent)) {
            return Err(Failure::new(format!(
                "something other than the answer to initialize came first: {}",
                message.py_repr()
            )));
        }
        let result = message.get("result").unwrap_or(&Value::Null);
        let proto_ver = result
            .get("protocolVersion")
            .and_then(|v| v.as_str())
            .filter(|v| VERSIONS.contains(v));
        let proto_ver = match proto_ver {
            Some(v) if result.is_dict() => v,
            _ => {
                return Err(Failure::new(format!(
                    "the tool picked a version that was not offered: {}",
                    result.py_repr()
                )));
            }
        };
        let tool_ver = match result.get("toolVersion").and_then(|v| v.as_str()) {
            Some(v) => v,
            None => {
                return Err(Failure::new(format!(
                    "the tool did not say its own version: {}",
                    result.py_repr()
                )));
            }
        };
        let mut said = format!("version {}, tool {}", proto_ver, tool_ver);
        if self.has_slot && self.has_feature("ui.slot") {
            self.link.send(&Value::Obj(vec![
                ("jsonrpc".into(), Value::Str("2.0".into())),
                ("method".into(), Value::Str("ui/slot".into())),
                (
                    "params".into(),
                    Value::Obj(vec![
                        ("visible".into(), Value::Bool(true)),
                        ("x".into(), Value::Int("0".into())),
                        ("y".into(), Value::Int("0".into())),
                        ("width".into(), Value::Int("400".into())),
                        ("height".into(), Value::Int("300".into())),
                    ]),
                ),
            ]))?;
            said.push_str(", and told where its slot is");
        }
        Ok(said)
    }

    pub fn a_command(&mut self) -> Result<String, Failure> {
        if self.commands.is_empty() {
            return Ok("the manifest declares no command".into());
        }
        let before = self.statuses.len();
        let docked = self.docked;
        let cmd = self.commands[0].clone();
        let sent = self.request(
            "command/run",
            Value::Obj(vec![("command".into(), Value::Str(cmd.clone()))]),
        )?;
        let (kind, message) = self.answer(&sent, ANSWER_SECONDS, false)?;
        if kind == MsgKind::Result && !message.get("result").is_some_and(|r| r.is_dict()) {
            return Err(Failure::new(format!(
                "a result that is not an object: {}",
                message.py_repr()
            )));
        }
        let outcome = if kind == MsgKind::Result {
            "ran".to_string()
        } else {
            let err_msg = message
                .get("error")
                .and_then(|e| e.get("message"))
                .and_then(|m| m.as_str())
                .unwrap_or("");
            format!("refused, {}", err_msg)
        };
        let mut said = format!("{}: {}", cmd, outcome);
        if self.statuses.len() > before {
            said.push_str(&format!(
                ", and set the status: {}",
                self.statuses[before..].join(", ")
            ));
        }
        if self.docked > docked {
            said.push_str(", and asked for its slot");
        }
        Ok(said)
    }

    pub fn unknown(&mut self) -> Result<String, Failure> {
        let sent = self.request(
            "command/run",
            Value::Obj(vec![(
                "command".into(),
                Value::Str("conformance.no-such-command".into()),
            )]),
        )?;
        let (kind, message) = self.answer(&sent, ANSWER_SECONDS, false)?;
        if kind != MsgKind::Failure {
            return Err(Failure::new(format!(
                "a command the tool does not have was answered as done: {}",
                message.py_repr()
            )));
        }
        let code = message
            .get("error")
            .and_then(|e| e.get("code"))
            .map(|c| c.py_str())
            .unwrap_or_default();
        Ok(format!("failure {}", code))
    }

    /// The ids of the panels the app draws from blocks, in the manifest's order.
    pub fn drawn(&self) -> Vec<String> {
        if self.protocol.as_deref() != Some("2") {
            return Vec::new();
        }
        self.panels
            .iter()
            .filter(|panel| {
                panel
                    .get("kind")
                    .and_then(|k| k.as_str())
                    .unwrap_or("blocks")
                    == "blocks"
            })
            .filter_map(|panel| panel.get("id").and_then(|id| id.as_str()).map(String::from))
            .collect()
    }

    /// Opens `panel` and reads the page it is answered with.
    pub fn opened_page(&mut self, panel: &str) -> Result<Value, Failure> {
        let sent = self.request(
            "ui/open",
            Value::Obj(vec![("panel".into(), Value::Str(panel.into()))]),
        )?;
        let (kind, message) = self.answer(&sent, ANSWER_SECONDS, false)?;
        let result = match message.get("result") {
            Some(r) if kind == MsgKind::Result && r.is_dict() => r,
            _ => {
                return Err(Failure::new(format!(
                    "ui/open was not answered with a result: {}",
                    message.py_repr()
                )));
            }
        };
        let page = result
            .get("tree")
            .or_else(|| self.rendered.get(panel))
            .cloned();
        let page = match page {
            Some(p) if is_tree(&p) => p,
            _ => {
                return Err(Failure::new(format!(
                    "ui/open was not answered with a page: {}",
                    message.py_repr()
                )));
            }
        };
        if let Some(wrong) = misnamed(&page, panel) {
            return Err(Failure::new(wrong));
        }
        if let Some(blocks) = page.get("blocks").and_then(|b| b.as_arr()) {
            if blocks
                .iter()
                .any(|b| b.get("type").and_then(|t| t.as_str()) == Some("choice"))
            {
                self.drew_choice = true;
            }
        }
        if let Some(newer) = newer_than(&page, self.features.as_deref(), panel) {
            return Err(Failure::new(newer));
        }
        Ok(page)
    }

    pub fn a_panel(&mut self) -> Result<String, Failure> {
        let drawn = self.drawn();
        if drawn.is_empty() {
            return Ok("the manifest declares no panel the app draws".into());
        }
        let mut said = self.first_panel(&drawn[0])?;
        for panel in &drawn[1..] {
            let page = self.opened_page(panel)?;
            let block_count = page
                .get("blocks")
                .and_then(|b| b.as_arr())
                .map(|a| a.len())
                .unwrap_or(0);
            said.push_str(&format!("; {}: a page of {} blocks", panel, block_count));
            self.link.send(&Value::Obj(vec![
                ("jsonrpc".into(), Value::Str("2.0".into())),
                ("method".into(), Value::Str("ui/close".into())),
                (
                    "params".into(),
                    Value::Obj(vec![("panel".into(), Value::Str(panel.clone()))]),
                ),
            ]))?;
        }
        Ok(said)
    }

    pub fn first_panel(&mut self, panel: &str) -> Result<String, Failure> {
        let first = self.opened_page(panel)?;
        let blocks = first.get("blocks").and_then(|b| b.as_arr()).unwrap_or(&[]);
        let buttons: Vec<String> = blocks
            .iter()
            .filter(|b| b.is_dict() && b.get("type").and_then(|t| t.as_str()) == Some("button"))
            .filter_map(|b| b.get("id").and_then(|id| id.as_str()).map(String::from))
            .collect();
        let mut said = format!("{}: a page of {} blocks", panel, blocks.len());
        if let Some(btn) = buttons.first() {
            let sent = self.request(
                "ui/event",
                Value::Obj(vec![
                    ("panel".into(), Value::Str(panel.into())),
                    ("block".into(), Value::Str(btn.clone())),
                    ("event".into(), Value::Str("tap".into())),
                ]),
            )?;
            let (kind, message) = self.answer(&sent, ANSWER_SECONDS, false)?;
            let result = match message.get("result") {
                Some(r) if kind == MsgKind::Result && r.is_dict() => r,
                _ => {
                    return Err(Failure::new(format!(
                        "a tap was not answered with a result: {}",
                        message.py_repr()
                    )));
                }
            };
            if let Some(tree) = result.get("tree") {
                if !is_tree(tree) {
                    return Err(Failure::new(format!(
                        "a tap was answered with something that is not a page: {}",
                        result.py_repr()
                    )));
                }
                if let Some(wrong) = misnamed(tree, panel) {
                    return Err(Failure::new(wrong));
                }
            }
            let nxt = result
                .get("tree")
                .or_else(|| self.rendered.get(panel))
                .cloned();
            if let Some(ref nxt_page) = nxt {
                if let Some(newer) = newer_than(nxt_page, self.features.as_deref(), panel) {
                    return Err(Failure::new(newer));
                }
            }
            let opened = self.opened(result)?;
            if let Some(opened_desc) = opened {
                said.push_str(&format!(", and {} after a tap on {}", opened_desc, btn));
            } else if result.get("keep").and_then(|k| k.as_bool()) != Some(true)
                && nxt.as_ref().map_or(true, |n| json::py_eq(n, &first))
            {
                return Err(Failure::new(format!(
                    "a tap on {} was answered with the same page",
                    btn
                )));
            } else {
                said.push_str(&format!(", and a new page after a tap on {}", btn));
            }
        }
        self.link.send(&Value::Obj(vec![
            ("jsonrpc".into(), Value::Str("2.0".into())),
            ("method".into(), Value::Str("ui/close".into())),
            (
                "params".into(),
                Value::Obj(vec![("panel".into(), Value::Str(panel.into()))]),
            ),
        ]))?;
        Ok(said)
    }

    pub fn opened(&self, result: &Value) -> Result<Option<String>, Failure> {
        let name_val = match result.get("open") {
            Some(v) => v,
            None => return Ok(None),
        };
        let name = match name_val.as_str() {
            Some(s) if is_text(name_val) => s,
            _ => {
                return Err(Failure::new(format!(
                    "a tap's open is not a panel's id: {}",
                    result.py_repr()
                )));
            }
        };
        let placement = self
            .panels
            .iter()
            .find(|p| p.get("id").and_then(|id| id.as_str()) == Some(name))
            .and_then(|p| p.get("placement"))
            .filter(|v| !matches!(v, Value::Null));
        let placement_val = match placement {
            Some(p) => p,
            None => {
                return Err(Failure::new(format!(
                    "a tap's open names {}, a panel the manifest does not declare",
                    name
                )));
            }
        };
        let placement_str = placement_val.py_str();
        if placement_str == "window" {
            return Ok(Some(format!("the window {}", name)));
        }
        if placement_str == "settings" {
            if !self.has_feature("ui.open.settings") {
                return Err(Failure::new(format!(
                    "a tap's open names the settings panel {}, which an app without ui.open.settings does not open: ask supports first",
                    name
                )));
            }
            return Ok(Some(format!("the settings panel {}", name)));
        }
        Err(Failure::new(format!(
            "a tap's open names {}, a panel of the {}, which the app does not open: only a window or the tool's settings panel opens",
            name, placement_str
        )))
    }

    pub fn refusals(&mut self) -> Result<String, Failure> {
        if self.commands.is_empty() {
            return Ok("the manifest declares no command".into());
        }
        let before = self.refused;
        let cmd = self.commands[0].clone();
        let sent = self.request(
            "command/run",
            Value::Obj(vec![("command".into(), Value::Str(cmd))]),
        )?;
        self.answer(&sent, ANSWER_SECONDS, true)?;
        let count = self.refused - before;
        if count > 0 {
            Ok(format!("{} refused", count))
        } else {
            Ok("the tool asked the app for nothing, so nothing was refused".into())
        }
    }

    pub fn shutdown(&mut self) -> Result<String, Failure> {
        self.link.send(&Value::Obj(vec![
            ("jsonrpc".into(), Value::Str("2.0".into())),
            ("method".into(), Value::Str("shutdown".into())),
        ]))?;
        self.link.close_stdin();
        let status = self.link.wait_exit(Duration::from_secs(EXIT_SECONDS))?;
        if status != 0 {
            return Err(Failure::new(format!("exited with {}", status)));
        }
        let more = self.last_words()?;
        if more > 0 {
            let plural = if more > 1 { "s" } else { "" };
            Ok(format!(
                "exited with 0, after {} more message{}",
                more, plural
            ))
        } else {
            Ok("exited with 0".into())
        }
    }

    /// Reads what the tool wrote after its last answer, to the end.
    pub fn last_words(&mut self) -> Result<usize, Failure> {
        let mut count = 0usize;
        let deadline = Instant::now() + Duration::from_secs(EXIT_SECONDS);
        loop {
            if Instant::now() >= deadline {
                return Err(Failure::new(format!(
                    "still writing {} seconds after it exited",
                    EXIT_SECONDS
                )));
            }
            let message = match self.link.receive(deadline, EXIT_SECONDS, true)? {
                Some(m) => m,
                None => return Ok(count),
            };
            count += 1;
            let kind = kind_of(&message)?;
            if matches!(kind, MsgKind::Result | MsgKind::Failure) {
                return Err(Failure::new(format!(
                    "an answer to a request that was not waiting: {}",
                    message.py_repr()
                )));
            }
            check_params(&message)?;
        }
    }
}

/// RAII temporary directory (`vitruvian-conformance-*`).
pub struct TempDir {
    path: PathBuf,
}

impl TempDir {
    pub fn new(prefix: &str) -> io::Result<Self> {
        static COUNTER: AtomicU64 = AtomicU64::new(0);
        let base = std::env::temp_dir();
        let pid = std::process::id();
        for _ in 0..256 {
            let seq = COUNTER.fetch_add(1, Ordering::Relaxed);
            let nanos = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_nanos();
            let dir_name = format!("{}{}-{}-{}", prefix, pid, nanos, seq);
            let candidate = base.join(dir_name);
            match fs::create_dir(&candidate) {
                Ok(()) => return Ok(Self { path: candidate }),
                Err(e) if e.kind() == io::ErrorKind::AlreadyExists => continue,
                Err(e) => return Err(e),
            }
        }
        Err(io::Error::new(
            io::ErrorKind::AlreadyExists,
            "failed to create unique temporary directory",
        ))
    }

    pub fn path(&self) -> &Path {
        &self.path
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.path);
    }
}

/// The tool, started once more by an app from before 3.48: its hello names no
/// `features`, and it answers `ui/status` with -32601.
pub fn an_older_app(command: &[String], manifest: &Value) -> Result<String, Failure> {
    let temp = TempDir::new("vitruvian-conformance-").map_err(|e| Failure::new(e.to_string()))?;
    let data_folder = temp.path().to_string_lossy().into_owned();
    let link = Link::spawn(command, temp.path()).map_err(|e| Failure::new(e.to_string()))?;
    let mut run = Run::new(link, manifest, data_folder, None);
    let mut did = Vec::new();
    let step_result: Result<(), Failure> = (|| {
        run.handshake()?;
        did.push("answered the hello".to_string());
        if !run.commands.is_empty() {
            run.a_command()?;
            did.push(format!("ran {}", run.commands[0]));
        }
        let panel_said = run.a_panel()?;
        if !panel_said.starts_with("the manifest declares no panel") {
            for panel in run.drawn() {
                did.push(format!("drew {}", panel));
            }
        }
        run.shutdown()?;
        Ok(())
    })();
    run.link.close();
    if let Err(failure) = step_result {
        if run.status_refused == 0
            || failure.0.starts_with("the tool went on")
            || failure.0.starts_with("the page of")
        {
            return Err(failure);
        }
        return Err(Failure::new(format!(
            "the tool did not carry on after an app that has no ui/status refused it with -32601 ({}). Ask what the app has first, or treat the refusal as no status",
            failure.0
        )));
    }
    let mut said = format!("{} and left with 0; ", did.join(", "));
    if run.status_refused > 0 {
        said.push_str(&format!(
            "{} ui/status refused with -32601, as an app before 3.48 does",
            run.status_refused
        ));
    } else {
        said.push_str("it sent no ui/status");
    }
    if run.drew_choice {
        said.push_str(
            "; its page holds a choice, which that app draws as its fallback text and nobody can change: send a field to an app without ui.choice",
        );
    }
    Ok(said)
}
