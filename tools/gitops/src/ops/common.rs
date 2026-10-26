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

//! What every gitops tool script does the same way: `set -euo pipefail`
//! exits, `${1:?msg}`, the KUBECONFIG / KUBE_CONTEXT defaults, `command -v`
//! checks, `cd "$BUILD_WORKSPACE_DIRECTORY"`, `read -rp`, and the
//! `printf | kubectl create secret | kubeseal >> OUT` pipeline.

use std::fs;
use std::io::{self, Write};
use std::os::fd::AsFd;
use std::os::unix::fs::OpenOptionsExt;
use std::process::{Child, Command, Stdio};

use shell_compat as sc;

/// `Err(code)`: the script exits with `code` here (its message is printed).
pub type Res<T> = Result<T, i32>;

/// The license header the seal tools put on every file they write (kubeseal
/// output has none, and license-check rejects a committed file without it).
pub const LICENSE_HEADER: &str = "\
# Copyright (c) 2026 VitruvianSoftware
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the \"Software\"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
";

/// Where every seal tool writes: the git-source Application for
/// cross-namespace SealedSecrets.
pub const SEALED_DIR: &str = "gitops/argocd/platform/sealed-secrets-manifests";

/// The `${BUILD_WORKSPACE_DIRECTORY:?...}` message as bash prints it: the
/// word after `:?` goes through quote removal, so the single quotes the
/// scripts wrote around `bazel run` never show.
pub const BAZEL_RUN_ONLY: &str = "this target must be run via bazel run, not bazel build";

/// The script's own name, as bash prints it in its diagnostics.
pub fn prog() -> Vec<u8> {
    use std::os::unix::ffi::OsStringExt;
    std::env::args_os()
        .next()
        .map(|a| a.into_vec())
        .unwrap_or_default()
}

/// A diagnostic from bash itself: `<script>: line <n>: <msg>`.
pub fn diag(line: u32, msg: &[u8]) {
    sc::err(&sc::cat(&[
        &prog(),
        format!(": line {}: ", line).as_bytes(),
        msg,
        b"\n",
    ]));
}

/// `echo "..."` to stdout.
pub fn say(msg: &[u8]) {
    sc::out(&sc::cat(&[msg, b"\n"]));
}

/// `echo "..." >&2`.
pub fn warn(msg: &[u8]) {
    sc::err(&sc::cat(&[msg, b"\n"]));
}

/// `echo "..." >&2; exit code`.
pub fn die<T>(code: i32, msg: &[u8]) -> Res<T> {
    warn(msg);
    Err(code)
}

/// `$N` (1-based), or empty when there are fewer arguments.
pub fn arg(args: &[Vec<u8>], n: usize) -> Vec<u8> {
    args.get(n - 1).cloned().unwrap_or_default()
}

/// `${N:?msg}`: the argument, or bash's `N: msg` and exit 1 when it is unset
/// or empty.
pub fn param(args: &[Vec<u8>], n: usize, line: u32, msg: &str) -> Res<Vec<u8>> {
    match args.get(n - 1) {
        Some(v) if !v.is_empty() => Ok(v.clone()),
        _ => {
            diag(line, format!("{}: {}", n, msg).as_bytes());
            Err(1)
        }
    }
}

/// `: "${KUBECONFIG:=$HOME/.kube/cluster.yaml}"; export KUBECONFIG`.
pub fn default_kubeconfig(line: u32) -> Res<()> {
    if sc::env_set_nonempty("KUBECONFIG") {
        return Ok(());
    }
    let home = match sc::env("HOME") {
        Some(h) => h,
        None => {
            diag(line, b"HOME: unbound variable");
            return Err(1);
        }
    };
    std::env::set_var(
        "KUBECONFIG",
        sc::os(&sc::cat(&[&home, b"/.kube/cluster.yaml"])),
    );
    Ok(())
}

/// `KCTX="${KUBE_CONTEXT:-default}"`.
pub fn kctx() -> Vec<u8> {
    sc::env_or("KUBE_CONTEXT", b"default")
}

/// `command -v NAME >/dev/null 2>&1`.
pub fn have(name: &str) -> bool {
    sc::which(name.as_bytes()).is_some()
}

/// `for c in ...; do command -v "$c" ... || { echo "ERROR: $c not found on
/// PATH." >&2; exit 1; }; done`, `quote` putting the name in single quotes
/// the way some of the scripts do.
pub fn need_tools(tools: &[&str], quote: bool) -> Res<()> {
    for t in tools {
        if !have(t) {
            let name = if quote {
                format!("'{}'", t)
            } else {
                t.to_string()
            };
            return die(1, format!("ERROR: {} not found on PATH.", name).as_bytes());
        }
    }
    Ok(())
}

