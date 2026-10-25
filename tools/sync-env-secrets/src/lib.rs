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

//! sync-env-secrets: sync-env-secrets.sh in Rust. Deploy-time GitHub Actions
//! secrets kept in a gitignored, Bitwarden-backed store: `apply` PUTs a
//! GitHub environment's secrets, `bw-push`/`bw-pull` move the store to and
//! from a Bitwarden attachment, `unlock`/`lock` manage a cached session, and
//! `agent-keys-*` do the same for the per-agent App keys. Same calls to `bw`,
//! `gh` and `tar`, same output and exit codes as the script.
//!
//! Where it differs, on purpose:
//!   * no `jq`: bw's JSON is read with serde_json (src/jq.rs), so "jq not
//!     installed" is no longer a failure;
//!   * the new-item payload is serialised by serde_json, so a BW_ITEM with a
//!     quote or backslash in it is escaped instead of breaking the JSON;
//!   * every temporary directory holding a decrypted archive is removed on
//!     exit (`set` makes two; the script's EXIT trap only knew the last).

pub mod jq;

use serde::Serialize;
use shell_compat as sh;
use std::process::{Command, Stdio};

pub struct Exit(pub i32);

fn die(msg: &[u8]) -> Exit {
    sh::err(&sh::cat(&[b"error: ", msg, b"\n"]));
    Exit(1)
}

type R = Result<(), Exit>;

/// Exit when a command that `set -e` guards fails, or when an interrupt
/// arrived while it ran (the cleanup in `run` then removes any decrypted
/// archive, as the script's EXIT trap does).
fn guard(st: i32) -> R {
    if let Some(sig) = sh::caught_signal() {
        return Err(Exit(128 + sig));
    }
    if st == 0 {
        Ok(())
    } else {
        Err(Exit(st))
    }
}

#[derive(Serialize)]
struct SecureNote {
    #[serde(rename = "type")]
    kind: u8,
}

/// The Bitwarden secure note the store's attachment hangs off.
#[derive(Serialize)]
struct NewItem<'a> {
    #[serde(rename = "type")]
    kind: u8,
    name: &'a str,
    notes: &'a str,
    #[serde(rename = "secureNote")]
    secure_note: SecureNote,
}

pub fn new_item_json(name: &str) -> Vec<u8> {
    serde_json::to_vec(&NewItem {
        kind: 2,
        name,
        notes: "gitignored deploy-time env secrets (managed by tools/sync-env-secrets)",
        secure_note: SecureNote { kind: 0 },
    })
    .expect("a struct of strings serialises")
}

/// A `cmd | jq ...` pipeline under pipefail: jq's output, and the status of
/// the rightmost command that failed.
fn piped(producer: i32, j: jq::JqOut) -> (Vec<u8>, i32) {
    let st = if j.status != 0 { j.status } else { producer };
    (j.stdout, st)
}

struct Tool {
    repo: Vec<u8>,
    store: Vec<u8>,
    bw_item: Vec<u8>,
    archive: Vec<u8>,
    agent_store: Vec<u8>,
    agent_item: Vec<u8>,
    agent_archive: Vec<u8>,
    sess_cache: Vec<u8>,
    tmp_cleanup: Vec<Vec<u8>>,
}

fn bw() -> Command {
    Command::new("bw")
}

