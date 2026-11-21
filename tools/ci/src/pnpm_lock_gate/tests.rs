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

//! Black-box & repo-parity tests for //tools/ci:pnpm_lock_gate.

use ci_testkit::{
    bin, git, names_job, verdict_fail_open, workflow_job_text, workflow_jobs, write, Output, Run,
    TempDir,
};
use pnpm_lock_gate::{extract_closure, extract_workflow_paths, parse_lockfile};
use std::path::Path;

const SAMPLE_WORKFLOW: &str = r#"name: sample-image
on:
  workflow_dispatch: {}
  push:
    branches: [main]
    paths:
      - 'apps/web/demo/**'
      - '!apps/web/demo/**/*.md'
      - '!apps/web/demo/tests/**'
      - 'pnpm-lock.yaml'
      - 'pnpm-workspace.yaml'
  pull_request:
    paths:
      - 'apps/web/demo/**'
      - '!apps/web/demo/**/*.md'
      - '!apps/web/demo/tests/**'
      - 'pnpm-lock.yaml'
      - 'pnpm-workspace.yaml'
"#;

const BASE_LOCK: &str = r#"lockfileVersion: '9.0'

settings:
  autoInstallPeers: true
  excludeLinksFromLockfile: false

catalogs:
  default:
    unused-tool:
      specifier: ^1.0.0
      version: 1.0.0
  demo:
    shared-lib:
      specifier: ^2.0.0
      version: 2.0.0

overrides:
  foo@1: ^1.2.3

packageExtensionsChecksum: sha256-base

importers:

  apps/web/demo:
    dependencies:
      alpha:
        specifier: ^1.0.0
        version: 1.0.0
      local-pkg:
        specifier: workspace:*
        version: link:../../../packages/local-pkg
      shared-lib:
        specifier: 'catalog:demo'
        version: 2.0.0

  packages/local-pkg:
    dependencies:
      beta:
        specifier: ^1.0.0
        version: 1.0.0

  apps/web/unrelated:
    dependencies:
      gamma:
        specifier: ^1.0.0
        version: 1.0.0

packages:

  alpha@1.0.0:
    resolution: {integrity: sha512-alpha100}

  beta@1.0.0:
    resolution: {integrity: sha512-beta100}

  gamma@1.0.0:
    resolution: {integrity: sha512-gamma100}

  shared-lib@2.0.0:
    resolution: {integrity: sha512-shared200}

snapshots:

  alpha@1.0.0:
    dependencies:
      beta: 1.0.0

  beta@1.0.0: {}

  gamma@1.0.0: {}

  shared-lib@2.0.0: {}
"#;

fn run_gate(repo: &Path, args: &[&str], env_vars: &[(&str, &str)]) -> (Output, String) {
    let dir = TempDir::new();
    let gh_out = dir.join("github_output");
    let mut r = Run::new(&bin("BIN"))
        .cwd(repo)
        .args(args)
        .env("GITHUB_OUTPUT", gh_out.to_str().unwrap());
    for (k, v) in env_vars {
        r = r.env(k, v);
    }
    let out = r.go();
    let recorded = std::fs::read_to_string(&gh_out).unwrap_or_default();
    (out, recorded)
}

fn init_sample_repo() -> (TempDir, String) {
    let dir = TempDir::new();
    let repo = dir.path();
    git(repo, &["init", "-q", "."]);
    write(
        repo.join(".github/workflows/sample-image.yaml"),
        SAMPLE_WORKFLOW,
    );
    write(repo.join("pnpm-lock.yaml"), BASE_LOCK);
    write(repo.join("apps/web/demo/index.ts"), "export const x = 1;\n");
    write(repo.join("apps/web/demo/README.md"), "doc\n");
    write(repo.join("apps/web/unrelated/pkg.json"), "{}\n");
    git(repo, &["add", "."]);
    git(repo, &["commit", "-q", "-m", "base"]);
    let base_sha = git(repo, &["rev-parse", "HEAD"]);
    (dir, base_sha)
}

