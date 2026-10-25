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

//! The ephemeral-preview tools -- neon-branch, provision-preview and
//! pr-comment -- ported from their bash scripts in this directory. One
//! library; each binary in src/bin/ is a one-line entry point into it.
//!
//! Behaviour is the scripts', byte for byte: arguments, usage text, log
//! lines, the commands run (curl, gcloud, kubectl, gh) and their argv,
//! output, and exit codes, including the bash `set -euo pipefail` corners.
//! The jq the scripts pipe JSON through is [`jq`], over serde_json; the ports
//! need no jq on PATH.

pub mod common;
pub mod jq;
pub mod neon_branch;
pub mod pr_comment;
pub mod provision_preview;
