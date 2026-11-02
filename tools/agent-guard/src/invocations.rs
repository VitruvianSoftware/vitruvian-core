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

//! Unwrapping: env/nice/time/timeout/xargs/sudo/... and shells/eval, and the
//! walk that turns command text into every program it would run.

use crate::paths::{basename, isabs, join, normpath};
use crate::pyutil::{is_assignment, is_python3_dotted};
use crate::shell::{fallback_split, parse_script_at, PErr, SimpleCommand, MAX_COMMANDS};

pub const SHELLS: [&str; 6] = ["bash", "sh", "zsh", "dash", "ksh", "fish"];

/// A program the command would run, with the directory it runs in.
#[derive(Clone, Debug)]
pub struct Invocation {
    pub argv: Vec<String>,
    pub cwd: String,
    pub redirects: Vec<(String, String)>,
    /// Run with an agent marker (CLAUDECODE, ...) unset or blanked.
    pub hides_marker: bool,
}

impl Invocation {
    pub fn new(argv: Vec<String>, cwd: &str, redirects: Vec<(String, String)>) -> Self {
        Invocation {
            argv,
            cwd: cwd.to_string(),
            redirects,
            hides_marker: false,
        }
    }

    pub fn prog(&self) -> &str {
        self.argv.first().map(|a| basename(a)).unwrap_or("")
    }
}

fn has(list: &[&str], a: &str) -> bool {
    list.contains(&a)
}

/// Drop leading options; those in with_arg consume the next word.
pub fn skip_opts(args: &[String], with_arg: &[&str]) -> Vec<String> {
    let mut i = 0;
    while i < args.len() {
        let a = &args[i];
        if a == "--" {
            return args[i + 1..].to_vec();
        }
        if !a.starts_with('-') || a == "-" {
            break;
        }
        if has(with_arg, a) {
            i += 2;
            continue;
        }
        i += 1;
    }
    args[i.min(args.len())..].to_vec()
}

fn quote_join(words: &[String]) -> String {
    words
        .iter()
        .map(|w| format!("'{}'", w.replace('\'', "'\\''")))
        .collect::<Vec<_>>()
        .join(" ")
}

fn note_force_arg0(assignment: &str, slot: &mut Option<String>) {
    let (name, value) = crate::pyutil::split1(assignment, '=');
    if name == "RUSTUP_FORCE_ARG0" {
        *slot = value.filter(|v| !v.is_empty()).map(|v| v.to_string());
    }
}

