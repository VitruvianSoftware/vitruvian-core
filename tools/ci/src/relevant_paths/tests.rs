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

//! Black-box tests for //tools/ci:relevant_paths, the docs-only gate every
//! heavy lane (build-test, tidy-check, conformance-check, license-check)
//! reaches through ./.github/actions/changed-paths-gate. Runs the REAL binary
//! against throwaway git repos. Ported case for case from the former
//! relevant-paths_test.sh, which the relevant-paths-test workflow ran.
//!
//! The property this pins is the ignore-regex narrowing license-check depends
//! on. The DEFAULT ignore set treats gitops/ as inert, which is right for the
//! Bazel build lanes but WRONG for license-check: addlicense does not ignore
//! gitops/ (those manifests carry MIT headers) and //tools/license:check is a
//! `bazel run` target with no test, so nothing else would catch an unlicensed
//! gitops file that skipped the required check. The narrowed sets are read
//! out of ci.yaml and tidy-check.yaml rather than copied here: a literal would
//! let a workflow drift to an unsafe set while this kept asserting the old one.

use ci_testkit::{bin, git, write, write_exe, Run, TempDir};
use std::path::{Path, PathBuf};

/// The single-quoted value of the first `key:` line at or after the first
/// line containing `anchor` in a workflow file.
fn quoted_after(workflow: &str, anchor: &str, key: &str) -> String {
    let text = std::fs::read_to_string(workflow).unwrap_or_else(|e| panic!("{workflow}: {e}"));
    let lines: Vec<&str> = text.lines().collect();
    let start = lines
        .iter()
        .position(|l| l.contains(anchor))
        .unwrap_or_else(|| panic!("{workflow}: no line contains {anchor:?}"));
    let want = format!("{key}:");
    let l = lines[start..]
        .iter()
        .find(|l| l.trim_start().starts_with(&want))
        .unwrap_or_else(|| panic!("{workflow}: no {want} after {anchor:?}"));
    let (a, b) = (l.find('\'').unwrap(), l.rfind('\'').unwrap());
    assert!(b > a, "{workflow}: {key} is not single-quoted: {l}");
    l[a + 1..b].to_string()
}

/// How many `ignore-regex:` lines a workflow has. Pinned below, so a lane
/// that starts narrowing its ignore set has to be added to these tests.
fn ignore_regex_lines(workflow: &str) -> Vec<String> {
    std::fs::read_to_string(workflow)
        .unwrap_or_else(|e| panic!("{workflow}: {e}"))
        .lines()
        .filter(|l| l.trim_start().starts_with("ignore-regex:"))
        .map(|l| l.trim().to_string())
        .collect()
}

/// license-check's own gate (merge queue and main).
fn license_regex() -> String {
    quoted_after(
        ".github/workflows/ci.yaml",
        "  license-check:",
        "ignore-regex",
    )
}

/// The PR-only license decision in ci.yaml's `changes` job.
fn license_pr_regex() -> String {
    quoted_after(".github/workflows/ci.yaml", "id: license", "ignore-regex")
}

fn tidy_regex() -> String {
    quoted_after(
        ".github/workflows/tidy-check.yaml",
        "    env:",
        "TIDY_IGNORE",
    )
}

fn tidy_pr_regex() -> String {
    quoted_after(
        ".github/workflows/tidy-check.yaml",
        "    env:",
        "TIDY_IGNORE_PR",
    )
}

const CONFORMANCE: &str = r"^docs/|\.md$";

/// A throwaway repo with a base commit, then one commit changing `files`;
/// returns what the binary prints with BEFORE_REV at the base.
fn verdict(ignore: &str, files: &[&str]) -> String {
    verdict_with(ignore, files, None)
}

