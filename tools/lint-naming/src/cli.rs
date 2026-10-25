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

//! lint_naming.py's command line: argparse's parsing, errors and help text
//! for this one parser, then the scan, the report and the exit code.

use crate::pystr::{basename, dollar, is_decimal, parse_int, py_len, repr};
use crate::scanner::{exe_dir, format_report, LineCache, Scanner};
use crate::textio::{encode, os_to_str, stdout_errors, Errors};
use crate::violation::Severity;
use std::ffi::OsString;
use std::io::Write;

const DESCRIPTION: &str = "Vitruvian Core Monorepo Naming Convention Linter & Enforcement Tool";

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Act {
    Help,
    Root,
    Format,
    Strict,
    Check,
}

/// `parser._option_string_actions`, in insertion order.
const OPTIONS: &[(&str, Act)] = &[
    ("-h", Act::Help),
    ("--help", Act::Help),
    ("--root", Act::Root),
    ("--format", Act::Format),
    ("--strict", Act::Strict),
    ("--check", Act::Check),
];

fn lookup(s: &str) -> Option<Act> {
    OPTIONS.iter().find(|(o, _)| *o == s).map(|(_, a)| *a)
}

impl Act {
    fn nargs(self) -> usize {
        match self {
            Act::Root | Act::Format => 1,
            _ => 0,
        }
    }

    /// `_get_action_name`: the option strings joined by '/'.
    fn name(self) -> &'static str {
        match self {
            Act::Help => "-h/--help",
            Act::Root => "--root",
            Act::Format => "--format",
            Act::Strict => "--strict",
            Act::Check => "--check",
        }
    }

    fn invocation(self) -> &'static str {
        match self {
            Act::Help => "-h, --help",
            Act::Root => "--root ROOT",
            Act::Format => "--format {text,json}",
            Act::Strict => "--strict",
            Act::Check => "--check",
        }
    }

    /// The help text, pre-split into textwrap's chunks.
    fn help_chunks(self) -> &'static [&'static str] {
        match self {
            Act::Help => &[
                "show", " ", "this", " ", "help", " ", "message", " ", "and", " ", "exit",
            ],
            Act::Root => &[
                "Root",
                " ",
                "directory",
                " ",
                "to",
                " ",
                "scan",
                " ",
                "(defaults",
                " ",
                "to",
                " ",
                "BUILD_WORKSPACE_DIRECTORY",
                " ",
                "or",
                " ",
                "current",
                " ",
                "directory)",
            ],
            Act::Format => &[
                "Output", " ", "format", " ", "(text", " ", "or", " ", "json)",
            ],
            Act::Strict => &[
                "Fail", " ", "on", " ", "warnings", " ", "as", " ", "well", " ", "as", " ",
                "errors",
            ],
            Act::Check => &[
                "Exit",
                " ",
                "with",
                " ",
                "non-",
                "zero",
                " ",
                "status",
                " ",
                "if",
                " ",
                "violations",
                " ",
                "are",
                " ",
                "found",
            ],
        }
    }
}

const ACTIONS: &[Act] = &[Act::Help, Act::Root, Act::Format, Act::Strict, Act::Check];
const DESCRIPTION_CHUNKS: &[&str] = &[
    "Vitruvian",
    " ",
    "Core",
    " ",
    "Monorepo",
    " ",
    "Naming",
    " ",
    "Convention",
    " ",
    "Linter",
    " ",
    "&",
    " ",
    "Enforcement",
    " ",
    "Tool",
];

