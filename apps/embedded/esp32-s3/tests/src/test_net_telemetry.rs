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

//! Rust migration of `test_net_telemetry.py`:
//! Wireless UDP telemetry (`vitruvian-companion.local:8266`), loopback UDP socket
//! verification, transport abstraction parity, USB/Wi-Fi link arbitration, and firmware source checks.

use crate::read_component_file;
use mac_stats_daemon::DaemonArgs;
use std::net::UdpSocket;
use std::time::Duration;

pub const MDNS_HOSTNAME: &str = "vitruvian-companion.local";
pub const NET_TELEMETRY_PORT: u16 = 8266;

const LINK_NONE: u8 = 0;
const LINK_USB: u8 = 1;
const LINK_WIFI: u8 = 2;
const LINK_ACTIVE_WINDOW_MS: i64 = 3000;

const USB_GREEN: u32 = 0x30D158;
const WIFI_CYAN: u32 = 0x64D2FF;
const STANDBY_ORANGE: u32 = 0xFF9F0A;

pub struct LinkModel {
    pub last_usb_rx_ms: Option<i64>,
    pub last_wifi_rx_ms: Option<i64>,
}

impl Default for LinkModel {
    fn default() -> Self {
        Self::new()
    }
}

impl LinkModel {
    pub fn new() -> Self {
        Self {
            last_usb_rx_ms: None,
            last_wifi_rx_ms: None,
        }
    }

    pub fn active_transport(&self, now_ms: i64) -> u8 {
        if let Some(usb) = self.last_usb_rx_ms {
            if (now_ms - usb) < LINK_ACTIVE_WINDOW_MS {
                return LINK_USB;
            }
        }
        if let Some(wifi) = self.last_wifi_rx_ms {
            if (now_ms - wifi) < LINK_ACTIVE_WINDOW_MS {
                return LINK_WIFI;
            }
        }
        LINK_NONE
    }

    pub fn badge(
        &self,
        now_ms: i64,
        ble_conn: bool,
        wifi_conn: bool,
        wifi_ip: &str,
    ) -> (String, u32) {
        let link = self.active_transport(now_ms);
        if link == LINK_USB {
            let suffix = if ble_conn { "BLE" } else { "HID" };
            (format!("● USB-C + {suffix}"), USB_GREEN)
        } else if link == LINK_WIFI {
            let suffix = if ble_conn {
                "BLE".to_string()
            } else if !wifi_ip.is_empty() {
                wifi_ip.to_string()
            } else {
                "UDP".to_string()
            };
            (format!("● Wi-Fi + {suffix}"), WIFI_CYAN)
        } else if ble_conn {
            ("● BLE KEYBOARD ACTIVE".to_string(), USB_GREEN)
        } else if wifi_conn {
            (format!("● Wi-Fi {wifi_ip}"), WIFI_CYAN)
        } else {
            ("● STANDALONE MODE".to_string(), STANDBY_ORANGE)
        }
    }
}

pub fn test_companion_discovery() {
    let default_args = DaemonArgs::default();
    assert_eq!(default_args.host, MDNS_HOSTNAME);
    assert_eq!(default_args.udp_port, NET_TELEMETRY_PORT);
    let version_h = read_component_file("include/version.h");
    assert!(version_h.contains("#define MDNS_HOSTNAME     \"vitruvian-companion\""));
    assert!(version_h.contains("#define MDNS_SERVICE      \"vitruvian\""));
    assert!(version_h.contains("#define MDNS_PROTO        \"tcp\""));
    assert!(version_h.contains("#define NET_TELEMETRY_PORT 8266"));
}

