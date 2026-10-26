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

//! ntfy_bootstrap_users.sh and ntfy_manage_users.sh: ntfy accounts live in
//! the pod's SQLite auth.db, so they are managed with `kubectl exec ntfy
//! ...`. Passwords come from `openssl rand`, reach the pod on stdin only, and
//! are printed once (or, with --gh-secret, never).

use std::process::{Command, Stdio};

use shell_compat as sc;

use super::common::*;

const NS: &[u8] = b"ntfy";

/// `kubectl --context K -n ntfy get pods -l app=ntfy -o
/// jsonpath='{.items[0].metadata.name}' 2>/dev/null || true`, and the error
/// when there is none.
fn find_pod(k: &[u8]) -> Res<Vec<u8>> {
    let (_, pod) = capture_quiet(
        0,
        kubectl(
            k,
            &[
                b"-n",
                NS,
                b"get",
                b"pods",
                b"-l",
                b"app=ntfy",
                b"-o",
                b"jsonpath={.items[0].metadata.name}",
            ],
        ),
    );
    if pod.is_empty() {
        return die(
            1,
            b"ERROR: no running ntfy pod found in namespace 'ntfy' (kubectl get pods -n ntfy -l app=ntfy). Is the ntfy Application synced?",
        );
    }
    Ok(pod)
}

/// `kubectl --context K -n ntfy exec [-i] POD -- ARGS...`.
fn kexec(k: &[u8], pod: &[u8], interactive: bool, args: &[&[u8]]) -> Command {
    let mut c = if interactive {
        kubectl(k, &[b"-n", NS, b"exec", b"-i", pod, b"--"])
    } else {
        kubectl(k, &[b"-n", NS, b"exec", pod, b"--"])
    };
    for a in args {
        c.arg(sc::os(a));
    }
    c
}

/// Does `text` hold `word` with a word boundary on each side (grep's `\b`)?
pub fn has_word(text: &[u8], word: &[u8]) -> bool {
    if word.is_empty() {
        return false;
    }
    let is_w = |c: u8| c.is_ascii_alphanumeric() || c == b'_';
    text.split(|&c| c == b'\n').any(|line| {
        line.len() >= word.len()
            && (0..=line.len() - word.len()).any(|i| {
                &line[i..i + word.len()] == word
                    && (i == 0 || !is_w(line[i - 1]) || !is_w(word[0]))
                    && (i + word.len() == line.len()
                        || !is_w(line[i + word.len()])
                        || !is_w(word[word.len() - 1]))
            })
    })
}

// ---------------------------------------------------------------------------
// ntfy_bootstrap_users.sh
// ---------------------------------------------------------------------------

pub fn bootstrap(args: &[Vec<u8>]) -> i32 {
    match bootstrap_run(args) {
        Ok(c) | Err(c) => c,
    }
}

fn valid_topic(t: &[u8]) -> bool {
    !t.is_empty()
        && t.iter()
            .all(|c| c.is_ascii_alphanumeric() || *c == b'_' || *c == b'-')
}

/// create_user, run as `$(create_user ...)`: in a command substitution bash
/// drops `set -e`, so no step here stops the others. Progress to stderr; the
/// `user:pass` line (only when the user was created) is returned.
fn create_user(
    k: &[u8],
    pod: &[u8],
    existing: &[u8],
    topic: &[u8],
    user: &str,
    access: &str,
) -> Vec<u8> {
    if has_word(existing, user.as_bytes()) {
        warn(&sc::cat(&[
            format!("= user '{}' already exists, skipping creation (rotate via: kubectl -n ntfy exec -it ", user).as_bytes(),
            pod,
            format!(" -- ntfy user change-pass {})", user).as_bytes(),
        ]));
        return Vec::new();
    }
    let (_, pass) = openssl_pass(0, "24");
    let pass = sc::subst(pass);
    let input = sc::cat(&[&pass, b"\n", &pass, b"\n"]);
    feed(
        0,
        kexec(
            k,
            pod,
            true,
            &[b"ntfy", b"user", b"add", b"--role=user", user.as_bytes()],
        ),
        &input,
        Some(to_stderr()),
    );
    let mut acc = kexec(
        k,
        pod,
        false,
        &[
            b"ntfy",
            b"access",
            user.as_bytes(),
            topic,
            access.as_bytes(),
        ],
    );
    acc.stdout(to_stderr());
    run(0, &mut acc, false);
    warn(&sc::cat(&[
        format!("\u{2713} created '{}' ({} on '", user, access).as_bytes(),
        topic,
        b"')",
    ]));
    sc::cat(&[user.as_bytes(), b":", &pass])
}

