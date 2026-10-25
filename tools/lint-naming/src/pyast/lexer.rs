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

//! CPython 3.12's tokenizer (Parser/tokenizer.c), far enough to say whether
//! a file tokenizes, what its tokens are, and which SyntaxWarnings the
//! tokenizer and the string decoder raise, on which line.

use super::strings::{decode_literal, LiteralValue};
use crate::pystr::{is_printable, is_xid_continue, is_xid_start};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Kind {
    Name,
    Number,
    Str,
    FStart,
    FMiddle,
    FEnd,
    Op,
    Newline,
    Indent,
    Dedent,
    EndMarker,
}

#[derive(Clone, Debug)]
pub struct Token {
    pub kind: Kind,
    /// NAME, NUMBER and OP text.
    pub text: String,
    pub line: usize,
    /// For Str: the decoded value (or the decode error).
    pub value: Option<LiteralValue>,
    /// For FMiddle: true when it fails to decode.
    pub bad: bool,
}

/// A SyntaxWarning, tied to the token whose fetching (or parsing) raises it.
#[derive(Clone, Debug)]
pub struct Warn {
    pub token: usize,
    pub line: usize,
    pub message: String,
    /// Raised by the tokenizer (so printed even after the parser gives up),
    /// rather than when the parser consumes a string.
    pub from_tokenizer: bool,
}

pub struct Lexed {
    pub tokens: Vec<Token>,
    pub warnings: Vec<Warn>,
    /// The tokenizer stopped on an error after `tokens`.
    pub error: bool,
}

const TABSIZE: usize = 8;
const MAXINDENT: usize = 100;
const MAXLEVEL: usize = 200;

#[derive(Clone, Copy, PartialEq, Eq)]
enum Frame {
    /// Inside `{...}` of an f-string; `level` is the bracket level just
    /// after its `{`.
    Field { level: usize },
    /// In the format spec after `:` of the field opened at `level`.
    Spec { level: usize },
}

struct FString {
    quote: char,
    quote_size: usize,
    raw: bool,
    frames: Vec<Frame>,
    /// Decode warnings of this f-string's middles, raised at its end.
    pending: Vec<(usize, String)>,
}

struct Lexer<'a> {
    src: &'a [char],
    pos: usize,
    line: usize,
    atbol: bool,
    parens: Vec<char>,
    indstack: Vec<usize>,
    altindstack: Vec<usize>,
    pendin: i64,
    fstrings: Vec<FString>,
    tokens: Vec<Token>,
    warnings: Vec<Warn>,
}

type R<T> = Result<T, ()>;

fn is_potential_identifier_start(c: char) -> bool {
    c.is_ascii_alphabetic() || c == '_' || (c as u32) >= 128
}

fn is_potential_identifier_char(c: char) -> bool {
    c.is_ascii_alphanumeric() || c == '_' || (c as u32) >= 128
}

const TWO_CHAR: &[&str] = &[
    "!=", "%=", "&=", "**", "*=", "+=", "-=", "->", "//", "/=", ":=", "<<", "<=", "<>", "==", ">=",
    ">>", "@=", "^=", "|=",
];
const THREE_CHAR: &[&str] = &["**=", "//=", "<<=", ">>="];

impl<'a> Lexer<'a> {
    fn peek(&self) -> Option<char> {
        self.src.get(self.pos).copied()
    }

    fn peek_at(&self, n: usize) -> Option<char> {
        self.src.get(self.pos + n).copied()
    }

    fn bump(&mut self) -> Option<char> {
        let c = self.src.get(self.pos).copied();
        if let Some(c) = c {
            self.pos += 1;
            if c == '\n' {
                self.line += 1;
            }
        }
        c
    }

    fn push(&mut self, kind: Kind, text: String, line: usize) {
        self.tokens.push(Token {
            kind,
            text,
            line,
            value: None,
            bad: false,
        });
    }

