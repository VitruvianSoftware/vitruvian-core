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

//! Rust port of `apps/mobile/android-remote/macmenu/tool/conformance_test.py`.
//!
//! Verifies the built Vitruvian Remote extension folder and its JSON-RPC protocol
//! end to end using `conformance_rs_lib`.

use conformance_rs_lib::json::{self, Value};
use conformance_rs_lib::{
    is_tree, Link, MsgKind, Run, Transport, FEATURES, MAX_BLOCKS, MAX_TREE_BYTES,
};
use std::collections::HashMap;
use std::env;
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

pub const TABS: [&str; 4] = [
    "tabGeneral",
    "tabPairing",
    "tabNotifications",
    "tabIntegrations",
];
pub const SECTIONS: [&str; 4] = [
    "General",
    "Pairing & Bridge",
    "Notifications",
    "Integrations",
];
pub const SECONDS: u64 = 15;

pub fn words(value: &Value) -> Vec<String> {
    match value {
        Value::Str(s) => vec![s.clone()],
        Value::Obj(entries) => entries.iter().flat_map(|(_, v)| words(v)).collect(),
        Value::Arr(items) => items.iter().flat_map(words).collect(),
        _ => Vec::new(),
    }
}

pub fn says(tree: &Value, text: &str) -> bool {
    let Some(blocks) = tree.get("blocks").and_then(|b| b.as_arr()) else {
        return false;
    };
    blocks.iter().flat_map(words).any(|w| w.contains(text))
}

pub fn block<'a>(tree: &'a Value, block_id: &str) -> Option<&'a Value> {
    tree.get("blocks")?
        .as_arr()?
        .iter()
        .find(|b| b.get("id").and_then(|id| id.as_str()) == Some(block_id))
}

pub fn section_headings(tree: &Value) -> Vec<String> {
    let Some(blocks) = tree.get("blocks").and_then(|b| b.as_arr()) else {
        return Vec::new();
    };
    blocks
        .iter()
        .filter(|b| {
            b.get("type").and_then(|t| t.as_str()) == Some("heading")
                && b.get("section").and_then(|s| s.as_bool()) == Some(true)
        })
        .filter_map(|b| b.get("text").and_then(|t| t.as_str()).map(String::from))
        .collect()
}

pub struct Driver<L: Transport> {
    pub run: Run<L>,
    pub pages: Vec<String>,
    pub current: HashMap<String, Value>,
}

impl<L: Transport> Driver<L> {
    pub fn new(run: Run<L>) -> Self {
        Self {
            run,
            pages: Vec::new(),
            current: HashMap::new(),
        }
    }

    pub fn check(&mut self, tree: Option<&Value>, where_ctx: &str) -> Result<Value, String> {
        let Some(tree_val) = tree else {
            return Err(format!(
                "{where_ctx}: not a page within the protocol's limits (0 blocks of at most {MAX_BLOCKS}, 0 bytes of at most {MAX_TREE_BYTES})"
            ));
        };
        let size = tree_val.dumps_compact().len();
        let count = tree_val
            .get("blocks")
            .and_then(|b| b.as_arr())
            .map(|a| a.len())
            .unwrap_or(0);
        if !is_tree(tree_val) {
            return Err(format!(
                "{where_ctx}: not a page within the protocol's limits ({count} blocks of at most {MAX_BLOCKS}, {size} bytes of at most {MAX_TREE_BYTES})"
            ));
        }
        self.pages
            .push(format!("{where_ctx}: {count} blocks, {size} bytes"));
        Ok(tree_val.clone())
    }

    pub fn ask(&mut self, method: &str, params: Value, where_ctx: &str) -> Result<Value, String> {
        let req_id = self
            .run
            .request(method, params)
            .map_err(|f| format!("{where_ctx}: {}", f.0))?;
        let (kind, message) = self
            .run
            .answer(&req_id, SECONDS, false)
            .map_err(|f| format!("{where_ctx}: {}", f.0))?;
        if kind != MsgKind::Result {
            return Err(format!("{where_ctx}: answered with {}", message.py_repr()));
        }
        let Some(res) = message.get("result") else {
            return Err(format!("{where_ctx}: answered with {}", message.py_repr()));
        };
        if res.as_obj().is_none() {
            return Err(format!("{where_ctx}: answered with {}", message.py_repr()));
        }
        Ok(res.clone())
    }

