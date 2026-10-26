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

use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::Duration;

use vitruvian_remote_macagent_metrics::json::{JsonMap, JsonValue};

use crate::http_util::{log_line, HttpRequest, HttpResponse};
use crate::sampler::{find_executable_in_path, run_tool_within};

pub const DEFAULT_TV_ADDRESS: &str = "192.168.86.31:5555";
pub const TV_CMD_TIMEOUT: Duration = Duration::from_secs(5);

pub type TvRunFn =
    dyn Fn(Duration, &str, &[String]) -> (String, String, Option<String>) + Send + Sync;

#[derive(Clone)]
pub struct TVController {
    pub config_path: PathBuf,
    pub legacy_config_path: PathBuf,
    pub find_adb: Arc<dyn Fn() -> String + Send + Sync>,
    pub run: Arc<TvRunFn>,
}

impl TVController {
    pub fn default_controller() -> Self {
        let home = std::env::var("HOME").unwrap_or_default();
        let home_path = PathBuf::from(&home);
        Self {
            config_path: home_path.join(".config").join("vitruvian").join("tv.json"),
            legacy_config_path: home_path
                .join("Library")
                .join("Application Support")
                .join("com.vitruviansoftware.vitruvian")
                .join("ToolData")
                .join("dev.vitruvian.tv")
                .join("storage.json"),
            find_adb: Arc::new(default_find_adb),
            run: Arc::new(|limit, name, args| run_tool_within(limit, name, args, None)),
        }
    }

    pub fn resolve_address(&self) -> String {
        for p in [&self.config_path, &self.legacy_config_path] {
            if p.as_os_str().is_empty() {
                continue;
            }
            let Ok(raw) = std::fs::read(p) else {
                continue;
            };
            let Ok(doc) = JsonValue::parse_bytes(&raw) else {
                continue;
            };
            for key in ["address", "tvAddress"] {
                if let Some(v) = doc.get_opt_str(key) {
                    let trimmed = v.trim();
                    if !trimmed.is_empty() {
                        return trimmed.to_string();
                    }
                }
            }
        }
        DEFAULT_TV_ADDRESS.to_string()
    }

    pub fn state(&self) -> TVState {
        let addr = self.resolve_address();
        let adb = (self.find_adb)();
        if adb.is_empty() {
            return TVState {
                available: false,
                reason: "adb is not installed on this Mac".to_string(),
                connected: false,
                awake: false,
                dreaming: false,
                foreground: "Standby".to_string(),
                mem_available_mb: 0,
                address: addr,
            };
        }

        let status_query = "dumpsys power | grep -E 'mWakefulness=' ; \
            dumpsys window displays | grep -E 'mCurrentFocus|mFocusedApp' ; \
            grep -E 'MemTotal|MemAvailable' /proc/meminfo";
        let args = vec![
            "-s".to_string(),
            addr.clone(),
            "shell".to_string(),
            status_query.to_string(),
        ];
        let (mut out, mut stderr, mut err) = (self.run)(TV_CMD_TIMEOUT, &adb, &args);
        let mut conn_out = String::new();
        if err.is_some() && !stderr.to_ascii_lowercase().contains("unauthorized") {
            let conn_args = vec!["connect".to_string(), addr.clone()];
            let (co, _, _) = (self.run)(TV_CMD_TIMEOUT, &adb, &conn_args);
            conn_out = co;
            let (o2, se2, e2) = (self.run)(TV_CMD_TIMEOUT, &adb, &args);
            out = o2;
            stderr = se2;
            err = e2;
        }
        if err.is_some() || out.trim().is_empty() {
            let mut reason = stderr.trim().to_string();
            if reason.is_empty() {
                reason = conn_out.trim().to_string();
            }
            if reason.is_empty() {
                reason = format!("could not connect to {addr}");
            }
            if reason.to_ascii_lowercase().contains("unauthorized") {
                reason = "TV unauthorized: check 'Always allow from this computer' on the TV screen (or toggle USB debugging off/on in TV Developer Options), then tap Reconnect".to_string();
            }
            return TVState {
                available: true,
                reason,
                connected: false,
                awake: false,
                dreaming: false,
                foreground: "Standby".to_string(),
                mem_available_mb: 0,
                address: addr,
            };
        }

        let awake = out.contains("mWakefulness=Awake");
        let dreaming = out.contains("mWakefulness=Dreaming")
            || out.contains("com.fourchars.lmp")
            || out.contains("Somnambulator");

        let foreground = if !awake && !dreaming {
            "Standby"
        } else if dreaming || out.contains("com.fourchars.lmp") {
            "AerialViews 4K"
        } else if out.contains("com.liskovsoft.smarttubetv") {
            "SmartTube 4K"
        } else if out.contains("com.spocky.projengmenu") {
            "Projectivy Home"
        } else if out.contains("com.disney.disneyplus") {
            "Disney+"
        } else if out.contains("com.netflix.ninja") {
            "Netflix"
        } else {
            "Awake"
        }
        .to_string();

        let mem_mb = parse_mem_available_mb(&out);

        TVState {
            available: true,
            reason: String::new(),
            connected: true,
            awake,
            dreaming,
            foreground,
            mem_available_mb: mem_mb,
            address: addr,
        }
    }

