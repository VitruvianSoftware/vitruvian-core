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

use std::collections::{HashMap, VecDeque};
use std::io::{Read, Write};
use std::path::PathBuf;
use std::time::{Duration, Instant};

use serde::de::DeserializeOwned;
use serde::Serialize;
use serde_json::{Map, Value};

use crate::app::App;
use crate::error::{codes, ToolError};
use crate::generated::{
    methods, CommandRunParams, Empty, Error, InitializeParams, InitializeResult,
    LanguageChangedParams, PreferencesChangedParams, PROTOCOL_VERSION,
};
use crate::link::{Link, Message, Next, Outgoing};

type Handler = Box<dyn FnMut(&mut App<'_>) -> Result<(), ToolError>>;
type Hook = Box<dyn FnMut(&mut App<'_>)>;
type PreferencesHook = Box<dyn FnMut(&mut App<'_>, &Map<String, Value>)>;

/// A tool that runs as its own program: its commands, and the loop that
/// reads what the app sends and answers it. Make one with [`Tool::new`],
/// add its commands, then call [`Tool::run`].
pub struct Tool {
    handlers: HashMap<String, Handler>,
    on_start: Option<Hook>,
    on_preferences_changed: Option<PreferencesHook>,
    on_language_changed: Option<Hook>,
    state: State,
}

/// What a handler's [`App`] reaches: the link and what it has learnt.
pub(crate) struct State {
    pub link: Link,
    pub version: String,
    pub answer_timeout: Duration,
    pub kept: VecDeque<Message>,
    pub last_id: i64,
    pub greeted: bool,
    pub stopping: bool,
    pub language: String,
    pub data_folder: PathBuf,
}

impl Tool {
    /// A tool that talks to the app over standard input and output.
    /// `version` is the tool's own, as its manifest gives it.
    pub fn new(version: &str) -> Tool {
        Tool::with_link(version, std::io::stdin(), std::io::stdout())
    }

    /// A tool that talks to the app over `input` and `output`. It is for a
    /// test; a tool uses [`Tool::new`].
    pub fn with_link(
        version: &str,
        input: impl Read + Send + 'static,
        output: impl Write + 'static,
    ) -> Tool {
        Tool {
            handlers: HashMap::new(),
            on_start: None,
            on_preferences_changed: None,
            on_language_changed: None,
            state: State {
                link: Link::new(Box::new(input), Box::new(output)),
                version: version.to_string(),
                answer_timeout: Duration::from_secs(10),
                kept: VecDeque::new(),
                last_id: 0,
                greeted: false,
                stopping: false,
                language: "en".to_string(),
                data_folder: std::env::current_dir().unwrap_or_default(),
            },
        }
    }

    /// Says what a command does. `id` is the one the manifest gives it. The
    /// handler returns `Ok(())` when the command ran; any error refuses it.
    pub fn command(
        &mut self,
        id: &str,
        handler: impl FnMut(&mut App<'_>) -> Result<(), ToolError> + 'static,
    ) {
        self.handlers.insert(id.to_string(), Box::new(handler));
    }

    /// Called once, after the app has said hello and been answered.
    pub fn on_start(&mut self, hook: impl FnMut(&mut App<'_>) + 'static) {
        self.on_start = Some(Box::new(hook));
    }

    /// Called when the person changed preferences: each one's id and value.
    pub fn on_preferences_changed(
        &mut self,
        hook: impl FnMut(&mut App<'_>, &Map<String, Value>) + 'static,
    ) {
        self.on_preferences_changed = Some(Box::new(hook));
    }

    /// Called when the person changed the app's language. [`App::language`]
    /// is already the new one.
    pub fn on_language_changed(&mut self, hook: impl FnMut(&mut App<'_>) + 'static) {
        self.on_language_changed = Some(Box::new(hook));
    }

    /// How long a call to the app waits for its answer. Ten seconds.
    pub fn set_answer_timeout(&mut self, timeout: Duration) {
        self.state.answer_timeout = timeout;
    }

    /// Reads and answers until the app says goodbye, then exits with 0.
    pub fn run(mut self) -> ! {
        std::process::exit(self.serve())
    }

    /// Reads and answers until the app says goodbye or the link ends, and
    /// returns the status to exit with, which is 0: the app going away is
    /// not the tool's failure. A link that has gone is a failed write, not
    /// a signal: Rust's runtime ignores the broken-pipe signal.
    pub fn serve(&mut self) -> i32 {
        self.state.link.start();
        while !self.state.stopping {
            let message = match self.state.kept.pop_front() {
                Some(message) => message,
                None => match self.state.link.next(None) {
                    Next::Got(message) => message,
                    Next::Ended | Next::Late => {
                        self.state.stopping = true;
                        continue;
                    }
                },
            };
            self.handle(message);
        }
        0
    }

    fn handle(&mut self, message: Message) {
        match message {
            Message::Request { id, method, params } => match method.as_str() {
                methods::INITIALIZE => self.greet(id, params),
                methods::COMMAND_RUN => self.run_command(id, params),
                _ => self
                    .state
                    .refuse(&id, codes::METHOD_NOT_FOUND, "method not found", None),
            },
            Message::Notice { method, params } => match method.as_str() {
                methods::SHUTDOWN => self.state.stopping = true,
                methods::PREFERENCES_CHANGED => {
                    if let Some(changed) = decode::<PreferencesChangedParams>(params) {
                        if let Some(hook) = self.on_preferences_changed.as_mut() {
                            hook(&mut App::new(&mut self.state), &changed.values);
                        }
                    }
                }
                methods::LANGUAGE_CHANGED => {
                    if let Some(changed) = decode::<LanguageChangedParams>(params) {
                        self.state.language = changed.language;
                        if let Some(hook) = self.on_language_changed.as_mut() {
                            hook(&mut App::new(&mut self.state));
                        }
                    }
                }
                _ => {}
            },
            // An answer nobody waits for: it came after its call gave up.
            Message::Answer { .. } => {}
        }
    }

    fn greet(&mut self, id: Value, params: Option<Value>) {
        let Some(hello) = decode::<InitializeParams>(params) else {
            return self
                .state
                .refuse(&id, codes::INVALID_PARAMS, "invalid params", None);
        };
        if !hello
            .protocol_versions
            .iter()
            .any(|v| v == PROTOCOL_VERSION)
        {
            let words = format!("this tool speaks protocol {PROTOCOL_VERSION} only");
            return self.state.refuse(&id, codes::INVALID_PARAMS, &words, None);
        }
        self.state.language = hello.language;
        self.state.data_folder = PathBuf::from(hello.data_folder);
        self.state.greeted = true;
        let answer = InitializeResult {
            protocol_version: PROTOCOL_VERSION.to_string(),
            tool_version: self.state.version.clone(),
        };
        self.state.answer(&id, &answer);
        if let Some(hook) = self.on_start.as_mut() {
            hook(&mut App::new(&mut self.state));
        }
    }

    fn run_command(&mut self, id: Value, params: Option<Value>) {
        if !self.state.greeted {
            let words = "initialize comes first";
            return self.state.refuse(&id, codes::INVALID_REQUEST, words, None);
        }
        let Some(asked) = decode::<CommandRunParams>(params) else {
            return self
                .state
                .refuse(&id, codes::INVALID_PARAMS, "invalid params", None);
        };
        let Some(handler) = self.handlers.get_mut(&asked.command) else {
            return self
                .state
                .refuse(&id, codes::INVALID_PARAMS, "no such command", None);
        };
        match handler(&mut App::new(&mut self.state)) {
            Ok(()) => self.state.answer(&id, &Empty {}),
            Err(ToolError::Refused(why)) => {
                self.state.refuse(&id, codes::COMMAND_REFUSED, &why, None)
            }
            // The app refused something the command needed. Its reason goes
            // with ours, for the log.
            Err(ToolError::App(refusal)) => {
                let data = serde_json::to_value(&refusal).ok();
                let words = "command refused";
                self.state.refuse(&id, codes::COMMAND_REFUSED, words, data)
            }
            Err(other) => {
                let words = other.to_string();
                self.state.refuse(&id, codes::COMMAND_REFUSED, &words, None)
            }
        }
    }
}

/// Reads params that must be there.
fn decode<T: DeserializeOwned>(params: Option<Value>) -> Option<T> {
    serde_json::from_value(params?).ok()
}

impl State {
    pub fn answer(&mut self, id: &Value, result: &impl Serialize) {
        match serde_json::to_value(result) {
            Ok(result) => {
                self.link.send(&Outgoing {
                    id: Some(id),
                    result: Some(&result),
                    ..Outgoing::new()
                });
            }
            Err(_) => {
                let words = "the answer could not be written";
                self.refuse(id, codes::INTERNAL_ERROR, words, None);
            }
        }
    }

    pub fn refuse(&mut self, id: &Value, code: i64, words: &str, data: Option<Value>) {
        let error = Error {
            code,
            message: words.to_string(),
            data,
        };
        self.link.send(&Outgoing {
            id: Some(id),
            error: Some(&error),
            ..Outgoing::new()
        });
    }

    /// Sends a request and reads the link until its answer has come. What
    /// else comes meanwhile is kept, in order, for after the handler.
    pub fn call<R: DeserializeOwned>(
        &mut self,
        method: &str,
        params: &impl Serialize,
    ) -> Result<R, ToolError> {
        if !self.greeted || self.stopping {
            return Err(ToolError::LinkClosed);
        }
        let params = serde_json::to_value(params).map_err(|e| ToolError::Other(e.to_string()))?;
        self.last_id += 1;
        let mine = self.last_id;
        let sent = self.link.send(&Outgoing {
            id: Some(&Value::from(mine)),
            method: Some(method),
            params: Some(&params),
            ..Outgoing::new()
        });
        if !sent {
            self.stopping = true;
            return Err(ToolError::LinkClosed);
        }
        let deadline = Instant::now() + self.answer_timeout;
        loop {
            match self.link.next(Some(deadline)) {
                Next::Ended => {
                    self.stopping = true;
                    return Err(ToolError::LinkClosed);
                }
                Next::Late => return Err(ToolError::NoAnswer(self.answer_timeout)),
                Next::Got(Message::Answer { id, result }) if id.as_i64() == Some(mine) => {
                    return match result {
                        Ok(value) => serde_json::from_value(value)
                            .map_err(|e| ToolError::Other(e.to_string())),
                        Err(refusal) => Err(ToolError::App(refusal)),
                    };
                }
                Next::Got(Message::Notice { method, .. }) if method == methods::SHUTDOWN => {
                    self.stopping = true;
                    return Err(ToolError::LinkClosed);
                }
                Next::Got(other) => self.kept.push_back(other),
            }
        }
    }

    /// Sends a notice. Nothing is sent before the greeting or after
    /// goodbye.
    pub fn note(&mut self, method: &str, params: &impl Serialize) {
        if !self.greeted || self.stopping {
            return;
        }
        if let Ok(params) = serde_json::to_value(params) {
            self.link.send(&Outgoing {
                method: Some(method),
                params: Some(&params),
                ..Outgoing::new()
            });
        }
    }
}
