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

//! Base64 as Python 3.12 reads and writes it: `base64.b64encode`, and
//! `base64.b64decode(text, validate=True)`, which is binascii's strict mode:
//! the alphabet only, padding only where it completes the last group, and
//! nothing after it. Bits left over in the last group are ignored, as
//! binascii ignores them.

const ALPHABET: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

pub fn encode(data: &[u8]) -> String {
    let mut out = String::with_capacity(data.len().div_ceil(3) * 4);
    for chunk in data.chunks(3) {
        let b = [
            chunk[0],
            *chunk.get(1).unwrap_or(&0),
            *chunk.get(2).unwrap_or(&0),
        ];
        let n = ((b[0] as u32) << 16) | ((b[1] as u32) << 8) | b[2] as u32;
        out.push(ALPHABET[(n >> 18) as usize & 63] as char);
        out.push(ALPHABET[(n >> 12) as usize & 63] as char);
        out.push(if chunk.len() > 1 {
            ALPHABET[(n >> 6) as usize & 63] as char
        } else {
            '='
        });
        out.push(if chunk.len() > 2 {
            ALPHABET[n as usize & 63] as char
        } else {
            '='
        });
    }
    out
}

fn value(c: u8) -> Option<u32> {
    ALPHABET.iter().position(|a| *a == c).map(|p| p as u32)
}

/// `base64.b64decode(text, validate=True)`; None where Python raises
/// (binascii.Error, or ValueError for a str that is not ASCII).
pub fn b64decode_validate(text: &str) -> Option<Vec<u8>> {
    if !text.is_ascii() {
        return None;
    }
    let bytes = text.as_bytes();
    if bytes.first() == Some(&b'=') {
        return None; // leading padding
    }
    let mut out = Vec::new();
    let (mut quad, mut acc, mut pads) = (0usize, 0u32, 0usize);
    for (i, &c) in bytes.iter().enumerate() {
        if c == b'=' {
            if quad == 0 {
                return None; // excess padding
            }
            pads += 1;
            if quad >= 2 && quad + pads >= 4 {
                if i + 1 < bytes.len() {
                    return None; // excess data after padding
                }
                // The partial group's bytes; its spare low bits are dropped.
                if quad == 2 {
                    out.push((acc >> 4) as u8);
                } else {
                    out.push((acc >> 10) as u8);
                    out.push((acc >> 2) as u8);
                }
                return Some(out);
            }
            continue;
        }
        if pads > 0 {
            return None; // discontinuous padding
        }
        acc = (acc << 6) | value(c)?;
        quad += 1;
        if quad == 4 {
            out.extend_from_slice(&[(acc >> 16) as u8, (acc >> 8) as u8, acc as u8]);
            quad = 0;
            acc = 0;
        }
    }
    // A group left open: one character over a multiple of four, or
    // "Incorrect padding".
    if quad == 0 {
        Some(out)
    } else {
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn strict_mode_as_python_3_12() {
        // From the hermetic Python 3.12's base64.b64decode(s, validate=True).
        assert_eq!(b64decode_validate("AAAA=="), None);
        assert_eq!(b64decode_validate("AA="), None);
        assert_eq!(b64decode_validate("AA=="), Some(vec![0]));
        assert_eq!(b64decode_validate("AAA"), None);
        assert_eq!(b64decode_validate("AAAA="), None);
        assert_eq!(b64decode_validate("A"), None);
        assert_eq!(b64decode_validate("QQ=="), Some(b"A".to_vec()));
        assert_eq!(b64decode_validate(" AAAA"), None);
        assert_eq!(b64decode_validate("AB=="), Some(vec![0]));
        assert_eq!(b64decode_validate("QR=="), Some(b"A".to_vec()));
        assert_eq!(b64decode_validate(""), Some(vec![]));
        assert_eq!(b64decode_validate("QUJD"), Some(b"ABC".to_vec()));
        assert_eq!(b64decode_validate("QUI="), Some(b"AB".to_vec()));
        assert_eq!(b64decode_validate("QUI=QUI="), None);
        assert_eq!(b64decode_validate("Q=UI"), None);
        assert_eq!(b64decode_validate("é"), None);
    }

    #[test]
    fn encodes() {
        assert_eq!(encode(b""), "");
        assert_eq!(encode(b"A"), "QQ==");
        assert_eq!(encode(b"AB"), "QUI=");
        assert_eq!(encode(b"ABC"), "QUJD");
        for n in 0..40u8 {
            let data: Vec<u8> = (0..n).map(|i| i.wrapping_mul(37)).collect();
            assert_eq!(b64decode_validate(&encode(&data)), Some(data));
        }
    }
}
