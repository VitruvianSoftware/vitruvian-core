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

//! Vitruvian TV extension (dev.vitruvian.tv).
//!
//! Controls the Living Room Sony BRAVIA 4K Google TV over ADB from the
//! Vitruvian Dynamic Island, Command Bar, Radial Menu, and Shortcuts.

use std::cell::RefCell;
use std::io::Read;
use std::net::Ipv6Addr;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::rc::Rc;
use std::sync::mpsc;
use std::thread;
use std::time::{Duration, Instant};

use serde_json::{Map, Value};
use vitruvian_tool_kit::{
    button, choice, divider, features, field, heading, row, section, status, text, toggle, tree,
    App, Panel, PanelAnswer, PanelEvent, StatusOptions, Tool, ToolError, UiBlock, UiChoiceOption,
    UiTree,
};

const VERSION: &str = "0.1.0";

/// Each app the panel can launch: key, label, package, and the activity to
/// start (None launches the package's leanback launcher through `monkey`).
const APPS: &[(&str, &str, &str, Option<&str>)] = &[
    (
        "smarttube",
        "SmartTube (Ad-Free 4K)",
        "org.smarttube.stable",
        None,
    ),
    (
        "projectivy",
        "Projectivy Home",
        "com.spocky.projengmenu",
        Some("com.spocky.projengmenu/.ui.home.MainActivity"),
    ),
    (
        "aerial",
        "AerialViews Screensaver",
        "com.neilturner.aerialviews",
        Some("com.android.systemui/.Somnambulator"),
    ),
    ("disney", "Disney+", "com.disney.disneyplus", None),
    ("netflix", "Netflix", "com.netflix.ninja", None),
];

/// Each input the panel can switch to: key, label, and Projectivy's activity
/// for it.
const INPUTS: &[(&str, &str, &str)] = &[
    (
        "home",
        "Google TV Home (Projectivy)",
        "com.spocky.projengmenu/.ui.home.MainActivity",
    ),
    (
        "hdmi1",
        "HDMI 1",
        "com.spocky.projengmenu/.ui.guidedActions.activities.input.SourceHDMI1Activity",
    ),
    (
        "hdmi2",
        "HDMI 2",
        "com.spocky.projengmenu/.ui.guidedActions.activities.input.SourceHDMI2Activity",
    ),
    (
        "hdmi3",
        "HDMI 3 (eARC)",
        "com.spocky.projengmenu/.ui.guidedActions.activities.input.SourceHDMI3Activity",
    ),
    (
        "hdmi4",
        "HDMI 4",
        "com.spocky.projengmenu/.ui.guidedActions.activities.input.SourceHDMI4Activity",
    ),
];

const STATUS_PROBE: &str = concat!(
    "dumpsys power | grep 'mWakefulness='; ",
    "dumpsys window | grep 'mCurrentFocus='; ",
    "grep MemAvailable /proc/meminfo"
);

const TOGGLE_POWER: &str = concat!(
    "if dumpsys power | grep -qE 'mWakefulness=(Awake|Dreaming)'; then ",
    "input keyevent KEYCODE_SLEEP; echo POWER_STATE=SLEEP; ",
    "else input keyevent KEYCODE_WAKEUP; echo POWER_STATE=AWAKE; fi; ",
    "grep MemAvailable /proc/meminfo"
);

const START_SCREENSAVER: &str =
    "input keyevent KEYCODE_WAKEUP; am start -n com.android.systemui/.Somnambulator";

const STANDBY: &str = "Standby (Remote Start Ready)";

fn app_entry(
    key: &str,
) -> Option<&'static (
    &'static str,
    &'static str,
    &'static str,
    Option<&'static str>,
)> {
    APPS.iter().find(|entry| entry.0 == key)
}

fn input_entry(key: &str) -> Option<&'static (&'static str, &'static str, &'static str)> {
    INPUTS.iter().find(|entry| entry.0 == key)
}

// ---------------------------------------------------------------------------
// Finding and running adb.

fn is_executable_file(path: &Path) -> bool {
    use std::os::unix::fs::PermissionsExt;
    match std::fs::metadata(path) {
        Ok(meta) => meta.is_file() && meta.permissions().mode() & 0o111 != 0,
        Err(_) => false,
    }
}

/// `shutil.which("adb")`: the first executable `adb` on `PATH`.
fn which_adb() -> Option<PathBuf> {
    let path = std::env::var_os("PATH").unwrap_or_else(|| "/bin:/usr/bin".into());
    std::env::split_paths(&path)
        .map(|dir| dir.join("adb"))
        .find(|candidate| is_executable_file(candidate))
}

/// The adb to run: Homebrew's, then /usr/local, then the Android SDK's, then
/// whichever `PATH` finds, and Homebrew's path when none exists.
fn find_adb() -> PathBuf {
    let sdk = match std::env::var_os("HOME") {
        Some(home) => PathBuf::from(home).join("Library/Android/sdk/platform-tools/adb"),
        None => PathBuf::from("~/Library/Android/sdk/platform-tools/adb"),
    };
    let candidates = [
        PathBuf::from("/opt/homebrew/bin/adb"),
        PathBuf::from("/usr/local/bin/adb"),
        sdk,
    ];
    for candidate in candidates {
        if is_executable_file(&candidate) {
            return candidate;
        }
    }
    which_adb().unwrap_or_else(|| PathBuf::from("/opt/homebrew/bin/adb"))
}

/// What one adb run gave: whether it exited 0, and its standard output.
#[derive(Clone, Debug, Default, PartialEq)]
struct AdbOutput {
    success: bool,
    stdout: String,
}

/// Runs adb. A seam so tests can stand in for the TV.
trait AdbRunner {
    /// Runs adb with `args` and waits at most `timeout`. `capture` keeps its
    /// standard output; without it the output is thrown away. An error is a
    /// run that could not start or did not finish in time.
    fn run(&self, args: &[&str], timeout: Duration, capture: bool) -> Result<AdbOutput, String>;
}

/// The real adb, as a child process with a deadline.
struct SystemAdb;

