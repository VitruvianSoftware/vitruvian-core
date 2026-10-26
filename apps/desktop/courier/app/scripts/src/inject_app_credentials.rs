// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

use std::env;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::Command;

const STORE_RELATIVE: &str = "tools/sync-env-secrets/secrets/courier-release";
const ID_NAME: &str = "COURIER_TELEGRAM_API_ID";
const HASH_NAME: &str = "COURIER_TELEGRAM_API_HASH";
const ENGINE_ID: &str = "com.vitruviansoftware.courier.engine";

fn strip_whitespace(s: &str) -> String {
    s.chars().filter(|c| !c.is_ascii_whitespace()).collect()
}

pub fn validate_api_id(raw: &str) -> Result<String, String> {
    let s = strip_whitespace(raw);
    if s.is_empty() {
        return Err("api_id is empty".into());
    }
    if !s.bytes().all(|b| b.is_ascii_digit()) {
        return Err("api_id is not a whole number".into());
    }
    let stripped = s.trim_start_matches('0');
    if stripped.is_empty() {
        return Err("api_id must be from 1 to 2147483647".into());
    }
    if stripped.len() > 10 {
        return Err("api_id must be from 1 to 2147483647".into());
    }
    let val: u64 = stripped.parse().unwrap_or(u64::MAX);
    if val > 2_147_483_647 {
        return Err("api_id must be from 1 to 2147483647".into());
    }
    Ok(stripped.to_string())
}

pub fn validate_api_hash(raw: &str) -> Result<String, String> {
    let s = strip_whitespace(raw);
    if s.len() != 32 {
        return Err("api_hash must be 32 hexadecimal characters".into());
    }
    if !s.bytes().all(|b| b.is_ascii_hexdigit()) {
        return Err("api_hash must be 32 hexadecimal characters".into());
    }
    Ok(s)
}

pub fn generate_plist(api_id: &str, api_hash: &str) -> String {
    format!(
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n\
         <!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n\
         <plist version=\"1.0\">\n\
         <dict>\n\
         \t<key>api_id</key>\n\
         \t<integer>{}</integer>\n\
         \t<key>api_hash</key>\n\
         \t<string>{}</string>\n\
         </dict>\n\
         </plist>\n",
        api_id, api_hash
    )
}

pub fn store_dirs(script_dir: &Path) -> Vec<PathBuf> {
    let mut dirs = Vec::new();

    if let Ok(secrets_dir) = env::var("COURIER_SECRETS_DIR") {
        if !secrets_dir.is_empty() {
            dirs.push(PathBuf::from(secrets_dir));
            return dirs;
        }
    }

    let base: PathBuf;
    if let Ok(bwd) = env::var("BUILD_WORKSPACE_DIRECTORY") {
        if !bwd.is_empty() {
            base = PathBuf::from(&bwd);
            dirs.push(base.join(STORE_RELATIVE));
        } else {
            base = script_dir.to_path_buf();
        }
    } else {
        base = script_dir.to_path_buf();
    }

    if let Ok(out) = Command::new("git")
        .args([
            "-C",
            &base.to_string_lossy(),
            "rev-parse",
            "--show-toplevel",
        ])
        .output()
    {
        if out.status.success() {
            let top = String::from_utf8_lossy(&out.stdout).trim().to_string();
            if !top.is_empty() {
                dirs.push(PathBuf::from(&top).join(STORE_RELATIVE));
            }
        }
    }

    if let Ok(out) = Command::new("git")
        .args([
            "-C",
            &base.to_string_lossy(),
            "rev-parse",
            "--path-format=absolute",
            "--git-common-dir",
        ])
        .output()
    {
        if out.status.success() {
            let common = String::from_utf8_lossy(&out.stdout).trim().to_string();
            if !common.is_empty() {
                if let Some(parent) = Path::new(&common).parent() {
                    dirs.push(parent.join(STORE_RELATIVE));
                }
            }
        }
    }

    dirs
}

fn read_store_file(dir: &Path, name: &str) -> Option<String> {
    let file = dir.join(name);
    let content = fs::read_to_string(&file).ok()?;
    let value = strip_whitespace(&content);
    if value.is_empty() {
        None
    } else {
        Some(value)
    }
}

