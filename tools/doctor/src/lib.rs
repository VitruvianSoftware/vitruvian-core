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

//! `doctor` — developer-environment checker for the vitruvian-core monorepo.
//!
//! A Rust port of `doctor.sh`, held to it byte for byte by
//! `doctor_rs_parity_test.py`: the same flags, the same source-of-truth
//! readers (.bazelversion / .nvmrc / package.json / go.mod), the same tool
//! probes (same argv, same stderr handling), the same report and exit code.
//!
//! Values are handled as bytes, never decoded, as the shell does. Column
//! widths count bytes: what bash's `${#var}` counts in the C locale, and what
//! its `printf '%-*s'` pads by in every locale. With a UTF-8 locale and a
//! non-ASCII tool name or version, bash itself counts characters for the width
//! but pads by bytes, so the shell's table is ragged there; this port's is not.
//!
//! Not reproduced, by choice: a key or a value with a glob character (the
//! shell expands it against the working directory), a value holding the
//! shell's internal \x1e / \x1f row separators, shell builtins, functions or
//! keywords used as tool keys (`command -v` finds those; this port only looks
//! on PATH), and `--required` / `--optional` / `--gomod` as the LAST argument
//! with no value, where the shell's `shift 2` fails and it loops forever; here
//! the value is empty and parsing ends.

use std::ffi::{OsStr, OsString};
use std::fs::{self, File};
use std::io::{IsTerminal, Read, Write};
use std::os::unix::ffi::{OsStrExt, OsStringExt};
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

pub const GLYPH_OK: &str = "✓";
pub const GLYPH_WARN: &str = "⚠";
pub const GLYPH_FAIL: &str = "✗";

/// ANSI colours, all empty unless stdout is a terminal.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Colors {
    pub reset: &'static str,
    pub green: &'static str,
    pub yellow: &'static str,
    pub red: &'static str,
    pub dim: &'static str,
    pub bold: &'static str,
}

impl Colors {
    pub fn for_tty(tty: bool) -> Colors {
        if tty {
            Colors {
                reset: "\x1b[0m",
                green: "\x1b[32m",
                yellow: "\x1b[33m",
                red: "\x1b[31m",
                dim: "\x1b[2m",
                bold: "\x1b[1m",
            }
        } else {
            Colors::default()
        }
    }
}

/// The flags the `doctor(...)` macro bakes in.
#[derive(Debug, Default, PartialEq, Eq)]
pub struct Options {
    pub label: Vec<u8>,
    pub required_csv: Vec<u8>,
    pub optional_csv: Vec<u8>,
    pub gomod_rel: Vec<u8>,
}

/// Parses argv (without the program name). Warnings for unknown arguments are
/// appended to `stderr`, one line each, as doctor.sh prints them.
///
/// Bazel's `args` word-splits each element, so a multi-word label arrives as
/// several tokens: every token after `--label` up to the next `--*` is joined
/// with single spaces (`${LABEL:+$LABEL }$1`).
pub fn parse_args(args: &[Vec<u8>], stderr: &mut Vec<u8>) -> Options {
    let mut o = Options::default();
    let mut i = 0;
    while i < args.len() {
        let a = args[i].as_slice();
        match a {
            b"--label" => {
                i += 1;
                o.label.clear();
                while i < args.len() && !args[i].starts_with(b"--") {
                    if !o.label.is_empty() {
                        o.label.push(b' ');
                    }
                    o.label.extend_from_slice(&args[i]);
                    i += 1;
                }
            }
            b"--required" | b"--optional" | b"--gomod" => {
                let v = args.get(i + 1).cloned().unwrap_or_default();
                match a {
                    b"--required" => o.required_csv = v,
                    b"--optional" => o.optional_csv = v,
                    _ => o.gomod_rel = v,
                }
                i += 2;
            }
            _ => {
                stderr.extend_from_slice(b"doctor: ignoring unknown arg '");
                stderr.extend_from_slice(a);
                stderr.extend_from_slice(b"'\n");
                i += 1;
            }
        }
    }
    o
}

/// `tr ',' ' '` then the shell's word splitting (space, tab, newline):
/// empty keys disappear.
pub fn csv_to_keys(csv: &[u8]) -> Vec<Vec<u8>> {
    csv.split(|b| matches!(b, b',' | b' ' | b'\t' | b'\n'))
        .filter(|k| !k.is_empty())
        .map(<[u8]>::to_vec)
        .collect()
}

