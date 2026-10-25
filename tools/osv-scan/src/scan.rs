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

//! osv-scan.sh, step for step. Each function names the shell it replaces;
//! the WHY for every step is in osv-scan.sh, which stays the reference.

use crate::pyjson::{self, Py};
use crate::pyval::{self, HKey, TypeError};
use crate::{jq, pypath, text};
use std::collections::HashMap;
use std::ffi::{OsStr, OsString};
use std::fs::File;
use std::io::Write;
use std::os::unix::ffi::{OsStrExt, OsStringExt};
use std::os::unix::fs::MetadataExt;
use std::os::unix::process::ExitStatusExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

const MIN_SOURCES: i64 = 50;

/// Exported for every child; see "NO CALL ANALYSIS" in osv-scan.sh.
const GOWORK_OFF: &str = "GOWORK=off";

/// TRANSIENT_RE's alternatives (all literals; matched case-insensitively).
const TRANSIENT: &[&str] = &[
    "rpc error",
    "unavailable",
    "deadline exceeded",
    "connection refused",
    "no such host",
    "i/o timeout",
    "tls handshake",
    "connection reset",
    "temporary failure in name resolution",
    "failed resolution",
    "client error",
    "status=\"404",
    "vulnerability not found",
];

/// The failure arm's excerpt pattern.
const EXCERPT: &[&str] = &[
    "error",
    "fail",
    "unavailable",
    "unreachable",
    "panic",
    "fatal",
    "timeout",
    "refused",
];

const FIX_HINT: &str =
    "   Fix by upgrading the dependency, or -- if it is genuinely not exploitable
   here -- add an ignoredVulns entry to osv-scanner.toml with a reason, and an
   expiry unless the advisory has no fix at all.";

// --- output ------------------------------------------------------------------

fn out(b: &[u8]) {
    let mut o = std::io::stdout().lock();
    let _ = o.write_all(b);
    let _ = o.flush();
}

fn err(b: &[u8]) {
    let mut e = std::io::stderr().lock();
    let _ = e.write_all(b);
    let _ = e.flush();
}

fn cat(parts: &[&[u8]]) -> Vec<u8> {
    parts.concat()
}

fn info(msg: &[u8]) {
    out(&cat(&["\x1b[36m\u{2192}\x1b[0m ".as_bytes(), msg, b"\n"]));
}

fn ok(msg: &[u8]) {
    out(&cat(&["\x1b[32m\u{2713}\x1b[0m ".as_bytes(), msg, b"\n"]));
}

/// Prints the failure; the caller returns 1.
fn die(msg: &[u8]) -> i32 {
    err(&cat(&["\x1b[31m\u{2717}\x1b[0m ".as_bytes(), msg, b"\n"]));
    1
}

fn warn(msg: &[u8]) {
    err(&cat(&["\x1b[33m!\x1b[0m ".as_bytes(), msg, b"\n"]));
    if !env_bytes("GITHUB_ACTIONS").is_empty() {
        out(&cat(&[
            b"::warning title=osv-scan coverage degraded::",
            msg,
            b"\n",
        ]));
    }
}

// --- environment and processes -------------------------------------------------

fn env_bytes(name: &str) -> Vec<u8> {
    std::env::var_os(name)
        .map(|v| v.into_vec())
        .unwrap_or_default()
}

fn os(b: &[u8]) -> &OsStr {
    OsStr::from_bytes(b)
}

fn code_of(st: std::process::ExitStatus) -> i32 {
    st.code().unwrap_or_else(|| 128 + st.signal().unwrap_or(0))
}

fn spawn_failure(e: &std::io::Error) -> i32 {
    if e.kind() == std::io::ErrorKind::NotFound {
        127
    } else {
        126
    }
}

/// `$(prog args...)` with stderr discarded (or inherited): (status, stdout).
fn capture(prog: &str, args: &[&[u8]], quiet: bool) -> (i32, Vec<u8>) {
    let mut c = Command::new(prog);
    c.args(args.iter().map(|a| os(a)))
        .stdin(Stdio::inherit())
        .stdout(Stdio::piped())
        .stderr(if quiet {
            Stdio::null()
        } else {
            Stdio::inherit()
        });
    match c.output() {
        Ok(o) => (code_of(o.status), o.stdout),
        Err(e) => (spawn_failure(&e), Vec::new()),
    }
}

/// `prog args >/dev/null 2>/dev/null`'s status.
fn quiet_status(prog: &str, args: &[&[u8]]) -> i32 {
    let mut c = Command::new(prog);
    c.args(args.iter().map(|a| os(a)))
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    match c.status() {
        Ok(s) => code_of(s),
        Err(e) => spawn_failure(&e),
    }
}

