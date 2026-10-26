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

//! The built HomeSpeaker tool is a tool the app can add, and it speaks the
//! protocol: validate, conformance, end-to-end page driving, scratch folder
//! isolation, and chat monitor startup with a stand-in Beeper HTTP server.

use std::collections::HashMap;
use std::fs;
use std::io::{BufRead, BufReader, Write as IoWrite};
use std::net::TcpListener;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use conformance_rs_lib::json::{self as cjson, Value as CValue};
use conformance_rs_lib::{
    is_tree, misnamed, newer_than, Failure, Link, MsgKind, Run, TempDir, Transport, MAX_BLOCKS,
    MAX_TREE_BYTES,
};

// ── Constants ───────────────────────────────────────────────────────────

const SECTIONS: &[&str] = &["general", "speakers", "monitor", "agents", "googleCloud"];
const SECTION_TITLES: &[&str] = &["General", "Speakers", "Chats", "AI Agents", "Google Cloud"];
const SECONDS: u64 = 15;

const AGENT_MARKERS: &[&str] = &[".claude", ".gemini/antigravity-cli", ".config/opencode"];
const AGENT_BUTTONS: &[&str] = &[
    "installHook.claudeCode",
    "installHook.antigravity",
    "installHook.opencode",
];

const APP_FILES: &[&str] = &[
    "speaker_broadcast.json",
    "speaker_history.json",
    "speaker_monitor_status.json",
];
const DOOR_FILE: &str = "speaker_door.json";
const NOT_SET_UP: &str = "sayClipboard: refused, Set up HomeSpeaker first";

const MORE_SETTINGS: &str = "moreSettings";
const MORE_SETTINGS_CAPTION: &str =
    "More settings: Vitruvian Settings \u{203a} Extensions \u{203a} HomeSpeaker";
const QUIT_AGAIN: &str = "door.quitAgain";
const OLD_APP: &str = "This copy of the app is older than 1.19";

const FATAL: &str = "Fatal error";
const REAL_BEEPER_PORT: u16 = 23373;
const FAKE_BEEPER_TOKEN: &str = "fake-beeper-conformance-token"; // gitleaks:allow
const POLLS_WITHIN_SECONDS: u64 = 30;
const NOT_RUNNING: &str = "Beeper Desktop isn't running";

const BEEPER_PAGE: usize = 20;
const SETTLE_SECONDS: u64 = 3;
const HOOK_BACKSTOP_SECONDS: u64 = 8;

// ── Error type ──────────────────────────────────────────────────────────

#[derive(Debug)]
struct E2EFailure(String);

impl std::fmt::Display for E2EFailure {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}

macro_rules! fail {
    ($($arg:tt)*) => {
        return Err(E2EFailure(format!($($arg)*)))
    };
}

fn wrap(f: Failure) -> E2EFailure {
    E2EFailure(f.0.clone())
}

// ── Helpers ─────────────────────────────────────────────────────────────

fn resolve_env(key: &str) -> PathBuf {
    let raw = std::env::var(key).unwrap_or_else(|_| panic!("{} not set", key));
    let p = PathBuf::from(&raw);
    if p.exists() {
        return p;
    }
    if let Ok(runfiles) = std::env::var("RUNFILES_DIR") {
        let resolved = PathBuf::from(&runfiles).join("_main").join(&raw);
        if resolved.exists() {
            return resolved;
        }
    }
    p
}

fn copy_dir_deref(src: &Path, dst: &Path) -> std::io::Result<()> {
    fs::create_dir_all(dst)?;
    for entry in fs::read_dir(src)? {
        let entry = entry?;
        let src_path = entry.path();
        let meta = fs::metadata(&src_path)?;
        let dst_path = dst.join(entry.file_name());
        if meta.is_dir() {
            copy_dir_deref(&src_path, &dst_path)?;
        } else {
            fs::copy(&src_path, &dst_path)?;
        }
    }
    Ok(())
}

fn obj(items: &[(&str, CValue)]) -> CValue {
    CValue::Obj(
        items
            .iter()
            .map(|(k, v)| (k.to_string(), v.clone()))
            .collect(),
    )
}

fn s(text: &str) -> CValue {
    CValue::Str(text.to_string())
}

fn close_notice(panel: &str) -> CValue {
    obj(&[
        ("jsonrpc", s("2.0")),
        ("method", s("ui/close")),
        ("params", obj(&[("panel", s(panel))])),
    ])
}

fn words(value: &CValue) -> Vec<String> {
    match value {
        CValue::Str(s) => vec![s.clone()],
        CValue::Obj(items) => items.iter().flat_map(|(_, v)| words(v)).collect(),
        CValue::Arr(items) => items.iter().flat_map(words).collect(),
        _ => vec![],
    }
}

fn says(tree: &CValue, text: &str) -> bool {
    tree.get("blocks")
        .and_then(|b| b.as_arr())
        .map(|blocks| {
            blocks
                .iter()
                .any(|blk| words(blk).iter().any(|w| w.contains(text)))
        })
        .unwrap_or(false)
}

fn block<'a>(tree: &'a CValue, block_id: &str) -> Option<&'a CValue> {
    tree.get("blocks")?
        .as_arr()?
        .iter()
        .find(|b| b.get("id").and_then(|id| id.as_str()) == Some(block_id))
}

fn offers_no_quit(tree: &CValue, where_: &str) -> Result<(), E2EFailure> {
    if block(tree, QUIT_AGAIN).is_some() || says(tree, OLD_APP) {
        fail!(
            "{}: the page offers to quit a HomeSpeaker app, though none was found",
            where_
        );
    }
    Ok(())
}

fn every_section(tree: &CValue, where_: &str) -> Result<(), E2EFailure> {
    if block(tree, "section").is_some() {
        fail!("{}: a Section picker on a page with every section", where_);
    }
    let blocks = tree.get("blocks").and_then(|b| b.as_arr());
    let titles: Vec<String> = blocks
        .into_iter()
        .flatten()
        .filter(|b| {
            b.get("type").and_then(|t| t.as_str()) == Some("heading")
                && b.get("section").and_then(|s| s.as_bool()) == Some(true)
        })
        .map(|b| {
            let text = b.get("text").unwrap_or(&CValue::Null);
            words(text).join(" ")
        })
        .collect();
    let expected: Vec<&str> = SECTION_TITLES.to_vec();
    if titles.iter().map(|s| s.as_str()).collect::<Vec<_>>() != expected {
        fail!(
            "{}: the section headings are {:?}, not {:?}",
            where_,
            titles,
            SECTION_TITLES
        );
    }
    Ok(())
}

fn stderr_of(path: &Path) -> String {
    match fs::read_to_string(path) {
        Ok(text) => {
            let trimmed = text.trim();
            if trimmed.is_empty() {
                "nothing on its standard error".into()
            } else {
                format!("its standard error: {:?}", trimmed)
            }
        }
        Err(_) => "no standard error was kept".into(),
    }
}

fn unique_prefix() -> String {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default();
    format!(
        "test.{:x}{:x}.homespeaker",
        now.as_secs(),
        now.subsec_nanos()
    )
}

fn iso_now_minus(seconds: u64) -> String {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default();
    let past = now - Duration::from_secs(seconds);
    let secs = past.as_secs();
    let days_since_epoch = secs / 86400;
    let time_of_day = secs % 86400;
    let h = time_of_day / 3600;
    let m = (time_of_day % 3600) / 60;
    let sec = time_of_day % 60;
    let (y, mo, d) = days_to_ymd(days_since_epoch);
    format!("{:04}-{:02}-{:02}T{:02}:{:02}:{:02}Z", y, mo, d, h, m, sec)
}

