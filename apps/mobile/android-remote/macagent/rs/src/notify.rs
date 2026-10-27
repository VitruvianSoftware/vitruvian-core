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

//! Outbound push notification client (ntfy publisher with per-key debounce).

use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;
use std::time::{Duration, Instant};

use crate::http_util::http_do;

pub const NOTIFY_DEBOUNCE: Duration = Duration::from_secs(60);
pub const NOTIFY_TIMEOUT: Duration = Duration::from_secs(5);
pub const ERR_NOTIFY_NOT_CONFIGURED: &str =
    "notifications are not configured (start the agent with --ntfy-url and --ntfy-topic)";
pub const ERR_NOTIFY_DISABLED: &str =
    "notifications are muted on the Mac (flip the switch in Settings to turn them back on)";

#[derive(Debug, Clone, Default)]
pub struct Notification {
    pub key: String,
    pub title: String,
    pub body: String,
    pub priority: String,
    pub tags: String,
    pub click: String,
}

#[derive(Clone)]
pub struct Notifier {
    url: String,
    topic: String,
    token: String,
    enabled: std::sync::Arc<AtomicBool>,
    sent: std::sync::Arc<Mutex<HashMap<String, Instant>>>,
}

impl Notifier {
    pub fn new(url: &str, topic: &str, token: &str) -> Self {
        Self {
            url: url.trim().trim_end_matches('/').to_string(),
            topic: topic.trim().trim_matches('/').to_string(),
            token: token.trim().to_string(),
            enabled: std::sync::Arc::new(AtomicBool::new(true)),
            sent: std::sync::Arc::new(Mutex::new(HashMap::new())),
        }
    }

    pub fn configured(&self) -> bool {
        !self.url.is_empty() && !self.topic.is_empty()
    }

    pub fn enabled(&self) -> bool {
        self.enabled.load(Ordering::SeqCst)
    }

    pub fn set_enabled(&self, on: bool) {
        self.enabled.store(on, Ordering::SeqCst);
    }

    pub fn topic(&self) -> &str {
        &self.topic
    }

    pub fn notify(
        &self,
        key: &str,
        title: &str,
        body: &str,
        priority: &str,
        tags: &str,
        click: &str,
    ) {
        let _ = self.send(&Notification {
            key: key.to_string(),
            title: title.to_string(),
            body: body.to_string(),
            priority: priority.to_string(),
            tags: tags.to_string(),
            click: click.to_string(),
        });
    }

    pub fn send(&self, n: &Notification) -> Result<(), String> {
        if !self.configured() || !self.enabled() {
            return Ok(());
        }
        if !n.key.is_empty() {
            if let Ok(mut guard) = self.sent.lock() {
                let now = Instant::now();
                if let Some(last) = guard.get(&n.key) {
                    if now.duration_since(*last) < NOTIFY_DEBOUNCE {
                        return Ok(());
                    }
                }
                guard.insert(n.key.clone(), now);
            }
        }
        self.publish(n)
    }

    pub fn send_test(&self, hostname: &str) -> Result<(), String> {
        if !self.configured() {
            return Err(
                "notifications are not configured (start the agent with --ntfy-url and --ntfy-topic)"
                    .to_string(),
            );
        }
        self.publish(&Notification {
            title: format!("Vitruvian Remote · {}", hostname),
            body: "Test notification from the Mac agent.".to_string(),
            priority: "default".to_string(),
            tags: "laptop".to_string(),
            ..Default::default()
        })
    }

    fn publish(&self, n: &Notification) -> Result<(), String> {
        let target = format!("{}/{}", self.url, self.topic);
        let mut headers: Vec<(&str, String)> = Vec::new();
        if !n.title.is_empty() {
            headers.push(("Title", n.title.clone()));
        }
        if !n.priority.is_empty() {
            headers.push(("Priority", n.priority.clone()));
        }
        if !n.tags.is_empty() {
            headers.push(("Tags", n.tags.clone()));
        }
        if !n.click.is_empty() {
            headers.push(("Click", n.click.clone()));
        }
        if !self.token.is_empty() {
            headers.push(("Authorization", format!("Bearer {}", self.token)));
        }
        let borrowed: Vec<(&str, &str)> = headers.iter().map(|(k, v)| (*k, v.as_str())).collect();
        let resp = http_do(
            "POST",
            &target,
            &borrowed,
            n.body.as_bytes(),
            Some(NOTIFY_TIMEOUT),
        )
        .map_err(|e| format!("ntfy: {}", e))?;
        if resp.status >= 300 {
            return Err(format!("ntfy: HTTP {}", resp.status));
        }
        Ok(())
    }

