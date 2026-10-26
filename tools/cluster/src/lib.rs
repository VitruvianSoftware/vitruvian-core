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

//! cluster_cmd.sh in Rust: kubectl behind `bazel run` for live-cluster node
//! operations (see the BUILD file for the ops).
//!
//! Every op runs kubectl with the arguments, environment (KUBECONFIG) and
//! working directory (the workspace) the script gives it. The passthrough ops
//! replace this process with kubectl, as `exec` does. The diagnostics do the
//! script's text stages here: `sort | uniq -c | sort -rn` for `balance` and
//! the awk namespace filter for `minio-status`. Messages, exit statuses and
//! bash's own wording for a missing argument are the script's.

use std::fs;
use std::io::{self, Write};
use std::os::unix::fs::{MetadataExt, PermissionsExt};
use std::os::unix::process::{CommandExt, ExitStatusExt};
use std::path::{Path, PathBuf};
use std::process::{Command, ExitStatus, Stdio};

const OPS: &str =
    "kubectl|cordon|uncordon|drain|delete-node|label-node|balance|placement|minio-status";

const PV_COLUMNS: &str = "custom-columns=PV:.metadata.name,CLAIM:.spec.claimRef.name,NS:.spec.claimRef.namespace,PINNED_NODE:.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values[0]";

const MC_SCRIPT: &str = "mc alias set local http://localhost:9000 \"$MINIO_ROOT_USER\" \"$MINIO_ROOT_PASSWORD\" >/dev/null 2>&1 && mc admin info local";

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

fn say(text: &str) {
    let mut out = io::stdout().lock();
    let _ = out.write_all(text.as_bytes());
    let _ = out.flush();
}

fn say_bytes(bytes: &[u8]) {
    let mut out = io::stdout().lock();
    let _ = out.write_all(bytes);
    let _ = out.flush();
}

fn complain(text: &str) {
    let mut err = io::stderr().lock();
    let _ = writeln!(err, "{text}");
    let _ = err.flush();
}

fn env_nonempty(name: &str) -> Option<String> {
    std::env::var(name).ok().filter(|v| !v.is_empty())
}