/// `command -v name`: the first executable file on PATH.
fn on_path(name: &str) -> bool {
    let path = env_bytes("PATH");
    path.split(|c| *c == b':').any(|dir| {
        let dir = if dir.is_empty() { &b"."[..] } else { dir };
        let p = Path::new(os(dir)).join(name);
        std::fs::metadata(&p)
            .map(|m| m.is_file() && m.mode() & 0o111 != 0)
            .unwrap_or(false)
    })
}

/// bash's `pwd`: $PWD when it names the working directory, else getcwd.
fn logical_pwd() -> Vec<u8> {
    let real = std::env::current_dir()
        .map(|c| c.into_os_string().into_vec())
        .unwrap_or_default();
    let pwd = env_bytes("PWD");
    if pwd.starts_with(b"/") && !pwd.split(|c| *c == b'/').any(|c| c == b"." || c == b"..") {
        if let (Ok(a), Ok(b)) = (std::fs::metadata(os(&pwd)), std::fs::metadata(".")) {
            if a.dev() == b.dev() && a.ino() == b.ino() {
                return pwd;
            }
        }
    }
    real
}

/// bash's `cd dir`: chdir, then PWD as the logical path.
fn cd(dir: &[u8]) -> std::io::Result<()> {
    let target = if dir.starts_with(b"/") {
        dir.to_vec()
    } else {
        pypath::join(&logical_pwd(), dir)
    };
    std::env::set_current_dir(os(dir))?;
    let mut logical = pypath::normpath(&target);
    if logical.starts_with(b"//") && !logical.starts_with(b"///") {
        logical.remove(0);
    }
    std::env::set_var("PWD", os(&logical));
    Ok(())
}

/// `mktemp [-d]`, the real one: where it puts files is platform policy
/// (GNU honours TMPDIR, macOS uses the per-user Darwin temp dir), and the
/// gate should create them exactly where the script did.
fn mktemp(dir: bool) -> std::io::Result<PathBuf> {
    let args: &[&[u8]] = if dir { &[b"-d"] } else { &[] };
    let (rc, o) = capture("mktemp", args, false);
    let p = text::strip_nl(&o);
    if rc != 0 || p.is_empty() {
        return Err(std::io::Error::new(
            std::io::ErrorKind::Other,
            "mktemp failed",
        ));
    }
    Ok(PathBuf::from(OsString::from_vec(p)))
}

fn mktemp_file() -> std::io::Result<PathBuf> {
    mktemp(false)
}

fn mktemp_dir() -> std::io::Result<PathBuf> {
    mktemp(true)
}

// --- shell arithmetic ----------------------------------------------------------

/// An operand of `[ ... -lt ... ]`: optional blanks and sign, decimal digits.
fn test_int(s: &str) -> Option<i64> {
    let t = s.trim_matches(|c: char| c == ' ' || c == '\t' || c == '\n');
    let digits = t.strip_prefix(['+', '-']).unwrap_or(t);
    if digits.is_empty() || !digits.bytes().all(|c| c.is_ascii_digit()) {
        return None;
    }
    t.parse::<i64>().ok()
}

/// `[ "$a" -OP "$b" ]` with bash's complaint for a non-integer operand.
fn test_cmp(a: &str, b: &str, op: fn(i64, i64) -> bool) -> bool {
    for v in [a, b] {
        if test_int(v).is_none() {
            err(format!("osv-scan: [: {}: integer expression expected\n", v).as_bytes());
            return false;
        }
    }
    op(test_int(a).unwrap(), test_int(b).unwrap())
}

/// `$((v * 2))` for the retry delay: decimal, 0-octal or 0x-hex; an unset
/// name reads as 0. `Err` is bash's fatal arithmetic error.
fn arith_double(v: &str) -> Result<String, ()> {
    let t = v.trim_matches(|c: char| c == ' ' || c == '\t' || c == '\n');
    if t.is_empty() {
        return Ok("0".into());
    }
    let (neg, body) = match t.as_bytes()[0] {
        b'-' => (true, &t[1..]),
        b'+' => (false, &t[1..]),
        _ => (false, t),
    };
    let n: i64 = if let Some(h) = body.strip_prefix("0x").or_else(|| body.strip_prefix("0X")) {
        i64::from_str_radix(h, 16).map_err(|_| ())?
    } else if body.len() > 1 && body.starts_with('0') {
        i64::from_str_radix(&body[1..], 8).map_err(|_| ())?
    } else if !body.is_empty() && body.bytes().all(|c| c.is_ascii_digit()) {
        body.parse().map_err(|_| ())?
    } else if !neg
        && !body.is_empty()
        && body.bytes().all(|c| c.is_ascii_alphanumeric() || c == b'_')
        && !body.as_bytes()[0].is_ascii_digit()
        && std::env::var_os(body).is_none()
    {
        0
    } else {
        return Err(());
    };
    Ok((if neg { -n } else { n }).wrapping_mul(2).to_string())
}

fn sleep_secs(s: &str) {
    if let Some(n) = test_int(s) {
        if n > 0 {
            std::thread::sleep(std::time::Duration::from_secs(n as u64));
        }
    }
}

