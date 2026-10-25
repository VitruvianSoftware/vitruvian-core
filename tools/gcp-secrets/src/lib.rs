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

//! gcp-secrets: gcp-secrets.sh in Rust. Seed and inspect GCP Secret Manager
//! secret VALUES with the identity and project pinned from
//! infrastructure/gcp-identities.tsv. The value is read hidden and handed to
//! gcloud on stdin (`--data-file=-`), never argv; an already-seeded secret is
//! skipped unless --force; a gcloud failure, including the reauth error it
//! exits 0 on, is fatal. Same argv, stdout, stderr and exit codes as the
//! script.

use shell_compat as sh;
use std::process::{Command, Stdio};

/// A fatal exit: the message was already printed; this is the code.
pub struct Exit(pub i32);

fn die(msg: &[u8]) -> Exit {
    sh::err(&sh::cat(&[b"error: ", msg, b"\n"]));
    Exit(1)
}

const USAGE: &str = "usage:
  bazel run //tools/gcp-secrets:status -- <infra-dir>
  bazel run //tools/gcp-secrets:seed   -- <infra-dir> [--force] [SECRET_NAME...]

<infra-dir> is the app's Pulumi infra directory as it appears in
infrastructure/gcp-identities.tsv, e.g. tabula/infra/build \u{2014} the identity and
target project are resolved from there, never from ambient gcloud.
";

/// `IFS=$'\t' read -r ACCOUNT PROJECT < <(bash resolver map dir) || true`.
pub fn resolve_identity(resolver: &[u8], map: &[u8], dir: &[u8]) -> (Vec<u8>, Vec<u8>) {
    let mut c = Command::new("bash");
    c.arg(sh::os(resolver)).arg(sh::os(map)).arg(sh::os(dir));
    let ran = sh::capture_stdout(105, &mut c);
    let line = sh::first_line(&ran.stdout);
    let mut f = sh::read_fields(&line, b"\t", 2);
    let project = f.pop().unwrap_or_default();
    let account = f.pop().unwrap_or_default();
    (account, project)
}

/// The workspace root: $BUILD_WORKSPACE_DIRECTORY under `bazel run`, else two
/// levels above this program (the script used its own directory).
fn workspace() -> Vec<u8> {
    if sh::env_set_nonempty("BUILD_WORKSPACE_DIRECTORY") {
        return sh::env_or_empty("BUILD_WORKSPACE_DIRECTORY");
    }
    let exe = std::env::current_exe().unwrap_or_default();
    let dir = exe.parent().map(|p| p.join("../..")).unwrap_or_default();
    let dir = std::fs::canonicalize(&dir).unwrap_or(dir);
    sh::path_bytes(&dir)
}

/// The number of non-empty lines, `grep -c .` over `printf '%s\n' "$out"`.
pub fn count_lines(out: &[u8]) -> usize {
    out.split(|&c| c == b'\n').filter(|l| !l.is_empty()).count()
}

/// all_secrets' post-processing: each line's last path segment, empty ones
/// dropped (`sed 's|.*/||' | grep -v '^$'`), as `$(...)` captures it.
pub fn secret_names(out: &[u8]) -> Vec<u8> {
    let mut v: Vec<u8> = Vec::new();
    for line in out.split(|&c| c == b'\n') {
        let name = match line.iter().rposition(|&c| c == b'/') {
            Some(i) => &line[i + 1..],
            None => line,
        };
        if name.is_empty() {
            continue;
        }
        v.extend_from_slice(name);
        v.push(b'\n');
    }
    sh::subst(v)
}

struct Gcloud {
    bin: Vec<u8>,
    account: Vec<u8>,
    project: Vec<u8>,
}

impl Gcloud {
    fn cmd(&self, args: &[&[u8]]) -> Command {
        let mut c = Command::new(sh::os(&self.bin));
        c.arg(sh::os(&sh::cat(&[b"--account=", &self.account])))
            .arg(sh::os(&sh::cat(&[b"--project=", &self.project])));
        for a in args {
            c.arg(sh::os(a));
        }
        c
    }