/// `verdict`, with PATH replaced when `path` is given (fake or missing grep).
fn verdict_with(ignore: &str, files: &[&str], path: Option<&str>) -> String {
    let dir = TempDir::new();
    let repo = dir.path();
    git(repo, &["init", "-q", "."]);
    for d in ["docs", "gitops/argocd", "vitruvian-tabs/api"] {
        std::fs::create_dir_all(repo.join(d)).unwrap();
    }
    write(repo.join("docs/.keep"), "base\n");
    git(repo, &["add", "-A"]);
    git(repo, &["commit", "-qm", "base"]);
    let base = git(repo, &["rev-parse", "HEAD"]);
    for f in files {
        let p = repo.join(f);
        let mut prior = std::fs::read_to_string(&p).unwrap_or_default();
        prior.push_str("change\n");
        write(&p, prior);
    }
    git(repo, &["add", "-A"]);
    git(repo, &["commit", "-qm", "change"]);
    let mut r = Run::new(&bin("BIN"))
        .cwd(repo)
        .env("BEFORE_REV", &base)
        .env_remove("BASE_REF")
        .env("GIT_CONFIG_NOSYSTEM", "1")
        .env("GIT_CONFIG_GLOBAL", "/dev/null");
    r = if ignore.is_empty() {
        r.env_remove("IGNORE_REGEX")
    } else {
        r.env("IGNORE_REGEX", ignore)
    };
    if let Some(p) = path {
        r = r.env("PATH", p);
    }
    r.go().all()
}

#[track_caller]
fn case(name: &str, expected: bool, ignore: &str, files: &[&str]) {
    let got = verdict(ignore, files);
    let want = format!("relevant={expected}");
    assert!(got.contains(&want), "{name}: expected {want}, got:\n{got}");
}

#[test]
fn default_ignore_set_for_the_bazel_build_lanes() {
    case("docs-only skips", false, "", &["docs/guide.md"]);
    case("markdown-only skips", false, "", &["README.md"]);
    case("gitops-only skips", false, "", &["gitops/argocd/app.yaml"]);
    case("root catalog-info skips", false, "", &["catalog-info.yaml"]);
    case(
        "app catalog-info skips",
        false,
        "",
        &["apps/mobile/vitruvian-remote/catalog-info.yaml"],
    );
    case("root OWNERS skips", false, "", &["OWNERS"]);
    case(
        "app OWNERS skips",
        false,
        "",
        &["apps/cli/vitruvian-devx/OWNERS"],
    );
    case("CODEOWNERS skips", false, "", &[".github/CODEOWNERS"]);
    case(
        "site vitruviansoftware-dev skips",
        false,
        "",
        &["apps/web/vitruviansoftware-dev/downloads.html"],
    );
    case(
        ".agents skills skip",
        false,
        "",
        &[".agents/skills/x/SKILL.yaml"],
    );
    // agent-guard's Antigravity wiring is code: //tools/agent-guard:agent_guard_test reads it.
    case(".agents/hooks.json RUNS", true, "", &[".agents/hooks.json"]);
    case(
        "source change runs",
        true,
        "",
        &["vitruvian-tabs/api/src/index.ts"],
    );
    case(
        "mixed docs+source runs",
        true,
        "",
        &["docs/guide.md", "vitruvian-tabs/api/src/index.ts"],
    );
    case(
        "mixed metadata+source runs",
        true,
        "",
        &["catalog-info.yaml", "vitruvian-tabs/api/src/index.ts"],
    );
}

#[test]
fn license_check_set_never_skips_gitops_or_catalog_info() {
    let re = license_regex();
    case("docs-only skips", false, &re, &["docs/guide.md"]);
    case("markdown-only skips", false, &re, &["README.md"]);
    // THE guard: a gitops manifest needs an MIT header and no other lane checks it.
    case(
        "gitops-only RUNS (no license backstop)",
        true,
        &re,
        &["gitops/argocd/app.yaml"],
    );
    case(
        "catalog-info RUNS (needs license)",
        true,
        &re,
        &["catalog-info.yaml"],
    );
    case(
        "nested docs/ runs (conservative)",
        true,
        &re,
        &["vitruvian-tabs/docs/notes.txt"],
    );
    case(
        "source change runs",
        true,
        &re,
        &["vitruvian-tabs/api/src/index.ts"],
    );
}

