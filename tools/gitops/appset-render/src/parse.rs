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

//! Go's text/template/parse lexer and parser (go1.26), ported for one job:
//! deciding whether a template parses, and producing the exact error Go
//! returns when it does not. The structure follows lex.go and parse.go
//! function for function — including the three-token lookahead and which
//! tree's token supplies the line number — because the error text depends
//! on it. The parse tree itself is reduced to what those decisions read.

use std::collections::{HashMap, HashSet};

use crate::gofmt::{self, Arg, ItemArg};
use crate::gostr;
use crate::numbers::{self, NumErr};

// ---------------------------------------------------------------------------
// lexer (lex.go)
// ---------------------------------------------------------------------------

#[derive(Clone, Copy, PartialEq, Eq, Debug, PartialOrd, Ord)]
#[repr(i64)]
pub enum ItemType {
    Error = 0,
    Bool,
    Char,
    CharConstant,
    Comment,
    Complex,
    Assign,
    Declare,
    Eof,
    Field,
    Identifier,
    LeftDelim,
    LeftParen,
    Number,
    Pipe,
    RawString,
    RightDelim,
    RightParen,
    Space,
    String,
    Text,
    Variable,
    Keyword,
    Block,
    Break,
    Continue,
    Dot,
    Define,
    Else,
    End,
    If,
    Nil,
    Range,
    Template,
    With,
}

#[derive(Clone, Debug)]
pub struct Item {
    pub typ: ItemType,
    pub pos: usize,
    pub val: Vec<u8>,
    pub line: i64,
}

impl Item {
    fn zero() -> Item {
        Item {
            typ: ItemType::Error,
            pos: 0,
            val: Vec::new(),
            line: 0,
        }
    }

    /// item.String().
    fn string(&self) -> Vec<u8> {
        match self.typ {
            ItemType::Eof => b"EOF".to_vec(),
            ItemType::Error => self.val.clone(),
            t if t > ItemType::Keyword => {
                let mut s = b"<".to_vec();
                s.extend_from_slice(&self.val);
                s.push(b'>');
                s
            }
            _ if self.val.len() > 10 => {
                // %.10q: the first ten runes, quoted, then "...".
                let mut n = 0;
                let mut i = 0;
                while i < self.val.len() && n < 10 {
                    let (_, w, _) = gostr::decode_rune(&self.val[i..]);
                    i += w;
                    n += 1;
                }
                let mut s = gostr::quote(&self.val[..i]);
                s.extend_from_slice(b"...");
                s
            }
            _ => gostr::quote(&self.val),
        }
    }

    fn arg(&self) -> Arg {
        Arg::Item(ItemArg {
            typ: self.typ as i64,
            pos: self.pos as i64,
            val: self.val.clone(),
            line: self.line,
            text: self.string(),
        })
    }
}

fn keyword(word: &[u8]) -> Option<ItemType> {
    Some(match word {
        b"." => ItemType::Dot,
        b"block" => ItemType::Block,
        b"break" => ItemType::Break,
        b"continue" => ItemType::Continue,
        b"define" => ItemType::Define,
        b"else" => ItemType::Else,
        b"end" => ItemType::End,
        b"if" => ItemType::If,
        b"range" => ItemType::Range,
        b"nil" => ItemType::Nil,
        b"template" => ItemType::Template,
        b"with" => ItemType::With,
        _ => return None,
    })
}

const EOF: i32 = -1;
const LEFT_DELIM: &[u8] = b"{{";
const RIGHT_DELIM: &[u8] = b"}}";
const LEFT_COMMENT: &[u8] = b"/*";
const RIGHT_COMMENT: &[u8] = b"*/";
const TRIM_MARKER_LEN: usize = 2;

#[derive(Clone, Copy)]
enum State {
    Text,
    LeftDelim,
    Comment,
    RightDelim,
    InsideAction,
    Space,
    Identifier,
    Field,
    Variable,
    Char,
    Number,
    Quote,
    RawQuote,
}

pub struct Lexer<'a> {
    input: &'a [u8],
    pos: usize,
    start: usize,
    at_eof: bool,
    paren_depth: i64,
    line: i64,
    start_line: i64,
    item: Item,
    inside_action: bool,
    break_ok: bool,
    continue_ok: bool,
}

fn is_space(r: i32) -> bool {
    r == ' ' as i32 || r == '\t' as i32 || r == '\r' as i32 || r == '\n' as i32
}

fn is_alpha_numeric(r: i32) -> bool {
    if r < 0 {
        return false;
    }
    let c = match char::from_u32(r as u32) {
        Some(c) => c,
        None => return false,
    };
    c == '_' || gostr::is_letter(c) || gostr::is_digit(c)
}

fn has_left_trim_marker(s: &[u8]) -> bool {
    s.len() >= 2 && s[0] == b'-' && is_space(s[1] as i32)
}

fn has_right_trim_marker(s: &[u8]) -> bool {
    s.len() >= 2 && is_space(s[0] as i32) && s[1] == b'-'
}

fn count_newlines(s: &[u8]) -> i64 {
    s.iter().filter(|&&b| b == b'\n').count() as i64
}

fn find(hay: &[u8], needle: &[u8]) -> Option<usize> {
    if needle.is_empty() {
        return Some(0);
    }
    hay.windows(needle.len()).position(|w| w == needle)
}

fn contains_rune(valid: &[u8], r: i32) -> bool {
    r >= 0 && r < 0x80 && valid.contains(&(r as u8))
}

