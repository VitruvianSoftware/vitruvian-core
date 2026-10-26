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

//! techdocs:check, in Rust: check.sh's walk over every mkdocs.yml git knows
//! about (tracked, or untracked and not ignored), each built with
//! `uv run --with mkdocs-techdocs-core==1.6.1 mkdocs build` in its own
//! directory, the generated `site/` removed before and after, and the same
//! report: a line per site, the failure logs (through printf's `%b`, escapes
//! and all), and the totals. Exit 0 when every site builds, 1 otherwise.
//!
//! `sort -u` is still run as a program, as the script runs it: its order is
//! the locale's collation, which is not something to re-derive.

use shell_compat::{
    basename, cat, dirname, env, err, ifs_split, out, path, spawn_diag, spawn_failure_status,
    status_code, strerror, subst,
};
use std::fs;
use std::io::Read;
use std::os::fd::OwnedFd;
use std::os::unix::ffi::OsStringExt;
use std::os::unix::net::UnixStream;
use std::process::{Command, Stdio};

pub const GREEN: &[u8] = b"\x1b[32m";
pub const RED: &[u8] = b"\x1b[31m";
pub const BOLD: &[u8] = b"\x1b[1m";
pub const RESET: &[u8] = b"\x1b[0m";

/// The mkdocs-techdocs-core release Backstage runs.
pub const TECHDOCS_CORE: &str = "mkdocs-techdocs-core==1.6.1";

fn prog() -> Vec<u8> {
    std::env::args_os()
        .next()
        .map(OsStringExt::into_vec)
        .unwrap_or_default()
}

/// bash's own diagnostic for a builtin: `<script>: line <n>: <what>`.
fn diag(line: u32, what: &[u8]) -> Vec<u8> {
    cat(&[
        &prog(),
        format!(": line {}: ", line).as_bytes(),
        what,
        b"\n",
    ])
}

/// `$PWD` as bash has it: the inherited value when it is an absolute path
/// naming the current directory, else the physical one.
pub fn logical_pwd() -> Vec<u8> {
    use std::os::unix::fs::MetadataExt;
    let cwd = std::env::current_dir()
        .map(|p| p.into_os_string().into_vec())
        .unwrap_or_default();
    if let Some(p) = env("PWD") {
        if p.first() == Some(&b'/') {
            if let (Ok(a), Ok(b)) = (fs::metadata(path(&p)), fs::metadata(path(&cwd))) {
                if a.dev() == b.dev() && a.ino() == b.ino() {
                    return p;
                }
            }
        }
    }
    cwd
}

/// The builtin `cd DIR`: false (after bash's message) when it fails.
pub fn cd(line: u32, dir: &[u8]) -> bool {
    match std::env::set_current_dir(path(dir)) {
        Ok(()) => true,
        Err(e) => {
            err(&diag(
                line,
                &cat(&[b"cd: ", dir, b": ", strerror(&e).as_bytes()]),
            ));
            false
        }
    }
}

/// `rm -rf P`. Nothing there is not an error.
pub fn rm_rf(p: &[u8]) {
    match fs::symlink_metadata(path(p)) {
        Ok(m) if m.is_dir() => {
            let _ = fs::remove_dir_all(path(p));
        }
        Ok(_) => {
            let _ = fs::remove_file(path(p));
        }
        Err(_) => {}
    }
}

fn utf8_locale() -> bool {
    shell_compat::utf8_locale()
}