    pub fn act(&self, req: &TVActionRequest) -> Result<(), (u16, String)> {
        let action = req.action.trim();
        let target = req.target.trim();

        if action == "set_address" {
            let raw_addr = if !req.address.trim().is_empty() {
                req.address.trim()
            } else {
                target
            };
            let normalized = validate_tv_address(raw_addr).map_err(|e| (400, e))?;
            self.save_address(&normalized).map_err(|e| (500, e))?;
            let adb = (self.find_adb)();
            if !adb.is_empty() {
                let _ = (self.run)(
                    TV_CMD_TIMEOUT,
                    &adb,
                    &["disconnect".to_string(), normalized.clone()],
                );
                let _ = (self.run)(
                    TV_CMD_TIMEOUT,
                    &adb,
                    &["connect".to_string(), normalized.clone()],
                );
            }
            log_line(&format!("act tv: set_address {normalized}"));
            return Ok(());
        }

        let adb = (self.find_adb)();
        if adb.is_empty() {
            return Err((503, "adb is not installed on this Mac".to_string()));
        }
        let mut addr = self.resolve_address();

        match action {
            "reconnect" => {
                let raw_addr = first_non_empty(&req.address, target);
                if !raw_addr.is_empty() {
                    let normalized = validate_tv_address(&raw_addr).map_err(|e| (400, e))?;
                    self.save_address(&normalized).map_err(|e| (500, e))?;
                    addr = normalized;
                }
                log_line(&format!("act tv: reconnect {addr}"));
                let _ = (self.run)(
                    TV_CMD_TIMEOUT,
                    &adb,
                    &["disconnect".to_string(), addr.clone()],
                );
                let _ = (self.run)(TV_CMD_TIMEOUT, &adb, &["connect".to_string(), addr]);
                Ok(())
            }
            "toggle_power" => {
                let _ = (self.run)(TV_CMD_TIMEOUT, &adb, &["connect".to_string(), addr.clone()]);
                let (out, _, _) = (self.run)(
                    TV_CMD_TIMEOUT,
                    &adb,
                    &[
                        "-s".to_string(),
                        addr.clone(),
                        "shell".to_string(),
                        "dumpsys power | grep mWakefulness=".to_string(),
                    ],
                );
                let key = if out.contains("mWakefulness=Awake")
                    || out.contains("mWakefulness=Dreaming")
                {
                    "KEYCODE_SLEEP"
                } else {
                    "KEYCODE_WAKEUP"
                };
                log_line(&format!("act tv: toggle_power ({key}) on {addr}"));
                let (_, stderr, err) = (self.run)(
                    TV_CMD_TIMEOUT,
                    &adb,
                    &[
                        "-s".to_string(),
                        addr,
                        "shell".to_string(),
                        "input".to_string(),
                        "keyevent".to_string(),
                        key.to_string(),
                    ],
                );
                if let Some(e) = err {
                    return Err((
                        502,
                        format!("adb toggle_power failed: {}", first_non_empty(&stderr, &e)),
                    ));
                }
                Ok(())
            }
            "start_aerial" => {
                let _ = (self.run)(TV_CMD_TIMEOUT, &adb, &["connect".to_string(), addr.clone()]);
                log_line(&format!("act tv: start_aerial on {addr}"));
                let cmd =
                    "input keyevent KEYCODE_WAKEUP && am start -n com.android.systemui/.Somnambulator";
                let (_, stderr, err) = (self.run)(
                    TV_CMD_TIMEOUT,
                    &adb,
                    &["-s".to_string(), addr, "shell".to_string(), cmd.to_string()],
                );
                if let Some(e) = err {
                    return Err((
                        502,
                        format!("adb start_aerial failed: {}", first_non_empty(&stderr, &e)),
                    ));
                }
                Ok(())
            }
            "launch_app" => {
                let pkg = match target {
                    "projectivy" => "com.spocky.projengmenu",
                    "smarttube" => "com.liskovsoft.smarttubetv.beta",
                    "disney" => "com.disney.disneyplus",
                    "netflix" => "com.netflix.ninja",
                    _ => {
                        return Err((
                            400,
                            format!(
                                "unknown app target {target:?} (want projectivy, smarttube, disney, or netflix)"
                            ),
                        ))
                    }
                };
                let _ = (self.run)(TV_CMD_TIMEOUT, &adb, &["connect".to_string(), addr.clone()]);
                log_line(&format!("act tv: launch_app {target} ({pkg}) on {addr}"));
                let cmd = format!(
                    "input keyevent KEYCODE_WAKEUP && monkey -p {pkg} -c android.intent.category.LAUNCHER 1"
                );
                let (_, stderr, err) = (self.run)(
                    TV_CMD_TIMEOUT,
                    &adb,
                    &["-s".to_string(), addr, "shell".to_string(), cmd],
                );
                if let Some(e) = err {
                    return Err((
                        502,
                        format!("adb launch_app failed: {}", first_non_empty(&stderr, &e)),
                    ));
                }
                Ok(())
            }
            "hdmi" => {
                if !matches!(target, "1" | "2" | "3" | "4") {
                    return Err((
                        400,
                        format!("unknown hdmi target {target:?} (want 1, 2, 3, or 4)"),
                    ));
                }
                let _ = (self.run)(TV_CMD_TIMEOUT, &adb, &["connect".to_string(), addr.clone()]);
                log_line(&format!("act tv: hdmi {target} on {addr}"));
                let uri = format!(
                    "content://android.media.tv/passthrough/com.sony.dtv.tvinput.external/.ExternalTvInputService%2FHW{target}"
                );
                let cmd = format!(
                    "input keyevent KEYCODE_WAKEUP && am start -a android.intent.action.VIEW -d {uri}"
                );
                let (_, stderr, err) = (self.run)(
                    TV_CMD_TIMEOUT,
                    &adb,
                    &["-s".to_string(), addr, "shell".to_string(), cmd],
                );
                if let Some(e) = err {
                    return Err((
                        502,
                        format!("adb hdmi failed: {}", first_non_empty(&stderr, &e)),
                    ));
                }
                Ok(())
            }
            "key" => {
                let code = match target {
                    "volume_up" => "24",
                    "volume_down" => "25",
                    "mute" => "164",
                    "play_pause" => "85",
                    "home" => "3",
                    "back" => "4",
                    "up" => "19",
                    "down" => "20",
                    "left" => "21",
                    "right" => "22",
                    "select" => "23",
                    _ => return Err((400, format!("unknown key target {target:?}"))),
                };
                let _ = (self.run)(TV_CMD_TIMEOUT, &adb, &["connect".to_string(), addr.clone()]);
                log_line(&format!("act tv: key {target} ({code}) on {addr}"));
                let (_, stderr, err) = (self.run)(
                    TV_CMD_TIMEOUT,
                    &adb,
                    &[
                        "-s".to_string(),
                        addr,
                        "shell".to_string(),
                        "input".to_string(),
                        "keyevent".to_string(),
                        code.to_string(),
                    ],
                );
                if let Some(e) = err {
                    return Err((
                        502,
                        format!("adb key failed: {}", first_non_empty(&stderr, &e)),
                    ));
                }
                Ok(())
            }
            "cast_url" => {
                let raw_url = if !req.url.trim().is_empty() {
                    req.url.trim()
                } else {
                    target
                };
                let quoted = validate_and_quote_cast_url(raw_url).map_err(|e| (400, e))?;
                let _ = (self.run)(TV_CMD_TIMEOUT, &adb, &["connect".to_string(), addr.clone()]);
                log_line(&format!("act tv: cast_url on {addr}"));
                let cmd = format!(
                    "input keyevent KEYCODE_WAKEUP && am start -a android.intent.action.VIEW -d {quoted} com.liskovsoft.smarttubetv.beta"
                );
                let (_, stderr, err) = (self.run)(
                    TV_CMD_TIMEOUT,
                    &adb,
                    &["-s".to_string(), addr, "shell".to_string(), cmd],
                );
                if let Some(e) = err {
                    return Err((
                        502,
                        format!("adb cast_url failed: {}", first_non_empty(&stderr, &e)),
                    ));
                }
                Ok(())
            }
            "trim_caches" => {
                let _ = (self.run)(TV_CMD_TIMEOUT, &adb, &["connect".to_string(), addr.clone()]);
                log_line(&format!("act tv: trim_caches on {addr}"));
                let (_, stderr, err) = (self.run)(
                    TV_CMD_TIMEOUT,
                    &adb,
                    &[
                        "-s".to_string(),
                        addr,
                        "shell".to_string(),
                        "pm".to_string(),
                        "trim-caches".to_string(),
                        "999999999999999999".to_string(),
                    ],
                );
                if let Some(e) = err {
                    return Err((
                        502,
                        format!("adb trim_caches failed: {}", first_non_empty(&stderr, &e)),
                    ));
                }
                Ok(())
            }
            _ => Err((400, format!("unknown action {action:?}"))),
        }
    }

