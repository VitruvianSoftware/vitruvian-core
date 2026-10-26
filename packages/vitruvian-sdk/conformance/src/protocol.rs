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

//! Vitruvian tool protocol v1 & v2 constants, block/tree/name rules, and
//! JSON-RPC message & parameter validators.

use std::collections::HashSet;
use std::fmt;

use crate::json::Value;
use crate::pystr;

pub const MAX_LINE_BYTES: usize = 1_048_576;
pub const FIRST_ANSWER_SECONDS: u64 = 10;
pub const ANSWER_SECONDS: u64 = 2;
pub const EXIT_SECONDS: u64 = 2;

pub const MAX_TREE_BYTES: usize = 262_144;
pub const MAX_BLOCKS: usize = 200;
pub const NEEDS_ID: &[&str] = &["button", "toggle", "field", "list", "choice", "chips"];
pub const VERSIONS: &[&str] = &["1", "2"];

/// What this app says it has beyond the first release of the protocol version,
/// in the hello. An app before 3.48 says nothing.
pub const FEATURES: &[&str] = &[
    "ui.status",
    "ui.choice",
    "preferences.options",
    "ui.status.activity",
    "ui.open.settings",
    "ui.chips",
    "ui.sections",
    "notify.notice",
    "ui.slot",
    "preferences.folder",
];

pub const STATES: &[&str] = &["none", "ok", "busy", "attention", "failure"];
pub const MAX_CHOICE_OPTIONS: usize = 64;
pub const MAX_CHOICE_VALUE: usize = 128;

/// The longest a name may be: a block's id, a list row's id. The app's rule is
/// `ManifestRules.isWellFormedName`, with `ManifestLimits.maxNameLength`.
pub const MAX_NAME: usize = 128;

/// The most `ui/status` a tool may send an app that answers each with -32601.
pub const MAX_STATUS_AFTER_REFUSAL: usize = 5;

pub const INVALID_PARAMS: i64 = -32602;
pub const METHOD_NOT_FOUND: i64 = -32601;
pub const NOT_IN_USES: i64 = -32001;
pub const UNAVAILABLE: i64 = -32004;

/// The kinds that may carry help: a line or two under the control.
pub const HAS_HELP: &[&str] = &["toggle", "field", "choice", "chips"];

/// A check the tool did not pass.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Failure(pub String);

impl Failure {
    pub fn new(msg: impl Into<String>) -> Self {
        Self(msg.into())
    }
}

