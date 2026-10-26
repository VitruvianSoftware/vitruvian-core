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

//! Version-pin registry parser for the conformance checker.
//!
//! Ports `parse_registry()` and `lookup_pin()` from check.sh. The registry
//! file (`version-pins.tsv`) is whitespace-aligned: fields are split on runs
//! of whitespace, with the sixth field onward treated as free-text reason
//! (rejoined with spaces).

use std::fs;
use std::path::Path;

/// The valid tool names a pin row may declare.
const VALID_TOOLS: &[&str] = &["go", "node", "pnpm"];

/// A single parsed row from the version-pins registry.
#[derive(Clone, Debug)]
pub struct PinRecord {
    pub file: String,
    pub tool: String,
    pub value: String,
    pub review_by: String,
    pub owner: String,
    pub reason: String,
}

/// The parsed version-pin registry.
#[derive(Debug)]
pub struct Registry {
    pub rows: Vec<PinRecord>,
}

impl Registry {
    /// Parse `version-pins.tsv` at the given path.
    ///
    /// Returns `Err(message)` with the die-format string on any validation
    /// failure (malformed row, unknown tool, bad date). The caller is expected
    /// to print to stderr and exit 2.
    pub fn parse(path: &str) -> Result<Self, String> {
        let p = Path::new(path);
        if !p.is_file() {
            return Err(format!("registry not found: {}", path));
        }

        let raw =
            fs::read_to_string(p).map_err(|e| format!("cannot read registry {}: {}", path, e))?;

        let mut rows = Vec::new();

        for line in raw.lines() {
            // Strip trailing CR (files saved on Windows).
            let line = line.strip_suffix('\r').unwrap_or(line);

            // Skip blank and comment lines.
            let trimmed = line.trim();
            if trimmed.is_empty() || trimmed.starts_with('#') {
                continue;
            }

            // Split on runs of whitespace (mirrors awk's `split($0, f, /[ \t]+/)`).
            let fields: Vec<&str> = line.split_whitespace().collect();

            if fields.len() < 6 {
                return Err(format!(
                    "malformed registry row (need: file tool pinned_value review_by owner reason): {}",
                    line
                ));
            }

            let file = fields[0].to_string();
            let tool = fields[1].to_string();
            let value = fields[2].to_string();
            let review_by = fields[3].to_string();
            let owner = fields[4].to_string();
            // Rejoin field 6+ with spaces (the free-text reason column).
            let reason = fields[5..].join(" ");

            // Validate tool name.
            if !VALID_TOOLS.contains(&tool.as_str()) {
                return Err(format!(
                    "registry row for '{}' has unknown tool '{}' (want go|node|pnpm)",
                    file, tool
                ));
            }

            // Validate review_by date format.
            if !valid_date(&review_by) {
                return Err(format!(
                    "registry row for '{}' ({}) has bad review_by date '{}' (want YYYY-MM-DD)",
                    file, tool, review_by
                ));
            }

            rows.push(PinRecord {
                file,
                tool,
                value,
                review_by,
                owner,
                reason,
            });
        }

        Ok(Registry { rows })
    }

    /// Look up a pin record by `(file, tool)`. Returns the first match, as
    /// bash's linear `while read` scan does.
    pub fn lookup(&self, file: &str, tool: &str) -> Option<&PinRecord> {
        self.rows.iter().find(|r| r.file == file && r.tool == tool)
    }

    /// Number of active pin records.
    pub fn active_count(&self) -> usize {
        self.rows.len()
    }
}

/// Validate a `YYYY-MM-DD` date string the same way bash's `valid_date` does:
///
/// ```bash
/// case "$1" in
///   [0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]) return 0 ;;
///   *) return 1 ;;
/// esac
/// ```
///
/// This is a lexical check only (it accepts 2099-19-39), matching bash.
fn valid_date(s: &str) -> bool {
    let b = s.as_bytes();
    if b.len() != 10 {
        return false;
    }
    // [0-9]{4}
    if !(b[0].is_ascii_digit()
        && b[1].is_ascii_digit()
        && b[2].is_ascii_digit()
        && b[3].is_ascii_digit())
    {
        return false;
    }
    // -
    if b[4] != b'-' {
        return false;
    }
    // [01][0-9]
    if !matches!(b[5], b'0' | b'1') || !b[6].is_ascii_digit() {
        return false;
    }
    // -
    if b[7] != b'-' {
        return false;
    }
    // [0-3][0-9]
    if !matches!(b[8], b'0'..=b'3') || !b[9].is_ascii_digit() {
        return false;
    }
    true
}

