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

//! charts:publish, in Rust: publish.sh's walk for every co-located Helm
//! chart (`./**/deploy/chart/Chart.yaml`, outside `./bazel-*`), each packaged
//! with `helm package` and pushed with `helm push` to
//! oci://ghcr.io/vitruviansoftware/charts -- or, on a push with a trustworthy
//! base (BEFORE_REV), only the charts whose directory changed since it.
//! Fail-open as the script is: a manual dispatch, a forced push, or a base
//! git cannot resolve publishes everything.
//!
//! Charts are found in the order find(1) finds them (directory order,
//! preorder), the chart name is read as `awk -F': ' '/^name:/{print $2;
//! exit}'` reads it, the changed-path test is `grep -q "^<dir>/"` (the
//! directory is a basic regular expression there, `.` and all), and the
//! package is the `/tmp/charts/<name>-*.tgz` glob.

use shell_compat::{
    cat, dirname, env, err, out, path, spawn_failure_status, status, status_code, strerror, subst,
};
use std::fs;
use std::os::unix::ffi::{OsStrExt, OsStringExt};
use std::process::{Command, Stdio};

pub const ORG: &str = "vitruviansoftware";
pub const CHART_DIR: &[u8] = b"/tmp/charts";

fn prog() -> Vec<u8> {
    std::env::args_os()
        .next()
        .map(OsStringExt::into_vec)
        .unwrap_or_default()
}

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

fn echo(s: &[u8]) {
    out(&cat(&[s, b"\n"]));
}

// ---------------------------------------------------------------------------
// find . -path '*/deploy/chart/Chart.yaml' -not -path './bazel-*/*'
// ---------------------------------------------------------------------------

/// Whether find's two -path tests select `p` (a path starting `./`).
pub fn is_chart_path(p: &[u8]) -> bool {
    let excluded = p.starts_with(b"./bazel-") && p[8..].contains(&b'/');
    p.ends_with(b"/deploy/chart/Chart.yaml") && !excluded
}

fn find_error(p: &[u8], e: &std::io::Error) {
    let what = strerror(e);
    if cfg!(target_os = "linux") {
        err(&cat(&[b"find: '", p, b"': ", what.as_bytes(), b"\n"]));
    } else {
        err(&cat(&[b"find: ", p, b": ", what.as_bytes(), b"\n"]));
    }
}

/// Preorder walk from `.` in directory order, symlinks not followed, as
/// find(1) walks.
pub fn find_charts() -> Vec<Vec<u8>> {
    let mut found = Vec::new();
    walk(b".", &mut found);
    found
}

fn walk(dir: &[u8], found: &mut Vec<Vec<u8>>) {
    let rd = match fs::read_dir(path(dir)) {
        Ok(rd) => rd,
        Err(e) => {
            find_error(dir, &e);
            return;
        }
    };
    for ent in rd.flatten() {
        let p = cat(&[dir, b"/", ent.file_name().as_bytes()]);
        if is_chart_path(&p) {
            found.push(p.clone());
        }
        if ent.file_type().map_or(false, |t| t.is_dir()) {
            walk(&p, found);
        }
    }
}

// ---------------------------------------------------------------------------
// grep -q "^${reldir}/" <<<"$changed"
// ---------------------------------------------------------------------------

#[derive(Debug, Clone)]
enum Atom {
    Any,
    Lit(u8),
    Class(Vec<(u8, u8)>, bool),
}

#[derive(Debug, Clone)]
struct Piece {
    atom: Atom,
    star: bool,
}