fn resolve_default_entitlements() -> PathBuf {
    if let Ok(exe) = env::current_exe() {
        if let Some(exe_dir) = exe.parent() {
            let candidate = exe_dir.join("../Resources/Courier.entitlements");
            if candidate.exists() {
                return candidate;
            }
            let candidate = exe_dir.join("Resources/Courier.entitlements");
            if candidate.exists() {
                return candidate;
            }
        }
    }
    // Fallback: relative to scripts/../Resources from current_exe
    if let Ok(exe) = env::current_exe() {
        if let Some(exe_dir) = exe.parent() {
            // Under Bazel runfiles the binary sits at e.g.
            // apps/desktop/courier/app/inject-app-credentials
            // and Resources is at apps/desktop/courier/app/Resources/
            let candidate = exe_dir.join("../Resources/Courier.entitlements");
            if let Ok(canon) = candidate.canonicalize() {
                return canon;
            }
        }
    }
    PathBuf::from("../Resources/Courier.entitlements")
}

fn find_identity() -> String {
    if let Ok(id) = env::var("COURIER_SIGN_IDENTITY") {
        if !id.is_empty() {
            return id;
        }
    }

    if let Ok(out) = Command::new("security")
        .args(["find-identity", "-v", "-p", "codesigning"])
        .output()
    {
        if out.status.success() {
            let text = String::from_utf8_lossy(&out.stdout);
            let mut seen = std::collections::HashSet::new();
            for line in text.lines() {
                if line.contains("\"Developer ID Application") {
                    let parts: Vec<&str> = line.split_whitespace().collect();
                    if parts.len() >= 2 {
                        let hash = parts[1].trim_end_matches(')');
                        if seen.insert(hash.to_string()) {
                            return hash.to_string();
                        }
                    }
                }
            }
        }
    }

    "-".to_string()
}

fn sign_one(identity: &str, args: &[&str]) -> bool {
    let max_attempts = if identity == "-" { 1 } else { 3 };
    for attempt in 1..=max_attempts {
        let mut cmd = Command::new("codesign");
        cmd.args(args);
        cmd.stdout(std::process::Stdio::null());
        match cmd.status() {
            Ok(s) if s.success() => return true,
            _ => {
                if identity == "-" || attempt == max_attempts {
                    return false;
                }
                eprintln!("  Signing failed; trying again ({}/3)", attempt + 1);
                std::thread::sleep(std::time::Duration::from_secs(attempt as u64));
            }
        }
    }
    false
}

