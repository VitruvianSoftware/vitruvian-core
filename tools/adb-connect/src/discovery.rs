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

//! From mDNS announcements to one connectable device: Tailscale peers,
//! de-duplication by hardware serial, deterministic ordering, target
//! selection (aliases, ambiguity refusal, phone-first default) and the
//! endpoint to dial.

use crate::profiles::{
    enrich_device_with_profile, serial_of, ADB_MDNS_SERVICES, SERVICE_LEGACY, SERVICE_TLS_CONNECT,
};
use crate::py::{join_strs, raise, rstrip_chars, s, strip, Dict, Val};
use crate::pyjson;
use crate::Tool;

/// `AmbiguousDeviceError`: several devices fit and none was chosen.
#[derive(Clone, Debug, PartialEq)]
pub struct AmbiguousDeviceError {
    pub message: String,
    pub candidates: Vec<Dict>,
}

impl std::fmt::Display for AmbiguousDeviceError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.message)
    }
}

fn no_attribute(v: &Val, attr: &str) -> ! {
    raise(
        "AttributeError",
        format!("'{}' object has no attribute '{}'", v.type_name(), attr),
    )
}

/// `_device_sort_key(dev)`: TLS phones first, then the default profile,
/// then by role, then by serial.
pub fn device_sort_key(dev: &Dict) -> (i32, i32, i32, String) {
    let is_tls = i32::from(
        !dev.get_or("service_type", s(SERVICE_TLS_CONNECT))
            .eq_str(SERVICE_TLS_CONNECT),
    );
    let is_default = i32::from(!dev.get_or("is_default", Val::Bool(false)).truthy());
    let role_rank = match dev.get_str_default("role") {
        Val::Str(r) => match r.as_str() {
            "primary" => 0,
            "secondary" => 1,
            "phone" => 2,
            "watch" => 3,
            "tv" => 4,
            _ => 2,
        },
        v @ (Val::List(_) | Val::Dict(_)) => {
            raise("TypeError", format!("unhashable type: '{}'", v.type_name()))
        }
        _ => 2,
    };
    let serial = dev.get_str_default("serial").py_str();
    (is_tls, is_default, role_rank, serial)
}

/// `list.sort(key=_device_sort_key)`: keys computed once, stable.
pub fn sort_devices(devices: &mut Vec<Dict>) {
    let keys: Vec<_> = devices.iter().map(device_sort_key).collect();
    let mut order: Vec<usize> = (0..devices.len()).collect();
    order.sort_by(|&a, &b| keys[a].cmp(&keys[b]));
    let sorted: Vec<Dict> = order.iter().map(|&i| devices[i].clone()).collect();
    *devices = sorted;
}

/// `deduplicate_devices_by_serial(devices)`: one entry per serial, the
/// latest announcement winning, in first-seen order.
pub fn deduplicate_devices_by_serial(devices: &[Dict]) -> Vec<Dict> {
    let mut slots: Vec<(String, Dict)> = Vec::new();
    for (idx, dev) in devices.iter().enumerate() {
        let serial = serial_of(dev, "instance");
        let key = if serial.is_empty() {
            format!("idx:{}:{}", idx, dev.get_str_default("instance").py_str())
        } else {
            format!("serial:{}", serial)
        };
        if let Some(slot) = slots.iter_mut().find(|(k, _)| *k == key) {
            slot.1 = dev.clone();
        } else {
            slots.push((key, dev.clone()));
        }
    }
    slots.into_iter().map(|(_, d)| d).collect()
}

fn label(d: &Dict) -> String {
    d.get_none("given_name")
        .or_else(|| d.get_none("name"))
        .or_else(|| d.get_none("instance"))
        .py_str()
}

