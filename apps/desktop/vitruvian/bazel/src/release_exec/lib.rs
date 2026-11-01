// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

//! How the release tools (publish, package_release, make_dmg, notarize and
//! the signing setups) run the commands they drive.
//!
//! Every external command goes through a [`Runner`], so a test can hand the
//! tools a [`FakeRunner`] that records each command and answers it, and so
//! pin the order and arguments of a release without codesign, hdiutil, gh
//! or Apple's notary service.

use std::cell::RefCell;
use std::collections::BTreeMap;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

/// One command to run.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct Cmd {
    pub program: String,
    pub args: Vec<String>,
    pub cwd: Option<PathBuf>,
    pub stdin: Option<Vec<u8>>,
}

impl Cmd {
    pub fn new(program: &str) -> Cmd {
        Cmd {
            program: program.to_string(),
            ..Cmd::default()
        }
    }

    pub fn arg<S: AsRef<str>>(mut self, a: S) -> Cmd {
        self.args.push(a.as_ref().to_string());
        self
    }

    pub fn args<I, S>(mut self, args: I) -> Cmd
    where
        I: IntoIterator<Item = S>,
        S: AsRef<str>,
    {
        for a in args {
            self.args.push(a.as_ref().to_string());
        }
        self
    }

    pub fn path(self, p: &Path) -> Cmd {
        self.arg(p.to_string_lossy())
    }

    pub fn cwd(mut self, dir: &Path) -> Cmd {
        self.cwd = Some(dir.to_path_buf());
        self
    }

    pub fn stdin(mut self, input: &str) -> Cmd {
        self.stdin = Some(input.as_bytes().to_vec());
        self
    }

    /// [`Cmd::line`] with secrets hidden; see [`redact_args`].
    pub fn redacted_line(&self) -> String {
        let mut s = self.program.clone();
        for a in redact_args(&self.program, &self.args) {
            s.push(' ');
            s.push_str(&a);
        }
        s
    }

    /// The command as one line, program and arguments joined by spaces.
    pub fn line(&self) -> String {
        let mut s = self.program.clone();
        for a in &self.args {
            s.push(' ');
            s.push_str(a);
        }
        s
    }
}

/// What a captured command printed, and how it ended.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct Out {
    pub code: i32,
    pub stdout: String,
    pub stderr: String,
}

impl Out {
    pub fn ok(stdout: &str) -> Out {
        Out {
            code: 0,
            stdout: stdout.to_string(),
            stderr: String::new(),
        }
    }

    pub fn fail(code: i32, stderr: &str) -> Out {
        Out {
            code,
            stdout: String::new(),
            stderr: stderr.to_string(),
        }
    }

    pub fn success(&self) -> bool {
        self.code == 0
    }
}

pub trait Runner {
    /// Runs with the terminal's output, as a shell script's plain command
    /// does, and returns its exit code (127 when it cannot start, 128+N
    /// when signal N ended it).
    fn status(&mut self, cmd: &Cmd) -> i32;
    /// Runs and captures what it prints.
    fn output(&mut self, cmd: &Cmd) -> Out;
    /// Runs with the terminal's output for at most `limit`. `None` when it
    /// was still running then, and was killed.
    fn status_within(&mut self, cmd: &Cmd, limit: Duration) -> Option<i32>;
    fn sleep(&mut self, d: Duration);
    /// Whether `path` is a folder (a mount point, for make_dmg).
    fn is_dir(&mut self, path: &Path) -> bool {
        path.is_dir()
    }
    /// Writes `text` to the tool's stderr: where a captured command's own
    /// error goes when it fails, as a script let it through to the log.
    fn report(&mut self, text: &str) {
        eprint!("{}", text);
    }
    /// The secret values in play (from the environment), hidden wherever
    /// they turn up in what the tools report.
    fn secrets(&self) -> Vec<String> {
        Vec::new()
    }
}

/// Runs the commands for real.
#[derive(Debug, Default, Clone)]
pub struct SystemRunner {
    /// Variables set on every command, over the inherited environment.
    pub envs: BTreeMap<String, String>,
    /// Secret values hidden from what the tools report; see [`env_secrets`].
    pub secrets: Vec<String>,
}

impl SystemRunner {
    pub fn new() -> SystemRunner {
        SystemRunner::default()
    }

    /// A runner that hides the secrets this process's environment holds.
    pub fn from_env() -> SystemRunner {
        let env: BTreeMap<String, String> = std::env::vars().collect();
        SystemRunner {
            secrets: env_secrets(&env),
            ..SystemRunner::default()
        }
    }

    fn command(&self, cmd: &Cmd) -> Command {
        let mut c = Command::new(&cmd.program);
        c.args(&cmd.args);
        if let Some(dir) = &cmd.cwd {
            c.current_dir(dir);
        }
        for (k, v) in &self.envs {
            c.env(k, v);
        }
        c
    }
}

/// The exit code a shell would report: the program's own, or 128+N when
/// signal N ended it.
fn exit_code(status: std::process::ExitStatus) -> i32 {
    if let Some(code) = status.code() {
        return code;
    }
    #[cfg(unix)]
    {
        use std::os::unix::process::ExitStatusExt;
        if let Some(sig) = status.signal() {
            return 128 + sig;
        }
    }
    1
}

fn feed(child: &mut std::process::Child, input: &Option<Vec<u8>>) {
    if let (Some(bytes), Some(mut pipe)) = (input, child.stdin.take()) {
        let _ = pipe.write_all(bytes);
    }
}

impl Runner for SystemRunner {
    fn status(&mut self, cmd: &Cmd) -> i32 {
        let mut c = self.command(cmd);
        if cmd.stdin.is_some() {
            c.stdin(Stdio::piped());
        }
        match c.spawn() {
            Ok(mut child) => {
                feed(&mut child, &cmd.stdin);
                child.wait().map(exit_code).unwrap_or(1)
            }
            Err(e) => {
                eprintln!("{}: {}", cmd.program, e);
                127
            }
        }
    }

    fn output(&mut self, cmd: &Cmd) -> Out {
        let mut c = self.command(cmd);
        c.stdout(Stdio::piped()).stderr(Stdio::piped());
        c.stdin(if cmd.stdin.is_some() {
            Stdio::piped()
        } else {
            Stdio::null()
        });
        match c.spawn() {
            Ok(mut child) => {
                feed(&mut child, &cmd.stdin);
                match child.wait_with_output() {
                    Ok(o) => Out {
                        code: exit_code(o.status),
                        stdout: String::from_utf8_lossy(&o.stdout).to_string(),
                        stderr: String::from_utf8_lossy(&o.stderr).to_string(),
                    },
                    Err(e) => Out::fail(1, &e.to_string()),
                }
            }
            Err(e) => Out::fail(127, &format!("{}: {}", cmd.program, e)),
        }
    }

    fn status_within(&mut self, cmd: &Cmd, limit: Duration) -> Option<i32> {
        let mut c = self.command(cmd);
        if cmd.stdin.is_some() {
            c.stdin(Stdio::piped());
        }
        let mut child = match c.spawn() {
            Ok(child) => child,
            Err(_) => return Some(127),
        };
        feed(&mut child, &cmd.stdin);
        let started = Instant::now();
        loop {
            if let Ok(Some(status)) = child.try_wait() {
                return Some(exit_code(status));
            }
            if started.elapsed() >= limit {
                // As the script did: TERM, a second's grace, then KILL.
                let _ = Command::new("kill")
                    .args(["-TERM", &child.id().to_string()])
                    .stderr(Stdio::null())
                    .status();
                thread::sleep(Duration::from_secs(1));
                if !matches!(child.try_wait(), Ok(Some(_))) {
                    let _ = child.kill();
                }
                let _ = child.wait();
                return None;
            }
            thread::sleep(Duration::from_millis(200));
        }
    }

    fn sleep(&mut self, d: Duration) {
        thread::sleep(d);
    }

    fn secrets(&self) -> Vec<String> {
        self.secrets.clone()
    }
}

type Responder = Box<dyn FnMut(&Cmd) -> Out>;
type DirCheck = Box<dyn FnMut(&Path) -> bool>;

/// Records every command and answers it with `respond`. A command it is
/// asked to run with a time limit answers `None` (timed out) when the
/// responder's code is [`FakeRunner::TIMED_OUT`].
pub struct FakeRunner {
    pub calls: Vec<String>,
    pub cmds: Vec<Cmd>,
    pub slept: Duration,
    /// Each command run with a time limit, and the limit it was given.
    pub limits: Vec<(String, Duration)>,
    /// What the tool wrote through [`Runner::report`].
    pub stderr: String,
    /// What [`Runner::secrets`] answers.
    pub secrets: Vec<String>,
    respond: Responder,
    dir_check: Option<DirCheck>,
}

impl FakeRunner {
    pub const TIMED_OUT: i32 = -999;

    pub fn new<F: FnMut(&Cmd) -> Out + 'static>(respond: F) -> FakeRunner {
        FakeRunner {
            calls: Vec::new(),
            cmds: Vec::new(),
            slept: Duration::ZERO,
            limits: Vec::new(),
            stderr: String::new(),
            secrets: Vec::new(),
            respond: Box::new(respond),
            dir_check: None,
        }
    }

    /// Answers `is_dir` with `check` instead of the filesystem.
    pub fn with_dirs<F: FnMut(&Path) -> bool + 'static>(mut self, check: F) -> FakeRunner {
        self.dir_check = Some(Box::new(check));
        self
    }

    /// A runner where every command succeeds and prints nothing.
    pub fn succeeding() -> FakeRunner {
        FakeRunner::new(|_| Out::ok(""))
    }

    fn answer(&mut self, cmd: &Cmd) -> Out {
        self.calls.push(cmd.line());
        self.cmds.push(cmd.clone());
        (self.respond)(cmd)
    }

    /// Index of the first recorded call that starts with `prefix`.
    pub fn position(&self, prefix: &str) -> Option<usize> {
        self.calls.iter().position(|c| c.starts_with(prefix))
    }

    pub fn count(&self, prefix: &str) -> usize {
        self.calls.iter().filter(|c| c.starts_with(prefix)).count()
    }
}

impl Runner for FakeRunner {
    fn status(&mut self, cmd: &Cmd) -> i32 {
        self.answer(cmd).code
    }

    fn output(&mut self, cmd: &Cmd) -> Out {
        self.answer(cmd)
    }

    fn status_within(&mut self, cmd: &Cmd, limit: Duration) -> Option<i32> {
        self.limits.push((cmd.line(), limit));
        let code = self.answer(cmd).code;
        if code == FakeRunner::TIMED_OUT {
            None
        } else {
            Some(code)
        }
    }

    fn sleep(&mut self, d: Duration) {
        self.slept += d;
    }

    fn is_dir(&mut self, path: &Path) -> bool {
        match &mut self.dir_check {
            Some(check) => check(path),
            None => path.is_dir(),
        }
    }

    fn report(&mut self, text: &str) {
        self.stderr.push_str(text);
    }

    fn secrets(&self) -> Vec<String> {
        self.secrets.clone()
    }
}

/// Runs `cmd` with the terminal's output; a failure is its exit code, as
/// `set -e` stops a script with the failing command's code.
pub fn run(r: &mut dyn Runner, cmd: &Cmd) -> Result<(), i32> {
    match r.status(cmd) {
        0 => Ok(()),
        code => Err(code),
    }
}

/// Runs `cmd` captured; a failure is its exit code. A failure also writes
/// which command failed and what it printed to stderr, so the log says why
/// (a script's `$(…)` let that stderr through).
pub fn capture(r: &mut dyn Runner, cmd: &Cmd) -> Result<String, i32> {
    let out = r.output(cmd);
    if out.success() {
        return Ok(out.stdout);
    }
    let code = if out.code == 0 { 1 } else { out.code };
    let mut text = format!("✗ `{}` failed (exit {})\n", cmd.redacted_line(), code);
    text.push_str(&out.stderr);
    if !out.stderr.is_empty() && !out.stderr.ends_with('\n') {
        text.push('\n');
    }
    report_redacted(r, &text);
    Err(code)
}

