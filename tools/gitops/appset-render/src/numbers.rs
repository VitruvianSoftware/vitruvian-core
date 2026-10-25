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

//! The number parsing text/template's NumberNode does, with Go's results:
//! strconv.ParseUint / ParseInt / ParseFloat (base 0, underscores, hex
//! floats, range errors), strconv.UnquoteChar for character constants and
//! fmt.Sscan for complex constants. Only success or failure, and the error
//! text, reach the output; values are computed where a decision needs them.

use crate::gofmt::Arg;
use crate::gostr;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum NumErr {
    Syntax,
    Range,
}

impl NumErr {
    pub fn text(self) -> &'static [u8] {
        match self {
            NumErr::Syntax => b"invalid syntax",
            NumErr::Range => b"value out of range",
        }
    }
}

fn lower(c: u8) -> u8 {
    c | (b'x' - b'X')
}

/// strconv.underscoreOK.
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

/// strconv.ParseUint(s, 0, 64).
pub fn parse_uint(s: &[u8]) -> Result<u64, NumErr> {
    if s.is_empty() {
        return Err(NumErr::Syntax);
    }
    let s0 = s;
    let mut s = s;
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
    let max_val = u64::MAX;
    let mut underscores = false;
    let mut n: u64 = 0;
    for &c in s {
        let d: u64 = if c == b'_' {
            underscores = true;
            continue;
        } else if c.is_ascii_digit() {
            (c - b'0') as u64
        } else if (b'a'..=b'z').contains(&lower(c)) {
            (lower(c) - b'a' + 10) as u64
        } else {
            return Err(NumErr::Syntax);
        };
        if d >= base {
            return Err(NumErr::Syntax);
        }
        if n >= cutoff {
            return Err(NumErr::Range);
        }
        n *= base;
        let n1 = n.wrapping_add(d);
        if n1 < n || n1 > max_val {
            return Err(NumErr::Range);
        }
        n = n1;
    }
    if underscores && !underscore_ok(s0) {
        return Err(NumErr::Syntax);
    }
    Ok(n)
}

