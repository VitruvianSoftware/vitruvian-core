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

//! appset-render: see lib.rs.

fn main() {
    use std::os::unix::ffi::OsStringExt;
    let argv: Vec<Vec<u8>> = std::env::args_os().map(|a| a.into_vec()).collect();
    // Go grows goroutine stacks to 1 GB; the parser recurses once per nested
    // action or parenthesis, so give it room to match.
    let code = std::thread::Builder::new()
        .stack_size(1 << 30)
        .spawn(move || appset_render::run(&argv, &mut std::io::stdout(), &mut std::io::stderr()))
        .expect("spawn parser thread")
        .join()
        .unwrap_or(2);
    std::process::exit(code);
}
