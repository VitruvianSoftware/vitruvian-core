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

//! The package-desktop.sh driver: options, staging, signing, notarization,
//! DMG / ZIP packaging, checksums, the Homebrew Cask, the GitHub Release
//! upload and read-back, the tap update and the downloads sync.
//!
//! Each step runs the programs the script runs (ditto, codesign, hdiutil,
//! lipo, xcrun, gh, git, python3, shasum, and the coreutils that change the
//! file system), with the same arguments, in the same order, and prints the
//! same lines. A step that fails ends the run with that step's status, as
//! `set -e` does, after the staging directory is removed.

use std::fs;
use std::io::Write;
use std::process::{Command, Stdio};

use crate::helpers::{
    basename, cask_name_for_app, clean_version, developer_id_from, dirname, first_fields,
    generate_cask_ruby, missing_assets, required_release_assets,
};
use crate::shell::{
    chomp, cmd, cmd_quiet, command_v, env, err, glob, has, is_dir, is_file, is_nonempty,
    logical_path, mktemp_d, out, out_raw, shell_pwd, Shell, Step,
};

/// `usage`'s text, as the script's heredoc holds it.
pub const USAGE: &str = r#"Usage:
  package-desktop.sh [options]

Standardized packaging script for macOS desktop applications in apps/desktop/.
Produces the full 6-point distribution contract:
  1. Universal DMG (<App>-<version>-universal.dmg)
  2. Apple Silicon DMG (<App>-<version>-arm64.dmg)
  3. Intel x86_64 DMG (<App>-<version>-x86_64.dmg)
  4. Universal ZIP (<App>-<version>-universal.zip)
  5. Homebrew Cask formula in VitruvianSoftware/homebrew-tap (Casks/<app>.rb)
  6. Sync to downloads catalog via tools/sync-downloads/sync_downloads.py

Options:
  --app-path <path>       Path to built .app bundle (e.g. dist/HomeSpeaker.app)
  --archive <path>        Path to Bazel-produced .zip archive containing .app bundle
  --app-name <name>       Application name (e.g. HomeSpeaker, Vitruvian, NexusAgent)
  --version <version>     Release version (e.g. 1.11.0). Inferred from Info.plist if omitted.
  --dist-dir <dir>        Directory to store release artifacts (default: ./dist)
  --cask-name <name>      Homebrew Cask name (default: kebab-case of app-name)
  --cask-desc <desc>      Description for Homebrew Cask formula
  --cask-homepage <url>   Homepage URL for Homebrew Cask formula
  --entitlements <path>   Path to entitlements plist file for codesigning
  --repo <owner/repo>     GitHub repository (default: VitruvianSoftware/vitruvian-core)
  --tag <tag>             GitHub Release tag (e.g. home-speaker-v1.11.0)
  --skip-signing          Skip codesigning
  --skip-dmg              Skip DMG generation (useful for testing environments)
  --skip-thinning         Skip lipo thinning (arm64/x86_64 DMGs)
  --sync-downloads        Run tools/sync-downloads/sync_downloads.py after packaging
  --dry-run               Package artifacts locally and verify; do not upload to GitHub or push to tap
  --require-asset <name>  Also require <name> (and <name>.sha256) among the artifacts; repeatable.
                          For a file the caller put in --dist-dir itself, named <App>-<version>*.zip|dmg
  --verify-only           Package nothing: only check that every expected artifact exists, on the
                          GitHub Release when --tag is given without --dry-run, else in --dist-dir.
                          Needs --app-name and --version (or --tag). Exits non-zero naming what is missing.
  --help                  Show this help message
"#;

/// The options, after parsing.
#[derive(Debug, Clone, Default)]
pub struct Opts {
    pub app_path: String,
    pub archive: String,
    pub app_name: String,
    pub version: String,
    pub dist_dir: String,
    pub cask_name: String,
    pub cask_desc: String,
    pub cask_homepage: String,
    pub entitlements: String,
    pub repo: String,
    pub tag: String,
    pub skip_signing: bool,
    pub skip_dmg: bool,
    pub skip_thinning: bool,
    pub sync_downloads: bool,
    pub dry_run: bool,
    pub verify_only: bool,
    pub require_assets: Vec<String>,
}

/// What parsing asks for instead of a run.
#[derive(Debug, PartialEq)]
pub enum Parsed {
    Run,
    /// `usage <code>`: print the help, exit with the code.
    Usage(i32),
    /// bash stopped (an option missing its value): exit with the status.
    Exit(i32),
}

/// The line of the script that reads each value-taking option's "$2".
fn value_line(option: &str) -> Option<u32> {
    Some(match option {
        "--app-path" => 496,
        "--archive" => 500,
        "--app-name" => 504,
        "--version" => 508,
        "--dist-dir" => 512,
        "--cask-name" => 516,
        "--cask-desc" => 520,
        "--cask-homepage" => 524,
        "--entitlements" => 528,
        "--repo" => 532,
        "--tag" => 536,
        "--require-asset" => 560,
        _ => return None,
    })
}

