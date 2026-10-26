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

//! package-desktop.sh in Rust: the release packager for the macOS desktop
//! apps (universal / arm64 / x86_64 DMGs, the universal ZIP, checksums, the
//! Homebrew Cask, the GitHub Release upload and its read-back, the tap and
//! the downloads catalog). See tools/desktop-package/README.md.
//!
//! helpers: the script's pure functions. shell: what the port borrows from
//! bash. driver: the options and the run.
//!
//! The script parses no JSON itself (`gh --jq` filters the release listing),
//! so neither does the port: it takes std only.

pub mod driver;
pub mod helpers;
pub mod shell;
