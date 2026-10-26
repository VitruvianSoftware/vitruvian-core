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

//! The platform-e2e master runner: runs tiers 1-4 (tier*_test.sh, next to
//! this binary), counts their TAP `ok` / `not ok` lines and reports in text,
//! TAP or JSON. A port of runner.sh with the same options, output, exit
//! codes and workspace resolution; the JSON report is written through serde
//! in the layout Python's `json.dumps(..., indent=2)` gives.
//!
//! The script runs under `set -uo pipefail` (no `-e`): a failing `cd` is
//! reported and the run goes on. One script behaviour is NOT reproduced: with
//! no tier selected (`--tier 5`), bash before 4.4 (macOS's 3.2) stops on the
//! empty TIER_RESULTS array under `set -u`; this follows bash 4.4+, which
//! reports the empty run.

use std::ffi::OsString;
use std::fs;
use std::os::unix::ffi::{OsStrExt, OsStringExt};
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use serde::Serialize;

const RULE: &str =
    "================================================================================";

/// The four tiers: number, name, script, the count assumed when a passing
/// script prints no `ok` lines.
pub const TIERS: [(&str, &str, &str, u64); 4] = [
    ("1", "Feature Coverage", "tier1_feature_test.sh", 60),
    ("2", "Boundary & Edge Cases", "tier2_boundary_test.sh", 60),
    (
        "3",
        "Pairwise Combinations",
        "tier3_combination_test.sh",
        12,
    ),
    ("4", "Real-World Workloads", "tier4_workload_test.sh", 6),
];

#[derive(Clone, Debug, PartialEq)]
pub struct TierResult {
    pub num: String,
    pub name: String,
    pub passed: bool,
    pub ok: u64,
    pub not_ok: u64,
    pub ms: i64,
}

#[derive(Serialize)]
struct JsonTier<'a> {
    tier: i64,
    name: &'a str,
    status: &'a str,
    passed: u64,
    failed: u64,
    duration_ms: i64,
}

#[derive(Serialize)]
struct JsonReport<'a> {
    total_tiers: usize,
    passed_tiers: usize,
    failed_tiers: usize,
    total_tests: u64,
    passed_tests: u64,
    failed_tests: u64,
    duration_ms: i64,
    tiers: Vec<JsonTier<'a>>,
}

fn out(b: &[u8]) {
    use std::io::Write;
    let mut o = std::io::stdout();
    let _ = o.write_all(b);
    let _ = o.flush();
}

fn err(b: &[u8]) {
    use std::io::Write;
    let _ = std::io::stderr().write_all(b);
}

fn line(s: &str) {
    out(format!("{}\n", s).as_bytes());
}

fn now_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

fn prog() -> Vec<u8> {
    std::env::args_os()
        .next()
        .map(OsString::into_vec)
        .unwrap_or_default()
}

fn strerror(e: &std::io::Error) -> String {
    let s = e.to_string();
    match s.rfind(" (os error ") {
        Some(i) => s[..i].to_string(),
        None => s,
    }
}

fn bash_diag(line_no: u32, msg: &[u8]) {
    let mut v = prog();
    v.extend_from_slice(format!(": line {}: ", line_no).as_bytes());
    v.extend_from_slice(msg);
    v.push(b'\n');
    err(&v);
}

/// `dirname`.
pub fn dirname(p: &[u8]) -> Vec<u8> {
    let mut s = p;
    while s.len() > 1 && s.ends_with(b"/") {
        s = &s[..s.len() - 1];
    }
    match s.iter().rposition(|&c| c == b'/') {
        None => b".".to_vec(),
        Some(i) => {
            let mut d = &s[..i];
            while d.len() > 1 && d.ends_with(b"/") {
                d = &d[..d.len() - 1];
            }
            if d.is_empty() {
                b"/".to_vec()
            } else {
                d.to_vec()
            }
        }
    }
}