#[test]
fn conformance_check_set_never_skips_metadata() {
    case("docs-only skips", false, CONFORMANCE, &["docs/guide.md"]);
    case("markdown-only skips", false, CONFORMANCE, &["README.md"]);
    case(
        "catalog-info RUNS",
        true,
        CONFORMANCE,
        &["catalog-info.yaml"],
    );
    case(
        "app catalog-info RUNS",
        true,
        CONFORMANCE,
        &["apps/mobile/vitruvian-remote/catalog-info.yaml"],
    );
    case("OWNERS RUNS", true, CONFORMANCE, &["OWNERS"]);
}

/// The conformance set is a literal above; make sure it is still the one
/// conformance-check.yaml passes, or the cases above test a stale copy.
#[test]
fn conformance_check_still_passes_that_set() {
    let text = std::fs::read_to_string(".github/workflows/conformance-check.yaml").unwrap();
    assert!(
        text.contains(&format!("ignore-regex: '{CONFORMANCE}'")),
        "conformance-check.yaml no longer passes ignore-regex '{CONFORMANCE}'; update this test with it"
    );
}

#[test]
fn tidy_check_set_skips_only_what_tidy_cannot_change() {
    // Every case holds for the merge-queue set and for the wider PR set.
    for re in [tidy_regex(), tidy_pr_regex()] {
        case("docs markdown skips", false, &re, &["docs/guide.md"]);
        case("root markdown skips", false, &re, &["README.md"]);
        case(
            "gitops yaml skips",
            false,
            &re,
            &["gitops/argocd/platform/buzz/values.yaml"],
        );
        case(
            "docs html skips",
            false,
            &re,
            &["docs/github-relay/register.html"],
        );
        case("OWNERS skips", false, &re, &["OWNERS"]);
        // The case that reached main unformatted (#2886): JSON under docs/.
        case(
            "docs JSON RUNS",
            true,
            &re,
            &["docs/github-relay/app-manifest.json"],
        );
        case(
            "docs JSON beside markdown RUNS",
            true,
            &re,
            &[
                "docs/github-relay/README.md",
                "docs/github-relay/app-manifest.json",
            ],
        );
        case(
            "gitops JSON RUNS",
            true,
            &re,
            &["gitops/argocd/platform/grafana/dashboards/x.json"],
        );
        case(
            "docs shell script RUNS",
            true,
            &re,
            &["docs/runbooks/fix.sh"],
        );
        case("gitops Starlark RUNS", true, &re, &["gitops/defs.bzl"]);
        case("gitops BUILD file RUNS", true, &re, &["gitops/BUILD"]);
        case("docs Python RUNS", true, &re, &["docs/tools/gen.py"]);
        case(
            ".agents TypeScript RUNS",
            true,
            &re,
            &[".agents/skills/x/run.ts"],
        );
        // YAML is only inert INSIDE those folders: a workflow or lockfile is not.
        case(
            "workflow yaml RUNS",
            true,
            &re,
            &[".github/workflows/presubmit.yaml"],
        );
        case("pnpm lockfile RUNS", true, &re, &["pnpm-lock.yaml"]);
        case(
            "source change runs",
            true,
            &re,
            &["vitruvian-tabs/api/src/index.ts"],
        );
    }
}

#[test]
fn ci_yaml_has_exactly_the_two_license_sets() {
    let lines = ignore_regex_lines(".github/workflows/ci.yaml");
    assert_eq!(
        lines.len(),
        2,
        "ci.yaml should narrow only license-check's gate and its PR decision in `changes`; found {lines:?}. Extend these tests for a new one."
    );
}

