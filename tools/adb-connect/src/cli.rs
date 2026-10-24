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

//! The command line, parsed and documented exactly as Python 3.12's
//! argparse does for adb_connect.py's parser.
//!
//! Same flags, same abbreviations (`--dis` is ambiguous, `--al` is
//! `--all`), same `-dfold` / `--device=fold` forms, same type errors and
//! "unrecognized arguments", and byte-identical `--help` and usage text at
//! any terminal width (`ArgumentDefaultsHelpFormatter`, wrapped by a port of
//! `textwrap`). The algorithm follows CPython's `_parse_known_args`.

use crate::py::{parse_float, parse_int, repr_str};
use std::collections::HashMap;

pub const DESCRIPTION: &str = "Auto-discover Android Wireless Debugging port and connect adb.";

#[derive(Clone, Copy, Debug, PartialEq)]
enum Nargs {
    /// `store_true` and `help`: no argument.
    Zero,
    /// The default: exactly one argument.
    One,
    /// `nargs="?"`: an optional argument (`const` when absent).
    Optional,
}

#[derive(Clone, Copy, Debug, PartialEq)]
enum Dest {
    Help,
    Device,
    All,
    Discover,
    Pair,
    PrintSerial,
    Ip,
    NoTailscale,
    DisconnectFirst,
    Tcpip,
    Status,
    Json,
    Timeout,
}

struct Spec {
    opts: &'static [&'static str],
    nargs: Nargs,
    metavar: &'static str,
    /// The help text after `%(default)s` expansion.
    help: &'static str,
    dest: Dest,
}

const SPECS: &[Spec] = &[
    Spec {
        opts: &["-h", "--help"],
        nargs: Nargs::Zero,
        metavar: "",
        help: "show this help message and exit",
        dest: Dest::Help,
    },
    Spec {
        opts: &["-d", "--device"],
        nargs: Nargs::One,
        metavar: "DEVICE",
        help: "Filter by device alias (fold, pixel4, watch, tv), model, codename, or serial. (default: None)",
        dest: Dest::Device,
    },
    Spec {
        opts: &["--all"],
        nargs: Nargs::Zero,
        metavar: "",
        help: "Connect all discovered Wireless Debugging phones (_adb-tls-connect._tcp). (default: False)",
        dest: Dest::All,
    },
    Spec {
        opts: &["--discover", "--list"],
        nargs: Nargs::Zero,
        metavar: "",
        help: "Discover all mDNS Android devices on the network and show their aliases and status. (default: False)",
        dest: Dest::Discover,
    },
    Spec {
        opts: &["--pair"],
        nargs: Nargs::One,
        metavar: "CODE",
        help: "Pair with a device using a 6-digit pairing code (auto-discovers pairing port via mDNS). (default: None)",
        dest: Dest::Pair,
    },
    Spec {
        opts: &["--print-serial"],
        nargs: Nargs::Zero,
        metavar: "",
        help: "Print only the resolved ADB transport identifier (for ANDROID_SERIAL) and exit. (default: False)",
        dest: Dest::PrintSerial,
    },
    Spec {
        opts: &["--ip"],
        nargs: Nargs::One,
        metavar: "IP",
        help: "Override target IP address instead of auto-resolving. (default: None)",
        dest: Dest::Ip,
    },
    Spec {
        opts: &["--no-tailscale"],
        nargs: Nargs::Zero,
        metavar: "",
        help: "Disable Tailscale IP preference; use direct local network IP. (default: False)",
        dest: Dest::NoTailscale,
    },
    Spec {
        opts: &["--disconnect-first"],
        nargs: Nargs::Zero,
        metavar: "",
        help: "Disconnect existing ADB session(s) before attempting to discover and connect. (default: False)",
        dest: Dest::DisconnectFirst,
    },
    Spec {
        opts: &["--tcpip"],
        nargs: Nargs::Optional,
        metavar: "TCPIP",
        help: "Switch ADB to static TCP/IP mode on specified port (default: 5555) once connected. (default: None)",
        dest: Dest::Tcpip,
    },
    Spec {
        opts: &["--status"],
        nargs: Nargs::Zero,
        metavar: "",
        help: "Show currently connected ADB devices and exit. (default: False)",
        dest: Dest::Status,
    },
    Spec {
        opts: &["--json"],
        nargs: Nargs::Zero,
        metavar: "",
        help: "Output structured JSON instead of human-readable text. (default: False)",
        dest: Dest::Json,
    },
    Spec {
        opts: &["--timeout"],
        nargs: Nargs::One,
        metavar: "TIMEOUT",
        help: "mDNS discovery timeout in seconds. (default: 1.5)",
        dest: Dest::Timeout,
    },
];

