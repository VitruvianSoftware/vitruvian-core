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

//! Set up, on each registry, the trust that lets the workflow publish:
//! setup_publishers.py, ported; its docstring says why. crates.io gets the
//! trusted publisher that is missing, npm is handed to
//! //tools/npm-trusted-publisher:setup, and PyPI, which has no API for it,
//! gets the exact values to enter printed. Every value comes from the
//! inventory, never typed.
//!
//! THE CARGO TOKEN is read when it is needed and only then, sent to
//! https://crates.io in the Authorization header and to nothing else (on
//! curl's stdin, never its command line), and never printed or written.
//!
//! Exit: 0 done · 1 a registry refused something · 2 setup error

use std::fs;
use std::io::Write;
use std::os::unix::fs::OpenOptionsExt;

use crate::check::Fetch;
use crate::http::{self, Answer, RegistryError, Request, USER_AGENT};
use crate::inventory::{self, Package, REGISTRIES};
use crate::json::{self, get_or, or_empty, Crash, Value};
use crate::py;
use crate::toml;

pub const CONFIGS: &str = "https://crates.io/api/v1/trusted_publishing/github_configs";
pub const NPM_SETUP: &str = "tools/npm-trusted-publisher/setup.sh";
pub const RUNBOOK: &str = "docs/engineering/registry-trust.md";

#[derive(Debug, Clone, PartialEq)]
pub struct SetupError(pub String);

impl std::fmt::Display for SetupError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}

/// What stops setup: a SetupError or a registry that could not be read
/// (exit 2), or what the script would have crashed on (exit 1).
#[derive(Debug, Clone, PartialEq)]
pub enum Fail {
    Setup(SetupError),
    Crash(Crash),
}

impl From<SetupError> for Fail {
    fn from(error: SetupError) -> Fail {
        Fail::Setup(error)
    }
}

impl From<RegistryError> for Fail {
    fn from(error: RegistryError) -> Fail {
        Fail::Setup(SetupError(error.0))
    }
}

impl From<Crash> for Fail {
    fn from(crash: Crash) -> Fail {
        Fail::Crash(crash)
    }
}

pub type Env = Vec<(String, String)>;
/// (method, url, token, json body) -> (status, body)
pub type Send<'a> = dyn FnMut(&str, &str, &str, Option<&Value>) -> Result<Answer, SetupError> + 'a;
/// (command, environment) -> did it fail
pub type RunNpm<'a> = dyn FnMut(&[String], &Env) -> Result<bool, SetupError> + 'a;

fn env_get<'e>(env: &'e Env, key: &str) -> Option<&'e str> {
    env.iter()
        .rev()
        .find(|(k, _)| k == key)
        .map(|(_, v)| v.as_str())
}

// --- crates.io ------------------------------------------------------------------

/// The token `cargo` would use, or a SetupError that says how to get one.
pub fn cargo_token(env: &Env) -> Result<String, Fail> {
    if let Some(token) = env_get(env, "CARGO_REGISTRY_TOKEN").filter(|t| !t.is_empty()) {
        return Ok(token.to_string());
    }
    let home = match env_get(env, "CARGO_HOME").filter(|h| !h.is_empty()) {
        Some(home) => home.to_string(),
        None => py::join(env_get(env, "HOME").unwrap_or(""), ".cargo"),
    };
    for name in ["credentials.toml", "credentials"] {
        let Ok(bytes) = fs::read(py::join(&home, name)) else {
            continue;
        };
        if let Some(message) = py::utf8_error(&bytes) {
            return Err(Crash::new("UnicodeDecodeError", message).into());
        }
        // Not the parser's message: it can quote the file.
        let Ok(data) = toml::loads(std::str::from_utf8(&bytes).unwrap()) else {
            return Err(SetupError(format!("cargo's {name} cannot be read as TOML")).into());
        };
        let token = get_or(&data, "registry", json::dict::<String>([]))?
            .pget("token")?
            .cloned();
        if let Some(token) = token.filter(Value::truthy) {
            return Ok(token.py_str());
        }
    }
    Err(SetupError(
        "no crates.io token: run `cargo login` (a token with the trusted-publishing scope), or set CARGO_REGISTRY_TOKEN, then re-run"
            .into(),
    )
    .into())
}

