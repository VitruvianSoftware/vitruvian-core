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

//! main.go: flags, the diff, the dependency map, the engine, and the output
//! formats.

use std::fs::OpenOptions;
use std::io::Write;
use std::time::Instant;

use serde::Serialize;
use unitfile::gocompat::exec::{eprint, print, Ctx};
use unitfile::gocompat::flag::{self, Flag, Value};
use unitfile::gocompat::json;
use unitfile::gocompat::oserr;

use crate::git::{self, DiffOptions, GitRevGraph};
use crate::query::{self, BazelQueryRunner};
use crate::{
    check_global_impact, earlier_map_base, is_docs_only, load_rdeps_map, peek_rdeps_map_commit,
    Engine, MatrixEntry,
};

fn flags() -> Vec<Flag> {
    let s = |name, usage, d: &str| Flag {
        name,
        usage,
        default: Value::Str(d.to_string()),
    };
    vec![
        s("base", "Base git commit/ref for diff comparison", ""),
        s("head", "Head git commit/ref (default: working tree)", ""),
        s("event", "GitHub event name (pull_request, merge_group, push)", ""),
        s("base-ref", "GitHub PR base_ref (e.g. main)", ""),
        s("base-sha", "GitHub merge_group base_sha", ""),
        s("before-rev", "GitHub push event.before SHA", ""),
        s("format", "Output format: json, targets, matrix, text, github-matrix", "json"),
        Flag {
            name: "output-github-matrix",
            usage: "Emit GitHub Actions step outputs to GITHUB_OUTPUT",
            default: Value::Bool(false),
        },
        s("output-file", "Write output to specific file path instead of stdout", ""),
        s("repo-root", "Path to repository workspace root", ""),
        Flag {
            name: "timeout-sec",
            usage: "Timeout in seconds for analysis and query execution",
            default: Value::Int(300),
        },
        s(
            "rdeps-map",
            "Dependency map for the diff base; used instead of a live query when valid (missing file = no map)",
            "",
        ),
        s(
            "emit-rdeps-map",
            "Compute the dependency map for HEAD, write it to this path, and exit",
            "",
        ),
        Flag {
            name: "rdeps-map-max-behind",
            usage: "Accept a dependency map from an ancestor of the diff base up to this many commits back, and plan against that ancestor instead (see EarlierMapBase)",
            default: Value::Int(0),
        },
    ]
}

fn degraded_hint(degraded: bool) -> &'static str {
    if degraded {
        " (could not determine what changed -- running everything, safe but wasteful)"
    } else {
        ""
    }
}

/// `time.Duration.String()` of a whole number of seconds.
fn duration_secs(total: u64) -> String {
    if total == 0 {
        return "0s".to_string();
    }
    let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60);
    if h > 0 {
        format!("{h}h{m}m{s}s")
    } else if m > 0 {
        format!("{m}m{s}s")
    } else {
        format!("{s}s")
    }
}

fn emit_rdeps_map(ctx: &Ctx, repo_root: &str, p: &str) -> i32 {
    let commit = git::rev_parse(ctx, repo_root, "HEAD");
    if commit.is_empty() {
        eprint("emit-rdeps-map: cannot resolve HEAD\n");
        return 1;
    }
    let start = Instant::now();
    let m = match query::build_rdeps_map(ctx, repo_root, &commit) {
        Ok(m) => m,
        Err(e) => {
            eprint(&format!("emit-rdeps-map: {e}\n"));
            return 1;
        }
    };
    let data = json::marshal(&m);
    if let Err((_, msg)) = write_file(p, data.as_bytes()) {
        eprint(&format!("emit-rdeps-map: write {p}: {msg}\n"));
        return 1;
    }
    // Duration.Round(time.Second): half rounds away from zero.
    let ms = start.elapsed().as_millis() as u64;
    let secs = (ms + 500) / 1000;
    print(&format!(
        "dependency map for {commit}: {} packages, {} with dependent tests, {} bytes, {}\n",
        m.packages.as_ref().map(|p| p.len()).unwrap_or(0),
        m.tests.as_ref().map(|t| t.len()).unwrap_or(0),
        data.len(),
        duration_secs(secs)
    ));
    0
}

