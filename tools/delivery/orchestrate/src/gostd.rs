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

//! The pieces of Go's standard library whose exact output the orchestrator's
//! messages depend on: strconv.Quote, path.Clean/Join/Base, error texts from
//! os and os/exec, and exec.LookPath. Each one copies Go's behaviour so that
//! a reason string in the manifest reads the same as the Go binary's.

use std::ffi::OsString;
use std::fs;
use std::io;
use std::os::unix::fs::{MetadataExt, PermissionsExt};
use std::os::unix::process::{CommandExt, ExitStatusExt};
use std::path::PathBuf;
use std::process::{Command, ExitStatus};

/// unicode.IsPrint, close enough for the strings this tool quotes: every
/// control, format, separator, private-use and noncharacter code point is
/// treated as unprintable. (Unassigned code points, which Go also escapes,
/// are not known to the standard library and print as themselves.)
pub fn is_print(c: char) -> bool {
    let u = c as u32;
    if u < 0x80 {
        return (0x20..0x7f).contains(&u);
    }
    if u < 0x100 {
        return u > 0xa0 && u != 0xad;
    }
    if c.is_control() || c.is_whitespace() {
        return false;
    }
    let format = matches!(u,
        0x0600..=0x0605 | 0x061c | 0x06dd | 0x070f | 0x0890..=0x0891 | 0x08e2 | 0x180e
        | 0x200b..=0x200f | 0x202a..=0x202e | 0x2060..=0x2064 | 0x2066..=0x206f
        | 0xfeff | 0xfff9..=0xfffb | 0x110bd | 0x110cd | 0x13430..=0x1343f
        | 0x1bca0..=0x1bca3 | 0x1d173..=0x1d17a | 0xe0001 | 0xe0020..=0xe007f);
    let private = matches!(u, 0xe000..=0xf8ff | 0xf0000..=0xffffd | 0x100000..=0x10fffd);
    let nonchar = matches!(u, 0xfdd0..=0xfdef) || (u & 0xfffe) == 0xfffe;
    !(format || private || nonchar)
}

/// strconv.Quote.
pub fn quote(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    out.push('"');
    for c in s.chars() {
        quote_rune(&mut out, c, '"');
    }
    out.push('"');
    out
}

/// The body of a quoted rune, as strconv.Quote writes it (no outer quotes).
pub fn quote_rune(out: &mut String, c: char, q: char) {
    if c == q || c == '\\' {
        out.push('\\');
        out.push(c);
        return;
    }
    if is_print(c) {
        out.push(c);
        return;
    }
    match c {
        '\x07' => out.push_str("\\a"),
        '\x08' => out.push_str("\\b"),
        '\x0c' => out.push_str("\\f"),
        '\n' => out.push_str("\\n"),
        '\r' => out.push_str("\\r"),
        '\t' => out.push_str("\\t"),
        '\x0b' => out.push_str("\\v"),
        _ => {
            let u = c as u32;
            if u < 0x20 || u == 0x7f {
                out.push_str(&format!("\\x{:02x}", u));
            } else if u < 0x10000 {
                out.push_str(&format!("\\u{:04x}", u));
            } else {
                out.push_str(&format!("\\U{:08x}", u));
            }
        }
    }
}

/// path.Clean.
pub fn clean(p: &str) -> String {
    if p.is_empty() {
        return ".".to_string();
    }
    let rooted = p.starts_with('/');
    let mut parts: Vec<&str> = Vec::new();
    for seg in p.split('/') {
        match seg {
            "" | "." => {}
            ".." => {
                if parts.last().map_or(false, |l| *l != "..") {
                    parts.pop();
                } else if !rooted {
                    parts.push("..");
                }
            }
            s => parts.push(s),
        }
    }
    let body = parts.join("/");
    match (rooted, body.is_empty()) {
        (true, _) => format!("/{}", body),
        (false, true) => ".".to_string(),
        (false, false) => body,
    }
}

/// path.Join (and, on unix, filepath.Join).
pub fn join(elems: &[&str]) -> String {
    let nonempty: Vec<&str> = elems.iter().copied().filter(|e| !e.is_empty()).collect();
    if nonempty.is_empty() {
        return String::new();
    }
    clean(&nonempty.join("/"))
}