fn days_to_ymd(mut days: u64) -> (u64, u64, u64) {
    let mut y = 1970;
    loop {
        let ylen = if is_leap(y) { 366 } else { 365 };
        if days < ylen {
            break;
        }
        days -= ylen;
        y += 1;
    }
    let mdays: [u64; 12] = if is_leap(y) {
        [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    } else {
        [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    };
    let mut mo = 0;
    for (i, &ml) in mdays.iter().enumerate() {
        if days < ml {
            mo = i;
            break;
        }
        days -= ml;
    }
    (y, (mo + 1) as u64, days + 1)
}

fn is_leap(y: u64) -> bool {
    y % 4 == 0 && (y % 100 != 0 || y % 400 == 0)
}

// ── Driver ──────────────────────────────────────────────────────────────

struct Driver<'a> {
    run: &'a mut Run<Link>,
    pages: Vec<String>,
    current: HashMap<String, CValue>,
}

impl<'a> Driver<'a> {
    fn new(run: &'a mut Run<Link>) -> Self {
        Self {
            run,
            pages: Vec::new(),
            current: HashMap::new(),
        }
    }

    fn check(&mut self, tree: &CValue, where_: &str) -> Result<CValue, E2EFailure> {
        if !is_tree(tree) {
            let size = tree.dumps_compact().len();
            let count = tree
                .get("blocks")
                .and_then(|b| b.as_arr())
                .map(|a| a.len())
                .unwrap_or(0);
            fail!(
                "{}: not a page within the protocol's limits ({} blocks of at most {}, {} bytes of at most {})",
                where_, count, MAX_BLOCKS, size, MAX_TREE_BYTES
            );
        }
        if let Some(wrong) = misnamed(tree, where_) {
            fail!("{}: {}", where_, wrong);
        }
        if let Some(newer) = newer_than(tree, self.run.features.as_deref(), where_) {
            fail!("{}: {}", where_, newer);
        }
        let size = tree.dumps_compact().len();
        let count = tree
            .get("blocks")
            .and_then(|b| b.as_arr())
            .map(|a| a.len())
            .unwrap_or(0);
        self.pages
            .push(format!("{}: {} blocks, {} bytes", where_, count, size));
        Ok(tree.clone())
    }

    fn ask(&mut self, method: &str, params: CValue, where_: &str) -> Result<CValue, E2EFailure> {
        let id = self
            .run
            .request(method, params)
            .map_err(|f| E2EFailure(format!("{}: {}", where_, f.0)))?;
        let (kind, message) = self
            .run
            .answer(&id, SECONDS, false)
            .map_err(|f| E2EFailure(format!("{}: {}", where_, f.0)))?;
        if kind != MsgKind::Result {
            fail!("{}: answered with {}", where_, message.py_repr());
        }
        match message.get("result") {
            Some(r) if r.is_dict() => Ok(r.clone()),
            _ => fail!("{}: answered with {}", where_, message.py_repr()),
        }
    }

    fn open(&mut self, panel: &str) -> Result<CValue, E2EFailure> {
        let result = self.ask(
            "ui/open",
            obj(&[("panel", s(panel))]),
            &format!("open {}", panel),
        )?;
        let tree_val = result
            .get("tree")
            .cloned()
            .or_else(|| self.run.rendered.get(panel).cloned());
        let tree = match tree_val {
            Some(ref t) => self.check(t, panel)?,
            None => fail!("open {}: no page in result or rendered", panel),
        };
        self.current.insert(panel.to_string(), tree.clone());
        Ok(tree)
    }

    fn act(
        &mut self,
        panel: &str,
        block_id: &str,
        event: &str,
        value: Option<CValue>,
        keep_ok: bool,
    ) -> Result<Option<CValue>, E2EFailure> {
        let where_ = if let Some(ref v) = value {
            format!("{}: {} {} = {}", panel, event, block_id, v.py_repr())
        } else {
            format!("{}: {} {}", panel, event, block_id)
        };
        {
            let shown = self
                .run
                .rendered
                .remove(panel)
                .or_else(|| self.current.get(panel).cloned());
            match &shown {
                None => fail!("{}: the page shown has no such block", where_),
                Some(tree) if block(tree, block_id).is_none() => {
                    fail!("{}: the page shown has no such block", where_);
                }
                _ => {}
            }
        }
        let mut params_items: Vec<(&str, CValue)> = vec![
            ("panel", s(panel)),
            ("block", s(block_id)),
            ("event", s(event)),
        ];
        if let Some(v) = value {
            params_items.push(("value", v));
        }
        let params = obj(&params_items);
        let result = self.ask("ui/event", params, &where_)?;
        if result.get("tree").is_none() {
            if keep_ok && result.get("keep").and_then(|k| k.as_bool()) == Some(true) {
                return Ok(None);
            }
            fail!("{}: answered with no page: {}", where_, result.py_repr());
        }
        let tree_val = result.get("tree").unwrap().clone();
        let tree = self.check(&tree_val, &where_)?;
        self.current.insert(panel.to_string(), tree.clone());
        Ok(Some(tree))
    }

    fn section(&mut self, name: &str) -> Result<CValue, E2EFailure> {
        let is_list = {
            let shown = self
                .run
                .rendered
                .get("settings")
                .or_else(|| self.current.get("settings"));
            shown
                .and_then(|s| block(s, "section"))
                .map(|p| p.get("type").and_then(|t| t.as_str()) == Some("list"))
                .unwrap_or(false)
        };
        if is_list {
            let tree = self
                .act("settings", "section", "tap", Some(s(name)), false)?
                .ok_or_else(|| E2EFailure("section tap returned keep".into()))?;
            let rows = block(&tree, "section")
                .and_then(|b| b.get("rows"))
                .and_then(|r| r.as_arr())
                .unwrap_or(&[]);
            let picked: Vec<&str> = rows
                .iter()
                .filter(|row| {
                    row.get("trailing")
                        .map(|t| words(t).iter().any(|w| w.contains('\u{2713}')))
                        .unwrap_or(false)
                })
                .filter_map(|row| row.get("id").and_then(|id| id.as_str()))
                .collect();
            if picked != [name] {
                fail!(
                    "settings: the section list does not tick {}: {:?}",
                    name,
                    rows.iter().map(|r| r.py_repr()).collect::<Vec<_>>()
                );
            }
            return Ok(tree);
        }
        let tree = self
            .act("settings", "section", "change", Some(s(name)), false)?
            .ok_or_else(|| E2EFailure("section change returned keep".into()))?;
        let picker = block(&tree, "section");
        if picker.is_none()
            || picker.and_then(|p| p.get("value").and_then(|v| v.as_str())) != Some(name)
        {
            fail!(
                "settings: the section picker does not show {}: {}",
                name,
                picker.map(|p| p.py_repr()).unwrap_or_default()
            );
        }
        Ok(tree)
    }
}

// ── where check ─────────────────────────────────────────────────────────

fn where_check(
    program: &Path,
    data: &Path,
    env: &HashMap<String, String>,
) -> Result<String, E2EFailure> {
    let done = Command::new(program)
        .arg("--where")
        .envs(env)
        .output()
        .map_err(|e| E2EFailure(format!("--where: cannot run: {}", e)))?;
    if !done.status.success() {
        fail!(
            "--where exited {}: {}{}",
            done.status.code().unwrap_or(-1),
            String::from_utf8_lossy(&done.stdout),
            String::from_utf8_lossy(&done.stderr)
        );
    }
    let named = String::from_utf8_lossy(&done.stdout).trim().to_string();
    let named_real = fs::canonicalize(&named).unwrap_or_else(|_| PathBuf::from(&named));
    let data_real = fs::canonicalize(data).unwrap_or_else(|_| data.to_path_buf());
    if named_real != data_real {
        fail!(
            "--where names {:?}, not the scratch data folder {:?}",
            named,
            data.display()
        );
    }
    Ok(format!("the program keeps its files in {}", named))
}

// ── nothing_outside ─────────────────────────────────────────────────────

fn nothing_outside(home: &Path, scratch: &Path) -> Result<String, E2EFailure> {
    let gemini = home.join(".gemini");
    for name in APP_FILES {
        let path = gemini.join(name);
        if path.exists() {
            fail!("{} was written: that is the app's file", path.display());
        }
    }
    let door = gemini.join(DOOR_FILE);
    if !door.exists() {
        return Ok(format!("nothing in {}", gemini.display()));
    }
    let text = fs::read_to_string(&door)
        .map_err(|e| E2EFailure(format!("cannot read {}: {}", door.display(), e)))?;
    let record: serde_json::Value = serde_json::from_str(&text)
        .map_err(|e| E2EFailure(format!("cannot parse {}: {}", door.display(), e)))?;
    let keys: Vec<&str> = record
        .as_object()
        .map(|o| o.keys().map(|k| k.as_str()).collect())
        .unwrap_or_default();
    let extra: Vec<&&str> = keys
        .iter()
        .filter(|k| **k != "version" && **k != "extension")
        .collect();
    if !extra.is_empty() {
        fail!(
            "{} holds more than the extension's block: {:?}",
            door.display(),
            keys
        );
    }
    let inside = fs::canonicalize(scratch)
        .unwrap_or_else(|_| scratch.to_path_buf())
        .to_string_lossy()
        .to_string();
    if let Some(ext) = record.get("extension").and_then(|e| e.as_object()) {
        for key in &["program", "data_folder"] {
            let path_str = ext.get(*key).and_then(|v| v.as_str()).unwrap_or("");
            let real = fs::canonicalize(path_str).unwrap_or_else(|_| PathBuf::from(path_str));
            if !real.to_string_lossy().starts_with(&inside) {
                fail!(
                    "{}: the extension's {} is {:?}, not in {}",
                    door.display(),
                    key,
                    path_str,
                    scratch.display()
                );
            }
        }
    }
    Ok(format!(
        "none of the app's files in {}; {} holds only the extension's block",
        gemini.display(),
        DOOR_FILE
    ))
}

// ── end_to_end ──────────────────────────────────────────────────────────

fn end_to_end(
    folder: &Path,
    data: &Path,
    env: &HashMap<String, String>,
) -> Result<Vec<String>, E2EFailure> {
    let manifest_path = folder.join("vitruvian-tool.json");
    let manifest_text = fs::read_to_string(&manifest_path)
        .map_err(|e| E2EFailure(format!("cannot read {}: {}", manifest_path.display(), e)))?;
    let manifest = cjson::loads(&manifest_text)
        .map_err(|e| E2EFailure(format!("cannot parse {}: {}", manifest_path.display(), e)))?;
    let exec = manifest
        .get("runtime")
        .and_then(|r| r.get("exec"))
        .and_then(|e| e.as_str())
        .ok_or_else(|| E2EFailure("manifest has no runtime.exec".into()))?;
    let program = folder.join(exec);
    let settings = data.join("settings.json");
    let secrets = data.join("secrets.json");
    let started_in = TempDir::new("vitruvian-e2e-").map_err(|e| E2EFailure(e.to_string()))?;

    for (key, value) in env {
        std::env::set_var(key, value);
    }
    let command = vec![program.to_string_lossy().to_string()];
    let link =
        Link::spawn(&command, started_in.path()).map_err(|e| wrap(Failure::new(e.to_string())))?;
    let mut said = Vec::new();

    // Modern app
    let mut run = Run::new(
        link,
        &manifest,
        started_in.path().to_string_lossy().to_string(),
        Run::<Link>::default_features(),
    );
    said.push(format!("handshake: {}", run.handshake().map_err(wrap)?));
    {
        let mut app = Driver::new(&mut run);

        let page = app.open("settings")?;
        offers_no_quit(&page, "settings, first page")?;
        every_section(&page, "settings")?;
        for path in [&settings, &secrets] {
            if !says(&page, &path.to_string_lossy()) {
                fail!(
                    "Files does not name {}: the tool is not using the test's data folder, and nothing may be written",
                    path.display()
                );
            }
        }
        said.push(format!(
            "settings: {} on one page",
            SECTION_TITLES.join(", ")
        ));
        let missing: Vec<&&str> = AGENT_BUTTONS
            .iter()
            .filter(|name| block(&page, name).is_none())
            .collect();
        if !missing.is_empty() {
            fail!(
                "settings: AI Agents does not draw {:?}, with Claude Code and Antigravity in the scratch home",
                missing
            );
        }
        said.push(format!(
            "settings: AI Agents draws {}",
            AGENT_BUTTONS.join(", ")
        ));

        let kept = app.ask(
            "ui/event",
            obj(&[
                ("panel", s("settings")),
                ("block", s("section")),
                ("event", s("change")),
                ("value", s("monitor")),
            ]),
            "settings: change section, from a page drawn before",
        )?;
        if kept.get("keep").and_then(|k| k.as_bool()) != Some(true) {
            fail!(
                "settings: a stale section event was answered with {}",
                kept.py_repr()
            );
        }
        said.push("settings: a stale section event kept".into());

        for block_id in &["quietStart", "quietEnd"] {
            let drawn = block(&page, block_id);
            if drawn.is_none()
                || drawn.and_then(|b| b.get("type").and_then(|t| t.as_str())) != Some("choice")
            {
                fail!(
                    "settings: {} is not a choice for an app that has one: {}",
                    block_id,
                    drawn.map(|d| d.py_repr()).unwrap_or_default()
                );
            }
        }
        app.act(
            "settings",
            "quiet",
            "toggle",
            Some(CValue::Bool(true)),
            false,
        )?;
        app.act("settings", "quietStart", "change", Some(s("23:00")), false)?;
        app.act("settings", "quietEnd", "change", Some(s("23:30")), false)?;
        app.act(
            "settings",
            "slackEnabled",
            "toggle",
            Some(CValue::Bool(true)),
            false,
        )?;
        let after_change = app
            .act("settings", "pollInterval", "submit", Some(s("45")), false)?
            .ok_or_else(|| E2EFailure("pollInterval submit returned keep".into()))?;
        every_section(&after_change, "settings, after a change")?;

        app.act(
            "settings",
            "oauthClientId",
            "change",
            Some(s("e2e-client.apps.googleusercontent.com")),
            true,
        )?;
        app.act(
            "settings",
            "oauthClientSecret",
            "change",
            Some(s("e2e-secret")),
            true,
        )?;
        let saved = app
            .act("settings", "saveOAuthClient", "tap", None, false)?
            .ok_or_else(|| E2EFailure("saveOAuthClient tap returned keep".into()))?;
        if !says(&saved, "OAuth client saved") {
            fail!("Save did not say the OAuth client was saved");
        }
        said.push(
            "settings: quiet hours picked, Slack, poll interval and an OAuth client changed".into(),
        );

        let island = app.open("speaker")?;
        offers_no_quit(&island, "speaker, first page")?;
        if says(&island, "not installed") {
            fail!("the island says HomeSpeaker is not installed");
        }
        app.act(
            "speaker",
            "broadcasting",
            "toggle",
            Some(CValue::Bool(false)),
            false,
        )?;
        said.push("speaker: drawn, broadcasting switched off".into());

        let island = app.current.get("speaker").cloned().unwrap();
        let blocks = island.get("blocks").and_then(|b| b.as_arr()).unwrap();
        let last = blocks.last().unwrap();
        if last.get("id").and_then(|id| id.as_str()) != Some(MORE_SETTINGS)
            || last.get("type").and_then(|t| t.as_str()) != Some("button")
        {
            fail!(
                "speaker: the last block is not the More settings button: {}",
                last.py_repr()
            );
        }
        let opened = app.ask(
            "ui/event",
            obj(&[
                ("panel", s("speaker")),
                ("block", s(MORE_SETTINGS)),
                ("event", s("tap")),
            ]),
            "speaker: tap moreSettings",
        )?;
        if opened.get("open").and_then(|o| o.as_str()) != Some("settings") {
            fail!(
                "speaker: More settings was not answered with open settings alone: {}",
                opened.py_repr()
            );
        }
        said.push("speaker: More settings answered open settings".into());

        app.run.link.send(&close_notice("speaker")).map_err(wrap)?;
        app.run.link.send(&close_notice("settings")).map_err(wrap)?;
        let sd = app.run.shutdown().map_err(wrap)?;
        said.push(format!("shutdown: {}", sd));
        said.extend(app.pages.drain(..));
    }

    // An older app (features=None): the typed quiet hour field and Section picker list
    let link2 =
        Link::spawn(&command, started_in.path()).map_err(|e| wrap(Failure::new(e.to_string())))?;
    let mut run2 = Run::new(
        link2,
        &manifest,
        started_in.path().to_string_lossy().to_string(),
        None,
    );
    said.push(format!("an older app: {}", run2.handshake().map_err(wrap)?));
    {
        let mut app = Driver::new(&mut run2);
        let _general = app.open("settings")?;
        offers_no_quit(
            app.current.get("settings").unwrap(),
            "an older app's settings, first page",
        )?;
        for name in SECTIONS {
            app.section(name)?;
        }
        said.push(format!(
            "an older app: {} each picked from the Section list",
            SECTIONS.join(", ")
        ));
        let general = app.section("general")?;
        let drawn = block(&general, "quietEnd");
        if drawn.is_none()
            || drawn.and_then(|b| b.get("type").and_then(|t| t.as_str())) != Some("field")
        {
            fail!(
                "settings: quietEnd is not the typed field for an app without choice: {}",
                drawn.map(|d| d.py_repr()).unwrap_or_default()
            );
        }
        let bad = app
            .act("settings", "quietEnd", "submit", Some(s("soon")), false)?
            .ok_or_else(|| E2EFailure("quietEnd submit returned keep".into()))?;
        if !says(&bad, "HH:mm") {
            fail!("a quiet hour that is not HH:mm was not said on the page");
        }

        let island = app.open("speaker")?;
        if block(&island, MORE_SETTINGS).is_some() || !says(&island, MORE_SETTINGS_CAPTION) {
            fail!("an older app's island does not end with where the settings are");
        }
        let kept = app.ask(
            "ui/event",
            obj(&[
                ("panel", s("speaker")),
                ("block", s(MORE_SETTINGS)),
                ("event", s("tap")),
            ]),
            "an older app's speaker: tap moreSettings",
        )?;
        if kept.get("open").is_some() {
            fail!("an older app was answered with open: {}", kept.py_repr());
        }
        app.run.link.send(&close_notice("speaker")).map_err(wrap)?;
        app.run.link.send(&close_notice("settings")).map_err(wrap)?;
        let sd = app.run.shutdown().map_err(wrap)?;
        said.push(format!(
            "an older app: the typed quiet hour refused, More settings a caption; {}",
            sd
        ));
        said.extend(app.pages.drain(..));
    }

    // Verify files on disk
    let written_text = fs::read_to_string(&settings)
        .map_err(|e| E2EFailure(format!("cannot read {}: {}", settings.display(), e)))?;
    let written: serde_json::Value = serde_json::from_str(&written_text)
        .map_err(|e| E2EFailure(format!("cannot parse {}: {}", settings.display(), e)))?;
    let expected: &[(&str, serde_json::Value)] = &[
        ("enabled", serde_json::Value::Bool(false)),
        ("quiet_hours_enabled", serde_json::Value::Bool(true)),
        (
            "quiet_hours_start",
            serde_json::Value::String("23:00".into()),
        ),
        ("quiet_hours_end", serde_json::Value::String("23:30".into())),
    ];
    for (key, value) in expected {
        if written.get(key) != Some(value) {
            fail!(
                "{}: {} is {:?}, not {:?}",
                settings.display(),
                key,
                written.get(key),
                value
            );
        }
    }
    if written.get("quiet_hours_end").and_then(|v| v.as_str()) == Some("soon") {
        fail!("{}: a refused quiet hour was saved", settings.display());
    }
    let monitor = written.get("chat_monitor");
    let slack_on = monitor
        .and_then(|m| m.get("slack_enabled"))
        .and_then(|v| v.as_bool())
        == Some(true);
    let poll_45 = monitor
        .and_then(|m| m.get("poll_interval_seconds"))
        .and_then(|v| v.as_u64())
        == Some(45);
    if !slack_on || !poll_45 {
        fail!("{}: chat_monitor is {:?}", settings.display(), monitor);
    }
    said.push("settings.json: written as changed".into());

    let secrets_text = fs::read_to_string(&secrets)
        .map_err(|e| E2EFailure(format!("cannot read {}: {}", secrets.display(), e)))?;
    if !secrets_text.contains("e2e-client.apps.googleusercontent.com") {
        fail!("{}: the OAuth client was not saved", secrets.display());
    }
    said.push("secrets.json: holds the OAuth client".into());
    Ok(said)
}

// ── StandInBeeper ───────────────────────────────────────────────────────

type RequestRecord = (String, String, String, HashMap<String, String>);

struct StandInBeeper {
    port: u16,
    requests: Arc<Mutex<Vec<RequestRecord>>>,
    shutdown: Arc<AtomicBool>,
    thread: Option<thread::JoinHandle<()>>,
}

fn parse_query(qs: &str) -> HashMap<String, String> {
    qs.split('&')
        .filter(|s| !s.is_empty())
        .filter_map(|pair| {
            let mut parts = pair.splitn(2, '=');
            let key = parts.next()?;
            let val = parts.next().unwrap_or("");
            Some((urldecode(key), urldecode(val)))
        })
        .collect()
}

fn urldecode(s: &str) -> String {
    let mut out = Vec::new();
    let bytes = s.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' && i + 2 < bytes.len() {
            if let Ok(b) =
                u8::from_str_radix(std::str::from_utf8(&bytes[i + 1..i + 3]).unwrap_or(""), 16)
            {
                out.push(b);
                i += 3;
                continue;
            }
        }
        if bytes[i] == b'+' {
            out.push(b' ');
        } else {
            out.push(bytes[i]);
        }
        i += 1;
    }
    String::from_utf8(out).unwrap_or_else(|e| String::from_utf8_lossy(e.as_bytes()).into_owned())
}

