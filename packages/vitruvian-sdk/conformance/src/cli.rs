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

//! Command-line argument parsing and orchestration for the seven protocol checks.

use std::env;
use std::fs;
use std::io::{self, Write};
use std::path::{Component, Path, PathBuf};

use crate::json::{self, Value};
use crate::protocol::Failure;
use crate::session::{an_older_app, Link, Run, TempDir, Transport};

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Options {
    pub folder: String,
    pub via: Option<String>,
    pub expect_refusal: bool,
}

const HELP_TEXT: &str = "\
usage: conformance [-h] [--via VIA] [--expect-refusal] folder

Check a tool against the Vitruvian tool protocol, versions 1 and 2.

positional arguments:
  folder            the tool's folder, which holds vitruvian-tool.json

options:
  -h, --help        show this help message and exit
  --via VIA         start the tool's program through this program
  --expect-refusal  fail unless the refusals check refused something
";

pub enum ParseOutcome {
    Options(Options),
    Help(String),
    Error(String),
}

pub fn parse_args(args: &[String]) -> ParseOutcome {
    let mut folder: Option<String> = None;
    let mut via: Option<String> = None;
    let mut expect_refusal = false;
    let mut positional_only = false;
    let mut i = 0;

    while i < args.len() {
        let arg = &args[i];
        if !positional_only {
            if arg == "--" {
                positional_only = true;
                i += 1;
                continue;
            }
            if arg == "-h" || arg == "--help" {
                return ParseOutcome::Help(HELP_TEXT.to_string());
            }
            if arg == "--expect-refusal" {
                expect_refusal = true;
                i += 1;
                continue;
            }
            if arg == "--via" {
                if i + 1 >= args.len() {
                    return ParseOutcome::Error(
                        "conformance: error: argument --via: expected one argument\n".into(),
                    );
                }
                via = Some(args[i + 1].clone());
                i += 2;
                continue;
            }
            if let Some(val) = arg.strip_prefix("--via=") {
                via = Some(val.to_string());
                i += 1;
                continue;
            }
            if arg.starts_with('-') && arg.len() > 1 {
                return ParseOutcome::Error(format!(
                    "conformance: error: unrecognized arguments: {}\n",
                    arg
                ));
            }
        }
        if folder.is_none() {
            folder = Some(arg.clone());
        } else {
            return ParseOutcome::Error(format!(
                "conformance: error: unrecognized arguments: {}\n",
                arg
            ));
        }
        i += 1;
    }

    match folder {
        Some(f) => ParseOutcome::Options(Options {
            folder: f,
            via,
            expect_refusal,
        }),
        None => ParseOutcome::Error(
            "conformance: error: the following arguments are required: folder\n".into(),
        ),
    }
}

/// Lexical `os.path.abspath(os.path.join(BUILD_WORKING_DIRECTORY, folder))`.
pub fn resolve_folder(folder: &str) -> PathBuf {
    let bwd = env::var("BUILD_WORKING_DIRECTORY").unwrap_or_default();
    let joined = if bwd.is_empty() {
        PathBuf::from(folder)
    } else {
        Path::new(&bwd).join(folder)
    };
    let abs = if joined.is_absolute() {
        joined
    } else {
        env::current_dir()
            .unwrap_or_else(|_| PathBuf::from("."))
            .join(joined)
    };
    normalize_lexical(&abs)
}

fn normalize_lexical(path: &Path) -> PathBuf {
    let mut out = PathBuf::new();
    for comp in path.components() {
        match comp {
            Component::CurDir => {}
            Component::ParentDir => {
                out.pop();
            }
            other => out.push(other.as_os_str()),
        }
    }
    out
}

/// Runs the seven conformance checks against `folder`, writing the formatted
/// report lines to `out`, and returns the exit code (`0` if all checks pass,
/// `1` otherwise).
pub fn check_to<W: Write>(
    folder: &Path,
    via: Option<&str>,
    expect_refusal: bool,
    out: &mut W,
) -> io::Result<i32> {
    let manifest_path = folder.join("vitruvian-tool.json");
    let manifest_text = fs::read_to_string(&manifest_path)?;
    let manifest: Value =
        json::loads(&manifest_text).map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
    let exec_rel = manifest
        .get("runtime")
        .and_then(|r| r.get("exec"))
        .and_then(|e| e.as_str())
        .ok_or_else(|| {
            io::Error::new(
                io::ErrorKind::InvalidData,
                "missing runtime.exec in manifest",
            )
        })?;
    let program = folder.join(exec_rel).to_string_lossy().into_owned();
    let command: Vec<String> = match via {
        Some(v) => vec![v.to_string(), program],
        None => vec![program],
    };

    let mut passed = true;
    let temp = TempDir::new("vitruvian-conformance-")?;
    let data_folder = temp.path().to_string_lossy().into_owned();
    let link = Link::spawn(&command, temp.path())?;
    let mut run = Run::new(
        link,
        &manifest,
        data_folder,
        Run::<Link>::default_features(),
    );

    let check_names = [
        "handshake",
        "a command",
        "unknown",
        "a panel",
        "refusals",
        "shutdown",
        "an older app",
    ];

    for name in check_names {
        if !passed {
            writeln!(out, "skipped  {}", name)?;
            continue;
        }
        let res: Result<String, Failure> = match name {
            "handshake" => run.handshake(),
            "a command" => run.a_command(),
            "unknown" => run.unknown(),
            "a panel" => run.a_panel(),
            "refusals" => run.refusals(),
            "shutdown" => run.shutdown(),
            "an older app" => an_older_app(&command, &manifest),
            _ => unreachable!(),
        };
        match res {
            Ok(msg) => {
                writeln!(out, "ok       {}: {}", name, msg)?;
            }
            Err(failure) => {
                passed = false;
                writeln!(out, "NOT OK   {}: {}", name, failure)?;
            }
        }
    }

    if passed && expect_refusal && run.refused == 0 {
        passed = false;
        writeln!(
            out,
            "NOT OK   refusals: nothing was refused, and --expect-refusal was given"
        )?;
    }

    run.link.close();
    Ok(if passed { 0 } else { 1 })
}

/// Convenience entrypoint matching `conformance.py` for a tool folder with default options.
pub fn check(folder: &Path) -> i32 {
    let mut stdout = io::stdout();
    check_to(folder, None, false, &mut stdout).unwrap_or(1)
}

/// CLI entrypoint matching `conformance.main(arguments)`.
pub fn main_with_args(arguments: &[String]) -> i32 {
    let options = match parse_args(arguments) {
        ParseOutcome::Options(opts) => opts,
        ParseOutcome::Help(text) => {
            print!("{}", text);
            return 0;
        }
        ParseOutcome::Error(err) => {
            eprint!("{}", err);
            return 2;
        }
    };
    let folder = resolve_folder(&options.folder);
    let mut stdout = io::stdout();
    match check_to(
        &folder,
        options.via.as_deref(),
        options.expect_refusal,
        &mut stdout,
    ) {
        Ok(code) => code,
        Err(err) => {
            eprintln!("conformance: {}", err);
            1
        }
    }
}