/// The parsed namespace.
#[derive(Clone, Debug, PartialEq)]
pub struct Args {
    pub device: Option<String>,
    pub all: bool,
    pub discover: bool,
    pub pair: Option<String>,
    pub print_serial: bool,
    pub ip: Option<String>,
    pub no_tailscale: bool,
    pub disconnect_first: bool,
    /// `--tcpip`, as an int's canonical digits (`const` is 5555).
    pub tcpip: Option<String>,
    pub status: bool,
    pub json: bool,
    pub timeout: f64,
}

impl Default for Args {
    fn default() -> Self {
        Args {
            device: None,
            all: false,
            discover: false,
            pair: None,
            print_serial: false,
            ip: None,
            no_tailscale: false,
            disconnect_first: false,
            tcpip: None,
            status: false,
            json: false,
            timeout: 1.5,
        }
    }
}

/// The parser's verdict.
#[derive(Debug, PartialEq)]
pub enum Parsed {
    Run(Args),
    /// argparse exits: `--help` (0, text on stdout) or an error (2, stderr).
    Exit {
        code: i32,
        stdout: String,
        stderr: String,
    },
}

/// `shutil.get_terminal_size().columns`, given `$COLUMNS` and the width
/// of the terminal on stdout (None when stdout is not a terminal).
pub fn terminal_columns(env_columns: Option<&str>, tty_columns: Option<u16>) -> i64 {
    let from_env = env_columns
        .and_then(parse_int)
        .and_then(|d| d.parse::<i64>().ok())
        .unwrap_or(0);
    if from_env > 0 {
        return from_env;
    }
    match tty_columns {
        Some(c) if c > 0 => i64::from(c),
        _ => 80,
    }
}

// ---------------------------------------------------------------- help --

fn char_len(st: &str) -> i64 {
    st.chars().count() as i64
}

fn invocation(spec: &Spec) -> String {
    match spec.nargs {
        Nargs::Zero => spec.opts.join(", "),
        Nargs::One => spec
            .opts
            .iter()
            .map(|o| format!("{} {}", o, spec.metavar))
            .collect::<Vec<_>>()
            .join(", "),
        Nargs::Optional => spec
            .opts
            .iter()
            .map(|o| format!("{} [{}]", o, spec.metavar))
            .collect::<Vec<_>>()
            .join(", "),
    }
}

fn usage_part(spec: &Spec) -> String {
    let first = spec.opts[0];
    match spec.nargs {
        Nargs::Zero => format!("[{}]", first),
        Nargs::One => format!("[{} {}]", first, spec.metavar),
        Nargs::Optional => format!("[{} [{}]]", first, spec.metavar),
    }
}

/// `HelpFormatter._format_usage`: "usage: ...\n\n".
fn usage_block(prog: &str, width: i64) -> String {
    let prefix = "usage: ";
    let opt_parts: Vec<String> = SPECS.iter().map(usage_part).collect();
    let usage = format!("{} {}", prog, opt_parts.join(" "));
    let text_width = width;
    let plen = char_len(prefix);
    if plen + char_len(&usage) <= text_width {
        return format!("{}{}\n\n", prefix, usage);
    }
    let get_lines = |parts: &[String], indent: &str, with_prefix: bool| -> Vec<String> {
        let mut lines: Vec<String> = Vec::new();
        let mut line: Vec<&str> = Vec::new();
        let indent_len = char_len(indent);
        let mut line_len = if with_prefix {
            plen - 1
        } else {
            indent_len - 1
        };
        for part in parts {
            let part_len = char_len(part);
            if line_len + 1 + part_len > text_width && !line.is_empty() {
                lines.push(format!("{}{}", indent, line.join(" ")));
                line.clear();
                line_len = indent_len - 1;
            }
            line.push(part);
            line_len += part_len + 1;
        }
        if !line.is_empty() {
            lines.push(format!("{}{}", indent, line.join(" ")));
        }
        if with_prefix && !lines.is_empty() {
            lines[0] = lines[0].chars().skip(indent.chars().count()).collect();
        }
        lines
    };
    let lines: Vec<String> = if (plen + char_len(prog)) as f64 <= 0.75 * text_width as f64 {
        let indent = " ".repeat((plen + char_len(prog) + 1) as usize);
        let mut parts = vec![prog.to_string()];
        parts.extend(opt_parts.iter().cloned());
        get_lines(&parts, &indent, true)
    } else {
        let indent = " ".repeat(plen as usize);
        let mut lines = get_lines(&opt_parts, &indent, false);
        if lines.len() > 1 {
            lines = get_lines(&opt_parts, &indent, false);
        }
        let mut all = vec![prog.to_string()];
        all.extend(lines);
        all
    };
    format!("{}{}\n\n", prefix, lines.join("\n"))
}

