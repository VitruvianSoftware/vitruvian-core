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

//! Native Rust port of `packages/vitruvian-sdk/conformance/conformance_test.py`.
//!
//! Proves the conformance validator two ways: the reference tools pass it (one
//! for each protocol version), and tools that break the protocol fail the check
//! meant to catch them.

use std::env;
use std::fs;
use std::io::{self, BufRead, Write};
use std::path::Path;
use std::process::{Command, Stdio};
use std::thread;
use std::time::{Duration, Instant};

use conformance_rs_lib::json::{self, Value};
use conformance_rs_lib::pystr;
use conformance_rs_lib::{
    check_to, Failure, Link, Run, TempDir, Transport, EXIT_SECONDS, FEATURES,
};

use crate::find_package_dir;

const SLOWEST_SECONDS: f64 = 15.0;
const REFUSED: &str = ": Vitruvian refuses the whole page";
const CHARS: &str = "ASCII letters, digits, '.', '-' and '_' only";

const BROKEN: &[(&str, &str)] = &[
    (
        "speaks first",
        "NOT OK   handshake: something other than the answer to initialize came first",
    ),
    ("not json", "NOT OK   handshake: a line that is not JSON"),
    (
        "wrong version",
        "NOT OK   handshake: the tool picked a version that was not offered",
    ),
    (
        "never answers",
        "NOT OK   a command: no answer within 2 seconds",
    ),
    (
        "answers another",
        "NOT OK   a command: an answer to a request that was not waiting",
    ),
    (
        "asks badly",
        "NOT OK   a command: notify/hud with params that are not its own",
    ),
    (
        "states badly",
        "NOT OK   a command: commands/state with params that are not its own",
    ),
    (
        "runs anything",
        "NOT OK   unknown: a command the tool does not have was answered as done",
    ),
    ("exits with 3", "NOT OK   shutdown: exited with 3"),
    (
        "will not exit",
        "NOT OK   shutdown: still running 2 seconds after shutdown",
    ),
    (
        "parts badly",
        "NOT OK   shutdown: commands/state with params that are not its own",
    ),
    (
        "parts mid-line",
        "NOT OK   shutdown: a line longer than 1 MB, or one cut short",
    ),
];

const BROKEN_PANEL: &[(&str, &str)] = &[
    (
        "renders an unknown panel",
        "NOT OK   a panel: ui/render for a panel the manifest does not declare: nowhere",
    ),
    (
        "opens with no page",
        "NOT OK   a panel: ui/open was not answered with a page",
    ),
    (
        "answers a tap with the same page",
        "NOT OK   a panel: a tap on add was answered with the same page",
    ),
    (
        "opens an undeclared panel",
        "NOT OK   a panel: a tap's open names elsewhere, a panel the manifest does not declare",
    ),
    (
        "opens its island page",
        "NOT OK   a panel: a tap's open names counter, a panel of the island",
    ),
    (
        "opens its settings without asking",
        "NOT OK   an older app: a tap's open names the settings panel settings, which an app without ui.open.settings does not open",
    ),
    (
        "puts a section in its settings",
        "NOT OK   an older app: the page of settings holds a heading that starts a section, which an app without ui.sections draws as a plain heading: ask supports first",
    ),
];

const OPENS_WELL: &[(&str, &str)] = &[
    (
        "opens a window",
        "ok       a panel: counter: a page of 2 blocks, and the window log after a tap on add",
    ),
    (
        "opens its settings",
        "ok       a panel: counter: a page of 2 blocks, and the settings panel settings after a tap on add",
    ),
];

const BROKEN_STATUS: &[(&str, &str)] = &[
    (
        "names a state there is not",
        "NOT OK   a command: ui/status with params that are not its own",
    ),
    (
        "says it in French alone",
        "NOT OK   a command: ui/status with params that are not its own",
    ),
    (
        "names a glyph that is no name",
        "NOT OK   a command: ui/status with params that are not its own",
    ),
    (
        "counts from before 1970",
        "NOT OK   a command: ui/status with params that are not its own",
    ),
    (
        "says its few words with a number",
        "NOT OK   a command: ui/status with params that are not its own",
    ),
    (
        "draws two options alike",
        "NOT OK   a panel: ui/open was not answered with a page",
    ),
    (
        "draws a choice of nothing",
        "NOT OK   a panel: ui/open was not answered with a page",
    ),
    (
        "draws two chips alike",
        "NOT OK   a panel: ui/open was not answered with a page",
    ),
    (
        "draws chips of nothing",
        "NOT OK   a panel: ui/open was not answered with a page",
    ),
    (
        "draws chips with no id",
        "NOT OK   a panel: ui/open was not answered with a page",
    ),
    (
        "draws chips whose chip is not on or off",
        "NOT OK   a panel: ui/open was not answered with a page",
    ),
    (
        "says help with a number",
        "NOT OK   a panel: ui/open was not answered with a page",
    ),
    (
        "draws chips whatever the app has",
        "NOT OK   an older app: the page of lights holds chips, which an app without ui.chips draws as their fallback text",
    ),
    (
        "starts a section whatever the app has",
        "NOT OK   an older app: the page of lights holds a heading that starts a section, which an app without ui.sections draws as a plain heading: ask supports first",
    ),
    (
        "says help whatever the app has",
        "NOT OK   an older app: the page of lights holds help on a toggle, which an app without ui.sections leaves out: ask supports first, and send a text after the control",
    ),
    (
        "dies when refused",
        "NOT OK   an older app: the tool did not carry on after an app that has no ui/status refused it with -32601",
    ),
    (
        "keeps asking an older app",
        "NOT OK   an older app: the tool went on sending ui/status to an app that answered it with -32601",
    ),
];

const BROKEN_SLOT: &[(&str, &str)] = &[
    (
        "says a notice with a number",
        "NOT OK   a command: notify/notice with params that are not its own",
    ),
    (
        "sends a notice whatever the app has",
        "NOT OK   an older app: notify/notice to an app whose hello does not name notify.notice",
    ),
    (
        "docks whatever the app has",
        "NOT OK   an older app: ui/dock to an app whose hello does not name ui.slot",
    ),
];

fn send_json<W: Write>(out: &mut W, msg: &Value) {
    let mut line = msg.dumps_compact();
    line.push('\n');
    let _ = out.write_all(line.as_bytes());
    let _ = out.flush();
}

fn str_val(s: &str) -> Value {
    Value::Str(s.to_string())
}

fn obj_val(entries: Vec<(&str, Value)>) -> Value {
    Value::Obj(
        entries
            .into_iter()
            .map(|(k, v)| (k.to_string(), v))
            .collect(),
    )
}

fn run_left_behind() -> i32 {
    let line =
        b"{\"jsonrpc\": \"2.0\", \"method\": \"log\", \"params\": {\"message\": \"still here\"}}\n";
    let end = Instant::now() + Duration::from_millis(2500);
    let mut stdout = io::stdout();
    while Instant::now() < end {
        if stdout.write_all(line).is_err() {
            break;
        }
    }
    0
}

