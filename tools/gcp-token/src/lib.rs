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

//! gcp-token: gcp-token.sh in Rust. Print a short-lived GCP access token for
//! a declared account: local gcloud first, then Pulumi ESC when configured,
//! then a homelab broker over the tailnet (ssh). Same sources in the same
//! order, same environment variables, same argv to every child, same stdout
//! (the bare token), stderr and exit codes as the script; see gcp-token.sh
//! for why each step is the way it is.

use shell_compat as sh;
use std::process::Command;

const DEFAULT_BROKERS: &[u8] =
    b"fedora,nuc9i5,nuc9i9,james-mbp16,james-macbook-pro,james-mbp,james-mbp32";

/// The characters an account may hold: letters, digits and `._%@+-`
/// (gcp-token.sh's `tr -d 'a-zA-Z0-9._%@+-'`, in the C locale).
fn allowed(c: u8) -> bool {
    c.is_ascii_alphanumeric() || b"._%@+-".contains(&c)
}

/// `disallowed_chars` captured with `$(...)`: the bytes `tr` would not
/// delete, trailing newlines dropped by the substitution.
pub fn disallowed_chars(account: &[u8]) -> Vec<u8> {
    sh::subst(account.iter().copied().filter(|&c| !allowed(c)).collect())
}

/// One byte as `od -c` prints it (C locale), before the field padding.
fn od_c_field(c: u8) -> String {
    match c {
        0 => "\\0".into(),
        7 => "\\a".into(),
        8 => "\\b".into(),
        12 => "\\f".into(),
        b'\n' => "\\n".into(),
        b'\r' => "\\r".into(),
        b'\t' => "\\t".into(),
        11 => "\\v".into(),
        0x20..=0x7e => (c as char).to_string(),
        _ => format!("{:03o}", c),
    }
}

/// `$(printf '%s' "$bad" | od -An -c | tr -s ' ' | sed 's/^ //;s/ $//')`.
pub fn describe_bytes(bad: &[u8]) -> Vec<u8> {
    let mut lines: Vec<String> = Vec::new();
    let mut prev: Option<&[u8]> = None;
    let mut starred = false;
    for chunk in bad.chunks(16) {
        // od folds a full line identical to the one before into a single `*`.
        if chunk.len() == 16 && prev == Some(chunk) {
            if !starred {
                lines.push("*".into());
                starred = true;
            }
            continue;
        }
        starred = false;
        prev = Some(chunk);
        let mut raw = String::with_capacity(chunk.len() * 4);
        for &c in chunk {
            use std::fmt::Write as _;
            let _ = write!(raw, "{:>4}", od_c_field(c));
        }
        // tr -s ' ': squeeze runs of spaces.
        let mut sq = String::with_capacity(raw.len());
        for ch in raw.chars() {
            if ch == ' ' && sq.ends_with(' ') {
                continue;
            }
            sq.push(ch);
        }
        let sq = sq.strip_prefix(' ').unwrap_or(&sq).to_string();
        let sq = sq.strip_suffix(' ').unwrap_or(&sq).to_string();
        lines.push(sq);
    }
    sh::subst(lines.join("\n").into_bytes())
}

/// `case "$ACCOUNT" in *?@?*.?*)`: something, an `@`, something, then a `.`
/// with something after it.
pub fn looks_like_email(a: &[u8]) -> bool {
    for (i, &c) in a.iter().enumerate() {
        if c != b'@' || i == 0 {
            continue;
        }
        // `?` after the @, then `*`, then `.`, then `?` and `*`.
        let start = i + 2;
        if start > a.len() {
            continue;
        }
        if a[start..]
            .iter()
            .enumerate()
            .any(|(j, &d)| d == b'.' && start + j + 1 < a.len())
        {
            return true;
        }
    }
    false
}

/// `is_token`: non-empty and at least `${MIN_TOKEN_LEN:-40}` characters. A
/// MIN_TOKEN_LEN that is not a number makes `[` fail, so nothing is a token.
pub fn is_token(s: &[u8]) -> bool {
    if s.is_empty() {
        return false;
    }
    let min = sh::env_or("MIN_TOKEN_LEN", b"40");
    let min = String::from_utf8_lossy(&min).trim().to_string();
    match min.parse::<i64>() {
        Ok(m) => (sh::char_len(s) as i64) >= m,
        Err(_) => false,
    }
}

