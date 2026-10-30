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

const APP_NAME: &str = "NexusAgent";
const UI_RESOURCES: &str = "NexusAgent_NexusAgentUI.bundle";

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
    if rest.len() < 3 {
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
        PathBuf::from("apps/desktop/nexus-agent/macos/Resources"),
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
    let res_dir = app_bundle.join("Contents/Resources");
    if let Err(e) = fs::create_dir_all(&macos_dir) {
        eprintln!("error: cannot create {}: {}", macos_dir.display(), e);
        return 1;
    }
    if let Err(e) = fs::create_dir_all(&res_dir) {
        eprintln!("error: cannot create {}: {}", res_dir.display(), e);
        return 1;
    }

    // Copy executable
    let dest_exe = macos_dir.join(APP_NAME);
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

    // Generate Info.plist
    let plist = format!(
        r#"<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>{app}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.vitruviansoftware.nexusagent</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>{app}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>{ver}</string>
    <key>CFBundleVersion</key>
    <string>{ver}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
</dict>
</plist>
"#,
        app = APP_NAME,
        ver = version,
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

    // Ad-hoc sign the bundle
    println!("==> Signing {} with ad-hoc signature", app_bundle.display());
    let status = Command::new("codesign")
        .args(["--force", "--deep", "--sign", "-"])
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
