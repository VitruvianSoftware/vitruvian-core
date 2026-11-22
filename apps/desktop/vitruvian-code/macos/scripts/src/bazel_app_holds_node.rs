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

use crate::check_packaged_app::{
    can_run_arch, check_helper_set, Helper, HelperFile, UNIVERSAL_ARCHS,
};

const HELPER_REL_PATH: &str = "Contents/Resources/claude-helper/claude-helper.mjs";
const MAIN_EXE_NAME: &str = "VitruvianCode";

/// `node --version` of one bundled Node, run in an empty environment, must be
/// the version `.nvmrc` names.
fn check_node_version(
    node: &HelperFile,
    want_version_tag: &str,
    isolated_root: &Path,
    isolated_home: &Path,
) -> Result<(), String> {
    let ver_out = Command::new(&node.path)
        .arg("--version")
        .current_dir(isolated_root)
        .env_clear()
        .env("HOME", isolated_home)
        .env("PATH", "/usr/bin:/bin")
        .output()
        .map_err(|e| format!("cannot run {} --version: {}", node.path.display(), e))?;
    if !ver_out.status.success() {
        return Err(format!(
            "{} --version exited {:?}: {}",
            node.rel,
            ver_out.status.code(),
            String::from_utf8_lossy(&ver_out.stderr).trim()
        ));
    }
    let got_version_tag = String::from_utf8_lossy(&ver_out.stdout).trim().to_string();
    if got_version_tag != want_version_tag {
        return Err(format!(
            "{} --version reported '{}', expected '{}' from .nvmrc",
            node.rel, got_version_tag, want_version_tag
        ));
    }
    println!("ok: {} --version == {}", node.rel, got_version_tag);
    Ok(())
}

/// Runs one bundled Node with the bundled `claude-helper.mjs` against a fake
/// claude script in an empty isolated environment and verifies the ACP
/// `initialize` response.
fn check_acp_initialize(
    node: &HelperFile,
    helper_mjs: &Path,
    fake_claude: &Path,
    isolated_root: &Path,
    isolated_home: &Path,
) -> Result<(), String> {
    let mut child = Command::new(&node.path)
        .arg(helper_mjs)
        .arg("--claude-path")
        .arg(fake_claude)
        .current_dir(isolated_root)
        .env_clear()
        .env("HOME", isolated_home)
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
    println!(
        "ok: {} + claude-helper.mjs completed ACP initialize",
        node.rel
    );
    Ok(())
}

/// The Bazel-built app holds the release's universal layout whatever
/// architectures its main program is built for: a thin `node-arm64` and
/// `node-x86_64` and no fat `node` (XProtect refuses a universal app with a fat
/// helper). Each is signed with the JIT entitlements; each one this Mac can run
/// reports the `.nvmrc` version and completes the helper's ACP `initialize`.
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

    // Present, executable, thin for its own architecture, signed, JIT
    // entitlements and nothing else.
    let nodes = check_helper_set(app, UNIVERSAL_ARCHS, Helper::Node)?;
    for node in &nodes {
        println!(
            "ok: {} is thin for {} and signed with JIT entitlements",
            node.rel, node.arch
        );
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
    println!("ok: codesign --verify passed on the app");

    let want_version = fs::read_to_string(nvmrc_path)
        .map_err(|e| format!("cannot read {}: {}", nvmrc_path.display(), e))?;
    let want_version_tag = format!("v{}", want_version.trim());

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

    let mut ran = 0;
    for node in &nodes {
        if !can_run_arch(&node.arch) {
            println!(
                "skip: {} is for {}, which this Mac cannot run",
                node.rel, node.arch
            );
            continue;
        }
        let isolated_root = work_root.join("node_isolated_run").join(&node.arch);
        let _ = fs::remove_dir_all(&isolated_root);
        let isolated_home = isolated_root.join("home");
        fs::create_dir_all(&isolated_home).map_err(|e| {
            format!(
                "cannot create isolated HOME {}: {}",
                isolated_home.display(),
                e
            )
        })?;
        check_node_version(node, &want_version_tag, &isolated_root, &isolated_home)?;

        let fake_claude = isolated_root.join("fake-claude.sh");
        fs::write(&fake_claude, "#!/bin/sh\necho '2.1.326 (Claude Code)'\n")
            .map_err(|e| format!("cannot write fake claude: {}", e))?;
        fs::set_permissions(&fake_claude, fs::Permissions::from_mode(0o755))
            .map_err(|e| format!("cannot chmod fake claude: {}", e))?;
        check_acp_initialize(
            node,
            &helper_mjs,
            &fake_claude,
            &isolated_root,
            &isolated_home,
        )?;
        ran += 1;
    }
    if ran == 0 {
        return Err("no bundled node could be run on this Mac".to_string());
    }

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
