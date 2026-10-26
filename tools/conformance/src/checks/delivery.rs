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

//! Delivery orchestrator, deploy durable-base, sequencer gate, local-path
//! leak and deleted-workflow-reference checks, ported from check.sh.

use crate::Context;

use std::collections::BTreeSet;
use std::fs;
use std::path::Path;
use std::process::Command;

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// The Phase-3 hard floor: every workflow that may still mutate state WITHOUT
/// being generated, frozen here. The delivery-legacy list may only SHRINK.
const DELIVERY_LEGACY_FLOOR: &[&str] = &[
    ".github/workflows/_deploy-cloud-run.yaml",
    ".github/workflows/_oauth-identity-apply.yaml",
    ".github/workflows/_repo-config-apply.yaml",
    ".github/workflows/_tabula-identity-apply.yaml",
    ".github/workflows/_zitadel-apps-apply.yaml",
    ".github/workflows/foundation-app-deploy.yaml",
    ".github/workflows/foundation-env-deploy.yaml",
    ".github/workflows/foundation-net-deploy.yaml",
    ".github/workflows/foundation-proj-deploy.yaml",
    ".github/workflows/foundation-release.yaml",
    ".github/workflows/tabula-data-stack.yaml",
    ".github/workflows/tabula-release.yaml",
    ".github/workflows/zitadel-apps-mcp-slack-apply.yaml",
];

/// Regex string for state-mutating invocations (used only in emit text).
const DELIVERY_SIDE_EFFECT_RE: &str = r"pulumi up|bazel run .*:(deploy|up|apply)|helm push|gh release upload|docker push|oci_push|tools/charts/publish\.sh";

/// Workflows Phase 3 deleted — references in living docs are failures.
const DELIVERY_DELETED_WORKFLOWS: &[&str] = &[
    "delivery.yaml",
    "oauth-user-inspector-deploy.yaml",
    "tabula-deploy.yaml",
    "tabula-dev-latest.yaml",
    "charts-publish.yml",
    "tabula-build-stack.yaml",
    "copybara-sync-auth-apply.yaml",
    "tabula-identity-stack.yaml",
    "oauth-user-inspector-identity-stack.yaml",
    "_deploy-gate.yaml",
];

// ---------------------------------------------------------------------------
// Side-effect matcher (port of DELIVERY_SIDE_EFFECT_RE grep -qE)
// ---------------------------------------------------------------------------

/// Returns true when `line` matches the DELIVERY_SIDE_EFFECT_RE extended regex.
fn matches_side_effect(line: &str) -> bool {
    if line.contains("pulumi up") {
        return true;
    }
    if line.contains("helm push") {
        return true;
    }
    if line.contains("gh release upload") {
        return true;
    }
    if line.contains("docker push") {
        return true;
    }
    if line.contains("oci_push") {
        return true;
    }
    if line.contains("tools/charts/publish.sh") {
        return true;
    }
    // `bazel run .*:(deploy|up|apply)` — the `bazel run` part followed
    // somewhere by `:<verb>`.
    if line.contains("bazel run ") {
        if line.contains(":deploy") || line.contains(":up") || line.contains(":apply") {
            return true;
        }
    }
    false
}

/// Returns true when the file at `path` contains at least one line matching
/// the side-effect regex.
fn file_matches_side_effect(path: &str) -> bool {
    let Ok(text) = fs::read_to_string(path) else {
        return false;
    };
    text.lines().any(matches_side_effect)
}

// ---------------------------------------------------------------------------
// Helpers: BUILD file discovery + delivery() block parsing
// ---------------------------------------------------------------------------

/// Directories pruned during the BUILD-file walk.
const PRUNE_DIRS: &[&str] = &["node_modules", ".git", ".claude", ".worktrees", ".agents"];

fn should_prune(name: &str) -> bool {
    PRUNE_DIRS.contains(&name) || name.starts_with("bazel-")
}

/// Find every BUILD / BUILD.bazel file under `root` that contains a line
/// starting with `delivery(`. Returns absolute paths, sorted.
fn delivery_declaring_files(root: &str) -> Vec<String> {
    let mut out = Vec::new();
    walk_for_build(Path::new(root), &mut out);
    out.sort_unstable();

    // Filter to only files containing `^delivery(`.
    out.retain(|path| {
        if let Ok(text) = fs::read_to_string(path) {
            text.lines().any(|l| l.starts_with("delivery("))
        } else {
            false
        }
    });
    out
}

fn walk_for_build(dir: &Path, out: &mut Vec<String>) {
    let Ok(entries) = fs::read_dir(dir) else {
        return;
    };
    let mut sorted: Vec<fs::DirEntry> = entries.filter_map(|e| e.ok()).collect();
    sorted.sort_by(|a, b| a.file_name().cmp(&b.file_name()));
    for entry in sorted {
        let name = match entry.file_name().into_string() {
            Ok(s) => s,
            Err(_) => continue,
        };
        let ft = match entry.file_type() {
            Ok(ft) => ft,
            Err(_) => continue,
        };
        if ft.is_dir() {
            if should_prune(&name) {
                continue;
            }
            walk_for_build(&entry.path(), out);
        } else if ft.is_file() && (name == "BUILD" || name == "BUILD.bazel") {
            if let Some(s) = entry.path().to_str() {
                out.push(s.to_string());
            }
        }
    }
}

