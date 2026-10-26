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

//! Whether Python 3.12's `re.compile(pattern)` takes a str pattern, which is
//! what jsonschema's "regex" format asks: a port of re/_parser.py's parse, with
//! the one check re/_compiler.py adds (a look-behind must be of fixed width).
//! Nothing is matched. What is kept is what the parser accepts, what it
//! refuses with re.error (its message and position, which a traceback
//! shows), and what it crashes on (OverflowError, ValueError), in the order
//! it finds them.
//! `\N{name}` is checked as unicodedata.lookup checks it: Hangul syllables
//! and CJK unified ideographs by rule, every other name and alias by its
//! hash in src/unicode_tables.rs.

use crate::pystr;
use std::collections::HashMap;

/// How `re.compile` ends when it does not return a pattern.
#[derive(Debug, PartialEq)]
pub enum Refusal {
    /// re.error, which the "regex" format catches: `str()` of it.
    Error(String),
    /// Any other exception, which escapes: (class, message).
    Crash(&'static str, &'static str),
}

type R<T> = Result<T, Refusal>;

const MAXREPEAT: u128 = 4294967295;
const MAXWIDTH: u128 = 1 << 64;
const MAXCODE: u128 = (1 << 32) - 1;
const MAXGROUPS: u128 = 1073741823;

const F_IGNORECASE: u32 = 2;
const F_LOCALE: u32 = 4;
const F_MULTILINE: u32 = 8;
const F_DOTALL: u32 = 16;
const F_UNICODE: u32 = 32;
const F_VERBOSE: u32 = 64;
const F_DEBUG: u32 = 128;
const F_ASCII: u32 = 256;
const F_TEMPLATE: u32 = 1;
const TYPE_FLAGS: u32 = F_ASCII | F_LOCALE | F_UNICODE;
const GLOBAL_FLAGS: u32 = F_DEBUG | F_TEMPLATE;

fn flag(c: &str) -> Option<u32> {
    Some(match c {
        "i" => F_IGNORECASE,
        "L" => F_LOCALE,
        "m" => F_MULTILINE,
        "s" => F_DOTALL,
        "x" => F_VERBOSE,
        "a" => F_ASCII,
        "t" => F_TEMPLATE,
        "u" => F_UNICODE,
        _ => return None,
    })
}

/// re.error's text: the message, where, and the line and column when the
/// pattern has more than one line.
fn error_at(pattern: &[char], msg: &str, pos: Option<usize>) -> Refusal {
    let pos = match pos {
        None => return Refusal::Error(msg.to_string()),
        Some(p) => p,
    };
    let mut text = format!("{} at position {}", msg, pos);
    if pattern.contains(&'\n') {
        let before = &pattern[..pos.min(pattern.len())];
        let lineno = before.iter().filter(|&&c| c == '\n').count() + 1;
        let colno = match before.iter().rposition(|&c| c == '\n') {
            Some(nl) => pos - nl,
            None => pos + 1,
        };
        text = format!("{} (line {}, column {})", text, lineno, colno);
    }
    Refusal::Error(text)
}

#[derive(Clone, Debug)]
enum Item {
    /// One character: a literal, a class, `.`.
    Unit,
    At,
    Repeat(u128, u128, Vec<Item>),
    Subpattern(Option<usize>, u32, u32, Vec<Item>),
    Atomic(Vec<Item>),
    Branch(Vec<Vec<Item>>),
    Assert(i32, Vec<Item>),
    GroupRef(usize),
    GroupRefExists(Vec<Item>, Option<Vec<Item>>),
}

struct State {
    flags: u32,
    groupdict: HashMap<String, usize>,
    groupwidths: Vec<Option<(u128, u128)>>,
    lookbehindgroups: Option<usize>,
    grouprefpos: Vec<(usize, usize)>,
}

impl State {
    fn groups(&self) -> usize {
        self.groupwidths.len()
    }

    fn checkgroup(&self, gid: usize) -> bool {
        gid < self.groups() && self.groupwidths[gid].is_some()
    }

    fn checklookbehindgroup(&self, gid: usize, source: &Tokenizer) -> R<()> {
        if let Some(lb) = self.lookbehindgroups {
            if !self.checkgroup(gid) {
                return Err(source.error("cannot refer to an open group", 0));
            }
            if gid >= lb {
                return Err(source.error(
                    "cannot refer to group defined in the same lookbehind subpattern",
                    0,
                ));
            }
        }
        Ok(())
    }