/// Format a die message the way bash does: `"✗ conformance — {message}\n"`.
/// The caller writes this to stderr and exits with code 2.
pub fn die_message(message: &str) -> String {
    format!("\u{2717} conformance \u{2014} {}\n", message)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn valid_date_accepts_good_dates() {
        assert!(valid_date("2026-10-25"));
        assert!(valid_date("2027-01-12"));
        assert!(valid_date("9999-09-09"));
        // Bash accepts these edge cases too (lexical check only).
        assert!(valid_date("2026-19-39"));
    }

    #[test]
    fn valid_date_rejects_bad_dates() {
        assert!(!valid_date(""));
        assert!(!valid_date("2026-1-12")); // single-digit month
        assert!(!valid_date("26-01-12")); // 2-digit year
        assert!(!valid_date("2026/01/12")); // wrong separator
        assert!(!valid_date("abcd-01-12")); // non-digit year
        assert!(!valid_date("2026-21-12")); // month tens digit is 2, not [01]
        assert!(!valid_date("2026-01-42")); // day tens digit is 4, not [0-3]
        assert!(!valid_date("2026-01-1")); // too short
        assert!(!valid_date("2026-01-12x")); // too long
    }

    #[test]
    fn parse_empty_registry() {
        let tmp = std::env::temp_dir().join(format!("reg_empty_{}", std::process::id()));
        std::fs::write(&tmp, "# only comments\n\n# another\n").unwrap();
        let reg = Registry::parse(tmp.to_str().unwrap()).unwrap();
        assert_eq!(reg.active_count(), 0);
        let _ = std::fs::remove_file(&tmp);
    }

    #[test]
    fn parse_valid_rows() {
        let tmp = std::env::temp_dir().join(format!("reg_valid_{}", std::process::id()));
        std::fs::write(
            &tmp,
            "# header\nsome/go.mod  go  1.22  2027-01-12  @james  the Go kit floor\n",
        )
        .unwrap();
        let reg = Registry::parse(tmp.to_str().unwrap()).unwrap();
        assert_eq!(reg.active_count(), 1);
        let r = &reg.rows[0];
        assert_eq!(r.file, "some/go.mod");
        assert_eq!(r.tool, "go");
        assert_eq!(r.value, "1.22");
        assert_eq!(r.review_by, "2027-01-12");
        assert_eq!(r.owner, "@james");
        assert_eq!(r.reason, "the Go kit floor");
        let _ = std::fs::remove_file(&tmp);
    }

    #[test]
    fn parse_multi_word_reason() {
        let tmp = std::env::temp_dir().join(format!("reg_reason_{}", std::process::id()));
        std::fs::write(
            &tmp,
            "path/go.mod  go  1.22  2027-01-12  @james  reason with many words here\n",
        )
        .unwrap();
        let reg = Registry::parse(tmp.to_str().unwrap()).unwrap();
        assert_eq!(reg.rows[0].reason, "reason with many words here");
        let _ = std::fs::remove_file(&tmp);
    }

    #[test]
    fn parse_rejects_unknown_tool() {
        let tmp = std::env::temp_dir().join(format!("reg_tool_{}", std::process::id()));
        std::fs::write(
            &tmp,
            "some/file  rust  1.80  2027-01-12  @james  reason text\n",
        )
        .unwrap();
        let err = Registry::parse(tmp.to_str().unwrap()).unwrap_err();
        assert!(err.contains("unknown tool 'rust'"), "got: {}", err);
        let _ = std::fs::remove_file(&tmp);
    }

    #[test]
    fn parse_rejects_bad_date() {
        let tmp = std::env::temp_dir().join(format!("reg_date_{}", std::process::id()));
        std::fs::write(
            &tmp,
            "some/go.mod  go  1.22  27-01-12  @james  reason text\n",
        )
        .unwrap();
        let err = Registry::parse(tmp.to_str().unwrap()).unwrap_err();
        assert!(err.contains("bad review_by date"), "got: {}", err);
        let _ = std::fs::remove_file(&tmp);
    }

    #[test]
    fn parse_rejects_malformed_row() {
        let tmp = std::env::temp_dir().join(format!("reg_mal_{}", std::process::id()));
        std::fs::write(&tmp, "only three fields here nope\n").unwrap();
        let err = Registry::parse(tmp.to_str().unwrap()).unwrap_err();
        assert!(err.contains("malformed registry row"), "got: {}", err);
        let _ = std::fs::remove_file(&tmp);
    }

    #[test]
    fn parse_missing_file() {
        let err = Registry::parse("/nonexistent/path/version-pins.tsv").unwrap_err();
        assert!(err.contains("registry not found"), "got: {}", err);
    }

    #[test]
    fn lookup_finds_record() {
        let tmp = std::env::temp_dir().join(format!("reg_lookup_{}", std::process::id()));
        std::fs::write(
            &tmp,
            concat!(
                "a/go.mod  go  1.22  2027-01-12  @alice  reason a\n",
                "b/go.mod  go  1.23  2027-02-15  @bob    reason b\n",
            ),
        )
        .unwrap();
        let reg = Registry::parse(tmp.to_str().unwrap()).unwrap();
        let hit = reg.lookup("b/go.mod", "go").unwrap();
        assert_eq!(hit.value, "1.23");
        assert_eq!(hit.owner, "@bob");
        assert!(reg.lookup("c/go.mod", "go").is_none());
        assert!(reg.lookup("a/go.mod", "node").is_none());
        let _ = std::fs::remove_file(&tmp);
    }

    #[test]
    fn die_message_format() {
        let msg = die_message("something broke");
        assert_eq!(msg, "\u{2717} conformance \u{2014} something broke\n");
    }

    #[test]
    fn parse_strips_carriage_return() {
        let tmp = std::env::temp_dir().join(format!("reg_cr_{}", std::process::id()));
        std::fs::write(
            &tmp,
            "some/go.mod  go  1.22  2027-01-12  @james  reason\r\n",
        )
        .unwrap();
        let reg = Registry::parse(tmp.to_str().unwrap()).unwrap();
        assert_eq!(reg.active_count(), 1);
        assert_eq!(reg.rows[0].reason, "reason");
        let _ = std::fs::remove_file(&tmp);
    }

    #[test]
    fn parse_handles_extra_whitespace_alignment() {
        let tmp = std::env::temp_dir().join(format!("reg_ws_{}", std::process::id()));
        // Heavily indented / aligned, mimicking the real file's spacing.
        std::fs::write(
            &tmp,
            "  some/go.mod                 go  1.22  2027-01-12  @james  the floor version\n",
        )
        .unwrap();
        let reg = Registry::parse(tmp.to_str().unwrap()).unwrap();
        assert_eq!(reg.active_count(), 1);
        assert_eq!(reg.rows[0].file, "some/go.mod");
        assert_eq!(reg.rows[0].reason, "the floor version");
        let _ = std::fs::remove_file(&tmp);
    }
}
