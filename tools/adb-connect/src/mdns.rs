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

//! mDNS over `dns-sd`: browsing for ADB services, looking an instance up
//! (host, port, TXT record), and resolving a `.local` name to IPv4.

use crate::profiles::{extract_serial, ADB_MDNS_SERVICES, ADB_PAIRING_SERVICE, SERVICE_LEGACY};
use crate::py::{parse_int, rstrip_chars, s, split_ws, splitlines, strip, Dict, Val};
use crate::system::{sleep_or_fail, sleep_or_raise};
use crate::Tool;

/// `re.search(r"can be reached at (.*?):(\d+)", text)`: `(host, port digits)`.
pub fn find_reach(text: &str) -> Option<(String, String)> {
    const LIT: &str = "can be reached at ";
    let mut from = 0;
    while let Some(pos) = text[from..].find(LIT) {
        let start = from + pos + LIT.len();
        let rest = &text[start..];
        for (i, c) in rest.char_indices() {
            if c == ':' {
                let digits: String = rest[i + 1..]
                    .chars()
                    .take_while(|d| d.is_ascii_digit())
                    .collect();
                if !digits.is_empty() {
                    return Some((rest[..i].to_string(), digits));
                }
            }
            if c == '\n' {
                break;
            }
        }
        from += pos + 1;
    }
    None
}

fn is_key_char(c: char) -> bool {
    c.is_ascii_alphanumeric() || c == '_' || c == '-'
}

/// The TXT attributes in `dns-sd -L` output, as the Python regex
/// `([a-zA-Z0-9_-]+)=((?:\\.|[^\s])+)` finds them, with `\ ` unescaped.
pub fn parse_txt_attrs(text: &str) -> Vec<(String, String)> {
    let c: Vec<char> = text.chars().collect();
    let n = c.len();
    let mut attrs: Vec<(String, String)> = Vec::new();
    let mut i = 0;
    while i < n {
        if is_key_char(c[i]) {
            let mut j = i;
            while j < n && is_key_char(c[j]) {
                j += 1;
            }
            if j < n && c[j] == '=' {
                let vstart = j + 1;
                let mut k = vstart;
                loop {
                    if k + 1 < n && c[k] == '\\' && c[k + 1] != '\n' {
                        k += 2;
                    } else if k < n && !crate::py::is_space(c[k]) {
                        k += 1;
                    } else {
                        break;
                    }
                }
                if k > vstart {
                    let key: String = c[i..j].iter().collect();
                    let raw: String = c[vstart..k].iter().collect();
                    let val = strip(&raw.replace("\\ ", " ")).to_string();
                    if let Some(slot) = attrs.iter_mut().find(|(kk, _)| *kk == key) {
                        slot.1 = val;
                    } else {
                        attrs.push((key, val));
                    }
                    i = k;
                    continue;
                }
            }
        }
        i += 1;
    }
    attrs
}

/// The instance names in `dns-sd -B` output, each with the service type
/// it was announced under, in first-seen order. Departures (`Rmv`) and
/// header lines are skipped. `svc` is the type this browse was for.
pub fn parse_browse_output(
    stdout: &str,
    svc: &str,
    service_types: &[&str],
) -> Vec<(String, String)> {
    let mut found: Vec<(String, String)> = Vec::new();
    for line in splitlines(stdout) {
        let line_str = strip(line);
        if line_str.is_empty()
            || line_str.starts_with("Browsing for")
            || line_str.contains("STARTING")
            || line_str.contains("Timestamp")
            || line_str.starts_with("DATE:")
        {
            continue;
        }
        let tokens = split_ws(line_str);
        if tokens.len() >= 2 && tokens[1] == "Rmv" {
            continue;
        }
        let candidates =
            std::iter::once(svc).chain(service_types.iter().copied().filter(|x| *x != svc));
        for candidate in candidates {
            let marker = format!("{}.", candidate);
            if line_str.contains(&marker) {
                if let Some(part) = line_str.split(marker.as_str()).nth(1) {
                    let instance = strip(part);
                    if !instance.is_empty() {
                        found.push((instance.to_string(), candidate.to_string()));
                    }
                }
                break;
            }
        }
    }
    found
}