/// A parsed delivery() declaration: file (relative), unit name, run label.
struct DeliveryDecl {
    file: String,
    name: String,
    run: String,
}

/// Parse delivery() blocks from the given BUILD files. Returns a list of
/// (file_rel, name, run) declarations.
fn parse_delivery_decls(root: &str, build_files: &[String]) -> Vec<DeliveryDecl> {
    let mut decls = Vec::new();
    let root_prefix = if root.ends_with('/') {
        root.to_string()
    } else {
        format!("{}/", root)
    };

    for bf in build_files {
        let rel = bf.strip_prefix(&root_prefix).unwrap_or(bf).to_string();
        let Ok(text) = fs::read_to_string(bf) else {
            continue;
        };

        let mut in_d = false;
        let mut nm = String::new();
        let mut rn = String::new();
        for line in text.lines() {
            if line.starts_with("delivery(") {
                in_d = true;
                nm.clear();
                rn.clear();
                continue;
            }
            if in_d && line.starts_with(')') {
                decls.push(DeliveryDecl {
                    file: rel.clone(),
                    name: nm.clone(),
                    run: rn.clone(),
                });
                in_d = false;
                continue;
            }
            if in_d {
                let trimmed = line.trim();
                if nm.is_empty() {
                    if let Some(v) = extract_starlark_string(trimmed, "name") {
                        nm = v;
                    }
                }
                if let Some(v) = extract_starlark_string(trimmed, "run") {
                    rn = v;
                }
            }
        }
    }
    decls
}

/// Extract value from `key = "value"` in a trimmed BUILD line.
fn extract_starlark_string(trimmed: &str, key: &str) -> Option<String> {
    // Pattern: key followed by optional spaces, `=`, optional spaces, `"`
    let prefix = format!("{} = \"", key);
    let alt_prefix = format!("{}=\"", key);
    let rest = if let Some(r) = trimmed.strip_prefix(&prefix) {
        r
    } else if let Some(r) = trimmed.strip_prefix(&alt_prefix) {
        r
    } else {
        // Allow tabs: `key\t=\t"`
        if !trimmed.starts_with(key) {
            return None;
        }
        let after_key = &trimmed[key.len()..];
        let after_ws = after_key.trim_start();
        let after_eq = after_ws.strip_prefix('=')?;
        let after_ws2 = after_eq.trim_start();
        after_ws2.strip_prefix('"')?
    };
    let end = rest.find('"')?;
    Some(rest[..end].to_string())
}

/// Generated delivery workflows: `.github/workflows/delivery-<app>.yaml` for
/// every `app = "..."` a delivery() block declares. Derived from declarations.
fn delivery_generated_workflows(root: &str) -> Vec<String> {
    let build_files = delivery_declaring_files(root);
    let mut apps = BTreeSet::new();
    for bf in &build_files {
        let Ok(text) = fs::read_to_string(bf) else {
            continue;
        };
        let mut in_d = false;
        for line in text.lines() {
            if line.starts_with("delivery(") {
                in_d = true;
                continue;
            }
            if in_d && line.starts_with(')') {
                in_d = false;
                continue;
            }
            if in_d {
                let trimmed = line.trim();
                if let Some(v) = extract_starlark_string(trimmed, "app") {
                    apps.insert(v);
                }
            }
        }
    }
    apps.into_iter()
        .map(|a| format!(".github/workflows/delivery-{}.yaml", a))
        .collect()
}

/// Target names a macro generates, read from tools/pulumi/defs.bzl.
fn delivery_macro_targets(root: &str) -> Vec<String> {
    let path = format!("{}/tools/pulumi/defs.bzl", root);
    let Ok(text) = fs::read_to_string(&path) else {
        return Vec::new();
    };
    let mut targets = Vec::new();
    let mut in_subcmds = false;
    for line in text.lines() {
        if line.starts_with("_SUBCOMMANDS = [") {
            in_subcmds = true;
            continue;
        }
        if in_subcmds {
            if line.starts_with(']') {
                in_subcmds = false;
                continue;
            }
            // Strip comments.
            let l = if let Some(idx) = line.find('#') {
                &line[..idx]
            } else {
                line
            };
            let cleaned = l.replace(['"', ','], "").trim().to_string();
            if !cleaned.is_empty() {
                targets.push(cleaned);
            }
            continue;
        }
        // `name = "..."` at any level.
        if let Some(v) = extract_starlark_string(line.trim(), "name") {
            targets.push(v);
        }
    }
    targets
}

// ---------------------------------------------------------------------------
// Workflow scanning helpers
// ---------------------------------------------------------------------------

fn list_workflow_files(workflows_dir: &str) -> Vec<String> {
    let Ok(entries) = fs::read_dir(workflows_dir) else {
        return Vec::new();
    };
    let mut files: Vec<String> = entries
        .filter_map(|e| e.ok())
        .filter_map(|e| {
            let name = e.file_name().into_string().ok()?;
            if (name.ends_with(".yaml") || name.ends_with(".yml")) && e.file_type().ok()?.is_file()
            {
                Some(e.path().to_string_lossy().to_string())
            } else {
                None
            }
        })
        .collect();
    files.sort_unstable();
    files
}

// ---------------------------------------------------------------------------
// check_delivery  (group "delivery", lines 2241-2462)
// ---------------------------------------------------------------------------

