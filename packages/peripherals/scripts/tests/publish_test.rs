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

//! `:publish` end to end against stub `bazel`, `lipo`, `gh` and `git` (and
//! the hermetic jq). The expectations -- exit codes, output, every external
//! call and the files staged -- are what `packages/peripherals/publish.sh`,
//! the script this binary replaced, did on the same stubs.

use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::atomic::{AtomicUsize, Ordering};

static N: AtomicUsize = AtomicUsize::new(0);

const BAZEL: &str = r#"echo "bazel $*" >>"$CALLS"
case "$1" in
  build) exit ${BAZEL_BUILD_RC:-0};;
  cquery) echo "bazel-out/darwin/bin/packages/peripherals/gravastar-mouse.runfiles"
          printf "%s\n" "${CQ_OUT-bazel-out/darwin/bin/packages/peripherals/gravastar-mouse}"; exit ${CQ_RC:-0};;
esac"#;
const LIPO: &str = r#"echo "lipo $*" >>"$CALLS"; [ -n "${LIPO_RC:-}" ] && exit $LIPO_RC; echo "${ARCHS-x86_64 arm64}""#;
const GH: &str = r#"echo "gh $*" >>"$CALLS"; v=0
case "$1 $2" in
  "release view") v=${GH_VIEW_RC:-1};;
  "release create") v=${GH_CREATE_RC:-0};;
  "release upload") v=${GH_UPLOAD_RC:-0};;
  "release edit") v=${GH_EDIT_RC:-0};;
  "api -X") v=${GH_API_RC:-0}; echo "{api}";;
esac; exit $v"#;
const GIT: &str = r#"echo "git $*" >>"$CALLS"
if [ "$1" = rev-parse ] && [ "$2" = HEAD ]; then echo deadbeefcafef00d1234; exit 0; fi
if [ "$1" = clone ]; then [ -n "${GIT_CLONE_RC:-}" ] && exit $GIT_CLONE_RC; for a; do d=$a; done; mkdir -p "$d"; exit 0; fi
if [ "$1" = -C ]; then case "$3" in add) exit 0;; diff) exit ${GIT_DIFF_RC:-1};; -c) exit 0;; push) exit ${GIT_PUSH_RC:-0};; esac; fi
exit 0"#;

struct Fx {
    root: PathBuf,
    temp: PathBuf,
    path: String,
    calls: PathBuf,
}

fn stub(p: &Path, body: &str) {
    fs::write(p, format!("#!/bin/sh\n{body}\n")).unwrap();
    fs::set_permissions(p, fs::Permissions::from_mode(0o755)).unwrap();
}

