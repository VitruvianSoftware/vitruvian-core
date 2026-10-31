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

//! The bazel wrapper ("shim"), shim.go.
//!
//! The tests CI runs on a pull request are chosen in two places: the
//! planner (which presubmit units) and //tools/ci:affected_targets (which
//! targets build-test runs). Both call `bazel` themselves, so the verified
//! run runs them unchanged with a `bazel` first on PATH that is this binary.
//! For build and test it appends the flags that make the run remote-only,
//! and it logs, per invocation, the BuildBuddy link and Bazel's own count of
//! where each process ran. That log is the evidence the record is built
//! from.

use std::fs::OpenOptions;
use std::io::{self, BufRead, BufReader, Write};
use std::os::unix::fs::OpenOptionsExt;
use std::os::unix::process::CommandExt;
use std::process::{Command, Stdio};

use serde::Serialize;
use unitfile::gocompat::exec::{self, ExecError};
use unitfile::gocompat::json::{self, Dec, GoValue};
use unitfile::gocompat::oserr;
use unitfile::gocompat::quote::quote;

pub const ENV_REAL_BAZEL: &str = "VERIFIED_RUN_REAL_BAZEL";
pub const ENV_LOG: &str = "VERIFIED_RUN_LOG";
pub const ENV_STARTUP: &str = "VERIFIED_RUN_STARTUP";
pub const ENV_STRICT: &str = "VERIFIED_RUN_STRICT";
pub const ENV_LANE: &str = "VERIFIED_RUN_LANE";

/// One bazel build/test the shim saw, as logged.
#[derive(Clone, Debug, Default, PartialEq, Serialize)]
pub struct Invocation {
    pub lane: String,
    pub command: String,
    /// None is Go's nil slice (null in the log).
    pub targets: Option<Vec<String>>,
    pub exit: i64,
    pub url: String,
    pub processes: String,
    pub saw_summary: bool,
}

/// The commands that execute actions.
pub fn is_build_command(c: &str) -> bool {
    matches!(c, "build" | "test" | "coverage")
}

/// The BuildBuddy key headers CI's scripts pass; the key comes from
/// user.bazelrc instead.
fn is_key_header(a: &str) -> bool {
    a.starts_with("--remote_header=x-buildbuddy-api-key=")
        || a.starts_with("--bes_header=x-buildbuddy-api-key=")
}

/// Rewrites one bazel command line: startup options first; for build/test
/// the strict flags last (before a `--`, if any). Returns the arguments,
/// the command and its targets.
pub fn shim_args(
    args: &[String],
    startup: &[String],
    strict: &[String],
) -> (Vec<String>, String, Option<Vec<String>>) {
    let mut i = 0;
    while i < args.len() && args[i].starts_with('-') {
        i += 1;
    }
    let mut out: Vec<String> = startup.to_vec();
    out.extend_from_slice(&args[..i]);
    if i == args.len() {
        return (out, String::new(), None);
    }
    let command = args[i].clone();
    let rest = &args[i + 1..];
    if !is_build_command(&command) {
        out.push(command.clone());
        out.extend_from_slice(rest);
        return (out, command, None);
    }
    out.push(command.clone());
    let mut tail: Vec<String> = Vec::new();
    let mut targets: Option<Vec<String>> = None;
    let mut after_dashes = false;
    for a in rest {
        if after_dashes {
            tail.push(a.clone());
            targets.get_or_insert_with(Vec::new).push(a.clone());
        } else if a == "--" {
            after_dashes = true;
            tail.push(a.clone());
        } else if is_key_header(a) {
        } else if a.starts_with('-') {
            out.push(a.clone());
        } else {
            out.push(a.clone());
            targets.get_or_insert_with(Vec::new).push(a.clone());
        }
    }
    // A --config the caller already passed is not expanded a second time.
    let have: std::collections::HashSet<String> = out.iter().cloned().collect();
    for f in strict {
        if f.starts_with("--config=") && have.contains(f) {
            continue;
        }
        out.push(f.clone());
    }
    out.extend(tail);
    (out, command, targets)
}

fn is_re2_space(c: char) -> bool {
    matches!(c, '\t' | '\n' | '\x0c' | '\r' | ' ')
}