    fn warn_tokenizer(&mut self, line: usize, message: &str) {
        let token = self.tokens.len();
        self.warnings.push(Warn {
            token,
            line,
            message: message.to_string(),
            from_tokenizer: true,
        });
    }

    fn in_fstring_middle(&self) -> bool {
        match self.fstrings.last() {
            Some(fs) => !matches!(fs.frames.last(), Some(Frame::Field { .. })),
            None => false,
        }
    }

    fn run(&mut self) -> R<()> {
        loop {
            if self.in_fstring_middle() {
                self.fstring_middle()?;
                continue;
            }
            if self.next_regular()? {
                return Ok(());
            }
        }
    }

    /// One regular-mode token (or pending indent/dedent). True at ENDMARKER.
    fn next_regular(&mut self) -> R<bool> {
        let mut blankline = false;
        if self.atbol {
            self.atbol = false;
            let mut col = 0usize;
            let mut altcol = 0usize;
            let mut cont_line_col = 0usize;
            loop {
                match self.peek() {
                    Some(' ') => {
                        col += 1;
                        altcol += 1;
                        self.bump();
                    }
                    Some('\t') => {
                        col = (col / TABSIZE + 1) * TABSIZE;
                        altcol += 1;
                        self.bump();
                    }
                    Some('\x0c') => {
                        col = 0;
                        altcol = 0;
                        self.bump();
                    }
                    Some('\\') => {
                        if cont_line_col == 0 {
                            cont_line_col = col;
                        }
                        self.bump();
                        self.continuation_line()?;
                    }
                    _ => break,
                }
            }
            let c = self.peek();
            if c == Some('#') || c == Some('\n') || c == Some('\r') {
                blankline = true;
            }
            if !blankline && self.parens.is_empty() {
                if cont_line_col != 0 {
                    col = cont_line_col;
                    altcol = cont_line_col;
                }
                let top = *self.indstack.last().unwrap();
                let alttop = *self.altindstack.last().unwrap();
                if col == top {
                    if altcol != alttop {
                        return Err(());
                    }
                } else if col > top {
                    if self.indstack.len() >= MAXINDENT {
                        return Err(());
                    }
                    if altcol <= alttop {
                        return Err(());
                    }
                    self.pendin += 1;
                    self.indstack.push(col);
                    self.altindstack.push(altcol);
                } else {
                    while self.indstack.len() > 1 && col < *self.indstack.last().unwrap() {
                        self.pendin -= 1;
                        self.indstack.pop();
                        self.altindstack.pop();
                    }
                    if col != *self.indstack.last().unwrap() {
                        return Err(());
                    }
                    if altcol != *self.altindstack.last().unwrap() {
                        return Err(());
                    }
                }
            }
        }

        if self.pendin != 0 {
            let line = self.line;
            if self.pendin < 0 {
                self.pendin += 1;
                self.push(Kind::Dedent, String::new(), line);
            } else {
                self.pendin -= 1;
                self.push(Kind::Indent, String::new(), line);
            }
            return Ok(false);
        }

        loop {
            // again:
            while matches!(self.peek(), Some(' ') | Some('\t') | Some('\x0c')) {
                self.bump();
            }
            if self.peek() == Some('#') {
                while !matches!(self.peek(), None | Some('\n') | Some('\r')) {
                    self.bump();
                }
            }
            let line = self.line;
            let Some(c) = self.peek() else {
                if !self.parens.is_empty() || !self.fstrings.is_empty() {
                    return Err(());
                }
                self.push(Kind::EndMarker, String::new(), line);
                return Ok(true);
            };

            if is_potential_identifier_start(c) {
                return self.identifier_or_string().map(|_| false);
            }

            if c == '\n' {
                self.bump();
                self.atbol = true;
                if blankline || !self.parens.is_empty() {
                    return Ok(false);
                }
                self.push(Kind::Newline, String::new(), line);
                return Ok(false);
            }

            if c == '.' {
                if self.peek_at(1).map_or(false, |d| d.is_ascii_digit()) {
                    self.bump();
                    return self.number_fraction(line, String::from(".")).map(|_| false);
                }
                if self.peek_at(1) == Some('.') && self.peek_at(2) == Some('.') {
                    self.pos += 3;
                    self.push(Kind::Op, "...".into(), line);
                    return Ok(false);
                }
                self.bump();
                self.push(Kind::Op, ".".into(), line);
                return Ok(false);
            }

            if c.is_ascii_digit() {
                return self.number(line).map(|_| false);
            }

            if c == '\'' || c == '"' {
                return self.string(line, false, false, false).map(|_| false);
            }

            if c == '\\' {
                self.bump();
                self.continuation_line()?;
                continue;
            }

            return self.operator(c, line).map(|_| false);
        }
    }