pub fn test_udp_transport_loopback() {
    let esp_sock = UdpSocket::bind("127.0.0.1:0").expect("bind esp_sock");
    let companion_sock = UdpSocket::bind("127.0.0.1:0").expect("bind companion_sock");
    esp_sock
        .set_read_timeout(Some(Duration::from_secs(2)))
        .unwrap();
    companion_sock
        .set_read_timeout(Some(Duration::from_secs(2)))
        .unwrap();

    let esp_addr = esp_sock.local_addr().unwrap();
    let companion_addr = companion_sock.local_addr().unwrap();

    let stats_line = "{\"type\":\"stats\",\"cpu\":23,\"ram\":61,\"disk\":48,\"up\":\"4d 2h\"}\n";
    let agent_line = "{\"type\":\"agent_ci\",\"agent_state\":\"CODING\",\"ci_status\":\"PASS\"}\n";
    companion_sock
        .send_to(stats_line.as_bytes(), esp_addr)
        .unwrap();
    companion_sock
        .send_to(agent_line.as_bytes(), esp_addr)
        .unwrap();

    let mut buf = [0u8; 2048];
    let (n1, _) = esp_sock.recv_from(&mut buf).unwrap();
    let msg1 = std::str::from_utf8(&buf[..n1]).unwrap();
    assert!(msg1.ends_with('\n'));
    assert!(msg1.contains("\"type\":\"stats\""));

    let (n2, _) = esp_sock.recv_from(&mut buf).unwrap();
    let msg2 = std::str::from_utf8(&buf[..n2]).unwrap();
    assert!(msg2.ends_with('\n'));
    assert!(msg2.contains("\"type\":\"agent_ci\""));

    let cmd_line = "{\"type\":\"cmd\",\"action\":\"run_checks\"}\n";
    esp_sock
        .send_to(cmd_line.as_bytes(), companion_addr)
        .unwrap();
    let (n_cmd, from_addr) = companion_sock.recv_from(&mut buf).unwrap();
    assert_eq!(from_addr.ip(), esp_addr.ip());
    let cmd_str = std::str::from_utf8(&buf[..n_cmd]).unwrap().trim();
    assert_eq!(cmd_str, "{\"type\":\"cmd\",\"action\":\"run_checks\"}");

    let multi =
        "{\"type\":\"cmd\",\"action\":\"refresh\"}\n{\"type\":\"cmd\",\"action\":\"sleep\"}\n";
    esp_sock.send_to(multi.as_bytes(), companion_addr).unwrap();
    let (n_multi, _) = companion_sock.recv_from(&mut buf).unwrap();
    let lines: Vec<&str> = std::str::from_utf8(&buf[..n_multi])
        .unwrap()
        .lines()
        .filter(|l| !l.trim().is_empty())
        .collect();
    assert_eq!(lines.len(), 2);
}

pub fn test_link_arbitration() {
    let mut m = LinkModel::new();
    assert_eq!(m.active_transport(0), LINK_NONE);

    m.last_wifi_rx_ms = Some(1000);
    assert_eq!(m.active_transport(2000), LINK_WIFI);
    assert_eq!(m.active_transport(4000), LINK_NONE);

    m.last_wifi_rx_ms = Some(2000);
    m.last_usb_rx_ms = Some(2500);
    assert_eq!(m.active_transport(3000), LINK_USB);

    m.last_usb_rx_ms = Some(1000);
    m.last_wifi_rx_ms = Some(3500);
    assert_eq!(m.active_transport(4001), LINK_WIFI);

    let m_usb = LinkModel {
        last_usb_rx_ms: Some(1000),
        last_wifi_rx_ms: None,
    };
    assert_eq!(
        m_usb.badge(2000, false, false, ""),
        ("● USB-C + HID".to_string(), USB_GREEN)
    );
    assert_eq!(
        m_usb.badge(2000, true, false, ""),
        ("● USB-C + BLE".to_string(), USB_GREEN)
    );

    let m_wifi = LinkModel {
        last_usb_rx_ms: None,
        last_wifi_rx_ms: Some(1000),
    };
    assert_eq!(
        m_wifi.badge(2000, true, true, "192.168.1.50"),
        ("● Wi-Fi + BLE".to_string(), WIFI_CYAN)
    );
    assert_eq!(
        m_wifi.badge(2000, false, true, "192.168.1.50"),
        ("● Wi-Fi + 192.168.1.50".to_string(), WIFI_CYAN)
    );

    let m_idle = LinkModel::new();
    assert_eq!(
        m_idle.badge(5000, true, false, ""),
        ("● BLE KEYBOARD ACTIVE".to_string(), USB_GREEN)
    );
    assert_eq!(
        m_idle.badge(5000, false, true, "10.0.0.9"),
        ("● Wi-Fi 10.0.0.9".to_string(), WIFI_CYAN)
    );
    assert_eq!(
        m_idle.badge(5000, false, false, ""),
        ("● STANDALONE MODE".to_string(), STANDBY_ORANGE)
    );
}

