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

use std::cmp::Ordering;
use std::env;
use std::ffi::{CStr, CString, OsStr, OsString};
use std::fs;
use std::io::{self, Write};
use std::os::raw::{c_char, c_int, c_void};
use std::os::unix::ffi::{OsStrExt, OsStringExt};
use std::os::unix::io::{FromRawFd, IntoRawFd};
use std::os::unix::process::ExitStatusExt;
use std::path::{Path, PathBuf};
use std::process::{Command, ExitStatus, Stdio};

const GIT_SH_HEADER: &str = r#"# git.sh — the git writes agents make, with the safety checks built in.
#
# Run from inside your worktree (made with //tools/worktree), never the main checkout.
#
# Save work:
#   bazel run //tools/git:commit -- -m "fix(scope): what changed" <paths>...
#   bazel run //tools/git:commit -- -m "feat(x): y" -m "Co-Authored-By: ..." --all
#   bazel run //tools/git:commit -- -F msg.txt <paths>...
#   bazel run //tools/git:commit -- --fixup <sha> <paths>...  # fold into <sha> later with sync --autosquash
#   bazel run //tools/git:commit -- --agent <name> -m "..." <paths>  # commit as that agent's bot
#   bazel run //tools/git:commit                              # during a merge: finish it
#
#   It stages the paths you name (or everything with --all), scans what is staged
#   for secrets, and commits. It refuses on main, in the main checkout, when
#   nothing is staged, when the scan finds something, and when a merge still has
#   conflict markers. With --agent <name> the author and committer are that
#   agent's GitHub App bot, from //tools/agent-app; without it, whoever
#   GIT_AUTHOR_*/GIT_COMMITTER_* or git config say.
#
# Publish work:
#   bazel run //tools/git:push                         # push this branch, set its upstream
#   bazel run //tools/git:push -- --agent <name>       # push as that agent's GitHub App
#   bazel run //tools/git:push -- --force-with-lease   # after a rebase (sync); never plain --force
#   bazel run //tools/git:push -- --dry-run            # say what would be pushed
#
#   It never pushes main, and scans the commits it is about to publish first.
#
# Catch up with main:
#   bazel run //tools/git:sync                    # fetch, then rebase this branch onto origin/main
#   bazel run //tools/git:sync -- --autosquash    # ...and fold in --fixup commits
#   bazel run //tools/git:sync -- --autosquash --keep-base  # fold them in where the branch is; main stays out
#   bazel run //tools/git:sync -- --merge         # merge origin/main in instead (no force-push needed)
#   bazel run //tools/git:sync -- --abort         # give up an unfinished merge or rebase
#
#   It refuses when you have uncommitted changes (it never stashes: the stash is
#   shared by every worktree). A rebase that hits a conflict is undone and the
#   files listed. A merge that hits one is left for you to finish. A branch
#   that already has merge commits is never rebased (that would drop them):
#   keep using --merge.
#
# Exit codes: 0 done, 1 refused or failed (the reason and what to run instead
# are printed), 2 bad arguments.

set -euo pipefail"#;

const CONVENTIONAL_TYPES: &[&str] = &[
    "feat", "fix", "docs", "chore", "ci", "build", "refactor", "perf", "test", "style", "revert",
];

const CONVENTIONAL_PATTERN: &str =
    "^(feat|fix|docs|chore|ci|build|refactor|perf|test|style|revert)(\\([^)]+\\))?!?: .+";
const REVERT_TITLE_PATTERN: &str = "^Revert \".+\"";

#[cfg(target_os = "macos")]
const LC_ALL: c_int = 0;
#[cfg(not(target_os = "macos"))]
const LC_ALL: c_int = 6;

extern "C" {
    fn setlocale(category: c_int, locale: *const c_char) -> *const c_char;
    fn strcoll(s1: *const c_char, s2: *const c_char) -> c_int;
    fn write(fd: c_int, buf: *const c_void, count: usize) -> isize;
    fn strerror(errnum: c_int) -> *const c_char;
    fn close(fd: c_int) -> c_int;
    fn dup(oldfd: c_int) -> c_int;
    fn fork() -> c_int;
    fn waitpid(pid: c_int, status: *mut c_int, options: c_int) -> c_int;
    fn _exit(status: c_int) -> !;
}

pub fn init_process() {
    unsafe {
        setlocale(LC_ALL, b"\0".as_ptr() as *const c_char);
    }
}

pub fn strcoll_cmp(a: &[u8], b: &[u8]) -> Ordering {
    let ca = CString::new(a).unwrap_or_else(|_| {
        let mut v: Vec<u8> = a.iter().copied().take_while(|&x| x != 0).collect();
        v.push(0);
        unsafe { CString::from_vec_unchecked(v) }
    });
    let cb = CString::new(b).unwrap_or_else(|_| {
        let mut v: Vec<u8> = b.iter().copied().take_while(|&x| x != 0).collect();
        v.push(0);
        unsafe { CString::from_vec_unchecked(v) }
    });
    let cmp = unsafe { strcoll(ca.as_ptr(), cb.as_ptr()) };
    if cmp < 0 {
        Ordering::Less
    } else if cmp > 0 {
        Ordering::Greater
    } else {
        Ordering::Equal
    }
}

pub fn locale_sort_unique_bytes(mut items: Vec<Vec<u8>>) -> Vec<Vec<u8>> {
    items.sort_by(|a, b| strcoll_cmp(a, b));
    let mut out: Vec<Vec<u8>> = Vec::with_capacity(items.len());
    for item in items {
        if out
            .last()
            .map_or(true, |prev| strcoll_cmp(prev, &item) != Ordering::Equal)
        {
            out.push(item);
        }
    }
    out
}

pub fn sorted_intersection_bytes(a: &[u8], b: &[u8]) -> Vec<Vec<u8>> {
    let mut list_a: Vec<&[u8]> = a.split(|&c| c == b'\n').filter(|s| !s.is_empty()).collect();
    let mut list_b: Vec<&[u8]> = b.split(|&c| c == b'\n').filter(|s| !s.is_empty()).collect();
    let cmp_fn = |x: &&[u8], y: &&[u8]| strcoll_cmp(x, y).then_with(|| x.cmp(y));
    list_a.sort_by(cmp_fn);
    list_b.sort_by(cmp_fn);

    let mut out = Vec::new();
    let (mut i, mut j) = (0, 0);
    while i < list_a.len() && j < list_b.len() {
        match cmp_fn(&list_a[i], &list_b[j]) {
            Ordering::Less => i += 1,
            Ordering::Greater => j += 1,
            Ordering::Equal => {
                out.push(list_a[i].to_vec());
                i += 1;
                j += 1;
            }
        }
    }
    out
}

fn bconcat(parts: &[&[u8]]) -> Vec<u8> {
    let total: usize = parts.iter().map(|p| p.len()).sum();
    let mut out = Vec::with_capacity(total);
    for p in parts {
        out.extend_from_slice(p);
    }
    out
}

fn errno_message(errnum: i32) -> Vec<u8> {
    unsafe {
        let ptr = strerror(errnum);
        if ptr.is_null() {
            format!("Unknown error {errnum}").into_bytes()
        } else {
            CStr::from_ptr(ptr).to_bytes().to_vec()
        }
    }
}

fn write_all_fd(fd: c_int, mut buf: &[u8]) -> Result<(), i32> {
    while !buf.is_empty() {
        let n = unsafe { write(fd, buf.as_ptr() as *const c_void, buf.len()) };
        if n < 0 {
            let err = io::Error::last_os_error().raw_os_error().unwrap_or(5);
            if err == 4 {
                // EINTR
                continue;
            }
            return Err(err);
        }
        buf = &buf[n as usize..];
    }
    Ok(())
}

fn report_write_error(prog: &[u8], line: u32, builtin: &[u8], errnum: i32) {
    let line_str = line.to_string();
    let err_str = errno_message(errnum);
    let msg = bconcat(&[
        prog,
        b": line ",
        line_str.as_bytes(),
        b": ",
        builtin,
        b": write error: ",
        &err_str,
        b"\n",
    ]);
    let _ = write_all_fd(2, &msg);
}

fn echo_stdout(prog: &[u8], line: u32, bytes: &[u8]) -> Result<(), i32> {
    let payload = bconcat(&[bytes, b"\n"]);
    if let Err(errnum) = write_all_fd(1, &payload) {
        report_write_error(prog, line, b"echo", errnum);
        return Err(1);
    }
    Ok(())
}

fn echo_stderr(prog: &[u8], line: u32, bytes: &[u8]) -> Result<(), i32> {
    let payload = bconcat(&[bytes, b"\n"]);
    if let Err(errnum) = write_all_fd(2, &payload) {
        report_write_error(prog, line, b"echo", errnum);
        return Err(1);
    }
    Ok(())
}

fn printf_stderr(prog: &[u8], line: u32, bytes: &[u8]) -> Result<(), i32> {
    if let Err(errnum) = write_all_fd(2, bytes) {
        report_write_error(prog, line, b"printf", errnum);
        return Err(1);
    }
    Ok(())
}

fn io_err_msg(err: &io::Error) -> Vec<u8> {
    if let Some(code) = err.raw_os_error() {
        errno_message(code)
    } else {
        let s = err.to_string();
        if let Some((msg, _)) = s.rsplit_once(" (os error ") {
            msg.as_bytes().to_vec()
        } else {
            s.into_bytes()
        }
    }
}

pub fn usage_text() -> String {
    let mut lines = Vec::new();
    let mut in_block = false;
    for line in GIT_SH_HEADER.split('\n') {
        if !in_block {
            if line.starts_with("# git.sh") {
                in_block = true;
            } else {
                continue;
            }
        }
        if line.starts_with("set -euo") {
            break;
        }
        lines.push(line);
    }
    let mut out = String::new();
    for line in lines {
        let stripped = if let Some(rest) = line.strip_prefix("# ") {
            rest
        } else if let Some(rest) = line.strip_prefix('#') {
            rest
        } else {
            line
        };
        out.push_str(stripped);
        out.push('\n');
    }
    out
}

fn status_to_code(st: ExitStatus) -> i32 {
    if let Some(code) = st.code() {
        code
    } else if let Some(sig) = st.signal() {
        128 + sig
    } else {
        1
    }
}

fn wait_status_to_code(raw: c_int) -> i32 {
    let sig = raw & 0x7f;
    if sig == 0 {
        (raw >> 8) & 0xff
    } else if sig != 0x7f {
        128 + sig
    } else {
        1
    }
}

fn print_usage(prog: &[u8]) -> i32 {
    // Matches git.sh line 68:
    // sed -n '/^# git.sh/,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'
    let text = usage_text();
    match Command::new("sed")
        .arg("s/^//")
        .stdin(Stdio::piped())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .spawn()
    {
        Ok(mut child) => {
            if let Some(mut stdin) = child.stdin.take() {
                let _ = stdin.write_all(text.as_bytes());
            }
            match child.wait() {
                Ok(st) => status_to_code(st),
                Err(_) => 1,
            }
        }
        Err(e) => {
            if let Err(errnum) = write_all_fd(1, text.as_bytes()) {
                report_write_error(prog, 68, b"printf", errnum);
                return 1;
            }
            let _ = e;
            0
        }
    }
}

