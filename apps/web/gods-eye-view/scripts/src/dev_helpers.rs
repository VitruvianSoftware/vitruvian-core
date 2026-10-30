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

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Preset {
    Fresh,
    Cctv,
    Secure,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum OpenSkyAuthMode {
    Basic,
    OAuth,
    Auto,
    Anon,
}

pub fn parse_opensky_auth_mode(s: &str) -> OpenSkyAuthMode {
    match s.trim().to_ascii_lowercase().as_str() {
        "basic" => OpenSkyAuthMode::Basic,
        "oauth" => OpenSkyAuthMode::OAuth,
        "auto" => OpenSkyAuthMode::Auto,
        "anon" => OpenSkyAuthMode::Anon,
        _ => {
            eprintln!(
                "warning: invalid OPENSKY_AUTH_MODE='{}', defaulting to 'oauth'",
                s
            );
            OpenSkyAuthMode::OAuth
        }
    }
}

impl std::fmt::Display for OpenSkyAuthMode {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Basic => write!(f, "basic"),
            Self::OAuth => write!(f, "oauth"),
            Self::Auto => write!(f, "auto"),
            Self::Anon => write!(f, "anon"),
        }
    }
}

#[derive(Debug, Clone)]
pub struct CctvConfig {
    pub sources_file: String,
    pub prefer_austin: String,
    pub austin_max_sources: String,
    pub caltrans_districts: String,
    pub caltrans_max_sources: String,
    pub tfl_enabled: String,
    pub tfl_max_sources: String,
    pub ontario_enabled: String,
    pub ontario_max_sources: String,
    pub fintraffic_enabled: String,
    pub fintraffic_max_sources: String,
    pub drivebc_enabled: String,
    pub drivebc_max_sources: String,
    pub txdot_enabled: String,
    pub txdot_districts: String,
    pub txdot_max_sources: String,
    pub tallinn_enabled: String,
    pub tallinn_max_sources: String,
    pub tarktee_enabled: String,
    pub tarktee_max_sources: String,
    pub warendorf_enabled: String,
    pub nsw_enabled: String,
    pub nsw_max_sources: String,
    pub calgary_enabled: String,
    pub calgary_max_sources: String,
    pub max_sources: String,
}

pub fn default_cctv_config(preset: Preset) -> CctvConfig {
    match preset {
        Preset::Fresh => CctvConfig {
            sources_file: String::new(),
            prefer_austin: String::new(),
            austin_max_sources: "250".into(),
            caltrans_districts: "4,7,11,3".into(),
            caltrans_max_sources: "300".into(),
            tfl_enabled: "1".into(),
            tfl_max_sources: "250".into(),
            ontario_enabled: "1".into(),
            ontario_max_sources: "1000".into(),
            fintraffic_enabled: "1".into(),
            fintraffic_max_sources: "300".into(),
            drivebc_enabled: "1".into(),
            drivebc_max_sources: "250".into(),
            txdot_enabled: "1".into(),
            txdot_districts: "AUS,SAT".into(),
            txdot_max_sources: "500".into(),
            tallinn_enabled: "1".into(),
            tallinn_max_sources: "255".into(),
            tarktee_enabled: "1".into(),
            tarktee_max_sources: "179".into(),
            warendorf_enabled: "1".into(),
            nsw_enabled: "1".into(),
            nsw_max_sources: "250".into(),
            calgary_enabled: "1".into(),
            calgary_max_sources: "220".into(),
            max_sources: "4000".into(),
        },
        Preset::Cctv => CctvConfig {
            sources_file: "config/cctv_sources.austin.json".into(),
            prefer_austin: "1".into(),
            austin_max_sources: "36".into(),
            caltrans_districts: String::new(),
            caltrans_max_sources: String::new(),
            tfl_enabled: String::new(),
            tfl_max_sources: String::new(),
            ontario_enabled: String::new(),
            ontario_max_sources: String::new(),
            fintraffic_enabled: String::new(),
            fintraffic_max_sources: String::new(),
            drivebc_enabled: String::new(),
            drivebc_max_sources: String::new(),
            txdot_enabled: String::new(),
            txdot_districts: String::new(),
            txdot_max_sources: String::new(),
            tallinn_enabled: String::new(),
            tallinn_max_sources: String::new(),
            tarktee_enabled: String::new(),
            tarktee_max_sources: String::new(),
            warendorf_enabled: String::new(),
            nsw_enabled: String::new(),
            nsw_max_sources: String::new(),
            calgary_enabled: String::new(),
            calgary_max_sources: String::new(),
            max_sources: "48".into(),
        },
        Preset::Secure => CctvConfig {
            sources_file: String::new(),
            prefer_austin: String::new(),
            austin_max_sources: "36".into(),
            caltrans_districts: String::new(),
            caltrans_max_sources: String::new(),
            tfl_enabled: String::new(),
            tfl_max_sources: String::new(),
            ontario_enabled: String::new(),
            ontario_max_sources: String::new(),
            fintraffic_enabled: String::new(),
            fintraffic_max_sources: String::new(),
            drivebc_enabled: String::new(),
            drivebc_max_sources: String::new(),
            txdot_enabled: String::new(),
            txdot_districts: String::new(),
            txdot_max_sources: String::new(),
            tallinn_enabled: String::new(),
            tallinn_max_sources: String::new(),
            tarktee_enabled: String::new(),
            tarktee_max_sources: String::new(),
            warendorf_enabled: String::new(),
            nsw_enabled: String::new(),
            nsw_max_sources: String::new(),
            calgary_enabled: String::new(),
            calgary_max_sources: String::new(),
            max_sources: "48".into(),
        },
    }
}

