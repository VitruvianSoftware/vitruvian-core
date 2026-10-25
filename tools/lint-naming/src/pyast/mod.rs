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

//! What rules/bazel.py asks of `ast.parse(content)` and `ast.walk(tree)`:
//! does the file parse, which calls does a breadth-first walk meet and in
//! what order, what are their `name=` keywords, and which SyntaxWarnings
//! does parsing print.

pub mod lexer;
pub mod parser;
pub mod strings;

use parser::{Node, Parser, K};
use std::collections::VecDeque;

/// A SyntaxWarning `ast.parse` prints.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SyntaxWarning {
    pub line: usize,
    pub message: String,
}

/// One keyword of a call.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct KeywordInfo {
    /// None for `**kwargs`.
    pub arg: Option<String>,
    pub line: usize,
    /// The value, when it is a `str` constant.
    pub str_value: Option<String>,
}

/// One `ast.Call`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CallInfo {
    /// `func.id` for a name, `func.attr` for an attribute, else None.
    pub rule_type: Option<String>,
    pub keywords: Vec<KeywordInfo>,
}

pub struct Parsed {
    /// The calls in `ast.walk` order, or None when `ast.parse` raises.
    pub calls: Option<Vec<CallInfo>>,
    pub warnings: Vec<SyntaxWarning>,
}

fn walk(body: Vec<Node>) -> Vec<CallInfo> {
    let module = Node {
        k: K::Other("Module"),
        kids: body,
        paren: false,
    };
    let mut calls = Vec::new();
    let mut queue: VecDeque<&Node> = VecDeque::new();
    queue.push_back(&module);
    while let Some(n) = queue.pop_front() {
        if n.k == K::Call {
            let rule_type = match n.kids.first().map(|f| &f.k) {
                Some(K::Name(id)) => Some(id.clone()),
                Some(K::Attribute(attr)) => Some(attr.clone()),
                _ => None,
            };
            let keywords = n
                .kids
                .iter()
                .filter_map(|k| match &k.k {
                    K::Keyword { arg, line } => Some(KeywordInfo {
                        arg: arg.clone(),
                        line: *line,
                        str_value: match k.kids.first().map(|v| &v.k) {
                            Some(K::Str(s)) => Some(s.clone()),
                            _ => None,
                        },
                    }),
                    _ => None,
                })
                .collect();
            calls.push(CallInfo {
                rule_type,
                keywords,
            });
        }
        queue.extend(n.kids.iter());
    }
    calls
}

/// `ast.parse(content)`, as far as the linter can tell.
pub fn parse(content: &str) -> Parsed {
    // "source code string cannot contain null bytes"
    if content.contains('\0') {
        return Parsed {
            calls: None,
            warnings: Vec::new(),
        };
    }
    let chars = source_chars(content);
    let lexed = lexer::tokenize(&chars);
    let mut p = Parser::new(&lexed.tokens);
    let result = p.file();
    let to_warning = |w: &lexer::Warn| SyntaxWarning {
        line: w.line,
        message: w.message.clone(),
    };
    match result {
        Ok(body) if !lexed.error => Parsed {
            calls: Some(walk(body)),
            warnings: lexed.warnings.iter().map(to_warning).collect(),
        },
        _ => {
            // The parser read up to `furthest`: strings before it were
            // decoded (and warned about), tokens up to it were fetched.
            // Then, unless it stopped on an indent or dedent (an
            // IndentationError, Parser/pegen_errors.c), CPython tokenizes the
            // rest of the file looking for a tokenizer error, which raises
            // the tokenizer's own warnings.
            let furthest = p.furthest;
            let on_indent = matches!(
                lexed.tokens.get(furthest).map(|t| t.kind),
                Some(lexer::Kind::Indent) | Some(lexer::Kind::Dedent)
            ) && p.missing_indent_at != Some(furthest);
            let extra = second_pass_strings(&lexed.tokens, &p.disjunctions, furthest);
            Parsed {
                calls: None,
                warnings: lexed
                    .warnings
                    .iter()
                    .filter(|w| {
                        if w.from_tokenizer {
                            !on_indent || w.token <= furthest
                        } else {
                            w.token < furthest
                                || extra.map_or(false, |(a, b)| a <= w.token && w.token < b)
                        }
                    })
                    .map(to_warning)
                    .collect(),
            }
        }
    }
}

/// CPython's second, error-reporting pass tries `invalid_expression` at each
/// expression: `!(NAME STRING | SOFT_KEYWORD) disjunction
/// expression_without_invalid`, and the `_without_invalid` rule turns
/// warnings back on. So when an expression's disjunction ends exactly where
/// parsing failed, the strings of the expression read after it are decoded,
/// and warned about, too. Returns that range of token indices.
fn second_pass_strings(
    toks: &[lexer::Token],
    disjunctions: &[(usize, usize)],
    furthest: usize,
) -> Option<(usize, usize)> {
    let soft = |t: &lexer::Token| {
        t.kind == lexer::Kind::Name && ["_", "case", "match", "type"].contains(&t.text.as_str())
    };
    let eligible = disjunctions
        .iter()
        .filter(|&&(s, e)| e == furthest && s < e)
        .any(|&(s, _)| {
            let first = &toks[s];
            let name_string = first.kind == lexer::Kind::Name
                && !parser::is_keyword(&first.text)
                && toks
                    .get(s + 1)
                    .map_or(false, |t| t.kind == lexer::Kind::Str);
            !name_string && !soft(first)
        });
    if !eligible || furthest >= toks.len() {
        return None;
    }
    let end = Parser::probe_expression(toks, furthest);
    Some((furthest, end))
}