#[test]
fn tidy_check_gate_reads_the_two_pinned_sets() {
    let lines = ignore_regex_lines(".github/workflows/tidy-check.yaml");
    assert_eq!(
        lines,
        vec!["ignore-regex: ${{ github.event_name == 'pull_request' && env.TIDY_IGNORE_PR || env.TIDY_IGNORE }}".to_string()],
        "tidy-check's gate must pick TIDY_IGNORE_PR on a PR and TIDY_IGNORE otherwise"
    );
}

/// The PR set only ADDS to the queue set: everything the queue skips, a PR
/// skips too, so the two can only differ on the files listed in its comment.
#[test]
fn tidy_pr_set_extends_the_queue_set() {
    let (q, pr) = (tidy_regex(), tidy_pr_regex());
    assert!(
        pr.starts_with(&format!("{q}|")),
        "TIDY_IGNORE_PR must be TIDY_IGNORE plus alternatives:\n  {q}\n  {pr}"
    );
}

#[test]
fn tidy_pr_set_skips_bot_and_swift_prs_only() {
    let re = tidy_pr_regex();
    // Release PRs, as release-please writes them.
    case(
        "release PR skips",
        false,
        &re,
        &[
            "apps/antigravity/plugins/hookify/.release-please-manifest.json",
            "apps/antigravity/plugins/hookify/CHANGELOG.md",
            "apps/antigravity/plugins/hookify/.claude-plugin/plugin.json",
        ],
    );
    case(
        "app release with plist and Swift version skips",
        false,
        &re,
        &[
            "apps/desktop/vitruvian-speaker/.release-please-manifest.json",
            "apps/desktop/vitruvian-speaker/CHANGELOG.md",
            "apps/desktop/vitruvian-speaker/Resources/Info.plist",
            "apps/desktop/vitruvian-speaker/Sources/VitruvianSpeakerCore/Version.swift",
            "apps/extensions/atrium/vitruvian-tv/vitruvian-tool.json",
        ],
    );
    case(
        "site catalog publish skips",
        false,
        &re,
        &[
            "apps/web/vitruviansoftware-dev/tools/catalog/tools.json",
            "apps/web/vitruviansoftware-dev/tools/catalog/tools.json.sig",
        ],
    );
    case(
        "site data yaml skips",
        false,
        &re,
        &["apps/web/vitruviansoftware-dev/_data/downloads.yml"],
    );
    case(
        "Swift-only change skips",
        false,
        &re,
        &["apps/desktop/vitruvian-atrium/Sources/VitruvianAtrium/main.swift"],
    );
    // What tidy DOES read keeps running.
    case(
        "package.json RUNS (js gazelle reads it)",
        true,
        &re,
        &["apps/antigravity/plugins/hookify/package.json"],
    );
    case(
        "tsconfig RUNS",
        true,
        &re,
        &["apps/suites/vitruvian-tabs/web/tsconfig.json"],
    );
    case(
        "top-level catalog JSON RUNS (prettier formats it)",
        true,
        &re,
        &["catalog/tools.json"],
    );
    case(
        "other JSON under apps RUNS",
        true,
        &re,
        &["apps/suites/vitruvian-tabs/web/src/data.json"],
    );
    case(
        "app CSS RUNS",
        true,
        &re,
        &["apps/suites/vitruvian-tabs/web/src/app.css"],
    );
    case(
        "Cargo.toml RUNS",
        true,
        &re,
        &["apps/mcp/vitruvian-slack-mcp/rs/Cargo.toml"],
    );
    case(
        "BUILD beside a release RUNS",
        true,
        &re,
        &[
            "apps/mobile/vitruvian-remote/.release-please-manifest.json",
            "apps/mobile/vitruvian-remote/BUILD",
        ],
    );
    case(
        "Rust version file RUNS",
        true,
        &re,
        &["apps/mcp/vitruvian-slack-mcp/rs/src/server.rs"],
    );
}

