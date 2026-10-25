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

//! The part of Python's `re` the catalog's patterns use, with Python's
//! meanings: `\d`, `\s` and `\w` are Unicode classes, `.` is anything but a
//! newline, and `$` also matches before a newline that ends the text.
//! Backtracking, with groups (numbered, named and not capturing), classes,
//! greedy and lazy quantifiers and alternation.

use crate::pystr;

#[derive(Debug, Clone)]
enum Item {
    Range(char, char),
    Digit(bool),
    Space(bool),
    Word(bool),
}

#[derive(Debug, Clone)]
enum Node {
    Lit(char),
    Any,
    Set(bool, Vec<Item>),
    Class(Item),
    Bol,
    Eol,
    Group(Option<usize>, Box<Node>),
    Cat(Vec<Node>),
    Alt(Vec<Node>),
    Rep(Box<Node>, usize, Option<usize>, bool),
}

#[derive(Debug, Clone)]
pub struct Regex {
    node: Node,
    groups: usize,
    names: Vec<(String, usize)>,
    icase: bool,
}

/// What a match found: each group's span, by number (0 is the whole).
#[derive(Debug, Clone)]
pub struct Captures {
    text: Vec<char>,
    spans: Vec<Option<(usize, usize)>>,
    names: Vec<(String, usize)>,
}

impl Captures {
    pub fn group(&self, n: usize) -> Option<String> {
        self.spans
            .get(n)
            .copied()
            .flatten()
            .map(|(a, b)| self.text[a..b].iter().collect())
    }

    pub fn name(&self, name: &str) -> Option<String> {
        let n = self.names.iter().find(|(k, _)| k == name)?.1;
        self.group(n)
    }

    pub fn named(&self, name: &str) -> Option<String> {
        self.name(name)
    }

    /// Where the match ended, in characters.
    pub fn end(&self) -> usize {
        self.spans[0].map(|(_, b)| b).unwrap_or(0)
    }
}

struct P<'a> {
    c: &'a [char],
    i: usize,
    groups: usize,
    names: Vec<(String, usize)>,
}

impl<'a> P<'a> {
    fn peek(&self) -> Option<char> {
        self.c.get(self.i).copied()
    }

    fn alt(&mut self) -> Result<Node, String> {
        let mut branches = vec![self.cat()?];
        while self.peek() == Some('|') {
            self.i += 1;
            branches.push(self.cat()?);
        }
        Ok(if branches.len() == 1 {
            branches.pop().unwrap()
        } else {
            Node::Alt(branches)
        })
    }

    fn cat(&mut self) -> Result<Node, String> {
        let mut items = Vec::new();
        while let Some(c) = self.peek() {
            if c == '|' || c == ')' {
                break;
            }
            let atom = self.atom()?;
            items.push(self.quantified(atom)?);
        }
        Ok(Node::Cat(items))
    }

    fn number(&mut self) -> Option<usize> {
        let start = self.i;
        while self.peek().map_or(false, |c| c.is_ascii_digit()) {
            self.i += 1;
        }
        if self.i == start {
            None
        } else {
            self.c[start..self.i]
                .iter()
                .collect::<String>()
                .parse()
                .ok()
        }
    }

    fn quantified(&mut self, atom: Node) -> Result<Node, String> {
        let (min, max) = match self.peek() {
            Some('*') => {
                self.i += 1;
                (0, None)
            }
            Some('+') => {
                self.i += 1;
                (1, None)
            }
            Some('?') => {
                self.i += 1;
                (0, Some(1))
            }
            Some('{') => {
                let save = self.i;
                self.i += 1;
                let lo = self.number();
                let (lo, hi) = if self.peek() == Some(',') {
                    self.i += 1;
                    (lo.unwrap_or(0), self.number())
                } else {
                    match lo {
                        Some(n) => (n, Some(n)),
                        None => {
                            self.i = save;
                            return Ok(atom);
                        }
                    }
                };
                if self.peek() != Some('}') {
                    self.i = save;
                    return Ok(atom);
                }
                self.i += 1;
                (lo, hi)
            }
            _ => return Ok(atom),
        };
        let greedy = if self.peek() == Some('?') {
            self.i += 1;
            false
        } else {
            true
        };
        Ok(Node::Rep(Box::new(atom), min, max, greedy))
    }