/// The option loop, with the script's defaults (GITHUB_REPOSITORY, TAG and
/// RELEASE_TAG from the environment).
pub fn parse(argv0: &str, args: &[String], o: &mut Opts) -> Parsed {
    o.dist_dir = "dist".to_string();
    o.repo = {
        let r = env("GITHUB_REPOSITORY");
        if r.is_empty() {
            "VitruvianSoftware/vitruvian-core".to_string()
        } else {
            r
        }
    };
    o.tag = {
        let t = env("TAG");
        if t.is_empty() {
            env("RELEASE_TAG")
        } else {
            t
        }
    };
    let mut i = 0;
    while i < args.len() {
        let a = args[i].as_str();
        if let Some(line) = value_line(a) {
            let Some(v) = args.get(i + 1).cloned() else {
                err(&format!("{argv0}: line {line}: $2: unbound variable"));
                return Parsed::Exit(1);
            };
            match a {
                "--app-path" => o.app_path = v,
                "--archive" => o.archive = v,
                "--app-name" => o.app_name = v,
                "--version" => o.version = v,
                "--dist-dir" => o.dist_dir = v,
                "--cask-name" => o.cask_name = v,
                "--cask-desc" => o.cask_desc = v,
                "--cask-homepage" => o.cask_homepage = v,
                "--entitlements" => o.entitlements = v,
                "--repo" => o.repo = v,
                "--tag" => o.tag = v,
                _ => o.require_assets.push(v),
            }
            i += 2;
            continue;
        }
        match a {
            "--skip-signing" => o.skip_signing = true,
            "--skip-dmg" => o.skip_dmg = true,
            "--skip-thinning" => o.skip_thinning = true,
            "--sync-downloads" => o.sync_downloads = true,
            "--dry-run" => o.dry_run = true,
            "--verify-only" => o.verify_only = true,
            "-h" | "--help" => return Parsed::Usage(0),
            _ => {
                err(&format!("Unknown option: {a}"));
                return Parsed::Usage(1);
            }
        }
        i += 1;
    }
    Parsed::Run
}

/// One packaging run.
pub struct Driver {
    pub sh: Shell,
    pub o: Opts,
    /// The path the program was started by (bash's ${BASH_SOURCE[0]}).
    pub program: String,
    pub stage_root: String,
}

impl Driver {
    fn run_line(&self, line: u32, program: &str, args: &[&str]) -> Step {
        self.sh.must(line, &mut cmd(program, args))
    }

    // --------------------------------------------------------------------
    // Operational helpers
    // --------------------------------------------------------------------

    /// copy_bundle: replace `dst` with a copy of `src` (ditto, else cp -R).
    pub fn copy_bundle(&self, src: &str, dst: &str) -> Step {
        self.run_line(216, "rm", &["-rf", dst])?;
        self.run_line(217, "mkdir", &["-p", &dirname(dst)])?;
        if has("ditto") {
            self.run_line(219, "ditto", &[src, dst])
        } else {
            self.run_line(221, "cp", &["-R", src, dst])
        }
    }

    /// find_macho_binaries: every regular file under the bundle, depth
    /// first in `find -depth -type f` order, that `file -b` calls Mach-O.
    pub fn find_macho_binaries(&self, bundle: &str) -> Vec<String> {
        if !is_dir(bundle) {
            return Vec::new();
        }
        let (found, _) = self.sh.capture(
            0,
            &mut cmd_quiet("find", &[bundle, "-depth", "-type", "f"]),
            true,
        );
        chomp(found)
            .split('\n')
            .filter(|f| !f.is_empty())
            .map(|f| f.to_string())
            .filter(|f| {
                let (o, code) = self.sh.capture(0, &mut cmd_quiet("file", &["-b", f]), true);
                code == 0 && o.contains("Mach-O")
            })
            .collect()
    }

    /// thin_bundle: lipo every universal Mach-O in the bundle down to `arch`.
    pub fn thin_bundle(&self, bundle: &str, arch: &str) -> Step {
        out(&format!("==> Thinning {bundle} to {arch}..."));
        if !has("lipo") {
            out("    lipo not found, skipping architecture thinning");
            return Ok(());
        }
        for bin in self.find_macho_binaries(bundle) {
            let (info, code) = self
                .sh
                .capture(0, &mut cmd_quiet("lipo", &["-info", &bin]), true);
            if code != 0 || !info.split('\n').any(|l| l.contains(arch)) {
                continue;
            }
            let (info, code) = self
                .sh
                .capture(0, &mut cmd_quiet("lipo", &["-info", &bin]), true);
            let fat = info.split('\n').any(|l| {
                let a = l.find("arm64");
                let x = l.find("x86_64");
                matches!((a, l.rfind("x86_64")), (Some(i), Some(j)) if j > i)
                    || matches!((x, l.rfind("arm64")), (Some(i), Some(j)) if j > i)
            });
            if code == 0 && fat {
                self.run_line(250, "lipo", &[&bin, "-thin", arch, "-output", &bin])?;
                out(&format!("    Thinned: {} -> {arch}", basename(&bin, "")));
            }
        }
        Ok(())
    }

    /// The Developer ID in the keychain, as the script's pipeline finds it.
    fn keychain_identity(&self) -> String {
        let (listing, _) = self.sh.capture(
            0,
            &mut cmd_quiet("security", &["find-identity", "-v", "-p", "codesigning"]),
            true,
        );
        developer_id_from(&listing)
    }