fn is_word(c: char) -> bool {
    c.is_alphanumeric() || c == '_'
}

fn is_letter(c: char) -> bool {
    is_word(c) && !c.is_numeric()
}

fn is_word_punct(c: char) -> bool {
    is_word(c) || "!\"'&.,?".contains(c)
}

fn is_tw_space(c: char) -> bool {
    matches!(c, '\t' | '\n' | '\x0b' | '\x0c' | '\r' | ' ')
}

/// `TextWrapper.wordsep_re.split(text)`, empty pieces dropped.
fn wordsep_chunks(text: &str) -> Vec<String> {
    let c: Vec<char> = text.chars().collect();
    let n = c.len();
    let at = |i: usize| c.get(i).copied();
    let letter_at = |i: Option<usize>| i.and_then(at).map_or(false, is_letter);
    let hyphens_then_word = |from: usize| {
        let mut j = from;
        while at(j) == Some('-') {
            j += 1;
        }
        j - from >= 2 && at(j).map_or(false, is_word)
    };
    let mut chunks = Vec::new();
    let mut p = 0;
    while p < n {
        if is_tw_space(c[p]) {
            let mut e = p;
            while e < n && is_tw_space(c[e]) {
                e += 1;
            }
            chunks.push(c[p..e].iter().collect());
            p = e;
            continue;
        }
        if c[p] == '-' && p > 0 && is_word_punct(c[p - 1]) && hyphens_then_word(p) {
            let mut e = p;
            while at(e) == Some('-') {
                e += 1;
            }
            chunks.push(c[p..e].iter().collect());
            p = e;
            continue;
        }
        let mut e = p + 1;
        loop {
            if at(e) == Some('-') {
                let behind = (letter_at(e.checked_sub(2)) && letter_at(e.checked_sub(1)))
                    || (letter_at(e.checked_sub(3))
                        && e >= 2
                        && at(e - 2) == Some('-')
                        && letter_at(e.checked_sub(1)));
                let ahead = letter_at(Some(e + 1))
                    && (letter_at(Some(e + 2))
                        || (at(e + 2) == Some('-') && letter_at(Some(e + 3))));
                if behind && ahead {
                    chunks.push(c[p..=e].iter().collect());
                    p = e + 1;
                    break;
                }
            }
            if e >= n || is_tw_space(c[e]) {
                chunks.push(c[p..e].iter().collect());
                p = e;
                break;
            }
            if is_word_punct(c[e - 1]) && hyphens_then_word(e) {
                chunks.push(c[p..e].iter().collect());
                p = e;
                break;
            }
            e += 1;
        }
    }
    chunks
}

