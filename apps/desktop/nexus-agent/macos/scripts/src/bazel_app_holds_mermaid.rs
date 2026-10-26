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

use std::path::Path;
use std::process::Command;

pub fn run(args: &[String]) -> i32 {
    let rest = if args.len() > 1 { &args[1..] } else { &[] };
    if rest.is_empty() {
        eprintln!("Usage: bazel-app-holds-mermaid <app name> <path>...");
        return 2;
    }

    let app_name = &rest[0];
    let paths = &rest[1..];

    let mut archive = String::new();
    let mut script = String::new();
    let mut licence = String::new();

    for path in paths {
        if path.ends_with(".zip") {
            archive = path.clone();
        } else if path.ends_with("/mermaid.min.js") || path == "mermaid.min.js" {
            script = path.clone();
        } else if path.ends_with("/mermaid-LICENSE.txt") || path == "mermaid-LICENSE.txt" {
            licence = path.clone();
        } else {
            let zip_candidate = format!("{}.zip", path);
            if archive.is_empty() && Path::new(&zip_candidate).exists() {
                archive = zip_candidate;
            }
        }
    }

    for (needed, name) in [
        (&archive, "archive"),
        (&script, "script"),
        (&licence, "licence"),
    ] {
        if needed.is_empty() {
            eprintln!("no {} among the paths given: {}", name, paths.join(" "));
            return 2;
        }
    }

    let resources = format!("{}.app/Contents/Resources", app_name);
    let tmpdir = std::env::var("TEST_TMPDIR").unwrap_or_else(|_| "/tmp".into());
    let mut failed = 0i32;

    for source in [&script, &licence] {
        let name = Path::new(source).file_name().unwrap().to_str().unwrap();
        let inside = format!("{}/{}", resources, name);

        let want = match crate::sha256_hex_file(Path::new(source)) {
            Ok(h) => h,
            Err(e) => {
                eprintln!("FAIL: cannot read {}: {}", source, e);
                failed = 1;
                continue;
            }
        };

        let tmp_out = format!("{}/{}", tmpdir, name);
        let output = Command::new("unzip")
            .args(["-p", &archive, &inside])
            .output();

        match output {
            Ok(o) if o.status.success() => {
                if let Err(e) = std::fs::write(&tmp_out, &o.stdout) {
                    eprintln!("FAIL: cannot write {}: {}", tmp_out, e);
                    failed = 1;
                    continue;
                }
            }
            _ => {
                eprintln!(
                    "FAIL: {} is not in {}",
                    inside,
                    Path::new(&archive).file_name().unwrap().to_str().unwrap()
                );
                failed = 1;
                continue;
            }
        }

        let got = match crate::sha256_hex_file(Path::new(&tmp_out)) {
            Ok(h) => h,
            Err(e) => {
                eprintln!("FAIL: cannot hash {}: {}", tmp_out, e);
                failed = 1;
                continue;
            }
        };

        if got != want {
            eprintln!(
                "FAIL: {} is not the file in the source tree: SHA-256 {}, expected {}",
                inside, got, want
            );
            failed = 1;
            continue;
        }

        println!("ok: {} (SHA-256 {})", inside, got);
    }

    if failed != 0 {
        let archive_basename = Path::new(&archive).file_name().unwrap().to_str().unwrap();
        eprintln!("{} holds, under Contents/Resources:", archive_basename);
        let _ = Command::new("unzip")
            .args(["-Z1", &archive, &format!("{}/*", resources)])
            .status();
        return 1;
    }

    0
}