fn refuse_bytes(prog: &[u8], name: &[u8], reason: &[u8], instead: &[&[u8]]) -> i32 {
    if echo_stderr(prog, 99, &bconcat(&[name, b": refused: ", reason])).is_err() {
        return 1;
    }
    if !instead.is_empty() {
        if echo_stderr(prog, 101, b"  instead:").is_err() {
            return 1;
        }
        let mut buf = Vec::new();
        for cmd in instead {
            buf.extend_from_slice(b"    ");
            buf.extend_from_slice(cmd);
            buf.push(b'\n');
        }
        if printf_stderr(prog, 102, &buf).is_err() {
            return 1;
        }
    }
    1
}

fn bad_args_bytes(prog: &[u8], name: &[u8], msg: &[u8]) -> i32 {
    if echo_stderr(
        prog,
        107,
        &bconcat(&[name, b": ", msg, b" (see: bazel run ", name, b" -- --help)"]),
    )
    .is_err()
    {
        return 1;
    }
    2
}

fn env_os_non_empty(key: &str) -> Option<Vec<u8>> {
    match env::var_os(key) {
        Some(val) if !val.is_empty() => Some(val.into_vec()),
        _ => None,
    }
}

#[derive(Default)]
struct RunfilesContext {
    runfiles_dir: Option<PathBuf>,
    manifest_file: Option<PathBuf>,
    repo_mapping: Option<String>,
}

impl RunfilesContext {
    fn discover(argv0: Option<&OsStr>) -> Self {
        // Mirror @bazel_tools//tools/bash/runfiles/runfiles.bash exactly:
        // If neither RUNFILES_DIR (as a directory) nor RUNFILES_MANIFEST_FILE (as a file)
        // is already set in the environment, check $0.runfiles_manifest, $0.runfiles/MANIFEST,
        // $0.exe.runfiles_manifest, and only then $0.runfiles (preferring the manifest when
        // both exist on disk, and exporting only the chosen variable).
        //
        // Deliberate KEEP-SAFE difference from runfiles.bash:
        // runfiles.bash exports shell functions (BASH_FUNC_rlocation%%, etc.) and internal
        // _RLOCATION_* arrays into the environment; this Rust port does not export shell
        // functions or RUNFILES_REPO_MAPPING.
        let mut runfiles_dir = env_os_non_empty("RUNFILES_DIR")
            .map(|v| PathBuf::from(OsString::from_vec(v)))
            .filter(|p| p.is_dir());
        let mut manifest_file = env_os_non_empty("RUNFILES_MANIFEST_FILE")
            .map(|v| PathBuf::from(OsString::from_vec(v)))
            .filter(|p| p.is_file());

        if runfiles_dir.is_none() && manifest_file.is_none() {
            if let Some(a0) = argv0 {
                let b = a0.as_bytes();
                let mf1 = PathBuf::from(OsStr::from_bytes(&bconcat(&[b, b".runfiles_manifest"])));
                let mf2 = PathBuf::from(OsStr::from_bytes(&bconcat(&[b, b".runfiles/MANIFEST"])));
                let mf3 =
                    PathBuf::from(OsStr::from_bytes(&bconcat(&[b, b".exe.runfiles_manifest"])));
                let dir = PathBuf::from(OsStr::from_bytes(&bconcat(&[b, b".runfiles"])));

                if mf1.is_file() {
                    env::set_var("RUNFILES_MANIFEST_FILE", &mf1);
                    manifest_file = Some(mf1);
                } else if mf2.is_file() {
                    env::set_var("RUNFILES_MANIFEST_FILE", &mf2);
                    manifest_file = Some(mf2);
                } else if mf3.is_file() {
                    env::set_var("RUNFILES_MANIFEST_FILE", &mf3);
                    manifest_file = Some(mf3);
                } else if dir.is_dir() {
                    env::set_var("RUNFILES_DIR", &dir);
                    runfiles_dir = Some(dir);
                }
            }
        }

        let mut ctx = Self {
            runfiles_dir,
            manifest_file,
            repo_mapping: None,
        };
        if let Some(mapping_path) = ctx.rlocation_checked("_repo_mapping") {
            let mp_os = OsStr::from_bytes(&mapping_path);
            if let Ok(content) = fs::read_to_string(mp_os) {
                ctx.repo_mapping = Some(content);
            }
        }
        ctx
    }

    fn rlocation_checked(&self, rlocation_path: &str) -> Option<Vec<u8>> {
        if let Some(ref mf) = self.manifest_file {
            if let Ok(content) = fs::read_to_string(mf) {
                if let Some(target) = lookup_in_manifest(&content, rlocation_path) {
                    if Path::new(&target).exists() {
                        return Some(target.into_bytes());
                    }
                }
            }
        }
        if let Some(ref dir) = self.runfiles_dir {
            let candidate = dir.join(rlocation_path);
            if candidate.exists() {
                return Some(candidate.into_os_string().into_vec());
            }
        }
        None
    }

    fn rlocation(&self, path: &str) -> Vec<u8> {
        if path.starts_with('/') {
            return path.as_bytes().to_vec();
        }
        if path.starts_with("../")
            || path.ends_with("/..")
            || path.starts_with("./")
            || path.contains("/./")
            || path.ends_with("/.")
            || path.contains("//")
            || path.starts_with('\\')
        {
            return Vec::new();
        }

        let rlocation_path = if let Some(ref mapping) = self.repo_mapping {
            if let Some((apparent_repo, remainder)) = path.split_once('/') {
                if !remainder.is_empty() {
                    if let Some(canonical_repo) = parse_repo_mapping(mapping, "", apparent_repo) {
                        format!("{canonical_repo}/{remainder}")
                    } else {
                        path.to_string()
                    }
                } else {
                    path.to_string()
                }
            } else {
                path.to_string()
            }
        } else {
            path.to_string()
        };

        self.rlocation_checked(&rlocation_path)
            .or_else(|| {
                if rlocation_path != path {
                    self.rlocation_checked(path)
                } else {
                    None
                }
            })
            .unwrap_or_default()
    }
}

pub fn parse_repo_mapping(
    mapping_content: &str,
    source_repo: &str,
    apparent_repo: &str,
) -> Option<String> {
    let prefix_exact = format!("{source_repo},{apparent_repo},");
    for line in mapping_content.split('\n') {
        let line = line.trim_end_matches('\r');
        if let Some(target) = line.strip_prefix(&prefix_exact) {
            if !target.is_empty() {
                return Some(target.to_string());
            }
        }
    }
    None
}

pub fn lookup_in_manifest(manifest_content: &str, key: &str) -> Option<String> {
    let prefix = format!("{key} ");
    for line in manifest_content.split('\n') {
        let line = line.trim_end_matches('\r');
        if let Some(target) = line.strip_prefix(&prefix) {
            return Some(target.to_string());
        }
    }
    None
}

pub fn is_conventional_commit(subject: &str) -> bool {
    for &ty in CONVENTIONAL_TYPES {
        if let Some(mut rest) = subject.strip_prefix(ty) {
            if let Some(after_open) = rest.strip_prefix('(') {
                if let Some(close_idx) = after_open.find(')') {
                    if close_idx >= 1 {
                        rest = &after_open[close_idx + 1..];
                    } else {
                        return false;
                    }
                } else {
                    return false;
                }
            }
            rest = rest.strip_prefix('!').unwrap_or(rest);
            if let Some(after_colon) = rest.strip_prefix(": ") {
                return !after_colon.is_empty();
            }
            return false;
        }
    }
    false
}

pub fn is_revert_title(subject: &str) -> bool {
    // grep -E '^Revert ".+"': at least one character, then a quote somewhere
    // after it (the first character may itself be a quote).
    if let Some(rest) = subject.strip_prefix("Revert \"") {
        let mut chars = rest.chars();
        if chars.next().is_some() {
            return chars.as_str().contains('"');
        }
    }
    false
}

pub fn is_valid_commit_subject(subject: &str) -> bool {
    is_conventional_commit(subject) || is_revert_title(subject)
}

pub fn extract_subject_from_file_content(content: &str) -> String {
    let mut lines: Vec<&str> = content.split('\n').collect();
    if lines.last() == Some(&"") {
        lines.pop();
    }
    for line in lines {
        if !line.starts_with('#') && !line.is_empty() {
            return line.to_string();
        }
    }
    String::new()
}

pub fn extract_subject_from_message(msg: &str) -> String {
    msg.split('\n').next().unwrap_or("").to_string()
}

pub fn is_agent_bot_name_bytes(name: &[u8]) -> bool {
    name.starts_with(b"vitruvian-")
        && name.ends_with(b"-agent[bot]")
        && name.len() >= b"vitruvian--agent[bot]".len()
}

pub fn is_agent_bot_name(name: &str) -> bool {
    is_agent_bot_name_bytes(name.as_bytes())
}

pub fn has_conflict_marker(line: &str) -> bool {
    let has_prefix =
        line.starts_with("<<<<<<<") || line.starts_with(">>>>>>>") || line.starts_with("|||||||");
    if !has_prefix {
        return false;
    }
    line.len() == 7 || line.as_bytes().get(7) == Some(&b' ')
}

pub fn find_conflict_markers(file_path: &str, content: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut lines: Vec<&str> = content.split('\n').collect();
    if lines.last() == Some(&"") {
        lines.pop();
    }
    for (idx, line) in lines.into_iter().enumerate() {
        if has_conflict_marker(line) {
            out.push(format!("{file_path}:{}", idx + 1));
        }
    }
    out
}

pub fn sorted_intersection(a: &str, b: &str) -> Vec<String> {
    sorted_intersection_bytes(a.as_bytes(), b.as_bytes())
        .into_iter()
        .map(|v| String::from_utf8_lossy(&v).into_owned())
        .collect()
}

pub fn parse_export_line_bytes(line: &[u8]) -> Option<(Vec<u8>, Vec<u8>)> {
    let rest = line.strip_prefix(b"export ")?;
    let eq_pos = rest.iter().position(|&b| b == b'=')?;
    let key = &rest[..eq_pos];
    let raw_val = &rest[eq_pos + 1..];
    if key.is_empty() {
        return None;
    }
    let val = if raw_val.len() >= 2 && raw_val.starts_with(b"'") && raw_val.ends_with(b"'") {
        raw_val[1..raw_val.len() - 1].to_vec()
    } else if raw_val.len() >= 2 && raw_val.starts_with(b"\"") && raw_val.ends_with(b"\"") {
        raw_val[1..raw_val.len() - 1].to_vec()
    } else {
        raw_val.to_vec()
    };
    Some((key.to_vec(), val))
}