impl Tool {
    fn new() -> Tool {
        let base = if sh::env_set_nonempty("BUILD_WORKSPACE_DIRECTORY") {
            sh::cat(&[
                &sh::env_or_empty("BUILD_WORKSPACE_DIRECTORY"),
                b"/tools/sync-env-secrets",
            ])
        } else {
            let exe = std::env::current_exe().unwrap_or_default();
            let dir = exe.parent().map(|p| p.to_path_buf()).unwrap_or_default();
            sh::path_bytes(&std::fs::canonicalize(&dir).unwrap_or(dir))
        };
        let cache_home = match sh::env("XDG_CACHE_HOME") {
            Some(v) if !v.is_empty() => v,
            _ => sh::cat(&[&sh::env_or_empty("HOME"), b"/.cache"]),
        };
        Tool {
            repo: sh::env_or("REPO", b"VitruvianSoftware/vitruvian-core"),
            store: sh::cat(&[&base, b"/secrets"]),
            agent_store: sh::cat(&[&base, b"/agent-keys"]),
            bw_item: sh::env_or("BW_ITEM", b"vitruvian-core/deploy-env-secrets"),
            archive: b"deploy-env-secrets.tar.gz".to_vec(),
            agent_item: sh::env_or("AGENT_KEY_BW_ITEM", b"vitruvian-core/agent-app-keys"),
            agent_archive: b"agent-app-keys.tar.gz".to_vec(),
            sess_cache: sh::cat(&[&cache_home, b"/vitruvian-core/bw-session"]),
            tmp_cleanup: Vec::new(),
        }
    }

    fn cleanup(&mut self) {
        for d in self.tmp_cleanup.drain(..) {
            let _ = std::fs::remove_dir_all(sh::path(&d));
        }
    }

    fn mktemp_dir(&mut self) -> Result<Vec<u8>, Exit> {
        match sh::mktemp_dir() {
            Ok(d) => {
                self.tmp_cleanup.push(d.clone());
                Ok(d)
            }
            Err(e) => {
                sh::err(format!("mktemp: {}\n", sh::strerror(&e)).as_bytes());
                Err(Exit(1))
            }
        }
    }

    fn apply(&self, env: &[u8]) -> R {
        if env.is_empty() {
            return Err(die(b"usage: apply <github-environment>"));
        }
        let dir = sh::cat(&[&self.store, b"/", env]);
        if !sh::is_dir(&dir) {
            return Err(die(&sh::cat(&[
                b"no local store at ",
                &dir,
                " \u{2014} run 'bw-pull' first (or copy from secrets.example/)".as_bytes(),
            ])));
        }
        if sh::which(b"gh").is_none() {
            return Err(die(b"gh not installed"));
        }
        let mut count = 0;
        for f in glob(&dir, |_| true) {
            if !sh::is_file(&f) {
                continue;
            }
            let key = sh::basename(&f);
            if key.starts_with(b".") || key.ends_with(b".md") {
                continue;
            }
            let input = match std::fs::File::open(sh::path(&f)) {
                Ok(h) => h,
                Err(e) => {
                    sh::redirect_error(95, &f, &e);
                    return Err(Exit(1));
                }
            };
            let mut c = Command::new("gh");
            c.args(["secret", "set"])
                .arg(sh::os(&key))
                .arg("--env")
                .arg(sh::os(env))
                .arg("--repo")
                .arg(sh::os(&self.repo))
                .stdin(Stdio::from(input));
            guard(sh::status(95, &mut c, false))?;
            sh::out(&sh::cat(&[b"  set ", &key, b"  (env=", env, b")\n"]));
            count += 1;
        }
        if count == 0 {
            return Err(die(&sh::cat(&[b"no secret files found in ", &dir])));
        }
        sh::out(&sh::cat(&[
            format!("synced {} secret(s) to environment '", count).as_bytes(),
            env,
            b"' on ",
            &self.repo,
            b"\n",
        ]));
        Ok(())
    }

    /// bw_state: `bw status 2>/dev/null | jq -r .status 2>/dev/null || echo unknown`.
    fn bw_state(&self) -> Vec<u8> {
        let mut c = bw();
        c.arg("status");
        let ran = sh::capture(103, &mut c);
        let (mut out, st) = piped(ran.status, jq::status(&ran.stdout));
        if st != 0 {
            out.extend_from_slice(b"unknown\n");
        }
        sh::subst(out)
    }

