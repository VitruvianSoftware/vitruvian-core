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

//! Writes `Sources/VitruvianToolCLI/Templates.swift` from the hello samples, or
//! checks with `--check` that the committed file matches what would be written.
//! Native Rust replacement for `packages/vitruvian-sdk/samples/sync_templates.py`.

use std::fs;
use std::path::{Path, PathBuf};

pub const OUTPUT_REL: &str = "Sources/VitruvianToolCLI/Templates.swift";
pub const VERSION_MARK: &str = "{{sdk-version}}";

/// The name each file has in Swift, and where it is under `samples/`.
pub const FILES: &[(&str, &str)] = &[
    ("pythonManifest", "hello-python/vitruvian-tool.json"),
    ("pythonProgram", "hello-python/bin/tool.py"),
    ("pythonKitManifest", "hello-python-kit/vitruvian-tool.json"),
    ("pythonKitProgram", "hello-python-kit/bin/tool.py"),
    ("pythonKitRequirements", "hello-python-kit/requirements.txt"),
    ("typescriptManifest", "hello-typescript/vitruvian-tool.json"),
    ("typescriptLauncher", "hello-typescript/bin/tool"),
    ("typescriptProgram", "hello-typescript/bin/tool.mjs"),
    ("typescriptPackage", "hello-typescript/package.json"),
    ("swiftManifest", "hello-swift/vitruvian-tool.json"),
    ("swiftProgram", "hello-swift/main.swift"),
    ("goManifest", "hello-go/vitruvian-tool.json"),
    ("goProgram", "hello-go/main.go"),
    ("rustManifest", "hello-rust/vitruvian-tool.json"),
    ("rustProgram", "hello-rust/src/main.rs"),
];

pub const SWIFT_LICENSE_HEADER: &str = "\
// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the \"Software\"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.";

/// Extracts the `#` license header from a Python script as `//` Swift comments,
/// matching `sync_templates.py`'s `header()`.
pub fn header_from_python_script(script_text: &str) -> String {
    let mut lines = Vec::new();
    for line in script_text.split('\n').skip(1) {
        if let Some(rest) = line.strip_prefix('#') {
            lines.push(format!("//{rest}"));
        } else {
            break;
        }
    }
    lines.join("\n")
}

pub fn header() -> &'static str {
    SWIFT_LICENSE_HEADER
}

/// Replaces `"@vitruviansoftware/tool-kit": "<version>"` with
/// `"@vitruviansoftware/tool-kit": "{{sdk-version}}"`.
pub fn replace_ts_toolkit_pin(text: &str) -> String {
    const PREFIX: &str = "\"@vitruviansoftware/tool-kit\": \"";
    let mut out = String::with_capacity(text.len());
    let mut rest = text;

    while let Some(pos) = rest.find(PREFIX) {
        let head_end = pos + PREFIX.len();
        out.push_str(&rest[..head_end]);
        let after = &rest[head_end..];
        if let Some(quote_idx) = after.find('"') {
            if quote_idx > 0 {
                out.push_str(VERSION_MARK);
                out.push('"');
                rest = &after[quote_idx + 1..];
            } else {
                rest = after;
            }
        } else {
            out.push_str(after);
            return out;
        }
    }
    out.push_str(rest);
    out
}

/// Replaces `vitruvian-tool-kit==\S+(  # x-release-please-version)?` with
/// `vitruvian-tool-kit=={{sdk-version}}`.
pub fn replace_py_toolkit_pin(text: &str) -> String {
    const PREFIX: &str = "vitruvian-tool-kit==";
    const RP_COMMENT: &str = "  # x-release-please-version";
    let mut out = String::with_capacity(text.len());
    let mut rest = text;

    while let Some(pos) = rest.find(PREFIX) {
        let head_end = pos + PREFIX.len();
        out.push_str(&rest[..head_end]);
        let after = &rest[head_end..];
        let non_ws_len: usize = after
            .chars()
            .take_while(|c| !c.is_whitespace())
            .map(char::len_utf8)
            .sum();
        if non_ws_len > 0 {
            out.push_str(VERSION_MARK);
            let after_ver = &after[non_ws_len..];
            if let Some(after_comment) = after_ver.strip_prefix(RP_COMMENT) {
                rest = after_comment;
            } else {
                rest = after_ver;
            }
        } else {
            rest = after;
        }
    }
    out.push_str(rest);
    out
}

/// Applies all version pin replacements defined in `PINS`.
pub fn apply_pins(text: &str) -> String {
    let step1 = replace_ts_toolkit_pin(text);
    replace_py_toolkit_pin(&step1)
}