impl AdbRunner for SystemAdb {
    fn run(&self, args: &[&str], timeout: Duration, capture: bool) -> Result<AdbOutput, String> {
        let deadline = Instant::now() + timeout;
        // Standard input is the link to the app: never let adb read from it.
        let mut child = Command::new(find_adb())
            .args(args)
            .stdin(Stdio::null())
            .stdout(if capture {
                Stdio::piped()
            } else {
                Stdio::null()
            })
            .stderr(Stdio::null())
            .spawn()
            .map_err(|e| e.to_string())?;
        // Read the output on a thread so a full pipe never stalls the child.
        let reader = child.stdout.take().map(|mut out| {
            let (tx, rx) = mpsc::channel();
            thread::spawn(move || {
                let mut bytes = Vec::new();
                let _ = out.read_to_end(&mut bytes);
                let _ = tx.send(bytes);
            });
            rx
        });
        let exit = loop {
            match child.try_wait() {
                Ok(Some(exit)) => break exit,
                Ok(None) if Instant::now() < deadline => thread::sleep(Duration::from_millis(5)),
                Ok(None) => {
                    let _ = child.kill();
                    let _ = child.wait();
                    return Err(format!("adb timed out after {timeout:?}"));
                }
                Err(e) => {
                    let _ = child.kill();
                    let _ = child.wait();
                    return Err(e.to_string());
                }
            }
        };
        let stdout = match reader {
            Some(rx) => {
                let left = deadline.saturating_duration_since(Instant::now());
                rx.recv_timeout(left.max(Duration::from_millis(50)))
                    .map_err(|_| format!("adb output not closed within {timeout:?}"))?
            }
            None => Vec::new(),
        };
        Ok(AdbOutput {
            success: exit.success(),
            stdout: String::from_utf8_lossy(&stdout).into_owned(),
        })
    }
}

// ---------------------------------------------------------------------------
// Quoting and URLs.

/// `shlex.quote`: the word as it is when it is only safe characters, else in
/// single quotes with each single quote written as `'"'"'`.
fn shlex_quote(word: &str) -> String {
    if word.is_empty() {
        return "''".to_string();
    }
    let safe = |c: char| c.is_ascii_alphanumeric() || "_@%+=:,./-".contains(c);
    if word.chars().all(safe) {
        return word.to_string();
    }
    format!("'{}'", word.replace('\'', "'\"'\"'"))
}

/// The scheme and network location `urllib.parse.urlsplit` finds, or an
/// error where it raises `ValueError`.
fn split_scheme_netloc(raw: &str) -> Result<(String, String), ()> {
    let mut scheme = String::new();
    let mut rest = raw;
    if let Some(colon) = raw.find(':') {
        let head = &raw[..colon];
        let first_ok = head
            .chars()
            .next()
            .map_or(false, |c| c.is_ascii_alphabetic());
        let all_ok = head
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '+' || c == '-' || c == '.');
        if colon > 0 && first_ok && all_ok {
            scheme = head.to_ascii_lowercase();
            rest = &raw[colon + 1..];
        }
    }
    let mut netloc = String::new();
    if let Some(after) = rest.strip_prefix("//") {
        let end = after
            .find(|c| c == '/' || c == '?' || c == '#')
            .unwrap_or(after.len());
        netloc = after[..end].to_string();
        let open = netloc.contains('[');
        let close = netloc.contains(']');
        if open != close {
            return Err(());
        }
        if open {
            check_bracketed_netloc(&netloc)?;
        }
    }
    Ok((scheme, netloc))
}

/// `urllib.parse._check_bracketed_netloc`: a bracketed host must be an IPv6
/// address (or an IPvFuture), alone before an optional `:port`.
fn check_bracketed_netloc(netloc: &str) -> Result<(), ()> {
    let host_and_port = netloc.rsplit_once('@').map_or(netloc, |(_, h)| h);
    let Some((before, bracketed)) = host_and_port.split_once('[') else {
        return Ok(());
    };
    if !before.is_empty() {
        return Err(());
    }
    let (host, port) = bracketed.split_once(']').unwrap_or((bracketed, ""));
    if !port.is_empty() && !port.starts_with(':') {
        return Err(());
    }
    if let Some(future) = host.strip_prefix('v') {
        // \Av[a-fA-F0-9]+\..+\z
        let Some((hex, tail)) = future.split_once('.') else {
            return Err(());
        };
        if hex.is_empty() || !hex.chars().all(|c| c.is_ascii_hexdigit()) || tail.is_empty() {
            return Err(());
        }
        return Ok(());
    }
    let address = host.split_once('%').map_or(host, |(a, _)| a);
    address.parse::<Ipv6Addr>().map(|_| ()).map_err(|_| ())
}

/// True for an http(s) URL with a host and no whitespace or control
/// characters, safe to hand to the TV's shell once quoted.
fn is_safe_http_url(raw: &str) -> bool {
    if raw.is_empty() || raw.chars().any(|c| c.is_whitespace() || (c as u32) < 32) {
        return false;
    }
    match split_scheme_netloc(raw) {
        Ok((scheme, netloc)) => (scheme == "http" || scheme == "https") && !netloc.is_empty(),
        Err(()) => false,
    }
}

/// The `MemAvailable` line's kB as whole MB, when it has one.
fn parse_mem_available_mb(out: &str) -> Option<u64> {
    let mut found = None;
    for line in out.lines() {
        if line.contains("MemAvailable:") {
            let parts: Vec<&str> = line.split_whitespace().collect();
            if parts.len() >= 2
                && !parts[1].is_empty()
                && parts[1].chars().all(|c| c.is_ascii_digit())
            {
                if let Ok(kb) = parts[1].parse::<u64>() {
                    found = Some(kb / 1024);
                }
            }
        }
    }
    found
}

/// Ignores the app's refusal; anything else (the link gone, no answer) is
/// still an error.
fn refusal_ok<T>(result: Result<T, ToolError>) -> Result<Option<T>, ToolError> {
    match result {
        Ok(value) => Ok(Some(value)),
        Err(ToolError::App(_)) => Ok(None),
        Err(other) => Err(other),
    }
}