/// Removes `\x1b\[[0-9;?]*[A-Za-z]`.
fn strip_ansi(s: &str) -> String {
    let b = s.as_bytes();
    let mut out = Vec::with_capacity(b.len());
    let mut i = 0;
    while i < b.len() {
        if b[i] == 0x1b && i + 1 < b.len() && b[i + 1] == b'[' {
            let mut j = i + 2;
            while j < b.len() && (b[j].is_ascii_digit() || b[j] == b';' || b[j] == b'?') {
                j += 1;
            }
            if j < b.len() && b[j].is_ascii_alphabetic() {
                i = j + 1;
                continue;
            }
        }
        out.push(b[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

/// `Streaming build results to: (https://\S+)`, leftmost.
fn streaming_url(line: &str) -> Option<String> {
    const PRE: &str = "Streaming build results to: https://";
    let mut from = 0;
    while let Some(i) = line[from..].find(PRE) {
        let start = from + i + PRE.len() - "https://".len();
        let after = &line[from + i + PRE.len()..];
        let n = after.find(is_re2_space).unwrap_or(after.len());
        if n > 0 {
            return Some(line[start..from + i + PRE.len() + n].to_string());
        }
        from += i + 1;
    }
    None
}

/// Whether s matches `^\.?\s*$`.
fn dot_then_space(s: &str) -> bool {
    let s = s.strip_prefix('.').unwrap_or(s);
    s.chars().all(is_re2_space)
}

/// `INFO: \d+ process(?:es)?(?:: (.*?))?\.?\s*$`, leftmost-first: the
/// summary text, if the line is a process summary.
fn process_summary(line: &str) -> Option<String> {
    let mut from = 0;
    while let Some(i) = line[from..].find("INFO: ") {
        let at = from + i;
        let rest = &line[at + 6..];
        let digits = rest.bytes().take_while(|c| c.is_ascii_digit()).count();
        if digits > 0 {
            if let Some(after) = rest[digits..].strip_prefix(" process") {
                for es in [true, false] {
                    let p = if es {
                        match after.strip_prefix("es") {
                            Some(p) => p,
                            None => continue,
                        }
                    } else {
                        after
                    };
                    if let Some(body) = p.strip_prefix(": ") {
                        // The lazy group takes the least it can.
                        let k = body
                            .char_indices()
                            .map(|(k, _)| k)
                            .chain(std::iter::once(body.len()))
                            .find(|&k| dot_then_space(&body[k..]))
                            .unwrap_or(body.len());
                        return Some(body[..k].to_string());
                    }
                    if dot_then_space(p) {
                        return Some(String::new());
                    }
                }
            }
        }
        from = at + 1;
    }
    None
}

/// Picks the BuildBuddy link and the "N processes: ..." summary out of one
/// line of Bazel's output.
pub fn scan_line(line: &str, inv: &mut Invocation) {
    let line = strip_ansi(line.trim_end_matches('\r'));
    if let Some(u) = streaming_url(&line) {
        inv.url = u;
    }
    if let Some(p) = process_summary(&line) {
        inv.saw_summary = true;
        inv.processes = exec::go_trim(&p).to_string();
    }
}

fn split_env_list(v: &str) -> Vec<String> {
    if v.is_empty() {
        return Vec::new();
    }
    v.split('\n').map(String::from).collect()
}

fn run_status(c: &mut Command) -> Result<(), ExecError> {
    match c.status() {
        Ok(st) => {
            if st.success() {
                Ok(())
            } else if let Some(code) = st.code() {
                Err(ExecError::ExitCode(code))
            } else {
                use std::os::unix::process::ExitStatusExt;
                Err(ExecError::Signal {
                    sig: st.signal().unwrap_or(0),
                    core: st.core_dumped(),
                })
            }
        }
        Err(e) => Err(ExecError::Start(e.to_string())),
    }
}

/// What runs when a script calls `bazel`.
pub fn shim_main(args: &[String]) -> i32 {
    let real = std::env::var(ENV_REAL_BAZEL).unwrap_or_default();
    if real.is_empty() {
        exec::eprint("verified-run: the bazel wrapper was run without the real bazel's path\n");
        return 2;
    }
    let (out, command, targets) = shim_args(
        args,
        &split_env_list(&std::env::var(ENV_STARTUP).unwrap_or_default()),
        &split_env_list(&std::env::var(ENV_STRICT).unwrap_or_default()),
    );
    // exec.Command looks a bare name up on PATH; a miss fails the run with
    // exit code 1 and no message.
    let path = if real.contains('/') {
        Some(real.clone())
    } else {
        exec::look_path(&real).ok()
    };
    let build = is_build_command(&command);
    let mut inv = Invocation {
        lane: std::env::var(ENV_LANE).unwrap_or_default(),
        command,
        targets,
        ..Invocation::default()
    };
    let Some(path) = path else {
        if !build {
            return 1;
        }
        inv.exit = 1;
        return log_invocation(inv);
    };
    let mut c = Command::new(path);
    c.arg0(real.as_str())
        .args(&out)
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit());
    if !build {
        c.stderr(Stdio::inherit());
        return exec::exit_code(&run_status(&mut c));
    }
    c.stderr(Stdio::piped());
    let mut child = match c.spawn() {
        Ok(ch) => ch,
        Err(_) => {
            inv.exit = 1;
            return log_invocation(inv);
        }
    };
    if let Some(pipe) = child.stderr.take() {
        let mut r = BufReader::new(pipe);
        let mut buf = Vec::new();
        let stderr = io::stderr();
        loop {
            buf.clear();
            match r.read_until(b'\n', &mut buf) {
                Ok(0) | Err(_) => break,
                Ok(_) => {
                    if buf.last() == Some(&b'\n') {
                        buf.pop();
                    }
                    if buf.last() == Some(&b'\r') {
                        buf.pop();
                    }
                    let text = String::from_utf8_lossy(&buf).into_owned();
                    let mut e = stderr.lock();
                    let _ = e.write_all(&buf);
                    let _ = e.write_all(b"\n");
                    drop(e);
                    scan_line(&text, &mut inv);
                }
            }
        }
    }
    let r = match child.wait() {
        Ok(st) => {
            if st.success() {
                Ok(())
            } else if let Some(code) = st.code() {
                Err(ExecError::ExitCode(code))
            } else {
                Err(ExecError::Signal {
                    sig: 0,
                    core: false,
                })
            }
        }
        Err(e) => Err(ExecError::Start(e.to_string())),
    };
    inv.exit = exec::exit_code(&r) as i64;
    log_invocation(inv)
}

fn log_invocation(inv: Invocation) -> i32 {
    let path = std::env::var(ENV_LOG).unwrap_or_default();
    if !path.is_empty() {
        match OpenOptions::new()
            .append(true)
            .create(true)
            .mode(0o600)
            .open(&path)
        {
            Ok(mut f) => {
                let _ = f.write_all((json::marshal(&inv) + "\n").as_bytes());
            }
            Err(e) => {
                exec::eprint(&format!(
                    "verified-run: could not log this bazel run: {}\n",
                    oserr::path_err("open", &path, &e)
                ));
                if inv.exit == 0 {
                    return 1;
                }
            }
        }
    }
    inv.exit as i32
}

fn decode_invocation(v: &GoValue) -> Result<Invocation, String> {
    let mut inv = Invocation::default();
    let mut d = Dec::new();
    d.object(
        v,
        "invocation",
        "main.invocation",
        &[
            "lane",
            "command",
            "targets",
            "exit",
            "url",
            "processes",
            "saw_summary",
        ],
        |d, name, x| match name {
            "lane" => d.string(x, &mut inv.lane),
            "command" => d.string(x, &mut inv.command),
            "targets" => d.strings(x, &mut inv.targets),
            "exit" => d.int(x, &mut inv.exit),
            "url" => d.string(x, &mut inv.url),
            "processes" => d.string(x, &mut inv.processes),
            _ => d.bool(x, &mut inv.saw_summary),
        },
    );
    d.finish().map(|_| inv)
}

/// Reads the shim's log back: one JSON value after another, as
/// `json.Decoder` reads them. A missing log is no invocations.
pub fn read_invocations(p: &str) -> Result<Option<Vec<Invocation>>, String> {
    let data = match unitfile::read_file(p) {
        Ok(d) => d,
        Err((e, msg)) => {
            if oserr::is_not_exist(&e) {
                return Ok(None);
            }
            return Err(msg);
        }
    };
    let mut invs: Vec<Invocation> = Vec::new();
    let mut pos = 0;
    loop {
        while pos < data.len() && matches!(data[pos], b' ' | b'\t' | b'\r' | b'\n') {
            pos += 1;
        }
        if pos >= data.len() || data[pos] == b']' || data[pos] == b'}' {
            break;
        }
        let len =
            json::value_len(&data[pos..]).map_err(|e| format!("the run log is unreadable: {e}"))?;
        let v = json::parse(&data[pos..pos + len])
            .map_err(|e| format!("the run log is unreadable: {e}"))?;
        pos += len;
        invs.push(decode_invocation(&v).map_err(|e| format!("the run log is unreadable: {e}"))?);
    }
    Ok(if invs.is_empty() { None } else { Some(invs) })
}

/// The only places Bazel may report work happening for a run to count as
/// remote.
fn allowed_kind(k: &str) -> bool {
    matches!(
        k,
        "internal" | "remote" | "remote cache hit" | "action cache hit"
    )
}

fn lane_label(lane: &str) -> &str {
    if lane.is_empty() {
        "no lane"
    } else {
        lane
    }
}

/// Why one bazel run cannot count as a remote run, or Ok.
pub fn check_invocation(inv: &Invocation) -> Result<(), String> {
    let name = format!("bazel {} ({})", inv.command, lane_label(&inv.lane));
    if inv.exit != 0 && inv.exit != 4 {
        return Err(format!("{name} failed with exit code {}", inv.exit));
    }
    if inv.url.is_empty() {
        return Err(format!(
            "{name} has no BuildBuddy link, so there is no proof of where it ran"
        ));
    }
    if !inv.saw_summary {
        if inv.exit == 4 {
            return Ok(());
        }
        return Err(format!("{name} did not report where its work ran"));
    }
    if inv.processes.is_empty() {
        return Ok(());
    }
    for part in inv.processes.split(',') {
        let part = exec::go_trim(part);
        let Some((n, kind)) = part.split_once(' ') else {
            return Err(format!(
                "{name}: could not read {} in Bazel's process summary",
                quote(part)
            ));
        };
        if !allowed_kind(kind) {
            return Err(format!(
                "{name} ran {n} process(es) on this machine ({}), not on the remote machines",
                quote(kind)
            ));
        }
    }
    Ok(())
}