    /// sign_bundle: sign nested Mach-O files inside out, then the bundle,
    /// with the Developer ID (SIGNING_IDENTITY or the keychain's) or ad hoc.
    pub fn sign_bundle(&self, bundle: &str, entitlements: &str) -> Step {
        let mut identity = env("SIGNING_IDENTITY");
        if !has("codesign") {
            out("    codesign not found, skipping code signing");
            return Ok(());
        }
        if identity.is_empty() {
            identity = self.keychain_identity();
        }
        // Bazel or unpacked outputs may be read-only and carry quarantine bits.
        self.sh
            .status(0, &mut cmd_quiet("chmod", &["-R", "u+w", bundle]), true);
        self.sh.status(
            0,
            &mut cmd_quiet("find", &[bundle, "-exec", "xattr", "-c", "{}", "+"]),
            true,
        );

        for bin in self.find_macho_binaries(bundle) {
            if bin.contains("/MacOS/") {
                continue;
            }
            if identity.is_empty() {
                self.run_line(284, "codesign", &["--force", "--sign", "-", &bin])?;
            } else {
                self.run_line(
                    282,
                    "codesign",
                    &[
                        "--force",
                        "--options",
                        "runtime",
                        "--timestamp",
                        "--sign",
                        &identity,
                        &bin,
                    ],
                )?;
            }
        }

        let ent: Vec<&str> = if !entitlements.is_empty() && is_file(entitlements) {
            vec!["--entitlements", entitlements]
        } else {
            Vec::new()
        };
        if identity.is_empty() {
            out(&format!(
                "==> No Developer ID found; signing ad-hoc: {bundle}"
            ));
            let mut a = vec!["--force"];
            a.extend(&ent);
            a.extend(["--sign", "-", bundle]);
            self.run_line(303, "codesign", &a)?;
        } else {
            out(&format!(
                "==> Signing {bundle} with Developer ID: {identity}"
            ));
            let mut a = vec!["--force", "--options", "runtime", "--timestamp"];
            a.extend(&ent);
            a.extend(["--sign", identity.as_str(), bundle]);
            self.run_line(300, "codesign", &a)?;
        }
        self.run_line(306, "codesign", &["--verify", "--deep", "--strict", bundle])
    }

    /// create_dmg: a compressed DMG of the app beside an /Applications link,
    /// signed with the Developer ID if there is one, then notarized.
    pub fn create_dmg(&self, app: &str, out_dmg: &str, volname: &str) -> Step {
        if !has("hdiutil") {
            out(&format!(
                "    hdiutil not found, skipping DMG creation: {out_dmg}"
            ));
            return Ok(());
        }
        out(&format!(
            "==> Creating DMG: {out_dmg} (volume: {volname})..."
        ));
        let work = mktemp_d()?;
        let stage = mktemp_d()?;
        self.copy_bundle(app, &format!("{stage}/{}", basename(app, "")))?;
        self.run_line(
            325,
            "ln",
            &["-s", "/Applications", &format!("{stage}/Applications")],
        )?;

        let rw = format!("{work}/rw.dmg");
        self.sh.status(
            0,
            &mut cmd_quiet(
                "hdiutil",
                &["detach", &format!("/Volumes/{volname}"), "-force"],
            ),
            true,
        );
        let mut created = false;
        for attempt in 1..=3 {
            let code = self.sh.status(
                332,
                &mut cmd(
                    "hdiutil",
                    &[
                        "create",
                        "-volname",
                        volname,
                        "-srcfolder",
                        &stage,
                        "-fs",
                        "HFS+",
                        "-format",
                        "UDRW",
                        "-ov",
                        &rw,
                        "-quiet",
                    ],
                ),
                false,
            );
            if code == 0 {
                created = true;
                break;
            }
            err(&format!(
                "    hdiutil create attempt {attempt} failed, retrying..."
            ));
            self.run_line(337, "rm", &["-f", &rw])?;
            self.run_line(338, "sleep", &["2"])?;
        }
        if !created {
            err(&format!("✗ Failed to create disk image at {rw}"));
            self.run_line(343, "rm", &["-rf", &work, &stage])?;
            return Err(1);
        }
        self.run_line(347, "rm", &["-f", out_dmg])?;
        self.run_line(
            348,
            "hdiutil",
            &[
                "convert",
                &rw,
                "-format",
                "UDZO",
                "-imagekey",
                "zlib-level=9",
                "-o",
                out_dmg,
                "-quiet",
            ],
        )?;
        self.run_line(349, "rm", &["-rf", &work, &stage])?;

        if !self.o.skip_signing {
            let mut identity = env("SIGNING_IDENTITY");
            if identity.is_empty() {
                identity = self.keychain_identity();
            }
            if !identity.is_empty() {
                out(&format!("==> Signing DMG with Developer ID: {out_dmg}"));
                self.run_line(
                    361,
                    "codesign",
                    &["--force", "--timestamp", "--sign", &identity, out_dmg],
                )?;
            }
        }
        self.notarize_target(out_dmg)
    }

