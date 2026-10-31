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

//! Rust port of `apps/mobile/android-remote/macmenu/scripts/zip-tool.sh`.
//!
//! The Vitruvian Remote extension for the Vitruvian app, as the app installs it
//! from the catalog: a zip of the extension's folder with `vitruvian-tool.json`
//! at the top, `bin/tool`, and `bin/vitruvian-remote-agent`, no folder of its
//! own, no links. Named `VitruvianRemote-<version>-tool.zip`.
//!
//! ```text
//! zip-tool <remote-tool binary> <vitruvian-remote-agent binary> <version> <dist dir>
//! ```
//!
//! With `REMOTE_TOOL_REQUIRE_UNIVERSAL=1` both programs must hold Apple silicon
//! and Intel code. With `REMOTE_TOOL_MAX_MINOS=X.Y` every architecture of every
//! program must say, in its `LC_BUILD_VERSION`, that it runs on macOS X.Y or
//! older. The version must be the one `tool/vitruvian-tool.json` says.
//!
//! Prints the zip's size and SHA-256, which a catalog entry pins.

use std::env;
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::Command;

pub const PKG: &str = "apps/mobile/android-remote/macmenu";

/// Everything the packaging needs. `lipo`/`vtool` name the programs to run so a
/// test can stand in for them.
pub struct Options {
    pub tool: PathBuf,
    pub agent: PathBuf,
    pub version: String,
    pub dist: PathBuf,
    pub manifest: PathBuf,
    pub require_universal: bool,
    pub max_minos: Option<String>,
    pub lipo: String,
    pub vtool: String,
}

/// The version the manifest says: the first `"version": "<v>"` line, as the
/// script's `sed -n ... | head -1` found it.
pub fn manifest_version(content: &str) -> Option<String> {
    for line in content.lines() {
        if let Some(pos) = line.find("\"version\":") {
            let rest = line[pos + "\"version\":".len()..].trim_start_matches(' ');
            if let Some(inner) = rest.strip_prefix('"') {
                if let Some(end) = inner.find('"') {
                    return Some(inner[..end].to_string());
                }
            }
        }
    }
    None
}

/// The oldest macOS each architecture of a program runs on, one
/// `(arch, minos)` per slice, from `vtool -show-build`. A slice with no
/// `LC_BUILD_VERSION` gives `(arch, "none")`.
pub fn minos_per_arch(vtool_output: &str) -> Vec<(String, String)> {
    let mut out = Vec::new();
    let mut arch = String::new();
    let mut minos = String::new();
    let mut seen_thin = false;
    let flush = |arch: &str, minos: &str, out: &mut Vec<(String, String)>| {
        if !arch.is_empty() {
            let m = if minos.is_empty() { "none" } else { minos };
            out.push((arch.to_string(), m.to_string()));
        }
    };
    for raw in vtool_output.lines() {
        let line = raw.trim_end_matches('\r');
        if let Some(pos) = line.find(" (architecture ") {
            if line.ends_with("):") {
                flush(&arch, &minos, &mut out);
                arch = line[pos + " (architecture ".len()..line.len() - 2].to_string();
                minos.clear();
                continue;
            }
        }
        if line.ends_with(':') && arch.is_empty() && !seen_thin {
            arch = "thin".to_string();
            seen_thin = true;
            continue;
        }
        let mut fields = line.split_whitespace();
        if fields.next() == Some("minos") {
            if let Some(v) = fields.next() {
                minos = v.to_string();
            }
        }
    }
    flush(&arch, &minos, &mut out);
    out
}

/// Whether version `a` is newer than `b`, comparing X.Y.Z numerically.
pub fn newer_than(a: &str, b: &str) -> bool {
    let num = |s: &str| -> Vec<u64> {
        s.split('.')
            .map(|p| {
                let digits: String = p.chars().take_while(|c| c.is_ascii_digit()).collect();
                digits.parse().unwrap_or(0)
            })
            .collect()
    };
    let (x, y) = (num(a), num(b));
    for i in 0..x.len().max(y.len()) {
        let (xi, yi) = (*x.get(i).unwrap_or(&0), *y.get(i).unwrap_or(&0));
        if xi > yi {
            return true;
        }
        if xi < yi {
            return false;
        }
    }
    false
}