/// fmt's %#U for a rune.
fn sharp_u(r: i32) -> Vec<u8> {
    gofmt::sprintf(b"%#U", &[Arg::Int(r as i64)])
}

impl<'a> Lexer<'a> {
    pub fn new(input: &'a [u8]) -> Lexer<'a> {
        Lexer {
            input,
            pos: 0,
            start: 0,
            at_eof: false,
            paren_depth: 0,
            line: 1,
            start_line: 1,
            item: Item::zero(),
            inside_action: false,
            break_ok: true,
            continue_ok: true,
        }
    }

    fn next(&mut self) -> i32 {
        if self.pos >= self.input.len() {
            self.at_eof = true;
            return EOF;
        }
        let (r, w, _) = gostr::decode_rune(&self.input[self.pos..]);
        self.pos += w;
        if r == '\n' {
            self.line += 1;
        }
        r as i32
    }

    fn peek(&mut self) -> i32 {
        let r = self.next();
        self.backup();
        r
    }

    fn backup(&mut self) {
        if !self.at_eof && self.pos > 0 {
            let (r, w) = gostr::decode_last_rune(&self.input[..self.pos]);
            self.pos -= w;
            if r == '\n' {
                self.line -= 1;
            }
        }
    }

    fn this_item(&mut self, t: ItemType) -> Item {
        let i = Item {
            typ: t,
            pos: self.start,
            val: self.input[self.start..self.pos].to_vec(),
            line: self.start_line,
        };
        self.start = self.pos;
        self.start_line = self.line;
        i
    }

    fn emit(&mut self, t: ItemType) -> Option<State> {
        let i = self.this_item(t);
        self.emit_item(i)
    }

    fn emit_item(&mut self, i: Item) -> Option<State> {
        self.item = i;
        None
    }

    fn ignore(&mut self) {
        self.line += count_newlines(&self.input[self.start..self.pos]);
        self.start = self.pos;
        self.start_line = self.line;
    }

    fn accept(&mut self, valid: &[u8]) -> bool {
        let r = self.next();
        if contains_rune(valid, r) {
            return true;
        }
        self.backup();
        false
    }

    fn accept_run(&mut self, valid: &[u8]) {
        loop {
            let r = self.next();
            if !contains_rune(valid, r) {
                break;
            }
        }
        self.backup();
    }

    fn errorf(&mut self, msg: Vec<u8>) -> Option<State> {
        self.item = Item {
            typ: ItemType::Error,
            pos: self.start,
            val: msg,
            line: self.start_line,
        };
        self.start = 0;
        self.pos = 0;
        self.input = &self.input[..0];
        None
    }

    pub fn next_item(&mut self) -> Item {
        self.item = Item {
            typ: ItemType::Eof,
            pos: self.pos,
            val: b"EOF".to_vec(),
            line: self.start_line,
        };
        let mut state = if self.inside_action {
            State::InsideAction
        } else {
            State::Text
        };
        loop {
            let next = match state {
                State::Text => self.lex_text(),
                State::LeftDelim => self.lex_left_delim(),
                State::Comment => self.lex_comment(),
                State::RightDelim => self.lex_right_delim(),
                State::InsideAction => self.lex_inside_action(),
                State::Space => self.lex_space(),
                State::Identifier => self.lex_identifier(),
                State::Field => self.lex_field_or_variable(ItemType::Field),
                State::Variable => self.lex_variable(),
                State::Char => self.lex_quoted(
                    b'\'',
                    b"unterminated character constant",
                    ItemType::CharConstant,
                ),
                State::Number => self.lex_number(),
                State::Quote => {
                    self.lex_quoted(b'"', b"unterminated quoted string", ItemType::String)
                }
                State::RawQuote => self.lex_raw_quote(),
            };
            match next {
                Some(s) => state = s,
                None => return std::mem::replace(&mut self.item, Item::zero()),
            }
        }
    }

    fn lex_text(&mut self) -> Option<State> {
        if let Some(x) = find(&self.input[self.pos..], LEFT_DELIM) {
            if x > 0 {
                self.pos += x;
                let mut trim_length = 0;
                let delim_end = self.pos + LEFT_DELIM.len();
                if has_left_trim_marker(&self.input[delim_end..]) {
                    trim_length = right_trim_length(&self.input[self.start..self.pos]);
                }
                self.pos -= trim_length;
                self.line += count_newlines(&self.input[self.start..self.pos]);
                let i = self.this_item(ItemType::Text);
                self.pos += trim_length;
                self.ignore();
                if !i.val.is_empty() {
                    return self.emit_item(i);
                }
            }
            return Some(State::LeftDelim);
        }
        self.pos = self.input.len();
        if self.pos > self.start {
            self.line += count_newlines(&self.input[self.start..self.pos]);
            return self.emit(ItemType::Text);
        }
        self.emit(ItemType::Eof)
    }

    fn at_right_delim(&self) -> (bool, bool) {
        let rest = &self.input[self.pos..];
        if has_right_trim_marker(rest) && rest[TRIM_MARKER_LEN..].starts_with(RIGHT_DELIM) {
            return (true, true);
        }
        if rest.starts_with(RIGHT_DELIM) {
            return (true, false);
        }
        (false, false)
    }

    fn lex_left_delim(&mut self) -> Option<State> {
        self.pos += LEFT_DELIM.len();
        let trim_space = has_left_trim_marker(&self.input[self.pos..]);
        let after_marker = if trim_space { TRIM_MARKER_LEN } else { 0 };
        if self.input[self.pos + after_marker..].starts_with(LEFT_COMMENT) {
            self.pos += after_marker;
            self.ignore();
            return Some(State::Comment);
        }
        let i = self.this_item(ItemType::LeftDelim);
        self.inside_action = true;
        self.pos += after_marker;
        self.ignore();
        self.paren_depth = 0;
        self.emit_item(i)
    }

    fn lex_comment(&mut self) -> Option<State> {
        self.pos += LEFT_COMMENT.len();
        let x = match find(&self.input[self.pos..], RIGHT_COMMENT) {
            Some(x) => x,
            None => return self.errorf(b"unclosed comment".to_vec()),
        };
        self.pos += x + RIGHT_COMMENT.len();
        let (delim, trim_space) = self.at_right_delim();
        if !delim {
            return self.errorf(b"comment ends before closing delimiter".to_vec());
        }
        self.line += count_newlines(&self.input[self.start..self.pos]);
        let _comment = self.this_item(ItemType::Comment);
        if trim_space {
            self.pos += TRIM_MARKER_LEN;
        }
        self.pos += RIGHT_DELIM.len();
        if trim_space {
            self.pos += left_trim_length(&self.input[self.pos..]);
        }
        self.ignore();
        // emitComment is off (no ParseComments mode).
        Some(State::Text)
    }

    fn lex_right_delim(&mut self) -> Option<State> {
        let (_, trim_space) = self.at_right_delim();
        if trim_space {
            self.pos += TRIM_MARKER_LEN;
            self.ignore();
        }
        self.pos += RIGHT_DELIM.len();
        let i = self.this_item(ItemType::RightDelim);
        if trim_space {
            self.pos += left_trim_length(&self.input[self.pos..]);
            self.ignore();
        }
        self.inside_action = false;
        self.emit_item(i)
    }

    fn lex_inside_action(&mut self) -> Option<State> {
        let (delim, _) = self.at_right_delim();
        if delim {
            if self.paren_depth == 0 {
                return Some(State::RightDelim);
            }
            return self.errorf(b"unclosed left paren".to_vec());
        }
        let r = self.next();
        if r == EOF {
            return self.errorf(b"unclosed action".to_vec());
        }
        if is_space(r) {
            self.backup();
            return Some(State::Space);
        }
        match r {
            0x3D => return self.emit(ItemType::Assign), // '='
            0x3A => {
                // ':'
                if self.next() != '=' as i32 {
                    return self.errorf(b"expected :=".to_vec());
                }
                return self.emit(ItemType::Declare);
            }
            0x7C => return self.emit(ItemType::Pipe), // '|'
            0x22 => return Some(State::Quote),        // '"'
            0x60 => return Some(State::RawQuote),     // '`'
            0x24 => return Some(State::Variable),     // '$'
            0x27 => return Some(State::Char),         // '\''
            _ => {}
        }
        if r == '.' as i32 {
            if self.pos < self.input.len() {
                let c = self.input[self.pos];
                if !c.is_ascii_digit() {
                    return Some(State::Field);
                }
            }
            self.backup();
            return Some(State::Number);
        }
        if r == '+' as i32 || r == '-' as i32 || ('0' as i32..='9' as i32).contains(&r) {
            self.backup();
            return Some(State::Number);
        }
        if is_alpha_numeric(r) {
            self.backup();
            return Some(State::Identifier);
        }
        if r == '(' as i32 {
            self.paren_depth += 1;
            return self.emit(ItemType::LeftParen);
        }
        if r == ')' as i32 {
            self.paren_depth -= 1;
            if self.paren_depth < 0 {
                return self.errorf(b"unexpected right paren".to_vec());
            }
            return self.emit(ItemType::RightParen);
        }
        if (0x20..=0x7E).contains(&r) {
            return self.emit(ItemType::Char);
        }
        let mut msg = b"unrecognized character in action: ".to_vec();
        msg.extend(sharp_u(r));
        self.errorf(msg)
    }

    fn lex_space(&mut self) -> Option<State> {
        let mut num_spaces = 0;
        loop {
            let r = self.peek();
            if !is_space(r) {
                break;
            }
            self.next();
            num_spaces += 1;
        }
        let rest = &self.input[self.pos - 1..];
        if has_right_trim_marker(rest) && rest[TRIM_MARKER_LEN..].starts_with(RIGHT_DELIM) {
            self.backup();
            if num_spaces == 1 {
                return Some(State::RightDelim);
            }
        }
        self.emit(ItemType::Space)
    }

    fn lex_identifier(&mut self) -> Option<State> {
        loop {
            let r = self.next();
            if is_alpha_numeric(r) {
                continue;
            }
            self.backup();
            let word = self.input[self.start..self.pos].to_vec();
            if !self.at_terminator() {
                let mut msg = b"bad character ".to_vec();
                msg.extend(sharp_u(r));
                return self.errorf(msg);
            }
            if let Some(k) = keyword(&word) {
                if k > ItemType::Keyword {
                    if (k == ItemType::Break && !self.break_ok)
                        || (k == ItemType::Continue && !self.continue_ok)
                    {
                        return self.emit(ItemType::Identifier);
                    }
                    return self.emit(k);
                }
            }
            if word.first() == Some(&b'.') {
                return self.emit(ItemType::Field);
            }
            if word == b"true" || word == b"false" {
                return self.emit(ItemType::Bool);
            }
            return self.emit(ItemType::Identifier);
        }
    }

    fn lex_variable(&mut self) -> Option<State> {
        if self.at_terminator() {
            return self.emit(ItemType::Variable);
        }
        self.lex_field_or_variable(ItemType::Variable)
    }

    fn lex_field_or_variable(&mut self, typ: ItemType) -> Option<State> {
        if self.at_terminator() {
            if typ == ItemType::Variable {
                return self.emit(ItemType::Variable);
            }
            return self.emit(ItemType::Dot);
        }
        let mut r;
        loop {
            r = self.next();
            if !is_alpha_numeric(r) {
                self.backup();
                break;
            }
        }
        if !self.at_terminator() {
            let mut msg = b"bad character ".to_vec();
            msg.extend(sharp_u(r));
            return self.errorf(msg);
        }
        self.emit(typ)
    }

    fn at_terminator(&mut self) -> bool {
        let r = self.peek();
        if is_space(r) {
            return true;
        }
        if r == EOF
            || [b'.', b',', b'|', b':', b')', b'(']
                .iter()
                .any(|&c| r == c as i32)
        {
            return true;
        }
        self.input[self.pos..].starts_with(RIGHT_DELIM)
    }

    /// lexChar and lexQuote.
    fn lex_quoted(&mut self, quote: u8, unterminated: &[u8], typ: ItemType) -> Option<State> {
        loop {
            let r = self.next();
            if r == '\\' as i32 {
                let r2 = self.next();
                if r2 != EOF && r2 != '\n' as i32 {
                    continue;
                }
                return self.errorf(unterminated.to_vec());
            }
            if r == EOF || r == '\n' as i32 {
                return self.errorf(unterminated.to_vec());
            }
            if r == quote as i32 {
                break;
            }
        }
        self.emit(typ)
    }

    fn lex_raw_quote(&mut self) -> Option<State> {
        loop {
            let r = self.next();
            if r == EOF {
                return self.errorf(b"unterminated raw quoted string".to_vec());
            }
            if r == '`' as i32 {
                break;
            }
        }
        self.emit(ItemType::RawString)
    }

    fn lex_number(&mut self) -> Option<State> {
        if !self.scan_number() {
            let mut msg = b"bad number syntax: ".to_vec();
            msg.extend(gostr::quote(&self.input[self.start..self.pos]));
            return self.errorf(msg);
        }
        let sign = self.peek();
        if sign == '+' as i32 || sign == '-' as i32 {
            if !self.scan_number() || self.input[self.pos - 1] != b'i' {
                let mut msg = b"bad number syntax: ".to_vec();
                msg.extend(gostr::quote(&self.input[self.start..self.pos]));
                return self.errorf(msg);
            }
            return self.emit(ItemType::Complex);
        }
        self.emit(ItemType::Number)
    }

    fn scan_number(&mut self) -> bool {
        self.accept(b"+-");
        let mut digits: &[u8] = b"0123456789_";
        if self.accept(b"0") {
            if self.accept(b"xX") {
                digits = b"0123456789abcdefABCDEF_";
            } else if self.accept(b"oO") {
                digits = b"01234567_";
            } else if self.accept(b"bB") {
                digits = b"01_";
            }
        }
        self.accept_run(digits);
        if self.accept(b".") {
            self.accept_run(digits);
        }
        if digits.len() == 10 + 1 && self.accept(b"eE") {
            self.accept(b"+-");
            self.accept_run(b"0123456789_");
        }
        if digits.len() == 16 + 6 + 1 && self.accept(b"pP") {
            self.accept(b"+-");
            self.accept_run(b"0123456789_");
        }
        self.accept(b"i");
        let p = self.peek();
        if is_alpha_numeric(p) {
            self.next();
            return false;
        }
        true
    }
}

/// len(s) - len(strings.TrimRight(s, " \t\r\n")).
fn right_trim_length(s: &[u8]) -> usize {
    s.iter().rev().take_while(|&&b| is_space(b as i32)).count()
}

fn left_trim_length(s: &[u8]) -> usize {
    s.iter().take_while(|&&b| is_space(b as i32)).count()
}

// ---------------------------------------------------------------------------
// parser (parse.go, node.go)
// ---------------------------------------------------------------------------

/// The result of an error: the text of the error text/template returns.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ParseError(pub Vec<u8>);

type PResult<T> = Result<T, ParseError>;

/// What textOrAction / itemList hand back, reduced to what is read later.
#[derive(Debug, Clone)]
enum Node {
    Text(Vec<u8>),
    Comment,
    Action,
    If,
    Range,
    With,
    Template,
    Break,
    Continue,
    End { pos: usize },
    Else { pos: usize, line: i64 },
}

impl Node {
    fn arg(&self) -> Arg {
        match self {
            Node::End { pos } => Arg::Node {
                ty: "*parse.endNode",
                typ: 7,
                pos: *pos as i64,
                line: None,
                text: b"{{end}}".to_vec(),
            },
            Node::Else { pos, line } => Arg::Node {
                ty: "*parse.elseNode",
                typ: 6,
                pos: *pos as i64,
                line: Some(*line),
                text: b"{{else}}".to_vec(),
            },
            _ => unreachable!("only end and else nodes are printed"),
        }
    }