/// `cd "${BUILD_WORKSPACE_DIRECTORY:?this target must be run via 'bazel
/// run', not 'bazel build'}"` (cd keeps $PWD in step for what runs next).
pub fn cd_workspace(line: u32) -> Res<()> {
    let dir = match sc::env("BUILD_WORKSPACE_DIRECTORY") {
        Some(d) if !d.is_empty() => d,
        _ => {
            diag(
                line,
                format!("BUILD_WORKSPACE_DIRECTORY: {}", BAZEL_RUN_ONLY).as_bytes(),
            );
            return Err(1);
        }
    };
    if let Err(e) = std::env::set_current_dir(sc::path(&dir)) {
        diag(
            line,
            &sc::cat(&[b"cd: ", &dir, b": ", sc::strerror(&e).as_bytes()]),
        );
        return Err(1);
    }
    if let Some(old) = sc::env("PWD") {
        std::env::set_var("OLDPWD", sc::os(&old));
    }
    std::env::set_var("PWD", sc::os(&dir));
    Ok(())
}

/// `[ -t 0 ]`-gated prompt then `read -r VAR`: bash shows a `read -p` prompt
/// (on stderr) only when stdin is a terminal; the value has surrounding
/// blanks trimmed; a read that hits end of input fails, which `set -e` turns
/// into exit 1.
pub fn read_prompt(prompt: &str) -> Res<Vec<u8>> {
    if sc::stdin_is_tty() {
        sc::err(prompt.as_bytes());
    }
    let (line, newline) = sc::read_stdin_line();
    if !newline {
        return Err(1);
    }
    Ok(sc::read_trim(&line))
}

/// A command with byte-string arguments.
pub fn cmd(prog: &str, args: &[&[u8]]) -> Command {
    let mut c = Command::new(prog);
    for a in args {
        c.arg(sc::os(a));
    }
    c
}

/// `kubectl --context "$KCTX" ARGS...`.
pub fn kubectl(kctx: &[u8], args: &[&[u8]]) -> Command {
    let mut c = cmd("kubectl", &[b"--context", kctx]);
    for a in args {
        c.arg(sc::os(a));
    }
    c
}

/// Every kubeseal call goes through here, so every one passes `--context`:
/// kubeseal fetches its sealing key from a cluster, and without it would use
/// the kubeconfig's current context -- another cluster's key, which the
/// target controller could never decrypt (see kubeseal_context_test.sh).
pub fn kubeseal(kctx: &[u8], args: &[&[u8]]) -> Command {
    let mut c = cmd("kubeseal", &[b"--context", kctx]);
    for a in args {
        c.arg(sc::os(a));
    }
    c
}

/// `$SEALED_SECRETS_NAMESPACE` / `$SEALED_SECRETS_CONTROLLER` with their
/// defaults.
pub fn controller() -> (Vec<u8>, Vec<u8>) {
    (
        sc::env_or("SEALED_SECRETS_NAMESPACE", b"sealed-secrets"),
        sc::env_or("SEALED_SECRETS_CONTROLLER", b"sealed-secrets-controller"),
    )
}

/// `kubeseal --context K --format yaml --controller-namespace NS
/// --controller-name NAME`.
pub fn kubeseal_yaml(kctx: &[u8]) -> Command {
    let (ns, name) = controller();
    kubeseal(
        kctx,
        &[
            b"--format",
            b"yaml",
            b"--controller-namespace",
            &ns,
            b"--controller-name",
            &name,
        ],
    )
}

/// A dup of our stderr, for a child whose stdout the script sent there
/// (`>&2`).
pub fn to_stderr() -> Stdio {
    match io::stderr().as_fd().try_clone_to_owned() {
        Ok(fd) => Stdio::from(fd),
        Err(_) => Stdio::inherit(),
    }
}

/// `cat > FILE <<'HEADER'`: create or truncate (mode 0666 less the umask)
/// and write. A redirection bash cannot open is reported its way, and `set -e`
/// exits 1.
pub fn write_new(line: u32, file: &[u8], data: &[u8]) -> Res<()> {
    let r = fs::OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .mode(0o666)
        .open(sc::path(file))
        .and_then(|mut f| f.write_all(data));
    r.map_err(|e| {
        sc::redirect_error(line, file, &e);
        1
    })
}