/// What `printf '%b'` makes of `s` (bash 5): the backslash escapes `\a \b
/// \e \E \f \n \r \t \v \\`, `\0NNN` and `\NNN` octal, `\xHH` hex, `\uHHHH`
/// and `\UHHHHHHHH`, anything else left as it stands. `\c` ends the output
/// (the second value is then true). Diagnostics bash prints for a `\x` or
/// `\u` with no digits are the third.
pub fn bexpand(s: &[u8]) -> (Vec<u8>, bool, Vec<Vec<u8>>) {
    let mut o = Vec::with_capacity(s.len());
    let mut warnings = Vec::new();
    let mut i = 0;
    let hex = |c: u8| (c as char).to_digit(16);
    while i < s.len() {
        let c = s[i];
        i += 1;
        if c != b'\\' || i >= s.len() {
            o.push(c);
            continue;
        }
        let e = s[i];
        i += 1;
        match e {
            b'a' => o.push(7),
            b'b' => o.push(8),
            b'e' | b'E' => o.push(0x1b),
            b'f' => o.push(12),
            b'n' => o.push(b'\n'),
            b'r' => o.push(b'\r'),
            b't' => o.push(b'\t'),
            b'v' => o.push(11),
            b'\\' => o.push(b'\\'),
            b'0'..=b'7' => {
                let mut v: u32 = (e - b'0') as u32;
                let mut more = if v == 0 { 3 } else { 2 };
                while more > 0 && i < s.len() && (b'0'..=b'7').contains(&s[i]) {
                    v = v * 8 + (s[i] - b'0') as u32;
                    i += 1;
                    more -= 1;
                }
                o.push((v & 0xff) as u8);
            }
            b'x' => {
                let start = i;
                let mut v: u32 = 0;
                while i < s.len() && i - start < 2 && hex(s[i]).is_some() {
                    v = v * 16 + hex(s[i]).unwrap();
                    i += 1;
                }
                if i == start {
                    warnings.push(b"printf: missing hex digit for \\x".to_vec());
                    o.push(b'\\');
                    i -= 1;
                } else {
                    o.push((v & 0xff) as u8);
                }
            }
            b'u' | b'U' => {
                let max = if e == b'u' { 4 } else { 8 };
                let start = i;
                let mut v: u32 = 0;
                while i < s.len() && i - start < max && hex(s[i]).is_some() {
                    v = v.wrapping_mul(16).wrapping_add(hex(s[i]).unwrap());
                    i += 1;
                }
                if i == start {
                    warnings.push(cat(&[b"printf: missing unicode digit for \\", &[e]]).to_vec());
                    o.push(b'\\');
                    i -= 1;
                } else if v < 0x80 {
                    o.push(v as u8);
                } else if let (true, Some(ch)) = (utf8_locale(), char::from_u32(v)) {
                    let mut buf = [0u8; 4];
                    o.extend_from_slice(ch.encode_utf8(&mut buf).as_bytes());
                } else if e == b'u' {
                    o.extend_from_slice(format!("\\u{:04X}", v).as_bytes());
                } else {
                    o.extend_from_slice(format!("\\U{:08X}", v).as_bytes());
                }
            }
            b'c' => return (o, true, warnings),
            _ => {
                o.push(b'\\');
                i -= 1;
            }
        }
    }
    (o, false, warnings)
}

/// `printf FMT` where every `%b` argument is already expanded: write `s`
/// through `%b` then `tail`, honouring `\c`.
fn printf_b(line: u32, s: &[u8], tail: &[u8]) {
    let (body, stop, warnings) = bexpand(s);
    for w in warnings {
        err(&diag(line, &w));
    }
    if stop {
        out(&body);
    } else {
        out(&cat(&[&body, tail]));
    }
}

/// `( git ls-files ... && git ls-files --others ... ) 2>/dev/null | sort -u`:
/// the listing and the pipeline's status under pipefail. A real pipeline:
/// both gits write straight into sort, so a sort that never started leaves
/// them writing into a closed pipe, as it does in the script.
fn list_mkdocs() -> (Vec<u8>, i32) {
    const PATTERNS: [&str; 2] = ["*mkdocs.yml", "**/mkdocs.yml"];
    let mut sort = Command::new("sort");
    sort.arg("-u").stdin(Stdio::piped()).stdout(Stdio::piped());
    let (child, sink): (Option<std::process::Child>, Option<OwnedFd>) = match sort.spawn() {
        Ok(mut c) => {
            let sin = c.stdin.take().map(OwnedFd::from);
            (Some(c), sin)
        }
        Err(e) => {
            err(&spawn_diag(41, &sort, &e));
            // The reading end gone: what the gits write raises SIGPIPE.
            let w = UnixStream::pair().ok().map(|(_r, w)| OwnedFd::from(w));
            (None, w)
        }
    };
    let git = |extra: &[&str]| -> i32 {
        let mut c = Command::new("git");
        c.arg("ls-files")
            .args(extra)
            .args(PATTERNS)
            .stderr(Stdio::null());
        match sink.as_ref().and_then(|s| s.try_clone().ok()) {
            Some(fd) => c.stdout(Stdio::from(fd)),
            None => c.stdout(Stdio::null()),
        };
        match c.status() {
            Ok(st) => status_code(st),
            Err(e) => spawn_failure_status(&e),
        }
    };
    let mut sub_rc = git(&[]);
    if sub_rc == 0 {
        sub_rc = git(&["--others", "--exclude-standard"]);
    }
    drop(sink);
    let (sorted, sort_rc) = match child {
        Some(mut c) => {
            let mut o = Vec::new();
            if let Some(mut so) = c.stdout.take() {
                let _ = so.read_to_end(&mut o);
            }
            (o, c.wait().map(status_code).unwrap_or(1))
        }
        None => (Vec::new(), 127),
    };
    let rc = if sort_rc != 0 { sort_rc } else { sub_rc };
    (subst(sorted), rc)
}

