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

//! `tomllib.loads` from Python 3.12, rule for rule (Lib/tomllib/_parser.py),
//! so a file it accepts reads the same here and a file it refuses is refused
//! with the same message at the same line and column: the inventory prints
//! that message. Dates and times are kept as the text that was written,
//! after checking them as tomllib does.

use std::collections::HashMap;

use crate::json::{Dict, Value};
use crate::py;

/// `str(tomllib.TOMLDecodeError)`.
#[derive(Debug, Clone, PartialEq)]
pub struct TomlError(pub String);

impl std::fmt::Display for TomlError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}

type R<T> = Result<T, TomlError>;

const FROZEN: u8 = 1;
const EXPLICIT_NEST: u8 = 2;

#[derive(Default)]
struct FlagNode {
    flags: u8,
    recursive: u8,
    nested: HashMap<String, FlagNode>,
}

#[derive(Default)]
struct Flags {
    root: HashMap<String, FlagNode>,
    pending: Vec<(Vec<String>, u8)>,
}

impl Flags {
    fn add_pending(&mut self, key: Vec<String>, flag: u8) {
        self.pending.push((key, flag));
    }

    fn finalize_pending(&mut self) {
        for (key, flag) in std::mem::take(&mut self.pending) {
            self.set(&key, flag, false);
        }
    }

    fn unset_all(&mut self, key: &[String]) {
        let mut cont = &mut self.root;
        for k in &key[..key.len() - 1] {
            match cont.get_mut(k) {
                Some(node) => cont = &mut node.nested,
                None => return,
            }
        }
        cont.remove(&key[key.len() - 1]);
    }

    fn set(&mut self, key: &[String], flag: u8, recursive: bool) {
        let mut cont = &mut self.root;
        for k in &key[..key.len() - 1] {
            cont = &mut cont.entry(k.clone()).or_default().nested;
        }
        let node = cont.entry(key[key.len() - 1].clone()).or_default();
        if recursive {
            node.recursive |= flag;
        } else {
            node.flags |= flag;
        }
    }

    fn is(&self, key: &[String], flag: u8) -> bool {
        if key.is_empty() {
            return false;
        }
        let mut cont = &self.root;
        for k in &key[..key.len() - 1] {
            let Some(node) = cont.get(k) else {
                return false;
            };
            if node.recursive & flag != 0 {
                return true;
            }
            cont = &node.nested;
        }
        match cont.get(&key[key.len() - 1]) {
            Some(node) => (node.flags | node.recursive) & flag != 0,
            None => false,
        }
    }
}

/// `NestedDict.get_or_create_nest`; Err is its KeyError.
fn nest<'a>(
    mut cont: &'a mut Value,
    key: &[String],
    access_lists: bool,
) -> Result<&'a mut Dict, ()> {
    for k in key {
        let Value::Dict(d) = cont else {
            return Err(());
        };
        if !d.contains(k) {
            d.insert(k.clone(), Value::Dict(Dict::new()));
        }
        let into_list = access_lists && matches!(d.get(k), Some(Value::List(_)));
        let next = d.get_mut(k).unwrap();
        let next = if into_list {
            match next {
                Value::List(items) => items.last_mut().ok_or(())?,
                _ => unreachable!(),
            }
        } else {
            next
        };
        if !matches!(next, Value::Dict(_)) {
            return Err(());
        }
        cont = next;
    }
    match cont {
        Value::Dict(d) => Ok(d),
        _ => Err(()),
    }
}

fn append_nest_to_list(root: &mut Value, key: &[String]) -> Result<(), ()> {
    let cont = nest(root, &key[..key.len() - 1], true)?;
    let last = &key[key.len() - 1];
    match cont.get_mut(last) {
        Some(Value::List(items)) => items.push(Value::Dict(Dict::new())),
        Some(_) => return Err(()),
        None => cont.insert(last.clone(), Value::List(vec![Value::Dict(Dict::new())])),
    }
    Ok(())
}