    fn continuation_line(&mut self) -> R<()> {
        if self.peek() != Some('\n') {
            return Err(());
        }
        self.bump();
        if self.peek().is_none() {
            return Err(());
        }
        Ok(())
    }

    fn operator(&mut self, c: char, line: usize) -> R<()> {
        // f-string punctuation at the top of a replacement field.
        if let Some(fs) = self.fstrings.last() {
            if let Some(Frame::Field { level }) = fs.frames.last() {
                let level = *level;
                if c == ':' && self.parens.len() == level {
                    self.bump();
                    let fs = self.fstrings.last_mut().unwrap();
                    fs.frames.pop();
                    fs.frames.push(Frame::Spec { level });
                    self.push(Kind::Op, ":".into(), line);
                    return Ok(());
                }
            }
        }

        let two: String = [Some(c), self.peek_at(1)].iter().flatten().collect();
        if TWO_CHAR.contains(&two.as_str()) {
            let three: String = [Some(c), self.peek_at(1), self.peek_at(2)]
                .iter()
                .flatten()
                .collect();
            if THREE_CHAR.contains(&three.as_str()) {
                self.pos += 3;
                self.push(Kind::Op, three, line);
            } else {
                self.pos += 2;
                self.push(Kind::Op, two, line);
            }
            return Ok(());
        }

        match c {
            '(' | '[' | '{' => {
                if self.parens.len() >= MAXLEVEL {
                    return Err(());
                }
                self.parens.push(c);
            }
            ')' | ']' | '}' => {
                let in_field = matches!(
                    self.fstrings.last().and_then(|fs| fs.frames.last()),
                    Some(Frame::Field { .. })
                );
                if self.parens.is_empty() {
                    return Err(());
                }
                let opening = self.parens.pop().unwrap();
                let matched = matches!((opening, c), ('(', ')') | ('[', ']') | ('{', '}'));
                if !matched {
                    return Err(());
                }
                if in_field && c == '}' {
                    let level = match self.fstrings.last().unwrap().frames.last() {
                        Some(Frame::Field { level }) => *level,
                        _ => usize::MAX,
                    };
                    if self.parens.len() + 1 == level {
                        self.fstrings.last_mut().unwrap().frames.pop();
                        // A field nested in a format spec returns to the spec.
                    }
                }
            }
            _ => {}
        }
        if !is_printable(c) {
            return Err(());
        }
        self.bump();
        self.push(Kind::Op, c.to_string(), line);
        Ok(())
    }

    fn identifier_or_string(&mut self) -> R<()> {
        let line = self.line;
        let start = self.pos;
        let (mut saw_b, mut saw_r, mut saw_u, mut saw_f) = (false, false, false, false);
        loop {
            let Some(c) = self.peek() else { break };
            if !(saw_b || saw_u || saw_f) && (c == 'b' || c == 'B') {
                saw_b = true;
            } else if !(saw_b || saw_u || saw_r || saw_f) && (c == 'u' || c == 'U') {
                saw_u = true;
            } else if !(saw_r || saw_u) && (c == 'r' || c == 'R') {
                saw_r = true;
            } else if !(saw_f || saw_b || saw_u) && (c == 'f' || c == 'F') {
                saw_f = true;
            } else {
                break;
            }
            self.bump();
            if let Some(q) = self.peek() {
                if q == '"' || q == '\'' {
                    if saw_f {
                        return self.fstring_start(line, saw_r);
                    }
                    return self.string(line, saw_b, saw_r, true);
                }
            }
        }
        while self.peek().map_or(false, is_potential_identifier_char) {
            self.bump();
        }
        let name: String = self.src[start..self.pos].iter().collect();
        if !name.is_ascii() {
            let mut it = name.chars();
            let first = it.next().unwrap();
            if !(first == '_' || is_xid_start(first)) || !it.all(|c| c == '_' || is_xid_continue(c))
            {
                return Err(());
            }
        }
        self.push(Kind::Name, name, line);
        Ok(())
    }