/// The first IPv4 address in `dns-sd -G v4` output.
pub fn parse_addr_output(stdout: &str) -> Option<String> {
    for line in splitlines(stdout) {
        let parts = split_ws(strip(line));
        if parts.len() >= 6 {
            let candidate = parts[5];
            let octets: Vec<&str> = candidate.split('.').collect();
            if octets.len() == 4
                && octets
                    .iter()
                    .all(|o| !o.is_empty() && o.chars().all(|c| c.is_ascii_digit()))
            {
                return Some(candidate.to_string());
            }
        }
    }
    None
}

impl<'a> Tool<'a> {
    /// `browse_mdns_instances(timeout_s, service_types)`.
    pub fn browse_mdns_instances(&self, timeout_s: f64, service_types: &[&str]) -> Vec<String> {
        let mut procs = Vec::new();
        for svc in service_types {
            if let Some(p) = self.sys.spawn(&["dns-sd", "-B", svc, "local."]) {
                procs.push((*svc, p));
            }
        }
        if procs.is_empty() {
            return Vec::new();
        }
        sleep_or_raise(self.sys, timeout_s);
        let mut instances: Vec<String> = Vec::new();
        for (svc, proc_) in procs {
            let Some(stdout) = proc_.finish() else {
                continue;
            };
            for (instance, candidate) in parse_browse_output(&stdout, svc, service_types) {
                self.hints.borrow_mut().set(instance.clone(), s(candidate));
                if !instances.contains(&instance) {
                    instances.push(instance);
                }
            }
        }
        instances
    }

    /// `browse_androidtv_remote_names(timeout_s)`: `.local` host -> TV name.
    pub fn browse_androidtv_remote_names(&self, timeout_s: f64) -> Dict {
        const SVC: &str = "_androidtvremote2._tcp";
        const MARKER: &str = "_androidtvremote2._tcp.";
        let Some(p) = self.sys.spawn(&["dns-sd", "-B", SVC, "local."]) else {
            return Dict::new();
        };
        if !sleep_or_fail(self.sys, timeout_s) {
            return Dict::new();
        }
        let Some(stdout) = p.finish() else {
            return Dict::new();
        };
        let mut tv_instances: Vec<String> = Vec::new();
        for line in splitlines(&stdout) {
            if line.contains(MARKER) && line.contains("Add") {
                if let Some(part) = line.split(MARKER).nth(1) {
                    let inst = strip(part);
                    if !inst.is_empty() && !tv_instances.iter().any(|t| t == inst) {
                        tv_instances.push(inst.to_string());
                    }
                }
            }
        }
        let mut host_to_name = Dict::new();
        for inst in tv_instances {
            let Some(lp) = self.sys.spawn(&["dns-sd", "-L", &inst, SVC, "local."]) else {
                continue;
            };
            if !sleep_or_fail(self.sys, 0.5) {
                continue;
            }
            let Some(lout) = lp.finish() else { continue };
            if let Some((host, _)) = find_reach(&lout) {
                let host = format!("{}.", rstrip_chars(&host, "."));
                host_to_name.set(host.to_lowercase(), s(inst.clone()));
            }
        }
        host_to_name
    }

    /// `_lookup_mdns_service(instance, service_type, timeout_s)`.
    pub fn lookup_mdns_service(
        &self,
        instance: &str,
        service_type: &str,
        timeout_s: f64,
    ) -> String {
        let Some(p) = self
            .sys
            .spawn(&["dns-sd", "-L", instance, service_type, "local."])
        else {
            return String::new();
        };
        if !sleep_or_fail(self.sys, timeout_s) {
            return String::new();
        }
        p.finish().unwrap_or_default()
    }

