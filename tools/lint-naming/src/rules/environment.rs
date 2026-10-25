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

//! rules/environment.py: environment variable and CLI flag naming rules.

use crate::pystr::{dollar, is_digit, is_lower_alnum, is_upper_alnum, py_len, separated, upper};
use crate::violation::{Severity, Violation};

/// Bazel's own snake_case flags, which are allowed (BAZEL_FLAG_EXCEPTIONS).
pub const BAZEL_FLAG_EXCEPTIONS: &[&str] = &[
    "--remote_cache",
    "--disk_cache",
    "--config",
    "--platforms",
    "--experimental_remote_downloader",
    "--action_env",
];

/// `^[A-Z0-9]+(_[A-Z0-9]+)*$`
pub fn is_env_var(s: &str) -> bool {
    dollar(s, |t| separated(t, '_', is_upper_alnum))
}

/// `^--[a-z0-9]+(-[a-z0-9]+)*$`
pub fn is_cli_flag(s: &str) -> bool {
    dollar(s, |t| {
        t.strip_prefix("--")
            .map_or(false, |rest| separated(rest, '-', is_lower_alnum))
    })
}

/// validate_env_var_name.
pub fn validate_env_var_name(
    file_path: &str,
    var_name: &str,
    line_number: Option<i64>,
) -> Vec<Violation> {
    let mut violations = Vec::new();
    // Shell internals such as $? $0 $1 are not checked.
    if var_name.is_empty() || py_len(var_name) <= 1 || var_name.chars().all(is_digit) {
        return violations;
    }
    if !is_env_var(var_name) {
        violations.push(Violation::new(
            "ENV001",
            file_path,
            line_number,
            format!(
                "Environment variable '{}' must use SCREAMING_SNAKE_CASE. Hyphens or lowercase are forbidden.",
                var_name
            ),
            Severity::Error,
            Some(upper(var_name).replace('-', "_")),
        ));
    }
    violations
}

/// validate_cli_flag_name.
pub fn validate_cli_flag_name(
    file_path: &str,
    flag_name: &str,
    line_number: Option<i64>,
) -> Vec<Violation> {
    let mut violations = Vec::new();
    if flag_name.starts_with("--")
        && !BAZEL_FLAG_EXCEPTIONS.contains(&flag_name)
        && !is_cli_flag(flag_name)
    {
        violations.push(Violation::new(
            "CLI001",
            file_path,
            line_number,
            format!(
                "Internal CLI flag '{}' must use kebab-case (e.g. '--dry-run').",
                flag_name
            ),
            Severity::Error,
            Some(flag_name.replace('_', "-")),
        ));
    }
    violations
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn env_vars() {
        assert!(validate_env_var_name("x.sh", "GH_TOKEN", None).is_empty());
        assert!(validate_env_var_name("x.sh", "?", None).is_empty());
        assert!(validate_env_var_name("x.sh", "12", None).is_empty());
        assert!(validate_env_var_name("x.sh", "²³", None).is_empty());
        let v = validate_env_var_name("x.sh", "gh-token", Some(3));
        assert_eq!(v[0].suggested_fix.as_deref(), Some("GH_TOKEN"));
        assert_eq!(
            validate_env_var_name("x.sh", "_TOKEN", None)[0].rule_id,
            "ENV001"
        );
        assert_eq!(
            validate_env_var_name("x.sh", "AUTH__TOKEN", None)[0].rule_id,
            "ENV001"
        );
    }

    #[test]
    fn cli_flags() {
        assert!(validate_cli_flag_name("x.sh", "--dry-run", None).is_empty());
        assert!(validate_cli_flag_name("x.sh", "--disk_cache", None).is_empty());
        assert!(validate_cli_flag_name("x.sh", "-x", None).is_empty());
        let v = validate_cli_flag_name("x.sh", "--output_format", None);
        assert_eq!(v[0].suggested_fix.as_deref(), Some("--output-format"));
    }
}
