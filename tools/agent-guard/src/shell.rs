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

//! Shell parsing: a small tokenizer that understands enough of sh/bash/zsh to
//! find every simple command: operators, quotes, $(...), backticks, process
//! substitution, subshells, braces, heredocs and redirections.
//!
//! A port of agent_guard.py's parser, index for index: it works on characters
//! (Python's string indices), and every regex there is a scanner here.

use std::collections::VecDeque;

use crate::pyutil::{cs, find_char, is_decimal, is_space, py_split_ws, starts_at, str_isdigit};

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct SimpleCommand {
    pub words: Vec<String>,
    pub redirects: Vec<(String, String)>,
    pub heredocs: Vec<String>,
    pub herestrings: Vec<String>,
}

impl SimpleCommand {
    fn nonempty(&self) -> bool {
        !(self.words.is_empty()
            && self.redirects.is_empty()
            && self.heredocs.is_empty()
            && self.herestrings.is_empty())
    }
}

#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub enum PErr {
    /// ParseError: unbalanced quotes and the like.
    Parse,
    /// TooComplex: more commands than the guard will check in time.
    TooComplex,
}

/// The most simple commands (plus nested parses) one tool call may contain.
pub const MAX_COMMANDS: i64 = 20000;

pub fn spend(budget: &mut i64) -> Result<(), PErr> {
    *budget -= 1;
    if *budget < 0 {
        Err(PErr::TooComplex)
    } else {
        Ok(())
    }
}

const KEYWORDS_DROP: [&str; 13] = [
    "then", "do", "else", "elif", "if", "while", "until", "!", "{", "}", "fi", "done", "esac",
];

/// `_HEREDOC_DELIM_RE.match(text, pos)`:
/// `-?[ \t]*(?:'([^'\n]*)'|"([^"\n]*)"|\\?([^\s;|&<>()'"]+))` -> (delimiter, end).
fn heredoc_delim(t: &[char], pos: usize) -> Option<(String, usize)> {
    fn delim_class(c: char) -> bool {
        !(is_space(c) || ";|&<>()'\"".contains(c))
    }
    fn after_dash(t: &[char], mut q: usize) -> Option<(String, usize)> {
        while q < t.len() && (t[q] == ' ' || t[q] == '\t') {
            q += 1;
        }
        let c = *t.get(q)?;
        if c == '\'' || c == '"' {
            let mut j = q + 1;
            while j < t.len() && t[j] != c && t[j] != '\n' {
                j += 1;
            }
            if j < t.len() && t[j] == c {
                return Some((cs(&t[q + 1..j]), j + 1));
            }
            return None;
        }
        let run = |from: usize| {
            let mut j = from;
            while j < t.len() && delim_class(t[j]) {
                j += 1;
            }
            j
        };
        if c == '\\' {
            let j = run(q + 1);
            if j > q + 1 {
                return Some((cs(&t[q + 1..j]), j));
            }
        }
        let j = run(q);
        if j > q {
            return Some((cs(&t[q..j]), j));
        }
        None
    }
    if t.get(pos) == Some(&'-') {
        if let Some(r) = after_dash(t, pos + 1) {
            return Some(r);
        }
    }
    after_dash(t, pos)
}

/// If a heredoc operator (<< or <<-, not <<<) starts at i: (delimiter, strip tabs, end).
pub fn heredoc_at(t: &[char], i: usize) -> Option<(String, bool, usize)> {
    if !starts_at(t, i, "<<") || starts_at(t, i, "<<<") {
        return None;
    }
    let (delim, end) = heredoc_delim(t, i + 2)?;
    if str_isdigit(&delim) {
        return None; // $(( 1 << 2 )): a shift, not a heredoc
    }
    Some((delim, t.get(i + 2) == Some(&'-'), end))
}

fn line_matches(line: &[char], strip_tabs: bool, delim: &[char]) -> bool {
    let mut l = line;
    if strip_tabs {
        let k = l.iter().take_while(|&&c| c == '\t').count();
        l = &l[k..];
    }
    l == delim
}