pub fn test_firmware_source_invariants() {
    let wifi_cpp = read_component_file("src/wifi_manager.cpp");
    let net_cpp = read_component_file("src/net_telemetry.cpp");
    let main_cpp = read_component_file("src/main.cpp");
    let router_h = read_component_file("src/packet_router.h");
    let router_cpp = read_component_file("src/packet_router.cpp");
    let ui_cpp = read_component_file("src/ui.cpp");
    let ota_cpp = read_component_file("src/ota_manager.cpp");
    let mac_hid_cpp = read_component_file("src/mac_hid.cpp");

    assert!(wifi_cpp.contains("MDNS.begin(MDNS_HOSTNAME)"));
    assert!(wifi_cpp.contains("MDNS.addService(MDNS_SERVICE, MDNS_PROTO, NET_TELEMETRY_PORT)"));
    assert!(wifi_cpp.contains("mdns_start();"));
    assert!(wifi_cpp.matches("mdns_stop();").count() >= 3);

    assert!(net_cpp.contains("udp.begin(NET_TELEMETRY_PORT)"));

    assert!(main_cpp.contains("packet_router_handle(json, len, LINK_CHANNEL_NET)"));
    assert!(
        main_cpp.contains("packet_router_handle(line.c_str(), line.length(), LINK_CHANNEL_USB)")
    );

    assert!(router_h.contains("#define LINK_ACTIVE_WINDOW_MS 3000UL"));
    assert!(router_cpp.contains("net_telemetry_send_line(json)"));

    assert!(ui_cpp.contains("lv_label_set_text(label_link, \"● USB\")"));
    assert!(ui_cpp.contains("LV_SYMBOL_WIFI \" Wi-Fi\""));
    assert!(ui_cpp.contains("packet_router_emit(\"{\\\"cmd\\\":\\\"run_checks\\\""));
    assert!(ui_cpp.contains("packet_router_emit(\"{\\\"cmd\\\":\\\"open_pr\\\""));
    assert!(ui_cpp.contains("packet_router_emit(\"{\\\"cmd\\\":\\\"wifi_sync\\\"}\")"));

    assert!(ota_cpp.contains("ArduinoOTA.setPassword(ota_password)"));
    assert!(ota_cpp.contains("ota_server->authenticate(OTA_HTTP_USER, ota_password)"));

    let idx = mac_hid_cpp
        .find("void trigger_display_sleep()")
        .expect("missing trigger_display_sleep");
    let body = &mac_hid_cpp[idx..];
    let end = body.find("\n}").unwrap_or(body.len());
    let fn_body = &body[..end];
    assert!(fn_body.contains("MOD_CTRL | MOD_SHIFT"));
    assert!(fn_body.contains("KEY_SYSTEM_POWER"));
    assert!(!fn_body.contains("0x0030"));
    assert!(!fn_body.contains("CONSUMER_CONTROL_DISPLAY_SLEEP"));
    assert!(mac_hid_cpp.contains("(0x66 + 136)"));
}

pub fn run_suite() -> usize {
    test_companion_discovery();
    test_udp_transport_loopback();
    test_link_arbitration();
    test_firmware_source_invariants();
    4
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn net_telemetry_suite() {
        assert_eq!(run_suite(), 4);
    }
}
