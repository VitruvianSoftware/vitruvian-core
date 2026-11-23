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

//! jq 1.8 error message formatters.

use crate::format::dump_trunc;
use crate::value::{Number, Value};

/// Formats `Cannot index <kind> with string (<truncated quoted key>)` (jq 1.8).
pub fn cannot_index_string(kind: &str, key: &str) -> String {
    format!(
        "Cannot index {kind} with string ({})",
        dump_trunc(&Value::String(key.to_string()))
    )
}

/// Formats `Cannot index <kind> with number (<truncated number>)` (jq 1.8).
pub fn cannot_index_number(kind: &str, idx: &Number) -> String {
    format!(
        "Cannot index {kind} with number ({})",
        dump_trunc(&Value::Number(idx.clone()))
    )
}

/// Formats `Cannot iterate over <kind> (<truncated value>)` (jq 1.8).
pub fn cannot_iterate(v: &Value) -> String {
    format!("Cannot iterate over {} ({})", v.kind(), dump_trunc(v))
}

/// Formats `jq: error (at <stdin>:<line>): <msg>\n`.
pub fn format_runtime_error(line: usize, msg: &str) -> String {
    format!("jq: error (at <stdin>:{line}): {msg}\n")
}

/// Formats `jq: parse error: <msg>\n`.
pub fn format_parse_error(msg: &str) -> String {
    format!("jq: parse error: {msg}\n")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn jq_18_error_wording() {
        assert_eq!(
            cannot_index_string("number", "x"),
            "Cannot index number with string (\"x\")"
        );
        assert_eq!(
            cannot_index_string("number", &"k".repeat(28)),
            format!(
                "Cannot index number with string (\"{}...\")",
                "k".repeat(24)
            )
        );
        assert_eq!(
            cannot_index_number("object", &Number::from_i64(0)),
            "Cannot index object with number (0)"
        );
        assert_eq!(
            cannot_iterate(&Value::Null),
            "Cannot iterate over null (null)"
        );
    }
}
