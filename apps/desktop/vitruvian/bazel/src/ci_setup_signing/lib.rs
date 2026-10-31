// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Copyright (C) 2026 VitruvianSoftware

//! Imports the stable signing certificate into a keychain on CI so the
//! release signs with the same identity used locally. This keeps the
//! bundle's designated requirement constant, so users keep their granted
//! permissions across updates. No-op (and an ad-hoc build) when the secret
//! isn't configured, unless REQUIRE_SIGNING=1. Ported from upstream's
//! `Tools/ci-setup-signing.sh`.
//!
//!   SIGNING_CERT_P12       base64 of the .p12
//!   SIGNING_CERT_PASSWORD  its password
//!   RUNNER_TEMP            where the keychain goes (/tmp otherwise)

use release_exec::{capture, run, write_private, Cmd, Runner};
use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};

pub const KEYCHAIN_PASSWORD: &str = "ci-signing";
pub const KEYCHAIN_FILENAME: &str = "vitruvian-signing.keychain-db";
pub const P12_FILENAME: &str = "vitruvian-signing.p12";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CiSigningConfig {
    pub signing_cert_p12: String,
    pub signing_cert_password: String,
    pub require_signing: bool,
    pub runner_temp: PathBuf,
}

impl CiSigningConfig {
    pub fn from_env(env_map: &BTreeMap<String, String>) -> CiSigningConfig {
        let get = |k: &str| env_map.get(k).cloned().unwrap_or_default();
        CiSigningConfig {
            signing_cert_p12: get("SIGNING_CERT_P12"),
            signing_cert_password: get("SIGNING_CERT_PASSWORD"),
            require_signing: get("REQUIRE_SIGNING") == "1",
            runner_temp: env_map
                .get("RUNNER_TEMP")
                .filter(|s| !s.is_empty())
                .map(PathBuf::from)
                .unwrap_or_else(|| PathBuf::from("/tmp")),
        }
    }

    pub fn keychain(&self) -> PathBuf {
        self.runner_temp.join(KEYCHAIN_FILENAME)
    }

    pub fn p12(&self) -> PathBuf {
        self.runner_temp.join(P12_FILENAME)
    }
}

/// The search list `security list-keychains -d user` prints, as
/// `sed 's/"//g' | xargs` turns it into words.
pub fn parse_keychain_list_output(output: &str) -> Vec<String> {
    output
        .replace('"', "")
        .split_whitespace()
        .map(String::from)
        .collect()
}

fn security(args: &[&str]) -> Cmd {
    Cmd::new("security").args(args)
}

fn restrict(path: &Path) {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = fs::set_permissions(path, fs::Permissions::from_mode(0o600));
    }
}

pub fn ci_setup_signing(r: &mut dyn Runner, cfg: &CiSigningConfig) -> Result<(), i32> {
    if cfg.signing_cert_p12.is_empty() || cfg.signing_cert_password.is_empty() {
        if cfg.require_signing {
            eprintln!("Release signing credentials are incomplete.");
            return Err(1);
        }
        println!("No release signing credentials — building ad-hoc.");
        return Ok(());
    }

    let kc = cfg.keychain().to_string_lossy().to_string();
    let p12 = cfg.p12();
    let bytes = release_exec::decode_base64(&cfg.signing_cert_p12).map_err(|e| {
        eprintln!("SIGNING_CERT_P12 is not base64: {}", e);
        1
    })?;
    write_private(&p12, &bytes).map_err(|e| {
        eprintln!("could not write {}: {}", p12.display(), e);
        1
    })?;

    let result = (|| {
        run(
            r,
            &security(&["create-keychain", "-p", KEYCHAIN_PASSWORD, &kc]),
        )?;
        restrict(&cfg.keychain());
        run(r, &security(&["set-keychain-settings", &kc]))?;
        run(
            r,
            &security(&["unlock-keychain", "-p", KEYCHAIN_PASSWORD, &kc]),
        )?;
        run(
            r,
            &security(&["import"]).path(&p12).args([
                "-k",
                &kc,
                "-P",
                &cfg.signing_cert_password,
                "-T",
                "/usr/bin/codesign",
            ]),
        )?;
        capture(
            r,
            &security(&[
                "set-key-partition-list",
                "-S",
                "apple-tool:,apple:,codesign:",
                "-s",
                "-k",
                KEYCHAIN_PASSWORD,
                &kc,
            ]),
        )?;
        let existing =
            parse_keychain_list_output(&capture(r, &security(&["list-keychains", "-d", "user"]))?);
        run(
            r,
            &security(&["list-keychains", "-d", "user", "-s", &kc]).args(&existing),
        )
    })();
    let _ = fs::remove_file(&p12);
    result?;
    println!("Signing certificate imported.");
    Ok(())
}

