// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

//! Turns the Bazel-built app into the release's disk images and zip, in
//! `<package>/dist/`:
//!   Vitruvian-<version>-universal.dmg, Vitruvian-<version>.dmg (the same
//!   image), Vitruvian-<version>-universal.zip, Vitruvian-<version>-arm64.dmg
//!   and Vitruvian-<version>-x86_64.dmg.
//!
//!   bazel build --config=macos-app //apps/desktop/vitruvian:Vitruvian
//!   bazel run //apps/desktop/vitruvian:package_release -- <path to Vitruvian.zip>
//!
//! It unpacks the bundle into a temp dir (never a "build" directory, which on
//! macOS's case-insensitive filesystem is the package's Bazel BUILD file) and
//! signs the fan helper, the Now Playing adapter, the GravaStar mouse command
//! (Contents/Helpers) and the bundle: with the Developer ID identity when one
//! is installed (ci_setup_signing imports it on CI), ad-hoc otherwise. It
//! notarizes each app and each DMG when the notary credentials are set
//! (notarize skips quietly when they are not), and packages each DMG with
//! make_dmg. The arm64 and x86_64 apps are the universal one thinned with
//! lipo and signed again.

use release_exec::{
    detect_developer_id, make_temp_dir, plist_short_version, run, Cmd, Runner, TempDir,
};
use std::fs;
use std::path::{Path, PathBuf};

pub const APP_BUNDLE_ID: &str = "com.vitruviansoftware.vitruvian";
pub const FAN_HELPER_ID: &str = "com.vitruviansoftware.vitruvian.fan-control";
pub const NOW_PLAYING_ADAPTER_ID: &str = "com.vitruviansoftware.vitruvian.now-playing";
pub const MOUSE_TOOL_ID: &str = "com.vitruviansoftware.vitruvian.gravastar-mouse";
pub const ENTITLEMENTS_REL: &str = "Resources/Vitruvian.entitlements";
pub const USAGE: &str = "usage: package-release <path to the Bazel-built Vitruvian.zip>";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BundleLayout {
    pub app: PathBuf,
    pub main_executable: PathBuf,
    pub helper: PathBuf,
    pub adapter: PathBuf,
    pub mouse_tool: PathBuf,
}

