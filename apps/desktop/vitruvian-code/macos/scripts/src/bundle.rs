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

use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::Command;

// The folder is "Vitruvian Code.app" (the name people see in Finder); the program
// inside it has no space, as Swift and the brand standard (docs/standards/brand.md) name it.
const APP_NAME: &str = "Vitruvian Code";
const EXECUTABLE_NAME: &str = "VitruvianCode";
const BOT_NAME: &str = "bot-engine";
const BOT_SIGNING_ID: &str = "com.vitruviansoftware.code.bot-engine";
const NODE_NAME: &str = "node";
const NODE_SIGNING_ID: &str = "com.vitruviansoftware.code.node";
const NODE_ENTITLEMENTS_NAME: &str = "node.entitlements";
const HELPER_DIR_NAME: &str = "claude-helper";
const HELPER_FILE_NAME: &str = "claude-helper.mjs";
const BUNDLE_ID: &str = "com.vitruviansoftware.code";
const DISPLAY_NAME: &str = "Vitruvian Code";
const UI_RESOURCES: &str = "VitruvianCode_VitruvianCodeUI.bundle";

/// The architectures a universal app holds a thin copy of each helper for.
const ARCHS: [&str; 2] = ["arm64", "x86_64"];

/// Copies the helper `name` from beside the executable into `helpers_dir`, and
/// returns where the copies landed (one file, or two).
///
/// A universal app must not hold a fat helper: XProtect refuses it ("Internal
/// Xprotect Error"). So when `<name>-arm64` and `<name>-x86_64` sit beside the
/// executable, both go in, each thin and picked at run time by architecture.
/// Otherwise `<name>` goes in as it is, which is what a single-architecture app
/// holds.
fn copy_helper(exe_parent: &Path, helpers_dir: &Path, name: &str) -> Result<Vec<PathBuf>, String> {
    let per_arch: Vec<String> = ARCHS.iter().map(|a| format!("{}-{}", name, a)).collect();
    let names: Vec<String> = if per_arch.iter().all(|n| exe_parent.join(n).is_file()) {
        per_arch
    } else {
        vec![name.to_string()]
    };
    let mut copies = Vec::new();
    for n in &names {
        let src = exe_parent.join(n);
        if !src.is_file() {
            return Err(format!(
                "{} not found at {}.\n       Keep {} (or {}-arm64 and {}-x86_64) beside the executable before bundling.",
                n,
                src.display(),
                name,
                name,
                name
            ));
        }
        let dest = helpers_dir.join(n);
        fs::copy(&src, &dest).map_err(|e| format!("cannot copy {}: {}", n, e))?;
        fs::set_permissions(&dest, fs::Permissions::from_mode(0o755))
            .map_err(|e| format!("cannot mark {} executable: {}", n, e))?;
        println!("    \u{2713} {} copied", n);
        copies.push(dest);
    }
    Ok(copies)
}

/// Ad-hoc signs `target` with `identifier`, and `entitlements` when given.
fn codesign_adhoc(
    target: &Path,
    identifier: &str,
    entitlements: Option<&Path>,
    what: &str,
) -> Result<(), String> {
    let mut cmd = Command::new("codesign");
    cmd.args(["--force", "--sign", "-", "--identifier", identifier]);
    if let Some(ent) = entitlements {
        cmd.arg("--entitlements").arg(ent);
    }
    match cmd.arg(target).status() {
        Ok(s) if s.success() => Ok(()),
        Ok(s) => Err(format!(
            "codesign {} exited {}",
            what,
            s.code().unwrap_or(-1)
        )),
        Err(e) => Err(format!("cannot run codesign on {}: {}", what, e)),
    }
}

fn copy_dir_recursive(src: &Path, dst: &Path) -> std::io::Result<()> {
    fs::create_dir_all(dst)?;
    for entry in fs::read_dir(src)? {
        let entry = entry?;
        let ft = entry.file_type()?;
        let dest = dst.join(entry.file_name());
        if ft.is_dir() {
            copy_dir_recursive(&entry.path(), &dest)?;
        } else {
            fs::copy(entry.path(), &dest)?;
        }
    }
    Ok(())
}

