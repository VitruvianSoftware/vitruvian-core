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

//! appset-render, the Rust port of main.go: simulate ArgoCD ApplicationSet
//! goTemplate parsing, offline.
//!
//! Why it exists, and why it parses rather than renders, is in main.go's
//! header: issue #414 was a stray backtick that closed a Go raw string early
//! and broke goTemplate rendering of a whole appset, which static schema
//! validation cannot see. ArgoCD parses with Go's text/template plus sprig
//! under `missingkey=zero`; src/parse.rs is that parser, ported, so this
//! agrees with the controller on what parses, and prints the same errors.
//!
//!   appset-render [-root gitops/argocd] [-include-disabled=true]
//!
//! Flags, output and exit codes are the Go tool's, byte for byte.

use std::ffi::OsStr;
use std::io::{Read, Write};
use std::os::unix::ffi::{OsStrExt, OsStringExt};

pub mod gofmt;
pub mod gostr;
pub mod numbers;
pub mod parse;
mod unicode_tables;

/// The function names ArgoCD's goTemplate provides (sprig + toYaml/fromYaml/
/// lookup): parsing only needs each to resolve. Same list as main.go.
pub const SPRIG_NAMES: &str = "
abbrev abbrevboth add add1 ago all any append atoi b32dec b32enc b64dec b64enc base
bcrypt buildCustomCert camelcase cat ceil clean coalesce compact concat contains date
dateInZone dateModify decryptAES deepCopy deepEqual default derivePassword dict dig dir
div duration durationRound empty encryptAES env expandenv ext fail first float64 floor
fromJson fromYaml genCA genPrivateKey genSelfSignedCert genSignedCert get getHostByName
has hasKey hasPrefix hasSuffix htmlDate htmlDateInZone indent initial initials int int64
isAbs join js kebabcase keys kindIs kindOf last list lookup lower max maxf merge
mergeOverwrite min minf mod mul mustAppend mustCompact mustDateModify mustDeepCopy
mustFirst mustFromJson mustHas mustInitial mustLast mustMerge mustPrepend mustPush
mustRegexFind mustRest mustReverse mustSlice mustToDate mustToJson mustToPrettyJson
mustToRawJson mustUniq mustWithout nindent nospace now omit osBase osClean osDir osExt
pluck plural prepend quote randAlpha randAlphaNum randAscii randBytes randInt randNumeric
regexFind regexMatch regexQuoteMeta regexReplaceAll regexSplit repeat replace rest reverse
round semver semverCompare seq set sha1sum sha256sum sha512sum shuffle slice snakecase
sortAlpha split splitList splitn squote sub substr swapcase ternary title toDate toDecimal
toJson toPrettyJson toRawJson toString toStrings toToml toYaml trim trimAll trimPrefix
trimSuffix trunc tuple typeIs typeIsLike typeOf unixEpoch unset until untilStep upper
uuidv4 values without wrap wrapWith
";

pub fn funcs() -> parse::Funcs {
    let names: Vec<&str> = SPRIG_NAMES.split_whitespace().collect();
    parse::Funcs::new(&names)
}

/// checkSource: None when the appset would render, else the parse error.
pub fn check_source(name: &[u8], src: &[u8], funcs: &parse::Funcs) -> Option<Vec<u8>> {
    parse::check_source(name, src, funcs).err().map(|e| e.0)
}

fn contains(hay: &[u8], needle: &[u8]) -> bool {
    hay.windows(needle.len()).any(|w| w == needle)
}

/// classify: actionable guidance for a parse error.
pub fn classify(err: &[u8]) -> &'static str {
    if contains(err, b"bad character U+0060") {
        "a literal backtick closed the Go raw-string passthrough early (this is issue #414). \
         Remove the backtick from inside the {{` ... `}} block."
    } else if contains(err, b"undefined variable") {
        "a literal {{ }} is being evaluated as goTemplate. Wrap the block in a raw-string \
         passthrough ({{` ... `}}) so Prometheus/Alertmanager/Gateway templating survives (CONTRIBUTING.md:419)."
    } else if contains(err, b"not defined") {
        "unknown template function. If ArgoCD/sprig provides it, add the name to sprigNames in \
         tools/gitops/appset-render/main.go; otherwise it is a typo and would fail in the controller too."
    } else {
        "goTemplate parse failure — the ApplicationSet controller would fail to render this."
    }
}

