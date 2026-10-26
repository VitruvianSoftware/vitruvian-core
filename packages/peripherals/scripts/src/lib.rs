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

use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

const PKG: &str = "packages/peripherals";
const REPO: &str = "VitruvianSoftware/vitruvian-core";
const TAP: &str = "VitruvianSoftware/homebrew-tap";
const TAG_PREFIX: &str = "gravastar-mouse-v";

#[derive(Debug, Clone, PartialEq)]
pub enum Grade {
    Beta,
    Production,
}

impl Grade {
    pub fn parse(s: &str) -> Result<Self, String> {
        match s {
            "beta" => Ok(Grade::Beta),
            "production" => Ok(Grade::Production),
            other => Err(format!(
                "publish: unknown GRADE={} (beta|production)",
                other
            )),
        }
    }
}

#[derive(Debug)]
pub struct PublishConfig {
    pub workspace_root: PathBuf,
    pub grade: Grade,
    pub sha: String,
    pub manifest_version: String,
    pub tag: String,
    pub version: String,
    pub asset_name: String,
    pub buildbuddy_api_key: Option<String>,
    pub homebrew_tap_token: Option<String>,
}

pub fn find_workspace_root() -> Result<PathBuf, String> {
    if let Ok(dir) = env::var("BUILD_WORKSPACE_DIRECTORY") {
        let p = PathBuf::from(&dir);
        if p.is_dir() {
            return Ok(p);
        }
    }
    if let Ok(output) = Command::new("git")
        .args(["rev-parse", "--show-toplevel"])
        .output()
    {
        if output.status.success() {
            let s = String::from_utf8_lossy(&output.stdout).trim().to_string();
            if !s.is_empty() {
                let p = PathBuf::from(&s);
                if p.is_dir() {
                    return Ok(p);
                }
            }
        }
    }
    env::current_dir().map_err(|e| format!("publish: cannot determine workspace root: {}", e))
}

pub fn read_manifest_version(root: &Path) -> Result<String, String> {
    let manifest_path = root.join(PKG).join(".release-please-manifest.json");
    let content = fs::read_to_string(&manifest_path)
        .map_err(|e| format!("publish: cannot read {}: {}", manifest_path.display(), e))?;
    extract_manifest_version(&content)
}

pub fn extract_manifest_version(json: &str) -> Result<String, String> {
    let key = "\"packages/peripherals\"";
    let idx = json.find(key).ok_or_else(|| {
        "publish: \"packages/peripherals\" not found in .release-please-manifest.json".to_string()
    })?;
    let after_key = &json[idx + key.len()..];
    let colon_pos = after_key
        .find(':')
        .ok_or_else(|| "publish: malformed manifest JSON (no colon after key)".to_string())?;
    let after_colon = &after_key[colon_pos + 1..];
    let quote_start = after_colon.find('"').ok_or_else(|| {
        "publish: malformed manifest JSON (no opening quote for value)".to_string()
    })?;
    let value_start = &after_colon[quote_start + 1..];
    let quote_end = value_start.find('"').ok_or_else(|| {
        "publish: malformed manifest JSON (no closing quote for value)".to_string()
    })?;
    let version = &value_start[..quote_end];
    if version.is_empty() {
        return Err("publish: empty version in .release-please-manifest.json".to_string());
    }
    Ok(version.to_string())
}

fn get_git_sha() -> Result<String, String> {
    let output = Command::new("git")
        .args(["rev-parse", "HEAD"])
        .output()
        .map_err(|e| format!("publish: git rev-parse HEAD failed: {}", e))?;
    if !output.status.success() {
        return Err("publish: git rev-parse HEAD failed".to_string());
    }
    Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
}

