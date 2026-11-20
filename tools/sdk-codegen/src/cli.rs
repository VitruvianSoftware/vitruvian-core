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

//! sdk_codegen.py itself: write the kits' generated files, or `--check` the
//! committed ones, with its output and exit status.
//!
//!     sdk-codegen                 writes the files into packages/vitruvian-sdk
//!     sdk-codegen --check         fails when a committed file is not what
//!                                 would be written, or is one no emitter writes
//!     sdk-codegen --out FOLDER    writes them under FOLDER instead
//!
//! Where Python would stop with an exception nothing catches, this prints
//! the traceback's last line, which names the exception, under a header
//! that says Python's stack frames are not reproduced, and exits 1.

use crate::argparse::{Kind, Opt, Parser};
use crate::difflib;
use crate::emitters;
use crate::fsio;
use crate::model;
use crate::pyerr::{PyErr, PyResult};
use crate::pystr;
use std::collections::{BTreeMap, BTreeSet};
use std::io::Write;

const PACKAGE: &str = "packages/vitruvian-sdk";
const DESCRIPTION: &str = "Writes each kit's generated types from the protocol's schemas.";
const PACKAGE_HELP: &str = "the SDK's folder; found from the repository when left out";

pub fn parser(prog: String) -> Parser {
    Parser {
        prog,
        description: Some(DESCRIPTION.into()),
        opts: vec![
            Opt::help(),
            Opt {
                strings: vec!["--check"],
                dest: "check",
                kind: Kind::Flag,
                help: None,
                required: false,
            },
            Opt {
                strings: vec!["--out"],
                dest: "out",
                kind: Kind::Value,
                help: None,
                required: false,
            },
            Opt {
                strings: vec!["--package"],
                dest: "package",
                kind: Kind::Value,
                help: Some(PACKAGE_HELP.into()),
                required: false,
            },
        ],
    }
}

/// Whether an emitter may write `path`: inside a folder named `generated`,
/// or a Go file named `*_gen.go`.
pub fn is_generated(path: &str) -> bool {
    let parts: Vec<&str> = path.split('/').collect();
    let (last, folders) = parts.split_last().unwrap();
    folders.contains(&"generated") || last.ends_with("_gen.go")
}

/// Every generated file, by its path under `package`, and its text.
pub fn generate(package: &str) -> PyResult<BTreeMap<String, String>> {
    let built = model::load(&fsio::join(package, "protocol"))?;
    let mut files = BTreeMap::new();
    for emitter in emitters::all() {
        for (path, text) in (emitter.emit)(&built)? {
            if !is_generated(&path) {
                return Err(PyErr::exit(format!(
                    "{} writes {}, which is not inside a folder named generated",
                    emitter.name, path
                )));
            }
            if files.contains_key(&path) {
                return Err(PyErr::exit(format!("{} is written by two emitters", path)));
            }
            files.insert(path, text);
        }
    }
    Ok(files)
}

/// Every generated file in the package's kits and its Go module.
pub fn committed(package: &str) -> PyResult<BTreeMap<String, String>> {
    let mut found = BTreeMap::new();
    for folder in ["kits", "go"] {
        let top = fsio::join(package, folder);
        for rel in fsio::walk(&top, &["node_modules", "__pycache__", "dist"]) {
            let relative = format!("{}/{}", folder, rel);
            if !is_generated(&relative) {
                continue;
            }
            found.insert(relative, fsio::read_text(&fsio::join(&top, &rel))?);
        }
    }
    Ok(found)
}

/// `check(package)`: its exit status, with what it printed.
pub fn check(package: &str, out: &mut dyn Write, err: &mut dyn Write) -> PyResult<i32> {
    let wanted = generate(package)?;
    let have = committed(package)?;
    let paths: BTreeSet<&String> = wanted.keys().chain(have.keys()).collect();
    let mut problems = Vec::new();
    for path in paths {
        match (have.get(path), wanted.get(path)) {
            (None, _) => problems.push(format!("{}: missing", path)),
            (_, None) => problems.push(format!("{}: no emitter writes it", path)),
            (Some(h), Some(w)) if h != w => {
                let diff = difflib::unified_diff(
                    &pystr::splitlines(h, false),
                    &pystr::splitlines(w, false),
                    &format!("committed/{}", path),
                    &format!("generated/{}", path),
                    1,
                );
                let shown: Vec<String> = diff.into_iter().take(40).collect();
                problems.push(format!("{}: out of date\n{}", path, shown.join("\n")));
            }
            _ => {}
        }
    }
    for problem in &problems {
        let _ = writeln!(err, "{}", problem);
    }
    let verdict = if problems.is_empty() {
        "in sync"
    } else {
        "OUT OF SYNC, run: bazel run //tools/sdk-codegen"
    };
    let _ = writeln!(out, "sdk-codegen: {} files, {}", wanted.len(), verdict);
    Ok(if problems.is_empty() { 0 } else { 1 })
}