    fn is_end(&self) -> bool {
        matches!(self, Node::End { .. })
    }

    fn is_end_or_else(&self) -> bool {
        matches!(self, Node::End { .. } | Node::Else { .. })
    }
}

/// An operand, reduced to its kind (and String() where an error prints it).
#[derive(Debug, Clone)]
enum Term {
    Identifier,
    Dot,
    Nil,
    Variable,
    Field,
    Bool(bool),
    Number(Vec<u8>),
    Str(Vec<u8>),
    Pipe,
    Chain,
}

impl Term {
    fn is_constant(&self) -> bool {
        matches!(
            self,
            Term::Bool(_) | Term::Dot | Term::Nil | Term::Number(_) | Term::Str(_)
        )
    }

    fn string(&self) -> Vec<u8> {
        match self {
            Term::Bool(true) => b"true".to_vec(),
            Term::Bool(false) => b"false".to_vec(),
            Term::Dot => b".".to_vec(),
            Term::Nil => b"nil".to_vec(),
            Term::Number(t) | Term::Str(t) => t.clone(),
            _ => Vec::new(),
        }
    }
}

const MAX_STACK_DEPTH: i64 = 10000;

/// The ArgoCD function names (sprig + toYaml/fromYaml/lookup) and
/// text/template's builtins: what hasFunction resolves.
pub struct Funcs(HashSet<Vec<u8>>);

impl Funcs {
    pub fn new(parse_funcs: &[&str]) -> Funcs {
        let builtins = [
            "and", "call", "html", "index", "slice", "js", "len", "not", "or", "print", "printf",
            "println", "urlquery", "eq", "ge", "gt", "le", "lt", "ne",
        ];
        Funcs(
            parse_funcs
                .iter()
                .chain(builtins.iter())
                .map(|s| s.as_bytes().to_vec())
                .collect(),
        )
    }