#[test]
fn unrelated_lockfile_edit_returns_run_false() {
    let (dir, base_sha) = init_sample_repo();
    let repo = dir.path();
    let updated_lock = BASE_LOCK
        .replace(
            "unused-tool:\n      specifier: ^1.0.0\n      version: 1.0.0",
            "unused-tool:\n      specifier: ^1.1.0\n      version: 1.1.0",
        )
        .replace("gamma@1.0.0", "gamma@1.0.1")
        .replace("version: 1.0.0\n\npackages:", "version: 1.0.1\n\npackages:")
        .replace("sha512-gamma100", "sha512-gamma101");
    write(repo.join("pnpm-lock.yaml"), &updated_lock);
    write(repo.join("apps/web/unrelated/pkg.json"), "{\"v\":2}\n");
    // Excluded doc path under demo/ should also not trigger a rebuild.
    write(repo.join("apps/web/demo/README.md"), "updated docs\n");
    git(repo, &["add", "."]);
    git(repo, &["commit", "-q", "-m", "bump unrelated"]);

    let (o, gh_out) = run_gate(
        repo,
        &[
            "--workflow",
            ".github/workflows/sample-image.yaml",
            "--importers",
            "apps/web/demo",
            "--base",
            &base_sha,
            "--event",
            "pull_request",
        ],
        &[],
    );
    assert_eq!(o.code, 0, "{o:?}");
    assert!(
        gh_out.contains("verdict=skip\n"),
        "gh_out={gh_out}\no={o:?}"
    );
}

#[test]
fn linked_workspace_transitive_dep_change_returns_run_true() {
    let (dir, base_sha) = init_sample_repo();
    let repo = dir.path();
    let updated_lock = BASE_LOCK.replace("sha512-beta100", "sha512-beta100-changed");
    write(repo.join("pnpm-lock.yaml"), &updated_lock);
    git(repo, &["add", "pnpm-lock.yaml"]);
    git(repo, &["commit", "-q", "-m", "change beta integrity"]);

    let (o, gh_out) = run_gate(
        repo,
        &[
            "--workflow",
            ".github/workflows/sample-image.yaml",
            "--importers",
            "apps/web/demo",
            "--base",
            &base_sha,
            "--event",
            "push",
        ],
        &[],
    );
    assert_eq!(o.code, 0, "{o:?}");
    assert!(gh_out.contains("verdict=run\n"), "gh_out={gh_out}\no={o:?}");
    assert!(
        gh_out.contains("pnpm-lock.yaml closure changed"),
        "expected closure change reason (not fail-open): {gh_out}"
    );
}

#[test]
fn non_lockfile_workflow_path_change_returns_run_true() {
    let (dir, base_sha) = init_sample_repo();
    let repo = dir.path();
    write(repo.join("apps/web/demo/index.ts"), "export const x = 2;\n");
    git(repo, &["add", "apps/web/demo/index.ts"]);
    git(repo, &["commit", "-q", "-m", "edit app source"]);

    let (o, gh_out) = run_gate(
        repo,
        &[
            "--workflow",
            ".github/workflows/sample-image.yaml",
            "--importers",
            "apps/web/demo",
            "--base",
            &base_sha,
            "--event",
            "pull_request",
        ],
        &[],
    );
    assert_eq!(o.code, 0, "{o:?}");
    assert!(gh_out.contains("verdict=run\n"), "gh_out={gh_out}\no={o:?}");
    assert!(
        gh_out.contains("workflow path changed: apps/web/demo/index.ts"),
        "expected non-lockfile workflow path reason: {gh_out}"
    );
}