/// The one request that carries the token: https, to crates.io, nowhere else.
pub fn crates_request(
    method: &str,
    url: &str,
    token: &str,
    body: Option<&Value>,
) -> Result<Request, String> {
    let (scheme, host) = py::split_url(url);
    if scheme != "https" || host.as_deref() != Some("crates.io") {
        return Err("the cargo token goes to https://crates.io and nowhere else".into());
    }
    let mut headers = vec![
        ("Authorization".to_string(), token.to_string()),
        ("User-Agent".to_string(), USER_AGENT.to_string()),
        ("Accept".to_string(), "application/json".to_string()),
    ];
    let data = body.map(|b| {
        headers.push(("Content-Type".into(), "application/json".into()));
        json::dumps(b).into_bytes()
    });
    Ok(Request {
        method: method.into(),
        url: url.into(),
        headers,
        body: data,
        follow: false,
    })
}

/// The live send, by curl. No answer at all is a setup error.
pub fn crates_send(
    method: &str,
    url: &str,
    token: &str,
    body: Option<&Value>,
) -> Result<Answer, SetupError> {
    let request = crates_request(method, url, token, body).map_err(SetupError)?;
    http::curl_open(&request).map_err(|e| SetupError(format!("{url} could not be reached: {e}")))
}

/// What crates.io said went wrong: its own words, and nothing we sent.
fn detail(body: &[u8]) -> Result<String, Crash> {
    let errors = match json::loads_bytes(body) {
        Ok(value @ Value::Dict(_)) => get_or(&value, "errors", Value::List(Vec::new()))?,
        _ => return Ok("no reason given".into()),
    };
    let mut said = Vec::new();
    for error in errors.iterate()? {
        said.push(
            error
                .pget("detail")?
                .map(Value::py_str)
                .unwrap_or_else(|| "None".into()),
        );
    }
    let joined = said.join("; ");
    Ok(if joined.is_empty() {
        "no reason given".into()
    } else {
        joined
    })
}

fn wanted(package: &Package) -> Value {
    json::dict([
        ("crate", json::s(&package.name)),
        ("repository_owner", json::s(&package.owner)),
        ("repository_name", json::s(&package.repo)),
        ("workflow_filename", json::s(&package.workflow)),
        (
            "environment",
            if package.environment.is_empty() {
                Value::Null
            } else {
                json::s(&package.environment)
            },
        ),
    ])
}

/// `_same(config, wanted)`, in its order, stopping where it stops.
fn same(config: &Value, package: &Package) -> Result<bool, Crash> {
    let lower = |k: &str| -> Result<String, Crash> {
        let value = match config.pget(k)? {
            Some(v) if v.truthy() => v.clone(),
            _ => json::s(""),
        };
        Ok(value.str_for("lower")?.to_lowercase())
    };
    if lower("repository_owner")? != package.owner.to_lowercase() {
        return Ok(false);
    }
    if lower("repository_name")? != package.repo.to_lowercase() {
        return Ok(false);
    }
    if config.pget("workflow_filename")? != Some(&json::s(&package.workflow)) {
        return Ok(false);
    }
    let environment = match config.pget("environment")? {
        Some(v) if v.truthy() => v.clone(),
        _ => Value::Null,
    };
    let want = if package.environment.is_empty() {
        Value::Null
    } else {
        json::s(&package.environment)
    };
    Ok(environment == want)
}

enum Listing {
    /// Said for this crate, and the next one is tried.
    Failed(String),
    Fatal(Fail),
}

impl From<Crash> for Listing {
    fn from(crash: Crash) -> Listing {
        Listing::Fatal(Fail::Crash(crash))
    }
}