    fn width(&self, items: &[Item]) -> (u128, u128) {
        let (mut lo, mut hi) = (0u128, 0u128);
        for item in items {
            match item {
                Item::Branch(branches) => {
                    let (mut i, mut j) = (MAXWIDTH, 0);
                    for b in branches {
                        let (l, h) = self.width(b);
                        i = i.min(l);
                        j = j.max(h);
                    }
                    lo += i;
                    hi += j;
                }
                Item::Atomic(p) | Item::Subpattern(_, _, _, p) => {
                    let (i, j) = self.width(p);
                    lo += i;
                    hi += j;
                }
                Item::Repeat(min, max, p) => {
                    let (i, j) = self.width(p);
                    lo += i * min;
                    if *max == MAXREPEAT && j > 0 {
                        hi = MAXWIDTH;
                    } else {
                        hi += j * max;
                    }
                }
                Item::Unit => {
                    lo += 1;
                    hi += 1;
                }
                Item::GroupRef(g) => {
                    let (i, j) = self.groupwidths[*g].unwrap_or((0, 0));
                    lo += i;
                    hi += j;
                }
                Item::GroupRefExists(yes, no) => {
                    let (mut i, mut j) = self.width(yes);
                    match no {
                        Some(no) => {
                            let (l, h) = self.width(no);
                            i = i.min(l);
                            j = j.max(h);
                        }
                        None => i = 0,
                    }
                    lo += i;
                    hi += j;
                }
                Item::At | Item::Assert(..) => {}
            }
            lo = lo.min(MAXWIDTH * 4);
            hi = hi.min(MAXWIDTH * 4);
        }
        (lo.min(MAXWIDTH), hi.min(MAXWIDTH))
    }
}

/// re/_parser.py's Tokenizer: a token is a character, or a backslash and the
/// character after it.
struct Tokenizer {
    s: Vec<char>,
    index: usize,
    next: Option<String>,
}

fn clen(s: &str) -> usize {
    s.chars().count()
}

impl Tokenizer {
    fn new(pattern: &str) -> R<Tokenizer> {
        let mut t = Tokenizer {
            s: pattern.chars().collect(),
            index: 0,
            next: None,
        };
        t.advance()?;
        Ok(t)
    }

    fn error(&self, msg: &str, offset: usize) -> Refusal {
        error_at(&self.s, msg, Some(self.tell() - offset))
    }

    fn advance(&mut self) -> R<()> {
        let mut index = self.index;
        let c = match self.s.get(index) {
            None => {
                self.next = None;
                return Ok(());
            }
            Some(&c) => c,
        };
        let mut token = c.to_string();
        if c == '\\' {
            index += 1;
            match self.s.get(index) {
                None => {
                    return Err(error_at(
                        &self.s,
                        "bad escape (end of pattern)",
                        Some(self.s.len() - 1),
                    ));
                }
                Some(&d) => token.push(d),
            }
        }
        self.index = index + 1;
        self.next = Some(token);
        Ok(())
    }

    fn next_is(&self, s: &str) -> bool {
        self.next.as_deref() == Some(s)
    }

    fn next_in(&self, set: fn(&str) -> bool) -> bool {
        self.next.as_deref().map(set).unwrap_or(false)
    }

    fn matches(&mut self, s: &str) -> R<bool> {
        if self.next_is(s) {
            self.advance()?;
            Ok(true)
        } else {
            Ok(false)
        }
    }

    fn get(&mut self) -> R<Option<String>> {
        let this = self.next.clone();
        self.advance()?;
        Ok(this)
    }

    fn getwhile(&mut self, n: usize, set: fn(&str) -> bool) -> R<String> {
        let mut result = String::new();
        for _ in 0..n {
            match self.next.clone() {
                Some(c) if set(&c) => {
                    result.push_str(&c);
                    self.advance()?;
                }
                _ => break,
            }
        }
        Ok(result)
    }

    fn getuntil(&mut self, terminator: &str, name: &str) -> R<String> {
        let mut result = String::new();
        loop {
            let c = self.next.clone();
            self.advance()?;
            match c {
                None => {
                    if result.is_empty() {
                        return Err(self.error(&format!("missing {}", name), 0));
                    }
                    return Err(self.error(
                        &format!("missing {}, unterminated name", terminator),
                        clen(&result),
                    ));
                }
                Some(c) if c == terminator => {
                    if result.is_empty() {
                        return Err(self.error(&format!("missing {}", name), 1));
                    }
                    return Ok(result);
                }
                Some(c) => result.push_str(&c),
            }
        }
    }

    fn tell(&self) -> usize {
        self.index - self.next.as_ref().map(|n| clen(n)).unwrap_or(0)
    }

    fn seek(&mut self, index: usize) -> R<()> {
        self.index = index;
        self.advance()
    }

    fn checkgroupname(&self, name: &str, offset: usize) -> R<()> {
        if pystr::is_identifier(name) {
            Ok(())
        } else {
            Err(self.error(
                &format!("bad character in group name {}", pystr::repr_str(name)),
                clen(name) + offset,
            ))
        }
    }
}

fn digits(c: &str) -> bool {
    c.len() == 1 && c.as_bytes()[0].is_ascii_digit()
}

fn octdigits(c: &str) -> bool {
    c.len() == 1 && (b'0'..=b'7').contains(&c.as_bytes()[0])
}

fn hexdigits(c: &str) -> bool {
    c.len() == 1 && c.as_bytes()[0].is_ascii_hexdigit()
}

/// What an escape in a pattern or a class stands for.
enum Escape {
    Literal(u32),
    /// A class such as `\d`.
    In,
    At,
    GroupRef(usize),
}