fn notify_safe(app: &mut App<'_>, icon: &str, message: &str) -> Result<(), ToolError> {
    refusal_ok(app.notify().hud(message, icon)).map(|_| ())
}

// ---------------------------------------------------------------------------
// The TV.

struct SonyTVState {
    tv_address: String,
    show_island_status: bool,
    selected_app: String,
    selected_input: String,
    awake: bool,
    foreground: String,
    mem_available_mb: u64,
    connected: bool,
    dry_run: bool,
    adb: Box<dyn AdbRunner>,
}

impl SonyTVState {
    fn new(adb: Box<dyn AdbRunner>) -> SonyTVState {
        SonyTVState {
            tv_address: "192.168.86.31:5555".to_string(),
            show_island_status: true,
            selected_app: "smarttube".to_string(),
            selected_input: "home".to_string(),
            awake: false,
            foreground: "Checking TV…".to_string(),
            mem_available_mb: 0,
            connected: false,
            dry_run: false,
            adb,
        }
    }

    /// Live only inside the installed app's data folder, or with
    /// VITRUVIAN_TV_LIVE=1; elsewhere (the conformance script, a test) it
    /// pretends.
    fn set_dry_run_for(&mut self, data_folder: &str) {
        self.dry_run = !data_folder.contains("Application Support")
            && std::env::var("VITRUVIAN_TV_LIVE").ok().as_deref() != Some("1");
    }

    fn load_preferences(&mut self, app: &mut App<'_>) {
        let folder = app.data_folder().to_string_lossy().into_owned();
        self.set_dry_run_for(&folder);
        if let Ok(Value::String(addr)) = app.storage().get("tvAddress") {
            if !addr.trim().is_empty() {
                self.tv_address = addr.trim().to_string();
            }
        }
        if let Ok(Value::Bool(show)) = app.storage().get("showIslandStatus") {
            self.show_island_status = show;
        }
    }

    /// Runs a single ADB shell call well inside the 2s request limit. Only
    /// runs `adb connect` on fallback if the device is not already connected.
    fn run_adb_shell(&mut self, shell_cmd: &str, timeout_secs: f64) -> String {
        if self.dry_run {
            self.connected = true;
            return String::new();
        }
        let address = self.tv_address.clone();
        let shell = ["-s", address.as_str(), "shell", shell_cmd];
        let attempt = || -> Result<Option<String>, String> {
            let first = self
                .adb
                .run(&shell, Duration::from_secs_f64(timeout_secs), true)?;
            if first.success {
                return Ok(Some(first.stdout.trim().to_string()));
            }
            self.adb.run(
                &["connect", address.as_str()],
                Duration::from_secs_f64(0.45),
                false,
            )?;
            let second = self.adb.run(&shell, Duration::from_secs_f64(0.65), true)?;
            if second.success {
                return Ok(Some(second.stdout.trim().to_string()));
            }
            Ok(None)
        };
        if let Ok(Some(out)) = attempt() {
            self.connected = true;
            return out;
        }
        self.connected = false;
        String::new()
    }

    fn parse_status_output(&mut self, out: &str) {
        if out.is_empty() {
            return;
        }
        self.awake = out.contains("Awake") || out.contains("Dreaming");
        self.foreground =
            if out.contains("com.neilturner.aerialviews") || out.contains("DreamActivity") {
                "AerialViews 4K"
            } else if out.contains("org.smarttube.stable") {
                "SmartTube 4K"
            } else if out.contains("com.spocky.projengmenu") {
                "Projectivy Home"
            } else if out.contains("com.disney.disneyplus") {
                "Disney+"
            } else if out.contains("com.netflix.ninja") {
                "Netflix"
            } else if !self.awake {
                STANDBY
            } else {
                "Active"
            }
            .to_string();
        if let Some(mb) = parse_mem_available_mb(out) {
            self.mem_available_mb = mb;
        }
    }

    fn refresh(&mut self) {
        if self.dry_run {
            self.connected = true;
            self.awake = true;
            self.foreground = "Projectivy Home".to_string();
            self.mem_available_mb = 640;
            return;
        }
        let out = self.run_adb_shell(STATUS_PROBE, 0.85);
        self.parse_status_output(&out);
    }

    /// Toggles TV wakefulness in a single atomic shell call so it never
    /// guesses from stale local state or exceeds the 2s timeout.
    fn toggle_power_atomic(&mut self) -> bool {
        if self.dry_run {
            self.connected = true;
            self.awake = !self.awake;
            self.foreground = if self.awake {
                "Projectivy Home"
            } else {
                STANDBY
            }
            .to_string();
            return self.awake;
        }
        let out = self.run_adb_shell(TOGGLE_POWER, 0.95);
        if out.contains("POWER_STATE=SLEEP") {
            self.awake = false;
            self.foreground = STANDBY.to_string();
        } else if out.contains("POWER_STATE=AWAKE") {
            self.awake = true;
            self.foreground = "Projectivy Home".to_string();
        }
        if let Some(mb) = parse_mem_available_mb(&out) {
            self.mem_available_mb = mb;
        }
        self.awake
    }

    /// The closed island's mark, from what the TV is doing. A refusal is
    /// logged and gives false.
    fn sync_status(&self, app: &mut App<'_>) -> Result<bool, ToolError> {
        let sent = if !self.show_island_status || !self.connected || !self.awake {
            app.ui().status(status::NONE, None, None)
        } else {
            let short = if self.foreground.contains("SmartTube") {
                "YT"
            } else if self.foreground.contains("Aerial") {
                "4K"
            } else {
                "TV"
            };
            let activity = if app.supports(features::STATUS_ACTIVITY) {
                Some(short.into())
            } else {
                None
            };
            app.ui().status_with(
                status::OK,
                StatusOptions {
                    text: Some(format!("Sony TV: {}", self.foreground).into()),
                    activity,
                    ..StatusOptions::default()
                },
            )
        };
        match sent {
            Err(ToolError::App(refusal)) => {
                app.log(&format!("status refused: {refusal}"));
                Ok(false)
            }
            other => other,
        }
    }

