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

//! macOS system metrics parsers (`top`, `sysctl`, `vm_stat`, `pmset`, `df`, `ioreg`, `netstat`, `route`).

use crate::json::{JsonMap, JsonValue};
use crate::time_util::Timestamp;

/// Payload of `GET /v1/metrics`.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct Snapshot {
    pub sampled_at: Timestamp,
    pub hostname: String,
    pub uptime_seconds: i64,
    pub cpu: CPU,
    pub memory: Memory,
    pub battery: Battery,
    pub disk: Disk,
    pub network: Network,
    pub thermal: Thermal,
}

impl Snapshot {
    pub fn to_json(&self) -> JsonValue {
        self.to_json_value()
    }

    pub fn to_json_value(&self) -> JsonValue {
        let mut m = JsonMap::new();
        m.insert(
            "sampled_at",
            JsonValue::from_str_val(self.sampled_at.to_rfc3339()),
        );
        m.insert("hostname", JsonValue::from_str_val(&self.hostname));
        m.insert("uptime_seconds", JsonValue::from_i64(self.uptime_seconds));
        m.insert("cpu", self.cpu.to_json_value());
        m.insert("memory", self.memory.to_json_value());
        m.insert("battery", self.battery.to_json_value());
        m.insert("disk", self.disk.to_json_value());
        m.insert("network", self.network.to_json_value());
        m.insert("thermal", self.thermal.to_json_value());
        JsonValue::Object(m)
    }

    pub fn to_json_string(&self) -> String {
        self.to_json_value().to_json_string()
    }
}

/// Payload of `GET /v1/host`.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct Host {
    pub hostname: String,
    pub os_version: String,
    pub build: String,
    pub arch: String,
    pub chip: String,
    pub cores: i32,
    pub memory_bytes: i64,
    pub tailscale_ip: String,
    pub mac_address: String,
    pub wake_on_lan: bool,
}

impl Host {
    pub fn to_json(&self) -> JsonValue {
        self.to_json_value()
    }

    pub fn to_json_value(&self) -> JsonValue {
        let mut m = JsonMap::new();
        m.insert("hostname", JsonValue::from_str_val(&self.hostname));
        m.insert("os_version", JsonValue::from_str_val(&self.os_version));
        m.insert("build", JsonValue::from_str_val(&self.build));
        m.insert("arch", JsonValue::from_str_val(&self.arch));
        m.insert("chip", JsonValue::from_str_val(&self.chip));
        m.insert("cores", JsonValue::from_i32(self.cores));
        m.insert("memory_bytes", JsonValue::from_i64(self.memory_bytes));
        m.insert("tailscale_ip", JsonValue::from_str_val(&self.tailscale_ip));
        if !self.mac_address.is_empty() {
            m.insert("mac_address", JsonValue::from_str_val(&self.mac_address));
        }
        m.insert("wake_on_lan", JsonValue::from_bool(self.wake_on_lan));
        JsonValue::Object(m)
    }

    pub fn to_json_string(&self) -> String {
        self.to_json_value().to_json_string()
    }
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct CPU {
    pub ready: bool,
    pub user_percent: f64,
    pub sys_percent: f64,
    pub idle_percent: f64,
    pub busy_percent: f64,
    pub load_avg_1: f64,
    pub load_avg_5: f64,
    pub load_avg_15: f64,
}

impl CPU {
    pub fn to_json(&self) -> JsonValue {
        self.to_json_value()
    }

