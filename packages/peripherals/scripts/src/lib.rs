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

//! `bazel run //packages/peripherals:publish` -- build the universal
//! gravastar-mouse command and publish it to a GitHub Release, and (for a
//! release) its Homebrew formula.
//!
//! ONE tool, TWO triggers (delivery-orchestrator spec §4.1): the generated
//! .github/workflows/delivery-gravastar-mouse.yaml runs it for the
//! `gravastar-mouse-publish` unit, and the break-glass path is the same
//! `bazel run` on a Mac. The rung selects the grade:
//!
//!   GRADE=beta        (push to main)  rolling prerelease `gravastar-mouse-beta-latest`;
//!                     the asset is overwritten and the tag is moved to HEAD.
//!   GRADE=production  (release event) attach the asset to the release-please
//!                     release named by RELEASE_TAG (gravastar-mouse-vX.Y.Z), then
//!                     update Formula/gravastar-mouse.rb in
//!                     VitruvianSoftware/homebrew-tap when HOMEBREW_TAP_TOKEN is set.
//!
//! The binary is universal (arm64 + x86_64) and signed ad hoc by rules_apple.
//!
//! Break-glass for production: check out the release tag, then
//!   GRADE=production RELEASE_TAG=gravastar-mouse-vX.Y.Z bazel run //packages/peripherals:publish
//!
//! Replaced `packages/peripherals/publish.sh` and keeps its behaviour step for
//! step: the same commands in the same order, `${VAR:-default}` treating an
//! empty variable as unset, and `set -euo pipefail` -- a failing command ends
//! the run with that command's status and nothing added. Std-only on purpose.

use std::env;
use std::fs;
use std::io::{self, Write};
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

const PKG: &str = "packages/peripherals";
const REPO: &str = "VitruvianSoftware/vitruvian-core";
const TAP: &str = "VitruvianSoftware/homebrew-tap";
const TAG_PREFIX: &str = "gravastar-mouse-v";

#[derive(Debug, Clone, PartialEq)]
pub enum Grade {
    Beta,
    Production,
}

/// What the run publishes, decided before anything is built.
#[derive(Debug, PartialEq)]
pub struct Plan {
    pub grade: Grade,
    pub tag: String,
    pub version: String,
    pub asset: String,
}

/// `${NAME:-}`: unset and empty are the same.
fn var(name: &str) -> Option<String> {
    env::var(name).ok().filter(|v| !v.is_empty())
}

/// The `case "${GRADE}"` block. Errors carry the script's message and status 2.
pub fn plan(
    grade: &str,
    tag: Option<&str>,
    release_tag: Option<&str>,
    sha: &str,
    manifest_ver: &str,
) -> Result<Plan, String> {
    match grade {
        "beta" => {
            let sha7: String = sha.chars().take(7).collect();
            Ok(Plan {
                grade: Grade::Beta,
                tag: tag.unwrap_or("gravastar-mouse-beta-latest").to_string(),
                version: format!("{manifest_ver}-beta.{sha7}"),
                asset: "gravastar-mouse-beta-macos.tar.gz".to_string(),
            })
        }
        "production" => {
            // A dispatch of the production rung carries no release event, and
            // re-uploading a release's asset from a different commit would
            // silently replace what was released. Require the tag; never guess it.
            let tag = release_tag.unwrap_or("");
            if tag.is_empty() {
                return Err(format!("publish: GRADE=production needs RELEASE_TAG={TAG_PREFIX}X.Y.Z (the release-please tag); refusing to guess"));
            }
            let Some(version) = tag.strip_prefix(TAG_PREFIX) else {
                return Err(format!("publish: RELEASE_TAG={tag} is not a {TAG_PREFIX}* release; another component's release reached this rung"));
            };
            if version != manifest_ver {
                return Err(format!("publish: {tag} is version {version}, but this checkout is {manifest_ver}; check out the release tag first"));
            }
            Ok(Plan {
                grade: Grade::Production,
                tag: tag.to_string(),
                version: version.to_string(),
                asset: format!("gravastar-mouse-{version}-macos.tar.gz"),
            })
        }
        other => Err(format!("publish: unknown GRADE={other} (beta|production)")),
    }
}

