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

//! The command-line flow: `main()` in adb_connect.py.

use crate::adb::find_existing_adb_transport;
use crate::cli::{self, Args, Parsed};
use crate::profiles::{enrich_device_with_profile, SERVICE_TLS_CONNECT};
use crate::py::{s, Dict, Val};
use crate::pyjson::dumps;
use crate::Tool;

fn json_indent(v: Val) -> String {
    dumps(&v, Some(2))
}

fn json_flat(v: Val) -> String {
    dumps(&v, None)
}

fn obj(pairs: Vec<(&str, Val)>) -> Val {
    Val::Dict(Dict::from_pairs(pairs))
}

/// `max(timeout, 2.0)` with Python's argument order (NaN stays NaN).
fn py_max(a: f64, b: f64) -> f64 {
    if b > a {
        b
    } else {
        a
    }
}

/// Run the tool for `argv` (without the program name). Returns the exit
/// status. `columns` is the terminal width argparse formats help for.
pub fn run(tool: &Tool, prog: &str, argv: &[String], columns: i64) -> i32 {
    let args = match cli::parse(prog, argv, columns) {
        Parsed::Run(a) => a,
        Parsed::Exit {
            code,
            stdout,
            stderr,
        } => {
            tool.write_out(&stdout);
            tool.write_err(&stderr);
            return code;
        }
    };
    if args.all
        && (non_empty(&args.device).is_some() || non_empty(&args.ip).is_some() || args.print_serial)
    {
        tool.write_err(&cli::error_text(
            prog,
            columns,
            "--all cannot be combined with --device, --ip, or --print-serial.",
        ));
        return 2;
    }
    run_args(tool, &args)
}

fn non_empty(o: &Option<String>) -> Option<&str> {
    o.as_deref().filter(|v| !v.is_empty())
}

