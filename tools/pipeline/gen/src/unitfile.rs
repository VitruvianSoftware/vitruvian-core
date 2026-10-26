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

//! pipeline_unit() declarations read straight out of BUILD files, without
//! running Bazel: a copy of //tools/pipeline/unitfile's scanner and reader
//! (that Go package is the source of truth and the presubmit planner still
//! uses it). A unit is either read completely or it is an error naming the
//! file and the unit; it never comes back with attributes quietly missing.
//!
//! It works on bytes, as the Go reader does on a Go string, so error text
//! quoting a clipped line is byte-identical. Messages are `Vec<u8>` for the
//! same reason.

use std::collections::BTreeMap;

use crate::gostr::{self, quote_bytes};

pub const DEFAULT_TIER: &str = "L1";
pub const DEFAULT_RUNNER: &str = "ubuntu-26.04";
pub const DEFAULT_PERSONA: &str = "all";
pub const DEFAULT_TIMEOUT_MINUTES: i64 = 20;

/// An error message, as raw bytes.
pub type Msg = Vec<u8>;

fn msg(parts: &[&[u8]]) -> Msg {
    parts.concat()
}

/// One pipeline_unit() declaration as written in a BUILD file.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct Unit {
    pub name: String,
    pub package: String,
    pub test_targets: Vec<String>,
    pub tier: String,
    pub runner: String,
    pub persona: String,
    pub timeout_minutes: i64,
    pub depends_on: Vec<String>,
    pub needs_emulator: bool,
    pub env: BTreeMap<String, String>,
    pub artifacts: BTreeMap<String, String>,
    pub build_flags: Vec<String>,
    pub line: usize,
}

#[derive(Clone, Copy, PartialEq, Debug)]
enum Kind {
    Ident,
    Str,
    Number,
    Punct,
}

#[derive(Clone, Debug)]
struct Token {
    kind: Kind,
    text: Vec<u8>,
    line: usize,
}

impl Token {
    fn is(&self, p: &str) -> bool {
        self.kind == Kind::Punct && self.text == p.as_bytes()
    }
}

fn is_ident_start(c: u8) -> bool {
    c == b'_' || c.is_ascii_alphabetic()
}

fn is_digit(c: u8) -> bool {
    c.is_ascii_digit()
}

fn line_prefix(line: usize, e: &[u8]) -> Msg {
    msg(&[format!("line {line}: ").as_bytes(), e])
}

/// Go's `tokenize`. On an error it also returns the tokens read so far
/// (none for an error in a prefixed string, as the Go code does).
fn tokenize(src: &[u8]) -> (Vec<Token>, Option<Msg>) {
    let mut toks = Vec::new();
    let mut line = 1;
    let mut i = 0;
    while i < src.len() {
        let c = src[i];
        if c == b'\n' {
            line += 1;
            i += 1;
        } else if c == b' ' || c == b'\t' || c == b'\r' {
            i += 1;
        } else if c == b'\\' && i + 1 < src.len() && src[i + 1] == b'\n' {
            line += 1;
            i += 2;
        } else if c == b'#' {
            while i < src.len() && src[i] != b'\n' {
                i += 1;
            }
        } else if c == b'"' || c == b'\'' {
            match scan_string(&src[i..], false) {
                Err(e) => return (toks, Some(line_prefix(line, &e))),
                Ok((val, n, lines)) => {
                    toks.push(Token {
                        kind: Kind::Str,
                        text: val,
                        line,
                    });
                    line += lines;
                    i += n;
                }
            }
        } else if is_ident_start(c) {
            let mut j = i;
            while j < src.len() && (is_ident_start(src[j]) || is_digit(src[j])) {
                j += 1;
            }
            let word = &src[i..j];
            if j < src.len() && (src[j] == b'"' || src[j] == b'\'') && is_string_prefix(word) {
                let raw = word.iter().any(|&b| b == b'r' || b == b'R');
                match scan_string(&src[j..], raw) {
                    Err(e) => return (Vec::new(), Some(line_prefix(line, &e))),
                    Ok((val, n, lines)) => {
                        toks.push(Token {
                            kind: Kind::Str,
                            text: val,
                            line,
                        });
                        line += lines;
                        i = j + n;
                        continue;
                    }
                }
            }
            toks.push(Token {
                kind: Kind::Ident,
                text: word.to_vec(),
                line,
            });
            i = j;
        } else if is_digit(c) {
            let mut j = i;
            while j < src.len() && (is_digit(src[j]) || is_ident_start(src[j]) || src[j] == b'.') {
                j += 1;
            }
            toks.push(Token {
                kind: Kind::Number,
                text: src[i..j].to_vec(),
                line,
            });
            i = j;
        } else {
            if i + 1 < src.len() && src[i + 1] == b'=' && b"=!<>+-*/%|&^".contains(&c) {
                toks.push(Token {
                    kind: Kind::Punct,
                    text: src[i..i + 2].to_vec(),
                    line,
                });
                i += 2;
                continue;
            }
            toks.push(Token {
                kind: Kind::Punct,
                text: vec![c],
                line,
            });
            i += 1;
        }
    }
    (toks, None)
}