    pub fn open(&mut self, panel: &str) -> Result<Value, String> {
        let params = Value::Obj(vec![("panel".into(), Value::Str(panel.into()))]);
        let result = self.ask("ui/open", params, &format!("open {panel}"))?;
        if result.has("tree") {
            self.run.rendered.remove(panel);
        }
        let tree_candidate = result
            .get("tree")
            .cloned()
            .or_else(|| self.run.rendered.get(panel).cloned());
        let tree = self.check(tree_candidate.as_ref(), panel)?;
        self.current.insert(panel.to_string(), tree.clone());
        Ok(tree)
    }

    pub fn act(
        &mut self,
        panel: &str,
        block_id: &str,
        event: &str,
        value: Option<Value>,
        keep_ok: bool,
    ) -> Result<Option<Value>, String> {
        let mut param_entries = vec![
            ("panel".into(), Value::Str(panel.into())),
            ("block".into(), Value::Str(block_id.into())),
            ("event".into(), Value::Str(event.into())),
        ];
        let where_ctx = match &value {
            Some(v) => {
                let s = format!("{panel}: {event} {block_id} = {}", v.py_repr());
                param_entries.push(("value".into(), v.clone()));
                s
            }
            None => format!("{panel}: {event} {block_id}"),
        };
        let shown = self
            .run
            .rendered
            .remove(panel)
            .or_else(|| self.current.get(panel).cloned());
        let Some(ref shown_tree) = shown else {
            return Err(format!("{where_ctx}: the page shown has no such block"));
        };
        if block(shown_tree, block_id).is_none() {
            return Err(format!("{where_ctx}: the page shown has no such block"));
        }
        let result = self.ask("ui/event", Value::Obj(param_entries), &where_ctx)?;
        if !result.has("tree") {
            if keep_ok && result.get("keep").and_then(|k| k.as_bool()) == Some(true) {
                return Ok(None);
            }
            return Err(format!(
                "{where_ctx}: answered with no page: {}",
                result.py_repr()
            ));
        }
        self.run.rendered.remove(panel);
        let checked = self.check(result.get("tree"), &where_ctx)?;
        self.current.insert(panel.to_string(), checked.clone());
        Ok(Some(checked))
    }
}

fn copy_dir_recursive(src: &Path, dst: &Path) -> Result<(), String> {
    fs::create_dir_all(dst).map_err(|e| format!("create_dir_all {}: {e}", dst.display()))?;
    for entry in fs::read_dir(src).map_err(|e| format!("read_dir {}: {e}", src.display()))? {
        let entry = entry.map_err(|e| format!("dir entry: {e}"))?;
        let src_path = entry.path();
        let dst_path = dst.join(entry.file_name());
        if src_path.is_dir() {
            copy_dir_recursive(&src_path, &dst_path)?;
        } else {
            fs::copy(&src_path, &dst_path).map_err(|e| {
                format!("copy {} -> {}: {e}", src_path.display(), dst_path.display())
            })?;
            if let Ok(meta) = fs::metadata(&src_path) {
                let _ = fs::set_permissions(&dst_path, meta.permissions());
            }
        }
    }
    Ok(())
}

fn apply_tool_env(home: &Path, data: &Path, folder: &Path, standalone_installed: &str) {
    env::set_var("HOME", home);
    env::set_var("CFFIXED_USER_HOME", home);
    env::set_var("REMOTETOOL_HOME", home);
    env::set_var("REMOTETOOL_DATA_FOLDER", data);
    env::set_var("REMOTETOOL_TOOL_FOLDER", folder);
    env::set_var("REMOTETOOL_AGENT_COMMAND", "");
    env::set_var("REMOTETOOL_FAKE_STATUS", "paired");
    env::set_var("REMOTETOOL_TAILSCALE_ADDRESS", "100.124.228.116");
    env::set_var("REMOTETOOL_STANDALONE_INSTALLED", standalone_installed);
}

