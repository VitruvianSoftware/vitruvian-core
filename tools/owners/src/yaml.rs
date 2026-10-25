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

//! The YAML that OWNERS files are written in, read into a [`Node`] tree and
//! decoded into typed structs through serde, the way `gopkg.in/yaml.v3`
//! decoded them for the Go tool.
//!
//! It reads block mappings and sequences, flow sequences, plain, single- and
//! double-quoted scalars, comments, anchors and aliases on values, and a
//! leading `---`, and plain scalars folded over several lines. What it does
//! not read (tags, block scalars, multi-line quoted scalars) is an error, and
//! an error is not a verdict: `schema::parse_config` then falls back to the
//! line-based reading, exactly as the Go tool did whenever yaml.v3 failed.

use serde::de::{self, DeserializeSeed, Deserializer, MapAccess, SeqAccess, Visitor};
use std::fmt;

#[derive(Debug, Clone, PartialEq)]
pub enum Node {
    Null,
    Scalar { value: String, plain: bool },
    Seq(Vec<Node>),
    Map(Vec<(String, Node)>),
}

#[derive(Debug, Clone, PartialEq)]
pub struct Error(pub String);

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

impl std::error::Error for Error {}

impl de::Error for Error {
    fn custom<T: fmt::Display>(msg: T) -> Self {
        Error(msg.to_string())
    }
}

fn err<T>(msg: &str) -> Result<T, Error> {
    Err(Error(msg.to_string()))
}

struct Line {
    indent: usize,
    text: String,
}

/// Parses the first YAML document in `src`.
pub fn parse(src: &str) -> Result<Node, Error> {
    // A byte-order mark opens the stream, as YAML allows.
    let src = src.strip_prefix('\u{feff}').unwrap_or(src);
    let mut lines: Vec<Line> = Vec::new();
    for raw in src.split('\n') {
        let raw = raw.strip_suffix('\r').unwrap_or(raw);
        for c in raw.chars() {
            let u = c as u32;
            if (u < 0x20 && c != '\t') || u == 0x7f || (0x80..0xa0).contains(&u) && u != 0x85 {
                return err("control characters are not allowed");
            }
        }
        let stripped = strip_comment(raw);
        let text_end = stripped.trim_end_matches([' ', '\t']);
        if text_end.trim_start_matches([' ', '\t']).is_empty() {
            continue;
        }
        let indent = text_end.len() - text_end.trim_start_matches(' ').len();
        let text = &text_end[indent..];
        if text.starts_with('\t') {
            return err("found a tab character that violates indentation");
        }
        if indent == 0 && (text == "---" || text.starts_with("--- ") || text.starts_with("---\t")) {
            if !lines.is_empty() {
                break;
            }
            if text.len() > 3 {
                return err("content on the document start line is not supported");
            }
            continue;
        }
        if indent == 0 && (text == "..." || text.starts_with("... ")) {
            break;
        }
        if indent == 0 && text.starts_with('%') {
            return err("directives are not supported");
        }
        lines.push(Line {
            indent,
            text: text.to_string(),
        });
    }
    if lines.is_empty() {
        return Ok(Node::Null);
    }
    let mut p = Parser {
        lines,
        pos: 0,
        anchors: std::collections::HashMap::new(),
    };
    let first = p.lines[0].indent;
    let node = p.block(first)?;
    if p.pos < p.lines.len() {
        return err("did not find expected <document start>");
    }
    Ok(node)
}

/// Drops a `#` comment, minding quoted scalars (a `#` inside quotes is text).
fn strip_comment(s: &str) -> String {
    let chars: Vec<char> = s.chars().collect();
    let mut out = String::with_capacity(s.len());
    let mut prev: Option<char> = None;
    let mut prev_sig: Option<char> = None;
    let mut i = 0;
    while i < chars.len() {
        let c = chars[i];
        let after_space = matches!(prev, None | Some(' ') | Some('\t'));
        if c == '#' && after_space {
            break;
        }
        let token_start = matches!(
            prev,
            None | Some(' ') | Some('\t') | Some('[') | Some('{') | Some(',')
        ) && matches!(
            prev_sig,
            None | Some('-') | Some(':') | Some('[') | Some('{') | Some(',') | Some('?')
        );
        if (c == '"' || c == '\'') && token_start {
            out.push(c);
            i += 1;
            while i < chars.len() {
                let q = chars[i];
                out.push(q);
                i += 1;
                if c == '"' && q == '\\' {
                    if i < chars.len() {
                        out.push(chars[i]);
                        i += 1;
                    }
                    continue;
                }
                if q == c {
                    if c == '\'' && i < chars.len() && chars[i] == '\'' {
                        out.push('\'');
                        i += 1;
                        continue;
                    }
                    break;
                }
            }
            prev = Some(c);
            prev_sig = Some(c);
            continue;
        }
        out.push(c);
        prev = Some(c);
        if c != ' ' && c != '\t' {
            prev_sig = Some(c);
        }
        i += 1;
    }
    out
}

