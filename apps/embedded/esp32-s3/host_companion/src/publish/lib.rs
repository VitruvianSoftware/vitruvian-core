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

//! Rust port of `publish.sh`: build, stamp and publish the ESP32-S3 firmware bundle
//! to a GitHub Release.
//!
//! ONE tool, TWO triggers: the generated `delivery-esp32-s3.yaml` runs it for the
//! `esp32-s3` unit, and the break-glass path is `bazel run //apps/embedded/esp32-s3:publish`.
//! `GRADE` selects the rung:
//!
//!   GRADE=beta        (push to main)  rolling prerelease `esp32-s3-beta-latest`;
//!                     assets are overwritten and the tag is moved to HEAD.
//!   GRADE=production  (release event) attach the assets to the release-please
//!                     release named by `RELEASE_TAG` (esp32-s3-vX.Y.Z).
//!
//! Stamping happens HERE and not in the Bazel genrule: a genrule's action sees
//! neither the workflow's env nor `.git`. The genrule produces the three raw
//! images; this tool wraps them with `build_info.json` and the Rust flash helper
//! sources into `esp32-s3-mac-controller.zip`.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

pub const TAG_PREFIX: &str = "esp32-s3-v";
pub const BETA_TAG: &str = "esp32-s3-beta-latest";
pub const PKG: &str = "apps/embedded/esp32-s3";

/// The flash helper that ships inside the zip (std-only; `rustc` builds it).
pub const FLASH_SOURCES: [(&str, &str); 2] = [
    ("host_companion/src/flash/main.rs", "flash/main.rs"),
    ("host_companion/src/flash/lib.rs", "flash/lib.rs"),
];

pub const FLASH_README: &str = "Flashing the ESP32-S3\n\
\n\
This folder holds the three images (bootloader.bin, partitions.bin, firmware.bin)\n\
and the flasher source in flash/. Build the flasher beside the images and run it:\n\
\n\
  rustc --edition 2021 -O flash/main.rs -o flash-esp32-s3\n\
  ./flash-esp32-s3 [/dev/cu.usbmodemXXXX]\n\
\n\
It writes the images with esptool (installed, via uvx, or python3 -m esptool).\n";

pub trait Runner {
    /// Run to completion with inherited stdio; returns the exit code.
    fn status(&self, program: &str, args: &[String], cwd: &Path) -> Result<i32, String>;
    /// True when the command exits 0 (output discarded).
    fn succeeds(&self, program: &str, args: &[String], cwd: &Path) -> bool;
    /// Trimmed stdout of a command that exited 0.
    fn capture(&self, program: &str, args: &[String], cwd: &Path) -> Option<String>;
    fn var(&self, name: &str) -> Option<String>;
}

pub struct RealRunner;

impl Runner for RealRunner {
    fn status(&self, program: &str, args: &[String], cwd: &Path) -> Result<i32, String> {
        let st = Command::new(program)
            .args(args)
            .current_dir(cwd)
            .status()
            .map_err(|e| format!("failed to run {}: {}", program, e))?;
        Ok(st.code().unwrap_or(1))
    }
    fn succeeds(&self, program: &str, args: &[String], cwd: &Path) -> bool {
        Command::new(program)
            .args(args)
            .current_dir(cwd)
            .stdin(std::process::Stdio::null())
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .status()
            .map(|s| s.success())
            .unwrap_or(false)
    }
    fn capture(&self, program: &str, args: &[String], cwd: &Path) -> Option<String> {
        let out = Command::new(program)
            .args(args)
            .current_dir(cwd)
            .output()
            .ok()?;
        if !out.status.success() {
            return None;
        }
        Some(String::from_utf8_lossy(&out.stdout).trim().to_string())
    }
    fn var(&self, name: &str) -> Option<String> {
        std::env::var(name).ok()
    }
}

#[derive(Debug, Clone)]
pub struct PublishConfig {
    pub root: PathBuf,
    pub grade: String,
    pub sha: String,
    pub tag: String,
    pub version: String,
    pub is_beta: bool,
}