pub fn bundle_layout(app: &Path) -> BundleLayout {
    BundleLayout {
        app: app.to_path_buf(),
        main_executable: app.join("Contents/MacOS/Vitruvian"),
        helper: app
            .join("Contents/Library/LaunchServices")
            .join(FAN_HELPER_ID),
        adapter: app.join("Contents/Frameworks/libVitruvianNowPlaying.dylib"),
        mouse_tool: app.join("Contents/Helpers/gravastar-mouse"),
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReleaseArtifacts {
    pub universal_dmg: PathBuf,
    pub default_dmg: PathBuf,
    pub universal_zip: PathBuf,
    pub arm64_dmg: PathBuf,
    pub x86_64_dmg: PathBuf,
}

pub fn expected_artifacts(dist: &Path, version: &str) -> ReleaseArtifacts {
    let f = |suffix: &str| dist.join(format!("Vitruvian-{}{}", version, suffix));
    ReleaseArtifacts {
        universal_dmg: f("-universal.dmg"),
        default_dmg: f(".dmg"),
        universal_zip: f("-universal.zip"),
        arm64_dmg: f("-arm64.dmg"),
        x86_64_dmg: f("-x86_64.dmg"),
    }
}

/// The codesign commands that sign `app`'s three embedded programs and then
/// the bundle, and verify each.
pub fn sign_bundle_commands(
    app: &Path,
    developer_id: Option<&str>,
    entitlements: &Path,
) -> Vec<Cmd> {
    let l = bundle_layout(app);
    let parts = [
        (FAN_HELPER_ID, &l.helper),
        (NOW_PLAYING_ADAPTER_ID, &l.adapter),
        (MOUSE_TOOL_ID, &l.mouse_tool),
    ];
    let mut cmds = Vec::new();
    match developer_id.filter(|s| !s.is_empty()) {
        Some(id) => {
            for (ident, path) in parts {
                cmds.push(
                    Cmd::new("codesign")
                        .args([
                            "--force",
                            "--options",
                            "runtime",
                            "--timestamp",
                            "--identifier",
                            ident,
                            "--sign",
                            id,
                        ])
                        .path(path),
                );
            }
            cmds.push(
                Cmd::new("codesign")
                    .args([
                        "--force",
                        "--options",
                        "runtime",
                        "--timestamp",
                        "--entitlements",
                    ])
                    .path(entitlements)
                    .args(["--sign", id])
                    .path(&l.app),
            );
        }
        None => {
            for (ident, path) in parts {
                cmds.push(
                    Cmd::new("codesign")
                        .args(["--force", "--identifier", ident, "--sign", "-"])
                        .path(path),
                );
            }
            cmds.push(
                Cmd::new("codesign")
                    .args(["--force", "--sign", "-"])
                    .path(&l.app),
            );
        }
    }
    for path in [&l.helper, &l.adapter, &l.mouse_tool] {
        cmds.push(
            Cmd::new("codesign")
                .args(["--verify", "--strict"])
                .path(path),
        );
    }
    cmds.push(
        Cmd::new("codesign")
            .args(["--verify", "--deep", "--strict"])
            .path(&l.app),
    );
    cmds
}

/// The steps package_release hands to the other release tools.
pub trait Packaging {
    fn notarize(&mut self, r: &mut dyn Runner, target: &Path) -> Result<(), i32>;
    fn make_dmg(&mut self, r: &mut dyn Runner, app: &Path, out: &Path) -> Result<(), i32>;
}

/// notarize and make_dmg, for real.
pub struct ReleaseTools {
    pub pkg_dir: PathBuf,
    pub tmp_root: PathBuf,
    pub notary: notarize::NotaryEnv,
    /// `DEVELOPER_ID` from the environment, which make_dmg prefers.
    pub dmg_developer_id: Option<String>,
}

impl ReleaseTools {
    pub fn from_env(pkg_dir: &Path, tmp_root: &Path) -> ReleaseTools {
        let env_map = std::env::vars().collect();
        ReleaseTools {
            pkg_dir: pkg_dir.to_path_buf(),
            tmp_root: tmp_root.to_path_buf(),
            notary: notarize::NotaryEnv::from_env(&env_map),
            dmg_developer_id: std::env::var("DEVELOPER_ID").ok(),
        }
    }
}

impl Packaging for ReleaseTools {
    fn notarize(&mut self, r: &mut dyn Runner, target: &Path) -> Result<(), i32> {
        notarize::notarize(r, target, &self.notary, &self.tmp_root)
    }

    fn make_dmg(&mut self, r: &mut dyn Runner, app: &Path, out: &Path) -> Result<(), i32> {
        make_dmg::make_dmg(
            r,
            &make_dmg::DmgRequest {
                pkg_dir: self.pkg_dir.clone(),
                app: app.to_path_buf(),
                out: Some(out.to_path_buf()),
                developer_id: self.dmg_developer_id.clone(),
                tmp_root: self.tmp_root.clone(),
            },
        )
        .map(|_| ())
    }
}

fn clear_xattrs(r: &mut dyn Runner, dir: &Path) {
    let _ = r.output(
        &Cmd::new("find")
            .path(dir)
            .args(["-exec", "xattr", "-c", "{}", "+"]),
    );
}

fn sign_bundle(
    r: &mut dyn Runner,
    app: &Path,
    developer_id: Option<&str>,
    entitlements: &Path,
) -> Result<(), i32> {
    run(r, &Cmd::new("chmod").args(["-R", "u+w"]).path(app))?;
    clear_xattrs(r, app);
    match developer_id {
        Some(id) => println!("▸ Signing with {}…", id),
        None => println!("▸ No Developer ID identity installed; signing ad-hoc…"),
    }
    for cmd in sign_bundle_commands(app, developer_id, entitlements) {
        run(r, &cmd)?;
    }
    Ok(())
}

/// Copies the universal app and thins its four programs to `arch`.
fn thinned_copy(r: &mut dyn Runner, app: &Path, stage: &Path, arch: &str) -> Result<PathBuf, i32> {
    let dir = stage.join(arch);
    fs::create_dir_all(&dir).map_err(|e| {
        eprintln!("✗ mkdir {}: {}", dir.display(), e);
        1
    })?;
    let thin = dir.join("Vitruvian.app");
    run(r, &Cmd::new("ditto").path(app).path(&thin))?;
    let l = bundle_layout(&thin);
    for bin in [&l.main_executable, &l.helper, &l.adapter, &l.mouse_tool] {
        let info = r.output(&Cmd::new("lipo").arg("-info").path(bin));
        if info.success() && info.stdout.contains(arch) {
            run(
                r,
                &Cmd::new("lipo")
                    .path(bin)
                    .args(["-thin", arch, "-output"])
                    .path(bin),
            )?;
        }
    }
    Ok(thin)
}

/// Packages `archive` into `<pkg_dir>/dist`, and returns the version.
pub fn package_release(
    r: &mut dyn Runner,
    tools: &mut dyn Packaging,
    pkg_dir: &Path,
    archive: &Path,
    tmp_root: &Path,
) -> Result<String, i32> {
    if !archive.is_file() {
        eprintln!("{}", USAGE);
        return Err(1);
    }
    let archive = fs::canonicalize(archive).unwrap_or_else(|_| archive.to_path_buf());
    let entitlements = pkg_dir.join(ENTITLEMENTS_REL);

    let stage = make_temp_dir(tmp_root, "vitruvian-package").map_err(|e| {
        eprintln!("✗ mktemp: {}", e);
        1
    })?;
    let _cleanup = TempDir(stage.clone());
    let layout = bundle_layout(&stage.join("Vitruvian.app"));

    println!("▸ Unpacking {}…", archive.display());
    run(
        r,
        &Cmd::new("ditto")
            .args(["-x", "-k"])
            .path(&archive)
            .path(&stage),
    )?;
    for part in [
        &layout.app,
        &layout.helper,
        &layout.adapter,
        &layout.mouse_tool,
    ] {
        if !part.exists() {
            eprintln!("✗ {} is missing from the archive", part.display());
            return Err(1);
        }
    }
    // Bazel's outputs are read-only; signing rewrites them in place.
    run(r, &Cmd::new("chmod").args(["-R", "u+w"]).path(&layout.app))?;
    clear_xattrs(r, &layout.app);

    let developer_id = detect_developer_id(r);
    let dev = developer_id.as_deref();

    // Sign and notarize the universal bundle.
    sign_bundle(r, &layout.app, dev, &entitlements)?;
    tools.notarize(r, &layout.app)?;

    let version = plist_short_version(r, &layout.app.join("Contents/Info.plist"))?;
    let dist = pkg_dir.join("dist");
    fs::create_dir_all(&dist).map_err(|e| {
        eprintln!("✗ mkdir {}: {}", dist.display(), e);
        1
    })?;
    let out = expected_artifacts(&dist, &version);

    println!("▸ Packaging Universal DMG & ZIP…");
    tools.make_dmg(r, &layout.app, &out.universal_dmg)?;
    fs::copy(&out.universal_dmg, &out.default_dmg).map_err(|e| {
        eprintln!("✗ cp {}: {}", out.universal_dmg.display(), e);
        1
    })?;
    let _ = fs::remove_file(&out.universal_zip);
    run(
        r,
        &Cmd::new("ditto")
            .args(["-c", "-k", "--keepParent"])
            .path(&layout.app)
            .path(&out.universal_zip),
    )?;

    println!("▸ Thinning and packaging Apple Silicon (arm64) DMG…");
    let arm64 = thinned_copy(r, &layout.app, &stage, "arm64")?;
    sign_bundle(r, &arm64, dev, &entitlements)?;
    tools.notarize(r, &arm64)?;
    tools.make_dmg(r, &arm64, &out.arm64_dmg)?;

    println!("▸ Thinning and packaging Intel (x86_64) DMG…");
    let x86_64 = thinned_copy(r, &layout.app, &stage, "x86_64")?;
    sign_bundle(r, &x86_64, dev, &entitlements)?;
    tools.notarize(r, &x86_64)?;
    tools.make_dmg(r, &x86_64, &out.x86_64_dmg)?;

    println!("▸ Notarizing DMGs…");
    for dmg in [
        &out.universal_dmg,
        &out.arm64_dmg,
        &out.x86_64_dmg,
        &out.default_dmg,
    ] {
        tools.notarize(r, dmg)?;
    }

    println!("✓ Release artifacts ready in dist/:");
    let prefix = format!("Vitruvian-{}", version);
    let mut listed: Vec<PathBuf> = fs::read_dir(&dist)
        .map(|it| {
            it.filter_map(|e| e.ok())
                .filter(|e| e.file_name().to_string_lossy().starts_with(&prefix))
                .map(|e| e.path())
                .collect()
        })
        .unwrap_or_default();
    listed.sort();
    let mut ls = Cmd::new("ls").arg("-lh");
    for p in &listed {
        ls = ls.path(p);
    }
    run(r, &ls)?;
    Ok(version)
}

pub fn run_cli(args: &[String]) -> i32 {
    let archive = match args {
        [one] if !one.is_empty() => release_exec::user_path(one),
        _ => {
            eprintln!("{}", USAGE);
            return 1;
        }
    };
    let pkg_dir = release_exec::package_dir();
    let tmp_root = release_exec::temp_root();
    let mut tools = ReleaseTools::from_env(&pkg_dir, &tmp_root);
    match package_release(
        &mut release_exec::SystemRunner::new(),
        &mut tools,
        &pkg_dir,
        &archive,
        &tmp_root,
    ) {
        Ok(_) => 0,
        Err(code) => code,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use release_exec::{FakeRunner, Out};

    /// Stands in for notarize and make_dmg, logging each through the runner
    /// so the order of everything shows in one list.
    struct LoggedTools;

    impl Packaging for LoggedTools {
        fn notarize(&mut self, r: &mut dyn Runner, target: &Path) -> Result<(), i32> {
            run(r, &Cmd::new("NOTARIZE").path(target))
        }
        fn make_dmg(&mut self, r: &mut dyn Runner, app: &Path, out: &Path) -> Result<(), i32> {
            run(r, &Cmd::new("MAKE_DMG").path(app).path(out))?;
            fs::write(out, b"dmg").unwrap();
            Ok(())
        }
    }

    struct Scene {
        _guard: TempDir,
        root: PathBuf,
        pkg: PathBuf,
        archive: PathBuf,
        tmp: PathBuf,
    }

    fn scene(name: &str) -> Scene {
        let root = make_temp_dir(&std::env::temp_dir(), name).unwrap();
        let pkg = root.join("pkg");
        let tmp = root.join("tmp");
        fs::create_dir_all(&pkg).unwrap();
        fs::create_dir_all(&tmp).unwrap();
        let archive = root.join("Vitruvian.zip");
        fs::write(&archive, b"zip").unwrap();
        Scene {
            _guard: TempDir(root.clone()),
            root,
            pkg,
            archive,
            tmp,
        }
    }

    /// A Mac whose ditto unpacks a whole bundle (or `missing` left out) and
    /// whose programs are all universal.
    fn mac(identity: Option<&'static str>, missing: Option<&'static str>) -> FakeRunner {
        FakeRunner::new(move |c| {
            let a: Vec<&str> = c.args.iter().map(String::as_str).collect();
            match (c.program.as_str(), a.as_slice()) {
                ("ditto", ["-x", "-k", _, stage]) => {
                    let l = bundle_layout(&Path::new(stage).join("Vitruvian.app"));
                    for p in [&l.main_executable, &l.helper, &l.adapter, &l.mouse_tool] {
                        if missing.is_some_and(|m| p.to_string_lossy().ends_with(m)) {
                            continue;
                        }
                        fs::create_dir_all(p.parent().unwrap()).unwrap();
                        fs::write(p, b"bin").unwrap();
                    }
                    Out::ok("")
                }
                ("security", _) => match identity {
                    Some(id) => Out::ok(&format!(
                        "  1) ABC \"{}\"\n     1 valid identities found\n",
                        id
                    )),
                    None => Out::ok("     0 valid identities found\n"),
                },
                ("/usr/libexec/PlistBuddy", _) => Out::ok("3.86.0\n"),
                ("lipo", ["-info", bin]) => Out::ok(&format!(
                    "Architectures in the fat file: {} are: x86_64 arm64\n",
                    bin
                )),
                _ => Out::ok(""),
            }
        })
    }

    #[test]
    fn a_missing_archive_is_a_usage_error() {
        let s = scene("package_release_usage");
        let mut r = FakeRunner::succeeding();
        assert_eq!(
            package_release(
                &mut r,
                &mut LoggedTools,
                &s.pkg,
                &s.root.join("nope.zip"),
                &s.tmp
            ),
            Err(1)
        );
        assert!(r.calls.is_empty());
    }

    #[test]
    fn an_archive_without_the_mouse_command_fails_before_signing() {
        let s = scene("package_release_missing");
        let mut r = mac(None, Some("gravastar-mouse"));
        assert_eq!(
            package_release(&mut r, &mut LoggedTools, &s.pkg, &s.archive, &s.tmp),
            Err(1)
        );
        assert_eq!(r.count("codesign"), 0);
    }

    #[test]
    fn developer_id_signing_uses_the_hardened_runtime_and_the_entitlements() {
        let app = Path::new("/s/Vitruvian.app");
        let ent = Path::new("/pkg/Resources/Vitruvian.entitlements");
        let lines: Vec<String> =
            sign_bundle_commands(app, Some("Developer ID Application: V (T)"), ent)
                .iter()
                .map(Cmd::line)
                .collect();
        assert_eq!(
            lines,
            vec![
                format!("codesign --force --options runtime --timestamp --identifier {} --sign Developer ID Application: V (T) /s/Vitruvian.app/Contents/Library/LaunchServices/{}", FAN_HELPER_ID, FAN_HELPER_ID),
                format!("codesign --force --options runtime --timestamp --identifier {} --sign Developer ID Application: V (T) /s/Vitruvian.app/Contents/Frameworks/libVitruvianNowPlaying.dylib", NOW_PLAYING_ADAPTER_ID),
                format!("codesign --force --options runtime --timestamp --identifier {} --sign Developer ID Application: V (T) /s/Vitruvian.app/Contents/Helpers/gravastar-mouse", MOUSE_TOOL_ID),
                "codesign --force --options runtime --timestamp --entitlements /pkg/Resources/Vitruvian.entitlements --sign Developer ID Application: V (T) /s/Vitruvian.app".to_string(),
                format!("codesign --verify --strict /s/Vitruvian.app/Contents/Library/LaunchServices/{}", FAN_HELPER_ID),
                "codesign --verify --strict /s/Vitruvian.app/Contents/Frameworks/libVitruvianNowPlaying.dylib".to_string(),
                "codesign --verify --strict /s/Vitruvian.app/Contents/Helpers/gravastar-mouse".to_string(),
                "codesign --verify --deep --strict /s/Vitruvian.app".to_string(),
            ]
        );
    }

    #[test]
    fn ad_hoc_signing_keeps_the_identifiers_and_drops_runtime_and_entitlements() {
        let lines: Vec<String> = sign_bundle_commands(Path::new("/s/V.app"), None, Path::new("/e"))
            .iter()
            .map(Cmd::line)
            .collect();
        assert_eq!(
            lines[..4].to_vec(),
            vec![
                format!("codesign --force --identifier {} --sign - /s/V.app/Contents/Library/LaunchServices/{}", FAN_HELPER_ID, FAN_HELPER_ID),
                format!("codesign --force --identifier {} --sign - /s/V.app/Contents/Frameworks/libVitruvianNowPlaying.dylib", NOW_PLAYING_ADAPTER_ID),
                format!("codesign --force --identifier {} --sign - /s/V.app/Contents/Helpers/gravastar-mouse", MOUSE_TOOL_ID),
                "codesign --force --sign - /s/V.app".to_string(),
            ]
        );
        assert_eq!(lines.len(), 8);
    }

    #[test]
    fn the_release_signs_notarizes_and_packages_each_build_in_order() {
        let s = scene("package_release_order");
        let mut r = mac(Some("Developer ID Application: V (T)"), None);
        let version =
            package_release(&mut r, &mut LoggedTools, &s.pkg, &s.archive, &s.tmp).unwrap();
        assert_eq!(version, "3.86.0");

        let dist = s.pkg.join("dist");
        let d = |f: &str| dist.join(f).to_string_lossy().to_string();
        // The steps, in order, by what they start with.
        let steps: Vec<String> = r
            .calls
            .iter()
            .filter(|c| {
                c.starts_with("NOTARIZE")
                    || c.starts_with("MAKE_DMG")
                    || c.starts_with("ditto")
                    || c.starts_with(
                        "codesign --force --options runtime --timestamp --entitlements",
                    )
                    || (c.starts_with("lipo ") && c.contains(" -thin "))
                    || c.starts_with("ls -lh")
            })
            .cloned()
            .collect();
        let kinds: Vec<String> = steps
            .iter()
            .map(|c| {
                let word = c.split(' ').next().unwrap().to_string();
                if word == "lipo" {
                    format!(
                        "lipo-thin {}",
                        c.split(" -thin ")
                            .nth(1)
                            .unwrap()
                            .split(' ')
                            .next()
                            .unwrap()
                    )
                } else if word == "codesign" {
                    "sign-app".to_string()
                } else if word == "ditto" {
                    let first = c.split(' ').nth(1).unwrap();
                    if first.starts_with('/') {
                        "ditto /".to_string()
                    } else {
                        format!("ditto {}", first)
                    }
                } else if word == "MAKE_DMG" || word == "NOTARIZE" {
                    let last = c.rsplit(' ').next().unwrap();
                    let tail = if last.ends_with(".app") {
                        let parent = Path::new(last)
                            .parent()
                            .unwrap()
                            .file_name()
                            .unwrap()
                            .to_string_lossy()
                            .to_string();
                        if parent == "arm64" || parent == "x86_64" {
                            format!("{}.app", parent)
                        } else {
                            "universal.app".to_string()
                        }
                    } else {
                        Path::new(last)
                            .file_name()
                            .unwrap()
                            .to_string_lossy()
                            .to_string()
                    };
                    format!("{} {}", word, tail)
                } else {
                    word
                }
            })
            .collect();
        let expect: Vec<&str> = vec![
            "ditto -x",
            "sign-app",
            "NOTARIZE universal.app",
            "MAKE_DMG Vitruvian-3.86.0-universal.dmg",
            "ditto -c",
            "ditto /",
            "lipo-thin arm64",
            "lipo-thin arm64",
            "lipo-thin arm64",
            "lipo-thin arm64",
            "sign-app",
            "NOTARIZE arm64.app",
            "MAKE_DMG Vitruvian-3.86.0-arm64.dmg",
            "ditto /",
            "lipo-thin x86_64",
            "lipo-thin x86_64",
            "lipo-thin x86_64",
            "lipo-thin x86_64",
            "sign-app",
            "NOTARIZE x86_64.app",
            "MAKE_DMG Vitruvian-3.86.0-x86_64.dmg",
            "NOTARIZE Vitruvian-3.86.0-universal.dmg",
            "NOTARIZE Vitruvian-3.86.0-arm64.dmg",
            "NOTARIZE Vitruvian-3.86.0-x86_64.dmg",
            "NOTARIZE Vitruvian-3.86.0.dmg",
            "ls",
        ];
        assert_eq!(kinds, expect, "{:#?}", steps);

        // The zip is of the signed universal app, and the plain DMG is a copy
        // of the universal one.
        let zip = r
            .calls
            .iter()
            .find(|c| c.starts_with("ditto -c -k --keepParent "))
            .unwrap();
        assert!(zip.ends_with(&format!(
            "/Vitruvian.app {}",
            d("Vitruvian-3.86.0-universal.zip")
        )));
        assert!(dist.join("Vitruvian-3.86.0.dmg").is_file());
        let ls = r.calls.last().unwrap();
        assert_eq!(
            *ls,
            format!(
                "ls -lh {} {} {} {}",
                d("Vitruvian-3.86.0-arm64.dmg"),
                d("Vitruvian-3.86.0-universal.dmg"),
                d("Vitruvian-3.86.0-x86_64.dmg"),
                d("Vitruvian-3.86.0.dmg"),
            )
        );
        // The entitlements are the package's.
        assert!(r.calls.iter().any(|c| c.contains(&format!(
            "--entitlements {} ",
            s.pkg.join(ENTITLEMENTS_REL).display()
        ))));
        // The stage is gone.
        assert_eq!(fs::read_dir(&s.tmp).unwrap().count(), 0);
    }

    #[test]
    fn only_programs_that_hold_the_arch_are_thinned() {
        let s = scene("package_release_lipo");
        let mut r = FakeRunner::new({
            let mut inner = mac(None, None);
            move |c| {
                if c.program == "lipo"
                    && c.args[0] == "-info"
                    && c.args[1].contains("gravastar-mouse")
                {
                    return Out::ok("Non-fat file: x is architecture: arm64\n");
                }
                inner.output(c)
            }
        });
        package_release(&mut r, &mut LoggedTools, &s.pkg, &s.archive, &s.tmp).unwrap();
        let thins = |arch: &str| {
            r.calls
                .iter()
                .filter(|c| c.starts_with("lipo ") && c.contains(&format!(" -thin {} ", arch)))
                .count()
        };
        assert_eq!(thins("arm64"), 4);
        assert_eq!(thins("x86_64"), 3);
    }

    #[test]
    fn a_failed_notarization_stops_the_release_with_its_code() {
        let s = scene("package_release_notary_fail");
        struct FailingNotary;
        impl Packaging for FailingNotary {
            fn notarize(&mut self, _r: &mut dyn Runner, _t: &Path) -> Result<(), i32> {
                Err(7)
            }
            fn make_dmg(&mut self, _r: &mut dyn Runner, _a: &Path, _o: &Path) -> Result<(), i32> {
                panic!("packaged after a failed notarization")
            }
        }
        let mut r = mac(None, None);
        assert_eq!(
            package_release(&mut r, &mut FailingNotary, &s.pkg, &s.archive, &s.tmp),
            Err(7)
        );
        assert_eq!(fs::read_dir(&s.tmp).unwrap().count(), 0);
    }
}