/// awk's first record of a file: everything up to the first newline, or
/// `None` for an empty file (awk then prints nothing).
fn first_record(content: &[u8]) -> Option<&[u8]> {
    if content.is_empty() {
        return None;
    }
    Some(content.split(|&b| b == b'\n').next().unwrap_or_default())
}

/// `gsub(/^[<lead>]+|[ \t\r]+$/, "")` on one line.
fn trim_line<'a>(line: &'a [u8], lead: &[u8]) -> &'a [u8] {
    let start = line
        .iter()
        .position(|b| !lead.contains(b))
        .unwrap_or(line.len());
    let rest = &line[start..];
    let end = rest
        .iter()
        .rposition(|b| !matches!(b, b' ' | b'\t' | b'\r'))
        .map_or(0, |p| p + 1);
    &rest[..end]
}

/// .bazelversion: a bare version on the first line.
pub fn parse_bazelversion(content: &[u8]) -> Vec<u8> {
    first_record(content).map_or_else(Vec::new, |l| trim_line(l, b" \t").to_vec())
}

/// .nvmrc: a bare version, optionally prefixed with `v`.
pub fn parse_nvmrc(content: &[u8]) -> Vec<u8> {
    first_record(content).map_or_else(Vec::new, |l| trim_line(l, b" \tv").to_vec())
}

/// package.json: on the first line holding `"packageManager"` whose
/// `.*pnpm@\([0-9][0-9.]*\).*` matches, the digits and dots after the LAST
/// `pnpm@<digit>` (the leading `.*` is greedy).
pub fn parse_package_json_pnpm(content: &[u8]) -> Vec<u8> {
    for line in lines(content) {
        if !contains(line, b"\"packageManager\"") {
            continue;
        }
        let mut found = None;
        let mut i = 0;
        while i + 5 < line.len() {
            if &line[i..i + 5] == b"pnpm@" && line[i + 5].is_ascii_digit() {
                found = Some(i + 5);
            }
            i += 1;
        }
        if let Some(s) = found {
            let n = line[s..]
                .iter()
                .take_while(|b| b.is_ascii_digit() || **b == b'.')
                .count();
            return line[s..s + n].to_vec();
        }
    }
    Vec::new()
}

/// go.mod: `awk '$1 == "go" { print $2; exit }'` (fields split on blanks).
pub fn parse_gomod(content: &[u8]) -> Vec<u8> {
    for line in lines(content) {
        let mut fields = line
            .split(|b| matches!(b, b' ' | b'\t'))
            .filter(|f| !f.is_empty());
        if fields.next() == Some(b"go".as_slice()) {
            return fields.next().unwrap_or_default().to_vec();
        }
    }
    Vec::new()
}

/// The lines grep, sed and awk see: split on newline, with no empty record
/// after a trailing newline.
fn lines(content: &[u8]) -> impl Iterator<Item = &[u8]> {
    let body = content.strip_suffix(b"\n").unwrap_or(content);
    let empty = content.is_empty();
    body.split(|&b| b == b'\n').filter(move |_| !empty)
}

fn contains(hay: &[u8], needle: &[u8]) -> bool {
    hay.windows(needle.len()).any(|w| w == needle)
}

/// The first dotted numeric version (X.Y or X.Y.Z) in arbitrary output:
/// `tr -c '0-9.' '\n' | grep '^[0-9][0-9]*\.[0-9]' | head -1 | sed 's/\.*$//'`.
pub fn extract_version(raw: &[u8]) -> Vec<u8> {
    for tok in raw.split(|b| !(b.is_ascii_digit() || *b == b'.')) {
        let digits = tok.iter().take_while(|b| b.is_ascii_digit()).count();
        if digits > 0
            && tok.get(digits) == Some(&b'.')
            && tok.get(digits + 1).is_some_and(u8::is_ascii_digit)
        {
            let end = tok.iter().rposition(|b| *b != b'.').map_or(0, |p| p + 1);
            return tok[..end].to_vec();
        }
    }
    Vec::new()
}