/// textwrap.TextWrapper(width)._wrap_chunks with break_long_words and
/// break_on_hyphens, no indents.
fn wrap_chunks(chunks: &[&str], width: i64) -> Vec<String> {
    let mut rev: Vec<String> = chunks.iter().rev().map(|s| s.to_string()).collect();
    let mut lines: Vec<String> = Vec::new();
    while !rev.is_empty() {
        let mut cur: Vec<String> = Vec::new();
        let mut cur_len: i64 = 0;
        if rev.last().unwrap().trim() == "" && !lines.is_empty() {
            rev.pop();
        }
        while let Some(last) = rev.last() {
            let l = py_len(last) as i64;
            if cur_len + l <= width {
                cur_len += l;
                cur.push(rev.pop().unwrap());
            } else {
                break;
            }
        }
        if let Some(last) = rev.last() {
            if py_len(last) as i64 > width {
                // _handle_long_word
                let space_left = if width < 1 { 1 } else { width - cur_len };
                let chunk: Vec<char> = last.chars().collect();
                let mut end = space_left.max(0) as usize;
                if chunk.len() as i64 > space_left {
                    let limit = end.min(chunk.len());
                    if let Some(h) = chunk[..limit].iter().rposition(|&c| c == '-') {
                        if h > 0 && chunk[..h].iter().any(|&c| c != '-') {
                            end = h + 1;
                        }
                    }
                }
                let end = end.min(chunk.len());
                cur.push(chunk[..end].iter().collect());
                let rest: String = chunk[end..].iter().collect();
                *rev.last_mut().unwrap() = rest;
                cur_len = cur.iter().map(|c| py_len(c) as i64).sum();
            }
        }
        if cur.last().map_or(false, |c| c.trim() == "") {
            cur_len -= py_len(cur.last().unwrap()) as i64;
            cur.pop();
        }
        let _ = cur_len;
        if !cur.is_empty() {
            lines.push(cur.concat());
        }
    }
    lines
}

/// The terminal width argparse's HelpFormatter starts from.
fn terminal_columns() -> i64 {
    if let Some(v) = std::env::var_os("COLUMNS") {
        if let Some(n) = parse_int(&os_to_str(&v)) {
            if n > 0 {
                return n;
            }
        }
    }
    match stdout_winsize_columns() {
        Some(c) if c > 0 => c as i64,
        _ => 80,
    }
}

#[repr(C)]
struct WinSize {
    ws_row: u16,
    ws_col: u16,
    ws_xpixel: u16,
    ws_ypixel: u16,
}

extern "C" {
    fn ioctl(fd: i32, request: std::os::raw::c_ulong, ...) -> i32;
}

#[cfg(target_os = "linux")]
const TIOCGWINSZ: std::os::raw::c_ulong = 0x5413;
#[cfg(not(target_os = "linux"))]
const TIOCGWINSZ: std::os::raw::c_ulong = 0x40087468;

fn stdout_winsize_columns() -> Option<u16> {
    let mut ws = WinSize {
        ws_row: 0,
        ws_col: 0,
        ws_xpixel: 0,
        ws_ypixel: 0,
    };
    // SAFETY: TIOCGWINSZ writes a struct winsize through the pointer.
    let r = unsafe { ioctl(1, TIOCGWINSZ, &mut ws as *mut WinSize) };
    if r == 0 {
        Some(ws.ws_col)
    } else {
        None
    }
}

struct Formatter {
    prog: String,
    width: i64,
}

impl Formatter {
    fn new(prog: &str) -> Formatter {
        Formatter {
            prog: prog.to_string(),
            width: terminal_columns() - 2,
        }
    }

    fn max_help_position(&self) -> i64 {
        24.min((self.width - 20).max(4))
    }

    /// _format_usage with prefix "usage: ", at indent 0.
    fn usage(&self) -> String {
        let prefix = "usage: ";
        let opt_parts = [
            "[-h]",
            "[--root ROOT]",
            "[--format {text,json}]",
            "[--strict]",
            "[--check]",
        ];
        let action_usage = opt_parts.join(" ");
        let prog = self.prog.as_str();
        let usage_parts: Vec<&str> = [prog, action_usage.as_str()]
            .into_iter()
            .filter(|s| !s.is_empty())
            .collect();
        let mut usage = usage_parts.join(" ");
        let text_width = self.width;
        let plen = py_len(prefix) as i64;
        if plen + py_len(&usage) as i64 > text_width {
            let get_lines = |parts: &[&str], indent: &str, prefix: Option<&str>| -> Vec<String> {
                let mut lines: Vec<String> = Vec::new();
                let mut line: Vec<&str> = Vec::new();
                let indent_length = py_len(indent) as i64;
                let mut line_len = match prefix {
                    Some(p) => py_len(p) as i64 - 1,
                    None => indent_length - 1,
                };
                for part in parts {
                    if line_len + 1 + py_len(part) as i64 > text_width && !line.is_empty() {
                        lines.push(format!("{}{}", indent, line.join(" ")));
                        line.clear();
                        line_len = indent_length - 1;
                    }
                    line.push(part);
                    line_len += py_len(part) as i64 + 1;
                }
                if !line.is_empty() {
                    lines.push(format!("{}{}", indent, line.join(" ")));
                }
                if prefix.is_some() {
                    let first: String = lines[0].chars().skip(indent_length as usize).collect();
                    lines[0] = first;
                }
                lines
            };
            let lines: Vec<String> =
                if (plen + py_len(prog) as i64) as f64 <= 0.75 * text_width as f64 {
                    let indent = " ".repeat(py_len(prefix) + py_len(prog) + 1);
                    let mut parts = vec![prog];
                    parts.extend(opt_parts.iter());
                    get_lines(&parts, &indent, Some(prefix))
                } else {
                    let indent = " ".repeat(py_len(prefix));
                    let mut lines = get_lines(&opt_parts, &indent, None);
                    if lines.len() > 1 {
                        lines = get_lines(&opt_parts, &indent, None);
                    }
                    let mut all = vec![prog.to_string()];
                    all.extend(lines);
                    all
                };
            usage = lines.join("\n");
        }
        format!("{}{}\n\n", prefix, usage)
    }