/// pos is just after a newline: skip each pending heredoc body and its delimiter line.
fn skip_heredoc_bodies(
    t: &[char],
    mut pos: usize,
    pending: &mut VecDeque<(Vec<char>, bool)>,
) -> usize {
    let n = t.len();
    while let Some((delim, strip_tabs)) = pending.pop_front() {
        while pos < n {
            let nl = find_char(t, '\n', pos);
            let line = match nl {
                Some(e) => &t[pos..e],
                None => &t[pos..],
            };
            pos = match nl {
                Some(e) => e + 1,
                None => n,
            };
            if line_matches(line, strip_tabs, &delim) {
                break;
            }
        }
    }
    pos
}

fn run_end(t: &[char], i: usize, stop: impl Fn(char) -> bool) -> usize {
    let mut j = i;
    while j < t.len() && !stop(t[j]) {
        j += 1;
    }
    j
}

fn word_run(t: &[char], i: usize) -> usize {
    run_end(t, i, |c| is_space(c) || "'\"\\$`<>&|;()".contains(c))
}

fn dq_run(t: &[char], i: usize) -> usize {
    run_end(t, i, |c| "\"\\$`".contains(c))
}

fn ansi_run(t: &[char], i: usize) -> usize {
    run_end(t, i, |c| c == '\'' || c == '\\')
}

fn match_run(t: &[char], i: usize) -> usize {
    run_end(t, i, |c| "\\\n<#'\"`(){}".contains(c))
}

/// Index of the close char matching t[start-1]==open, quote and heredoc aware.
pub fn find_matching(t: &[char], start: usize, open: char, close: char) -> Result<usize, PErr> {
    let mut depth = 1;
    let mut i = start;
    let n = t.len();
    let mut pending: VecDeque<(Vec<char>, bool)> = VecDeque::new();
    while i < n {
        let m = match_run(t, i);
        if m > i {
            i = m;
            if i >= n {
                break;
            }
        }
        let c = t[i];
        if c == '\\' {
            i += 2;
            continue;
        }
        if c == '\n' && !pending.is_empty() {
            i = skip_heredoc_bodies(t, i + 1, &mut pending);
            continue;
        }
        if c == '<' {
            if let Some((d, strip, end)) = heredoc_at(t, i) {
                pending.push_back((d.chars().collect(), strip));
                i = end;
                continue;
            }
        }
        if c == '#' && (i == start || " \t\n;(|&".contains(t[i - 1])) {
            i = find_char(t, '\n', i).unwrap_or(n);
            continue;
        }
        if c == '\'' {
            match find_char(t, '\'', i + 1) {
                Some(j) => {
                    i = j + 1;
                    continue;
                }
                None => return Err(PErr::Parse),
            }
        }
        if c == '"' {
            i = skip_double(t, i + 1)?;
            continue;
        }
        if c == '`' {
            i = find_backtick(t, i + 1)? + 1;
            continue;
        }
        if c == open {
            depth += 1;
        } else if c == close {
            depth -= 1;
            if depth == 0 {
                return Ok(i);
            }
        }
        i += 1;
    }
    Err(PErr::Parse)
}

fn skip_double(t: &[char], mut i: usize) -> Result<usize, PErr> {
    let n = t.len();
    while i < n {
        let m = dq_run(t, i);
        if m > i {
            i = m;
            if i >= n {
                break;
            }
        }
        let c = t[i];
        if c == '\\' {
            i += 2;
            continue;
        }
        if c == '"' {
            return Ok(i + 1);
        }
        if c == '$' && i + 1 < n && t[i + 1] == '(' {
            i = find_matching(t, i + 2, '(', ')')? + 1;
            continue;
        }
        if c == '`' {
            i = find_backtick(t, i + 1)? + 1;
            continue;
        }
        i += 1;
    }
    Err(PErr::Parse)
}

fn find_backtick(t: &[char], mut i: usize) -> Result<usize, PErr> {
    while i < t.len() {
        match t[i..].iter().position(|&c| c == '\\' || c == '`') {
            None => break,
            Some(p) => {
                let at = i + p;
                if t[at] == '\\' {
                    i = at + 2;
                    continue;
                }
                return Ok(at);
            }
        }
    }
    Err(PErr::Parse)
}

fn ansi_escape(c: char) -> char {
    match c {
        'n' => '\n',
        't' => '\t',
        'r' => '\r',
        'a' => '\x07',
        'e' => '\x1b',
        '0' => '\0',
        other => other, // \\ \' \" and anything else: the character itself
    }
}

