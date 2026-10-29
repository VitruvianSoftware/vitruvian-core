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

//! agent-app: the Rust replacement for the deleted agent-app.sh script. It
//! kept the script's command line, its calls to curl, openssl, gh, git and the
//! landed gate (argument for argument), its output, exit codes and files.
//!
//! What the script does with jq on its own machine (convert, installations,
//! repos, token) is done here with serde_json (see jq.rs); the filters it
//! hands to `gh --jq` are handed to gh unchanged.

pub mod jq;

#[cfg(test)]
mod tests;

use shell_compat as sh;
use std::ffi::c_int;
use std::io::Write;
use std::os::unix::ffi::OsStrExt;
use std::os::unix::fs::OpenOptionsExt;
use std::os::unix::process::CommandExt;
use std::process::{Command, Stdio};

pub const HOLD_LABEL: &str = "do-not-automerge";
pub const RELEASE_HOLD_LABEL: &str = "dev-deploy-red";
pub const BETA_GATE_LABEL: &str = "beta-not-built";
pub const FAST_LANE_LABEL: &str = "agent-fast-lane";

/// The lines of the script a diagnostic names (bash says `<script>: line N:`).
mod line {
    pub const SIGN: u32 = 106;
    pub const API_CALL: u32 = 114;
    pub const CONVERT_CURL: u32 = 128;
    pub const CONVERT_PEM: u32 = 135;
    pub const KEY_DIR_GIT: u32 = 192;
    pub const CD: u32 = 282;
    pub const GH_AS: u32 = 289;
    pub const EXEC_GH: u32 = 292;
    pub const SLEEP: u32 = 747;
    pub const LANDED: u32 = 1033;
    pub const GIT_SHA: u32 = 1039;
}

const HOLD_QUERY: &str = "
    query($id: ID!) { node(id: $id) { ... on PullRequest {
      state
      autoMergeRequest { enabledAt }
      mergeQueueEntry { id }
      labels(first: 100) { nodes { name } }
    } } }";

fn hold_jq() -> String {
    format!(
        ".data.node |
      [.labels.nodes[].name] as $labels |
      \"\\(.autoMergeRequest != null) \\(.mergeQueueEntry != null) \\($labels | index(\"{}\") != null) \\(.state) \\(first($labels[] | select(. == \"{}\" or . == \"{}\")) // \"-\")\"",
        HOLD_LABEL, RELEASE_HOLD_LABEL, BETA_GATE_LABEL
    )
}

const ENQUEUE_QUERY: &str = "
      query($id: ID!) { node(id: $id) { ... on PullRequest {
        state
        autoMergeRequest { mergeMethod enabledBy { login } }
        mergeQueueEntry { position state }
      } } }";

const ENQUEUE_JQ: &str = ".data.node |
        if .mergeQueueEntry then \"queue \\(.mergeQueueEntry.position) \\(.mergeQueueEntry.state)\"
        elif .autoMergeRequest then \"auto \\(.autoMergeRequest.enabledBy.login // \"unknown\") \\(.autoMergeRequest.mergeMethod)\"
        else \"none \\(.state)\" end";

const DEQUEUE_MUTATION: &str = "
      mutation($id: ID!) { dequeuePullRequest(input: {id: $id}) { mergeQueueEntry { id } } }";

const USAGE: &str = r"agent-app — the API half of standing up a per-agent GitHub App identity.

App CREATION is not scriptable: GitHub's Apps REST API has fourteen endpoints
and none of them creates an App. The only creation path is the App-manifest
flow, whose final step IS an API call -- but the `code` it consumes exists only
after a signed-in human approves the handshake in a browser. So the manual part
is two clicks per agent; everything either side of them is here.

  bazel run //tools/agent-app -- convert <manifest-code> <out.pem>
  bazel run //tools/agent-app -- installations <app-id> <key.pem>
  bazel run //tools/agent-app -- repos <app-id> <key.pem> <installation-id>
  bazel run //tools/agent-app -- token <app-id> <key.pem> <installation-id>
  bazel run //tools/agent-app -- env <agent>        # the one agents actually use
  bazel run //tools/agent-app -- login <agent>      # token only
  bazel run //tools/agent-app -- pr-create [--agent <agent>] [gh pr create args]
                                  # open a PR as the agent, in the fast lane
  bazel run //tools/agent-app -- pr-edit [--agent <agent>] <pr> [gh pr edit args]
  bazel run //tools/agent-app -- pr-comment [--agent <agent>] <pr> --body-file <f> | --body <s>
  bazel run //tools/agent-app -- pr-review [--agent <agent>] <pr> (--approve | --comment | --request-changes) [--body-file <f> | --body <s>]
  bazel run //tools/agent-app -- pr-ready [--agent <agent>] <pr> [gh pr ready args]
  bazel run //tools/agent-app -- pr-close [--agent <agent>] <pr> [--comment <s>] [--delete-branch]
  bazel run //tools/agent-app -- pr-enqueue [--agent <agent>] <pr> [gh pr merge args]
                                  # arm auto-merge into the merge queue; never --admin
  bazel run //tools/agent-app -- pr-hold [--agent <agent>] <pr> [--reason <s>]
                                  # do-not-automerge on, auto-merge off, out of the queue
  bazel run //tools/agent-app -- pr-unhold [--agent <agent>] <pr>
                                  # label off only; run pr-enqueue to re-arm
  bazel run //tools/agent-app -- run-rerun [--agent <agent>] <run-id> [--failed] [--job <id>]
  bazel run //tools/agent-app -- run-cancel [--agent <agent>] <run-id>
  bazel run //tools/agent-app -- workflow-run [--agent <agent>] <workflow.yaml> [-f k=v ...] [--ref main]
                                  # only workflows in workflow-allowlist.txt, only from main
  bazel run //tools/agent-app -- issue-create [--agent <agent>] --title <s> --body-file <f> [gh issue create args]
  bazel run //tools/agent-app -- issue-comment [--agent <agent>] <issue> --body-file <f> | --body <s>
  bazel run //tools/agent-app -- issue-close [--agent <agent>] <issue> [--comment <s>] [--reason <r>]
  bazel run //tools/agent-app -- branch-delete [--agent <agent>] <branch>...
                                  # delete branches on GitHub, only ones already on main

Every pr-* and run command acts AS the agent app (default wren, or
$AGENT_APP_AGENT): the token reaches gh through its environment only, and if
it cannot be minted nothing runs. pr-enqueue too: the agent apps can arm
auto-merge themselves (scout did on #3421), so it never needs your login;
it refuses a PR held with do-not-automerge (pr-unhold first) or by a
release gate's own label (the gate re-arms it when its condition clears).
run-rerun, run-cancel and workflow-run need Actions write, which only wren
has (permissions.tsv); they refuse for an agent without it.

See docs/guides/creating-an-agent-github-app.md for the SOP these implement,
and docs/guides/agent-github-identities.md for why per-agent Apps at all.

";

/// What ends a command early: the exit status (die is 1).
type Res<T = ()> = Result<T, i32>;

fn cat(parts: &[&[u8]]) -> Vec<u8> {
    sh::cat(parts)
}

fn s(b: &[u8]) -> String {
    String::from_utf8_lossy(b).into_owned()
}

fn out(b: &[u8]) {
    sh::out(b);
}

fn err(b: &[u8]) {
    sh::err(b);
}

/// `die`: `agent-app: <message>` on stderr; the caller exits 1.
fn die(msg: &[u8]) -> i32 {
    err(&cat(&[b"agent-app: ", msg, b"\n"]));
    1
}

/// A refusal decided from the arguments alone: the message `die` prints.
#[derive(Debug, PartialEq)]
pub struct Refusal(pub Vec<u8>);

fn refuse(parts: &[&[u8]]) -> Refusal {
    Refusal(cat(parts))
}

impl From<Refusal> for i32 {
    fn from(r: Refusal) -> i32 {
        die(&r.0)
    }
}

// ---------------------------------------------------------------------------
// running things
// ---------------------------------------------------------------------------

#[derive(Clone, Copy, PartialEq)]
enum Io {
    Inherit,
    Null,
    Capture,
}

fn stdio(io: Io) -> Stdio {
    match io {
        Io::Inherit => Stdio::inherit(),
        Io::Null => Stdio::null(),
        Io::Capture => Stdio::piped(),
    }
}

/// Run `cmd` (stdin inherited) with stdout and stderr as given; its status
/// and captured stdout. A command that cannot start reports what bash would
/// (`line`), unless its stderr goes to /dev/null.
fn run(line: u32, cmd: &mut Command, o: Io, e: Io) -> (i32, Vec<u8>) {
    let _ = std::io::stdout().flush();
    cmd.stdout(stdio(o)).stderr(stdio(e));
    match cmd.spawn() {
        Ok(child) => match child.wait_with_output() {
            Ok(r) => (sh::status_code(r.status), r.stdout),
            Err(_) => (1, Vec::new()),
        },
        Err(x) => {
            if e != Io::Null {
                err(&sh::spawn_diag(line, cmd, &x));
            }
            (sh::spawn_failure_status(&x), Vec::new())
        }
    }
}

/// Run `cmd` with `input` on stdin, stdout captured, stderr passed through.
fn run_with_input(line: u32, cmd: &mut Command, input: &[u8]) -> (i32, Vec<u8>) {
    let _ = std::io::stdout().flush();
    cmd.stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit());
    let mut child = match cmd.spawn() {
        Ok(c) => c,
        Err(x) => {
            err(&sh::spawn_diag(line, cmd, &x));
            return (sh::spawn_failure_status(&x), Vec::new());
        }
    };
    let mut sin = child.stdin.take().expect("piped stdin");
    let data = input.to_vec();
    let writer = std::thread::spawn(move || {
        let _ = sin.write_all(&data);
    });
    let r = child.wait_with_output();
    let _ = writer.join();
    match r {
        Ok(r) => (sh::status_code(r.status), r.stdout),
        Err(_) => (1, Vec::new()),
    }
}

extern "C" {
    fn pipe(fds: *mut c_int) -> c_int;
    fn dup2(old: c_int, new: c_int) -> c_int;
    fn close(fd: c_int) -> c_int;
}