fn is_ctrl(c: char) -> bool {
    (c as u32) < 32 || c == '\u{7f}'
}
fn illegal_basic(c: char) -> bool {
    is_ctrl(c) && c != '\t'
}
fn illegal_multiline(c: char) -> bool {
    is_ctrl(c) && c != '\t' && c != '\n'
}
fn is_ws(c: char) -> bool {
    c == ' ' || c == '\t'
}
fn is_ws_nl(c: char) -> bool {
    c == ' ' || c == '\t' || c == '\n'
}
fn is_bare(c: char) -> bool {
    c.is_ascii_alphanumeric() || c == '-' || c == '_'
}

struct Src {
    s: Vec<char>,
}

impl Src {
    fn at(&self, pos: usize) -> Option<char> {
        self.s.get(pos).copied()
    }

    fn starts(&self, pos: usize, text: &str) -> bool {
        let mut i = pos;
        for c in text.chars() {
            if self.at(i) != Some(c) {
                return false;
            }
            i += 1;
        }
        true
    }

    fn slice(&self, a: usize, b: usize) -> String {
        self.s[a.min(self.s.len())..b.min(self.s.len())]
            .iter()
            .collect()
    }

    fn err(&self, pos: usize, msg: &str) -> TomlError {
        let place = if pos >= self.s.len() {
            "end of document".to_string()
        } else {
            let before = &self.s[..pos];
            let line = before.iter().filter(|&&c| c == '\n').count() + 1;
            let column = if line == 1 {
                pos + 1
            } else {
                pos - before.iter().rposition(|&c| c == '\n').unwrap()
            };
            format!("line {line}, column {column}")
        };
        TomlError(format!("{msg} (at {place})"))
    }

    fn skip(&self, mut pos: usize, chars: fn(char) -> bool) -> usize {
        while self.at(pos).is_some_and(chars) {
            pos += 1;
        }
        pos
    }

    fn skip_until(
        &self,
        pos: usize,
        expect: &str,
        error_on: fn(char) -> bool,
        error_on_eof: bool,
    ) -> R<usize> {
        let found = (pos..self.s.len()).find(|&i| self.starts(i, expect));
        let new_pos = match found {
            Some(i) => i,
            None => {
                if error_on_eof {
                    return Err(
                        self.err(self.s.len(), &format!("Expected {}", py::repr_str(expect)))
                    );
                }
                self.s.len()
            }
        };
        if let Some(bad) = (pos..new_pos).find(|&i| error_on(self.s[i])) {
            return Err(self.err(
                bad,
                &format!(
                    "Found invalid character {}",
                    py::repr_str(&self.s[bad].to_string())
                ),
            ));
        }
        Ok(new_pos)
    }

    fn skip_comment(&self, pos: usize) -> R<usize> {
        if self.at(pos) == Some('#') {
            return self.skip_until(pos + 1, "\n", illegal_basic, false);
        }
        Ok(pos)
    }

    fn skip_comments_and_array_ws(&self, mut pos: usize) -> R<usize> {
        loop {
            let before = pos;
            pos = self.skip(pos, is_ws_nl);
            pos = self.skip_comment(pos)?;
            if pos == before {
                return Ok(pos);
            }
        }
    }

    fn parse_key(&self, pos: usize) -> R<(usize, Vec<String>)> {
        let (mut pos, part) = self.parse_key_part(pos)?;
        let mut key = vec![part];
        pos = self.skip(pos, is_ws);
        loop {
            if self.at(pos) != Some('.') {
                return Ok((pos, key));
            }
            pos = self.skip(pos + 1, is_ws);
            let (after, part) = self.parse_key_part(pos)?;
            key.push(part);
            pos = self.skip(after, is_ws);
        }
    }

    fn parse_key_part(&self, pos: usize) -> R<(usize, String)> {
        match self.at(pos) {
            Some(c) if is_bare(c) => {
                let end = self.skip(pos, is_bare);
                Ok((end, self.slice(pos, end)))
            }
            Some('\'') => self.parse_literal_str(pos),
            Some('"') => self.parse_basic_str(pos + 1, false),
            _ => Err(self.err(pos, "Invalid initial character for a key part")),
        }
    }

    fn parse_key_value_pair(&self, pos: usize) -> R<(usize, Vec<String>, Value)> {
        let (pos, key) = self.parse_key(pos)?;
        if self.at(pos) != Some('=') {
            return Err(self.err(pos, "Expected '=' after a key in a key/value pair"));
        }
        let pos = self.skip(pos + 1, is_ws);
        let (pos, value) = self.parse_value(pos)?;
        Ok((pos, key, value))
    }

