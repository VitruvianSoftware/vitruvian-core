// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT
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

//! Native Rust port of `packages/vitruvian-sdk/conformance/reference-tool-2/bin/reference_tool_2.py`.
//! The smallest tool that speaks the Vitruvian tool protocol, version 2.

use std::io::{self, BufRead, Write};

use conformance_rs_lib::json::{self, Value};

fn send<W: Write>(out: &mut W, message: &Value) -> io::Result<()> {
    let mut line = message.dumps_compact();
    line.push('\n');
    out.write_all(line.as_bytes())?;
    out.flush()
}

pub fn page(presses: usize) -> Value {
    let words = match presses {
        0 => "Hello. Press the button.".to_string(),
        1 => "Pressed once.".to_string(),
        n => format!("Pressed {n} times."),
    };
    Value::Obj(vec![(
        "blocks".into(),
        Value::Arr(vec![
            Value::Obj(vec![
                ("type".into(), Value::Str("text".into())),
                ("text".into(), Value::Str(words)),
            ]),
            Value::Obj(vec![
                ("type".into(), Value::Str("button".into())),
                ("id".into(), Value::Str("press".into())),
                ("title".into(), Value::Str("Press me".into())),
            ]),
        ]),
    )])
}

pub fn run_session<R: BufRead, W: Write>(reader: R, out: &mut W) -> i32 {
    let mut asked: i64 = 0;
    let mut presses: usize = 0;
    let mut waiting: Vec<(Value, Value)> = Vec::new();
    let empty_obj = Value::Obj(Vec::new());

    for line_res in reader.lines() {
        let line = match line_res {
            Ok(l) => l,
            Err(_) => break,
        };
        if line.trim().is_empty() {
            continue;
        }
        let message = match json::loads(&line) {
            Ok(m) => m,
            Err(_) => continue,
        };
        let method = message.get("method").and_then(|m| m.as_str());
        let params = message.get("params").unwrap_or(&empty_obj);

        match method {
            Some("initialize") => {
                let versions = params.get("protocolVersions").and_then(|v| v.as_arr());
                let supports_v2 =
                    versions.is_some_and(|arr| arr.iter().any(|v| v.as_str() == Some("2")));
                let id = message.get("id").cloned().unwrap_or(Value::Null);
                if !supports_v2 {
                    let error = Value::Obj(vec![
                        ("code".into(), Value::Int("-32602".into())),
                        (
                            "message".into(),
                            Value::Str("this tool speaks protocol 2 only".into()),
                        ),
                    ]);
                    let _ = send(
                        out,
                        &Value::Obj(vec![
                            ("jsonrpc".into(), Value::Str("2.0".into())),
                            ("id".into(), id),
                            ("error".into(), error),
                        ]),
                    );
                    continue;
                }
                let result = Value::Obj(vec![
                    ("protocolVersion".into(), Value::Str("2".into())),
                    ("toolVersion".into(), Value::Str("0.1.0".into())),
                ]);
                let _ = send(
                    out,
                    &Value::Obj(vec![
                        ("jsonrpc".into(), Value::Str("2.0".into())),
                        ("id".into(), id),
                        ("result".into(), result),
                    ]),
                );
                let _ = send(
                    out,
                    &Value::Obj(vec![
                        ("jsonrpc".into(), Value::Str("2.0".into())),
                        ("method".into(), Value::Str("commands/state".into())),
                        (
                            "params".into(),
                            Value::Obj(vec![(
                                "runnable".into(),
                                Value::Arr(vec![Value::Str("hello".into())]),
                            )]),
                        ),
                    ]),
                );
            }
            Some("command/run") => {
                let cmd = params.get("command").and_then(|c| c.as_str());
                let id = message.get("id").cloned().unwrap_or(Value::Null);
                if cmd != Some("hello") {
                    let error = Value::Obj(vec![
                        ("code".into(), Value::Int("-32602".into())),
                        ("message".into(), Value::Str("no such command".into())),
                    ]);
                    let _ = send(
                        out,
                        &Value::Obj(vec![
                            ("jsonrpc".into(), Value::Str("2.0".into())),
                            ("id".into(), id),
                            ("error".into(), error),
                        ]),
                    );
                    continue;
                }
                asked += 1;
                let asked_val = Value::Int(asked.to_string());
                waiting.push((asked_val.clone(), id));
                let hud = Value::Obj(vec![
                    ("icon".into(), Value::Str("hand.wave".into())),
                    (
                        "message".into(),
                        Value::Str("Hello from reference tool 2".into()),
                    ),
                ]);
                let _ = send(
                    out,
                    &Value::Obj(vec![
                        ("jsonrpc".into(), Value::Str("2.0".into())),
                        ("id".into(), asked_val),
                        ("method".into(), Value::Str("notify/hud".into())),
                        ("params".into(), hud),
                    ]),
                );
            }
            Some("ui/open") => {
                let panel = params.get("panel").and_then(|p| p.as_str());
                let id = message.get("id").cloned().unwrap_or(Value::Null);
                if panel != Some("hello") {
                    let error = Value::Obj(vec![
                        ("code".into(), Value::Int("-32602".into())),
                        ("message".into(), Value::Str("no such panel".into())),
                    ]);
                    let _ = send(
                        out,
                        &Value::Obj(vec![
                            ("jsonrpc".into(), Value::Str("2.0".into())),
                            ("id".into(), id),
                            ("error".into(), error),
                        ]),
                    );
                    continue;
                }
                let result = Value::Obj(vec![("tree".into(), page(presses))]);
                let _ = send(
                    out,
                    &Value::Obj(vec![
                        ("jsonrpc".into(), Value::Str("2.0".into())),
                        ("id".into(), id),
                        ("result".into(), result),
                    ]),
                );
            }
            Some("ui/event") => {
                let id = message.get("id").cloned().unwrap_or(Value::Null);
                let pressed = params.get("panel").and_then(|p| p.as_str()) == Some("hello")
                    && params.get("block").and_then(|b| b.as_str()) == Some("press")
                    && params.get("event").and_then(|e| e.as_str()) == Some("tap");
                let result = if pressed {
                    presses += 1;
                    Value::Obj(vec![("tree".into(), page(presses))])
                } else {
                    Value::Obj(vec![("keep".into(), Value::Bool(true))])
                };
                let _ = send(
                    out,
                    &Value::Obj(vec![
                        ("jsonrpc".into(), Value::Str("2.0".into())),
                        ("id".into(), id),
                        ("result".into(), result),
                    ]),
                );
            }
            Some("ui/close") => {}
            Some("shutdown") => return 0,
            None => {
                if let Some(msg_id) = message.get("id") {
                    if let Some(pos) = waiting.iter().position(|(k, _)| json::py_eq(k, msg_id)) {
                        let (_, run_id) = waiting.remove(pos);
                        if let Some(err_val) = message.get("error") {
                            let error = Value::Obj(vec![
                                ("code".into(), Value::Int("-32010".into())),
                                ("message".into(), Value::Str("command refused".into())),
                                ("data".into(), err_val.clone()),
                            ]);
                            let _ = send(
                                out,
                                &Value::Obj(vec![
                                    ("jsonrpc".into(), Value::Str("2.0".into())),
                                    ("id".into(), run_id),
                                    ("error".into(), error),
                                ]),
                            );
                        } else {
                            let _ = send(
                                out,
                                &Value::Obj(vec![
                                    ("jsonrpc".into(), Value::Str("2.0".into())),
                                    ("id".into(), run_id),
                                    ("result".into(), Value::Obj(Vec::new())),
                                ]),
                            );
                        }
                    }
                }
            }
            Some(_) => {
                if let Some(id) = message.get("id") {
                    let error = Value::Obj(vec![
                        ("code".into(), Value::Int("-32601".into())),
                        ("message".into(), Value::Str("method not found".into())),
                    ]);
                    let _ = send(
                        out,
                        &Value::Obj(vec![
                            ("jsonrpc".into(), Value::Str("2.0".into())),
                            ("id".into(), id.clone()),
                            ("error".into(), error),
                        ]),
                    );
                }
            }
        }
    }
    0
}

pub fn main() -> i32 {
    let stdin = io::stdin();
    let mut stdout = io::stdout();
    run_session(stdin.lock(), &mut stdout)
}
