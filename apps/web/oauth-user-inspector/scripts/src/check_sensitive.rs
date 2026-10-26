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

use std::process::Command;

pub fn is_sensitive(path: &str) -> bool {
    let parts: Vec<&str> = path.split('/').collect();
    for part in &parts {
        if *part == ".env" || part.starts_with(".env.") {
            return true;
        }
        if *part == "dist" || *part == "dist-server" {
            return true;
        }
    }
    false
}

pub fn run(_args: &[String]) -> i32 {
    let output = match Command::new("git")
        .args(["diff", "--cached", "--name-only"])
        .output()
    {
        Ok(o) => o,
        Err(_) => return 0,
    };

    let stdout = String::from_utf8_lossy(&output.stdout);
    for line in stdout.lines() {
        let trimmed = line.trim();
        if !trimmed.is_empty() && is_sensitive(trimmed) {
            println!("\\nERROR: You're trying to commit a sensitive or build file (env or dist).");
            println!("Please remove it from staging: git reset HEAD <file>");
            println!("If you really intend to add a built artifact, add an exception to .gitignore or contact the repo maintainers.\\n");
            return 1;
        }
    }

    0
}