pub fn check_delivery(ctx: &Context) {
    let build_files = delivery_declaring_files(&ctx.root);
    let decls = parse_delivery_decls(&ctx.root, &build_files);

    // --- (a) declarations ---------------------------------------------------
    if decls.is_empty() {
        ctx.emit_fail(
            "delivery",
            "tools/delivery/defs.bzl",
            "0 declarations",
            ">=1",
            "no delivery() block found in any BUILD file -- the macro, the buildifier formatting, or this parser drifted, and arms (a)+(b) are checking nothing",
            "confirm a delivery() call still starts at column 0 in a BUILD file (e.g. oauth-user-inspector/infra/app/BUILD)",
        );
    } else {
        let mut seen_units: Vec<String> = Vec::new();
        let macro_targets = delivery_macro_targets(&ctx.root);

        for d in &decls {
            if d.name.is_empty() {
                ctx.emit_fail(
                    "delivery",
                    &d.file,
                    "(no name)",
                    "name = \"...\"",
                    "a delivery() block declares no name -- it can never be addressed, gated or rolled back",
                    &format!(
                        "add name = \"<unit>\" to the delivery() call in {}",
                        d.file
                    ),
                );
                continue;
            }

            // (a) unique names
            if seen_units.contains(&d.name) {
                ctx.emit_fail(
                    "delivery",
                    &d.file,
                    &d.name,
                    "unique",
                    "duplicate delivery unit name -- both render the same job id, and YAML keeps only the last, so one unit silently stops being delivered",
                    "rename one of the units; delivery() names are the repo-wide handle for gating, promotion and rollback",
                );
                continue;
            }
            seen_units.push(d.name.clone());

            // (b) run label resolves
            if !(d.run.starts_with("//") && d.run.contains(':')) {
                ctx.emit_fail(
                    "delivery",
                    &d.file,
                    &d.name,
                    "//pkg:target",
                    &format!(
                        "run = \"{}\" is not an absolute Bazel label -- the generated job would fail at 'bazel run' time, i.e. mid-deploy",
                        d.run
                    ),
                    &format!(
                        "set run = \"//<package>:<target>\" on the {} delivery() block",
                        d.name
                    ),
                );
                continue;
            }

            let without_slashes = d.run.strip_prefix("//").unwrap();
            let pkg = without_slashes.split(':').next().unwrap_or("");
            let tgt = without_slashes.rsplit(':').next().unwrap_or("");
            let pkg_dir = format!("{}/{}", ctx.root, pkg);
            let mut dbuild = String::new();
            for cand in &[
                format!("{}/{}/BUILD", ctx.root, pkg),
                format!("{}/{}/BUILD.bazel", ctx.root, pkg),
            ] {
                if Path::new(cand).is_file() {
                    dbuild = cand.clone();
                    break;
                }
            }

            if !Path::new(&pkg_dir).is_dir() {
                ctx.emit_fail(
                    "delivery",
                    &d.file,
                    &d.name,
                    &d.run,
                    &format!(
                        "the run target's package directory ({}) does not exist -- the unit points at a package that moved or was never there",
                        pkg
                    ),
                    &format!(
                        "fix run = on the {} delivery() block, or move the target back to //{}",
                        d.name, pkg
                    ),
                );
            } else if dbuild.is_empty() {
                ctx.emit_fail(
                    "delivery",
                    &d.file,
                    &d.name,
                    &d.run,
                    &format!(
                        "{} has no BUILD file, so //{}:{} is not a Bazel package at all",
                        pkg, pkg, tgt
                    ),
                    &format!(
                        "add a BUILD file declaring {} in {}, or repoint run = on the {} delivery() block",
                        tgt, pkg, d.name
                    ),
                );
            } else {
                let dbuild_content = fs::read_to_string(&dbuild).unwrap_or_default();
                let dbuild_rel = ctx.rel(&dbuild);
                let target_literal = format!("name = \"{}\"", tgt);
                if dbuild_content.contains(&target_literal) {
                    ctx.emit_ok(
                        "delivery",
                        &d.file,
                        &d.name,
                        &d.run,
                        &format!("run target declared literally in {}", dbuild_rel),
                    );
                } else if macro_targets.contains(&tgt.to_string())
                    && dbuild_content.contains("pulumi_project(")
                {
                    ctx.emit_ok(
                        "delivery",
                        &d.file,
                        &d.name,
                        &d.run,
                        &format!("run target generated by pulumi_project() in {}", dbuild_rel),
                    );
                } else {
                    ctx.emit_fail(
                        "delivery",
                        &d.file,
                        &d.name,
                        &d.run,
                        &format!(
                            "{} declares no target named '{}' (and no macro in it is known to generate one) -- the generated job would fail at 'bazel run' time",
                            dbuild_rel, tgt
                        ),
                        &format!(
                            "fix run = on the {} delivery() block, or declare {} in {}",
                            d.name, tgt, dbuild_rel
                        ),
                    );
                }
            }
        }
    }

    // --- (c) side-effect firewall -------------------------------------------
    let gen_wfs = delivery_generated_workflows(&ctx.root);
    let mut sidefx_seen: Vec<String> = Vec::new();
    let mut sidefx_count = 0u32;

    let wf_dir = &ctx.workflows_dir;
    if Path::new(wf_dir).is_dir() {
        for wf_path in &list_workflow_files(wf_dir) {
            let basename = Path::new(wf_path)
                .file_name()
                .and_then(|n| n.to_str())
                .unwrap_or("");
            let wf_rel = format!(".github/workflows/{}", basename);

            if !file_matches_side_effect(wf_path) {
                continue;
            }
            sidefx_count += 1;
            sidefx_seen.push(wf_rel.clone());

            if gen_wfs.contains(&wf_rel) {
                ctx.emit_ok(
                    "delivery",
                    &wf_rel,
                    "generated",
                    "generated",
                    "an app's generated delivery workflow is the sanctioned side-effect path",
                );
                continue;
            }

            // Check legacy TSV.
            let legacy_path = format!("{}/tools/conformance/delivery-legacy.tsv", ctx.root);
            let mut justification = String::new();
            if let Ok(legacy_text) = fs::read_to_string(&legacy_path) {
                for line in legacy_text.lines() {
                    let trimmed = line.trim();
                    if trimmed.is_empty() || trimmed.starts_with('#') {
                        continue;
                    }
                    let parts: Vec<&str> = line.splitn(2, '\t').collect();
                    if parts.first().copied() == Some(wf_rel.as_str()) {
                        justification = parts.get(1).unwrap_or(&"").to_string();
                        break;
                    }
                }
            }

            if !justification.is_empty() {
                ctx.emit_pin(
                    "delivery",
                    &wf_rel,
                    "legacy",
                    "orchestrated",
                    &justification,
                );
            } else {
                ctx.emit_fail(
                    "delivery",
                    &wf_rel,
                    "unlisted",
                    "orchestrated",
                    &format!(
                        "this workflow mutates state (matches: {}) but is neither an app's generated delivery workflow nor a declared legacy exception -- it is a delivery path outside the orchestrator's gating, ladder and kill switch (#1794)",
                        DELIVERY_SIDE_EFFECT_RE
                    ),
                    "declare a delivery() unit and regenerate, or add to delivery-legacy.tsv with justification",
                );
            }
        }
    }

    if sidefx_count == 0 {
        ctx.emit_fail(
            "delivery",
            ".github/workflows",
            "0 matched",
            ">=1",
            "no workflow matched the state-mutation regex -- the pattern or the workflow layout changed, so the side-effect firewall is checking nothing",
            "confirm the deploy/apply/publish lanes still exist and update DELIVERY_SIDE_EFFECT_RE in tools/conformance/check.sh",
        );
    }

    // Stale legacy rows + hard floor.
    let legacy_path = format!("{}/tools/conformance/delivery-legacy.tsv", ctx.root);
    if let Ok(legacy_text) = fs::read_to_string(&legacy_path) {
        let mut floor_ok = 0u32;
        for line in legacy_text.lines() {
            let trimmed = line.trim();
            if trimmed.is_empty() || trimmed.starts_with('#') {
                continue;
            }
            let parts: Vec<&str> = line.splitn(2, '\t').collect();
            let lfile = parts[0];

            if !sidefx_seen.iter().any(|s| s == lfile) {
                ctx.emit_fail(
                    "delivery",
                    lfile,
                    "legacy row",
                    "live match",
                    "listed as a pre-orchestrator legacy exception but the workflow no longer performs a state-mutating invocation (or no longer exists) -- stale exception",
                    "remove the row from tools/conformance/delivery-legacy.tsv",
                );
            }

            // (e) Hard floor.
            if !DELIVERY_LEGACY_FLOOR.contains(&lfile) {
                ctx.emit_fail(
                    "delivery",
                    lfile,
                    "new legacy row",
                    "delivery() unit",
                    "not in the Phase-3 hard floor: the delivery-legacy list may only SHRINK, and this row would add a state-mutating workflow outside the orchestrator's gating, ladder and kill switch (#1794)",
                    "declare a delivery() unit next to the code and regenerate ('bazel run //tools/ci:gen') instead of adding a row; widening DELIVERY_LEGACY_FLOOR in tools/conformance/check.sh is a reviewed decision about the orchestrator's scope (spec §3 non-goals), not a workflow-authoring step",
                );
            } else {
                floor_ok += 1;
            }
        }
        if floor_ok > 0 {
            ctx.emit_ok(
                "delivery",
                "delivery-legacy.tsv",
                &format!("{} rows", floor_ok),
                "<= frozen floor",
                "every legacy exception is inside the Phase-3 hard floor; the list can only shrink from here",
            );
        }
    }

    // --- (d) §6.1 kill switch -----------------------------------------------
    if gen_wfs.is_empty() {
        ctx.emit_fail(
            "delivery",
            "tools/delivery/defs.bzl",
            "0 apps",
            ">=1",
            "no delivery() block declares an app = \"...\" -- the macro or this parser drifted, so no generated workflow is checked at all",
            "confirm the delivery() calls still carry app = \"<app>\" on its own line",
        );
    }
    for genrel in &gen_wfs {
        let genwf = format!("{}/{}", ctx.root, genrel);
        if !Path::new(&genwf).is_file() {
            ctx.emit_fail(
                "delivery",
                genrel,
                "missing",
                "generated",
                "a delivery() block declares this app, but its generated workflow is gone -- nothing renders the app's units, and the orchestrator has no entry point for them",
                &format!("run 'bazel run //tools/ci:gen' and commit {}", genrel),
            );
        } else {
            let content = fs::read_to_string(&genwf).unwrap_or_default();
            if !content.contains("GENERATED by 'bazel run //tools/ci:gen'") {
                ctx.emit_fail(
                    "delivery",
                    genrel,
                    "hand-written",
                    "generated",
                    "the delivery workflow has lost its GENERATED banner -- it is being maintained by hand, which the next 'bazel run //tools/ci:gen' silently reverts",
                    "regenerate with 'bazel run //tools/ci:gen'; put real changes in the delivery() declarations or //tools/delivery/gen",
                );
            } else if !content.contains("DELIVERY_ORCHESTRATOR_ENABLED == 'true'") {
                ctx.emit_fail(
                    "delivery",
                    genrel,
                    "no kill switch",
                    "vars gate",
                    "the orchestrate job does not carry the DELIVERY_ORCHESTRATOR_ENABLED condition -- spec §6.1 rollback level 1 (disable by flipping a repo variable, no commit) does not exist",
                    "restore the job-level if: vars.DELIVERY_ORCHESTRATOR_ENABLED == 'true' in //tools/delivery/gen and regenerate",
                );
            } else {
                ctx.emit_ok(
                    "delivery",
                    genrel,
                    "kill switch",
                    "vars gate",
                    "generated, and disableable by flipping DELIVERY_ORCHESTRATOR_ENABLED (spec §6.1 rollback level 1)",
                );
            }
        }
    }

    // Stale generated workflows: on disk but not declared.
    if Path::new(wf_dir).is_dir() {
        for wf_path in &list_workflow_files(wf_dir) {
            let basename = Path::new(wf_path)
                .file_name()
                .and_then(|n| n.to_str())
                .unwrap_or("");
            if !basename.starts_with("delivery") || !basename.ends_with(".yaml") {
                continue;
            }
            let wf_rel = format!(".github/workflows/{}", basename);
            if gen_wfs.contains(&wf_rel) {
                continue;
            }
            let content = fs::read_to_string(wf_path).unwrap_or_default();
            if !content.contains("GENERATED by 'bazel run //tools/ci:gen'") {
                continue;
            }
            ctx.emit_fail(
                "delivery",
                &wf_rel,
                "stale",
                "an app's workflow",
                "a generated delivery workflow that no delivery() app accounts for -- it still triggers on every push and release, delivering units nothing declares into it",
                "run 'bazel run //tools/ci:gen', which removes it, and commit the deletion",
            );
        }
    }
}