/// `write(package, out)`.
pub fn write(package: &str, folder: &str, out: &mut dyn Write) -> PyResult<i32> {
    let files = generate(package)?;
    for (path, text) in &files {
        let target = fsio::join(folder, path);
        fsio::makedirs(&fsio::dirname(&target))?;
        fsio::write_text(&target, text)?;
        let _ = writeln!(out, "wrote {}", target);
    }
    Ok(0)
}

/// `os.path.normpath` on POSIX.
pub fn normpath(path: &str) -> String {
    if path.is_empty() {
        return ".".into();
    }
    let initial = if path.starts_with("//") && !path.starts_with("///") {
        2
    } else if path.starts_with('/') {
        1
    } else {
        0
    };
    let mut parts: Vec<&str> = Vec::new();
    for comp in path.split('/') {
        if comp.is_empty() || comp == "." {
            continue;
        }
        if comp != ".." || (initial == 0 && parts.is_empty()) || parts.last() == Some(&"..") {
            parts.push(comp);
        } else if !parts.is_empty() {
            parts.pop();
        }
    }
    let joined = format!("{}{}", "/".repeat(initial), parts.join("/"));
    if joined.is_empty() {
        ".".into()
    } else {
        joined
    }
}

fn abspath(path: &str) -> String {
    if path.starts_with('/') {
        normpath(path)
    } else {
        let cwd = std::env::current_dir()
            .map(|p| p.to_string_lossy().to_string())
            .unwrap_or_default();
        normpath(&fsio::join(&cwd, path))
    }
}

/// The folder this program is in, as sdk_codegen.py's HERE is its own:
/// the runfiles' copy of tools/sdk-codegen when Bazel built one beside it.
fn here(argv0: &str) -> String {
    let exe = if argv0.contains('/') {
        Some(abspath(argv0))
    } else {
        std::env::var("PATH").ok().and_then(|path| {
            path.split(':')
                .map(|dir| fsio::join(if dir.is_empty() { "." } else { dir }, argv0))
                .find(|p| std::path::Path::new(p).is_file())
                .map(|p| abspath(&p))
        })
    };
    let exe = exe.unwrap_or_else(|| {
        std::env::current_exe()
            .map(|p| p.to_string_lossy().to_string())
            .unwrap_or_default()
    });
    let runfiles = format!("{}.runfiles/_main/tools/sdk-codegen", exe);
    if std::path::Path::new(&runfiles).is_dir() {
        return runfiles;
    }
    fsio::dirname(&exe)
}

/// How an exception nothing caught is printed.
pub fn traceback(e: &PyErr) -> String {
    let own = format!(
        "Traceback (most recent call last):\n  (sdk-codegen-rs: Python's stack frames are not reproduced)\n{}\n",
        e.render()
    );
    match &e.cause {
        None => own,
        Some(cause) => format!(
            "{}\nThe above exception was the direct cause of the following exception:\n\n{}",
            traceback(cause),
            own
        ),
    }
}