    fn save_address(&self, addr: &str) -> Result<(), String> {
        if self.config_path.as_os_str().is_empty() {
            return Err("no config path configured".to_string());
        }
        if let Some(parent) = self.config_path.parent() {
            std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
        }
        let mut doc = JsonMap::new();
        if let Ok(existing) = std::fs::read(&self.config_path) {
            if let Ok(JsonValue::Object(m)) = JsonValue::parse_bytes(&existing) {
                doc = m;
            }
        }
        doc.insert("address".to_string(), JsonValue::String(addr.to_string()));
        let mut data = JsonValue::Object(doc).to_json_pretty();
        data.push('\n');
        std::fs::write(&self.config_path, data.as_bytes()).map_err(|e| e.to_string())
    }
}

pub fn default_find_adb() -> String {
    let home = std::env::var("HOME").unwrap_or_default();
    let candidates = [
        "/opt/homebrew/bin/adb".to_string(),
        "/usr/local/bin/adb".to_string(),
        format!("{home}/Library/Android/sdk/platform-tools/adb"),
    ];
    for p in &candidates {
        if is_executable(Path::new(p)) {
            return p.clone();
        }
    }
    find_executable_in_path("adb").unwrap_or_default()
}

fn is_executable(p: &Path) -> bool {
    if let Ok(meta) = std::fs::metadata(p) {
        if meta.is_file() {
            #[cfg(unix)]
            {
                use std::os::unix::fs::PermissionsExt;
                return meta.permissions().mode() & 0o111 != 0;
            }
            #[cfg(not(unix))]
            return true;
        }
    }
    false
}