/// Renders the full contents of `Sources/VitruvianToolCLI/Templates.swift` from `samples_dir`.
pub fn swift_from_dir(samples_dir: &Path) -> Result<String, String> {
    let mut parts: Vec<String> = vec![
        header().to_string(),
        String::new(),
        "// GENERATED by samples/sync_templates.py from the hello samples. Do not".to_string(),
        "// edit it: change the sample, then run".to_string(),
        "//   bazel run //packages/vitruvian-sdk:sync-templates".to_string(),
        String::new(),
        "/// The files `vitruvian-tool init` starts a new tool from: the hello".to_string(),
        "/// samples, byte for byte, but for the kit's version, written {{sdk-version}}."
            .to_string(),
        "enum Templates {".to_string(),
    ];

    for &(name, rel_path) in FILES {
        let full_path = samples_dir.join(rel_path);
        let raw_text =
            fs::read_to_string(&full_path).map_err(|e| format!("{}: {e}", full_path.display()))?;
        let text = apply_pins(&raw_text);
        if text.contains("\"\"\"#") || text.contains("\\#") || !text.ends_with('\n') {
            return Err(format!(
                "{rel_path} cannot be written as a Swift raw string"
            ));
        }
        parts.push(format!("    /// samples/{rel_path}"));
        parts.push(format!("    static let {name} = #\"\"\""));
        parts.push(text[..text.len() - 1].to_string());
        parts.push("\"\"\"# + \"\\n\"".to_string());
        parts.push(String::new());
    }

    if let Some(last) = parts.last_mut() {
        *last = "}".to_string();
    }
    let mut result = parts.join("\n");
    result.push('\n');
    Ok(result)
}

/// Resolves `(samples_dir, package_dir)` matching `sync_templates.py`'s path resolution.
pub fn resolve_dirs() -> Result<(PathBuf, PathBuf), String> {
    let workspace_root = std::env::var("BUILD_WORKSPACE_DIRECTORY")
        .ok()
        .filter(|s| !s.is_empty())
        .map(PathBuf::from);

    let mut samples_candidates = Vec::new();
    if let Ok(explicit) = std::env::var("SYNC_TEMPLATES_SAMPLES_DIR") {
        if !explicit.is_empty() {
            samples_candidates.push(PathBuf::from(explicit));
        }
    }
    if let Some(ref root) = workspace_root {
        samples_candidates.push(root.join("packages").join("vitruvian-sdk").join("samples"));
    }
    if let Ok(cwd) = std::env::current_dir() {
        samples_candidates.push(cwd.join("packages").join("vitruvian-sdk").join("samples"));
        samples_candidates.push(cwd.join("samples"));
        samples_candidates.push(cwd);
    }
    for var in ["RUNFILES_DIR", "TEST_SRCDIR"] {
        if let Ok(rf) = std::env::var(var) {
            if !rf.is_empty() {
                let rf_path = PathBuf::from(rf);
                samples_candidates.push(
                    rf_path
                        .join("_main")
                        .join("packages")
                        .join("vitruvian-sdk")
                        .join("samples"),
                );
                samples_candidates.push(
                    rf_path
                        .join("packages")
                        .join("vitruvian-sdk")
                        .join("samples"),
                );
            }
        }
    }

    let samples_dir = samples_candidates
        .into_iter()
        .find(|cand| cand.join("hello-python/vitruvian-tool.json").is_file())
        .ok_or_else(|| {
            "could not locate samples/ directory containing hello-python/vitruvian-tool.json"
                .to_string()
        })?;

    let package_dir = if let Some(root) = workspace_root {
        root.join("packages").join("vitruvian-sdk")
    } else {
        samples_dir
            .parent()
            .map(Path::to_path_buf)
            .unwrap_or_else(|| PathBuf::from("."))
    };

    Ok((samples_dir, package_dir))
}

/// Runs the template synchronization or `--check` verification against `(samples_dir, package_dir)`.
pub fn run_with_dirs(
    arguments: &[String],
    samples_dir: &Path,
    package_dir: &Path,
) -> Result<(i32, String), String> {
    let path = package_dir
        .join("Sources")
        .join("VitruvianToolCLI")
        .join("Templates.swift");
    let wanted = swift_from_dir(samples_dir)?;

    if arguments.iter().any(|a| a == "--check") {
        let current = fs::read_to_string(&path).map_err(|e| format!("{}: {e}", path.display()))?;
        let same = current == wanted;
        let line = format!(
            "templates: {}\n",
            if same {
                "in sync"
            } else {
                "OUT OF SYNC, run sync_templates.py"
            }
        );
        return Ok((if same { 0 } else { 1 }, line));
    }

    fs::write(&path, &wanted).map_err(|e| format!("{}: {e}", path.display()))?;
    Ok((0, format!("wrote {}\n", path.display())))
}