fn run_args(tool: &Tool, args: &Args) -> i32 {
    let device = non_empty(&args.device);
    let ip = non_empty(&args.ip);
    let tcpip = args.tcpip.as_deref();

    if args.status {
        let mut devices = tool.get_adb_attached_devices();
        let profiles = tool.load_device_profiles(None);
        for d in devices.iter_mut() {
            enrich_device_with_profile(d, &profiles);
        }
        if args.json {
            let list = Val::List(devices.into_iter().map(Val::Dict).collect());
            tool.print(&json_indent(obj(vec![("devices", list)])));
        } else if devices.is_empty() {
            tool.print("No adb devices currently attached.");
        } else {
            tool.print(&format!("Attached adb devices ({}):", devices.len()));
            for d in &devices {
                let alias_tag = if d.get_none("profile_key").truthy() {
                    format!(" alias:{}", d.item("profile_key").py_str())
                } else {
                    String::new()
                };
                tool.print(&format!(
                    "  • {} [{}] model:{}{}",
                    d.item("id").py_str(),
                    d.item("status").py_str(),
                    d.get_or("model", s("unknown")).py_str(),
                    alias_tag
                ));
            }
        }
        return 0;
    }

    if let Some(code) = non_empty(&args.pair) {
        let res = tool.pair_device(code, device, py_max(args.timeout, 2.0));
        let success = res.item("success").truthy();
        if args.json {
            tool.print(&json_indent(Val::Dict(res)));
        } else if success {
            tool.print(&format!("✓ {}", res.item("stdout").py_str()));
        } else {
            let why = res
                .get_none("error")
                .or_else(|| res.get_none("stderr"))
                .or_else(|| res.get_none("stdout"));
            tool.eprint(&format!("✗ Pairing failed: {}", why.py_str()));
        }
        return if success { 0 } else { 2 };
    }

    if args.discover {
        let mut discovered = tool.discover_all_devices(!args.no_tailscale, args.timeout);
        let attached = tool.get_adb_attached_devices();
        for dev in discovered.iter_mut() {
            let (existing, duplicates) = find_existing_adb_transport(dev, &attached);
            let (status, id) = match &existing {
                Some(e) => (e.item("status"), e.item("id")),
                None => (s("not_attached"), s("")),
            };
            dev.set("adb_status", status);
            dev.set("adb_transport_id", id);
            dev.set(
                "duplicate_transports",
                Val::List(duplicates.into_iter().map(s).collect()),
            );
        }
        if args.json {
            let list = Val::List(discovered.into_iter().map(Val::Dict).collect());
            tool.print(&json_indent(obj(vec![("discovered", list)])));
        } else if discovered.is_empty() {
            tool.print("No Android mDNS services discovered on the local network.");
        } else {
            tool.print(&format!(
                "Discovered Android mDNS devices ({}):",
                discovered.len()
            ));
            for d in &discovered {
                let label = d
                    .get_none("given_name")
                    .or_else(|| d.get_none("name"))
                    .or_else(|| d.item("instance"));
                let alias = d.get_none("profile_key").or(s("-"));
                let role = d.get_none("role").or(s("-"));
                let status = d.get_or("adb_status", s("not_attached"));
                let serial = d.get_none("serial").or(s("unknown"));
                tool.print(&format!(
                    "  • {} (alias: {}, role: {}, serial: {})\n    service: {} | endpoint: {} ({}) | adb: {}",
                    label.py_str(),
                    alias.py_str(),
                    role.py_str(),
                    serial.py_str(),
                    d.get_none("service_type").py_str(),
                    d.item("endpoint").py_str(),
                    d.item("connection_type").py_str(),
                    status.py_str()
                ));
            }
        }
        return 0;
    }

    if args.all {
        let discovered = tool.discover_all_devices(!args.no_tailscale, args.timeout);
        let phones: Vec<Dict> = discovered
            .into_iter()
            .filter(|d| d.get_none("service_type").eq_str(SERVICE_TLS_CONNECT))
            .collect();
        if phones.is_empty() {
            let msg = "No Wireless Debugging phones (_adb-tls-connect._tcp) discovered.";
            if args.json {
                tool.print(&json_flat(obj(vec![
                    ("success", Val::Bool(false)),
                    ("error", s(msg)),
                    ("results", Val::List(vec![])),
                ])));
            } else {
                tool.eprint(&format!("Error: {}", msg));
            }
            return 1;
        }
        let attached = tool.get_adb_attached_devices();
        let results: Vec<Dict> = phones
            .iter()
            .map(|p| tool.connect_device(p, tcpip, Some(&attached)))
            .collect();
        let all_ok = results.iter().all(|r| r.item("success").truthy());
        if args.json {
            let list = Val::List(results.into_iter().map(Val::Dict).collect());
            tool.print(&json_indent(obj(vec![
                ("success", Val::Bool(all_ok)),
                ("results", list),
            ])));
        } else {
            for r in &results {
                let mark = if r.item("success").truthy() {
                    "✓"
                } else {
                    "✗"
                };
                tool.print(&format!(
                    "{} {} ({}): {}",
                    mark,
                    r.item("device").py_str(),
                    r.get_none("profile").or_else(|| r.item("serial")).py_str(),
                    r.item("stdout").or_else(|| r.item("stderr")).py_str()
                ));
            }
        }
        return if all_ok { 0 } else { 2 };
    }

    if args.disconnect_first && device.is_none() {
        tool.sys.run(&["adb", "disconnect"], Some(2.0));
    }

    if !args.json && !args.print_serial {
        tool.print("Scanning local network for Android Wireless Debugging (mDNS)...");
    }

    let target = match tool.find_target_device(device, !args.no_tailscale, args.timeout) {
        Ok(t) => t,
        Err(e) => {
            if args.json {
                tool.print(&json_flat(obj(vec![
                    ("success", Val::Bool(false)),
                    ("error", s(e.message)),
                ])));
            } else {
                tool.eprint(&format!("Error: {}", e.message));
            }
            return 1;
        }
    };
    let Some(mut target) = target else {
        let msg = "No Android Wireless Debugging instances discovered via mDNS.";
        if args.json {
            tool.print(&json_flat(obj(vec![
                ("success", Val::Bool(false)),
                ("error", s(msg)),
            ])));
        } else {
            tool.eprint(&format!("Error: {}", msg));
            tool.eprint("Ensure Wireless Debugging is toggled ON in Developer Options.");
        }
        return 1;
    };

    if let Some(ip) = ip {
        target.set("target_ip", s(ip));
        let endpoint = format!("{}:{}", ip, target.item("port").py_str());
        target.set("endpoint", s(endpoint));
        target.set("connection_type", s("manual_override"));
    }

    let mut attached = tool.get_adb_attached_devices();
    if args.disconnect_first && device.is_some() {
        let (existing, duplicates) = find_existing_adb_transport(&target, &attached);
        if let Some(existing) = existing {
            let id = existing.item("id").py_str();
            tool.sys.run(&["adb", "disconnect", &id], Some(2.0));
        }
        for dup in &duplicates {
            tool.sys.run(&["adb", "disconnect", dup], Some(2.0));
        }
        attached = tool.get_adb_attached_devices();
    }

    if !args.json && !args.print_serial {
        let dev_label = target
            .item("given_name")
            .or_else(|| target.item("name"))
            .or(s("Android Device"));
        let alias_suffix = if target.get_none("profile_key").truthy() {
            format!(" [{}]", target.item("profile_key").py_str())
        } else {
            String::new()
        };
        tool.print(&format!(
            "Found: {}{} (port {}, via {})",
            dev_label.py_str(),
            alias_suffix,
            target.item("port").py_str(),
            target.item("connection_type").py_str()
        ));
        tool.print(&format!(
            "Connecting adb to {}...",
            target.item("endpoint").py_str()
        ));
    }

    let result = tool.connect_device(
        &target,
        tcpip,
        if ip.is_some() { None } else { Some(&attached) },
    );
    let success = result.item("success").truthy();

    if args.print_serial {
        if success {
            let serial = result
                .get_none("adb_serial")
                .or_else(|| result.item("endpoint"));
            tool.print(&serial.py_str());
            return 0;
        }
        let why = match result.get_none("stderr") {
            v if v.truthy() => v.py_str(),
            _ => format!("failed to connect to {}", target.item("endpoint").py_str()),
        };
        tool.eprint(&format!("Error: {}", why));
        return 2;
    }

    if args.json {
        tool.print(&json_indent(Val::Dict(result)));
    } else if success {
        tool.print(&format!("✓ {}", result.item("stdout").py_str()));
        if let Some(Val::Dict(tcp)) = result.get("tcpip_mode") {
            if tcp.item("success").truthy() {
                tool.print(&format!(
                    "✓ Restarted adbd in TCP/IP mode on port {}.",
                    tcp.item("requested_port").py_str()
                ));
            } else {
                tool.eprint(&format!(
                    "⚠ Failed to switch to TCP/IP mode: {}",
                    tcp.item("stderr").py_str()
                ));
            }
        }
    } else {
        tool.eprint(&format!(
            "✗ Failed to connect: {}",
            result
                .item("stderr")
                .or_else(|| result.item("stdout"))
                .py_str()
        ));
    }
    if success {
        0
    } else {
        2
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testutil::*;

    fn argv(a: &[&str]) -> Vec<String> {
        a.iter().map(|x| x.to_string()).collect()
    }

    #[test]
    fn status_text_and_json() {
        let sys = MockSystem::new().run_output(&["adb", "devices", "-l"], 0, ADB_DEVICES);
        let (t, out, _) = tool(&sys);
        assert_eq!(run(&t, "adb-connect", &argv(&["--status"]), 80), 0);
        assert_eq!(
            out.text(),
            "Attached adb devices (2):\n  • 100.74.154.64:41067 [device] model:Pixel_11_Pro_Fold alias:fold\n  • emulator-5554 [device] model:sdk_gphone64_arm64\n"
        );
        let (t, out, _) = tool(&sys);
        assert_eq!(
            run(&t, "adb-connect", &argv(&["--status", "--json"]), 80),
            0
        );
        let text = out.text();
        assert!(text.starts_with("{\n  \"devices\": [\n    {\n      \"id\": \"100.74.154.64:41067\",\n      \"status\": \"device\",\n      \"product\": \"yogi\","));
        assert!(text.contains(
            "\"profile_key\": \"fold\",\n      \"role\": \"primary\",\n      \"is_default\": true,"
        ));
    }

    #[test]
    fn status_with_no_devices() {
        let sys = MockSystem::new().run_output(
            &["adb", "devices", "-l"],
            0,
            "List of devices attached\n",
        );
        let (t, out, _) = tool(&sys);
        assert_eq!(run(&t, "adb-connect", &argv(&["--status"]), 80), 0);
        assert_eq!(out.text(), "No adb devices currently attached.\n");
    }

    #[test]
    fn all_conflicts_with_device() {
        let sys = MockSystem::new();
        let (t, _, err) = tool(&sys);
        assert_eq!(run(&t, "adb-connect", &argv(&["--all", "-d", "x"]), 80), 2);
        assert!(err.text().ends_with(
            "adb-connect: error: --all cannot be combined with --device, --ip, or --print-serial.\n"
        ));
        // An empty --device is falsy in Python, so it does not conflict.
        let (t, _, _) = tool(&sys);
        assert_eq!(
            run(&t, "adb-connect", &argv(&["--all", "-d", "", "--json"]), 80),
            1
        );
    }

    #[test]
    fn default_flow_connects_the_fold() {
        let sys = fold_network()
            .run_output(&["tailscale", "status", "--json"], 0, TAILSCALE_JSON)
            .run_seq(
                &["adb", "devices", "-l"],
                vec![
                    (0, "List of devices attached\n", ""),
                    (0, "List of devices attached\nadb-66211FDDJ000XR-DYsKrZ._adb-tls-connect._tcp device product:yogi\n", ""),
                ],
            )
            .run_output(
                &["adb", "connect", "adb-66211FDDJ000XR-DYsKrZ._adb-tls-connect._tcp"],
                0,
                "connected to adb-66211FDDJ000XR-DYsKrZ._adb-tls-connect._tcp",
            );
        let (t, out, err) = tool(&sys);
        assert_eq!(run(&t, "adb-connect", &argv(&[]), 80), 0);
        assert_eq!(
            out.text(),
            "Scanning local network for Android Wireless Debugging (mDNS)...\n\
             Found: James Pixel 11 Pro Fold [fold] (port 41067, via tailscale)\n\
             Connecting adb to 100.74.154.64:41067...\n\
             ✓ connected to adb-66211FDDJ000XR-DYsKrZ._adb-tls-connect._tcp\n"
        );
        assert_eq!(err.text(), "");
    }

    #[test]
    fn print_serial_and_nothing_found() {
        let sys = MockSystem::new();
        let (t, out, err) = tool(&sys);
        assert_eq!(run(&t, "adb-connect", &argv(&["--print-serial"]), 80), 1);
        assert_eq!(out.text(), "");
        assert_eq!(
            err.text(),
            "Error: No Android Wireless Debugging instances discovered via mDNS.\nEnsure Wireless Debugging is toggled ON in Developer Options.\n"
        );
        let (t, out, _) = tool(&sys);
        assert_eq!(run(&t, "adb-connect", &argv(&["--json"]), 80), 1);
        assert_eq!(
            out.text(),
            "{\"success\": false, \"error\": \"No Android Wireless Debugging instances discovered via mDNS.\"}\n"
        );
    }

    #[test]
    fn pair_bad_code_exits_2() {
        let sys = MockSystem::new();
        let (t, out, err) = tool(&sys);
        assert_eq!(run(&t, "adb-connect", &argv(&["--pair", "12ab"]), 80), 2);
        assert_eq!(out.text(), "");
        assert_eq!(
            err.text(),
            "✗ Pairing failed: Pairing code must be a 6-digit number.\n"
        );
        assert!(sys.slept().is_empty());
    }

    #[test]
    fn negative_timeout_raises_like_time_sleep() {
        let sys = MockSystem::new();
        let (t, _, _) = tool(&sys);
        let res = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            run(
                &t,
                "adb-connect",
                &argv(&["--discover", "--timeout", "-1"]),
                80,
            )
        }));
        let exc = res.unwrap_err();
        let exc = exc.downcast_ref::<crate::py::PyExc>().unwrap();
        assert_eq!(
            (exc.kind, exc.msg.as_str()),
            ("ValueError", "sleep length must be non-negative")
        );
    }

    #[test]
    fn help_goes_to_stdout() {
        let sys = MockSystem::new();
        let (t, out, _) = tool(&sys);
        assert_eq!(run(&t, "adb-connect", &argv(&["-h"]), 80), 0);
        assert!(out.text().starts_with("usage: adb-connect [-h]"));
    }
}