    fn parse_array(&self, pos: usize) -> R<(usize, Value)> {
        let mut items = Vec::new();
        let mut pos = self.skip_comments_and_array_ws(pos + 1)?;
        if self.starts(pos, "]") {
            return Ok((pos + 1, Value::List(items)));
        }
        loop {
            let (after, value) = self.parse_value(pos)?;
            items.push(value);
            pos = self.skip_comments_and_array_ws(after)?;
            match self.at(pos) {
                Some(']') => return Ok((pos + 1, Value::List(items))),
                Some(',') => {}
                _ => return Err(self.err(pos, "Unclosed array")),
            }
            pos = self.skip_comments_and_array_ws(pos + 1)?;
            if self.starts(pos, "]") {
                return Ok((pos + 1, Value::List(items)));
            }
        }
    }

    fn parse_inline_table(&self, pos: usize) -> R<(usize, Value)> {
        let mut table = Value::Dict(Dict::new());
        let mut flags = Flags::default();
        let mut pos = self.skip(pos + 1, is_ws);
        if self.starts(pos, "}") {
            return Ok((pos + 1, table));
        }
        loop {
            let (after, key, value) = self.parse_key_value_pair(pos)?;
            pos = after;
            let (parent, stem) = key.split_at(key.len() - 1);
            if flags.is(&key, FROZEN) {
                return Err(self.err(
                    pos,
                    &format!("Cannot mutate immutable namespace {}", py::repr_tuple(&key)),
                ));
            }
            let container = value_is_container(&value);
            let Ok(cont) = nest(&mut table, parent, false) else {
                return Err(self.err(pos, "Cannot overwrite a value"));
            };
            if cont.contains(&stem[0]) {
                return Err(self.err(
                    pos,
                    &format!("Duplicate inline table key {}", py::repr_str(&stem[0])),
                ));
            }
            cont.insert(stem[0].clone(), value);
            pos = self.skip(pos, is_ws);
            match self.at(pos) {
                Some('}') => return Ok((pos + 1, table)),
                Some(',') => {}
                _ => return Err(self.err(pos, "Unclosed inline table")),
            }
            if container {
                flags.set(&key, FROZEN, true);
            }
            pos = self.skip(pos + 1, is_ws);
        }
    }

    fn parse_basic_str_escape(&self, pos: usize, multiline: bool) -> R<(usize, String)> {
        let id = self.slice(pos, pos + 2);
        let mut pos = pos + 2;
        if multiline && (id == "\\ " || id == "\\\t" || id == "\\\n") {
            if id != "\\\n" {
                pos = self.skip(pos, is_ws);
                match self.at(pos) {
                    None => return Ok((pos, String::new())),
                    Some('\n') => {}
                    Some(_) => return Err(self.err(pos, "Unescaped '\\' in a string")),
                }
                pos += 1;
            }
            pos = self.skip(pos, is_ws_nl);
            return Ok((pos, String::new()));
        }
        match id.as_str() {
            "\\u" => self.parse_hex_char(pos, 4),
            "\\U" => self.parse_hex_char(pos, 8),
            "\\b" => Ok((pos, "\u{8}".into())),
            "\\t" => Ok((pos, "\t".into())),
            "\\n" => Ok((pos, "\n".into())),
            "\\f" => Ok((pos, "\u{c}".into())),
            "\\r" => Ok((pos, "\r".into())),
            "\\\"" => Ok((pos, "\"".into())),
            "\\\\" => Ok((pos, "\\".into())),
            _ => Err(self.err(pos, "Unescaped '\\' in a string")),
        }
    }

    fn parse_hex_char(&self, pos: usize, len: usize) -> R<(usize, String)> {
        let hex = self.slice(pos, pos + len);
        if hex.chars().count() != len || !hex.chars().all(|c| c.is_ascii_hexdigit()) {
            return Err(self.err(pos, "Invalid hex value"));
        }
        let pos = pos + len;
        let code = u32::from_str_radix(&hex, 16).unwrap();
        match char::from_u32(code) {
            Some(c) => Ok((pos, c.to_string())),
            None => Err(self.err(pos, "Escaped character is not a Unicode scalar value")),
        }
    }