fn is_string_prefix(word: &[u8]) -> bool {
    matches!(
        word.to_ascii_lowercase().as_slice(),
        b"r" | b"b" | b"rb" | b"br"
    )
}

/// Go's `scanString`: the value, bytes consumed and newlines crossed.
fn scan_string(s: &[u8], raw: bool) -> Result<(Vec<u8>, usize, usize), Msg> {
    let quote = s[0];
    let triple = s.len() >= 3 && s[1] == quote && s[2] == quote;
    let mut i = if triple { 3 } else { 1 };
    let mut lines = 0;
    let mut b = Vec::new();
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
        } else if c == quote && !triple {
            return Ok((b, i + 1, lines));
        } else if c == quote && triple && s[i..].starts_with(&s[..3]) {
            return Ok((b, i + 3, lines));
        } else if c == b'\n' && !triple {
            return Err(msg(&[
                b"a string starting ",
                &clip(s),
                b" is not closed before the end of the line",
            ]));
        } else {
            if c == b'\n' {
                lines += 1;
            }
            b.push(c);
            i += 1;
        }
    }
    Err(msg(&[b"a string starting ", &clip(s), b" is never closed"]))
}

fn clip(s: &[u8]) -> Vec<u8> {
    let mut s = s;
    if let Some(nl) = s.iter().position(|&c| c == b'\n') {
        s = &s[..nl];
    }
    if s.len() > 30 {
        let mut v = s[..30].to_vec();
        v.extend_from_slice(b"...");
        return v;
    }
    s.to_vec()
}

fn closer_of(t: &Token) -> Option<&'static str> {
    if t.kind != Kind::Punct {
        return None;
    }
    match t.text.as_slice() {
        b"(" => Some(")"),
        b"[" => Some("]"),
        b"{" => Some("}"),
        _ => None,
    }
}

fn is_closer(t: &Token) -> bool {
    t.is(")") || t.is("]") || t.is("}")
}

fn q(b: &[u8]) -> Vec<u8> {
    quote_bytes(b).into_bytes()
}

/// Go's `matchBracket`.
fn match_bracket(toks: &[Token], open: usize) -> Result<usize, Msg> {
    let mut stack: Vec<&Token> = Vec::new();
    for (i, t) in toks.iter().enumerate().skip(open) {
        if t.kind != Kind::Punct {
            continue;
        }
        if closer_of(t).is_some() {
            stack.push(t);
            continue;
        }
        if !is_closer(t) {
            continue;
        }
        let Some(top) = stack.last() else {
            return Err(msg(&[
                format!("line {}: ", t.line).as_bytes(),
                &q(&t.text),
                b" closes nothing",
            ]));
        };
        if closer_of(top).map(str::as_bytes) != Some(t.text.as_slice()) {
            return Err(msg(&[
                format!("line {}: ", t.line).as_bytes(),
                &q(&t.text),
                b" closes the ",
                &q(&top.text),
                format!(" opened on line {}", top.line).as_bytes(),
            ]));
        }
        stack.pop();
        if stack.is_empty() {
            return Ok(i);
        }
    }
    Err(msg(&[
        b"the ",
        &q(&toks[open].text),
        format!(" opened on line {} is never closed", toks[open].line).as_bytes(),
    ]))
}

/// Go's `splitTopLevel`.
fn split_top_level<'a>(toks: &'a [Token], sep: &str) -> Vec<&'a [Token]> {
    let mut parts = Vec::new();
    let mut depth: i64 = 0;
    let mut start = 0;
    for (i, t) in toks.iter().enumerate() {
        if t.kind != Kind::Punct {
            continue;
        }
        if closer_of(t).is_some() {
            depth += 1;
        } else if is_closer(t) {
            depth -= 1;
        } else if depth == 0 && t.text == sep.as_bytes() {
            parts.push(&toks[start..i]);
            start = i + 1;
        }
    }
    if start < toks.len() {
        parts.push(&toks[start..]);
    }
    parts
}

