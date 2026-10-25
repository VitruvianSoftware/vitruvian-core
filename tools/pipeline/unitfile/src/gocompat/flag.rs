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

//! Go's `flag` package with `flag.ExitOnError`, as the Go tools parse their
//! command lines: "-name value", "-name=value", one or two dashes, bool
//! flags without a value, "--" ends the flags, the first argument that is
//! not a flag ends them too, the last repeat wins, and every mistake prints
//! the error and the usage to stderr and exits 2 (`-h`/`-help` exit 0).

use std::collections::BTreeMap;

use super::quote::quote;

#[derive(Clone, Debug, PartialEq)]
pub enum Value {
    Str(String),
    Int(i64),
    Bool(bool),
}

pub struct Flag {
    pub name: &'static str,
    pub usage: &'static str,
    pub default: Value,
}

/// The parsed values, by name, plus the arguments left after the flags.
pub struct Parsed {
    values: BTreeMap<&'static str, Value>,
    pub rest: Vec<String>,
}

impl Parsed {
    pub fn str(&self, name: &str) -> String {
        match self.values.get(name) {
            Some(Value::Str(s)) => s.clone(),
            _ => String::new(),
        }
    }
    pub fn int(&self, name: &str) -> i64 {
        match self.values.get(name) {
            Some(Value::Int(i)) => *i,
            _ => 0,
        }
    }
    pub fn bool(&self, name: &str) -> bool {
        matches!(self.values.get(name), Some(Value::Bool(true)))
    }
}

/// Why parsing stopped: help was asked for (exit 0) or a mistake (exit 2).
/// The text is what goes to stderr.
pub struct Exit {
    pub code: i32,
    pub stderr: String,
}

/// `flag.PrintDefaults()` after "Usage of <prog>:".
pub fn usage(prog: &str, flags: &[Flag]) -> String {
    let mut sorted: Vec<&Flag> = flags.iter().collect();
    sorted.sort_by_key(|f| f.name);
    let mut out = format!("Usage of {prog}:\n");
    for f in sorted {
        let mut b = format!("  -{}", f.name);
        let (tname, usage) = unquote_usage(f);
        if !tname.is_empty() {
            b.push(' ');
            b.push_str(&tname);
        }
        if b.len() <= 4 {
            b.push('\t');
        } else {
            b.push_str("\n    \t");
        }
        b.push_str(&usage.replace('\n', "\n    \t"));
        match &f.default {
            Value::Str(s) if !s.is_empty() => b.push_str(&format!(" (default {})", quote(s))),
            Value::Int(i) if *i != 0 => b.push_str(&format!(" (default {i})")),
            Value::Bool(true) => b.push_str(" (default true)"),
            _ => {}
        }
        out.push_str(&b);
        out.push('\n');
    }
    out
}

fn unquote_usage(f: &Flag) -> (String, String) {
    let u = f.usage;
    if let Some(i) = u.find('`') {
        if let Some(j) = u[i + 1..].find('`') {
            let name = &u[i + 1..i + 1 + j];
            let usage = format!("{}{}{}", &u[..i], name, &u[i + 2 + j..]);
            return (name.to_string(), usage);
        }
    }
    let name = match f.default {
        Value::Bool(_) => "",
        Value::Int(_) => "int",
        Value::Str(_) => "string",
    };
    (name.to_string(), u.to_string())
}

/// `strconv.ParseBool`.
fn parse_bool(s: &str) -> Option<bool> {
    match s {
        "1" | "t" | "T" | "TRUE" | "true" | "True" => Some(true),
        "0" | "f" | "F" | "FALSE" | "false" | "False" => Some(false),
        _ => None,
    }
}

/// The error class of `strconv.ParseInt`, as flag reports it.
#[derive(Debug, PartialEq)]
pub enum IntErr {
    Syntax,
    Range,
}

