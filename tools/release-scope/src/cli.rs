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

//! release_scope.py's command line: its argparse parser, rebuilt rule for
//! rule (abbreviations, `--opt=value`, `--`, the order errors come in) with
//! argparse's usage and help layout at the terminal's width, and main(),
//! with its exit codes: 0 every product it releases is named, 1 one is not
//! (and, as for any uncaught Python exception, a crash), 2 it could not tell.

use crate::pystr::{decimal, PyStr};
use crate::pyval::{Exc, PyVal};
use crate::{json, scope, textio};

const DESCRIPTION: &str = "Does this pull request release a product its title does not name?";

struct Opt {
    strings: &'static [&'static str],
    metavar: &'static str,
    takes_value: bool,
    required: bool,
    help: Option<&'static str>,
}

const OPTS: [Opt; 6] = [
    Opt {
        strings: &["-h", "--help"],
        metavar: "",
        takes_value: false,
        required: false,
        help: Some("show this help message and exit"),
    },
    Opt {
        strings: &["--pr-json"],
        metavar: "PR_JSON",
        takes_value: true,
        required: true,
        help: Some("GitHub's pull request object"),
    },
    Opt {
        strings: &["--commits-json"],
        metavar: "COMMITS_JSON",
        takes_value: true,
        required: true,
        help: Some("a JSON list of the commits' messages"),
    },
    Opt {
        strings: &["--files"],
        metavar: "FILES",
        takes_value: true,
        required: true,
        help: Some("the changed files, one a line"),
    },
    Opt {
        strings: &["--repo-root"],
        metavar: "REPO_ROOT",
        takes_value: true,
        required: false,
        help: None,
    },
    Opt {
        strings: &["--aliases"],
        metavar: "ALIASES",
        takes_value: true,
        required: false,
        help: None,
    },
];
const HELP: usize = 0;

/// What the process around the program provides, gathered by main.rs.
pub struct Env {
    /// argv, decoded as Python decodes it.
    pub argv: Vec<PyStr>,
    /// The aliases.json to use when --aliases is not given.
    pub default_aliases: PyStr,
    /// What shutil.get_terminal_size().columns gives.
    pub columns: i64,
    /// sys.stdout's error handler.
    pub stdout_errors: crate::pystr::Errors,
}

/// What the program wrote and how it ended.
pub struct Outcome {
    pub code: i32,
    pub stdout: Vec<u8>,
    pub stderr: Vec<u8>,
}

/// `int(text)` as shutil reads COLUMNS: Python's whitespace around it, a
/// sign, digits of any script, single underscores between digits.
pub fn py_int(text: &PyStr) -> Option<i64> {
    let s = text.strip();
    let c = s.cps();
    let (negative, digits) = match c.first() {
        Some(&x) if x == '-' as u32 => (true, &c[1..]),
        Some(&x) if x == '+' as u32 => (false, &c[1..]),
        _ => (false, c),
    };
    if digits.is_empty() {
        return None;
    }
    let mut value: i64 = 0;
    let mut previous_digit = false;
    for (i, &ch) in digits.iter().enumerate() {
        if ch == '_' as u32 {
            if !previous_digit || i + 1 == digits.len() {
                return None;
            }
            previous_digit = false;
            continue;
        }
        let d = decimal(ch)?;
        value = value.saturating_mul(10).saturating_add(d as i64);
        previous_digit = true;
    }
    Some(if negative { -value } else { value })
}

/// shutil.get_terminal_size().columns, from COLUMNS and the terminal's own
/// width (None when stdout is not a terminal).
pub fn terminal_columns(columns_env: Option<&PyStr>, tty_columns: Option<i64>) -> i64 {
    let columns = columns_env.and_then(py_int).unwrap_or(0);
    if columns > 0 {
        return columns;
    }
    match tty_columns {
        Some(c) if c > 0 => c,
        _ => 80,
    }
}

fn s(text: &str) -> PyStr {
    PyStr::from(text)
}

fn spaces(n: i64) -> PyStr {
    s(&" ".repeat(n.max(0) as usize))
}

/// textwrap.wrap for text whose words all fit (argparse never asks for a
/// width under 11, and no word here is longer than 8).
fn wrap(text: &str, width: i64) -> Vec<String> {
    let mut lines = Vec::new();
    let mut line = String::new();
    for word in text.split(' ').filter(|w| !w.is_empty()) {
        if line.is_empty() {
            line.push_str(word);
        } else if (line.chars().count() + 1 + word.chars().count()) as i64 <= width {
            line.push(' ');
            line.push_str(word);
        } else {
            lines.push(std::mem::take(&mut line));
            line.push_str(word);
        }
    }
    if !line.is_empty() {
        lines.push(line);
    }
    lines
}