impl fmt::Display for Failure {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

impl std::error::Error for Failure {}

/// Each request a tool may make: the entry of `uses` it needs, and what the app
/// answers once it has done the work.
pub fn service_spec(method: &str) -> Option<(&'static str, Value)> {
    let empty = || Value::Obj(Vec::new());
    match method {
        "notify/hud" => Some(("notify", empty())),
        "notify/beep" => Some(("notify", empty())),
        "open/url" => Some((
            "open",
            Value::Obj(vec![("opened".into(), Value::Bool(true))]),
        )),
        "clipboard/readText" => Some((
            "clipboard.read",
            Value::Obj(vec![("text".into(), Value::Str("conformance".into()))]),
        )),
        "clipboard/writeText" => Some((
            "clipboard.write",
            Value::Obj(vec![("written".into(), Value::Bool(true))]),
        )),
        "keystrokes/paste" => Some(("keystrokes", empty())),
        "keystrokes/pressMenuItem" => Some((
            "keystrokes",
            Value::Obj(vec![("pressed".into(), Value::Bool(true))]),
        )),
        "processes/terminate" => Some(("processes", empty())),
        "storage/get" => Some(("storage", Value::Null)),
        "storage/set" => Some(("storage", empty())),
        "ui/badge" => Some(("notify", empty())),
        "notify/notice" => Some(("notify", empty())),
        _ => None,
    }
}

/// The requests an app has only when its hello names the feature: an app that
/// does not answers them with -32601, and a tool must ask before it sends one.
pub fn gated_spec(method: &str) -> Option<(&'static str, &'static str)> {
    match method {
        "notify/notice" => Some(("notify.notice", "send notify/hud there")),
        "ui/dock" => Some(("ui.slot", "dock nothing there")),
        _ => None,
    }
}

pub fn is_text(value: &Value) -> bool {
    value.is_str()
}

pub fn is_flag(value: &Value) -> bool {
    value.is_bool()
}

pub fn is_number(value: &Value) -> bool {
    value.is_number()
}

pub fn is_whole(value: &Value) -> bool {
    value.is_whole()
}

/// What a preference may hold: text, yes or no, or a number.
pub fn is_saved(value: &Value) -> bool {
    is_text(value) || is_flag(value) || is_number(value)
}

pub fn is_equivalent(value: &Value) -> bool {
    if !value.is_dict() {
        return false;
    }
    if !value.get("character").is_some_and(is_text) {
        return false;
    }
    match value.get("modifiers").and_then(|v| v.as_arr()) {
        Some(mods) => mods.iter().all(|held| {
            held.as_str()
                .is_some_and(|s| matches!(s, "shift" | "option" | "control"))
        }),
        None => false,
    }
}

pub fn is_count(value: &Value) -> bool {
    is_whole(value) && value.is_non_negative()
}

/// Text the person reads: a string, or one entry per language with English under `en`.
pub fn is_ui_text(value: &Value) -> bool {
    if is_text(value) {
        return true;
    }
    match value.as_obj() {
        Some(items) => {
            value.get("en").is_some_and(is_text) && items.iter().all(|(_, v)| is_text(v))
        }
        None => false,
    }
}

pub fn is_state(value: &Value) -> bool {
    value.as_str().is_some_and(|s| STATES.contains(&s))
}

/// A start time: Unix seconds, never before 1970.
pub fn is_since(value: &Value) -> bool {
    is_number(value) && value.is_non_negative()
}

/// A choice's own fields: what is selected, and from 1 to 64 options, each a
/// value and a title, no two with one value.
pub fn is_choice(value: &Value) -> bool {
    let options = value.get("options");
    let val_str = match value.get("value").and_then(|v| v.as_str()) {
        Some(s) => s,
        None => return false,
    };
    if pystr::len(val_str) > MAX_CHOICE_VALUE {
        return false;
    }
    let options = match options.and_then(|v| v.as_arr()) {
        Some(opts) if (1..=MAX_CHOICE_OPTIONS).contains(&opts.len()) => opts,
        _ => return false,
    };
    let mut seen = HashSet::with_capacity(options.len());
    for option in options {
        if !option.is_dict() || !option.get("title").is_some_and(is_ui_text) {
            return false;
        }
        let opt_val = match option.get("value").and_then(|v| v.as_str()) {
            Some(s) if pystr::len(s) <= MAX_CHOICE_VALUE => s,
            _ => return false,
        };
        seen.insert(opt_val);
    }
    if seen.len() != options.len() {
        return false;
    }
    value.get("title").map_or(true, is_ui_text) && value.get("enabled").map_or(true, is_flag)
}

/// Chips' own fields: from 1 to 64 options, each a value, a title and whether
/// it is on, no two with one value; a chip that cannot be turned may say why.
pub fn is_chips(value: &Value) -> bool {
    let options = match value.get("options").and_then(|v| v.as_arr()) {
        Some(opts) if (1..=MAX_CHOICE_OPTIONS).contains(&opts.len()) => opts,
        _ => return false,
    };
    let mut seen = HashSet::with_capacity(options.len());
    for option in options {
        if !option.is_dict() || !option.get("title").is_some_and(is_ui_text) {
            return false;
        }
        let opt_val = match option.get("value").and_then(|v| v.as_str()) {
            Some(s) if pystr::len(s) <= MAX_CHOICE_VALUE => s,
            _ => return false,
        };
        if !option.get("on").is_some_and(is_flag) {
            return false;
        }
        if !option.get("enabled").map_or(true, is_flag) {
            return false;
        }
        if !option.get("reason").map_or(true, is_ui_text) {
            return false;
        }
        seen.insert(opt_val);
    }
    if seen.len() != options.len() {
        return false;
    }
    value.get("title").map_or(true, is_ui_text) && value.get("enabled").map_or(true, is_flag)
}

/// A block: a kind, and an id where its kind needs one, which is text on any
/// block that has one.
pub fn is_block(value: &Value) -> bool {
    if !value.is_dict() {
        return false;
    }
    let kind = match value.get("type").and_then(|v| v.as_str()) {
        Some(k) => k,
        None => return false,
    };
    (!NEEDS_ID.contains(&kind) || value.get("id").is_some_and(is_text))
        && value
            .get("id")
            .map_or(true, |id| matches!(id, Value::Null) || is_text(id))
        && (kind != "choice" || is_choice(value))
        && (kind != "chips" || is_chips(value))
        && (kind != "heading" || value.get("section").map_or(true, is_flag))
        && (!HAS_HELP.contains(&kind) || value.get("help").map_or(true, is_ui_text))
}

fn is_name_char(c: char) -> bool {
    c.is_ascii_alphanumeric() || matches!(c, '.' | '-' | '_')
}

/// The rule of a name that `text` breaks, in words, or `None` when it is a name:
/// ASCII letters, digits, `.`, `-` and `_`, at most 128 of them, with no dot at
/// either end and no two together.
pub fn name_rule_broken(text: &str) -> Option<String> {
    if text.is_empty() {
        return Some("at least one character".into());
    }
    if !text.chars().all(is_name_char) {
        return Some("ASCII letters, digits, '.', '-' and '_' only".into());
    }
    if pystr::len(text) > MAX_NAME {
        return Some(format!("at most {} characters", MAX_NAME));
    }
    if text.starts_with('.') || text.ends_with('.') {
        return Some("no '.' at either end".into());
    }
    if text.contains("..") {
        return Some("no two '.' together".into());
    }
    None
}

/// What on a page of `panel` has an id that is not a name, said in words, or
/// `None`.
pub fn misnamed(tree: &Value, panel: &str) -> Option<String> {
    let refused = "Vitruvian refuses the whole page";
    let blocks = tree.get("blocks").and_then(|v| v.as_arr()).unwrap_or(&[]);
    for block in blocks {
        let named = block.get("id").filter(|v| !matches!(v, Value::Null));
        if let Some(named_val) = named {
            let named_str = named_val.as_str().unwrap_or("");
            if let Some(rule) = name_rule_broken(named_str) {
                return Some(format!(
                    "the page of {} has block id {}, which is not a valid name ({}): {}",
                    panel,
                    named_val.py_repr(),
                    rule,
                    refused
                ));
            }
        }
        let is_list = block.get("type").and_then(|v| v.as_str()) == Some("list");
        let rows = if is_list {
            block.get("rows").and_then(|v| v.as_arr()).unwrap_or(&[])
        } else {
            &[]
        };
        let named_repr = named.map(|v| v.py_repr()).unwrap_or_else(|| "None".into());
        for row in rows {
            if !row.is_dict() {
                continue;
            }
            let row_id = match row.get("id") {
                Some(v) if is_text(v) => v,
                _ => {
                    return Some(format!(
                        "the page of {} has a row in list {} whose id is missing or not text: {}",
                        panel, named_repr, refused
                    ));
                }
            };
            let row_id_str = row_id.as_str().unwrap_or("");
            if let Some(rule) = name_rule_broken(row_id_str) {
                return Some(format!(
                    "the page of {} has list row id {} in list {}, which is not a valid name ({}): {}",
                    panel,
                    row_id.py_repr(),
                    named_repr,
                    rule,
                    refused
                ));
            }
        }
    }
    None
}

/// What a page of `panel` holds that an app with only these features does not
/// draw, said in words, or `None`. `features` is `None` for an app that named none.
pub fn newer_than(tree: &Value, features: Option<&[String]>, panel: &str) -> Option<String> {
    let have: &[String] = features.unwrap_or(&[]);
    let has = |feat: &str| have.iter().any(|f| f == feat);
    let blocks = tree.get("blocks").and_then(|v| v.as_arr()).unwrap_or(&[]);
    for block in blocks {
        let kind = block.get("type").and_then(|v| v.as_str()).unwrap_or("");
        if kind == "chips" && !has("ui.chips") {
            return Some(format!(
                "the page of {} holds chips, which an app without ui.chips draws as their fallback text and nobody can change: ask supports first, and send a toggle for each option",
                panel
            ));
        }
        if has("ui.sections") {
            continue;
        }
        if kind == "heading" && block.get("section").and_then(|v| v.as_bool()) == Some(true) {
            return Some(format!(
                "the page of {} holds a heading that starts a section, which an app without ui.sections draws as a plain heading: ask supports first",
                panel
            ));
        }
        if HAS_HELP.contains(&kind) && block.has("help") {
            return Some(format!(
                "the page of {} holds help on a {}, which an app without ui.sections leaves out: ask supports first, and send a text after the control",
                panel, kind
            ));
        }
    }
    None
}

/// A page: at most 200 blocks, and at most 262,144 bytes as JSON.
pub fn is_tree(value: &Value) -> bool {
    if !value.is_dict() {
        return false;
    }
    let blocks = match value.get("blocks").and_then(|v| v.as_arr()) {
        Some(b) => b,
        None => return false,
    };
    if blocks.len() > MAX_BLOCKS || !blocks.iter().all(is_block) {
        return false;
    }
    value.dumps_compact().len() <= MAX_TREE_BYTES
}

type ParamCheck = fn(&Value) -> bool;

fn is_text_list(value: &Value) -> bool {
    value
        .as_arr()
        .is_some_and(|items| items.iter().all(is_text))
}

fn is_equivalent_list(value: &Value) -> bool {
    value
        .as_arr()
        .is_some_and(|items| items.iter().all(is_equivalent))
}

fn required_params(method: &str) -> &'static [(&'static str, ParamCheck)] {
    match method {
        "commands/state" => &[("runnable", is_text_list)],
        "log" => &[("message", is_text)],
        "notify/hud" => &[("icon", is_text), ("message", is_text)],
        "notify/beep" => &[],
        "open/url" => &[("url", is_text)],
        "clipboard/readText" => &[],
        "clipboard/writeText" => &[("text", is_text)],
        "keystrokes/paste" => &[("text", is_text)],
        "keystrokes/pressMenuItem" => &[("equivalents", is_equivalent_list)],
        "processes/terminate" => &[("pid", is_whole), ("name", is_text), ("force", is_flag)],
        "storage/get" => &[("key", is_text)],
        "storage/set" => &[("key", is_text), ("value", is_saved)],
        "ui/render" => &[("panel", is_text), ("tree", is_tree)],
        "ui/badge" => &[],
        "ui/status" => &[("state", is_state)],
        "notify/notice" => &[("icon", is_text), ("title", is_text)],
        "ui/dock" => &[],
        _ => &[],
    }
}