/// Go's errno text for an io::Error from a syscall.
fn errno_text(e: &std::io::Error) -> String {
    let n = e.raw_os_error().unwrap_or(0);
    #[cfg(target_os = "macos")]
    let s = match n {
        1 => "operation not permitted",
        2 => "no such file or directory",
        5 => "input/output error",
        9 => "bad file descriptor",
        12 => "cannot allocate memory",
        13 => "permission denied",
        20 => "not a directory",
        21 => "is a directory",
        22 => "invalid argument",
        24 => "too many open files",
        62 => "too many levels of symbolic links",
        63 => "file name too long",
        _ => "",
    };
    #[cfg(not(target_os = "macos"))]
    let s = match n {
        1 => "operation not permitted",
        2 => "no such file or directory",
        5 => "input/output error",
        9 => "bad file descriptor",
        12 => "cannot allocate memory",
        13 => "permission denied",
        20 => "not a directory",
        21 => "is a directory",
        22 => "invalid argument",
        24 => "too many open files",
        36 => "file name too long",
        40 => "too many levels of symbolic links",
        _ => "",
    };
    if s.is_empty() {
        format!("errno {n}")
    } else {
        s.to_string()
    }
}

fn path_error(op: &str, path: &[u8], e: &std::io::Error) -> Vec<u8> {
    [op.as_bytes(), b" ", path, b": ", errno_text(e).as_bytes()].concat()
}

/// filepath.Clean (Unix).
pub fn clean(path: &[u8]) -> Vec<u8> {
    if path.is_empty() {
        return b".".to_vec();
    }
    let rooted = path[0] == b'/';
    let n = path.len();
    let mut out: Vec<u8> = Vec::with_capacity(n);
    let mut r = 0;
    let mut dotdot = 0;
    if rooted {
        out.push(b'/');
        r = 1;
        dotdot = 1;
    }
    while r < n {
        if path[r] == b'/' {
            r += 1;
        } else if path[r] == b'.' && (r + 1 == n || path[r + 1] == b'/') {
            r += 1;
        } else if path[r] == b'.' && path[r + 1] == b'.' && (r + 2 == n || path[r + 2] == b'/') {
            r += 2;
            if out.len() > dotdot {
                let mut w = out.len() - 1;
                while w > dotdot && out[w] != b'/' {
                    w -= 1;
                }
                out.truncate(w);
            } else if !rooted {
                if !out.is_empty() {
                    out.push(b'/');
                }
                out.extend_from_slice(b"..");
                dotdot = out.len();
            }
        } else {
            if (rooted && out.len() != 1) || (!rooted && !out.is_empty()) {
                out.push(b'/');
            }
            while r < n && path[r] != b'/' {
                out.push(path[r]);
                r += 1;
            }
        }
    }
    if out.is_empty() {
        out.push(b'.');
    }
    out
}

/// filepath.Base.
pub fn base(path: &[u8]) -> Vec<u8> {
    if path.is_empty() {
        return b".".to_vec();
    }
    let mut p = path;
    while p.len() > 1 && p.last() == Some(&b'/') {
        p = &p[..p.len() - 1];
    }
    if p == b"/" {
        return b"/".to_vec();
    }
    match p.iter().rposition(|&b| b == b'/') {
        Some(i) => p[i + 1..].to_vec(),
        None => p.to_vec(),
    }
}

fn lstat(path: &[u8]) -> Result<std::fs::Metadata, Vec<u8>> {
    std::fs::symlink_metadata(OsStr::from_bytes(path)).map_err(|e| path_error("lstat", path, &e))
}

/// readDirNames: sorted entry names, or Go's error text.
fn read_dir_names(path: &[u8]) -> Result<Vec<Vec<u8>>, Vec<u8>> {
    let rd =
        std::fs::read_dir(OsStr::from_bytes(path)).map_err(|e| path_error("open", path, &e))?;
    let mut names = Vec::new();
    for ent in rd {
        let ent = ent.map_err(|e| path_error("readdirent", path, &e))?;
        names.push(ent.file_name().into_vec());
    }
    names.sort();
    Ok(names)
}