    fn format_usage(&self) -> String {
        let s = self.usage();
        format!("{}\n", s.trim_matches('\n'))
    }

    fn format_help(&self) -> String {
        let mut out = self.usage();
        debug_assert_eq!(DESCRIPTION_CHUNKS.concat(), DESCRIPTION);
        // Description.
        let text_width = self.width.max(11);
        out.push_str(&wrap_chunks(DESCRIPTION_CHUNKS, text_width).join("\n"));
        out.push_str("\n\n");
        // The "options" section, items at indent 2.
        let indent = 2i64;
        let action_max_length = ACTIONS
            .iter()
            .map(|a| py_len(a.invocation()) as i64 + indent)
            .max()
            .unwrap();
        let help_position = (action_max_length + 2).min(self.max_help_position());
        let help_width = (self.width - help_position).max(11);
        let action_width = help_position - indent - 2;
        let mut items = String::new();
        for a in ACTIONS {
            let header = a.invocation();
            let indent_first;
            if py_len(header) as i64 <= action_width {
                let pad = (action_width - py_len(header) as i64).max(0) as usize;
                items.push_str(&format!(
                    "{}{}{}  ",
                    " ".repeat(indent as usize),
                    header,
                    " ".repeat(pad)
                ));
                indent_first = 0;
            } else {
                items.push_str(&format!("{}{}\n", " ".repeat(indent as usize), header));
                indent_first = help_position;
            }
            let lines = wrap_chunks(a.help_chunks(), help_width);
            items.push_str(&format!(
                "{}{}\n",
                " ".repeat(indent_first.unsigned_abs() as usize),
                lines[0]
            ));
            for line in &lines[1..] {
                items.push_str(&format!(
                    "{}{}\n",
                    " ".repeat(help_position.unsigned_abs() as usize),
                    line
                ));
            }
        }
        out.push_str(&format!("\noptions:\n{}\n", items));
        // _long_break_matcher, then strip('\n') + '\n'.
        let mut collapsed = String::with_capacity(out.len());
        let mut run = 0;
        for c in out.chars() {
            if c == '\n' {
                run += 1;
                continue;
            }
            if run > 0 {
                collapsed.push_str(if run >= 3 {
                    "\n\n"
                } else if run == 2 {
                    "\n\n"
                } else {
                    "\n"
                });
                run = 0;
            }
            collapsed.push(c);
        }
        if run > 0 {
            collapsed.push_str(if run >= 2 { "\n\n" } else { "\n" });
        }
        format!("{}\n", collapsed.trim_matches('\n'))
    }
}

/// How a run ends early: help, or an argument error.
enum Exit {
    Help,
    Error(String),
}

#[derive(Debug, PartialEq, Eq)]
pub struct Args {
    pub root: String,
    pub format: String,
    pub strict: bool,
    pub check: bool,
}

type Tuple = (Option<Act>, String, Option<String>, Option<String>);

/// `^-\d+$|^-\d*\.\d+$`
fn looks_negative(s: &str) -> bool {
    dollar(s, |t| {
        let Some(rest) = t.strip_prefix('-') else {
            return false;
        };
        if !rest.is_empty() && rest.chars().all(is_decimal) {
            return true;
        }
        match rest.split_once('.') {
            Some((a, b)) => a.chars().all(is_decimal) && !b.is_empty() && b.chars().all(is_decimal),
            None => false,
        }
    })
}

