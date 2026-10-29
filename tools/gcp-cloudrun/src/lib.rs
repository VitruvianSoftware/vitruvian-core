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

//! gcp-cloudrun describe: a read-only look at a Cloud Run service or revision.
//!
//! It resolves the GCP project from `infrastructure/gcp-identities.tsv` (or an
//! app's `Pulumi.<env>.yaml`), mints a short-lived token with `//tools/gcp-token`
//! for a human operator account, and runs a fixed set of `gcloud` reads:
//! describe, list and log reads. Every gcloud argv is built through [`gcloud`],
//! which refuses any verb outside [`ALLOWED_VERBS`], and the runner checks the
//! argv again before it executes anything. Nothing here can deploy, update,
//! delete, replace, move traffic or change IAM.

use std::fs;
use std::path::{Path, PathBuf};

/// The only gcloud verbs this tool will ever run.
pub const ALLOWED_VERBS: &[&str] = &["describe", "list", "read"];

/// The command groups it may run them in (`gcloud <group...> <verb>`).
const ALLOWED_GROUPS: &[&[&str]] = &[&["run", "services"], &["run", "revisions"], &["logging"]];

pub const DEFAULT_REGION: &str = "us-central1";
pub const DEFAULT_SINCE: &str = "3h";
pub const DEFAULT_LIMIT: &str = "200";

/// The human operator account a token is minted for when the identity map's
/// account column is a service account. App rows name a WIF deploy service
/// account that only CI can impersonate; it cannot be minted locally. Every
/// first-party app deploys under this personal account today (AGENTS.md, "GCP
/// identity is pinned per-infrastructure").
pub const DEFAULT_OPERATOR_ACCOUNT: &str = "james.nguyen@gmail.com";

pub const IDENTITY_MAP: &str = "infrastructure/gcp-identities.tsv";

pub const USAGE: &str = "\
usage: bazel run //tools/gcp-cloudrun:describe -- (--app <name> | --infra <dir> | --project <id>)
                                                  (--service <name> | --revision <name> [--service <name>])
                                                  [--env <env>] [--region <r>] [--since <dur>]
                                                  [--limit <n>] [--account <email>]

Read-only look at a Cloud Run service or revision: describe (with the traffic
split), the revision list, and recent logs. Runs only gcloud describe/list/read.

