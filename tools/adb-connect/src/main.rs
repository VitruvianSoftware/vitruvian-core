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

//! `adb_connect_rs`: the Rust build of `bazel run //tools/adb-connect`.
//! Same flags, output and exit codes as adb_connect.py; see lib.rs.

use adb_connect_lib::py::PyExc;
use adb_connect_lib::system::{stdout_tty_columns, RealSystem};
use adb_connect_lib::{app, cli, default_config_path, Tool};
use std::panic;

fn main() {
    let mut raw = std::env::args_os();
    let argv0 = raw
        .next()
        .map(|a| a.to_string_lossy().into_owned())
        .unwrap_or_default();
    let prog = argv0.rsplit('/').next().unwrap_or_default().to_string();
    let argv: Vec<String> = raw.map(|a| a.to_string_lossy().into_owned()).collect();

    let columns = cli::terminal_columns(
        std::env::var("COLUMNS").ok().as_deref(),
        stdout_tty_columns(),
    );
    #[allow(deprecated)] // home_dir is exactly expanduser's HOME-then-passwd lookup.
    let home = std::env::home_dir().map(|h| h.to_string_lossy().into_owned());

    // A Python exception the original would not catch ends the run with a
    // traceback-style message and status 1; anything else is a real bug.
    let default_hook = panic::take_hook();
    panic::set_hook(Box::new(move |info| {
        if info.payload().downcast_ref::<PyExc>().is_none() {
            default_hook(info);
        }
    }));

    let sys = RealSystem::from_env();
    let tool = Tool::new(
        &sys,
        default_config_path(home),
        Box::new(std::io::stdout()),
        Box::new(std::io::stderr()),
    );
    let outcome = panic::catch_unwind(panic::AssertUnwindSafe(|| {
        app::run(&tool, &prog, &argv, columns)
    }));
    tool.flush();
    match outcome {
        Ok(code) => std::process::exit(code),
        Err(payload) => match payload.downcast_ref::<PyExc>() {
            Some(exc) => {
                if exc.msg.is_empty() {
                    eprintln!(
                        "Traceback (most recent call last):\n  File \"{}\", in main\n{}",
                        prog, exc.kind
                    );
                } else {
                    eprintln!(
                        "Traceback (most recent call last):\n  File \"{}\", in main\n{}: {}",
                        prog, exc.kind, exc.msg
                    );
                }
                std::process::exit(1);
            }
            None => panic::resume_unwind(payload),
        },
    }
}
