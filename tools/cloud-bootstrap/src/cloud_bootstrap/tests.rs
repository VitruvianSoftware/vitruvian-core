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

//! Hermetic regression guard for //tools/cloud-bootstrap. Drives the REAL
//! binary's `auth` and `whoami` paths against a fake `gcloud` (and fake
//! pulumi/curl/cache configurator) that record every invocation, so the
//! assertions are about what the tool actually does. Ported from
//! cloud-bootstrap_test.sh with every case kept. The installers are network
//! downloads and are not exercised; what is pinned is the properties whose
//! failure is a PRIVILEGE ESCALATION or a SECRET LEAK:
//!
//!   1. an unset or unknown VITRUVIAN_PROFILE bootstraps NOTHING;
//!   2. a key whose client_email is not the profile's sa_account is REFUSED;
//!   3. the matching key IS activated, via --key-file (never argv bytes);
//!   4. every secret read carries the pinned --account AND --project;
//!   5. secret values never reach stdout/stderr, and land only in a 0600 file
//!      outside the workspace;
//!   6. gcloud's exit-0-with-"ERROR:" is a FAILURE;
//!   7. an env var already set on the environment WINS;
//!   8. a profile declaring no identity reads no secrets at all;
//!   9. a placeholder CLOUDSDK_AUTH_ACCESS_TOKEN is cleared;
//! plus the keyless ESC path, the profile boundary's scrub, environment-only
//! credentials, the build cache, multiple profiles and the shipped manifest.
//!
//! Added with the port: session.env is read back by real bash with awkward
//! values (it is bash syntax, sourced by every Bash tool call), a session.env
//! written by bash's own `printf %q` (the shell version) is read correctly by
//! `whoami`, and the CLI's subcommand, flag and exit-code contract.

use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicUsize, Ordering};

const SA_KEY_GOOD: &str = r#"{"type":"service_account","client_email":"sa-pinned@x.iam.gserviceaccount.com","private_key":"KEYBYTES"}"#;
const SA_KEY_WRONG: &str = r#"{"type":"service_account","client_email":"sa-admin@x.iam.gserviceaccount.com","private_key":"KEYBYTES"}"#;
const SA_KEY_SECOND: &str = r#"{"type":"service_account","client_email":"sa-second@x.iam.gserviceaccount.com","private_key":"KEYBYTES"}"#;
const SECRET_VALUE: &str = "s3cr3t-value-do-not-print-0123456789";
const ESC_SA_EXPECTED: &str = "sa-esc@x.iam.gserviceaccount.com";

const PROFILES: &str = "\
# profile  tools   sa_account          sa_project  secrets                              purpose
pinned     gh      sa-pinned@x.iam.gserviceaccount.com  proj-a  TOK=tok-secret,OTHER=other-secret  Pinned test profile.
second     kubectl sa-second@x.iam.gserviceaccount.com  proj-b  EXTRA=extra-secret                 Second profile with its own identity.
clashing   gh      sa-pinned@x.iam.gserviceaccount.com  proj-a  TOK=different-secret               Maps TOK to a different secret than `pinned`.
nocreds    gh      -                   -           -                                    No credentials at all.
onlytok    gh      sa-pinned@x.iam.gserviceaccount.com  proj-a  TOK=tok-secret                     Claims TOK and nothing else.
envonly    gh      sa-pinned@x.iam.gserviceaccount.com  proj-a  TOK=tok-secret,ENVCRED=-           Declares an environment-only credential.
cached     bazel,gh sa-pinned@x.iam.gserviceaccount.com proj-a  TOK=tok-secret,BUILDBUDDY_API_KEY=- Declares the build-cache key AND installs bazel.
nobazel    gh      sa-pinned@x.iam.gserviceaccount.com  proj-a  TOK=tok-secret,BUILDBUDDY_API_KEY=- Declares the build-cache key but installs no bazel.
";

const BIG_A: &str = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
const BIG_B: &str = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
const BIG_C: &str = "cccccccccccccccccccccccccccccccccccccccc";
const BIG_D: &str = "dddddddddddddddddddddddddddddddddddddddd";
const BB_KEY: &str = "bbbbbbbbkeyeeeeeeeeeeeeeeeeeeeeeeeeeeeee";

fn bin() -> PathBuf {
    let rel = std::env::var_os("BIN").expect("BIN is set by the rust_test");
    fs::canonicalize(&rel).unwrap_or_else(|e| panic!("BIN={rel:?}: {e}"))
}

fn shipped_profiles() -> PathBuf {
    let rel = std::env::var_os("SHIPPED_PROFILES").expect("SHIPPED_PROFILES is set");
    fs::canonicalize(&rel).unwrap_or_else(|e| panic!("SHIPPED_PROFILES={rel:?}: {e}"))
}

fn has(hay: &str, needle: &str) -> bool {
    hay.contains(needle)
}

#[track_caller]
fn assert_contains(what: &str, hay: &str, needle: &str) {
    assert!(has(hay, needle), "{what}: {needle:?} not found in:\n{hay}");
}

#[track_caller]
fn assert_not_contains(what: &str, hay: &str, needle: &str) {
    assert!(
        !has(hay, needle),
        "{what}: unexpectedly found {needle:?} in:\n{hay}"
    );
}

fn mode(p: &Path) -> u32 {
    fs::metadata(p)
        .unwrap_or_else(|e| panic!("{}: {e}", p.display()))
        .permissions()
        .mode()
        & 0o777
}

fn write_exec(p: &Path, body: &str) {
    fs::write(p, body).unwrap();
    fs::set_permissions(p, fs::Permissions::from_mode(0o755)).unwrap();
}

/// One throwaway world per test: HOME, state dir, fakes, manifest.
struct World {
    dir: PathBuf,
}

impl Drop for World {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.dir);
    }
}

static SEQ: AtomicUsize = AtomicUsize::new(0);

impl World {
    fn new() -> World {
        let base = std::env::var_os("TEST_TMPDIR")
            .map(PathBuf::from)
            .unwrap_or_else(std::env::temp_dir);
        let dir = base.join(format!(
            "cb-{}-{}",
            std::process::id(),
            SEQ.fetch_add(1, Ordering::SeqCst)
        ));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(dir.join("escbin")).unwrap();
        fs::write(dir.join("profiles.tsv"), PROFILES).unwrap();
        let w = World { dir };
        w.make_gcloud("ok");
        w.make_cache_setup("ok");
        w
    }

