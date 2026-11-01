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

//! Authentication and the session environment.
//!
//! The profile is the blast-radius boundary: its row decides which identity
//! the session takes and which secrets it may materialise. Every property here
//! whose failure would be a PRIVILEGE ESCALATION or a SECRET LEAK is pinned by
//! //tools/cloud-bootstrap:cloud-bootstrap_test.

use std::fs;
use std::path::PathBuf;
use std::process::Command;
use std::time::Duration;

use crate::manifest::{self, Profile};
use crate::sh::{self, which};
use crate::{note, warn, Ctx};

const MARK_BEGIN: &str =
    "# >>> vitruvian-core cloud session (managed by tools/cloud-bootstrap) — do not edit by hand";
const MARK_END: &str = "# <<< vitruvian-core cloud session (managed by tools/cloud-bootstrap)";

/// AUTH_STATE gates every later secret read, so a refusal FAILS CLOSED:
/// authorisation is never delegated to the failure mode of the tool we just
/// refused to trust.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum AuthState {
    Ok,
    None,
    Failed,
}

impl Ctx {
    /// is_credential: long enough to be a real secret. The sandbox pre-sets
    /// GH_TOKEN, GITHUB_TOKEN, AWS_ACCESS_KEY_ID and CLOUDSDK_AUTH_ACCESS_TOKEN
    /// to short dummy strings; every real credential is comfortably longer.
    pub fn is_credential(&self, v: &[u8]) -> bool {
        !v.is_empty() && sh::char_len(v) >= self.min_credential_len
    }

    /// env_set: replace VAR's line in the 0600 session.env (outside the
    /// workspace, so a stray `git add -A` cannot commit it). The value is
    /// never echoed. Rewritten rather than appended, so a resumed session
    /// whose hook runs again does not grow the file a copy at a time.
    pub fn env_set(&self, var: &str, value: &[u8]) {
        let f = &self.session_env;
        let res = (|| -> std::io::Result<()> {
            sh::private_dir(&self.state_dir)?;
            let old = fs::read(f).unwrap_or_default();
            let prefix = format!("export {var}=");
            let mut kept = Vec::new();
            for line in sh::lines(&old) {
                if !line.starts_with(prefix.as_bytes()) {
                    kept.extend_from_slice(line);
                    kept.push(b'\n');
                }
            }
            kept.extend_from_slice(prefix.as_bytes());
            kept.extend_from_slice(&sh::shell_quote(value));
            kept.push(b'\n');
            let tmp = PathBuf::from(format!("{}.tmp", sh::path_str(f)));
            sh::write_private(&tmp, &kept)?;
            fs::rename(&tmp, f)
        })();
        if let Err(e) = res {
            warn(&format!("could not write {}: {e}", sh::path_str(f)));
        }
    }

    /// wire_session_env: carry session.env into every later shell (a marker
    /// block in ~/.bashrc), into $CLAUDE_ENV_FILE when the harness gives one,
    /// and into this process so the verification after it sees the values.
    pub fn wire_session_env(&self) {
        if !sh::non_empty(&self.session_env) {
            return;
        }
        if !sh::file_contains(&self.bashrc, MARK_BEGIN.as_bytes()) {
            let q = sh::shell_quote(sh::path_str(&self.session_env).as_bytes());
            let mut block = format!("\n{MARK_BEGIN}\n").into_bytes();
            block.extend_from_slice(b"[ -f ");
            block.extend_from_slice(&q);
            block.extend_from_slice(b" ] && . ");
            block.extend_from_slice(&q);
            block.extend_from_slice(format!("\n{MARK_END}\n").as_bytes());
            if let Err(e) = sh::append(&self.bashrc, &block) {
                warn(&format!(
                    "could not write {}: {e}",
                    sh::path_str(&self.bashrc)
                ));
            }
        }
        let claude_env = sh::env_or_empty("CLAUDE_ENV_FILE");
        if !claude_env.is_empty() {
            if let Ok(text) = fs::read(&self.session_env) {
                let _ = sh::append(&sh::path(&claude_env), &text);
            }
        }
        sh::source_exports(&self.session_env);
    }

