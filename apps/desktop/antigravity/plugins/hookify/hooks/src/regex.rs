// Copyright (c) 2026 VitruvianSoftware
//
// SPDX-License-Identifier: MIT

//! JavaScript regular expressions, as `new RegExp(pattern, "" | "i" | "g")`
//! reads them, without the `u` flag.
//!
//! Hookify rules are regexes their authors tested in JavaScript, and the hook
//! used to run them with Node.js. This engine keeps that meaning without a
//! crate: it works on UTF-16 code units (as JavaScript does without `u`),
//! follows the web-compatibility grammar (Annex B: `\8`, `{`, `]`, legacy
//! octal escapes, `\c` fallbacks) and supports groups, named groups,
//! backreferences, lookahead and lookbehind, and greedy and lazy quantifiers.
//!
//! One deliberate difference: a match that backtracks for more than
//! [`STEP_LIMIT`] steps is abandoned and reported as no match, where
//! JavaScript would hang until the hook's timeout.

pub const STEP_LIMIT: usize = 5_000_000;

/// A pattern JavaScript would reject with a `SyntaxError`.
#[derive(Debug, Clone, PartialEq)]
pub struct SyntaxError(pub &'static str);

#[derive(Debug, Clone)]
enum ClassItem {
    Range(u16, u16),
    Set(u8), // b'd', b'D', b's', b'S', b'w', b'W'
}

#[derive(Debug, Clone)]
enum Node {
    Empty,
    Char(u16),
    Any,
    Class {
        negated: bool,
        items: Vec<ClassItem>,
    },
    Set(u8),
    Start,
    End,
    WordBoundary(bool),
    Group(Box<Node>, Option<usize>),
    Look {
        node: Box<Node>,
        behind: bool,
        negated: bool,
    },
    /// Several groups when a name is reused in different alternatives;
    /// the first that took part is used.
    Backref(Vec<usize>),
    Concat(Vec<Node>),
    Alt(Vec<Node>),
    Repeat {
        node: Box<Node>,
        min: usize,
        max: Option<usize>,
        greedy: bool,
    },
}

/// A compiled pattern.
#[derive(Debug, Clone)]
pub struct Regex {
    root: Node,
    groups: usize,
    names: Vec<(Vec<u16>, usize)>,
    ignore_case: bool,
}

const fn u(c: char) -> u16 {
    c as u16
}

fn is_digit(c: u16) -> bool {
    (u('0')..=u('9')).contains(&c)
}

fn hex_value(c: u16) -> Option<u16> {
    match c {
        0x30..=0x39 => Some(c - 0x30),
        0x41..=0x46 => Some(c - 0x41 + 10),
        0x61..=0x66 => Some(c - 0x61 + 10),
        _ => None,
    }
}

fn is_word(c: u16) -> bool {
    c == u('_') || (c < 128 && (c as u8).is_ascii_alphanumeric())
}

/// `\s`: WhiteSpace and LineTerminator.
fn is_space(c: u16) -> bool {
    matches!(
        c,
        0x09..=0x0d | 0x20 | 0xa0 | 0x1680 | 0x2000..=0x200a | 0x2028 | 0x2029 | 0x202f | 0x205f
            | 0x3000 | 0xfeff
    )
}

fn in_set(kind: u8, c: u16) -> bool {
    match kind {
        b'd' => is_digit(c),
        b'D' => !is_digit(c),
        b's' => is_space(c),
        b'S' => !is_space(c),
        b'w' => is_word(c),
        b'W' => !is_word(c),
        _ => false,
    }
}

/// Canonicalize for `i` without `u`: the single-unit upper case, unless that
/// would map a non-ASCII unit onto ASCII.
fn canon(c: u16) -> u16 {
    if c < 128 {
        return (c as u8).to_ascii_uppercase() as u16;
    }
    let Some(ch) = char::from_u32(c as u32) else {
        return c;
    };
    let mut up = ch.to_uppercase();
    match (up.next(), up.next()) {
        (Some(single), None) if (single as u32) <= 0xffff && (single as u32) >= 128 => {
            single as u16
        }
        _ => c,
    }
}

fn units(s: &str) -> Vec<u16> {
    s.encode_utf16().collect()
}

/// Group count and names, read before parsing so `\N` and `\k` can be told
/// apart from escapes.
fn prescan(p: &[u16]) -> (usize, Vec<(Vec<u16>, usize)>) {
    let mut count = 0;
    let mut names = Vec::new();
    let mut i = 0;
    let mut in_class = false;
    while i < p.len() {
        let c = p[i];
        if c == u('\\') {
            i += 2;
            continue;
        }
        if in_class {
            if c == u(']') {
                in_class = false;
            }
        } else if c == u('[') {
            in_class = true;
        } else if c == u('(') {
            if p.get(i + 1) != Some(&u('?')) {
                count += 1;
            } else if p.get(i + 2) == Some(&u('<'))
                && !matches!(p.get(i + 3), Some(&x) if x == u('=') || x == u('!'))
            {
                count += 1;
                let start = i + 3;
                let mut end = start;
                while end < p.len() && p[end] != u('>') {
                    end += 1;
                }
                names.push((p[start..end].to_vec(), count));
            }
        }
        i += 1;
    }
    (count, names)
}

struct Parser<'a> {
    p: &'a [u16],
    pos: usize,
    groups: usize,
    names: &'a [(Vec<u16>, usize)],
    next_group: usize,
    /// Where each named group sits: `(disjunction id, alternative)` from the
    /// root. A name may repeat only in different alternatives (ES2025).
    declared: Vec<(Vec<u16>, Vec<(usize, usize)>)>,
    path: Vec<(usize, usize)>,
    disjunctions: usize,
}

