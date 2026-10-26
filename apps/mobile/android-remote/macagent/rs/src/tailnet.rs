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

//! Tailnet interface watcher and CGNAT (`100.64.0.0/10`) IPv4 discovery.

use std::process::Command;
use std::sync::{Arc, Mutex};

pub trait Closer: Send + Sync {
    fn close(&self);
}

pub use Closer as TailnetListener;

pub struct TailnetWatcher {
    port: String,
    lookup: Box<dyn Fn() -> Option<String> + Send + Sync>,
    listen: Box<dyn Fn(&str) -> Result<Arc<dyn Closer>, String> + Send + Sync>,
    serve: Box<dyn Fn(Arc<dyn Closer>) + Send + Sync>,
    state: Mutex<WatcherState>,
}

#[derive(Default)]
struct WatcherState {
    ip: String,
    ln: Option<Arc<dyn Closer>>,
}

impl TailnetWatcher {
    pub fn new(
        port: impl Into<String>,
        lookup: impl Fn() -> Option<String> + Send + Sync + 'static,
        listen: impl Fn(&str) -> Result<Arc<dyn Closer>, String> + Send + Sync + 'static,
        serve: impl Fn(Arc<dyn Closer>) + Send + Sync + 'static,
    ) -> Self {
        Self {
            port: port.into(),
            lookup: Box::new(lookup),
            listen: Box::new(listen),
            serve: Box::new(serve),
            state: Mutex::new(WatcherState::default()),
        }
    }

    pub fn current(&self) -> String {
        self.state.lock().map(|s| s.ip.clone()).unwrap_or_default()
    }

    pub fn tick(&self) {
        let want = (self.lookup)().unwrap_or_default();
        let current_ip = self.current();
        if want == current_ip {
            return;
        }
        if let Ok(mut st) = self.state.lock() {
            if let Some(old) = st.ln.take() {
                old.close();
            }
            st.ip.clear();
        }
        if want.is_empty() {
            return;
        }
        let addr = format!("{}:{}", want, self.port);
        if let Ok(ln) = (self.listen)(&addr) {
            if let Ok(mut st) = self.state.lock() {
                st.ip = want;
                st.ln = Some(Arc::clone(&ln));
            }
            (self.serve)(ln);
        }
    }

    pub fn run(&self, cancel: crate::http_util::CancelToken, interval: std::time::Duration) {
        while !cancel.is_cancelled() {
            self.tick();
            if cancel.wait_timeout(interval) {
                break;
            }
        }
        if let Ok(mut st) = self.state.lock() {
            if let Some(old) = st.ln.take() {
                old.close();
            }
            st.ip.clear();
        }
    }
}

/// Finds the first IPv4 address in the Tailscale CGNAT range (`100.64.0.0/10`: `100.64.0.0` .. `100.127.255.255`).
pub fn tailscale_ipv4() -> Option<String> {
    let out = Command::new("ifconfig").output().ok()?;
    let text = String::from_utf8_lossy(&out.stdout);
    parse_tailscale_ipv4_from_ifconfig(&text)
}

pub fn parse_tailscale_ipv4_from_ifconfig(out: &str) -> Option<String> {
    for line in out.lines() {
        let trimmed = line.trim();
        if let Some(rest) = trimmed.strip_prefix("inet ") {
            let ip = rest.split_whitespace().next().unwrap_or("");
            if is_cgnat_ipv4(ip) {
                return Some(ip.to_string());
            }
        }
    }
    None
}

pub fn is_cgnat_ipv4(ip: &str) -> bool {
    let parts: Vec<&str> = ip.split('.').collect();
    if parts.len() != 4 {
        return false;
    }
    let Ok(o0) = parts[0].parse::<u8>() else {
        return false;
    };
    let Ok(o1) = parts[1].parse::<u8>() else {
        return false;
    };
    let Ok(_o2) = parts[2].parse::<u8>() else {
        return false;
    };
    let Ok(_o3) = parts[3].parse::<u8>() else {
        return false;
    };
    o0 == 100 && (64..=127).contains(&o1)
}