pub fn run_cli(args: &[String]) -> i32 {
    if !args.is_empty() {
        eprintln!("usage: ci_setup_signing (env: SIGNING_CERT_P12, SIGNING_CERT_PASSWORD, REQUIRE_SIGNING, RUNNER_TEMP)");
        return 2;
    }
    let env_map: BTreeMap<String, String> = std::env::vars().collect();
    match ci_setup_signing(
        &mut release_exec::SystemRunner::new(),
        &CiSigningConfig::from_env(&env_map),
    ) {
        Ok(()) => 0,
        Err(code) => code,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use release_exec::{make_temp_dir, FakeRunner, Out, TempDir};

    fn env(pairs: &[(&str, &str)]) -> BTreeMap<String, String> {
        pairs
            .iter()
            .map(|(k, v)| (k.to_string(), v.to_string()))
            .collect()
    }

    #[test]
    fn without_credentials_it_builds_ad_hoc_unless_signing_is_required() {
        let mut r = FakeRunner::succeeding();
        let cfg = CiSigningConfig::from_env(&env(&[("SIGNING_CERT_P12", "eA==")]));
        assert_eq!(ci_setup_signing(&mut r, &cfg), Ok(()));
        let required = CiSigningConfig::from_env(&env(&[
            ("SIGNING_CERT_PASSWORD", "pw"),
            ("REQUIRE_SIGNING", "1"),
        ]));
        assert_eq!(ci_setup_signing(&mut r, &required), Err(1));
        assert!(r.calls.is_empty());
    }

    #[test]
    fn the_keychain_goes_in_runner_temp_or_tmp() {
        assert_eq!(
            CiSigningConfig::from_env(&env(&[])).keychain(),
            PathBuf::from("/tmp/vitruvian-signing.keychain-db")
        );
        assert_eq!(
            CiSigningConfig::from_env(&env(&[("RUNNER_TEMP", "/r")])).p12(),
            PathBuf::from("/r/vitruvian-signing.p12")
        );
    }

    #[test]
    fn keychain_list_drops_quotes() {
        assert_eq!(
            parse_keychain_list_output("    \"/Users/runner/Library/Keychains/login.keychain-db\"\n    \"/Library/Keychains/System.keychain\"\n"),
            vec!["/Users/runner/Library/Keychains/login.keychain-db", "/Library/Keychains/System.keychain"]
        );
    }

    #[test]
    fn it_imports_into_its_own_keychain_and_puts_it_first_in_the_search_list() {
        let tmp = make_temp_dir(&std::env::temp_dir(), "ci_setup_signing").unwrap();
        let _g = TempDir(tmp.clone());
        let cfg = CiSigningConfig::from_env(&env(&[
            ("SIGNING_CERT_P12", "aGVsbG8="),
            ("SIGNING_CERT_PASSWORD", "pw"),
            ("RUNNER_TEMP", &tmp.to_string_lossy()),
        ]));
        let p12 = cfg.p12();
        let p12_seen = p12.clone();
        let mut r = FakeRunner::new(move |c| {
            if c.args.first().map(String::as_str) == Some("import") {
                assert_eq!(fs::read(&p12_seen).unwrap(), b"hello");
                #[cfg(unix)]
                {
                    use std::os::unix::fs::PermissionsExt;
                    assert_eq!(
                        fs::metadata(&p12_seen).unwrap().permissions().mode() & 0o777,
                        0o600
                    );
                }
            }
            if c.args == ["list-keychains", "-d", "user"] {
                return Out::ok("    \"/Users/runner/Library/Keychains/login.keychain-db\"\n");
            }
            Out::ok("")
        });
        assert_eq!(ci_setup_signing(&mut r, &cfg), Ok(()));
        let kc = cfg.keychain().to_string_lossy().to_string();
        assert_eq!(
            r.calls,
            vec![
                format!("security create-keychain -p ci-signing {}", kc),
                format!("security set-keychain-settings {}", kc),
                format!("security unlock-keychain -p ci-signing {}", kc),
                format!("security import {} -k {} -P pw -T /usr/bin/codesign", p12.display(), kc),
                format!("security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k ci-signing {}", kc),
                "security list-keychains -d user".to_string(),
                format!("security list-keychains -d user -s {} /Users/runner/Library/Keychains/login.keychain-db", kc),
            ]
        );
        assert!(!p12.exists(), "the p12 is removed");
    }

    #[test]
    fn a_failed_import_fails_with_its_code_and_still_removes_the_p12() {
        let tmp = make_temp_dir(&std::env::temp_dir(), "ci_setup_signing_fail").unwrap();
        let _g = TempDir(tmp.clone());
        let cfg = CiSigningConfig::from_env(&env(&[
            ("SIGNING_CERT_P12", "aGVsbG8="),
            ("SIGNING_CERT_PASSWORD", "wrong"),
            ("RUNNER_TEMP", &tmp.to_string_lossy()),
        ]));
        let mut r = FakeRunner::new(|c| {
            if c.args.first().map(String::as_str) == Some("import") {
                Out::fail(35, "MAC verification failed")
            } else {
                Out::ok("")
            }
        });
        assert_eq!(ci_setup_signing(&mut r, &cfg), Err(35));
        assert_eq!(r.count("security list-keychains"), 0);
        assert!(!cfg.p12().exists());
    }
}
