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

//! npm trusted publishing, set up and bootstrapped: setup.sh and bootstrap.sh
//! in Rust, with the same output, exit codes and npm calls.
//!
//! Each script reads package.json through `python3 -c`; `pyjson` reproduces
//! what those snippets print, and `sh` the bash semantics around them.
//!
//! Known divergences, none reachable with a well-formed manifest and the
//! supported environment:
//!   * a manifest that is not valid JSON (or not an object) is skipped as in
//!     the script, but stderr carries one line instead of Python's traceback;
//!     the same for a dependency field that is not an object (exit 1 in both);
//!   * bash's own diagnostics (a failed redirection to the terminal, a failed
//!     `cd`, "integer expression expected") have the same meaning and exit
//!     status but not bash's `script: line N:` prefix;
//!   * children inside setup's manifest loop read /dev/null rather than the
//!     loop's heredoc (no npm subcommand involved reads stdin);
//!   * OTP_WAIT_SECONDS / OTP_POLL_SECONDS must be integers (bash's
//!     arithmetic errors on anything else are not reproduced);
//!   * words of a `for x in $(...)` list are not pathname-expanded, and
//!     `type -aP npm` paths are split on blanks without globbing;
//!   * a `grep -q "$workflow"` pattern outside the plain BRE subset (brackets,
//!     groups, a leading `-`) is handed to the system grep, so it matches as
//!     the script's would; `.` matches a byte, as in the C locale;
//!   * a large (>64 KiB) npm output with an early match is not subject to the
//!     SIGPIPE-under-pipefail false negative the script's `printf | grep -q`
//!     can hit;
//!   * bootstrap's hand-off: see `bootstrap`.

pub mod bootstrap;
pub mod manifest;
pub mod pyjson;
pub mod setup;
pub mod sh;