pub fn run(args: &[String]) -> i32 {
    let mut allow_missing = false;
    let mut app_path = String::new();
    let mut entitlements_override: Option<String> = None;
    let mut i = 1;

    while i < args.len() {
        match args[i].as_str() {
            "--allow-missing" => allow_missing = true,
            "--entitlements" => {
                if i + 1 >= args.len() {
                    eprintln!("inject-app-credentials: --entitlements needs a file");
                    return 2;
                }
                i += 1;
                entitlements_override = Some(args[i].clone());
            }
            "-h" | "--help" => {
                eprintln!("Usage: inject-app-credentials [--allow-missing] [--entitlements FILE] <path/to/Courier.app>");
                return 2;
            }
            s if s.starts_with('-') => {
                eprintln!("inject-app-credentials: unknown option {}", s);
                return 2;
            }
            _ => {
                if !app_path.is_empty() {
                    eprintln!("inject-app-credentials: one Courier.app at a time");
                    return 2;
                }
                app_path = args[i].clone();
            }
        }
        i += 1;
    }

    if app_path.is_empty() {
        eprintln!("Usage: inject-app-credentials.sh [--allow-missing] [--entitlements FILE] <path/to/Courier.app>");
        return 2;
    }

    let contents = Path::new(&app_path).join("Contents");
    if !contents.is_dir() {
        eprintln!(
            "inject-app-credentials: {} is not an app bundle (no Contents folder)",
            app_path
        );
        return 2;
    }

    let app = match fs::canonicalize(&app_path) {
        Ok(p) => p,
        Err(_) => PathBuf::from(&app_path),
    };
    let app_str = app.to_string_lossy().to_string();

    let entitlements = if let Some(ref e) = entitlements_override {
        PathBuf::from(e)
    } else {
        resolve_default_entitlements()
    };

    if !entitlements.exists() {
        eprintln!(
            "inject-app-credentials: no entitlements file at {}",
            entitlements.display()
        );
        return 2;
    }

    let engine = app.join("Contents/Helpers/courier-engine");
    if !engine.exists() {
        eprintln!(
            "inject-app-credentials: {} has no Contents/Helpers/courier-engine to sign",
            app_str
        );
        return 2;
    }

    // Resolve script dir for store_dirs (use exe parent)
    let script_dir = env::current_exe()
        .ok()
        .and_then(|e| e.parent().map(|p| p.to_path_buf()))
        .unwrap_or_else(|| PathBuf::from("."));

    // Read credentials
    let mut api_id = String::new();
    let mut api_hash = String::new();
    let mut origin = String::new();

    let id_in_env = env::var(ID_NAME).unwrap_or_default();
    let hash_in_env = env::var(HASH_NAME).unwrap_or_default();

    if !id_in_env.is_empty() && !hash_in_env.is_empty() {
        api_id = strip_whitespace(&id_in_env);
        api_hash = strip_whitespace(&hash_in_env);
        origin = "the environment".to_string();
    } else if !id_in_env.is_empty() || !hash_in_env.is_empty() {
        eprintln!(
            "inject-app-credentials: only one of {} and {} is set. Set both, or neither.",
            ID_NAME, HASH_NAME
        );
        return 2;
    } else {
        for dir in store_dirs(&script_dir) {
            if let (Some(id), Some(hash)) = (
                read_store_file(&dir, ID_NAME),
                read_store_file(&dir, HASH_NAME),
            ) {
                api_id = id;
                api_hash = hash;
                origin = format!("the store ({})", dir.display());
                break;
            }
        }
    }

    if api_id.is_empty() || api_hash.is_empty() {
        if allow_missing {
            eprintln!("No Telegram app ID found (bazel run //tools/sync-env-secrets:bw-pull fetches it): leaving it out, so the app will ask for Telegram keys.");
        } else {
            eprintln!("No Telegram app ID found for Courier.");
            eprintln!(
                "Looked for {} and {} in the environment, then in the store:",
                ID_NAME, HASH_NAME
            );
            for dir in store_dirs(&script_dir) {
                eprintln!("  {}", dir.display());
            }
            eprintln!("To fetch them: bazel run //tools/sync-env-secrets:bw-pull");
            eprintln!("(apps/desktop/courier/app/README.md says how to add them.)");
            return 1;
        }
    } else {
        match validate_api_id(&api_id) {
            Ok(stripped) => api_id = stripped,
            Err(msg) => {
                eprintln!("inject-app-credentials: {} (from {}).", msg, origin);
                return 2;
            }
        }

        if let Err(msg) = validate_api_hash(&api_hash) {
            eprintln!("inject-app-credentials: {} (from {}).", msg, origin);
            return 2;
        }

        let resources = app.join("Contents/Resources");
        let _ = fs::create_dir_all(&resources);
        let target = resources.join("TelegramApp.plist");

        let staged = resources.join(format!(".TelegramApp.{}", std::process::id()));

        let plist_content = generate_plist(&api_id, &api_hash);
        {
            let mut f = match fs::OpenOptions::new()
                .write(true)
                .create(true)
                .truncate(true)
                .mode(0o600)
                .open(&staged)
            {
                Ok(f) => f,
                Err(e) => {
                    eprintln!("inject-app-credentials: cannot write staging file: {}", e);
                    return 2;
                }
            };
            if f.write_all(plist_content.as_bytes()).is_err() {
                let _ = fs::remove_file(&staged);
                eprintln!("inject-app-credentials: cannot write staging file");
                return 2;
            }
        }

        // Set permissions to 644
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let _ = fs::set_permissions(&staged, fs::Permissions::from_mode(0o644));
        }

        // plutil -lint
        let lint = Command::new("plutil")
            .args(["-lint", &staged.to_string_lossy()])
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .status();
        match lint {
            Ok(s) if s.success() => {}
            _ => {
                let _ = fs::remove_file(&staged);
                eprintln!("inject-app-credentials: the property list it wrote did not check out.");
                return 2;
            }
        }

        if fs::rename(&staged, &target).is_err() {
            let _ = fs::remove_file(&staged);
            eprintln!("inject-app-credentials: cannot move staging file to target");
            return 2;
        }

        println!(
            "Wrote Contents/Resources/TelegramApp.plist from {}.",
            origin
        );
    }

    // Signing
    let identity = find_identity();

    let mut extra_flags: Vec<String> = Vec::new();
    if let Ok(flags) = env::var("COURIER_SIGN_FLAGS") {
        if !flags.is_empty() {
            extra_flags = flags.split_whitespace().map(|s| s.to_string()).collect();
        }
    }

    let mut id_flags: Vec<String> = vec!["--strip-disallowed-xattrs".to_string()];
    if identity != "-" {
        id_flags.push("--options".to_string());
        id_flags.push("runtime".to_string());
        id_flags.push("--timestamp".to_string());
    }

    // chmod -R u+w
    let _ = Command::new("chmod").args(["-R", "u+w", &app_str]).status();

    // xattr -c via find
    let _ = Command::new("find")
        .args([&app_str, "-exec", "xattr", "-c", "{}", "+"])
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status();

    // Sign engine
    let mut engine_args: Vec<&str> = vec!["--force"];
    let id_flags_refs: Vec<&str> = id_flags.iter().map(|s| s.as_str()).collect();
    engine_args.extend_from_slice(&id_flags_refs);
    engine_args.push("--identifier");
    engine_args.push(ENGINE_ID);
    let extra_refs: Vec<&str> = extra_flags.iter().map(|s| s.as_str()).collect();
    engine_args.extend_from_slice(&extra_refs);
    engine_args.push("--sign");
    engine_args.push(&identity);
    let engine_str = engine.to_string_lossy().to_string();
    engine_args.push(&engine_str);

    if !sign_one(&identity, &engine_args) {
        eprintln!(
            "inject-app-credentials: codesign could not sign the engine in {}.",
            app_str
        );
        return 1;
    }

    // Sign app
    let ent_str = entitlements.to_string_lossy().to_string();
    let mut app_args: Vec<&str> = vec!["--force"];
    app_args.extend_from_slice(&id_flags_refs);
    app_args.push("--entitlements");
    app_args.push(&ent_str);
    app_args.extend_from_slice(&extra_refs);
    app_args.push("--sign");
    app_args.push(&identity);
    app_args.push(&app_str);

    if !sign_one(&identity, &app_args) {
        eprintln!(
            "inject-app-credentials: codesign could not sign {}.",
            app_str
        );
        return 1;
    }

    // Verify
    let verify = Command::new("codesign")
        .args(["--verify", "--deep", "--strict", &app_str])
        .status();
    match verify {
        Ok(s) if s.success() => {}
        _ => {
            eprintln!(
                "inject-app-credentials: {} does not pass codesign --verify after signing.",
                app_str
            );
            return 1;
        }
    }

    // Report what kind of signature
    let details = Command::new("codesign")
        .args(["-dv", "--verbose=2", &app_str])
        .output()
        .map(|o| String::from_utf8_lossy(&o.stderr).to_string())
        .unwrap_or_default();

    let team = details
        .lines()
        .find(|l| l.starts_with("TeamIdentifier="))
        .map(|l| l.trim_start_matches("TeamIdentifier="))
        .unwrap_or("unknown");

    if identity == "-" {
        println!("Signed {} ad hoc.", app_str);
    } else if details
        .lines()
        .any(|l| l.starts_with("Authority=Developer ID Application"))
    {
        println!("Signed {} with Developer ID (team {}).", app_str, team);
    } else {
        println!(
            "Signed {} with a certificate that is not a Developer ID (team {}).",
            app_str,
            if team.is_empty() { "-" } else { team }
        );
    }

    0
}

#[cfg(unix)]
use std::os::unix::fs::OpenOptionsExt;