/// `basename`.
pub fn basename(p: &[u8]) -> Vec<u8> {
    let mut s = p;
    while s.len() > 1 && s.ends_with(b"/") {
        s = &s[..s.len() - 1];
    }
    if s == b"/" {
        return b"/".to_vec();
    }
    match s.iter().rposition(|&c| c == b'/') {
        None => s.to_vec(),
        Some(i) => s[i + 1..].to_vec(),
    }
}

fn path(b: &[u8]) -> PathBuf {
    PathBuf::from(OsString::from_vec(b.to_vec()))
}

/// `$(cd -P "$d" && pwd)`: the physical directory, or empty after cd's
/// complaint (`line_no` is the script line it mirrors).
fn physical(d: &[u8], line_no: u32) -> Vec<u8> {
    match fs::canonicalize(path(d)) {
        Ok(p) if p.is_dir() => p.into_os_string().into_vec(),
        Ok(_) => {
            let mut m = b"cd: ".to_vec();
            m.extend_from_slice(d);
            m.extend_from_slice(b": Not a directory");
            bash_diag(line_no, &m);
            Vec::new()
        }
        Err(e) => {
            let mut m = b"cd: ".to_vec();
            m.extend_from_slice(d);
            m.extend_from_slice(b": ");
            m.extend_from_slice(strerror(&e).as_bytes());
            bash_diag(line_no, &m);
            Vec::new()
        }
    }
}

/// bash's $PWD at start: the inherited one when it names the current
/// directory, else the physical current directory.
fn start_pwd() -> Vec<u8> {
    let here = std::env::current_dir().ok();
    if let Some(p) = std::env::var_os("PWD") {
        let pb = p.as_bytes();
        if pb.starts_with(b"/") {
            if let (Ok(a), Some(h)) = (fs::metadata(&p), here.as_ref()) {
                if let Ok(b) = fs::metadata(h) {
                    if a.dev() == b.dev() && a.ino() == b.ino() {
                        return pb.to_vec();
                    }
                }
            }
        }
    }
    here.map(|h| h.into_os_string().into_vec())
        .unwrap_or_default()
}

/// The script's BASH_SOURCE[0]: this program as it was invoked.
fn self_path() -> Vec<u8> {
    let a0 = prog();
    if a0.contains(&b'/') {
        a0
    } else {
        std::env::current_exe()
            .map(|p| p.into_os_string().into_vec())
            .unwrap_or(a0)
    }
}

/// `resolve_workspace_root "$src"`.
pub fn resolve_workspace_root(src: &[u8], pwd: &[u8]) -> Vec<u8> {
    let mut target = src.to_vec();
    while fs::symlink_metadata(path(&target))
        .map(|m| m.file_type().is_symlink())
        .unwrap_or(false)
    {
        let dir = physical(&dirname(&target), 28);
        let link = match fs::read_link(path(&target)) {
            Ok(l) => l.into_os_string().into_vec(),
            Err(_) => Vec::new(),
        };
        target = if link.starts_with(b"/") {
            link
        } else {
            let mut t = dir;
            t.push(b'/');
            t.extend_from_slice(&link);
            t
        };
    }
    let mut cur = physical(&dirname(&target), 32);
    while cur != b"/" && !cur.is_empty() {
        for marker in ["MODULE.bazel", "go.work"] {
            let mut f = cur.clone();
            f.push(b'/');
            f.extend_from_slice(marker.as_bytes());
            if fs::metadata(path(&f)).map(|m| m.is_file()).unwrap_or(false) {
                return cur;
            }
        }
        cur = dirname(&cur);
    }
    match std::env::var_os("BUILD_WORKSPACE_DIRECTORY") {
        Some(v) if !v.is_empty() => v.into_vec(),
        _ => pwd.to_vec(),
    }
}

