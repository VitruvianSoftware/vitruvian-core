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

//! sync: sync.py, as `bazel run //tools/sync-site-tools:sync` runs it.

use std::io::Write;
use std::os::unix::ffi::OsStrExt;

use sync_site_tools::pystr::PyStr;
use sync_site_tools::sync;

fn main() {
    let mut argv = std::env::args_os();
    let argv0 = argv.next().unwrap_or_default();
    let arguments: Vec<std::ffi::OsString> = argv.collect();
    // The program's own path stands in for sync.py's __file__: as given
    // when it has a slash (so a runfiles path is not resolved), else where
    // the system says it is.
    let program = if argv0.as_bytes().contains(&b'/') {
        PyStr::from_surrogateescape(argv0.as_bytes())
    } else {
        std::env::current_exe()
            .map(|p| PyStr::from_surrogateescape(p.as_os_str().as_bytes()))
            .unwrap_or_default()
    };
    let workspace = std::env::var_os("BUILD_WORKSPACE_DIRECTORY");
    let stdout = std::io::stdout();
    let stderr = std::io::stderr();
    let mut out = std::io::BufWriter::new(stdout.lock());
    let mut err = stderr.lock();
    let code = sync::run(&arguments, workspace, &program, &mut out, &mut err);
    let _ = out.flush();
    drop(out);
    let _ = err.flush();
    std::process::exit(code);
}
