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

//! CLI entrypoint for `//tools/sentry:ci-token`.

use sentry_tools::ci_token::{execute, parse_args, preflight_out_path, USAGE};
use sentry_tools::http::{AuthHeader, CurlClient};
use std::path::PathBuf;
use std::process::ExitCode;

fn resolve_out_path(raw: &str) -> PathBuf {
    let p = PathBuf::from(raw);
    if p.is_absolute() {
        return p;
    }
    if let Ok(wd) = std::env::var("BUILD_WORKING_DIRECTORY") {
        if !wd.is_empty() {
            return PathBuf::from(wd).join(p);
        }
    }
    p
}

fn main() -> ExitCode {
    let argv: Vec<String> = std::env::args().skip(1).collect();
    let args = match parse_args(&argv) {
        Ok(a) => a,
        Err(e) => {
            eprintln!("ci-token: {e}\n\n{USAGE}");
            return ExitCode::from(2);
        }
    };
    if args.help {
        print!("{USAGE}");
        return ExitCode::SUCCESS;
    }

    let out_path = resolve_out_path(&args.out);
    if let Err(e) = preflight_out_path(&out_path, args.force) {
        eprintln!("ci-token: {e}");
        return ExitCode::from(1);
    }

    let raw_token = std::env::var("SENTRY_TOKEN").ok();
    let token = match sentry_tools::validate_token(raw_token.as_deref()) {
        Ok(t) => t,
        Err(e) => {
            eprintln!("ci-token: {e}");
            return ExitCode::from(1);
        }
    };

    let curl_bin = std::env::var("SENTRY_CURL_BIN").unwrap_or_else(|_| "curl".into());
    let mut client = match CurlClient::new(curl_bin, AuthHeader::Bearer(token.clone())) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("ci-token: {e}");
            return ExitCode::from(1);
        }
    };

    let code = execute(
        &args,
        &out_path,
        &token,
        &mut client,
        &mut std::io::stdout(),
        &mut std::io::stderr(),
    );
    drop(client);
    ExitCode::from(u8::try_from(code).unwrap_or(1))
}
