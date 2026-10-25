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

//! Python 3.12's argparse, for a parser of optionals only (no positionals):
//! `-h/--help`, flags (`store_true`) and options that take one value. It
//! reads a command line the way argparse does (abbreviations, `--x=value`,
//! `--`, glued short options, negative numbers) and prints the same help,
//! usage and errors, wrapped to the same terminal width. A subcommand
//! (`add_subparsers`) is a parser of its own whose prog is the parent's and
//! the command's name: bump.py always names one first, so the parent never
//! parses anything itself.

use crate::pystr;

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Kind {
    Help,
    Flag,
    Value,
}

#[derive(Clone, Debug)]
pub struct Opt {
    pub strings: Vec<&'static str>,
    pub dest: &'static str,
    pub kind: Kind,
    pub help: Option<String>,
    pub required: bool,
}

impl Opt {
    pub fn help() -> Opt {
        Opt {
            strings: vec!["-h", "--help"],
            dest: "help",
            kind: Kind::Help,
            help: Some("show this help message and exit".into()),
            required: false,
        }
    }

    fn name(&self) -> String {
        self.strings.join("/")
    }

    fn metavar(&self) -> String {
        self.dest.to_uppercase()
    }

    fn invocation(&self) -> String {
        match self.kind {
            Kind::Value => {
                let m = self.metavar();
                self.strings
                    .iter()
                    .map(|s| format!("{} {}", s, m))
                    .collect::<Vec<_>>()
                    .join(", ")
            }
            _ => self.strings.join(", "),
        }
    }
}

pub struct Parser {
    pub prog: String,
    pub description: Option<String>,
    pub opts: Vec<Opt>,
}

/// Parsed values by dest: a flag's presence, an option's last value.
#[derive(Debug, Default)]
pub struct Values {
    pub flags: Vec<&'static str>,
    pub values: Vec<(&'static str, String)>,
}

impl Values {
    pub fn flag(&self, dest: &str) -> bool {
        self.flags.iter().any(|d| *d == dest)
    }

    pub fn value(&self, dest: &str) -> Option<&str> {
        self.values
            .iter()
            .rev()
            .find(|(d, _)| *d == dest)
            .map(|(_, v)| v.as_str())
    }
}

/// argparse ending the program: help (0, on stdout) or an error (2, on
/// stderr).
#[derive(Debug, PartialEq)]
pub struct Exit {
    pub code: i32,
    pub stdout: String,
    pub stderr: String,
}

type Tuple = (Option<usize>, String, Option<String>, Option<String>);

impl Parser {
    fn option_strings(&self) -> Vec<(&'static str, usize)> {
        let mut out = Vec::new();
        for (i, o) in self.opts.iter().enumerate() {
            for s in &o.strings {
                out.push((*s, i));
            }
        }
        out
    }

    fn lookup(&self, s: &str) -> Option<usize> {
        self.option_strings()
            .into_iter()
            .find(|(os, _)| *os == s)
            .map(|(_, i)| i)
    }

    fn parse_optional(&self, arg: &str) -> Option<Vec<Tuple>> {
        let chars: Vec<char> = arg.chars().collect();
        if chars.is_empty() || chars[0] != '-' {
            return None;
        }
        if let Some(i) = self.lookup(arg) {
            return Some(vec![(Some(i), arg.into(), None, None)]);
        }
        if chars.len() == 1 {
            return None;
        }
        if let Some((os, explicit)) = arg.split_once('=') {
            if let Some(i) = self.lookup(os) {
                return Some(vec![(
                    Some(i),
                    os.into(),
                    Some("=".into()),
                    Some(explicit.into()),
                )]);
            }
        }
        let tuples = self.option_tuples(arg, &chars);
        if !tuples.is_empty() {
            return Some(tuples);
        }
        if is_negative_number(&chars) {
            return None;
        }
        if arg.contains(' ') {
            return None;
        }
        Some(vec![(None, arg.into(), None, None)])
    }

