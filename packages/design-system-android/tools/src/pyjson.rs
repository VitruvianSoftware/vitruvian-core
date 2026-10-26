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

//! `json.loads` as CPython 3.12's C scanner (Modules/_json.c) reads a str:
//! what it accepts (NaN, Infinity, integers of any size up to int()'s
//! digit limit, lone surrogates from `\u` escapes, the last of two equal
//! keys), and the JSONDecodeError, with the same message and position, for
//! what it refuses. Positions count code points, as Python's do.
//!
//! serde_json reads a different language (no NaN, a 128-deep nesting
//! limit, integers past 64 bits rounded to floats, no lone surrogates) and
//! words its errors differently, so it cannot stand in for this: the port
//! keeps it as the reference the unit tests check this reader against on
//! the JSON both accept.

use crate::pyerr::Exc;
use crate::pystr::{BigInt, PyStr, MAX_STR_DIGITS};
use crate::value::{Dict, Value};

/// How deep arrays and objects may nest before the C scanner's recursion
/// guard stops it: what is left of CPython 3.12's C recursion budget (10000)
/// once gen_tokens-py's launcher (Bazel's bootstrap, runpy) and json.loads
/// have taken theirs. Measured; the parity test holds both sides of the
/// edge. (`python3 gen_tokens.py`, with no launcher, allows 9997.)
pub const MAX_DEPTH: usize = 9_994;

enum Fail {
    /// The scanner's StopIteration: no value starts here.
    NoValue(usize),
    Raise(Exc),
}

fn decode_error(text: &[u32], msg: &str, pos: usize) -> Exc {
    let nl = '\n' as u32;
    let line = text[..pos].iter().filter(|&&c| c == nl).count() + 1;
    let col = match text[..pos].iter().rposition(|&c| c == nl) {
        Some(i) => pos - i,
        None => pos + 1,
    };
    Exc::new(
        "json.decoder.JSONDecodeError",
        format!("{}: line {} column {} (char {})", msg, line, col, pos),
    )
}

struct Scanner<'a> {
    s: &'a [u32],
    depth: usize,
}

fn is_ws(c: u32) -> bool {
    matches!(c, 0x20 | 0x09 | 0x0A | 0x0D)
}

fn is_digit(c: u32) -> bool {
    (0x30..=0x39).contains(&c)
}

fn hex(c: u32) -> Option<u32> {
    char::from_u32(c).and_then(|c| c.to_digit(16))
}

impl<'a> Scanner<'a> {
    fn raise(&self, msg: &str, pos: usize) -> Fail {
        Fail::Raise(decode_error(self.s, msg, pos))
    }

    fn at(&self, i: usize) -> Option<u32> {
        self.s.get(i).copied()
    }

    fn is(&self, i: usize, c: char) -> bool {
        self.at(i) == Some(c as u32)
    }

    fn skip_ws(&self, mut i: usize) -> usize {
        while self.at(i).is_some_and(is_ws) {
            i += 1;
        }
        i
    }

    fn word(&self, i: usize, w: &str) -> bool {
        let w: Vec<u32> = w.chars().map(|c| c as u32).collect();
        self.s.len() >= i + w.len() && self.s[i..i + w.len()] == w[..]
    }

    /// scan_once_unicode: the value starting at `i`, and where it ends.
    fn scan(&mut self, i: usize) -> Result<(Value, usize), Fail> {
        let Some(c) = self.at(i) else {
            return Err(Fail::NoValue(i));
        };
        match char::from_u32(c) {
            Some('"') => {
                let (s, end) = self.string(i + 1)?;
                return Ok((Value::Str(s), end));
            }
            Some('{') => return self.nested(i, true),
            Some('[') => return self.nested(i, false),
            Some('n') if self.word(i, "null") => return Ok((Value::Null, i + 4)),
            Some('t') if self.word(i, "true") => return Ok((Value::Bool(true), i + 4)),
            Some('f') if self.word(i, "false") => return Ok((Value::Bool(false), i + 5)),
            Some('N') if self.word(i, "NaN") => return Ok((Value::Float(f64::NAN), i + 3)),
            Some('I') if self.word(i, "Infinity") => {
                return Ok((Value::Float(f64::INFINITY), i + 8))
            }
            Some('-') if self.word(i, "-Infinity") => {
                return Ok((Value::Float(f64::NEG_INFINITY), i + 9))
            }
            _ => {}
        }
        self.number(i)
    }

