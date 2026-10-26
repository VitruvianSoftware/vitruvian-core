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

use crate::commands::config::format_ascii_table;

pub const PACKAGE_VERSION: &str = "0.1.24";
pub const CLI_REPORTED_VERSION: &str = "0.1.0";

pub fn format_version_table() -> String {
    let rows = vec![
        vec!["Component".to_string(), "Version".to_string()],
        vec!["TabCLI".to_string(), CLI_REPORTED_VERSION.to_string()],
        vec!["Package".to_string(), PACKAGE_VERSION.to_string()],
        vec!["Platform".to_string(), std::env::consts::OS.to_string()],
        vec!["Arch".to_string(), std::env::consts::ARCH.to_string()],
    ];
    format!("\n{}", format_ascii_table(&rows))
}

pub fn run_version_command() -> Result<String, String> {
    Ok(format_version_table())
}