type Res<T> = Result<T, SyntaxError>;

impl Parser<'_> {
    fn peek(&self) -> Option<u16> {
        self.p.get(self.pos).copied()
    }

    fn peek_at(&self, off: usize) -> Option<u16> {
        self.p.get(self.pos + off).copied()
    }

    fn eat(&mut self, c: char) -> bool {
        if self.peek() == Some(u(c)) {
            self.pos += 1;
            true
        } else {
            false
        }
    }

    fn disjunction(&mut self) -> Res<Node> {
        self.disjunctions += 1;
        let id = self.disjunctions;
        self.path.push((id, 0));
        let mut alts = vec![self.alternative()?];
        while self.eat('|') {
            self.path.last_mut().unwrap().1 += 1;
            alts.push(self.alternative()?);
        }
        self.path.pop();
        Ok(if alts.len() == 1 {
            alts.pop().unwrap()
        } else {
            Node::Alt(alts)
        })
    }

    fn alternative(&mut self) -> Res<Node> {
        let mut terms = Vec::new();
        while let Some(c) = self.peek() {
            if c == u('|') || c == u(')') {
                break;
            }
            terms.push(self.term()?);
        }
        Ok(match terms.len() {
            0 => Node::Empty,
            1 => terms.pop().unwrap(),
            _ => Node::Concat(terms),
        })
    }

    /// Reads `{n}`, `{n,}` or `{n,m}` at the cursor without consuming it.
    fn braced_quantifier(&self) -> Option<(usize, Option<usize>, usize)> {
        let mut i = self.pos + 1;
        let read = |i: &mut usize| -> Option<usize> {
            let start = *i;
            let mut n: usize = 0;
            while let Some(&c) = self.p.get(*i) {
                if !is_digit(c) {
                    break;
                }
                n = n.saturating_mul(10).saturating_add((c - u('0')) as usize);
                *i += 1;
            }
            (*i > start).then_some(n)
        };
        let min = read(&mut i)?;
        let max = if self.p.get(i) == Some(&u(',')) {
            i += 1;
            if self.p.get(i) == Some(&u('}')) {
                None
            } else {
                Some(read(&mut i)?)
            }
        } else {
            Some(min)
        };
        (self.p.get(i) == Some(&u('}'))).then_some((min, max, i + 1 - self.pos))
    }

    fn quantifier(&mut self) -> Res<Option<(usize, Option<usize>, bool)>> {
        let (min, max) = match self.peek() {
            Some(c) if c == u('*') => {
                self.pos += 1;
                (0, None)
            }
            Some(c) if c == u('+') => {
                self.pos += 1;
                (1, None)
            }
            Some(c) if c == u('?') => {
                self.pos += 1;
                (0, Some(1))
            }
            Some(c) if c == u('{') => match self.braced_quantifier() {
                Some((min, max, len)) => {
                    self.pos += len;
                    if matches!(max, Some(m) if m < min) {
                        return Err(SyntaxError("numbers out of order in {} quantifier"));
                    }
                    (min, max)
                }
                None => return Ok(None),
            },
            _ => return Ok(None),
        };
        let greedy = !self.eat('?');
        Ok(Some((min, max, greedy)))
    }

    fn term(&mut self) -> Res<Node> {
        let c = self.peek().unwrap();
        // Assertions that cannot be quantified.
        let assertion = if c == u('^') {
            self.pos += 1;
            Some(Node::Start)
        } else if c == u('$') {
            self.pos += 1;
            Some(Node::End)
        } else if c == u('\\') && matches!(self.peek_at(1), Some(x) if x == u('b') || x == u('B')) {
            let b = self.peek_at(1) == Some(u('b'));
            self.pos += 2;
            Some(Node::WordBoundary(b))
        } else if c == u('(')
            && self.peek_at(1) == Some(u('?'))
            && self.peek_at(2) == Some(u('<'))
            && matches!(self.peek_at(3), Some(x) if x == u('=') || x == u('!'))
        {
            let negated = self.peek_at(3) == Some(u('!'));
            self.pos += 4;
            let node = self.disjunction()?;
            if !self.eat(')') {
                return Err(SyntaxError("unterminated group"));
            }
            Some(Node::Look {
                node: Box::new(node),
                behind: true,
                negated,
            })
        } else {
            None
        };
        if let Some(a) = assertion {
            if self.quantifier()?.is_some() {
                return Err(SyntaxError("nothing to repeat"));
            }
            return Ok(a);
        }

        let atom = self.atom()?;
        Ok(match self.quantifier()? {
            Some((min, max, greedy)) => Node::Repeat {
                node: Box::new(atom),
                min,
                max,
                greedy,
            },
            None => atom,
        })
    }

    fn atom(&mut self) -> Res<Node> {
        let c = self.peek().unwrap();
        self.pos += 1;
        match c {
            x if x == u('.') => Ok(Node::Any),
            x if x == u('(') => {
                let capture = if self.eat('?') {
                    if self.eat(':') {
                        None
                    } else if self.eat('=') || self.peek() == Some(u('!')) {
                        let negated = self.eat('!');
                        let node = self.disjunction()?;
                        if !self.eat(')') {
                            return Err(SyntaxError("unterminated group"));
                        }
                        return Ok(Node::Look {
                            node: Box::new(node),
                            behind: false,
                            negated,
                        });
                    } else if self.eat('<') {
                        let start = self.pos;
                        while self.peek().is_some_and(|x| x != u('>')) {
                            self.pos += 1;
                        }
                        let name = &self.p[start..self.pos];
                        if !self.eat('>') || !valid_group_name(name) {
                            return Err(SyntaxError("invalid capture group name"));
                        }
                        let clash = self.declared.iter().any(|(n, other)| {
                            n == name
                                && !other
                                    .iter()
                                    .zip(&self.path)
                                    .take_while(|(a, b)| a.0 == b.0)
                                    .any(|(a, b)| a.1 != b.1)
                        });
                        if clash {
                            return Err(SyntaxError("duplicate capture group name"));
                        }
                        self.declared.push((name.to_vec(), self.path.clone()));
                        self.next_group += 1;
                        Some(self.next_group)
                    } else {
                        return Err(SyntaxError("invalid group"));
                    }
                } else {
                    self.next_group += 1;
                    Some(self.next_group)
                };
                let node = self.disjunction()?;
                if !self.eat(')') {
                    return Err(SyntaxError("unterminated group"));
                }
                Ok(Node::Group(Box::new(node), capture))
            }
            x if x == u(')') => Err(SyntaxError("unmatched )")),
            x if x == u('*') || x == u('+') || x == u('?') => Err(SyntaxError("nothing to repeat")),
            x if x == u('{') => {
                self.pos -= 1;
                if self.braced_quantifier().is_some() {
                    return Err(SyntaxError("nothing to repeat"));
                }
                self.pos += 1;
                Ok(Node::Char(x))
            }
            x if x == u('[') => self.class(),
            x if x == u('\\') => self.atom_escape(),
            x => Ok(Node::Char(x)),
        }
    }

    /// `\c`, `\x`, `\u`, `\0`, legacy octal and control escapes shared by
    /// atoms and classes. `None` means "not one of these".
    fn character_escape(&mut self, c: u16, in_class: bool) -> Option<u16> {
        match c {
            x if x == u('f') => Some(0x0c),
            x if x == u('n') => Some(0x0a),
            x if x == u('r') => Some(0x0d),
            x if x == u('t') => Some(0x09),
            x if x == u('v') => Some(0x0b),
            x if x == u('c') => {
                let next = self.peek()?;
                let ok = (next < 128 && (next as u8).is_ascii_alphabetic())
                    || (in_class && (is_digit(next) || next == u('_')));
                if ok {
                    self.pos += 1;
                    Some(next % 32)
                } else {
                    // `\c` without a letter is a backslash; the `c` is
                    // read again as a literal.
                    self.pos -= 1;
                    Some(u('\\'))
                }
            }
            x if x == u('x') => {
                let h = (
                    self.peek().and_then(hex_value),
                    self.peek_at(1).and_then(hex_value),
                );
                if let (Some(a), Some(b)) = h {
                    self.pos += 2;
                    Some(a * 16 + b)
                } else {
                    Some(u('x'))
                }
            }
            x if x == u('u') => {
                let mut v = 0u16;
                for k in 0..4 {
                    match self.peek_at(k).and_then(hex_value) {
                        Some(d) => v = v * 16 + d,
                        None => return Some(u('u')),
                    }
                }
                self.pos += 4;
                Some(v)
            }
            x if (u('0')..=u('7')).contains(&x) => {
                // Legacy octal: up to three digits, at most 0o377.
                let mut v = x - u('0');
                let max_digits = if x <= u('3') { 3 } else { 2 };
                for _ in 1..max_digits {
                    match self.peek() {
                        Some(d) if (u('0')..=u('7')).contains(&d) => {
                            v = v * 8 + (d - u('0'));
                            self.pos += 1;
                        }
                        _ => break,
                    }
                }
                Some(v)
            }
            _ => None,
        }
    }

    fn atom_escape(&mut self) -> Res<Node> {
        let Some(c) = self.peek() else {
            return Err(SyntaxError("\\ at end of pattern"));
        };
        self.pos += 1;
        if let Some(set) = set_escape(c) {
            return Ok(Node::Set(set));
        }
        if (u('1')..=u('9')).contains(&c) {
            let start = self.pos - 1;
            let mut n: usize = (c - u('0')) as usize;
            while let Some(d) = self.peek().filter(|d| is_digit(*d)) {
                n = n.saturating_mul(10).saturating_add((d - u('0')) as usize);
                self.pos += 1;
            }
            if n <= self.groups {
                return Ok(Node::Backref(vec![n]));
            }
            self.pos = start + 1;
            if c >= u('8') {
                return Ok(Node::Char(c));
            }
        }
        if c == u('0') && !self.peek().is_some_and(is_digit) {
            return Ok(Node::Char(0));
        }
        if c == u('k') && !self.names.is_empty() {
            if !self.eat('<') {
                return Err(SyntaxError("invalid named reference"));
            }
            let start = self.pos;
            while self.peek().is_some_and(|x| x != u('>')) {
                self.pos += 1;
            }
            let name = self.p[start..self.pos].to_vec();
            if !self.eat('>') {
                return Err(SyntaxError("invalid named reference"));
            }
            let groups: Vec<usize> = self
                .names
                .iter()
                .filter(|(n, _)| *n == name)
                .map(|(_, idx)| *idx)
                .collect();
            if groups.is_empty() {
                return Err(SyntaxError("invalid named capture referenced"));
            }
            return Ok(Node::Backref(groups));
        }
        if let Some(v) = self.character_escape(c, false) {
            return Ok(Node::Char(v));
        }
        Ok(Node::Char(c))
    }

    fn class_atom(&mut self) -> Res<ClassItem> {
        let c = self
            .peek()
            .ok_or(SyntaxError("unterminated character class"))?;
        self.pos += 1;
        if c != u('\\') {
            return Ok(ClassItem::Range(c, c));
        }
        let Some(e) = self.peek() else {
            return Err(SyntaxError("\\ at end of pattern"));
        };
        self.pos += 1;
        if let Some(set) = set_escape(e) {
            return Ok(ClassItem::Set(set));
        }
        let v = if e == u('b') {
            0x08
        } else if e == u('-') {
            u('-')
        } else if e == u('8') || e == u('9') {
            e
        } else if let Some(v) = self.character_escape(e, true) {
            v
        } else {
            e
        };
        Ok(ClassItem::Range(v, v))
    }

    fn class(&mut self) -> Res<Node> {
        let negated = self.eat('^');
        let mut items = Vec::new();
        loop {
            match self.peek() {
                None => return Err(SyntaxError("unterminated character class")),
                Some(c) if c == u(']') => {
                    self.pos += 1;
                    return Ok(Node::Class { negated, items });
                }
                _ => {}
            }
            let a = self.class_atom()?;
            if self.peek() == Some(u('-')) && self.peek_at(1).is_some_and(|x| x != u(']')) {
                self.pos += 1;
                let b = self.class_atom()?;
                match (&a, &b) {
                    (ClassItem::Range(lo, _), ClassItem::Range(hi, _)) => {
                        if lo > hi {
                            return Err(SyntaxError("range out of order in character class"));
                        }
                        items.push(ClassItem::Range(*lo, *hi));
                    }
                    // A set at either end makes the dash a literal.
                    _ => {
                        items.push(a);
                        items.push(ClassItem::Range(u('-'), u('-')));
                        items.push(b);
                    }
                }
            } else {
                items.push(a);
            }
        }
    }
}