/// filepath.Walk with main.go's walk function: the applicationset* files
/// under root, in walk order, or the first error.
fn collect(root: &[u8], include_disabled: bool) -> Result<Vec<Vec<u8>>, Vec<u8>> {
    let mut files = Vec::new();
    let visit = |p: &[u8], is_dir: bool, files: &mut Vec<Vec<u8>>| {
        if is_dir {
            return;
        }
        let b = base(p);
        if !b.starts_with(b"applicationset") {
            return;
        }
        if b.ends_with(b".disabled") && !include_disabled {
            return;
        }
        files.push(p.to_vec());
    };
    fn walk(
        path: &[u8],
        meta: &std::fs::Metadata,
        files: &mut Vec<Vec<u8>>,
        visit: &dyn Fn(&[u8], bool, &mut Vec<Vec<u8>>),
    ) -> Result<(), Vec<u8>> {
        if !meta.is_dir() {
            visit(path, false, files);
            return Ok(());
        }
        let names = read_dir_names(path)?;
        visit(path, true, files);
        for name in names {
            let mut joined = path.to_vec();
            joined.push(b'/');
            joined.extend_from_slice(&name);
            let filename = clean(&joined);
            let m = lstat(&filename)?;
            walk(&filename, &m, files, visit)?;
        }
        Ok(())
    }
    let meta = lstat(root)?;
    walk(root, &meta, &mut files, &visit)?;
    Ok(files)
}

/// os.ReadFile, with Go's error text.
fn read_file(path: &[u8]) -> Result<Vec<u8>, Vec<u8>> {
    let mut f =
        std::fs::File::open(OsStr::from_bytes(path)).map_err(|e| path_error("open", path, &e))?;
    let mut data = Vec::new();
    f.read_to_end(&mut data)
        .map_err(|e| path_error("read", path, &e))?;
    Ok(data)
}

const USAGE_DEFAULTS: &[u8] = b"  -include-disabled\n    \talso check *.disabled appsets (advisory: they do not reconcile) (default true)\n  -root string\n    \tdirectory to scan for applicationset manifests (default \"gitops/argocd\")\n";

fn usage(prog: &[u8], err: &mut dyn Write) {
    let _ = err.write_all(&[b"Usage of ", prog, b":\n", USAGE_DEFAULTS].concat());
}

/// strconv.ParseBool.
fn parse_bool(s: &[u8]) -> Option<bool> {
    match s {
        b"1" | b"t" | b"T" | b"TRUE" | b"true" | b"True" => Some(true),
        b"0" | b"f" | b"F" | b"FALSE" | b"false" | b"False" => Some(false),
        _ => None,
    }
}

pub struct Options {
    pub root: Vec<u8>,
    pub include_disabled: bool,
}

/// flag.Parse with ExitOnError: Ok(options), or Err(exit code) after
/// printing what Go's flag package prints.
pub fn parse_flags(prog: &[u8], args: &[Vec<u8>], err: &mut dyn Write) -> Result<Options, i32> {
    let mut o = Options {
        root: b"gitops/argocd".to_vec(),
        include_disabled: true,
    };
    let mut args: &[Vec<u8>] = args;
    let fail = |msg: Vec<u8>, err: &mut dyn Write| {
        let _ = err.write_all(&msg);
        let _ = err.write_all(b"\n");
        usage(prog, err);
        2
    };
    loop {
        if args.is_empty() {
            break;
        }
        let s = &args[0][..];
        if s.len() < 2 || s[0] != b'-' {
            break;
        }
        let mut num_minuses = 1;
        if s[1] == b'-' {
            num_minuses += 1;
            if s.len() == 2 {
                break; // "--" ends the flags (and is consumed; nothing reads the rest)
            }
        }
        let mut name = &s[num_minuses..];
        if name.is_empty() || name[0] == b'-' || name[0] == b'=' {
            return Err(fail([b"bad flag syntax: ", s].concat(), err));
        }
        args = &args[1..];
        let mut has_value = false;
        let mut value: &[u8] = b"";
        for i in 1..name.len() {
            if name[i] == b'=' {
                value = &name[i + 1..];
                has_value = true;
                name = &name[..i];
                break;
            }
        }
        match name {
            b"include-disabled" => {
                if has_value {
                    match parse_bool(value) {
                        Some(v) => o.include_disabled = v,
                        None => {
                            let msg = [
                                b"invalid boolean value ".as_slice(),
                                &gostr::quote(value),
                                b" for -",
                                name,
                                b": parse error",
                            ]
                            .concat();
                            return Err(fail(msg, err));
                        }
                    }
                } else {
                    o.include_disabled = true;
                }
            }
            b"root" => {
                if !has_value && !args.is_empty() {
                    has_value = true;
                    value = &args[0];
                    args = &args[1..];
                }
                if !has_value {
                    return Err(fail([b"flag needs an argument: -", name].concat(), err));
                }
                o.root = value.to_vec();
            }
            b"help" | b"h" => {
                usage(prog, err);
                return Err(0);
            }
            _ => {
                return Err(fail(
                    [b"flag provided but not defined: -", name].concat(),
                    err,
                ));
            }
        }
    }
    Ok(o)
}