/// `command -v <name>` for a name without a slash: the first executable file
/// in a PATH directory (an empty entry is the current directory). Like bash,
/// when no directory has an executable one, the first plain file of that name
/// still counts; running it then fails with "Permission denied".
pub fn on_path(name: &str, path: &str) -> Option<PathBuf> {
    let mut fallback = None;
    for dir in path.split(':') {
        let dir = if dir.is_empty() { "." } else { dir };
        let candidate = Path::new(dir).join(name);
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

/// The directory bash starts in, as its $PWD: the inherited PWD when it names
/// the current directory, else the physical path.
fn shell_pwd() -> String {
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

/// The directory `cd <dir>` leaves in $PWD: <dir> taken from `from` when it
/// is relative, with `.`, `..` and repeated slashes resolved by name.
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

/// The lines a text stream holds, as sort and uniq read them: split on
/// newlines, a final line without one still counts.
fn lines(input: &[u8]) -> Vec<&[u8]> {
    if input.is_empty() {
        return Vec::new();
    }
    let body = input.strip_suffix(b"\n").unwrap_or(input);
    body.split(|&b| b == b'\n').collect()
}

/// The leading number `sort -n` keys on: blanks, an optional minus sign,
/// digits (with an optional fraction). No number reads as zero.
fn numeric_key(line: &[u8]) -> f64 {
    let s = String::from_utf8_lossy(line);
    let t = s.trim_start_matches([' ', '\t']);
    let mut end = 0;
    let bytes = t.as_bytes();
    if end < bytes.len() && bytes[end] == b'-' {
        end += 1;
    }
    let digits_start = end;
    while end < bytes.len() && bytes[end].is_ascii_digit() {
        end += 1;
    }
    if end < bytes.len() && bytes[end] == b'.' {
        end += 1;
        while end < bytes.len() && bytes[end].is_ascii_digit() {
            end += 1;
        }
    }
    if end == digits_start {
        return 0.0;
    }
    t[..end].parse().unwrap_or(0.0)
}

/// The width uniq -c gives its count: BSD (macOS) "%4d ", GNU "%7d ".
pub const UNIQ_WIDTH: usize = if cfg!(target_os = "macos") { 4 } else { 7 };

/// `sort | uniq -c | sort -rn` in the C locale: count each distinct line, most
/// frequent first, ties in reverse byte order of the whole output line.
pub fn count_lines(input: &[u8]) -> Vec<u8> {
    let mut sorted = lines(input);
    sorted.sort();
    let mut counted: Vec<Vec<u8>> = Vec::new();
    let mut i = 0;
    while i < sorted.len() {
        let mut j = i;
        while j < sorted.len() && sorted[j] == sorted[i] {
            j += 1;
        }
        let mut line = format!("{:>width$} ", j - i, width = UNIQ_WIDTH).into_bytes();
        line.extend_from_slice(sorted[i]);
        counted.push(line);
        i = j;
    }
    counted.sort_by(|a, b| {
        numeric_key(b)
            .partial_cmp(&numeric_key(a))
            .unwrap_or(std::cmp::Ordering::Equal)
            .then_with(|| b.cmp(a))
    });
    let mut out = Vec::new();
    for line in counted {
        out.extend_from_slice(&line);
        out.push(b'\n');
    }
    out
}

/// Whether awk would treat a field as a number (a "strnum"): optional blanks,
/// a sign, digits with an optional point and exponent, optional blanks.
fn awk_number(s: &str) -> Option<f64> {
    let t = s.trim_matches([' ', '\t', '\n']);
    let b = t.as_bytes();
    let mut i = 0;
    if i < b.len() && (b[i] == b'+' || b[i] == b'-') {
        i += 1;
    }
    let mut digits = 0;
    while i < b.len() && b[i].is_ascii_digit() {
        i += 1;
        digits += 1;
    }
    if i < b.len() && b[i] == b'.' {
        i += 1;
        while i < b.len() && b[i].is_ascii_digit() {
            i += 1;
            digits += 1;
        }
    }
    if digits == 0 {
        return None;
    }
    if i < b.len() && (b[i] == b'e' || b[i] == b'E') {
        let mut k = i + 1;
        if k < b.len() && (b[k] == b'+' || b[k] == b'-') {
            k += 1;
        }
        let start = k;
        while k < b.len() && b[k].is_ascii_digit() {
            k += 1;
        }
        if k > start {
            i = k;
        }
    }
    if i != b.len() {
        return None;
    }
    t.parse().ok()
}

/// `awk -v ns="$ns" 'NR==1 || $3==ns'`: the header, then the rows whose third
/// field is the namespace (compared as numbers when both look like numbers).
pub fn filter_namespace(input: &[u8], ns: &str) -> Vec<u8> {
    let mut out = Vec::new();
    for (n, line) in lines(input).into_iter().enumerate() {
        let text = String::from_utf8_lossy(line);
        let third = text
            .split([' ', '\t'])
            .filter(|f| !f.is_empty())
            .nth(2)
            .unwrap_or("");
        let matches = match (awk_number(third), awk_number(ns)) {
            (Some(a), Some(b)) => a == b,
            _ => third == ns,
        };
        if n == 0 || matches {
            out.extend_from_slice(line);
            out.push(b'\n');
        }
    }
    out
}

/// `grep -m1 .`: the first line with at least one character.
pub fn first_nonempty_line(input: &[u8]) -> Option<String> {
    lines(input)
        .into_iter()
        .find(|l| !l.is_empty())
        .map(|l| String::from_utf8_lossy(l).into_owned())
}

/// The kubectl argument list for a passthrough op, or None for the others.
pub fn passthrough_args(op: &str, ctx: &str, rest: &[String]) -> Option<Vec<String>> {
    let fixed: &[&str] = match op {
        "kubectl" => &[],
        "cordon" => &["cordon"],
        "uncordon" => &["uncordon"],
        "drain" => &["drain", "--ignore-daemonsets", "--delete-emptydir-data"],
        "delete-node" => &["delete", "node"],
        "label-node" => &["label", "node"],
        "placement" => &[
            "get",
            "pods",
            "-o",
            "custom-columns=POD:.metadata.name,STATUS:.status.phase,NODE:.spec.nodeName",
        ],
        _ => return None,
    };
    let mut args = vec!["--context".to_string(), ctx.to_string()];
    args.extend(fixed.iter().map(|s| s.to_string()));
    args.extend(rest.iter().cloned());
    Some(args)
}

fn exec_line(op: &str) -> u32 {
    match op {
        "kubectl" => 58,
        "cordon" => 60,
        "uncordon" => 61,
        "drain" => 63,
        "delete-node" => 64,
        "label-node" => 65,
        _ => 78,
    }
}

fn kubectl(ctx: &str, args: &[&str]) -> Command {
    let mut cmd = Command::new("kubectl");
    cmd.arg("--context")
        .arg(ctx)
        .args(args)
        .stderr(Stdio::inherit());
    cmd
}

/// Runs a kubectl whose output goes straight to ours; Err(status) when it
/// failed, which ends the op as `set -e` would.
fn run_through(mut cmd: Command) -> Result<(), i32> {
    match cmd.status() {
        Ok(s) if s.success() => Ok(()),
        Ok(s) => Err(status_code(s)),
        Err(_) => Err(127),
    }
}

/// Runs a kubectl and captures its stdout; the status rides along.
fn capture(mut cmd: Command) -> (Vec<u8>, i32) {
    match cmd.stdout(Stdio::piped()).output() {
        Ok(o) => (o.stdout, status_code(o.status)),
        Err(_) => (Vec::new(), 127),
    }
}

fn balance(ctx: &str) -> i32 {
    let (out, status) = capture(kubectl(
        ctx,
        &[
            "get",
            "pods",
            "-A",
            "--field-selector=status.phase=Running",
            "--no-headers",
            "-o",
            "custom-columns=NODE:.spec.nodeName",
        ],
    ));
    say_bytes(&count_lines(&out));
    status
}

fn minio_status(ctx: &str) -> i32 {
    let ns = env_nonempty("MINIO_NS").unwrap_or_else(|| "minio".to_string());
    say("== pods ==\n");
    if let Err(code) = run_through(kubectl(ctx, &["-n", &ns, "get", "pods", "-o", "wide"])) {
        return code;
    }
    say("\n== drive PV node pinning (local-path is node-bound) ==\n");
    let (pv, status) = capture(kubectl(ctx, &["get", "pv", "-o", PV_COLUMNS]));
    say_bytes(&filter_namespace(&pv, &ns));
    if status != 0 {
        return status;
    }
    say("\n== mc admin info (network/drive/heal) ==\n");
    let mut names = kubectl(ctx, &["-n", &ns, "get", "pods", "-o", "name"]);
    names.stderr(Stdio::null());
    let (listing, _) = capture(names);
    match first_nonempty_line(&listing) {
        Some(pod) => {
            let pod = pod.strip_prefix("pod/").unwrap_or(&pod).to_string();
            let exec = kubectl(ctx, &["-n", &ns, "exec", &pod, "--", "sh", "-c", MC_SCRIPT]);
            if run_through(exec).is_err() {
                say("(mc admin info unavailable — pod not ready, or root creds not in env)\n");
            }
        }
        None => say(&format!("(no pods in namespace '{ns}')\n")),
    }
    0
}

/// cluster_cmd.sh. `args` is the op followed by what `--` forwarded; `argv0`
/// stands where bash names the script in its own error messages.
pub fn run(argv0: &str, args: &[String]) -> i32 {
    let op = match args.first() {
        Some(op) if !op.is_empty() => op.clone(),
        _ => {
            complain(&format!("{argv0}: line 40: 1: cluster op required ({OPS})"));
            return 1;
        }
    };
    let rest = &args[1..];

    if env_nonempty("KUBECONFIG").is_none() {
        let Ok(home) = std::env::var("HOME") else {
            complain(&format!("{argv0}: line 43: HOME: unbound variable"));
            return 1;
        };
        std::env::set_var("KUBECONFIG", format!("{home}/.kube/cluster.yaml"));
    }
    let ctx = env_nonempty("KUBE_CONTEXT").unwrap_or_else(|| "default".to_string());

    let Some(found) = on_path("kubectl", &std::env::var("PATH").unwrap_or_default()) else {
        complain("ERROR: kubectl not found on PATH.");
        return 1;
    };

    // bash removes the quotes inside ${VAR:?word}, so the message the script
    // prints has none.
    let Some(workspace) = env_nonempty("BUILD_WORKSPACE_DIRECTORY") else {
        complain(&format!(
            "{argv0}: line 53: BUILD_WORKSPACE_DIRECTORY: this target must be run via bazel run, not bazel build"
        ));
        return 1;
    };
    let old_pwd = shell_pwd();
    if let Err(err) = std::env::set_current_dir(&workspace) {
        complain(&format!(
            "{argv0}: line 53: cd: {workspace}: {}",
            strerror(&err)
        ));
        return 1;
    }
    // bash's cd exports the logical directory as PWD and the old one as
    // OLDPWD, and kubectl (or anything it runs) sees those.
    std::env::set_var("PWD", logical_path(&old_pwd, &workspace));
    std::env::set_var("OLDPWD", old_pwd);

    if let Some(kargs) = passthrough_args(&op, &ctx, rest) {
        let err = Command::new("kubectl").args(&kargs).exec();
        let line = exec_line(&op);
        let (msg, code) = match err.kind() {
            io::ErrorKind::NotFound => ("exec: kubectl: not found".to_string(), 127),
            io::ErrorKind::PermissionDenied => {
                (format!("{}: Permission denied", found.display()), 126)
            }
            _ => (
                format!("exec: kubectl: cannot execute: {}", strerror(&err)),
                126,
            ),
        };
        complain(&format!("{argv0}: line {line}: {msg}"));
        return code;
    }
    match op.as_str() {
        "balance" => balance(&ctx),
        "minio-status" => minio_status(&ctx),
        _ => {
            complain(&format!("ERROR: unknown cluster op '{op}' ({OPS})"));
            2
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn pad(n: usize, rest: &str) -> String {
        format!("{:>w$} {rest}\n", n, w = UNIQ_WIDTH)
    }

    #[test]
    fn balance_counts_most_first_ties_reverse() {
        let got = count_lines(b"nodeA\nnodeB\nnodeB\nnodeC\n");
        let want = pad(2, "nodeB") + &pad(1, "nodeC") + &pad(1, "nodeA");
        assert_eq!(String::from_utf8(got).unwrap(), want);
    }

    #[test]
    fn balance_handles_empty_and_unterminated_input() {
        assert!(count_lines(b"").is_empty());
        assert_eq!(
            String::from_utf8(count_lines(b"x\nx")).unwrap(),
            pad(2, "x")
        );
        assert_eq!(String::from_utf8(count_lines(b"\n")).unwrap(), pad(1, ""));
    }

    #[test]
    fn balance_orders_counts_numerically() {
        let mut input = String::new();
        for _ in 0..10 {
            input.push_str("big\n");
        }
        input.push_str("small\nsmall\n");
        let got = String::from_utf8(count_lines(input.as_bytes())).unwrap();
        assert_eq!(got, pad(10, "big") + &pad(2, "small"));
    }

    #[test]
    fn namespace_filter_keeps_header_and_matching_rows() {
        let table = b"PV CLAIM NS PINNED_NODE\npv1 data-0 minio nuc9\npv2 x other nuc8\npv3 data-1 minio nuc7";
        assert_eq!(
            String::from_utf8(filter_namespace(table, "minio")).unwrap(),
            "PV CLAIM NS PINNED_NODE\npv1 data-0 minio nuc9\npv3 data-1 minio nuc7\n"
        );
    }

    #[test]
    fn namespace_filter_compares_numbers_as_numbers() {
        let table = b"H\na b 1.0 d\na b 1x d\n";
        assert_eq!(
            String::from_utf8(filter_namespace(table, "1")).unwrap(),
            "H\na b 1.0 d\n"
        );
    }

    #[test]
    fn first_pod_is_the_first_nonempty_line() {
        assert_eq!(
            first_nonempty_line(b"\npod/minio-0\npod/minio-1\n"),
            Some("pod/minio-0".into())
        );
        assert_eq!(first_nonempty_line(b"\n\n"), None);
    }

    #[test]
    fn passthrough_ops_bake_their_verbs() {
        let rest = vec!["nuc9".to_string(), "--force".to_string()];
        assert_eq!(
            passthrough_args("drain", "ctx", &rest).unwrap().join(" "),
            "--context ctx drain --ignore-daemonsets --delete-emptydir-data nuc9 --force"
        );
        assert_eq!(
            passthrough_args("kubectl", "c", &[]).unwrap().join(" "),
            "--context c"
        );
        assert_eq!(
            passthrough_args("delete-node", "c", &rest[..1])
                .unwrap()
                .join(" "),
            "--context c delete node nuc9"
        );
        assert!(passthrough_args("balance", "c", &[]).is_none());
        assert!(passthrough_args("bogus", "c", &[]).is_none());
    }

    #[test]
    fn cd_leaves_a_logical_pwd() {
        assert_eq!(logical_path("/a", "/w/x/../y//./"), "/w/y");
        assert_eq!(logical_path("/a/b", "c/.."), "/a/b");
        assert_eq!(logical_path("/a", "/"), "/");
    }

    #[test]
    fn missing_op_is_refused() {
        assert_eq!(run("p", &[]), 1);
        assert_eq!(run("p", &[String::new()]), 1);
    }
}