/// `printf '%s' "$1" | cut -d. -f"$2"`: a value with no dot is printed whole
/// for every field; past the last field it is empty.
pub fn field(s: &[u8], n: usize) -> Vec<u8> {
    if !s.contains(&b'.') {
        return s.to_vec();
    }
    s.split(|b| *b == b'.')
        .nth(n - 1)
        .unwrap_or_default()
        .to_vec()
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Verdict {
    Ok,
    Patch,
    Mismatch,
    Unknown,
}

/// major.minor equal and patch equal → Ok; patch only differs → Patch;
/// major or minor differ → Mismatch; either side empty → Unknown. A missing
/// patch counts as 0.
pub fn compare_versions(found: &[u8], expected: &[u8]) -> Verdict {
    if found.is_empty() || expected.is_empty() {
        return Verdict::Unknown;
    }
    let zero = |v: Vec<u8>| if v.is_empty() { b"0".to_vec() } else { v };
    if field(found, 1) != field(expected, 1) || field(found, 2) != field(expected, 2) {
        Verdict::Mismatch
    } else if zero(field(found, 3)) != zero(field(expected, 3)) {
        Verdict::Patch
    } else {
        Verdict::Ok
    }
}

/// The binary behind a tool key (lima → limactl).
pub fn tool_binary(key: &[u8]) -> &[u8] {
    if key == b"lima" {
        b"limactl"
    } else {
        key
    }
}

/// Pinned tools are compared against a source-of-truth file.
pub fn is_pinned(key: &[u8]) -> bool {
    matches!(key, b"bazel" | b"node" | b"pnpm" | b"go")
}

/// A short, actionable fix hint per tool.
pub fn fix_hint(key: &[u8], expected: &[u8]) -> Vec<u8> {
    let s: &str = match key {
        b"bazel" => "install Bazelisk so `bazel` honors .bazelversion",
        b"node" => "nvm use (reads .nvmrc)",
        b"pnpm" => "corepack enable",
        b"go" => {
            let mut v = b"install Go ".to_vec();
            v.extend_from_slice(if expected.is_empty() {
                b"<expected>"
            } else {
                expected
            });
            return v;
        }
        b"git" => "install git (xcode-select --install or your package manager)",
        b"gh" => "install GitHub CLI: https://cli.github.com/",
        b"gcloud" => "install the Google Cloud SDK: https://cloud.google.com/sdk/docs/install",
        b"docker" => "start Docker/colima",
        b"direnv" => "install direnv + hook your shell: https://direnv.net/",
        b"mage" => "install mage: https://magefile.org/",
        b"mise" => "install mise: https://mise.jdx.dev/",
        b"lima" => "install Lima: https://lima-vm.io/",
        b"swift" => "install Swift toolchain (Xcode or swift.org)",
        b"python3" => "install Python 3: https://www.python.org/downloads/",
        b"goreleaser" => "install GoReleaser: https://goreleaser.com/install/",
        _ => {
            let mut v = b"install ".to_vec();
            v.extend_from_slice(key);
            return v;
        }
    };
    s.as_bytes().to_vec()
}

/// The first `n` lines of `out`, as `head -n` keeps them.
pub fn head_lines(out: &[u8], n: usize) -> &[u8] {
    let mut seen = 0;
    for (i, b) in out.iter().enumerate() {
        if *b == b'\n' {
            seen += 1;
            if seen == n {
                return &out[..=i];
            }
        }
    }
    out
}

/// The rest of the first line starting `Build label:`, with leading blanks
/// dropped (`sed -n 's/^Build label:[ \t]*//p' | head -1`); `None` when no
/// line starts that way.
pub fn bazel_build_label(out: &[u8]) -> Option<Vec<u8>> {
    lines(out).find_map(|l| {
        l.strip_prefix(b"Build label:".as_slice()).map(|rest| {
            let n = rest
                .iter()
                .take_while(|b| matches!(b, b' ' | b'\t'))
                .count();
            rest[n..].to_vec()
        })
    })
}

/// One report row.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Row {
    pub glyph: &'static str,
    pub color: &'static str,
    pub tool: Vec<u8>,
    pub found: Vec<u8>,
    pub expected: Vec<u8>,
    pub hint: Vec<u8>,
}

/// The tally behind the summary line.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Counts {
    pub ok: usize,
    pub warn: usize,
    pub fail: usize,
}