    fn has(&self, name: &[u8]) -> bool {
        self.0.contains(name)
    }
}

struct Ctx<'l, 'a> {
    lex: &'l mut Lexer<'a>,
    tree_set: HashMap<Vec<u8>, bool>,
    funcs: &'l Funcs,
}

struct Tree {
    name: Vec<u8>,
    parse_name: Vec<u8>,
    token: [Item; 3],
    peek_count: usize,
    vars: Vec<Vec<u8>>,
    action_line: i64,
    range_depth: i64,
    stack_depth: i64,
}

fn is_empty_tree(nodes: &[Node]) -> bool {
    nodes.iter().all(|n| match n {
        Node::Text(t) => gostr::trim_space(t).is_empty(),
        Node::Comment => true,
        _ => false,
    })
}

fn err_syntax() -> Arg {
    Arg::ErrString(b"invalid syntax".to_vec())
}

impl Tree {
    fn new(name: Vec<u8>, parse_name: Vec<u8>) -> Tree {
        Tree {
            name,
            parse_name,
            token: [Item::zero(), Item::zero(), Item::zero()],
            peek_count: 0,
            vars: vec![b"$".to_vec()],
            action_line: 0,
            range_depth: 0,
            stack_depth: 0,
        }
    }

    fn next(&mut self, cx: &mut Ctx) -> Item {
        if self.peek_count > 0 {
            self.peek_count -= 1;
        } else {
            self.token[0] = cx.lex.next_item();
        }
        self.token[self.peek_count].clone()
    }