/// The source as CPython's string tokenizer reads it (translate_newlines):
/// `\r\n` and `\r` become `\n`, and a final newline is added.
fn source_chars(content: &str) -> Vec<char> {
    let mut chars: Vec<char> = Vec::with_capacity(content.len() + 1);
    let mut it = content.chars().peekable();
    while let Some(c) = it.next() {
        if c == '\r' {
            if it.peek() == Some(&'\n') {
                it.next();
            }
            chars.push('\n');
        } else {
            chars.push(c);
        }
    }
    if chars.last() != Some(&'\n') {
        chars.push('\n');
    }
    chars
}

/// Where parsing stops, for debugging the port: the line and kind of the
/// furthest token read, and whether the tokenizer itself failed.
pub fn failure_point(content: &str) -> Option<(usize, String, bool)> {
    let chars = source_chars(content);
    let lexed = lexer::tokenize(&chars);
    let mut p = Parser::new(&lexed.tokens);
    if p.file().is_ok() && !lexed.error {
        return None;
    }
    let t = lexed.tokens.get(p.furthest);
    Some((
        t.map(|t| t.line).unwrap_or(0),
        t.map(|t| format!("{:?} {:?}", t.kind, t.text))
            .unwrap_or_else(|| "<end>".into()),
        lexed.error,
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn calls(
        src: &str,
    ) -> Option<Vec<(Option<String>, Vec<(Option<String>, usize, Option<String>)>)>> {
        parse(src).calls.map(|cs| {
            cs.into_iter()
                .map(|c| {
                    (
                        c.rule_type,
                        c.keywords
                            .into_iter()
                            .map(|k| (k.arg, k.line, k.str_value))
                            .collect(),
                    )
                })
                .collect()
        })
    }

    fn s(x: &str) -> Option<String> {
        Some(x.to_string())
    }

    #[test]
    fn breadth_first_order() {
        let got = calls("a(b(name='x'))\nc(name='y')\n").unwrap();
        assert_eq!(got[0].0, s("a"));
        assert_eq!(got[1].0, s("c"));
        assert_eq!(got[2].0, s("b"));
        assert_eq!(got[2].1, [(s("name"), 1, s("x"))]);
    }

    #[test]
    fn keyword_values() {
        let got = calls("f(name = 'a' 'b', other=1, **kw)\n").unwrap();
        assert_eq!(got[0].1[0], (s("name"), 1, s("ab")));
        assert_eq!(got[0].1[1].2, None);
        assert_eq!(got[0].1[2].0, None);
        let got = calls("f(name=f'a')\n").unwrap();
        assert_eq!(got[0].1[0].2, None, "an f-string is not a str constant");
        let got = calls("f(name=b'a')\n").unwrap();
        assert_eq!(got[0].1[0].2, None);
    }

    #[test]
    fn syntax_errors() {
        for bad in [
            "f(a=1, b)\n",
            "f(**a, *b)\n",
            "x = = 1\n",
            "f() = 1\n",
            "def f(a=1, b): pass\n",
            "if x:\npass\n",
            "x = (\n",
            "a, b += 1\n",
            "x := 1\n",
            "\"a\" b\"b\"\n",
            "print 'x'\n",
        ] {
            assert!(calls(bad).is_none(), "{:?}", bad);
        }
        for good in [
            "f(a=1, *b)\n",
            "f(a, a=1, a=2)\n",
            "return 1\n",
            "x = [i for i in range(3) if i]\n",
            "with (open(a) as f, open(b) as g):\n    pass\n",
            "lambda *a, b=1, **k: 0\n",
            "def f[T](x: T, /, *, y=1) -> T: ...\n",
            "type X = int\n",
            "x = f'{a!r:>{w}}'\n",
            "@d(name='x')\nclass A(B, metaclass=M):\n    pass\n",
            "try:\n    pass\nexcept* E as e:\n    pass\n",
            "a[1:2, ::3, *b]\n",
            "del a, b[1], c.d\n",
            "from . import (a, b as c,)\n",
        ] {
            assert!(calls(good).is_some(), "{:?}", good);
        }
    }

    #[test]
    fn warnings_on_failure() {
        let p = parse("x = 1if 1 else 2\ny = = 1\nz = 1if 1 else 2\n");
        assert!(p.calls.is_none());
        assert_eq!(
            p.warnings.iter().map(|w| w.line).collect::<Vec<_>>(),
            [1, 3]
        );
        let p = parse("y = = 1\nz = \"\\d\"\n");
        assert!(p.warnings.is_empty());
        let p = parse("x = \"\\d\"\ny = (\n");
        assert_eq!(p.warnings.len(), 1);
    }

    #[test]
    fn null_bytes_do_not_parse() {
        assert!(parse("x = 1\0\n").calls.is_none());
    }
}