#[test]
fn license_pr_set_skips_only_files_neither_tool_reads() {
    let re = license_pr_regex();
    case(
        "release PR skips",
        false,
        &re,
        &[
            "apps/antigravity/plugins/hookify/.release-please-manifest.json",
            "apps/antigravity/plugins/hookify/CHANGELOG.md",
            "apps/antigravity/plugins/hookify/.claude-plugin/plugin.json",
            "apps/antigravity/plugins/hookify/package.json",
        ],
    );
    case(
        "site catalog publish skips",
        false,
        &re,
        &[
            "apps/web/vitruviansoftware-dev/tools/catalog/tools.json",
            "apps/web/vitruviansoftware-dev/tools/catalog/tools.json.sig",
        ],
    );
    case(
        "plist skips",
        false,
        &re,
        &["apps/desktop/vitruvian-speaker/Resources/Info.plist"],
    );
    case("docs skips", false, &re, &["docs/guide.md"]);
    // addlicense headers YAML, and :verify reads Swift and LICENSE files.
    case(
        "site data yaml RUNS (addlicense heads YAML)",
        true,
        &re,
        &["apps/web/vitruviansoftware-dev/_data/downloads.yml"],
    );
    case(
        "gitops-only RUNS (no license backstop)",
        true,
        &re,
        &["gitops/argocd/app.yaml"],
    );
    case(
        "Swift RUNS (:verify reads it)",
        true,
        &re,
        &["apps/desktop/vitruvian-speaker/Sources/VitruvianSpeakerCore/Version.swift"],
    );
    case(
        "LICENSE RUNS",
        true,
        &re,
        &["apps/cli/vitruvian-devx/LICENSE"],
    );
    case(
        "license tool RUNS",
        true,
        &re,
        &["tools/license/src/lib.rs"],
    );
    case(
        "JSON beside source RUNS",
        true,
        &re,
        &["catalog/tools.json", "vitruvian-tabs/api/src/index.ts"],
    );
}

/// The globs listed under `header` (a line ending in `:`), up to the next line
/// indented no deeper than it. Comments are skipped.
fn globs_under(workflow: &str, header: &str) -> Vec<String> {
    let text = std::fs::read_to_string(workflow).unwrap_or_else(|e| panic!("{workflow}: {e}"));
    let lines: Vec<&str> = text.lines().collect();
    let i = lines
        .iter()
        .position(|l| l.trim_end() == header)
        .unwrap_or_else(|| panic!("{workflow}: no line {header:?}"));
    let indent = header.len() - header.trim_start().len();
    let mut out = Vec::new();
    for l in &lines[i + 1..] {
        let t = l.trim_start();
        if t.is_empty() || t.starts_with('#') {
            continue;
        }
        if l.len() - t.len() <= indent {
            break;
        }
        if let Some(g) = t.strip_prefix("- ") {
            out.push(g.trim().trim_matches('\'').to_string());
        }
    }
    out
}

#[track_caller]
fn lists(workflow: &str, header: &str, want: &[&str]) {
    let got = globs_under(workflow, header);
    for w in want {
        assert!(
            got.iter().any(|g| g == w),
            "{workflow} {header}: missing {w:?}, a file this check reads, so a PR changing only it would skip the check. Got {got:?}"
        );
    }
}

