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

//! permission_drift.py in Rust, standard library only: the same command
//! line, the same GitHub requests, the same report and exit codes. The
//! parity test (permission_drift_rs_parity_test.py) holds the two together.
//!
//! agent_app is agent-app.sh in Rust (the `:agent-app` binary), held to the
//! script by agent_app_rs_parity_test.py. It shares this library because a
//! package has one rust_library (//tools/lint-naming).

#[cfg(not(feature = "standalone_permission_drift"))]
pub mod agent_app;
pub mod argparse;
pub mod drift;
pub mod github;
pub mod http;
pub mod json;
pub mod pyerr;
pub mod pystr;

#[cfg(test)]
mod drift_test;

use std::io::{Read, Write};
use std::path::Path;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

use argparse::{Kind, Opt, Parser};
use drift::LoadFail;
use pyerr::Crash;

pub const DEFAULT_API: &str = "https://api.github.com";
const DESCRIPTION: &str =
    "Does each agent's GitHub App have exactly the permissions the code says?";

/// `os.path.join(a, b)`.
fn join(a: &str, b: &str) -> String {
    if b.starts_with('/') {
        b.to_string()
    } else if a.is_empty() || a.ends_with('/') {
        format!("{}{}", a, b)
    } else {
        format!("{}/{}", a, b)
    }
}

/// `_here()`: under `bazel run` the files to judge are the committed ones in
/// the workspace, not the runfiles copies. Otherwise the binary's runfiles,
/// or the directory it sits in, as the script uses its own directory.
fn here() -> String {
    if let Some(ws) = std::env::var_os("BUILD_WORKSPACE_DIRECTORY") {
        let ws = ws.to_string_lossy().into_owned();
        if !ws.is_empty() {
            return join(&join(&ws, "tools"), "agent-app");
        }
    }
    let exe = std::env::current_exe().unwrap_or_default();
    let mut runfiles = exe.clone().into_os_string();
    runfiles.push(".runfiles");
    let packaged = Path::new(&runfiles).join("_main/tools/agent-app");
    if packaged.join("agents.tsv").is_file() {
        return packaged.to_string_lossy().into_owned();
    }
    exe.parent()
        .map(|p| p.to_string_lossy().into_owned())
        .unwrap_or_else(|| ".".into())
}

/// Why there is no token: a ReadError (exit 2) or a crash.
#[derive(Debug)]
pub enum TokenFail {
    Read(String),
    Crash(Crash),
}

/// Python's text-mode decode of a child's output: UTF-8, universal newlines.
fn text(bytes: &[u8]) -> Result<String, Crash> {
    Ok(pyerr::decode_utf8(bytes)?
        .replace("\r\n", "\n")
        .replace('\r', "\n"))
}

/// `token()`: `(token, where it came from)`.
pub fn token() -> Result<(String, &'static str), TokenFail> {
    for name in ["GH_TOKEN", "GITHUB_TOKEN"] {
        if let Some(v) = std::env::var_os(name) {
            let v = v.to_string_lossy().into_owned();
            if !v.is_empty() {
                return Ok((v, name));
            }
        }
    }
    let failed =
        |m: String| TokenFail::Read(format!("no GH_TOKEN and `gh auth token` failed: {}", m));
    let mut child = Command::new("gh")
        .args(["auth", "token"])
        .stdin(Stdio::inherit())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| failed(pyerr::os_error_with_name(&e, "gh")))?;
    let mut out_pipe = child.stdout.take().unwrap();
    let mut err_pipe = child.stderr.take().unwrap();
    let out_reader = std::thread::spawn(move || {
        let mut b = Vec::new();
        let _ = out_pipe.read_to_end(&mut b);
        b
    });
    let err_reader = std::thread::spawn(move || {
        let mut b = Vec::new();
        let _ = err_pipe.read_to_end(&mut b);
        b
    });
    let deadline = Instant::now() + Duration::from_secs(30);
    let status = loop {
        match child.try_wait() {
            Ok(Some(s)) => break s,
            Ok(None) if Instant::now() >= deadline => {
                let _ = child.kill();
                let _ = child.wait();
                return Err(failed(
                    "Command '['gh', 'auth', 'token']' timed out after 30 seconds".into(),
                ));
            }
            Ok(None) => std::thread::sleep(Duration::from_millis(10)),
            Err(e) => return Err(failed(e.to_string())),
        }
    };
    let stdout = text(&out_reader.join().unwrap_or_default()).map_err(TokenFail::Crash)?;
    text(&err_reader.join().unwrap_or_default()).map_err(TokenFail::Crash)?;
    let tok = pystr::strip(&stdout);
    if !status.success() || tok.is_empty() {
        return Err(TokenFail::Read(
            "no GH_TOKEN and no gh login: run `gh auth login`".into(),
        ));
    }
    Ok((tok.to_string(), "your gh login"))
}