    /// gc_checked, as its caller's `$(...)` sees it: stdout, or a fatal exit
    /// that surfaces gcloud's own stderr (a reauth error exits 0).
    fn checked(&self, args: &[&[u8]]) -> Result<Vec<u8>, Exit> {
        let ran = sh::capture(121, &mut self.cmd(args));
        if !ran.ok() || sh::grep_q_line_start(&ran.stderr, b"ERROR:") {
            let joined = args.join(&b' ');
            sh::err(&sh::cat(&[
                b"error: gcloud ",
                &joined,
                b" failed as ",
                &self.account,
                b" on ",
                &self.project,
                b":\n",
            ]));
            sh::err(&sh::indent(&ran.stderr));
            if sh::grep_qi(&ran.stderr, &["reauth", "auth tokens", "credentials"]) {
                sh::err(&sh::cat(&[
                    "  \u{2192} refresh the pinned identity:  gcloud auth login ".as_bytes(),
                    &self.account,
                    b"\n",
                ]));
            }
            return Err(Exit(1));
        }
        Ok(sh::subst(ran.stdout))
    }

    /// version_count: the number of ENABLED versions, as text.
    fn version_count(&self, secret: &[u8]) -> Result<Vec<u8>, Exit> {
        let out = self.checked(&[
            b"secrets",
            b"versions",
            b"list",
            secret,
            b"--filter=state:ENABLED",
            b"--format=value(name)",
        ])?;
        Ok(count_lines(&out).to_string().into_bytes())
    }

    fn all_secrets(&self) -> Result<Vec<u8>, Exit> {
        let out = self.checked(&[b"secrets", b"list", b"--format=value(name)"])?;
        Ok(secret_names(&out))
    }
}

/// `IFS= read -rs value` from stdin: terminal echo off while reading when
/// stdin is a terminal.
fn read_hidden() -> Vec<u8> {
    let tty = if sh::stdin_is_tty() {
        std::fs::File::open("/dev/stdin").ok()
    } else {
        None
    };
    sh::with_echo_off(tty.as_ref(), sh::read_stdin_line).0
}