pub fn parse_export_line(line: &str) -> Option<(String, String)> {
    let (k, v) = parse_export_line_bytes(line.as_bytes())?;
    Some((
        String::from_utf8_lossy(&k).into_owned(),
        String::from_utf8_lossy(&v).into_owned(),
    ))
}

pub fn is_git_identity_export_line_bytes(line: &[u8]) -> bool {
    line.starts_with(b"export GIT_AUTHOR_NAME=")
        || line.starts_with(b"export GIT_AUTHOR_EMAIL=")
        || line.starts_with(b"export GIT_COMMITTER_NAME=")
        || line.starts_with(b"export GIT_COMMITTER_EMAIL=")
}

pub fn is_git_identity_export_line(line: &str) -> bool {
    is_git_identity_export_line_bytes(line.as_bytes())
}

pub fn parse_identity_exports_bytes(exports: &[u8]) -> Option<Vec<(Vec<u8>, Vec<u8>)>> {
    let matching: Vec<&[u8]> = exports
        .split(|&b| b == b'\n')
        .filter(|line| is_git_identity_export_line_bytes(line))
        .collect();
    if matching.len() != 4 {
        return None;
    }
    let mut parsed = Vec::with_capacity(4);
    for line in matching {
        parsed.push(parse_export_line_bytes(line)?);
    }
    Some(parsed)
}

pub fn parse_identity_exports(exports: &str) -> Option<Vec<(String, String)>> {
    let pairs = parse_identity_exports_bytes(exports.as_bytes())?;
    Some(
        pairs
            .into_iter()
            .map(|(k, v)| {
                (
                    String::from_utf8_lossy(&k).into_owned(),
                    String::from_utf8_lossy(&v).into_owned(),
                )
            })
            .collect(),
    )
}

pub fn clamp_wd_to_here_bytes(wd: &[u8], here: &[u8]) -> Vec<u8> {
    let wd_slash = bconcat(&[wd, b"/"]);
    let here_slash = bconcat(&[here, b"/"]);
    if wd_slash.starts_with(&here_slash) {
        wd.to_vec()
    } else {
        here.to_vec()
    }
}

pub fn clamp_wd_to_here(wd: &str, here: &str) -> String {
    String::from_utf8_lossy(&clamp_wd_to_here_bytes(wd.as_bytes(), here.as_bytes())).into_owned()
}

fn trim_trailing_newlines(mut v: Vec<u8>) -> Vec<u8> {
    while v.last() == Some(&b'\n') {
        v.pop();
    }
    v
}

fn spawn_err_to_code(
    prog: &[u8],
    line: u32,
    cmd_name: &[u8],
    err: &io::Error,
    discard_stderr: bool,
) -> i32 {
    let is_not_found = err.kind() == io::ErrorKind::NotFound;
    if !discard_stderr {
        let line_str = line.to_string();
        if is_not_found {
            let msg = bconcat(&[
                prog,
                b": line ",
                line_str.as_bytes(),
                b": ",
                cmd_name,
                b": command not found\n",
            ]);
            let _ = write_all_fd(2, &msg);
        } else {
            let errnum = err.raw_os_error().unwrap_or(13);
            let err_str = errno_message(errnum);
            let msg = bconcat(&[
                prog,
                b": line ",
                line_str.as_bytes(),
                b": ",
                cmd_name,
                b": ",
                &err_str,
                b"\n",
            ]);
            let _ = write_all_fd(2, &msg);
        }
    }
    if is_not_found {
        127
    } else {
        126
    }
}

fn git_output_bytes(
    prog: &[u8],
    line: u32,
    args: &[&[u8]],
    env_vars: &[(&str, &str)],
    discard_stderr: bool,
) -> (i32, Vec<u8>) {
    let mut cmd = Command::new("git");
    for &a in args {
        cmd.arg(OsStr::from_bytes(a));
    }
    for &(k, v) in env_vars {
        cmd.env(k, v);
    }
    cmd.stdin(Stdio::inherit());
    cmd.stdout(Stdio::piped());
    if discard_stderr {
        cmd.stderr(Stdio::null());
    } else {
        cmd.stderr(Stdio::inherit());
    }
    match cmd.output() {
        Ok(out) => {
            let code = status_to_code(out.status);
            (code, trim_trailing_newlines(out.stdout))
        }
        Err(e) => (
            spawn_err_to_code(prog, line, b"git", &e, discard_stderr),
            Vec::new(),
        ),
    }
}

fn git_status_bytes(
    prog: &[u8],
    line: u32,
    args: &[&[u8]],
    env_vars: &[(&str, &str)],
    discard_stdout: bool,
    discard_stderr: bool,
) -> i32 {
    let mut cmd = Command::new("git");
    for &a in args {
        cmd.arg(OsStr::from_bytes(a));
    }
    for &(k, v) in env_vars {
        cmd.env(k, v);
    }
    cmd.stdin(Stdio::inherit());
    if discard_stdout {
        cmd.stdout(Stdio::null());
    } else {
        cmd.stdout(Stdio::inherit());
    }
    if discard_stderr {
        cmd.stderr(Stdio::null());
    } else {
        cmd.stderr(Stdio::inherit());
    }
    match cmd.status() {
        Ok(st) => status_to_code(st),
        Err(e) => spawn_err_to_code(prog, line, b"git", &e, discard_stderr),
    }
}

fn run_dirty_pipeline(prog: &[u8], dirty: &[u8]) -> i32 {
    // Matches git.sh line 487 inside `{ ... } >&2` under `set -euo pipefail`:
    //   printf '%s\n' "${dirty}" | head -20 | sed 's/^/    /'
    let Ok(mut head_child) = Command::new("head")
        .arg("-20")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .spawn()
    else {
        return 1;
    };
    let Some(head_stdin) = head_child.stdin.take() else {
        let _ = head_child.wait();
        return 1;
    };
    let Some(head_stdout) = head_child.stdout.take() else {
        drop(head_stdin);
        let _ = head_child.wait();
        return 1;
    };
    let dup2_fd = unsafe { dup(2) };
    let sed_stdout = if dup2_fd >= 0 {
        unsafe { Stdio::from_raw_fd(dup2_fd) }
    } else {
        Stdio::null()
    };
    let Ok(mut sed_child) = Command::new("sed")
        .arg("s/^/    /")
        .stdin(Stdio::from(head_stdout))
        .stdout(sed_stdout)
        .stderr(Stdio::inherit())
        .spawn()
    else {
        drop(head_stdin);
        let _ = head_child.wait();
        return 1;
    };

    let write_fd = head_stdin.into_raw_fd();
    let pid = unsafe { fork() };
    if pid < 0 {
        unsafe {
            close(write_fd);
        }
        let _ = head_child.wait();
        let _ = sed_child.wait();
        return 1;
    }
    if pid == 0 {
        let payload = bconcat(&[dirty, b"\n"]);
        let rc = match write_all_fd(write_fd, &payload) {
            Ok(()) => 0,
            Err(errnum) => {
                report_write_error(prog, 487, b"printf", errnum);
                1
            }
        };
        unsafe {
            close(write_fd);
            _exit(rc);
        }
    }
    unsafe {
        close(write_fd);
    }
    let mut raw_printf_status: c_int = 0;
    unsafe {
        waitpid(pid, &mut raw_printf_status, 0);
    }
    let rc_printf = wait_status_to_code(raw_printf_status);
    let rc_head = head_child.wait().map(status_to_code).unwrap_or(1);
    let rc_sed = sed_child.wait().map(status_to_code).unwrap_or(1);
    if rc_sed != 0 {
        rc_sed
    } else if rc_head != 0 {
        rc_head
    } else {
        rc_printf
    }
}

fn extract_subject_from_file_grep(msg_file: &[u8]) -> Vec<u8> {
    let Ok(mut grep1) = Command::new("grep")
        .arg("-v")
        .arg("^#")
        .arg(OsStr::from_bytes(msg_file))
        .stdin(Stdio::inherit())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .spawn()
    else {
        return Vec::new();
    };
    let Some(g1_out) = grep1.stdout.take() else {
        let _ = grep1.wait();
        return Vec::new();
    };
    let grep2 = Command::new("grep")
        .arg("-m1")
        .arg(".")
        .stdin(Stdio::from(g1_out))
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .output();
    let _ = grep1.wait();
    match grep2 {
        Ok(out) => trim_trailing_newlines(out.stdout),
        Err(_) => Vec::new(),
    }
}

fn grep_eq(pattern: &str, subject: &[u8]) -> bool {
    let Ok(mut child) = Command::new("grep")
        .arg("-Eq")
        .arg(pattern)
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::inherit())
        .spawn()
    else {
        return false;
    };
    if let Some(mut stdin) = child.stdin.take() {
        let _ = stdin.write_all(&bconcat(&[subject, b"\n"]));
    }
    match child.wait() {
        Ok(st) => st.success(),
        Err(_) => false,
    }
}

fn find_staged_conflict_markers(file_path: &[u8]) -> Vec<Vec<u8>> {
    // Matches git.sh line 321:
    // git show ":${f}" 2>/dev/null | grep -nE '^(<{7}|>{7}|\|{7})( |$)' | cut -d: -f1 | sed "s|^|${f}:|" || true
    //
    // Deliberate KEEP-SAFE improvement over git.sh:
    // In git.sh, `sed "s|^|${f}:|"` fails when `${f}` contains `|` (hidden by `|| true`,
    // allowing conflict markers to be committed!) and mangles `&` into the matched regex
    // text (empty). Here we prepend the literal `file_path` bytes so conflict markers are
    // caught regardless of `|` or `&` in the filename.
    let spec = bconcat(&[b":", file_path]);
    let Ok(mut git_child) = Command::new("git")
        .arg("show")
        .arg(OsStr::from_bytes(&spec))
        .stdin(Stdio::inherit())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
    else {
        return Vec::new();
    };
    let Some(git_stdout) = git_child.stdout.take() else {
        let _ = git_child.wait();
        return Vec::new();
    };
    let grep_out = Command::new("grep")
        .arg("-nE")
        .arg("^(<{7}|>{7}|\\|{7})( |$)")
        .stdin(Stdio::from(git_stdout))
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .output();
    let _ = git_child.wait();
    let Ok(out) = grep_out else {
        return Vec::new();
    };
    let mut markers = Vec::new();
    for line in out.stdout.split(|&b| b == b'\n') {
        if line.is_empty() {
            continue;
        }
        let first_field = line.split(|&b| b == b':').next().unwrap_or(line);
        markers.push(bconcat(&[file_path, b":", first_field]));
    }
    markers
}

struct EnvState {
    prog: Vec<u8>,
    name: Vec<u8>,
    here: Vec<u8>,
    wd: Vec<u8>,
    git_dir: Vec<u8>,
    common_dir: Vec<u8>,
    branch: Vec<u8>,
    secret_scan: Vec<u8>,
    agent_app: Vec<u8>,
}