/// Reports `text` with every secret the runner knows of hidden, so a
/// command's own error output cannot echo one into the log. URLs in it
/// also lose their credentials, which catches a token minted at run time
/// that no environment variable holds.
pub fn report_redacted(r: &mut dyn Runner, text: &str) {
    let secrets = r.secrets();
    r.report(&redact_github_tokens(&redact_json_secrets(
        &redact_credentials_in_text(&redact_urls_in_text(&redact_known(text, &secrets))),
    )));
}

pub const REDACTED: &str = "<redacted>";

/// Flags whose next argument is a secret, for any program.
const SECRET_FLAGS: [&str; 6] = [
    "--password",
    "--passphrase",
    "--token",
    "--secret",
    "--api-key",
    "--client-secret",
];

/// `security`'s flags that carry a password, by subcommand. Elsewhere the
/// same letters are not secrets: `import -k` is the keychain path and
/// `find-identity -p` a policy name.
const SECURITY_SECRET_FLAGS: [(&str, &str); 6] = [
    ("create-keychain", "-p"),
    ("unlock-keychain", "-p"),
    ("set-key-partition-list", "-k"),
    ("import", "-P"),
    ("export", "-P"),
    ("set-keychain-password", "-p"),
];

/// Whether a variable, flag or header name names a secret. Precise on
/// purpose: a name holding a secret word as a whole word (`token`,
/// `password`, …), or `api`/`access`/`private`/`secret` followed by `key`.
/// `key` alone is not one: `keychain`, `key-id` and `cache_key` stay.
pub fn is_secret_name(name: &str) -> bool {
    let lower = name.to_ascii_lowercase();
    let words: Vec<&str> = lower
        .split(|c: char| !c.is_ascii_alphanumeric())
        .filter(|w| !w.is_empty())
        .collect();
    const WHOLE: [&str; 9] = [
        "token",
        "secret",
        "password",
        "passwd",
        "passphrase",
        "authorization",
        "credential",
        "credentials",
        "apikey",
    ];
    if words.iter().any(|w| WHOLE.contains(w)) {
        return true;
    }
    words
        .windows(2)
        .any(|p| p[1] == "key" && matches!(p[0], "api" | "access" | "private" | "secret"))
}

/// The values of the environment's secrets: every variable whose name
/// [`is_secret_name`], plus the base64 p12 and its password.
pub fn env_secrets(env: &BTreeMap<String, String>) -> Vec<String> {
    let mut v: Vec<String> = env
        .iter()
        .filter(|(k, val)| {
            !val.is_empty()
                && (is_secret_name(k)
                    || matches!(k.as_str(), "SIGNING_CERT_P12" | "NOTARY_API_KEY_P8"))
        })
        .map(|(_, val)| val.clone())
        .collect();
    v.sort();
    v.dedup();
    v
}

/// `text` with every exact occurrence of a known secret hidden, longest
/// first. Values under 4 characters are skipped: hiding them would shred
/// ordinary words and they are not real secrets.
///
/// A secret of several lines (a PEM key, wrapped base64) is also hidden
/// line by line, so a tool that echoes it re-indented or with other line
/// endings, or prints only some of its lines, still cannot show it. A line
/// counts when it is at least [`MIN_SECRET_LINE`] characters once trimmed
/// and is not PEM armour (`-----BEGIN …-----`), which is not secret.
///
/// Not covered: a secret re-wrapped at another width (base64 at 76
/// columns instead of 64) has lines that match none of the original's,
/// and a one-line secret a tool wraps over several lines matches nothing.
pub fn redact_known(text: &str, secrets: &[String]) -> String {
    let mut all: Vec<&str> = Vec::new();
    for s in secrets {
        all.push(s.as_str());
        if s.contains('\n') || s.contains('\r') {
            all.extend(
                s.lines()
                    .map(str::trim)
                    .filter(|l| l.len() >= MIN_SECRET_LINE && !l.starts_with("-----")),
            );
        }
    }
    all.retain(|s| s.len() >= 4);
    all.sort_by(|a, b| b.len().cmp(&a.len()).then(a.cmp(b)));
    all.dedup();
    let mut out = text.to_string();
    for s in all {
        out = out.replace(s, REDACTED);
    }
    out
}

/// The shortest line of a multi-line secret that [`redact_known`] hides on
/// its own; a shorter one (a base64 tail like `AB==`) could match ordinary
/// text.
pub const MIN_SECRET_LINE: usize = 8;

/// `text` with the credentials of every URL in it hidden (see
/// [`redact_url`]), word by word, keeping the whitespace between words.
pub fn redact_urls_in_text(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    let mut word_start: Option<usize> = None;
    for (i, c) in text.char_indices() {
        if c.is_whitespace() {
            if let Some(s) = word_start.take() {
                push_url_redacted(&mut out, &text[s..i]);
            }
            out.push(c);
        } else if word_start.is_none() {
            word_start = Some(i);
        }
    }
    if let Some(s) = word_start {
        push_url_redacted(&mut out, &text[s..]);
    }
    out
}

fn push_url_redacted(out: &mut String, word: &str) {
    match redact_url(word) {
        Some(w) => out.push_str(&w),
        None => out.push_str(word),
    }
}

/// The arguments of `program` with secrets replaced by `<redacted>`, one
/// argument at a time (so a secret holding a space is hidden whole): the
/// argument after a secret flag, the value of a `NAME=value` whose name
/// [`is_secret_name`], an `Authorization:` header's value, a URL's
/// credentials and an openssl `pass:` value.
pub fn redact_args(program: &str, args: &[String]) -> Vec<String> {
    let base = Path::new(program)
        .file_name()
        .map(|f| f.to_string_lossy().to_string())
        .unwrap_or_default();
    let sub = args.first().map(String::as_str).unwrap_or("");
    let security_flag: Option<&str> = if base == "security" {
        SECURITY_SECRET_FLAGS
            .iter()
            .find(|(s, _)| *s == sub)
            .map(|(_, f)| *f)
    } else {
        None
    };
    let is_curl = base == "curl";
    let mut out = Vec::with_capacity(args.len());
    let mut hide_next = false;
    let mut curl_next: Option<CurlValue> = None;
    for a in args {
        if hide_next {
            out.push(REDACTED.to_string());
            hide_next = false;
            continue;
        }
        if let Some(kind) = curl_next.take() {
            out.push(redact_curl_value(kind, a));
            continue;
        }
        if is_curl {
            match curl_option(a) {
                CurlOption::ValueNext(kind) => {
                    curl_next = Some(kind);
                    out.push(a.clone());
                    continue;
                }
                CurlOption::Attached(flag, kind, value) => {
                    out.push(format!("{}{}", flag, redact_curl_value(kind, value)));
                    continue;
                }
                CurlOption::Plain => {}
            }
        }
        hide_next = SECRET_FLAGS.contains(&a.as_str()) || security_flag == Some(a.as_str());
        out.push(redact_arg(a));
    }
    out
}

/// How the value of a curl option is hidden. Only for curl: elsewhere
/// `-u`, `--user` and `-E` mean other things (`git add -u`, `pip install
/// --user`, `grep -E`).
#[derive(Clone, Copy)]
enum CurlValue {
    /// A credential whole: `-u`/`--user` and `-U`/`--proxy-user`
    /// (`user:password`), `--oauth2-bearer`, `--pass`/`--proxy-pass` (the
    /// private key's passphrase) and `--tlspassword`/`--proxy-tlspassword`
    /// (the TLS-SRP password).
    Whole,
    /// `certificate[:password]` (`-E`/`--cert`, `--proxy-cert`): the
    /// password is hidden, the path kept.
    Cert,
    /// `-b`/`--cookie`: cookie data (`name=value; …`) is hidden whole; a
    /// value without `=` is a file to read cookies from, and is kept.
    Cookie,
    /// Anything else, judged like any argument ([`redact_arg`]): a header
    /// by its name, `name=value` data by its name, a URL's credentials.
    Other,
}

fn curl_value_kind(flag: &str) -> CurlValue {
    match flag {
        "-u"
        | "--user"
        | "-U"
        | "--proxy-user"
        | "--oauth2-bearer"
        | "--pass"
        | "--proxy-pass"
        | "--tlspassword"
        | "--proxy-tlspassword" => CurlValue::Whole,
        "-E" | "--cert" | "--proxy-cert" => CurlValue::Cert,
        "-b" | "--cookie" => CurlValue::Cookie,
        _ => CurlValue::Other,
    }
}

fn redact_curl_value(kind: CurlValue, value: &str) -> String {
    match kind {
        CurlValue::Whole => REDACTED.to_string(),
        CurlValue::Cert => redact_cert_password(value),
        CurlValue::Cookie if value.contains('=') => REDACTED.to_string(),
        CurlValue::Cookie => value.to_string(),
        CurlValue::Other => redact_arg(value),
    }
}

/// `certificate[:password]` with the password hidden. As curl reads it, a
/// `\:` is a colon in the path. Only curl built for Windows also reads a
/// drive letter's colon as part of the path (`C:\certs\c.pem:pw`); on macOS,
/// where these tools run, curl takes `C` as the file and everything after
/// the first colon as the password, so that is what is hidden. A PKCS#11 URI
/// (`pkcs11:…;pin-value=…`) is hidden after its scheme, the PIN with it.
fn redact_cert_password(value: &str) -> String {
    let b = value.as_bytes();
    let drive = cfg!(windows) && b.len() >= 3 && b[0].is_ascii_alphabetic() && b[1] == b':';
    let mut i = if drive && (b[2] == b'\\' || b[2] == b'/') {
        2
    } else {
        0
    };
    while i < b.len() {
        match b[i] {
            b'\\' => i += 2,
            b':' => return format!("{}{}", &value[..=i], REDACTED),
            _ => i += 1,
        }
    }
    value.to_string()
}

/// curl's short options, other than `-u`/`-U`, that take a value: in a
/// cluster, whatever follows one of them is its value (`-XPUT`, `-oout.bin`,
/// `-HName: v`).
const CURL_VALUE_SHORT_FLAGS: &str = "AbcCdDeEFHKmoPQrtTwxXyYz";

enum CurlOption<'a> {
    /// Not an option whose value needs its own handling: judged whole.
    Plain,
    /// An option whose value is the next argument and is hidden its way.
    ValueNext(CurlValue),
    /// An option with its value attached: the option as written (`-d`,
    /// `-sSE`, `--cert=`), how to hide the value, and the value.
    Attached(&'a str, CurlValue, &'a str),
}

fn curl_option(arg: &str) -> CurlOption<'_> {
    if let Some(long) = arg.strip_prefix("--") {
        let (flag, value) = match long.split_once('=') {
            Some((name, value)) => (&arg[..2 + name.len()], Some(value)),
            None => (arg, None),
        };
        return match (curl_value_kind(flag), value) {
            // `--data=token=x` and `--header=Name: v` are judged whole, by
            // the names in them, as before.
            (CurlValue::Other, _) => CurlOption::Plain,
            (kind, Some(value)) => CurlOption::Attached(&arg[..flag.len() + 1], kind, value),
            (kind, None) => CurlOption::ValueNext(kind),
        };
    }
    // Short options cluster (`-sSu user:pw`) and take their value joined
    // (`-uuser:pw`, `-dtoken=x`): the first option that takes a value ends
    // the cluster, and the rest of the argument is its value. So `-XPUT` is
    // the method PUT, not `-X` plus `-U`.
    let Some(cluster) = arg.strip_prefix('-') else {
        return CurlOption::Plain;
    };
    for (i, c) in cluster.char_indices() {
        if !c.is_ascii_alphabetic() {
            break;
        }
        if c == 'u' || c == 'U' || CURL_VALUE_SHORT_FLAGS.contains(c) {
            let end = 1 + i + 1;
            let kind = curl_value_kind(&format!("-{}", c));
            return match (kind, end == arg.len()) {
                (CurlValue::Other, true) => CurlOption::Plain,
                (kind, true) => CurlOption::ValueNext(kind),
                (kind, false) => CurlOption::Attached(&arg[..end], kind, &arg[end..]),
            };
        }
    }
    CurlOption::Plain
}

/// One argument with its secrets hidden (see [`redact_args`]), secret
/// members of a JSON body ([`redact_json_secrets`]) and GitHub tokens
/// ([`redact_github_tokens`]) included wherever they sit in it.
fn redact_arg(arg: &str) -> String {
    redact_github_tokens(&redact_json_secrets(&redact_arg_by_shape(arg)))
}

