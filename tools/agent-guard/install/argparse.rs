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

//! install.py's command line, parsed as its argparse parser parses it
//! (Python 3.12): the same abbreviations, errors, usage and help text.

use crate::sys::{terminal_columns, Ctx};

pub const PROG: &str = "bazel run //tools/agent-guard:install --";
pub const DESCRIPTION: &str =
    "agent-guard: the per-user backstop, and checking the repo's own wiring.";

#[derive(Clone, Copy, PartialEq, Debug)]
enum Act {
    Help,
    Check,
    Uninstall,
    DryRun,
    Mode,
    Home,
    Workspace,
}

/// `parser._option_string_actions`, in the order argparse registered them.
const OPTIONS: &[(&str, Act)] = &[
    ("-h", Act::Help),
    ("--help", Act::Help),
    ("--check", Act::Check),
    ("--uninstall", Act::Uninstall),
    ("--dry-run", Act::DryRun),
    ("--mode", Act::Mode),
    ("--home", Act::Home),
    ("--workspace", Act::Workspace),
];

/// The help listing: (invocation, help). --mode/--home/--workspace are SUPPRESSed.
const HELP: &[(&str, &str)] = &[
    ("-h, --help", "show this help message and exit"),
    ("--check", "exit 1 unless the repo hooks and the backstop are wired and answer"),
    (
        "--uninstall",
        "remove the backstop (and any old per-user copy) from ~/.claude and ~/.gemini (the log is kept)",
    ),
    ("--dry-run", "print what would change, write nothing"),
];
const USAGE_PARTS: &[&str] = &["[-h]", "[--check]", "[--uninstall]", "[--dry-run]"];

#[derive(Default, Debug, Clone)]
pub struct Args {
    pub check: bool,
    pub uninstall: bool,
    pub dry_run: bool,
    pub mode: Vec<String>,
    pub home: Option<String>,
    pub workspace: Option<String>,
}

pub enum Parsed {
    Run(Args),
    /// Help was printed (0) or a usage error (2).
    Exit(i32),
}

fn act_of(opt: &str) -> Option<Act> {
    OPTIONS.iter().find(|(o, _)| *o == opt).map(|(_, a)| *a)
}

/// `'/'.join(action.option_strings)`.
fn act_name(a: Act) -> String {
    let names: Vec<&str> = OPTIONS
        .iter()
        .filter(|(_, x)| *x == a)
        .map(|(o, _)| *o)
        .collect();
    names.join("/")
}

enum Cls {
    /// A known option: (action, the option string, sep was '=', explicit argument).
    Opt(Act, String, bool, Option<String>),
    /// Looks like an option but is none ('O' with no action).
    Unknown,
    /// A positional ('A').
    Arg,
    /// '--': it and everything after are positional.
    DashDash,
}

fn is_negative_number(a: &str) -> bool {
    // ^-\d+$|^-\d*\.\d+$
    let rest = &a[1..];
    if !rest.is_empty() && rest.chars().all(|c| c.is_ascii_digit()) {
        return true;
    }
    match rest.split_once('.') {
        Some((int, frac)) => {
            int.chars().all(|c| c.is_ascii_digit())
                && !frac.is_empty()
                && frac.chars().all(|c| c.is_ascii_digit())
        }
        None => false,
    }
}

/// `parser._parse_optional(arg)`; Err(message) when an abbreviation is ambiguous.
fn classify(a: &str) -> Result<Cls, String> {
    if a.is_empty() || !a.starts_with('-') {
        return Ok(Cls::Arg);
    }
    if let Some(act) = act_of(a) {
        return Ok(Cls::Opt(act, a.to_string(), false, None));
    }
    if a.chars().count() == 1 {
        return Ok(Cls::Arg);
    }
    if let Some((prefix, explicit)) = a.split_once('=') {
        if let Some(act) = act_of(prefix) {
            return Ok(Cls::Opt(
                act,
                prefix.to_string(),
                true,
                Some(explicit.to_string()),
            ));
        }
    }
    let mut tuples: Vec<(Act, String, bool, Option<String>)> = Vec::new();
    if a.starts_with("--") {
        let (prefix, explicit) = match a.split_once('=') {
            Some((p, e)) => (p, Some(e.to_string())),
            None => (a, None),
        };
        for (opt, act) in OPTIONS {
            if opt.starts_with(prefix) {
                tuples.push((*act, opt.to_string(), explicit.is_some(), explicit.clone()));
            }
        }
    } else {
        let short: String = a.chars().take(2).collect();
        let short_explicit: String = a.chars().skip(2).collect();
        for (opt, act) in OPTIONS {
            if *opt == short {
                tuples.push((*act, opt.to_string(), false, Some(short_explicit.clone())));
            } else if opt.starts_with(a) {
                tuples.push((*act, opt.to_string(), false, None));
            }
        }
    }
    if tuples.len() > 1 {
        let matches: Vec<String> = tuples.iter().map(|t| t.1.clone()).collect();
        return Err(format!(
            "ambiguous option: {} could match {}",
            a,
            matches.join(", ")
        ));
    }
    if let Some((act, opt, sep, explicit)) = tuples.pop() {
        return Ok(Cls::Opt(act, opt, sep, explicit));
    }
    if is_negative_number(a) || a.contains(' ') {
        return Ok(Cls::Arg);
    }
    Ok(Cls::Unknown)
}