// ---------------------------------------------------------------------------
// check_no_local_paths  (group "localpath", lines 2464-2502)
// ---------------------------------------------------------------------------

pub fn check_no_local_paths(ctx: &Context) {
    // Check root is a git repo.
    let git_check = Command::new("git")
        .args(["-C", &ctx.root, "rev-parse", "--git-dir"])
        .output();
    match git_check {
        Ok(out) if out.status.success() => {}
        _ => {
            ctx.emit_fail(
                "localpath",
                "tree",
                "not a git repo",
                "scannable",
                "the leaked-local-path guard cannot scan - it would report green without looking",
                &format!("check $ROOT ({}) is the git worktree", ctx.root),
            );
            return;
        }
    }

    let grep_result = Command::new("git")
        .args([
            "-C",
            &ctx.root,
            "grep",
            "-nI",
            "-E",
            r#"\.claude-worktrees/|/(Users|home)/[^/ "]+/[^ "]*vitruvian-core"#,
            "--",
            "*.yaml",
            "*.yml",
            "*.json",
            "*.go",
            "*.ts",
            "*.tsx",
            "*.sh",
            "*.sky",
            "*.bzl",
        ])
        .output();

    let raw = match grep_result {
        Ok(out) => String::from_utf8_lossy(&out.stdout).to_string(),
        Err(_) => String::new(),
    };

    // Filter out self and docs/.
    let hits: Vec<&str> = raw
        .lines()
        .filter(|l| !l.is_empty())
        .filter(|l| !l.starts_with("tools/conformance/check.sh:"))
        .filter(|l| !l.starts_with("docs/") && !l.starts_with("devx/docs/"))
        .collect();

    if hits.is_empty() {
        ctx.emit_ok_uncounted(
            "localpath",
            "tree",
            "no local paths",
            "none",
            "no committed file embeds a developer machine path",
        );
        return;
    }

    for h in &hits {
        let file = h.split(':').next().unwrap_or(h);
        let rest = h
            .strip_prefix(file)
            .and_then(|s| s.strip_prefix(':'))
            .unwrap_or("");
        ctx.emit_fail(
            "localpath",
            file,
            "local path",
            "none",
            &format!("embeds a developer machine path: {}", rest),
            "remove it - if this file is generated, generate it with a real template, not a shell heredoc (zsh applies :a/:r history modifiers inside $var:word)",
        );
    }
    // Bash increments FAIL_COUNT only ONCE (outside the loop).
    // Our emit_fail increments per call, matching the way individual rows are
    // emitted but the bash also sets OVERALL_FAIL once. That's fine — the
    // per-row emits are the same.
}