// --- the scan --------------------------------------------------------------------

struct Ctx {
    root: Vec<u8>,
    scan_args: Vec<Vec<u8>>,
    json: PathBuf,
    scan_err: PathBuf,
    tree_before: Vec<u8>,
    max_attempts: String,
    retry_delay: String,
}

/// One `osv-scanner ... --output-file <json> . >/dev/null 2><err>` (after
/// `: > json; : > err`).
fn run_scan(args: &[Vec<u8>], json: &Path, errf: &Path) -> i32 {
    let _ = File::create(json);
    let e = match File::create(errf) {
        Ok(f) => f,
        Err(_) => return 1,
    };
    let mut c = Command::new("osv-scanner");
    c.args(args.iter().map(|a| os(a)))
        .arg("--all-packages")
        .args(["--format", "json", "--output-file"])
        .arg(json)
        .arg(".")
        .stdin(Stdio::inherit())
        .stdout(Stdio::null())
        .stderr(e);
    match c.status() {
        Ok(s) => code_of(s),
        Err(x) => {
            if let Ok(mut f) = std::fs::OpenOptions::new().append(true).open(errf) {
                let _ = writeln!(
                    f,
                    "osv-scan: osv-scanner: {}",
                    if spawn_failure(&x) == 127 {
                        "command not found"
                    } else {
                        "Permission denied"
                    }
                );
            }
            spawn_failure(&x)
        }
    }
}

fn transient(errf: &Path) -> bool {
    std::fs::read(errf)
        .map(|b| text::contains_any_ci(&b, TRANSIENT))
        .unwrap_or(false)
}

/// `dirty_snapshot`: (pipeline status, output with trailing newlines kept off).
fn dirty_snapshot() -> (i32, Vec<u8>) {
    if quiet_status("git", &[b"rev-parse", b"--is-inside-work-tree"]) != 0 {
        return (0, Vec::new());
    }
    let (rc, o) = capture("git", &[b"status", b"--porcelain"], true);
    (rc, text::strip_nl(&text::cut4_sort(&o)))
}

/// `assert_tree_unchanged`: Some(exit code) when it dies.
fn assert_tree_unchanged(ctx: &Ctx) -> Option<i32> {
    let (_, now) = dirty_snapshot();
    let touched = text::strip_nl(&text::comm_13(&ctx.tree_before, &now));
    if touched.is_empty() {
        return None;
    }
    let msg = cat(&[
        b"the scan MUTATED the working tree -- refusing to report a verdict:\n",
        &text::indent_var(&touched),
        b"\n   This gate is required and must be read-only; a scan that rewrites the
   checkout breaks tidy-check downstream and corrupts what it is inspecting.
   Historically this was osv-scanner's Go call analysis normalising go.work.sum.
   Restore with `git checkout -- <file>`, then find which osv-scanner stage
   ran the toolchain (put a logging shim ahead of `go` on PATH and re-run).",
    ]);
    Some(die(&msg))
}

/// `resolve_diff_base`'s stdout, as `$(resolve_diff_base)` sees it.
fn resolve_diff_base() -> Vec<u8> {
    let rev = env_bytes("BASE_REV");
    if !rev.is_empty() {
        return text::strip_nl(&rev);
    }
    let base_ref = env_bytes("BASE_REF");
    if base_ref.is_empty() {
        return Vec::new();
    }
    let (_, mut o) = capture("git", &[b"fetch", b"--quiet", b"origin", &base_ref], true);
    let (rc, mb) = capture("git", &[b"merge-base", b"HEAD", b"FETCH_HEAD"], true);
    let mut sub = mb;
    if rc != 0 {
        let origin = cat(&[b"origin/", &base_ref]);
        let (_, mb2) = capture("git", &[b"merge-base", b"HEAD", &origin], true);
        sub.extend_from_slice(&mb2);
    }
    o.extend_from_slice(&text::strip_nl(&sub));
    text::strip_nl(&o)
}

fn commit_readable(base: &[u8]) -> bool {
    let spec = cat(&[base, b"^{commit}"]);
    // stdout is inherited by the script, but `cat-file -e` prints nothing.
    let mut c = Command::new("git");
    c.args([os(b"cat-file"), os(b"-e"), os(&spec)])
        .stderr(Stdio::null());
    matches!(c.status().map(code_of), Ok(0))
}

/// `git show <rev>:<file>`'s stdout, or None when it fails.
fn git_show(rev: &[u8], f: &[u8]) -> Option<Vec<u8>> {
    let spec = cat(&[rev, b":", f]);
    let (rc, o) = capture("git", &[b"show", &spec], true);
    if rc == 0 {
        Some(o)
    } else {
        None
    }
}

