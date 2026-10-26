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

//! sdk_codegen.py's command line as Python 3.12's argparse reads it: `-h`,
//! `--check`, `--out OUT`, `--package PACKAGE`, each long one by any prefix,
//! `=` or a separate word for a value, and the same usage, help and errors,
//! wrapped to the same width.

use crate::pystr;
use crate::textwrap;

const DESCRIPTION: &str = "Writes each kit's generated types from the protocol's schemas.";
const PACKAGE_HELP: &str = "the SDK's folder; found from the repository when left out";

/// The options, in the order argparse registered their strings.
const STRINGS: [(&str, Opt); 5] = [
    ("-h", Opt::Help),
    ("--help", Opt::Help),
    ("--check", Opt::Check),
    ("--out", Opt::Out),
    ("--package", Opt::Package),
];

#[derive(Clone, Copy, Debug, PartialEq)]
enum Opt {
    Help,
    Check,
    Out,
    Package,
}

impl Opt {
    fn name(self) -> &'static str {
        match self {
            Opt::Help => "-h/--help",
            Opt::Check => "--check",
            Opt::Out => "--out",
            Opt::Package => "--package",
        }
    }

    fn takes_value(self) -> bool {
        matches!(self, Opt::Out | Opt::Package)
    }
}

#[derive(Debug, Default, PartialEq)]
pub struct Options {
    pub check: bool,
    pub out: Option<String>,
    pub package: Option<String>,
}

/// What parsing the command line came to.
#[derive(Debug, PartialEq)]
pub enum Parsed {
    Run(Options),
    /// Print this to stdout and exit 0.
    Help(String),
    /// Print this to stderr and exit 2.
    Error(String),
}

type Tuple = (Option<Opt>, String, Option<String>, Option<String>);

fn lookup(s: &str) -> Option<Opt> {
    STRINGS.iter().find(|(k, _)| *k == s).map(|(_, o)| *o)
}

fn partition(s: &str) -> (String, Option<String>, String) {
    match s.split_once('=') {
        Some((a, b)) => (a.to_string(), Some("=".into()), b.to_string()),
        None => (s.to_string(), None, String::new()),
    }
}

fn option_tuples(arg: &str) -> Vec<Tuple> {
    let chars: Vec<char> = arg.chars().collect();
    let mut result = Vec::new();
    let (prefix, sep, explicit) = partition(arg);
    let (sep, explicit) = match sep {
        Some(s) => (Some(s), Some(explicit)),
        None => (None, None),
    };
    if chars[1] == '-' {
        for (s, o) in STRINGS {
            if s.starts_with(&prefix) {
                result.push((Some(o), s.to_string(), sep.clone(), explicit.clone()));
            }
        }
    } else {
        let short: String = chars[..2].iter().collect();
        let short_explicit: String = chars[2..].iter().collect();
        for (s, o) in STRINGS {
            if s == short {
                result.push((
                    Some(o),
                    s.to_string(),
                    Some(String::new()),
                    Some(short_explicit.clone()),
                ));
            } else if s.starts_with(&prefix) {
                result.push((Some(o), s.to_string(), sep.clone(), explicit.clone()));
            }
        }
    }
    result
}

fn negative_number(s: &str) -> bool {
    let rest = match s.strip_prefix('-') {
        Some(r) => r,
        None => return false,
    };
    let all_digits = |t: &str| t.chars().all(|c| c.is_ascii_digit());
    if !rest.is_empty() && all_digits(rest) {
        return true;
    }
    match rest.split_once('.') {
        Some((a, b)) => all_digits(a) && !b.is_empty() && all_digits(b),
        None => false,
    }
}

/// `_parse_optional`: None for an argument, else what it may be.
fn parse_optional(arg: &str) -> Option<Vec<Tuple>> {
    if arg.is_empty() || !arg.starts_with('-') {
        return None;
    }
    if let Some(o) = lookup(arg) {
        return Some(vec![(Some(o), arg.to_string(), None, None)]);
    }
    if pystr::len(arg) == 1 {
        return None;
    }
    let (head, sep, explicit) = partition(arg);
    if sep.is_some() {
        if let Some(o) = lookup(&head) {
            return Some(vec![(Some(o), head, sep, Some(explicit))]);
        }
    }
    let tuples = option_tuples(arg);
    if !tuples.is_empty() {
        return Some(tuples);
    }
    if negative_number(arg) || arg.contains(' ') {
        return None;
    }
    Some(vec![(None, arg.to_string(), None, None)])
}

