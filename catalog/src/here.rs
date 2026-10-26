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

//! Where the scripts' `Path(__file__).resolve().parent` is: the catalog
//! folder. Under `bazel run` or `bazel test` the files come from the
//! binary's runfiles, whose links lead back to the source tree, so this is
//! the folder they resolve to, as `resolve()` follows the same links.

use std::path::{Path, PathBuf};

fn runfiles_dirs() -> Vec<PathBuf> {
    let mut dirs = Vec::new();
    if let Ok(d) = std::env::var("RUNFILES_DIR") {
        dirs.push(PathBuf::from(d));
    }
    if let Ok(exe) = std::env::current_exe() {
        let mut runfiles = exe.clone().into_os_string();
        runfiles.push(".runfiles");
        dirs.push(PathBuf::from(runfiles));
        // A binary run from inside another target's runfiles.
        for a in exe.ancestors() {
            if a.extension().map_or(false, |e| e == "runfiles") {
                dirs.push(a.to_path_buf());
            }
        }
    }
    dirs
}

/// The catalog folder: the one holding tools.json beside this program's
/// data, resolved through its links.
pub fn catalog_dir() -> PathBuf {
    for dir in runfiles_dirs() {
        let candidate = dir.join("_main/catalog/tools.json");
        if candidate.exists() {
            if let Ok(real) = candidate.canonicalize() {
                return real.parent().unwrap().to_path_buf();
            }
            return dir.join("_main/catalog");
        }
    }
    // Not under Bazel: the catalog folder of the checkout we run in.
    let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
    for a in cwd.ancestors() {
        if a.join("catalog/tools.json").exists() {
            return a.join("catalog");
        }
        if a.file_name().map_or(false, |n| n == "catalog") && a.join("tools.json").exists() {
            return a.to_path_buf();
        }
    }
    cwd.join("catalog")
}

/// `path` as Python's `Path(given) if absolute or not workspace else
/// Path(workspace) / given` reads it under BUILD_WORKSPACE_DIRECTORY.
pub fn under_workspace(path: &Path) -> PathBuf {
    match std::env::var("BUILD_WORKSPACE_DIRECTORY") {
        Ok(w) if !w.is_empty() && !path.is_absolute() => Path::new(&w).join(path),
        _ => path.to_path_buf(),
    }
}

/// A folder of our own under the system's temporary folder, removed when
/// dropped: `tempfile.TemporaryDirectory()`.
pub struct TempDir(PathBuf);

impl TempDir {
    pub fn new() -> std::io::Result<TempDir> {
        use std::sync::atomic::{AtomicU32, Ordering};
        static COUNT: AtomicU32 = AtomicU32::new(0);
        let base = std::env::temp_dir();
        loop {
            let nanos = std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|d| d.subsec_nanos())
                .unwrap_or(0);
            let name = format!(
                "tmp{}{:x}{:x}",
                std::process::id(),
                nanos,
                COUNT.fetch_add(1, Ordering::Relaxed)
            );
            let path = base.join(name);
            match std::fs::create_dir(&path) {
                Ok(()) => return Ok(TempDir(path)),
                Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => continue,
                Err(e) => return Err(e),
            }
        }
    }

    pub fn path(&self) -> &Path {
        &self.0
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}