    /// create_universal_zip: ditto, else zip, else tar, else an empty file.
    pub fn create_universal_zip(&self, app: &str, out_zip: &str) -> Step {
        out(&format!("==> Packaging Universal ZIP: {out_zip}..."));
        self.run_line(372, "rm", &["-f", out_zip])?;
        let dir = dirname(app);
        let base = basename(app, "");
        if has("ditto") {
            self.run_line(374, "ditto", &["-c", "-k", "--keepParent", app, out_zip])
        } else if has("zip") {
            // (cd "$(dirname "$app_path")" && zip -q -r "$out_zip" ...)
            let pwd = shell_pwd();
            if let Err(e) = fs::metadata(&dir).and_then(|m| {
                if m.is_dir() {
                    Ok(())
                } else {
                    Err(std::io::Error::from_raw_os_error(20))
                }
            }) {
                err(&format!(
                    "{}: line 376: cd: {dir}: {}",
                    self.sh.argv0,
                    crate::shell::strerror(&e)
                ));
                return Err(1);
            }
            let mut c = cmd("zip", &["-q", "-r", out_zip, &base]);
            c.current_dir(&dir)
                .env("PWD", logical_path(&pwd, &dir))
                .env("OLDPWD", &pwd);
            self.sh.must(376, &mut c)
        } else if has("tar") {
            let code = self.sh.status(
                0,
                &mut cmd_quiet("tar", &["-czf", out_zip, "-C", &dir, &base]),
                true,
            );
            if code == 0 {
                Ok(())
            } else {
                self.run_line(378, "touch", &[out_zip])
            }
        } else {
            self.run_line(380, "touch", &[out_zip])
        }
    }

    /// verify_release_assets: every required name present and non-empty, in
    /// the dist directory ("local") or on the GitHub Release ("release").
    pub fn verify_release_assets(&self, place: &str, required: &str) -> Step {
        let o = &self.o;
        let mut present = String::new();
        if place == "release" {
            out(&format!(
                "==> Checking GitHub Release {} ({}) holds every expected asset...",
                o.tag, o.repo
            ));
            for attempt in 1..=3 {
                let (listing, code) = self.sh.capture(
                    400,
                    &mut cmd(
                        "gh",
                        &[
                            "release",
                            "view",
                            &o.tag,
                            "--repo",
                            &o.repo,
                            "--json",
                            "assets",
                            "--jq",
                            ".assets[] | select(.size > 0) | .name",
                        ],
                    ),
                    false,
                );
                if code != 0 {
                    return Err(code);
                }
                present = chomp(listing);
                if missing_assets(required, &present).is_empty() || attempt == 3 {
                    break;
                }
                let secs = {
                    let s = env("VERIFY_RETRY_SECONDS");
                    if s.is_empty() {
                        "5".to_string()
                    } else {
                        s
                    }
                };
                self.run_line(404, "sleep", &[&secs])?;
            }
        } else {
            out(&format!(
                "==> Checking {} holds every expected artifact...",
                o.dist_dir
            ));
            for name in required.split('\n') {
                if !name.is_empty() && is_nonempty(&format!("{}/{name}", o.dist_dir)) {
                    present.push_str(name);
                    present.push('\n');
                }
            }
        }

        let missing = missing_assets(required, &present);
        if !missing.is_empty() {
            err(&format!(
                "✗ {} {}: expected artifacts are missing or empty ({place}):",
                o.app_name, o.version
            ));
            for name in &missing {
                err(&format!("    - {name}"));
            }
            if !env("GITHUB_ACTIONS").is_empty() {
                let mut joined = missing.join(" ");
                joined.push(' ');
                out(&format!(
                    "::error title={} {} release is incomplete::missing ({place}): {joined}",
                    o.app_name, o.version
                ));
            }
            return Err(1);
        }
        let count = required.split('\n').filter(|l| !l.is_empty()).count();
        out(&format!(
            "    ✓ all {count} expected artifacts present ({place})"
        ));
        Ok(())
    }

    /// verify_expected_assets: the release when this run uploads to one,
    /// else the dist directory.
    pub fn verify_expected_assets(&self) -> Step {
        let o = &self.o;
        let place = if !o.dry_run && !o.tag.is_empty() {
            "release"
        } else {
            "local"
        };
        let required = required_release_assets(
            &o.app_name,
            &o.version,
            o.skip_dmg,
            o.skip_thinning,
            &o.require_assets,
        )
        .join("\n");
        self.verify_release_assets(place, &required)
    }

    // --------------------------------------------------------------------
    // Notarization
    // --------------------------------------------------------------------