fn optional_params(method: &str) -> &'static [(&'static str, ParamCheck)] {
    match method {
        "notify/notice" => &[("detail", is_text), ("system", is_flag)],
        "ui/badge" => &[("count", is_count), ("dot", is_flag)],
        "ui/status" => &[
            ("text", is_ui_text),
            ("icon", is_text),
            ("activity", is_ui_text),
            ("since", is_since),
        ],
        _ => &[],
    }
}

/// Returns a `Failure` when a message the protocol has does not carry its params.
pub fn check_params(message: &Value) -> Result<(), Failure> {
    let empty_obj = Value::Obj(Vec::new());
    let params = message.get("params").unwrap_or(&empty_obj);
    let method = message.get("method").and_then(|v| v.as_str()).unwrap_or("");
    for &(name, check) in required_params(method) {
        if !params.get(name).is_some_and(check) {
            return Err(Failure::new(format!(
                "{} with params that are not its own: {}",
                method,
                params.py_repr()
            )));
        }
    }
    for &(name, check) in optional_params(method) {
        if let Some(val) = params.get(name) {
            if !check(val) {
                return Err(Failure::new(format!(
                    "{} with params that are not its own: {}",
                    method,
                    params.py_repr()
                )));
            }
        }
    }
    Ok(())
}

