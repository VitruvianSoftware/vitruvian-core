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

//! github-app-key: set-key.sh in Rust. Store (or rotate) a GitHub App's
//! private key as a repo secret, after proving -- by signing an App JWT with
//! it and asking GitHub -- that it is the right App's key, that the App is
//! installed, and (where it must be) not a ruleset bypass actor. `--create`
//! runs GitHub's App Manifest flow first. The key goes to `gh secret set` on
//! stdin and is never printed. Same calls to gh and openssl, same output and
//! exit codes as the script; the manifest and the JWT claims are JSON made by
//! serde_json, so an odd character in a value is escaped, not spliced in.

use serde::ser::{SerializeMap, Serializer};
use serde::Serialize;
use shell_compat as sh;
use std::process::{Command, Stdio};

/// name | App slug | client ID | secret name | secret stores | must-not-bypass | permissions
pub const APPS: &str = "
renovate|vitruvian-renovate|Iv23liR87u9iun3Br4GZ|RENOVATE_APP_PRIVATE_KEY|actions|yes|contents=write,issues=write,pull_requests=write
copybara-sync|vitruvian-copybara-sync|Iv23li2K1dcn4V98uOW3|SYNC_APP_PRIVATE_KEY|actions dependabot|no|contents=write,pull_requests=write
";

pub struct Exit(pub i32);

struct Colors {
    bold: &'static str,
    reset: &'static str,
    green: &'static str,
    yellow: &'static str,
    red: &'static str,
}

impl Colors {
    fn detect() -> Colors {
        if sh::stdout_is_tty() {
            Colors {
                bold: "\x1b[1m",
                reset: "\x1b[0m",
                green: "\x1b[32m",
                yellow: "\x1b[33m",
                red: "\x1b[31m",
            }
        } else {
            Colors {
                bold: "",
                reset: "",
                green: "",
                yellow: "",
                red: "",
            }
        }
    }

    fn ok(&self, msg: &[u8]) {
        sh::out(&sh::cat(&[
            b"  ",
            self.green.as_bytes(),
            "\u{2713}".as_bytes(),
            self.reset.as_bytes(),
            b" ",
            msg,
            b"\n",
        ]));
    }

    fn warn(&self, msg: &[u8]) {
        sh::out(&sh::cat(&[
            b"  ",
            self.yellow.as_bytes(),
            b"!",
            self.reset.as_bytes(),
            b" ",
            msg,
            b"\n",
        ]));
    }

    fn die(&self, msg: &[u8]) -> Exit {
        sh::err(&sh::cat(&[
            b"  ",
            self.red.as_bytes(),
            "\u{2717}".as_bytes(),
            self.reset.as_bytes(),
            b" ",
            msg,
            b"\n",
        ]));
        Exit(1)
    }
}

/// One APPS row, split as `IFS='|' read -r _ SLUG CLIENT_ID ...` splits it.
pub struct App {
    pub slug: Vec<u8>,
    pub client_id: Vec<u8>,
    pub secret: Vec<u8>,
    pub stores: Vec<u8>,
    pub no_bypass: Vec<u8>,
    pub perms: Vec<u8>,
}

fn rows() -> impl Iterator<Item = &'static str> {
    APPS.split('\n').filter(|l| !l.trim().is_empty())
}

fn field(row: &str, i: usize) -> &str {
    row.split('|').nth(i).unwrap_or("")
}

/// `awk -F'|' -v a="$APP" '$1==a'` then the `read`.
pub fn lookup(app: &[u8]) -> Option<App> {
    let row = rows().find(|r| field(r, 0).as_bytes() == app)?;
    let f = sh::read_fields(row.as_bytes(), b"|", 7);
    Some(App {
        slug: f[1].clone(),
        client_id: f[2].clone(),
        secret: f[3].clone(),
        stores: f[4].clone(),
        no_bypass: f[5].clone(),
        perms: f[6].clone(),
    })
}