    /// scrub_placeholder_creds: a short CLOUDSDK_AUTH_ACCESS_TOKEN is worse
    /// than none. tools/pulumi treats a non-empty one as "ambient credentials
    /// present" and skips its gcp-identities.tsv pin.
    fn scrub_placeholder_creds(&self) {
        let t = sh::env_or_empty("CLOUDSDK_AUTH_ACCESS_TOKEN");
        if !t.is_empty() && !self.is_credential(&t) {
            self.env_set("CLOUDSDK_AUTH_ACCESS_TOKEN", b"");
            note("cleared a placeholder CLOUDSDK_AUTH_ACCESS_TOKEN (would have masked the real identity)");
        }
    }

    /// The identity secrets are read as, for log lines.
    fn secret_reader(&self, p: &Profile) -> String {
        if self.esc_token_file.is_some() {
            self.esc_sa.clone()
        } else {
            p.sa_account.clone()
        }
    }

    /// gcloud_secret: the value, or None after printing gcloud's reason.
    /// gcloud EXITS 0 while printing "ERROR: ... Reauthentication failed" on a
    /// broken credential, so neither the status nor an empty result is trusted
    /// alone.
    fn gcloud_secret(&self, p: &Profile, name: &str) -> Option<Vec<u8>> {
        let mut cmd = Command::new(&self.gcloud_bin);
        match &self.esc_token_file {
            Some(f) => cmd.arg(format!("--access-token-file={}", sh::path_str(f))),
            None => cmd.arg(format!("--account={}", p.sa_account)),
        };
        cmd.arg(format!("--project={}", p.sa_project))
            .args(["secrets", "versions", "access", "latest"])
            .arg(format!("--secret={name}"));
        let r = sh::capture(&mut cmd);
        let out = sh::subst(r.stdout);
        let err_line = sh::lines(&r.stderr)
            .iter()
            .any(|l| l.starts_with(b"ERROR:"));
        if !r.ok || err_line || out.is_empty() {
            crate::err_bytes(&sh::indent(&r.stderr, "    "));
            return None;
        }
        Some(out)
    }

    fn esc_fail(&mut self, profile: &str, reason: &str) {
        self.auth_state = AuthState::Failed;
        let _ = sh::private_dir(&self.state_dir);
        let _ = fs::remove_file(self.state_dir.join(format!("esc-token-{profile}")));
        let _ = sh::write_private(
            &self.state_dir.join("esc-last-error"),
            format!("{reason}\n").as_bytes(),
        );
    }