/// `>> FILE` for a pipeline's last stage.
pub fn append_to(line: u32, file: &[u8]) -> Res<Stdio> {
    fs::OpenOptions::new()
        .append(true)
        .create(true)
        .mode(0o666)
        .open(sc::path(file))
        .map(Stdio::from)
        .map_err(|e| {
            sc::redirect_error(line, file, &e);
            1
        })
}

/// A pipeline under `set -o pipefail`: `printf '%s' INPUT | c1 | c2 ... >
/// out`. The status is the rightmost non-zero one (a printf that could not
/// write because the first command exited unread counts as 141, SIGPIPE).
/// stderr of every stage is ours. With no `input` the first stage reads our
/// stdin.
pub fn pipeline(
    line: u32,
    mut cmds: Vec<Command>,
    input: Option<&[u8]>,
    out: Option<Stdio>,
) -> i32 {
    let n = cmds.len();
    let mut statuses: Vec<i32> = vec![0; n];
    let mut children: Vec<Option<Child>> = Vec::with_capacity(n);
    let mut prev: Option<std::process::ChildStdout> = None;
    let mut out = out;
    for (i, c) in cmds.iter_mut().enumerate() {
        if i == 0 {
            if input.is_some() {
                c.stdin(Stdio::piped());
            }
        } else {
            c.stdin(match prev.take() {
                Some(s) => Stdio::from(s),
                None => Stdio::null(),
            });
        }
        if i == n - 1 {
            if let Some(o) = out.take() {
                c.stdout(o);
            }
        } else {
            c.stdout(Stdio::piped());
        }
        match c.spawn() {
            Ok(mut ch) => {
                if i < n - 1 {
                    prev = ch.stdout.take();
                }
                children.push(Some(ch));
            }
            Err(e) => {
                sc::err(&sc::spawn_diag(line, c, &e));
                statuses[i] = sc::spawn_failure_status(&e);
                children.push(None);
            }
        }
    }
    let mut printf_status = 0;
    if let Some(data) = input {
        match children[0].as_mut().and_then(|c| c.stdin.take()) {
            Some(mut sin) => {
                if sin.write_all(data).is_err() {
                    printf_status = 141;
                }
            }
            None => printf_status = 141,
        }
    }
    for (i, ch) in children.iter_mut().enumerate() {
        if let Some(c) = ch {
            statuses[i] = match c.wait() {
                Ok(st) => sc::status_code(st),
                Err(_) => 1,
            };
        }
    }
    let mut status = printf_status;
    for s in statuses {
        if s != 0 {
            status = s;
        }
    }
    status
}

/// `CMD` as a simple command: its status (stdio as given; a command that
/// cannot start is reported on stderr unless `quiet`).
pub fn run(line: u32, c: &mut Command, quiet: bool) -> i32 {
    sc::status(line, c, quiet)
}

/// `CMD >/dev/null 2>&1`.
pub fn run_quiet(line: u32, mut c: Command) -> i32 {
    c.stdout(Stdio::null()).stderr(Stdio::null());
    sc::status(line, &mut c, true)
}

/// `$(CMD)`: stdout captured (trailing newlines dropped), stderr ours.
pub fn capture(line: u32, mut c: Command) -> (i32, Vec<u8>) {
    let r = sc::capture_stdout(line, &mut c);
    (r.status, sc::subst(r.stdout))
}

/// `$(CMD 2>/dev/null)`.
pub fn capture_quiet(line: u32, mut c: Command) -> (i32, Vec<u8>) {
    c.stderr(Stdio::null());
    c.stdout(Stdio::piped());
    let r = match c.output() {
        Ok(o) => (sc::status_code(o.status), o.stdout),
        Err(e) => {
            let _ = line;
            (sc::spawn_failure_status(&e), Vec::new())
        }
    };
    (r.0, sc::subst(r.1))
}

/// Raw stdout of a command (no `$(...)` trimming), stderr as configured.
pub fn output(line: u32, mut c: Command, quiet_err: bool) -> (i32, Vec<u8>) {
    c.stdout(Stdio::piped());
    c.stderr(if quiet_err {
        Stdio::null()
    } else {
        Stdio::inherit()
    });
    match c.spawn() {
        Ok(ch) => match ch.wait_with_output() {
            Ok(o) => (sc::status_code(o.status), o.stdout),
            Err(_) => (1, Vec::new()),
        },
        Err(e) => {
            if !quiet_err {
                sc::err(&sc::spawn_diag(line, &c, &e));
            }
            (sc::spawn_failure_status(&e), Vec::new())
        }
    }
}