/// `dep_manifests_changed`: true for "changed".
fn dep_manifests_changed() -> bool {
    let base = resolve_diff_base();
    if base.is_empty() || !commit_readable(&base) {
        return true;
    }
    let (rc, files) = capture("git", &[b"diff", b"--name-only", &base, b"HEAD"], true);
    if rc != 0 {
        return true;
    }
    let files = text::strip_nl(&files);
    let mut herestring = files.clone();
    herestring.push(b'\n');
    let matches: Vec<&[u8]> = text::lines(&herestring)
        .into_iter()
        .filter(|l| text::is_dep_manifest(l))
        .collect();
    for f in matches {
        if f.is_empty() {
            continue;
        }
        let json_manifest = f == b"package.json"
            || f.ends_with(b"/package.json")
            || f == b"composer.json"
            || f.ends_with(b"/composer.json");
        if !json_manifest {
            return true;
        }
        let old = git_show(&base, f);
        let new = git_show(b"HEAD", f);
        if !jq::same_without_version(old.as_deref(), new.as_deref()) {
            return true;
        }
    }
    false
}

// --- advisories_added's python ---------------------------------------------------

type Finding = (Vec<Py>, Vec<(HKey, Py)>);

struct Loaded {
    sources: usize,
    order: Vec<Vec<HKey>>,
    found: HashMap<Vec<HKey>, Finding>,
}

enum PyFail {
    /// An exception inside the try: `sys.exit(2)`.
    Load,
}

fn dict_get(d: &Py, k: &str, default: Py) -> Result<Py, PyFail> {
    if !d.is_dict() {
        return Err(PyFail::Load);
    }
    Ok(d.get(k).cloned().unwrap_or(default))
}

fn lift<T>(r: Result<T, TypeError>) -> Result<T, PyFail> {
    r.map_err(|_| PyFail::Load)
}

/// `load(path, root)` from the comparison script.
fn py_load(path: &Path, root: &[u8]) -> Result<Loaded, PyFail> {
    let root = pypath::realpath(root).map_err(|_| PyFail::Load)?;
    let doc = pyjson::load_file(path).map_err(|_| PyFail::Load)?;
    let results = dict_get(&doc, "results", Py::List(vec![]))?;
    let results = lift(pyval::iterate(&results))?;
    let mut sources: Vec<HKey> = Vec::new();
    for r in &results {
        let src = dict_get(r, "source", Py::Dict(vec![]))?;
        let p = dict_get(&src, "path", Py::None)?;
        let k = lift(pyval::hkey(&p))?;
        if !sources.contains(&k) {
            sources.push(k);
        }
    }
    let mut prefix = root.clone();
    prefix.push(b'/');
    let mut order = Vec::new();
    let mut found: HashMap<Vec<HKey>, Finding> = HashMap::new();
    for r in &results {
        let src = dict_get(r, "source", Py::Dict(vec![]))?;
        let p = match dict_get(&src, "path", Py::Str(String::new()))? {
            Py::Str(s) => s,
            _ => return Err(PyFail::Load),
        };
        let p = pypath::realpath(p.as_bytes()).map_err(|_| PyFail::Load)?;
        let rel = if p.starts_with(&prefix) {
            p[prefix.len()..].to_vec()
        } else {
            p
        };
        let rel = Py::Str(String::from_utf8_lossy(&rel).into_owned());
        for pk in lift(pyval::iterate(&dict_get(r, "packages", Py::List(vec![]))?))? {
            let pkg = dict_get(&pk, "package", Py::Dict(vec![]))?;
            let vulns = match pk.get("vulnerabilities") {
                Some(v) if v.truthy() => lift(pyval::iterate(v))?,
                _ => Vec::new(),
            };
            for v in vulns {
                let eco = dict_get(&pkg, "ecosystem", Py::Str(String::new()))?;
                let name = dict_get(&pkg, "name", Py::Str(String::new()))?;
                let id = dict_get(&v, "id", Py::Str(String::new()))?;
                let tuple = vec![rel.clone(), eco, name, id];
                let key = tuple.iter().map(pyval::hkey).collect::<Result<Vec<_>, _>>();
                let key = lift(key)?;
                let version = dict_get(&pkg, "version", Py::Str(String::new()))?;
                let vk = lift(pyval::hkey(&version))?;
                let entry = found.entry(key.clone()).or_insert_with(|| {
                    order.push(key.clone());
                    (tuple, Vec::new())
                });
                if !entry.1.iter().any(|(k, _)| *k == vk) {
                    entry.1.push((vk, version));
                }
            }
        }
    }
    Ok(Loaded {
        sources: sources.len(),
        order,
        found,
    })
}