fn underscore_ok(s: &str) -> bool {
    let b = s.as_bytes();
    let mut saw = b'^';
    let mut i = 0;
    let b = if !b.is_empty() && (b[0] == b'-' || b[0] == b'+') {
        &b[1..]
    } else {
        b
    };
    let mut hex = false;
    if b.len() >= 2 && b[0] == b'0' && matches!(b[1] | 0x20, b'b' | b'o' | b'x') {
        i = 2;
        saw = b'0';
        hex = (b[1] | 0x20) == b'x';
    }
    while i < b.len() {
        let c = b[i];
        let l = c | 0x20;
        if c.is_ascii_digit() || (hex && (b'a'..=b'f').contains(&l)) {
            saw = b'0';
        } else if c == b'_' {
            if saw != b'0' {
                return false;
            }
            saw = b'_';
        } else {
            if saw == b'_' {
                return false;
            }
            saw = b'!';
        }
        i += 1;
    }
    saw != b'_'
}

/// `strconv.ParseInt(s, 0, 64)`.
pub fn parse_int0(s0: &str) -> Result<i64, IntErr> {
    if s0.is_empty() {
        return Err(IntErr::Syntax);
    }
    let (neg, s) = match s0.as_bytes()[0] {
        b'+' => (false, &s0[1..]),
        b'-' => (true, &s0[1..]),
        _ => (false, s0),
    };
    // ParseUint(s, 0, 64)
    if s.is_empty() {
        return Err(IntErr::Syntax);
    }
    let sb = s.as_bytes();
    let (base, digits): (u64, &[u8]) = if sb[0] == b'0' {
        if sb.len() >= 3 && (sb[1] | 0x20) == b'b' {
            (2, &sb[2..])
        } else if sb.len() >= 3 && (sb[1] | 0x20) == b'o' {
            (8, &sb[2..])
        } else if sb.len() >= 3 && (sb[1] | 0x20) == b'x' {
            (16, &sb[2..])
        } else {
            (8, &sb[1..])
        }
    } else {
        (10, sb)
    };
    let cutoff: u64 = u64::MAX / base + 1;
    let mut n: u64 = 0;
    let mut underscores = false;
    for &c in digits {
        let d = match c {
            b'_' => {
                underscores = true;
                continue;
            }
            b'0'..=b'9' => (c - b'0') as u64,
            _ if (c | 0x20).is_ascii_lowercase() => ((c | 0x20) - b'a' + 10) as u64,
            _ => return Err(IntErr::Syntax),
        };
        if d >= base {
            return Err(IntErr::Syntax);
        }
        if n >= cutoff {
            return Err(IntErr::Range);
        }
        n *= base;
        let n1 = n.wrapping_add(d);
        if n1 < n {
            return Err(IntErr::Range);
        }
        n = n1;
    }
    if underscores && !underscore_ok(s) {
        return Err(IntErr::Syntax);
    }
    let limit: u64 = 1 << 63;
    if !neg && n >= limit {
        return Err(IntErr::Range);
    }
    if neg && n > limit {
        return Err(IntErr::Range);
    }
    Ok(if neg {
        (n as i64).wrapping_neg()
    } else {
        n as i64
    })
}

