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

//! orchestrate in Rust — the delivery orchestrator's DECIDE stage (spec
//! docs/superpowers/specs/2026-08-19-delivery-orchestrator-design.md §4.2).
//!
//! It answers one question per push for every delivery unit in the repo,
//! "does this diff affect you?", and writes the answer to
//! delivery-manifest.json plus $GITHUB_OUTPUT. Three stages:
//!
//!  1. DISCOVER — `bazel query` the "delivery" tag, `bazel build` the units,
//!     read their metadata JSON out of bazel-bin.
//!  2. DECIDE — run tools/ci/deploy-affected.sh once per unit. That script
//!     is the decision engine and is deliberately NOT reimplemented here.
//!  3. EMIT — the manifest, the job outputs and a summary table.
//!
//! FAIL-OPEN: every uncertainty marks every unit affected with
//! computed_by="fail-open" and a reason, and the binary still exits 0. The
//! one exit 1 is an unwritable --out.
//!
//! This is a port of the Go original (`:orchestrate-go`, main.go, which
//! carries the full rationale for each rule). Its stdout, manifest bytes,
//! $GITHUB_OUTPUT lines and exit code match the Go binary's; the parity
//! test runs both side by side.

pub mod flags;
pub mod gostd;
pub mod json;
pub mod tabwriter;

use gostd::{quote, GoCmd};
use json::UnitMeta;
use serde::Serialize;
use std::collections::HashMap;
use std::ffi::OsString;
use std::fs;
use std::io::Write;
use std::os::unix::fs::OpenOptionsExt;
use std::process::Stdio;

pub const SCHEMA_VERSION: i64 = 1;
pub const COMPUTED_BY_GRAPH: &str = "graph";
pub const COMPUTED_BY_PATHS: &str = "paths";
pub const COMPUTED_BY_FAIL_OPEN: &str = "fail-open";
pub const DEFAULT_MANIFEST_NAME: &str = "delivery-manifest.json";
pub const DEPLOY_AFFECTED_REL: &str = "tools/ci/deploy-affected.sh";
pub const DELIVERY_QUERY: &str =
    r#"attr(tags, "\bdelivery\b", (//... except //apps/desktop/nexus-agent/macos/...))"#;
const UNIT_TARGET_SUFFIX: &str = ".delivery_unit";
const META_FILE_SUFFIX: &str = ".delivery.json";

/// One row of the manifest (spec §4.2, plus per-unit computed_by and base).
#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct ManifestUnit {
    pub name: String,
    pub affected: bool,
    pub computed_by: String,
    pub reason: String,
    pub environments: Option<Vec<String>>,
    pub kind: String,
    pub github_environment: String,
    pub run: String,
    pub base: String,
}

/// delivery-manifest.json.
#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct Manifest {
    pub schema: i64,
    pub commit: String,
    pub before: String,
    pub computed_by: String,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub reason: String,
    pub units: Vec<ManifestUnit>,
}

/// The orchestrator's environment. Values are kept as the OS gave them, so
/// bazel and git see exactly what the orchestrator was started with.
#[derive(Debug, Clone, Default)]
pub struct Env(pub HashMap<String, OsString>);

impl Env {
    pub fn from_process() -> Env {
        let mut m = HashMap::new();
        for (k, v) in std::env::vars_os() {
            m.insert(k.to_string_lossy().into_owned(), v);
        }
        Env(m)
    }

    pub fn from_pairs(pairs: &[(&str, &str)]) -> Env {
        Env(pairs
            .iter()
            .map(|(k, v)| (k.to_string(), OsString::from(v)))
            .collect())
    }

    /// cfg.env[k]: "" when absent.
    pub fn get(&self, k: &str) -> String {
        self.0
            .get(k)
            .map(|v| v.to_string_lossy().into_owned())
            .unwrap_or_default()
    }

    fn flat(&self) -> Vec<(OsString, OsString)> {
        self.0
            .iter()
            .map(|(k, v)| (OsString::from(k), v.clone()))
            .collect()
    }
}

