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

//! Test doubles and fixtures: a scripted [`System`], captured output,
//! temporary files, and the `dns-sd` / `adb` / `tailscale` samples the
//! Python tests use.

pub use crate::py::{int, s, Dict};
use crate::system::{Pending, System};
use crate::Tool;
use std::cell::RefCell;
use std::collections::HashMap;
use std::io::Write;
use std::rc::Rc;

/// Captured stdout or stderr.
#[derive(Clone, Default)]
pub struct Buf(Rc<RefCell<Vec<u8>>>);

impl Buf {
    pub fn text(&self) -> String {
        String::from_utf8(self.0.borrow().clone()).expect("utf-8 output")
    }
}

impl Write for Buf {
    fn write(&mut self, data: &[u8]) -> std::io::Result<usize> {
        self.0.borrow_mut().extend_from_slice(data);
        Ok(data.len())
    }
    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}

type RunResult = (i32, String, String);

/// A scripted system: canned output per command line, every call recorded.
#[derive(Default)]
pub struct MockSystem {
    run_scripts: RefCell<HashMap<Vec<String>, Vec<RunResult>>>,
    run_default: Option<RunResult>,
    spawn_outputs: HashMap<Vec<String>, String>,
    spawn_disabled: bool,
    hosts: HashMap<String, String>,
    calls: RefCell<Vec<(Vec<String>, Option<f64>)>>,
    spawned: RefCell<Vec<Vec<String>>>,
    slept: RefCell<Vec<f64>>,
    hosts_asked: RefCell<Vec<String>>,
}

fn key(cmd: &[&str]) -> Vec<String> {
    cmd.iter().map(|c| c.to_string()).collect()
}

impl MockSystem {
    pub fn new() -> Self {
        Self::default()
    }

    /// `cmd` prints `out` and exits with `code`, every time.
    pub fn run_output(self, cmd: &[&str], code: i32, out: &str) -> Self {
        self.run_seq(cmd, vec![(code, out, "")])
    }

    /// `cmd` answers with each result in turn, repeating the last.
    pub fn run_seq(self, cmd: &[&str], results: Vec<(i32, &str, &str)>) -> Self {
        let results = results
            .into_iter()
            .map(|(c, o, e)| (c, o.to_string(), e.to_string()))
            .collect();
        self.run_scripts.borrow_mut().insert(key(cmd), results);
        self
    }

    /// Any command without a script answers this (default: exit 0, no output).
    pub fn run_default(mut self, code: i32, out: &str, err: &str) -> Self {
        self.run_default = Some((code, out.to_string(), err.to_string()));
        self
    }

    /// A background `cmd` (dns-sd) prints `out`.
    pub fn spawn_output(mut self, cmd: &[&str], out: &str) -> Self {
        self.spawn_outputs.insert(key(cmd), out.to_string());
        self
    }

    /// No `dns-sd` on PATH: every spawn fails.
    pub fn no_spawn(mut self) -> Self {
        self.spawn_disabled = true;
        self
    }

    /// `socket.gethostbyname(name)` answers `ip`.
    pub fn host(mut self, name: &str, ip: &str) -> Self {
        self.hosts.insert(name.to_string(), ip.to_string());
        self
    }

    pub fn calls(&self) -> Vec<Vec<String>> {
        self.calls.borrow().iter().map(|(c, _)| c.clone()).collect()
    }

    pub fn timeouts(&self) -> Vec<Option<f64>> {
        self.calls.borrow().iter().map(|(_, t)| *t).collect()
    }

    pub fn spawned(&self) -> Vec<Vec<String>> {
        self.spawned.borrow().clone()
    }

    pub fn slept(&self) -> Vec<f64> {
        self.slept.borrow().clone()
    }

    pub fn hosts_asked(&self) -> Vec<String> {
        self.hosts_asked.borrow().clone()
    }
}

struct MockPending(String);

impl Pending for MockPending {
    fn finish(self: Box<Self>) -> Option<String> {
        Some(self.0)
    }
}

impl System for MockSystem {
    fn run(&self, cmd: &[&str], timeout: Option<f64>) -> (i32, String, String) {
        self.calls.borrow_mut().push((key(cmd), timeout));
        let mut scripts = self.run_scripts.borrow_mut();
        if let Some(results) = scripts.get_mut(&key(cmd)) {
            if results.len() > 1 {
                return results.remove(0);
            }
            return results[0].clone();
        }
        self.run_default
            .clone()
            .unwrap_or((0, String::new(), String::new()))
    }

    fn spawn(&self, cmd: &[&str]) -> Option<Box<dyn Pending>> {
        if self.spawn_disabled {
            return None;
        }
        self.spawned.borrow_mut().push(key(cmd));
        let out = self
            .spawn_outputs
            .get(&key(cmd))
            .cloned()
            .unwrap_or_default();
        Some(Box::new(MockPending(out)))
    }

    fn sleep(&self, secs: f64) {
        self.slept.borrow_mut().push(secs);
    }

    fn gethostbyname(&self, host: &str) -> Option<String> {
        self.hosts_asked.borrow_mut().push(host.to_string());
        self.hosts.get(host).cloned()
    }
}

/// A tool on `sys` with captured stdout and stderr, and no user profiles.
pub fn tool(sys: &MockSystem) -> (Tool<'_>, Buf, Buf) {
    let out = Buf::default();
    let err = Buf::default();
    let t = Tool::new(
        sys,
        "/nonexistent/adb-connect-test/adb-devices.json".into(),
        Box::new(out.clone()),
        Box::new(err.clone()),
    );
    (t, out, err)
}

/// A device dict of string fields.
pub fn dev(pairs: &[(&str, &str)]) -> Dict {
    Dict::from_pairs(pairs.iter().map(|(k, v)| (*k, s(*v))).collect())
}