fn beeper_accounts() -> serde_json::Value {
    serde_json::json!([
        {
            "accountID": "local-whatsapp_ba_FAKE",
            "bridge": {"id": "local-whatsapp", "type": "whatsapp", "provider": "local"},
            "network": "WhatsApp",
            "user": {"id": "@me-wa:fake.test", "isSelf": true, "fullName": "Me"}
        },
        {
            "accountID": "local-signal_FAKE",
            "network": "Signal",
            "user": {"id": "@me-signal:fake.test"}
        },
        {
            "accountID": "slackgo.TFAKE-UFAKE",
            "network": "Slack",
            "user": {"id": "@me-slack:fake.test"}
        },
        {
            "accountID": "gmessages.someone@example.test/0",
            "bridge": {"type": "gmessages"},
            "network": "Google Messages",
            "user": {"id": "@me-sms:fake.test"}
        }
    ])
}

fn beeper_chats() -> serde_json::Value {
    serde_json::json!({
        "wa-dm": {"id": "wa-dm", "type": "single", "title": "Alice", "network": "WhatsApp"},
        "sig-family": {"id": "sig-family", "type": "group", "title": "Family", "network": "Signal"},
        "slack-dm": {"id": "slack-dm", "type": "single", "title": "Dee", "network": "Slack"}
    })
}

