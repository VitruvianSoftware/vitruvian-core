// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

//! Placing the pinned desktop-commander where the installed `vrelay` can
//! run it, ripgrep included.
//!
//! The package comes from `vrelay`'s Bazel runfiles in pnpm's layout: every
//! package sits once under `.aspect_rules_js/<name>@<version>/node_modules/`,
//! and the packages it needs are relative symlinks beside it. Bazel adds
//! absolute symlinks into its output tree. [`copy_tree`] keeps the relative
//! links (so Node resolves each import as it did under Bazel) and copies
//! through the absolute ones, so the copy stands alone.
//!
//! ripgrep: desktop-commander 0.3.1 imports `@vscode/ripgrep` (1.18.0 in the
//! lock), whose `rgPath` is the `rg` in the optional package for this
//! platform, `@vscode/ripgrep-<platform>-<arch>`. Those packages ship `rg`
//! inside the tarball the lock pins by checksum; no install script downloads
//! it. So the copy carries a pinned `rg`, and [`find_rg`] checks it is there
//! the way Node would look for it.
//!
//! Standard library only: the package test (`src/package_test.rs`, run with
//! the real package) builds this file on its own.

use std::path::{Component, Path, PathBuf};

/// desktop-commander's folder, relative to the `node_modules` folder.
pub const DC_PACKAGE: &str = "@wonderwhy-er/desktop-commander";
/// Its entry point, relative to the package folder.
pub const DC_ENTRY: &str = "dist/index.js";

/// Node's `${process.platform}-${process.arch}` for this build, as
/// `@vscode/ripgrep` names its per-platform packages.
pub fn rg_platform() -> Option<String> {
    rg_platform_for(std::env::consts::OS, std::env::consts::ARCH)
}

pub fn rg_platform_for(os: &str, arch: &str) -> Option<String> {
    let os = match os {
        "macos" => "darwin",
        "linux" => "linux",
        _ => return None,
    };
    let arch = match arch {
        "aarch64" => "arm64",
        "x86_64" => "x64",
        _ => return None,
    };
    Some(format!("{os}-{arch}"))
}

/// How many absolute links one path may pass through (a loop stops here).
const MAX_FOLLOWS: u32 = 40;

/// Copies the folder `src` to `dst` (which must not exist). Relative
/// symlinks stay symlinks, and must point inside `dst`; absolute symlinks
/// are followed and what they point to is copied. Files keep their mode
/// (plus write for the owner, so the copy can be replaced); folders are 0755.
pub fn copy_tree(src: &Path, dst: &Path) -> Result<(), String> {
    if std::fs::symlink_metadata(dst).is_ok() {
        return Err(format!("{} already exists", dst.display()));
    }
    copy_entry(src, dst, dst, 0)
}

fn copy_entry(src: &Path, dst: &Path, root: &Path, follows: u32) -> Result<(), String> {
    use std::os::unix::fs::{DirBuilderExt, PermissionsExt};
    let meta =
        std::fs::symlink_metadata(src).map_err(|e| format!("read {}: {e}", src.display()))?;
    if meta.file_type().is_symlink() {
        let target = std::fs::read_link(src).map_err(|e| format!("read {}: {e}", src.display()))?;
        if target.is_absolute() {
            if follows >= MAX_FOLLOWS {
                return Err(format!("{}: too many links (a loop?)", src.display()));
            }
            return copy_entry(&target, dst, root, follows + 1);
        }
        let base = dst.parent().unwrap_or(root);
        if !lexical_join(base, &target).is_some_and(|p| p.starts_with(root)) {
            return Err(format!(
                "{} points outside the package ({}), so the copy would not stand alone",
                src.display(),
                target.display()
            ));
        }
        return std::os::unix::fs::symlink(&target, dst)
            .map_err(|e| format!("link {}: {e}", dst.display()));
    }
    if meta.is_dir() {
        std::fs::DirBuilder::new()
            .mode(0o755)
            .create(dst)
            .map_err(|e| format!("create {}: {e}", dst.display()))?;
        let mut names: Vec<_> = std::fs::read_dir(src)
            .map_err(|e| format!("read {}: {e}", src.display()))?
            .map(|e| e.map(|e| e.file_name()))
            .collect::<std::io::Result<_>>()
            .map_err(|e| format!("read {}: {e}", src.display()))?;
        names.sort();
        for n in names {
            copy_entry(&src.join(&n), &dst.join(&n), root, follows)?;
        }
        return Ok(());
    }
    if meta.is_file() {
        std::fs::copy(src, dst)
            .map_err(|e| format!("copy {} to {}: {e}", src.display(), dst.display()))?;
        let mode = (meta.permissions().mode() & 0o777) | 0o200;
        return std::fs::set_permissions(dst, std::fs::Permissions::from_mode(mode))
            .map_err(|e| format!("set the mode of {}: {e}", dst.display()));
    }
    Err(format!("{} is not a file, folder or link", src.display()))
}

