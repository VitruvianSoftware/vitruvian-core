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

//! Rust ports of `apps/mobile/android-remote/macagent/install.sh` and `pair.sh`.

use std::env;
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::thread;
use std::time::Duration;

pub const LABEL: &str = "com.vitruvian.remote-agent";
pub const BIN_REL_DIR: &str = ".local/bin";
pub const BIN_NAME: &str = "vitruvian-remote-agent";
pub const BIN_REL_PATH: &str = ".local/bin/vitruvian-remote-agent";
pub const LOG_REL_DIR: &str = "Library/Logs";
pub const LOG_REL_PATH: &str = "Library/Logs/vitruvian-remote-agent.log";
pub const PLIST_REL_DIR: &str = "Library/LaunchAgents";
pub const SIGN_ID: &str = "Vitruvian Remote Agent";
pub const BASE_URL: &str = "http://127.0.0.1:7411";
pub const HEALTHZ_URL: &str = "http://127.0.0.1:7411/healthz";
pub const RUNFILES_PKG_SUBDIR: &str = "_main/apps/mobile/android-remote/macagent";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct InstallerPaths {
    pub bin_dir: PathBuf,
    pub bin: PathBuf,
    pub log_dir: PathBuf,
    pub log: PathBuf,
    pub plist_dir: PathBuf,
    pub plist: PathBuf,
}

impl InstallerPaths {
    pub fn for_home(home: &Path) -> Self {
        let bin_dir = home.join(BIN_REL_DIR);
        let bin = bin_dir.join(BIN_NAME);
        let log_dir = home.join(LOG_REL_DIR);
        let log = home.join(LOG_REL_PATH);
        let plist_dir = home.join(PLIST_REL_DIR);
        let plist = plist_dir.join(format!("{LABEL}.plist"));
        Self {
            bin_dir,
            bin,
            log_dir,
            log,
            plist_dir,
            plist,
        }
    }
}

pub fn expand_tilde(arg: &str, home: &str) -> String {
    if arg == "~" {
        home.to_string()
    } else if let Some(rest) = arg.strip_prefix("~/") {
        format!("{home}/{rest}")
    } else {
        arg.to_string()
    }
}

pub fn xml_escape(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    for ch in input.chars() {
        match ch {
            '&' => out.push_str("&amp;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            '"' => out.push_str("&quot;"),
            _ => out.push(ch),
        }
    }
    out
}

pub fn format_args_xml(args: &[String], home: &str) -> String {
    let mut xml = String::new();
    for arg in args {
        let expanded = expand_tilde(arg, home);
        let escaped = xml_escape(&expanded);
        xml.push_str("\t\t<string>");
        xml.push_str(&escaped);
        xml.push_str("</string>\n");
    }
    xml
}

pub fn render_plist(template: &str, bin: &Path, log: &Path, args_xml: &str) -> String {
    let bin_str = bin.to_string_lossy();
    let log_str = log.to_string_lossy();
    let mut out = String::with_capacity(template.len() + args_xml.len() + 128);
    for line in template.lines() {
        let replaced = line
            .replace("__BIN__", &bin_str)
            .replace("__LOG__", &log_str);
        if replaced == "__ARGS__" {
            out.push_str(args_xml);
        } else {
            out.push_str(&replaced);
            out.push('\n');
        }
    }
    out
}

pub fn is_executable(path: &Path) -> bool {
    match fs::metadata(path) {
        Ok(meta) => meta.is_file() && (meta.permissions().mode() & 0o111 != 0),
        Err(_) => false,
    }
}

pub fn resolve_src_dir(argv0: &str, runfiles_dir_env: Option<&str>) -> PathBuf {
    let runfiles = match runfiles_dir_env {
        Some(dir) if !dir.is_empty() => PathBuf::from(dir),
        _ => PathBuf::from(format!("{argv0}.runfiles")),
    };
    let candidate = runfiles.join(RUNFILES_PKG_SUBDIR);
    if candidate.is_dir() {
        return candidate;
    }
    let exe_path = Path::new(argv0);
    if let Some(parent) = exe_path.parent() {
        if !parent.as_os_str().is_empty() {
            if let Ok(canon) = fs::canonicalize(parent) {
                return canon;
            }
            return parent.to_path_buf();
        }
    }
    env::current_dir().unwrap_or_else(|_| PathBuf::from("."))
}

pub fn find_agent_binary(src_dir: &Path) -> Option<PathBuf> {
    let nested = src_dir.join("macagent_/macagent");
    if is_executable(&nested) {
        return Some(nested);
    }
    let flat = src_dir.join("macagent");
    if is_executable(&flat) {
        return Some(flat);
    }
    None
}

fn current_uname_s() -> String {
    Command::new("uname")
        .arg("-s")
        .output()
        .ok()
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .unwrap_or_default()
}

fn current_uid() -> Result<u32, String> {
    let output = Command::new("id")
        .arg("-u")
        .output()
        .map_err(|e| format!("failed to run id -u: {e}"))?;
    if !output.status.success() {
        return Err("id -u exited non-zero".to_string());
    }
    String::from_utf8_lossy(&output.stdout)
        .trim()
        .parse::<u32>()
        .map_err(|e| format!("failed to parse uid: {e}"))
}

pub fn validate_pair_args(args: &[String]) -> Result<&[String], &'static str> {
    if args.len() < 2 {
        return Err(
            "usage: bazel run //mobile/android/remote/macagent:pair -- <six-digit code from the phone>",
        );
    }
    Ok(&args[1..])
}