fn run_broken_tool() -> i32 {
    let how = env::var("BROKEN_HOW").unwrap_or_default();
    let stdin = io::stdin();
    let mut stdout = io::stdout();

    for line_res in stdin.lock().lines() {
        let Ok(line) = line_res else { break };
        if line.trim().is_empty() {
            continue;
        }
        let Ok(message) = json::loads(&line) else {
            continue;
        };
        let method = message.get("method").and_then(|m| m.as_str());
        match method {
            Some("initialize") => {
                if how == "speaks first" {
                    send_json(
                        &mut stdout,
                        &obj_val(vec![
                            ("jsonrpc", str_val("2.0")),
                            ("method", str_val("log")),
                            ("params", obj_val(vec![("message", str_val("starting"))])),
                        ]),
                    );
                }
                if how == "not json" {
                    let _ = stdout.write_all(b"starting up\n");
                    let _ = stdout.flush();
                }
                let version = if how == "wrong version" { "3" } else { "1" };
                let id = message.get("id").cloned().unwrap_or(Value::Null);
                send_json(
                    &mut stdout,
                    &obj_val(vec![
                        ("jsonrpc", str_val("2.0")),
                        ("id", id),
                        (
                            "result",
                            obj_val(vec![
                                ("protocolVersion", str_val(version)),
                                ("toolVersion", str_val("0")),
                            ]),
                        ),
                    ]),
                );
                if how == "states badly" {
                    send_json(
                        &mut stdout,
                        &obj_val(vec![
                            ("jsonrpc", str_val("2.0")),
                            ("method", str_val("commands/state")),
                            ("params", obj_val(vec![("runnable", str_val("hello"))])),
                        ]),
                    );
                }
            }
            Some("command/run") => {
                if how == "never answers" {
                    continue;
                }
                let known = message
                    .get("params")
                    .and_then(|p| p.get("command"))
                    .and_then(|c| c.as_str())
                    == Some("hello");
                if how == "asks badly" {
                    send_json(
                        &mut stdout,
                        &obj_val(vec![
                            ("jsonrpc", str_val("2.0")),
                            ("id", str_val("a")),
                            ("method", str_val("notify/hud")),
                            (
                                "params",
                                obj_val(vec![
                                    ("icon", str_val("hand.wave")),
                                    ("message", Value::Int("5".into())),
                                ]),
                            ),
                        ]),
                    );
                }
                let id = message.get("id").cloned().unwrap_or(Value::Null);
                if how == "answers another" {
                    let bumped_id = match &id {
                        Value::Int(s) => {
                            Value::Int((s.parse::<i64>().unwrap_or(0) + 100).to_string())
                        }
                        _ => Value::Int("100".into()),
                    };
                    send_json(
                        &mut stdout,
                        &obj_val(vec![
                            ("jsonrpc", str_val("2.0")),
                            ("id", bumped_id),
                            ("result", obj_val(vec![])),
                        ]),
                    );
                    continue;
                }
                if known || how == "runs anything" {
                    send_json(
                        &mut stdout,
                        &obj_val(vec![
                            ("jsonrpc", str_val("2.0")),
                            ("id", id),
                            ("result", obj_val(vec![])),
                        ]),
                    );
                } else {
                    send_json(
                        &mut stdout,
                        &obj_val(vec![
                            ("jsonrpc", str_val("2.0")),
                            ("id", id),
                            (
                                "error",
                                obj_val(vec![
                                    ("code", Value::Int("-32602".into())),
                                    ("message", str_val("no such command")),
                                ]),
                            ),
                        ]),
                    );
                }
            }
            Some("shutdown") if how == "exits with 3" => return 3,
            Some("shutdown") if how == "parts badly" => {
                send_json(
                    &mut stdout,
                    &obj_val(vec![
                        ("jsonrpc", str_val("2.0")),
                        ("method", str_val("commands/state")),
                        ("params", obj_val(vec![("runnable", str_val("hello"))])),
                    ]),
                );
                return 0;
            }
            Some("shutdown") if how == "parts well" => {
                send_json(
                    &mut stdout,
                    &obj_val(vec![
                        ("jsonrpc", str_val("2.0")),
                        ("method", str_val("log")),
                        ("params", obj_val(vec![("message", str_val("going"))])),
                    ]),
                );
                return 0;
            }
            Some("shutdown") if how == "parts mid-line" => {
                let _ = stdout.write_all(b"{\"jsonrpc\": \"2.0\", \"method\": \"log\"");
                let _ = stdout.flush();
                return 0;
            }
            Some("shutdown") if how == "never stops writing" => {
                if let Ok(exe) = env::current_exe() {
                    if let Ok(child) = Command::new(exe)
                        .arg("--left-behind")
                        .stdin(Stdio::null())
                        .spawn()
                    {
                        if let Ok(pidfile) = env::var("BROKEN_PIDFILE") {
                            let _ = fs::write(pidfile, child.id().to_string());
                        }
                    }
                }
                return 0;
            }
            _ => {}
        }
    }
    if how == "will not exit" {
        thread::sleep(Duration::from_secs(30));
    }
    0
}

fn broken_panel_page(how: &str, count: i64) -> Value {
    let mut blocks = vec![
        obj_val(vec![
            ("type", str_val("text")),
            ("text", str_val(&format!("Pressed {count} times"))),
        ]),
        obj_val(vec![
            ("type", str_val("button")),
            ("id", str_val("add")),
            ("title", str_val("Add one")),
        ]),
    ];
    let named = env::var("BROKEN_ID").ok();
    let named_val = match named {
        Some(s) => Value::Str(s),
        None => Value::Null,
    };
    if how == "names a block" {
        blocks.push(obj_val(vec![
            ("type", str_val("toggle")),
            ("id", named_val),
            ("title", str_val("Hook")),
            ("value", Value::Bool(false)),
        ]));
    } else if how == "names a plain row" {
        blocks.push(obj_val(vec![
            ("type", str_val("row")),
            ("id", named_val),
            ("title", str_val("web")),
        ]));
    } else if how == "names a row of a list" {
        blocks.push(obj_val(vec![
            ("type", str_val("list")),
            ("id", str_val("hooks")),
            (
                "rows",
                Value::Arr(vec![obj_val(vec![
                    ("id", named_val),
                    ("title", str_val("Claude Code")),
                ])]),
            ),
        ]));
    } else if how == "leaves a row of a list unnamed" {
        blocks.push(obj_val(vec![
            ("type", str_val("list")),
            ("id", str_val("hooks")),
            (
                "rows",
                Value::Arr(vec![obj_val(vec![("title", str_val("Claude Code"))])]),
            ),
        ]));
    }
    obj_val(vec![("blocks", Value::Arr(blocks))])
}