#[test]
fn override_change_or_unknown_section_or_bad_base_fails_open() {
    let (dir, base_sha) = init_sample_repo();
    let repo = dir.path();

    // Global overrides change -> verdict=run.
    let ov_lock = BASE_LOCK.replace("foo@1: ^1.2.3", "foo@1: ^1.2.4");
    write(repo.join("pnpm-lock.yaml"), &ov_lock);
    git(repo, &["add", "pnpm-lock.yaml"]);
    git(repo, &["commit", "-q", "-m", "override bump"]);
    let (_, gh_ov) = run_gate(
        repo,
        &[
            "--workflow",
            ".github/workflows/sample-image.yaml",
            "--importers",
            "apps/web/demo",
            "--base",
            &base_sha,
            "--event",
            "pull_request",
        ],
        &[],
    );
    assert!(gh_ov.contains("verdict=run\n"), "{gh_ov}");

    // Unknown top-level section -> fail open verdict=run.
    let head_prev = git(repo, &["rev-parse", "HEAD"]);
    let unk_lock = format!("{BASE_LOCK}\nfutureSection:\n  key: value\n");
    write(repo.join("pnpm-lock.yaml"), &unk_lock);
    git(repo, &["add", "pnpm-lock.yaml"]);
    git(repo, &["commit", "-q", "-m", "unknown top key"]);
    let (o, gh_unk) = run_gate(
        repo,
        &[
            "--workflow",
            ".github/workflows/sample-image.yaml",
            "--importers",
            "apps/web/demo",
            "--base",
            &head_prev,
            "--event",
            "pull_request",
        ],
        &[],
    );
    assert_eq!(o.code, 0, "{o:?}");
    assert!(gh_unk.contains("verdict=run\n"), "{gh_unk}");

    // Missing / all-zero base -> fail open verdict=run.
    let (o0, gh_zero) = run_gate(
        repo,
        &[
            "--workflow",
            ".github/workflows/sample-image.yaml",
            "--importers",
            "apps/web/demo",
            "--base",
            "0000000000000000000000000000000000000000",
            "--event",
            "push",
        ],
        &[],
    );
    assert_eq!(o0.code, 0, "{o0:?}");
    assert!(gh_zero.contains("verdict=run\n"), "{gh_zero}");

    // workflow_dispatch -> always verdict=run.
    let (od, gh_disp) = run_gate(
        repo,
        &[
            "--workflow",
            ".github/workflows/sample-image.yaml",
            "--importers",
            "apps/web/demo",
            "--base",
            &base_sha,
            "--event",
            "workflow_dispatch",
        ],
        &[],
    );
    assert_eq!(od.code, 0, "{od:?}");
    assert!(gh_disp.contains("verdict=run\n"), "{gh_disp}");
    // Unsupported glob construct in workflow paths -> fail open verdict=run.
    write(
        repo.join(".github/workflows/sample-image.yaml"),
        SAMPLE_WORKFLOW.replace(
            "'pnpm-workspace.yaml'",
            "'apps/web/**.mjs'\n      - 'pnpm-workspace.yaml'",
        ),
    );
    git(repo, &["add", ".github/workflows/sample-image.yaml"]);
    git(
        repo,
        &["commit", "-q", "-m", "add partial-segment glob workflow"],
    );
    let head_wf = git(repo, &["rev-parse", "HEAD"]);
    write(repo.join("apps/web/unrelated/pkg.json"), "{\"v\":3}\n");
    git(repo, &["add", "apps/web/unrelated/pkg.json"]);
    git(
        repo,
        &["commit", "-q", "-m", "edit unrelated with unsupported glob"],
    );
    let (og, gh_glob) = run_gate(
        repo,
        &[
            "--workflow",
            ".github/workflows/sample-image.yaml",
            "--importers",
            "apps/web/demo",
            "--base",
            &head_wf,
            "--event",
            "pull_request",
        ],
        &[],
    );
    assert_eq!(og.code, 0, "{og:?}");
    assert!(gh_glob.contains("verdict=run\n"), "{gh_glob}");
}

