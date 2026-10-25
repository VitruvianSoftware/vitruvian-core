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

//! Go's fmt.Sprintf / fmt.Errorf, for the argument types the template parser
//! passes. Normally the formats are fixed and this is plain substitution, but
//! the parser builds its error format as "template: <name>:<line>: <format>"
//! and only then hands it to Errorf, so a '%' in an ApplicationSet's file name
//! is read as a verb. Reproducing what Go prints then means reproducing fmt:
//! flags, width, precision, argument indexes, bad verbs, missing and extra
//! arguments, and how each argument type prints under each verb.
//!
//! One thing cannot be reproduced: under a verb its methods do not handle,
//! a pointer-typed argument (a parse node, a *strconv.NumError) prints the
//! address of a field, which differs between runs of the Go tool itself.
//! Those print a fixed stand-in address.

use crate::gostr;

/// The text/template/parse token passed to the parser's error formats.
#[derive(Debug, Clone)]
pub struct ItemArg {
    pub typ: i64,
    pub pos: i64,
    pub val: Vec<u8>,
    pub line: i64,
    /// item.String().
    pub text: Vec<u8>,
}

/// An argument to a format, by its Go type.
#[derive(Debug, Clone)]
pub enum Arg {
    /// string
    Str(Vec<u8>),
    /// int
    Int(i64),
    /// parse.item (a Stringer)
    Item(ItemArg),
    /// *errors.errorString
    ErrString(Vec<u8>),
    /// *strconv.NumError
    NumError {
        func: Vec<u8>,
        num: Vec<u8>,
        err: Vec<u8>,
    },
    /// *parse.elseNode / *parse.endNode (Stringers); `line` is elseNode's.
    Node {
        ty: &'static str,
        typ: i64,
        pos: i64,
        line: Option<i64>,
        text: Vec<u8>,
    },
}

impl Arg {
    fn type_string(&self) -> &'static str {
        match self {
            Arg::Str(_) => "string",
            Arg::Int(_) => "int",
            Arg::Item(_) => "parse.item",
            Arg::ErrString(_) => "*errors.errorString",
            Arg::NumError { .. } => "*strconv.NumError",
            Arg::Node { ty, .. } => ty,
        }
    }

    fn is_error(&self) -> bool {
        matches!(self, Arg::ErrString(_) | Arg::NumError { .. })
    }

    /// Error() or String(), for the verbs handleMethods takes over.
    fn method_text(&self) -> Option<Vec<u8>> {
        match self {
            Arg::Item(i) => Some(i.text.clone()),
            Arg::ErrString(s) => Some(s.clone()),
            Arg::NumError { func, num, err } => {
                let mut s = b"strconv.".to_vec();
                s.extend_from_slice(func);
                s.extend_from_slice(b": parsing ");
                s.extend_from_slice(&gostr::quote(num));
                s.extend_from_slice(b": ");
                s.extend_from_slice(err);
                Some(s)
            }
            Arg::Node { text, .. } => Some(text.clone()),
            _ => None,
        }
    }
}