    pub fn to_json_value(&self) -> JsonValue {
        let mut m = JsonMap::new();
        m.insert("ready", JsonValue::from_bool(self.ready));
        m.insert("user_percent", JsonValue::from_f64(self.user_percent));
        m.insert("sys_percent", JsonValue::from_f64(self.sys_percent));
        m.insert("idle_percent", JsonValue::from_f64(self.idle_percent));
        m.insert("busy_percent", JsonValue::from_f64(self.busy_percent));
        m.insert("load_avg_1", JsonValue::from_f64(self.load_avg_1));
        m.insert("load_avg_5", JsonValue::from_f64(self.load_avg_5));
        m.insert("load_avg_15", JsonValue::from_f64(self.load_avg_15));
        JsonValue::Object(m)
    }
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct Memory {
    pub ready: bool,
    pub total_bytes: i64,
    pub used_bytes: i64,
    pub wired_bytes: i64,
    pub active_bytes: i64,
    pub compressed_bytes: i64,
    pub free_bytes: i64,
    pub swap_used_bytes: i64,
    pub used_percent: f64,
}

impl Memory {
    pub fn to_json(&self) -> JsonValue {
        self.to_json_value()
    }

    pub fn to_json_value(&self) -> JsonValue {
        let mut m = JsonMap::new();
        m.insert("ready", JsonValue::from_bool(self.ready));
        m.insert("total_bytes", JsonValue::from_i64(self.total_bytes));
        m.insert("used_bytes", JsonValue::from_i64(self.used_bytes));
        m.insert("wired_bytes", JsonValue::from_i64(self.wired_bytes));
        m.insert("active_bytes", JsonValue::from_i64(self.active_bytes));
        m.insert(
            "compressed_bytes",
            JsonValue::from_i64(self.compressed_bytes),
        );
        m.insert("free_bytes", JsonValue::from_i64(self.free_bytes));
        m.insert("swap_used_bytes", JsonValue::from_i64(self.swap_used_bytes));
        m.insert("used_percent", JsonValue::from_f64(self.used_percent));
        JsonValue::Object(m)
    }
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct Battery {
    pub present: bool,
    pub percent: i32,
    pub status: String,
    pub source: String,
    pub time_remaining: String,
    pub temperature_c: Option<f64>,
}

impl Battery {
    pub fn to_json(&self) -> JsonValue {
        self.to_json_value()
    }

    pub fn to_json_value(&self) -> JsonValue {
        let mut m = JsonMap::new();
        m.insert("present", JsonValue::from_bool(self.present));
        m.insert("percent", JsonValue::from_i32(self.percent));
        m.insert("status", JsonValue::from_str_val(&self.status));
        m.insert("source", JsonValue::from_str_val(&self.source));
        if !self.time_remaining.is_empty() {
            m.insert(
                "time_remaining",
                JsonValue::from_str_val(&self.time_remaining),
            );
        }
        match self.temperature_c {
            Some(t) => m.insert("temperature_c", JsonValue::from_f64(t)),
            None => m.insert("temperature_c", JsonValue::Null),
        }
        JsonValue::Object(m)
    }
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct Disk {
    pub ready: bool,
    pub mount: String,
    pub total_bytes: i64,
    pub used_bytes: i64,
    pub avail_bytes: i64,
    pub used_percent: f64,
}

impl Disk {
    pub fn to_json(&self) -> JsonValue {
        self.to_json_value()
    }

    pub fn to_json_value(&self) -> JsonValue {
        let mut m = JsonMap::new();
        m.insert("ready", JsonValue::from_bool(self.ready));
        m.insert("mount", JsonValue::from_str_val(&self.mount));
        m.insert("total_bytes", JsonValue::from_i64(self.total_bytes));
        m.insert("used_bytes", JsonValue::from_i64(self.used_bytes));
        m.insert("avail_bytes", JsonValue::from_i64(self.avail_bytes));
        m.insert("used_percent", JsonValue::from_f64(self.used_percent));
        JsonValue::Object(m)
    }
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct Network {
    pub ready: bool,
    pub interface: String,
    pub rx_bytes: u64,
    pub tx_bytes: u64,
    pub rx_bytes_per_sec: f64,
    pub tx_bytes_per_sec: f64,
}

impl Network {
    pub fn to_json(&self) -> JsonValue {
        self.to_json_value()
    }