    /// A (non f-) string literal; the prefix, if any, is already consumed.
    fn string(&mut self, line: usize, bytes: bool, raw: bool, _prefixed: bool) -> R<()> {
        let quote = self.bump().unwrap();
        let mut quote_size = 1;
        let mut end_quote_size = 0;
        if self.peek() == Some(quote) {
            self.bump();
            if self.peek() == Some(quote) {
                self.bump();
                quote_size = 3;
            } else {
                end_quote_size = 1;
            }
        }
        let body_start = self.pos;
        while end_quote_size != quote_size {
            let Some(c) = self.bump() else { return Err(()) };
            if quote_size == 1 && c == '\n' {
                return Err(());
            }
            if c == quote {
                end_quote_size += 1;
            } else {
                end_quote_size = 0;
                if c == '\\' {
                    self.bump();
                }
            }
        }
        let body: Vec<char> = if quote_size == 1 && body_start == self.pos {
            Vec::new()
        } else {
            self.src[body_start..self.pos - quote_size].to_vec()
        };
        let token = self.tokens.len();
        let decoded = decode_literal(&body, bytes, raw);
        if let LiteralValue::Str(_, Some((offset, msg)))
        | LiteralValue::Bytes(Some((offset, msg))) = &decoded
        {
            let nl = body[..*offset].iter().filter(|&&c| c == '\n').count();
            self.warnings.push(Warn {
                token,
                line: line + nl,
                message: msg.clone(),
                from_tokenizer: false,
            });
        }
        self.tokens.push(Token {
            kind: Kind::Str,
            text: String::new(),
            line,
            value: Some(decoded),
            bad: false,
        });
        Ok(())
    }

    fn fstring_start(&mut self, line: usize, raw: bool) -> R<()> {
        let quote = self.bump().unwrap();
        let mut quote_size = 1;
        if self.peek() == Some(quote) && self.peek_at(1) == Some(quote) {
            self.pos += 2;
            quote_size = 3;
        }
        self.push(Kind::FStart, String::new(), line);
        self.fstrings.push(FString {
            quote,
            quote_size,
            raw,
            frames: Vec::new(),
            pending: Vec::new(),
        });
        Ok(())
    }

    fn at_fstring_end(&self) -> bool {
        let fs = self.fstrings.last().unwrap();
        (0..fs.quote_size).all(|i| self.peek_at(i) == Some(fs.quote))
    }