fn logical(p: &[u8]) -> Vec<u8> {
    let mut parts: Vec<&[u8]> = Vec::new();
    for c in p.split(|&b| b == b'/') {
        match c {
            b"" | b"." => {}
            b".." => {
                parts.pop();
            }
            c => parts.push(c),
        }
    }
    let mut o = Vec::new();
    for c in parts {
        o.push(b'/');
        o.extend_from_slice(c);
    }
    if o.is_empty() {
        o.push(b'/');
    }
    o
}

/// Lines of `<<<"$out"` matching awk's `/^[[:space:]]*<word> /`.
pub fn count(out: &[u8], word: &[u8]) -> u64 {
    out.split(|&c| c == b'\n')
        .filter(|l| {
            let mut s: &[u8] = l;
            while let Some((&c, rest)) = s.split_first() {
                if matches!(c, b' ' | b'\t' | b'\x0b' | b'\x0c' | b'\r') {
                    s = rest;
                } else {
                    break;
                }
            }
            s.starts_with(word) && s.get(word.len()) == Some(&b' ')
        })
        .count() as u64
}

/// `echo "$text"`: bash's echo takes a lone word of -n/-e/-E as options.
pub fn echo_bytes(text: &[u8]) -> Vec<u8> {
    let is_opts = text.len() >= 2
        && text[0] == b'-'
        && text[1..].iter().all(|c| matches!(c, b'n' | b'e' | b'E'));
    if is_opts {
        return if text.contains(&b'n') {
            Vec::new()
        } else {
            b"\n".to_vec()
        };
    }
    let mut v = text.to_vec();
    v.push(b'\n');
    v
}

/// `out="$(bash "$script" 2>&1)" || status=$?`: both streams into one file,
/// in the order written.
fn run_script(script: &[u8]) -> (Vec<u8>, i32) {
    let dir = std::env::var_os("TMPDIR")
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/tmp"));
    let tmp = dir.join(format!(
        ".platform-e2e-runner.{}.{}",
        std::process::id(),
        now_ms()
    ));
    let file = fs::OpenOptions::new()
        .read(true)
        .write(true)
        .create_new(true)
        .open(&tmp)
        .or_else(|_| fs::File::create(&tmp));
    let file = match file {
        Ok(f) => f,
        Err(e) => {
            return (format!("{}\n", strerror(&e)).into_bytes(), 1);
        }
    };
    let _ = fs::remove_file(&tmp);
    let (o, e) = match (file.try_clone(), file.try_clone()) {
        (Ok(a), Ok(b)) => (a, b),
        _ => return (Vec::new(), 1),
    };
    let status = Command::new("bash")
        .arg(OsString::from_vec(script.to_vec()))
        .stdin(Stdio::inherit())
        .stdout(Stdio::from(o))
        .stderr(Stdio::from(e))
        .status();
    let code = match status {
        Ok(st) => {
            use std::os::unix::process::ExitStatusExt;
            st.code().unwrap_or_else(|| 128 + st.signal().unwrap_or(0))
        }
        Err(e) => {
            if e.kind() == std::io::ErrorKind::NotFound {
                127
            } else {
                126
            }
        }
    };
    let mut buf = Vec::new();
    {
        use std::io::{Read, Seek, SeekFrom};
        let mut f = file;
        let _ = f.seek(SeekFrom::Start(0));
        let _ = f.read_to_end(&mut buf);
    }
    buf.retain(|&c| c != 0);
    while buf.last() == Some(&b'\n') {
        buf.pop();
    }
    (buf, code)
}

fn usage(code: i32) -> i32 {
    let name = String::from_utf8_lossy(&basename(&prog())).into_owned();
    out(format!(
        "Usage: {} [options]

Options:
  --tier <1|2|3|4|all>       Execute specific test tier (default: all)
  --format <text|tap|json>   Output format (default: text)
  -v, --verbose              Enable verbose test output
  -h, --help                 Show this help message

Test Tiers:
  Tier 1: Feature Coverage (60 tests across 12 feature areas)
  Tier 2: Boundary Value Analysis (60 boundary and corner cases)
  Tier 3: Pairwise Combinations (12 cross-feature integration scenarios)
  Tier 4: Real-World Workloads (6 end-to-end multi-team application workloads)
",
        name
    )
    .as_bytes());
    code
}

