// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

//! Runs the compiled `Tools/MakeIcon.swift` for a Bazel genrule.
//!
//! `MakeIcon` finds its masters at `<dir of argv[0]>/../Resources/Brand` and writes
//! `AppIcon.icns`, `MenuBarIcon.png`, `MenuBarIcon@2x.png` and `BrandMark.png` next to
//! the iconset directory it is given. Stage that layout in a scratch directory,
//! then copy the four products to the declared outputs.

use std::env;
use std::fs;
use std::path::PathBuf;
use std::process::Command;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

pub const PRODUCTS: &[&str] = &[
    "AppIcon.icns",
    "MenuBarIcon.png",
    "MenuBarIcon@2x.png",
    "BrandMark.png",
];

static SCRATCH_COUNTER: AtomicU64 = AtomicU64::new(0);

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Config {
    pub tool: PathBuf,
    pub brand: PathBuf,
    pub out_dir: PathBuf,
}

pub fn parse_args(args: &[String]) -> Result<Config, String> {
    if args.len() != 3 || args.iter().any(|a| a == "-h" || a == "--help") {
        return Err(
            "usage: make_icons <MakeIcon binary> <Resources/Brand dir> <out dir of the 4 outputs>"
                .into(),
        );
    }
    Ok(Config {
        tool: PathBuf::from(&args[0]),
        brand: PathBuf::from(&args[1]),
        out_dir: PathBuf::from(&args[2]),
    })
}

fn make_scratch_dir() -> Result<PathBuf, String> {
    let base = env::var("TEST_TMPDIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| env::temp_dir());
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    let seq = SCRATCH_COUNTER.fetch_add(1, Ordering::Relaxed);
    let scratch = base.join(format!(
        "make_icons_{}_{}_{}",
        std::process::id(),
        nanos,
        seq
    ));
    fs::create_dir_all(&scratch).map_err(|e| format!("create scratch dir: {}", e))?;
    Ok(scratch)
}

pub fn run(config: &Config) -> Result<(), String> {
    let scratch = make_scratch_dir()?;
    let result = (|| -> Result<(), String> {
        let tools_dir = scratch.join("Tools");
        let resources_dir = scratch.join("Resources");
        let build_dir = scratch.join("build");
        fs::create_dir_all(&tools_dir).map_err(|e| format!("mkdir Tools: {}", e))?;
        fs::create_dir_all(&resources_dir).map_err(|e| format!("mkdir Resources: {}", e))?;
        fs::create_dir_all(&build_dir).map_err(|e| format!("mkdir build: {}", e))?;

        let staged_tool = tools_dir.join("MakeIcon");
        fs::copy(&config.tool, &staged_tool)
            .map_err(|e| format!("copy {}: {}", config.tool.display(), e))?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            if let Ok(meta) = fs::metadata(&staged_tool) {
                let mut perms = meta.permissions();
                perms.set_mode(perms.mode() | 0o755);
                let _ = fs::set_permissions(&staged_tool, perms);
            }
        }

        let abs_brand = if config.brand.is_absolute() {
            config.brand.clone()
        } else {
            env::current_dir()
                .map_err(|e| format!("current_dir: {}", e))?
                .join(&config.brand)
        };
        #[cfg(unix)]
        std::os::unix::fs::symlink(&abs_brand, resources_dir.join("Brand"))
            .map_err(|e| format!("symlink Brand: {}", e))?;

        let iconset = build_dir.join("AppIcon.iconset");
        let status = Command::new(&staged_tool)
            .arg(&iconset)
            .status()
            .map_err(|e| format!("spawn {}: {}", staged_tool.display(), e))?;
        if !status.success() {
            return Err(format!(
                "MakeIcon exited with status {}",
                status.code().unwrap_or(1)
            ));
        }

        fs::create_dir_all(&config.out_dir)
            .map_err(|e| format!("mkdir {}: {}", config.out_dir.display(), e))?;
        for product in PRODUCTS {
            let src = build_dir.join(product);
            let dst = config.out_dir.join(product);
            fs::copy(&src, &dst)
                .map_err(|e| format!("copy {} -> {}: {}", src.display(), dst.display(), e))?;
        }
        Ok(())
    })();

    let _ = fs::remove_dir_all(&scratch);
    result
}

pub fn run_cli(args: &[String]) -> i32 {
    let config = match parse_args(args) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("{}", e);
            return 2;
        }
    };
    match run(&config) {
        Ok(()) => 0,
        Err(e) => {
            eprintln!("{}", e);
            1
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_make_icons_stages_layout_and_copies_four_products() {
        let tmp = env::temp_dir().join(format!("test_make_icons_{}", std::process::id()));
        let _ = fs::remove_dir_all(&tmp);
        fs::create_dir_all(&tmp).unwrap();

        let brand_dir = tmp.join("Resources/Brand");
        fs::create_dir_all(&brand_dir).unwrap();
        fs::write(brand_dir.join("logo.png"), b"logo").unwrap();

        let fake_tool = tmp.join("fake_make_icon.sh");
        let script = "\
#!/bin/sh
set -eu
tool_dir=\"$(dirname \"$0\")\"
test -f \"$tool_dir/../Resources/Brand/logo.png\"
build_dir=\"$(dirname \"$1\")\"
for p in AppIcon.icns MenuBarIcon.png MenuBarIcon@2x.png BrandMark.png; do
    echo \"generated:$p\" > \"$build_dir/$p\"
done
";
        fs::write(&fake_tool, script).unwrap();
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mut perms = fs::metadata(&fake_tool).unwrap().permissions();
            perms.set_mode(0o755);
            fs::set_permissions(&fake_tool, perms).unwrap();
        }

        let out_dir = tmp.join("out/icons");
        let rc = run_cli(&[
            fake_tool.to_string_lossy().to_string(),
            brand_dir.to_string_lossy().to_string(),
            out_dir.to_string_lossy().to_string(),
        ]);
        assert_eq!(rc, 0);

        for product in PRODUCTS {
            let content = fs::read_to_string(out_dir.join(product)).unwrap();
            assert_eq!(content.trim(), format!("generated:{}", product));
        }

        let _ = fs::remove_dir_all(&tmp);
    }
}
