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

//! Fails when the checked-in `VitruvianTokens.kt` is not what `gen_tokens` + `ktfmt`
//! produce from `tokens.json`.
//! Native Rust replacement for `packages/design-system-android/tools/tokens_are_current.sh`.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicU64, Ordering};

pub const OUT_OF_DATE_MSG: &str = "\nVitruvianTokens.kt is out of date with packages/design-system/src/tokens.json.\n\nRegenerate it, then format:\n\n  bazel run //packages/design-system-android/tools:gen_tokens -- \\\n    --tokens \"$PWD/packages/design-system/src/tokens.json\" \\\n    --header \"$PWD/packages/design-system-android/tools/kt_license_header.txt\" \\\n    --out \"$PWD/packages/design-system-android/src/main/kotlin/dev/vitruvian/design/VitruvianTokens.kt\"\n  bazel run //:tidy\n\n";

static TMP_COUNTER: AtomicU64 = AtomicU64::new(0);

struct TempWorkdir {
    path: PathBuf,
}

impl TempWorkdir {
    fn new() -> Result<Self, String> {
        let seq = TMP_COUNTER.fetch_add(1, Ordering::Relaxed);
        let dir =
            std::env::temp_dir().join(format!("tokens_are_current_{}_{}", std::process::id(), seq));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir)
            .map_err(|e| format!("failed to create temp workdir {}: {e}", dir.display()))?;
        Ok(Self { path: dir })
    }
}

impl Drop for TempWorkdir {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.path);
    }
}

/// Resolves a Bazel runfiles path (`_main/...` or repository-relative path) the same way
/// `@bazel_tools//tools/bash/runfiles`'s `rlocation` does.
pub fn rlocation(rpath: &str) -> Result<PathBuf, String> {
    let direct = Path::new(rpath);
    if direct.is_absolute() && direct.exists() {
        return Ok(direct.to_path_buf());
    }

    for var in ["RUNFILES_DIR", "TEST_SRCDIR"] {
        if let Ok(dir) = std::env::var(var) {
            if !dir.is_empty() {
                let candidate = Path::new(&dir).join(rpath);
                if candidate.exists() {
                    return Ok(candidate);
                }
            }
        }
    }

    let mut manifest_candidates = Vec::new();
    if let Ok(mf) = std::env::var("RUNFILES_MANIFEST_FILE") {
        if !mf.is_empty() {
            manifest_candidates.push(PathBuf::from(mf));
        }
    }
    for var in ["RUNFILES_DIR", "TEST_SRCDIR"] {
        if let Ok(dir) = std::env::var(var) {
            if !dir.is_empty() {
                manifest_candidates.push(Path::new(&dir).join("MANIFEST"));
            }
        }
    }
    if let Ok(exe) = std::env::current_exe() {
        let mut s = exe.into_os_string();
        s.push(".runfiles_manifest");
        manifest_candidates.push(PathBuf::from(s));
    }

    for manifest in manifest_candidates {
        if let Ok(content) = fs::read_to_string(&manifest) {
            let prefix = format!("{rpath} ");
            for line in content.lines() {
                if let Some(target) = line.strip_prefix(&prefix) {
                    return Ok(PathBuf::from(target));
                }
            }
        }
    }

    if let Ok(exe) = std::env::current_exe() {
        let mut s = exe.into_os_string();
        s.push(".runfiles");
        let candidate = PathBuf::from(s).join(rpath);
        if candidate.exists() {
            return Ok(candidate);
        }
    }

    let stripped = rpath.strip_prefix("_main/").unwrap_or(rpath);
    if Path::new(stripped).exists() {
        return Ok(PathBuf::from(stripped));
    }
    if direct.exists() {
        return Ok(direct.to_path_buf());
    }

    Err(format!("cannot locate runfile: {rpath}"))
}

pub struct Config {
    pub generator_path: Option<PathBuf>,
    pub ktfmt_path: PathBuf,
    pub tokens_path: PathBuf,
    pub header_path: PathBuf,
    pub checked_in_path: PathBuf,
}

impl Config {
    pub fn from_env() -> Result<Self, String> {
        let get_or = |key: &str, default: &str| -> String {
            std::env::var(key)
                .ok()
                .filter(|v| !v.is_empty())
                .unwrap_or_else(|| default.to_string())
        };

        let generator_raw = get_or(
            "GENERATOR",
            "_main/packages/design-system-android/tools/gen_tokens",
        );
        let generator_path = rlocation(&generator_raw).ok();

        let ktfmt_path = rlocation(&get_or("KTFMT", "_main/tools/format/ktfmt"))?;
        let tokens_path = rlocation(&get_or(
            "TOKENS",
            "_main/packages/design-system/src/tokens.json",
        ))?;
        let header_path = rlocation(&get_or(
            "HEADER",
            "_main/packages/design-system-android/tools/kt_license_header.txt",
        ))?;
        let checked_in_path = rlocation(&get_or(
            "CHECKED_IN",
            "_main/packages/design-system-android/src/main/kotlin/dev/vitruvian/design/VitruvianTokens.kt",
        ))?;

        Ok(Self {
            generator_path,
            ktfmt_path,
            tokens_path,
            header_path,
            checked_in_path,
        })
    }
}