    /// KEYLESS IDENTITY via Pulumi ESC. The org forbids service-account keys
    /// (iam.disableServiceAccountKeyCreation), so the session presents its
    /// Pulumi token to ESC, which exchanges an OIDC token for a ~1h GCP token
    /// for ESC_SA. Retried, because a cold session can run this before the
    /// network is up; a wrong-account token is NOT retried, it is a refusal.
    fn authenticate_esc(&mut self, profile: &str) {
        let esc_env = sh::env_str("VITRUVIAN_ESC_ENV", "ipv1337/vitruvian-core/cloud-session");
        let token_file = self.state_dir.join(format!("esc-token-{profile}"));
        let _ = fs::remove_file(self.state_dir.join("esc-last-error"));
        let _ = fs::remove_file(&token_file);

        if which(&self.pulumi_bin).is_none() {
            self.esc_fail(profile, "pulumi is not installed");
            warn("pulumi is not installed — cannot mint the keyless ESC identity");
            return;
        }

        let mut attempt: u32 = 1;
        let tok = loop {
            let r = sh::capture(
                Command::new(&self.pulumi_bin)
                    .args(["env", "open"])
                    .arg(&esc_env)
                    .args(["gcp.login.accessToken", "--format", "string"]),
            );
            let tok: Vec<u8> = sh::subst(r.stdout)
                .into_iter()
                .filter(|&c| c != b'\r' && c != b'\n')
                .collect();
            let reason = if r.ok && self.is_credential(&tok) {
                // IDENTITY PINNING, for ESC: refuse a token that is not the
                // expected account. The token goes to curl on stdin, never argv.
                let mut body = b"access_token=".to_vec();
                body.extend_from_slice(&tok);
                let info = sh::capture_with_input(
                    Command::new("curl")
                        .args(["-fsS", "--max-time", "15", "--data", "@-"])
                        .arg("https://oauth2.googleapis.com/tokeninfo"),
                    &body,
                );
                let email = tokeninfo_email(&info.stdout);
                if email == self.esc_sa {
                    break tok;
                }
                if !email.is_empty() {
                    self.esc_fail(
                        profile,
                        &format!(
                            "the ESC token belongs to {email}, not the expected {}",
                            self.esc_sa
                        ),
                    );
                    warn(&format!(
                        "REFUSING the ESC identity for profile '{profile}': expected {}",
                        self.esc_sa
                    ));
                    note(&format!("but the token belongs to '{email}'."));
                    return;
                }
                "could not verify which account the ESC token belongs to (Google tokeninfo lookup failed)".to_string()
            } else {
                format!(
                    "pulumi env open {esc_env} failed: {}",
                    pulumi_reason(&r.stderr)
                )
            };

            if attempt >= self.esc_retries {
                self.esc_fail(profile, &format!("{reason} (after {attempt} attempts)"));
                warn(&format!(
                    "Pulumi ESC ({esc_env}) did not yield a GCP token for profile '{profile}' after {attempt} attempts"
                ));
                note(&reason);
                note("check $PULUMI_ACCESS_TOKEN is valid and can open that environment, then re-run:");
                note("  bash tools/cloud-bootstrap/cloud-bootstrap.sh auth");
                return;
            }
            note(&format!(
                "ESC attempt {attempt}/{} failed ({reason}); retrying in {}s",
                self.esc_retries, self.esc_retry_delay_raw
            ));
            std::thread::sleep(self.esc_retry_delay);
            attempt += 1;
        };

        let _ = sh::private_dir(&self.state_dir);
        if let Err(e) = sh::write_private(&token_file, &tok) {
            self.esc_fail(profile, &format!("could not write the ESC token file: {e}"));
            warn(&format!(
                "could not write {}: {e}",
                sh::path_str(&token_file)
            ));
            return;
        }
        self.esc_token_file = Some(token_file);
        self.auth_state = AuthState::Ok;
        note(&format!(
            "identity: {} via Pulumi ESC ({esc_env}) — keyless, reads this profile's secrets only",
            self.esc_sa
        ));
    }

