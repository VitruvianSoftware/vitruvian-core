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

//! adb-connect in Rust: zero-touch Android Wireless Debugging discovery,
//! pairing and connection, ported from `adb_connect.py` with the same
//! flags, output and exit codes.
//!
//! Module map, following the Python file top to bottom:
//!
//! * [`profiles`]: the built-in device catalog, `~/.config/vitruvian/adb-devices.json`
//!   overrides, and matching a device to a profile.
//! * [`mdns`]: `dns-sd` browse / lookup / address parsing.
//! * [`discovery`]: Tailscale peers, de-duplication, target selection and
//!   endpoint resolution.
//! * [`adb`]: `adb devices -l`, duplicate-transport detection, connect and pair.
//! * [`app`]: the command-line flow (`main()` in Python).
//! * [`cli`], [`py`], [`pyjson`], [`system`]: argparse, the Python value
//!   model, the `json` module and the operating-system boundary.

pub mod adb;
pub mod app;
pub mod cli;
pub mod discovery;
pub mod mdns;
pub mod profiles;
pub mod py;
pub mod pyjson;
pub mod system;

#[cfg(test)]
mod testutil;

use std::cell::RefCell;
use std::io::Write;
use system::System;

/// One run of the tool: the system it talks to, the stdout/stderr it
/// prints to, and the state the Python module keeps in globals.
pub struct Tool<'a> {
    pub sys: &'a dyn System,
    /// `_INSTANCE_SERVICE_HINTS`: instance name -> the mDNS service type
    /// it was last browsed under.
    pub hints: RefCell<py::Dict>,
    /// The user profile file `load_device_profiles()` reads by default.
    pub default_config_path: String,
    out: RefCell<Box<dyn Write + 'a>>,
    err: RefCell<Box<dyn Write + 'a>>,
}

impl<'a> Tool<'a> {
    pub fn new(
        sys: &'a dyn System,
        default_config_path: String,
        out: Box<dyn Write + 'a>,
        err: Box<dyn Write + 'a>,
    ) -> Self {
        Tool {
            sys,
            hints: RefCell::new(py::Dict::new()),
            default_config_path,
            out: RefCell::new(out),
            err: RefCell::new(err),
        }
    }

    /// `print(text)`.
    pub fn print(&self, text: &str) {
        let mut out = self.out.borrow_mut();
        let _ = writeln!(out, "{}", text);
    }

    /// `print(text, file=sys.stderr)`.
    pub fn eprint(&self, text: &str) {
        let mut err = self.err.borrow_mut();
        let _ = writeln!(err, "{}", text);
    }

    /// Write raw text to stdout (argparse's `--help`).
    pub fn write_out(&self, text: &str) {
        let _ = self.out.borrow_mut().write_all(text.as_bytes());
    }

    /// Write raw text to stderr (argparse's errors).
    pub fn write_err(&self, text: &str) {
        let _ = self.err.borrow_mut().write_all(text.as_bytes());
    }

    pub fn flush(&self) {
        let _ = self.out.borrow_mut().flush();
        let _ = self.err.borrow_mut().flush();
    }
}

/// `os.path.expanduser("~/.config/vitruvian/adb-devices.json")`.
pub fn default_config_path(home: Option<String>) -> String {
    let rest = "/.config/vitruvian/adb-devices.json";
    match home {
        Some(h) => {
            let joined = format!("{}{}", h.trim_end_matches('/'), rest);
            if joined.is_empty() {
                "/".into()
            } else {
                joined
            }
        }
        None => format!("~{}", rest),
    }
}
