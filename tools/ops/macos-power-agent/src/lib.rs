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

//! Rust implementation of `tools/ops/macos-power-agent` (`power-agent` and `install`).
//!
//! Samples macOS SoC compute power (`powermetrics`) and battery state (`pmset` +
//! `ioreg`) and pushes Prometheus exposition metrics to Pushgateway, matching
//! `power-agent.sh` and `install.sh` byte for byte on stdout, stderr, and exit code.

use std::collections::HashMap;
use std::fs;
use std::io::{Read, Write};
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{SystemTime, UNIX_EPOCH};

/// Parsed SoC power figures from `powermetrics --samplers cpu_power`.
#[derive(Debug, Default, PartialEq, Eq)]
pub struct PowerMetrics {
    pub soc_w: String,
    pub cpu_mw: String,
    pub gpu_mw: String,
    pub ane_mw: String,
}

/// Parsed battery state from `pmset -g batt`.
#[derive(Debug, Default, PartialEq, Eq)]
pub struct BatteryMetrics {
    pub pct: String,
    pub ac: u8,
    pub charging: u8,
}

fn env_nonempty(name: &str) -> Option<String> {
    std::env::var(name).ok().filter(|v| !v.is_empty())
}

fn is_executable(p: &Path) -> bool {
    fs::metadata(p)
        .map(|m| m.is_file() && (m.permissions().mode() & 0o111 != 0))
        .unwrap_or(false)
}

/// Equivalent to `$(command -v <cmd> 2>/dev/null || echo <default>)`.
pub fn which_or_default(cmd: &str, default: &str) -> String {
    if cmd.contains('/') {
        if is_executable(Path::new(cmd)) {
            return cmd.to_string();
        }
        return default.to_string();
    }
    if let Some(path_var) = std::env::var_os("PATH") {
        for dir in std::env::split_paths(&path_var) {
            if dir.as_os_str().is_empty() {
                continue;
            }
            let candidate = dir.join(cmd);
            if is_executable(&candidate) {
                return candidate.to_string_lossy().into_owned();
            }
        }
    }
    default.to_string()
}

/// Equivalent to `$(hostname -s | tr '[:upper:]' '[:lower:]')`.
pub fn short_hostname_lower() -> String {
    if let Ok(out) = Command::new("hostname")
        .arg("-s")
        .stdin(Stdio::null())
        .stderr(Stdio::null())
        .output()
    {
        let s = String::from_utf8_lossy(&out.stdout);
        return s.trim_end_matches(&['\r', '\n'][..]).to_ascii_lowercase();
    }
    String::new()
}

/// Equivalent to `$(date +%s)`.
pub fn unix_timestamp_secs() -> String {
    if let Ok(out) = Command::new("date")
        .arg("+%s")
        .stdin(Stdio::null())
        .stderr(Stdio::null())
        .output()
    {
        if out.status.success() {
            let s = String::from_utf8_lossy(&out.stdout)
                .trim_end_matches(&['\r', '\n'][..])
                .to_string();
            if !s.is_empty() {
                return s;
            }
        }
    }
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs().to_string())
        .unwrap_or_else(|_| "0".to_string())
}

