// Copyright (c) 2026 VitruvianSoftware
//
// SPDX-License-Identifier: MIT
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

//! The design-sync tools (`:prepare`, `:inject-reference-fonts`) and the
//! Rust port of `tools/test-mcp-slack-e2e.sh`.

pub mod inject_reference_fonts;
pub mod mcp_slack_e2e;
pub mod prepare;

use std::path::PathBuf;

/// The repo's `.design-sync/` directory, which both tools work on.
///
/// `bazel run` starts the binary in its runfiles tree, so the checkout comes
/// from `BUILD_WORKSPACE_DIRECTORY`. A binary started directly (outside
/// Bazel) finds it from the working directory or one of its parents.
pub fn design_sync_dir() -> PathBuf {
    if let Some(ws) = std::env::var_os("BUILD_WORKSPACE_DIRECTORY").filter(|v| !v.is_empty()) {
        return PathBuf::from(ws).join(".design-sync");
    }
    let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
    cwd.ancestors()
        .map(|d| d.join(".design-sync"))
        .find(|d| d.is_dir())
        .unwrap_or_else(|| cwd.join(".design-sync"))
}