    fn ensure_bw_session(&self) -> R {
        if sh::which(b"bw").is_none() {
            return Err(die(
                b"bw (Bitwarden CLI) not installed: brew install bitwarden-cli",
            ));
        }
        if sh::env_set_nonempty("BW_SESSION") && self.bw_state() == b"unlocked" {
            return Ok(());
        }
        std::env::remove_var("BW_SESSION");
        if sh::is_readable(&self.sess_cache) {
            let cached = match std::fs::read(sh::path(&self.sess_cache)) {
                Ok(v) => sh::subst(v),
                Err(e) => {
                    sh::err(&sh::cat(&[
                        b"cat: ",
                        &self.sess_cache,
                        b": ",
                        sh::strerror(&e).as_bytes(),
                        b"\n",
                    ]));
                    return Err(Exit(1));
                }
            };
            std::env::set_var("BW_SESSION", sh::os(&cached));
            if self.bw_state() == b"unlocked" {
                return Ok(());
            }
            std::env::remove_var("BW_SESSION");
        }
        if self.bw_state() == b"unauthenticated" {
            return Err(die(
                "not logged in to Bitwarden \u{2014} run 'bw login' once, then retry".as_bytes(),
            ));
        }
        let session = if sh::env_set_nonempty("BW_PASSWORD") {
            let mut c = bw();
            c.args(["unlock", "--passwordenv", "BW_PASSWORD", "--raw"]);
            let ran = sh::capture_stdout(123, &mut c);
            if !ran.ok() {
                return Err(die(b"bw unlock failed (BW_PASSWORD)"));
            }
            sh::subst(ran.stdout)
        } else if sh::stdin_is_tty() {
            sh::err("Unlocking Bitwarden \u{2014} enter your master password:\n".as_bytes());
            let mut c = bw();
            c.args(["unlock", "--raw"]);
            let ran = sh::capture_stdout(126, &mut c);
            if !ran.ok() {
                return Err(die(b"bw unlock failed"));
            }
            sh::subst(ran.stdout)
        } else {
            return Err(die(
                "Bitwarden locked and no usable cached session \u{2014} run 'bazel run //tools/sync-env-secrets:unlock' once (it prompts), then retry headless".as_bytes(),
            ));
        };
        if session.is_empty() {
            return Err(die(b"bw unlock returned an empty session"));
        }
        std::env::set_var("BW_SESSION", sh::os(&session));
        Ok(())
    }

    /// Persist the unlocked session, 0600, in a 0700 directory.
    fn cache_session(&self) -> R {
        let session = sh::env_or_empty("BW_SESSION");
        let old = sh::umask(0o077);
        let r = (|| -> R {
            let dir = sh::dirname(&self.sess_cache);
            if let Err(e) = sh::mkdir_p(&dir) {
                sh::err(&sh::cat(&[
                    b"mkdir: ",
                    &dir,
                    b": ",
                    sh::strerror(&e).as_bytes(),
                    b"\n",
                ]));
                return Err(Exit(1));
            }
            if let Err(e) = sh::write_file(&self.sess_cache, &session, 0o666) {
                sh::redirect_error(140, &self.sess_cache, &e);
                return Err(Exit(1));
            }
            use std::os::unix::fs::PermissionsExt;
            let _ = std::fs::set_permissions(
                sh::path(&self.sess_cache),
                std::fs::Permissions::from_mode(0o600),
            );
            Ok(())
        })();
        sh::umask(old);
        r
    }

    /// bw_item_id: the first search hit's id, or nothing; never fails.
    fn bw_item_id(&self) -> Vec<u8> {
        let mut c = bw();
        c.args(["list", "items", "--search"])
            .arg(sh::os(&self.bw_item));
        let ran = sh::capture(148, &mut c);
        sh::subst(jq::first_id_or_empty(&ran.stdout).stdout)
    }

    fn bw_sync(&self, line: u32) -> R {
        let mut c = bw();
        c.arg("sync").stdout(Stdio::null());
        guard(sh::status(line, &mut c, false))
    }

