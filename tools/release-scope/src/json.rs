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

//! CPython 3.12 `json.loads` adapter over `vitruvian_pycompat::json`.
//!
//! Keeps release-scope's `PyVal`/`PyStr` (preserving lone surrogates) and maps
//! `JsonError` into the exact `Exc` class and message CPython 3.12 produces.

use crate::pystr::PyStr;
use crate::pyval::{Dict, Exc, PyInt, PyVal};
use vitruvian_pycompat::json::{
    loads_codepoints, CodepointLoadOptions, CodepointValue, JsonError, JsonErrorKind,
    CPYTHON_312_MAX_DEPTH, DEFAULT_INT_MAX_STR_DIGITS,
};

/// CPython 3.12.x decodes 9997 nested arrays or objects from these call sites
/// and raises RecursionError on 9998.
pub const MAX_DEPTH: usize = CPYTHON_312_MAX_DEPTH;

enum ConvertFrame {
    List {
        out: Vec<PyVal>,
        rem: std::vec::IntoIter<CodepointValue>,
    },
    Dict {
        out: Vec<(PyStr, PyVal)>,
        key: PyStr,
        rem: std::vec::IntoIter<(Vec<u32>, CodepointValue)>,
    },
}

fn convert_value(mut current: CodepointValue) -> PyVal {
    let mut stack: Vec<ConvertFrame> = Vec::new();
    loop {
        let mut produced = match &mut current {
            CodepointValue::Null => PyVal::None,
            CodepointValue::Bool(b) => PyVal::Bool(*b),
            CodepointValue::Int(text) => PyVal::Int(PyInt::from_decimal(text)),
            CodepointValue::Float(x) => PyVal::Float(*x),
            CodepointValue::Str(cps) => PyVal::Str(PyStr(std::mem::take(cps))),
            CodepointValue::Arr(items) => {
                let mut iter = std::mem::take(items).into_iter();
                match iter.next() {
                    None => PyVal::List(Vec::new()),
                    Some(first) => {
                        stack.push(ConvertFrame::List {
                            out: Vec::with_capacity(iter.len() + 1),
                            rem: iter,
                        });
                        current = first;
                        continue;
                    }
                }
            }
            CodepointValue::Obj(entries) => {
                let mut iter = std::mem::take(entries).into_iter();
                match iter.next() {
                    None => PyVal::Dict(Dict::default()),
                    Some((key, first)) => {
                        stack.push(ConvertFrame::Dict {
                            out: Vec::with_capacity(iter.len() + 1),
                            key: PyStr(key),
                            rem: iter,
                        });
                        current = first;
                        continue;
                    }
                }
            }
        };

        loop {
            match stack.last_mut() {
                None => return produced,
                Some(ConvertFrame::List { out, rem }) => {
                    out.push(produced);
                    if let Some(next) = rem.next() {
                        current = next;
                        break;
                    }
                    let Some(ConvertFrame::List { out, .. }) = stack.pop() else {
                        unreachable!();
                    };
                    produced = PyVal::List(out);
                }
                Some(ConvertFrame::Dict { out, key, rem }) => {
                    out.push((std::mem::take(key), produced));
                    if let Some((next_key, next_val)) = rem.next() {
                        *key = PyStr(next_key);
                        current = next_val;
                        break;
                    }
                    let Some(ConvertFrame::Dict { out, .. }) = stack.pop() else {
                        unreachable!();
                    };
                    produced = PyVal::Dict(Dict(out));
                }
            }
        }
    }
}

fn convert_error(err: JsonError) -> Exc {
    match err.kind() {
        JsonErrorKind::Decode => Exc::ValueError(PyStr::from(err.python_str().as_str())),
        JsonErrorKind::IntDigitLimit => Exc::ValueError(PyStr::from(err.msg.as_str())),
        JsonErrorKind::Recursion => Exc::RecursionError(PyStr::from(
            err.recursion_message().unwrap_or(err.msg.as_str()),
        )),
    }
}