fn is_seq_line(text: &str) -> bool {
    text == "-" || text.starts_with("- ") || text.starts_with("-\t")
}

struct Parser {
    lines: Vec<Line>,
    pos: usize,
    anchors: std::collections::HashMap<String, Node>,
}

/// Splits a leading `&anchor` off a value.
fn take_anchor(rest: &str) -> (Option<String>, &str) {
    match rest.strip_prefix('&') {
        Some(a) => {
            let end = a.find([' ', '\t']).unwrap_or(a.len());
            (
                Some(a[..end].to_string()),
                a[end..].trim_start_matches([' ', '\t']),
            )
        }
        None => (None, rest),
    }
}

impl Parser {
    /// An inline value, or `*alias` to an anchored one.
    fn inline(&self, s: &str) -> Result<Node, Error> {
        if let Some(name) = s.strip_prefix('*') {
            return match self.anchors.get(name.trim_end_matches([' ', '\t'])) {
                Some(n) => Ok(n.clone()),
                None => err("unknown anchor referenced"),
            };
        }
        parse_inline(s)
    }

    /// A plain scalar continued on lines indented past its parent (`n`) is
    /// one value, its line breaks folded to spaces. Anything else indented
    /// there is an error.
    fn fold_plain(&mut self, v: Node, n: usize) -> Result<Node, Error> {
        if !matches!(self.next_indent(), Some(i) if i > n) {
            return Ok(v);
        }
        let Node::Scalar {
            mut value,
            plain: true,
        } = v
        else {
            return err("multi-line values are not supported here");
        };
        while matches!(self.next_indent(), Some(i) if i > n) {
            let text = &self.lines[self.pos].text;
            if text.contains(": ") || text.contains(":\t") || text.ends_with(':') {
                return err("mapping values are not allowed in this context");
            }
            value.push(' ');
            value.push_str(text);
            self.pos += 1;
        }
        Ok(Node::Scalar { value, plain: true })
    }

    fn next_indent(&self) -> Option<usize> {
        self.lines.get(self.pos).map(|l| l.indent)
    }

    fn block(&mut self, n: usize) -> Result<Node, Error> {
        let text = self.lines[self.pos].text.clone();
        if is_seq_line(&text) {
            return self.seq(n);
        }
        if split_map_entry(&text)?.is_some() {
            return self.map(n);
        }
        self.pos += 1;
        parse_inline(&text)
    }

    fn seq(&mut self, n: usize) -> Result<Node, Error> {
        let mut items = Vec::new();
        while let Some(ind) = self.next_indent() {
            if ind < n {
                break;
            }
            if ind > n {
                return err("did not find expected '-' indicator");
            }
            let text = self.lines[self.pos].text.clone();
            if !is_seq_line(&text) {
                break;
            }
            let after = &text[1..];
            let rest = after.trim_start_matches([' ', '\t']);
            if rest.is_empty() {
                self.pos += 1;
                match self.next_indent() {
                    Some(i) if i > n => items.push(self.block(i)?),
                    _ => items.push(Node::Null),
                }
            } else if rest.starts_with('&') || rest.starts_with('*') {
                self.pos += 1;
                let (anchor, rest) = take_anchor(rest);
                let v = if rest.is_empty() {
                    match self.next_indent() {
                        Some(i) if i > n => self.block(i)?,
                        _ => Node::Null,
                    }
                } else {
                    let v = self.inline(rest)?;
                    self.fold_plain(v, n)?
                };
                if let Some(a) = anchor {
                    self.anchors.insert(a, v.clone());
                }
                items.push(v);
            } else {
                let col = n + 1 + (after.len() - rest.len());
                self.lines[self.pos] = Line {
                    indent: col,
                    text: rest.to_string(),
                };
                let v = self.block(col)?;
                items.push(self.fold_plain(v, n)?);
            }
        }
        Ok(Node::Seq(items))
    }