fn add_offset_to_iso(base: &str, seconds: f64) -> String {
    let (date_part, time_rest) = base
        .split_once('T')
        .unwrap_or(("1970-01-01", "00:00:00.000Z"));
    let time_str = time_rest.trim_end_matches('Z');
    let (time_part, frac_part) = time_str.split_once('.').unwrap_or((time_str, "0"));
    let parts: Vec<&str> = time_part.split(':').collect();
    let h: u64 = parts.first().and_then(|s| s.parse().ok()).unwrap_or(0);
    let m: u64 = parts.get(1).and_then(|s| s.parse().ok()).unwrap_or(0);
    let sec: u64 = parts.get(2).and_then(|s| s.parse().ok()).unwrap_or(0);
    let frac_padded = format!("{:0<3}", &frac_part[..frac_part.len().min(3)]);
    let ms: u64 = frac_padded.parse().unwrap_or(0);
    let total_ms = (h * 3_600_000 + m * 60_000 + sec * 1_000 + ms) as f64 + seconds * 1000.0;
    let total_ms = total_ms as u64;
    let new_h = (total_ms / 3_600_000) % 24;
    let new_m = (total_ms % 3_600_000) / 60_000;
    let new_s = (total_ms % 60_000) / 1_000;
    let new_ms = total_ms % 1_000;
    format!(
        "{}T{:02}:{:02}:{:02}.{:03}Z",
        date_part, new_h, new_m, new_s, new_ms
    )
}