#[test]
fn ignored_optional_dependencies_parses_and_is_part_of_every_closure() {
    // pnpm 10.20+ writes this section when pnpm-workspace.yaml sets
    // `ignoredOptionalDependencies`. It is workspace-wide, so a change to it
    // must change every importer's closure, the same as `overrides`.
    let section = "\nignoredOptionalDependencies:\n  - '@scope/pkg-darwin-arm64'\n  - '@scope/pkg-linux-x64'\n";
    let with = format!("{BASE_LOCK}{section}");
    let changed = with.replace("pkg-linux-x64", "pkg-linux-arm64");

    let base = parse_lockfile(BASE_LOCK).expect("parse base lock");
    let lock_with = parse_lockfile(&with).expect("parse lock with ignoredOptionalDependencies");
    let lock_changed = parse_lockfile(&changed).expect("parse changed lock");
    assert!(
        lock_with
            .ignored_optional_dependencies
            .contains("@scope/pkg-darwin-arm64"),
        "section not captured: {:?}",
        lock_with.ignored_optional_dependencies
    );

    let seeds = ["apps/web/demo"];
    let c_base = extract_closure(&base, &seeds).expect("base closure");
    let c_with = extract_closure(&lock_with, &seeds).expect("closure with section");
    let c_changed = extract_closure(&lock_changed, &seeds).expect("changed closure");
    assert_ne!(c_base, c_with, "adding the section must change the closure");
    assert_ne!(
        c_with, c_changed,
        "editing the section must change the closure"
    );
}

#[test]
fn real_repo_lockfile_parses_and_extracts_backstage_and_gev_closures() {
    let raw = std::fs::read_to_string("pnpm-lock.yaml").expect("read repo pnpm-lock.yaml");
    let lock = parse_lockfile(&raw).expect("parse real repo pnpm-lock.yaml");

    let backstage = extract_closure(
        &lock,
        &[
            ".",
            "apps/web/backstage/packages/app",
            "apps/web/backstage/packages/backend",
        ],
    )
    .expect("extract backstage closure");
    assert!(
        backstage.packages.len() > 200,
        "unexpectedly small backstage closure: {}",
        backstage.packages.len()
    );
    assert!(
        backstage
            .catalogs
            .contains_key(&("backstage".to_string(), "react-router".to_string())),
        "expected catalog:backstage/react-router in backstage closure"
    );

    let gev =
        extract_closure(&lock, &["apps/web/gods-eye-view"]).expect("extract gods-eye-view closure");
    assert!(
        gev.packages.len() > 50,
        "unexpectedly small gev closure: {}",
        gev.packages.len()
    );
    assert!(
        gev.packages.keys().any(|k| k.starts_with("cesium@")),
        "expected cesium in gev closure"
    );
}

#[test]
fn web_image_workflows_wire_gate_fail_open_and_have_matching_paths() {
    for wf_path in [
        ".github/workflows/backstage-image.yaml",
        ".github/workflows/gods-eye-view-image.yaml",
    ] {
        let yaml = std::fs::read_to_string(wf_path).unwrap();
        let push_paths = extract_workflow_paths(&yaml, "push").expect("push paths");
        let pr_paths = extract_workflow_paths(&yaml, "pull_request").expect("pull_request paths");
        assert_eq!(
            push_paths, pr_paths,
            "{wf_path}: push and pull_request paths drifted"
        );
        assert!(
            push_paths.iter().any(|p| p == "pnpm-lock.yaml"),
            "{wf_path}: must trigger on pnpm-lock.yaml"
        );
        assert!(
            push_paths
                .iter()
                .any(|p| p == "tools/ci/src/pnpm_lock_gate/**"),
            "{wf_path}: must trigger on tools/ci/src/pnpm_lock_gate/**"
        );

        let gate_txt = workflow_job_text(&yaml, "gate");
        assert!(
            gate_txt.contains("\n      skip: ${{ steps.gate.outputs.verdict == 'skip' }}\n"),
            "{wf_path}: gate must expose verdict == 'skip':\n{gate_txt}"
        );
        let bad = verdict_fail_open(&yaml, "gate", "skip");
        assert!(bad.is_empty(), "{wf_path}:\n{}", bad.join("\n"));

        for job in workflow_jobs(&yaml) {
            if job.id == "gate" {
                continue;
            }
            assert!(
                names_job(&job.needs, "gate"),
                "{wf_path} job {} must depend on gate",
                job.id
            );
            assert!(
                job.cond.contains("needs.gate.outputs.skip != 'true'"),
                "{wf_path} job {} must check needs.gate.outputs.skip != 'true': {}",
                job.id,
                job.cond
            );
            assert!(
                job.cond.contains("!cancelled()"),
                "{wf_path} job {} must carry !cancelled(): {}",
                job.id,
                job.cond
            );
        }
    }
}