fn run_broken_panel_tool() -> i32 {
    let how = env::var("BROKEN_HOW").unwrap_or_default();
    let mut count: i64 = 0;
    let mut features: Vec<String> = Vec::new();
    let stdin = io::stdin();
    let mut stdout = io::stdout();

    for line_res in stdin.lock().lines() {
        let Ok(line) = line_res else { break };
        if line.trim().is_empty() {
            continue;
        }
        let Ok(message) = json::loads(&line) else {
            continue;
        };
        let method = message.get("method").and_then(|m| m.as_str());
        let id = message.get("id").cloned().unwrap_or(Value::Null);
        match method {
            Some("initialize") => {
                features = message
                    .get("params")
                    .and_then(|p| p.get("features"))
                    .and_then(|f| f.as_arr())
                    .map(|arr| {
                        arr.iter()
                            .filter_map(|v| v.as_str().map(String::from))
                            .collect()
                    })
                    .unwrap_or_default();
                send_json(
                    &mut stdout,
                    &obj_val(vec![
                        ("jsonrpc", str_val("2.0")),
                        ("id", id),
                        (
                            "result",
                            obj_val(vec![
                                ("protocolVersion", str_val("2")),
                                ("toolVersion", str_val("0")),
                            ]),
                        ),
                    ]),
                );
            }
            Some("command/run") => {
                if message
                    .get("params")
                    .and_then(|p| p.get("command"))
                    .and_then(|c| c.as_str())
                    == Some("hello")
                {
                    send_json(
                        &mut stdout,
                        &obj_val(vec![
                            ("jsonrpc", str_val("2.0")),
                            ("id", id),
                            ("result", obj_val(vec![])),
                        ]),
                    );
                } else {
                    send_json(
                        &mut stdout,
                        &obj_val(vec![
                            ("jsonrpc", str_val("2.0")),
                            ("id", id),
                            (
                                "error",
                                obj_val(vec![
                                    ("code", Value::Int("-32602".into())),
                                    ("message", str_val("no such command")),
                                ]),
                            ),
                        ]),
                    );
                }
            }
            Some("ui/open") => {
                let panel = message
                    .get("params")
                    .and_then(|p| p.get("panel"))
                    .and_then(|p| p.as_str());
                if how == "puts a section in its settings" && panel == Some("settings") {
                    let heading = obj_val(vec![
                        ("type", str_val("heading")),
                        ("text", str_val("Counting")),
                        ("section", Value::Bool(true)),
                    ]);
                    send_json(
                        &mut stdout,
                        &obj_val(vec![
                            ("jsonrpc", str_val("2.0")),
                            ("id", id),
                            (
                                "result",
                                obj_val(vec![(
                                    "tree",
                                    obj_val(vec![("blocks", Value::Arr(vec![heading]))]),
                                )]),
                            ),
                        ]),
                    );
                    continue;
                }
                if how == "renders an unknown panel" {
                    send_json(
                        &mut stdout,
                        &obj_val(vec![
                            ("jsonrpc", str_val("2.0")),
                            ("method", str_val("ui/render")),
                            (
                                "params",
                                obj_val(vec![
                                    ("panel", str_val("nowhere")),
                                    ("tree", broken_panel_page(&how, count)),
                                ]),
                            ),
                        ]),
                    );
                }
                if how == "opens with no page" {
                    send_json(
                        &mut stdout,
                        &obj_val(vec![
                            ("jsonrpc", str_val("2.0")),
                            ("id", id),
                            ("result", obj_val(vec![])),
                        ]),
                    );
                } else {
                    send_json(
                        &mut stdout,
                        &obj_val(vec![
                            ("jsonrpc", str_val("2.0")),
                            ("id", id),
                            (
                                "result",
                                obj_val(vec![("tree", broken_panel_page(&how, count))]),
                            ),
                        ]),
                    );
                }
            }
            Some("ui/event") => {
                let mut opens = match how.as_str() {
                    "opens its settings" | "opens its settings without asking" => Some("settings"),
                    "opens a window" => Some("log"),
                    "opens an undeclared panel" => Some("elsewhere"),
                    "opens its island page" => Some("counter"),
                    _ => None,
                };
                if how == "opens its settings" && !features.iter().any(|f| f == "ui.open.settings")
                {
                    opens = None;
                }
                if let Some(target) = opens {
                    send_json(
                        &mut stdout,
                        &obj_val(vec![
                            ("jsonrpc", str_val("2.0")),
                            ("id", id),
                            ("result", obj_val(vec![("open", str_val(target))])),
                        ]),
                    );
                    continue;
                }
                if how != "answers a tap with the same page" {
                    count += 1;
                }
                send_json(
                    &mut stdout,
                    &obj_val(vec![
                        ("jsonrpc", str_val("2.0")),
                        ("id", id),
                        (
                            "result",
                            obj_val(vec![("tree", broken_panel_page(&how, count))]),
                        ),
                    ]),
                );
            }
            Some("shutdown") => return 0,
            _ => {}
        }
    }
    0
}

fn status_tool_page(how: &str, asked: i64, features: &[String]) -> Value {
    let has_feature = |name: &str| features.iter().any(|f| f == name);
    let mut options = vec![
        obj_val(vec![
            ("value", str_val("green")),
            ("title", str_val("Green")),
        ]),
        obj_val(vec![
            ("value", str_val("breathe green")),
            (
                "title",
                obj_val(vec![
                    ("en", str_val("Pulsing green")),
                    ("de", str_val("Pulsierendes Gr\u{00fc}n")),
                ]),
            ),
        ]),
    ];
    if how == "draws two options alike" {
        options.push(obj_val(vec![
            ("value", str_val("green")),
            ("title", str_val("Green again")),
        ]));
    }
    if how == "draws a choice of nothing" {
        options.clear();
    }
    let pick = if has_feature("ui.choice") || how.starts_with("draws") {
        obj_val(vec![
            ("type", str_val("choice")),
            ("id", str_val("light")),
            ("title", str_val("Light")),
            ("value", str_val("green")),
            ("options", Value::Arr(options)),
            ("fallback", str_val("Light: Green")),
        ])
    } else {
        obj_val(vec![
            ("type", str_val("field")),
            ("id", str_val("light")),
            ("title", str_val("Light")),
            ("value", str_val("green")),
        ])
    };
    let mut blocks = vec![
        obj_val(vec![
            ("type", str_val("text")),
            ("text", str_val(&format!("Pressed {asked} times"))),
        ]),
        pick,
    ];
    let mut chips = vec![
        obj_val(vec![
            ("value", str_val("whatsapp")),
            ("title", str_val("WhatsApp")),
            ("on", Value::Bool(true)),
        ]),
        obj_val(vec![
            ("value", str_val("signal")),
            (
                "title",
                obj_val(vec![("en", str_val("Signal")), ("de", str_val("Signal"))]),
            ),
            ("on", Value::Bool(false)),
        ]),
    ];
    if how == "draws two chips alike" {
        chips.push(obj_val(vec![
            ("value", str_val("whatsapp")),
            ("title", str_val("WhatsApp again")),
            ("on", Value::Bool(false)),
        ]));
    }
    if how == "draws chips of nothing" {
        chips.clear();
    }
    if how == "draws chips whose chip is not on or off" {
        chips[0] = obj_val(vec![
            ("value", str_val("whatsapp")),
            ("title", str_val("WhatsApp")),
        ]);
    }
    if how == "draws chips well" && !has_feature("ui.chips") {
        for c in &chips {
            blocks.push(obj_val(vec![
                ("type", str_val("toggle")),
                ("id", c.get("value").cloned().unwrap_or(Value::Null)),
                ("title", c.get("title").cloned().unwrap_or(Value::Null)),
                ("value", c.get("on").cloned().unwrap_or(Value::Null)),
            ]));
        }
    } else if how.contains("chips") {
        let mut drawn_entries = vec![
            ("type", str_val("chips")),
            ("title", str_val("Networks")),
            ("options", Value::Arr(chips)),
            ("fallback", str_val("Networks: WhatsApp")),
        ];
        if how != "draws chips with no id" {
            drawn_entries.push(("id", str_val("networks")));
        }
        blocks.push(obj_val(drawn_entries));
    }
    let well = how == "sections and help well" && has_feature("ui.sections");
    if how == "starts a section whatever the app has" || well {
        blocks.insert(
            0,
            obj_val(vec![
                ("type", str_val("heading")),
                ("text", str_val("Lights")),
                ("section", Value::Bool(true)),
            ]),
        );
    }
    if how == "says help whatever the app has" || well {
        blocks.push(obj_val(vec![
            ("type", str_val("toggle")),
            ("id", str_val("pause")),
            ("title", str_val("Pause")),
            ("value", Value::Bool(false)),
            ("help", str_val("Pauses what is playing.")),
        ]));
    }
    if how == "says section: false to an older app" {
        blocks.insert(
            0,
            obj_val(vec![
                ("type", str_val("heading")),
                ("text", str_val("Lights")),
                ("section", Value::Bool(has_feature("ui.sections"))),
            ]),
        );
    }
    if how == "says help with a number" {
        blocks.push(obj_val(vec![
            ("type", str_val("toggle")),
            ("id", str_val("pause")),
            ("title", str_val("Pause")),
            ("value", Value::Bool(false)),
            ("help", Value::Int("5".into())),
        ]));
    }
    if how == "sections and help well" && !well {
        blocks.push(obj_val(vec![
            ("type", str_val("heading")),
            ("text", str_val("Lights")),
        ]));
        blocks.push(obj_val(vec![
            ("type", str_val("toggle")),
            ("id", str_val("pause")),
            ("title", str_val("Pause")),
            ("value", Value::Bool(false)),
        ]));
        blocks.push(obj_val(vec![
            ("type", str_val("text")),
            ("text", str_val("Pauses what is playing.")),
            ("style", str_val("caption")),
        ]));
    }
    obj_val(vec![("blocks", Value::Arr(blocks))])
}