/// A pipe: (read end, write end), neither close-on-exec.
fn os_pipe() -> Option<(c_int, c_int)> {
    let mut fds = [0 as c_int; 2];
    // SAFETY: fds has room for the two descriptors pipe(2) writes.
    if unsafe { pipe(fds.as_mut_ptr()) } != 0 {
        return None;
    }
    Some((fds[0], fds[1]))
}

fn write_fd(fd: c_int, data: &[u8]) {
    use std::os::unix::io::FromRawFd;
    // SAFETY: fd is a pipe end this process owns; the File closes it.
    let mut f = unsafe { std::fs::File::from_raw_fd(fd) };
    let _ = f.write_all(data);
}

/// Run `cmd` with stdout and stderr in ONE capture, in the order written, as
/// `$(cmd 2>&1)` has them.
fn run_merged(line: u32, mut cmd: Command) -> (i32, Vec<u8>) {
    use std::io::Read;
    use std::os::unix::io::FromRawFd;
    let _ = std::io::stdout().flush();
    let (r, w) = match os_pipe() {
        Some(p) => p,
        None => return (1, Vec::new()),
    };
    // SAFETY: r and w are the fresh pipe ends from os_pipe, owned here.
    let (mut rf, wf) = unsafe { (std::fs::File::from_raw_fd(r), std::fs::File::from_raw_fd(w)) };
    let wf2 = match wf.try_clone() {
        Ok(f) => f,
        Err(_) => return (1, Vec::new()),
    };
    cmd.stdout(Stdio::from(wf)).stderr(Stdio::from(wf2));
    let spawned = cmd.spawn();
    let diag = match &spawned {
        Err(x) => sh::spawn_diag(line, &cmd, x),
        Ok(_) => Vec::new(),
    };
    // The Command holds our copies of the write end: drop it, so the read
    // sees EOF once the child is done.
    drop(cmd);
    let mut child = match spawned {
        Ok(c) => c,
        Err(x) => return (sh::spawn_failure_status(&x), diag),
    };
    let mut buf = Vec::new();
    let _ = rf.read_to_end(&mut buf);
    let st = child.wait().map(sh::status_code).unwrap_or(1);
    (st, buf)
}

/// `-H @<(printf 'Authorization: Bearer %s\n' "$token")`: the header goes to
/// curl through a pipe at /dev/fd/63, as bash's process substitution hands
/// it over, so the token is never in argv.
fn api_call(api: &[u8], method: &str, path: &[u8], token: &[u8]) -> (i32, Vec<u8>) {
    let header = cat(&[b"Authorization: Bearer ", token, b"\n"]);
    const FD: c_int = 63;
    let piped = os_pipe().map(|(r, w)| {
        write_fd(w, &header);
        if r != FD {
            // SAFETY: r is our pipe's read end; FD is unused by this process.
            unsafe {
                dup2(r, FD);
                close(r);
            }
        }
    });
    let mut c = Command::new("curl");
    c.arg("-sSf")
        .arg("-X")
        .arg(method)
        .arg(sh::os(&cat(&[api, path])))
        .arg("-H")
        .arg("@/dev/fd/63")
        .arg("-H")
        .arg("Accept: application/vnd.github+json")
        .arg("-H")
        .arg("X-GitHub-Api-Version: 2022-11-28");
    let r = run(line::API_CALL, &mut c, Io::Capture, Io::Inherit);
    if piped.is_some() {
        // SAFETY: FD is the read end placed above; nothing else uses it.
        unsafe {
            close(FD);
        }
    }
    r
}

/// base64url without padding, what `openssl base64 -A | tr '+/' '-_' | tr -d '='`
/// gives once `$(...)` has dropped the newline.
pub fn b64url(data: &[u8]) -> Vec<u8> {
    const T: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    let mut o = Vec::with_capacity(data.len() * 4 / 3 + 4);
    for ch in data.chunks(3) {
        let b = [ch[0], *ch.get(1).unwrap_or(&0), *ch.get(2).unwrap_or(&0)];
        let n = (b[0] as u32) << 16 | (b[1] as u32) << 8 | b[2] as u32;
        o.push(T[(n >> 18) as usize & 63]);
        o.push(T[(n >> 12) as usize & 63]);
        if ch.len() > 1 {
            o.push(T[(n >> 6) as usize & 63]);
        }
        if ch.len() > 2 {
            o.push(T[n as usize & 63]);
        }
    }
    o
}

fn unix_now() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

