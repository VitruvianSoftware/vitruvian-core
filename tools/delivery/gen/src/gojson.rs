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

//! encoding/json's syntax check and literal decoding, ported from Go 1.26.
//!
//! WHY NOT serde_json. A *.delivery.json the generator cannot read must fail
//! the regenerate with the SAME message the Go generator printed — that text is
//! what a human reads in the tidy-check log — and the two libraries disagree on
//! almost everything a malformed file can do: which error wins, how it is
//! worded, whether "NAME" fills the `name` field (Go matches keys
//! case-insensitively), how invalid UTF-8 is replaced. So this is Go's scanner
//! state machine, transcribed, plus a tree builder for input it has accepted.

/// A syntactically valid JSON value, with numbers kept as their literal text
/// (Go converts a number only once it knows the destination type).
#[derive(Clone, Debug)]
pub enum J {
    Null,
    Bool(bool),
    Num(String),
    Str(String),
    Arr(Vec<J>),
    Obj(Vec<(String, J)>),
}

const MAX_DEPTH: usize = 10000;

#[derive(Clone, Copy, PartialEq)]
enum PS {
    ObjectKey,
    ObjectValue,
    ArrayValue,
}

#[derive(Clone, Copy, PartialEq)]
enum St {
    BeginValueOrEmpty,
    BeginValue,
    BeginStringOrEmpty,
    BeginString,
    EndValue,
    EndTop,
    InString,
    InStringEsc,
    InStringEscU(u8),
    Neg,
    One,
    Zero,
    Dot,
    Dot0,
    E,
    ESign,
    E0,
    Lit(&'static [u8], usize, &'static str),
    Error,
}

struct Scanner {
    step: St,
    stack: Vec<PS>,
    end_top: bool,
    err: Option<String>,
}

fn is_space(c: u8) -> bool {
    c == b' ' || c == b'\t' || c == b'\r' || c == b'\n'
}

impl Scanner {
    fn error(&mut self, c: u8, ctx: &str) -> bool {
        self.step = St::Error;
        self.err = Some(format!(
            "invalid character {} {}",
            crate::gostd::quote_char(c),
            ctx
        ));
        false
    }

    fn push(&mut self, c: u8, ps: PS) -> bool {
        self.stack.push(ps);
        if self.stack.len() <= MAX_DEPTH {
            return true;
        }
        self.error(c, "exceeded max depth")
    }

    /// One byte. Returns false on a syntax error.
    fn feed(&mut self, c: u8) -> bool {
        match self.step {
            St::BeginValueOrEmpty => {
                if is_space(c) {
                    return true;
                }
                if c == b']' {
                    return self.end_value(c);
                }
                self.begin_value(c)
            }
            St::BeginValue => self.begin_value(c),
            St::BeginStringOrEmpty => {
                if is_space(c) {
                    return true;
                }
                if c == b'}' {
                    let n = self.stack.len();
                    self.stack[n - 1] = PS::ObjectValue;
                    return self.end_value(c);
                }
                self.begin_string(c)
            }
            St::BeginString => self.begin_string(c),
            St::EndValue => self.end_value(c),
            St::EndTop => {
                if !is_space(c) {
                    self.error(c, "after top-level value");
                    return false;
                }
                true
            }
            St::InString => {
                if c == b'"' {
                    self.step = St::EndValue;
                    return true;
                }
                if c == b'\\' {
                    self.step = St::InStringEsc;
                    return true;
                }
                if c < 0x20 {
                    return self.error(c, "in string literal");
                }
                true
            }
            St::InStringEsc => match c {
                b'b' | b'f' | b'n' | b'r' | b't' | b'\\' | b'/' | b'"' => {
                    self.step = St::InString;
                    true
                }
                b'u' => {
                    self.step = St::InStringEscU(0);
                    true
                }
                _ => self.error(c, "in string escape code"),
            },
            St::InStringEscU(n) => {
                if c.is_ascii_hexdigit() {
                    self.step = if n == 3 {
                        St::InString
                    } else {
                        St::InStringEscU(n + 1)
                    };
                    return true;
                }
                self.error(c, "in \\u hexadecimal character escape")
            }
            St::Neg => {
                if c == b'0' {
                    self.step = St::Zero;
                    return true;
                }
                if (b'1'..=b'9').contains(&c) {
                    self.step = St::One;
                    return true;
                }
                self.error(c, "in numeric literal")
            }
            St::One => {
                if c.is_ascii_digit() {
                    return true;
                }
                self.state0(c)
            }
            St::Zero => self.state0(c),
            St::Dot => {
                if c.is_ascii_digit() {
                    self.step = St::Dot0;
                    return true;
                }
                self.error(c, "after decimal point in numeric literal")
            }
            St::Dot0 => {
                if c.is_ascii_digit() {
                    return true;
                }
                if c == b'e' || c == b'E' {
                    self.step = St::E;
                    return true;
                }
                self.end_value(c)
            }
            St::E => {
                if c == b'+' || c == b'-' {
                    self.step = St::ESign;
                    return true;
                }
                self.esign(c)
            }
            St::ESign => self.esign(c),
            St::E0 => {
                if c.is_ascii_digit() {
                    return true;
                }
                self.end_value(c)
            }
            St::Lit(word, i, name) => {
                if c == word[i] {
                    self.step = if i + 1 == word.len() {
                        St::EndValue
                    } else {
                        St::Lit(word, i + 1, name)
                    };
                    return true;
                }
                let ctx = format!(
                    "in literal {} (expecting {})",
                    name,
                    crate::gostd::quote_char(word[i])
                );
                self.error(c, &ctx)
            }
            St::Error => false,
        }
    }