fn set_escape(c: u16) -> Option<u8> {
    [b'd', b'D', b's', b'S', b'w', b'W']
        .into_iter()
        .find(|k| *k as u16 == c)
}

fn valid_group_name(name: &[u16]) -> bool {
    let Ok(s) = String::from_utf16(name) else {
        return false;
    };
    let mut chars = s.chars();
    let Some(first) = chars.next() else {
        return false;
    };
    (first.is_alphabetic() || first == '$' || first == '_')
        && chars.all(|c| {
            c.is_alphanumeric() || c == '$' || c == '_' || c == '\u{200c}' || c == '\u{200d}'
        })
}

impl Regex {
    /// `new RegExp(pattern, ignore_case ? "i" : "")`.
    pub fn new(pattern: &str, ignore_case: bool) -> Result<Regex, SyntaxError> {
        let p = units(pattern);
        let (groups, names) = prescan(&p);
        let mut parser = Parser {
            p: &p,
            pos: 0,
            groups,
            names: &names,
            next_group: 0,
            declared: Vec::new(),
            path: Vec::new(),
            disjunctions: 0,
        };
        let root = parser.disjunction()?;
        if parser.pos != p.len() {
            return Err(SyntaxError("unmatched )"));
        }
        Ok(Regex {
            root,
            groups,
            names,
            ignore_case,
        })
    }

