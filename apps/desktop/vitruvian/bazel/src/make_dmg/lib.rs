// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Copyright (C) 2026 VitruvianSoftware

//! Packages a signed app into a styled, distributable DMG
//! (`dist/Vitruvian-<version>.dmg` unless told where): a window with the app
//! icon, an arrow and the Applications folder for drag-and-drop install.
//! Ported from upstream's `Tools/make-dmg.sh`; package_release calls it.
//!
//! Nothing here writes into a "build" directory: on macOS's case-insensitive
//! filesystem that name is the package's Bazel BUILD file, so the background
//! renders into this run's own temp dir.

use release_exec::{
    capture, detect_developer_id, make_temp_dir, plist_short_version, run, Cmd, Out, Runner,
};
use std::fs;
use std::path::{Path, PathBuf};
use std::time::Duration;

pub const APP_NAME: &str = "Vitruvian";
pub const VOLUME: &str = "Vitruvian";

/// How long Finder may take to style the window before it is killed and the
/// DMG ships unstyled.
pub const STYLE_LIMIT: Duration = Duration::from_secs(25);

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DmgRequest {
    /// `apps/desktop/vitruvian`: where `Tools/MakeDMGBackground.swift` and
    /// the default `dist/` are.
    pub pkg_dir: PathBuf,
    /// The signed `Vitruvian.app`.
    pub app: PathBuf,
    /// Where the DMG goes; `<pkg_dir>/dist/Vitruvian-<version>.dmg` if not set.
    pub out: Option<PathBuf>,
    /// `DEVELOPER_ID` from the environment: signs the image with this identity
    /// instead of the installed Developer ID.
    pub developer_id: Option<String>,
    /// Where the work and staging folders are made (`$TMPDIR`).
    pub tmp_root: PathBuf,
}

pub fn usage() -> String {
    format!(
        "usage: make-dmg <path to the signed {}.app> [output.dmg]",
        APP_NAME
    )
}

/// The app and the optional output the command line names.
pub fn parse_cli_args(args: &[String]) -> Result<(String, Option<String>), String> {
    match args {
        [app] if !app.is_empty() => Ok((app.clone(), None)),
        [app, out] if !app.is_empty() => Ok((app.clone(), Some(out.clone()))),
        _ => Err(usage()),
    }
}

/// The mounted volume in `hdiutil attach` output: everything from
/// `/Volumes/` on, on the first line that has it.
pub fn parse_mount_point(attach_output: &str) -> Option<String> {
    attach_output.lines().find_map(|line| {
        line.find("/Volumes/")
            .map(|idx| line[idx..].trim_end().to_string())
            .filter(|m| !m.is_empty())
    })
}

/// The AppleScript that lays out Finder's window.
pub fn render_finder_applescript(volume: &str, app_name: &str) -> String {
    [
        "tell application \"Finder\"".to_string(),
        format!("    tell disk \"{}\"", volume),
        "        open".to_string(),
        "        set current view of container window to icon view".to_string(),
        "        set toolbar visible of container window to false".to_string(),
        "        set statusbar visible of container window to false".to_string(),
        "        set the bounds of container window to {200, 120, 800, 520}".to_string(),
        "        set theOptions to the icon view options of container window".to_string(),
        "        set arrangement of theOptions to not arranged".to_string(),
        "        set icon size of theOptions to 128".to_string(),
        "        set text size of theOptions to 13".to_string(),
        "        set background picture of theOptions to file \".background:background.png\""
            .to_string(),
        format!(
            "        set position of item \"{}.app\" of container window to {{150, 200}}",
            app_name
        ),
        "        set position of item \"Applications\" of container window to {450, 200}"
            .to_string(),
        "        update without registering applications".to_string(),
        "        delay 1".to_string(),
        "        close".to_string(),
        "    end tell".to_string(),
        "end tell".to_string(),
        String::new(),
    ]
    .join("\n")
}

/// Clears extended attributes on everything in `dir`, ignoring failures.
fn clear_xattrs(r: &mut dyn Runner, dir: &Path) {
    let _ = r.output(
        &Cmd::new("find")
            .path(dir)
            .args(["-exec", "xattr", "-c", "{}", "+"]),
    );
}

fn image_attached(r: &mut dyn Runner, image: &Path) -> bool {
    let out = r.output(&Cmd::new("hdiutil").arg("info"));
    out.success() && out.stdout.contains(&*image.to_string_lossy())
}

