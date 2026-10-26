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

//! check-loopback.sh in Rust.
//!
//! Runs as the `test` of a rules_itest service_test once the named service is
//! healthy, and fails unless every socket LISTENing on the service's assigned
//! port is bound to 127.0.0.1 (see check-loopback.sh for why). The output,
//! exit status and the programs it runs (the port helper and, on macOS,
//! /usr/sbin/lsof) are the script's; the awk / sort / sed stages are done
//! here. Where bash 3.2 and bash 5 disagree, this follows bash 5.

use std::collections::BTreeSet;
use std::fs;
use std::io::{self, Write};
use std::os::unix::fs::PermissionsExt;
use std::os::unix::process::ExitStatusExt;
use std::path::Path;
use std::process::{Command, ExitStatus, Stdio};

const PROC_TCP: &str = "/proc/net/tcp";
const PROC_TCP6: &str = "/proc/net/tcp6";
const LSOF: &str = "/usr/sbin/lsof";

fn strerror(err: &io::Error) -> String {
    let text = err.to_string();
    match text.rfind(" (os error ") {
        Some(i) => text[..i].to_string(),
        None => text,
    }
}

fn status_code(status: ExitStatus) -> i32 {
    match status.code() {
        Some(code) => code,
        None => 128 + status.signal().unwrap_or(0),
    }
}

fn err_line(msg: &str) {
    let mut e = io::stderr().lock();
    let _ = writeln!(e, "{msg}");
    let _ = e.flush();
}

/// `$(...)`: stdout with every trailing newline removed.
fn strip_trailing_newlines(mut s: String) -> String {
    while s.ends_with('\n') {
        s.pop();
    }
    s
}

/// The value bash's printf takes for a %X argument: strtol with base 0
/// (0x.. hex, 0.. octal), leading blanks and a sign allowed. Err holds bash
/// 5's complaint ("invalid number", or "invalid octal number" for a leading
/// zero followed by something that is not octal).
pub fn printf_number(s: &str) -> Result<i64, &'static str> {
    let t = s.trim_start_matches([' ', '\t', '\n']);
    let (neg, t) = match t.as_bytes().first() {
        Some(b'-') => (true, &t[1..]),
        Some(b'+') => (false, &t[1..]),
        _ => (false, t),
    };
    let (radix, digits) = if t.len() > 2 && (t.starts_with("0x") || t.starts_with("0X")) {
        (16, &t[2..])
    } else if t.len() > 1 && t.starts_with('0') {
        (8, &t[1..])
    } else {
        (10, t)
    };
    if digits.is_empty() {
        return Err("invalid number");
    }
    let complaint = if radix == 8 && digits.bytes().all(|b| b.is_ascii_digit()) {
        "invalid octal number"
    } else {
        "invalid number"
    };
    let v = i64::from_str_radix(digits, radix).map_err(|_| complaint)?;
    Ok(if neg { -v } else { v })
}

/// `printf '%04X' n`.
pub fn hex4(n: i64) -> String {
    format!("{:04X}", n as u64)
}

/// The awk program over /proc/net/tcp{,6}: local_address of every row whose
/// port is `hex` and whose state is 0A (LISTEN), sorted and de-duplicated.
pub fn proc_listeners(tables: &str, hex: &str) -> Vec<String> {
    let suffix = format!(":{hex}");
    let set: BTreeSet<String> = tables
        .lines()
        .filter_map(|line| {
            let f: Vec<&str> = line.split_whitespace().collect();
            let local = *f.get(1)?;
            if local.ends_with(&suffix) && f.get(3).copied() == Some("0A") {
                Some(local.to_string())
            } else {
                None
            }
        })
        .collect();
    set.into_iter().collect()
}

/// `awk 'NR > 1 { print $(NF - 1) }' | sort -u` over lsof's table.
pub fn lsof_listeners(table: &str) -> Vec<String> {
    let set: BTreeSet<String> = table
        .lines()
        .skip(1)
        .map(|line| {
            let f: Vec<&str> = line.split_whitespace().collect();
            match f.len() {
                0 | 1 => line.to_string(),
                n => f[n - 2].to_string(),
            }
        })
        .collect();
    set.into_iter().collect()
}