/// The $(...) and `...` commands an UNQUOTED heredoc body would run.
pub fn body_substitutions(body: &[char]) -> Vec<Vec<char>> {
    let mut out = Vec::new();
    let mut i = 0;
    let n = body.len();
    while i < n {
        let found = (i..n).find(|&k| {
            body[k] == '\\' || body[k] == '`' || (body[k] == '$' && k + 1 < n && body[k + 1] == '(')
        });
        let Some(at) = found else { break };
        i = at;
        let c = body[i];
        if c == '\\' {
            i += 2;
            continue;
        }
        if starts_at(body, i, "$((") {
            match find_matching(body, i + 3, '(', ')') {
                Ok(k) => {
                    i = k + 2;
                    continue;
                }
                Err(_) => break,
            }
        }
        if starts_at(body, i, "$(") {
            match find_matching(body, i + 2, '(', ')') {
                Ok(k) => {
                    out.push(body[i + 2..k].to_vec());
                    i = k + 1;
                    continue;
                }
                Err(_) => break,
            }
        }
        if c == '`' {
            match find_backtick(body, i + 1) {
                Ok(k) => {
                    out.push(body[i + 1..k].to_vec());
                    i = k + 1;
                    continue;
                }
                Err(_) => break,
            }
        }
        i += 1;
    }
    out
}

struct PendingHeredoc {
    delim: Vec<char>,
    strip_tabs: bool,
    owner: usize,
    literal: bool,
}

struct Parser<'a> {
    t: &'a [char],
    depth: usize,
    arena: Vec<SimpleCommand>,
    commands: Vec<usize>,
    nested: Vec<SimpleCommand>,
    cur: usize,
    word: String,
    in_word: bool,
    quoted: bool,
    pending_redirect: Option<&'static str>,
    pending_heredocs: VecDeque<PendingHeredoc>,
}

impl<'a> Parser<'a> {
    fn end_word(&mut self) {
        if !self.in_word {
            return;
        }
        let w = std::mem::take(&mut self.word);
        if let Some(op) = self.pending_redirect.take() {
            if op == "<<" || op == "<<-" {
                // A quoted delimiter ('EOF', "EOF", \EOF) makes the body
                // literal; an unquoted one lets the shell run $(...) in it.
                self.pending_heredocs.push_back(PendingHeredoc {
                    delim: w.chars().collect(),
                    strip_tabs: op == "<<-",
                    owner: self.cur,
                    literal: self.quoted,
                });
            } else if op == "<<<" {
                self.arena[self.cur].herestrings.push(w);
            } else {
                self.arena[self.cur].redirects.push((op.to_string(), w));
            }
        } else {
            self.arena[self.cur].words.push(w);
        }
        self.in_word = false;
        self.quoted = false;
    }

    fn end_command(&mut self, budget: &mut i64) -> Result<(), PErr> {
        self.end_word();
        if self.arena[self.cur].nonempty() {
            spend(budget)?;
            self.commands.push(self.cur);
        }
        self.arena.push(SimpleCommand::default());
        self.cur = self.arena.len() - 1;
        Ok(())
    }

    /// Called right after a newline: consume the bodies of pending heredocs.
    fn read_heredocs(&mut self, mut pos: usize, budget: &mut i64) -> Result<usize, PErr> {
        let t = self.t;
        let n = t.len();
        while let Some(h) = self.pending_heredocs.pop_front() {
            let mut lines: Vec<&[char]> = Vec::new();
            while pos <= n {
                let nl = find_char(t, '\n', pos);
                let line = match nl {
                    Some(e) => &t[pos..e],
                    None => &t[pos.min(n)..],
                };
                pos = match nl {
                    Some(e) => e + 1,
                    None => n + 1,
                };
                if line_matches(line, h.strip_tabs, &h.delim) {
                    break;
                }
                lines.push(line);
                if nl.is_none() {
                    break;
                }
            }
            let mut body: Vec<char> = Vec::new();
            for (k, l) in lines.iter().enumerate() {
                if k > 0 {
                    body.push('\n');
                }
                body.extend_from_slice(l);
            }
            self.arena[h.owner].heredocs.push(cs(&body));
            if !h.literal {
                // Each distinct command once.
                let mut seen: Vec<Vec<char>> = Vec::new();
                for sub in body_substitutions(&body) {
                    if seen.contains(&sub) {
                        continue;
                    }
                    seen.push(sub.clone());
                    match parse_script_at(&sub, self.depth + 1, budget) {
                        Ok(cmds) => self.nested.extend(cmds),
                        Err(PErr::Parse) => {
                            self.nested.extend(fallback_split(&cs(&sub), Some(budget))?)
                        }
                        Err(e) => return Err(e),
                    }
                }
            }
        }
        Ok(pos.min(n))
    }
}

