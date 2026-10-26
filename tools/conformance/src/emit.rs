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

//! Output formatting engine for the conformance checker.
//!
//! Port of `emit()`, `print_group()`, banner and summary output from
//! `check.sh`. Rows are buffered per group using US (0x1F) as the field
//! separator and RS (0x1E) as the row separator, matching the bash original.

use std::cell::RefCell;
use std::collections::HashMap;

// ---------------------------------------------------------------------------
// Glyphs
// ---------------------------------------------------------------------------

pub const GLYPH_OK: &str = "\u{2713}"; // ✓
pub const GLYPH_FAIL: &str = "\u{2717}"; // ✗
pub const GLYPH_PIN: &str = "\u{2298}"; // ⊘
pub const GLYPH_WARN: &str = "\u{26A0}"; // ⚠

// ---------------------------------------------------------------------------
// Separators (matching the bash US / RS convention)
// ---------------------------------------------------------------------------

const US: char = '\x1F'; // unit separator — field delimiter inside a row
const RS: char = '\x1E'; // record separator — row delimiter

// ---------------------------------------------------------------------------
// Colors
// ---------------------------------------------------------------------------

/// ANSI escape sequences, populated only when stdout is an interactive TTY.
/// When piped or redirected every field is the empty string so the report
/// greps cleanly.
pub struct Colors {
    pub reset: &'static str,
    pub green: &'static str,
    pub yellow: &'static str,
    pub red: &'static str,
    pub dim: &'static str,
    pub bold: &'static str,
    pub cyan: &'static str,
}