    fn launch_app(&mut self, app_key: &str) {
        let Some(&(key, label, pkg, component)) = app_entry(app_key) else {
            return;
        };
        self.selected_app = key.to_string();
        let cmd = match component {
            Some(component) => format!(
                "input keyevent KEYCODE_WAKEUP; am start -n {}",
                shlex_quote(component)
            ),
            None => format!(
                "input keyevent KEYCODE_WAKEUP; monkey -p {} -c android.intent.category.leanback.LAUNCHER 1 >/dev/null 2>&1",
                shlex_quote(pkg)
            ),
        };
        self.run_adb_shell(&cmd, 0.95);
        self.awake = true;
        self.foreground = label.to_string();
    }

    fn switch_input(&mut self, input_key: &str) {
        let Some(&(key, label, component)) = input_entry(input_key) else {
            return;
        };
        self.selected_input = key.to_string();
        self.run_adb_shell(
            &format!(
                "input keyevent KEYCODE_WAKEUP; am start -n {}",
                shlex_quote(component)
            ),
            0.95,
        );
        self.awake = true;
        self.foreground = label.to_string();
    }

    fn start_screensaver(&mut self) {
        self.run_adb_shell(START_SCREENSAVER, 0.95);
        self.awake = true;
        self.foreground = "AerialViews 4K".to_string();
    }

    /// Plays `clip` on SmartTube when it is a safe http(s) URL; false, and
    /// nothing is run, when it is not.
    fn cast_url(&mut self, clip: &str) -> bool {
        if !is_safe_http_url(clip) {
            return false;
        }
        self.run_adb_shell(
            &format!(
                "input keyevent KEYCODE_WAKEUP; am start -a android.intent.action.VIEW -d {} org.smarttube.stable",
                shlex_quote(clip)
            ),
            0.95,
        );
        self.awake = true;
        self.foreground = "SmartTube 4K".to_string();
        true
    }

    fn page(&self, app: &App<'_>) -> UiTree {
        let status_line = if self.connected {
            format!(
                "{} • {} MB available",
                self.foreground, self.mem_available_mb
            )
        } else {
            format!("Disconnected ({})", self.tv_address)
        };
        let has_choice = app.supports(features::CHOICE);
        let app_options = APPS
            .iter()
            .map(|(key, label, _, _)| UiChoiceOption {
                value: key.to_string(),
                title: (*label).into(),
            })
            .collect();
        let input_options = INPUTS
            .iter()
            .map(|(key, label, _)| UiChoiceOption {
                value: key.to_string(),
                title: (*label).into(),
            })
            .collect();
        let app_picker: UiBlock = if has_choice {
            choice("launchApp", self.selected_app.as_str(), app_options)
                .title("Launch TV App")
                .into()
        } else {
            field("launchApp")
                .title("App (smarttube, projectivy, aerial, disney, netflix)")
                .value(self.selected_app.as_str())
                .into()
        };
        let input_picker: UiBlock = if has_choice {
            choice("switchInput", self.selected_input.as_str(), input_options)
                .title("TV Input / Source")
                .into()
        } else {
            field("switchInput")
                .title("Input (home, hdmi1, hdmi2, hdmi3, hdmi4)")
                .value(self.selected_input.as_str())
                .into()
        };
        tree![
            heading("Living Room Sony TV"),
            row("BRAVIA 4K VH22")
                .subtitle(status_line)
                .icon(if self.awake { "tv.fill" } else { "tv" })
                .trailing(if self.awake { "Awake" } else { "Standby" }),
            button(
                "togglePower",
                if self.awake {
                    "Put TV to Sleep"
                } else {
                    "Wake TV Now"
                }
            )
            .style("prominent"),
            button("startScreensaver", "Start 4K Aerial Screensaver"),
            button("playClipboard", "Cast Clipboard URL to SmartTube"),
            divider(),
            app_picker,
            input_picker,
            divider(),
            button("volUp", "Volume Up"),
            button("volDown", "Volume Down"),
            button("muteTV", "Mute / Unmute"),
            button("refresh", "Refresh TV Status"),
        ]
    }

    fn settings(&self, app: &App<'_>) -> UiTree {
        let help_text = "Shows a green mark on the closed island while the Sony TV is awake.";
        if !app.supports(features::SECTIONS) {
            return tree![
                field("tvAddress")
                    .title("Sony TV ADB Address")
                    .value(self.tv_address.as_str())
                    .placeholder("192.168.86.31:5555"),
                toggle(
                    "showIslandStatus",
                    "Show TV status on closed island",
                    self.show_island_status
                ),
                text(help_text).style("caption"),
                button("trimCaches", "Trim TV Caches in Background"),
            ];
        }
        tree![
            section("Connection"),
            field("tvAddress")
                .title("Sony TV ADB Address")
                .value(self.tv_address.as_str())
                .placeholder("192.168.86.31:5555")
                .help("IP:port of your Sony BRAVIA TV with Network ADB enabled."),
            section("Dynamic Island"),
            toggle(
                "showIslandStatus",
                "Show TV status on closed island",
                self.show_island_status
            )
            .help(help_text),
            section("Maintenance"),
            button("trimCaches", "Trim TV Caches in Background"),
        ]
    }
}

type Tv = Rc<RefCell<SonyTVState>>;

fn cast_clipboard_url(app: &mut App<'_>, tv: &mut SonyTVState) -> Result<(), ToolError> {
    let clip = refusal_ok(app.clipboard().read_text())?
        .flatten()
        .unwrap_or_default();
    if tv.cast_url(clip.trim()) {
        notify_safe(app, "play.tv", "Playing clipboard URL on Sony TV")
    } else {
        notify_safe(
            app,
            "exclamationmark.triangle",
            "Clipboard does not contain a valid HTTP(S) URL",
        )
    }
}