/// `base` joined with a relative `target`, `..` taken lexically (as the
/// link will be read once copied). `None` if it climbs above the root.
fn lexical_join(base: &Path, target: &Path) -> Option<PathBuf> {
    let mut out = base.to_path_buf();
    for c in target.components() {
        match c {
            Component::CurDir => {}
            Component::ParentDir => {
                if !out.pop() {
                    return None;
                }
            }
            Component::Normal(n) => out.push(n),
            Component::RootDir | Component::Prefix(_) => return None,
        }
    }
    Some(out)
}

/// Node's lookup of a bare `name` imported from a module in `from_dir`:
/// `node_modules/<name>` in each folder up from there (skipping folders
/// that are themselves `node_modules`).
fn node_resolve(from_dir: &Path, name: &str) -> Option<PathBuf> {
    from_dir
        .ancestors()
        .filter(|d| d.file_name().is_none_or(|n| n != "node_modules"))
        .map(|d| d.join("node_modules").join(name))
        .find(|p| p.is_dir())
}

/// The `rg` that desktop-commander in `node_modules` will run on
/// `platform` (see [`rg_platform`]), found as Node finds it: the
/// package's real folder, then `@vscode/ripgrep` from there, then its
/// per-platform package from ripgrep's real `lib/` (its `index.js` resolves
/// `${platformPkg}/bin/rg` from there). An error if any step is missing or
/// `rg` is not an executable file.
pub fn find_rg(node_modules: &Path, platform: &str) -> Result<PathBuf, String> {
    use std::os::unix::fs::PermissionsExt;
    let dc = node_modules.join(DC_PACKAGE);
    let dc_real = std::fs::canonicalize(&dc)
        .map_err(|e| format!("no {DC_PACKAGE} in {}: {e}", node_modules.display()))?;
    let rg_pkg = node_resolve(&dc_real, "@vscode/ripgrep")
        .ok_or_else(|| format!("{DC_PACKAGE} has no @vscode/ripgrep it can import"))?;
    let rg_real =
        std::fs::canonicalize(&rg_pkg).map_err(|e| format!("read {}: {e}", rg_pkg.display()))?;
    let plat = format!("@vscode/ripgrep-{platform}");
    let plat_dir = node_resolve(&rg_real.join("lib"), &plat).ok_or_else(|| {
        format!("@vscode/ripgrep has no {plat} beside it: this platform's rg is missing")
    })?;
    let rg = plat_dir.join("bin/rg");
    let rg = std::fs::canonicalize(&rg).map_err(|e| format!("no {}: {e}", rg.display()))?;
    let meta = std::fs::metadata(&rg).map_err(|e| format!("read {}: {e}", rg.display()))?;
    if !meta.is_file() || meta.permissions().mode() & 0o111 == 0 {
        return Err(format!("{} is not executable", rg.display()));
    }
    Ok(rg)
}

