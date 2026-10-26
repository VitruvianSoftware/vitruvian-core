// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT

//! Native Rust implementation of `Tools/notarize.sh`.
//! Notarizes and staples a built `.app` or `.dmg` artifact with Apple's notary service.

use std::collections::BTreeMap;
use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NotarizeConfig {
    pub target: PathBuf,
    pub api_key_p8: String,
    pub key_id: String,
    pub issuer_id: String,
    pub require_notarization: bool,
    pub dry_run: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum NotarizeDecision {
    SkipNoCredentials { target: PathBuf },
    MissingRequiredCredentials,
    Execute(NotarizePlan),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NotarizePlan {
    pub target: PathBuf,
    pub is_app_bundle: bool,
    pub submit_path: PathBuf,
    pub p8_path: PathBuf,
    pub key_id: String,
    pub issuer_id: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CommandSpec {
    pub program: String,
    pub args: Vec<String>,
}

pub fn parse_cli_args(
    args: &[String],
    env_map: &BTreeMap<String, String>,
) -> Result<NotarizeConfig, String> {
    let mut dry_run = false;
    let mut target: Option<PathBuf> = None;

    for arg in args {
        match arg.as_str() {
            "--dry-run" => dry_run = true,
            "-h" | "--help" => {
                return Err("usage: notarize.sh <app-or-dmg>".to_string());
            }
            s if s.starts_with('-') => {
                return Err(format!("notarize.sh: unknown option '{}'", s));
            }
            s => {
                if target.is_some() {
                    return Err("usage: notarize.sh <app-or-dmg>".to_string());
                }
                target = Some(PathBuf::from(s));
            }
        }
    }

    let Some(target) = target else {
        return Err("usage: notarize.sh <app-or-dmg>".to_string());
    };

    let api_key_p8 = env_map
        .get("NOTARY_API_KEY_P8")
        .cloned()
        .unwrap_or_default();
    let key_id = env_map.get("NOTARY_KEY_ID").cloned().unwrap_or_default();
    let issuer_id = env_map.get("NOTARY_ISSUER_ID").cloned().unwrap_or_default();
    let require_notarization = env_map
        .get("REQUIRE_NOTARIZATION")
        .map(|v| v == "1")
        .unwrap_or(false);

    Ok(NotarizeConfig {
        target,
        api_key_p8,
        key_id,
        issuer_id,
        require_notarization,
        dry_run,
    })
}

pub fn evaluate_notarize(cfg: &NotarizeConfig, work_dir: &Path) -> NotarizeDecision {
    if cfg.api_key_p8.is_empty() || cfg.key_id.is_empty() || cfg.issuer_id.is_empty() {
        if cfg.require_notarization {
            return NotarizeDecision::MissingRequiredCredentials;
        }
        return NotarizeDecision::SkipNoCredentials {
            target: cfg.target.clone(),
        };
    }

    let is_app_bundle = cfg.target.to_string_lossy().ends_with(".app");
    let basename = cfg
        .target
        .file_name()
        .map(|f| f.to_string_lossy().to_string())
        .unwrap_or_else(|| "artifact".to_string());
    let submit_path = if is_app_bundle {
        work_dir.join(format!("{}.zip", basename))
    } else {
        cfg.target.clone()
    };

    NotarizeDecision::Execute(NotarizePlan {
        target: cfg.target.clone(),
        is_app_bundle,
        submit_path,
        p8_path: work_dir.join("AuthKey.p8"),
        key_id: cfg.key_id.clone(),
        issuer_id: cfg.issuer_id.clone(),
    })
}

pub fn build_notarize_commands(plan: &NotarizePlan) -> Vec<CommandSpec> {
    let target_str = plan.target.to_string_lossy().to_string();
    let submit_str = plan.submit_path.to_string_lossy().to_string();
    let p8_str = plan.p8_path.to_string_lossy().to_string();

    let mut cmds = Vec::new();
    if plan.is_app_bundle {
        cmds.push(CommandSpec {
            program: "xattr".to_string(),
            args: vec!["-cr".to_string(), target_str.clone()],
        });
        cmds.push(CommandSpec {
            program: "codesign".to_string(),
            args: vec![
                "--verify".to_string(),
                "--deep".to_string(),
                "--strict".to_string(),
                target_str.clone(),
            ],
        });
        cmds.push(CommandSpec {
            program: "/usr/bin/ditto".to_string(),
            args: vec![
                "-c".to_string(),
                "-k".to_string(),
                "--keepParent".to_string(),
                target_str.clone(),
                submit_str.clone(),
            ],
        });
    }

    cmds.push(CommandSpec {
        program: "xcrun".to_string(),
        args: vec![
            "notarytool".to_string(),
            "submit".to_string(),
            submit_str,
            "--key".to_string(),
            p8_str,
            "--key-id".to_string(),
            plan.key_id.clone(),
            "--issuer".to_string(),
            plan.issuer_id.clone(),
            "--wait".to_string(),
        ],
    });

    cmds.push(CommandSpec {
        program: "xcrun".to_string(),
        args: vec!["stapler".to_string(), "staple".to_string(), target_str],
    });

    cmds
}

pub fn decode_base64(input: &str) -> Result<Vec<u8>, String> {
    let mut out = Vec::new();
    let mut buf: u32 = 0;
    let mut bits: u8 = 0;

    for b in input.bytes() {
        if b.is_ascii_whitespace() || b == b'=' {
            continue;
        }
        let val = match b {
            b'A'..=b'Z' => b - b'A',
            b'a'..=b'z' => b - b'a' + 26,
            b'0'..=b'9' => b - b'0' + 52,
            b'+' => 62,
            b'/' => 63,
            _ => return Err(format!("invalid base64 byte: 0x{:02x}", b)),
        };
        buf = (buf << 6) | (val as u32);
        bits += 6;
        if bits >= 8 {
            bits -= 8;
            out.push(((buf >> bits) & 0xff) as u8);
        }
    }
    Ok(out)
}

pub fn run_cli(args: &[String]) -> i32 {
    let env_map: BTreeMap<String, String> = env::vars().collect();
    let cfg = match parse_cli_args(args, &env_map) {
        Ok(c) => c,
        Err(msg) => {
            eprintln!("{}", msg);
            return 1;
        }
    };

    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    let work_dir = env::temp_dir().join(format!(
        "vitruvian_notarize_{}_{}",
        std::process::id(),
        nanos
    ));

    match evaluate_notarize(&cfg, &work_dir) {
        NotarizeDecision::MissingRequiredCredentials => {
            eprintln!("Release notarization credentials are incomplete.");
            1
        }
        NotarizeDecision::SkipNoCredentials { target } => {
            println!(
                "No notarization credentials in the environment — skipping ({}).",
                target.display()
            );
            0
        }
        NotarizeDecision::Execute(plan) => {
            if !cfg.dry_run && !plan.target.exists() {
                eprintln!("✗ {} not found", plan.target.display());
                return 1;
            }

            if cfg.dry_run {
                for cmd in build_notarize_commands(&plan) {
                    println!("dry-run: {} {}", cmd.program, cmd.args.join(" "));
                }
                return 0;
            }

            if let Err(e) = fs::create_dir_all(&work_dir) {
                eprintln!("✗ could not create temp dir: {}", e);
                return 1;
            }

            let decoded = match decode_base64(&cfg.api_key_p8) {
                Ok(b) => b,
                Err(e) => {
                    let _ = fs::remove_dir_all(&work_dir);
                    eprintln!("✗ invalid NOTARY_API_KEY_P8: {}", e);
                    return 1;
                }
            };
            if let Err(e) = fs::write(&plan.p8_path, &decoded) {
                let _ = fs::remove_dir_all(&work_dir);
                eprintln!("✗ failed to write AuthKey.p8: {}", e);
                return 1;
            }
            #[cfg(unix)]
            {
                use std::os::unix::fs::PermissionsExt;
                let _ = fs::set_permissions(&plan.p8_path, fs::Permissions::from_mode(0o600));
            }

            let basename = plan
                .target
                .file_name()
                .map(|f| f.to_string_lossy().to_string())
                .unwrap_or_else(|| plan.target.to_string_lossy().to_string());

            let cmds = build_notarize_commands(&plan);
            for cmd in cmds {
                if cmd.program == "xcrun"
                    && cmd.args.first().map(|s| s.as_str()) == Some("notarytool")
                {
                    println!(
                        "▸ Submitting {} to the notary service (can take a few minutes)…",
                        basename
                    );
                } else if cmd.program == "xcrun"
                    && cmd.args.first().map(|s| s.as_str()) == Some("stapler")
                {
                    println!("▸ Stapling {}…", basename);
                }
                let ok = Command::new(&cmd.program)
                    .args(&cmd.args)
                    .status()
                    .map(|s| s.success())
                    .unwrap_or(false);
                if !ok {
                    let _ = fs::remove_dir_all(&work_dir);
                    return 1;
                }
            }

            let _ = fs::remove_dir_all(&work_dir);
            println!("✓ Notarized and stapled: {}", basename);
            0
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_missing_target_fails() {
        let env_map = BTreeMap::new();
        assert!(parse_cli_args(&[], &env_map).is_err());
    }

    #[test]
    fn test_skip_when_credentials_missing_and_not_required() {
        let env_map = BTreeMap::new();
        let cfg = parse_cli_args(&["dist/Vitruvian.dmg".to_string()], &env_map).unwrap();
        assert_eq!(
            evaluate_notarize(&cfg, Path::new("/tmp/work")),
            NotarizeDecision::SkipNoCredentials {
                target: PathBuf::from("dist/Vitruvian.dmg")
            }
        );
    }

    #[test]
    fn test_fail_when_credentials_missing_and_required() {
        let mut env_map = BTreeMap::new();
        env_map.insert("REQUIRE_NOTARIZATION".to_string(), "1".to_string());
        let cfg = parse_cli_args(&["dist/Vitruvian.dmg".to_string()], &env_map).unwrap();
        assert_eq!(
            evaluate_notarize(&cfg, Path::new("/tmp/work")),
            NotarizeDecision::MissingRequiredCredentials
        );
    }

    #[test]
    fn test_app_bundle_zips_before_submitting() {
        let mut env_map = BTreeMap::new();
        env_map.insert("NOTARY_API_KEY_P8".to_string(), "aGVsbG8=".to_string());
        env_map.insert("NOTARY_KEY_ID".to_string(), "KEY123".to_string());
        env_map.insert("NOTARY_ISSUER_ID".to_string(), "ISSUER456".to_string());

        let cfg = parse_cli_args(&["/tmp/stage/Vitruvian.app".to_string()], &env_map).unwrap();
        let NotarizeDecision::Execute(plan) = evaluate_notarize(&cfg, Path::new("/tmp/work"))
        else {
            panic!("expected Execute");
        };
        assert!(plan.is_app_bundle);
        assert_eq!(
            plan.submit_path,
            PathBuf::from("/tmp/work/Vitruvian.app.zip")
        );

        let cmds = build_notarize_commands(&plan);
        assert_eq!(cmds.len(), 5);
        assert_eq!(cmds[0].program, "xattr");
        assert_eq!(cmds[1].program, "codesign");
        assert_eq!(cmds[2].program, "/usr/bin/ditto");
        assert_eq!(
            cmds[3].args,
            vec![
                "notarytool",
                "submit",
                "/tmp/work/Vitruvian.app.zip",
                "--key",
                "/tmp/work/AuthKey.p8",
                "--key-id",
                "KEY123",
                "--issuer",
                "ISSUER456",
                "--wait",
            ]
        );
        assert_eq!(
            cmds[4].args,
            vec!["stapler", "staple", "/tmp/stage/Vitruvian.app"]
        );
    }

    #[test]
    fn test_dmg_submits_directly_without_ditto() {
        let mut env_map = BTreeMap::new();
        env_map.insert("NOTARY_API_KEY_P8".to_string(), "aGVsbG8=".to_string());
        env_map.insert("NOTARY_KEY_ID".to_string(), "KEY123".to_string());
        env_map.insert("NOTARY_ISSUER_ID".to_string(), "ISSUER456".to_string());

        let cfg = parse_cli_args(&["dist/Vitruvian-1.2.3.dmg".to_string()], &env_map).unwrap();
        let NotarizeDecision::Execute(plan) = evaluate_notarize(&cfg, Path::new("/tmp/work"))
        else {
            panic!("expected Execute");
        };
        assert!(!plan.is_app_bundle);
        assert_eq!(plan.submit_path, PathBuf::from("dist/Vitruvian-1.2.3.dmg"));
        let cmds = build_notarize_commands(&plan);
        assert_eq!(cmds.len(), 2);
        assert_eq!(cmds[0].args[2], "dist/Vitruvian-1.2.3.dmg");
        assert_eq!(cmds[1].args[2], "dist/Vitruvian-1.2.3.dmg");
    }
}