    /// `re.test(text)`.
    pub fn test(&self, text: &str) -> bool {
        let t = units(text);
        self.find_at(&t, 0).is_some()
    }

    /// The first match starting at or after `from`: `(start, end, captures)`.
    fn find_at(
        &self,
        t: &[u16],
        from: usize,
    ) -> Option<(usize, usize, Vec<Option<(usize, usize)>>)> {
        let mut m = Matcher {
            re: self,
            t,
            caps: vec![None; self.groups + 1],
            steps: 0,
        };
        for start in from..=t.len() {
            m.caps.iter_mut().for_each(|c| *c = None);
            let mut end = None;
            if m.node(&self.root, start, &mut |_, j| {
                end = Some(j);
                true
            }) {
                return Some((start, end.unwrap(), m.caps.clone()));
            }
            if m.steps > STEP_LIMIT {
                return None;
            }
        }
        None
    }

    /// `text.replace(new RegExp(pattern, "g"), replacement)`: every match,
    /// with `$&`, `$1`, `$<name>` and friends expanded.
    pub fn replace_all(&self, text: &str, replacement: &str) -> String {
        let t = units(text);
        let r = units(replacement);
        let mut out: Vec<u16> = Vec::new();
        let mut last = 0;
        let mut from = 0;
        while from <= t.len() {
            let Some((start, end, caps)) = self.find_at(&t, from) else {
                break;
            };
            out.extend_from_slice(&t[last..start]);
            substitute(&mut out, &r, &t, start, end, &caps[1..], &self.names);
            last = end;
            from = if end == start { end + 1 } else { end };
        }
        out.extend_from_slice(&t[last.min(t.len())..]);
        String::from_utf16_lossy(&out)
    }
}