/// `--list`.
pub fn list() -> String {
    let mut out = String::new();
    for r in rows() {
        out.push_str(&format!(
            "{:<15} {:<26} -> {} ({})\n",
            field(r, 0),
            field(r, 1),
            field(r, 3),
            field(r, 4)
        ));
    }
    out
}

pub fn usage() -> String {
    let mut names = String::new();
    for r in rows() {
        names.push_str(field(r, 0));
        names.push(' ');
    }
    format!(
        "Usage: bazel run //tools/github-app-key -- <app> [--create | --pem <path>] [--yes]
       bazel run //tools/github-app-key -- --list

  <app>        one of: {}
  --create     create the App first (GitHub's manifest flow), then store its key
  --pem PATH   the downloaded private key (default: newest <slug>.*.private-key.pem in ~/Downloads)
  --yes        don't prompt; stores the key and deletes the .pem
",
        names
    )
}

/// `default_permissions`, in the order APPS lists them.
struct Perms<'a>(Vec<(&'a str, &'a str)>);

impl Serialize for Perms<'_> {
    fn serialize<S: Serializer>(&self, s: S) -> Result<S::Ok, S::Error> {
        let mut m = s.serialize_map(Some(self.0.len()))?;
        for (k, v) in &self.0 {
            m.serialize_entry(k, v)?;
        }
        m.end()
    }
}

#[derive(Serialize)]
struct Manifest<'a> {
    name: &'a str,
    url: String,
    redirect_url: &'a str,
    public: bool,
    default_permissions: Perms<'a>,
    default_events: [&'a str; 0],
}

/// The App manifest --create posts: the APPS permissions, no webhook events.
pub fn manifest(slug: &str, owner: &str, perms: &str) -> String {
    let pairs = if perms.is_empty() {
        Vec::new()
    } else {
        perms
            .split(',')
            .map(|kv| {
                let mut it = kv.splitn(3, '=');
                (it.next().unwrap_or(""), it.next().unwrap_or(""))
            })
            .collect()
    };
    serde_json::to_string(&Manifest {
        name: slug,
        url: format!("https://github.com/{}", owner),
        redirect_url: "http://localhost:8723/cb",
        public: false,
        default_permissions: Perms(pairs),
        default_events: [],
    })
    .expect("strings serialise")
}

#[derive(Serialize)]
struct Header {
    alg: &'static str,
    typ: &'static str,
}

#[derive(Serialize)]
struct Claims<'a> {
    iat: i64,
    exp: i64,
    iss: &'a str,
}

/// `openssl base64 -A | tr '+/' '-_' | tr -d '='`: unpadded base64url.
pub fn b64url(data: &[u8]) -> String {
    const T: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    let mut s = String::with_capacity(data.len() * 4 / 3 + 3);
    for c in data.chunks(3) {
        let n = (c[0] as u32) << 16
            | (*c.get(1).unwrap_or(&0) as u32) << 8
            | *c.get(2).unwrap_or(&0) as u32;
        s.push(T[(n >> 18) as usize & 63] as char);
        s.push(T[(n >> 12) as usize & 63] as char);
        if c.len() > 1 {
            s.push(T[(n >> 6) as usize & 63] as char);
        }
        if c.len() > 2 {
            s.push(T[n as usize & 63] as char);
        }
    }
    s
}

/// The App JWT's header and claims, encoded: `<header>.<claims>`.
pub fn unsigned_jwt(now: i64, client_id: &str) -> String {
    let h = serde_json::to_vec(&Header {
        alg: "RS256",
        typ: "JWT",
    })
    .expect("serialises");
    let c = serde_json::to_vec(&Claims {
        iat: now - 60,
        exp: now + 300,
        iss: client_id,
    })
    .expect("serialises");
    format!("{}.{}", b64url(&h), b64url(&c))
}