fn partition_eq(s: &str) -> (&str, Option<&str>) {
    match s.split_once('=') {
        Some((a, b)) => (a, Some(b)),
        None => (s, None),
    }
}

fn get_option_tuples(s: &str) -> Vec<Tuple> {
    let chars: Vec<char> = s.chars().collect();
    let mut result = Vec::new();
    if chars[0] == '-' && chars[1] == '-' {
        let (prefix, explicit) = partition_eq(s);
        for (o, a) in OPTIONS {
            if o.starts_with(prefix) {
                result.push((
                    Some(*a),
                    o.to_string(),
                    explicit.map(|_| "=".to_string()),
                    explicit.map(String::from),
                ));
            }
        }
    } else {
        let (prefix, explicit) = partition_eq(s);
        let short_prefix: String = chars[..2].iter().collect();
        let short_explicit: String = chars[2..].iter().collect();
        for (o, a) in OPTIONS {
            if *o == short_prefix {
                result.push((
                    Some(*a),
                    o.to_string(),
                    Some(String::new()),
                    Some(short_explicit.clone()),
                ));
            } else if o.starts_with(prefix) {
                result.push((
                    Some(*a),
                    o.to_string(),
                    explicit.map(|_| "=".to_string()),
                    explicit.map(String::from),
                ));
            }
        }
    }
    result
}

fn parse_optional(s: &str) -> Option<Vec<Tuple>> {
    if s.is_empty() || !s.starts_with('-') {
        return None;
    }
    if let Some(a) = lookup(s) {
        return Some(vec![(Some(a), s.to_string(), None, None)]);
    }
    if py_len(s) == 1 {
        return None;
    }
    if let (opt, Some(explicit)) = partition_eq(s) {
        if let Some(a) = lookup(opt) {
            return Some(vec![(
                Some(a),
                opt.to_string(),
                Some("=".into()),
                Some(explicit.to_string()),
            )]);
        }
    }
    let tuples = get_option_tuples(s);
    if !tuples.is_empty() {
        return Some(tuples);
    }
    if looks_negative(s) {
        return None;
    }
    if s.contains(' ') {
        return None;
    }
    Some(vec![(None, s.to_string(), None, None)])
}