/// Everything orchestrate() reads from the outside world.
pub struct Config<'a> {
    pub repo_root: String,
    pub script: String,
    pub bazel: String,
    pub out: String,
    pub env: Env,
    pub stdout: &'a mut dyn Write,
}

// ---------------------------------------------------------------------------
// discovery
// ---------------------------------------------------------------------------

fn placeholder(name: String) -> UnitMeta {
    UnitMeta {
        name,
        ..Default::default()
    }
}

/// The declared delivery units. An Err means "go fail-open"; the units
/// returned alongside it are still the best list there is.
pub fn discover(cfg: &Config) -> (Vec<UnitMeta>, Option<String>) {
    let out = match bazel_run(
        cfg,
        &[
            "query".into(),
            DELIVERY_QUERY.into(),
            "--output=label".into(),
        ],
    ) {
        Ok(o) => o,
        Err(e) => {
            return (
                Vec::new(),
                Some(format!("bazel query for delivery units failed: {}", e)),
            )
        }
    };
    let labels = non_empty_lines(&out);
    if labels.is_empty() {
        return (Vec::new(), None);
    }
    let placeholders: Vec<UnitMeta> = labels
        .iter()
        .map(|l| placeholder(unit_name_from_label(l)))
        .collect();

    let mut build = vec!["build".to_string()];
    build.extend(labels.iter().cloned());
    if let Err(e) = bazel_run(cfg, &build) {
        return (
            placeholders,
            Some(format!("bazel build of delivery metadata failed: {}", e)),
        );
    }
    let bin_dir = match bazel_run(cfg, &["info".into(), "bazel-bin".into()]) {
        Ok(o) => o.trim().to_string(),
        Err(e) => {
            return (
                placeholders,
                Some(format!("bazel info bazel-bin failed: {}", e)),
            )
        }
    };

    let mut units = Vec::with_capacity(labels.len());
    let mut first_err = None;
    for (i, l) in labels.iter().enumerate() {
        let err = match metadata_rel_path(l) {
            Err(e) => e,
            Ok(rel) => match gostd::read_file(&gostd::join(&[&bin_dir, &rel])) {
                Err(e) => e,
                Ok(raw) => match json::decode_unit_meta(&raw) {
                    Ok(m) if !m.name.is_empty() => {
                        units.push(m);
                        continue;
                    }
                    Ok(_) => "metadata has no \"name\"".to_string(),
                    Err(e) => e,
                },
            },
        };
        if first_err.is_none() {
            first_err = Some(format!("delivery metadata for {} unreadable: {}", l, err));
        }
        units.push(placeholders[i].clone());
    }
    (units, first_err)
}

/// Narrows the units to ORCHESTRATE_UNITS (space-separated; empty = all).
/// A named unit discovery did not find is kept, as a placeholder, and
/// reported: dropping it would read as "not affected" downstream.
pub fn select_units(units: Vec<UnitMeta>, names: &str) -> (Vec<UnitMeta>, Option<String>) {
    let wanted: Vec<&str> = names.split_whitespace().collect();
    if wanted.is_empty() {
        return (units, None);
    }
    let mut by_name: HashMap<&str, &UnitMeta> = HashMap::new();
    for u in &units {
        by_name.insert(u.name.as_str(), u);
    }
    let mut out = Vec::with_capacity(wanted.len());
    let mut missing = Vec::new();
    for n in &wanted {
        match by_name.get(n) {
            Some(u) => out.push((*u).clone()),
            None => {
                out.push(placeholder(n.to_string()));
                missing.push(*n);
            }
        }
    }
    if !missing.is_empty() {
        let e = format!(
            "ORCHESTRATE_UNITS names {}, which discovery did not find -- the workflow is stale against the delivery() declarations",
            missing.join(", ")
        );
        return (out, Some(e));
    }
    (out, None)
}