pub fn parse_dotenv_value(content: &str, key: &str) -> Option<String> {
    for line in content.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }
        if let Some(eq_pos) = trimmed.find('=') {
            let k = trimmed[..eq_pos].trim();
            if k == key {
                let v = trimmed[eq_pos + 1..].trim();
                if v.len() >= 2
                    && ((v.starts_with('"') && v.ends_with('"'))
                        || (v.starts_with('\'') && v.ends_with('\'')))
                {
                    return Some(v[1..v.len() - 1].to_string());
                }
                return Some(v.to_string());
            }
        }
    }
    None
}

pub fn read_dotenv_value(root: &Path, key: &str) -> String {
    let files = [
        ".env.development.local",
        ".env.development",
        ".env.local",
        ".env",
    ];
    for filename in &files {
        let path = root.join(filename);
        if let Ok(content) = std::fs::read_to_string(&path) {
            if let Some(value) = parse_dotenv_value(&content, key) {
                return value;
            }
        }
    }
    String::new()
}

const TRACKED_KEY_NAMES: &[&str] = &[
    "GOOGLE_MAPS_API_KEY",
    "GOOGLE_MAPS_SERVER_API_KEY",
    "CESIUM_ION_TOKEN",
    "OPENAI_API_KEY",
    "AISSTREAM_API_KEY",
    "FIRMS_MAP_KEY",
    "TOMTOM_API_KEY",
    "OPENSKY_CLIENT_ID",
    "OPENSKY_CLIENT_SECRET",
    "LL2_API_TOKEN",
];

pub fn track_external_keys(get_env: &dyn Fn(&str) -> Option<String>) -> Vec<String> {
    TRACKED_KEY_NAMES
        .iter()
        .filter(|&&k| get_env(k).filter(|v| !v.is_empty()).is_some())
        .map(|&k| k.to_string())
        .collect()
}

pub fn external_keys_csv(keys: &[String]) -> String {
    keys.join(",")
}

#[derive(Debug, Clone)]
pub struct OpenSkyState {
    pub auth_mode: OpenSkyAuthMode,
    pub client_id: String,
    pub client_secret: String,
    pub username: String,
    pub password: String,
    pub credentials_file: String,
}