    /// notary_key_to_file: the App Store Connect key, given as PEM or as
    /// base64 of it, written where notarytool can read it.
    pub fn notary_key_to_file(&self, value: &str, path: &str) -> Step {
        if value.contains("-----BEGIN") {
            if let Err(e) = fs::write(path, format!("{value}\n")) {
                err(&format!(
                    "{}: line 152: {path}: {}",
                    self.sh.argv0,
                    crate::shell::strerror(&e)
                ));
            }
        } else {
            let filtered: String = value
                .chars()
                .filter(|c| !matches!(c, ' ' | '\r' | '\n'))
                .collect();
            let ok = match fs::File::create(path) {
                Ok(file) => {
                    let mut c = cmd_quiet("base64", &["--decode"]);
                    c.stdin(Stdio::piped()).stdout(file);
                    match c.spawn() {
                        Ok(mut child) => {
                            if let Some(mut stdin) = child.stdin.take() {
                                let _ = stdin.write_all(filtered.as_bytes());
                            }
                            child.wait().map(|s| s.success()).unwrap_or(false)
                        }
                        Err(_) => false,
                    }
                }
                Err(e) => {
                    err(&format!(
                        "{}: line 153: {path}: {}",
                        self.sh.argv0,
                        crate::shell::strerror(&e)
                    ));
                    false
                }
            };
            if !ok {
                err("    NOTARY_API_KEY_P8 is neither a PEM key nor base64 of one");
                return Err(1);
            }
        }
        let decoded = fs::read(path).unwrap_or_default();
        if !decoded.windows(10).any(|w| w == b"-----BEGIN") {
            err("    NOTARY_API_KEY_P8 did not decode to a PEM key");
            return Err(1);
        }
        Ok(())
    }

    /// notarize_target: submit to notarytool (a .app as a zip of it) and
    /// staple the ticket to a .app or .dmg; skipped without credentials.
    pub fn notarize_target(&self, target: &str) -> Step {
        let p8 = env("NOTARY_API_KEY_P8");
        let key_file_env = env("NOTARY_KEY_FILE");
        let key_id = env("NOTARY_KEY_ID");
        let issuer = env("NOTARY_ISSUER_ID");
        if key_id.is_empty() || issuer.is_empty() || (p8.is_empty() && key_file_env.is_empty()) {
            out("==> Notary credentials not provided; skipping notarization.");
            return Ok(());
        }
        let tmp = mktemp_d()?;
        let mut key_file = key_file_env;
        if key_file.is_empty() {
            key_file = format!("{tmp}/AuthKey.p8");
            if self.notary_key_to_file(&p8, &key_file).is_err() {
                self.run_line(173, "rm", &["-rf", &tmp])?;
                return Err(1);
            }
        }
        let mut submit = target.to_string();
        if target.ends_with(".app") {
            submit = format!("{tmp}/{}.zip", basename(target, ".app"));
            self.run_line(183, "ditto", &["-c", "-k", "--keepParent", target, &submit])?;
        }
        out(&format!("==> Submitting {target} for notarization..."));
        let rc = self.sh.status(
            188,
            &mut cmd(
                "xcrun",
                &[
                    "notarytool",
                    "submit",
                    &submit,
                    "--key",
                    &key_file,
                    "--key-id",
                    &key_id,
                    "--issuer",
                    &issuer,
                    "--wait",
                ],
            ),
            false,
        );
        self.run_line(193, "rm", &["-rf", &tmp])?;
        if rc != 0 {
            return Err(rc);
        }
        if target.ends_with(".app") || target.ends_with(".dmg") {
            out(&format!("==> Stapling notarization ticket to {target}..."));
            self.run_line(198, "xcrun", &["stapler", "staple", target])?;
        }
        Ok(())
    }

    // --------------------------------------------------------------------
    // The run
    // --------------------------------------------------------------------

    fn sha256_line(&self, file: &str) -> Step<String> {
        let tool: &[&str] = if has("shasum") {
            &["shasum", "-a", "256"]
        } else if has("sha256sum") {
            &["sha256sum"]
        } else {
            return Ok(String::new());
        };
        let mut args: Vec<&str> = tool[1..].to_vec();
        args.push(file);
        let (o, code) = self.sh.capture(0, &mut cmd(tool[0], &args), false);
        if code != 0 {
            return Err(code);
        }
        Ok(first_fields(&o))
    }

