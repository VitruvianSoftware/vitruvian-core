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

//! What the port borrows from bash: finding a command the way `command -v`
//! does, running one and reporting a failure to start it in bash's words
//! (with the script's line number), `$(...)` capture, `mktemp -d`, `$PWD`,
//! and the pathname expansion of `"$DIST_DIR/$APP-$VERSION"*.ext`.

use std::fs;
use std::io::{self, Write};
use std::os::unix::fs::{MetadataExt, PermissionsExt};
use std::os::unix::process::ExitStatusExt;
use std::path::PathBuf;
use std::process::{Command, ExitStatus, Stdio};

/// A failed step: the exit status the script would end with.
pub type Step<T = ()> = Result<T, i32>;

/// Writes to stdout and flushes, so text interleaves with child output as
/// the script's `echo` does.
pub fn out(text: &str) {
    let mut o = io::stdout().lock();
    let _ = o.write_all(text.as_bytes());
    let _ = o.write_all(b"\n");
    let _ = o.flush();
}

/// stdout without a newline added.
pub fn out_raw(bytes: &[u8]) {
    let mut o = io::stdout().lock();
    let _ = o.write_all(bytes);
    let _ = o.flush();
}

/// A line on stderr.
pub fn err(text: &str) {
    let mut e = io::stderr().lock();
    let _ = e.write_all(text.as_bytes());
    let _ = e.write_all(b"\n");
    let _ = e.flush();
}

/// strerror(3) for an I/O error, without Rust's " (os error N)".
pub fn strerror(e: &io::Error) -> String {
    let text = e.to_string();
    match text.rfind(" (os error ") {
        Some(i) => text[..i].to_string(),
        None => text,
    }
}

/// The status bash reports for a finished child.
pub fn status_code(status: ExitStatus) -> i32 {
    match status.code() {
        Some(code) => code,
        None => 128 + status.signal().unwrap_or(0),
    }
}

/// `$(...)`: drops every trailing newline.
pub fn chomp(mut s: String) -> String {
    while s.ends_with('\n') {
        s.pop();
    }
    s
}

/// `${NAME:-}`: the variable, empty when unset.
pub fn env(name: &str) -> String {
    std::env::var(name).unwrap_or_default()
}

/// `[[ -f path ]]`: a regular file, symlinks followed.
pub fn is_file(path: &str) -> bool {
    fs::metadata(path).map(|m| m.is_file()).unwrap_or(false)
}

/// `[[ -d path ]]`.
pub fn is_dir(path: &str) -> bool {
    fs::metadata(path).map(|m| m.is_dir()).unwrap_or(false)
}

/// `[[ -s path ]]`: exists with a size above zero.
pub fn is_nonempty(path: &str) -> bool {
    fs::metadata(path).map(|m| m.len() > 0).unwrap_or(false)
}

/// `command -v name`: the first executable file of that name on PATH (an
/// empty entry is the current directory). As in bash, when no entry holds an
/// executable one, the first plain file of the name still answers.
pub fn command_v(name: &str) -> Option<PathBuf> {
    if name.contains('/') {
        return if is_file(name) {
            Some(PathBuf::from(name))
        } else {
            None
        };
    }
    let path = env("PATH");
    let mut fallback = None;
    for dir in path.split(':') {
        let dir = if dir.is_empty() { "." } else { dir };
        let candidate = PathBuf::from(dir).join(name);
        if let Ok(m) = fs::metadata(&candidate) {
            if m.is_file() {
                if m.permissions().mode() & 0o111 != 0 {
                    return Some(candidate);
                }
                fallback.get_or_insert(candidate);
            }
        }
    }
    fallback
}

/// `command -v name >/dev/null 2>&1`.
pub fn has(name: &str) -> bool {
    command_v(name).is_some()
}

/// Runs commands as the script's lines do. `argv0` stands where bash names
/// the script in its own messages.
pub struct Shell {
    pub argv0: String,
}

impl Shell {
    /// bash's report for a command that could not start, and its status.
    /// `quiet` is a line whose stderr goes to /dev/null, where bash's own
    /// message goes too.
    fn spawn_failed(&self, line: u32, cmd: &Command, e: &io::Error, quiet: bool) -> i32 {
        let prog = cmd.get_program().to_string_lossy().into_owned();
        let (msg, code) = match e.kind() {
            io::ErrorKind::NotFound if prog.contains('/') => {
                (format!("{prog}: No such file or directory"), 127)
            }
            io::ErrorKind::NotFound => (format!("{prog}: command not found"), 127),
            io::ErrorKind::PermissionDenied => {
                let shown = command_v(&prog)
                    .map(|p| p.to_string_lossy().into_owned())
                    .unwrap_or(prog);
                (format!("{shown}: Permission denied"), 126)
            }
            _ => (format!("{prog}: {}", strerror(e)), 126),
        };
        if !quiet {
            err(&format!("{}: line {line}: {msg}", self.argv0));
        }
        code
    }

    /// Runs `cmd` with our stdio; its exit status (0 is success).
    pub fn status(&self, line: u32, cmd: &mut Command, quiet: bool) -> i32 {
        match cmd.status() {
            Ok(s) => status_code(s),
            Err(e) => self.spawn_failed(line, cmd, &e, quiet),
        }
    }

    /// A plain line under `set -e`: a failure ends the script with its status.
    pub fn must(&self, line: u32, cmd: &mut Command) -> Step {
        match self.status(line, cmd, false) {
            0 => Ok(()),
            code => Err(code),
        }
    }

