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

//! `$((start_time + TIMEOUT))`: watch-pr.sh hands `--timeout` to bash
//! arithmetic, so `010` is eight, `0x10` sixteen, `2*60` a hundred and twenty
//! and a variable name is looked up (under `set -u`). This covers integer
//! constants in every base bash reads, names, unary `+ -`, `* / %`, `+ -` and
//! parentheses, with bash's messages for the errors. Anything else bash
//! arithmetic offers (comparisons, assignment, `?:`, bit operators) is
//! reported as a syntax error.

/// Why an expression failed, and the exit status bash gives the script.
#[derive(Debug, PartialEq)]
pub struct ArithError {
    /// What bash prints after `<script>: line <n>: `.
    pub message: String,
    pub status: i32,
}

const MAX_DEPTH: usize = 1024;

/// An unset name under `set -u` ends the script with 1 in bash 5. bash 3.2
/// (macOS's /bin/bash) prints the same message and then exits 0, reporting
/// success for a watch that never ran; this port takes bash 5's answer.
pub const UNBOUND_STATUS: i32 = 1;

pub trait Vars {
    fn get(&self, name: &str) -> Option<String>;
}

struct Parser<'a, V: Vars> {
    text: &'a str,
    pos: usize,
    vars: &'a V,
    depth: usize,
}

fn syntax(expr: &str, what: &str, token: &str) -> ArithError {
    ArithError {
        message: format!("{expr}: {what} (error token is \"{token}\")"),
        status: 1,
    }
}

impl<'a, V: Vars> Parser<'a, V> {
    fn skip_ws(&mut self) {
        while let Some(c) = self.text[self.pos..].chars().next() {
            if c == ' ' || c == '\t' || c == '\n' {
                self.pos += 1;
            } else {
                break;
            }
        }
    }

    fn peek(&mut self) -> Option<char> {
        self.skip_ws();
        self.text[self.pos..].chars().next()
    }

    fn rest(&self) -> &str {
        &self.text[self.pos..]
    }

    fn expr(&mut self) -> Result<i64, ArithError> {
        let mut value = self.term()?;
        loop {
            match self.peek() {
                Some('+') => {
                    self.pos += 1;
                    value = value.wrapping_add(self.term()?);
                }
                Some('-') => {
                    self.pos += 1;
                    value = value.wrapping_sub(self.term()?);
                }
                _ => return Ok(value),
            }
        }
    }

    fn term(&mut self) -> Result<i64, ArithError> {
        let mut value = self.unary()?;
        loop {
            let op = match self.peek() {
                Some(c @ ('*' | '/' | '%')) => c,
                _ => return Ok(value),
            };
            if self.rest().starts_with("**") {
                return Err(syntax(
                    self.text,
                    "syntax error: operand expected",
                    self.rest(),
                ));
            }
            self.pos += 1;
            let at = self.pos;
            let rhs = self.unary()?;
            if op == '*' {
                value = value.wrapping_mul(rhs);
            } else if rhs == 0 {
                let token = self.text[at..].trim_start();
                return Err(syntax(self.text, "division by 0", token));
            } else if op == '/' {
                value = value.wrapping_div(rhs);
            } else {
                value = value.wrapping_rem(rhs);
            }
        }
    }

    fn unary(&mut self) -> Result<i64, ArithError> {
        match self.peek() {
            Some('+') => {
                self.pos += 1;
                self.unary()
            }
            Some('-') => {
                self.pos += 1;
                Ok(self.unary()?.wrapping_neg())
            }
            _ => self.primary(),
        }
    }

    fn primary(&mut self) -> Result<i64, ArithError> {
        match self.peek() {
            None => Err(syntax(self.text, "syntax error: operand expected", "")),
            Some('(') => {
                self.pos += 1;
                let value = self.expr()?;
                if self.peek() != Some(')') {
                    return Err(syntax(self.text, "missing `)'", self.rest()));
                }
                self.pos += 1;
                Ok(value)
            }
            Some(c) if c.is_ascii_digit() => self.number(),
            Some(c) if c.is_ascii_alphabetic() || c == '_' => self.name(),
            Some(_) => Err(syntax(
                self.text,
                "syntax error: operand expected",
                self.rest(),
            )),
        }
    }

    fn number(&mut self) -> Result<i64, ArithError> {
        let start = self.pos;
        let rest = &self.text[start..];
        let len = rest
            .char_indices()
            .find(|&(_, c)| !(c.is_ascii_alphanumeric() || c == '#' || c == '@' || c == '_'))
            .map(|(i, _)| i)
            .unwrap_or(rest.len());
        let token = &rest[..len];
        self.pos += len;
        let too_great = || syntax(self.text, "value too great for base", &self.text[start..]);
        let (base, digits) = if let Some(hash) = token.find('#') {
            let base: u32 = token[..hash].parse().map_err(|_| too_great())?;
            if !(2..=64).contains(&base) {
                return Err(syntax(
                    self.text,
                    "invalid arithmetic base",
                    &self.text[start..],
                ));
            }
            (base, &token[hash + 1..])
        } else if let Some(hex) = token
            .strip_prefix("0x")
            .or_else(|| token.strip_prefix("0X"))
        {
            (16, hex)
        } else if token.len() > 1 && token.starts_with('0') {
            (8, &token[1..])
        } else {
            (10, token)
        };
        let mut value: i64 = 0;
        for c in digits.chars() {
            let d = match c {
                '0'..='9' => c as u32 - '0' as u32,
                'a'..='z' => c as u32 - 'a' as u32 + 10,
                'A'..='Z' if base <= 36 => c as u32 - 'A' as u32 + 10,
                'A'..='Z' => c as u32 - 'A' as u32 + 36,
                '@' => 62,
                '_' => 63,
                _ => 99,
            };
            if d >= base {
                return Err(too_great());
            }
            value = value.wrapping_mul(base as i64).wrapping_add(d as i64);
        }
        if base != 10 && digits.is_empty() && !token.contains('#') && base == 16 {
            return Ok(0);
        }
        self.after_operand()?;
        Ok(value)
    }