fn bootstrap_run(args: &[Vec<u8>]) -> Res<i32> {
    default_kubeconfig(50)?;
    let k = kctx();
    let mut topic = arg(args, 1);
    if topic.is_empty() {
        topic = read_prompt("ntfy topic name (e.g. vitruvian-alerts): ")?;
    }
    if !valid_topic(&topic) {
        return die(
            2,
            &sc::cat(&[
                b"ERROR: topic must be non-empty and match [a-zA-Z0-9_-]+, got: '",
                &topic,
                b"'",
            ]),
        );
    }
    need_tools(&["kubectl", "openssl"], false)?;
    let pod = find_pod(&k)?;
    let (_, existing) = capture_quiet(0, kexec(&k, &pod, false, &[b"ntfy", b"user", b"list"]));

    warn(&sc::cat(&[
        b"Bootstrapping ntfy users for topic '",
        &topic,
        b"' (pod ",
        &pod,
        b")...",
    ]));
    let am = create_user(&k, &pod, &existing, &topic, "alertmanager", "write-only");
    let james = create_user(&k, &pod, &existing, &topic, "james", "read-only");

    warn(b"");
    warn(
        b"Alertmanager webhook password (feed straight into seal-alert-ntfy, never commit it raw):",
    );
    if !am.is_empty() {
        // ${AM_CRED#*:}
        let pass = match am.iter().position(|&c| c == b':') {
            Some(i) => &am[i + 1..],
            None => &am[..],
        };
        warn(&sc::cat(&[
            b"  bazel run //tools/gitops:seal-alert-ntfy -- '",
            pass,
            b"'",
        ]));
    } else {
        warn(
            "  (user already existed \u{2014} rotate its password first if you need it again)"
                .as_bytes(),
        );
    }
    warn(b"");
    warn(b"James's ntfy app / web UI login (save to a password manager now):");
    if !james.is_empty() {
        warn(&sc::cat(&[
            b"  server: https://ntfy.ipv1337.dev   topic: ",
            &topic,
            b"   ",
            &james,
        ]));
    } else {
        warn(
            "  (user already existed \u{2014} rotate its password if you need it again)".as_bytes(),
        );
    }
    Ok(0)
}

// ---------------------------------------------------------------------------
// ntfy_manage_users.sh
// ---------------------------------------------------------------------------

pub fn manage(args: &[Vec<u8>]) -> i32 {
    match manage_run(args) {
        Ok(c) | Err(c) => c,
    }
}

fn require_role(role: &[u8]) -> Res<()> {
    match role {
        b"admin" | b"user" => Ok(()),
        _ => die(
            2,
            &sc::cat(&[b"ERROR: role must be 'admin' or 'user', got '", role, b"'"]),
        ),
    }
}

/// `PASS="${NTFY_PASSWORD:-$(gen_pass)}"`: the status is gen_pass's
/// pipeline (openssl's) when it ran.
fn password() -> Res<Vec<u8>> {
    if sc::env_set_nonempty("NTFY_PASSWORD") {
        return Ok(sc::env_or_empty("NTFY_PASSWORD"));
    }
    let (st, pass) = openssl_pass(0, "48");
    if st != 0 {
        return Err(st);
    }
    Ok(sc::subst(pass))
}

/// A simple command under `set -e`: its status ends the run when non-zero.
fn must(st: i32) -> Res<()> {
    if st != 0 {
        Err(st)
    } else {
        Ok(())
    }
}

/// `kexec ntfy user list 2>&1 | grep -qE "^user ${USER} "`.
fn user_listed(k: &[u8], pod: &[u8], user: &[u8]) -> bool {
    let mut c = kexec(k, pod, false, &[b"ntfy", b"user", b"list"]);
    c.stdout(Stdio::piped()).stderr(Stdio::piped());
    // stdout and stderr interleaved into one stream, as 2>&1 into a pipe.
    let (st, text) = match c.output() {
        Ok(o) => {
            let mut t = o.stdout;
            t.extend_from_slice(&o.stderr);
            (sc::status_code(o.status), t)
        }
        Err(e) => (sc::spawn_failure_status(&e), sc::spawn_diag(0, &c, &e)),
    };
    let want = sc::cat(&[b"user ", user, b" "]);
    st == 0 && text.split(|&c| c == b'\n').any(|l| l.starts_with(&want))
}