    fn bw_push(&mut self) -> R {
        self.ensure_bw_session()?;
        if !sh::is_dir(&self.store) {
            return Err(die(&sh::cat(&[
                b"nothing to push: ",
                &self.store,
                b" does not exist",
            ])));
        }
        self.bw_sync(153)?;
        let tmpdir = self.mktemp_dir()?;
        let tar = sh::cat(&[&tmpdir, b"/", &self.archive]);
        let mut c = Command::new("tar");
        c.arg("-czf")
            .arg(sh::os(&tar))
            .arg("-C")
            .arg(sh::os(&self.store))
            .arg(".");
        guard(sh::status(158, &mut c, false))?;
        let mut id = self.bw_item_id();
        if id.is_empty() {
            let name = String::from_utf8_lossy(&self.bw_item).into_owned();
            let payload = new_item_json(&name);
            // printf ... | bw encode | bw create item | jq -r '.id'
            let enc = pipe_through(161, bw().arg("encode"), &payload);
            let created = pipe_through(161, bw().args(["create", "item"]), &enc.stdout);
            let j = jq::id(&created.stdout);
            sh::err(&j.stderr);
            let (out, st) = piped(
                if created.status != 0 {
                    created.status
                } else {
                    enc.status
                },
                j,
            );
            guard(st)?;
            id = sh::subst(out);
            sh::out(&sh::cat(&[
                b"  created Bitwarden item '",
                &self.bw_item,
                b"' (",
                &id,
                b")\n",
            ]));
        } else {
            let mut c = bw();
            c.args(["get", "item"]).arg(sh::os(&id));
            let ran = sh::capture_stdout(166, &mut c);
            let name = String::from_utf8_lossy(&self.archive).into_owned();
            let j = jq::attachment_ids(&ran.stdout, &name);
            sh::err(&j.stderr);
            let olds = sh::subst(j.stdout);
            for att in sh::ifs_split(&olds) {
                let mut d = bw();
                d.args(["delete", "attachment"])
                    .arg(sh::os(&att))
                    .arg("--itemid")
                    .arg(sh::os(&id))
                    .stdout(Stdio::null());
                if sh::status(167, &mut d, false) != 0 {
                    return Err(die(&sh::cat(&[
                        b"failed to remove a stale '",
                        &self.archive,
                        "' attachment \u{2014} re-run, or delete it in the Bitwarden UI".as_bytes(),
                    ])));
                }
            }
        }
        let mut c = bw();
        c.args(["create", "attachment", "--itemid"])
            .arg(sh::os(&id))
            .arg("--file")
            .arg(sh::os(&tar))
            .stdout(Stdio::null());
        guard(sh::status(171, &mut c, false))?;
        sh::out(&sh::cat(&[
            b"pushed ",
            &self.archive,
            b" to Bitwarden item '",
            &self.bw_item,
            b"'\n",
        ]));
        Ok(())
    }