pub fn resolve_config() -> Result<PublishConfig, (String, i32)> {
    let workspace_root = find_workspace_root().map_err(|e| (e, 1))?;
    let grade_str = env::var("GRADE").unwrap_or_else(|_| "beta".to_string());
    let grade = Grade::parse(&grade_str).map_err(|e| (e, 2))?;
    let sha = env::var("GITHUB_SHA")
        .or_else(|_| get_git_sha())
        .map_err(|e| (e, 1))?;
    let manifest_version = read_manifest_version(&workspace_root).map_err(|e| (e, 1))?;
    let buildbuddy_api_key = env::var("BUILDBUDDY_API_KEY")
        .ok()
        .filter(|s| !s.is_empty());
    let homebrew_tap_token = env::var("HOMEBREW_TAP_TOKEN")
        .ok()
        .filter(|s| !s.is_empty());

    let (tag, version, asset_name) = match &grade {
        Grade::Beta => {
            let tag = env::var("TAG").unwrap_or_else(|_| "gravastar-mouse-beta-latest".to_string());
            let sha7 = if sha.len() >= 7 { &sha[..7] } else { &sha };
            let version = format!("{}-beta.{}", manifest_version, sha7);
            let asset = "gravastar-mouse-beta-macos.tar.gz".to_string();
            (tag, version, asset)
        }
        Grade::Production => {
            let tag = env::var("RELEASE_TAG").unwrap_or_default();
            if tag.is_empty() {
                return Err((
                    format!(
                        "publish: GRADE=production needs RELEASE_TAG={}X.Y.Z (the release-please tag); refusing to guess",
                        TAG_PREFIX
                    ),
                    2,
                ));
            }
            if !tag.starts_with(TAG_PREFIX) {
                return Err((
                    format!(
                        "publish: RELEASE_TAG={} is not a {}* release; another component's release reached this rung",
                        tag, TAG_PREFIX
                    ),
                    2,
                ));
            }
            let version = tag[TAG_PREFIX.len()..].to_string();
            if version != manifest_version {
                return Err((
                    format!(
                        "publish: {} is version {}, but this checkout is {}; check out the release tag first",
                        tag, version, manifest_version
                    ),
                    2,
                ));
            }
            let asset = format!("gravastar-mouse-{}-macos.tar.gz", version);
            (tag, version, asset)
        }
    };

    Ok(PublishConfig {
        workspace_root,
        grade,
        sha,
        manifest_version,
        tag,
        version,
        asset_name,
        buildbuddy_api_key,
        homebrew_tap_token,
    })
}

pub fn build_bazel_flags(config: &PublishConfig) -> Vec<String> {
    let mut flags = vec![
        "--config=macos-app".to_string(),
        "--macos_cpus=arm64,x86_64".to_string(),
    ];
    if let Some(ref key) = config.buildbuddy_api_key {
        flags.push("--config=remotecache-ci".to_string());
        flags.push(format!("--remote_header=x-buildbuddy-api-key={}", key));
    }
    flags
}