    /// Everything after the staging directory exists. Err is the status the
    /// script would exit with.
    pub fn package(&mut self) -> Step {
        let stage_root = self.stage_root.clone();

        // 1. Unpack or stage the input app.
        let archive = self.o.archive.clone();
        let app_path_in = self.o.app_path.clone();
        let app_path;
        if !archive.is_empty() && is_file(&archive) {
            out(&format!("==> Unpacking archive {archive} into staging..."));
            if has("ditto") {
                self.run_line(621, "ditto", &["-x", "-k", &archive, &stage_root])?;
            } else if has("unzip") {
                self.run_line(623, "unzip", &["-q", "-o", &archive, "-d", &stage_root])?;
            } else {
                self.sh.status(
                    0,
                    &mut cmd_quiet("tar", &["-xzf", &archive, "-C", &stage_root]),
                    true,
                );
            }
            match find_app(&self.sh, &stage_root) {
                Some(found) => app_path = found,
                None => {
                    err(&format!("✗ No .app bundle found inside archive {archive}"));
                    return Err(1);
                }
            }
        } else if !app_path_in.is_empty() && is_dir(&app_path_in) {
            out(&format!("==> Staging application from {app_path_in}..."));
            let staged = format!("{stage_root}/{}", basename(&app_path_in, ""));
            self.copy_bundle(&app_path_in, &staged)?;
            app_path = staged;
        } else {
            err("✗ Either --app-path or --archive must be specified and exist.");
            return Err(1);
        }

        // 2. Derive what was not given.
        if self.o.app_name.is_empty() {
            self.o.app_name = basename(&app_path, ".app");
        }
        if self.o.version.is_empty() {
            let plist = format!("{app_path}/Contents/Info.plist");
            if is_file(&plist) {
                let (v, _) = self.sh.capture(
                    0,
                    &mut cmd_quiet(
                        "/usr/libexec/PlistBuddy",
                        &["-c", "Print CFBundleShortVersionString", &plist],
                    ),
                    true,
                );
                self.o.version = chomp(v);
            }
            if self.o.version.is_empty() && !self.o.tag.is_empty() {
                self.o.version = clean_version(&self.o.tag);
            }
            if self.o.version.is_empty() {
                err("✗ Version could not be determined. Specify --version <ver>.");
                return Err(1);
            }
        }
        if self.o.cask_name.is_empty() {
            self.o.cask_name = cask_name_for_app(&self.o.app_name);
        }
        if self.o.cask_desc.is_empty() {
            self.o.cask_desc = format!("macOS desktop application for {}", self.o.app_name);
        }
        if self.o.cask_homepage.is_empty() {
            self.o.cask_homepage = format!(
                "https://github.com/{}/tree/main/apps/desktop/{}",
                self.o.repo, self.o.cask_name
            );
        }
        let o = self.o.clone();
        let rule =
            "================================================================================";
        out(rule);
        out(&format!(" Packaging Desktop App: {}", o.app_name));
        out(&format!(" Version:               {}", o.version));
        out(&format!(" Cask:                  {}", o.cask_name));
        out(&format!(" Dist Directory:        {}", o.dist_dir));
        out(&format!(
            " GitHub Tag:            {}",
            if o.tag.is_empty() { "<none>" } else { &o.tag }
        ));
        out(rule);

        self.run_line(681, "mkdir", &["-p", &o.dist_dir])?;
        let stage_univ = format!("{stage_root}/universal/{}.app", o.app_name);
        self.run_line(684, "mkdir", &["-p", &dirname(&stage_univ)])?;
        self.copy_bundle(&app_path, &stage_univ)?;

        // 3. Sign the universal bundle.
        if !o.skip_signing {
            self.sign_bundle(&stage_univ, &o.entitlements)?;
            self.notarize_target(&stage_univ)?;
        }

        let base = format!("{}/{}-{}", o.dist_dir, o.app_name, o.version);
        let universal_dmg = format!("{base}-universal.dmg");
        let legacy_dmg = format!("{base}.dmg");
        let universal_zip = format!("{base}-universal.zip");

        // 4. Universal DMG and ZIP.
        if !o.skip_dmg {
            self.create_dmg(&stage_univ, &universal_dmg, &o.app_name)?;
            self.run_line(702, "cp", &["-f", &universal_dmg, &legacy_dmg])?;
        }
        self.create_universal_zip(&stage_univ, &universal_zip)?;
        self.run_line(
            705,
            "cp",
            &["-f", &universal_zip, &format!("{base}-macOS.zip")],
        )?;

        // 5. Thin to Apple Silicon and Intel.
        if !o.skip_thinning && !o.skip_dmg {
            for (arch, line) in [("arm64", 711), ("x86_64", 722)] {
                let staged = format!("{stage_root}/{arch}/{}.app", o.app_name);
                self.run_line(line, "mkdir", &["-p", &dirname(&staged)])?;
                self.copy_bundle(&stage_univ, &staged)?;
                self.thin_bundle(&staged, arch)?;
                if !o.skip_signing {
                    self.sign_bundle(&staged, &o.entitlements)?;
                    self.notarize_target(&staged)?;
                }
                self.create_dmg(&staged, &format!("{base}-{arch}.dmg"), &o.app_name)?;
            }
        }

        // 6. Checksums.
        out("==> Computing SHA256 checksums...");
        let prefix = format!("{}-{}", o.app_name, o.version);
        let mut arts = glob(&o.dist_dir, &prefix, ".dmg");
        arts.extend(glob(&o.dist_dir, &prefix, ".zip"));
        for art in arts {
            if !is_file(&art) {
                continue;
            }
            let local = basename(&art, "");
            let tool: Option<(&str, &[&str], u32)> = if has("shasum") {
                Some(("shasum", &["-a", "256"], 738))
            } else if has("sha256sum") {
                Some(("sha256sum", &[], 740))
            } else {
                None
            };
            if let Some((prog, flags, line)) = tool {
                self.checksum_into_dist(prog, flags, line, &local)?;
            }
            if let Ok(bytes) = fs::read(format!("{art}.sha256")) {
                out_raw(&bytes);
            }
        }

        // 7. The Homebrew Cask.
        let universal_sha = if is_file(&universal_dmg) {
            self.sha256_line(&universal_dmg)?
        } else if is_file(&universal_zip) {
            self.sha256_line(&universal_zip)?
        } else {
            String::new()
        };
        let effective_tag = if o.tag.is_empty() {
            format!("{}-v{}", o.cask_name, o.version)
        } else {
            o.tag.clone()
        };
        let download_url = format!(
            "https://github.com/{}/releases/download/{effective_tag}/{}-{}-universal.dmg",
            o.repo, o.app_name, o.version
        );
        let cask = generate_cask_ruby(
            &o.cask_name,
            &o.version,
            &universal_sha,
            &download_url,
            &o.app_name,
            &o.cask_desc,
            &o.cask_homepage,
        );
        let cask_file = format!("{}/{}.rb", o.dist_dir, o.cask_name);
        if let Err(e) = fs::write(&cask_file, format!("{cask}\n")) {
            err(&format!(
                "{}: line 767: {cask_file}: {}",
                self.sh.argv0,
                crate::shell::strerror(&e)
            ));
            return Err(1);
        }
        out(&format!("==> Generated Homebrew Cask formula: {cask_file}"));

        // 8. Upload to the GitHub Release.
        let token = {
            let t = env("GH_TOKEN");
            if t.is_empty() {
                env("GITHUB_TOKEN")
            } else {
                t
            }
        };
        if !o.dry_run && !o.tag.is_empty() && !token.is_empty() {
            out(&format!(
                "==> Uploading artifacts to GitHub Release: {} ({})...",
                o.tag, o.repo
            ));
            let mut files = glob(&o.dist_dir, &prefix, ".dmg");
            files.extend(glob(&o.dist_dir, &prefix, ".zip"));
            files.extend(glob(&o.dist_dir, &prefix, ".sha256"));
            for f in files {
                if is_file(&f) {
                    out(&format!("    Uploading {}...", basename(&f, "")));
                    self.run_line(
                        776,
                        "gh",
                        &[
                            "release",
                            "upload",
                            &o.tag,
                            &f,
                            "--repo",
                            &o.repo,
                            "--clobber",
                        ],
                    )?;
                }
            }
        }

        // 9. Proof before anything points at these files.
        self.verify_expected_assets()?;

        // 10. The Homebrew tap, after the proof.
        let tap_token = env("HOMEBREW_TAP_TOKEN");
        if !o.dry_run && !tap_token.is_empty() {
            let tap = "VitruvianSoftware/homebrew-tap";
            let tap_dir = format!("{stage_root}/homebrew-tap");
            let cask_rel = format!("Casks/{}.rb", o.cask_name);
            out(&format!("==> Updating {tap} {cask_rel}..."));
            let url = format!("https://x-access-token:{tap_token}@github.com/{tap}.git");
            self.run_line(791, "git", &["clone", "--depth", "1", &url, &tap_dir])?;
            self.run_line(792, "mkdir", &["-p", &format!("{tap_dir}/Casks")])?;
            self.run_line(793, "cp", &[&cask_file, &format!("{tap_dir}/{cask_rel}")])?;
            self.run_line(794, "git", &["-C", &tap_dir, "add", &cask_rel])?;
            let unchanged = self.sh.status(
                795,
                &mut cmd("git", &["-C", &tap_dir, "diff", "--cached", "--quiet"]),
                false,
            ) == 0;
            if unchanged {
                out(&format!(
                    "    Tap already contains up-to-date {} {}",
                    o.cask_name, o.version
                ));
            } else {
                let msg = format!("{} {}", o.cask_name, o.version);
                self.run_line(
                    798,
                    "git",
                    &[
                        "-C",
                        &tap_dir,
                        "-c",
                        "user.name=github-actions[bot]",
                        "-c",
                        "user.email=41898282+github-actions[bot]@users.noreply.github.com",
                        "commit",
                        "-q",
                        "-m",
                        &msg,
                    ],
                )?;
                self.run_line(
                    801,
                    "git",
                    &["-C", &tap_dir, "push", "-q", "origin", "HEAD"],
                )?;
                out(&format!("    ✓ {tap} {cask_rel} updated to {}", o.version));
            }
        }

        // 11. The downloads catalog.
        let pwd = shell_pwd();
        let script_dir = logical_path(&pwd, &dirname(&self.program));
        let repo_root = {
            let w = env("BUILD_WORKSPACE_DIRECTORY");
            if w.is_empty() {
                logical_path(&script_dir, "../..")
            } else {
                w
            }
        };
        let sync_script = format!("{repo_root}/tools/sync-downloads/sync_downloads.py");
        if o.sync_downloads || (!o.tag.is_empty() && !o.dry_run) {
            out("==> Synchronizing downloads catalog...");
            if is_file(&sync_script) {
                let mut a = vec![sync_script.as_str()];
                if o.dry_run {
                    a.push("--dry-run");
                }
                self.run_line(821, "python3", &a)?;
            } else {
                err(&format!(
                    "Warning: downloads catalog sync script not found at {sync_script}"
                ));
            }
        }

        out(&format!(
            "==> Desktop release packaging complete for {} v{}.",
            o.app_name, o.version
        ));
        let mut listing = glob(&o.dist_dir, &prefix, "");
        if listing.is_empty() {
            listing.push(format!("{}/{prefix}*", o.dist_dir));
        }
        let mut ls = vec!["-lh"];
        ls.extend(listing.iter().map(|s| s.as_str()));
        self.sh.status(0, &mut cmd_quiet("ls", &ls), true);
        Ok(())
    }