impl EnvState {
    fn is_primary(&self) -> bool {
        self.git_dir == self.common_dir
    }

    fn in_merge(&self) -> bool {
        let (rc, path) = git_output_bytes(
            &self.prog,
            130,
            &[b"rev-parse", b"--git-path", b"MERGE_HEAD"],
            &[],
            false,
        );
        rc == 0 && !path.is_empty() && Path::new(OsStr::from_bytes(&path)).is_file()
    }

    fn in_rebase(&self) -> bool {
        let (rc1, p1) = git_output_bytes(
            &self.prog,
            131,
            &[b"rev-parse", b"--git-path", b"rebase-merge"],
            &[],
            false,
        );
        if rc1 == 0 && !p1.is_empty() && Path::new(OsStr::from_bytes(&p1)).is_dir() {
            return true;
        }
        let (rc2, p2) = git_output_bytes(
            &self.prog,
            131,
            &[b"rev-parse", b"--git-path", b"rebase-apply"],
            &[],
            false,
        );
        rc2 == 0 && !p2.is_empty() && Path::new(OsStr::from_bytes(&p2)).is_dir()
    }

    fn base_ref(&self) -> &'static [u8] {
        if git_status_bytes(
            &self.prog,
            132,
            &[
                b"rev-parse",
                b"--verify",
                b"--quiet",
                b"refs/remotes/origin/main",
            ],
            &[],
            true,
            false,
        ) == 0
        {
            b"origin/main"
        } else {
            b"main"
        }
    }

    fn need_work_branch(&self) -> Result<(), i32> {
        if self.branch.is_empty() {
            return Err(refuse_bytes(
                &self.prog,
                &self.name,
                b"HEAD is detached, so there is no branch to put this on",
                &[b"make a branch worktree: bazel run //tools/worktree -- <branch>"],
            ));
        }
        if self.branch == b"main" {
            return Err(refuse_bytes(
                &self.prog,
                &self.name,
                b"this is main. Work happens on a branch in its own worktree",
                &[b"bazel run //tools/worktree -- <branch>, then run this from inside it"],
            ));
        }
        Ok(())
    }

    fn no_op_in_progress(&self) -> Result<(), i32> {
        if self.in_rebase() {
            return Err(refuse_bytes(
                &self.prog,
                &self.name,
                b"a rebase is in progress here",
                &[b"finish or drop it: bazel run //tools/git:sync -- --abort"],
            ));
        }
        Ok(())
    }

    fn conflicted_files(&self) -> Result<Vec<u8>, i32> {
        let (rc, out) = git_output_bytes(
            &self.prog,
            150,
            &[b"diff", b"--name-only", b"--diff-filter=U"],
            &[],
            false,
        );
        if rc != 0 {
            return Err(rc);
        }
        Ok(out)
    }

    fn scan(&self, scan_arg: &str) -> Result<bool, i32> {
        if self.secret_scan.is_empty() || !Path::new(OsStr::from_bytes(&self.secret_scan)).is_file()
        {
            let instead = bconcat(&[b"run this through Bazel: bazel run ", &self.name]);
            return Err(refuse_bytes(
                &self.prog,
                &self.name,
                b"cannot find //tools/secret-scan, so nothing could be scanned",
                &[&instead],
            ));
        }
        let status = Command::new("bash")
            .arg(OsStr::from_bytes(&self.secret_scan))
            .arg(scan_arg)
            .env("BUILD_WORKSPACE_DIRECTORY", OsStr::from_bytes(&self.here))
            .stdin(Stdio::inherit())
            .stdout(Stdio::inherit())
            .stderr(Stdio::inherit())
            .status();
        match status {
            Ok(st) => Ok(st.success()),
            Err(_) => Ok(false),
        }
    }

    fn agent_exports(&self, agent: &[u8]) -> Result<Vec<u8>, i32> {
        if self.agent_app.is_empty() || !Path::new(OsStr::from_bytes(&self.agent_app)).is_file() {
            let instead = bconcat(&[
                b"run this through Bazel: bazel run ",
                &self.name,
                b" -- --agent ",
                agent,
            ]);
            return Err(refuse_bytes(
                &self.prog,
                &self.name,
                b"cannot find //tools/agent-app",
                &[&instead],
            ));
        }
        let out = Command::new("bash")
            .arg(OsStr::from_bytes(&self.agent_app))
            .arg("env")
            .arg(OsStr::from_bytes(agent))
            .env("BUILD_WORKSPACE_DIRECTORY", OsStr::from_bytes(&self.here))
            .stdin(Stdio::inherit())
            .stdout(Stdio::piped())
            .stderr(Stdio::inherit())
            .output();
        match out {
            Ok(o) if o.status.success() => Ok(trim_trailing_newlines(o.stdout)),
            _ => {
                let reason = bconcat(&[
                    b"could not get ",
                    agent,
                    b"'s GitHub identity (agent-app's reason is above); nothing was done",
                ]);
                let instead = bconcat(&[
                    b"check the name and the key: bazel run //tools/agent-app -- env ",
                    agent,
                ]);
                Err(refuse_bytes(&self.prog, &self.name, &reason, &[&instead]))
            }
        }
    }
}

pub fn run(args: &[String]) -> i32 {
    let os_args: Vec<OsString> = args.iter().map(OsString::from).collect();
    run_os(&os_args)
}

pub fn run_os(args: &[OsString]) -> i32 {
    init_process();

    let argv0 = args.first().map(|s| s.as_os_str());
    let prog: Vec<u8> = argv0
        .map(|s| s.as_bytes().to_vec())
        .filter(|b| !b.is_empty())
        .unwrap_or_else(|| b"git.sh".to_vec());
    let rf = RunfilesContext::discover(argv0);

    let secret_scan = env_os_non_empty("SECRET_SCAN")
        .unwrap_or_else(|| rf.rlocation("_main/tools/secret-scan/secret-scan.sh"));
    let gitleaks = env_os_non_empty("GITLEAKS")
        .unwrap_or_else(|| rf.rlocation("multitool/tools/gitleaks/gitleaks"));
    let gitleaks_config =
        env_os_non_empty("GITLEAKS_CONFIG").unwrap_or_else(|| rf.rlocation("_main/.gitleaks.toml"));
    let agent_app = env_os_non_empty("AGENT_APP")
        .unwrap_or_else(|| rf.rlocation("_main/tools/agent-app/agent-app.sh"));

    env::set_var("GITLEAKS", OsStr::from_bytes(&gitleaks));
    env::set_var("GITLEAKS_CONFIG", OsStr::from_bytes(&gitleaks_config));

    let cmd = args.get(1).map(|s| s.as_bytes()).unwrap_or(b"");
    let sub_args = if args.len() > 2 { &args[2..] } else { &[] };
    let name_cmd: &[u8] = if cmd.is_empty() { b"?" } else { cmd };
    let name = bconcat(&[b"//tools/git:", name_cmd]);

    if matches!(cmd, b"" | b"-h" | b"--help" | b"help") {
        return print_usage(&prog);
    }

    let here_raw = env_os_non_empty("BUILD_WORKSPACE_DIRECTORY").unwrap_or_else(|| {
        let (_rc, out) =
            git_output_bytes(&prog, 116, &[b"rev-parse", b"--show-toplevel"], &[], true);
        out
    });
    if here_raw.is_empty()
        || git_status_bytes(
            &prog,
            117,
            &[b"-C", &here_raw, b"rev-parse", b"--git-dir"],
            &[],
            true,
            true,
        ) != 0
    {
        let instead = bconcat(&[b"cd into your worktree, then: bazel run ", &name]);
        return refuse_bytes(
            &prog,
            &name,
            b"this is not inside a git repository",
            &[&instead],
        );
    }
    let here = match fs::canonicalize(OsStr::from_bytes(&here_raw)) {
        Ok(p) => p.into_os_string().into_vec(),
        Err(e) => {
            let err_msg = io_err_msg(&e);
            let msg = bconcat(&[
                &prog,
                b": line 120: cd: ",
                &here_raw,
                b": ",
                &err_msg,
                b"\n",
            ]);
            let _ = write_all_fd(2, &msg);
            return 1;
        }
    };

    let wd_raw = env_os_non_empty("BUILD_WORKING_DIRECTORY").unwrap_or_else(|| {
        env::current_dir()
            .map(|p| p.into_os_string().into_vec())
            .unwrap_or_else(|_| here.clone())
    });
    let wd_canon = if Path::new(OsStr::from_bytes(&wd_raw)).is_dir() {
        fs::canonicalize(OsStr::from_bytes(&wd_raw))
            .map(|p| p.into_os_string().into_vec())
            .unwrap_or_else(|_| here.clone())
    } else {
        here.clone()
    };
    let wd = clamp_wd_to_here_bytes(&wd_canon, &here);

    let oldpwd = env::var_os("PWD").or_else(|| env::current_dir().ok().map(OsString::from));
    if let Err(e) = env::set_current_dir(OsStr::from_bytes(&here)) {
        let err_msg = io_err_msg(&e);
        let msg = bconcat(&[&prog, b": line 124: cd: ", &here, b": ", &err_msg, b"\n"]);
        let _ = write_all_fd(2, &msg);
        return 1;
    }
    if let Some(old) = oldpwd {
        env::set_var("OLDPWD", old);
    }
    env::set_var("PWD", OsStr::from_bytes(&here));

    let (rc_gd, git_dir) = git_output_bytes(
        &prog,
        126,
        &[b"rev-parse", b"--path-format=absolute", b"--git-dir"],
        &[],
        false,
    );
    if rc_gd != 0 {
        return rc_gd;
    }
    let (rc_cd, common_dir) = git_output_bytes(
        &prog,
        127,
        &[b"rev-parse", b"--path-format=absolute", b"--git-common-dir"],
        &[],
        false,
    );
    if rc_cd != 0 {
        return rc_cd;
    }
    let (_rc_br, branch) = git_output_bytes(
        &prog,
        128,
        &[b"symbolic-ref", b"--quiet", b"--short", b"HEAD"],
        &[],
        true,
    );

    let state = EnvState {
        prog,
        name,
        here,
        wd,
        git_dir,
        common_dir,
        branch,
        secret_scan,
        agent_app,
    };

    match cmd {
        b"commit" => cmd_commit(&state, sub_args),
        b"push" => cmd_push(&state, sub_args),
        b"sync" => cmd_sync(&state, sub_args),
        _ => bad_args_bytes(
            &state.prog,
            b"//tools/git",
            &bconcat(&[b"unknown command: ", cmd, b" (one of: commit, push, sync)"]),
        ),
    }
}