/// The escapes `\x`, `\u`, `\U`, `\N`, read the same in a class and out.
fn hex_escape(source: &mut Tokenizer, escape: &str, c: &str) -> R<Option<u32>> {
    let (n, want) = match c {
        "x" => (2, 4),
        "u" => (4, 6),
        "U" => (8, 10),
        "N" => {
            if !source.matches("{")? {
                return Err(source.error("missing {", 0));
            }
            let charname = source.getuntil("}", "character name")?;
            return match lookup(&charname) {
                Some(c) => Ok(Some(c)),
                None => Err(source.error(
                    &format!("undefined character name {}", pystr::repr_str(&charname)),
                    clen(&charname) + 4,
                )),
            };
        }
        _ => return Ok(None),
    };
    let more = source.getwhile(n, hexdigits)?;
    let full = format!("{}{}", escape, more);
    if clen(&full) != want {
        return Err(source.error(&format!("incomplete escape {}", full), clen(&full)));
    }
    let value = u32::from_str_radix(&more, 16).unwrap();
    if c == "U" && value > 0x10FFFF {
        return Err(source.error(&format!("bad escape {}", full), clen(&full)));
    }
    Ok(Some(value))
}

const JAMO_L: [&str; 19] = [
    "G", "GG", "N", "D", "DD", "R", "M", "B", "BB", "S", "SS", "", "J", "JJ", "C", "K", "T", "P",
    "H",
];
const JAMO_V: [&str; 21] = [
    "A", "AE", "YA", "YAE", "EO", "E", "YEO", "YE", "O", "WA", "WAE", "OE", "YO", "U", "WEO", "WE",
    "WI", "YU", "EU", "YI", "I",
];
const JAMO_T: [&str; 28] = [
    "", "G", "GG", "GS", "N", "NJ", "NH", "D", "L", "LG", "LM", "LB", "LS", "LT", "LP", "LH", "M",
    "B", "BS", "S", "SS", "NG", "J", "C", "K", "T", "P", "H",
];

/// CPython's find_syllable: the longest jamo `text` starts with, first of
/// equals; (length, index), index None when none does.
fn find_syllable(text: &[u8], table: &[&str]) -> (usize, Option<usize>) {
    let mut len: isize = -1;
    let mut pos = None;
    for (i, s) in table.iter().enumerate() {
        let n = s.len() as isize;
        if n <= len {
            continue;
        }
        if text.starts_with(s.as_bytes()) {
            len = n;
            pos = Some(i);
        }
    }
    (len.max(0) as usize, pos)
}

/// Whether `unicodedata.lookup(name)` gives one character (CPython's _getcode).
pub fn names_a_character(name: &str) -> bool {
    lookup(name).is_some()
}

/// The character `unicodedata.lookup(name)` gives, when it is one.
pub fn lookup(name: &str) -> Option<u32> {
    let bytes = name.as_bytes();
    if bytes.starts_with(b"HANGUL SYLLABLE ") {
        let mut at = 16;
        let (n, l) = find_syllable(&bytes[at..], &JAMO_L);
        at += n;
        let (n, v) = find_syllable(&bytes[at..], &JAMO_V);
        at += n;
        let (n, t) = find_syllable(&bytes[at..], &JAMO_T);
        at += n;
        return match (l, v, t) {
            (Some(l), Some(v), Some(t)) if at == bytes.len() => {
                Some(0xAC00 + ((l * 21 + v) * 28 + t) as u32)
            }
            _ => None,
        };
    }
    if bytes.starts_with(b"CJK UNIFIED IDEOGRAPH-") {
        let hex = &bytes[22..];
        if hex.len() != 4 && hex.len() != 5 {
            return None;
        }
        if !hex
            .iter()
            .all(|b| b.is_ascii_digit() || (b'A'..=b'F').contains(b))
        {
            return None;
        }
        let v = u32::from_str_radix(std::str::from_utf8(hex).unwrap(), 16).unwrap();
        let ideograph = crate::unicode_tables::CJK_UNIFIED
            .iter()
            .any(|&(lo, hi)| lo <= v && v <= hi);
        return if ideograph { Some(v) } else { None };
    }
    let mut h: u64 = 0xCBF29CE484222325;
    for b in bytes {
        h = (h ^ b.to_ascii_uppercase() as u64).wrapping_mul(0x100000001B3);
    }
    let table = crate::unicode_tables::NAME_HASHES.as_bytes();
    const ENTRY: usize = 22;
    let (mut lo, mut hi) = (0usize, table.len() / ENTRY);
    while lo < hi {
        let mid = (lo + hi) / 2;
        let at = std::str::from_utf8(&table[mid * ENTRY..mid * ENTRY + 16]).unwrap();
        let v = u64::from_str_radix(at, 16).unwrap();
        if v == h {
            let cp = std::str::from_utf8(&table[mid * ENTRY + 16..mid * ENTRY + ENTRY]).unwrap();
            return Some(u32::from_str_radix(cp, 16).unwrap());
        }
        if v < h {
            lo = mid + 1;
        } else {
            hi = mid;
        }
    }
    None
}

fn simple_escape(escape: &str) -> Option<u32> {
    Some(match escape {
        "\\a" => 7,
        "\\b" => 8,
        "\\f" => 12,
        "\\n" => 10,
        "\\r" => 13,
        "\\t" => 9,
        "\\v" => 11,
        "\\\\" => 92,
        _ => return None,
    })
}