    fn parse_literal_str(&self, pos: usize) -> R<(usize, String)> {
        let start = pos + 1;
        let end = self.skip_until(start, "'", illegal_basic, true)?;
        Ok((end + 1, self.slice(start, end)))
    }

    fn parse_multiline_str(&self, pos: usize, literal: bool) -> R<(usize, Value)> {
        let mut pos = pos + 3;
        if self.starts(pos, "\n") {
            pos += 1;
        }
        let (delim, mut result) = if literal {
            let end = self.skip_until(pos, "'''", illegal_multiline, true)?;
            let text = self.slice(pos, end);
            pos = end + 3;
            ("'", text)
        } else {
            let (after, text) = self.parse_basic_str(pos, true)?;
            pos = after;
            ("\"", text)
        };
        if !self.starts(pos, delim) {
            return Ok((pos, Value::Str(result)));
        }
        pos += 1;
        result.push_str(delim);
        if !self.starts(pos, delim) {
            return Ok((pos, Value::Str(result)));
        }
        pos += 1;
        result.push_str(delim);
        Ok((pos, Value::Str(result)))
    }

    fn parse_basic_str(&self, mut pos: usize, multiline: bool) -> R<(usize, String)> {
        let error_on: fn(char) -> bool = if multiline {
            illegal_multiline
        } else {
            illegal_basic
        };
        let mut result = String::new();
        let mut start = pos;
        loop {
            let Some(c) = self.at(pos) else {
                return Err(self.err(pos, "Unterminated string"));
            };
            if c == '"' {
                if !multiline {
                    result.push_str(&self.slice(start, pos));
                    return Ok((pos + 1, result));
                }
                if self.starts(pos, "\"\"\"") {
                    result.push_str(&self.slice(start, pos));
                    return Ok((pos + 3, result));
                }
                pos += 1;
                continue;
            }
            if c == '\\' {
                result.push_str(&self.slice(start, pos));
                let (after, escaped) = self.parse_basic_str_escape(pos, multiline)?;
                result.push_str(&escaped);
                pos = after;
                start = pos;
                continue;
            }
            if error_on(c) {
                return Err(self.err(
                    pos,
                    &format!("Illegal character {}", py::repr_str(&c.to_string())),
                ));
            }
            pos += 1;
        }
    }

    fn digits_at(&self, pos: usize, n: usize) -> Option<u32> {
        let text = self.slice(pos, pos + n);
        if text.chars().count() == n && text.chars().all(|c| c.is_ascii_digit()) {
            text.parse().ok()
        } else {
            None
        }
    }

    /// `_TIME_RE_STR` at pos: the end of the match, and whether the time
    /// is a real one (the pattern itself limits the ranges).
    fn match_time(&self, pos: usize) -> Option<usize> {
        let two = |p: usize, max: u32| self.digits_at(p, 2).filter(|&v| v <= max);
        two(pos, 23)?;
        if self.at(pos + 2) != Some(':') {
            return None;
        }
        two(pos + 3, 59)?;
        if self.at(pos + 5) != Some(':') {
            return None;
        }
        two(pos + 6, 59)?;
        let mut end = pos + 8;
        if self.at(end) == Some('.') && self.at(end + 1).is_some_and(|c| c.is_ascii_digit()) {
            end += 1;
            while self.at(end).is_some_and(|c| c.is_ascii_digit()) {
                end += 1;
            }
        }
        Some(end)
    }

    /// RE_DATETIME at pos: (end, year, month, day).
    fn match_datetime(&self, pos: usize) -> Option<(usize, u32, u32, u32)> {
        let year = self.digits_at(pos, 4)?;
        if self.at(pos + 4) != Some('-') {
            return None;
        }
        let month = self
            .digits_at(pos + 5, 2)
            .filter(|m| (1..=12).contains(m))?;
        if self.at(pos + 7) != Some('-') {
            return None;
        }
        let day = self
            .digits_at(pos + 8, 2)
            .filter(|d| (1..=31).contains(d))?;
        let mut end = pos + 10;
        if matches!(self.at(end), Some('T' | 't' | ' ')) {
            if let Some(after) = self.match_time(end + 1) {
                end = after;
                match self.at(end) {
                    Some('Z' | 'z') => end += 1,
                    Some('+' | '-') => {
                        let hour = self.digits_at(end + 1, 2).filter(|&h| h <= 23);
                        let minute = self.digits_at(end + 4, 2).filter(|&m| m <= 59);
                        if hour.is_some() && self.at(end + 3) == Some(':') && minute.is_some() {
                            end += 6;
                        }
                    }
                    _ => {}
                }
            }
        }
        Some((end, year, month, day))
    }

