// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT

//! Native Rust implementation of `Tools/ci-setup-signing.sh`.
//! Imports the stable signing certificate into a dedicated keychain on CI.

use std::collections::BTreeMap;
use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

pub const KEYCHAIN_PASSWORD: &str = "ci-signing";
pub const KEYCHAIN_FILENAME: &str = "vitruvian-signing.keychain-db";
pub const P12_FILENAME: &str = "vitruvian-signing.p12";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CiSigningConfig {
    pub signing_cert_p12: String,
    pub signing_cert_password: String,
    pub require_signing: bool,
    pub runner_temp: PathBuf,
    pub dry_run: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CiSigningDecision {
    SkipAdHoc,
    MissingRequiredCredentials,
    Import(CiSigningPlan),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CiSigningPlan {
    pub keychain_path: PathBuf,
    pub p12_path: PathBuf,
    pub keychain_password: String,
    pub cert_password: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CommandSpec {
    pub program: String,
    pub args: Vec<String>,
    pub suppress_output: bool,
}

pub fn parse_cli_args(
    args: &[String],
    env_map: &BTreeMap<String, String>,
) -> Result<CiSigningConfig, String> {
    let mut dry_run = false;
    for arg in args {
        match arg.as_str() {
            "--dry-run" => dry_run = true,
            "-h" | "--help" => {
                return Err("usage: ci-setup-signing [--dry-run]".to_string());
            }
            other => {
                return Err(format!("ci-setup-signing: unknown argument '{}'", other));
            }
        }
    }

    let signing_cert_p12 = env_map.get("SIGNING_CERT_P12").cloned().unwrap_or_default();
    let signing_cert_password = env_map
        .get("SIGNING_CERT_PASSWORD")
        .cloned()
        .unwrap_or_default();
    let require_signing = env_map
        .get("REQUIRE_SIGNING")
        .map(|v| v == "1")
        .unwrap_or(false);
    let runner_temp = env_map
        .get("RUNNER_TEMP")
        .filter(|s| !s.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/tmp"));

    Ok(CiSigningConfig {
        signing_cert_p12,
        signing_cert_password,
        require_signing,
        runner_temp,
        dry_run,
    })
}

pub fn evaluate_config(cfg: &CiSigningConfig) -> CiSigningDecision {
    if cfg.signing_cert_p12.is_empty() || cfg.signing_cert_password.is_empty() {
        if cfg.require_signing {
            return CiSigningDecision::MissingRequiredCredentials;
        }
        return CiSigningDecision::SkipAdHoc;
    }

    CiSigningDecision::Import(CiSigningPlan {
        keychain_path: cfg.runner_temp.join(KEYCHAIN_FILENAME),
        p12_path: cfg.runner_temp.join(P12_FILENAME),
        keychain_password: KEYCHAIN_PASSWORD.to_string(),
        cert_password: cfg.signing_cert_password.clone(),
    })
}

pub fn parse_keychain_list_output(output: &str) -> Vec<String> {
    output
        .lines()
        .flat_map(|line| {
            line.replace('"', "")
                .split_whitespace()
                .map(String::from)
                .collect::<Vec<_>>()
        })
        .filter(|s| !s.is_empty())
        .collect()
}

pub fn build_security_commands(
    plan: &CiSigningPlan,
    existing_keychains: &[String],
) -> Vec<CommandSpec> {
    let kc = plan.keychain_path.to_string_lossy().to_string();
    let p12 = plan.p12_path.to_string_lossy().to_string();
    let kcpass = plan.keychain_password.clone();

    let mut search_list_args = vec![
        "list-keychains".to_string(),
        "-d".to_string(),
        "user".to_string(),
        "-s".to_string(),
        kc.clone(),
    ];
    for existing in existing_keychains {
        search_list_args.push(existing.clone());
    }

    vec![
        CommandSpec {
            program: "security".to_string(),
            args: vec![
                "create-keychain".to_string(),
                "-p".to_string(),
                kcpass.clone(),
                kc.clone(),
            ],
            suppress_output: false,
        },
        CommandSpec {
            program: "security".to_string(),
            args: vec!["set-keychain-settings".to_string(), kc.clone()],
            suppress_output: false,
        },
        CommandSpec {
            program: "security".to_string(),
            args: vec![
                "unlock-keychain".to_string(),
                "-p".to_string(),
                kcpass.clone(),
                kc.clone(),
            ],
            suppress_output: false,
        },
        CommandSpec {
            program: "security".to_string(),
            args: vec![
                "import".to_string(),
                p12,
                "-k".to_string(),
                kc.clone(),
                "-P".to_string(),
                plan.cert_password.clone(),
                "-T".to_string(),
                "/usr/bin/codesign".to_string(),
            ],
            suppress_output: false,
        },
        CommandSpec {
            program: "security".to_string(),
            args: vec![
                "set-key-partition-list".to_string(),
                "-S".to_string(),
                "apple-tool:,apple:,codesign:".to_string(),
                "-s".to_string(),
                "-k".to_string(),
                kcpass,
                kc,
            ],
            suppress_output: true,
        },
        CommandSpec {
            program: "security".to_string(),
            args: search_list_args,
            suppress_output: false,
        },
    ]
}

pub fn decode_base64_to_file(encoded: &str, dest: &Path) -> Result<(), String> {
    let bytes = decode_base64(encoded)?;
    fs::write(dest, &bytes).map_err(|e| format!("failed to write {}: {}", dest.display(), e))?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = fs::set_permissions(dest, fs::Permissions::from_mode(0o600));
    }
    Ok(())
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
            if msg.starts_with("usage:") {
                println!("{}", msg);
                return 0;
            }
            eprintln!("{}", msg);
            return 2;
        }
    };

    match evaluate_config(&cfg) {
        CiSigningDecision::MissingRequiredCredentials => {
            eprintln!("Release signing credentials are incomplete.");
            1
        }
        CiSigningDecision::SkipAdHoc => {
            println!("No release signing credentials — building ad-hoc.");
            0
        }
        CiSigningDecision::Import(plan) => {
            if cfg.dry_run {
                let cmds = build_security_commands(&plan, &["login.keychain-db".to_string()]);
                for cmd in cmds {
                    println!("dry-run: {} {}", cmd.program, cmd.args.join(" "));
                }
                return 0;
            }

            if let Err(e) = decode_base64_to_file(&cfg.signing_cert_p12, &plan.p12_path) {
                eprintln!("{}", e);
                return 1;
            }

            let existing_output = Command::new("security")
                .args(["list-keychains", "-d", "user"])
                .output()
                .ok()
                .map(|o| String::from_utf8_lossy(&o.stdout).to_string())
                .unwrap_or_default();
            let existing = parse_keychain_list_output(&existing_output);

            let cmds = build_security_commands(&plan, &existing);
            for cmd in cmds {
                let status = if cmd.suppress_output {
                    Command::new(&cmd.program)
                        .args(&cmd.args)
                        .output()
                        .map(|o| o.status.success())
                        .unwrap_or(false)
                } else {
                    Command::new(&cmd.program)
                        .args(&cmd.args)
                        .status()
                        .map(|s| s.success())
                        .unwrap_or(false)
                };
                if !status {
                    let _ = fs::remove_file(&plan.p12_path);
                    return 1;
                }
            }

            let _ = fs::remove_file(&plan.p12_path);
            println!("Signing certificate imported.");
            0
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_skip_when_no_credentials_and_not_required() {
        let env_map = BTreeMap::new();
        let cfg = parse_cli_args(&[], &env_map).unwrap();
        assert_eq!(evaluate_config(&cfg), CiSigningDecision::SkipAdHoc);
    }

    #[test]
    fn test_fail_when_no_credentials_and_required() {
        let mut env_map = BTreeMap::new();
        env_map.insert("REQUIRE_SIGNING".to_string(), "1".to_string());
        let cfg = parse_cli_args(&[], &env_map).unwrap();
        assert_eq!(
            evaluate_config(&cfg),
            CiSigningDecision::MissingRequiredCredentials
        );
    }

    #[test]
    fn test_import_plan_and_security_commands() {
        let mut env_map = BTreeMap::new();
        env_map.insert("SIGNING_CERT_P12".to_string(), "aGVsbG8=".to_string());
        env_map.insert("SIGNING_CERT_PASSWORD".to_string(), "s3cret".to_string());
        env_map.insert("RUNNER_TEMP".to_string(), "/tmp/runner".to_string());

        let cfg = parse_cli_args(&["--dry-run".to_string()], &env_map).unwrap();
        assert!(cfg.dry_run);
        let CiSigningDecision::Import(plan) = evaluate_config(&cfg) else {
            panic!("expected Import decision");
        };
        assert_eq!(
            plan.keychain_path,
            PathBuf::from("/tmp/runner/vitruvian-signing.keychain-db")
        );
        assert_eq!(
            plan.p12_path,
            PathBuf::from("/tmp/runner/vitruvian-signing.p12")
        );

        let existing = parse_keychain_list_output(
            "    \"/Users/runner/Library/Keychains/login.keychain-db\"\n    \"/Library/Keychains/System.keychain\"\n",
        );
        assert_eq!(
            existing,
            vec![
                "/Users/runner/Library/Keychains/login.keychain-db".to_string(),
                "/Library/Keychains/System.keychain".to_string(),
            ]
        );

        let cmds = build_security_commands(&plan, &existing);
        assert_eq!(cmds.len(), 6);
        assert_eq!(
            cmds[0].args,
            vec![
                "create-keychain",
                "-p",
                "ci-signing",
                "/tmp/runner/vitruvian-signing.keychain-db"
            ]
        );
        assert_eq!(
            cmds[3].args,
            vec![
                "import",
                "/tmp/runner/vitruvian-signing.p12",
                "-k",
                "/tmp/runner/vitruvian-signing.keychain-db",
                "-P",
                "s3cret",
                "-T",
                "/usr/bin/codesign"
            ]
        );
        assert_eq!(
            cmds[5].args,
            vec![
                "list-keychains",
                "-d",
                "user",
                "-s",
                "/tmp/runner/vitruvian-signing.keychain-db",
                "/Users/runner/Library/Keychains/login.keychain-db",
                "/Library/Keychains/System.keychain",
            ]
        );
    }

    #[test]
    fn test_base64_decode() {
        let decoded = decode_base64("SGVsbG8gVml0cnV2aWFuIQ==\n").unwrap();
        assert_eq!(decoded, b"Hello Vitruvian!");
    }
}