impl Colors {
    /// Detect whether stdout is a TTY and return populated or empty codes.
    pub fn detect() -> Self {
        if shell_compat::stdout_is_tty() {
            Self {
                reset: "\x1b[0m",
                green: "\x1b[32m",
                yellow: "\x1b[33m",
                red: "\x1b[31m",
                dim: "\x1b[2m",
                bold: "\x1b[1m",
                cyan: "\x1b[36m",
            }
        } else {
            Self {
                reset: "",
                green: "",
                yellow: "",
                red: "",
                dim: "",
                bold: "",
                cyan: "",
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Row buffers
// ---------------------------------------------------------------------------

/// Per-group row accumulator. Each group name maps to a string of
/// RS-delimited rows whose fields are US-delimited.
///
/// The `RefCell` mirrors the bash pattern where `emit()` is called from
/// many places and appends to global variables; a single `&RowBuffers`
/// reference is all any check function needs.
pub struct RowBuffers {
    groups: RefCell<HashMap<String, String>>,
}

impl RowBuffers {
    pub fn new() -> Self {
        Self {
            groups: RefCell::new(HashMap::new()),
        }
    }

    /// Append a row to the named group, exactly as the bash `emit()` does:
    ///
    /// ```text
    /// row = glyph US color US file US found US canon US note US fix RS
    /// ```
    pub fn emit(
        &self,
        group: &str,
        glyph: &str,
        color: &str,
        file: &str,
        found: &str,
        canon: &str,
        note: &str,
        fix: &str,
    ) {
        let mut row = String::new();
        row.push_str(glyph);
        row.push(US);
        row.push_str(color);
        row.push(US);
        row.push_str(file);
        row.push(US);
        row.push_str(found);
        row.push(US);
        row.push_str(canon);
        row.push(US);
        row.push_str(note);
        row.push(US);
        row.push_str(fix);
        row.push(RS);

        let mut groups = self.groups.borrow_mut();
        groups
            .entry(group.to_ascii_uppercase())
            .or_default()
            .push_str(&row);
    }

    /// Retrieve the accumulated rows for `group` (uppercased to match the
    /// bash `ROWS_GO`, `ROWS_NODE`, ... convention). Returns an empty string
    /// when the group has no rows.
    pub fn get(&self, group: &str) -> String {
        self.groups
            .borrow()
            .get(&group.to_ascii_uppercase())
            .cloned()
            .unwrap_or_default()
    }
}

// ---------------------------------------------------------------------------
// Row parsing helpers (split on US / RS)
// ---------------------------------------------------------------------------

/// A single parsed row from the buffer.
struct Row<'a> {
    glyph: &'a str,
    color: &'a str,
    file: &'a str,
    found: &'a str,
    canon: &'a str,
    note: &'a str,
    fix: &'a str,
}

/// Split a raw row string (US-delimited) into its seven fields.
fn parse_row(raw: &str) -> Option<Row<'_>> {
    let fields: Vec<&str> = raw.split(US).collect();
    if fields.len() < 7 {
        return None;
    }
    Some(Row {
        glyph: fields[0],
        color: fields[1],
        file: fields[2],
        found: fields[3],
        canon: fields[4],
        note: fields[5],
        fix: fields[6],
    })
}

// ---------------------------------------------------------------------------
// print_group
// ---------------------------------------------------------------------------

/// Print a titled group of rows, column-aligned.
///
/// Port of `print_group()` from check.sh (lines 4083-4121). A width pass
/// measures the file / found / canon columns, then a print pass emits each
/// row left-justified in those widths. An optional fix line is indented
/// below each row that carries one.
///
/// Does nothing when `rows` is empty.
pub fn print_group(colors: &Colors, title: &str, rows: &str) {
    if rows.is_empty() {
        return;
    }

    let raw_rows: Vec<&str> = rows.split(RS).filter(|r| !r.is_empty()).collect();

    if raw_rows.is_empty() {
        return;
    }

    // -- width pass ----------------------------------------------------------
    let mut w_file: usize = 4; // "file"
    let mut w_found: usize = 5; // "found"
    let mut w_canon: usize = 9; // "canonical"

    let parsed: Vec<Option<Row<'_>>> = raw_rows.iter().map(|r| parse_row(r)).collect();

    for row in parsed.iter().flatten() {
        let lf = row.file.chars().count();
        let lfn = row.found.chars().count();
        let lc = row.canon.chars().count();
        if lf > w_file {
            w_file = lf;
        }
        if lfn > w_found {
            w_found = lfn;
        }
        if lc > w_canon {
            w_canon = lc;
        }
    }

    // -- header --------------------------------------------------------------
    println!("\n{}{}{}", colors.bold, title, colors.reset);

    // -- print pass ----------------------------------------------------------
    for row in parsed.iter().flatten() {
        // Pad with spaces to the measured width, counting characters (not
        // bytes) to match bash's `${#field}` in a UTF-8 locale.
        let file_pad = w_file.saturating_sub(row.file.chars().count());
        let found_pad = w_found.saturating_sub(row.found.chars().count());
        let canon_pad = w_canon.saturating_sub(row.canon.chars().count());

        print!(
            "  {}{}{}  {}{:fp$}  found {}{:fnp$}  canon {}{:cp$}",
            row.color,
            row.glyph,
            colors.reset,
            row.file,
            "",
            row.found,
            "",
            row.canon,
            "",
            fp = file_pad,
            fnp = found_pad,
            cp = canon_pad,
        );
        if !row.note.is_empty() {
            print!("  {}{}{}", colors.dim, row.note, colors.reset);
        }
        println!();
        if !row.fix.is_empty() {
            println!(
                "       {}\u{2192} fix: {}{}",
                colors.dim, row.fix, colors.reset
            );
        }
    }
}

// ---------------------------------------------------------------------------
// Banner
// ---------------------------------------------------------------------------

/// Print the conformance banner with canonical version information.
///
/// ```text
/// {bold}{green}conformance{reset} — vitruvian-core version conformance
/// {dim}canonical: go {go} (go.work) · node {node} (.nvmrc) · pnpm {pnpm} (package.json){reset}
/// ```
pub fn print_banner(colors: &Colors, go: &str, node: &str, pnpm: &str) {
    println!();
    println!(
        "{}{}conformance{} \u{2014} vitruvian-core version conformance",
        colors.bold, colors.green, colors.reset,
    );
    println!(
        "{}canonical: go {} (go.work) \u{00B7} node {} (.nvmrc) \u{00B7} pnpm {} (package.json){}",
        colors.dim, go, node, pnpm, colors.reset,
    );
}

// ---------------------------------------------------------------------------
// Summary
// ---------------------------------------------------------------------------

/// Print the final summary line and the explanatory footer.
///
/// When `overall_fail` is true the line reads `FAIL` in red; otherwise
/// `PASS` in green.
pub fn print_summary(
    colors: &Colors,
    ok: u32,
    pinned: u32,
    advisory: u32,
    fail: u32,
    active_pins: usize,
    overall_fail: bool,
) {
    println!();
    if overall_fail {
        println!(
            "{}{} FAIL{} \u{2014} {} ok, {} pinned, {} advisory, {} fail. ({} active pins in version-pins.tsv)",
            colors.red, GLYPH_FAIL, colors.reset,
            ok, pinned, advisory, fail, active_pins,
        );
    } else {
        println!(
            "{}{} PASS{} \u{2014} {} ok, {} pinned, {} advisory, {} fail. ({} active pins in version-pins.tsv)",
            colors.green, GLYPH_OK, colors.reset,
            ok, pinned, advisory, fail, active_pins,
        );
    }
    println!(
        "{}every file must match canonical; deviations live only as justified, temporary pins in tools/conformance/version-pins.tsv{}",
        colors.dim, colors.reset,
    );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    fn no_color() -> Colors {
        Colors {
            reset: "",
            green: "",
            yellow: "",
            red: "",
            dim: "",
            bold: "",
            cyan: "",
        }
    }

    #[test]
    fn emit_and_get_round_trip() {
        let buf = RowBuffers::new();
        buf.emit("go", GLYPH_OK, "", "go.mod", "1.23", "1.23", "ok", "");
        buf.emit(
            "go",
            GLYPH_FAIL,
            "",
            "apps/cli/devx/go.mod",
            "1.22",
            "1.23",
            "mismatch",
            "update go.mod",
        );

        let rows = buf.get("go");
        assert!(!rows.is_empty());

        // Each row ends with RS and has 7 US-delimited fields.
        let parsed: Vec<&str> = rows.split(RS).filter(|r| !r.is_empty()).collect();
        assert_eq!(parsed.len(), 2);

        let first_fields: Vec<&str> = parsed[0].split(US).collect();
        assert_eq!(first_fields.len(), 7);
        assert_eq!(first_fields[0], GLYPH_OK); // glyph
        assert_eq!(first_fields[2], "go.mod"); // file
        assert_eq!(first_fields[3], "1.23"); // found
        assert_eq!(first_fields[4], "1.23"); // canon
        assert_eq!(first_fields[5], "ok"); // note
        assert_eq!(first_fields[6], ""); // fix (empty)

        let second_fields: Vec<&str> = parsed[1].split(US).collect();
        assert_eq!(second_fields[6], "update go.mod"); // fix
    }

    #[test]
    fn get_unknown_group_is_empty() {
        let buf = RowBuffers::new();
        assert!(buf.get("nonexistent").is_empty());
    }

    #[test]
    fn group_key_is_uppercased() {
        let buf = RowBuffers::new();
        buf.emit("node", GLYPH_OK, "", "f", "22", "22", "ok", "");
        // get with different casing works.
        assert!(!buf.get("NODE").is_empty());
        assert!(!buf.get("node").is_empty());
        assert!(!buf.get("Node").is_empty());
    }

    #[test]
    fn print_group_empty_is_silent() {
        // Should not panic and should produce no output.
        let colors = no_color();
        print_group(&colors, "Empty group", "");
    }

    #[test]
    fn parse_row_splits_correctly() {
        let raw = format!(
            "{}{}{}{}{}{}{}{}{}{}{}{}{}",
            GLYPH_OK, US, "", US, "go.mod", US, "1.23", US, "1.23", US, "ok", US, ""
        );
        let row = parse_row(&raw).expect("should parse");
        assert_eq!(row.glyph, GLYPH_OK);
        assert_eq!(row.file, "go.mod");
        assert_eq!(row.found, "1.23");
        assert_eq!(row.canon, "1.23");
        assert_eq!(row.note, "ok");
        assert_eq!(row.fix, "");
    }

    #[test]
    fn width_measurement_uses_char_count() {
        // A file path with multi-byte characters should be measured by
        // char count, not byte count.
        let buf = RowBuffers::new();
        buf.emit("go", GLYPH_OK, "", "caf\u{00E9}", "1.23", "1.23", "", "");
        let rows = buf.get("go");
        let raw_rows: Vec<&str> = rows.split(RS).filter(|r| !r.is_empty()).collect();
        let row = parse_row(raw_rows[0]).unwrap();
        // "caf\u{00E9}" is 4 characters (c, a, f, e-with-acute) but 5 bytes.
        assert_eq!(row.file.chars().count(), 4);
        assert_eq!(row.file.len(), 5);
    }
}
