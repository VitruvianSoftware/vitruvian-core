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

//! sync, the Rust port of main.go: run the pinned Copybara image for one
//! component, retrying the bidirectional import on a concurrent race.
//!
//!   sync <export|import> <component> [--options "<opts>"]
//!   sync import_pr <component> <pr-number> [--options "<opts>"]
//!
//! Docker invocations, output and exit codes are the Go tool's, byte for
//! byte; arguments and environment values are handled as raw bytes.

use std::ffi::{OsStr, OsString};
use std::io::Write;
use std::os::unix::ffi::{OsStrExt, OsStringExt};
use std::os::unix::fs::OpenOptionsExt;
use std::os::unix::process::ExitStatusExt;
use std::process::Stdio;

pub mod goexec;
pub mod gostr;
mod unicode_tables;

pub const PINNED_IMAGE: &[u8] =
    b"olivr/copybara@sha256:87e2e9089344e64693faebb2ee0ed33b8797358c0420b0fa98325ca611e98679";
pub const DEFAULT_OPTIONS: &[u8] = b"--ignore-noop";
pub const MAX_ATTEMPTS: i32 = 3;

/// How the sync logic invokes Docker. Ok is docker's exit code; Err is the
/// text Go's error would print.
pub trait Runner {
    fn run(&mut self, image: &[u8], docker_args: &[Vec<u8>]) -> Result<i32, Vec<u8>>;
}

/// `docker run <args> <image> copybara`, sharing this process's stdout and
/// stderr (stdin is /dev/null, as exec.Cmd leaves it).
pub struct DockerRunner;

impl Runner for DockerRunner {
    fn run(&mut self, image: &[u8], docker_args: &[Vec<u8>]) -> Result<i32, Vec<u8>> {
        let mut args = vec![b"run".to_vec()];
        args.extend(docker_args.iter().cloned());
        args.push(image.to_vec());
        args.push(b"copybara".to_vec());
        let mut cmd = goexec::command(b"docker", &args).map_err(|e| e.go_string())?;
        let _ = std::io::stdout().flush();
        let status = cmd
            .stdin(Stdio::null())
            .stdout(Stdio::inherit())
            .stderr(Stdio::inherit())
            .status();
        match status {
            Ok(s) => Ok(match s.code() {
                Some(c) => c,
                None => {
                    let _ = s.signal();
                    -1
                }
            }),
            Err(e) => {
                let path = goexec::look_path(b"docker").unwrap_or_else(|_| b"docker".to_vec());
                Err(goexec::ExecError::Start {
                    path,
                    errno: e.raw_os_error().unwrap_or(0),
                }
                .go_string())
            }
        }
    }
}

/// ("import", "mcp-slack") -> "import_mcp_slack".
pub fn workflow_name(direction: &[u8], component: &[u8]) -> Vec<u8> {
    let mut s = direction.to_vec();
    s.push(b'_');
    s.extend(component.iter().map(|&b| if b == b'-' { b'_' } else { b }));
    s
}

/// Exit codes 0 and 4 (Copybara's NO_OP) are success.
pub fn is_success(code: i32) -> bool {
    code == 0 || code == 4
}

fn getenv(name: &str) -> Vec<u8> {
    std::env::var_os(name)
        .map(|v| v.into_vec())
        .unwrap_or_default()
}

fn same_file(a: &std::fs::Metadata, b: &std::fs::Metadata) -> bool {
    use std::os::unix::fs::MetadataExt;
    a.dev() == b.dev() && a.ino() == b.ino()
}

/// os.Getwd: $PWD when it names the current directory, else getcwd(3).
fn getwd() -> Option<Vec<u8>> {
    let pwd = getenv("PWD");
    if pwd.first() == Some(&b'/') {
        let dot = std::fs::metadata(".").ok()?;
        if let Ok(d) = std::fs::metadata(OsStr::from_bytes(&pwd)) {
            if same_file(&dot, &d) {
                return Some(pwd);
            }
        }
    }
    std::env::current_dir()
        .ok()
        .map(|p| p.into_os_string().into_vec())
}

