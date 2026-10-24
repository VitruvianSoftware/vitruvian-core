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

//! The `antigravity-telemetry` command line (`antigravity_telemetry.py`):
//! `setup`, `status`, `emit` and `export`, plus the small argparse-alike the
//! entrypoints share.
//!
//! One deliberate difference from Python: `setup` installs *this* binary as
//! the exporter (`~/.gemini/hooks/antigravity-telemetry-rs`, run with the
//! `session-exporter` subcommand) instead of copying `session_exporter.py`,
//! and `status` looks for that install. The launchd label is the same, so
//! running the Rust `setup` replaces a Python-installed exporter in place.

use crate::http_client::{Flavor, TelemetryHttpClient};
use crate::json::{dumps, float_repr, J};
use crate::otlp_builder::{self as ob, get_hostname, SpanArgs, DEFAULT_LATENCY_BOUNDS};
use crate::pyutil::{parse_py_float, py_int, py_str, strip};
use crate::session_exporter::glob_brain_transcripts;
use crate::sys;
use crate::telemetry_hook::{process_event, ToolTimers};
use std::io::{Read, Write};

pub const DEFAULT_ENDPOINT: &str = "https://otel.lab.ipv1337.dev";
pub const LAUNCH_AGENT_LABEL: &str = "com.google.antigravity.telemetry";
/// File name the exporter binary is installed under in the hooks directory.
pub const EXPORTER_NAME: &str = "antigravity-telemetry-rs";
/// Subcommand the launchd job runs.
pub const EXPORTER_SUBCOMMAND: &str = "session-exporter";
pub const DEFAULT_HOOK_NAME: &str = "telemetry_hook.py";

pub fn legacy_gemini_settings_path() -> String {
    sys::expanduser("~/.gemini/settings.json")
}

pub fn default_hooks_dir() -> String {
    sys::expanduser("~/.gemini/hooks")
}

pub fn launch_agent_path() -> String {
    sys::expanduser(&format!(
        "~/Library/LaunchAgents/{}.plist",
        LAUNCH_AGENT_LABEL
    ))
}

pub fn exporter_log_dir() -> String {
    sys::expanduser("~/.gemini/antigravity/logs")
}

/// `GEMINI_SETTINGS_PATH`, or Gemini CLI's own settings file.
pub fn get_default_settings_path() -> String {
    std::env::var("GEMINI_SETTINGS_PATH").unwrap_or_else(|_| legacy_gemini_settings_path())
}

// ============================================================================
// A small argparse
// ============================================================================

#[derive(Clone, Copy, PartialEq, Debug)]
pub enum Kind {
    Flag,
    Str,
    Int,
    Float,
}

struct OptSpec {
    name: &'static str,
    kind: Kind,
    default: Option<J>,
    help: &'static str,
}

/// Parsed options: `--name` -> value (`J::Bool` for flags, `J::Null` unset).
pub struct Namespace {
    values: Vec<(&'static str, J)>,
}

impl Namespace {
    pub fn get(&self, name: &str) -> &J {
        self.values
            .iter()
            .find(|(k, _)| *k == name)
            .map(|(_, v)| v)
            .unwrap_or(&J::Null)
    }

    pub fn flag(&self, name: &str) -> bool {
        matches!(self.get(name), J::Bool(true))
    }

    pub fn str(&self, name: &str) -> Option<String> {
        self.get(name).as_str().map(str::to_string)
    }

    pub fn float(&self, name: &str) -> Option<f64> {
        match self.get(name) {
            J::Float(f) => Some(*f),
            J::Int(i) => Some(*i as f64),
            _ => None,
        }
    }

    pub fn int(&self, name: &str) -> Option<i128> {
        match self.get(name) {
            J::Int(i) => Some(*i),
            _ => None,
        }
    }
}

pub struct ArgParser {
    prog: String,
    description: String,
    opts: Vec<OptSpec>,
}

fn looks_negative_number(s: &str) -> bool {
    s.starts_with('-')
        && s[1..]
            .chars()
            .next()
            .map(|c| c.is_ascii_digit() || c == '.')
            .unwrap_or(false)
        && parse_py_float(s).is_some()
}

impl ArgParser {
    pub fn new(prog: &str, description: &str) -> Self {
        ArgParser {
            prog: prog.to_string(),
            description: description.to_string(),
            opts: Vec::new(),
        }
    }

    pub fn opt(
        mut self,
        name: &'static str,
        kind: Kind,
        default: Option<J>,
        help: &'static str,
    ) -> Self {
        self.opts.push(OptSpec {
            name,
            kind,
            default,
            help,
        });
        self
    }

    fn usage(&self) -> String {
        let parts: Vec<String> = self
            .opts
            .iter()
            .map(|o| match o.kind {
                Kind::Flag => format!("[{}]", o.name),
                _ => format!(
                    "[{} {}]",
                    o.name,
                    o.name
                        .trim_start_matches('-')
                        .replace('-', "_")
                        .to_uppercase()
                ),
            })
            .collect();
        format!("usage: {} [-h] {}", self.prog, parts.join(" "))
    }

    fn help(&self) -> String {
        let mut out = format!(
            "{}\n\n{}\n\noptions:\n  -h, --help            show this help message and exit\n",
            self.usage(),
            self.description
        );
        for o in &self.opts {
            let left = match o.kind {
                Kind::Flag => o.name.to_string(),
                _ => format!(
                    "{} {}",
                    o.name,
                    o.name
                        .trim_start_matches('-')
                        .replace('-', "_")
                        .to_uppercase()
                ),
            };
            if left.len() <= 20 {
                out.push_str(&format!("  {:<22}{}\n", left, o.help));
            } else {
                out.push_str(&format!("  {}\n                        {}\n", left, o.help));
            }
        }
        out
    }