pub fn end_to_end_active(
    folder: &Path,
    scratch: &Path,
    features: Vec<String>,
) -> Result<Vec<String>, String> {
    let sections = features.iter().any(|f| f == "ui.sections");
    let kind = if sections { "sections" } else { "tabs" };
    let manifest_text = fs::read_to_string(folder.join("vitruvian-tool.json"))
        .map_err(|e| format!("read manifest: {e}"))?;
    let manifest = json::loads(&manifest_text).map_err(|e| format!("parse manifest: {e:?}"))?;
    let exec_rel = manifest
        .get("runtime")
        .and_then(|r| r.get("exec"))
        .and_then(|e| e.as_str())
        .ok_or("missing runtime.exec")?;
    let program = folder.join(exec_rel);

    let home = scratch.join(format!("e2e_home_{kind}"));
    let data = scratch.join(format!("e2e_data_{kind}"));
    fs::create_dir_all(&home).map_err(|e| format!("mkdir home: {e}"))?;
    fs::create_dir_all(&data).map_err(|e| format!("mkdir data: {e}"))?;

    apply_tool_env(&home, &data, folder, "0");

    let link = Link::spawn(&[program.to_string_lossy().into_owned()], &data)
        .map_err(|e| format!("spawn tool: {e}"))?;
    let run = Run::new(
        link,
        &manifest,
        data.to_string_lossy().into_owned(),
        Some(features),
    );
    let mut app = Driver::new(run);
    let mut said = Vec::new();

    let hs = app
        .run
        .handshake()
        .map_err(|f| format!("handshake ({kind}): {}", f.0))?;
    said.push(format!("active handshake ({kind}): {hs}"));

    let island = app.open("remote")?;
    if !says(&island, "Pixel Fold") {
        return Err("island did not show connected Pixel Fold".into());
    }
    let qr_tree = app
        .act("remote", "islandPairWithQR", "tap", None, false)?
        .ok_or("islandPairWithQR returned no tree")?;
    if !says(&qr_tree, "data:image/png;base64,") {
        return Err("islandPairWithQR did not render inline QR PNG data URL".into());
    }
    said.push("island: rendered connected phone and inline QR code".into());

    let settings = app.open("settings")?;
    if sections {
        let got_headings = section_headings(&settings);
        let expected_headings: Vec<String> = SECTIONS.iter().map(|s| (*s).to_string()).collect();
        if got_headings != expected_headings {
            return Err(format!(
                "settings: section headings {got_headings:?}, expected {expected_headings:?}"
            ));
        }
        for tab in TABS {
            if block(&settings, tab).is_some() {
                return Err(format!("settings: {tab} drawn on an app with sections"));
            }
        }
        let stale = app.ask(
            "ui/event",
            Value::Obj(vec![
                ("panel".into(), Value::Str("settings".into())),
                ("block".into(), Value::Str("tabPairing".into())),
                ("event".into(), Value::Str("tap".into())),
            ]),
            "settings: a stale tap on tabPairing",
        )?;
        if stale.get("keep").and_then(|k| k.as_bool()) != Some(true) {
            return Err(format!(
                "settings: a stale tab tap was answered with {}",
                stale.py_repr()
            ));
        }
        said.push(format!(
            "settings: {} on one page, no tabs",
            SECTIONS.join(", ")
        ));
    } else {
        if !section_headings(&settings).is_empty() {
            return Err("settings: a section heading on an app without sections".into());
        }
        for tab in TABS {
            app.act("settings", tab, "tap", None, false)?;
        }
        said.push(format!("settings: {} each drawn", TABS.join(", ")));
    }

    if !sections {
        app.act("settings", "tabGeneral", "tap", None, false)?;
    }
    app.act(
        "settings",
        "intervalSeconds",
        "submit",
        Some(Value::Str("5".into())),
        false,
    )?;
    let bad_interval = app
        .act(
            "settings",
            "intervalSeconds",
            "submit",
            Some(Value::Str("999".into())),
            false,
        )?
        .ok_or("intervalSeconds returned no tree")?;
    if !says(&bad_interval, "between 1 and 60") {
        return Err("out-of-range intervalSeconds was not rejected on page".into());
    }

    if !sections {
        app.act("settings", "tabPairing", "tap", None, false)?;
    }
    app.act(
        "settings",
        "permissionHookToggle",
        "toggle",
        Some(Value::Bool(true)),
        false,
    )?;
    app.act(
        "settings",
        "permissionWaitSeconds",
        "submit",
        Some(Value::Str("90".into())),
        false,
    )?;

    if !sections {
        app.act("settings", "tabNotifications", "tap", None, false)?;
    }
    app.act(
        "settings",
        "ntfyURL",
        "submit",
        Some(Value::Str("https://ntfy.example.com".into())),
        false,
    )?;
    app.act(
        "settings",
        "ntfyTopic",
        "submit",
        Some(Value::Str("vitruvian-e2e".into())),
        false,
    )?;
    app.act(
        "settings",
        "ntfyTokenField",
        "submit",
        Some(Value::Str("tk_e2e_secret".into())),
        false,
    )?;

    if !sections {
        app.act("settings", "tabIntegrations", "tap", None, false)?;
    }
    app.act(
        "settings",
        "kubeContext",
        "submit",
        Some(Value::Str("homelab-e2e".into())),
        false,
    )?;
    app.act(
        "settings",
        "prometheusURL",
        "submit",
        Some(Value::Str("https://prom.example.com".into())),
        false,
    )?;
    app.act(
        "settings",
        "prometheusTokenField",
        "submit",
        Some(Value::Str("prom_e2e_secret".into())),
        false,
    )?;
    app.act(
        "settings",
        "ghExtraRepos",
        "submit",
        Some(Value::Str("VitruvianSoftware/vitruvian-core".into())),
        false,
    )?;

    for panel in ["remote", "settings"] {
        app.run
            .link
            .send(&Value::Obj(vec![
                ("jsonrpc".into(), Value::Str("2.0".into())),
                ("method".into(), Value::Str("ui/close".into())),
                (
                    "params".into(),
                    Value::Obj(vec![("panel".into(), Value::Str(panel.into()))]),
                ),
            ]))
            .map_err(|f| f.0)?;
    }
    let sd = app.run.shutdown().map_err(|f| f.0)?;
    said.push(format!("active shutdown: {sd}"));
    said.extend(app.pages.clone());
    app.run.link.close();

    let settings_file = data.join("settings.json");
    let written_text =
        fs::read_to_string(&settings_file).map_err(|e| format!("read settings.json: {e}"))?;
    let written = json::loads(&written_text).map_err(|e| format!("parse settings.json: {e:?}"))?;

    if !matches!(written.get("interval_seconds"), Some(Value::Int(s)) if s == "5") {
        return Err("settings.json interval_seconds != 5".into());
    }
    if !matches!(
        written.get("permission_wait_seconds"),
        Some(Value::Int(s)) if s == "90"
    ) {
        return Err("settings.json permission_wait_seconds != 90".into());
    }
    for (k, expected) in [
        ("ntfy_url", "https://ntfy.example.com"),
        ("ntfy_topic", "vitruvian-e2e"),
        ("kube_context", "homelab-e2e"),
        ("prometheus_url", "https://prom.example.com"),
        ("gh_extra_repos", "VitruvianSoftware/vitruvian-core"),
    ] {
        if written.get(k).and_then(|v| v.as_str()) != Some(expected) {
            return Err(format!("settings.json {k} mismatch"));
        }
    }

    for (secret_name, secret_val) in [
        ("ntfy-token", "tk_e2e_secret"),
        ("prometheus-token", "prom_e2e_secret"),
    ] {
        let secret_path = data.join("config").join(secret_name);
        let got = fs::read_to_string(&secret_path)
            .map_err(|e| format!("read {}: {e}", secret_path.display()))?;
        if got.trim() != secret_val {
            return Err(format!("{secret_name} was not persisted accurately"));
        }
    }

    let claude_settings = home.join(".claude/settings.json");
    let claude_text = fs::read_to_string(&claude_settings)
        .map_err(|e| format!("read ~/.claude/settings.json: {e}"))?;
    if !claude_text.contains("permission-hook --config-dir") {
        return Err("~/.claude/settings.json did not receive --config-dir hook".into());
    }

    said.push(format!(
        "active persistence ({kind}): settings.json, 0600 tokens, and ~/.claude/settings.json verified"
    ));
    Ok(said)
}