    /// RE_NUMBER at pos: (end, is it a float).
    fn match_number(&self, pos: usize) -> Option<(usize, bool)> {
        let run = |mut p: usize, ok: fn(char) -> bool| -> Option<usize> {
            if !self.at(p).is_some_and(ok) {
                return None;
            }
            p += 1;
            loop {
                if self.at(p).is_some_and(ok) {
                    p += 1;
                } else if self.at(p) == Some('_') && self.at(p + 1).is_some_and(ok) {
                    p += 2;
                } else {
                    return Some(p);
                }
            }
        };
        if self.at(pos) == Some('0') {
            let prefixed = match self.at(pos + 1) {
                Some('x') => run(pos + 2, |c| c.is_ascii_hexdigit()),
                Some('b') => run(pos + 2, |c| c == '0' || c == '1'),
                Some('o') => run(pos + 2, |c| ('0'..='7').contains(&c)),
                _ => None,
            };
            if let Some(end) = prefixed {
                return Some((end, false));
            }
        }
        let mut p = pos;
        if matches!(self.at(p), Some('+' | '-')) {
            p += 1;
        }
        let digit: fn(char) -> bool = |c| c.is_ascii_digit();
        match self.at(p) {
            Some('0') => p += 1,
            Some('1'..='9') => p = run(p, digit)?,
            _ => return None,
        }
        let int_end = p;
        if self.at(p) == Some('.') {
            if let Some(end) = run(p + 1, digit) {
                p = end;
            }
        }
        if matches!(self.at(p), Some('e' | 'E')) {
            let mut q = p + 1;
            if matches!(self.at(q), Some('+' | '-')) {
                q += 1;
            }
            if let Some(end) = run(q, digit) {
                p = end;
            }
        }
        Some((p, p != int_end))
    }

    fn parse_value(&self, pos: usize) -> R<(usize, Value)> {
        match self.at(pos) {
            Some('"') => {
                if self.starts(pos, "\"\"\"") {
                    return self.parse_multiline_str(pos, false);
                }
                return self
                    .parse_basic_str(pos + 1, false)
                    .map(|(p, s)| (p, Value::Str(s)));
            }
            Some('\'') => {
                if self.starts(pos, "'''") {
                    return self.parse_multiline_str(pos, true);
                }
                return self.parse_literal_str(pos).map(|(p, s)| (p, Value::Str(s)));
            }
            Some('t') if self.starts(pos, "true") => return Ok((pos + 4, Value::Bool(true))),
            Some('f') if self.starts(pos, "false") => return Ok((pos + 5, Value::Bool(false))),
            Some('[') => return self.parse_array(pos),
            Some('{') => return self.parse_inline_table(pos),
            _ => {}
        }
        if let Some((end, year, month, day)) = self.match_datetime(pos) {
            if !valid_date(year, month, day) {
                return Err(self.err(pos, "Invalid date or datetime"));
            }
            return Ok((end, date_value(&self.slice(pos, end))));
        }
        if let Some(end) = self.match_time(pos) {
            return Ok((
                end,
                Value::Date(time_str(&self.slice(pos, end)), "datetime.time"),
            ));
        }
        if let Some((end, float)) = self.match_number(pos) {
            let text = self.slice(pos, end).replace('_', "");
            let value = if float {
                Value::Float(text.parse().unwrap_or(f64::NAN))
            } else {
                Value::Int(int_text(&text))
            };
            return Ok((end, value));
        }
        let three = self.slice(pos, pos + 3);
        if three == "inf" || three == "nan" {
            return Ok((pos + 3, Value::Float(three.parse().unwrap())));
        }
        let four = self.slice(pos, pos + 4);
        if ["-inf", "+inf", "-nan", "+nan"].contains(&four.as_str()) {
            return Ok((pos + 4, Value::Float(four.parse().unwrap())));
        }
        Err(self.err(pos, "Invalid value"))
    }
}