/// The report when the listeners are not exactly the loopback one.
pub fn mismatch_report(label: &str, port: &str, listeners: &str) -> String {
    let body = if listeners.is_empty() {
        "  (none)"
    } else {
        listeners
    };
    let mut out = format!(
        "{label} must listen on 127.0.0.1:{port} only; sockets LISTENing on port {port}:\n"
    );
    for line in body.split('\n') {
        out.push_str("  ");
        out.push_str(line);
        out.push('\n');
    }
    out
}

fn is_executable(path: &str) -> bool {
    match fs::metadata(path) {
        Ok(m) => m.permissions().mode() & 0o111 != 0,
        Err(_) => false,
    }
}

fn readable(path: &str) -> bool {
    fs::File::open(path).is_ok()
}

fn env_nonempty(name: &str) -> Option<String> {
    std::env::var(name).ok().filter(|v| !v.is_empty())
}

/// check-loopback.sh. `argv0` stands where bash names the script in its own
/// error messages.
pub fn run(argv0: &str) -> i32 {
    let Some(label) = env_nonempty("ITEST_SERVICE_LABEL") else {
        err_line(&format!(
            "{argv0}: line 37: ITEST_SERVICE_LABEL: set to the itest service label to check"
        ));
        return 1;
    };
    let Some(helper) = env_nonempty("GET_ASSIGNED_PORT_BIN") else {
        err_line(&format!(
            "{argv0}: line 38: GET_ASSIGNED_PORT_BIN: not running under rules_itest svcinit"
        ));
        return 1;
    };
    let output = Command::new(&helper)
        .arg(&label)
        .stdin(Stdio::inherit())
        .stderr(Stdio::inherit())
        .output();
    let port = match output {
        Ok(o) if o.status.success() => {
            strip_trailing_newlines(String::from_utf8_lossy(&o.stdout).into_owned())
        }
        Ok(o) => return status_code(o.status),
        Err(err) => {
            let (msg, code) = match err.kind() {
                io::ErrorKind::NotFound if helper.contains('/') => {
                    (format!("{helper}: No such file or directory"), 127)
                }
                io::ErrorKind::NotFound => (format!("{helper}: command not found"), 127),
                io::ErrorKind::PermissionDenied => (format!("{helper}: Permission denied"), 126),
                _ => (format!("{helper}: {}", strerror(&err)), 126),
            };
            err_line(&format!("{argv0}: line 38: {msg}"));
            return code;
        }
    };
    if port.is_empty() {
        err_line(&format!("no assigned port for {label} in ASSIGNED_PORTS"));
        return 1;
    }

    let (listeners, want) = if readable(PROC_TCP) {
        // Linux. local_address is HEXIP:HEXPORT (0100007F is 127.0.0.1) and
        // st 0A is LISTEN. tcp6 is absent when the kernel has IPv6 off.
        let n = match printf_number(&port) {
            Ok(n) => n,
            Err(complaint) => {
                err_line(&format!("{argv0}: line 48: printf: {port}: {complaint}"));
                return 1;
            }
        };
        let hex = hex4(n);
        let mut tables = fs::read_to_string(PROC_TCP).unwrap_or_default();
        if !tables.is_empty() && !tables.ends_with('\n') {
            tables.push('\n');
        }
        tables.push_str(&fs::read_to_string(PROC_TCP6).unwrap_or_default());
        (
            proc_listeners(&tables, &hex).join("\n"),
            format!("0100007F:{hex}"),
        )
    } else if Path::new(LSOF).exists() && is_executable(LSOF) {
        // macOS. The NAME column is "addr:port", followed by "(LISTEN)".
        let out = Command::new(LSOF)
            .args(["-nP", &format!("-iTCP:{port}"), "-sTCP:LISTEN"])
            .stderr(Stdio::inherit())
            .output();
        match out {
            // pipefail: lsof finding nothing (status 1) ends the script.
            Ok(o) if !o.status.success() => return status_code(o.status),
            Ok(o) => (
                lsof_listeners(&String::from_utf8_lossy(&o.stdout)).join("\n"),
                format!("127.0.0.1:{port}"),
            ),
            Err(err) => {
                err_line(&format!("{argv0}: line 61: {LSOF}: {}", strerror(&err)));
                return 126;
            }
        }
    } else {
        err_line("cannot inspect listening sockets here: no /proc/net/tcp and no /usr/sbin/lsof");
        return 1;
    };

    if listeners != want {
        let mut e = io::stderr().lock();
        let _ = e.write_all(mismatch_report(&label, &port, &listeners).as_bytes());
        let _ = e.flush();
        return 1;
    }
    let mut o = io::stdout().lock();
    let _ = writeln!(o, "ok: {label} listens on 127.0.0.1:{port} only");
    let _ = o.flush();
    0
}