/// //pkg/sub:x.delivery_unit -> pkg/sub/x.delivery.json (relative to bazel-bin).
pub fn metadata_rel_path(label: &str) -> Result<String, String> {
    let l = label.strip_prefix("@@").unwrap_or(label);
    let l = l.strip_prefix('@').unwrap_or(l);
    let l = l.strip_prefix("//").unwrap_or(l);
    if l.is_empty() {
        return Err(format!("label {} is not a main-repo label", quote(label)));
    }
    let (pkg, target) = match l.split_once(':') {
        Some((p, t)) => (p.to_string(), t.to_string()),
        None => (l.to_string(), gostd::base(l)),
    };
    if target.is_empty() {
        return Err(format!("label {} has an empty target name", quote(label)));
    }
    let file = format!(
        "{}{}",
        target.strip_suffix(UNIT_TARGET_SUFFIX).unwrap_or(&target),
        META_FILE_SUFFIX
    );
    Ok(gostd::join(&[&pkg, &file]))
}

/// The delivery() name behind a unit's filegroup label.
pub fn unit_name_from_label(label: &str) -> String {
    let target = match label.split_once(':') {
        Some((_, t)) => t.to_string(),
        None => gostd::base(label),
    };
    target
        .strip_suffix(UNIT_TARGET_SUFFIX)
        .unwrap_or(&target)
        .to_string()
}

// ---------------------------------------------------------------------------
// decision
// ---------------------------------------------------------------------------

/// The human reason from the engine's "deploy-affected: affected=..." line
/// (the first one, as Go's (?m)^...$ regexp finds it).
fn engine_reason(combined: &str) -> Option<String> {
    for line in combined.split('\n') {
        let Some(rest) = line.strip_prefix("deploy-affected: affected=") else {
            continue;
        };
        let rest = match rest
            .strip_prefix("true (")
            .or_else(|| rest.strip_prefix("false ("))
        {
            Some(r) => r,
            None => continue,
        };
        if let Some(reason) = rest.strip_suffix(')') {
            return Some(reason.to_string());
        }
    }
    None
}

/// A private temp dir, removed on drop (os.MkdirTemp + defer RemoveAll).
struct TempDir(String);