    fn backup(&mut self) {
        self.peek_count += 1;
    }

    fn backup2(&mut self, t1: Item) {
        self.token[1] = t1;
        self.peek_count = 2;
    }

    fn backup3(&mut self, t2: Item, t1: Item) {
        self.token[1] = t1;
        self.token[2] = t2;
        self.peek_count = 3;
    }

    fn peek(&mut self, cx: &mut Ctx) -> Item {
        if self.peek_count > 0 {
            return self.token[self.peek_count - 1].clone();
        }
        self.peek_count = 1;
        self.token[0] = cx.lex.next_item();
        self.token[0].clone()
    }

    fn next_non_space(&mut self, cx: &mut Ctx) -> Item {
        loop {
            let t = self.next(cx);
            if t.typ != ItemType::Space {
                return t;
            }
        }
    }

    fn peek_non_space(&mut self, cx: &mut Ctx) -> Item {
        let t = self.next_non_space(cx);
        self.backup();
        t
    }

    /// t.errorf: "template: <ParseName>:<line>: <format>", then Errorf.
    fn errorf(&self, format: &[u8], args: &[Arg]) -> ParseError {
        let mut f = b"template: ".to_vec();
        f.extend_from_slice(&self.parse_name);
        f.push(b':');
        f.extend_from_slice(self.token[0].line.to_string().as_bytes());
        f.extend_from_slice(b": ");
        f.extend_from_slice(format);
        ParseError(gofmt::errorf(&f, args))
    }

    fn error(&self, err: Arg) -> ParseError {
        self.errorf(b"%s", &[err])
    }

    fn expect(&mut self, cx: &mut Ctx, expected: ItemType, context: &[u8]) -> PResult<Item> {
        let token = self.next_non_space(cx);
        if token.typ != expected {
            return Err(self.unexpected(&token, context));
        }
        Ok(token)
    }

    fn expect_one_of(
        &mut self,
        cx: &mut Ctx,
        e1: ItemType,
        e2: ItemType,
        context: &[u8],
    ) -> PResult<Item> {
        let token = self.next_non_space(cx);
        if token.typ != e1 && token.typ != e2 {
            return Err(self.unexpected(&token, context));
        }
        Ok(token)
    }