fn beeper_messages(start: &str) -> Vec<serde_json::Value> {
    let mut out = Vec::with_capacity(51);
    let msg = |mid: &str, chat: &str, account: &str, sender: &str, secs_after: f64, text: &str| {
        let stamp = add_offset_to_iso(start, secs_after);
        serde_json::json!({
            "id": mid,
            "chatID": chat,
            "accountID": account,
            "senderID": format!("@{}:fake.test", sender.to_lowercase()),
            "senderName": sender,
            "timestamp": stamp,
            "type": "TEXT",
            "text": text,
            "isSender": false,
            "isHidden": false,
            "isDeleted": false,
            "mentions": null
        })
    };
    out.push(msg(
        "dm",
        "wa-dm",
        "local-whatsapp_ba_FAKE",
        "Alice",
        0.01,
        "behind the others",
    ));
    for n in 0..25 {
        out.push(msg(
            &format!("s{}", n),
            "slack-dm",
            "slackgo.TFAKE-UFAKE",
            "Dee",
            0.5 + n as f64 / 100.0,
            &format!("busy {}", n),
        ));
    }
    for n in 0..25 {
        out.push(msg(
            &format!("g{}", n),
            "sig-family",
            "local-signal_FAKE",
            "Bob",
            0.2 + n as f64 / 100.0,
            &format!("chat {}", n),
        ));
    }
    out
}

fn beeper_page(
    query: &HashMap<String, String>,
    messages: &Mutex<Option<Vec<serde_json::Value>>>,
) -> (u16, serde_json::Value) {
    let limit: usize = query
        .get("limit")
        .and_then(|l| l.parse().ok())
        .unwrap_or(BEEPER_PAGE);
    if !(1..=BEEPER_PAGE).contains(&limit) {
        return (
            400,
            serde_json::json!({"message": format!("limit must be 1 to {}", BEEPER_PAGE)}),
        );
    }
    let mut guard = messages.lock().unwrap();
    let date_after = query.get("dateAfter").cloned().unwrap_or_default();
    if guard.is_none() {
        *guard = Some(beeper_messages(&date_after));
    }
    let all = guard.as_ref().unwrap().clone();
    drop(guard);

    let mut matching: Vec<&serde_json::Value> = all
        .iter()
        .filter(|m| {
            m.get("timestamp")
                .and_then(|t| t.as_str())
                .map(|t| t > date_after.as_str())
                .unwrap_or(false)
        })
        .collect();
    matching.sort_by(|a, b| {
        let ta = a.get("timestamp").and_then(|t| t.as_str()).unwrap_or("");
        let tb = b.get("timestamp").and_then(|t| t.as_str()).unwrap_or("");
        tb.cmp(ta)
    });

    let mut offset: usize = 0;
    if let Some(cursor) = query.get("cursor") {
        if query.get("direction").map(|d| d.as_str()) != Some("before") || !cursor.starts_with('c')
        {
            return (400, serde_json::json!({"message": "bad cursor"}));
        }
        offset = cursor[1..].parse().unwrap_or(0);
    }
    let end = (offset + limit).min(matching.len());
    let items: Vec<serde_json::Value> =
        matching[offset..end].iter().map(|v| (*v).clone()).collect();
    (
        200,
        serde_json::json!({
            "items": items,
            "hasMore": end < matching.len(),
            "oldestCursor": format!("c{}", end),
            "newestCursor": format!("c{}", offset),
            "chats": beeper_chats()
        }),
    )
}

fn handle_connection(
    mut stream: std::net::TcpStream,
    requests: &Mutex<Vec<RequestRecord>>,
    messages: &Mutex<Option<Vec<serde_json::Value>>>,
) {
    stream.set_read_timeout(Some(Duration::from_secs(5))).ok();
    let reader_stream = match stream.try_clone() {
        Ok(s) => s,
        Err(_) => return,
    };
    let mut reader = BufReader::new(reader_stream);

    let mut request_line = String::new();
    if reader.read_line(&mut request_line).is_err() {
        return;
    }
    let parts: Vec<&str> = request_line.trim().split_whitespace().collect();
    if parts.len() < 2 {
        return;
    }
    let method = parts[0].to_string();
    let full_path = parts[1];
    let (path, query) = if let Some(q_pos) = full_path.find('?') {
        (
            full_path[..q_pos].to_string(),
            parse_query(&full_path[q_pos + 1..]),
        )
    } else {
        (full_path.to_string(), HashMap::new())
    };

    let mut auth = String::new();
    loop {
        let mut line = String::new();
        if reader.read_line(&mut line).is_err() || line.trim().is_empty() {
            break;
        }
        let lower = line.to_lowercase();
        if lower.starts_with("authorization:") {
            auth = line["authorization:".len()..].trim().to_string();
        }
    }

    requests
        .lock()
        .unwrap()
        .push((method.clone(), path.clone(), auth.clone(), query.clone()));

    let (status, body) = if method != "GET" {
        (405, serde_json::json!({"message": "method not allowed"}))
    } else if auth != format!("Bearer {}", FAKE_BEEPER_TOKEN) {
        (
            401,
            serde_json::json!({"message": "Unauthorized", "code": "unauthorized"}),
        )
    } else if path == "/v1/accounts" {
        (200, beeper_accounts())
    } else if path == "/v1/messages/search" {
        beeper_page(&query, messages)
    } else {
        (404, serde_json::json!({"message": "not found"}))
    };

    let body_bytes = serde_json::to_vec(&body).unwrap_or_default();
    let response = format!(
        "HTTP/1.1 {} OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
        status,
        body_bytes.len()
    );
    let _ = stream.write_all(response.as_bytes());
    let _ = stream.write_all(&body_bytes);
    let _ = stream.flush();
}