/// A basic regular expression, as grep reads one: `.`, `[...]` (ranges,
/// `^` negation, a leading `]`), `*` after an atom (literal at the start),
/// and `\c` for a literal c. None for an unterminated bracket, which grep
/// refuses (exit 2).
fn compile_bre(re: &[u8]) -> Option<Vec<Piece>> {
    let mut v: Vec<Piece> = Vec::new();
    let mut i = 0;
    while i < re.len() {
        let c = re[i];
        i += 1;
        let atom = match c {
            b'*' if !v.is_empty() => {
                v.last_mut().unwrap().star = true;
                continue;
            }
            b'.' => Atom::Any,
            b'\\' if i < re.len() => {
                i += 1;
                Atom::Lit(re[i - 1])
            }
            b'[' => {
                let mut neg = false;
                if i < re.len() && re[i] == b'^' {
                    neg = true;
                    i += 1;
                }
                let mut set = Vec::new();
                let mut first = true;
                loop {
                    if i >= re.len() {
                        return None;
                    }
                    let a = re[i];
                    if a == b']' && !first {
                        i += 1;
                        break;
                    }
                    first = false;
                    if i + 2 < re.len() && re[i + 1] == b'-' && re[i + 2] != b']' {
                        set.push((a, re[i + 2]));
                        i += 3;
                    } else {
                        set.push((a, a));
                        i += 1;
                    }
                }
                Atom::Class(set, neg)
            }
            _ => Atom::Lit(c),
        };
        v.push(Piece { atom, star: false });
    }
    Some(v)
}

fn atom_matches(a: &Atom, c: u8) -> bool {
    match a {
        Atom::Any => c != b'\n',
        Atom::Lit(l) => *l == c,
        Atom::Class(set, neg) => set.iter().any(|&(lo, hi)| lo <= c && c <= hi) != *neg,
    }
}

fn match_here(p: &[Piece], s: &[u8]) -> bool {
    match p.split_first() {
        None => true,
        Some((first, rest)) => {
            if first.star {
                let mut n = 0;
                while n < s.len() && atom_matches(&first.atom, s[n]) {
                    n += 1;
                }
                loop {
                    if match_here(rest, &s[n..]) {
                        return true;
                    }
                    if n == 0 {
                        return false;
                    }
                    n -= 1;
                }
            } else {
                !s.is_empty() && atom_matches(&first.atom, s[0]) && match_here(rest, &s[1..])
            }
        }
    }
}

/// `grep -q "^<prefix>" <<<"$text"`: whether a line of `text` starts with
/// a match of `prefix`, a basic regular expression. None: grep refused it.
pub fn grep_q_anchored(prefix: &[u8], text: &[u8]) -> Option<bool> {
    let re = compile_bre(prefix)?;
    let mut herestring = text.to_vec();
    herestring.push(b'\n');
    let body = &herestring[..herestring.len() - 1];
    Some(body.split(|&c| c == b'\n').any(|l| match_here(&re, l)))
}

// ---------------------------------------------------------------------------
// awk -F': ' '/^name:/{print $2; exit}' Chart.yaml
// ---------------------------------------------------------------------------

/// The second `: `-separated field of the first line starting `name:`.
pub fn chart_name(chart: &[u8]) -> Vec<u8> {
    let mut body = chart;
    if body.ends_with(b"\n") {
        body = &body[..body.len() - 1];
    }
    if chart.is_empty() {
        return Vec::new();
    }
    for line in body.split(|&c| c == b'\n') {
        if line.starts_with(b"name:") {
            let mut fields = split_on(line, b": ");
            fields.next();
            return fields.next().unwrap_or_default().to_vec();
        }
    }
    Vec::new()
}

fn split_on<'a>(s: &'a [u8], sep: &'a [u8]) -> impl Iterator<Item = &'a [u8]> + 'a {
    let mut rest = Some(s);
    std::iter::from_fn(move || {
        let r = rest?;
        match r.windows(sep.len()).position(|w| w == sep) {
            Some(i) => {
                rest = Some(&r[i + sep.len()..]);
                Some(&r[..i])
            }
            None => {
                rest = None;
                Some(r)
            }
        }
    })
}

// ---------------------------------------------------------------------------
// /tmp/charts/"${name}"-*.tgz
// ---------------------------------------------------------------------------