    fn state0(&mut self, c: u8) -> bool {
        if c == b'.' {
            self.step = St::Dot;
            return true;
        }
        if c == b'e' || c == b'E' {
            self.step = St::E;
            return true;
        }
        self.end_value(c)
    }

    fn esign(&mut self, c: u8) -> bool {
        if c.is_ascii_digit() {
            self.step = St::E0;
            return true;
        }
        self.error(c, "in exponent of numeric literal")
    }

    fn begin_value(&mut self, c: u8) -> bool {
        if is_space(c) {
            return true;
        }
        match c {
            b'{' => {
                self.step = St::BeginStringOrEmpty;
                self.push(c, PS::ObjectKey)
            }
            b'[' => {
                self.step = St::BeginValueOrEmpty;
                self.push(c, PS::ArrayValue)
            }
            b'"' => {
                self.step = St::InString;
                true
            }
            b'-' => {
                self.step = St::Neg;
                true
            }
            b'0' => {
                self.step = St::Zero;
                true
            }
            b't' => {
                self.step = St::Lit(b"true", 1, "true");
                true
            }
            b'f' => {
                self.step = St::Lit(b"false", 1, "false");
                true
            }
            b'n' => {
                self.step = St::Lit(b"null", 1, "null");
                true
            }
            b'1'..=b'9' => {
                self.step = St::One;
                true
            }
            _ => self.error(c, "looking for beginning of value"),
        }
    }

    fn begin_string(&mut self, c: u8) -> bool {
        if is_space(c) {
            return true;
        }
        if c == b'"' {
            self.step = St::InString;
            return true;
        }
        self.error(c, "looking for beginning of object key string")
    }

    fn end_value(&mut self, c: u8) -> bool {
        let n = self.stack.len();
        if n == 0 {
            self.step = St::EndTop;
            self.end_top = true;
            return self.feed(c);
        }
        if is_space(c) {
            self.step = St::EndValue;
            return true;
        }
        match self.stack[n - 1] {
            PS::ObjectKey => {
                if c == b':' {
                    self.stack[n - 1] = PS::ObjectValue;
                    self.step = St::BeginValue;
                    return true;
                }
                self.error(c, "after object key")
            }
            PS::ObjectValue => {
                if c == b',' {
                    self.stack[n - 1] = PS::ObjectKey;
                    self.step = St::BeginString;
                    return true;
                }
                if c == b'}' {
                    self.stack.pop();
                    if self.stack.is_empty() {
                        self.step = St::EndTop;
                        self.end_top = true;
                    } else {
                        self.step = St::EndValue;
                    }
                    return true;
                }
                self.error(c, "after object key:value pair")
            }
            PS::ArrayValue => {
                if c == b',' {
                    self.step = St::BeginValue;
                    return true;
                }
                if c == b']' {
                    self.stack.pop();
                    if self.stack.is_empty() {
                        self.step = St::EndTop;
                        self.end_top = true;
                    } else {
                        self.step = St::EndValue;
                    }
                    return true;
                }
                self.error(c, "after array element")
            }
        }
    }
}