fn invocation(opt: &Opt) -> String {
    if opt.takes_value {
        opt.strings
            .iter()
            .map(|o| format!("{} {}", o, opt.metavar))
            .collect::<Vec<_>>()
            .join(", ")
    } else {
        opt.strings.join(", ")
    }
}

/// HelpFormatter._format_usage at indent 0: "usage: ...\n\n".
fn format_usage_item(prog: &PyStr, width: i64) -> PyStr {
    let prefix = "usage: ";
    let mut opt_parts: Vec<PyStr> = Vec::new();
    for opt in &OPTS {
        let part = if opt.takes_value {
            format!("{} {}", opt.strings[0], opt.metavar)
        } else {
            opt.strings[0].to_string()
        };
        if opt.required {
            for piece in part.split(' ') {
                opt_parts.push(s(piece));
            }
        } else {
            opt_parts.push(s(&format!("[{}]", part)));
        }
    }
    let action_usage = PyStr::join(" ", &opt_parts);
    let mut usage = PyStr::new();
    if !prog.is_empty() {
        usage.push_py(prog);
        usage.push_str(" ");
    }
    usage.push_py(&action_usage);
    let text_width = width;
    let plen = prefix.len() as i64;
    if plen + usage.len() as i64 > text_width {
        let get_lines = |parts: &[PyStr], indent: &PyStr, with_prefix: bool| -> Vec<PyStr> {
            let mut lines: Vec<PyStr> = Vec::new();
            let mut line: Vec<PyStr> = Vec::new();
            let indent_length = indent.len() as i64;
            let mut line_len = if with_prefix {
                plen - 1
            } else {
                indent_length - 1
            };
            for part in parts {
                if line_len + 1 + part.len() as i64 > text_width && !line.is_empty() {
                    let mut l = indent.clone();
                    l.push_py(&PyStr::join(" ", &line));
                    lines.push(l);
                    line.clear();
                    line_len = indent_length - 1;
                }
                line.push(part.clone());
                line_len += part.len() as i64 + 1;
            }
            if !line.is_empty() {
                let mut l = indent.clone();
                l.push_py(&PyStr::join(" ", &line));
                lines.push(l);
            }
            if with_prefix {
                let first = &lines[0];
                lines[0] = first.slice((indent_length as usize).min(first.len()), first.len());
            }
            lines
        };
        let lines: Vec<PyStr> = if (plen + prog.len() as i64) as f64 <= 0.75 * text_width as f64 {
            let indent = spaces(plen + prog.len() as i64 + 1);
            let mut parts = vec![prog.clone()];
            parts.extend(opt_parts.iter().cloned());
            get_lines(&parts, &indent, true)
        } else {
            let indent = spaces(plen);
            let mut lines = get_lines(&opt_parts, &indent, false);
            if lines.len() > 1 {
                lines = get_lines(&opt_parts, &indent, false);
            }
            let mut all = vec![prog.clone()];
            all.extend(lines);
            all
        };
        usage = PyStr::join("\n", &lines);
    }
    let mut out = s(prefix);
    out.push_py(&usage);
    out.push_str("\n\n");
    out
}

/// HelpFormatter.format_help's last step.
fn finish(mut text: PyStr) -> PyStr {
    let mut collapsed = Vec::new();
    let c = text.cps();
    let mut i = 0;
    while i < c.len() {
        if c[i] == 0x0A {
            let mut j = i;
            while j < c.len() && c[j] == 0x0A {
                j += 1;
            }
            let run = j - i;
            collapsed.extend(std::iter::repeat(0x0A).take(if run >= 3 { 2 } else { run }));
            i = j;
        } else {
            collapsed.push(c[i]);
            i += 1;
        }
    }
    text = PyStr(collapsed).strip_chars("\n");
    text.push_str("\n");
    text
}

/// parser.format_usage().
pub fn format_usage(prog: &PyStr, columns: i64) -> PyStr {
    let width = columns - 2;
    let mut text = s("\n");
    text.push_py(&format_usage_item(prog, width));
    text.push_str("\n");
    finish(text)
}

