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

//! Talking to `adb`: the attached-device list, spotting a device that is
//! already attached (and its redundant transports), connecting, and
//! pairing with a 6-digit code.

use crate::discovery::select_target_device;
use crate::profiles::{
    enrich_device_with_profile, extract_serial, serial_of, ADB_PAIRING_SERVICE, SERVICE_TLS_CONNECT,
};
use crate::py::{s, split_ws, splitlines, strip, Dict, Val};
use crate::Tool;

/// `"tcpip_mode"`-style `not set_tcpip`: no `--tcpip`, or `--tcpip 0`.
fn tcpip_set(set_tcpip: Option<&str>) -> bool {
    set_tcpip.map_or(false, |d| d != "0")
}

fn authorization_hint(id: &Val, status: &Val) -> String {
    format!(
        "Device {} is {}; accept the debugging authorization prompt on the screen.",
        id.py_str(),
        status.py_str()
    )
}

/// `find_existing_adb_transport(target_device, attached_devices)`:
/// the attached entry for this device (matched by serial or exact
/// endpoint, never by model), and redundant `ip:port` transports to drop.
pub fn find_existing_adb_transport(
    target: &Dict,
    attached: &[Dict],
) -> (Option<Dict>, Vec<String>) {
    let target_serial = serial_of(target, "instance");
    let target_endpoint = target.get_str_default("endpoint");
    let target_ip = target.get_none("target_ip");
    let target_port = target.get_none("port");
    let target_lan = if target_ip.truthy() && target_port.truthy() {
        format!("{}:{}", target_ip.py_str(), target_port.py_str())
    } else {
        String::new()
    };

    let mut matching: Vec<Dict> = Vec::new();
    for entry in attached {
        let entry_id = entry.get_str_default("id");
        let entry_serial = serial_of(entry, "id");
        if (!target_serial.is_empty() && !entry_serial.is_empty() && target_serial == entry_serial)
            || (target_endpoint.truthy() && entry_id == target_endpoint)
            || (!target_lan.is_empty() && entry_id.eq_str(&target_lan))
        {
            matching.push(entry.clone());
        }
    }
    if matching.is_empty() {
        return (None, Vec::new());
    }
    let is_device = |e: &Dict| e.get_none("status").eq_str("device");
    let healthy_tls = matching
        .iter()
        .find(|e| is_device(e) && e.get_str_default("id").contains_str(SERVICE_TLS_CONNECT));
    let healthy_any = matching.iter().find(|e| is_device(e));
    let primary = healthy_tls.or(healthy_any).unwrap_or(&matching[0]).clone();
    let primary_id = primary.item("id");
    let duplicates = matching
        .iter()
        .filter(|e| {
            let id = e.item("id");
            id != primary_id
                && !id.expect_str("startswith").starts_with("adb-")
                && is_device(&primary)
        })
        .map(|e| e.item("id").py_str())
        .collect();
    (Some(primary), duplicates)
}

impl<'a> Tool<'a> {
    /// `get_adb_attached_devices()`: `adb devices -l`, one dict per line.
    pub fn get_adb_attached_devices(&self) -> Vec<Dict> {
        let (code, stdout, _) = self.sys.run(&["adb", "devices", "-l"], Some(3.0));
        if code != 0 {
            return Vec::new();
        }
        let mut devices = Vec::new();
        for line in splitlines(&stdout) {
            let line = strip(line);
            if line.is_empty() || line.starts_with("List of devices") {
                continue;
            }
            let parts = split_ws(line);
            if parts.len() >= 2 {
                let mut info = Dict::new();
                info.set("id", s(parts[0]));
                info.set("status", s(parts[1]));
                for prop in &parts[2..] {
                    if let Some((k, v)) = prop.split_once(':') {
                        info.set(k, s(v));
                    }
                }
                let serial = extract_serial(parts[0]);
                if !serial.is_empty() {
                    info.set("serial", s(serial));
                }
                devices.push(info);
            }
        }
        devices
    }