pub fn is_id(value: &Value) -> bool {
    matches!(value, Value::Int(_) | Value::Str(_))
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum MsgKind {
    Request,
    Notice,
    Result,
    Failure,
}

/// Classifies `message` as `Request`, `Notice`, `Result`, or `Failure`, or
/// returns a `Failure` for anything else.
pub fn kind_of(message: &Value) -> Result<MsgKind, Failure> {
    if !message.is_dict() || message.get("jsonrpc").and_then(|v| v.as_str()) != Some("2.0") {
        return Err(Failure::new(format!(
            "a line that is not a JSON-RPC 2.0 message: {}",
            message.py_repr()
        )));
    }
    if let Some(method_val) = message.get("method") {
        let answers = message.has("result") || message.has("error");
        if !method_val.is_str() || answers {
            return Err(Failure::new(format!(
                "a message that is not well formed: {}",
                message.py_repr()
            )));
        }
        if !message.get("params").map_or(true, |p| p.is_dict()) {
            return Err(Failure::new(format!(
                "params that are not an object: {}",
                message.py_repr()
            )));
        }
        return match message.get("id") {
            None => Ok(MsgKind::Notice),
            Some(id) if is_id(id) => Ok(MsgKind::Request),
            Some(_) => Err(Failure::new(format!(
                "a message that is not well formed: {}",
                message.py_repr()
            ))),
        };
    } else if let Some(error) = message.get("error") {
        if !message.has("result")
            && error.is_dict()
            && error.get("code").is_some_and(|c| c.is_int())
            && error.get("message").is_some_and(|m| m.is_str())
            && message
                .get("id")
                .is_some_and(|id| is_id(id) || matches!(id, Value::Null))
        {
            return Ok(MsgKind::Failure);
        }
    } else if message.has("result") && message.get("id").is_some_and(is_id) {
        return Ok(MsgKind::Result);
    }
    Err(Failure::new(format!(
        "a message that is not well formed: {}",
        message.py_repr()
    )))
}