    /// `resolve_mdns_instance(instance, timeout_s, service_hint)`.
    pub fn resolve_mdns_instance(
        &self,
        instance: &str,
        timeout_s: f64,
        service_hint: Option<&str>,
    ) -> Option<Dict> {
        let hint: Option<String> = match service_hint {
            Some(h) if !h.is_empty() => Some(h.to_string()),
            _ => self
                .hints
                .borrow()
                .get(instance)
                .and_then(|v| v.as_str().map(str::to_string)),
        };
        let all = [
            ADB_MDNS_SERVICES[0],
            ADB_MDNS_SERVICES[1],
            ADB_PAIRING_SERVICE,
        ];
        let ordered: Vec<&str> = match hint.as_deref() {
            Some(h) if all.contains(&h) => std::iter::once(h)
                .chain(ADB_MDNS_SERVICES.iter().copied().filter(|x| *x != h))
                .collect(),
            _ => ADB_MDNS_SERVICES.to_vec(),
        };

        let mut found = None;
        for svc in &ordered {
            let stdout = self.lookup_mdns_service(instance, svc, timeout_s);
            if let Some(reach) = find_reach(&stdout) {
                found = Some((stdout, reach, *svc));
                break;
            }
        }
        let (stdout, (host, port), service_type) = found?;
        let hostname = format!("{}.", rstrip_chars(&host, "."));
        let port = parse_int(&port).unwrap_or_else(|| "0".into());

        let attrs = parse_txt_attrs(&stdout);
        let attr = |k: &str| attrs.iter().find(|(kk, _)| kk == k).map(|(_, v)| v.clone());
        let mut serial = attr("serial").unwrap_or_default();
        if serial.is_empty() && instance.starts_with("adb-") {
            serial = extract_serial(instance);
        }
        let mut name = attr("name").unwrap_or_default();
        let mut given_name = match attr("given_name") {
            Some(g) if !g.is_empty() => g,
            _ => name.clone(),
        };
        if given_name.is_empty() && service_type == SERVICE_LEGACY {
            let tv_names = self.browse_androidtv_remote_names(timeout_s.min(0.8));
            let tv_label = tv_names
                .get(&hostname.to_lowercase())
                .map(Val::py_str)
                .unwrap_or_default();
            if !tv_label.is_empty() {
                given_name = tv_label.clone();
                if name.is_empty() {
                    name = tv_label;
                }
            }
        }
        Some(Dict::from_pairs(vec![
            ("instance", s(instance)),
            ("hostname", s(hostname)),
            ("port", Val::Int(port)),
            ("serial", s(serial)),
            ("name", s(name)),
            ("given_name", s(given_name)),
            ("api", s(attr("api").unwrap_or_default())),
            ("service_type", s(service_type)),
        ]))
    }