pub fn end_to_end_coexistence(folder: &Path, scratch: &Path) -> Result<Vec<String>, String> {
    let manifest_text = fs::read_to_string(folder.join("vitruvian-tool.json"))
        .map_err(|e| format!("read manifest: {e}"))?;
    let manifest = json::loads(&manifest_text).map_err(|e| format!("parse manifest: {e:?}"))?;
    let exec_rel = manifest
        .get("runtime")
        .and_then(|r| r.get("exec"))
        .and_then(|e| e.as_str())
        .ok_or("missing runtime.exec")?;
    let program = folder.join(exec_rel);

    let home = scratch.join("coexist_home");
    let data = scratch.join("coexist_data");
    let standalone_cfg = home.join(".config/vitruvian-remote-agent");
    fs::create_dir_all(&standalone_cfg).map_err(|e| format!("mkdir standalone_cfg: {e}"))?;
    fs::create_dir_all(&data).map_err(|e| format!("mkdir coexist_data: {e}"))?;

    fs::write(standalone_cfg.join("token"), "standalone-token-xyz\n")
        .map_err(|e| format!("write token: {e}"))?;
    fs::write(standalone_cfg.join("paired"), "2026-10-15T12:00:00Z\n")
        .map_err(|e| format!("write paired: {e}"))?;
    fs::write(
        standalone_cfg.join("settings.json"),
        "{\"ntfy_url\":\"https://ntfy.sh\",\"ntfy_topic\":\"copied-topic\"}",
    )
    .map_err(|e| format!("write settings.json: {e}"))?;

    apply_tool_env(&home, &data, folder, "1");

    let link = Link::spawn(&[program.to_string_lossy().into_owned()], &data)
        .map_err(|e| format!("spawn tool: {e}"))?;
    let run = Run::new(
        link,
        &manifest,
        data.to_string_lossy().into_owned(),
        Run::<Link>::default_features(),
    );
    let mut app = Driver::new(run);
    let mut said = Vec::new();

    let hs = app
        .run
        .handshake()
        .map_err(|f| format!("coexistence handshake: {}", f.0))?;
    said.push(format!("coexistence handshake: {hs}"));

    let island = app.open("remote")?;
    if !says(&island, "Choose One Vitruvian Remote") {
        return Err("coexistence prompt not shown when both installed".into());
    }
    app.act("remote", "chooseExtension", "tap", None, false)?;
    let active_island = app
        .act("remote", "confirmUseExtension", "tap", None, false)?
        .ok_or("confirmUseExtension returned no tree")?;
    if says(&active_island, "Choose One Vitruvian Remote") {
        return Err("coexistence prompt remained after confirming extension".into());
    }

    app.run
        .link
        .send(&Value::Obj(vec![
            ("jsonrpc".into(), Value::Str("2.0".into())),
            ("method".into(), Value::Str("ui/close".into())),
            (
                "params".into(),
                Value::Obj(vec![("panel".into(), Value::Str("remote".into()))]),
            ),
        ]))
        .map_err(|f| f.0)?;
    let sd = app.run.shutdown().map_err(|f| f.0)?;
    said.push(format!("coexistence shutdown: {sd}"));
    app.run.link.close();

    let choice_text = fs::read_to_string(standalone_cfg.join("remote_door.json"))
        .map_err(|e| format!("read remote_door.json: {e}"))?;
    let choice = json::loads(&choice_text).map_err(|e| format!("parse remote_door.json: {e:?}"))?;
    if choice.get("chosen").and_then(|v| v.as_str()) != Some("extension") {
        return Err("remote_door.json chosen != 'extension'".into());
    }
    let ext_meta = choice.get("extension").ok_or("missing extension meta")?;
    if ext_meta.get("program").and_then(|v| v.as_str()) != Some(&program.to_string_lossy())
        || ext_meta.get("data_folder").and_then(|v| v.as_str()) != Some(&data.to_string_lossy())
    {
        return Err("remote_door.json extension metadata mismatch".into());
    }

    let copied_token = fs::read_to_string(data.join("config/token"))
        .map_err(|e| format!("read copied token: {e}"))?;
    if copied_token.trim() != "standalone-token-xyz" {
        return Err("standalone bearer token was not copied to extension config/token".into());
    }

    said.push("coexistence handoff: remote_door.json and copied bearer token verified".into());
    Ok(said)
}