    fn nested(&mut self, i: usize, object: bool) -> Result<(Value, usize), Fail> {
        if self.depth >= MAX_DEPTH {
            let what = if object { "object" } else { "array" };
            return Err(Fail::Raise(Exc::recursion(&format!(
                " while decoding a JSON {} from a unicode string",
                what
            ))));
        }
        self.depth += 1;
        let r = if object {
            self.object(i + 1)
        } else {
            self.array(i + 1)
        };
        self.depth -= 1;
        r
    }

    /// _match_number_unicode.
    fn number(&self, start: usize) -> Result<(Value, usize), Fail> {
        let s = self.s;
        let end_idx = s.len() as isize - 1;
        let mut i = start;
        if s[i] == '-' as u32 {
            i += 1;
            if i as isize > end_idx {
                return Err(Fail::NoValue(start));
            }
        }
        if (0x31..=0x39).contains(&s[i]) {
            i += 1;
            while (i as isize) <= end_idx && is_digit(s[i]) {
                i += 1;
            }
        } else if s[i] == '0' as u32 {
            i += 1;
        } else {
            return Err(Fail::NoValue(start));
        }
        let mut is_float = false;
        if (i as isize) < end_idx && s[i] == '.' as u32 && is_digit(s[i + 1]) {
            is_float = true;
            i += 2;
            while (i as isize) <= end_idx && is_digit(s[i]) {
                i += 1;
            }
        }
        if (i as isize) < end_idx && (s[i] == 'e' as u32 || s[i] == 'E' as u32) {
            let e_start = i;
            i += 1;
            if (i as isize) < end_idx && (s[i] == '-' as u32 || s[i] == '+' as u32) {
                i += 1;
            }
            while (i as isize) <= end_idx && is_digit(s[i]) {
                i += 1;
            }
            if is_digit(s[i - 1]) {
                is_float = true;
            } else {
                i = e_start;
            }
        }
        let text: String = s[start..i].iter().map(|&c| c as u8 as char).collect();
        if is_float {
            return Ok((Value::Float(text.parse().unwrap()), i));
        }
        let (neg, digits) = match text.strip_prefix('-') {
            Some(d) => (true, d),
            None => (false, text.as_str()),
        };
        if digits.len() > MAX_STR_DIGITS {
            return Err(Fail::Raise(Exc::value_error(format!(
                "Exceeds the limit ({} digits) for integer string conversion: value has {} digits; use sys.set_int_max_str_digits() to increase the limit",
                MAX_STR_DIGITS,
                digits.len()
            ))));
        }
        Ok((Value::Int(BigInt::from_digits(neg, digits)), i))
    }

