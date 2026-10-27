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
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

//! Rust migration of `test_wifi_provisioning.py`:
//! macOS Keychain & CoreWLAN Wi-Fi provisioning, `wifi_set` serialization,
//! Zero-Typing Companion Sync (`wifi_sync` -> `wifi_set` / `wifi_sync_error`),
//! IEEE 802.11 32-byte SSID / 63-byte WPA2 bounds, and firmware NVS simulation.

use crate::{json_escape_str, json_extract_str};
use std::collections::BTreeMap;

pub fn build_wifi_set_payload(ssid: &str, password: &str) -> String {
    format!(
        "{{\"type\":\"wifi_set\",\"ssid\":\"{}\",\"password\":\"{}\"}}\n",
        json_escape_str(ssid),
        json_escape_str(password)
    )
}

pub fn handle_incoming_serial_line<F, W>(
    line: &str,
    on_action: &mut F,
    resolve_wifi: &W,
) -> Option<String>
where
    F: FnMut(&str),
    W: Fn() -> Option<(String, String)>,
{
    if json_extract_str(line, "type").as_deref() != Some("cmd") {
        return None;
    }
    let action = json_extract_str(line, "action")?;
    on_action(&action);
    if action == "wifi_sync" {
        if let Some((ssid, pass)) = resolve_wifi() {
            return Some(build_wifi_set_payload(&ssid, &pass));
        } else {
            return Some(
                "{\"type\":\"wifi_sync_error\",\"reason\":\"no_credentials\"}\n".to_string(),
            );
        }
    }
    None
}

pub struct FirmwareNvsSim {
    pub store: BTreeMap<(String, String), String>,
    pub connected_ssid: Option<String>,
    pub tx_lines: Vec<String>,
}

impl Default for FirmwareNvsSim {
    fn default() -> Self {
        Self::new()
    }
}

impl FirmwareNvsSim {
    pub fn new() -> Self {
        Self {
            store: BTreeMap::new(),
            connected_ssid: None,
            tx_lines: Vec::new(),
        }
    }

    pub fn handle_serial_line(&mut self, line: &str) -> bool {
        let msg_type = json_extract_str(line, "type").or_else(|| json_extract_str(line, "cmd"));
        let msg_type = match msg_type {
            Some(t) => t,
            None => return false,
        };
        if msg_type != "wifi_set" {
            return false;
        }
        let ssid = json_extract_str(line, "ssid").unwrap_or_default();
        let password = json_extract_str(line, "password")
            .or_else(|| json_extract_str(line, "pass"))
            .unwrap_or_default();
        if ssid.is_empty() || ssid.len() > 32 || password.len() > 63 {
            self.tx_lines.push(
                "{\"type\":\"wifi_status\",\"connected\":false,\"error\":\"invalid_length\"}"
                    .to_string(),
            );
            return false;
        }
        self.store.insert(
            ("wifi_config".to_string(), "ssid".to_string()),
            ssid.clone(),
        );
        self.store
            .insert(("wifi_config".to_string(), "pass".to_string()), password);
        self.store.insert(
            ("wifi_config".to_string(), "enabled".to_string()),
            "true".to_string(),
        );
        self.connected_ssid = Some(ssid.clone());
        self.tx_lines.push(format!(
            "{{\"type\":\"wifi_status\",\"connected\":true,\"ssid\":\"{ssid}\",\"ip\":\"192.168.1.42\"}}"
        ));
        true
    }

    pub fn power_cycle(&mut self) {
        self.connected_ssid = None;
        if self
            .store
            .get(&("wifi_config".to_string(), "enabled".to_string()))
            .map(|v| v == "true")
            .unwrap_or(false)
        {
            if let Some(ssid) = self
                .store
                .get(&("wifi_config".to_string(), "ssid".to_string()))
                .cloned()
            {
                if !ssid.is_empty() {
                    self.connected_ssid = Some(ssid);
                }
            }
        }
    }

    pub fn disable_radio(&mut self) {
        self.store.insert(
            ("wifi_config".to_string(), "enabled".to_string()),
            "false".to_string(),
        );
        self.connected_ssid = None;
    }
}