fn category(escape: &str) -> Option<Escape> {
    match escape {
        "\\A" | "\\b" | "\\B" | "\\Z" => Some(Escape::At),
        "\\d" | "\\D" | "\\s" | "\\S" | "\\w" | "\\W" => Some(Escape::In),
        _ => None,
    }
}

fn second(escape: &str) -> String {
    escape.chars().skip(1).take(1).collect()
}

fn plain_escape(source: &Tokenizer, escape: &str, c: &str) -> R<Escape> {
    if clen(escape) == 2 {
        if c.chars().all(|x| x.is_ascii_alphabetic()) {
            return Err(source.error(&format!("bad escape {}", escape), clen(escape)));
        }
        return Ok(Escape::Literal(c.chars().next().unwrap() as u32));
    }
    Err(source.error(&format!("bad escape {}", escape), clen(escape)))
}

fn class_escape(source: &mut Tokenizer, escape: &str) -> R<Escape> {
    if let Some(v) = simple_escape(escape) {
        return Ok(Escape::Literal(v));
    }
    if let Some(Escape::In) = category(escape) {
        return Ok(Escape::In);
    }
    let c = second(escape);
    if let Some(v) = hex_escape(source, escape, &c)? {
        return Ok(Escape::Literal(v));
    }
    if octdigits(&c) {
        let more = source.getwhile(2, octdigits)?;
        let full = format!("{}{}", escape, more);
        let value = u32::from_str_radix(&format!("{}{}", c, more), 8).unwrap();
        if value > 0o377 {
            return Err(source.error(
                &format!("octal escape value {} outside of range 0-0o377", full),
                clen(&full),
            ));
        }
        return Ok(Escape::Literal(value));
    }
    if digits(&c) {
        return Err(source.error(&format!("bad escape {}", escape), clen(escape)));
    }
    plain_escape(source, escape, &c)
}

fn escape(source: &mut Tokenizer, escape: &str, state: &State) -> R<Escape> {
    if let Some(code) = category(escape) {
        return Ok(code);
    }
    if let Some(v) = simple_escape(escape) {
        return Ok(Escape::Literal(v));
    }
    let c = second(escape);
    if let Some(v) = hex_escape(source, escape, &c)? {
        return Ok(Escape::Literal(v));
    }
    if c == "0" {
        let more = source.getwhile(2, octdigits)?;
        return Ok(Escape::Literal(
            u32::from_str_radix(&format!("0{}", more), 8).unwrap(),
        ));
    }
    if digits(&c) {
        let mut text = escape.to_string();
        if source.next_in(digits) {
            text.push_str(&source.get()?.unwrap());
            let b: Vec<char> = text.chars().collect();
            if octdigits(&b[1].to_string())
                && octdigits(&b[2].to_string())
                && source.next_in(octdigits)
            {
                text.push_str(&source.get()?.unwrap());
                let value = u32::from_str_radix(&text[1..], 8).unwrap();
                if value > 0o377 {
                    return Err(source.error(
                        &format!("octal escape value {} outside of range 0-0o377", text),
                        clen(&text),
                    ));
                }
                return Ok(Escape::Literal(value));
            }
        }
        let group: usize = text[1..].parse().unwrap();
        if group < state.groups() {
            if !state.checkgroup(group) {
                return Err(source.error("cannot refer to an open group", clen(&text)));
            }
            state.checklookbehindgroup(group, source)?;
            return Ok(Escape::GroupRef(group));
        }
        return Err(source.error(
            &format!("invalid group reference {}", group),
            clen(&text) - 1,
        ));
    }
    plain_escape(source, escape, &c)
}

fn ws_token(t: &str) -> bool {
    matches!(t, " " | "\t" | "\n" | "\r" | "\x0b" | "\x0c")
}

fn parse_sub(
    source: &mut Tokenizer,
    state: &mut State,
    verbose: bool,
    nested: usize,
) -> R<Vec<Item>> {
    let mut items: Vec<Vec<Item>> = Vec::new();
    let mut verbose = verbose;
    loop {
        let first = nested == 0 && items.is_empty();
        items.push(parse(source, state, verbose, nested + 1, first)?);
        if !source.matches("|")? {
            break;
        }
        if nested == 0 {
            verbose = state.flags & F_VERBOSE != 0;
        }
    }
    if items.len() == 1 {
        return Ok(items.pop().unwrap());
    }
    Ok(vec![Item::Branch(items)])
}

fn required_get(source: &mut Tokenizer) -> R<String> {
    match source.get()? {
        None => Err(source.error("unexpected end of pattern", 0)),
        Some(c) => Ok(c),
    }
}