fn expand_vars(input: &str, vars: &HashMap<String, String>) -> String {
    let mut out = String::with_capacity(input.len());
    let bytes = input.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'\\' && i + 1 < bytes.len() {
            let next = bytes[i + 1];
            if next == b'"' || next == b'\\' || next == b'$' || next == b'`' {
                out.push(next as char);
                i += 2;
                continue;
            }
        }
        if bytes[i] == b'$' {
            if i + 1 < bytes.len() && bytes[i + 1] == b'{' {
                if let Some(close_rel) = input[i + 2..].find('}') {
                    let expr = &input[i + 2..i + 2 + close_rel];
                    let val = if let Some((name, def)) = expr.split_once(":-") {
                        vars.get(name)
                            .cloned()
                            .or_else(|| std::env::var(name).ok())
                            .filter(|v| !v.is_empty())
                            .unwrap_or_else(|| def.to_string())
                    } else if let Some(rest) = expr.strip_suffix("%/") {
                        let raw = vars
                            .get(rest)
                            .cloned()
                            .or_else(|| std::env::var(rest).ok())
                            .unwrap_or_default();
                        raw.strip_suffix('/').unwrap_or(&raw).to_string()
                    } else {
                        vars.get(expr)
                            .cloned()
                            .or_else(|| std::env::var(expr).ok())
                            .unwrap_or_default()
                    };
                    out.push_str(&val);
                    i += 3 + close_rel;
                    continue;
                }
            } else if i + 1 < bytes.len()
                && (bytes[i + 1].is_ascii_alphabetic() || bytes[i + 1] == b'_')
            {
                let mut end = i + 2;
                while end < bytes.len()
                    && (bytes[end].is_ascii_alphanumeric() || bytes[end] == b'_')
                {
                    end += 1;
                }
                let name = &input[i + 1..end];
                let val = vars
                    .get(name)
                    .cloned()
                    .or_else(|| std::env::var(name).ok())
                    .unwrap_or_default();
                out.push_str(&val);
                i = end;
                continue;
            }
        }
        let ch = input[i..].chars().next().unwrap();
        out.push(ch);
        i += ch.len_utf8();
    }
    out
}

/// Parse shell assignments from `/usr/local/etc/vitruvian-power-agent.conf`.
pub fn parse_conf_str(content: &str, vars: &mut HashMap<String, String>) {
    for raw_line in content.lines() {
        let line = raw_line.trim_start();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let line = line
            .strip_prefix("export ")
            .map(str::trim_start)
            .unwrap_or(line);
        let Some((key_raw, val_raw)) = line.split_once('=') else {
            continue;
        };
        let key = key_raw.trim();
        if key.is_empty() || !key.chars().all(|c| c.is_ascii_alphanumeric() || c == '_') {
            continue;
        }
        let val_trimmed = val_raw.trim();
        let value = if val_trimmed.starts_with('"') && val_trimmed.len() >= 2 {
            // Find matching closing quote
            let inner = if let Some(stripped) = val_trimmed[1..].strip_suffix('"') {
                stripped
            } else {
                &val_trimmed[1..]
            };
            expand_vars(inner, vars)
        } else if val_trimmed.starts_with('\'') && val_trimmed.len() >= 2 {
            let inner = if let Some(stripped) = val_trimmed[1..].strip_suffix('\'') {
                stripped
            } else {
                &val_trimmed[1..]
            };
            inner.to_string()
        } else {
            // Strip inline comment if preceded by whitespace
            let mut unquoted = val_trimmed;
            for (idx, _) in val_trimmed.match_indices('#') {
                if idx == 0 || val_trimmed.as_bytes()[idx - 1].is_ascii_whitespace() {
                    unquoted = val_trimmed[..idx].trim_end();
                    break;
                }
            }
            expand_vars(unquoted, vars)
        };
        vars.insert(key.to_string(), value);
    }
}

/// Replicates `sub(/ *mW.*/, "", v)` on field `$2` of `awk -F': '`.
fn strip_mw_suffix(field2: &str) -> String {
    if let Some(idx) = field2.find("mW") {
        field2[..idx].trim_end_matches(' ').to_string()
    } else {
        field2.to_string()
    }
}

/// Format milliwatts string as watts (`%.3f`), matching `awk -v m="$mw" 'BEGIN { printf "%.3f", m / 1000 }'`.
pub fn mw_to_watts_str(mw: &str) -> String {
    let val = parse_awk_number(mw);
    format!("{:.3}", val / 1000.0)
}