/// path.Base (and, on unix, filepath.Base).
pub fn base(p: &str) -> String {
    if p.is_empty() {
        return ".".to_string();
    }
    let t = p.trim_end_matches('/');
    if t.is_empty() {
        return "/".to_string();
    }
    match t.rfind('/') {
        Some(i) => t[i + 1..].to_string(),
        None => t.to_string(),
    }
}

/// The text Go's syscall.Errno.Error() gives an OS error: the C library's
/// message with its first letter lowered, which is how Go's tables read.
pub fn errno_text(e: &io::Error) -> String {
    let full = e.to_string();
    let msg = match full.rfind(" (os error ") {
        Some(i) => &full[..i],
        None => full.as_str(),
    };
    let mut cs = msg.chars();
    match cs.next() {
        Some(f) => f.to_lowercase().collect::<String>() + cs.as_str(),
        None => String::new(),
    }
}

/// A *PathError's text: "<op> <path>: <errno>".
pub fn path_error(op: &str, path: &str, e: &io::Error) -> String {
    format!("{} {}: {}", op, path, errno_text(e))
}

/// os.ReadFile, with Go's error texts ("open ..." / "read ...").
pub fn read_file(path: &str) -> Result<Vec<u8>, String> {
    use std::io::Read;
    let mut f = fs::File::open(path).map_err(|e| path_error("open", path, &e))?;
    let mut buf = Vec::new();
    f.read_to_end(&mut buf)
        .map_err(|e| path_error("read", path, &e))?;
    Ok(buf)
}

/// lp_unix.go's findExecutable, as an errno-style text.
fn find_executable(file: &str) -> Result<(), String> {
    let md = fs::metadata(file).map_err(|e| errno_text(&e))?;
    if md.is_dir() {
        return Err("is a directory".to_string());
    }
    if md.permissions().mode() & 0o111 != 0 {
        Ok(())
    } else {
        Err("permission denied".to_string())
    }
}

/// exec.LookPath, against the orchestrator's OWN $PATH (exec.Command
/// resolves the name when the command is built, before cmd.Env applies).
fn look_path(file: &str) -> Result<PathBuf, String> {
    if file.contains('/') {
        return find_executable(file)
            .map(|_| PathBuf::from(file))
            .map_err(|e| format!("exec: {}: {}", quote(file), e));
    }
    let path = std::env::var_os("PATH").unwrap_or_default();
    let path = path.to_string_lossy().into_owned();
    if !path.is_empty() {
        for dir in path.split(':') {
            let dir = if dir.is_empty() { "." } else { dir };
            let cand = join(&[dir, file]);
            if find_executable(&cand).is_ok() {
                if !cand.starts_with('/') {
                    return Err(format!(
                        "exec: {}: cannot run executable found relative to current directory",
                        quote(file)
                    ));
                }
                return Ok(PathBuf::from(cand));
            }
        }
    }
    Err(format!(
        "exec: {}: executable file not found in $PATH",
        quote(file)
    ))
}

/// A process to run the way os/exec runs one: the name resolved against
/// $PATH unless it contains a slash, argv[0] the name as given, an exactly
/// specified environment, stdin from /dev/null, and Go's error texts.
pub struct GoCmd {
    pub cmd: Command,
    path: String,
    dir: String,
}

impl GoCmd {
    pub fn new(
        name: &str,
        args: &[String],
        dir: &str,
        env: &[(OsString, OsString)],
    ) -> Result<GoCmd, String> {
        if name.is_empty() {
            return Err("exec: no command".to_string());
        }
        let (mut cmd, path) = if base(name) == name {
            let p = look_path(name)?;
            let ps = p.to_string_lossy().into_owned();
            let mut c = Command::new(&p);
            c.arg0(name);
            (c, ps)
        } else {
            (Command::new(name), name.to_string())
        };
        cmd.args(args);
        if !dir.is_empty() {
            cmd.current_dir(dir);
        }
        cmd.env_clear();
        for (k, v) in env {
            cmd.env(k, v);
        }
        cmd.stdin(std::process::Stdio::null());
        Ok(GoCmd {
            cmd,
            path,
            dir: dir.to_string(),
        })
    }

    /// The error Start() would return for a spawn failure.
    pub fn spawn_error(&self, e: &io::Error) -> String {
        path_error("fork/exec", &self.path, e)
    }

    /// Go stats Dir before forking, so a missing one reads "chdir ...".
    pub fn check_dir(&self) -> Result<(), String> {
        if self.dir.is_empty() {
            return Ok(());
        }
        fs::metadata(&self.dir)
            .map(|_| ())
            .map_err(|e| path_error("chdir", &self.dir, &e))
    }
}

