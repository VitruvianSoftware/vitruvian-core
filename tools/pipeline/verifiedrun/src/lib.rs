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

//! //tools/pipeline/verifiedrun in Rust: runs the tests a pull request would
//! run in CI, on the same remote build machines CI uses, and records a pass
//! against the exact code (#3418, Step 2). See README.md.
//!
//! The same flags, output, messages, exit codes, bazel command lines and
//! record as the Go tool (main.go, record.go, shim.go; kept as
//! :verifiedrun-go); verifiedrun_rs_parity_test runs the two side by side.

use std::collections::{BTreeMap, HashMap};
use std::io::Write;

use unitfile::gocompat::exec::{self, Cmd, Ctx, Io};
use unitfile::gocompat::flag::{self, Flag, Value};
use unitfile::gocompat::json::{self, Dec};
use unitfile::gocompat::path;
use unitfile::gocompat::quote::quote;
use unitfile::Unit;

mod http;
pub mod record;
mod sha256;
pub mod shim;

pub use record::{
    load_recorder, new_record, plan_digest, without_github_tokens, Record, RecorderConfig,
    StatusRecorder,
};
pub use shim::{check_invocation, read_invocations, scan_line, shim_args, Invocation};

use record::{short, STATUS_CONTEXT};

/// Exit codes.
pub const EXIT_VERIFIED: i32 = 0;
pub const EXIT_NOT_VERIFIED: i32 = 1;
pub const EXIT_SETUP: i32 = 2;
pub const EXIT_NOT_RECORDED: i32 = 3;

/// The flags that make a build or test remote-only and tie it to the code.
pub fn strict_flags(head: &str, tree: &str) -> Vec<String> {
    [
        "--config=remote",
        "--platforms=//tools/platforms:linux_x86_64",
        "--host_platform=//tools/platforms:linux_x86_64",
        "--extra_execution_platforms=//tools/platforms:linux_x86_64",
        "--spawn_strategy=remote",
        "--noremote_local_fallback",
        "--noremote_upload_local_results",
        "--disk_cache=",
        "--nocache_test_results",
        "--color=no",
        "--curses=no",
        "--build_metadata=ROLE=VERIFIED_RUN",
    ]
    .iter()
    .map(|s| s.to_string())
    .chain([
        format!(
            "--build_metadata=REPO_URL=https://github.com/{}",
            record::REPO_SLUG
        ),
        format!("--build_metadata=COMMIT_SHA={head}"),
        format!("--build_metadata=TREE_SHA={tree}"),
    ])
    .collect()
}

// ---- git -------------------------------------------------------------------

/// git in dir: trimmed stdout, or "git <args>: <err>: <stderr>".
pub fn git(ctx: &Ctx, dir: &str, args: &[&str]) -> Result<String, String> {
    let mut c = Cmd::new("git", args);
    c.dir = dir.to_string();
    c.stdout = Io::Capture;
    c.stderr = Io::Capture;
    let (r, out) = exec::run(&c, ctx);
    match r {
        Ok(()) => Ok(exec::trim_space(&out.stdout)),
        Err(e) => Err(format!(
            "git {}: {e}: {}",
            args.join(" "),
            exec::trim_space(&out.stderr)
        )),
    }
}

fn is_hash(t: &str) -> bool {
    (t.len() == 40 || t.len() == 64)
        && t.bytes()
            .all(|c| c.is_ascii_digit() || (b'a'..=b'f').contains(&c))
}

/// git's hash of every file at HEAD.
pub fn tree_hash(ctx: &Ctx, dir: &str) -> Result<String, String> {
    let t = git(ctx, dir, &["rev-parse", "--verify", "HEAD^{tree}"])?;
    if !is_hash(&t) {
        return Err(format!("unexpected tree hash {}", quote(&t)));
    }
    Ok(t)
}