/// parser.format_help().
pub fn format_help(prog: &PyStr, columns: i64) -> PyStr {
    let width = columns - 2;
    let indent: i64 = 2;
    let max_help_position = 24.min((width - 20).max(4));
    let action_max_length = OPTS
        .iter()
        .map(|o| invocation(o).chars().count() as i64 + indent)
        .max()
        .unwrap_or(0);
    let help_position = (action_max_length + 2).min(max_help_position);
    let help_width = (width - help_position).max(11);
    let action_width = help_position - indent - 2;
    let mut items = PyStr::new();
    for opt in &OPTS {
        let header = invocation(opt);
        let header_len = header.chars().count() as i64;
        let indent_first = match opt.help {
            None => {
                items.push_py(&spaces(indent));
                items.push_str(&header);
                items.push_str("\n");
                continue;
            }
            Some(_) if header_len <= action_width => {
                items.push_py(&spaces(indent));
                items.push_str(&header);
                items.push_py(&spaces(action_width - header_len));
                items.push_str("  ");
                0
            }
            Some(_) => {
                items.push_py(&spaces(indent));
                items.push_str(&header);
                items.push_str("\n");
                help_position
            }
        };
        let lines = wrap(opt.help.expect("has help"), help_width);
        for (i, line) in lines.iter().enumerate() {
            items.push_py(&spaces(if i == 0 { indent_first } else { help_position }));
            items.push_str(line);
            items.push_str("\n");
        }
    }
    let mut text = s("\n");
    text.push_py(&format_usage_item(prog, width));
    text.push_str(&wrap(DESCRIPTION, width.max(11)).join("\n"));
    text.push_str("\n\n");
    text.push_str("\noptions:\n");
    text.push_py(&items);
    text.push_str("\n");
    text.push_str("\n");
    finish(text)
}

pub struct Args {
    pub pr_json: PyStr,
    pub commits_json: PyStr,
    pub files: PyStr,
    pub repo_root: PyStr,
    pub aliases: PyStr,
}

enum Parse {
    Args(Args),
    Help,
    Error(PyStr),
}

type Tuple = (Option<usize>, PyStr, Option<PyStr>, Option<PyStr>);

fn option_strings() -> Vec<(&'static str, usize)> {
    OPTS.iter()
        .enumerate()
        .flat_map(|(i, o)| o.strings.iter().map(move |s| (*s, i)))
        .collect()
}

fn find_option(name: &PyStr) -> Option<usize> {
    option_strings()
        .into_iter()
        .find(|(s, _)| name.eq_str(s))
        .map(|(_, i)| i)
}

fn partition_eq(arg: &PyStr) -> (PyStr, Option<PyStr>) {
    match arg.cps().iter().position(|&c| c == '=' as u32) {
        Some(at) => (arg.slice(0, at), Some(arg.slice(at + 1, arg.len()))),
        None => (arg.clone(), None),
    }
}

/// `^-\d+$|^-\d*\.\d+$`.
fn looks_negative(arg: &PyStr) -> bool {
    let c = arg.cps();
    if c.first() != Some(&('-' as u32)) {
        return false;
    }
    let rest = &c[1..];
    let digits = |x: &[u32]| x.iter().all(|&d| decimal(d).is_some());
    if !rest.is_empty() && digits(rest) {
        return true;
    }
    match rest.iter().position(|&d| d == '.' as u32) {
        Some(dot) => digits(&rest[..dot]) && rest.len() > dot + 1 && digits(&rest[dot + 1..]),
        None => false,
    }
}

/// _parse_optional.
fn parse_optional(arg: &PyStr) -> Option<Vec<Tuple>> {
    let c = arg.cps();
    if c.is_empty() || c[0] != '-' as u32 {
        return None;
    }
    if let Some(i) = find_option(arg) {
        return Some(vec![(Some(i), arg.clone(), None, None)]);
    }
    if c.len() == 1 {
        return None;
    }
    let (before, after) = partition_eq(arg);
    if let Some(explicit) = &after {
        if let Some(i) = find_option(&before) {
            return Some(vec![(
                Some(i),
                before,
                Some(s("=")),
                Some(explicit.clone()),
            )]);
        }
    }
    let mut result = Vec::new();
    if c[1] == '-' as u32 {
        let (prefix, explicit) = partition_eq(arg);
        let sep = explicit.as_ref().map(|_| s("="));
        for (name, i) in option_strings() {
            if s(name).cps().starts_with(prefix.cps()) {
                result.push((Some(i), s(name), sep.clone(), explicit.clone()));
            }
        }
    } else {
        let (prefix, explicit) = partition_eq(arg);
        let sep = explicit.as_ref().map(|_| s("="));
        let short_prefix = arg.slice(0, 2);
        let short_explicit = arg.slice(2, arg.len());
        for (name, i) in option_strings() {
            if short_prefix.eq_str(name) {
                result.push((Some(i), s(name), Some(s("")), Some(short_explicit.clone())));
            } else if s(name).cps().starts_with(prefix.cps()) {
                result.push((Some(i), s(name), sep.clone(), explicit.clone()));
            }
        }
    }
    if !result.is_empty() {
        return Some(result);
    }
    if looks_negative(arg) {
        return None;
    }
    if c.contains(&(' ' as u32)) {
        return None;
    }
    Some(vec![(None, arg.clone(), None, None)])
}