fn parse_mem_available_mb(out: &str) -> i64 {
    for line in out.lines() {
        if let Some(rest) = line.trim().strip_prefix("MemAvailable:") {
            let num_str = rest.trim().split_whitespace().next().unwrap_or("");
            if let Ok(kb) = num_str.parse::<i64>() {
                return kb / 1024;
            }
        }
    }
    0
}

#[derive(Debug, Clone, PartialEq)]
pub struct TVState {
    pub available: bool,
    pub reason: String,
    pub connected: bool,
    pub awake: bool,
    pub dreaming: bool,
    pub foreground: String,
    pub mem_available_mb: i64,
    pub address: String,
}

impl TVState {
    pub fn to_json_value(&self) -> JsonValue {
        let mut m = JsonMap::new();
        m.insert("available".to_string(), JsonValue::Bool(self.available));
        if !self.reason.is_empty() {
            m.insert("reason".to_string(), JsonValue::String(self.reason.clone()));
        }
        m.insert("connected".to_string(), JsonValue::Bool(self.connected));
        m.insert("awake".to_string(), JsonValue::Bool(self.awake));
        m.insert("dreaming".to_string(), JsonValue::Bool(self.dreaming));
        m.insert(
            "foreground".to_string(),
            JsonValue::String(self.foreground.clone()),
        );
        m.insert(
            "mem_available_mb".to_string(),
            JsonValue::from_i64(self.mem_available_mb),
        );
        m.insert(
            "address".to_string(),
            JsonValue::String(self.address.clone()),
        );
        JsonValue::Object(m)
    }

