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

//! The slices of the Go standard library whose exact output the generator's
//! callers can see: `%q` / `%v` formatting, `strconv` number formatting and
//! parsing, `path/filepath` lexical path handling, and the text of `os` /
//! `syscall` errors.
//!
//! Every function here exists because the Go generator printed something
//! through it — into a workflow file (tidy-check diffs those bytes) or into an
//! error message (the parity test diffs those too). They are ports of the Go
//! 1.26 sources, not approximations of what the output "usually" looks like.

use std::collections::BTreeMap;
use std::io;

/// A decoded `interface{}` value from a delivery() JSON file — the element
/// type of `workflow_inputs` / `changelog_inputs`.
#[derive(Clone, Debug, PartialEq)]
pub enum Value {
    Null,
    Bool(bool),
    Num(f64),
    Str(String),
    Arr(Vec<Value>),
    Obj(BTreeMap<String, Value>),
}

// ---------------------------------------------------------------------------
// UTF-8 decoding with Go's error semantics.
// ---------------------------------------------------------------------------

/// utf8.DecodeRune: the rune at the start of `b` and its width, or
/// (None, 1) for an invalid or truncated sequence — Go replaces EACH such
/// byte with U+FFFD, where Rust's from_utf8_lossy replaces a maximal prefix.
pub fn decode_rune(b: &[u8]) -> (Option<char>, usize) {
    if b.is_empty() {
        return (None, 0);
    }
    let b0 = b[0];
    if b0 < 0x80 {
        return (Some(b0 as char), 1);
    }
    let cont = |i: usize, lo: u8, hi: u8| -> bool { i < b.len() && b[i] >= lo && b[i] <= hi };
    let (n, lo, hi) = match b0 {
        0xC2..=0xDF => (2, 0x80, 0xBF),
        0xE0 => (3, 0xA0, 0xBF),
        0xE1..=0xEC | 0xEE..=0xEF => (3, 0x80, 0xBF),
        0xED => (3, 0x80, 0x9F),
        0xF0 => (4, 0x90, 0xBF),
        0xF1..=0xF3 => (4, 0x80, 0xBF),
        0xF4 => (4, 0x80, 0x8F),
        _ => return (None, 1),
    };
    if !cont(1, lo, hi) {
        return (None, 1);
    }
    for i in 2..n {
        if !cont(i, 0x80, 0xBF) {
            return (None, 1);
        }
    }
    match std::str::from_utf8(&b[..n]) {
        Ok(s) => (s.chars().next(), n),
        Err(_) => (None, 1),
    }
}

/// Bytes to a String the way a Go `string([]byte)` later ranged over as
/// runes would read: each invalid byte becomes U+FFFD.
pub fn go_lossy(b: &[u8]) -> String {
    if let Ok(s) = std::str::from_utf8(b) {
        return s.to_string();
    }
    let mut out = String::with_capacity(b.len());
    let mut i = 0;
    while i < b.len() {
        let (r, n) = decode_rune(&b[i..]);
        out.push(r.unwrap_or('\u{FFFD}'));
        i += n;
    }
    out
}

// ---------------------------------------------------------------------------
// strconv.Quote — what `%q` prints.
// ---------------------------------------------------------------------------

/// unicode.IsPrint, as closely as the Rust standard library allows: letters,
/// marks, numbers, punctuation and symbols plus the ASCII space. Rust exposes
/// no general-category table, so this excludes the categories Go excludes —
/// controls, separators, format characters, private use, surrogates and the
/// noncharacters — by range. Unassigned code points are the one gap: Go treats
/// them as unprintable, this treats them as printable.
pub fn is_print(c: char) -> bool {
    let r = c as u32;
    if r < 0x80 {
        return (0x20..0x7F).contains(&r);
    }
    if c.is_control() || c.is_whitespace() {
        return false;
    }
    let ranges: &[(u32, u32)] = &[
        (0x00AD, 0x00AD),
        (0x0600, 0x0605),
        (0x061C, 0x061C),
        (0x06DD, 0x06DD),
        (0x070F, 0x070F),
        (0x0890, 0x0891),
        (0x08E2, 0x08E2),
        (0x180E, 0x180E),
        (0x200B, 0x200F),
        (0x202A, 0x202E),
        (0x2060, 0x2064),
        (0x2066, 0x206F),
        (0xD800, 0xDFFF),
        (0xE000, 0xF8FF),
        (0xFDD0, 0xFDEF),
        (0xFEFF, 0xFEFF),
        (0xFFF0, 0xFFFB),
        (0x110BD, 0x110BD),
        (0x110CD, 0x110CD),
        (0x13430, 0x1343F),
        (0x1BCA0, 0x1BCA3),
        (0x1D173, 0x1D17A),
        (0xE0000, 0xE0FFF),
        (0xF0000, 0x10FFFF),
    ];
    if (r & 0xFFFE) == 0xFFFE {
        return false;
    }
    !ranges.iter().any(|&(lo, hi)| r >= lo && r <= hi)
}