/// Refuses uncommitted or untracked files.
pub fn require_clean(ctx: &Ctx, dir: &str) -> Result<(), String> {
    let s = git(
        ctx,
        dir,
        &["status", "--porcelain", "--untracked-files=normal"],
    )?;
    if !s.is_empty() {
        return Err(format!("the working tree has uncommitted or untracked files, so a pass would not describe HEAD. Commit or remove them first:\n{s}"));
    }
    Ok(())
}

// ---- BuildBuddy key ----------------------------------------------------------

const KEY_MARKER: &[u8] = b"x-buildbuddy-api-key=";

fn has_key(p: &str) -> bool {
    std::fs::read(p)
        .map(|b| b.windows(KEY_MARKER.len()).any(|w| w == KEY_MARKER))
        .unwrap_or(false)
}

/// Finds the BuildBuddy key without reading its value: this checkout's
/// user.bazelrc, else the main checkout's through --bazelrc. Never both.
pub fn key_startup(workspace: &str, main_checkout: &str) -> Result<Vec<String>, String> {
    if has_key(&path::join(&[workspace, "user.bazelrc"])) {
        return Ok(Vec::new());
    }
    let main = path::join(&[main_checkout, "user.bazelrc"]);
    if !main_checkout.is_empty()
        && path::clean(main_checkout) != path::clean(workspace)
        && has_key(&main)
    {
        return Ok(vec![format!("--bazelrc={main}")]);
    }
    Err("there is no BuildBuddy key in user.bazelrc (here or in the main checkout), so nothing can run on the remote machines. A local-only run is not offered: CI could not trust it".to_string())
}

// ---- plan ------------------------------------------------------------------

#[derive(Clone, Debug, Default, PartialEq)]
pub struct PlanEntry {
    pub name: String,
    pub runner: String,
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct PlanResult {
    pub is_degraded: bool,
    pub sweep_reason: String,
    pub changed_files: Vec<String>,
    pub matrix: Vec<PlanEntry>,
}

/// Reads the planner's JSON as Go's json.Unmarshal into planResult does.
pub fn decode_plan(data: &[u8]) -> Result<PlanResult, String> {
    let v = json::parse(data)?;
    let mut p = PlanResult::default();
    let mut files: Option<Vec<String>> = None;
    let mut matrix: Option<Vec<PlanEntry>> = None;
    let mut d = Dec::new();
    d.object(
        &v,
        "planResult",
        "main.planResult",
        &["is_degraded", "sweep_reason", "changed_files", "matrix"],
        |d, name, x| match name {
            "is_degraded" => d.bool(x, &mut p.is_degraded),
            "sweep_reason" => d.string(x, &mut p.sweep_reason),
            "changed_files" => d.strings(x, &mut files),
            _ => d.slice(
                x,
                "[]main.planEntry",
                &mut matrix,
                |d, e, out: &mut PlanEntry| {
                    d.object(
                        e,
                        "planEntry",
                        "main.planEntry",
                        &["name", "runner"],
                        |d, n, y| {
                            if n == "name" {
                                d.string(y, &mut out.name)
                            } else {
                                d.string(y, &mut out.runner)
                            }
                        },
                    )
                },
            ),
        },
    );
    d.finish()?;
    p.changed_files = files.unwrap_or_default();
    p.matrix = matrix.unwrap_or_default();
    Ok(p)
}

/// Splits the planner's units into the ones this run can verify the way CI
/// runs them and the ones it must leave to CI, with the reason.
pub fn classify(
    picked: &[PlanEntry],
    units: &HashMap<String, Unit>,
) -> Result<(Vec<Unit>, BTreeMap<String, String>), String> {
    let mut covered = Vec::new();
    let mut left = BTreeMap::new();
    for e in picked {
        let Some(u) = units.get(&e.name) else {
            return Err(format!(
                "the planner picked unit {}, but no pipeline_unit by that name was found",
                quote(&e.name)
            ));
        };
        if u.runner.starts_with("macos") || u.runner.starts_with("xcode") {
            left.insert(
                u.name.clone(),
                "runs on a macOS runner; the remote machines are Linux".to_string(),
            );
        } else if u.needs_emulator {
            left.insert(u.name.clone(), "needs an Android emulator".to_string());
        } else if !u.artifacts.is_empty() {
            left.insert(
                u.name.clone(),
                "builds files CI uploads, and CI runs it with local execution".to_string(),
            );
        } else {
            covered.push(u.clone());
        }
    }
    covered.sort_by(|a: &Unit, b: &Unit| a.name.cmp(&b.name));
    Ok((covered, left))
}

// ---- the run ---------------------------------------------------------------

/// The result of running a script or bazel: Go's (int, error).
pub type RunResult = (i32, Option<String>);

/// Writes the record (the status recorder, or a test's stand-in).
pub type RecordFn<'a> = Box<dyn FnMut(&Record) -> Result<(), String> + 'a>;

/// The run, with every outside effect behind a field so tests can drive it
/// without Bazel, BuildBuddy or GitHub.
pub struct Verifier<'a> {
    pub out: Box<dyn Write + 'a>,
    pub head: String,
    pub tree: String,
    pub base: String,
    pub units: HashMap<String, Unit>,
    pub plan: Box<dyn FnMut() -> Result<PlanResult, String> + 'a>,
    pub run_build_test: Box<dyn FnMut() -> RunResult + 'a>,
    pub run_unit: Box<dyn FnMut(&Unit) -> RunResult + 'a>,
    pub invocations: Box<dyn FnMut() -> Result<Vec<Invocation>, String> + 'a>,
    /// None: --no-record.
    pub record: Option<RecordFn<'a>>,
}

