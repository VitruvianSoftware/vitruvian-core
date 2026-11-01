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

use ci_testkit::{bin, git, write, Run, TempDir};

/// The one `ignore-regex: '...'` value in a workflow file; panics unless there
/// is exactly one, so a second narrowed lane has to be added here too.
fn ignore_regex(workflow: &str) -> String {
    let text = std::fs::read_to_string(workflow).unwrap_or_else(|e| panic!("{workflow}: {e}"));
    let found: Vec<&str> = text
        .lines()
        .filter(|l| l.trim_start().starts_with("ignore-regex:"))
        .collect();
    assert_eq!(
        found.len(),
        1,
        "expected exactly 1 ignore-regex in {workflow}, found {}. If another lane now narrows its ignore set too, extend this test to cover it.",
        found.len()
    );
    let l = found[0];
    let (a, b) = (l.find('\'').unwrap(), l.rfind('\'').unwrap());
    assert!(
        b > a,
        "{workflow}: the ignore-regex is not single-quoted: {l}"
    );
    l[a + 1..b].to_string()
}

fn license_regex() -> String {
    ignore_regex(".github/workflows/ci.yaml")
}

fn tidy_regex() -> String {
    ignore_regex(".github/workflows/tidy-check.yaml")
}

const CONFORMANCE: &str = r"^docs/|\.md$";

/// A throwaway repo with a base commit, then one commit changing `files`;
/// returns what the binary prints with BEFORE_REV at the base.
fn verdict(ignore: &str, files: &[&str]) -> String {
    let dir = TempDir::new();
    let repo = dir.path();
    git(repo, &["init", "-q", "."]);
    for d in ["docs", "gitops/argocd", "tabula/api"] {
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
        &["apps/mobile/android-remote/catalog-info.yaml"],
    );
    case("root OWNERS skips", false, "", &["OWNERS"]);
    case("app OWNERS skips", false, "", &["apps/cli/devx/OWNERS"]);
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
    case("source change runs", true, "", &["tabula/api/src/index.ts"]);
    case(
        "mixed docs+source runs",
        true,
        "",
        &["docs/guide.md", "tabula/api/src/index.ts"],
    );
    case(
        "mixed metadata+source runs",
        true,
        "",
        &["catalog-info.yaml", "tabula/api/src/index.ts"],
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
        &["tabula/docs/notes.txt"],
    );
    case(
        "source change runs",
        true,
        &re,
        &["tabula/api/src/index.ts"],
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
        &["apps/mobile/android-remote/catalog-info.yaml"],
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
    let re = tidy_regex();
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
        &["tabula/api/src/index.ts"],
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