fn manage_run(args: &[Vec<u8>]) -> Res<i32> {
    let sub = param(
        args,
        1,
        54,
        "usage: ntfy-user-SUBCMD (list|add|del|change-pass|change-role|access)",
    )?;
    let a = &args[1..];
    default_kubeconfig(57)?;
    let k = kctx();
    let url = sc::env_or("NTFY_URL", b"https://ntfy.ipv1337.dev");
    let repo = sc::env_or("GH_REPO", b"VitruvianSoftware/vitruvian-core");
    if !have("kubectl") {
        return die(1, b"ERROR: kubectl not found on PATH.");
    }
    let pod = find_pod(&k)?;
    let exec = |args: &[&[u8]]| run(0, &mut kexec(&k, &pod, false, args), false);

    match sub.as_slice() {
        b"list" => must(exec(&[b"ntfy", b"user", b"list"]))?,
        b"add" => {
            let user = param(a, 1, 90, "usage: ntfy-user-add USERNAME [admin|user]")?;
            assign_exported("USER", &user);
            let role = {
                let r = arg(a, 2);
                if r.is_empty() {
                    b"user".to_vec()
                } else {
                    r
                }
            };
            require_role(&role)?;
            if !have("openssl") {
                return die(1, b"ERROR: openssl not found on PATH.");
            }
            let pass = password()?;
            let input = sc::cat(&[&pass, b"\n", &pass, b"\n"]);
            must(feed(
                96,
                kexec(
                    &k,
                    &pod,
                    true,
                    &[
                        b"ntfy",
                        b"user",
                        b"add",
                        &sc::cat(&[b"--role=", &role]),
                        &user,
                    ],
                ),
                &input,
                None,
            ))?;
            warn(&sc::cat(&[
                b"\xe2\x9c\x93 created '",
                &user,
                b"' (role: ",
                &role,
                b")",
            ]));
            if !sc::env_set_nonempty("NTFY_PASSWORD") {
                say(&sc::cat(&[
                    b"password (save now, unrecoverable after this): ",
                    &pass,
                ]));
            }
            warn(&sc::cat(&[
                "next: grant topic access \u{2014} bazel run //tools/gitops:ntfy-user-access -- "
                    .as_bytes(),
                &user,
                b" TOPIC read-only",
            ]));
        }
        b"del" => {
            let user = param(a, 1, 103, "usage: ntfy-user-del USERNAME")?;
            assign_exported("USER", &user);
            must(exec(&[b"ntfy", b"user", b"del", &user]))?;
            warn(&sc::cat(&[b"\xe2\x9c\x93 deleted '", &user, b"'"]));
        }
        b"change-pass" => {
            let user = param(
                a,
                1,
                108,
                "usage: ntfy-user-change-pass USERNAME [--gh-secret NAME]",
            )?;
            assign_exported("USER", &user);
            let mut gh_secret = Vec::new();
            if arg(a, 2) == b"--gh-secret" {
                gh_secret = param(
                    a,
                    3,
                    111,
                    "usage: ntfy-user-change-pass USERNAME --gh-secret NAME",
                )?;
                for tool in ["gh", "curl"] {
                    if !have(tool) {
                        return die(1, format!("ERROR: {} not found on PATH.", tool).as_bytes());
                    }
                }
                if run_quiet(0, cmd("gh", &[b"auth", b"status"])) != 0 {
                    return die(1, b"ERROR: gh is not signed in -- run 'gh auth login'.");
                }
                // Fail BEFORE touching the password if the account isn't there.
                if !user_listed(&k, &pod, &user) {
                    return die(
                        1,
                        &sc::cat(&[
                            b"ERROR: no ntfy user '",
                            &user,
                            b"' -- create it first (ntfy-user-add).",
                        ]),
                    );
                }
            }
            if !have("openssl") {
                return die(1, b"ERROR: openssl not found on PATH.");
            }
            let pass = password()?;
            let input = sc::cat(&[&pass, b"\n", &pass, b"\n"]);
            must(feed(
                124,
                kexec(&k, &pod, true, &[b"ntfy", b"user", b"change-pass", &user]),
                &input,
                None,
            ))?;
            warn(&sc::cat(&[
                b"\xe2\x9c\x93 rotated password for '",
                &user,
                b"'",
            ]));
            if !gh_secret.is_empty() {
                let set = cmd("gh", &[b"secret", b"set", &gh_secret, b"--repo", &repo]);
                if feed(129, set, &pass, Some(Stdio::null())) != 0 {
                    return die(
                        1,
                        &sc::cat(&[
                            b"ERROR: could not store ",
                            &gh_secret,
                            b" -- CI can't log in to ntfy until you re-run this.",
                        ]),
                    );
                }
                warn(&sc::cat(&[
                    b"\xe2\x9c\x93 stored it as the ",
                    &repo,
                    b" secret ",
                    &gh_secret,
                    b" (never printed)",
                ]));
                // The credentials go to curl on stdin, never on its command line.
                let cfg = sc::cat(&[b"user = \"", &user, b":", &pass, b"\"\n"]);
                let check = cmd(
                    "curl",
                    &[
                        b"-fsS",
                        b"-o",
                        b"/dev/null",
                        b"--config",
                        b"-",
                        &sc::cat(&[&url, b"/v1/account"]),
                    ],
                );
                if feed(136, check, &cfg, None) == 0 {
                    warn(&sc::cat(&[
                        b"\xe2\x9c\x93 ",
                        &url,
                        b" accepts the new password",
                    ]));
                } else {
                    return die(
                        1,
                        &sc::cat(&[
                            b"ERROR: ",
                            &url,
                            b" rejected the new password -- re-run to rotate again.",
                        ]),
                    );
                }
            } else if !sc::env_set_nonempty("NTFY_PASSWORD") {
                say(&sc::cat(&[
                    b"new password (save now, unrecoverable after this): ",
                    &pass,
                ]));
            }
        }
        b"change-role" => {
            let user = param(
                a,
                1,
                145,
                "usage: ntfy-user-change-role USERNAME admin|user",
            )?;
            assign_exported("USER", &user);
            let role = param(
                a,
                2,
                146,
                "usage: ntfy-user-change-role USERNAME admin|user",
            )?;
            require_role(&role)?;
            must(exec(&[b"ntfy", b"user", b"change-role", &user, &role]))?;
            warn(&sc::cat(&[
                b"\xe2\x9c\x93 changed role for '",
                &user,
                b"' to '",
                &role,
                b"'",
            ]));
        }
        b"access" => {
            let user = param(
                a,
                1,
                152,
                "usage: ntfy-user-access USERNAME TOPIC PERMISSION",
            )?;
            assign_exported("USER", &user);
            let topic = param(
                a,
                2,
                153,
                "usage: ntfy-user-access USERNAME TOPIC PERMISSION",
            )?;
            let perm = param(
                a,
                3,
                154,
                "usage: ntfy-user-access USERNAME TOPIC PERMISSION (read-write|read-only|write-only|deny)",
            )?;
            must(exec(&[b"ntfy", b"access", &user, &topic, &perm]))?;
            warn(&sc::cat(&[
                b"\xe2\x9c\x93 set '",
                &user,
                b"' access to '",
                &topic,
                b"': ",
                &perm,
            ]));
        }
        _ => {
            return die(
                2,
                &sc::cat(&[
                    b"ERROR: unknown subcommand '",
                    &sub,
                    b"' (list|add|del|change-pass|change-role|access)",
                ]),
            )
        }
    }
    Ok(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn word_boundaries_like_grep() {
        assert!(has_word(b"user james (role: user)", b"james"));
        assert!(!has_word(b"user jamesb (role: user)", b"james"));
        assert!(!has_word(b"user xjames", b"james"));
        assert!(has_word(b"james", b"james"));
        assert!(!has_word(b"", b"james"));
        assert!(has_word(b"a\nuser alertmanager\n", b"alertmanager"));
    }

    #[test]
    fn topics() {
        assert!(valid_topic(b"vitruvian-alerts"));
        assert!(valid_topic(b"a_b-9"));
        assert!(!valid_topic(b""));
        assert!(!valid_topic(b"a b"));
        assert!(!valid_topic(b"a/b"));
    }
}