    pub fn from_json_value(v: &JsonValue) -> Option<Self> {
        Some(Self {
            available: v.get_bool("available"),
            reason: v.get_str("reason").to_string(),
            connected: v.get_bool("connected"),
            awake: v.get_bool("awake"),
            dreaming: v.get_bool("dreaming"),
            foreground: v.get_str("foreground").to_string(),
            mem_available_mb: v.get_i64("mem_available_mb"),
            address: v.get_str("address").to_string(),
        })
    }
}

#[derive(Debug, Clone, Default)]
pub struct TVActionRequest {
    pub action: String,
    pub target: String,
    pub url: String,
    pub address: String,
}

impl TVActionRequest {
    pub fn from_json_value(v: &JsonValue) -> Result<Self, String> {
        let obj = v.as_object().ok_or("expected JSON object")?;
        Ok(Self {
            action: obj
                .get("action")
                .and_then(|x| x.as_str())
                .unwrap_or("")
                .to_string(),
            target: obj
                .get("target")
                .and_then(|x| x.as_str())
                .unwrap_or("")
                .to_string(),
            url: obj
                .get("url")
                .and_then(|x| x.as_str())
                .unwrap_or("")
                .to_string(),
            address: obj
                .get("address")
                .and_then(|x| x.as_str())
                .unwrap_or("")
                .to_string(),
        })
    }
}

pub fn validate_tv_address(addr: &str) -> Result<String, String> {
    if addr.is_empty() {
        return Err("address is required (expected host:port)".to_string());
    }
    let Some((host, port_str)) = addr.rsplit_once(':') else {
        return Err("address must be host:port (e.g. 192.168.86.31:5555)".to_string());
    };
    if host.is_empty()
        || !host
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '.' || c == '-')
    {
        return Err("invalid host in address".to_string());
    }
    let port: i64 = port_str
        .parse()
        .map_err(|_| "port must be between 1 and 65535".to_string())?;
    if !(1..=65535).contains(&port) {
        return Err("port must be between 1 and 65535".to_string());
    }
    Ok(format!("{host}:{port}"))
}

pub fn validate_and_quote_cast_url(raw: &str) -> Result<String, String> {
    if raw.is_empty() {
        return Err("url is required".to_string());
    }
    if raw.chars().any(|r| r.is_whitespace() || r.is_control()) {
        return Err("url must not contain whitespace or control characters".to_string());
    }
    let rest = if let Some(r) = raw.strip_prefix("http://") {
        r
    } else if let Some(r) = raw.strip_prefix("https://") {
        r
    } else {
        return Err("url must be a valid http or https URL".to_string());
    };
    let host = rest.split('/').next().unwrap_or("");
    if host.is_empty() {
        return Err("url must be a valid http or https URL".to_string());
    }
    Ok(format!("'{}'", raw.replace('\'', r"'\''")))
}

fn first_non_empty(a: &str, b: &str) -> String {
    let sa = a.trim();
    if !sa.is_empty() {
        return sa.to_string();
    }
    b.trim().to_string()
}

pub fn handle_tv_get(tv: &TVController) -> HttpResponse {
    HttpResponse::json(200, &tv.state().to_json_value())
}