    fn p(&self, rel: &str) -> PathBuf {
        self.dir.join(rel)
    }

    fn s(&self, rel: &str) -> String {
        self.p(rel).to_string_lossy().into_owned()
    }

    fn read(&self, rel: &str) -> String {
        fs::read_to_string(self.p(rel)).unwrap_or_default()
    }

    fn state(&self, rel: &str) -> PathBuf {
        self.p("state").join(rel)
    }

    fn session_env(&self) -> String {
        fs::read_to_string(self.state("session.env")).unwrap_or_default()
    }

    fn argv(&self) -> String {
        self.read("gcloud.argv")
    }

    /// The lines of gcloud.argv that read a secret.
    fn secret_reads(&self) -> Vec<String> {
        self.argv()
            .lines()
            .filter(|l| l.contains("secrets versions access"))
            .map(str::to_string)
            .collect()
    }

    /// Fake gcloud: records argv per call, serves `value` for secrets, and in
    /// `autherr` mode emulates the exit-0-but-ERROR failure of an expired
    /// credential.
    fn make_gcloud_serving(&self, mode: &str, value: &str) {
        let argv = self.s("gcloud.argv");
        let value_file = self.s("gcloud.value");
        fs::write(&value_file, value).unwrap();
        write_exec(
            &self.p("gcloud"),
            &format!(
                r#"#!/usr/bin/env bash
printf '%s\n' "$*" >>"{argv}"
for a in "$@"; do
  case "$a" in
    secrets) is_secret=1 ;;
  esac
done
if [ "${{is_secret:-0}}" = 1 ]; then
  if [ "{mode}" = autherr ]; then
    echo "ERROR: (gcloud.secrets) Reauthentication failed" >&2
    exit 0
  fi
  cat "{value_file}"; echo
  exit 0
fi
exit 0
"#
            ),
        );
    }

    fn make_gcloud(&self, mode: &str) {
        self.make_gcloud_serving(mode, SECRET_VALUE);
    }

    /// Fake build-cache configurator: records argv AND the environment it was
    /// handed. `partial` leaves an EMPTY user.bazelrc (seen in a real session);
    /// `ok` writes the line that makes a plain `bazel` use the cache.
    fn make_cache_setup(&self, mode: &str) {
        let (argv, env) = (self.s("cache-setup.argv"), self.s("cache-setup.env"));
        write_exec(
            &self.p("cache-setup"),
            &format!(
                r#"#!/usr/bin/env bash
printf '%s\n' "$*" >>"{argv}"
printf 'KEY=%s WS=%s\n' "${{BUILDBUDDY_API_KEY:-<unset>}}" \
  "${{BUILD_WORKSPACE_DIRECTORY:-<unset>}}" >>"{env}"
case "{mode}" in
fail) exit 3 ;;
partial) : >"${{BUILD_WORKSPACE_DIRECTORY}}/user.bazelrc"; exit 3 ;;
esac
printf 'common --config=remotecache\ncommon --remote_header=k=v\n' \
  >"${{BUILD_WORKSPACE_DIRECTORY}}/user.bazelrc"
exit 0
"#
            ),
        );
    }

    /// Fake pulumi (ok | fail | flaky: fails the first call only) and a curl
    /// that answers tokeninfo with `email`. Calls are counted.
    fn make_esc_tools(&self, mode: &str, email: &str) {
        let calls = self.s("escbin/pulumi.calls");
        fs::write(&calls, "").unwrap();
        let token = "e".repeat(120);
        write_exec(
            &self.p("escbin/pulumi"),
            &format!(
                r#"#!/usr/bin/env bash
echo x >>"{calls}"
n=$(wc -l <"{calls}")
case "{mode}" in
  fail) echo "error: boom token exchange refused (HTTP 503)" >&2; exit 1 ;;
  flaky) [ "$n" -le 1 ] && {{ echo "error: network not ready yet" >&2; exit 1; }} ;;
esac
[ "$1 $2" = "env open" ] && {{ printf '%s\n' "{token}"; exit 0; }}
exit 1
"#
            ),
        );
        // Records argv and stdin, so a test can pin where the token travels.
        let (argv, stdin) = (self.s("escbin/curl.argv"), self.s("escbin/curl.stdin"));
        write_exec(
            &self.p("escbin/curl"),
            &format!(
                "#!/usr/bin/env bash\nprintf '%s\\n' \"$*\" >>\"{argv}\"\ncat >>\"{stdin}\"\necho '{{\"email\": \"{email}\"}}'\n"
            ),
        );
    }

    fn esc_calls(&self) -> usize {
        self.read("escbin/pulumi.calls").lines().count()
    }

    /// The tool, with a scrubbed environment (`env -i`) and `envs` on top.
    /// Returns stdout+stderr interleaved as one stream, and the exit code.
    fn exec(&self, args: &[&str], envs: &[(&str, String)]) -> (String, i32) {
        let out_path = self.p("run.out");
        let out = fs::File::create(&out_path).unwrap();
        let mut cmd = Command::new(bin());
        cmd.args(args)
            .env_clear()
            .env("PATH", std::env::var_os("PATH").unwrap_or_default())
            .env("HOME", self.p("home"))
            .env("CLAUDE_CODE_REMOTE", "true")
            .env("CLOUD_BOOTSTRAP_PROFILES", self.p("profiles.tsv"))
            .env("CLOUD_BOOTSTRAP_STATE_DIR", self.p("state"))
            .env("CLOUD_BOOTSTRAP_BASHRC", self.p("home/.bashrc"))
            .env("GCLOUD_BIN", self.p("gcloud"))
            .stdin(Stdio::null())
            .stdout(out.try_clone().unwrap())
            .stderr(out);
        for (k, v) in envs {
            cmd.env(k, v);
        }
        let st = cmd.status().unwrap();
        (
            fs::read_to_string(&out_path).unwrap(),
            st.code().unwrap_or(-1),
        )
    }

    /// run_auth: the auth path in a fresh HOME/state, logs reset.
    fn auth(&self, key: &str, envs: &[(&str, &str)]) -> String {
        let _ = fs::remove_dir_all(self.p("home"));
        let _ = fs::remove_dir_all(self.p("state"));
        fs::create_dir_all(self.p("home")).unwrap();
        for f in ["gcloud.argv", "cache-setup.argv", "cache-setup.env"] {
            fs::write(self.p(f), "").unwrap();
        }
        let mut all: Vec<(&str, String)> = vec![("VITRUVIAN_CLOUD_KEY", key.to_string())];
        all.extend(envs.iter().map(|(k, v)| (*k, v.to_string())));
        self.exec(&["auth"], &all).0
    }

    fn esc_env(&self) -> Vec<(&'static str, String)> {
        let path = format!(
            "{}:{}",
            self.s("escbin"),
            std::env::var("PATH").unwrap_or_default()
        );
        vec![
            ("PATH", path),
            ("PULUMI_BIN", self.s("escbin/pulumi")),
            ("PULUMI_ACCESS_TOKEN", "p".repeat(44)),
            ("VITRUVIAN_ESC_SA", ESC_SA_EXPECTED.to_string()),
        ]
    }

    /// run_esc: no key, a Pulumi token, the fake ESC tools first on PATH.
    fn esc(&self, profile: &str) -> String {
        let e = self.esc_env();
        let mut envs: Vec<(&str, &str)> = e.iter().map(|(k, v)| (*k, v.as_str())).collect();
        envs.push(("VITRUVIAN_PROFILE", profile));
        envs.push(("VITRUVIAN_ESC_RETRY_DELAY", "0"));
        self.auth("", &envs)
    }

    /// whoami against whatever state the last run left behind.
    fn whoami_esc(&self, profile: &str) -> String {
        let mut envs = self.esc_env();
        envs.push(("VITRUVIAN_PROFILE", profile.to_string()));
        self.exec(&["whoami"], &envs).0
    }

    /// effective_value: what a Bash tool call in the session really sees. The
    /// harness sets the env var, the shell sources session.env, and whatever
    /// survives is what the agent can use.
    fn effective(&self, var: &str, ambient: &str) -> String {
        let o = Command::new("bash")
            .arg("-c")
            .arg(r#". "$0" 2>/dev/null; printf "%s" "${!1}""#)
            .arg(self.state("session.env"))
            .arg(var)
            .env(var, ambient)
            .output()
            .unwrap();
        String::from_utf8_lossy(&o.stdout).into_owned()
    }

    /// run_cache_auth: auth against a THROWAWAY workspace (this path writes
    /// and deletes user.bazelrc at the workspace root).
    fn cache_auth(&self, profile: &str, envs: &[(&str, &str)]) -> String {
        let ws = self.p("ws");
        let _ = fs::remove_dir_all(&ws);
        fs::create_dir_all(&ws).unwrap();
        self.cache_auth_keep_ws(profile, envs)
    }

    fn cache_auth_keep_ws(&self, profile: &str, envs: &[(&str, &str)]) -> String {
        let (ws, setup) = (self.s("ws"), self.s("cache-setup"));
        let mut all: Vec<(&str, &str)> = vec![
            ("VITRUVIAN_PROFILE", profile),
            ("CLAUDE_PROJECT_DIR", &ws),
            ("CLOUD_BOOTSTRAP_CACHE_SETUP", &setup),
        ];
        all.extend_from_slice(envs);
        self.auth(SA_KEY_GOOD, &all)
    }
}

