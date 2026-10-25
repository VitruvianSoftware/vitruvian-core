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

//! sync_downloads.py in Rust, standard library only. Same command line,
//! same output, same edits to the catalog; the parity test
//! (sync_downloads_rs_parity_test.py) holds the two together.

pub mod argparse;
pub mod difflib;
pub mod fetch;
pub mod json;
pub mod pyerr;
pub mod pyre;
pub mod pystr;
pub mod sync;

use std::process::Command;

use argparse::{Kind, Opt, Parser};
use pyerr::Crash;

fn parser(prog: String) -> Parser {
    Parser {
        prog,
        description: Some(
            "Synchronize vitruviansoftware.dev downloads catalog with latest releases".into(),
        ),
        opts: vec![
            Opt::help(),
            Opt {
                strings: vec!["--file"],
                dest: "file",
                kind: Kind::Value,
                help: Some(format!(
                    "Path to downloads.yml (default: {})",
                    sync::DEFAULT_CATALOG
                )),
                required: false,
            },
            Opt {
                strings: vec!["--dry-run"],
                dest: "dry_run",
                kind: Kind::Flag,
                help: Some("Print diff without modifying file".into()),
                required: false,
            },
            Opt {
                strings: vec!["--check"],
                dest: "check",
                kind: Kind::Flag,
                help: Some("Exit 1 if catalog is out of date".into()),
                required: false,
            },
            Opt {
                strings: vec!["--token"],
                dest: "token",
                kind: Kind::Value,
                help: Some("GitHub token for API queries (or uses ambient gh / GH_TOKEN)".into()),
                required: false,
            },
        ],
    }
}

/// `os.path.basename(sys.argv[0])`, argparse's prog.
pub fn prog_name(argv0: &str) -> String {
    match argv0.rfind('/') {
        Some(i) => argv0[i + 1..].to_string(),
        None => argv0.to_string(),
    }
}

fn resolve(path: &str) -> Result<String, Crash> {
    if path.starts_with('/') {
        return Ok(path.to_string());
    }
    let mut root = std::env::var("BUILD_WORKSPACE_DIRECTORY").unwrap_or_default();
    if root.is_empty() {
        let out = Command::new("git")
            .args(["rev-parse", "--show-toplevel"])
            .output()
            .map_err(|e| Crash::os(&e, Some("git")))?;
        let text = String::from_utf8(out.stdout).map_err(|_| {
            Crash::new(
                "UnicodeDecodeError",
                "'utf-8' codec can't decode git output",
            )
        })?;
        root = pystr::strip(&text).to_string();
    }
    if root.is_empty() {
        return Ok(path.to_string());
    }
    // os.path.join
    Ok(if root.ends_with('/') {
        format!("{}{}", root, path)
    } else {
        format!("{}/{}", root, path)
    })
}

/// `main()`: what to print and the exit code. argv[0] included.
pub fn run(argv: &[String]) -> i32 {
    let prog = prog_name(
        argv.first()
            .map(String::as_str)
            .unwrap_or("sync_downloads.py"),
    );
    let p = parser(prog);
    let values = match p.parse(&argv[1.min(argv.len())..], &|_, _| Ok(())) {
        Ok(v) => v,
        Err(exit) => {
            print!("{}", exit.stdout);
            eprint!("{}", exit.stderr);
            return exit.code;
        }
    };
    let file = values
        .value("file")
        .unwrap_or(sync::DEFAULT_CATALOG)
        .to_string();
    let token = values.value("token").map(String::from);
    let result = resolve(&file).and_then(|path| {
        sync::sync_catalog(
            &path,
            values.flag("dry_run"),
            values.flag("check"),
            token.as_deref(),
        )
    });
    match result {
        Ok(code) => code,
        Err(crash) => {
            use std::io::Write;
            let _ = std::io::stdout().flush();
            eprint!("{}", crash.traceback());
            1
        }
    }
}