pub fn parse(ctx: &Ctx, argv: &[String]) -> Parsed {
    let width = terminal_columns(ctx).saturating_sub(2);
    let fail = |msg: &str| {
        ctx.eprint(&format!(
            "{}{}: error: {}\n",
            format_usage(width),
            PROG,
            msg
        ));
        Parsed::Exit(2)
    };
    let mut cls = Vec::new();
    let mut after = false;
    for a in argv {
        if after {
            cls.push(Cls::Arg);
        } else if a == "--" {
            after = true;
            cls.push(Cls::DashDash);
        } else {
            match classify(a) {
                Ok(c) => cls.push(c),
                Err(msg) => return fail(&msg),
            }
        }
    }
    let mut args = Args::default();
    let mut extras: Vec<String> = Vec::new();
    let mut i = 0;
    while i < argv.len() {
        match &cls[i] {
            Cls::DashDash => {
                extras.extend(argv[i..].iter().cloned());
                break;
            }
            Cls::Arg | Cls::Unknown => extras.push(argv[i].clone()),
            Cls::Opt(act, opt, sep, explicit) => {
                let takes_value = matches!(act, Act::Mode | Act::Home | Act::Workspace);
                let value = if takes_value {
                    match explicit {
                        Some(v) => v.clone(),
                        None => match (cls.get(i + 1), argv.get(i + 1)) {
                            (Some(Cls::Arg), Some(v)) => {
                                i += 1;
                                v.clone()
                            }
                            _ => {
                                return fail(&format!(
                                    "argument {}: expected one argument",
                                    act_name(*act)
                                ))
                            }
                        },
                    }
                } else {
                    if let Some(ex) = explicit {
                        // A single-dash flag with more letters runs on (-hx is -h, -x);
                        // anything else with an argument is an error.
                        let single = !opt.starts_with("--");
                        if !(single && !*sep && !ex.is_empty() && !ex.starts_with('-')) {
                            return fail(&format!(
                                "argument {}: ignored explicit argument {}",
                                act_name(*act),
                                agent_guard::pyutil::py_repr_str(ex)
                            ));
                        }
                    }
                    String::new()
                };
                match act {
                    Act::Help => {
                        ctx.print(&format_help(width).trim_end_matches('\n').to_string());
                        return Parsed::Exit(0);
                    }
                    Act::Check => args.check = true,
                    Act::Uninstall => args.uninstall = true,
                    Act::DryRun => args.dry_run = true,
                    Act::Mode => args.mode.push(value),
                    Act::Home => args.home = Some(value),
                    Act::Workspace => args.workspace = Some(value),
                }
            }
        }
        i += 1;
    }
    if !extras.is_empty() {
        return fail(&format!("unrecognized arguments: {}", extras.join(" ")));
    }
    Parsed::Run(args)
}

/// `parser.format_usage()`.
fn format_usage(width: usize) -> String {
    let prefix = "usage: ";
    let text_width = width;
    let one_line = format!("{} {}", PROG, USAGE_PARTS.join(" "));
    if prefix.len() + one_line.len() <= text_width {
        return format!("{}{}\n", prefix, one_line);
    }
    let get_lines = |parts: &[&str], indent: &str, prefix: Option<&str>| -> Vec<String> {
        let mut lines = Vec::new();
        let mut line: Vec<&str> = Vec::new();
        let mut line_len = match prefix {
            Some(p) => p.len() as isize - 1,
            None => indent.len() as isize - 1,
        };
        for part in parts {
            if line_len + 1 + part.len() as isize > text_width as isize && !line.is_empty() {
                lines.push(format!("{}{}", indent, line.join(" ")));
                line.clear();
                line_len = indent.len() as isize - 1;
            }
            line.push(part);
            line_len += part.len() as isize + 1;
        }
        if !line.is_empty() {
            lines.push(format!("{}{}", indent, line.join(" ")));
        }
        if prefix.is_some() && !lines.is_empty() {
            lines[0] = lines[0][indent.len()..].to_string();
        }
        lines
    };
    let lines: Vec<String> = if (prefix.len() + PROG.len()) as f64 <= 0.75 * text_width as f64 {
        let indent = " ".repeat(prefix.len() + PROG.len() + 1);
        let mut parts = vec![PROG];
        parts.extend_from_slice(USAGE_PARTS);
        get_lines(&parts, &indent, Some(prefix))
    } else {
        let indent = " ".repeat(prefix.len());
        let mut lines = get_lines(USAGE_PARTS, &indent, None);
        if lines.len() > 1 {
            lines = get_lines(USAGE_PARTS, &indent, None);
        }
        let mut all = vec![PROG.to_string()];
        all.extend(lines);
        all
    };
    format!("{}{}\n", prefix, lines.join("\n"))
}