/// `select_target_device(resolved_devices, device_filter, profiles)`.
pub fn select_target_device(
    tool: &Tool,
    resolved: &[Dict],
    device_filter: Option<&str>,
    profiles: Option<&[Dict]>,
) -> Result<Option<Dict>, AmbiguousDeviceError> {
    if resolved.is_empty() {
        return Ok(None);
    }
    let loaded;
    let catalog: &[Dict] = match profiles {
        Some(p) => p,
        None => {
            loaded = tool.load_device_profiles(None);
            &loaded
        }
    };
    let deduped = deduplicate_devices_by_serial(resolved);
    let enriched: Vec<Dict> = deduped
        .into_iter()
        .map(|mut d| {
            enrich_device_with_profile(&mut d, catalog);
            d
        })
        .collect();

    if let Some(raw_filter) = device_filter.filter(|f| !f.is_empty()) {
        let filt = strip(raw_filter).to_lowercase();
        let exact: Vec<Dict> = enriched
            .iter()
            .filter(|dev| {
                filt == dev.get_str_default("profile_key").lower()
                    || dev
                        .get_or("aliases", Val::List(vec![]))
                        .iter_items()
                        .iter()
                        .map(Val::lower)
                        .collect::<Vec<_>>()
                        .contains(&filt)
                    || filt == dev.get_str_default("codename").lower()
                    || (dev.get_none("serial").truthy() && filt == dev.item("serial").lower())
                    || filt == dev.get_str_default("instance").lower()
            })
            .cloned()
            .collect();
        if exact.len() == 1 {
            return Ok(exact.into_iter().next());
        }
        if exact.len() > 1 {
            let labels: Vec<String> = exact
                .iter()
                .map(|d| {
                    format!(
                        "{} (--device {})",
                        label(d),
                        d.get_none("serial")
                            .or_else(|| d.get_none("instance"))
                            .py_str()
                    )
                })
                .collect();
            return Err(AmbiguousDeviceError {
                message: format!(
                    "Filter '{}' matched {} devices: {}. Specify an unambiguous serial.",
                    raw_filter,
                    exact.len(),
                    labels.join(", ")
                ),
                candidates: exact,
            });
        }

        let mut sub: Vec<Dict> = Vec::new();
        for dev in &enriched {
            let aliases = join_strs(" ", &dev.get_or("aliases", Val::List(vec![])).iter_items());
            let fields = [
                dev.get_str_default("instance"),
                dev.get_str_default("given_name"),
                dev.get_str_default("serial"),
                dev.get_str_default("name"),
                dev.get_str_default("hostname"),
                dev.get_str_default("profile_key"),
                s(aliases),
            ];
            if fields
                .iter()
                .filter(|f| f.truthy())
                .any(|f| f.lower().contains(&filt))
            {
                sub.push(dev.clone());
            }
        }
        if sub.is_empty() {
            return Ok(None);
        }
        if sub.len() > 1 {
            let labels: Vec<String> = sub
                .iter()
                .map(|d| {
                    format!(
                        "{} (--device {})",
                        label(d),
                        d.get_none("profile_key")
                            .or_else(|| d.get_none("serial"))
                            .py_str()
                    )
                })
                .collect();
            return Err(AmbiguousDeviceError {
                message: format!(
                    "Filter '{}' matched {} devices: {}. Specify an unambiguous alias or serial.",
                    raw_filter,
                    sub.len(),
                    labels.join(", ")
                ),
                candidates: sub,
            });
        }
        return Ok(sub.into_iter().next());
    }

    // No filter: only Wireless Debugging phones, never a watch or a TV.
    let mut phones: Vec<Dict> = enriched
        .into_iter()
        .filter(|d| {
            !d.get_or("service_type", s(SERVICE_TLS_CONNECT))
                .eq_str(SERVICE_LEGACY)
                && !matches!(d.get_none("role").as_str(), Some("tv") | Some("watch"))
        })
        .collect();
    if phones.is_empty() {
        return Ok(None);
    }
    let defaults: Vec<&Dict> = phones
        .iter()
        .filter(|d| d.get_or("is_default", Val::Bool(false)).truthy())
        .collect();
    if defaults.len() == 1 {
        return Ok(Some(defaults[0].clone()));
    }
    if phones.len() == 1 {
        return Ok(phones.pop());
    }
    sort_devices(&mut phones);
    let labels: Vec<String> = phones
        .iter()
        .map(|d| {
            format!(
                "{} [--device {}]",
                label(d),
                d.get_none("profile_key")
                    .or_else(|| d.get_none("serial"))
                    .py_str()
            )
        })
        .collect();
    Err(AmbiguousDeviceError {
        message: format!(
            "Multiple Android phones discovered ({}); pass --device <alias> or --all.",
            labels.join(", ")
        ),
        candidates: phones,
    })
}