/// The text report's table and verdict.
pub fn text_report(results: &[TierResult], total_ms: i64) -> String {
    let passed_tiers = results.iter().filter(|r| r.passed).count();
    let failed_tiers = results.len() - passed_tiers;
    let ok: u64 = results.iter().map(|r| r.ok).sum();
    let all: u64 = results.iter().map(|r| r.ok + r.not_ok).sum();
    let mut s = String::new();
    s.push('\n');
    s.push_str(RULE);
    s.push_str("\n Execution Matrix & Coverage Verification Summary\n");
    s.push_str(RULE);
    s.push('\n');
    s.push_str(&format!(
        "| {:<6} | {:<25} | {:<8} | {:<8} | {:<8} | {:<10} |\n",
        "Tier", "Description", "Status", "Passed", "Failed", "Duration"
    ));
    s.push_str(
        "|--------|---------------------------|----------|----------|----------|------------|\n",
    );
    for r in results {
        s.push_str(&format!(
            "| Tier {:<2} | {:<25} | {:<8} | {:<8} | {:<8} | {:<8}ms |\n",
            r.num,
            r.name,
            if r.passed { "PASSED" } else { "FAILED" },
            r.ok,
            r.not_ok,
            r.ms
        ));
    }
    s.push_str(RULE);
    s.push('\n');
    s.push_str(&format!(
        " TOTALS: {}/{} tests passed across {}/{} tiers ({}ms total)\n",
        ok,
        all,
        passed_tiers,
        results.len(),
        total_ms
    ));
    s.push_str(RULE);
    s.push('\n');
    if failed_tiers == 0 {
        s.push_str(" 🎉 100% PASS RATE — MONOREPO SCALABILITY OVERHAUL READY FOR PRODUCTION\n");
    } else {
        s.push_str(&format!(
            " ❌ FAILURES DETECTED IN {} TIER(S)\n",
            failed_tiers
        ));
    }
    s
}

pub fn tap_report(results: &[TierResult]) -> String {
    let mut s = format!("1..{}\n", results.len());
    for (i, r) in results.iter().enumerate() {
        if r.passed {
            s.push_str(&format!(
                "ok {} - Tier {}: {} ({}/{} passed in {}ms)\n",
                i + 1,
                r.num,
                r.name,
                r.ok,
                r.ok,
                r.ms
            ));
        } else {
            s.push_str(&format!(
                "not ok {} - Tier {}: {} ({} failed in {}ms)\n",
                i + 1,
                r.num,
                r.name,
                r.not_ok,
                r.ms
            ));
        }
    }
    s
}

pub fn json_report(results: &[TierResult], total_ms: i64) -> String {
    let tiers: Vec<JsonTier> = results
        .iter()
        .map(|r| JsonTier {
            tier: r.num.parse().unwrap_or(0),
            name: &r.name,
            status: if r.passed { "PASSED" } else { "FAILED" },
            passed: r.ok,
            failed: r.not_ok,
            duration_ms: r.ms,
        })
        .collect();
    let report = JsonReport {
        total_tiers: tiers.len(),
        passed_tiers: tiers.iter().filter(|t| t.status == "PASSED").count(),
        failed_tiers: tiers.iter().filter(|t| t.status == "FAILED").count(),
        total_tests: tiers.iter().map(|t| t.passed + t.failed).sum(),
        passed_tests: tiers.iter().map(|t| t.passed).sum(),
        failed_tests: tiers.iter().map(|t| t.failed).sum(),
        duration_ms: total_ms,
        tiers,
    };
    format!(
        "{}\n",
        serde_json::to_string_pretty(&report).unwrap_or_default()
    )
}