/// The comparison script: Ok(stdout) on exit 0; Err(()) for any other exit
/// (after printing what Python would have printed to stderr).
fn py_compare(
    head_json: &Path,
    head_root: &[u8],
    base_json: &Path,
    base_root: &[u8],
) -> Result<Vec<u8>, ()> {
    let loaded =
        py_load(head_json, head_root).and_then(|h| py_load(base_json, base_root).map(|b| (h, b)));
    let (head, base) = match loaded {
        Ok(x) => x,
        Err(PyFail::Load) => return Err(()),
    };
    if (base.sources as i64) < MIN_SOURCES || head.found.is_empty() {
        return Err(());
    }
    let count = |l: &Loaded| l.found.values().map(|f| f.1.len()).sum::<usize>();
    let mut o = format!("COUNTS\t{}\t{}\n", count(&base), count(&head)).into_bytes();
    let traceback = |e: TypeError| {
        err(format!(
            "Traceback (most recent call last):\n  File \"<stdin>\", line 37, in <module>\nTypeError: {}\n",
            e.0
        )
        .as_bytes());
    };
    let keys = match pyval::sorted_by(&head.order, |a, b| {
        pyval::cmp_tuple(&head.found[a].0, &head.found[b].0)
    }) {
        Ok(k) => k,
        Err(e) => {
            traceback(e);
            return Err(());
        }
    };
    for key in keys {
        let (tuple, versions) = &head.found[&key];
        let in_base = base.found.get(&key).map(|f| f.1.len()).unwrap_or(0);
        if versions.len() <= in_base {
            continue;
        }
        let mut strs: Vec<String> = Vec::new();
        for (_, v) in versions {
            match v {
                Py::Str(s) => strs.push(s.clone()),
                other => {
                    traceback(TypeError(format!(
                        "sequence item 0: expected str instance, {} found",
                        pyval::type_name(other)
                    )));
                    return Err(());
                }
            }
        }
        strs.sort();
        o.extend_from_slice(
            format!(
                "ADDED\t{} {} ({}) in {}\n",
                tuple[3].py_str(),
                tuple[2].py_str(),
                strs.join(", "),
                tuple[0].py_str()
            )
            .as_bytes(),
        );
    }
    Ok(o)
}

/// `advisories_added`, a subshell: (exit status, stdout). Its cd and its
/// temporary directory are undone before returning.
fn advisories_added(ctx: &Ctx) -> (i32, Vec<u8>) {
    let base = resolve_diff_base();
    if base.is_empty() || !commit_readable(&base) {
        return (2, Vec::new());
    }
    if quiet_status(
        "git",
        &[
            b"diff",
            b"--quiet",
            &base,
            b"HEAD",
            b"--",
            b"osv-scanner.toml",
        ],
    ) != 0
    {
        return (2, Vec::new());
    }
    let tmp = match mktemp_dir() {
        Ok(t) => t,
        Err(_) => return (2, Vec::new()),
    };
    let saved_cwd = std::env::current_dir().ok();
    let saved_pwd = std::env::var_os("PWD");
    let result = advisories_in(ctx, &base, &tmp);
    if let Some(c) = saved_cwd {
        let _ = std::env::set_current_dir(c);
    }
    match saved_pwd {
        Some(p) => std::env::set_var("PWD", p),
        None => std::env::remove_var("PWD"),
    }
    let _ = std::fs::remove_dir_all(&tmp);
    result
}

fn advisories_in(ctx: &Ctx, base: &[u8], tmp: &Path) -> (i32, Vec<u8>) {
    let tree = tmp.join("tree");
    if let Err(e) = std::fs::create_dir(&tree) {
        err(format!("mkdir: {}: {}\n", tree.display(), e).as_bytes());
    }
    // git archive <base> | tar -x -C <tree> 2>/dev/null, under pipefail.
    let archive = Command::new("git")
        .args([os(b"archive"), os(base)])
        .stdin(Stdio::inherit())
        .stdout(Stdio::piped())
        .spawn();
    let mut archive = match archive {
        Ok(a) => a,
        Err(_) => return (2, Vec::new()),
    };
    let pipe = archive.stdout.take().expect("piped");
    let tar = Command::new("tar")
        .args([OsStr::new("-x"), OsStr::new("-C"), tree.as_os_str()])
        .stdin(pipe)
        .stdout(Stdio::inherit())
        .stderr(Stdio::null())
        .status();
    let git_rc = archive.wait().map(code_of).unwrap_or(1);
    let tar_rc = tar.map(code_of).unwrap_or(127);
    if git_rc != 0 || tar_rc != 0 {
        return (2, Vec::new());
    }
    if cd(tree.as_os_str().as_bytes()).is_err() {
        return (2, Vec::new());
    }
    let base_json = tmp.join("base.json");
    let base_err = tmp.join("base.err");
    let mut b_attempt: i64 = 1;
    let mut b_delay = ctx.retry_delay.clone();
    let b_rc = loop {
        let rc = run_scan(&ctx.scan_args, &base_json, &base_err);
        if rc != 0
            && rc != 1
            && test_cmp(&b_attempt.to_string(), &ctx.max_attempts, |a, b| a < b)
            && transient(&base_err)
        {
            if test_cmp(&b_delay, "0", |a, b| a > b) {
                sleep_secs(&b_delay);
            }
            b_delay = match arith_double(&b_delay) {
                Ok(d) => d,
                Err(()) => {
                    err(format!(
                        "osv-scan: {} * 2: syntax error: invalid arithmetic operator\n",
                        b_delay
                    )
                    .as_bytes());
                    return (1, Vec::new());
                }
            };
            b_attempt += 1;
            continue;
        }
        break rc;
    };
    if b_rc != 0 && b_rc != 1 {
        return (2, Vec::new());
    }
    match py_compare(
        &ctx.json,
        &ctx.root,
        &base_json,
        tree.as_os_str().as_bytes(),
    ) {
        Ok(o) => (0, o),
        Err(()) => (2, Vec::new()),
    }
}