pub fn resolve_opensky_credentials(
    auth_mode_str: &str,
    get_dotenv: &dyn Fn(&str) -> String,
    get_keychain: &dyn Fn(&str, &str) -> String,
    credentials_file_content: Option<&str>,
    env_client_id: &str,
    env_client_secret: &str,
    env_username: &str,
    env_password: &str,
) -> OpenSkyState {
    let auth_mode = parse_opensky_auth_mode(auth_mode_str);

    let mut client_id = if env_client_id.is_empty() {
        get_dotenv("OPENSKY_CLIENT_ID")
    } else {
        env_client_id.to_string()
    };
    let mut client_secret = if env_client_secret.is_empty() {
        get_dotenv("OPENSKY_CLIENT_SECRET")
    } else {
        env_client_secret.to_string()
    };
    let mut username = if env_username.is_empty() {
        get_dotenv("OPENSKY_USERNAME")
    } else {
        env_username.to_string()
    };
    let mut password = if env_password.is_empty() {
        get_dotenv("OPENSKY_PASSWORD")
    } else {
        env_password.to_string()
    };

    let credentials_file = get_dotenv("OPENSKY_CREDENTIALS_FILE");

    if (auth_mode == OpenSkyAuthMode::Basic || auth_mode == OpenSkyAuthMode::Auto)
        && username.is_empty()
    {
        let services = ["opensky-network", "opensky"];
        let accounts = ["username", "user", "login", "email", "default"];
        'outer_u: for svc in &services {
            for acct in &accounts {
                let val = get_keychain(svc, acct);
                if !val.is_empty() {
                    username = val;
                    break 'outer_u;
                }
            }
        }
    }
    if (auth_mode == OpenSkyAuthMode::Basic || auth_mode == OpenSkyAuthMode::Auto)
        && password.is_empty()
    {
        let services = ["opensky-network", "opensky"];
        let accounts = ["password", "pass", "token", "secret", "default"];
        'outer_p: for svc in &services {
            for acct in &accounts {
                let val = get_keychain(svc, acct);
                if !val.is_empty() {
                    password = val;
                    break 'outer_p;
                }
            }
        }
    }

    if (auth_mode == OpenSkyAuthMode::OAuth || auth_mode == OpenSkyAuthMode::Auto)
        && credentials_file_content.is_some()
    {
        if let Some(content) = credentials_file_content {
            if let Ok(creds) = crate::opensky_import_client::parse_credentials(content) {
                if client_id.is_empty() {
                    client_id = creds.client_id;
                }
                if client_secret.is_empty() {
                    client_secret = creds.client_secret;
                }
            }
        }
    }

    if (auth_mode == OpenSkyAuthMode::OAuth || auth_mode == OpenSkyAuthMode::Auto)
        && client_id.is_empty()
    {
        let services = ["opensky-network", "opensky"];
        let accounts = ["client_id", "client-id", "client", "api-key"];
        'outer_ci: for svc in &services {
            for acct in &accounts {
                let val = get_keychain(svc, acct);
                if !val.is_empty() {
                    client_id = val;
                    break 'outer_ci;
                }
            }
        }
    }
    if (auth_mode == OpenSkyAuthMode::OAuth || auth_mode == OpenSkyAuthMode::Auto)
        && client_secret.is_empty()
    {
        let services = ["opensky-network", "opensky"];
        let accounts = ["client_secret", "client-secret", "secret"];
        'outer_cs: for svc in &services {
            for acct in &accounts {
                let val = get_keychain(svc, acct);
                if !val.is_empty() {
                    client_secret = val;
                    break 'outer_cs;
                }
            }
        }
    }

    match auth_mode {
        OpenSkyAuthMode::Basic => {
            client_id.clear();
            client_secret.clear();
        }
        OpenSkyAuthMode::OAuth => {
            username.clear();
            password.clear();
        }
        OpenSkyAuthMode::Anon => {
            client_id.clear();
            client_secret.clear();
            username.clear();
            password.clear();
        }
        OpenSkyAuthMode::Auto => {}
    }

    OpenSkyState {
        auth_mode,
        client_id,
        client_secret,
        username,
        password,
        credentials_file,
    }
}