/// `text.replaceAll(find, replacement)` with a plain string `find`.
pub fn replace_all_literal(text: &str, find: &str, replacement: &str) -> String {
    let t = units(text);
    let f = units(find);
    let r = units(replacement);
    let advance = f.len().max(1);
    let mut positions = Vec::new();
    let mut i = 0;
    while i + f.len() <= t.len() {
        if t[i..i + f.len()] == f[..] {
            positions.push(i);
            i += advance;
        } else {
            i += 1;
        }
    }
    let mut out = Vec::new();
    let mut last = 0;
    for p in positions {
        out.extend_from_slice(&t[last..p]);
        substitute(&mut out, &r, &t, p, p + f.len(), &[], &[]);
        last = p + f.len();
    }
    out.extend_from_slice(&t[last..]);
    String::from_utf16_lossy(&out)
}

/// GetSubstitution: expands `$$ $& $\` $' $n $nn $<name>` in `r`.
fn substitute(
    out: &mut Vec<u16>,
    r: &[u16],
    t: &[u16],
    start: usize,
    end: usize,
    caps: &[Option<(usize, usize)>],
    names: &[(Vec<u16>, usize)],
) {
    let m = caps.len();
    let cap = |out: &mut Vec<u16>, n: usize| {
        if let Some(Some((a, b))) = caps.get(n - 1) {
            out.extend_from_slice(&t[*a..*b]);
        }
    };
    let mut i = 0;
    while i < r.len() {
        let c = r[i];
        if c != u('$') || i + 1 >= r.len() {
            out.push(c);
            i += 1;
            continue;
        }
        let n = r[i + 1];
        if n == u('$') {
            out.push(u('$'));
            i += 2;
        } else if n == u('&') {
            out.extend_from_slice(&t[start..end]);
            i += 2;
        } else if n == u('`') {
            out.extend_from_slice(&t[..start]);
            i += 2;
        } else if n == u('\'') {
            out.extend_from_slice(&t[end..]);
            i += 2;
        } else if is_digit(n) {
            let d1 = (n - u('0')) as usize;
            let two = r
                .get(i + 2)
                .filter(|d| is_digit(**d))
                .map(|d| d1 * 10 + (*d - u('0')) as usize);
            match two {
                Some(nn) if nn >= 1 && nn <= m => {
                    cap(out, nn);
                    i += 3;
                }
                _ if d1 >= 1 && d1 <= m => {
                    cap(out, d1);
                    i += 2;
                }
                _ => {
                    out.extend_from_slice(&r[i..i + 2]);
                    i += 2;
                }
            }
        } else if n == u('<') && !names.is_empty() {
            match r[i + 2..].iter().position(|x| *x == u('>')) {
                Some(rel) => {
                    let name = &r[i + 2..i + 2 + rel];
                    // A reused name: whichever of its groups took part.
                    if let Some((_, idx)) = names
                        .iter()
                        .filter(|(nm, _)| nm == name)
                        .find(|(_, idx)| matches!(caps.get(idx - 1), Some(Some(_))))
                    {
                        cap(out, *idx);
                    }
                    i += 3 + rel;
                }
                None => {
                    out.extend_from_slice(&r[i..i + 2]);
                    i += 2;
                }
            }
        } else {
            out.push(c);
            i += 1;
        }
    }
}