fn parse_args(argv: &[String], default_root: String) -> Result<Args, Exit> {
    let mut args = Args {
        root: default_root,
        format: "text".into(),
        strict: false,
        check: true,
    };
    let mut indices: std::collections::BTreeMap<usize, Vec<Tuple>> = Default::default();
    let mut pattern: Vec<char> = Vec::new();
    let mut i = 0;
    while i < argv.len() {
        if argv[i] == "--" {
            pattern.push('-');
            for _ in i + 1..argv.len() {
                pattern.push('A');
            }
            break;
        }
        match parse_optional(&argv[i]) {
            None => pattern.push('A'),
            Some(t) => {
                indices.insert(i, t);
                pattern.push('O');
            }
        }
        i += 1;
    }

    let mut extras: Vec<String> = Vec::new();
    let take = |args: &mut Args, act: Act, values: &[String]| -> Result<(), Exit> {
        match act {
            Act::Help => Err(Exit::Help),
            Act::Root => {
                args.root = values[0].clone();
                Ok(())
            }
            Act::Format => {
                let v = &values[0];
                if v != "text" && v != "json" {
                    return Err(Exit::Error(format!(
                        "argument --format: invalid choice: {} (choose from text, json)",
                        repr(v)
                    )));
                }
                args.format = v.clone();
                Ok(())
            }
            Act::Strict => {
                args.strict = true;
                Ok(())
            }
            Act::Check => {
                args.check = true;
                Ok(())
            }
        }
    };

    let mut start = 0usize;
    let max_index = indices.keys().next_back().copied();
    while let Some(max_index) = max_index {
        if start > max_index {
            break;
        }
        let next = *indices.range(start..).next().unwrap().0;
        if start != next {
            extras.extend(argv[start..next].iter().cloned());
            start = next;
        }
        // consume_optional(start)
        let tuples = &indices[&start];
        if tuples.len() > 1 {
            let matches: Vec<&str> = tuples.iter().map(|t| t.1.as_str()).collect();
            return Err(Exit::Error(format!(
                "ambiguous option: {} could match {}",
                argv[start],
                matches.join(", ")
            )));
        }
        let (mut action, mut option_string, mut sep, mut explicit) = tuples[0].clone();
        let mut action_tuples: Vec<(Act, Vec<String>)> = Vec::new();
        let stop;
        loop {
            let Some(act) = action else {
                extras.push(argv[start].clone());
                stop = start + 1;
                break;
            };
            if let Some(exp) = explicit.clone() {
                let arg_count = act.nargs();
                let second = option_string.chars().nth(1).unwrap_or('-');
                if arg_count == 0 && second != '-' && !exp.is_empty() {
                    if sep.as_deref().map_or(false, |s| !s.is_empty()) || exp.starts_with('-') {
                        return Err(Exit::Error(format!(
                            "argument {}: ignored explicit argument {}",
                            act.name(),
                            repr(&exp)
                        )));
                    }
                    action_tuples.push((act, Vec::new()));
                    let ch = option_string.chars().next().unwrap();
                    let first = exp.chars().next().unwrap();
                    option_string = format!("{}{}", ch, first);
                    if let Some(next_act) = lookup(&option_string) {
                        action = Some(next_act);
                        let rest: String = exp.chars().skip(1).collect();
                        if rest.is_empty() {
                            sep = None;
                            explicit = None;
                        } else if let Some(r) = rest.strip_prefix('=') {
                            sep = Some("=".into());
                            explicit = Some(r.to_string());
                        } else {
                            sep = Some(String::new());
                            explicit = Some(rest);
                        }
                    } else {
                        extras.push(format!("{}{}", ch, exp));
                        stop = start + 1;
                        break;
                    }
                } else if arg_count == 1 {
                    action_tuples.push((act, vec![exp]));
                    stop = start + 1;
                    break;
                } else {
                    return Err(Exit::Error(format!(
                        "argument {}: ignored explicit argument {}",
                        act.name(),
                        repr(&exp)
                    )));
                }
            } else {
                let arg_count = act.nargs();
                if arg_count == 1 && pattern.get(start + 1) != Some(&'A') {
                    return Err(Exit::Error(format!(
                        "argument {}: expected one argument",
                        act.name()
                    )));
                }
                let values = argv[start + 1..start + 1 + arg_count].to_vec();
                action_tuples.push((act, values));
                stop = start + 1 + arg_count;
                break;
            }
        }
        for (act, values) in &action_tuples {
            take(&mut args, *act, values)?;
        }
        start = stop;
    }
    extras.extend(argv[start.min(argv.len())..].iter().cloned());
    if !extras.is_empty() {
        return Err(Exit::Error(format!(
            "unrecognized arguments: {}",
            extras.join(" ")
        )));
    }
    Ok(args)
}

/// Write text to stderr as Python does (`backslashreplace`).
pub fn write_stderr(err: &mut dyn Write, s: &str) {
    if let Ok(bytes) = encode(s, Errors::BackslashReplace) {
        let _ = err.write_all(&bytes);
        let _ = err.flush();
    }
}

/// The program: argv (with argv[0]) in, exit status out.
pub fn run(argv: Vec<OsString>, out: &mut dyn Write, err: &mut dyn Write) -> i32 {
    let mut it = argv.into_iter();
    let prog = it
        .next()
        .map(|a| basename(&os_to_str(&a)).to_string())
        .unwrap_or_default();
    let args: Vec<String> = it.map(|a| os_to_str(&a)).collect();
    let default_root = std::env::var_os("BUILD_WORKSPACE_DIRECTORY")
        .map(|v| os_to_str(&v))
        .unwrap_or_else(|| ".".into());

    let parsed = match parse_args(&args, default_root) {
        Ok(a) => a,
        Err(Exit::Help) => {
            let help = Formatter::new(&prog).format_help();
            match encode(&help, stdout_errors()) {
                Ok(bytes) => {
                    let _ = out.write_all(&bytes);
                    let _ = out.flush();
                    return 0;
                }
                Err(e) => return crash(err, &e.message()),
            }
        }
        Err(Exit::Error(message)) => {
            let f = Formatter::new(&prog);
            write_stderr(err, &f.format_usage());
            write_stderr(err, &format!("{}: error: {}\n", prog, message));
            return 2;
        }
    };

    let scanner = Scanner::new(&parsed.root, None, true);
    let mut cache = LineCache::new(exe_dir());
    let violations = scanner.scan(&mut cache, &mut |w| write_stderr(err, &w));
    let report = format_report(&violations, &parsed.format);
    match encode(&format!("{}\n", report), stdout_errors()) {
        Ok(bytes) => {
            let _ = out.write_all(&bytes);
            let _ = out.flush();
        }
        Err(e) => return crash(err, &e.message()),
    }

    if !parsed.check {
        return 0;
    }
    if parsed.strict && !violations.is_empty() {
        return 1;
    }
    if violations.iter().any(|v| v.severity == Severity::Error) {
        1
    } else {
        0
    }
}