    fn option_tuples(&self, arg: &str, chars: &[char]) -> Vec<Tuple> {
        let mut result = Vec::new();
        let (prefix, sep, explicit) = match arg.split_once('=') {
            Some((p, e)) => (p.to_string(), Some("=".to_string()), Some(e.to_string())),
            None => (arg.to_string(), None, None),
        };
        if chars[1] == '-' {
            for (os, i) in self.option_strings() {
                if os.starts_with(&prefix) {
                    result.push((Some(i), os.into(), sep.clone(), explicit.clone()));
                }
            }
        } else {
            let short: String = chars[..2].iter().collect();
            let short_explicit: String = chars[2..].iter().collect();
            for (os, i) in self.option_strings() {
                if os == short {
                    result.push((
                        Some(i),
                        os.into(),
                        Some(String::new()),
                        Some(short_explicit.clone()),
                    ));
                } else if os.starts_with(&prefix) {
                    result.push((Some(i), os.into(), sep.clone(), explicit.clone()));
                }
            }
        }
        result
    }

    pub fn error(&self, msg: &str) -> Exit {
        Exit {
            code: 2,
            stdout: String::new(),
            stderr: format!("{}{}: error: {}\n", self.format_usage(), self.prog, msg),
        }
    }

    fn arg_error(&self, opt: usize, msg: &str) -> Exit {
        self.error(&format!("argument {}: {}", self.opts[opt].name(), msg))
    }

    /// `parser.parse_known_args(args)`: the values and what nothing
    /// consumed. `convert` is the option's `type=`: it returns the type's
    /// name when a value does not convert.
    pub fn parse_known(
        &self,
        args: &[String],
        convert: &dyn Fn(&str, &str) -> Result<(), &'static str>,
    ) -> Result<(Values, Vec<String>), Exit> {
        let mut pattern: Vec<char> = Vec::new();
        let mut indices: Vec<Option<Vec<Tuple>>> = Vec::new();
        let mut after_dashes = false;
        for arg in args {
            if after_dashes {
                pattern.push('A');
                indices.push(None);
            } else if arg == "--" {
                pattern.push('-');
                indices.push(None);
                after_dashes = true;
            } else {
                match self.parse_optional(arg) {
                    None => {
                        pattern.push('A');
                        indices.push(None);
                    }
                    Some(t) => {
                        pattern.push('O');
                        indices.push(Some(t));
                    }
                }
            }
        }

        let mut values = Values::default();
        let mut seen: Vec<bool> = vec![false; self.opts.len()];
        let mut extras: Vec<String> = Vec::new();
        let max_index = indices.iter().rposition(|t| t.is_some());
        let mut start = 0usize;
        if let Some(max_index) = max_index {
            while start <= max_index {
                let next = (start..args.len()).find(|i| indices[*i].is_some()).unwrap();
                if indices[start].is_none() {
                    extras.extend(args[start..next].iter().cloned());
                    start = next;
                }
                start = self.consume_optional(
                    start,
                    args,
                    &pattern,
                    &indices,
                    &mut extras,
                    &mut values,
                    &mut seen,
                    convert,
                )?;
            }
        }
        extras.extend(args[start..].iter().cloned());

        let required: Vec<String> = self
            .opts
            .iter()
            .enumerate()
            .filter(|(i, o)| o.required && !seen[*i])
            .map(|(_, o)| o.name())
            .collect();
        if !required.is_empty() {
            return Err(self.error(&format!(
                "the following arguments are required: {}",
                required.join(", ")
            )));
        }
        Ok((values, extras))
    }

    /// `parser.parse_args(args)`: `parse_known` that refuses anything left.
    pub fn parse(
        &self,
        args: &[String],
        convert: &dyn Fn(&str, &str) -> Result<(), &'static str>,
    ) -> Result<Values, Exit> {
        let (values, extras) = self.parse_known(args, convert)?;
        if !extras.is_empty() {
            return Err(self.unrecognized(&extras));
        }
        Ok(values)
    }