// ---------------------------------------------------------------------------
// check_deploy_sequencer_gate  (group "gate", lines 1803-1869)
// ---------------------------------------------------------------------------

pub fn check_deploy_sequencer_gate(ctx: &Context) {
    // Check if tools/deploy/ is allowlisted in affected-targets.sh.
    let at_path = format!("{}/tools/ci/affected-targets.sh", ctx.root);
    let at_text = fs::read_to_string(&at_path).unwrap_or_default();
    // grep -o "\^tools/([^']*)" then check for |deploy/|
    let allow = {
        let mut found = String::new();
        if let Some(idx) = at_text.find("^tools/(") {
            let rest = &at_text[idx..];
            if let Some(end) = rest.find('\'').or_else(|| rest.find('"')) {
                found = rest[..end].to_string();
            } else {
                found = rest.to_string();
            }
        }
        found
    };

    if !allow.contains("|deploy/|") {
        ctx.emit_ok_uncounted(
            "gate",
            "tools/deploy",
            "force-sweeps",
            "n/a",
            "tools/deploy is not allowlisted, so the global-impact guard still covers a sequencer change",
        );
        return;
    }

    let gen_wfs = delivery_generated_workflows(&ctx.root);
    let mut missing_parts: Vec<String> = Vec::new();
    let mut gen_callers: Vec<String> = Vec::new();

    if Path::new(&ctx.workflows_dir).is_dir() {
        for wf_path in &list_workflow_files(&ctx.workflows_dir) {
            let content = fs::read_to_string(wf_path).unwrap_or_default();
            let basename = Path::new(wf_path)
                .file_name()
                .and_then(|n| n.to_str())
                .unwrap_or("");

            // Only callers of _deploy-cloud-run.yaml.
            let is_caller = content.lines().any(|l| {
                let trimmed = l.trim_start();
                trimmed.starts_with("uses:")
                    && trimmed.contains("./.github/workflows/_deploy-cloud-run.yaml")
            });
            if !is_caller {
                continue;
            }

            let wf_rel = format!(".github/workflows/{}", basename);
            if gen_wfs.contains(&wf_rel) {
                gen_callers.push(basename.to_string());
                continue;
            }

            // Check for tools/deploy/ in trigger paths.
            let has_trigger = content.lines().any(|l| {
                let trimmed = l.trim_start();
                // extra_path_regex or extra-path-regex with tools/deploy/
                let lower = trimmed.to_lowercase();
                if (lower.starts_with("extra_path_regex:")
                    || lower.starts_with("extra-path-regex:"))
                    && trimmed.contains("tools/deploy/")
                {
                    return true;
                }
                // paths glob entry
                if trimmed.starts_with("- \"tools/deploy/")
                    || trimmed.starts_with("- 'tools/deploy/")
                {
                    return true;
                }
                false
            });

            if !has_trigger {
                missing_parts.push(basename.to_string());
            }
        }
    }

    if !gen_callers.is_empty() {
        // Check delivery declarations for Cloud Run units missing tools/deploy/.
        let build_files = delivery_declaring_files(&ctx.root);
        let mut decl_missing: Vec<String> = Vec::new();
        for bf in &build_files {
            let Ok(text) = fs::read_to_string(bf) else {
                continue;
            };
            let mut in_d = false;
            let mut nm = String::new();
            let mut cloudrun = false;
            let mut seq = false;
            for line in text.lines() {
                if line.starts_with("delivery(") {
                    in_d = true;
                    nm.clear();
                    cloudrun = false;
                    seq = false;
                    continue;
                }
                if in_d && line.starts_with(')') {
                    if cloudrun && !seq {
                        if !nm.is_empty() {
                            decl_missing.push(nm.clone());
                        }
                    }
                    in_d = false;
                    continue;
                }
                if in_d {
                    let trimmed = line.trim();
                    if nm.is_empty() {
                        if let Some(v) = extract_starlark_string(trimmed, "name") {
                            nm = v;
                        }
                    }
                    if let Some(v) = extract_starlark_string(trimmed, "kind") {
                        if v == "cloud-run" {
                            cloudrun = true;
                        }
                    }
                    if line.contains("\"tools/deploy/\"")
                        || line.contains("'tools/deploy/'")
                        || line.contains("tools/deploy/")
                    {
                        // More precise: check the line for the pattern
                        if line.contains("tools/deploy/") {
                            seq = true;
                        }
                    }
                }
            }
        }
        if !decl_missing.is_empty() {
            missing_parts.push(format!("delivery()(units:{})", decl_missing.join(",")));
        }
    }

    if missing_parts.is_empty() {
        ctx.emit_ok_uncounted(
            "gate",
            "_deploy-cloud-run.yaml callers",
            "trigger on tools/deploy/",
            "all callers",
            "every Cloud Run rollout workflow redeploys when the sequencer changes",
        );
    } else {
        ctx.emit_fail(
            "gate",
            &missing_parts.join(" "),
            "no tools/deploy/ trigger",
            "tools/deploy/",
            "tools/deploy/ is allowlisted out of the global-impact guard, so these rollout workflows would NOT redeploy when the candidate->smoke->promote sequencer changes",
            "add tools/deploy/ to the workflow's EXTRA_PATH_REGEX (graph-gated apps), or 'tools/deploy/**' to its push paths: (path-gated apps)",
        );
    }
}