fn existing(package: &Package, token: &str, send: &mut Send) -> Result<Vec<Value>, Listing> {
    let mut configs = Vec::new();
    let mut page = json::s(&format!("?crate={}", py::quote(&package.name, "/")));
    while page.truthy() {
        let Value::Str(next) = &page else {
            let message = format!(
                "can only concatenate str (not \"{}\") to str",
                page.type_name()
            );
            return Err(Crash::new("TypeError", message).into());
        };
        let url = format!("{CONFIGS}{next}");
        let (status, body) =
            send("GET", &url, token, None).map_err(|e| Listing::Fatal(e.into()))?;
        if status != 200 {
            return Err(Listing::Failed(format!(
                "HTTP {status} listing its trusted publishers: {}",
                detail(&body)?
            )));
        }
        let data = json::loads_bytes(&body).map_err(|e| Listing::from(e.crash()))?;
        configs.extend(get_or(&data, "github_configs", Value::List(Vec::new()))?.iterate()?);
        page = or_empty(data.pget("meta")?)
            .pget("next_page")?
            .cloned()
            .unwrap_or(Value::Null);
    }
    Ok(configs)
}

fn target(package: &Package) -> String {
    let environment = if package.environment.is_empty() {
        String::new()
    } else {
        format!(" environment {}", package.environment)
    };
    format!("{} {}{environment}", package.repository(), package.workflow)
}

#[allow(clippy::too_many_arguments)]
pub fn setup_crates(
    packages: &[&Package],
    dry_run: bool,
    env: &Env,
    fetch: &mut Fetch,
    send: &mut Send,
    out: &mut dyn Write,
    err: &mut dyn Write,
) -> Result<i32, Fail> {
    let (mut configured, mut already, mut failed, mut unpublished) = (0, 0, 0, 0);
    let _ = writeln!(out, "crates.io:");
    let mut token: Option<String> = None;
    for package in packages {
        let (status, _) = fetch(&format!("https://crates.io/api/v1/crates/{}", package.name))?;
        if status == 404 {
            let _ = writeln!(
                out,
                "  -- {} is not on crates.io yet; publish it once ({RUNBOOK}), then re-run",
                package.name
            );
            unpublished += 1;
            continue;
        }
        if status != 200 {
            return Err(SetupError(format!(
                "crates.io answered HTTP {status} for {}; refusing to guess whether it is published",
                package.name
            ))
            .into());
        }
        if dry_run {
            let _ = writeln!(
                out,
                "  DRY_RUN {} -> {} (created only if crates.io does not list it already)",
                package.name,
                target(package)
            );
            configured += 1;
            continue;
        }
        if token.is_none() {
            token = Some(cargo_token(env)?);
        }
        let token = token.as_deref().unwrap();
        let configs = match existing(package, token, send) {
            Ok(configs) => configs,
            Err(Listing::Failed(error)) => {
                let _ = writeln!(err, "  ✗ {} -- {error}", package.name);
                failed += 1;
                continue;
            }
            Err(Listing::Fatal(error)) => return Err(error),
        };
        let mut there = false;
        for config in &configs {
            if same(config, package)? {
                there = true;
                break;
            }
        }
        if there {
            let _ = writeln!(out, "  ok {} (already configured)", package.name);
            already += 1;
            continue;
        }
        let shown = |c: &Value, k: &str| -> Result<String, Crash> {
            Ok(c.pget(k)?
                .map(Value::py_str)
                .unwrap_or_else(|| "None".into()))
        };
        for config in &configs {
            let _ = writeln!(
                out,
                "  note: {} also trusts {}/{} {}; left as it is",
                package.name,
                shown(config, "repository_owner")?,
                shown(config, "repository_name")?,
                shown(config, "workflow_filename")?
            );
        }
        let body = json::dict([("github_config", wanted(package))]);
        let (status, answer) = send("POST", CONFIGS, token, Some(&body))?;
        if status == 200 {
            let _ = writeln!(out, "  + {} -> {}", package.name, target(package));
            configured += 1;
        } else {
            let _ = writeln!(
                err,
                "  ✗ {} -- HTTP {status}: {}",
                package.name,
                detail(&answer)?
            );
            failed += 1;
        }
    }
    let _ = writeln!(
        out,
        "  {configured} {}, {already} already set, {failed} failed, {unpublished} not yet on the registry.",
        if dry_run { "to configure" } else { "configured" }
    );
    Ok(if failed > 0 { 1 } else { 0 })
}

