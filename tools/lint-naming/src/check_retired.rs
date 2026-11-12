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

//! Standalone entrypoint that checks the workspace for retired product names
//! (`RET001`) and exits non-zero if any un-allowlisted mention exists.

use lint_naming::rules::retired_names::RULE_ID;
use lint_naming::scanner::{exe_dir, format_report, LineCache, Scanner};
use lint_naming::textio::os_to_str;

fn main() {
    let code = lint_naming::with_big_stack(|| {
        let root = std::env::args_os()
            .nth(1)
            .or_else(|| std::env::var_os("BUILD_WORKSPACE_DIRECTORY"))
            .map(|v| os_to_str(&v))
            .unwrap_or_else(|| ".".into());
        let scanner = Scanner::new(&root, None, true);
        let mut cache = LineCache::new(exe_dir());
        let retired: Vec<_> = scanner
            .scan(&mut cache, &mut |_| {})
            .into_iter()
            .filter(|v| v.rule_id == RULE_ID)
            .collect();
        println!("{}", format_report(&retired, "text"));
        if retired.is_empty() {
            0
        } else {
            1
        }
    });
    std::process::exit(code);
}