/// Strip wrappers. Returns (argv, scripts) where scripts are nested shell text.
pub fn unwrap(mut words: Vec<String>, cmd: &SimpleCommand) -> (Vec<String>, Vec<String>) {
    let mut scripts: Vec<String> = Vec::new();
    // RUSTUP_FORCE_ARG0=<x> makes rustup act as <x> (#4171), so remember it
    // from `VAR=...` prefixes and `env VAR=...` for the rustup it reaches.
    let mut force_arg0: Option<String> = None;
    for _ in 0..20 {
        let lead = words.iter().take_while(|w| is_assignment(w)).count();
        for w in &words[..lead] {
            note_force_arg0(w, &mut force_arg0);
        }
        words.drain(..lead);
        if words.is_empty() {
            return (vec![], scripts);
        }
        let prog = basename(&words[0]).to_string();
        let args: Vec<String> = words[1..].to_vec();
        let first = args.first().map(|s| s.as_str());
        let p = prog.as_str();
        if p == "env" {
            let mut rest: Vec<String> = Vec::new();
            let mut i = 0;
            while i < args.len() {
                let a = &args[i];
                if has(&["-u", "-C", "--unset", "--chdir"], a) {
                    i += 2;
                    continue;
                }
                if (a == "-S" || a == "--split-string") && i + 1 < args.len() {
                    scripts.push(args[i + 1..].join(" "));
                    return (vec![], scripts);
                }
                if a.starts_with("-S") && a.chars().count() > 2 {
                    let mut parts = vec![a[2..].to_string()];
                    parts.extend_from_slice(&args[i + 1..]);
                    scripts.push(parts.join(" "));
                    return (vec![], scripts);
                }
                if a.starts_with('-') || is_assignment(a) {
                    note_force_arg0(a, &mut force_arg0);
                    i += 1;
                    continue;
                }
                rest = args[i..].to_vec();
                break;
            }
            words = rest;
            continue;
        }
        if p == "command" || p == "builtin" {
            if first == Some("-v") || first == Some("-V") {
                return (vec![], scripts); // a lookup, not a run
            }
            words = skip_opts(&args, &[]);
            continue;
        }
        if has(
            &[
                "exec",
                "nohup",
                "noglob",
                "chronic",
                "unbuffer",
                "nocorrect",
            ],
            p,
        ) {
            words = skip_opts(&args, &["-a"]);
            continue;
        }
        if p == "sudo" || p == "doas" {
            words = skip_opts(
                &args,
                &["-u", "-g", "-h", "-p", "-C", "-D", "-r", "-t", "-U", "-T"],
            );
            continue;
        }
        if p == "nice" {
            words = skip_opts(&args, &["-n"]);
            continue;
        }
        if p == "ionice" {
            words = skip_opts(&args, &["-c", "-n", "-p", "-P", "-u"]);
            continue;
        }
        if p == "time" {
            words = skip_opts(&args, &["-f", "-o", "--format", "--output"]);
            continue;
        }
        if p == "timeout" || p == "gtimeout" {
            let rest = skip_opts(&args, &["-s", "-k", "--signal", "--kill-after"]);
            words = if rest.is_empty() {
                vec![]
            } else {
                rest[1..].to_vec()
            };
            continue;
        }
        if p == "stdbuf" {
            words = skip_opts(&args, &["-i", "-o", "-e"]);
            continue;
        }
        if p == "caffeinate" {
            words = skip_opts(&args, &["-t", "-w"]);
            continue;
        }
        if p == "watch" {
            let rest = skip_opts(&args, &["-n", "--interval", "-d"]);
            if !rest.is_empty() {
                scripts.push(rest.join(" "));
            }
            return (vec![], scripts);
        }
        if p == "xargs" {
            words = skip_opts(
                &args,
                &[
                    "-I", "-L", "-n", "-P", "-s", "-E", "-d", "-a", "-J", "-R", "-S",
                ],
            );
            if words.is_empty() {
                return (vec![], scripts); // xargs with no command runs echo
            }
            continue;
        }
        // rustup [OPTIONS] [+toolchain] run [--install] <toolchain> <cmd...>
        // runs <cmd> with that toolchain: judge <cmd> (#4171). Usage and
        // flags are from `rustup --help` / `rustup run --help` (rustup 1.29.2).
        if p == "rustup" {
            if let Some(arg0) = force_arg0.take() {
                let mut w = vec![arg0];
                w.extend_from_slice(&args);
                words = w;
                continue;
            }
            let mut rest = skip_opts(&args, &[]);
            if rest.first().map_or(false, |s| s.starts_with('+')) {
                rest = skip_opts(&rest[1..], &[]);
            }
            if rest.first().map(|s| s.as_str()) == Some("run") {
                let after = skip_opts(&rest[1..], &[]);
                words = after.get(1..).map(|s| s.to_vec()).unwrap_or_default();
                if words.first().map(|s| s.as_str()) == Some("--") {
                    words.remove(0);
                }
                continue;
            }
        }
        if p == "direnv" && first == Some("exec") {
            words = args.get(2..).map(|s| s.to_vec()).unwrap_or_default();
            continue;
        }
        if has(&["mise", "asdf", "rtx"], p) && first == Some("exec") {
            let rest = &args[1..];
            words = match rest.iter().position(|a| a == "--") {
                Some(k) => rest[k + 1..].to_vec(),
                None => rest.get(1..).map(|s| s.to_vec()).unwrap_or_default(),
            };
            continue;
        }
        if has(&["uv", "poetry", "pdm", "hatch", "pipenv"], p) && first == Some("run") {
            words = skip_opts(
                &args[1..],
                &[
                    "--with",
                    "--python",
                    "-p",
                    "--directory",
                    "--project",
                    "--group",
                    "--extra",
                    "--env-file",
                ],
            );
            continue;
        }
        if p == "uvx" || (p == "pipx" && first == Some("run")) {
            let a: &[String] = if p == "uvx" { &args } else { &args[1..] };
            words = skip_opts(a, &["--from", "--with", "--python", "-p", "--spec"]);
            continue;
        }
        if p == "python" || p == "python3" || is_python3_dotted(p) {
            let rest = &args;
            // python -m <module> ... -> treat the module as the program.
            let mut j = 0;
            while j < rest.len() && rest[j].starts_with('-') && rest[j] != "-m" && rest[j] != "-c" {
                j += 1;
            }
            if j < rest.len() && rest[j] == "-m" && j + 1 < rest.len() {
                let mut w = vec![rest[j + 1].clone()];
                w.extend_from_slice(&rest[j + 2..]);
                words = w;
                continue;
            }
            return (words, scripts);
        }
        if SHELLS.contains(&p) {
            let mut i = 0;
            let mut has_c = false;
            while i < args.len() {
                let a = &args[i];
                if a == "--" {
                    i += 1;
                    break;
                }
                if has(&["-o", "+o", "-O", "+O", "--rcfile", "--init-file"], a) {
                    i += 2;
                    continue;
                }
                if a.starts_with('-') && !a.starts_with("--") && a[1..].contains('c') {
                    has_c = true;
                    i += 1;
                    continue;
                }
                if a.starts_with('-') || a.starts_with('+') {
                    i += 1;
                    continue;
                }
                break;
            }
            let mut script = None;
            let mut positional = None;
            if has_c {
                if i < args.len() {
                    script = Some(args[i].clone());
                }
            } else if i < args.len() {
                positional = Some(args[i].clone());
            }
            if let Some(s) = script {
                scripts.push(s);
                return (vec![], scripts);
            }
            if positional.is_none() {
                scripts.extend(cmd.heredocs.iter().cloned());
                scripts.extend(cmd.herestrings.iter().cloned());
                return (vec![], scripts);
            }
            // bash some-script.sh: the script's contents are not seen (a limit).
            return (words, scripts);
        }
        if p == "eval" {
            scripts.push(args.join(" "));
            return (vec![], scripts);
        }
        if p == "find" {
            // find ... -exec cmd {} ; -> cmd. find itself is otherwise ungoverned.
            let mut j = 0;
            while j < args.len() {
                if has(&["-exec", "-execdir", "-ok", "-okdir"], &args[j]) {
                    let mut k = j + 1;
                    let mut sub = Vec::new();
                    while k < args.len() && !has(&[";", "+", "\\;"], &args[k]) {
                        sub.push(args[k].clone());
                        k += 1;
                    }
                    if !sub.is_empty() {
                        scripts.push(quote_join(&sub));
                    }
                    j = k + 1;
                    continue;
                }
                j += 1;
            }
            return (words, scripts);
        }
        return (words, scripts);
    }
    (words, scripts)
}