/// `text` with the value of every JSON member whose key [`is_secret_name`]
/// hidden, wherever the JSON sits (a curl `--data`/`--json` body, a line of
/// a tool's output): `{"token":"X"}` becomes `{"token":"<redacted>"}`, an
/// object or array value becomes `"<redacted>"` and a number `<redacted>`.
/// `true`, `false`, `null` and a value already (partly) `<redacted>` are
/// kept, so `"Basic <redacted>"` keeps its scheme. A value cut off before
/// its end is hidden to the end of its line.
pub fn redact_json_secrets(text: &str) -> String {
    let b = text.as_bytes();
    let skip_ws = |j: usize| {
        j + b[j..]
            .iter()
            .take_while(|c| c.is_ascii_whitespace())
            .count()
    };
    let line_end = |j: usize| {
        j + b[j..]
            .iter()
            .take_while(|c| **c != b'\n' && **c != b'\r')
            .count()
    };
    // The closing quote of the string opening at `open`, past `\` escapes.
    // A JSON string never spans lines, so a stray quote in prose throws off
    // the pairing of quotes on its own line only.
    let string_close = |open: usize| {
        let mut k = open + 1;
        while k < b.len() {
            match b[k] {
                b'\\' => k += 2,
                b'"' => return Some(k),
                b'\n' | b'\r' => return None,
                _ => k += 1,
            }
        }
        None
    };
    // Just past the bracket closing the object or array opening at `open`.
    let container_end = |open: usize| {
        let mut depth = 0usize;
        let mut k = open;
        while k < b.len() {
            match b[k] {
                b'"' => match string_close(k) {
                    Some(c) => k = c,
                    None => return b.len(),
                },
                b'{' | b'[' => depth += 1,
                b'}' | b']' => {
                    depth -= 1;
                    if depth == 0 {
                        return k + 1;
                    }
                }
                _ => {}
            }
            k += 1;
        }
        b.len()
    };
    let mut spans: Vec<(usize, usize, &str)> = Vec::new();
    let mut i = 0;
    while i < b.len() {
        if b[i] != b'"' {
            i += 1;
            continue;
        }
        let Some(close) = string_close(i) else {
            i = line_end(i);
            continue;
        };
        let key = &text[i + 1..close];
        i = close + 1;
        let colon = skip_ws(i);
        if colon >= b.len() || b[colon] != b':' || !is_secret_name(key) {
            continue;
        }
        let v = skip_ws(colon + 1);
        if v >= b.len() || text[v..].starts_with(REDACTED) {
            continue;
        }
        match b[v] {
            b'"' => {
                let end = string_close(v).unwrap_or_else(|| line_end(v));
                if end > v + 1 && !text[v + 1..end].contains(REDACTED) {
                    spans.push((v + 1, end, REDACTED));
                }
                i = end;
            }
            b'{' | b'[' => {
                let end = container_end(v);
                spans.push((v, end, "\"<redacted>\""));
                i = end;
            }
            _ => {
                let end = v + b[v..]
                    .iter()
                    .take_while(|c| !c.is_ascii_whitespace() && !b",}]".contains(c))
                    .count();
                if end > v && !matches!(&text[v..end], "true" | "false" | "null") {
                    spans.push((v, end, REDACTED));
                }
                i = end;
            }
        }
    }
    let mut out = String::with_capacity(text.len());
    let mut copied = 0;
    for (start, end, with) in spans {
        out.push_str(&text[copied..start]);
        out.push_str(with);
        copied = end;
    }
    out.push_str(&text[copied..]);
    out
}

fn redact_arg_by_shape(arg: &str) -> String {
    let lower = arg.to_ascii_lowercase();
    if let Some(i) = lower.find("authorization:") {
        return format!("{} {}", &arg[..i + "authorization:".len()], REDACTED);
    }
    if lower.starts_with("pass:") {
        return format!("pass:{}", REDACTED);
    }
    // The name before each `=` is what follows the previous one, so
    // `--remote_header=x-buildbuddy-api-key=V` is judged by
    // `x-buildbuddy-api-key`.
    let mut start = 0;
    let mut secret_eq = None;
    for (i, _) in arg.match_indices('=') {
        if is_secret_name(&arg[start..i]) {
            secret_eq = Some(i);
            break;
        }
        start = i + 1;
    }
    let url_at = arg.find("://");
    let header = redact_secret_header(arg);
    // A secret-named `NAME=` that comes before a URL or a header hides the
    // whole value, whatever it holds: `MY_PASSWORD=db-password:hunter2`
    // and `TOKEN=https://hooks.slack.com/…` are one secret each, not a
    // header or a URL with a little hidden.
    if let Some(i) = secret_eq {
        if url_at.map_or(true, |u| i < u) && header.as_ref().map_or(true, |(c, _)| i < *c) {
            return format!("{}={}", &arg[..i], REDACTED);
        }
    }
    if let Some(url) = redact_url(arg) {
        return url;
    }
    if let Some((_, header)) = header {
        return header;
    }
    match secret_eq {
        Some(i) => format!("{}={}", &arg[..i], REDACTED),
        None => arg.to_string(),
    }
}

/// A `Name: value` header (as `-H` or `--header=` passes it) whose name
/// [`is_secret_name`], any case: `X-Api-Key`, `PRIVATE-TOKEN`,
/// `X-Auth-Token`. The name must look like a header name, so a path or a
/// time holding a colon is left alone. Also answers where the colon is.
fn redact_secret_header(arg: &str) -> Option<(usize, String)> {
    let colon = arg.find(':')?;
    let before = &arg[..colon];
    let name = before.rsplit('=').next().unwrap_or(before);
    if name.is_empty()
        || !name
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_')
        || !(is_secret_name(name) || is_cookie_header(name))
    {
        return None;
    }
    let value = &arg[colon + 1..];
    let space = &value[..value.len() - value.trim_start().len()];
    Some((colon, format!("{}{}{}", &arg[..colon + 1], space, REDACTED)))
}

/// The prefixes GitHub gives its tokens: personal (classic and
/// fine-grained), OAuth, user-to-server, server-to-server (an App's
/// installation token) and refresh.
const GITHUB_TOKEN_PREFIXES: [&str; 6] = ["github_pat_", "ghp_", "gho_", "ghu_", "ghs_", "ghr_"];

/// `text` with every GitHub token hidden by its prefix, wherever it sits:
/// after `;`, `=`, `(`, a quote or at the start of a word, not only where a
/// name like `token=` or a URL's userinfo announces it. A token runs while
/// its characters are letters, digits or `_`, so what follows it (`!`, `)`,
/// `]`, `,`, `.`, a quote) is kept. A prefix right after a letter
/// (`xghp_…`) or with nothing after it is not a token.
pub fn redact_github_tokens(text: &str) -> String {
    let bytes = text.as_bytes();
    let mut out = String::with_capacity(text.len());
    let mut copied = 0;
    let mut i = 0;
    while i < bytes.len() {
        // Only a letter before the prefix makes it part of a longer word:
        // a token glued to a number (`run 42ghs_…`) is still one.
        let at_word_start = i == 0 || !bytes[i - 1].is_ascii_alphabetic();
        let prefix = GITHUB_TOKEN_PREFIXES
            .iter()
            .find(|p| bytes[i..].starts_with(p.as_bytes()));
        if let (true, Some(p)) = (at_word_start, prefix) {
            let body = i + p.len();
            let end = body
                + bytes[body..]
                    .iter()
                    .take_while(|b| b.is_ascii_alphanumeric() || **b == b'_')
                    .count();
            if end > body {
                // Both ends sit next to ASCII bytes, so on char boundaries.
                out.push_str(&text[copied..i]);
                out.push_str(REDACTED);
                copied = end;
                i = end;
                continue;
            }
        }
        i += 1;
    }
    out.push_str(&text[copied..]);
    out
}

/// `Cookie` and `Set-Cookie`, any case: a header whose value is a session.
fn is_cookie_header(name: &str) -> bool {
    name.eq_ignore_ascii_case("cookie") || name.eq_ignore_ascii_case("set-cookie")
}

/// The shortest token after a bare `Bearer` that [`redact_credentials_in_text`]
/// hides: real tokens are far longer, and prose (`the bearer of …`) is not.
pub const MIN_BEARER_TOKEN: usize = 8;

/// `text` with the credentials that announce themselves hidden, though no
/// environment variable holds them (a token minted at run time): the value
/// of an `Authorization:` header after its scheme (`token`, `Bearer`,
/// `Basic`, …), also as a JSON key or as `authorization=`; the value of any
/// other secret-named header (`X-Auth-Token: …`) or `name=value` pair
/// (`password=…`); a token of at least
/// [`MIN_BEARER_TOKEN`] characters after a bare `Bearer`; and the rest of
/// the line after `Cookie:` or `Set-Cookie:`, unless already `<redacted>`.
/// A credential runs to a blank, quote, `,`, `;` or closing bracket, which
/// are kept.
pub fn redact_credentials_in_text(text: &str) -> String {
    let lower = text.to_ascii_lowercase();
    let b = text.as_bytes();
    let word_start = |i: usize| i == 0 || !b[i - 1].is_ascii_alphanumeric();
    let is_cred = |c: u8| !c.is_ascii_whitespace() && !b"\"'`,;)]}<>".contains(&c);
    let cred_end = |j: usize| j + b[j..].iter().take_while(|c| is_cred(**c)).count();
    let skip_blank = |j: usize| {
        j + b[j..]
            .iter()
            .take_while(|c| **c == b' ' || **c == b'\t')
            .count()
    };
    let is_quote = |j: usize| j < b.len() && (b[j] == b'"' || b[j] == b'\'');
    let is_name = |c: u8| c.is_ascii_alphanumeric() || c == b'-' || c == b'_';
    let mut spans: Vec<(usize, usize)> = Vec::new();
    // A secret-named `Name: value` header or `name=value` pair. A header
    // name must look like one (`X-Auth-Token`, `api_key`, `Authorization`),
    // so prose such as `token: expired` is kept; any secret name before `=`
    // counts (`password=…`, `authorization=token …`).
    let mut i = 0;
    while i < b.len() {
        if !is_name(b[i]) || (i > 0 && is_name(b[i - 1])) {
            i += 1;
            continue;
        }
        let name_end = i + b[i..].iter().take_while(|c| is_name(**c)).count();
        let name = &text[i..name_end];
        i = name_end;
        // A JSON key's closing quote may sit between the name and its `:`.
        let mut j = name_end;
        if is_quote(j) {
            j += 1;
        }
        if j >= b.len() || !is_secret_name(name) {
            continue;
        }
        let header_like = name.eq_ignore_ascii_case("authorization") || name.contains(['-', '_']);
        j = match b[j] {
            b':' if header_like => skip_blank(j + 1),
            b'=' => j + 1,
            _ => continue,
        };
        let quote = if is_quote(j) {
            j += 1;
            Some(b[j - 1])
        } else {
            None
        };
        if text[j..].starts_with(REDACTED) {
            continue;
        }
        // An authorization's scheme, then a blank: the credential is what
        // follows. Other values have no scheme: `password=abc def` hides
        // `abc`.
        if name.to_ascii_lowercase().contains("authorization") {
            let w = j + b[j..]
                .iter()
                .take_while(|c| c.is_ascii_alphabetic())
                .count();
            if w > j && w < b.len() && (b[w] == b' ' || b[w] == b'\t') {
                let k = skip_blank(w);
                if text[k..].starts_with(REDACTED) {
                    continue;
                }
                if k < b.len() && is_cred(b[k]) {
                    j = k;
                }
            }
        }
        // A quoted value runs to its closing quote, blanks and all.
        let e = match quote {
            Some(q) => {
                j + b[j..]
                    .iter()
                    .take_while(|c| **c != q && **c != b'\n' && **c != b'\r')
                    .count()
            }
            None => cred_end(j),
        };
        if e > j {
            spans.push((j, e));
        }
    }
    for (i, _) in lower.match_indices("bearer") {
        let j = i + "bearer".len();
        if !word_start(i) || j >= b.len() || !(b[j] == b' ' || b[j] == b'\t') {
            continue;
        }
        let j = skip_blank(j);
        let e = cred_end(j);
        if e - j >= MIN_BEARER_TOKEN {
            spans.push((j, e));
        }
    }
    for (i, _) in lower.match_indices("cookie:") {
        if !word_start(i) {
            continue;
        }
        let j = skip_blank(i + "cookie:".len());
        let e = j + b[j..]
            .iter()
            .take_while(|c| **c != b'\n' && **c != b'\r')
            .count();
        if e > j && !text[j..].starts_with(REDACTED) {
            spans.push((j, e));
        }
    }
    spans.sort();
    let mut out = String::with_capacity(text.len());
    let mut copied = 0;
    for (start, end) in spans {
        if end <= copied {
            continue;
        }
        let start = start.max(copied);
        out.push_str(&text[copied..start]);
        out.push_str(REDACTED);
        copied = end;
    }
    out.push_str(&text[copied..]);
    out
}