fn send_status<W: Write>(out: &mut W, asked: &mut i64, state: &str, more: Vec<(&str, Value)>) {
    *asked += 1;
    let mut params = more;
    params.push(("state", str_val(state)));
    send_json(
        out,
        &obj_val(vec![
            ("jsonrpc", str_val("2.0")),
            ("id", str_val(&format!("s{}", *asked))),
            ("method", str_val("ui/status")),
            ("params", obj_val(params)),
        ]),
    );
}

fn run_status_tool() -> i32 {
    let how = env::var("BROKEN_HOW").unwrap_or_default();
    let mut features: Vec<String> = Vec::new();
    let mut asked: i64 = 0;
    let stdin = io::stdin();
    let mut stdout = io::stdout();

    for line_res in stdin.lock().lines() {
        let Ok(line) = line_res else { break };
        if line.trim().is_empty() {
            continue;
        }
        let Ok(message) = json::loads(&line) else {
            continue;
        };
        let method = message.get("method").and_then(|m| m.as_str());
        let id = message.get("id").cloned().unwrap_or(Value::Null);
        match method {
            Some("initialize") => {
                features = message
                    .get("params")
                    .and_then(|p| p.get("features"))
                    .and_then(|f| f.as_arr())
                    .map(|arr| {
                        arr.iter()
                            .filter_map(|v| v.as_str().map(String::from))
                            .collect()
                    })
                    .unwrap_or_default();
                send_json(
                    &mut stdout,
                    &obj_val(vec![
                        ("jsonrpc", str_val("2.0")),
                        ("id", id),
                        (
                            "result",
                            obj_val(vec![
                                ("protocolVersion", str_val("2")),
                                ("toolVersion", str_val("0")),
                            ]),
                        ),
                    ]),
                );
            }
            Some("command/run") => {
                if message
                    .get("params")
                    .and_then(|p| p.get("command"))
                    .and_then(|c| c.as_str())
                    != Some("hello")
                {
                    send_json(
                        &mut stdout,
                        &obj_val(vec![
                            ("jsonrpc", str_val("2.0")),
                            ("id", id),
                            (
                                "error",
                                obj_val(vec![
                                    ("code", Value::Int("-32602".into())),
                                    ("message", str_val("no such command")),
                                ]),
                            ),
                        ]),
                    );
                    continue;
                }
                let has_feature = |name: &str| features.iter().any(|f| f == name);
                if how == "names a state there is not" {
                    send_status(&mut stdout, &mut asked, "broken", vec![]);
                } else if how == "says it in French alone" {
                    send_status(
                        &mut stdout,
                        &mut asked,
                        "failure",
                        vec![("text", obj_val(vec![("fr", str_val("main est rouge"))]))],
                    );
                } else if how == "names a glyph that is no name" {
                    send_status(
                        &mut stdout,
                        &mut asked,
                        "busy",
                        vec![("icon", Value::Int("7".into()))],
                    );
                } else if how == "counts from before 1970" {
                    send_status(
                        &mut stdout,
                        &mut asked,
                        "busy",
                        vec![("since", Value::Int("-1".into()))],
                    );
                } else if how == "says its few words with a number" {
                    send_status(
                        &mut stdout,
                        &mut asked,
                        "busy",
                        vec![("activity", Value::Int("3".into()))],
                    );
                } else if how == "says a few words" && has_feature("ui.status.activity") {
                    send_status(
                        &mut stdout,
                        &mut asked,
                        "busy",
                        vec![
                            ("text", str_val("Checks are running")),
                            ("activity", str_val("3")),
                        ],
                    );
                    send_status(
                        &mut stdout,
                        &mut asked,
                        "busy",
                        vec![("since", Value::Float(1760450400.5))],
                    );
                } else if has_feature("ui.status") {
                    send_status(
                        &mut stdout,
                        &mut asked,
                        "busy",
                        vec![
                            ("icon", str_val("arrow.triangle.branch")),
                            (
                                "text",
                                obj_val(vec![
                                    ("en", str_val("Working")),
                                    ("fr", str_val("En cours")),
                                ]),
                            ),
                        ],
                    );
                    send_status(&mut stdout, &mut asked, "none", vec![]);
                } else if how == "asks an older app" || how == "dies when refused" {
                    send_status(&mut stdout, &mut asked, "busy", vec![]);
                } else if how == "keeps asking an older app" {
                    for _ in 0..8 {
                        send_status(&mut stdout, &mut asked, "busy", vec![]);
                    }
                }
                send_json(
                    &mut stdout,
                    &obj_val(vec![
                        ("jsonrpc", str_val("2.0")),
                        ("id", id),
                        ("result", obj_val(vec![])),
                    ]),
                );
            }
            Some("ui/open") => {
                send_json(
                    &mut stdout,
                    &obj_val(vec![
                        ("jsonrpc", str_val("2.0")),
                        ("id", id),
                        (
                            "result",
                            obj_val(vec![("tree", status_tool_page(&how, asked, &features))]),
                        ),
                    ]),
                );
            }
            Some("ui/event") => {
                send_json(
                    &mut stdout,
                    &obj_val(vec![
                        ("jsonrpc", str_val("2.0")),
                        ("id", id),
                        ("result", obj_val(vec![("keep", Value::Bool(true))])),
                    ]),
                );
            }
            Some("shutdown") => return 0,
            None => {
                if matches!(
                    message.get("error").and_then(|e| e.get("code")),
                    Some(Value::Int(s)) if s == "-32601"
                ) && how == "dies when refused"
                {
                    return 1;
                }
            }
            _ => {}
        }
    }
    0
}