pub fn firmware_dispatch(line: &str) -> &'static str {
    let trimmed = line.trim();
    if !trimmed.starts_with('{') || !trimmed.ends_with('}') {
        return "ignored";
    }
    if let Some(cmd) = json_extract_str(trimmed, "cmd") {
        if cmd == "wifi_set" {
            return "wifi_set";
        }
        if cmd == "wifi_status" || cmd == "radio_status" {
            return "radio_status_query";
        }
    }
    if let Some(pkt_type) = json_extract_str(trimmed, "type") {
        return match pkt_type.as_str() {
            "stats" => "stats",
            "app" => "app",
            "agent_ci" => "agent_ci",
            "deck_config" => "deck_config",
            _ => "ignored",
        };
    }
    if trimmed.contains("\"cpu\"") {
        return "stats";
    }
    "ignored"
}

pub fn parse_networksetup_ssid(output: &str) -> Option<String> {
    if output.contains("You are not associated") {
        return None;
    }
    if let Some((_, right)) = output.split_once("Current Wi-Fi Network:") {
        let ssid = right.trim();
        if !ssid.is_empty() {
            return Some(ssid.to_string());
        }
    }
    None
}

pub fn parse_ipconfig_ssid(output: &str) -> Option<String> {
    for line in output.lines() {
        let trimmed = line.trim();
        if let Some(rest) = trimmed.strip_prefix("SSID : ") {
            let candidate = rest.trim();
            if !candidate.is_empty() && candidate != "<redacted>" {
                return Some(candidate.to_string());
            }
        }
    }
    None
}

pub fn test_ssid_and_payload_serialization() {
    assert_eq!(
        parse_networksetup_ssid("Current Wi-Fi Network: Vitruvian-5G\n").as_deref(),
        Some("Vitruvian-5G")
    );
    assert_eq!(
        parse_networksetup_ssid("Current Wi-Fi Network: Net:Guest:2.4G\n").as_deref(),
        Some("Net:Guest:2.4G")
    );
    assert!(parse_networksetup_ssid("You are not associated with an AirPort network.\n").is_none());

    assert_eq!(
        parse_ipconfig_ssid("  SSID : BackupLabWiFi\n").as_deref(),
        Some("BackupLabWiFi")
    );
    assert!(parse_ipconfig_ssid("  SSID : <redacted>\n").is_none());

    let payload = build_wifi_set_payload("HomeNet", "p\"a\\ss");
    assert!(payload.ends_with('\n'));
    assert!(payload.len() < 1024);
    assert_eq!(
        json_extract_str(&payload, "type").as_deref(),
        Some("wifi_set")
    );
    assert_eq!(
        json_extract_str(&payload, "ssid").as_deref(),
        Some("HomeNet")
    );
    assert_eq!(
        json_extract_str(&payload, "password").as_deref(),
        Some("p\"a\\ss")
    );

    // Also verify mac_stats_daemon's exported helpers directly
    assert_eq!(
        mac_stats_daemon::parse_networksetup_ssid("Current Wi-Fi Network: Vitruvian-5G\n")
            .as_deref(),
        Some("Vitruvian-5G")
    );
    assert_eq!(
        mac_stats_daemon::parse_ipconfig_ssid("  SSID : BackupLabWiFi\n").as_deref(),
        Some("BackupLabWiFi")
    );
    let daemon_payload = mac_stats_daemon::build_wifi_set_payload("HomeNet", "p\"a\\ss");
    assert_eq!(
        json_extract_str(&daemon_payload, "cmd").as_deref(),
        Some("wifi_set")
    );
    assert_eq!(
        json_extract_str(&daemon_payload, "ssid").as_deref(),
        Some("HomeNet")
    );
    assert_eq!(
        json_extract_str(&daemon_payload, "pass").as_deref(),
        Some("p\"a\\ss")
    );
    let daemon_pkt = mac_stats_daemon::serialize_wifi_set_packet("HomeNet", "pw");
    assert!(daemon_pkt.ends_with(b"\n"));
    assert!(daemon_pkt.len() < 1024);
}

pub fn test_zero_typing_companion_sync() {
    let mut actions = Vec::new();
    let resp = handle_incoming_serial_line(
        "{\"type\":\"cmd\",\"action\":\"wifi_sync\"}",
        &mut |act| actions.push(act.to_string()),
        &|| Some(("ZeroTouchNet".to_string(), "ZeroTouchSecret99".to_string())),
    )
    .expect("expected wifi_set response");

    assert_eq!(actions, vec!["wifi_sync"]);
    assert_eq!(json_extract_str(&resp, "type").as_deref(), Some("wifi_set"));
    assert_eq!(
        json_extract_str(&resp, "ssid").as_deref(),
        Some("ZeroTouchNet")
    );
    assert_eq!(
        json_extract_str(&resp, "password").as_deref(),
        Some("ZeroTouchSecret99")
    );

    let err_resp = handle_incoming_serial_line(
        "{\"type\":\"cmd\",\"action\":\"wifi_sync\"}",
        &mut |_| {},
        &|| None,
    )
    .expect("expected wifi_sync_error response");
    assert_eq!(
        json_extract_str(&err_resp, "type").as_deref(),
        Some("wifi_sync_error")
    );
}