    fn map(&mut self, n: usize) -> Result<Node, Error> {
        let mut entries: Vec<(String, Node)> = Vec::new();
        while let Some(ind) = self.next_indent() {
            if ind < n {
                break;
            }
            if ind > n {
                return err("mapping values are not allowed in this context");
            }
            let text = self.lines[self.pos].text.clone();
            let Some((key, rest)) = split_map_entry(&text)? else {
                return err("could not find expected ':'");
            };
            if entries.iter().any(|(k, _)| *k == key) {
                return Err(Error(format!("mapping key {key:?} already defined")));
            }
            self.pos += 1;
            let (anchor, rest) = take_anchor(&rest);
            let value = if rest.is_empty() {
                match self.next_indent() {
                    Some(i) if i > n => self.block(i)?,
                    Some(i) if i == n && is_seq_line(&self.lines[self.pos].text) => self.seq(n)?,
                    _ => Node::Null,
                }
            } else {
                let v = self.inline(rest)?;
                self.fold_plain(v, n)?
            };
            if let Some(a) = anchor {
                self.anchors.insert(a, value.clone());
            }
            entries.push((key, value));
        }
        Ok(Node::Map(entries))
    }
}

/// `key: rest` when the line is a mapping entry.
fn split_map_entry(text: &str) -> Result<Option<(String, String)>, Error> {
    let first = text.chars().next().unwrap_or(' ');
    if first == '"' || first == '\'' {
        let Ok((key, end)) = quoted(text) else {
            return Ok(None);
        };
        let after = text[end..].trim_start_matches([' ', '\t']);
        if let Some(rest) = after.strip_prefix(':') {
            if rest.is_empty() || rest.starts_with([' ', '\t']) {
                return Ok(Some((key, rest.trim_matches([' ', '\t']).to_string())));
            }
        }
        return Ok(None);
    }
    if first == '[' || first == '{' || is_seq_line(text) {
        return Ok(None);
    }
    let bytes = text.as_bytes();
    for (i, &b) in bytes.iter().enumerate() {
        if b == b':' && (i + 1 == bytes.len() || bytes[i + 1] == b' ' || bytes[i + 1] == b'\t') {
            let key = text[..i].trim_end_matches([' ', '\t']);
            if key.is_empty() {
                return Ok(None);
            }
            let key = match parse_plain(key)? {
                Node::Scalar { value, .. } => value,
                _ => key.to_string(),
            };
            return Ok(Some((
                key,
                text[i + 1..].trim_matches([' ', '\t']).to_string(),
            )));
        }
    }
    Ok(None)
}

/// A value written on the same line as its key or dash.
fn parse_inline(s: &str) -> Result<Node, Error> {
    let s = s.trim_matches([' ', '\t']);
    match s.chars().next() {
        Some('"') | Some('\'') => {
            let (v, end) = quoted(s)?;
            if !s[end..].trim_matches([' ', '\t']).is_empty() {
                return err("did not find expected key");
            }
            Ok(Node::Scalar {
                value: v,
                plain: false,
            })
        }
        Some('[') => {
            let (node, end) = flow_seq(s)?;
            if !s[end..].trim_matches([' ', '\t']).is_empty() {
                return err("did not find expected <document start>");
            }
            Ok(node)
        }
        Some('{') => {
            if s[1..].trim_matches([' ', '\t']) == "}" {
                Ok(Node::Map(Vec::new()))
            } else {
                err("flow mappings are not supported")
            }
        }
        _ => {
            if s.contains(": ") || s.contains(":\t") {
                return err("mapping values are not allowed in this context");
            }
            parse_plain(s)
        }
    }
}

fn parse_plain(s: &str) -> Result<Node, Error> {
    let mut cs = s.chars();
    let first = cs.next().unwrap_or(' ');
    let second = cs.next();
    if matches!(first, '@' | '`') {
        return err("found character that cannot start any token");
    }
    if matches!(
        first,
        '&' | '*' | '!' | '|' | '>' | '%' | ',' | '[' | ']' | '{' | '}' | '#' | '"' | '\''
    ) {
        return err("unsupported YAML construct");
    }
    if matches!(first, '-' | '?' | ':') && matches!(second, None | Some(' ') | Some('\t')) {
        return err("block entries are not allowed in this context");
    }
    if matches!(s, "" | "~" | "null" | "Null" | "NULL") {
        return Ok(Node::Null);
    }
    Ok(Node::Scalar {
        value: s.to_string(),
        plain: true,
    })
}