pub fn build_bazel_flags(buildbuddy_api_key: Option<&str>) -> Vec<String> {
    let mut flags = vec![
        "--config=macos-app".to_string(),
        "--macos_cpus=arm64,x86_64".to_string(),
    ];
    if let Some(key) = buildbuddy_api_key {
        flags.push("--config=remotecache-ci".to_string());
        flags.push(format!("--remote_header=x-buildbuddy-api-key={key}"));
    }
    flags
}

/// The first `bazel cquery --output=files` line naming the binary, and the
/// status `$(cquery | grep '/gravastar-mouse$' | head -1)` had under pipefail:
/// grep's 1 when nothing matched, else cquery's own.
pub fn pick_binary(cquery_stdout: &[u8], cquery_status: i32) -> Result<String, i32> {
    let text = String::from_utf8_lossy(cquery_stdout);
    match text.lines().find(|l| l.ends_with("/gravastar-mouse")) {
        None => Err(1),
        Some(_) if cquery_status != 0 => Err(cquery_status),
        Some(l) => Ok(l.to_string()),
    }
}

/// `[[ " ${archs} " == *" ${arch} "* ]]` for both architectures.
pub fn missing_arch(archs: &str) -> Option<&'static str> {
    let padded = format!(" {archs} ");
    ["arm64", "x86_64"]
        .into_iter()
        .find(|a| !padded.contains(&format!(" {a} ")))
}

/// What `$(...)` keeps of a command's output: trailing newlines stripped.
fn captured(mut v: Vec<u8>) -> String {
    while v.last() == Some(&b'\n') {
        v.pop();
    }
    String::from_utf8_lossy(&v).into_owned()
}

fn say(line: &str) {
    let mut o = io::stdout().lock();
    let _ = writeln!(o, "{line}");
    let _ = o.flush();
}

/// A command bash could not start: its diagnostic and status.
fn not_started(cmd: &Command, e: &io::Error) -> i32 {
    let name = cmd.get_program().to_string_lossy().into_owned();
    if e.kind() == io::ErrorKind::NotFound {
        if name.contains('/') {
            eprintln!("{name}: No such file or directory");
        } else {
            eprintln!("{name}: command not found");
        }
        127
    } else {
        eprintln!("{name}: Permission denied");
        126
    }
}

fn code(st: std::process::ExitStatus) -> i32 {
    use std::os::unix::process::ExitStatusExt;
    st.code()
        .or_else(|| st.signal().map(|s| 128 + s))
        .unwrap_or(1)
}

/// A plain command line under errexit: Ok on success, else its status.
fn run(cmd: &mut Command) -> Result<(), i32> {
    match cmd.status() {
        Ok(s) if s.success() => Ok(()),
        Ok(s) => Err(code(s)),
        Err(e) => Err(not_started(cmd, &e)),
    }
}

/// `$(cmd)` with stderr passed through: (status, stdout).
fn capture(cmd: &mut Command) -> (i32, Vec<u8>) {
    match cmd.stdout(Stdio::piped()).output() {
        Ok(o) => (code(o.status), o.stdout),
        Err(e) => (not_started(cmd, &e), Vec::new()),
    }
}

/// `x="$(cmd)"` under errexit: the captured text, or the status to exit with.
fn assign(cmd: &mut Command) -> Result<String, i32> {
    match capture(cmd.stderr(Stdio::inherit())) {
        (0, out) => Ok(captured(out)),
        (rc, _) => Err(rc),
    }
}

fn workspace_root() -> PathBuf {
    if let Some(d) = var("BUILD_WORKSPACE_DIRECTORY") {
        return PathBuf::from(d);
    }
    // $(git rev-parse --show-toplevel 2>/dev/null || pwd)
    let mut git = Command::new("git");
    git.args(["rev-parse", "--show-toplevel"])
        .stderr(Stdio::null());
    if let (0, out) = capture(&mut git) {
        let top = captured(out);
        if !top.is_empty() {
            return PathBuf::from(top);
        }
    }
    env::current_dir().unwrap_or_else(|_| PathBuf::from("."))
}

