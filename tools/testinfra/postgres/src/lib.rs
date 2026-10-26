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

//! run-postgres.sh and check-postgres.sh in Rust.
//!
//! Both scripts are a few lines of `set -euo pipefail` bash. The port keeps
//! what a caller can see: the same child processes with the same arguments
//! and environment, the same exit status, and bash's own wording (with the
//! script's line numbers) when an argument is missing or a program cannot be
//! started. Where bash 3.2 and bash 5 disagree (the exit status of a program
//! that is not there), this follows bash 5, the Linux CI shell.

use std::io::{self, Write};
use std::os::unix::process::{CommandExt, ExitStatusExt};
use std::process::{Command, ExitStatus, Stdio};

/// The text strerror(3) gives for an I/O error, without Rust's
/// " (os error N)" suffix.
pub fn strerror(err: &io::Error) -> String {
    let text = err.to_string();
    match text.rfind(" (os error ") {
        Some(i) => text[..i].to_string(),
        None => text,
    }
}

/// `set -u` on a missing positional parameter.
fn unbound(argv0: &str, line: u32, n: usize) -> i32 {
    eprintln_flush(&format!("{argv0}: line {line}: ${n}: unbound variable"));
    1
}

fn eprintln_flush(msg: &str) {
    let mut err = io::stderr().lock();
    let _ = writeln!(err, "{msg}");
    let _ = err.flush();
}

/// The exit status bash reports for a finished child.
pub fn status_code(status: ExitStatus) -> i32 {
    match status.code() {
        Some(code) => code,
        None => 128 + status.signal().unwrap_or(0),
    }
}

/// bash's report, and exit status, for a simple command that could not start.
pub fn start_failure(argv0: &str, line: u32, program: &str, err: &io::Error) -> (String, i32) {
    match err.kind() {
        io::ErrorKind::NotFound if program.contains('/') => (
            format!("{argv0}: line {line}: {program}: No such file or directory"),
            127,
        ),
        io::ErrorKind::NotFound => (
            format!("{argv0}: line {line}: {program}: command not found"),
            127,
        ),
        io::ErrorKind::PermissionDenied => (
            format!("{argv0}: line {line}: {program}: Permission denied"),
            126,
        ),
        _ => (
            format!("{argv0}: line {line}: {program}: {}", strerror(err)),
            126,
        ),
    }
}

/// bash's report, and exit status, for an `exec` that failed.
pub fn exec_failure(argv0: &str, line: u32, program: &str, err: &io::Error) -> (String, i32) {
    match err.kind() {
        io::ErrorKind::NotFound if program.contains('/') => (
            format!("{argv0}: line {line}: {program}: No such file or directory"),
            127,
        ),
        io::ErrorKind::NotFound => (
            format!("{argv0}: line {line}: exec: {program}: not found"),
            127,
        ),
        io::ErrorKind::PermissionDenied => (
            format!("{argv0}: line {line}: {program}: Permission denied"),
            126,
        ),
        _ => (
            format!(
                "{argv0}: line {line}: exec: {program}: cannot execute: {}",
                strerror(err)
            ),
            126,
        ),
    }
}

/// Replaces this process with `cmd`, as `exec` does; returns only on failure.
fn exec(argv0: &str, line: u32, program: &str, cmd: &mut Command) -> i32 {
    let err = cmd.exec();
    let (msg, code) = exec_failure(argv0, line, program, &err);
    eprintln_flush(&msg);
    code
}

/// The arguments run-postgres.sh hands postgres after initdb.
pub fn postgres_args(datadir: &str, port: &str) -> Vec<String> {
    [
        "-D",
        datadir,
        "-p",
        port,
        "-c",
        "listen_addresses=127.0.0.1",
        "-c",
        "unix_socket_directories=",
        "-c",
        "fsync=off",
        "-c",
        "synchronous_commit=off",
        "-c",
        "full_page_writes=off",
    ]
    .iter()
    .map(|s| s.to_string())
    .collect()
}

/// The arguments run-postgres.sh hands initdb.
pub fn initdb_args(datadir: &str) -> Vec<String> {
    vec![
        format!("--pgdata={datadir}"),
        "--username=postgres".to_string(),
        "--auth=trust".to_string(),
        "--no-sync".to_string(),
    ]
}

/// The arguments check-postgres.sh hands pg_isready.
pub fn isready_args(port: &str) -> Vec<String> {
    ["-h", "127.0.0.1", "-p", port, "-U", "postgres"]
        .iter()
        .map(|s| s.to_string())
        .collect()
}