    /// The error `parse_args` gives for arguments nothing consumed.
    pub fn unrecognized(&self, extras: &[String]) -> Exit {
        self.error(&format!("unrecognized arguments: {}", extras.join(" ")))
    }

    #[allow(clippy::too_many_arguments)]
    fn consume_optional(
        &self,
        start: usize,
        args: &[String],
        pattern: &[char],
        indices: &[Option<Vec<Tuple>>],
        extras: &mut Vec<String>,
        values: &mut Values,
        seen: &mut [bool],
        convert: &dyn Fn(&str, &str) -> Result<(), &'static str>,
    ) -> Result<usize, Exit> {
        let tuples = indices[start].as_ref().unwrap();
        if tuples.len() > 1 {
            let options: Vec<&str> = tuples.iter().map(|t| t.1.as_str()).collect();
            return Err(self.error(&format!(
                "ambiguous option: {} could match {}",
                args[start],
                options.join(", ")
            )));
        }
        let (mut action, mut option_string, mut sep, mut explicit) = tuples[0].clone();
        let mut todo: Vec<(usize, Vec<String>)> = Vec::new();
        let stop;
        loop {
            let opt = match action {
                None => {
                    extras.push(args[start].clone());
                    return Ok(start + 1);
                }
                Some(o) => o,
            };
            let nargs = if self.opts[opt].kind == Kind::Value {
                1
            } else {
                0
            };
            if let Some(exp) = explicit.clone() {
                let second = option_string.chars().nth(1);
                if nargs == 0 && second != Some('-') && !exp.is_empty() {
                    let sep_truthy = sep.as_deref().map_or(false, |s| !s.is_empty());
                    if sep_truthy || exp.starts_with('-') {
                        return Err(self.arg_error(
                            opt,
                            &format!("ignored explicit argument {}", pystr::repr_str(&exp)),
                        ));
                    }
                    todo.push((opt, vec![]));
                    let first = exp.chars().next().unwrap();
                    let rest: String = exp.chars().skip(1).collect();
                    let ch = option_string.chars().next().unwrap();
                    option_string = format!("{}{}", ch, first);
                    if let Some(o) = self.lookup(&option_string) {
                        action = Some(o);
                        if rest.is_empty() {
                            sep = None;
                            explicit = None;
                        } else if let Some(r) = rest.strip_prefix('=') {
                            sep = Some("=".into());
                            explicit = Some(r.into());
                        } else {
                            sep = Some(String::new());
                            explicit = Some(rest);
                        }
                    } else {
                        extras.push(format!("{}{}", ch, exp));
                        stop = start + 1;
                        break;
                    }
                } else if nargs == 1 {
                    stop = start + 1;
                    todo.push((opt, vec![exp]));
                    break;
                } else {
                    return Err(self.arg_error(
                        opt,
                        &format!("ignored explicit argument {}", pystr::repr_str(&exp)),
                    ));
                }
            } else {
                let from = start + 1;
                if nargs == 1 {
                    if pattern.get(from) != Some(&'A') {
                        return Err(self.arg_error(opt, "expected one argument"));
                    }
                    todo.push((opt, vec![args[from].clone()]));
                    stop = from + 1;
                } else {
                    todo.push((opt, vec![]));
                    stop = from;
                }
                break;
            }
        }
        for (opt, vals) in todo {
            seen[opt] = true;
            let o = &self.opts[opt];
            match o.kind {
                Kind::Help => {
                    return Err(Exit {
                        code: 0,
                        stdout: self.format_help(),
                        stderr: String::new(),
                    })
                }
                Kind::Flag => values.flags.push(o.dest),
                Kind::Value => {
                    if let Err(type_name) = convert(o.dest, &vals[0]) {
                        return Err(self.arg_error(
                            opt,
                            &format!("invalid {} value: {}", type_name, pystr::repr_str(&vals[0])),
                        ));
                    }
                    values.values.push((o.dest, vals[0].clone()));
                }
            }
        }
        Ok(stop)
    }

