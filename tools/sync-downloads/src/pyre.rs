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

//! Just enough of Python's `re` for sync_downloads.py: the patterns it
//! writes (literals, `.`, `\s`, `\d`, `[\s\S]`, `[^\n]`, `[^"]`, capturing
//! and non-capturing groups, `*` `+` `?` and their lazy forms, an optional
//! group) matched the way Python's backtracking engine matches them, on code
//! points; and `re.sub`'s replacement templates, errors included.
//!
//! A quantifier applies to one character class or to a group that holds only
//! a fixed sequence; that covers every pattern the script uses, and the
//! patterns are fixed, so `compile` panics on anything else.

use crate::pystr;

#[derive(Clone, Copy, Debug, PartialEq)]
enum Class {
    Char(char),
    Any,      // [\s\S]
    NotNl,    // . and [^\n]
    NotQuote, // [^"]
    Space,    // \s
    Digit,    // \d
}

impl Class {
    fn matches(self, c: char) -> bool {
        match self {
            Class::Char(x) => c == x,
            Class::Any => true,
            Class::NotNl => c != '\n',
            Class::NotQuote => c != '"',
            Class::Space => pystr::is_space(c),
            Class::Digit => pystr::decimal_value(c).is_some(),
        }
    }
}

#[derive(Clone, Debug)]
enum Node {
    /// A class repeated min..=max times (max None: unbounded).
    Rep {
        class: Class,
        min: usize,
        max: Option<usize>,
        greedy: bool,
    },
    Open(usize),
    Close(usize),
    /// `(?:...)?` or `(...)?` (greedy): the inner nodes, matched once or not.
    Optional(Vec<Node>),
}

#[derive(Clone, Debug)]
pub struct Regex {
    nodes: Vec<Node>,
    pub groups: usize,
}

/// Where a match starts and ends, and each group's span (None if the group
/// did not take part), all in code points.
#[derive(Clone, Debug, PartialEq)]
pub struct Match {
    pub start: usize,
    pub end: usize,
    pub spans: Vec<Option<(usize, usize)>>,
}

pub fn compile(pattern: &str) -> Regex {
    let chars: Vec<char> = pattern.chars().collect();
    let mut i = 0;
    let mut groups = 0;
    let nodes = parse_seq(&chars, &mut i, &mut groups);
    assert!(i == chars.len(), "unsupported pattern {:?}", pattern);
    Regex { nodes, groups }
}

fn parse_seq(p: &[char], i: &mut usize, groups: &mut usize) -> Vec<Node> {
    let mut nodes = Vec::new();
    while *i < p.len() && p[*i] != ')' {
        if p[*i] == '(' {
            *i += 1;
            let capture = if p[*i..].starts_with(&['?', ':']) {
                *i += 2;
                None
            } else {
                *groups += 1;
                Some(*groups)
            };
            let inner = parse_seq(p, i, groups);
            assert!(p[*i] == ')', "unbalanced group");
            *i += 1;
            let mut body = Vec::new();
            if let Some(n) = capture {
                body.push(Node::Open(n));
            }
            body.extend(inner);
            if let Some(n) = capture {
                body.push(Node::Close(n));
            }
            if *i < p.len() && p[*i] == '?' {
                *i += 1;
                assert!(!(*i < p.len() && p[*i] == '?'), "lazy optional group");
                nodes.push(Node::Optional(body));
            } else {
                assert!(
                    !(*i < p.len() && matches!(p[*i], '*' | '+')),
                    "repeated group"
                );
                nodes.extend(body);
            }
            continue;
        }
        let class = if p[*i] == '\\' {
            *i += 1;
            let c = p[*i];
            *i += 1;
            match c {
                's' => Class::Space,
                'd' => Class::Digit,
                'n' => Class::Char('\n'),
                '.' | '\\' | '(' | ')' | '[' | ']' | '-' | '/' => Class::Char(c),
                _ => panic!("unsupported escape \\{}", c),
            }
        } else if p[*i] == '[' {
            let rest: String = p[*i..].iter().collect();
            let (class, len) = if rest.starts_with("[\\s\\S]") {
                (Class::Any, 6)
            } else if rest.starts_with("[^\\n]") {
                (Class::NotNl, 5)
            } else if rest.starts_with("[^\"]") {
                (Class::NotQuote, 4)
            } else {
                panic!("unsupported class {}", rest)
            };
            *i += len;
            class
        } else if p[*i] == '.' {
            *i += 1;
            Class::NotNl
        } else {
            let c = p[*i];
            assert!(
                !matches!(c, '*' | '+' | '?' | '{' | '|' | '^' | '$'),
                "unsupported {}",
                c
            );
            *i += 1;
            Class::Char(c)
        };
        let (min, max) = match p.get(*i) {
            Some('*') => (0, None),
            Some('+') => (1, None),
            Some('?') => (0, Some(1)),
            _ => (1, Some(1)),
        };
        let mut greedy = true;
        if (min, max) != (1, Some(1)) {
            *i += 1;
            if p.get(*i) == Some(&'?') {
                *i += 1;
                greedy = false;
            }
        }
        nodes.push(Node::Rep {
            class,
            min,
            max,
            greedy,
        });
    }
    nodes
}