    fn error(&self, msg: &str) -> i32 {
        eprintln!("{}\n{}: error: {}", self.usage(), self.prog, msg);
        2
    }

    fn convert(&self, spec: &OptSpec, raw: &str) -> Result<J, String> {
        match spec.kind {
            Kind::Str => Ok(J::str(raw)),
            Kind::Int => py_int(&J::str(raw))
                .map(J::Int)
                .map_err(|_| format!("argument {}: invalid int value: '{}'", spec.name, raw)),
            Kind::Float => parse_py_float(raw)
                .map(J::Float)
                .ok_or_else(|| format!("argument {}: invalid float value: '{}'", spec.name, raw)),
            Kind::Flag => Ok(J::Bool(true)),
        }
    }

    /// Parse `args`; `Err(exit_code)` after printing help or an error.
    pub fn parse(&self, args: &[String]) -> Result<Namespace, i32> {
        let mut values: Vec<(&'static str, J)> = self
            .opts
            .iter()
            .map(|o| {
                let d = match o.kind {
                    Kind::Flag => J::Bool(false),
                    _ => o.default.clone().unwrap_or(J::Null),
                };
                (o.name, d)
            })
            .collect();
        let mut i = 0;
        while i < args.len() {
            let arg = &args[i];
            if arg == "-h" || arg == "--help" {
                print!("{}", self.help());
                return Err(0);
            }
            if !arg.starts_with("--") || arg == "--" {
                return Err(self.error(&format!("unrecognized arguments: {}", args[i..].join(" "))));
            }
            let (name, inline) = match arg.split_once('=') {
                Some((n, v)) => (n, Some(v.to_string())),
                None => (arg.as_str(), None),
            };
            let matches: Vec<&OptSpec> = match self.opts.iter().find(|o| o.name == name) {
                Some(o) => vec![o],
                None => self
                    .opts
                    .iter()
                    .filter(|o| o.name.starts_with(name))
                    .collect(),
            };
            let spec = match matches.len() {
                1 => matches[0],
                0 => return Err(self.error(&format!("unrecognized arguments: {}", arg))),
                _ => {
                    let names: Vec<&str> = matches.iter().map(|o| o.name).collect();
                    return Err(self.error(&format!(
                        "ambiguous option: {} could match {}",
                        name,
                        names.join(", ")
                    )));
                }
            };
            let value = if spec.kind == Kind::Flag {
                if inline.is_some() {
                    return Err(self.error(&format!(
                        "argument {}: ignored explicit argument '{}'",
                        spec.name,
                        inline.unwrap_or_default()
                    )));
                }
                J::Bool(true)
            } else {
                let raw = match inline {
                    Some(v) => v,
                    None => {
                        let next = args.get(i + 1);
                        match next {
                            Some(n) if !n.starts_with('-') || looks_negative_number(n) => {
                                i += 1;
                                n.clone()
                            }
                            _ => {
                                return Err(self.error(&format!(
                                    "argument {}: expected one argument",
                                    spec.name
                                )))
                            }
                        }
                    }
                };
                match self.convert(spec, &raw) {
                    Ok(v) => v,
                    Err(msg) => return Err(self.error(&msg)),
                }
            };
            if let Some(slot) = values.iter_mut().find(|(k, _)| *k == spec.name) {
                slot.1 = value;
            }
            i += 1;
        }
        Ok(Namespace { values })
    }
}

// ============================================================================
// Shared pieces
// ============================================================================

/// Remove the telemetry hooks earlier versions wrote into Gemini CLI's
/// `settings.json`. Returns the cleaned settings and the (sorted, unique)
/// events touched; `Err` when the settings are not a JSON object, where
/// Python raises.
pub fn strip_legacy_hooks(existing: &J) -> Result<(J, Vec<String>), String> {
    if !matches!(existing, J::Obj(_)) {
        return Err(format!(
            "'{}' object has no attribute 'get'",
            crate::pyutil::type_name(existing)
        ));
    }
    let mut updated = existing.clone();
    let mut removed: Vec<String> = Vec::new();
    let mut hooks = match updated.get("hooks") {
        Some(h @ J::Obj(_)) => h.clone(),
        _ => return Ok((updated, removed)),
    };

    let is_ours = |h: &J| -> bool {
        if !matches!(h, J::Obj(_)) {
            return false;
        }
        let command = py_str(h.get("command").unwrap_or(&J::str("")));
        h.get("name") == Some(&J::str("telemetry-hook"))
            || command.contains("telemetry_hook")
            || command.contains("stream-hook")
            || command.contains("stream_hook")
    };

    let event_names: Vec<String> = match &hooks {
        J::Obj(pairs) => pairs.iter().map(|(k, _)| k.clone()).collect(),
        _ => Vec::new(),
    };
    for event_name in event_names {
        let Some(J::Arr(matchers)) = hooks.get(&event_name).cloned() else {
            continue;
        };
        let mut kept_matchers = Vec::new();
        for mut matcher in matchers {
            if !matches!(matcher, J::Obj(_)) {
                kept_matchers.push(matcher);
                continue;
            }
            let Some(J::Arr(inner)) = matcher.get("hooks").cloned() else {
                kept_matchers.push(matcher);
                continue;
            };
            let kept: Vec<J> = inner.iter().filter(|h| !is_ours(h)).cloned().collect();
            if kept.len() != inner.len() {
                removed.push(event_name.clone());
            }
            if !kept.is_empty() {
                matcher.set("hooks", J::Arr(kept));
                kept_matchers.push(matcher);
            }
        }
        if kept_matchers.is_empty() {
            hooks.remove(&event_name);
        } else {
            hooks.set(&event_name, J::Arr(kept_matchers));
        }
    }

    if matches!(&hooks, J::Obj(p) if p.is_empty()) {
        updated.remove("hooks");
    } else {
        updated.set("hooks", hooks);
    }
    removed.sort();
    removed.dedup();
    Ok((updated, removed))
}

/// The launchd job that keeps the exporter running.
pub fn build_launch_agent_plist(exporter_path: &str) -> String {
    let log_dir = exporter_log_dir();
    format!(
        r#"<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>{label}</string>
    <key>ProgramArguments</key>
    <array>
        <string>{exe}</string>
        <string>{sub}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>{log}/session_exporter.log</string>
    <key>StandardErrorPath</key>
    <string>{log}/session_exporter.err</string>
</dict>
</plist>
"#,
        label = LAUNCH_AGENT_LABEL,
        exe = exporter_path,
        sub = EXPORTER_SUBCOMMAND,
        log = log_dir
    )
}

/// Locate the Antigravity CLI, which is what produces the transcripts.
pub fn find_agy() -> Option<String> {
    let explicit = std::env::var("AGY_BIN").unwrap_or_default();
    if !explicit.is_empty() && sys::is_executable(&explicit) {
        return Some(explicit);
    }
    for candidate in [
        sys::expanduser("~/.local/bin/agy"),
        "/opt/homebrew/bin/agy".into(),
        "/usr/local/bin/agy".into(),
    ] {
        if sys::is_executable(&candidate) {
            return Some(candidate);
        }
    }
    sys::which("agy")
}

fn read_settings(path: &str) -> Result<J, String> {
    let bytes = std::fs::read(path).map_err(|e| e.to_string())?;
    let text = String::from_utf8(bytes).map_err(|e| e.to_string())?;
    let content = strip(&text);
    if content.is_empty() {
        Ok(J::empty_obj())
    } else {
        J::parse(content)
    }
}

fn opt_str(v: Option<String>) -> J {
    v.map(J::Str).unwrap_or(J::Null)
}

// ============================================================================
// setup
// ============================================================================

pub fn cmd_setup(ns: &Namespace) -> i32 {
    let endpoint = ns
        .str("--endpoint")
        .unwrap_or_default()
        .trim_end_matches('/')
        .to_string();
    let hooks_dir = sys::abspath(&sys::expanduser(&ns.str("--hooks-dir").unwrap_or_default()));
    let exporter_dest = sys::join(&hooks_dir, EXPORTER_NAME);
    let settings_path = sys::abspath(&sys::expanduser(
        &ns.str("--settings-path").unwrap_or_default(),
    ));
    let dry_run = ns.flag("--dry-run");
    let as_json = ns.flag("--json");
    let launch_agent = launch_agent_path();
    let agy = find_agy();

    let mut results = J::obj(vec![
        ("status", J::str("success")),
        ("exporter", J::str(exporter_dest.clone())),
        ("launch_agent", J::str(launch_agent.clone())),
        ("endpoint", J::str(endpoint.clone())),
        ("agy", opt_str(agy.clone())),
        ("dry_run", J::Bool(dry_run)),
    ]);

    let source = match std::env::current_exe() {
        Ok(p) => p,
        Err(e) => {
            let msg = format!("Exporter source not found: {}", e);
            results.set("status", J::str("error"));
            results.set("error", J::str(msg.clone()));
            if as_json {
                println!("{}", dumps(&results, Some(2), true));
            } else {
                eprintln!("{}", msg);
            }
            return 1;
        }
    };

    if !dry_run {
        let install = || -> std::io::Result<(bool, String)> {
            use std::os::unix::fs::PermissionsExt;
            std::fs::create_dir_all(&hooks_dir)?;
            std::fs::create_dir_all(exporter_log_dir())?;
            // Copy to a temporary name and rename, so a running exporter is
            // replaced rather than overwritten underneath itself.
            let tmp = format!("{}.tmp.{}", exporter_dest, std::process::id());
            std::fs::copy(&source, &tmp)?;
            std::fs::set_permissions(&tmp, std::fs::Permissions::from_mode(0o755))?;
            std::fs::rename(&tmp, &exporter_dest)?;
            std::fs::create_dir_all(sys::dirname(&launch_agent))?;
            std::fs::write(&launch_agent, build_launch_agent_plist(&exporter_dest))?;

            let uid = sys::uid();
            let _ = sys::run(
                &[
                    "/bin/launchctl",
                    "bootout",
                    &format!("gui/{}/{}", uid, LAUNCH_AGENT_LABEL),
                ],
                None,
                None,
            );
            match sys::run(
                &[
                    "/bin/launchctl",
                    "bootstrap",
                    &format!("gui/{}", uid),
                    &launch_agent,
                ],
                None,
                None,
            ) {
                Ok(o) => Ok((
                    o.code == 0,
                    String::from_utf8_lossy(&o.stderr).trim().to_string(),
                )),
                Err(sys::CmdError::Spawn(e)) => Err(e),
                Err(sys::CmdError::Timeout) => Ok((false, "launchctl timed out".to_string())),
            }
        };
        match install() {
            Ok((loaded, err)) => {
                results.set("launch_agent_loaded", J::Bool(loaded));
                if !loaded {
                    results.set("launch_agent_error", J::str(err));
                }
            }
            Err(e) => {
                eprintln!("antigravity-telemetry setup: {}", e);
                return 1;
            }
        }
    }

    let mut removed_events: Vec<String> = Vec::new();
    if std::path::Path::new(&settings_path).exists() {
        match read_settings(&settings_path) {
            Err(e) => results.set(
                "legacy_cleanup",
                J::str(format!("skipped, unreadable: {}", e)),
            ),
            Ok(existing) => {
                let (cleaned, removed) = match strip_legacy_hooks(&existing) {
                    Ok(r) => r,
                    Err(e) => {
                        eprintln!("antigravity-telemetry setup: {}", e);
                        return 1;
                    }
                };
                removed_events = removed;
                if !removed_events.is_empty() && !dry_run {
                    let write = || -> std::io::Result<Option<String>> {
                        let mut backup = None;
                        if !ns.flag("--no-backup") {
                            let path =
                                format!("{}.bak.{}", settings_path, sys::local_timestamp_compact());
                            std::fs::copy(&settings_path, &path)?;
                            backup = Some(path);
                        }
                        let tmp = format!("{}.tmp.{}", settings_path, std::process::id());
                        std::fs::write(&tmp, format!("{}\n", dumps(&cleaned, Some(2), true)))?;
                        std::fs::rename(&tmp, &settings_path)?;
                        Ok(backup)
                    };
                    match write() {
                        Ok(Some(backup)) => results.set("backup_path", J::str(backup)),
                        Ok(None) => {}
                        Err(e) => {
                            eprintln!("antigravity-telemetry setup: {}", e);
                            return 1;
                        }
                    }
                }
            }
        }
    }
    results.set(
        "legacy_hooks_removed",
        J::Arr(removed_events.iter().map(|e| J::str(e.clone())).collect()),
    );

    if as_json {
        println!("{}", dumps(&results, Some(2), true));
    } else {
        println!("Antigravity Telemetry Setup");
        println!("==========================");
        println!("Collector endpoint: {}", endpoint);
        println!("Exporter:           {}", exporter_dest);
        println!("launchd job:        {}", launch_agent);
        println!(
            "agy binary:         {}",
            agy.unwrap_or_else(|| "NOT FOUND".to_string())
        );
        if !removed_events.is_empty() {
            println!(
                "Removed dead Gemini CLI hooks from {}: {}",
                settings_path,
                removed_events.join(", ")
            );
        }
        if dry_run {
            println!("Mode:               DRY-RUN (no files modified)");
        } else {
            println!("Status:             Exporter installed and running.");
        }
    }
    0
}

// ============================================================================
// status
// ============================================================================

fn round1(x: f64) -> f64 {
    format!("{:.1}", x).parse().unwrap_or(x)
}

fn probe(client: &TelemetryHttpClient, path: &str, payload: &J) -> (J, bool) {
    let t0 = sys::now_secs();
    let (ok, code, msg) = client.post_json(path, payload, false, true);
    let lat = round1((sys::now_secs() - t0) * 1000.0);
    let passed = ok || code == 200 || code == 202;
    let message = if passed {
        format!("HTTP {} ({}ms)", code, float_repr(lat))
    } else {
        format!("Failed: {}", msg)
    };
    (
        J::obj(vec![
            ("passed", J::Bool(passed)),
            ("http_status", J::Int(code as i128)),
            ("latency_ms", J::Float(lat)),
            ("message", J::Str(message)),
        ]),
        passed,
    )
}

pub fn cmd_status(ns: &Namespace) -> i32 {
    let endpoint = ns
        .str("--endpoint")
        .unwrap_or_default()
        .trim_end_matches('/')
        .to_string();
    let hooks_dir = sys::abspath(&sys::expanduser(&ns.str("--hooks-dir").unwrap_or_default()));
    let exporter_path = sys::join(&hooks_dir, EXPORTER_NAME);
    let settings_path = sys::abspath(&sys::expanduser(
        &ns.str("--settings-path").unwrap_or_default(),
    ));
    let timeout = ns.float("--timeout").unwrap_or(5.0);
    let host = get_hostname();
    let launch_agent = launch_agent_path();

    let mut checks = J::empty_obj();
    let mut local_passed = true;
    let mut remote_passed = true;

    // 1. agy, whose transcripts are the data source.
    let agy = find_agy();
    checks.set(
        "agy_cli",
        J::obj(vec![
            ("passed", J::Bool(agy.is_some())),
            ("path", J::str(agy.clone().unwrap_or_default())),
            (
                "message",
                J::Str(match &agy {
                    Some(p) => format!("Found at {}", p),
                    None => "agy not installed".to_string(),
                }),
            ),
        ]),
    );
    if agy.is_none() {
        local_passed = false;
    }

    // 2. Transcripts, per surface.
    let brain_dirs = [
        (
            "antigravity",
            sys::expanduser("~/.gemini/antigravity/brain"),
        ),
        ("agy", sys::expanduser("~/.gemini/antigravity-cli/brain")),
        (
            "antigravity-ide",
            sys::expanduser("~/.gemini/antigravity-ide/brain"),
        ),
    ];
    let mut counts = J::empty_obj();
    let mut total = 0usize;
    let mut parts = Vec::new();
    for (name, dir) in &brain_dirs {
        let n = glob_brain_transcripts(dir).len();
        total += n;
        counts.set(name, J::Int(n as i128));
        parts.push(format!("{}: {}", name, n));
    }
    checks.set(
        "transcripts",
        J::obj(vec![
            ("passed", J::Bool(total > 0)),
            ("counts", counts),
            ("message", J::Str(parts.join(", "))),
        ]),
    );
    if total == 0 {
        local_passed = false;
    }

    // 3. The installed exporter.
    let installed =
        std::path::Path::new(&exporter_path).exists() && sys::is_executable(&exporter_path);
    checks.set(
        "exporter_script",
        J::obj(vec![
            ("passed", J::Bool(installed)),
            ("path", J::str(exporter_path.clone())),
            (
                "message",
                J::str(if installed {
                    "Installed and executable"
                } else {
                    "Missing or not executable — run `setup`"
                }),
            ),
        ]),
    );
    if !installed {
        local_passed = false;
    }

    // 4. The launchd job actually running.
    let pattern = format!("{} {}", EXPORTER_NAME, EXPORTER_SUBCOMMAND);
    let pid = match sys::run(&["/usr/bin/pgrep", "-f", &pattern], None, Some(5.0)) {
        Ok(o) if o.code == 0 => String::from_utf8_lossy(&o.stdout)
            .split('\n')
            .next()
            .unwrap_or("")
            .trim()
            .to_string(),
        _ => String::new(),
    };
    checks.set(
        "exporter_running",
        J::obj(vec![
            ("passed", J::Bool(!pid.is_empty())),
            ("pid", J::str(pid.clone())),
            ("launch_agent", J::str(launch_agent)),
            (
                "message",
                J::Str(if pid.is_empty() {
                    "Not running — run `setup`".to_string()
                } else {
                    format!("Running (pid {})", pid)
                }),
            ),
        ]),
    );
    if pid.is_empty() {
        local_passed = false;
    }

    // 5. Leftovers from the Gemini CLI era, which nothing executes.
    let mut legacy: Vec<String> = Vec::new();
    if std::path::Path::new(&settings_path).exists() {
        if let Ok(data) = read_settings(&settings_path) {
            if let Ok((_, events)) = strip_legacy_hooks(&data) {
                legacy = events;
            }
        }
    }
    checks.set(
        "legacy_gemini_hooks",
        J::obj(vec![
            ("passed", J::Bool(legacy.is_empty())),
            ("path", J::str(settings_path)),
            (
                "events",
                J::Arr(legacy.iter().map(|e| J::str(e.clone())).collect()),
            ),
            (
                "message",
                J::Str(if legacy.is_empty() {
                    "None".to_string()
                } else {
                    format!(
                        "Dead hooks still present for {} — run `setup` to remove",
                        legacy.join(", ")
                    )
                }),
            ),
        ]),
    );

    // 6. Collector connectivity.
    let client = TelemetryHttpClient::new(&endpoint, timeout, Flavor::Builder);
    let (metrics_check, ok_m) = probe(
        &client,
        "v1/metrics",
        &J::obj(vec![("resourceMetrics", J::Arr(vec![]))]),
    );
    checks.set("collector_metrics", metrics_check);
    let (traces_check, ok_t) = probe(
        &client,
        "v1/traces",
        &J::obj(vec![("resourceSpans", J::Arr(vec![]))]),
    );
    checks.set("collector_traces", traces_check);
    if !ok_m || !ok_t {
        remote_passed = false;
    }

    let healthy = local_passed && remote_passed;
    if ns.flag("--json") {
        let report = J::obj(vec![
            (
                "status",
                J::str(if healthy { "healthy" } else { "degraded" }),
            ),
            ("timestamp", J::Str(sys::utc_isoformat_now())),
            ("host", J::str(host)),
            ("endpoint", J::str(endpoint)),
            ("checks", checks),
        ]);
        println!("{}", dumps(&report, Some(2), true));
    } else {
        let (system, release) = sys::uname();
        println!("Antigravity Telemetry Status");
        println!("Host:     {} ({} {})", host, system, release);
        println!("Endpoint: {}", endpoint);
        println!();
        println!("Checks:");
        if let J::Obj(pairs) = &checks {
            for (name, c) in pairs {
                let mark = if c.get("passed") == Some(&J::Bool(true)) {
                    "[✓]"
                } else {
                    "[✗]"
                };
                let message = c.get("message").map(py_str).unwrap_or_default();
                println!("  {} {:<20} {}", mark, name, message);
            }
        }
        println!();
        if healthy {
            println!("Status: HEALTHY (All checks passed)");
        } else {
            println!("Status: DEGRADED (One or more checks failed)");
        }
    }

    match (local_passed, remote_passed) {
        (true, true) => 0,
        (false, false) => 3,
        (true, false) => 2,
        (false, true) => 1,
    }
}

// ============================================================================
// emit
// ============================================================================

pub fn cmd_emit(ns: &Namespace) -> i32 {
    let endpoint = ns
        .str("--endpoint")
        .unwrap_or_default()
        .trim_end_matches('/')
        .to_string();
    let host = match ns.str("--host") {
        Some(h) if !h.is_empty() => h,
        _ => get_hostname(),
    };
    let model = J::Str(ns.str("--model").unwrap_or_default());
    let tool = J::Str(ns.str("--tool").unwrap_or_default());
    let latency = ns.float("--tool-latency-ms").unwrap_or(145.0);
    let count = ns.int("--count").unwrap_or(1);
    let interval = ns.float("--interval").unwrap_or(0.0);
    let as_json = ns.flag("--json");
    let client = TelemetryHttpClient::new(&endpoint, 5.0, Flavor::Builder);
    let h = Some(host.as_str());
    let success_j = J::str("success");

    let mut metrics = Vec::new();
    if !ns.flag("--traces-only") {
        let tok = |name: &str| J::Int(ns.int(name).unwrap_or(0));
        metrics.push(ob::build_token_usage_metric(
            &tok("--tokens-input"),
            &tok("--tokens-output"),
            &tok("--tokens-thinking"),
            &tok("--tokens-cached"),
            &model,
            h,
            None,
        ));
        metrics.push(ob::build_api_request_metric(
            &model,
            &J::str("200"),
            1,
            h,
            None,
        ));
        metrics.push(ob::build_tool_call_count_metric(
            &tool, &success_j, 1, h, None,
        ));
        metrics.push(ob::build_tool_call_latency_metric(
            &tool,
            &[latency],
            &success_j,
            h,
            Some(&DEFAULT_LATENCY_BOUNDS),
            None,
        ));
        metrics.push(ob::build_session_count_metric(
            &J::str("started"),
            1,
            h,
            None,
        ));
        metrics.push(ob::build_turn_count_metric(&model, 1, h, None));
        metrics.push(ob::build_subagent_spawn_metric(
            &J::str("explorer"),
            1,
            h,
            None,
        ));
    }

    let mut spans = Vec::new();
    if !ns.flag("--metrics-only") {
        let now_ns = sys::now_ns();
        let mut args = SpanArgs::new(
            "antigravity.synthetic_session_turn",
            now_ns - (latency * 1e6) as i128,
            now_ns,
        );
        args.attributes = vec![
            ("host", J::str(host.clone())),
            ("model.name", model.clone()),
            ("tool.name", tool.clone()),
            (
                "session.id",
                J::Str(format!("synthetic-{}", sys::now_secs() as i64)),
            ),
        ];
        spans.push(ob::build_span(&args));
    }
    let metrics_emitted = metrics.len();
    let traces_emitted = spans.len();

    let metrics_payload = if metrics.is_empty() {
        None
    } else {
        Some(ob::build_metrics_payload(
            metrics,
            "antigravity",
            h,
            ob::SCOPE_NAME,
            ob::SCOPE_VERSION,
        ))
    };
    let traces_payload = if spans.is_empty() {
        None
    } else {
        Some(ob::build_traces_payload(
            spans,
            "antigravity",
            h,
            ob::SCOPE_NAME,
            ob::SCOPE_VERSION,
        ))
    };

    if ns.flag("--verbose") {
        if let Some(p) = &metrics_payload {
            println!("OTLP Metrics Payload:");
            println!("{}", dumps(p, Some(2), true));
        }
        if let Some(p) = &traces_payload {
            println!("OTLP Traces Payload:");
            println!("{}", dumps(p, Some(2), true));
        }
    }

    let mut success = true;
    let mut iteration: i128 = 0;
    while iteration < count {
        if let Some(p) = &metrics_payload {
            let (ok, code, msg) = client.post_json("v1/metrics", p, true, false);
            if !ok && code != 200 && code != 202 {
                success = false;
                if !as_json {
                    eprintln!(
                        "Failed to emit metrics (iteration {}): {}",
                        iteration + 1,
                        msg
                    );
                }
            }
        }
        if let Some(p) = &traces_payload {
            let (ok, code, msg) = client.post_json("v1/traces", p, true, false);
            if !ok && code != 200 && code != 202 {
                success = false;
                if !as_json {
                    eprintln!(
                        "Failed to emit traces (iteration {}): {}",
                        iteration + 1,
                        msg
                    );
                }
            }
        }
        if interval > 0.0 && iteration < count - 1 {
            std::thread::sleep(std::time::Duration::from_secs_f64(interval));
        }
        iteration += 1;
    }

    if as_json {
        let out = J::obj(vec![
            ("status", J::str(if success { "success" } else { "error" })),
            ("host", J::str(host.clone())),
            ("endpoint", J::str(endpoint.clone())),
            ("metrics_emitted", J::Int(metrics_emitted as i128)),
            ("traces_emitted", J::Int(traces_emitted as i128)),
            ("iterations", J::Int(count)),
        ]);
        println!("{}", dumps(&out, Some(2), true));
    } else if success {
        println!(
            "Successfully emitted telemetry to {} (host: {}, {} iteration(s))",
            endpoint, host, count
        );
    } else {
        println!("Emission completed with errors to {}", endpoint);
    }
    if success {
        0
    } else {
        2
    }
}

// ============================================================================
// export
// ============================================================================

pub fn cmd_export(ns: &Namespace) -> i32 {
    let endpoint = ns
        .str("--endpoint")
        .unwrap_or_default()
        .trim_end_matches('/')
        .to_string();
    let host = get_hostname();
    let verbose = ns.flag("--verbose");

    let result: Result<(), String> = (|| {
        let raw = match ns.str("--file") {
            Some(path) => {
                let bytes = std::fs::read(&path).map_err(|e| {
                    format!(
                        "[Errno {}] {}: '{}'",
                        e.raw_os_error().unwrap_or(0),
                        e.kind_message(),
                        path
                    )
                })?;
                String::from_utf8(bytes).map_err(|e| e.to_string())?
            }
            None => {
                let mut buf = Vec::new();
                std::io::stdin()
                    .read_to_end(&mut buf)
                    .map_err(|e| e.to_string())?;
                String::from_utf8(buf).map_err(|e| e.to_string())?
            }
        };
        let data = if strip(&raw).is_empty() {
            J::empty_obj()
        } else {
            J::parse(&raw)?
        };
        let metrics = process_event(&data, Some(&host), &mut ToolTimers::default())?;
        if !metrics.is_empty() {
            let n = metrics.len();
            let payload = ob::build_metrics_payload(
                metrics,
                "antigravity",
                Some(&host),
                ob::SCOPE_NAME,
                ob::SCOPE_VERSION,
            );
            let client = TelemetryHttpClient::new(&endpoint, 2.0, Flavor::Builder);
            let (_, code, msg) = client.post_json("v1/metrics", &payload, true, true);
            if verbose {
                eprintln!("[export] Dispatched {} metrics -> {} ({})", n, code, msg);
            }
        }
        Ok(())
    })();
    if let Err(e) = result {
        if verbose {
            eprintln!("[export] Warning: {}", e);
        }
    }
    if ns.flag("--hook-mode") {
        let mut out = std::io::stdout();
        let _ = out.write_all(b"{}\n");
        let _ = out.flush();
    }
    0
}

trait KindMessage {
    fn kind_message(&self) -> String;
}

impl KindMessage for std::io::Error {
    /// The OS's own wording (`No such file or directory`), without Rust's
    /// ` (os error 2)` suffix.
    fn kind_message(&self) -> String {
        let text = self.to_string();
        text.split(" (os error").next().unwrap_or(&text).to_string()
    }
}

// ============================================================================
// Entry point
// ============================================================================

const SUBCOMMANDS: [&str; 4] = ["setup", "status", "emit", "export"];

fn endpoint_help() -> &'static str {
    "OTLP collector endpoint (default: https://otel.lab.ipv1337.dev)"
}

fn subparser(name: &str) -> ArgParser {
    let prog = format!("antigravity-telemetry {}", name);
    match name {
        "setup" => ArgParser::new(
            &prog,
            "Install the transcript exporter and remove retired Gemini CLI hooks",
        )
        .opt(
            "--endpoint",
            Kind::Str,
            Some(J::str(DEFAULT_ENDPOINT)),
            endpoint_help(),
        )
        .opt(
            "--settings-path",
            Kind::Str,
            Some(J::str(get_default_settings_path())),
            "Gemini CLI settings.json to clean up (legacy)",
        )
        .opt(
            "--hooks-dir",
            Kind::Str,
            Some(J::str(default_hooks_dir())),
            "Path to hooks directory",
        )
        .opt(
            "--hook-script-name",
            Kind::Str,
            Some(J::str(DEFAULT_HOOK_NAME)),
            "Filename of hook script",
        )
        .opt(
            "--dry-run",
            Kind::Flag,
            None,
            "Print planned changes without writing to disk",
        )
        .opt(
            "--no-backup",
            Kind::Flag,
            None,
            "Disable creating settings backup",
        )
        .opt("--json", Kind::Flag, None, "Output machine-readable JSON"),
        "status" => ArgParser::new(
            &prog,
            "Diagnose the exporter, transcript sources, and collector connectivity",
        )
        .opt(
            "--endpoint",
            Kind::Str,
            Some(J::str(DEFAULT_ENDPOINT)),
            endpoint_help(),
        )
        .opt(
            "--settings-path",
            Kind::Str,
            Some(J::str(get_default_settings_path())),
            "Gemini CLI settings.json to clean up (legacy)",
        )
        .opt(
            "--hooks-dir",
            Kind::Str,
            Some(J::str(default_hooks_dir())),
            "Path to hooks directory",
        )
        .opt(
            "--timeout",
            Kind::Float,
            Some(J::Float(5.0)),
            "HTTP connection timeout in seconds",
        )
        .opt("--json", Kind::Flag, None, "Output machine-readable JSON"),
        "emit" => ArgParser::new(&prog, "Emit synthetic or custom metrics and traces")
            .opt(
                "--endpoint",
                Kind::Str,
                Some(J::str(DEFAULT_ENDPOINT)),
                endpoint_help(),
            )
            .opt("--host", Kind::Str, None, "Override hostname label")
            .opt(
                "--model",
                Kind::Str,
                Some(J::str("gemini-3.7-flash")),
                "Model name label",
            )
            .opt(
                "--tool",
                Kind::Str,
                Some(J::str("run_command")),
                "Tool name label",
            )
            .opt(
                "--tokens-input",
                Kind::Int,
                Some(J::Int(1250)),
                "Input token count",
            )
            .opt(
                "--tokens-output",
                Kind::Int,
                Some(J::Int(320)),
                "Output token count",
            )
            .opt(
                "--tokens-thinking",
                Kind::Int,
                Some(J::Int(450)),
                "Thinking token count",
            )
            .opt(
                "--tokens-cached",
                Kind::Int,
                Some(J::Int(800)),
                "Cached token count",
            )
            .opt(
                "--tool-latency-ms",
                Kind::Float,
                Some(J::Float(145.0)),
                "Tool latency in ms",
            )
            .opt(
                "--count",
                Kind::Int,
                Some(J::Int(1)),
                "Number of iterations",
            )
            .opt(
                "--interval",
                Kind::Float,
                Some(J::Float(0.0)),
                "Interval between iterations in seconds",
            )
            .opt("--metrics-only", Kind::Flag, None, "Emit metrics only")
            .opt("--traces-only", Kind::Flag, None, "Emit traces only")
            .opt("--verbose", Kind::Flag, None, "Print full JSON payloads")
            .opt("--json", Kind::Flag, None, "Output machine-readable JSON"),
        _ => ArgParser::new(&prog, "Process hook events from stdin or file")
            .opt(
                "--endpoint",
                Kind::Str,
                Some(J::str(DEFAULT_ENDPOINT)),
                endpoint_help(),
            )
            .opt(
                "--file",
                Kind::Str,
                None,
                "Read JSON from file instead of stdin",
            )
            .opt(
                "--hook-mode",
                Kind::Flag,
                None,
                "Always output {} to stdout and exit 0",
            )
            .opt("--verbose", Kind::Flag, None, "Log debug details to stderr"),
    }
}

const TOP_USAGE: &str = "usage: antigravity-telemetry [-h] {setup,status,emit,export,session-exporter,telemetry-hook,telemetry-loader} ...";

fn top_help() -> String {
    format!(
        "{}\n\nAntigravity & AGY OTLP Telemetry Exporter, Diagnostics, and Setup Tool.\n\n\
positional arguments:\n\
  setup               Install the transcript exporter and remove retired Gemini CLI hooks\n\
  status              Diagnose the exporter, transcript sources, and collector connectivity\n\
  emit                Emit synthetic or custom metrics and traces\n\
  export              Process hook events from stdin or file\n\
  session-exporter    Tail agent transcripts and export OTLP (session_exporter.py)\n\
  telemetry-hook      Lifecycle hook: one event on stdin to OTLP (telemetry_hook.py)\n\
  telemetry-loader    Self-updating loader for the hook engine (telemetry_loader.py)\n\n\
options:\n  -h, --help          show this help message and exit\n",
        TOP_USAGE
    )
}

/// `antigravity_telemetry.py`'s command line.
pub fn main(args: &[String]) -> i32 {
    let Some(first) = args.first() else {
        eprintln!(
            "{}\nantigravity-telemetry: error: the following arguments are required: subcommand",
            TOP_USAGE
        );
        return 2;
    };
    if first == "-h" || first == "--help" {
        print!("{}", top_help());
        return 0;
    }
    if !SUBCOMMANDS.contains(&first.as_str()) {
        eprintln!(
            "{}\nantigravity-telemetry: error: argument subcommand: invalid choice: '{}' (choose from 'setup', 'status', 'emit', 'export', 'session-exporter', 'telemetry-hook', 'telemetry-loader')",
            TOP_USAGE, first
        );
        return 2;
    }
    let ns = match subparser(first).parse(&args[1..]) {
        Ok(ns) => ns,
        Err(code) => return code,
    };
    match first.as_str() {
        "setup" => cmd_setup(&ns),
        "status" => cmd_status(&ns),
        "emit" => cmd_emit(&ns),
        _ => cmd_export(&ns),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn args(v: &[&str]) -> Vec<String> {
        v.iter().map(|s| s.to_string()).collect()
    }

    #[test]
    fn argparse_abbreviations_and_types() {
        let p = subparser("emit");
        let ns = p
            .parse(&args(&[
                "--tokens-in",
                "7",
                "--tool-latency-ms=-3.5",
                "--json",
                "--count",
                "2",
            ]))
            .unwrap();
        assert_eq!(ns.int("--tokens-input"), Some(7));
        assert_eq!(ns.float("--tool-latency-ms"), Some(-3.5));
        assert_eq!(ns.int("--tokens-output"), Some(320));
        assert!(ns.flag("--json"));
        assert!(!ns.flag("--verbose"));
        assert_eq!(p.parse(&args(&["--tokens", "1"])).err(), Some(2)); // ambiguous
        assert_eq!(p.parse(&args(&["--count", "x"])).err(), Some(2));
        assert_eq!(p.parse(&args(&["--bogus"])).err(), Some(2));
        assert_eq!(p.parse(&args(&["--host"])).err(), Some(2));
    }

    #[test]
    fn strip_legacy_hooks_removes_only_ours() {
        let settings = J::parse(
            r#"{"theme": "dark", "hooks": {
                "AfterModel": [{"matcher": "*", "hooks": [
                    {"name": "telemetry-hook", "command": "python3 x"},
                    {"name": "mine", "command": "echo hi"}]}],
                "BeforeTool": [{"hooks": [{"command": "/x/stream_hook.sh"}]}],
                "Stop": [{"hooks": "not-a-list"}, 3]}}"#,
        )
        .unwrap();
        let (cleaned, removed) = strip_legacy_hooks(&settings).unwrap();
        assert_eq!(removed, vec!["AfterModel", "BeforeTool"]);
        assert_eq!(
            dumps(&cleaned, None, true),
            r#"{"theme": "dark", "hooks": {"AfterModel": [{"matcher": "*", "hooks": [{"name": "mine", "command": "echo hi"}]}], "Stop": [{"hooks": "not-a-list"}, 3]}}"#
        );
    }

    #[test]
    fn strip_legacy_hooks_drops_empty_hooks_key() {
        let settings = J::parse(
            r#"{"hooks": {"AfterTool": [{"hooks": [{"command": "telemetry_hook.py"}]}]}, "x": 1}"#,
        )
        .unwrap();
        let (cleaned, removed) = strip_legacy_hooks(&settings).unwrap();
        assert_eq!(removed, vec!["AfterTool"]);
        assert_eq!(dumps(&cleaned, None, true), r#"{"x": 1}"#);
        assert!(strip_legacy_hooks(&J::Arr(vec![])).is_err());
    }

    #[test]
    fn plist_runs_the_exporter_subcommand() {
        let plist = build_launch_agent_plist("/h/.gemini/hooks/antigravity-telemetry-rs");
        assert!(plist.contains("<string>/h/.gemini/hooks/antigravity-telemetry-rs</string>\n        <string>session-exporter</string>"));
        assert!(plist.contains(&format!("<string>{}</string>", LAUNCH_AGENT_LABEL)));
    }
}
