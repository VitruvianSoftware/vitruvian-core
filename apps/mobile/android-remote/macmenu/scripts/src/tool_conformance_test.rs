// Copyright (c) 2026 VitruvianSoftware
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

//! Rust test runner for `//apps/mobile/android-remote/macmenu:tool_conformance_rs_test`.

use std::path::PathBuf;

fn resolve_env(key: &str) -> String {
    let raw = std::env::var(key).unwrap_or_else(|_| panic!("{key} not set"));
    let p = PathBuf::from(&raw);
    if p.exists() {
        return p.to_string_lossy().into_owned();
    }
    if let Ok(runfiles) = std::env::var("RUNFILES_DIR") {
        let resolved = PathBuf::from(&runfiles).join("_main").join(&raw);
        if resolved.exists() {
            return resolved.to_string_lossy().into_owned();
        }
    }
    if let Ok(srcdir) = std::env::var("TEST_SRCDIR") {
        let resolved = PathBuf::from(&srcdir).join("_main").join(&raw);
        if resolved.exists() {
            return resolved.to_string_lossy().into_owned();
        }
    }
    raw
}

#[test]
fn remote_tool_conformance_end_to_end() {
    let manifest_path = resolve_env("MANIFEST_PATH");
    let validate_bin = resolve_env("VALIDATE_BIN");
    let args = vec![
        "tool-conformance-rs".to_string(),
        manifest_path,
        validate_bin,
    ];
    let code = tool_conformance_lib::run(&args);
    assert_eq!(code, 0, "tool_conformance_lib::run exited with {code}");
}