    fn bw_pull(&mut self) -> R {
        self.ensure_bw_session()?;
        self.bw_sync(177)?;
        let id = self.bw_item_id();
        if id.is_empty() {
            return Err(die(&sh::cat(&[
                b"no Bitwarden item '",
                &self.bw_item,
                "' \u{2014} run 'bw-push' first".as_bytes(),
            ])));
        }
        let mut c = bw();
        c.args(["get", "item"]).arg(sh::os(&id));
        let ran = sh::capture_stdout(182, &mut c);
        let name = String::from_utf8_lossy(&self.archive).into_owned();
        let j = jq::first_attachment_id_or_empty(&ran.stdout, &name);
        sh::err(&j.stderr);
        let (out, st) = piped(ran.status, j);
        guard(st)?;
        let att = sh::subst(out);
        if att.is_empty() {
            return Err(die(&sh::cat(&[
                b"no '",
                &self.archive,
                b"' attachment on item '",
                &self.bw_item,
                b"'",
            ])));
        }
        let tmpdir = self.mktemp_dir()?;
        let tar = sh::cat(&[&tmpdir, b"/", &self.archive]);
        let mut c = bw();
        c.args(["get", "attachment"])
            .arg(sh::os(&att))
            .arg("--itemid")
            .arg(sh::os(&id))
            .arg("--output")
            .arg(sh::os(&tar))
            .stdout(Stdio::null());
        guard(sh::status(187, &mut c, false))?;
        if let Err(e) = sh::mkdir_p(&self.store) {
            sh::err(&sh::cat(&[
                b"mkdir: ",
                &self.store,
                b": ",
                sh::strerror(&e).as_bytes(),
                b"\n",
            ]));
            return Err(Exit(1));
        }
        let mut c = Command::new("tar");
        c.arg("-xzf")
            .arg(sh::os(&tar))
            .arg("-C")
            .arg(sh::os(&self.store));
        guard(sh::status(189, &mut c, false))?;
        sh::out(&sh::cat(&[
            b"pulled store from Bitwarden item '",
            &self.bw_item,
            b"' into ",
            &self.store,
            b"\n",
        ]));
        Ok(())
    }

    fn unlock(&mut self) -> R {
        self.ensure_bw_session()?;
        self.cache_session()?;
        sh::out(&sh::cat(&[
            "\u{2713} Bitwarden unlocked; session cached at ".as_bytes(),
            &self.sess_cache,
            b".\n",
            b"  apply / bw-push / bw-pull now run headless (agent or CI) until the vault relocks. Run 'lock' to clear.\n",
        ]));
        Ok(())
    }

    fn lock(&self) -> R {
        let p = sh::path(&self.sess_cache);
        match std::fs::symlink_metadata(&p) {
            Ok(m) if m.is_dir() => {
                sh::err(&sh::cat(&[
                    b"rm: ",
                    &self.sess_cache,
                    b": is a directory\n",
                ]));
                return Err(Exit(1));
            }
            Ok(_) => {
                if let Err(e) = std::fs::remove_file(&p) {
                    sh::err(&sh::cat(&[
                        b"rm: ",
                        &self.sess_cache,
                        b": ",
                        sh::strerror(&e).as_bytes(),
                        b"\n",
                    ]));
                    return Err(Exit(1));
                }
            }
            Err(_) => {}
        }
        if sh::which(b"bw").is_some() {
            let mut c = bw();
            c.arg("lock").stdout(Stdio::null()).stderr(Stdio::null());
            let _ = sh::status(202, &mut c, true);
        }
        sh::out("\u{2713} cleared the cached session and locked the vault.\n".as_bytes());
        Ok(())
    }

    fn use_agent_store(&mut self) {
        self.store = self.agent_store.clone();
        self.bw_item = self.agent_item.clone();
        self.archive = self.agent_archive.clone();
    }

    fn agent_keys_push(&mut self) -> R {
        self.use_agent_store();
        if !sh::is_dir(&self.store) {
            return Err(die(&sh::cat(&[
                b"nothing to push: ",
                &self.store,
                b" does not exist (put <agent>.pem files there)",
            ])));
        }
        let pems = glob(&self.store, |n| n.ends_with(b".pem"));
        if pems.is_empty() {
            return Err(die(&sh::cat(&[b"no .pem files in ", &self.store])));
        }
        for f in &pems {
            if !sh::exists(f) {
                return Err(die(&sh::cat(&[b"no .pem files in ", &self.store])));
            }
            let mode = file_mode(f);
            if mode != "600" {
                return Err(die(&sh::cat(&[
                    f,
                    b" is mode ",
                    mode.as_bytes(),
                    b"; expected 600",
                ])));
            }
        }
        self.bw_push()
    }

    fn agent_keys_pull(&mut self) -> R {
        self.use_agent_store();
        sh::umask(0o077);
        self.bw_pull()
    }

