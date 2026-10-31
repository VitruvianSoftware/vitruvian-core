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

//! queue-runner-routing — a workflow may name the homelab runner only through
//! one exact rule, so a pull request can never choose it.

use shell_compat::{basename, cat, contains, err, out};

const ROUTED: &[u8] = b"runs-on: ${{ (github.event_name == 'merge_group' || (github.event_name == 'push' && github.ref == 'refs/heads/main')) && vars.QUEUE_RUNNER == 'on' && vars.QUEUE_RUNNER_FALLBACK != 'on' && 'vitruvian-queue' || 'ubuntu-26.04' }}";

pub fn run(args: &[Vec<u8>]) -> i32 {
    if args.is_empty() {
        // The script's `${1:?usage: ...}`: message, status 1.
        err(b"queue-runner-routing: usage: queue-runner-routing <workflows-dir-or-files...>\n");
        return 1;
    }

    let mut files: Vec<Vec<u8>> = Vec::new();
    for a in args {
        if shell_compat::is_dir(a) {
            if let Ok(entries) = std::fs::read_dir(shell_compat::path(a)) {
                for entry in entries.flatten() {
                    let p = shell_compat::path_bytes(&entry.path());
                    if p.ends_with(b".yaml") {
                        files.push(p);
                    }
                }
            }
        } else {
            files.push(a.clone());
        }
    }
    files.sort();

    let mut fail = false;
    for f in &files {
        if basename(f) == b"queue-runner-watch.yaml" {
            continue;
        }
        let content = match std::fs::read(shell_compat::path(f)) {
            Ok(c) => c,
            Err(_) => continue,
        };
        for (n, line) in content.split(|&c| c == b'\n').enumerate() {
            let lineno = n + 1;
            let trimmed = &line[line
                .iter()
                .position(|c| !c.is_ascii_whitespace())
                .unwrap_or(line.len())..];
            if trimmed.starts_with(b"#") {
                continue;
            }
            if !contains(line, b"vitruvian-queue") && !contains(line, b"QUEUE_RUNNER") {
                continue;
            }
            let body = trimmed.strip_prefix(b"- ").unwrap_or(trimmed);
            if body != ROUTED {
                err(&cat(&[
                    b"queue-runner-routing: ",
                    f,
                    b":",
                    lineno.to_string().as_bytes(),
                    b" names the homelab runner outside the one allowed rule:\n",
                ]));
                err(&cat(&[b"    ", trimmed, b"\n"]));
                fail = true;
            }
        }
    }

    if fail {
        err(&cat(&[b"queue-runner-routing: allowed: ", ROUTED, b"\n"]));
        1
    } else {
        out(b"queue-runner-routing: ok\n");
        0
    }
}