fn run_slot_tool() -> i32 {
    let how = env::var("BROKEN_HOW").unwrap_or_default();
    let mut features: Vec<String> = Vec::new();
    let stdin = io::stdin();
    let mut stdout = io::stdout();

    for line_res in stdin.lock().lines() {
        let Ok(line) = line_res else { break };
        if line.trim().is_empty() {
            continue;
        }
        let Ok(message) = json::loads(&line) else {
            continue;
        };
        let method = message.get("method").and_then(|m| m.as_str());
        let id = message.get("id").cloned().unwrap_or(Value::Null);
        match method {
            Some("initialize") => {
                features = message
                    .get("params")
                    .and_then(|p| p.get("features"))
                    .and_then(|f| f.as_arr())
                    .map(|arr| {
                        arr.iter()
                            .filter_map(|v| v.as_str().map(String::from))
                            .collect()
                    })
                    .unwrap_or_default();
                send_json(
                    &mut stdout,
                    &obj_val(vec![
                        ("jsonrpc", str_val("2.0")),
                        ("id", id),
                        (
                            "result",
                            obj_val(vec![
                                ("protocolVersion", str_val("2")),
                                ("toolVersion", str_val("0")),
                            ]),
                        ),
                    ]),
                );
            }
            Some("ui/slot") => {}
            Some("command/run") => {
                if message
                    .get("params")
                    .and_then(|p| p.get("command"))
                    .and_then(|c| c.as_str())
                    != Some("hello")
                {
                    send_json(
                        &mut stdout,
                        &obj_val(vec![
                            ("jsonrpc", str_val("2.0")),
                            ("id", id),
                            (
                                "error",
                                obj_val(vec![
                                    ("code", Value::Int("-32602".into())),
                                    ("message", str_val("no such command")),
                                ]),
                            ),
                        ]),
                    );
                    continue;
                }
                let has_feature = |name: &str| features.iter().any(|f| f == name);
                if has_feature("notify.notice") || how == "sends a notice whatever the app has" {
                    let title_val = if how == "says a notice with a number" {
                        Value::Int("5".into())
                    } else {
                        str_val("Done")
                    };
                    send_json(
                        &mut stdout,
                        &obj_val(vec![
                            ("jsonrpc", str_val("2.0")),
                            ("id", str_val("n")),
                            ("method", str_val("notify/notice")),
                            (
                                "params",
                                obj_val(vec![
                                    ("icon", str_val("bell")),
                                    ("title", title_val),
                                    ("detail", str_val("the tests pass")),
                                    ("system", Value::Bool(true)),
                                ]),
                            ),
                        ]),
                    );
                } else {
                    send_json(
                        &mut stdout,
                        &obj_val(vec![
                            ("jsonrpc", str_val("2.0")),
                            ("id", str_val("n")),
                            ("method", str_val("notify/hud")),
                            (
                                "params",
                                obj_val(vec![
                                    ("icon", str_val("bell")),
                                    ("message", str_val("Done")),
                                ]),
                            ),
                        ]),
                    );
                }
                if has_feature("ui.slot") || how == "docks whatever the app has" {
                    send_json(
                        &mut stdout,
                        &obj_val(vec![
                            ("jsonrpc", str_val("2.0")),
                            ("id", str_val("d")),
                            ("method", str_val("ui/dock")),
                        ]),
                    );
                }
                send_json(
                    &mut stdout,
                    &obj_val(vec![
                        ("jsonrpc", str_val("2.0")),
                        ("id", id),
                        ("result", obj_val(vec![])),
                    ]),
                );
            }
            Some("shutdown") => return 0,
            _ => {}
        }
    }
    0
}

/// Checks if the current process was spawned as one of the mock tools (`--via <current_exe>`).
pub fn maybe_run_mock_tool(args: &[String]) -> Option<i32> {
    let first = args.first()?.as_str();
    if first == "--left-behind" {
        return Some(run_left_behind());
    }
    if first.ends_with("reference_tool.py") {
        return Some(crate::reference_tool::main());
    }
    if first.ends_with("reference_tool_2.py") {
        return Some(crate::reference_tool_2::main());
    }
    if first.ends_with("broken.py") {
        return Some(run_broken_tool());
    }
    if first.ends_with("panel.py") {
        return Some(run_broken_panel_tool());
    }
    if first.ends_with("status.py") {
        return Some(run_status_tool());
    }
    if first.ends_with("slot.py") {
        return Some(run_slot_tool());
    }
    None
}

fn check(folder: &Path, via: &str, expect_refusal: bool) -> (i32, String) {
    let mut buf = Vec::new();
    let status = check_to(folder, Some(via), expect_refusal, &mut buf).unwrap_or(1);
    let printed = String::from_utf8_lossy(&buf).into_owned();
    (status, printed)
}

fn end_left_behind(pid_file: &Path) {
    let Ok(text) = fs::read_to_string(pid_file) else {
        return;
    };
    let _ = fs::remove_file(pid_file);
    if let Ok(pid) = text.trim().parse::<u32>() {
        let _ = Command::new("kill")
            .args(["-9", &pid.to_string()])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status();
    }
}

fn never_stops_writing(folder: &Path, via: &str) -> Vec<String> {
    let pid_file = folder.join("left-behind.pid");
    env::set_var("BROKEN_HOW", "never stops writing");
    env::set_var("BROKEN_PIDFILE", &pid_file);
    let started = Instant::now();
    let (status, printed) = check(folder, via, false);
    end_left_behind(&pid_file);
    let took = started.elapsed().as_secs_f64();

    let find_line = |name: &str| -> String {
        printed
            .lines()
            .find(|line| line.len() >= 9 && line[9..].starts_with(name))
            .unwrap_or("")
            .to_string()
    };
    let shutdown_line = find_line("shutdown");
    let older_app_line = find_line("an older app");
    let writing = format!("still writing {EXIT_SECONDS} seconds after it exited");
    let caught = status == 1 && shutdown_line == format!("NOT OK   shutdown: {writing}");
    let counted = shutdown_line.starts_with("ok       shutdown: exited with 0, after ")
        && ((status == 0 && older_app_line.starts_with("ok       an older app: "))
            || (status == 1 && older_app_line == format!("NOT OK   an older app: {writing}")));

    let mut problems = Vec::new();
    if !(caught || counted) {
        problems.push(format!("a tool that never stops writing:\n{printed}"));
    }
    if took > SLOWEST_SECONDS {
        problems.push(format!(
            "a tool that never stops writing held the script {took:.1} seconds"
        ));
    }
    problems
}

fn set_obj_field(obj: &mut Value, key: &str, val: Value) {
    if let Value::Obj(entries) = obj {
        if let Some((_, existing)) = entries.iter_mut().find(|(k, _)| k == key) {
            *existing = val;
        } else {
            entries.push((key.to_string(), val));
        }
    }
}

fn remove_obj_field(obj: &mut Value, key: &str) {
    if let Value::Obj(entries) = obj {
        entries.retain(|(k, _)| k != key);
    }
}

