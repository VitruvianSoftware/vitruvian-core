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

//! json.loads as CPython 3.12 does it (Modules/_json.c and json/decoder.py):
//! the same values (key order kept, a repeated key's last value, NaN and
//! Infinity, lone surrogates), and when the text is not JSON, the same
//! message at the same place, because release-scope prints it. Iterative,
//! so nesting as deep as Python allows cannot overflow the stack.

use crate::pystr::PyStr;
use crate::pyval::{Dict, Exc, PyInt, PyVal};

/// Python 3.12.12 decodes 9997 nested arrays or objects from these call
/// sites and raises RecursionError on the next (measured; its C recursion
/// limit is 10000, less the frames already in use).
pub const MAX_DEPTH: usize = 9997;
/// sys.int_info.default_max_str_digits.
const MAX_INT_DIGITS: usize = 4300;

fn is_ws(c: u32) -> bool {
    c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D
}

fn decode_error(msg: &str, doc: &[u32], pos: usize) -> Exc {
    let lineno = doc[..pos].iter().filter(|&&c| c == 0x0A).count() + 1;
    let colno = match doc[..pos].iter().rposition(|&c| c == 0x0A) {
        Some(nl) => pos - nl,
        None => pos + 1,
    };
    Exc::ValueError(PyStr::from(
        format!("{}: line {} column {} (char {})", msg, lineno, colno, pos).as_str(),
    ))
}

enum Fail {
    /// StopIteration(idx): json reports it as "Expecting value".
    Stop(usize),
    Raise(Exc),
}

impl From<Exc> for Fail {
    fn from(e: Exc) -> Fail {
        Fail::Raise(e)
    }
}

/// json.loads(s) for a str.
pub fn loads(s: &[u32]) -> Result<PyVal, Exc> {
    if s.first() == Some(&0xFEFF) {
        return Err(decode_error(
            "Unexpected UTF-8 BOM (decode using utf-8-sig)",
            s,
            0,
        ));
    }
    let mut idx = 0;
    while idx < s.len() && is_ws(s[idx]) {
        idx += 1;
    }
    let (value, mut end) = match scan(s, idx) {
        Ok(found) => found,
        Err(Fail::Stop(at)) => return Err(decode_error("Expecting value", s, at)),
        Err(Fail::Raise(e)) => return Err(e),
    };
    while end < s.len() && is_ws(s[end]) {
        end += 1;
    }
    if end != s.len() {
        return Err(decode_error("Extra data", s, end));
    }
    Ok(value)
}

enum Frame {
    List(Vec<PyVal>),
    Dict(Dict, PyStr),
}

fn skip(s: &[u32], mut idx: usize) -> usize {
    while idx < s.len() && is_ws(s[idx]) {
        idx += 1;
    }
    idx
}

fn at(s: &[u32], idx: usize, c: char) -> bool {
    idx < s.len() && s[idx] == c as u32
}

/// Reads `"key" :` at `idx` (just past `{` or `,` and any space), returning
/// the key and where its value starts.
fn object_key(s: &[u32], idx: usize) -> Result<(PyStr, usize), Fail> {
    if !at(s, idx, '"') {
        return Err(Fail::Raise(decode_error(
            "Expecting property name enclosed in double quotes",
            s,
            idx,
        )));
    }
    let (key, next) = scanstring(s, idx + 1)?;
    let idx = skip(s, next);
    if !at(s, idx, ':') {
        return Err(Fail::Raise(decode_error("Expecting ':' delimiter", s, idx)));
    }
    Ok((key, skip(s, idx + 1)))
}

fn scan(s: &[u32], start: usize) -> Result<(PyVal, usize), Fail> {
    let mut stack: Vec<Frame> = Vec::new();
    let mut idx = start;
    loop {
        // Read one value at idx: a scalar, or the start of a container.
        let mut value = None;
        if idx >= s.len() {
            return Err(Fail::Stop(idx));
        }
        let c = s[idx];
        if c == '{' as u32 || c == '[' as u32 {
            let object = c == '{' as u32;
            if stack.len() + 1 > MAX_DEPTH {
                return Err(Fail::Raise(Exc::RecursionError(PyStr::from(if object {
                    "maximum recursion depth exceeded while decoding a JSON object from a unicode string"
                } else {
                    "maximum recursion depth exceeded while decoding a JSON array from a unicode string"
                }))));
            }
            let inner = skip(s, idx + 1);
            if object {
                if at(s, inner, '}') {
                    value = Some((PyVal::Dict(Dict::default()), inner + 1));
                } else {
                    let (key, next) = object_key(s, inner)?;
                    stack.push(Frame::Dict(Dict::default(), key));
                    idx = next;
                    continue;
                }
            } else if at(s, inner, ']') {
                value = Some((PyVal::List(Vec::new()), inner + 1));
            } else {
                stack.push(Frame::List(Vec::new()));
                idx = inner;
                continue;
            }
        }
        let (mut v, mut next) = match value {
            Some(found) => found,
            None => scalar(s, idx)?,
        };
        // Hand it to the container it is in, closing as many as end here.
        loop {
            let frame = match stack.last_mut() {
                None => return Ok((v, next)),
                Some(frame) => frame,
            };
            let after = skip(s, next);
            let (close, is_list) = match frame {
                Frame::List(items) => {
                    items.push(v);
                    (']', true)
                }
                Frame::Dict(d, key) => {
                    d.insert(std::mem::take(key), v);
                    ('}', false)
                }
            };
            if at(s, after, close) {
                v = match stack.pop().expect("a frame") {
                    Frame::List(items) => PyVal::List(items),
                    Frame::Dict(d, _) => PyVal::Dict(d),
                };
                next = after + 1;
                continue;
            }
            if !at(s, after, ',') {
                return Err(Fail::Raise(decode_error(
                    "Expecting ',' delimiter",
                    s,
                    after,
                )));
            }
            let following = skip(s, after + 1);
            if is_list {
                idx = following;
            } else {
                let (key, value_at) = object_key(s, following)?;
                if let Some(Frame::Dict(_, slot)) = stack.last_mut() {
                    *slot = key;
                }
                idx = value_at;
            }
            break;
        }
    }
}