/// `textwrap.wrap(text, width)` with the defaults argparse uses.
pub fn wrap(text: &str, width: usize) -> Vec<String> {
    let munged: String = text
        .chars()
        .map(|c| if is_tw_space(c) { ' ' } else { c })
        .collect();
    let mut chunks: Vec<String> = wordsep_chunks(&munged);
    chunks.reverse();
    let clen = |st: &str| st.chars().count();
    let mut lines: Vec<String> = Vec::new();
    while !chunks.is_empty() {
        let mut cur: Vec<String> = Vec::new();
        let mut cur_len = 0usize;
        if !lines.is_empty()
            && chunks
                .last()
                .map_or(false, |c| c.trim_matches(' ').is_empty())
        {
            chunks.pop();
        }
        while let Some(last) = chunks.last() {
            let l = clen(last);
            if cur_len + l <= width {
                cur_len += l;
                cur.push(chunks.pop().expect("checked non-empty"));
            } else {
                break;
            }
        }
        if chunks.last().map_or(false, |c| clen(c) > width) {
            // _handle_long_word
            let space_left = if width < 1 { 1 } else { width - cur_len };
            let chunk: Vec<char> = chunks.last().expect("checked").chars().collect();
            let mut end = space_left;
            if chunk.len() > space_left {
                if let Some(h) = chunk[..space_left.min(chunk.len())]
                    .iter()
                    .rposition(|&c| c == '-')
                {
                    if h > 0 && chunk[..h].iter().any(|&c| c != '-') {
                        end = h + 1;
                    }
                }
            }
            cur.push(chunk[..end].iter().collect());
            let rest: String = chunk[end..].iter().collect();
            *chunks.last_mut().expect("checked") = rest;
        }
        if cur.last().map_or(false, |c| c.trim_matches(' ').is_empty()) {
            cur.pop();
        }
        if !cur.is_empty() {
            lines.push(cur.concat());
        }
    }
    lines
}

fn format_action(
    spec: &Spec,
    width: i64,
    action_max_length: i64,
    max_help_position: i64,
) -> String {
    let current_indent: i64 = 2;
    let help_position = (action_max_length + 2).min(max_help_position);
    let help_width = (width - help_position).max(11);
    let action_width = help_position - current_indent - 2;
    let header = invocation(spec);
    let pad = |n: i64| " ".repeat(n.unsigned_abs() as usize);
    let mut out = String::new();
    out.push_str(&pad(current_indent));
    out.push_str(&header);
    // A short invocation shares its line with the help; a long one
    // gets a line of its own and the help starts under it.
    let indent_first = if char_len(&header) <= action_width {
        out.push_str(&pad(action_width - char_len(&header)));
        out.push_str("  ");
        0
    } else {
        out.push('\n');
        help_position
    };
    let lines = wrap(spec.help, help_width as usize);
    for (i, line) in lines.iter().enumerate() {
        out.push_str(&pad(if i == 0 { indent_first } else { help_position }));
        out.push_str(line);
        out.push('\n');
    }
    out
}

/// `parser.format_usage()`.
pub fn format_usage(prog: &str, columns: i64) -> String {
    let block = usage_block(prog, columns - 2);
    format!("{}\n", block.trim_matches('\n'))
}

/// `parser.format_help()`.
pub fn format_help(prog: &str, columns: i64) -> String {
    let width = columns - 2;
    let max_help_position = 24.min((width - 20).max(4));
    let action_max_length = SPECS
        .iter()
        .map(|s| char_len(&invocation(s)) + 2)
        .max()
        .unwrap_or(0);
    let mut out = usage_block(prog, width);
    let desc = wrap(DESCRIPTION, width.max(11) as usize).join("\n");
    out.push_str(&desc);
    out.push_str("\n\n");
    out.push_str("\noptions:\n");
    for spec in SPECS {
        out.push_str(&format_action(
            spec,
            width,
            action_max_length,
            max_help_position,
        ));
    }
    out.push('\n');
    while out.contains("\n\n\n") {
        out = out.replace("\n\n\n", "\n\n");
    }
    format!("{}\n", out.trim_matches('\n'))
}

/// `parser.error(message)`: the stderr text (exit status 2).
pub fn error_text(prog: &str, columns: i64, message: &str) -> String {
    format!(
        "{}{}: error: {}\n",
        format_usage(prog, columns),
        prog,
        message
    )
}

// ------------------------------------------------------------- parsing --

/// One interpretation of an option-like argument:
/// `(spec index or None, option string, sep, explicit argument)`.
type OptTuple = (Option<usize>, String, Option<String>, Option<String>);

fn option_strings() -> Vec<(&'static str, usize)> {
    let mut v = Vec::new();
    for (i, spec) in SPECS.iter().enumerate() {
        for o in spec.opts {
            v.push((*o, i));
        }
    }
    v
}

fn lookup(opt: &str) -> Option<usize> {
    option_strings()
        .into_iter()
        .find(|(o, _)| *o == opt)
        .map(|(_, i)| i)
}

