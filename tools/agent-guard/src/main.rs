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

//! agent_guard_rs: the hook (no arguments: payload on stdin), `--version`,
//! or `--batch` for the parity test.
//!
//!   echo '{"tool_name":"Bash","cwd":"'$PWD'","tool_input":{"command":"git push"}}' \
//!     | bazel run //tools/agent-guard:agent_guard_rs

use std::io::{Read, Write};

fn main() {
    // A guard bug is caught and logged, as agent_guard.py catches exceptions;
    // the default hook would print it into the agent's transcript.
    std::panic::set_hook(Box::new(|_| {}));
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.first().map(|a| a.as_str()) == Some("--batch") {
        std::process::exit(agent_guard::batch::run());
    }
    let mut input = Vec::new();
    let _ = std::io::stdin().read_to_end(&mut input);
    let out = agent_guard::hook::main(&args, &input);
    let _ = std::io::stdout().write_all(out.stdout.as_bytes());
    let _ = std::io::stderr().write_all(out.stderr.as_bytes());
    std::process::exit(out.code);
}