    fn unexpected(&self, token: &Item, context: &[u8]) -> ParseError {
        if token.typ == ItemType::Error {
            let mut extra: Vec<u8> = Vec::new();
            if self.action_line != 0 && self.action_line != token.line {
                extra = b" in action started at ".to_vec();
                extra.extend_from_slice(&self.parse_name);
                extra.push(b':');
                extra.extend_from_slice(self.action_line.to_string().as_bytes());
                if token.val.ends_with(b" action") {
                    extra = extra[b" in action".len()..].to_vec();
                }
            }
            return self.errorf(b"%s%s", &[token.arg(), Arg::Str(extra)]);
        }
        self.errorf(
            b"unexpected %s in %s",
            &[token.arg(), Arg::Str(context.to_vec())],
        )
    }

    /// Tree.add: install this tree, unless a non-empty one has the name.
    fn add(&self, cx: &mut Ctx, root: &[Node]) -> PResult<()> {
        let empty = is_empty_tree(root);
        match cx.tree_set.get(&self.name) {
            None => {
                cx.tree_set.insert(self.name.clone(), empty);
                Ok(())
            }
            Some(&stored_empty) if stored_empty => {
                cx.tree_set.insert(self.name.clone(), empty);
                Ok(())
            }
            Some(_) => {
                if !empty {
                    return Err(self.errorf(
                        b"template: multiple definition of template %q",
                        &[Arg::Str(self.name.clone())],
                    ));
                }
                Ok(())
            }
        }
    }

    fn parse(&mut self, cx: &mut Ctx) -> PResult<Vec<Node>> {
        let mut root: Vec<Node> = Vec::new();
        self.peek(cx);
        while self.peek(cx).typ != ItemType::Eof {
            if self.peek(cx).typ == ItemType::LeftDelim {
                let delim = self.next(cx);
                if self.next_non_space(cx).typ == ItemType::Define {
                    let mut new_t = Tree::new(b"definition".to_vec(), self.parse_name.clone());
                    new_t.parse_definition(cx)?;
                    continue;
                }
                self.backup2(delim);
            }
            let n = self.text_or_action(cx)?;
            if n.is_end_or_else() {
                return Err(self.errorf(b"unexpected %s", &[n.arg()]));
            }
            root.push(n);
        }
        Ok(root)
    }

    fn parse_definition(&mut self, cx: &mut Ctx) -> PResult<()> {
        let context: &[u8] = b"define clause";
        let name = self.expect_one_of(cx, ItemType::String, ItemType::RawString, context)?;
        self.name = gostr::unquote(&name.val).map_err(|_| self.error(err_syntax()))?;
        self.expect(cx, ItemType::RightDelim, context)?;
        let (root, end) = self.item_list(cx)?;
        if !end.is_end() {
            return Err(self.errorf(
                b"unexpected %s in %s",
                &[end.arg(), Arg::Str(context.to_vec())],
            ));
        }
        self.add(cx, &root)
    }

    fn item_list(&mut self, cx: &mut Ctx) -> PResult<(Vec<Node>, Node)> {
        let mut list = Vec::new();
        self.peek_non_space(cx);
        while self.peek_non_space(cx).typ != ItemType::Eof {
            let n = self.text_or_action(cx)?;
            if n.is_end_or_else() {
                return Ok((list, n));
            }
            list.push(n);
        }
        Err(self.errorf(b"unexpected EOF", &[]))
    }

    fn text_or_action(&mut self, cx: &mut Ctx) -> PResult<Node> {
        let token = self.next_non_space(cx);
        match token.typ {
            ItemType::Text => Ok(Node::Text(token.val)),
            ItemType::LeftDelim => {
                self.action_line = token.line;
                let r = self.action(cx);
                self.action_line = 0;
                r
            }
            ItemType::Comment => Ok(Node::Comment),
            _ => Err(self.unexpected(&token, b"input")),
        }
    }

    fn action(&mut self, cx: &mut Ctx) -> PResult<Node> {
        let token = self.next_non_space(cx);
        match token.typ {
            ItemType::Block => return self.block_control(cx),
            ItemType::Break => return self.break_control(cx, b"{{break}}", Node::Break),
            ItemType::Continue => return self.break_control(cx, b"{{continue}}", Node::Continue),
            ItemType::Else => return self.else_control(cx),
            ItemType::End => return self.end_control(cx),
            ItemType::If => return self.parse_control(cx, b"if").map(|_| Node::If),
            ItemType::Range => return self.parse_control(cx, b"range").map(|_| Node::Range),
            ItemType::Template => return self.template_control(cx),
            ItemType::With => return self.parse_control(cx, b"with").map(|_| Node::With),
            _ => {}
        }
        self.backup();
        self.peek(cx);
        self.pipeline(cx, b"command", ItemType::RightDelim)?;
        Ok(Node::Action)
    }

    /// breakControl and continueControl.
    fn break_control(&mut self, cx: &mut Ctx, what: &[u8], node: Node) -> PResult<Node> {
        let token = self.next_non_space(cx);
        if token.typ != ItemType::RightDelim {
            return Err(self.unexpected(&token, what));
        }
        if self.range_depth == 0 {
            let mut f = what.to_vec();
            f.extend_from_slice(b" outside {{range}}");
            return Err(self.errorf(&f, &[]));
        }
        Ok(node)
    }

