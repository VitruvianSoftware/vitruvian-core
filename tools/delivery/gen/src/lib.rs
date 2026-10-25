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

//! delivery-gen: render one .github/workflows/delivery-<app>.yaml per app
//! from the delivery() declarations in the Bazel graph (spec §4.3).
//!
//!     bazel run //tools/ci:gen
//!
//! The native port of main.go. The Go generator stays buildable as
//! //tools/delivery/gen:gen-go, and //tools/delivery/gen:gen_rs_parity_test
//! runs both over the real repository, every fixture, and every flag and
//! error case, requiring byte-identical workflows, stdout and stderr.
//!
//! DETERMINISM IS A HARD REQUIREMENT: tidy-check asserts `git diff
//! --exit-code` after a regenerate. Units are sorted by name, maps are
//! ordered (BTreeMap), and nothing time- or environment-dependent is emitted.

pub mod actionpins;
pub mod app;
pub mod gojson;
pub mod gostd;
pub mod render;
pub mod unit;

#[cfg(test)]
mod tests;