struct Matcher<'a> {
    s: &'a [char],
    spans: Vec<Option<(usize, usize)>>,
    open: Vec<usize>,
}

impl<'a> Matcher<'a> {
    /// Match `nodes[k..]` then `rest` (a continuation stack) at `pos`.
    fn run(
        &mut self,
        nodes: &[Node],
        k: usize,
        pos: usize,
        rest: &[(&[Node], usize)],
    ) -> Option<usize> {
        if k == nodes.len() {
            return match rest.split_last() {
                None => Some(pos),
                Some((&(n, kk), more)) => self.run(n, kk, pos, more),
            };
        }
        match &nodes[k] {
            Node::Open(g) => {
                let saved = self.open[*g];
                self.open[*g] = pos;
                let r = self.run(nodes, k + 1, pos, rest);
                if r.is_none() {
                    self.open[*g] = saved;
                }
                r
            }
            Node::Close(g) => {
                let saved = self.spans[*g];
                self.spans[*g] = Some((self.open[*g], pos));
                let r = self.run(nodes, k + 1, pos, rest);
                if r.is_none() {
                    self.spans[*g] = saved;
                }
                r
            }
            Node::Optional(body) => {
                let mut more: Vec<(&[Node], usize)> = rest.to_vec();
                more.push((nodes, k + 1));
                if let Some(r) = self.run(body, 0, pos, &more) {
                    return Some(r);
                }
                self.run(nodes, k + 1, pos, rest)
            }
            Node::Rep {
                class,
                min,
                max,
                greedy,
            } => {
                // How far the class can run from here, up to max.
                let limit = max.unwrap_or(usize::MAX);
                let mut n = 0;
                while n < limit && pos + n < self.s.len() && class.matches(self.s[pos + n]) {
                    n += 1;
                }
                if n < *min {
                    return None;
                }
                if *greedy {
                    let mut take = n;
                    loop {
                        if let Some(r) = self.run(nodes, k + 1, pos + take, rest) {
                            return Some(r);
                        }
                        if take == *min {
                            return None;
                        }
                        take -= 1;
                    }
                } else {
                    for take in *min..=n {
                        if let Some(r) = self.run(nodes, k + 1, pos + take, rest) {
                            return Some(r);
                        }
                    }
                    None
                }
            }
        }
    }
}

impl Regex {
    /// `re.search` on a string already split into code points.
    pub fn search(&self, s: &[char]) -> Option<Match> {
        for start in 0..=s.len() {
            let mut m = Matcher {
                s,
                spans: vec![None; self.groups + 1],
                open: vec![0; self.groups + 1],
            };
            if let Some(end) = m.run(&self.nodes, 0, start, &[]) {
                let mut spans = m.spans;
                spans[0] = Some((start, end));
                return Some(Match { start, end, spans });
            }
        }
        None
    }
}

/// The exception `re.sub` raises for a bad template: the class, then the
/// message.
#[derive(Debug, PartialEq)]
pub struct TemplateError {
    pub class: &'static str,
    pub msg: String,
}