    pub fn to_json_value(&self) -> JsonValue {
        let mut m = JsonMap::new();
        m.insert("ready", JsonValue::from_bool(self.ready));
        m.insert("interface", JsonValue::from_str_val(&self.interface));
        m.insert("rx_bytes", JsonValue::from_u64(self.rx_bytes));
        m.insert("tx_bytes", JsonValue::from_u64(self.tx_bytes));
        m.insert(
            "rx_bytes_per_sec",
            JsonValue::from_f64(self.rx_bytes_per_sec),
        );
        m.insert(
            "tx_bytes_per_sec",
            JsonValue::from_f64(self.tx_bytes_per_sec),
        );
        JsonValue::Object(m)
    }
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct Thermal {
    pub ready: bool,
    pub pressure: String,
}

impl Thermal {
    pub fn to_json(&self) -> JsonValue {
        self.to_json_value()
    }

    pub fn to_json_value(&self) -> JsonValue {
        let mut m = JsonMap::new();
        m.insert("ready", JsonValue::from_bool(self.ready));
        m.insert("pressure", JsonValue::from_str_val(&self.pressure));
        JsonValue::Object(m)
    }
}

/// Parses the `CPU usage: 11.42% user, 6.18% sys, 82.39% idle` line from `top -l 1 -n 0`.
pub fn parse_top(out: &str) -> Option<(f64, f64, f64)> {
    for line in out.lines() {
        if let Some(idx) = line.find("CPU usage:") {
            let rest = &line[idx + "CPU usage:".len()..];
            // Expect: "<user>% user, <sys>% sys, <idle>% idle"
            let parts: Vec<&str> = rest.split(',').collect();
            if parts.len() < 3 {
                continue;
            }
            let parse_pct = |part: &str, suffix: &str| -> Option<f64> {
                let part = part.trim();
                let part = part.strip_suffix(suffix)?.trim();
                let part = part.strip_suffix('%')?.trim();
                part.parse::<f64>().ok()
            };
            if let (Some(u), Some(s), Some(i)) = (
                parse_pct(parts[0], "user"),
                parse_pct(parts[1], "sys"),
                parse_pct(parts[2], "idle"),
            ) {
                return Some((u, s, i));
            }
        }
    }
    None
}

/// Parses `{ 2.41 2.18 1.97 }` (or bare `2.41 2.18 1.97`) from `sysctl -n vm.loadavg`.
pub fn parse_load_avg(out: &str) -> Option<(f64, f64, f64)> {
    let cleaned = out.replace(['{', '}'], " ");
    let nums: Vec<f64> = cleaned
        .split_whitespace()
        .filter_map(|t| t.parse::<f64>().ok())
        .collect();
    if nums.len() >= 3 {
        Some((nums[0], nums[1], nums[2]))
    } else {
        None
    }
}

/// Parses `vm_stat` output and combines it with `hw.memsize` (`total_bytes`).
pub fn parse_vm_stat(out: &str, total_bytes: i64) -> Memory {
    let mut page_size: i64 = 16384;
    for line in out.lines() {
        if let Some(idx) = line.find("page size of ") {
            let after = &line[idx + "page size of ".len()..];
            if let Some(end) = after.find(" bytes") {
                if let Ok(ps) = after[..end].trim().parse::<i64>() {
                    if ps > 0 {
                        page_size = ps;
                        break;
                    }
                }
            }
        }
    }

    let mut pages = std::collections::HashMap::new();
    for line in out.lines() {
        if let Some((k, v)) = line.split_once(':') {
            let key = k.trim();
            let val_str = v.trim().trim_end_matches('.');
            if let Ok(n) = val_str.parse::<i64>() {
                pages.insert(key, n);
            }
        }
    }

    if pages.is_empty() {
        return Memory::default();
    }

    let active = pages.get("Pages active").copied().unwrap_or(0) * page_size;
    let wired = pages.get("Pages wired down").copied().unwrap_or(0) * page_size;
    let compressed = pages
        .get("Pages occupied by compressor")
        .copied()
        .unwrap_or(0)
        * page_size;
    let free = pages.get("Pages free").copied().unwrap_or(0) * page_size;
    let inactive = pages.get("Pages inactive").copied().unwrap_or(0) * page_size;
    let speculative = pages.get("Pages speculative").copied().unwrap_or(0) * page_size;

    let used = active + wired + compressed;
    let mut m = Memory {
        ready: true,
        total_bytes,
        used_bytes: used,
        wired_bytes: wired,
        active_bytes: active,
        compressed_bytes: compressed,
        free_bytes: free + inactive + speculative,
        swap_used_bytes: 0,
        used_percent: 0.0,
    };
    if total_bytes > 0 {
        m.free_bytes = (total_bytes - used).max(0);
        m.used_percent = (used as f64 / total_bytes as f64) * 100.0;
    }
    m
}

/// Parses `pmset -g batt`.
pub fn parse_battery(out: &str) -> Battery {
    let mut b = Battery::default();
    for line in out.lines() {
        if let Some(idx) = line.find("Now drawing from '") {
            let after = &line[idx + "Now drawing from '".len()..];
            if let Some(end) = after.find('\'') {
                b.source = after[..end].to_string();
            }
        }
        if line.contains("InternalBattery") {
            // Find "<digits>%; <status>; <rest>"
            if let Some(semi1) = line.find("%;") {
                let before_pct = &line[..semi1];
                let digits_start = before_pct
                    .rfind(|c: char| !c.is_ascii_digit())
                    .map(|i| i + 1)
                    .unwrap_or(0);
                if let Ok(pct) = before_pct[digits_start..].parse::<i32>() {
                    let after_semi1 = line[semi1 + 2..].trim();
                    if let Some((status_part, rem_part)) = after_semi1.split_once(';') {
                        b.present = true;
                        b.percent = pct;
                        b.status = status_part.trim().to_string();
                        let rem = rem_part.trim();
                        if let Some(rem_idx) = rem.find(" remaining") {
                            let candidate = rem[..rem_idx].trim();
                            if !candidate.contains("(no estimate)") {
                                b.time_remaining = candidate.to_string();
                            }
                        }
                    }
                }
            }
        }
    }
    b
}

/// Parses `df -k /`.
pub fn parse_df(out: &str) -> Disk {
    let lines: Vec<&str> = out.trim().lines().collect();
    if lines.len() < 2 {
        return Disk::default();
    }
    let fields: Vec<&str> = lines[1].split_whitespace().collect();
    if fields.len() < 6 {
        return Disk::default();
    }
    let total_kb = match fields[1].parse::<i64>() {
        Ok(v) if v > 0 => v,
        _ => return Disk::default(),
    };
    let used_kb = match fields[2].parse::<i64>() {
        Ok(v) => v,
        Err(_) => return Disk::default(),
    };
    let avail_kb = match fields[3].parse::<i64>() {
        Ok(v) => v,
        Err(_) => return Disk::default(),
    };
    let mount = fields[fields.len() - 1].to_string();
    let total = total_kb * 1024;
    let used = used_kb * 1024;
    let avail = avail_kb * 1024;
    let mut pct = 0.0;
    if used + avail > 0 {
        pct = (used as f64 / (used + avail) as f64) * 100.0;
    }
    Disk {
        ready: true,
        mount,
        total_bytes: total,
        used_bytes: used,
        avail_bytes: avail,
        used_percent: pct,
    }
}

/// Parses `ioreg -rn AppleSmartBattery` for centi-degrees Celsius battery temperature.
pub fn parse_nested_battery_temperature(out: &str) -> Option<f64> {
    let stripped = without_commands(out);
    for line in stripped.lines() {
        if let Some(idx) = line.find("\"Temperature\"") {
            let after = &line[idx + "\"Temperature\"".len()..];
            let after = after.trim_start();
            if let Some(after_eq) = after.strip_prefix('=') {
                let after_eq = after_eq.trim_start();
                let digits_len = after_eq.bytes().take_while(|b| b.is_ascii_digit()).count();
                if digits_len > 0 {
                    if let Ok(raw) = after_eq[..digits_len].parse::<i64>() {
                        if (1000..=4000).contains(&raw) {
                            return Some((raw as f64) / 100.0);
                        }
                    }
                }
            }
        }
    }
    None
}

/// Strips `"Commands" = { ... }` sub-dictionaries from `ioreg` output so nested
/// `"Temperature"` keys inside `"Commands"` are not mistaken for battery temperature.
pub fn without_commands(out: &str) -> String {
    let Some(i) = out.find("\"Commands\"") else {
        return out.to_string();
    };
    let after = &out[i..];
    let Some(rel_open) = after.find('{') else {
        return out.to_string();
    };
    let open = i + rel_open;
    let mut depth = 0i32;
    for (offset, ch) in out[open..].char_indices() {
        match ch {
            '{' => depth += 1,
            '}' => {
                depth -= 1;
                if depth == 0 {
                    let end = open + offset + 1;
                    let mut result = String::with_capacity(out.len() - (end - i));
                    result.push_str(&out[..i]);
                    result.push_str(&out[end..]);
                    return result;
                }
            }
            _ => {}
        }
    }
    out.to_string()
}

/// Extracts `(rx_bytes, tx_bytes)` for `iface` from `netstat -ibn`.
pub fn parse_netstat(out: &str, iface: &str) -> Option<(u64, u64)> {
    if iface.is_empty() {
        return None;
    }
    for line in out.lines() {
        let fields: Vec<&str> = line.split_whitespace().collect();
        if fields.len() < 10 || fields[0] != iface {
            continue;
        }
        if !fields[2].starts_with("<Link#") {
            continue;
        }
        if let (Ok(rx), Ok(tx)) = (fields[6].parse::<u64>(), fields[9].parse::<u64>()) {
            return Some((rx, tx));
        }
    }
    None
}

/// Extracts the interface name from `route -n get default`.
pub fn parse_default_interface(out: &str) -> String {
    for line in out.lines() {
        let trimmed = line.trim();
        if let Some(rest) = trimmed.strip_prefix("interface:") {
            let token = rest.split_whitespace().next().unwrap_or("");
            if !token.is_empty() {
                return token.to_string();
            }
        }
    }
    String::new()
}

/// Parses `pmset -g therm`.
pub fn parse_therm(out: &str) -> Thermal {
    let lower = out.to_ascii_lowercase();
    if lower.contains("no thermal warning level has been recorded")
        && lower.contains("no performance warning level has been recorded")
    {
        return Thermal {
            ready: true,
            pressure: "nominal".to_string(),
        };
    }

    // Check CPU_Scheduler_Limit / CPU_Speed_Limit = <N>
    for key in ["cpu_scheduler_limit", "cpu_speed_limit"] {
        if let Some(idx) = lower.find(key) {
            let after = lower[idx + key.len()..].trim_start();
            if let Some(after_eq) = after.strip_prefix('=') {
                let after_eq = after_eq.trim_start();
                let digits_len = after_eq.bytes().take_while(|b| b.is_ascii_digit()).count();
                if digits_len > 0 {
                    if let Ok(lim) = after_eq[..digits_len].parse::<i32>() {
                        let pressure = if lim <= 50 {
                            "critical"
                        } else if lim < 100 {
                            "serious"
                        } else {
                            "nominal"
                        };
                        return Thermal {
                            ready: true,
                            pressure: pressure.to_string(),
                        };
                    }
                }
            }
        }
    }

    // Check thermal warning level: <word>
    if let Some(idx) = lower.find("thermal warning level") {
        let after = lower[idx + "thermal warning level".len()..].trim_start();
        let after = after
            .strip_prefix(':')
            .or_else(|| after.strip_prefix('='))
            .unwrap_or(after)
            .trim_start();
        let lvl: String = after
            .chars()
            .take_while(|c| c.is_ascii_alphanumeric())
            .collect();
        if lvl.contains("critical") || lvl.contains("sleeping") {
            return Thermal {
                ready: true,
                pressure: "critical".to_string(),
            };
        }
        if lvl.contains("moderate") || lvl.contains("heavy") || lvl.contains("serious") {
            return Thermal {
                ready: true,
                pressure: "serious".to_string(),
            };
        }
        if lvl.contains("nominal") || lvl.contains("normal") || lvl == "0" {
            return Thermal {
                ready: true,
                pressure: "nominal".to_string(),
            };
        }
    }

    Thermal {
        ready: false,
        pressure: "unknown".to_string(),
    }
}

/// Parses `{ sec = 1757180000, usec = 123456 } ...` from `sysctl -n kern.boottime`.
pub fn parse_boottime(out: &str, now: Timestamp) -> Option<i64> {
    let idx = out.find("sec =")?;
    let after = out[idx + "sec =".len()..].trim_start();
    let digits_len = after.bytes().take_while(|b| b.is_ascii_digit()).count();
    if digits_len == 0 {
        return None;
    }
    let sec = after[..digits_len].parse::<i64>().ok()?;
    let now_sec = now.unix_secs();
    if sec <= 0 || now_sec < sec {
        return None;
    }
    Some(now_sec - sec)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_top() {
        let sample = "Processes: 582 total, 3 running, 579 sleeping, 3421 threads \n\
2026/09/07 01:12:44\n\
Load Avg: 2.31, 2.04, 1.89 \n\
CPU usage: 11.42% user, 6.18% sys, 82.39% idle \n\
SharedLibs: 642M resident, 98M data, 62M linkedit.\n";
        let (u, s, i) = parse_top(sample).expect("parse_top failed");
        assert_eq!((u, s, i), (11.42, 6.18, 82.39));
    }

    #[test]
    fn test_parse_load_avg() {
        for inp in ["{ 2.41 2.18 1.97 }\n", "2.41 2.18 1.97\n"] {
            let (l1, l5, l15) = parse_load_avg(inp).expect("parse_load_avg failed");
            assert_eq!((l1, l5, l15), (2.41, 2.18, 1.97));
        }
    }

    #[test]
    fn test_parse_vm_stat() {
        let sample = "Mach Virtual Memory Statistics: (page size of 16384 bytes)\n\
Pages free:                              120000.\n\
Pages active:                            410000.\n\
Pages inactive:                          390000.\n\
Pages speculative:                         8000.\n\
Pages throttled:                              0.\n\
Pages wired down:                        180000.\n\
Pages purgeable:                          12000.\n\
\"Translation faults\":                 912834912.\n\
Pages copy-on-write:                   41293841.\n\
Pages zero filled:                    512938412.\n\
Pages reactivated:                      8123941.\n\
Pages purged:                           2193841.\n\
File-backed pages:                       310000.\n\
Anonymous pages:                         498000.\n\
Pages stored in compressor:              220000.\n\
Pages occupied by compressor:             90000.\n";
        let total = 32i64 * 1024 * 1024 * 1024;
        let m = parse_vm_stat(sample, total);
        assert!(m.ready);
        let want_used = (410000i64 + 180000 + 90000) * 16384;
        assert_eq!(m.used_bytes, want_used);
        assert_eq!(m.used_bytes + m.free_bytes, total);
        assert!(m.used_percent > 30.0 && m.used_percent < 36.0);
    }

    #[test]
    fn test_parse_battery_discharging() {
        let sample = "Now drawing from 'Battery Power'\n\
 -InternalBattery-0 (id=20316259)\t78%; discharging; 4:12 remaining present: true\n";
        let b = parse_battery(sample);
        assert!(b.present);
        assert_eq!(b.percent, 78);
        assert_eq!(b.status, "discharging");
        assert_eq!(b.source, "Battery Power");
        assert_eq!(b.time_remaining, "4:12");
    }

    #[test]
    fn test_parse_battery_ac_charged_no_estimate() {
        let sample = "Now drawing from 'AC Power'\n\
 -InternalBattery-0 (id=20316259)\t100%; charged; 0:00 remaining present: true\n";
        let b = parse_battery(sample);
        assert!(b.present);
        assert_eq!(b.percent, 100);
        assert_eq!(b.status, "charged");
        assert_eq!(b.source, "AC Power");
    }

    #[test]
    fn test_parse_battery_desktop_mac_no_battery() {
        let sample = "Now drawing from 'AC Power'\n";
        let b = parse_battery(sample);
        assert!(!b.present);
        assert_eq!(b.source, "AC Power");
    }

    #[test]
    fn test_parse_nested_battery_temperature() {
        let sample = "+-o AppleSmartBattery  <class AppleSmartBattery>\n\
    {\n\
      \"Commands\" = {\"Temperature\"=0,\"Flags\"=5}\n\
      \"VirtualTemperature\" = 2948\n\
      \"Temperature\" = 3015\n\
    }\n";
        let t = parse_nested_battery_temperature(sample).expect("temperature should parse");
        assert!((t - 30.15).abs() < 0.001);
    }

    #[test]
    fn test_parse_df() {
        let sample = "Filesystem   1024-blocks      Used Available Capacity iused ifree %iused  Mounted on\n\
/dev/disk3s1s1 971350180 412398120 541203940    44%  412398 5412039400    0%   /\n";
        let d = parse_df(sample);
        assert!(d.ready);
        assert_eq!(d.mount, "/");
        assert_eq!(d.total_bytes, 971350180i64 * 1024);
        assert!(d.used_percent >= 43.0 && d.used_percent <= 44.0);
    }

    #[test]
    fn test_parse_netstat() {
        let sample = "Name       Mtu   Network       Address            Ipkts Ierrs     Ibytes    Opkts Oerrs     Obytes  Coll\n\
lo0        16384 <Link#1>                        192831     0   48192831   192831     0   48192831     0\n\
lo0        16384 127           127.0.0.1         192831     -   48192831   192831     -   48192831     -\n\
en0        1500  <Link#14>     a4:cf:99:12:34:56 9812734     0 8912734912  4129834     0 1293847123     0\n\
en0        1500  192.168.1     192.168.1.42     9812734     - 8912734912  4129834     - 1293847123     -\n";
        let (rx, tx) = parse_netstat(sample, "en0").expect("parse_netstat failed");
        assert_eq!(rx, 8912734912);
        assert_eq!(tx, 1293847123);
    }

    #[test]
    fn test_parse_default_interface() {
        let sample = "   route to: default\n\
destination: default\n\
       mask: default\n\
    gateway: 192.168.1.1\n\
  interface: en0\n\
      flags: <UP,GATEWAY,DONE,STATIC,PRCLONING,GLOBAL>\n";
        assert_eq!(parse_default_interface(sample), "en0");
    }

    #[test]
    fn test_parse_therm() {
        let cases = [
            (
                "Note: No thermal warning level has been recorded\nNote: No performance warning level has been recorded\n",
                "nominal",
                true,
            ),
            (
                "t = 0.00\n\tCPU_Scheduler_Limit \t= 100\n\tCPU_Available_CPUs \t= 12\n\tCPU_Speed_Limit \t= 100\n",
                "nominal",
                true,
            ),
            ("\tCPU_Speed_Limit \t= 72\n", "serious", true),
            ("\tCPU_Speed_Limit \t= 40\n", "critical", true),
            ("", "unknown", false),
        ];
        for (inp, want_p, want_ok) in cases {
            let th = parse_therm(inp);
            assert_eq!(th.ready, want_ok, "input {:?}", inp);
            assert_eq!(th.pressure, want_p, "input {:?}", inp);
        }
    }

    #[test]
    fn test_parse_boottime() {
        let now = Timestamp::from_unix_secs(1757200000);
        let sample = "{ sec = 1757180000, usec = 412893 } Sun Sep  6 19:13:20 2026\n";
        let up = parse_boottime(sample, now).expect("parse_boottime failed");
        assert_eq!(up, 20000);
    }
}