/// An uncaught exception: Python prints a traceback and exits 1. The frames
/// name Python's own files, so only the last line can match.
fn crash(err: &mut dyn Write, last_line: &str) -> i32 {
    write_stderr(
        err,
        &format!(
            "Traceback (most recent call last):\n  File \"lint_naming.py\", in main\n{}\n",
            last_line
        ),
    );
    1
}

#[cfg(test)]
mod tests {
    use super::*;

    fn p(args: &[&str]) -> Result<Args, String> {
        let v: Vec<String> = args.iter().map(|s| s.to_string()).collect();
        parse_args(&v, ".".into()).map_err(|e| match e {
            Exit::Help => "HELP".to_string(),
            Exit::Error(m) => m,
        })
    }

    #[test]
    fn parses_like_argparse() {
        assert_eq!(
            p(&["--root", "x", "--format", "json", "--strict"])
                .unwrap()
                .root,
            "x"
        );
        assert_eq!(p(&["--ro=y"]).unwrap().root, "y");
        assert_eq!(p(&["--root", "-1"]).unwrap().root, "-1");
        assert_eq!(p(&["--f", "json"]).unwrap().format, "json");
        assert!(p(&["--s"]).unwrap().strict);
        assert_eq!(p(&["-hx"]).unwrap_err(), "HELP");
        assert_eq!(p(&["--bogus", "-h"]).unwrap_err(), "HELP");
    }

    #[test]
    fn errors_like_argparse() {
        assert_eq!(
            p(&["--format", "xml"]).unwrap_err(),
            "argument --format: invalid choice: 'xml' (choose from text, json)"
        );
        assert_eq!(
            p(&["--root"]).unwrap_err(),
            "argument --root: expected one argument"
        );
        assert_eq!(
            p(&["--root", "-x"]).unwrap_err(),
            "argument --root: expected one argument"
        );
        assert_eq!(
            p(&["--strict=1"]).unwrap_err(),
            "argument --strict: ignored explicit argument '1'"
        );
        assert_eq!(
            p(&["-h=1"]).unwrap_err(),
            "argument -h/--help: ignored explicit argument '1'"
        );
        assert_eq!(
            p(&["a", "--bogus", "b"]).unwrap_err(),
            "unrecognized arguments: a --bogus b"
        );
        assert_eq!(
            p(&["--", "--strict"]).unwrap_err(),
            "unrecognized arguments: -- --strict"
        );
        assert_eq!(
            p(&["--=x"]).unwrap_err(),
            "ambiguous option: --=x could match --help, --root, --format, --strict, --check"
        );
    }

    #[test]
    fn help_wraps_like_textwrap() {
        let f = Formatter {
            prog: "lint_naming.py".into(),
            width: 78,
        };
        let help = f.format_help();
        assert!(help.starts_with(
            "usage: lint_naming.py [-h] [--root ROOT] [--format {text,json}] [--strict]\n                      [--check]\n\n"
        ));
        assert!(help.contains("  --root ROOT           Root directory to scan (defaults to\n                        BUILD_WORKSPACE_DIRECTORY or current directory)\n"));
        let narrow = Formatter {
            prog: "lint_naming.py".into(),
            width: 38,
        };
        assert!(narrow.format_help().contains(
            "  --check         Exit with non-zero\n                  status if violations\n"
        ));
        assert_eq!(wrap_chunks(&["abcdefghij"], 4), ["abcd", "efgh", "ij"]);
    }
}