fn panels(base_manifest: &Value, via: &str) -> Vec<String> {
    let mut problems = Vec::new();
    let mut manifest = base_manifest.clone();
    set_obj_field(&mut manifest, "protocol", str_val("2"));
    set_obj_field(
        &mut manifest,
        "runtime",
        obj_val(vec![
            ("kind", str_val("external")),
            ("exec", str_val("panel.py")),
        ]),
    );
    let mut contributes = manifest
        .get("contributes")
        .cloned()
        .unwrap_or_else(|| obj_val(vec![]));
    set_obj_field(
        &mut contributes,
        "panels",
        Value::Arr(vec![
            obj_val(vec![
                ("id", str_val("counter")),
                ("title", obj_val(vec![("en", str_val("Counter"))])),
                ("placement", str_val("island")),
            ]),
            obj_val(vec![
                ("id", str_val("settings")),
                ("title", obj_val(vec![("en", str_val("Counter"))])),
                ("placement", str_val("settings")),
            ]),
            obj_val(vec![
                ("id", str_val("log")),
                ("title", obj_val(vec![("en", str_val("Log"))])),
                ("placement", str_val("window")),
            ]),
        ]),
    );
    set_obj_field(&mut manifest, "contributes", contributes);

    let Ok(temp) = TempDir::new("conformance-panels-") else {
        return vec!["could not create temp dir for panels".into()];
    };
    let folder = temp.path();
    let _ = fs::write(folder.join("vitruvian-tool.json"), manifest.dumps_compact());
    let _ = fs::write(folder.join("panel.py"), "# mock panel tool\n");

    env::set_var("BROKEN_HOW", "draws well");
    let (status, printed) = check(folder, via, false);
    let wanted = "ok       a panel: counter: a page of 2 blocks, and a new page after a tap on add; settings: a page of 2 blocks; log: a page of 2 blocks";
    if status != 0
        || !printed.contains(wanted)
        || !printed.contains("ok       handshake: version 2")
    {
        problems.push(format!("a tool that draws well does not pass:\n{printed}"));
    }

    for (how, line) in OPENS_WELL {
        env::set_var("BROKEN_HOW", how);
        let (status, printed) = check(folder, via, false);
        if status != 0 || !printed.contains(line) {
            problems.push(format!("a tool that {how} does not pass:\n{printed}"));
        }
    }

    for (how, line) in BROKEN_PANEL {
        env::set_var("BROKEN_HOW", how);
        let (status, printed) = check(folder, via, false);
        let failed: Vec<&str> = printed
            .lines()
            .filter(|t| t.starts_with("NOT OK"))
            .collect();
        if status != 1 || failed.len() != 1 || !failed[0].starts_with(line) {
            problems.push(format!("a tool that {how} is not caught:\n{printed}"));
        }
    }

    let mut ill_named: Vec<(&str, Option<String>, String)> = Vec::new();
    let bad_names: Vec<(String, &str)> = vec![
        ("installHook:claudeCode".into(), CHARS),
        ("caf\u{00e9}".into(), CHARS),
        ("the latest".into(), CHARS),
        ("a".repeat(129), "at most 128 characters"),
        ("hooks..claude".into(), "no two '.' together"),
        (".hooks".into(), "no '.' at either end"),
        ("hooks.".into(), "no '.' at either end"),
        ("".into(), "at least one character"),
    ];
    for (how, what, where_in) in [
        ("names a block", "block id", ""),
        ("names a plain row", "block id", ""),
        ("names a row of a list", "list row id", " in list 'hooks'"),
    ] {
        for (named, rule) in &bad_names {
            let line = format!(
                "NOT OK   a panel: the page of counter has {what} {}{where_in}, which is not a valid name ({rule}){REFUSED}",
                pystr::repr_str(named)
            );
            ill_named.push((how, Some(named.clone()), line));
        }
    }
    ill_named.push((
        "leaves a row of a list unnamed",
        None,
        format!(
            "NOT OK   a panel: the page of counter has a row in list 'hooks' whose id is missing or not text{REFUSED}"
        ),
    ));

    for (how, named, line) in &ill_named {
        env::set_var("BROKEN_HOW", how);
        env::set_var("BROKEN_ID", named.as_deref().unwrap_or(""));
        let (status, printed) = check(folder, via, false);
        let failed: Vec<&str> = printed
            .lines()
            .filter(|t| t.starts_with("NOT OK"))
            .collect();
        if status != 1 || failed != [line.as_str()] {
            let repr_named = match named {
                Some(s) => pystr::repr_str(s),
                None => "None".into(),
            };
            problems.push(format!(
                "a tool that {how} {repr_named} is not caught as\n{line}\nbut:\n{printed}"
            ));
        }
    }

    let well_names = [
        "a".repeat(128),
        "install-hook.claude_code".into(),
        "x".into(),
        "0.1-b_2".into(),
    ];
    for how in [
        "names a block",
        "names a plain row",
        "names a row of a list",
    ] {
        for named in &well_names {
            env::set_var("BROKEN_HOW", how);
            env::set_var("BROKEN_ID", named);
            let (status, printed) = check(folder, via, false);
            if status != 0 || !printed.contains("ok       a panel: counter: a page of 3 blocks") {
                problems.push(format!(
                    "a tool that {how} {} does not pass:\n{printed}",
                    pystr::repr_str(named)
                ));
            }
        }
    }
    env::remove_var("BROKEN_ID");
    problems
}

fn statuses(base_manifest: &Value, via: &str) -> Vec<String> {
    let mut problems = Vec::new();
    let mut manifest = base_manifest.clone();
    set_obj_field(&mut manifest, "protocol", str_val("2"));
    set_obj_field(&mut manifest, "uses", Value::Arr(vec![]));
    set_obj_field(
        &mut manifest,
        "runtime",
        obj_val(vec![
            ("kind", str_val("external")),
            ("exec", str_val("status.py")),
        ]),
    );
    let mut contributes = manifest
        .get("contributes")
        .cloned()
        .unwrap_or_else(|| obj_val(vec![]));
    set_obj_field(
        &mut contributes,
        "panels",
        Value::Arr(vec![obj_val(vec![
            ("id", str_val("lights")),
            ("title", obj_val(vec![("en", str_val("Lights"))])),
            ("placement", str_val("island")),
        ])]),
    );
    set_obj_field(
        &mut contributes,
        "status",
        obj_val(vec![("placement", str_val("island"))]),
    );
    set_obj_field(&mut manifest, "contributes", contributes);

    let Ok(temp) = TempDir::new("conformance-statuses-") else {
        return vec!["could not create temp dir for statuses".into()];
    };
    let folder = temp.path();
    let write_manifest = |declared: &Value| {
        let _ = fs::write(folder.join("vitruvian-tool.json"), declared.dumps_compact());
    };
    write_manifest(&manifest);
    let _ = fs::write(folder.join("status.py"), "# mock status tool\n");

    env::set_var("BROKEN_HOW", "shows a status well");
    let (status, printed) = check(folder, via, false);
    let wanted = [
        "ok       a command: hello: ran, and set the status: busy, none",
        "ok       a panel: lights: a page of 2 blocks",
        "ok       refusals: 2 refused",
        "ok       an older app: answered the hello, ran hello, drew lights and left with 0; it sent no ui/status",
    ];
    if status != 0 || !wanted.iter().all(|piece| printed.contains(piece)) {
        problems.push(format!(
            "a tool that shows a status well does not pass:\n{printed}"
        ));
    }

    env::set_var("BROKEN_HOW", "asks an older app");
    let (status, printed) = check(folder, via, false);
    let wanted = "ok       an older app: answered the hello, ran hello, drew lights and left with 0; 1 ui/status refused with -32601, as an app before 3.48 does";
    if status != 0 || !printed.contains(wanted) {
        problems.push(format!(
            "a tool that an older app refuses, and that carries on, does not pass:\n{printed}"
        ));
    }

    env::set_var("BROKEN_HOW", "draws a choice whatever the app has");
    let (status, printed) = check(folder, via, false);
    let wanted = "its page holds a choice, which that app draws as its fallback text";
    if status != 0 || !printed.contains(wanted) {
        problems.push(format!(
            "a tool that sends an older app a choice is not told so:\n{printed}"
        ));
    }

    for how in [
        "draws chips well",
        "sections and help well",
        "says section: false to an older app",
    ] {
        env::set_var("BROKEN_HOW", how);
        let (status, printed) = check(folder, via, false);
        let wanted = [
            "ok       a panel: lights: a page of",
            "ok       an older app: answered the hello, ran hello, drew lights and left with 0",
        ];
        if status != 0 || !wanted.iter().all(|piece| printed.contains(piece)) {
            problems.push(format!(
                "a tool that {how}, asking what the app has, does not pass:\n{printed}"
            ));
        }
    }

    for (how, line) in BROKEN_STATUS {
        env::set_var("BROKEN_HOW", how);
        let started = Instant::now();
        let (status, printed) = check(folder, via, false);
        let took = started.elapsed().as_secs_f64();
        let failed: Vec<&str> = printed
            .lines()
            .filter(|t| t.starts_with("NOT OK"))
            .collect();
        if status != 1 || failed.len() != 1 || !failed[0].starts_with(line) {
            problems.push(format!("a tool that {how} is not caught:\n{printed}"));
        }
        if took > SLOWEST_SECONDS {
            problems.push(format!(
                "a tool that {how} held the script {took:.1} seconds"
            ));
        }
    }

    let mut undeclared = manifest.clone();
    if let Some(mut c) = undeclared.get("contributes").cloned() {
        remove_obj_field(&mut c, "status");
        set_obj_field(&mut undeclared, "contributes", c);
    }
    write_manifest(&undeclared);
    env::set_var("BROKEN_HOW", "shows a status well");
    let (status, printed) = check(folder, via, false);
    let failed: Vec<&str> = printed
        .lines()
        .filter(|t| t.starts_with("NOT OK"))
        .collect();
    let wanted = "NOT OK   a command: ui/status from a tool whose manifest declares no status. The app answers it with -32602: add `contributes.status`";
    if status != 1 || failed != [wanted] {
        problems.push(format!(
            "a tool that sets a status its manifest does not declare is not told:\n{printed}"
        ));
    }

    write_manifest(&manifest);
    env::set_var("BROKEN_HOW", "says a few words");
    let (status, printed) = check(folder, via, false);
    let failed: Vec<&str> = printed
        .lines()
        .filter(|t| t.starts_with("NOT OK"))
        .collect();
    let wanted = "NOT OK   a command: ui/status with words from a tool whose manifest does not declare them. The app draws the mark and leaves the words out: add \"activity\": true to contributes.status";
    if status != 1 || failed != [wanted] {
        problems.push(format!(
            "a tool that sends words its manifest does not declare is not told:\n{printed}"
        ));
    }

    let mut declared = manifest.clone();
    if let Some(mut c) = declared.get("contributes").cloned() {
        set_obj_field(
            &mut c,
            "status",
            obj_val(vec![
                ("placement", str_val("island")),
                ("activity", Value::Bool(true)),
            ]),
        );
        set_obj_field(&mut declared, "contributes", c);
    }
    write_manifest(&declared);
    let (status, printed) = check(folder, via, false);
    let wanted = [
        "ok       a command: hello: ran, and set the status: busy, busy",
        "ok       an older app: answered the hello, ran hello, drew lights and left with 0; it sent no ui/status",
    ];
    if status != 0 || !wanted.iter().all(|piece| printed.contains(piece)) {
        problems.push(format!(
            "a tool that declares its words and sends them does not pass:\n{printed}"
        ));
    }
    problems
}