    fn usage_parts(&self) -> Vec<String> {
        self.opts
            .iter()
            .map(|o| {
                let part = match o.kind {
                    Kind::Value => format!("{} {}", o.strings[0], o.metavar()),
                    _ => o.strings[0].to_string(),
                };
                if o.required {
                    part
                } else {
                    format!("[{}]", part)
                }
            })
            .collect()
    }

    fn usage_text(&self, width: i64) -> String {
        let prefix = "usage: ";
        let prog = &self.prog;
        let opt_usage = self.usage_parts().join(" ");
        let usage = if opt_usage.is_empty() {
            prog.clone()
        } else {
            format!("{} {}", prog, opt_usage)
        };
        let text_width = width;
        let len = |s: &str| s.chars().count() as i64;
        if len(prefix) + len(&usage) <= text_width {
            return format!("{}{}\n\n", prefix, usage);
        }
        let opt_parts = split_usage_parts(&opt_usage);
        let get_lines = |parts: &[String], indent: &str, prefix: Option<&str>| -> Vec<String> {
            let mut lines: Vec<String> = Vec::new();
            let mut line: Vec<String> = Vec::new();
            let indent_length = len(indent);
            let mut line_len = match prefix {
                Some(p) => len(p) - 1,
                None => indent_length - 1,
            };
            for part in parts {
                if line_len + 1 + len(part) > text_width && !line.is_empty() {
                    lines.push(format!("{}{}", indent, line.join(" ")));
                    line.clear();
                    line_len = indent_length - 1;
                }
                line.push(part.clone());
                line_len += len(part) + 1;
            }
            if !line.is_empty() {
                lines.push(format!("{}{}", indent, line.join(" ")));
            }
            if prefix.is_some() {
                lines[0] = lines[0].chars().skip(indent_length as usize).collect();
            }
            lines
        };
        let lines: Vec<String> = if ((len(prefix) + len(prog)) as f64) <= 0.75 * text_width as f64 {
            let indent = " ".repeat((len(prefix) + len(prog) + 1) as usize);
            if !opt_parts.is_empty() {
                let mut parts = vec![prog.clone()];
                parts.extend(opt_parts.iter().cloned());
                get_lines(&parts, &indent, Some(prefix))
            } else {
                vec![prog.clone()]
            }
        } else {
            let indent = " ".repeat(len(prefix) as usize);
            let mut lines = get_lines(&opt_parts, &indent, None);
            if lines.len() > 1 {
                lines = get_lines(&opt_parts, &indent, None);
            }
            let mut all = vec![prog.clone()];
            all.extend(lines);
            all
        };
        format!("{}{}\n\n", prefix, lines.join("\n"))
    }

    fn finish(text: &str) -> String {
        // argparse squeezes runs of three or more newlines, then trims.
        let mut out = String::new();
        let mut run = 0;
        for c in text.chars() {
            if c == '\n' {
                run += 1;
                if run <= 2 {
                    out.push(c);
                }
            } else {
                run = 0;
                out.push(c);
            }
        }
        let trimmed = out.trim_matches('\n');
        if trimmed.is_empty() {
            String::new()
        } else {
            format!("{}\n", trimmed)
        }
    }

    pub fn format_usage(&self) -> String {
        Self::finish(&self.usage_text(help_width()))
    }