/// strconv.ParseInt(s, 0, 64).
pub fn parse_int(s: &[u8]) -> Result<i64, NumErr> {
    if s.is_empty() {
        return Err(NumErr::Syntax);
    }
    let mut s = s;
    let mut neg = false;
    if s[0] == b'+' {
        s = &s[1..];
    } else if s[0] == b'-' {
        s = &s[1..];
        neg = true;
    }
    let un = match parse_uint(s) {
        Ok(v) => v,
        Err(NumErr::Range) => u64::MAX,
        Err(e) => return Err(e),
    };
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

/// strconv.Atoi.
pub fn atoi(s: &[u8]) -> Result<i64, NumErr> {
    if !s.is_empty() && s.len() < 19 {
        let mut t = s;
        if s[0] == b'-' || s[0] == b'+' {
            t = &s[1..];
            if t.is_empty() {
                return Err(NumErr::Syntax);
            }
        }
        let mut n: i64 = 0;
        for &ch in t {
            let d = ch.wrapping_sub(b'0');
            if d > 9 {
                return Err(NumErr::Syntax);
            }
            n = n * 10 + d as i64;
        }
        return Ok(if s[0] == b'-' { -n } else { n });
    }
    // ParseInt(s, 10, 0): no base prefixes, no underscores.
    if s.is_empty() {
        return Err(NumErr::Syntax);
    }
    let mut t = s;
    let mut neg = false;
    if t[0] == b'+' || t[0] == b'-' {
        neg = t[0] == b'-';
        t = &t[1..];
    }
    if t.is_empty() {
        return Err(NumErr::Syntax);
    }
    let mut n: u64 = 0;
    for &c in t {
        if !c.is_ascii_digit() {
            return Err(NumErr::Syntax);
        }
        // ParseUint stops with ErrRange at the first overflow.
        match n
            .checked_mul(10)
            .and_then(|v| v.checked_add((c - b'0') as u64))
        {
            Some(v) => n = v,
            None => return Err(NumErr::Range),
        }
    }
    let cutoff: u64 = 1 << 63;
    if (!neg && n >= cutoff) || (neg && n > cutoff) {
        return Err(NumErr::Range);
    }
    Ok(if neg {
        (n as i64).wrapping_neg()
    } else {
        n as i64
    })
}

/// strconv's readFloat: (mantissa, exp, neg, trunc, hex, consumed, ok).
struct ReadFloat {
    mantissa: u64,
    exp: i64,
    neg: bool,
    trunc: bool,
    hex: bool,
    n: usize,
    ok: bool,
}

fn read_float(s: &[u8]) -> ReadFloat {
    let mut r = ReadFloat {
        mantissa: 0,
        exp: 0,
        neg: false,
        trunc: false,
        hex: false,
        n: 0,
        ok: false,
    };
    let mut underscores = false;
    let mut i = 0usize;
    if i >= s.len() {
        return r;
    }
    if s[i] == b'+' {
        i += 1;
    } else if s[i] == b'-' {
        i += 1;
        r.neg = true;
    }
    let mut base: u64 = 10;
    let mut max_mant_digits = 19;
    let mut exp_char = b'e';
    if i + 2 < s.len() && s[i] == b'0' && lower(s[i + 1]) == b'x' {
        base = 16;
        max_mant_digits = 16;
        i += 2;
        exp_char = b'p';
        r.hex = true;
    }
    let mut sawdot = false;
    let mut sawdigits = false;
    let mut nd: i64 = 0;
    let mut nd_mant: i64 = 0;
    let mut dp: i64 = 0;
    while i < s.len() {
        let c = s[i];
        if c == b'_' {
            underscores = true;
            i += 1;
            continue;
        } else if c == b'.' {
            if sawdot {
                break;
            }
            sawdot = true;
            dp = nd;
            i += 1;
            continue;
        } else if c.is_ascii_digit() {
            sawdigits = true;
            if c == b'0' && nd == 0 {
                dp -= 1;
                i += 1;
                continue;
            }
            nd += 1;
            if nd_mant < max_mant_digits {
                r.mantissa = r.mantissa * base + (c - b'0') as u64;
                nd_mant += 1;
            } else if c != b'0' {
                r.trunc = true;
            }
            i += 1;
            continue;
        } else if base == 16 && (b'a'..=b'f').contains(&lower(c)) {
            sawdigits = true;
            nd += 1;
            if nd_mant < max_mant_digits {
                r.mantissa = r.mantissa * 16 + (lower(c) - b'a' + 10) as u64;
                nd_mant += 1;
            } else {
                r.trunc = true;
            }
            i += 1;
            continue;
        }
        break;
    }
    r.n = i;
    if !sawdigits {
        return r;
    }
    if !sawdot {
        dp = nd;
    }
    if base == 16 {
        dp *= 4;
        nd_mant *= 4;
    }
    if i < s.len() && lower(s[i]) == exp_char {
        i += 1;
        if i >= s.len() {
            r.n = i;
            return r;
        }
        let mut esign = 1;
        if s[i] == b'+' {
            i += 1;
        } else if s[i] == b'-' {
            i += 1;
            esign = -1;
        }
        if i >= s.len() || !s[i].is_ascii_digit() {
            r.n = i;
            return r;
        }
        let mut e: i64 = 0;
        while i < s.len() && (s[i].is_ascii_digit() || s[i] == b'_') {
            if s[i] == b'_' {
                underscores = true;
                i += 1;
                continue;
            }
            if e < 10000 {
                e = e * 10 + (s[i] - b'0') as i64;
            }
            i += 1;
        }
        dp += e * esign;
    } else if base == 16 {
        r.n = i;
        return r;
    }
    if r.mantissa != 0 {
        r.exp = dp - nd_mant;
    }
    r.n = i;
    if underscores && !underscore_ok(&s[..i]) {
        return r;
    }
    r.ok = true;
    r
}

/// strconv's atofHex for float64: whether the value overflows.
fn atof_hex_overflows(mut mantissa: u64, mut exp: i64, trunc: bool) -> bool {
    const MANTBITS: u32 = 52;
    const EXPBITS: u32 = 11;
    const BIAS: i64 = -1023;
    let max_exp = (1i64 << EXPBITS) + BIAS - 2;
    let min_exp = BIAS + 1;
    exp += MANTBITS as i64;
    while mantissa != 0 && mantissa >> (MANTBITS + 2) == 0 {
        mantissa <<= 1;
        exp -= 1;
    }
    if trunc {
        mantissa |= 1;
    }
    while mantissa >> (1 + MANTBITS + 2) != 0 {
        mantissa = (mantissa >> 1) | (mantissa & 1);
        exp += 1;
    }
    while mantissa > 1 && exp < min_exp - 2 {
        mantissa = (mantissa >> 1) | (mantissa & 1);
        exp += 1;
    }
    let mut round = mantissa & 3;
    mantissa >>= 2;
    round |= mantissa & 1;
    exp += 2;
    if round == 3 {
        mantissa += 1;
        if mantissa == 1 << (1 + MANTBITS) {
            mantissa >>= 1;
            exp += 1;
        }
    }
    if mantissa >> MANTBITS == 0 {
        exp = BIAS;
    }
    exp > max_exp
}

/// strconv's special(): ±Inf/Infinity/NaN prefixes. Returns consumed length.
fn special(s: &[u8]) -> Option<(f64, usize)> {
    if s.is_empty() {
        return None;
    }
    let prefix_len = |s: &[u8], word: &[u8]| -> usize {
        s.iter()
            .zip(word)
            .take_while(|(a, b)| a.to_ascii_lowercase() == **b)
            .count()
    };
    let (sign, nsign, rest) = match s[0] {
        b'+' => (1.0, 1, &s[1..]),
        b'-' => (-1.0, 1, &s[1..]),
        b'i' | b'I' => (1.0, 0, s),
        b'n' | b'N' => {
            if prefix_len(s, b"nan") == 3 {
                return Some((f64::NAN, 3));
            }
            return None;
        }
        _ => return None,
    };
    let mut n = prefix_len(rest, b"infinity");
    if 3 < n && n < 8 {
        n = 3;
    }
    if n == 3 || n == 8 {
        return Some((sign * f64::INFINITY, nsign + n));
    }
    None
}

/// strconv.ParseFloat(s, 64): the value, or the error kind.
pub fn parse_float(s: &[u8]) -> Result<f64, NumErr> {
    if let Some((v, n)) = special(s) {
        if n != s.len() {
            return Err(NumErr::Syntax);
        }
        return Ok(v);
    }
    let r = read_float(s);
    if !r.ok || r.n != s.len() {
        return Err(NumErr::Syntax);
    }
    if r.hex {
        if atof_hex_overflows(r.mantissa, r.exp, r.trunc) {
            return Err(NumErr::Range);
        }
        // The value itself only feeds integer-ness checks; approximate it.
        let v = (r.mantissa as f64) * 2f64.powi(r.exp.clamp(-2000, 2000) as i32);
        return Ok(if r.neg { -v } else { v });
    }
    // Decimal: Rust's parser rounds correctly, as Go's does, so the two agree
    // on overflow. Rebuild the literal without underscores or a base prefix.
    let text: Vec<u8> = s.iter().copied().filter(|&c| c != b'_').collect();
    let text = String::from_utf8_lossy(&text).into_owned();
    let v: f64 = text.parse().map_err(|_| NumErr::Syntax)?;
    if v.is_infinite() {
        return Err(NumErr::Range);
    }
    Ok(v)
}

/// The *strconv.NumError Go builds for a failed parse.
fn num_error(func: &str, num: &[u8], e: NumErr) -> Arg {
    Arg::NumError {
        func: func.as_bytes().to_vec(),
        num: num.to_vec(),
        err: e.text().to_vec(),
    }
}

/// fmt's ss reading a string: just enough of fmt.Sscan for one complex128.
struct Scan<'a> {
    s: &'a [u8],
    pos: usize,
    buf: Vec<u8>,
}