fn parser(prog: String) -> Parser {
    let opt = |s: &'static str, dest: &'static str| Opt {
        strings: vec![s],
        dest,
        kind: Kind::Value,
        help: None,
        required: false,
    };
    Parser {
        prog,
        description: Some(DESCRIPTION.into()),
        opts: vec![
            Opt::help(),
            opt("--agents", "agents"),
            opt("--permissions", "permissions"),
            opt("--org", "org"),
        ],
    }
}

fn prog_name(argv0: &str) -> String {
    match argv0.rfind('/') {
        Some(i) => argv0[i + 1..].to_string(),
        None => argv0.to_string(),
    }
}

fn crash(c: &Crash) -> i32 {
    let _ = std::io::stdout().flush();
    eprint!("{}", c.traceback());
    1
}

/// `main()`: the exit code, having printed what the script prints.
pub fn run(argv: &[String]) -> i32 {
    let here = here();
    let prog = prog_name(
        argv.first()
            .map(String::as_str)
            .unwrap_or("permission-drift"),
    );
    let p = parser(prog);
    let values = match p.parse(&argv[1.min(argv.len())..], &|_, _| Ok(())) {
        Ok(v) => v,
        Err(exit) => {
            print!("{}", exit.stdout);
            eprint!("{}", exit.stderr);
            return exit.code;
        }
    };
    let agents_path = values
        .value("agents")
        .map(String::from)
        .unwrap_or_else(|| join(&here, "agents.tsv"));
    let perms_path = values
        .value("permissions")
        .map(String::from)
        .unwrap_or_else(|| join(&here, "permissions.tsv"));
    let org = values.value("org").unwrap_or(drift::ORG).to_string();

    let loaded = drift::load_agents(&agents_path).and_then(|agents| {
        let declared = drift::load_declared(&perms_path, &agents)?;
        Ok((agents, declared))
    });
    let (agents, declared) = match loaded {
        Ok(x) => x,
        Err(LoadFail::File(m)) => {
            eprintln!("permission-drift: {}", m);
            return 2;
        }
        Err(LoadFail::Crash(c)) => return crash(&c),
    };
    let (tok, source) = match token() {
        Ok(t) => t,
        Err(TokenFail::Read(m)) => {
            eprintln!("permission-drift: NOT CHECKED: {}", m);
            return 2;
        }
        Err(TokenFail::Crash(c)) => return crash(&c),
    };
    println!("(reading GitHub as {})", source);
    let api = std::env::var_os("GITHUB_API_URL")
        .map(|v| v.to_string_lossy().into_owned())
        .unwrap_or_else(|| DEFAULT_API.to_string());
    let mut gh = github::GitHub::new(&tok, &api);
    match drift::check(&agents, &declared, &mut gh, &org) {
        Ok((code, lines)) => {
            println!("{}", lines.join("\n"));
            code
        }
        Err(c) => crash(&c),
    }
}