fn archs_of(lipo: &str, binary: &Path) -> Result<String, String> {
    let out = Command::new(lipo)
        .arg("-archs")
        .arg(binary)
        .output()
        .map_err(|e| format!("failed to run {lipo}: {e}"))?;
    if !out.status.success() {
        return Err(format!("{lipo} -archs failed for {}", binary.display()));
    }
    Ok(String::from_utf8_lossy(&out.stdout).trim().to_string())
}

fn sha256_of(path: &Path) -> Result<String, String> {
    for (prog, args) in [("shasum", vec!["-a", "256"]), ("sha256sum", vec![])] {
        if let Ok(out) = Command::new(prog).args(&args).arg(path).output() {
            if out.status.success() {
                if let Some(h) = String::from_utf8_lossy(&out.stdout)
                    .split_whitespace()
                    .next()
                {
                    return Ok(h.to_string());
                }
            }
        }
    }
    Err("could not compute SHA-256 (no shasum or sha256sum)".to_string())
}

/// Checks the programs, stages the extension's folder, and zips it into
/// `dist`. Returns the zip's path.
pub fn package(opts: &Options) -> Result<PathBuf, String> {
    let programs = [&opts.tool, &opts.agent];

    if opts.require_universal {
        for binary in programs {
            let archs = archs_of(&opts.lipo, binary)?;
            if !(archs.contains("arm64") && archs.contains("x86_64")) {
                return Err(format!(
                    "expected a universal binary, {} is: {archs}",
                    binary.display()
                ));
            }
        }
    }

    if let Some(max) = opts.max_minos.as_deref().filter(|m| !m.is_empty()) {
        for binary in programs {
            let out = Command::new(&opts.vtool)
                .arg("-show-build")
                .arg(binary)
                .output()
                .map_err(|e| format!("failed to run {}: {e}", opts.vtool))?;
            let slices = minos_per_arch(&String::from_utf8_lossy(&out.stdout));
            if slices.is_empty() {
                return Err(format!(
                    "vtool found no architecture in {}",
                    binary.display()
                ));
            }
            for (arch, minos) in slices {
                if minos == "none" || newer_than(&minos, max) {
                    return Err(format!(
                        "{} ({arch}) needs macOS {minos}; the extension supports macOS {max}",
                        binary.display()
                    ));
                }
            }
        }
    }

    let manifest_text = fs::read_to_string(&opts.manifest)
        .map_err(|e| format!("failed to read {}: {e}", opts.manifest.display()))?;
    let said = manifest_version(&manifest_text).unwrap_or_default();
    if said != opts.version {
        return Err(format!(
            "tool/vitruvian-tool.json says {said}, the release is {}",
            opts.version
        ));
    }

    let stage = env::temp_dir().join(format!(
        "ar-zip-tool-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos()
    ));
    let result = stage_and_zip(opts, &stage);
    let _ = fs::remove_dir_all(&stage);
    result
}

fn stage_and_zip(opts: &Options, stage: &Path) -> Result<PathBuf, String> {
    let folder = stage.join("remote");
    let bin = folder.join("bin");
    fs::create_dir_all(&bin).map_err(|e| format!("failed to stage: {e}"))?;
    // fs::copy follows links, so what lands in the folder is a plain file even
    // when Bazel's output is one.
    let copy = |from: &Path, to: &Path, mode: u32| -> Result<(), String> {
        fs::copy(from, to).map_err(|e| format!("failed to copy {}: {e}", from.display()))?;
        fs::set_permissions(to, fs::Permissions::from_mode(mode))
            .map_err(|e| format!("failed to chmod {}: {e}", to.display()))
    };
    copy(&opts.manifest, &folder.join("vitruvian-tool.json"), 0o644)?;
    copy(&opts.tool, &bin.join("tool"), 0o755)?;
    copy(&opts.agent, &bin.join("vitruvian-remote-agent"), 0o755)?;

    // The zip is made from inside the staging folder, so the dist folder is
    // made whole first: `./dist` would otherwise name a folder in the staging one.
    fs::create_dir_all(&opts.dist).map_err(|e| format!("failed to create dist: {e}"))?;
    let dist = fs::canonicalize(&opts.dist).map_err(|e| format!("bad dist dir: {e}"))?;
    let asset = dist.join(format!("VitruvianRemote-{}-tool.zip", opts.version));
    let _ = fs::remove_file(&asset);
    let status = Command::new("zip")
        .args(["-q", "-r", "-X"])
        .arg(&asset)
        .arg(".")
        .current_dir(&folder)
        .status()
        .map_err(|e| format!("failed to run zip: {e}"))?;
    if !status.success() {
        return Err("zip failed".to_string());
    }

    let size = fs::metadata(&asset)
        .map_err(|e| format!("zip was not created: {e}"))?
        .len();
    println!("==> {}", asset.display());
    println!("size: {size}");
    println!("sha256: {}", sha256_of(&asset)?);
    Ok(asset)
}