fn fixture() -> Fx {
    let base = std::env::var_os("TEST_TMPDIR")
        .map(PathBuf::from)
        .unwrap_or_else(std::env::temp_dir);
    let d = base.join(format!(
        "publish-{}-{}",
        std::process::id(),
        N.fetch_add(1, Ordering::SeqCst)
    ));
    let _ = fs::remove_dir_all(&d);
    let (root, stubs, temp) = (d.join("root"), d.join("stubs"), d.join("rt"));
    let out = root.join("bazel-out/darwin/bin/packages/peripherals");
    for dir in [&stubs, &temp, &out] {
        fs::create_dir_all(dir).unwrap();
    }
    let pkg = root.join("packages/peripherals");
    fs::create_dir_all(&pkg).unwrap();
    fs::write(
        pkg.join(".release-please-manifest.json"),
        "{\n  \"packages/peripherals\": \"0.1.2\"\n}\n",
    )
    .unwrap();
    fs::write(pkg.join("LICENSE"), "MIT LICENSE\n").unwrap();
    fs::write(pkg.join("README.md"), "# readme\n").unwrap();
    stub(&out.join("gravastar-mouse"), r#"echo "${BIN_VER-0.1.2}""#);
    stub(&stubs.join("bazel"), BAZEL);
    stub(&stubs.join("lipo"), LIPO);
    stub(&stubs.join("gh"), GH);
    stub(&stubs.join("git"), GIT);
    // $(JQ_BIN) is an execroot path; from the runfiles root an external
    // repository sits one level up.
    let jq_var = std::env::var("JQ_BIN").expect("JQ_BIN");
    let jq_rel = match jq_var.strip_prefix("external/") {
        Some(rest) => format!("../{rest}"),
        None => jq_var.clone(),
    };
    let jq = fs::canonicalize(&jq_rel).unwrap_or_else(|e| panic!("JQ_BIN={jq_var}: {e}"));
    std::os::unix::fs::symlink(jq, stubs.join("jq")).unwrap();
    Fx {
        path: format!("{}:/usr/bin:/bin", stubs.display()),
        calls: d.join("calls"),
        root,
        temp,
    }
}

struct Out {
    rc: i32,
    stdout: String,
    stderr: String,
    calls: String,
}

fn publish(fx: &Fx, env: &[(&str, &str)]) -> Out {
    let bin = fs::canonicalize(std::env::var("PUBLISH_BIN").expect("PUBLISH_BIN")).unwrap();
    let mut c = Command::new(bin);
    c.env_clear()
        .current_dir(std::env::temp_dir())
        .env("PATH", &fx.path)
        .env("HOME", "/nonexistent")
        .env("CALLS", &fx.calls)
        .env("BUILD_WORKSPACE_DIRECTORY", &fx.root)
        .env("RUNNER_TEMP", &fx.temp)
        .env("GITHUB_SHA", "0123456789abcdef")
        .env("GRADE", "beta");
    for (k, v) in env {
        c.env(k, v);
    }
    let o = c.output().unwrap();
    let norm = |s: String| {
        let s = s.replace(fx.temp.to_str().unwrap(), "WORK");
        // the archive digest varies with gzip's header; checked separately
        let mut out = String::new();
        for w in s.split_inclusive(|ch: char| !ch.is_ascii_hexdigit()) {
            let hex = w.trim_end_matches(|ch: char| !ch.is_ascii_hexdigit());
            if hex.len() == 64 {
                out.push_str("DIGEST");
                out.push_str(&w[64..]);
            } else {
                out.push_str(w);
            }
        }
        out
    };
    Out {
        rc: o.status.code().unwrap_or(-1),
        stdout: norm(String::from_utf8_lossy(&o.stdout).into_owned()),
        stderr: norm(String::from_utf8_lossy(&o.stderr).into_owned()),
        calls: norm(fs::read_to_string(&fx.calls).unwrap_or_default()),
    }
}

const BUILD: &str = "bazel build --config=macos-app --macos_cpus=arm64,x86_64 //packages/peripherals:gravastar-mouse\n\
bazel cquery --config=macos-app --macos_cpus=arm64,x86_64 --output=files //packages/peripherals:gravastar-mouse\n\
lipo -archs bazel-out/darwin/bin/packages/peripherals/gravastar-mouse\n";

#[test]
fn beta_creates_the_rolling_release_uploads_and_moves_the_tag() {
    let fx = fixture();
    let o = publish(&fx, &[]);
    assert_eq!(o.rc, 0, "{}", o.stderr);
    assert_eq!(
        o.stdout,
        "=== gravastar-mouse publish: grade=beta version=0.1.2-beta.0123456 tag=gravastar-mouse-beta-latest commit=0123456789abcdef ===\n\
         gravastar-mouse-beta-macos.tar.gz: sha256 DIGEST\n\
         === gravastar-mouse publish complete: gravastar-mouse-beta-latest (0.1.2-beta.0123456, beta) ===\n"
    );
    assert_eq!(
        o.calls,
        format!(
            "{BUILD}gh release view gravastar-mouse-beta-latest\n\
gh release create gravastar-mouse-beta-latest --prerelease --target 0123456789abcdef --title gravastar-mouse (Beta Rolling Release) --notes Rolling pre-release built automatically from commits landing on main.\n\
gh release upload gravastar-mouse-beta-latest WORK/gravastar-mouse-dist/gravastar-mouse-beta-macos.tar.gz WORK/gravastar-mouse-dist/gravastar-mouse-beta-macos.tar.gz.sha256 --clobber\n\
gh api -X PATCH repos/{{owner}}/{{repo}}/git/refs/tags/gravastar-mouse-beta-latest -f sha=0123456789abcdef -F force=true\n\
gh release edit gravastar-mouse-beta-latest --notes Latest beta build: 0.1.2-beta.0123456\n\
Commit: 0123456789abcdef\n\n\
gravastar-mouse-beta-macos.tar.gz: the universal (arm64 + x86_64) gravastar-mouse command, with its LICENSE and README.\n\
sha256: DIGEST\n"
        )
    );
    let dist = fx.temp.join("gravastar-mouse-dist");
    let sums = fs::read_to_string(dist.join("gravastar-mouse-beta-macos.tar.gz.sha256")).unwrap();
    assert!(sums.ends_with("  gravastar-mouse-beta-macos.tar.gz\n"));
    assert_eq!(
        fs::metadata(dist.join("stage/gravastar-mouse"))
            .unwrap()
            .permissions()
            .mode()
            & 0o777,
        0o755
    );
    let list = Command::new("tar")
        .arg("-tzf")
        .arg(dist.join("gravastar-mouse-beta-macos.tar.gz"))
        .output()
        .unwrap();
    assert_eq!(
        String::from_utf8_lossy(&list.stdout),
        "gravastar-mouse\nLICENSE\nREADME.md\n"
    );
}

#[test]
fn beta_failures_end_the_run_with_the_commands_status() {
    // The old port ignored a failed tag move and a failed notes edit.
    for (var, rc) in [
        ("GH_API_RC", "4"),
        ("GH_EDIT_RC", "5"),
        ("GH_UPLOAD_RC", "6"),
        ("GH_CREATE_RC", "7"),
    ] {
        let fx = fixture();
        let o = publish(&fx, &[(var, rc)]);
        assert_eq!(o.rc.to_string(), rc, "{var}");
        assert!(!o.stdout.contains("publish complete"), "{var}");
        assert_eq!(
            o.stderr, "",
            "{var}: nothing added to the command's own failure"
        );
    }
    let fx = fixture();
    let o = publish(&fx, &[("BAZEL_BUILD_RC", "3")]);
    assert_eq!((o.rc, o.stderr.as_str()), (3, ""));
}

#[test]
fn empty_variables_count_as_unset() {
    let fx = fixture();
    let o = publish(&fx, &[("GRADE", ""), ("TAG", ""), ("GITHUB_SHA", "")]);
    assert_eq!(o.rc, 0, "{}", o.stderr);
    assert!(o.stdout.starts_with("=== gravastar-mouse publish: grade=beta version=0.1.2-beta.deadbee tag=gravastar-mouse-beta-latest commit=deadbeefcafef00d1234 ===\n"));
    assert!(o.calls.starts_with("git rev-parse HEAD\n"));
}

#[test]
fn production_checks_come_before_any_build() {
    let fx = fixture();
    for (tag, want) in [
        (None, "publish: GRADE=production needs RELEASE_TAG=gravastar-mouse-vX.Y.Z (the release-please tag); refusing to guess\n"),
        (Some("esp32-s3-v1.0.0"), "publish: RELEASE_TAG=esp32-s3-v1.0.0 is not a gravastar-mouse-v* release; another component's release reached this rung\n"),
        (Some("gravastar-mouse-v9.9.9"), "publish: gravastar-mouse-v9.9.9 is version 9.9.9, but this checkout is 0.1.2; check out the release tag first\n"),
    ] {
        let mut env = vec![("GRADE", "production")];
        if let Some(t) = tag {
            env.push(("RELEASE_TAG", t));
        }
        let o = publish(&fx, &env);
        assert_eq!((o.rc, o.stderr.as_str(), o.calls.as_str()), (2, want, ""));
    }
    let o = publish(&fx, &[("GRADE", "staging")]);
    assert_eq!(
        (o.rc, o.stderr.as_str()),
        (2, "publish: unknown GRADE=staging (beta|production)\n")
    );
}

#[test]
fn production_attaches_the_asset_and_updates_the_tap() {
    let tag = ("RELEASE_TAG", "gravastar-mouse-v0.1.2");
    let fx = fixture();
    let o = publish(&fx, &[("GRADE", "production"), tag]);
    assert_eq!(o.rc, 0, "{}", o.stderr);
    assert!(o.stdout.ends_with(
        "publish: HOMEBREW_TAP_TOKEN is not set; skipping the VitruvianSoftware/homebrew-tap formula update\n\
         === gravastar-mouse publish complete: gravastar-mouse-v0.1.2 (0.1.2, production) ===\n"
    ));
    assert!(!o.calls.contains("gh release view") && !o.calls.contains("gh api"));

    let fx = fixture();
    let o = publish(
        &fx,
        &[("GRADE", "production"), tag, ("HOMEBREW_TAP_TOKEN", "tok")],
    );
    assert_eq!(o.rc, 0, "{}", o.stderr);
    assert!(o.calls.ends_with(
        "gh release upload gravastar-mouse-v0.1.2 WORK/gravastar-mouse-dist/gravastar-mouse-0.1.2-macos.tar.gz WORK/gravastar-mouse-dist/gravastar-mouse-0.1.2-macos.tar.gz.sha256 --clobber\n\
         git clone --depth 1 https://x-access-token:tok@github.com/VitruvianSoftware/homebrew-tap.git WORK/gravastar-mouse-dist/tap\n\
         git -C WORK/gravastar-mouse-dist/tap add Formula/gravastar-mouse.rb\n\
         git -C WORK/gravastar-mouse-dist/tap diff --cached --quiet\n\
         git -C WORK/gravastar-mouse-dist/tap -c user.name=github-actions[bot] -c user.email=41898282+github-actions[bot]@users.noreply.github.com commit -q -m gravastar-mouse 0.1.2\n\
         git -C WORK/gravastar-mouse-dist/tap push -q origin HEAD\n"
    ), "{}", o.calls);
    assert!(o.stdout.contains(
        "publish: VitruvianSoftware/homebrew-tap Formula/gravastar-mouse.rb is now 0.1.2\n"
    ));
    let formula = fs::read_to_string(
        fx.temp
            .join("gravastar-mouse-dist/tap/Formula/gravastar-mouse.rb"),
    )
    .unwrap();
    assert!(formula.contains("  url \"https://github.com/VitruvianSoftware/vitruvian-core/releases/download/gravastar-mouse-v0.1.2/gravastar-mouse-0.1.2-macos.tar.gz\"\n  version \"0.1.2\"\n"));

    let fx = fixture();
    let o = publish(
        &fx,
        &[
            ("GRADE", "production"),
            tag,
            ("HOMEBREW_TAP_TOKEN", "tok"),
            ("GIT_DIFF_RC", "0"),
        ],
    );
    assert_eq!(o.rc, 0);
    assert!(o
        .stdout
        .contains("publish: VitruvianSoftware/homebrew-tap already has gravastar-mouse 0.1.2\n"));
    assert!(!o.calls.contains(" commit "));

    let fx = fixture();
    let o = publish(
        &fx,
        &[
            ("GRADE", "production"),
            tag,
            ("HOMEBREW_TAP_TOKEN", "tok"),
            ("GIT_PUSH_RC", "9"),
        ],
    );
    assert_eq!(o.rc, 9);
}

#[test]
fn the_binary_must_be_universal_and_report_the_manifest_version() {
    let fx = fixture();
    let o = publish(&fx, &[("ARCHS", "arm64e x86_64h")]);
    assert_eq!(o.rc, 1);
    assert_eq!(o.stderr, "publish: bazel-out/darwin/bin/packages/peripherals/gravastar-mouse is 'arm64e x86_64h', missing arm64\n");

    let o = publish(&fx, &[("BIN_VER", "9.9.9")]);
    assert_eq!(o.rc, 1);
    assert_eq!(
        o.stderr,
        "publish: the binary reports 9.9.9, but the manifest is 0.1.2 (CLI.version out of step?)\n"
    );

    // `$(cquery | grep | head -1)` under pipefail: nothing matching is grep's 1, silently.
    let o = publish(&fx, &[("CQ_OUT", "bazel-out/x/other")]);
    assert_eq!((o.rc, o.stderr.as_str()), (1, ""));
    let o = publish(&fx, &[("LIPO_RC", "8")]);
    assert_eq!(o.rc, 8);
}