/// `awk -F'\t' '$1==tag{print $n}'` over `<<<"$text"`.
fn awk_field(text_: &[u8], tag: &[u8], n: usize, prefix: &[u8]) -> Vec<u8> {
    let mut s = text_.to_vec();
    s.push(b'\n');
    let mut o = Vec::new();
    for l in text::lines(&s) {
        let fields: Vec<&[u8]> = l.split(|c| *c == b'\t').collect();
        if fields[0] == tag {
            o.extend_from_slice(prefix);
            o.extend_from_slice(fields.get(n - 1).copied().unwrap_or(b""));
            o.push(b'\n');
        }
    }
    text::strip_nl(&o)
}

/// Python's coverage count: distinct `source.path`s in `results`, or -1.
fn count_sources(json: &Path) -> i64 {
    let count = || -> Result<i64, ()> {
        let doc = pyjson::load_file(json).map_err(|_| ())?;
        let results = dict_get(&doc, "results", Py::List(vec![])).map_err(|_| ())?;
        let mut seen: Vec<HKey> = Vec::new();
        for r in pyval::iterate(&results).map_err(|_| ())? {
            let src = dict_get(&r, "source", Py::Dict(vec![])).map_err(|_| ())?;
            let p = dict_get(&src, "path", Py::None).map_err(|_| ())?;
            let k = pyval::hkey(&p).map_err(|_| ())?;
            if !seen.contains(&k) {
                seen.push(k);
            }
        }
        Ok(seen.len() as i64)
    };
    count().unwrap_or(-1)
}

fn retry_loop(ctx: &Ctx) -> Result<(i32, i64), i32> {
    let mut attempt: i64 = 1;
    let mut delay = ctx.retry_delay.clone();
    loop {
        let rc = run_scan(&ctx.scan_args, &ctx.json, &ctx.scan_err);
        if let Some(code) = assert_tree_unchanged(ctx) {
            return Err(code);
        }
        if rc != 0
            && rc != 1
            && test_cmp(&attempt.to_string(), &ctx.max_attempts, |a, b| a < b)
            && transient(&ctx.scan_err)
        {
            info(
                format!(
                    "attempt {}/{} failed with a transient resolver error (exit {}); retrying in {}s",
                    attempt, ctx.max_attempts, rc, delay
                )
                .as_bytes(),
            );
            if test_cmp(&delay, "0", |a, b| a > b) {
                sleep_secs(&delay);
            }
            delay = match arith_double(&delay) {
                Ok(d) => d,
                Err(()) => {
                    err(format!(
                        "osv-scan: {} * 2: syntax error: invalid arithmetic operator\n",
                        delay
                    )
                    .as_bytes());
                    return Err(1);
                }
            };
            attempt += 1;
            continue;
        }
        return Ok((rc, attempt));
    }
}