/// `printf '%s' INPUT | CMD`, stdout as given; the pipefail status.
pub fn feed(line: u32, c: Command, input: &[u8], out: Option<Stdio>) -> i32 {
    pipeline(line, vec![c], Some(input), out)
}

/// `NAME=value` for a variable that may already be in the environment: bash
/// changes the exported copy too (the ntfy and headscale scripts assign
/// `USER`), so every later child sees the new value.
pub fn assign_exported(name: &str, value: &[u8]) {
    if std::env::var_os(name).is_some() {
        std::env::set_var(name, sc::os(value));
    }
}

/// `printf '%s' "$VALUE" | kubectl --context K create secret generic SECRET
/// -n NS --dry-run=client --from-file=KEY=/dev/stdin -o yaml | kubeseal
/// --context K --format yaml --controller-namespace ... --controller-name
/// ... >> OUT`, the pipefail status (or a redirection error).
pub fn seal_value(
    line: u32,
    kctx: &[u8],
    ns: &str,
    secret: &str,
    key: &str,
    value: &[u8],
    out: &[u8],
) -> i32 {
    let o = match append_to(line, out) {
        Ok(o) => o,
        Err(c) => return c,
    };
    let create = kubectl(
        kctx,
        &[
            b"create",
            b"secret",
            b"generic",
            secret.as_bytes(),
            b"-n",
            ns.as_bytes(),
            b"--dry-run=client",
            format!("--from-file={}=/dev/stdin", key).as_bytes(),
            b"-o",
            b"yaml",
        ],
    );
    pipeline(
        line,
        vec![create, kubeseal_yaml(kctx)],
        Some(value),
        Some(o),
    )
}

/// `openssl rand -base64 N | tr -dc 'A-Za-z0-9' | head -c LEN` as an
/// assignment: the status is openssl's (tr and head do not fail here), the
/// value the first LEN alphanumerics.
pub fn openssl_alnum(line: u32, nbytes: &str, len: usize) -> (i32, Vec<u8>) {
    let (st, raw) = output(
        line,
        cmd("openssl", &[b"rand", b"-base64", nbytes.as_bytes()]),
        false,
    );
    let v: Vec<u8> = raw
        .into_iter()
        .filter(|c| c.is_ascii_alphanumeric())
        .take(len)
        .collect();
    (st, sc::subst(v))
}

/// `openssl rand -base64 N | tr -d '\n=+/' | cut -c1-32`: what is left of
/// the base64 after dropping newlines and `=+/`, cut to 32 characters (cut
/// prints nothing at all for empty input).
pub fn openssl_pass(line: u32, nbytes: &str) -> (i32, Vec<u8>) {
    let (st, raw) = output(
        line,
        cmd("openssl", &[b"rand", b"-base64", nbytes.as_bytes()]),
        false,
    );
    let v: Vec<u8> = raw
        .into_iter()
        .filter(|c| !matches!(c, b'\n' | b'=' | b'+' | b'/'))
        .take(32)
        .collect();
    (st, v)
}

/// The `$?` of `[ "$a" = "$b" ]`-style tests is never needed; but `[ "$n"
/// -ge 1 ]` on a value that is not an integer is a bash error (status 2 and
/// a message) -- which the scripts' `|| { ...; exit 1; }` then turns into
/// their own error. None when bash would complain.
pub fn test_int(v: &[u8]) -> Option<i64> {
    let s = std::str::from_utf8(v).ok()?;
    let t = s.trim_matches(|c| c == ' ' || c == '\t' || c == '\n');
    if t.is_empty() {
        return None;
    }
    let (neg, digits) = match t.as_bytes()[0] {
        b'-' => (true, &t[1..]),
        b'+' => (false, &t[1..]),
        _ => (false, t),
    };
    if digits.is_empty() || !digits.bytes().all(|c| c.is_ascii_digit()) {
        return None;
    }
    let n: i64 = digits.parse().ok()?;
    Some(if neg { -n } else { n })
}

/// `[ "$v" -ge 1 ]`: true, false, or bash's `integer expression expected`
/// (printed; the test then fails).
pub fn test_ge_1(line: u32, v: &[u8]) -> bool {
    match test_int(v) {
        Some(n) => n >= 1,
        None => {
            diag(
                line,
                &sc::cat(&[b"[: ", v, b": integer expression expected"]),
            );
            false
        }
    }
}

