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

//! `bazel run //tools/claude-cli-pin:update -- [--check] [--version x.y.z] [--offline <dir>]`

use claude_cli_pin::{
    fetch_registry, offline_fetcher, parse_pin, plan, render_pin, resolve, Plan, PIN_REL,
};
use std::path::{Path, PathBuf};
use std::process::ExitCode;

const USAGE: &str =
    "usage: bazel run //tools/claude-cli-pin:update -- [--check] [--version x.y.z] [--offline <dir>]";

fn main() -> ExitCode {
    match run() {
        Ok(code) => code,
        Err(e) => {
            eprintln!("error: {e}");
            ExitCode::from(2)
        }
    }
}

fn run() -> Result<ExitCode, String> {
    let mut check = false;
    let mut version: Option<String> = None;
    let mut offline: Option<PathBuf> = None;
    let mut args = std::env::args().skip(1);
    while let Some(a) = args.next() {
        match a.as_str() {
            "--check" => check = true,
            "--version" => version = Some(args.next().ok_or(USAGE)?),
            "--offline" => offline = Some(PathBuf::from(args.next().ok_or(USAGE)?)),
            "-h" | "--help" => {
                println!("{USAGE}");
                return Ok(ExitCode::SUCCESS);
            }
            other => return Err(format!("unknown argument {other:?}\n{USAGE}")),
        }
    }
    let workspace = std::env::var("BUILD_WORKSPACE_DIRECTORY").map_err(|_| {
        "BUILD_WORKSPACE_DIRECTORY is not set; run via `bazel run //tools/claude-cli-pin:update`"
            .to_string()
    })?;
    let pin_path = Path::new(&workspace).join(PIN_REL);
    let text =
        std::fs::read_to_string(&pin_path).map_err(|e| format!("{}: {e}", pin_path.display()))?;
    let current = parse_pin(&text)?;

    let requested = version.as_deref().unwrap_or("latest");
    let offline_dir = offline.map(|d| Path::new(&workspace).join(d));
    let target = match &offline_dir {
        Some(dir) => resolve(&offline_fetcher(dir), requested)?,
        None => resolve(&fetch_registry, requested)?,
    };

    match plan(&current, &target, version.is_some())? {
        Plan::Current => {
            println!("Claude Code CLI pin is current at {}.", current.version);
            Ok(ExitCode::SUCCESS)
        }
        Plan::Update { from, to } if check => {
            println!("Claude Code CLI pin is out of date: {from} -> {to}.");
            Ok(ExitCode::from(1))
        }
        Plan::Update { from, to } => {
            let new = render_pin(&text, &target)?;
            // Write beside the pin and rename over it, so a crash never leaves
            // a half-written file.
            let tmp = pin_path.with_extension("bzl.tmp");
            std::fs::write(&tmp, new).map_err(|e| format!("{}: {e}", tmp.display()))?;
            std::fs::rename(&tmp, &pin_path).map_err(|e| format!("{}: {e}", pin_path.display()))?;
            println!("Claude Code CLI pin: {from} -> {to} ({PIN_REL}).");
            Ok(ExitCode::SUCCESS)
        }
    }
}