fn verdict(ctx: &mut Ctx) -> i32 {
    let (mut rc, attempt) = match retry_loop(ctx) {
        Ok(x) => x,
        Err(code) => return code,
    };
    if attempt != 1 {
        info(format!("settled after {} attempt(s)", attempt).as_bytes());
    }

    let mut degraded = false;
    if rc != 0 && rc != 1 && transient(&ctx.scan_err) {
        degraded = true;
        ctx.scan_args.push(b"--no-resolve".to_vec());
        info(
            format!(
                "transitive resolution unavailable after {} attempt(s); re-scanning with --no-resolve",
                attempt
            )
            .as_bytes(),
        );
        rc = run_scan(&ctx.scan_args, &ctx.json, &ctx.scan_err);
        if let Some(code) = assert_tree_unchanged(ctx) {
            return code;
        }
    }

    let sources = count_sources(&ctx.json);
    if sources < 0 {
        let last = std::fs::read(&ctx.scan_err).unwrap_or_default();
        let words = text::strip_nl(&text::prefix_stream(&text::tail(&last, 5), b"     "));
        return die(&cat(&[
            format!(
                "osv-scanner exited {} without parseable JSON output, so there is no
   evidence it covered anything -- refusing to report a verdict. Its last words:\n",
                rc
            )
            .as_bytes(),
            &words,
            b"\n   \"No package sources found\" here means the scan was run from a gitignored
   directory (a worktree under .claude/ walks up to the parent .gitignore and
   excludes itself). Run from the primary checkout.",
        ]));
    }
    if sources < MIN_SOURCES {
        return die(format!(
            "osv-scanner scanned only {} source(s), expected >= {}.
   The scan did not cover this repo, so its result is meaningless -- refusing to
   report green. Most likely cause: running from a gitignored directory (a
   worktree under .claude/ walks up to the parent .gitignore and excludes
   itself). Run from the primary checkout.",
            sources, MIN_SOURCES
        )
        .as_bytes());
    }

    match rc {
        0 => {
            if degraded {
                warn(format!("no unaccepted advisories across {} scanned sources, but transitive PyPI resolution was UNAVAILABLE (deps.dev) and this run scanned with --no-resolve. Advisories that only surface once requirements.txt is resolved were NOT checked. Lockfile coverage (Go, npm, Cargo) is unaffected and complete.", sources).as_bytes());
            } else {
                ok(format!(
                    "no unaccepted advisories across {} scanned sources",
                    sources
                )
                .as_bytes());
            }
            0
        }
        1 => {
            // Re-run for a readable log: stdout to ours, stderr dropped.
            let _ = std::io::stdout().flush();
            let _ = Command::new("osv-scanner")
                .args(ctx.scan_args.iter().map(|a| os(a)))
                .arg(".")
                .stdin(Stdio::inherit())
                .stdout(Stdio::inherit())
                .stderr(Stdio::null())
                .status();
            if let Some(code) = assert_tree_unchanged(ctx) {
                return code;
            }
            if !dep_manifests_changed() {
                warn(b"osv-scanner found advisories (above), but this change touches NO dependency manifest or lockfile, so they are PRE-EXISTING in the base revision -- not introduced here. Reporting instead of blocking: failing an unrelated change for a vulnerability already present in main stops all work without removing the vulnerability. Fix it on its own branch (bump the dependency, or add a time-boxed osv-scanner.toml entry). The nightly scheduled scan still BLOCKS on the full set, so this does not go unnoticed.");
                return 0;
            }
            let (cmp_rc, cmp_out) = advisories_added(ctx);
            if cmp_rc == 1 {
                return 1;
            }
            let cmp_out = text::strip_nl(&cmp_out);
            if cmp_rc == 0 {
                let before = awk_field(&cmp_out, b"COUNTS", 2, b"");
                let after = awk_field(&cmp_out, b"COUNTS", 3, b"");
                let added = awk_field(&cmp_out, b"ADDED", 2, b"     ");
                let (before, after) = (
                    String::from_utf8_lossy(&before),
                    String::from_utf8_lossy(&after),
                );
                if added.is_empty() {
                    warn(format!("osv-scanner found advisories (above), but this change ADDS none of them: the base revision already had {}, and after this change there are {}. They are pre-existing, so they are reported, not blocking -- blocking would also stop the very PRs that remove them. The nightly scheduled scan still BLOCKS on the full set and files an issue, so they stay visible.", before, after).as_bytes());
                    return 0;
                }
                return die(&cat(&[
                    format!(
                        "this change ADDS advisories that the base revision does not have
   (base: {}, after this change: {}):\n",
                        before, after
                    )
                    .as_bytes(),
                    &added,
                    b"\n",
                    FIX_HINT.as_bytes(),
                ]));
            }
            if env_bytes("BASE_REV").is_empty() && env_bytes("BASE_REF").is_empty() {
                return die(cat(&[
                    b"osv-scanner found advisories not covered by osv-scanner.toml (above).
   This is a full-tree scan with no diff base (the nightly schedule or a manual
   run), so it blocks on every unaccepted advisory in this revision -- that is
   its job. Nothing here was introduced by a particular change.\n",
                    FIX_HINT.as_bytes(),
                ])
                .as_slice());
            }
            die(cat(&[
                b"osv-scanner found advisories not covered by osv-scanner.toml (above),
   and this change DOES touch a dependency manifest/lockfile -- so it may have
   introduced them. (Could not compare against the base revision, so failing
   closed on the full set.)\n",
                FIX_HINT.as_bytes(),
            ])
            .as_slice())
        }
        _ => {
            // `excerpt="$(grep -inE ... | tail -n 12)"` runs under `set -e` and
            // `pipefail`: when grep matches nothing (or cannot read the file)
            // the assignment fails and the script exits 1 there, silently. So
            // the `tail` fallback after it is unreachable, and so is this
            // arm's message, for a scanner whose stderr names no error.
            let e = match std::fs::read(&ctx.scan_err) {
                Ok(e) => e,
                Err(_) => return 1,
            };
            let matched = text::grep_n_ci(&e, EXCERPT);
            if matched.is_empty() {
                return 1;
            }
            let excerpt = text::strip_nl(&text::tail(&matched, 12));
            die(&cat(&[
                format!(
                    "osv-scanner failed to run (exit {}); refusing to report green.
   Matching lines from its output (stderr is where --output-file sends it):\n",
                    rc
                )
                .as_bytes(),
                &text::indent_var(&excerpt),
                b"\n   Reaching this arm now means one of two things, and they want opposite fixes:
   either the failure is DETERMINISTIC (stderr named no network fault, so the
   retry and the --no-resolve fallback were both skipped -- suspect a bad flag,
   a missing binary, or an osv-scanner upgrade), or the resolution-free fallback
   ITSELF failed, which rules the network out as the sole cause. Do not re-run
   hoping it clears: deps.dev being down no longer reaches this path.",
            ]))
        }
    }
}

