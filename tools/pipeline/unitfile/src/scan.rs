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

//! A small scanner for the part of Starlark a BUILD file uses: enough to
//! find where a call starts and ends and to read literal values out of it.
//! It is not a Starlark parser -- nothing is evaluated, and anything that is
//! not a literal comes back as "not a literal" for the caller to refuse.

use std::collections::HashMap;

use crate::gocompat::quote::quote;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub(crate) enum Kind {
    Ident,
    Str,
    Number,
    Punct,
}

#[derive(Clone, Debug)]
pub(crate) struct Token {
    pub kind: Kind,
    /// The identifier, the digits, the punctuation, or -- for a string --
    /// its value with the quotes gone and the escapes resolved.
    pub text: String,
    pub line: usize,
}

impl Token {
    fn is(&self, punct: &str) -> bool {
        self.kind == Kind::Punct && self.text == punct
    }
}

fn is_ident_start(c: u8) -> bool {
    c == b'_' || c.is_ascii_alphabetic()
}

fn lossy(b: &[u8]) -> String {
    String::from_utf8_lossy(b).into_owned()
}

/// Splits src into tokens. Comments and whitespace are dropped. On an error
/// it also returns the tokens read up to it (none, for a prefixed string,
/// as the Go reader does), so the caller can say which call it was in.
pub(crate) fn tokenize(src: &[u8]) -> (Vec<Token>, Option<String>) {
    let mut toks: Vec<Token> = Vec::new();
    let mut line = 1usize;
    let mut i = 0usize;
    let n = src.len();
    while i < n {
        let c = src[i];
        if c == b'\n' {
            line += 1;
            i += 1;
        } else if c == b' ' || c == b'\t' || c == b'\r' {
            i += 1;
        } else if c == b'\\' && i + 1 < n && src[i + 1] == b'\n' {
            line += 1;
            i += 2;
        } else if c == b'#' {
            while i < n && src[i] != b'\n' {
                i += 1;
            }
        } else if c == b'"' || c == b'\'' {
            match scan_string(&src[i..], false) {
                Ok((val, used, lines)) => {
                    toks.push(Token {
                        kind: Kind::Str,
                        text: val,
                        line,
                    });
                    line += lines;
                    i += used;
                }
                Err(e) => return (toks, Some(format!("line {line}: {e}"))),
            }
        } else if is_ident_start(c) {
            let mut j = i;
            while j < n && (is_ident_start(src[j]) || src[j].is_ascii_digit()) {
                j += 1;
            }
            let word = lossy(&src[i..j]);
            if j < n && (src[j] == b'"' || src[j] == b'\'') && is_string_prefix(&word) {
                let raw = word.contains('r') || word.contains('R');
                match scan_string(&src[j..], raw) {
                    Ok((val, used, lines)) => {
                        toks.push(Token {
                            kind: Kind::Str,
                            text: val,
                            line,
                        });
                        line += lines;
                        i = j + used;
                        continue;
                    }
                    Err(e) => return (Vec::new(), Some(format!("line {line}: {e}"))),
                }
            }
            toks.push(Token {
                kind: Kind::Ident,
                text: word,
                line,
            });
            i = j;
        } else if c.is_ascii_digit() {
            let mut j = i;
            while j < n && (src[j].is_ascii_digit() || is_ident_start(src[j]) || src[j] == b'.') {
                j += 1;
            }
            toks.push(Token {
                kind: Kind::Number,
                text: lossy(&src[i..j]),
                line,
            });
            i = j;
        } else {
            // "==", "!=", "<=", ">=", "+=" and friends are one token, so a
            // lone "=" always means a keyword argument.
            if i + 1 < n && src[i + 1] == b'=' && b"=!<>+-*/%|&^".contains(&c) {
                toks.push(Token {
                    kind: Kind::Punct,
                    text: lossy(&src[i..i + 2]),
                    line,
                });
                i += 2;
                continue;
            }
            // Go's string(c) of a byte is the rune U+00XX.
            toks.push(Token {
                kind: Kind::Punct,
                text: char::from(c).to_string(),
                line,
            });
            i += 1;
        }
    }
    (toks, None)
}

fn is_string_prefix(word: &str) -> bool {
    matches!(word.to_lowercase().as_str(), "r" | "b" | "rb" | "br")
}