fn cmd_commit(state: &EnvState, args: &[OsString]) -> i32 {
    let mut msgs: Vec<Vec<u8>> = Vec::new();
    let mut msg_file: Vec<u8> = Vec::new();
    let mut fixup: Vec<u8> = Vec::new();
    let mut all = false;
    let mut paths: Vec<Vec<u8>> = Vec::new();
    let mut agent: Vec<u8> = Vec::new();

    let mut i = 0;
    while i < args.len() {
        let arg = args[i].as_bytes();
        match arg {
            b"-h" | b"--help" => {
                return print_usage(&state.prog);
            }
            b"-m" | b"--message" => {
                if i + 1 >= args.len() {
                    return bad_args_bytes(&state.prog, &state.name, b"-m needs a message");
                }
                msgs.push(args[i + 1].as_bytes().to_vec());
                i += 1;
            }
            b"-F" | b"--file" => {
                if i + 1 >= args.len() {
                    return bad_args_bytes(&state.prog, &state.name, b"-F needs a file");
                }
                msg_file = args[i + 1].as_bytes().to_vec();
                i += 1;
            }
            b"--fixup" => {
                if i + 1 >= args.len() {
                    return bad_args_bytes(&state.prog, &state.name, b"--fixup needs a commit");
                }
                fixup = args[i + 1].as_bytes().to_vec();
                i += 1;
            }
            b"--agent" => {
                if i + 1 >= args.len() {
                    return bad_args_bytes(&state.prog, &state.name, b"--agent needs a name");
                }
                agent = args[i + 1].as_bytes().to_vec();
                i += 1;
            }
            b"-a" | b"--all" => {
                all = true;
            }
            b"--amend" | b"--no-verify" | b"-n" => {
                return refuse_bytes(
                    &state.prog,
                    &state.name,
                    &bconcat(&[
                        arg,
                        b" is not offered: amending rewrites a commit, and hooks are part of the checks",
                    ]),
                    &[b"add a commit that fixes it: bazel run //tools/git:commit -- --fixup <sha> <paths>"],
                );
            }
            b"--" => {
                for p in &args[i + 1..] {
                    paths.push(p.as_bytes().to_vec());
                }
                break;
            }
            _ if arg.starts_with(b"-") => {
                return bad_args_bytes(
                    &state.prog,
                    &state.name,
                    &bconcat(&[b"unknown flag: ", arg]),
                );
            }
            _ => {
                paths.push(arg.to_vec());
            }
        }
        i += 1;
    }

    if state.is_primary() {
        return refuse_bytes(
            &state.prog,
            &state.name,
            b"this is the main checkout, which stays on main and is shared",
            &[
                b"make a worktree: bazel run //tools/worktree -- <branch>, then commit from inside it",
                b"to carry edits you already made here: git diff HEAD --binary > /tmp/wip.patch (here),",
                b"  then git apply /tmp/wip.patch in the new worktree; copy any new (untracked) files across too",
            ],
        );
    }
    if let Err(rc) = state.no_op_in_progress() {
        return rc;
    }
    if let Err(rc) = state.need_work_branch() {
        return rc;
    }

    let merging = state.in_merge();
    if all && !paths.is_empty() {
        return bad_args_bytes(&state.prog, &state.name, b"give paths or --all, not both");
    }
    if !msg_file.is_empty() && !msgs.is_empty() {
        return bad_args_bytes(&state.prog, &state.name, b"give -m or -F, not both");
    }
    if !fixup.is_empty() && (!msg_file.is_empty() || !msgs.is_empty()) {
        return bad_args_bytes(
            &state.prog,
            &state.name,
            b"--fixup writes its own message; drop -m/-F",
        );
    }
    if !fixup.is_empty() && merging {
        return refuse_bytes(
            &state.prog,
            &state.name,
            b"a merge is in progress; a fixup cannot conclude it",
            &[
                b"finish the merge first: bazel run //tools/git:commit",
                b"or drop it: bazel run //tools/git:sync -- --abort",
            ],
        );
    }
    if fixup.is_empty() && msg_file.is_empty() && msgs.is_empty() && !merging {
        return refuse_bytes(
            &state.prog,
            &state.name,
            b"a commit message is required",
            &[b"bazel run //tools/git:commit -- -m \"fix(scope): what changed\" <paths>..."],
        );
    }

    if !msg_file.is_empty() {
        if !msg_file.starts_with(b"/") {
            msg_file = bconcat(&[&state.wd, b"/", &msg_file]);
        }
        if !Path::new(OsStr::from_bytes(&msg_file)).is_file() {
            return bad_args_bytes(
                &state.prog,
                &state.name,
                &bconcat(&[b"no such message file: ", &msg_file]),
            );
        }
    }
    if fixup.is_empty() && !merging {
        let subject = if !msg_file.is_empty() {
            extract_subject_from_file_grep(&msg_file)
        } else {
            msgs[0]
                .split(|&b| b == b'\n')
                .next()
                .unwrap_or(&[])
                .to_vec()
        };
        if !grep_eq(CONVENTIONAL_PATTERN, &subject) && !grep_eq(REVERT_TITLE_PATTERN, &subject) {
            return refuse_bytes(
                &state.prog,
                &state.name,
                &bconcat(&[
                    b"the first line is not a Conventional Commit: \"",
                    &subject,
                    b"\"",
                ]),
                &[
                    b"start it with a type and optional scope, e.g. -m \"fix(worktree): keep locked trees\"",
                    b"types: feat fix docs chore ci build refactor perf test style revert; or a revert's own Revert \"<title>\"",
                ],
            );
        }
    }

    if !fixup.is_empty() {
        let commit_spec = bconcat(&[&fixup, b"^{commit}"]);
        let (rc, target) = git_output_bytes(
            &state.prog,
            249,
            &[b"rev-parse", b"--verify", b"--quiet", &commit_spec],
            &[],
            false,
        );
        if rc != 0 || target.is_empty() {
            return bad_args_bytes(
                &state.prog,
                &state.name,
                &bconcat(&[b"--fixup: no such commit: ", &fixup]),
            );
        }
        if git_status_bytes(
            &state.prog,
            251,
            &[b"merge-base", b"--is-ancestor", &target, b"HEAD"],
            &[],
            false,
            false,
        ) != 0
        {
            let bref = state.base_ref();
            let instead = bconcat(&[b"name a commit from: git log --oneline ", bref, b"..HEAD"]);
            return refuse_bytes(
                &state.prog,
                &state.name,
                &bconcat(&[
                    &fixup,
                    b" is not on this branch, so there is nothing for the fixup to fold into",
                ]),
                &[&instead],
            );
        }
        let bref = state.base_ref();
        if git_status_bytes(
            &state.prog,
            254,
            &[b"merge-base", b"--is-ancestor", &target, bref],
            &[],
            false,
            true,
        ) == 0
        {
            let bref2 = state.base_ref();
            return refuse_bytes(
                &state.prog,
                &state.name,
                &bconcat(&[&fixup, b" is already on ", bref2, b"; it cannot be rewritten"]),
                &[b"commit the fix normally: bazel run //tools/git:commit -- -m \"fix(scope): ...\" <paths>"],
            );
        }
    }

    if !agent.is_empty() {
        let exports = match state.agent_exports(&agent) {
            Ok(e) => e,
            Err(rc) => return rc,
        };
        // Deliberate divergence from git.sh: parse only `export K=v` and `export K='v'`
        // lines emitted by `agent-app.sh env` instead of evaluating arbitrary shell via `eval`.
        let Some(ident_pairs) = parse_identity_exports_bytes(&exports) else {
            let instead = bconcat(&[b"check it: bazel run //tools/agent-app -- env ", &agent]);
            return refuse_bytes(
                &state.prog,
                &state.name,
                &bconcat(&[
                    b"agent-app printed no complete git identity for ",
                    &agent,
                    b"; nothing was committed",
                ]),
                &[&instead],
            );
        };
        for (k, v) in ident_pairs {
            env::set_var(OsStr::from_bytes(&k), OsStr::from_bytes(&v));
        }
    }

    if all {
        let rc = git_status_bytes(&state.prog, 274, &[b"add", b"-A"], &[], false, false);
        if rc != 0 {
            return rc;
        }
    } else if !paths.is_empty() {
        let mut tracked: Vec<Vec<u8>> = Vec::new();
        let mut rest: Vec<Vec<u8>> = Vec::new();
        for p in &paths {
            let full = bconcat(&[&state.wd, b"/", p]);
            if !Path::new(OsStr::from_bytes(&full)).is_dir()
                && git_status_bytes(
                    &state.prog,
                    284,
                    &[
                        b"--literal-pathspecs",
                        b"-C",
                        &state.wd,
                        b"ls-files",
                        b"--error-unmatch",
                        b"--",
                        p,
                    ],
                    &[],
                    true,
                    true,
                ) == 0
            {
                tracked.push(p.clone());
            } else {
                rest.push(p.clone());
            }
        }
        if !tracked.is_empty() {
            let mut add_args: Vec<&[u8]> = vec![
                b"--literal-pathspecs",
                b"-C",
                &state.wd,
                b"add",
                b"-f",
                b"--",
            ];
            for t in &tracked {
                add_args.push(t.as_slice());
            }
            if git_status_bytes(&state.prog, 291, &add_args, &[], false, false) != 0 {
                let joined = tracked.join(&b' ');
                let instead = bconcat(&[
                    b"check the paths, relative to ",
                    &state.wd,
                    b": git status --short",
                ]);
                return refuse_bytes(
                    &state.prog,
                    &state.name,
                    &bconcat(&[b"could not stage ", &joined, b" (see git's message above)"]),
                    &[&instead],
                );
            }
        }
        if !rest.is_empty() {
            let mut add_args: Vec<&[u8]> = vec![b"-C", &state.wd, b"add", b"--"];
            for r in &rest {
                add_args.push(r.as_slice());
            }
            if git_status_bytes(&state.prog, 296, &add_args, &[], false, false) != 0 {
                let joined = rest.join(&b' ');
                let instead = bconcat(&[
                    b"check the paths, relative to ",
                    &state.wd,
                    b": git status --short",
                ]);
                return refuse_bytes(
                    &state.prog,
                    &state.name,
                    &bconcat(&[b"could not stage ", &joined, b" (see git's message above)"]),
                    &[&instead],
                );
            }
        }
    }

    if merging {
        let unmerged = match state.conflicted_files() {
            Ok(u) => u,
            Err(rc) => return rc,
        };
        if !unmerged.is_empty() {
            if echo_stderr(
                &state.prog,
                307,
                &bconcat(&[
                    &state.name,
                    b": refused: these files still have merge conflicts:",
                ]),
            )
            .is_err()
            {
                return 1;
            }
            let mut indented = Vec::new();
            for line in unmerged.split(|&b| b == b'\n') {
                indented.extend_from_slice(b"    ");
                indented.extend_from_slice(line);
                indented.push(b'\n');
            }
            if printf_stderr(&state.prog, 308, &indented).is_err() {
                return 1;
            }
            if echo_stderr(
                &state.prog,
                309,
                b"  instead: fix them, then stage and conclude in one step:",
            )
            .is_err()
            {
                return 1;
            }
            let joined: Vec<u8> = unmerged
                .iter()
                .map(|&b| if b == b'\n' { b' ' } else { b })
                .collect();
            if echo_stderr(
                &state.prog,
                310,
                &bconcat(&[b"    bazel run //tools/git:commit -- ", &joined]),
            )
            .is_err()
            {
                return 1;
            }
            if echo_stderr(
                &state.prog,
                311,
                b"  or drop the merge: bazel run //tools/git:sync -- --abort",
            )
            .is_err()
            {
                return 1;
            }
            return 1;
        }
        let (_rc1, diff_head) = git_output_bytes(
            &state.prog,
            318,
            &[b"diff", b"--cached", b"--name-only", b"HEAD"],
            &[],
            false,
        );
        let (_rc2, diff_merge) = git_output_bytes(
            &state.prog,
            318,
            &[b"diff", b"--cached", b"--name-only", b"MERGE_HEAD"],
            &[],
            false,
        );
        let both = sorted_intersection_bytes(&diff_head, &diff_merge);
        let mut markers: Vec<Vec<u8>> = Vec::new();
        for f in both {
            markers.extend(find_staged_conflict_markers(&f));
        }
        if !markers.is_empty() {
            if echo_stderr(
                &state.prog,
                326,
                &bconcat(&[
                    &state.name,
                    b": refused: conflict markers are still in the staged files:",
                ]),
            )
            .is_err()
            {
                return 1;
            }
            let mut indented = Vec::new();
            for m in &markers {
                indented.extend_from_slice(b"    ");
                indented.extend_from_slice(m);
                indented.push(b'\n');
            }
            if printf_stderr(&state.prog, 327, &indented).is_err() {
                return 1;
            }
            if echo_stderr(
                &state.prog,
                328,
                b"  instead: remove the <<<<<<< / >>>>>>> sections, then:",
            )
            .is_err()
            {
                return 1;
            }
            let raw_files: Vec<Vec<u8>> = markers
                .iter()
                .map(|m| m.split(|&b| b == b':').next().unwrap_or(m).to_vec())
                .collect();
            let unique_files = locale_sort_unique_bytes(raw_files);
            let mut files_with_trailing_space = Vec::new();
            for uf in unique_files {
                files_with_trailing_space.extend_from_slice(&uf);
                files_with_trailing_space.push(b' ');
            }
            if echo_stderr(
                &state.prog,
                329,
                &bconcat(&[
                    b"    bazel run //tools/git:commit -- ",
                    &files_with_trailing_space,
                ]),
            )
            .is_err()
            {
                return 1;
            }
            if echo_stderr(
                &state.prog,
                330,
                b"  or drop the merge: bazel run //tools/git:sync -- --abort",
            )
            .is_err()
            {
                return 1;
            }
            return 1;
        }
    } else if git_status_bytes(
        &state.prog,
        334,
        &[b"diff", b"--cached", b"--quiet"],
        &[],
        false,
        false,
    ) == 0
    {
        return refuse_bytes(
            &state.prog,
            &state.name,
            b"nothing is staged, so there is nothing to commit",
            &[
                b"name what to commit: bazel run //tools/git:commit -- -m \"...\" <paths>",
                b"or everything changed: bazel run //tools/git:commit -- -m \"...\" --all",
            ],
        );
    }

    match state.scan("--staged") {
        Ok(true) => {}
        Ok(false) => {
            return refuse_bytes(
                &state.prog,
                &state.name,
                b"the secret scan did not pass, so nothing was committed (your changes are still staged)",
                &[b"fix what it names above, then run the same commit again"],
            );
        }
        Err(rc) => return rc,
    }

    let mut commit_args: Vec<Vec<u8>> = vec![b"commit".to_vec(), b"-q".to_vec()];
    if !fixup.is_empty() {
        let commit_spec = bconcat(&[&fixup, b"^{commit}"]);
        let (rc, target) = git_output_bytes(
            &state.prog,
            348,
            &[b"rev-parse", b"--verify", &commit_spec],
            &[],
            false,
        );
        if rc != 0 {
            return rc;
        }
        commit_args.push(bconcat(&[b"--fixup=", &target]));
    } else if !msg_file.is_empty() {
        commit_args.push(b"-F".to_vec());
        commit_args.push(msg_file);
        commit_args.push(b"--cleanup=strip".to_vec());
    } else if !msgs.is_empty() {
        for m in &msgs {
            commit_args.push(b"-m".to_vec());
            commit_args.push(m.clone());
        }
    } else {
        commit_args.push(b"--no-edit".to_vec());
        commit_args.push(b"--cleanup=strip".to_vec());
    }

    let commit_arg_refs: Vec<&[u8]> = commit_args.iter().map(|s| s.as_slice()).collect();
    if git_status_bytes(
        &state.prog,
        357,
        &commit_arg_refs,
        &[("GIT_EDITOR", ":")],
        false,
        false,
    ) != 0
    {
        return refuse_bytes(
            &state.prog,
            &state.name,
            b"git commit failed (see above); nothing was committed",
            &[b"fix what git reports, then run the same commit again"],
        );
    }

    let (_rc1, short_head) = git_output_bytes(
        &state.prog,
        360,
        &[b"rev-parse", b"--short", b"HEAD"],
        &[],
        false,
    );
    let (_rc2, subj) = git_output_bytes(
        &state.prog,
        360,
        &[b"log", b"-1", b"--format=%s"],
        &[],
        false,
    );
    if echo_stdout(
        &state.prog,
        360,
        &bconcat(&[
            &state.name,
            b": committed ",
            &short_head,
            b" on ",
            &state.branch,
            b": ",
            &subj,
        ]),
    )
    .is_err()
    {
        return 1;
    }
    let (_rc3, author_full) = git_output_bytes(
        &state.prog,
        361,
        &[b"log", b"-1", b"--format=%an <%ae>"],
        &[],
        false,
    );
    if echo_stdout(&state.prog, 361, &bconcat(&[b"  author: ", &author_full])).is_err() {
        return 1;
    }
    let (_rc4, author_name) = git_output_bytes(
        &state.prog,
        362,
        &[b"log", b"-1", b"--format=%an"],
        &[],
        false,
    );
    if !is_agent_bot_name_bytes(&author_name)
        && echo_stdout(
            &state.prog,
            364,
            b"  note: that is not an agent's bot. Agents commit with --agent <name>.",
        )
        .is_err()
    {
        return 1;
    }
    if !fixup.is_empty() {
        if echo_stdout(
            &state.prog,
            367,
            b"  next: fold it in with: bazel run //tools/git:sync -- --autosquash",
        )
        .is_err()
        {
            return 1;
        }
    } else if echo_stdout(&state.prog, 369, b"  next: bazel run //tools/git:push").is_err() {
        return 1;
    }
    0
}