/// A quoted scalar at the start of `s`: its value and the byte after it.
fn quoted(s: &str) -> Result<(String, usize), Error> {
    let q = s.as_bytes()[0];
    let mut out = String::new();
    let mut it = s.char_indices().skip(1).peekable();
    while let Some((i, c)) = it.next() {
        if q == b'\'' {
            if c == '\'' {
                if matches!(it.peek(), Some((_, '\''))) {
                    it.next();
                    out.push('\'');
                    continue;
                }
                return Ok((out, i + 1));
            }
            out.push(c);
            continue;
        }
        match c {
            '"' => return Ok((out, i + 1)),
            '\\' => {
                let Some((_, e)) = it.next() else {
                    return err("found unexpected end of stream");
                };
                match e {
                    '0' => out.push('\0'),
                    'a' => out.push('\u{7}'),
                    'b' => out.push('\u{8}'),
                    't' | '\t' => out.push('\t'),
                    'n' => out.push('\n'),
                    'v' => out.push('\u{b}'),
                    'f' => out.push('\u{c}'),
                    'r' => out.push('\r'),
                    'e' => out.push('\u{1b}'),
                    ' ' => out.push(' '),
                    '"' => out.push('"'),
                    '/' => out.push('/'),
                    '\\' => out.push('\\'),
                    'N' => out.push('\u{85}'),
                    '_' => out.push('\u{a0}'),
                    'L' => out.push('\u{2028}'),
                    'P' => out.push('\u{2029}'),
                    'x' | 'u' | 'U' => {
                        let len = match e {
                            'x' => 2,
                            'u' => 4,
                            _ => 8,
                        };
                        let mut hex = String::new();
                        for _ in 0..len {
                            match it.next() {
                                Some((_, h)) if h.is_ascii_hexdigit() => hex.push(h),
                                _ => return err("did not find expected hexdecimal number"),
                            }
                        }
                        let v = u32::from_str_radix(&hex, 16).unwrap_or(0);
                        match char::from_u32(v) {
                            Some(ch) => out.push(ch),
                            None => return err("found invalid Unicode character escape code"),
                        }
                    }
                    _ => return err("found unknown escape character"),
                }
            }
            c => out.push(c),
        }
    }
    err("found unexpected end of stream")
}

/// A flow sequence `[a, "b"]` at the start of `s`.
fn flow_seq(s: &str) -> Result<(Node, usize), Error> {
    let bytes = s.as_bytes();
    let mut i = 1;
    let mut items = Vec::new();
    let skip_ws = |i: &mut usize| {
        while *i < bytes.len() && (bytes[*i] == b' ' || bytes[*i] == b'\t') {
            *i += 1;
        }
    };
    loop {
        skip_ws(&mut i);
        if i >= bytes.len() {
            return err("did not find expected ',' or ']'");
        }
        if bytes[i] == b']' {
            return Ok((Node::Seq(items), i + 1));
        }
        let item = match bytes[i] {
            b'"' | b'\'' => {
                let (v, end) = quoted(&s[i..])?;
                i += end;
                Node::Scalar {
                    value: v,
                    plain: false,
                }
            }
            b'[' => {
                let (n, end) = flow_seq(&s[i..])?;
                i += end;
                n
            }
            b',' => return err("did not find expected node content"),
            _ => {
                let start = i;
                while i < bytes.len() && !matches!(bytes[i], b',' | b']' | b'[' | b'{' | b'}') {
                    if bytes[i] == b':'
                        && (i + 1 < bytes.len()
                            && matches!(bytes[i + 1], b' ' | b'\t' | b',' | b']'))
                    {
                        return err("flow mappings are not supported");
                    }
                    i += 1;
                }
                if i < bytes.len() && matches!(bytes[i], b'[' | b'{' | b'}') {
                    return err("did not find expected ',' or ']'");
                }
                let raw = s[start..i].trim_end_matches([' ', '\t']);
                // A lone `-` or `?` right before `,` or `]` is a value in a
                // flow sequence: the indicator needs a blank after it.
                if (raw == "-" || raw == "?") && raw.len() == i - start {
                    Node::Scalar {
                        value: raw.to_string(),
                        plain: true,
                    }
                } else {
                    parse_plain(raw)?
                }
            }
        };
        items.push(item);
        skip_ws(&mut i);
        if i >= bytes.len() {
            return err("did not find expected ',' or ']'");
        }
        match bytes[i] {
            b',' => i += 1,
            b']' => return Ok((Node::Seq(items), i + 1)),
            _ => return err("did not find expected ',' or ']'"),
        }
    }
}