/// A device dict of string fields plus an int `port`.
pub fn dev_with_port(pairs: &[(&str, &str)], port: i64) -> Dict {
    let mut d = dev(pairs);
    d.set("port", int(port));
    d
}

/// A temporary directory, removed on drop.
pub struct TempDir(std::path::PathBuf);

impl TempDir {
    pub fn new() -> Self {
        use std::sync::atomic::{AtomicUsize, Ordering};
        static N: AtomicUsize = AtomicUsize::new(0);
        let base = std::env::var("TEST_TMPDIR")
            .map(std::path::PathBuf::from)
            .unwrap_or_else(|_| std::env::temp_dir());
        let dir = base.join(format!(
            "adb-connect-{}-{}",
            std::process::id(),
            N.fetch_add(1, Ordering::SeqCst)
        ));
        std::fs::create_dir_all(&dir).expect("create temp dir");
        TempDir(dir)
    }

    pub fn write(&self, name: &str, content: &str) -> String {
        let path = self.0.join(name);
        std::fs::write(&path, content).expect("write temp file");
        path.to_string_lossy().into_owned()
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

pub const BROWSE: &str = "
Browsing for _adb-tls-connect._tcp.local.
DATE: ---Tue 22 Sep 2026---
19:09:12.601  ...STARTING...
Timestamp     A/R    Flags  if Domain               Service Type         Instance Name
19:09:12.789  Add        2  13 local.               _adb-tls-connect._tcp. adb-66211FDDJ000XR-DYsKrZ
";

pub const LOOKUP: &str = "
Lookup adb-66211FDDJ000XR-DYsKrZ._adb-tls-connect._tcp.local.
DATE: ---Tue 22 Sep 2026---
19:09:16.819  ...STARTING...
19:09:16.820  adb-66211FDDJ000XR-DYsKrZ._adb-tls-connect._tcp.local. can be reached at Android_43W5CGQ4.local.:41067 (interface 13)
 given_name=James\\ Pixel\\ 11\\ Pro\\ Fold serial=66211FDDJ000XR v=2.0 api=37.0 name=Pixel\\ 11\\ Pro\\ Fold
";

pub const LOOKUP_PIXEL4: &str = "
Lookup adb-98271FFBA007YW-OflOTi._adb-tls-connect._tcp.local.
DATE: ---Fri 23 Oct 2026---
21:18:57.645  ...STARTING...
21:18:57.645  adb-98271FFBA007YW-OflOTi._adb-tls-connect._tcp.local. can be reached at Android-2.local.:41295 (interface 13)
 api= name=Pixel\\ 4\\ XL v=1
";

pub const ADDR: &str = "
DATE: ---Tue 22 Sep 2026---
19:09:34.153  ...STARTING...
Timestamp     A/R  Flags         IF  Hostname                               Address                                      TTL
19:09:34.153  Add  40000002      13  Android_43W5CGQ4.local.                192.168.86.36                                120
";

pub const BROWSE_TCP: &str = "
Browsing for _adb._tcp.local.
DATE: ---Thu 22 Oct 2026---
20:16:35.945  ...STARTING...
Timestamp     A/R    Flags  if Domain               Service Type         Instance Name
20:16:35.946  Add        2  13 local.               _adb._tcp.           adb-24adbf003005591
";

pub const LOOKUP_TCP: &str = "
Lookup adb-24adbf003005591._adb._tcp.local.
DATE: ---Thu 22 Oct 2026---
20:16:50.334  ...STARTING...
20:16:50.335  adb-24adbf003005591._adb._tcp.local. can be reached at Android.local.:5555 (interface 13)
";

pub const TAILSCALE_JSON: &str = r#"{"Peer": {
  "nodekey:mac": {"HostName": "james-mbp32", "OS": "macOS", "TailscaleIPs": ["100.103.234.45"], "Online": true},
  "nodekey:pixel": {"HostName": "James Pixel 11 Pro Fold", "DNSName": "james-pixel-11-pro-fold.coati-koi.ts.net.",
    "OS": "android", "TailscaleIPs": ["100.74.154.64", "fd7a:115c:a1e0::5b39:9a41"],
    "CurAddr": "192.168.86.36:48143", "Online": true, "Active": true}
}}"#;

pub const ADB_DEVICES: &str = "List of devices attached
100.74.154.64:41067    device product:yogi model:Pixel_11_Pro_Fold device:yogi transport_id:1116
emulator-5554          device product:sdk_gphone64_arm64 model:sdk_gphone64_arm64 device:emu64a transport_id:1001
";

pub const ADB_MULTI_DEVICES: &str = "List of devices attached
192.168.86.31:5555     unauthorized transport_id:2
192.168.86.61:41295    device product:coral model:Pixel_4_XL device:coral transport_id:277
adb-66211FDDJ000XR-DYsKrZ._adb-tls-connect._tcp device product:yogi model:Pixel_11_Pro_Fold device:yogi transport_id:1
adb-98271FFBA007YW-OflOTi._adb-tls-connect._tcp device product:coral model:Pixel_4_XL device:coral transport_id:276
";

/// A `dns-sd -G v4` answer for one host.
pub fn addr_line(host: &str, ip: &str) -> String {
    format!("Timestamp     A/R  Flags  IF  Hostname  Address  TTL\n19:09:34.153  Add  40000002  13  {}  {}  120\n", host, ip)
}

/// The Fold on the LAN: browse, lookup and address answers.
pub fn fold_network() -> MockSystem {
    MockSystem::new()
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
        )
        .spawn_output(&["dns-sd", "-G", "v4", "Android_43W5CGQ4.local."], ADDR)
}
