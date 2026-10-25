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

//! registry-trust in Rust: which registry trusts which workflow, and proof
//! that a released version came from that workflow and not from a person.
//! A port of inventory.py, check.py and setup_publishers.py, which say why
//! each exists; this crate reads the same files, asks the same registries
//! and prints the same words, byte for byte, with the same exit codes.
//! registry_trust_rs_parity_test runs both on the same inputs and compares.
//!
//! Standard library only. What Python gave the scripts for free is here as
//! its own module: `json` and `tomllib` with their exact error messages
//! (the inventory prints them), and the corners of `str`, `os.path` and
//! `urllib.parse` that reach the output. HTTPS goes through `curl`.
//!
//! Where the port does not follow the scripts: a registry answer missing a
//! field the scripts index directly (a crash with a traceback, exit 1, in
//! Python) is a "did not answer in the expected shape" error here, exit 2,
//! like any other unreadable answer; and a name or version that is not a
//! string is shown as Python's str() would show it, but written to
//! `--json` as a string.

pub mod check;
pub mod cli;
pub mod http;
pub mod inventory;
pub mod json;
pub mod py;
pub mod setup_publishers;
pub mod toml;
