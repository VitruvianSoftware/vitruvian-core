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

//! saas-cli: saas-cli.sh in Rust. Run the Neon and Upstash CLIs (pinned
//! versions, through npx) with their credentials read per invocation from
//! GCP Secret Manager under the identity pinned in
//! infrastructure/gcp-identities.tsv, and handed over in the ENVIRONMENT,
//! never argv. A gcloud failure, including the reauth error it exits 0 on,
//! and an empty secret are fatal with the fix named. Same calls, output and
//! exit codes as the script.

use shell_compat as sh;
use std::os::unix::ffi::OsStringExt;
use std::process::Command;

pub struct Exit(pub i32);

fn die(msg: &[u8]) -> Exit {
    sh::err(&sh::cat(&[b"saas-cli: ", msg, b"\n"]));
    Exit(1)
}

/// `IFS=$'\t' read -r ACCOUNT PROJECT < <(bash resolver map dir) || true`.
fn resolve_identity(resolver: &[u8], map: &[u8], dir: &[u8]) -> (Vec<u8>, Vec<u8>) {
    let mut c = Command::new("bash");
    c.arg(sh::os(resolver)).arg(sh::os(map)).arg(sh::os(dir));
    let ran = sh::capture_stdout(79, &mut c);
    let mut f = sh::read_fields(&sh::first_line(&ran.stdout), b"\t", 2);
    let project = f.pop().unwrap_or_default();
    let account = f.pop().unwrap_or_default();
    (account, project)
}

fn workspace() -> Vec<u8> {
    if sh::env_set_nonempty("BUILD_WORKSPACE_DIRECTORY") {
        return sh::env_or_empty("BUILD_WORKSPACE_DIRECTORY");
    }
    let exe = std::env::current_exe().unwrap_or_default();
    let dir = exe.parent().map(|p| p.join("../..")).unwrap_or_default();
    let dir = std::fs::canonicalize(&dir).unwrap_or(dir);
    sh::path_bytes(&dir)
}

struct Ctx {
    gcloud: Vec<u8>,
    npx: Vec<u8>,
    account: Vec<u8>,
    project: Vec<u8>,
    cred_dir: Vec<u8>,
}

impl Ctx {
    /// `secret NAME`: the value, or a fatal error naming how to fix it.
    fn secret(&self, name: &str) -> Result<Vec<u8>, Exit> {
        let mut c = Command::new(sh::os(&self.gcloud));
        c.arg(sh::os(&sh::cat(&[b"--account=", &self.account])))
            .arg(sh::os(&sh::cat(&[b"--project=", &self.project])))
            .args(["secrets", "versions", "access", "latest"])
            .arg(format!("--secret={}", name));
        let ran = sh::capture(97, &mut c);
        if !ran.ok() || sh::grep_q_line_start(&ran.stderr, b"ERROR:") {
            sh::err(&sh::cat(&[
                b"saas-cli: could not read ",
                name.as_bytes(),
                b" from ",
                &self.project,
                b" as ",
                &self.account,
                b":\n",
            ]));
            sh::err(&sh::indent(&ran.stderr));
            if sh::grep_qi(&ran.stderr, &["reauth", "auth tokens", "credentials"]) {
                sh::err(&sh::cat(&[
                    "  \u{2192} refresh the pinned identity:  gcloud auth login ".as_bytes(),
                    &self.account,
                    b"\n",
                ]));
            } else {
                sh::err(&sh::cat(&[
                    "  \u{2192} seed it:  bazel run //tools/gcp-secrets:seed -- ".as_bytes(),
                    &self.cred_dir,
                    b" ",
                    name.as_bytes(),
                    b"\n",
                ]));
            }
            return Err(Exit(1));
        }
        let out = sh::subst(ran.stdout);
        if out.is_empty() {
            return Err(die(&sh::cat(&[
                name.as_bytes(),
                b" is empty in ",
                &self.project,
                " \u{2014} seed it with //tools/gcp-secrets:seed".as_bytes(),
            ])));
        }
        Ok(out)
    }

    fn npx(&self, package: &str, args: &[&[u8]], env: &[(&str, &[u8])]) -> Command {
        let mut c = Command::new(sh::os(&self.npx));
        c.arg("--yes").arg(package);
        for a in args {
            c.arg(sh::os(a));
        }
        for (k, v) in env {
            c.env(k, sh::os(v));
        }
        c
    }