pub fn check_catalog_wiring(
    cctv_js_exists: bool,
    catalog_content: &str,
    construct_catalog_content: &str,
) -> Result<(), String> {
    if !cctv_js_exists {
        return Err("expected CCTV layer file missing: src/data/cctv.js".into());
    }
    let has_catalog_call = catalog_content.contains("return createApplicationCatalog(");
    let has_cctv_wire = construct_catalog_content
        .lines()
        .any(|line| line.trim_start().starts_with("createApplicationCctv({"));
    if !has_catalog_call || !has_cctv_wire {
        return Err("CCTV layer not wired in src/standalone/catalog.js".into());
    }
    Ok(())
}

pub fn resolve_google_maps_key_fresh(
    env_value: &str,
    dotenv_value: &str,
    keychain_lookup: &dyn Fn(&str, &str) -> String,
) -> (String, String) {
    if !env_value.is_empty() {
        return (env_value.to_string(), "env".to_string());
    }
    if !dotenv_value.is_empty() {
        return (dotenv_value.to_string(), "dotenv".to_string());
    }
    for acct in &["api-key", "default", "key"] {
        let kc = keychain_lookup("google-maps-api", acct);
        if !kc.is_empty() {
            return (kc, format!("keychain:{}", acct));
        }
    }
    (String::new(), "not configured".to_string())
}

pub fn resolve_google_maps_key_secure(
    env_value: &str,
    keychain_lookup: &dyn Fn(&str, &str) -> String,
) -> (String, String) {
    for acct in &["api-key", "default", "key"] {
        let kc = keychain_lookup("google-maps-api", acct);
        if !kc.is_empty() {
            return (kc, format!("keychain:{}", acct));
        }
    }
    if !env_value.is_empty() {
        return (env_value.to_string(), "env".to_string());
    }
    (String::new(), "not configured".to_string())
}

pub fn lan_warning_message(host: &str, port: &str, lan_ip: Option<&str>) -> Option<String> {
    match host {
        "localhost" | "127.0.0.1" | "::1" => None,
        _ => {
            let ip_line = match lan_ip {
                Some(ip) if !ip.is_empty() => format!("!! LAN URL: http://{}:{}/", ip, port),
                _ => format!("!! LAN URL: http://<this-machine-ip>:{}/", port),
            };
            Some(format!(
                "\n\
                 !! ==============================================================\n\
                 !! WARNING: HOST={} — network-exposed mode.\n\
                 !! This dev server brokers your configured API keys (OpenAI,\n\
                 !! OpenSky, AISStream, TomTom, FIRMS, LL2, Google) to ANYONE who can\n\
                 !! reach it on the network. Use only on networks you trust.\n\
                 !! Consider the opt-in per-IP throttles GEV_RATELIMIT_OPENAI_PER_MIN\n\
                 !! and GEV_RATELIMIT_GOOGLE_PER_MIN (see .env.example) — and note\n\
                 !! they are NOT billing caps; set provider-side budget alerts too.\n\
                 {}\n\
                 !! ==============================================================\n",
                host, ip_line
            ))
        }
    }
}

/// This app's folder in the monorepo, from the repository root.
pub const APP_DIR: &str = "apps/web/gods-eye-view";

fn env_path(name: &str) -> Option<PathBuf> {
    std::env::var_os(name).filter(|v| !v.is_empty()).map(PathBuf::from)
}

fn resolve_roots() -> (PathBuf, PathBuf) {
    roots_from(
        env_path("BUILD_WORKSPACE_DIRECTORY"),
        std::env::current_exe().ok(),
        std::env::current_dir().unwrap_or_default(),
        env_path("GEV_PROJECT_ROOT"),
    )
}