fn island_event(
    app: &mut App<'_>,
    tv: &mut SonyTVState,
    event: &PanelEvent,
) -> Result<PanelAnswer, ToolError> {
    match event.block.as_deref() {
        Some("togglePower") => {
            tv.toggle_power_atomic();
            tv.sync_status(app)?;
        }
        Some("startScreensaver") => {
            tv.start_screensaver();
            tv.sync_status(app)?;
        }
        Some("playClipboard") => {
            cast_clipboard_url(app, tv)?;
            tv.sync_status(app)?;
        }
        Some("launchApp") => {
            let Some(key) = event.text().filter(|k| app_entry(k).is_some()) else {
                return Ok(PanelAnswer::Keep);
            };
            tv.launch_app(key);
            tv.sync_status(app)?;
        }
        Some("switchInput") => {
            let Some(key) = event.text().filter(|k| input_entry(k).is_some()) else {
                return Ok(PanelAnswer::Keep);
            };
            tv.switch_input(key);
            tv.sync_status(app)?;
        }
        Some("volUp") => {
            tv.run_adb_shell("input keyevent KEYCODE_VOLUME_UP", 0.6);
        }
        Some("volDown") => {
            tv.run_adb_shell("input keyevent KEYCODE_VOLUME_DOWN", 0.6);
        }
        Some("muteTV") => {
            tv.run_adb_shell("input keyevent KEYCODE_VOLUME_MUTE", 0.6);
        }
        Some("refresh") => {
            tv.refresh();
            tv.sync_status(app)?;
        }
        _ => return Ok(PanelAnswer::Keep),
    }
    Ok(PanelAnswer::Page(tv.page(app)))
}

fn settings_event(
    app: &mut App<'_>,
    tv: &mut SonyTVState,
    event: &PanelEvent,
) -> Result<PanelAnswer, ToolError> {
    match (event.block.as_deref(), event.text(), event.is_on()) {
        (Some("tvAddress"), Some(addr), _) => {
            let addr = addr.trim();
            if !addr.is_empty() {
                tv.tv_address = addr.to_string();
                refusal_ok(app.storage().set("tvAddress", addr))?;
            }
        }
        (Some("showIslandStatus"), _, Some(on)) => {
            tv.show_island_status = on;
            refusal_ok(app.storage().set("showIslandStatus", on))?;
            tv.sync_status(app)?;
        }
        (Some("trimCaches"), _, _) => {
            tv.run_adb_shell(
                "nohup sh -c 'pm trim-caches 999999999G' >/dev/null 2>&1 &",
                0.75,
            );
            notify_safe(app, "sparkles", "Started background cache trim on Sony TV")?;
        }
        _ => return Ok(PanelAnswer::Keep),
    }
    Ok(PanelAnswer::Page(tv.settings(app)))
}

fn on_start(app: &mut App<'_>, tv: &mut SonyTVState) {
    tv.load_preferences(app);
    tv.refresh();
    let _ = tv.sync_status(app);
}

fn on_preferences_changed(app: &mut App<'_>, tv: &mut SonyTVState, values: &Map<String, Value>) {
    if let Some(Value::String(addr)) = values.get("tvAddress") {
        let addr = addr.trim();
        if !addr.is_empty() {
            tv.tv_address = addr.to_string();
        }
    }
    if let Some(Value::Bool(show)) = values.get("showIslandStatus") {
        tv.show_island_status = *show;
        let _ = tv.sync_status(app);
    }
}

/// After a command: the island's mark and, when the panel is open, its page.
fn after_command(app: &mut App<'_>, tv: &SonyTVState, island: &Panel) -> Result<(), ToolError> {
    tv.sync_status(app)?;
    let page = tv.page(app);
    island.render(app, &page);
    Ok(())
}

/// Adds the TV's panels, commands and hooks to `tool`.
fn register(tool: &mut Tool, tv: Tv) {
    let island = {
        let (open_tv, event_tv) = (tv.clone(), tv.clone());
        tool.panel(
            "tv",
            move |app, _panel| {
                let mut tv = open_tv.borrow_mut();
                tv.refresh();
                tv.sync_status(app)?;
                Ok(Some(tv.page(app)))
            },
            move |app, _panel, event| island_event(app, &mut event_tv.borrow_mut(), &event),
        )
    };

    {
        let (open_tv, event_tv) = (tv.clone(), tv.clone());
        tool.panel(
            "settings",
            move |app, _panel| Ok(Some(open_tv.borrow().settings(app))),
            move |app, _panel, event| settings_event(app, &mut event_tv.borrow_mut(), &event),
        );
    }

    {
        let (tv, island) = (tv.clone(), island.clone());
        tool.command("togglePower", move |app| {
            let mut tv = tv.borrow_mut();
            if tv.toggle_power_atomic() {
                notify_safe(app, "tv.fill", "Sony TV woken up")?;
            } else {
                notify_safe(app, "moon.fill", "Sony TV put to sleep")?;
            }
            after_command(app, &tv, &island)
        });
    }
    {
        let (tv, island) = (tv.clone(), island.clone());
        tool.command("startScreensaver", move |app| {
            let mut tv = tv.borrow_mut();
            tv.start_screensaver();
            notify_safe(app, "sparkles.tv", "Started 4K Aerial screensaver")?;
            after_command(app, &tv, &island)
        });
    }
    {
        let (tv, island) = (tv.clone(), island.clone());
        tool.command("openSmartTube", move |app| {
            let mut tv = tv.borrow_mut();
            tv.launch_app("smarttube");
            notify_safe(app, "play.tv", "Opened SmartTube on Sony TV")?;
            after_command(app, &tv, &island)
        });
    }
    {
        let (tv, island) = (tv.clone(), island.clone());
        tool.command("playClipboard", move |app| {
            let mut tv = tv.borrow_mut();
            cast_clipboard_url(app, &mut tv)?;
            after_command(app, &tv, &island)
        });
    }
    {
        let (tv, island) = (tv.clone(), island.clone());
        tool.command("goHome", move |app| {
            let mut tv = tv.borrow_mut();
            tv.launch_app("projectivy");
            notify_safe(app, "house", "Returned to Projectivy Home")?;
            after_command(app, &tv, &island)
        });
    }
    {
        let tv = tv.clone();
        tool.command("muteTV", move |app| {
            tv.borrow_mut()
                .run_adb_shell("input keyevent KEYCODE_VOLUME_MUTE", 0.6);
            notify_safe(app, "speaker.slash", "Toggled Sony TV mute")
        });
    }

    {
        let tv = tv.clone();
        tool.on_start(move |app| on_start(app, &mut tv.borrow_mut()));
    }
    tool.on_preferences_changed(move |app, values| {
        on_preferences_changed(app, &mut tv.borrow_mut(), values)
    });
}