/// The glob's matches, sorted, or the pattern itself when nothing matches.
pub fn package_glob(name: &[u8]) -> Vec<Vec<u8>> {
    let pattern = cat(&[CHART_DIR, b"/", name, b"-*.tgz"]);
    let lead = cat(&[CHART_DIR, b"/", name, b"-"]);
    let slash = lead.iter().rposition(|&c| c == b'/').unwrap_or(0);
    let (dir, prefix) = (&lead[..slash], &lead[slash + 1..]);
    let mut hits: Vec<Vec<u8>> = match fs::read_dir(path(if dir.is_empty() { b"/" } else { dir })) {
        Ok(rd) => rd
            .flatten()
            .map(|e| e.file_name().as_bytes().to_vec())
            .filter(|f| {
                f.len() >= prefix.len() + 4
                    && f.starts_with(prefix)
                    && f.ends_with(b".tgz")
                    && (f.first() != Some(&b'.') || prefix.first() == Some(&b'.'))
            })
            .map(|f| cat(&[dir, b"/", &f]))
            .collect(),
        Err(_) => Vec::new(),
    };
    if hits.is_empty() {
        return vec![pattern];
    }
    hits.sort();
    hits
}

// ---------------------------------------------------------------------------
// the script
// ---------------------------------------------------------------------------

fn git_capture(args: &[&[u8]], quiet: bool) -> (Vec<u8>, i32) {
    let mut c = Command::new("git");
    for a in args {
        c.arg(shell_compat::os(a));
    }
    c.stdout(Stdio::piped());
    c.stderr(if quiet {
        Stdio::null()
    } else {
        Stdio::inherit()
    });
    match c.output() {
        Ok(o) => (o.stdout, status_code(o.status)),
        Err(e) => {
            if !quiet {
                err(&shell_compat::spawn_diag(64, &c, &e));
            }
            (Vec::new(), spawn_failure_status(&e))
        }
    }
}

fn helm(args: &[&[u8]]) -> i32 {
    let mut c = Command::new("helm");
    for a in args {
        c.arg(shell_compat::os(a));
    }
    c.stdin(Stdio::null());
    status(98, &mut c, false)
}