/// `re.sub(r"^\$\{?HOME\}?", home, p)`.
fn sub_home(p: &str, home: &str) -> String {
    if !p.starts_with('$') {
        return p.to_string();
    }
    let mut j = 1;
    if p[j..].starts_with('{') {
        j += 1;
    }
    if !p[j..].starts_with("HOME") {
        return p.to_string();
    }
    j += 4;
    if p[j..].starts_with('}') {
        j += 1;
    }
    format!("{}{}", home, &p[j..])
}

pub fn expand_path(path: &str, cwd: &str, home: &str) -> String {
    let mut p = path.to_string();
    if p == "~" || p.starts_with("~/") {
        p = format!("{}{}", home, &p[1..]);
    }
    p = sub_home(&p, home);
    if !isabs(&p) {
        p = join(cwd, &p);
    }
    normpath(&p)
}

fn is_marker(name: &str) -> bool {
    name == "CLAUDECODE" || name == "GEMINI_CLI" || name.starts_with("ANTIGRAVITY_")
}

fn assign_name(a: &str) -> &str {
    crate::pyutil::split1(a, '=').0
}

/// Does this simple command unset or blank an agent marker for what it runs?
pub fn hides_agent_marker(words: &[String]) -> bool {
    let mut i = 0;
    while i < words.len() && is_assignment(&words[i]) {
        if is_marker(assign_name(&words[i])) {
            return true;
        }
        i += 1;
    }
    if i >= words.len() {
        return false;
    }
    let prog = basename(&words[i]);
    let args = &words[i + 1..];
    if prog == "env" {
        let mut j = 0;
        while j < args.len() {
            let a = &args[j];
            if (a == "-u" || a == "--unset") && j + 1 < args.len() && is_marker(&args[j + 1]) {
                return true;
            }
            if let Some(v) = a.strip_prefix("--unset=") {
                if is_marker(v) {
                    return true;
                }
            }
            if a.starts_with("-u") && a.chars().count() > 2 && is_marker(&a[2..]) {
                return true;
            }
            if a == "-i" || a == "--ignore-environment" || a == "-" {
                return true;
            }
            if is_assignment(a) {
                if is_marker(assign_name(a)) {
                    return true;
                }
            } else if !a.starts_with('-') {
                break;
            }
            j += 1;
        }
        return false;
    }
    if prog == "unset" {
        return args
            .iter()
            .filter(|a| !a.starts_with('-'))
            .any(|a| is_marker(a));
    }
    if prog == "export" && args.iter().any(|a| a == "-n") {
        return args
            .iter()
            .filter(|a| !a.starts_with('-'))
            .any(|a| is_marker(a));
    }
    false
}