    /// `connect_device(target_device, set_tcpip, attached_devices)`.
    pub fn connect_device(
        &self,
        target: &Dict,
        set_tcpip: Option<&str>,
        attached: Option<&[Dict]>,
    ) -> Dict {
        let tcpip = tcpip_set(set_tcpip);
        let device_label = || {
            target
                .get_none("given_name")
                .or_else(|| target.get_str_default("name"))
        };
        if let (Some(attached), false) = (attached, tcpip) {
            let (existing, duplicates) = find_existing_adb_transport(target, attached);
            for dup in &duplicates {
                self.sys.run(&["adb", "disconnect", dup], Some(3.0));
            }
            if let Some(existing) = existing {
                let attached_id = existing.item("id");
                let status = existing.get_or("status", s("unknown"));
                if status.eq_str("device") {
                    let connection_type = if attached_id.contains_str(SERVICE_TLS_CONNECT) {
                        s("mdns_tls")
                    } else {
                        target.get_or("connection_type", s("lan_ip"))
                    };
                    return Dict::from_pairs(vec![
                        ("success", Val::Bool(true)),
                        ("endpoint", attached_id.clone()),
                        ("adb_serial", attached_id.clone()),
                        ("adb_status", s("device")),
                        ("device", device_label()),
                        ("profile", target.get_str_default("profile_key")),
                        ("serial", target.get_str_default("serial")),
                        ("connection_type", connection_type),
                        ("port", target.get_or("port", crate::py::int(0))),
                        (
                            "deduplicated_endpoints",
                            Val::List(duplicates.iter().map(|d| s(d.clone())).collect()),
                        ),
                        (
                            "stdout",
                            s(format!("already connected to {}", attached_id.py_str())),
                        ),
                        ("stderr", s("")),
                    ]);
                }
                if status.eq_str("unauthorized") || status.eq_str("offline") {
                    return Dict::from_pairs(vec![
                        ("success", Val::Bool(false)),
                        ("endpoint", attached_id.clone()),
                        ("adb_serial", attached_id.clone()),
                        ("adb_status", status.clone()),
                        ("device", device_label()),
                        ("profile", target.get_str_default("profile_key")),
                        ("serial", target.get_str_default("serial")),
                        (
                            "connection_type",
                            target.get_or("connection_type", s("lan_ip")),
                        ),
                        ("port", target.get_or("port", crate::py::int(0))),
                        ("stdout", s("")),
                        ("stderr", s(authorization_hint(&attached_id, &status))),
                    ]);
                }
            }
        }

        // With live attached-device tracking, dial a TLS phone by its mDNS
        // service name so adb does not open a second transport beside its
        // own mDNS auto-connect.
        let connect_target = if attached.is_some()
            && !tcpip
            && !target.get_none("connection_type").eq_str("manual_override")
            && target.get_none("mdns_endpoint").truthy()
        {
            target.item("mdns_endpoint")
        } else {
            target.item("endpoint")
        };
        let ct = connect_target.expect_str("__fspath__").to_string();

        let (mut code, mut stdout, mut stderr) = self.sys.run(&["adb", "connect", &ct], Some(5.0));
        let combined = format!("{}\n{}", stdout, stderr).to_lowercase();
        if combined.contains("no route to host") {
            // A stale macOS adb server without Local Network permission.
            self.sys.run(&["adb", "kill-server"], Some(3.0));
            (code, stdout, stderr) = self.sys.run(&["adb", "connect", &ct], Some(5.0));
        }

        let lower = stdout.to_lowercase();
        let mut success =
            code == 0 && (lower.contains("connected to") || lower.contains("already connected"));
        if success && attached.is_some() {
            let refreshed = self.get_adb_attached_devices();
            let (post, _) = find_existing_adb_transport(target, &refreshed);
            if let Some(post) = post {
                if !post.get_none("status").eq_str("device") {
                    let st = post.get_or("status", s("unauthorized"));
                    success = false;
                    stderr = authorization_hint(&post.item("id"), &st);
                }
            }
        }

        let device = target.item("given_name").or_else(|| target.item("name"));
        let connection_type = if ct.contains(SERVICE_TLS_CONNECT) {
            s("mdns_tls")
        } else {
            target.item("connection_type")
        };
        let mut result = Dict::from_pairs(vec![
            ("success", Val::Bool(success)),
            ("endpoint", connect_target.clone()),
            ("adb_serial", connect_target.clone()),
            ("device", device),
            ("serial", target.item("serial")),
            ("connection_type", connection_type),
            ("port", target.item("port")),
            ("stdout", s(strip(&stdout))),
            ("stderr", s(strip(&stderr))),
        ]);
        if target.get_none("profile_key").truthy() {
            result.set("profile", target.item("profile_key"));
        }

        if let (true, Some(port)) = (success && tcpip, set_tcpip) {
            let (tcode, tout, terr) = self.sys.run(&["adb", "-s", &ct, "tcpip", port], Some(5.0));
            result.set(
                "tcpip_mode",
                Val::Dict(Dict::from_pairs(vec![
                    ("requested_port", Val::Int(port.to_string())),
                    ("success", Val::Bool(tcode == 0)),
                    ("stdout", s(strip(&tout))),
                    ("stderr", s(strip(&terr))),
                ])),
            );
        }
        result
    }

