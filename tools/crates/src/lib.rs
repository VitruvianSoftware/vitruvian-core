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

//! Re-lock the root Cargo.lock so it only holds crates the Bazel Rust toolchain
//! can build.
//!
//! Cargo picks crate versions by the `rust-version` of the workspace members
//! (MSRV-aware resolution, `incompatible-rust-versions = fallback`). That only
//! means "buildable by Bazel" if every member declares the toolchain's version,
//! so this checks that first and refuses otherwise: a member without one lets
//! cargo fall back to whatever rustc is on PATH.

use std::path::{Path, PathBuf};
use std::process::Command;

/// The version in `rust.toolchain(... versions = ["X"] ...)` in MODULE.bazel.
pub fn toolchain_version(module_bazel: &str) -> Option<String> {
    let block = &module_bazel[module_bazel.find("rust.toolchain(")?..];
    let block = &block[..block.find(')')?];
    let versions = &block[block.find("versions")?..];
    first_quoted(versions)
}

/// The paths in the root Cargo.toml's `[workspace] members = [...]`.
pub fn workspace_members(root_cargo_toml: &str) -> Vec<String> {
    let uncommented: String = root_cargo_toml
        .lines()
        .map(|line| line.split('#').next().unwrap_or(""))
        .collect::<Vec<_>>()
        .join("\n");
    let Some(start) = uncommented
        .lines()
        .scan(0, |offset, line| {
            let here = *offset;
            *offset += line.len() + 1;
            Some((here, line))
        })
        .find(|(_, line)| line.trim_start().starts_with("members"))
        .map(|(offset, _)| offset)
    else {
        return Vec::new();
    };
    let rest = &uncommented[start..];
    let (Some(open), Some(close)) = (rest.find('['), rest.find(']')) else {
        return Vec::new();
    };
    rest[open + 1..close]
        .split('"')
        .skip(1)
        .step_by(2)
        .map(str::to_string)
        .collect()
}

/// A member's `rust-version`, read from its `[package]` table.
pub fn package_rust_version(cargo_toml: &str) -> Option<String> {
    let mut in_package = false;
    for line in cargo_toml.lines() {
        let line = line.trim();
        if line.starts_with('[') {
            in_package = line == "[package]";
        } else if in_package && line.starts_with("rust-version") {
            return first_quoted(line);
        }
    }
    None
}

/// Whether a declared `rust-version` names the toolchain's minor release:
/// "1.75" and "1.75.0" both match toolchain "1.75.0".
pub fn same_minor(declared: &str, toolchain: &str) -> bool {
    let minor = |v: &str| v.split('.').take(2).collect::<Vec<_>>().join(".");
    !declared.is_empty() && minor(declared) == minor(toolchain)
}

fn first_quoted(s: &str) -> Option<String> {
    let start = s.find('"')? + 1;
    let end = start + s[start..].find('"')?;
    Some(s[start..end].to_string())
}

/// Every member whose `rust-version` is missing or names another release.
pub fn msrv_problems(workspace: &Path, toolchain: &str) -> Result<Vec<String>, String> {
    let root = read(&workspace.join("Cargo.toml"))?;
    let mut members = workspace_members(&root);
    if members.is_empty() {
        // A single package that is its own workspace (an app with its own
        // lock, like apps/mcp/slack/rs): the root manifest is the member.
        if !root.lines().any(|line| line.trim() == "[package]") {
            return Err("no [workspace] members and no [package] in Cargo.toml".into());
        }
        members.push(".".into());
    }
    let mut problems = Vec::new();
    for member in members {
        let manifest = read(&workspace.join(&member).join("Cargo.toml"))?;
        match package_rust_version(&manifest) {
            Some(v) if same_minor(&v, toolchain) => {}
            Some(v) => problems.push(format!("{member}: rust-version = \"{v}\"")),
            None => problems.push(format!("{member}: no rust-version")),
        }
    }
    Ok(problems)
}

