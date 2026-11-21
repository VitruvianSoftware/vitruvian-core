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
use std::io::{BufRead, BufReader, Read, Write};
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use crate::check_packaged_app::check_node_entitlements;

const NODE_REL_PATH: &str = "Contents/Helpers/node";
const HELPER_REL_PATH: &str = "Contents/Resources/claude-helper/claude-helper.mjs";
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

pub fn verify_unpacked_app(
    app: &Path,
    nvmrc_path: &Path,
    expected_bundle_path: &Path,
    work_root: &Path,
) -> Result<(), String> {
    let main_exe = app.join("Contents/MacOS").join(MAIN_EXE_NAME);
    if !main_exe.is_file() {
        return Err(format!("missing main executable at {}", main_exe.display()));
    }

    let node_exe = app.join(NODE_REL_PATH);
    if !node_exe.is_file() {
        return Err(format!(
            "missing {} inside {}",
            NODE_REL_PATH,
            app.display()
        ));
    }
    let meta = fs::metadata(&node_exe)
        .map_err(|e| format!("cannot stat {}: {}", node_exe.display(), e))?;
    if meta.permissions().mode() & 0o111 == 0 {
        return Err(format!("{} is not executable", NODE_REL_PATH));
    }

    let app_archs = lipo_archs(&main_exe)?;
    let node_archs = lipo_archs(&node_exe)?;
    for required in ["arm64", "x86_64"] {
        if !node_archs.iter().any(|a| a == required) {
            return Err(format!(
                "{} lacks universal architecture {} (node: {})",
                NODE_REL_PATH,
                required,
                node_archs.join(" ")
            ));
        }
    }
    let missing_app_archs: Vec<&str> = app_archs
        .iter()
        .filter(|a| !node_archs.contains(a))
        .map(|s| s.as_str())
        .collect();
    if !missing_app_archs.is_empty() {
        return Err(format!(
            "{} lacks app architecture(s) {} (app: {}, node: {})",
            NODE_REL_PATH,
            missing_app_archs.join(" "),
            app_archs.join(" "),
            node_archs.join(" ")
        ));
    }
    println!(
        "ok: {} holds universal architectures [{}]",
        NODE_REL_PATH,
        node_archs.join(" ")
    );

    let node_cs = Command::new("codesign")
        .args(["--verify", "--strict"])
        .arg(&node_exe)
        .output()
        .map_err(|e| format!("cannot run codesign --verify on {}: {}", NODE_REL_PATH, e))?;
    if !node_cs.status.success() {
        return Err(format!(
            "codesign --verify --strict failed on {}: {}",
            NODE_REL_PATH,
            String::from_utf8_lossy(&node_cs.stderr).trim()
        ));
    }

    let app_cs = Command::new("codesign")
        .args(["--verify", "--deep", "--strict"])
        .arg(app)
        .output()
        .map_err(|e| format!("cannot run codesign --verify: {}", e))?;
    if !app_cs.status.success() {
        return Err(format!(
            "codesign --verify --deep --strict failed on {}: {}",
            app.display(),
            String::from_utf8_lossy(&app_cs.stderr).trim()
        ));
    }
    println!("ok: codesign --verify passed on node and app");

    check_node_entitlements(&node_exe)?;
    println!("ok: {} carries JIT entitlements", NODE_REL_PATH);

    let want_version = fs::read_to_string(nvmrc_path)
        .map_err(|e| format!("cannot read {}: {}", nvmrc_path.display(), e))?;
    let want_version_tag = format!("v{}", want_version.trim());

    let isolated_root = work_root.join("node_isolated_run");
    let _ = fs::remove_dir_all(&isolated_root);
    let isolated_home = isolated_root.join("home");
    fs::create_dir_all(&isolated_home).map_err(|e| {
        format!(
            "cannot create isolated HOME {}: {}",
            isolated_home.display(),
            e
        )
    })?;

    let ver_out = Command::new(&node_exe)
        .arg("--version")
        .current_dir(&isolated_root)
        .env_clear()
        .env("HOME", &isolated_home)
        .env("PATH", "/usr/bin:/bin")
        .output()
        .map_err(|e| format!("cannot run {} --version: {}", node_exe.display(), e))?;
    if !ver_out.status.success() {
        return Err(format!(
            "{} --version exited {:?}: {}",
            NODE_REL_PATH,
            ver_out.status.code(),
            String::from_utf8_lossy(&ver_out.stderr).trim()
        ));
    }
    let got_version_tag = String::from_utf8_lossy(&ver_out.stdout).trim().to_string();
    if got_version_tag != want_version_tag {
        return Err(format!(
            "{} --version reported '{}', expected '{}' from .nvmrc",
            NODE_REL_PATH, got_version_tag, want_version_tag
        ));
    }
    println!("ok: {} --version == {}", NODE_REL_PATH, got_version_tag);

    let helper_mjs = app.join(HELPER_REL_PATH);
    if !helper_mjs.is_file() {
        return Err(format!(
            "missing {} inside {}",
            HELPER_REL_PATH,
            app.display()
        ));
    }
    let want_sha = crate::sha256_hex_file(expected_bundle_path).map_err(|e| {
        format!(
            "cannot hash checked-in helper bundle {}: {}",
            expected_bundle_path.display(),
            e
        )
    })?;
    let got_sha = crate::sha256_hex_file(&helper_mjs)
        .map_err(|e| format!("cannot hash bundled helper {}: {}", helper_mjs.display(), e))?;
    if got_sha != want_sha {
        return Err(format!(
            "{} SHA-256 {} does not match checked-in bundle {}",
            HELPER_REL_PATH, got_sha, want_sha
        ));
    }
    println!(
        "ok: {} matches checked-in bundle (SHA-256 {})",
        HELPER_REL_PATH, got_sha
    );

    // Run bundled node + bundled claude-helper.mjs against a fake claude script
    // in an empty isolated environment and verify ACP initialize response.
    let fake_claude = isolated_root.join("fake-claude.sh");
    fs::write(&fake_claude, "#!/bin/sh\necho '2.1.326 (Claude Code)'\n")
        .map_err(|e| format!("cannot write fake claude: {}", e))?;
    fs::set_permissions(&fake_claude, fs::Permissions::from_mode(0o755))
        .map_err(|e| format!("cannot chmod fake claude: {}", e))?;

    let mut child = Command::new(&node_exe)
        .arg(&helper_mjs)
        .arg("--claude-path")
        .arg(&fake_claude)
        .current_dir(&isolated_root)
        .env_clear()
        .env("HOME", &isolated_home)
        .env("PATH", "/usr/bin:/bin")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| format!("cannot spawn bundled node + helper: {}", e))?;

    let mut stdin = child
        .stdin
        .take()
        .ok_or_else(|| "missing stdin pipe on bundled helper".to_string())?;
    let stdout = child
        .stdout
        .take()
        .ok_or_else(|| "missing stdout pipe on bundled helper".to_string())?;
    let mut stderr_pipe = child
        .stderr
        .take()
        .ok_or_else(|| "missing stderr pipe on bundled helper".to_string())?;

    let req = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":1,\"clientInfo\":{\"name\":\"VitruvianCode\",\"version\":\"1.0.0\"},\"clientCapabilities\":{}}}\n";
    stdin
        .write_all(req.as_bytes())
        .and_then(|_| stdin.flush())
        .map_err(|e| format!("cannot write initialize request: {}", e))?;

    // Keep stdin open until the helper writes its initialize response, then
    // drop stdin so it sees EOF and exits cleanly.
    let mut stdout_reader = BufReader::new(stdout);
    let mut response_line = String::new();
    stdout_reader
        .read_line(&mut response_line)
        .map_err(|e| format!("cannot read initialize response: {}", e))?;
    drop(stdin);

    let mut trailing_stdout = String::new();
    let _ = stdout_reader.read_to_string(&mut trailing_stdout);
    let mut stderr_raw = String::new();
    let _ = stderr_pipe.read_to_string(&mut stderr_raw);
    let status = child
        .wait()
        .map_err(|e| format!("failed waiting for bundled helper: {}", e))?;

    let stdout = response_line.trim().to_string();
    let stderr = stderr_raw.trim().to_string();
    if !status.success() {
        return Err(format!(
            "bundled helper exited {:?}; stdout='{}' stderr='{}'",
            status.code(),
            stdout,
            stderr
        ));
    }
    if !stderr.is_empty() {
        return Err(format!(
            "bundled helper emitted unexpected stderr: {}",
            stderr
        ));
    }
    for expected_fragment in [
        "\"jsonrpc\":\"2.0\"",
        "\"id\":1",
        "\"protocolVersion\":1",
        "\"vitruvian-claude-helper\"",
        "\"claudeVersion\":\"2.1.326\"",
        "\"minClaudeVersionForMcpSecrets\"",
        "\"loadSession\":false",
        "\"authMethods\":[]",
    ] {
        if !stdout.contains(expected_fragment) {
            return Err(format!(
                "ACP initialize response missing {}: got '{}'",
                expected_fragment, stdout
            ));
        }
    }
    println!("ok: bundled node + claude-helper.mjs completed ACP initialize");

    Ok(())
}

pub fn run(args: &[String]) -> i32 {
    let rest = if args.len() > 1 { &args[1..] } else { &[] };
    if rest.len() < 4 {
        eprintln!(
            "Usage: bazel-app-holds-node <app name> <nvmrc path> <expected helper.mjs path> <archive-or-app-path>..."
        );
        return 2;
    }

    let app_name = &rest[0];
    let nvmrc_path = Path::new(&rest[1]);
    let expected_bundle = Path::new(&rest[2]);
    let paths = &rest[3..];
    let tmp_root = PathBuf::from(std::env::var("TEST_TMPDIR").unwrap_or_else(|_| "/tmp".into()));
    let unzip_dir = tmp_root.join("app_holds_node_unzip");

    let app = match crate::bazel_app_holds_bot::resolve_app_bundle(app_name, paths, &unzip_dir) {
        Ok(a) => a,
        Err(msg) => {
            eprintln!("FAIL: {}", msg);
            return 2;
        }
    };

    if let Err(err) = verify_unpacked_app(&app, nvmrc_path, expected_bundle, &tmp_root) {
        eprintln!("FAIL: {}", err);
        return 1;
    }

    0
}