// ---------------------------------------------------------------------------
// profile resolution
// ---------------------------------------------------------------------------

#[test]
fn unset_profile_bootstraps_nothing() {
    let w = World::new();
    let out = w.auth(SA_KEY_GOOD, &[("VITRUVIAN_PROFILE", "")]);
    assert_contains(
        "unset profile bootstraps nothing",
        &out,
        "VITRUVIAN_PROFILE is not set",
    );
    assert_contains("unset profile lists the valid names", &out, "pinned");
    assert!(w.argv().is_empty(), "unset profile still called gcloud");
}

#[test]
fn unknown_profile_is_refused() {
    let w = World::new();
    let out = w.auth(SA_KEY_GOOD, &[("VITRUVIAN_PROFILE", "admin-everything")]);
    assert_contains("unknown profile is refused", &out, "is not a known profile");
    assert!(w.argv().is_empty(), "unknown profile still called gcloud");
}

#[test]
fn shell_metacharacter_profile_name_is_rejected() {
    // The name builds variable names, so it is constrained at the door.
    let w = World::new();
    let name = format!("pinned;touch {}", w.s("pwned"));
    let out = w.auth(SA_KEY_GOOD, &[("VITRUVIAN_PROFILE", &name)]);
    assert_contains(
        "a shell-metacharacter profile name is rejected",
        &out,
        "invalid profile name",
    );
    assert!(
        !w.p("pwned").exists(),
        "a profile name was executed as shell"
    );
}

// ---------------------------------------------------------------------------
// identity pinning
// ---------------------------------------------------------------------------

#[test]
fn a_key_for_another_account_is_refused() {
    let w = World::new();
    let out = w.auth(SA_KEY_WRONG, &[("VITRUVIAN_PROFILE", "pinned")]);
    assert_contains(
        "a key for another account is refused",
        &out,
        "REFUSING to authenticate",
    );
    assert_contains(
        "…and both identities are named",
        &out,
        "sa-admin@x.iam.gserviceaccount.com",
    );
    assert_not_contains(
        "…and no secret is read with it",
        &w.argv(),
        "secrets versions access",
    );
    assert!(
        !w.state("sa-key-pinned.json").exists(),
        "the rejected key was left at state/sa-key-pinned.json"
    );
}

#[test]
fn a_malformed_key_is_refused() {
    let w = World::new();
    let out = w.auth(
        &format!("base64:{SA_KEY_GOOD}"),
        &[("VITRUVIAN_PROFILE", "pinned")],
    );
    assert_contains(
        "a malformed key is refused, not guessed at",
        &out,
        "not a valid service-account key",
    );
}

#[test]
fn a_base64_key_is_accepted() {
    let w = World::new();
    let o = Command::new("base64")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .and_then(|mut c| {
            use std::io::Write;
            c.stdin.take().unwrap().write_all(SA_KEY_GOOD.as_bytes())?;
            c.wait_with_output()
        })
        .unwrap();
    let b64: String = String::from_utf8(o.stdout)
        .unwrap()
        .split_whitespace()
        .collect();
    w.auth(&b64, &[("VITRUVIAN_PROFILE", "pinned")]);
    assert_contains(
        "a base64-encoded key is accepted",
        &w.argv(),
        "activate-service-account",
    );
}

// ---------------------------------------------------------------------------
// keyless identity via Pulumi ESC
// ---------------------------------------------------------------------------