impl Scan<'_> {
    fn get_rune(&mut self) -> Option<(char, usize)> {
        if self.pos >= self.s.len() {
            return None;
        }
        let (r, w, _) = gostr::decode_rune(&self.s[self.pos..]);
        self.pos += w;
        Some((r, w))
    }

    fn accept(&mut self, ok: &str) -> bool {
        match self.get_rune() {
            None => false,
            Some((r, w)) => {
                if ok.contains(r) {
                    gostr::push_rune(&mut self.buf, r);
                    true
                } else {
                    self.pos -= w;
                    false
                }
            }
        }
    }

    fn float_token(&mut self) -> Vec<u8> {
        self.buf.clear();
        if self.accept("nN") && self.accept("aA") && self.accept("nN") {
            return self.buf.clone();
        }
        self.accept("+-");
        if self.accept("iI") && self.accept("nN") && self.accept("fF") {
            return self.buf.clone();
        }
        let mut digits = "0123456789_";
        let mut exp = "eEpP";
        if self.accept("0") && self.accept("xX") {
            digits = "0123456789aAbBcCdDeEfF_";
            exp = "pP";
        }
        while self.accept(digits) {}
        if self.accept(".") {
            while self.accept(digits) {}
        }
        if self.accept(exp) {
            self.accept("+-");
            while self.accept("0123456789_") {}
        }
        self.buf.clone()
    }
}

