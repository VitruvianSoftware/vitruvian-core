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

//! Black-box integration tests for `//tools/ci:image_bump_changelog`.
//! Runs the compiled binary against a throwaway git repo and a fake `curl` on
//! PATH — zero network access.

use ci_testkit::{
    assert_has, assert_lacks, bin, commit_file, git, git_init, write, write_exe, Run, TempDir,
};
use std::path::Path;

fn pad64(ch: char) -> String {
    std::iter::repeat(ch).take(64).collect()
}

fn setup_fake_curl(dir: &Path, fixtures: &Path) {
    let script = format!(
        r#"#!/bin/sh
url=""
for a in "$@"; do
  url="$a"
done
map="{fixtures}/map.tsv"
while IFS='	' read -r pat mode target; do
  [ -z "$pat" ] && continue
  case "$url" in
    *"$pat"*)
      if [ "$mode" = "fail" ]; then
        echo "curl: (22) The requested URL returned error: $target" >&2
        exit 22
      fi
      cat "{fixtures}/$target"
      exit 0
      ;;
  esac
done < "$map"
echo "unexpected url: $url" >&2
exit 99
"#,
        fixtures = fixtures.display()
    );
    write_exe(dir.join("curl"), script);
}

#[test]
fn usage_without_args_exits_2() {
    let bin = bin("BIN");
    let dir = TempDir::new();
    let o = Run::new(&bin).cwd(dir.path()).go();
    assert_eq!(o.code, 2, "stderr={}", o.stderr);
    assert_has(&o.stderr, "image-bump-changelog: usage:", "usage stderr");
    assert_eq!(o.stdout, "", "no stdout on usage error");
}