/// Reads the string literal at the start of s: single or double quoted, or
/// triple quoted. Returns the value, the bytes consumed and the newlines
/// crossed.
fn scan_string(s: &[u8], raw: bool) -> Result<(String, usize, usize), String> {
    let quote_c = s[0];
    let triple = s.len() >= 3 && s[1] == quote_c && s[2] == quote_c;
    let mut i = if triple { 3 } else { 1 };
    let mut lines = 0usize;
    let mut b: Vec<u8> = Vec::new();
    while i < s.len() {
        let c = s[i];
        if c == b'\\' && i + 1 < s.len() {
            let next = s[i + 1];
            if next == b'\n' {
                lines += 1;
            }
            if raw {
                b.push(c);
                b.push(next);
                i += 2;
                continue;
            }
            i += 2;
            match next {
                b'n' => b.push(b'\n'),
                b't' => b.push(b'\t'),
                b'r' => b.push(b'\r'),
                b'\\' | b'\'' | b'"' => b.push(next),
                b'\n' => {}
                _ => {
                    b.push(b'\\');
                    b.push(next);
                }
            }
        } else if c == quote_c && !triple {
            return Ok((lossy(&b), i + 1, lines));
        } else if c == quote_c && triple && s[i..].starts_with(&s[..3]) {
            return Ok((lossy(&b), i + 3, lines));
        } else if c == b'\n' && !triple {
            return Err(format!(
                "a string starting {} is not closed before the end of the line",
                clip(s)
            ));
        } else {
            if c == b'\n' {
                lines += 1;
            }
            b.push(c);
            i += 1;
        }
    }
    Err(format!("a string starting {} is never closed", clip(s)))
}

fn clip(s: &[u8]) -> String {
    let mut s = s;
    if let Some(nl) = s.iter().position(|&c| c == b'\n') {
        s = &s[..nl];
    }
    if s.len() > 30 {
        return lossy(&s[..30]) + "...";
    }
    lossy(s)
}

fn closer_of(t: &str) -> Option<&'static str> {
    match t {
        "(" => Some(")"),
        "[" => Some("]"),
        "{" => Some("}"),
        _ => None,
    }
}

fn is_closer(t: &Token) -> bool {
    t.is(")") || t.is("]") || t.is("}")
}

/// The index of the bracket that closes toks[open], counting all three
/// kinds, refusing a mismatch such as "[ ... )".
pub(crate) fn match_bracket(toks: &[Token], open: usize) -> Result<usize, String> {
    let mut stack: Vec<&Token> = Vec::new();
    for (i, t) in toks.iter().enumerate().skip(open) {
        if t.kind != Kind::Punct {
            continue;
        }
        if closer_of(&t.text).is_some() {
            stack.push(t);
            continue;
        }
        if !is_closer(t) {
            continue;
        }
        let Some(top) = stack.last() else {
            return Err(format!(
                "line {}: {} closes nothing",
                t.line,
                quote(&t.text)
            ));
        };
        if closer_of(&top.text) != Some(t.text.as_str()) {
            return Err(format!(
                "line {}: {} closes the {} opened on line {}",
                t.line,
                quote(&t.text),
                quote(&top.text),
                top.line
            ));
        }
        stack.pop();
        if stack.is_empty() {
            return Ok(i);
        }
    }
    Err(format!(
        "the {} opened on line {} is never closed",
        quote(&toks[open].text),
        toks[open].line
    ))
}

/// Cuts toks at each separator that is not inside brackets. A trailing
/// separator does not make an empty last piece.
fn split_top_level<'a>(toks: &'a [Token], sep: &str) -> Vec<&'a [Token]> {
    let mut parts = Vec::new();
    let (mut depth, mut start) = (0i64, 0usize);
    for (i, t) in toks.iter().enumerate() {
        if t.kind != Kind::Punct {
            continue;
        }
        if closer_of(&t.text).is_some() {
            depth += 1;
        } else if is_closer(t) {
            depth -= 1;
        } else if depth == 0 && t.text == sep {
            parts.push(&toks[start..i]);
            start = i + 1;
        }
    }
    if start < toks.len() {
        parts.push(&toks[start..]);
    }
    parts
}

/// A literal the scanner read, or `NotLiteral` for a name, a call such as
/// glob() or select(), a concatenation, a comprehension.
#[derive(Clone, Debug, PartialEq)]
pub(crate) enum Value {
    NotLiteral,
    Str(String),
    Int(i64),
    Bool(bool),
    List(Vec<Value>),
    /// The pairs in the order written.
    Dict(Vec<(Value, Value)>),
}

