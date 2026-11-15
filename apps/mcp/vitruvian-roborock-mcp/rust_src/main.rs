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
// SPDX-License-Identifier: MIT

//! `rrctl`: native Rust CLI entrypoint for `vitruvian-roborock-mcp`.

fn main() {
    let sentry_dsn = std::env::var("SENTRY_DSN").ok().or_else(|| {
        if std::env::var("SENTRY_ENABLED")
            .map(|v| v == "1" || v == "true")
            .unwrap_or(false)
        {
            Some(
                "https://9f49d950b8128850cffd06bce7bb04e3@sentry-ingest.ipv1337.dev/14".to_string(),
            )
        } else {
            None
        }
    });
    let _sentry_guard = sentry_dsn.filter(|s| !s.trim().is_empty()).map(|dsn| {
        sentry::init((
            dsn,
            sentry::ClientOptions {
                release: sentry::release_name!(),
                environment: Some(
                    std::env::var("NODE_ENV")
                        .or_else(|_| std::env::var("ENVIRONMENT"))
                        .unwrap_or_else(|_| "production".to_string())
                        .into(),
                ),
                ..Default::default()
            },
        ))
    });

    let args: Vec<String> = std::env::args().skip(1).collect();
    std::process::exit(vitruvian_roborock_mcp_rs_lib::cli::run(&args));
}