fn pad(out: &mut Vec<u8>, s: &[u8], width: usize) {
    out.extend_from_slice(s);
    for _ in s.len()..width {
        out.push(b' ');
    }
}

/// The report: header, aligned table, summary line.
pub fn render(label: &[u8], rows: &[Row], counts: Counts, failed: bool, c: Colors) -> Vec<u8> {
    let mut out = Vec::new();
    out.push(b'\n');
    out.extend_from_slice(format!("{}{}doctor{} — ", c.bold, c.green, c.reset).as_bytes());
    out.extend_from_slice(if label.is_empty() {
        b"vitruvian-core"
    } else {
        label
    });
    out.push(b'\n');
    out.extend_from_slice(
        format!("{}developer-environment check{}\n\n", c.dim, c.reset).as_bytes(),
    );

    let w_tool = rows.iter().map(|r| r.tool.len()).fold(4, usize::max);
    let w_found = rows.iter().map(|r| r.found.len()).fold(5, usize::max);
    let w_exp = rows.iter().map(|r| r.expected.len()).fold(8, usize::max);

    out.extend_from_slice(b"  ");
    pad(&mut out, b"", 2);
    out.extend_from_slice(b"  ");
    pad(&mut out, b"TOOL", w_tool);
    out.extend_from_slice(b"  ");
    pad(&mut out, b"FOUND", w_found);
    out.extend_from_slice(b"  ");
    pad(&mut out, b"EXPECTED", w_exp);
    out.push(b'\n');

    for r in rows {
        out.extend_from_slice(format!("  {}{}{}  ", r.color, r.glyph, c.reset).as_bytes());
        pad(&mut out, &r.tool, w_tool);
        out.extend_from_slice(b"  ");
        pad(&mut out, &r.found, w_found);
        out.extend_from_slice(b"  ");
        pad(&mut out, &r.expected, w_exp);
        if !r.hint.is_empty() {
            out.extend_from_slice(format!("  {}→ fix: ", c.dim).as_bytes());
            out.extend_from_slice(&r.hint);
            out.extend_from_slice(c.reset.as_bytes());
        }
        out.push(b'\n');
    }

    out.push(b'\n');
    let line = if failed {
        format!(
            "{}{} FAIL{} — {} ok, {} warn, {} fail. Required checks did not pass.\n",
            c.red, GLYPH_FAIL, c.reset, counts.ok, counts.warn, counts.fail
        )
    } else {
        format!(
            "{}{} PASS{} — {} ok, {} warn, {} fail.\n",
            c.green, GLYPH_OK, c.reset, counts.ok, counts.warn, counts.fail
        )
    };
    out.extend_from_slice(line.as_bytes());
    out.extend_from_slice(
        format!(
            "{}See CONTRIBUTING.md for the full toolchain setup.{}\n",
            c.dim, c.reset
        )
        .as_bytes(),
    );
    out
}

// ---------------------------------------------------------------------------
// The live side: PATH lookups, child processes, files.
// ---------------------------------------------------------------------------

fn os(b: &[u8]) -> &OsStr {
    OsStr::from_bytes(b)
}

fn join(dir: &[u8], name: &[u8]) -> PathBuf {
    let mut p = dir.to_vec();
    p.push(b'/');
    p.extend_from_slice(name);
    PathBuf::from(OsString::from_vec(p))
}

/// `[ -f path ]` then the file's bytes; `None` if it is not a regular file.
fn read_regular(path: &Path) -> Option<Vec<u8>> {
    if fs::metadata(path).map(|m| m.is_file()).unwrap_or(false) {
        Some(fs::read(path).unwrap_or_default())
    } else {
        None
    }
}

fn is_executable(m: &fs::Metadata) -> bool {
    m.permissions().mode() & 0o111 != 0
}

/// bash's `command -v NAME` for a command on PATH: the first executable
/// non-directory along PATH (an empty entry is the current directory); failing
/// that, a non-executable file still counts, as bash reports it too.
pub fn command_exists(name: &[u8], path_env: Option<&[u8]>) -> bool {
    if name.contains(&b'/') {
        return fs::metadata(os(name))
            .map(|m| !m.is_dir() && is_executable(&m))
            .unwrap_or(false);
    }
    let mut fallback = false;
    for dir in path_env.unwrap_or_default().split(|b| *b == b':') {
        let dir: &[u8] = if dir.is_empty() { b"." } else { dir };
        if let Ok(m) = fs::metadata(join(dir, name)) {
            if m.is_dir() {
                continue;
            }
            if is_executable(&m) {
                return true;
            }
            fallback = true;
        }
    }
    fallback
}