pub fn verify_binary(binary: &Path, manifest_version: &str) -> Result<(), (String, i32)> {
    let output = Command::new("lipo")
        .args(["-archs", &binary.to_string_lossy()])
        .output()
        .map_err(|e| (format!("publish: lipo -archs failed: {}", e), 1))?;
    if !output.status.success() {
        return Err((
            format!("publish: lipo -archs {} failed", binary.display()),
            1,
        ));
    }
    let archs = String::from_utf8_lossy(&output.stdout).trim().to_string();
    for arch in &["arm64", "x86_64"] {
        let padded = format!(" {} ", archs);
        let padded = format!(" {} ", padded.trim());
        if !padded.contains(&format!(" {} ", arch)) {
            return Err((
                format!(
                    "publish: {} is '{}', missing {}",
                    binary.display(),
                    archs,
                    arch
                ),
                1,
            ));
        }
    }

    let output = Command::new(binary)
        .arg("--version")
        .output()
        .map_err(|e| {
            (
                format!("publish: {} --version failed: {}", binary.display(), e),
                1,
            )
        })?;
    let reported = String::from_utf8_lossy(&output.stdout).trim().to_string();
    if reported != manifest_version {
        return Err((
            format!(
                "publish: the binary reports {}, but the manifest is {} (CLI.version out of step?)",
                reported, manifest_version
            ),
            1,
        ));
    }
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

// ---------------------------------------------------------------------------
// Staging, archiving, release operations
// ---------------------------------------------------------------------------

pub fn stage_and_archive(
    config: &PublishConfig,
    binary: &Path,
) -> Result<(PathBuf, String), String> {
    let work = env::var("RUNNER_TEMP")
        .map(PathBuf::from)
        .unwrap_or_else(|_| env::temp_dir())
        .join("gravastar-mouse-dist");
    if work.exists() {
        fs::remove_dir_all(&work)
            .map_err(|e| format!("publish: cannot clean {}: {}", work.display(), e))?;
    }
    let stage = work.join("stage");
    fs::create_dir_all(&stage)
        .map_err(|e| format!("publish: cannot create {}: {}", stage.display(), e))?;

    let dest_binary = stage.join("gravastar-mouse");
    fs::copy(binary, &dest_binary).map_err(|e| format!("publish: cannot copy binary: {}", e))?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(&dest_binary, fs::Permissions::from_mode(0o755))
            .map_err(|e| format!("publish: cannot chmod binary: {}", e))?;
    }

    let pkg_dir = config.workspace_root.join(PKG);
    for file in &["LICENSE", "README.md"] {
        let src = pkg_dir.join(file);
        let dst = stage.join(file);
        fs::copy(&src, &dst)
            .map_err(|e| format!("publish: cannot copy {}: {}", src.display(), e))?;
    }

    let archive = work.join(&config.asset_name);
    let tar_status = Command::new("tar")
        .args(["-czf"])
        .arg(&archive)
        .args(["-C"])
        .arg(&stage)
        .args(["gravastar-mouse", "LICENSE", "README.md"])
        .status()
        .map_err(|e| format!("publish: tar failed: {}", e))?;
    if !tar_status.success() {
        return Err("publish: tar failed".to_string());
    }

    let archive_data =
        fs::read(&archive).map_err(|e| format!("publish: cannot read archive: {}", e))?;
    let digest = sha256_digest(&archive_data);

    let sha_file = work.join(format!("{}.sha256", config.asset_name));
    fs::write(&sha_file, format!("{}  {}\n", digest, config.asset_name))
        .map_err(|e| format!("publish: cannot write sha256 file: {}", e))?;

    eprintln!("{}: sha256 {}", config.asset_name, digest);

    Ok((archive, digest))
}

pub fn create_or_upload_release(
    config: &PublishConfig,
    archive: &Path,
    digest: &str,
) -> Result<(), String> {
    let sha_file = archive.with_extension("tar.gz.sha256");
    let sha_path = archive
        .parent()
        .unwrap()
        .join(format!("{}.sha256", config.asset_name));

    if config.grade == Grade::Beta {
        let view = Command::new("gh")
            .args(["release", "view", &config.tag])
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .status();
        let exists = view.map(|s| s.success()).unwrap_or(false);
        if !exists {
            let status = Command::new("gh")
                .args([
                    "release",
                    "create",
                    &config.tag,
                    "--prerelease",
                    "--target",
                    &config.sha,
                    "--title",
                    "gravastar-mouse (Beta Rolling Release)",
                    "--notes",
                    "Rolling pre-release built automatically from commits landing on main.",
                ])
                .status()
                .map_err(|e| format!("publish: gh release create failed: {}", e))?;
            if !status.success() {
                return Err("publish: gh release create failed".to_string());
            }
        }
    }

    let status = Command::new("gh")
        .args(["release", "upload", &config.tag])
        .arg(archive)
        .arg(&sha_path)
        .arg("--clobber")
        .status()
        .map_err(|e| format!("publish: gh release upload failed: {}", e))?;
    if !status.success() {
        return Err("publish: gh release upload failed".to_string());
    }

    if config.grade == Grade::Beta {
        let _ = Command::new("gh")
            .args([
                "api",
                "-X",
                "PATCH",
                &format!("repos/{{owner}}/{{repo}}/git/refs/tags/{}", config.tag),
                "-f",
                &format!("sha={}", config.sha),
                "-F",
                "force=true",
            ])
            .stdout(std::process::Stdio::null())
            .status();

        let notes = format!(
            "Latest beta build: {}\nCommit: {}\n\n{}: the universal (arm64 + x86_64) gravastar-mouse command, with its LICENSE and README.\nsha256: {}",
            config.version, config.sha, config.asset_name, digest
        );
        let _ = Command::new("gh")
            .args(["release", "edit", &config.tag, "--notes", &notes])
            .status();

        eprintln!(
            "=== gravastar-mouse publish complete: {} ({}, beta) ===",
            config.tag, config.version
        );
    }

    let _ = sha_file; // suppress unused warning
    Ok(())
}