// ---- serde: a Deserializer over a parsed Node -------------------------------
//
// Decoding follows yaml.v3's rules for the Go struct's field types: any scalar
// fills a string (its text as written), a null leaves the zero value, a
// sequence or mapping where a string is wanted is a type error, and a bool
// takes YAML's true/false spellings plus the YAML 1.1 y/yes/on and n/no/off.
// A null list element is dropped, as yaml.v3 drops it.

impl<'de> Deserializer<'de> for &'de Node {
    type Error = Error;

    fn deserialize_any<V: Visitor<'de>>(self, v: V) -> Result<V::Value, Error> {
        match self {
            Node::Null => v.visit_unit(),
            Node::Scalar { value, .. } => v.visit_str(value),
            Node::Seq(items) => v.visit_seq(SeqDe(items.iter())),
            Node::Map(entries) => v.visit_map(MapDe {
                it: entries.iter(),
                value: None,
            }),
        }
    }

    fn deserialize_bool<V: Visitor<'de>>(self, v: V) -> Result<V::Value, Error> {
        match self {
            Node::Null => v.visit_bool(false),
            Node::Scalar { value, plain } => {
                let s = value.as_str();
                if *plain && matches!(s, "true" | "True" | "TRUE") {
                    return v.visit_bool(true);
                }
                if *plain && matches!(s, "false" | "False" | "FALSE") {
                    return v.visit_bool(false);
                }
                match s {
                    "y" | "Y" | "yes" | "Yes" | "YES" | "on" | "On" | "ON" => v.visit_bool(true),
                    "n" | "N" | "no" | "No" | "NO" | "off" | "Off" | "OFF" => v.visit_bool(false),
                    _ => Err(Error(format!("cannot unmarshal {s:?} into bool"))),
                }
            }
            _ => err("cannot unmarshal a collection into bool"),
        }
    }

    fn deserialize_str<V: Visitor<'de>>(self, v: V) -> Result<V::Value, Error> {
        match self {
            Node::Null => v.visit_str(""),
            Node::Scalar { value, .. } => v.visit_str(value),
            _ => err("cannot unmarshal a collection into string"),
        }
    }

    fn deserialize_string<V: Visitor<'de>>(self, v: V) -> Result<V::Value, Error> {
        self.deserialize_str(v)
    }

    fn deserialize_option<V: Visitor<'de>>(self, v: V) -> Result<V::Value, Error> {
        match self {
            Node::Null => v.visit_none(),
            _ => v.visit_some(self),
        }
    }

    fn deserialize_seq<V: Visitor<'de>>(self, v: V) -> Result<V::Value, Error> {
        match self {
            Node::Null => v.visit_seq(SeqDe([].iter())),
            Node::Seq(items) => v.visit_seq(SeqDe(items.iter())),
            _ => err("cannot unmarshal into a sequence"),
        }
    }

    fn deserialize_map<V: Visitor<'de>>(self, v: V) -> Result<V::Value, Error> {
        match self {
            Node::Null => v.visit_map(MapDe {
                it: [].iter(),
                value: None,
            }),
            Node::Map(entries) => v.visit_map(MapDe {
                it: entries.iter(),
                value: None,
            }),
            _ => err("cannot unmarshal into a mapping"),
        }
    }

    fn deserialize_struct<V: Visitor<'de>>(
        self,
        _name: &'static str,
        _fields: &'static [&'static str],
        v: V,
    ) -> Result<V::Value, Error> {
        self.deserialize_map(v)
    }

    fn deserialize_ignored_any<V: Visitor<'de>>(self, v: V) -> Result<V::Value, Error> {
        v.visit_unit()
    }

    serde::forward_to_deserialize_any! {
        i8 i16 i32 i64 i128 u8 u16 u32 u64 u128 f32 f64 char bytes byte_buf
        unit unit_struct newtype_struct tuple tuple_struct enum identifier
    }
}

struct SeqDe<'a>(std::slice::Iter<'a, Node>);