    /// `pair_device(pairing_code, device_filter, scan_timeout)`.
    pub fn pair_device(
        &self,
        pairing_code: &str,
        device_filter: Option<&str>,
        scan_timeout: f64,
    ) -> Dict {
        let fail =
            |msg: String| Dict::from_pairs(vec![("success", Val::Bool(false)), ("error", s(msg))]);
        let clean = strip(pairing_code);
        if !(clean.chars().count() == 6 && clean.chars().all(|c| c.is_ascii_digit())) {
            return fail("Pairing code must be a 6-digit number.".into());
        }
        let instances = self.browse_mdns_instances(scan_timeout, &[ADB_PAIRING_SERVICE]);
        if instances.is_empty() {
            return fail(
                "No device advertising Wireless Debugging pairing (_adb-tls-pairing._tcp). \
                 Open 'Pair device with pairing code' on the phone and try again."
                    .into(),
            );
        }
        let profiles = self.load_device_profiles(None);
        let mut candidates = Vec::new();
        for inst in &instances {
            if let Some(mut dev) = self.resolve_mdns_instance(inst, 1.2, Some(ADB_PAIRING_SERVICE))
            {
                enrich_device_with_profile(&mut dev, &profiles);
                candidates.push(dev);
            }
        }
        if candidates.is_empty() {
            return fail("Failed to resolve pairing service endpoint over mDNS.".into());
        }
        let has_filter = device_filter.map_or(false, |f| !f.is_empty());
        let target = if has_filter || candidates.len() == 1 {
            match select_target_device(self, &candidates, device_filter, Some(&profiles)) {
                Ok(t) => t,
                Err(e) => return fail(e.message),
            }
        } else {
            None
        };
        let Some(mut target) = target else {
            return fail(format!(
                "Multiple devices advertising pairing ({}). Specify --device to choose one.",
                candidates.len()
            ));
        };

        // Pairing always goes over the LAN, never Tailscale.
        self.resolve_device_endpoint(&mut target, false, 1, None);
        let endpoint = target.item("endpoint");
        let ep = endpoint.expect_str("__fspath__").to_string();
        let (code, stdout, stderr) = self.sys.run(&["adb", "pair", &ep, clean], Some(10.0));
        let paired = code == 0 && stdout.to_lowercase().contains("successfully paired");
        let device = target
            .get_none("given_name")
            .or_else(|| target.get_none("name"))
            .or_else(|| target.item("instance"));
        Dict::from_pairs(vec![
            ("success", Val::Bool(paired)),
            ("endpoint", endpoint.clone()),
            ("device", device),
            ("serial", target.get_str_default("serial")),
            ("port", target.item("port")),
            ("pairing_code", s("***")),
            ("stdout", s(strip(&stdout))),
            ("stderr", s(strip(&stderr))),
        ])
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testutil::*;

    fn fold_target() -> Dict {
        dev_with_port(
            &[
                ("endpoint", "100.74.154.64:41067"),
                ("given_name", "James Pixel 11 Pro Fold"),
                ("name", "Pixel 11 Pro Fold"),
                ("serial", "66211FDDJ000XR"),
                ("connection_type", "tailscale"),
            ],
            41067,
        )
    }

    #[test]
    fn get_adb_attached_devices() {
        let sys = MockSystem::new().run_output(&["adb", "devices", "-l"], 0, ADB_DEVICES);
        let (t, _, _) = tool(&sys);
        let devices = t.get_adb_attached_devices();
        assert_eq!(devices.len(), 2);
        assert_eq!(devices[0].get("id"), Some(&s("100.74.154.64:41067")));
        assert_eq!(devices[0].get("status"), Some(&s("device")));
        assert_eq!(devices[0].get("model"), Some(&s("Pixel_11_Pro_Fold")));
        assert_eq!(devices[0].get("transport_id"), Some(&s("1116")));
        assert_eq!(devices[1].get("id"), Some(&s("emulator-5554")));
        assert_eq!(devices[1].get("serial"), None);
        assert_eq!(sys.timeouts(), vec![Some(3.0)]);
    }

    #[test]
    fn adb_failure_means_no_devices() {
        let sys = MockSystem::new().run_output(&["adb", "devices", "-l"], 127, "");
        let (t, _, _) = tool(&sys);
        assert!(t.get_adb_attached_devices().is_empty());
    }

    #[test]
    fn connect_device_success() {
        let sys = MockSystem::new().run_default(0, "connected to 100.74.154.64:41067", "");
        let (t, _, _) = tool(&sys);
        let r = t.connect_device(&fold_target(), None, None);
        assert_eq!(r.get("success"), Some(&Val::Bool(true)));
        assert_eq!(r.get("endpoint"), Some(&s("100.74.154.64:41067")));
        assert_eq!(r.get("connection_type"), Some(&s("tailscale")));
        assert_eq!(r.get("profile"), None);
        assert_eq!(
            sys.calls(),
            vec![vec!["adb", "connect", "100.74.154.64:41067"]]
        );
    }

    #[test]
    fn connect_device_with_tcpip() {
        let sys = MockSystem::new()
            .run_output(
                &["adb", "connect", "100.74.154.64:41067"],
                0,
                "connected to 100.74.154.64:41067",
            )
            .run_output(
                &["adb", "-s", "100.74.154.64:41067", "tcpip", "5555"],
                0,
                "restarting in TCP mode port: 5555",
            );
        let (t, _, _) = tool(&sys);
        let r = t.connect_device(&fold_target(), Some("5555"), None);
        assert_eq!(r.get("success"), Some(&Val::Bool(true)));
        let mode = r.get("tcpip_mode").and_then(Val::as_dict).unwrap();
        assert_eq!(mode.get("success"), Some(&Val::Bool(true)));
        assert_eq!(mode.get("requested_port"), Some(&int(5555)));
        assert_eq!(
            mode.get("stdout"),
            Some(&s("restarting in TCP mode port: 5555"))
        );
    }

    #[test]
    fn connect_device_recovers_from_no_route_to_host() {
        let target = dev_with_port(
            &[
                ("endpoint", "192.168.86.31:5555"),
                ("given_name", "Living Room Sony TV"),
                ("name", "Living Room Sony TV"),
                ("serial", "24adbf003005591"),
                ("connection_type", "lan_ip"),
            ],
            5555,
        );
        let sys = MockSystem::new().run_seq(
            &["adb", "connect", "192.168.86.31:5555"],
            vec![
                (
                    0,
                    "failed to connect to '192.168.86.31:5555': No route to host",
                    "",
                ),
                (0, "connected to 192.168.86.31:5555", ""),
            ],
        );
        let (t, _, _) = tool(&sys);
        let r = t.connect_device(&target, None, None);
        assert_eq!(r.get("success"), Some(&Val::Bool(true)));
        assert_eq!(
            sys.calls(),
            vec![
                vec!["adb", "connect", "192.168.86.31:5555"],
                vec!["adb", "kill-server"],
                vec!["adb", "connect", "192.168.86.31:5555"],
            ]
        );
    }

    #[test]
    fn connect_device_avoids_duplicate_and_cleans_up_ip_transport() {
        let sys = MockSystem::new().run_output(&["adb", "devices", "-l"], 0, ADB_MULTI_DEVICES);
        let (t, _, _) = tool(&sys);
        let attached = t.get_adb_attached_devices();
        let target = dev_with_port(
            &[
                ("instance", "adb-98271FFBA007YW-OflOTi"),
                ("endpoint", "192.168.86.61:41295"),
                ("target_ip", "192.168.86.61"),
                ("given_name", "Pixel 4 XL"),
                ("name", "Pixel 4 XL"),
                ("profile_key", "pixel4"),
                ("codename", "coral"),
                ("serial", "98271FFBA007YW"),
                ("connection_type", "lan_ip"),
            ],
            41295,
        );
        let sys = MockSystem::new().run_default(0, "disconnected 192.168.86.61:41295", "");
        let (t, _, _) = tool(&sys);
        let r = t.connect_device(&target, None, Some(&attached));
        assert_eq!(r.get("success"), Some(&Val::Bool(true)));
        assert_eq!(
            r.get("endpoint"),
            Some(&s("adb-98271FFBA007YW-OflOTi._adb-tls-connect._tcp"))
        );
        assert_eq!(r.get("connection_type"), Some(&s("mdns_tls")));
        assert_eq!(
            r.get("deduplicated_endpoints"),
            Some(&Val::List(vec![s("192.168.86.61:41295")]))
        );
        assert_eq!(
            sys.calls(),
            vec![vec!["adb", "disconnect", "192.168.86.61:41295"]]
        );
        assert_eq!(sys.timeouts(), vec![Some(3.0)]);
    }

    #[test]
    fn find_existing_adb_transport_does_not_confuse_different_phone_of_same_model() {
        let attached = vec![dev(&[
            ("id", "192.168.86.99:40000"),
            ("status", "device"),
            ("product", "coral"),
            ("model", "Pixel_4_XL"),
            ("device", "coral"),
        ])];
        let target = dev_with_port(
            &[
                ("instance", "adb-98271FFBA007YW-OflOTi"),
                ("endpoint", "192.168.86.61:41295"),
                ("target_ip", "192.168.86.61"),
                ("serial", "98271FFBA007YW"),
                ("codename", "coral"),
            ],
            41295,
        );
        assert_eq!(
            find_existing_adb_transport(&target, &attached),
            (None, vec![])
        );
    }

    #[test]
    fn connect_device_reports_failure_when_device_is_unauthorized() {
        let sys = MockSystem::new().run_output(&["adb", "devices", "-l"], 0, ADB_MULTI_DEVICES);
        let (t, _, _) = tool(&sys);
        let attached = t.get_adb_attached_devices();
        let target = dev_with_port(
            &[
                ("instance", "adb-24adbf003005591"),
                ("endpoint", "192.168.86.31:5555"),
                ("target_ip", "192.168.86.31"),
                ("given_name", "Living Room Sony TV"),
                ("name", "Living Room Sony TV"),
                ("profile_key", "tv"),
                ("serial", "24adbf003005591"),
                ("connection_type", "lan_ip"),
            ],
            5555,
        );
        let sys = MockSystem::new();
        let (t, _, _) = tool(&sys);
        let r = t.connect_device(&target, None, Some(&attached));
        assert_eq!(r.get("success"), Some(&Val::Bool(false)));
        assert_eq!(r.get("adb_status"), Some(&s("unauthorized")));
        assert_eq!(
            r.get("stderr"),
            Some(&s("Device 192.168.86.31:5555 is unauthorized; accept the debugging authorization prompt on the screen."))
        );
        assert!(sys.calls().is_empty());
    }

    #[test]
    fn connect_device_uses_mdns_endpoint_for_unattached_tls_phone() {
        let target = dev_with_port(
            &[
                ("instance", "adb-98271FFBA007YW-OflOTi"),
                ("endpoint", "192.168.86.61:41295"),
                (
                    "mdns_endpoint",
                    "adb-98271FFBA007YW-OflOTi._adb-tls-connect._tcp",
                ),
                ("target_ip", "192.168.86.61"),
                ("given_name", "Pixel 4 XL"),
                ("name", "Pixel 4 XL"),
                ("profile_key", "pixel4"),
                ("serial", "98271FFBA007YW"),
                ("connection_type", "lan_ip"),
            ],
            41295,
        );
        let sys = MockSystem::new()
            .run_output(
                &["adb", "connect", "adb-98271FFBA007YW-OflOTi._adb-tls-connect._tcp"],
                0,
                "connected to adb-98271FFBA007YW-OflOTi._adb-tls-connect._tcp",
            )
            .run_output(
                &["adb", "devices", "-l"],
                0,
                "List of devices attached\nadb-98271FFBA007YW-OflOTi._adb-tls-connect._tcp device\n",
            );
        let (t, _, _) = tool(&sys);
        let r = t.connect_device(&target, None, Some(&[]));
        assert_eq!(r.get("success"), Some(&Val::Bool(true)));
        assert_eq!(
            r.get("endpoint"),
            Some(&s("adb-98271FFBA007YW-OflOTi._adb-tls-connect._tcp"))
        );
        assert_eq!(r.get("connection_type"), Some(&s("mdns_tls")));
        assert_eq!(r.get("profile"), Some(&s("pixel4")));
        assert_eq!(
            sys.calls()[0],
            vec![
                "adb",
                "connect",
                "adb-98271FFBA007YW-OflOTi._adb-tls-connect._tcp"
            ]
        );
        assert_eq!(sys.timeouts()[0], Some(5.0));
    }

    #[test]
    fn connect_success_downgraded_when_device_turns_out_unauthorized() {
        let target = dev_with_port(
            &[
                ("instance", "adb-X1-a"),
                ("endpoint", "10.0.0.5:4000"),
                ("given_name", "Phone"),
                ("name", ""),
                ("serial", "X1"),
                ("connection_type", "lan_ip"),
            ],
            4000,
        );
        let sys = MockSystem::new()
            .run_output(
                &["adb", "connect", "10.0.0.5:4000"],
                0,
                "connected to 10.0.0.5:4000",
            )
            .run_output(&["adb", "devices", "-l"], 0, "10.0.0.5:4000 unauthorized\n");
        let (t, _, _) = tool(&sys);
        let r = t.connect_device(&target, None, Some(&[]));
        assert_eq!(r.get("success"), Some(&Val::Bool(false)));
        assert_eq!(
            r.get("stderr"),
            Some(&s("Device 10.0.0.5:4000 is unauthorized; accept the debugging authorization prompt on the screen."))
        );
    }

    #[test]
    fn pair_device_validates_code_and_uses_lan() {
        let sys = MockSystem::new();
        let (t, _, _) = tool(&sys);
        let bad = t.pair_device("12ab", None, 2.0);
        assert_eq!(bad.get("success"), Some(&Val::Bool(false)));
        assert_eq!(
            bad.get("error"),
            Some(&s("Pairing code must be a 6-digit number."))
        );

        let sys = MockSystem::new()
            .spawn_output(
                &["dns-sd", "-B", "_adb-tls-pairing._tcp", "local."],
                "12:00:00.000  Add  2  13 local.  _adb-tls-pairing._tcp.  adb-98271FFBA007YW-pair\n",
            )
            .spawn_output(
                &["dns-sd", "-L", "adb-98271FFBA007YW-pair", "_adb-tls-pairing._tcp", "local."],
                "x can be reached at Android-2.local.:37379 (interface 13)\n name=Pixel\\ 4\\ XL\n",
            )
            .spawn_output(&["dns-sd", "-G", "v4", "Android-2.local."], &addr_line("Android-2.local.", "192.168.86.61"))
            .run_output(
                &["adb", "pair", "192.168.86.61:37379", "052698"],
                0,
                "Successfully paired to 192.168.86.61:37379 [guid=adb-98271FFBA007YW-OflOTi]",
            );
        let (t, _, _) = tool(&sys);
        let r = t.pair_device(" 052698 ", None, 2.0);
        assert_eq!(r.get("success"), Some(&Val::Bool(true)));
        assert_eq!(r.get("endpoint"), Some(&s("192.168.86.61:37379")));
        assert_eq!(r.get("pairing_code"), Some(&s("***")));
        assert_eq!(r.get("device"), Some(&s("Pixel 4 XL")));
        assert_eq!(r.get("serial"), Some(&s("98271FFBA007YW")));
        assert_eq!(
            sys.calls(),
            vec![vec!["adb", "pair", "192.168.86.61:37379", "052698"]]
        );
        assert_eq!(sys.timeouts(), vec![Some(10.0)]);
    }

    #[test]
    fn pair_device_reports_missing_and_ambiguous_services() {
        let sys = MockSystem::new();
        let (t, _, _) = tool(&sys);
        let r = t.pair_device("123456", None, 2.0);
        assert!(r
            .get("error")
            .unwrap()
            .py_str()
            .starts_with("No device advertising"));

        let sys = MockSystem::new()
            .spawn_output(
                &["dns-sd", "-B", "_adb-tls-pairing._tcp", "local."],
                "Add _adb-tls-pairing._tcp. adb-A-1\nAdd _adb-tls-pairing._tcp. adb-B-1\n",
            )
            .spawn_output(
                &["dns-sd", "-L", "adb-A-1", "_adb-tls-pairing._tcp", "local."],
                "can be reached at a.local.:1\n",
            )
            .spawn_output(
                &["dns-sd", "-L", "adb-B-1", "_adb-tls-pairing._tcp", "local."],
                "can be reached at b.local.:2\n",
            );
        let (t, _, _) = tool(&sys);
        let r = t.pair_device("123456", None, 2.0);
        assert_eq!(
            r.get("error"),
            Some(&s(
                "Multiple devices advertising pairing (2). Specify --device to choose one."
            ))
        );
    }
}
