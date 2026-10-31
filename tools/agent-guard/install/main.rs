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

//! agent-guard's per-user backstop installer.
//!
//!   bazel run //tools/agent-guard:install                   # install or update the backstop
//!   bazel run //tools/agent-guard:install -- --dry-run      # show exactly what would change
//!   bazel run //tools/agent-guard:install -- --check        # repo wiring, backstop, and the launcher answering
//!   bazel run //tools/agent-guard:install -- --uninstall    # remove the backstop (and any old copy)
//!
//! A port of the retired install.py, message for message, so its users and
//! tests saw no change at the cutover. See README.md for who may do what, and
//! why.
//!
//! Standard library only, like the guard: JSON through agent_guard::pyval
//! (Python's json semantics), plus small ports of the Python stdlib pieces
//! the installer used (argparse, difflib, shlex, json's indent writer and
//! error messages).

mod argparse;
mod difflib;
mod installer;
mod pyjson;
mod shlex;
mod sys;

#[cfg(test)]
mod install_test;
#[cfg(test)]
mod launcher_test;
#[cfg(test)]
mod testlib;

fn main() {
    let argv: Vec<String> = std::env::args_os()
        .skip(1)
        .map(|a| a.to_string_lossy().into_owned())
        .collect();
    let ctx = sys::Ctx::real();
    std::process::exit(installer::main(&ctx, &argv));
}