impl<'a> Tool<'a> {
    /// `get_tailscale_android_peers()`.
    pub fn get_tailscale_android_peers(&self) -> Vec<Dict> {
        let (code, stdout, _) = self.sys.run(&["tailscale", "status", "--json"], Some(2.0));
        if code != 0 || stdout.is_empty() {
            return Vec::new();
        }
        let Ok(data) = pyjson::loads(&stdout) else {
            return Vec::new();
        };
        let Val::Dict(data) = data else {
            no_attribute(&data, "get")
        };
        let peer_dict = data.get_or("Peer", Val::Dict(Dict::new()));
        let Val::Dict(peer_dict) = peer_dict else {
            no_attribute(&peer_dict, "values")
        };
        let mut peers = Vec::new();
        for (_, node) in &peer_dict.0 {
            let Val::Dict(node) = node else {
                no_attribute(node, "get")
            };
            if node.get_str_default("OS").lower() != "android" {
                continue;
            }
            let ips: Vec<Val> = node
                .get_or("TailscaleIPs", Val::List(vec![]))
                .iter_items()
                .into_iter()
                .filter(|ip| !ip.contains_str(":"))
                .collect();
            let dns_name =
                rstrip_chars(node.get_str_default("DNSName").expect_str("rstrip"), ".").to_string();
            peers.push(Dict::from_pairs(vec![
                ("hostname", node.get_str_default("HostName")),
                ("dns_name", s(dns_name)),
                ("tailscale_ip", ips.into_iter().next().unwrap_or(Val::None)),
                ("cur_addr", node.get_str_default("CurAddr")),
                ("online", node.get_or("Online", Val::Bool(false))),
                ("active", node.get_or("Active", Val::Bool(false))),
            ]));
        }
        peers
    }

    /// `resolve_device_endpoint(dev, prefer_tailscale, total_devices_count, ts_peers)`:
    /// fills `target_ip`, `connection_type`, `endpoint` (and `mdns_endpoint`).
    pub fn resolve_device_endpoint(
        &self,
        dev: &mut Dict,
        prefer_tailscale: bool,
        total_devices_count: usize,
        ts_peers: Option<&[Dict]>,
    ) {
        let fetched;
        let peers: &[Dict] = match ts_peers {
            Some(p) => p,
            None => {
                fetched = if prefer_tailscale {
                    self.get_tailscale_android_peers()
                } else {
                    Vec::new()
                };
                &fetched
            }
        };
        let mut target_ip = Val::None;
        let mut connection_type = "mdns_lan";
        let is_legacy = dev.get_none("service_type").eq_str(SERVICE_LEGACY);

        if prefer_tailscale && !peers.is_empty() {
            for peer in peers {
                let peer_name = peer.item("hostname").lower();
                let dev_name = dev.get_str_default("given_name").lower();
                let dev_model = dev.get_str_default("name").lower();
                let name_matches = !peer_name.is_empty()
                    && ((!dev_name.is_empty()
                        && (peer_name.contains(&dev_name) || dev_name.contains(&peer_name)))
                        || (!dev_model.is_empty() && peer_name.contains(&dev_model)));
                let fallback_active = !is_legacy
                    && total_devices_count == 1
                    && peer.get_or("active", Val::Bool(false)).truthy();
                if (name_matches || fallback_active) && peer.get_none("tailscale_ip").truthy() {
                    target_ip = peer.item("tailscale_ip");
                    connection_type = "tailscale";
                    break;
                }
            }
        }

        if !target_ip.truthy() {
            match self.resolve_hostname_ipv4(&dev.item("hostname"), 1.2) {
                Some(lan_ip) => {
                    target_ip = s(lan_ip);
                    connection_type = "lan_ip";
                }
                None => {
                    target_ip = dev.item("hostname");
                    connection_type = "hostname";
                }
            }
        }

        let endpoint = format!("{}:{}", target_ip.py_str(), dev.item("port").py_str());
        dev.set("target_ip", target_ip);
        dev.set("connection_type", s(connection_type));
        dev.set("endpoint", s(endpoint));
        if dev.get_none("instance").truthy()
            && dev
                .get_or("service_type", s(SERVICE_TLS_CONNECT))
                .eq_str(SERVICE_TLS_CONNECT)
        {
            let mdns = format!("{}._adb-tls-connect._tcp", dev.item("instance").py_str());
            dev.set("mdns_endpoint", s(mdns));
        }
    }

