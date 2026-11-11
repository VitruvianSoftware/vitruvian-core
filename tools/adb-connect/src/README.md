# Src

## Overview
Component package providing implementation for `tools/adb-connect/src`.

## Interface
- `[adb.rs:find_existing_adb_transport]`
- `[app.rs:run]`
- `[cli.rs:DESCRIPTION]`
- `[cli.rs:Args]`
- `[cli.rs:Parsed]`
- `[cli.rs:terminal_columns]`
- `[cli.rs:wrap]`
- `[cli.rs:format_usage]`
- `[cli.rs:format_help]`
- `[cli.rs:error_text]`
- `[cli.rs:parse]`
- `[discovery.rs:AmbiguousDeviceError]`
- `[discovery.rs:device_sort_key]`
- `[discovery.rs:sort_devices]`
- `[discovery.rs:deduplicate_devices_by_serial]`
- `[discovery.rs:select_target_device]`
- `[lib.rs:Tool]`
- `[lib.rs:default_config_path]`
- `[mdns.rs:find_reach]`
- `[mdns.rs:parse_txt_attrs]`

## Invariants
- [adb.rs:380]: `assert!(t.get_adb_attached_devices().is_empty());`
- [app.rs:396]: `assert!(text.starts_with("{\n  \"devices\": [\n    {\n      \"id\": \"100.74....`
- [app.rs:397]: `assert!(text.contains(`
- [app.rs:419]: `assert!(err.text().ends_with(`
- [main.rs:27]: `use std::panic;`
- [main.rs:47]: `let default_hook = panic::take_hook();`
- [main.rs:48]: `panic::set_hook(Box::new(move |info| {`
- [mdns.rs:383]: `assert!(t.browse_mdns_instances(5.0, &ADB_MDNS_SERVICES).is_empty());`
- [mdns.rs:384]: `assert!(sys.slept().is_empty());`
- [mdns.rs:487]: `assert!(t.resolve_mdns_instance("adb-unknown", 0.01, None).is_none());`

## Side Effects
- [mdns.rs:168]: `if let Some(p) = self.sys.spawn(&["dns-sd", "-B", svc, "local."]) {`
- [mdns.rs:195]: `let Some(p) = self.sys.spawn(&["dns-sd", "-B", SVC, "local."]) else {`
- [mdns.rs:217]: `let Some(lp) = self.sys.spawn(&["dns-sd", "-L", &inst, SVC, "local."]) else {`
- [system.rs:25]: `//! [`RealSystem`] reproduces what the Python tool's subprocess calls do:`
- [system.rs:26]: `//! `run_command` (`subprocess.run(..., capture_output=True, text=True,`
- [system.rs:54]: `/// `subprocess.Popen(cmd, stdout=PIPE, stderr=PIPE, text=True)`, or`
- [testutil.rs:105]: `/// No `dns-sd` on PATH: every spawn fails.`
- [testutil.rs:161]: `fn spawn(&self, cmd: &[&str]) -> Option<Box<dyn Pending>> {`

## Verification
- Run: `bazel test //tools/adb-connect/src/...`