#[derive(Clone, Debug, Default)]
enum Value {
    #[default]
    NotLiteral,
    Str(Vec<u8>),
    Int(i64),
    Bool(bool),
    List(Vec<Value>),
    Dict(Vec<(Value, Value)>),
}

/// Go's `strconv.Atoi` on a number token: decimal digits only.
fn atoi(b: &[u8]) -> Option<i64> {
    if b.is_empty() || !b.iter().all(u8::is_ascii_digit) {
        return None;
    }
    std::str::from_utf8(b).ok()?.parse().ok()
}

/// Go's `readValue`.
fn read_value(toks: &[Token]) -> Value {
    if toks.is_empty() {
        return Value::NotLiteral;
    }
    if toks.len() == 1 {
        let t = &toks[0];
        return match t.kind {
            Kind::Str => Value::Str(t.text.clone()),
            Kind::Number => atoi(&t.text).map_or(Value::NotLiteral, Value::Int),
            Kind::Ident if t.text == b"True" || t.text == b"False" => {
                Value::Bool(t.text == b"True")
            }
            _ => Value::NotLiteral,
        };
    }
    let (first, last) = (&toks[0], &toks[toks.len() - 1]);
    if !first.is("[") && !first.is("{") {
        return Value::NotLiteral;
    }
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
        let mut d = Vec::new();
        for part in split_top_level(inner, ",") {
            let kv = split_top_level(part, ":");
            if kv.len() != 2 {
                return Value::NotLiteral;
            }
            d.push((read_value(kv[0]), read_value(kv[1])));
        }
        return Value::Dict(d);
    }
    Value::NotLiteral
}

struct Call {
    line: usize,
    args: BTreeMap<Vec<u8>, Value>,
}

/// Go's `nameIn`.
fn name_in(toks: &[Token]) -> Option<Vec<u8>> {
    let mut i = 0;
    while i + 2 < toks.len() && i < 200 {
        if toks[i].kind == Kind::Ident
            && toks[i].text == b"name"
            && toks[i + 1].is("=")
            && toks[i + 2].kind == Kind::Str
        {
            return Some(toks[i + 2].text.clone());
        }
        i += 1;
    }
    None
}

fn is_call_of(toks: &[Token], i: usize, fn_name: &[u8]) -> bool {
    toks[i].kind == Kind::Ident && toks[i].text == fn_name && toks[i + 1].is("(")
}

/// Go's `findCalls`.
fn find_calls(src: &[u8], fn_name: &str) -> Result<Vec<Call>, Msg> {
    let fname = fn_name.as_bytes();
    let (toks, err) = tokenize(src);
    if let Some(err) = err {
        // If the text stopped making sense inside a call to fn, name it.
        let mut i = toks.len() as i64 - 2;
        while i >= 0 {
            let iu = i as usize;
            if !is_call_of(&toks, iu, fname) {
                i -= 1;
                continue;
            }
            if match_bracket(&toks, iu + 1).is_err() {
                let line = format!("{}", toks[iu].line);
                return Err(match name_in(&toks[iu + 2..]) {
                    Some(name) => msg(&[
                        fname,
                        b"(name = ",
                        &q(&name),
                        b"), which starts on line ",
                        line.as_bytes(),
                        b": ",
                        &err,
                    ]),
                    None => msg(&[
                        fname,
                        b"(...), which starts on line ",
                        line.as_bytes(),
                        b": ",
                        &err,
                    ]),
                });
            }
            break;
        }
        return Err(err);
    }
    let mut calls = Vec::new();
    let mut i = 0;
    while i + 1 < toks.len() {
        if !is_call_of(&toks, i, fname) {
            i += 1;
            continue;
        }
        if i > 0
            && (toks[i - 1].is(".")
                || (toks[i - 1].kind == Kind::Ident && toks[i - 1].text == b"def"))
        {
            i += 1;
            continue;
        }
        let line = toks[i].line;
        let end = match match_bracket(&toks, i + 1) {
            Ok(e) => e,
            Err(e) => {
                let lp = format!("line {line}: ");
                return Err(match name_in(&toks[i + 2..]) {
                    Some(name) => msg(&[lp.as_bytes(), fname, b"(name = ", &q(&name), b"): ", &e]),
                    None => msg(&[lp.as_bytes(), fname, b"(...): ", &e]),
                });
            }
        };
        let mut args = BTreeMap::new();
        for arg in split_top_level(&toks[i + 2..end], ",") {
            if arg.len() < 3 || arg[0].kind != Kind::Ident || !arg[1].is("=") {
                return Err(msg(&[
                    format!("line {}: ", arg[0].line).as_bytes(),
                    fname,
                    b"(...): every argument must be written name = value; found one that is not (positional, * or **)",
                ]));
            }
            args.insert(arg[0].text.clone(), read_value(&arg[2..]));
        }
        calls.push(Call { line, args });
        i = end + 1;
    }
    Ok(calls)
}