/// `os.WriteFile(p, data, 0o644)`.
fn write_file(p: &str, data: &[u8]) -> Result<(), (std::io::Error, String)> {
    use std::os::unix::fs::OpenOptionsExt;
    let mut f = OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .mode(0o644)
        .open(p)
        .map_err(|e| {
            let m = oserr::path_err("open", p, &e);
            (e, m)
        })?;
    f.write_all(data).map_err(|e| {
        let m = oserr::path_err("write", p, &e);
        (e, m)
    })
}

#[derive(Serialize)]
struct Include<'a> {
    include: &'a [MatrixEntry],
}

/// The planner's main: returns the exit code.
pub fn main_with(args: Vec<String>) -> i32 {
    let prog = args.first().cloned().unwrap_or_default();
    let defs = flags();
    let f = match flag::parse(&prog, &defs, &args[1.min(args.len())..]) {
        Ok(f) => f,
        Err(e) => {
            eprint(&e.stderr);
            return e.code;
        }
    };

    let mut repo_root = f.str("repo-root");
    if repo_root.is_empty() {
        match std::env::var("BUILD_WORKSPACE_DIRECTORY") {
            Ok(ws) if !ws.is_empty() => repo_root = ws,
            _ => match std::env::current_dir() {
                Ok(d) => repo_root = d.to_string_lossy().into_owned(),
                Err(e) => {
                    eprint(&format!(
                        "failed to get current working directory: {}\n",
                        oserr::path_err("getwd", ".", &e)
                    ));
                    return 1;
                }
            },
        }
    }

    let ctx = Ctx::with_timeout_secs(f.int("timeout-sec"));

    let emit = f.str("emit-rdeps-map");
    if !emit.is_empty() {
        return emit_rdeps_map(&ctx, &repo_root, &emit);
    }

    let diff_opts = DiffOptions {
        repo_root: repo_root.clone(),
        base: f.str("base"),
        head: f.str("head"),
        base_ref: f.str("base-ref"),
        base_sha: f.str("base-sha"),
        before_rev: f.str("before-rev"),
        event: f.str("event"),
    };

    let (res, mut base_rev) = git::extract_changed_files(&ctx, &diff_opts);
    let diff_ok = res.is_ok();
    let mut changed_files = match res {
        Ok(files) => files,
        Err(e) => {
            eprint(&format!(
                "warning: extract changed files error ({e}), falling back to full sweep\n"
            ));
            base_rev = "unknown".to_string();
            vec!["MODULE.bazel".to_string()]
        }
    };

    let rdeps_map_path = f.str("rdeps-map");
    let max_behind = f.int("rdeps-map-max-behind");
    if diff_ok && !rdeps_map_path.is_empty() && max_behind > 0 && !is_docs_only(&changed_files) {
        let (global, _) = check_global_impact(&changed_files);
        if !global {
            let map_commit = peek_rdeps_map_commit(&rdeps_map_path);
            let base_commit = git::rev_parse(&ctx, &repo_root, &base_rev);
            if !map_commit.is_empty() && !base_commit.is_empty() && map_commit != base_commit {
                let graph = GitRevGraph {
                    root: repo_root.clone(),
                    ctx: &ctx,
                };
                let (ok, mut why) = earlier_map_base(&graph, &map_commit, &base_commit, max_behind);
                if ok {
                    let mut widened = diff_opts.clone();
                    widened.base = map_commit.clone();
                    let (wres, rev) = git::extract_changed_files(&ctx, &widened);
                    match wres {
                        Ok(files) => {
                            changed_files = files;
                            base_rev = rev;
                        }
                        Err(werr) => {
                            why = format!(
                                "dependency map not used (cannot diff against {map_commit}: {werr})"
                            );
                        }
                    }
                }
                eprint(&format!("{why}\n"));
            }
        }
    }

    let runner = BazelQueryRunner { ctx: &ctx };
    let mut engine = Engine::new(&repo_root, &runner);
    if !rdeps_map_path.is_empty() {
        let want = git::rev_parse(&ctx, &repo_root, &base_rev);
        match load_rdeps_map(&rdeps_map_path, &want) {
            Err(e) => eprint(&format!(
                "dependency map not used ({e}); falling back to the live query\n"
            )),
            Ok(None) => {
                eprint("no dependency map for this diff base; falling back to the live query\n")
            }
            Ok(Some(m)) => engine.rdeps_map = Some(m),
        }
    }

    let head = f.str("head");
    let p = match engine.compute_plan(changed_files, &base_rev, &head) {
        Ok(p) => p,
        Err(e) => {
            eprint(&format!("error computing plan: {e}\n"));
            return 1;
        }
    };

    let format = f.str("format");
    if f.bool("output-github-matrix") || format == "github-matrix" {
        let matrix_json = json::marshal(&p.matrix);
        let tf = |b: bool| if b { "true" } else { "false" };
        let has_units = tf(!p.matrix.is_empty());
        let lines = format!(
            "matrix={matrix_json}\nhas_units={has_units}\ndocs_only={}\naffected_count={}\nis_global_impact={}\nis_degraded={}\n",
            tf(p.is_docs_only),
            p.matrix.len(),
            tf(p.is_global_impact),
            tf(p.is_degraded)
        );
        if let Ok(gh_out) = std::env::var("GITHUB_OUTPUT") {
            if !gh_out.is_empty() {
                use std::os::unix::fs::OpenOptionsExt;
                if let Ok(mut fh) = OpenOptions::new()
                    .append(true)
                    .create(true)
                    .mode(0o644)
                    .open(&gh_out)
                {
                    // One write per line, as the Go planner does.
                    for l in lines.split_inclusive('\n') {
                        let _ = fh.write_all(l.as_bytes());
                    }
                }
            }
        }
        print(&lines);
        print(&format!("plan_source={}\n", p.plan_source));
        if !p.plan_source_note.is_empty() {
            eprint(&format!("note: {}\n", p.plan_source_note));
        }
        if p.is_degraded {
            eprint(&format!("::warning title=Affected-target analysis degraded::Could not determine what changed, so every pipeline unit will run. This is safe but wasteful. Reason: {}\n", p.sweep_reason));
        }
        return 0;
    }

    let output = match format.as_str() {
        "targets" => {
            let t = p.targets.clone().unwrap_or_default().join("\n");
            if t.is_empty() {
                t
            } else {
                t + "\n"
            }
        }
        "matrix" => json::marshal_indent(&Include { include: &p.matrix }) + "\n",
        "text" => {
            let persona = p.persona.map(|x| x.as_str()).unwrap_or("");
            let operation = p.operation.map(|x| x.as_str()).unwrap_or("");
            let mut sb = String::new();
            sb.push_str("========================================================\n");
            sb.push_str("            Smart Pipeline Execution Plan               \n");
            sb.push_str("========================================================\n");
            sb.push_str(&format!("Base Revision:      {}\n", p.base_rev));
            sb.push_str(&format!("Persona:            {persona}\n"));
            sb.push_str(&format!("Operation:          {operation}\n"));
            sb.push_str(&format!("Docs-Only:          {}\n", p.is_docs_only));
            sb.push_str(&format!(
                "Global Impact:      {} ({})\n",
                p.is_global_impact, p.sweep_reason
            ));
            sb.push_str(&format!(
                "Degraded:           {}{}\n",
                p.is_degraded,
                degraded_hint(p.is_degraded)
            ));
            sb.push_str(&format!(
                "Changed Files:      {}\n",
                p.changed_files.as_ref().map(|v| v.len()).unwrap_or(0)
            ));
            sb.push_str(&format!(
                "Affected Packages:  {}\n",
                p.affected_packages.as_ref().map(|v| v.len()).unwrap_or(0)
            ));
            sb.push_str(&format!(
                "Affected Targets:   {}\n",
                p.targets.as_ref().map(|v| v.len()).unwrap_or(0)
            ));
            sb.push_str(&format!("Pipeline Units:     {}\n", p.matrix.len()));
            sb.push_str(&format!("Duration:           {} ms\n", p.duration_ms));
            sb.push_str("========================================================\n");
            sb
        }
        _ => json::marshal_indent(&p) + "\n",
    };

    let out_file = f.str("output-file");
    if !out_file.is_empty() {
        if let Err((_, msg)) = write_file(&out_file, output.as_bytes()) {
            eprint(&format!("failed to write output file: {msg}\n"));
            return 1;
        }
    } else {
        print(&output);
    }
    0
}