/// `$(cd "$cfg_dir" && uv run ... mkdocs build -f "$cfg_file" 2>&1)`: the
/// output (stdout and stderr interleaved as written) and the status. The
/// working directory is back at `root` afterwards.
fn build_site(root: &std::path::Path, cfg_dir: &[u8], cfg_file: &[u8]) -> (Vec<u8>, i32) {
    if !cd(63, cfg_dir) {
        return (Vec::new(), 1);
    }
    let r = run_merged(
        Command::new("uv")
            .args(["run", "--with", TECHDOCS_CORE, "mkdocs", "build", "-f"])
            .arg(shell_compat::os(cfg_file)),
    );
    let _ = std::env::set_current_dir(root);
    r
}

/// Run `cmd` with its stdout and stderr on one channel, captured.
fn run_merged(cmd: &mut Command) -> (Vec<u8>, i32) {
    let pair = UnixStream::pair().and_then(|(r, w)| Ok((r, w.try_clone()?, w)));
    let (mut reader, w1, w2) = match pair {
        Ok(p) => p,
        Err(e) => return (diag(63, strerror(&e).as_bytes()), 1),
    };
    cmd.stdout(Stdio::from(OwnedFd::from(w1)))
        .stderr(Stdio::from(OwnedFd::from(w2)));
    let spawned = cmd.spawn();
    // Drop our copies of the write end (held by `cmd`) so EOF arrives when
    // the child is done.
    cmd.stdout(Stdio::null()).stderr(Stdio::null());
    match spawned {
        Ok(mut child) => {
            let mut o = Vec::new();
            let _ = reader.read_to_end(&mut o);
            let rc = child.wait().map(status_code).unwrap_or(1);
            (subst(o), rc)
        }
        Err(e) => (subst(spawn_diag(63, cmd, &e)), spawn_failure_status(&e)),
    }
}