#[derive(Debug, PartialEq)]
enum Piece {
    Lit(String),
    Group(usize),
}

/// `re._parser.parse_template` for a pattern with `groups` groups.
fn parse_template(t: &str, groups: usize) -> Result<Vec<Piece>, TemplateError> {
    let err = |msg: String| TemplateError {
        class: "re.error",
        msg,
    };
    let c: Vec<char> = t.chars().collect();
    let mut out = Vec::new();
    let mut lit = String::new();
    let mut i = 0;
    let oct = |ch: Option<&char>| matches!(ch, Some('0'..='7'));
    let dig = |ch: Option<&char>| matches!(ch, Some('0'..='9'));
    while i < c.len() {
        if c[i] != '\\' {
            lit.push(c[i]);
            i += 1;
            continue;
        }
        if i + 1 >= c.len() {
            return Err(err(format!(
                "bad escape (end of pattern) at position {}",
                i
            )));
        }
        let e = c[i + 1];
        let at = i;
        i += 2;
        let group = |index: usize, lit: &mut String, out: &mut Vec<Piece>| {
            if index > groups {
                return Err(err(format!(
                    "invalid group reference {} at position {}",
                    index,
                    at + 1
                )));
            }
            if !lit.is_empty() {
                out.push(Piece::Lit(std::mem::take(lit)));
            }
            out.push(Piece::Group(index));
            Ok(())
        };
        match e {
            'g' => {
                if c.get(i) != Some(&'<') {
                    return Err(err(format!("missing < at position {}", i)));
                }
                i += 1;
                let mut name = String::new();
                loop {
                    match c.get(i) {
                        None => {
                            return Err(err(if name.is_empty() {
                                format!("missing group name at position {}", i)
                            } else {
                                format!(
                                    "missing >, unterminated name at position {}",
                                    i - name.chars().count()
                                )
                            }))
                        }
                        Some('>') => {
                            i += 1;
                            if name.is_empty() {
                                return Err(err(format!(
                                    "missing group name at position {}",
                                    i - 1
                                )));
                            }
                            break;
                        }
                        Some(&ch) => {
                            name.push(ch);
                            i += 1;
                        }
                    }
                }
                if name.chars().all(|ch| ch.is_ascii_digit()) {
                    let index = name.trim_start_matches('0').parse::<usize>().unwrap_or(
                        if name.trim_start_matches('0').is_empty() {
                            0
                        } else {
                            usize::MAX
                        },
                    );
                    group(index, &mut lit, &mut out)?;
                } else {
                    let mut it = name.chars();
                    let first = it.next().unwrap();
                    let ident = (first == '_' || first.is_alphabetic())
                        && it.all(|ch| ch == '_' || ch.is_alphanumeric());
                    if !ident {
                        return Err(err(format!(
                            "bad character in group name {}",
                            pystr::repr_str(&name)
                        )));
                    }
                    return Err(TemplateError {
                        class: "IndexError",
                        msg: format!("unknown group name {}", pystr::repr_str(&name)),
                    });
                }
            }
            '0' => {
                let mut v = 0u32;
                let mut n = 0;
                while n < 2 && oct(c.get(i)) {
                    v = v * 8 + c[i].to_digit(8).unwrap();
                    i += 1;
                    n += 1;
                }
                lit.push(char::from_u32(v & 0xff).unwrap());
            }
            '1'..='9' => {
                let mut digits = e.to_string();
                let mut octal = false;
                if dig(c.get(i)) {
                    digits.push(c[i]);
                    i += 1;
                    if oct(Some(&e)) && oct(digits.chars().nth(1).as_ref()) && oct(c.get(i)) {
                        digits.push(c[i]);
                        i += 1;
                        octal = true;
                        let v = u32::from_str_radix(&digits, 8).unwrap();
                        if v > 0o377 {
                            return Err(err(format!(
                                "octal escape value \\{} outside of range 0-0o377 at position {}",
                                digits, at
                            )));
                        }
                        lit.push(char::from_u32(v).unwrap());
                    }
                }
                if !octal {
                    group(digits.parse().unwrap(), &mut lit, &mut out)?;
                }
            }
            'a' => lit.push('\u{7}'),
            'b' => lit.push('\u{8}'),
            'f' => lit.push('\u{c}'),
            'n' => lit.push('\n'),
            'r' => lit.push('\r'),
            't' => lit.push('\t'),
            'v' => lit.push('\u{b}'),
            '\\' => lit.push('\\'),
            e if e.is_ascii_alphabetic() => {
                return Err(err(format!("bad escape \\{} at position {}", e, at)));
            }
            e => {
                lit.push('\\');
                lit.push(e);
            }
        }
    }
    if !lit.is_empty() {
        out.push(Piece::Lit(lit));
    }
    Ok(out)
}