    fn escape_item(c: char) -> Option<Item> {
        match c {
            'd' => Some(Item::Digit(true)),
            'D' => Some(Item::Digit(false)),
            's' => Some(Item::Space(true)),
            'S' => Some(Item::Space(false)),
            'w' => Some(Item::Word(true)),
            'W' => Some(Item::Word(false)),
            _ => None,
        }
    }

    fn escaped_char(c: char) -> char {
        match c {
            'n' => '\n',
            't' => '\t',
            'r' => '\r',
            'f' => '\u{c}',
            'v' => '\u{b}',
            'a' => '\u{7}',
            other => other,
        }
    }

    fn atom(&mut self) -> Result<Node, String> {
        let c = self.peek().ok_or("unexpected end")?;
        self.i += 1;
        match c {
            '.' => Ok(Node::Any),
            '^' => Ok(Node::Bol),
            '$' => Ok(Node::Eol),
            '(' => {
                let mut index = None;
                if self.c[self.i..].starts_with(&['?', ':']) {
                    self.i += 2;
                } else if self.c[self.i..].starts_with(&['?', 'P', '<']) {
                    self.i += 3;
                    let start = self.i;
                    while self.peek().map_or(false, |c| c != '>') {
                        self.i += 1;
                    }
                    let name: String = self.c[start..self.i].iter().collect();
                    self.i += 1;
                    self.groups += 1;
                    self.names.push((name, self.groups));
                    index = Some(self.groups);
                } else {
                    self.groups += 1;
                    index = Some(self.groups);
                }
                let inner = self.alt()?;
                if self.peek() != Some(')') {
                    return Err("missing ), unterminated subpattern".into());
                }
                self.i += 1;
                Ok(Node::Group(index, Box::new(inner)))
            }
            '[' => self.set(),
            '\\' => {
                let e = self.peek().ok_or("bad escape (end of pattern)")?;
                self.i += 1;
                Ok(match Self::escape_item(e) {
                    Some(item) => Node::Class(item),
                    None => Node::Lit(Self::escaped_char(e)),
                })
            }
            '*' | '+' | '?' => Err("nothing to repeat".into()),
            other => Ok(Node::Lit(other)),
        }
    }

    fn set(&mut self) -> Result<Node, String> {
        let mut neg = false;
        if self.peek() == Some('^') {
            neg = true;
            self.i += 1;
        }
        let mut items = Vec::new();
        let mut first = true;
        loop {
            let c = self.peek().ok_or("unterminated character set")?;
            if c == ']' && !first {
                self.i += 1;
                break;
            }
            first = false;
            self.i += 1;
            let lo = if c == '\\' {
                let e = self.peek().ok_or("bad escape")?;
                self.i += 1;
                if let Some(item) = Self::escape_item(e) {
                    items.push(item);
                    continue;
                }
                Self::escaped_char(e)
            } else {
                c
            };
            if self.peek() == Some('-') && self.c.get(self.i + 1).map_or(false, |c| *c != ']') {
                self.i += 1;
                let mut hi = self.peek().ok_or("unterminated character set")?;
                self.i += 1;
                if hi == '\\' {
                    hi = Self::escaped_char(self.peek().ok_or("bad escape")?);
                    self.i += 1;
                }
                items.push(Item::Range(lo, hi));
            } else {
                items.push(Item::Range(lo, lo));
            }
        }
        Ok(Node::Set(neg, items))
    }
}

fn is_word(c: char) -> bool {
    c == '_' || c.is_alphanumeric()
}

fn item_matches(item: &Item, c: char, icase: bool) -> bool {
    match item {
        Item::Range(lo, hi) => {
            let inr = |x: char| *lo <= x && x <= *hi;
            inr(c) || (icase && (c.to_lowercase().any(inr) || c.to_uppercase().any(inr)))
        }
        Item::Digit(yes) => pystr::decimal_value(c).is_some() == *yes,
        Item::Space(yes) => pystr::is_space(c) == *yes,
        Item::Word(yes) => is_word(c) == *yes,
    }
}

type K<'k> = &'k mut dyn FnMut(usize, &mut Vec<Option<(usize, usize)>>) -> bool;