impl TempDir {
    fn new(prefix: &str) -> std::io::Result<TempDir> {
        use std::os::unix::fs::DirBuilderExt;
        let base = std::env::temp_dir();
        let seed = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0) as u64
            ^ ((std::process::id() as u64) << 32);
        let mut x = seed | 1;
        for _ in 0..10000 {
            x ^= x << 13;
            x ^= x >> 7;
            x ^= x << 17;
            let p = base.join(format!("{}{}", prefix, x % 10_000_000_000));
            match fs::DirBuilder::new().mode(0o700).create(&p) {
                Ok(()) => return Ok(TempDir(p.to_string_lossy().into_owned())),
                Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => continue,
                Err(e) => return Err(e),
            }
        }
        Err(std::io::Error::from(std::io::ErrorKind::AlreadyExists))
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

pub struct Verdict {
    pub affected: bool,
    pub mode: &'static str,
    pub reason: String,
}

/// Runs the engine once for one unit. Graph mode when the unit declares
/// graph_targets or a build target; otherwise PATH-ONLY mode with
/// DEPLOY_TARGETS UNSET (not empty: the script tests for unset-or-empty and
/// an inherited value would switch modes).
pub fn decide(cfg: &mut Config, base: &str, u: &UnitMeta) -> Result<Verdict, (Verdict, String)> {
    let join = |v: &Option<Vec<String>>, sep: &str| v.as_deref().unwrap_or(&[]).join(sep);
    let mut extra: Vec<(&str, String)> = vec![
        ("BEFORE_REV", base.to_string()),
        ("FORCED_PUSH", cfg.env.get("FORCED_PUSH")),
        ("EXTRA_PATH_REGEX", join(&u.extra_paths, "|")),
        ("EXCLUDE_PATH_REGEX", join(&u.exclude_paths, "|")),
    ];
    let mut mode = COMPUTED_BY_PATHS;
    if u.graph_targets.as_ref().map_or(false, |g| !g.is_empty()) {
        mode = COMPUTED_BY_GRAPH;
        extra.push(("DEPLOY_TARGETS", join(&u.graph_targets, " ")));
    } else if !u.build.is_empty() {
        mode = COMPUTED_BY_GRAPH;
        extra.push((
            "DEPLOY_TARGETS",
            format!("{} {}", u.build, u.run).trim().to_string(),
        ));
    }
    let fail = |reason: String, e: String| {
        Err((
            Verdict {
                affected: true,
                mode,
                reason,
            },
            e,
        ))
    };

    let tmp = match TempDir::new("delivery-orchestrate-") {
        Ok(t) => t,
        Err(e) => {
            return fail(
                String::new(),
                format!(
                    "cannot create a temp dir for the engine's GITHUB_OUTPUT: {}",
                    gostd::path_error(
                        "mkdirtemp",
                        &std::env::temp_dir()
                            .join("delivery-orchestrate-*")
                            .to_string_lossy(),
                        &e
                    )
                ),
            )
        }
    };
    let out_path = gostd::join(&[&tmp.0, "github_output"]);
    if let Err(e) = write_file(&out_path, b"") {
        return fail(
            String::new(),
            format!("cannot seed the engine's GITHUB_OUTPUT: {}", e),
        );
    }
    extra.push(("GITHUB_OUTPUT", out_path.clone()));

    // The engine's combined stdout+stderr, in the order it wrote them: both
    // streams share one open file, as Go shares one pipe between them.
    let combined_path = gostd::join(&[&tmp.0, "combined"]);
    let (combined, run_err) = run_engine(cfg, &engine_env(&cfg.env, &extra), &combined_path);

    let _ = writeln!(
        cfg.stdout,
        "---- deploy-affected.sh: {} ({} mode) ----",
        u.name, mode
    );
    let trimmed = {
        let mut end = combined.len();
        while end > 0 && combined[end - 1] == b'\n' {
            end -= 1;
        }
        &combined[..end]
    };
    for line in trimmed.split(|&b| b == b'\n') {
        let _ = cfg.stdout.write_all(b"  ");
        let _ = cfg.stdout.write_all(line);
        let _ = cfg.stdout.write_all(b"\n");
    }

    let reason = engine_reason(&json::go_string(&combined)).unwrap_or_default();
    if let Some(e) = run_err {
        return fail(
            reason,
            format!(
                "deploy-affected.sh for unit {} exited non-zero: {}",
                quote(&u.name),
                e
            ),
        );
    }

    let raw = match gostd::read_file(&out_path) {
        Ok(r) => r,
        Err(e) => {
            return fail(
                reason,
                format!(
                    "cannot read the engine's GITHUB_OUTPUT for unit {}: {}",
                    quote(&u.name),
                    e
                ),
            )
        }
    };
    let mut verdict = String::new();
    for line in non_empty_lines(&json::go_string(&raw)) {
        if let Some(v) = line.strip_prefix("affected=") {
            verdict = v.trim().to_string();
        }
    }
    match verdict.as_str() {
        "true" => Ok(Verdict {
            affected: true,
            mode,
            reason,
        }),
        "false" => Ok(Verdict {
            affected: false,
            mode,
            reason,
        }),
        _ => fail(
            reason,
            format!(
                "deploy-affected.sh for unit {} emitted no affected= line",
                quote(&u.name)
            ),
        ),
    }
}

/// `bash <script>` in the repo root; returns the combined output and, when
/// it did not exit 0, Go's text for why.
fn run_engine(
    cfg: &Config,
    env: &[(OsString, OsString)],
    combined_path: &str,
) -> (Vec<u8>, Option<String>) {
    let mut gc = match GoCmd::new("bash", &[cfg.script.clone()], &cfg.repo_root, env) {
        Ok(c) => c,
        Err(e) => return (Vec::new(), Some(e)),
    };
    if let Err(e) = gc.check_dir() {
        return (Vec::new(), Some(e));
    }
    let file = match fs::OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(true)
        .open(combined_path)
    {
        Ok(f) => f,
        Err(e) => {
            return (
                Vec::new(),
                Some(gostd::path_error("open", combined_path, &e)),
            )
        }
    };
    let err_file = match file.try_clone() {
        Ok(f) => f,
        Err(e) => return (Vec::new(), Some(gostd::errno_text(&e))),
    };
    gc.cmd
        .stdout(Stdio::from(file))
        .stderr(Stdio::from(err_file));
    let status = match gc.cmd.status() {
        Ok(s) => s,
        Err(e) => return (Vec::new(), Some(gc.spawn_error(&e))),
    };
    let combined = fs::read(combined_path).unwrap_or_default();
    if status.success() {
        (combined, None)
    } else {
        (combined, Some(gostd::exit_status_string(&status)))
    }
}

// ---------------------------------------------------------------------------
// orchestration
// ---------------------------------------------------------------------------

/// The whole run; returns the exit code.
pub fn orchestrate(cfg: &mut Config) -> i32 {
    let mut m = Manifest {
        schema: SCHEMA_VERSION,
        commit: git_output(cfg, &["rev-parse", "HEAD"]),
        before: String::new(),
        computed_by: String::new(),
        reason: String::new(),
        units: Vec::new(),
    };

    // 1. The diff base. Anything untrustworthy fails the whole manifest open
    //    before the engine runs. BASE_REF is only a fallback for BEFORE_REV.
    let base = first_non_empty(&[&cfg.env.get("BEFORE_REV"), &cfg.env.get("BASE_REF")]);
    m.before = base.clone();

    // Optional per-unit bases (#1842); unparseable input is ignored.
    let mut unit_bases: HashMap<String, String> = HashMap::new();
    let raw_bases = cfg.env.get("UNIT_BASES_JSON");
    if !raw_bases.is_empty() {
        if let Some(pairs) = json::decode_string_map(raw_bases.as_bytes()) {
            unit_bases.extend(pairs);
        }
    }

    let mut fail_open = String::new();
    if cfg.env.get("FORCED_PUSH") == "true" {
        fail_open = "forced push -- no trustworthy diff base".to_string();
    } else if base.is_empty() {
        fail_open =
            "neither BEFORE_REV nor BASE_REF is set -- no diff base to compute against".to_string();
    } else if git_output(
        cfg,
        &[
            "rev-parse",
            "--verify",
            "--quiet",
            &format!("{}^{{commit}}", base),
        ],
    )
    .is_empty()
    {
        fail_open = format!("base {} does not resolve to a commit", quote(&base));
    }

    // 2. The universe, narrowed to the units this workflow delivers.
    let (units, err) = discover(cfg);
    if let (Some(e), true) = (err, fail_open.is_empty()) {
        fail_open = e;
    }
    let (units, err) = select_units(units, &cfg.env.get("ORCHESTRATE_UNITS"));
    if let (Some(e), true) = (err, fail_open.is_empty()) {
        fail_open = e;
    }

    // 3. The verdicts. One unit's engine failure fails the whole manifest.
    if fail_open.is_empty() {
        let mut graph_seen = false;
        for u in &units {
            let mut unit_base = base.clone();
            if let Some(b) = unit_bases.get(&u.name) {
                if !b.is_empty()
                    && !git_output(
                        cfg,
                        &[
                            "rev-parse",
                            "--verify",
                            "--quiet",
                            &format!("{}^{{commit}}", b),
                        ],
                    )
                    .is_empty()
                {
                    unit_base = b.clone();
                }
            }
            match decide(cfg, &unit_base, u) {
                Err((_, e)) => {
                    fail_open = e;
                    break;
                }
                Ok(v) => {
                    if v.mode == COMPUTED_BY_GRAPH {
                        graph_seen = true;
                    }
                    m.units.push(new_manifest_unit(
                        u, v.affected, v.mode, &v.reason, &unit_base,
                    ));
                }
            }
        }
        if fail_open.is_empty() {
            m.computed_by = if graph_seen {
                COMPUTED_BY_GRAPH
            } else {
                COMPUTED_BY_PATHS
            }
            .to_string();
        }
    }

    if !fail_open.is_empty() {
        m.computed_by = COMPUTED_BY_FAIL_OPEN.to_string();
        m.reason = fail_open.clone();
        m.units.clear();
        for u in &units {
            m.units.push(new_manifest_unit(
                u,
                true,
                COMPUTED_BY_FAIL_OPEN,
                &fail_open,
                &base,
            ));
        }
        let _ = writeln!(
            cfg.stdout,
            "::warning title=delivery-orchestrator-fail-open::delivery detection failed OPEN -- every unit marked affected ({})",
            fail_open
        );
    }

    if let Err(e) = write_manifest(cfg, &m) {
        let _ = writeln!(cfg.stdout, "::error title=delivery-orchestrator::{}", e);
        return 1;
    }
    if let Err(e) = write_github_outputs(cfg, &m) {
        let _ = writeln!(cfg.stdout, "::warning title=delivery-orchestrator::{}", e);
    }
    print_summary(cfg, &m);
    0
}

fn new_manifest_unit(
    u: &UnitMeta,
    affected: bool,
    mode: &str,
    reason: &str,
    base: &str,
) -> ManifestUnit {
    ManifestUnit {
        name: u.name.clone(),
        affected,
        computed_by: mode.to_string(),
        reason: reason.to_string(),
        environments: u.environments.clone(),
        kind: u.kind.clone(),
        // The DECLARED pattern, "{env}" intact.
        github_environment: u.github_environment.clone(),
        run: u.run.clone(),
        base: base.to_string(),
    }
}

// ---------------------------------------------------------------------------
// emission
// ---------------------------------------------------------------------------

/// os.WriteFile(path, data, 0o644) with Go's error text.
fn write_file(path: &str, data: &[u8]) -> Result<(), String> {
    let mut f = fs::OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .mode(0o644)
        .open(path)
        .map_err(|e| gostd::path_error("open", path, &e))?;
    f.write_all(data)
        .map_err(|e| gostd::path_error("write", path, &e))
}

fn write_manifest(cfg: &mut Config, m: &Manifest) -> Result<(), String> {
    let mut raw = json::marshal_indent(m);
    raw.push(b'\n');
    write_file(&cfg.out, &raw)
        .map_err(|e| format!("cannot write the manifest to {}: {}", cfg.out, e))?;
    let _ = writeln!(cfg.stdout, "delivery-orchestrate: wrote {}", cfg.out);
    Ok(())
}

/// Appends `manifest=<compact json>` and one `affected_<unit>=` per unit.
fn write_github_outputs(cfg: &Config, m: &Manifest) -> Result<(), String> {
    let p = cfg.env.get("GITHUB_OUTPUT");
    if p.is_empty() {
        return Ok(());
    }
    let mut b = b"manifest=".to_vec();
    b.extend(json::marshal(m));
    b.push(b'\n');
    for u in &m.units {
        b.extend(format!("affected_{}={}\n", output_var_name(&u.name), u.affected).into_bytes());
    }
    let mut f = fs::OpenOptions::new()
        .append(true)
        .create(true)
        .mode(0o644)
        .open(&p)
        .map_err(|e| {
            format!(
                "cannot open GITHUB_OUTPUT {}: {}",
                p,
                gostd::path_error("open", &p, &e)
            )
        })?;
    f.write_all(&b).map_err(|e| {
        format!(
            "cannot append to GITHUB_OUTPUT {}: {}",
            p,
            gostd::path_error("write", &p, &e)
        )
    })
}

/// A unit name as a GHA output key: everything outside [A-Za-z0-9_] -> "_".
/// A CROSS-BINARY CONTRACT with //tools/delivery/gen, which renders the
/// `if:` that reads these keys (see main.go's outputVarName).
pub fn output_var_name(name: &str) -> String {
    name.chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() || c == '_' {
                c
            } else {
                '_'
            }
        })
        .collect()
}