/// Detaches every attachment of one image, found by the image's path. It
/// reaches an attachment that has no mount point and whose device nobody
/// recorded.
fn release_image(r: &mut dyn Runner, image: &Path) {
    let info = r.output(&Cmd::new("hdiutil").arg("info"));
    for device in dmg_image_devices::extract_devices(&info.stdout, &image.to_string_lossy()) {
        let _ = r.status(&Cmd::new("hdiutil").args(["detach", &device, "-force"]));
    }
}

/// What the exit cleanup still has to undo.
#[derive(Default)]
struct Leftovers {
    mount: Option<String>,
    dirs: Vec<PathBuf>,
}

fn clean_up(r: &mut dyn Runner, left: &mut Leftovers) {
    if let Some(mount) = left.mount.take() {
        if r.output(&Cmd::new("hdiutil").args(["detach", &mount, "-quiet"]))
            .code
            != 0
        {
            let _ = r.output(&Cmd::new("hdiutil").args(["detach", &mount, "-force", "-quiet"]));
        }
    }
    for d in left.dirs.drain(..) {
        let _ = fs::remove_dir_all(d);
    }
}

/// Builds the DMG and returns where it is. A failure is the exit code the
/// script would have stopped with.
pub fn make_dmg(r: &mut dyn Runner, req: &DmgRequest) -> Result<PathBuf, i32> {
    let mut left = Leftovers::default();
    let result = build(r, req, &mut left);
    clean_up(r, &mut left);
    result
}

fn fs_step<T>(what: &str, res: std::io::Result<T>) -> Result<T, i32> {
    res.map_err(|e| {
        eprintln!("✗ {}: {}", what, e);
        1
    })
}