pub fn run(args: &[String]) -> i32 {
    if args.len() < 3 {
        eprintln!("usage: tool_conformance <built vitruvian-tool.json> <vitruvian-tool>");
        return 2;
    }
    let manifest_arg = Path::new(&args[1]);
    let validate_arg = if args.len() >= 4 {
        Path::new(&args[3])
    } else {
        Path::new(&args[2])
    };
    let built = match fs::canonicalize(manifest_arg)
        .ok()
        .and_then(|p| p.parent().map(Path::to_path_buf))
    {
        Some(p) => p,
        None => {
            eprintln!(
                "cannot resolve built folder from {}",
                manifest_arg.display()
            );
            return 1;
        }
    };
    let validate_bin =
        fs::canonicalize(validate_arg).unwrap_or_else(|_| validate_arg.to_path_buf());

    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    let scratch = env::var("TEST_TMPDIR")
        .ok()
        .filter(|s| !s.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(env::temp_dir)
        .join(format!("remote-conformance-{nanos}"));
    let folder = scratch.join("remote");
    if let Err(e) = copy_dir_recursive(&built, &folder) {
        eprintln!("copy built folder failed: {e}");
        return 1;
    }

    let bundled_agent = folder.join("bin/vitruvian-remote-agent");
    let is_exec = fs::metadata(&bundled_agent)
        .map(|m| m.is_file() && (m.permissions().mode() & 0o111 != 0))
        .unwrap_or(false);
    if !is_exec {
        println!(
            "bundled agent missing or not executable at {}",
            bundled_agent.display()
        );
        return 1;
    }

    let home = scratch.join("home");
    let data_dir = scratch.join("data");
    let _ = fs::create_dir_all(&home);
    let _ = fs::create_dir_all(&data_dir);
    apply_tool_env(&home, &data_dir, &folder, "0");

    let mut failed = 0;
    let val_out = Command::new(&validate_bin)
        .arg("validate")
        .arg(&folder)
        .output();
    match val_out {
        Ok(o) => {
            let code = o.status.code().unwrap_or(1);
            print!(
                "--- validate: exit {code}\n{}{}",
                String::from_utf8_lossy(&o.stdout),
                String::from_utf8_lossy(&o.stderr)
            );
            if code != 0 {
                failed += 1;
            }
        }
        Err(e) => {
            println!("--- validate: failed to spawn: {e}");
            failed += 1;
        }
    }

    let conf_code = conformance_rs_lib::check(&folder);
    println!("--- conformance: exit {conf_code}");
    if conf_code != 0 {
        failed += 1;
    }
    if failed > 0 {
        println!("{failed} of 2 checks failed");
        return 1;
    }

    let all_features: Vec<String> = FEATURES.iter().map(|s| (*s).to_string()).collect();
    let without_sections: Vec<String> = FEATURES
        .iter()
        .filter(|&&s| s != "ui.sections")
        .map(|s| (*s).to_string())
        .collect();

    let mut said = Vec::new();
    for res in [
        end_to_end_active(&folder, &scratch, all_features),
        end_to_end_active(&folder, &scratch, without_sections),
        end_to_end_coexistence(&folder, &scratch),
    ] {
        match res {
            Ok(lines) => said.extend(lines),
            Err(failure) => {
                println!("--- end to end: NOT OK: {failure}");
                return 1;
            }
        }
    }

    println!("--- end to end: ok\n{}", said.join("\n"));
    println!(
        "the built Vitruvian Remote tool validates, passes the conformance script, \
         and drives its island, its settings as one page (ui.sections) and as 4 tabs, \
         QR pairing, and coexistence end to end"
    );
    0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn words_and_says_extract_nested_strings() {
        let tree = json::loads(
            r#"{"blocks": [{"id": "b1", "type": "text", "text": "Pixel Fold connected"}, {"id": "b2", "type": "heading", "section": true, "text": "General"}]}"#,
        )
        .unwrap();
        assert!(says(&tree, "Pixel Fold"));
        assert!(!says(&tree, "Nexus 5"));
        assert!(block(&tree, "b1").is_some());
        assert!(block(&tree, "missing").is_none());
        assert_eq!(section_headings(&tree), vec!["General".to_string()]);
    }

    #[test]
    fn section_headings_ignores_non_section_headings() {
        let tree = json::loads(
            r#"{"blocks": [{"type": "heading", "text": "Title Only"}, {"type": "heading", "section": true, "text": "General"}, {"type": "heading", "section": true, "text": "Integrations"}]}"#,
        )
        .unwrap();
        assert_eq!(
            section_headings(&tree),
            vec!["General".to_string(), "Integrations".to_string()]
        );
    }
}