fn parse(
    source: &mut Tokenizer,
    state: &mut State,
    verbose: bool,
    nested: usize,
    first: bool,
) -> R<Vec<Item>> {
    let mut sub: Vec<Item> = Vec::new();
    let mut verbose = verbose;
    loop {
        let this = match source.next.clone() {
            None => break,
            Some(t) => t,
        };
        if this == "|" || this == ")" {
            break;
        }
        source.get()?;
        if verbose {
            if ws_token(&this) {
                continue;
            }
            if this == "#" {
                loop {
                    match source.get()? {
                        None => break,
                        Some(t) if t == "\n" => break,
                        _ => {}
                    }
                }
                continue;
            }
        }
        if this.starts_with('\\') {
            match escape(source, &this, state)? {
                Escape::Literal(_) | Escape::In => sub.push(Item::Unit),
                Escape::At => sub.push(Item::At),
                Escape::GroupRef(g) => sub.push(Item::GroupRef(g)),
            }
        } else if !".\\[{()*+?^$|".contains(this.as_str()) {
            sub.push(Item::Unit);
        } else if this == "[" {
            parse_class(source)?;
            sub.push(Item::Unit);
        } else if "*+?{".contains(this.as_str()) {
            let here = source.tell();
            let (min, max);
            if this == "?" {
                min = 0;
                max = 1;
            } else if this == "*" {
                min = 0;
                max = MAXREPEAT;
            } else if this == "+" {
                min = 1;
                max = MAXREPEAT;
            } else {
                if source.next_is("}") {
                    sub.push(Item::Unit);
                    continue;
                }
                let (mut lo, mut hi) = (String::new(), String::new());
                while source.next_in(digits) {
                    lo.push_str(&source.get()?.unwrap());
                }
                if source.matches(",")? {
                    while source.next_in(digits) {
                        hi.push_str(&source.get()?.unwrap());
                    }
                } else {
                    hi = lo.clone();
                }
                if !source.matches("}")? {
                    sub.push(Item::Unit);
                    source.seek(here)?;
                    continue;
                }
                let too_large =
                    Refusal::Crash("OverflowError", "the repetition number is too large");
                let mut mn = 0u128;
                let mut mx = MAXREPEAT;
                if !lo.is_empty() {
                    mn = big(&lo);
                    if mn >= MAXREPEAT {
                        return Err(too_large);
                    }
                }
                if !hi.is_empty() {
                    mx = big(&hi);
                    if mx >= MAXREPEAT {
                        return Err(too_large);
                    }
                    if mx < mn {
                        return Err(source
                            .error("min repeat greater than max repeat", source.tell() - here));
                    }
                }
                min = mn;
                max = mx;
            }
            let at = source.tell() - here + clen(&this);
            let item = match sub.last() {
                None | Some(Item::At) => return Err(source.error("nothing to repeat", at)),
                Some(Item::Repeat(..)) => return Err(source.error("multiple repeat", at)),
                Some(Item::Subpattern(None, 0, 0, p)) => p.clone(),
                Some(last) => vec![last.clone()],
            };
            if !source.matches("?")? {
                source.matches("+")?;
            }
            let n = sub.len();
            sub[n - 1] = Item::Repeat(min, max, item);
        } else if this == "." {
            sub.push(Item::Unit);
        } else if this == "(" {
            let start = source.tell() - 1;
            let mut capture = true;
            let mut atomic = false;
            let mut name: Option<String> = None;
            let mut add_flags = 0u32;
            let mut del_flags = 0u32;
            if source.matches("?")? {
                let ch = required_get(source)?;
                if ch == "P" {
                    if source.matches("<")? {
                        let n = source.getuntil(">", "group name")?;
                        source.checkgroupname(&n, 1)?;
                        name = Some(n);
                    } else if source.matches("=")? {
                        let n = source.getuntil(")", "group name")?;
                        source.checkgroupname(&n, 1)?;
                        let gid = match state.groupdict.get(&n) {
                            None => {
                                return Err(source.error(
                                    &format!("unknown group name {}", pystr::repr_str(&n)),
                                    clen(&n) + 1,
                                ))
                            }
                            Some(&g) => g,
                        };
                        if !state.checkgroup(gid) {
                            return Err(source.error("cannot refer to an open group", clen(&n) + 1));
                        }
                        state.checklookbehindgroup(gid, source)?;
                        sub.push(Item::GroupRef(gid));
                        continue;
                    } else {
                        let ch = required_get(source)?;
                        return Err(
                            source.error(&format!("unknown extension ?P{}", ch), clen(&ch) + 2)
                        );
                    }
                } else if ch == ":" {
                    capture = false;
                } else if ch == "#" {
                    loop {
                        if source.next.is_none() {
                            return Err(source
                                .error("missing ), unterminated comment", source.tell() - start));
                        }
                        if source.get()?.as_deref() == Some(")") {
                            break;
                        }
                    }
                    continue;
                } else if ch == "=" || ch == "!" || ch == "<" {
                    let mut dir = 1;
                    let mut lookbehindgroups = None;
                    if ch == "<" {
                        let ch2 = required_get(source)?;
                        if ch2 != "=" && ch2 != "!" {
                            return Err(source
                                .error(&format!("unknown extension ?<{}", ch2), clen(&ch2) + 2));
                        }
                        dir = -1;
                        lookbehindgroups = state.lookbehindgroups;
                        if lookbehindgroups.is_none() {
                            state.lookbehindgroups = Some(state.groups());
                        }
                    }
                    let p = parse_sub(source, state, verbose, nested + 1)?;
                    if dir < 0 && lookbehindgroups.is_none() {
                        state.lookbehindgroups = None;
                    }
                    if !source.matches(")")? {
                        return Err(source
                            .error("missing ), unterminated subpattern", source.tell() - start));
                    }
                    sub.push(Item::Assert(dir, p));
                    continue;
                } else if ch == "(" {
                    let condname = source.getuntil(")", "group name")?;
                    let condgroup;
                    if !(condname.chars().all(pystr::is_decimal) && condname.is_ascii()) {
                        source.checkgroupname(&condname, 1)?;
                        condgroup = match state.groupdict.get(&condname) {
                            None => {
                                return Err(source.error(
                                    &format!("unknown group name {}", pystr::repr_str(&condname)),
                                    clen(&condname) + 1,
                                ))
                            }
                            Some(&g) => g,
                        };
                    } else {
                        let g = big(&condname);
                        if g == 0 {
                            return Err(source.error("bad group number", clen(&condname) + 1));
                        }
                        if g >= MAXGROUPS {
                            return Err(source.error(
                                &format!(
                                    "invalid group reference {}",
                                    condname.trim_start_matches('0')
                                ),
                                clen(&condname) + 1,
                            ));
                        }
                        condgroup = g as usize;
                        if !state.grouprefpos.iter().any(|(k, _)| *k == condgroup) {
                            state
                                .grouprefpos
                                .push((condgroup, source.tell() - clen(&condname) - 1));
                        }
                    }
                    state.checklookbehindgroup(condgroup, source)?;
                    let yes = parse(source, state, verbose, nested + 1, false)?;
                    let no = if source.matches("|")? {
                        let no = parse(source, state, verbose, nested + 1, false)?;
                        if source.next_is("|") {
                            return Err(
                                source.error("conditional backref with more than two branches", 0)
                            );
                        }
                        Some(no)
                    } else {
                        None
                    };
                    if !source.matches(")")? {
                        return Err(source
                            .error("missing ), unterminated subpattern", source.tell() - start));
                    }
                    sub.push(Item::GroupRefExists(yes, no));
                    continue;
                } else if ch == ">" {
                    capture = false;
                    atomic = true;
                } else if flag(&ch).is_some() || ch == "-" {
                    match parse_flags(source, state, &ch)? {
                        None => {
                            if !first || !sub.is_empty() {
                                return Err(source.error(
                                    "global flags not at the start of the expression",
                                    source.tell() - start,
                                ));
                            }
                            verbose = state.flags & F_VERBOSE != 0;
                            continue;
                        }
                        Some((add, del)) => {
                            add_flags = add;
                            del_flags = del;
                            capture = false;
                        }
                    }
                } else {
                    return Err(source.error(&format!("unknown extension ?{}", ch), clen(&ch) + 1));
                }
            }
            let group = if capture {
                let gid = state.groups();
                state.groupwidths.push(None);
                if let Some(n) = &name {
                    if let Some(&ogid) = state.groupdict.get(n) {
                        return Err(source.error(
                            &format!(
                                "redefinition of group name {} as group {}; was group {}",
                                pystr::repr_str(n),
                                gid,
                                ogid
                            ),
                            clen(n) + 1,
                        ));
                    }
                    state.groupdict.insert(n.clone(), gid);
                }
                Some(gid)
            } else {
                None
            };
            let sub_verbose = (verbose || add_flags & F_VERBOSE != 0) && del_flags & F_VERBOSE == 0;
            let p = parse_sub(source, state, sub_verbose, nested + 1)?;
            if !source.matches(")")? {
                return Err(
                    source.error("missing ), unterminated subpattern", source.tell() - start)
                );
            }
            if let Some(g) = group {
                state.groupwidths[g] = Some(state.width(&p));
            }
            if atomic {
                sub.push(Item::Atomic(p));
            } else {
                sub.push(Item::Subpattern(group, add_flags, del_flags, p));
            }
        } else if this == "^" || this == "$" {
            sub.push(Item::At);
        }
    }
    Ok(sub)
}