/// Reads the literal that toks spell out, or says it is not one.
pub(crate) fn read_value(toks: &[Token]) -> Value {
    if toks.is_empty() {
        return Value::NotLiteral;
    }
    if toks.len() == 1 {
        let t = &toks[0];
        return match t.kind {
            Kind::Str => Value::Str(t.text.clone()),
            // strconv.Atoi: decimal digits only (a number token never
            // starts with a sign), and it must fit an int.
            Kind::Number if t.text.bytes().all(|c| c.is_ascii_digit()) => t
                .text
                .parse::<i64>()
                .map(Value::Int)
                .unwrap_or(Value::NotLiteral),
            Kind::Ident if t.text == "True" || t.text == "False" => Value::Bool(t.text == "True"),
            _ => Value::NotLiteral,
        };
    }
    let (first, last) = (&toks[0], &toks[toks.len() - 1]);
    if !first.is("[") && !first.is("{") {
        return Value::NotLiteral;
    }
    // "[a] + [b]" starts and ends with the right brackets too, so the first
    // bracket has to be the one the last closes.
    match match_bracket(toks, 0) {
        Ok(end) if end == toks.len() - 1 => {}
        _ => return Value::NotLiteral,
    }
    let inner = &toks[1..toks.len() - 1];
    if first.is("[") && last.is("]") {
        return Value::List(
            split_top_level(inner, ",")
                .into_iter()
                .map(read_value)
                .collect(),
        );
    }
    if first.is("{") && last.is("}") {
        let mut pairs = Vec::new();
        for part in split_top_level(inner, ",") {
            let kv = split_top_level(part, ":");
            if kv.len() != 2 {
                return Value::NotLiteral;
            }
            pairs.push((read_value(kv[0]), read_value(kv[1])));
        }
        return Value::Dict(pairs);
    }
    Value::NotLiteral
}

/// One call to a function, with its keyword arguments as written.
pub(crate) struct Call {
    pub line: usize,
    pub args: HashMap<String, Value>,
}

/// Every call to `func` in src. A `def func(` and a method call `x.func(`
/// are not calls to it; neither is the name in a string or a comment.
pub(crate) fn find_calls(src: &[u8], func: &str) -> Result<Vec<Call>, String> {
    let (toks, err) = tokenize(src);
    if let Some(err) = err {
        // If the text stopped making sense inside a call to func, name it.
        let mut i = toks.len() as isize - 2;
        while i >= 0 {
            let iu = i as usize;
            if toks[iu].kind != Kind::Ident || toks[iu].text != func || !toks[iu + 1].is("(") {
                i -= 1;
                continue;
            }
            if match_bracket(&toks, iu + 1).is_err() {
                if let Some(name) = name_in(&toks[iu + 2..]) {
                    return Err(format!(
                        "{func}(name = {}), which starts on line {}: {err}",
                        quote(&name),
                        toks[iu].line
                    ));
                }
                return Err(format!(
                    "{func}(...), which starts on line {}: {err}",
                    toks[iu].line
                ));
            }
            break;
        }
        return Err(err);
    }
    let mut calls = Vec::new();
    let mut i = 0usize;
    while i + 1 < toks.len() {
        if toks[i].kind != Kind::Ident || toks[i].text != func || !toks[i + 1].is("(") {
            i += 1;
            continue;
        }
        if i > 0
            && (toks[i - 1].is(".")
                || (toks[i - 1].kind == Kind::Ident && toks[i - 1].text == "def"))
        {
            i += 1;
            continue;
        }
        let line = toks[i].line;
        let end = match match_bracket(&toks, i + 1) {
            Ok(e) => e,
            Err(e) => {
                if let Some(name) = name_in(&toks[i + 2..]) {
                    return Err(format!("line {line}: {func}(name = {}): {e}", quote(&name)));
                }
                return Err(format!("line {line}: {func}(...): {e}"));
            }
        };
        let mut args = HashMap::new();
        for arg in split_top_level(&toks[i + 2..end], ",") {
            if arg.len() < 3 || arg[0].kind != Kind::Ident || !arg[1].is("=") {
                // Go indexes arg[0] here and panics on an empty argument
                // ("f(, x)"); this names the call's line instead.
                let at = arg.first().map(|t| t.line).unwrap_or(line);
                return Err(format!(
                    "line {at}: {func}(...): every argument must be written name = value; found one that is not (positional, * or **)"
                ));
            }
            args.insert(arg[0].text.clone(), read_value(&arg[2..]));
        }
        calls.push(Call { line, args });
        i = end + 1;
    }
    Ok(calls)
}

/// Finds `name = "..."` in the tokens of a call whose end is unknown.
fn name_in(toks: &[Token]) -> Option<String> {
    let mut i = 0;
    while i + 2 < toks.len() && i < 200 {
        if toks[i].kind == Kind::Ident
            && toks[i].text == "name"
            && toks[i + 1].is("=")
            && toks[i + 2].kind == Kind::Str
        {
            // Go returns the first match, and an empty one reads as none.
            let t = &toks[i + 2].text;
            return if t.is_empty() { None } else { Some(t.clone()) };
        }
        i += 1;
    }
    None
}
