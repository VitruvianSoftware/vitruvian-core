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
const HELPERS_REL_DIR: &str = "Contents/Helpers";
const BOT_NAME: &str = "bot-engine";
const NODE_NAME: &str = "node";
/// The architectures a universal app is built for.
pub const ARCHS: [&str; 2] = ["arm64", "x86_64"];
/// `ARCHS` the way the checks here take them: sorted, each followed by a space.
pub const UNIVERSAL_ARCHS: &str = "arm64 x86_64 ";
const HELPER_REL_PATH: &str = "Contents/Resources/claude-helper/claude-helper.mjs";
const TOOL_BIN_REL_PATH: &str = "bin/tool";
const TOOL_NODE_REL_PATH: &str = "bin/node";
const TOOL_HELPER_REL_PATH: &str = "bin/claude-helper/claude-helper.mjs";
const REQUIRED_NODE_ENTITLEMENTS: &[&str] = &[
    "com.apple.security.cs.allow-jit",
    "com.apple.security.cs.allow-unsigned-executable-memory",
];

pub fn entitlements_plist_has_true(plist: &str, key: &str) -> bool {
    let needle = format!("<key>{}</key>", key);
    let Some(pos) = plist.find(&needle) else {
        return false;
    };
    let rest = plist[pos + needle.len()..].trim_start();
    rest.starts_with("<true/>")
}

/// Every `<key>` in an entitlements plist that isn't one Node needs. Node is
/// signed with `node.entitlements` alone, so anything else (for example
/// `disable-library-validation`) means it was signed with the wrong file.
pub fn unexpected_entitlement_keys(plist: &str) -> Vec<String> {
    plist
        .split("<key>")
        .skip(1)
        .filter_map(|rest| rest.split_once("</key>").map(|(k, _)| k.trim().to_string()))
        .filter(|k| !REQUIRED_NODE_ENTITLEMENTS.contains(&k.as_str()))
        .collect()
}

pub fn check_node_entitlements(node_exe: &Path) -> Result<(), String> {
    let out = Command::new("codesign")
        .args(["-d", "--entitlements", "-", "--xml"])
        .arg(node_exe)
        .output()
        .map_err(|e| {
            format!(
                "cannot inspect entitlements on {}: {}",
                node_exe.display(),
                e
            )
        })?;
    if !out.status.success() {
        return Err(format!(
            "codesign -d --entitlements failed on {}: {}",
            node_exe.display(),
            String::from_utf8_lossy(&out.stderr).trim()
        ));
    }
    let xml = format!(
        "{}{}",
        String::from_utf8_lossy(&out.stdout),
        String::from_utf8_lossy(&out.stderr)
    );
    for key in REQUIRED_NODE_ENTITLEMENTS {
        if !entitlements_plist_has_true(&xml, key) {
            return Err(format!(
                "{} is missing entitlement {} (<true/>)",
                node_exe.display(),
                key
            ));
        }
    }
    let extra = unexpected_entitlement_keys(&xml);
    if !extra.is_empty() {
        return Err(format!(
            "{} carries entitlements beyond the JIT pair: {}",
            node_exe.display(),
            extra.join(", ")
        ));
    }
    Ok(())
}

/// Checks that `binary` (called `label` in messages) is an executable Mach-O
/// built for exactly `want_archs` ("arm64 x86_64 ": sorted, each followed by
/// a space).
pub fn check_macho_archs(binary: &Path, label: &str, want_archs: &str) -> Result<(), String> {
    if !binary.is_file() {
        return Err(format!("no executable at {}", label));
    }
    let meta = fs::metadata(binary).map_err(|e| format!("cannot read {}: {}", label, e))?;
    if meta.permissions().mode() & 0o111 == 0 {
        return Err(format!("{} is not executable", label));
    }
    let got = lipo_archs(binary, label)?;
    let got_str = format!("{} ", got.join(" "));
    if got_str != want_archs {
        return Err(format!(
            "{} is built for '{}', expected '{}'",
            label,
            got_str.trim(),
            want_archs.trim()
        ));
    }
    println!("    \u{2713} {}, built for {}", label, got_str.trim());
    Ok(())
}

/// The bundled Node at `node_exe` (called `label` in messages): present,
/// executable, built for exactly `want_archs` ("arm64 x86_64 ": sorted, each
/// followed by a space), its signature valid and carrying the JIT entitlements.
pub fn check_node_binary(node_exe: &Path, label: &str, want_archs: &str) -> Result<(), String> {
    check_macho_archs(node_exe, label, want_archs)?;
    let verified = Command::new("codesign")
        .args(["--verify", "--strict"])
        .arg(node_exe)
        .status();
    if !matches!(verified, Ok(s) if s.success()) {
        return Err(format!("{} signature does not verify", label));
    }
    check_node_entitlements(node_exe)
}