    /// scanstring_unicode, strict: `begin` is just past the opening quote.
    fn string(&self, begin: usize) -> Result<(PyStr, usize), Fail> {
        let s = self.s;
        let len = s.len();
        let mut out = Vec::new();
        let mut end = begin;
        loop {
            let mut next = end;
            let mut c = 0;
            while next < len {
                c = s[next];
                if c == '"' as u32 || c == '\\' as u32 {
                    break;
                }
                if c <= 0x1F {
                    return Err(self.raise("Invalid control character at", next));
                }
                next += 1;
            }
            if next == len || (c != '"' as u32 && c != '\\' as u32) {
                return Err(self.raise("Unterminated string starting at", begin - 1));
            }
            out.extend_from_slice(&s[end..next]);
            next += 1;
            if c == '"' as u32 {
                return Ok((out, next));
            }
            if next == len {
                return Err(self.raise("Unterminated string starting at", begin - 1));
            }
            let esc = s[next];
            if esc != 'u' as u32 {
                end = next + 1;
                let ch = match char::from_u32(esc) {
                    Some('"') => '"',
                    Some('\\') => '\\',
                    Some('/') => '/',
                    Some('b') => '\u{8}',
                    Some('f') => '\u{c}',
                    Some('n') => '\n',
                    Some('r') => '\r',
                    Some('t') => '\t',
                    _ => return Err(self.raise("Invalid \\escape", end - 2)),
                };
                out.push(ch as u32);
                continue;
            }
            next += 1;
            end = next + 4;
            if end >= len {
                return Err(self.raise("Invalid \\uXXXX escape", next - 1));
            }
            let mut u = 0;
            while next < end {
                let Some(d) = hex(s[next]) else {
                    return Err(self.raise("Invalid \\uXXXX escape", end - 5));
                };
                u = (u << 4) | d;
                next += 1;
            }
            if (0xD800..=0xDBFF).contains(&u) && end + 6 < len {
                let backslash = s[next] == '\\' as u32;
                next += 1;
                if backslash && s[next] == 'u' as u32 {
                    next += 1;
                    end += 6;
                    let mut u2 = 0;
                    while next < end {
                        let Some(d) = hex(s[next]) else {
                            return Err(self.raise("Invalid \\uXXXX escape", end - 5));
                        };
                        u2 = (u2 << 4) | d;
                        next += 1;
                    }
                    if (0xDC00..=0xDFFF).contains(&u2) {
                        u = 0x10000 + (((u - 0xD800) << 10) | (u2 - 0xDC00));
                    } else {
                        end -= 6;
                    }
                }
            }
            out.push(u);
        }
    }

    /// _parse_object_unicode: `i` is just past the `{`.
    fn object(&mut self, i: usize) -> Result<(Value, usize), Fail> {
        let mut d = Dict::new();
        let mut i = self.skip_ws(i);
        if !self.is(i, '}') {
            loop {
                if !self.is(i, '"') {
                    return Err(self.raise("Expecting property name enclosed in double quotes", i));
                }
                let (key, next) = self.string(i + 1)?;
                i = self.skip_ws(next);
                if !self.is(i, ':') {
                    return Err(self.raise("Expecting ':' delimiter", i));
                }
                i = self.skip_ws(i + 1);
                let (value, next) = self.scan(i)?;
                d.insert(key, value);
                i = self.skip_ws(next);
                if self.is(i, '}') {
                    break;
                }
                if !self.is(i, ',') {
                    return Err(self.raise("Expecting ',' delimiter", i));
                }
                i = self.skip_ws(i + 1);
            }
        }
        Ok((Value::Dict(d), i + 1))
    }

    /// _parse_array_unicode: `i` is just past the `[`.
    fn array(&mut self, i: usize) -> Result<(Value, usize), Fail> {
        let mut items = Vec::new();
        let mut i = self.skip_ws(i);
        if !self.is(i, ']') {
            loop {
                let (value, next) = self.scan(i)?;
                items.push(value);
                i = self.skip_ws(next);
                if self.is(i, ']') {
                    break;
                }
                if !self.is(i, ',') {
                    return Err(self.raise("Expecting ',' delimiter", i));
                }
                i = self.skip_ws(i + 1);
            }
        }
        Ok((Value::List(items), i + 1))
    }
}

