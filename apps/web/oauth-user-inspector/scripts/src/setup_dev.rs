// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT
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

//! Rust port of `apps/web/oauth-user-inspector/scripts/setup-dev.sh`.

use std::env;
use std::fs;
use std::path::{Path, PathBuf};

pub const PRE_COMMIT_HOOK_SCRIPT: &str =
    "#!/usr/bin/env bash\nexec bazel run //apps/web/oauth-user-inspector:check-sensitive-rs\n";

pub fn install_pre_commit_hook(repo_root: &Path) -> Result<PathBuf, String> {
    let hooks_dir = repo_root.join(".git/hooks");
    fs::create_dir_all(&hooks_dir)
        .map_err(|e| format!("failed to create {}: {e}", hooks_dir.display()))?;
    let hook_path = hooks_dir.join("pre-commit");
    fs::write(&hook_path, PRE_COMMIT_HOOK_SCRIPT)
        .map_err(|e| format!("failed to write {}: {e}", hook_path.display()))?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(&hook_path, fs::Permissions::from_mode(0o755))
            .map_err(|e| format!("failed to chmod {}: {e}", hook_path.display()))?;
    }
    Ok(hook_path)
}

pub fn run(_args: &[String]) -> i32 {
    let root = env::var("BUILD_WORKSPACE_DIRECTORY")
        .ok()
        .filter(|s| !s.is_empty())
        .map(PathBuf::from)
        .or_else(|| env::current_dir().ok())
        .unwrap_or_else(|| PathBuf::from("."));

    match install_pre_commit_hook(&root) {
        Ok(_) => {
            println!("Pre-commit hook installed -> .git/hooks/pre-commit");
            0
        }
        Err(e) => {
            eprintln!("{e}");
            1
        }
    }
}