fn build(r: &mut dyn Runner, req: &DmgRequest, left: &mut Leftovers) -> Result<PathBuf, i32> {
    let app = &req.app;
    if !app.is_dir() {
        eprintln!("✗ {} not found", app.display());
        return Err(1);
    }
    clear_xattrs(r, app);
    run(
        r,
        &Cmd::new("codesign")
            .args(["--verify", "--deep", "--strict"])
            .path(app),
    )?;

    let version = plist_short_version(r, &app.join("Contents/Info.plist"))?;
    let out = req.out.clone().unwrap_or_else(|| {
        req.pkg_dir
            .join("dist")
            .join(format!("{}-{}.dmg", APP_NAME, version))
    });

    let work = fs_step("mktemp", make_temp_dir(&req.tmp_root, "vitruvian-dmg-work"))?;
    left.dirs.push(work.clone());
    let background = work.join("dmg-background.png");

    println!("▸ Rendering installer background…");
    run(
        r,
        &Cmd::new("swift")
            .arg("Tools/MakeDMGBackground.swift")
            .path(&background)
            .cwd(&req.pkg_dir),
    )?;

    println!("▸ Staging DMG contents…");
    let staging = fs_step(
        "mktemp",
        make_temp_dir(&req.tmp_root, "vitruvian-dmg-stage"),
    )?;
    left.dirs.push(staging.clone());
    let staged_app = staging.join(format!("{}.app", APP_NAME));
    run(r, &Cmd::new("ditto").path(app).path(&staged_app))?;
    clear_xattrs(r, &staged_app);
    run(
        r,
        &Cmd::new("codesign")
            .args(["--verify", "--deep", "--strict"])
            .path(&staged_app),
    )?;
    #[cfg(unix)]
    fs_step(
        "ln -s /Applications",
        std::os::unix::fs::symlink("/Applications", staging.join("Applications")),
    )?;
    fs_step(
        "mkdir .background",
        fs::create_dir(staging.join(".background")),
    )?;
    fs_step(
        "cp background.png",
        fs::copy(&background, staging.join(".background/background.png")),
    )?;

    println!("▸ Creating writable image…");
    // Clear any stale mount left by a previous attempt on the same runner.
    let _ =
        r.output(&Cmd::new("hdiutil").args(["detach", &format!("/Volumes/{}", VOLUME), "-force"]));
    // hdiutil can fail transiently on CI runners; retry a few times. No
    // -quiet, so a real error is visible in the build log.
    //
    // A create that fails with "Resource busy" can leave its half-made image
    // attached. Each attempt therefore writes its own file, so a leftover from
    // a failed attempt is never mistaken for the image being packaged, and
    // the leftover is detached before the next attempt.
    let mut rw = None;
    for attempt in 1..=3 {
        let candidate = work.join(format!("rw-{}.dmg", attempt));
        let create = Cmd::new("hdiutil")
            .args(["create", "-volname", VOLUME, "-srcfolder"])
            .path(&staging)
            .args(["-fs", "HFS+", "-format", "UDRW", "-ov"])
            .path(&candidate);
        if r.status(&create) == 0 {
            rw = Some(candidate);
            break;
        }
        eprintln!(
            "  hdiutil create failed (attempt {} of 3), retrying…",
            attempt
        );
        release_image(r, &candidate);
        let _ = fs::remove_file(&candidate);
        r.sleep(Duration::from_secs(3));
    }
    let Some(rw) = rw else {
        eprintln!("✗ Could not create the disk image after 3 attempts");
        return Err(1);
    };

    let attach_output = capture(
        r,
        &Cmd::new("hdiutil").arg("attach").path(&rw).arg("-nobrowse"),
    )?;
    let mount = parse_mount_point(&attach_output).unwrap_or_default();
    if mount.is_empty() || !r.is_dir(Path::new(&mount)) {
        eprintln!("✗ Could not find mounted volume in hdiutil output");
        eprintln!("{}", attach_output.trim_end());
        return Err(1);
    }
    left.mount = Some(mount.clone());

    println!("▸ Arranging window (icons, arrow, background)…");
    // Finder automation lays out the window; best-effort so a headless hiccup
    // never fails the release (the DMG is still valid, just unstyled that
    // once).
    let style = Cmd::new("osascript").stdin(&render_finder_applescript(VOLUME, APP_NAME));
    match r.status_within(&style, STYLE_LIMIT) {
        None => println!("  (window styling timed out; continuing with a valid unstyled DMG)"),
        Some(0) => {}
        Some(_) => println!("  (window styling skipped)"),
    }

    let _ = r.status(&Cmd::new("sync"));
    // Finder can keep the volume busy for a moment after its window closes,
    // and a busy volume refuses to detach, forced or not. Retry before
    // forcing; no -quiet, so a real failure says why in the build log.
    let mut detached = false;
    for attempt in 1..=4 {
        if r.status(&Cmd::new("hdiutil").args(["detach", &mount])) == 0 {
            detached = true;
            break;
        }
        // A detach that reported "Resource busy" can still finish a moment
        // later. Once the mount is gone there is nothing left to detach, and
        // asking again fails with "No such file or directory", which is not a
        // failure.
        if !r.is_dir(Path::new(&mount)) {
            detached = true;
            break;
        }
        eprintln!(
            "  hdiutil detach failed (attempt {} of 4), retrying…",
            attempt
        );
        r.sleep(Duration::from_secs(2));
    }
    if !detached && r.is_dir(Path::new(&mount)) {
        run(r, &Cmd::new("hdiutil").args(["detach", &mount, "-force"]))?;
    }
    left.mount = None;

    // The mount point can vanish while the image is still attached, and
    // converting an attached image fails. Wait until the image itself is
    // released.
    for _ in 1..=5 {
        if !image_attached(r, &rw) {
            break;
        }
        r.sleep(Duration::from_secs(2));
    }
    // Still attached with the mount folder gone: a detach by path has nothing
    // to act on, so release the image by its device nodes, forced.
    if image_attached(r, &rw) {
        for attempt in 1..=5 {
            release_image(r, &rw);
            if !image_attached(r, &rw) {
                break;
            }
            eprintln!(
                "  image still attached after forced detach (attempt {} of 5), retrying…",
                attempt
            );
            r.sleep(Duration::from_secs(3));
        }
    }
    if image_attached(r, &rw) {
        eprintln!("✗ The disk image is still attached and cannot be compressed");
        let info: Out = r.output(&Cmd::new("hdiutil").arg("info"));
        eprint!("{}", info.stdout);
        return Err(1);
    }

    println!("▸ Compressing…");
    if let Some(parent) = out.parent().filter(|p| !p.as_os_str().is_empty()) {
        fs_step("mkdir -p", fs::create_dir_all(parent))?;
    }
    let _ = fs::remove_file(&out);
    // No -quiet, so a failure says why; a convert can lose a race with a late
    // detach, so try again before giving up.
    let mut converted = false;
    for attempt in 1..=3 {
        let convert = Cmd::new("hdiutil")
            .arg("convert")
            .path(&rw)
            .args(["-format", "UDZO", "-imagekey", "zlib-level=9", "-o"])
            .path(&out);
        if r.status(&convert) == 0 {
            converted = true;
            break;
        }
        eprintln!(
            "  hdiutil convert failed (attempt {} of 3), retrying…",
            attempt
        );
        let _ = fs::remove_file(&out);
        r.sleep(Duration::from_secs(5));
    }
    if !converted {
        eprintln!("✗ Could not compress the disk image after 3 attempts");
        return Err(1);
    }

    // Sign the image itself, not only the app inside it. Gatekeeper judges a
    // downloaded disk image by the image's own signature before it mounts; an
    // unsigned image that was notarized still fails `spctl -t open`. This
    // runs before notarize submits the image, so the image is signed and
    // notarized.
    let identity = req
        .developer_id
        .clone()
        .filter(|s| !s.is_empty())
        .or_else(|| detect_developer_id(r));
    match identity {
        Some(id) => {
            println!("▸ Signing the disk image with {}…", id);
            run(
                r,
                &Cmd::new("codesign")
                    .args(["--force", "--timestamp", "--sign", &id])
                    .path(&out),
            )?;
            run(
                r,
                &Cmd::new("codesign")
                    .args(["--verify", "--strict"])
                    .path(&out),
            )?;
        }
        None => println!("▸ No Developer ID identity installed; the disk image stays unsigned"),
    }

    println!("✓ DMG ready: {}", out.display());
    Ok(out)
}