/// `re.sub(pattern, template, s, count=1)`.
pub fn sub1(re: &Regex, template: &str, s: &str) -> Result<String, TemplateError> {
    // Python compiles the template before it looks for a match.
    let pieces = if template.contains('\\') {
        parse_template(template, re.groups)?
    } else {
        vec![Piece::Lit(template.to_string())]
    };
    let chars: Vec<char> = s.chars().collect();
    let m = match re.search(&chars) {
        None => return Ok(s.to_string()),
        Some(m) => m,
    };
    let mut out: String = chars[..m.start].iter().collect();
    for piece in &pieces {
        match piece {
            Piece::Lit(l) => out.push_str(l),
            Piece::Group(g) => {
                if let Some((a, b)) = m.spans[*g] {
                    out.extend(&chars[a..b]);
                }
            }
        }
    }
    out.extend(&chars[m.end..]);
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn search(p: &str, s: &str) -> Option<(usize, usize)> {
        let chars: Vec<char> = s.chars().collect();
        compile(p).search(&chars).map(|m| (m.start, m.end))
    }

    #[test]
    fn lazy_and_greedy() {
        assert_eq!(search(r"a[\s\S]*?b", "xxaqbqb"), Some((2, 5)));
        assert_eq!(search(r"a[\s\S]*b", "xxaqbqb"), Some((2, 7)));
        assert_eq!(
            search(r#"v:\s*"[^"]+(")"#, "v: \"\" v: \"1\""),
            Some((6, 12))
        );
        assert_eq!(search(r"x[^\n]+y", "x\ny"), None);
        assert_eq!(search(r"\d+", "ab\u{0663}4"), Some((2, 4)));
    }

    #[test]
    fn optional_group() {
        let re = compile(r"(\d+)\.(\d+)(?:\.(\d+))?");
        let chars: Vec<char> = "v1.2.".chars().collect();
        let m = re.search(&chars).unwrap();
        assert_eq!((m.start, m.end), (1, 4));
        assert_eq!(m.spans[3], None);
        let chars: Vec<char> = "v1.2.3".chars().collect();
        assert_eq!(re.search(&chars).unwrap().spans[3], Some((5, 6)));
    }

    #[test]
    fn substitution() {
        let re = compile(r#"(id:\s*devx[\s\S]*?version:\s*")[^"]+(")"#);
        let s = "- id: devx\n  version: \"1.0\"\n- id: other\n  version: \"2\"\n";
        assert_eq!(
            sub1(&re, "\\g<1>9.9\\g<2>", s).unwrap(),
            "- id: devx\n  version: \"9.9\"\n- id: other\n  version: \"2\"\n"
        );
        assert_eq!(
            sub1(&re, "\\g<1>a\\nb\\2", s).unwrap().lines().nth(1),
            Some("  version: \"a")
        );
        assert_eq!(
            sub1(&re, "\\1\\101\\2", s).unwrap().lines().nth(1),
            Some("  version: \"A\"")
        );
        assert_eq!(
            sub1(&re, "\\g<3>", "nothing").unwrap_err().class,
            "re.error"
        );
        assert_eq!(sub1(&re, "\\q", s).unwrap_err().class, "re.error");
        assert_eq!(sub1(&re, "\\g<name>", s).unwrap_err().class, "IndexError");
        assert_eq!(sub1(&re, "\\", s).unwrap_err().class, "re.error");
        // An escape that is not a letter stays as written.
        assert!(sub1(&re, "\\%", s)
            .unwrap()
            .starts_with("- \\%\n- id: other"));
    }
}