/// The command run ON the broker: `$(remote_cmd)` from gcp-token.sh, with the
/// heredoc's backslash-newlines joined exactly as bash joins them.
pub fn remote_cmd(account: &[u8]) -> Vec<u8> {
    let mut v = Vec::new();
    v.extend_from_slice(
        b"G=\"$(command -v gcloud 2>/dev/null)\"\n\
[ -n \"$G\" ] || G=\"$(\"${SHELL:-/bin/sh}\" -lc 'command -v gcloud' 2>/dev/null)\"\n\
if [ -z \"$G\" ]; then\n\
\x20\x20for p in \"$HOME/google-cloud-sdk/bin/gcloud\" /opt/homebrew/bin/gcloud            \
/opt/homebrew/share/google-cloud-sdk/bin/gcloud /usr/local/bin/gcloud            \
/usr/local/share/google-cloud-sdk/bin/gcloud /snap/bin/gcloud; do\n\
\x20\x20\x20\x20[ -x \"$p\" ] && G=\"$p\" && break\n\
\x20\x20done\n\
fi\n\
[ -n \"$G\" ] || { echo \"gcloud: command not found\" >&2; exit 127; }\n\
exec \"$G\" auth print-access-token --account=",
    );
    v.extend_from_slice(account);
    sh::subst(v)
}

/// Why a broker did not mint: the classifier in try_broker, first match wins.
pub fn classify(err: &[u8], tok: &[u8], account: &[u8]) -> Vec<u8> {
    if sh::grep_qi(err, &["Reauthentication failed", "reauth"]) {
        b"REAUTH LAPSED \xe2\x80\x94 this node's login for the account has expired (another node may still mint)".to_vec()
    } else if sh::grep_qi(err, &["command not found", "No such file"]) {
        b"no gcloud installed".to_vec()
    } else if sh::grep_qi(
        err,
        &[
            "not have any valid credentials",
            "no credentialed account",
            "is not a valid account",
            "Could not find",
            "not a valid account",
        ],
    ) {
        sh::cat(&[b"gcloud present but not logged in as ", account])
    } else if sh::grep_qi(
        err,
        &[
            "Connection refused",
            "timed out",
            "unreachable",
            "Host key",
            "Permission denied",
        ],
    ) {
        b"unreachable over the tailnet".to_vec()
    } else if !tok.is_empty() {
        format!(
            "returned something too short to be a token ({} chars)",
            sh::char_len(tok)
        )
        .into_bytes()
    } else {
        sh::first_line(err)
    }
}

/// The brokers in the order they are tried: the cached winner first when it
/// is in the list, then the list in its declared order, skipping the cached
/// name. `cached` is None when there was no readable cache (the script then
/// compares against an unset `$_cached`, i.e. the environment's).
pub fn order_brokers(hosts: &[u8], cached: Option<&[u8]>) -> Vec<Vec<u8>> {
    let mut ordered = Vec::new();
    if let Some(c) = cached {
        let list = sh::cat(&[b",", hosts, b","]);
        let needle = sh::cat(&[b",", c, b","]);
        if sh::contains(&list, &needle) && !c.is_empty() {
            ordered.push(c.to_vec());
        }
        // `_ordered="$_cached"` with an empty cache leaves nothing to add.
    }
    let words: Vec<u8> = hosts
        .iter()
        .map(|&c| if c == b',' { b' ' } else { c })
        .collect();
    let skip = cached
        .map(<[u8]>::to_vec)
        .or_else(|| sh::env("_cached"))
        .unwrap_or_default();
    for w in sh::ifs_split(&words) {
        if w == skip {
            continue;
        }
        ordered.push(w);
    }
    ordered
}

fn die(msg: &[u8]) -> i32 {
    sh::err(&sh::cat(&[b"gcp-token: ", msg, b"\n"]));
    1
}

struct Broker {
    ssh: Vec<u8>,
    user: Vec<u8>,
    opts: Vec<Vec<u8>>,
    account: Vec<u8>,
    report: Vec<u8>,
}