/// Every program the command text would run, in order, with its directory.
pub fn invocations(text: &str, cwd: &str, home: &str) -> Result<Vec<Invocation>, PErr> {
    let mut out = Vec::new();
    let mut state_cwd = cwd.to_string();
    let mut budget = MAX_COMMANDS;
    walk(text, 0, home, &mut state_cwd, &mut budget, &mut out)?;
    Ok(out)
}

fn walk(
    script: &str,
    depth: usize,
    home: &str,
    state_cwd: &mut String,
    budget: &mut i64,
    out: &mut Vec<Invocation>,
) -> Result<(), PErr> {
    if depth > 6 {
        return Ok(());
    }
    let t: Vec<char> = script.chars().collect();
    let cmds = match parse_script_at(&t, 0, budget) {
        Ok(c) => c,
        Err(PErr::Parse) => fallback_split(script, Some(budget))?,
        Err(e) => return Err(e),
    };
    for cmd in cmds {
        let hidden = hides_agent_marker(&cmd.words);
        let (argv, scripts) = unwrap(cmd.words.clone(), &cmd);
        if !argv.is_empty() {
            let prog = basename(&argv[0]);
            if (prog == "cd" || prog == "pushd") && argv.len() >= 2 {
                if let Some(target) = argv[1..].iter().find(|a| !a.starts_with('-')) {
                    *state_cwd = expand_path(target, state_cwd, home);
                }
                continue;
            }
            out.push(Invocation {
                argv,
                cwd: state_cwd.clone(),
                redirects: cmd.redirects.clone(),
                hides_marker: hidden,
            });
        } else if !cmd.redirects.is_empty() || hidden {
            out.push(Invocation {
                argv: vec![":".into()],
                cwd: state_cwd.clone(),
                redirects: cmd.redirects.clone(),
                hides_marker: hidden,
            });
        }
        for s in scripts {
            walk(&s, depth + 1, home, state_cwd, budget, out)?;
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn expands_home_and_relative_paths() {
        assert_eq!(expand_path("~/x", "/c", "/h"), "/h/x");
        assert_eq!(expand_path("${HOME}/x", "/c", "/h"), "/h/x");
        assert_eq!(expand_path("$HOMEDIR", "/c", "/h"), "/hDIR");
        assert_eq!(expand_path("../y", "/c/d", "/h"), "/c/y");
    }

    #[test]
    fn unwraps_wrappers() {
        let invs = invocations(
            "sudo -u x env A=1 timeout 5 git push && bash -c 'go test'",
            "/r",
            "/h",
        )
        .unwrap();
        let argvs: Vec<Vec<String>> = invs.into_iter().map(|i| i.argv).collect();
        assert_eq!(
            argvs,
            vec![
                vec!["git".to_string(), "push".into()],
                vec!["go".into(), "test".into()]
            ]
        );
        // rustup run [--install] <toolchain> [--] <cmd...> runs <cmd> (#4171).
        for text in [
            "rustup run stable cargo update",
            "rustup run --install nightly cargo update",
            "rustup -q run 1.95.0 -- cargo update",
        ] {
            let argvs: Vec<Vec<String>> = invocations(text, "/r", "/h")
                .unwrap()
                .into_iter()
                .map(|i| i.argv)
                .collect();
            assert_eq!(
                argvs,
                vec![vec!["cargo".to_string(), "update".into()]],
                "{}",
                text
            );
        }
        let show: Vec<Vec<String>> = invocations("rustup show", "/r", "/h")
            .unwrap()
            .into_iter()
            .map(|i| i.argv)
            .collect();
        assert_eq!(show, vec![vec!["rustup".to_string(), "show".into()]]);
        assert!(hides_agent_marker(&[
            "env".into(),
            "-u".into(),
            "CLAUDECODE".into(),
            "x".into()
        ]));
    }
}