/// ProcessState.String(), which is also an *ExitError's text.
pub fn exit_status_string(st: &ExitStatus) -> String {
    let mut res = if let Some(code) = st.code() {
        format!("exit status {}", code)
    } else if let Some(sig) = st.signal() {
        format!("signal: {}", signal_name(sig))
    } else {
        String::new()
    };
    if st.core_dumped() {
        res.push_str(" (core dumped)");
    }
    res
}

#[cfg(target_os = "macos")]
const SIGNALS: [&str; 31] = [
    "hangup",
    "interrupt",
    "quit",
    "illegal instruction",
    "trace/BPT trap",
    "abort trap",
    "EMT trap",
    "floating point exception",
    "killed",
    "bus error",
    "segmentation fault",
    "bad system call",
    "broken pipe",
    "alarm clock",
    "terminated",
    "urgent I/O condition",
    "suspended (signal)",
    "suspended",
    "continued",
    "child exited",
    "stopped (tty input)",
    "stopped (tty output)",
    "I/O possible",
    "cputime limit exceeded",
    "filesize limit exceeded",
    "virtual timer expired",
    "profiling timer expired",
    "window size changes",
    "information request",
    "user defined signal 1",
    "user defined signal 2",
];

#[cfg(not(target_os = "macos"))]
const SIGNALS: [&str; 31] = [
    "hangup",
    "interrupt",
    "quit",
    "illegal instruction",
    "trace/breakpoint trap",
    "aborted",
    "bus error",
    "floating point exception",
    "killed",
    "user defined signal 1",
    "segmentation fault",
    "user defined signal 2",
    "broken pipe",
    "alarm clock",
    "terminated",
    "stack fault",
    "child exited",
    "continued",
    "stopped (signal)",
    "stopped",
    "stopped (tty input)",
    "stopped (tty output)",
    "urgent I/O condition",
    "CPU time limit exceeded",
    "file size limit exceeded",
    "virtual timer expired",
    "profiling timer expired",
    "window changed",
    "I/O possible",
    "power failure",
    "bad system call",
];

fn signal_name(sig: i32) -> String {
    if sig >= 1 && (sig as usize) <= SIGNALS.len() {
        SIGNALS[sig as usize - 1].to_string()
    } else {
        format!("signal {}", sig)
    }
}

/// os.Getwd: $PWD when it names the current directory, else getcwd.
pub fn getwd() -> Result<String, String> {
    let dot = fs::metadata(".").map_err(|e| path_error("stat", ".", &e))?;
    if let Some(pwd) = std::env::var_os("PWD") {
        let pwd = pwd.to_string_lossy().into_owned();
        if pwd.starts_with('/') {
            if let Ok(d) = fs::metadata(&pwd) {
                if d.dev() == dot.dev() && d.ino() == dot.ino() {
                    return Ok(pwd);
                }
            }
        }
    }
    std::env::current_dir()
        .map(|p| p.to_string_lossy().into_owned())
        .map_err(|e| format!("getwd: {}", errno_text(&e)))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn quote_matches_strconv() {
        assert_eq!(quote("a\"b\\c"), "\"a\\\"b\\\\c\"");
        assert_eq!(quote("\n\t\x00\x7f"), "\"\\n\\t\\x00\\x7f\"");
        assert_eq!(quote("é\u{a0}\u{200b}"), "\"é\\u00a0\\u200b\"");
        assert_eq!(quote("\u{10fffd}"), "\"\\U0010fffd\"");
    }

    #[test]
    fn path_helpers_match_go() {
        assert_eq!(clean(""), ".");
        assert_eq!(clean("a//b/./c/.."), "a/b");
        assert_eq!(clean("/../a"), "/a");
        assert_eq!(clean("../../a"), "../../a");
        assert_eq!(join(&["", ""]), "");
        assert_eq!(
            join(&["repo//x", "y.delivery.json"]),
            "repo/x/y.delivery.json"
        );
        assert_eq!(base(""), ".");
        assert_eq!(base("///"), "/");
        assert_eq!(base("a/b/"), "b");
    }

    #[test]
    fn errno_text_is_go_shaped() {
        let e = io::Error::from_raw_os_error(2);
        assert_eq!(errno_text(&e), "no such file or directory");
    }
}