#[test]
fn esc_identity_reads_secrets_with_the_token_file() {
    let w = World::new();
    w.make_esc_tools("ok", ESC_SA_EXPECTED);
    let out = w.esc("pinned");
    let argv = w.argv();
    assert_contains(
        "no key but a Pulumi token takes the ESC identity",
        &out,
        "via Pulumi ESC",
    );
    let tf = format!(
        "--access-token-file={}",
        w.state("esc-token-pinned").display()
    );
    assert_contains("…secrets are read with the ESC token file", &argv, &tf);
    assert_not_contains("…not as the profile's service account", &argv, "--account=");
    assert_not_contains(
        "…and no service-account key is activated",
        &argv,
        "activate-service-account",
    );
    assert_eq!(
        mode(&w.state("esc-token-pinned")),
        0o600,
        "the ESC token file is not mode 600"
    );
    assert_not_contains("the ESC token itself is never echoed", &out, "eeeeeeeeee");

    // The token is checked with Google over curl: on stdin, never in argv
    // (argv is world-readable through `ps`).
    let token = "e".repeat(120);
    let curl_argv = w.read("escbin/curl.argv");
    assert_contains(
        "curl was asked about the token",
        &curl_argv,
        "oauth2.googleapis.com/tokeninfo",
    );
    assert_not_contains(
        "the ESC token never reaches curl's argv",
        &curl_argv,
        "eeeeeeeeee",
    );
    assert_eq!(
        w.read("escbin/curl.stdin"),
        format!("access_token={token}"),
        "the ESC token must reach curl on stdin"
    );
}

#[test]
fn esc_token_for_another_account_is_refused_and_not_retried() {
    let w = World::new();
    w.make_esc_tools("ok", "sa-someone-else@x.iam.gserviceaccount.com");
    let out = w.esc("pinned");
    assert_contains(
        "an ESC token for another account is refused",
        &out,
        "REFUSING the ESC identity",
    );
    assert_contains(
        "…naming the account it belongs to",
        &out,
        "sa-someone-else@x.iam.gserviceaccount.com",
    );
    assert_not_contains(
        "…and no secret is read with it",
        &w.argv(),
        "secrets versions access",
    );
    assert_eq!(w.esc_calls(), 1, "a wrong-account token was retried");
}

#[test]
fn esc_failure_is_reported_retried_and_explained_by_whoami() {
    let w = World::new();
    w.make_esc_tools("fail", ESC_SA_EXPECTED);
    let out = w.esc("pinned");
    assert_contains(
        "an ESC failure is reported, not hidden",
        &out,
        "did not yield a GCP token",
    );
    assert_contains(
        "…with the reason pulumi gave",
        &out,
        "boom token exchange refused",
    );
    assert_contains("…and how many attempts were made", &out, "after 3 attempts");
    assert_contains(
        "…and the command to re-run",
        &out,
        "cloud-bootstrap.sh auth",
    );
    assert_not_contains(
        "…and no secret is read",
        &w.argv(),
        "secrets versions access",
    );
    assert_eq!(
        w.esc_calls(),
        3,
        "expected exactly the configured number of attempts"
    );
    assert!(
        !w.state("esc-token-pinned").exists(),
        "a failed ESC run left a token file"
    );

    // The banner must say WHY, not just "not authenticated".
    let out = w.whoami_esc("pinned");
    assert_contains(
        "the banner shows the identity as not authenticated",
        &out,
        "not authenticated",
    );
    assert_contains("…and says why", &out, "why: pulumi env open");
    assert_contains(
        "…and what to run",
        &out,
        "fix: bash tools/cloud-bootstrap/cloud-bootstrap.sh auth",
    );
}

#[test]
fn esc_blip_is_retried_and_whoami_shows_it_established() {
    let w = World::new();
    w.make_esc_tools("flaky", ESC_SA_EXPECTED);
    let out = w.esc("pinned");
    assert_contains("a transient ESC failure is retried", &out, "retrying in");
    assert_contains("…and the retry succeeds", &out, "via Pulumi ESC");
    assert_contains(
        "…so the secrets are still read",
        &w.argv(),
        "secrets versions access",
    );
    assert_eq!(w.esc_calls(), 2, "expected exactly one retry");

    // Once ESC works the banner must not claim otherwise (the keyless identity
    // is a token file, not an activated gcloud account).
    let out = w.whoami_esc("pinned");
    assert_contains(
        "a working ESC identity is shown as established",
        &out,
        "via Pulumi ESC (keyless",
    );
    assert_not_contains("…not as 'not authenticated'", &out, "not authenticated");
}

// ---------------------------------------------------------------------------
// credential handling
// ---------------------------------------------------------------------------

#[test]
fn credential_handling() {
    let w = World::new();
    let out = w.auth(SA_KEY_GOOD, &[("VITRUVIAN_PROFILE", "pinned")]);
    let argv = w.argv();

    assert_contains(
        "the matching key IS activated",
        &argv,
        "activate-service-account",
    );
    let kf = format!("--key-file={}", w.state("sa-key-pinned.json").display());
    assert_contains("…by path, never by value", &argv, &kf);
    assert_not_contains("…so the key bytes never reach argv", &argv, "KEYBYTES");

    assert_contains(
        "secrets are read with the pinned account",
        &argv,
        "--account=sa-pinned@x.iam.gserviceaccount.com",
    );
    assert_contains("…and the pinned project", &argv, "--project=proj-a");
    let reads = w.secret_reads();
    let pinned = reads
        .iter()
        .filter(|l| l.contains("--account=sa-pinned@x.iam.gserviceaccount.com"))
        .count();
    assert!(
        !reads.is_empty() && reads.len() == pinned,
        "only {pinned} of {} secret reads were identity-pinned",
        reads.len()
    );

    assert_not_contains(
        "the secret value never reaches the output",
        &out,
        SECRET_VALUE,
    );
    assert_contains(
        "…but the operator is told where it came from",
        &out,
        "TOK: from tok-secret",
    );

    let envfile = w.state("session.env");
    assert!(
        w.session_env()
            .lines()
            .any(|l| l.starts_with("export TOK=")),
        "the value did not reach {}",
        envfile.display()
    );
    assert_eq!(mode(&envfile), 0o600, "the session env file is not 0600");
    assert_eq!(
        mode(&w.state("sa-key-pinned.json")),
        0o600,
        "the SA key file is not 0600"
    );
    assert_eq!(mode(&w.p("state")), 0o700, "the state dir is not 0700");

    let workspace = std::env::current_dir().unwrap();
    assert!(
        !envfile.starts_with(workspace),
        "the session env file is inside the workspace"
    );
    assert_contains(
        "the session env is wired into ~/.bashrc for every later shell",
        &w.read("home/.bashrc"),
        "session.env",
    );
}