fn cmd_push(state: &EnvState, args: &[OsString]) -> i32 {
    let mut agent: Vec<u8> = Vec::new();
    let mut lease = false;
    let mut dry = false;

    let mut i = 0;
    while i < args.len() {
        let arg = args[i].as_bytes();
        match arg {
            b"-h" | b"--help" => {
                return print_usage(&state.prog);
            }
            b"--agent" => {
                if i + 1 >= args.len() {
                    return bad_args_bytes(&state.prog, &state.name, b"--agent needs a name");
                }
                agent = args[i + 1].as_bytes().to_vec();
                i += 1;
            }
            b"--force-with-lease" => {
                lease = true;
            }
            b"--dry-run" | b"-n" => {
                dry = true;
            }
            b"-f" | b"--force" => {
                return refuse_bytes(
                    &state.prog,
                    &state.name,
                    &bconcat(&[
                        arg,
                        b" is not offered. A plain force push can throw away commits someone else pushed",
                    ]),
                    &[b"bazel run //tools/git:push -- --force-with-lease   (only overwrites what you last fetched)"],
                );
            }
            _ if arg.starts_with(b"--force=") || arg.starts_with(b"--force-with-lease=") => {
                return refuse_bytes(
                    &state.prog,
                    &state.name,
                    &bconcat(&[
                        arg,
                        b" is not offered. A plain force push can throw away commits someone else pushed",
                    ]),
                    &[b"bazel run //tools/git:push -- --force-with-lease   (only overwrites what you last fetched)"],
                );
            }
            _ if arg.starts_with(b"-") => {
                return bad_args_bytes(
                    &state.prog,
                    &state.name,
                    &bconcat(&[b"unknown flag: ", arg]),
                );
            }
            _ => {
                return bad_args_bytes(
                    &state.prog,
                    &state.name,
                    b"push takes no branch or remote: it always pushes the current branch to origin under the same name",
                );
            }
        }
        i += 1;
    }

    if let Err(rc) = state.no_op_in_progress() {
        return rc;
    }
    if let Err(rc) = state.need_work_branch() {
        return rc;
    }
    if state.in_merge() {
        return refuse_bytes(
            &state.prog,
            &state.name,
            b"a merge is in progress and not concluded",
            &[
                b"finish it: bazel run //tools/git:commit",
                b"or drop it: bazel run //tools/git:sync -- --abort",
            ],
        );
    }
    if git_status_bytes(
        &state.prog,
        399,
        &[b"remote", b"get-url", b"origin"],
        &[],
        true,
        true,
    ) != 0
    {
        return refuse_bytes(
            &state.prog,
            &state.name,
            b"this repository has no remote called origin",
            &[b"add it, then retry"],
        );
    }

    match state.scan("--unpushed") {
        Ok(true) => {}
        Ok(false) => {
            return refuse_bytes(
                &state.prog,
                &state.name,
                b"the secret scan did not pass, so nothing was pushed",
                &[
                    b"fix it in a new commit and fold it in:",
                    b"  bazel run //tools/git:commit -- --fixup <sha> <file>",
                    b"  bazel run //tools/git:sync -- --autosquash",
                    b"then: bazel run //tools/git:push -- --force-with-lease",
                ],
            );
        }
        Err(rc) => return rc,
    }

    if !agent.is_empty() {
        let exports = match state.agent_exports(&agent) {
            Ok(e) => e,
            Err(rc) => return rc,
        };
        // Deliberate divergence from git.sh: parse only `export K=v` and `export K='v'`
        // lines emitted by `agent-app.sh env` instead of evaluating arbitrary shell via `eval`.
        for line in exports.split(|&b| b == b'\n') {
            if let Some((k, v)) = parse_export_line_bytes(line) {
                env::set_var(OsStr::from_bytes(&k), OsStr::from_bytes(&v));
            }
        }
        let committer = env_os_non_empty("GIT_COMMITTER_NAME").unwrap_or_else(|| agent.clone());
        if echo_stdout(
            &state.prog,
            417,
            &bconcat(&[&state.name, b": pushing as ", &committer]),
        )
        .is_err()
        {
            return 1;
        }
    }

    let mut push_args: Vec<&[u8]> = vec![b"push", b"-u", b"--no-follow-tags"];
    if dry {
        push_args.push(b"--dry-run");
    }
    if lease {
        push_args.push(b"--force-with-lease");
        push_args.push(b"--force-if-includes");
    }
    let refspec = bconcat(&[
        b"refs/heads/",
        &state.branch,
        b":refs/heads/",
        &state.branch,
    ]);
    push_args.push(b"origin");
    push_args.push(&refspec);

    if git_status_bytes(&state.prog, 427, &push_args, &[], false, false) != 0 {
        if !lease {
            return refuse_bytes(
                &state.prog,
                &state.name,
                b"the push was rejected (git's reason is above). If origin has commits you do not, catch up first",
                &[
                    b"bazel run //tools/git:sync, then push again",
                    b"if you rewrote this branch (sync, --autosquash): bazel run //tools/git:push -- --force-with-lease",
                ],
            );
        }
        return refuse_bytes(
            &state.prog,
            &state.name,
            b"the push was rejected (git's reason is above). --force-with-lease refuses when origin has commits you have not fetched",
            &[b"bazel run //tools/git:sync, check the result, then push again"],
        );
    }
    if dry {
        if echo_stdout(
            &state.prog,
            436,
            &bconcat(&[&state.name, b": dry run: nothing was pushed"]),
        )
        .is_err()
        {
            return 1;
        }
        return 0;
    }
    let (_rc, short_head) = git_output_bytes(
        &state.prog,
        437,
        &[b"rev-parse", b"--short", b"HEAD"],
        &[],
        false,
    );
    if echo_stdout(
        &state.prog,
        437,
        &bconcat(&[
            &state.name,
            b": pushed ",
            &state.branch,
            b" (",
            &short_head,
            b") to origin; it now tracks origin/",
            &state.branch,
        ]),
    )
    .is_err()
    {
        return 1;
    }
    0
}