/// `arg` with the credentials of the URL in it hidden, or `None` when it
/// holds no URL: the password of `user:password@` (or the whole userinfo
/// when it is a bare token), whatever follows the host and even when the
/// password itself holds `/`, `?` or `#` (as base64 does); and the value of
/// each query or fragment parameter that names a secret
/// ([`is_secret_url_param`]), as `?access_token=` does.
pub fn redact_url(arg: &str) -> Option<String> {
    let scheme_end = arg.find("://")? + 3;
    let rest = &arg[scheme_end..];
    let sep = rest.find(['/', '?', '#']).unwrap_or(rest.len());
    let at = match rest[..sep].rfind('@') {
        Some(at) => Some(at),
        // No `@` before the first separator, but `user:pa/ss@host`: a
        // password holding a separator. A port (`host:8080/@scope`,
        // `[::1]:8080/@scope`) is not.
        None => rest[..sep].rfind(':').and_then(|colon| {
            let port = &rest[colon + 1..sep];
            let is_port = !port.is_empty() && port.bytes().all(|b| b.is_ascii_digit());
            if is_port {
                None
            } else {
                rest[sep..].find('@').map(|i| sep + i)
            }
        }),
    };
    let mut out = String::with_capacity(arg.len());
    out.push_str(&arg[..scheme_end]);
    let after_userinfo = match at {
        Some(at) => {
            match rest[..at].find(':') {
                Some(colon) => {
                    out.push_str(&rest[..colon + 1]);
                    out.push_str(REDACTED);
                }
                // `https://TOKEN@host`: the whole userinfo is the secret.
                None => out.push_str(REDACTED),
            }
            &rest[at..]
        }
        None => rest,
    };
    // The query and fragment: hide each secret parameter's value.
    let params_start = after_userinfo
        .find(['?', '#'])
        .unwrap_or(after_userinfo.len());
    out.push_str(&after_userinfo[..params_start]);
    let params = &after_userinfo[params_start..];
    let mut piece_start = 0;
    for (i, c) in params.char_indices().chain([(params.len(), '\0')]) {
        if i == params.len() || (i > 0 && matches!(c, '&' | '?' | '#' | ';')) {
            let piece = &params[piece_start..i];
            // Each piece is a separator followed by `name=value`.
            let (lead, body) = piece.split_at(piece.len().min(1));
            match body.split_once('=') {
                Some((name, _)) if is_secret_url_param(name) => {
                    out.push_str(lead);
                    out.push_str(name);
                    out.push('=');
                    out.push_str(REDACTED);
                }
                _ => out.push_str(piece),
            }
            piece_start = i;
        }
    }
    Some(out)
}

/// Whether a URL query or fragment parameter carries a secret: any name
/// [`is_secret_name`] (`access_token`, `client_secret`, `api_key`), a
/// signed URL's signature (`sig`, `X-Goog-Signature`, `X-Amz-Signature`),
/// and a bare `key`, which in a URL is an API key (`?key=AIza…`).
pub fn is_secret_url_param(name: &str) -> bool {
    let lower = name.to_ascii_lowercase();
    is_secret_name(&lower)
        || matches!(lower.as_str(), "key" | "sig")
        || lower
            .split(|c: char| !c.is_ascii_alphanumeric())
            .any(|w| w == "signature")
}

/// A new private (0700) folder under `parent`, like `mktemp -d`.
pub fn make_temp_dir(parent: &Path, prefix: &str) -> std::io::Result<PathBuf> {
    thread_local!(static SEQ: RefCell<u64> = const { RefCell::new(0) });
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    let seq = SEQ.with(|s| {
        let mut s = s.borrow_mut();
        *s += 1;
        *s
    });
    let dir = parent.join(format!(
        "{}.{}.{}.{}",
        prefix,
        std::process::id(),
        nanos,
        seq
    ));
    let mut b = fs::DirBuilder::new();
    #[cfg(unix)]
    {
        use std::os::unix::fs::DirBuilderExt;
        b.mode(0o700);
    }
    b.create(&dir)?;
    Ok(dir)
}

/// Writes `bytes` to a new file readable by its owner alone (umask 077).
pub fn write_private(path: &Path, bytes: &[u8]) -> std::io::Result<()> {
    let _ = fs::remove_file(path);
    let mut o = fs::OpenOptions::new();
    o.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        o.mode(0o600);
    }
    let mut f = o.open(path)?;
    f.write_all(bytes)
}

/// Paths removed if SIGHUP, SIGINT or SIGTERM ends the process: the
/// notary key and the signing certificates, which a script's `trap … EXIT`
/// removed on Ctrl-C or a cancelled CI job and a `Drop` never sees.
#[cfg(unix)]
mod on_signal {
    use std::ffi::CString;
    use std::os::raw::{c_char, c_int};
    use std::os::unix::ffi::OsStrExt;
    use std::path::Path;
    use std::ptr;
    use std::sync::atomic::{AtomicPtr, Ordering};
    use std::sync::Once;

    const SLOTS: usize = 16;
    const SIGNALS: [c_int; 3] = [1, 2, 15]; // SIGHUP, SIGINT, SIGTERM
    const SIG_DFL: usize = 0;
    const SIG_IGN: usize = 1;

    #[allow(clippy::declare_interior_mutable_const)]
    const EMPTY: AtomicPtr<c_char> = AtomicPtr::new(ptr::null_mut());
    static PATHS: [AtomicPtr<c_char>; SLOTS] = [EMPTY; SLOTS];
    static INSTALL: Once = Once::new();

    extern "C" {
        fn signal(sig: c_int, handler: usize) -> usize;
        fn raise(sig: c_int) -> c_int;
        fn unlink(path: *const c_char) -> c_int;
        fn rmdir(path: *const c_char) -> c_int;
    }

    // Only async-signal-safe calls: unlink, rmdir, signal, raise.
    extern "C" fn handle(sig: c_int) {
        // Files first, so the folders that held them are empty for rmdir.
        for slot in PATHS.iter().rev() {
            let p = slot.load(Ordering::SeqCst);
            if !p.is_null() {
                unsafe {
                    if unlink(p) != 0 {
                        rmdir(p);
                    }
                }
            }
        }
        // Then die of the same signal, so the exit status says so (128+N).
        unsafe {
            signal(sig, SIG_DFL);
            raise(sig);
        }
    }

    /// Removes `path` if a signal ends the process, until dropped.
    pub struct Guard(usize);

    impl Drop for Guard {
        fn drop(&mut self) {
            let p = PATHS[self.0].swap(ptr::null_mut(), Ordering::SeqCst);
            if !p.is_null() {
                drop(unsafe { CString::from_raw(p) });
            }
        }
    }

    /// Whether a signal now would remove `path`.
    pub fn covers(path: &Path) -> bool {
        let want = path.as_os_str().as_bytes();
        PATHS.iter().any(|slot| {
            let p = slot.load(Ordering::SeqCst);
            !p.is_null() && unsafe { std::ffi::CStr::from_ptr(p) }.to_bytes() == want
        })
    }

    pub fn remove(path: &Path) -> Option<Guard> {
        INSTALL.call_once(|| {
            for sig in SIGNALS {
                // Ignore first, which returns what was there. A signal the
                // parent ignored (`nohup` ignores SIGHUP) stays ignored, as a
                // shell's `trap` cannot override an inherited ignore either;
                // anything else gets the handler.
                unsafe {
                    if signal(sig, SIG_IGN) != SIG_IGN {
                        signal(sig, handle as extern "C" fn(c_int) as usize);
                    }
                }
            }
        });
        let c = CString::new(path.as_os_str().as_bytes()).ok()?.into_raw();
        for (i, slot) in PATHS.iter().enumerate() {
            if slot
                .compare_exchange(ptr::null_mut(), c, Ordering::SeqCst, Ordering::SeqCst)
                .is_ok()
            {
                return Some(Guard(i));
            }
        }
        drop(unsafe { CString::from_raw(c) });
        None
    }
}

/// Removes `path` (a file, or an empty folder) if SIGHUP, SIGINT or
/// SIGTERM ends the process before the returned guard is dropped. Register
/// a folder before the files in it.
pub struct SignalCleanup {
    #[cfg(unix)]
    _guard: Option<on_signal::Guard>,
}

pub fn remove_on_signal(path: &Path) -> SignalCleanup {
    SignalCleanup {
        #[cfg(unix)]
        _guard: on_signal::remove(path),
    }
}

/// Whether a signal now would remove `path`.
pub fn signal_cleanup_covers(path: &Path) -> bool {
    #[cfg(unix)]
    {
        on_signal::covers(path)
    }
    #[cfg(not(unix))]
    {
        let _ = path;
        false
    }
}

/// A private (0700) work folder for secrets: removed when dropped, and
/// removed with the named files in it if a signal ends the run first. The
/// folder is removed before the signal cover is dropped, so there is no
/// moment where it exists uncovered.
pub struct PrivateWorkDir {
    path: PathBuf,
    covers: Vec<SignalCleanup>,
}

impl PrivateWorkDir {
    pub fn path(&self) -> &Path {
        &self.path
    }
}

/// [`make_temp_dir`] under `parent`, covered with `files` (names in it)
/// against a signal; see [`PrivateWorkDir`].
pub fn private_work_dir(
    parent: &Path,
    prefix: &str,
    files: &[&str],
) -> std::io::Result<PrivateWorkDir> {
    let path = make_temp_dir(parent, prefix)?;
    // The folder first, so the handler removes the files before it.
    let mut covers = vec![remove_on_signal(&path)];
    covers.extend(files.iter().map(|f| remove_on_signal(&path.join(f))));
    Ok(PrivateWorkDir { path, covers })
}

#[cfg(test)]
thread_local! {
    /// Called between removing a work folder and dropping its cover.
    static AFTER_WORK_DIR_REMOVED: RefCell<Option<Box<dyn FnMut()>>> = RefCell::new(None);
}

impl Drop for PrivateWorkDir {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.path);
        #[cfg(test)]
        AFTER_WORK_DIR_REMOVED.with(|h| {
            if let Some(f) = h.borrow_mut().as_mut() {
                f();
            }
        });
        self.covers.clear();
    }
}

/// Removes a folder when dropped, as a script's `trap … EXIT` does.
pub struct TempDir(pub PathBuf);

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

/// The temp folder a script's `mktemp` uses: `$TMPDIR`, else `/tmp`.
pub fn temp_root() -> PathBuf {
    std::env::var_os("TMPDIR")
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/tmp"))
}

/// Decodes standard base64, as `base64 --decode` does; whitespace is
/// skipped and anything else outside the alphabet is an error.
pub fn decode_base64(input: &str) -> Result<Vec<u8>, String> {
    let mut out = Vec::new();
    let mut buf: u32 = 0;
    let mut bits: u8 = 0;
    for b in input.bytes() {
        if b.is_ascii_whitespace() || b == b'=' {
            continue;
        }
        let val = match b {
            b'A'..=b'Z' => b - b'A',
            b'a'..=b'z' => b - b'a' + 26,
            b'0'..=b'9' => b - b'0' + 52,
            b'+' => 62,
            b'/' => 63,
            _ => return Err(format!("invalid base64 byte: 0x{:02x}", b)),
        };
        buf = (buf << 6) | (val as u32);
        bits += 6;
        if bits >= 8 {
            bits -= 8;
            out.push(((buf >> bits) & 0xff) as u8);
        }
    }
    Ok(out)
}

