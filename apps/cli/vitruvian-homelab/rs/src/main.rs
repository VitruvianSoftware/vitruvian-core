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

use std::process::ExitCode;
use std::time::Duration;

use homelab_rs::cmd::RootCmd;

const VERSION: &str = "dev";
const COMMIT: &str = "none";
const DATE: &str = "unknown";

/// Fallback Sentry DSN for the `homelab` CLI when `SENTRY_DSN` is unset.
const DEFAULT_SENTRY_DSN: &str =
    "https://d28a9615550bccaa0c33eabe4c3f44ed@sentry-ingest.ipv1337.dev/17";

/// Maximum time dropping the Sentry guard may block on exit.
const SENTRY_SHUTDOWN_TIMEOUT: Duration = Duration::from_millis(500);

fn resolve_sentry_dsn() -> String {
    std::env::var("SENTRY_DSN")
        .ok()
        .unwrap_or_else(|| DEFAULT_SENTRY_DSN.to_string())
}

fn init_sentry(dsn: &str) -> sentry::ClientInitGuard {
    sentry::init((
        dsn,
        sentry::ClientOptions {
            release: sentry::release_name!(),
            shutdown_timeout: SENTRY_SHUTDOWN_TIMEOUT,
            ..Default::default()
        },
    ))
}

fn main() -> ExitCode {
    let _sentry_guard = init_sentry(&resolve_sentry_dsn());

    let root = RootCmd::new(VERSION, COMMIT, DATE);
    if let Err(err) = root.execute() {
        eprintln!("{}", err);
        return ExitCode::FAILURE;
    }
    ExitCode::SUCCESS
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_sentry_fail_open_unreachable_port() {
        let listener = std::net::TcpListener::bind("127.0.0.1:0").expect("bind ephemeral port");
        let port = listener.local_addr().expect("local addr").port();
        drop(listener);

        let dsn = format!("http://abc@127.0.0.1:{port}/1");
        let start = std::time::Instant::now();
        let guard = init_sentry(&dsn);
        sentry::capture_message("homelab fail-open test", sentry::Level::Info);
        drop(guard);

        assert!(
            start.elapsed() < Duration::from_secs(2),
            "sentry shutdown stalled: {:?}",
            start.elapsed()
        );
    }
}