pub fn test_firmware_nvs_and_80211_bounds() {
    let mut sim = FirmwareNvsSim::new();
    let pkt = build_wifi_set_payload("StudioWiFi", "correct-horse-battery");
    assert!(sim.handle_serial_line(&pkt));
    assert_eq!(sim.connected_ssid.as_deref(), Some("StudioWiFi"));

    let mut sim_empty = FirmwareNvsSim::new();
    assert!(
        !sim_empty.handle_serial_line("{\"type\":\"wifi_set\",\"ssid\":\"\",\"password\":\"abc\"}")
    );

    let ssid_32 = "A".repeat(32);
    let ssid_33 = "A".repeat(33);
    assert!(sim.handle_serial_line(&build_wifi_set_payload(&ssid_32, "validpass")));
    assert!(!sim.handle_serial_line(&build_wifi_set_payload(&ssid_33, "validpass")));

    let pass_63 = "p".repeat(63);
    let pass_64 = "p".repeat(64);
    assert!(sim.handle_serial_line(&build_wifi_set_payload("TestNet", &pass_63)));
    assert!(!sim.handle_serial_line(&build_wifi_set_payload("TestNet", &pass_64)));

    let emoji_8 = "📡".repeat(8);
    assert_eq!(emoji_8.len(), 32);
    assert!(sim.handle_serial_line(&build_wifi_set_payload(&emoji_8, "pass")));

    let emoji_ssid = "📡".repeat(9);
    assert_eq!(emoji_ssid.len(), 36);
    assert!(!sim.handle_serial_line(&build_wifi_set_payload(&emoji_ssid, "pass")));

    // Power-cycle persistence, reprovisioning, and radio disable
    let mut nvs_sim = FirmwareNvsSim::new();
    assert!(
        nvs_sim.handle_serial_line(&mac_stats_daemon::build_wifi_set_payload(
            "OfficeWiFi",
            "hunter2"
        ))
    );
    assert_eq!(nvs_sim.connected_ssid.as_deref(), Some("OfficeWiFi"));
    nvs_sim.power_cycle();
    assert_eq!(nvs_sim.connected_ssid.as_deref(), Some("OfficeWiFi"));
    assert!(
        nvs_sim.handle_serial_line(&mac_stats_daemon::build_wifi_set_payload(
            "HomeWiFi",
            "newsecret"
        ))
    );
    nvs_sim.power_cycle();
    assert_eq!(nvs_sim.connected_ssid.as_deref(), Some("HomeWiFi"));
    nvs_sim.disable_radio();
    nvs_sim.power_cycle();
    assert!(nvs_sim.connected_ssid.is_none());

    // Firmware dispatch priority
    assert_eq!(
        firmware_dispatch(r#"{"cmd":"wifi_set","type":"stats","ssid":"X","pass":"Y"}"#),
        "wifi_set"
    );
    assert_eq!(
        firmware_dispatch(r#"{"cmd":"wifi_status"}"#),
        "radio_status_query"
    );
    assert_eq!(
        firmware_dispatch(r#"{"cmd":"radio_status"}"#),
        "radio_status_query"
    );
    assert_eq!(firmware_dispatch(r#"{"type":"stats","cpu":10}"#), "stats");
    assert_eq!(firmware_dispatch(r#"{"cpu":5}"#), "stats");
    assert_eq!(firmware_dispatch(r#"{"type":"app"}"#), "app");
    assert_eq!(firmware_dispatch(r#"{"type":"agent_ci"}"#), "agent_ci");
    assert_eq!(
        firmware_dispatch(r#"{"type":"deck_config"}"#),
        "deck_config"
    );
    assert_eq!(firmware_dispatch(r#"{"type":"unknown"}"#), "ignored");
}

pub fn run_suite() -> usize {
    test_ssid_and_payload_serialization();
    test_zero_typing_companion_sync();
    test_firmware_nvs_and_80211_bounds();
    3
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn wifi_provisioning_suite() {
        assert_eq!(run_suite(), 3);
    }
}