/// The whole tool: argv is the full command line (argv[0] included).
pub fn run(argv: &[Vec<u8>], out: &mut dyn Write, err: &mut dyn Write) -> i32 {
    let prog: &[u8] = argv.first().map(|v| v.as_slice()).unwrap_or(b"");
    let rest = if argv.is_empty() {
        &argv[..]
    } else {
        &argv[1..]
    };
    let o = match parse_flags(prog, rest, err) {
        Ok(o) => o,
        Err(code) => return code,
    };

    if let Some(wd) = std::env::var_os("BUILD_WORKSPACE_DIRECTORY") {
        let wd = wd.into_vec();
        if !wd.is_empty() {
            if let Err(e) = std::env::set_current_dir(OsStr::from_bytes(&wd)) {
                let _ = err.write_all(
                    &[
                        b"appset-render: cannot enter workspace: ".as_slice(),
                        &path_error("chdir", &wd, &e),
                        b"\n",
                    ]
                    .concat(),
                );
                return 1;
            }
        }
    }

    let mut files = match collect(&o.root, o.include_disabled) {
        Ok(f) => f,
        Err(e) => {
            let _ = err.write_all(
                &[
                    b"appset-render: cannot scan ".as_slice(),
                    &o.root,
                    b": ",
                    &e,
                    b"\n",
                ]
                .concat(),
            );
            return 1;
        }
    };
    files.sort();

    if files.is_empty() {
        let _ = err.write_all(
            &[
                b"appset-render: found NO applicationset manifests under ".as_slice(),
                &o.root,
                " — refusing to report green.\n".as_bytes(),
            ]
            .concat(),
        );
        return 1;
    }

    let funcs = funcs();
    let mut fail = 0;
    for f in &files {
        let src = match read_file(f) {
            Ok(s) => s,
            Err(e) => {
                let _ = err.write_all(&["✗ ".as_bytes(), f, b": ", &e, b"\n"].concat());
                fail += 1;
                continue;
            }
        };
        if let Some(perr) = check_source(&base(f), &src, &funcs) {
            let disabled = f.ends_with(b".disabled");
            let (mark, tag): (&str, &str) = if disabled {
                ("!", " (disabled — advisory)")
            } else {
                ("✗", "")
            };
            let _ = err.write_all(
                &[
                    mark.as_bytes(),
                    b" ",
                    f,
                    tag.as_bytes(),
                    b"\n    ",
                    &perr,
                    "\n    → ".as_bytes(),
                    classify(&perr).as_bytes(),
                    b"\n",
                ]
                .concat(),
            );
            if !disabled {
                fail += 1;
            }
        }
    }

    if fail > 0 {
        let _ = err.write_all(
            format!(
                "\nappset-render: {fail} of {} ApplicationSet(s) would FAIL to render.\n",
                files.len()
            )
            .as_bytes(),
        );
        return 1;
    }
    let _ = out.write_all(
        format!(
            "appset-render: {} ApplicationSet(s) render-parse clean\n",
            files.len()
        )
        .as_bytes(),
    );
    let _ = out.flush();
    0
}

#[cfg(test)]
mod lib_test;