/// The first `Developer ID Application` identity in `security find-identity
/// -v -p codesigning` output, as `grep … | head -1 | sed -E 's/.*"(.*)".*/\1/'`.
pub fn developer_id_from_listing(listing: &str) -> Option<String> {
    let line = listing
        .lines()
        .find(|l| l.contains("Developer ID Application"))?;
    let first = line.find('"')?;
    let last = line.rfind('"')?;
    if last <= first {
        return None;
    }
    let id = &line[first + 1..last];
    if id.is_empty() {
        None
    } else {
        Some(id.to_string())
    }
}

/// The installed Developer ID identity, if there is one.
pub fn detect_developer_id(r: &mut dyn Runner) -> Option<String> {
    let out = r.output(&Cmd::new("security").args(["find-identity", "-v", "-p", "codesigning"]));
    developer_id_from_listing(&out.stdout)
}

/// `CFBundleShortVersionString` of an Info.plist, read with PlistBuddy as
/// the scripts read it.
pub fn plist_short_version(r: &mut dyn Runner, plist: &Path) -> Result<String, i32> {
    let v = capture(
        r,
        &Cmd::new("/usr/libexec/PlistBuddy")
            .args(["-c", "Print CFBundleShortVersionString"])
            .path(plist),
    )?;
    let v = v.trim().to_string();
    if v.is_empty() {
        eprintln!("✗ {} has no CFBundleShortVersionString", plist.display());
        return Err(1);
    }
    Ok(v)
}

/// The package folder (`apps/desktop/vitruvian`) under the workspace that
/// `bazel run` was started in, else the git checkout, else the current
/// folder.
pub fn workspace_root() -> PathBuf {
    if let Some(w) = std::env::var_os("BUILD_WORKSPACE_DIRECTORY").filter(|v| !v.is_empty()) {
        return PathBuf::from(w);
    }
    if let Ok(o) = Command::new("git")
        .args(["rev-parse", "--show-toplevel"])
        .output()
    {
        if o.status.success() {
            let s = String::from_utf8_lossy(&o.stdout).trim().to_string();
            if !s.is_empty() {
                return PathBuf::from(s);
            }
        }
    }
    std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."))
}

pub const PKG_REL: &str = "apps/desktop/vitruvian";

pub fn package_dir() -> PathBuf {
    workspace_root().join(PKG_REL)
}