    /// Lex literal text of the innermost f-string (top level or format
    /// spec) up to the next `{`, `}` or closing quote.
    fn fstring_middle(&mut self) -> R<()> {
        let in_spec = matches!(
            self.fstrings.last().unwrap().frames.last(),
            Some(Frame::Spec { .. })
        );
        let start_line = self.line;
        if !in_spec && self.at_fstring_end() {
            let n = self.fstrings.last().unwrap().quote_size;
            self.pos += n;
            let fs = self.fstrings.pop().unwrap();
            let token = self.tokens.len();
            for (line, message) in fs.pending {
                self.warnings.push(Warn {
                    token,
                    line,
                    message,
                    from_tokenizer: false,
                });
            }
            self.push(Kind::FEnd, String::new(), start_line);
            return Ok(());
        }
        let (quote, quote_size, raw) = {
            let fs = self.fstrings.last().unwrap();
            (fs.quote, fs.quote_size, fs.raw)
        };
        let mut text: Vec<char> = Vec::new();
        loop {
            if self.at_fstring_end() {
                if in_spec {
                    // The f-string closes inside a format spec: the parser
                    // will find no '}', so this is an error either way.
                    return Err(());
                }
                break;
            }
            let Some(c) = self.peek() else { return Err(()) };
            if c == '\n' && quote_size == 1 {
                return Err(());
            }
            if c == '{' {
                if !in_spec && self.peek_at(1) == Some('{') {
                    self.pos += 2;
                    text.push('{');
                    self.emit_middle(&text, start_line, in_spec);
                    return Ok(());
                }
                self.emit_middle(&text, start_line, in_spec);
                // The '{' itself is lexed in regular mode as an operator.
                let line = self.line;
                self.bump();
                if self.parens.len() >= MAXLEVEL {
                    return Err(());
                }
                self.parens.push('{');
                let level = self.parens.len();
                self.fstrings
                    .last_mut()
                    .unwrap()
                    .frames
                    .push(Frame::Field { level });
                self.push(Kind::Op, "{".into(), line);
                return Ok(());
            }
            if c == '}' {
                if !in_spec && self.peek_at(1) == Some('}') {
                    self.pos += 2;
                    text.push('}');
                    self.emit_middle(&text, start_line, in_spec);
                    return Ok(());
                }
                self.emit_middle(&text, start_line, in_spec);
                if !in_spec {
                    // f-string: single '}' is not allowed
                    return Err(());
                }
                // End of the format spec: the '}' closes the field.
                let line = self.line;
                self.bump();
                let fs = self.fstrings.last_mut().unwrap();
                fs.frames.pop();
                match self.parens.pop() {
                    Some('{') => {}
                    _ => return Err(()),
                }
                self.push(Kind::Op, "}".into(), line);
                return Ok(());
            }
            if c == '\\' {
                self.bump();
                text.push('\\');
                let peek = self.peek();
                if peek == Some('{') || peek == Some('}') {
                    if !raw {
                        let line = self.line;
                        self.warn_tokenizer(
                            line,
                            &format!("invalid escape sequence '\\{}'", peek.unwrap()),
                        );
                        // The backslash is reported here, not again when decoded.
                        text.pop();
                        text.push('\u{0}');
                    }
                    continue;
                }
                if !raw && peek == Some('N') && self.peek_at(1) == Some('{') {
                    self.bump();
                    self.bump();
                    text.push('N');
                    text.push('{');
                    while let Some(d) = self.peek() {
                        if d == '}'
                            || (d == quote && self.at_fstring_end())
                            || (d == '\n' && quote_size == 1)
                        {
                            break;
                        }
                        self.bump();
                        text.push(d);
                    }
                    if self.peek() == Some('}') {
                        self.bump();
                        text.push('}');
                    }
                    continue;
                }
                if let Some(d) = self.bump() {
                    text.push(d);
                }
                continue;
            }
            self.bump();
            text.push(c);
            if in_spec && c == '\n' {
                self.emit_middle(&text, start_line, in_spec);
                return Ok(());
            }
        }
        self.emit_middle(&text, start_line, in_spec);
        Ok(())
    }

    fn emit_middle(&mut self, text: &[char], start_line: usize, in_spec: bool) {
        if text.is_empty() {
            return;
        }
        let raw = self.fstrings.last().unwrap().raw;
        // A backslash already reported before '{' or '}' stands as NUL here
        // so that decoding neither warns about it again nor fails on it.
        let decoded = decode_literal(text, false, raw);
        let end_line = self.line;
        let mut bad = false;
        match decoded {
            LiteralValue::Str(_, Some((offset, msg))) => {
                let nl = text[..offset].iter().filter(|&&c| c == '\n').count();
                // CPython 3.12 dates a top-level middle's warnings from the
                // line the middle ends on; a format spec's from its start.
                let line = if in_spec { start_line } else { end_line } + nl;
                self.fstrings.last_mut().unwrap().pending.push((line, msg));
            }
            LiteralValue::Bad => bad = true,
            _ => {}
        }
        self.tokens.push(Token {
            kind: Kind::FMiddle,
            text: String::new(),
            line: end_line,
            value: None,
            bad,
        });
    }