// ---------------------------------------------------------------------------
// check_deploy_durable_base  (group "durable", lines 1910-2039)
// ---------------------------------------------------------------------------

pub fn check_deploy_durable_base(ctx: &Context) {
    if !Path::new(&ctx.workflows_dir).is_dir() {
        return;
    }

    let mut found_any = 0u32;

    for wf_path in &list_workflow_files(&ctx.workflows_dir) {
        let content = fs::read_to_string(wf_path).unwrap_or_default();

        // Match: `run: bash tools/ci/deploy-affected.sh` or
        //        `run: bazel run //tools/delivery/orchestrate`
        let has_engine = content.lines().any(|l| {
            let trimmed = l.trim_start();
            if !trimmed.starts_with("run:") {
                return false;
            }
            let after_run = trimmed[4..].trim_start();
            after_run.starts_with("bash tools/ci/deploy-affected.sh")
                || after_run.starts_with("bazel run //tools/delivery/orchestrate")
        });
        if !has_engine {
            continue;
        }

        found_any += 1;
        let basename = Path::new(wf_path)
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("");
        let wf_rel = format!(".github/workflows/{}", basename);

        // resolve-deploy-base.sh presence
        let has_resolver = content.lines().any(|l| {
            let trimmed = l.trim_start();
            trimmed.starts_with("run:")
                && trimmed[4..]
                    .trim_start()
                    .starts_with("bash tools/ci/resolve-deploy-base.sh")
        });

        // Parse concurrency groups (awk port).
        let mut groups: Vec<String> = Vec::new();
        {
            let mut in_c = false;
            for line in content.lines() {
                let trimmed = line.trim();
                if trimmed == "concurrency:" {
                    in_c = true;
                    continue;
                }
                if in_c {
                    if trimmed.starts_with("group:") {
                        let g = trimmed.strip_prefix("group:").unwrap().trim().to_string();
                        groups.push(g);
                        in_c = false;
                        continue;
                    }
                    // Another key at any indentation ends the concurrency block.
                    if trimmed
                        .chars()
                        .next()
                        .map_or(false, |c| c.is_ascii_alphanumeric() || c == '_' || c == '-')
                        && trimmed.contains(':')
                    {
                        in_c = false;
                    }
                }
            }
        }
        let group_count = groups.len();

        // sha-keyed check with multi-group awareness.
        let sha_keyed_group = if group_count > 1 {
            groups
                .iter()
                .filter(|g| !g.contains("delivery-${{ github.workflow }}"))
                .find(|g| g.contains("github.sha"))
                .cloned()
                .unwrap_or_default()
        } else {
            groups
                .iter()
                .find(|g| g.contains("github.sha"))
                .cloned()
                .unwrap_or_default()
        };

        let unserialized = group_count == 0;
        let sha_keyed = !sha_keyed_group.is_empty();

        // continue-on-error check
        let mut masked = false;
        let mut mask_where = String::new();

        let has_coe = content.lines().any(|l| {
            let trimmed = l.trim_start();
            trimmed.starts_with("continue-on-error:")
        });
        if has_coe {
            masked = true;
            mask_where = wf_rel.clone();
        }

        // Check if it calls _deploy-cloud-run.yaml
        let calls_deploy_cr = content.lines().any(|l| {
            let trimmed = l.trim_start();
            trimmed.starts_with("uses:")
                && trimmed.contains("./.github/workflows/_deploy-cloud-run.yaml")
        });
        if calls_deploy_cr {
            let callee = format!("{}/_deploy-cloud-run.yaml", ctx.workflows_dir);
            if Path::new(&callee).is_file() {
                let callee_content = fs::read_to_string(&callee).unwrap_or_default();
                let callee_coe = callee_content.lines().any(|l| {
                    let trimmed = l.trim_start();
                    trimmed.starts_with("continue-on-error:")
                });
                if callee_coe {
                    masked = true;
                    if mask_where.is_empty() {
                        mask_where = ".github/workflows/_deploy-cloud-run.yaml".to_string();
                    } else {
                        mask_where =
                            format!("{}, .github/workflows/_deploy-cloud-run.yaml", mask_where);
                    }
                }
            }
        }

        if has_resolver && !unserialized && !sha_keyed && !masked {
            ctx.emit_ok(
                "durable",
                &wf_rel,
                "durable base",
                "coalescing, unmasked",
                &format!(
                    "diffs from resolve-deploy-base.sh's durable base; {} concurrency group(s) found, all coalescing (non-sha); no continue-on-error in the deploy chain to fake a success verdict",
                    group_count
                ),
            );
            continue;
        }

        if !has_resolver {
            ctx.emit_fail(
                "durable",
                &wf_rel,
                "event.before",
                "resolve-deploy-base.sh",
                "runs deploy-affected.sh but never resolve-deploy-base.sh \u{2014} BEFORE_REV traces back to github.event.before, which a run dropped by a coalescing concurrency group (#1311/#1335 eviction) can skip forever (#1351)",
                "add a step running tools/ci/resolve-deploy-base.sh before the gate step and feed BEFORE_REV: ${{ steps.<id>.outputs.base_sha || github.event.before }}",
            );
        }
        if unserialized {
            ctx.emit_fail(
                "durable",
                &wf_rel,
                "no group",
                "coalescing",
                "no concurrency group serializes this deploy lane \u{2014} two commits can deploy against the SAME live env + build Artifact Registry concurrently",
                "add a constant (non-sha) concurrency group, either at the workflow level or on each deploy-* job that calls _deploy-cloud-run.yaml (job-level concurrency does not work INSIDE that reusable workflow's own job -- put it on the calling job)",
            );
        } else if sha_keyed {
            ctx.emit_fail(
                "durable",
                &wf_rel,
                "sha-keyed",
                "coalescing",
                &format!(
                    "a concurrency group in this file keys on github.sha ('{}') \u{2014} that lets two commits deploy against the SAME live env + build Artifact Registry concurrently; sha-keying is the #1335 fix for GATING lanes (which CAN run in parallel), not this DEPLOY lane shape, which must serialize",
                    sha_keyed_group
                ),
                "key the group on a constant string instead (e.g. group: deploy-${{ inputs.app-name }}-${{ inputs.environment }}-${{ inputs.service-name }} on the calling job), and rely on tools/ci/resolve-deploy-base.sh for eviction-safety instead of per-commit isolation",
            );
        }
        if masked {
            ctx.emit_fail(
                "durable",
                &wf_rel,
                "continue-on-error",
                "no masking",
                &format!(
                    "continue-on-error in {} lets a failed deploy step still conclude the run success \u{2014} resolve-deploy-base.sh would then adopt that FAILED commit as the durable base, silently skipping every real change since (a subtler #1351 that conformance would otherwise never catch)",
                    mask_where
                ),
                "remove continue-on-error from the push-triggered deploy chain (gate -> build -> deploy), including inside _deploy-cloud-run.yaml \u{2014} a masked failure there breaks the invariant the durable base depends on",
            );
        }
    }

    if found_any == 0 {
        ctx.emit_fail(
            "durable",
            ".github/workflows",
            "0 matched",
            ">=1",
            "no workflow invokes the affected engine (directly, or via //tools/delivery/orchestrate) \u{2014} the parser or the workflow layout changed",
            "confirm the generated .github/workflows/delivery-<app>.yaml files still run 'bazel run //tools/delivery/orchestrate'",
        );
    }
}

