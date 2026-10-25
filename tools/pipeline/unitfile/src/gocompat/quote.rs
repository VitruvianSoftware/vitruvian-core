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

//! Go's `strconv.Quote` (what `%q` prints for a string).

/// Whether Go's `unicode.IsPrint` holds for a non-ASCII rune. Letters,
/// marks, numbers, punctuation and symbols are printable; spaces other than
/// U+0020, controls, format characters, private use and unassigned code
/// points are not. This covers the ranges that turn up in practice.
fn is_print_non_ascii(c: char) -> bool {
    let u = c as u32;
    !matches!(u,
        0x80..=0xA0
        | 0xAD
        | 0x34F
        | 0x61C
        | 0x115F..=0x1160
        | 0x1680
        | 0x180B..=0x180F
        | 0x2000..=0x200F
        | 0x2028..=0x202F
        | 0x205F..=0x206F
        | 0x3000
        | 0x3164
        | 0xD800..=0xF8FF
        | 0xFE00..=0xFE0F
        | 0xFEFF
        | 0xFFA0
        | 0xFFF0..=0xFFFB
        | 0xFFFE..=0xFFFF
        | 0xE0000..=0xE0FFF
        | 0xF0000..=0x10FFFF
    )
}

/// `strconv.Quote(s)`.
pub fn quote(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\x07' => out.push_str("\\a"),
            '\x08' => out.push_str("\\b"),
            '\x0c' => out.push_str("\\f"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            '\x0b' => out.push_str("\\v"),
            c if (c as u32) < 0x20 || c as u32 == 0x7f => {
                out.push_str(&format!("\\x{:02x}", c as u32));
            }
            c if c.is_ascii() => out.push(c),
            c if is_print_non_ascii(c) => out.push(c),
            c if (c as u32) < 0x10000 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push_str(&format!("\\U{:08x}", c as u32)),
        }
    }
    out.push('"');
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn quotes_like_go() {
        assert_eq!(quote("a\"b\\c"), r#""a\"b\\c""#);
        assert_eq!(quote("tab\there\n"), r#""tab\there\n""#);
        assert_eq!(quote("\x01\x7f"), r#""\x01\x7f""#);
        assert_eq!(quote("héllo ✓"), "\"héllo ✓\"");
        assert_eq!(quote("\u{a0}\u{2028}"), "\"\\u00a0\\u2028\"");
        assert_eq!(quote(""), "\"\"");
    }
}