    fn pipeline(&mut self, cx: &mut Ctx, context: &[u8], end: ItemType) -> PResult<Vec<Term>> {
        self.peek_non_space(cx);
        let mut decl = 0usize;
        loop {
            let v = self.peek_non_space(cx);
            if v.typ != ItemType::Variable {
                break;
            }
            self.next(cx);
            let token_after_variable = self.peek(cx);
            let next = self.peek_non_space(cx);
            if next.typ == ItemType::Assign || next.typ == ItemType::Declare {
                self.next_non_space(cx);
                self.vars.push(v.val.clone());
                break;
            } else if next.typ == ItemType::Char && next.val == b"," {
                self.next_non_space(cx);
                decl += 1;
                self.vars.push(v.val.clone());
                if context == b"range" && decl < 2 {
                    match self.peek_non_space(cx).typ {
                        ItemType::Variable | ItemType::RightDelim | ItemType::RightParen => {
                            continue
                        }
                        _ => return Err(self.errorf(b"range can only initialize variables", &[])),
                    }
                }
                return Err(self.errorf(
                    b"too many declarations in %s",
                    &[Arg::Str(context.to_vec())],
                ));
            } else if token_after_variable.typ == ItemType::Space {
                self.backup3(v, token_after_variable);
            } else {
                self.backup2(v);
            }
            break;
        }
        // The first argument of each command, which checkPipeline reads.
        let mut cmds: Vec<Term> = Vec::new();
        loop {
            let token = self.next_non_space(cx);
            if token.typ == end {
                self.check_pipeline(&cmds, context)?;
                return Ok(cmds);
            }
            match token.typ {
                ItemType::Bool
                | ItemType::CharConstant
                | ItemType::Complex
                | ItemType::Dot
                | ItemType::Field
                | ItemType::Identifier
                | ItemType::Number
                | ItemType::Nil
                | ItemType::RawString
                | ItemType::String
                | ItemType::Variable
                | ItemType::LeftParen => {
                    self.backup();
                    let first = self.command(cx)?;
                    cmds.push(first);
                }
                _ => return Err(self.unexpected(&token, context)),
            }
        }
    }

    fn check_pipeline(&self, cmds: &[Term], context: &[u8]) -> PResult<()> {
        if cmds.is_empty() {
            return Err(self.errorf(b"missing value for %s", &[Arg::Str(context.to_vec())]));
        }
        for (i, c) in cmds[1..].iter().enumerate() {
            if c.is_constant() {
                return Err(self.errorf(
                    b"non executable command in pipeline stage %d",
                    &[Arg::Int(i as i64 + 2)],
                ));
            }
        }
        Ok(())
    }

    fn parse_control(&mut self, cx: &mut Ctx, context: &[u8]) -> PResult<()> {
        let saved = self.vars.len();
        let r = self.parse_control_inner(cx, context);
        self.vars.truncate(saved);
        r
    }

    fn parse_control_inner(&mut self, cx: &mut Ctx, context: &[u8]) -> PResult<()> {
        self.pipeline(cx, context, ItemType::RightDelim)?;
        if context == b"range" {
            self.range_depth += 1;
        }
        let (_list, next) = self.item_list(cx)?;
        if context == b"range" {
            self.range_depth -= 1;
        }
        if let Node::Else { .. } = next {
            if context == b"if" && self.peek(cx).typ == ItemType::If {
                self.next(cx);
                self.parse_control(cx, b"if")?;
            } else if context == b"with" && self.peek(cx).typ == ItemType::With {
                self.next(cx);
                self.parse_control(cx, b"with")?;
            } else {
                let (_else_list, next) = self.item_list(cx)?;
                if !next.is_end() {
                    return Err(self.errorf(b"expected end; found %s", &[next.arg()]));
                }
            }
        }
        Ok(())
    }

    fn end_control(&mut self, cx: &mut Ctx) -> PResult<Node> {
        let t = self.expect(cx, ItemType::RightDelim, b"end")?;
        Ok(Node::End { pos: t.pos })
    }

    fn else_control(&mut self, cx: &mut Ctx) -> PResult<Node> {
        let peek = self.peek_non_space(cx);
        if peek.typ == ItemType::If || peek.typ == ItemType::With {
            return Ok(Node::Else {
                pos: peek.pos,
                line: peek.line,
            });
        }
        let token = self.expect(cx, ItemType::RightDelim, b"else")?;
        Ok(Node::Else {
            pos: token.pos,
            line: token.line,
        })
    }

    fn block_control(&mut self, cx: &mut Ctx) -> PResult<Node> {
        let context: &[u8] = b"block clause";
        let token = self.next_non_space(cx);
        let name = self.parse_template_name(&token, context)?;
        self.pipeline(cx, context, ItemType::RightDelim)?;
        let mut block = Tree::new(name, self.parse_name.clone());
        let (root, end) = block.item_list(cx)?;
        if !end.is_end() {
            return Err(self.errorf(
                b"unexpected %s in %s",
                &[end.arg(), Arg::Str(context.to_vec())],
            ));
        }
        block.add(cx, &root)?;
        Ok(Node::Template)
    }

    fn template_control(&mut self, cx: &mut Ctx) -> PResult<Node> {
        let context: &[u8] = b"template clause";
        let token = self.next_non_space(cx);
        self.parse_template_name(&token, context)?;
        if self.next_non_space(cx).typ != ItemType::RightDelim {
            self.backup();
            self.pipeline(cx, context, ItemType::RightDelim)?;
        }
        Ok(Node::Template)
    }

    fn parse_template_name(&self, token: &Item, context: &[u8]) -> PResult<Vec<u8>> {
        match token.typ {
            ItemType::String | ItemType::RawString => {
                gostr::unquote(&token.val).map_err(|_| self.error(err_syntax()))
            }
            _ => Err(self.unexpected(token, context)),
        }
    }