    /// `exec "$NPX_BIN" ...` (script line `line`): become the CLI. Returns
    /// only if that failed, having said why as bash does.
    fn exec(&self, line: u32, mut c: Command) -> Exit {
        use std::os::unix::process::CommandExt;
        let e = c.exec();
        let (msg, code) = exec_failure(&self.npx, &e);
        let prog = sh::cat(&[&std::env::args_os()
            .next()
            .map(OsStringExt::into_vec)
            .unwrap_or_default()]);
        sh::err(&sh::cat(&[
            &prog,
            format!(": line {}: ", line).as_bytes(),
            &msg,
            b"\n",
        ]));
        Exit(code)
    }

    /// `VAR=... "$NPX_BIN" ... 2>&1 | sed 's/^/  /'`: both streams through
    /// one pipe, indented as they arrive; the CLI's status (pipefail).
    fn indented(&self, mut c: Command) -> i32 {
        use std::io::Read;
        use std::os::fd::OwnedFd;
        use std::os::unix::net::UnixStream;
        let (mut r, w) = match UnixStream::pair() {
            Ok(p) => p,
            Err(_) => return 1,
        };
        let w2 = match w.try_clone() {
            Ok(w2) => w2,
            Err(_) => return 1,
        };
        c.stdout(std::process::Stdio::from(OwnedFd::from(w)))
            .stderr(std::process::Stdio::from(OwnedFd::from(w2)));
        let spawned = c.spawn();
        drop(c); // our copies of the write end, so the read below sees EOF
        let mut child = match spawned {
            Ok(ch) => ch,
            Err(e) => {
                // bash's "command not found" goes down the pipe, indented.
                let probe = Command::new(sh::os(&self.npx));
                sh::out(&sh::indent(&sh::spawn_diag(158, &probe, &e)));
                return sh::spawn_failure_status(&e);
            }
        };
        let mut at_start = true;
        let mut buf = [0u8; 8192];
        loop {
            match r.read(&mut buf) {
                Ok(0) => break,
                Ok(n) => sh::out(&indent_chunk(&buf[..n], &mut at_start)),
                Err(e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
                Err(_) => break,
            }
        }
        match child.wait() {
            Ok(st) => sh::status_code(st),
            Err(_) => 1,
        }
    }
}

/// `sed 's/^/  /'` over a stream, one chunk at a time: `at_start` carries
/// whether the next byte begins a line.
pub fn indent_chunk(chunk: &[u8], at_start: &mut bool) -> Vec<u8> {
    let mut v = Vec::with_capacity(chunk.len() + 16);
    for &b in chunk {
        if *at_start {
            v.extend_from_slice(b"  ");
            *at_start = false;
        }
        v.push(b);
        if b == b'\n' {
            *at_start = true;
        }
    }
    v
}

/// What bash says, and exits with, when `exec NAME` fails.
pub fn exec_failure(name: &[u8], e: &std::io::Error) -> (Vec<u8>, i32) {
    if e.kind() == std::io::ErrorKind::NotFound {
        if name.contains(&b'/') {
            (sh::cat(&[name, b": ", sh::strerror(e).as_bytes()]), 127)
        } else {
            (sh::cat(&[b"exec: ", name, b": not found"]), 127)
        }
    } else {
        (
            sh::cat(&[
                b"exec: ",
                name,
                b": cannot execute: ",
                sh::strerror(e).as_bytes(),
            ]),
            126,
        )
    }
}

fn body(args: &[Vec<u8>]) -> Result<(), Exit> {
    let neonctl = sh::env_or("NEONCTL_VERSION", b"2.15.0");
    let upstash = sh::env_or("UPSTASH_CLI_VERSION", b"1.0.2");
    let cred_dir = sh::env_or("CRED_DIR", b"tabula/infra/build");
    let gcloud = sh::env_or("GCLOUD_BIN", b"gcloud");
    let npx = sh::env_or("NPX_BIN", b"npx");

    let sub = args.first().cloned().unwrap_or_default();
    if sub.is_empty() {
        return Err(die(
            b"internal: no subcommand (the sh_binary target bakes it)",
        ));
    }
    let rest: Vec<&[u8]> = args[1..].iter().map(Vec::as_slice).collect();

    let ws = workspace();
    let id_map = sh::env_or(
        "GCP_IDENTITY_MAP",
        &sh::cat(&[&ws, b"/infrastructure/gcp-identities.tsv"]),
    );
    let resolver = sh::env_or(
        "GCP_IDENTITY_RESOLVER",
        &sh::cat(&[&ws, b"/tools/pulumi/resolve_identity.sh"]),
    );
    if !sh::is_file(&id_map) {
        return Err(die(&sh::cat(&[b"identity map not found: ", &id_map])));
    }
    if !sh::is_file(&resolver) {
        return Err(die(&sh::cat(&[
            b"identity resolver not found: ",
            &resolver,
        ])));
    }
    let (account, project) = resolve_identity(&resolver, &id_map, &cred_dir);
    let map_name = sh::basename(&id_map);
    if account.is_empty() {
        return Err(die(&sh::cat(&[
            &cred_dir,
            b" is not listed in ",
            &map_name,
        ])));
    }
    if project.is_empty() || project == b"-" {
        return Err(die(&sh::cat(&[
            &cred_dir,
            b" has no project pinned in ",
            &map_name,
        ])));
    }

    let ctx = Ctx {
        gcloud,
        npx,
        account,
        project,
        cred_dir,
    };
    let neon_pkg = format!("neonctl@{}", String::from_utf8_lossy(&neonctl));
    let upstash_pkg = format!("@upstash/cli@{}", String::from_utf8_lossy(&upstash));

    match sub.as_slice() {
        b"neon" => {
            let key = ctx.secret("NEON_API_KEY")?;
            sh::err(&sh::cat(&[
                "\u{2192} ".as_bytes(),
                neon_pkg.as_bytes(),
                b" as the ",
                &ctx.project,
                b" NEON_API_KEY\n",
            ]));
            let c = ctx.npx(&neon_pkg, &rest, &[("NEON_API_KEY", &key)]);
            Err(ctx.exec(128, c))
        }
        b"upstash" => {
            let email = ctx.secret("UPSTASH_EMAIL")?;
            let key = ctx.secret("UPSTASH_API_KEY")?;
            sh::err(&sh::cat(&[
                "\u{2192} ".as_bytes(),
                upstash_pkg.as_bytes(),
                b" as the ",
                &ctx.project,
                b" UPSTASH_API_KEY\n",
            ]));
            let c = ctx.npx(
                &upstash_pkg,
                &rest,
                &[("UPSTASH_EMAIL", &email), ("UPSTASH_API_KEY", &key)],
            );
            Err(ctx.exec(136, c))
        }
        b"whoami" => {
            let nkey = ctx.secret("NEON_API_KEY")?;
            let uemail = ctx.secret("UPSTASH_EMAIL")?;
            let ukey = ctx.secret("UPSTASH_API_KEY")?;
            let mut rc = 0;
            sh::out(b"neon:\n");
            let c = ctx.npx(&neon_pkg, &[b"me"], &[("NEON_API_KEY", &nkey)]);
            if ctx.indented(c) != 0 {
                sh::err(
                    "  \u{2717} neonctl me failed \u{2014} the key is present but not usable\n"
                        .as_bytes(),
                );
                rc = 1;
            }
            sh::out(b"upstash:\n");
            let c = ctx.npx(
                &upstash_pkg,
                &[b"redis", b"list"],
                &[("UPSTASH_EMAIL", &uemail), ("UPSTASH_API_KEY", &ukey)],
            );
            if ctx.indented(c) != 0 {
                sh::err("  \u{2717} upstash redis list failed \u{2014} the key is present but not usable\n".as_bytes());
                rc = 1;
            }
            Err(Exit(rc))
        }
        _ => Err(die(&sh::cat(&[
            b"unknown subcommand '",
            &sub,
            b"' (expected: neon, upstash, whoami)",
        ]))),
    }
}

/// The whole tool; the process exit code (neon and upstash only return here
/// when the CLI could not be started).
pub fn run(args: &[Vec<u8>]) -> i32 {
    match body(args) {
        Ok(()) => 0,
        Err(Exit(c)) => c,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn indents_across_chunks() {
        let mut at = true;
        let mut out = indent_chunk(b"one\ntw", &mut at);
        out.extend(indent_chunk(b"o\n", &mut at));
        out.extend(indent_chunk(b"", &mut at));
        out.extend(indent_chunk(b"three", &mut at));
        assert_eq!(out, b"  one\n  two\n  three");
    }

    #[test]
    fn exec_failures_read_like_bash() {
        let nf = std::io::Error::from(std::io::ErrorKind::NotFound);
        assert_eq!(
            exec_failure(b"npx", &nf),
            (b"exec: npx: not found".to_vec(), 127)
        );
        let enoent = std::io::Error::from_raw_os_error(2);
        assert_eq!(
            exec_failure(b"/x/npx", &enoent),
            (b"/x/npx: No such file or directory".to_vec(), 127)
        );
        let eacces = std::io::Error::from_raw_os_error(13);
        assert_eq!(
            exec_failure(b"/x/npx", &eacces),
            (
                b"exec: /x/npx: cannot execute: Permission denied".to_vec(),
                126
            )
        );
    }
}
