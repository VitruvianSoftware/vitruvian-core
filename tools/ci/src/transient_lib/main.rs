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

//! //tools/ci:transient-lib: the Rust port.

fn main() {
    let args = shell_compat::args();
    let path = match args.first() {
        Some(p) => p,
        None => {
            shell_compat::err(b"usage: transient-lib <output-file>\n");
            std::process::exit(2);
        }
    };
    let content = match std::fs::read(shell_compat::path(path)) {
        Ok(c) => c,
        Err(e) => {
            shell_compat::err(&shell_compat::cat(&[
                b"transient-lib: ",
                path,
                b": ",
                e.to_string().as_bytes(),
                b"\n",
            ]));
            std::process::exit(2);
        }
    };
    if transient_lib::is_transient_network_error(&content) {
        std::process::exit(0);
    } else {
        std::process::exit(1);
    }
}