fn body(args: &[Vec<u8>]) -> Result<(), Exit> {
    let gcloud_bin = sh::env_or("GCLOUD_BIN", b"gcloud");

    let mut it = args.iter();
    let sub = it.next().cloned().unwrap_or_default();
    if sub.is_empty() {
        return Err(die(
            b"internal: no subcommand (the sh_binary target bakes it)",
        ));
    }
    let infra = it.next().cloned().unwrap_or_default();
    if infra.is_empty() {
        sh::err(USAGE.as_bytes());
        return Err(Exit(2));
    }
    let mut force = false;
    let mut names: Vec<Vec<u8>> = Vec::new();
    for a in it {
        if a == b"--force" {
            force = true;
        } else if a.starts_with(b"-") {
            return Err(die(&sh::cat(&[b"unknown flag: ", a])));
        } else {
            names.push(a.clone());
        }
    }

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
    let (account, project) = resolve_identity(&resolver, &id_map, &infra);
    let map_name = sh::basename(&id_map);
    if account.is_empty() {
        return Err(die(&sh::cat(&[
            &infra,
            " is not listed in ".as_bytes(),
            &map_name,
            " \u{2014} add it (account + project) before seeding secrets".as_bytes(),
        ])));
    }
    if project.is_empty() || project == b"-" {
        return Err(die(&sh::cat(&[
            &infra,
            b" has no project pinned in ",
            &map_name,
            b" (found '-'); secrets need a concrete project",
        ])));
    }
    sh::err(&sh::cat(&[
        "\u{2192} GCP identity: ".as_bytes(),
        &account,
        b"   project: ",
        &project,
        b"   (",
        &infra,
        b")\n",
    ]));

    let gc = Gcloud {
        bin: gcloud_bin,
        account: account.clone(),
        project: project.clone(),
    };

    match sub.as_slice() {
        b"status" => {
            let secrets = gc.all_secrets()?;
            sh::out(&sh::cat(&[
                &sh::pad_right(b"SECRET", 32),
                b" ENABLED VERSIONS\n",
            ]));
            let mut unseeded = 0;
            for line in sh::lines(&secrets) {
                let s = sh::read_trim(&line);
                if s.is_empty() {
                    continue;
                }
                let n = gc.version_count(&s)?;
                let note: &[u8] = if n == b"0" {
                    b"   <- needs a value"
                } else {
                    b""
                };
                sh::out(&sh::cat(&[&sh::pad_right(&s, 32), b" ", &n, note, b"\n"]));
                if n == b"0" {
                    unseeded += 1;
                }
            }
            if unseeded > 0 {
                sh::err(&sh::cat(&[
                    b"\n",
                    format!(
                        "{} secret(s) have no value yet. Seed them with:\n",
                        unseeded
                    )
                    .as_bytes(),
                    b"  bazel run //tools/gcp-secrets:seed -- ",
                    &infra,
                    b"\n",
                ]));
            }
        }
        b"seed" => {
            if names.is_empty() {
                let discovered = gc.all_secrets()?;
                for line in sh::lines(&discovered) {
                    let s = sh::read_trim(&line);
                    if !s.is_empty() {
                        names.push(s);
                    }
                }
                if names.is_empty() {
                    return Err(die(&sh::cat(&[
                        b"no secrets found in ",
                        &project,
                        " \u{2014} has the stack been applied?".as_bytes(),
                    ])));
                }
            }
            let (mut seeded, mut skipped) = (0, 0);
            for s in &names {
                let n = gc.version_count(s)?;
                if n != b"0" && !force {
                    sh::out(&sh::cat(&[
                        b"  ",
                        s,
                        b": already has ",
                        &n,
                        " version(s) \u{2014} skipping (use --force to rotate)\n".as_bytes(),
                    ]));
                    skipped += 1;
                    continue;
                }
                sh::err(&sh::cat(&[
                    b"value for ",
                    s,
                    b" (input hidden, empty to skip): ",
                ]));
                let mut value = read_hidden();
                sh::err(b"\n");
                if value.is_empty() {
                    sh::out(&sh::cat(&[b"  ", s, b": skipped (no value entered)\n"]));
                    skipped += 1;
                    continue;
                }
                let mut c = gc.cmd(&[b"secrets", b"versions", b"add", s, b"--data-file=-"]);
                c.stdout(Stdio::null()).stderr(Stdio::null());
                let st = sh::status_with_input(231, &mut c, &value, true);
                // The value is not kept a moment longer than the call.
                value.iter_mut().for_each(|b| *b = 0);
                if st == 0 {
                    sh::out(&sh::cat(&[b"  ", s, ": seeded \u{2705}\n".as_bytes()]));
                    seeded += 1;
                } else {
                    return Err(die(&sh::cat(&[
                        s,
                        b": failed to add a version (identity ",
                        &account,
                        b" may lack secretmanager.versions.add on ",
                        &project,
                        b")",
                    ])));
                }
            }
            sh::out(format!("\nseeded {}, skipped {}\n", seeded, skipped).as_bytes());
        }
        _ => {
            return Err(die(&sh::cat(&[
                b"unknown subcommand '",
                &sub,
                b"' (expected: status, seed)",
            ])));
        }
    }
    Ok(())
}

/// The whole tool; the process exit code.
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
    fn counts_non_empty_lines() {
        assert_eq!(count_lines(b""), 0);
        assert_eq!(count_lines(b"a/versions/1"), 1);
        assert_eq!(count_lines(b"a\n\nb"), 2);
    }

    #[test]
    fn names_are_last_segments() {
        assert_eq!(
            secret_names(b"projects/p/secrets/ALPHA\nprojects/p/secrets/BETA"),
            b"ALPHA\nBETA"
        );
        assert_eq!(secret_names(b"PLAIN\nends/with/\n\n"), b"PLAIN");
        assert_eq!(secret_names(b""), b"");
    }
}