pub fn generate_formula(repo: &str, tag: &str, asset: &str, version: &str, digest: &str) -> String {
    format!(
        r##"# Generated by packages/peripherals/publish.sh in {repo}; do not edit here.
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

pub fn update_homebrew_formula(config: &PublishConfig, digest: &str) -> Result<(), String> {
    let Some(ref token) = config.homebrew_tap_token else {
        eprintln!(
            "publish: HOMEBREW_TAP_TOKEN is not set; skipping the {} formula update",
            TAP
        );
        eprintln!(
            "=== gravastar-mouse publish complete: {} ({}, production) ===",
            config.tag, config.version
        );
        return Ok(());
    };

    let work = env::var("RUNNER_TEMP")
        .map(PathBuf::from)
        .unwrap_or_else(|_| env::temp_dir())
        .join("gravastar-mouse-dist");
    let tap_dir = work.join("tap");

    let clone_url = format!("https://x-access-token:{}@github.com/{}.git", token, TAP);
    let status = Command::new("git")
        .args(["clone", "--depth", "1", &clone_url])
        .arg(&tap_dir)
        .status()
        .map_err(|e| format!("publish: git clone tap failed: {}", e))?;
    if !status.success() {
        return Err("publish: git clone tap failed".to_string());
    }

    let formula_dir = tap_dir.join("Formula");
    fs::create_dir_all(&formula_dir)
        .map_err(|e| format!("publish: cannot create Formula dir: {}", e))?;

    let formula = generate_formula(
        REPO,
        &config.tag,
        &config.asset_name,
        &config.version,
        digest,
    );
    fs::write(formula_dir.join("gravastar-mouse.rb"), &formula)
        .map_err(|e| format!("publish: cannot write formula: {}", e))?;

    let _ = Command::new("git")
        .args(["-C"])
        .arg(&tap_dir)
        .args(["add", "Formula/gravastar-mouse.rb"])
        .status();

    let diff = Command::new("git")
        .args(["-C"])
        .arg(&tap_dir)
        .args(["diff", "--cached", "--quiet"])
        .status()
        .map_err(|e| format!("publish: git diff failed: {}", e))?;

    if diff.success() {
        eprintln!(
            "publish: {} already has gravastar-mouse {}",
            TAP, config.version
        );
    } else {
        let status = Command::new("git")
            .args(["-C"])
            .arg(&tap_dir)
            .args([
                "-c",
                "user.name=github-actions[bot]",
                "-c",
                "user.email=41898282+github-actions[bot]@users.noreply.github.com",
                "commit",
                "-q",
                "-m",
                &format!("gravastar-mouse {}", config.version),
            ])
            .status()
            .map_err(|e| format!("publish: git commit failed: {}", e))?;
        if !status.success() {
            return Err("publish: git commit to tap failed".to_string());
        }

        let status = Command::new("git")
            .args(["-C"])
            .arg(&tap_dir)
            .args(["push", "-q", "origin", "HEAD"])
            .status()
            .map_err(|e| format!("publish: git push failed: {}", e))?;
        if !status.success() {
            return Err("publish: git push to tap failed".to_string());
        }

        eprintln!(
            "publish: {} Formula/gravastar-mouse.rb is now {}",
            TAP, config.version
        );
    }

    eprintln!(
        "=== gravastar-mouse publish complete: {} ({}, production) ===",
        config.tag, config.version
    );
    Ok(())
}

pub fn run() -> i32 {
    let config = match resolve_config() {
        Ok(c) => c,
        Err((msg, code)) => {
            eprintln!("{}", msg);
            return code;
        }
    };

    eprintln!(
        "=== gravastar-mouse publish: grade={} version={} tag={} commit={} ===",
        match config.grade {
            Grade::Beta => "beta",
            Grade::Production => "production",
        },
        config.version,
        config.tag,
        config.sha
    );

    let flags = build_bazel_flags(&config);
    let target = format!("//{}:gravastar-mouse", PKG);

    let mut build_args = vec!["build".to_string()];
    build_args.extend(flags.clone());
    build_args.push(target.clone());

    let status = Command::new("bazel").args(&build_args).status();
    match status {
        Ok(s) if s.success() => {}
        Ok(_) => {
            eprintln!("publish: bazel build failed");
            return 1;
        }
        Err(e) => {
            eprintln!("publish: bazel build failed: {}", e);
            return 1;
        }
    }

    let mut cquery_args = vec!["cquery".to_string()];
    cquery_args.extend(flags);
    cquery_args.extend(["--output=files".to_string(), target]);

    let cquery_out = Command::new("bazel")
        .args(&cquery_args)
        .stderr(std::process::Stdio::null())
        .output();
    let binary_path = match cquery_out {
        Ok(out) if out.status.success() => {
            let stdout = String::from_utf8_lossy(&out.stdout);
            stdout
                .lines()
                .find(|l| l.ends_with("/gravastar-mouse"))
                .map(|l| PathBuf::from(l.trim()))
        }
        _ => None,
    };
    let binary = match binary_path {
        Some(ref p) if p.exists() => p,
        _ => {
            eprintln!(
                "publish: bazel produced no gravastar-mouse binary for //{}:gravastar-mouse",
                PKG
            );
            return 1;
        }
    };

    if let Err((msg, code)) = verify_binary(binary, &config.manifest_version) {
        eprintln!("{}", msg);
        return code;
    }

    let (archive, digest) = match stage_and_archive(&config, binary) {
        Ok(v) => v,
        Err(e) => {
            eprintln!("{}", e);
            return 1;
        }
    };

    if let Err(e) = create_or_upload_release(&config, &archive, &digest) {
        eprintln!("{}", e);
        return 1;
    }

    if config.grade == Grade::Production {
        if let Err(e) = update_homebrew_formula(&config, &digest) {
            eprintln!("{}", e);
            return 1;
        }
    }

    if config.grade == Grade::Beta {
        // Message already printed in create_or_upload_release
    } else {
        // Message already printed in update_homebrew_formula
    }

    0
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;

    static ENV_LOCK: Mutex<()> = Mutex::new(());

    #[test]
    fn test_sha256_empty() {
        assert_eq!(
            sha256_digest(b""),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        );
    }

    #[test]
    fn test_sha256_abc() {
        assert_eq!(
            sha256_digest(b"abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
    }

    #[test]
    fn test_sha256_long() {
        let data = vec![b'a'; 1_000_000];
        assert_eq!(
            sha256_digest(&data),
            "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0"
        );
    }

    #[test]
    fn test_grade_parse() {
        assert_eq!(Grade::parse("beta").unwrap(), Grade::Beta);
        assert_eq!(Grade::parse("production").unwrap(), Grade::Production);
        assert!(Grade::parse("staging").is_err());
        let err = Grade::parse("foo").unwrap_err();
        assert!(err.contains("unknown GRADE=foo"));
    }

    #[test]
    fn test_resolve_config_production_missing_tag() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        // Save and restore env vars to avoid test interference.
        let saved_grade = env::var("GRADE").ok();
        let saved_release = env::var("RELEASE_TAG").ok();
        let saved_bwd = env::var("BUILD_WORKSPACE_DIRECTORY").ok();
        let saved_sha = env::var("GITHUB_SHA").ok();

        env::set_var("GRADE", "production");
        env::remove_var("RELEASE_TAG");
        env::set_var("GITHUB_SHA", "abc1234567890");
        // Point to a temp dir that has the manifest file.
        let tmp = env::temp_dir().join("publish_test_prod_missing");
        let pkg_dir = tmp.join(PKG);
        let _ = fs::create_dir_all(&pkg_dir);
        let _ = fs::write(
            pkg_dir.join(".release-please-manifest.json"),
            r#"{"packages/peripherals": "1.2.3"}"#,
        );
        env::set_var("BUILD_WORKSPACE_DIRECTORY", tmp.to_string_lossy().as_ref());

        let result = resolve_config();

        // Restore env.
        match saved_grade {
            Some(v) => env::set_var("GRADE", v),
            None => env::remove_var("GRADE"),
        }
        match saved_release {
            Some(v) => env::set_var("RELEASE_TAG", v),
            None => env::remove_var("RELEASE_TAG"),
        }
        match saved_bwd {
            Some(v) => env::set_var("BUILD_WORKSPACE_DIRECTORY", v),
            None => env::remove_var("BUILD_WORKSPACE_DIRECTORY"),
        }
        match saved_sha {
            Some(v) => env::set_var("GITHUB_SHA", v),
            None => env::remove_var("GITHUB_SHA"),
        }
        let _ = fs::remove_dir_all(&tmp);

        assert!(result.is_err());
        let (msg, code) = result.unwrap_err();
        assert_eq!(code, 2);
        assert!(msg.contains("GRADE=production needs RELEASE_TAG="));
    }

    #[test]
    fn test_resolve_config_production_wrong_prefix() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let saved_grade = env::var("GRADE").ok();
        let saved_release = env::var("RELEASE_TAG").ok();
        let saved_bwd = env::var("BUILD_WORKSPACE_DIRECTORY").ok();
        let saved_sha = env::var("GITHUB_SHA").ok();

        env::set_var("GRADE", "production");
        env::set_var("RELEASE_TAG", "wrong-prefix-v1.0.0");
        env::set_var("GITHUB_SHA", "abc1234567890");
        let tmp = env::temp_dir().join("publish_test_prod_prefix");
        let pkg_dir = tmp.join(PKG);
        let _ = fs::create_dir_all(&pkg_dir);
        let _ = fs::write(
            pkg_dir.join(".release-please-manifest.json"),
            r#"{"packages/peripherals": "1.0.0"}"#,
        );
        env::set_var("BUILD_WORKSPACE_DIRECTORY", tmp.to_string_lossy().as_ref());

        let result = resolve_config();

        match saved_grade {
            Some(v) => env::set_var("GRADE", v),
            None => env::remove_var("GRADE"),
        }
        match saved_release {
            Some(v) => env::set_var("RELEASE_TAG", v),
            None => env::remove_var("RELEASE_TAG"),
        }
        match saved_bwd {
            Some(v) => env::set_var("BUILD_WORKSPACE_DIRECTORY", v),
            None => env::remove_var("BUILD_WORKSPACE_DIRECTORY"),
        }
        match saved_sha {
            Some(v) => env::set_var("GITHUB_SHA", v),
            None => env::remove_var("GITHUB_SHA"),
        }
        let _ = fs::remove_dir_all(&tmp);

        assert!(result.is_err());
        let (msg, code) = result.unwrap_err();
        assert_eq!(code, 2);
        assert!(msg.contains("is not a gravastar-mouse-v* release"));
    }

    #[test]
    fn test_resolve_config_production_version_mismatch() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let saved_grade = env::var("GRADE").ok();
        let saved_release = env::var("RELEASE_TAG").ok();
        let saved_bwd = env::var("BUILD_WORKSPACE_DIRECTORY").ok();
        let saved_sha = env::var("GITHUB_SHA").ok();

        env::set_var("GRADE", "production");
        env::set_var("RELEASE_TAG", "gravastar-mouse-v2.0.0");
        env::set_var("GITHUB_SHA", "abc1234567890");
        let tmp = env::temp_dir().join("publish_test_prod_mismatch");
        let pkg_dir = tmp.join(PKG);
        let _ = fs::create_dir_all(&pkg_dir);
        let _ = fs::write(
            pkg_dir.join(".release-please-manifest.json"),
            r#"{"packages/peripherals": "1.0.0"}"#,
        );
        env::set_var("BUILD_WORKSPACE_DIRECTORY", tmp.to_string_lossy().as_ref());

        let result = resolve_config();

        match saved_grade {
            Some(v) => env::set_var("GRADE", v),
            None => env::remove_var("GRADE"),
        }
        match saved_release {
            Some(v) => env::set_var("RELEASE_TAG", v),
            None => env::remove_var("RELEASE_TAG"),
        }
        match saved_bwd {
            Some(v) => env::set_var("BUILD_WORKSPACE_DIRECTORY", v),
            None => env::remove_var("BUILD_WORKSPACE_DIRECTORY"),
        }
        match saved_sha {
            Some(v) => env::set_var("GITHUB_SHA", v),
            None => env::remove_var("GITHUB_SHA"),
        }
        let _ = fs::remove_dir_all(&tmp);

        assert!(result.is_err());
        let (msg, code) = result.unwrap_err();
        assert_eq!(code, 2);
        assert!(msg.contains("is version 2.0.0, but this checkout is 1.0.0"));
    }

    #[test]
    fn test_resolve_config_beta_defaults() {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let saved_grade = env::var("GRADE").ok();
        let saved_tag = env::var("TAG").ok();
        let saved_bwd = env::var("BUILD_WORKSPACE_DIRECTORY").ok();
        let saved_sha = env::var("GITHUB_SHA").ok();
        let saved_release = env::var("RELEASE_TAG").ok();

        env::set_var("GRADE", "beta");
        env::remove_var("TAG");
        env::set_var("GITHUB_SHA", "abcdef1234567890");
        let tmp = env::temp_dir().join("publish_test_beta_defaults");
        let pkg_dir = tmp.join(PKG);
        let _ = fs::create_dir_all(&pkg_dir);
        let _ = fs::write(
            pkg_dir.join(".release-please-manifest.json"),
            r#"{"packages/peripherals": "1.2.3"}"#,
        );
        env::set_var("BUILD_WORKSPACE_DIRECTORY", tmp.to_string_lossy().as_ref());

        let result = resolve_config();

        match saved_grade {
            Some(v) => env::set_var("GRADE", v),
            None => env::remove_var("GRADE"),
        }
        match saved_tag {
            Some(v) => env::set_var("TAG", v),
            None => env::remove_var("TAG"),
        }
        match saved_bwd {
            Some(v) => env::set_var("BUILD_WORKSPACE_DIRECTORY", v),
            None => env::remove_var("BUILD_WORKSPACE_DIRECTORY"),
        }
        match saved_sha {
            Some(v) => env::set_var("GITHUB_SHA", v),
            None => env::remove_var("GITHUB_SHA"),
        }
        match saved_release {
            Some(v) => env::set_var("RELEASE_TAG", v),
            None => env::remove_var("RELEASE_TAG"),
        }
        let _ = fs::remove_dir_all(&tmp);

        let config = result.unwrap();
        assert_eq!(config.grade, Grade::Beta);
        assert_eq!(config.tag, "gravastar-mouse-beta-latest");
        assert_eq!(config.version, "1.2.3-beta.abcdef1");
        assert_eq!(config.asset_name, "gravastar-mouse-beta-macos.tar.gz");
        assert_eq!(config.manifest_version, "1.2.3");
    }

    #[test]
    fn test_build_flags_without_buildbuddy() {
        let config = PublishConfig {
            workspace_root: PathBuf::from("/tmp"),
            grade: Grade::Beta,
            sha: "abc".to_string(),
            manifest_version: "1.0.0".to_string(),
            tag: "t".to_string(),
            version: "1.0.0".to_string(),
            asset_name: "a.tar.gz".to_string(),
            buildbuddy_api_key: None,
            homebrew_tap_token: None,
        };
        let flags = build_bazel_flags(&config);
        assert_eq!(
            flags,
            vec!["--config=macos-app", "--macos_cpus=arm64,x86_64"]
        );
    }

    #[test]
    fn test_build_flags_with_buildbuddy() {
        let config = PublishConfig {
            workspace_root: PathBuf::from("/tmp"),
            grade: Grade::Beta,
            sha: "abc".to_string(),
            manifest_version: "1.0.0".to_string(),
            tag: "t".to_string(),
            version: "1.0.0".to_string(),
            asset_name: "a.tar.gz".to_string(),
            buildbuddy_api_key: Some("secret123".to_string()),
            homebrew_tap_token: None,
        };
        let flags = build_bazel_flags(&config);
        assert_eq!(
            flags,
            vec![
                "--config=macos-app",
                "--macos_cpus=arm64,x86_64",
                "--config=remotecache-ci",
                "--remote_header=x-buildbuddy-api-key=secret123",
            ]
        );
    }

    #[test]
    fn test_generate_formula() {
        let formula = generate_formula(
            "VitruvianSoftware/vitruvian-core",
            "gravastar-mouse-v1.2.3",
            "gravastar-mouse-1.2.3-macos.tar.gz",
            "1.2.3",
            "abcdef1234567890",
        );
        assert!(formula.contains("class GravastarMouse < Formula"));
        assert!(formula.contains(
            r#"desc "Status light and MCP server for the RGB LED of a GravaStar mouse""#
        ));
        assert!(formula.contains(
            r#"homepage "https://github.com/VitruvianSoftware/vitruvian-core/tree/main/packages/peripherals""#
        ));
        assert!(formula.contains(
            r#"url "https://github.com/VitruvianSoftware/vitruvian-core/releases/download/gravastar-mouse-v1.2.3/gravastar-mouse-1.2.3-macos.tar.gz""#
        ));
        assert!(formula.contains(r#"version "1.2.3""#));
        assert!(formula.contains(r#"sha256 "abcdef1234567890""#));
        assert!(formula.contains(r#"license "MIT""#));
        assert!(formula.contains("depends_on macos: :sonoma"));
        assert!(formula.contains(r#"bin.install "gravastar-mouse""#));
        assert!(formula.contains("assert_equal version.to_s, shell_output"));
        assert!(formula.starts_with(
            "# Generated by packages/peripherals/publish.sh in VitruvianSoftware/vitruvian-core; do not edit here."
        ));
    }

    #[test]
    fn test_manifest_parse() {
        let json = r#"{
  "packages/peripherals": "3.14.1",
  "packages/other": "1.0.0"
}"#;
        assert_eq!(extract_manifest_version(json).unwrap(), "3.14.1");
    }

    #[test]
    fn test_manifest_parse_missing_key() {
        let json = r#"{"packages/other": "1.0.0"}"#;
        assert!(extract_manifest_version(json).is_err());
    }
}