fn parse_awk_number(s: &str) -> f64 {
    let trimmed = s.trim_start();
    if trimmed.is_empty() {
        return 0.0;
    }
    let mut end = 0;
    let bytes = trimmed.as_bytes();
    if end < bytes.len() && (bytes[end] == b'+' || bytes[end] == b'-') {
        end += 1;
    }
    let mut seen_dot = false;
    while end < bytes.len() {
        if bytes[end].is_ascii_digit() {
            end += 1;
        } else if bytes[end] == b'.' && !seen_dot {
            seen_dot = true;
            end += 1;
        } else {
            break;
        }
    }
    trimmed[..end].parse::<f64>().unwrap_or(0.0)
}

/// Replicates `sed -nE 's/.*derived package power[^:]*: *([0-9.]+) *W.*/\1/p' | head -1`.
fn parse_intel_package_watts(pm: &str) -> String {
    let needle = "derived package power";
    for line in pm.lines() {
        let mut search_from = 0;
        let mut matched_val: Option<String> = None;
        while let Some(rel) = line[search_from..].find(needle) {
            let after_needle = &line[search_from + rel + needle.len()..];
            if let Some(colon_idx) = after_needle.find(':') {
                let after_colon = after_needle[colon_idx + 1..].trim_start_matches(' ');
                let num_len = after_colon
                    .bytes()
                    .take_while(|b| b.is_ascii_digit() || *b == b'.')
                    .count();
                if num_len > 0 {
                    let after_num = after_colon[num_len..].trim_start_matches(' ');
                    if after_num.starts_with('W') {
                        matched_val = Some(after_colon[..num_len].to_string());
                    }
                }
            }
            search_from += rel + needle.len();
        }
        if let Some(v) = matched_val {
            return v;
        }
    }
    String::new()
}

/// Extract per-domain power in mW (`CPU`, `GPU`, `ANE`), matching:
/// `awk -F': ' -v k="$1 Power" 'index($0, k ":") == 1 {v = $2; sub(/ *mW.*/, "", v); print v; exit}'`
pub fn parse_domain_mw(pm: &str, domain: &str) -> String {
    let prefix = format!("{domain} Power:");
    for line in pm.lines() {
        if line.starts_with(&prefix) {
            let field2 = line.split(": ").nth(1).unwrap_or("");
            return strip_mw_suffix(field2);
        }
    }
    String::new()
}

/// Parse `powermetrics --samplers cpu_power` output.
pub fn parse_powermetrics(pm: &str) -> PowerMetrics {
    let mut combined_mw = String::new();
    for line in pm.lines() {
        if line.contains("Combined Power") {
            let field2 = line.split(": ").nth(1).unwrap_or("");
            combined_mw = strip_mw_suffix(field2);
            break;
        }
    }
    let soc_w = if !combined_mw.is_empty() {
        mw_to_watts_str(&combined_mw)
    } else {
        parse_intel_package_watts(pm)
    };
    PowerMetrics {
        soc_w,
        cpu_mw: parse_domain_mw(pm, "CPU"),
        gpu_mw: parse_domain_mw(pm, "GPU"),
        ane_mw: parse_domain_mw(pm, "ANE"),
    }
}

/// Parse `pmset -g batt` output.
pub fn parse_pmset(batt: &str) -> BatteryMetrics {
    // pct="$(printf '%s\n' "$batt" | grep -oE '[0-9]+%' | head -1 | tr -d '%')"
    let mut pct = String::new();
    let bytes = batt.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i].is_ascii_digit() {
            let start = i;
            while i < bytes.len() && bytes[i].is_ascii_digit() {
                i += 1;
            }
            if i < bytes.len() && bytes[i] == b'%' {
                pct = batt[start..i].to_string();
                break;
            }
        } else {
            i += 1;
        }
    }

    let lower = batt.to_ascii_lowercase();
    let ac = if lower.contains("ac power") || lower.contains("ac attached") {
        1
    } else {
        0
    };
    let charging = if lower.contains("; charging") { 1 } else { 0 };

    BatteryMetrics { pct, ac, charging }
}

