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

//! `bazel run //tools/pipeline/replay -- --map <map.json> [--commits N]`

use std::process::Command;

fn git(root: &str, args: &[&str]) -> Result<String, String> {
    let o = Command::new("git")
        .arg("-C")
        .arg(root)
        .args(args)
        .output()
        .map_err(|e| e.to_string())?;
    if !o.status.success() {
        return Err(String::from_utf8_lossy(&o.stderr).to_string());
    }
    Ok(String::from_utf8_lossy(&o.stdout).to_string())
}

fn main() {
    let mut map_path = String::new();
    let mut commits = 200usize;
    let mut root = std::env::var("BUILD_WORKSPACE_DIRECTORY").unwrap_or_else(|_| ".".into());
    let mut tip = "origin/main".to_string();
    let a: Vec<String> = std::env::args().skip(1).collect();
    let mut i = 0;
    while i < a.len() {
        let v = a.get(i + 1).cloned().unwrap_or_default();
        match a[i].as_str() {
            "--map" => map_path = v,
            "--commits" => commits = v.parse().unwrap_or(200),
            "--repo-root" => root = v,
            "--tip" => tip = v,
            "-h" | "--help" => {
                println!("usage: replay --map <map.json> [--commits N] [--tip REF] [--repo-root DIR]\nSee tools/pipeline/replay/README.md");
                return;
            }
            x => {
                eprintln!("unknown flag {x}");
                std::process::exit(2);
            }
        }
        i += 2;
    }
    if map_path.is_empty() {
        eprintln!("--map is required (fetch one: see README.md)");
        std::process::exit(2);
    }
    let want = match plan::peek_rdeps_map_commit(&map_path) {
        c if c.is_empty() => {
            eprintln!("cannot read a commit from {map_path}");
            std::process::exit(1);
        }
        c => c,
    };
    let map = match plan::load_rdeps_map(&map_path, &want) {
        Ok(Some(m)) => m,
        Ok(None) => {
            eprintln!("{map_path} does not exist");
            std::process::exit(1);
        }
        Err(e) => {
            eprintln!("cannot use {map_path}: {e}");
            std::process::exit(1);
        }
    };
    if map.unit_packages.is_none() {
        eprintln!("this map has no unit_packages, so old and new would be identical");
        std::process::exit(1);
    }
    let log = git(
        &root,
        &[
            "log",
            "--first-parent",
            "-n",
            &commits.to_string(),
            "--format=%H",
            &tip,
        ],
    )
    .unwrap_or_else(|e| {
        eprintln!("git log: {e}");
        std::process::exit(1)
    });
    let mut results = Vec::new();
    for c in log.lines() {
        let files = match git(&root, &["diff", "--name-only", &format!("{c}^"), c]) {
            Ok(o) => replay::parse_files(&o),
            Err(_) => continue,
        };
        results.push((
            c[..10.min(c.len())].to_string(),
            replay::replay_one(&root, &map, files),
        ));
    }
    print!("{}", replay::render(&replay::tally(&results)));
    println!("\nPlanned against the checkout at {root} and the map for {}; package ownership of files added or moved since then is approximated.", &want[..10.min(want.len())]);
}