/// `str()` of the time of day that starts `text` (HH:MM:SS[.digits]):
/// microseconds shown only when there are some, always six digits.
fn time_str(text: &str) -> String {
    let (clock, rest) = text.split_at(8);
    let digits: String = rest
        .strip_prefix('.')
        .unwrap_or("")
        .chars()
        .take_while(|c| c.is_ascii_digit())
        .take(6)
        .collect();
    let micros: u32 = if digits.is_empty() {
        0
    } else {
        format!("{digits:0<6}").parse().unwrap()
    };
    if micros == 0 {
        clock.to_string()
    } else {
        format!("{clock}.{micros:06}")
    }
}

/// A RE_DATETIME match as tomllib returns it: a date, or a datetime with
/// the offset it was written with (Z is +00:00), shown as `str()` shows it.
fn date_value(text: &str) -> Value {
    if text.len() == 10 {
        return Value::Date(text.to_string(), "datetime.date");
    }
    let (date, time) = (&text[..10], &text[11..]);
    let clock_end = 8 + time[8..].strip_prefix('.').map_or(0, |r| {
        1 + r.chars().take_while(|c| c.is_ascii_digit()).count()
    });
    let offset = match &time[clock_end..] {
        "Z" | "z" => "+00:00",
        other => other,
    };
    Value::Date(
        format!("{date} {}{offset}", time_str(&time[..clock_end])),
        "datetime.datetime",
    )
}

fn value_is_container(value: &Value) -> bool {
    matches!(value, Value::Dict(_) | Value::List(_))
}

fn valid_date(year: u32, month: u32, day: u32) -> bool {
    if year == 0 {
        return false;
    }
    let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;
    let days = match month {
        2 if leap => 29,
        2 => 28,
        4 | 6 | 9 | 11 => 30,
        _ => 31,
    };
    day <= days
}

/// `str(int(text, 0))` for what RE_NUMBER takes as an integer.
fn int_text(text: &str) -> String {
    let (negative, body) = match text.as_bytes().first() {
        Some(b'-') => (true, &text[1..]),
        Some(b'+') => (false, &text[1..]),
        _ => (false, text),
    };
    let (radix, digits) = match body.get(..2) {
        Some("0x") => (16, &body[2..]),
        Some("0o") => (8, &body[2..]),
        Some("0b") => (2, &body[2..]),
        _ => (10, body),
    };
    // Base-10 digits arbitrarily long, by repeated multiply-and-add.
    let mut out: Vec<u8> = vec![0];
    for c in digits.chars() {
        let mut carry = c.to_digit(radix).unwrap_or(0);
        for d in out.iter_mut() {
            let v = *d as u32 * radix + carry;
            *d = (v % 10) as u8;
            carry = v / 10;
        }
        while carry > 0 {
            out.push((carry % 10) as u8);
            carry /= 10;
        }
    }
    while out.len() > 1 && *out.last().unwrap() == 0 {
        out.pop();
    }
    let text: String = out.iter().rev().map(|d| (b'0' + d) as char).collect();
    if negative && text != "0" {
        format!("-{text}")
    } else {
        text
    }
}

/// `tomllib.loads(text)`.
pub fn loads(text: &str) -> Result<Value, TomlError> {
    let src = Src {
        s: text.replace("\r\n", "\n").chars().collect(),
    };
    let mut root = Value::Dict(Dict::new());
    let mut flags = Flags::default();
    let mut header: Vec<String> = Vec::new();
    let mut pos = 0;
    loop {
        pos = src.skip(pos, is_ws);
        let Some(c) = src.at(pos) else {
            break;
        };
        if c == '\n' {
            pos += 1;
            continue;
        }
        if is_bare(c) || c == '"' || c == '\'' {
            pos = key_value_rule(&src, pos, &mut root, &mut flags, &header)?;
            pos = src.skip(pos, is_ws);
        } else if c == '[' {
            flags.finalize_pending();
            let list = src.at(pos + 1) == Some('[');
            let (after, key) = if list {
                create_list_rule(&src, pos, &mut root, &mut flags)?
            } else {
                create_dict_rule(&src, pos, &mut root, &mut flags)?
            };
            header = key;
            pos = src.skip(after, is_ws);
        } else if c != '#' {
            return Err(src.err(pos, "Invalid statement"));
        }
        pos = src.skip_comment(pos)?;
        let Some(c) = src.at(pos) else {
            break;
        };
        if c != '\n' {
            return Err(src.err(pos, "Expected newline or end of document after a statement"));
        }
        pos += 1;
    }
    Ok(root)
}