Where to look (one of):
  --app <name>       an app under apps/*/<name>, using its infra/app Pulumi project
  --infra <dir>      a Pulumi project dir listed in infrastructure/gcp-identities.tsv
  --project <id>     a GCP project id directly (skips the lookup)
  --env <env>        take the project from <infra>/Pulumi.<env>.yaml (gcp:project)
                     instead of the identity map; dev|nonprod|prod or the full name

What to look at:
  --service <name>   service: describe + traffic, revision list, logs
  --revision <name>  revision: describe, logs for that revision only

Options:
  --region <r>       Cloud Run region (default us-central1)
  --since <dur>      log window, e.g. 30m, 3h, 2d (default 3h)
  --limit <n>        max log entries (default 200)
  --account <email>  account to mint the token for. Default: the identity map's
                     account if it is a person, otherwise james.nguyen@gmail.com
                     (app rows name a CI-only WIF service account)
  -h, --help         this help

Example:
  bazel run //tools/gcp-cloudrun:describe -- --app oauth-user-inspector --env dev \\
      --service oauth-user-inspector-development --since 6h
";

// --- the write guard ---------------------------------------------------------

/// A gcloud argv (without the leading `gcloud`) that has passed [`guard`].
/// The field is private: the only way to get one is through [`gcloud`].
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GcloudCmd(Vec<String>);

impl GcloudCmd {
    pub fn argv(&self) -> &[String] {
        &self.0
    }
}

/// Refuse any argv whose command is not `<allowed group> <allowed verb>`.
pub fn guard(argv: &[String]) -> Result<(), String> {
    let group = ALLOWED_GROUPS
        .iter()
        .find(|g| argv.len() > g.len() && g.iter().zip(argv).all(|(a, b)| *a == b))
        .ok_or_else(|| {
            format!(
                "refusing gcloud {}: not a Cloud Run or logging read",
                argv.join(" ")
            )
        })?;
    let verb = &argv[group.len()];
    if !ALLOWED_VERBS.contains(&verb.as_str()) {
        return Err(format!(
            "refusing gcloud {}: verb '{}' is not one of {}",
            argv.join(" "),
            verb,
            ALLOWED_VERBS.join(", ")
        ));
    }
    // Credentials only ever travel through the environment.
    if argv
        .iter()
        .any(|a| a.starts_with("--access-token") || a.starts_with("--impersonate"))
    {
        return Err("refusing gcloud: credentials must not be passed on argv".into());
    }
    Ok(())
}

/// Build one gcloud argv: `<group...> <verb> <rest...>`, through [`guard`].
pub fn gcloud(group: &[&str], verb: &str, rest: &[String]) -> Result<GcloudCmd, String> {
    let mut argv: Vec<String> = group.iter().map(|s| s.to_string()).collect();
    argv.push(verb.to_string());
    argv.extend(rest.iter().cloned());
    guard(&argv)?;
    Ok(GcloudCmd(argv))
}

// --- the identity map ---------------------------------------------------------

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct IdentityRow {
    pub infra_dir: String,
    pub account: String,
    pub project: String,
}

/// Parse gcp-identities.tsv the way //tools/pulumi resolve_identity does:
/// whitespace-separated, `#` comments and blank lines skipped, `-` rows are
/// reference-only.
pub fn parse_identity_map(text: &str) -> Vec<IdentityRow> {
    text.lines()
        .filter_map(|line| {
            let f: Vec<&str> = line.split_whitespace().collect();
            if f.is_empty() || f[0].starts_with('#') || f[0] == "-" || f.len() < 3 {
                return None;
            }
            Some(IdentityRow {
                infra_dir: f[0].to_string(),
                account: f[1].to_string(),
                project: f[2].to_string(),
            })
        })
        .collect()
}

pub fn lookup<'a>(rows: &'a [IdentityRow], infra_dir: &str) -> Option<&'a IdentityRow> {
    let want = infra_dir.trim_end_matches('/');
    rows.iter().find(|r| r.infra_dir == want)
}

pub fn is_service_account(account: &str) -> bool {
    account.ends_with(".iam.gserviceaccount.com")
}

/// The account to mint a token for: `--account` if given, else the map's
/// account when it is a person, else [`DEFAULT_OPERATOR_ACCOUNT`].
pub fn operator_account(map_account: Option<&str>, override_account: Option<&str>) -> String {
    if let Some(a) = override_account {
        return a.to_string();
    }
    match map_account {
        Some(a) if a.contains('@') && !is_service_account(a) => a.to_string(),
        _ => DEFAULT_OPERATOR_ACCOUNT.to_string(),
    }
}

/// `dev` -> `development` and friends; anything else is taken as written.
pub fn normalize_env(env: &str) -> String {
    match env {
        "dev" => "development",
        "nonprod" | "staging" => "nonproduction",
        "prod" => "production",
        other => other,
    }
    .to_string()
}

/// The `gcp:project` value from a Pulumi stack file.
pub fn pulumi_stack_project(yaml: &str) -> Option<String> {
    yaml.lines().find_map(|l| {
        let v = l.trim().strip_prefix("gcp:project:")?;
        let v = v
            .split('#')
            .next()?
            .trim()
            .trim_matches(|c| c == '"' || c == '\'');
        (!v.is_empty()).then(|| v.to_string())
    })
}

/// `apps/*/<app>/infra/app`, relative to the workspace.
pub fn resolve_app_infra(workspace: &Path, app: &str) -> Result<String, String> {
    let apps = workspace.join("apps");
    let mut found = Vec::new();
    let entries =
        fs::read_dir(&apps).map_err(|e| format!("cannot read {}: {}", apps.display(), e))?;
    for cat in entries.flatten() {
        let rel = format!(
            "apps/{}/{}/infra/app",
            cat.file_name().to_string_lossy(),
            app
        );
        if workspace.join(&rel).is_dir() {
            found.push(rel);
        }
    }
    found.sort();
    match found.len() {
        1 => Ok(found.remove(0)),
        0 => Err(format!(
            "no app '{}' with an infra/app project under apps/*/",
            app
        )),
        _ => Err(format!("app '{}' is ambiguous: {}", app, found.join(", "))),
    }
}

// --- arguments ------------------------------------------------------------------

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Args {
    pub app: Option<String>,
    pub infra: Option<String>,
    pub project: Option<String>,
    pub env: Option<String>,
    pub service: Option<String>,
    pub revision: Option<String>,
    pub region: String,
    pub since: String,
    pub limit: String,
    pub account: Option<String>,
    pub help: bool,
}

/// Cloud Run names (services, revisions) and regions: lowercase letters,
/// digits and hyphens. Checked because they are interpolated into a logging filter.
/// It must start with a letter (as Cloud Run names, regions and project ids
/// do), so a value can never be read by gcloud as a flag.
fn valid_name(s: &str) -> bool {
    s.as_bytes().first().is_some_and(|c| c.is_ascii_lowercase())
        && s.len() <= 100
        && s.bytes()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == b'-')
}

fn valid_project(s: &str) -> bool {
    valid_name(s) && s.len() <= 30
}

fn valid_since(s: &str) -> bool {
    if s.is_empty() || !s.is_ascii() {
        return false;
    }
    let (n, unit) = s.split_at(s.len().saturating_sub(1));
    !n.is_empty()
        && n.bytes().all(|c| c.is_ascii_digit())
        && matches!(unit, "s" | "m" | "h" | "d" | "w")
}

pub fn parse_args(argv: &[String]) -> Result<Args, String> {
    let mut a = Args {
        region: DEFAULT_REGION.into(),
        since: DEFAULT_SINCE.into(),
        limit: DEFAULT_LIMIT.into(),
        ..Default::default()
    };
    let mut it = argv.iter();
    while let Some(flag) = it.next() {
        if flag == "-h" || flag == "--help" {
            a.help = true;
            continue;
        }
        let (name, inline) = match flag.split_once('=') {
            Some((n, v)) if n.starts_with("--") => (n.to_string(), Some(v.to_string())),
            _ => (flag.clone(), None),
        };
        let mut value = || -> Result<String, String> {
            match &inline {
                Some(v) => Ok(v.clone()),
                None => it
                    .next()
                    .cloned()
                    .ok_or_else(|| format!("{} needs a value", name)),
            }
        };
        match name.as_str() {
            "--app" => a.app = Some(value()?),
            "--infra" => a.infra = Some(value()?),
            "--project" => a.project = Some(value()?),
            "--env" => a.env = Some(value()?),
            "--service" => a.service = Some(value()?),
            "--revision" => a.revision = Some(value()?),
            "--region" => a.region = value()?,
            "--since" => a.since = value()?,
            "--limit" => a.limit = value()?,
            "--account" => a.account = Some(value()?),
            other => return Err(format!("unknown argument: {}", other)),
        }
    }
    if a.help {
        return Ok(a);
    }
    if a.service.is_none() && a.revision.is_none() {
        return Err("give --service <name> or --revision <name>".into());
    }
    if [&a.app, &a.infra, &a.project]
        .iter()
        .filter(|o| o.is_some())
        .count()
        != 1
    {
        return Err("give exactly one of --app, --infra or --project".into());
    }
    if a.env.is_some() && a.project.is_some() {
        return Err("--env picks a project from the app's Pulumi stack; it cannot be combined with --project".into());
    }
    for (what, v) in [("--service", &a.service), ("--revision", &a.revision)] {
        if let Some(v) = v {
            if !valid_name(v) {
                return Err(format!(
                    "{} '{}' is not a Cloud Run name (a-z, 0-9, -)",
                    what, v
                ));
            }
        }
    }
    if let Some(p) = &a.project {
        if !valid_project(p) {
            return Err(format!("--project '{}' is not a GCP project id", p));
        }
    }
    if !valid_name(&a.region) {
        return Err(format!("--region '{}' is not a region name", a.region));
    }
    if !valid_since(&a.since) {
        return Err(format!(
            "--since '{}' must look like 30m, 3h or 2d",
            a.since
        ));
    }
    if a.limit.is_empty() || !a.limit.bytes().all(|c| c.is_ascii_digit()) {
        return Err(format!("--limit '{}' must be a number", a.limit));
    }
    if let Some(acct) = &a.account {
        if !acct.contains('@') {
            return Err(format!("--account '{}' is not an email address", acct));
        }
    }
    Ok(a)
}

// --- the plan -------------------------------------------------------------------

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Resolved {
    pub project: String,
    pub account: String,
    /// Where the project came from, for the header line.
    pub source: String,
}

/// Work out the project and the account to mint for.
pub fn resolve(workspace: &Path, a: &Args) -> Result<Resolved, String> {
    if let Some(p) = &a.project {
        return Ok(Resolved {
            project: p.clone(),
            account: operator_account(None, a.account.as_deref()),
            source: "--project".into(),
        });
    }
    let infra = match (&a.infra, &a.app) {
        (Some(i), _) => i.trim_end_matches('/').to_string(),
        (None, Some(app)) => resolve_app_infra(workspace, app)?,
        _ => unreachable!("parse_args requires one of --app, --infra, --project"),
    };
    let map_path = workspace.join(IDENTITY_MAP);
    let map_text = fs::read_to_string(&map_path)
        .map_err(|e| format!("cannot read {}: {}", map_path.display(), e))?;
    let rows = parse_identity_map(&map_text);
    let row = lookup(&rows, &infra);
    let account = operator_account(row.map(|r| r.account.as_str()), a.account.as_deref());

    if let Some(env) = &a.env {
        let env = normalize_env(env);
        let stack = workspace.join(&infra).join(format!("Pulumi.{}.yaml", env));
        let yaml = fs::read_to_string(&stack)
            .map_err(|e| format!("cannot read {}: {}", stack.display(), e))?;
        let project = pulumi_stack_project(&yaml)
            .ok_or_else(|| format!("{} has no gcp:project", stack.display()))?;
        if !valid_project(&project) {
            return Err(format!(
                "{}: gcp:project '{}' is not a project id",
                stack.display(),
                project
            ));
        }
        return Ok(Resolved {
            project,
            account,
            source: format!("{}/Pulumi.{}.yaml", infra, env),
        });
    }

    let row = row.ok_or_else(|| {
        format!(
            "{} is not in {} (pass --env or --project)",
            infra, IDENTITY_MAP
        )
    })?;
    if row.project == "-" || !valid_project(&row.project) {
        return Err(format!(
            "{} declares no GCP project for {} (pass --env or --project)",
            IDENTITY_MAP, infra
        ));
    }
    Ok(Resolved {
        project: row.project.clone(),
        account,
        source: IDENTITY_MAP.into(),
    })
}

pub fn log_filter(service: Option<&str>, revision: Option<&str>) -> String {
    let mut f = String::from("resource.type=\"cloud_run_revision\"");
    if let Some(s) = service {
        f.push_str(&format!(" AND resource.labels.service_name=\"{}\"", s));
    }
    if let Some(r) = revision {
        f.push_str(&format!(" AND resource.labels.revision_name=\"{}\"", r));
    }
    f
}

/// Every gcloud command for one invocation, in order. All of them pass [`guard`].
pub fn plan(a: &Args, project: &str) -> Result<Vec<GcloudCmd>, String> {
    let s = |v: &str| v.to_string();
    let loc = vec![
        format!("--project={}", project),
        format!("--region={}", a.region),
    ];
    let mut cmds = Vec::new();
    match (&a.revision, &a.service) {
        (Some(rev), _) => {
            let mut rest = vec![rev.clone()];
            rest.extend(loc.iter().cloned());
            cmds.push(gcloud(&["run", "revisions"], "describe", &rest)?);
        }
        (None, Some(svc)) => {
            let mut rest = vec![svc.clone()];
            rest.extend(loc.iter().cloned());
            cmds.push(gcloud(&["run", "services"], "describe", &rest)?);
            let mut rest = vec![format!("--service={}", svc)];
            rest.extend(loc.iter().cloned());
            cmds.push(gcloud(&["run", "revisions"], "list", &rest)?);
        }
        (None, None) => return Err("give --service <name> or --revision <name>".into()),
    }
    let filter = log_filter(a.service.as_deref(), a.revision.as_deref());
    cmds.push(gcloud(
        &["logging"],
        "read",
        &[
            filter,
            format!("--project={}", project),
            format!("--freshness={}", a.since),
            format!("--limit={}", a.limit),
            s("--order=desc"),
            s("--format=value(timestamp,severity,resource.labels.revision_name,httpRequest.status,httpRequest.requestUrl,textPayload,jsonPayload.message)"),
        ],
    )?);
    Ok(cmds)
}

// --- running ----------------------------------------------------------------------

/// Side effects, injected so tests can see every argv without running gcloud.
pub trait Runner {
    /// A short-lived access token for `account`.
    fn mint_token(&mut self, account: &str) -> Result<String, String>;
    /// Run `gcloud <argv>` with the token in its environment; return the exit code.
    fn gcloud(&mut self, cmd: &GcloudCmd, token: &str) -> i32;
    fn say(&mut self, line: &str);
    fn warn(&mut self, line: &str);
    /// True once the user has asked to stop (Ctrl-C, SIGTERM, SIGHUP).
    fn interrupted(&self) -> bool {
        false
    }
}

pub fn run<R: Runner>(argv: &[String], workspace: &Path, r: &mut R) -> i32 {
    let a = match parse_args(argv) {
        Ok(a) => a,
        Err(e) => {
            r.warn(&format!("gcp-cloudrun: {}\n\n{}", e, USAGE));
            return 2;
        }
    };
    if a.help {
        r.say(USAGE);
        return 0;
    }
    let res = match resolve(workspace, &a) {
        Ok(v) => v,
        Err(e) => {
            r.warn(&format!("gcp-cloudrun: {}", e));
            return 2;
        }
    };
    let cmds = match plan(&a, &res.project) {
        Ok(c) => c,
        Err(e) => {
            r.warn(&format!("gcp-cloudrun: {}", e));
            return 2;
        }
    };
    r.warn(&format!(
        "gcp-cloudrun: project {} (from {}), region {}, as {}",
        res.project, res.source, a.region, res.account
    ));
    let token = match r.mint_token(&res.account) {
        Ok(t) => t,
        Err(e) => {
            r.warn(&format!(
                "gcp-cloudrun: could not mint a token for {}: {}",
                res.account, e
            ));
            return 1;
        }
    };
    let mut code = 0;
    for cmd in &cmds {
        if r.interrupted() {
            r.warn("gcp-cloudrun: interrupted");
            return 130;
        }
        r.say(&format!("\n== gcloud {} ==", cmd.argv().join(" ")));
        let c = r.gcloud(cmd, &token);
        if c != 0 && code == 0 {
            code = c;
        }
    }
    if r.interrupted() {
        r.warn("gcp-cloudrun: interrupted");
        return 130;
    }
    code
}

/// Signals, without a libc crate. Ctrl-C goes to gcloud and to us; if it
/// killed us, the token file would outlive the run. So we catch SIGINT,
/// SIGTERM and SIGHUP with a handler that only records them: gcloud still
/// stops (a caught handler is reset to the default across exec, unlike an
/// ignored signal), and we get back control to delete the file and exit.
pub mod signals {
    use std::sync::atomic::{AtomicBool, Ordering};

    static INTERRUPTED: AtomicBool = AtomicBool::new(false);
    const SIGHUP: i32 = 1;
    const SIGINT: i32 = 2;
    const SIGTERM: i32 = 15;

    extern "C" {
        fn signal(sig: i32, handler: extern "C" fn(i32)) -> usize;
        fn kill(pid: i32, sig: i32) -> i32;
    }

    extern "C" fn record(_: i32) {
        INTERRUPTED.store(true, Ordering::SeqCst);
    }

    pub fn install() {
        for s in [SIGHUP, SIGINT, SIGTERM] {
            // SAFETY: `record` only stores to an atomic, which is async-signal-safe.
            unsafe {
                signal(s, record);
            }
        }
    }

    pub fn interrupted() -> bool {
        INTERRUPTED.load(Ordering::SeqCst)
    }

    /// Whether a process with this pid exists (that we may signal).
    pub fn alive(pid: i32) -> bool {
        // SAFETY: signal 0 only checks for existence; nothing is delivered.
        pid > 0 && unsafe { kill(pid, 0) } == 0
    }
}

const TOKEN_FILE_PREFIX: &str = "gcp-cloudrun-";
const TOKEN_FILE_SUFFIX: &str = ".token";

/// Delete token files left in `dir` by runs whose process is gone (a
/// SIGKILL cannot be caught). Returns how many were removed.
pub fn sweep_stale_token_files(dir: &Path) -> usize {
    let Ok(entries) = fs::read_dir(dir) else {
        return 0;
    };
    let mut removed = 0;
    for e in entries.flatten() {
        let name = e.file_name().to_string_lossy().to_string();
        let Some(pid) = name
            .strip_prefix(TOKEN_FILE_PREFIX)
            .and_then(|r| r.strip_suffix(TOKEN_FILE_SUFFIX))
            .and_then(|p| p.parse::<i32>().ok())
        else {
            continue;
        };
        if pid as u32 != std::process::id()
            && !signals::alive(pid)
            && fs::remove_file(e.path()).is_ok()
        {
            removed += 1;
        }
    }
    removed
}

/// The real runner: `//tools/gcp-token` for the token, `gcloud` from PATH.
pub struct SystemRunner {
    pub gcp_token_bin: PathBuf,
    pub gcloud_bin: String,
    token_file: Option<PathBuf>,
}