impl StandInBeeper {
    fn new() -> Result<Self, E2EFailure> {
        let listener = TcpListener::bind("127.0.0.1:0")
            .map_err(|e| E2EFailure(format!("cannot bind: {}", e)))?;
        let port = listener
            .local_addr()
            .map_err(|e| E2EFailure(format!("no addr: {}", e)))?
            .port();
        if port == REAL_BEEPER_PORT {
            fail!(
                "the stand-in Beeper got port {}, the real Beeper's",
                REAL_BEEPER_PORT
            );
        }
        listener
            .set_nonblocking(true)
            .map_err(|e| E2EFailure(format!("nonblocking: {}", e)))?;

        let requests = Arc::new(Mutex::new(Vec::new()));
        let messages: Arc<Mutex<Option<Vec<serde_json::Value>>>> = Arc::new(Mutex::new(None));
        let shutdown = Arc::new(AtomicBool::new(false));

        let r = requests.clone();
        let m = messages.clone();
        let sd = shutdown.clone();
        let thread = thread::spawn(move || {
            while !sd.load(Ordering::Relaxed) {
                match listener.accept() {
                    Ok((stream, _)) => {
                        let r = r.clone();
                        let m = m.clone();
                        thread::spawn(move || handle_connection(stream, &r, &m));
                    }
                    Err(ref e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                        thread::sleep(Duration::from_millis(10));
                    }
                    Err(_) => break,
                }
            }
        });

        Ok(Self {
            port,
            requests,
            shutdown,
            thread: Some(thread),
        })
    }

    fn url(&self) -> String {
        format!("http://localhost:{}", self.port)
    }

    fn seen(&self) -> Vec<RequestRecord> {
        self.requests.lock().unwrap().clone()
    }

    fn searches(&self) -> Vec<RequestRecord> {
        self.seen()
            .into_iter()
            .filter(|(_, p, _, _)| p == "/v1/messages/search")
            .collect()
    }

    fn polls(&self) -> Vec<RequestRecord> {
        self.searches()
            .into_iter()
            .filter(|(_, _, _, q)| !q.contains_key("cursor"))
            .collect()
    }

    fn stop(&mut self) {
        self.shutdown.store(true, Ordering::Relaxed);
        if let Some(t) = self.thread.take() {
            let _ = t.join();
        }
    }
}

impl Drop for StandInBeeper {
    fn drop(&mut self) {
        self.stop();
    }
}

// ── run_with_monitor ────────────────────────────────────────────────────

fn run_with_monitor(
    manifest: &CValue,
    program: &str,
    errors: &Path,
    status: &Path,
    name: &str,
    until_fn: &dyn Fn() -> bool,
    never_fn: &dyn Fn() -> String,
) -> Result<Vec<String>, E2EFailure> {
    let started_in = TempDir::new("vitruvian-monitor-").map_err(|e| E2EFailure(e.to_string()))?;
    let mut said = Vec::new();

    let shell_cmd = vec![
        "/bin/sh".to_string(),
        "-c".to_string(),
        "exec \"$0\" 2>>\"$1\"".to_string(),
        program.to_string(),
        errors.to_string_lossy().to_string(),
    ];
    let link = Link::spawn(&shell_cmd, started_in.path())
        .map_err(|e| E2EFailure(format!("{}: cannot start: {}", name, e)))?;
    let mut run = Run::new(
        link,
        manifest,
        started_in.path().to_string_lossy().to_string(),
        Run::<Link>::default_features(),
    );

    match run.handshake() {
        Ok(h) => said.push(format!("{}: handshake: {}", name, h)),
        Err(f) => fail!("{}: handshake: {}; {}", name, f.0, stderr_of(errors)),
    }

    let started = Instant::now();
    while !until_fn() {
        if started.elapsed() > Duration::from_secs(POLLS_WITHIN_SECONDS) {
            fail!("{}: {}; {}", name, never_fn(), stderr_of(errors));
        }
        thread::sleep(Duration::from_millis(250));
    }
    let waited = started.elapsed();
    thread::sleep(Duration::from_secs(SETTLE_SECONDS));

    {
        let mut app = Driver::new(&mut run);
        match app.open("settings") {
            Ok(_) => {}
            Err(e) => fail!("{}: {}; {}", name, e.0, stderr_of(errors)),
        }
    }
    said.push(format!(
        "{}: still running and answering {:.0} s after it started",
        name,
        waited.as_secs_f64() + SETTLE_SECONDS as f64
    ));

    if !status.exists() {
        fail!(
            "{}: {} was not written: the chat monitor never started, so this run proves nothing; {}",
            name,
            status.display(),
            stderr_of(errors)
        );
    }
    let status_text = fs::read_to_string(status)
        .map_err(|e| E2EFailure(format!("cannot read {}: {}", status.display(), e)))?;
    let status_json: serde_json::Value = serde_json::from_str(&status_text)
        .map_err(|e| E2EFailure(format!("cannot parse {}: {}", status.display(), e)))?;
    said.push(format!(
        "{}: the monitor's status: {}",
        name,
        serde_json::to_string(&status_json).unwrap_or_default()
    ));

    run.link.send(&close_notice("settings")).map_err(wrap)?;
    match run.shutdown() {
        Ok(sd) => said.push(format!("{}: shutdown: {}", name, sd)),
        Err(f) => fail!("{}: shutdown: {}; {}", name, f.0, stderr_of(errors)),
    }

    drop(run);
    let se = stderr_of(errors);
    if se.contains(FATAL) {
        fail!("{}: {}", name, se);
    }
    Ok(said)
}

// ── monitor_starts ──────────────────────────────────────────────────────