fn err_suffix(e: &Option<String>) -> String {
    match e {
        Some(e) => format!(": {e}"),
        None => String::new(),
    }
}

impl Verifier<'_> {
    fn say(&mut self, s: &str) {
        let _ = self.out.write_all(s.as_bytes());
        let _ = self.out.write_all(b"\n");
        let _ = self.out.flush();
    }

    fn refuse(&mut self, s: &str) -> i32 {
        self.say(&format!("\nNOT VERIFIED: {s}"));
        self.say("Nothing was recorded.");
        EXIT_NOT_VERIFIED
    }

    pub fn run(&mut self) -> i32 {
        let (head, tree, base) = (self.head.clone(), self.tree.clone(), self.base.clone());
        self.say(&format!(
            "verified-run: commit {}, files (tree) {tree}",
            short(&head)
        ));
        self.say(&format!(
            "Compared with {}, the merge base with origin/main.",
            short(&base)
        ));

        let p = match (self.plan)() {
            Ok(p) => p,
            Err(e) => return self.refuse(&format!("the planner failed: {e}")),
        };
        if p.is_degraded {
            return self.refuse(&format!(
                "the planner could not work out what changed ({}). CI would run everything; fix the cause first.",
                p.sweep_reason
            ));
        }
        let (covered, left) = match classify(&p.matrix, &self.units) {
            Ok(x) => x,
            Err(e) => return self.refuse(&e),
        };

        self.say(&format!(
            "\n{} changed file(s). What runs here, and why:",
            p.changed_files.len()
        ));
        self.say("  - build-test: the affected targets, chosen by tools/ci/affected-targets.sh exactly as on a PR.");
        for u in &covered {
            self.say(&format!(
                "  - unit {}: picked by the planner; {} target(s).",
                u.name,
                u.test_targets.len()
            ));
        }
        if covered.is_empty() {
            self.say("  - no presubmit units: the planner picked none this run can cover.");
        }
        if !left.is_empty() {
            self.say("Left to CI (not covered by this record):");
            for (n, why) in &left {
                self.say(&format!("  - unit {n}: {why}"));
            }
        }
        self.say("Also left to CI: the fast checks and every other CI job (macOS build, race tests, lint, ...).\n");

        let (rc, err) = (self.run_build_test)();
        if err.is_some() || rc != 0 {
            return self.refuse(&format!(
                "build-test did not pass (exit {rc}{}).",
                err_suffix(&err)
            ));
        }
        for u in &covered {
            let (rc, err) = (self.run_unit)(u);
            if err.is_some() || rc != 0 {
                return self.refuse(&format!(
                    "unit {} did not pass (exit {rc}{}).",
                    u.name,
                    err_suffix(&err)
                ));
            }
        }

        let invs = match (self.invocations)() {
            Ok(i) => i,
            Err(e) => return self.refuse(&e),
        };
        if invs.is_empty() {
            self.say("\nNothing needed building or testing for this change, so there is nothing to record.");
            return EXIT_VERIFIED;
        }
        for inv in &invs {
            if let Err(e) = check_invocation(inv) {
                return self.refuse(&format!("{e}."));
            }
        }

        let r = new_record(&head, &tree, &base, &invs);
        self.say(&format!(
            "\nPASSED on the remote machines: {} Bazel run(s), lanes {}.",
            invs.len(),
            r.lanes.join(", ")
        ));
        self.say(&format!("Build results: {}", r.target_url));
        self.say(&format!(
            "Record: context {}, {}",
            quote(STATUS_CONTEXT),
            r.description()
        ));

        let Some(rec) = self.record.as_mut() else {
            self.say("Not recorded (--no-record).");
            return EXIT_VERIFIED;
        };
        if let Err(e) = rec(&r) {
            self.say(&format!("\nThe tests passed, but: {e}"));
            return EXIT_NOT_RECORDED;
        }
        self.say(&format!("Recorded on commit {}.", short(&head)));
        EXIT_VERIFIED
    }
}