/// json.loads(s) for a str.
pub fn loads(s: &[u32]) -> Result<PyVal, Exc> {
    let opts = CodepointLoadOptions {
        max_depth: Some(CPYTHON_312_MAX_DEPTH),
        max_int_digits: Some(DEFAULT_INT_MAX_STR_DIGITS),
    };
    match loads_codepoints(s, &opts) {
        Ok(value) => Ok(convert_value(value)),
        Err(err) => Err(convert_error(err)),
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

    /// Test-only copy of the pre-refactor release-scope JSON parser from HEAD
    /// (`tools/release-scope/src/json.rs`), used as the differential oracle.
    mod legacy_release_scope_parser {
        use crate::pystr::PyStr;
        use crate::pyval::{Dict, Exc, PyInt, PyVal};

        pub const MAX_DEPTH: usize = 9997;
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
            Stop(usize),
            Raise(Exc),
        }

        impl From<Exc> for Fail {
            fn from(e: Exc) -> Fail {
                Fail::Raise(e)
            }
        }

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

        fn scalar(s: &[u32], idx: usize) -> Result<(PyVal, usize), Fail> {
            let len = s.len();
            match char::from_u32(s[idx]) {
                Some('"') => {
                    let (text, next) = scanstring(s, idx + 1)?;
                    return Ok((PyVal::Str(text), next));
                }
                Some('n') if idx + 3 < len && word(s, idx, "null") => {
                    return Ok((PyVal::None, idx + 4))
                }
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
    }

    const CPYTHON_312_PARITY_JSON: &str = include_str!("../testdata/cpython312_json_parity.json");

    fn bs(template: &str) -> String {
        const BS: char = '\\';
        assert!(
            !template.contains(BS),
            "build escapes in code with '|' instead of literal backslashes: {template:?}"
        );
        template.replace('|', &BS.to_string())
    }

    fn parse_decode_location(msg: &str) -> Option<(usize, usize, usize)> {
        let (_, tail) = msg.rsplit_once(": line ")?;
        let (line_s, rest) = tail.split_once(" column ")?;
        let (col_s, pos_tail) = rest.split_once(" (char ")?;
        let pos_s = pos_tail.strip_suffix(')')?;
        Some((
            line_s.parse().ok()?,
            col_s.parse().ok()?,
            pos_s.parse().ok()?,
        ))
    }

    struct Rng(u64);

    impl Rng {
        fn next(&mut self) -> u64 {
            let mut x = self.0;
            x ^= x << 13;
            x ^= x >> 7;
            x ^= x << 17;
            self.0 = x;
            x
        }

        fn bound(&mut self, n: usize) -> usize {
            (self.next() % (n as u64)) as usize
        }
    }

    fn push_str_cps(out: &mut Vec<u32>, s: &str) {
        out.extend(s.chars().map(|c| c as u32));
    }

    fn rand_ws(rng: &mut Rng, out: &mut Vec<u32>) {
        match rng.bound(6) {
            0 | 1 => {}
            2 => out.push(0x20),
            3 => push_str_cps(out, " \t"),
            4 => push_str_cps(out, "\n  "),
            _ => push_str_cps(out, "\r\n\t "),
        }
    }

    fn rand_string(rng: &mut Rng, out: &mut Vec<u32>) {
        out.push('"' as u32);
        let len = rng.bound(6);
        for _ in 0..len {
            match rng.bound(16) {
                0..=4 => out.push('a' as u32 + rng.bound(6) as u32),
                5 => push_str_cps(out, "\u{00e9}"),
                6 => push_str_cps(out, "\u{1f600}"),
                7 => push_str_cps(out, &bs("|ud83d|ude00")),
                8 => push_str_cps(out, &bs("|ud800")),
                9 => push_str_cps(out, &bs("|udfff")),
                10 => push_str_cps(out, &bs("|ud800|ud800|udc00")),
                11 => out.push(0xD800 + rng.bound(0x800) as u32),
                12 => push_str_cps(out, &bs("|n|t|/")),
                13 => push_str_cps(out, &bs("||")),
                14 => push_str_cps(out, &bs("|\"")),
                _ => push_str_cps(out, &bs("|u0041")),
            }
        }
        out.push('"' as u32);
    }

    fn rand_scalar(rng: &mut Rng, out: &mut Vec<u32>) {
        match rng.bound(16) {
            0 => push_str_cps(out, "null"),
            1 => push_str_cps(out, "true"),
            2 => push_str_cps(out, "false"),
            3 => push_str_cps(out, "0"),
            4 => push_str_cps(out, "-0"),
            5 => push_str_cps(
                out,
                &format!("{}", (rng.next() % 1_000_000) as i64 - 500_000),
            ),
            6 => push_str_cps(out, "900719925474099312345678901234567890"),
            7 => push_str_cps(out, "-0.0"),
            8 => push_str_cps(out, "1.25"),
            9 => push_str_cps(out, "1.5e-07"),
            10 => push_str_cps(out, "1E+16"),
            11 => push_str_cps(out, "NaN"),
            12 => push_str_cps(out, "Infinity"),
            13 => push_str_cps(out, "-Infinity"),
            _ => rand_string(rng, out),
        }
    }

    fn gen_valid_doc(rng: &mut Rng, target_depth: usize) -> Vec<u32> {
        let mut out = Vec::new();
        let mut closers: Vec<u32> = Vec::new();
        let mut cur_depth = 0usize;
        rand_ws(rng, &mut out);
        while cur_depth < target_depth {
            if rng.bound(2) == 0 {
                out.push('[' as u32);
                rand_ws(rng, &mut out);
                if rng.bound(4) == 0 {
                    rand_scalar(rng, &mut out);
                    rand_ws(rng, &mut out);
                    out.push(',' as u32);
                    rand_ws(rng, &mut out);
                }
                closers.push(']' as u32);
            } else {
                out.push('{' as u32);
                rand_ws(rng, &mut out);
                if rng.bound(3) == 0 {
                    // Duplicate key candidate before the deeper nested branch.
                    let key_tag = rng.bound(3);
                    let dup_key = match key_tag {
                        0 => "\"dup\"".to_string(),
                        1 => bs("\"|ud800\""),
                        _ => "\"k\"".to_string(),
                    };
                    push_str_cps(&mut out, &dup_key);
                    rand_ws(rng, &mut out);
                    out.push(':' as u32);
                    rand_ws(rng, &mut out);
                    rand_scalar(rng, &mut out);
                    rand_ws(rng, &mut out);
                    out.push(',' as u32);
                    rand_ws(rng, &mut out);
                    push_str_cps(&mut out, &dup_key);
                } else {
                    rand_string(rng, &mut out);
                }
                rand_ws(rng, &mut out);
                out.push(':' as u32);
                rand_ws(rng, &mut out);
                closers.push('}' as u32);
            }
            cur_depth += 1;
        }
        if target_depth > 0 && rng.bound(5) == 0 {
            if closers.last() == Some(&(']' as u32)) {
                out.push('[' as u32);
                rand_ws(rng, &mut out);
                out.push(']' as u32);
            } else {
                out.push('{' as u32);
                rand_ws(rng, &mut out);
                out.push('}' as u32);
            }
        } else {
            rand_scalar(rng, &mut out);
        }
        for closer in closers.into_iter().rev() {
            rand_ws(rng, &mut out);
            if rng.bound(5) == 0 {
                out.push(',' as u32);
                rand_ws(rng, &mut out);
                if closer == '}' as u32 {
                    rand_string(rng, &mut out);
                    rand_ws(rng, &mut out);
                    out.push(':' as u32);
                    rand_ws(rng, &mut out);
                }
                rand_scalar(rng, &mut out);
                rand_ws(rng, &mut out);
            }
            out.push(closer);
        }
        rand_ws(rng, &mut out);
        out
    }

    fn mutate_input(rng: &mut Rng, base: &[u32]) -> Vec<u32> {
        let mut doc = base.to_vec();
        if doc.is_empty() {
            return doc;
        }
        match rng.bound(6) {
            0 => {
                // Truncate at a random point.
                let cut = rng.bound(doc.len());
                doc.truncate(cut);
            }
            1 => {
                // Replace or insert random special/control/surrogate codepoint.
                let pool: [u32; 17] = [
                    0x00,
                    0x0A,
                    0x0D,
                    0x09,
                    0x1F,
                    '"' as u32,
                    '\\' as u32,
                    ',' as u32,
                    ':' as u32,
                    '[' as u32,
                    ']' as u32,
                    '{' as u32,
                    '}' as u32,
                    'x' as u32,
                    'u' as u32,
                    0xD800,
                    0xDFFF,
                ];
                let idx = rng.bound(doc.len());
                let ch = pool[rng.bound(pool.len())];
                if rng.bound(2) == 0 {
                    doc[idx] = ch;
                } else {
                    doc.insert(idx, ch);
                }
            }
            2 => {
                // Delete a code point.
                let idx = rng.bound(doc.len());
                doc.remove(idx);
            }
            3 => {
                // Trailing extra data.
                push_str_cps(&mut doc, " extra");
            }
            4 => {
                // Leading BOM.
                doc.insert(0, 0xFEFF);
            }
            _ => {
                // Bad escape or truncated \uXXXX.
                let snippets = [
                    bs("\"|x\""),
                    bs("\"|u12\""),
                    bs("\"|u0041"),
                    bs("\"|ud800|u12\""),
                    bs("\"|ud800|udc00"),
                    "[1, ]".to_string(),
                    "{\"a\": 1,}".to_string(),
                    "{\"a\" 1}".to_string(),
                    "[1 2]".to_string(),
                    "\"a\nb\"".to_string(),
                ];
                let chosen = &snippets[rng.bound(snippets.len())];
                doc = cps(chosen);
            }
        }
        doc
    }

    #[test]
    fn differential_against_legacy_parser() {
        let mut rng = Rng(0x9E37_79B9_7F4A_7C15);
        let mut inputs: Vec<Vec<u32>> = Vec::with_capacity(6200);

        // Targeted valid & malformed edge cases (big ints, BOM, NaN/Inf, dups, surrogates, whitespace).
        for s in [
            "",
            "   \t\r\n  ",
            "\u{feff}",
            "\u{feff}{}",
            " \u{feff}{}",
            "NaN",
            "Infinity",
            "-Infinity",
            "[NaN, Infinity, -Infinity]",
            "{\"a\": 1, \"b\": 2, \"a\": 3}",
            &bs("{\"|ud800\": 1, \"b\": 2, \"|ud800\": 3, \"c\": \"|ud83d|ude00|ud800|ud800|udc00\"}"),
            &format!("1{}", "0".repeat(4298)),
            &format!("1{}", "0".repeat(4299)),
            &format!("-{}", "9".repeat(4300)),
            &format!("1{}", "0".repeat(4300)),
            &format!("-{}", "9".repeat(4301)),
            &format!("[1, 1{}]", "0".repeat(4300)),
            &format!("{{\"k\": 1{}}}", "0".repeat(4300)),
            &format!("1{}.0", "0".repeat(4300)),
            &format!("1{} x", "0".repeat(4300)),
            &bs("\"|u"),
            &bs("\"|u0041"),
            &bs("\"|ud800|u0041"),
            &bs("\"|ud800|udc00"),
            &bs("\"|ud800|udc00\""),
            &bs("\"|ud800|u0041\""),
        ] {
            inputs.push(cps(s));
        }
        // Raw literal lone surrogates inside and outside quotes.
        inputs.push(vec![0xD800]);
        inputs.push(vec!['"' as u32, 0xD800, '"' as u32]);
        inputs.push(vec![
            '{' as u32, '"' as u32, 0xD800, '"' as u32, ':' as u32, '1' as u32, '}' as u32,
        ]);

        // 2,800 random valid documents across nesting depths 0..=60.
        for i in 0..2800 {
            let depth = if i % 7 == 0 {
                55 + (i % 6)
            } else {
                rng.bound(61)
            };
            inputs.push(gen_valid_doc(&mut rng, depth));
        }

        // 3,200 random malformed inputs by mutating/truncating generated docs.
        for _ in 0..3200 {
            let depth = rng.bound(25);
            let base = gen_valid_doc(&mut rng, depth);
            inputs.push(mutate_input(&mut rng, &base));
        }

        let mut total = 0usize;
        let mut valid = 0usize;
        let mut malformed = 0usize;
        let mut mismatches: Vec<String> = Vec::new();

        for input in &inputs {
            total += 1;
            let new_res = loads(input);
            let old_res = legacy_release_scope_parser::loads(input);
            match (new_res, old_res) {
                (Ok(nv), Ok(ov)) => {
                    valid += 1;
                    let n_repr = nv.repr();
                    let o_repr = ov.repr();
                    if n_repr != o_repr || !nv.py_eq(&ov) {
                        mismatches.push(format!(
                            "value mismatch on {:?}: new={} old={}",
                            PyStr(input.clone()).repr().lossy(),
                            n_repr.lossy(),
                            o_repr.lossy()
                        ));
                    }
                }
                (Err(ne), Err(oe)) => {
                    malformed += 1;
                    let n_msg = ne.message();
                    let o_msg = oe.message();
                    let n_loc = parse_decode_location(&n_msg.lossy());
                    let o_loc = parse_decode_location(&o_msg.lossy());
                    if ne.class() != oe.class() || n_msg != o_msg || n_loc != o_loc {
                        mismatches.push(format!(
                            "error mismatch on {:?}: new=({}, {:?}, {:?}) old=({}, {:?}, {:?})",
                            PyStr(input.clone()).repr().lossy(),
                            ne.class(),
                            n_msg.lossy(),
                            n_loc,
                            oe.class(),
                            o_msg.lossy(),
                            o_loc
                        ));
                    } else if let Some((line, col, _)) = n_loc {
                        let raw_err = loads_codepoints(
                            input,
                            &CodepointLoadOptions {
                                max_depth: Some(CPYTHON_312_MAX_DEPTH),
                                max_int_digits: Some(DEFAULT_INT_MAX_STR_DIGITS),
                            },
                        )
                        .unwrap_err();
                        if (raw_err.line, raw_err.col) != (line, col)
                            || raw_err.python_str() != n_msg.lossy()
                        {
                            mismatches.push(format!(
                                "raw JsonError mismatch on {:?}: raw=({},{},{:?}) mapped={:?}",
                                PyStr(input.clone()).repr().lossy(),
                                raw_err.line,
                                raw_err.col,
                                raw_err.python_str(),
                                n_msg.lossy()
                            ));
                        }
                    }
                }
                (new_r, old_r) => {
                    mismatches.push(format!(
                        "accept/reject mismatch on {:?}: new={:?} old={:?}",
                        PyStr(input.clone()).repr().lossy(),
                        new_r.map(|v| v.repr().lossy()),
                        old_r.map(|v| v.repr().lossy())
                    ));
                }
            }
        }

        eprintln!(
            "DIFFERENTIAL_JSON total={} valid={} malformed={} mismatches={}",
            total,
            valid,
            malformed,
            mismatches.len()
        );
        assert!(
            total >= 5000,
            "expected >= 5000 differential cases, got {total}"
        );
        assert!(valid > 0 && malformed > 0);
        assert!(
            mismatches.is_empty(),
            "differential mismatches ({}):\n{}",
            mismatches.len(),
            mismatches
                .iter()
                .take(10)
                .cloned()
                .collect::<Vec<_>>()
                .join("\n")
        );
    }

    #[test]
    fn cpython_312_malformed_parity() {
        let new_fixture = loads(&cps(CPYTHON_312_PARITY_JSON)).unwrap();
        let old_fixture =
            legacy_release_scope_parser::loads(&cps(CPYTHON_312_PARITY_JSON)).unwrap();
        assert_eq!(new_fixture.repr(), old_fixture.repr());

        let cases = new_fixture.index("cases").unwrap().iterate().unwrap();
        assert!(
            cases.len() >= 150,
            "expected >= 150 CPython 3.12 parity cases, got {}",
            cases.len()
        );

        let mut seen = std::collections::HashSet::new();
        for case in &cases {
            let input_str = case.index("input").unwrap();
            let input_cps = input_str.as_str().unwrap().cps();
            assert!(
                seen.insert(input_cps.to_vec()),
                "duplicate parity case {:?}",
                case.index("repr").unwrap().repr().lossy()
            );
            let py_class = case.index("class").unwrap().as_str().unwrap().lossy();
            let want_class = match py_class.as_str() {
                "JSONDecodeError" | "ValueError" => "ValueError",
                "RecursionError" => "RecursionError",
                other => panic!("unexpected exception class {other:?}"),
            };
            let want_msg = case.index("message").unwrap().as_str().unwrap().lossy();

            let new_err = loads(input_cps).unwrap_err();
            let old_err = legacy_release_scope_parser::loads(input_cps).unwrap_err();
            assert_eq!(new_err.class(), want_class, "new class for {want_msg}");
            assert_eq!(old_err.class(), want_class, "old class for {want_msg}");
            assert_eq!(new_err.message().lossy(), want_msg);
            assert_eq!(old_err.message().lossy(), want_msg);
        }
        eprintln!(
            "CPYTHON_312_PARITY_CASES count={} version={}",
            cases.len(),
            new_fixture
                .index("python_version")
                .unwrap()
                .as_str()
                .unwrap()
                .lossy()
                .lines()
                .next()
                .unwrap_or("")
        );
    }

    #[test]
    fn depth_boundary_9997_and_9998_on_32mib_thread() {
        let handle = std::thread::Builder::new()
            .stack_size(32 * 1024 * 1024)
            .spawn(|| {
                assert_eq!(MAX_DEPTH, 9997);
                assert_eq!(legacy_release_scope_parser::MAX_DEPTH, 9997);

                let arr_9997 = format!("{}{}", "[".repeat(9997), "]".repeat(9997));
                let arr_9997_scalar = format!("{}1{}", "[".repeat(9997), "]".repeat(9997));
                for doc in [&arr_9997, &arr_9997_scalar] {
                    let nv = loads(&cps(doc)).unwrap();
                    let ov = legacy_release_scope_parser::loads(&cps(doc)).unwrap();
                    assert!(matches!(nv, PyVal::List(_)));
                    assert!(matches!(ov, PyVal::List(_)));
                    std::mem::forget((nv, ov));
                }

                let arr_9998 = format!("{}{}", "[".repeat(9998), "]".repeat(9998));
                let arr_9998_scalar = format!("{}1{}", "[".repeat(9998), "]".repeat(9998));
                let want_arr =
                    "maximum recursion depth exceeded while decoding a JSON array from a unicode string";
                for doc in [&arr_9998, &arr_9998_scalar] {
                    let ne = loads(&cps(doc)).unwrap_err();
                    let oe = legacy_release_scope_parser::loads(&cps(doc)).unwrap_err();
                    assert_eq!(ne.class(), "RecursionError");
                    assert_eq!(oe.class(), "RecursionError");
                    assert_eq!(ne.message().lossy(), want_arr);
                    assert_eq!(oe.message().lossy(), want_arr);
                }

                let obj_9997_scalar = format!("{}1{}", "{\"a\":".repeat(9997), "}".repeat(9997));
                let obj_9997_empty = format!("{}{{}}{}", "{\"a\":".repeat(9996), "}".repeat(9996));
                for doc in [&obj_9997_scalar, &obj_9997_empty] {
                    let nv = loads(&cps(doc)).unwrap();
                    let ov = legacy_release_scope_parser::loads(&cps(doc)).unwrap();
                    assert!(matches!(nv, PyVal::Dict(_)));
                    assert!(matches!(ov, PyVal::Dict(_)));
                    std::mem::forget((nv, ov));
                }

                let obj_9998_scalar = format!("{}1{}", "{\"a\":".repeat(9998), "}".repeat(9998));
                let obj_9998_empty = format!("{}{{}}{}", "{\"a\":".repeat(9997), "}".repeat(9997));
                let want_obj =
                    "maximum recursion depth exceeded while decoding a JSON object from a unicode string";
                for doc in [&obj_9998_scalar, &obj_9998_empty] {
                    let ne = loads(&cps(doc)).unwrap_err();
                    let oe = legacy_release_scope_parser::loads(&cps(doc)).unwrap_err();
                    assert_eq!(ne.class(), "RecursionError");
                    assert_eq!(oe.class(), "RecursionError");
                    assert_eq!(ne.message().lossy(), want_obj);
                    assert_eq!(oe.message().lossy(), want_obj);
                }

                let mixed_obj = format!("{}{{}}{}", "[".repeat(9997), "]".repeat(9997));
                assert_eq!(loads(&cps(&mixed_obj)).unwrap_err().message().lossy(), want_obj);
                let mixed_arr = format!("{}[]{}", "{\"a\":".repeat(9997), "}".repeat(9997));
                assert_eq!(loads(&cps(&mixed_arr)).unwrap_err().message().lossy(), want_arr);
            })
            .unwrap();
        handle.join().unwrap();
    }

    #[test]
    fn targeted_edge_cases_bom_nan_inf_dups_bigint_escapes() {
        let bom = loads(&cps("\u{feff}{}")).unwrap_err();
        let bom_old = legacy_release_scope_parser::loads(&cps("\u{feff}{}")).unwrap_err();
        assert_eq!(bom, bom_old);
        assert_eq!(
            bom.message().lossy(),
            "Unexpected UTF-8 BOM (decode using utf-8-sig): line 1 column 1 (char 0)"
        );

        let specials = loads(&cps(
            r#"{"x": NaN, "y": Infinity, "z": -Infinity, "x": 42}"#,
        ))
        .unwrap();
        let specials_old = legacy_release_scope_parser::loads(&cps(
            r#"{"x": NaN, "y": Infinity, "z": -Infinity, "x": 42}"#,
        ))
        .unwrap();
        assert_eq!(specials.repr(), specials_old.repr());
        assert_eq!(specials.repr().lossy(), "{'x': 42, 'y': inf, 'z': -inf}");

        let ok_4300 = format!("-{}", "9".repeat(4300));
        assert_eq!(
            loads(&cps(&ok_4300)).unwrap().repr(),
            legacy_release_scope_parser::loads(&cps(&ok_4300))
                .unwrap()
                .repr()
        );

        let bad_4301 = format!("1{}", "0".repeat(4300));
        let ne = loads(&cps(&bad_4301)).unwrap_err();
        let oe = legacy_release_scope_parser::loads(&cps(&bad_4301)).unwrap_err();
        assert_eq!(ne, oe);
        assert_eq!(ne.class(), "ValueError");
        assert_eq!(
            ne.message().lossy(),
            "Exceeds the limit (4300 digits) for integer string conversion: value has 4301 digits; use sys.set_int_max_str_digits() to increase the limit"
        );

        let float_4301 = format!("{bad_4301}.0");
        assert_eq!(loads(&cps(&float_4301)).unwrap().repr().lossy(), "inf");

        for esc in [
            bs("\"|u"),
            bs("\"|u12"),
            bs("\"|u0041"),
            bs("\"|ud800|u12\""),
            bs("\"|ud800|udc00"),
            bs("\"ab|"),
        ] {
            let n = loads(&cps(&esc)).unwrap_err();
            let o = legacy_release_scope_parser::loads(&cps(&esc)).unwrap_err();
            assert_eq!(n, o, "escape mismatch for {esc:?}");
        }
    }

    #[test]
    fn lone_surrogate_output_matches_legacy() {
        // 1. Lone surrogate in a printed value: PR title flows through scope::report
        //    and triggers UnicodeEncodeError when encoding stdout under Errors::Strict.
        let pr_raw = bs(
            r#"{"title": "chore(x): bad |ud800 title", "body": "", "user": {"login": "a", "type": "User"}, "head": {"ref": "b"}}"#,
        );
        let commits_raw = bs(r#"["chore(x): bad |ud800 title"]"#);
        let new_pr = loads(&cps(&pr_raw)).unwrap();
        let old_pr = legacy_release_scope_parser::loads(&cps(&pr_raw)).unwrap();
        let new_commits = loads(&cps(&commits_raw)).unwrap();
        let old_commits = legacy_release_scope_parser::loads(&cps(&commits_raw)).unwrap();
        assert_eq!(new_pr.repr(), old_pr.repr());
        assert_eq!(new_pr.repr().lossy(), old_pr.repr().lossy());
        assert_eq!(new_commits.repr(), old_commits.repr());

        let new_pull = crate::scope::pull_request(&new_pr, &new_commits, vec![]).unwrap();
        let old_pull = crate::scope::pull_request(&old_pr, &old_commits, vec![]).unwrap();
        let new_verdict = crate::scope::judge(&new_pull, &[], &[]).unwrap();
        let old_verdict = crate::scope::judge(&old_pull, &[], &[]).unwrap();
        let new_report = crate::scope::report(&new_verdict).unwrap();
        let old_report = crate::scope::report(&old_verdict).unwrap();
        assert_eq!(new_report, old_report);
        assert_eq!(new_report.lossy(), old_report.lossy());

        let new_enc_err =
            crate::pystr::encode_utf8(new_report.cps(), crate::pystr::Errors::Strict).unwrap_err();
        let old_enc_err =
            crate::pystr::encode_utf8(old_report.cps(), crate::pystr::Errors::Strict).unwrap_err();
        assert_eq!(new_enc_err, old_enc_err);
        assert!(
            new_enc_err.contains("surrogates not allowed"),
            "unexpected encode error: {new_enc_err}"
        );

        // 2. Lone surrogate in a dict key: preserved in order, deduplication, aliases error,
        //    and component name printed into report().
        let dict_raw = bs(r#"{"|ud800": 1, "b": 2, "|ud800": 3, "|ud801": 4}"#);
        let new_dict = loads(&cps(&dict_raw)).unwrap();
        let old_dict = legacy_release_scope_parser::loads(&cps(&dict_raw)).unwrap();
        assert_eq!(new_dict.repr(), old_dict.repr());
        assert_eq!(
            new_dict.repr().lossy(),
            "{'\\ud800': 3, 'b': 2, '\\ud801': 4}"
        );

        let aliases_raw = bs(r#"{"aliases": {"scope-|ud800": {"components": ["missing"]}}}"#);
        let new_aliases = crate::scope::load_aliases(&loads(&cps(&aliases_raw)).unwrap()).unwrap();
        let old_aliases = crate::scope::load_aliases(
            &legacy_release_scope_parser::loads(&cps(&aliases_raw)).unwrap(),
        )
        .unwrap();
        let new_alias_err = crate::scope::judge(&new_pull, &[], &new_aliases).unwrap_err();
        let old_alias_err = crate::scope::judge(&old_pull, &[], &old_aliases).unwrap_err();
        assert_eq!(new_alias_err, old_alias_err);
        assert_eq!(
            new_alias_err.message().lossy(),
            "aliases.json: scope-\\ud800 means missing, which no release-please config has"
        );

        let cfg_raw = bs(r#"{"packages": {"apps/|ud800": {}}}"#);
        let new_cfg = loads(&cps(&cfg_raw)).unwrap();
        let old_cfg = legacy_release_scope_parser::loads(&cps(&cfg_raw)).unwrap();
        assert_eq!(new_cfg.repr(), old_cfg.repr());
        let new_comps = crate::scope::load_components(vec![(
            PyStr::from("release-please-config.json"),
            new_cfg,
        )])
        .unwrap();
        let old_comps = crate::scope::load_components(vec![(
            PyStr::from("release-please-config.json"),
            old_cfg,
        )])
        .unwrap();
        let new_key_pull = crate::scope::PullRequest {
            title: PyVal::str("feat: change"),
            body: PyVal::str(""),
            files: vec![PyStr(
                cps("apps/")
                    .into_iter()
                    .chain([0xD800])
                    .chain(cps("/f.txt"))
                    .collect(),
            )],
            commits: vec![PyVal::str("feat: change")],
            author: PyVal::str("a"),
            author_type: PyVal::str("User"),
            head_ref: PyVal::str("b"),
        };
        let new_key_verdict = crate::scope::judge(&new_key_pull, &new_comps, &[]).unwrap();
        let old_key_verdict = crate::scope::judge(&new_key_pull, &old_comps, &[]).unwrap();
        let new_key_report = crate::scope::report(&new_key_verdict).unwrap();
        let old_key_report = crate::scope::report(&old_key_verdict).unwrap();
        assert_eq!(new_key_report, old_key_report);
        assert_eq!(
            crate::pystr::encode_utf8(new_key_report.cps(), crate::pystr::Errors::Strict)
                .unwrap_err(),
            crate::pystr::encode_utf8(old_key_report.cps(), crate::pystr::Errors::Strict)
                .unwrap_err()
        );

        // 3. Full CLI stdout UnicodeEncodeError check under Errors::Strict (matches cli.rs:764).
        let dir =
            std::env::temp_dir().join(format!("release-scope-surr-test-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join("pr.json"), pr_raw.as_bytes()).unwrap();
        std::fs::write(dir.join("commits.json"), commits_raw.as_bytes()).unwrap();
        std::fs::write(dir.join("files.txt"), b"").unwrap();
        std::fs::write(dir.join("aliases.json"), br#"{"aliases": {}}"#).unwrap();
        std::fs::write(
            dir.join("release-please-config.json"),
            br#"{"packages": {"apps/demo": {"component": "demo"}}}"#,
        )
        .unwrap();
        let env = crate::cli::Env {
            argv: vec![
                PyStr::from("release_scope"),
                PyStr::from("--pr-json"),
                PyStr::from(dir.join("pr.json").to_str().unwrap()),
                PyStr::from("--commits-json"),
                PyStr::from(dir.join("commits.json").to_str().unwrap()),
                PyStr::from("--files"),
                PyStr::from(dir.join("files.txt").to_str().unwrap()),
                PyStr::from("--repo-root"),
                PyStr::from(dir.to_str().unwrap()),
                PyStr::from("--aliases"),
                PyStr::from(dir.join("aliases.json").to_str().unwrap()),
            ],
            default_aliases: PyStr::from(dir.join("aliases.json").to_str().unwrap()),
            columns: 80,
            stdout_errors: crate::pystr::Errors::Strict,
        };
        let outcome = crate::cli::main(&env);
        let _ = std::fs::remove_dir_all(&dir);
        assert_eq!(outcome.code, 1);
        let stderr = String::from_utf8_lossy(&outcome.stderr);
        assert!(
            stderr.contains("UnicodeEncodeError: 'utf-8' codec can't encode character '\\ud800'"),
            "expected UnicodeEncodeError on stdout, got stderr: {stderr}"
        );
    }
}