fn action_name(i: usize) -> String {
    OPTS[i].strings.join("/")
}

fn argument_error(i: usize, msg: &PyStr) -> PyStr {
    let mut out = s(&format!("argument {}: ", action_name(i)));
    out.push_py(msg);
    out
}

/// ArgumentParser.parse_args for release_scope.py's parser.
fn parse(args: &[PyStr], default_aliases: &PyStr) -> Parse {
    let mut pattern: Vec<char> = Vec::new();
    let mut tuples: Vec<Option<Vec<Tuple>>> = Vec::new();
    let mut after_dashes = false;
    for arg in args {
        if after_dashes {
            pattern.push('A');
            tuples.push(None);
        } else if arg.eq_str("--") {
            pattern.push('-');
            tuples.push(None);
            after_dashes = true;
        } else {
            match parse_optional(arg) {
                None => {
                    pattern.push('A');
                    tuples.push(None);
                }
                Some(t) => {
                    pattern.push('O');
                    tuples.push(Some(t));
                }
            }
        }
    }
    let mut values: [Option<PyStr>; 6] = Default::default();
    let mut seen = [false; 6];
    let mut extras: Vec<PyStr> = Vec::new();
    let option_indices: Vec<usize> = (0..args.len()).filter(|&i| tuples[i].is_some()).collect();
    let max_option = option_indices.last().copied();
    let mut start = 0usize;
    while max_option.map_or(false, |m| start <= m) {
        let next = *option_indices
            .iter()
            .find(|&&i| i >= start)
            .expect("an option follows");
        if start != next {
            extras.extend(args[start..next].iter().cloned());
            start = next;
        }
        // consume_optional
        let found = tuples[start].as_ref().expect("an option");
        if found.len() > 1 {
            let matches: Vec<PyStr> = found.iter().map(|t| t.1.clone()).collect();
            let mut msg = s("ambiguous option: ");
            msg.push_py(&args[start]);
            msg.push_str(" could match ");
            msg.push_py(&PyStr::join(", ", &matches));
            return Parse::Error(msg);
        }
        let (mut action, mut option_string, mut sep, mut explicit) = found[0].clone();
        let mut taken: Vec<(usize, Option<PyStr>)> = Vec::new();
        let stop;
        loop {
            let Some(i) = action else {
                extras.push(args[start].clone());
                stop = start + 1;
                break;
            };
            if let Some(exp) = explicit.clone() {
                let arg_count = if OPTS[i].takes_value { 1 } else { 0 };
                if arg_count == 0 && option_string.cps()[1] != '-' as u32 && !exp.is_empty() {
                    let sep_truthy = sep.as_ref().map_or(false, |x| !x.is_empty());
                    if sep_truthy || exp.cps()[0] == '-' as u32 {
                        let mut msg = s("ignored explicit argument ");
                        msg.push_py(&exp.repr());
                        return Parse::Error(argument_error(i, &msg));
                    }
                    taken.push((i, None));
                    let ch = option_string.cps()[0];
                    let mut next_option = PyStr(vec![ch]);
                    next_option.push(exp.cps()[0]);
                    option_string = next_option;
                    match find_option(&option_string) {
                        Some(j) => {
                            action = Some(j);
                            let rest = exp.slice(1, exp.len());
                            if rest.is_empty() {
                                sep = None;
                                explicit = None;
                            } else if rest.cps()[0] == '=' as u32 {
                                sep = Some(s("="));
                                explicit = Some(rest.slice(1, rest.len()));
                            } else {
                                sep = Some(s(""));
                                explicit = Some(rest);
                            }
                            continue;
                        }
                        None => {
                            let mut extra = PyStr(vec![ch]);
                            extra.push_py(&exp);
                            extras.push(extra);
                            stop = start + 1;
                            break;
                        }
                    }
                } else if arg_count == 1 {
                    stop = start + 1;
                    taken.push((i, Some(exp)));
                    break;
                } else {
                    let mut msg = s("ignored explicit argument ");
                    msg.push_py(&exp.repr());
                    return Parse::Error(argument_error(i, &msg));
                }
            } else {
                let first = start + 1;
                if OPTS[i].takes_value {
                    if pattern.get(first) != Some(&'A') {
                        return Parse::Error(argument_error(i, &s("expected one argument")));
                    }
                    taken.push((i, Some(args[first].clone())));
                    stop = first + 1;
                } else {
                    taken.push((i, None));
                    stop = first;
                }
                break;
            }
        }
        for (i, value) in taken {
            seen[i] = true;
            if i == HELP {
                return Parse::Help;
            }
            values[i] = value;
        }
        start = stop;
    }
    extras.extend(args[start..].iter().cloned());
    let missing: Vec<String> = (0..OPTS.len())
        .filter(|&i| OPTS[i].required && !seen[i])
        .map(action_name)
        .collect();
    if !missing.is_empty() {
        return Parse::Error(s(&format!(
            "the following arguments are required: {}",
            missing.join(", ")
        )));
    }
    if !extras.is_empty() {
        let mut msg = s("unrecognized arguments: ");
        msg.push_py(&PyStr::join(" ", &extras));
        return Parse::Error(msg);
    }
    let take = |i: usize, default: PyStr| values[i].clone().unwrap_or(default);
    Parse::Args(Args {
        pr_json: take(1, PyStr::new()),
        commits_json: take(2, PyStr::new()),
        files: take(3, PyStr::new()),
        repo_root: take(4, s(".")),
        aliases: take(5, default_aliases.clone()),
    })
}