fn slots(base_manifest: &Value, via: &str) -> Vec<String> {
    let mut problems = Vec::new();
    let mut manifest = base_manifest.clone();
    set_obj_field(&mut manifest, "protocol", str_val("2"));
    set_obj_field(&mut manifest, "uses", Value::Arr(vec![str_val("notify")]));
    set_obj_field(
        &mut manifest,
        "runtime",
        obj_val(vec![
            ("kind", str_val("external")),
            ("exec", str_val("slot.py")),
        ]),
    );
    let commands = manifest
        .get("contributes")
        .and_then(|c| c.get("commands"))
        .cloned()
        .unwrap_or_else(|| Value::Arr(vec![]));
    set_obj_field(
        &mut manifest,
        "contributes",
        obj_val(vec![
            ("commands", commands.clone()),
            ("slot", obj_val(vec![("placement", str_val("agents"))])),
        ]),
    );

    let Ok(temp) = TempDir::new("conformance-slots-") else {
        return vec!["could not create temp dir for slots".into()];
    };
    let folder = temp.path();
    let write_manifest = |declared: &Value| {
        let _ = fs::write(folder.join("vitruvian-tool.json"), declared.dumps_compact());
    };
    write_manifest(&manifest);
    let _ = fs::write(folder.join("slot.py"), "# mock slot tool\n");

    env::set_var("BROKEN_HOW", "docks well");
    let (status, printed) = check(folder, via, false);
    let wanted = [
        "ok       handshake: version 2, tool 0, and told where its slot is",
        "ok       a command: hello: ran, and asked for its slot",
        "ok       refusals: 2 refused",
        "ok       an older app: answered the hello, ran hello and left with 0",
    ];
    if status != 0 || !wanted.iter().all(|piece| printed.contains(piece)) {
        problems.push(format!("a tool that docks well does not pass:\n{printed}"));
    }

    for (how, line) in BROKEN_SLOT {
        env::set_var("BROKEN_HOW", how);
        let (status, printed) = check(folder, via, false);
        let failed: Vec<&str> = printed
            .lines()
            .filter(|t| t.starts_with("NOT OK"))
            .collect();
        if status != 1 || failed.len() != 1 || !failed[0].starts_with(line) {
            problems.push(format!("a tool that {how} is not caught:\n{printed}"));
        }
    }

    let mut undeclared = manifest.clone();
    set_obj_field(
        &mut undeclared,
        "contributes",
        obj_val(vec![("commands", commands)]),
    );
    write_manifest(&undeclared);
    env::set_var("BROKEN_HOW", "docks well");
    let (status, printed) = check(folder, via, false);
    let failed: Vec<&str> = printed
        .lines()
        .filter(|t| t.starts_with("NOT OK"))
        .collect();
    let wanted = "NOT OK   a command: ui/dock from a tool whose manifest declares no slot. The app answers it with -32602: add `contributes.slot`";
    if status != 1 || failed != [wanted] {
        problems.push(format!(
            "a tool that docks with no slot declared is not told:\n{printed}"
        ));
    }
    problems
}

fn the_hello(manifest: &Value) -> Vec<String> {
    let mut problems = Vec::new();

    struct Kept {
        sent: Vec<Value>,
    }
    impl Transport for Kept {
        fn send(&mut self, message: &Value) -> Result<(), Failure> {
            self.sent.push(message.clone());
            Ok(())
        }
        fn receive(
            &mut self,
            _deadline: Instant,
            _seconds: u64,
            _leaving: bool,
        ) -> Result<Option<Value>, Failure> {
            Ok(Some(
                json::loads(
                    r#"{"jsonrpc": "2.0", "id": 1, "result": {"protocolVersion": "1", "toolVersion": "0"}}"#,
                )
                .unwrap(),
            ))
        }
    }

    let mut run_modern = Run::new(
        Kept { sent: Vec::new() },
        manifest,
        "/tmp/data",
        Run::<Kept>::default_features(),
    );
    let _ = run_modern.handshake();
    let sent_features: Option<Vec<&str>> = run_modern.link.sent[0]
        .get("params")
        .and_then(|p| p.get("features"))
        .and_then(|f| f.as_arr())
        .map(|arr| arr.iter().filter_map(|v| v.as_str()).collect());
    if sent_features.as_deref() != Some(FEATURES) {
        problems.push(format!(
            "the hello says {}",
            run_modern.link.sent[0]
                .get("params")
                .map(|p| p.py_repr())
                .unwrap_or_default()
        ));
    }

    let mut run_older = Run::new(Kept { sent: Vec::new() }, manifest, "/tmp/data", None);
    let _ = run_older.handshake();
    if run_older.link.sent[0]
        .get("params")
        .and_then(|p| p.get("features"))
        .is_some()
    {
        problems.push(format!(
            "the hello says {}",
            run_older.link.sent[0]
                .get("params")
                .map(|p| p.py_repr())
                .unwrap_or_default()
        ));
    }

    let check_hello = Run::new(
        Kept { sent: Vec::new() },
        manifest,
        "",
        Run::<Kept>::default_features(),
    )
    .hello();
    if check_hello.get("features").is_none() {
        problems.push("the hello of this app names no features".into());
    }
    problems
}