    fn set(&mut self, env: &[u8], name: &[u8]) -> R {
        if env.is_empty() || name.is_empty() {
            return Err(die(b"usage: set <github-environment> <SECRET_NAME>"));
        }
        if !sh::is_readable(b"/dev/tty") {
            return Err(die(b"set needs a terminal to prompt for the value"));
        }
        sh::err("\u{2192} syncing the store from Bitwarden first (so a partial store is never pushed)\u{2026}\n".as_bytes());
        self.bw_pull()?;
        // The pulled archive is extracted; do not keep it in $TMPDIR while
        // waiting on a person (the script's trap only knew the newest dir).
        self.cleanup();
        let tty = match std::fs::File::open("/dev/tty") {
            Ok(t) => t,
            Err(e) => {
                sh::redirect_error(247, b"/dev/tty", &e);
                return Err(Exit(1));
            }
        };
        sh::err(&sh::cat(&[b"value for ", env, b"/", name, b" (hidden): "]));
        let mut reader = &tty;
        // `read -rs` without IFS=: surrounding blanks are trimmed.
        // Nothing decrypted is on disk now, so Ctrl-C may end the run as is.
        sh::default_exit_signals();
        let (line, _) = sh::with_echo_off(Some(&tty), || sh::read_line_raw(&mut reader));
        sh::record_exit_signals();
        let val = sh::read_trim(&line);
        sh::err(b"\n");
        if val.is_empty() {
            return Err(die("empty value \u{2014} nothing written".as_bytes()));
        }
        let dir = sh::cat(&[&self.store, b"/", env]);
        if let Err(e) = sh::mkdir_p(&dir) {
            sh::err(&sh::cat(&[
                b"mkdir: ",
                &dir,
                b": ",
                sh::strerror(&e).as_bytes(),
                b"\n",
            ]));
            return Err(Exit(1));
        }
        let file = sh::cat(&[&dir, b"/", name]);
        let old = sh::umask(0o077);
        let w = sh::write_file(&file, &val, 0o666);
        sh::umask(old);
        if let Err(e) = w {
            sh::redirect_error(251, &file, &e);
            return Err(Exit(1));
        }
        sh::err(&sh::cat(&[
            "\u{2192} wrote ".as_bytes(),
            &file,
            "; pushing the full store back to Bitwarden\u{2026}\n".as_bytes(),
        ]));
        self.bw_push()?;
        sh::err(&sh::cat(&[
            "\u{2713} ".as_bytes(),
            name,
            b" saved to Bitwarden and the local store.\n",
        ]));
        Ok(())
    }

    fn usage(&self) -> Exit {
        sh::err(&sh::cat(&[
            "sync-env-secrets \u{2014} manage non-GCP-SM deploy secrets as code (\u{a7}2.2, \u{a7}2.18)\n".as_bytes(),
            b"\n",
            b"Run via bazel (preferred):\n",
            b"  bazel run //tools/sync-env-secrets:apply   -- <github-environment>   # store -> GitHub env secrets\n",
            b"  bazel run //tools/sync-env-secrets:bw-pull                            # Bitwarden -> store\n",
            b"  bazel run //tools/sync-env-secrets:bw-push                            # store -> Bitwarden\n",
            b"  bazel run //tools/sync-env-secrets:unlock                             # cache a bw session (run once)\n",
            b"  bazel run //tools/sync-env-secrets:lock                               # clear the cached session + lock\n",
            b"\n",
            b"store: ",
            &self.store,
            b"/<github-environment>/<SECRET_NAME>   (gitignored; see secrets.example/)\n",
        ]));
        Exit(2)
    }
}