/// Parse `ioreg -rn AppleSmartBattery` output and return `discharge_w` (formatted `%.2f`),
/// or empty string if `InstantAmperage` or `Voltage` is absent.
pub fn parse_ioreg(ioreg: &str) -> String {
    let extract_field = |key: &str| -> String {
        let needle = format!("\"{key}\"");
        for line in ioreg.lines() {
            if line.contains(&needle) {
                let field2 = line.split("= ").nth(1).unwrap_or("");
                return field2
                    .chars()
                    .filter(|c| c.is_ascii_digit() || *c == '-')
                    .collect();
            }
        }
        String::new()
    };

    let amp_raw = extract_field("InstantAmperage");
    let volt_raw = extract_field("Voltage");
    if amp_raw.is_empty() || volt_raw.is_empty() {
        return String::new();
    }

    // Bash arithmetic `$((amp_raw))` interprets 64-bit unsigned overflow (2^64 - N)
    // as signed 64-bit negative (-N).
    let amp: i64 = if let Ok(u) = amp_raw.parse::<u64>() {
        u as i64
    } else {
        amp_raw.parse::<i64>().unwrap_or(0)
    };
    let volt = parse_awk_number(&volt_raw);
    let watts = if amp < 0 {
        (-(amp as f64)) * volt / 1_000_000.0
    } else {
        0.0
    };
    format!("{watts:.2}")
}

/// Assemble the Prometheus exposition text.
pub fn assemble_metrics(
    pm: &PowerMetrics,
    batt: &BatteryMetrics,
    discharge_w: &str,
    last_push_secs: &str,
) -> String {
    let mut metrics = String::new();
    let mut emit = |name: &str, val: &str| {
        metrics.push_str(&format!("# TYPE {name} gauge\n{name} {val}\n"));
    };
    if !pm.soc_w.is_empty() {
        emit("mac_soc_power_watts", &pm.soc_w);
    }
    if !pm.cpu_mw.is_empty() {
        emit("mac_cpu_power_watts", &mw_to_watts_str(&pm.cpu_mw));
    }
    if !pm.gpu_mw.is_empty() {
        emit("mac_gpu_power_watts", &mw_to_watts_str(&pm.gpu_mw));
    }
    if !pm.ane_mw.is_empty() {
        emit("mac_ane_power_watts", &mw_to_watts_str(&pm.ane_mw));
    }
    if !batt.pct.is_empty() {
        emit("mac_battery_percent", &batt.pct);
    }
    emit("mac_ac_online", &batt.ac.to_string());
    emit("mac_battery_charging", &batt.charging.to_string());
    if !discharge_w.is_empty() {
        emit("mac_battery_discharge_watts", discharge_w);
    }
    emit("mac_power_agent_last_push_seconds", last_push_secs);
    metrics
}

fn run_capture_stdout(bin: &str, args: &[&str]) -> String {
    match Command::new(bin)
        .args(args)
        .stdin(Stdio::null())
        .stderr(Stdio::null())
        .output()
    {
        Ok(o) => String::from_utf8_lossy(&o.stdout)
            .trim_end_matches('\n')
            .to_string(),
        Err(_) => String::new(),
    }
}