    /// authenticate: establish the profile's identity, or record why not.
    pub fn authenticate(&mut self, profile: &str, p: &Profile) {
        self.scrub_placeholder_creds();

        if p.sa_account == "-" {
            self.auth_state = AuthState::None;
            note(&format!(
                "profile '{profile}' declares no GCP identity — no credentials established"
            ));
            return;
        }

        // Per-profile key first, so ONE environment can hold several profiles'
        // keys. The variable NAME is built from the (validated) profile name;
        // nothing is ever evaluated as code.
        let upper: String = profile
            .chars()
            .map(|c| {
                if c == '-' {
                    '_'
                } else {
                    c.to_ascii_uppercase()
                }
            })
            .collect();
        let varname = format!("VITRUVIAN_CLOUD_KEY_{upper}");
        let mut key = sh::env_or_empty(&varname);
        if key.is_empty() {
            key = sh::env_or_empty("VITRUVIAN_CLOUD_KEY");
        }
        // One file per profile: several identities can be active at once.
        let sa_key_file = self.state_dir.join(format!("sa-key-{profile}.json"));

        if key.is_empty() && !sh::env_or_empty("PULUMI_ACCESS_TOKEN").is_empty() {
            self.authenticate_esc(profile);
            return;
        }

        if key.is_empty() {
            self.auth_state = AuthState::Failed;
            warn(&format!(
                "no key for profile '{profile}' (${varname} or $VITRUVIAN_CLOUD_KEY) — no GCP identity."
            ));
            note(&format!(
                "add the '{}' service-account key to the cloud environment,",
                p.sa_account
            ));
            note("or set the individual tokens directly (they are honored if already present).");
            return;
        }

        if which(&self.gcloud_bin).is_none() {
            self.auth_state = AuthState::Failed;
            warn("gcloud is not installed — cannot establish the profile identity");
            return;
        }

        let _ = sh::private_dir(&self.state_dir);
        if let Err(e) = sh::write_private(&sa_key_file, &decode_key(&key)) {
            self.auth_state = AuthState::Failed;
            warn(&format!(
                "could not write {}: {e}",
                sh::path_str(&sa_key_file)
            ));
            return;
        }

        // IDENTITY PINNING: the key must be the account this profile declares.
        let content = fs::read(&sa_key_file).unwrap_or_default();
        let client_email = key_client_email(&content);
        if client_email.is_empty() {
            self.auth_state = AuthState::Failed;
            warn(&format!(
                "the key for profile '{profile}' is not a valid service-account key JSON"
            ));
            note("give it as raw JSON or single-line base64, and check it was not truncated");
            let _ = fs::remove_file(&sa_key_file);
            return;
        }
        if client_email != p.sa_account {
            self.auth_state = AuthState::Failed;
            warn(&format!(
                "REFUSING to authenticate: profile '{profile}' declares {}",
                p.sa_account
            ));
            note(&format!(
                "but ${varname} resolved to a key belonging to {client_email}."
            ));
            note("With several profiles active each needs its OWN key in $VITRUVIAN_CLOUD_KEY_<PROFILE>;");
            note("the shared $VITRUVIAN_CLOUD_KEY can only satisfy one of them.");
            let _ = fs::remove_file(&sa_key_file);
            return;
        }

        // By path, never by value: argv is world-readable through `ps`.
        if !sh::quiet(
            Command::new(&self.gcloud_bin)
                .args(["auth", "activate-service-account"])
                .arg(format!("--key-file={}", sh::path_str(&sa_key_file)))
                .arg("--quiet"),
        ) {
            self.auth_state = AuthState::Failed;
            warn(&format!(
                "gcloud could not activate {} (key rejected or revoked)",
                p.sa_account
            ));
            return;
        }
        self.auth_state = AuthState::Ok;

        // THE FIRST LISTED PROFILE THAT HAS AN IDENTITY is ambient for the
        // session (GOOGLE_APPLICATION_CREDENTIALS, so every Google client can
        // refresh on its own; an access token would expire within the hour).
        if self.primary_account.is_empty() {
            self.primary_account = p.sa_account.clone();
            let _ = sh::quiet(
                Command::new(&self.gcloud_bin)
                    .args(["config", "set", "project"])
                    .arg(&p.sa_project)
                    .arg("--quiet"),
            );
            self.env_set(
                "GOOGLE_APPLICATION_CREDENTIALS",
                sh::path_str(&sa_key_file).as_bytes(),
            );
            self.env_set("CLOUDSDK_CORE_PROJECT", p.sa_project.as_bytes());
            self.env_set("GOOGLE_CLOUD_PROJECT", p.sa_project.as_bytes());
            note(&format!(
                "identity: {} (project {}) — PRIMARY, ambient for pulumi/gcloud",
                p.sa_account, p.sa_project
            ));
        } else {
            note(&format!(
                "identity: {} (project {}) — reads its own secrets only",
                p.sa_account, p.sa_project
            ));
        }
    }

    fn claimed_as(&self, var: &str) -> Option<&str> {
        self.claimed
            .iter()
            .find(|(v, _)| v == var)
            .map(|(_, n)| n.as_str())
    }