fn create_dict_rule(
    src: &Src,
    pos: usize,
    root: &mut Value,
    flags: &mut Flags,
) -> R<(usize, Vec<String>)> {
    let pos = src.skip(pos + 1, is_ws);
    let (pos, key) = src.parse_key(pos)?;
    if flags.is(&key, EXPLICIT_NEST) || flags.is(&key, FROZEN) {
        return Err(src.err(
            pos,
            &format!("Cannot declare {} twice", py::repr_tuple(&key)),
        ));
    }
    flags.set(&key, EXPLICIT_NEST, false);
    if nest(root, &key, true).is_err() {
        return Err(src.err(pos, "Cannot overwrite a value"));
    }
    if !src.starts(pos, "]") {
        return Err(src.err(pos, "Expected ']' at the end of a table declaration"));
    }
    Ok((pos + 1, key))
}

fn create_list_rule(
    src: &Src,
    pos: usize,
    root: &mut Value,
    flags: &mut Flags,
) -> R<(usize, Vec<String>)> {
    let pos = src.skip(pos + 2, is_ws);
    let (pos, key) = src.parse_key(pos)?;
    if flags.is(&key, FROZEN) {
        return Err(src.err(
            pos,
            &format!("Cannot mutate immutable namespace {}", py::repr_tuple(&key)),
        ));
    }
    flags.unset_all(&key);
    flags.set(&key, EXPLICIT_NEST, false);
    if append_nest_to_list(root, &key).is_err() {
        return Err(src.err(pos, "Cannot overwrite a value"));
    }
    if !src.starts(pos, "]]") {
        return Err(src.err(pos, "Expected ']]' at the end of an array declaration"));
    }
    Ok((pos + 2, key))
}