    /// `resolve_hostname_ipv4(hostname, timeout_s)`.
    pub fn resolve_hostname_ipv4(&self, hostname: &Val, timeout_s: f64) -> Option<String> {
        let stdout = match hostname.as_str() {
            Some(h) => match self.sys.spawn(&["dns-sd", "-G", "v4", h]) {
                Some(p) if sleep_or_fail(self.sys, timeout_s) => p.finish().unwrap_or_default(),
                _ => String::new(),
            },
            None => String::new(),
        };
        if let Some(ip) = parse_addr_output(&stdout) {
            return Some(ip);
        }
        let clean = rstrip_chars(hostname.expect_str("rstrip"), ".");
        self.sys.gethostbyname(clean)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testutil::*;

    #[test]
    fn browse_mdns_instances_parsing() {
        let sys = MockSystem::new()
            .spawn_output(&["dns-sd", "-B", "_adb-tls-connect._tcp", "local."], BROWSE);
        let (t, _, _) = tool(&sys);
        assert_eq!(
            t.browse_mdns_instances(0.01, &ADB_MDNS_SERVICES),
            vec!["adb-66211FDDJ000XR-DYsKrZ"]
        );
        assert_eq!(
            t.hints.borrow().get("adb-66211FDDJ000XR-DYsKrZ"),
            Some(&s("_adb-tls-connect._tcp"))
        );
        assert_eq!(sys.slept(), vec![0.01]);
    }

    #[test]
    fn browse_mdns_ignores_rmv_departure_lines() {
        let out = format!(
            "{}19:09:13.100  Rmv        0  13 local.               _adb-tls-connect._tcp. adb-stale-departed\n",
            BROWSE
        );
        let sys = MockSystem::new()
            .spawn_output(&["dns-sd", "-B", "_adb-tls-connect._tcp", "local."], &out);
        let (t, _, _) = tool(&sys);
        assert_eq!(
            t.browse_mdns_instances(0.01, &ADB_MDNS_SERVICES),
            vec!["adb-66211FDDJ000XR-DYsKrZ"]
        );
    }

    #[test]
    fn browse_without_dns_sd_returns_nothing_and_does_not_sleep() {
        let sys = MockSystem::new().no_spawn();
        let (t, _, _) = tool(&sys);
        assert!(t.browse_mdns_instances(5.0, &ADB_MDNS_SERVICES).is_empty());
        assert!(sys.slept().is_empty());
    }

    #[test]
    fn resolve_mdns_instance_parsing() {
        let sys = MockSystem::new().spawn_output(
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
        let r = t
            .resolve_mdns_instance("adb-66211FDDJ000XR-DYsKrZ", 0.01, None)
            .unwrap();
        assert_eq!(r.get("instance"), Some(&s("adb-66211FDDJ000XR-DYsKrZ")));
        assert_eq!(r.get("hostname"), Some(&s("Android_43W5CGQ4.local.")));
        assert_eq!(r.get("port"), Some(&int(41067)));
        assert_eq!(r.get("given_name"), Some(&s("James Pixel 11 Pro Fold")));
        assert_eq!(r.get("serial"), Some(&s("66211FDDJ000XR")));
        assert_eq!(r.get("name"), Some(&s("Pixel 11 Pro Fold")));
        assert_eq!(r.get("api"), Some(&s("37.0")));
        assert_eq!(r.get("service_type"), Some(&s("_adb-tls-connect._tcp")));
    }

    #[test]
    fn resolve_mdns_instance_pixel4_extracts_serial_from_instance_name() {
        let sys = MockSystem::new().spawn_output(
            &[
                "dns-sd",
                "-L",
                "adb-98271FFBA007YW-OflOTi",
                "_adb-tls-connect._tcp",
                "local.",
            ],
            LOOKUP_PIXEL4,
        );
        let (t, _, _) = tool(&sys);
        let r = t
            .resolve_mdns_instance("adb-98271FFBA007YW-OflOTi", 0.01, None)
            .unwrap();
        assert_eq!(r.get("serial"), Some(&s("98271FFBA007YW")));
        assert_eq!(r.get("name"), Some(&s("Pixel 4 XL")));
        assert_eq!(r.get("port"), Some(&int(41295)));
        // `api=` has an empty value, which the regex does not match.
        assert_eq!(r.get("api"), Some(&s("")));
    }

    #[test]
    fn browse_and_resolve_legacy_adb_tcp_tv() {
        let sys = MockSystem::new()
            .spawn_output(&["dns-sd", "-B", "_adb._tcp", "local."], BROWSE_TCP)
            .spawn_output(&["dns-sd", "-L", "adb-24adbf003005591", "_adb._tcp", "local."], LOOKUP_TCP)
            .spawn_output(
                &["dns-sd", "-B", "_androidtvremote2._tcp", "local."],
                "12:00:00.000  Add        2  13 local.  _androidtvremote2._tcp. Living Room Sony TV\n",
            )
            .spawn_output(
                &["dns-sd", "-L", "Living Room Sony TV", "_androidtvremote2._tcp", "local."],
                "x can be reached at Android.local.:6466 (interface 13)\n",
            );
        let (t, _, _) = tool(&sys);
        assert_eq!(
            t.browse_mdns_instances(0.01, &ADB_MDNS_SERVICES),
            vec!["adb-24adbf003005591"]
        );
        let r = t
            .resolve_mdns_instance("adb-24adbf003005591", 0.01, None)
            .unwrap();
        // The browse hint sends the lookup straight to _adb._tcp.
        let lookups: Vec<Vec<String>> = sys
            .spawned()
            .into_iter()
            .filter(|c| c[1] == "-L" && c[3] != "_androidtvremote2._tcp")
            .collect();
        assert_eq!(
            lookups,
            vec![vec![
                "dns-sd",
                "-L",
                "adb-24adbf003005591",
                "_adb._tcp",
                "local."
            ]]
        );
        assert_eq!(r.get("hostname"), Some(&s("Android.local.")));
        assert_eq!(r.get("port"), Some(&int(5555)));
        assert_eq!(r.get("serial"), Some(&s("24adbf003005591")));
        assert_eq!(r.get("given_name"), Some(&s("Living Room Sony TV")));
        assert_eq!(r.get("name"), Some(&s("Living Room Sony TV")));
        assert_eq!(r.get("service_type"), Some(&s("_adb._tcp")));
        // min(timeout_s, 0.8) for the TV browse, 0.5 for its lookup.
        assert_eq!(sys.slept(), vec![0.01, 0.01, 0.01, 0.5]);
    }

    #[test]
    fn resolve_falls_back_across_services_and_fails_cleanly() {
        let sys = MockSystem::new();
        let (t, _, _) = tool(&sys);
        assert!(t.resolve_mdns_instance("adb-unknown", 0.01, None).is_none());
        let tried: Vec<String> = sys.spawned().into_iter().map(|c| c[3].clone()).collect();
        assert_eq!(tried, vec!["_adb-tls-connect._tcp", "_adb._tcp"]);
        let sys = MockSystem::new();
        let (t, _, _) = tool(&sys);
        t.resolve_mdns_instance("adb-x", 0.01, Some(ADB_PAIRING_SERVICE));
        let tried: Vec<String> = sys.spawned().into_iter().map(|c| c[3].clone()).collect();
        assert_eq!(
            tried,
            vec![
                "_adb-tls-pairing._tcp",
                "_adb-tls-connect._tcp",
                "_adb._tcp"
            ]
        );
    }

    #[test]
    fn resolve_hostname_ipv4_parsing_and_fallback() {
        let sys = MockSystem::new()
            .spawn_output(&["dns-sd", "-G", "v4", "Android_43W5CGQ4.local."], ADDR);
        let (t, _, _) = tool(&sys);
        assert_eq!(
            t.resolve_hostname_ipv4(&s("Android_43W5CGQ4.local."), 0.01)
                .as_deref(),
            Some("192.168.86.36")
        );
        let sys = MockSystem::new().host("other.local", "10.0.0.9");
        let (t, _, _) = tool(&sys);
        assert_eq!(
            t.resolve_hostname_ipv4(&s("other.local."), 0.01).as_deref(),
            Some("10.0.0.9")
        );
        assert_eq!(sys.hosts_asked(), vec!["other.local"]);
    }

    #[test]
    fn txt_parser_follows_the_python_regex() {
        let attrs = parse_txt_attrs(
            "x can be reached at h.local.:1 a=b c=d\\ e\\\\ f bad= k-1=v_1 trail=\\\n dup=1 dup=2",
        );
        let got: Vec<(&str, &str)> = attrs
            .iter()
            .map(|(k, v)| (k.as_str(), v.as_str()))
            .collect();
        assert_eq!(
            got,
            vec![
                ("a", "b"),
                ("c", "d e\\\\"),
                ("k-1", "v_1"),
                ("trail", "\\"),
                ("dup", "2")
            ]
        );
    }

    #[test]
    fn reach_regex_is_lazy_and_line_bound() {
        assert_eq!(
            find_reach("can be reached at fe80::1:5555 x"),
            Some(("fe80:".to_string(), "1".to_string()))
        );
        assert_eq!(find_reach("can be reached at host\n:55"), None);
        assert_eq!(
            find_reach("can be reached at nope\ncan be reached at h.:7 "),
            Some(("h.".to_string(), "7".to_string()))
        );
    }
}