/// int() of a run of ASCII digits, saturating far above any limit here.
fn big(digits: &str) -> u128 {
    let mut v: u128 = 0;
    for b in digits.bytes() {
        v = v.saturating_mul(10).saturating_add((b - b'0') as u128);
        if v > (1u128 << 100) {
            return 1u128 << 100;
        }
    }
    v
}

fn parse_class(source: &mut Tokenizer) -> R<()> {
    let here = source.tell() - 1;
    source.matches("^")?;
    let mut count = 0usize;
    loop {
        let this = match source.get()? {
            None => return Err(source.error("unterminated character set", source.tell() - here)),
            Some(t) => t,
        };
        if this == "]" && count > 0 {
            return Ok(());
        }
        let code1 = if this.starts_with('\\') {
            class_escape(source, &this)?
        } else {
            Escape::Literal(this.chars().next().unwrap() as u32)
        };
        if source.matches("-")? {
            let that = match source.get()? {
                None => {
                    return Err(source.error("unterminated character set", source.tell() - here))
                }
                Some(t) => t,
            };
            if that == "]" {
                return Ok(());
            }
            let code2 = if that.starts_with('\\') {
                class_escape(source, &that)?
            } else {
                Escape::Literal(that.chars().next().unwrap() as u32)
            };
            let bad = || {
                source.error(
                    &format!("bad character range {}-{}", this, that),
                    clen(&this) + 1 + clen(&that),
                )
            };
            match (code1, code2) {
                (Escape::Literal(lo), Escape::Literal(hi)) => {
                    if hi < lo {
                        return Err(bad());
                    }
                }
                _ => return Err(bad()),
            }
        }
        count += 1;
    }
}