/// True when `want_archs` ("arm64 x86_64 ": sorted, each followed by a space)
/// names both architectures: a universal app.
pub fn is_universal(want_archs: &str) -> bool {
    ARCHS
        .iter()
        .all(|a| want_archs.split_whitespace().any(|w| w == *a))
}

/// `Contents/Helpers/<name>-<arch>`: where the universal app holds one thin copy
/// of a helper.
pub fn per_arch_helper_rel_path(name: &str, arch: &str) -> String {
    format!("{}/{}-{}", HELPERS_REL_DIR, name, arch)
}

/// The architectures of the Mach-O at `binary`, sorted.
pub fn lipo_archs(binary: &Path, label: &str) -> Result<Vec<String>, String> {
    let out = Command::new("lipo")
        .args(["-archs"])
        .arg(binary)
        .output()
        .map_err(|e| format!("cannot run lipo on {}: {}", label, e))?;
    if !out.status.success() {
        return Err(format!(
            "lipo -archs on {} failed: {}",
            label,
            String::from_utf8_lossy(&out.stderr).trim()
        ));
    }
    let mut got: Vec<String> = String::from_utf8_lossy(&out.stdout)
        .split_whitespace()
        .map(|s| s.to_string())
        .collect();
    got.sort();
    got.dedup();
    Ok(got)
}

/// The bundled bot engine at `bot_exe` (called `label` in messages): present,
/// executable, built for exactly `want_archs` and signed.
pub fn check_bot_binary(bot_exe: &Path, label: &str, want_archs: &str) -> Result<(), String> {
    check_macho_archs(bot_exe, label, want_archs)?;
    let verified = Command::new("codesign")
        .args(["--verify", "--strict"])
        .arg(bot_exe)
        .status();
    if !matches!(verified, Ok(s) if s.success()) {
        return Err(format!("{} signature does not verify", label));
    }
    Ok(())
}

/// A helper the app holds: the architecture it is for, its path relative to the
/// app (for messages), and where it is.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HelperFile {
    pub arch: String,
    pub rel: String,
    pub path: PathBuf,
}

/// One of the two Mach-O helpers in `Contents/Helpers`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Helper {
    Bot,
    Node,
}

impl Helper {
    pub fn name(self) -> &'static str {
        match self {
            Helper::Bot => BOT_NAME,
            Helper::Node => NODE_NAME,
        }
    }

    fn check(self, path: &Path, rel: &str, want_archs: &str) -> Result<(), String> {
        match self {
            Helper::Bot => check_bot_binary(path, rel, want_archs),
            Helper::Node => {
                check_node_binary(path, rel, want_archs)?;
                println!("    \u{2713} {} signed with JIT entitlements", rel);
                Ok(())
            }
        }
    }
}

/// What `Contents/Helpers` of the app at `app` must hold of `helper`, for an
/// executable built for `want_archs` ("arm64 x86_64 ": sorted, each followed by
/// a space). Returns the files found.
///
/// - A single-architecture app holds `<name>`, thin.
/// - A universal app holds `<name>-arm64` and `<name>-x86_64`, each thin Mach-O
///   for the architecture in its name, and no plain `<name>`: XProtect
///   (`syspolicy_check`) refuses a universal app that holds a fat helper, with
///   "Internal Xprotect Error".
pub fn check_helper_set(
    app: &Path,
    want_archs: &str,
    helper: Helper,
) -> Result<Vec<HelperFile>, String> {
    let name = helper.name();
    let mut found = Vec::new();
    if !is_universal(want_archs) {
        let rel = format!("{}/{}", HELPERS_REL_DIR, name);
        let path = app.join(&rel);
        helper.check(&path, &rel, want_archs)?;
        found.push(HelperFile {
            arch: want_archs.trim().to_string(),
            rel,
            path,
        });
        return Ok(found);
    }
    let plain = format!("{}/{}", HELPERS_REL_DIR, name);
    if app.join(&plain).exists() {
        return Err(format!(
            "{} is in the universal app: ship a thin {}-<arch> for each architecture instead (XProtect refuses a universal app with a fat helper)",
            plain, name
        ));
    }
    for arch in ARCHS {
        let rel = per_arch_helper_rel_path(name, arch);
        let path = app.join(&rel);
        helper.check(&path, &rel, &format!("{} ", arch))?;
        found.push(HelperFile {
            arch: arch.to_string(),
            rel,
            path,
        });
    }
    Ok(found)
}