/// The whole script; returns its exit status.
pub fn run() -> i32 {
    let mut root = env_bytes("BUILD_WORKSPACE_DIRECTORY");
    if root.is_empty() {
        let (rc, mut o) = capture("git", &[b"rev-parse", b"--show-toplevel"], true);
        if rc != 0 {
            o.extend_from_slice(&logical_pwd());
            o.push(b'\n');
        }
        root = text::strip_nl(&o);
    }
    if let Err(e) = cd(&root) {
        let reason = match e.kind() {
            std::io::ErrorKind::NotFound => "No such file or directory".to_string(),
            std::io::ErrorKind::PermissionDenied => "Permission denied".to_string(),
            _ => e.to_string(),
        };
        err(format!(
            "osv-scan: cd: {}: {}\n",
            String::from_utf8_lossy(&root),
            reason
        )
        .as_bytes());
        return 1;
    }

    if !on_path("osv-scanner") {
        return die(b"osv-scanner not on PATH.
   CI installs it pinned + checksum-verified (see .github/workflows/supply-chain.yaml).
   Locally: go install github.com/google/osv-scanner/v2/cmd/osv-scanner@v2.6.0");
    }

    // GOWORK=off: go.work.sum can only be written in workspace mode.
    let (k, v) = GOWORK_OFF.split_once('=').expect("NAME=value");
    std::env::set_var(k, v);
    let goflags = env_bytes("GOFLAGS");
    let goflags = if goflags.is_empty() {
        b"-mod=readonly".to_vec()
    } else {
        cat(&[&goflags, b" -mod=readonly"])
    };
    std::env::set_var("GOFLAGS", os(&goflags));

    let mut scan_args: Vec<Vec<u8>> = [
        "scan",
        "source",
        "--recursive",
        "--no-call-analysis=go",
        "--no-call-analysis=rust",
    ]
    .iter()
    .map(|s| s.as_bytes().to_vec())
    .collect();
    if Path::new("osv-scanner.toml").is_file() {
        scan_args.push(b"--config=osv-scanner.toml".to_vec());
    }

    let json = match mktemp_file() {
        Ok(p) => p,
        Err(_) => return 1,
    };
    let scan_err = match mktemp_file() {
        Ok(p) => p,
        Err(_) => return 1,
    };

    let code = (|| {
        info(&cat(&[
            b"scanning ",
            &root,
            b" (recursive; .gitignore excludes bazel-*/node_modules)",
        ]));
        let (snap_rc, tree_before) = dirty_snapshot();
        if snap_rc != 0 {
            return snap_rc;
        }
        let mut ctx = Ctx {
            root: root.clone(),
            scan_args,
            json: json.clone(),
            scan_err: scan_err.clone(),
            tree_before,
            max_attempts: env_or("OSV_MAX_ATTEMPTS", "5"),
            retry_delay: env_or("OSV_RETRY_DELAY", "5"),
        };
        verdict(&mut ctx)
    })();
    let _ = std::fs::remove_file(&json);
    let _ = std::fs::remove_file(&scan_err);
    code
}

/// `${NAME:-default}`.
fn env_or(name: &str, default: &str) -> String {
    let v = env_bytes(name);
    if v.is_empty() {
        default.to_string()
    } else {
        String::from_utf8_lossy(&v).into_owned()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn shell_integers() {
        assert_eq!(test_int("5"), Some(5));
        assert_eq!(test_int(" 05 "), Some(5));
        assert_eq!(test_int("-3"), Some(-3));
        assert_eq!(test_int("1.5"), None);
        assert_eq!(test_int(""), None);
        assert_eq!(arith_double("5").unwrap(), "10");
        assert_eq!(arith_double("010").unwrap(), "16");
        assert_eq!(arith_double("0x10").unwrap(), "32");
        assert_eq!(arith_double("0").unwrap(), "0");
        assert!(arith_double("1.5").is_err());
        assert!(arith_double("08").is_err());
    }

    #[test]
    fn awk_fields() {
        let t = b"COUNTS\t2\t1\nADDED\tGHSA-c hono (4.1) in p\nADDED";
        assert_eq!(awk_field(t, b"COUNTS", 2, b""), b"2");
        assert_eq!(awk_field(t, b"COUNTS", 3, b""), b"1");
        assert_eq!(
            awk_field(t, b"ADDED", 2, b"     "),
            b"     GHSA-c hono (4.1) in p\n     "
        );
    }
}