// ---- wiring ----------------------------------------------------------------

/// The environment for every script and bazel call: the shim first on PATH,
/// no runfiles variables from our own `bazel run`, and no GitHub tokens.
fn child_env(shim_dir: &str, extra: &[String]) -> Vec<String> {
    let mut env: Vec<String> = without_github_tokens(record::environ())
        .into_iter()
        .filter(|kv| {
            let k = kv.split_once('=').map(|(k, _)| k).unwrap_or(kv);
            !matches!(
                k,
                "PATH"
                    | "RUNFILES_DIR"
                    | "RUNFILES_MANIFEST_FILE"
                    | "JAVA_RUNFILES"
                    | "GITHUB_STEP_SUMMARY"
                    | "GITHUB_OUTPUT"
            )
        })
        .collect();
    env.push(format!(
        "PATH={shim_dir}:{}",
        std::env::var("PATH").unwrap_or_default()
    ));
    env.extend_from_slice(extra);
    env
}

/// Go's runCmd: output to our stderr; an exit status is a code, anything
/// else is a code and an error.
fn run_cmd(ctx: &Ctx, dir: &str, env: Vec<String>, name: &str, args: &[&str]) -> RunResult {
    let mut c = Cmd::new(name, args);
    c.dir = dir.to_string();
    c.env = Some(env);
    c.stdout = Io::Stderr;
    c.stderr = Io::Stderr;
    let (r, _) = exec::run(&c, ctx);
    let code = exec::exit_code(&r);
    match r {
        Err(e) if !e.is_exit() => (code, Some(e.to_string())),
        _ => (code, None),
    }
}

/// Resolves a $(rlocationpath) handed over by the BUILD file.
fn runfile(rloc: &str) -> Result<String, String> {
    let mut roots = Vec::new();
    if let Ok(d) = std::env::var("RUNFILES_DIR") {
        if !d.is_empty() {
            roots.push(d);
        }
    }
    if let Ok(exe) = std::env::current_exe() {
        roots.push(format!("{}.runfiles", exe.to_string_lossy()));
    }
    for r in roots {
        let p = path::join(&[&r, rloc]);
        if std::fs::metadata(&p).is_ok() {
            return Ok(p);
        }
    }
    Err(format!(
        "cannot find {rloc} in the runfiles; run this with `bazel run`"
    ))
}