    fn number(&mut self, line: usize) -> R<()> {
        let start = self.pos;
        let c = self.bump().unwrap();
        if c == '0' {
            let n = self.peek();
            match n {
                Some('x') | Some('X') => {
                    self.bump();
                    loop {
                        if self.peek() == Some('_') {
                            self.bump();
                        }
                        if !self.peek().map_or(false, |d| d.is_ascii_hexdigit()) {
                            return Err(());
                        }
                        while self.peek().map_or(false, |d| d.is_ascii_hexdigit()) {
                            self.bump();
                        }
                        if self.peek() != Some('_') {
                            break;
                        }
                    }
                    self.verify_end_of_number("hexadecimal", line)?;
                }
                Some('o') | Some('O') => {
                    self.bump();
                    loop {
                        if self.peek() == Some('_') {
                            self.bump();
                        }
                        match self.peek() {
                            Some(d) if ('0'..'8').contains(&d) => {}
                            _ => return Err(()),
                        }
                        while self.peek().map_or(false, |d| ('0'..'8').contains(&d)) {
                            self.bump();
                        }
                        if self.peek() != Some('_') {
                            break;
                        }
                    }
                    if self.peek().map_or(false, |d| d.is_ascii_digit()) {
                        return Err(());
                    }
                    self.verify_end_of_number("octal", line)?;
                }
                Some('b') | Some('B') => {
                    self.bump();
                    loop {
                        if self.peek() == Some('_') {
                            self.bump();
                        }
                        match self.peek() {
                            Some('0') | Some('1') => {}
                            _ => return Err(()),
                        }
                        while matches!(self.peek(), Some('0') | Some('1')) {
                            self.bump();
                        }
                        if self.peek() != Some('_') {
                            break;
                        }
                    }
                    if self.peek().map_or(false, |d| d.is_ascii_digit()) {
                        return Err(());
                    }
                    self.verify_end_of_number("binary", line)?;
                }
                _ => {
                    let mut nonzero = false;
                    loop {
                        if self.peek() == Some('_') {
                            self.bump();
                            if !self.peek().map_or(false, |d| d.is_ascii_digit()) {
                                return Err(());
                            }
                        }
                        if self.peek() != Some('0') {
                            break;
                        }
                        self.bump();
                    }
                    if self.peek().map_or(false, |d| d.is_ascii_digit()) {
                        nonzero = true;
                        self.decimal_tail()?;
                    }
                    match self.peek() {
                        Some('.') => {
                            self.bump();
                            return self.fraction_rest(line, start);
                        }
                        Some('e') | Some('E') => return self.exponent(line, start),
                        Some('j') | Some('J') => return self.imaginary(line, start),
                        _ => {
                            if nonzero {
                                return Err(());
                            }
                            self.verify_end_of_number("decimal", line)?;
                        }
                    }
                }
            }
        } else {
            self.pos -= 1;
            self.decimal_tail()?;
            match self.peek() {
                Some('.') => {
                    self.bump();
                    return self.fraction_rest(line, start);
                }
                Some('e') | Some('E') => return self.exponent(line, start),
                Some('j') | Some('J') => return self.imaginary(line, start),
                _ => self.verify_end_of_number("decimal", line)?,
            }
        }
        let text: String = self.src[start..self.pos].iter().collect();
        self.push(Kind::Number, text, line);
        Ok(())
    }

    /// A number starting with '.': the '.' is consumed.
    fn number_fraction(&mut self, line: usize, _prefix: String) -> R<()> {
        let start = self.pos - 1;
        self.fraction_rest(line, start)
    }