/// A path given on the command line, made absolute against the folder
/// `bazel run` was started from (its runfiles folder is no one's cwd).
pub fn user_path(arg: &str) -> PathBuf {
    let p = PathBuf::from(arg);
    if p.is_absolute() {
        return p;
    }
    let base = std::env::var_os("BUILD_WORKING_DIRECTORY")
        .filter(|v| !v.is_empty())
        .map(PathBuf::from)
        .or_else(|| std::env::current_dir().ok())
        .unwrap_or_else(|| PathBuf::from("."));
    base.join(p)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn developer_id_is_the_first_developer_id_application_line() {
        let listing = "  1) AAAA \"Apple Development: Someone (X)\"\n  2) BBBB \"Developer ID Application: Vitruvian Software (TEAM123)\"\n  3) CCCC \"Developer ID Application: Other (T2)\"\n     3 valid identities found\n";
        assert_eq!(
            developer_id_from_listing(listing).as_deref(),
            Some("Developer ID Application: Vitruvian Software (TEAM123)")
        );
        assert_eq!(
            developer_id_from_listing("0 valid identities found\n"),
            None
        );
    }

    #[test]
    fn base64_decodes_like_base64_decode() {
        assert_eq!(decode_base64("aGVs\nbG8=").unwrap(), b"hello");
        assert!(decode_base64("a*b").is_err());
    }

    #[test]
    fn capture_returns_the_failing_code() {
        let mut r = FakeRunner::new(|c| {
            if c.program == "bad" {
                Out::fail(3, "nope")
            } else {
                Out::ok("yes\n")
            }
        });
        assert_eq!(capture(&mut r, &Cmd::new("good")).unwrap(), "yes\n");
        assert_eq!(capture(&mut r, &Cmd::new("bad")), Err(3));
        assert_eq!(r.calls, vec!["good", "bad"]);
    }

    #[test]
    fn a_failed_capture_reports_which_command_and_its_stderr() {
        let mut r = FakeRunner::new(|_| Out::fail(1, "gh: API rate limit exceeded (HTTP 403)\n"));
        assert_eq!(
            capture(
                &mut r,
                &Cmd::new("gh").args(["api", "repos/x/y/compare/a...b"])
            ),
            Err(1)
        );
        assert!(
            r.stderr.contains("gh api repos/x/y/compare/a...b"),
            "names the command: {:?}",
            r.stderr
        );
        assert!(
            r.stderr.contains("gh: API rate limit exceeded (HTTP 403)"),
            "passes its stderr through: {:?}",
            r.stderr
        );
        // A success prints nothing of its own.
        let mut ok = FakeRunner::succeeding();
        capture(&mut ok, &Cmd::new("true")).unwrap();
        assert_eq!(ok.stderr, "");
    }

    #[test]
    fn a_failed_capture_never_reports_a_secret_on_its_command_line() {
        let mut r = FakeRunner::new(|_| Out::fail(2, "boom\n"));
        let _ = capture(
            &mut r,
            &Cmd::new("bazel").args([
                "cquery",
                "--remote_header=x-buildbuddy-api-key=bb_SECRET",
                "//a:b",
            ]),
        );
        assert!(!r.stderr.contains("bb_SECRET"), "{:?}", r.stderr);
        assert!(
            r.stderr.contains("x-buildbuddy-api-key=<redacted>"),
            "{:?}",
            r.stderr
        );
    }

    fn red(program: &str, args: &[&str]) -> String {
        Cmd::new(program).args(args).redacted_line()
    }

    #[test]
    fn the_redactions_from_the_first_review_still_hold() {
        assert_eq!(
            red(
                "bazel",
                &["build", "--remote_header=x-buildbuddy-api-key=abc=", "//x"]
            ),
            "bazel build --remote_header=x-buildbuddy-api-key=<redacted> //x"
        );
        assert_eq!(
            red(
                "git",
                &[
                    "clone",
                    "https://x-access-token:ghs_abc@github.com/o/r.git",
                    "dir"
                ]
            ),
            "git clone https://x-access-token:<redacted>@github.com/o/r.git dir"
        );
        assert_eq!(
            red("env", &["TOKEN=t1", "PASSWORD=p2", "SECRET=s3"]),
            "env TOKEN=<redacted> PASSWORD=<redacted> SECRET=<redacted>"
        );
        assert_eq!(
            red(
                "security",
                &[
                    "set-key-partition-list",
                    "-S",
                    "apple:",
                    "-s",
                    "-k",
                    "kcpass",
                    "/tmp/k.keychain"
                ]
            ),
            "security set-key-partition-list -S apple: -s -k <redacted> /tmp/k.keychain"
        );
        assert_eq!(
            red("tool", &["--password", "hunter2", "x"]),
            "tool --password <redacted> x"
        );
    }

    #[test]
    fn a_secret_holding_a_space_is_hidden_whole() {
        let mut r = FakeRunner::new(|_| Out::fail(1, "nope\n"));
        let _ = capture(
            &mut r,
            &Cmd::new("tool").args(["--password", "correct horse battery", "--token=staple two"]),
        );
        assert!(!r.stderr.contains("horse"), "{:?}", r.stderr);
        assert!(!r.stderr.contains("battery"), "{:?}", r.stderr);
        assert!(!r.stderr.contains("two"), "{:?}", r.stderr);
        assert!(
            r.stderr
                .contains("tool --password <redacted> --token=<redacted>"),
            "{:?}",
            r.stderr
        );
    }

    #[test]
    fn headers_bare_url_tokens_openssl_pass_and_client_secret_are_hidden() {
        let mut r = FakeRunner::new(|_| Out::fail(1, "nope\n"));
        let _ = capture(
            &mut r,
            &Cmd::new("curl").args([
                "-H",
                "Authorization: Bearer abc123def",
                "https://ghp_TOKENVALUE@github.com/o/r.git",
            ]),
        );
        let _ = capture(
            &mut r,
            &Cmd::new("openssl").args(["pkcs12", "-passout", "pass:p12-PASS", "-out", "id.p12"]),
        );
        let _ = capture(
            &mut r,
            &Cmd::new("tool").args(["--client-secret", "cs-VALUE", "--client-secret=cs-OTHER"]),
        );
        for leaked in [
            "abc123def",
            "ghp_TOKENVALUE",
            "p12-PASS",
            "cs-VALUE",
            "cs-OTHER",
        ] {
            assert!(
                !r.stderr.contains(leaked),
                "{} leaked: {:?}",
                leaked,
                r.stderr
            );
        }
        assert!(
            r.stderr
                .contains("-H Authorization: <redacted> https://<redacted>@github.com/o/r.git"),
            "{:?}",
            r.stderr
        );
        assert!(
            r.stderr.contains("-passout pass:<redacted> -out id.p12"),
            "{:?}",
            r.stderr
        );
        assert!(
            r.stderr
                .contains("--client-secret <redacted> --client-secret=<redacted>"),
            "{:?}",
            r.stderr
        );
    }

    #[test]
    fn a_failed_commands_stderr_hides_the_secrets_in_play() {
        let mut r = FakeRunner::new(|_| {
            Out::fail(
                1,
                "fatal: could not read from https://x-access-token:tok-SECRET-123@github.com\nbad key bb_KEY_VALUE\n",
            )
        });
        r.secrets = env_secrets(
            &[
                ("HOMEBREW_TAP_TOKEN", "tok-SECRET-123"), // gitleaks:allow (made-up test value)
                ("BUILDBUDDY_API_KEY", "bb_KEY_VALUE"),
                ("GRADE", "beta"),
            ]
            .iter()
            .map(|(k, v)| (k.to_string(), v.to_string()))
            .collect(),
        );
        // A positional secret no flag rule knows about is still hidden.
        let _ = capture(&mut r, &Cmd::new("tool").args(["bb_KEY_VALUE"]));
        assert!(!r.stderr.contains("tok-SECRET-123"), "{:?}", r.stderr);
        assert!(!r.stderr.contains("bb_KEY_VALUE"), "{:?}", r.stderr);
        assert!(
            r.stderr.contains("✗ `tool <redacted>` failed"),
            "{:?}",
            r.stderr
        );
        assert!(r.stderr.contains("bad key <redacted>"), "{:?}", r.stderr);
    }

    #[test]
    fn env_secrets_are_the_secret_variables_values_only() {
        let env: BTreeMap<String, String> = [
            ("BUILDBUDDY_API_KEY", "bb"),
            ("HOMEBREW_TAP_TOKEN", "tok"),
            ("SIGNING_CERT_P12", "p12b64"),
            ("SIGNING_CERT_PASSWORD", "pw"),
            ("NOTARY_API_KEY_P8", "p8b64"),
            ("NOTARY_KEY_ID", "KEYID"),
            ("NOTARY_ISSUER_ID", "issuer"),
            ("GH_TOKEN", "ghs"),
            ("GRADE", "beta"),
            ("RUNNER_TEMP", "/tmp/r"),
            ("EMPTY_TOKEN", ""),
        ]
        .iter()
        .map(|(k, v)| (k.to_string(), v.to_string()))
        .collect();
        assert_eq!(
            env_secrets(&env),
            vec!["bb", "ghs", "p12b64", "p8b64", "pw", "tok"]
        );
        // Short values are left in text; long ones are hidden everywhere.
        assert_eq!(
            redact_known("pw tok p12b64 p12b64", &env_secrets(&env)),
            "pw tok <redacted> <redacted>"
        );
    }

    #[test]
    fn non_secrets_are_left_alone() {
        let mut r = FakeRunner::new(|_| Out::fail(1, "nope\n"));
        let cmds = [
            Cmd::new("security").args([
                "import",
                "/r/c.p12",
                "-k",
                "/r/ci.keychain",
                "-P",
                "p12pass",
                "-T",
                "/usr/bin/codesign",
            ]),
            Cmd::new("security").args(["find-identity", "-v", "-p", "codesigning"]),
            Cmd::new("tool").args([
                "cache_key=abc",
                "--keychain=/r/k.keychain",
                "--key-id=KEYID",
                "keyfile=/x/AuthKey.p8",
            ]),
            Cmd::new("ditto").args(["-c", "-k", "--keepParent", "a", "b"]),
            Cmd::new("gh").args([
                "api",
                "-X",
                "PATCH",
                "repos/o/r/git/refs/tags/t",
                "-f",
                "sha=abc",
                "-F",
                "force=true",
            ]),
        ];
        for c in &cmds {
            let _ = capture(&mut r, c);
        }
        for kept in [
            "security import /r/c.p12 -k /r/ci.keychain -P <redacted> -T /usr/bin/codesign",
            "security find-identity -v -p codesigning",
            "tool cache_key=abc --keychain=/r/k.keychain --key-id=KEYID keyfile=/x/AuthKey.p8",
            "ditto -c -k --keepParent a b",
            "gh api -X PATCH repos/o/r/git/refs/tags/t -f sha=abc -F force=true",
        ] {
            assert!(
                r.stderr.contains(kept),
                "expected `{}` in {:?}",
                kept,
                r.stderr
            );
        }
    }

    #[test]
    fn secret_query_parameters_are_hidden_and_others_kept() {
        assert_eq!(
            red(
                "curl",
                &["https://api.example.com/v1/x?access_token=tok-QUERY&page=2"]
            ),
            "curl https://api.example.com/v1/x?access_token=<redacted>&page=2"
        );
        assert_eq!(
            red(
                "curl",
                &["https://h/p?page=2&ACCESS_TOKEN=tok-AMP&client_secret=cs-Q#frag"]
            ),
            "curl https://h/p?page=2&ACCESS_TOKEN=<redacted>&client_secret=<redacted>#frag"
        );
        // OAuth's implicit flow puts the token in the fragment.
        assert_eq!(
            red("open", &["https://h/cb#access_token=tok-FRAG&state=s1"]),
            "open https://h/cb#access_token=<redacted>&state=s1"
        );
        // Signed-URL signatures and a bare `key=` API key, in a URL only.
        assert_eq!(
            red(
                "curl",
                &["https://h/o?X-Goog-Signature=abcd&sig=efgh&key=AIzaKEY"]
            ),
            "curl https://h/o?X-Goog-Signature=<redacted>&sig=<redacted>&key=<redacted>"
        );
        assert_eq!(
            red("curl", &["--url=https://h/p?access_token=tok-INLINE"]),
            "curl --url=https://h/p?access_token=<redacted>"
        );
        // Ordinary query parameters stay readable.
        assert_eq!(
            red(
                "curl",
                &["https://h/p?page=2&per_page=100&ref=main&state=open"]
            ),
            "curl https://h/p?page=2&per_page=100&ref=main&state=open"
        );
    }

    #[test]
    fn a_url_password_is_hidden_whatever_follows_the_host() {
        assert_eq!(
            red("git", &["clone", "https://u:SECRET@host/path/repo.git"]),
            "git clone https://u:<redacted>@host/path/repo.git"
        );
        // A base64 password holds `/`, `+` and `=`: still one password.
        assert_eq!(
            red("git", &["clone", "https://u:ab/cd+ef==@host/path"]),
            "git clone https://u:<redacted>@host/path"
        );
        assert_eq!(
            red("curl", &["https://u:pa?ss#word@host/p?q=1"]),
            "curl https://u:<redacted>@host/p?q=1"
        );
        // An `@` in the path and a port are not credentials.
        assert_eq!(
            red("curl", &["https://registry.npmjs.org/@types/node"]),
            "curl https://registry.npmjs.org/@types/node"
        );
        assert_eq!(
            red("curl", &["http://localhost:8080/@scope/pkg"]),
            "curl http://localhost:8080/@scope/pkg"
        );
        assert_eq!(
            red("curl", &["http://[::1]:8080/@scope/pkg"]),
            "curl http://[::1]:8080/@scope/pkg"
        );
    }

    #[test]
    fn a_secret_named_variable_hides_its_whole_value_whatever_it_holds() {
        // Review finding on #4123: the header rule ran first and showed
        // `db-password:` of a password's value.
        assert_eq!(
            red("env", &["MY_PASSWORD=db-password:hunter2"]),
            "env MY_PASSWORD=<redacted>"
        );
        // A webhook URL held in a secret variable is the secret itself.
        assert_eq!(
            red(
                "env",
                &["SLACK_TOKEN=https://hooks.slack.com/services/T0/B0/xyz"]
            ),
            "env SLACK_TOKEN=<redacted>"
        );
        // The other way round: a header's value holding `=` is all hidden.
        assert_eq!(
            red("curl", &["-H", "X-Api-Key: ab=cd"]),
            "curl -H X-Api-Key: <redacted>"
        );
        // A non-secret name before the URL leaves it to the URL rule.
        assert_eq!(
            red("curl", &["--url=https://u:pw@h/p?page=2"]),
            "curl --url=https://u:<redacted>@h/p?page=2"
        );
    }

    #[test]
    fn secret_headers_are_hidden_whatever_their_case() {
        for (header, want) in [
            ("x-api-key: k-LOWER", "x-api-key: <redacted>"),
            ("X-API-Key: k-MIXED", "X-API-Key: <redacted>"),
            ("X-Api-Key:k-NOSPACE", "X-Api-Key:<redacted>"),
            ("PRIVATE-TOKEN: glpat-x", "PRIVATE-TOKEN: <redacted>"),
            ("X-Auth-Token: t-H", "X-Auth-Token: <redacted>"),
        ] {
            assert_eq!(
                red("curl", &["-H", header, "https://h/"]),
                format!("curl -H {} https://h/", want)
            );
        }
        assert_eq!(
            red("curl", &["--header=x-api-key: k-INLINE"]),
            "curl --header=x-api-key: <redacted>"
        );
        // Other headers, and colons that are not headers, stay.
        assert_eq!(
            red(
                "curl",
                &[
                    "-H",
                    "Accept: application/vnd.github+json",
                    "-H",
                    "X-GitHub-Api-Version: 2022-11-28",
                    "-H",
                    "Content-Type: application/json"
                ]
            ),
            "curl -H Accept: application/vnd.github+json -H X-GitHub-Api-Version: 2022-11-28 -H Content-Type: application/json"
        );
        assert_eq!(
            red("tool", &["--at=10:00:00", "/x/AuthKey.p8:1", "apple:"]),
            "tool --at=10:00:00 /x/AuthKey.p8:1 apple:"
        );
    }

    #[test]
    fn curl_user_credentials_are_hidden_in_every_spelling() {
        assert_eq!(
            red("curl", &["-u", "bob:pw-SPACE", "https://h/"]),
            "curl -u <redacted> https://h/"
        );
        assert_eq!(
            red("/usr/bin/curl", &["--user", "bob:pw-LONG", "https://h/"]),
            "/usr/bin/curl --user <redacted> https://h/"
        );
        assert_eq!(
            red("curl", &["--user=bob:pw-EQ", "https://h/"]),
            "curl --user=<redacted> https://h/"
        );
        assert_eq!(
            red("curl", &["-ubob:pw-JOINED", "https://h/"]),
            "curl -u<redacted> https://h/"
        );
        assert_eq!(
            red("curl", &["-sSu", "bob:pw-CLUSTER", "https://h/"]),
            "curl -sSu <redacted> https://h/"
        );
        assert_eq!(
            red("curl", &["-U", "p:pw-PROXY", "--proxy-user=p:pw-PEQ"]),
            "curl -U <redacted> --proxy-user=<redacted>"
        );
        assert_eq!(
            red("curl", &["--oauth2-bearer", "tok-BEARER", "https://h/"]),
            "curl --oauth2-bearer <redacted> https://h/"
        );
        // `-u` / `--user` mean something else to other programs.
        assert_eq!(
            red("pip", &["install", "--user", "requests"]),
            "pip install --user requests"
        );
        assert_eq!(red("git", &["add", "-u", "src"]), "git add -u src");
        assert_eq!(
            red("curl", &["-sS", "-o", "out.json", "https://h/"]),
            "curl -sS -o out.json https://h/"
        );
    }

    #[test]
    fn curl_flags_that_take_a_value_end_the_cluster_so_x_put_is_not_a_credential() {
        // `-XPUT`: `X` takes the method as its value, so the `U` in PUT is
        // not curl's `-U` (proxy user). Likewise `-o`/`-T` take a file name.
        assert_eq!(
            red(
                "curl",
                &["-XPUT", "-XPOST", "-sXPUT", "-X", "PUT", "https://h/"]
            ),
            "curl -XPUT -XPOST -sXPUT -X PUT https://h/"
        );
        assert_eq!(
            red(
                "curl",
                &["-oupload.bin", "-Tupdate.json", "-sSfL", "https://h/"]
            ),
            "curl -oupload.bin -Tupdate.json -sSfL https://h/"
        );
        // A credential flag before the value-taking one still counts, and
        // one after it is the other flag's value.
        assert_eq!(
            red("curl", &["-sUp:pw-PROXY", "-XPUT", "https://h/"]),
            "curl -sU<redacted> -XPUT https://h/"
        );
        assert_eq!(
            red("curl", &["-ufoo:pw-USER", "-sSu", "bob:pw-NEXT"]),
            "curl -u<redacted> -sSu <redacted>"
        );
        // Headers keep being judged by their name, attached or not.
        assert_eq!(
            red("curl", &["-XPUT", "-HAuthorization: Bearer tok-ATTACHED"]),
            "curl -XPUT -HAuthorization: <redacted>"
        );
    }

    #[test]
    fn github_tokens_are_hidden_wherever_they_sit_and_keep_what_follows() {
        for (arg, want) in [
            ("--data=a;ghp_AAAA1111bbbb", "--data=a;<redacted>"),
            ("note:ghs_MINTED22!", "note:<redacted>!"),
            ("(gho_OAUTH33)", "(<redacted>)"),
            ("[ghu_USER44],", "[<redacted>],"),
            ("\"ghr_REFRESH55\"", "\"<redacted>\""),
            ("'github_pat_11ABCD_efgh66'", "'<redacted>'"),
            ("x=1&t=ghp_QUERY77.", "x=1&t=<redacted>."),
            ("ghp_WHOLE88", "<redacted>"),
            // Not tokens: a longer word ending in the prefix, a bare prefix.
            ("xghp_notatoken", "xghp_notatoken"),
            ("ghp_", "ghp_"),
            ("ghx_OTHER", "ghx_OTHER"),
        ] {
            assert_eq!(red("tool", &[arg]), format!("tool {}", want), "{}", arg);
        }
        // In output a tool prints, which no environment variable names.
        let mut r = FakeRunner::new(|_| {
            Out::fail(
                1,
                "remote: token ghs_RUNTIME99, rejected (see github_pat_11ZZ_yy) ok\n",
            )
        });
        let _ = capture(&mut r, &Cmd::new("git").args(["push"]));
        assert!(!r.stderr.contains("RUNTIME99"), "{:?}", r.stderr);
        assert!(!r.stderr.contains("11ZZ_yy"), "{:?}", r.stderr);
        assert!(
            r.stderr
                .contains("remote: token <redacted>, rejected (see <redacted>) ok\n"),
            "{:?}",
            r.stderr
        );
    }

    #[test]
    fn curl_certificate_passwords_are_hidden_and_the_path_kept() {
        // `-E`/`--cert` take `certificate[:password]`.
        assert_eq!(
            red(
                "curl",
                &[
                    "-E",
                    "cert.pem:pw-SHORT",
                    "--cert",
                    "c.pem:pw-LONG",
                    "--cert=c.pem:pw-EQ",
                    "-Ec.pem:pw-JOINED",
                    "-sSEc.pem:pw-CLUSTER",
                    "--proxy-cert",
                    "p.pem:pw-PX",
                    "https://h/",
                ]
            ),
            "curl -E cert.pem:<redacted> --cert c.pem:<redacted> --cert=c.pem:<redacted> -Ec.pem:<redacted> -sSEc.pem:<redacted> --proxy-cert p.pem:<redacted> https://h/"
        );
        // The private key's passphrase is a secret whole.
        assert_eq!(
            red(
                "curl",
                &[
                    "--pass",
                    "pw-PASS",
                    "--pass=pw-PEQ",
                    "--proxy-pass",
                    "pw-PP"
                ]
            ),
            "curl --pass <redacted> --pass=<redacted> --proxy-pass <redacted>"
        );
        // No password: the path is kept. An escaped colon is part of the
        // path; a PKCS#11 URI is hidden after its scheme (it can carry
        // `pin-value=`). A Windows path is in
        // `a_windows_style_cert_path_is_read_as_curl_on_macos_reads_it`.
        for (cert, want) in [
            ("cert.pem", "cert.pem"),
            ("a\\:b.pem:pw-ESC", "a\\:b.pem:<redacted>"),
            ("pkcs11:token=t;pin-value=1234", "pkcs11:<redacted>"),
        ] {
            assert_eq!(
                red("curl", &["--cert", cert]),
                format!("curl --cert {}", want),
                "{}",
                cert
            );
        }
        // `-E` means something else to other programs.
        assert_eq!(red("grep", &["-E", "a:b"]), "grep -E a:b");
    }

    #[test]
    fn curl_data_attached_to_its_flag_is_judged_by_its_name() {
        assert_eq!(
            red(
                "curl",
                &[
                    "-dtoken=SECRET-D",
                    "-sSdpassword=SECRET-CL",
                    "--data=password=SECRET-DATA",
                    "--data-raw",
                    "api_key=SECRET-RAW",
                    "--data-urlencode",
                    "client_secret=SECRET-URL",
                    "--data-urlencode=token=SECRET-UEQ",
                    "-Ftoken=SECRET-F",
                    "--form",
                    "password=SECRET-FORM",
                    "-d",
                    "page=2",
                    "-dpage=3",
                ]
            ),
            "curl -dtoken=<redacted> -sSdpassword=<redacted> --data=password=<redacted> --data-raw api_key=<redacted> --data-urlencode client_secret=<redacted> --data-urlencode=token=<redacted> -Ftoken=<redacted> --form password=<redacted> -d page=2 -dpage=3"
        );
    }

    #[test]
    fn cookies_are_hidden_in_headers_curl_cookie_flags_and_output() {
        assert_eq!(
            red(
                "curl",
                &[
                    "-H",
                    "Cookie: session=SECRET-H",
                    "--header=cookie: sid=SECRET-HEQ",
                    "-b",
                    "session=SECRET-B",
                    "--cookie",
                    "a=SECRET-C; b=2",
                    "--cookie=sid=SECRET-CEQ",
                    "-bsid=SECRET-BJ",
                    "-b",
                    "cookies.txt",
                    "-c",
                    "jar.txt",
                ]
            ),
            "curl -H Cookie: <redacted> --header=cookie: <redacted> -b <redacted> --cookie <redacted> --cookie=<redacted> -b<redacted> -b cookies.txt -c jar.txt"
        );
        let mut r = FakeRunner::new(|_| {
            Out::fail(
                1,
                "> Cookie: session=SECRET-OUT; theme=dark\r\n< Set-Cookie: id=SECRET-SET; Path=/\n",
            )
        });
        let _ = capture(
            &mut r,
            &Cmd::new("curl").args(["-v", "-H", "Cookie: a=SECRET-ARG", "https://h/"]),
        );
        assert!(!r.stderr.contains("SECRET"), "{:?}", r.stderr);
        assert!(
            r.stderr
                .contains("`curl -v -H Cookie: <redacted> https://h/` failed (exit 1)\n"),
            "{:?}",
            r.stderr
        );
        assert!(
            r.stderr
                .contains("> Cookie: <redacted>\r\n< Set-Cookie: <redacted>\n"),
            "{:?}",
            r.stderr
        );
    }

    #[test]
    fn authorization_values_in_output_are_hidden_without_a_known_secret() {
        // Minted at run time, so in no environment variable.
        let mut r = FakeRunner::new(|_| {
            Out::fail(
                1,
                "> Authorization: token tok-AUTHTOKEN\nsent authorization: Bearer eyJhbGciOi.payload.sig-JWT\nretrying with Bearer abcDEF123456789-BARE, then gave up\n{\"Authorization\": \"Basic dXNlcjpwYXNz\", \"x\": 1}\nproxy-authorization:raw-PROXYCRED\nthe bearer of bad news\n",
            )
        });
        let _ = capture(&mut r, &Cmd::new("tool"));
        for leaked in ["AUTHTOKEN", "sig-JWT", "BARE", "dXNlcjpwYXNz", "PROXYCRED"] {
            assert!(
                !r.stderr.contains(leaked),
                "{} leaked: {:?}",
                leaked,
                r.stderr
            );
        }
        assert!(
            r.stderr.contains(
                "> Authorization: token <redacted>\nsent authorization: Bearer <redacted>\nretrying with Bearer <redacted>, then gave up\n{\"Authorization\": \"Basic <redacted>\", \"x\": 1}\nproxy-authorization:<redacted>\nthe bearer of bad news\n"
            ),
            "{:?}",
            r.stderr
        );
    }

    #[test]
    fn secrets_inside_a_json_body_are_hidden_and_other_members_kept() {
        assert_eq!(
            red(
                "curl",
                &[
                    "--data",
                    r#"{"token":"SECRET-DATA","page":2}"#,
                    "--json",
                    r#"{ "user": "me", "password" : "SECRET JSON" }"#,
                    r#"-d{"api_key":"SECRET-JOINED"}"#,
                    r#"--data-raw={"client_secret":"SECRET-ESC\"APED","ok":true}"#,
                    "--json",
                    r#"{"credentials":{"user":"u","pass":"SECRET-NESTED"},"pin":1}"#,
                    "--json",
                    r#"{"access_token":123456789,"refresh_token":null}"#,
                    "--json",
                    r#"{"note":"token","a":1}"#,
                ]
            ),
            concat!(
                r#"curl --data {"token":"<redacted>","page":2}"#,
                r#" --json { "user": "me", "password" : "<redacted>" }"#,
                r#" -d{"api_key":"<redacted>"}"#,
                r#" --data-raw={"client_secret":"<redacted>","ok":true}"#,
                r#" --json {"credentials":"<redacted>","pin":1}"#,
                r#" --json {"access_token":<redacted>,"refresh_token":null}"#,
                r#" --json {"note":"token","a":1}"#,
            )
        );
        // And in what a failed command prints, even cut off mid-value.
        let mut r = FakeRunner::new(|_| {
            Out::fail(
                1,
                "response: {\"id\": 7, \"token\": \"SECRET-OUT\"}\n{\"password\": \"SECRET-CUT\n",
            )
        });
        let _ = capture(&mut r, &Cmd::new("tool"));
        assert!(!r.stderr.contains("SECRET"), "{:?}", r.stderr);
        assert!(
            r.stderr.contains(
                "response: {\"id\": 7, \"token\": \"<redacted>\"}\n{\"password\": \"<redacted>\n"
            ),
            "{:?}",
            r.stderr
        );
    }

    #[test]
    fn curl_tls_srp_passwords_are_hidden() {
        assert_eq!(
            red(
                "curl",
                &[
                    "--tlsuser",
                    "me",
                    "--tlspassword",
                    "SECRET-TLS",
                    "--tlspassword=SECRET-TLSEQ",
                    "--proxy-tlspassword",
                    "SECRET-PXTLS",
                    "--proxy-tlspassword=SECRET-PXTLSEQ",
                    "https://h/",
                ]
            ),
            "curl --tlsuser me --tlspassword <redacted> --tlspassword=<redacted> --proxy-tlspassword <redacted> --proxy-tlspassword=<redacted> https://h/"
        );
    }

    #[test]
    fn other_secret_headers_and_pairs_in_output_are_hidden_without_a_known_secret() {
        // Minted at run time, so in no environment variable.
        let mut r = FakeRunner::new(|_| {
            Out::fail(
                1,
                concat!(
                    "> X-Auth-Token: SECRET-XAUTH\n",
                    "> PRIVATE-TOKEN:SECRET-PRIV\n",
                    "x-api-key: \"SECRET QUOTED\"\n",
                    "sent authorization=token SECRET-AUTHEQ\n",
                    "retry password=SECRET-PW, api_key='SECRET-SQ'\n",
                    "--remote_header=x-buildbuddy-api-key=SECRET-BB\n",
                    "token: expired; page=2 sha=abc123 key-id: K1\n",
                ),
            )
        });
        let _ = capture(&mut r, &Cmd::new("tool"));
        assert!(!r.stderr.contains("SECRET"), "{:?}", r.stderr);
        assert!(
            r.stderr.contains(concat!(
                "> X-Auth-Token: <redacted>\n",
                "> PRIVATE-TOKEN:<redacted>\n",
                "x-api-key: \"<redacted>\"\n",
                "sent authorization=token <redacted>\n",
                "retry password=<redacted>, api_key='<redacted>'\n",
                "--remote_header=x-buildbuddy-api-key=<redacted>\n",
                // Prose and harmless pairs are kept.
                "token: expired; page=2 sha=abc123 key-id: K1\n",
            )),
            "{:?}",
            r.stderr
        );
    }

    #[test]
    fn a_windows_style_cert_path_is_read_as_curl_on_macos_reads_it() {
        // curl reads a drive letter's colon as part of the path only when
        // built for Windows. Elsewhere `C` is the file and the rest the
        // password, so the rest is hidden.
        let want = if cfg!(windows) {
            "curl --cert C:\\certs\\c.pem:<redacted> -EC:/c.pem:<redacted>"
        } else {
            "curl --cert C:<redacted> -EC:<redacted>"
        };
        assert_eq!(
            red(
                "curl",
                &[
                    "--cert",
                    "C:\\certs\\c.pem:SECRET-WIN",
                    "-EC:/c.pem:SECRET-FWD"
                ]
            ),
            want
        );
    }

    #[test]
    fn known_secret_values_are_hidden_whatever_carries_them() {
        // The value-based layer: a secret the environment holds is hidden
        // even where no rule about names or shapes would see it.
        let mut r = FakeRunner::new(|_| {
            Out::fail(1, "echo: {\"note\":\"KNOWN-VALUE-1\"}\nid: KNOWN-VALUE-2\n")
        });
        r.secrets = env_secrets(
            &[
                ("RELEASE_TOKEN", "KNOWN-VALUE-1"),
                ("SIGNING_CERT_PASSWORD", "KNOWN-VALUE-2"),
            ]
            .iter()
            .map(|(k, v)| (k.to_string(), v.to_string()))
            .collect(),
        );
        let _ = capture(
            &mut r,
            &Cmd::new("curl").args(["-d", "payload=KNOWN-VALUE-1", "https://h/"]),
        );
        assert!(!r.stderr.contains("KNOWN-VALUE"), "{:?}", r.stderr);
        assert!(
            r.stderr.contains(
                "`curl -d payload=<redacted> https://h/` failed (exit 1)\necho: {\"note\":\"<redacted>\"}\nid: <redacted>\n"
            ),
            "{:?}",
            r.stderr
        );
    }

    #[test]
    fn a_github_token_right_after_a_digit_is_hidden() {
        assert_eq!(red("tool", &["id=9ghp_AFTERDIGIT1"]), "tool id=9<redacted>");
        let mut r = FakeRunner::new(|_| Out::fail(1, "run 42ghs_AFTERDIGIT2 failed\n"));
        let _ = capture(&mut r, &Cmd::new("tool"));
        assert!(
            r.stderr.contains("run 42<redacted> failed\n"),
            "{:?}",
            r.stderr
        );
        // A letter before the prefix still makes it part of a longer word.
        assert_eq!(red("tool", &["xghp_notatoken"]), "tool xghp_notatoken");
    }

    #[test]
    fn each_line_of_a_multi_line_secret_is_hidden_in_stderr() {
        let key = "-----BEGIN PRIVATE KEY-----\nMIGTAgEAMBMGByqGSM49AgEGCCqGSM49\nAwEHBHkwdwIBAQQgLINE2-of-the-key\n-----END PRIVATE KEY-----\n"; // gitleaks:allow (made-up test value)
        let mut r = FakeRunner::new(move |_| {
            // The tool re-wraps the key with CRLF and indents it: the value
            // as a whole never appears, each of its lines does.
            Out::fail(
                1,
                "error: bad key\r\n    MIGTAgEAMBMGByqGSM49AgEGCCqGSM49\r\n    AwEHBHkwdwIBAQQgLINE2-of-the-key\r\n-----END PRIVATE KEY-----\n",
            )
        });
        r.secrets = env_secrets(
            &[("NOTARY_API_KEY_P8", key)]
                .iter()
                .map(|(k, v)| (k.to_string(), v.to_string()))
                .collect(),
        );
        let _ = capture(&mut r, &Cmd::new("xcrun").args(["notarytool", "submit"]));
        assert!(!r.stderr.contains("MIGTAgEA"), "{:?}", r.stderr);
        assert!(!r.stderr.contains("LINE2-of"), "{:?}", r.stderr);
        // The armour lines are not secret and the rest of stderr is kept.
        assert!(
            r.stderr.contains(
                "error: bad key\r\n    <redacted>\r\n    <redacted>\r\n-----END PRIVATE KEY-----"
            ),
            "{:?}",
            r.stderr
        );
    }

    #[test]
    fn urls_in_stderr_lose_their_credentials_even_when_not_a_known_secret() {
        // A token minted at run time is in no environment variable.
        let mut r = FakeRunner::new(|_| {
            Out::fail(
                128,
                "fatal: could not read from 'https://x-access-token:ghs_MINTED@github.com/o/r.git/': denied\nGET https://h/p?access_token=tok-LOG&page=2 401\nsee https://docs.github.com/en/rest for help\n",
            )
        });
        let _ = capture(&mut r, &Cmd::new("git").args(["fetch"]));
        assert!(!r.stderr.contains("ghs_MINTED"), "{:?}", r.stderr);
        assert!(!r.stderr.contains("tok-LOG"), "{:?}", r.stderr);
        assert!(
            r.stderr.contains(
                "fatal: could not read from 'https://x-access-token:<redacted>@github.com/o/r.git/': denied\nGET https://h/p?access_token=<redacted>&page=2 401\nsee https://docs.github.com/en/rest for help\n"
            ),
            "{:?}",
            r.stderr
        );
    }

    #[test]
    fn a_command_killed_by_a_signal_reports_128_plus_the_signal_as_a_shell_does() {
        let mut r = SystemRunner::new();
        let killed = Cmd::new("sh").args(["-c", "kill -TERM $$"]);
        assert_eq!(r.status(&killed), 128 + 15);
        assert_eq!(r.output(&killed).code, 128 + 15);
        assert_eq!(
            r.status_within(&killed, Duration::from_secs(10)),
            Some(128 + 15)
        );
    }

    #[test]
    fn a_timed_out_command_that_ignores_term_is_killed_and_reaped() {
        let root = make_temp_dir(&std::env::temp_dir(), "release_exec_hung").unwrap();
        let _guard = TempDir(root.clone());
        let pidfile = root.join("pid");
        // A child that shrugs off TERM, as a hung osascript can.
        let script = format!(
            "trap '' TERM; echo $$ > '{}'; while :; do sleep 1; done",
            pidfile.display()
        );
        let (tx, rx) = std::sync::mpsc::channel();
        thread::spawn(move || {
            let mut r = SystemRunner::new();
            let _ = tx.send(r.status_within(
                &Cmd::new("sh").args(["-c", &script]),
                Duration::from_secs(1),
            ));
        });
        let result = rx.recv_timeout(Duration::from_secs(15));
        let pid = fs::read_to_string(&pidfile).expect("the child wrote its pid");
        let pid = pid.trim().to_string();
        if result.is_err() {
            // Don't leave the loop running after a failed test.
            let _ = Command::new("sh")
                .args(["-c", &format!("kill -KILL {}", pid)])
                .status();
            panic!("status_within never returned: the child that ignores TERM was not killed");
        }
        assert_eq!(result.unwrap(), None, "reported as timed out");
        let pid = pid.as_str();
        // `kill -0` succeeds for a live process and for an unreaped zombie
        // alike, so it fails only once the child is dead and waited for.
        let alive = Command::new("sh")
            .args(["-c", &format!("kill -0 {} 2>/dev/null", pid)])
            .status()
            .unwrap()
            .success();
        if alive {
            let _ = Command::new("sh")
                .args(["-c", &format!("kill -KILL {}", pid)])
                .status();
            panic!("pid {} is still there after the timeout", pid);
        }
    }

    #[test]
    fn the_fake_runner_records_each_time_limit() {
        let mut r = FakeRunner::succeeding();
        r.status_within(&Cmd::new("osascript"), Duration::from_secs(25));
        assert_eq!(
            r.limits,
            vec![("osascript".to_string(), Duration::from_secs(25))]
        );
    }

    /// Run in a child process by the test below: writes a secret, asks for
    /// it to be removed on a signal, says it is ready, and waits.
    #[test]
    #[ignore]
    fn signal_cleanup_child() {
        let Some(dir) = std::env::var_os("SIGNAL_CLEANUP_DIR") else {
            return;
        };
        let dir = PathBuf::from(dir);
        let work = dir.join("work");
        fs::create_dir(&work).unwrap();
        let _d = remove_on_signal(&work);
        let key = work.join("AuthKey.p8");
        write_private(&key, b"secret").unwrap();
        let _k = remove_on_signal(&key);
        fs::write(dir.join("ready"), b"").unwrap();
        let hold_ms = std::env::var("SIGNAL_CLEANUP_HOLD_MS")
            .ok()
            .and_then(|v| v.parse().ok())
            .unwrap_or(30_000);
        thread::sleep(Duration::from_millis(hold_ms));
    }

    /// Run in a child process by the test below, with secrets in its
    /// environment: the real runner must know them.
    #[test]
    #[ignore]
    fn from_env_child() {
        if std::env::var_os("FROM_ENV_CHILD").is_none() {
            return;
        }
        let r = SystemRunner::from_env();
        assert!(
            r.secrets.contains(&"bb-from-env-1234".to_string()),
            "{:?}",
            r.secrets
        );
        assert!(
            r.secrets.contains(&"p12-pass-from-env".to_string()),
            "{:?}",
            r.secrets
        );
        assert!(!r.secrets.contains(&"beta".to_string()), "{:?}", r.secrets);
        assert_eq!(r.secrets(), r.secrets);
    }

    #[test]
    fn the_real_runner_takes_its_secrets_from_the_environment() {
        let status = Command::new(std::env::current_exe().unwrap())
            .args(["--exact", "tests::from_env_child", "--ignored"])
            .env("FROM_ENV_CHILD", "1")
            .env("BUILDBUDDY_API_KEY", "bb-from-env-1234") // gitleaks:allow (made-up test value)
            .env("SIGNING_CERT_PASSWORD", "p12-pass-from-env") // gitleaks:allow (made-up test value)
            .env("GRADE", "beta")
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .unwrap();
        assert!(
            status.success(),
            "SystemRunner::from_env() missed a secret: {:?}",
            status
        );
    }

    #[test]
    fn an_inherited_sighup_ignore_is_kept_as_nohup_expects() {
        let dir = make_temp_dir(&std::env::temp_dir(), "release_exec_nohup").unwrap();
        let _guard = TempDir(dir.clone());
        // As `nohup` starts it: SIGHUP ignored, which exec keeps.
        let mut child = Command::new("sh")
            .args([
                "-c",
                "trap '' HUP; exec \"$0\" \"$@\"",
                &std::env::current_exe().unwrap().to_string_lossy(),
                "--exact",
                "tests::signal_cleanup_child",
                "--ignored",
            ])
            .env("SIGNAL_CLEANUP_DIR", &dir)
            .env("SIGNAL_CLEANUP_HOLD_MS", "1500")
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .unwrap();
        let started = Instant::now();
        while !dir.join("ready").exists() {
            if started.elapsed() > Duration::from_secs(20) {
                let _ = child.kill();
                panic!("the child never got ready");
            }
            thread::sleep(Duration::from_millis(20));
        }
        Command::new("sh")
            .args(["-c", &format!("kill -HUP {}", child.id())])
            .status()
            .unwrap();
        let status = child.wait().unwrap();
        assert!(
            status.success(),
            "a HUP the parent ignored ended it: {:?}",
            status
        );
        assert!(dir.join("work/AuthKey.p8").exists(), "and removed nothing");
    }

    #[test]
    fn a_private_work_dir_stays_covered_until_it_is_gone() {
        let dir = make_temp_dir(&std::env::temp_dir(), "release_exec_workdir").unwrap();
        let _guard = TempDir(dir.clone());
        let w = private_work_dir(&dir, "w", &["AuthKey.p8"]).unwrap();
        let path = w.path().to_path_buf();
        let key = path.join("AuthKey.p8");
        write_private(&key, b"k").unwrap();
        assert!(signal_cleanup_covers(&path) && signal_cleanup_covers(&key));
        let seen = std::rc::Rc::new(RefCell::new(None));
        let s2 = seen.clone();
        let (p2, k2) = (path.clone(), key.clone());
        AFTER_WORK_DIR_REMOVED.with(|h| {
            *h.borrow_mut() = Some(Box::new(move || {
                *s2.borrow_mut() = Some((
                    p2.exists(),
                    signal_cleanup_covers(&p2),
                    signal_cleanup_covers(&k2),
                ));
            }))
        });
        drop(w);
        AFTER_WORK_DIR_REMOVED.with(|h| *h.borrow_mut() = None);
        assert_eq!(
            *seen.borrow(),
            Some((false, true, true)),
            "(folder still there, folder covered, key covered) right after the folder was removed"
        );
        assert!(!signal_cleanup_covers(&path) && !signal_cleanup_covers(&key));
    }

    #[test]
    fn a_signal_removes_the_secret_files_and_ends_with_that_signal() {
        use std::os::unix::process::ExitStatusExt;
        for (sig, name) in [(15, "TERM"), (2, "INT")] {
            let dir = make_temp_dir(&std::env::temp_dir(), "release_exec_signal").unwrap();
            let _guard = TempDir(dir.clone());
            let mut child = Command::new(std::env::current_exe().unwrap())
                .args([
                    "--exact",
                    "tests::signal_cleanup_child",
                    "--ignored",
                    "--nocapture",
                ])
                .env("SIGNAL_CLEANUP_DIR", &dir)
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .spawn()
                .unwrap();
            let started = Instant::now();
            while !dir.join("ready").exists() {
                if started.elapsed() > Duration::from_secs(20) {
                    let _ = child.kill();
                    panic!("the child never got ready");
                }
                thread::sleep(Duration::from_millis(20));
            }
            assert!(dir.join("work/AuthKey.p8").exists());
            Command::new("sh")
                .args(["-c", &format!("kill -{} {}", name, child.id())])
                .status()
                .unwrap();
            let status = child.wait().unwrap();
            assert_eq!(
                status.signal(),
                Some(sig),
                "SIG{} ends it: {:?}",
                name,
                status
            );
            assert!(
                !dir.join("work/AuthKey.p8").exists(),
                "SIG{} left the key behind",
                name
            );
            assert!(
                !dir.join("work").exists(),
                "SIG{} left the key's folder behind",
                name
            );
        }
    }

    #[test]
    fn a_dropped_cleanup_forgets_its_path() {
        let dir = make_temp_dir(&std::env::temp_dir(), "release_exec_forget").unwrap();
        let _guard = TempDir(dir.clone());
        // Every slot is free again once its guard is gone.
        for _ in 0..64 {
            let g = remove_on_signal(&dir.join("x"));
            #[cfg(unix)]
            assert!(g._guard.is_some());
            drop(g);
        }
    }

    #[test]
    fn private_files_and_dirs_are_owner_only() {
        let root = make_temp_dir(&std::env::temp_dir(), "release_exec_test").unwrap();
        let _guard = TempDir(root.clone());
        let f = root.join("secret");
        write_private(&f, b"x").unwrap();
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            assert_eq!(
                fs::metadata(&f).unwrap().permissions().mode() & 0o777,
                0o600
            );
            assert_eq!(
                fs::metadata(&root).unwrap().permissions().mode() & 0o777,
                0o700
            );
        }
    }

    #[test]
    fn system_runner_reports_exit_codes_and_timeouts() {
        let mut r = SystemRunner::new();
        assert_eq!(r.status(&Cmd::new("sh").args(["-c", "exit 4"])), 4);
        let out = r.output(&Cmd::new("sh").args(["-c", "cat; echo err >&2"]).stdin("in"));
        assert_eq!(
            (out.code, out.stdout.as_str(), out.stderr.as_str()),
            (0, "in", "err\n")
        );
        assert_eq!(
            r.status_within(&Cmd::new("sleep").arg("5"), Duration::from_millis(300)),
            None
        );
        assert_eq!(r.status(&Cmd::new("/nonexistent/program")), 127);
    }
}