// ---------------------------------------------------------------------------
// failure modes
// ---------------------------------------------------------------------------

#[test]
fn gcloud_exit_zero_auth_failure_is_a_failure() {
    let w = World::new();
    w.make_gcloud("autherr");
    let out = w.auth(SA_KEY_GOOD, &[("VITRUVIAN_PROFILE", "pinned")]);
    assert_contains(
        "gcloud's exit-0 auth failure is still a failure",
        &out,
        "could not read tok-secret",
    );
    assert!(
        !w.session_env().lines().any(|l| l == "export TOK=''"),
        "an empty credential was written as if it were real"
    );
}

#[test]
fn an_env_var_already_set_wins() {
    let w = World::new();
    let out = w.auth(
        SA_KEY_GOOD,
        &[
            ("VITRUVIAN_PROFILE", "pinned"),
            ("TOK", "already-set-on-the-environment"),
        ],
    );
    assert_contains(
        "an env var already set WINS",
        &out,
        "TOK: already set on the environment",
    );
    assert!(
        !w.secret_reads().iter().any(|l| l.contains("tok-secret")),
        "…and is not re-read from Secret Manager"
    );
}

#[test]
fn a_placeholder_env_var_does_not_win() {
    // The sandbox pre-sets GH_TOKEN and friends to short dummy strings.
    let w = World::new();
    let out = w.auth(
        SA_KEY_GOOD,
        &[("VITRUVIAN_PROFILE", "pinned"), ("TOK", "dummy-token")],
    );
    assert_contains(
        "a placeholder env var does NOT win",
        &out,
        "ignoring a placeholder value",
    );
    assert_contains(
        "…the real secret is fetched over it",
        &out,
        "TOK: from tok-secret",
    );
    let env = w.session_env();
    assert!(
        env.lines().any(|l| l.starts_with("export TOK="))
            && !env.lines().any(|l| l.starts_with("export TOK=dummy-token")),
        "the placeholder value survived into the session env"
    );
}

#[test]
fn a_no_identity_profile_reads_nothing() {
    let w = World::new();
    let out = w.auth(SA_KEY_GOOD, &[("VITRUVIAN_PROFILE", "nocreds")]);
    assert_contains(
        "a no-identity profile establishes nothing",
        &out,
        "declares no GCP identity",
    );
    assert!(
        w.argv().is_empty(),
        "a no-identity profile still called gcloud"
    );
}

#[test]
fn a_placeholder_ambient_gcp_token_is_cleared_and_a_real_one_kept() {
    let w = World::new();
    let out = w.auth(
        SA_KEY_GOOD,
        &[
            ("VITRUVIAN_PROFILE", "pinned"),
            ("CLOUDSDK_AUTH_ACCESS_TOKEN", "dummy-token"),
        ],
    );
    assert_contains(
        "a placeholder ambient GCP token is cleared",
        &out,
        "cleared a placeholder",
    );
    assert!(
        w.session_env()
            .lines()
            .any(|l| l == "export CLOUDSDK_AUTH_ACCESS_TOKEN=''"),
        "the placeholder token was not cleared in the session env"
    );

    // A real (long) token must NOT be clobbered: a deliberate break-glass.
    let real = format!("ya29.{}", "a".repeat(80));
    let out = w.auth(
        SA_KEY_GOOD,
        &[
            ("VITRUVIAN_PROFILE", "pinned"),
            ("CLOUDSDK_AUTH_ACCESS_TOKEN", &real),
        ],
    );
    assert_not_contains(
        "a real ambient token is left alone",
        &out,
        "cleared a placeholder",
    );
}

// ---------------------------------------------------------------------------
// the profile boundary actually withholds
// ---------------------------------------------------------------------------

#[test]
fn a_no_credential_profile_blanks_every_declared_credential() {
    let w = World::new();
    let out = w.auth(
        SA_KEY_GOOD,
        &[
            ("VITRUVIAN_PROFILE", "nocreds"),
            ("TOK", BIG_A),
            ("OTHER", BIG_B),
            ("EXTRA", BIG_C),
        ],
    );
    for v in ["TOK", "OTHER", "EXTRA"] {
        assert_eq!(
            w.effective(v, BIG_A),
            "",
            "{v} survived into a no-credential session"
        );
    }
    assert_contains("…and says so out loud", &out, "CLEARED");
}

#[test]
fn a_profile_keeps_what_it_declares_and_loses_the_rest() {
    let w = World::new();
    w.auth(
        SA_KEY_GOOD,
        &[
            ("VITRUVIAN_PROFILE", "onlytok"),
            ("TOK", BIG_A),
            ("OTHER", BIG_B),
            ("EXTRA", BIG_C),
        ],
    );
    assert_ne!(
        w.effective("TOK", BIG_A),
        "",
        "the profile's own credential was scrubbed"
    );
    assert_eq!(
        w.effective("OTHER", BIG_B),
        "",
        "OTHER survived a profile that does not declare it"
    );
    assert_eq!(
        w.effective("EXTRA", BIG_C),
        "",
        "EXTRA survived a profile that does not declare it"
    );
}

#[test]
fn a_var_no_row_names_is_left_alone() {
    let w = World::new();
    let out = w.auth(
        SA_KEY_GOOD,
        &[
            ("VITRUVIAN_PROFILE", "nocreds"),
            ("SOME_UNRELATED_VAR", BIG_C),
        ],
    );
    assert_not_contains(
        "a var no row names is left alone",
        &out,
        "SOME_UNRELATED_VAR",
    );
}

// ---------------------------------------------------------------------------
// environment-only credentials
// ---------------------------------------------------------------------------