    /// materialise_secrets: every VAR=secret the profile declares.
    pub fn materialise_secrets(&mut self, profile: &str, p: &Profile) {
        if p.secrets == "-" {
            return;
        }
        for pair in manifest::words(&p.secrets) {
            let (var, name) = manifest::split_pair(&pair);
            if var.is_empty() || name.is_empty() {
                continue;
            }

            // Two rows naming the same var: identical is a harmless overlap,
            // different is refused (it would resolve by manifest row order).
            if let Some(prev) = self.claimed_as(&var) {
                if prev == name {
                    continue;
                }
                let prev = prev.to_string();
                warn(&format!(
                    "REFUSING {var} for profile '{profile}': an earlier profile already mapped it"
                ));
                note(&format!(
                    "to secret '{prev}', this one says '{name}'. Which credential the"
                ));
                note("session holds must not depend on manifest row order — fix the manifest.");
                continue;
            }

            // An env var already set on the environment WINS, but only when it
            // is actually a credential, never a sandbox placeholder.
            let ambient = sh::env_or_empty(&var);
            if self.is_credential(&ambient) {
                self.claimed.push((var.clone(), name.clone()));
                note(&format!(
                    "{var}: already set on the environment (left untouched)"
                ));
                continue;
            }
            if !ambient.is_empty() {
                note(&format!(
                    "{var}: ignoring a placeholder value ({} chars — too short to be a real credential)",
                    sh::char_len(&ambient)
                ));
            }
            // ENVIRONMENT-ONLY ("-"): entitled, never read from Secret Manager.
            if name == "-" {
                note(&format!(
                    "{var}: environment-only (not in Secret Manager by design)"
                ));
                continue;
            }
            // FAIL CLOSED: no established identity, no read attempted at all.
            if self.auth_state != AuthState::Ok {
                note(&format!(
                    "{var}: unavailable (no established GCP identity to read {name} with)"
                ));
                continue;
            }
            match self.gcloud_secret(p, &name) {
                Some(val) => {
                    self.env_set(&var, &val);
                    self.claimed.push((var.clone(), name.clone()));
                    note(&format!(
                        "{var}: from {name} (as {})",
                        self.secret_reader(p)
                    ));
                }
                None => {
                    note(&format!(
                        "{var}: could not read {name} from {} as {}",
                        p.sa_project,
                        self.secret_reader(p)
                    ));
                    note(&format!(
                        "  → seed it: bazel run //tools/gcp-secrets:seed -- <infra-dir> {name}"
                    ));
                }
            }
        }
    }

    /// scrub_undeclared: blank every manifest-declared credential no active
    /// profile claimed. Without this the profile boundary is decorative
    /// whenever credentials come from the environment.
    pub fn scrub_undeclared(&self) {
        let mut cleared = 0;
        for var in manifest::known_credential_vars(&self.profiles_file) {
            if self.claimed_as(&var).is_some() {
                continue;
            }
            if sh::env_or_empty(&var).is_empty() {
                continue;
            }
            self.env_set(&var, b"");
            note(&format!("{var}: CLEARED — no active profile declares it"));
            cleared += 1;
        }
        if cleared != 0 {
            note(&format!(
                "scrubbed {cleared} credential(s) this profile is not entitled to"
            ));
        }
    }