impl SystemRunner {
    /// Also installs the signal handlers and sweeps token files that earlier,
    /// killed runs left behind.
    pub fn new(gcp_token_bin: PathBuf, gcloud_bin: String) -> Self {
        signals::install();
        sweep_stale_token_files(&std::env::temp_dir());
        SystemRunner {
            gcp_token_bin,
            gcloud_bin,
            token_file: None,
        }
    }

    /// gcloud has no access-token property, only `auth/access_token_file`
    /// (CLOUDSDK_AUTH_ACCESS_TOKEN_FILE), so the token goes in a 0600 file
    /// that is removed when the runner is dropped.
    fn token_file(&mut self, token: &str) -> std::io::Result<PathBuf> {
        if let Some(p) = &self.token_file {
            return Ok(p.clone());
        }
        use std::io::Write;
        use std::os::unix::fs::OpenOptionsExt;
        let dir = std::env::temp_dir();
        let path = dir.join(format!(
            "{}{}{}",
            TOKEN_FILE_PREFIX,
            std::process::id(),
            TOKEN_FILE_SUFFIX
        ));
        let mut f = fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(&path)?;
        f.write_all(token.as_bytes())?;
        self.token_file = Some(path.clone());
        Ok(path)
    }
}

impl Drop for SystemRunner {
    fn drop(&mut self) {
        if let Some(p) = self.token_file.take() {
            let _ = fs::remove_file(p);
        }
    }
}