fn flags() -> Vec<Flag> {
    vec![
        Flag {
            name: "planner",
            usage: "runfiles path of the planner (set by the BUILD file)",
            default: Value::Str(String::new()),
        },
        Flag {
            name: "agent-app",
            usage: "runfiles path of agent-app.sh (set by the BUILD file)",
            default: Value::Str(String::new()),
        },
        Flag {
            name: "no-record",
            usage: "run and check, but do not write a record",
            default: Value::Bool(false),
        },
    ]
}

/// `os.MkdirTemp("", prefix)`.
fn mkdir_temp(prefix: &str) -> Result<String, String> {
    let dir = std::env::var("TMPDIR")
        .ok()
        .filter(|d| !d.is_empty())
        .unwrap_or_else(|| "/tmp".to_string());
    let mut seed = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_nanos() as u64)
        .unwrap_or(0)
        ^ (std::process::id() as u64) << 32;
    for _ in 0..10000 {
        seed = seed
            .wrapping_mul(6364136223846793005)
            .wrapping_add(1442695040888963407);
        let name = path::join(&[&dir, &format!("{prefix}{}", (seed >> 33) as u32)]);
        use std::os::unix::fs::DirBuilderExt;
        match std::fs::DirBuilder::new().mode(0o700).create(&name) {
            Ok(()) => return Ok(name),
            Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => continue,
            Err(e) => {
                return Err(unitfile::gocompat::oserr::path_err(
                    "mkdirtemp",
                    &path::join(&[&dir, &format!("{prefix}*")]),
                    &e,
                ))
            }
        }
    }
    Err("mkdirtemp: too many attempts".to_string())
}

/// The tool's main (after the `__shim` check): returns the exit code.
pub fn real_main(args: &[String]) -> i32 {
    let prog = args.first().cloned().unwrap_or_default();
    let defs = flags();
    let f = match flag::parse(&prog, &defs, &args[1.min(args.len())..]) {
        Ok(f) => f,
        Err(e) => {
            exec::eprint(&e.stderr);
            return e.code;
        }
    };
    let fail = |msg: &str| -> i32 {
        exec::eprint(&format!("verified-run: {msg}\n"));
        EXIT_SETUP
    };
    let root = std::env::var("BUILD_WORKSPACE_DIRECTORY").unwrap_or_default();
    if root.is_empty() {
        return fail("run this with `bazel run //tools/pipeline/verifiedrun`");
    }
    let planner = match runfile(&f.str("planner")) {
        Ok(p) => p,
        Err(e) => return fail(&e),
    };
    let agent_app = match runfile(&f.str("agent-app")) {
        Ok(p) => p,
        Err(e) => return fail(&e),
    };
    let self_exe = match std::env::current_exe() {
        Ok(p) => p.to_string_lossy().into_owned(),
        Err(e) => return fail(&e.to_string()),
    };
    let real_bazel = match exec::look_path("bazel") {
        Ok(p) => p,
        Err(_) => return fail("bazel is not on PATH"),
    };

    let ctx = exec::notify_interrupt();

    if let Err(e) = git(&ctx, &root, &["fetch", "--quiet", "origin", "main"]) {
        exec::eprint(&format!(
            "verified-run: warning: could not fetch origin/main, using the copy already here: {e}\n"
        ));
    }
    if let Err(e) = require_clean(&ctx, &root) {
        return fail(&e);
    }
    let head = match git(&ctx, &root, &["rev-parse", "--verify", "HEAD^{commit}"]) {
        Ok(h) => h,
        Err(e) => return fail(&e),
    };
    let tree = match tree_hash(&ctx, &root) {
        Ok(t) => t,
        Err(e) => return fail(&e),
    };
    let base = match git(&ctx, &root, &["merge-base", "origin/main", "HEAD"]) {
        Ok(b) => b,
        Err(e) => {
            return fail(&format!(
                "cannot find where this branch left origin/main: {e}"
            ))
        }
    };
    let common = match git(
        &ctx,
        &root,
        &["rev-parse", "--path-format=absolute", "--git-common-dir"],
    ) {
        Ok(c) => c,
        Err(e) => return fail(&e),
    };
    let main_checkout = path::dir(&common);
    let startup = match key_startup(&root, &main_checkout) {
        Ok(s) => s,
        Err(e) => return fail(&e),
    };
    let units = match unitfile::discover(&root) {
        Ok(u) => u,
        Err(e) => return fail(&format!("cannot read the pipeline units: {e}")),
    };
    let unit_map: HashMap<String, Unit> = units.into_iter().map(|u| (u.name.clone(), u)).collect();

    let work = match mkdir_temp("verified-run-") {
        Ok(w) => w,
        Err(e) => return fail(&e),
    };
    let rc = run_in(
        &ctx,
        &f,
        &root,
        &work,
        &planner,
        &agent_app,
        &self_exe,
        &real_bazel,
        &head,
        &tree,
        &base,
        &main_checkout,
        &startup,
        unit_map,
    );
    let _ = std::fs::remove_dir_all(&work);
    rc
}