/// The whole runner; the exit status.
pub fn run(args: &[Vec<u8>]) -> i32 {
    let src = self_path();
    let pwd = start_pwd();
    let root = match std::env::var_os("BUILD_WORKSPACE_DIRECTORY") {
        Some(v) if !v.is_empty() => v.into_vec(),
        _ => resolve_workspace_root(&src, &pwd),
    };
    match std::env::set_current_dir(path(&root)) {
        Ok(()) => {
            let full = if root.starts_with(b"/") {
                root.clone()
            } else {
                let mut f = pwd.clone();
                f.push(b'/');
                f.extend_from_slice(&root);
                f
            };
            std::env::set_var("PWD", OsString::from_vec(logical(&full)));
        }
        Err(e) => {
            let mut m = b"cd: ".to_vec();
            m.extend_from_slice(&root);
            m.extend_from_slice(b": ");
            m.extend_from_slice(strerror(&e).as_bytes());
            bash_diag(30, &m);
        }
    }
    let script_dir = physical(&dirname(&src), 32);

    let mut tier_filter: Vec<u8> = b"all".to_vec();
    let mut format: Vec<u8> = b"text".to_vec();
    let mut verbose = false;
    let mut i = 0;
    while i < args.len() {
        match args[i].as_slice() {
            b"--tier" | b"--format" => {
                let is_tier = args[i] == b"--tier";
                match args.get(i + 1) {
                    Some(v) => {
                        if is_tier {
                            tier_filter = v.clone();
                        } else {
                            format = v.clone();
                        }
                        i += 2;
                    }
                    None => {
                        bash_diag(if is_tier { 59 } else { 63 }, b"$2: unbound variable");
                        return 1;
                    }
                }
            }
            b"-v" | b"--verbose" => {
                verbose = true;
                i += 1;
            }
            b"-h" | b"--help" => return usage(0),
            other => {
                let mut m = b"ERROR: Unknown option: ".to_vec();
                m.extend_from_slice(other);
                m.push(b'\n');
                err(&m);
                return usage(1);
            }
        }
    }

    let start = now_ms();
    line(RULE);
    line(" Vitruvian Monorepo Scalability Overhaul — E2E Master Test Suite");
    out(&[b" Working Directory: ".as_slice(), &root, b"\n"].concat());
    out(&[b" Tier Selection:    ".as_slice(), &tier_filter, b"\n"].concat());
    line(RULE);

    let mut results: Vec<TierResult> = Vec::new();
    for (num, name, script, expected) in TIERS {
        if tier_filter != b"all" && tier_filter != num.as_bytes() {
            continue;
        }
        let t_start = now_ms();
        let mut sp = script_dir.clone();
        sp.push(b'/');
        sp.extend_from_slice(script.as_bytes());
        let exists = fs::metadata(path(&sp)).is_ok();
        let (text, status) = if exists {
            run_script(&sp)
        } else {
            let mut m = b"Script not found: ".to_vec();
            m.extend_from_slice(&sp);
            (m, 1)
        };
        let ms = now_ms() - t_start;
        let mut ok = count(&text, b"ok");
        let not_ok = count(&text, b"not ok");
        if ok == 0 && status == 0 {
            ok = expected;
        }
        let passed = status == 0 && not_ok == 0;
        results.push(TierResult {
            num: num.to_string(),
            name: name.to_string(),
            passed,
            ok,
            not_ok,
            ms,
        });
        if passed {
            if verbose {
                out(&echo_bytes(&text));
            }
        } else {
            err(&echo_bytes(&text));
        }
    }
    let total_ms = now_ms() - start;

    if format == b"json" {
        out(json_report(&results, total_ms).as_bytes());
    } else if format == b"tap" {
        out(tap_report(&results).as_bytes());
    } else {
        out(text_report(&results, total_ms).as_bytes());
    }
    if results.iter().any(|r| !r.passed) {
        1
    } else {
        0
    }
}