fn push_escaped_rune(out: &mut String, c: char, quote: char) {
    if c == quote || c == '\\' {
        out.push('\\');
        out.push(c);
        return;
    }
    if is_print(c) {
        out.push(c);
        return;
    }
    match c {
        '\x07' => out.push_str("\\a"),
        '\x08' => out.push_str("\\b"),
        '\x0C' => out.push_str("\\f"),
        '\n' => out.push_str("\\n"),
        '\r' => out.push_str("\\r"),
        '\t' => out.push_str("\\t"),
        '\x0B' => out.push_str("\\v"),
        _ => {
            let r = c as u32;
            if r < 0x20 || r == 0x7F {
                out.push_str(&format!("\\x{:02x}", r));
            } else if r < 0x10000 {
                out.push_str(&format!("\\u{:04x}", r));
            } else {
                out.push_str(&format!("\\U{:08x}", r));
            }
        }
    }
}

/// strconv.Quote over raw bytes (invalid UTF-8 becomes `\xHH`).
pub fn quote_bytes(b: &[u8]) -> String {
    let mut out = String::with_capacity(b.len() + 2);
    out.push('"');
    let mut i = 0;
    while i < b.len() {
        let (r, n) = decode_rune(&b[i..]);
        match r {
            None => out.push_str(&format!("\\x{:02x}", b[i])),
            Some(c) => push_escaped_rune(&mut out, c, '"'),
        }
        i += n;
    }
    out.push('"');
    out
}

/// `%q` of a string.
pub fn q(s: &str) -> String {
    quote_bytes(s.as_bytes())
}

/// The JSON scanner's quoteChar: a single BYTE, widened to a rune.
pub fn quote_char(c: u8) -> String {
    if c == b'\'' {
        return "'\\''".to_string();
    }
    if c == b'"' {
        return "'\"'".to_string();
    }
    let mut s = String::new();
    push_escaped_rune(&mut s, c as char, '"');
    format!("'{}'", s)
}

// ---------------------------------------------------------------------------
// Float formatting: strconv.FormatFloat(f, 'e'|'f'|'g', -1, 64).
// ---------------------------------------------------------------------------

/// The shortest decimal digits that round-trip `abs` (> 0), and the decimal
/// point position: abs = 0.DIGITS × 10^dp.
fn shortest_digits(abs: f64) -> (String, i32) {
    // Rust's `{:e}` prints the shortest round-tripping digits, like Go's -1
    // precision: "d.ddde±x".
    let s = format!("{:e}", abs);
    let (mant, exp) = s.split_once('e').unwrap();
    let exp: i32 = exp.parse().unwrap();
    let digits: String = mant.chars().filter(|c| *c != '.').collect();
    (digits, exp + 1)
}

fn fmt_e(neg: bool, digits: &str, dp: i32) -> String {
    let mut out = String::new();
    if neg {
        out.push('-');
    }
    out.push_str(&digits[..1]);
    if digits.len() > 1 {
        out.push('.');
        out.push_str(&digits[1..]);
    }
    let exp = if digits == "0" { 0 } else { dp - 1 };
    out.push('e');
    if exp < 0 {
        out.push('-');
    } else {
        out.push('+');
    }
    let a = exp.abs();
    if a < 10 {
        out.push('0');
    }
    out.push_str(&a.to_string());
    out
}