pub fn run(args: &[String]) -> i32 {
    let rest = if args.len() > 1 { &args[1..] } else { &[] };
    if rest.len() != 3 {
        eprintln!("Usage: bundle-app <executable> <version> <output_dir>");
        return 2;
    }

    let executable = &rest[0];
    let version = &rest[1];
    let output_dir = &rest[2];

    let exe_path = PathBuf::from(executable);

    // Resolve RESOURCES_DIR the same way the shell script does:
    // SCRIPT_DIR=$(dirname "$0"), RESOURCES_DIR="${SCRIPT_DIR}/../Resources"
    // Fall back to standard workspace/mirror paths when compiled to $RUNNER_TEMP.
    let script_dir = match std::env::current_exe() {
        Ok(p) => p.parent().unwrap_or(Path::new(".")).to_path_buf(),
        Err(_) => PathBuf::from("."),
    };
    let resources_candidates = [
        script_dir.join("../Resources"),
        script_dir.join("Resources"),
        PathBuf::from("apps/desktop/vitruvian-code/macos/Resources"),
        PathBuf::from("macos/Resources"),
        PathBuf::from("Resources"),
    ];
    let resources_dir = resources_candidates
        .into_iter()
        .find(|p| p.is_dir())
        .unwrap_or_else(|| script_dir.join("../Resources"));

    let app_bundle = PathBuf::from(output_dir).join(format!("{}.app", APP_NAME));

    println!("==> Assembling {}.app v{}", APP_NAME, version);

    // Clean and create bundle structure
    let _ = fs::remove_dir_all(&app_bundle);
    let macos_dir = app_bundle.join("Contents/MacOS");
    let helpers_dir = app_bundle.join("Contents/Helpers");
    let res_dir = app_bundle.join("Contents/Resources");
    if let Err(e) = fs::create_dir_all(&macos_dir) {
        eprintln!("error: cannot create {}: {}", macos_dir.display(), e);
        return 1;
    }
    if let Err(e) = fs::create_dir_all(&helpers_dir) {
        eprintln!("error: cannot create {}: {}", helpers_dir.display(), e);
        return 1;
    }
    if let Err(e) = fs::create_dir_all(&res_dir) {
        eprintln!("error: cannot create {}: {}", res_dir.display(), e);
        return 1;
    }

    // Copy executable
    let dest_exe = macos_dir.join(EXECUTABLE_NAME);
    if let Err(e) = fs::copy(&exe_path, &dest_exe) {
        eprintln!("error: cannot copy executable: {}", e);
        return 1;
    }
    let _ = fs::set_permissions(&dest_exe, fs::Permissions::from_mode(0o755));

    // Copy icon
    let icon = resources_dir.join("AppIcon.icns");
    if icon.exists() {
        if let Err(e) = fs::copy(&icon, res_dir.join("AppIcon.icns")) {
            eprintln!("error: cannot copy icon: {}", e);
            return 1;
        }
        println!("    \u{2713} Icon copied");
    }

    // Copy the chat view's resources
    let exe_parent = exe_path.parent().unwrap_or(Path::new("."));
    let ui_dir = exe_parent.join(UI_RESOURCES);
    let has_mermaid = ui_dir.join("mermaid.min.js").exists()
        || ui_dir.join("Contents/Resources/mermaid.min.js").exists();
    if !has_mermaid {
        eprintln!("error: mermaid.min.js not found in {}.", ui_dir.display());
        eprintln!(
            "       Keep {} beside the executable: SwiftPM writes both to the same folder.",
            UI_RESOURCES
        );
        return 1;
    }
    if let Err(e) = copy_dir_recursive(&ui_dir, &res_dir.join(UI_RESOURCES)) {
        eprintln!("error: cannot copy UI resources: {}", e);
        return 1;
    }
    println!("    \u{2713} Chat resources copied");

    // Copy the bundled Rust bot helper beside the main executable into
    // Contents/Helpers (`bot-engine`, or a thin copy per architecture).
    let bot_copies = match copy_helper(exe_parent, &helpers_dir, BOT_NAME) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("error: {}", e);
            return 1;
        }
    };

    // Copy the bundled Node executable the same way (`node`, or a thin copy per
    // architecture).
    let node_copies = match copy_helper(exe_parent, &helpers_dir, NODE_NAME) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("error: {}", e);
            return 1;
        }
    };

    // Copy bundled Claude helper JS beside the main executable into Contents/Resources/claude-helper/
    let helper_src = exe_parent.join(HELPER_DIR_NAME).join(HELPER_FILE_NAME);
    if !helper_src.is_file() {
        eprintln!(
            "error: {} not found at {}.",
            HELPER_FILE_NAME,
            helper_src.display()
        );
        eprintln!(
            "       Keep {}/{} beside the executable before bundling.",
            HELPER_DIR_NAME, HELPER_FILE_NAME
        );
        return 1;
    }
    let helper_dest_dir = res_dir.join(HELPER_DIR_NAME);
    if let Err(e) = fs::create_dir_all(&helper_dest_dir) {
        eprintln!("error: cannot create {}: {}", helper_dest_dir.display(), e);
        return 1;
    }
    let helper_dest = helper_dest_dir.join(HELPER_FILE_NAME);
    if let Err(e) = fs::copy(&helper_src, &helper_dest) {
        eprintln!("error: cannot copy {}: {}", HELPER_FILE_NAME, e);
        return 1;
    }
    println!(
        "    \u{2713} {}/{} copied",
        HELPER_DIR_NAME, HELPER_FILE_NAME
    );

    let node_entitlements = resources_dir.join(NODE_ENTITLEMENTS_NAME);
    if !node_entitlements.is_file() {
        eprintln!(
            "error: {} not found at {}.",
            NODE_ENTITLEMENTS_NAME,
            node_entitlements.display()
        );
        return 1;
    }

    // Generate Info.plist
    let apple_events_usage = "\n    <key>NSAppleEventsUsageDescription</key>\n    <string>Vitruvian Code launches AI coding tools (such as Claude and Gemini) that may run AppleScript to automate other Mac apps when a task asks for it.</string>";
    let plist = format!(
        r#"<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>{exe}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>{bundle_id}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>{display_name}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>{ver}</string>
    <key>CFBundleVersion</key>
    <string>{ver}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>{apple_events_usage}
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
</dict>
</plist>
"#,
        exe = EXECUTABLE_NAME,
        bundle_id = BUNDLE_ID,
        display_name = DISPLAY_NAME,
        ver = version,
        apple_events_usage = apple_events_usage,
    );
    if let Err(e) = fs::write(app_bundle.join("Contents/Info.plist"), &plist) {
        eprintln!("error: cannot write Info.plist: {}", e);
        return 1;
    }
    println!("    \u{2713} Info.plist generated");

    // Create PkgInfo (no trailing newline, matching echo -n)
    if let Err(e) = fs::write(app_bundle.join("Contents/PkgInfo"), b"APPL????") {
        eprintln!("error: cannot write PkgInfo: {}", e);
        return 1;
    }

    // Ad-hoc sign the nested helpers first (inside-out), then the app bundle
    // without `--deep` so `node`'s JIT entitlements are preserved.
    println!("==> Signing {} with ad-hoc signature", app_bundle.display());
    for bot in &bot_copies {
        if let Err(e) = codesign_adhoc(bot, BOT_SIGNING_ID, None, "helper") {
            eprintln!("error: {}", e);
            return 1;
        }
    }
    for node in &node_copies {
        if let Err(e) = codesign_adhoc(node, NODE_SIGNING_ID, Some(&node_entitlements), "node") {
            eprintln!("error: {}", e);
            return 1;
        }
    }
    let status = Command::new("codesign")
        .args(["--force", "--sign", "-"])
        .arg(&app_bundle)
        .status();
    match status {
        Ok(s) if s.success() => {}
        Ok(s) => {
            eprintln!("error: codesign exited {}", s.code().unwrap_or(-1));
            return 1;
        }
        Err(e) => {
            eprintln!("error: cannot run codesign: {}", e);
            return 1;
        }
    }

    println!("==> {} ready", app_bundle.display());
    0
}