    /// `discover_all_devices(prefer_tailscale, scan_timeout)`.
    pub fn discover_all_devices(&self, prefer_tailscale: bool, scan_timeout: f64) -> Vec<Dict> {
        let instances = self.browse_mdns_instances(scan_timeout, &ADB_MDNS_SERVICES);
        if instances.is_empty() {
            return Vec::new();
        }
        let profiles = self.load_device_profiles(None);
        let raw: Vec<Dict> = instances
            .iter()
            .filter_map(|inst| self.resolve_mdns_instance(inst, 1.2, None))
            .collect();
        let mut devices = deduplicate_devices_by_serial(&raw);
        for dev in devices.iter_mut() {
            enrich_device_with_profile(dev, &profiles);
        }
        let ts_peers = if prefer_tailscale {
            self.get_tailscale_android_peers()
        } else {
            Vec::new()
        };
        let total = devices.len();
        for dev in devices.iter_mut() {
            self.resolve_device_endpoint(dev, prefer_tailscale, total, Some(&ts_peers));
        }
        sort_devices(&mut devices);
        devices
    }

    /// `find_target_device(device_filter, prefer_tailscale, scan_timeout)`.
    pub fn find_target_device(
        &self,
        device_filter: Option<&str>,
        prefer_tailscale: bool,
        scan_timeout: f64,
    ) -> Result<Option<Dict>, AmbiguousDeviceError> {
        let instances = self.browse_mdns_instances(scan_timeout, &ADB_MDNS_SERVICES);
        if instances.is_empty() {
            return Ok(None);
        }
        let resolved: Vec<Dict> = instances
            .iter()
            .filter_map(|inst| self.resolve_mdns_instance(inst, 1.2, None))
            .collect();
        if resolved.is_empty() {
            return Ok(None);
        }
        let Some(mut selected) = select_target_device(self, &resolved, device_filter, None)? else {
            return Ok(None);
        };
        self.resolve_device_endpoint(&mut selected, prefer_tailscale, resolved.len(), None);
        Ok(Some(selected))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::py::int;
    use crate::testutil::*;

    fn fold() -> Dict {
        dev_with_port(
            &[
                ("instance", "adb-66211FDDJ000XR-DYsKrZ"),
                ("hostname", "Android_43W5CGQ4.local."),
                ("serial", "66211FDDJ000XR"),
                ("name", "Pixel 11 Pro Fold"),
                ("given_name", "James Pixel 11 Pro Fold"),
                ("service_type", "_adb-tls-connect._tcp"),
            ],
            46223,
        )
    }

    fn pixel4() -> Dict {
        dev_with_port(
            &[
                ("instance", "adb-98271FFBA007YW-OflOTi"),
                ("hostname", "Android-2.local."),
                ("serial", "98271FFBA007YW"),
                ("name", "Pixel 4 XL"),
                ("given_name", "Pixel 4 XL"),
                ("service_type", "_adb-tls-connect._tcp"),
            ],
            41295,
        )
    }

    fn tv() -> Dict {
        dev_with_port(
            &[
                ("instance", "adb-24adbf003005591"),
                ("hostname", "Android.local."),
                ("serial", "24adbf003005591"),
                ("name", "Living Room Sony TV"),
                ("given_name", "Living Room Sony TV"),
                ("service_type", "_adb._tcp"),
            ],
            5555,
        )
    }

    fn select(devs: &[Dict], filter: Option<&str>) -> Result<Option<Dict>, AmbiguousDeviceError> {
        let sys = MockSystem::new();
        let (t, _, _) = tool(&sys);
        let profiles = t.load_device_profiles(None);
        select_target_device(&t, devs, filter, Some(&profiles))
    }

    #[test]
    fn default_selection_prefers_primary_phone_over_tv_and_secondary() {
        let devices = vec![pixel4(), fold(), tv()];
        let sel = select(&devices, None).unwrap().unwrap();
        assert_eq!(sel.get("profile_key"), Some(&s("fold")));
        assert_eq!(sel.get("serial"), Some(&s("66211FDDJ000XR")));
        for alias in ["pixel4", "coral", "secondary", "Pixel 4"] {
            let p4 = select(&devices, Some(alias)).unwrap().unwrap();
            assert_eq!(p4.get("profile_key"), Some(&s("pixel4")), "alias {}", alias);
            assert_eq!(p4.get("serial"), Some(&s("98271FFBA007YW")));
        }
        let err = select(&devices, Some("pixel")).unwrap_err();
        assert_eq!(
            err.message,
            "Filter 'pixel' matched 2 devices: Pixel 4 XL (--device pixel4), James Pixel 11 Pro Fold (--device fold). Specify an unambiguous alias or serial."
        );
    }

    #[test]
    fn pixel_watch_4_profile_matching_and_no_default_autoselect() {
        let watch = dev_with_port(
            &[
                ("instance", "adb-58301WRBNL30SD-js57rs"),
                ("hostname", "Android_A2G1X1TA.local."),
                ("serial", "58301WRBNL30SD"),
                ("name", "Pixel Watch 4"),
                ("given_name", "Pixel Watch 4"),
                ("api", "37.1"),
                ("service_type", "_adb-tls-connect._tcp"),
            ],
            39643,
        );
        assert_eq!(select(&[watch.clone()], None).unwrap(), None);
        for alias in [
            "watch",
            "pixel-watch",
            "pixelwatch4",
            "pw4",
            "kenari",
            "kenari_lte",
            "wear",
            "Pixel Watch 4",
        ] {
            let sel = select(&[watch.clone()], Some(alias)).unwrap().unwrap();
            assert_eq!(sel.get("profile_key"), Some(&s("watch")), "alias {}", alias);
            assert_eq!(sel.get("role"), Some(&s("watch")));
            assert_eq!(sel.get("codename"), Some(&s("kenari_lte")));
            assert_eq!(sel.get("serial"), Some(&s("58301WRBNL30SD")));
        }
    }

    #[test]
    fn default_selection_never_picks_tv_when_only_tv_on_network() {
        assert_eq!(select(&[tv()], None).unwrap(), None);
        let sel = select(&[tv()], Some("tv")).unwrap().unwrap();
        assert_eq!(sel.get("profile_key"), Some(&s("tv")));
    }

    #[test]
    fn multiple_unknown_phones_are_refused_in_sorted_order() {
        let a = dev_with_port(
            &[
                ("instance", "adb-ZZZ-1"),
                ("hostname", "a.local."),
                ("serial", "ZZZ"),
                ("name", "Galaxy"),
                ("service_type", "_adb-tls-connect._tcp"),
            ],
            1,
        );
        let b = dev_with_port(
            &[
                ("instance", "adb-AAA-1"),
                ("hostname", "b.local."),
                ("serial", "AAA"),
                ("name", "Moto"),
                ("service_type", "_adb-tls-connect._tcp"),
            ],
            2,
        );
        let err = select(&[a, b], None).unwrap_err();
        assert_eq!(
            err.message,
            "Multiple Android phones discovered (Moto [--device AAA], Galaxy [--device ZZZ]); pass --device <alias> or --all."
        );
        assert_eq!(err.candidates.len(), 2);
    }

    #[test]
    fn exact_match_on_two_devices_is_ambiguous() {
        let mut second = pixel4();
        second.set("serial", s("OTHERSERIAL"));
        second.set("instance", s("adb-OTHERSERIAL-x"));
        let err = select(&[pixel4(), second], Some("coral")).unwrap_err();
        assert!(err.message.starts_with("Filter 'coral' matched 2 devices: Pixel 4 XL (--device 98271FFBA007YW), Pixel 4 XL (--device OTHERSERIAL)."));
    }

    #[test]
    fn deduplicate_devices_by_serial_collapses_stale_mdns_entries() {
        let mut old = fold();
        old.set("instance", s("adb-66211FDDJ000XR-old"));
        old.set("port", int(39000));
        let mut new = fold();
        new.set("instance", s("adb-66211FDDJ000XR-new"));
        let sel = select(&[old, new], Some("fold")).unwrap().unwrap();
        assert_eq!(sel.get("instance"), Some(&s("adb-66211FDDJ000XR-new")));
        assert_eq!(sel.get("port"), Some(&int(46223)));
    }

    #[test]
    fn get_tailscale_android_peers() {
        let sys =
            MockSystem::new().run_output(&["tailscale", "status", "--json"], 0, TAILSCALE_JSON);
        let (t, _, _) = tool(&sys);
        let peers = t.get_tailscale_android_peers();
        assert_eq!(peers.len(), 1);
        assert_eq!(
            peers[0].get("hostname"),
            Some(&s("James Pixel 11 Pro Fold"))
        );
        assert_eq!(peers[0].get("tailscale_ip"), Some(&s("100.74.154.64")));
        assert_eq!(
            peers[0].get("dns_name"),
            Some(&s("james-pixel-11-pro-fold.coati-koi.ts.net"))
        );
        assert_eq!(peers[0].get("online"), Some(&Val::Bool(true)));
        assert_eq!(sys.calls(), vec![vec!["tailscale", "status", "--json"]]);
        assert_eq!(sys.timeouts(), vec![Some(2.0)]);
    }

    #[test]
    fn tailscale_failures_mean_no_peers() {
        for (code, out) in [(1, TAILSCALE_JSON), (0, ""), (0, "not json"), (124, "")] {
            let sys = MockSystem::new().run_output(&["tailscale", "status", "--json"], code, out);
            let (t, _, _) = tool(&sys);
            assert!(t.get_tailscale_android_peers().is_empty());
        }
    }

    #[test]
    fn find_target_device_prefer_tailscale() {
        let sys = fold_network().run_output(&["tailscale", "status", "--json"], 0, TAILSCALE_JSON);
        let (t, _, _) = tool(&sys);
        let target = t.find_target_device(None, true, 0.01).unwrap().unwrap();
        assert_eq!(target.get("target_ip"), Some(&s("100.74.154.64")));
        assert_eq!(target.get("endpoint"), Some(&s("100.74.154.64:41067")));
        assert_eq!(target.get("connection_type"), Some(&s("tailscale")));
        assert_eq!(
            target.get("mdns_endpoint"),
            Some(&s("adb-66211FDDJ000XR-DYsKrZ._adb-tls-connect._tcp"))
        );
    }

    #[test]
    fn find_target_device_fallback_lan() {
        let sys = fold_network();
        let (t, _, _) = tool(&sys);
        let target = t.find_target_device(None, false, 0.01).unwrap().unwrap();
        assert_eq!(target.get("target_ip"), Some(&s("192.168.86.36")));
        assert_eq!(target.get("endpoint"), Some(&s("192.168.86.36:41067")));
        assert_eq!(target.get("connection_type"), Some(&s("lan_ip")));
        assert!(
            sys.calls().is_empty(),
            "no tailscale call with prefer_tailscale=False"
        );
    }

    #[test]
    fn find_target_device_falls_back_to_hostname() {
        let sys = MockSystem::new()
            .spawn_output(&["dns-sd", "-B", "_adb-tls-connect._tcp", "local."], BROWSE)
            .spawn_output(
                &[
                    "dns-sd",
                    "-L",
                    "adb-66211FDDJ000XR-DYsKrZ",
                    "_adb-tls-connect._tcp",
                    "local.",
                ],
                LOOKUP,
            );
        let (t, _, _) = tool(&sys);
        let target = t.find_target_device(None, false, 0.01).unwrap().unwrap();
        assert_eq!(target.get("connection_type"), Some(&s("hostname")));
        assert_eq!(
            target.get("endpoint"),
            Some(&s("Android_43W5CGQ4.local.:41067"))
        );
    }

    #[test]
    fn find_target_device_filter_mismatch() {
        let sys = fold_network();
        let (t, _, _) = tool(&sys);
        assert_eq!(
            t.find_target_device(Some("GalaxyS24"), true, 0.01).unwrap(),
            None
        );
    }

    #[test]
    fn tv_does_not_use_unrelated_phone_tailscale_ip() {
        let mut tv_dev = tv();
        let peers = vec![Dict::from_pairs(vec![
            ("hostname", s("James Pixel 11 Pro Fold")),
            ("tailscale_ip", s("100.74.154.64")),
            ("active", Val::Bool(true)),
        ])];
        let sys = MockSystem::new().spawn_output(
            &["dns-sd", "-G", "v4", "Android.local."],
            &addr_line("Android.local.", "192.168.86.31"),
        );
        let (t, _, _) = tool(&sys);
        t.resolve_device_endpoint(&mut tv_dev, true, 2, Some(&peers));
        assert_eq!(tv_dev.get("target_ip"), Some(&s("192.168.86.31")));
        assert_eq!(tv_dev.get("endpoint"), Some(&s("192.168.86.31:5555")));
        assert_eq!(tv_dev.get("connection_type"), Some(&s("lan_ip")));
        assert_eq!(tv_dev.get("mdns_endpoint"), None);
    }

    #[test]
    fn lone_phone_uses_the_active_peer_even_without_a_name_match() {
        let mut phone = pixel4();
        let peers = vec![Dict::from_pairs(vec![
            ("hostname", s("unrelated")),
            ("tailscale_ip", s("100.1.1.1")),
            ("active", Val::Bool(true)),
        ])];
        let sys = MockSystem::new();
        let (t, _, _) = tool(&sys);
        t.resolve_device_endpoint(&mut phone, true, 1, Some(&peers));
        assert_eq!(phone.get("endpoint"), Some(&s("100.1.1.1:41295")));
    }

    #[test]
    fn discover_all_devices_sorts_and_resolves_everything() {
        let sys = fold_network()
            .spawn_output(
                &["dns-sd", "-B", "_adb._tcp", "local."],
                "20:16:35.946  Add  2  13 local.  _adb._tcp.  adb-24adbf003005591\n",
            )
            .spawn_output(
                &["dns-sd", "-L", "adb-24adbf003005591", "_adb._tcp", "local."],
                "x can be reached at Android.local.:5555 (interface 13)\n given_name=Bravia\n",
            )
            .spawn_output(
                &["dns-sd", "-G", "v4", "Android.local."],
                &addr_line("Android.local.", "192.168.86.31"),
            )
            .run_output(&["tailscale", "status", "--json"], 0, TAILSCALE_JSON);
        let (t, _, _) = tool(&sys);
        let all = t.discover_all_devices(true, 0.01);
        let keys: Vec<Val> = all.iter().map(|d| d.item("profile_key")).collect();
        assert_eq!(keys, vec![s("fold"), s("tv")]);
        assert_eq!(all[0].get("connection_type"), Some(&s("tailscale")));
        assert_eq!(all[1].get("endpoint"), Some(&s("192.168.86.31:5555")));
        // One tailscale call for the whole scan.
        assert_eq!(sys.calls().len(), 1);
    }
}