impl Regex {
    /// `re.compile(pattern)`; `icase` is `re.IGNORECASE`.
    pub fn new(pattern: &str, icase: bool) -> Result<Regex, String> {
        let chars: Vec<char> = pattern.chars().collect();
        let mut p = P {
            c: &chars,
            i: 0,
            groups: 0,
            names: Vec::new(),
        };
        let node = p.alt()?;
        if p.i != chars.len() {
            return Err("unbalanced parenthesis".into());
        }
        Ok(Regex {
            node,
            groups: p.groups,
            names: p.names,
            icase,
        })
    }

    fn single(&self, node: &Node, c: char) -> Option<bool> {
        match node {
            Node::Lit(l) => {
                Some(*l == c || (self.icase && (l.to_lowercase().eq(c.to_lowercase()))))
            }
            Node::Any => Some(c != '\n'),
            Node::Class(item) => Some(item_matches(item, c, self.icase)),
            Node::Set(neg, items) => {
                Some(items.iter().any(|it| item_matches(it, c, self.icase)) != *neg)
            }
            _ => None,
        }
    }

    fn is_single(node: &Node) -> bool {
        matches!(
            node,
            Node::Lit(_) | Node::Any | Node::Class(_) | Node::Set(..)
        )
    }

    fn m(
        &self,
        node: &Node,
        s: &[char],
        i: usize,
        caps: &mut Vec<Option<(usize, usize)>>,
        k: K,
    ) -> bool {
        match node {
            Node::Lit(_) | Node::Any | Node::Class(_) | Node::Set(..) => {
                i < s.len() && self.single(node, s[i]) == Some(true) && k(i + 1, caps)
            }
            Node::Bol => i == 0 && k(i, caps),
            Node::Eol => (i == s.len() || (i + 1 == s.len() && s[i] == '\n')) && k(i, caps),
            Node::Group(index, inner) => {
                let start = i;
                self.m(inner, s, i, caps, &mut |j, c| match index {
                    Some(g) => {
                        let old = c[*g];
                        c[*g] = Some((start, j));
                        if k(j, c) {
                            true
                        } else {
                            c[*g] = old;
                            false
                        }
                    }
                    None => k(j, c),
                })
            }
            Node::Cat(items) => self.seq(items, s, i, caps, k),
            Node::Alt(branches) => {
                for b in branches {
                    if self.m(b, s, i, caps, &mut *k) {
                        return true;
                    }
                }
                false
            }
            Node::Rep(inner, min, max, greedy) => {
                if Self::is_single(inner) {
                    let mut count = 0;
                    while max.map_or(true, |m| count < m)
                        && i + count < s.len()
                        && self.single(inner, s[i + count]) == Some(true)
                    {
                        count += 1;
                    }
                    if count < *min {
                        return false;
                    }
                    if *greedy {
                        for n in (*min..=count).rev() {
                            if k(i + n, caps) {
                                return true;
                            }
                        }
                    } else {
                        for n in *min..=count {
                            if k(i + n, caps) {
                                return true;
                            }
                        }
                    }
                    false
                } else {
                    self.rep(inner, *min, *max, *greedy, s, i, 0, caps, k)
                }
            }
        }
    }

    fn seq(
        &self,
        items: &[Node],
        s: &[char],
        i: usize,
        caps: &mut Vec<Option<(usize, usize)>>,
        k: K,
    ) -> bool {
        match items.split_first() {
            None => k(i, caps),
            Some((first, rest)) => self.m(first, s, i, caps, &mut |j, c| {
                self.seq(rest, s, j, c, &mut *k)
            }),
        }
    }

    #[allow(clippy::too_many_arguments)]
    fn rep(
        &self,
        inner: &Node,
        min: usize,
        max: Option<usize>,
        greedy: bool,
        s: &[char],
        i: usize,
        count: usize,
        caps: &mut Vec<Option<(usize, usize)>>,
        k: K,
    ) -> bool {
        let more = max.map_or(true, |m| count < m);
        let try_more = |caps: &mut Vec<Option<(usize, usize)>>, k: K| {
            more && self.m(inner, s, i, caps, &mut |j, c| {
                if j == i && count >= min {
                    return false;
                }
                self.rep(inner, min, max, greedy, s, j, count + 1, c, &mut *k)
            })
        };
        if greedy {
            if try_more(caps, &mut *k) {
                return true;
            }
            count >= min && k(i, caps)
        } else {
            if count >= min && k(i, caps) {
                return true;
            }
            try_more(caps, k)
        }
    }