fn default_manifest() -> PathBuf {
    let base = env::var("BUILD_WORKSPACE_DIRECTORY")
        .ok()
        .filter(|s| !s.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| env::current_dir().unwrap_or_default());
    base.join(PKG).join("tool/vitruvian-tool.json")
}

pub fn run(args: &[String]) -> i32 {
    if args.len() != 5 {
        eprintln!(
            "Usage: zip-tool <remote-tool binary> <vitruvian-remote-agent binary> <version> <dist dir>"
        );
        return 1;
    }
    let opts = Options {
        tool: PathBuf::from(&args[1]),
        agent: PathBuf::from(&args[2]),
        version: args[3].clone(),
        dist: PathBuf::from(&args[4]),
        manifest: env::var("REMOTE_TOOL_MANIFEST")
            .ok()
            .filter(|s| !s.is_empty())
            .map(PathBuf::from)
            .unwrap_or_else(default_manifest),
        require_universal: env::var("REMOTE_TOOL_REQUIRE_UNIVERSAL").as_deref() == Ok("1"),
        max_minos: env::var("REMOTE_TOOL_MAX_MINOS").ok(),
        lipo: "lipo".to_string(),
        vtool: "vtool".to_string(),
    };
    match package(&opts) {
        Ok(_) => 0,
        Err(msg) => {
            eprintln!("error: {msg}");
            1
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp(label: &str) -> PathBuf {
        let p = env::temp_dir().join(format!(
            "ar-zip-test-{label}-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        fs::create_dir_all(&p).unwrap();
        p
    }

    fn script(dir: &Path, name: &str, body: &str) -> String {
        let p = dir.join(name);
        fs::write(&p, format!("#!/bin/sh\n{body}\n")).unwrap();
        fs::set_permissions(&p, fs::Permissions::from_mode(0o755)).unwrap();
        p.to_string_lossy().into_owned()
    }

    fn have(prog: &str) -> bool {
        Command::new(prog).arg("-v").output().is_ok() || Command::new(prog).output().is_ok()
    }

    struct Fixture {
        dir: PathBuf,
        opts: Options,
    }

    fn fixture(label: &str, lipo_out: &str, vtool_out: &str) -> Fixture {
        let dir = temp(label);
        fs::write(dir.join("tool"), "tool").unwrap();
        fs::write(dir.join("agent"), "agent").unwrap();
        fs::write(
            dir.join("vitruvian-tool.json"),
            "{\n  \"version\": \"3.0.0\"\n}\n",
        )
        .unwrap();
        let lipo = script(&dir, "lipo", &format!("echo '{lipo_out}'"));
        let vtool = script(&dir, "vtool", &format!("cat <<'EOT'\n{vtool_out}\nEOT"));
        let opts = Options {
            tool: dir.join("tool"),
            agent: dir.join("agent"),
            version: "3.0.0".to_string(),
            dist: dir.join("dist"),
            manifest: dir.join("vitruvian-tool.json"),
            require_universal: false,
            max_minos: None,
            lipo,
            vtool,
        };
        Fixture { dir, opts }
    }

    const FAT_14: &str = "x (architecture arm64):\n  cmd LC_BUILD_VERSION\n minos 14.0\nx (architecture x86_64):\n  cmd LC_BUILD_VERSION\n minos 14.0";

    #[test]
    fn manifest_version_first_match() {
        assert_eq!(
            manifest_version("{\n  \"version\": \"1.2.3\",\n  \"version\": \"9\"\n}"),
            Some("1.2.3".to_string())
        );
        assert_eq!(manifest_version("{}"), None);
    }

    #[test]
    fn newer_than_compares_numerically() {
        assert!(newer_than("14.10", "14.9"));
        assert!(newer_than("15.0", "14.99"));
        assert!(!newer_than("14.0", "14.0"));
        assert!(!newer_than("13.5", "14.0"));
        assert!(!newer_than("14", "14.0.0"));
    }

    #[test]
    fn minos_per_arch_fat_thin_and_none() {
        assert_eq!(
            minos_per_arch(FAT_14),
            vec![
                ("arm64".to_string(), "14.0".to_string()),
                ("x86_64".to_string(), "14.0".to_string())
            ]
        );
        assert_eq!(
            minos_per_arch("x:\n  cmd LC_BUILD_VERSION\n minos 13.0"),
            vec![("thin".to_string(), "13.0".to_string())]
        );
        assert_eq!(
            minos_per_arch("x (architecture arm64):\nx (architecture x86_64):\n minos 14.0"),
            vec![
                ("arm64".to_string(), "none".to_string()),
                ("x86_64".to_string(), "14.0".to_string())
            ]
        );
        assert!(minos_per_arch("").is_empty());
    }

    #[test]
    fn refuses_half_universal_build() {
        let mut f = fixture("half", "arm64", FAT_14);
        f.opts.require_universal = true;
        let err = package(&f.opts).unwrap_err();
        assert!(err.contains("expected a universal binary"), "{err}");
        let _ = fs::remove_dir_all(&f.dir);
    }

    #[test]
    fn refuses_program_too_new_or_unversioned() {
        let mut f = fixture("minos", "arm64 x86_64", FAT_14);
        f.opts.max_minos = Some("13.0".to_string());
        let err = package(&f.opts).unwrap_err();
        assert!(err.contains("needs macOS 14.0"), "{err}");
        assert!(err.contains("supports macOS 13.0"), "{err}");
        let _ = fs::remove_dir_all(&f.dir);

        let mut g = fixture("nominos", "arm64 x86_64", "x (architecture arm64):");
        g.opts.max_minos = Some("14.0".to_string());
        let err = package(&g.opts).unwrap_err();
        assert!(err.contains("needs macOS none"), "{err}");
        let _ = fs::remove_dir_all(&g.dir);
    }

    #[test]
    fn refuses_version_the_manifest_does_not_say() {
        let mut f = fixture("ver", "arm64 x86_64", FAT_14);
        f.opts.version = "9.9.9".to_string();
        let err = package(&f.opts).unwrap_err();
        assert!(err.contains("says 3.0.0, the release is 9.9.9"), "{err}");
        let _ = fs::remove_dir_all(&f.dir);
    }

    #[test]
    fn zip_holds_manifest_and_both_programs_at_the_top() {
        if !have("zip") || !have("unzip") {
            eprintln!("skipping: zip/unzip not available");
            return;
        }
        let mut f = fixture("zip", "arm64 x86_64", FAT_14);
        f.opts.require_universal = true;
        f.opts.max_minos = Some("14.0".to_string());
        let asset = package(&f.opts).expect("package");
        assert_eq!(
            asset.file_name().unwrap().to_string_lossy(),
            "VitruvianRemote-3.0.0-tool.zip"
        );
        let listing = Command::new("unzip")
            .arg("-Z1")
            .arg(&asset)
            .output()
            .unwrap();
        let mut names: Vec<String> = String::from_utf8_lossy(&listing.stdout)
            .lines()
            .map(str::to_string)
            .filter(|n| !n.ends_with('/'))
            .collect();
        names.sort();
        assert_eq!(
            names,
            vec![
                "bin/tool".to_string(),
                "bin/vitruvian-remote-agent".to_string(),
                "vitruvian-tool.json".to_string()
            ]
        );
        let _ = fs::remove_dir_all(&f.dir);
    }
}