/// BUILD_WORKSPACE_DIRECTORY (set by `bazel run`), then GITHUB_WORKSPACE,
/// then the current directory ("." if that cannot be read).
pub fn resolve_workspace() -> Vec<u8> {
    let v = getenv("BUILD_WORKSPACE_DIRECTORY");
    if !v.is_empty() {
        return v;
    }
    let v = getenv("GITHUB_WORKSPACE");
    if !v.is_empty() {
        return v;
    }
    getwd().unwrap_or_else(|| b".".to_vec())
}

fn cat(parts: &[&[u8]]) -> Vec<u8> {
    parts.concat()
}

fn put(w: &mut dyn Write, parts: &[&[u8]]) {
    for p in parts {
        let _ = w.write_all(p);
    }
    let _ = w.flush();
}

/// The `--options` scan main.go does: every "--options" at index >= from
/// that has a following argument sets the options; the last one wins.
fn parse_options(args: &[Vec<u8>], from: usize) -> Vec<u8> {
    let mut options = DEFAULT_OPTIONS.to_vec();
    let mut i = from;
    while i + 1 < args.len() {
        if args[i] == b"--options" {
            options = args[i + 1].clone();
        }
        i += 1;
    }
    options
}

/// The testable core: args are the command line after the program name;
/// sleeper is called with the backoff in seconds. Returns the exit code.
pub fn run(
    args: &[Vec<u8>],
    r: &mut dyn Runner,
    sleeper: &mut dyn FnMut(i32),
    out: &mut dyn Write,
    err: &mut dyn Write,
) -> i32 {
    if args.len() < 2 {
        put(
            err,
            &[b"usage: sync <export|import> <component> [--options \"<opts>\"]\n"],
        );
        put(
            err,
            &[b"       sync import_pr <component> <pr-number> [--options \"<opts>\"]\n"],
        );
        return 2;
    }
    let direction = &args[0][..];
    let component = &args[1][..];

    if direction == b"import_pr" {
        return run_import_pr(args, component, r, out, err);
    }

    let options = parse_options(args, 2);

    if direction != b"export" && direction != b"import" {
        put(
            err,
            &[b"unknown direction: ", direction, b" (use export|import)\n"],
        );
        return 2;
    }

    let wf = workflow_name(direction, component);
    let workspace = resolve_workspace();
    let home = getenv("HOME");

    let docker_args: Vec<Vec<u8>> = vec![
        b"--rm".to_vec(),
        b"-v".to_vec(),
        cat(&[&workspace, b":/usr/src/app"]),
        b"-v".to_vec(),
        cat(&[&home, b"/.ssh/id_rsa:/root/.ssh/id_rsa"]),
        b"-v".to_vec(),
        cat(&[&home, b"/.ssh/known_hosts:/root/.ssh/known_hosts"]),
        b"-v".to_vec(),
        cat(&[
            &workspace,
            b"/tools/copybara/copy.bara.sky:/root/copy.bara.sky",
        ]),
        b"-v".to_vec(),
        cat(&[&home, b"/.git-credentials:/root/.git-credentials"]),
        b"-v".to_vec(),
        cat(&[&home, b"/.gitconfig:/root/.gitconfig"]),
        b"-e".to_vec(),
        b"COPYBARA_CONFIG=/root/copy.bara.sky".to_vec(),
        b"-e".to_vec(),
        cat(&[b"COPYBARA_WORKFLOW=", &wf]),
        b"-e".to_vec(),
        cat(&[b"COPYBARA_OPTIONS=", &options]),
    ];

    let mut attempt = 1;
    loop {
        let exit_code = match r.run(PINNED_IMAGE, &docker_args) {
            Ok(c) => c,
            Err(e) => {
                put(err, &[b"docker error: ", &e, b"\n"]);
                return 1;
            }
        };

        if is_success(exit_code) {
            put(
                out,
                &[format!("Copybara OK (exit {exit_code}; 4 = no-op/up-to-date)\n").as_bytes()],
            );
            return 0;
        }

        if direction != b"import" || attempt >= MAX_ATTEMPTS {
            put(
                err,
                &[format!("Copybara failed (exit {exit_code}").as_bytes()],
            );
            if direction == b"import" && attempt >= MAX_ATTEMPTS {
                put(err, &[format!(" after {MAX_ATTEMPTS} attempts").as_bytes()]);
            }
            put(err, &[b")\n"]);
            return exit_code;
        }

        attempt += 1;
        put(
            out,
            &[format!(
                "Copybara exit {exit_code} (attempt {}/{MAX_ATTEMPTS}) — retrying after re-fetch (likely a concurrent import race)\n",
                attempt - 1
            )
            .as_bytes()],
        );
        sleeper(attempt * 5);
    }
}