pub fn check_tokens_are_current(cfg: &Config) -> Result<(), String> {
    let workdir = TempWorkdir::new()?;
    let regenerated = workdir.path.join("VitruvianTokens.kt");

    if let Some(ref gen_bin) = cfg.generator_path {
        let status = Command::new(gen_bin)
            .arg("--tokens")
            .arg(&cfg.tokens_path)
            .arg("--header")
            .arg(&cfg.header_path)
            .arg("--out")
            .arg(&regenerated)
            .status()
            .map_err(|e| format!("failed to execute generator {}: {e}", gen_bin.display()))?;
        if !status.success() {
            return Err(format!(
                "generator {} exited with status {status}",
                gen_bin.display()
            ));
        }
    } else {
        gen_tokens::generate(
            &cfg.tokens_path.to_string_lossy(),
            &cfg.header_path.to_string_lossy(),
            &regenerated.to_string_lossy(),
        )
        .map_err(|e| e.traceback())?;
    }

    let ktfmt_status = Command::new(&cfg.ktfmt_path)
        .arg(&regenerated)
        .stdout(Stdio::null())
        .status()
        .map_err(|e| format!("failed to execute ktfmt {}: {e}", cfg.ktfmt_path.display()))?;
    if !ktfmt_status.success() {
        return Err(format!(
            "ktfmt {} exited with status {ktfmt_status}",
            cfg.ktfmt_path.display()
        ));
    }

    let checked_in_bytes = fs::read(&cfg.checked_in_path)
        .map_err(|e| format!("failed to read {}: {e}", cfg.checked_in_path.display()))?;
    let regenerated_bytes = fs::read(&regenerated)
        .map_err(|e| format!("failed to read {}: {e}", regenerated.display()))?;

    if checked_in_bytes != regenerated_bytes {
        let _ = Command::new("diff")
            .arg("-u")
            .arg(&cfg.checked_in_path)
            .arg(&regenerated)
            .status();
        return Err(OUT_OF_DATE_MSG.to_string());
    }

    Ok(())
}

fn main() {
    let cfg = match Config::from_env() {
        Ok(c) => c,
        Err(e) => {
            eprintln!("ERROR: {e}");
            std::process::exit(1);
        }
    };
    if let Err(msg) = check_tokens_are_current(&cfg) {
        eprint!("{msg}");
        std::process::exit(1);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn checked_in_tokens_are_current() {
        let cfg = Config::from_env().expect("resolve config from environment");
        check_tokens_are_current(&cfg).expect("VitruvianTokens.kt should be current");
    }

    #[test]
    fn detects_drift_when_checked_in_file_differs() {
        let mut cfg = Config::from_env().expect("resolve config from environment");
        let workdir = TempWorkdir::new().expect("temp workdir");
        let drifted = workdir.path.join("DriftedVitruvianTokens.kt");
        fs::write(&drifted, "// hand-edited drift\n").unwrap();
        cfg.checked_in_path = drifted;
        cfg.generator_path = None;
        cfg.ktfmt_path = PathBuf::from("/usr/bin/true");

        let err = check_tokens_are_current(&cfg).unwrap_err();
        assert_eq!(err, OUT_OF_DATE_MSG);
    }

    #[test]
    fn in_process_generator_fallback_matches_binary_generator() {
        let cfg = Config::from_env().expect("resolve config from environment");
        let workdir = TempWorkdir::new().expect("temp workdir");
        let out_bin = workdir.path.join("out_bin.kt");
        let out_inproc = workdir.path.join("out_inproc.kt");

        let gen_bin = cfg.generator_path.as_ref().expect("generator path");
        let status = Command::new(gen_bin)
            .arg("--tokens")
            .arg(&cfg.tokens_path)
            .arg("--header")
            .arg(&cfg.header_path)
            .arg("--out")
            .arg(&out_bin)
            .status()
            .unwrap();
        assert!(status.success());

        gen_tokens::generate(
            &cfg.tokens_path.to_string_lossy(),
            &cfg.header_path.to_string_lossy(),
            &out_inproc.to_string_lossy(),
        )
        .unwrap();

        assert_eq!(fs::read(&out_bin).unwrap(), fs::read(&out_inproc).unwrap());
    }

    #[test]
    fn rlocation_resolves_from_manifest_file() {
        let workdir = TempWorkdir::new().expect("temp workdir");
        let target = workdir.path.join("target.txt");
        fs::write(&target, "ok").unwrap();
        let manifest = workdir.path.join("MANIFEST");
        fs::write(
            &manifest,
            format!("_main/custom/file.txt {}\n", target.display()),
        )
        .unwrap();

        let content = fs::read_to_string(&manifest).unwrap();
        let resolved = content
            .lines()
            .find_map(|l| l.strip_prefix("_main/custom/file.txt "))
            .map(PathBuf::from)
            .unwrap();
        assert_eq!(resolved, target);
    }
}
