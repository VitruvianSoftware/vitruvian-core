// Copyright (c) 2026 VitruvianSoftware
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

//! The relay server: which devices are connected, how calls reach them, and
//! the HTTP side (MCP for AI apps, device registration, `/connect`).

pub mod config;
pub mod devices;
pub mod http;
pub mod legacy_devices;
pub mod mcp;
pub mod parked;
pub mod ratelimit;
pub mod registry;
pub mod store;
#[doc(hidden)]
pub mod store_contract;

use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

use serde_json::{json, Value};

/// Where log lines go: stdout in production, a buffer in tests. Lines are
/// JSON objects. Nothing that reaches a sink may carry call arguments, call
/// output or a token (spec §7.2).
pub type LogSink = Arc<dyn Fn(&str) + Send + Sync>;

pub fn stdout_log() -> LogSink {
    Arc::new(|line| println!("{line}"))
}

/// Writes one event with a millisecond timestamp.
pub fn log_event(sink: &LogSink, event: &str, fields: Value) {
    let ts = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0);
    let mut line = json!({"ts_ms": ts, "event": event});
    if let (Some(obj), Some(extra)) = (line.as_object_mut(), fields.as_object()) {
        for (k, v) in extra {
            obj.insert(k.clone(), v.clone());
        }
    }
    sink(&line.to_string());
}

/// `n` random bytes from the OS. Panics if the OS has no randomness to give,
/// which is not something the relay can run without.
pub fn random_bytes<const N: usize>() -> [u8; N] {
    use ring::rand::SecureRandom;
    let mut out = [0u8; N];
    ring::rand::SystemRandom::new()
        .fill(&mut out)
        .expect("the OS random source failed");
    out
}

/// Resolves when the server is told to stop: SIGTERM (what Kubernetes sends
/// on a rollout; as PID 1 nothing else would act on it) or Ctrl-C. The
/// SIGTERM handler is in place once this returns, so a signal sent after
/// it is never lost. Says which it was.
pub fn stop_signal() -> std::io::Result<impl std::future::Future<Output = &'static str>> {
    use tokio::signal::unix::{signal, SignalKind};
    let mut term = signal(SignalKind::terminate())?;
    Ok(async move {
        tokio::select! {
            _ = term.recv() => "SIGTERM",
            _ = tokio::signal::ctrl_c() => "SIGINT",
        }
    })
}

pub use vitruvian_relay_protocol::hex;

/// 128 random bits as 32 hex characters: session ids and call ids.
pub fn random_id() -> String {
    hex(&random_bytes::<16>())
}

/// A random (version 4) UUID in its usual text form.
pub fn uuid_v4() -> String {
    let mut b = random_bytes::<16>();
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    let h = hex(&b);
    format!(
        "{}-{}-{}-{}-{}",
        &h[0..8],
        &h[8..12],
        &h[12..16],
        &h[16..20],
        &h[20..32]
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Final review M2: SIGTERM stops the server, not just Ctrl-C.
    #[tokio::test]
    async fn sigterm_is_a_stop() {
        let stop = stop_signal().unwrap();
        let status = std::process::Command::new("kill")
            .args(["-TERM", &std::process::id().to_string()])
            .status()
            .unwrap();
        assert!(status.success());
        let why = tokio::time::timeout(std::time::Duration::from_secs(10), stop)
            .await
            .expect("the stop signal resolved");
        assert_eq!(why, "SIGTERM");
    }

    #[test]
    fn ids_are_random_and_well_formed() {
        let (a, b) = (random_id(), random_id());
        assert_eq!(a.len(), 32);
        assert!(a.bytes().all(|c| c.is_ascii_hexdigit()));
        assert_ne!(a, b);

        let u = uuid_v4();
        let parts: Vec<&str> = u.split('-').collect();
        assert_eq!(
            parts.iter().map(|p| p.len()).collect::<Vec<_>>(),
            vec![8, 4, 4, 4, 12]
        );
        assert!(parts[2].starts_with('4'), "{u}");
        assert!("89ab".contains(&parts[3][..1]), "{u}");
        assert_ne!(u, uuid_v4());
    }
}