// --- PyPI -----------------------------------------------------------------------

pub fn setup_pypi(
    packages: &[&Package],
    fetch: &mut Fetch,
    out: &mut dyn Write,
) -> Result<i32, Fail> {
    let _ = writeln!(out, "PyPI:");
    let _ = writeln!(
        out,
        "  PyPI has no API for trusted publishers. Enter these by hand, once a\n  project; nothing here can tell whether they are entered already."
    );
    for package in packages {
        let (status, _) = fetch(&format!("https://pypi.org/pypi/{}/json", package.name))?;
        if status != 200 && status != 404 {
            return Err(SetupError(format!(
                "PyPI answered HTTP {status} for {}; refusing to guess whether it is published",
                package.name
            ))
            .into());
        }
        if status == 200 {
            let page = format!(
                "https://pypi.org/manage/project/{}/settings/publishing/",
                package.name
            );
            let _ = writeln!(
                out,
                "  {} (on PyPI): add a GitHub publisher at\n      {page}",
                package.name
            );
        } else {
            let _ = writeln!(
                out,
                "  {} is not on PyPI yet: add a pending GitHub publisher at\n      https://pypi.org/manage/account/publishing/\n      PyPI Project Name: {}",
                package.name, package.name
            );
        }
        let environment = if package.environment.is_empty() {
            "(leave empty)"
        } else {
            &package.environment
        };
        let _ = writeln!(
            out,
            "      Owner: {}\n      Repository name: {}\n      Workflow name: {}\n      Environment name: {environment}",
            package.owner, package.repo, package.workflow
        );
    }
    let _ = writeln!(out, "  {} to enter by hand.", packages.len());
    Ok(0)
}

// --- npm ------------------------------------------------------------------------

/// `os.get_exec_path(env)` then the first `bash` on it, as subprocess does.
fn which(program: &str, env: &Env) -> String {
    let path = env_get(env, "PATH")
        .map(str::to_string)
        .unwrap_or_else(|| "/bin:/usr/bin".into());
    for dir in path.split(':') {
        let candidate = py::join(if dir.is_empty() { "." } else { dir }, program);
        if fs::metadata(&candidate)
            .map(|m| m.is_file())
            .unwrap_or(false)
        {
            return candidate;
        }
    }
    program.to_string()
}

/// `subprocess.call(command, env=env)`: true when it failed.
pub fn run_npm_setup(command: &[String], env: &Env) -> Result<bool, SetupError> {
    let program = which(&command[0], env);
    let status = std::process::Command::new(program)
        .args(&command[1..])
        .env_clear()
        .envs(env.iter().cloned())
        .status()
        .map_err(|e| SetupError(format!("{}: {}", command[0], e)))?;
    Ok(!status.success())
}

/// `tempfile.mkstemp(prefix=..., suffix=".tsv")`: a new file only this
/// user can read.
fn temp_file() -> Result<(String, fs::File), SetupError> {
    let dir = std::env::temp_dir();
    let seed = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    for attempt in 0..100u128 {
        let tag = (seed ^ (std::process::id() as u128) << 32).wrapping_add(attempt * 0x9e37_79b9)
            % 36u128.pow(8);
        let name = format!("registry-trust-npm-{}.tsv", base36(tag));
        let path = dir.join(name);
        match fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(&path)
        {
            Ok(file) => return Ok((path.to_string_lossy().into_owned(), file)),
            Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => continue,
            Err(e) => return Err(SetupError(format!("cannot make a temporary file: {e}"))),
        }
    }
    Err(SetupError("cannot make a temporary file".into()))
}

