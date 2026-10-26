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

//! `bazel run //tools/pipeline-status:pipeline-mouse-daemon`

use pipeline_status::mouse_daemon::{self, DaemonConfig};
use pipeline_status::sh;

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let once = args.iter().any(|a| a == "--once")
        || std::env::var("MOUSE_DAEMON_ONCE")
            .ok()
            .map_or(false, |v| v == "1");
    let max_iterations = std::env::var("MAX_ITERATIONS")
        .ok()
        .and_then(|v| v.parse::<u64>().ok());

    let config = DaemonConfig {
        interval: sh::env_or("POLL_INTERVAL", "15").parse().unwrap_or(15),
        repo: sh::env_or("PIPELINE_REPO", "VitruvianSoftware/vitruvian-core"),
        branch: sh::env_or("PIPELINE_BRANCH", "main"),
        gravastar_bin: mouse_daemon::resolve_gravastar_bin(),
        once,
        max_iterations,
        pipeline_cmd: std::env::var("PIPELINE_CMD").ok().filter(|s| !s.is_empty()),
    };

    std::process::exit(mouse_daemon::run(&config));
}