/// The whole program: `main(arguments)` and how Python exits from it.
pub fn run(argv: &[String], out: &mut dyn Write, err: &mut dyn Write) -> i32 {
    let argv0 = argv.first().cloned().unwrap_or_default();
    let prog = argv0.rsplit('/').next().unwrap_or("").to_string();
    let p = parser(prog);
    let values = match p.parse(&argv[argv.len().min(1)..], &|_, _| Ok(())) {
        Ok(v) => v,
        Err(exit) => {
            if !exit.stdout.is_empty() {
                let _ = out.write_all(exit.stdout.as_bytes());
            }
            if !exit.stderr.is_empty() {
                let _ = err.write_all(exit.stderr.as_bytes());
            }
            return exit.code;
        }
    };
    let root = std::env::var("BUILD_WORKSPACE_DIRECTORY")
        .ok()
        .filter(|r| !r.is_empty());
    let package = match values.value("package").filter(|p| !p.is_empty()) {
        Some(p) => p.to_string(),
        None => {
            let base = root.unwrap_or_else(|| fsio::dirname(&fsio::dirname(&here(&argv0))));
            fsio::join(&base, PACKAGE)
        }
    };
    let result = if values.flag("check") {
        check(&package, out, err)
    } else {
        let folder = values
            .value("out")
            .filter(|o| !o.is_empty())
            .map(str::to_string)
            .unwrap_or_else(|| package.clone());
        write(&package, &folder, out)
    };
    match result {
        Ok(code) => code,
        Err(e) if e.exit => {
            let _ = writeln!(err, "{}", e.message);
            1
        }
        Err(e) => {
            let _ = out.flush();
            let _ = err.write_all(traceback(&e).as_bytes());
            1
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn generated_paths() {
        assert!(is_generated("kits/python/x/generated/messages.py"));
        assert!(is_generated("go/toolkit/protocol_gen.go"));
        assert!(!is_generated("kits/generated"));
        assert!(!is_generated("go/toolkit/protocol.go"));
    }

    #[test]
    fn normpaths() {
        assert_eq!(normpath("a/./b/../c"), "a/c");
        assert_eq!(normpath("/a/../../b"), "/b");
        assert_eq!(normpath("../a"), "../a");
        assert_eq!(normpath(""), ".");
        assert_eq!(normpath("//a"), "//a");
    }

    #[test]
    fn committed_kit_files_are_in_sync() {
        if !std::path::Path::new("packages/vitruvian-sdk/protocol").exists() {
            return;
        }
        let mut out = Vec::new();
        let mut err = Vec::new();
        let status = check("packages/vitruvian-sdk", &mut out, &mut err).unwrap();
        assert_eq!(
            status,
            0,
            "sdk-codegen --check failed:\n{}",
            String::from_utf8_lossy(&err)
        );
        let names: Vec<&str> = emitters::all().iter().map(|e| e.name).collect();
        assert_eq!(names, ["go", "python", "rust", "typescript"]);
    }

    #[test]
    fn a_crash_prints_the_traceback_line() {
        let e = PyErr::new("KeyError", "'$defs'");
        assert!(traceback(&e).ends_with("\nKeyError: '$defs'\n"));
    }

    fn parse_cli(args: &[&str]) -> Result<crate::argparse::Values, crate::argparse::Exit> {
        let args: Vec<String> = args.iter().map(|s| s.to_string()).collect();
        parser("sdk_codegen.py".into()).parse_with_width(&args, 78, &|_, _| Ok(()))
    }

    fn parse_err(args: &[&str]) -> String {
        match parse_cli(args) {
            Err(e) if e.code == 2 => e.stderr.lines().nth(1).unwrap().to_string(),
            other => panic!("{other:?}"),
        }
    }

    #[test]
    fn reads_options() {
        let v = parse_cli(&[]).unwrap();
        assert!(!v.flag("check"));
        assert_eq!(v.value("out"), None);
        assert_eq!(v.value("package"), None);

        let v = parse_cli(&["--ch", "--out=x", "--p", "y", "--out", "-1"]).unwrap();
        assert!(v.flag("check"));
        assert_eq!(v.value("out"), Some("-1"));
        assert_eq!(v.value("package"), Some("y"));

        assert_eq!(parse_cli(&["-hx"]).unwrap_err().code, 0);
        assert_eq!(parse_cli(&["--he"]).unwrap_err().code, 0);
    }

    #[test]
    fn errors_are_pythons() {
        assert_eq!(
            parse_err(&["--out"]),
            "sdk_codegen.py: error: argument --out: expected one argument"
        );
        assert_eq!(
            parse_err(&["--", "x", "y"]),
            "sdk_codegen.py: error: unrecognized arguments: -- x y"
        );
        assert_eq!(
            parse_err(&["--=x"]),
            "sdk_codegen.py: error: ambiguous option: --=x could match --help, --check, --out, --package"
        );
        assert_eq!(
            parse_err(&["--check=1", "a", "-x"]),
            "sdk_codegen.py: error: argument --check: ignored explicit argument '1'"
        );
        assert_eq!(
            parse_err(&["a", "-x"]),
            "sdk_codegen.py: error: unrecognized arguments: a -x"
        );
        assert_eq!(
            parse_err(&["--out", "--check"]),
            "sdk_codegen.py: error: argument --out: expected one argument"
        );
        assert_eq!(
            parse_err(&["-h-x"]),
            "sdk_codegen.py: error: argument -h/--help: ignored explicit argument '-x'"
        );
    }

    #[test]
    fn help_wraps_as_python_does() {
        let help = |w: i64| parser("sdk_codegen.py".into()).format_help_with_width(w);
        assert_eq!(
            help(78),
            "usage: sdk_codegen.py [-h] [--check] [--out OUT] [--package PACKAGE]\n\nWrites each kit's generated types from the protocol's schemas.\n\noptions:\n  -h, --help         show this help message and exit\n  --check\n  --out OUT\n  --package PACKAGE  the SDK's folder; found from the repository when left out\n"
        );
        assert_eq!(
            help(38),
            "usage: sdk_codegen.py [-h] [--check]\n                      [--out OUT]\n                      [--package PACKAGE]\n\nWrites each kit's generated types from\nthe protocol's schemas.\n\noptions:\n  -h, --help      show this help\n                  message and exit\n  --check\n  --out OUT\n  --package PACKAGE\n                  the SDK's folder;\n                  found from the\n                  repository when left\n                  out\n"
        );
        assert!(help(18).starts_with(
            "usage: sdk_codegen.py\n       [-h]\n       [--check]\n       [--out OUT]\n       [--package PACKAGE]\n\nWrites each kit's\ngenerated types\n"
        ));
    }
}