pub fn handle_tv_post(req: &HttpRequest, tv: &TVController) -> HttpResponse {
    let parsed = match req.json() {
        Ok(v) => v,
        Err(e) => return HttpResponse::error(400, &e),
    };
    let action_req = match TVActionRequest::from_json_value(&parsed) {
        Ok(r) => r,
        Err(e) => return HttpResponse::error(400, &e),
    };
    if let Err((code, msg)) = tv.act(&action_req) {
        return HttpResponse::error(code, &msg);
    }
    HttpResponse::json(200, &tv.state().to_json_value())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::http_util::{http_request, parse_bearer, TestServer};
    use crate::pair::Store;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::Mutex;

    static NEXT_TV_DIR: AtomicUsize = AtomicUsize::new(0);

    fn temp_dir() -> PathBuf {
        let id = NEXT_TV_DIR.fetch_add(1, Ordering::SeqCst);
        let dir =
            std::env::temp_dir().join(format!("macagent-tv-test-{}-{}", std::process::id(), id));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[derive(Debug, Clone)]
    struct RecordedTVCall {
        #[allow(dead_code)]
        name: String,
        args: Vec<String>,
    }

    struct TvHarnessState {
        calls: Vec<RecordedTVCall>,
        adb_path: String,
        status_out: String,
        status_stderr: String,
        status_err: Option<String>,
        connect_out: String,
    }

    struct TvTestHarness {
        tv: TVController,
        token: String,
        state: Arc<Mutex<TvHarnessState>>,
        server: TestServer,
    }

    impl TvTestHarness {
        fn new() -> Self {
            let dir = temp_dir();
            let store = Store::new(dir.join("store"));
            let token = store.ensure_token().unwrap();
            let state = Arc::new(Mutex::new(TvHarnessState {
                calls: Vec::new(),
                adb_path: "/opt/homebrew/bin/adb".to_string(),
                connect_out: "connected to 192.168.86.31:5555\n".to_string(),
                status_out: "  mWakefulness=Awake\n  mCurrentFocus=Window{123 u0 com.spocky.projengmenu/com.spocky.projengmenu.ui.home.MainActivity}\nMemTotal:        3014656 kB\nMemAvailable:    1048576 kB\n".to_string(),
                status_stderr: String::new(),
                status_err: None,
            }));

            let st_adb = Arc::clone(&state);
            let st_run = Arc::clone(&state);

            let tv = TVController {
                config_path: dir.join("tv.json"),
                legacy_config_path: dir.join("storage.json"),
                find_adb: Arc::new(move || st_adb.lock().unwrap().adb_path.clone()),
                run: Arc::new(move |_, name, args| {
                    let mut st = st_run.lock().unwrap();
                    st.calls.push(RecordedTVCall {
                        name: name.to_string(),
                        args: args.to_vec(),
                    });
                    if args.first().map(|s| s.as_str()) == Some("connect") {
                        return (st.connect_out.clone(), String::new(), None);
                    }
                    if args.len() >= 4 && args[2] == "shell" && args[3].contains("MemAvailable") {
                        if let Some(err) = &st.status_err {
                            let stderr = if st.status_stderr.is_empty() {
                                "device offline".to_string()
                            } else {
                                st.status_stderr.clone()
                            };
                            return (String::new(), stderr, Some(err.clone()));
                        }
                        return (st.status_out.clone(), String::new(), None);
                    }
                    if args.len() >= 4
                        && args[2] == "shell"
                        && args[3].contains("dumpsys power | grep mWakefulness=")
                    {
                        return (st.status_out.clone(), String::new(), None);
                    }
                    ("ok\n".to_string(), String::new(), None)
                }),
            };

            let tv_srv = tv.clone();
            let store_srv = store.clone();
            let server = TestServer::start(move |req: &HttpRequest| {
                if req.path != "/v1/tv" {
                    return HttpResponse::error(404, "not found");
                }
                match req.method.as_str() {
                    "GET" | "HEAD" => handle_tv_get(&tv_srv),
                    "POST" => {
                        let Some(tok) = parse_bearer(req) else {
                            return HttpResponse::error(401, "missing bearer token");
                        };
                        if !store_srv.authorized(tok) {
                            return HttpResponse::error(403, "invalid bearer token");
                        }
                        handle_tv_post(req, &tv_srv)
                    }
                    _ => HttpResponse::method_not_allowed("GET, HEAD, POST"),
                }
            });

            Self {
                tv,
                token,
                state,
                server,
            }
        }

        fn get_state(&self) -> TVState {
            let url = format!("{}/v1/tv", self.server.url());
            let (status, _, body) =
                http_request("GET", &url, &[], None, Duration::from_secs(5)).unwrap();
            assert_eq!(status, 200);
            let v = JsonValue::parse_bytes(&body).unwrap();
            TVState::from_json_value(&v).unwrap()
        }

        fn post(&self, token: &str, body: &str) -> (u16, JsonValue) {
            let url = format!("{}/v1/tv", self.server.url());
            let mut headers = vec![("Content-Type", "application/json")];
            let auth = format!("Bearer {token}");
            if !token.is_empty() {
                headers.push(("Authorization", &auth));
            }
            let (status, _, resp_body) = http_request(
                "POST",
                &url,
                &headers,
                Some(body.as_bytes()),
                Duration::from_secs(5),
            )
            .unwrap();
            let j = JsonValue::parse_bytes(&resp_body).unwrap_or(JsonValue::Null);
            (status, j)
        }
    }

    fn has_args(calls: &[RecordedTVCall], suffix: &[&str]) -> bool {
        calls.iter().any(|c| {
            if c.args.len() < suffix.len() {
                return false;
            }
            let tail = &c.args[c.args.len() - suffix.len()..];
            tail.iter().zip(suffix.iter()).all(|(a, b)| a == b)
        })
    }

    fn has_arg_substring(calls: &[RecordedTVCall], sub: &str) -> bool {
        calls.iter().any(|c| c.args.iter().any(|a| a.contains(sub)))
    }

    #[test]
    fn test_tv_state_when_adb_is_missing() {
        let h = TvTestHarness::new();
        h.state.lock().unwrap().adb_path = String::new();

        let st = h.get_state();
        assert!(!st.available);
        assert!(st.reason.contains("adb"));
        assert_eq!(st.address, DEFAULT_TV_ADDRESS);
    }

    #[test]
    fn test_tv_state_parses_foreground_apps_and_memory() {
        let h = TvTestHarness::new();
        let st = h.get_state();
        assert!(st.available && st.connected && st.awake && !st.dreaming);
        assert_eq!(st.foreground, "Projectivy Home");
        assert_eq!(st.mem_available_mb, 1024);

        let cases = [
            (
                "SmartTube",
                "mWakefulness=Awake\nmCurrentFocus=Window{1 u0 com.liskovsoft.smarttubetv.beta}\nMemAvailable: 524288 kB\n",
                true,
                false,
                "SmartTube 4K",
            ),
            (
                "AerialViews dreaming",
                "mWakefulness=Dreaming\nmCurrentFocus=Window{1 u0 com.fourchars.lmp}\n",
                false,
                true,
                "AerialViews 4K",
            ),
            (
                "Disney+",
                "mWakefulness=Awake\nmCurrentFocus=Window{1 u0 com.disney.disneyplus}\n",
                true,
                false,
                "Disney+",
            ),
            (
                "Netflix",
                "mWakefulness=Awake\nmCurrentFocus=Window{1 u0 com.netflix.ninja}\n",
                true,
                false,
                "Netflix",
            ),
            ("Standby", "mWakefulness=Asleep\n", false, false, "Standby"),
        ];

        for (name, out, want_awake, want_dreaming, want_fg) in cases {
            h.state.lock().unwrap().status_out = out.to_string();
            let got = h.get_state();
            assert_eq!(got.awake, want_awake, "{name}");
            assert_eq!(got.dreaming, want_dreaming, "{name}");
            assert_eq!(got.foreground, want_fg, "{name}");
        }
    }

    #[test]
    fn test_tv_state_when_disconnected() {
        let h = TvTestHarness::new();
        {
            let mut st = h.state.lock().unwrap();
            st.connect_out = "failed to connect to 192.168.86.31:5555".to_string();
            st.status_err = Some("exit status 1".to_string());
        }
        let st = h.get_state();
        assert!(st.available && !st.connected);
        assert_eq!(st.foreground, "Standby");
        assert!(!st.reason.is_empty());

        h.state.lock().unwrap().status_stderr =
            "adb: device unauthorized.\nThis adb server's $ADB_VENDOR_KEYS is not set".to_string();
        let st2 = h.get_state();
        assert!(st2.reason.contains("TV unauthorized"));
    }

    #[test]
    fn test_tv_address_fallback_and_set_address() {
        let h = TvTestHarness::new();
        std::fs::write(
            &h.tv.legacy_config_path,
            r#"{"tvAddress":"192.168.86.99:5555"}"#,
        )
        .unwrap();
        assert_eq!(h.get_state().address, "192.168.86.99:5555");

        let (unauth_status, _) = h.post(
            "",
            r#"{"action":"set_address","address":"192.168.86.42:5555"}"#,
        );
        assert_eq!(unauth_status, 401);

        let (status, body) = h.post(
            &h.token,
            r#"{"action":"set_address","address":"192.168.86.42:5555"}"#,
        );
        assert_eq!(status, 200);
        let st = TVState::from_json_value(&body).unwrap();
        assert_eq!(st.address, "192.168.86.42:5555");

        for bad in ["", "192.168.86.42", "bad host:5555", "192.168.86.42:99999"] {
            let (s, _) = h.post(
                &h.token,
                &format!(r#"{{"action":"set_address","address":"{bad}"}}"#),
            );
            assert_eq!(s, 400, "{bad}");
        }
    }

    #[test]
    fn test_tv_actions_dispatch_expected_adb_commands() {
        let h = TvTestHarness::new();

        // 1. toggle_power when Awake -> KEYCODE_SLEEP
        h.state.lock().unwrap().calls.clear();
        let (s, _) = h.post(&h.token, r#"{"action":"toggle_power"}"#);
        assert_eq!(s, 200);
        assert!(has_args(
            &h.state.lock().unwrap().calls,
            &["shell", "input", "keyevent", "KEYCODE_SLEEP"]
        ));

        // 2. toggle_power when Asleep -> KEYCODE_WAKEUP
        {
            let mut st = h.state.lock().unwrap();
            st.status_out = "mWakefulness=Asleep\n".to_string();
            st.calls.clear();
        }
        let (s, _) = h.post(&h.token, r#"{"action":"toggle_power"}"#);
        assert_eq!(s, 200);
        assert!(has_args(
            &h.state.lock().unwrap().calls,
            &["shell", "input", "keyevent", "KEYCODE_WAKEUP"]
        ));

        // 3. start_aerial
        h.state.lock().unwrap().calls.clear();
        let (s, _) = h.post(&h.token, r#"{"action":"start_aerial"}"#);
        assert_eq!(s, 200);
        assert!(has_arg_substring(
            &h.state.lock().unwrap().calls,
            "com.android.systemui/.Somnambulator"
        ));

        // 4. launch_app
        h.state.lock().unwrap().calls.clear();
        let (s, _) = h.post(&h.token, r#"{"action":"launch_app","target":"smarttube"}"#);
        assert_eq!(s, 200);
        assert!(has_arg_substring(
            &h.state.lock().unwrap().calls,
            "monkey -p com.liskovsoft.smarttubetv.beta -c android.intent.category.LAUNCHER 1"
        ));

        // 5. hdmi
        h.state.lock().unwrap().calls.clear();
        let (s, _) = h.post(&h.token, r#"{"action":"hdmi","target":"2"}"#);
        assert_eq!(s, 200);
        assert!(has_arg_substring(
            &h.state.lock().unwrap().calls,
            "ExternalTvInputService%2FHW2"
        ));

        // 6. key
        h.state.lock().unwrap().calls.clear();
        let (s, _) = h.post(&h.token, r#"{"action":"key","target":"volume_up"}"#);
        assert_eq!(s, 200);
        assert!(has_args(
            &h.state.lock().unwrap().calls,
            &["shell", "input", "keyevent", "24"]
        ));

        // 7. cast_url
        h.state.lock().unwrap().calls.clear();
        let (s, _) = h.post(
            &h.token,
            r#"{"action":"cast_url","url":"https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=10s"}"#,
        );
        assert_eq!(s, 200);
        assert!(has_arg_substring(
            &h.state.lock().unwrap().calls,
            "'https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=10s' com.liskovsoft.smarttubetv.beta"
        ));

        for bad_url in ["", "javascript:alert(1)", "https://example.com/a b"] {
            let (bs, _) = h.post(
                &h.token,
                &format!(r#"{{"action":"cast_url","url":"{bad_url}"}}"#),
            );
            assert_eq!(bs, 400, "{bad_url}");
        }

        // 8. trim_caches
        h.state.lock().unwrap().calls.clear();
        let (s, _) = h.post(&h.token, r#"{"action":"trim_caches"}"#);
        assert_eq!(s, 200);
        assert!(has_args(
            &h.state.lock().unwrap().calls,
            &["shell", "pm", "trim-caches", "999999999999999999"]
        ));

        // 9. reconnect
        h.state.lock().unwrap().calls.clear();
        let (s, _) = h.post(&h.token, r#"{"action":"reconnect"}"#);
        assert_eq!(s, 200);
        assert!(has_args(
            &h.state.lock().unwrap().calls,
            &["disconnect", DEFAULT_TV_ADDRESS]
        ));
        assert!(has_args(
            &h.state.lock().unwrap().calls,
            &["connect", DEFAULT_TV_ADDRESS]
        ));
    }
}