type Cont<'k, 'a> = dyn FnMut(&mut Matcher<'a>, usize) -> bool + 'k;

struct Matcher<'a> {
    re: &'a Regex,
    t: &'a [u16],
    caps: Vec<Option<(usize, usize)>>,
    steps: usize,
}

impl<'a> Matcher<'a> {
    fn eq(&self, a: u16, b: u16) -> bool {
        a == b || (self.re.ignore_case && canon(a) == canon(b))
    }

    fn class_has(&self, items: &[ClassItem], c: u16) -> bool {
        let direct = |c: u16| {
            items.iter().any(|it| match it {
                ClassItem::Range(lo, hi) => (*lo..=*hi).contains(&c),
                ClassItem::Set(k) => in_set(*k, c),
            })
        };
        if direct(c) {
            return true;
        }
        if !self.re.ignore_case {
            return false;
        }
        // Any member with the same canonical form: the upper case itself,
        // or a lower case that canonicalizes back to it.
        let cc = canon(c);
        let in_ranges = |x: u16| {
            items
                .iter()
                .any(|it| matches!(it, ClassItem::Range(lo, hi) if (*lo..=*hi).contains(&x)))
        };
        if in_ranges(cc) {
            return true;
        }
        if let Some(ch) = char::from_u32(cc as u32) {
            for low in ch.to_lowercase() {
                let l = low as u32;
                if l <= 0xffff && canon(l as u16) == cc && in_ranges(l as u16) {
                    return true;
                }
            }
        }
        false
    }

    /// Whether `node` matches one unit at `i` (for the fast repeat path).
    fn single(&self, node: &Node, i: usize) -> Option<bool> {
        let c = self.t.get(i).copied();
        Some(match node {
            Node::Char(x) => c.is_some_and(|c| self.eq(c, *x)),
            Node::Any => c.is_some_and(|c| !matches!(c, 0x0a | 0x0d | 0x2028 | 0x2029)),
            Node::Set(k) => c.is_some_and(|c| in_set(*k, c)),
            Node::Class { negated, items } => {
                c.is_some_and(|c| self.class_has(items, c) != *negated)
            }
            _ => return None,
        })
    }

