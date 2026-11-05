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

//! `bazel run //tools/agent-roster -- [--check|--write]` (see lib.rs).

use std::path::Path;

fn main() {
    let workspace = match std::env::var("BUILD_WORKSPACE_DIRECTORY") {
        Ok(dir) if !dir.trim().is_empty() => dir,
        _ => {
            eprintln!(
                "error: BUILD_WORKSPACE_DIRECTORY is not set; run via `bazel run //tools/agent-roster -- [--check|--write]`"
            );
            std::process::exit(1);
        }
    };

    let default_mode = match option_env!("AGENT_ROSTER_DEFAULT_MODE") {
        Some("write") => agent_roster::Mode::Write,
        _ => agent_roster::Mode::Check,
    };

    let args: Vec<String> = std::env::args().skip(1).collect();
    let mode = match args.as_slice() {
        [] => default_mode,
        [flag] if flag == "--check" => agent_roster::Mode::Check,
        [flag] if flag == "--write" => agent_roster::Mode::Write,
        _ => {
            eprintln!("usage: agent-roster [--check|--write]");
            std::process::exit(1);
        }
    };

    let code = agent_roster::run_in_workspace(Path::new(&workspace), mode);
    std::process::exit(code);
}