fn word(s: &[u32], idx: usize, w: &str) -> bool {
    crate::pystr::starts_with_at(s, idx, w)
}

/// A string, constant or number at idx.
fn scalar(s: &[u32], idx: usize) -> Result<(PyVal, usize), Fail> {
    let len = s.len();
    match char::from_u32(s[idx]) {
        Some('"') => {
            let (text, next) = scanstring(s, idx + 1)?;
            return Ok((PyVal::Str(text), next));
        }
        Some('n') if idx + 3 < len && word(s, idx, "null") => return Ok((PyVal::None, idx + 4)),
        Some('t') if idx + 3 < len && word(s, idx, "true") => {
            return Ok((PyVal::Bool(true), idx + 4))
        }
        Some('f') if idx + 4 < len && word(s, idx, "false") => {
            return Ok((PyVal::Bool(false), idx + 5))
        }
        Some('N') if idx + 2 < len && word(s, idx, "NaN") => {
            return Ok((PyVal::Float(f64::NAN), idx + 3))
        }
        Some('I') if idx + 7 < len && word(s, idx, "Infinity") => {
            return Ok((PyVal::Float(f64::INFINITY), idx + 8))
        }
        Some('-') if idx + 8 < len && word(s, idx, "-Infinity") => {
            return Ok((PyVal::Float(f64::NEG_INFINITY), idx + 9))
        }
        _ => {}
    }
    number(s, idx)
}

fn digit(s: &[u32], idx: usize) -> bool {
    idx < s.len() && (0x30..=0x39).contains(&s[idx])
}

/// _match_number_unicode.
fn number(s: &[u32], start: usize) -> Result<(PyVal, usize), Fail> {
    let len = s.len();
    let end_idx = len as isize - 1;
    let mut idx = start;
    if s[idx] == '-' as u32 {
        idx += 1;
        if idx as isize > end_idx {
            return Err(Fail::Stop(start));
        }
    }
    if (0x31..=0x39).contains(&s[idx]) {
        idx += 1;
        while digit(s, idx) {
            idx += 1;
        }
    } else if s[idx] == '0' as u32 {
        idx += 1;
    } else {
        return Err(Fail::Stop(start));
    }
    let mut is_float = false;
    if (idx as isize) < end_idx && s[idx] == '.' as u32 && digit(s, idx + 1) {
        is_float = true;
        idx += 2;
        while digit(s, idx) {
            idx += 1;
        }
    }
    if (idx as isize) < end_idx && (s[idx] == 'e' as u32 || s[idx] == 'E' as u32) {
        let e_start = idx;
        idx += 1;
        if (idx as isize) < end_idx && (s[idx] == '-' as u32 || s[idx] == '+' as u32) {
            idx += 1;
        }
        while digit(s, idx) {
            idx += 1;
        }
        if digit(s, idx - 1) {
            is_float = true;
        } else {
            idx = e_start;
        }
    }
    let text: String = s[start..idx].iter().map(|&c| c as u8 as char).collect();
    if is_float {
        let x: f64 = text.parse().expect("a JSON number is a Rust float");
        return Ok((PyVal::Float(x), idx));
    }
    let digits = text.trim_start_matches('-').len();
    if digits > MAX_INT_DIGITS {
        return Err(Fail::Raise(Exc::ValueError(PyStr::from(
            format!(
                "Exceeds the limit ({} digits) for integer string conversion: value has {} digits; use sys.set_int_max_str_digits() to increase the limit",
                MAX_INT_DIGITS, digits
            )
            .as_str(),
        ))));
    }
    Ok((PyVal::Int(PyInt::from_decimal(&text)), idx))
}

fn hex(c: u32) -> Option<u32> {
    char::from_u32(c).and_then(|c| c.to_digit(16))
}

