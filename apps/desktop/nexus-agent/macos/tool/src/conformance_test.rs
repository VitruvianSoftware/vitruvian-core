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

//! The built Nexus Agent tool validates and passes the conformance script.
//!
//! Copies built/nexus-agent (dereferencing symlinks) into a scratch dir,
//! creates scratch/home, sets HOME and CFFIXED_USER_HOME, runs
//! `vitruvian-tool validate` and the conformance binary, and asserts both
//! exit 0.

use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

fn resolve_env(key: &str) -> PathBuf {
    let raw = std::env::var(key).unwrap_or_else(|_| panic!("{} not set", key));
    let p = PathBuf::from(&raw);
    if p.exists() {
        return p;
    }
    if let Ok(runfiles) = std::env::var("RUNFILES_DIR") {
        let resolved = PathBuf::from(&runfiles).join("_main").join(&raw);
        if resolved.exists() {
            return resolved;
        }
    }
    p
}

fn copy_dir_deref(src: &Path, dst: &Path) -> std::io::Result<()> {
    fs::create_dir_all(dst)?;
    for entry in fs::read_dir(src)? {
        let entry = entry?;
        let src_path = entry.path();
        let meta = fs::metadata(&src_path)?;
        let dst_path = dst.join(entry.file_name());
        if meta.is_dir() {
            copy_dir_deref(&src_path, &dst_path)?;
        } else {
            fs::copy(&src_path, &dst_path)?;
        }
    }
    Ok(())
}

#[test]
fn conformance_test() {
    let manifest_path = resolve_env("MANIFEST_PATH");
    let conformance_bin = resolve_env("CONFORMANCE_BIN");
    let validate_bin = resolve_env("VALIDATE_BIN");

    let built = manifest_path.parent().expect("MANIFEST_PATH has no parent");

    let base = std::env::var("TEST_TMPDIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| std::env::temp_dir());
    let scratch = tempfile::tempdir_in(&base).unwrap_or_else(|_| {
        let p = base.join(format!("nexus-conformance-{}", std::process::id()));
        fs::create_dir_all(&p).unwrap();
        tempfile::TempDir::new_in(&p).unwrap()
    });

    let folder = scratch.path().join("nexus-agent");
    copy_dir_deref(built, &folder).expect("cannot copy built folder");

    let home = scratch.path().join("home");
    fs::create_dir_all(&home).expect("cannot create home");

    let mut env: HashMap<String, String> = std::env::vars().collect();
    env.insert("HOME".into(), home.to_string_lossy().to_string());
    env.insert(
        "CFFIXED_USER_HOME".into(),
        home.to_string_lossy().to_string(),
    );

    let validate_abs = fs::canonicalize(&validate_bin).unwrap_or_else(|_| validate_bin.clone());
    let conformance_abs =
        fs::canonicalize(&conformance_bin).unwrap_or_else(|_| conformance_bin.clone());

    let checks: Vec<(&str, Vec<String>)> = vec![
        (
            "validate",
            vec![
                validate_abs.to_string_lossy().to_string(),
                "validate".into(),
                folder.to_string_lossy().to_string(),
            ],
        ),
        (
            "conformance",
            vec![
                conformance_abs.to_string_lossy().to_string(),
                folder.to_string_lossy().to_string(),
            ],
        ),
    ];

    let mut failed = 0;
    for (name, args) in &checks {
        let done = Command::new(&args[0])
            .args(&args[1..])
            .envs(&env)
            .output()
            .unwrap_or_else(|e| panic!("{}: cannot run: {}", name, e));

        let stdout = String::from_utf8_lossy(&done.stdout);
        let stderr = String::from_utf8_lossy(&done.stderr);
        println!(
            "--- {}: exit {}\n{}{}",
            name,
            done.status.code().unwrap_or(-1),
            stdout,
            stderr
        );

        if !done.status.success() {
            failed += 1;
        }
    }

    if failed > 0 {
        panic!("{} of 2 checks failed", failed);
    }
    println!("the built Nexus Agent tool validates and passes the conformance script");
}

// tempfile is not a dep; provide a minimal fallback
mod tempfile {
    use std::fs;
    use std::path::{Path, PathBuf};

    pub struct TempDir {
        path: PathBuf,
    }

    impl TempDir {
        pub fn new_in(base: &Path) -> std::io::Result<Self> {
            for i in 0..256 {
                let p = base.join(format!(
                    "tmp-{}-{}-{}",
                    std::process::id(),
                    std::time::SystemTime::now()
                        .duration_since(std::time::UNIX_EPOCH)
                        .unwrap_or_default()
                        .as_nanos(),
                    i
                ));
                match fs::create_dir(&p) {
                    Ok(()) => return Ok(Self { path: p }),
                    Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => continue,
                    Err(e) => return Err(e),
                }
            }
            Err(std::io::Error::new(
                std::io::ErrorKind::AlreadyExists,
                "could not create temp dir",
            ))
        }

        pub fn path(&self) -> &Path {
            &self.path
        }
    }

    impl Drop for TempDir {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.path);
        }
    }

    pub fn tempdir_in(base: &Path) -> std::io::Result<TempDir> {
        TempDir::new_in(base)
    }
}