/// Entrypoint for `power-agent`.
pub fn run_power_agent() -> i32 {
    let mut vars: HashMap<String, String> = HashMap::new();
    let default_url = env_nonempty("PUSHGATEWAY_URL")
        .unwrap_or_else(|| "https://pushgateway.lab.ipv1337.dev".to_string());
    let default_instance = env_nonempty("INSTANCE").unwrap_or_else(short_hostname_lower);
    let default_job = env_nonempty("JOB").unwrap_or_else(|| "mac_power".to_string());
    let conf_path = env_nonempty("CONF_FILE")
        .unwrap_or_else(|| "/usr/local/etc/vitruvian-power-agent.conf".to_string());

    let default_pm_bin = env_nonempty("POWERMETRICS_BIN")
        .unwrap_or_else(|| which_or_default("powermetrics", "/usr/bin/powermetrics"));
    let default_pmset_bin =
        env_nonempty("PMSET_BIN").unwrap_or_else(|| which_or_default("pmset", "/usr/bin/pmset"));
    let default_ioreg_bin =
        env_nonempty("IOREG_BIN").unwrap_or_else(|| which_or_default("ioreg", "/usr/sbin/ioreg"));
    let default_curl_bin =
        env_nonempty("CURL_BIN").unwrap_or_else(|| which_or_default("curl", "/usr/bin/curl"));

    vars.insert("PUSHGATEWAY_URL".to_string(), default_url);
    vars.insert("INSTANCE".to_string(), default_instance);
    vars.insert("JOB".to_string(), default_job);
    vars.insert("CONF".to_string(), conf_path.clone());
    vars.insert("POWERMETRICS_BIN".to_string(), default_pm_bin);
    vars.insert("PMSET_BIN".to_string(), default_pmset_bin);
    vars.insert("IOREG_BIN".to_string(), default_ioreg_bin);
    vars.insert("CURL_BIN".to_string(), default_curl_bin);
    if let Some(dr) = env_nonempty("DRY_RUN") {
        vars.insert("DRY_RUN".to_string(), dr);
    }

    if let Ok(mut f) = fs::File::open(&conf_path) {
        let mut contents = String::new();
        if f.read_to_string(&mut contents).is_ok() {
            parse_conf_str(&contents, &mut vars);
        }
    }

    let pushgateway_url = vars.get("PUSHGATEWAY_URL").cloned().unwrap_or_default();
    let instance = vars.get("INSTANCE").cloned().unwrap_or_default();
    let job = vars.get("JOB").cloned().unwrap_or_default();
    let pm_bin = vars.get("POWERMETRICS_BIN").cloned().unwrap_or_default();
    let pmset_bin = vars.get("PMSET_BIN").cloned().unwrap_or_default();
    let ioreg_bin = vars.get("IOREG_BIN").cloned().unwrap_or_default();
    let curl_bin = vars.get("CURL_BIN").cloned().unwrap_or_default();
    let dry_run = vars
        .get("DRY_RUN")
        .cloned()
        .or_else(|| env_nonempty("DRY_RUN"))
        .unwrap_or_else(|| "0".to_string());

    let pm_out = run_capture_stdout(
        &pm_bin,
        &["--samplers", "cpu_power", "-n", "1", "-i", "700"],
    );
    let pm = parse_powermetrics(&pm_out);

    let batt_out = run_capture_stdout(&pmset_bin, &["-g", "batt"]);
    let batt = parse_pmset(&batt_out);

    let ioreg_out = run_capture_stdout(&ioreg_bin, &["-rn", "AppleSmartBattery"]);
    let discharge_w = parse_ioreg(&ioreg_out);

    let last_push_secs = unix_timestamp_secs();
    let metrics = assemble_metrics(&pm, &batt, &discharge_w, &last_push_secs);

    if pm.soc_w.is_empty() && batt.pct.is_empty() {
        eprintln!("power-agent: nothing parsed (powermetrics/pmset failed?); not pushing");
        return 0;
    }

    let url_stripped = pushgateway_url
        .strip_suffix('/')
        .unwrap_or(&pushgateway_url);
    let target_url = format!("{url_stripped}/metrics/job/{job}/instance/{instance}");

    if dry_run == "1" {
        print!("target: {target_url}\n{metrics}");
        let _ = std::io::stdout().flush();
        return 0;
    }

    let push_ok = match Command::new(&curl_bin)
        .args([
            "-sS",
            "--max-time",
            "15",
            "--data-binary",
            "@-",
            &target_url,
        ])
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
    {
        Ok(mut child) => {
            if let Some(mut stdin) = child.stdin.take() {
                let _ = stdin.write_all(metrics.as_bytes());
            }
            child.wait().map(|s| s.success()).unwrap_or(false)
        }
        Err(_) => false,
    };

    if !push_ok {
        eprintln!("power-agent: push to {pushgateway_url} failed (instance={instance})");
        return 0;
    }

    0
}

