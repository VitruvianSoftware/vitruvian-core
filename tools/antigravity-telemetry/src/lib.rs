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

//! Antigravity & AGY OTLP telemetry: a native port of the Python tool in this
//! directory (`antigravity_telemetry.py`, `session_exporter.py`,
//! `telemetry_hook.py`, `telemetry_loader.py`, `otlp_builder.py`,
//! `http_client.py`), built on std alone.
//!
//! Output is meant to be interchangeable with the Python tool's: the same
//! OTLP JSON (key order, number formatting, gzip thresholds), the same state
//! file, the same stdout. `antigravity_telemetry_rs_parity_test.py` runs both
//! side by side against a mock collector to hold that.

pub mod cli;
pub mod gzip;
pub mod http_client;
pub mod json;
pub mod otlp_builder;
pub mod pyutil;
pub mod session_exporter;
pub mod sys;
pub mod telemetry_hook;
pub mod telemetry_loader;

/// Entry points, by the name a program is invoked as or its first argument.
pub const ENTRYPOINTS: [&str; 3] = ["session-exporter", "telemetry-hook", "telemetry-loader"];

fn entrypoint_for(name: &str) -> Option<&'static str> {
    let normalized = name.replace('_', "-");
    let normalized = normalized.trim_end_matches(".py");
    ENTRYPOINTS.iter().copied().find(|e| normalized == *e)
}

/// Dispatch a whole command line: `argv[0]` may name an entry point
/// (`telemetry-hook`), else the first argument may (`… telemetry-hook`),
/// else it is the `setup`/`status`/`emit`/`export` CLI.
pub fn run(argv: &[String]) -> i32 {
    let program = argv.first().map(|a| sys::basename(a)).unwrap_or_default();
    let rest = argv.get(1..).unwrap_or(&[]);
    let (entry, args) = match entrypoint_for(&program) {
        Some(e) => (Some(e), rest),
        None => match rest.first().and_then(|a| entrypoint_for(a)) {
            Some(e) => (Some(e), &rest[1..]),
            None => (None, rest),
        },
    };
    match entry {
        Some("session-exporter") => session_exporter::main(args),
        Some("telemetry-hook") => telemetry_hook::main(),
        Some("telemetry-loader") => telemetry_loader::main(),
        _ => cli::main(args),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn entrypoint_names() {
        assert_eq!(entrypoint_for("telemetry_hook.py"), Some("telemetry-hook"));
        assert_eq!(entrypoint_for("session-exporter"), Some("session-exporter"));
        assert_eq!(entrypoint_for("antigravity_telemetry_rs"), None);
        assert_eq!(entrypoint_for("status"), None);
    }
}
