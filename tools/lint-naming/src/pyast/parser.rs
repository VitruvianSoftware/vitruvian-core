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

//! A recursive-descent parser for Python 3.12's grammar (Grammar/python.gram),
//! building just enough of the `ast` tree to walk it as `ast.walk` does: each
//! node's children in the order of its `_fields`. Nodes that can never hold a
//! call (operators, contexts, `alias`, bare constants) are left out; they do
//! not change the order in which a breadth-first walk meets the calls.
//!
//! `match` statements are parsed for their syntax only: patterns cannot hold
//! a call, so they are checked but not kept.

use super::lexer::{Kind, Token};
use super::strings::LiteralValue;

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum K {
    Name(String),
    Attribute(String),
    Subscript,
    Starred,
    Tuple,
    List,
    Call,
    Keyword {
        arg: Option<String>,
        line: usize,
    },
    Str(String),
    Const,
    JoinedStr,
    NamedExpr,
    /// Any other node; the label is for debugging.
    Other(&'static str),
}

#[derive(Clone, Debug)]
pub struct Node {
    pub k: K,
    pub kids: Vec<Node>,
    /// Written in parentheses.
    pub paren: bool,
}

fn node(k: K, kids: Vec<Node>) -> Node {
    Node {
        k,
        kids,
        paren: false,
    }
}

fn other(label: &'static str, kids: Vec<Node>) -> Node {
    node(K::Other(label), kids)
}

const KEYWORDS: &[&str] = &[
    "False", "None", "True", "and", "as", "assert", "async", "await", "break", "class", "continue",
    "def", "del", "elif", "else", "except", "finally", "for", "from", "global", "if", "import",
    "in", "is", "lambda", "nonlocal", "not", "or", "pass", "raise", "return", "try", "while",
    "with", "yield",
];

/// Is `s` one of Python's hard keywords?
pub fn is_keyword(s: &str) -> bool {
    KEYWORDS.contains(&s)
}

const AUGASSIGN: &[&str] = &[
    "+=", "-=", "*=", "@=", "/=", "%=", "&=", "|=", "^=", "<<=", ">>=", "**=", "//=",
];

/// Deeper than this and CPython's parser gives up too ("too complex").
const MAX_DEPTH: usize = 2000;

type R<T> = Result<T, ()>;

pub struct Parser<'a> {
    toks: &'a [Token],
    pos: usize,
    /// The furthest token looked at: where CPython would report the error.
    pub furthest: usize,
    /// Where a block's indent was missing ("expected an indented block",
    /// a specific error, unlike a stray indent or dedent).
    pub missing_indent_at: Option<usize>,
    /// Every `expression`'s leading disjunction: (first token, token after).
    pub disjunctions: Vec<(usize, usize)>,
    depth: usize,
}

impl<'a> Parser<'a> {
    pub fn new(toks: &'a [Token]) -> Parser<'a> {
        Parser {
            toks,
            pos: 0,
            furthest: 0,
            missing_indent_at: None,
            disjunctions: Vec::new(),
            depth: 0,
        }
    }

    // ---- token helpers -------------------------------------------------

    fn tok(&mut self, n: usize) -> Option<&'a Token> {
        let i = self.pos + n;
        if i > self.furthest {
            self.furthest = i;
        }
        self.toks.get(i)
    }

    fn at_op(&mut self, op: &str) -> bool {
        self.op_at(0, op)
    }

    fn op_at(&mut self, n: usize, op: &str) -> bool {
        matches!(self.tok(n), Some(t) if t.kind == Kind::Op && t.text == op)
    }

    fn at_kw(&mut self, kw: &str) -> bool {
        self.kw_at(0, kw)
    }

    fn kw_at(&mut self, n: usize, kw: &str) -> bool {
        matches!(self.tok(n), Some(t) if t.kind == Kind::Name && t.text == kw)
    }

    fn at_kind(&mut self, kind: Kind) -> bool {
        matches!(self.tok(0), Some(t) if t.kind == kind)
    }