fn is_executable(p: &Path) -> bool {
    fs::metadata(p).is_ok_and(|m| m.permissions().mode() & 0o111 != 0)
}

pub fn main_rc() -> i32 {
    match publish() {
        Ok(()) => 0,
        Err(rc) => rc,
    }
}

fn publish() -> Result<(), i32> {
    let root = workspace_root();
    if env::set_current_dir(&root).is_err() {
        eprintln!("cd: {}: No such file or directory", root.display());
        return Err(1);
    }

    let grade = var("GRADE").unwrap_or_else(|| "beta".to_string());
    let sha = match var("GITHUB_SHA") {
        Some(s) => s,
        None => assign(Command::new("git").args(["rev-parse", "HEAD"]))?,
    };
    let manifest_ver = assign(Command::new("jq").args([
        "-r",
        ".\"packages/peripherals\"",
        &format!("{PKG}/.release-please-manifest.json"),
    ]))?;

    let p = plan(
        &grade,
        var("TAG").as_deref(),
        var("RELEASE_TAG").as_deref(),
        &sha,
        &manifest_ver,
    )
    .map_err(|msg| {
        eprintln!("{msg}");
        2
    })?;
    let (tag, version, asset) = (&p.tag, &p.version, &p.asset);

    say(&format!(
        "=== gravastar-mouse publish: grade={grade} version={version} tag={tag} commit={sha} ==="
    ));

    let flags = build_bazel_flags(var("BUILDBUDDY_API_KEY").as_deref());
    let target = format!("//{PKG}:gravastar-mouse");
    run(Command::new("bazel").arg("build").args(&flags).arg(&target))?;
    let (cq_rc, cq_out) = capture(
        Command::new("bazel")
            .arg("cquery")
            .args(&flags)
            .args(["--output=files", &target])
            .stderr(Stdio::null()),
    );
    let binary = pick_binary(&cq_out, cq_rc)?;
    if binary.is_empty() || !is_executable(Path::new(&binary)) {
        eprintln!("publish: bazel produced no gravastar-mouse binary for //{PKG}:gravastar-mouse");
        return Err(1);
    }

    // What the release promises: both architectures, and the version it is named for.
    let archs = assign(Command::new("lipo").args(["-archs", &binary]))?;
    if let Some(arch) = missing_arch(&archs) {
        eprintln!("publish: {binary} is '{archs}', missing {arch}");
        return Err(1);
    }
    let reported = assign(Command::new(&binary).arg("--version"))?;
    if reported != manifest_ver {
        eprintln!("publish: the binary reports {reported}, but the manifest is {manifest_ver} (CLI.version out of step?)");
        return Err(1);
    }

    let base = match var("RUNNER_TEMP") {
        Some(t) => t,
        None => assign(Command::new("mktemp").arg("-d"))?,
    };
    let work = PathBuf::from(base).join("gravastar-mouse-dist");
    let stage = work.join("stage");
    let io_fail = |what: &str, e: io::Error| {
        eprintln!("publish: {what}: {e}");
        1
    };
    if work.exists() {
        fs::remove_dir_all(&work).map_err(|e| io_fail("rm -rf", e))?;
    }
    fs::create_dir_all(&stage).map_err(|e| io_fail("mkdir -p", e))?;
    let staged = stage.join("gravastar-mouse");
    fs::copy(&binary, &staged).map_err(|e| io_fail("cp", e))?;
    fs::set_permissions(&staged, fs::Permissions::from_mode(0o755))
        .map_err(|e| io_fail("chmod", e))?;
    for f in ["LICENSE", "README.md"] {
        fs::copy(Path::new(PKG).join(f), stage.join(f)).map_err(|e| io_fail("cp", e))?;
    }
    let archive = work.join(asset);
    run(Command::new("tar")
        .arg("-czf")
        .arg(&archive)
        .arg("-C")
        .arg(&stage)
        .args(["gravastar-mouse", "LICENSE", "README.md"]))?;
    let digest = sha256_digest(&fs::read(&archive).map_err(|e| io_fail("shasum", e))?);
    let sums = work.join(format!("{asset}.sha256"));
    fs::write(&sums, format!("{digest}  {asset}\n")).map_err(|e| io_fail("write", e))?;
    say(&format!("{asset}: sha256 {digest}"));

    if p.grade == Grade::Beta {
        let exists = Command::new("gh")
            .args(["release", "view", tag])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .is_ok_and(|s| s.success());
        if !exists {
            run(Command::new("gh").args([
                "release",
                "create",
                tag,
                "--prerelease",
                "--target",
                &sha,
                "--title",
                "gravastar-mouse (Beta Rolling Release)",
                "--notes",
                "Rolling pre-release built automatically from commits landing on main.",
            ]))?;
        }
    }

    run(Command::new("gh")
        .args(["release", "upload", tag])
        .arg(&archive)
        .arg(&sums)
        .arg("--clobber"))?;

    if p.grade == Grade::Beta {
        // Move the rolling tag to the commit whose asset now sits on the release.
        run(Command::new("gh")
            .args([
                "api",
                "-X",
                "PATCH",
                &format!("repos/{{owner}}/{{repo}}/git/refs/tags/{tag}"),
                "-f",
                &format!("sha={sha}"),
                "-F",
                "force=true",
            ])
            .stdout(Stdio::null()))?;
        let notes = format!(
            "Latest beta build: {version}\nCommit: {sha}\n\n{asset}: the universal (arm64 + x86_64) gravastar-mouse command, with its LICENSE and README.\nsha256: {digest}"
        );
        run(Command::new("gh").args(["release", "edit", tag, "--notes", &notes]))?;
        say(&format!(
            "=== gravastar-mouse publish complete: {tag} ({version}, beta) ==="
        ));
        return Ok(());
    }

    let Some(token) = var("HOMEBREW_TAP_TOKEN") else {
        say(&format!(
            "publish: HOMEBREW_TAP_TOKEN is not set; skipping the {TAP} formula update"
        ));
        say(&format!(
            "=== gravastar-mouse publish complete: {tag} ({version}, production) ==="
        ));
        return Ok(());
    };

    let tap_dir = work.join("tap");
    run(Command::new("git")
        .args(["clone", "--depth", "1"])
        .arg(format!(
            "https://x-access-token:{token}@github.com/{TAP}.git"
        ))
        .arg(&tap_dir))?;
    fs::create_dir_all(tap_dir.join("Formula")).map_err(|e| io_fail("mkdir -p", e))?;
    fs::write(
        tap_dir.join("Formula/gravastar-mouse.rb"),
        generate_formula(REPO, tag, asset, version, &digest),
    )
    .map_err(|e| io_fail("write formula", e))?;
    let git = || {
        let mut c = Command::new("git");
        c.arg("-C").arg(&tap_dir);
        c
    };
    run(git().args(["add", "Formula/gravastar-mouse.rb"]))?;
    if git()
        .args(["diff", "--cached", "--quiet"])
        .status()
        .is_ok_and(|s| s.success())
    {
        say(&format!(
            "publish: {TAP} already has gravastar-mouse {version}"
        ));
    } else {
        run(git().args([
            "-c",
            "user.name=github-actions[bot]",
            "-c",
            "user.email=41898282+github-actions[bot]@users.noreply.github.com",
            "commit",
            "-q",
            "-m",
            &format!("gravastar-mouse {version}"),
        ]))?;
        run(git().args(["push", "-q", "origin", "HEAD"]))?;
        say(&format!(
            "publish: {TAP} Formula/gravastar-mouse.rb is now {version}"
        ));
    }

    say(&format!(
        "=== gravastar-mouse publish complete: {tag} ({version}, production) ==="
    ));
    Ok(())
}