/// Runs a command as `$(cmd args 2>/dev/null)` does (stdin inherited) and
/// returns its stdout; with `merge_stderr`, as `$(cmd args 2>&1)`. NUL bytes
/// are dropped, as bash drops them from a command substitution. A command that
/// cannot be started yields nothing.
pub fn capture(argv: &[&[u8]], merge_stderr: bool) -> Vec<u8> {
    let mut cmd = Command::new(os(argv[0]));
    for a in &argv[1..] {
        cmd.arg(os(a));
    }
    cmd.stdin(Stdio::inherit());
    let mut out = Vec::new();
    if merge_stderr {
        // One file behind both descriptors keeps the two streams in the
        // order the child wrote them, as a shared pipe does.
        let path = std::env::temp_dir().join(format!("doctor-probe-{}", std::process::id()));
        let Ok(f) = File::options()
            .read(true)
            .write(true)
            .create(true)
            .truncate(true)
            .open(&path)
        else {
            return out;
        };
        let _ = fs::remove_file(&path);
        let (Ok(o), Ok(e), Ok(mut r)) = (f.try_clone(), f.try_clone(), f.try_clone()) else {
            return out;
        };
        cmd.stdout(o).stderr(e);
        if cmd.status().is_ok() {
            use std::io::{Seek, SeekFrom};
            let _ = r.seek(SeekFrom::Start(0));
            let _ = r.read_to_end(&mut out);
        }
    } else {
        cmd.stdout(Stdio::piped()).stderr(Stdio::null());
        if let Ok(o) = cmd.output() {
            out = o.stdout;
        }
    }
    out.retain(|b| *b != 0);
    out
}