fn fmt_f(neg: bool, digits: &str, dp: i32) -> String {
    let mut out = String::new();
    if neg {
        out.push('-');
    }
    let nd = digits.len() as i32;
    if dp > 0 {
        for i in 0..dp {
            out.push(if i < nd {
                digits.as_bytes()[i as usize] as char
            } else {
                '0'
            });
        }
    } else {
        out.push('0');
    }
    if nd > dp.max(0) {
        out.push('.');
        for i in dp..nd {
            out.push(if i < 0 {
                '0'
            } else {
                digits.as_bytes()[i as usize] as char
            });
        }
    }
    out
}

fn float_parts(f: f64) -> (bool, String, i32) {
    let neg = f.is_sign_negative();
    let abs = f.abs();
    if abs == 0.0 {
        return (neg, "0".to_string(), 1);
    }
    let (d, dp) = shortest_digits(abs);
    (neg, d, dp)
}

/// strconv.FormatFloat(f, 'g', -1, 64) — what `%v` prints for a float64.
pub fn format_g(f: f64) -> String {
    if f.is_nan() {
        return "NaN".into();
    }
    if f.is_infinite() {
        return if f > 0.0 {
            "+Inf".into()
        } else {
            "-Inf".into()
        };
    }
    let (neg, digits, dp) = float_parts(f);
    let nd = digits.len() as i32;
    let mut eprec = 6;
    if eprec > nd && nd >= dp {
        eprec = nd;
    }
    let exp = dp - 1;
    if exp < -4 || exp >= eprec {
        return fmt_e(neg, &digits, dp);
    }
    fmt_f(neg, &digits, dp)
}

/// encoding/json's float64 encoder (ES6 number-to-string).
pub fn json_float(f: f64) -> String {
    let abs = f.abs();
    let (neg, digits, dp) = float_parts(f);
    if abs != 0.0 && !(1e-6..1e21).contains(&abs) {
        let mut s = fmt_e(neg, &digits, dp);
        let n = s.len();
        let b = s.as_bytes();
        if n >= 4 && b[n - 4] == b'e' && b[n - 3] == b'-' && b[n - 2] == b'0' {
            let last = b[n - 1] as char;
            s.truncate(n - 2);
            s.push(last);
        }
        return s;
    }
    fmt_f(neg, &digits, dp)
}