/// checkValid: the whole input is scanned before anything is decoded, so a
/// syntax error anywhere beats a type error earlier in the file.
pub fn check_valid(data: &[u8]) -> Result<(), String> {
    let mut s = Scanner {
        step: St::BeginValue,
        stack: Vec::new(),
        end_top: false,
        err: None,
    };
    for &c in data {
        if !s.feed(c) {
            return Err(s.err.unwrap());
        }
    }
    // eof()
    if s.end_top {
        return Ok(());
    }
    s.feed(b' ');
    if s.end_top {
        return Ok(());
    }
    Err(s
        .err
        .unwrap_or_else(|| "unexpected end of JSON input".to_string()))
}

/// Parse input that check_valid accepted.
pub fn parse(data: &[u8]) -> J {
    let mut p = Parser { b: data, i: 0 };
    p.value()
}

struct Parser<'a> {
    b: &'a [u8],
    i: usize,
}

impl<'a> Parser<'a> {
    fn ws(&mut self) {
        while self.i < self.b.len() && is_space(self.b[self.i]) {
            self.i += 1;
        }
    }

    fn value(&mut self) -> J {
        self.ws();
        match self.b[self.i] {
            b'{' => {
                self.i += 1;
                let mut out = Vec::new();
                self.ws();
                if self.b[self.i] == b'}' {
                    self.i += 1;
                    return J::Obj(out);
                }
                loop {
                    self.ws();
                    let k = self.string();
                    self.ws();
                    self.i += 1; // ':'
                    let v = self.value();
                    out.push((k, v));
                    self.ws();
                    let c = self.b[self.i];
                    self.i += 1;
                    if c == b'}' {
                        return J::Obj(out);
                    }
                }
            }
            b'[' => {
                self.i += 1;
                let mut out = Vec::new();
                self.ws();
                if self.b[self.i] == b']' {
                    self.i += 1;
                    return J::Arr(out);
                }
                loop {
                    out.push(self.value());
                    self.ws();
                    let c = self.b[self.i];
                    self.i += 1;
                    if c == b']' {
                        return J::Arr(out);
                    }
                }
            }
            b'"' => J::Str(self.string()),
            b't' => {
                self.i += 4;
                J::Bool(true)
            }
            b'f' => {
                self.i += 5;
                J::Bool(false)
            }
            b'n' => {
                self.i += 4;
                J::Null
            }
            _ => {
                let start = self.i;
                while self.i < self.b.len()
                    && matches!(
                        self.b[self.i],
                        b'0'..=b'9' | b'-' | b'+' | b'.' | b'e' | b'E'
                    )
                {
                    self.i += 1;
                }
                J::Num(String::from_utf8_lossy(&self.b[start..self.i]).into_owned())
            }
        }
    }

    /// The string literal at self.i (on its opening quote), unquoted the way
    /// Go's unquoteBytes does it.
    fn string(&mut self) -> String {
        self.i += 1;
        let start = self.i;
        let mut end = start;
        while self.b[end] != b'"' {
            if self.b[end] == b'\\' {
                end += 1;
            }
            end += 1;
        }
        self.i = end + 1;
        unquote(&self.b[start..end])
    }
}

fn getu4(s: &[u8]) -> Option<u32> {
    if s.len() < 6 || s[0] != b'\\' || s[1] != b'u' {
        return None;
    }
    let h = std::str::from_utf8(&s[2..6]).ok()?;
    u32::from_str_radix(h, 16).ok()
}