impl Broker {
    /// try_broker: the token on success; on failure, why, appended to the report.
    fn try_host(&mut self, host: &[u8]) -> Option<Vec<u8>> {
        let target = sh::cat(&[&self.user, b"@", host]);
        let remote = remote_cmd(&self.account);
        let mut cmd = if sh::which(b"timeout").is_some() {
            let mut c = Command::new("timeout");
            c.arg("45").arg(sh::os(&self.ssh));
            c
        } else {
            Command::new(sh::os(&self.ssh))
        };
        for o in &self.opts {
            cmd.arg(sh::os(o));
        }
        cmd.arg(sh::os(&target)).arg(sh::os(&remote));
        let ran = sh::capture(280, &mut cmd);
        let tok = sh::subst(sh::strip_cr_lf(&ran.stdout));
        if is_token(&tok) {
            return Some(tok);
        }
        let why = classify(&ran.stderr, &tok, &self.account);
        self.report.extend_from_slice(b"  ");
        self.report.extend(sh::pad_right(host, 22));
        self.report.push(b' ');
        self.report.extend(why);
        self.report.push(b'\n');
        None
    }
}

/// Remember the winning broker, best-effort, under umask 077.
fn cache_winner(cache: &[u8], host: &[u8]) {
    use std::os::unix::fs::DirBuilderExt;
    let dir = sh::dirname(cache);
    if std::fs::DirBuilder::new()
        .recursive(true)
        .mode(0o700)
        .create(sh::path(&dir))
        .is_err()
    {
        return;
    }
    // `printf ... >"$BROKER_CACHE" 2>/dev/null`: the redirection to the cache
    // is opened before stderr is silenced, so bash reports a failed open.
    if let Err(e) = sh::write_file(cache, &sh::cat(&[host, b"\n"]), 0o600) {
        sh::redirect_error(330, cache, &e);
    }
}