#[cfg(test)]
mod tests {
    use super::*;

    struct FakeListener {
        addr: String,
        closed: Mutex<bool>,
    }

    impl FakeListener {
        fn new(addr: &str) -> Self {
            Self {
                addr: addr.to_string(),
                closed: Mutex::new(false),
            }
        }

        fn is_closed(&self) -> bool {
            *self.closed.lock().unwrap()
        }
    }

    impl Closer for FakeListener {
        fn close(&self) {
            *self.closed.lock().unwrap() = true;
        }
    }

    struct TailnetHarness {
        watcher: TailnetWatcher,
        ip: Arc<Mutex<String>>,
        failing: Arc<Mutex<Option<String>>>,
        opened: Arc<Mutex<Vec<Arc<FakeListener>>>>,
    }

    impl TailnetHarness {
        fn new() -> Self {
            let ip = Arc::new(Mutex::new(String::new()));
            let failing: Arc<Mutex<Option<String>>> = Arc::new(Mutex::new(None));
            let opened: Arc<Mutex<Vec<Arc<FakeListener>>>> = Arc::new(Mutex::new(Vec::new()));

            let ip_c = Arc::clone(&ip);
            let failing_c = Arc::clone(&failing);
            let opened_c = Arc::clone(&opened);

            let watcher = TailnetWatcher::new(
                "7411",
                move || {
                    let s = ip_c.lock().unwrap().clone();
                    if s.is_empty() {
                        None
                    } else {
                        Some(s)
                    }
                },
                move |a| {
                    if let Some(err) = failing_c.lock().unwrap().clone() {
                        return Err(err);
                    }
                    let l = Arc::new(FakeListener::new(a));
                    opened_c.lock().unwrap().push(Arc::clone(&l));
                    Ok(l)
                },
                move |_| {},
            );

            Self {
                watcher,
                ip,
                failing,
                opened,
            }
        }

        fn set_ip(&self, val: &str) {
            *self.ip.lock().unwrap() = val.to_string();
        }

        fn set_failing(&self, err: Option<&str>) {
            *self.failing.lock().unwrap() = err.map(|s| s.to_string());
        }

        fn opened(&self) -> Vec<Arc<FakeListener>> {
            self.opened.lock().unwrap().clone()
        }
    }

    #[test]
    fn test_tailnet_listener_starts_when_tailscale_comes_up_later() {
        let h = TailnetHarness::new();
        h.watcher.tick();
        assert_eq!(h.watcher.current(), "");
        assert_eq!(h.opened().len(), 0);

        h.set_ip("100.124.228.116");
        h.watcher.tick();
        assert_eq!(h.watcher.current(), "100.124.228.116");
        let opened = h.opened();
        assert_eq!(opened.len(), 1);
        assert_eq!(opened[0].addr, "100.124.228.116:7411");

        // Steady state opens nothing more.
        h.watcher.tick();
        h.watcher.tick();
        assert_eq!(h.opened().len(), 1);
    }

    #[test]
    fn test_tailnet_listener_follows_address_changes_and_loss() {
        let h = TailnetHarness::new();
        h.set_ip("100.64.0.1");
        h.watcher.tick();
        h.set_ip("100.64.0.2");
        h.watcher.tick();
        let opened = h.opened();
        assert!(opened[0].is_closed());
        assert_eq!(h.watcher.current(), "100.64.0.2");

        h.set_ip("");
        h.watcher.tick();
        let opened = h.opened();
        assert!(opened[1].is_closed());
        assert_eq!(h.watcher.current(), "");
    }

    #[test]
    fn test_tailnet_listener_retries_after_a_bind_failure() {
        let h = TailnetHarness::new();
        h.set_ip("100.64.0.1");
        h.set_failing(Some("can't assign requested address"));
        h.watcher.tick();
        h.watcher.tick();
        assert_eq!(h.watcher.current(), "");

        h.set_failing(None);
        h.watcher.tick();
        assert_eq!(h.watcher.current(), "100.64.0.1");
        assert_eq!(h.opened().len(), 1);
    }
}