impl<'de> SeqAccess<'de> for SeqDe<'de> {
    type Error = Error;
    fn next_element_seed<T: DeserializeSeed<'de>>(
        &mut self,
        seed: T,
    ) -> Result<Option<T::Value>, Error> {
        // yaml.v3 drops a null list element: it cannot set a string or a
        // struct to null, so the element is skipped rather than zeroed.
        match self.0.by_ref().find(|n| **n != Node::Null) {
            Some(n) => seed.deserialize(n).map(Some),
            None => Ok(None),
        }
    }
}

struct MapDe<'a> {
    it: std::slice::Iter<'a, (String, Node)>,
    value: Option<&'a Node>,
}

impl<'de> MapAccess<'de> for MapDe<'de> {
    type Error = Error;
    fn next_key_seed<K: DeserializeSeed<'de>>(
        &mut self,
        seed: K,
    ) -> Result<Option<K::Value>, Error> {
        match self.it.next() {
            Some((k, v)) => {
                self.value = Some(v);
                seed.deserialize(de::value::StrDeserializer::<Error>::new(k))
                    .map(Some)
            }
            None => Ok(None),
        }
    }
    fn next_value_seed<V: DeserializeSeed<'de>>(&mut self, seed: V) -> Result<V::Value, Error> {
        match self.value.take() {
            Some(v) => seed.deserialize(v),
            None => err("value requested before key"),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn s(v: &str) -> Node {
        Node::Scalar {
            value: v.to_string(),
            plain: true,
        }
    }

    #[test]
    fn block_map_and_seq() {
        let n = parse("approvers:\n  - \"@a\"\n  - b # c\noptions:\n  no_parent_owners: true\n")
            .unwrap();
        assert_eq!(
            n,
            Node::Map(vec![
                (
                    "approvers".into(),
                    Node::Seq(vec![
                        Node::Scalar {
                            value: "@a".into(),
                            plain: false
                        },
                        s("b")
                    ])
                ),
                (
                    "options".into(),
                    Node::Map(vec![("no_parent_owners".into(), s("true"))])
                ),
            ])
        );
    }

    #[test]
    fn same_indent_sequence_and_seq_of_maps() {
        let n = parse("per_file:\n- pattern: \"*.md\"\n  approvers:\n  - x\nk: v\n").unwrap();
        let Node::Map(m) = n else { panic!() };
        assert_eq!(m.len(), 2);
        let Node::Seq(items) = &m[0].1 else { panic!() };
        assert_eq!(
            items[0],
            Node::Map(vec![
                (
                    "pattern".into(),
                    Node::Scalar {
                        value: "*.md".into(),
                        plain: false
                    }
                ),
                ("approvers".into(), Node::Seq(vec![s("x")])),
            ])
        );
    }

    #[test]
    fn flow_and_errors() {
        assert_eq!(
            parse("a: [x, 'y''z', ]").unwrap(),
            Node::Map(vec![(
                "a".into(),
                Node::Seq(vec![
                    s("x"),
                    Node::Scalar {
                        value: "y'z".into(),
                        plain: false
                    }
                ])
            )])
        );
        assert!(parse("a: @x").is_err());
        assert_eq!(
            parse("a: [-]").unwrap(),
            Node::Map(vec![("a".into(), Node::Seq(vec![s("-")]))])
        );
        assert!(parse("a: [- ]").is_err());
        assert!(parse("a: *x").is_err());
        assert_eq!(
            parse("a: &x [y]\nb: *x").unwrap(),
            Node::Map(vec![
                ("a".into(), Node::Seq(vec![s("y")])),
                ("b".into(), Node::Seq(vec![s("y")]))
            ])
        );
        assert!(parse("a: 1\na: 2").is_err());
        assert_eq!(parse("- a\n  b").unwrap(), Node::Seq(vec![s("a b")]));
        assert!(parse("- 'a'\n  b").is_err());
        assert!(parse("\ta: 1").is_err());
        assert_eq!(parse("# only\n\n").unwrap(), Node::Null);
        assert!(parse("set noparent\n@bob").is_err());
    }

    #[test]
    fn comments_respect_quotes() {
        assert_eq!(strip_comment("a: \"x # y\" # z"), "a: \"x # y\" ");
        assert_eq!(strip_comment("a: it's # z"), "a: it's ");
        assert_eq!(strip_comment("a: b#c"), "a: b#c");
    }
}