/// Whether s is a non-empty run of ASCII digits.
pub fn is_digits(s: &[u8]) -> bool {
    !s.is_empty() && s.iter().all(u8::is_ascii_digit)
}

/// Go's *fs.PathError text: "<op> <path>: <errno text>".
fn path_error(op: &str, path: &[u8], e: &std::io::Error) -> Vec<u8> {
    cat(&[
        op.as_bytes(),
        b" ",
        path,
        b": ",
        goexec::errno_string(e.raw_os_error().unwrap_or(0)).as_bytes(),
    ])
}

/// os.ReadFile, with Go's error text.
fn read_file(path: &[u8]) -> Result<Vec<u8>, Vec<u8>> {
    use std::io::Read;
    let mut f =
        std::fs::File::open(OsStr::from_bytes(path)).map_err(|e| path_error("open", path, &e))?;
    let mut data = Vec::new();
    f.read_to_end(&mut data)
        .map_err(|e| path_error("read", path, &e))?;
    Ok(data)
}

/// A small xorshift seeded from the clock and pid: CreateTemp only needs
/// names unlikely to collide, and retries on a collision.
fn next_random(state: &mut u64) -> u32 {
    if *state == 0 {
        let t = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos() as u64)
            .unwrap_or(1);
        *state = t ^ ((std::process::id() as u64) << 32) | 1;
    }
    let mut x = *state;
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    *state = x;
    (x >> 32) as u32
}

/// os.CreateTemp("", "copy.bara.*.sky") with `data` written to it: the path,
/// or Go's error text.
fn create_temp(data: &[u8]) -> Result<Vec<u8>, Vec<u8>> {
    let mut dir = getenv("TMPDIR");
    if dir.is_empty() {
        dir = b"/tmp".to_vec();
    }
    let mut prefix = dir.clone();
    if prefix.last() != Some(&b'/') {
        prefix.push(b'/');
    }
    prefix.extend_from_slice(b"copy.bara.");
    let suffix: &[u8] = b".sky";
    let mut state = 0u64;
    let mut tries = 0;
    loop {
        let name = cat(&[
            &prefix,
            next_random(&mut state).to_string().as_bytes(),
            suffix,
        ]);
        let opened = std::fs::OpenOptions::new()
            .read(true)
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(OsStr::from_bytes(&name));
        match opened {
            Ok(mut f) => {
                if let Err(e) = f.write_all(data) {
                    let _ = std::fs::remove_file(OsStr::from_bytes(&name));
                    return Err(path_error("write", &name, &e));
                }
                return Ok(name);
            }
            Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => {
                tries += 1;
                if tries >= 10000 {
                    return Err(cat(&[
                        b"createtemp ",
                        &prefix,
                        b"*",
                        suffix,
                        b": file already exists",
                    ]));
                }
            }
            Err(e) => return Err(path_error("open", &name, &e)),
        }
    }
}

fn replace_all(s: &[u8], from: &[u8], to: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(s.len());
    let mut i = 0;
    while i < s.len() {
        if s[i..].starts_with(from) {
            out.extend_from_slice(to);
            i += from.len();
        } else {
            out.push(s[i]);
            i += 1;
        }
    }
    out
}