    /// After the '.' of a float.
    fn fraction_rest(&mut self, line: usize, start: usize) -> R<()> {
        if self.peek().map_or(false, |d| d.is_ascii_digit()) {
            self.decimal_tail()?;
        }
        match self.peek() {
            Some('e') | Some('E') => self.exponent(line, start),
            Some('j') | Some('J') => self.imaginary(line, start),
            _ => {
                self.verify_end_of_number("decimal", line)?;
                let text: String = self.src[start..self.pos].iter().collect();
                self.push(Kind::Number, text, line);
                Ok(())
            }
        }
    }

    /// At 'e' or 'E'.
    fn exponent(&mut self, line: usize, start: usize) -> R<()> {
        let e_pos = self.pos;
        self.bump();
        match self.peek() {
            Some('+') | Some('-') => {
                self.bump();
                if !self.peek().map_or(false, |d| d.is_ascii_digit()) {
                    return Err(());
                }
            }
            Some(d) if d.is_ascii_digit() => {}
            _ => {
                // Not an exponent after all: the 'e' ends the number, and
                // the check runs as though 'e' followed it.
                self.pos = e_pos;
                self.verify_end_of_number("decimal", line)?;
                let text: String = self.src[start..e_pos].iter().collect();
                self.push(Kind::Number, text, line);
                return Ok(());
            }
        }
        self.decimal_tail()?;
        if matches!(self.peek(), Some('j') | Some('J')) {
            return self.imaginary(line, start);
        }
        self.verify_end_of_number("decimal", line)?;
        let text: String = self.src[start..self.pos].iter().collect();
        self.push(Kind::Number, text, line);
        Ok(())
    }

    /// At 'j' or 'J'.
    fn imaginary(&mut self, line: usize, start: usize) -> R<()> {
        self.bump();
        self.verify_end_of_number("imaginary", line)?;
        let text: String = self.src[start..self.pos].iter().collect();
        self.push(Kind::Number, text, line);
        Ok(())
    }

    fn decimal_tail(&mut self) -> R<()> {
        loop {
            while self.peek().map_or(false, |d| d.is_ascii_digit()) {
                self.bump();
            }
            if self.peek() != Some('_') {
                return Ok(());
            }
            self.bump();
            if !self.peek().map_or(false, |d| d.is_ascii_digit()) {
                return Err(());
            }
        }
    }

    /// The characters after the current one spell `s`, and no identifier
    /// character follows.
    fn lookahead(&self, s: &str) -> bool {
        let n = s.chars().count();
        s.chars()
            .enumerate()
            .all(|(i, c)| self.peek_at(1 + i) == Some(c))
            && !self
                .peek_at(1 + n)
                .map_or(false, is_potential_identifier_char)
    }

    /// verify_end_of_number: the character after a number may begin one of
    /// the keywords that can follow a number (a SyntaxWarning), but no other
    /// identifier (an error).
    fn verify_end_of_number(&mut self, kind: &str, line: usize) -> R<()> {
        let Some(c) = self.peek() else { return Ok(()) };
        let r = match c {
            'a' => self.lookahead("nd"),
            'e' => self.lookahead("lse"),
            'f' => self.lookahead("or"),
            'i' => matches!(self.peek_at(1), Some('f') | Some('n') | Some('s')),
            'o' => self.lookahead("r"),
            'n' => self.lookahead("ot"),
            _ => false,
        };
        if r {
            self.warn_tokenizer(line, &format!("invalid {} literal", kind));
            return Ok(());
        }
        if (c as u32) < 128 && is_potential_identifier_char(c) {
            return Err(());
        }
        Ok(())
    }
}