/// Takes a leading `--dir <path>` off the arguments. The path must stay inside
/// the repository, so it is relative and has no `..`.
pub fn split_dir_arg(args: &[String]) -> Result<(Option<PathBuf>, Vec<String>), String> {
    if args.first().map(String::as_str) != Some("--dir") {
        return Ok((None, args.to_vec()));
    }
    let dir = args.get(1).ok_or("--dir needs a path")?;
    let path = Path::new(dir);
    if path.is_absolute()
        || path
            .components()
            .any(|c| matches!(c, std::path::Component::ParentDir))
    {
        return Err(format!(
            "--dir must be a path inside the repository, got {dir}"
        ));
    }
    Ok((Some(path.to_path_buf()), args[2..].to_vec()))
}

fn read(path: &Path) -> Result<String, String> {
    std::fs::read_to_string(path).map_err(|e| format!("cannot read {}: {e}", path.display()))
}

const USAGE: &str = "\
usage: bazel run //tools/crates:lock -- [--dir <path>] [--check | <cargo update args>]

  (no args)   add what Cargo.toml now asks for; leave every other locked version alone
  --dir P     lock the Cargo workspace at P (repo-relative) instead of the root one,
              for an app that keeps its own Cargo.lock (e.g. apps/mcp/slack/rs)
  --check     fail if Cargo.lock does not match Cargo.toml (changes nothing)
  <args>      passed to `cargo update`, e.g. `-p ring` or `--verbose`
";

pub fn run(args: &[String]) -> i32 {
    if args.iter().any(|a| a == "-h" || a == "--help") {
        print!("{USAGE}");
        return 0;
    }
    match try_run(args) {
        Ok(code) => code,
        Err(message) => {
            eprintln!("crates:lock: {message}");
            1
        }
    }
}