fn lossy(b: &[u8]) -> String {
    String::from_utf8_lossy(b).into_owned()
}

/// Go's `Parse`: every pipeline_unit() call in one BUILD file's text.
pub fn parse(content: &[u8], pkg: &str) -> Result<Vec<Unit>, Msg> {
    if !content.windows(13).any(|w| w == b"pipeline_unit") {
        return Ok(Vec::new());
    }
    let calls = find_calls(content, "pipeline_unit")?;
    let mut units = Vec::new();
    for c in calls {
        units.push(unit_from_call(&c, pkg)?);
    }
    Ok(units)
}

fn unit_from_call(c: &Call, pkg: &str) -> Result<Unit, Msg> {
    let name = match c.args.get(b"name".as_slice()) {
        Some(Value::Str(s)) if !s.is_empty() => s.clone(),
        _ => {
            return Err(format!(
                "line {}: pipeline_unit(...): name must be a quoted string",
                c.line
            )
            .into_bytes())
        }
    };
    let mut u = Unit {
        name: lossy(&name),
        package: pkg.to_string(),
        tier: DEFAULT_TIER.into(),
        runner: DEFAULT_RUNNER.into(),
        persona: DEFAULT_PERSONA.into(),
        timeout_minutes: DEFAULT_TIMEOUT_MINUTES,
        line: c.line,
        ..Default::default()
    };
    let fail = |what: &str| -> Msg {
        msg(&[
            format!("line {}: pipeline_unit(name = ", c.line).as_bytes(),
            &q(&name),
            b"): ",
            what.as_bytes(),
        ])
    };

    // Go ranges over a map here, so with two bad attributes which one it
    // reports is random; a single bad one is reported identically.
    for (attr, dst) in [
        ("tier", &mut u.tier),
        ("runner", &mut u.runner),
        ("persona", &mut u.persona),
    ] {
        match c.args.get(attr.as_bytes()) {
            None => {}
            Some(Value::Str(s)) => *dst = lossy(s),
            Some(_) => return Err(fail(&format!("{attr} must be a quoted string"))),
        }
    }
    match c.args.get(b"timeout_minutes".as_slice()) {
        None => {}
        Some(Value::Int(n)) => u.timeout_minutes = *n,
        Some(_) => return Err(fail("timeout_minutes must be a whole number")),
    }
    match c.args.get(b"needs_emulator".as_slice()) {
        None => {}
        Some(Value::Bool(b)) => u.needs_emulator = *b,
        Some(_) => return Err(fail("needs_emulator must be True or False")),
    }
    for (attr, dst) in [
        ("test_targets", &mut u.test_targets),
        ("depends_on", &mut u.depends_on),
        ("build_flags", &mut u.build_flags),
    ] {
        match c.args.get(attr.as_bytes()) {
            None => {}
            Some(Value::List(items)) => {
                for item in items {
                    let Value::Str(s) = item else {
                        return Err(fail(&format!("every entry of {attr} must be a quoted string")));
                    };
                    dst.push(lossy(s));
                }
            }
            Some(_) => {
                return Err(fail(&format!(
                    "{attr} must be a list written out in the call, [\"...\", ...]; this reader does not run Bazel, so it cannot follow a name, glob() or select()"
                )))
            }
        }
    }
    for (attr, dst) in [("env", &mut u.env), ("artifacts", &mut u.artifacts)] {
        match c.args.get(attr.as_bytes()) {
            None => {}
            Some(Value::Dict(kvs)) => {
                for (k, v) in kvs {
                    let (Value::Str(k), Value::Str(v)) = (k, v) else {
                        return Err(fail(&format!(
                            "every key and value of {attr} must be a quoted string"
                        )));
                    };
                    dst.insert(lossy(k), lossy(v));
                }
            }
            Some(_) => {
                return Err(fail(&format!(
                    "{attr} must be a dict written out in the call, {{\"...\": \"...\"}}"
                )))
            }
        }
    }
    if u.test_targets.is_empty() {
        return Err(fail("test_targets is missing or empty"));
    }
    for t in u.test_targets.iter_mut() {
        if t.starts_with(':') {
            *t = format!("//{pkg}{t}");
        }
    }
    Ok(u)
}