/// Entrypoint matching `sync_templates.py`'s `main(arguments)`.
pub fn run(arguments: &[String]) -> i32 {
    let (samples_dir, package_dir) = match resolve_dirs() {
        Ok(dirs) => dirs,
        Err(e) => {
            eprintln!("{e}");
            return 1;
        }
    };
    match run_with_dirs(arguments, &samples_dir, &package_dir) {
        Ok((code, stdout_msg)) => {
            print!("{stdout_msg}");
            code
        }
        Err(err_msg) => {
            eprintln!("{err_msg}");
            1
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU64, Ordering};

    static TEST_SEQ: AtomicU64 = AtomicU64::new(0);

    fn make_temp_dir(label: &str) -> PathBuf {
        let seq = TEST_SEQ.fetch_add(1, Ordering::Relaxed);
        let dir = std::env::temp_dir().join(format!(
            "sync_templates_rs_test_{}_{}_{}",
            label,
            std::process::id(),
            seq
        ));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn copy_samples_to(src_samples: &Path, dst_samples: &Path) {
        for &(_, rel_path) in FILES {
            let src = src_samples.join(rel_path);
            let dst = dst_samples.join(rel_path);
            if let Some(parent) = dst.parent() {
                fs::create_dir_all(parent).unwrap();
            }
            fs::copy(&src, &dst).unwrap();
        }
    }

    #[test]
    fn committed_templates_swift_is_in_sync() {
        let (samples_dir, package_dir) = resolve_dirs().expect("resolve dirs");
        let (code, out) =
            run_with_dirs(&["--check".to_string()], &samples_dir, &package_dir).unwrap();
        assert_eq!(out, "templates: in sync\n");
        assert_eq!(code, 0);
    }

    #[test]
    fn header_matches_sync_templates_py_header() {
        let (samples_dir, _) = resolve_dirs().expect("resolve dirs");
        let py_script = fs::read_to_string(samples_dir.join("sync_templates.py")).unwrap();
        assert_eq!(header(), header_from_python_script(&py_script));
    }

    #[test]
    fn pin_replacements_match_typescript_and_python_patterns() {
        let pkg_json =
            "{\n  \"dependencies\": {\n    \"@vitruviansoftware/tool-kit\": \"1.2.3\"\n  }\n}\n";
        assert_eq!(
            apply_pins(pkg_json),
            "{\n  \"dependencies\": {\n    \"@vitruviansoftware/tool-kit\": \"{{sdk-version}}\"\n  }\n}\n"
        );

        let req_with_comment = "vitruvian-tool-kit==0.10.0  # x-release-please-version\n";
        assert_eq!(
            apply_pins(req_with_comment),
            "vitruvian-tool-kit=={{sdk-version}}\n"
        );

        let req_without_comment = "vitruvian-tool-kit==0.10.0\n";
        assert_eq!(
            apply_pins(req_without_comment),
            "vitruvian-tool-kit=={{sdk-version}}\n"
        );
    }

    #[test]
    fn sync_mode_writes_and_check_mode_detects_drift() {
        let (real_samples, _) = resolve_dirs().expect("resolve dirs");
        let tmp = make_temp_dir("sync_and_drift");
        let pkg_dir = tmp.join("packages/vitruvian-sdk");
        let samples_dir = pkg_dir.join("samples");
        let cli_dir = pkg_dir.join("Sources/VitruvianToolCLI");
        fs::create_dir_all(&cli_dir).unwrap();
        copy_samples_to(&real_samples, &samples_dir);

        // 1. Write mode generates Templates.swift
        let (code, out) = run_with_dirs(&[], &samples_dir, &pkg_dir).unwrap();
        assert_eq!(code, 0);
        assert!(out.starts_with("wrote "));

        // 2. Check mode passes on freshly generated file
        let (code, out) = run_with_dirs(&["--check".to_string()], &samples_dir, &pkg_dir).unwrap();
        assert_eq!(code, 0);
        assert_eq!(out, "templates: in sync\n");

        // 3. Modify Templates.swift -> check mode fails with exit 1
        fs::write(cli_dir.join("Templates.swift"), "// drifted\n").unwrap();
        let (code, out) = run_with_dirs(&["--check".to_string()], &samples_dir, &pkg_dir).unwrap();
        assert_eq!(code, 1);
        assert_eq!(out, "templates: OUT OF SYNC, run sync_templates.py\n");

        let _ = fs::remove_dir_all(&tmp);
    }

    #[test]
    fn rejects_files_unsafe_for_swift_raw_strings() {
        let (real_samples, _) = resolve_dirs().expect("resolve dirs");
        for (label, bad_content) in [
            ("triple_quote_hash", "print(\"\"\"#)\n"),
            ("backslash_hash", "print(\"\\#(x)\")\n"),
            ("no_trailing_newline", "print(\"hi\")"),
        ] {
            let tmp = make_temp_dir(label);
            let samples_dir = tmp.join("samples");
            copy_samples_to(&real_samples, &samples_dir);
            fs::write(samples_dir.join("hello-python/bin/tool.py"), bad_content).unwrap();

            let err = swift_from_dir(&samples_dir).unwrap_err();
            assert_eq!(
                err,
                "hello-python/bin/tool.py cannot be written as a Swift raw string"
            );
            let _ = fs::remove_dir_all(&tmp);
        }
    }
}