/// usage: run-postgres <initdb> <postgres> <port> <tmpdir>
///
/// initdb into <tmpdir>/pgdata, then exec postgres on 127.0.0.1:<port>, TCP
/// only, with the durability knobs off. Returns only when something failed.
pub fn run_postgres(argv0: &str, args: &[String]) -> i32 {
    // INITDB="$1" ... TMP="$4", lines 24-27 of run-postgres.sh.
    for n in 1..=4 {
        if args.len() < n {
            return unbound(argv0, 23 + n as u32, n);
        }
    }
    let (initdb, postgres, port, tmp) = (&args[0], &args[1], &args[2], &args[3]);

    // macOS: anything that goes multithreaded before fork (locale lookups)
    // crashes the postmaster with "postmaster became multithreaded during
    // startup". `export LC_ALL=C LANG=C`.
    let datadir = format!("{tmp}/pgdata");
    let status = Command::new(initdb)
        .args(initdb_args(&datadir))
        .env("LC_ALL", "C")
        .env("LANG", "C")
        .stdout(Stdio::null())
        .status();
    match status {
        Ok(s) if s.success() => {}
        Ok(s) => return status_code(s),
        Err(err) => {
            let (msg, code) = start_failure(argv0, 34, initdb, &err);
            eprintln_flush(&msg);
            return code;
        }
    }

    let mut cmd = Command::new(postgres);
    cmd.args(postgres_args(&datadir, port))
        .env("LC_ALL", "C")
        .env("LANG", "C");
    exec(argv0, 38, postgres, &mut cmd)
}

/// usage: check-postgres <pg_isready> <port>
///
/// exec pg_isready against 127.0.0.1:<port> as the postgres user.
pub fn check_postgres(argv0: &str, args: &[String]) -> i32 {
    // `exec "$1" ... "$2" ...` on line 24 expands $1 before $2.
    for n in 1..=2 {
        if args.len() < n {
            return unbound(argv0, 24, n);
        }
    }
    let mut cmd = Command::new(&args[0]);
    cmd.args(isready_args(&args[1]));
    exec(argv0, 24, &args[0], &mut cmd)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn postgres_gets_loopback_tcp_only_and_no_durability() {
        assert_eq!(
            postgres_args("/t/pgdata", "5433").join(" "),
            "-D /t/pgdata -p 5433 -c listen_addresses=127.0.0.1 -c unix_socket_directories= \
             -c fsync=off -c synchronous_commit=off -c full_page_writes=off"
        );
    }

    #[test]
    fn initdb_gets_trust_auth_into_the_data_dir() {
        assert_eq!(
            initdb_args("/t/pgdata"),
            vec![
                "--pgdata=/t/pgdata",
                "--username=postgres",
                "--auth=trust",
                "--no-sync"
            ]
        );
    }

    #[test]
    fn isready_targets_loopback() {
        assert_eq!(isready_args("1").join(" "), "-h 127.0.0.1 -p 1 -U postgres");
    }

    #[test]
    fn missing_arguments_are_reported_in_order() {
        assert_eq!(run_postgres("p", &[]), 1);
        assert_eq!(run_postgres("p", &["a".into(), "b".into(), "c".into()]), 1);
        assert_eq!(check_postgres("p", &["a".into()]), 1);
    }

    #[test]
    fn start_failures_read_like_bash() {
        let nf = io::Error::from(io::ErrorKind::NotFound);
        assert_eq!(
            start_failure("s", 34, "/x/initdb", &nf),
            (
                "s: line 34: /x/initdb: No such file or directory".to_string(),
                127
            )
        );
        assert_eq!(
            start_failure("s", 34, "initdb", &nf),
            ("s: line 34: initdb: command not found".to_string(), 127)
        );
        assert_eq!(
            exec_failure("s", 38, "pg", &nf),
            ("s: line 38: exec: pg: not found".to_string(), 127)
        );
        let pd = io::Error::from_raw_os_error(13);
        assert_eq!(
            exec_failure("s", 38, "/x/pg", &pd),
            ("s: line 38: /x/pg: Permission denied".to_string(), 126)
        );
        assert_eq!(
            strerror(&io::Error::from_raw_os_error(2)),
            "No such file or directory"
        );
    }

    #[test]
    fn initdb_failure_status_is_passed_on() {
        let args: Vec<String> = ["/usr/bin/false", "/nonexistent", "1", "/tmp"]
            .iter()
            .map(|s| s.to_string())
            .collect();
        assert_eq!(run_postgres("p", &args), 1);
    }
}