/// `app_jwt` as `$(app_jwt ...)` sees it: what it printed. An unreadable key
/// is reported and gives nothing (the caller carries on, as the script's
/// does: a failed substitution in an argument stops nothing).
fn app_jwt(app_id: &[u8], key: &[u8]) -> Vec<u8> {
    if !sh::is_readable(key) {
        die(&cat(&[b"cannot read private key: ", key]));
        return Vec::new();
    }
    let now = unix_now();
    let header = b64url(br#"{"alg":"RS256","typ":"JWT"}"#);
    let payload = b64url(&cat(&[
        format!("{{\"iat\":{},\"exp\":{},\"iss\":\"", now - 60, now + 540).as_bytes(),
        app_id,
        b"\"}",
    ]));
    let signing_input = cat(&[&header, b".", &payload]);
    let mut c = Command::new("openssl");
    c.args(["dgst", "-sha256", "-sign"])
        .arg(sh::os(key))
        .arg("-binary");
    let (_, sig) = run_with_input(line::SIGN, &mut c, &signing_input);
    cat(&[&signing_input, b".", &b64url(&sig)])
}

/// Run a jq program on `input`, printing its stderr; (stdout, status).
fn jq(prog: &jq::Prog, input: &[u8], exit_status: bool) -> (Vec<u8>, i32) {
    let r = jq::run(prog, input, exit_status);
    err(&r.stderr);
    (r.stdout, r.status)
}

/// pipefail: the last failing status in a pipeline, else 0.
fn pipe_status(left: i32, right: i32) -> i32 {
    if right != 0 {
        right
    } else {
        left
    }
}

// ---------------------------------------------------------------------------
// awk over the committed tables
// ---------------------------------------------------------------------------

/// The value awk's `-v a=VALUE` assigns: its escape sequences processed.
pub fn awk_v(v: &[u8]) -> Vec<u8> {
    let mut o = Vec::with_capacity(v.len());
    let mut i = 0;
    while i < v.len() {
        let c = v[i];
        if c != b'\\' || i + 1 >= v.len() {
            o.push(c);
            i += 1;
            continue;
        }
        let n = v[i + 1];
        i += 2;
        match n {
            b'\\' => o.push(b'\\'),
            b'"' => o.push(b'"'),
            b'/' => o.push(b'/'),
            b'n' => o.push(b'\n'),
            b't' => o.push(b'\t'),
            b'r' => o.push(b'\r'),
            b'a' => o.push(7),
            b'b' => o.push(8),
            b'f' => o.push(12),
            b'v' => o.push(11),
            b'0'..=b'7' => {
                let mut val = (n - b'0') as u32;
                let mut k = 0;
                while k < 2 && i < v.len() && (b'0'..=b'7').contains(&v[i]) {
                    val = val * 8 + (v[i] - b'0') as u32;
                    i += 1;
                    k += 1;
                }
                o.push(val as u8);
            }
            other => {
                o.push(b'\\');
                o.push(other);
            }
        }
    }
    o
}

/// The records of a tab-separated table awk reads (`-F'\t'`), comment lines
/// (`/^#/`) left out. None when the file cannot be read, after awk's
/// complaint.
fn table(path: &[u8]) -> Option<Vec<Vec<Vec<u8>>>> {
    match std::fs::read(sh::path(path)) {
        Ok(data) => Some(
            sh::lines(&data)
                .into_iter()
                .filter(|l| !l.starts_with(b"#"))
                .map(|l| {
                    if l.is_empty() {
                        Vec::new()
                    } else {
                        l.split(|&c| c == b'\t').map(<[u8]>::to_vec).collect()
                    }
                })
                .collect(),
        ),
        Err(_) => {
            if cfg!(target_os = "macos") {
                err(&cat(&[
                    b"awk: can't open file ",
                    path,
                    b"\n source line number 1\n",
                ]));
            } else {
                err(&cat(&[
                    b"awk: cannot open ",
                    path,
                    b" (No such file or directory)\n",
                ]));
            }
            None
        }
    }
}

fn field(rec: &[Vec<u8>], n: usize) -> &[u8] {
    rec.get(n - 1).map(Vec::as_slice).unwrap_or(b"")
}

/// `awk -F'\t' -v a="$agent" '!/^#/ && $1==a {print $N}' FILE` as `$(...)`
/// captures it; None when awk could not read the file (it exits 2).
fn column_or_fail(path: &[u8], agent: &[u8], n: usize) -> Option<Vec<u8>> {
    let a = awk_v(agent);
    let mut o = Vec::new();
    for rec in table(path)? {
        if field(&rec, 1) == a.as_slice() {
            o.extend_from_slice(field(&rec, n));
            o.push(b'\n');
        }
    }
    Some(sh::subst(o))
}

fn column(path: &[u8], agent: &[u8], n: usize) -> Vec<u8> {
    let a = awk_v(agent);
    let mut o = Vec::new();
    for rec in table(path).unwrap_or_default() {
        if field(&rec, 1) == a.as_slice() {
            o.extend_from_slice(field(&rec, n));
            o.push(b'\n');
        }
    }
    sh::subst(o)
}

// ---------------------------------------------------------------------------
// the tool
// ---------------------------------------------------------------------------

pub struct Tool {
    api: Vec<u8>,
    registry: Vec<u8>,
    key_dir: Vec<u8>,
    permissions: Vec<u8>,
    allowlist: Vec<u8>,
    landed: Vec<u8>,
    gh: Vec<u8>,
}

/// `${BASH_SOURCE[0]}` for this program: the path it was started by, or,
/// for a bare name, where `$PATH` finds it.
fn source_path(argv0: &[u8]) -> Vec<u8> {
    if argv0.contains(&b'/') {
        return argv0.to_vec();
    }
    match sh::which(argv0) {
        Some(p) => sh::path_bytes(&p),
        None => argv0.to_vec(),
    }
}

impl Tool {
    /// Everything the script resolves before `main`: the registry, the key
    /// folder (a worktree borrows the main checkout's), and the committed
    /// permissions, allowlist and landed gate, which an environment variable
    /// may replace only under `bazel test`.
    pub fn new(argv0: &[u8]) -> Tool {
        let here = sh::dirname(&source_path(argv0));
        let bwd = sh::env_or_empty("BUILD_WORKSPACE_DIRECTORY");
        let base = |ws: &[u8], rel: &[u8]| -> Vec<u8> {
            if bwd.is_empty() {
                cat(&[&here, b"/", rel])
            } else {
                cat(&[&bwd, b"/tools/", ws])
            }
        };
        let registry = sh::env_or(
            "AGENT_REGISTRY",
            &base(b"agent-app/agents.tsv", b"agents.tsv"),
        );
        let mut default_key_dir = base(
            b"sync-env-secrets/agent-keys",
            b"../sync-env-secrets/agent-keys",
        );
        if !sh::env_set_nonempty("AGENT_KEY_DIR") && !sh::is_dir(&default_key_dir) {
            let mut c = Command::new("git");
            c.arg("-C")
                .arg(sh::os(&sh::dirname(&default_key_dir)))
                .args(["rev-parse", "--path-format=absolute", "--git-common-dir"]);
            let (st, o) = run(line::KEY_DIR_GIT, &mut c, Io::Capture, Io::Null);
            if st == 0 {
                let cand = cat(&[
                    &sh::dirname(&sh::subst(o)),
                    b"/tools/sync-env-secrets/agent-keys",
                ]);
                if sh::is_dir(&cand) {
                    default_key_dir = cand;
                }
            }
        }
        let key_dir = sh::env_or("AGENT_KEY_DIR", &default_key_dir);
        let in_test = sh::env_set_nonempty("TEST_SRCDIR") || sh::env_set_nonempty("TEST_TMPDIR");
        let over = |name: &str, default: Vec<u8>| -> Vec<u8> {
            if in_test {
                sh::env_or(name, &default)
            } else {
                default
            }
        };
        Tool {
            api: sh::env_or("GITHUB_API_URL", b"https://api.github.com"),
            registry,
            key_dir,
            permissions: over(
                "AGENT_PERMISSIONS",
                base(b"agent-app/permissions.tsv", b"permissions.tsv"),
            ),
            allowlist: over(
                "WORKFLOW_ALLOWLIST",
                base(
                    b"agent-app/workflow-allowlist.txt",
                    b"workflow-allowlist.txt",
                ),
            ),
            landed: over(
                "AGENT_APP_LANDED",
                base(b"landed/landed.sh", b"../landed/landed.sh"),
            ),
            gh: sh::env_or("GH_BIN", b"gh"),
        }
    }

    // --- the App API ------------------------------------------------------

    fn convert(&self, args: &[Vec<u8>]) -> Res {
        let code = arg(args, 0);
        let outp = arg(args, 1);
        if code.is_empty() || outp.is_empty() {
            return Err(die(b"usage: convert <manifest-code> <out.pem>"));
        }
        if sh::exists(outp) {
            return Err(die(&cat(&[b"refusing to overwrite existing key: ", outp])));
        }
        let mut c = Command::new("curl");
        c.args(["-sSf", "-X", "POST"])
            .arg(sh::os(&cat(&[
                &self.api,
                b"/app-manifests/",
                code,
                b"/conversions",
            ])))
            .args(["-H", "Accept: application/vnd.github+json"])
            .args(["-H", "X-GitHub-Api-Version: 2022-11-28"]);
        let (st, o) = run(line::CONVERT_CURL, &mut c, Io::Capture, Io::Inherit);
        if st != 0 {
            return Err(die(b"manifest conversion failed -- the code is single-use and expires in 1h; redo the browser step"));
        }
        let resp = sh::subst(o);
        let old = sh::umask(0o077);
        let opened = std::fs::OpenOptions::new()
            .write(true)
            .create(true)
            .truncate(true)
            .mode(0o666)
            .open(sh::path(outp));
        let mut f = match opened {
            Ok(f) => f,
            Err(e) => {
                sh::redirect_error(line::CONVERT_PEM, outp, &e);
                return Err(die(b"response contained no pem"));
            }
        };
        let (pem, pst) = jq(&jq::Prog::Field("pem"), &resp, true);
        let _ = f.write_all(&pem);
        drop(f);
        if pst != 0 {
            return Err(die(b"response contained no pem"));
        }
        sh::umask(old);
        let outs = s(outp);
        let (summary, sst) = jq(&jq::Prog::Convert(&outs), &resp, false);
        out(&summary);
        if sst != 0 {
            return Err(sst);
        }
        err(&cat(&[
            b"agent-app: key written to ",
            outp,
            b" (mode 600). GitHub will not issue it again.\n",
        ]));
        Ok(())
    }

    fn installations(&self, args: &[Vec<u8>]) -> Res {
        let (app_id, key) = (arg(args, 0), arg(args, 1));
        if app_id.is_empty() || key.is_empty() {
            return Err(die(b"usage: installations <app-id> <key.pem>"));
        }
        let jwt = app_jwt(app_id, key);
        let (st, o) = api_call(&self.api, "GET", b"/app/installations", &jwt);
        let (j, jst) = jq(&jq::Prog::Installations, &o, false);
        out(&j);
        status(pipe_status(st, jst))
    }

    fn repos(&self, args: &[Vec<u8>]) -> Res {
        let (app_id, key, inst) = (arg(args, 0), arg(args, 1), arg(args, 2));
        if app_id.is_empty() || key.is_empty() || inst.is_empty() {
            return Err(die(b"usage: repos <app-id> <key.pem> <installation-id>"));
        }
        let (tok, tst) = self.token(app_id, key, inst);
        if tst != 0 {
            return Err(tst);
        }
        let tok = sh::subst(tok);
        let (st, o) = api_call(&self.api, "GET", b"/installation/repositories", &tok);
        let (j, jst) = jq(&jq::Prog::Repos, &o, false);
        out(&j);
        status(pipe_status(st, jst))
    }

    /// `cmd_token`: (what it prints, its status).
    fn token(&self, app_id: &[u8], key: &[u8], inst: &[u8]) -> (Vec<u8>, i32) {
        if app_id.is_empty() || key.is_empty() || inst.is_empty() {
            return (
                Vec::new(),
                die(b"usage: token <app-id> <key.pem> <installation-id>"),
            );
        }
        let jwt = app_jwt(app_id, key);
        let path = cat(&[b"/app/installations/", inst, b"/access_tokens"]);
        let (st, o) = api_call(&self.api, "POST", &path, &jwt);
        let (j, jst) = jq(&jq::Prog::Field("token"), &o, true);
        (j, pipe_status(st, jst))
    }

    // --- agents -----------------------------------------------------------

    fn known_agents(&self) -> Vec<u8> {
        let mut o = Vec::new();
        for rec in table(&self.registry).unwrap_or_default() {
            if rec.len() >= 3 {
                o.extend_from_slice(&rec[0]);
                o.push(b' ');
            }
        }
        o
    }

    /// `cmd_login`: (what it prints, its status).
    fn login(&self, agent: &[u8]) -> (Vec<u8>, i32) {
        if agent.is_empty() {
            let k = self.known_agents();
            return (
                Vec::new(),
                die(&cat(&[b"usage: login <agent>   (one of: ", &k, b")"])),
            );
        }
        if !sh::is_readable(&self.registry) {
            return (
                Vec::new(),
                die(&cat(&[b"cannot read agent registry: ", &self.registry])),
            );
        }
        let app_id = column(&self.registry, agent, 2);
        let inst = column(&self.registry, agent, 3);
        if app_id.is_empty() || inst.is_empty() {
            let k = self.known_agents();
            return (
                Vec::new(),
                die(&cat(&[b"unknown agent '", agent, b"' -- known: ", &k])),
            );
        }
        let key = cat(&[&self.key_dir, b"/", agent, b".pem"]);
        if !sh::is_readable(&key) {
            return (
                Vec::new(),
                die(&cat(&[
                    b"no key at ",
                    &key,
                    b" -- run: bazel run //tools/sync-env-secrets:agent-keys-pull",
                ])),
            );
        }
        self.token(&app_id, &key, &inst)
    }

    fn env(&self, args: &[Vec<u8>]) -> Res {
        let agent = arg(args, 0);
        if agent.is_empty() {
            let k = self.known_agents();
            return Err(die(&cat(&[b"usage: env <agent>   (one of: ", &k, b")"])));
        }
        let slug = cat(&[b"vitruvian-", agent, b"-agent"]);
        // Under set -e a failed awk ends the script with awk's status.
        let bot_id = column_or_fail(&self.registry, agent, 4).ok_or(2)?;
        if bot_id.is_empty() {
            return Err(die(&cat(&[
                b"no bot_user_id for '",
                agent,
                b"' in ",
                &self.registry,
            ])));
        }
        let (o, st) = self.login(agent);
        if st != 0 {
            return Err(1);
        }
        let token = sh::subst(o);
        let email = cat(&[
            b"'",
            &bot_id,
            b"+",
            &slug,
            b"[bot]@users.noreply.github.com'",
        ]);
        let name = cat(&[b"'", &slug, b"[bot]'"]);
        out(&cat(&[
            b"export GH_TOKEN=",
            &token,
            b"\nexport GIT_AUTHOR_NAME=",
            &name,
            b"\nexport GIT_AUTHOR_EMAIL=",
            &email,
            b"\nexport GIT_COMMITTER_NAME=",
            &name,
            b"\nexport GIT_COMMITTER_EMAIL=",
            &email,
            b"\n",
        ]));
        Ok(())
    }

    /// `mint_token`: the agent's token, or die saying `<not_done>`.
    fn mint_token(&self, agent: &[u8], not_done: &[u8]) -> Res<Vec<u8>> {
        let (o, st) = self.login(agent);
        let tok = sh::subst(o);
        if st != 0 || tok.is_empty() {
            return Err(die(&cat(&[
                b"could not mint a token for the ",
                agent,
                b" app; ",
                not_done,
            ])));
        }
        Ok(tok)
    }

    // --- gh as the agent ----------------------------------------------------

    fn gh_cmd(&self, token: &[u8], args: &[&[u8]]) -> Command {
        let mut c = Command::new(sh::os(&self.gh));
        for a in args {
            c.arg(sh::os(a));
        }
        c.env("GH_TOKEN", sh::os(token)).env("GITHUB_TOKEN", "");
        c
    }

    fn gh(&self, token: &[u8], args: &[&[u8]], o: Io, e: Io) -> (i32, Vec<u8>) {
        let mut c = self.gh_cmd(token, args);
        run(line::GH_AS, &mut c, o, e)
    }

    /// `exec_gh_as`: only returns when gh could not be started.
    fn exec_gh(&self, token: &[u8], args: &[&[u8]]) -> i32 {
        let _ = std::io::stdout().flush();
        let mut c = self.gh_cmd(token, args);
        let e = c.exec();
        let prog = std::env::args_os()
            .next()
            .map(|a| a.as_bytes().to_vec())
            .unwrap_or_default();
        let what = if !self.gh.contains(&b'/') && e.kind() == std::io::ErrorKind::NotFound {
            cat(&[b"exec: ", &self.gh, b": not found"])
        } else {
            cat(&[&self.gh, b": ", sh::strerror(&e).as_bytes()])
        };
        err(&cat(&[
            &prog,
            format!(": line {}: ", line::EXEC_GH).as_bytes(),
            &what,
            b"\n",
        ]));
        sh::spawn_failure_status(&e)
    }

    fn pass(&self, token: &[u8], head: &[&[u8]], rest: &[Vec<u8>]) -> Res {
        let mut v: Vec<&[u8]> = head.to_vec();
        v.extend(rest.iter().map(Vec::as_slice));
        Err(self.exec_gh(token, &v))
    }

    // --- pull requests ------------------------------------------------------

    fn pr_create(&self, args: &[Vec<u8>]) -> Res {
        let (agent, rest) = take_agent(args)
            .ok_or_else(|| die(b"usage: pr-create [--agent <agent>] [gh pr create args]"))?;
        let has = has_fast_lane(rest);
        let tok = self.mint_token(&agent, b"the PR was NOT opened")?;
        let mut v: Vec<Vec<u8>> = rest.to_vec();
        if !has {
            v.push(b"--label".to_vec());
            v.push(FAST_LANE_LABEL.as_bytes().to_vec());
        }
        to_caller_dir()?;
        self.pass(&tok, &[b"pr", b"create"], &v)
    }

    fn pr_passthrough(&self, verb: &[u8], usage: &str, args: &[Vec<u8>]) -> Res {
        let (agent, rest) =
            take_agent(args).ok_or_else(|| die(&cat(&[b"usage: ", usage.as_bytes()])))?;
        need_target("pr", usage, arg(rest, 0))?;
        let tok = self.mint_token(&agent, b"the PR was NOT changed")?;
        to_caller_dir()?;
        self.pass(&tok, &[b"pr", verb], rest)
    }

    fn pr_comment(&self, args: &[Vec<u8>]) -> Res {
        let usage = "pr-comment [--agent <agent>] <pr> --body-file <f> | --body <s>";
        let (agent, rest) =
            take_agent(args).ok_or_else(|| die(&cat(&[b"usage: ", usage.as_bytes()])))?;
        need_target("pr", usage, arg(rest, 0))?;
        if !has_body(rest.get(1..).unwrap_or(&[])) {
            return Err(die(&cat(&[
                b"usage: ",
                usage.as_bytes(),
                b"   (give the body: without it gh waits for an editor)",
            ])));
        }
        let tok = self.mint_token(&agent, b"the comment was NOT posted")?;
        to_caller_dir()?;
        self.pass(&tok, &[b"pr", b"comment"], rest)
    }

    fn pr_review(&self, args: &[Vec<u8>]) -> Res {
        let usage = "pr-review [--agent <agent>] <pr> (--approve | --comment | --request-changes) [--body-file <f> | --body <s>]";
        let (agent, rest) =
            take_agent(args).ok_or_else(|| die(&cat(&[b"usage: ", usage.as_bytes()])))?;
        need_target("pr", usage, arg(rest, 0))?;
        review_args(usage, rest.get(1..).unwrap_or(&[]))?;
        let tok = self.mint_token(&agent, b"the review was NOT posted")?;
        to_caller_dir()?;
        self.pass(&tok, &[b"pr", b"review"], rest)
    }

    fn pr_node_id(&self, tok: &[u8], pr: &[u8], repo: &Option<Vec<u8>>) -> Option<Vec<u8>> {
        let mut v: Vec<&[u8]> = vec![b"pr", b"view", pr];
        if let Some(r) = repo {
            v.push(b"--repo");
            v.push(r);
        }
        v.extend_from_slice(&[b"--json", b"id", b"--jq", b".id"]);
        let (st, o) = self.gh(tok, &v, Io::Capture, Io::Inherit);
        let id = sh::subst(o);
        if st == 0 && !id.is_empty() {
            Some(id)
        } else {
            None
        }
    }

    /// `hold_state`: Some(its answer) when gh succeeded.
    fn hold_state(&self, tok: &[u8], id: &[u8]) -> Option<Vec<u8>> {
        let idarg = cat(&[b"id=", id]);
        let q = cat(&[b"query=", HOLD_QUERY.as_bytes()]);
        let j = hold_jq();
        let (st, o) = self.gh(
            tok,
            &[
                b"api",
                b"graphql",
                b"-f",
                &idarg,
                b"-f",
                &q,
                b"--jq",
                j.as_bytes(),
            ],
            Io::Capture,
            Io::Inherit,
        );
        if st == 0 {
            Some(sh::subst(o))
        } else {
            None
        }
    }

    fn pr_enqueue(&self, args: &[Vec<u8>]) -> Res {
        let usage = "pr-enqueue [--agent <agent>] <pr> [gh pr merge args, never --admin]";
        let (agent, rest) =
            take_agent(args).ok_or_else(|| die(&cat(&[b"usage: ", usage.as_bytes()])))?;
        let flags = enqueue_args(rest)?;
        need_target("pr", usage, arg(rest, 0))?;
        let pr = arg(rest, 0).to_vec();
        let tok = self.mint_token(&agent, b"auto-merge was NOT armed")?;
        to_caller_dir()?;
        let id = self.pr_node_id(&tok, &pr, &flags.repo).ok_or_else(|| {
            die(&cat(&[
                b"could not look ",
                &pr,
                b" up; auto-merge was NOT armed",
            ]))
        })?;
        let st = self.hold_state(&tok, &id).ok_or_else(|| {
            die(&cat(&[
                b"could not read ",
                &pr,
                b" from GitHub; auto-merge was NOT armed",
            ]))
        })?;
        let f = read5(&st);
        let (labelled, pr_state, gate) = (&f[2], &f[3], &f[4]);
        if labelled.as_slice() == b"true" {
            return Err(die(&cat(&[
                &pr,
                b" is held (",
                HOLD_LABEL.as_bytes(),
                b"); auto-merge was NOT armed. If the hold should end, run pr-unhold ",
                &pr,
                b" first",
            ])));
        }
        if gate.as_slice() == RELEASE_HOLD_LABEL.as_bytes() {
            return Err(die(&cat(&[&pr, b" is held by release-hold (", gate, b": its development deploy is red); auto-merge was NOT armed. The gate re-arms the PR itself once development is green again, so leave it to the gate"])));
        } else if gate.as_slice() == BETA_GATE_LABEL.as_bytes() {
            return Err(die(&cat(&[&pr, b" is held by release-beta-gate (", gate, b": its beta build is not green); auto-merge was NOT armed. The gate re-arms the PR itself once the beta is built, so leave it to the gate"])));
        } else if !(gate.as_slice() == b"-" || gate.is_empty()) {
            return Err(die(&cat(&[
                &pr,
                b" carries an unknown hold (",
                gate,
                b"); auto-merge was NOT armed",
            ])));
        }
        match pr_state.as_slice() {
            b"OPEN" => {}
            b"MERGED" => {
                out(&cat(&[b"agent-app: ", &pr, b" is already merged\n"]));
                return Ok(());
            }
            other => {
                let shown: &[u8] = if other.is_empty() { b"unknown" } else { other };
                return Err(die(&cat(&[
                    &pr,
                    b" is ",
                    shown,
                    b", not open; auto-merge was NOT armed",
                ])));
            }
        }
        let mut v: Vec<&[u8]> = vec![b"pr", b"merge"];
        v.extend(rest.iter().map(Vec::as_slice));
        if !flags.auto {
            v.push(b"--auto");
        }
        if !flags.method {
            v.push(b"--squash");
        }
        let (mst, _) = self.gh(&tok, &v, Io::Inherit, Io::Inherit);
        if mst != 0 {
            return Err(die(&cat(&[
                b"gh pr merge failed; auto-merge was NOT armed on ",
                &pr,
            ])));
        }
        let tries = arith(&sh::env_or("AGENT_APP_VERIFY_TRIES", b"5"));
        let idarg = cat(&[b"id=", &id]);
        let q = cat(&[b"query=", ENQUEUE_QUERY.as_bytes()]);
        let mut state: Vec<u8> = Vec::new();
        let mut i: i64 = 1;
        while i <= tries {
            let (gst, o) = self.gh(
                &tok,
                &[
                    b"api",
                    b"graphql",
                    b"-f",
                    &idarg,
                    b"-f",
                    &q,
                    b"--jq",
                    ENQUEUE_JQ.as_bytes(),
                ],
                Io::Capture,
                Io::Inherit,
            );
            state = if gst == 0 { sh::subst(o) } else { Vec::new() };
            if state.starts_with(b"queue ") {
                let f = sh::read_fields(first_line(&state), b" \t\n", 3);
                out(&cat(&[
                    b"agent-app: ",
                    &pr,
                    b" is in the merge queue (mergeQueueEntry: position ",
                    &f[1],
                    b", ",
                    &f[2],
                    b")\n",
                ]));
                return Ok(());
            }
            if state.starts_with(b"auto ") {
                let f = sh::read_fields(first_line(&state), b" \t\n", 3);
                out(&cat(&[
                    b"agent-app: ",
                    &pr,
                    b" has auto-merge armed by ",
                    &f[1],
                    b" (autoMergeRequest: ",
                    &f[2],
                    b"); it joins the merge queue when its checks pass\n",
                ]));
                return Ok(());
            }
            if state.as_slice() == b"none MERGED" {
                out(&cat(&[b"agent-app: ", &pr, b" is already merged\n"]));
                return Ok(());
            }
            if test_lt(i, &sh::env_or("AGENT_APP_VERIFY_TRIES", b"5")) {
                let mut c = Command::new("sleep");
                c.arg(sh::os(&sh::env_or("AGENT_APP_VERIFY_SLEEP", b"2")));
                let (sst, _) = run(line::SLEEP, &mut c, Io::Inherit, Io::Inherit);
                if sst != 0 {
                    return Err(sst);
                }
            }
            i += 1;
        }
        let shown: &[u8] = if state.is_empty() {
            b"no answer"
        } else {
            &state
        };
        Err(die(&cat(&[
            b"gh reported success, but GitHub shows neither autoMergeRequest nor mergeQueueEntry on ",
            &pr,
            b" (",
            shown,
            b"); it is NOT queued",
        ])))
    }

    fn pr_hold(&self, args: &[Vec<u8>]) -> Res {
        let usage = "pr-hold [--agent <agent>] <pr> [--reason <s>]";
        let (agent, rest) =
            take_agent(args).ok_or_else(|| die(&cat(&[b"usage: ", usage.as_bytes()])))?;
        need_target("pr", usage, arg(rest, 0))?;
        let pr = rest[0].clone();
        let h = hold_args(usage, true, &rest[1..])?;
        let tok = self.mint_token(&agent, b"the PR was NOT held")?;
        to_caller_dir()?;
        let id = self.pr_node_id(&tok, &pr, &h.repo).ok_or_else(|| {
            die(&cat(&[
                b"could not look ",
                &pr,
                b" up; the PR was NOT held",
            ]))
        })?;
        let st = self.hold_state(&tok, &id).ok_or_else(|| {
            die(&cat(&[
                b"could not read ",
                &pr,
                b" from GitHub; the PR was NOT held",
            ]))
        })?;
        let f = read5(&st);
        if f[3].as_slice() != b"OPEN" {
            let shown: &[u8] = if f[3].is_empty() { b"unknown" } else { &f[3] };
            return Err(die(&cat(&[
                &pr,
                b" is ",
                shown,
                b", not open; nothing to hold",
            ])));
        }
        let with_repo = |head: &[&[u8]], tail: &[&[u8]]| -> Vec<Vec<u8>> {
            let mut v: Vec<Vec<u8>> = head.iter().map(|x| x.to_vec()).collect();
            if let Some(r) = &h.repo {
                v.push(b"--repo".to_vec());
                v.push(r.clone());
            }
            v.extend(tail.iter().map(|x| x.to_vec()));
            v
        };
        let gh_v = |v: Vec<Vec<u8>>| -> i32 {
            let refs: Vec<&[u8]> = v.iter().map(Vec::as_slice).collect();
            self.gh(&tok, &refs, Io::Null, Io::Inherit).0
        };
        if f[2].as_slice() != b"true" {
            let v = with_repo(
                &[b"pr", b"edit", &pr],
                &[b"--add-label", HOLD_LABEL.as_bytes()],
            );
            if gh_v(v) != 0 {
                return Err(die(&cat(&[
                    b"could not add ",
                    HOLD_LABEL.as_bytes(),
                    b" to ",
                    &pr,
                    b"; nothing was changed and the PR is NOT held",
                ])));
            }
        }
        let mut disable_failed = false;
        if f[0].as_slice() == b"true" {
            let v = with_repo(&[b"pr", b"merge", &pr], &[b"--disable-auto"]);
            if gh_v(v) != 0 {
                disable_failed = true;
            }
        }
        let st = self.hold_state(&tok, &id).ok_or_else(|| {
            die(&cat(&[
                b"could not read ",
                &pr,
                b" back from GitHub; it is labelled, but check the hold by hand",
            ]))
        })?;
        let f = read5(&st);
        let mut dequeued: &[u8] = b"";
        if f[1].as_slice() == b"true" {
            let idarg = cat(&[b"id=", &id]);
            let q = cat(&[b"query=", DEQUEUE_MUTATION.as_bytes()]);
            let (dst, _) = self.gh(
                &tok,
                &[b"api", b"graphql", b"-f", &idarg, b"-f", &q],
                Io::Null,
                Io::Inherit,
            );
            if dst != 0 {
                return Err(die(&cat(&[
                    b"could not take ",
                    &pr,
                    b" out of the merge queue; it is labelled but NOT held",
                ])));
            }
            dequeued = b" and taken out of the merge queue";
        }
        if disable_failed {
            return Err(die(&cat(&[
                b"could not turn auto-merge off on ",
                &pr,
                b"; it is labelled",
                dequeued,
                b", but NOT held: it can still merge",
            ])));
        }
        let st = self.hold_state(&tok, &id).ok_or_else(|| {
            die(&cat(&[
                b"could not read ",
                &pr,
                b" back from GitHub; check the hold by hand",
            ]))
        })?;
        let f = read5(&st);
        if !(f[0].as_slice() == b"false"
            && f[1].as_slice() == b"false"
            && f[2].as_slice() == b"true")
        {
            return Err(die(&cat(&[
                b"GitHub still shows auto-merge armed: ",
                &f[0],
                b", in the merge queue: ",
                &f[1],
                b", ",
                HOLD_LABEL.as_bytes(),
                b": ",
                &f[2],
                b"; ",
                &pr,
                b" is NOT held",
            ])));
        }
        out(&cat(&[
            b"agent-app: ",
            &pr,
            b" is held: ",
            HOLD_LABEL.as_bytes(),
            b" on, auto-merge off, not in the merge queue\n",
        ]));
        if !h.reason.is_empty() {
            let body = cat(&[
                b"Held by the ",
                &agent,
                b" agent: ",
                &h.reason,
                b"\n\nThe `",
                HOLD_LABEL.as_bytes(),
                b"` label is on and auto-merge is off. To release it: `bazel run //tools/agent-app -- pr-unhold ",
                &pr,
                b"`, then `pr-enqueue ",
                &pr,
                b"` when it should land.",
            ]);
            let v = with_repo(&[b"pr", b"comment", &pr], &[b"--body", &body]);
            if gh_v(v) != 0 {
                return Err(die(&cat(&[
                    &pr,
                    b" is held, but the reason was NOT posted",
                ])));
            }
        }
        Ok(())
    }

    fn pr_unhold(&self, args: &[Vec<u8>]) -> Res {
        let usage = "pr-unhold [--agent <agent>] <pr>";
        let (agent, rest) =
            take_agent(args).ok_or_else(|| die(&cat(&[b"usage: ", usage.as_bytes()])))?;
        need_target("pr", usage, arg(rest, 0))?;
        let pr = rest[0].clone();
        let h = hold_args(usage, false, &rest[1..])?;
        let tok = self.mint_token(&agent, b"the hold was NOT released")?;
        to_caller_dir()?;
        let id = self.pr_node_id(&tok, &pr, &h.repo).ok_or_else(|| {
            die(&cat(&[
                b"could not look ",
                &pr,
                b" up; the hold was NOT released",
            ]))
        })?;
        let mut v: Vec<&[u8]> = vec![b"pr", b"edit", &pr];
        if let Some(r) = &h.repo {
            v.push(b"--repo");
            v.push(r);
        }
        v.push(b"--remove-label");
        v.push(HOLD_LABEL.as_bytes());
        if self.gh(&tok, &v, Io::Null, Io::Inherit).0 != 0 {
            return Err(die(&cat(&[
                b"could not remove ",
                HOLD_LABEL.as_bytes(),
                b" from ",
                &pr,
                b"; the hold was NOT released",
            ])));
        }
        let st = self.hold_state(&tok, &id).ok_or_else(|| {
            die(&cat(&[
                b"could not read ",
                &pr,
                b" back from GitHub; check the label by hand",
            ]))
        })?;
        let f = read5(&st);
        if f[2].as_slice() != b"false" {
            return Err(die(&cat(&[
                b"GitHub still shows ",
                HOLD_LABEL.as_bytes(),
                b" on ",
                &pr,
                b"; the hold was NOT released",
            ])));
        }
        out(&cat(&[
            b"agent-app: ",
            &pr,
            b": ",
            HOLD_LABEL.as_bytes(),
            b" removed. Auto-merge was NOT re-armed; run pr-enqueue ",
            &pr,
            b" when it should land\n",
        ]));
        Ok(())
    }

    // --- Actions ------------------------------------------------------------

    fn need_actions_write(&self, agent: &[u8]) -> Res {
        if !sh::is_readable(&self.permissions) {
            return Err(die(&cat(&[
                b"cannot read ",
                &self.permissions,
                b"; nothing was run",
            ])));
        }
        let a = awk_v(agent);
        let rows = table(&self.permissions).unwrap_or_default();
        let mut level = Vec::new();
        for r in &rows {
            if field(r, 1) == a.as_slice() && field(r, 2) == b"actions" {
                level.extend_from_slice(field(r, 3));
                level.push(b'\n');
            }
        }
        let level = sh::subst(level);
        if level.as_slice() == b"write" || level.as_slice() == b"admin" {
            return Ok(());
        }
        let mut who = Vec::new();
        for r in &rows {
            if field(r, 2) == b"actions" && (field(r, 3) == b"write" || field(r, 3) == b"admin") {
                who.extend_from_slice(field(r, 1));
                who.push(b' ');
            }
        }
        if who.is_empty() {
            return Err(die(&cat(&[
                b"the ",
                agent,
                b" app has no Actions write, and no agent App does (permissions.tsv); nothing was run",
            ])));
        }
        let first = match who.iter().position(|&c| c == b' ') {
            Some(i) => &who[..i],
            None => &who[..],
        };
        let all = who.strip_suffix(b" ").unwrap_or(&who);
        Err(die(&cat(&[
            b"the ",
            agent,
            b" app has no Actions write (permissions.tsv), so GitHub would refuse; use --agent ",
            first,
            b" (has it: ",
            all,
            b")",
        ])))
    }

    fn run_passthrough(&self, verb: &[u8], usage: &str, not_done: &[u8], args: &[Vec<u8>]) -> Res {
        let (agent, rest) =
            take_agent(args).ok_or_else(|| die(&cat(&[b"usage: ", usage.as_bytes()])))?;
        let id = arg(rest, 0);
        if id.is_empty() || !id.iter().all(u8::is_ascii_digit) {
            return Err(die(&cat(&[
                b"usage: ",
                usage.as_bytes(),
                b"   (<run-id> is the number in the run's URL)",
            ])));
        }
        self.need_actions_write(&agent)?;
        let tok = self.mint_token(&agent, not_done)?;
        to_caller_dir()?;
        self.pass(&tok, &[b"run", verb], rest)
    }

    fn workflow_run(&self, args: &[Vec<u8>]) -> Res {
        let usage = "workflow-run [--agent <agent>] <workflow.yaml> [-f k=v ...] [--ref main]";
        let (agent, rest) =
            take_agent(args).ok_or_else(|| die(&cat(&[b"usage: ", usage.as_bytes()])))?;
        need_target("workflow", usage, arg(rest, 0))?;
        let wf = rest[0].clone();
        let inputs = &rest[1..];
        workflow_args(usage, inputs)?;
        if !sh::is_readable(&self.allowlist) {
            return Err(die(&cat(&[
                b"cannot read ",
                &self.allowlist,
                b"; nothing was run",
            ])));
        }
        let allowed = allowlist(&std::fs::read(sh::path(&self.allowlist)).unwrap_or_default());
        if !allowed_has(&allowed, &wf) {
            let shown: Vec<u8> = allowed
                .split(|&c| c == b'\n')
                .collect::<Vec<_>>()
                .join(&b", "[..]);
            return Err(die(&cat(&[
                b"refusing to start '",
                &wf,
                b"': not in ",
                &sh::basename(&self.allowlist),
                b" (allowed: ",
                &shown,
                b")",
            ])));
        }
        self.need_actions_write(&agent)?;
        let tok = self.mint_token(&agent, b"the workflow was NOT started")?;
        to_caller_dir()?;
        let mut v: Vec<Vec<u8>> = vec![wf];
        v.extend_from_slice(inputs);
        self.pass(&tok, &[b"workflow", b"run"], &v)
    }

    // --- branches -----------------------------------------------------------

    fn remote_sha(&self, tok: &[u8], br: &[u8]) -> Option<Vec<u8>> {
        let path = cat(&[b"repos/{owner}/{repo}/git/ref/heads/", br]);
        let (st, o) = self.gh(
            tok,
            &[b"api", &path, b"--jq", b".object.sha"],
            Io::Capture,
            Io::Null,
        );
        if st != 0 {
            return None;
        }
        let sha = sh::subst(o);
        if sha.len() == 40 && sha.iter().all(|c| matches!(c, b'0'..=b'9' | b'a'..=b'f')) {
            Some(sha)
        } else {
            None
        }
    }

    fn branch_delete(&self, args: &[Vec<u8>]) -> Res {
        let usage = "branch-delete [--agent <agent>] <branch>...";
        let (agent, rest) =
            take_agent(args).ok_or_else(|| die(&cat(&[b"usage: ", usage.as_bytes()])))?;
        need_target("branch", usage, arg(rest, 0))?;
        if !sh::is_readable(&self.landed) {
            return Err(die(&cat(&[
                b"cannot read ",
                &self.landed,
                b"; nothing was deleted",
            ])));
        }
        let tok = self.mint_token(&agent, b"nothing was deleted")?;
        to_caller_dir()?;
        let mut kept = 0;
        let keep = |kept: &mut i32, br: &[u8], why: &[u8]| {
            err(&cat(&[b"kept ", br, b": ", why, b"\n"]));
            *kept += 1;
        };
        for br in rest {
            let br = br.as_slice();
            if !plain_branch_name(br) {
                keep(&mut kept, br, b"not a plain branch name");
                continue;
            }
            if matches!(br, b"main" | b"master" | b"HEAD") {
                keep(&mut kept, br, b"never deleted");
                continue;
            }
            let (ost, o) = self.gh(
                &tok,
                &[
                    b"pr",
                    b"list",
                    b"--head",
                    br,
                    b"--state",
                    b"open",
                    b"--json",
                    b"number",
                    b"--jq",
                    b".[].number",
                ],
                Io::Capture,
                Io::Inherit,
            );
            if ost != 0 {
                keep(
                    &mut kept,
                    br,
                    b"could not ask GitHub for its open pull requests",
                );
                continue;
            }
            let open = sh::subst(o);
            if !open.is_empty() {
                let list: Vec<u8> = open
                    .split(|&c| c == b'\n')
                    .collect::<Vec<_>>()
                    .join(&b", #"[..]);
                let first = open.split(|&c| c == b'\n').next().unwrap_or(b"");
                keep(
                    &mut kept,
                    br,
                    &cat(&[
                        b"PR #",
                        &list,
                        b" is open on it; to close it and delete the branch: pr-close ",
                        first,
                        b" --delete-branch",
                    ]),
                );
                continue;
            }
            let sha: Vec<u8>;
            if let Some(pr) = queue_pr(br) {
                let (_, o) = self.gh(
                    &tok,
                    &[b"pr", b"view", &pr, b"--json", b"state", b"--jq", b".state"],
                    Io::Capture,
                    Io::Null,
                );
                let state = sh::subst(o);
                if !matches!(state.as_slice(), b"MERGED" | b"CLOSED") {
                    let shown: &[u8] = if state.is_empty() {
                        b"unreadable"
                    } else {
                        &state
                    };
                    keep(
                        &mut kept,
                        br,
                        &cat(&[
                            b"the merge-queue branch of PR #",
                            &pr,
                            b", which is ",
                            shown,
                        ]),
                    );
                    continue;
                }
                match self.remote_sha(&tok, br) {
                    Some(x) => sha = x,
                    None => {
                        keep(&mut kept, br, b"could not read its SHA on GitHub");
                        continue;
                    }
                }
            } else {
                let mut c = Command::new("bash");
                c.arg(sh::os(&self.landed))
                    .arg("--remote-branch")
                    .arg(sh::os(br))
                    .env("GH_TOKEN", sh::os(&tok))
                    .env("GITHUB_TOKEN", "");
                let (gst, gate) = run_merged(line::LANDED, c);
                if gst != 0 {
                    let gate = sh::subst(gate);
                    keep(&mut kept, br, b"not landed");
                    let mut ind = b"    ".to_vec();
                    for &ch in &gate {
                        ind.push(ch);
                        if ch == b'\n' {
                            ind.extend_from_slice(b"    ");
                        }
                    }
                    ind.push(b'\n');
                    err(&ind);
                    continue;
                }
                let mut c = Command::new("git");
                c.args(["rev-parse", "--verify", "-q"]).arg(sh::os(&cat(&[
                    b"refs/remotes/origin/",
                    br,
                    b"^{commit}",
                ])));
                let (_, o) = run(line::GIT_SHA, &mut c, Io::Capture, Io::Inherit);
                sha = sh::subst(o);
            }
            let now = match self.remote_sha(&tok, br) {
                Some(x) => x,
                None => {
                    keep(&mut kept, br, b"could not read its SHA on GitHub");
                    continue;
                }
            };
            if sha.is_empty() || now != sha {
                keep(
                    &mut kept,
                    br,
                    &cat(&[
                        b"it moved since it was checked (",
                        &sha[..sha.len().min(8)],
                        b" -> ",
                        &now[..now.len().min(8)],
                        b"); run again",
                    ]),
                );
                continue;
            }
            let path = cat(&[b"repos/{owner}/{repo}/git/refs/heads/", br]);
            let (dst, _) = self.gh(
                &tok,
                &[b"api", b"-X", b"DELETE", &path],
                Io::Null,
                Io::Inherit,
            );
            if dst == 0 {
                out(&cat(&[
                    b"deleted ",
                    br,
                    b" (",
                    &sha[..sha.len().min(8)],
                    b")\n",
                ]));
            } else {
                keep(&mut kept, br, b"GitHub refused the delete");
            }
        }
        if kept != 0 {
            return Err(die(
                format!("{} branch(es) kept; see above", kept).as_bytes()
            ));
        }
        Ok(())
    }

    // --- issues -------------------------------------------------------------

    fn issue_create(&self, args: &[Vec<u8>]) -> Res {
        let usage = "issue-create [--agent <agent>] --title <s> --body-file <f> | --body <s> [gh issue create args]";
        let (agent, rest) =
            take_agent(args).ok_or_else(|| die(&cat(&[b"usage: ", usage.as_bytes()])))?;
        issue_args_ok(usage, rest)?;
        let titled = rest.iter().any(|a| {
            let a = a.as_slice();
            a == b"--title"
                || a.starts_with(b"--title=")
                || a == b"-t"
                || (a.starts_with(b"-t") && a.len() > 2)
        });
        if !titled {
            return Err(die(&cat(&[
                b"usage: ",
                usage.as_bytes(),
                b"   (give the title: without it gh prompts)",
            ])));
        }
        if !has_body(rest) {
            return Err(die(&cat(&[
                b"usage: ",
                usage.as_bytes(),
                b"   (give the body: without it gh waits for an editor)",
            ])));
        }
        let tok = self.mint_token(&agent, b"the issue was NOT opened")?;
        to_caller_dir()?;
        self.pass(&tok, &[b"issue", b"create"], rest)
    }

    fn issue_comment(&self, args: &[Vec<u8>]) -> Res {
        let usage = "issue-comment [--agent <agent>] <issue> --body-file <f> | --body <s>";
        let (agent, rest) =
            take_agent(args).ok_or_else(|| die(&cat(&[b"usage: ", usage.as_bytes()])))?;
        need_target("issue", usage, arg(rest, 0))?;
        issue_args_ok(usage, rest)?;
        if !has_body(rest.get(1..).unwrap_or(&[])) {
            return Err(die(&cat(&[
                b"usage: ",
                usage.as_bytes(),
                b"   (give the body: without it gh waits for an editor)",
            ])));
        }
        let tok = self.mint_token(&agent, b"the comment was NOT posted")?;
        to_caller_dir()?;
        self.pass(&tok, &[b"issue", b"comment"], rest)
    }

    fn issue_close(&self, args: &[Vec<u8>]) -> Res {
        let usage = "issue-close [--agent <agent>] <issue> [--comment <s>] [--reason completed|\"not planned\"]";
        let (agent, rest) =
            take_agent(args).ok_or_else(|| die(&cat(&[b"usage: ", usage.as_bytes()])))?;
        need_target("issue", usage, arg(rest, 0))?;
        issue_args_ok(usage, rest)?;
        let tok = self.mint_token(&agent, b"the issue was NOT closed")?;
        to_caller_dir()?;
        self.pass(&tok, &[b"issue", b"close"], rest)
    }

    /// `main`: the exit status.
    pub fn main(&self, args: &[Vec<u8>]) -> i32 {
        let cmd = arg(args, 0).to_vec();
        if cmd.is_empty() {
            return usage(1);
        }
        let rest = &args[1..];
        let r = match cmd.as_slice() {
            b"convert" => self.convert(rest),
            b"installations" => self.installations(rest),
            b"repos" => self.repos(rest),
            b"token" => {
                let (o, st) = self.token(arg(rest, 0), arg(rest, 1), arg(rest, 2));
                out(&o);
                status(st)
            }
            b"login" => {
                let (o, st) = self.login(arg(rest, 0));
                out(&o);
                status(st)
            }
            b"env" => self.env(rest),
            b"pr-create" => self.pr_create(rest),
            b"pr-edit" => self.pr_passthrough(
                b"edit",
                "pr-edit [--agent <agent>] <pr> [gh pr edit args]",
                rest,
            ),
            b"pr-comment" => self.pr_comment(rest),
            b"pr-review" => self.pr_review(rest),
            b"pr-ready" => self.pr_passthrough(
                b"ready",
                "pr-ready [--agent <agent>] <pr> [gh pr ready args]",
                rest,
            ),
            b"pr-close" => self.pr_passthrough(
                b"close",
                "pr-close [--agent <agent>] <pr> [--comment <s>] [--delete-branch]",
                rest,
            ),
            b"pr-enqueue" => self.pr_enqueue(rest),
            b"pr-hold" => self.pr_hold(rest),
            b"pr-unhold" => self.pr_unhold(rest),
            b"run-rerun" => self.run_passthrough(
                b"rerun",
                "run-rerun [--agent <agent>] <run-id> [--failed] [--job <id>]",
                b"the run was NOT re-run",
                rest,
            ),
            b"run-cancel" => self.run_passthrough(
                b"cancel",
                "run-cancel [--agent <agent>] <run-id>",
                b"the run was NOT cancelled",
                rest,
            ),
            b"workflow-run" => self.workflow_run(rest),
            b"issue-create" => self.issue_create(rest),
            b"issue-comment" => self.issue_comment(rest),
            b"issue-close" => self.issue_close(rest),
            b"branch-delete" => self.branch_delete(rest),
            b"-h" | b"--help" | b"help" => return usage(0),
            _ => Err(die(&cat(&[b"unknown command: ", &cmd, b" (try --help)"]))),
        };
        match r {
            Ok(()) => 0,
            Err(code) => code,
        }
    }
}

fn status(st: i32) -> Res {
    if st == 0 {
        Ok(())
    } else {
        Err(st)
    }
}

fn arg(args: &[Vec<u8>], i: usize) -> &[u8] {
    args.get(i).map(Vec::as_slice).unwrap_or(b"")
}

fn first_line(b: &[u8]) -> &[u8] {
    match b.iter().position(|&c| c == b'\n') {
        Some(i) => &b[..i],
        None => b,
    }
}

/// `read -r v1 v2 v3 v4 v5 <<<"$st"`.
fn read5(st: &[u8]) -> Vec<Vec<u8>> {
    sh::read_fields(first_line(st), b" \t\n", 5)
}

/// The value of `$((NAME))` for a number as the environment gives it: a
/// decimal, 0x hex or 0 octal integer; anything else is taken as 0.
pub fn arith(v: &[u8]) -> i64 {
    let t = std::str::from_utf8(v).unwrap_or("").trim();
    let (neg, t) = match t.strip_prefix('-') {
        Some(r) => (true, r),
        None => (false, t.strip_prefix('+').unwrap_or(t)),
    };
    let n = if let Some(h) = t.strip_prefix("0x").or_else(|| t.strip_prefix("0X")) {
        i64::from_str_radix(h, 16).unwrap_or(0)
    } else if t.len() > 1 && t.starts_with('0') {
        i64::from_str_radix(&t[1..], 8).unwrap_or(0)
    } else {
        t.parse::<i64>().unwrap_or(0)
    };
    if neg {
        -n
    } else {
        n
    }
}

/// `[ "$i" -lt "$tries" ]` (a non-number is not less).
fn test_lt(i: i64, tries: &[u8]) -> bool {
    match std::str::from_utf8(tries)
        .ok()
        .and_then(|t| t.trim().parse::<i64>().ok())
    {
        Some(t) => i < t,
        None => false,
    }
}

fn usage(code: i32) -> i32 {
    out(USAGE.as_bytes());
    code
}

/// `take_agent`: (the agent, the arguments after `--agent <agent>`), or None
/// for a `--agent` without a name.
pub fn take_agent(args: &[Vec<u8>]) -> Option<(Vec<u8>, &[Vec<u8>])> {
    if arg(args, 0) == b"--agent" {
        let a = arg(args, 1);
        if a.is_empty() {
            return None;
        }
        return Some((a.to_vec(), &args[2..]));
    }
    Some((sh::env_or("AGENT_APP_AGENT", b"wren"), args))
}

/// `need_target`: a target that is there and is not a flag.
pub fn need_target(what: &str, usage: &str, target: &[u8]) -> Result<(), Refusal> {
    if !target.is_empty() && !target.starts_with(b"-") {
        return Ok(());
    }
    Err(refuse(&[
        b"usage: ",
        usage.as_bytes(),
        b"   (missing <",
        what.as_bytes(),
        b">)",
    ]))
}

/// pr-create: did the caller already pass the fast-lane label?
pub fn has_fast_lane(args: &[Vec<u8>]) -> bool {
    let mut has = false;
    let mut prev: &[u8] = b"";
    for a in args {
        let a = a.as_slice();
        let mut labels: &[u8] = b"";
        if prev == b"--label" || prev == b"-l" {
            labels = a;
        }
        if let Some(r) = a.strip_prefix(b"--label=") {
            labels = r;
        } else if a.starts_with(b"-l") && a.len() > 2 {
            labels = &a[2..];
        }
        if !labels.is_empty() {
            let squeezed: Vec<u8> = labels.iter().copied().filter(|&c| c != b' ').collect();
            let hay = cat(&[b",", &squeezed, b","]);
            let needle = cat(&[b",", FAST_LANE_LABEL.as_bytes(), b","]);
            if sh::contains(&hay, &needle) {
                has = true;
            }
        }
        prev = a;
    }
    has
}

/// `has_body`: do these arguments give gh a body?
pub fn has_body(args: &[Vec<u8>]) -> bool {
    args.iter().any(|a| {
        let a = a.as_slice();
        a == b"--body"
            || a.starts_with(b"--body=")
            || a == b"-b"
            || (a.starts_with(b"-b") && a.len() > 2)
            || a == b"--body-file"
            || a.starts_with(b"--body-file=")
            || a == b"-F"
            || (a.starts_with(b"-F") && a.len() > 2)
    })
}

/// pr-review's checks on what follows the PR.
pub fn review_args(usage: &str, args: &[Vec<u8>]) -> Result<(), Refusal> {
    let browser = |a: &[u8]| {
        refuse(&[
            b"refusing ",
            a,
            b": it opens a browser and waits; usage: ",
            usage.as_bytes(),
        ])
    };
    let mut value_for = false;
    let (mut actions, mut need_body, mut body) = (0, false, false);
    for a in args {
        let a = a.as_slice();
        if value_for {
            value_for = false;
            continue;
        }
        if a == b"--approve" || a.starts_with(b"--approve=") {
            actions += 1;
        } else if a == b"--comment"
            || a.starts_with(b"--comment=")
            || a == b"--request-changes"
            || a.starts_with(b"--request-changes=")
        {
            actions += 1;
            need_body = true;
        } else if a == b"--body" || a == b"--body-file" {
            body = true;
            value_for = true;
        } else if a.starts_with(b"--body=") || a.starts_with(b"--body-file=") {
            body = true;
        } else if a == b"--repo" {
            value_for = true;
        } else if a.starts_with(b"--repo=") {
        } else if a == b"--web" || a.starts_with(b"--web=") {
            return Err(browser(a));
        } else if a.starts_with(b"--") {
        } else if a.starts_with(b"-") && a.len() >= 2 {
            for i in 1..a.len() {
                match a[i] {
                    b'a' => actions += 1,
                    b'c' | b'r' => {
                        actions += 1;
                        need_body = true;
                    }
                    b'b' | b'F' => {
                        body = true;
                        if i + 1 >= a.len() {
                            value_for = true;
                        }
                        break;
                    }
                    b'R' => {
                        if i + 1 >= a.len() {
                            value_for = true;
                        }
                        break;
                    }
                    b'w' => return Err(browser(a)),
                    _ => {}
                }
            }
        }
    }
    let u = usage.as_bytes();
    if value_for {
        return Err(refuse(&[b"usage: ", u]));
    }
    if actions != 1 {
        return Err(refuse(&[
            b"usage: ",
            u,
            b"   (pass one of --approve, --comment or --request-changes: without it gh prompts)",
        ]));
    }
    if need_body && !body {
        return Err(refuse(&[
            b"usage: ",
            u,
            b"   (give the body with --body or --body-file: without it gh waits for an editor)",
        ]));
    }
    Ok(())
}

/// What pr-enqueue reads from its arguments.
#[derive(Debug, Default, PartialEq)]
pub struct Enqueue {
    pub auto: bool,
    pub method: bool,
    pub repo: Option<Vec<u8>>,
}

/// pr-enqueue's checks: never --admin, never off, never a merge commit or a
/// rebase; whether --auto and a method were given, and any --repo.
pub fn enqueue_args(args: &[Vec<u8>]) -> Result<Enqueue, Refusal> {
    #[derive(PartialEq)]
    enum V {
        No,
        Repo,
        Other,
    }
    let mut e = Enqueue::default();
    let mut value_for = V::No;
    for a in args {
        let a = a.as_slice();
        if value_for != V::No {
            if value_for == V::Repo {
                e.repo = Some(a.to_vec());
            }
            value_for = V::No;
            continue;
        }
        if a == b"--admin" || a.starts_with(b"--admin=") {
            return Err(refuse(&[b"refusing --admin: it merges past the merge queue. That is the maintainer's break-glass, not an agent's; nothing was run"]));
        } else if a == b"--disable-auto" || a.starts_with(b"--disable-auto=") {
            return Err(refuse(&[b"--disable-auto turns auto-merge OFF; pr-enqueue only turns it on (to hold a PR: pr-hold). Nothing was run"]));
        } else if a == b"--merge"
            || a.starts_with(b"--merge=")
            || a == b"--rebase"
            || a.starts_with(b"--rebase=")
        {
            return Err(refuse(&[
                b"refusing ",
                a,
                b": main's ruleset allows only squash merges; nothing was run",
            ]));
        } else if a == b"--auto" || a.starts_with(b"--auto=") {
            e.auto = true;
        } else if a == b"--squash" || a.starts_with(b"--squash=") {
            e.method = true;
        } else if a == b"--repo" {
            value_for = V::Repo;
        } else if let Some(r) = a.strip_prefix(b"--repo=") {
            e.repo = Some(r.to_vec());
        } else if matches!(
            a,
            b"--body" | b"--body-file" | b"--subject" | b"--author-email" | b"--match-head-commit"
        ) {
            value_for = V::Other;
        } else if a.starts_with(b"--") {
        } else if a.starts_with(b"-") && a.len() >= 2 {
            for i in 1..a.len() {
                match a[i] {
                    b'm' | b'r' => {
                        return Err(refuse(&[
                            b"refusing ",
                            a,
                            b": it asks for a merge commit or a rebase, and main's ruleset allows only squash merges; nothing was run",
                        ]))
                    }
                    b's' => e.method = true,
                    b'R' => {
                        if i + 1 < a.len() {
                            e.repo = Some(a[i + 1..].to_vec());
                        } else {
                            value_for = V::Repo;
                        }
                        break;
                    }
                    b'b' | b't' | b'A' | b'F' => {
                        if i + 1 >= a.len() {
                            value_for = V::Other;
                        }
                        break;
                    }
                    _ => {}
                }
            }
        }
    }
    Ok(e)
}

/// What pr-hold and pr-unhold take after the PR.
#[derive(Debug, Default, PartialEq)]
pub struct Hold {
    pub reason: Vec<u8>,
    pub repo: Option<Vec<u8>>,
}

pub fn hold_args(usage: &str, allow_reason: bool, args: &[Vec<u8>]) -> Result<Hold, Refusal> {
    let u = usage.as_bytes();
    let mut h = Hold::default();
    let mut i = 0;
    while i < args.len() {
        let a = args[i].as_slice();
        if a == b"--reason" || a.starts_with(b"--reason=") {
            if !allow_reason {
                return Err(refuse(&[b"usage: ", u, b"   (unexpected '", a, b"')"]));
            }
            if a == b"--reason" {
                if i + 1 >= args.len() {
                    return Err(refuse(&[b"usage: ", u]));
                }
                h.reason = args[i + 1].clone();
                i += 1;
            } else {
                h.reason = a[b"--reason=".len()..].to_vec();
            }
        } else if a == b"-R" || a == b"--repo" {
            if i + 1 >= args.len() {
                return Err(refuse(&[b"usage: ", u]));
            }
            h.repo = Some(args[i + 1].clone());
            i += 1;
        } else if let Some(r) = a.strip_prefix(b"--repo=") {
            h.repo = Some(r.to_vec());
        } else {
            return Err(refuse(&[b"usage: ", u, b"   (unexpected '", a, b"')"]));
        }
        i += 1;
    }
    Ok(h)
}

/// `issue_args_ok`: no --repo, no --web.
pub fn issue_args_ok(usage: &str, args: &[Vec<u8>]) -> Result<(), Refusal> {
    for a in args {
        let a = a.as_slice();
        if a == b"-R" || a.starts_with(b"-R") || a == b"--repo" || a.starts_with(b"--repo=") {
            return Err(refuse(&[
                b"refusing ",
                a,
                b": issues in this repository only; nothing was changed",
            ]));
        }
        if a == b"-w" || a == b"--web" {
            return Err(refuse(&[
                b"refusing ",
                a,
                b": it opens a browser and waits; usage: ",
                usage.as_bytes(),
            ]));
        }
    }
    Ok(())
}

/// workflow-run's checks on what follows the workflow: inputs and --ref
/// main, nothing else.
pub fn workflow_args(usage: &str, args: &[Vec<u8>]) -> Result<(), Refusal> {
    let u = usage.as_bytes();
    let mut i = 0;
    while i < args.len() {
        let a = args[i].as_slice();
        if matches!(a, b"-f" | b"-F" | b"--raw-field" | b"--field") {
            if i + 1 >= args.len() {
                return Err(refuse(&[b"usage: ", u]));
            }
            i += 1;
        } else if (a.starts_with(b"-f") && a.len() > 2)
            || (a.starts_with(b"-F") && a.len() > 2)
            || a.starts_with(b"--raw-field=")
            || a.starts_with(b"--field=")
        {
        } else if a == b"--ref"
            || a == b"-r"
            || a.starts_with(b"--ref=")
            || (a.starts_with(b"-r") && a.len() > 2)
        {
            let r: Vec<u8> = if a == b"--ref" || a == b"-r" {
                if i + 1 >= args.len() {
                    return Err(refuse(&[b"usage: ", u]));
                }
                i += 1;
                args[i].clone()
            } else if let Some(r) = a.strip_prefix(b"--ref=") {
                r.to_vec()
            } else {
                a[2..].to_vec()
            };
            if r.as_slice() != b"main" {
                return Err(refuse(&[
                    b"refusing --ref ",
                    &r,
                    b": another ref runs that branch's copy of the workflow. Only main; nothing was run",
                ]));
            }
        } else if a == b"-R" || a.starts_with(b"-R") || a == b"--repo" || a.starts_with(b"--repo=")
        {
            return Err(refuse(&[
                b"refusing ",
                a,
                b": workflow-run starts workflows in this repository only; nothing was run",
            ]));
        } else {
            return Err(refuse(&[b"usage: ", u, b"   (unexpected '", a, b"')"]));
        }
        i += 1;
    }
    Ok(())
}

/// `awk '!/^#/ && NF {print $1}'` over the allowlist, as `$(...)` keeps it.
pub fn allowlist(data: &[u8]) -> Vec<u8> {
    let mut o = Vec::new();
    for l in sh::lines(data) {
        if l.starts_with(b"#") {
            continue;
        }
        if let Some(w) = l
            .split(|&c| c == b' ' || c == b'\t')
            .find(|w| !w.is_empty())
        {
            o.extend_from_slice(w);
            o.push(b'\n');
        }
    }
    sh::subst(o)
}

/// `grep -qxF -- "$wf" <<<"$allowed"`: a line of the workflow name (each
/// line of it is a pattern) is a whole line of the list.
pub fn allowed_has(allowed: &[u8], wf: &[u8]) -> bool {
    let lines: Vec<&[u8]> = allowed.split(|&c| c == b'\n').collect();
    wf.split(|&c| c == b'\n')
        .any(|p| lines.iter().any(|l| *l == p))
}

/// `[[ "$br" =~ ^[A-Za-z0-9._][A-Za-z0-9._/-]*$ ]]`, not refs/..., no "..".
pub fn plain_branch_name(br: &[u8]) -> bool {
    let ok_first = |c: u8| c.is_ascii_alphanumeric() || c == b'.' || c == b'_';
    let ok = |c: u8| ok_first(c) || c == b'/' || c == b'-';
    match br.split_first() {
        Some((&f, rest)) if ok_first(f) && rest.iter().all(|&c| ok(c)) => {}
        _ => return false,
    }
    !br.starts_with(b"refs/") && !sh::contains(br, b"..")
}

/// `^gh-readonly-queue/[^/]+/pr-([0-9]+)-`: the PR a merge-queue branch is for.
pub fn queue_pr(br: &[u8]) -> Option<Vec<u8>> {
    let r = br.strip_prefix(b"gh-readonly-queue/")?;
    let slash = r.iter().position(|&c| c == b'/')?;
    if slash == 0 {
        return None;
    }
    let r = r[slash..].strip_prefix(b"/pr-")?;
    let n = r.iter().take_while(|c| c.is_ascii_digit()).count();
    if n == 0 || r.get(n) != Some(&b'-') {
        return None;
    }
    Some(r[..n].to_vec())
}

/// `to_caller_dir`.
fn to_caller_dir() -> Res {
    let d = sh::env_or("BUILD_WORKING_DIRECTORY", b".");
    if let Err(e) = std::env::set_current_dir(sh::path(&d)) {
        let prog = std::env::args_os()
            .next()
            .map(|a| a.as_bytes().to_vec())
            .unwrap_or_default();
        err(&cat(&[
            &prog,
            format!(": line {}: cd: ", line::CD).as_bytes(),
            &d,
            b": ",
            sh::strerror(&e).as_bytes(),
            b"\n",
        ]));
        return Err(die(&cat(&[b"cannot enter ", &d])));
    }
    Ok(())
}

/// The program: argv in, exit status out.
pub fn run_main() -> i32 {
    let argv = sh::args();
    let argv0 = std::env::args_os()
        .next()
        .map(|a| a.as_bytes().to_vec())
        .unwrap_or_default();
    let tool = Tool::new(&argv0);
    let code = tool.main(&argv);
    let _ = std::io::stdout().flush();
    code
}