fn sv(v: &[&str]) -> Vec<String> {
    v.iter().map(|s| s.to_string()).collect()
}

/// `${BUILD_WORKSPACE_DIRECTORY:-$(git rev-parse --show-toplevel || pwd)}`.
pub fn resolve_root(r: &dyn Runner) -> PathBuf {
    let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
    if let Some(ws) = r.var("BUILD_WORKSPACE_DIRECTORY").filter(|w| !w.is_empty()) {
        return PathBuf::from(ws);
    }
    r.capture("git", &sv(&["rev-parse", "--show-toplevel"]), &cwd)
        .filter(|s| !s.is_empty())
        .map(PathBuf::from)
        .unwrap_or(cwd)
}

pub fn resolve_config(r: &dyn Runner) -> Result<PublishConfig, String> {
    let root = resolve_root(r);
    let grade = r
        .var("GRADE")
        .filter(|g| !g.is_empty())
        .unwrap_or_else(|| "beta".into());
    let sha = match r.var("GITHUB_SHA").filter(|s| !s.is_empty()) {
        Some(s) => s,
        None => r
            .capture("git", &sv(&["rev-parse", "HEAD"]), &root)
            .ok_or("git rev-parse HEAD failed and GITHUB_SHA is unset")?,
    };
    let short_sha = &sha[..7.min(sha.len())];
    let manifest_ver = read_manifest_version(&root)?;

    let (tag, version) = match grade.as_str() {
        "beta" => (
            r.var("TAG")
                .filter(|t| !t.is_empty())
                .unwrap_or_else(|| BETA_TAG.into()),
            format!("{}-beta.{}", manifest_ver, short_sha),
        ),
        "production" => {
            // A dispatch of the production rung carries no release event, and
            // re-uploading a release's assets from a different commit would silently
            // replace what was released. Require the tag; never guess it.
            let tag = r.var("RELEASE_TAG").unwrap_or_default();
            if tag.is_empty() {
                return Err(format!(
                    "publish: GRADE=production needs RELEASE_TAG={}X.Y.Z (the release-please tag); refusing to guess",
                    TAG_PREFIX
                ));
            }
            if !tag.starts_with(TAG_PREFIX) {
                return Err(format!(
                    "publish: RELEASE_TAG={} is not an {}* release; another component's release reached this rung",
                    tag, TAG_PREFIX
                ));
            }
            let version = tag[TAG_PREFIX.len()..].to_string();
            (tag, version)
        }
        other => {
            return Err(format!(
                "publish: unknown GRADE={} (beta|production)",
                other
            ))
        }
    };

    Ok(PublishConfig {
        root,
        is_beta: grade == "beta",
        grade,
        sha,
        tag,
        version,
    })
}

/// `jq -r '."apps/embedded/esp32-s3"' <pkg>/.release-please-manifest.json`; like jq under
/// `set -e`, a missing file or key is an error (never a made-up `0.0.0`).
pub fn read_manifest_version(root: &Path) -> Result<String, String> {
    let path = root.join(PKG).join(".release-please-manifest.json");
    let content =
        fs::read_to_string(&path).map_err(|e| format!("read {}: {}", path.display(), e))?;
    let key = format!("\"{}\"", PKG);
    let at = content
        .find(&key)
        .ok_or_else(|| format!("{}: no {} entry", path.display(), key))?;
    let rest = content[at + key.len()..].trim_start();
    let rest = rest
        .strip_prefix(':')
        .ok_or_else(|| format!("{}: malformed {} entry", path.display(), key))?
        .trim_start();
    let rest = rest
        .strip_prefix('"')
        .ok_or_else(|| format!("{}: {} is not a string", path.display(), key))?;
    let end = rest
        .find('"')
        .ok_or_else(|| format!("{}: unterminated version", path.display()))?;
    Ok(rest[..end].to_string())
}