fn is_negative_number(arg: &str) -> bool {
    // ^-\d+$|^-\d*\.\d+$  ($ also matches before a final newline)
    let a = arg.strip_suffix('\n').unwrap_or(arg);
    let Some(rest) = a.strip_prefix('-') else {
        return false;
    };
    let digits = |x: &str| !x.is_empty() && x.chars().all(|c| c.is_ascii_digit());
    if digits(rest) {
        return true;
    }
    match rest.split_once('.') {
        Some((a, b)) => (a.is_empty() || digits(a)) && digits(b),
        None => false,
    }
}

fn partition_eq(st: &str) -> (String, Option<String>, Option<String>) {
    match st.split_once('=') {
        Some((a, b)) => (a.to_string(), Some("=".into()), Some(b.to_string())),
        None => (st.to_string(), None, None),
    }
}

fn get_option_tuples(arg: &str) -> Vec<OptTuple> {
    let chars: Vec<char> = arg.chars().collect();
    let mut result = Vec::new();
    if chars[0] == '-' && chars[1] == '-' {
        let (prefix, sep, explicit) = partition_eq(arg);
        for (o, i) in option_strings() {
            if o.starts_with(&prefix) {
                result.push((Some(i), o.to_string(), sep.clone(), explicit.clone()));
            }
        }
    } else {
        let (prefix, sep, explicit) = partition_eq(arg);
        let short_prefix: String = chars[..2].iter().collect();
        let short_explicit: String = chars[2..].iter().collect();
        for (o, i) in option_strings() {
            if o == short_prefix {
                result.push((
                    Some(i),
                    o.to_string(),
                    Some(String::new()),
                    Some(short_explicit.clone()),
                ));
            } else if o.starts_with(&prefix) {
                result.push((Some(i), o.to_string(), sep.clone(), explicit.clone()));
            }
        }
    }
    result
}

fn parse_optional(arg: &str) -> Option<Vec<OptTuple>> {
    if arg.is_empty() || !arg.starts_with('-') {
        return None;
    }
    if let Some(i) = lookup(arg) {
        return Some(vec![(Some(i), arg.to_string(), None, None)]);
    }
    if arg.chars().count() == 1 {
        return None;
    }
    let (opt, sep, explicit) = partition_eq(arg);
    if sep.is_some() {
        if let Some(i) = lookup(&opt) {
            return Some(vec![(Some(i), opt, sep, explicit)]);
        }
    }
    let tuples = get_option_tuples(arg);
    if !tuples.is_empty() {
        return Some(tuples);
    }
    if is_negative_number(arg) {
        return None;
    }
    if arg.contains(' ') {
        return None;
    }
    Some(vec![(None, arg.to_string(), None, None)])
}

enum Stop {
    Help,
    Error(String),
}

fn action_name(spec: &Spec) -> String {
    spec.opts.join("/")
}

fn take_action(spec: &Spec, values: &[String], ns: &mut Args) -> Result<(), Stop> {
    let invalid = |ty: &str, v: &str| {
        Stop::Error(format!(
            "argument {}: invalid {} value: {}",
            action_name(spec),
            ty,
            repr_str(v)
        ))
    };
    match spec.dest {
        Dest::Help => return Err(Stop::Help),
        Dest::All => ns.all = true,
        Dest::Discover => ns.discover = true,
        Dest::PrintSerial => ns.print_serial = true,
        Dest::NoTailscale => ns.no_tailscale = true,
        Dest::DisconnectFirst => ns.disconnect_first = true,
        Dest::Status => ns.status = true,
        Dest::Json => ns.json = true,
        Dest::Device => ns.device = Some(values[0].clone()),
        Dest::Pair => ns.pair = Some(values[0].clone()),
        Dest::Ip => ns.ip = Some(values[0].clone()),
        Dest::Tcpip => {
            ns.tcpip = Some(match values.first() {
                None => "5555".into(),
                Some(v) => parse_int(v).ok_or_else(|| invalid("int", v))?,
            })
        }
        Dest::Timeout => {
            ns.timeout = parse_float(&values[0]).ok_or_else(|| invalid("float", &values[0]))?
        }
    }
    Ok(())
}

fn match_argument(spec: &Spec, pattern: &[char]) -> Result<usize, Stop> {
    match spec.nargs {
        Nargs::Zero => Ok(0),
        Nargs::Optional => Ok(usize::from(pattern.first() == Some(&'A'))),
        Nargs::One => {
            if pattern.first() == Some(&'A') {
                Ok(1)
            } else {
                Err(Stop::Error(format!(
                    "argument {}: expected one argument",
                    action_name(spec)
                )))
            }
        }
    }
}

