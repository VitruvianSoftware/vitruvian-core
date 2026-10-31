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

//! `bazel run //tools/ci:delivery_drift`: see lib.rs.

fn main() {
    // Find the engine in our runfiles first: the lookup may rely on a
    // relative argv[0] or runfiles path that the cwd change below would break.
    let engine = delivery_drift::default_engine();
    // `bazel run` starts us in the runfiles tree; act from the caller's
    // directory, as the script did.
    let rc = shell_compat::enter_bazel_run_cwd("delivery-drift");
    if rc != 0 {
        std::process::exit(rc);
    }
    std::process::exit(delivery_drift::run_with_engine(
        &shell_compat::args(),
        engine,
    ));
}