fn read_json(path: &PyStr) -> Result<PyVal, Exc> {
    json::loads(&textio::read_text(path)?)
}

/// find_configs: every release-please-config.json under root, parsed.
fn find_configs(root: &PyStr) -> Result<Vec<(PyStr, PyVal)>, Exc> {
    let mut configs = Vec::new();
    textio::walk(root, |folder| {
        if folder.files.iter().any(|f| f.eq_str(scope::CONFIG_NAME)) {
            let mut place = PyStr::new();
            for name in &folder.names {
                place.push_py(name);
                place.push_str("/");
            }
            place.push_str(scope::CONFIG_NAME);
            let path = textio::join(&folder.path, scope::CONFIG_NAME);
            let value = read_json(&path).map_err(|e| match e {
                Exc::ValueError(msg) => {
                    let mut text = place.clone();
                    text.push_str(" does not parse: ");
                    text.push_py(&msg);
                    Exc::Misconfigured(text)
                }
                other => other,
            })?;
            configs.push((place, value));
        }
        Ok(())
    })?;
    if configs.is_empty() {
        let mut msg = s(&format!("no {} under ", scope::CONFIG_NAME));
        msg.push_py(root);
        return Err(Exc::Misconfigured(msg));
    }
    Ok(configs)
}

/// The traceback an uncaught exception leaves. Python's frames name its own
/// files and lines, which a port cannot have; the last line, the exception,
/// is Python's.
pub fn traceback(e: &Exc) -> String {
    format!(
        "Traceback (most recent call last):\n  (release_scope_rs: Python's stack frames are not reproduced)\n{}: {}\n",
        e.class(),
        e.message().lossy()
    )
}

fn run_checked(args: &Args) -> Result<scope::Verdict, Exc> {
    let files = textio::read_stripped_lines(&args.files)?;
    let pr = read_json(&args.pr_json)?;
    let commits = read_json(&args.commits_json)?;
    let pull = scope::pull_request(&pr, &commits, files)?;
    let components = scope::load_components(find_configs(&args.repo_root)?)?;
    let aliases = scope::load_aliases(&read_json(&args.aliases)?)?;
    // The values are left to the process's exit: dropping one nested
    // thousands deep would recurse as deep.
    std::mem::forget((pr, commits));
    scope::judge(&pull, &components, &aliases)
}