/// For tests: does `p` exist as a file.
pub fn is_file(p: &Path) -> bool {
    p.is_file()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn r(num: &str, passed: bool, ok: u64, not_ok: u64) -> TierResult {
        TierResult {
            num: num.into(),
            name: TIERS[num.parse::<usize>().unwrap() - 1].1.into(),
            passed,
            ok,
            not_ok,
            ms: 7,
        }
    }

    #[test]
    fn counting_tap_lines() {
        let t = b"ok 1 - a\n  ok 2 - b\n\tnot ok 3 - c\nok\nokay 4\nnot ok 5\n# ok 6\n\x0bok 7";
        assert_eq!(count(t, b"ok"), 3);
        assert_eq!(count(t, b"not ok"), 2);
    }

    #[test]
    fn echo_takes_option_words() {
        assert_eq!(echo_bytes(b"-n"), b"".to_vec());
        assert_eq!(echo_bytes(b"-e"), b"\n".to_vec());
        assert_eq!(echo_bytes(b"-x"), b"-x\n".to_vec());
        assert_eq!(echo_bytes(b""), b"\n".to_vec());
    }

    #[test]
    fn json_matches_python_indent_2() {
        let j = json_report(&[r("1", true, 60, 0), r("3", false, 2, 1)], 99);
        assert_eq!(
            j,
            "{\n  \"total_tiers\": 2,\n  \"passed_tiers\": 1,\n  \"failed_tiers\": 1,\n  \"total_tests\": 63,\n  \"passed_tests\": 62,\n  \"failed_tests\": 1,\n  \"duration_ms\": 99,\n  \"tiers\": [\n    {\n      \"tier\": 1,\n      \"name\": \"Feature Coverage\",\n      \"status\": \"PASSED\",\n      \"passed\": 60,\n      \"failed\": 0,\n      \"duration_ms\": 7\n    },\n    {\n      \"tier\": 3,\n      \"name\": \"Pairwise Combinations\",\n      \"status\": \"FAILED\",\n      \"passed\": 2,\n      \"failed\": 1,\n      \"duration_ms\": 7\n    }\n  ]\n}\n"
        );
        assert!(json_report(&[], 0).contains("\"tiers\": []"));
    }

    #[test]
    fn tap_and_text() {
        let rs = [r("2", true, 5, 0), r("4", false, 1, 2)];
        assert_eq!(
            tap_report(&rs),
            "1..2\nok 1 - Tier 2: Boundary & Edge Cases (5/5 passed in 7ms)\nnot ok 2 - Tier 4: Real-World Workloads (2 failed in 7ms)\n"
        );
        let t = text_report(&rs, 30);
        assert!(t.contains("| Tier 2  | Boundary & Edge Cases     | PASSED   | 5        | 0        | 7       ms |\n"));
        assert!(t.contains(" TOTALS: 6/8 tests passed across 1/2 tiers (30ms total)\n"));
        assert!(t.ends_with(" ❌ FAILURES DETECTED IN 1 TIER(S)\n"));
    }

    #[test]
    fn paths() {
        assert_eq!(dirname(b"/a/b/"), b"/a".to_vec());
        assert_eq!(dirname(b"runner"), b".".to_vec());
        assert_eq!(basename(b"/x/runner"), b"runner".to_vec());
        assert_eq!(logical(b"/a/./b/../c"), b"/a/c".to_vec());
    }

    #[test]
    fn workspace_root_is_the_nearest_marker() {
        let base = std::env::temp_dir().join(format!("runner-test-{}", std::process::id()));
        let deep = base.join("x/tools/platform-e2e");
        fs::create_dir_all(&deep).unwrap();
        fs::write(base.join("MODULE.bazel"), "").unwrap();
        fs::write(base.join("x/go.work"), "").unwrap();
        fs::write(deep.join("runner"), "").unwrap();
        let src = deep.join("runner").into_os_string().into_vec();
        let got = resolve_workspace_root(&src, b"/nowhere");
        let want = fs::canonicalize(base.join("x"))
            .unwrap()
            .into_os_string()
            .into_vec();
        assert_eq!(got, want);
        fs::remove_dir_all(&base).unwrap();
    }
}
