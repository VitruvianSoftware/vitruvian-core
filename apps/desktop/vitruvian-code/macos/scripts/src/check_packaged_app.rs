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

const SCRIPT_NAME: &str = "mermaid.min.js";
const LICENCE_NAME: &str = "mermaid-LICENSE.txt";
const UI_RESOURCES: &str = "VitruvianCode_VitruvianCodeUI.bundle";

fn fail(app: &str, msg: &str) -> i32 {
    eprintln!("error: {}", msg);
    let p = Path::new(app);
    if p.is_dir() {
        eprintln!("       {} holds:", app);
        if let Ok(entries) = collect_files(p) {
            for e in entries {
                eprintln!("         {}", e);
            }
        }
    }
    1
}

fn collect_files(dir: &Path) -> std::io::Result<Vec<String>> {
    let mut out = Vec::new();
    let base = dir.to_path_buf();
    collect_files_inner(&base, &base, &mut out)?;
    out.sort();
    Ok(out)
}

fn collect_files_inner(base: &Path, dir: &Path, out: &mut Vec<String>) -> std::io::Result<()> {
    for entry in fs::read_dir(dir)? {
        let entry = entry?;
        let ft = entry.file_type()?;
        if ft.is_dir() {
            collect_files_inner(base, &entry.path(), out)?;
        } else {
            let rel = entry
                .path()
                .strip_prefix(base)
                .unwrap_or(&entry.path())
                .display()
                .to_string();
            out.push(format!("./{}", rel));
        }
    }
    Ok(())
}

pub fn extract_sha256_from_notices(content: &str) -> Option<String> {
    for line in content.lines() {
        // Match: | SHA-256 of the file | `<64 hex chars>` |
        if let Some(start) = line.find("| SHA-256 of the file | `") {
            let after = &line[start + 25..]; // skip "| SHA-256 of the file | `"
            if let Some(end) = after.find("` |") {
                let candidate = &after[..end];
                if candidate.len() == 64 && candidate.chars().all(|c| c.is_ascii_hexdigit()) {
                    return Some(candidate.to_string());
                }
            }
        }
    }
    None
}

pub fn find_mermaid(app: &str, name: &str) -> Option<PathBuf> {
    let app_path = Path::new(app);
    let roots = [
        app_path.join("Contents/Resources"),
        app_path.join("Contents/MacOS"),
    ];
    for root in &roots {
        for dir in [
            root.clone(),
            root.join(UI_RESOURCES),
            root.join(UI_RESOURCES).join("Contents/Resources"),
        ] {
            if dir.join(name).is_file() {
                return Some(dir);
            }
        }
    }
    None
}

pub fn run(args: &[String]) -> i32 {
    let rest = if args.len() > 1 { &args[1..] } else { &[] };
    if rest.is_empty() {
        eprintln!(
            "Usage: check-packaged-app [--notarized] <app folder, e.g. Vitruvian Code.app> <architecture>..."
        );
        return 2;
    }

    let mut require_notarized = std::env::var("CHECK_NOTARIZED")
        .map(|v| v == "1")
        .unwrap_or(false);
    let mut positional: Vec<&String> = Vec::new();
    for arg in rest {
        if arg == "--notarized" {
            require_notarized = true;
        } else {
            positional.push(arg);
        }
    }
    if positional.is_empty() {
        eprintln!(
            "Usage: check-packaged-app [--notarized] <app folder, e.g. Vitruvian Code.app> <architecture>..."
        );
        return 2;
    }

    let app = positional[0];
    let archs = &positional[1..];
    if archs.is_empty() {
        eprintln!("error: name the architectures the executable must have");
        return 2;
    }

    let mut sorted_archs: Vec<&str> = archs.iter().map(|s| s.as_str()).collect();
    sorted_archs.sort();
    let want_archs = format!("{} ", sorted_archs.join(" "));

    // Resolve THIRD_PARTY_NOTICES.md relative to the binary's location,
    // mirroring the shell script's SCRIPT_DIR/../../THIRD_PARTY_NOTICES.md,
    // or from standard workspace/mirror paths when compiled to $RUNNER_TEMP.
    let script_dir = match std::env::current_exe() {
        Ok(p) => p.parent().unwrap_or(Path::new(".")).to_path_buf(),
        Err(_) => PathBuf::from("."),
    };
    let notices_candidates = [
        script_dir.join("../../THIRD_PARTY_NOTICES.md"),
        script_dir.join("../THIRD_PARTY_NOTICES.md"),
        PathBuf::from("apps/desktop/vitruvian-code/THIRD_PARTY_NOTICES.md"),
        PathBuf::from("THIRD_PARTY_NOTICES.md"),
        PathBuf::from("../THIRD_PARTY_NOTICES.md"),
    ];
    let notices_path = notices_candidates
        .into_iter()
        .find(|p| p.is_file())
        .unwrap_or_else(|| script_dir.join("../../THIRD_PARTY_NOTICES.md"));

    let notices_content = match fs::read_to_string(&notices_path) {
        Ok(c) => c,
        Err(e) => {
            return fail(
                app,
                &format!("cannot read {}: {}", notices_path.display(), e),
            );
        }
    };

    let want_sha = match extract_sha256_from_notices(&notices_content) {
        Some(s) => s,
        None => {
            return fail(
                app,
                &format!(
                    "no 'SHA-256 of the file' row with one hash in {}",
                    notices_path.display()
                ),
            );
        }
    };

    println!("==> Checking {}", app);

    if !Path::new(app).is_dir() {
        return fail(app, &format!("no app at {}", app));
    }

    // Find mermaid.min.js
    let found = match find_mermaid(app, SCRIPT_NAME) {
        Some(d) => d,
        None => {
            return fail(
                app,
                &format!("{} is in none of the places the app looks", SCRIPT_NAME),
            );
        }
    };

    let rel = found
        .strip_prefix(app)
        .map(|p| p.display().to_string())
        .unwrap_or_else(|_| found.display().to_string());
    println!("    \u{2713} {} found in {}", SCRIPT_NAME, rel);

    // SHA-256 check using pure-Rust implementation
    let got_sha = match crate::sha256_hex_file(&found.join(SCRIPT_NAME)) {
        Ok(h) => h,
        Err(e) => {
            return fail(
                app,
                &format!("cannot hash {}: {}", found.join(SCRIPT_NAME).display(), e),
            );
        }
    };

    if got_sha != want_sha {
        return fail(
            app,
            &format!(
                "{} is not the recorded file: SHA-256 {}, THIRD_PARTY_NOTICES.md says {}",
                SCRIPT_NAME, got_sha, want_sha
            ),
        );
    }
    println!("    \u{2713} it is the recorded file (SHA-256 {})", got_sha);

    // Licence beside it
    let licence_path = found.join(LICENCE_NAME);
    if !licence_path.is_file()
        || fs::metadata(&licence_path)
            .map(|m| m.len() == 0)
            .unwrap_or(true)
    {
        return fail(
            app,
            &format!(
                "{} is missing or empty beside {}",
                LICENCE_NAME, SCRIPT_NAME
            ),
        );
    }
    println!("    \u{2713} {} is beside it", LICENCE_NAME);

    check_program_and_signature(app, "VitruvianCode", &want_archs, require_notarized)
}