/// `_OPERATOR_RE.match`: `&&|\|\||;;|\|&|[;|&\n()]`.
fn operator_at(t: &[char], i: usize) -> Option<usize> {
    for op in ["&&", "||", ";;", "|&"] {
        if starts_at(t, i, op) {
            return Some(i + 2);
        }
    }
    if i < t.len() && ";|&\n()".contains(t[i]) {
        return Some(i + 1);
    }
    None
}

/// `_OPERATOR_RUN.match`: `(?:[();| \t]|&(?!>))+`.
fn operator_run(t: &[char], i: usize) -> Option<usize> {
    let mut j = i;
    while j < t.len() {
        let c = t[j];
        if "();| \t".contains(c) || (c == '&' && t.get(j + 1) != Some(&'>')) {
            j += 1;
        } else {
            break;
        }
    }
    if j > i {
        Some(j)
    } else {
        None
    }
}

/// `_FD_DUP.match`: `\d+-?|-`.
fn fd_dup(t: &[char], i: usize) -> Option<usize> {
    let mut j = i;
    while j < t.len() && is_decimal(t[j]) {
        j += 1;
    }
    if j > i {
        if t.get(j) == Some(&'-') {
            j += 1;
        }
        return Some(j);
    }
    if t.get(i) == Some(&'-') {
        return Some(i + 1);
    }
    None
}

/// `re.match(r"^[A-Za-z_][A-Za-z0-9_]*\(\)$", w)`: a function definition.
fn is_funcdef(w: &str) -> bool {
    let t: Vec<char> = w.chars().collect();
    match t.first() {
        Some(c) if c.is_ascii_alphabetic() || *c == '_' => {}
        _ => return false,
    }
    let mut i = 1;
    while i < t.len() && (t[i].is_ascii_alphanumeric() || t[i] == '_') {
        i += 1;
    }
    starts_at(&t, i, "()") && crate::pyutil::dollar(&t, i + 2)
}

/// Split a shell script into simple commands, nested ones included.
pub fn parse_script(text: &str, budget: &mut i64) -> Result<Vec<SimpleCommand>, PErr> {
    let t: Vec<char> = text.chars().collect();
    parse_script_at(&t, 0, budget)
}