/// The whole tool; the process exit code.
pub fn run(args: &[Vec<u8>]) -> i32 {
    let hosts = match sh::env("VITRUVIAN_GCP_BROKERS") {
        Some(v) if !v.is_empty() => v,
        _ => sh::env_or("VITRUVIAN_GCP_BROKER", DEFAULT_BROKERS),
    };
    let user = sh::env_or("VITRUVIAN_GCP_BROKER_USER", b"james");
    let cache = match sh::env("VITRUVIAN_GCP_BROKER_CACHE") {
        Some(v) if !v.is_empty() => v,
        _ => sh::cat(&[
            &sh::env_or_empty("HOME"),
            b"/.config/vitruvian-core/cloud/gcp-broker",
        ]),
    };
    let ssh = sh::env_or("SSH_BIN", b"ssh");
    let pulumi = sh::env_or("PULUMI_BIN", b"pulumi");
    let gcloud = sh::env_or("GCLOUD_BIN", b"gcloud");
    let socks_port = sh::env_or("VITRUVIAN_SOCKS_PORT", b"1055");

    let account = args.first().cloned().unwrap_or_default();
    if account.is_empty() {
        return die(b"usage: gcp-token.sh <account-email>");
    }

    let bad = disallowed_chars(&account);
    if !bad.is_empty() {
        return die(&sh::cat(&[
            b"invalid account '",
            &account,
            b"' (expected an email address) (disallowed character(s): ",
            &describe_bytes(&bad),
            b")",
        ]));
    }
    if !looks_like_email(&account) {
        return die(&sh::cat(&[
            b"invalid account '",
            &account,
            b"' (expected an email address)",
        ]));
    }

    // --- 1. local credentials ------------------------------------------------
    if sh::which(&gcloud).is_some() {
        if !is_token(&sh::env_or_empty("CLOUDSDK_AUTH_ACCESS_TOKEN")) {
            std::env::remove_var("CLOUDSDK_AUTH_ACCESS_TOKEN");
        }
        let mut c = Command::new(sh::os(&gcloud));
        c.arg("auth")
            .arg("print-access-token")
            .arg(sh::os(&sh::cat(&[b"--account=", &account])));
        let ran = sh::capture(160, &mut c);
        if ran.ok() {
            let tok = sh::subst(ran.stdout);
            if is_token(&tok) {
                sh::out(&tok);
                return 0;
            }
        }
    }

    // --- 1.5 Pulumi ESC ------------------------------------------------------
    let esc_env = sh::env_or_empty("VITRUVIAN_ESC_ENV");
    if !esc_env.is_empty() && sh::which(&pulumi).is_some() {
        let esc_path = sh::env_or("VITRUVIAN_ESC_PATH", b"gcp.login.accessToken");
        let mut c = Command::new(sh::os(&pulumi));
        c.arg("env")
            .arg("open")
            .arg(sh::os(&esc_env))
            .arg(sh::os(&esc_path))
            .arg("--format")
            .arg("string");
        let ran = sh::capture(194, &mut c);
        let tok = sh::subst(sh::strip_cr_lf(&ran.stdout));
        if ran.ok() && is_token(&tok) {
            sh::err(&sh::cat(&[
                b"gcp-token: token minted by Pulumi ESC (",
                &esc_env,
                b") \xe2\x80\x94 the identity is that\n",
                b"  environment's service account, NOT the requested '",
                &account,
                b"'.\n",
            ]));
            sh::out(&tok);
            return 0;
        }
        sh::err(&sh::cat(&[
            b"gcp-token: Pulumi ESC (",
            &esc_env,
            b") did not yield a token; falling back to the tailnet broker\n",
        ]));
        sh::err(&sh::indent(&ran.stderr));
    }

    // --- 2. mint over the tailnet ---------------------------------------------
    if sh::which(&ssh).is_none() {
        return die(&sh::cat(&[
            b"no local credentials for ",
            &account,
            b" and ssh is not installed to reach a broker",
        ]));
    }
    let mut opts: Vec<Vec<u8>> = [
        "StrictHostKeyChecking=accept-new",
        "GSSAPIAuthentication=no",
        "PreferredAuthentications=publickey",
        "BatchMode=yes",
        "ConnectTimeout=10",
    ]
    .iter()
    .flat_map(|o| [b"-o".to_vec(), o.as_bytes().to_vec()])
    .collect();
    if sh::which(b"nc").is_some() {
        let mut c = Command::new("nc");
        c.arg("-z")
            .arg("localhost")
            .arg(sh::os(&socks_port))
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null());
        if sh::status(236, &mut c, true) == 0 {
            opts.push(b"-o".to_vec());
            opts.push(sh::cat(&[
                b"ProxyCommand=nc -X 5 -x localhost:",
                &socks_port,
                b" %h %p",
            ]));
        }
    }

    let cached = if sh::is_readable(&cache) {
        let raw = std::fs::read(sh::path(&cache)).unwrap_or_default();
        Some(
            raw.into_iter()
                .filter(|c| !c.is_ascii_whitespace() && *c != 0x0b)
                .collect::<Vec<u8>>(),
        )
    } else {
        None
    };
    let ordered = order_brokers(&hosts, cached.as_deref());

    let mut broker = Broker {
        ssh,
        user,
        opts,
        account: account.clone(),
        report: Vec::new(),
    };
    let mut tok: Vec<u8> = Vec::new();
    for h in &ordered {
        if let Some(t) = broker.try_host(h) {
            cache_winner(&cache, h);
            tok = t;
            break;
        }
    }

    if tok.is_empty() {
        let a = &account;
        let mut e = sh::cat(&[b"gcp-token: no broker could mint a token for ", a, b"\n"]);
        e.extend_from_slice(&broker.report);
        for line in [
            sh::cat(&[b"  Fixes, by cause:"]),
            sh::cat(&["    \u{b7} REAUTH LAPSED    \u{2192} that NODE's session expired, not the account. Any node with".as_bytes()]),
            sh::cat(&["                         a fresh login still mints, which is why brokers are a list \u{2014}".as_bytes()]),
            sh::cat(&[b"                         every one above was already tried. Re-login there with"]),
            sh::cat(&[b"                         'gcloud auth login ", a, "', or widen Admin console \u{2192}".as_bytes()]),
            sh::cat(&["                         Security \u{2192} Google Cloud session control to make it recur less.".as_bytes()]),
            sh::cat(&["    \u{b7} no gcloud        \u{2192} install the SDK on that node".as_bytes()]),
            sh::cat(&["    \u{b7} not logged in    \u{2192} gcloud auth login ".as_bytes(), a, b"   (once, on that node)"]),
            sh::cat(&["    \u{b7} unreachable      \u{2192} tailscale status".as_bytes()]),
            sh::cat(&["    \u{b7} other brokers    \u{2192} VITRUVIAN_GCP_BROKERS=host1,host2".as_bytes()]),
        ] {
            e.extend(line);
            e.push(b'\n');
        }
        sh::err(&e);
        return 1;
    }

    if !is_token(&tok) {
        return die(format!(
            "the broker returned something too short to be an access token ({} chars)",
            sh::char_len(&tok)
        )
        .as_bytes());
    }
    sh::out(&tok);
    0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn disallowed_chars_keeps_only_outsiders() {
        assert_eq!(disallowed_chars(b"james@vitruviansoftware.dev"), b"");
        assert_eq!(disallowed_chars(b"user+tag@example.co.uk"), b"");
        assert_eq!(disallowed_chars(b"a@b.c; touch x"), b";  ");
        // $(...) drops a trailing newline, so it is not "disallowed".
        assert_eq!(disallowed_chars(b"a@b.c\n"), b"");
        assert_eq!(disallowed_chars(b"a@b.c\t"), b"\t");
    }

    #[test]
    fn describe_bytes_matches_od_pipeline() {
        assert_eq!(describe_bytes(b"\t"), b"\\t");
        assert_eq!(describe_bytes(b"; "), b";");
        assert_eq!(describe_bytes(b" ;"), b";");
        assert_eq!(describe_bytes(b";\x01\x7f"), b"; 001 177");
        assert_eq!(describe_bytes(b"\xc2\xa0"), b"302 240");
        assert_eq!(describe_bytes(b"x\ny"), b"x \\n y");
        let dup = [b';'; 40];
        assert_eq!(
            describe_bytes(&dup),
            b"; ; ; ; ; ; ; ; ; ; ; ; ; ; ; ;\n*\n; ; ; ; ; ; ; ;"
        );
    }

    #[test]
    fn email_shape() {
        assert!(looks_like_email(b"a@b.c"));
        assert!(looks_like_email(b"james@vitruviansoftware.dev"));
        assert!(!looks_like_email(b"not-an-email"));
        assert!(!looks_like_email(b"@b.c"));
        assert!(!looks_like_email(b"a@.c"));
        assert!(!looks_like_email(b"a@b."));
        assert!(!looks_like_email(b"a@bc"));
        assert!(looks_like_email(b"a@b@c.d"));
    }

    #[test]
    fn remote_cmd_carries_account_and_fallbacks() {
        let r = String::from_utf8(remote_cmd(b"x@y.z")).unwrap();
        assert!(r.ends_with("exec \"$G\" auth print-access-token --account=x@y.z"));
        assert!(r.contains("/opt/homebrew/bin/gcloud            /opt/homebrew/share"));
        assert!(r.contains("-lc 'command -v gcloud'"));
        assert_eq!(r.lines().count(), 9);
    }

    #[test]
    fn classifier_order() {
        let a = b"me@x.dev";
        assert!(
            String::from_utf8(classify(b"Reauthentication failed", b"", a))
                .unwrap()
                .starts_with("REAUTH LAPSED")
        );
        assert_eq!(
            classify(b"gcloud: command not found", b"", a),
            b"no gcloud installed"
        );
        assert_eq!(
            classify(b"does not have any valid credentials", b"", a),
            b"gcloud present but not logged in as me@x.dev"
        );
        assert_eq!(
            classify(b"Connection timed out", b"", a),
            b"unreachable over the tailnet"
        );
        assert_eq!(
            classify(b"", b"short", a),
            b"returned something too short to be a token (5 chars)"
        );
        assert_eq!(classify(b"first\nsecond", b"", a), b"first");
        assert_eq!(classify(b"", b"", a), b"");
    }

    #[test]
    fn broker_order() {
        let o = order_brokers(b"a,b,c", Some(b"b"));
        assert_eq!(o, vec![b"b".to_vec(), b"a".to_vec(), b"c".to_vec()]);
        let o = order_brokers(b"a,b", Some(b"ghost"));
        assert_eq!(o, vec![b"a".to_vec(), b"b".to_vec()]);
        let o = order_brokers(b"a,,b", Some(b""));
        assert_eq!(o, vec![b"a".to_vec(), b"b".to_vec()]);
        // A cached name not delimited by commas alone is dropped from the walk.
        let o = order_brokers(b"a, good", Some(b"good"));
        assert_eq!(o, vec![b"a".to_vec()]);
    }
}