/// `json.loads(text)`.
pub fn loads(text: &[u32]) -> Result<Value, Exc> {
    if text.first() == Some(&0xFEFF) {
        return Err(decode_error(
            text,
            "Unexpected UTF-8 BOM (decode using utf-8-sig)",
            0,
        ));
    }
    let mut scanner = Scanner { s: text, depth: 0 };
    let start = scanner.skip_ws(0);
    let (value, end) = match scanner.scan(start) {
        Ok(v) => v,
        Err(Fail::NoValue(at)) => return Err(decode_error(text, "Expecting value", at)),
        Err(Fail::Raise(e)) => return Err(e),
    };
    let end = scanner.skip_ws(end);
    if end != text.len() {
        return Err(decode_error(text, "Extra data", end));
    }
    Ok(value)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::pystr::{self, ps};

    fn err(t: &str) -> String {
        let e = loads(&ps(t)).unwrap_err();
        format!("{}: {}", e.class, pystr::backslashreplace(&e.msg))
    }

    #[test]
    fn errors_match_cpython() {
        assert_eq!(
            err("[1,]"),
            "json.decoder.JSONDecodeError: Expecting value: line 1 column 4 (char 3)"
        );
        assert_eq!(
            err("{\"a\":1,}"),
            "json.decoder.JSONDecodeError: Expecting property name enclosed in double quotes: line 1 column 8 (char 7)"
        );
        assert_eq!(
            err("\u{feff}{}"),
            "json.decoder.JSONDecodeError: Unexpected UTF-8 BOM (decode using utf-8-sig): line 1 column 1 (char 0)"
        );
        assert_eq!(
            err("{}\n x"),
            "json.decoder.JSONDecodeError: Extra data: line 2 column 2 (char 4)"
        );
        assert_eq!(
            err(""),
            "json.decoder.JSONDecodeError: Expecting value: line 1 column 1 (char 0)"
        );
    }

    #[test]
    fn reads_what_python_reads() {
        let v = loads(&ps(
            "[NaN, -Infinity, 1e400, 123456789012345678901234567890, \"\\ud800\"]",
        ))
        .unwrap();
        assert_eq!(
            v.repr(),
            "[nan, -inf, inf, 123456789012345678901234567890, '\\ud800']"
        );
    }

    #[test]
    fn nests_as_deep_as_python() {
        // As main does, on a stack big enough for Python's depth.
        std::thread::Builder::new()
            .stack_size(1 << 30)
            .spawn(|| {
                let deep = format!("{}{}", "[".repeat(MAX_DEPTH), "]".repeat(MAX_DEPTH));
                assert!(loads(&ps(&deep)).is_ok());
                let deeper = format!("[{}]", deep);
                assert_eq!(
                    loads(&ps(&deeper)).unwrap_err().msg,
                    ps("maximum recursion depth exceeded while decoding a JSON array from a unicode string")
                );
            })
            .unwrap()
            .join()
            .unwrap();
    }

    /// On the JSON both accept, this reader and serde_json agree (serde_json
    /// standing in for no Python, only as an independent JSON reader).
    #[test]
    fn agrees_with_serde_json() {
        fn same(ours: &Value, theirs: &serde_json::Value) -> bool {
            match (ours, theirs) {
                (Value::Null, serde_json::Value::Null) => true,
                (Value::Bool(a), serde_json::Value::Bool(b)) => a == b,
                (Value::Int(a), serde_json::Value::Number(n)) => n.to_string() == a.to_string_py(),
                (Value::Float(a), serde_json::Value::Number(n)) => n.as_f64() == Some(*a),
                (Value::Str(a), serde_json::Value::String(b)) => *a == pystr::ps(b),
                (Value::List(a), serde_json::Value::Array(b)) => {
                    a.len() == b.len() && a.iter().zip(b).all(|(x, y)| same(x, y))
                }
                (Value::Dict(a), serde_json::Value::Object(b)) => {
                    a.items().len() == b.len()
                        && a.items().iter().all(|(k, v)| {
                            b.get(&pystr::backslashreplace(k))
                                .is_some_and(|w| same(v, w))
                        })
                }
                _ => false,
            }
        }
        let tokens = include_str!("../../../design-system/src/tokens.json");
        for doc in [
            tokens,
            "{\"a\": [1, -2, 0.5, 1e3, true, false, null, \"\\u00e9\\n\\\"\"]}",
            " [ ] ",
            "{\"k\": {\"$value\": \"#ffffff\"}}",
            "\"\\ud83d\\ude00\"",
        ] {
            let ours = loads(&ps(doc)).unwrap();
            let theirs: serde_json::Value = serde_json::from_str(doc).unwrap();
            assert!(same(&ours, &theirs), "{}", doc);
        }
    }
}