    pub fn format_help(&self) -> String {
        let width = help_width();
        let max_help_position = 24i64.min((width - 20).max(4));
        let mut text = self.usage_text(width);
        if let Some(desc) = &self.description {
            let text_width = width.max(11) as usize;
            text.push_str(&wrap(desc, text_width).join("\n"));
            text.push_str("\n\n");
        }
        let action_max_length = self
            .opts
            .iter()
            .map(|o| o.invocation().chars().count() as i64 + 2)
            .max()
            .unwrap_or(0);
        let help_position = (action_max_length + 2).min(max_help_position);
        let help_wrap = (width - help_position).max(11) as usize;
        let action_width = help_position - 2 - 2;
        let mut items = String::new();
        for o in &self.opts {
            let header = o.invocation();
            let help = o.help.as_deref().unwrap_or("");
            let indent_first;
            if help.is_empty() {
                items.push_str(&format!("  {}\n", header));
                continue;
            } else if header.chars().count() as i64 <= action_width {
                let pad = action_width as usize - header.chars().count();
                items.push_str(&format!("  {}{}  ", header, " ".repeat(pad)));
                indent_first = 0;
            } else {
                items.push_str(&format!("  {}\n", header));
                indent_first = help_position as usize;
            }
            if !pystr::strip(help).is_empty() {
                let lines = wrap(help, help_wrap);
                items.push_str(&format!("{}{}\n", " ".repeat(indent_first), lines[0]));
                for line in &lines[1..] {
                    items.push_str(&format!("{}{}\n", " ".repeat(help_position as usize), line));
                }
            }
        }
        if !items.is_empty() {
            text.push_str("\noptions:\n");
            text.push_str(&items);
            text.push('\n');
        }
        Self::finish(&text)
    }
}

/// `-\d+` or `-\d*\.\d+`, the whole string: argparse reads it as a value.
fn is_negative_number(c: &[char]) -> bool {
    if c.first() != Some(&'-') {
        return false;
    }
    let d = |x: &char| pystr::decimal_value(*x).is_some();
    let rest = &c[1..];
    if !rest.is_empty() && rest.iter().all(d) {
        return true;
    }
    match rest.iter().position(|x| *x == '.') {
        Some(p) => rest[..p].iter().all(d) && p + 1 < rest.len() && rest[p + 1..].iter().all(d),
        None => false,
    }
}

/// `re.findall(r'\(.*?\)+(?=\s|$)|\[.*?\]+(?=\s|$)|\S+', usage)` on a usage
/// string with no newlines.
fn split_usage_parts(s: &str) -> Vec<String> {
    let c: Vec<char> = s.chars().collect();
    let ws = |x: char| pystr::is_space(x);
    let mut out = Vec::new();
    let mut i = 0;
    while i < c.len() {
        if ws(c[i]) {
            i += 1;
            continue;
        }
        let mut matched = None;
        if c[i] == '(' || c[i] == '[' {
            let close = if c[i] == '(' { ')' } else { ']' };
            let mut k = i + 1;
            while k < c.len() && c[k] != '\n' {
                if c[k] == close {
                    let mut m = k;
                    while m < c.len() && c[m] == close {
                        m += 1;
                    }
                    if m == c.len() || ws(c[m]) {
                        matched = Some(m);
                        break;
                    }
                }
                k += 1;
            }
        }
        let end = matched.unwrap_or_else(|| {
            let mut k = i;
            while k < c.len() && !ws(c[k]) {
                k += 1;
            }
            k
        });
        out.push(c[i..end].iter().collect());
        i = end;
    }
    out
}

/// `int(text)` for an environment variable: whitespace around, a sign,
/// digits with single underscores between them.
pub fn py_int(text: &str) -> Option<i64> {
    let t = pystr::strip(text);
    let (neg, body) = match t.chars().next() {
        Some('-') => (true, &t[1..]),
        Some('+') => (false, &t[1..]),
        _ => (false, t),
    };
    if body.is_empty() || body.starts_with('_') || body.ends_with('_') || body.contains("__") {
        return None;
    }
    let mut v: i64 = 0;
    for ch in body.chars() {
        if ch == '_' {
            continue;
        }
        let d = pystr::decimal_value(ch)? as i64;
        v = v.saturating_mul(10).saturating_add(d);
    }
    Some(if neg { -v } else { v })
}

#[cfg(unix)]
fn stdout_columns() -> Option<i64> {
    #[repr(C)]
    struct Winsize {
        row: u16,
        col: u16,
        xpixel: u16,
        ypixel: u16,
    }
    extern "C" {
        fn ioctl(fd: i32, request: std::os::raw::c_ulong, ...) -> i32;
    }
    #[cfg(any(target_os = "macos", target_os = "ios", target_os = "freebsd"))]
    const TIOCGWINSZ: std::os::raw::c_ulong = 0x40087468;
    #[cfg(not(any(target_os = "macos", target_os = "ios", target_os = "freebsd")))]
    const TIOCGWINSZ: std::os::raw::c_ulong = 0x5413;
    let mut ws = Winsize {
        row: 0,
        col: 0,
        xpixel: 0,
        ypixel: 0,
    };
    // SAFETY: TIOCGWINSZ writes one winsize into the struct we pass.
    let rc = unsafe { ioctl(1, TIOCGWINSZ, &mut ws as *mut Winsize) };
    if rc == 0 {
        Some(ws.col as i64)
    } else {
        None
    }
}

#[cfg(not(unix))]
fn stdout_columns() -> Option<i64> {
    None
}

/// `shutil.get_terminal_size().columns - 2`, argparse's width.
pub fn help_width() -> i64 {
    let env_int = |name: &str| {
        std::env::var(name)
            .ok()
            .and_then(|v| py_int(&v))
            .unwrap_or(0)
    };
    let mut columns = env_int("COLUMNS");
    let lines = env_int("LINES");
    if columns <= 0 || lines <= 0 {
        let size = stdout_columns().unwrap_or(80);
        if columns <= 0 {
            columns = if size == 0 { 80 } else { size };
        }
    }
    columns - 2
}

fn is_letter(c: char) -> bool {
    c == '_' || (c.is_alphanumeric() && pystr::decimal_value(c).is_none())
}

/// textwrap's chunks: runs of spaces, and words broken after a hyphen that
/// sits between letters (`goof-ball` gives `goof-` and `ball`).
fn chunks(text: &str) -> Vec<String> {
    let c: Vec<char> = text.chars().collect();
    let mut out = Vec::new();
    let mut i = 0;
    while i < c.len() {
        if c[i] == ' ' {
            let mut k = i;
            while k < c.len() && c[k] == ' ' {
                k += 1;
            }
            out.push(c[i..k].iter().collect());
            i = k;
            continue;
        }
        let mut end = None;
        let mut k = i + 1;
        while k <= c.len() {
            if k == c.len() || c[k] == ' ' {
                end = Some(k);
                break;
            }
            // A hyphen at k ends a chunk at k+1 when argparse's lookarounds
            // hold: two letters (or letter-hyphen-letter) before, and a
            // letter, an optional hyphen and a letter after.
            if c[k] == '-' {
                let before = (k >= 2 && is_letter(c[k - 2]) && is_letter(c[k - 1]))
                    || (k >= 3 && is_letter(c[k - 3]) && c[k - 2] == '-' && is_letter(c[k - 1]));
                let after = k + 1 < c.len()
                    && is_letter(c[k + 1])
                    && ((k + 2 < c.len() && is_letter(c[k + 2]))
                        || (k + 3 < c.len() && c[k + 2] == '-' && is_letter(c[k + 3])));
                if before && after && k > i {
                    end = Some(k + 1);
                    break;
                }
            }
            k += 1;
        }
        let end = end.unwrap();
        out.push(c[i..end].iter().collect());
        i = end;
    }
    out
}

/// `textwrap.wrap(text, width)` after argparse's whitespace squeeze.
pub fn wrap(text: &str, width: usize) -> Vec<String> {
    let mut squeezed = String::new();
    let mut in_ws = false;
    for ch in text.chars() {
        if matches!(ch, ' ' | '\t' | '\n' | '\r' | '\u{b}' | '\u{c}') {
            if !in_ws {
                squeezed.push(' ');
            }
            in_ws = true;
        } else {
            squeezed.push(ch);
            in_ws = false;
        }
    }
    let text = squeezed.trim_matches(' ');
    let mut rev: Vec<String> = chunks(text);
    rev.reverse();
    let len = |s: &str| s.chars().count();
    let blank = |s: &str| pystr::strip(s).is_empty();
    let mut lines: Vec<String> = Vec::new();
    while !rev.is_empty() {
        let mut cur: Vec<String> = Vec::new();
        let mut cur_len = 0usize;
        if blank(rev.last().unwrap()) && !lines.is_empty() {
            rev.pop();
        }
        while let Some(last) = rev.last() {
            let l = len(last);
            if cur_len + l <= width {
                cur_len += l;
                cur.push(rev.pop().unwrap());
            } else {
                break;
            }
        }
        if let Some(last) = rev.last() {
            if len(last) > width {
                // _handle_long_word
                let space_left = if width < 1 { 1 } else { width - cur_len };
                let chunk: Vec<char> = last.chars().collect();
                let mut end = space_left;
                if chunk.len() > space_left {
                    if let Some(h) = chunk[..space_left].iter().rposition(|c| *c == '-') {
                        if h > 0 && chunk[..h].iter().any(|c| *c != '-') {
                            end = h + 1;
                        }
                    }
                }
                let end = end.min(chunk.len());
                cur.push(chunk[..end].iter().collect());
                let n = rev.len();
                rev[n - 1] = chunk[end..].iter().collect();
                cur_len = cur.iter().map(|s| len(s)).sum();
            }
        }
        if let Some(last) = cur.last() {
            if blank(last) {
                cur_len -= len(last);
                cur.pop();
            }
        }
        let _ = cur_len;
        if !cur.is_empty() {
            lines.push(cur.concat());
        }
    }
    lines
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parser() -> Parser {
        Parser {
            prog: "tool.py".into(),
            description: Some("Do a thing".into()),
            opts: vec![
                Opt::help(),
                Opt {
                    strings: vec!["--file"],
                    dest: "file",
                    kind: Kind::Value,
                    help: Some("Path to it".into()),
                    required: false,
                },
                Opt {
                    strings: vec!["--dry-run"],
                    dest: "dry_run",
                    kind: Kind::Flag,
                    help: Some("Print only".into()),
                    required: false,
                },
            ],
        }
    }

    fn run(args: &[&str]) -> Result<Values, Exit> {
        let a: Vec<String> = args.iter().map(|s| s.to_string()).collect();
        parser().parse(&a, &|_, _| Ok(()))
    }

    #[test]
    fn abbreviations_and_equals() {
        let v = run(&["--fi=x", "--dry"]).unwrap();
        assert_eq!(v.value("file"), Some("x"));
        assert!(v.flag("dry_run"));
        let v = run(&["--file", "-5"]).unwrap();
        assert_eq!(v.value("file"), Some("-5"));
    }

    #[test]
    fn errors() {
        let e = run(&["--file"]).unwrap_err();
        assert_eq!(e.code, 2);
        assert!(e
            .stderr
            .ends_with("tool.py: error: argument --file: expected one argument\n"));
        let e = run(&["--dry-run=1"]).unwrap_err();
        assert!(e
            .stderr
            .ends_with("argument --dry-run: ignored explicit argument '1'\n"));
        let e = run(&["x", "--", "--dry-run"]).unwrap_err();
        assert!(e
            .stderr
            .ends_with("unrecognized arguments: x -- --dry-run\n"));
        let e = run(&["--=a"]).unwrap_err();
        assert!(e
            .stderr
            .contains("ambiguous option: --=a could match --help, --file, --dry-run"));
    }

    #[test]
    fn help_and_wrap() {
        let e = run(&["-hx"]).unwrap_err();
        assert_eq!(e.code, 0);
        assert!(e.stdout.starts_with(
            "usage: tool.py [-h] [--file FILE] [--dry-run]\n\nDo a thing\n\noptions:\n"
        ));
        assert_eq!(wrap("aa bb-cc dd", 6), vec!["aa bb-", "cc dd"]);
        assert_eq!(wrap("abcdefghij", 4), vec!["abcd", "efgh", "ij"]);
        assert_eq!(py_int(" +1_0 "), Some(10));
        assert_eq!(py_int("1__0"), None);
    }
}