/// scanstring_unicode: `end` is just past the opening quote.
fn scanstring(s: &[u32], end: usize) -> Result<(PyStr, usize), Fail> {
    let len = s.len();
    let begin = end - 1;
    let mut out = PyStr::new();
    let mut end = end;
    loop {
        let mut next = end;
        let mut c = 0u32;
        while next < len {
            c = s[next];
            if c == '"' as u32 || c == '\\' as u32 {
                break;
            }
            if c <= 0x1F {
                return Err(Fail::Raise(decode_error(
                    "Invalid control character at",
                    s,
                    next,
                )));
            }
            next += 1;
        }
        if c != '"' as u32 && c != '\\' as u32 || next == len {
            return Err(Fail::Raise(decode_error(
                "Unterminated string starting at",
                s,
                begin,
            )));
        }
        out.0.extend_from_slice(&s[end..next]);
        next += 1;
        if c == '"' as u32 {
            return Ok((out, next));
        }
        if next == len {
            return Err(Fail::Raise(decode_error(
                "Unterminated string starting at",
                s,
                begin,
            )));
        }
        let e = s[next];
        if e != 'u' as u32 {
            end = next + 1;
            let ch = match char::from_u32(e) {
                Some('"') => '"' as u32,
                Some('\\') => '\\' as u32,
                Some('/') => '/' as u32,
                Some('b') => 0x08,
                Some('f') => 0x0C,
                Some('n') => 0x0A,
                Some('r') => 0x0D,
                Some('t') => 0x09,
                _ => return Err(Fail::Raise(decode_error("Invalid \\escape", s, end - 2))),
            };
            out.push(ch);
            continue;
        }
        next += 1;
        end = next + 4;
        if end >= len {
            return Err(Fail::Raise(decode_error(
                "Invalid \\uXXXX escape",
                s,
                next - 1,
            )));
        }
        let mut ch = 0u32;
        while next < end {
            match hex(s[next]) {
                Some(d) => ch = (ch << 4) | d,
                None => {
                    return Err(Fail::Raise(decode_error(
                        "Invalid \\uXXXX escape",
                        s,
                        end - 5,
                    )))
                }
            }
            next += 1;
        }
        if (0xD800..=0xDBFF).contains(&ch)
            && end + 6 < len
            && s[next] == '\\' as u32
            && s[next + 1] == 'u' as u32
        {
            next += 2;
            let mut c2 = 0u32;
            end += 6;
            while next < end {
                match hex(s[next]) {
                    Some(d) => c2 = (c2 << 4) | d,
                    None => {
                        return Err(Fail::Raise(decode_error(
                            "Invalid \\uXXXX escape",
                            s,
                            end - 5,
                        )))
                    }
                }
                next += 1;
            }
            if (0xDC00..=0xDFFF).contains(&c2) {
                ch = 0x10000 + (((ch - 0xD800) << 10) | (c2 - 0xDC00));
            } else {
                end -= 6;
            }
        }
        out.push(ch);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::pystr::cps;

    fn err(text: &str) -> String {
        loads(&cps(text)).unwrap_err().message().lossy()
    }

    #[test]
    fn errors_read_like_pythons() {
        assert_eq!(err(""), "Expecting value: line 1 column 1 (char 0)");
        assert_eq!(
            err("{"),
            "Expecting property name enclosed in double quotes: line 1 column 2 (char 1)"
        );
        assert_eq!(err("[1,]"), "Expecting value: line 1 column 4 (char 3)");
        assert_eq!(
            err("{\"a\" 1}"),
            "Expecting ':' delimiter: line 1 column 6 (char 5)"
        );
        assert_eq!(
            err("[1 2]"),
            "Expecting ',' delimiter: line 1 column 4 (char 3)"
        );
        assert_eq!(
            err("\"ab"),
            "Unterminated string starting at: line 1 column 1 (char 0)"
        );
        assert_eq!(err("{}\n x"), "Extra data: line 2 column 2 (char 4)");
        assert_eq!(
            err("\u{feff}{}"),
            "Unexpected UTF-8 BOM (decode using utf-8-sig): line 1 column 1 (char 0)"
        );
    }

    #[test]
    fn values_are_pythons() {
        let v = loads(&cps(
            "{\"b\": 1, \"a\": [true, null, 1.5, NaN, -0], \"b\": \"\\ud83d\\ude00\\ud800\"}",
        ))
        .unwrap();
        assert_eq!(
            v.repr().lossy(),
            "{'b': '\u{1f600}\\ud800', 'a': [True, None, 1.5, nan, 0]}"
        );
    }

    #[test]
    fn nesting_stops_where_python_does() {
        let deep = |n: usize| format!("{}{}", "[".repeat(n), "]".repeat(n));
        // Forgotten, not dropped: dropping it recurses as deep as it nests.
        std::mem::forget(loads(&cps(&deep(MAX_DEPTH))).unwrap());
        assert!(matches!(
            loads(&cps(&deep(MAX_DEPTH + 1))),
            Err(Exc::RecursionError(_))
        ));
    }
}