fn monitor_starts(folder: &Path, scratch: &Path) -> Result<Vec<String>, E2EFailure> {
    let base = scratch.join("monitor");
    let home = base.join("home");
    let data = base.join("data");
    let gemini = home.join(".gemini");
    fs::create_dir_all(&gemini)
        .map_err(|e| E2EFailure(format!("cannot create {}: {}", gemini.display(), e)))?;
    fs::create_dir_all(&data)
        .map_err(|e| E2EFailure(format!("cannot create {}: {}", data.display(), e)))?;

    let mut beeper = StandInBeeper::new()?;

    let mut env: HashMap<String, String> = std::env::vars().collect();
    env.insert("HOME".into(), home.to_string_lossy().to_string());
    env.insert(
        "CFFIXED_USER_HOME".into(),
        home.to_string_lossy().to_string(),
    );
    env.insert(
        "HOMESPEAKER_DATA_FOLDER".into(),
        data.to_string_lossy().to_string(),
    );
    env.insert("HOMESPEAKER_PROGRAM".into(), String::new());
    env.insert("HOMESPEAKER_MESSAGE_PREFIX".into(), unique_prefix());
    env.insert(
        "SWIFT_IS_CURRENT_EXECUTOR_LEGACY_MODE_OVERRIDE".into(),
        "legacy".into(),
    );
    env.insert("HOMESPEAKER_BEEPER_URL".into(), beeper.url());

    if env
        .get("HOMESPEAKER_BEEPER_URL")
        .map(|u| u.contains(&format!(":{}", REAL_BEEPER_PORT)))
        .unwrap_or(false)
    {
        fail!("HOMESPEAKER_BEEPER_URL names the real Beeper's port");
    }

    let settings_json = serde_json::json!({
        "enabled": false,
        "default_target": "",
        "structure_id": "",
        "targets": {},
        "chat_monitor": {
            "slack_enabled": true,
            "beeper_enabled": true,
            "poll_interval_seconds": 5
        }
    });
    fs::write(
        data.join("settings.json"),
        serde_json::to_string(&settings_json).unwrap(),
    )
    .map_err(|e| E2EFailure(format!("cannot write settings.json: {}", e)))?;

    let secrets_path = data.join("secrets.json");
    let secrets_json = serde_json::json!({"beeperToken": FAKE_BEEPER_TOKEN});
    fs::write(&secrets_path, serde_json::to_string(&secrets_json).unwrap())
        .map_err(|e| E2EFailure(format!("cannot write secrets.json: {}", e)))?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = fs::set_permissions(&secrets_path, fs::Permissions::from_mode(0o600));
    }

    let door_json = serde_json::json!({
        "version": 1,
        "chosen": "extension",
        "chosen_at": iso_now_minus(3600),
        "chosen_by": "conformance test"
    });
    fs::write(
        gemini.join(DOOR_FILE),
        serde_json::to_string(&door_json).unwrap(),
    )
    .map_err(|e| E2EFailure(format!("cannot write {}: {}", DOOR_FILE, e)))?;

    let manifest_path = folder.join("vitruvian-tool.json");
    let manifest_text = fs::read_to_string(&manifest_path)
        .map_err(|e| E2EFailure(format!("cannot read {}: {}", manifest_path.display(), e)))?;
    let manifest = cjson::loads(&manifest_text)
        .map_err(|e| E2EFailure(format!("cannot parse {}: {}", manifest_path.display(), e)))?;
    let exec = manifest
        .get("runtime")
        .and_then(|r| r.get("exec"))
        .and_then(|e| e.as_str())
        .ok_or_else(|| E2EFailure("manifest has no runtime.exec".into()))?;
    let program = folder.join(exec);
    let program_str = program.to_string_lossy().to_string();
    let status = data.join("speaker_monitor_status.json");
    let errors = base.join("stderr.txt");
    let mut said = Vec::new();

    for (key, value) in &env {
        std::env::set_var(key, value);
    }

    // With the stand-in Beeper running
    said.extend(run_with_monitor(
        &manifest,
        &program_str,
        &errors,
        &status,
        "with the stand-in Beeper",
        &|| beeper.polls().len() >= 2,
        &|| {
            format!(
                "the monitor never polled the stand-in Beeper twice in {} s; it was asked {:?}",
                POLLS_WITHIN_SECONDS,
                beeper
                    .seen()
                    .iter()
                    .map(|(m, p, _, _)| (m.as_str(), p.as_str()))
                    .collect::<Vec<_>>()
            )
        },
    )?);
    {
        let status_text = fs::read_to_string(&status)
            .map_err(|e| E2EFailure(format!("cannot read {}: {}", status.display(), e)))?;
        let written: serde_json::Value = serde_json::from_str(&status_text)
            .map_err(|e| E2EFailure(format!("cannot parse {}: {}", status.display(), e)))?;
        if written.get("is_running").and_then(|v| v.as_bool()) != Some(true) {
            fail!("the monitor's status does not say it runs: {:?}", written);
        }
        let beeper_reads = serde_json::json!(["Google Messages", "Signal", "WhatsApp"]);
        if written.get("beeper_networks") != Some(&beeper_reads) {
            fail!(
                "the monitor reads Beeper's {:?}, not {:?}",
                written.get("beeper_networks"),
                beeper_reads
            );
        }
        let beeper_skips = serde_json::json!(["Slack"]);
        if written.get("beeper_skipped_networks") != Some(&beeper_skips) {
            fail!(
                "the monitor skips Beeper's {:?}, not {:?}",
                written.get("beeper_skipped_networks"),
                beeper_skips
            );
        }
    }
    let asked = beeper.seen();
    let wrong: Vec<&RequestRecord> = asked
        .iter()
        .filter(|(m, _, auth, _)| m != "GET" || auth != &format!("Bearer {}", FAKE_BEEPER_TOKEN))
        .collect();
    if !wrong.is_empty() {
        fail!(
            "the stand-in Beeper was asked with another method or without the made-up token: {:?}",
            wrong
                .iter()
                .map(|(m, p, _, _)| (m.as_str(), p.as_str()))
                .collect::<Vec<_>>()
        );
    }
    let searches = beeper.searches();
    if searches
        .iter()
        .any(|(_, _, _, q)| q.get("limit").map(|l| l.as_str()) != Some(&BEEPER_PAGE.to_string()))
    {
        fail!(
            "a search asked for more than {}: {:?}",
            BEEPER_PAGE,
            searches.iter().map(|(_, _, _, q)| q).collect::<Vec<_>>()
        );
    }
    let paged: Vec<&RequestRecord> = searches
        .iter()
        .filter(|(_, _, _, q)| q.contains_key("cursor"))
        .collect();
    if paged.len() < 2 {
        fail!(
            "the monitor did not page through the stand-in's 51 messages: {:?}",
            searches.iter().map(|(_, _, _, q)| q).collect::<Vec<_>>()
        );
    }
    said.push(format!(
        "the stand-in Beeper was asked {} times, every time a GET with the made-up token: {:?}; {} polls, {} further pages by cursor; plain HTTP to localhost is allowed",
        asked.len(),
        asked.iter().map(|(_, p, _, _)| p.as_str()).collect::<std::collections::BTreeSet<_>>(),
        beeper.polls().len(),
        paged.len()
    ));
    beeper.stop();

    // With Beeper not running
    let says_not_running = || -> bool {
        fs::read_to_string(&status)
            .ok()
            .and_then(|s| serde_json::from_str::<serde_json::Value>(&s).ok())
            .and_then(|v| {
                v.get("last_error")?
                    .as_str()
                    .map(|s| s.contains(NOT_RUNNING))
            })
            .unwrap_or(false)
    };
    let _ = fs::remove_file(&status);
    said.extend(run_with_monitor(
        &manifest,
        &program_str,
        &errors,
        &status,
        "with Beeper not running",
        &says_not_running,
        &|| {
            format!(
                "the monitor's status never said {:?} with the stand-in stopped",
                NOT_RUNNING
            )
        },
    )?);
    {
        let status_text = fs::read_to_string(&status)
            .map_err(|e| E2EFailure(format!("cannot read {}: {}", status.display(), e)))?;
        let written: serde_json::Value = serde_json::from_str(&status_text)
            .map_err(|e| E2EFailure(format!("cannot parse {}: {}", status.display(), e)))?;
        if written.get("is_running").and_then(|v| v.as_bool()) != Some(true) {
            fail!(
                "with Beeper not running, the monitor did not run: {:?}",
                written
            );
        }
        said.push(format!(
            "with Beeper not running: {}",
            written
                .get("last_error")
                .and_then(|v| v.as_str())
                .unwrap_or("")
        ));
    }

    // The Stop hook
    let hook_started_in = TempDir::new("vitruvian-hook-").map_err(|e| E2EFailure(e.to_string()))?;
    let transcript = base.join("transcript.jsonl");
    let transcript_content = serde_json::json!({
        "type": "assistant",
        "message": {
            "role": "assistant",
            "content": [{"type": "text", "text": format!("test {}: done.", unique_prefix())}]
        }
    });
    fs::write(
        &transcript,
        serde_json::to_string(&transcript_content).unwrap() + "\n",
    )
    .map_err(|e| E2EFailure(format!("cannot write transcript: {}", e)))?;

    let hook_input = serde_json::json!({"transcript_path": transcript.to_string_lossy()});
    let started = Instant::now();
    let done = Command::new(&program)
        .arg("--claude-stop-hook")
        .envs(&env)
        .current_dir(hook_started_in.path())
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::piped())
        .spawn()
        .map_err(|e| E2EFailure(format!("--claude-stop-hook: cannot run: {}", e)))?;

    let mut child = done;
    if let Some(mut stdin) = child.stdin.take() {
        let _ = stdin.write_all(serde_json::to_string(&hook_input).unwrap().as_bytes());
    }
    let output = child
        .wait_with_output()
        .map_err(|e| E2EFailure(format!("--claude-stop-hook: wait failed: {}", e)))?;
    let took = started.elapsed().as_secs_f64();

    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr_text = String::from_utf8_lossy(&output.stderr);
    if !output.status.success() || stdout.trim() != "{}" || stderr_text.contains(FATAL) {
        fail!(
            "--claude-stop-hook exited {}: {:?} {:?}",
            output.status.code().unwrap_or(-1),
            stdout.as_ref(),
            stderr_text.as_ref()
        );
    }
    if took >= (HOOK_BACKSTOP_SECONDS - 1) as f64 {
        fail!(
            "--claude-stop-hook took {:.1} s: it ran into its {} s backstop instead of finishing",
            took,
            HOOK_BACKSTOP_SECONDS
        );
    }
    said.push(format!(
        "--claude-stop-hook: {{}} and exit 0 in {:.1} s",
        took
    ));
    Ok(said)
}