    /// command(): returns the command's first argument.
    fn command(&mut self, cx: &mut Ctx) -> PResult<Term> {
        self.peek_non_space(cx);
        let mut first: Option<Term> = None;
        loop {
            self.peek_non_space(cx);
            if let Some(op) = self.operand(cx)? {
                if first.is_none() {
                    first = Some(op);
                }
            }
            let token = self.next(cx);
            match token.typ {
                ItemType::Space => continue,
                ItemType::RightDelim | ItemType::RightParen => self.backup(),
                ItemType::Pipe => {}
                _ => return Err(self.unexpected(&token, b"operand")),
            }
            break;
        }
        match first {
            Some(t) => Ok(t),
            None => Err(self.errorf(b"empty command", &[])),
        }
    }

    fn operand(&mut self, cx: &mut Ctx) -> PResult<Option<Term>> {
        let node = match self.term(cx)? {
            Some(n) => n,
            None => return Ok(None),
        };
        if self.peek(cx).typ == ItemType::Field {
            while self.peek(cx).typ == ItemType::Field {
                self.next(cx);
            }
            return match node {
                Term::Field => Ok(Some(Term::Field)),
                Term::Variable => Ok(Some(Term::Variable)),
                ref n if n.is_constant() => {
                    Err(self.errorf(b"unexpected . after term %q", &[Arg::Str(n.string())]))
                }
                _ => Ok(Some(Term::Chain)),
            };
        }
        Ok(Some(node))
    }

    fn term(&mut self, cx: &mut Ctx) -> PResult<Option<Term>> {
        let token = self.next_non_space(cx);
        match token.typ {
            ItemType::Identifier => {
                if !cx.funcs.has(&token.val) {
                    return Err(
                        self.errorf(b"function %q not defined", &[Arg::Str(token.val.clone())])
                    );
                }
                Ok(Some(Term::Identifier))
            }
            ItemType::Dot => Ok(Some(Term::Dot)),
            ItemType::Nil => Ok(Some(Term::Nil)),
            ItemType::Variable => {
                let ident0 = token
                    .val
                    .split(|&b| b == b'.')
                    .next()
                    .unwrap_or(&[])
                    .to_vec();
                if self.vars.iter().any(|v| *v == ident0) {
                    return Ok(Some(Term::Variable));
                }
                Err(self.errorf(b"undefined variable %q", &[Arg::Str(ident0)]))
            }
            ItemType::Field => Ok(Some(Term::Field)),
            ItemType::Bool => Ok(Some(Term::Bool(token.val == b"true"))),
            ItemType::CharConstant | ItemType::Complex | ItemType::Number => {
                new_number(&token.val, token.typ).map_err(|e| self.error(e))?;
                Ok(Some(Term::Number(token.val)))
            }
            ItemType::LeftParen => {
                if self.stack_depth >= MAX_STACK_DEPTH {
                    return Err(self.errorf(b"max expression depth exceeded", &[]));
                }
                self.stack_depth += 1;
                let r = self.pipeline(cx, b"parenthesized pipeline", ItemType::RightParen);
                self.stack_depth -= 1;
                r?;
                Ok(Some(Term::Pipe))
            }
            ItemType::String | ItemType::RawString => {
                gostr::unquote(&token.val).map_err(|_| self.error(err_syntax()))?;
                Ok(Some(Term::Str(token.val)))
            }
            _ => {
                self.backup();
                Ok(None)
            }
        }
    }
}

/// newNumber: Ok if text/template accepts the constant, else the error.
fn new_number(text: &[u8], typ: ItemType) -> Result<(), Arg> {
    match typ {
        ItemType::CharConstant => {
            let (_, _, tail) =
                gostr::unquote_char(&text[1..], text[0]).map_err(|_| err_syntax())?;
            if tail != b"'" {
                let mut m = b"malformed character constant: ".to_vec();
                m.extend_from_slice(text);
                return Err(Arg::ErrString(m));
            }
            return Ok(());
        }
        ItemType::Complex => {
            numbers::sscan_complex(text)?;
            return Ok(());
        }
        _ => {}
    }
    if text.last() == Some(&b'i') && numbers::parse_float(&text[..text.len() - 1]).is_ok() {
        return Ok(());
    }
    let is_uint = numbers::parse_uint(text).is_ok();
    let is_int = numbers::parse_int(text).is_ok();
    if is_int || is_uint {
        return Ok(());
    }
    match numbers::parse_float(text) {
        Ok(_) => {
            if !text.iter().any(|c| b".eEpP".contains(c)) {
                let mut m = b"integer overflow: ".to_vec();
                m.extend(gostr::quote(text));
                return Err(Arg::ErrString(m));
            }
            Ok(())
        }
        Err(NumErr::Syntax) | Err(NumErr::Range) => {
            let mut m = b"illegal number syntax: ".to_vec();
            m.extend(gostr::quote(text));
            Err(Arg::ErrString(m))
        }
    }
}

/// template.New(name).Funcs(funcs).Option("missingkey=zero").Parse(src):
/// Ok, or the error text Go's Parse returns.
pub fn check_source(name: &[u8], src: &[u8], funcs: &Funcs) -> Result<(), ParseError> {
    let mut lex = Lexer::new(src);
    let mut cx = Ctx {
        lex: &mut lex,
        tree_set: HashMap::new(),
        funcs,
    };
    let mut t = Tree::new(name.to_vec(), name.to_vec());
    let root = t.parse(&mut cx)?;
    t.add(&mut cx, &root)
}