/// A throwaway copy of copy.bara.sky with @@PR_NUMBER@@ replaced by the PR
/// number; the caller removes it. Err is the text main.go prints after
/// "import_pr: ".
pub fn resolve_import_pr_config(workspace: &[u8], pr_number: &[u8]) -> Result<Vec<u8>, Vec<u8>> {
    let src = gostr::join(&[workspace, b"tools", b"copybara", b"copy.bara.sky"]);
    let data = read_file(&src).map_err(|e| cat(&[b"read ", &src, b": ", &e]))?;
    let resolved = replace_all(&data, b"@@PR_NUMBER@@", pr_number);
    create_temp(&resolved)
}

/// The one-way PR import: args = [import_pr, component, pr-number,
/// (--options "<opts>")?]. One attempt, HTTPS App-token auth (GITHUB_TOKEN
/// passed through by name), no SSH key.
pub fn run_import_pr(
    args: &[Vec<u8>],
    component: &[u8],
    r: &mut dyn Runner,
    out: &mut dyn Write,
    err: &mut dyn Write,
) -> i32 {
    if args.len() < 3 {
        put(
            err,
            &[b"usage: sync import_pr <component> <pr-number> [--options \"<opts>\"]\n"],
        );
        return 2;
    }
    let pr_number = &args[2][..];
    if !is_digits(pr_number) {
        put(
            err,
            &[
                b"import_pr: pr-number must be digits, got ",
                &gostr::quote(pr_number),
                b"\n",
            ],
        );
        return 2;
    }

    let options = parse_options(args, 3);

    let workspace = resolve_workspace();
    let cfg_path = match resolve_import_pr_config(&workspace, pr_number) {
        Ok(p) => p,
        Err(e) => {
            put(err, &[b"import_pr: ", &e, b"\n"]);
            return 1;
        }
    };

    let home = getenv("HOME");
    let wf = workflow_name(b"import_pr", component);
    let docker_args: Vec<Vec<u8>> = vec![
        b"--rm".to_vec(),
        b"-v".to_vec(),
        cat(&[&workspace, b":/usr/src/app"]),
        b"-v".to_vec(),
        cat(&[&cfg_path, b":/root/copy.bara.sky"]),
        b"-v".to_vec(),
        cat(&[&home, b"/.git-credentials:/root/.git-credentials"]),
        b"-v".to_vec(),
        cat(&[&home, b"/.gitconfig:/root/.gitconfig"]),
        b"-e".to_vec(),
        b"COPYBARA_CONFIG=/root/copy.bara.sky".to_vec(),
        b"-e".to_vec(),
        cat(&[b"COPYBARA_WORKFLOW=", &wf]),
        b"-e".to_vec(),
        cat(&[b"COPYBARA_SOURCEREF=", pr_number]),
        b"-e".to_vec(),
        cat(&[b"COPYBARA_OPTIONS=", &options]),
        // The App token comes from the host env by name; its value never
        // appears in argv, so never in `ps`.
        b"-e".to_vec(),
        b"GITHUB_TOKEN".to_vec(),
    ];

    let result = r.run(PINNED_IMAGE, &docker_args);
    let code = match result {
        Err(e) => {
            put(err, &[b"docker error: ", &e, b"\n"]);
            1
        }
        Ok(c) if is_success(c) => {
            put(
                out,
                &[
                    format!("Copybara import_pr OK (exit {c}; 4 = no-op) for ").as_bytes(),
                    component,
                    b" PR #",
                    pr_number,
                    b"\n",
                ],
            );
            0
        }
        Ok(c) => {
            put(
                err,
                &[
                    format!("Copybara import_pr failed (exit {c}) for ").as_bytes(),
                    component,
                    b" PR #",
                    pr_number,
                    b"\n",
                ],
            );
            c
        }
    };
    let _ = std::fs::remove_file(OsString::from_vec(cfg_path));
    code
}

#[cfg(test)]
mod lib_test;