#[test]
fn local_range_lists_app_commits_and_counts_shared_inputs() {
    let bin = bin("BIN");
    let tmp = TempDir::new();
    let repo = tmp.join("repo");
    git_init(&repo);

    let old_sha = commit_file(
        &repo,
        "apps/mcp/vitruvian-slack-mcp/main.rs",
        "v1\n",
        "init app (#100)",
    );
    let _app_sha = commit_file(
        &repo,
        "apps/mcp/vitruvian-slack-mcp/main.rs",
        "v2\n",
        "feat(slack): add thread tool (#101)",
    );
    let _shared_sha = commit_file(
        &repo,
        "MODULE.bazel",
        "rust 1.98.1\n",
        "chore(deps): rust 1.98.1 (#102)",
    );
    let new_sha = commit_file(&repo, "docs/note.md", "typo fix\n", "docs: fix typo (#103)");

    let d_old = format!("sha256:{}", pad64('1'));
    let d_new = format!("sha256:{}", pad64('2'));
    let d_att = format!("sha256:{}", pad64('a'));
    let d_p_old = format!("sha256:{}", pad64('b'));
    let d_p_new = format!("sha256:{}", pad64('c'));
    let d_cfg_old = format!("sha256:{}", pad64('d'));
    let d_cfg_new = format!("sha256:{}", pad64('e'));

    let fix = tmp.join("fixtures");
    write(fix.join("token.json"), r#"{"token":"anon-tok"}"#);
    write(
        fix.join("idx_old.json"),
        format!(
            r#"{{"manifests":[{{"digest":"{d_att}","platform":{{"os":"unknown","architecture":"unknown"}},"annotations":{{"vnd.docker.reference.type":"attestation-manifest"}}}},{{"digest":"{d_p_old}","platform":{{"os":"linux","architecture":"amd64"}}}}]}}"#
        ),
    );
    write(
        fix.join("idx_new.json"),
        format!(
            r#"{{"manifests":[{{"digest":"{d_p_new}","platform":{{"os":"linux","architecture":"amd64"}}}}]}}"#
        ),
    );
    write(
        fix.join("plat_old.json"),
        format!(r#"{{"config":{{"digest":"{d_cfg_old}"}}}}"#),
    );
    write(
        fix.join("plat_new.json"),
        format!(r#"{{"config":{{"digest":"{d_cfg_new}"}}}}"#),
    );
    write(
        fix.join("cfg_old.json"),
        format!(r#"{{"config":{{"Labels":{{"org.opencontainers.image.revision":"{old_sha}"}}}}}}"#),
    );
    write(
        fix.join("cfg_new.json"),
        format!(r#"{{"config":{{"Labels":{{"org.opencontainers.image.revision":"{new_sha}"}}}}}}"#),
    );
    write(
        fix.join("map.tsv"),
        format!(
            "/token?\tok\ttoken.json\n\
             /manifests/{d_old}\tok\tidx_old.json\n\
             /manifests/{d_new}\tok\tidx_new.json\n\
             /manifests/{d_p_old}\tok\tplat_old.json\n\
             /manifests/{d_p_new}\tok\tplat_new.json\n\
             /blobs/{d_cfg_old}\tok\tcfg_old.json\n\
             /blobs/{d_cfg_new}\tok\tcfg_new.json\n"
        ),
    );

    let fakebin = tmp.join("bin");
    setup_fake_curl(&fakebin, &fix);

    let o = Run::new(&bin)
        .cwd(&repo)
        .path_first(&fakebin)
        .args([
            "--image",
            "ghcr.io/vitruviansoftware/vitruvian-slack-mcp",
            "--old-digest",
            &d_old,
            "--new-digest",
            &d_new,
            "--path",
            "apps/mcp/vitruvian-slack-mcp",
            "--shared-path",
            "MODULE.bazel",
        ])
        .go();

    assert_eq!(o.code, 0, "stderr={}\nstdout={}", o.stderr, o.stdout);
    let old7 = &old_sha[..7];
    let new7 = &new_sha[..7];
    assert_has(
        &o.stdout,
        &format!("Built from [`{old7}..{new7}`](https://github.com/VitruvianSoftware/vitruvian-core/compare/{old_sha}...{new_sha})."),
        "compare header",
    );
    assert_has(
        &o.stdout,
        "feat(slack): add thread tool (#101)",
        "app commit",
    );
    assert_lacks(
        &o.stdout,
        "docs: fix typo (#103)",
        "unrelated commit omitted",
    );
    assert_lacks(
        &o.stdout,
        "(#102)",
        "shared commit not duplicated in app list",
    );
    assert_has(
        &o.stdout,
        "1 other commit in this range changed shared build inputs.",
        "shared count line",
    );

    // Also verify --values-file against origin/main in the same repo.
    commit_file(
        &repo,
        "gitops/argocd/platform/mcp-slack/values.yaml",
        &format!("image:\n  digest: \"main@{d_old}\"\n"),
        "old values",
    );
    let main_tip = git(&repo, &["rev-parse", "HEAD"]);
    git(
        &repo,
        &["update-ref", "refs/remotes/origin/main", &main_tip],
    );
    write(
        repo.join("gitops/argocd/platform/mcp-slack/values.yaml"),
        format!("image:\n  digest: \"main@{d_new}\"\n"),
    );

    let o2 = Run::new(&bin)
        .cwd(&repo)
        .path_first(&fakebin)
        .args([
            "--image",
            "ghcr.io/vitruviansoftware/vitruvian-slack-mcp",
            "--values-file",
            "gitops/argocd/platform/mcp-slack/values.yaml",
            "--path",
            "apps/mcp/vitruvian-slack-mcp",
            "--shared-path",
            "MODULE.bazel",
        ])
        .go();
    assert_eq!(o2.code, 0, "stderr={}", o2.stderr);
    assert_eq!(
        o2.stdout, o.stdout,
        "--values-file output must match explicit digests"
    );
}

#[test]
fn missing_old_revision_label_is_reported_honestly() {
    let bin = bin("BIN");
    let tmp = TempDir::new();
    let repo = tmp.join("repo");
    let new_sha = git_init(&repo);

    let d_old = format!("sha256:{}", pad64('3'));
    let d_new = format!("sha256:{}", pad64('4'));
    let d_cfg_old = format!("sha256:{}", pad64('5'));
    let d_cfg_new = format!("sha256:{}", pad64('6'));

    let fix = tmp.join("fixtures");
    write(fix.join("token.json"), r#"{"token":"tok"}"#);
    write(
        fix.join("m_old.json"),
        format!(r#"{{"config":{{"digest":"{d_cfg_old}"}}}}"#),
    );
    write(
        fix.join("m_new.json"),
        format!(r#"{{"config":{{"digest":"{d_cfg_new}"}}}}"#),
    );
    write(fix.join("cfg_old.json"), r#"{"config":{"Labels":{}}}"#);
    write(
        fix.join("cfg_new.json"),
        format!(r#"{{"config":{{"Labels":{{"org.opencontainers.image.revision":"{new_sha}"}}}}}}"#),
    );
    write(
        fix.join("tags_empty.json"),
        r#"{"name":"vitruviansoftware/backstage","tags":["latest"]}"#,
    );
    write(
        fix.join("map.tsv"),
        format!(
            "/token?\tok\ttoken.json\n\
             /manifests/{d_old}\tok\tm_old.json\n\
             /manifests/{d_new}\tok\tm_new.json\n\
             /blobs/{d_cfg_old}\tok\tcfg_old.json\n\
             /blobs/{d_cfg_new}\tok\tcfg_new.json\n\
             /tags/list\tok\ttags_empty.json\n"
        ),
    );

    let fakebin = tmp.join("bin");
    setup_fake_curl(&fakebin, &fix);

    let o = Run::new(&bin)
        .cwd(&repo)
        .path_first(&fakebin)
        .args([
            "--image",
            "ghcr.io/vitruviansoftware/backstage",
            "--old-digest",
            &d_old,
            "--new-digest",
            &d_new,
            "--path",
            "apps/web/backstage",
        ])
        .go();

    assert_eq!(o.code, 0, "stderr={}", o.stderr);
    assert_has(
        &o.stdout,
        "previous revision unknown",
        "old revision fallback",
    );
    assert_has(&o.stdout, &new_sha[..7], "new revision shown");
}

#[test]
fn upstream_mode_handles_compare_and_unlabeled_and_errors() {
    let bin = bin("BIN");
    let tmp = TempDir::new();

    let d_old = format!("sha256:{}", pad64('7'));
    let d_new = format!("sha256:{}", pad64('8'));
    let d_unlabeled = format!("sha256:{}", pad64('9'));
    let d_cfg_old = format!("sha256:{}", pad64('c'));
    let d_cfg_new = format!("sha256:{}", pad64('d'));
    let d_cfg_unl = format!("sha256:{}", pad64('e'));

    let rev_old = "1fb33e4545660196d4c863daf70e1d3bc245f164";
    let rev_new = "2fb33e4545660196d4c863daf70e1d3bc245f164";

    let fix = tmp.join("fixtures");
    write(fix.join("token.json"), r#"{"token":"tok"}"#);
    write(
        fix.join("m_old.json"),
        format!(r#"{{"config":{{"digest":"{d_cfg_old}"}}}}"#),
    );
    write(
        fix.join("m_new.json"),
        format!(r#"{{"config":{{"digest":"{d_cfg_new}"}}}}"#),
    );
    write(
        fix.join("m_unl.json"),
        format!(r#"{{"config":{{"digest":"{d_cfg_unl}"}}}}"#),
    );
    write(
        fix.join("cfg_old.json"),
        format!(r#"{{"config":{{"Labels":{{"org.opencontainers.image.revision":"{rev_old}"}}}}}}"#),
    );
    write(
        fix.join("cfg_new.json"),
        format!(r#"{{"config":{{"Labels":{{"org.opencontainers.image.revision":"{rev_new}"}}}}}}"#),
    );
    write(fix.join("cfg_unl.json"), r#"{"config":{"Labels":{}}}"#);
    write(
        fix.join("tags_empty.json"),
        r#"{"name":"block/buzz","tags":["main","latest"]}"#,
    );
    write(
        fix.join("compare.json"),
        format!(
            r#"{{"total_commits":1,"commits":[{{"sha":"{rev_new}","commit":{{"message":"feat: upstream change (#12)"}}}}]}}"#
        ),
    );
    write(
        fix.join("map.tsv"),
        format!(
            "/token?\tok\ttoken.json\n\
             /manifests/{d_old}\tok\tm_old.json\n\
             /manifests/{d_new}\tok\tm_new.json\n\
             /manifests/{d_unlabeled}\tok\tm_unl.json\n\
             /blobs/{d_cfg_old}\tok\tcfg_old.json\n\
             /blobs/{d_cfg_new}\tok\tcfg_new.json\n\
             /blobs/{d_cfg_unl}\tok\tcfg_unl.json\n\
             /tags/list\tok\ttags_empty.json\n\
             api.github.com/repos/block/buzz/compare/\tok\tcompare.json\n"
        ),
    );

    let fakebin = tmp.join("bin");
    setup_fake_curl(&fakebin, &fix);

    let o = Run::new(&bin)
        .cwd(tmp.path())
        .path_first(&fakebin)
        .args([
            "--image",
            "ghcr.io/block/buzz",
            "--old-digest",
            &d_old,
            "--new-digest",
            &d_new,
            "--repo",
            "block/buzz",
            "--upstream",
        ])
        .go();
    assert_eq!(o.code, 0, "stderr={}", o.stderr);
    assert_has(
        &o.stdout,
        &format!("https://github.com/block/buzz/compare/{rev_old}...{rev_new}"),
        "upstream compare link",
    );
    assert_has(&o.stdout, "feat: upstream change (#12)", "upstream commit");

    // Unlabeled upstream new image
    let o_unl = Run::new(&bin)
        .cwd(tmp.path())
        .path_first(&fakebin)
        .args([
            "--image",
            "ghcr.io/block/buzz",
            "--old-digest",
            &d_old,
            "--new-digest",
            &d_unlabeled,
            "--repo",
            "block/buzz",
            "--upstream",
        ])
        .go();
    assert_eq!(o_unl.code, 0, "stderr={}", o_unl.stderr);
    assert_has(
        &o_unl.stdout,
        "Upstream revision isn't recorded",
        "unlabeled upstream",
    );

    // Registry error -> non-zero exit + reason on stderr, empty stdout
    let d_missing = format!("sha256:{}", pad64('f'));
    let o_err = Run::new(&bin)
        .cwd(tmp.path())
        .path_first(&fakebin)
        .args([
            "--image",
            "ghcr.io/block/buzz",
            "--old-digest",
            &d_old,
            "--new-digest",
            &d_missing,
            "--repo",
            "block/buzz",
            "--upstream",
        ])
        .go();
    assert_eq!(o_err.code, 1, "stdout={}", o_err.stdout);
    assert_eq!(o_err.stdout, "", "empty stdout on failure");
    assert_has(
        &o_err.stderr,
        "image-bump-changelog:",
        "error prefix on stderr",
    );
}

#[test]
fn tag_fallback_resolves_commit_from_matching_40_hex_tag() {
    let bin = bin("BIN");
    let tmp = TempDir::new();
    let repo = tmp.join("repo");
    git_init(&repo);

    let old_sha = commit_file(
        &repo,
        "apps/web/gods-eye-view/index.ts",
        "v1\n",
        "init (#200)",
    );
    let _app_sha = commit_file(
        &repo,
        "apps/web/gods-eye-view/index.ts",
        "v2\n",
        "feat(gev): show cluster view (#201)",
    );
    let new_sha = commit_file(&repo, "MODULE.bazel", "bump\n", "chore(deps): bump (#202)");

    let d_old = format!("sha256:{}", pad64('1'));
    let d_new = format!("sha256:{}", pad64('2'));
    let d_other = format!("sha256:{}", pad64('9'));
    let d_cfg_old = format!("sha256:{}", pad64('a'));
    let d_cfg_new = format!("sha256:{}", pad64('b'));
    let other_sha = "0000000000000000000000000000000000000001";

    let fix = tmp.join("fixtures");
    write(fix.join("token.json"), r#"{"token":"tok"}"#);
    write(
        fix.join("m_old.json"),
        format!(r#"{{"config":{{"digest":"{d_cfg_old}"}}}}"#),
    );
    write(
        fix.join("m_new.json"),
        format!(r#"{{"config":{{"digest":"{d_cfg_new}"}}}}"#),
    );
    write(fix.join("cfg_empty.json"), r#"{"config":{"Labels":{}}}"#);
    write(
        fix.join("tags.json"),
        format!(
            r#"{{"name":"vitruviansoftware/gods-eye-view","tags":["latest","buildcache","{other_sha}","{old_sha}","{new_sha}"]}}"#
        ),
    );
    write(
        fix.join("head_old.txt"),
        format!("HTTP/2 200\r\ndocker-content-digest: {d_old}\r\n\r\n"),
    );
    write(
        fix.join("head_new.txt"),
        format!("HTTP/2 200\r\ndocker-content-digest: {d_new}\r\n\r\n"),
    );
    write(
        fix.join("head_other.txt"),
        format!("HTTP/2 200\r\ndocker-content-digest: {d_other}\r\n\r\n"),
    );
    write(
        fix.join("map.tsv"),
        format!(
            "/token?\tok\ttoken.json\n\
             /manifests/{d_old}\tok\tm_old.json\n\
             /manifests/{d_new}\tok\tm_new.json\n\
             /blobs/{d_cfg_old}\tok\tcfg_empty.json\n\
             /blobs/{d_cfg_new}\tok\tcfg_empty.json\n\
             /tags/list\tok\ttags.json\n\
             /manifests/{old_sha}\tok\thead_old.txt\n\
             /manifests/{new_sha}\tok\thead_new.txt\n\
             /manifests/{other_sha}\tok\thead_other.txt\n"
        ),
    );

    let fakebin = tmp.join("bin");
    setup_fake_curl(&fakebin, &fix);

    let o = Run::new(&bin)
        .cwd(&repo)
        .path_first(&fakebin)
        .args([
            "--image",
            "ghcr.io/vitruviansoftware/gods-eye-view",
            "--old-digest",
            &d_old,
            "--new-digest",
            &d_new,
            "--path",
            "apps/web/gods-eye-view",
            "--shared-path",
            "MODULE.bazel",
        ])
        .go();

    assert_eq!(o.code, 0, "stderr={}\nstdout={}", o.stderr, o.stdout);
    let old7 = &old_sha[..7];
    let new7 = &new_sha[..7];
    assert_has(
        &o.stdout,
        &format!("Built from [`{old7}..{new7}`](https://github.com/VitruvianSoftware/vitruvian-core/compare/{old_sha}...{new_sha})."),
        "compare header resolved via 40-hex tags",
    );
    assert_has(
        &o.stdout,
        "feat(gev): show cluster view (#201)",
        "app commit resolved via 40-hex tag range",
    );
    assert_has(
        &o.stdout,
        "1 other commit in this range changed shared build inputs.",
        "shared count line",
    );
}

#[test]
fn tag_fallback_reports_unknown_when_only_non_matching_tags_exist() {
    let bin = bin("BIN");
    let tmp = TempDir::new();
    let repo = tmp.join("repo");
    let new_sha = git_init(&repo);

    let d_old = format!("sha256:{}", pad64('3'));
    let d_new = format!("sha256:{}", pad64('4'));
    let d_other = format!("sha256:{}", pad64('8'));
    let d_cfg_old = format!("sha256:{}", pad64('5'));
    let d_cfg_new = format!("sha256:{}", pad64('6'));

    let tag_a = "1111111111111111111111111111111111111111";
    let tag_b = "2222222222222222222222222222222222222222";

    let fix = tmp.join("fixtures");
    write(fix.join("token.json"), r#"{"token":"tok"}"#);
    write(
        fix.join("m_old.json"),
        format!(r#"{{"config":{{"digest":"{d_cfg_old}"}}}}"#),
    );
    write(
        fix.join("m_new.json"),
        format!(r#"{{"config":{{"digest":"{d_cfg_new}"}}}}"#),
    );
    write(fix.join("cfg_old.json"), r#"{"config":{"Labels":{}}}"#);
    write(
        fix.join("cfg_new.json"),
        format!(r#"{{"config":{{"Labels":{{"org.opencontainers.image.revision":"{new_sha}"}}}}}}"#),
    );
    write(
        fix.join("tags.json"),
        format!(r#"{{"name":"vitruviansoftware/backstage","tags":["{tag_a}","{tag_b}"]}}"#),
    );
    write(
        fix.join("head_other.txt"),
        format!("HTTP/2 200\r\ndocker-content-digest: {d_other}\r\n\r\n"),
    );
    write(
        fix.join("map.tsv"),
        format!(
            "/token?\tok\ttoken.json\n\
             /manifests/{d_old}\tok\tm_old.json\n\
             /manifests/{d_new}\tok\tm_new.json\n\
             /blobs/{d_cfg_old}\tok\tcfg_old.json\n\
             /blobs/{d_cfg_new}\tok\tcfg_new.json\n\
             /tags/list\tok\ttags.json\n\
             /manifests/{tag_a}\tok\thead_other.txt\n\
             /manifests/{tag_b}\tfail\t404\n"
        ),
    );

    let fakebin = tmp.join("bin");
    setup_fake_curl(&fakebin, &fix);

    let o = Run::new(&bin)
        .cwd(&repo)
        .path_first(&fakebin)
        .args([
            "--image",
            "ghcr.io/vitruviansoftware/backstage",
            "--old-digest",
            &d_old,
            "--new-digest",
            &d_new,
            "--path",
            "apps/web/backstage",
        ])
        .go();

    assert_eq!(o.code, 0, "stderr={}", o.stderr);
    assert_has(
        &o.stdout,
        "previous revision unknown",
        "non-matching 40-hex tags yield unknown",
    );
    assert_has(&o.stdout, &new_sha[..7], "new revision still shown");
}

#[test]
fn tag_fallback_ignores_short_sha_and_non_hex_tags() {
    let bin = bin("BIN");
    let tmp = TempDir::new();
    let repo = tmp.join("repo");
    let new_sha = git_init(&repo);

    let d_old = format!("sha256:{}", pad64('3'));
    let d_new = format!("sha256:{}", pad64('4'));
    let d_cfg_old = format!("sha256:{}", pad64('5'));
    let d_cfg_new = format!("sha256:{}", pad64('6'));

    let short_sha = "1fb33e4";
    let prefixed_sha = "sha-1fa63ba";
    let non_hex_40 = "zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz";
    let upper_hex_40 = "ABCDEF0123456789ABCDEF0123456789ABCDEF01";

    let fix = tmp.join("fixtures");
    write(fix.join("token.json"), r#"{"token":"tok"}"#);
    write(
        fix.join("m_old.json"),
        format!(r#"{{"config":{{"digest":"{d_cfg_old}"}}}}"#),
    );
    write(
        fix.join("m_new.json"),
        format!(r#"{{"config":{{"digest":"{d_cfg_new}"}}}}"#),
    );
    write(fix.join("cfg_old.json"), r#"{"config":{"Labels":{}}}"#);
    write(
        fix.join("cfg_new.json"),
        format!(r#"{{"config":{{"Labels":{{"org.opencontainers.image.revision":"{new_sha}"}}}}}}"#),
    );
    write(
        fix.join("tags.json"),
        format!(
            r#"{{"name":"vitruviansoftware/backstage","tags":["latest","{short_sha}","{prefixed_sha}","{non_hex_40}","{upper_hex_40}"]}}"#
        ),
    );
    // Deliberately point every ignored tag's manifest HEAD at d_old so any
    // failure to filter them out would falsely resolve old_rev.
    write(
        fix.join("head_trap.txt"),
        format!("HTTP/2 200\r\ndocker-content-digest: {d_old}\r\n\r\n"),
    );
    write(
        fix.join("map.tsv"),
        format!(
            "/token?\tok\ttoken.json\n\
             /manifests/{d_old}\tok\tm_old.json\n\
             /manifests/{d_new}\tok\tm_new.json\n\
             /blobs/{d_cfg_old}\tok\tcfg_old.json\n\
             /blobs/{d_cfg_new}\tok\tcfg_new.json\n\
             /tags/list\tok\ttags.json\n\
             /manifests/latest\tok\thead_trap.txt\n\
             /manifests/{short_sha}\tok\thead_trap.txt\n\
             /manifests/{prefixed_sha}\tok\thead_trap.txt\n\
             /manifests/{non_hex_40}\tok\thead_trap.txt\n\
             /manifests/{upper_hex_40}\tok\thead_trap.txt\n"
        ),
    );

    let fakebin = tmp.join("bin");
    setup_fake_curl(&fakebin, &fix);

    let o = Run::new(&bin)
        .cwd(&repo)
        .path_first(&fakebin)
        .args([
            "--image",
            "ghcr.io/vitruviansoftware/backstage",
            "--old-digest",
            &d_old,
            "--new-digest",
            &d_new,
            "--path",
            "apps/web/backstage",
        ])
        .go();

    assert_eq!(o.code, 0, "stderr={}", o.stderr);
    assert_has(
        &o.stdout,
        "previous revision unknown",
        "short-sha, non-hex, and uppercase tags ignored",
    );
    assert_has(&o.stdout, &new_sha[..7], "new revision shown");
}