fn unquote(s: &[u8]) -> String {
    let mut out = String::with_capacity(s.len());
    let mut r = 0;
    while r < s.len() {
        let c = s[r];
        if c == b'\\' {
            let e = s[r + 1];
            match e {
                b'"' | b'\\' | b'/' | b'\'' => {
                    out.push(e as char);
                    r += 2;
                }
                b'b' => {
                    out.push('\x08');
                    r += 2;
                }
                b'f' => {
                    out.push('\x0C');
                    r += 2;
                }
                b'n' => {
                    out.push('\n');
                    r += 2;
                }
                b'r' => {
                    out.push('\r');
                    r += 2;
                }
                b't' => {
                    out.push('\t');
                    r += 2;
                }
                _ => {
                    // 'u'
                    let rr = getu4(&s[r..]).unwrap_or(0xFFFD);
                    r += 6;
                    if (0xD800..0xE000).contains(&rr) {
                        let rr1 = getu4(&s[r..]);
                        if let Some(rr1) = rr1 {
                            if (0xD800..0xDC00).contains(&rr) && (0xDC00..0xE000).contains(&rr1) {
                                let dec = 0x10000 + ((rr - 0xD800) << 10) + (rr1 - 0xDC00);
                                out.push(char::from_u32(dec).unwrap_or('\u{FFFD}'));
                                r += 6;
                                continue;
                            }
                        }
                        out.push('\u{FFFD}');
                        continue;
                    }
                    out.push(char::from_u32(rr).unwrap_or('\u{FFFD}'));
                }
            }
            continue;
        }
        if c < 0x80 {
            out.push(c as char);
            r += 1;
            continue;
        }
        let (ch, n) = crate::gostd::decode_rune(&s[r..]);
        out.push(ch.unwrap_or('\u{FFFD}'));
        r += n;
    }
    out
}

/// The kind word an UnmarshalTypeError names for a value of the wrong type.
pub fn kind_word(j: &J) -> String {
    match j {
        J::Null => "null".into(),
        J::Bool(_) => "bool".into(),
        J::Num(_) => "number".into(),
        J::Str(_) => "string".into(),
        J::Arr(_) => "array".into(),
        J::Obj(_) => "object".into(),
    }
}

/// foldName: the key Go uses for its case-insensitive field match.
pub fn fold_name(key: &str) -> String {
    key.chars()
        .map(|c| {
            if c.is_ascii() {
                c.to_ascii_uppercase()
            } else {
                match c {
                    // unicode.SimpleFold orbits whose smallest member is ASCII.
                    '\u{212A}' => 'K',
                    '\u{017F}' => 'S',
                    _ => {
                        // Every other orbit's minimum is itself non-ASCII, so
                        // it can never equal an (ASCII) field name; any
                        // stable non-ASCII stand-in keeps that true.
                        c
                    }
                }
            }
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn err(s: &str) -> String {
        check_valid(s.as_bytes()).unwrap_err()
    }

    #[test]
    fn syntax_errors_read_like_go() {
        assert_eq!(err("{"), "unexpected end of JSON input");
        assert_eq!(err(""), "unexpected end of JSON input");
        assert_eq!(
            err("x"),
            "invalid character 'x' looking for beginning of value"
        );
        assert_eq!(err("{\"a\" 1}"), "invalid character '1' after object key");
        assert_eq!(
            err("{\"a\":1 2}"),
            "invalid character '2' after object key:value pair"
        );
        assert_eq!(err("[1 2]"), "invalid character '2' after array element");
        assert_eq!(
            err("{1}"),
            "invalid character '1' looking for beginning of object key string"
        );
        assert_eq!(err("{} x"), "invalid character 'x' after top-level value");
        assert_eq!(
            err("tru"),
            "invalid character ' ' in literal true (expecting 'e')"
        );
        assert_eq!(
            err("trx"),
            "invalid character 'x' in literal true (expecting 'u')"
        );
        assert_eq!(
            err("1."),
            "invalid character ' ' after decimal point in numeric literal"
        );
        assert_eq!(
            err("1.x"),
            "invalid character 'x' after decimal point in numeric literal"
        );
        assert_eq!(
            err("1ex"),
            "invalid character 'x' in exponent of numeric literal"
        );
        assert_eq!(err("-x"), "invalid character 'x' in numeric literal");
        assert_eq!(
            err("\"\\x\""),
            "invalid character 'x' in string escape code"
        );
        assert_eq!(
            err("\"\\u12x\""),
            "invalid character 'x' in \\u hexadecimal character escape"
        );
        assert_eq!(err("\"\n\""), "invalid character '\\n' in string literal");
        assert!(check_valid(b" {\"a\": [1, -0.5e+3, true, null, \"x\"]} ").is_ok());
        assert!(check_valid(b"1").is_ok());
    }

    #[test]
    fn unquote_handles_surrogates_and_bad_bytes() {
        match parse(b"\"\\ud83d\\ude00 \\ud800x \\u00e9 \xff\"") {
            J::Str(s) => assert_eq!(s, "\u{1F600} \u{FFFD}x é \u{FFFD}"),
            _ => panic!(),
        }
    }
}