/// The last non-empty line of gcp-token's stdout.
pub fn last_line(stdout: &str) -> Option<String> {
    stdout
        .lines()
        .rev()
        .map(str::trim)
        .find(|l| !l.is_empty())
        .map(str::to_string)
}

impl Runner for SystemRunner {
    fn mint_token(&mut self, account: &str) -> Result<String, String> {
        let out = std::process::Command::new(&self.gcp_token_bin)
            .arg(account)
            .stderr(std::process::Stdio::inherit())
            .output()
            .map_err(|e| format!("cannot run {}: {}", self.gcp_token_bin.display(), e))?;
        if !out.status.success() {
            return Err(format!(
                "gcp-token exited {}",
                out.status.code().unwrap_or(1)
            ));
        }
        last_line(&String::from_utf8_lossy(&out.stdout))
            .ok_or_else(|| "gcp-token printed no token".into())
    }

    fn gcloud(&mut self, cmd: &GcloudCmd, token: &str) -> i32 {
        // Checked again here: nothing reaches exec without passing the guard.
        if let Err(e) = guard(cmd.argv()) {
            self.warn(&format!("gcp-cloudrun: {}", e));
            return 2;
        }
        let file = match self.token_file(token) {
            Ok(f) => f,
            Err(e) => {
                self.warn(&format!("gcp-cloudrun: cannot write the token file: {}", e));
                return 1;
            }
        };
        let status = std::process::Command::new(&self.gcloud_bin)
            .args(cmd.argv())
            .env("CLOUDSDK_AUTH_ACCESS_TOKEN_FILE", &file)
            .env("CLOUDSDK_CORE_DISABLE_PROMPTS", "1")
            .env_remove("CLOUDSDK_CORE_PROJECT")
            .status();
        match status {
            Ok(s) => s.code().unwrap_or(1),
            Err(e) => {
                self.warn(&format!(
                    "gcp-cloudrun: cannot run {}: {}",
                    self.gcloud_bin, e
                ));
                127
            }
        }
    }

    fn say(&mut self, line: &str) {
        println!("{}", line);
    }

    fn warn(&mut self, line: &str) {
        eprintln!("{}", line);
    }

    fn interrupted(&self) -> bool {
        signals::interrupted()
    }
}

#[cfg(test)]
mod tests;