/// `parser.format_help()`.
fn format_help(width: usize) -> String {
    let mut out = format_usage(width);
    out.push('\n');
    for line in wrap(DESCRIPTION, width.max(11)) {
        out.push_str(&line);
        out.push('\n');
    }
    out.push_str("\noptions:\n");
    let max_help_position = 24usize.min(width.saturating_sub(20).max(4));
    let action_max = HELP.iter().map(|(inv, _)| inv.len() + 2).max().unwrap_or(0);
    let help_position = (action_max + 2).min(max_help_position);
    let help_width = width.saturating_sub(help_position).max(11);
    let action_width = help_position.saturating_sub(4);
    for (inv, help) in HELP {
        let lines = wrap(help, help_width);
        if inv.len() <= action_width {
            out.push_str(&format!("  {:<w$}  ", inv, w = action_width));
            out.push_str(lines.first().map(|s| s.as_str()).unwrap_or(""));
            out.push('\n');
        } else {
            out.push_str(&format!("  {}\n", inv));
            if let Some(first) = lines.first() {
                out.push_str(&format!("{}{}\n", " ".repeat(help_position), first));
            }
        }
        for line in lines.iter().skip(1) {
            out.push_str(&format!("{}{}\n", " ".repeat(help_position), line));
        }
    }
    out
}

/// `textwrap.wrap(text, width)` for these texts: words, broken after a
/// hyphen between letters (`per-user`), long words broken to fit.
fn wrap(text: &str, width: usize) -> Vec<String> {
    let mut chunks: Vec<String> = Vec::new();
    for (wi, word) in text.split_whitespace().enumerate() {
        if wi > 0 {
            chunks.push(" ".into());
        }
        let c: Vec<char> = word.chars().collect();
        let mut start = 0;
        for k in 2..c.len() {
            let breaks = c[k] == '-'
                && c[k - 1].is_alphabetic()
                && c[k - 2].is_alphabetic()
                && k + 2 < c.len() + 1
                && c.get(k + 1).map_or(false, |x| x.is_alphabetic())
                && (c.get(k + 2).map_or(false, |x| x.is_alphabetic())
                    || (c.get(k + 2) == Some(&'-')
                        && c.get(k + 3).map_or(false, |x| x.is_alphabetic())));
            if breaks {
                chunks.push(c[start..=k].iter().collect());
                start = k + 1;
            }
        }
        chunks.push(c[start..].iter().collect());
    }
    chunks.reverse();
    let mut lines = Vec::new();
    while !chunks.is_empty() {
        let mut cur: Vec<String> = Vec::new();
        let mut cur_len = 0;
        if chunks.last().map_or(false, |c| c.trim().is_empty()) && !lines.is_empty() {
            chunks.pop();
        }
        while let Some(c) = chunks.last() {
            let l = c.chars().count();
            if cur_len + l <= width {
                cur_len += l;
                cur.push(chunks.pop().unwrap());
            } else {
                break;
            }
        }
        if let Some(c) = chunks.last().cloned() {
            if c.chars().count() > width {
                let space_left = if width < 1 { 1 } else { width - cur_len };
                if space_left > 0 || cur.is_empty() {
                    let take = space_left.max(1).min(c.chars().count());
                    cur.push(c.chars().take(take).collect());
                    let rest: String = c.chars().skip(take).collect();
                    *chunks.last_mut().unwrap() = rest;
                }
            }
        }
        if cur.last().map_or(false, |c| c.trim().is_empty()) {
            cur.pop();
        }
        if !cur.is_empty() {
            lines.push(cur.concat());
        }
        if chunks.last().map_or(false, |c| c.is_empty()) {
            chunks.pop();
        }
    }
    lines
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn help_at_80_columns_is_pythons() {
        // COLUMNS=80 python3.12 install.py --help
        assert_eq!(
            format_help(78),
            "usage: bazel run //tools/agent-guard:install -- [-h] [--check] [--uninstall]
                                                [--dry-run]

agent-guard: the per-user backstop, and checking the repo's own wiring.

options:
  -h, --help   show this help message and exit
  --check      exit 1 unless the repo hooks and the backstop are wired and
               answer
  --uninstall  remove the backstop (and any old per-user copy) from ~/.claude
               and ~/.gemini (the log is kept)
  --dry-run    print what would change, write nothing
"
        );
    }

    #[test]
    fn wraps_after_a_hyphen() {
        // textwrap.wrap(...) in Python 3.12.
        assert_eq!(wrap("old per-user copy", 12), vec!["old per-user", "copy"]);
        assert_eq!(wrap("old per-user copy", 10), vec!["old per-", "user copy"]);
        assert_eq!(
            wrap(HELP[2].1, 30),
            vec![
                "remove the backstop (and any",
                "old per-user copy) from",
                "~/.claude and ~/.gemini (the",
                "log is kept)"
            ]
        );
    }
}