pub fn run(_args: &[Vec<u8>]) -> i32 {
    let target = match env("BUILD_WORKSPACE_DIRECTORY") {
        Some(v) if !v.is_empty() => v,
        _ => {
            let (mut o, rc) = git_capture(&[b"rev-parse", b"--show-toplevel"], true);
            if rc != 0 {
                o.extend(logical_pwd());
                o.push(b'\n');
            }
            subst(o)
        }
    };
    if !target.is_empty() {
        if let Err(e) = std::env::set_current_dir(path(&target)) {
            err(&diag(
                52,
                &cat(&[b"cd: ", &target, b": ", strerror(&e).as_bytes()]),
            ));
            return 1;
        }
    }

    if let Err(e) = fs::create_dir_all(path(CHART_DIR)) {
        err(&cat(&[
            b"mkdir: ",
            CHART_DIR,
            b": ",
            strerror(&e).as_bytes(),
            b"\n",
        ]));
        return 1;
    }

    let mut publish_all = false;
    let mut changed = Vec::new();
    let before = env("BEFORE_REV").unwrap_or_default();
    if env("GITHUB_EVENT_NAME").as_deref() == Some(b"workflow_dispatch".as_slice()) {
        publish_all = true;
        echo(b"workflow_dispatch -> publishing all charts");
    } else if env("FORCED_PUSH").filter(|v| !v.is_empty()).as_deref() == Some(b"true".as_slice())
        || before.is_empty()
        || {
            let mut c = Command::new("git");
            c.args(["rev-parse", "--verify", "--quiet"])
                .arg(shell_compat::os(&cat(&[&before, b"^{commit}"])))
                .stdout(Stdio::null());
            status(64, &mut c, false) != 0
        }
    {
        publish_all = true;
        echo(b"untrustworthy diff base -> publishing all charts (fail-open)");
    } else {
        let (o, _) = git_capture(&[b"diff", b"--name-only", &before, b"HEAD", b"--"], false);
        changed = subst(o);
    }

    let mut found = false;
    for chart in find_charts() {
        let dir = dirname(&chart);
        let reldir = dir.strip_prefix(b"./".as_slice()).unwrap_or(&dir).to_vec();
        if !publish_all && !grep_q_anchored(&cat(&[&reldir, b"/"]), &changed).unwrap_or(false) {
            echo(&cat(&[b"skipping ", &reldir, b" (unchanged in this push)"]));
            continue;
        }
        let name = subst(chart_name(&fs::read(path(&chart)).unwrap_or_default()));
        echo(&cat(&[b"::group::Packaging ", &name, b" from ", &dir]));
        let rc = helm(&[b"package", &dir, b"-d", CHART_DIR]);
        if rc != 0 {
            return rc;
        }
        let mut push: Vec<Vec<u8>> = vec![b"push".to_vec()];
        push.extend(package_glob(&name));
        push.push(format!("oci://ghcr.io/{}/charts", ORG).into_bytes());
        let refs: Vec<&[u8]> = push.iter().map(Vec::as_slice).collect();
        let rc = helm(&refs);
        if rc != 0 {
            return rc;
        }
        echo(b"::endgroup::");
        found = true;
    }
    if !found {
        echo(b"No charts (re)published this run");
    }
    0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn chart_paths() {
        assert!(is_chart_path(b"./apps/x/deploy/chart/Chart.yaml"));
        assert!(is_chart_path(b"./deploy/chart/Chart.yaml"));
        assert!(!is_chart_path(b"./bazel-out/x/deploy/chart/Chart.yaml"));
        assert!(is_chart_path(b"./x/bazel-out/deploy/chart/Chart.yaml"));
        assert!(!is_chart_path(b"./x/deploy/chart/Chart.yml"));
        assert!(!is_chart_path(b"./x/deploy/charts/Chart.yaml"));
    }

    #[test]
    fn grep_is_anchored_and_a_regex() {
        let changed = b"apps/web/deploy/chart/values.yaml\nREADME.md";
        assert_eq!(
            grep_q_anchored(b"apps/web/deploy/chart/", changed),
            Some(true)
        );
        assert_eq!(grep_q_anchored(b"web/deploy/chart/", changed), Some(false));
        // `.` is any character.
        assert_eq!(grep_q_anchored(b"apps.web/", changed), Some(true));
        assert_eq!(grep_q_anchored(b"a*pps/", changed), Some(true));
        assert_eq!(grep_q_anchored(b"[ab]pps/", changed), Some(true));
        assert_eq!(grep_q_anchored(b"[^a]pps/", changed), Some(false));
        assert_eq!(grep_q_anchored(b"x/", b""), Some(false));
        assert_eq!(grep_q_anchored(b"[x/", changed), None);
    }

    #[test]
    fn name_is_awks_second_field() {
        assert_eq!(
            chart_name(b"apiVersion: v2\nname: tabula\nversion: 1\n"),
            b"tabula"
        );
        assert_eq!(chart_name(b"name: a: b\n"), b"a");
        assert_eq!(chart_name(b"name:nospace\n"), b"");
        assert_eq!(chart_name(b" name: indented\nname: second"), b"second");
        assert_eq!(chart_name(b"name: crlf\r\n"), b"crlf\r");
        assert_eq!(chart_name(b"version: 1\n"), b"");
    }

    #[test]
    fn glob_without_a_match_is_the_pattern() {
        let n = format!("no-such-chart-{}", std::process::id());
        assert_eq!(
            package_glob(n.as_bytes()),
            vec![format!("/tmp/charts/{}-*.tgz", n).into_bytes()]
        );
    }
}