fn lossy(b: &[u8]) -> String {
    String::from_utf8_lossy(b).into_owned()
}

/// `ls -t DIR/SLUG.*.private-key.pem | head -n1`: the newest match, ties by name.
fn newest_download(dir: &[u8], slug: &[u8]) -> Vec<u8> {
    use std::os::unix::ffi::OsStrExt;
    let prefix = sh::cat(&[slug, b"."]);
    let suffix: &[u8] = b".private-key.pem";
    let mut found: Vec<(std::time::SystemTime, Vec<u8>)> = Vec::new();
    if let Ok(rd) = std::fs::read_dir(sh::path(dir)) {
        for e in rd.flatten() {
            let name = e.file_name().as_bytes().to_vec();
            if name.len() >= prefix.len() + suffix.len()
                && name.starts_with(&prefix)
                && name.ends_with(suffix)
            {
                let p = sh::cat(&[dir, b"/", &name]);
                let m = std::fs::metadata(sh::path(&p))
                    .and_then(|m| m.modified())
                    .unwrap_or(std::time::UNIX_EPOCH);
                found.push((m, p));
            }
        }
    }
    found.sort_by(|a, b| b.0.cmp(&a.0).then_with(|| a.1.cmp(&b.1)));
    found.into_iter().next().map(|x| x.1).unwrap_or_default()
}

/// `read -r VAR` from stdin, default IFS: surrounding blanks trimmed.
fn read_reply() -> Vec<u8> {
    sh::read_trim(&sh::read_stdin_line().0)
}

struct Run {
    c: Colors,
    repo: Vec<u8>,
    temp_pem: Option<Vec<u8>>,
}

impl Run {
    /// `gh api -H "Authorization: Bearer $jwt" ARGS`, stdout captured.
    fn app_api(&self, jwt: &str, args: &[&[u8]], quiet: bool) -> sh::Ran {
        let mut c = Command::new("gh");
        c.arg("api")
            .arg("-H")
            .arg(format!("Authorization: Bearer {}", jwt));
        for a in args {
            c.arg(sh::os(a));
        }
        if quiet {
            sh::capture(0, &mut c)
        } else {
            sh::capture_stdout(0, &mut c)
        }
    }

    fn ask(&self, assume_yes: bool, prompt: &[u8]) -> bool {
        if assume_yes {
            return true;
        }
        if !sh::stdin_is_tty() {
            return false;
        }
        sh::out(&sh::cat(&[b"? ", prompt, b" [y/N] "]));
        matches!(read_reply().as_slice(), b"y" | b"Y" | b"yes" | b"YES")
    }