// ---------------------------------------------------------------------------
// Pure Rust SHA-256 (NIST FIPS 180-4)
// ---------------------------------------------------------------------------

const K: [u32; 64] = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
];

const H_INIT: [u32; 8] = [
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
];

fn sha256_pad(data: &[u8]) -> Vec<u8> {
    let bit_len = (data.len() as u64) * 8;
    let mut padded = data.to_vec();
    padded.push(0x80);
    while (padded.len() % 64) != 56 {
        padded.push(0x00);
    }
    padded.extend_from_slice(&bit_len.to_be_bytes());
    padded
}

fn sha256_compress(state: &mut [u32; 8], block: &[u8]) {
    let mut w = [0u32; 64];
    for i in 0..16 {
        w[i] = u32::from_be_bytes([
            block[i * 4],
            block[i * 4 + 1],
            block[i * 4 + 2],
            block[i * 4 + 3],
        ]);
    }
    for i in 16..64 {
        let s0 = w[i - 15].rotate_right(7) ^ w[i - 15].rotate_right(18) ^ (w[i - 15] >> 3);
        let s1 = w[i - 2].rotate_right(17) ^ w[i - 2].rotate_right(19) ^ (w[i - 2] >> 10);
        w[i] = w[i - 16]
            .wrapping_add(s0)
            .wrapping_add(w[i - 7])
            .wrapping_add(s1);
    }

    let [mut a, mut b, mut c, mut d, mut e, mut f, mut g, mut h] = *state;

    for i in 0..64 {
        let s1 = e.rotate_right(6) ^ e.rotate_right(11) ^ e.rotate_right(25);
        let ch = (e & f) ^ ((!e) & g);
        let temp1 = h
            .wrapping_add(s1)
            .wrapping_add(ch)
            .wrapping_add(K[i])
            .wrapping_add(w[i]);
        let s0 = a.rotate_right(2) ^ a.rotate_right(13) ^ a.rotate_right(22);
        let maj = (a & b) ^ (a & c) ^ (b & c);
        let temp2 = s0.wrapping_add(maj);

        h = g;
        g = f;
        f = e;
        e = d.wrapping_add(temp1);
        d = c;
        c = b;
        b = a;
        a = temp1.wrapping_add(temp2);
    }

    state[0] = state[0].wrapping_add(a);
    state[1] = state[1].wrapping_add(b);
    state[2] = state[2].wrapping_add(c);
    state[3] = state[3].wrapping_add(d);
    state[4] = state[4].wrapping_add(e);
    state[5] = state[5].wrapping_add(f);
    state[6] = state[6].wrapping_add(g);
    state[7] = state[7].wrapping_add(h);
}