/// Each PR-only skip filter must list what its check reads beyond the obvious
/// sources. Each entry here is one a review found missing (#4854): the check
/// reads it, so a PR changing only it must still run the check.
#[test]
fn pr_skip_filters_list_every_input_their_checks_read() {
    // lint-naming's unit test runs under every rc file .bazelrc imports.
    lists(
        ".github/workflows/ci.yaml",
        "            lintnaming:",
        &[
            "tools/lint-naming/**",
            ".bazelrc",
            "tools/*.bazelrc",
            "MODULE.bazel",
        ],
    );
    // //tools/ci:go_test_lanes links //tools/shell-compat:shell_compat.
    lists(
        ".github/workflows/ci.yaml",
        "            golanes:",
        &[
            "**/*_test.go",
            "**/BUILD",
            "tools/ci/src/go_test_lanes/**",
            "tools/shell-compat/**",
        ],
    );
    // The required lint checks that moved behind `changes`: each lists what
    // it reads, and every tool built by build-ci-tool or installed by
    // install-pinned-tool brings tools/ci/src, tools/shell-compat and the pin.
    lists(
        ".github/workflows/ci.yaml",
        "            gitopsvalidate:",
        &[
            "gitops/**",
            "tools/gitops/appset-render/**",
            "go.mod",
            "tools/ci/src/**",
            "tools/shell-compat/**",
            "tools/tools.lock.json",
        ],
    );
    lists(
        ".github/workflows/ci.yaml",
        "            migrationsafety:",
        &[
            "apps/suites/vitruvian-tabs/api/prisma/**",
            "tools/ci/src/**",
            "tools/shell-compat/**",
        ],
    );
    lists(
        ".github/workflows/ci.yaml",
        "            actionlint:",
        &[
            ".github/workflows/**",
            ".github/actions/**",
            ".github/actionlint.yaml",
            "apps/cli/vitruvian-devx/internal/scaffold/templates/**",
            "tools/ci/src/**",
            "tools/tools.lock.json",
        ],
    );
    lists(
        ".github/workflows/ci.yaml",
        "            osvscan:",
        &[
            "tools/osv-scan/**",
            "packages/jq/**",
            "packages/pycompat/vitruvian-pycompat/**",
            "tools/ci/src/**",
            "tools/tools.lock.json",
        ],
    );
    // promtool is installed by install-pinned-tool, checked against tools.lock.json.
    lists(
        ".github/workflows/chart-render.yaml",
        "    paths:",
        &[
            "gitops/**",
            "**/deploy/chart/**",
            "tools/ci/**",
            "tools/tools.lock.json",
        ],
    );
}

/// No BEFORE_REV and no BASE_REF at all: it must run the heavy work.
#[test]
fn with_no_diff_base_it_runs() {
    let dir = TempDir::new();
    let o = Run::new(&bin("BIN"))
        .cwd(dir.path())
        .env("BEFORE_REV", "")
        .env("BASE_REF", "")
        .go();
    assert!(
        o.all().contains("relevant=true"),
        "no diff base must run: {o:?}"
    );
}

#[test]
fn an_unresolvable_before_rev_runs() {
    let dir = TempDir::new();
    git(dir.path(), &["init", "-q", "."]);
    let o = Run::new(&bin("BIN"))
        .cwd(dir.path())
        .env("BEFORE_REV", "0000000000000000000000000000000000000000")
        .env_remove("BASE_REF")
        .go();
    assert!(
        o.all().contains("relevant=true"),
        "a zero before-rev must run: {o:?}"
    );
}

#[test]
fn the_verdict_goes_to_github_output() {
    let dir = TempDir::new();
    let gho = dir.join("gho");
    let o = Run::new(&bin("BIN"))
        .cwd(dir.path())
        .env("BEFORE_REV", "")
        .env("BASE_REF", "")
        .env("GITHUB_OUTPUT", &gho)
        .go();
    assert_eq!(o.code, 0, "{o:?}");
    assert_eq!(ci_testkit::read(&gho), "relevant=true\n");
}

/// Workflows reach the tool through ./.github/actions/changed-paths-gate,
/// which owns the "which commit do I diff against" expressions for every
/// event. A workflow that builds or runs it directly has to copy those
/// expressions, and a copy can go stale or miss an event without anything
/// failing.
#[test]
fn no_workflow_runs_it_directly() {
    let mut direct = Vec::new();
    for e in std::fs::read_dir(".github/workflows").unwrap().flatten() {
        let p = e.path();
        let text = std::fs::read_to_string(&p).unwrap();
        for (n, l) in text.lines().enumerate() {
            if l.trim_start().starts_with('#') {
                continue;
            }
            if l.contains("tool: relevant_paths") || l.contains("relevant-paths.sh") {
                direct.push(format!("{}:{}: {}", p.display(), n + 1, l.trim()));
            }
        }
    }
    assert!(
        direct.is_empty(),
        "use ./.github/actions/changed-paths-gate instead of running the rule directly:\n{}",
        direct.join("\n")
    );
    let gate = std::fs::read_to_string(".github/actions/changed-paths-gate/action.yml").unwrap();
    assert!(
        gate.contains("tool: relevant_paths"),
        "the changed-paths gate no longer builds relevant_paths"
    );
}

