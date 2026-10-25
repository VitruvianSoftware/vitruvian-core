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

//! //tools/owners in Rust: compiles per-directory OWNERS files into
//! .github/CODEOWNERS, checks the committed file against them, and audits
//! that every required subtree declares owners. Output, messages and exit
//! codes match the Go tool (`:owners-go`) byte for byte; the parity test
//! holds it to that.

pub mod engine;
pub mod flags;
pub mod gostr;
pub mod schema;
pub mod validate;
pub mod yaml;

use std::io::Write;

fn out(s: &str) {
    let _ = std::io::stdout().write_all(s.as_bytes());
}

fn err(s: &str) {
    let _ = std::io::stderr().write_all(s.as_bytes());
}

/// Runs the tool; returns the exit code.
pub fn run(argv0: &str, args: &[String]) -> i32 {
    let f = match flags::parse(args) {
        Ok(f) => f,
        Err(flags::FlagError::Help) => {
            err(&flags::usage(argv0));
            return 0;
        }
        Err(flags::FlagError::Bad(msg)) => {
            err(&format!("{msg}\n{}", flags::usage(argv0)));
            return 2;
        }
    };

    let root_dir = if !f.root.is_empty() {
        f.root.clone()
    } else {
        match std::env::var("BUILD_WORKSPACE_DIRECTORY") {
            Ok(ws) if !ws.is_empty() => ws,
            _ => ".".to_string(),
        }
    };
    let abs_root = match gostr::abs(&root_dir) {
        Ok(a) => a,
        Err(e) => {
            err(&format!(
                "Error resolving root directory: {}\n",
                gostr::errno_text(&e)
            ));
            return 1;
        }
    };

    let mut engine = engine::Engine::new(&abs_root);
    if let Err(e) = engine.discover() {
        err(&format!("Discovery error: {e}\n"));
        return 1;
    }

    if f.validate_only {
        out(&format!(
            "All {} OWNERS files validated successfully.\n",
            engine.nodes.len()
        ));
        return 0;
    }

    if f.coverage_check {
        let missing = engine.check_coverage();
        if !missing.is_empty() {
            let mut s = "Coverage audit FAILED:\n".to_string();
            for m in &missing {
                s.push_str(&format!("  - Missing OWNERS in {m}\n"));
            }
            err(&s);
            return 1;
        }
        out("Coverage audit PASSED: all required subtrees have declared OWNERS.\n");
    }

    let compiled = engine.compile();

    if f.check {
        let path = gostr::join(&abs_root, ".github/CODEOWNERS");
        let current = match gostr::read_file(&path) {
            Ok(c) => c,
            Err(e) => {
                err(&format!("Error reading {path}: {e}\n"));
                return 1;
            }
        };
        if current != compiled.as_bytes() {
            err("CODEOWNERS drift detected! Run `bazel run //tools/owners -- --out .github/CODEOWNERS` to regenerate.\n");
            return 1;
        }
        out(".github/CODEOWNERS is up to date.\n");
        return 0;
    }

    if !f.out.is_empty() {
        let out_path = if f.out.starts_with('/') {
            f.out.clone()
        } else {
            gostr::join(&abs_root, &f.out)
        };
        let parent = gostr::dir(&out_path);
        if let Err(e) = gostr::mkdir_all(&parent) {
            err(&format!("Error creating parent dirs for {out_path}: {e}\n"));
            return 1;
        }
        if let Err(e) = gostr::write_file(&out_path, compiled.as_bytes()) {
            err(&format!("Error writing to {out_path}: {e}\n"));
            return 1;
        }
        out(&format!("Wrote compiled CODEOWNERS to {out_path}\n"));
    } else if !f.coverage_check {
        out(&compiled);
    }
    0
}