    fn name(&mut self) -> Result<i64, ArithError> {
        let rest = &self.text[self.pos..];
        let len = rest
            .char_indices()
            .find(|&(_, c)| !(c.is_ascii_alphanumeric() || c == '_'))
            .map(|(i, _)| i)
            .unwrap_or(rest.len());
        let name = rest[..len].to_string();
        self.pos += len;
        let value = match self.vars.get(&name) {
            Some(v) => v,
            None => {
                return Err(ArithError {
                    message: format!("{name}: unbound variable"),
                    status: UNBOUND_STATUS,
                })
            }
        };
        if self.depth + 1 >= MAX_DEPTH {
            return Err(syntax(&name, "expression recursion level exceeded", &name));
        }
        let inner = evaluate_at(&value, self.vars, self.depth + 1).map_err(|e| {
            if e.message.contains("expression recursion level exceeded") {
                syntax(&name, "expression recursion level exceeded", &name)
            } else {
                e
            }
        })?;
        self.after_operand()?;
        Ok(inner)
    }

    /// After an operand only an operator, `)` or the end may follow.
    fn after_operand(&mut self) -> Result<(), ArithError> {
        match self.peek() {
            None | Some('+' | '-' | '*' | '/' | '%' | ')') => Ok(()),
            Some(c) if c.is_ascii_alphanumeric() || c == '_' => {
                Err(syntax(self.text, "syntax error in expression", self.rest()))
            }
            Some(_) => Err(syntax(
                self.text,
                "syntax error: invalid arithmetic operator",
                self.rest(),
            )),
        }
    }
}

fn evaluate_at<V: Vars>(text: &str, vars: &V, depth: usize) -> Result<i64, ArithError> {
    let mut p = Parser {
        text,
        pos: 0,
        vars,
        depth,
    };
    if p.peek().is_none() {
        return Ok(0);
    }
    let value = p.expr()?;
    match p.peek() {
        None => Ok(value),
        Some(')') => Err(syntax(
            text,
            "syntax error: invalid arithmetic operator",
            p.rest(),
        )),
        Some(_) => Err(syntax(text, "syntax error in expression", p.rest())),
    }
}

/// The value of variable `name` in an arithmetic context.
pub fn variable<V: Vars>(name: &str, vars: &V) -> Result<i64, ArithError> {
    match vars.get(name) {
        None => Err(ArithError {
            message: format!("{name}: unbound variable"),
            status: UNBOUND_STATUS,
        }),
        Some(value) => evaluate_at(&value, vars, 1).map_err(|e| {
            if e.message.contains("expression recursion level exceeded") {
                syntax(name, "expression recursion level exceeded", name)
            } else {
                e
            }
        }),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;

    struct Map(HashMap<&'static str, &'static str>);
    impl Vars for Map {
        fn get(&self, name: &str) -> Option<String> {
            self.0.get(name).map(|s| s.to_string())
        }
    }

    fn timeout(value: &'static str) -> Result<i64, ArithError> {
        let vars = Map(HashMap::from([("TIMEOUT", value), ("start_time", "5")]));
        variable("TIMEOUT", &vars)
    }

    fn msg(r: Result<i64, ArithError>) -> (String, i32) {
        let e = r.unwrap_err();
        (e.message, e.status)
    }

    #[test]
    fn constants_in_every_base() {
        assert_eq!(timeout("2700"), Ok(2700));
        assert_eq!(timeout(" 7 "), Ok(7));
        assert_eq!(timeout(""), Ok(0));
        assert_eq!(timeout("010"), Ok(8));
        assert_eq!(timeout("0x1f"), Ok(31));
        assert_eq!(timeout("0x"), Ok(0));
        assert_eq!(timeout("64#z"), Ok(35));
        assert_eq!(timeout("2#101"), Ok(5));
        assert_eq!(timeout("-5"), Ok(-5));
        assert_eq!(timeout("--5"), Ok(5));
        assert_eq!(timeout("2*60+1"), Ok(121));
        assert_eq!(timeout("(1+2)*3"), Ok(9));
        assert_eq!(timeout("start_time"), Ok(5));
    }

    #[test]
    fn bash_messages() {
        assert_eq!(
            msg(timeout("08")),
            (
                "08: value too great for base (error token is \"08\")".into(),
                1
            )
        );
        assert_eq!(
            msg(timeout("1.5")),
            (
                "1.5: syntax error: invalid arithmetic operator (error token is \".5\")".into(),
                1
            )
        );
        assert_eq!(
            msg(timeout("5abc")),
            (
                "5abc: value too great for base (error token is \"5abc\")".into(),
                1
            )
        );
        assert_eq!(
            msg(timeout("1 2")),
            (
                "1 2: syntax error in expression (error token is \"2\")".into(),
                1
            )
        );
        assert_eq!(
            msg(timeout("2#12")),
            (
                "2#12: value too great for base (error token is \"2#12\")".into(),
                1
            )
        );
        assert_eq!(msg(timeout("x+1")), ("x: unbound variable".into(), 1));
        assert_eq!(
            msg(timeout("TIMEOUT")),
            (
                "TIMEOUT: expression recursion level exceeded (error token is \"TIMEOUT\")".into(),
                1
            )
        );
    }
}