// --- counting the changed files can fail: any doubt is "run" -------------
//
// The shell script ran in all of these: `[ "" -eq 0 ]` errors, so it fell
// through to "run". The first Rust port counted every grep failure as zero
// changed files and said skip (#4173 review).

/// A directory holding only `git` (a link to the real one), so the binary
/// can diff but finds no grep.
fn path_without_grep(tmp: &TempDir) -> String {
    let real_git = std::env::var("PATH")
        .unwrap_or_default()
        .split(':')
        .map(|d| Path::new(d).join("git"))
        .find(|p| p.is_file())
        .expect("git on PATH");
    let dir: PathBuf = tmp.join("only-git");
    std::fs::create_dir_all(&dir).unwrap();
    std::os::unix::fs::symlink(real_git, dir.join("git")).unwrap();
    dir.display().to_string()
}

/// A fake grep first on PATH, the real tools after it.
fn path_with_fake_grep(tmp: &TempDir, body: &str) -> String {
    let dir = tmp.join("fake-grep");
    write_exe(dir.join("grep"), format!("#!/bin/sh\n{body}\n"));
    ci_testkit::path_with(&dir)
}

#[track_caller]
fn runs_with_reason(got: &str, what: &str) {
    assert!(
        got.contains("relevant=true"),
        "{what} must run, got:\n{got}"
    );
    assert!(
        got.contains("could not count changed files"),
        "{what}: say why it ran, got:\n{got}"
    );
}

#[test]
fn an_invalid_ignore_regex_runs() {
    for bad in ["(", "[z-a]"] {
        let got = verdict(bad, &["vitruvian-tabs/api/src/index.ts"]);
        runs_with_reason(&got, &format!("invalid IGNORE_REGEX {bad:?}"));
        // A docs-only diff too: the bad regex must not be read as "all ignored".
        let got = verdict(bad, &["docs/guide.md"]);
        runs_with_reason(
            &got,
            &format!("invalid IGNORE_REGEX {bad:?} on a docs diff"),
        );
    }
}

#[test]
fn no_grep_on_path_runs() {
    let tmp = TempDir::new();
    let got = verdict_with("", &["docs/guide.md"], Some(&path_without_grep(&tmp)));
    runs_with_reason(&got, "no grep on PATH");
}

#[test]
fn grep_exiting_non_zero_runs() {
    for (what, body) in [
        (
            "grep exits 2 with no count",
            "echo 'grep: broken' >&2; exit 2",
        ),
        ("grep exits 2 after printing 0", "echo 0; exit 2"),
        ("grep killed by a signal", "kill -9 $$"),
        ("grep exits 1 with no count", "exit 1"),
        (
            "grep prints something that is not a count",
            "echo nope; exit 0",
        ),
    ] {
        let tmp = TempDir::new();
        let got = verdict_with(
            "",
            &["docs/guide.md"],
            Some(&path_with_fake_grep(&tmp, body)),
        );
        runs_with_reason(&got, what);
    }
}

/// The other side: a grep that answers "0 lines outside the set" (exit 1,
/// as real grep -c does) is still a skip, so the fix did not make every
/// diff run.
#[test]
fn a_real_zero_count_still_skips() {
    let tmp = TempDir::new();
    let got = verdict_with(
        "",
        &["docs/guide.md"],
        Some(&path_with_fake_grep(&tmp, "cat >/dev/null; echo 0; exit 1")),
    );
    assert!(
        got.contains("relevant=false"),
        "a counted zero must skip, got:\n{got}"
    );
}