fn default_src_dir() -> PathBuf {
    if let Some(s) = env_nonempty("SRC_DIR") {
        return PathBuf::from(s);
    }
    if let Ok(rf) = runfiles::Runfiles::create() {
        if let Some(p) = runfiles::rlocation!(
            rf,
            "_main/tools/ops/macos-power-agent/com.vitruvian.power-agent.plist"
        ) {
            if p.exists() {
                if let Some(parent) = p.parent() {
                    return parent.to_path_buf();
                }
            }
        }
    }
    std::env::current_exe()
        .ok()
        .and_then(|p| p.parent().map(Path::to_path_buf))
        .unwrap_or_else(|| PathBuf::from("."))
}

/// Entrypoint for `install`.
pub fn run_install(args: &[String]) -> i32 {
    let id_bin = env_nonempty("ID_BIN").unwrap_or_else(|| "id".to_string());
    let uid = Command::new(&id_bin)
        .arg("-u")
        .stdin(Stdio::null())
        .output()
        .ok()
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .unwrap_or_default();

    if uid != "0" {
        eprintln!("install.sh: must run as root (use sudo)");
        return 1;
    }

    let instance = args
        .first()
        .filter(|s| !s.is_empty())
        .cloned()
        .unwrap_or_else(short_hostname_lower);
    let pushgateway_url = env_nonempty("PUSHGATEWAY_URL")
        .unwrap_or_else(|| "https://pushgateway.lab.ipv1337.dev".to_string());
    let src_dir = default_src_dir();
    let label = "com.vitruvian.power-agent";
    let dest_root = env_nonempty("DEST_ROOT").unwrap_or_default();
    let plist_dest = format!("{dest_root}/Library/LaunchDaemons/{label}.plist");
    let bin_dest = format!("{dest_root}/usr/local/bin/vitruvian-power-agent");
    let conf_dest = format!("{dest_root}/usr/local/etc/vitruvian-power-agent.conf");

    let install_bin = env_nonempty("INSTALL_BIN").unwrap_or_else(|| "install".to_string());
    let chown_bin = env_nonempty("CHOWN_BIN").unwrap_or_else(|| "chown".to_string());
    let launchctl_bin = env_nonempty("LAUNCHCTL_BIN").unwrap_or_else(|| "launchctl".to_string());

    let agent_src = env_nonempty("AGENT_SRC").unwrap_or_else(|| {
        let sh_candidate = src_dir.join("power-agent.sh");
        if sh_candidate.exists() {
            sh_candidate.to_string_lossy().into_owned()
        } else {
            src_dir.join("power-agent").to_string_lossy().into_owned()
        }
    });
    let plist_src = src_dir.join(format!("{label}.plist"));

    let status_dirs = Command::new(&install_bin)
        .args([
            "-d",
            "-m",
            "0755",
            &format!("{dest_root}/usr/local/bin"),
            &format!("{dest_root}/usr/local/etc"),
            &format!("{dest_root}/var/log"),
        ])
        .status();
    if !status_dirs.map(|s| s.success()).unwrap_or(false) {
        return 1;
    }

    let status_bin = Command::new(&install_bin)
        .args(["-m", "0755", &agent_src, &bin_dest])
        .status();
    if !status_bin.map(|s| s.success()).unwrap_or(false) {
        return 1;
    }

    let conf_content = format!(
        "# Written by macos-power-agent install.sh — edit and reload the daemon to change.\n\
         INSTANCE=\"{instance}\"\n\
         PUSHGATEWAY_URL=\"{pushgateway_url}\"\n\
         JOB=\"mac_power\"\n"
    );
    if fs::write(&conf_dest, conf_content).is_err() {
        return 1;
    }
    let _ = fs::set_permissions(&conf_dest, fs::Permissions::from_mode(0o644));

    let status_plist = Command::new(&install_bin)
        .args(["-m", "0644", &plist_src.to_string_lossy(), &plist_dest])
        .status();
    if !status_plist.map(|s| s.success()).unwrap_or(false) {
        return 1;
    }

    let status_chown = Command::new(&chown_bin)
        .args(["root:wheel", &plist_dest, &bin_dest])
        .status();
    if !status_chown.map(|s| s.success()).unwrap_or(false) {
        return 1;
    }

    let _ = Command::new(&launchctl_bin)
        .args(["bootout", &format!("system/{label}")])
        .stderr(Stdio::null())
        .status();

    let status_bootstrap = Command::new(&launchctl_bin)
        .args(["bootstrap", "system", &plist_dest])
        .status();
    if !status_bootstrap.map(|s| s.success()).unwrap_or(false) {
        return 1;
    }

    let status_enable = Command::new(&launchctl_bin)
        .args(["enable", &format!("system/{label}")])
        .status();
    if !status_enable.map(|s| s.success()).unwrap_or(false) {
        return 1;
    }

    let _ = Command::new(&launchctl_bin)
        .args(["kickstart", &format!("system/{label}")])
        .stderr(Stdio::null())
        .status();

    println!("macos-power-agent installed: instance={instance} target={pushgateway_url}");
    println!("logs: /var/log/vitruvian-power-agent.log   (first push within ~30s)");
    0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn apple_silicon_powermetrics_parsing() {
        let sample = "\
*** Sampled system activity (Mon Oct 26 01:00:00 2026) (700.12ms elapsed) ***
CPU Power: 1450 mW
GPU Power: 320 mW
ANE Power: 45 mW
Combined Power (CPU + GPU + ANE): 1815 mW
";
        let pm = parse_powermetrics(sample);
        assert_eq!(pm.soc_w, "1.815");
        assert_eq!(pm.cpu_mw, "1450");
        assert_eq!(pm.gpu_mw, "320");
        assert_eq!(pm.ane_mw, "45");
    }

    #[test]
    fn intel_powermetrics_parsing() {
        let sample = "\
Intel energy model derived package power (CPUs+GT+SA): 12.34W
";
        let pm = parse_powermetrics(sample);
        assert_eq!(pm.soc_w, "12.34");
        assert_eq!(pm.cpu_mw, "");
        assert_eq!(pm.gpu_mw, "");
        assert_eq!(pm.ane_mw, "");
    }

    #[test]
    fn pmset_battery_states() {
        let ac_charging = "Now drawing from 'AC Power'\n -InternalBattery-0 (id=123)\t84%; charging; 0:45 remaining present: true\n";
        assert_eq!(
            parse_pmset(ac_charging),
            BatteryMetrics {
                pct: "84".to_string(),
                ac: 1,
                charging: 1
            }
        );

        let batt_discharging = "Now drawing from 'Battery Power'\n -InternalBattery-0 (id=123)\t62%; discharging; 3:12 remaining present: true\n";
        assert_eq!(
            parse_pmset(batt_discharging),
            BatteryMetrics {
                pct: "62".to_string(),
                ac: 0,
                charging: 0
            }
        );
    }

    #[test]
    fn ioreg_unsigned_overflow_wraparound() {
        // 2^64 - 1225 = 18446744073709550391 -> -1225 mA at 11450 mV -> 14.02625 W -> 14.03
        let ioreg_discharging = "\
+-o AppleSmartBattery  <class AppleSmartBattery>
    {
      \"InstantAmperage\" = 18446744073709550391
      \"Voltage\" = 11450
    }
";
        assert_eq!(parse_ioreg(ioreg_discharging), "14.03");

        // Positive amperage while charging -> 0.00 W discharge
        let ioreg_charging = "\
    {
      \"InstantAmperage\" = 1500
      \"Voltage\" = 12600
    }
";
        assert_eq!(parse_ioreg(ioreg_charging), "0.00");
    }
}
