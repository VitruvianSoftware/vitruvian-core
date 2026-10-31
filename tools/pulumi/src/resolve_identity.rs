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

use std::io::Write;

/// Resolve GCP identity from the map file for the given project directory.
/// Returns `(account, gcp_project)` when the directory is listed and is not a
/// reference placeholder; `None` otherwise.
pub fn resolve(map_path: &str, dir: &str) -> Option<(String, String)> {
    let content = std::fs::read_to_string(map_path).ok()?;
    for line in content.lines() {
        let fields: Vec<&str> = line.split_whitespace().collect();
        if fields.is_empty() {
            continue;
        }
        if fields[0].starts_with('#') {
            continue;
        }
        if fields[0] == "-" {
            continue;
        }
        if fields[0] == dir {
            let account = fields.get(1).copied().unwrap_or("");
            let project = fields.get(2).copied().unwrap_or("");
            return Some((account.to_string(), project.to_string()));
        }
    }
    None
}

/// Entry point (`resolve-identity <map> <infra-dir>`): exit 0 on all normal paths;
/// non-zero only for missing/empty arguments.
pub fn run(args: &[String]) -> i32 {
    let map = match args.first().filter(|s| !s.is_empty()) {
        Some(s) => s.as_str(),
        None => {
            eprintln!("usage: resolve-identity <map_file> <infra_dir>");
            return 1;
        }
    };
    let dir = match args.get(1).filter(|s| !s.is_empty()) {
        Some(s) => s.as_str(),
        None => {
            eprintln!("usage: resolve-identity <map_file> <infra_dir>");
            return 1;
        }
    };

    if !std::path::Path::new(map).is_file() {
        return 0;
    }

    if let Some((account, project)) = resolve(map, dir) {
        print!("{}\t{}\n", account, project);
        let _ = std::io::stdout().flush();
    }
    0
}