#[cfg(test)]
pub(crate) fn test_dir(name: &str) -> PathBuf {
    let base = std::env::var_os("TEST_TMPDIR")
        .map(PathBuf::from)
        .unwrap_or_else(std::env::temp_dir);
    let dir = base.join(format!("vrelay-install-{}-{name}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

/// A pnpm-shaped `node_modules` with desktop-commander, `@vscode/ripgrep`
/// and its `platform` package holding an `rg` that prints `ripgrep 0.0.0`.
#[cfg(test)]
pub(crate) fn fake_package(nm: &Path, platform: &str) {
    use std::os::unix::fs::{symlink, PermissionsExt};
    let store = nm.join(".aspect_rules_js");
    let dc_real = store.join("@wonderwhy-er+desktop-commander@0.3.1/node_modules");
    let rg_real = store.join("@vscode+ripgrep@1.18.0/node_modules");
    let plat = format!("@vscode/ripgrep-{platform}");
    let plat_real = store.join(format!("@vscode+ripgrep-{platform}@1.18.0/node_modules"));
    std::fs::create_dir_all(dc_real.join(DC_PACKAGE).join("dist")).unwrap();
    std::fs::write(dc_real.join(DC_PACKAGE).join(DC_ENTRY), "// dc\n").unwrap();
    std::fs::create_dir_all(dc_real.join("@vscode")).unwrap();
    symlink(
        "../../../@vscode+ripgrep@1.18.0/node_modules/@vscode/ripgrep",
        dc_real.join("@vscode/ripgrep"),
    )
    .unwrap();
    std::fs::create_dir_all(rg_real.join("@vscode/ripgrep/lib")).unwrap();
    std::fs::write(rg_real.join("@vscode/ripgrep/lib/index.js"), "// rg\n").unwrap();
    symlink(
        format!("../../../@vscode+ripgrep-{platform}@1.18.0/node_modules/{plat}"),
        rg_real.join(&plat),
    )
    .unwrap();
    let bin = plat_real.join(&plat).join("bin");
    std::fs::create_dir_all(&bin).unwrap();
    std::fs::write(bin.join("rg"), "#!/bin/sh\necho 'ripgrep 0.0.0'\n").unwrap();
    std::fs::set_permissions(bin.join("rg"), std::fs::Permissions::from_mode(0o755)).unwrap();
    std::fs::create_dir_all(nm.join("@wonderwhy-er")).unwrap();
    symlink(
        "../.aspect_rules_js/@wonderwhy-er+desktop-commander@0.3.1/node_modules/@wonderwhy-er/desktop-commander",
        nm.join(DC_PACKAGE),
    )
    .unwrap();
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::{symlink, PermissionsExt};

    fn no_absolute_links(dir: &Path) {
        for e in std::fs::read_dir(dir).unwrap() {
            let p = e.unwrap().path();
            let m = std::fs::symlink_metadata(&p).unwrap();
            if m.file_type().is_symlink() {
                let t = std::fs::read_link(&p).unwrap();
                assert!(t.is_relative(), "{} -> {}", p.display(), t.display());
            } else if m.is_dir() {
                no_absolute_links(&p);
            }
        }
    }

    #[test]
    fn rg_platform_names_match_node() {
        assert_eq!(
            rg_platform_for("macos", "aarch64").as_deref(),
            Some("darwin-arm64")
        );
        assert_eq!(
            rg_platform_for("macos", "x86_64").as_deref(),
            Some("darwin-x64")
        );
        assert_eq!(
            rg_platform_for("linux", "x86_64").as_deref(),
            Some("linux-x64")
        );
        assert_eq!(
            rg_platform_for("linux", "aarch64").as_deref(),
            Some("linux-arm64")
        );
        assert_eq!(rg_platform_for("windows", "x86_64"), None);
        assert!(rg_platform().is_some());
    }

    #[test]
    fn copy_keeps_in_tree_links_and_copies_through_absolute_ones() {
        let t = test_dir("copy-links");
        let src = t.join("src");
        let ext = t.join("bazel-out/b");
        std::fs::create_dir_all(src.join(".store/a@1/node_modules/a")).unwrap();
        std::fs::write(src.join(".store/a@1/node_modules/a/index.js"), "a").unwrap();
        symlink(".store/a@1/node_modules/a", src.join("a")).unwrap();
        std::fs::create_dir_all(&ext).unwrap();
        std::fs::write(ext.join("f.txt"), "b").unwrap();
        // A folder in Bazel's output tree, holding an in-tree link of its own.
        symlink("../a", ext.join("up")).unwrap();
        std::fs::create_dir_all(src.join(".store/b@1/node_modules")).unwrap();
        symlink(&ext, src.join(".store/b@1/node_modules/b")).unwrap();
        // A file the same way.
        std::fs::write(t.join("abs-file"), "c").unwrap();
        symlink(t.join("abs-file"), src.join("c.txt")).unwrap();

        let dst = t.join("dst");
        copy_tree(&src, &dst).unwrap();
        assert_eq!(
            std::fs::read_link(dst.join("a")).unwrap(),
            PathBuf::from(".store/a@1/node_modules/a")
        );
        assert_eq!(
            std::fs::read_to_string(dst.join("a/index.js")).unwrap(),
            "a"
        );
        let b = dst.join(".store/b@1/node_modules/b");
        assert!(!std::fs::symlink_metadata(&b)
            .unwrap()
            .file_type()
            .is_symlink());
        assert_eq!(std::fs::read_to_string(b.join("f.txt")).unwrap(), "b");
        assert_eq!(
            std::fs::read_link(b.join("up")).unwrap(),
            PathBuf::from("../a")
        );
        assert_eq!(std::fs::read_to_string(dst.join("c.txt")).unwrap(), "c");
        no_absolute_links(&dst);
    }

    #[test]
    fn copy_refuses_a_link_that_leaves_the_tree() {
        let t = test_dir("copy-escape");
        let src = t.join("src");
        std::fs::create_dir_all(src.join("x")).unwrap();
        symlink("../../outside", src.join("x/out")).unwrap();
        let err = copy_tree(&src, &t.join("dst")).unwrap_err();
        assert!(err.contains("outside"), "{err}");
    }

    #[test]
    fn copy_refuses_an_existing_destination() {
        let t = test_dir("copy-exists");
        std::fs::create_dir_all(t.join("src")).unwrap();
        std::fs::create_dir_all(t.join("dst")).unwrap();
        assert!(copy_tree(&t.join("src"), &t.join("dst")).is_err());
    }

    #[test]
    fn copy_keeps_the_executable_bit() {
        let t = test_dir("copy-mode");
        let src = t.join("src");
        std::fs::create_dir_all(&src).unwrap();
        std::fs::write(src.join("rg"), "x").unwrap();
        std::fs::set_permissions(src.join("rg"), std::fs::Permissions::from_mode(0o755)).unwrap();
        copy_tree(&src, &t.join("dst")).unwrap();
        let mode = std::fs::metadata(t.join("dst/rg"))
            .unwrap()
            .permissions()
            .mode();
        assert_eq!(mode & 0o111, 0o111);
    }

    #[test]
    fn rg_is_found_in_the_copy_the_way_node_resolves_it() {
        let t = test_dir("rg-found");
        let plat = rg_platform().unwrap();
        fake_package(&t.join("src"), &plat);
        let dst = t.join("dst");
        copy_tree(&t.join("src"), &dst).unwrap();
        let rg = find_rg(&dst, &plat).unwrap();
        let real_dst = std::fs::canonicalize(&dst).unwrap();
        assert!(rg.starts_with(&real_dst), "{}", rg.display());
        assert!(
            rg.ends_with(format!("@vscode/ripgrep-{plat}/bin/rg")),
            "{}",
            rg.display()
        );
        let out = std::process::Command::new(&rg)
            .arg("--version")
            .output()
            .unwrap();
        assert!(String::from_utf8_lossy(&out.stdout).starts_with("ripgrep"));
    }

    #[test]
    fn a_missing_or_unrunnable_rg_names_the_platform() {
        let t = test_dir("rg-missing");
        let nm = t.join("nm");
        fake_package(&nm, "darwin-arm64");
        // The other platform's package is not there.
        let err = find_rg(&nm, "darwin-x64").unwrap_err();
        assert!(err.contains("@vscode/ripgrep-darwin-x64"), "{err}");
        let rg = find_rg(&nm, "darwin-arm64").unwrap();
        std::fs::set_permissions(&rg, std::fs::Permissions::from_mode(0o644)).unwrap();
        let err = find_rg(&nm, "darwin-arm64").unwrap_err();
        assert!(err.contains("not executable"), "{err}");
        // No desktop-commander at all.
        let err = find_rg(&t.join("empty"), "darwin-arm64").unwrap_err();
        assert!(err.contains(DC_PACKAGE), "{err}");
    }
}