/// What `Contents/Helpers` of the app at `app` must hold: both helpers (see
/// `check_helper_set`) and, in a universal app, nothing fat.
pub fn check_helpers(app: &Path, want_archs: &str) -> Result<(), String> {
    for helper in [Helper::Bot, Helper::Node] {
        check_helper_set(app, want_archs, helper)?;
    }
    if !is_universal(want_archs) {
        return Ok(());
    }
    // No other Mach-O in Contents/Helpers may be fat either.
    let entries = fs::read_dir(app.join(HELPERS_REL_DIR))
        .map_err(|e| format!("cannot read {}: {}", HELPERS_REL_DIR, e))?;
    for entry in entries {
        let entry = entry.map_err(|e| format!("cannot read {}: {}", HELPERS_REL_DIR, e))?;
        if !entry.path().is_file() {
            continue;
        }
        let rel = format!(
            "{}/{}",
            HELPERS_REL_DIR,
            entry.file_name().to_string_lossy()
        );
        let archs = lipo_archs(&entry.path(), &rel).unwrap_or_default();
        if archs.len() > 1 {
            return Err(format!(
                "{} is a fat helper ({}): the universal app holds only thin helpers",
                rel,
                archs.join(" ")
            ));
        }
    }
    println!(
        "    \u{2713} {} holds a thin bot-engine and node per architecture and no fat helper",
        HELPERS_REL_DIR
    );
    Ok(())
}

/// Whether this Mac can run a Mach-O built for `arch`: its own architecture
/// always, `x86_64` on Apple silicon when Rosetta is installed.
pub fn can_run_arch(arch: &str) -> bool {
    let host = if cfg!(target_arch = "aarch64") {
        "arm64"
    } else {
        "x86_64"
    };
    if arch == host {
        return true;
    }
    arch == "x86_64"
        && Command::new("/usr/bin/arch")
            .args(["-x86_64", "/usr/bin/true"])
            .stderr(std::process::Stdio::null())
            .status()
            .map(|s| s.success())
            .unwrap_or(false)
}

/// The Claude helper's bundle at `helper`: a file with something in it.
pub fn check_helper_file(helper: &Path, label: &str) -> Result<(), String> {
    match fs::metadata(helper) {
        Ok(m) if m.is_file() && m.len() > 0 => Ok(()),
        _ => Err(format!("{} is missing or empty", label)),
    }
}

/// What the tool's folder (`vitruvian-tool.json`, `bin/tool`, `bin/node`,
/// `bin/claude-helper/claude-helper.mjs`) must hold before it is zipped.
pub fn check_tool_folder(folder: &str, archs: &[&String]) -> i32 {
    let root = Path::new(folder);
    let mut sorted: Vec<&str> = archs.iter().map(|s| s.as_str()).collect();
    sorted.sort();
    let want_archs = format!("{} ", sorted.join(" "));
    for rel in ["vitruvian-tool.json", "bin/mermaid.min.js"] {
        if !root.join(rel).is_file() {
            return fail(folder, &format!("no file at {}", rel));
        }
    }
    if let Err(msg) = check_macho_archs(
        &root.join(TOOL_BIN_REL_PATH),
        TOOL_BIN_REL_PATH,
        &want_archs,
    ) {
        return fail(folder, &msg);
    }
    if let Err(msg) = check_node_binary(
        &root.join(TOOL_NODE_REL_PATH),
        TOOL_NODE_REL_PATH,
        &want_archs,
    ) {
        return fail(folder, &msg);
    }
    println!(
        "    \u{2713} {} signed with JIT entitlements",
        TOOL_NODE_REL_PATH
    );
    if let Err(msg) = check_helper_file(&root.join(TOOL_HELPER_REL_PATH), TOOL_HELPER_REL_PATH) {
        return fail(folder, &msg);
    }
    println!("    \u{2713} {} present", TOOL_HELPER_REL_PATH);
    0
}

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
            "Usage: check-packaged-app [--notarized] <app folder, e.g. Vitruvian Code.app> <architecture>...\n       check-packaged-app --tool-folder <tool folder> <architecture>..."
        );
        return 2;
    }

    // check-packaged-app --tool-folder <folder> <architecture>...
    if rest[0] == "--tool-folder" {
        if rest.len() < 3 {
            eprintln!("Usage: check-packaged-app --tool-folder <tool folder> <architecture>...");
            return 2;
        }
        let archs: Vec<&String> = rest[2..].iter().collect();
        return check_tool_folder(&rest[1], &archs);
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
            "Usage: check-packaged-app [--notarized] <app folder, e.g. Vitruvian Code.app> <architecture>...\n       check-packaged-app --tool-folder <tool folder> <architecture>..."
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

    // Bundled bot and Node helpers (Mach-O executables in Contents/Helpers):
    // one thin file per architecture in the universal app, one in the others.
    if let Err(msg) = check_helpers(Path::new(app), want_archs) {
        return fail(app, &msg);
    }
    // The Claude helper's JavaScript.
    if let Err(msg) = check_helper_file(&Path::new(app).join(HELPER_REL_PATH), HELPER_REL_PATH) {
        return fail(app, &msg);
    }
    println!("    \u{2713} {} present", HELPER_REL_PATH);

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