fn a_line_always_waiting() -> Vec<String> {
    struct AlwaysWaiting {
        give_up: Instant,
    }
    impl Transport for AlwaysWaiting {
        fn send(&mut self, _message: &Value) -> Result<(), Failure> {
            Ok(())
        }
        fn receive(
            &mut self,
            _deadline: Instant,
            _seconds: u64,
            _leaving: bool,
        ) -> Result<Option<Value>, Failure> {
            if Instant::now() >= self.give_up {
                return Err(Failure::new("read on past its limit"));
            }
            Ok(Some(
                json::loads(
                    r#"{"jsonrpc": "2.0", "method": "log", "params": {"message": "still here"}}"#,
                )
                .unwrap(),
            ))
        }
    }

    let empty_manifest = obj_val(vec![]);
    let mut run = Run::new(
        AlwaysWaiting {
            give_up: Instant::now() + Duration::from_secs(2 * EXIT_SECONDS),
        },
        &empty_manifest,
        "",
        Run::<AlwaysWaiting>::default_features(),
    );
    let started = Instant::now();
    let said = match run.last_words() {
        Ok(n) => format!("read {n} messages and was content"),
        Err(failure) => failure.to_string(),
    };
    let took = started.elapsed().as_secs_f64();
    let wanted = format!("still writing {EXIT_SECONDS} seconds after it exited");
    if said != wanted || took > (EXIT_SECONDS as f64) + 1.0 {
        return vec![format!(
            "a line always waiting: {said}, after {took:.1} seconds"
        )];
    }
    Vec::new()
}

fn answers_with_its_page(folder: &Path, python: &str) -> Vec<String> {
    let Ok(manifest_text) = fs::read_to_string(folder.join("vitruvian-tool.json")) else {
        return vec!["could not read reference-tool-2 manifest".into()];
    };
    let Ok(manifest) = json::loads(&manifest_text) else {
        return vec!["could not parse reference-tool-2 manifest".into()];
    };
    let exec_rel = manifest
        .get("runtime")
        .and_then(|r| r.get("exec"))
        .and_then(|e| e.as_str())
        .unwrap_or("bin/reference_tool_2.py");
    let program = folder.join(exec_rel).to_string_lossy().into_owned();
    let Ok(temp) = TempDir::new("conformance-answers-page-") else {
        return vec!["could not create temp dir".into()];
    };
    let data_folder = temp.path().to_string_lossy().into_owned();
    let command = vec![python.to_string(), program];
    let Ok(link) = Link::spawn(&command, temp.path()) else {
        return vec!["could not spawn reference-tool-2".into()];
    };
    let mut run = Run::new(
        link,
        &manifest,
        data_folder,
        Run::<Link>::default_features(),
    );
    let res = (|| -> Result<String, Failure> {
        run.handshake()?;
        let said = run.a_panel()?;
        run.shutdown()?;
        Ok(said)
    })();
    run.link.close();
    let said = match res {
        Ok(s) => s,
        Err(failure) => {
            return vec![format!(
                "the reference tool of protocol 2 failed: {failure}"
            )]
        }
    };
    if !said.contains("a new page after a tap") {
        return vec![format!(
            "the reference tool of protocol 2 drew no new page after a tap: {said}"
        )];
    }
    if !run.rendered.is_empty() {
        return vec![
            "the reference tool of protocol 2 sent its page with ui/render, not in its answer to the tap"
                .into(),
        ];
    }
    Vec::new()
}

pub fn run_all() -> Result<Vec<String>, String> {
    let pkg_dir = find_package_dir()?;
    let reference = pkg_dir.join("conformance/reference-tool");
    let reference_2 = pkg_dir.join("conformance/reference-tool-2");
    let current_exe = env::current_exe()
        .map_err(|e| format!("current_exe: {e}"))?
        .to_string_lossy()
        .into_owned();

    let mut problems = Vec::new();

    let (status, printed) = check(&reference, &current_exe, true);
    let wanted = [
        "ok       handshake",
        "ok       a command: hello: ran",
        "ok       unknown",
        "1 refused",
        "exited with 0",
        "ok       an older app: answered the hello, ran hello and left with 0; it sent no ui/status",
    ];
    if status != 0 || !wanted.iter().all(|piece| printed.contains(piece)) {
        problems.push(format!("the reference tool does not pass:\n{printed}"));
    }

    let (status, printed) = check(&reference_2, &current_exe, true);
    let wanted = [
        "ok       handshake: version 2, tool 0.1.0",
        "ok       a command: hello: ran",
        "ok       unknown",
        "ok       a panel: hello: a page of 2 blocks, and a new page after a tap on press",
        "1 refused",
        "exited with 0",
        "ok       an older app: answered the hello, ran hello, drew hello and left with 0; it sent no ui/status",
    ];
    if status != 0 || !wanted.iter().all(|piece| printed.contains(piece)) {
        problems.push(format!(
            "the reference tool of protocol 2 does not pass:\n{printed}"
        ));
    }
    problems.extend(answers_with_its_page(&reference_2, &current_exe));

    let manifest_text = fs::read_to_string(reference.join("vitruvian-tool.json"))
        .map_err(|e| format!("read reference manifest: {e}"))?;
    let mut manifest = json::loads(&manifest_text)?;
    set_obj_field(
        &mut manifest,
        "runtime",
        obj_val(vec![
            ("kind", str_val("external")),
            ("exec", str_val("broken.py")),
        ]),
    );

    let temp = TempDir::new("conformance-broken-").map_err(|e| format!("tempdir: {e}"))?;
    let folder = temp.path();
    fs::write(folder.join("vitruvian-tool.json"), manifest.dumps_compact())
        .map_err(|e| format!("write manifest: {e}"))?;
    fs::write(folder.join("broken.py"), "# mock broken tool\n")
        .map_err(|e| format!("write broken.py: {e}"))?;

    for (how, line) in BROKEN {
        env::set_var("BROKEN_HOW", how);
        let started = Instant::now();
        let (status, printed) = check(folder, &current_exe, false);
        let took = started.elapsed().as_secs_f64();
        let failed: Vec<&str> = printed
            .lines()
            .filter(|t| t.starts_with("NOT OK"))
            .collect();
        if status != 1 || failed.len() != 1 || !failed[0].starts_with(line) {
            problems.push(format!("a tool that {how} is not caught:\n{printed}"));
        }
        if took > SLOWEST_SECONDS {
            problems.push(format!(
                "a tool that {how} held the script {took:.1} seconds"
            ));
        }
    }

    env::set_var("BROKEN_HOW", "nothing");
    let (status, printed) = check(folder, &current_exe, true);
    if status != 1 || !printed.contains("--expect-refusal was given") {
        problems.push(format!(
            "a tool that asks for nothing passes --expect-refusal:\n{printed}"
        ));
    }
    let (status, printed) = check(folder, &current_exe, false);
    if status != 0 || !printed.contains("nothing was refused") {
        problems.push(format!(
            "a tool that only answers does not pass:\n{printed}"
        ));
    }

    env::set_var("BROKEN_HOW", "parts well");
    let (status, printed) = check(folder, &current_exe, false);
    if status != 0 || !printed.contains("exited with 0, after 1 more message") {
        problems.push(format!(
            "a tool that says a last good word does not pass:\n{printed}"
        ));
    }

    problems.extend(never_stops_writing(folder, &current_exe));
    drop(temp);

    problems.extend(panels(&manifest, &current_exe));
    problems.extend(statuses(&manifest, &current_exe));
    problems.extend(slots(&manifest, &current_exe));
    problems.extend(the_hello(&manifest));
    problems.extend(a_line_always_waiting());

    Ok(problems)
}

pub fn main_with_args(args: &[String]) -> i32 {
    if let Some(code) = maybe_run_mock_tool(args) {
        return code;
    }
    match run_all() {
        Ok(problems) => {
            for problem in &problems {
                eprintln!("{problem}");
            }
            println!(
                "conformance: {}",
                if problems.is_empty() { "OK" } else { "FAILED" }
            );
            if problems.is_empty() {
                0
            } else {
                1
            }
        }
        Err(err) => {
            eprintln!("{err}");
            println!("conformance: FAILED");
            1
        }
    }
}
