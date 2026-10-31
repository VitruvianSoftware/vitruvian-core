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

//! `migrate_deploy_bin`: hermetic `prisma migrate deploy` with the
//! expand/contract phase guard (issue #819). The logic lives in
//! `tabula_api_tools_rs_lib::run_migrate_deploy`; this binary only finds the
//! Prisma CLI in its Bazel runfiles and hands over the process environment.
//!
//! The Prisma CLI is `//apps/suites/tabula/api:prisma_cli`, a `js_binary` on the
//! hermetic Node toolchain, so nothing is fetched at run time (no `npx`).
//! `PRISMA_SCHEMA_ENGINE_BINARY` / `PRISMA_QUERY_ENGINE_LIBRARY` are made
//! absolute against the working directory, because the CLI resolves them
//! against its own.

use std::collections::BTreeMap;
use std::path::PathBuf;

use tabula_api_tools_rs_lib::run_migrate_deploy;

/// Runfiles path of the Prisma CLI launcher, baked in at build time.
const PRISMA_CLI_RLOCATION: &str = env!("PRISMA_CLI_RLOCATION");

/// The runfiles directory of this binary: `RUNFILES_DIR` / `TEST_SRCDIR` when
/// the caller exported one (itest tasks, tests), else `<exe>.runfiles` next to
/// the executable (`bazel run`, or a direct `bazel-bin/...` invocation).
fn runfiles_dir() -> Option<PathBuf> {
    for var in ["RUNFILES_DIR", "TEST_SRCDIR"] {
        if let Some(dir) = std::env::var_os(var).map(PathBuf::from) {
            if dir.is_dir() {
                return Some(dir);
            }
        }
    }
    let exe = std::env::current_exe().ok()?;
    let mut sibling = exe.clone().into_os_string();
    sibling.push(".runfiles");
    let sibling = PathBuf::from(sibling);
    if sibling.is_dir() {
        return Some(sibling);
    }
    // Invoked from inside another binary's runfiles tree.
    let s = exe.to_str()?;
    let idx = s.find(".runfiles/")?;
    Some(PathBuf::from(&s[..idx + ".runfiles".len()]))
}

/// Locate the Prisma CLI launcher inside the runfiles TREE (not through the
/// manifest). It is a `js_binary` launcher, which finds its own runfiles from
/// the path it was started by (`*.runfiles/...`) and refuses to start
/// otherwise; a manifest lookup would hand back the bare `bazel-out` file.
fn prisma_cli() -> Result<PathBuf, String> {
    let dir = runfiles_dir()
        .ok_or_else(|| "migrate-deploy: cannot locate this binary's Bazel runfiles".to_string())?;
    let path = dir.join(PRISMA_CLI_RLOCATION);
    if !path.exists() {
        return Err(format!(
            "migrate-deploy: the Prisma CLI is missing at {}",
            path.display()
        ));
    }
    Ok(path)
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let cli = match prisma_cli() {
        Ok(p) => p,
        Err(msg) => {
            eprintln!("{msg}");
            std::process::exit(1);
        }
    };
    let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
    let ambient: BTreeMap<String, String> = std::env::vars().collect();
    std::process::exit(run_migrate_deploy(&args, &ambient, &cwd, &cli));
}