/// The app's source folder and the folder the dev server runs in.
///
/// Under `bazel run`, the binary sits in bazel-out, so the folder two levels
/// above it is not the app: `workspace` (BUILD_WORKSPACE_DIRECTORY, which
/// `bazel run` sets) names the checkout instead. Elsewhere it falls back to two
/// levels above `exe`, as the shell scripts did from `scripts/`.
/// `project_root` (GEV_PROJECT_ROOT) moves only where the server runs.
pub fn roots_from(
    workspace: Option<PathBuf>,
    exe: Option<PathBuf>,
    cwd: PathBuf,
    project_root: Option<PathBuf>,
) -> (PathBuf, PathBuf) {
    let source_root = match workspace {
        Some(ws) => ws.join(APP_DIR),
        None => exe
            .and_then(|p| p.parent().and_then(|d| d.parent()).map(PathBuf::from))
            .unwrap_or(cwd),
    };
    let root_dir = project_root.unwrap_or_else(|| source_root.clone());
    (source_root, root_dir)
}

fn find_dev_command() -> Result<Vec<String>, String> {
    if which_exists("npm") {
        Ok(vec![
            "npm".into(),
            "run".into(),
            "dev".into(),
            "--".into(),
        ])
    } else if which_exists("pnpm") {
        Ok(vec!["pnpm".into(), "run".into(), "dev".into()])
    } else {
        Err("neither npm nor pnpm found".into())
    }
}