/// fmt's convertFloat (n = 64).
fn convert_float(s: &[u8]) -> Result<f64, Arg> {
    if let Some(p) = s.iter().position(|&c| c == b'p') {
        if !s.iter().any(|&c| c == b'x' || c == b'X') {
            let f = parse_float(&s[..p]).map_err(|e| num_error("ParseFloat", s, e))?;
            let m = atoi(&s[p + 1..]).map_err(|e| num_error("Atoi", s, e))?;
            return Ok(f * 2f64.powi(m.clamp(-5000, 5000) as i32));
        }
    }
    parse_float(s).map_err(|e| num_error("ParseFloat", s, e))
}

/// fmt.Sscan(text, &complex128): (real, imag) or the error argument.
pub fn sscan_complex(text: &[u8]) -> Result<(f64, f64), Arg> {
    let err_complex = || Arg::ErrString(b"syntax error scanning complex number".to_vec());
    let mut sc = Scan {
        s: text,
        pos: 0,
        buf: Vec::new(),
    };
    // SkipSpace: the lexer never produces leading space here.
    if sc.pos >= sc.s.len() {
        return Err(Arg::ErrString(b"unexpected EOF".to_vec()));
    }
    let parens = sc.accept("(");
    let real = sc.float_token();
    sc.buf.clear();
    if !sc.accept("+-") {
        return Err(err_complex());
    }
    let mut imag = sc.buf.clone();
    imag.extend(sc.float_token());
    if !sc.accept("i") {
        return Err(err_complex());
    }
    if parens && !sc.accept(")") {
        return Err(err_complex());
    }
    let re = convert_float(&real)?;
    let im = convert_float(&imag)?;
    Ok((re, im))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ints() {
        assert_eq!(parse_uint(b"0x_1F"), Ok(31));
        assert_eq!(parse_uint(b"017"), Ok(15));
        assert_eq!(parse_uint(b"08"), Err(NumErr::Syntax));
        assert_eq!(parse_uint(b"1__0"), Err(NumErr::Syntax));
        assert_eq!(parse_uint(b"18446744073709551616"), Err(NumErr::Range));
        assert_eq!(parse_int(b"-9223372036854775808"), Ok(i64::MIN));
        assert_eq!(parse_int(b"9223372036854775808"), Err(NumErr::Range));
        assert_eq!(parse_int(b"+0b101"), Ok(5));
        assert_eq!(parse_uint(b"+5"), Err(NumErr::Syntax));
    }

    #[test]
    fn floats() {
        assert_eq!(parse_float(b"1_000.5"), Ok(1000.5));
        assert_eq!(parse_float(b"1e400"), Err(NumErr::Range));
        assert_eq!(parse_float(b"1e-400"), Ok(0.0));
        assert_eq!(parse_float(b"0x1p-2"), Ok(0.25));
        assert_eq!(parse_float(b"0x1.8"), Err(NumErr::Syntax));
        assert_eq!(parse_float(b"0x1p1024"), Err(NumErr::Range));
        assert!(parse_float(b"0x1.fffffffffffffp1023").is_ok());
        assert_eq!(parse_float(b"08"), Ok(8.0));
        assert_eq!(parse_float(b"."), Err(NumErr::Syntax));
        assert_eq!(parse_float(b"+"), Err(NumErr::Syntax));
        assert_eq!(parse_float(b"1e"), Err(NumErr::Syntax));
        assert_eq!(parse_float(b"0x"), Err(NumErr::Syntax));
    }

    #[test]
    fn complexes() {
        assert_eq!(sscan_complex(b"1+2i").ok(), Some((1.0, 2.0)));
        assert!(matches!(sscan_complex(b"1+i"), Err(Arg::ErrString(_))));
        assert!(matches!(sscan_complex(b"1_+2i"), Err(Arg::NumError { .. })));
    }
}