pub fn build_info_json(cfg: &PublishConfig, built_at: &str) -> String {
    format!(
        "{{\n  \"version\": \"{}\",\n  \"grade\": \"{}\",\n  \"commit\": \"{}\",\n  \"builtAt\": \"{}\",\n  \"board\": \"Waveshare ESP32-S3-Touch-LCD-1.69\",\n  \"mcu\": \"ESP32-S3\",\n  \"flash_size\": \"16MB\",\n  \"framework\": \"arduino\",\n  \"lvgl_version\": \"8.4.0\"\n}}\n",
        cfg.version, cfg.grade, cfg.sha, built_at
    )
}

pub fn beta_notes(cfg: &PublishConfig, built_at: &str) -> String {
    format!(
        "Latest Beta Firmware Build: {}\nCommit: {}\nBuilt: {}\n\nArtifacts Included:\n* firmware.bin: Application binary (Flash at 0x10000)\n* bootloader.bin: ESP32-S3 second-stage bootloader (Flash at 0x0000)\n* partitions.bin: 16MB partition table (Flash at 0x8000)\n* build_info.json: version / grade / commit stamp\n* esp32-s3-mac-controller.zip: Full flashable archive with the Rust flash helper (flash/).",
        cfg.version, cfg.sha, built_at
    )
}

fn run(r: &dyn Runner, prog: &str, args: &[String], cwd: &Path, what: &str) -> Result<(), String> {
    match r.status(prog, args, cwd)? {
        0 => Ok(()),
        c => Err(format!("{} failed (exit {})", what, c)),
    }
}

fn work_dir(r: &dyn Runner) -> PathBuf {
    let base = match r.var("RUNNER_TEMP").filter(|t| !t.is_empty()) {
        Some(t) => PathBuf::from(t),
        None => {
            let nanos = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.as_nanos())
                .unwrap_or(0);
            std::env::temp_dir().join(format!("esp32-s3-publish-{}-{}", std::process::id(), nanos))
        }
    };
    base.join("esp32-s3-dist")
}

fn make_writable(p: &Path) -> Result<(), String> {
    let mut perm = fs::metadata(p)
        .map_err(|e| format!("stat {}: {}", p.display(), e))?
        .permissions();
    #[allow(clippy::permissions_set_readonly_false)]
    perm.set_readonly(false);
    fs::set_permissions(p, perm).map_err(|e| format!("chmod {}: {}", p.display(), e))
}