/// The program's presence, its processors and the bundle's signature: what is
/// checked of both apps.
fn check_program_and_signature(
    app: &str,
    program: &str,
    want_archs: &str,
    require_notarized: bool,
) -> i32 {
    // Executable check
    let exe = format!("{}/Contents/MacOS/{}", app, program);
    if !Path::new(&exe).is_file() {
        return fail(app, &format!("no executable at Contents/MacOS/{}", program));
    }
    let exe_meta = fs::metadata(&exe).unwrap();
    if exe_meta.permissions().mode() & 0o111 == 0 {
        return fail(
            app,
            &format!("Contents/MacOS/{} is not executable", program),
        );
    }

    // Architecture check
    let lipo_out = Command::new("lipo").args(["-archs", &exe]).output();
    match lipo_out {
        Ok(o) if o.status.success() => {
            let raw = String::from_utf8_lossy(&o.stdout);
            let mut got: Vec<&str> = raw.split_whitespace().filter(|s| !s.is_empty()).collect();
            got.sort();
            let got_str = format!("{} ", got.join(" "));
            if got_str != want_archs {
                return fail(
                    app,
                    &format!(
                        "the executable is built for '{}', expected '{}'",
                        got_str.trim(),
                        want_archs.trim()
                    ),
                );
            }
            println!("    \u{2713} executable, built for {}", got_str.trim());
        }
        Ok(o) => {
            return fail(
                app,
                &format!("lipo -archs failed: {}", String::from_utf8_lossy(&o.stderr)),
            );
        }
        Err(e) => {
            return fail(app, &format!("cannot run lipo: {}", e));
        }
    }

    // Bundled bot helper check
    let bot_rel = "Contents/Helpers/bot-engine";
    let bot_exe = format!("{}/{}", app, bot_rel);
    if !Path::new(&bot_exe).is_file() {
        return fail(app, &format!("no executable at {}", bot_rel));
    }
    let bot_meta = fs::metadata(&bot_exe).unwrap();
    if bot_meta.permissions().mode() & 0o111 == 0 {
        return fail(app, &format!("{} is not executable", bot_rel));
    }
    let bot_lipo = Command::new("lipo").args(["-archs", &bot_exe]).output();
    match bot_lipo {
        Ok(o) if o.status.success() => {
            let raw = String::from_utf8_lossy(&o.stdout);
            let mut got: Vec<&str> = raw.split_whitespace().filter(|s| !s.is_empty()).collect();
            got.sort();
            let got_str = format!("{} ", got.join(" "));
            if got_str != want_archs {
                return fail(
                    app,
                    &format!(
                        "{} is built for '{}', expected '{}'",
                        bot_rel,
                        got_str.trim(),
                        want_archs.trim()
                    ),
                );
            }
            println!("    \u{2713} {}, built for {}", bot_rel, got_str.trim());
        }
        Ok(o) => {
            return fail(
                app,
                &format!(
                    "lipo -archs on {} failed: {}",
                    bot_rel,
                    String::from_utf8_lossy(&o.stderr)
                ),
            );
        }
        Err(e) => {
            return fail(app, &format!("cannot run lipo on {}: {}", bot_rel, e));
        }
    }

    // Signature check
    let cs = Command::new("codesign")
        .args(["--verify", "--deep", "--strict", app])
        .status();
    match cs {
        Ok(s) if s.success() => {
            println!("    \u{2713} signature verifies");
        }
        _ => {
            return fail(app, "the signature does not verify");
        }
    }

    if require_notarized {
        let spctl = Command::new("spctl")
            .args(["-a", "-vv", "-t", "exec", app])
            .status();
        match spctl {
            Ok(s) if s.success() => {
                println!("    \u{2713} Gatekeeper (spctl) accepts executable bundle");
            }
            _ => {
                return fail(app, "Gatekeeper (spctl -a -t exec) rejected the bundle");
            }
        }
    }

    println!("==> {} is complete", app);
    0
}
