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

//! `bazel run //tools/model-prices:update -- [--check] [--offline <file>] [--max-change <percent>]`

use model_prices::{
    execute_in_workspace, fetch_openrouter_json, parse_cli_args, sanitize_log_output,
    today_utc_ymd, CliParseResult,
};
use std::path::PathBuf;

fn main() {
    let workspace = match std::env::var("BUILD_WORKSPACE_DIRECTORY") {
        Ok(dir) if !dir.trim().is_empty() => PathBuf::from(dir),
        _ => {
            eprintln!(
                "error: BUILD_WORKSPACE_DIRECTORY is not set; run via `bazel run //tools/model-prices:update`"
            );
            std::process::exit(2);
        }
    };

    let caller_dir = std::env::var("BUILD_WORKING_DIRECTORY")
        .ok()
        .filter(|d| !d.trim().is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| workspace.clone());

    let opts = match parse_cli_args(std::env::args().skip(1), &caller_dir) {
        Ok(CliParseResult::Help(text)) => {
            println!("{text}");
            return;
        }
        Ok(CliParseResult::Run(opts)) => opts,
        Err(err) => {
            eprintln!("error: {}", sanitize_log_output(&err));
            std::process::exit(2);
        }
    };

    let outcome = execute_in_workspace(&workspace, &opts, &today_utc_ymd(), fetch_openrouter_json);
    if !outcome.stdout.is_empty() {
        print!("{}", sanitize_log_output(&outcome.stdout));
    }
    if !outcome.stderr.is_empty() {
        eprint!("{}", sanitize_log_output(&outcome.stderr));
    }
    std::process::exit(outcome.exit_code);
}