    /// configure_build_cache: point a plain `bazel` at the shared BuildBuddy
    /// cache, by delegating to //tools/remote:setup (one definition of the
    /// block). CACHE ONLY, never --config=remote. Called from `auth`, never
    /// `install`: the block holds the key, and `install` is what the Setup
    /// script bakes into a cached image.
    pub fn configure_build_cache(&self) {
        // Entitlement first: an ACTIVE profile declared it and it resolved.
        if self.claimed_as("BUILDBUDDY_API_KEY").is_none() {
            return;
        }
        let key = sh::env_or_empty("BUILDBUDDY_API_KEY");
        if !self.is_credential(&key) {
            return;
        }
        if !self.tools_all.iter().any(|t| t == "bazel") {
            return; // nothing in this session would read user.bazelrc
        }
        if !sh::is_executable(&self.cache_setup) {
            note(&format!(
                "build cache: {} is not executable — skipped, builds stay local",
                sh::path_str(&self.cache_setup)
            ));
            return;
        }
        let user_bazelrc = self.ws.join("user.bazelrc");
        // The key travels in the environment, never as --key (argv is
        // world-readable). The workspace is pinned rather than guessed.
        // VERIFIED, NOT ASSUMED: a zero exit is not evidence the block landed.
        let ran = sh::quiet(
            Command::new(&self.cache_setup)
                .args(["--cache", "buildbuddy", "--no-ci", "--yes"])
                .env("BUILD_WORKSPACE_DIRECTORY", &self.ws)
                .env("BUILDBUDDY_API_KEY", sh::os(&key)),
        );
        if ran && sh::file_contains(&user_bazelrc, b"--config=remotecache") {
            note("build cache: BuildBuddy is now the default for plain bazel (cache only; RBE stays --config=remote)");
            return;
        }
        // Clear up a partial run, but strictly a zero-byte file: a developer's
        // own user.bazelrc is never empty.
        if sh::is_file(&user_bazelrc) && !sh::non_empty(&user_bazelrc) {
            let _ = fs::remove_file(&user_bazelrc);
            note("build cache: removed an empty user.bazelrc left by a partial run");
        }
        note("build cache: could not configure — builds stay local");
    }
}

/// decode_key: raw JSON, or base64 of it. A pasted credential arrives
/// wrapped, CR-laden or base64'd depending on who pasted it.
pub fn decode_key(raw: &[u8]) -> Vec<u8> {
    let first = raw.iter().find(|c| !c.is_ascii_whitespace() && **c != 0x0b);
    if first == Some(&b'{') {
        raw.iter().copied().filter(|&c| c != b'\r').collect()
    } else {
        let compact: Vec<u8> = raw
            .iter()
            .copied()
            .filter(|c| !c.is_ascii_whitespace() && *c != 0x0b)
            .collect();
        sh::base64_decode(&compact)
    }
}

fn is_space(c: u8) -> bool {
    matches!(c, b' ' | b'\t' | b'\r' | 0x0b | 0x0c)
}

/// The value of `"client_email" : "..."` at `at` (the opening quote of the
/// key), if the whole pattern matches there.
fn client_email_at(line: &[u8], at: usize) -> Option<Vec<u8>> {
    const KEY: &[u8] = b"\"client_email\"";
    let mut i = at + KEY.len();
    while i < line.len() && is_space(line[i]) {
        i += 1;
    }
    if line.get(i) != Some(&b':') {
        return None;
    }
    i += 1;
    while i < line.len() && is_space(line[i]) {
        i += 1;
    }
    if line.get(i) != Some(&b'"') {
        return None;
    }
    i += 1;
    let end = line[i..].iter().position(|&c| c == b'"')? + i;
    Some(line[i..end].to_vec())
}

/// key_client_email: the key's client_email, or empty unless exactly one line
/// carries one. Deliberately not a JSON parser (the shell avoided jq for the
/// same reason): a malformed or doctored key yields empty, which is fatal.
pub fn key_client_email(content: &[u8]) -> String {
    const KEY: &[u8] = b"\"client_email\"";
    let mut found: Vec<Vec<u8>> = Vec::new();
    for line in sh::lines(content) {
        let mut start = 0;
        while let Some(off) = line[start..].windows(KEY.len()).position(|w| w == KEY) {
            let at = start + off;
            if let Some(v) = client_email_at(line, at) {
                found.push(v);
                break;
            }
            start = at + 1;
        }
    }
    if found.len() == 1 {
        sh::lossy(&found[0])
    } else {
        String::new()
    }
}