/// The exit status of `cmd args >/dev/null 2>&1`, stdin inherited.
fn succeeds(argv: &[&[u8]]) -> bool {
    let mut cmd = Command::new(os(argv[0]));
    for a in &argv[1..] {
        cmd.arg(os(a));
    }
    cmd.stdin(Stdio::inherit())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

/// The parsed version a tool reports, or empty.
pub fn probe_version(key: &[u8]) -> Vec<u8> {
    let raw: Vec<u8> = match key {
        b"bazel" => {
            let label = bazel_build_label(&capture(&[b"bazel", b"version"], false));
            match label {
                Some(l) if !l.is_empty() => l,
                _ => capture(&[b"bazel", b"version"], false),
            }
        }
        b"node" | b"pnpm" | b"docker" | b"direnv" => capture(&[key, b"--version"], false),
        b"go" | b"git" => {
            let arg: &[u8] = if key == b"go" {
                b"version"
            } else {
                b"--version"
            };
            capture(&[key, arg], false)
        }
        b"mage" => head_lines(&capture(&[key, b"--version"], false), 2).to_vec(),
        b"goreleaser" => head_lines(&capture(&[key, b"--version"], false), 5).to_vec(),
        b"lima" => head_lines(&capture(&[b"limactl", b"--version"], false), 1).to_vec(),
        b"python3" => head_lines(&capture(&[key, b"--version"], true), 1).to_vec(),
        _ => head_lines(&capture(&[key, b"--version"], false), 1).to_vec(),
    };
    extract_version(&raw)
}

/// Where the source-of-truth files are read from.
pub struct Sources {
    pub root: Vec<u8>,
    pub gomod_rel: Vec<u8>,
}

impl Sources {
    fn read(&self, rel: &[u8]) -> Option<Vec<u8>> {
        read_regular(&join(&self.root, rel))
    }

    /// The expected version for a pinned key (empty for the rest, or when the
    /// file or field is absent).
    pub fn expected_for(&self, key: &[u8]) -> Vec<u8> {
        match key {
            b"bazel" => self
                .read(b".bazelversion")
                .map_or_else(Vec::new, |c| parse_bazelversion(&c)),
            b"node" => self
                .read(b".nvmrc")
                .map_or_else(Vec::new, |c| parse_nvmrc(&c)),
            b"pnpm" => self
                .read(b"package.json")
                .map_or_else(Vec::new, |c| parse_package_json_pnpm(&c)),
            b"go" if !self.gomod_rel.is_empty() => self
                .read(&self.gomod_rel)
                .map_or_else(Vec::new, |c| parse_gomod(&c)),
            _ => Vec::new(),
        }
    }
}

struct Report {
    rows: Vec<Row>,
    counts: Counts,
    failed: bool,
    c: Colors,
}

impl Report {
    fn add(
        &mut self,
        glyph: &'static str,
        tool: &[u8],
        found: Vec<u8>,
        expected: Vec<u8>,
        hint: Vec<u8>,
    ) {
        let color = match glyph {
            GLYPH_OK => {
                self.counts.ok += 1;
                self.c.green
            }
            GLYPH_WARN => {
                self.counts.warn += 1;
                self.c.yellow
            }
            _ => {
                self.counts.fail += 1;
                self.failed = true;
                self.c.red
            }
        };
        self.rows.push(Row {
            glyph,
            color,
            tool: tool.to_vec(),
            found,
            expected,
            hint,
        });
    }
}

fn check_tool(
    rep: &mut Report,
    src: &Sources,
    path_env: Option<&[u8]>,
    key: &[u8],
    required: bool,
) {
    let bad = if required { GLYPH_FAIL } else { GLYPH_WARN };

    if !command_exists(tool_binary(key), path_env) {
        let expected = src.expected_for(key);
        let hint = fix_hint(key, &src.expected_for(key));
        rep.add(bad, key, b"not found".to_vec(), expected, hint);
        return;
    }

    let mut found = probe_version(key);
    if found.is_empty() {
        found = b"present".to_vec();
    }
    let expected = src.expected_for(key);

    if key == b"docker" {
        if succeeds(&[b"docker", b"info"]) {
            rep.add(GLYPH_OK, key, found, Vec::new(), Vec::new());
        } else {
            found.extend_from_slice(b" (daemon down)");
            rep.add(bad, key, found, Vec::new(), fix_hint(b"docker", b""));
        }
        return;
    }

    if is_pinned(key) && !expected.is_empty() {
        match compare_versions(&found, &expected) {
            Verdict::Ok => rep.add(GLYPH_OK, key, found, expected, Vec::new()),
            Verdict::Patch => rep.add(
                GLYPH_OK,
                key,
                found,
                expected,
                b"patch differs (ok)".to_vec(),
            ),
            Verdict::Mismatch => {
                let hint = fix_hint(key, &expected);
                rep.add(bad, key, found, expected, hint);
            }
            Verdict::Unknown => rep.add(
                GLYPH_WARN,
                key,
                found,
                expected,
                b"could not parse version".to_vec(),
            ),
        }
        return;
    }

    rep.add(GLYPH_OK, key, found, Vec::new(), Vec::new());
}

const CACHE_MARKER: &[u8] = b"# >>> build cache (managed by tools/remote:setup)";

/// The workspace root for the build-cache check: BUILD_WORKSPACE_DIRECTORY,
/// else `git rev-parse --show-toplevel`, else the working directory.
fn cache_root(bwd: Option<&[u8]>) -> Vec<u8> {
    if let Some(b) = bwd {
        return b.to_vec();
    }
    let mut cmd = Command::new("git");
    cmd.args(["rev-parse", "--show-toplevel"])
        .stdin(Stdio::inherit())
        .stdout(Stdio::piped())
        .stderr(Stdio::null());
    if let Ok(o) = cmd.output() {
        if o.status.success() {
            let mut v = o.stdout;
            v.retain(|b| *b != 0);
            while v.last() == Some(&b'\n') {
                v.pop();
            }
            return v;
        }
    }
    std::env::current_dir()
        .map(|p| p.into_os_string().into_vec())
        .unwrap_or_default()
}

fn env_nonempty(name: &str) -> Option<Vec<u8>> {
    std::env::var_os(name)
        .map(OsString::into_vec)
        .filter(|v| !v.is_empty())
}

/// Runs the whole check with the process environment. Returns the exit code
/// and the bytes for stdout and stderr.
pub fn run(args: &[OsString], tty: bool) -> (i32, Vec<u8>, Vec<u8>) {
    let mut err = Vec::new();
    let argv: Vec<Vec<u8>> = args.iter().map(|a| a.as_bytes().to_vec()).collect();
    let opts = parse_args(&argv, &mut err);

    let bwd = env_nonempty("BUILD_WORKSPACE_DIRECTORY");
    let root = bwd.clone().unwrap_or_else(|| {
        // $PWD: the same directory (bash re-derives a stale one at start).
        std::env::current_dir()
            .map(|p| p.into_os_string().into_vec())
            .unwrap_or_default()
    });
    let src = Sources {
        root,
        gomod_rel: opts.gomod_rel.clone(),
    };
    let path_env = std::env::var_os("PATH").map(OsString::into_vec);

    let mut rep = Report {
        rows: Vec::new(),
        counts: Counts::default(),
        failed: false,
        c: Colors::for_tty(tty),
    };
    for k in csv_to_keys(&opts.required_csv) {
        check_tool(&mut rep, &src, path_env.as_deref(), &k, true);
    }
    for k in csv_to_keys(&opts.optional_csv) {
        check_tool(&mut rep, &src, path_env.as_deref(), &k, false);
    }

    let wsroot = cache_root(bwd.as_deref());
    let configured = read_regular(&join(&wsroot, b"user.bazelrc"))
        .map(|c| lines(&c).any(|l| l.starts_with(CACHE_MARKER)))
        .unwrap_or(false);
    if configured {
        rep.add(
            GLYPH_OK,
            b"build-cache",
            b"configured".to_vec(),
            b"shared default".to_vec(),
            Vec::new(),
        );
    } else {
        rep.add(
            GLYPH_WARN,
            b"build-cache",
            b"not set up".to_vec(),
            b"shared default".to_vec(),
            b"run: bazel run //tools/remote:setup (makes the BuildBuddy cache the local default, #506)"
                .to_vec(),
        );
    }

    let out = render(&opts.label, &rep.rows, rep.counts, rep.failed, rep.c);
    (i32::from(rep.failed), out, err)
}

/// The binary's entry point: parse, check, print, return the exit code.
pub fn main_with_args(args: &[OsString]) -> i32 {
    let tty = std::io::stdout().is_terminal();
    let (code, out, err) = run(args, tty);
    let _ = std::io::stderr().write_all(&err);
    let mut so = std::io::stdout().lock();
    let _ = so.write_all(&out);
    let _ = so.flush();
    code
}

#[cfg(test)]
mod tests {
    use super::*;

    fn v(s: &str) -> Vec<u8> {
        s.as_bytes().to_vec()
    }

    #[test]
    fn label_joins_tokens_until_next_flag() {
        let mut err = Vec::new();
        let args: Vec<Vec<u8>> = [
            "--label",
            "vitruvian-core",
            "(core",
            "toolchain)",
            "--required",
            "bazel,git",
        ]
        .iter()
        .map(|s| v(s))
        .collect();
        let o = parse_args(&args, &mut err);
        assert_eq!(o.label, v("vitruvian-core (core toolchain)"));
        assert_eq!(o.required_csv, v("bazel,git"));
        assert!(err.is_empty());
    }

    #[test]
    fn label_with_empty_tokens_keeps_shell_spacing() {
        let mut err = Vec::new();
        let args: Vec<Vec<u8>> = ["--label", "", "a", "", "b"].iter().map(|s| v(s)).collect();
        assert_eq!(parse_args(&args, &mut err).label, v("a  b"));
    }

    #[test]
    fn unknown_args_warn() {
        let mut err = Vec::new();
        let args: Vec<Vec<u8>> = ["--label", "x", "--bogus", ""]
            .iter()
            .map(|s| v(s))
            .collect();
        let o = parse_args(&args, &mut err);
        assert_eq!(o.label, v("x"));
        assert_eq!(
            String::from_utf8(err).unwrap(),
            "doctor: ignoring unknown arg '--bogus'\ndoctor: ignoring unknown arg ''\n"
        );
    }

    #[test]
    fn csv_drops_empties_and_splits_blanks() {
        assert_eq!(
            csv_to_keys(b",bazel,,go git,\t"),
            vec![v("bazel"), v("go"), v("git")]
        );
        assert!(csv_to_keys(b"").is_empty());
    }

    #[test]
    fn source_readers() {
        assert_eq!(parse_bazelversion(b" \t9.3.0 \r\nnext\n"), v("9.3.0"));
        assert_eq!(parse_bazelversion(b""), v(""));
        assert_eq!(parse_nvmrc(b"vv22.21.1\r\n"), v("22.21.1"));
        assert_eq!(
            parse_package_json_pnpm(b"{\n  \"packageManager\": \"pnpm@10.20.0+sha512.abc\"\n}\n"),
            v("10.20.0")
        );
        assert_eq!(
            parse_package_json_pnpm(b"\"packageManager\": \"pnpm@1.2 pnpm@3.4.5\""),
            v("3.4.5")
        );
        assert_eq!(
            parse_package_json_pnpm(b"\"packageManager\": \"npm@1\""),
            v("")
        );
        assert_eq!(
            parse_gomod(b"module x\n\n  go\t1.25.5\ntoolchain go1.26\n"),
            v("1.25.5")
        );
        assert_eq!(parse_gomod(b"go\n"), v(""));
    }

    #[test]
    fn extract_version_cases() {
        assert_eq!(extract_version(b"v26.4.0"), v("26.4.0"));
        assert_eq!(
            extract_version(b"go version go1.25.5 darwin/arm64"),
            v("1.25.5")
        );
        assert_eq!(
            extract_version(b"Docker version 29.6.0, build x"),
            v("29.6.0")
        );
        assert_eq!(extract_version(b"version 7 then 1.2..."), v("1.2"));
        assert_eq!(extract_version(b".5.6 1."), v(""));
        assert_eq!(extract_version(b"no digits"), v(""));
    }

    #[test]
    fn field_follows_cut() {
        assert_eq!(field(b"1.2", 3), v(""));
        assert_eq!(field(b"present", 2), v("present"));
        assert_eq!(field(b"1.2.3.4", 2), v("2"));
    }

    #[test]
    fn compare_cases() {
        assert_eq!(compare_versions(b"9.3.0", b"9.3.0"), Verdict::Ok);
        assert_eq!(compare_versions(b"22.21", b"22.21.0"), Verdict::Ok);
        assert_eq!(compare_versions(b"22.21.2", b"22.21.1"), Verdict::Patch);
        assert_eq!(compare_versions(b"9.4.0", b"9.3.0"), Verdict::Mismatch);
        assert_eq!(compare_versions(b"present", b"9.3.0"), Verdict::Mismatch);
        assert_eq!(compare_versions(b"", b"1"), Verdict::Unknown);
    }

    #[test]
    fn hints() {
        assert_eq!(fix_hint(b"go", b""), v("install Go <expected>"));
        assert_eq!(fix_hint(b"go", b"1.25.5"), v("install Go 1.25.5"));
        assert_eq!(fix_hint(b"zig", b""), v("install zig"));
        assert_eq!(tool_binary(b"lima"), b"limactl");
    }

    #[test]
    fn head_and_label() {
        assert_eq!(head_lines(b"a\nb\nc", 2), b"a\nb\n");
        assert_eq!(head_lines(b"a", 1), b"a");
        assert_eq!(
            bazel_build_label(b"Bazelisk version: 1.2\nBuild label: 9.3.0\n"),
            Some(v("9.3.0"))
        );
        assert_eq!(bazel_build_label(b"x\n"), None);
    }

    #[test]
    fn render_pads_and_summarises() {
        let rows = vec![Row {
            glyph: GLYPH_FAIL,
            color: "",
            tool: v("bazel"),
            found: v("not found"),
            expected: v("9.3.0"),
            hint: v("h"),
        }];
        let out = String::from_utf8(render(
            b"",
            &rows,
            Counts {
                ok: 0,
                warn: 0,
                fail: 1,
            },
            true,
            Colors::default(),
        ))
        .unwrap();
        assert_eq!(
            out,
            "\ndoctor — vitruvian-core\ndeveloper-environment check\n\n      TOOL   FOUND      EXPECTED\n  ✗  bazel  not found  9.3.0     → fix: h\n\n✗ FAIL — 0 ok, 0 warn, 1 fail. Required checks did not pass.\nSee CONTRIBUTING.md for the full toolchain setup.\n"
        );
    }
}