pub fn publish(cfg: &PublishConfig, r: &dyn Runner) -> Result<(), String> {
    eprintln!(
        "=== esp32-s3 publish: grade={} version={} tag={} commit={} ===",
        cfg.grade, cfg.version, cfg.tag, cfg.sha
    );
    let root = &cfg.root;

    run(
        r,
        "bazel",
        &sv(&["build", &format!("//{}:firmware", PKG)]),
        root,
        "bazel build firmware",
    )?;

    let work = work_dir(r);
    let _ = fs::remove_dir_all(&work);
    fs::create_dir_all(&work).map_err(|e| format!("mkdir {}: {}", work.display(), e))?;
    for img in ["firmware", "bootloader", "partitions"] {
        let src = root.join(format!("bazel-bin/{}/{}.bin", PKG, img));
        let dst = work.join(format!("{}.bin", img));
        fs::copy(&src, &dst).map_err(|e| format!("copy {}: {}", src.display(), e))?;
        make_writable(&dst)?;
    }
    // The flasher ships as source (std-only) so it builds natively on the user's
    // Mac; the release job runs on Linux and cannot cross-build a macOS binary.
    fs::create_dir_all(work.join("flash")).map_err(|e| format!("mkdir flash: {}", e))?;
    for (from, to) in FLASH_SOURCES {
        let src = root.join(PKG).join(from);
        fs::copy(&src, work.join(to)).map_err(|e| format!("copy {}: {}", src.display(), e))?;
    }
    fs::write(work.join("flash/README.txt"), FLASH_README)
        .map_err(|e| format!("write README: {}", e))?;

    let built_at = r
        .capture("date", &sv(&["-u", "+%Y-%m-%dT%H:%M:%SZ"]), root)
        .ok_or("date -u failed")?;
    fs::write(
        work.join("build_info.json"),
        build_info_json(cfg, &built_at),
    )
    .map_err(|e| format!("write build_info.json: {}", e))?;

    let zip = work.join("esp32-s3-mac-controller.zip");
    let mut zip_args = sv(&["-q", zip.to_str().unwrap_or("")]);
    zip_args.extend(sv(&[
        "firmware.bin",
        "bootloader.bin",
        "partitions.bin",
        "build_info.json",
        "flash/main.rs",
        "flash/lib.rs",
        "flash/README.txt",
    ]));
    run(r, "zip", &zip_args, &work, "zip")?;

    if cfg.is_beta && !r.succeeds("gh", &sv(&["release", "view", &cfg.tag]), root) {
        run(
            r,
            "gh",
            &sv(&[
                "release",
                "create",
                &cfg.tag,
                "--prerelease",
                "--target",
                &cfg.sha,
                "--title",
                "ESP32-S3 Firmware (Beta Rolling Release)",
                "--notes",
                "Rolling pre-release built automatically from commits landing on main.",
            ]),
            root,
            "gh release create",
        )?;
    }

    let mut upload = sv(&["release", "upload", &cfg.tag]);
    for f in [
        "firmware.bin",
        "bootloader.bin",
        "partitions.bin",
        "build_info.json",
    ] {
        upload.push(work.join(f).to_string_lossy().to_string());
    }
    upload.push(zip.to_string_lossy().to_string());
    upload.push("--clobber".into());
    run(r, "gh", &upload, root, "gh release upload")?;

    if cfg.is_beta {
        // Move the rolling tag to the commit whose assets now sit on the release, so
        // the release page's compare/source links agree with build_info.json. A
        // failure here is a real failure, not something to paper over.
        run(
            r,
            "gh",
            &sv(&[
                "api",
                "-X",
                "PATCH",
                &format!("repos/{{owner}}/{{repo}}/git/refs/tags/{}", cfg.tag),
                "-f",
                &format!("sha={}", cfg.sha),
                "-F",
                "force=true",
            ]),
            root,
            "gh api PATCH tag",
        )?;
        run(
            r,
            "gh",
            &sv(&[
                "release",
                "edit",
                &cfg.tag,
                "--notes",
                &beta_notes(cfg, &built_at),
            ]),
            root,
            "gh release edit",
        )?;
    }

    eprintln!(
        "=== esp32-s3 publish complete: {} ({}, {}) ===",
        cfg.tag, cfg.version, cfg.grade
    );
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::RefCell;
    use std::collections::HashMap;

    type Call = (String, Vec<String>, PathBuf);

    struct Fake {
        vars: HashMap<String, String>,
        calls: RefCell<Vec<Call>>,
        root: PathBuf,
        release_exists: bool,
        fail: Option<&'static str>, // fail when args join contains this
    }

    impl Fake {
        fn new(root: &Path, vars: &[(&str, &str)]) -> Self {
            Fake {
                vars: vars
                    .iter()
                    .map(|(k, v)| (k.to_string(), v.to_string()))
                    .collect(),
                calls: RefCell::new(vec![]),
                root: root.to_path_buf(),
                release_exists: false,
                fail: None,
            }
        }
        fn log(&self, p: &str, a: &[String], c: &Path) {
            self.calls
                .borrow_mut()
                .push((p.into(), a.to_vec(), c.to_path_buf()));
        }
        fn lines(&self) -> Vec<String> {
            self.calls
                .borrow()
                .iter()
                .map(|(p, a, _)| format!("{} {}", p, a.join(" ")))
                .collect()
        }
    }

    impl Runner for Fake {
        fn status(&self, p: &str, a: &[String], c: &Path) -> Result<i32, String> {
            self.log(p, a, c);
            if p == "bazel" {
                // Like a real build: the three images appear under bazel-bin.
                let d = self.root.join(format!("bazel-bin/{}", PKG));
                fs::create_dir_all(&d).unwrap();
                for i in ["firmware", "bootloader", "partitions"] {
                    fs::write(d.join(format!("{}.bin", i)), format!("IMG:{}", i)).unwrap();
                }
            }
            if let Some(f) = self.fail {
                if format!("{} {}", p, a.join(" ")).contains(f) {
                    return Ok(1);
                }
            }
            Ok(0)
        }
        fn succeeds(&self, p: &str, a: &[String], c: &Path) -> bool {
            self.log(p, a, c);
            self.release_exists
        }
        fn capture(&self, p: &str, a: &[String], _c: &Path) -> Option<String> {
            match p {
                "date" => Some("2026-01-02T03:04:05Z".into()),
                "git" if a.contains(&"HEAD".to_string()) => Some("f".repeat(40)),
                _ => None,
            }
        }
        fn var(&self, n: &str) -> Option<String> {
            self.vars.get(n).cloned()
        }
    }

    fn tmpdir(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("pub-test-{}-{}", name, std::process::id()));
        let _ = fs::remove_dir_all(&d);
        fs::create_dir_all(&d).unwrap();
        d
    }

    /// A fake workspace: manifest + the flash helper sources.
    fn workspace(name: &str) -> PathBuf {
        let root = tmpdir(name);
        let pkg = root.join(PKG);
        fs::create_dir_all(pkg.join("host_companion/src/flash")).unwrap();
        fs::write(
            pkg.join(".release-please-manifest.json"),
            "{\n  \"apps/embedded/esp32-s3\": \"0.1.12\"\n}\n",
        )
        .unwrap();
        fs::write(pkg.join("host_companion/src/flash/main.rs"), "// main").unwrap();
        fs::write(pkg.join("host_companion/src/flash/lib.rs"), "// lib").unwrap();
        root
    }

    fn cfg(root: &Path, grade: &str) -> PublishConfig {
        let beta = grade == "beta";
        PublishConfig {
            root: root.to_path_buf(),
            grade: grade.into(),
            sha: "abcdef1234567890abcdef1234567890abcdef12".into(),
            tag: if beta {
                BETA_TAG.into()
            } else {
                "esp32-s3-v2.0.0".into()
            },
            version: if beta {
                "0.1.12-beta.abcdef1".into()
            } else {
                "2.0.0".into()
            },
            is_beta: beta,
        }
    }

    fn envs(root: &Path, extra: &[(&str, &str)]) -> Fake {
        let mut v = vec![
            ("BUILD_WORKSPACE_DIRECTORY", root.to_str().unwrap()),
            ("GITHUB_SHA", "abcdef1234567890"),
        ];
        v.extend_from_slice(extra);
        Fake::new(root, &v)
    }

    #[test]
    fn beta_defaults() {
        let root = workspace("beta-cfg");
        let c = resolve_config(&envs(&root, &[("GRADE", "beta")])).unwrap();
        assert!(c.is_beta);
        assert_eq!(c.tag, BETA_TAG);
        assert_eq!(c.version, "0.1.12-beta.abcdef1");
        // grade defaults to beta
        assert_eq!(resolve_config(&envs(&root, &[])).unwrap().grade, "beta");
    }

    #[test]
    fn production_rules() {
        let root = workspace("prod-cfg");
        let c = resolve_config(&envs(
            &root,
            &[("GRADE", "production"), ("RELEASE_TAG", "esp32-s3-v3.1.0")],
        ))
        .unwrap();
        assert!(!c.is_beta);
        assert_eq!(c.version, "3.1.0");
        let e = resolve_config(&envs(&root, &[("GRADE", "production")])).unwrap_err();
        assert!(e.contains("refusing to guess"));
        let e = resolve_config(&envs(
            &root,
            &[("GRADE", "production"), ("RELEASE_TAG", "tabula-v1.0.0")],
        ))
        .unwrap_err();
        assert!(e.contains("is not an esp32-s3-v*"));
        let e = resolve_config(&envs(&root, &[("GRADE", "staging")])).unwrap_err();
        assert!(e.contains("unknown GRADE=staging"));
    }

    #[test]
    fn manifest_is_required() {
        let root = tmpdir("nomanifest");
        assert!(read_manifest_version(&root).is_err());
        let pkg = root.join(PKG);
        fs::create_dir_all(&pkg).unwrap();
        fs::write(pkg.join(".release-please-manifest.json"), "{}").unwrap();
        assert!(read_manifest_version(&root).is_err());
        fs::write(
            pkg.join(".release-please-manifest.json"),
            "{\"apps/embedded/esp32-s3\":\"1.2.3\"}",
        )
        .unwrap();
        assert_eq!(read_manifest_version(&root).unwrap(), "1.2.3");
    }

    #[test]
    fn beta_publish_runs_the_full_shell_sequence() {
        let root = workspace("beta-run");
        let f = envs(
            &root,
            &[("RUNNER_TEMP", root.join("tmp").to_str().unwrap())],
        );
        let c = cfg(&root, "beta");
        publish(&c, &f).unwrap();

        let l = f.lines();
        let sha = &c.sha;
        // (a) it builds the firmware itself
        assert_eq!(l[0], format!("bazel build //{}:firmware", PKG));
        // zip bundles images + stamp + flash helper (c: the old zip shipped flash.sh)
        let zip = l.iter().find(|x| x.starts_with("zip ")).expect("zip step");
        assert!(zip.contains("esp32-s3-mac-controller.zip firmware.bin bootloader.bin partitions.bin build_info.json flash/main.rs flash/lib.rs flash/README.txt"), "{}", zip);
        // release view -> create (release absent)
        assert!(l.contains(&format!("gh release view {}", BETA_TAG)));
        assert!(l.iter().any(|x| x.starts_with(&format!("gh release create {} --prerelease --target {} --title ESP32-S3 Firmware (Beta Rolling Release) --notes", BETA_TAG, sha))));
        // five assets uploaded with --clobber
        let up = l
            .iter()
            .find(|x| x.starts_with("gh release upload"))
            .unwrap();
        for n in [
            "firmware.bin",
            "bootloader.bin",
            "partitions.bin",
            "build_info.json",
            "esp32-s3-mac-controller.zip",
            "--clobber",
        ] {
            assert!(up.contains(n), "upload missing {}: {}", n, up);
        }
        // (c) the rolling tag is moved and the notes are edited, after the upload
        let iu = l
            .iter()
            .position(|x| x.starts_with("gh release upload"))
            .unwrap();
        let ip = l.iter().position(|x| x == &format!("gh api -X PATCH repos/{{owner}}/{{repo}}/git/refs/tags/{} -f sha={} -F force=true", BETA_TAG, sha)).expect("tag PATCH");
        let ie = l
            .iter()
            .position(|x| {
                x.starts_with(&format!(
                    "gh release edit {} --notes Latest Beta Firmware Build: 0.1.12-beta.abcdef1",
                    BETA_TAG
                ))
            })
            .expect("release edit");
        assert!(iu < ip && ip < ie);
        assert!(l[ie].contains("Built: 2026-01-02T03:04:05Z"));
        assert!(l[ie].contains("esp32-s3-mac-controller.zip"));
    }

    #[test]
    fn staged_bundle_contents_and_build_info() {
        let root = workspace("bundle");
        let tmp = root.join("tmp");
        let f = envs(&root, &[("RUNNER_TEMP", tmp.to_str().unwrap())]);
        publish(&cfg(&root, "beta"), &f).unwrap();
        let w = tmp.join("esp32-s3-dist");
        for (n, want) in [
            ("firmware.bin", "IMG:firmware"),
            ("bootloader.bin", "IMG:bootloader"),
            ("partitions.bin", "IMG:partitions"),
            ("flash/main.rs", "// main"),
            ("flash/lib.rs", "// lib"),
        ] {
            assert_eq!(fs::read_to_string(w.join(n)).unwrap(), want, "{}", n);
        }
        assert!(w.join("flash/README.txt").is_file());
        // (b) build_info.json is written, with the shell's exact shape
        let bi = fs::read_to_string(w.join("build_info.json")).unwrap();
        assert_eq!(bi, "{\n  \"version\": \"0.1.12-beta.abcdef1\",\n  \"grade\": \"beta\",\n  \"commit\": \"abcdef1234567890abcdef1234567890abcdef12\",\n  \"builtAt\": \"2026-01-02T03:04:05Z\",\n  \"board\": \"Waveshare ESP32-S3-Touch-LCD-1.69\",\n  \"mcu\": \"ESP32-S3\",\n  \"flash_size\": \"16MB\",\n  \"framework\": \"arduino\",\n  \"lvgl_version\": \"8.4.0\"\n}\n");
    }

    #[test]
    fn existing_beta_release_is_not_recreated() {
        let root = workspace("exists");
        let mut f = envs(
            &root,
            &[("RUNNER_TEMP", root.join("tmp").to_str().unwrap())],
        );
        f.release_exists = true;
        publish(&cfg(&root, "beta"), &f).unwrap();
        assert!(!f.lines().iter().any(|x| x.starts_with("gh release create")));
    }

    #[test]
    fn production_uploads_only_and_never_touches_the_tag_or_notes() {
        let root = workspace("prod-run");
        let f = envs(
            &root,
            &[("RUNNER_TEMP", root.join("tmp").to_str().unwrap())],
        );
        publish(&cfg(&root, "production"), &f).unwrap();
        let l = f.lines();
        assert!(l
            .iter()
            .any(|x| x.starts_with("gh release upload esp32-s3-v2.0.0")));
        assert!(!l.iter().any(|x| x.contains("release view")
            || x.contains("release create")
            || x.contains("api -X PATCH")
            || x.contains("release edit")));
    }

    #[test]
    fn tag_move_failure_is_a_real_failure() {
        let root = workspace("patchfail");
        let mut f = envs(
            &root,
            &[("RUNNER_TEMP", root.join("tmp").to_str().unwrap())],
        );
        f.fail = Some("api -X PATCH");
        let e = publish(&cfg(&root, "beta"), &f).unwrap_err();
        assert!(e.contains("gh api PATCH tag"));
        assert!(!f.lines().iter().any(|x| x.starts_with("gh release edit")));
    }

    #[test]
    fn a_failed_bazel_build_stops_everything() {
        let root = workspace("bazelfail");
        let mut f = envs(
            &root,
            &[("RUNNER_TEMP", root.join("tmp").to_str().unwrap())],
        );
        f.fail = Some("bazel build");
        assert!(publish(&cfg(&root, "beta"), &f).is_err());
        assert!(!f.lines().iter().any(|x| x.starts_with("gh ")));
    }

    #[test]
    fn upload_failure_is_reported_before_the_tag_moves() {
        let root = workspace("uploadfail");
        let mut f = envs(
            &root,
            &[("RUNNER_TEMP", root.join("tmp").to_str().unwrap())],
        );
        f.fail = Some("release upload");
        assert!(publish(&cfg(&root, "beta"), &f).is_err());
        assert!(!f.lines().iter().any(|x| x.contains("api -X PATCH")));
    }

    #[test]
    fn gh_runs_from_the_workspace_root() {
        let root = workspace("cwd");
        let f = envs(
            &root,
            &[("RUNNER_TEMP", root.join("tmp").to_str().unwrap())],
        );
        publish(&cfg(&root, "beta"), &f).unwrap();
        for (p, _, cwd) in f.calls.borrow().iter() {
            if p == "gh" || p == "bazel" {
                assert_eq!(cwd, &root);
            }
        }
    }
}