/// grep's basic-regex match where the only metacharacter in `pat` is `.`
/// (any character): does some line of `text` contain it? What `grep -q
/// "server.secretkey"` asks.
pub fn grep_dot(text: &[u8], pat: &[u8]) -> bool {
    text.split(|&c| c == b'\n').any(|line| {
        line.len() >= pat.len()
            && (0..=line.len() - pat.len()).any(|i| {
                pat.iter()
                    .zip(&line[i..])
                    .all(|(p, c)| *p == b'.' || p == c)
            })
    })
}

/// `mv SRC DST`: a rename, or a copy and delete across filesystems (keeping
/// the mode, as mv does).
pub fn mv(line: u32, src: &[u8], dst: &[u8]) -> Res<()> {
    let (s, d) = (sc::path(src), sc::path(dst));
    let r = match fs::rename(&s, &d) {
        Ok(()) => Ok(()),
        Err(e) if e.raw_os_error() == Some(18) => fs::copy(&s, &d)
            .and_then(|_| fs::metadata(&s))
            .and_then(|m| fs::set_permissions(&d, m.permissions()))
            .and_then(|_| fs::remove_file(&s)),
        Err(e) => Err(e),
    };
    r.map_err(|e| {
        let _ = line;
        sc::err(&sc::cat(&[
            b"mv: cannot move '",
            src,
            b"' to '",
            dst,
            b"': ",
            sc::strerror(&e).as_bytes(),
            b"\n",
        ]));
        1
    })
}

/// A fresh mode-0700 directory `$TMPDIR/PREFIX.XXXXXX` (`mktemp -d -t
/// PREFIX.XXXXXX`).
pub fn mktemp_dir_named(prefix: &str) -> io::Result<Vec<u8>> {
    use std::os::unix::fs::DirBuilderExt;
    for _ in 0..100 {
        let p = sc::cat(&[
            &sc::tmpdir(),
            b"/",
            prefix.as_bytes(),
            b".",
            &random_suffix(6),
        ]);
        match fs::DirBuilder::new().mode(0o700).create(sc::path(&p)) {
            Ok(()) => return Ok(p),
            Err(e) if e.kind() == io::ErrorKind::AlreadyExists => continue,
            Err(e) => return Err(e),
        }
    }
    Err(io::Error::new(
        io::ErrorKind::AlreadyExists,
        "mktemp: too many tries",
    ))
}

fn random_suffix(n: usize) -> Vec<u8> {
    const ALNUM: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
    let mut buf = vec![0u8; n];
    if fs::File::open("/dev/urandom")
        .and_then(|mut f| io::Read::read_exact(&mut f, &mut buf))
        .is_err()
    {
        let seed = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_or(0, |d| d.as_nanos() as u64)
            ^ std::process::id() as u64;
        for (i, b) in buf.iter_mut().enumerate() {
            *b = (seed >> ((i % 8) * 8)) as u8 ^ (i as u8).wrapping_mul(31);
        }
    }
    buf.iter()
        .map(|b| ALNUM[*b as usize % ALNUM.len()])
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn grep_dot_treats_dot_as_any_char() {
        assert!(grep_dot(
            b"a: 1\n  server.secretkey: x\n",
            b"server.secretkey"
        ));
        assert!(grep_dot(b"serverXsecretkey", b"server.secretkey"));
        assert!(!grep_dot(b"server\nsecretkey", b"server.secretkey"));
        assert!(!grep_dot(b"", b"kind: Secret"));
    }

    #[test]
    fn test_int_follows_bash() {
        assert_eq!(test_int(b"3"), Some(3));
        assert_eq!(test_int(b" 3 "), Some(3));
        assert_eq!(test_int(b"-2"), Some(-2));
        assert_eq!(test_int(b""), None);
        assert_eq!(test_int(b"3\n0"), None);
        assert_eq!(test_int(b"x"), None);
    }

    #[test]
    fn every_kubeseal_call_passes_context() {
        let c = kubeseal_yaml(b"lab-b");
        let args: Vec<_> = c
            .get_args()
            .map(|a| a.to_string_lossy().into_owned())
            .collect();
        assert_eq!(&args[..2], &["--context", "lab-b"]);
        let c = kubeseal(b"x", &[b"--validate"]);
        let args: Vec<_> = c
            .get_args()
            .map(|a| a.to_string_lossy().into_owned())
            .collect();
        assert_eq!(&args[..2], &["--context", "x"]);
    }

    #[test]
    fn license_header_is_nineteen_lines() {
        assert_eq!(LICENSE_HEADER.lines().count(), 19);
        assert!(LICENSE_HEADER.starts_with("# Copyright (c) 2026 VitruvianSoftware\n"));
        assert!(LICENSE_HEADER.ends_with("# SOFTWARE.\n"));
    }
}
