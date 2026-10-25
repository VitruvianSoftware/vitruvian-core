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

//! `NamingViolation` and `ViolationSeverity` from rules/__init__.py.

use crate::pystr::json_string;

/// ViolationSeverity.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Severity {
    Error,
    Warning,
    Info,
}

impl Severity {
    /// The enum's value: "ERROR", "WARNING" or "INFO".
    pub fn as_str(self) -> &'static str {
        match self {
            Severity::Error => "ERROR",
            Severity::Warning => "WARNING",
            Severity::Info => "INFO",
        }
    }

    pub fn parse(s: &str) -> Option<Severity> {
        match s {
            "ERROR" => Some(Severity::Error),
            "WARNING" => Some(Severity::Warning),
            "INFO" => Some(Severity::Info),
            _ => None,
        }
    }
}

/// NamingViolation.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Violation {
    pub rule_id: String,
    pub file_path: String,
    pub line_number: Option<i64>,
    pub message: String,
    pub severity: Severity,
    pub suggested_fix: Option<String>,
}

impl Violation {
    pub fn new(
        rule_id: &str,
        file_path: &str,
        line_number: Option<i64>,
        message: String,
        severity: Severity,
        suggested_fix: Option<String>,
    ) -> Violation {
        Violation {
            rule_id: rule_id.to_string(),
            file_path: file_path.to_string(),
            line_number,
            message,
            severity,
            suggested_fix,
        }
    }

    /// `format_line()`. A line number of 0 and an empty fix are falsy in
    /// Python, so they are left out just as None is.
    pub fn format_line(&self) -> String {
        let loc = match self.line_number {
            Some(n) if n != 0 => format!("{}:{}", self.file_path, n),
            _ => self.file_path.clone(),
        };
        let fix = match &self.suggested_fix {
            Some(f) if !f.is_empty() => format!(" (suggested: '{}')", f),
            _ => String::new(),
        };
        format!(
            "{}: [{}] {}: {}{}",
            loc,
            self.rule_id,
            self.severity.as_str(),
            self.message,
            fix
        )
    }

    /// `json.dumps(v.to_dict(), indent=2)` nested `depth` levels deep.
    pub fn to_json(&self, indent: &str) -> String {
        let inner = format!("{}  ", indent);
        let line = match self.line_number {
            Some(n) => n.to_string(),
            None => "null".to_string(),
        };
        let fix = match &self.suggested_fix {
            Some(f) => json_string(f),
            None => "null".to_string(),
        };
        let fields = [
            ("rule_id", json_string(&self.rule_id)),
            ("file_path", json_string(&self.file_path)),
            ("line_number", line),
            ("severity", json_string(self.severity.as_str())),
            ("message", json_string(&self.message)),
            ("suggested_fix", fix),
        ];
        let body: Vec<String> = fields
            .iter()
            .map(|(k, v)| format!("{}\"{}\": {}", inner, k, v))
            .collect();
        format!("{{\n{}\n{}}}", body.join(",\n"), indent)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn v(line: Option<i64>, fix: Option<&str>) -> Violation {
        Violation::new(
            "GO001",
            "a/b.go",
            line,
            "msg".into(),
            Severity::Error,
            fix.map(String::from),
        )
    }

    #[test]
    fn format_line_matches_python() {
        assert_eq!(v(None, None).format_line(), "a/b.go: [GO001] ERROR: msg");
        assert_eq!(
            v(Some(3), Some("x")).format_line(),
            "a/b.go:3: [GO001] ERROR: msg (suggested: 'x')"
        );
        assert_eq!(
            v(Some(0), Some("")).format_line(),
            "a/b.go: [GO001] ERROR: msg"
        );
        assert_eq!(
            v(Some(-1), None).format_line(),
            "a/b.go:-1: [GO001] ERROR: msg"
        );
    }

    #[test]
    fn to_json_matches_python() {
        let expected = "{\n    \"rule_id\": \"GO001\",\n    \"file_path\": \"a/b.go\",\n    \"line_number\": null,\n    \"severity\": \"ERROR\",\n    \"message\": \"msg\",\n    \"suggested_fix\": \"x\"\n  }";
        assert_eq!(v(None, Some("x")).to_json("  "), expected);
    }
}
