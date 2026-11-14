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

//! The built bin/tool must run on every Mac the app runs on.
//!
//! catalog-bump reads each program's oldest macOS (LC_BUILD_VERSION minos)
//! and refuses a release whose program needs a newer macOS than the app's
//! LSMinimumSystemVersion. Left to its default, Bazel stamps the build
//! machine's own macOS as the minimum, which is how 0.1.1 and 0.1.2 were
//! refused (#4704, #4796). This runs the same reader on the same file before
//! a release is cut, so the refusal shows up here instead.

use std::path::PathBuf;

use catalog::macho;

fn runfile(var: &str) -> PathBuf {
    PathBuf::from(std::env::var(var).unwrap_or_else(|_| panic!("{var} must be set")))
}

/// The app's LSMinimumSystemVersion, read as catalog-bump reads it.
fn app_oldest() -> macho::Version {
    let info = runfile("APP_INFO_PATH");
    let root = info
        .to_str()
        .expect("utf-8 path")
        .strip_suffix(catalog::bump::APP_INFO)
        .expect("APP_INFO_PATH ends in the app's Info.plist path")
        .to_string();
    catalog::bump::app_oldest_macos(&root).expect("read LSMinimumSystemVersion")
}

#[test]
fn bin_tool_runs_on_the_apps_oldest_macos() {
    let oldest = app_oldest();
    let tool = runfile("TOOL_PATH");
    let data = std::fs::read(&tool).expect("read bin/tool");
    let slices = macho::macho_slices(&data)
        .expect("bin/tool is a readable Mach-O")
        .expect("bin/tool is a Mach-O");
    assert!(!slices.is_empty(), "bin/tool has no architectures");
    for (arch, needs) in slices {
        let needs = needs.unwrap_or_else(|| panic!("bin/tool ({arch}) names no oldest macOS"));
        assert!(
            needs <= oldest,
            "bin/tool ({arch}) needs macOS {}; the app runs on macOS {}, so catalog-bump would refuse it",
            macho::version_text(needs),
            macho::version_text(oldest),
        );
    }
}