#[test]
fn environment_only_credentials_stay_inside_the_boundary() {
    let w = World::new();
    w.auth(
        SA_KEY_GOOD,
        &[("VITRUVIAN_PROFILE", "envonly"), ("ENVCRED", BIG_D)],
    );
    assert!(
        !w.secret_reads().iter().any(|l| l.contains("--secret=-")),
        "a Secret Manager read was attempted for an environment-only credential"
    );
    assert_ne!(
        w.effective("ENVCRED", BIG_D),
        "",
        "an environment-only credential was scrubbed from its own profile"
    );

    // With no value on the environment it is reported, never looked up (the
    // case above never reaches the lookup: a real value is kept first).
    let out = w.auth(SA_KEY_GOOD, &[("VITRUVIAN_PROFILE", "envonly")]);
    assert_contains(
        "an unset environment-only credential is reported",
        &out,
        "ENVCRED: environment-only",
    );
    assert!(
        !w.secret_reads().iter().any(|l| l.contains("--secret=-")),
        "a Secret Manager read was attempted for an unset environment-only credential"
    );

    // The point of declaring it: a profile that does NOT list it scrubs it.
    w.auth(
        SA_KEY_GOOD,
        &[("VITRUVIAN_PROFILE", "onlytok"), ("ENVCRED", BIG_D)],
    );
    assert_eq!(
        w.effective("ENVCRED", BIG_D),
        "",
        "an environment-only credential escaped the boundary"
    );
}

// ---------------------------------------------------------------------------
// build cache
// ---------------------------------------------------------------------------

#[test]
fn a_declaring_profile_configures_the_cache_with_the_key_in_env() {
    let w = World::new();
    let out = w.cache_auth("cached", &[("BUILDBUDDY_API_KEY", BB_KEY)]);
    let cargv = w.read("cache-setup.argv");
    let cenv = w.read("cache-setup.env");
    assert_contains(
        "a declaring profile configures the cache",
        &cargv,
        "--cache buildbuddy",
    );
    assert_contains("…without touching CI secrets", &cargv, "--no-ci");
    assert_not_contains("the API key never reaches argv", &cargv, BB_KEY);
    assert_contains(
        "…it is handed over in the environment instead",
        &cenv,
        &format!("KEY={BB_KEY}"),
    );
    assert_not_contains(
        "…and the workspace is pinned, not guessed",
        &cenv,
        "WS=<unset>",
    );
    assert_contains(
        "…and it is reported as configured",
        &out,
        "default for plain bazel",
    );
}

#[test]
fn the_cache_is_never_configured_without_entitlement() {
    let w = World::new();
    w.cache_auth("cached", &[("BUILDBUDDY_API_KEY", "dummy-key")]);
    assert!(
        w.read("cache-setup.argv").is_empty(),
        "the cache was configured with a placeholder key"
    );

    w.cache_auth("onlytok", &[("BUILDBUDDY_API_KEY", BB_KEY)]);
    assert!(
        w.read("cache-setup.argv").is_empty(),
        "an unentitled profile still configured the cache"
    );

    w.cache_auth("nobazel", &[("BUILDBUDDY_API_KEY", BB_KEY)]);
    assert!(
        w.read("cache-setup.argv").is_empty(),
        "the cache was configured for a session with no bazel"
    );
}

#[test]
fn an_undeclared_cache_key_is_not_used_even_when_no_row_names_it() {
    // The scrub only blanks what SOME row declares. With no row naming
    // BUILDBUDDY_API_KEY nothing scrubs it, and entitlement alone must stop an
    // ambient key from giving a bazel profile cache write access.
    let w = World::new();
    fs::write(
        w.p("profiles.tsv"),
        "bazelonly bazel sa-pinned@x.iam.gserviceaccount.com proj-a TOK=tok-secret Bazel, no cache key.\n",
    )
    .unwrap();
    w.cache_auth("bazelonly", &[("BUILDBUDDY_API_KEY", BB_KEY)]);
    assert!(
        w.read("cache-setup.argv").is_empty(),
        "an ambient key no profile declares configured the cache"
    );
}

#[test]
fn a_failed_cache_configuration_is_not_fatal() {
    let w = World::new();
    w.make_cache_setup("fail");
    let out = w.cache_auth("cached", &[("BUILDBUDDY_API_KEY", BB_KEY)]);
    assert_contains(
        "a failed configuration is reported, not fatal",
        &out,
        "builds stay local",
    );
    assert!(
        w.session_env()
            .lines()
            .any(|l| l.starts_with("export TOK=")),
        "a build-cache failure cost the session its credentials"
    );
}

#[test]
fn a_partial_cache_write_is_cleaned_but_a_real_user_bazelrc_never_is() {
    let w = World::new();
    w.make_cache_setup("partial");
    let out = w.cache_auth("cached", &[("BUILDBUDDY_API_KEY", BB_KEY)]);
    assert_contains(
        "a partial write is not mistaken for success",
        &out,
        "builds stay local",
    );
    assert!(
        !w.p("ws/user.bazelrc").exists(),
        "an empty user.bazelrc was left behind"
    );

    // Only ever a ZERO-BYTE file: anything with content is a developer's own.
    w.make_cache_setup("fail");
    let _ = fs::remove_dir_all(w.p("ws"));
    fs::create_dir_all(w.p("ws")).unwrap();
    fs::write(w.p("ws/user.bazelrc"), "common --disk_cache=/tmp/mine\n").unwrap();
    w.cache_auth_keep_ws("cached", &[("BUILDBUDDY_API_KEY", BB_KEY)]);
    assert_contains(
        "a non-empty user.bazelrc is never deleted",
        &w.read("ws/user.bazelrc"),
        "disk_cache",
    );
}

// ---------------------------------------------------------------------------
// multiple profiles
// ---------------------------------------------------------------------------