    #[cfg(test)]
    pub fn clear_debounce_for_test(&self, key: &str, age: Duration) {
        if let Ok(mut guard) = self.sent.lock() {
            if let Some(inst) = Instant::now().checked_sub(age) {
                guard.insert(key.to_string(), inst);
            } else {
                guard.remove(key);
            }
        }
    }
}

#[cfg(test)]
pub mod tests {
    use super::*;
    use crate::http_util::{HttpRequest, HttpResponse, TestServer};
    use std::sync::Arc;

    #[derive(Clone, Default)]
    pub struct FakeNtfyPost {
        pub path: String,
        pub headers: Vec<(String, String)>,
        pub body: String,
    }

    impl FakeNtfyPost {
        pub fn header(&self, name: &str) -> &str {
            self.headers
                .iter()
                .find(|(k, _)| k.eq_ignore_ascii_case(name))
                .map(|(_, v)| v.as_str())
                .unwrap_or("")
        }
    }

    #[derive(Clone, Default)]
    pub struct FakeNtfy {
        posts: Arc<Mutex<Vec<FakeNtfyPost>>>,
    }

    impl FakeNtfy {
        pub fn new() -> Self {
            Self::default()
        }

        pub fn start_server(&self) -> TestServer {
            let posts = Arc::clone(&self.posts);
            TestServer::start(move |req: &HttpRequest| {
                posts.lock().unwrap().push(FakeNtfyPost {
                    path: req.path.clone(),
                    headers: req.headers.clone(),
                    body: req.body_str(),
                });
                HttpResponse::new(200, b"ok".to_vec())
            })
        }

        pub fn count(&self) -> usize {
            self.posts.lock().unwrap().len()
        }

        pub fn last(&self) -> FakeNtfyPost {
            self.posts
                .lock()
                .unwrap()
                .last()
                .cloned()
                .unwrap_or_default()
        }
    }

    #[test]
    fn test_notifier_sends_headers_and_body() {
        let f = FakeNtfy::new();
        let srv = f.start_server();
        let n = Notifier::new(&srv.url, "my-topic", "tk_secret");
        n.send(&Notification {
            key: "k1".to_string(),
            title: "Claude Code may be waiting".to_string(),
            body: "vitruvian-core · Bash".to_string(),
            priority: "high".to_string(),
            tags: "hourglass".to_string(),
            click: "https://github.com/example/pr/1".to_string(),
        })
        .expect("send notification");

        assert_eq!(f.count(), 1);
        let p = f.last();
        assert_eq!(p.path, "/my-topic");
        assert_eq!(p.body, "vitruvian-core · Bash");
        assert_eq!(p.header("Title"), "Claude Code may be waiting");
        assert_eq!(p.header("Priority"), "high");
        assert_eq!(p.header("Authorization"), "Bearer tk_secret");
        assert_eq!(p.header("Click"), "https://github.com/example/pr/1");
    }

    #[test]
    fn test_notifier_debounces_per_key() {
        let f = FakeNtfy::new();
        let srv = f.start_server();
        let n = Notifier::new(&srv.url, "t", "");

        n.send(&Notification {
            key: "same".to_string(),
            title: "first".to_string(),
            body: "1".to_string(),
            ..Default::default()
        })
        .unwrap();
        n.send(&Notification {
            key: "same".to_string(),
            title: "second".to_string(),
            body: "2".to_string(),
            ..Default::default()
        })
        .unwrap();
        n.send(&Notification {
            key: "other".to_string(),
            title: "third".to_string(),
            body: "3".to_string(),
            ..Default::default()
        })
        .unwrap();

        assert_eq!(f.count(), 2, "want 2 sends (same debounced, other allowed)");

        // Once the window passes, the same key may fire again.
        n.clear_debounce_for_test("same", Duration::from_secs(120));
        n.send(&Notification {
            key: "same".to_string(),
            title: "fourth".to_string(),
            body: "4".to_string(),
            ..Default::default()
        })
        .unwrap();
        assert_eq!(f.count(), 3);
    }

    #[test]
    fn test_unconfigured_notifier_is_a_no_op() {
        let n = Notifier::new("", "", "");
        assert!(!n.configured());
        assert!(n
            .send(&Notification {
                key: "x".to_string(),
                title: "y".to_string(),
                ..Default::default()
            })
            .is_ok());
        assert!(
            n.send_test("atlas").is_err(),
            "SendTest on an unconfigured notifier must tell the caller so"
        );
    }
}