/// release_scope.main().
pub fn main(env: &Env) -> Outcome {
    let mut out = Outcome {
        code: 0,
        stdout: Vec::new(),
        stderr: Vec::new(),
    };
    let prog = {
        let argv0 = env.argv.first().cloned().unwrap_or_default();
        let cut = argv0
            .cps()
            .iter()
            .rposition(|&c| c == '/' as u32)
            .map_or(0, |i| i + 1);
        argv0.slice(cut, argv0.len())
    };
    let crash = |out: &mut Outcome, e: &Exc| {
        out.stderr.extend_from_slice(traceback(e).as_bytes());
        out.code = 1;
    };
    let args = match parse(env.argv.get(1..).unwrap_or(&[]), &env.default_aliases) {
        Parse::Args(args) => args,
        Parse::Help => {
            let text = format_help(&prog, env.columns);
            match crate::pystr::encode_utf8(text.cps(), env.stdout_errors) {
                Ok(bytes) => out.stdout = bytes,
                Err(msg) => crash(&mut out, &Exc::UnicodeEncodeError(s(&msg))),
            }
            return out;
        }
        Parse::Error(msg) => {
            let mut text = format_usage(&prog, env.columns);
            text.push_py(&prog);
            text.push_str(": error: ");
            text.push_py(&msg);
            text.push_str("\n");
            out.stderr = text.lossy().into_bytes();
            out.code = 2;
            return out;
        }
    };
    let verdict = match run_checked(&args) {
        Ok(v) => v,
        Err(e) if e.caught_by_main() => {
            let mut text = s("release-scope: COULD NOT TELL, which is not a pass. ");
            text.push_py(e.message());
            text.push_str("\n");
            out.stderr = text.lossy().into_bytes();
            out.code = 2;
            return out;
        }
        Err(e) => {
            crash(&mut out, &e);
            return out;
        }
    };
    let text = match scope::report(&verdict) {
        Ok(t) => t,
        Err(e) => {
            crash(&mut out, &e);
            return out;
        }
    };
    match crate::pystr::encode_utf8(text.cps(), env.stdout_errors) {
        Ok(mut bytes) => {
            bytes.push(b'\n');
            out.stdout = bytes;
            out.code = if verdict.ok { 0 } else { 1 };
        }
        Err(msg) => crash(&mut out, &Exc::UnicodeEncodeError(s(&msg))),
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn args(list: &[&str]) -> Vec<PyStr> {
        list.iter().map(|a| s(a)).collect()
    }

    fn error(list: &[&str]) -> String {
        match parse(&args(list), &s("aliases.json")) {
            Parse::Error(msg) => msg.lossy(),
            Parse::Help => "HELP".into(),
            Parse::Args(_) => "ARGS".into(),
        }
    }

    #[test]
    fn argparse_rules() {
        assert_eq!(
            error(&[]),
            "the following arguments are required: --pr-json, --commits-json, --files"
        );
        assert_eq!(error(&["--pr", "a", "--c", "b", "--f=c"]), "ARGS");
        assert_eq!(
            error(&["--pr-json"]),
            "argument --pr-json: expected one argument"
        );
        assert_eq!(
            error(&["--pr-json", "-x"]),
            "argument --pr-json: expected one argument"
        );
        assert_eq!(
            error(&["--pr-json", "-1", "--commits-json", "b", "--files", "c"]),
            "ARGS"
        );
        assert_eq!(
            error(&["--=x"]),
            "ambiguous option: --=x could match --help, --pr-json, --commits-json, --files, --repo-root, --aliases"
        );
        assert_eq!(
            error(&["--help=x"]),
            "argument -h/--help: ignored explicit argument 'x'"
        );
        assert_eq!(error(&["-hx"]), "HELP");
        assert_eq!(
            error(&["--pr-json", "a", "--commits-json", "b", "--files", "c", "z"]),
            "unrecognized arguments: z"
        );
    }

    #[test]
    fn usage_wraps_like_argparse() {
        assert_eq!(
            format_usage(&s("release_scope.py"), 80).lossy(),
            "usage: release_scope.py [-h] --pr-json PR_JSON --commits-json COMMITS_JSON\n                        --files FILES [--repo-root REPO_ROOT]\n                        [--aliases ALIASES]\n"
        );
    }

    #[test]
    fn columns_read_like_int() {
        assert_eq!(py_int(&s(" 1_00 ")), Some(100));
        assert_eq!(py_int(&s("1__0")), None);
        assert_eq!(py_int(&s("\u{0661}\u{0662}")), Some(12));
        assert_eq!(terminal_columns(Some(&s("x")), None), 80);
    }
}