pub fn parse_script_at(
    t: &[char],
    depth: usize,
    budget: &mut i64,
) -> Result<Vec<SimpleCommand>, PErr> {
    spend(budget)?;
    if depth > 8 {
        return Err(PErr::Parse);
    }
    let n = t.len();
    let mut p = Parser {
        t,
        depth,
        arena: vec![SimpleCommand::default()],
        commands: Vec::new(),
        nested: Vec::new(),
        cur: 0,
        word: String::new(),
        in_word: false,
        quoted: false,
        pending_redirect: None,
        pending_heredocs: VecDeque::new(),
    };
    let mut i = 0;
    while i < n {
        let c = t[i];
        // Comments start only at the beginning of a word.
        if c == '#' && !p.in_word {
            i = find_char(t, '\n', i).unwrap_or(n);
            continue;
        }
        if c == ' ' || c == '\t' {
            p.end_word();
            i += 1;
            while i < n && (t[i] == ' ' || t[i] == '\t') {
                i += 1;
            }
            continue;
        }
        if c == '\\' {
            if i + 1 < n && t[i + 1] == '\n' {
                i += 2;
                continue;
            }
            if i + 1 < n {
                p.word.push(t[i + 1]);
                p.in_word = true;
                p.quoted = true;
            }
            i += 2;
            continue;
        }
        if c == '\'' {
            let j = find_char(t, '\'', i + 1).ok_or(PErr::Parse)?;
            p.word.push_str(&cs(&t[i + 1..j]));
            p.in_word = true;
            p.quoted = true;
            i = j + 1;
            continue;
        }
        if c == '$' && i + 1 < n && t[i + 1] == '\'' {
            // ANSI-C quoting.
            let mut j = i + 2;
            let mut out = String::new();
            while j < n && t[j] != '\'' {
                let m = ansi_run(t, j);
                if m > j {
                    out.push_str(&cs(&t[j..m]));
                    j = m;
                    continue;
                }
                if t[j] == '\\' && j + 1 < n {
                    out.push(ansi_escape(t[j + 1]));
                    j += 2;
                    continue;
                }
                out.push(t[j]);
                j += 1;
            }
            if j >= n {
                return Err(PErr::Parse);
            }
            p.word.push_str(&out);
            p.in_word = true;
            p.quoted = true;
            i = j + 1;
            continue;
        }
        if c == '"' {
            let mut j = i + 1;
            let mut out = String::new();
            loop {
                if j >= n {
                    return Err(PErr::Parse);
                }
                let m = dq_run(t, j);
                if m > j {
                    out.push_str(&cs(&t[j..m]));
                    j = m;
                    continue;
                }
                let ch = t[j];
                if ch == '"' {
                    break;
                }
                if ch == '\\' && j + 1 < n && "\"\\$`\n".contains(t[j + 1]) {
                    if t[j + 1] != '\n' {
                        out.push(t[j + 1]);
                    }
                    j += 2;
                    continue;
                }
                if ch == '$' && j + 1 < n && t[j + 1] == '(' {
                    if j + 2 < n && t[j + 2] == '(' {
                        let k = find_matching(t, j + 3, '(', ')')?;
                        let end = if k + 1 < n && t[k + 1] == ')' {
                            k + 2
                        } else {
                            k + 1
                        };
                        out.push_str(&cs(&t[j..end]));
                        j = end;
                        continue;
                    }
                    let k = find_matching(t, j + 2, '(', ')')?;
                    let sub = parse_script_at(&t[j + 2..k], depth + 1, budget)?;
                    p.nested.extend(sub);
                    out.push_str(&cs(&t[j..k + 1]));
                    j = k + 1;
                    continue;
                }
                if ch == '`' {
                    let k = find_backtick(t, j + 1)?;
                    let sub = parse_script_at(&t[j + 1..k], depth + 1, budget)?;
                    p.nested.extend(sub);
                    out.push_str(&cs(&t[j..k + 1]));
                    j = k + 1;
                    continue;
                }
                out.push(ch);
                j += 1;
            }
            p.word.push_str(&out);
            p.in_word = true;
            p.quoted = true;
            i = j + 1;
            continue;
        }
        if c == '$' && i + 1 < n && t[i + 1] == '(' {
            if i + 2 < n && t[i + 2] == '(' {
                // Arithmetic $(( ... )): data, not a command.
                let k = find_matching(t, i + 3, '(', ')')?;
                let end = if k + 1 < n && t[k + 1] == ')' {
                    k + 2
                } else {
                    k + 1
                };
                p.word.push_str(&cs(&t[i..end]));
                p.in_word = true;
                i = end;
                continue;
            }
            let k = find_matching(t, i + 2, '(', ')')?;
            let sub = parse_script_at(&t[i + 2..k], depth + 1, budget)?;
            p.nested.extend(sub);
            p.word.push_str(&cs(&t[i..k + 1]));
            p.in_word = true;
            i = k + 1;
            continue;
        }
        if c == '$' && i + 1 < n && t[i + 1] == '{' {
            let k = find_matching(t, i + 2, '{', '}')?;
            p.word.push_str(&cs(&t[i..k + 1]));
            p.in_word = true;
            i = k + 1;
            continue;
        }
        if c == '`' {
            let k = find_backtick(t, i + 1)?;
            let sub = parse_script_at(&t[i + 1..k], depth + 1, budget)?;
            p.nested.extend(sub);
            p.word.push_str(&cs(&t[i..k + 1]));
            p.in_word = true;
            i = k + 1;
            continue;
        }
        if (c == '<' || c == '>') && i + 1 < n && t[i + 1] == '(' {
            // Process substitution <( ... ) / >( ... ).
            let k = find_matching(t, i + 2, '(', ')')?;
            let sub = parse_script_at(&t[i + 2..k], depth + 1, budget)?;
            p.nested.extend(sub);
            p.word.push_str(&cs(&t[i..k + 1]));
            p.in_word = true;
            i = k + 1;
            continue;
        }
        if c == '<' || c == '>' || (c == '&' && i + 1 < n && t[i + 1] == '>') {
            // Redirection. A bare number right before it is the fd, not a word.
            if p.in_word && !p.quoted && str_isdigit(&p.word) {
                p.word.clear();
                p.in_word = false;
            } else {
                p.end_word();
            }
            let mut op = "";
            for cand in [
                "<<<", "<<-", "&>>", "<<", ">>", ">|", "<>", ">&", "<&", "&>", ">", "<",
            ] {
                if starts_at(t, i, cand) {
                    op = cand;
                    break;
                }
            }
            i += op.len();
            if op == ">&" || op == "<&" {
                // >&2, >&- : fd duplication, no file.
                if let Some(e) = fd_dup(t, i) {
                    i = e;
                    continue;
                }
            }
            p.pending_redirect = Some(op);
            continue;
        }
        if c == '\n' {
            p.end_command(budget)?;
            i = p.read_heredocs(i + 1, budget)?;
            continue;
        }
        if let Some(end) = operator_at(t, i) {
            p.end_command(budget)?;
            i = operator_run(t, end).unwrap_or(end);
            continue;
        }
        if (c == '{' || c == '}') && !p.in_word {
            // A brace group opener/closer only when it stands alone as a word.
            if i + 1 >= n || " \t\n;".contains(t[i + 1]) {
                if c == '}' {
                    p.end_command(budget)?;
                } else {
                    p.end_word();
                }
                i += 1;
                continue;
            }
        }
        let m = word_run(t, i);
        let end = if m > i { m } else { i + 1 };
        p.word.push_str(&cs(&t[i..end]));
        p.in_word = true;
        i = end;
    }
    p.end_command(budget)?;

    // Drop shell keywords that lead a command (if/then/do/...); keep the rest.
    let Parser {
        mut arena,
        commands,
        nested,
        ..
    } = p;
    let mut all: Vec<SimpleCommand> = commands
        .iter()
        .map(|&k| std::mem::take(&mut arena[k]))
        .collect();
    all.extend(nested);
    let mut out = Vec::new();
    for mut cmd in all {
        let drop = cmd
            .words
            .iter()
            .take_while(|w| KEYWORDS_DROP.contains(&w.as_str()))
            .count();
        cmd.words.drain(..drop);
        if let Some(w0) = cmd.words.first() {
            if ["for", "select", "case", "function"].contains(&w0.as_str()) || is_funcdef(w0) {
                continue;
            }
        }
        if cmd.nonempty() {
            out.push(cmd);
        }
    }
    Ok(out)
}

