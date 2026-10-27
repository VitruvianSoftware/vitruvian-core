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
use std::path::PathBuf;
use std::process::Command;

#[test]
fn test_mirror_build() {
    let test_srcdir = std::env::var("TEST_SRCDIR").expect("TEST_SRCDIR not set");
    let test_workspace = std::env::var("TEST_WORKSPACE").expect("TEST_WORKSPACE not set");
    let test_tmpdir = PathBuf::from(std::env::var("TEST_TMPDIR").expect("TEST_TMPDIR not set"));

    let app = PathBuf::from(&test_srcdir)
        .join(&test_workspace)
        .join("apps/desktop/nexus-agent");
    let mirror = test_tmpdir.join("mirror");
    let work = mirror.join("macos");
    fs::create_dir_all(&work).expect("create work dir");

    let status = Command::new("cp")
        .arg("-RL")
        .arg(app.join("macos/Package.swift"))
        .arg(app.join("macos/Sources"))
        .arg(app.join("macos/Tests"))
        .arg(app.join("macos/Resources"))
        .arg(&work)
        .status()
        .expect("cp macos sources");
    assert!(status.success(), "cp macos sources failed");

    let status = Command::new("cp")
        .arg("-RL")
        .arg(app.join("testdata"))
        .arg(&mirror)
        .status()
        .expect("cp testdata");
    assert!(status.success(), "cp testdata failed");

    let home = test_tmpdir.join("home");
    fs::create_dir_all(&home).expect("create home dir");
    let build_dir = test_tmpdir.join("build");
    let cache_dir = test_tmpdir.join("cache");
    let dist_dir = test_tmpdir.join("dist");

    let status = Command::new("xcrun")
        .args([
            "swift",
            "build",
            "--package-path",
            work.to_str().unwrap(),
            "--scratch-path",
            build_dir.to_str().unwrap(),
            "--cache-path",
            cache_dir.to_str().unwrap(),
            "--disable-sandbox",
        ])
        .env("HOME", &home)
        .status()
        .expect("xcrun swift build");
    assert!(status.success(), "xcrun swift build failed");

    let bin_path_out = Command::new("xcrun")
        .args([
            "swift",
            "build",
            "--package-path",
            work.to_str().unwrap(),
            "--scratch-path",
            build_dir.to_str().unwrap(),
            "--cache-path",
            cache_dir.to_str().unwrap(),
            "--disable-sandbox",
            "--show-bin-path",
        ])
        .env("HOME", &home)
        .output()
        .expect("xcrun swift build --show-bin-path");
    assert!(
        bin_path_out.status.success(),
        "xcrun swift build --show-bin-path failed"
    );
    let built = PathBuf::from(String::from_utf8_lossy(&bin_path_out.stdout).trim());

    let bundle_bin_rel = std::env::var("BUNDLE_BIN").expect("BUNDLE_BIN not set");
    let bundle_bin = PathBuf::from(&test_srcdir)
        .join(&test_workspace)
        .join(bundle_bin_rel);
    let status = Command::new(&bundle_bin)
        .arg(built.join("NexusAgent"))
        .arg("0.0.0")
        .arg(&dist_dir)
        .current_dir(&work)
        .env("HOME", &home)
        .status()
        .expect("bundle-app");
    assert!(status.success(), "bundle-app failed");

    let packaged = dist_dir.join("NexusAgent.app");
    let status = Command::new("codesign")
        .args(["--verify", "--deep", "--strict"])
        .arg(&packaged)
        .status()
        .expect("codesign --verify");
    assert!(status.success(), "codesign --verify failed");

    let test_out = Command::new("xcrun")
        .args([
            "swift",
            "test",
            "--package-path",
            work.to_str().unwrap(),
            "--scratch-path",
            build_dir.to_str().unwrap(),
            "--cache-path",
            cache_dir.to_str().unwrap(),
            "--disable-sandbox",
        ])
        .env_remove("TEST_SRCDIR")
        .env_remove("TEST_WORKSPACE")
        .env("HOME", &home)
        .env("CFFIXED_USER_HOME", &home)
        .env("NEXUS_AGENT_PACKAGED_APP", &packaged)
        .output()
        .expect("xcrun swift test");

    let log = format!(
        "{}{}",
        String::from_utf8_lossy(&test_out.stdout),
        String::from_utf8_lossy(&test_out.stderr)
    );
    if !test_out.status.success() {
        eprintln!("{log}");
        panic!("xcrun swift test failed");
    }

    let summary = log
        .lines()
        .filter(|line| line.contains("Executed ") && line.contains("with 0 failures"))
        .last()
        .unwrap_or("");
    println!(
        "swift test: {}",
        if summary.is_empty() {
            "no summary line"
        } else {
            summary
        }
    );
    let ran_some = summary
        .split_whitespace()
        .nth(1)
        .and_then(|n| n.parse::<u32>().ok())
        .is_some_and(|n| n > 0);
    if !ran_some {
        eprintln!("{log}");
        panic!("swift test ran no tests");
    }

    let found = log
        .lines()
        .filter(|line| line.starts_with("packaged app: found "))
        .last()
        .unwrap_or("");
    println!(
        "{}",
        if found.is_empty() {
            "packaged app: not looked at"
        } else {
            found
        }
    );
    if found.is_empty() {
        eprintln!("{log}");
        panic!("no test looked for the copy of Mermaid in the packaged app");
    }
}
