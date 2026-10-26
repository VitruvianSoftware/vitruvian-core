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

use std::os::unix::fs::PermissionsExt;
use std::process::Command;

fn is_executable(path: &str) -> bool {
    std::fs::metadata(path)
        .map(|m| m.permissions().mode() & 0o111 != 0)
        .unwrap_or(false)
}

fn find_in_path(name: &str) -> Option<String> {
    let path_var = std::env::var("PATH").unwrap_or_default();
    for dir in path_var.split(':') {
        if dir.is_empty() {
            continue;
        }
        let candidate = format!("{dir}/{name}");
        if is_executable(&candidate) {
            return Some(candidate);
        }
    }
    None
}

pub fn run(args: &[String]) -> i32 {
    let home = std::env::var("HOME").unwrap_or_default();

    let candidates: Vec<String> = vec![
        std::env::var("AGY_BIN").unwrap_or_default(),
        format!("{home}/.local/bin/agy"),
        "/opt/homebrew/bin/agy".to_string(),
        "/usr/local/bin/agy".to_string(),
        find_in_path("agy").unwrap_or_default(),
    ];

    let forward_args: Vec<&str> = args.iter().skip(1).map(|s| s.as_str()).collect();

    for candidate in &candidates {
        if !candidate.is_empty() && is_executable(candidate) {
            use std::os::unix::process::CommandExt;
            let err = Command::new(candidate).args(&forward_args).exec();
            eprintln!("exec failed: {err}");
            return 1;
        }
    }

    eprintln!("agy (Antigravity CLI) is not installed.");
    eprintln!("Install it from https://antigravity.google, then run: agy install");
    127
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_is_executable_nonexistent() {
        assert!(!is_executable("/nonexistent/path/to/agy"));
    }

    #[test]
    fn test_find_in_path_nonexistent() {
        assert!(find_in_path("__nonexistent_tool_xyz__").is_none());
    }

    #[test]
    fn test_not_installed_returns_127() {
        std::env::remove_var("AGY_BIN");
        let old_home = std::env::var("HOME").ok();
        let old_path = std::env::var("PATH").ok();
        let tmp = std::env::temp_dir().join("agy_test_empty");
        let _ = std::fs::create_dir_all(&tmp);
        std::env::set_var("HOME", tmp.to_str().unwrap());
        std::env::set_var("PATH", tmp.to_str().unwrap());

        let rc = run(&["agy".to_string()]);
        assert_eq!(rc, 127);

        if let Some(h) = old_home {
            std::env::set_var("HOME", h);
        }
        if let Some(p) = old_path {
            std::env::set_var("PATH", p);
        }
        let _ = std::fs::remove_dir_all(&tmp);
    }
}
