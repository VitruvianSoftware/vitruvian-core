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

//! Test-only: runs one of the port's functions the way the shell tests call
//! the script's, so they can hold the two to the same answers.
//!
//!   pipeline-status-rs-probe evaluate-runs-json '<json>'
//!       echoes what `evaluate_runs_json` echoes and exits with what it returns.

use std::io::Write;

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match args.first().map(String::as_str) {
        Some("evaluate-runs-json") => {
            let json = args.get(1).map(String::as_str).unwrap_or("");
            let e = pipeline_status::evaluate::evaluate_runs_json(json);
            let _ = std::io::stderr().write_all(e.stderr.as_bytes());
            let _ = std::io::stdout().write_all(e.stdout.as_bytes());
            let _ = std::io::stdout().flush();
            std::process::exit(e.status);
        }
        _ => {
            eprintln!("usage: pipeline-status-rs-probe evaluate-runs-json <json>");
            std::process::exit(64);
        }
    }
}