fn parse_known(argv: &[String], ns: &mut Args) -> Result<Vec<String>, Stop> {
    let mut pattern: Vec<char> = Vec::new();
    let mut option_indices: HashMap<usize, Vec<OptTuple>> = HashMap::new();
    for (i, arg) in argv.iter().enumerate() {
        if arg == "--" {
            // Everything after `--` is an argument, never an option.
            pattern.push('-');
            pattern.resize(argv.len(), 'A');
            break;
        }
        match parse_optional(arg) {
            None => pattern.push('A'),
            Some(t) => {
                option_indices.insert(i, t);
                pattern.push('O');
            }
        }
    }

    let mut extras: Vec<String> = Vec::new();
    let mut start = 0usize;
    let max_index = option_indices.keys().max().copied();
    while let Some(max) = max_index {
        if start > max {
            break;
        }
        let next = *option_indices
            .keys()
            .filter(|&&k| k >= start)
            .min()
            .expect("an option index at or after start");
        if !option_indices.contains_key(&start) {
            extras.extend(argv[start..next].iter().cloned());
            start = next;
        }
        // consume_optional(start)
        let tuples = &option_indices[&start];
        if tuples.len() > 1 {
            let options: Vec<&str> = tuples.iter().map(|t| t.1.as_str()).collect();
            return Err(Stop::Error(format!(
                "ambiguous option: {} could match {}",
                argv[start],
                options.join(", ")
            )));
        }
        let (mut action, mut option_string, mut sep, mut explicit) = tuples[0].clone();
        let mut action_tuples: Vec<(usize, Vec<String>)> = Vec::new();
        let stop;
        loop {
            let Some(idx) = action else {
                extras.push(argv[start].clone());
                stop = start + 1;
                break;
            };
            let spec = &SPECS[idx];
            if let Some(exp) = explicit.clone() {
                let arg_count = match_argument(spec, &['A'])?;
                let second = option_string.chars().nth(1);
                if arg_count == 0 && second != Some('-') && !exp.is_empty() {
                    if sep.as_deref().map_or(false, |s| !s.is_empty()) || exp.starts_with('-') {
                        return Err(Stop::Error(format!(
                            "argument {}: ignored explicit argument {}",
                            action_name(spec),
                            repr_str(&exp)
                        )));
                    }
                    action_tuples.push((idx, Vec::new()));
                    let first = exp.chars().next().expect("non-empty");
                    option_string = format!("-{}", first);
                    if let Some(next_idx) = lookup(&option_string) {
                        action = Some(next_idx);
                        let rest: String = exp.chars().skip(1).collect();
                        if rest.is_empty() {
                            sep = None;
                            explicit = None;
                        } else if let Some(after) = rest.strip_prefix('=') {
                            sep = Some("=".into());
                            explicit = Some(after.to_string());
                        } else {
                            sep = Some(String::new());
                            explicit = Some(rest);
                        }
                    } else {
                        extras.push(format!("-{}", exp));
                        stop = start + 1;
                        break;
                    }
                } else if arg_count == 1 {
                    stop = start + 1;
                    action_tuples.push((idx, vec![exp]));
                    break;
                } else {
                    return Err(Stop::Error(format!(
                        "argument {}: ignored explicit argument {}",
                        action_name(spec),
                        repr_str(&exp)
                    )));
                }
            } else {
                let from = start + 1;
                let count = match_argument(spec, &pattern[from..])?;
                stop = from + count;
                action_tuples.push((idx, argv[from..stop].to_vec()));
                break;
            }
        }
        for (idx, values) in &action_tuples {
            take_action(&SPECS[*idx], values, ns)?;
        }
        start = stop;
    }
    extras.extend(argv[start.min(argv.len())..].iter().cloned());
    Ok(extras)
}