fn print_summary(cfg: &mut Config, m: &Manifest) {
    let _ = write!(
        cfg.stdout,
        "\ndelivery-orchestrate: {} unit(s), computed_by={}\n",
        m.units.len(),
        m.computed_by
    );
    if !m.reason.is_empty() {
        let _ = writeln!(cfg.stdout, "  reason: {}", m.reason);
    }
    let mut w = tabwriter::TabWriter::new(2);
    w.write(b"  UNIT\tAFFECTED\tBY\tWHY\n");
    for u in &m.units {
        w.write(
            format!(
                "  {}\t{}\t{}\t{}\n",
                u.name, u.affected, u.computed_by, u.reason
            )
            .as_bytes(),
        );
    }
    let _ = cfg.stdout.write_all(&w.finish());
}

// ---------------------------------------------------------------------------
// process plumbing
// ---------------------------------------------------------------------------

/// What the engine may inherit. An allowlist, so DEPLOY_TARGETS can be
/// guaranteed absent in path-only mode.
pub const ENGINE_ENV_ALLOWLIST: [&str; 12] = [
    "PATH",
    "HOME",
    "USER",
    "TMPDIR",
    "LANG",
    "LC_ALL",
    "BUILDBUDDY_API_KEY",
    "TD_BIN",
    "GITHUB_STEP_SUMMARY",
    "GIT_CONFIG_GLOBAL",
    "GIT_CONFIG_SYSTEM",
    "GIT_CONFIG_NOSYSTEM",
];

