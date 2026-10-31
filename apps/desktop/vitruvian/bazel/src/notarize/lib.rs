// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Copyright (C) 2026 VitruvianSoftware

//! Notarizes and staples a built artifact (the .app or the .dmg) with Apple's
//! notary service, so Gatekeeper opens it without the "unverified developer"
//! warning. The release runs it once on each app (before packaging) and once
//! on each DMG. Ported from upstream's `Tools/notarize.sh`.
//!
//! Credentials come from the environment (CI secrets):
//!   NOTARY_API_KEY_P8   base64 of the App Store Connect API key (.p8)
//!   NOTARY_KEY_ID       the key's ID
//!   NOTARY_ISSUER_ID    the issuer UUID
//!
//! When the credentials are absent it skips quietly (success), so a plain
//! build without notarization still succeeds, unless REQUIRE_NOTARIZATION=1.

use release_exec::{make_temp_dir, remove_on_signal, run, write_private, Cmd, Runner, TempDir};
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

pub const USAGE: &str = "usage: notarize <app-or-dmg>";

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct NotaryEnv {
    pub api_key_p8: String,
    pub key_id: String,
    pub issuer_id: String,
    pub require_notarization: bool,
}

impl NotaryEnv {
    pub fn from_env(env_map: &BTreeMap<String, String>) -> NotaryEnv {
        let get = |k: &str| env_map.get(k).cloned().unwrap_or_default();
        NotaryEnv {
            api_key_p8: get("NOTARY_API_KEY_P8"),
            key_id: get("NOTARY_KEY_ID"),
            issuer_id: get("NOTARY_ISSUER_ID"),
            require_notarization: get("REQUIRE_NOTARIZATION") == "1",
        }
    }