pub fn run_pair(args: &[String]) -> i32 {
    let pair_args = match validate_pair_args(args) {
        Ok(rest) => rest,
        Err(msg) => {
            eprintln!("{msg}");
            return 2;
        }
    };

    let argv0 = args.first().map(|s| s.as_str()).unwrap_or("pair");
    let runfiles_env = env::var("RUNFILES_DIR").ok();
    let src_dir = resolve_src_dir(argv0, runfiles_env.as_deref());
    let bin = match find_agent_binary(&src_dir) {
        Some(b) => b,
        None => {
            eprintln!(
                "pair.sh: built agent not found under {} (run via: bazel run //apps/mobile/android-remote/macagent:pair -- <code>)",
                src_dir.display()
            );
            return 1;
        }
    };

    let status = Command::new(&bin).arg("pair").args(pair_args).status();
    match status {
        Ok(s) => s.code().unwrap_or(1),
        Err(e) => {
            eprintln!("pair.sh: failed to execute {}: {e}", bin.display());
            1
        }
    }
}

pub fn run_install(args: &[String]) -> i32 {
    if current_uname_s() != "Darwin" {
        eprintln!("install.sh: this agent only runs on macOS");
        return 1;
    }

    let uid = match current_uid() {
        Ok(0) => {
            eprintln!("install.sh: do not run as root -- this is a per-user login item");
            return 1;
        }
        Ok(u) => u,
        Err(e) => {
            eprintln!("install.sh: {e}");
            return 1;
        }
    };

    let argv0 = args.first().map(|s| s.as_str()).unwrap_or("install");
    let runfiles_env = env::var("RUNFILES_DIR").ok();
    let src_dir = resolve_src_dir(argv0, runfiles_env.as_deref());
    let plist_src = src_dir.join(format!("{LABEL}.plist"));
    let bin_src = match find_agent_binary(&src_dir) {
        Some(b) if plist_src.is_file() => b,
        _ => {
            eprintln!(
                "install.sh: built agent or plist not found under {} (run via: bazel run //apps/mobile/android-remote/macagent:install)",
                src_dir.display()
            );
            return 1;
        }
    };

    let home = match env::var("HOME") {
        Ok(h) if !h.is_empty() => h,
        _ => {
            eprintln!("install.sh: HOME is not set");
            return 1;
        }
    };
    let paths = InstallerPaths::for_home(Path::new(&home));
    let extra_args = if args.len() > 1 { &args[1..] } else { &[] };
    let args_xml = format_args_xml(extra_args, &home);

    for dir in [&paths.bin_dir, &paths.log_dir, &paths.plist_dir] {
        if let Err(e) = fs::create_dir_all(dir) {
            eprintln!("install.sh: failed to create {}: {e}", dir.display());
            return 1;
        }
        let _ = fs::set_permissions(dir, fs::Permissions::from_mode(0o755));
    }

    if let Err(e) = fs::copy(&bin_src, &paths.bin) {
        eprintln!(
            "install.sh: failed to copy {} to {}: {e}",
            bin_src.display(),
            paths.bin.display()
        );
        return 1;
    }
    if let Err(e) = fs::set_permissions(&paths.bin, fs::Permissions::from_mode(0o755)) {
        eprintln!("install.sh: failed to chmod {}: {e}", paths.bin.display());
        return 1;
    }

    let has_sign_id = Command::new("security")
        .args(["find-identity", "-p", "codesigning"])
        .output()
        .ok()
        .map(|o| String::from_utf8_lossy(&o.stdout).contains(&format!("\"{SIGN_ID}\"")))
        .unwrap_or(false);

    let signed_msg = if has_sign_id {
        let status = Command::new("codesign")
            .args(["-f", "-s", SIGN_ID, "-i", "dev.vitruvian.remote-agent"])
            .arg(&paths.bin)
            .stderr(std::process::Stdio::null())
            .status();
        if !status.map(|s| s.success()).unwrap_or(false) {
            eprintln!("install.sh: codesign with \"{SIGN_ID}\" failed");
            return 1;
        }
        format!("signed as \"{SIGN_ID}\" (TCC grants survive reinstalls)")
    } else {
        format!(
            "ad-hoc signed: re-grant Screen Recording after EVERY reinstall, or create the \"{SIGN_ID}\" identity (see README)"
        )
    };

    let template = match fs::read_to_string(&plist_src) {
        Ok(t) => t,
        Err(e) => {
            eprintln!("install.sh: failed to read {}: {e}", plist_src.display());
            return 1;
        }
    };
    let rendered_plist = render_plist(&template, &paths.bin, &paths.log, &args_xml);
    if let Err(e) = fs::write(&paths.plist, &rendered_plist) {
        eprintln!("install.sh: failed to write {}: {e}", paths.plist.display());
        return 1;
    }
    let _ = fs::set_permissions(&paths.plist, fs::Permissions::from_mode(0o644));

    let lint_ok = Command::new("plutil")
        .arg("-lint")
        .arg(&paths.plist)
        .stdout(std::process::Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false);
    if !lint_ok {
        eprintln!(
            "install.sh: plutil -lint failed for {}",
            paths.plist.display()
        );
        return 1;
    }

    let service_target = format!("gui/{uid}/{LABEL}");
    let domain_target = format!("gui/{uid}");
    let _ = Command::new("launchctl")
        .args(["bootout", &service_target])
        .stderr(std::process::Stdio::null())
        .status();

    for _ in 0..50 {
        let still_loaded = Command::new("launchctl")
            .args(["print", &service_target])
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .status()
            .map(|s| s.success())
            .unwrap_or(false);
        if !still_loaded {
            break;
        }
        thread::sleep(Duration::from_millis(200));
    }

    if !Command::new("launchctl")
        .args(["bootstrap", &domain_target])
        .arg(&paths.plist)
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
    {
        eprintln!("install.sh: launchctl bootstrap failed");
        return 1;
    }

    if !Command::new("launchctl")
        .args(["enable", &service_target])
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
    {
        eprintln!("install.sh: launchctl enable failed");
        return 1;
    }

    let _ = Command::new("launchctl")
        .args(["kickstart", "-k", &service_target])
        .stderr(std::process::Stdio::null())
        .status();

    for _ in 0..10 {
        let healthy = Command::new("curl")
            .args(["-fsS", "--max-time", "1", HEALTHZ_URL])
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null())
            .status()
            .map(|s| s.success())
            .unwrap_or(false);
        if healthy {
            let extracted_args = Command::new("plutil")
                .args(["-extract", "ProgramArguments", "json", "-o", "-"])
                .arg(&paths.plist)
                .stderr(std::process::Stdio::null())
                .output()
                .ok()
                .map(|o| String::from_utf8_lossy(&o.stdout).replace('\n', ""))
                .unwrap_or_default();
            println!("vitruvian-remote-agent installed and answering on {BASE_URL}");
            println!("  signing: {signed_msg}");
            println!("  binary: {}", paths.bin.display());
            println!("  args:   {extracted_args}");
            println!("  plist:  {}", paths.plist.display());
            println!("  log:    {}", paths.log.display());
            println!("  try:    curl -s {BASE_URL}/v1/metrics | jq .");
            println!(
                "  mcp:    {home}/.config/vitruvian-remote-agent/mcp-token (0600) -- the phone bridge's token"
            );
            println!("          claude mcp add --transport http phone {BASE_URL}/mcp/phone \\");
            println!(
                "            --header \"Authorization: Bearer $(cat ~/.config/vitruvian-remote-agent/mcp-token)\""
            );
            println!(
                "  remove: launchctl bootout {service_target}; rm {} {}",
                paths.plist.display(),
                paths.bin.display()
            );
            return 0;
        }
        thread::sleep(Duration::from_millis(500));
    }

    eprintln!(
        "install.sh: agent did not answer on :7411 within 5s -- see {}",
        paths.log.display()
    );
    1
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn make_temp_dir(label: &str) -> PathBuf {
        let dir = env::temp_dir().join(format!(
            "macagent-scripts-test-{label}-{}",
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_nanos()
        ));
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn installer_paths_match_contract() {
        let home = Path::new("/Users/tester");
        let p = InstallerPaths::for_home(home);
        assert_eq!(p.bin_dir, PathBuf::from("/Users/tester/.local/bin"));
        assert_eq!(
            p.bin,
            PathBuf::from("/Users/tester/.local/bin/vitruvian-remote-agent")
        );
        assert_eq!(p.log_dir, PathBuf::from("/Users/tester/Library/Logs"));
        assert_eq!(
            p.log,
            PathBuf::from("/Users/tester/Library/Logs/vitruvian-remote-agent.log")
        );
        assert_eq!(
            p.plist_dir,
            PathBuf::from("/Users/tester/Library/LaunchAgents")
        );
        assert_eq!(
            p.plist,
            PathBuf::from("/Users/tester/Library/LaunchAgents/com.vitruvian.remote-agent.plist")
        );
        assert_eq!(BASE_URL, "http://127.0.0.1:7411");
    }

    #[test]
    fn tilde_expansion_handles_bare_and_prefixed_paths() {
        assert_eq!(expand_tilde("~", "/Users/alice"), "/Users/alice");
        assert_eq!(
            expand_tilde("~/.kube/config", "/Users/alice"),
            "/Users/alice/.kube/config"
        );
        assert_eq!(expand_tilde("--kubeconfig", "/Users/alice"), "--kubeconfig");
        assert_eq!(expand_tilde("~other/file", "/Users/alice"), "~other/file");
    }

    #[test]
    fn xml_escape_escapes_four_special_chars() {
        assert_eq!(xml_escape("a&b<c>d\"e'f"), "a&amp;b&lt;c&gt;d&quot;e'f");
    }

    #[test]
    fn format_args_xml_expands_tilde_and_escapes() {
        let args = vec![
            "--kubeconfig".to_string(),
            "~/.kube/cluster.yaml".to_string(),
            "--filter".to_string(),
            "a&b<\"c\">".to_string(),
        ];
        let xml = format_args_xml(&args, "/Users/james");
        assert_eq!(
            xml,
            "\t\t<string>--kubeconfig</string>\n\t\t<string>/Users/james/.kube/cluster.yaml</string>\n\t\t<string>--filter</string>\n\t\t<string>a&amp;b&lt;&quot;c&quot;&gt;</string>\n"
        );
    }

    #[test]
    fn render_plist_substitutes_placeholders() {
        let template = "\
<dict>
\t<key>ProgramArguments</key>
\t<array>
\t\t<string>__BIN__</string>
__ARGS__
\t</array>
\t<key>StandardOutPath</key>
\t<string>__LOG__</string>
</dict>
";
        let args_xml = format_args_xml(&["--port".into(), "7411".into()], "/Users/test");
        let rendered = render_plist(
            template,
            Path::new("/Users/test/.local/bin/vitruvian-remote-agent"),
            Path::new("/Users/test/Library/Logs/vitruvian-remote-agent.log"),
            &args_xml,
        );
        assert!(rendered.contains("<string>/Users/test/.local/bin/vitruvian-remote-agent</string>"));
        assert!(rendered.contains("\t\t<string>--port</string>\n\t\t<string>7411</string>\n"));
        assert!(rendered
            .contains("<string>/Users/test/Library/Logs/vitruvian-remote-agent.log</string>"));
        assert!(!rendered.contains("__BIN__"));
        assert!(!rendered.contains("__LOG__"));
        assert!(!rendered.contains("__ARGS__"));
    }

    #[test]
    fn find_agent_binary_prefers_nested_then_flat() {
        let dir = make_temp_dir("find-bin");
        assert!(find_agent_binary(&dir).is_none());

        let flat = dir.join("macagent");
        fs::write(&flat, b"#!/bin/sh\n").unwrap();
        fs::set_permissions(&flat, fs::Permissions::from_mode(0o755)).unwrap();
        assert_eq!(find_agent_binary(&dir), Some(flat.clone()));

        let nested_dir = dir.join("macagent_");
        fs::create_dir_all(&nested_dir).unwrap();
        let nested = nested_dir.join("macagent");
        fs::write(&nested, b"#!/bin/sh\n").unwrap();
        fs::set_permissions(&nested, fs::Permissions::from_mode(0o755)).unwrap();
        assert_eq!(find_agent_binary(&dir), Some(nested));

        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn resolve_src_dir_uses_runfiles_when_present() {
        let dir = make_temp_dir("runfiles");
        let pkg_dir = dir.join(RUNFILES_PKG_SUBDIR);
        fs::create_dir_all(&pkg_dir).unwrap();

        let resolved = resolve_src_dir("/fake/install", Some(&dir.to_string_lossy()));
        assert_eq!(resolved, pkg_dir);

        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn validate_pair_args_requires_code() {
        let empty = vec!["pair".to_string()];
        assert!(validate_pair_args(&empty).is_err());

        let with_code = vec!["pair".to_string(), "482917".to_string()];
        assert_eq!(
            validate_pair_args(&with_code).unwrap(),
            &["482917".to_string()]
        );
    }

    #[test]
    fn run_pair_without_args_exits_two() {
        let code = run_pair(&["pair".to_string()]);
        assert_eq!(code, 2);
    }
}