pub fn run_cli(args: &[String]) -> i32 {
    let (app, out) = match parse_cli_args(args) {
        Ok(v) => v,
        Err(msg) => {
            eprintln!("{}", msg);
            return 1;
        }
    };
    let req = DmgRequest {
        pkg_dir: release_exec::package_dir(),
        app: release_exec::user_path(&app),
        out: out.as_deref().map(release_exec::user_path),
        developer_id: std::env::var("DEVELOPER_ID").ok(),
        tmp_root: release_exec::temp_root(),
    };
    match make_dmg(&mut release_exec::SystemRunner::from_env(), &req) {
        Ok(_) => 0,
        Err(code) => code,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use release_exec::{FakeRunner, TempDir};
    use std::cell::RefCell;
    use std::rc::Rc;

    struct Scene {
        _guard: TempDir,
        root: PathBuf,
        req: DmgRequest,
        mount: PathBuf,
    }

    fn scene(name: &str) -> Scene {
        let root = make_temp_dir(&std::env::temp_dir(), name).unwrap();
        let app = root.join("in/Vitruvian.app");
        fs::create_dir_all(app.join("Contents")).unwrap();
        fs::create_dir_all(root.join("pkg")).unwrap();
        fs::create_dir_all(root.join("tmp")).unwrap();
        let mount = PathBuf::from("/Volumes/Vitruvian");
        Scene {
            _guard: TempDir(root.clone()),
            req: DmgRequest {
                pkg_dir: root.join("pkg"),
                app,
                out: None,
                developer_id: None,
                tmp_root: root.join("tmp"),
            },
            mount,
            root,
        }
    }

    /// The machine a DMG is built on, as hdiutil and friends answer.
    #[derive(Default)]
    struct Mac {
        /// `hdiutil create` fails this many times first, each leaving its
        /// half-made image attached.
        create_failures: u32,
        /// `hdiutil detach <mount>` fails this many times first.
        detach_failures: u32,
        /// The mount folder disappears on a failed detach.
        mount_vanishes: bool,
        /// After the mount is detached, `hdiutil info` still lists the image
        /// this many times.
        lingering: u32,
        /// A forced detach of the device never releases the image.
        stuck: bool,
        convert_failures: u32,
        style: i32,
        identity: Option<String>,
        /// The image `hdiutil info` lists, if any.
        listed: Option<String>,
        last_image: String,
        mounted: bool,
    }

    fn listing(img: &str) -> String {
        format!(
            "================\nimage-path      : {}\n/dev/disk9\tGUID_partition_scheme\t\n/dev/disk9s1\tApple_HFS\t\n",
            img
        )
    }

    fn mac_runner(scene: &Scene, mac: Mac) -> (FakeRunner, Rc<RefCell<Mac>>) {
        let state = Rc::new(RefCell::new(mac));
        let s = state.clone();
        let mount = scene.mount.clone();
        let mount_s = mount.to_string_lossy().to_string();
        let mount2 = mount.clone();
        let r = FakeRunner::new(move |c| {
            let mut m = s.borrow_mut();
            let a: Vec<&str> = c.args.iter().map(String::as_str).collect();
            match (c.program.as_str(), a.as_slice()) {
                ("/usr/libexec/PlistBuddy", _) => Out::ok("3.86.0\n"),
                ("swift", [_, bg]) => {
                    fs::write(bg, b"png").unwrap();
                    Out::ok("")
                }
                ("hdiutil", ["create", .., rw]) => {
                    m.last_image = rw.to_string();
                    if m.create_failures > 0 {
                        m.create_failures -= 1;
                        m.listed = Some(rw.to_string());
                        Out::fail(1, "hdiutil: create failed - Resource busy")
                    } else {
                        fs::write(rw, b"rw").unwrap();
                        Out::ok("")
                    }
                }
                ("hdiutil", ["info"]) => match m.listed.clone() {
                    Some(img) => {
                        if m.lingering > 0 {
                            m.lingering -= 1;
                            if m.lingering == 0 && !m.stuck {
                                m.listed = None;
                            }
                        }
                        Out::ok(&listing(&img))
                    }
                    None => Out::ok("================\n"),
                },
                ("hdiutil", ["attach", ..]) => {
                    m.mounted = true;
                    m.listed = Some(m.last_image.clone());
                    Out::ok(&format!(
                        "/dev/disk9\tGUID_partition_scheme\t\n/dev/disk9s1\tApple_HFS\t{}\n",
                        mount.display()
                    ))
                }
                ("hdiutil", ["detach", "/dev/disk9", "-force"]) => {
                    if !m.stuck {
                        m.listed = None;
                    }
                    Out::ok("")
                }
                ("hdiutil", ["detach", target, rest @ ..]) if *target == mount_s => {
                    if rest.is_empty() && m.detach_failures > 0 {
                        m.detach_failures -= 1;
                        if m.mount_vanishes {
                            m.mounted = false;
                            if m.lingering == 0 && !m.stuck {
                                m.listed = None;
                            }
                        }
                        return Out::fail(16, "hdiutil: couldn't unmount - Resource busy");
                    }
                    m.mounted = false;
                    if m.lingering == 0 && !m.stuck {
                        m.listed = None;
                    }
                    Out::ok("")
                }
                ("hdiutil", ["convert", .., out]) => {
                    if m.convert_failures > 0 {
                        m.convert_failures -= 1;
                        Out::fail(1, "convert failed")
                    } else {
                        fs::write(out, b"udzo").unwrap();
                        Out::ok("")
                    }
                }
                ("osascript", _) => Out::fail(m.style, ""),
                ("security", _) => match &m.identity {
                    Some(id) => Out::ok(&format!(
                        "  1) ABC \"{}\"\n     1 valid identities found\n",
                        id
                    )),
                    None => Out::ok("     0 valid identities found\n"),
                },
                _ => Out::ok(""),
            }
        });
        let s2 = state.clone();
        let r = r.with_dirs(move |p| {
            if p == mount2 {
                s2.borrow().mounted
            } else {
                p.is_dir()
            }
        });
        (r, state)
    }

    /// How many calls after the image was attached start with `prefix` (the
    /// stale-mount clear before creating names the same /Volumes path).
    fn count_after_attach(r: &FakeRunner, prefix: &str) -> usize {
        let at = r.position("hdiutil attach").expect("attached");
        r.calls[at..]
            .iter()
            .filter(|c| c.starts_with(prefix))
            .count()
    }

    #[test]
    fn usage() {
        assert!(parse_cli_args(&[]).is_err());
        assert_eq!(
            parse_cli_args(&["a.app".into()]),
            Ok(("a.app".to_string(), None))
        );
        assert_eq!(
            parse_cli_args(&["a.app".into(), "o.dmg".into()]),
            Ok(("a.app".to_string(), Some("o.dmg".to_string())))
        );
    }

    #[test]
    fn mount_point_keeps_spaces_in_the_volume_name() {
        let out =
            "/dev/disk6\tGUID_partition_scheme\t\n/dev/disk6s1\tApple_HFS\t/Volumes/Vitruvian 1\n";
        assert_eq!(
            parse_mount_point(out).as_deref(),
            Some("/Volumes/Vitruvian 1")
        );
        assert_eq!(parse_mount_point("/dev/disk6\t\n"), None);
    }

    #[test]
    fn the_finder_script_is_the_heredoc_upstream_wrote() {
        let want = "tell application \"Finder\"\n    tell disk \"Vitruvian\"\n        open\n        set current view of container window to icon view\n        set toolbar visible of container window to false\n        set statusbar visible of container window to false\n        set the bounds of container window to {200, 120, 800, 520}\n        set theOptions to the icon view options of container window\n        set arrangement of theOptions to not arranged\n        set icon size of theOptions to 128\n        set text size of theOptions to 13\n        set background picture of theOptions to file \".background:background.png\"\n        set position of item \"Vitruvian.app\" of container window to {150, 200}\n        set position of item \"Applications\" of container window to {450, 200}\n        update without registering applications\n        delay 1\n        close\n    end tell\nend tell\n";
        assert_eq!(render_finder_applescript(VOLUME, APP_NAME), want);
    }

    #[test]
    fn a_missing_app_fails_before_any_command() {
        let s = scene("make_dmg_missing");
        let mut req = s.req.clone();
        req.app = s.root.join("nope.app");
        let mut r = FakeRunner::succeeding();
        assert_eq!(make_dmg(&mut r, &req), Err(1));
        assert!(r.calls.is_empty());
    }

    #[test]
    fn the_happy_path_stages_creates_styles_detaches_compresses_and_signs_after() {
        let s = scene("make_dmg_happy");
        let (mut r, _) = mac_runner(
            &s,
            Mac {
                identity: Some("Developer ID Application: V (T)".into()),
                ..Mac::default()
            },
        );
        let out = make_dmg(&mut r, &s.req).unwrap();
        assert_eq!(out, s.req.pkg_dir.join("dist/Vitruvian-3.86.0.dmg"));
        assert!(out.is_file());

        let c = &r.calls;
        let app = s.req.app.to_string_lossy().to_string();
        assert_eq!(c[0], format!("find {} -exec xattr -c {{}} +", app));
        assert_eq!(c[1], format!("codesign --verify --deep --strict {}", app));
        let bg = r.cmds.iter().find(|c| c.program == "swift").unwrap();
        assert_eq!(bg.args[0], "Tools/MakeDMGBackground.swift");
        assert_eq!(bg.cwd.as_deref(), Some(s.req.pkg_dir.as_path()));
        let create = r
            .position("hdiutil create -volname Vitruvian -srcfolder ")
            .unwrap();
        assert!(
            c[create].contains(" -fs HFS+ -format UDRW -ov ") && c[create].ends_with("/rw-1.dmg")
        );
        assert!(
            r.position("hdiutil detach /Volumes/Vitruvian -force")
                .unwrap()
                < create
        );
        let osa = r.cmds.iter().find(|c| c.program == "osascript").unwrap();
        assert!(String::from_utf8_lossy(osa.stdin.as_ref().unwrap())
            .contains("tell disk \"Vitruvian\""));
        let convert = r.position("hdiutil convert ").unwrap();
        assert!(c[convert].ends_with(&format!(
            "/rw-1.dmg -format UDZO -imagekey zlib-level=9 -o {}",
            out.display()
        )));
        assert!(!c[convert].contains("-quiet"));
        let sign = r
            .position("codesign --force --timestamp --sign Developer ID Application: V (T) ")
            .unwrap();
        assert!(sign > convert, "the image is signed after it is compressed");
        assert!(
            r.position("codesign --force").unwrap() > convert,
            "nothing signs the image before it is compressed"
        );
        assert_eq!(
            c[sign + 1],
            format!("codesign --verify --strict {}", out.display())
        );
        // Staging and work folders are gone; the staged tree had the link
        // and background.
        assert_eq!(fs::read_dir(&s.req.tmp_root).unwrap().count(), 0);
    }

    #[test]
    fn the_staging_folder_holds_the_app_the_applications_link_and_the_background() {
        let s = scene("make_dmg_stage");
        let seen = Rc::new(RefCell::new(Vec::new()));
        let seen2 = seen.clone();
        let (inner, _) = mac_runner(&s, Mac::default());
        let inner = Rc::new(RefCell::new(inner));
        let inner2 = inner.clone();
        let r = FakeRunner::new(move |c| {
            if c.program == "hdiutil" && c.args.first().map(String::as_str) == Some("create") {
                let staging = PathBuf::from(&c.args[4]);
                let mut names: Vec<String> = fs::read_dir(&staging)
                    .unwrap()
                    .map(|e| e.unwrap().file_name().to_string_lossy().to_string())
                    .collect();
                names.sort();
                seen2.borrow_mut().push((
                    names,
                    fs::read_link(staging.join("Applications")).ok(),
                    staging.join(".background/background.png").is_file(),
                ));
            }
            inner2.borrow_mut().output(c)
        });
        let inner3 = inner.clone();
        let mut r = r.with_dirs(move |p| inner3.borrow_mut().is_dir(p));
        make_dmg(&mut r, &s.req).unwrap();
        assert_eq!(
            seen.borrow()[0],
            (
                vec![".background".to_string(), "Applications".to_string()],
                Some(PathBuf::from("/Applications")),
                true
            ),
            "ditto is faked, so the app itself is not in the folder"
        );
    }

    #[test]
    fn a_failed_create_releases_its_leftover_and_the_next_attempt_writes_a_new_file() {
        let s = scene("make_dmg_create_retry");
        let (mut r, _) = mac_runner(
            &s,
            Mac {
                create_failures: 2,
                ..Mac::default()
            },
        );
        make_dmg(&mut r, &s.req).unwrap();
        let creates: Vec<&String> = r
            .calls
            .iter()
            .filter(|c| c.starts_with("hdiutil create"))
            .collect();
        assert_eq!(creates.len(), 3);
        assert!(creates[0].ends_with("/rw-1.dmg"));
        assert!(creates[1].ends_with("/rw-2.dmg"));
        assert!(creates[2].ends_with("/rw-3.dmg"));
        // Each failure detaches the half-made image by its device node.
        let first = r.position("hdiutil create").unwrap();
        assert_eq!(r.calls[first + 1], "hdiutil info");
        assert_eq!(r.calls[first + 2], "hdiutil detach /dev/disk9 -force");
        assert_eq!(r.slept, Duration::from_secs(6));
        assert!(r
            .calls
            .iter()
            .any(|c| c.starts_with("hdiutil convert") && c.contains("/rw-3.dmg ")));
    }

    #[test]
    fn three_failed_creates_fail_the_dmg_and_clean_up() {
        let s = scene("make_dmg_create_fail");
        let (mut r, _) = mac_runner(
            &s,
            Mac {
                create_failures: 3,
                ..Mac::default()
            },
        );
        assert_eq!(make_dmg(&mut r, &s.req), Err(1));
        assert_eq!(r.count("hdiutil create"), 3);
        assert_eq!(r.count("hdiutil attach"), 0);
        assert_eq!(fs::read_dir(&s.req.tmp_root).unwrap().count(), 0);
    }

    #[test]
    fn a_busy_detach_is_retried_and_forced_only_while_the_mount_exists() {
        let s = scene("make_dmg_detach_force");
        let (mut r, _) = mac_runner(
            &s,
            Mac {
                detach_failures: 4,
                ..Mac::default()
            },
        );
        // Four busy detaches, then a forced one (which the fake answers by
        // succeeding without removing the folder).
        make_dmg(&mut r, &s.req).unwrap();
        let mount = s.mount.to_string_lossy().to_string();
        assert_eq!(
            count_after_attach(&r, &format!("hdiutil detach {}", mount)),
            5
        );
        assert_eq!(
            count_after_attach(&r, &format!("hdiutil detach {} -force", mount)),
            1
        );
    }

    #[test]
    fn a_mount_that_is_gone_after_a_busy_detach_is_not_detached_again() {
        let s = scene("make_dmg_detach_gone");
        let (mut r, _) = mac_runner(
            &s,
            Mac {
                detach_failures: 1,
                mount_vanishes: true,
                ..Mac::default()
            },
        );
        make_dmg(&mut r, &s.req).unwrap();
        let mount = s.mount.to_string_lossy().to_string();
        assert_eq!(
            count_after_attach(&r, &format!("hdiutil detach {}", mount)),
            1
        );
        assert_eq!(r.slept, Duration::ZERO);
    }

    #[test]
    fn a_still_attached_image_is_waited_for_then_released_before_converting() {
        let s = scene("make_dmg_wait_release");
        let (mut r, _) = mac_runner(
            &s,
            Mac {
                lingering: 7,
                ..Mac::default()
            },
        );
        make_dmg(&mut r, &s.req).unwrap();
        let force = r.position("hdiutil detach /dev/disk9 -force").unwrap();
        let convert = r.position("hdiutil convert").unwrap();
        assert!(
            force < convert,
            "the image is released by its device before converting"
        );
        // Five waits of 2s while it was still listed.
        assert_eq!(r.slept, Duration::from_secs(10));
    }

    #[test]
    fn an_image_that_will_not_release_fails_before_converting() {
        let s = scene("make_dmg_stuck");
        let (mut r, _) = mac_runner(
            &s,
            Mac {
                lingering: 1000,
                stuck: true,
                ..Mac::default()
            },
        );
        assert_eq!(make_dmg(&mut r, &s.req), Err(1));
        assert_eq!(r.count("hdiutil detach /dev/disk9 -force"), 5);
        assert_eq!(r.count("hdiutil convert"), 0);
        assert_eq!(fs::read_dir(&s.req.tmp_root).unwrap().count(), 0);
    }

    #[test]
    fn a_failed_convert_is_retried() {
        let s = scene("make_dmg_convert_retry");
        let (mut r, _) = mac_runner(
            &s,
            Mac {
                convert_failures: 2,
                ..Mac::default()
            },
        );
        make_dmg(&mut r, &s.req).unwrap();
        assert_eq!(r.count("hdiutil convert"), 3);
        assert_eq!(r.slept, Duration::from_secs(10));

        let s = scene("make_dmg_convert_fail");
        let (mut r, _) = mac_runner(
            &s,
            Mac {
                convert_failures: 3,
                ..Mac::default()
            },
        );
        assert_eq!(make_dmg(&mut r, &s.req), Err(1));
        assert_eq!(r.count("codesign --force"), 0);
    }

    #[test]
    fn styling_that_fails_or_hangs_never_fails_the_dmg() {
        for style in [1, FakeRunner::TIMED_OUT] {
            let s = scene("make_dmg_style");
            let (mut r, _) = mac_runner(
                &s,
                Mac {
                    style,
                    ..Mac::default()
                },
            );
            assert!(make_dmg(&mut r, &s.req).is_ok(), "style {}", style);
        }
    }

    #[test]
    fn finder_gets_25_seconds_to_style_the_window() {
        let s = scene("make_dmg_style_limit");
        let (mut r, _) = mac_runner(&s, Mac::default());
        make_dmg(&mut r, &s.req).unwrap();
        assert_eq!(
            r.limits,
            vec![("osascript".to_string(), Duration::from_secs(25))]
        );
    }

    #[test]
    fn a_failed_attach_says_why() {
        let s = scene("make_dmg_attach_fails");
        let (inner, _) = mac_runner(&s, Mac::default());
        let inner = Rc::new(RefCell::new(inner));
        let inner_dirs = inner.clone();
        let r = FakeRunner::new(move |c| {
            if c.program == "hdiutil" && c.args.first().map(String::as_str) == Some("attach") {
                return Out::fail(1, "hdiutil: attach failed - no mountable file systems\n");
            }
            inner.borrow_mut().output(c)
        });
        let mut r = r.with_dirs(move |p| inner_dirs.borrow_mut().is_dir(p));
        assert_eq!(make_dmg(&mut r, &s.req), Err(1));
        assert!(
            r.stderr
                .contains("hdiutil: attach failed - no mountable file systems"),
            "hdiutil's own error reaches the log: {:?}",
            r.stderr
        );
        assert!(r.stderr.contains("hdiutil attach "), "{:?}", r.stderr);
    }

    #[test]
    fn without_an_identity_the_image_stays_unsigned_and_developer_id_overrides_the_keychain() {
        let s = scene("make_dmg_unsigned");
        let (mut r, _) = mac_runner(&s, Mac::default());
        make_dmg(&mut r, &s.req).unwrap();
        assert_eq!(r.count("codesign --force"), 0);

        let s = scene("make_dmg_env_identity");
        let mut req = s.req.clone();
        req.developer_id = Some("Developer ID Application: From Env (E)".into());
        req.out = Some(s.root.join("elsewhere/x.dmg"));
        let (mut r, _) = mac_runner(
            &s,
            Mac {
                identity: Some("Developer ID Application: Keychain (K)".into()),
                ..Mac::default()
            },
        );
        let out = make_dmg(&mut r, &req).unwrap();
        assert_eq!(out, s.root.join("elsewhere/x.dmg"));
        assert_eq!(r.count("security find-identity"), 0);
        assert_eq!(
            r.count("codesign --force --timestamp --sign Developer ID Application: From Env (E) "),
            1
        );
    }

    #[test]
    fn a_failure_after_attaching_detaches_the_mount_on_the_way_out() {
        let s = scene("make_dmg_cleanup_mount");
        let mount = s.mount.to_string_lossy().to_string();
        let (inner, _) = mac_runner(&s, Mac::default());
        let inner = Rc::new(RefCell::new(inner));
        let inner_dirs = inner.clone();
        let m2 = mount.clone();
        let r = FakeRunner::new(move |c| {
            // Every detach of the mount, forced or not, says busy.
            if c.program == "hdiutil"
                && c.args.len() >= 2
                && c.args[0] == "detach"
                && c.args[1] == m2
            {
                return Out::fail(16, "busy");
            }
            inner.borrow_mut().output(c)
        });
        let mut r = r.with_dirs(move |p| inner_dirs.borrow_mut().is_dir(p));
        assert_eq!(make_dmg(&mut r, &s.req), Err(16));
        let at = r.position("hdiutil attach").unwrap();
        let exactly = |line: String| r.calls[at..].iter().filter(|c| **c == line).count();
        assert_eq!(exactly(format!("hdiutil detach {} -force", mount)), 1);
        assert!(r
            .calls
            .iter()
            .any(|c| c == &format!("hdiutil detach {} -quiet", mount)));
        assert!(r
            .calls
            .iter()
            .any(|c| c == &format!("hdiutil detach {} -force -quiet", mount)));
        assert_eq!(r.count("hdiutil convert"), 0);
        assert_eq!(fs::read_dir(&s.req.tmp_root).unwrap().count(), 0);
    }
}
