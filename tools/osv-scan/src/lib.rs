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

//! osv-scan in Rust: tools/osv-scan/osv-scan.sh, ported step for step.
//!
//! Scans the repo's lockfiles with osv-scanner, refuses to report green on a
//! scan that covered nothing, crashed or mutated the checkout, retries only
//! transient resolver failures and falls back to `--no-resolve`, and on
//! findings blocks only what this change could have introduced. The script
//! is the reference: same messages, ANSI colours, streams and exit codes.
//! What the script did with jq, python3, comm, sort, cut, sed, awk and grep
//! is done here (so neither jq nor python3 needs to be installed); git,
//! tar and osv-scanner are still the real programs.
//!
//! Divergences, none of which a real run produces: bash's own diagnostics
//! (a failed `cd`, a non-integer OSV_MAX_ATTEMPTS / OSV_RETRY_DELAY, a fatal
//! arithmetic error) and Python tracebacks are worded differently; output
//! sorts and compares in byte order, as under the C locale; `grep -i` folds
//! ASCII only and never reports "Binary file matches"; see pyjson, jq and
//! pyval for the JSON edge cases.

pub mod jq;
pub mod pyjson;
pub mod pypath;
pub mod pyval;
pub mod scan;
pub mod text;

pub use scan::run;