fn base36(mut n: u128) -> String {
    let digits = b"abcdefghijklmnopqrstuvwxyz0123456789";
    let mut out = Vec::new();
    for _ in 0..8 {
        out.push(digits[(n % 36) as usize]);
        n /= 36;
    }
    String::from_utf8(out).unwrap()
}

#[allow(clippy::too_many_arguments)]
pub fn setup_npm(
    packages: &[&Package],
    dry_run: bool,
    root: &str,
    env: &Env,
    fetch: &mut Fetch,
    run_npm: &mut RunNpm,
    out: &mut dyn Write,
) -> Result<i32, Fail> {
    let _ = writeln!(out, "npm:");
    if dry_run {
        let mut unpublished = 0;
        for package in packages {
            let (status, _) = fetch(&format!(
                "https://registry.npmjs.org/{}",
                py::quote(&package.name, "@")
            ))?;
            if status == 404 {
                let _ = writeln!(
                    out,
                    "  -- {} is not on npm yet; publish it once ({RUNBOOK}), then re-run",
                    package.name
                );
                unpublished += 1;
            } else if status == 200 {
                let _ = writeln!(out, "  DRY_RUN {} -> {}", package.name, target(package));
            } else {
                return Err(SetupError(format!(
                    "npm answered HTTP {status} for {}; refusing to guess whether it is published",
                    package.name
                ))
                .into());
            }
        }
        let _ = writeln!(
            out,
            "  {} to hand to //tools/npm-trusted-publisher:setup (it skips what is set already), {unpublished} not yet on the registry.",
            packages.len() - unpublished
        );
        return Ok(0);
    }
    let (listed, mut file) = temp_file()?;
    let result = (|| -> Result<i32, Fail> {
        let mut sorted: Vec<&&Package> = packages.iter().collect();
        sorted.sort_by(|a, b| a.file.cmp(&b.file));
        for package in sorted {
            writeln!(
                file,
                "{}\t{}\t{}",
                package.file,
                package.repository(),
                package.workflow
            )
            .map_err(|e| SetupError(format!("cannot write {listed}: {e}")))?;
        }
        drop(file);
        let _ = out.flush();
        let mut child: Env = env
            .iter()
            .filter(|(k, _)| k != "NPM_TP_PACKAGES" && k != "BUILD_WORKSPACE_DIRECTORY")
            .cloned()
            .collect();
        child.push(("NPM_TP_PACKAGES".into(), listed.clone()));
        child.push(("BUILD_WORKSPACE_DIRECTORY".into(), root.into()));
        let failed = run_npm(&["bash".to_string(), py::join(root, NPM_SETUP)], &child)?;
        Ok(if failed { 1 } else { 0 })
    })();
    let _ = fs::remove_file(&listed);
    result
}

// --- all of it ------------------------------------------------------------------