/// What badVerb describes: the argument, or the reflect value being printed.
#[derive(Clone, Copy)]
enum Cur<'a> {
    Arg(&'a Arg),
    Str(&'a [u8]),
    Int(i64, &'static str),
    Ptr(&'static str),
}

const FAKE_ADDR: u64 = 0xc000010000;

#[derive(Default, Clone, Copy)]
struct Flags {
    plus: bool,
    minus: bool,
    sharp: bool,
    space: bool,
    zero: bool,
    plus_v: bool,
    sharp_v: bool,
    wid: i64,
    prec: i64,
    wid_present: bool,
    prec_present: bool,
}

struct Printer {
    buf: Vec<u8>,
    f: Flags,
    erroring: bool,
    wrap_errs: bool,
    reordered: bool,
    good_arg_num: bool,
}

fn rune_count(b: &[u8]) -> i64 {
    let mut n = 0;
    let mut i = 0;
    while i < b.len() {
        let (_, w, _) = gostr::decode_rune(&b[i..]);
        i += w.max(1);
        n += 1;
    }
    n
}

fn too_large(x: i64) -> bool {
    x > 1_000_000 || x < -1_000_000
}

/// fmt's parsenum: (num, isnum, newi).
fn parsenum(s: &[u8], start: usize, end: usize) -> (i64, bool, usize) {
    if start >= end {
        return (0, false, end);
    }
    let mut num = 0i64;
    let mut isnum = false;
    let mut i = start;
    while i < end && s[i].is_ascii_digit() {
        if too_large(num) {
            return (0, false, end);
        }
        num = num * 10 + (s[i] - b'0') as i64;
        isnum = true;
        i += 1;
    }
    (num, isnum, i)
}

/// fmt's parseArgNumber: (index, wid, ok).
fn parse_arg_number(format: &[u8]) -> (i64, usize, bool) {
    if format.len() < 3 {
        return (0, 1, false);
    }
    for i in 1..format.len() {
        if format[i] == b']' {
            let (width, ok, newi) = parsenum(format, 1, i);
            if !ok || newi != i {
                return (0, i + 1, false);
            }
            return (width - 1, i + 1, true);
        }
    }
    (0, 1, false)
}

impl Printer {
    fn write_padding(&mut self, n: i64) {
        if n <= 0 {
            return;
        }
        let pad = if self.f.zero && !self.f.minus {
            b'0'
        } else {
            b' '
        };
        self.buf.extend(std::iter::repeat(pad).take(n as usize));
    }

    fn pad(&mut self, b: &[u8]) {
        if !self.f.wid_present || self.f.wid == 0 {
            self.buf.extend_from_slice(b);
            return;
        }
        let width = self.f.wid - rune_count(b);
        if !self.f.minus {
            self.write_padding(width);
            self.buf.extend_from_slice(b);
        } else {
            self.buf.extend_from_slice(b);
            self.write_padding(width);
        }
    }

    fn truncate<'a>(&self, s: &'a [u8]) -> &'a [u8] {
        if self.f.prec_present {
            let mut n = self.f.prec;
            let mut i = 0;
            while i < s.len() {
                n -= 1;
                if n < 0 {
                    return &s[..i];
                }
                let (_, w, _) = gostr::decode_rune(&s[i..]);
                i += w.max(1);
            }
        }
        s
    }

    fn fmt_s(&mut self, s: &[u8]) {
        let s = self.truncate(s).to_vec();
        self.pad(&s);
    }

    fn fmt_sx(&mut self, s: &[u8], digits: &[u8; 17]) {
        let mut length = s.len() as i64;
        if self.f.prec_present && self.f.prec < length {
            length = self.f.prec;
        }
        let mut width = 2 * length;
        if width > 0 {
            if self.f.space {
                if self.f.sharp {
                    width *= 2;
                }
                width += length - 1;
            } else if self.f.sharp {
                width += 2;
            }
        } else {
            if self.f.wid_present {
                let w = self.f.wid;
                self.write_padding(w);
            }
            return;
        }
        if self.f.wid_present && self.f.wid > width && !self.f.minus {
            let w = self.f.wid - width;
            self.write_padding(w);
        }
        if self.f.sharp {
            self.buf.push(b'0');
            self.buf.push(digits[16]);
        }
        for i in 0..length as usize {
            if self.f.space && i > 0 {
                self.buf.push(b' ');
                if self.f.sharp {
                    self.buf.push(b'0');
                    self.buf.push(digits[16]);
                }
            }
            let c = s[i];
            self.buf.push(digits[(c >> 4) as usize]);
            self.buf.push(digits[(c & 15) as usize]);
        }
        if self.f.wid_present && self.f.wid > width && self.f.minus {
            let w = self.f.wid - width;
            self.write_padding(w);
        }
    }

    fn fmt_q(&mut self, s: &[u8]) {
        let s = self.truncate(s).to_vec();
        if self.f.sharp && gostr::can_backquote(&s) {
            let mut b = vec![b'`'];
            b.extend_from_slice(&s);
            b.push(b'`');
            self.pad_string(&b);
            return;
        }
        let q = if self.f.plus {
            gostr::quote_to_ascii(&s)
        } else {
            gostr::quote(&s)
        };
        self.pad(&q);
    }

    fn pad_string(&mut self, s: &[u8]) {
        // padString and pad differ only in how they count; both count runes.
        self.pad(s);
    }

    fn fmt_integer(&mut self, u: u64, base: u32, signed: bool, verb: char, digits: &[u8; 17]) {
        let negative = signed && (u as i64) < 0;
        let mut u = if negative {
            (u as i64).wrapping_neg() as u64
        } else {
            u
        };
        let mut prec: i64 = 0;
        if self.f.prec_present {
            prec = self.f.prec;
            if prec == 0 && u == 0 {
                let old = self.f.zero;
                self.f.zero = false;
                let w = self.f.wid;
                self.write_padding(w);
                self.f.zero = old;
                return;
            }
        } else if self.f.zero && !self.f.minus && self.f.wid_present {
            prec = self.f.wid;
            if negative || self.f.plus || self.f.space {
                prec -= 1;
            }
        }
        let mut out: Vec<u8> = Vec::new(); // reversed
        match base {
            10 => {
                while u >= 10 {
                    out.push(b'0' + (u % 10) as u8);
                    u /= 10;
                }
            }
            16 => {
                while u >= 16 {
                    out.push(digits[(u & 15) as usize]);
                    u >>= 4;
                }
            }
            8 => {
                while u >= 8 {
                    out.push(b'0' + (u & 7) as u8);
                    u >>= 3;
                }
            }
            _ => {
                while u >= 2 {
                    out.push(b'0' + (u & 1) as u8);
                    u >>= 1;
                }
            }
        }
        out.push(digits[u as usize]);
        while prec > out.len() as i64 {
            out.push(b'0');
        }
        if self.f.sharp {
            match base {
                2 => {
                    out.push(b'b');
                    out.push(b'0');
                }
                8 => {
                    if *out.last().unwrap() != b'0' {
                        out.push(b'0');
                    }
                }
                16 => {
                    out.push(digits[16]);
                    out.push(b'0');
                }
                _ => {}
            }
        }
        if verb == 'O' {
            out.push(b'o');
            out.push(b'0');
        }
        if negative {
            out.push(b'-');
        } else if self.f.plus {
            out.push(b'+');
        } else if self.f.space {
            out.push(b' ');
        }
        out.reverse();
        let old = self.f.zero;
        self.f.zero = false;
        self.pad(&out);
        self.f.zero = old;
    }

    fn fmt_unicode(&mut self, u: u64) {
        let mut prec: i64 = 4;
        if self.f.prec_present && self.f.prec > 4 {
            prec = self.f.prec;
        }
        let mut tail: Vec<u8> = Vec::new();
        if self.f.sharp && u <= 0x10FFFF {
            if let Some(c) = char::from_u32(u as u32) {
                if gostr::is_print(c) {
                    tail.extend_from_slice(b" '");
                    gostr::push_rune(&mut tail, c);
                    tail.push(b'\'');
                }
            }
        }
        let mut hex: Vec<u8> = Vec::new();
        let mut v = u;
        while v >= 16 {
            hex.push(UDIGITS[(v & 15) as usize]);
            prec -= 1;
            v >>= 4;
        }
        hex.push(UDIGITS[v as usize]);
        prec -= 1;
        while prec > 0 {
            hex.push(b'0');
            prec -= 1;
        }
        hex.reverse();
        let mut b = b"U+".to_vec();
        b.extend_from_slice(&hex);
        b.extend_from_slice(&tail);
        let old = self.f.zero;
        self.f.zero = false;
        self.pad(&b);
        self.f.zero = old;
    }

    fn fmt_c(&mut self, c: u64) {
        let r = if c > 0x10FFFF { 0xFFFD } else { c as u32 };
        let ch = char::from_u32(r).unwrap_or(gostr::RUNE_ERROR);
        let mut b = Vec::new();
        gostr::push_rune(&mut b, ch);
        self.pad(&b);
    }

    fn fmt_qc(&mut self, c: u64) {
        let r = if c > 0x10FFFF { 0xFFFD } else { c as u32 };
        let q = gostr::quote_rune(r, self.f.plus);
        self.pad(&q);
    }

    fn fmt0x64(&mut self, v: u64, leading0x: bool) {
        let sharp = self.f.sharp;
        self.f.sharp = leading0x;
        self.fmt_integer(v, 16, false, 'v', LDIGITS);
        self.f.sharp = sharp;
    }

    fn bad_verb(&mut self, verb: char, cur: Cur) {
        self.erroring = true;
        self.buf.extend_from_slice(b"%!");
        gostr::push_rune(&mut self.buf, verb);
        self.buf.push(b'(');
        match cur {
            Cur::Arg(a) => {
                self.buf.extend_from_slice(a.type_string().as_bytes());
                self.buf.push(b'=');
                self.print_arg(a, 'v');
            }
            Cur::Str(s) => {
                self.buf.extend_from_slice(b"string=");
                self.fmt_string(s, 'v', cur);
            }
            Cur::Int(v, ty) => {
                self.buf.extend_from_slice(ty.as_bytes());
                self.buf.push(b'=');
                self.fmt_int_value(v, 'v', cur);
            }
            Cur::Ptr(ty) => {
                self.buf.extend_from_slice(ty.as_bytes());
                self.buf.push(b'=');
                self.fmt_pointer(true, 'v', cur);
            }
        }
        self.buf.push(b')');
        self.erroring = false;
    }

    fn fmt_string(&mut self, v: &[u8], verb: char, cur: Cur) {
        match verb {
            'v' => {
                if self.f.sharp_v {
                    self.fmt_q(v)
                } else {
                    self.fmt_s(v)
                }
            }
            's' => self.fmt_s(v),
            'x' => self.fmt_sx(v, LDIGITS),
            'X' => self.fmt_sx(v, UDIGITS),
            'q' => self.fmt_q(v),
            _ => self.bad_verb(verb, cur),
        }
    }

    fn fmt_int_value(&mut self, v: i64, verb: char, cur: Cur) {
        let u = v as u64;
        match verb {
            'v' | 'd' => self.fmt_integer(u, 10, true, verb, LDIGITS),
            'b' => self.fmt_integer(u, 2, true, verb, LDIGITS),
            'o' | 'O' => self.fmt_integer(u, 8, true, verb, LDIGITS),
            'x' => self.fmt_integer(u, 16, true, verb, LDIGITS),
            'X' => self.fmt_integer(u, 16, true, verb, UDIGITS),
            'c' => self.fmt_c(u),
            'q' => self.fmt_qc(u),
            'U' => self.fmt_unicode(u),
            _ => self.bad_verb(verb, cur),
        }
    }

    /// fmtPointer for a non-nil pointer (the address is a stand-in).
    fn fmt_pointer(&mut self, is_ptr: bool, verb: char, cur: Cur) {
        if !is_ptr {
            self.bad_verb(verb, cur);
            return;
        }
        let ty = match cur {
            Cur::Arg(a) => a.type_string(),
            Cur::Ptr(t) => t,
            _ => "",
        };
        match verb {
            'v' => {
                if self.f.sharp_v {
                    self.buf.push(b'(');
                    self.buf.extend_from_slice(ty.as_bytes());
                    self.buf.extend_from_slice(b")(");
                    self.fmt0x64(FAKE_ADDR, true);
                    self.buf.push(b')');
                } else {
                    let lead = !self.f.sharp;
                    self.fmt0x64(FAKE_ADDR, lead);
                }
            }
            'p' => {
                let lead = !self.f.sharp;
                self.fmt0x64(FAKE_ADDR, lead);
            }
            'b' | 'o' | 'd' | 'x' | 'X' => {
                let digits = if verb == 'X' { UDIGITS } else { LDIGITS };
                let base = match verb {
                    'b' => 2,
                    'o' => 8,
                    'd' => 10,
                    _ => 16,
                };
                self.fmt_integer(FAKE_ADDR, base, false, verb, digits);
            }
            _ => self.bad_verb(verb, cur),
        }
    }

    fn handle_methods(&mut self, a: &Arg, verb: char) -> bool {
        if self.erroring {
            return false;
        }
        let mut verb = verb;
        if verb == 'w' {
            if !a.is_error() || !self.wrap_errs {
                self.bad_verb('w', Cur::Arg(a));
                return true;
            }
            verb = 'v';
        }
        if self.f.sharp_v {
            return false; // none of these types is a GoStringer
        }
        if matches!(verb, 'v' | 's' | 'x' | 'X' | 'q') {
            if let Some(t) = a.method_text() {
                self.fmt_string(&t, verb, Cur::Arg(a));
                return true;
            }
        }
        false
    }

    fn print_arg(&mut self, a: &Arg, verb: char) {
        match verb {
            'T' => {
                self.fmt_s(a.type_string().as_bytes());
                return;
            }
            'p' => {
                let is_ptr = matches!(
                    a,
                    Arg::ErrString(_) | Arg::NumError { .. } | Arg::Node { .. }
                );
                self.fmt_pointer(is_ptr, 'p', Cur::Arg(a));
                return;
            }
            _ => {}
        }
        match a {
            Arg::Str(s) => self.fmt_string(s, verb, Cur::Arg(a)),
            Arg::Int(i) => self.fmt_int_value(*i, verb, Cur::Arg(a)),
            _ => {
                if !self.handle_methods(a, verb) {
                    self.print_value(a, verb);
                }
            }
        }
    }

    fn field_name(&mut self, name: &str) {
        if self.f.plus_v || self.f.sharp_v {
            self.buf.extend_from_slice(name.as_bytes());
            self.buf.push(b':');
        }
    }

    fn field_sep(&mut self) {
        if self.f.sharp_v {
            self.buf.extend_from_slice(b", ");
        } else {
            self.buf.push(b' ');
        }
    }

    /// printValue at depth 0 for the non-basic argument types.
    fn print_value(&mut self, a: &Arg, verb: char) {
        match a {
            Arg::Item(it) => {
                if self.f.sharp_v {
                    self.buf.extend_from_slice(b"parse.item");
                }
                self.buf.push(b'{');
                self.field_name("typ");
                self.fmt_int_value(it.typ, verb, Cur::Int(it.typ, "parse.itemType"));
                self.field_sep();
                self.field_name("pos");
                self.fmt_int_value(it.pos, verb, Cur::Int(it.pos, "parse.Pos"));
                self.field_sep();
                self.field_name("val");
                self.fmt_string(&it.val, verb, Cur::Str(&it.val));
                self.field_sep();
                self.field_name("line");
                self.fmt_int_value(it.line, verb, Cur::Int(it.line, "int"));
                self.buf.push(b'}');
            }
            Arg::ErrString(s) => {
                self.buf.push(b'&');
                if self.f.sharp_v {
                    self.buf.extend_from_slice(b"errors.errorString");
                }
                self.buf.push(b'{');
                self.field_name("s");
                self.fmt_string(s, verb, Cur::Str(s));
                self.buf.push(b'}');
            }
            Arg::NumError { func, num, err } => {
                self.buf.push(b'&');
                if self.f.sharp_v {
                    self.buf.extend_from_slice(b"strconv.NumError");
                }
                self.buf.push(b'{');
                self.field_name("Func");
                self.fmt_string(func, verb, Cur::Str(func));
                self.field_sep();
                self.field_name("Num");
                self.fmt_string(num, verb, Cur::Str(num));
                self.field_sep();
                self.field_name("Err");
                // An exported interface field: its Error method applies.
                let inner = Arg::ErrString(err.clone());
                if !self.handle_methods(&inner, verb) {
                    self.fmt_pointer(true, verb, Cur::Ptr("*errors.errorString"));
                }
                self.buf.push(b'}');
            }
            Arg::Node {
                ty, typ, pos, line, ..
            } => {
                self.buf.push(b'&');
                if self.f.sharp_v {
                    self.buf.extend_from_slice(ty[1..].as_bytes());
                }
                self.buf.push(b'{');
                self.field_name("NodeType");
                self.fmt_int_value(*typ, verb, Cur::Int(*typ, "parse.NodeType"));
                self.field_sep();
                self.field_name("Pos");
                self.fmt_int_value(*pos, verb, Cur::Int(*pos, "parse.Pos"));
                self.field_sep();
                self.field_name("tr");
                self.fmt_pointer(true, verb, Cur::Ptr("*parse.Tree"));
                if let Some(l) = line {
                    self.field_sep();
                    self.field_name("Line");
                    self.fmt_int_value(*l, verb, Cur::Int(*l, "int"));
                }
                self.buf.push(b'}');
            }
            Arg::Str(_) | Arg::Int(_) => unreachable!("basic types print directly"),
        }
    }

    fn arg_number(
        &mut self,
        arg_num: usize,
        format: &[u8],
        i: usize,
        num_args: usize,
    ) -> (usize, usize, bool) {
        if format.len() <= i || format[i] != b'[' {
            return (arg_num, i, false);
        }
        self.reordered = true;
        let (index, wid, ok) = parse_arg_number(&format[i..]);
        if ok && 0 <= index && (index as usize) < num_args {
            return (index as usize, i + wid, true);
        }
        self.good_arg_num = false;
        (arg_num, i + wid, ok)
    }

    fn do_printf(&mut self, format: &[u8], a: &[Arg]) {
        let end = format.len();
        let mut arg_num = 0usize;
        let mut after_index;
        self.reordered = false;
        let mut i = 0;
        'format_loop: while i < end {
            self.good_arg_num = true;
            let lasti = i;
            while i < end && format[i] != b'%' {
                i += 1;
            }
            if i > lasti {
                self.buf.extend_from_slice(&format[lasti..i]);
            }
            if i >= end {
                break;
            }
            i += 1;
            self.f = Flags::default();
            while i < end {
                let c = format[i];
                match c {
                    b'#' => self.f.sharp = true,
                    b'0' => self.f.zero = true,
                    b'+' => self.f.plus = true,
                    b'-' => self.f.minus = true,
                    b' ' => self.f.space = true,
                    _ => {
                        if c.is_ascii_lowercase() && arg_num < a.len() {
                            if c == b'w' || c == b'v' {
                                self.f.sharp_v = self.f.sharp;
                                self.f.sharp = false;
                                self.f.plus_v = self.f.plus;
                                self.f.plus = false;
                            }
                            self.print_arg(&a[arg_num], c as char);
                            arg_num += 1;
                            i += 1;
                            continue 'format_loop;
                        }
                        break;
                    }
                }
                i += 1;
            }

            let r = self.arg_number(arg_num, format, i, a.len());
            arg_num = r.0;
            i = r.1;
            after_index = r.2;

            if i < end && format[i] == b'*' {
                i += 1;
                let (num, is_int, next) = int_from_arg(a, arg_num);
                self.f.wid = num;
                self.f.wid_present = is_int;
                arg_num = next;
                if !self.f.wid_present {
                    self.buf.extend_from_slice(b"%!(BADWIDTH)");
                }
                if self.f.wid < 0 {
                    self.f.wid = -self.f.wid;
                    self.f.minus = true;
                    self.f.zero = false;
                }
                after_index = false;
            } else {
                let (num, isnum, ni) = parsenum(format, i, end);
                self.f.wid = num;
                self.f.wid_present = isnum;
                i = ni;
                if after_index && self.f.wid_present {
                    self.good_arg_num = false;
                }
            }

            if i + 1 < end && format[i] == b'.' {
                i += 1;
                if after_index {
                    self.good_arg_num = false;
                }
                let r = self.arg_number(arg_num, format, i, a.len());
                arg_num = r.0;
                i = r.1;
                after_index = r.2;
                if i < end && format[i] == b'*' {
                    i += 1;
                    let (num, is_int, next) = int_from_arg(a, arg_num);
                    self.f.prec = num;
                    self.f.prec_present = is_int;
                    arg_num = next;
                    if self.f.prec < 0 {
                        self.f.prec = 0;
                        self.f.prec_present = false;
                    }
                    if !self.f.prec_present {
                        self.buf.extend_from_slice(b"%!(BADPREC)");
                    }
                    after_index = false;
                } else {
                    let (num, isnum, ni) = parsenum(format, i, end);
                    self.f.prec = num;
                    self.f.prec_present = isnum;
                    i = ni;
                    if !self.f.prec_present {
                        self.f.prec = 0;
                        self.f.prec_present = true;
                    }
                }
            }

            if !after_index {
                let r = self.arg_number(arg_num, format, i, a.len());
                arg_num = r.0;
                i = r.1;
            }

            if i >= end {
                self.buf.extend_from_slice(b"%!(NOVERB)");
                break;
            }

            let (verb, size, _) = gostr::decode_rune(&format[i..]);
            i += size;

            if verb == '%' {
                self.buf.push(b'%');
            } else if !self.good_arg_num {
                self.buf.extend_from_slice(b"%!");
                gostr::push_rune(&mut self.buf, verb);
                self.buf.extend_from_slice(b"(BADINDEX)");
            } else if arg_num >= a.len() {
                self.buf.extend_from_slice(b"%!");
                gostr::push_rune(&mut self.buf, verb);
                self.buf.extend_from_slice(b"(MISSING)");
            } else {
                if verb == 'w' || verb == 'v' {
                    self.f.sharp_v = self.f.sharp;
                    self.f.sharp = false;
                    self.f.plus_v = self.f.plus;
                    self.f.plus = false;
                }
                self.print_arg(&a[arg_num], verb);
                arg_num += 1;
            }
        }

        if !self.reordered && arg_num < a.len() {
            self.f = Flags::default();
            self.buf.extend_from_slice(b"%!(EXTRA ");
            for (k, arg) in a[arg_num..].iter().enumerate() {
                if k > 0 {
                    self.buf.extend_from_slice(b", ");
                }
                self.buf.extend_from_slice(arg.type_string().as_bytes());
                self.buf.push(b'=');
                self.print_arg(arg, 'v');
            }
            self.buf.push(b')');
        }
    }
}