    /// A NAME that is not a keyword.
    fn name_at(&mut self, n: usize) -> Option<&'a Token> {
        match self.tok(n) {
            Some(t) if t.kind == Kind::Name && !KEYWORDS.contains(&t.text.as_str()) => Some(t),
            _ => None,
        }
    }

    fn advance(&mut self) -> &'a Token {
        let t = self.tok(0).expect("advance past end");
        self.pos += 1;
        t
    }

    fn expect_op(&mut self, op: &str) -> R<()> {
        if self.at_op(op) {
            self.pos += 1;
            Ok(())
        } else {
            Err(())
        }
    }

    fn expect_kw(&mut self, kw: &str) -> R<()> {
        if self.at_kw(kw) {
            self.pos += 1;
            Ok(())
        } else {
            Err(())
        }
    }

    fn expect_name(&mut self) -> R<&'a Token> {
        match self.name_at(0) {
            Some(t) => {
                self.pos += 1;
                Ok(t)
            }
            None => Err(()),
        }
    }

    fn eat_op(&mut self, op: &str) -> bool {
        if self.at_op(op) {
            self.pos += 1;
            true
        } else {
            false
        }
    }

    fn eat_kw(&mut self, kw: &str) -> bool {
        if self.at_kw(kw) {
            self.pos += 1;
            true
        } else {
            false
        }
    }

    fn enter(&mut self) -> R<()> {
        self.depth += 1;
        if self.depth > MAX_DEPTH {
            Err(())
        } else {
            Ok(())
        }
    }

    fn leave(&mut self) {
        self.depth -= 1;
    }

    /// Could the current token begin an expression?
    fn starts_expression(&mut self) -> bool {
        let Some(t) = self.tok(0) else { return false };
        match t.kind {
            Kind::Name => {
                !KEYWORDS.contains(&t.text.as_str())
                    || ["False", "None", "True", "lambda", "not", "await", "yield"]
                        .contains(&t.text.as_str())
            }
            Kind::Number | Kind::Str | Kind::FStart => true,
            Kind::Op => ["(", "[", "{", "-", "+", "~", "...", "*"].contains(&t.text.as_str()),
            _ => false,
        }
    }

    /// Parse one expression starting at token `at`; how far it read.
    pub fn probe_expression(toks: &'a [Token], at: usize) -> usize {
        let mut p = Parser::new(toks);
        p.pos = at;
        p.furthest = at;
        let _ = p.expression();
        p.furthest
    }

    // ---- statements ------------------------------------------------------

    pub fn file(&mut self) -> R<Vec<Node>> {
        let mut body = Vec::new();
        while !self.at_kind(Kind::EndMarker) {
            if self.tok(0).is_none() {
                return Err(());
            }
            body.extend(self.statement()?);
        }
        Ok(body)
    }

    fn statement(&mut self) -> R<Vec<Node>> {
        self.enter()?;
        let r = self.statement_inner();
        self.leave();
        r
    }

    fn statement_inner(&mut self) -> R<Vec<Node>> {
        if self.at_op("@") {
            return Ok(vec![self.decorated()?]);
        }
        let Some(t) = self.tok(0) else { return Err(()) };
        if t.kind == Kind::Name {
            match t.text.as_str() {
                "def" => return Ok(vec![self.funcdef(Vec::new())?]),
                "class" => return Ok(vec![self.classdef(Vec::new())?]),
                "if" => return Ok(vec![self.if_stmt()?]),
                "while" => return Ok(vec![self.while_stmt()?]),
                "for" => return Ok(vec![self.for_stmt()?]),
                "try" => return Ok(vec![self.try_stmt()?]),
                "with" => return Ok(vec![self.with_stmt()?]),
                "match" => {
                    // A soft keyword: when this is not a match statement,
                    // `match` is an ordinary name.
                    let save = self.pos;
                    if let Ok(n) = self.match_stmt() {
                        return Ok(vec![n]);
                    }
                    self.pos = save;
                }
                "async" => {
                    if self.kw_at(1, "def") {
                        self.pos += 1;
                        return Ok(vec![self.funcdef(Vec::new())?]);
                    }
                    if self.kw_at(1, "for") {
                        self.pos += 1;
                        return Ok(vec![self.for_stmt()?]);
                    }
                    if self.kw_at(1, "with") {
                        self.pos += 1;
                        return Ok(vec![self.with_stmt()?]);
                    }
                    return Err(());
                }
                _ => {}
            }
        }
        self.simple_stmts()
    }

    fn simple_stmts(&mut self) -> R<Vec<Node>> {
        let mut out = vec![self.simple_stmt()?];
        loop {
            if self.at_kind(Kind::Newline) {
                self.pos += 1;
                return Ok(out);
            }
            self.expect_op(";")?;
            if self.at_kind(Kind::Newline) {
                self.pos += 1;
                return Ok(out);
            }
            out.push(self.simple_stmt()?);
        }
    }

    fn block(&mut self) -> R<Vec<Node>> {
        if self.at_kind(Kind::Newline) {
            self.pos += 1;
            if !self.at_kind(Kind::Indent) {
                self.missing_indent_at = Some(self.pos);
                return Err(());
            }
            self.pos += 1;
            let mut body = Vec::new();
            loop {
                if self.at_kind(Kind::Dedent) {
                    self.pos += 1;
                    return Ok(body);
                }
                if self.tok(0).is_none() || self.at_kind(Kind::EndMarker) {
                    return Err(());
                }
                body.extend(self.statement()?);
            }
        }
        self.simple_stmts()
    }

    fn simple_stmt(&mut self) -> R<Node> {
        let Some(t) = self.tok(0) else { return Err(()) };
        if t.kind == Kind::Name {
            match t.text.as_str() {
                "pass" | "break" | "continue" => {
                    self.pos += 1;
                    return Ok(other("Pass", vec![]));
                }
                "return" => {
                    self.pos += 1;
                    let mut kids = Vec::new();
                    if self.starts_expression() {
                        kids.push(self.star_expressions()?);
                    }
                    return Ok(other("Return", kids));
                }
                "raise" => {
                    self.pos += 1;
                    let mut kids = Vec::new();
                    if self.starts_expression() {
                        kids.push(self.expression()?);
                        if self.eat_kw("from") {
                            kids.push(self.expression()?);
                        }
                    }
                    return Ok(other("Raise", kids));
                }
                "global" | "nonlocal" => {
                    self.pos += 1;
                    self.expect_name()?;
                    while self.eat_op(",") {
                        self.expect_name()?;
                    }
                    return Ok(other("Global", vec![]));
                }
                "del" => {
                    self.pos += 1;
                    let targets = self.del_targets()?;
                    if !(self.at_op(";") || self.at_kind(Kind::Newline)) {
                        return Err(());
                    }
                    return Ok(other("Delete", targets));
                }
                "assert" => {
                    self.pos += 1;
                    let mut kids = vec![self.expression()?];
                    if self.eat_op(",") {
                        kids.push(self.expression()?);
                    }
                    return Ok(other("Assert", kids));
                }
                "import" => {
                    self.pos += 1;
                    loop {
                        self.dotted_name()?;
                        if self.eat_kw("as") {
                            self.expect_name()?;
                        }
                        if !self.eat_op(",") {
                            break;
                        }
                    }
                    return Ok(other("Import", vec![]));
                }
                "from" => {
                    self.pos += 1;
                    let mut dots = 0;
                    while self.at_op(".") || self.at_op("...") {
                        dots += 1;
                        self.pos += 1;
                    }
                    if !self.at_kw("import") {
                        self.dotted_name()?;
                    } else if dots == 0 {
                        return Err(());
                    }
                    self.expect_kw("import")?;
                    if self.eat_op("*") {
                        return Ok(other("ImportFrom", vec![]));
                    }
                    let paren = self.eat_op("(");
                    loop {
                        self.expect_name()?;
                        if self.eat_kw("as") {
                            self.expect_name()?;
                        }
                        if !self.eat_op(",") {
                            break;
                        }
                        if paren && self.at_op(")") {
                            break;
                        }
                        if !paren && !self.name_at(0).is_some() {
                            // A trailing comma needs parentheses.
                            return Err(());
                        }
                    }
                    if paren {
                        self.expect_op(")")?;
                    }
                    return Ok(other("ImportFrom", vec![]));
                }
                "type" => {
                    if self.name_at(1).is_some() && (self.op_at(2, "=") || self.op_at(2, "[")) {
                        self.pos += 1;
                        let name = self.expect_name()?;
                        let mut kids = vec![node(K::Name(name.text.clone()), vec![])];
                        if self.at_op("[") {
                            kids.extend(self.type_params()?);
                        }
                        self.expect_op("=")?;
                        kids.push(self.expression()?);
                        return Ok(other("TypeAlias", kids));
                    }
                }
                "yield" => {
                    let y = self.yield_expr()?;
                    return self.after_first_expression(y);
                }
                _ => {}
            }
        }
        let first = self.star_expressions()?;
        self.after_first_expression(first)
    }

    /// An expression statement, or an assignment whose first part is `first`.
    fn after_first_expression(&mut self, first: Node) -> R<Node> {
        if self.at_op(":") {
            if !matches!(first.k, K::Name(_) | K::Attribute(_) | K::Subscript) {
                return Err(());
            }
            self.pos += 1;
            let annotation = self.expression()?;
            let mut kids = vec![first, annotation];
            if self.eat_op("=") {
                kids.push(self.assignment_value()?);
            }
            return Ok(other("AnnAssign", kids));
        }
        if let Some(t) = self.tok(0) {
            if t.kind == Kind::Op && AUGASSIGN.contains(&t.text.as_str()) {
                if !matches!(first.k, K::Name(_) | K::Attribute(_) | K::Subscript) {
                    return Err(());
                }
                self.pos += 1;
                let value = self.assignment_value()?;
                return Ok(other("AugAssign", vec![first, value]));
            }
        }
        if self.at_op("=") {
            if !valid_target(&first) {
                return Err(());
            }
            let mut kids = vec![first];
            loop {
                self.expect_op("=")?;
                let value = self.assignment_value()?;
                if self.at_op("=") {
                    if !valid_target(&value) {
                        return Err(());
                    }
                    kids.push(value);
                    continue;
                }
                kids.push(value);
                return Ok(other("Assign", kids));
            }
        }
        Ok(other("Expr", vec![first]))
    }

    fn assignment_value(&mut self) -> R<Node> {
        if self.at_kw("yield") {
            self.yield_expr()
        } else {
            self.star_expressions()
        }
    }

    fn dotted_name(&mut self) -> R<()> {
        self.expect_name()?;
        while self.at_op(".") {
            self.pos += 1;
            self.expect_name()?;
        }
        Ok(())
    }

    fn del_targets(&mut self) -> R<Vec<Node>> {
        let mut out = Vec::new();
        loop {
            let t = self.bitwise_or()?;
            if !valid_del_target(&t) {
                return Err(());
            }
            out.push(t);
            if !self.eat_op(",") {
                break;
            }
            if self.at_op(";") || self.at_kind(Kind::Newline) {
                break;
            }
        }
        Ok(out)
    }

    fn decorated(&mut self) -> R<Node> {
        let mut decorators = Vec::new();
        while self.eat_op("@") {
            decorators.push(self.named_expression()?);
            if !self.at_kind(Kind::Newline) {
                return Err(());
            }
            self.pos += 1;
        }
        if self.at_kw("def") {
            return self.funcdef(decorators);
        }
        if self.at_kw("class") {
            return self.classdef(decorators);
        }
        if self.at_kw("async") && self.kw_at(1, "def") {
            self.pos += 1;
            return self.funcdef(decorators);
        }
        Err(())
    }

    fn type_params(&mut self) -> R<Vec<Node>> {
        self.expect_op("[")?;
        let mut out = Vec::new();
        loop {
            if self.eat_op("*") || self.eat_op("**") {
                self.expect_name()?;
                out.push(other("TypeVarTuple", vec![]));
            } else {
                self.expect_name()?;
                let mut kids = Vec::new();
                if self.eat_op(":") {
                    kids.push(self.expression()?);
                }
                out.push(other("TypeVar", kids));
            }
            if !self.eat_op(",") {
                break;
            }
            if self.at_op("]") {
                break;
            }
        }
        self.expect_op("]")?;
        Ok(out)
    }

    fn funcdef(&mut self, decorators: Vec<Node>) -> R<Node> {
        self.expect_kw("def")?;
        self.expect_name()?;
        let type_params = if self.at_op("[") {
            self.type_params()?
        } else {
            Vec::new()
        };
        self.expect_op("(")?;
        let args = self.parameters(")", true)?;
        self.expect_op(")")?;
        let mut returns = Vec::new();
        if self.eat_op("->") {
            returns.push(self.expression()?);
        }
        self.expect_op(":")?;
        let body = self.block()?;
        let mut kids = vec![args];
        kids.extend(body);
        kids.extend(decorators);
        kids.extend(returns);
        kids.extend(type_params);
        Ok(other("FunctionDef", kids))
    }

    fn classdef(&mut self, decorators: Vec<Node>) -> R<Node> {
        self.expect_kw("class")?;
        self.expect_name()?;
        let type_params = if self.at_op("[") {
            self.type_params()?
        } else {
            Vec::new()
        };
        let mut bases = Vec::new();
        let mut keywords = Vec::new();
        if self.eat_op("(") {
            let (a, k) = self.arguments()?;
            bases = a;
            keywords = k;
            self.expect_op(")")?;
        }
        self.expect_op(":")?;
        let body = self.block()?;
        let mut kids = bases;
        kids.extend(keywords);
        kids.extend(body);
        kids.extend(decorators);
        kids.extend(type_params);
        Ok(other("ClassDef", kids))
    }

    /// Parameters of a def (`annotations`) or a lambda, up to `close`.
    fn parameters(&mut self, close: &str, annotations: bool) -> R<Node> {
        let mut posonly: Vec<Node> = Vec::new();
        let mut args: Vec<Node> = Vec::new();
        let mut vararg: Vec<Node> = Vec::new();
        let mut kwonly: Vec<Node> = Vec::new();
        let mut kw_defaults: Vec<Node> = Vec::new();
        let mut kwarg: Vec<Node> = Vec::new();
        let mut defaults: Vec<Node> = Vec::new();
        let mut seen_slash = false;
        let mut seen_star = false;
        let mut bare_star = false;
        let mut seen_default = false;
        let mut done = false;

        while !self.at_op(close) {
            if done {
                return Err(());
            }
            if self.eat_op("/") {
                if seen_slash || seen_star || (posonly.is_empty() && args.is_empty()) {
                    return Err(());
                }
                seen_slash = true;
                posonly.append(&mut args);
            } else if self.eat_op("**") {
                let a = self.param(annotations, false)?;
                kwarg.push(a);
                done = true;
            } else if self.eat_op("*") {
                if seen_star {
                    return Err(());
                }
                seen_star = true;
                if self.at_op(",") {
                    bare_star = true;
                } else {
                    let a = self.param(annotations, true)?;
                    vararg.push(a);
                }
            } else {
                let a = self.param(annotations, false)?;
                if seen_star {
                    kwonly.push(a);
                    if self.eat_op("=") {
                        kw_defaults.push(self.expression()?);
                    }
                    if bare_star {
                        bare_star = false;
                    }
                } else {
                    args.push(a);
                    if self.eat_op("=") {
                        defaults.push(self.expression()?);
                        seen_default = true;
                    } else if seen_default {
                        return Err(());
                    }
                }
            }
            if !self.eat_op(",") {
                break;
            }
        }
        if bare_star {
            return Err(());
        }
        if !self.at_op(close) {
            return Err(());
        }
        // A bare '*' must be followed by a named parameter.
        if seen_star && vararg.is_empty() && kwonly.is_empty() {
            return Err(());
        }
        let mut kids = posonly;
        kids.extend(args);
        kids.extend(vararg);
        kids.extend(kwonly);
        kids.extend(kw_defaults);
        kids.extend(kwarg);
        kids.extend(defaults);
        Ok(other("arguments", kids))
    }

    fn param(&mut self, annotations: bool, star: bool) -> R<Node> {
        self.expect_name()?;
        let mut kids = Vec::new();
        if annotations && self.eat_op(":") {
            if star && self.at_op("*") {
                self.pos += 1;
                let v = self.bitwise_or()?;
                kids.push(node(K::Starred, vec![v]));
            } else {
                kids.push(self.expression()?);
            }
        }
        Ok(other("arg", kids))
    }

    fn if_stmt(&mut self) -> R<Node> {
        // At 'if' or 'elif'.
        self.pos += 1;
        let test = self.named_expression()?;
        self.expect_op(":")?;
        let body = self.block()?;
        let mut kids = vec![test];
        kids.extend(body);
        if self.at_kw("elif") {
            kids.push(self.if_stmt()?);
        } else if self.eat_kw("else") {
            self.expect_op(":")?;
            kids.extend(self.block()?);
        }
        Ok(other("If", kids))
    }

    fn while_stmt(&mut self) -> R<Node> {
        self.expect_kw("while")?;
        let test = self.named_expression()?;
        self.expect_op(":")?;
        let mut kids = vec![test];
        kids.extend(self.block()?);
        if self.eat_kw("else") {
            self.expect_op(":")?;
            kids.extend(self.block()?);
        }
        Ok(other("While", kids))
    }

    fn for_stmt(&mut self) -> R<Node> {
        self.expect_kw("for")?;
        let target = self.star_targets()?;
        self.expect_kw("in")?;
        let iter = self.star_expressions()?;
        self.expect_op(":")?;
        let mut kids = vec![target, iter];
        kids.extend(self.block()?);
        if self.eat_kw("else") {
            self.expect_op(":")?;
            kids.extend(self.block()?);
        }
        Ok(other("For", kids))
    }

    fn with_stmt(&mut self) -> R<Node> {
        self.expect_kw("with")?;
        // with ( item, ... ) :   is tried first, as in the grammar.
        let save = self.pos;
        if self.at_op("(") {
            self.pos += 1;
            if let Ok(items) = self.with_items(true) {
                if self.eat_op(")") && self.at_op(":") {
                    self.pos += 1;
                    let mut kids = items;
                    kids.extend(self.block()?);
                    return Ok(other("With", kids));
                }
            }
            self.pos = save;
        }
        let items = self.with_items(false)?;
        self.expect_op(":")?;
        let mut kids = items;
        kids.extend(self.block()?);
        Ok(other("With", kids))
    }

    fn with_items(&mut self, parenthesized: bool) -> R<Vec<Node>> {
        let mut items = Vec::new();
        loop {
            let expr = self.expression()?;
            let mut kids = vec![expr];
            if self.eat_kw("as") {
                let target = self.star_target()?;
                if !(self.at_op(",") || self.at_op(")") || self.at_op(":")) {
                    return Err(());
                }
                kids.push(target);
            }
            items.push(other("withitem", kids));
            if !self.eat_op(",") {
                break;
            }
            if parenthesized && self.at_op(")") {
                break;
            }
        }
        Ok(items)
    }

    fn try_stmt(&mut self) -> R<Node> {
        self.expect_kw("try")?;
        self.expect_op(":")?;
        let mut kids = self.block()?;
        let mut handlers = 0;
        let mut star: Option<bool> = None;
        while self.at_kw("except") {
            self.pos += 1;
            let is_star = self.eat_op("*");
            if let Some(s) = star {
                if s != is_star {
                    return Err(());
                }
            }
            star = Some(is_star);
            let mut hk = Vec::new();
            if self.at_op(":") {
                if is_star {
                    return Err(());
                }
            } else {
                hk.push(self.expression()?);
                if self.eat_kw("as") {
                    self.expect_name()?;
                }
            }
            self.expect_op(":")?;
            hk.extend(self.block()?);
            kids.push(other("ExceptHandler", hk));
            handlers += 1;
        }
        if handlers > 0 && self.eat_kw("else") {
            self.expect_op(":")?;
            kids.extend(self.block()?);
        }
        if self.eat_kw("finally") {
            self.expect_op(":")?;
            kids.extend(self.block()?);
        } else if handlers == 0 {
            return Err(());
        }
        Ok(other("Try", kids))
    }

    // ---- match statements --------------------------------------------------

    fn match_stmt(&mut self) -> R<Node> {
        self.pos += 1; // "match"
        let first = self.star_named_expression()?;
        let subject = if self.at_op(",") {
            let mut elts = vec![first];
            while self.eat_op(",") {
                if self.at_op(":") {
                    break;
                }
                elts.push(self.star_named_expression()?);
            }
            node(K::Tuple, elts)
        } else {
            if matches!(first.k, K::Starred) {
                return Err(());
            }
            first
        };
        self.expect_op(":")?;
        if !self.at_kind(Kind::Newline) {
            return Err(());
        }
        self.pos += 1;
        if !self.at_kind(Kind::Indent) {
            return Err(());
        }
        self.pos += 1;
        let mut kids = vec![subject];
        loop {
            if !(self.at_kw("case") && self.tok(0).map_or(false, |t| t.kind == Kind::Name)) {
                return Err(());
            }
            self.pos += 1;
            self.patterns()?;
            let mut case_kids = Vec::new();
            if self.eat_kw("if") {
                case_kids.push(self.named_expression()?);
            }
            self.expect_op(":")?;
            case_kids.extend(self.block()?);
            kids.push(other("match_case", case_kids));
            if self.at_kind(Kind::Dedent) {
                self.pos += 1;
                break;
            }
        }
        Ok(other("Match", kids))
    }

    fn starts_pattern(&mut self) -> bool {
        let Some(t) = self.tok(0) else { return false };
        match t.kind {
            Kind::Name => {
                !KEYWORDS.contains(&t.text.as_str())
                    || ["None", "True", "False"].contains(&t.text.as_str())
            }
            Kind::Number | Kind::Str => true,
            Kind::Op => ["-", "(", "[", "{", "*"].contains(&t.text.as_str()),
            _ => false,
        }
    }

    /// patterns: open_sequence_pattern | pattern
    fn patterns(&mut self) -> R<()> {
        let save = self.pos;
        if self.maybe_star_pattern().is_ok() && self.at_op(",") {
            self.pos += 1;
            self.maybe_sequence_rest()?;
            return Ok(());
        }
        self.pos = save;
        self.pattern()
    }

    /// The rest of a maybe_sequence_pattern after a comma: more patterns,
    /// an optional trailing comma.
    fn maybe_sequence_rest(&mut self) -> R<()> {
        while self.starts_pattern() {
            self.maybe_star_pattern()?;
            if !self.eat_op(",") {
                break;
            }
        }
        Ok(())
    }

    fn maybe_star_pattern(&mut self) -> R<()> {
        if self.eat_op("*") {
            return match self.name_at(0) {
                Some(t) if !(t.text != "_" && self.next_blocks_capture(1)) => {
                    self.pos += 1;
                    Ok(())
                }
                _ => Err(()),
            };
        }
        self.pattern()
    }

    /// `!('.' | '(' | '=')` after a capture name at offset `n`.
    fn next_blocks_capture(&mut self, n: usize) -> bool {
        self.op_at(n, ".") || self.op_at(n, "(") || self.op_at(n, "=")
    }

    /// pattern: or_pattern ['as' capture]
    fn pattern(&mut self) -> R<()> {
        self.enter()?;
        let r = (|| {
            self.closed_pattern()?;
            while self.eat_op("|") {
                self.closed_pattern()?;
            }
            if self.at_kw("as") {
                match self.name_at(1) {
                    Some(t) if t.text != "_" && !self.next_blocks_capture(2) => {
                        self.pos += 2;
                    }
                    _ => return Err(()),
                }
            }
            Ok(())
        })();
        self.leave();
        r
    }

    fn is_imaginary(t: &Token) -> bool {
        t.text.ends_with('j') || t.text.ends_with('J')
    }

    /// signed_number !('+'|'-') | complex_number
    fn number_pattern(&mut self) -> R<()> {
        self.eat_op("-");
        let t = match self.tok(0) {
            Some(t) if t.kind == Kind::Number => t,
            _ => return Err(()),
        };
        self.pos += 1;
        if self.at_op("+") || self.at_op("-") {
            if Self::is_imaginary(t) {
                return Err(());
            }
            self.pos += 1;
            match self.tok(0) {
                Some(i) if i.kind == Kind::Number && Self::is_imaginary(i) => self.pos += 1,
                _ => return Err(()),
            }
        }
        Ok(())
    }

    fn string_pattern(&mut self) -> R<()> {
        let mut any_bytes = false;
        let mut any_str = false;
        while let Some(t) = self.tok(0) {
            match t.kind {
                Kind::Str => {
                    match &t.value {
                        Some(LiteralValue::Str(..)) => any_str = true,
                        Some(LiteralValue::Bytes(_)) => any_bytes = true,
                        _ => return Err(()),
                    }
                    self.pos += 1;
                }
                Kind::FStart => return Err(()),
                _ => break,
            }
        }
        if any_bytes && any_str {
            return Err(());
        }
        Ok(())
    }

    /// A dotted name; returns how many parts it has.
    fn name_or_attr(&mut self) -> R<usize> {
        self.expect_name()?;
        let mut parts = 1;
        while self.at_op(".") {
            self.pos += 1;
            self.expect_name()?;
            parts += 1;
        }
        Ok(parts)
    }

    fn closed_pattern(&mut self) -> R<()> {
        let Some(t) = self.tok(0) else { return Err(()) };
        match t.kind {
            Kind::Number => return self.number_pattern(),
            Kind::Str => return self.string_pattern(),
            Kind::FStart => return Err(()),
            Kind::Op if t.text == "-" => return self.number_pattern(),
            Kind::Op if t.text == "(" => {
                self.pos += 1;
                let save = self.pos;
                // group_pattern: '(' pattern ')'
                if self.pattern().is_ok() && self.eat_op(")") {
                    return Ok(());
                }
                self.pos = save;
                // sequence_pattern: '(' [open_sequence_pattern] ')'
                if self.eat_op(")") {
                    return Ok(());
                }
                self.maybe_star_pattern()?;
                self.expect_op(",")?;
                self.maybe_sequence_rest()?;
                return self.expect_op(")");
            }
            Kind::Op if t.text == "[" => {
                self.pos += 1;
                if self.eat_op("]") {
                    return Ok(());
                }
                loop {
                    self.maybe_star_pattern()?;
                    if !self.eat_op(",") || self.at_op("]") {
                        break;
                    }
                }
                return self.expect_op("]");
            }
            Kind::Op if t.text == "{" => {
                self.pos += 1;
                return self.mapping_pattern();
            }
            Kind::Name => {}
            _ => return Err(()),
        }
        if ["None", "True", "False"].contains(&t.text.as_str()) {
            self.pos += 1;
            return Ok(());
        }
        if self.name_at(0).is_none() {
            return Err(());
        }
        // capture_pattern / wildcard_pattern
        if !self.next_blocks_capture(1) {
            self.pos += 1;
            return Ok(());
        }
        if t.text == "_" && !self.op_at(1, ".") {
            self.pos += 1;
            return Ok(());
        }
        let parts = self.name_or_attr()?;
        if self.at_op("(") {
            self.pos += 1;
            return self.class_pattern_args();
        }
        // value_pattern: attr !('.' | '(' | '=')
        if parts >= 2 && !self.at_op("=") {
            return Ok(());
        }
        Err(())
    }

    fn mapping_pattern(&mut self) -> R<()> {
        loop {
            if self.eat_op("}") {
                return Ok(());
            }
            if self.eat_op("**") {
                match self.name_at(0) {
                    Some(t) if t.text != "_" && !self.next_blocks_capture(1) => self.pos += 1,
                    _ => return Err(()),
                }
                self.eat_op(",");
                return self.expect_op("}");
            }
            // key: literal_expr | attr
            let Some(t) = self.tok(0) else { return Err(()) };
            match t.kind {
                Kind::Number => self.number_pattern()?,
                Kind::Op if t.text == "-" => self.number_pattern()?,
                Kind::Str => self.string_pattern()?,
                Kind::Name if ["None", "True", "False"].contains(&t.text.as_str()) => self.pos += 1,
                Kind::Name => {
                    if self.name_or_attr()? < 2 {
                        return Err(());
                    }
                }
                _ => return Err(()),
            }
            self.expect_op(":")?;
            self.pattern()?;
            if !self.eat_op(",") {
                return self.expect_op("}");
            }
        }
    }

    /// After `Cls(`: positional patterns, then keyword patterns.
    fn class_pattern_args(&mut self) -> R<()> {
        let mut seen_keyword = false;
        loop {
            if self.eat_op(")") {
                return Ok(());
            }
            if self.name_at(0).is_some() && self.op_at(1, "=") {
                self.pos += 2;
                self.pattern()?;
                seen_keyword = true;
            } else {
                if seen_keyword {
                    return Err(());
                }
                self.pattern()?;
            }
            if !self.eat_op(",") {
                return self.expect_op(")");
            }
        }
    }

    // ---- targets -----------------------------------------------------------

    fn star_target(&mut self) -> R<Node> {
        if self.eat_op("*") {
            if self.at_op("*") {
                return Err(());
            }
            let inner = self.bitwise_or()?;
            let n = node(K::Starred, vec![inner]);
            if !valid_target(&n) {
                return Err(());
            }
            return Ok(n);
        }
        let t = self.bitwise_or()?;
        if !valid_target(&t) {
            return Err(());
        }
        Ok(t)
    }

    fn star_targets(&mut self) -> R<Node> {
        let first = self.star_target()?;
        if !self.at_op(",") {
            if matches!(first.k, K::Starred) {
                // star_targets: star_target !','  (a lone starred target is
                // still accepted by the parser)
            }
            return Ok(first);
        }
        let mut elts = vec![first];
        while self.eat_op(",") {
            if self.at_op("*") || self.starts_target() {
                elts.push(self.star_target()?);
            } else {
                break;
            }
        }
        Ok(node(K::Tuple, elts))
    }

    fn starts_target(&mut self) -> bool {
        let Some(t) = self.tok(0) else { return false };
        match t.kind {
            Kind::Name => !KEYWORDS.contains(&t.text.as_str()),
            Kind::Op => t.text == "(" || t.text == "[",
            Kind::Str | Kind::FStart | Kind::Number => true,
            _ => false,
        }
    }

    // ---- expressions -------------------------------------------------------

    fn star_expressions(&mut self) -> R<Node> {
        let first = self.star_expression()?;
        if !self.at_op(",") {
            return Ok(first);
        }
        let mut elts = vec![first];
        while self.eat_op(",") {
            if self.starts_expression() {
                elts.push(self.star_expression()?);
            } else {
                break;
            }
        }
        Ok(node(K::Tuple, elts))
    }

    fn star_expression(&mut self) -> R<Node> {
        if self.eat_op("*") {
            let v = self.bitwise_or()?;
            return Ok(node(K::Starred, vec![v]));
        }
        self.expression()
    }

    fn star_named_expression(&mut self) -> R<Node> {
        if self.eat_op("*") {
            let v = self.bitwise_or()?;
            return Ok(node(K::Starred, vec![v]));
        }
        self.named_expression()
    }

    fn named_expression(&mut self) -> R<Node> {
        if self.name_at(0).is_some() && self.op_at(1, ":=") {
            let name = self.advance().text.clone();
            self.pos += 1;
            let value = self.expression()?;
            return Ok(node(K::NamedExpr, vec![node(K::Name(name), vec![]), value]));
        }
        let e = self.expression()?;
        if self.at_op(":=") {
            return Err(());
        }
        Ok(e)
    }

    fn expression(&mut self) -> R<Node> {
        self.enter()?;
        let r = self.expression_inner();
        self.leave();
        r
    }

    fn expression_inner(&mut self) -> R<Node> {
        if self.at_kw("lambda") {
            return self.lambdef();
        }
        let start = self.pos;
        let body = self.disjunction()?;
        self.disjunctions.push((start, self.pos));
        if self.at_kw("if") {
            self.pos += 1;
            let test = self.disjunction()?;
            self.expect_kw("else")?;
            let orelse = self.expression()?;
            return Ok(other("IfExp", vec![test, body, orelse]));
        }
        Ok(body)
    }

    fn lambdef(&mut self) -> R<Node> {
        self.expect_kw("lambda")?;
        let args = self.parameters(":", false)?;
        self.expect_op(":")?;
        let body = self.expression()?;
        Ok(other("Lambda", vec![args, body]))
    }

    fn disjunction(&mut self) -> R<Node> {
        let first = self.conjunction()?;
        if !self.at_kw("or") {
            return Ok(first);
        }
        let mut values = vec![first];
        while self.eat_kw("or") {
            values.push(self.conjunction()?);
        }
        Ok(other("BoolOp", values))
    }

    fn conjunction(&mut self) -> R<Node> {
        let first = self.inversion()?;
        if !self.at_kw("and") {
            return Ok(first);
        }
        let mut values = vec![first];
        while self.eat_kw("and") {
            values.push(self.inversion()?);
        }
        Ok(other("BoolOp", values))
    }

    fn inversion(&mut self) -> R<Node> {
        if self.eat_kw("not") {
            self.enter()?;
            let v = self.inversion();
            self.leave();
            return Ok(other("UnaryOp", vec![v?]));
        }
        self.comparison()
    }

    fn comparison(&mut self) -> R<Node> {
        let left = self.bitwise_or()?;
        let mut kids = vec![left];
        loop {
            let is_op = ["==", "!=", "<", "<=", ">", ">="]
                .iter()
                .any(|op| self.at_op(op));
            if is_op {
                self.pos += 1;
            } else if self.at_kw("in") {
                self.pos += 1;
            } else if self.at_kw("not") && self.kw_at(1, "in") {
                self.pos += 2;
            } else if self.at_kw("is") {
                self.pos += 1;
                self.eat_kw("not");
            } else {
                break;
            }
            kids.push(self.bitwise_or()?);
        }
        if kids.len() == 1 {
            Ok(kids.pop().unwrap())
        } else {
            Ok(other("Compare", kids))
        }
    }

    fn binary(&mut self, ops: &[&str], next: fn(&mut Self) -> R<Node>) -> R<Node> {
        let mut left = next(self)?;
        loop {
            let matched = ops.iter().any(|op| self.at_op(op));
            if !matched {
                return Ok(left);
            }
            self.pos += 1;
            let right = next(self)?;
            left = other("BinOp", vec![left, right]);
        }
    }

    fn bitwise_or(&mut self) -> R<Node> {
        self.binary(&["|"], Self::bitwise_xor)
    }

    fn bitwise_xor(&mut self) -> R<Node> {
        self.binary(&["^"], Self::bitwise_and)
    }

    fn bitwise_and(&mut self) -> R<Node> {
        self.binary(&["&"], Self::shift_expr)
    }

    fn shift_expr(&mut self) -> R<Node> {
        self.binary(&["<<", ">>"], Self::sum)
    }

    fn sum(&mut self) -> R<Node> {
        self.binary(&["+", "-"], Self::term)
    }

    fn term(&mut self) -> R<Node> {
        self.binary(&["*", "/", "//", "%", "@"], Self::factor)
    }

    fn factor(&mut self) -> R<Node> {
        if self.at_op("+") || self.at_op("-") || self.at_op("~") {
            self.pos += 1;
            self.enter()?;
            let v = self.factor();
            self.leave();
            return Ok(other("UnaryOp", vec![v?]));
        }
        self.power()
    }

    fn power(&mut self) -> R<Node> {
        let base = self.await_primary()?;
        if self.eat_op("**") {
            self.enter()?;
            let exp = self.factor();
            self.leave();
            return Ok(other("BinOp", vec![base, exp?]));
        }
        Ok(base)
    }

    fn await_primary(&mut self) -> R<Node> {
        if self.eat_kw("await") {
            let v = self.primary()?;
            return Ok(other("Await", vec![v]));
        }
        self.primary()
    }

    fn primary(&mut self) -> R<Node> {
        let mut e = self.atom()?;
        loop {
            if self.at_op(".") {
                self.pos += 1;
                let name = self.expect_name()?;
                e = node(K::Attribute(name.text.clone()), vec![e]);
            } else if self.at_op("(") {
                self.pos += 1;
                e = self.call_rest(e)?;
            } else if self.at_op("[") {
                self.pos += 1;
                let s = self.slices()?;
                self.expect_op("]")?;
                e = node(K::Subscript, vec![e, s]);
            } else {
                return Ok(e);
            }
        }
    }

    /// After `func(`.
    fn call_rest(&mut self, func: Node) -> R<Node> {
        self.enter()?;
        let r = (|| {
            // primary genexp: f(x for x in y)
            let save = self.pos;
            if self.starts_expression()
                && !self.at_op("*")
                && !(self.name_at(0).is_some() && self.op_at(1, "="))
            {
                let save_furthest = self.furthest;
                if let Ok(elt) = self.named_expression() {
                    if self.at_kw("for") || (self.at_kw("async") && self.kw_at(1, "for")) {
                        let gens = self.comprehensions()?;
                        self.expect_op(")")?;
                        let mut kids = vec![elt];
                        kids.extend(gens);
                        return Ok(node(K::Call, vec![func, other("GeneratorExp", kids)]));
                    }
                }
                self.pos = save;
                self.furthest = self.furthest.max(save_furthest);
            }
            let (args, keywords) = self.arguments()?;
            self.expect_op(")")?;
            let mut kids = vec![func];
            kids.extend(args);
            kids.extend(keywords);
            Ok(node(K::Call, kids))
        })();
        self.leave();
        r
    }

    /// Call arguments up to (not including) ')': positional and keyword.
    fn arguments(&mut self) -> R<(Vec<Node>, Vec<Node>)> {
        let mut args = Vec::new();
        let mut keywords = Vec::new();
        let mut seen_keyword = false;
        let mut seen_double_star = false;
        while !self.at_op(")") {
            if self.at_op("**") {
                let line = self.tok(0).unwrap().line;
                self.pos += 1;
                let v = self.expression()?;
                keywords.push(node(K::Keyword { arg: None, line }, vec![v]));
                seen_double_star = true;
            } else if self.at_op("*") {
                if seen_double_star {
                    return Err(());
                }
                self.pos += 1;
                let v = self.expression()?;
                args.push(node(K::Starred, vec![v]));
            } else if self.name_at(0).is_some() && self.op_at(1, "=") {
                let t = self.advance();
                self.pos += 1;
                let v = self.expression()?;
                keywords.push(node(
                    K::Keyword {
                        arg: Some(t.text.clone()),
                        line: t.line,
                    },
                    vec![v],
                ));
                seen_keyword = true;
            } else {
                if seen_keyword || seen_double_star {
                    return Err(());
                }
                let v = self.named_expression()?;
                if self.at_op("=") {
                    return Err(());
                }
                if self.at_kw("for") || self.at_kw("async") {
                    // An unparenthesized generator among other arguments.
                    return Err(());
                }
                args.push(v);
            }
            if !self.eat_op(",") {
                break;
            }
        }
        Ok((args, keywords))
    }

    fn slices(&mut self) -> R<Node> {
        let first = self.slice_item()?;
        if !self.at_op(",") {
            if matches!(first.k, K::Starred) {
                return Ok(node(K::Tuple, vec![first]));
            }
            return Ok(first);
        }
        let mut elts = vec![first];
        while self.eat_op(",") {
            if self.at_op("]") {
                break;
            }
            elts.push(self.slice_item()?);
        }
        Ok(node(K::Tuple, elts))
    }

    fn slice_item(&mut self) -> R<Node> {
        if self.eat_op("*") {
            let v = self.bitwise_or()?;
            return Ok(node(K::Starred, vec![v]));
        }
        let mut kids = Vec::new();
        if !self.at_op(":") {
            let e = self.named_expression()?;
            if !self.at_op(":") {
                return Ok(e);
            }
            if matches!(e.k, K::NamedExpr) && !e.paren {
                return Err(());
            }
            kids.push(e);
        }
        self.expect_op(":")?;
        if !self.at_op(":") && !self.at_op(",") && !self.at_op("]") {
            kids.push(self.expression()?);
        }
        if self.eat_op(":") && !self.at_op(",") && !self.at_op("]") {
            kids.push(self.expression()?);
        }
        Ok(other("Slice", kids))
    }

    fn comprehensions(&mut self) -> R<Vec<Node>> {
        let mut out = Vec::new();
        loop {
            if self.at_kw("async") && self.kw_at(1, "for") {
                self.pos += 1;
            } else if !self.at_kw("for") {
                break;
            }
            self.expect_kw("for")?;
            let target = self.star_targets()?;
            self.expect_kw("in")?;
            let iter = self.disjunction()?;
            let mut kids = vec![target, iter];
            while self.eat_kw("if") {
                kids.push(self.disjunction()?);
            }
            out.push(other("comprehension", kids));
        }
        if out.is_empty() {
            return Err(());
        }
        Ok(out)
    }

    fn yield_expr(&mut self) -> R<Node> {
        self.expect_kw("yield")?;
        if self.eat_kw("from") {
            let v = self.expression()?;
            return Ok(other("YieldFrom", vec![v]));
        }
        let mut kids = Vec::new();
        if self.starts_expression() {
            kids.push(self.star_expressions()?);
        }
        Ok(other("Yield", kids))
    }

    fn atom(&mut self) -> R<Node> {
        let Some(t) = self.tok(0) else { return Err(()) };
        match t.kind {
            Kind::Name => {
                match t.text.as_str() {
                    "True" | "False" | "None" => {
                        self.pos += 1;
                        return Ok(node(K::Const, vec![]));
                    }
                    _ => {}
                }
                if KEYWORDS.contains(&t.text.as_str()) {
                    return Err(());
                }
                self.pos += 1;
                Ok(node(K::Name(t.text.clone()), vec![]))
            }
            Kind::Number => {
                self.pos += 1;
                Ok(node(K::Const, vec![]))
            }
            Kind::Str | Kind::FStart => self.strings(),
            Kind::Op => match t.text.as_str() {
                "..." => {
                    self.pos += 1;
                    Ok(node(K::Const, vec![]))
                }
                "(" => {
                    self.pos += 1;
                    self.enter()?;
                    let r = self.paren_rest();
                    self.leave();
                    r
                }
                "[" => {
                    self.pos += 1;
                    self.enter()?;
                    let r = self.list_rest();
                    self.leave();
                    r
                }
                "{" => {
                    self.pos += 1;
                    self.enter()?;
                    let r = self.brace_rest();
                    self.leave();
                    r
                }
                _ => Err(()),
            },
            _ => Err(()),
        }
    }

    /// After '(': a tuple, a group or a generator.
    fn paren_rest(&mut self) -> R<Node> {
        if self.eat_op(")") {
            let mut n = node(K::Tuple, vec![]);
            n.paren = true;
            return Ok(n);
        }
        if self.at_kw("yield") {
            let mut y = self.yield_expr()?;
            self.expect_op(")")?;
            y.paren = true;
            return Ok(y);
        }
        let first = self.star_named_expression()?;
        if self.at_kw("for") || (self.at_kw("async") && self.kw_at(1, "for")) {
            if matches!(first.k, K::Starred) {
                return Err(());
            }
            let gens = self.comprehensions()?;
            self.expect_op(")")?;
            let mut kids = vec![first];
            kids.extend(gens);
            let mut n = other("GeneratorExp", kids);
            n.paren = true;
            return Ok(n);
        }
        if self.eat_op(")") {
            if matches!(first.k, K::Starred) {
                return Err(());
            }
            let mut n = first;
            n.paren = true;
            return Ok(n);
        }
        self.expect_op(",")?;
        let mut elts = vec![first];
        while !self.at_op(")") {
            elts.push(self.star_named_expression()?);
            if !self.eat_op(",") {
                break;
            }
        }
        self.expect_op(")")?;
        let mut n = node(K::Tuple, elts);
        n.paren = true;
        Ok(n)
    }

    /// After '[': a list or a list comprehension.
    fn list_rest(&mut self) -> R<Node> {
        if self.eat_op("]") {
            return Ok(node(K::List, vec![]));
        }
        let first = self.star_named_expression()?;
        if self.at_kw("for") || (self.at_kw("async") && self.kw_at(1, "for")) {
            if matches!(first.k, K::Starred) {
                return Err(());
            }
            let gens = self.comprehensions()?;
            self.expect_op("]")?;
            let mut kids = vec![first];
            kids.extend(gens);
            return Ok(other("ListComp", kids));
        }
        let mut elts = vec![first];
        while self.eat_op(",") {
            if self.at_op("]") {
                break;
            }
            elts.push(self.star_named_expression()?);
        }
        self.expect_op("]")?;
        Ok(node(K::List, elts))
    }

    /// After '{': a dict, a set, or one of their comprehensions.
    fn brace_rest(&mut self) -> R<Node> {
        if self.eat_op("}") {
            return Ok(other("Dict", vec![]));
        }
        if self.at_op("**") {
            return self.dict_items(Vec::new(), Vec::new());
        }
        if self.at_op("*") {
            return self.set_items();
        }
        let first = self.named_expression()?;
        if self.eat_op(":") {
            if matches!(first.k, K::NamedExpr) && !first.paren {
                return Err(());
            }
            let value = self.expression()?;
            if self.at_kw("for") || (self.at_kw("async") && self.kw_at(1, "for")) {
                let gens = self.comprehensions()?;
                self.expect_op("}")?;
                let mut kids = vec![first, value];
                kids.extend(gens);
                return Ok(other("DictComp", kids));
            }
            if self.eat_op("}") {
                return Ok(other("Dict", vec![first, value]));
            }
            self.expect_op(",")?;
            return self.dict_items(vec![first], vec![value]);
        }
        if self.at_kw("for") || (self.at_kw("async") && self.kw_at(1, "for")) {
            let gens = self.comprehensions()?;
            self.expect_op("}")?;
            let mut kids = vec![first];
            kids.extend(gens);
            return Ok(other("SetComp", kids));
        }
        let mut elts = vec![first];
        while self.eat_op(",") {
            if self.at_op("}") {
                break;
            }
            elts.push(self.star_named_expression()?);
        }
        self.expect_op("}")?;
        Ok(other("Set", elts))
    }

    fn set_items(&mut self) -> R<Node> {
        let mut elts = Vec::new();
        loop {
            elts.push(self.star_named_expression()?);
            if !self.eat_op(",") || self.at_op("}") {
                break;
            }
        }
        self.expect_op("}")?;
        Ok(other("Set", elts))
    }

    fn dict_items(&mut self, mut keys: Vec<Node>, mut values: Vec<Node>) -> R<Node> {
        while !self.at_op("}") {
            if self.eat_op("**") {
                values.push(self.bitwise_or()?);
            } else {
                keys.push(self.expression()?);
                self.expect_op(":")?;
                values.push(self.expression()?);
            }
            if !self.eat_op(",") {
                break;
            }
        }
        self.expect_op("}")?;
        let mut kids = keys;
        kids.extend(values);
        Ok(other("Dict", kids))
    }

    /// Adjacent string literals: one Constant, or a JoinedStr if any is an
    /// f-string.
    fn strings(&mut self) -> R<Node> {
        let mut value = String::new();
        let mut any_bytes = false;
        let mut any_str = false;
        let mut fstring = false;
        let mut kids = Vec::new();
        loop {
            match self.tok(0) {
                Some(t) if t.kind == Kind::Str => {
                    self.pos += 1;
                    match &t.value {
                        Some(LiteralValue::Str(s, _)) => {
                            any_str = true;
                            value.push_str(s);
                        }
                        Some(LiteralValue::Bytes(_)) => any_bytes = true,
                        _ => return Err(()),
                    }
                }
                Some(t) if t.kind == Kind::FStart => {
                    self.pos += 1;
                    any_str = true;
                    fstring = true;
                    kids.extend(self.fstring_rest()?);
                }
                _ => break,
            }
        }
        if any_bytes && any_str {
            return Err(());
        }
        if fstring {
            return Ok(node(K::JoinedStr, kids));
        }
        if any_bytes {
            return Ok(node(K::Const, vec![]));
        }
        Ok(node(K::Str(value), vec![]))
    }

    /// After FSTRING_START: the FormattedValue nodes, through FSTRING_END.
    fn fstring_rest(&mut self) -> R<Vec<Node>> {
        let mut values = Vec::new();
        loop {
            let Some(t) = self.tok(0) else { return Err(()) };
            match t.kind {
                Kind::FEnd => {
                    self.pos += 1;
                    return Ok(values);
                }
                Kind::FMiddle => {
                    if t.bad {
                        return Err(());
                    }
                    self.pos += 1;
                }
                Kind::Op if t.text == "{" => {
                    self.pos += 1;
                    values.push(self.replacement_field()?);
                }
                _ => return Err(()),
            }
        }
    }

    /// After a field's '{': through its closing '}'.
    fn replacement_field(&mut self) -> R<Node> {
        self.enter()?;
        let r = (|| {
            let value = if self.at_kw("yield") {
                self.yield_expr()?
            } else {
                self.star_expressions()?
            };
            let mut kids = vec![value];
            self.eat_op("=");
            if self.eat_op("!") {
                match self.tok(0) {
                    Some(t)
                        if t.kind == Kind::Name && ["s", "r", "a"].contains(&t.text.as_str()) =>
                    {
                        self.pos += 1;
                    }
                    _ => return Err(()),
                }
            }
            if self.eat_op(":") {
                let mut spec = Vec::new();
                loop {
                    let Some(t) = self.tok(0) else { return Err(()) };
                    match t.kind {
                        Kind::FMiddle => {
                            if t.bad {
                                return Err(());
                            }
                            self.pos += 1;
                        }
                        Kind::Op if t.text == "{" => {
                            self.pos += 1;
                            spec.push(self.replacement_field()?);
                        }
                        _ => break,
                    }
                }
                kids.push(node(K::JoinedStr, spec));
            }
            self.expect_op("}")?;
            Ok(other("FormattedValue", kids))
        })();
        self.leave();
        r
    }
}

/// star_targets: a name, attribute or subscript; a starred target in a
/// list or tuple; or a list or tuple of targets.
pub fn valid_target(n: &Node) -> bool {
    match &n.k {
        K::Name(_) | K::Attribute(_) | K::Subscript => true,
        K::Starred => {
            !n.paren
                && n.kids
                    .first()
                    .map_or(false, |k| !matches!(k.k, K::Starred) && valid_target(k))
        }
        K::Tuple | K::List => n.kids.iter().all(valid_target),
        _ => false,
    }
}

fn valid_del_target(n: &Node) -> bool {
    match &n.k {
        K::Name(_) | K::Attribute(_) | K::Subscript => true,
        K::Tuple | K::List => n.kids.iter().all(valid_del_target),
        _ => false,
    }
}
