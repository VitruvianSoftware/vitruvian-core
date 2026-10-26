// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT

//! Native Rust implementation of `Tools/setup-signing.sh`.
//! Creates a stable, self-signed code-signing identity named `"Vitruvian Signing"`
//! in a dedicated user keychain (`~/Library/Keychains/vitruvian-signing.keychain-db`).

use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

pub const IDENTITY_NAME: &str = "Vitruvian Signing";
pub const KEYCHAIN_REL_PATH: &str = "Library/Keychains/vitruvian-signing.keychain-db";
pub const KEYCHAIN_PASS: &str = "vitruvian-signing";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SetupSigningConfig {
    pub home_dir: PathBuf,
    pub identity: String,
    pub keychain_path: PathBuf,
    pub keychain_password: String,
    pub dry_run: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CommandSpec {
    pub program: String,
    pub args: Vec<String>,
    pub ignore_failure: bool,
    pub suppress_output: bool,
}

pub fn parse_cli_args(args: &[String], home_dir: &Path) -> Result<SetupSigningConfig, String> {
    let mut dry_run = false;
    for arg in args {
        match arg.as_str() {
            "--dry-run" => dry_run = true,
            "-h" | "--help" => {
                return Err("usage: setup-signing [--dry-run]".to_string());
            }
            other => {
                return Err(format!("setup-signing: unknown argument '{}'", other));
            }
        }
    }

    Ok(SetupSigningConfig {
        home_dir: home_dir.to_path_buf(),
        identity: IDENTITY_NAME.to_string(),
        keychain_path: home_dir.join(KEYCHAIN_REL_PATH),
        keychain_password: KEYCHAIN_PASS.to_string(),
        dry_run,
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

pub fn build_openssl_commands(cfg: &SetupSigningConfig, work_dir: &Path) -> Vec<CommandSpec> {
    let key_pem = work_dir.join("key.pem").to_string_lossy().to_string();
    let cert_pem = work_dir.join("cert.pem").to_string_lossy().to_string();
    let id_p12 = work_dir.join("id.p12").to_string_lossy().to_string();

    vec![
        CommandSpec {
            program: "openssl".to_string(),
            args: vec![
                "req".to_string(),
                "-x509".to_string(),
                "-newkey".to_string(),
                "rsa:2048".to_string(),
                "-keyout".to_string(),
                key_pem.clone(),
                "-out".to_string(),
                cert_pem.clone(),
                "-days".to_string(),
                "3650".to_string(),
                "-nodes".to_string(),
                "-subj".to_string(),
                format!("/CN={}/O=Vitruvian", cfg.identity),
                "-addext".to_string(),
                "keyUsage=critical,digitalSignature".to_string(),
                "-addext".to_string(),
                "extendedKeyUsage=critical,codeSigning".to_string(),
                "-addext".to_string(),
                "basicConstraints=critical,CA:false".to_string(),
            ],
            ignore_failure: false,
            suppress_output: true,
        },
        CommandSpec {
            program: "openssl".to_string(),
            args: vec![
                "pkcs12".to_string(),
                "-export".to_string(),
                "-inkey".to_string(),
                key_pem,
                "-in".to_string(),
                cert_pem,
                "-out".to_string(),
                id_p12,
                "-passout".to_string(),
                format!("pass:{}", cfg.keychain_password),
                "-name".to_string(),
                cfg.identity.clone(),
                "-keypbe".to_string(),
                "PBE-SHA1-3DES".to_string(),
                "-certpbe".to_string(),
                "PBE-SHA1-3DES".to_string(),
                "-macalg".to_string(),
                "sha1".to_string(),
            ],
            ignore_failure: false,
            suppress_output: false,
        },
    ]
}

pub fn build_keychain_setup_commands(
    cfg: &SetupSigningConfig,
    work_dir: &Path,
    existing_keychains: &[String],
) -> Vec<CommandSpec> {
    let kc = cfg.keychain_path.to_string_lossy().to_string();
    let kcpass = cfg.keychain_password.clone();
    let id_p12 = work_dir.join("id.p12").to_string_lossy().to_string();

    let mut search_args = vec![
        "list-keychains".to_string(),
        "-d".to_string(),
        "user".to_string(),
        "-s".to_string(),
        kc.clone(),
    ];
    for k in existing_keychains {
        if k != &kc {
            search_args.push(k.clone());
        }
    }

    vec![
        CommandSpec {
            program: "security".to_string(),
            args: vec!["delete-keychain".to_string(), kc.clone()],
            ignore_failure: true,
            suppress_output: true,
        },
        CommandSpec {
            program: "security".to_string(),
            args: vec![
                "create-keychain".to_string(),
                "-p".to_string(),
                kcpass.clone(),
                kc.clone(),
            ],
            ignore_failure: false,
            suppress_output: false,
        },
        CommandSpec {
            program: "security".to_string(),
            args: vec!["set-keychain-settings".to_string(), kc.clone()],
            ignore_failure: false,
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
            ignore_failure: false,
            suppress_output: false,
        },
        CommandSpec {
            program: "security".to_string(),
            args: vec![
                "import".to_string(),
                id_p12,
                "-k".to_string(),
                kc.clone(),
                "-P".to_string(),
                kcpass.clone(),
                "-T".to_string(),
                "/usr/bin/codesign".to_string(),
            ],
            ignore_failure: false,
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
            ignore_failure: false,
            suppress_output: true,
        },
        CommandSpec {
            program: "security".to_string(),
            args: search_args,
            ignore_failure: false,
            suppress_output: false,
        },
    ]
}

pub fn identity_can_sign(cfg: &SetupSigningConfig) -> bool {
    let _ = Command::new("security")
        .args([
            "unlock-keychain",
            "-p",
            &cfg.keychain_password,
            &cfg.keychain_path.to_string_lossy(),
        ])
        .output();

    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    let probe = env::temp_dir().join(format!(
        "vitruvian_sign_probe_{}_{}",
        std::process::id(),
        nanos
    ));
    if fs::copy("/bin/echo", &probe).is_err() {
        return false;
    }

    let ok = Command::new("codesign")
        .args([
            "--force",
            "--strip-disallowed-xattrs",
            "--sign",
            &cfg.identity,
            &probe.to_string_lossy(),
        ])
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false);

    let _ = fs::remove_file(&probe);
    ok
}

fn run_command_spec(spec: &CommandSpec) -> bool {
    if spec.suppress_output {
        Command::new(&spec.program)
            .args(&spec.args)
            .output()
            .map(|o| o.status.success() || spec.ignore_failure)
            .unwrap_or(spec.ignore_failure)
    } else {
        Command::new(&spec.program)
            .args(&spec.args)
            .status()
            .map(|s| s.success() || spec.ignore_failure)
            .unwrap_or(spec.ignore_failure)
    }
}

pub fn run_cli(args: &[String]) -> i32 {
    let home = env::var("HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("/tmp"));
    let cfg = match parse_cli_args(args, &home) {
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

    if cfg.dry_run {
        let work_dir = PathBuf::from("/tmp/vitruvian-setup-signing-work");
        for spec in build_openssl_commands(&cfg, &work_dir) {
            println!("dry-run: {} {}", spec.program, spec.args.join(" "));
        }
        for spec in
            build_keychain_setup_commands(&cfg, &work_dir, &["login.keychain-db".to_string()])
        {
            println!("dry-run: {} {}", spec.program, spec.args.join(" "));
        }
        return 0;
    }

    if identity_can_sign(&cfg) {
        println!("✓ Signing identity already installed.");
        return 0;
    }

    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    let work_dir = env::temp_dir().join(format!(
        "vitruvian_setup_signing_{}_{}",
        std::process::id(),
        nanos
    ));
    if let Err(e) = fs::create_dir_all(&work_dir) {
        eprintln!("✗ failed to create temp work directory: {}", e);
        return 1;
    }

    let openssl_cmds = build_openssl_commands(&cfg, &work_dir);
    if !run_command_spec(&openssl_cmds[0]) {
        let _ = fs::remove_dir_all(&work_dir);
        eprintln!("✗ openssl req failed.");
        return 1;
    }
    if !run_command_spec(&openssl_cmds[1]) {
        let _ = fs::remove_dir_all(&work_dir);
        eprintln!("✗ openssl pkcs12 could not export the identity.");
        return 1;
    }

    let existing_output = Command::new("security")
        .args(["list-keychains", "-d", "user"])
        .output()
        .ok()
        .map(|o| String::from_utf8_lossy(&o.stdout).to_string())
        .unwrap_or_default();
    let existing = parse_keychain_list_output(&existing_output);

    let kc_cmds = build_keychain_setup_commands(&cfg, &work_dir, &existing);
    for spec in &kc_cmds {
        if !run_command_spec(spec) {
            let _ = fs::remove_dir_all(&work_dir);
            return 1;
        }
    }

    let _ = fs::remove_dir_all(&work_dir);

    if !identity_can_sign(&cfg) {
        eprintln!("✗ Identity imported but codesign cannot sign with it; keychain search list may be off.");
        return 1;
    }

    println!(
        "✓ Created signing identity '{}'. Future ./build.sh runs use it automatically.",
        cfg.identity
    );
    0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_cli_args() {
        let cfg = parse_cli_args(&["--dry-run".to_string()], Path::new("/Users/tester")).unwrap();
        assert!(cfg.dry_run);
        assert_eq!(cfg.identity, "Vitruvian Signing");
        assert_eq!(
            cfg.keychain_path,
            PathBuf::from("/Users/tester/Library/Keychains/vitruvian-signing.keychain-db")
        );
        assert_eq!(cfg.keychain_password, "vitruvian-signing");
    }

    #[test]
    fn test_openssl_and_keychain_commands_preserve_pbe_and_extensions() {
        let cfg = parse_cli_args(&[], Path::new("/Users/tester")).unwrap();
        let work = Path::new("/tmp/work");
        let openssl_cmds = build_openssl_commands(&cfg, work);
        assert_eq!(openssl_cmds.len(), 2);
        assert!(openssl_cmds[0]
            .args
            .contains(&"/CN=Vitruvian Signing/O=Vitruvian".to_string()));
        assert!(openssl_cmds[0]
            .args
            .contains(&"extendedKeyUsage=critical,codeSigning".to_string()));
        assert!(openssl_cmds[1].args.contains(&"PBE-SHA1-3DES".to_string()));
        assert!(openssl_cmds[1].args.contains(&"sha1".to_string()));

        let kc_cmds = build_keychain_setup_commands(
            &cfg,
            work,
            &["/Users/tester/Library/Keychains/login.keychain-db".to_string()],
        );
        assert_eq!(kc_cmds.len(), 7);
        assert_eq!(kc_cmds[0].args[0], "delete-keychain");
        assert!(kc_cmds[0].ignore_failure);
        assert_eq!(kc_cmds[4].args[0], "import");
        assert_eq!(
            kc_cmds[6].args,
            vec![
                "list-keychains",
                "-d",
                "user",
                "-s",
                "/Users/tester/Library/Keychains/vitruvian-signing.keychain-db",
                "/Users/tester/Library/Keychains/login.keychain-db",
            ]
        );
    }
}