/// encoding/json's string encoder with HTML escaping (json.Marshal's default).
pub fn json_string(s: &str) -> String {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut out = String::with_capacity(s.len() + 2);
    out.push('"');
    for c in s.chars() {
        match c {
            '\\' | '"' => {
                out.push('\\');
                out.push(c);
            }
            '\x08' => out.push_str("\\b"),
            '\x0C' => out.push_str("\\f"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            '<' | '>' | '&' => {
                let b = c as u8;
                out.push_str("\\u00");
                out.push(HEX[(b >> 4) as usize] as char);
                out.push(HEX[(b & 0xF) as usize] as char);
            }
            c if (c as u32) < 0x20 => {
                let b = c as u8;
                out.push_str("\\u00");
                out.push(HEX[(b >> 4) as usize] as char);
                out.push(HEX[(b & 0xF) as usize] as char);
            }
            '\u{2028}' => out.push_str("\\u2028"),
            '\u{2029}' => out.push_str("\\u2029"),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

/// `%v` of a decoded interface value.
pub fn value_v(v: &Value) -> String {
    match v {
        Value::Null => "<nil>".into(),
        Value::Bool(b) => b.to_string(),
        Value::Num(f) => format_g(*f),
        Value::Str(s) => s.clone(),
        Value::Arr(a) => format!("[{}]", a.iter().map(value_v).collect::<Vec<_>>().join(" ")),
        Value::Obj(m) => format!(
            "map[{}]",
            m.iter()
                .map(|(k, v)| format!("{}:{}", k, value_v(v)))
                .collect::<Vec<_>>()
                .join(" ")
        ),
    }
}

/// `%T` of a decoded interface value.
pub fn value_t(v: &Value) -> &'static str {
    match v {
        Value::Null => "<nil>",
        Value::Bool(_) => "bool",
        Value::Num(_) => "float64",
        Value::Str(_) => "string",
        Value::Arr(_) => "[]interface {}",
        Value::Obj(_) => "map[string]interface {}",
    }
}

/// `%v` of a []string.
pub fn vec_v(v: &[String]) -> String {
    format!("[{}]", v.join(" "))
}

// ---------------------------------------------------------------------------
// strconv.ParseInt(s, 0, 64), as the flag package uses it.
// ---------------------------------------------------------------------------

#[derive(Debug, PartialEq)]
pub enum NumErr {
    Syntax,
    Range,
}

fn lower(c: u8) -> u8 {
    c | 0x20
}

fn underscore_ok(s: &[u8]) -> bool {
    let mut saw = b'^';
    let mut i = 0;
    let mut s = s;
    if !s.is_empty() && (s[0] == b'-' || s[0] == b'+') {
        s = &s[1..];
    }
    let mut hex = false;
    if s.len() >= 2 && s[0] == b'0' && matches!(lower(s[1]), b'b' | b'o' | b'x') {
        i = 2;
        saw = b'0';
        hex = lower(s[1]) == b'x';
    }
    while i < s.len() {
        let c = s[i];
        if c.is_ascii_digit() || (hex && (b'a'..=b'f').contains(&lower(c))) {
            saw = b'0';
            i += 1;
            continue;
        }
        if c == b'_' {
            if saw != b'0' {
                return false;
            }
            saw = b'_';
            i += 1;
            continue;
        }
        if saw == b'_' {
            return false;
        }
        saw = b'!';
        i += 1;
    }
    saw != b'_'
}

fn parse_uint0(s0: &[u8]) -> Result<u64, NumErr> {
    if s0.is_empty() {
        return Err(NumErr::Syntax);
    }
    let mut s = s0;
    let mut base: u64 = 10;
    if s[0] == b'0' {
        if s.len() >= 3 && lower(s[1]) == b'b' {
            base = 2;
            s = &s[2..];
        } else if s.len() >= 3 && lower(s[1]) == b'o' {
            base = 8;
            s = &s[2..];
        } else if s.len() >= 3 && lower(s[1]) == b'x' {
            base = 16;
            s = &s[2..];
        } else {
            base = 8;
            s = &s[1..];
        }
    }
    let cutoff = u64::MAX / base + 1;
    let mut n: u64 = 0;
    let mut underscores = false;
    for &c in s {
        let d: u64;
        if c == b'_' {
            underscores = true;
            continue;
        } else if c.is_ascii_digit() {
            d = (c - b'0') as u64;
        } else if lower(c).is_ascii_lowercase() {
            d = (lower(c) - b'a' + 10) as u64;
        } else {
            return Err(NumErr::Syntax);
        }
        if d >= base {
            return Err(NumErr::Syntax);
        }
        if n >= cutoff {
            return Err(NumErr::Range);
        }
        n *= base;
        let (n1, over) = n.overflowing_add(d);
        if over {
            return Err(NumErr::Range);
        }
        n = n1;
    }
    if underscores && !underscore_ok(s0) {
        return Err(NumErr::Syntax);
    }
    Ok(n)
}

pub fn parse_int0(s: &str) -> Result<i64, NumErr> {
    let b = s.as_bytes();
    if b.is_empty() {
        return Err(NumErr::Syntax);
    }
    let (neg, rest) = match b[0] {
        b'+' => (false, &b[1..]),
        b'-' => (true, &b[1..]),
        _ => (false, b),
    };
    let un = parse_uint0(rest)?;
    let cutoff: u64 = 1 << 63;
    if !neg && un >= cutoff {
        return Err(NumErr::Range);
    }
    if neg && un > cutoff {
        return Err(NumErr::Range);
    }
    Ok(if neg {
        (un as i64).wrapping_neg()
    } else {
        un as i64
    })
}

// ---------------------------------------------------------------------------
// path/filepath (Unix).
// ---------------------------------------------------------------------------

/// filepath.Clean.
pub fn clean(path: &str) -> String {
    if path.is_empty() {
        return ".".into();
    }
    let rooted = path.starts_with('/');
    let mut out: Vec<&str> = Vec::new();
    for part in path.split('/') {
        match part {
            "" | "." => {}
            ".." => {
                if let Some(last) = out.last() {
                    if *last != ".." {
                        out.pop();
                        continue;
                    }
                }
                if !rooted {
                    out.push("..");
                }
            }
            p => out.push(p),
        }
    }
    let body = out.join("/");
    if rooted {
        format!("/{}", body)
    } else if body.is_empty() {
        ".".into()
    } else {
        body
    }
}

/// filepath.Join.
pub fn join(parts: &[&str]) -> String {
    let nonempty: Vec<&str> = parts.iter().copied().filter(|p| !p.is_empty()).collect();
    if nonempty.is_empty() {
        return String::new();
    }
    clean(&nonempty.join("/"))
}

/// filepath.Dir.
pub fn dir(path: &str) -> String {
    let i = path.rfind('/').map(|i| i + 1).unwrap_or(0);
    clean(&path[..i])
}

/// filepath.Ext.
pub fn ext(path: &str) -> &str {
    for (i, c) in path.char_indices().rev() {
        if c == '/' {
            break;
        }
        if c == '.' {
            return &path[i..];
        }
    }
    ""
}

pub fn is_abs(path: &str) -> bool {
    path.starts_with('/')
}

// ---------------------------------------------------------------------------
// os / syscall error text.
// ---------------------------------------------------------------------------

/// syscall.Errno.Error(): Go's per-OS tables are strerror(3) with the first
/// letter lowered, which is what this derives from Rust's own strerror text.
pub fn errno_text(e: &io::Error) -> String {
    let s = e.to_string();
    let s = match s.rfind(" (os error ") {
        Some(i) => s[..i].to_string(),
        None => s,
    };
    let mut c = s.chars();
    match c.next() {
        Some(f) => f.to_lowercase().collect::<String>() + c.as_str(),
        None => s,
    }
}

/// *os.PathError's text: "<op> <path>: <errno>".
pub fn path_err(op: &str, path: &str, e: &io::Error) -> String {
    format!("{} {}: {}", op, path, errno_text(e))
}

pub fn is_not_exist(e: &io::Error) -> bool {
    e.kind() == io::ErrorKind::NotFound
}

/// os.ReadFile with Go's error text ("open P: …" or "read P: …").
pub fn read_file(path: &str) -> Result<Vec<u8>, (String, io::Error)> {
    use std::io::Read;
    let mut f = std::fs::File::open(path).map_err(|e| (path_err("open", path, &e), e))?;
    let mut buf = Vec::new();
    f.read_to_end(&mut buf)
        .map_err(|e| (path_err("read", path, &e), e))?;
    Ok(buf)
}

/// os.MkdirAll, with its error shapes.
pub fn mkdir_all(path: &str) -> Result<(), String> {
    use std::os::unix::fs::DirBuilderExt;
    if let Ok(m) = std::fs::metadata(path) {
        if m.is_dir() {
            return Ok(());
        }
        return Err(format!("mkdir {}: not a directory", path));
    }
    let b = path.as_bytes();
    let mut i = b.len() as isize - 1;
    while i >= 0 && b[i as usize] == b'/' {
        i -= 1;
    }
    while i >= 0 && b[i as usize] != b'/' {
        i -= 1;
    }
    if i < 0 {
        i = 0;
    }
    let parent = &path[..i as usize];
    if !parent.is_empty() {
        mkdir_all(parent)?;
    }
    if let Err(e) = std::fs::DirBuilder::new().mode(0o755).create(path) {
        if let Ok(m) = std::fs::symlink_metadata(path) {
            if m.is_dir() {
                return Ok(());
            }
        }
        return Err(path_err("mkdir", path, &e));
    }
    Ok(())
}

/// os.Getwd: $PWD when it names the current directory, else getcwd(3).
pub fn getwd() -> Option<String> {
    use std::os::unix::fs::MetadataExt;
    let dot = std::fs::metadata(".").ok()?;
    if let Ok(pwd) = std::env::var("PWD") {
        if pwd.starts_with('/') {
            if let Ok(d) = std::fs::metadata(&pwd) {
                if d.dev() == dot.dev() && d.ino() == dot.ino() {
                    return Some(pwd);
                }
            }
        }
    }
    std::env::current_dir()
        .ok()
        .map(|p| p.to_string_lossy().into_owned())
}

/// A Go signal's String().
pub fn signal_name(sig: i32) -> String {
    let mac = cfg!(target_os = "macos");
    let s = match sig {
        1 => "hangup",
        2 => "interrupt",
        3 => "quit",
        4 => "illegal instruction",
        5 => "trace/breakpoint trap",
        6 => {
            if mac {
                "abort trap"
            } else {
                "aborted"
            }
        }
        8 => "floating point exception",
        9 => "killed",
        11 => "segmentation fault",
        13 => "broken pipe",
        14 => "alarm clock",
        15 => "terminated",
        10 if mac => "bus error",
        7 if !mac => "bus error",
        30 if mac => "user defined signal 1",
        31 if mac => "user defined signal 2",
        10 => "user defined signal 1",
        12 => "user defined signal 2",
        _ => return format!("signal {}", sig),
    };
    s.to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn floats_format_like_go() {
        assert_eq!(json_float(30.0), "30");
        assert_eq!(json_float(0.5), "0.5");
        assert_eq!(json_float(-0.0), "-0");
        assert_eq!(json_float(1e21), "1e+21");
        assert_eq!(json_float(1e20), "100000000000000000000");
        assert_eq!(json_float(1.5e-7), "1.5e-7");
        assert_eq!(json_float(0.000001), "0.000001");
        assert_eq!(format_g(1e6), "1e+06");
        assert_eq!(format_g(123456.0), "123456");
        assert_eq!(format_g(1234567.0), "1.234567e+06");
        assert_eq!(format_g(0.0001), "0.0001");
        assert_eq!(format_g(0.00001), "1e-05");
        assert_eq!(format_g(1.5), "1.5");
    }

    #[test]
    fn quote_matches_strconv() {
        assert_eq!(q("a\"b\\c\n"), "\"a\\\"b\\\\c\\n\"");
        assert_eq!(q("é\u{200b}"), "\"é\\u200b\"");
        assert_eq!(quote_bytes(b"a\xffb"), "\"a\\xffb\"");
        assert_eq!(quote_char(b'x'), "'x'");
        assert_eq!(quote_char(0xEF), "'ï'");
        assert_eq!(quote_char(0x80), "'\\u0080'");
        assert_eq!(quote_char(b'\''), "'\\''");
    }

    #[test]
    fn paths_clean_like_go() {
        assert_eq!(clean("a/../b/./c//"), "b/c");
        assert_eq!(clean("/../x"), "/x");
        assert_eq!(clean("../../x"), "../../x");
        assert_eq!(join(&["", "a", "", "b"]), "a/b");
        assert_eq!(join(&["", ""]), "");
        assert_eq!(dir("a/b/c.yaml"), "a/b");
        assert_eq!(dir("c.yaml"), ".");
        assert_eq!(ext("x/delivery.a.yaml"), ".yaml");
        assert_eq!(ext("x.d/file"), "");
    }

    #[test]
    fn parse_int_base_zero() {
        assert_eq!(parse_int0("2"), Ok(2));
        assert_eq!(parse_int0("0x10"), Ok(16));
        assert_eq!(parse_int0("010"), Ok(8));
        assert_eq!(parse_int0("-1_0"), Ok(-10));
        assert_eq!(parse_int0("1__0"), Err(NumErr::Syntax));
        assert_eq!(parse_int0(""), Err(NumErr::Syntax));
        assert_eq!(parse_int0("9223372036854775808"), Err(NumErr::Range));
        assert_eq!(parse_int0("-9223372036854775808"), Ok(i64::MIN));
    }

    #[test]
    fn invalid_utf8_is_one_replacement_per_byte() {
        assert_eq!(go_lossy(b"\xe2\x82a"), "\u{FFFD}\u{FFFD}a");
    }
}