    /// `$(cmd)`: stdout (trailing newlines kept; see chomp) and status. stderr
    /// is the caller's to set (inherited unless set otherwise).
    pub fn capture(&self, line: u32, cmd: &mut Command, quiet: bool) -> (String, i32) {
        cmd.stdout(Stdio::piped());
        match cmd.output() {
            Ok(o) => (
                String::from_utf8_lossy(&o.stdout).into_owned(),
                status_code(o.status),
            ),
            Err(e) => (String::new(), self.spawn_failed(line, cmd, &e, quiet)),
        }
    }
}

/// A command whose stderr goes where ours does (Command::output would
/// otherwise capture it).
pub fn cmd(program: &str, args: &[&str]) -> Command {
    let mut c = Command::new(program);
    c.args(args)
        .stdin(Stdio::inherit())
        .stderr(Stdio::inherit());
    c
}

/// The same with `2>/dev/null`.
pub fn cmd_quiet(program: &str, args: &[&str]) -> Command {
    let mut c = cmd(program, args);
    c.stderr(Stdio::null());
    c
}

/// `$(mktemp -d)`: a new private directory from the system's mktemp, as
/// the script makes one. (Not made here: macOS's mktemp gives the directory
/// the user's primary group where a plain mkdir inherits the parent's, and
/// ditto stamps that group into every zip entry.) Its failure ends the run.
pub fn mktemp_d() -> Step<String> {
    let mut c = cmd("mktemp", &["-d"]);
    c.stdout(Stdio::piped());
    match c.output() {
        Ok(o) if o.status.success() => Ok(chomp(String::from_utf8_lossy(&o.stdout).into_owned())),
        Ok(o) => Err(status_code(o.status)),
        Err(_) => {
            err("mktemp: command not found");
            Err(127)
        }
    }
}

/// The directory bash starts in, as its $PWD: the inherited PWD when it
/// names the current directory, else the physical path.
pub fn shell_pwd() -> String {
    let physical = std::env::current_dir()
        .map(|p| p.to_string_lossy().into_owned())
        .unwrap_or_default();
    if let Ok(pwd) = std::env::var("PWD") {
        if pwd.starts_with('/') {
            if let (Ok(a), Ok(b)) = (fs::metadata(&pwd), fs::metadata(".")) {
                if a.dev() == b.dev() && a.ino() == b.ino() {
                    return pwd;
                }
            }
        }
    }
    physical
}

/// What `cd dir && pwd` prints from `from`: `dir` joined to `from` when
/// relative, with `.`, `..` and repeated slashes resolved by name.
pub fn logical_path(from: &str, dir: &str) -> String {
    let joined = if dir.starts_with('/') {
        dir.to_string()
    } else {
        format!("{from}/{dir}")
    };
    let mut parts: Vec<&str> = Vec::new();
    for part in joined.split('/') {
        match part {
            "" | "." => {}
            ".." => {
                parts.pop();
            }
            p => parts.push(p),
        }
    }
    format!("/{}", parts.join("/"))
}

/// `"$dir/$prefix"*"$suffix"`: the matching entries of `dir`, as
/// "$dir/<name>", in byte order (the C locale's collation). Empty when
/// nothing matches; the caller decides what bash's unmatched literal means.
pub fn glob(dir: &str, prefix: &str, suffix: &str) -> Vec<String> {
    let listing = if dir.is_empty() { "/" } else { dir };
    let mut names: Vec<String> = match fs::read_dir(listing) {
        Ok(rd) => rd
            .filter_map(|e| e.ok())
            .map(|e| e.file_name().to_string_lossy().into_owned())
            .filter(|n| {
                n.len() >= prefix.len() + suffix.len()
                    && n.starts_with(prefix)
                    && n.ends_with(suffix)
                    && (prefix.starts_with('.') || !n.starts_with('.'))
            })
            .collect(),
        Err(_) => Vec::new(),
    };
    names.sort();
    names.into_iter().map(|n| format!("{dir}/{n}")).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn logical_paths() {
        assert_eq!(logical_path("/a/b", "../.."), "/");
        assert_eq!(logical_path("/a/b", "c/./d//"), "/a/b/c/d");
        assert_eq!(logical_path("/x", "/r/tools/desktop-package/../.."), "/r");
    }

    #[test]
    fn chomp_drops_only_newlines() {
        assert_eq!(chomp("a b \n\n".to_string()), "a b ");
    }

    #[test]
    fn globbing_sorts_bytewise_and_matches_ends() {
        let d = mktemp_d().unwrap();
        for n in [
            "A-1-b.zip",
            "A-1-a.zip",
            "A-1.zip.sha256",
            "B-1.zip",
            "A-1-Z.zip",
        ] {
            fs::write(format!("{d}/{n}"), "x").unwrap();
        }
        let got = glob(&d, "A-1", ".zip");
        let names: Vec<String> = got.iter().map(|p| p[d.len() + 1..].to_string()).collect();
        assert_eq!(names, vec!["A-1-Z.zip", "A-1-a.zip", "A-1-b.zip"]);
        fs::remove_dir_all(&d).unwrap();
    }

    #[test]
    fn mktemp_makes_a_private_directory() {
        let d = mktemp_d().unwrap();
        assert!(d.rsplit('/').next().unwrap().starts_with("tmp."), "{d}");
        assert_eq!(
            fs::metadata(&d).unwrap().permissions().mode() & 0o777,
            0o700
        );
        fs::remove_dir(&d).unwrap();
    }
}
