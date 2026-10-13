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

//! The link to the app, from the tool's end: one thread reads lines and
//! hands each message over, and the thread that serves writes.

use std::io::{BufRead, BufReader, ErrorKind, Read, Write};
use std::sync::mpsc::{sync_channel, Receiver, RecvTimeoutError, SyncSender, TryRecvError};
use std::thread;
use std::time::Instant;

use serde::Serialize;
use serde_json::Value;

use crate::generated::Error;

/// The longest line the protocol allows, not counting its line break.
const MAX_LINE_BYTES: usize = 1_048_576;

/// One line on the link, taken apart.
pub(crate) enum Message {
    Request {
        id: Value,
        method: String,
        params: Option<Value>,
    },
    Notice {
        method: String,
        params: Option<Value>,
    },
    Answer {
        id: Value,
        result: Result<Value, Error>,
    },
}

/// Takes a line apart. None for a line that is not a message of JSON-RPC
/// 2.0: it is dropped, as there is nothing to answer.
pub(crate) fn parse(line: &[u8]) -> Option<Message> {
    let value: Value = serde_json::from_slice(line).ok()?;
    let object = value.as_object()?;
    if object.get("jsonrpc")?.as_str()? != "2.0" {
        return None;
    }
    let id = object.get("id");
    let is_id = |id: &Value| id.is_string() || id.as_i64().is_some();
    if let Some(method) = object.get("method") {
        let method = method.as_str().filter(|method| !method.is_empty())?;
        if object.contains_key("result") || object.contains_key("error") {
            return None;
        }
        let params = match object.get("params") {
            Some(params) if params.is_object() => Some(params.clone()),
            Some(_) => return None,
            None => None,
        };
        return Some(match id {
            Some(id) if is_id(id) => Message::Request {
                id: id.clone(),
                method: method.to_string(),
                params,
            },
            Some(_) => return None,
            None => Message::Notice {
                method: method.to_string(),
                params,
            },
        });
    }
    if let Some(error) = object.get("error") {
        if object.contains_key("result") {
            return None;
        }
        return Some(Message::Answer {
            id: id?.clone(),
            result: Err(serde_json::from_value(error.clone()).ok()?),
        });
    }
    Some(Message::Answer {
        id: id.filter(|id| is_id(id))?.clone(),
        result: Ok(object.get("result")?.clone()),
    })
}

/// What waiting on the link came to.
pub(crate) enum Next {
    Got(Message),
    /// The app closed the link, or it broke.
    Ended,
    /// The time given passed first.
    Late,
}

/// A message this tool writes.
#[derive(Serialize)]
pub(crate) struct Outgoing<'a> {
    pub jsonrpc: &'static str,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub id: Option<&'a Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub method: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub params: Option<&'a Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub result: Option<&'a Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<&'a Error>,
}

impl Outgoing<'_> {
    pub fn new() -> Self {
        Outgoing {
            jsonrpc: "2.0",
            id: None,
            method: None,
            params: None,
            result: None,
            error: None,
        }
    }
}

pub(crate) struct Link {
    input: Option<Box<dyn Read + Send>>,
    inbox: Option<Receiver<Message>>,
    output: Box<dyn Write>,
    broken: bool,
}

impl Link {
    pub fn new(input: Box<dyn Read + Send>, output: Box<dyn Write>) -> Self {
        Link {
            input: Some(input),
            inbox: None,
            output,
            broken: false,
        }
    }

    /// Starts the reading thread. It hands over one message at a time and
    /// waits until it is taken, so the app cannot get ahead of the tool by
    /// more than one line.
    pub fn start(&mut self) {
        if let Some(input) = self.input.take() {
            let (sender, receiver) = sync_channel(0);
            self.inbox = Some(receiver);
            thread::spawn(move || read(input, sender));
        }
    }

    /// The next message. With `deadline` None it waits for as long as the
    /// link is open. A message that has already come is handed over even
    /// when the time is up.
    pub fn next(&mut self, deadline: Option<Instant>) -> Next {
        let inbox = match (&self.inbox, self.broken) {
            (Some(inbox), false) => inbox,
            _ => return Next::Ended,
        };
        match inbox.try_recv() {
            Ok(message) => return Next::Got(message),
            Err(TryRecvError::Disconnected) => return Next::Ended,
            Err(TryRecvError::Empty) => {}
        }
        match deadline {
            None => inbox.recv().map_or(Next::Ended, Next::Got),
            Some(deadline) => {
                match inbox.recv_timeout(deadline.saturating_duration_since(Instant::now())) {
                    Ok(message) => Next::Got(message),
                    Err(RecvTimeoutError::Timeout) => Next::Late,
                    Err(RecvTimeoutError::Disconnected) => Next::Ended,
                }
            }
        }
    }

    /// Writes one message as one line. False when it could not be written;
    /// the link has then ended.
    pub fn send(&mut self, message: &Outgoing) -> bool {
        if self.broken {
            return false;
        }
        let Ok(mut line) = serde_json::to_vec(message) else {
            return false;
        };
        line.push(b'\n');
        if self
            .output
            .write_all(&line)
            .and_then(|_| self.output.flush())
            .is_err()
        {
            self.broken = true;
            return false;
        }
        true
    }
}

/// The reading thread. A line over the limit is dropped, and so is a last
/// line with no line break: the protocol never delivers it.
fn read(input: Box<dyn Read + Send>, inbox: SyncSender<Message>) {
    let mut reader = BufReader::with_capacity(64 * 1024, input);
    let mut line = Vec::new();
    let mut too_long = false;
    loop {
        let (used, ended_line) = match reader.fill_buf() {
            Ok([]) => return,
            Ok(buffer) => match buffer.iter().position(|byte| *byte == b'\n') {
                Some(at) => {
                    if !too_long && line.len() + at <= MAX_LINE_BYTES {
                        line.extend_from_slice(&buffer[..at]);
                    } else {
                        too_long = true;
                    }
                    (at + 1, true)
                }
                None => {
                    if !too_long && line.len() + buffer.len() <= MAX_LINE_BYTES {
                        line.extend_from_slice(buffer);
                    } else {
                        too_long = true;
                        line.clear();
                    }
                    (buffer.len(), false)
                }
            },
            Err(error) if error.kind() == ErrorKind::Interrupted => continue,
            Err(_) => return,
        };
        reader.consume(used);
        if ended_line {
            if !too_long {
                if let Some(message) = parse(&line) {
                    if inbox.send(message).is_err() {
                        return;
                    }
                }
            }
            line.clear();
            too_long = false;
        }
    }
}