/// `flag.Parse()` over `args` (without the program name).
pub fn parse(prog: &str, flags: &[Flag], args: &[String]) -> Result<Parsed, Exit> {
    let mut values: BTreeMap<&'static str, Value> = BTreeMap::new();
    for f in flags {
        values.insert(f.name, f.default.clone());
    }
    let fail = |msg: String| Exit {
        code: 2,
        stderr: format!("{msg}\n{}", usage(prog, flags)),
    };
    let mut i = 0;
    while i < args.len() {
        let s = &args[i];
        let sb = s.as_bytes();
        if sb.len() < 2 || sb[0] != b'-' {
            break;
        }
        let mut minuses = 1;
        if sb[1] == b'-' {
            minuses = 2;
            if sb.len() == 2 {
                i += 1;
                break;
            }
        }
        let mut name = &s[minuses..];
        if name.is_empty() || name.starts_with('-') || name.starts_with('=') {
            return Err(fail(format!("bad flag syntax: {s}")));
        }
        i += 1;
        let mut value: Option<&str> = None;
        if let Some(eq) = name.as_bytes()[1..].iter().position(|&c| c == b'=') {
            value = Some(&name[eq + 2..]);
            name = &name[..eq + 1];
        }
        let Some(f) = flags.iter().find(|f| f.name == name) else {
            if name == "help" || name == "h" {
                return Err(Exit {
                    code: 0,
                    stderr: usage(prog, flags),
                });
            }
            return Err(fail(format!("flag provided but not defined: -{name}")));
        };
        match f.default {
            Value::Bool(_) => {
                let v = value.unwrap_or("true");
                match parse_bool(v) {
                    Some(b) => {
                        values.insert(f.name, Value::Bool(b));
                    }
                    None => {
                        return Err(fail(format!(
                            "invalid boolean value {} for -{name}: parse error",
                            quote(v)
                        )))
                    }
                }
            }
            _ => {
                let v: String = match value {
                    Some(v) => v.to_string(),
                    None => {
                        if i < args.len() {
                            i += 1;
                            args[i - 1].clone()
                        } else {
                            return Err(fail(format!("flag needs an argument: -{name}")));
                        }
                    }
                };
                match f.default {
                    Value::Int(_) => match parse_int0(&v) {
                        Ok(n) => {
                            values.insert(f.name, Value::Int(n));
                        }
                        Err(e) => {
                            let why = if e == IntErr::Syntax {
                                "parse error"
                            } else {
                                "value out of range"
                            };
                            return Err(fail(format!(
                                "invalid value {} for flag -{name}: {why}",
                                quote(&v)
                            )));
                        }
                    },
                    _ => {
                        values.insert(f.name, Value::Str(v));
                    }
                }
            }
        }
    }
    Ok(Parsed {
        values,
        rest: args[i..].to_vec(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn flags() -> Vec<Flag> {
        vec![
            Flag {
                name: "format",
                usage: "Output format",
                default: Value::Str("json".into()),
            },
            Flag {
                name: "n",
                usage: "count",
                default: Value::Int(300),
            },
            Flag {
                name: "v",
                usage: "verbose",
                default: Value::Bool(false),
            },
        ]
    }

    fn a(v: &[&str]) -> Vec<String> {
        v.iter().map(|s| s.to_string()).collect()
    }

    #[test]
    fn parses_go_forms() {
        let p = parse(
            "p",
            &flags(),
            &a(&["--format", "text", "-n=0x10", "-v", "x", "-n", "1"]),
        )
        .ok()
        .unwrap();
        assert_eq!(p.str("format"), "text");
        assert_eq!(p.int("n"), 16);
        assert!(p.bool("v"));
        assert_eq!(p.rest, a(&["x", "-n", "1"]));
    }

    #[test]
    fn errors_and_usage() {
        let e = parse("p", &flags(), &a(&["-nope"])).err().unwrap();
        assert_eq!(e.code, 2);
        assert_eq!(
            e.stderr,
            "flag provided but not defined: -nope\nUsage of p:\n  -format string\n    \tOutput format (default \"json\")\n  -n int\n    \tcount (default 300)\n  -v\tverbose\n"
        );
        let e = parse("p", &flags(), &a(&["-n", "abc"])).err().unwrap();
        assert!(e
            .stderr
            .starts_with("invalid value \"abc\" for flag -n: parse error\n"));
        let e = parse("p", &flags(), &a(&["-h"])).err().unwrap();
        assert_eq!(e.code, 0);
        let e = parse("p", &flags(), &a(&["-format"])).err().unwrap();
        assert!(e.stderr.starts_with("flag needs an argument: -format\n"));
        let e = parse("p", &flags(), &a(&["-v=maybe"])).err().unwrap();
        assert!(e
            .stderr
            .starts_with("invalid boolean value \"maybe\" for -v: parse error\n"));
        let e = parse("p", &flags(), &a(&["---x"])).err().unwrap();
        assert!(e.stderr.starts_with("bad flag syntax: ---x\n"));
    }

    #[test]
    fn parse_int_like_strconv() {
        assert_eq!(parse_int0("1_000"), Ok(1000));
        assert_eq!(parse_int0("0o17"), Ok(15));
        assert_eq!(parse_int0("017"), Ok(15));
        assert_eq!(parse_int0("08"), Err(IntErr::Syntax));
        assert_eq!(parse_int0("-9223372036854775808"), Ok(i64::MIN));
        assert_eq!(parse_int0("9223372036854775808"), Err(IntErr::Range));
        assert_eq!(parse_int0("_1"), Err(IntErr::Syntax));
        assert_eq!(parse_int0(""), Err(IntErr::Syntax));
        assert_eq!(parse_int0("-"), Err(IntErr::Syntax));
    }
}
