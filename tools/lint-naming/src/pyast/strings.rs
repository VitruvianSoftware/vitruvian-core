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

//! Decoding a string literal's body the way CPython 3.12's string parser
//! does (Parser/string_parser.c), including which escape it warns about:
//! only the first invalid one in each literal.

use crate::pystr::surrogate_char;

/// A decoded literal, and the first invalid escape (its offset in the body
/// and the warning text), if any.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum LiteralValue {
    Str(String, Option<(usize, String)>),
    Bytes(Option<(usize, String)>),
    /// The literal does not decode: a SyntaxError.
    Bad,
}

fn hex_value(chars: &[char]) -> Option<u32> {
    let mut v: u32 = 0;
    for &c in chars {
        v = v.checked_mul(16)? + c.to_digit(16)?;
    }
    Some(v)
}

fn push_code(out: &mut String, v: u32) -> bool {
    if (0xD800..=0xDFFF).contains(&v) {
        out.push(surrogate_char(v));
        true
    } else if let Some(c) = char::from_u32(v) {
        out.push(c);
        true
    } else {
        false
    }
}

/// Decode `body` (the characters between the quotes).
pub fn decode_literal(body: &[char], bytes: bool, raw: bool) -> LiteralValue {
    if bytes && body.iter().any(|&c| (c as u32) >= 0x80) {
        return LiteralValue::Bad;
    }
    if raw {
        return if bytes {
            LiteralValue::Bytes(None)
        } else {
            LiteralValue::Str(body.iter().collect(), None)
        };
    }
    let mut out = String::with_capacity(body.len());
    let mut first: Option<(usize, String)> = None;
    let mut i = 0;
    while i < body.len() {
        let c = body[i];
        if c != '\\' {
            out.push(c);
            i += 1;
            continue;
        }
        // A backslash at the end, or before a non-ASCII character, is a
        // literal backslash (CPython rewrites it as \ first).
        let Some(&e) = body.get(i + 1) else {
            out.push('\\');
            i += 1;
            continue;
        };
        if (e as u32) >= 0x80 {
            out.push('\\');
            i += 1;
            continue;
        }
        i += 2;
        match e {
            '\n' => {}
            '\\' => out.push('\\'),
            '\'' => out.push('\''),
            '"' => out.push('"'),
            'b' => out.push('\x08'),
            'f' => out.push('\x0c'),
            't' => out.push('\t'),
            'n' => out.push('\n'),
            'r' => out.push('\r'),
            'v' => out.push('\x0b'),
            'a' => out.push('\x07'),
            '0'..='7' => {
                let start = i - 1;
                let mut x = e as u32 - '0' as u32;
                let mut n = 1;
                while n < 3 && i < body.len() && ('0'..='7').contains(&body[i]) {
                    x = (x << 3) + (body[i] as u32 - '0' as u32);
                    i += 1;
                    n += 1;
                }
                if x > 0o377 && first.is_none() {
                    let digits: String = body[start..start + 3].iter().collect();
                    first = Some((
                        start,
                        format!("invalid octal escape sequence '\\{}'", digits),
                    ));
                }
                if !bytes {
                    push_code(&mut out, x);
                }
            }
            'x' => {
                let end = i + 2;
                if end > body.len() {
                    return LiteralValue::Bad;
                }
                let Some(v) = hex_value(&body[i..end]) else {
                    return LiteralValue::Bad;
                };
                i = end;
                if !bytes {
                    push_code(&mut out, v);
                }
            }
            'u' | 'U' if !bytes => {
                let n = if e == 'u' { 4 } else { 8 };
                let end = i + n;
                if end > body.len() {
                    return LiteralValue::Bad;
                }
                let Some(v) = hex_value(&body[i..end]) else {
                    return LiteralValue::Bad;
                };
                if v > 0x10FFFF || !push_code(&mut out, v) {
                    return LiteralValue::Bad;
                }
                i = end;
            }
            'N' if !bytes => {
                // The name is looked up in the Unicode database, which this
                // port does not carry: any well-formed \N{...} is accepted.
                if body.get(i) != Some(&'{') {
                    return LiteralValue::Bad;
                }
                let Some(close) = body[i + 1..].iter().position(|&c| c == '}') else {
                    return LiteralValue::Bad;
                };
                if close == 0 {
                    return LiteralValue::Bad;
                }
                out.push('\u{FFFD}');
                i += close + 2;
            }
            _ => {
                if first.is_none() {
                    first = Some((i - 1, format!("invalid escape sequence '\\{}'", e)));
                }
                out.push('\\');
                out.push(e);
            }
        }
    }
    if bytes {
        LiteralValue::Bytes(first)
    } else {
        LiteralValue::Str(out, first)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn d(s: &str, bytes: bool, raw: bool) -> LiteralValue {
        decode_literal(&s.chars().collect::<Vec<_>>(), bytes, raw)
    }

    #[test]
    fn escapes() {
        assert_eq!(
            d("a\\x5fb\\n", false, false),
            LiteralValue::Str("a_b\n".into(), None)
        );
        assert_eq!(
            d("\\101\\u00e9\\U0001F680", false, false),
            LiteralValue::Str("Aé🚀".into(), None)
        );
        assert_eq!(
            d("a\\\nb", false, false),
            LiteralValue::Str("ab".into(), None)
        );
        assert_eq!(d("\\x4", false, false), LiteralValue::Bad);
        assert_eq!(d("\\U00110000", false, false), LiteralValue::Bad);
        assert_eq!(d("\\N{}", false, false), LiteralValue::Bad);
    }

    #[test]
    fn first_invalid_escape_only() {
        assert_eq!(
            d("\\d\\q", false, false),
            LiteralValue::Str(
                "\\d\\q".into(),
                Some((1, "invalid escape sequence '\\d'".into()))
            )
        );
        assert_eq!(
            d("\\400", false, false),
            LiteralValue::Str(
                "Ā".into(),
                Some((1, "invalid octal escape sequence '\\400'".into()))
            )
        );
        assert_eq!(
            d("\\é", false, false),
            LiteralValue::Str("\\é".into(), None)
        );
        assert_eq!(
            d("\\u1234", true, false),
            LiteralValue::Bytes(Some((1, "invalid escape sequence '\\u'".into())))
        );
        assert_eq!(d("é", true, false), LiteralValue::Bad);
        assert_eq!(d("\\d", false, true), LiteralValue::Str("\\d".into(), None));
    }
}
