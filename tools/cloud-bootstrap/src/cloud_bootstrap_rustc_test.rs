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

//! The crate builds with ONE plain `rustc` call and nothing else: no crates,
//! no Bazel-generated inputs. That is how a bare cloud VM builds it, before
//! Bazel exists (cloud-bootstrap is what installs Bazel), so adding a
//! dependency here would silently break session start. Type-checks the real
//! sources with the toolchain's own rustc (--emit=metadata: no linker needed).

use std::path::PathBuf;
use std::process::Command;

fn runfile(var: &str) -> PathBuf {
    let rel = std::env::var_os(var).unwrap_or_else(|| panic!("{var} is not set"));
    std::env::current_dir().unwrap().join(rel)
}

#[test]
fn builds_with_one_plain_rustc_call() {
    let out = std::env::var_os("TEST_TMPDIR")
        .map(PathBuf::from)
        .unwrap_or_else(std::env::temp_dir)
        .join("cloud-bootstrap.rmeta");
    let o = Command::new(runfile("RUSTC"))
        .args([
            "--edition",
            "2021",
            "--crate-type",
            "bin",
            "--emit=metadata",
            "-o",
        ])
        .arg(&out)
        .arg(runfile("MAIN_RS"))
        .output()
        .expect("rustc runs");
    assert!(
        o.status.success(),
        "plain rustc could not build src/cloud_bootstrap/main.rs on its own:\n{}",
        String::from_utf8_lossy(&o.stderr)
    );
}
