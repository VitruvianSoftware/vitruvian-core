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

//! Test-only: runs the port's `parse_checks_json` the way the shell test
//! calls the script's, so the same test can run against the binary.
//!
//!   watch-pr-rs-probe parse-checks-json '<json>'

use std::io::Write;

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match args.first().map(String::as_str) {
        Some("parse-checks-json") => {
            let json = args.get(1).map(String::as_str).unwrap_or("");
            let p = watch_pr::checks::parse_checks_json(json);
            let _ = std::io::stderr().write_all(p.stderr.as_bytes());
            let _ = std::io::stdout().write_all(p.stdout.as_bytes());
            let _ = std::io::stdout().flush();
            std::process::exit(p.status);
        }
        _ => {
            eprintln!("usage: watch-pr-rs-probe parse-checks-json <json>");
            std::process::exit(64);
        }
    }
}