fn try_run(args: &[String]) -> Result<i32, String> {
    let workspace = std::env::var_os("BUILD_WORKSPACE_DIRECTORY")
        .map(PathBuf::from)
        .ok_or("run this with `bazel run //tools/crates:lock`")?;
    // A runfiles-relative path; resolve it before leaving the runfiles tree.
    let cargo = std::env::var_os("RELOCK_CARGO").ok_or("RELOCK_CARGO is not set")?;
    let cargo = std::fs::canonicalize(&cargo)
        .map_err(|e| format!("cargo not found at {}: {e}", Path::new(&cargo).display()))?;

    let toolchain = toolchain_version(&read(&workspace.join("MODULE.bazel"))?)
        .ok_or("no rust.toolchain(versions = [...]) in MODULE.bazel")?;
    let (dir, args) = split_dir_arg(args)?;
    let workspace = match dir {
        Some(dir) => workspace.join(dir),
        None => workspace,
    };
    let problems = msrv_problems(&workspace, &toolchain)?;
    if !problems.is_empty() {
        eprintln!(
            "crates:lock: Bazel builds Rust with {toolchain}, so every workspace member must"
        );
        eprintln!("declare rust-version = \"{toolchain}\" in [package]. Without it cargo can lock");
        eprintln!("crates that toolchain cannot build. Fix these, then run this again:");
        for p in &problems {
            eprintln!("  {p}");
        }
        return Ok(1);
    }

    let mut cmd = Command::new(&cargo);
    cmd.current_dir(&workspace)
        .env("CARGO_RESOLVER_INCOMPATIBLE_RUST_VERSIONS", "fallback");
    let args = args.as_slice();
    let check = args.first().map(String::as_str) == Some("--check");
    if check {
        if args.len() > 1 {
            return Err("--check takes no other arguments".into());
        }
        cmd.args(["metadata", "--format-version", "1", "--locked"])
            .stdout(std::process::Stdio::null());
    } else if args.is_empty() {
        cmd.args(["update", "--workspace"]);
    } else {
        cmd.arg("update").args(args);
    }

    let status = cmd
        .status()
        .map_err(|e| format!("cannot run {}: {e}", cargo.display()))?;
    if !status.success() {
        if check {
            eprintln!(
                "crates:lock: Cargo.lock is out of date. Run `bazel run //tools/crates:lock`."
            );
        }
        return Ok(status.code().unwrap_or(1));
    }
    if check {
        println!("crates:lock: Cargo.lock matches Cargo.toml (resolved for Rust {toolchain}).");
    } else {
        println!("crates:lock: Cargo.lock resolved for Rust {toolchain}.");
        println!("  next: bazel build the targets that use @crates to prove they build");
    }
    Ok(0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_the_toolchain_version() {
        let module = r#"
rust = use_extension("@rules_rust//rust:extensions.bzl", "rust")
rust.toolchain(
    edition = "2021",
    versions = ["1.75.0"],
)
rust.repository_set(versions = ["1.98.1"])
"#;
        assert_eq!(toolchain_version(module).as_deref(), Some("1.75.0"));
        assert_eq!(toolchain_version("bazel_dep(name = \"x\")"), None);
    }

    #[test]
    fn reads_workspace_members_and_skips_comments() {
        let root = r#"
[workspace]
resolver = "2"
# members = ["old/thing"]
members = [
    "apps/mcp/slack/rs",
    # "commented/out",
    "packages/kit",  # trailing note
]
"#;
        assert_eq!(
            workspace_members(root),
            vec!["apps/mcp/slack/rs".to_string(), "packages/kit".to_string()]
        );
        assert!(workspace_members("[workspace]\n").is_empty());
    }

    #[test]
    fn reads_rust_version_only_from_package() {
        let manifest = r#"
[package]
name = "x"
rust-version = "1.75"

[dependencies]
rust-version = "not this"
"#;
        assert_eq!(package_rust_version(manifest).as_deref(), Some("1.75"));
        assert_eq!(
            package_rust_version("[dependencies]\nrust-version = \"1.75\"\n"),
            None
        );
    }

    #[test]
    fn splits_a_leading_dir_argument() {
        let args = |v: &[&str]| v.iter().map(|s| s.to_string()).collect::<Vec<_>>();
        assert_eq!(
            split_dir_arg(&args(&["--dir", "apps/mcp/slack/rs", "--check"])).unwrap(),
            (Some(PathBuf::from("apps/mcp/slack/rs")), args(&["--check"]))
        );
        assert_eq!(
            split_dir_arg(&args(&["-p", "ring"])).unwrap(),
            (None, args(&["-p", "ring"]))
        );
        assert!(split_dir_arg(&args(&["--dir"])).is_err());
        assert!(split_dir_arg(&args(&["--dir", "/etc"])).is_err());
        assert!(split_dir_arg(&args(&["--dir", "apps/../../x"])).is_err());
    }

    #[test]
    fn a_package_that_is_its_own_workspace_is_checked_itself() {
        let dir = std::env::temp_dir().join(format!("crates-lock-solo-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(
            dir.join("Cargo.toml"),
            "[workspace]\n\n[package]\nname = \"solo\"\nrust-version = \"1.70\"\n",
        )
        .unwrap();
        let problems = msrv_problems(&dir, "1.75.0").unwrap();
        let _ = std::fs::remove_dir_all(&dir);
        assert_eq!(problems, vec![".: rust-version = \"1.70\"".to_string()]);
    }

    #[test]
    fn matches_on_minor_release() {
        assert!(same_minor("1.75", "1.75.0"));
        assert!(same_minor("1.75.0", "1.75.0"));
        assert!(!same_minor("1.76", "1.75.0"));
        assert!(!same_minor("1.7", "1.75.0"));
        assert!(!same_minor("", "1.75.0"));
    }

    #[test]
    fn reports_members_without_a_matching_rust_version() {
        let dir = std::env::temp_dir().join(format!("crates-lock-test-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        for (path, body) in [
            (
                "Cargo.toml",
                "[workspace]\nmembers = [\"a\", \"b\", \"c\"]\n",
            ),
            (
                "a/Cargo.toml",
                "[package]\nname = \"a\"\nrust-version = \"1.75\"\n",
            ),
            ("b/Cargo.toml", "[package]\nname = \"b\"\n"),
            (
                "c/Cargo.toml",
                "[package]\nname = \"c\"\nrust-version = \"1.80\"\n",
            ),
        ] {
            let p = dir.join(path);
            std::fs::create_dir_all(p.parent().unwrap()).unwrap();
            std::fs::write(p, body).unwrap();
        }
        let problems = msrv_problems(&dir, "1.75.0").unwrap();
        let _ = std::fs::remove_dir_all(&dir);
        assert_eq!(
            problems,
            vec![
                "b: no rust-version".to_string(),
                "c: rust-version = \"1.80\"".to_string()
            ]
        );
    }
}