#[cfg(test)]
mod tests {
    use super::*;

    const TCP: &str = "  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode
   0: 0100007F:1F90 00000000:0000 0A 00000000:00000000 00:00000000 00000000  1000        0 1 1 0000000000000000 100 0 0 10 0
   1: 00000000:1F90 00000000:0000 0A 00000000:00000000 00:00000000 00000000  1000        0 2 1 0000000000000000 100 0 0 10 0
   2: 0100007F:1F90 0100007F:D431 01 00000000:00000000 00:00000000 00000000  1000        0 3 1 0000000000000000 100 0 0 10 0
   3: 0100007F:11F90 00000000:0000 0A 00000000:00000000 00:00000000 00000000  1000        0 4 1 0000000000000000 100 0 0 10 0
   4: 0100007F:1F90 00000000:0000 0A 00000000:00000000 00:00000000 00000000  1000        0 5 1 0000000000000000 100 0 0 10 0
";

    #[test]
    fn proc_rows_are_listen_rows_on_the_port_only() {
        // Row 2 is ESTABLISHED and row 3 is port 0x11F90, so rows 0, 1 and
        // 4 count, and the duplicate of row 0 is listed once.
        assert_eq!(
            proc_listeners(TCP, "1F90"),
            vec!["00000000:1F90", "0100007F:1F90"]
        );
    }

    #[test]
    fn lsof_name_column_is_second_last() {
        let table = "COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
redis 1 me 6u IPv4 0x1 0t0 TCP 127.0.0.1:6379 (LISTEN)
redis 1 me 7u IPv6 0x2 0t0 TCP [::1]:6379 (LISTEN)
redis 1 me 8u IPv4 0x3 0t0 TCP 127.0.0.1:6379 (LISTEN)
";
        assert_eq!(lsof_listeners(table), vec!["127.0.0.1:6379", "[::1]:6379"]);
    }

    #[test]
    fn port_numbers_parse_like_bash_printf() {
        assert_eq!(printf_number("8080"), Ok(8080));
        assert_eq!(printf_number("0x1F"), Ok(31));
        assert_eq!(printf_number("010"), Ok(8));
        assert_eq!(printf_number(" 7"), Ok(7));
        assert_eq!(printf_number("08"), Err("invalid octal number"));
        assert_eq!(printf_number("abc"), Err("invalid number"));
        assert_eq!(printf_number("12 "), Err("invalid number"));
        assert_eq!(hex4(8080), "1F90");
        assert_eq!(hex4(5), "0005");
        assert_eq!(hex4(70000), "11170");
    }

    #[test]
    fn mismatch_lists_each_socket_indented() {
        assert_eq!(
            mismatch_report("svc", "1", "a\nb"),
            "svc must listen on 127.0.0.1:1 only; sockets LISTENing on port 1:\n  a\n  b\n"
        );
        assert_eq!(
            mismatch_report("svc", "1", ""),
            "svc must listen on 127.0.0.1:1 only; sockets LISTENing on port 1:\n    (none)\n"
        );
    }
}
