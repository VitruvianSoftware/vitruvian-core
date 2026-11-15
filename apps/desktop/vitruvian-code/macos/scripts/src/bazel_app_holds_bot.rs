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

const BOT_REL_PATH: &str = "Contents/Helpers/bot-engine";
const MAIN_EXE_NAME: &str = "VitruvianCode";

fn lipo_archs(binary: &Path) -> Result<Vec<String>, String> {
    let out = Command::new("lipo")
        .args(["-archs", &binary.to_string_lossy()])
        .output()
        .map_err(|e| format!("cannot run lipo on {}: {}", binary.display(), e))?;
    if !out.status.success() {
        return Err(format!(
            "lipo -archs on {} failed: {}",
            binary.display(),
            String::from_utf8_lossy(&out.stderr).trim()
        ));
    }
    let mut archs: Vec<String> = String::from_utf8_lossy(&out.stdout)
        .split_whitespace()
        .filter(|s| !s.is_empty())
        .map(|s| s.to_string())
        .collect();
    archs.sort();
    archs.dedup();
    if archs.is_empty() {
        return Err(format!(
            "lipo -archs reported no architectures for {}",
            binary.display()
        ));
    }
    Ok(archs)
}

pub fn resolve_app_bundle(
    app_name: &str,
    paths: &[String],
    dest: &Path,
) -> Result<PathBuf, String> {
    let expected_app_dir = format!("{}.app", app_name);
    let mut archive: Option<String> = None;

    for path in paths {
        let p = Path::new(path);
        if p.is_dir() && p.file_name().and_then(|n| n.to_str()) == Some(expected_app_dir.as_str()) {
            return Ok(p.to_path_buf());
        }
        if path.ends_with(".zip") && p.is_file() {
            archive = Some(path.clone());
            break;
        }
        let zip_candidate = format!("{}.zip", path);
        if Path::new(&zip_candidate).is_file() {
            archive = Some(zip_candidate);
            break;
        }
    }

    let archive = archive.ok_or_else(|| {
        format!(
            "no {}.app or zip archive among the paths given: {}",
            app_name,
            paths.join(" ")
        )
    })?;

    let _ = fs::remove_dir_all(dest);
    fs::create_dir_all(dest)
        .map_err(|e| format!("cannot create unzip directory {}: {}", dest.display(), e))?;

    let status = Command::new("unzip")
        .args(["-q", &archive, "-d", &dest.to_string_lossy()])
        .status()
        .map_err(|e| format!("cannot run unzip on {}: {}", archive, e))?;
    if !status.success() {
        return Err(format!("unzip failed on {}", archive));
    }

    let candidate = dest.join(&expected_app_dir);
    if candidate.is_dir() {
        Ok(candidate)
    } else {
        Err(format!("{} did not unpack {}", archive, expected_app_dir))
    }
}

pub fn verify_unpacked_app(app: &Path, work_root: &Path) -> Result<(), String> {
    let main_exe = app.join("Contents/MacOS").join(MAIN_EXE_NAME);
    if !main_exe.is_file() {
        return Err(format!("missing main executable at {}", main_exe.display()));
    }

    let bot_exe = app.join(BOT_REL_PATH);
    if !bot_exe.is_file() {
        return Err(format!("missing {} inside {}", BOT_REL_PATH, app.display()));
    }
    let meta =
        fs::metadata(&bot_exe).map_err(|e| format!("cannot stat {}: {}", bot_exe.display(), e))?;
    if meta.permissions().mode() & 0o111 == 0 {
        return Err(format!("{} is not executable", BOT_REL_PATH));
    }

    let app_archs = lipo_archs(&main_exe)?;
    let bot_archs = lipo_archs(&bot_exe)?;
    let missing: Vec<&str> = app_archs
        .iter()
        .filter(|a| !bot_archs.contains(a))
        .map(|s| s.as_str())
        .collect();
    if !missing.is_empty() {
        return Err(format!(
            "{} lacks app architecture(s) {} (app: {}, bot: {})",
            BOT_REL_PATH,
            missing.join(" "),
            app_archs.join(" "),
            bot_archs.join(" ")
        ));
    }
    println!(
        "ok: {} covers app architectures [{}] (bot: {})",
        BOT_REL_PATH,
        app_archs.join(" "),
        bot_archs.join(" ")
    );

    let cs = Command::new("codesign")
        .args(["--verify", "--deep", "--strict"])
        .arg(app)
        .output()
        .map_err(|e| format!("cannot run codesign --verify: {}", e))?;
    if !cs.status.success() {
        return Err(format!(
            "codesign --verify --deep --strict failed on {}: {}",
            app.display(),
            String::from_utf8_lossy(&cs.stderr).trim()
        ));
    }
    println!("ok: codesign --verify --deep --strict passed");

    // Run the bundled bot-engine in an isolated temp workspace with a fake token
    // so it loads .env from CWD and validates without reading ~/.config or calling Telegram.
    let dry_root = work_root.join("dry_run");
    let _ = fs::remove_dir_all(&dry_root);
    let dry_home = dry_root.join("home");
    let dry_bot_dir = dry_root.join("bot");
    fs::create_dir_all(&dry_home)
        .map_err(|e| format!("cannot create isolated HOME {}: {}", dry_home.display(), e))?;
    fs::create_dir_all(&dry_bot_dir).map_err(|e| {
        format!(
            "cannot create isolated bot dir {}: {}",
            dry_bot_dir.display(),
            e
        )
    })?;
    fs::write(dry_bot_dir.join(".env"), "TELEGRAM_BOT_TOKEN=0:dry-run\n")
        .map_err(|e| format!("cannot write isolated .env: {}", e))?;

    let dry_out = Command::new(&bot_exe)
        .arg("--dry-run")
        .current_dir(&dry_bot_dir)
        .env_clear()
        .env("HOME", &dry_home)
        .env("PATH", "/usr/bin:/bin")
        .output()
        .map_err(|e| format!("cannot run {} --dry-run: {}", bot_exe.display(), e))?;
    let combined = format!(
        "{}{}",
        String::from_utf8_lossy(&dry_out.stdout),
        String::from_utf8_lossy(&dry_out.stderr)
    );
    if !dry_out.status.success() || !combined.contains("Bot is running") {
        return Err(format!(
            "{} --dry-run failed (status {:?}): {}",
            BOT_REL_PATH,
            dry_out.status.code(),
            combined.trim()
        ));
    }
    println!(
        "ok: {} --dry-run exited 0 in isolated environment",
        BOT_REL_PATH
    );

    Ok(())
}

pub fn run(args: &[String]) -> i32 {
    let rest = if args.len() > 1 { &args[1..] } else { &[] };
    if rest.len() < 2 {
        eprintln!("Usage: bazel-app-holds-bot <app name> <archive-or-app-path>...");
        return 2;
    }

    let app_name = &rest[0];
    let paths = &rest[1..];
    let tmp_root = PathBuf::from(std::env::var("TEST_TMPDIR").unwrap_or_else(|_| "/tmp".into()));
    let unzip_dir = tmp_root.join("app_holds_bot_unzip");

    let app = match resolve_app_bundle(app_name, paths, &unzip_dir) {
        Ok(a) => a,
        Err(msg) => {
            eprintln!("FAIL: {}", msg);
            return 2;
        }
    };

    if let Err(err) = verify_unpacked_app(&app, &tmp_root) {
        eprintln!("FAIL: {}", err);
        return 1;
    }

    0
}