pub fn sha256_digest(data: &[u8]) -> String {
    let padded = sha256_pad(data);
    let mut state = H_INIT;
    for chunk in padded.chunks(64) {
        sha256_compress(&mut state, chunk);
    }
    state
        .iter()
        .map(|v| format!("{:08x}", v))
        .collect::<String>()
}

pub fn generate_formula(repo: &str, tag: &str, asset: &str, version: &str, digest: &str) -> String {
    format!(
        r##"# Generated by //packages/peripherals:publish in {repo}; do not edit here.
class GravastarMouse < Formula
  desc "Status light and MCP server for the RGB LED of a GravaStar mouse"
  homepage "https://github.com/{repo}/tree/main/packages/peripherals"
  url "https://github.com/{repo}/releases/download/{tag}/{asset}"
  version "{version}"
  sha256 "{digest}"
  license "MIT"

  depends_on macos: :sonoma

  def install
    bin.install "gravastar-mouse"
  end

  test do
    assert_equal version.to_s, shell_output("#{{bin}}/gravastar-mouse --version").strip
  end
end
"##,
        repo = repo,
        tag = tag,
        asset = asset,
        version = version,
        digest = digest,
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_sha256_vectors() {
        assert_eq!(
            sha256_digest(b""),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        );
        assert_eq!(
            sha256_digest(b"abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
        assert_eq!(
            sha256_digest(&vec![b'a'; 1_000_000]),
            "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0"
        );
    }

    #[test]
    fn plan_beta_defaults_and_override() {
        let p = plan("beta", None, None, "abcdef1234567890", "1.2.3").unwrap();
        assert_eq!(
            p,
            Plan {
                grade: Grade::Beta,
                tag: "gravastar-mouse-beta-latest".into(),
                version: "1.2.3-beta.abcdef1".into(),
                asset: "gravastar-mouse-beta-macos.tar.gz".into(),
            }
        );
        assert_eq!(plan("beta", Some("t"), None, "ab", "1").unwrap().tag, "t");
        assert_eq!(
            plan("beta", None, None, "ab", "1").unwrap().version,
            "1-beta.ab"
        );
    }

    #[test]
    fn plan_production_refuses_to_guess() {
        let e = plan("production", None, None, "s", "1.0.0").unwrap_err();
        assert!(e.contains("GRADE=production needs RELEASE_TAG=gravastar-mouse-vX.Y.Z"));
        let e = plan("production", None, Some("esp32-s3-v1.0.0"), "s", "1.0.0").unwrap_err();
        assert!(e.contains("is not a gravastar-mouse-v* release"));
        let e = plan(
            "production",
            None,
            Some("gravastar-mouse-v2.0.0"),
            "s",
            "1.0.0",
        )
        .unwrap_err();
        assert!(e.contains("is version 2.0.0, but this checkout is 1.0.0"));
        let p = plan(
            "production",
            Some("ignored"),
            Some("gravastar-mouse-v1.0.0"),
            "s",
            "1.0.0",
        )
        .unwrap();
        assert_eq!(
            (p.tag.as_str(), p.asset.as_str()),
            (
                "gravastar-mouse-v1.0.0",
                "gravastar-mouse-1.0.0-macos.tar.gz"
            )
        );
        assert!(plan("staging", None, None, "s", "1")
            .unwrap_err()
            .contains("unknown GRADE=staging (beta|production)"));
    }

    #[test]
    fn bazel_flags() {
        assert_eq!(
            build_bazel_flags(None),
            vec!["--config=macos-app", "--macos_cpus=arm64,x86_64"]
        );
        assert_eq!(
            build_bazel_flags(Some("k")),
            vec![
                "--config=macos-app",
                "--macos_cpus=arm64,x86_64",
                "--config=remotecache-ci",
                "--remote_header=x-buildbuddy-api-key=k"
            ]
        );
    }

    #[test]
    fn cquery_pipeline_status() {
        let out = b"bazel-out/b/gravastar-mouse.runfiles\nbazel-out/b/gravastar-mouse\n";
        assert_eq!(
            pick_binary(out, 0),
            Ok("bazel-out/b/gravastar-mouse".into())
        );
        assert_eq!(pick_binary(out, 2), Err(2));
        assert_eq!(pick_binary(b"bazel-out/b/other\n", 0), Err(1));
        assert_eq!(pick_binary(b"", 2), Err(1));
    }

    #[test]
    fn arch_check_is_word_exact() {
        assert_eq!(missing_arch("x86_64 arm64"), None);
        assert_eq!(missing_arch("arm64"), Some("x86_64"));
        assert_eq!(missing_arch("arm64e x86_64h"), Some("arm64"));
    }

    #[test]
    fn formula_text() {
        let f = generate_formula("o/r", "gravastar-mouse-v1.2.3", "a.tar.gz", "1.2.3", "d1g");
        assert!(f.starts_with("# Generated by //packages/peripherals:publish in o/r; do not edit here.\nclass GravastarMouse < Formula\n"));
        assert!(f.contains("  url \"https://github.com/o/r/releases/download/gravastar-mouse-v1.2.3/a.tar.gz\"\n  version \"1.2.3\"\n  sha256 \"d1g\"\n"));
        assert!(f.contains("shell_output(\"#{bin}/gravastar-mouse --version\").strip"));
    }
}