    fn node(&mut self, n: &'a Node, i: usize, k: &mut Cont<'_, 'a>) -> bool {
        self.steps += 1;
        if self.steps > STEP_LIMIT {
            return false;
        }
        match n {
            Node::Empty => k(self, i),
            Node::Char(_) | Node::Any | Node::Set(_) | Node::Class { .. } => {
                self.single(n, i) == Some(true) && k(self, i + 1)
            }
            Node::Start => i == 0 && k(self, i),
            Node::End => i == self.t.len() && k(self, i),
            Node::WordBoundary(want) => {
                let before = i > 0 && is_word(self.t[i - 1]);
                let after = i < self.t.len() && is_word(self.t[i]);
                ((before != after) == *want) && k(self, i)
            }
            Node::Group(inner, None) => self.node(inner, i, k),
            Node::Group(inner, Some(idx)) => {
                let idx = *idx;
                let saved = self.caps[idx];
                let ok = self.node(inner, i, &mut |s, j| {
                    let prev = s.caps[idx];
                    s.caps[idx] = Some((i, j));
                    if k(s, j) {
                        return true;
                    }
                    s.caps[idx] = prev;
                    false
                });
                if !ok {
                    self.caps[idx] = saved;
                }
                ok
            }
            Node::Look {
                node,
                behind,
                negated,
            } => {
                let saved = self.caps.clone();
                let found = if *behind {
                    (0..=i)
                        .rev()
                        .any(|start| self.node(node, start, &mut |_, j| j == i))
                } else {
                    self.node(node, i, &mut |_, _| true)
                };
                if found == *negated {
                    self.caps = saved;
                    return false;
                }
                if *negated {
                    self.caps = saved.clone();
                }
                if k(self, i) {
                    return true;
                }
                self.caps = saved;
                false
            }
            Node::Backref(idxs) => match idxs
                .iter()
                .find_map(|i| self.caps.get(*i).copied().flatten())
            {
                None => k(self, i),
                Some((a, b)) => {
                    let len = b - a;
                    if i + len > self.t.len() {
                        return false;
                    }
                    let same = (0..len).all(|o| self.eq(self.t[a + o], self.t[i + o]));
                    same && k(self, i + len)
                }
            },
            Node::Concat(v) => self.seq(v, 0, i, k),
            Node::Alt(v) => {
                for a in v {
                    if self.node(a, i, k) {
                        return true;
                    }
                }
                false
            }
            Node::Repeat {
                node,
                min,
                max,
                greedy,
            } => {
                if self.single(node, i).is_some() {
                    // One unit per iteration: walk the run without recursion,
                    // so `.*` over a long file cannot exhaust the stack.
                    let cap = max.unwrap_or(usize::MAX);
                    let mut run = 0;
                    while run < cap && self.single(node, i + run) == Some(true) {
                        run += 1;
                    }
                    if run < *min {
                        return false;
                    }
                    if *greedy {
                        for j in (*min..=run).rev() {
                            if k(self, i + j) {
                                return true;
                            }
                            if self.steps > STEP_LIMIT {
                                return false;
                            }
                        }
                    } else {
                        for j in *min..=run {
                            if k(self, i + j) {
                                return true;
                            }
                            if self.steps > STEP_LIMIT {
                                return false;
                            }
                        }
                    }
                    return false;
                }
                self.repeat(node, *min, *max, *greedy, 0, i, k)
            }
        }
    }

    fn seq(&mut self, v: &'a [Node], idx: usize, i: usize, k: &mut Cont<'_, 'a>) -> bool {
        if idx == v.len() {
            return k(self, i);
        }
        self.node(&v[idx], i, &mut |s, j| s.seq(v, idx + 1, j, k))
    }