    pub fn complete(&self) -> bool {
        !self.api_key_p8.is_empty() && !self.key_id.is_empty() && !self.issuer_id.is_empty()
    }
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

/// The one target the command line names, or the usage line.
pub fn parse_cli_args(args: &[String]) -> Result<String, String> {
    match args {
        [one] if !one.is_empty() => Ok(one.clone()),
        _ => Err(USAGE.to_string()),
    }
}

/// What a submission of `target` runs, with the key written to `work_dir`.
pub fn plan(target: &Path, creds: &NotaryEnv, work_dir: &Path) -> NotarizePlan {
    let is_app_bundle = target.to_string_lossy().ends_with(".app");
    let basename = target
        .file_name()
        .map(|f| f.to_string_lossy().to_string())
        .unwrap_or_default();
    NotarizePlan {
        target: target.to_path_buf(),
        is_app_bundle,
        submit_path: if is_app_bundle {
            work_dir.join(format!("{}.zip", basename))
        } else {
            target.to_path_buf()
        },
        p8_path: work_dir.join("AuthKey.p8"),
        key_id: creds.key_id.clone(),
        issuer_id: creds.issuer_id.clone(),
    }
}

/// notarytool needs a zip/dmg/pkg. A .app is zipped first; a .dmg is
/// submitted as-is. Stapling always targets the original artifact.
pub fn build_notarize_commands(plan: &NotarizePlan) -> Vec<Cmd> {
    let mut cmds = Vec::new();
    if plan.is_app_bundle {
        cmds.push(Cmd::new("xattr").arg("-cr").path(&plan.target));
        cmds.push(
            Cmd::new("codesign")
                .args(["--verify", "--deep", "--strict"])
                .path(&plan.target),
        );
        cmds.push(
            Cmd::new("/usr/bin/ditto")
                .args(["-c", "-k", "--keepParent"])
                .path(&plan.target)
                .path(&plan.submit_path),
        );
    }
    cmds.push(
        Cmd::new("xcrun")
            .args(["notarytool", "submit"])
            .path(&plan.submit_path)
            .arg("--key")
            .path(&plan.p8_path)
            .args([
                "--key-id",
                &plan.key_id,
                "--issuer",
                &plan.issuer_id,
                "--wait",
            ]),
    );
    cmds.push(
        Cmd::new("xcrun")
            .args(["stapler", "staple"])
            .path(&plan.target),
    );
    cmds
}

/// Notarizes and staples `target`. Its work folder (the key, the app's zip)
/// is made under `tmp_root` and removed whatever happens.
pub fn notarize(
    r: &mut dyn Runner,
    target: &Path,
    creds: &NotaryEnv,
    tmp_root: &Path,
) -> Result<(), i32> {
    if !creds.complete() {
        if creds.require_notarization {
            eprintln!("Release notarization credentials are incomplete.");
            return Err(1);
        }
        println!(
            "No notarization credentials in the environment — skipping ({}).",
            target.display()
        );
        return Ok(());
    }
    if !target.exists() {
        eprintln!("✗ {} not found", target.display());
        return Err(1);
    }

    let work = make_temp_dir(tmp_root, "vitruvian-notarize").map_err(|e| {
        eprintln!("✗ could not make a work folder: {}", e);
        1
    })?;
    let _cleanup = TempDir(work.clone());
    let _on_signal_dir = remove_on_signal(&work);
    let p = plan(target, creds, &work);

    let key = release_exec::decode_base64(&creds.api_key_p8).map_err(|e| {
        eprintln!("✗ NOTARY_API_KEY_P8 is not base64: {}", e);
        1
    })?;
    let _on_signal_key = remove_on_signal(&p.p8_path);
    write_private(&p.p8_path, &key).map_err(|e| {
        eprintln!("✗ could not write AuthKey.p8: {}", e);
        1
    })?;

    let name = target
        .file_name()
        .map(|f| f.to_string_lossy().to_string())
        .unwrap_or_default();
    for cmd in build_notarize_commands(&p) {
        match cmd.args.first().map(String::as_str) {
            Some("notarytool") => println!(
                "▸ Submitting {} to the notary service (can take a few minutes)…",
                name
            ),
            // Staple the ticket so it is recognized even offline. Fails (and
            // fails the release) if notarization did not actually succeed,
            // so a bad result never ships.
            Some("stapler") => println!("▸ Stapling {}…", name),
            _ => {}
        }
        run(r, &cmd)?;
    }
    println!("✓ Notarized and stapled: {}", name);
    Ok(())
}

pub fn run_cli(args: &[String]) -> i32 {
    let target = match parse_cli_args(args) {
        Ok(t) => t,
        Err(msg) => {
            eprintln!("{}", msg);
            return 1;
        }
    };
    let env_map: BTreeMap<String, String> = std::env::vars().collect();
    let creds = NotaryEnv::from_env(&env_map);
    let mut r = release_exec::SystemRunner::from_env();
    match notarize(
        &mut r,
        &release_exec::user_path(&target),
        &creds,
        &release_exec::temp_root(),
    ) {
        Ok(()) => 0,
        Err(code) => code,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use release_exec::{FakeRunner, Out};
    use std::fs;

    fn creds() -> NotaryEnv {
        NotaryEnv {
            api_key_p8: "aGVsbG8=".into(),
            key_id: "KEY123".into(),
            issuer_id: "ISSUER456".into(),
            require_notarization: false,
        }
    }

    fn scratch(name: &str) -> PathBuf {
        let d = make_temp_dir(&std::env::temp_dir(), name).unwrap();
        fs::create_dir_all(d.join("tmp")).unwrap();
        d
    }

    #[test]
    fn usage_needs_exactly_one_target() {
        assert_eq!(parse_cli_args(&[]), Err(USAGE.to_string()));
        assert_eq!(parse_cli_args(&["".into()]), Err(USAGE.to_string()));
        assert_eq!(parse_cli_args(&["a.dmg".into()]), Ok("a.dmg".to_string()));
    }

    #[test]
    fn credentials_come_from_the_three_variables() {
        let mut env_map = BTreeMap::new();
        env_map.insert("NOTARY_API_KEY_P8".into(), "x".into());
        env_map.insert("NOTARY_KEY_ID".into(), "k".into());
        assert!(!NotaryEnv::from_env(&env_map).complete());
        env_map.insert("NOTARY_ISSUER_ID".into(), "i".into());
        env_map.insert("REQUIRE_NOTARIZATION".into(), "1".into());
        let c = NotaryEnv::from_env(&env_map);
        assert!(c.complete() && c.require_notarization);
    }

    #[test]
    fn skips_quietly_without_credentials_and_runs_nothing() {
        let mut r = FakeRunner::succeeding();
        let none = NotaryEnv::default();
        assert_eq!(
            notarize(
                &mut r,
                Path::new("/nowhere/x.dmg"),
                &none,
                Path::new("/tmp")
            ),
            Ok(())
        );
        assert!(r.calls.is_empty());
    }

    #[test]
    fn fails_without_credentials_when_they_are_required() {
        let mut r = FakeRunner::succeeding();
        let required = NotaryEnv {
            require_notarization: true,
            ..NotaryEnv::default()
        };
        assert_eq!(
            notarize(
                &mut r,
                Path::new("/nowhere/x.dmg"),
                &required,
                Path::new("/tmp")
            ),
            Err(1)
        );
        assert!(r.calls.is_empty());
    }

    #[test]
    fn a_missing_target_fails_before_any_command() {
        let mut r = FakeRunner::succeeding();
        assert_eq!(
            notarize(
                &mut r,
                Path::new("/nowhere/x.dmg"),
                &creds(),
                Path::new("/tmp")
            ),
            Err(1)
        );
        assert!(r.calls.is_empty());
    }

    #[test]
    fn an_app_is_verified_zipped_submitted_and_stapled_with_a_private_key() {
        let d = scratch("notarize_app");
        let _g = TempDir(d.clone());
        let app = d.join("Vitruvian.app");
        fs::create_dir_all(&app).unwrap();
        let tmp = d.join("tmp");
        let seen_key = std::rc::Rc::new(std::cell::RefCell::new(None));
        let seen = seen_key.clone();
        let mut r = FakeRunner::new(move |c| {
            if c.args.first().map(String::as_str) == Some("notarytool") {
                let key = PathBuf::from(&c.args[4]);
                #[cfg(unix)]
                {
                    use std::os::unix::fs::PermissionsExt;
                    let mode = fs::metadata(&key).unwrap().permissions().mode() & 0o777;
                    *seen.borrow_mut() = Some((fs::read(&key).unwrap(), mode));
                }
            }
            Out::ok("")
        });
        assert_eq!(notarize(&mut r, &app, &creds(), &tmp), Ok(()));
        let app_s = app.to_string_lossy().to_string();
        assert_eq!(r.calls.len(), 5);
        assert_eq!(r.calls[0], format!("xattr -cr {}", app_s));
        assert_eq!(
            r.calls[1],
            format!("codesign --verify --deep --strict {}", app_s)
        );
        assert!(r.calls[2].starts_with(&format!("/usr/bin/ditto -c -k --keepParent {} ", app_s)));
        assert!(r.calls[2].ends_with("/Vitruvian.app.zip"));
        assert!(r.calls[3].starts_with("xcrun notarytool submit "));
        assert!(r.calls[3].contains("/Vitruvian.app.zip --key "));
        assert!(r.calls[3].ends_with("/AuthKey.p8 --key-id KEY123 --issuer ISSUER456 --wait"));
        assert_eq!(r.calls[4], format!("xcrun stapler staple {}", app_s));
        #[cfg(unix)]
        assert_eq!(*seen_key.borrow(), Some((b"hello".to_vec(), 0o600)));
        // The work folder, key included, is gone afterwards.
        assert_eq!(fs::read_dir(&tmp).unwrap().count(), 0);
    }

    #[test]
    fn a_dmg_is_submitted_as_is_and_a_failed_submission_fails_with_its_code() {
        let d = scratch("notarize_dmg");
        let _g = TempDir(d.clone());
        let dmg = d.join("Vitruvian-1.2.3.dmg");
        fs::write(&dmg, b"dmg").unwrap();
        let tmp = d.join("tmp");
        let mut r = FakeRunner::succeeding();
        assert_eq!(notarize(&mut r, &dmg, &creds(), &tmp), Ok(()));
        let dmg_s = dmg.to_string_lossy().to_string();
        assert_eq!(r.calls.len(), 2);
        assert!(r.calls[0].starts_with(&format!("xcrun notarytool submit {} --key ", dmg_s)));
        assert_eq!(r.calls[1], format!("xcrun stapler staple {}", dmg_s));

        let mut failing = FakeRunner::new(|c| {
            if c.args.first().map(String::as_str) == Some("notarytool") {
                Out::fail(69, "Invalid")
            } else {
                Out::ok("")
            }
        });
        assert_eq!(notarize(&mut failing, &dmg, &creds(), &tmp), Err(69));
        assert_eq!(failing.count("xcrun stapler"), 0);
        assert_eq!(fs::read_dir(&tmp).unwrap().count(), 0);
    }
}