/// argparse's width: `$COLUMNS`, else the terminal's, else 80; less two.
pub fn width_from(columns: Option<&str>, terminal: Option<usize>) -> usize {
    let cols = columns
        .and_then(|c| c.trim().parse::<i64>().ok())
        .filter(|&c| c > 0)
        .map(|c| c as usize)
        .or(terminal)
        .unwrap_or(80);
    cols.saturating_sub(2).max(0)
}

fn usage(prog: &str, width: usize) -> String {
    let parts = ["[-h]", "[--check]", "[--out OUT]", "[--package PACKAGE]"];
    let prefix = "usage: ";
    let full = format!("{} {}", prog, parts.join(" "));
    let text_width = width as isize;
    if (pystr::len(prefix) + pystr::len(&full)) as isize <= text_width {
        return format!("{}{}", prefix, full);
    }
    let get_lines = |parts: &[String], indent: &str, prefix: Option<&str>| -> Vec<String> {
        let mut lines = Vec::new();
        let mut line: Vec<String> = Vec::new();
        let indent_length = pystr::len(indent) as isize;
        let mut line_len = match prefix {
            Some(p) => pystr::len(p) as isize - 1,
            None => indent_length - 1,
        };
        for part in parts {
            if line_len + 1 + pystr::len(part) as isize > text_width && !line.is_empty() {
                lines.push(format!("{}{}", indent, line.join(" ")));
                line.clear();
                line_len = indent_length - 1;
            }
            line.push(part.clone());
            line_len += pystr::len(part) as isize + 1;
        }
        if !line.is_empty() {
            lines.push(format!("{}{}", indent, line.join(" ")));
        }
        if prefix.is_some() && !lines.is_empty() {
            lines[0] = lines[0].chars().skip(pystr::len(indent)).collect();
        }
        lines
    };
    let opt_parts: Vec<String> = parts.iter().map(|s| s.to_string()).collect();
    let lines: Vec<String> =
        if ((pystr::len(prefix) + pystr::len(prog)) as f64) <= 0.75 * text_width as f64 {
            let indent = " ".repeat(pystr::len(prefix) + pystr::len(prog) + 1);
            let mut with_prog = vec![prog.to_string()];
            with_prog.extend(opt_parts.iter().cloned());
            get_lines(&with_prog, &indent, Some(prefix))
        } else {
            let indent = " ".repeat(pystr::len(prefix));
            let mut lines = vec![prog.to_string()];
            lines.extend(get_lines(&opt_parts, &indent, None));
            lines
        };
    format!("{}{}", prefix, lines.join("\n"))
}

/// `parser.format_help()`.
pub fn help(prog: &str, width: usize) -> String {
    let mut out = format!("{}\n\n", usage(prog, width));
    let text_width = width.max(11);
    out.push_str(&textwrap::wrap(DESCRIPTION, text_width).join("\n"));
    out.push_str("\n\noptions:\n");
    let max_help_position = 24usize.min((width as isize - 20).max(4) as usize);
    // The longest invocation, "--package PACKAGE", is 17 wide, at indent 2.
    let help_position = (17 + 2 + 2).min(max_help_position);
    let help_width = (width as isize - help_position as isize).max(11) as usize;
    let action_width = help_position as isize - 2 - 2;
    let actions: [(&str, Option<&str>); 4] = [
        ("-h, --help", Some("show this help message and exit")),
        ("--check", None),
        ("--out OUT", None),
        ("--package PACKAGE", Some(PACKAGE_HELP)),
    ];
    for (header, text) in actions {
        match text {
            None => out.push_str(&format!("  {}\n", header)),
            Some(text) => {
                let lines = textwrap::wrap(text, help_width);
                let indent_first;
                if pystr::len(header) as isize <= action_width {
                    out.push_str(&format!(
                        "  {}  ",
                        pystr::ljust(header, action_width as usize)
                    ));
                    indent_first = 0;
                } else {
                    out.push_str(&format!("  {}\n", header));
                    indent_first = help_position;
                }
                if let Some(first) = lines.first() {
                    out.push_str(&format!("{}{}\n", " ".repeat(indent_first), first));
                    for line in &lines[1..] {
                        out.push_str(&format!("{}{}\n", " ".repeat(help_position), line));
                    }
                }
            }
        }
    }
    out
}