#[allow(clippy::too_many_arguments)]
pub fn main(
    argv: &[String],
    root: &str,
    env: &Env,
    fetch: &mut Fetch,
    send: &mut Send,
    run_npm: &mut RunNpm,
    out: &mut dyn Write,
    err: &mut dyn Write,
) -> i32 {
    let mut dry_run = false;
    let mut only: Option<String> = None;
    let mut args = argv.iter().peekable();
    while let Some(flag) = args.next() {
        if flag == "--dry-run" {
            dry_run = true;
        } else if flag == "--only"
            && args
                .peek()
                .is_some_and(|a| REGISTRIES.contains(&a.as_str()))
        {
            only = args.next().cloned();
        } else {
            let _ = writeln!(err, "registry-trust: unknown flag: {flag}");
            let _ = writeln!(err, "  usage: setup [--dry-run] [--only npm|pypi|crates]");
            return 2;
        }
    }
    let found = match inventory::load(root) {
        Ok(found) => found,
        Err(crash) => {
            let _ = write!(err, "{}", crash.traceback());
            return 1;
        }
    };
    if !found.problems.is_empty() || found.packages.is_empty() {
        let problems = if found.problems.is_empty() {
            vec!["the inventory is empty".to_string()]
        } else {
            found.problems
        };
        for problem in problems {
            let _ = writeln!(err, "registry-trust: {problem}");
        }
        return 2;
    }
    let mine = |registry: &str| -> Vec<&Package> {
        if only.as_deref().is_some_and(|o| o != registry) {
            return Vec::new();
        }
        found
            .packages
            .iter()
            .filter(|p| p.registry == registry)
            .collect()
    };
    let mut code = 0;
    let mut steps = || -> Result<(), Fail> {
        let npm = mine("npm");
        if !npm.is_empty() {
            code |= setup_npm(&npm, dry_run, root, env, fetch, run_npm, out)?;
        }
        let crates = mine("crates");
        if !crates.is_empty() {
            code |= setup_crates(&crates, dry_run, env, fetch, send, out, err)?;
        }
        let pypi = mine("pypi");
        if !pypi.is_empty() {
            code |= setup_pypi(&pypi, fetch, out)?;
        }
        Ok(())
    };
    match steps() {
        Ok(()) => {}
        Err(Fail::Setup(error)) => {
            let _ = writeln!(err, "registry-trust: {error}");
            return 2;
        }
        Err(Fail::Crash(crash)) => {
            let _ = write!(err, "{}", crash.traceback());
            return 1;
        }
    }
    if code != 0 {
        let _ = writeln!(
            err,
            "registry-trust: something failed. Fix it and re-run; what is set already is skipped, so this is safe to repeat."
        );
    } else if !dry_run {
        let _ = writeln!(out, "  Verify with: bazel run //tools/registry-trust:check");
    }
    code
}

#[cfg(test)]
mod tests {
    use super::*;

    const TOKEN: &str = "cio-test-token-that-must-never-be-shown";

    fn kit() -> Package {
        Package {
            registry: "crates".into(),
            name: "example-kit".into(),
            version: "1.1.0".into(),
            file: "packages/sdk/kits/rs/Cargo.toml".into(),
            path: "packages/sdk".into(),
            config: "packages/sdk/release-please-config.json".into(),
            owner: "Example".into(),
            repo: "sdk-mirror".into(),
            workflow: "release.yml".into(),
            job: "crates-publish".into(),
            environment: "crates-io".into(),
            name_value: json::s("example-kit"),
            version_value: json::s("1.1.0"),
        }
    }

    #[test]
    fn a_token_goes_to_crates_io_and_nowhere_else() {
        let request = crates_request("GET", &format!("{CONFIGS}?crate=x"), TOKEN, None).unwrap();
        assert_eq!(request.header("Authorization"), Some(TOKEN));
        assert!(request
            .header("User-agent")
            .unwrap()
            .contains("registry-trust"));
        assert!(
            !request.follow,
            "a redirect could carry the token elsewhere"
        );
        assert!(
            crates_request("GET", "https://crates.io.example.com/api/v1/x", TOKEN, None).is_err()
        );
        assert!(crates_request("GET", "http://crates.io/api/v1/x", TOKEN, None).is_err());
    }