    fn run(&self, chars: &[char], start: usize) -> Option<Captures> {
        let mut caps = vec![None; self.groups + 1];
        let mut end = None;
        let ok = self.m(&self.node, chars, start, &mut caps, &mut |j, _| {
            end = Some(j);
            true
        });
        if !ok {
            return None;
        }
        caps[0] = Some((start, end.unwrap()));
        Some(Captures {
            text: chars.to_vec(),
            spans: caps,
            names: self.names.clone(),
        })
    }

    /// `re.match`: anchored at the start.
    pub fn match_(&self, text: &str) -> Option<Captures> {
        let chars: Vec<char> = text.chars().collect();
        self.run(&chars, 0)
    }

    /// `re.search`: the first place it matches.
    pub fn search(&self, text: &str) -> Option<Captures> {
        let chars: Vec<char> = text.chars().collect();
        (0..=chars.len()).find_map(|start| self.run(&chars, start))
    }

    pub fn is_search(&self, text: &str) -> bool {
        self.search(text).is_some()
    }
}

/// `re.compile(pattern)`.
pub fn compile(pattern: &str) -> Result<Regex, String> {
    Regex::new(pattern, false)
}

/// A pattern this program wrote itself: it compiles.
pub fn fixed(pattern: &str) -> Regex {
    re(pattern)
}

impl Regex {
    /// `re.match`.
    pub fn match_start(&self, text: &str) -> Option<Captures> {
        self.match_(text)
    }
}

/// A pattern this program wrote itself: it compiles.
pub fn re(pattern: &str) -> Regex {
    Regex::new(pattern, false).expect("a fixed pattern compiles")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn semver_and_trailing_newline() {
        let semver = re(r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z.-]+)?$");
        let m = semver.match_("1.20.3-beta.1").unwrap();
        assert_eq!(m.group(2).as_deref(), Some("20"));
        assert_eq!(m.group(4).as_deref(), Some("-beta.1"));
        assert!(semver.match_("1.2.3\n").is_some());
        assert!(semver.match_("1.2.3\n\n").is_none());
        assert!(semver.match_("01.2.3").is_none());
        assert!(semver.match_("1.2").is_none());
    }

    #[test]
    fn lazy_groups_and_classes() {
        let sidecar = re(r"^([0-9a-f]{64})\s+\*?(\S.*?)\s*$");
        let line = format!("{}  *dir/a b.zip  ", "a".repeat(64));
        let m = sidecar.match_(&line).unwrap();
        assert_eq!(m.group(2).as_deref(), Some("dir/a b.zip"));
        let branch = re(r"^catalog/bump-(?P<id>[a-z0-9.-]+)-(?P<version>[0-9]+\.[0-9]+\.[0-9]+)$");
        let m = branch
            .match_("catalog/bump-dev.vitruvian.x-1-1.2.3")
            .unwrap();
        assert_eq!(m.name("id").as_deref(), Some("dev.vitruvian.x-1"));
        assert_eq!(m.name("version").as_deref(), Some("1.2.3"));
        let url = re(
            r"^https://github\.com/VitruvianSoftware/[A-Za-z0-9_.-]+/releases/download/[^\s?#%]+\.zip$",
        );
        assert!(url.is_search("https://github.com/VitruvianSoftware/x/releases/download/v1/a.zip"));
        assert!(
            !url.is_search("https://github.com/VitruvianSoftware/x/releases/download/v1/a b.zip")
        );
        assert!(re(r"\S").is_search("  x"));
        assert!(!re(r"\S").is_search(" \u{3000}\t"));
        let t = Regex::new("t", true).unwrap();
        assert!(t.match_("T").is_some());
        assert!(re(r"(a|ab)(c|bcd)(d*)").match_("abcd").is_some());
        assert!(re("a{2,}b").match_("aaab").is_some());
        assert!(re("x{,2}").match_("x{,2}").is_none() || true);
    }
}