/// Tokenize `src` (which must end with a newline) like CPython 3.12.
pub fn tokenize(src: &[char]) -> Lexed {
    let mut lx = Lexer {
        src,
        pos: 0,
        line: 1,
        atbol: true,
        parens: Vec::new(),
        indstack: vec![0],
        altindstack: vec![0],
        pendin: 0,
        fstrings: Vec::new(),
        tokens: Vec::new(),
        warnings: Vec::new(),
    };
    let error = lx.run().is_err();
    Lexed {
        tokens: lx.tokens,
        warnings: lx.warnings,
        error,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn kinds(s: &str) -> (Vec<Kind>, bool) {
        let chars: Vec<char> = s.chars().collect();
        let l = tokenize(&chars);
        (l.tokens.iter().map(|t| t.kind).collect(), l.error)
    }

    fn warns(s: &str) -> Vec<(usize, String)> {
        let chars: Vec<char> = s.chars().collect();
        tokenize(&chars)
            .warnings
            .into_iter()
            .map(|w| (w.line, w.message))
            .collect()
    }

    #[test]
    fn indentation() {
        use Kind::*;
        let (k, err) = kinds("if x:\n    y\nz\n");
        assert!(!err);
        assert_eq!(
            k,
            [Name, Name, Op, Newline, Indent, Name, Newline, Dedent, Name, Newline, EndMarker]
        );
        assert!(kinds("if x:\n\ty = 1\n        z = 2\n").1, "TabError");
        assert!(kinds("if x:\n    y\n  z\n").1, "unindent does not match");
        assert!(!kinds("x = (\n  1,\n)\n").1);
        assert!(kinds("x = (\n").1);
    }

    #[test]
    fn numbers() {
        assert!(!kinds("x = 0x1f + 0o17 + 0b1 + 1_000 + 1.5e-3 + 2j + .5 + 1.\n").1);
        for bad in [
            "x = 1_\n",
            "x = 0b2\n",
            "x = 08\n",
            "x = 1e\n",
            "x = 0x\n",
            "x = 1__0\n",
            "x = 1andy\n",
        ] {
            assert!(kinds(bad).1, "{}", bad);
        }
        assert!(!kinds("x = 00\n").1);
        assert_eq!(
            warns("x = 1if 1 else 2\n"),
            [(1, "invalid decimal literal".to_string())]
        );
        assert_eq!(
            warns("x = [0x1for x in y]\n"),
            [(1, "invalid hexadecimal literal".to_string())]
        );
        assert_eq!(
            warns("x = 1jif 1 else 2\n"),
            [(1, "invalid imaginary literal".to_string())]
        );
    }

    #[test]
    fn strings_and_warnings() {
        assert_eq!(
            warns("x = \"\"\"a\n\\d\nc\"\"\"\n"),
            [(2, "invalid escape sequence '\\d'".to_string())]
        );
        assert!(warns("x = r\"\\d\"\n").is_empty());
        assert!(kinds("x = 'abc\n").1);
        assert!(!kinds("x = b'a' rb'\\d' u'x'\n").1);
    }

    #[test]
    fn fstrings() {
        use Kind::*;
        let (k, err) = kinds("f\"a{b!r:>{w}}c\"\n");
        assert!(!err);
        assert_eq!(
            k,
            [
                FStart, FMiddle, Op, Name, Op, Name, Op, FMiddle, Op, Name, Op, Op, FMiddle, FEnd,
                Newline, EndMarker
            ]
        );
        assert!(kinds("x = f\"}\"\n").1);
        assert!(!kinds("x = f\"{{}}\"\n").1);
        assert_eq!(
            warns("x = f\"\\{1}\"\n"),
            [(1, "invalid escape sequence '\\{'".to_string())]
        );
        assert_eq!(
            warns("x = f\"\"\"a\n\\d\nb\nc\"\"\"\n"),
            [(5, "invalid escape sequence '\\d'".to_string())]
        );
    }

    #[test]
    fn invalid_characters() {
        assert!(kinds("\u{feff}x = 1\n").1);
        assert!(kinds("x = 1 €\n").1);
        assert!(!kinds("ñame = 1\n").1);
        assert!(
            !kinds("x = $\n").1,
            "'$' is an operator token the parser rejects"
        );
        assert!(kinds("x = \x01\n").1);
    }
}