#[allow(clippy::too_many_arguments)]
fn run_in(
    ctx: &Ctx,
    f: &flag::Parsed,
    root: &str,
    work: &str,
    planner: &str,
    agent_app: &str,
    self_exe: &str,
    real_bazel: &str,
    head: &str,
    tree: &str,
    base: &str,
    main_checkout: &str,
    startup: &[String],
    unit_map: HashMap<String, Unit>,
) -> i32 {
    let fail = |msg: &str| -> i32 {
        exec::eprint(&format!("verified-run: {msg}\n"));
        EXIT_SETUP
    };
    let shim_dir = path::join(&[work, "bin"]);
    {
        use std::os::unix::fs::DirBuilderExt;
        if let Err(e) = std::fs::DirBuilder::new().mode(0o700).create(&shim_dir) {
            return fail(&unitfile::gocompat::oserr::path_err("mkdir", &shim_dir, &e));
        }
    }
    let wrapper = format!("#!/bin/sh\nexec {} __shim \"$@\"\n", quote(self_exe));
    let wrapper_path = path::join(&[&shim_dir, "bazel"]);
    {
        use std::os::unix::fs::OpenOptionsExt;
        let w = std::fs::OpenOptions::new()
            .write(true)
            .create(true)
            .truncate(true)
            .mode(0o700)
            .open(&wrapper_path)
            .and_then(|mut fh| fh.write_all(wrapper.as_bytes()));
        if let Err(e) = w {
            return fail(&unitfile::gocompat::oserr::path_err(
                "open",
                &wrapper_path,
                &e,
            ));
        }
    }
    let log_path = path::join(&[work, "invocations.jsonl"]);
    let shim_env = vec![
        format!("{}={real_bazel}", shim::ENV_REAL_BAZEL),
        format!("{}={log_path}", shim::ENV_LOG),
        format!("{}={}", shim::ENV_STARTUP, startup.join("\n")),
        format!(
            "{}={}",
            shim::ENV_STRICT,
            strict_flags(head, tree).join("\n")
        ),
    ];
    let rdeps_map = path::join(&[work, "pipeline-rdeps-map.json"]);

    let mut recorder: Option<StatusRecorder> = None;
    if !f.bool("no-record") {
        let key_dir = std::env::var("AGENT_KEY_DIR")
            .ok()
            .filter(|d| !d.is_empty())
            .unwrap_or_else(|| {
                path::join(&[main_checkout, "tools", "sync-env-secrets", "agent-keys"])
            });
        recorder = Some(StatusRecorder {
            config_path: path::join(&[root, record::RECORDER_FILE]),
            agents_path: path::join(&[root, record::AGENTS_FILE]),
            key_dir,
            mint: record::agent_app_minter(agent_app.to_string(), ctx),
            api_base: "https://api.github.com".to_string(),
        });
    }

    let mut v = Verifier {
        out: Box::new(std::io::stdout()),
        head: head.to_string(),
        tree: tree.to_string(),
        base: base.to_string(),
        units: unit_map,
        plan: Box::new(|| {
            // Same dependency map and planner flags as the presubmit plan job.
            let (_, err) = run_cmd(
                ctx,
                root,
                child_env(&shim_dir, &shim_env),
                "bash",
                &["tools/ci/rdeps-map-ref.sh", "fetch", &rdeps_map, base],
            );
            if let Some(e) = err {
                exec::eprint(&format!(
                    "verified-run: no dependency map ({e}); the planner will query instead\n"
                ));
            }
            let a_base = format!("--base={base}");
            let a_map = format!("--rdeps-map={rdeps_map}");
            let a_root = format!("--repo-root={root}");
            let mut c = Cmd::new(
                planner,
                &[
                    &a_base,
                    "--head=HEAD",
                    "--event=pull_request",
                    "--timeout-sec=900",
                    &a_map,
                    "--rdeps-map-max-behind=9",
                    "--format=json",
                    &a_root,
                ],
            );
            c.dir = root.to_string();
            c.env = Some(child_env(&shim_dir, &shim_env));
            c.stdout = Io::Capture;
            c.stderr = Io::Stderr;
            let (r, out) = exec::run(&c, ctx);
            if let Err(e) = r {
                return Err(e.to_string());
            }
            decode_plan(&out.stdout).map_err(|e| format!("unreadable plan: {e}"))
        }),
        run_build_test: Box::new(|| {
            let mut extra = shim_env.clone();
            extra.extend([
                format!("{}=build-test", shim::ENV_LANE),
                "BASE_REF=main".to_string(),
                format!("RDEPS_MAP={rdeps_map}"),
                format!("PLAN_BIN={planner}"),
                "BUILDBUDDY_API_KEY=from-user-bazelrc".to_string(),
            ]);
            run_cmd(
                ctx,
                root,
                child_env(&shim_dir, &extra),
                "bash",
                &["tools/ci/affected-targets.sh"],
            )
        }),
        run_unit: Box::new(|u: &Unit| {
            let mut extra = shim_env.clone();
            extra.push(format!("{}=unit:{}", shim::ENV_LANE, u.name));
            let env = child_env(&shim_dir, &extra);
            let mut a: Vec<&str> = u.build_flags.iter().map(|s| s.as_str()).collect();
            a.extend(u.test_targets.iter().map(|s| s.as_str()));
            let mut test = vec!["test"];
            test.extend(a.iter().copied());
            let (rc, err) = run_cmd(ctx, root, env.clone(), &wrapper_path, &test);
            if err.is_none() && rc == 4 {
                let mut build = vec!["build"];
                build.extend(a.iter().copied());
                return run_cmd(ctx, root, env, &wrapper_path, &build);
            }
            (rc, err)
        }),
        invocations: Box::new(|| read_invocations(&log_path).map(|i| i.unwrap_or_default())),
        record: None,
    };
    if let Some(rec) = recorder.as_ref() {
        v.record = Some(Box::new(move |r: &Record| rec.record(r)));
    }
    v.run()
}

/// The binary's main: the shim when called as `bazel`, else the run.
pub fn main_with(args: Vec<String>) -> i32 {
    if args.len() > 1 && args[1] == "__shim" {
        return shim::shim_main(&args[2..]);
    }
    real_main(&args)
}

#[cfg(test)]
mod tests;