    fn body(&mut self, args: &[Vec<u8>]) -> Result<(), Exit> {
        let downloads = match sh::env("GITHUB_APP_KEY_DOWNLOADS") {
            Some(v) if !v.is_empty() => v,
            _ => sh::cat(&[&sh::env_or_empty("HOME"), b"/Downloads"]),
        };

        let (mut app, mut pem, mut assume_yes, mut create) = (Vec::new(), Vec::new(), false, false);
        let mut i = 0;
        while i < args.len() {
            let a = args[i].as_slice();
            match a {
                b"--list" => {
                    sh::out(list().as_bytes());
                    return Err(Exit(0));
                }
                b"--pem" => {
                    pem = args.get(i + 1).cloned().unwrap_or_default();
                    // `shift 2` past the end fails, and set -e ends the run.
                    if i + 2 > args.len() {
                        return Err(Exit(1));
                    }
                    i += 2;
                }
                b"--yes" => {
                    assume_yes = true;
                    i += 1;
                }
                b"--create" => {
                    create = true;
                    i += 1;
                }
                b"-h" | b"--help" => {
                    sh::out(usage().as_bytes());
                    return Err(Exit(0));
                }
                _ if a.starts_with(b"-") => {
                    sh::err(usage().as_bytes());
                    return Err(Exit(2));
                }
                _ => {
                    app = a.to_vec();
                    i += 1;
                }
            }
        }
        if app.is_empty() {
            sh::err(usage().as_bytes());
            return Err(Exit(2));
        }
        let a = match lookup(&app) {
            Some(a) => a,
            None => {
                return Err(self
                    .c
                    .die(&sh::cat(&[b"unknown app '", &app, b"' (try --list)"])))
            }
        };
        let mut client_id = a.client_id.clone();
        if create && !pem.is_empty() {
            return Err(self
                .c
                .die(b"--create and --pem don't mix: --create gets the key from GitHub"));
        }
        sh::out(&sh::cat(&[
            b"\n",
            self.c.bold.as_bytes(),
            b"Store the ",
            &a.slug,
            b" private key as ",
            &a.secret,
            self.c.reset.as_bytes(),
            b"\n\n",
        ]));
        for tool in ["gh", "openssl"] {
            if sh::which(tool.as_bytes()).is_none() {
                return Err(self.c.die(format!("{} not found on PATH", tool).as_bytes()));
            }
        }
        let mut c = Command::new("gh");
        c.args(["auth", "status"])
            .stdout(Stdio::null())
            .stderr(Stdio::null());
        if sh::status(0, &mut c, true) != 0 {
            return Err(self.c.die(b"gh is not signed in -- run 'gh auth login'"));
        }

        let owner = self
            .repo
            .split(|&c| c == b'/')
            .next()
            .unwrap_or_default()
            .to_vec();
        let repo_name = match self.repo.iter().position(|&c| c == b'/') {
            Some(i) => self.repo[i + 1..].to_vec(),
            None => self.repo.clone(),
        };

        // ---- 0. create the App (--create only) ------------------------------
        if create {
            let m = manifest(&lossy(&a.slug), &lossy(&owner), &lossy(&a.perms));
            let form = self.write_form(&a.slug, &owner, m.as_bytes())?;
            sh::out(&sh::cat(&[
                b"  Creating ",
                &a.slug,
                b" with: ",
                &a.perms,
                b"\n",
            ]));
            let no_browser = sh::env_set_nonempty("GITHUB_APP_KEY_NO_BROWSER");
            let opener = if no_browser {
                None
            } else if sh::which(b"open").is_some() {
                Some("open")
            } else if sh::which(b"xdg-open").is_some() {
                Some("xdg-open")
            } else {
                None
            };
            match opener {
                Some(o) => {
                    // A failing opener ends the run (set -e), form left behind.
                    let st = sh::status(0, Command::new(o).arg(sh::os(&form)), false);
                    if st != 0 {
                        return Err(Exit(st));
                    }
                }
                None => sh::out(&sh::cat(&[
                    b"  Open this file in a browser: ",
                    &form,
                    b"\n",
                ])),
            }
            sh::out(b"  In the browser: check the permissions and click \"Create GitHub App\".\n");
            sh::out(b"  The browser then lands on a localhost page that will not load -- that is expected.\n");
            sh::out(b"? Paste the code= value from that address bar: ");
            let code = read_reply();
            let _ = std::fs::remove_file(sh::path(&form));
            if code.is_empty() {
                return Err(self.c.die(b"no code pasted -- re-run"));
            }
            let mut c = Command::new("gh");
            c.args(["api", "--method", "POST"])
                .arg(sh::os(&sh::cat(&[
                    b"/app-manifests/",
                    &code,
                    b"/conversions",
                ])))
                .arg("--jq")
                .arg(r#""\(.slug) \(.client_id) \(.pem | @base64)""#);
            let ran = sh::capture(0, &mut c);
            if !ran.ok() {
                return Err(self.c.die(
                    b"GitHub did not accept that code (they expire after an hour, and work once) -- re-run",
                ));
            }
            let conv = sh::subst(ran.stdout);
            let f = sh::read_fields(
                sh::lines(&conv).first().map(Vec::as_slice).unwrap_or(b""),
                b" \t\n",
                3,
            );
            let (new_slug, new_client, pem_b64) = (f[0].clone(), f[1].clone(), f[2].clone());
            client_id = new_client;
            if new_slug != a.slug {
                return Err(self.c.die(&sh::cat(&[
                    b"GitHub created '",
                    &new_slug,
                    b"', expected '",
                    &a.slug,
                    b"' -- was the name changed on the form? Delete that App and re-run",
                ])));
            }
            // printf '%s' "$pem_b64" | openssl base64 -d -A >"$PEM", but held
            // in memory until the person has installed the App: the key is
            // not left in $TMPDIR if they walk away or press Ctrl-C there.
            let mut c = Command::new("openssl");
            c.args(["base64", "-d", "-A"]);
            let decoded = pipe_capture(&mut c, &pem_b64);
            if decoded.status != 0 {
                return Err(Exit(decoded.status));
            }
            let key = decoded.stdout;
            self.c.ok(&sh::cat(&[
                b"created ",
                &a.slug,
                b" (client ID ",
                &client_id,
                b")",
            ]));
            sh::out(&sh::cat(&[
                b"  Now install it: https://github.com/apps/",
                &a.slug,
                b"/installations/new\n",
            ]));
            sh::out(&sh::cat(&[
                b"  Choose \"Only select repositories\" and pick ",
                &repo_name,
                b".\n",
            ]));
            sh::out(b"? Press Enter once it is installed... ");
            let _ = sh::read_stdin_line();
            pem = self.write_temp_key(&key)?;
            // From here the key is on disk: an interrupt is recorded, the
            // run stops at the next step, and `run` removes the key.
            sh::record_exit_signals();
        }
        if client_id.is_empty() {
            return Err(self.c.die(&sh::cat(&[
                b"no client ID for ",
                &app,
                b" yet -- run with --create, or add it to APPS",
            ])));
        }

        // ---- 1. the file ------------------------------------------------------
        interrupted()?;
        if pem.is_empty() {
            pem = newest_download(&downloads, &a.slug);
            if pem.is_empty() {
                return Err(self.c.die(&sh::cat(&[
                    b"no ",
                    &a.slug,
                    b".*.private-key.pem in ",
                    &downloads,
                    b" -- generate one at https://github.com/organizations/",
                    &owner,
                    b"/settings/apps/",
                    &a.slug,
                    b" or pass --pem",
                ])));
            }
        }
        if !sh::is_file(&pem) {
            return Err(self.c.die(&sh::cat(&[b"not a file: ", &pem])));
        }
        let mut c = Command::new("openssl");
        c.args(["pkey", "-in"])
            .arg(sh::os(&pem))
            .arg("-noout")
            .stdout(Stdio::null())
            .stderr(Stdio::null());
        if sh::status(0, &mut c, true) != 0 {
            return Err(self
                .c
                .die(&sh::cat(&[&pem, b" is not a readable private key"])));
        }
        self.c.ok(&sh::cat(&[b"private key file: ", &pem]));

        // ---- 2. prove it is this App's key ----------------------------------
        interrupted()?;
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_or(0, |d| d.as_secs() as i64);
        let unsigned = unsigned_jwt(now, &lossy(&client_id));
        let mut c = Command::new("openssl");
        c.args(["dgst", "-sha256", "-sign"])
            .arg(sh::os(&pem))
            .arg("-binary");
        let sig = pipe_capture(&mut c, unsigned.as_bytes());
        if sig.status != 0 {
            return Err(Exit(sig.status));
        }
        let jwt = format!("{}.{}", unsigned, b64url(&sig.stdout));

        let ran = self.app_api(&jwt, &[b"/app", b"--jq", b".slug"], true);
        if !ran.ok() {
            return Err(self.c.die(&sh::cat(&[
                b"GitHub rejected this key for ",
                &a.slug,
                b" -- wrong App, or a key already deleted in the App's settings",
            ])));
        }
        let got_slug = sh::subst(ran.stdout);
        if got_slug != a.slug {
            return Err(self.c.die(&sh::cat(&[
                b"this key belongs to '",
                &got_slug,
                b"', not '",
                &a.slug,
                b"'",
            ])));
        }
        let ran = self.app_api(&jwt, &[b"/app", b"--jq", b".id"], false);
        if !ran.ok() {
            return Err(Exit(ran.status));
        }
        let app_id = sh::subst(ran.stdout);
        self.c.ok(&sh::cat(&[
            b"GitHub confirms the key belongs to ",
            &a.slug,
            b" (App id ",
            &app_id,
            b")",
        ]));

        // ---- 3. installed, and not a bypass actor -----------------------------
        interrupted()?;
        let inst = sh::cat(&[b"repos/", &self.repo, b"/installation"]);
        if !self.app_api(&jwt, &[&inst, b"--jq", b".id"], true).ok() {
            return Err(self.c.die(&sh::cat(&[
                &a.slug,
                b" is not installed on ",
                &self.repo,
                b" -- install it (Only select repositories) and re-run",
            ])));
        }
        self.c.ok(&sh::cat(&[b"installed on ", &self.repo]));

        if a.no_bypass == b"yes" {
            let mut c = Command::new("gh");
            c.arg("api")
                .arg(sh::os(&sh::cat(&[b"repos/", &self.repo, b"/rulesets"])))
                .args(["--jq", ".[].id"]);
            let ids = sh::subst(sh::capture_stdout(0, &mut c).stdout);
            for rs in sh::ifs_split(&ids) {
                let mut c = Command::new("gh");
                c.arg("api")
                    .arg(sh::os(&sh::cat(&[
                        b"repos/",
                        &self.repo,
                        b"/rulesets/",
                        &rs,
                    ])))
                    .arg("--jq")
                    .arg(r#".bypass_actors[]? | select(.actor_type=="Integration") | .actor_id"#);
                let ran = sh::capture_stdout(0, &mut c);
                if !ran.ok() {
                    return Err(Exit(ran.status));
                }
                let bypass = sh::subst(ran.stdout);
                // printf '%s\n' "$bypass" | grep -qx "$APP_ID"
                if bypass
                    .split(|&c| c == b'\n')
                    .any(|l| l == app_id.as_slice())
                {
                    return Err(self.c.die(&sh::cat(&[
                        &a.slug,
                        b" is on the bypass list of ruleset ",
                        &rs,
                        b" -- remove it; this App must go through the merge queue like everyone else",
                    ])));
                }
            }
            self.c.ok(b"not on any ruleset bypass list");
        }

        // ---- 4. store ---------------------------------------------------------
        interrupted()?;
        for store in sh::ifs_split(&a.stores) {
            let input = std::fs::File::open(sh::path(&pem)).map_err(|e| {
                sh::redirect_error(0, &pem, &e);
                Exit(1)
            })?;
            let mut c = Command::new("gh");
            c.args(["secret", "set"])
                .arg(sh::os(&a.secret))
                .arg("--repo")
                .arg(sh::os(&self.repo));
            if store == b"dependabot" {
                c.args(["--app", "dependabot"]);
            }
            c.stdin(Stdio::from(input)).stdout(Stdio::null());
            let st = sh::status(0, &mut c, false);
            if st != 0 {
                return Err(Exit(st));
            }
            self.c.ok(&sh::cat(&[
                b"stored ",
                &a.secret,
                b" (",
                &store,
                b" secrets)",
            ]));
        }
        if a.secret == b"SYNC_APP_PRIVATE_KEY" {
            self.c.warn(b"repo-config (Pulumi) also writes this secret, from the same CI secret -- nothing else to update");
        }

        // ---- 5. clean up --------------------------------------------------------
        if let Some(tmp) = self.temp_pem.take() {
            if std::fs::remove_file(sh::path(&tmp)).is_ok() || !sh::exists(&tmp) {
                self.c.ok(b"removed the temporary copy of the key");
            }
            if a.client_id != client_id {
                self.c.warn(&sh::cat(&[
                    b"commit this client ID into APPS in tools/github-app-key/set-key.sh: ",
                    &client_id,
                ]));
            }
        } else if self.ask(
            assume_yes,
            &sh::cat(&[b"Delete ", &pem, b" now that it is stored?"]),
        ) {
            if std::fs::remove_file(sh::path(&pem)).is_ok() || !sh::exists(&pem) {
                self.c.ok(&sh::cat(&[b"deleted ", &pem]));
            }
        } else {
            self.c.warn(&sh::cat(&[
                b"left ",
                &pem,
                b" in place -- delete it once you're done",
            ]));
        }
        sh::out(&sh::cat(&[
            b"\n",
            self.c.bold.as_bytes(),
            b"Done.",
            self.c.reset.as_bytes(),
            b"\n",
        ]));
        Ok(())
    }

    /// The --create key, in a mode-0600 mktemp $TMPDIR/github-app-key.XXXXXX
    /// that `run` removes on the way out.
    fn write_temp_key(&mut self, key: &[u8]) -> Result<Vec<u8>, Exit> {
        let old = sh::umask(0o077);
        let made = sh::mktemp_file(&sh::cat(&[
            &sh::env_or("TMPDIR", b"/tmp"),
            b"/github-app-key.XXXXXX",
        ]));
        sh::umask(old);
        let tmp = match made {
            Ok(p) => p,
            Err(e) => {
                sh::err(format!("mktemp: {}\n", sh::strerror(&e)).as_bytes());
                return Err(Exit(1));
            }
        };
        self.temp_pem = Some(tmp.clone());
        if let Err(e) = std::fs::write(sh::path(&tmp), key) {
            sh::redirect_error(0, &tmp, &e);
            return Err(Exit(1));
        }
        Ok(tmp)
    }

    /// The manifest form: mktemp $TMPDIR/github-app-create.XXXXXX, renamed to .html.
    fn write_form(&self, slug: &[u8], owner: &[u8], manifest: &[u8]) -> Result<Vec<u8>, Exit> {
        let made = sh::mktemp_file(&sh::cat(&[
            &sh::env_or("TMPDIR", b"/tmp"),
            b"/github-app-create.XXXXXX",
        ]));
        let base = match made {
            Ok(p) => p,
            Err(e) => {
                sh::err(format!("mktemp: {}\n", sh::strerror(&e)).as_bytes());
                return Err(Exit(1));
            }
        };
        let form = sh::cat(&[&base, b".html"]);
        if std::fs::rename(sh::path(&base), sh::path(&form)).is_err() {
            return Err(Exit(1));
        }
        let html = sh::cat(&[
            b"<!doctype html><html><body onload=\"document.getElementById('f').submit()\">\n",
            b"<p>Opening GitHub's new-App page for <strong>",
            slug,
            b"</strong>...</p>\n",
            b"<form id=\"f\" method=\"post\" action=\"https://github.com/organizations/",
            owner,
            b"/settings/apps/new\">\n",
            b"<input type=\"hidden\" name=\"manifest\" value='",
            manifest,
            b"'><button type=\"submit\">Create GitHub App</button>\n",
            b"</form></body></html>\n",
        ]);
        if let Err(e) = std::fs::write(sh::path(&form), html) {
            sh::redirect_error(0, &form, &e);
            return Err(Exit(1));
        }
        Ok(form)
    }
}

/// `printf '%s' DATA | cmd`: cmd's stdout and status, its stderr passed
/// through.
fn pipe_capture(cmd: &mut Command, data: &[u8]) -> sh::Ran {
    use std::io::Write;
    cmd.stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit());
    let mut child = match cmd.spawn() {
        Ok(c) => c,
        Err(e) => {
            return sh::Ran {
                status: sh::spawn_failure_status(&e),
                stdout: Vec::new(),
                stderr: Vec::new(),
            }
        }
    };
    // Fed from a thread, so a child that writes before it has read
    // everything cannot deadlock against us.
    let input = data.to_vec();
    let writer = child.stdin.take().map(|mut sin| {
        std::thread::spawn(move || {
            let _ = sin.write_all(&input);
        })
    });
    let out = child.wait_with_output();
    if let Some(w) = writer {
        let _ = w.join();
    }
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

/// Stop if SIGINT/SIGTERM/SIGHUP arrived (only recorded once a temporary
/// key exists; see record_exit_signals).
fn interrupted() -> Result<(), Exit> {
    match sh::caught_signal() {
        Some(sig) => Err(Exit(128 + sig)),
        None => Ok(()),
    }
}

/// The whole tool; the process exit code.
pub fn run(args: &[Vec<u8>]) -> i32 {
    let mut r = Run {
        c: Colors::detect(),
        repo: sh::env_or("GITHUB_APP_KEY_REPO", b"VitruvianSoftware/vitruvian-core"),
        temp_pem: None,
    };
    let res = r.body(args);
    // trap 'rm -f "$PEM"' EXIT, once --create made a temporary key.
    if let Some(tmp) = r.temp_pem.take() {
        let _ = std::fs::remove_file(sh::path(&tmp));
    }
    match res {
        Ok(()) => 0,
        Err(Exit(c)) => c,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn manifest_matches_the_scripts_shape() {
        assert_eq!(
            manifest(
                "vitruvian-renovate",
                "VitruvianSoftware",
                "contents=write,issues=write,pull_requests=write"
            ),
            r#"{"name":"vitruvian-renovate","url":"https://github.com/VitruvianSoftware","redirect_url":"http://localhost:8723/cb","public":false,"default_permissions":{"contents":"write","issues":"write","pull_requests":"write"},"default_events":[]}"#
        );
        // Order as listed, not sorted.
        assert!(manifest("s", "o", "z=read,a=write").contains(r#"{"z":"read","a":"write"}"#));
        assert!(manifest("s", "o", "").contains(r#""default_permissions":{}"#));
    }

    #[test]
    fn b64url_is_unpadded_url_safe() {
        assert_eq!(b64url(b""), "");
        assert_eq!(b64url(b"f"), "Zg");
        assert_eq!(b64url(b"fo"), "Zm8");
        assert_eq!(b64url(b"foo"), "Zm9v");
        assert_eq!(b64url(&[0xfb, 0xff]), "-_8");
        assert_eq!(
            b64url(br#"{"alg":"RS256","typ":"JWT"}"#),
            "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9"
        );
    }

    #[test]
    fn jwt_claims() {
        let u = unsigned_jwt(1000, "Iv23x");
        let claims = u.split('.').nth(1).unwrap();
        assert_eq!(claims, b64url(br#"{"iat":940,"exp":1300,"iss":"Iv23x"}"#));
    }

    #[test]
    fn apps_table() {
        let a = lookup(b"renovate").unwrap();
        assert_eq!(a.slug, b"vitruvian-renovate");
        assert_eq!(a.no_bypass, b"yes");
        assert_eq!(
            lookup(b"copybara-sync").unwrap().stores,
            b"actions dependabot"
        );
        assert!(lookup(b"nope").is_none());
        assert!(lookup(b"").is_none());
        assert!(list().starts_with(
            "renovate        vitruvian-renovate         -> RENOVATE_APP_PRIVATE_KEY (actions)\n"
        ));
        assert!(usage().contains("one of: renovate copybara-sync \n"));
    }
}