    /// `(cd "$DIST_DIR" && <tool> "$local_art" > "${local_art}.sha256")`.
    fn checksum_into_dist(&self, prog: &str, flags: &[&str], line: u32, local: &str) -> Step {
        let dist = &self.o.dist_dir;
        let pwd = shell_pwd();
        if !is_dir(dist) {
            err(&format!(
                "{}: line {line}: cd: {dist}: No such file or directory",
                self.sh.argv0
            ));
            return Err(1);
        }
        let sidecar = format!("{dist}/{local}.sha256");
        let file = match fs::File::create(sidecar) {
            Ok(f) => f,
            Err(e) => {
                err(&format!(
                    "{}: line {line}: {local}.sha256: {}",
                    self.sh.argv0,
                    crate::shell::strerror(&e)
                ));
                return Err(1);
            }
        };
        let mut args: Vec<&str> = flags.to_vec();
        args.push(local);
        let mut c: Command = cmd(prog, &args);
        c.current_dir(dist)
            .stdout(file)
            .env("PWD", logical_path(&pwd, dist))
            .env("OLDPWD", &pwd);
        self.sh.must(line, &mut c)
    }
}

/// `find "$STAGE_ROOT" -maxdepth 2 -name "*.app" | head -1`.
fn find_app(sh: &Shell, root: &str) -> Option<String> {
    let (found, _) = sh.capture(
        0,
        &mut cmd_quiet("find", &[root, "-maxdepth", "2", "-name", "*.app"]),
        true,
    );
    chomp(found)
        .split('\n')
        .find(|l| !l.is_empty())
        .map(|l| l.to_string())
}

