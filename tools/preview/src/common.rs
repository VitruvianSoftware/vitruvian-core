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

//! The bash behaviours the three preview scripts share and the ports have to
//! reproduce: `$0`, `set -u` on a missing option value, `echo "$var" |`,
//! running a command whose stdout is captured or discarded, and a two-stage
//! pipeline under `pipefail`.

use shell_compat::{cat, err, spawn_diag, spawn_failure_status, status_code};
use std::io::Write;
use std::process::{Command, Stdio};

/// `$0`.
pub fn prog() -> Vec<u8> {
    use std::os::unix::ffi::OsStringExt;
    std::env::args_os()
        .next()
        .map(|a| a.into_vec())
        .unwrap_or_default()
}

/// `$(basename "$0")`.
pub fn prog_name() -> Vec<u8> {
    shell_compat::basename(&prog())
}

/// `X="$2"` under `set -u` with no `$2`: bash's message, status 1.
pub fn unbound(line: u32) -> i32 {
    err(&cat(&[
        &prog(),
        format!(": line {}: $2: unbound variable\n", line).as_bytes(),
    ]));
    1
}

/// What `echo "$v"` writes: the value and a newline -- or, for a value bash's
/// echo takes as its own options (`-n`, `-e`, `-neE`, ...), nothing but the
/// newline `-n` leaves out.
pub fn echo(v: &[u8]) -> Vec<u8> {
    if v.len() >= 2 && v[0] == b'-' && v[1..].iter().all(|c| b"neE".contains(c)) {
        return if v.contains(&b'n') {
            Vec::new()
        } else {
            b"\n".to_vec()
        };
    }
    let mut o = v.to_vec();
    o.push(b'\n');
    o
}

/// The shell's spelling of `cmd args...` as one diagnostic name.
fn start(line: u32, cmd: &mut Command) -> Result<std::process::Child, i32> {
    cmd.spawn().map_err(|e| {
        err(&spawn_diag(line, cmd, &e));
        spawn_failure_status(&e)
    })
}

/// `cmd` with its stdout captured, stderr passed through: (status, stdout).
pub fn captured(line: u32, cmd: &mut Command) -> (i32, Vec<u8>) {
    let r = shell_compat::capture_stdout(line, cmd);
    (r.status, r.stdout)
}

/// `cmd >/dev/null` (stderr passed through): the status.
pub fn discarded(line: u32, cmd: &mut Command) -> i32 {
    cmd.stdout(Stdio::null());
    shell_compat::status(line, cmd, false)
}

/// `cmd` with stdout and stderr inherited: the status.
pub fn inherited(line: u32, cmd: &mut Command) -> i32 {
    shell_compat::status(line, cmd, false)
}

/// `left | right` under `pipefail`, right's stdout inherited: the status of
/// the last stage that failed, 0 when both succeeded.
pub fn pipeline(line: u32, left: &mut Command, right: &mut Command) -> i32 {
    left.stdout(Stdio::piped());
    let mut l = match start(line, left) {
        Ok(c) => Some(c),
        Err(st) => {
            // The right side still runs, reading an empty pipe.
            right.stdin(Stdio::null());
            let rs = match start(line, right) {
                Ok(mut c) => c.wait().map(status_code).unwrap_or(1),
                Err(s) => s,
            };
            return if rs != 0 { rs } else { st };
        }
    };
    let lout = l
        .as_mut()
        .and_then(|c| c.stdout.take())
        .expect("piped stdout");
    right.stdin(Stdio::from(lout));
    let rs = match start(line, right) {
        Ok(mut c) => c.wait().map(status_code).unwrap_or(1),
        Err(s) => s,
    };
    let ls = l
        .take()
        .map(|mut c| c.wait().map(status_code).unwrap_or(1))
        .unwrap_or(0);
    if rs != 0 {
        rs
    } else {
        ls
    }
}

/// Write to stderr the way `log "..."` (`echo "$*" >&2`) does.
pub fn log(parts: &[&[u8]]) {
    let mut v = cat(parts);
    v.push(b'\n');
    let _ = std::io::stderr().lock().write_all(&v);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn echo_adds_a_newline_except_for_its_own_options() {
        assert_eq!(echo(b"{}"), b"{}\n");
        assert_eq!(echo(b""), b"\n");
        assert_eq!(echo(b"-n"), b"");
        assert_eq!(echo(b"-e"), b"\n");
        assert_eq!(echo(b"-x"), b"-x\n");
        assert_eq!(echo(b"-"), b"-\n");
    }

    #[test]
    fn pipeline_reports_the_failing_stage() {
        let st = pipeline(1, &mut Command::new("false"), &mut Command::new("cat"));
        assert_eq!(st, 1);
        let st = pipeline(1, &mut Command::new("true"), &mut Command::new("true"));
        assert_eq!(st, 0);
        let st = pipeline(
            1,
            Command::new("sh").args(["-c", "exit 3"]),
            Command::new("sh").args(["-c", "cat >/dev/null; exit 4"]),
        );
        assert_eq!(st, 4);
    }
}