/// `sed -n 's/.*"email": *"\([^"]*\)".*/\1/p' | head -1`: on the first line
/// that has one, the LAST `"email": "..."` (the leading `.*` is greedy).
pub fn tokeninfo_email(out: &[u8]) -> String {
    const KEY: &[u8] = b"\"email\":";
    for line in sh::lines(out) {
        let starts: Vec<usize> = line
            .windows(KEY.len())
            .enumerate()
            .filter(|(_, w)| *w == KEY)
            .map(|(i, _)| i)
            .collect();
        for &at in starts.iter().rev() {
            let mut i = at + KEY.len();
            while line.get(i) == Some(&b' ') {
                i += 1;
            }
            if line.get(i) != Some(&b'"') {
                continue;
            }
            i += 1;
            if let Some(len) = line[i..].iter().position(|&c| c == b'"') {
                return sh::lossy(&line[i..i + len]);
            }
        }
    }
    String::new()
}

/// The stderr line that names pulumi's error (it opens with an info line such
/// as "Logging in using access token...", which is not the reason), else its
/// last line. Long token-looking runs are masked, then cut to 160 characters.
pub fn pulumi_reason(stderr: &[u8]) -> String {
    let ls = sh::lines(stderr);
    let line: &[u8] = ls
        .iter()
        .find(|l| sh::lossy(l).to_lowercase().contains("error"))
        .or_else(|| ls.last())
        .copied()
        .unwrap_or(b"");
    let token_char = |c: u8| c.is_ascii_alphanumeric() || matches!(c, b'_' | b'.' | b'-');
    let mut masked = Vec::new();
    let mut i = 0;
    while i < line.len() {
        if token_char(line[i]) {
            let start = i;
            while i < line.len() && token_char(line[i]) {
                i += 1;
            }
            if i - start >= 40 {
                masked.extend_from_slice("…".as_bytes());
            } else {
                masked.extend_from_slice(&line[start..i]);
            }
        } else {
            masked.push(line[i]);
            i += 1;
        }
    }
    sh::lossy(&masked).chars().take(160).collect()
}

/// VITRUVIAN_ESC_RETRY_DELAY as `sleep` takes it (seconds, fractions allowed).
pub fn parse_delay(raw: &str) -> Duration {
    raw.trim()
        .parse::<f64>()
        .ok()
        .filter(|s| s.is_finite() && *s >= 0.0)
        .map(Duration::from_secs_f64)
        .unwrap_or(Duration::from_secs(0))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn client_email_needs_exactly_one() {
        assert_eq!(
            key_client_email(br#"{"type":"x","client_email":"a@b","k":1}"#),
            "a@b"
        );
        assert_eq!(
            key_client_email(b"{\"client_email\" : \"a@b\"}\n{\"client_email\":\"c@d\"}"),
            ""
        );
        assert_eq!(key_client_email(b"base64-garbage"), "");
    }

    #[test]
    fn tokeninfo_takes_first_line_last_match() {
        assert_eq!(tokeninfo_email(b"{\"email\": \"x@y\"}\n"), "x@y");
        assert_eq!(
            tokeninfo_email(b"{\n  \"aud\": \"1\",\n  \"email\": \"sa@p\",\n}"),
            "sa@p"
        );
        assert_eq!(tokeninfo_email(b"{\"error\":\"invalid\"}"), "");
        // sed's leading `.*` is greedy: the LAST match on the line wins.
        assert_eq!(
            tokeninfo_email(b"{\"email\": \"a@x\", \"inner\": {\"email\": \"b@y\"}}"),
            "b@y"
        );
    }

    #[test]
    fn pulumi_reason_masks_and_prefers_error_lines() {
        let tok = "a".repeat(45);
        let r = pulumi_reason(
            format!("Logging in using access token {tok}\nerror: boom {tok}\n").as_bytes(),
        );
        assert_eq!(r, "error: boom …");
        assert_eq!(pulumi_reason(b"one\ntwo\n"), "two");
        assert_eq!(pulumi_reason(b""), "");
    }
}