const LDIGITS: &[u8; 17] = b"0123456789abcdefx";
const UDIGITS: &[u8; 17] = b"0123456789ABCDEFX";

fn int_from_arg(a: &[Arg], arg_num: usize) -> (i64, bool, usize) {
    let mut new_arg_num = arg_num;
    let mut num = 0;
    let mut is_int = false;
    if arg_num < a.len() {
        if let Arg::Int(n) = a[arg_num] {
            num = n;
            is_int = true;
        }
        new_arg_num = arg_num + 1;
        if too_large(num) {
            num = 0;
            is_int = false;
        }
    }
    (num, is_int, new_arg_num)
}

/// fmt.Sprintf.
pub fn sprintf(format: &[u8], args: &[Arg]) -> Vec<u8> {
    let mut p = Printer {
        buf: Vec::new(),
        f: Flags::default(),
        erroring: false,
        wrap_errs: false,
        reordered: false,
        good_arg_num: true,
    };
    p.do_printf(format, args);
    p.buf
}

/// fmt.Errorf(...).Error(): Sprintf, except %w accepts an error argument.
pub fn errorf(format: &[u8], args: &[Arg]) -> Vec<u8> {
    let mut p = Printer {
        buf: Vec::new(),
        f: Flags::default(),
        erroring: false,
        wrap_errs: true,
        reordered: false,
        good_arg_num: true,
    };
    p.do_printf(format, args);
    p.buf
}