pub fn run(_args: &[Vec<u8>]) -> i32 {
    let root = match env("BUILD_WORKSPACE_DIRECTORY") {
        Some(v) if !v.is_empty() => v,
        _ => logical_pwd(),
    };
    if !cd(30, &root) {
        return 1;
    }
    out(&cat(&[
        BOLD,
        b"TechDocs build verification",
        RESET,
        " — testing all mkdocs.yml sites with mkdocs-techdocs-core\n".as_bytes(),
    ]));

    let (files, rc) = list_mkdocs();
    if rc != 0 {
        return rc;
    }
    if files.is_empty() {
        out(&cat(&[
            RED,
            "✗ No mkdocs.yml files found in repository".as_bytes(),
            RESET,
            b"\n",
        ]));
        return 1;
    }
    let abs_root = match std::env::current_dir() {
        Ok(p) => p,
        Err(e) => {
            err(&diag(30, strerror(&e).as_bytes()));
            return 1;
        }
    };

    let (mut total, mut passed, mut failed) = (0u64, 0u64, 0u64);
    let mut fail_logs: Vec<u8> = Vec::new();
    for cfg in ifs_split(&files) {
        total += 1;
        let cfg_dir = dirname(&cfg);
        let cfg_file = basename(&cfg);
        let site_dir = cat(&[&cfg_dir, b"/site"]);
        rm_rf(&site_dir);
        let (build_out, status) = build_site(&abs_root, &cfg_dir, &cfg_file);
        rm_rf(&site_dir);
        if status == 0 {
            passed += 1;
            out(&cat(&[
                b"  ",
                GREEN,
                "✓".as_bytes(),
                RESET,
                b" ",
                &cfg,
                b"\n",
            ]));
        } else {
            failed += 1;
            out(&cat(&[
                b"  ",
                RED,
                "✗".as_bytes(),
                RESET,
                b" ",
                &cfg,
                b" (failed to build)\n",
            ]));
            fail_logs.extend_from_slice(&cat(&[
                b"\\n--- Failure log for ",
                &cfg,
                b" ---\\n",
                &build_out,
                b"\\n",
            ]));
        }
    }
    let _ = passed;

    out(b"\n");
    if failed > 0 {
        out(&cat(&[
            BOLD,
            RED,
            format!("FAIL: {}/{} TechDocs sites failed to build", failed, total).as_bytes(),
            RESET,
            b"\n",
        ]));
        printf_b(85, &fail_logs, b"\n");
        1
    } else {
        out(&cat(&[
            BOLD,
            GREEN,
            format!(
                "PASS: All {} TechDocs sites built successfully with mkdocs-techdocs-core",
                total
            )
            .as_bytes(),
            RESET,
            b"\n",
        ]));
        0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn b(s: &[u8]) -> Vec<u8> {
        bexpand(s).0
    }

    #[test]
    fn bexpand_simple_escapes() {
        assert_eq!(b(b"a\\nb\\tc"), b"a\nb\tc");
        assert_eq!(b(b"\\\\n"), b"\\n");
        assert_eq!(b(b"\\e[1m\\E"), b"\x1b[1m\x1b");
        assert_eq!(b(b"\\a\\b\\f\\r\\v"), b"\x07\x08\x0c\r\x0b");
    }

    #[test]
    fn bexpand_octal() {
        assert_eq!(b(b"\\033[0m"), b"\x1b[0m");
        assert_eq!(b(b"\\0101x"), b"Ax");
        assert_eq!(b(b"\\101"), b"A");
        assert_eq!(b(b"\\1018"), b"A8");
        assert_eq!(b(b"\\0"), b"\0");
        assert_eq!(b(b"\\08"), b"\x008");
    }

    #[test]
    fn bexpand_hex() {
        assert_eq!(b(b"\\x41\\x4"), b"A\x04");
        assert_eq!(b(b"\\x414"), b"A4");
        let (o, stop, w) = bexpand(b"\\xg");
        assert_eq!(o, b"\\xg");
        assert!(!stop);
        assert_eq!(w.len(), 1);
    }

    #[test]
    fn bexpand_unknown_and_trailing_backslash_pass_through() {
        assert_eq!(b(b"C:\\path\\q"), b"C:\\path\\q");
        assert_eq!(b(b"end\\"), b"end\\");
        assert_eq!(b(b"\\'\\\"\\?"), b"\\'\\\"\\?");
    }

    #[test]
    fn bexpand_c_stops_output() {
        let (o, stop, _) = bexpand(b"keep\\cdrop");
        assert_eq!(o, b"keep");
        assert!(stop);
    }

    #[test]
    fn bexpand_unicode_ascii() {
        assert_eq!(b(b"\\u0041\\U00000042"), b"AB");
    }

    #[test]
    fn rm_rf_removes_trees_files_and_nothing() {
        let d = std::env::temp_dir().join(format!("techdocs-rmrf-{}", std::process::id()));
        fs::create_dir_all(d.join("site/a/b")).unwrap();
        fs::write(d.join("site/a/b/f"), b"x").unwrap();
        fs::write(d.join("file"), b"x").unwrap();
        let p = |n: &str| d.join(n).into_os_string().into_vec();
        rm_rf(&p("site"));
        rm_rf(&p("file"));
        rm_rf(&p("absent"));
        assert!(!d.join("site").exists());
        assert!(!d.join("file").exists());
        fs::remove_dir_all(&d).unwrap();
    }

    #[test]
    fn run_merged_interleaves_stdout_and_stderr() {
        let (o, rc) = run_merged(
            Command::new("sh").args(["-c", "echo one; echo two >&2; echo three; exit 3"]),
        );
        assert_eq!(o, b"one\ntwo\nthree");
        assert_eq!(rc, 3);
    }
}