fn flag_or(ch: &str, otherwise: &str) -> String {
    if ch.chars().count() == 1 && ch.chars().all(pystr::is_alpha) {
        "unknown flag".into()
    } else if !ch.is_empty() && ch.chars().all(pystr::is_alpha) {
        "unknown flag".into()
    } else {
        otherwise.into()
    }
}

fn parse_flags(source: &mut Tokenizer, state: &mut State, ch: &str) -> R<Option<(u32, u32)>> {
    let mut add = 0u32;
    let mut del = 0u32;
    let mut ch = ch.to_string();
    if ch != "-" {
        loop {
            let f = flag(&ch).unwrap();
            if ch == "L" {
                return Err(source.error(
                    "bad inline flags: cannot use 'L' flag with a str pattern",
                    0,
                ));
            }
            add |= f;
            if f & TYPE_FLAGS != 0 && add & TYPE_FLAGS != f {
                return Err(source.error(
                    "bad inline flags: flags 'a', 'u' and 'L' are incompatible",
                    0,
                ));
            }
            ch = match source.get()? {
                None => return Err(source.error("missing -, : or )", 0)),
                Some(c) => c,
            };
            if ch == ")" || ch == "-" || ch == ":" {
                break;
            }
            if flag(&ch).is_none() {
                return Err(source.error(&flag_or(&ch, "missing -, : or )"), clen(&ch)));
            }
        }
    }
    if ch == ")" {
        state.flags |= add;
        return Ok(None);
    }
    if add & GLOBAL_FLAGS != 0 {
        return Err(source.error("bad inline flags: cannot turn on global flag", 1));
    }
    if ch == "-" {
        ch = match source.get()? {
            None => return Err(source.error("missing flag", 0)),
            Some(c) => c,
        };
        if flag(&ch).is_none() {
            return Err(source.error(&flag_or(&ch, "missing flag"), clen(&ch)));
        }
        loop {
            let f = flag(&ch).unwrap();
            if f & TYPE_FLAGS != 0 {
                return Err(source.error(
                    "bad inline flags: cannot turn off flags 'a', 'u' and 'L'",
                    0,
                ));
            }
            del |= f;
            ch = match source.get()? {
                None => return Err(source.error("missing :", 0)),
                Some(c) => c,
            };
            if ch == ":" {
                break;
            }
            if flag(&ch).is_none() {
                return Err(source.error(&flag_or(&ch, "missing :"), clen(&ch)));
            }
        }
    }
    if del & GLOBAL_FLAGS != 0 {
        return Err(source.error("bad inline flags: cannot turn off global flag", 1));
    }
    if add & del != 0 {
        return Err(source.error("bad inline flags: flag turned on and off", 1));
    }
    Ok(Some((add, del)))
}

/// The look-behinds the compiler measures: each must have one width.
fn check_lookbehinds(state: &State, items: &[Item]) -> R<()> {
    for item in items {
        match item {
            Item::Assert(dir, p) => {
                if *dir < 0 {
                    let (lo, hi) = state.width(p);
                    if lo > MAXCODE {
                        return Err(Refusal::Error("looks too much behind".into()));
                    }
                    if lo != hi {
                        return Err(Refusal::Error(
                            "look-behind requires fixed-width pattern".into(),
                        ));
                    }
                }
                check_lookbehinds(state, p)?;
            }
            Item::Repeat(_, _, p) | Item::Subpattern(_, _, _, p) | Item::Atomic(p) => {
                check_lookbehinds(state, p)?;
            }
            Item::Branch(branches) => {
                for b in branches {
                    check_lookbehinds(state, b)?;
                }
            }
            Item::GroupRefExists(yes, no) => {
                check_lookbehinds(state, yes)?;
                if let Some(no) = no {
                    check_lookbehinds(state, no)?;
                }
            }
            _ => {}
        }
    }
    Ok(())
}