// ---------------------------------------------------------------------------
// check_deleted_workflow_references  (group "delivery", lines 2214-2239)
// ---------------------------------------------------------------------------

pub fn check_deleted_workflow_references(ctx: &Context) {
    let docs_dir = format!("{}/docs", ctx.root);
    let mut md_files: Vec<String> = Vec::new();

    // Walk docs/ excluding archive/ and superpowers/.
    if Path::new(&docs_dir).is_dir() {
        walk_md_files(&docs_dir, &mut md_files, &ctx.root);
    }

    // Also check CONTRIBUTING.md and README.md.
    for name in &["CONTRIBUTING.md", "README.md"] {
        let p = format!("{}/{}", ctx.root, name);
        if Path::new(&p).is_file() {
            md_files.push(p);
        }
    }

    if md_files.is_empty() {
        return;
    }

    let mut bad: Vec<String> = Vec::new();
    for f in &md_files {
        let Ok(content) = fs::read_to_string(f) else {
            continue;
        };
        let f_rel = f.strip_prefix(&format!("{}/", ctx.root)).unwrap_or(f);
        for dw in DELIVERY_DELETED_WORKFLOWS {
            if content.contains(dw) {
                bad.push(format!("{}->{}", f_rel, dw));
            }
        }
    }

    if bad.is_empty() {
        ctx.emit_ok(
            "delivery",
            "docs + CONTRIBUTING",
            "no dead refs",
            "delivery-<app>.yaml",
            "no living document points at a workflow Phase 3 deleted",
        );
    } else {
        ctx.emit_fail(
            "delivery",
            &bad.join(" "),
            "deleted workflow",
            "delivery-<app>.yaml",
            "a living document names a workflow Phase 3 deleted -- a runbook telling someone to dispatch it is an instruction that cannot be followed",
            "point the doc at the unit's app workflow, .github/workflows/delivery-<app>.yaml (its workflow_dispatch takes a unit + an environment), or at the unit's break-glass 'bazel run' target",
        );
    }
}