    #[test]
    fn the_token_is_read_from_the_environment_then_cargo_s_files() {
        let dir = std::env::temp_dir().join(format!("rt-token-{}", std::process::id()));
        fs::create_dir_all(dir.join(".cargo")).unwrap();
        let home = dir.to_string_lossy().into_owned();
        let env = |pairs: &[(&str, &str)]| -> Env {
            pairs
                .iter()
                .map(|(k, v)| (k.to_string(), v.to_string()))
                .collect()
        };
        assert_eq!(
            cargo_token(&env(&[("CARGO_REGISTRY_TOKEN", TOKEN)])).unwrap(),
            TOKEN
        );
        let message = |r: Result<String, Fail>| match r.unwrap_err() {
            Fail::Setup(e) => e.0,
            Fail::Crash(c) => c.0,
        };
        assert!(message(cargo_token(&env(&[("HOME", &home)]))).contains("cargo login"));
        fs::write(
            dir.join(".cargo/credentials.toml"),
            format!("[registry]\ntoken = \"{TOKEN}\"\n"),
        )
        .unwrap();
        assert_eq!(cargo_token(&env(&[("HOME", &home)])).unwrap(), TOKEN);
        fs::write(
            dir.join(".cargo/credentials.toml"),
            format!("[registry]\ntoken = \"{TOKEN}\n"),
        )
        .unwrap();
        let error = message(cargo_token(&env(&[("HOME", &home)])));
        assert_eq!(error, "cargo's credentials.toml cannot be read as TOML");
        assert!(!error.contains(TOKEN));
        let elsewhere = dir.join("elsewhere");
        fs::create_dir_all(&elsewhere).unwrap();
        fs::write(
            elsewhere.join("credentials"),
            format!("[registry]\ntoken = \"{TOKEN}\"\n"),
        )
        .unwrap();
        let moved = env(&[
            ("HOME", &home),
            ("CARGO_HOME", &elsewhere.to_string_lossy()),
        ]);
        assert_eq!(cargo_token(&moved).unwrap(), TOKEN);
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn a_config_counts_as_there_only_when_every_value_matches() {
        let wanted = wanted(&kit());
        let mut config = wanted.clone();
        if let Value::Dict(d) = &mut config {
            d.insert("repository_owner".into(), json::s("example"));
            d.insert("id".into(), Value::Int("7".into()));
        }
        assert!(same(&config, &kit()).unwrap());
        for (key, value) in [
            ("workflow_filename", json::s("other.yml")),
            ("environment", Value::Null),
        ] {
            let mut other = config.clone();
            if let Value::Dict(d) = &mut other {
                d.insert(key.into(), value);
            }
            assert!(!same(&other, &kit()).unwrap(), "{key}");
        }
    }

    #[test]
    fn crates_io_s_reason_is_its_own_words() {
        assert_eq!(
            detail(br#"{"errors": [{"detail": "a"}, {"detail": "b"}]}"#).unwrap(),
            "a; b"
        );
        assert_eq!(detail(b"not json").unwrap(), "no reason given");
        assert_eq!(detail(br#"{"errors": []}"#).unwrap(), "no reason given");
        assert_eq!(
            detail(br#"{"errors": 5}"#).unwrap_err().0,
            "TypeError: 'int' object is not iterable"
        );
    }

    #[test]
    fn a_missing_config_is_created_and_the_token_is_never_shown() {
        let mut sent: Vec<(String, String, String, Option<Value>)> = Vec::new();
        let mut out = Vec::new();
        let mut err = Vec::new();
        let env: Env = vec![("CARGO_REGISTRY_TOKEN".into(), TOKEN.into())];
        let code = setup_crates(
            &[&kit()],
            false,
            &env,
            &mut |_url: &str| Ok((200, b"{}".to_vec())),
            &mut |m: &str, u: &str, t: &str, b: Option<&Value>| {
                sent.push((m.into(), u.into(), t.into(), b.cloned()));
                if m == "GET" {
                    Ok((
                        200,
                        br#"{"github_configs": [], "meta": {"next_page": null}}"#.to_vec(),
                    ))
                } else {
                    Ok((200, b"{}".to_vec()))
                }
            },
            &mut out,
            &mut err,
        )
        .unwrap();
        let out = String::from_utf8(out).unwrap();
        assert_eq!(code, 0);
        assert_eq!(sent.len(), 2);
        assert_eq!(sent[1].1, CONFIGS);
        assert_eq!(sent[1].2, TOKEN);
        assert_eq!(
            json::dumps(sent[1].3.as_ref().unwrap()),
            r#"{"github_config": {"crate": "example-kit", "repository_owner": "Example", "repository_name": "sdk-mirror", "workflow_filename": "release.yml", "environment": "crates-io"}}"#
        );
        assert!(
            out.contains("+ example-kit -> Example/sdk-mirror release.yml environment crates-io")
        );
        assert!(!out.contains(TOKEN) && !String::from_utf8(err).unwrap().contains(TOKEN));
    }
}