/// `printf ... | cmd` as one stage of a pipeline: `input` on stdin, stdout
/// captured, stderr passed through.
fn pipe_through(line: u32, cmd: &mut Command, input: &[u8]) -> sh::Ran {
    use std::io::Write;
    cmd.stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit());
    let mut child = match cmd.spawn() {
        Ok(c) => c,
        Err(e) => {
            sh::err(&sh::spawn_diag(line, cmd, &e));
            return sh::Ran {
                status: sh::spawn_failure_status(&e),
                stdout: Vec::new(),
                stderr: Vec::new(),
            };
        }
    };
    let data = input.to_vec();
    let mut sin = child.stdin.take().expect("piped stdin");
    let writer = std::thread::spawn(move || {
        let _ = sin.write_all(&data);
    });
    let out = child.wait_with_output();
    let _ = writer.join();
    match out {
        Ok(o) => sh::Ran {
            status: sh::status_code(o.status),
            stdout: o.stdout,
            stderr: Vec::new(),
        },
        Err(_) => sh::Ran {
            status: 1,
            stdout: Vec::new(),
            stderr: Vec::new(),
        },
    }
}

/// `"$dir"/*`, restricted by `keep` on the name: hidden names excluded,
/// sorted bytewise (the C locale's order).
fn glob(dir: &[u8], keep: impl Fn(&[u8]) -> bool) -> Vec<Vec<u8>> {
    use std::os::unix::ffi::OsStrExt;
    let mut names: Vec<Vec<u8>> = match std::fs::read_dir(sh::path(dir)) {
        Ok(rd) => rd
            .filter_map(|e| e.ok())
            .map(|e| e.file_name().as_bytes().to_vec())
            .filter(|n| !n.starts_with(b".") && keep(n))
            .collect(),
        Err(_) => Vec::new(),
    };
    names.sort();
    names
        .into_iter()
        .map(|n| sh::cat(&[dir, b"/", &n]))
        .collect()
}

/// A file's permission bits as `stat -c %a` prints them (octal, no padding).
fn file_mode(f: &[u8]) -> String {
    use std::os::unix::fs::PermissionsExt;
    match std::fs::metadata(sh::path(f)) {
        Ok(m) => format!("{:o}", m.permissions().mode() & 0o7777),
        Err(_) => String::new(),
    }
}

/// The whole tool; the process exit code.
pub fn run(args: &[Vec<u8>]) -> i32 {
    sh::record_exit_signals();
    let mut t = Tool::new();
    let arg = |i: usize| args.get(i).cloned().unwrap_or_default();
    let r = match arg(0).as_slice() {
        b"set" => {
            let (e, n) = (arg(1), arg(2));
            t.set(&e, &n)
        }
        b"apply" => t.apply(&arg(1)),
        b"agent-keys-push" => t.agent_keys_push(),
        b"agent-keys-pull" => t.agent_keys_pull(),
        b"bw-push" => t.bw_push(),
        b"bw-pull" => t.bw_pull(),
        b"unlock" => t.unlock(),
        b"lock" => t.lock(),
        _ => Err(t.usage()),
    };
    t.cleanup();
    if let Some(sig) = sh::caught_signal() {
        return 128 + sig;
    }
    match r {
        Ok(()) => 0,
        Err(Exit(c)) => c,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn new_item_payload_matches_the_script() {
        assert_eq!(
            String::from_utf8(new_item_json("vitruvian-core/deploy-env-secrets")).unwrap(),
            r#"{"type":2,"name":"vitruvian-core/deploy-env-secrets","notes":"gitignored deploy-time env secrets (managed by tools/sync-env-secrets)","secureNote":{"type":0}}"#
        );
    }

    #[test]
    fn new_item_payload_escapes() {
        let v: serde_json::Value = serde_json::from_slice(&new_item_json("a\"b\\c")).unwrap();
        assert_eq!(v["name"], "a\"b\\c");
    }

    #[test]
    fn pipefail_status_is_the_rightmost_failure() {
        let j = |status| jq::JqOut {
            stdout: Vec::new(),
            stderr: Vec::new(),
            status,
        };
        assert_eq!(piped(3, j(0)).1, 3);
        assert_eq!(piped(3, j(5)).1, 5);
        let ok = j(0);
        assert_eq!(piped(0, ok).1, 0);
    }
}