/// Drop heredoc bodies (they are data) so the crude fallback never splits them.
pub fn strip_heredoc_bodies(text: &str) -> String {
    let mut out: Vec<&str> = Vec::new();
    let mut pending: VecDeque<(Vec<char>, bool)> = VecDeque::new();
    for line in text.split('\n') {
        let lc: Vec<char> = line.chars().collect();
        if let Some((delim, strip_tabs)) = pending.front() {
            if line_matches(&lc, *strip_tabs, delim) {
                pending.pop_front();
            }
            continue;
        }
        out.push(line);
        let mut i = crate::pyutil::find_str(&lc, "<<", 0);
        while let Some(at) = i {
            match heredoc_at(&lc, at) {
                Some((d, strip, end)) => {
                    pending.push_back((d.chars().collect(), strip));
                    i = crate::pyutil::find_str(&lc, "<<", end);
                }
                None => i = crate::pyutil::find_str(&lc, "<<", at + 3),
            }
        }
    }
    out.join("\n")
}

/// `re.split(r"&&|\|\||[;|&\n()`]|\$\(", text)`.
fn split_operators(text: &str) -> Vec<String> {
    let t: Vec<char> = text.chars().collect();
    let mut out = Vec::new();
    let mut seg = String::new();
    let mut i = 0;
    while i < t.len() {
        let len = if starts_at(&t, i, "&&") || starts_at(&t, i, "||") {
            2
        } else if ";|&\n()`".contains(t[i]) {
            1
        } else if starts_at(&t, i, "$(") {
            2
        } else {
            0
        };
        if len > 0 {
            out.push(std::mem::take(&mut seg));
            i += len;
        } else {
            seg.push(t[i]);
            i += 1;
        }
    }
    out.push(seg);
    out
}