fn cmd_sync(state: &EnvState, args: &[OsString]) -> i32 {
    let mut mode = "rebase";
    let mut autosquash = false;
    let mut abort = false;
    let mut keep_base = false;

    for os_arg in args {
        let arg = os_arg.as_bytes();
        match arg {
            b"-h" | b"--help" => {
                return print_usage(&state.prog);
            }
            b"--autosquash" => autosquash = true,
            b"--keep-base" => keep_base = true,
            b"--merge" => mode = "merge",
            b"--abort" => abort = true,
            _ if arg.starts_with(b"-") => {
                return bad_args_bytes(
                    &state.prog,
                    &state.name,
                    &bconcat(&[b"unknown flag: ", arg]),
                );
            }
            _ => {
                return bad_args_bytes(
                    &state.prog,
                    &state.name,
                    b"sync takes no branch: it always brings origin/main into the current branch",
                );
            }
        }
    }
    if mode == "merge" && autosquash {
        return bad_args_bytes(
            &state.prog,
            &state.name,
            b"--autosquash rewrites commits; it goes with a rebase, not --merge",
        );
    }
    if mode == "merge" && keep_base {
        return bad_args_bytes(
            &state.prog,
            &state.name,
            b"--keep-base goes with a rebase, not --merge",
        );
    }

    if abort {
        let br_or_head: &[u8] = if state.branch.is_empty() {
            b"HEAD"
        } else {
            &state.branch
        };
        if state.in_merge() {
            let rc = git_status_bytes(&state.prog, 462, &[b"merge", b"--abort"], &[], false, false);
            if rc != 0 {
                return rc;
            }
            if echo_stdout(
                &state.prog,
                462,
                &bconcat(&[
                    &state.name,
                    b": dropped the unfinished merge; ",
                    br_or_head,
                    b" is back where it was",
                ]),
            )
            .is_err()
            {
                return 1;
            }
        } else if state.in_rebase() {
            let rc = git_status_bytes(
                &state.prog,
                464,
                &[b"rebase", b"--abort"],
                &[],
                false,
                false,
            );
            if rc != 0 {
                return rc;
            }
            if echo_stdout(
                &state.prog,
                464,
                &bconcat(&[
                    &state.name,
                    b": dropped the unfinished rebase; ",
                    br_or_head,
                    b" is back where it was",
                ]),
            )
            .is_err()
            {
                return 1;
            }
        } else if echo_stdout(
            &state.prog,
            466,
            &bconcat(&[
                &state.name,
                b": no merge or rebase is in progress; nothing to abort",
            ]),
        )
        .is_err()
        {
            return 1;
        }
        return 0;
    }

    if state.branch == b"main" {
        return refuse_bytes(
            &state.prog,
            &state.name,
            b"this is main, which only ever fast-forwards",
            &[b"git pull --ff-only"],
        );
    }
    if let Err(rc) = state.no_op_in_progress() {
        return rc;
    }
    if let Err(rc) = state.need_work_branch() {
        return rc;
    }
    if state.in_merge() {
        return refuse_bytes(
            &state.prog,
            &state.name,
            b"a merge is already in progress",
            &[
                b"finish it: bazel run //tools/git:commit",
                b"or drop it: bazel run //tools/git:sync -- --abort",
            ],
        );
    }

    let (rc_dirty, dirty) = git_output_bytes(
        &state.prog,
        482,
        &[b"status", b"--porcelain", b"--untracked-files=no"],
        &[],
        false,
    );
    if rc_dirty != 0 {
        return rc_dirty;
    }
    if !dirty.is_empty() {
        if echo_stderr(
            &state.prog,
            485,
            &bconcat(&[
                &state.name,
                b": refused: you have uncommitted changes, and sync never stashes them",
            ]),
        )
        .is_err()
        {
            return 1;
        }
        if echo_stderr(
            &state.prog,
            486,
            b"  (the stash is shared by every worktree, so another session could take yours):",
        )
        .is_err()
        {
            return 1;
        }
        let pipe_rc = run_dirty_pipeline(&state.prog, &dirty);
        if pipe_rc != 0 {
            return pipe_rc;
        }
        if echo_stderr(
            &state.prog,
            488,
            b"  instead: commit them first: bazel run //tools/git:commit -- -m \"...\" <paths>",
        )
        .is_err()
        {
            return 1;
        }
        return 1;
    }

    if git_status_bytes(
        &state.prog,
        493,
        &[b"fetch", b"-q", b"origin", b"main"],
        &[],
        false,
        false,
    ) != 0
    {
        return refuse_bytes(
            &state.prog,
            &state.name,
            b"could not fetch origin/main (git's reason is above); nothing changed",
            &[b"check the network, then retry"],
        );
    }
    let (rc_b, before) = git_output_bytes(&state.prog, 496, &[b"rev-parse", b"HEAD"], &[], false);
    if rc_b != 0 {
        return rc_b;
    }
    let (rc_o, onto) = git_output_bytes(
        &state.prog,
        497,
        &[b"rev-parse", b"--short", b"origin/main"],
        &[],
        false,
    );
    if rc_o != 0 {
        return rc_o;
    }

    if mode == "merge" {
        if git_status_bytes(
            &state.prog,
            500,
            &[
                b"-c",
                b"merge.autoStash=false",
                b"merge",
                b"-q",
                b"--no-edit",
                b"origin/main",
            ],
            &[("GIT_EDITOR", ":")],
            false,
            false,
        ) == 0
        {
            if echo_stdout(
                &state.prog,
                501,
                &bconcat(&[
                    &state.name,
                    b": merged origin/main (",
                    &onto,
                    b") into ",
                    &state.branch,
                ]),
            )
            .is_err()
            {
                return 1;
            }
            if echo_stdout(&state.prog, 502, b"  next: bazel run //tools/git:push").is_err() {
                return 1;
            }
            return 0;
        }
        let files = match state.conflicted_files() {
            Ok(f) => f,
            Err(rc) => return rc,
        };
        if files.is_empty() || !state.in_merge() {
            if state.in_merge() {
                let rc =
                    git_status_bytes(&state.prog, 508, &[b"merge", b"--abort"], &[], false, false);
                if rc != 0 {
                    return rc;
                }
            }
            return refuse_bytes(
                &state.prog,
                &state.name,
                &bconcat(&[
                    b"the merge stopped (git's reason is above); ",
                    &state.branch,
                    b" is unchanged",
                ]),
                &[b"fix what git reports, then retry"],
            );
        }
        if echo_stderr(
            &state.prog,
            512,
            &bconcat(&[
                &state.name,
                b": merging origin/main (",
                &onto,
                b") into ",
                &state.branch,
                b" hit conflicts in:",
            ]),
        )
        .is_err()
        {
            return 1;
        }
        let mut indented = Vec::new();
        for f in files.split(|&b| b == b'\n') {
            indented.extend_from_slice(b"    ");
            indented.extend_from_slice(f);
            indented.push(b'\n');
        }
        if printf_stderr(&state.prog, 513, &indented).is_err() {
            return 1;
        }
        if echo_stderr(
            &state.prog,
            514,
            b"  The merge is left in progress so you can resolve them.",
        )
        .is_err()
        {
            return 1;
        }
        if echo_stderr(
            &state.prog,
            515,
            b"  To finish: fix each file, then stage them and conclude the merge in one step:",
        )
        .is_err()
        {
            return 1;
        }
        let joined: Vec<u8> = files
            .iter()
            .map(|&b| if b == b'\n' { b' ' } else { b })
            .collect();
        let joined = joined.strip_suffix(b" ").unwrap_or(&joined);
        if echo_stderr(
            &state.prog,
            516,
            &bconcat(&[b"    bazel run //tools/git:commit -- ", joined]),
        )
        .is_err()
        {
            return 1;
        }
        if echo_stderr(
            &state.prog,
            517,
            b"  To give up: bazel run //tools/git:sync -- --abort",
        )
        .is_err()
        {
            return 1;
        }
        return 1;
    }

    let (rc_m, merges) = git_output_bytes(
        &state.prog,
        525,
        &[b"rev-list", b"--merges", b"origin/main..HEAD"],
        &[],
        false,
    );
    if rc_m != 0 {
        return rc_m;
    }
    if !merges.is_empty() {
        let count = merges
            .split(|&b| b == b'\n')
            .filter(|s| !s.is_empty())
            .count();
        let count_str = count.to_string();
        return refuse_bytes(
            &state.prog,
            &state.name,
            &bconcat(&[
                &state.branch,
                b" has ",
                count_str.as_bytes(),
                b" merge commit(s) since origin/main; a rebase would drop them",
            ]),
            &[b"keep merging: bazel run //tools/git:sync -- --merge"],
        );
    }

    let mut rebase_args: Vec<&[u8]> = vec![b"-c", b"rebase.autoStash=false", b"rebase", b"-q"];
    if autosquash {
        rebase_args.push(b"-i");
        rebase_args.push(b"--autosquash");
    }
    if keep_base {
        rebase_args.push(b"--keep-base");
    }
    rebase_args.push(b"origin/main");

    if git_status_bytes(
        &state.prog,
        536,
        &rebase_args,
        &[("GIT_SEQUENCE_EDITOR", ":"), ("GIT_EDITOR", ":")],
        false,
        false,
    ) == 0
    {
        let (_rc_after, after) =
            git_output_bytes(&state.prog, 537, &[b"rev-parse", b"HEAD"], &[], false);
        if after == before {
            if echo_stdout(
                &state.prog,
                538,
                &bconcat(&[
                    &state.name,
                    b": ",
                    &state.branch,
                    b" is already up to date with origin/main (",
                    &onto,
                    b")",
                ]),
            )
            .is_err()
            {
                return 1;
            }
            return 0;
        }
        let folded_suffix: &[u8] = if autosquash {
            b", fixups folded in"
        } else {
            b""
        };
        let remote_branch_ref = bconcat(&[b"refs/remotes/origin/", &state.branch]);
        if keep_base {
            if echo_stdout(
                &state.prog,
                542,
                &bconcat(&[
                    &state.name,
                    b": rewrote ",
                    &state.branch,
                    b" in place",
                    folded_suffix,
                    b"; origin/main was not brought in",
                ]),
            )
            .is_err()
            {
                return 1;
            }
            if echo_stdout(
                &state.prog,
                543,
                b"  bring it in later with: bazel run //tools/git:sync",
            )
            .is_err()
            {
                return 1;
            }
            if git_status_bytes(
                &state.prog,
                544,
                &[b"rev-parse", b"--verify", b"--quiet", &remote_branch_ref],
                &[],
                true,
                false,
            ) == 0
                && echo_stdout(
                    &state.prog,
                    545,
                    &bconcat(&[
                        b"  origin/",
                        &state.branch,
                        b" has the old commits; publish with: bazel run //tools/git:push -- --force-with-lease",
                    ]),
                )
                .is_err()
            {
                return 1;
            }
            return 0;
        }
        if echo_stdout(
            &state.prog,
            548,
            &bconcat(&[
                &state.name,
                b": rebased ",
                &state.branch,
                b" onto origin/main (",
                &onto,
                b")",
                folded_suffix,
            ]),
        )
        .is_err()
        {
            return 1;
        }
        if git_status_bytes(
            &state.prog,
            549,
            &[b"rev-parse", b"--verify", b"--quiet", &remote_branch_ref],
            &[],
            true,
            false,
        ) == 0
        {
            if echo_stdout(
                &state.prog,
                550,
                &bconcat(&[
                    b"  origin/",
                    &state.branch,
                    b" still has the old commits. Publish the new ones with:",
                ]),
            )
            .is_err()
            {
                return 1;
            }
            if echo_stdout(
                &state.prog,
                551,
                b"    bazel run //tools/git:push -- --force-with-lease",
            )
            .is_err()
            {
                return 1;
            }
        } else if echo_stdout(&state.prog, 553, b"  next: bazel run //tools/git:push").is_err() {
            return 1;
        }
        return 0;
    }

    let files = match state.conflicted_files() {
        Ok(f) => f,
        Err(rc) => return rc,
    };
    if state.in_rebase() {
        let rc = git_status_bytes(
            &state.prog,
            559,
            &[b"rebase", b"--abort"],
            &[],
            false,
            false,
        );
        if rc != 0 {
            return rc;
        }
    }
    if !files.is_empty() {
        if echo_stderr(
            &state.prog,
            562,
            &bconcat(&[
                &state.name,
                b": rebasing ",
                &state.branch,
                b" onto origin/main (",
                &onto,
                b") hit conflicts in:",
            ]),
        )
        .is_err()
        {
            return 1;
        }
        let mut indented = Vec::new();
        for f in files.split(|&b| b == b'\n') {
            indented.extend_from_slice(b"    ");
            indented.extend_from_slice(f);
            indented.push(b'\n');
        }
        if printf_stderr(&state.prog, 563, &indented).is_err() {
            return 1;
        }
        if echo_stderr(
            &state.prog,
            564,
            &bconcat(&[
                b"  The rebase was undone; ",
                &state.branch,
                b" is exactly as it was.",
            ]),
        )
        .is_err()
        {
            return 1;
        }
        if echo_stderr(
            &state.prog,
            565,
            b"  instead: merge main in and resolve the conflicts once:",
        )
        .is_err()
        {
            return 1;
        }
        if echo_stderr(
            &state.prog,
            566,
            b"    bazel run //tools/git:sync -- --merge",
        )
        .is_err()
        {
            return 1;
        }
        return 1;
    }
    refuse_bytes(
        &state.prog,
        &state.name,
        &bconcat(&[
            b"the rebase stopped (git's reason is above) and was undone; ",
            &state.branch,
            b" is unchanged",
        ]),
        &[b"fix what git reports, then retry, or merge instead: bazel run //tools/git:sync -- --merge"],
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_usage_text_extracts_header() {
        let text = usage_text();
        assert!(text.starts_with(
            "git.sh — the git writes agents make, with the safety checks built in.\n"
        ));
        assert!(text.contains("Save work:\n"));
        assert!(text.contains("Publish work:\n"));
        assert!(text.contains("Catch up with main:\n"));
        assert!(text.ends_with("are printed), 2 bad arguments.\n\n"));
        assert!(!text.contains("set -euo"));
    }

    #[test]
    fn test_conventional_commit_validation() {
        assert!(is_valid_commit_subject("feat: add new feature"));
        assert!(is_valid_commit_subject("fix(git): handle edge case"));
        assert!(is_valid_commit_subject("refactor(core)!: breaking change"));
        assert!(is_valid_commit_subject("chore!: drop old support"));
        assert!(is_valid_commit_subject("Revert \"fix: x (#12)\""));

        assert!(!is_valid_commit_subject("added a file"));
        assert!(!is_valid_commit_subject("feat(): empty scope"));
        assert!(!is_valid_commit_subject("feat(unclosed: bad scope"));
        assert!(!is_valid_commit_subject("feat: "));
        assert!(!is_valid_commit_subject("feat:"));
        assert!(!is_valid_commit_subject("Revert fix x"));
        assert!(!is_valid_commit_subject("Revert \"\""));
        // grep -E '^Revert ".+"' lets the first character be a quote.
        assert!(is_valid_commit_subject("Revert \"\"x\""));
        assert!(is_valid_commit_subject("Revert \"\"\""));
        assert!(is_valid_commit_subject("Revert \"é\""));
        assert!(!is_valid_commit_subject("unknown(scope): msg"));
    }

    #[test]
    fn test_extract_subject_from_file_content() {
        let content = "# Comment line\n\n# Another comment\ndocs(a): from a file\n\nBody line.\n";
        assert_eq!(
            extract_subject_from_file_content(content),
            "docs(a): from a file"
        );
        assert_eq!(extract_subject_from_file_content("# only comments\n\n"), "");
    }

    #[test]
    fn test_extract_subject_from_message() {
        assert_eq!(
            extract_subject_from_message("feat(x): first line\n\nsecond line"),
            "feat(x): first line"
        );
        assert_eq!(extract_subject_from_message(""), "");
    }

    #[test]
    fn test_is_agent_bot_name() {
        assert!(is_agent_bot_name("vitruvian-wren-agent[bot]"));
        assert!(is_agent_bot_name("vitruvian-beacon-agent[bot]"));
        assert!(!is_agent_bot_name("tester"));
        assert!(!is_agent_bot_name("vitruvian-wren"));
    }

    #[test]
    fn test_conflict_markers() {
        let content = "line 1\n<<<<<<< HEAD\nours\n||||||| base\nbase\n=======\ntheirs\n>>>>>>> origin/main\n<<<<<<<not a marker\n";
        let markers = find_conflict_markers("shared.txt", content);
        assert_eq!(
            markers,
            vec!["shared.txt:2", "shared.txt:4", "shared.txt:8"]
        );
    }

    #[test]
    fn test_sorted_intersection() {
        let a = "b.txt\na.txt\nc.txt";
        let b = "c.txt\na.txt\nd.txt";
        assert_eq!(sorted_intersection(a, b), vec!["a.txt", "c.txt"]);
    }

    #[test]
    fn test_parse_identity_exports() {
        let exports = "\
export GH_TOKEN=token-for-wren
export GIT_AUTHOR_NAME='vitruvian-wren-agent[bot]'
export GIT_AUTHOR_EMAIL='4521094+vitruvian-wren-agent[bot]@users.noreply.github.com'
export GIT_COMMITTER_NAME='vitruvian-wren-agent[bot]'
export GIT_COMMITTER_EMAIL='4521094+vitruvian-wren-agent[bot]@users.noreply.github.com'";
        let parsed = parse_identity_exports(exports).expect("should parse 4 identity vars");
        assert_eq!(parsed.len(), 4);
        assert_eq!(
            parsed[0],
            (
                "GIT_AUTHOR_NAME".to_string(),
                "vitruvian-wren-agent[bot]".to_string()
            )
        );
        assert!(parse_identity_exports("export GH_TOKEN=abc").is_none());
    }

    #[test]
    fn test_repo_mapping_and_manifest_lookup() {
        let mapping = ",bazel_tools,bazel_tools\n,multitool,rules_multitool++multitool+multitool\n,vitruvian_core,_main\n";
        assert_eq!(
            parse_repo_mapping(mapping, "", "multitool"),
            Some("rules_multitool++multitool+multitool".to_string())
        );
        assert_eq!(parse_repo_mapping(mapping, "", "nonexistent"), None);

        let manifest = "_main/.gitleaks.toml /path/to/.gitleaks.toml\nrules_multitool++multitool+multitool/tools/gitleaks/gitleaks /path/to/gitleaks\n";
        assert_eq!(
            lookup_in_manifest(
                manifest,
                "rules_multitool++multitool+multitool/tools/gitleaks/gitleaks"
            ),
            Some("/path/to/gitleaks".to_string())
        );
    }

    #[test]
    fn test_clamp_wd_to_here() {
        assert_eq!(clamp_wd_to_here("/repo/wt", "/repo/wt"), "/repo/wt");
        assert_eq!(clamp_wd_to_here("/repo/wt/sub", "/repo/wt"), "/repo/wt/sub");
        assert_eq!(clamp_wd_to_here("/repo/wt_other", "/repo/wt"), "/repo/wt");
        assert_eq!(clamp_wd_to_here("/other", "/repo/wt"), "/repo/wt");
    }

    #[test]
    fn test_locale_sort_unique_bytes() {
        let items = vec![
            b"b.txt".to_vec(),
            b"a.txt".to_vec(),
            b"b.txt".to_vec(),
            b"c.txt".to_vec(),
        ];
        assert_eq!(
            locale_sort_unique_bytes(items),
            vec![b"a.txt".to_vec(), b"b.txt".to_vec(), b"c.txt".to_vec()]
        );
    }
}