#[cfg(test)]
mod tests {
    use super::*;

    fn s(f: &str, a: &[Arg]) -> String {
        String::from_utf8(sprintf(f.as_bytes(), a)).unwrap()
    }

    fn item() -> Arg {
        Arg::Item(ItemArg {
            typ: 12,
            pos: 3,
            val: b"x".to_vec(),
            line: 1,
            text: b"\"x\"".to_vec(),
        })
    }

    #[test]
    fn basics() {
        assert_eq!(
            s(
                "a %s b %d %q",
                &[
                    Arg::Str(b"x".to_vec()),
                    Arg::Int(-7),
                    Arg::Str(b"y".to_vec())
                ]
            ),
            "a x b -7 \"y\""
        );
        assert_eq!(
            s(
                "%5s|%-5s|%.1s|%05d|%x|%X|%#x|%+d|% d",
                &[
                    Arg::Str(b"ab".to_vec()),
                    Arg::Str(b"ab".to_vec()),
                    Arg::Str(b"ab".to_vec()),
                    Arg::Int(-42),
                    Arg::Str(b"hi".to_vec()),
                    Arg::Int(255),
                    Arg::Int(255),
                    Arg::Int(3),
                    Arg::Int(3)
                ]
            ),
            "   ab|ab   |a|-0042|6869|FF|0xff|+3| 3"
        );
        assert_eq!(s("%d", &[Arg::Str(b"x".to_vec())]), "%!d(string=x)");
        assert_eq!(s("%s %s", &[Arg::Str(b"x".to_vec())]), "x %!s(MISSING)");
        assert_eq!(
            s("%s", &[Arg::Str(b"x".to_vec()), Arg::Int(2)]),
            "x%!(EXTRA int=2)"
        );
        assert_eq!(s("%", &[]), "%!(NOVERB)");
        assert_eq!(
            s(
                "%[2]s %[1]s",
                &[Arg::Str(b"a".to_vec()), Arg::Str(b"b".to_vec())]
            ),
            "b a"
        );
        assert_eq!(s("%[3]s", &[Arg::Str(b"a".to_vec())]), "%!s(BADINDEX)");
        assert_eq!(
            s(
                "%#U %U %c",
                &[Arg::Int(0x60), Arg::Int(0x1F600), Arg::Int(65)]
            ),
            "U+0060 '`' U+1F600 A"
        );
        assert_eq!(
            s(
                "%*d|%.*s",
                &[
                    Arg::Int(4),
                    Arg::Int(7),
                    Arg::Int(1),
                    Arg::Str(b"xyz".to_vec())
                ]
            ),
            "   7|x"
        );
        assert_eq!(
            s("%T %T", &[item(), Arg::ErrString(b"e".to_vec())]),
            "parse.item *errors.errorString"
        );
    }

    #[test]
    fn stringers_and_structs() {
        assert_eq!(
            s("%s %v %q", &[item(), item(), item()]),
            "\"x\" \"x\" \"\\\"x\\\"\""
        );
        assert_eq!(s("%d", &[item()]), "{12 3 %!d(string=x) 1}");
        assert_eq!(s("%+d", &[item()]), "{+12 +3 %!d(string=x) +1}");
        assert_eq!(
            s("%#v", &[item()]),
            "parse.item{typ:12, pos:3, val:\"x\", line:1}"
        );
        assert_eq!(
            s("%d", &[Arg::ErrString(b"bad".to_vec())]),
            "&{%!d(string=bad)}"
        );
        assert_eq!(s("%w", &[Arg::Str(b"x".to_vec())]), "%!w(string=x)");
        assert_eq!(
            String::from_utf8(errorf(b"%w", &[Arg::ErrString(b"bad".to_vec())])).unwrap(),
            "bad"
        );
        assert_eq!(s("%w", &[item()]), "%!w(parse.item={12 3 x 1})");
    }
}