#[test]
fn combined_profiles_keep_separate_identities() {
    let w = World::new();
    let out = w.auth(
        SA_KEY_GOOD,
        &[
            ("VITRUVIAN_PROFILE", "pinned,second"),
            ("VITRUVIAN_CLOUD_KEY_SECOND", SA_KEY_SECOND),
        ],
    );
    let argv = w.argv();
    assert_contains("both identities are activated", &argv, "sa-key-pinned.json");
    assert_contains("…each from its own key file", &argv, "sa-key-second.json");

    let reads = w.secret_reads();
    let tok = reads
        .iter()
        .find(|l| l.contains("--secret=tok-secret"))
        .cloned()
        .unwrap_or_default();
    let extra = reads
        .iter()
        .find(|l| l.contains("--secret=extra-secret"))
        .cloned()
        .unwrap_or_default();
    assert_contains(
        "profile 1's secret is read as profile 1's SA",
        &tok,
        "--account=sa-pinned@x.iam.gserviceaccount.com",
    );
    assert_contains(
        "profile 2's secret is read as profile 2's SA",
        &extra,
        "--account=sa-second@x.iam.gserviceaccount.com",
    );
    assert_contains(
        "…and with profile 2's own project",
        &extra,
        "--project=proj-b",
    );
    assert_not_contains(
        "profile 2's SA never reads profile 1's secret",
        &tok,
        "sa-second@",
    );

    let env = w.session_env();
    for v in ["TOK", "OTHER", "EXTRA"] {
        assert!(
            env.lines().any(|l| l.starts_with(&format!("export {v}="))),
            "{v} missing from the combined session env"
        );
    }

    assert_contains(
        "the first listed identity is the primary",
        &out,
        "sa-pinned@x.iam.gserviceaccount.com (project proj-a) — PRIMARY",
    );
    assert!(
        env.lines()
            .any(|l| l.starts_with("export GOOGLE_APPLICATION_CREDENTIALS=")
                && l.ends_with("sa-key-pinned.json")),
        "GOOGLE_APPLICATION_CREDENTIALS does not point at the primary key:\n{env}"
    );
    assert_contains(
        "…the non-primary is reported as such",
        &out,
        "reads its own secrets only",
    );
}

#[test]
fn listing_order_chooses_the_primary() {
    let w = World::new();
    let out = w.auth(
        SA_KEY_SECOND,
        &[
            ("VITRUVIAN_PROFILE", "second,pinned"),
            ("VITRUVIAN_CLOUD_KEY_PINNED", SA_KEY_GOOD),
        ],
    );
    assert_contains(
        "listing order chooses the primary",
        &out,
        "sa-second@x.iam.gserviceaccount.com (project proj-b) — PRIMARY",
    );
}

#[test]
fn a_conflicting_secret_mapping_is_refused() {
    let w = World::new();
    let out = w.auth(SA_KEY_GOOD, &[("VITRUVIAN_PROFILE", "pinned,clashing")]);
    assert_contains(
        "a conflicting secret mapping is refused",
        &out,
        "REFUSING TOK for profile 'clashing'",
    );
    assert_contains(
        "…naming both secrets",
        &out,
        "this one says 'different-secret'",
    );
    assert_not_contains(
        "…and the conflicting secret is never read",
        &w.argv(),
        "--secret=different-secret",
    );
}

#[test]
fn a_repeated_profile_is_deduped() {
    let w = World::new();
    let out = w.auth(SA_KEY_GOOD, &[("VITRUVIAN_PROFILE", "pinned,pinned")]);
    assert_not_contains(
        "a repeated profile is deduped, not refused",
        &out,
        "REFUSING",
    );
    let n = w.argv().matches("--secret=tok-secret").count();
    assert_eq!(n, 1, "a deduped profile read its secret {n} times");
    // The secret mapping check above would hide a repeat; the identity would
    // still be activated twice.
    let n = w.argv().matches("activate-service-account").count();
    assert_eq!(n, 1, "a deduped profile was authenticated {n} times");
}

#[test]
fn one_bad_name_refuses_the_whole_list() {
    let w = World::new();
    let out = w.auth(SA_KEY_GOOD, &[("VITRUVIAN_PROFILE", "pinned,nope")]);
    assert_contains(
        "an unknown profile in the list is refused",
        &out,
        "is not a known profile",
    );
    assert!(
        w.argv().is_empty(),
        "a partial bootstrap happened despite an invalid list"
    );
}

// ---------------------------------------------------------------------------
// shipped manifest
// ---------------------------------------------------------------------------

/// The `grep -qiE` the shell test ran: a private-key header, a Google access
/// token, a GitHub PAT, or a Pulumi token.
fn looks_like_a_credential(text: &str) -> bool {
    let lower = text.to_lowercase();
    if lower.contains("ya29.") || lower.contains("ghp_") {
        return true;
    }
    for kind in ["", "rsa ", "ec ", "openssh "] {
        if lower.contains(&format!("begin {kind}private key")) {
            return true;
        }
    }
    let b = lower.as_bytes();
    (0..b.len()).any(|i| {
        b[i..].starts_with(b"pul-")
            && b.len() >= i + 44
            && b[i + 4..i + 44].iter().all(|c| c.is_ascii_hexdigit())
    })
}

#[test]
fn the_shipped_manifest_is_well_formed_and_credential_free() {
    let text = fs::read_to_string(shipped_profiles()).expect("profiles.tsv is missing");
    let rows: Vec<Vec<&str>> = text
        .lines()
        .map(|l| l.split_whitespace().collect::<Vec<_>>())
        .filter(|f| !f.is_empty() && !f[0].starts_with('#'))
        .collect();
    assert!(
        !rows.is_empty(),
        "the shipped manifest declares no profiles"
    );
    let bad: Vec<&str> = rows.iter().filter(|f| f.len() < 6).map(|f| f[0]).collect();
    assert!(
        bad.is_empty(),
        "under-specified rows in profiles.tsv: {bad:?}"
    );
    assert!(
        !looks_like_a_credential(&text),
        "profiles.tsv contains something that looks like a credential"
    );
}

#[test]
fn the_credential_check_itself_catches_credentials() {
    // Without this, a check that matched nothing would pass forever.
    assert!(looks_like_a_credential("TOK=ghp_abc"));
    assert!(looks_like_a_credential("-----BEGIN RSA PRIVATE KEY-----"));
    assert!(looks_like_a_credential(&format!(
        "x pul-{}",
        "a1".repeat(20)
    )));
    assert!(!looks_like_a_credential(
        "GH_TOKEN=claude-cloud-github-token"
    ));
}

// ---------------------------------------------------------------------------
// added with the port
// ---------------------------------------------------------------------------

#[test]
fn session_env_round_trips_awkward_values_through_bash() {
    // session.env is bash syntax sourced by every Bash tool call; whatever the
    // secret holds, bash must read back exactly that.
    for value in [
        "plain-token-value-0123456789",
        "with space and 'single' and \"double\" quotes",
        "dollar $HOME and `backtick` and \\ backslash",
        "~leading-tilde-and-#hash-and-glob-*?[x]-{a,b}",
        // Bare, bash would expand the first to $HOME/... and drop the second
        // as a comment: both only mean something at the start of a word.
        "~/tilde-must-stay-literal-0123456789",
        "#leading-hash-is-not-a-comment-0123",
        "multi\nline\tand-tab-0123456789",
        "unicode-é-ü-0123456789",
    ] {
        let w = World::new();
        w.make_gcloud_serving("ok", value);
        w.auth(SA_KEY_GOOD, &[("VITRUVIAN_PROFILE", "onlytok")]);
        assert_eq!(
            w.effective("TOK", ""),
            value,
            "bash read back a different value"
        );
        assert_eq!(mode(&w.state("session.env")), 0o600);
    }
}

