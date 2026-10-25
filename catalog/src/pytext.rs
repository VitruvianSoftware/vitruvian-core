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

//! Bytes to text the way Python turns them: `bytes.decode("utf-8")` with its
//! error messages, `Path.read_text()` (which also folds `\r\n` and `\r` into
//! `\n`), and the encoding `json.loads` picks for bytes.

/// `data.decode("utf-8")`: the text, or `str(UnicodeDecodeError)`.
pub fn decode_utf8(data: &[u8]) -> Result<String, String> {
    decode_utf8_named(data, "utf-8")
}

fn decode_utf8_named(data: &[u8], codec: &str) -> Result<String, String> {
    match std::str::from_utf8(data) {
        Ok(s) => Ok(s.to_string()),
        Err(e) => {
            let start = e.valid_up_to();
            let (end, reason) = match e.error_len() {
                None => (data.len(), "unexpected end of data"),
                Some(n) => {
                    let lead = data[start];
                    if n == 1 && !(0xC2..=0xF4).contains(&lead) {
                        (start + 1, "invalid start byte")
                    } else {
                        (start + n, "invalid continuation byte")
                    }
                }
            };
            Err(if end - start == 1 {
                format!(
                    "'{}' codec can't decode byte 0x{:02x} in position {}: {}",
                    codec, data[start], start, reason
                )
            } else {
                format!(
                    "'{}' codec can't decode bytes in position {}-{}: {}",
                    codec,
                    start,
                    end - 1,
                    reason
                )
            })
        }
    }
}

/// `data.decode("utf-8", "replace")`.
pub fn decode_utf8_replace(data: &[u8]) -> String {
    String::from_utf8_lossy(data).into_owned()
}

/// Universal newlines, as text mode reads a file.
pub fn universal_newlines(s: &str) -> String {
    if !s.contains('\r') {
        return s.to_string();
    }
    s.replace("\r\n", "\n").replace('\r', "\n")
}

/// `Path(path).read_text(encoding="utf-8")`: Err is the crash Python would
/// have, as `Class: message`.
pub fn read_text(path: &std::path::Path) -> Result<String, String> {
    let data = std::fs::read(path).map_err(|e| crate::pyerr::os_error(&e, path).to_string())?;
    decode_utf8(&data)
        .map(|s| universal_newlines(&s))
        .map_err(|m| format!("UnicodeDecodeError: {}", m))
}

fn decode_utf16(data: &[u8], big: bool, codec: &str) -> Result<String, String> {
    let mut units = Vec::new();
    let mut i = 0;
    while i + 1 < data.len() {
        let pair = [data[i], data[i + 1]];
        units.push(if big {
            u16::from_be_bytes(pair)
        } else {
            u16::from_le_bytes(pair)
        });
        i += 2;
    }
    let text: Result<String, _> = char::decode_utf16(units.iter().copied()).collect();
    match text {
        Ok(t) if data.len() % 2 == 0 => Ok(t),
        Ok(_) => Err(format!(
            "'{}' codec can't decode byte 0x{:02x} in position {}: truncated data",
            codec,
            data[data.len() - 1],
            data.len() - 1
        )),
        Err(_) => Err(format!(
            "'{}' codec can't decode bytes: illegal encoding",
            codec
        )),
    }
}

fn decode_utf32(data: &[u8], big: bool, codec: &str) -> Result<String, String> {
    if data.len() % 4 != 0 {
        return Err(format!(
            "'{}' codec can't decode bytes: truncated data",
            codec
        ));
    }
    let mut out = String::new();
    for chunk in data.chunks(4) {
        let w = [chunk[0], chunk[1], chunk[2], chunk[3]];
        let cp = if big {
            u32::from_be_bytes(w)
        } else {
            u32::from_le_bytes(w)
        };
        match char::from_u32(cp) {
            Some(c) => out.push(c),
            None => {
                return Err(format!(
                    "'{}' codec can't decode bytes: code point not in range(0x110000)",
                    codec
                ))
            }
        }
    }
    Ok(out)
}

/// `s.decode(json.detect_encoding(s), "surrogatepass")`, as `json.loads`
/// does with bytes.
pub fn decode_json_bytes(b: &[u8]) -> Result<String, String> {
    let starts = |p: &[u8]| b.starts_with(p);
    if starts(&[0, 0, 0xFE, 0xFF]) {
        return decode_utf32(&b[4..], true, "utf-32");
    }
    if starts(&[0xFF, 0xFE, 0, 0]) {
        return decode_utf32(&b[4..], false, "utf-32");
    }
    if starts(&[0xFE, 0xFF]) {
        return decode_utf16(&b[2..], true, "utf-16");
    }
    if starts(&[0xFF, 0xFE]) {
        return decode_utf16(&b[2..], false, "utf-16");
    }
    if starts(&[0xEF, 0xBB, 0xBF]) {
        return decode_utf8_named(&b[3..], "utf-8");
    }
    if b.len() >= 4 {
        if b[0] == 0 {
            return if b[1] != 0 {
                decode_utf16(b, true, "utf-16-be")
            } else {
                decode_utf32(b, true, "utf-32-be")
            };
        }
        if b[1] == 0 {
            return if b[2] != 0 || b[3] != 0 {
                decode_utf16(b, false, "utf-16-le")
            } else {
                decode_utf32(b, false, "utf-32-le")
            };
        }
    } else if b.len() == 2 {
        if b[0] == 0 {
            return decode_utf16(b, true, "utf-16-be");
        }
        if b[1] == 0 {
            return decode_utf16(b, false, "utf-16-le");
        }
    }
    decode_utf8(b)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn utf8_errors_in_pythons_words() {
        assert_eq!(
            decode_utf8(b"ab\xff").unwrap_err(),
            "'utf-8' codec can't decode byte 0xff in position 2: invalid start byte"
        );
        assert_eq!(
            decode_utf8(b"\xe1\x80A").unwrap_err(),
            "'utf-8' codec can't decode bytes in position 0-1: invalid continuation byte"
        );
        assert_eq!(
            decode_utf8(b"x\xe1\x80").unwrap_err(),
            "'utf-8' codec can't decode bytes in position 1-2: unexpected end of data"
        );
        assert_eq!(decode_json_bytes(b"\xef\xbb\xbf[1]").unwrap(), "[1]");
        assert_eq!(decode_json_bytes(b"[\x001\x00]\x00").unwrap(), "[1]");
        assert_eq!(universal_newlines("a\r\nb\rc"), "a\nb\nc");
    }
}
