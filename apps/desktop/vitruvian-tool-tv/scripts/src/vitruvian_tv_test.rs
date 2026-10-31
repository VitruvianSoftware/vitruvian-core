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

fn built_dir() -> PathBuf {
    let manifest = std::env::var("MANIFEST_PATH")
        .expect("MANIFEST_PATH must point to built/vitruvian-tv/vitruvian-tool.json");
    PathBuf::from(manifest)
        .parent()
        .expect("manifest has a parent")
        .to_path_buf()
}

fn conformance_bin() -> PathBuf {
    PathBuf::from(
        std::env::var("CONFORMANCE_BIN")
            .expect("CONFORMANCE_BIN must point to the conformance binary"),
    )
}

fn copy_dir_deref(src: &Path, dst: &Path) {
    fs::create_dir_all(dst).expect("create dest dir");
    for entry in fs::read_dir(src).expect("read source dir") {
        let entry = entry.expect("dir entry");
        let dest = dst.join(entry.file_name());
        let src_path = entry.path();
        let real = fs::canonicalize(&src_path).unwrap_or_else(|_| src_path.clone());
        let meta = fs::metadata(&real).expect("metadata");
        if meta.is_dir() {
            copy_dir_deref(&real, &dest);
        } else {
            fs::copy(&real, &dest).expect("copy file");
        }
    }
}

fn setup_folder(name: &str) -> PathBuf {
    let built = built_dir();
    let tmp_base = std::env::var("TEST_TMPDIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| std::env::temp_dir());
    let scratch = tmp_base.join(format!("scratch-{name}-{}", std::process::id()));
    let folder = scratch.join("vitruvian-tv");
    if folder.exists() {
        fs::remove_dir_all(&folder).expect("clean old folder");
    }
    copy_dir_deref(&built, &folder);
    let tool = folder.join("bin/tool");
    fs::set_permissions(&tool, fs::Permissions::from_mode(0o755)).expect("chmod bin/tool");
    folder
}

#[test]
fn test_folder_holds_the_rust_program() {
    let folder = setup_folder("holds");
    let tool = folder.join("bin/tool");
    let meta = fs::metadata(&tool).expect("bin/tool exists");
    assert!(
        meta.permissions().mode() & 0o111 != 0,
        "bin/tool is executable"
    );
    assert!(
        !folder.join("bin/tool.py").exists(),
        "bin/tool.py must not exist"
    );
    assert!(!folder.join("lib").exists(), "lib/ must not exist");
}

#[test]
fn test_sdk_conformance_suite() {
    let folder = setup_folder("conformance");
    let bin = conformance_bin();
    let mut env: Vec<(String, String)> = std::env::vars().collect();
    env.retain(|(k, _)| k != "VITRUVIAN_TV_LIVE");
    let mut cmd = Command::new(&bin);
    cmd.arg(&folder);
    cmd.env_clear();
    for (k, v) in &env {
        cmd.env(k, v);
    }
    let output = cmd.output().expect("run conformance binary");
    assert!(
        output.status.success(),
        "conformance failed:\n{}\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr),
    );
}