/// The whole program: package-desktop.sh with `args`. Returns the exit
/// status. `argv0` names the program in bash-style messages; `program` is
/// the path it was started by (where the downloads sync is looked for).
pub fn main_with(argv0: &str, program: &str, args: &[String]) -> i32 {
    let mut o = Opts::default();
    match parse(argv0, args, &mut o) {
        Parsed::Run => {}
        Parsed::Usage(code) => {
            out_raw(USAGE.as_bytes());
            return code;
        }
        Parsed::Exit(code) => return code,
    }
    let sh = Shell {
        argv0: argv0.to_string(),
    };

    if o.verify_only {
        if o.version.is_empty() && !o.tag.is_empty() {
            o.version = clean_version(&o.tag);
        }
        if o.app_name.is_empty() || o.version.is_empty() {
            err("✗ --verify-only needs --app-name and --version (or --tag).");
            return 1;
        }
        let d = Driver {
            sh,
            o,
            program: program.to_string(),
            stage_root: String::new(),
        };
        return match d.verify_expected_assets() {
            Ok(()) => 0,
            Err(code) => code,
        };
    }

    let stage_root = match mktemp_d() {
        Ok(p) => p,
        Err(code) => return code,
    };
    let mut d = Driver {
        sh,
        o,
        program: program.to_string(),
        stage_root: stage_root.clone(),
    };
    let result = d.package();
    // The EXIT trap: remove the staging tree whatever happened.
    d.sh.status(608, &mut cmd("rm", &["-rf", &stage_root]), false);
    match result {
        Ok(()) => 0,
        Err(code) => code,
    }
}

/// The path to report as the program's own: argv[0] when it holds a slash
/// (as bash's ${BASH_SOURCE[0]} does), else the executable found on PATH.
pub fn program_path(argv0: &str) -> String {
    if argv0.contains('/') {
        return argv0.to_string();
    }
    command_v(argv0)
        .map(|p| p.to_string_lossy().into_owned())
        .or_else(|| {
            std::env::current_exe()
                .ok()
                .map(|p| p.to_string_lossy().into_owned())
        })
        .unwrap_or_else(|| argv0.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn args(a: &[&str]) -> Vec<String> {
        a.iter().map(|s| s.to_string()).collect()
    }

    #[test]
    fn parsing_takes_values_and_flags() {
        let mut o = Opts::default();
        let got = parse(
            "p",
            &args(&[
                "--app-path",
                "x.app",
                "--skip-dmg",
                "--require-asset",
                "a",
                "--require-asset",
                "b",
            ]),
            &mut o,
        );
        assert_eq!(got, Parsed::Run);
        assert_eq!(o.app_path, "x.app");
        assert!(o.skip_dmg && !o.skip_signing);
        assert_eq!(o.require_assets, vec!["a", "b"]);
        assert_eq!(o.dist_dir, "dist");
    }

    #[test]
    fn parsing_stops_like_the_script() {
        let mut o = Opts::default();
        assert_eq!(parse("p", &args(&["--help"]), &mut o), Parsed::Usage(0));
        assert_eq!(parse("p", &args(&["--bogus"]), &mut o), Parsed::Usage(1));
        assert_eq!(parse("p", &args(&["--tag"]), &mut o), Parsed::Exit(1));
    }

    #[test]
    fn usage_is_the_scripts_heredoc() {
        assert!(USAGE.starts_with("Usage:\n  package-desktop.sh [options]\n"));
        assert!(USAGE.ends_with("  --help                  Show this help message\n"));
    }
}