#[test]
fn a_reused_key_file_is_made_private() {
    // The SA key file survives from an earlier session; if it was left 0644
    // (by hand, or an older tool), rewriting it must not keep that mode.
    let w = World::new();
    let _ = fs::remove_dir_all(w.p("state"));
    fs::create_dir_all(w.p("state")).unwrap();
    fs::write(w.state("sa-key-pinned.json"), "stale").unwrap();
    fs::set_permissions(
        w.state("sa-key-pinned.json"),
        fs::Permissions::from_mode(0o644),
    )
    .unwrap();
    fs::create_dir_all(w.p("home")).unwrap();
    w.exec(
        &["auth"],
        &[
            ("VITRUVIAN_PROFILE", "pinned".into()),
            ("VITRUVIAN_CLOUD_KEY", SA_KEY_GOOD.into()),
        ],
    );
    assert_contains(
        "the key was rewritten",
        &w.argv(),
        "activate-service-account",
    );
    assert_eq!(
        mode(&w.state("sa-key-pinned.json")),
        0o600,
        "a reused 0644 key file stayed world-readable"
    );
}

#[test]
fn whoami_reads_a_session_env_written_by_bash() {
    // A session resumed after this port still has the file the shell version
    // wrote with bash's own `printf %q`.
    let w = World::new();
    fs::create_dir_all(w.p("state")).unwrap();
    let tricky = "it's a \"tricky\" $value with spaces";
    let st = Command::new("bash")
        .arg("-c")
        .arg(r#"printf 'export %s=%q\n' TOK "$1" OTHER short > "$2""#)
        .arg("_")
        .arg(tricky)
        .arg(w.state("session.env"))
        .status()
        .unwrap();
    assert!(st.success());
    let (out, rc) = w.exec(&["whoami"], &[("VITRUVIAN_PROFILE", "pinned".to_string())]);
    assert_contains(
        "whoami sees the bash-quoted value at its real length",
        &out,
        &format!(
            "TOK                    set ({} bytes)",
            tricky.chars().count()
        ),
    );
    assert_contains(
        "…and a short one as a placeholder",
        &out,
        "OTHER                  placeholder only (5 bytes",
    );
    assert_eq!(rc, 1, "an unsatisfied profile must fail the whoami gate");
}

#[test]
fn whoami_is_a_gate() {
    let w = World::new();
    // nocreds needs only gh: satisfied once gh exists.
    let fakebin = w.p("fakebin");
    fs::create_dir_all(&fakebin).unwrap();
    write_exec(
        &fakebin.join("gh"),
        "#!/usr/bin/env bash\necho 'gh version 9.9.9'\n",
    );
    let path = format!(
        "{}:{}",
        fakebin.display(),
        std::env::var("PATH").unwrap_or_default()
    );
    let (out, rc) = w.exec(
        &["whoami"],
        &[("VITRUVIAN_PROFILE", "nocreds".into()), ("PATH", path)],
    );
    assert_eq!(rc, 0, "a satisfied profile failed whoami:\n{out}");
    assert_contains(
        "tools are reported with their version",
        &out,
        "  ✓ gh         gh version 9.9.9",
    );
    assert_contains(
        "…and the identity as none by design",
        &out,
        "identity   – none (holds no credentials by design)",
    );
    assert_contains(
        "…and the header names the profile",
        &out,
        "profile(s): nocreds",
    );

    let (out, rc) = w.exec(&["whoami"], &[("VITRUVIAN_PROFILE", "nocreds".into())]);
    assert_eq!(rc, 1, "a missing tool passed the whoami gate:\n{out}");
    assert_contains(
        "a missing tool is named",
        &out,
        "  ✗ gh         not installed",
    );
}

#[test]
fn cli_contract() {
    let w = World::new();

    let (out, rc) = w.exec(&["profiles"], &[]);
    assert_eq!(rc, 0);
    assert_contains(
        "profiles lists each row",
        &out,
        "  pinned     Pinned test profile.\n",
    );
    assert_contains("…after the header", &out, "VITRUVIAN_PROFILE=core,homelab");

    let (out, rc) = w.exec(
        &["profiles"],
        &[("CLOUD_BOOTSTRAP_PROFILES", w.s("missing.tsv"))],
    );
    assert_eq!(rc, 1, "profiles with no manifest must fail");
    assert_contains("…naming the file", &out, "profile manifest not found");

    let (out, rc) = w.exec(&["bogus"], &[]);
    assert_eq!(rc, 2, "an unknown subcommand must exit 2");
    assert_contains("…and say so", &out, "unknown subcommand 'bogus'");

    let (out, rc) = w.exec(&["whoami", "--help"], &[]);
    assert_eq!(rc, 0);
    assert_contains(
        "--help prints the usage",
        &out,
        "Usage: bazel run //tools/cloud-bootstrap",
    );

    // Cloud sessions only, unless --force.
    let (out, rc) = w.exec(
        &["auth"],
        &[
            ("CLAUDE_CODE_REMOTE", "".into()),
            ("VITRUVIAN_PROFILE", "pinned".into()),
        ],
    );
    assert_eq!(rc, 0);
    assert_contains("a local run does nothing", &out, "not a cloud session");
    assert!(w.argv().is_empty(), "a local run still called gcloud");
    let (out, _) = w.exec(
        &["auth", "--force", "--profile", "nocreds", "--bogus"],
        &[
            ("CLAUDE_CODE_REMOTE", "".into()),
            ("VITRUVIAN_PROFILE", "pinned".into()),
        ],
    );
    assert_contains("--force runs it anyway", &out, "declares no GCP identity");
    assert_contains(
        "…--profile overrides the environment",
        &out,
        "profile 'nocreds'",
    );
    assert_contains(
        "…and an unknown flag is ignored, loudly",
        &out,
        "ignoring unknown argument '--bogus'",
    );

    // The best-effort subcommands exit 0 even when nothing could be done.
    let (_, rc) = w.exec(&["install"], &[("VITRUVIAN_PROFILE", "nope".into())]);
    assert_eq!(rc, 0, "install must never fail the session");
}