/// When the parser gives up (unbalanced quotes), split crudely on operators.
pub fn fallback_split(
    text: &str,
    mut budget: Option<&mut i64>,
) -> Result<Vec<SimpleCommand>, PErr> {
    let mut out = Vec::new();
    for seg in split_operators(&strip_heredoc_bodies(text)) {
        let words: Vec<String> = py_split_ws(&seg)
            .into_iter()
            .map(|w| w.trim_matches(|c| c == '\'' || c == '"').to_string())
            .collect();
        if !words.is_empty() {
            if let Some(b) = budget.as_deref_mut() {
                spend(b)?;
            }
            out.push(SimpleCommand {
                words,
                ..Default::default()
            });
        }
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn words(text: &str) -> Vec<Vec<String>> {
        let mut b = MAX_COMMANDS;
        parse_script(text, &mut b)
            .unwrap()
            .into_iter()
            .map(|c| c.words)
            .collect()
    }

    fn v(items: &[&[&str]]) -> Vec<Vec<String>> {
        items
            .iter()
            .map(|ws| ws.iter().map(|w| w.to_string()).collect())
            .collect()
    }

    #[test]
    fn quotes_and_operators() {
        assert_eq!(
            words("a 'b c' \"d $e\" && f|g; h"),
            v(&[&["a", "b c", "d $e"], &["f"], &["g"], &["h"]])
        );
    }

    #[test]
    fn redirections_are_not_arguments() {
        let mut b = MAX_COMMANDS;
        let cmds = parse_script("git log > out.txt 2>&1 < /dev/null", &mut b).unwrap();
        assert_eq!(cmds[0].words, vec!["git", "log"]);
        assert!(cmds[0].redirects.contains(&(">".into(), "out.txt".into())));
    }

    #[test]
    fn heredocs() {
        let mut b = MAX_COMMANDS;
        let cmds = parse_script("cat <<'EOF' > f\ngit push\nEOF\necho done", &mut b).unwrap();
        assert_eq!(
            cmds.iter().map(|c| c.words.clone()).collect::<Vec<_>>(),
            v(&[&["cat"], &["echo", "done"]])
        );
        assert_eq!(cmds[0].heredocs, vec!["git push"]);
        assert!(words("cat <<EOF\n$(git push)\nEOF").contains(&vec!["git".into(), "push".into()]));
        assert!(
            !words("cat <<'EOF'\n$(git push)\nEOF").contains(&vec!["git".into(), "push".into()])
        );
        let text = "echo \"$(cat <<'EOF'\nit's `git push`\nEOF\n)\" && ls";
        assert_eq!(
            words(text),
            v(&[
                &["echo", "$(cat <<'EOF'\nit's `git push`\nEOF\n)"],
                &["ls"],
                &["cat"]
            ])
        );
    }

    #[test]
    fn substitutions_and_comments() {
        assert!(words("echo \"$(echo $(git push))\"").contains(&vec!["git".into(), "push".into()]));
        assert_eq!(words("ls # git push"), v(&[&["ls"]]));
        let subs: Vec<String> = body_substitutions(
            &"a $(git push) `go test` \\$(no) \\`no\\` $((1+2))"
                .chars()
                .collect::<Vec<_>>(),
        )
        .iter()
        .map(|s| cs(s))
        .collect();
        assert_eq!(subs, vec!["git push", "go test"]);
    }

    #[test]
    fn fallback_drops_heredoc_bodies() {
        let text = "cat <<'EOF'\ndon't git push\nEOF\necho \"unterminated";
        assert!(!strip_heredoc_bodies(text).contains("push"));
        let ws: Vec<String> = fallback_split(text, None)
            .unwrap()
            .into_iter()
            .flat_map(|c| c.words)
            .collect();
        assert!(!ws.contains(&"push".to_string()));
    }

    #[test]
    fn too_many_commands() {
        let mut b = MAX_COMMANDS;
        assert_eq!(
            parse_script(&"true; ".repeat(25000), &mut b),
            Err(PErr::TooComplex)
        );
    }
}