/// `re.compile(pattern)` for a str pattern: Ok when it compiles.
pub fn compile(pattern: &str) -> R<()> {
    let mut source = Tokenizer::new(pattern)?;
    let mut state = State {
        flags: 0,
        groupdict: HashMap::new(),
        groupwidths: vec![None],
        lookbehindgroups: None,
        grouprefpos: Vec::new(),
    };
    let p = parse_sub(&mut source, &mut state, false, 0)?;
    // fix_flags
    if state.flags & F_LOCALE != 0 {
        return Err(Refusal::Crash(
            "ValueError",
            "cannot use LOCALE flag with a str pattern",
        ));
    }
    if state.flags & F_ASCII != 0 && state.flags & F_UNICODE != 0 {
        return Err(Refusal::Crash(
            "ValueError",
            "ASCII and UNICODE flags are incompatible",
        ));
    }
    if source.next.is_some() {
        return Err(source.error("unbalanced parenthesis", 0));
    }
    for &(g, pos) in &state.grouprefpos {
        if g >= state.groups() {
            return Err(error_at(
                &source.s,
                &format!("invalid group reference {}", g),
                Some(pos),
            ));
        }
    }
    check_lookbehinds(&state, &p)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ok(p: &str) -> bool {
        compile(p).is_ok()
    }

    fn message(p: &str) -> String {
        match compile(p) {
            Err(Refusal::Error(m)) => m,
            other => panic!("{p:?}: {other:?}"),
        }
    }

    #[test]
    fn takes_what_python_takes() {
        for p in [
            "",
            "^[a-z]+$",
            "a{2,3}",
            "a{,}",
            "{",
            "a{x}",
            "x{}",
            "(?P<name>a)(?P=name)",
            "(a)\\1",
            "(?<=ab)c",
            "(?<!a|b)c",
            "(?i)abc",
            "(?x) a b # c",
            "(?:)*",
            "[]a]",
            "[^]]",
            "[a-]",
            "\\x41\\u0041\\U00000041",
            "(?>a+)b",
            "a*+",
            "(a)(?(1)b|c)",
            "\\d\\w\\s\\b",
            "\\0",
            "[\\d-]",
        ] {
            assert!(ok(p), "{p:?} should compile");
        }
    }

    #[test]
    fn refuses_in_pythons_words() {
        let cases = [
            ("(", "missing ), unterminated subpattern at position 0"),
            (")", "unbalanced parenthesis at position 0"),
            ("[", "unterminated character set at position 0"),
            ("a**", "multiple repeat at position 2"),
            ("*", "nothing to repeat at position 0"),
            ("^*", "nothing to repeat at position 1"),
            ("a{3,2}", "min repeat greater than max repeat at position 2"),
            ("\\", "bad escape (end of pattern) at position 0"),
            ("\\q", "bad escape \\q at position 0"),
            ("[z-a]", "bad character range z-a at position 1"),
            ("[\\d-z]", "bad character range \\d-z at position 1"),
            ("(?<=a+)b", "look-behind requires fixed-width pattern"),
            ("(?P<1>a)", "bad character in group name '1' at position 4"),
            ("(?P=x)", "unknown group name 'x' at position 4"),
            ("\\1", "invalid group reference 1 at position 1"),
            ("(a\\1)", "cannot refer to an open group at position 2"),
            (
                "(?L)a",
                "bad inline flags: cannot use 'L' flag with a str pattern at position 3",
            ),
            (
                "a(?i)",
                "global flags not at the start of the expression at position 1",
            ),
            (
                "(?P<a>x)(?P<a>y)",
                "redefinition of group name 'a' as group 2; was group 1 at position 12",
            ),
            ("(?(2)a)", "invalid group reference 2 at position 3"),
            ("\\x4", "incomplete escape \\x4 at position 0"),
            ("(?#x", "missing ), unterminated comment at position 0"),
            ("(?z)", "unknown extension ?z at position 1"),
            (
                "a\n(",
                "missing ), unterminated subpattern at position 2 (line 2, column 1)",
            ),
        ];
        for (p, want) in cases {
            assert_eq!(message(p), want, "{p:?}");
        }
    }

    #[test]
    fn character_names_are_looked_up() {
        for name in [
            "LATIN SMALL LETTER A",
            "latin small letter a",
            "NUL",
            "LINE FEED",
            "HANGUL SYLLABLE GA",
            "HANGUL SYLLABLE GAG",
            "HANGUL SYLLABLE A",
            "CJK UNIFIED IDEOGRAPH-4E00",
            "CJK UNIFIED IDEOGRAPH-2A6DF",
        ] {
            assert!(names_a_character(name), "{name}");
        }
        for name in [
            "DASH",
            "HANGUL SYLLABLE ga",
            "hangul syllable GA",
            "cjk unified ideograph-4E00",
            "TANGUT IDEOGRAPH-17000",
            "HANGUL SYLLABLE G",
            "CJK UNIFIED IDEOGRAPH-4e00",
            "CJK UNIFIED IDEOGRAPH-2A6E0",
            "LATIN CAPITAL LETTER A WITH MACRON AND GRAVE",
            "",
        ] {
            assert!(!names_a_character(name), "{name}");
        }
        assert_eq!(
            message("\\N{DASH}"),
            "undefined character name 'DASH' at position 0"
        );
        assert_eq!(lookup("SNOWMAN"), Some(0x2603));
        assert_eq!(lookup("HANGUL SYLLABLE GAG"), Some(0xAC01));
        assert_eq!(lookup("CJK UNIFIED IDEOGRAPH-4E00"), Some(0x4E00));
        assert_eq!(
            message("[\\N{COMET}-\\N{SNOWMAN}]"),
            "bad character range \\N-\\N at position 17"
        );
        assert!(ok("[\\N{SNOWMAN}-\\N{COMET}]"));
    }

    #[test]
    fn crashes_where_python_crashes() {
        assert_eq!(
            compile("a{4294967295}"),
            Err(Refusal::Crash(
                "OverflowError",
                "the repetition number is too large"
            ))
        );
        assert_eq!(
            compile("(?a)(?u)x"),
            Err(Refusal::Crash(
                "ValueError",
                "ASCII and UNICODE flags are incompatible"
            ))
        );
    }
}