/// `parser.parse_args(argv)`.
pub fn parse(prog: &str, argv: &[String], columns: i64) -> Parsed {
    let mut ns = Args::default();
    let result = parse_known(argv, &mut ns).and_then(|extras| {
        if extras.is_empty() {
            Ok(())
        } else {
            Err(Stop::Error(format!(
                "unrecognized arguments: {}",
                extras.join(" ")
            )))
        }
    });
    match result {
        Ok(()) => Parsed::Run(ns),
        Err(Stop::Help) => Parsed::Exit {
            code: 0,
            stdout: format_help(prog, columns),
            stderr: String::new(),
        },
        Err(Stop::Error(msg)) => Parsed::Exit {
            code: 2,
            stdout: String::new(),
            stderr: error_text(prog, columns, &msg),
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn run(args: &[&str]) -> Parsed {
        let argv: Vec<String> = args.iter().map(|a| a.to_string()).collect();
        parse("adb_connect.py", &argv, 80)
    }

    fn ok(args: &[&str]) -> Args {
        match run(args) {
            Parsed::Run(a) => a,
            other => panic!("expected success for {:?}, got {:?}", args, other),
        }
    }

    fn err(args: &[&str]) -> String {
        match run(args) {
            Parsed::Exit {
                code: 2, stderr, ..
            } => stderr.lines().last().unwrap_or_default().to_string(),
            other => panic!("expected an error for {:?}, got {:?}", args, other),
        }
    }

    const HELP_80: &str =
        "usage: adb_connect.py [-h] [-d DEVICE] [--all] [--discover] [--pair CODE]
                      [--print-serial] [--ip IP] [--no-tailscale]
                      [--disconnect-first] [--tcpip [TCPIP]] [--status]
                      [--json] [--timeout TIMEOUT]

Auto-discover Android Wireless Debugging port and connect adb.

options:
  -h, --help            show this help message and exit
  -d DEVICE, --device DEVICE
                        Filter by device alias (fold, pixel4, watch, tv),
                        model, codename, or serial. (default: None)
  --all                 Connect all discovered Wireless Debugging phones
                        (_adb-tls-connect._tcp). (default: False)
  --discover, --list    Discover all mDNS Android devices on the network and
                        show their aliases and status. (default: False)
  --pair CODE           Pair with a device using a 6-digit pairing code (auto-
                        discovers pairing port via mDNS). (default: None)
  --print-serial        Print only the resolved ADB transport identifier (for
                        ANDROID_SERIAL) and exit. (default: False)
  --ip IP               Override target IP address instead of auto-resolving.
                        (default: None)
  --no-tailscale        Disable Tailscale IP preference; use direct local
                        network IP. (default: False)
  --disconnect-first    Disconnect existing ADB session(s) before attempting
                        to discover and connect. (default: False)
  --tcpip [TCPIP]       Switch ADB to static TCP/IP mode on specified port
                        (default: 5555) once connected. (default: None)
  --status              Show currently connected ADB devices and exit.
                        (default: False)
  --json                Output structured JSON instead of human-readable text.
                        (default: False)
  --timeout TIMEOUT     mDNS discovery timeout in seconds. (default: 1.5)
";

    #[test]
    fn help_matches_python_at_80_columns() {
        assert_eq!(format_help("adb_connect.py", 80), HELP_80);
        match run(&["--bogus", "-h"]) {
            Parsed::Exit {
                code: 0, stdout, ..
            } => assert_eq!(stdout, HELP_80),
            other => panic!("{:?}", other),
        }
    }

    #[test]
    fn usage_wraps_like_python_at_60_columns() {
        assert_eq!(
            format_usage("adb_connect.py", 60),
            "usage: adb_connect.py [-h] [-d DEVICE] [--all]
                      [--discover] [--pair CODE]
                      [--print-serial] [--ip IP]
                      [--no-tailscale]
                      [--disconnect-first]
                      [--tcpip [TCPIP]] [--status]
                      [--json] [--timeout TIMEOUT]
"
        );
    }

    #[test]
    fn parses_forms_python_accepts() {
        assert_eq!(ok(&["-dfoo"]).device.as_deref(), Some("foo"));
        assert_eq!(ok(&["-d=foo"]).device.as_deref(), Some("foo"));
        assert_eq!(ok(&["--dev=x"]).device.as_deref(), Some("x"));
        assert_eq!(ok(&["--device=--"]).device.as_deref(), Some("--"));
        assert_eq!(ok(&["-d", "-1"]).device.as_deref(), Some("-1"));
        assert_eq!(ok(&["-d", "-a b"]).device.as_deref(), Some("-a b"));
        assert_eq!(ok(&["--tcpip", "-5"]).tcpip.as_deref(), Some("-5"));
        assert_eq!(ok(&["--tcpip", " +07 "]).tcpip.as_deref(), Some("7"));
        assert_eq!(ok(&["--tcpip"]).tcpip.as_deref(), Some("5555"));
        assert_eq!(ok(&["--timeout", "-1"]).timeout, -1.0);
        assert_eq!(ok(&["--timeout", " 1_5 "]).timeout, 15.0);
        assert!(ok(&["--timeout", "1e999"]).timeout.is_infinite());
        assert!(ok(&["--al"]).all);
        assert!(ok(&["--l"]).discover);
        let a = ok(&["--discover", "-ddd"]);
        assert!(a.discover);
        assert_eq!(a.device.as_deref(), Some("dd"));
        assert_eq!(ok(&["-d", "a", "-d", "b"]).device.as_deref(), Some("b"));
    }

    #[test]
    fn errors_match_python() {
        assert_eq!(
            err(&["--"]),
            "adb_connect.py: error: unrecognized arguments: --"
        );
        assert_eq!(
            err(&["--json", "--"]),
            "adb_connect.py: error: unrecognized arguments: --"
        );
        assert_eq!(
            err(&["-d", "--", "x"]),
            "adb_connect.py: error: argument -d/--device: expected one argument"
        );
        assert_eq!(
            err(&["--tcpip=--"]),
            "adb_connect.py: error: argument --tcpip: invalid int value: '--'"
        );
        assert_eq!(
            err(&["--timeout=--"]),
            "adb_connect.py: error: argument --timeout: invalid float value: '--'"
        );
        assert_eq!(
            err(&["-h=x"]),
            "adb_connect.py: error: argument -h/--help: ignored explicit argument 'x'"
        );
        assert_eq!(err(&["--=x"]), "adb_connect.py: error: ambiguous option: --=x could match --help, --device, --all, --discover, --list, --pair, --print-serial, --ip, --no-tailscale, --disconnect-first, --tcpip, --status, --json, --timeout");
        assert_eq!(
            err(&["--ip", "-x"]),
            "adb_connect.py: error: argument --ip: expected one argument"
        );
        assert_eq!(
            err(&["--all=", "x"]),
            "adb_connect.py: error: argument --all: ignored explicit argument ''"
        );
        assert_eq!(
            err(&["-", "x"]),
            "adb_connect.py: error: unrecognized arguments: - x"
        );
        assert_eq!(err(&["--di"]), "adb_connect.py: error: ambiguous option: --di could match --discover, --disconnect-first");
        assert_eq!(
            err(&["--tcpip", "1__0"]),
            "adb_connect.py: error: argument --tcpip: invalid int value: '1__0'"
        );
        assert_eq!(
            err(&["--timeout", "-inf"]),
            "adb_connect.py: error: argument --timeout: expected one argument"
        );
        assert_eq!(
            err(&["--all", "--", "--all"]),
            "adb_connect.py: error: unrecognized arguments: -- --all"
        );
        assert_eq!(
            err(&["-xyz"]),
            "adb_connect.py: error: unrecognized arguments: -xyz"
        );
        assert_eq!(
            err(&["--json=1"]),
            "adb_connect.py: error: argument --json: ignored explicit argument '1'"
        );
        assert_eq!(
            err(&["--tcpip", "x"]),
            "adb_connect.py: error: argument --tcpip: invalid int value: 'x'"
        );
        assert!(matches!(run(&["-hx"]), Parsed::Exit { code: 0, .. }));
    }

    #[test]
    fn wrap_breaks_on_hyphens_like_textwrap() {
        assert_eq!(
            wrap("Pair with a device using a 6-digit pairing code (auto-discovers pairing port via mDNS).", 54),
            vec![
                "Pair with a device using a 6-digit pairing code (auto-",
                "discovers pairing port via mDNS)."
            ]
        );
        assert_eq!(
            wrap("abcdefghijklmnop", 5),
            vec!["abcde", "fghij", "klmno", "p"]
        );
        assert_eq!(
            wordsep_chunks("(_adb-tls-connect._tcp)."),
            vec!["(_adb-", "tls-", "connect._tcp)."]
        );
    }

    #[test]
    fn terminal_columns_follows_shutil() {
        assert_eq!(terminal_columns(Some("120"), Some(50)), 120);
        assert_eq!(terminal_columns(Some("0"), Some(50)), 50);
        assert_eq!(terminal_columns(Some("x"), None), 80);
        assert_eq!(terminal_columns(None, Some(0)), 80);
    }
}