/// Go's `Discover`: every BUILD and BUILD.bazel under root, units sorted by
/// name, every unreadable declaration and every duplicate name reported.
pub fn discover(root: &str) -> Result<Vec<Unit>, Msg> {
    let mut units: Vec<Unit> = Vec::new();
    let mut errs: Vec<Msg> = Vec::new();
    let mut declared_in: BTreeMap<String, String> = BTreeMap::new();
    gostr::walk(root, &mut |path, is_dir, name| {
        let Some(is_dir) = is_dir else { return false };
        if is_dir {
            if name == ".git" || name == "node_modules" || name == ".claude" {
                return true;
            }
            // Bazel's output links at the top of the workspace.
            return name.starts_with("bazel-") && gostr::dir(path) == root;
        }
        if name != "BUILD" && name != "BUILD.bazel" {
            return false;
        }
        let rel = gostr::rel_under(root, path);
        let pkg = match rel.rfind('/') {
            Some(i) => rel[..i].to_string(),
            None => String::new(),
        };
        let content = match gostr::read_file(path) {
            Ok(c) => c,
            Err(e) => {
                errs.push(format!("{rel}: {e}").into_bytes());
                return false;
            }
        };
        match parse(&content, &pkg) {
            Err(e) => errs.push(msg(&[rel.as_bytes(), b": ", &e])),
            Ok(parsed) => {
                for u in parsed {
                    if let Some(first) = declared_in.get(&u.name) {
                        errs.push(
                            format!(
                                "{rel}: line {}: pipeline_unit(name = {}) is already declared in {first}; unit names must be unique across the repository",
                                u.line,
                                gostr::quote(&u.name)
                            )
                            .into_bytes(),
                        );
                        continue;
                    }
                    declared_in.insert(u.name.clone(), rel.clone());
                    units.push(u);
                }
            }
        }
        false
    });
    if !errs.is_empty() {
        let mut m = b"cannot read every pipeline unit:\n".to_vec();
        m.extend_from_slice(&errs.join(&b'\n'));
        return Err(m);
    }
    units.sort_by(|a, b| a.name.cmp(&b.name));
    Ok(units)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn one(build: &str, pkg: &str) -> Unit {
        let mut v = parse(build.as_bytes(), pkg).unwrap();
        assert_eq!(v.len(), 1);
        v.remove(0)
    }

    #[test]
    fn reads_attributes_through_comments_and_strings() {
        let u = one(
            r#"
pipeline_unit(
    name = "remote",
    # NDK 29.0.14206865 (the version installed when this landed) decides ABIs.
    artifacts = {"apk": "apps/x/app.apk"},
    env = {"REF": "main#head"},
    build_flags = ["--fat_apk_cpu=arm64-v8a,x86_64"],
    test_targets = [
        ":app",
        "//other:lib",
    ],
    tier = "L1",
    timeout_minutes = 30,
    needs_emulator = True,
)
"#,
            "pkg",
        );
        assert_eq!(u.test_targets, ["//pkg:app", "//other:lib"]);
        assert_eq!(u.artifacts["apk"], "apps/x/app.apk");
        assert_eq!(u.env["REF"], "main#head");
        assert_eq!(u.build_flags, ["--fat_apk_cpu=arm64-v8a,x86_64"]);
        assert_eq!((u.timeout_minutes, u.needs_emulator), (30, true));
        assert_eq!(
            (u.runner.as_str(), u.persona.as_str()),
            (DEFAULT_RUNNER, DEFAULT_PERSONA)
        );
    }

    #[test]
    fn non_literals_and_bad_text_are_errors() {
        let e = |s: &str| String::from_utf8(parse(s.as_bytes(), "p").unwrap_err()).unwrap();
        assert_eq!(
            e("pipeline_unit(name = \"u\", test_targets = glob([\"*\"]))"),
            "line 1: pipeline_unit(name = \"u\"): test_targets must be a list written out in the call, [\"...\", ...]; this reader does not run Bazel, so it cannot follow a name, glob() or select()"
        );
        assert_eq!(
            e("pipeline_unit(name = \"u\")"),
            "line 1: pipeline_unit(name = \"u\"): test_targets is missing or empty"
        );
        assert_eq!(
            e("pipeline_unit(\n  name = \"u\",\n  tier = \"L1\n)"),
            "pipeline_unit(name = \"u\"), which starts on line 1: line 3: a string starting \"L1 is not closed before the end of the line"
        );
        assert_eq!(
            e("pipeline_unit(name = \"u\", test_targets = [\":t\"]]"),
            "line 1: pipeline_unit(name = \"u\"): line 1: \"]\" closes the \"(\" opened on line 1"
        );
        assert!(parse(
            b"def pipeline_unit(name): pass\nx.pipeline_unit(name = 1)",
            "p"
        )
        .unwrap()
        .is_empty());
    }
}