fn which_exists(cmd: &str) -> bool {
    std::process::Command::new("which")
        .arg(cmd)
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

fn read_keychain_secret(service: &str, account: &str) -> String {
    std::process::Command::new("security")
        .args(["find-generic-password", "-s", service, "-a", account, "-w"])
        .output()
        .ok()
        .filter(|o| o.status.success())
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .unwrap_or_default()
}

fn kill_stale_servers(root_dir: &Path, port: &str) {
    let vite_bin = root_dir.join("node_modules/.bin/vite");
    let _ = std::process::Command::new("pkill")
        .args(["-f", &vite_bin.to_string_lossy()])
        .output();
    let vite_js = root_dir.join("node_modules/vite/bin/vite.js");
    let _ = std::process::Command::new("pkill")
        .args(["-f", &vite_js.to_string_lossy()])
        .output();

    if let Ok(output) = std::process::Command::new("lsof")
        .args([
            &format!("-tiTCP:{}", port),
            "-sTCP:LISTEN",
        ])
        .output()
    {
        let pids = String::from_utf8_lossy(&output.stdout);
        for pid in pids.split_whitespace() {
            let _ = std::process::Command::new("kill")
                .args(["-9", pid])
                .output();
        }
    }
}

fn get_lan_ip() -> Option<String> {
    for iface in &["en0", "en1"] {
        if let Ok(output) = std::process::Command::new("ipconfig")
            .args(["getifaddr", iface])
            .output()
        {
            if output.status.success() {
                let ip = String::from_utf8_lossy(&output.stdout).trim().to_string();
                if !ip.is_empty() {
                    return Some(ip);
                }
            }
        }
    }
    None
}

pub fn run_dev_fresh(_args: &[String]) -> Result<(), String> {
    let (source_root, root_dir) = resolve_roots();
    std::env::set_current_dir(&root_dir)
        .map_err(|e| format!("Cannot cd to {}: {}", root_dir.display(), e))?;

    let port = std::env::var("PORT").unwrap_or_else(|_| "4173".into());
    let host = std::env::var("HOST").unwrap_or_else(|_| "localhost".into());
    let cctv = default_cctv_config(Preset::Fresh);
    let dev_cmd = find_dev_command()?;

    let ext_keys = track_external_keys(&|k| std::env::var(k).ok());
    let ext_csv = external_keys_csv(&ext_keys);

    let env_gmaps = std::env::var("GOOGLE_MAPS_API_KEY").unwrap_or_default();
    let dotenv_gmaps = read_dotenv_value(&source_root, "GOOGLE_MAPS_API_KEY");
    let (gmaps_key, gmaps_source) = resolve_google_maps_key_fresh(
        &env_gmaps,
        &dotenv_gmaps,
        &read_keychain_secret,
    );

    let opensky_mode_env = std::env::var("OPENSKY_AUTH_MODE")
        .unwrap_or_else(|_| read_dotenv_value(&source_root, "OPENSKY_AUTH_MODE"));
    let opensky_mode_str = if opensky_mode_env.is_empty() {
        "oauth".to_string()
    } else {
        opensky_mode_env
    };
    let cred_file_env = std::env::var("OPENSKY_CREDENTIALS_FILE")
        .unwrap_or_else(|_| read_dotenv_value(&source_root, "OPENSKY_CREDENTIALS_FILE"));
    let cred_content = if !cred_file_env.is_empty() {
        std::fs::read_to_string(&cred_file_env).ok()
    } else {
        None
    };
    let opensky = resolve_opensky_credentials(
        &opensky_mode_str,
        &|k| {
            let val = std::env::var(k).unwrap_or_default();
            if val.is_empty() {
                read_dotenv_value(&source_root, k)
            } else {
                val
            }
        },
        &read_keychain_secret,
        cred_content.as_deref(),
        &std::env::var("OPENSKY_CLIENT_ID").unwrap_or_default(),
        &std::env::var("OPENSKY_CLIENT_SECRET").unwrap_or_default(),
        &std::env::var("OPENSKY_USERNAME").unwrap_or_default(),
        &std::env::var("OPENSKY_PASSWORD").unwrap_or_default(),
    );

    let resolve_key = |env_name: &str, svc: &str, acct: &str| -> String {
        let val = std::env::var(env_name).unwrap_or_default();
        if !val.is_empty() {
            return val;
        }
        let dv = read_dotenv_value(&source_root, env_name);
        if !dv.is_empty() {
            return dv;
        }
        read_keychain_secret(svc, acct)
    };
    let openai = resolve_key("OPENAI_API_KEY", "openai-api", "api-key");
    let aisstream = resolve_key("AISSTREAM_API_KEY", "aisstream-api", "api-key");
    let cesium = resolve_key("CESIUM_ION_TOKEN", "cesium-ion", "token");
    let tomtom = resolve_key("TOMTOM_API_KEY", "tomtom-api", "api-key");
    let firms = resolve_key("FIRMS_MAP_KEY", "firms-map", "map-key");
    let ll2 = std::env::var("LL2_API_TOKEN")
        .unwrap_or_else(|_| read_dotenv_value(&source_root, "LL2_API_TOKEN"));

    let cctv_js = source_root.join("src/data/cctv.js");
    let catalog_content =
        std::fs::read_to_string(source_root.join("src/standalone/catalog.js")).unwrap_or_default();
    let construct_content = std::fs::read_to_string(
        source_root.join("src/app/constructCatalog.js"),
    )
    .unwrap_or_default();
    check_catalog_wiring(cctv_js.is_file(), &catalog_content, &construct_content)?;

    eprintln!("Stopping all existing God's Eye View dev servers...");
    kill_stale_servers(&root_dir, &port);
    eprintln!("Clearing Vite cache...");
    let _ = std::fs::remove_dir_all(root_dir.join("node_modules/.vite"));

    eprintln!("Starting fresh God's Eye View dev server...");
    if let Some(warning) = lan_warning_message(&host, &port, get_lan_ip().as_deref()) {
        eprintln!("{}", warning);
        eprintln!("URL (this machine): http://localhost:{}/", port);
    } else {
        eprintln!(
            "Local-only mode: reachable at http://localhost:{}/ (set HOST=0.0.0.0 for LAN)",
            port
        );
    }
    eprintln!("Google Maps key source: {}", gmaps_source);
    eprintln!("OpenSky auth mode: {}", opensky.auth_mode);

    let mut env_vars: Vec<(String, String)> = Vec::new();
    let mut unset_vars: Vec<String> = Vec::new();

    for (k, v) in [
        ("CCTV_AUSTIN_MAX_SOURCES", cctv.austin_max_sources.as_str()),
        ("CCTV_CALTRANS_DISTRICTS", cctv.caltrans_districts.as_str()),
        ("CCTV_CALTRANS_MAX_SOURCES", cctv.caltrans_max_sources.as_str()),
        ("CCTV_TFL_ENABLED", cctv.tfl_enabled.as_str()),
        ("CCTV_TFL_MAX_SOURCES", cctv.tfl_max_sources.as_str()),
        ("CCTV_ONTARIO_ENABLED", cctv.ontario_enabled.as_str()),
        ("CCTV_ONTARIO_MAX_SOURCES", cctv.ontario_max_sources.as_str()),
        ("CCTV_FINTRAFFIC_ENABLED", cctv.fintraffic_enabled.as_str()),
        ("CCTV_FINTRAFFIC_MAX_SOURCES", cctv.fintraffic_max_sources.as_str()),
        ("CCTV_DRIVEBC_ENABLED", cctv.drivebc_enabled.as_str()),
        ("CCTV_DRIVEBC_MAX_SOURCES", cctv.drivebc_max_sources.as_str()),
        ("CCTV_TXDOT_ENABLED", cctv.txdot_enabled.as_str()),
        ("CCTV_TXDOT_DISTRICTS", cctv.txdot_districts.as_str()),
        ("CCTV_TXDOT_MAX_SOURCES", cctv.txdot_max_sources.as_str()),
        ("CCTV_TALLINN_ENABLED", cctv.tallinn_enabled.as_str()),
        ("CCTV_TALLINN_MAX_SOURCES", cctv.tallinn_max_sources.as_str()),
        ("CCTV_TARKTEE_ENABLED", cctv.tarktee_enabled.as_str()),
        ("CCTV_TARKTEE_MAX_SOURCES", cctv.tarktee_max_sources.as_str()),
        ("CCTV_WARENDORF_ENABLED", cctv.warendorf_enabled.as_str()),
        ("CCTV_NSW_ENABLED", cctv.nsw_enabled.as_str()),
        ("CCTV_NSW_MAX_SOURCES", cctv.nsw_max_sources.as_str()),
        ("CCTV_CALGARY_ENABLED", cctv.calgary_enabled.as_str()),
        ("CCTV_CALGARY_MAX_SOURCES", cctv.calgary_max_sources.as_str()),
        ("CCTV_MAX_SOURCES", cctv.max_sources.as_str()),
    ] {
        env_vars.push((k.to_string(), v.to_string()));
    }
    env_vars.push(("OPENSKY_AUTH_MODE".to_string(), opensky.auth_mode.to_string()));

    let tfl_app_key = std::env::var("TFL_APP_KEY").unwrap_or_default();
    for (k, v) in [
        ("GOOGLE_MAPS_API_KEY", gmaps_key.as_str()),
        ("TFL_APP_KEY", tfl_app_key.as_str()),
        ("OPENSKY_CREDENTIALS_FILE", opensky.credentials_file.as_str()),
        ("OPENSKY_CLIENT_ID", opensky.client_id.as_str()),
        ("OPENSKY_CLIENT_SECRET", opensky.client_secret.as_str()),
        ("OPENSKY_USERNAME", opensky.username.as_str()),
        ("OPENSKY_PASSWORD", opensky.password.as_str()),
        ("OPENAI_API_KEY", openai.as_str()),
        ("AISSTREAM_API_KEY", aisstream.as_str()),
        ("CESIUM_ION_TOKEN", cesium.as_str()),
        ("TOMTOM_API_KEY", tomtom.as_str()),
        ("FIRMS_MAP_KEY", firms.as_str()),
        ("LL2_API_TOKEN", ll2.as_str()),
    ] {
        if v.is_empty() {
            unset_vars.push(k.to_string());
        } else {
            env_vars.push((k.to_string(), v.to_string()));
        }
    }
    env_vars.push(("GEV_LAUNCHER".to_string(), "dev-fresh".to_string()));
    env_vars.push(("GEV_KEY_SETUP_EXTERNAL_KEYS".to_string(), ext_csv));

    let mut cmd = std::process::Command::new(&dev_cmd[0]);
    cmd.args(&dev_cmd[1..]);
    cmd.args(["--host", &host, "--port", &port, "--force"]);
    for (k, v) in &env_vars {
        cmd.env(k, v);
    }
    for k in &unset_vars {
        cmd.env_remove(k);
    }

    let status = cmd
        .status()
        .map_err(|e| format!("Failed to launch dev server: {}", e))?;
    if !status.success() {
        return Err(format!("Dev server exited with {}", status));
    }
    Ok(())
}

pub fn run_dev_cctv(_args: &[String]) -> Result<(), String> {
    let cctv = default_cctv_config(Preset::Cctv);
    std::env::set_var("CCTV_SOURCES_FILE", &cctv.sources_file);
    std::env::set_var("CCTV_PREFER_AUSTIN", &cctv.prefer_austin);
    std::env::set_var("CCTV_AUSTIN_MAX_SOURCES", &cctv.austin_max_sources);
    std::env::set_var("CCTV_MAX_SOURCES", &cctv.max_sources);
    run_dev_fresh(_args)
}

pub fn run_dev_secure(_args: &[String]) -> Result<(), String> {
    let (_source_root, root_dir) = resolve_roots();
    std::env::set_current_dir(&root_dir)
        .map_err(|e| format!("Cannot cd to {}: {}", root_dir.display(), e))?;

    let port = std::env::var("PORT").unwrap_or_else(|_| "4173".into());
    let host = std::env::var("HOST").unwrap_or_else(|_| "localhost".into());

    let env_gmaps = std::env::var("GOOGLE_MAPS_API_KEY").unwrap_or_default();
    let (gmaps_key, gmaps_source) =
        resolve_google_maps_key_secure(&env_gmaps, &read_keychain_secret);
    if gmaps_key.is_empty() {
        return Err(
            "Google Maps API key missing.\n\
             set GOOGLE_MAPS_API_KEY in env, or add Keychain item: \
             service=google-maps-api account=api-key"
                .into(),
        );
    }

    let opensky_mode_str = std::env::var("OPENSKY_AUTH_MODE").unwrap_or_else(|_| "oauth".into());
    let cred_file_env = std::env::var("OPENSKY_CREDENTIALS_FILE").unwrap_or_default();
    let cred_content = if !cred_file_env.is_empty() {
        std::fs::read_to_string(&cred_file_env).ok()
    } else {
        None
    };
    let opensky = resolve_opensky_credentials(
        &opensky_mode_str,
        &|_| String::new(),
        &read_keychain_secret,
        cred_content.as_deref(),
        &std::env::var("OPENSKY_CLIENT_ID").unwrap_or_default(),
        &std::env::var("OPENSKY_CLIENT_SECRET").unwrap_or_default(),
        &std::env::var("OPENSKY_USERNAME").unwrap_or_default(),
        &std::env::var("OPENSKY_PASSWORD").unwrap_or_default(),
    );

    let cctv = default_cctv_config(Preset::Secure);

    eprintln!("Starting God's Eye View dev server...");
    eprintln!("URL: http://localhost:{}/", port);
    eprintln!("Google Maps key source: {}", gmaps_source);
    eprintln!("OpenSky auth mode: {}", opensky.auth_mode);

    let status = std::process::Command::new("npm")
        .args(["run", "dev", "--", "--host", &host, "--port", &port])
        .env("GOOGLE_MAPS_API_KEY", &gmaps_key)
        .env("CCTV_AUSTIN_MAX_SOURCES", &cctv.austin_max_sources)
        .env("CCTV_MAX_SOURCES", &cctv.max_sources)
        .env("OPENSKY_AUTH_MODE", opensky.auth_mode.to_string())
        .env("OPENSKY_CREDENTIALS_FILE", &opensky.credentials_file)
        .env("OPENSKY_CLIENT_ID", &opensky.client_id)
        .env("OPENSKY_CLIENT_SECRET", &opensky.client_secret)
        .env("OPENSKY_USERNAME", &opensky.username)
        .env("OPENSKY_PASSWORD", &opensky.password)
        .status()
        .map_err(|e| format!("Failed to launch dev server: {}", e))?;
    if !status.success() {
        return Err(format!("Dev server exited with {}", status));
    }
    Ok(())
}