/// Walk `dir` collecting .md files, excluding archive/ and superpowers/ subtrees.
fn walk_md_files(dir: &str, out: &mut Vec<String>, root: &str) {
    let Ok(entries) = fs::read_dir(dir) else {
        return;
    };
    let mut sorted: Vec<fs::DirEntry> = entries.filter_map(|e| e.ok()).collect();
    sorted.sort_by(|a, b| a.file_name().cmp(&b.file_name()));
    for entry in sorted {
        let name = match entry.file_name().into_string() {
            Ok(s) => s,
            Err(_) => continue,
        };
        let ft = match entry.file_type() {
            Ok(ft) => ft,
            Err(_) => continue,
        };
        if ft.is_dir() {
            // Exclude archive/ and superpowers/ relative to docs/.
            let rel = entry
                .path()
                .to_string_lossy()
                .strip_prefix(&format!("{}/docs/", root))
                .unwrap_or("")
                .to_string();
            if rel == "archive"
                || rel.starts_with("archive/")
                || rel == "superpowers"
                || rel.starts_with("superpowers/")
            {
                continue;
            }
            walk_md_files(&entry.path().to_string_lossy(), out, root);
        } else if ft.is_file() && name.ends_with(".md") {
            if let Some(p) = entry.path().to_str() {
                out.push(p.to_string());
            }
        }
    }
}
