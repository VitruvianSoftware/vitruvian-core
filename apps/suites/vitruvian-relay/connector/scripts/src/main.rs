// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

//! `bazel run //apps/suites/vitruvian-relay/connector/scripts:install [-- --unsigned] [-- --node /path/to/node]`
//! and `bazel run //apps/suites/vitruvian-relay/connector/scripts:uninstall`.
//! One source for both: the `uninstall` target sets `VRELAY_SCRIPT`.

use std::path::PathBuf;

use vitruvian_relay_connector::bridge::dc_home;
use vitruvian_relay_connector::Result;
use vrelay_install::{install, resolve_node, uninstall, Inputs, Install, Timing, Tools};

const SCRIPT: &str = match option_env!("VRELAY_SCRIPT") {
    Some(s) => s,
    None => "install",
};
const USAGE: &str = "usage: bazel run //apps/suites/vitruvian-relay/connector/scripts:install \
                     [-- [--unsigned] [--node /absolute/path/to/node]]";

/// The person running it, never root: a LaunchAgent is per user.
fn uid() -> Result<u32> {
    if !cfg!(target_os = "macos") {
        return Err("vrelay installs only on macOS".into());
    }
    // SAFETY: getuid cannot fail.
    let uid = unsafe { libc::getuid() };
    if uid == 0 {
        return Err("do not run this as root: vrelay is a per-user LaunchAgent".into());
    }
    Ok(uid)
}

fn run_install(args: &[String]) -> Result<()> {
    let mut unsigned = false;
    let mut node = None;
    let mut it = args.iter();
    while let Some(a) = it.next() {
        match a.as_str() {
            "--unsigned" => unsigned = true,
            "--node" => node = Some(PathBuf::from(it.next().ok_or(USAGE)?)),
            _ => return Err(USAGE.into()),
        }
    }
    let uid = uid()?;
    let home = dc_home(std::env::var_os("HOME"))?;
    let mut runfiles = Vec::new();
    if let Some(d) = std::env::var_os("RUNFILES_DIR") {
        runfiles.push(PathBuf::from(d));
    }
    if let Ok(exe) = std::env::current_exe() {
        let mut d = exe.into_os_string();
        d.push(".runfiles");
        runfiles.push(PathBuf::from(d));
    }
    let inputs = Inputs::from_runfiles(&runfiles)?;
    // Under `bazel run`, the checkout: a node from in there would not last.
    let workspace = std::env::var_os("BUILD_WORKSPACE_DIRECTORY").map(PathBuf::from);
    let path = std::env::var("PATH").ok();
    let node = resolve_node(node.as_deref(), path.as_deref(), workspace.as_deref())?;
    install(
        &Install {
            home,
            uid,
            inputs,
            tools: Tools::system(),
            node,
            unsigned,
            workspace,
            timing: Timing::default(),
        },
        &mut std::io::stdout(),
    )
}

fn run_uninstall(args: &[String]) -> Result<()> {
    if !args.is_empty() {
        return Err(
            "usage: bazel run //apps/suites/vitruvian-relay/connector/scripts:uninstall".into(),
        );
    }
    let uid = uid()?;
    let home = dc_home(std::env::var_os("HOME"))?;
    uninstall(&home, uid, &Tools::system(), &mut std::io::stdout())
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let result = match SCRIPT {
        "uninstall" => run_uninstall(&args),
        _ => run_install(&args),
    };
    if let Err(e) = result {
        eprintln!("vrelay {SCRIPT}: {e}");
        std::process::exit(1);
    }
}