fn error(prog: &str, width: usize, message: &str) -> Parsed {
    Parsed::Error(format!(
        "{}\n{}: error: {}\n",
        usage(prog, width),
        prog,
        message
    ))
}

/// `parser.parse_args(args)`.
pub fn parse(prog: &str, args: &[String], width: usize) -> Parsed {
    // The pattern of the arguments: an option ('O'), an argument ('A'), or
    // the `--` after which everything is an argument.
    let mut tuples: Vec<Option<Vec<Tuple>>> = Vec::new();
    let mut pattern: Vec<char> = Vec::new();
    let mut separated = false;
    for arg in args {
        if separated {
            pattern.push('A');
            tuples.push(None);
        } else if arg == "--" {
            separated = true;
            pattern.push('-');
            tuples.push(None);
        } else {
            let t = parse_optional(arg);
            pattern.push(if t.is_some() { 'O' } else { 'A' });
            tuples.push(t);
        }
    }
    let mut options = Options::default();
    let mut extras: Vec<String> = Vec::new();
    let mut i = 0;
    while i < args.len() {
        let found = match &tuples[i] {
            None => {
                extras.push(args[i].clone());
                i += 1;
                continue;
            }
            Some(t) => t,
        };
        if found.len() > 1 {
            let names: Vec<&str> = found.iter().map(|t| t.1.as_str()).collect();
            return error(
                prog,
                width,
                &format!(
                    "ambiguous option: {} could match {}",
                    args[i],
                    names.join(", ")
                ),
            );
        }
        let (action, option_string, sep, explicit) = found[0].clone();
        let mut action = match action {
            None => {
                extras.push(args[i].clone());
                i += 1;
                continue;
            }
            Some(a) => a,
        };
        let mut option_string = option_string;
        let mut sep = sep;
        let mut explicit = explicit;
        let mut queued: Vec<(Opt, Option<String>)> = Vec::new();
        let stop;
        loop {
            match explicit.clone() {
                Some(arg) => {
                    let count = if action.takes_value() { 1 } else { 0 };
                    let second = option_string.chars().nth(1).unwrap_or('-');
                    if count == 0 && second != '-' && !arg.is_empty() {
                        if sep.as_deref().map(|s| !s.is_empty()).unwrap_or(false)
                            || arg.starts_with('-')
                        {
                            return error(
                                prog,
                                width,
                                &format!(
                                    "argument {}: ignored explicit argument {}",
                                    action.name(),
                                    pystr::repr_str(&arg)
                                ),
                            );
                        }
                        queued.push((action, None));
                        let mut rest = arg.chars();
                        let first = rest.next().unwrap();
                        option_string = format!("-{}", first);
                        match lookup(&option_string) {
                            Some(next) => {
                                action = next;
                                let remaining: String = rest.collect();
                                if remaining.is_empty() {
                                    sep = None;
                                    explicit = None;
                                } else if let Some(r) = remaining.strip_prefix('=') {
                                    sep = Some("=".into());
                                    explicit = Some(r.to_string());
                                } else {
                                    sep = Some(String::new());
                                    explicit = Some(remaining);
                                }
                            }
                            None => {
                                extras.push(format!("-{}", arg));
                                stop = i + 1;
                                break;
                            }
                        }
                    } else if count == 1 {
                        queued.push((action, Some(arg)));
                        stop = i + 1;
                        break;
                    } else {
                        return error(
                            prog,
                            width,
                            &format!(
                                "argument {}: ignored explicit argument {}",
                                action.name(),
                                pystr::repr_str(&arg)
                            ),
                        );
                    }
                }
                None => {
                    if action.takes_value() {
                        if pattern.get(i + 1) == Some(&'A') {
                            queued.push((action, Some(args[i + 1].clone())));
                            stop = i + 2;
                        } else {
                            return error(
                                prog,
                                width,
                                &format!("argument {}: expected one argument", action.name()),
                            );
                        }
                    } else {
                        queued.push((action, None));
                        stop = i + 1;
                    }
                    break;
                }
            }
        }
        for (action, value) in queued {
            match action {
                Opt::Help => return Parsed::Help(help(prog, width)),
                Opt::Check => options.check = true,
                Opt::Out => options.out = value,
                Opt::Package => options.package = value,
            }
        }
        i = stop;
    }
    if !extras.is_empty() {
        return error(
            prog,
            width,
            &format!("unrecognized arguments: {}", extras.join(" ")),
        );
    }
    Parsed::Run(options)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn run(args: &[&str]) -> Parsed {
        let args: Vec<String> = args.iter().map(|s| s.to_string()).collect();
        parse("sdk_codegen.py", &args, 78)
    }

    fn err(args: &[&str]) -> String {
        match run(args) {
            Parsed::Error(e) => e.lines().nth(1).unwrap().to_string(),
            other => panic!("{other:?}"),
        }
    }

    #[test]
    fn reads_options() {
        assert_eq!(run(&[]), Parsed::Run(Options::default()));
        assert_eq!(
            run(&["--ch", "--out=x", "--p", "y", "--out", "-1"]),
            Parsed::Run(Options {
                check: true,
                out: Some("-1".into()),
                package: Some("y".into())
            })
        );
        assert!(matches!(run(&["-hx"]), Parsed::Help(_)));
        assert!(matches!(run(&["--he"]), Parsed::Help(_)));
    }

    #[test]
    fn errors_are_pythons() {
        assert_eq!(
            err(&["--out"]),
            "sdk_codegen.py: error: argument --out: expected one argument"
        );
        assert_eq!(
            err(&["--", "x", "y"]),
            "sdk_codegen.py: error: unrecognized arguments: -- x y"
        );
        assert_eq!(
            err(&["--=x"]),
            "sdk_codegen.py: error: ambiguous option: --=x could match --help, --check, --out, --package"
        );
        assert_eq!(
            err(&["--check=1", "a", "-x"]),
            "sdk_codegen.py: error: argument --check: ignored explicit argument '1'"
        );
        assert_eq!(
            err(&["a", "-x"]),
            "sdk_codegen.py: error: unrecognized arguments: a -x"
        );
        assert_eq!(
            err(&["--out", "--check"]),
            "sdk_codegen.py: error: argument --out: expected one argument"
        );
        assert_eq!(
            err(&["-h-x"]),
            "sdk_codegen.py: error: argument -h/--help: ignored explicit argument '-x'"
        );
    }

    #[test]
    fn help_wraps_as_python_does() {
        assert_eq!(
            help("sdk_codegen.py", 78),
            "usage: sdk_codegen.py [-h] [--check] [--out OUT] [--package PACKAGE]\n\nWrites each kit's generated types from the protocol's schemas.\n\noptions:\n  -h, --help         show this help message and exit\n  --check\n  --out OUT\n  --package PACKAGE  the SDK's folder; found from the repository when left out\n"
        );
        assert_eq!(
            help("sdk_codegen.py", 38),
            "usage: sdk_codegen.py [-h] [--check]\n                      [--out OUT]\n                      [--package PACKAGE]\n\nWrites each kit's generated types from\nthe protocol's schemas.\n\noptions:\n  -h, --help      show this help\n                  message and exit\n  --check\n  --out OUT\n  --package PACKAGE\n                  the SDK's folder;\n                  found from the\n                  repository when left\n                  out\n"
        );
        assert!(help("sdk_codegen.py", 18).starts_with(
            "usage: sdk_codegen.py\n       [-h]\n       [--check]\n       [--out OUT]\n       [--package PACKAGE]\n\nWrites each kit's\ngenerated types\n"
        ));
    }
}
