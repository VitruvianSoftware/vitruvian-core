// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 VitruvianSoftware

use std::env;
use std::fs;
use std::path::{Path, PathBuf};

pub const BEGIN_MARKER: &str = "// BEGIN PINNED FROM apps/desktop/nexus-agent";
pub const END_MARKER: &str = "// END PINNED FROM apps/desktop/nexus-agent";

pub struct Config {
    pub check: bool,
    pub shared: PathBuf,
    pub pinned: PathBuf,
}

pub fn parse_args(args: &[String]) -> Result<Config, String> {
    let workspace = env::var("BUILD_WORKSPACE_DIRECTORY")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("."));
    let mut check = false;
    let mut shared = workspace
        .join("apps/desktop/nexus-agent/macos/Sources/NexusAgentShared/NexusAgentShared.swift");
    let mut pinned = workspace.join(
        "apps/desktop/vitruvian/Sources/Vitruvian/Services/Platform/External/ToolProtocol.swift",
    );

    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--check" => check = true,
            "--shared" => {
                i += 1;
                if i >= args.len() {
                    return Err("--shared requires a value".into());
                }
                shared = PathBuf::from(&args[i]);
            }
            "--pinned" => {
                i += 1;
                if i >= args.len() {
                    return Err("--pinned requires a value".into());
                }
                pinned = PathBuf::from(&args[i]);
            }
            "-h" | "--help" => {
                return Err(
                    "Usage: pin_nexus_agent_shared [--check] [--shared <path>] [--pinned <path>]"
                        .into(),
                );
            }
            other => return Err(format!("unknown argument: {}", other)),
        }
        i += 1;
    }

    Ok(Config {
        check,
        shared,
        pinned,
    })
}

pub fn extract_pinned_section(content: &str) -> Option<(usize, usize, String)> {
    let lines: Vec<&str> = content.split_inclusive('\n').collect();
    let mut begin_idx = None;
    let mut end_idx = None;
    for (idx, line) in lines.iter().enumerate() {
        if line.contains(BEGIN_MARKER) {
            begin_idx = Some(idx);
        } else if line.contains(END_MARKER) {
            end_idx = Some(idx);
        }
    }
    let b = begin_idx?;
    let e = end_idx?;
    if b >= e {
        return None;
    }
    let body: String = lines[b + 1..e].concat();
    Some((b, e, body))
}

pub fn check(shared_path: &Path, pinned_path: &Path) -> i32 {
    if !shared_path.exists() {
        println!(
            "Shared source {} not present in this checkout; skipping pin check.",
            shared_path.display()
        );
        return 0;
    }
    let Ok(pinned_content) = fs::read_to_string(pinned_path) else {
        eprintln!("ERROR: cannot read {}", pinned_path.display());
        return 1;
    };
    let Some((_, _, pinned_body)) = extract_pinned_section(&pinned_content) else {
        println!("No pin markers in {}; OK.", pinned_path.display());
        return 0;
    };
    let Ok(shared_content) = fs::read_to_string(shared_path) else {
        eprintln!("ERROR: cannot read {}", shared_path.display());
        return 1;
    };
    if let Some((_, _, shared_body)) = extract_pinned_section(&shared_content) {
        if pinned_body.trim() != shared_body.trim() {
            eprintln!(
                "ERROR: {} has drifted from {}.",
                pinned_path.display(),
                shared_path.display()
            );
            eprintln!("Run: bazel run //apps/desktop/vitruvian:pin_nexus_agent_shared");
            return 1;
        }
    }
    println!(
        "OK: {} is in sync with {}.",
        pinned_path.display(),
        shared_path.display()
    );
    0
}

pub fn sync(shared_path: &Path, pinned_path: &Path) -> i32 {
    if !shared_path.exists() {
        eprintln!("ERROR: {} not found.", shared_path.display());
        return 1;
    }
    let Ok(pinned_content) = fs::read_to_string(pinned_path) else {
        eprintln!("ERROR: cannot read {}", pinned_path.display());
        return 1;
    };
    let Some((b, e, _)) = extract_pinned_section(&pinned_content) else {
        println!(
            "No pin markers in {}; nothing to update.",
            pinned_path.display()
        );
        return 0;
    };
    let Ok(shared_content) = fs::read_to_string(shared_path) else {
        eprintln!("ERROR: cannot read {}", shared_path.display());
        return 1;
    };
    let Some((_, _, shared_body)) = extract_pinned_section(&shared_content) else {
        eprintln!("ERROR: no pin markers in {}.", shared_path.display());
        return 1;
    };
    let lines: Vec<&str> = pinned_content.split_inclusive('\n').collect();
    let mut updated = String::new();
    for line in &lines[..=b] {
        updated.push_str(line);
    }
    updated.push_str(&shared_body);
    for line in &lines[e..] {
        updated.push_str(line);
    }
    if let Err(err) = fs::write(pinned_path, updated) {
        eprintln!("ERROR: write {}: {}", pinned_path.display(), err);
        return 1;
    }
    println!(
        "Updated {} from {}.",
        pinned_path.display(),
        shared_path.display()
    );
    0
}

pub fn run_cli(args: &[String]) -> i32 {
    let config = match parse_args(args) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("{}", e);
            return 2;
        }
    };
    if config.check {
        check(&config.shared, &config.pinned)
    } else {
        sync(&config.shared, &config.pinned)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_extract_check_and_sync() {
        let tmp = env::temp_dir().join("test_pin_nexus_agent_shared_rs");
        let _ = fs::remove_dir_all(&tmp);
        fs::create_dir_all(&tmp).unwrap();

        let shared = tmp.join("shared.swift");
        let pinned = tmp.join("pinned.swift");

        let shared_text = format!(
            "// header\n{}\npublic struct Msg {{}}\n{}\n// footer\n",
            BEGIN_MARKER, END_MARKER
        );
        let pinned_stale = format!(
            "// header\n{}\npublic struct OldMsg {{}}\n{}\n// footer\n",
            BEGIN_MARKER, END_MARKER
        );

        fs::write(&shared, &shared_text).unwrap();
        fs::write(&pinned, &pinned_stale).unwrap();

        assert_eq!(check(&shared, &pinned), 1);
        assert_eq!(sync(&shared, &pinned), 0);
        assert_eq!(check(&shared, &pinned), 0);

        let _ = fs::remove_dir_all(&tmp);
    }
}