fn main() {
    let mut tool = Tool::new(VERSION);
    register(
        &mut tool,
        Rc::new(RefCell::new(SonyTVState::new(Box::new(SystemAdb)))),
    );
    tool.run();
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::VecDeque;
    use std::io::{self, Cursor, Write};

    /// One adb run the mock saw.
    #[derive(Clone, Debug, PartialEq)]
    struct Call {
        args: Vec<String>,
        timeout: Duration,
        capture: bool,
    }

    /// A stand-in adb: answers from a script in order, and keeps every call.
    #[derive(Clone, Default)]
    struct MockAdb {
        script: Rc<RefCell<VecDeque<Result<AdbOutput, String>>>>,
        calls: Rc<RefCell<Vec<Call>>>,
    }

    impl MockAdb {
        fn answering(script: Vec<Result<AdbOutput, String>>) -> MockAdb {
            MockAdb {
                script: Rc::new(RefCell::new(script.into())),
                calls: Rc::default(),
            }
        }

        fn calls(&self) -> Vec<Call> {
            self.calls.borrow().clone()
        }
    }

    impl AdbRunner for MockAdb {
        fn run(
            &self,
            args: &[&str],
            timeout: Duration,
            capture: bool,
        ) -> Result<AdbOutput, String> {
            self.calls.borrow_mut().push(Call {
                args: args.iter().map(|a| a.to_string()).collect(),
                timeout,
                capture,
            });
            self.script
                .borrow_mut()
                .pop_front()
                .unwrap_or_else(|| Ok(ok("")))
        }
    }

    fn ok(stdout: &str) -> AdbOutput {
        AdbOutput {
            success: true,
            stdout: stdout.to_string(),
        }
    }

    fn failed() -> AdbOutput {
        AdbOutput {
            success: false,
            stdout: String::new(),
        }
    }

    fn live(adb: &MockAdb) -> SonyTVState {
        let mut state = SonyTVState::new(Box::new(adb.clone()));
        state.dry_run = false;
        state
    }

    // is_safe_http_url

    #[test]
    fn safe_url_accepts_http_and_https() {
        assert!(is_safe_http_url(
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
        ));
        assert!(is_safe_http_url("http://192.168.86.31:8080/video.mp4"));
        assert!(is_safe_http_url("HTTPS://example.com"));
        assert!(is_safe_http_url("https://[::1]:8080/x"));
        assert!(is_safe_http_url("https://youtu.be/abc'def"));
    }

    #[test]
    fn safe_url_rejects_injection_and_non_http() {
        assert!(!is_safe_http_url(""));
        assert!(!is_safe_http_url("javascript:alert(1)"));
        assert!(!is_safe_http_url("file:///etc/passwd"));
        assert!(!is_safe_http_url("https://youtu.be/x'; rm -rf /; '"));
        assert!(!is_safe_http_url("https://youtu.be/x\necho injected"));
        assert!(!is_safe_http_url("https://youtu.be/x\techo"));
        assert!(!is_safe_http_url("https://youtu.be/\u{1b}[31m"));
        assert!(!is_safe_http_url("https:example.com"));
        assert!(!is_safe_http_url("https://"));
        assert!(!is_safe_http_url("https:///path"));
        assert!(!is_safe_http_url("ftp://example.com"));
        assert!(!is_safe_http_url("//example.com"));
    }

    #[test]
    fn safe_url_rejects_what_urlsplit_raises_on() {
        assert!(!is_safe_http_url("https://[::1/x"));
        assert!(!is_safe_http_url("https://::1]/x"));
        assert!(!is_safe_http_url("https://[127.0.0.1]/x"));
        assert!(!is_safe_http_url("https://a[::1]/x"));
        assert!(!is_safe_http_url("https://[::1]junk/x"));
    }

    // shlex quoting

    #[test]
    fn shlex_quote_matches_python() {
        assert_eq!(shlex_quote(""), "''");
        assert_eq!(shlex_quote("org.smarttube.stable"), "org.smarttube.stable");
        assert_eq!(
            shlex_quote("com.spocky.projengmenu/.ui.home.MainActivity"),
            "com.spocky.projengmenu/.ui.home.MainActivity"
        );
        assert_eq!(
            shlex_quote("https://youtu.be/x?a=1&b=2"),
            "'https://youtu.be/x?a=1&b=2'"
        );
        assert_eq!(shlex_quote("it's"), "'it'\"'\"'s'");
        assert_eq!(shlex_quote("a b"), "'a b'");
        assert_eq!(shlex_quote("é"), "'é'");
    }

    #[test]
    fn cast_url_quotes_the_url_safely() {
        let adb = MockAdb::default();
        let mut state = live(&adb);
        assert!(state.cast_url("https://youtu.be/abc'def"));
        let calls = adb.calls();
        assert_eq!(calls.len(), 1);
        let cmd = &calls[0].args[3];
        assert!(
            cmd.contains("'https://youtu.be/abc'\"'\"'def'"),
            "unquoted: {cmd}"
        );
        assert!(cmd.ends_with(" org.smarttube.stable"));
        assert!(state.awake);
        assert_eq!(state.foreground, "SmartTube 4K");
    }

    #[test]
    fn cast_url_runs_nothing_for_an_unsafe_clip() {
        let adb = MockAdb::default();
        let mut state = live(&adb);
        assert!(!state.cast_url("javascript:alert(1)"));
        assert!(adb.calls().is_empty());
        assert!(!state.awake);
    }

    // toggle_power_atomic

    #[test]
    fn toggle_power_parses_sleep_and_awake() {
        let adb = MockAdb::answering(vec![
            Ok(ok("POWER_STATE=SLEEP\nMemAvailable:     655360 kB\n")),
            Ok(ok("POWER_STATE=AWAKE\nMemAvailable:     614400 kB")),
        ]);
        let mut state = live(&adb);
        assert!(!state.toggle_power_atomic());
        assert_eq!(state.foreground, STANDBY);
        assert_eq!(state.mem_available_mb, 640);

        assert!(state.toggle_power_atomic());
        assert_eq!(state.foreground, "Projectivy Home");
        assert_eq!(state.mem_available_mb, 600);
        assert_eq!(adb.calls()[0].args[3], TOGGLE_POWER);
        assert_eq!(adb.calls()[0].timeout, Duration::from_secs_f64(0.95));
    }

    #[test]
    fn toggle_power_keeps_state_when_the_tv_says_nothing() {
        let adb = MockAdb::answering(vec![Ok(ok("")), Ok(failed()), Ok(failed())]);
        let mut state = live(&adb);
        state.awake = true;
        state.foreground = "Netflix".to_string();
        state.mem_available_mb = 12;
        assert!(state.toggle_power_atomic());
        assert_eq!(state.foreground, "Netflix");
        assert_eq!(state.mem_available_mb, 12);
    }

    #[test]
    fn toggle_power_in_dry_run_flips_without_adb() {
        let adb = MockAdb::default();
        let mut state = SonyTVState::new(Box::new(adb.clone()));
        state.dry_run = true;
        assert!(state.toggle_power_atomic());
        assert_eq!(state.foreground, "Projectivy Home");
        assert!(!state.toggle_power_atomic());
        assert_eq!(state.foreground, STANDBY);
        assert!(adb.calls().is_empty());
    }

    // parse_status_output

    #[test]
    fn status_output_names_the_foreground_app() {
        let adb = MockAdb::default();
        let mut state = live(&adb);
        let cases = [
            (
                "mWakefulness=Awake\nmCurrentFocus=Window{1 u0 org.smarttube.stable/x}",
                true,
                "SmartTube 4K",
            ),
            (
                "mWakefulness=Dreaming\nmCurrentFocus=Window{1 u0 com.neilturner.aerialviews/x}",
                true,
                "AerialViews 4K",
            ),
            (
                "mWakefulness=Dreaming\nmCurrentFocus=Window{DreamActivity}",
                true,
                "AerialViews 4K",
            ),
            (
                "mWakefulness=Awake\nmCurrentFocus=com.spocky.projengmenu/x",
                true,
                "Projectivy Home",
            ),
            (
                "mWakefulness=Awake\nmCurrentFocus=com.disney.disneyplus/x",
                true,
                "Disney+",
            ),
            (
                "mWakefulness=Awake\nmCurrentFocus=com.netflix.ninja/x",
                true,
                "Netflix",
            ),
            ("mWakefulness=Asleep\nmCurrentFocus=null", false, STANDBY),
            (
                "mWakefulness=Awake\nmCurrentFocus=com.other/x",
                true,
                "Active",
            ),
        ];
        for (out, awake, foreground) in cases {
            state.parse_status_output(out);
            assert_eq!(state.awake, awake, "{out}");
            assert_eq!(state.foreground, foreground, "{out}");
        }
    }

    #[test]
    fn status_output_reads_mem_available() {
        let adb = MockAdb::default();
        let mut state = live(&adb);
        state.parse_status_output("mWakefulness=Awake\nMemAvailable:    1048576 kB");
        assert_eq!(state.mem_available_mb, 1024);
        // A line it cannot read leaves the last value.
        state.parse_status_output("mWakefulness=Awake\nMemAvailable: lots kB");
        assert_eq!(state.mem_available_mb, 1024);
    }

    #[test]
    fn empty_status_output_changes_nothing() {
        let adb = MockAdb::default();
        let mut state = live(&adb);
        state.awake = true;
        state.foreground = "Netflix".to_string();
        state.parse_status_output("");
        assert!(state.awake);
        assert_eq!(state.foreground, "Netflix");
    }

    // run_adb_shell

    #[test]
    fn run_adb_shell_does_not_reconnect_when_connected() {
        let adb = MockAdb::answering(vec![Ok(ok("  mWakefulness=Awake\n"))]);
        let mut state = live(&adb);
        assert_eq!(
            state.run_adb_shell("dumpsys power", 0.85),
            "mWakefulness=Awake"
        );
        assert!(state.connected);
        let calls = adb.calls();
        assert_eq!(calls.len(), 1);
        assert_eq!(
            calls[0].args,
            ["-s", "192.168.86.31:5555", "shell", "dumpsys power"]
        );
        assert_eq!(calls[0].timeout, Duration::from_secs_f64(0.85));
        assert!(calls[0].capture);
    }

    #[test]
    fn run_adb_shell_reconnects_only_on_failure() {
        let adb = MockAdb::answering(vec![
            Ok(failed()),
            Ok(failed()), // `adb connect`'s own exit status is ignored
            Ok(ok("mWakefulness=Awake\n")),
        ]);
        let mut state = live(&adb);
        assert_eq!(
            state.run_adb_shell("dumpsys power", 0.85),
            "mWakefulness=Awake"
        );
        assert!(state.connected);
        let calls = adb.calls();
        assert_eq!(calls.len(), 3);
        assert_eq!(calls[1].args, ["connect", "192.168.86.31:5555"]);
        assert_eq!(calls[1].timeout, Duration::from_secs_f64(0.45));
        assert!(!calls[1].capture);
        assert_eq!(calls[2].args, calls[0].args);
        assert_eq!(calls[2].timeout, Duration::from_secs_f64(0.65));
    }

    #[test]
    fn run_adb_shell_is_disconnected_when_the_retry_fails() {
        let adb = MockAdb::answering(vec![Ok(failed()), Ok(ok("")), Ok(failed())]);
        let mut state = live(&adb);
        state.connected = true;
        assert_eq!(state.run_adb_shell("dumpsys power", 0.85), "");
        assert!(!state.connected);
        assert_eq!(adb.calls().len(), 3);
    }

    #[test]
    fn run_adb_shell_gives_up_at_once_on_a_timeout() {
        let adb = MockAdb::answering(vec![Err("timed out".to_string())]);
        let mut state = live(&adb);
        state.connected = true;
        assert_eq!(state.run_adb_shell("dumpsys power", 0.85), "");
        assert!(!state.connected);
        assert_eq!(adb.calls().len(), 1);
    }

    #[test]
    fn run_adb_shell_gives_up_when_connect_times_out() {
        let adb = MockAdb::answering(vec![Ok(failed()), Err("timed out".to_string())]);
        let mut state = live(&adb);
        assert_eq!(state.run_adb_shell("dumpsys power", 0.85), "");
        assert!(!state.connected);
        assert_eq!(adb.calls().len(), 2);
    }

    #[test]
    fn run_adb_shell_in_dry_run_runs_nothing() {
        let adb = MockAdb::default();
        let mut state = SonyTVState::new(Box::new(adb.clone()));
        state.dry_run = true;
        assert_eq!(state.run_adb_shell("dumpsys power", 0.85), "");
        assert!(state.connected);
        assert!(adb.calls().is_empty());
    }

    #[test]
    fn launch_app_and_switch_input_quote_their_targets() {
        let adb = MockAdb::default();
        let mut state = live(&adb);
        state.launch_app("netflix");
        state.launch_app("projectivy");
        state.launch_app("nope");
        state.switch_input("hdmi3");
        let calls = adb.calls();
        assert_eq!(calls.len(), 3);
        assert_eq!(
            calls[0].args[3],
            "input keyevent KEYCODE_WAKEUP; monkey -p com.netflix.ninja -c android.intent.category.leanback.LAUNCHER 1 >/dev/null 2>&1"
        );
        assert_eq!(
            calls[1].args[3],
            "input keyevent KEYCODE_WAKEUP; am start -n com.spocky.projengmenu/.ui.home.MainActivity"
        );
        assert!(calls[2].args[3].ends_with("SourceHDMI3Activity"));
        assert_eq!(state.selected_app, "projectivy");
        assert_eq!(state.selected_input, "hdmi3");
        assert_eq!(state.foreground, "HDMI 3 (eARC)");
    }

    #[test]
    fn dry_run_follows_the_data_folder_and_env() {
        let adb = MockAdb::default();
        let mut state = SonyTVState::new(Box::new(adb));
        if std::env::var("VITRUVIAN_TV_LIVE").ok().as_deref() != Some("1") {
            state.set_dry_run_for("/tmp/conformance");
            assert!(state.dry_run);
        }
        state.set_dry_run_for("/Users/x/Library/Application Support/com.vitruviansoftware.vitruvian/Tools/dev.vitruvian.tv");
        assert!(!state.dry_run);
    }

    // The whole tool, over a link of two buffers.

    #[derive(Clone, Default)]
    struct Written(Rc<RefCell<Vec<u8>>>);

    impl Write for Written {
        fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
            self.0.borrow_mut().extend_from_slice(bytes);
            Ok(bytes.len())
        }
        fn flush(&mut self) -> io::Result<()> {
            Ok(())
        }
    }

    fn written_lines(written: &Written) -> Vec<Value> {
        String::from_utf8(written.0.borrow().clone())
            .unwrap()
            .lines()
            .map(|line| serde_json::from_str(line).unwrap())
            .collect()
    }

    #[test]
    fn play_clipboard_command_casts_over_a_live_link() {
        let sent = [
            r#"{"jsonrpc":"2.0","id":"hello","method":"initialize","params":{"protocolVersions":["1","2"],"language":"en","dataFolder":"/Users/x/Library/Application Support/tv"}}"#,
            r#"{"jsonrpc":"2.0","id":1,"result":{"value":" 10.0.0.9:5555 "}}"#,
            r#"{"jsonrpc":"2.0","id":2,"result":{"value":true}}"#,
            r#"{"jsonrpc":"2.0","id":"run","method":"command/run","params":{"command":"playClipboard"}}"#,
            r#"{"jsonrpc":"2.0","id":3,"result":{"text":"  https://youtu.be/abc'def\n"}}"#,
            r#"{"jsonrpc":"2.0","id":4,"result":{}}"#,
            r#"{"jsonrpc":"2.0","method":"shutdown"}"#,
        ]
        .join("\n")
            + "\n";
        let adb = MockAdb::answering(vec![
            Ok(ok("mWakefulness=Awake\nMemAvailable: 655360 kB")),
            Ok(ok("")),
        ]);
        let written = Written::default();
        let tv = Rc::new(RefCell::new(SonyTVState::new(Box::new(adb.clone()))));
        let mut tool = Tool::with_link(VERSION, Cursor::new(sent.into_bytes()), written.clone());
        register(&mut tool, tv.clone());
        assert_eq!(tool.serve(), 0);

        let calls = adb.calls();
        assert_eq!(calls.len(), 2, "{calls:?}");
        assert_eq!(calls[0].args[..3], ["-s", "10.0.0.9:5555", "shell"]);
        assert_eq!(calls[0].args[3], STATUS_PROBE);
        assert!(
            calls[1].args[3].contains("-d 'https://youtu.be/abc'\"'\"'def' org.smarttube.stable")
        );

        let lines = written_lines(&written);
        let methods: Vec<&str> = lines.iter().filter_map(|l| l["method"].as_str()).collect();
        assert_eq!(
            methods,
            [
                "storage/get",
                "storage/get",
                "clipboard/readText",
                "notify/hud"
            ]
        );
        let hud = lines.iter().find(|l| l["method"] == "notify/hud").unwrap();
        assert_eq!(hud["params"]["message"], "Playing clipboard URL on Sony TV");
        let answer = lines.iter().find(|l| l["id"] == "run").unwrap();
        assert!(answer.get("error").is_none(), "{answer}");
        assert_eq!(tv.borrow().foreground, "SmartTube 4K");
        assert_eq!(tv.borrow().mem_available_mb, 640);
    }
}