    #[allow(clippy::too_many_arguments)]
    fn repeat(
        &mut self,
        node: &'a Node,
        min: usize,
        max: Option<usize>,
        greedy: bool,
        count: usize,
        i: usize,
        k: &mut Cont<'_, 'a>,
    ) -> bool {
        let can_more = max.map_or(true, |m| count < m);
        let more = |s: &mut Self, k: &mut Cont<'_, 'a>| {
            can_more
                && s.node(node, i, &mut |s, j| {
                    // An iteration past the minimum must consume something.
                    if j == i && count >= min {
                        return false;
                    }
                    s.repeat(node, min, max, greedy, count + 1, j, k)
                })
        };
        if count < min {
            return more(self, k);
        }
        if greedy {
            more(self, k) || k(self, i)
        } else {
            k(self, i) || more(self, k)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn t(p: &str, s: &str) -> bool {
        Regex::new(p, false).unwrap().test(s)
    }

    #[test]
    fn backtracks_into_groups() {
        // The old engine kept a group's first way of matching.
        assert!(t("(a|ab)c", "abc"));
        assert!(t("(a+)ab", "aaab"));
        assert!(t("^(ab)*abc$", "abababc"));
    }

    #[test]
    fn lazy_quantifiers_lookaround_and_backrefs() {
        assert!(t("--force(?!-with-lease)", "git push --force origin"));
        assert!(!t("--force(?!-with-lease)", "git push --force-with-lease"));
        assert!(t("(?<=git )push", "git push"));
        assert!(!t("(?<!git )push", "git push"));
        assert!(t("^a.*?b$", "axxb"));
        assert!(t("(\\w)\\1", "xaay"));
        assert!(t("(?<q>['\"]).*\\k<q>", "say 'hi'"));
    }

    #[test]
    fn escapes_follow_annex_b() {
        assert!(t("\\x41\\u0042", "AB"));
        assert!(t("\\f\\v\\0", "\u{c}\u{b}\0"));
        assert!(t("^\\8$", "8"));
        assert!(t("^\\101$", "A")); // octal, no group 101
        assert!(t("^\\cJ$", "\n"));
        assert!(t("^\\c$", "\\c"));
        assert!(t("^a{,2}$", "a{,2}"));
        assert!(t("^]$", "]"));
        assert!(t("^[\\d-z]+$", "1-z"));
        assert!(!t("[]", "anything"));
        assert!(t("^[^]$", "\n"));
    }

    #[test]
    fn a_name_may_repeat_in_different_alternatives() {
        let re = Regex::new("(?<n>x)|(?<n>y)", false).unwrap();
        assert!(re.test("y"));
        assert_eq!(re.replace_all("xy", "[$<n>]"), "[x][y]");
        assert!(t("^(?:(?<n>a)|(?<n>b))\\k<n>$", "bb"));
        assert!(Regex::new("(?<n>a)(?<n>b)", false).is_err());
        assert!(Regex::new("(?<n>a)|(?:x|(?<n>b))", false).is_ok());
        assert!(Regex::new("(?:(?<n>a)|b)(?<n>c)", false).is_err());
    }

    #[test]
    fn rejects_what_javascript_rejects() {
        for p in [
            "(",
            ")",
            "a**",
            "*a",
            "[b-a]",
            "a{2,1}",
            "^*",
            "(?<n>a)(?<n>b)",
            "\\",
            "(?x)",
            "\\k<n>(?<m>a)",
        ] {
            assert!(
                Regex::new(p, false).is_err(),
                "{p:?} should be a SyntaxError"
            );
        }
    }

    #[test]
    fn ignore_case_and_utf16_units() {
        let re = Regex::new("^é[a-c]$", true).unwrap();
        assert!(re.test("ÉB"));
        // Without `u`, `.` is one UTF-16 unit: an emoji is two.
        assert!(!t("^.$", "😀"));
        assert!(t("^..$", "😀"));
        // `\s` is JavaScript's set: NBSP and BOM yes, NEL no.
        assert!(t("^\\s\\s$", "\u{a0}\u{feff}"));
        assert!(!t("^\\s$", "\u{85}"));
    }

    #[test]
    fn replaces_like_string_prototype_replace() {
        let re = Regex::new("x*", false).unwrap();
        assert_eq!(re.replace_all("abc", "-"), "-a-b-c-");
        let re = Regex::new("(\\w+)@(?<host>\\w+)", false).unwrap();
        assert_eq!(
            re.replace_all("me@home", "$2:$1 $<host> $& $$ $3 $0"),
            "home:me home me@home $ $3 $0"
        );
        assert_eq!(replace_all_literal("a.b.c", ".", "[$&]"), "a[.]b[.]c");
        assert_eq!(replace_all_literal("ab", "", "-"), "-a-b-");
    }

    #[test]
    fn long_inputs_do_not_exhaust_the_stack_and_runaways_stop() {
        let big = "a".repeat(200_000);
        assert!(t("^a.*a$", &big));
        let evil = format!("{}!", "a".repeat(40));
        assert!(!t("^(a+)+$", &evil));
    }
}