pub fn engine_env(env: &Env, extra: &[(&str, String)]) -> Vec<(OsString, OsString)> {
    let mut out = Vec::with_capacity(ENGINE_ENV_ALLOWLIST.len() + extra.len());
    for k in ENGINE_ENV_ALLOWLIST {
        if let Some(v) = env.0.get(k) {
            out.push((OsString::from(k), v.clone()));
        }
    }
    for (k, v) in extra {
        out.push((OsString::from(k), OsString::from(v)));
    }
    out
}

/// bazel in the workspace, with the orchestrator's full environment.
fn bazel_run(cfg: &Config, args: &[String]) -> Result<String, String> {
    let describe = |err: &str, stderr: &[u8]| {
        format!(
            "{} {}: {}: {}",
            gostd::base(&cfg.bazel),
            args.join(" "),
            err,
            one_line(&json::go_string(stderr))
        )
    };
    let mut gc = GoCmd::new(&cfg.bazel, args, &cfg.repo_root, &cfg.env.flat())
        .map_err(|e| describe(&e, b""))?;
    gc.check_dir().map_err(|e| describe(&e, b""))?;
    let out = gc
        .cmd
        .output()
        .map_err(|e| describe(&gc.spawn_error(&e), b""))?;
    if !out.status.success() {
        return Err(describe(
            &gostd::exit_status_string(&out.status),
            &out.stderr,
        ));
    }
    Ok(json::go_string(&out.stdout))
}

/// git in the workspace: trimmed stdout, or "" on any failure.
fn git_output(cfg: &Config, args: &[&str]) -> String {
    let args: Vec<String> = args.iter().map(|s| s.to_string()).collect();
    let Ok(mut gc) = GoCmd::new("git", &args, &cfg.repo_root, &cfg.env.flat()) else {
        return String::new();
    };
    if gc.check_dir().is_err() {
        return String::new();
    }
    match gc.cmd.stderr(Stdio::piped()).output() {
        Ok(o) if o.status.success() => json::go_string(&o.stdout).trim().to_string(),
        _ => String::new(),
    }
}

pub fn non_empty_lines(s: &str) -> Vec<String> {
    s.split('\n')
        .map(str::trim)
        .filter(|l| !l.is_empty())
        .map(String::from)
        .collect()
}

fn one_line(s: &str) -> String {
    s.split_whitespace().collect::<Vec<_>>().join(" ")
}

pub fn first_non_empty(vals: &[&str]) -> String {
    vals.iter()
        .map(|v| v.trim())
        .find(|v| !v.is_empty())
        .unwrap_or("")
        .to_string()
}

#[cfg(test)]
mod tests;