// ── Main test ───────────────────────────────────────────────────────────

#[test]
fn conformance_test() {
    let manifest_path = resolve_env("MANIFEST_PATH");
    let conformance_bin = resolve_env("CONFORMANCE_BIN");
    let validate_bin = resolve_env("VALIDATE_BIN");

    let built = manifest_path.parent().expect("MANIFEST_PATH has no parent");

    let scratch_dir = TempDir::new("vitruvian-hs-conformance-").expect("cannot create scratch dir");
    let scratch = scratch_dir.path();

    let folder = scratch.join("homespeaker");
    copy_dir_deref(built, &folder).expect("cannot copy built folder");

    let home = scratch.join("home");
    fs::create_dir_all(&home).expect("cannot create home");
    for marker in AGENT_MARKERS {
        fs::create_dir_all(home.join(marker)).expect("cannot create agent marker");
    }
    let data = scratch.join("data");

    let mut env: HashMap<String, String> = std::env::vars().collect();
    env.insert("HOME".into(), home.to_string_lossy().to_string());
    env.insert(
        "CFFIXED_USER_HOME".into(),
        home.to_string_lossy().to_string(),
    );
    env.insert(
        "HOMESPEAKER_DATA_FOLDER".into(),
        data.to_string_lossy().to_string(),
    );
    env.insert("HOMESPEAKER_PROGRAM".into(), String::new());
    env.insert("HOMESPEAKER_MESSAGE_PREFIX".into(), unique_prefix());

    let program = folder.join("bin").join("tool");
    let validate_abs = fs::canonicalize(&validate_bin).unwrap_or_else(|_| validate_bin.clone());
    let conformance_abs =
        fs::canonicalize(&conformance_bin).unwrap_or_else(|_| conformance_bin.clone());

    // where check
    match where_check(&program, &data, &env) {
        Ok(msg) => println!("--- where: {}", msg),
        Err(e) => panic!("--- where: NOT OK: {}", e),
    }

    // validate and conformance
    let mut failed = 0;
    let checks: Vec<(&str, Vec<String>)> = vec![
        (
            "validate",
            vec![
                validate_abs.to_string_lossy().to_string(),
                "validate".into(),
                folder.to_string_lossy().to_string(),
            ],
        ),
        (
            "conformance",
            vec![
                conformance_abs.to_string_lossy().to_string(),
                folder.to_string_lossy().to_string(),
            ],
        ),
    ];
    for (name, args) in &checks {
        let done = Command::new(&args[0])
            .args(&args[1..])
            .envs(&env)
            .output()
            .unwrap_or_else(|e| panic!("{}: cannot run: {}", name, e));
        let stdout = String::from_utf8_lossy(&done.stdout);
        let stderr = String::from_utf8_lossy(&done.stderr);
        println!(
            "--- {}: exit {}\n{}{}",
            name,
            done.status.code().unwrap_or(-1),
            stdout,
            stderr
        );
        if !done.status.success() {
            failed += 1;
        }
        if *name == "conformance" && !stdout.contains(NOT_SET_UP) {
            println!(
                "the sayClipboard command was not refused as not set up: \
                 the program found something to speak on"
            );
            failed += 1;
        }
    }
    if failed > 0 {
        panic!("{} of 2 checks failed", failed);
    }

    // end to end
    match end_to_end(&folder, &data, &env) {
        Ok(said) => println!("--- end to end: ok\n{}", said.join("\n")),
        Err(e) => panic!("--- end to end: NOT OK: {}", e),
    }

    // nothing outside
    match nothing_outside(&home, scratch) {
        Ok(msg) => println!("--- the app's files: {}", msg),
        Err(e) => panic!("--- the app's files: NOT OK: {}", e),
    }

    // monitor starts
    match monitor_starts(&folder, scratch) {
        Ok(said) => println!("--- the chat monitor starting: ok\n{}", said.join("\n")),
        Err(e) => panic!("--- the chat monitor starting: NOT OK: {}", e),
    }

    println!(
        "the built HomeSpeaker tool validates, passes the conformance script, \
         draws and saves its pages end to end, keeps to its scratch folder, \
         and stays up when its chat monitor starts"
    );
}

// ── Unit tests for helpers ──────────────────────────────────────────────

#[test]
fn test_add_offset_to_iso() {
    let base = "2026-10-25T12:00:00.000Z";
    assert_eq!(add_offset_to_iso(base, 0.01), "2026-10-25T12:00:00.010Z");
    assert_eq!(add_offset_to_iso(base, 0.5), "2026-10-25T12:00:00.500Z");
    assert_eq!(add_offset_to_iso(base, 0.74), "2026-10-25T12:00:00.740Z");
    let base2 = "2026-10-25T12:59:59.500Z";
    assert_eq!(add_offset_to_iso(base2, 0.6), "2026-10-25T13:00:00.100Z");
}

#[test]
fn test_parse_query() {
    let qs = "limit=20&dateAfter=2026-10-25T12%3A00%3A00.000Z&cursor=c20&direction=before";
    let parsed = parse_query(qs);
    assert_eq!(parsed.get("limit").map(|s| s.as_str()), Some("20"));
    assert_eq!(
        parsed.get("dateAfter").map(|s| s.as_str()),
        Some("2026-10-25T12:00:00.000Z")
    );
    assert_eq!(parsed.get("cursor").map(|s| s.as_str()), Some("c20"));
    assert_eq!(parsed.get("direction").map(|s| s.as_str()), Some("before"));
}

#[test]
fn test_beeper_messages_count() {
    let msgs = beeper_messages("2026-10-25T12:00:00.000Z");
    assert_eq!(msgs.len(), 51);
}

#[test]
fn test_words_extraction() {
    let tree = CValue::Obj(vec![
        ("type".into(), s("heading")),
        ("text".into(), s("Hello World")),
    ]);
    let w = words(&tree);
    assert!(w.contains(&"heading".to_string()));
    assert!(w.contains(&"Hello World".to_string()));
}

#[test]
fn test_says_check() {
    let tree = CValue::Obj(vec![(
        "blocks".into(),
        CValue::Arr(vec![CValue::Obj(vec![
            ("type".into(), s("text")),
            ("text".into(), s("contains HH:mm format")),
        ])]),
    )]);
    assert!(says(&tree, "HH:mm"));
    assert!(!says(&tree, "missing"));
}

#[test]
fn test_block_lookup() {
    let tree = CValue::Obj(vec![(
        "blocks".into(),
        CValue::Arr(vec![
            CValue::Obj(vec![
                ("id".into(), s("alpha")),
                ("type".into(), s("switch")),
            ]),
            CValue::Obj(vec![("id".into(), s("beta")), ("type".into(), s("button"))]),
        ]),
    )]);
    assert!(block(&tree, "alpha").is_some());
    assert!(block(&tree, "beta").is_some());
    assert!(block(&tree, "gamma").is_none());
}

#[test]
fn test_days_to_ymd() {
    assert_eq!(days_to_ymd(0), (1970, 1, 1));
    assert_eq!(days_to_ymd(365), (1971, 1, 1));
    assert_eq!(days_to_ymd(730), (1972, 1, 1));
}