fn key_value_rule(
    src: &Src,
    pos: usize,
    root: &mut Value,
    flags: &mut Flags,
    header: &[String],
) -> R<usize> {
    let (pos, key, value) = src.parse_key_value_pair(pos)?;
    let (parent, stem) = key.split_at(key.len() - 1);
    let abs_parent: Vec<String> = header.iter().chain(parent).cloned().collect();
    for i in 1..key.len() {
        let cont_key: Vec<String> = header.iter().chain(&key[..i]).cloned().collect();
        if flags.is(&cont_key, EXPLICIT_NEST) {
            return Err(src.err(
                pos,
                &format!("Cannot redefine namespace {}", py::repr_tuple(&cont_key)),
            ));
        }
        flags.add_pending(cont_key, EXPLICIT_NEST);
    }
    if flags.is(&abs_parent, FROZEN) {
        let shown = if abs_parent.is_empty() {
            "()".to_string()
        } else {
            py::repr_tuple(&abs_parent)
        };
        return Err(src.err(pos, &format!("Cannot mutate immutable namespace {shown}")));
    }
    let container = value_is_container(&value);
    let Ok(cont) = nest(root, &abs_parent, true) else {
        return Err(src.err(pos, "Cannot overwrite a value"));
    };
    if cont.contains(&stem[0]) {
        return Err(src.err(pos, "Cannot overwrite a value"));
    }
    cont.insert(stem[0].clone(), value);
    if container {
        let full: Vec<String> = header.iter().chain(&key).cloned().collect();
        flags.set(&full, FROZEN, true);
    }
    Ok(pos)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn err(text: &str) -> String {
        loads(text).unwrap_err().0
    }

    #[test]
    fn package_files_read_as_tomllib_reads_them() {
        let v = loads(
            "# c\n[package]\nname = \"example-kit\" # trailing\nversion = '1.1.0'\npublish = false\n\
             [project]\nclassifiers = [\n  \"Private :: Do Not Upload\", # why\n]\n\
             [a.b]\nc = { d = 1, e.f = [1, 2.5] }\n[[x]]\ny = 0x1F\n[[x]]\ny = 1_000\n\
             s = \"\"\"\nline\\\n   more\"\"\"\nd = 1979-05-27T07:32:00Z\n",
        )
        .unwrap();
        let package = v.get("package").unwrap();
        assert_eq!(package.get("name"), Some(&Value::Str("example-kit".into())));
        assert_eq!(package.get("version"), Some(&Value::Str("1.1.0".into())));
        assert_eq!(package.get("publish"), Some(&Value::Bool(false)));
        let classifiers = v.get("project").unwrap().get("classifiers").unwrap();
        assert_eq!(classifiers.py_repr(), "['Private :: Do Not Upload']");
        assert_eq!(
            v.get("a").unwrap().py_repr(),
            "{'b': {'c': {'d': 1, 'e': {'f': [1, 2.5]}}}}"
        );
        let x = v.get("x").unwrap();
        assert_eq!(
            x.py_repr(),
            "[{'y': 31}, {'y': 1000, 's': 'linemore', 'd': 1979-05-27 07:32:00+00:00}]"
        );
    }

    #[test]
    fn errors_are_tomllib_s() {
        assert_eq!(
            err("[package]\nname = \"x\nversion = 1"),
            "Illegal character '\\n' (at line 2, column 10)"
        );
        assert_eq!(
            err("a = 1\na = 2"),
            "Cannot overwrite a value (at end of document)"
        );
        assert_eq!(err("a ="), "Invalid value (at end of document)");
        assert_eq!(
            err("[a]\n[a]"),
            "Cannot declare ('a',) twice (at line 2, column 3)"
        );
        assert_eq!(
            err("a = 1 b"),
            "Expected newline or end of document after a statement (at line 1, column 7)"
        );
        assert_eq!(err("= 1"), "Invalid statement (at line 1, column 1)");
        assert_eq!(
            err("a 1"),
            "Expected '=' after a key in a key/value pair (at line 1, column 3)"
        );
        assert_eq!(err("a = [1 2]"), "Unclosed array (at line 1, column 8)");
        assert_eq!(
            err("a = {b = 1 c}"),
            "Unclosed inline table (at line 1, column 12)"
        );
        assert_eq!(err("a = 'x"), "Expected \"'\" (at end of document)");
        assert_eq!(
            err("a = \"\\q\""),
            "Unescaped '\\' in a string (at line 1, column 8)"
        );
        assert_eq!(
            err("a = 2021-02-30"),
            "Invalid date or datetime (at line 1, column 5)"
        );
        assert_eq!(
            err("\u{feff}a = 1"),
            "Invalid statement (at line 1, column 1)"
        );
        assert_eq!(
            err("a = {b = 1, b = 2}"),
            "Duplicate inline table key 'b' (at line 1, column 18)"
        );
        assert_eq!(
            err("a = [1]\n[a.b]"),
            "Cannot declare ('a', 'b') twice (at line 2, column 5)"
        );
        assert_eq!(
            err("# a\u{1}"),
            "Found invalid character '\\x01' (at line 1, column 4)"
        );
    }

    #[test]
    fn dates_and_times_show_as_python_shows_them() {
        let v = loads("a = 1979-05-27T07:32:00.999999999-07:00\nb = 07:32:00.5\nc = 1979-05-27\nd = 1979-05-27 07:32:00\n").unwrap();
        assert_eq!(
            v.get("a"),
            Some(&Value::Date(
                "1979-05-27 07:32:00.999999-07:00".into(),
                "datetime.datetime"
            ))
        );
        assert_eq!(
            v.get("b"),
            Some(&Value::Date("07:32:00.500000".into(), "datetime.time"))
        );
        assert_eq!(
            v.get("c"),
            Some(&Value::Date("1979-05-27".into(), "datetime.date"))
        );
        assert_eq!(
            v.get("d"),
            Some(&Value::Date(
                "1979-05-27 07:32:00".into(),
                "datetime.datetime"
            ))
        );
    }

    #[test]
    fn integers_are_exact() {
        assert_eq!(int_text("0x1F"), "31");
        assert_eq!(int_text("-0"), "0");
        assert_eq!(
            int_text("123456789012345678901234567890"),
            "123456789012345678901234567890"
        );
        assert_eq!(int_text("0b101"), "5");
    }
}
