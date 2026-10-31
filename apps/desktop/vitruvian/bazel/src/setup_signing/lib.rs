// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Copyright (C) 2026 VitruvianSoftware

//! Creates a stable, self-signed code-signing identity named "Vitruvian
//! Signing" in a dedicated keychain. build.sh runs it (through
//! `bazel run //apps/desktop/vitruvian:setup_signing`) for a build that
//! installs, giving every build the same code signature, so macOS keeps
//! granted permissions (Accessibility, Screen Recording) across updates
//! instead of re-prompting. Ported from upstream's `Tools/setup-signing.sh`.
//!
//! The identity name keeps its original "Vitruvian Signing" on purpose: it is
//! the lookup key build.sh matches, and the released app's designated
//! requirement is pinned to this exact certificate. Renaming it would change
//! that requirement and drop every user's granted permissions. The name lives
//! only in the keychain and codesign output, never in anything the app shows.
//!
//! Free, offline, and idempotent (re-running is a no-op once a working
//! identity exists). It does NOT replace Apple notarization. Official
//! releases use the protected release-signing environment (ci_setup_signing).

use release_exec::{capture, make_temp_dir, run, Cmd, Runner, TempDir};
use std::fs;
use std::path::{Path, PathBuf};

pub const IDENTITY_NAME: &str = "Vitruvian Signing";
pub const KEYCHAIN_REL_PATH: &str = "Library/Keychains/vitruvian-signing.keychain-db";
pub const KEYCHAIN_PASS: &str = "vitruvian-signing";

pub fn keychain_path(home: &Path) -> PathBuf {
    home.join(KEYCHAIN_REL_PATH)
}

pub fn parse_keychain_list_output(output: &str) -> Vec<String> {
    output
        .replace('"', "")
        .split_whitespace()
        .map(String::from)
        .collect()
}

/// Whether codesign can sign with the identity. A find-identity listing also
/// names certificates codesign then rejects, and -v excludes every
/// self-signed one; ask codesign itself, with a throwaway copy of /bin/echo.
pub fn identity_can_sign(r: &mut dyn Runner, keychain: &Path, tmp_root: &Path) -> bool {
    // Locked after every reboot; a locked keychain cannot sign, and a false
    // answer here would delete it and reissue the identity.
    let _ = r.output(
        &Cmd::new("security")
            .args(["unlock-keychain", "-p", KEYCHAIN_PASS])
            .path(keychain),
    );
    let Ok(dir) = make_temp_dir(tmp_root, "vitruvian-sign-probe") else {
        return false;
    };
    let _cleanup = TempDir(dir.clone());
    let probe = dir.join("probe");
    if fs::copy("/bin/echo", &probe).is_err() {
        return false;
    }
    r.output(
        &Cmd::new("codesign")
            .args([
                "--force",
                "--strip-disallowed-xattrs",
                "--sign",
                IDENTITY_NAME,
            ])
            .path(&probe),
    )
    .success()
}

pub fn openssl_commands(work: &Path) -> (Cmd, Cmd) {
    let key = work.join("key.pem");
    let cert = work.join("cert.pem");
    let req = Cmd::new("openssl")
        .args(["req", "-x509", "-newkey", "rsa:2048", "-keyout"])
        .path(&key)
        .arg("-out")
        .path(&cert)
        .args(["-days", "3650", "-nodes", "-subj"])
        .arg(format!("/CN={}/O=Vitruvian", IDENTITY_NAME))
        .args([
            "-addext",
            "keyUsage=critical,digitalSignature",
            "-addext",
            "extendedKeyUsage=critical,codeSigning",
            "-addext",
            "basicConstraints=critical,CA:false",
        ]);
    // The PBE and MAC algorithms are named explicitly: the stock
    // /usr/bin/openssl is LibreSSL, which rejects OpenSSL 3's -legacy flag,
    // while OpenSSL 3's defaults (AES-256, PBKDF2) are newer than what
    // security(1) imports reliably. These three are accepted by both and
    // produce the same portable file.
    let export = Cmd::new("openssl")
        .args(["pkcs12", "-export", "-inkey"])
        .path(&key)
        .arg("-in")
        .path(&cert)
        .arg("-out")
        .path(&work.join("id.p12"))
        .args([
            "-passout",
            &format!("pass:{}", KEYCHAIN_PASS),
            "-name",
            IDENTITY_NAME,
        ])
        .args([
            "-keypbe",
            "PBE-SHA1-3DES",
            "-certpbe",
            "PBE-SHA1-3DES",
            "-macalg",
            "sha1",
        ]);
    (req, export)
}

pub fn setup_signing(r: &mut dyn Runner, home: &Path, tmp_root: &Path) -> Result<(), i32> {
    let kc_path = keychain_path(home);
    let kc = kc_path.to_string_lossy().to_string();
    if identity_can_sign(r, &kc_path, tmp_root) {
        println!("✓ Signing identity already installed.");
        return Ok(());
    }

    let work = make_temp_dir(tmp_root, "vitruvian-setup-signing").map_err(|e| {
        eprintln!("✗ mktemp: {}", e);
        1
    })?;
    let _cleanup = TempDir(work.clone());
    // The private key and the p12 go too if a signal ends the run.
    let _on_signal: Vec<_> = [
        work.clone(),
        work.join("key.pem"),
        work.join("cert.pem"),
        work.join("id.p12"),
    ]
    .iter()
    .map(|p| release_exec::remove_on_signal(p))
    .collect();

    let (req, export) = openssl_commands(&work);
    let made = r.output(&req);
    if !made.success() {
        print!("{}", made.stdout);
        return Err(made.code);
    }
    if r.status(&export) != 0 {
        eprintln!("✗ openssl pkcs12 could not export the identity.");
        return Err(1);
    }

    let security = |args: &[&str]| Cmd::new("security").args(args);
    let _ = r.output(&security(&["delete-keychain", &kc]));
    run(r, &security(&["create-keychain", "-p", KEYCHAIN_PASS, &kc]))?;
    run(r, &security(&["set-keychain-settings", &kc]))?; // no auto-lock
    run(r, &security(&["unlock-keychain", "-p", KEYCHAIN_PASS, &kc]))?;
    run(
        r,
        &security(&["import"]).path(&work.join("id.p12")).args([
            "-k",
            &kc,
            "-P",
            KEYCHAIN_PASS,
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
            KEYCHAIN_PASS,
            &kc,
        ]),
    )?;
    let existing =
        parse_keychain_list_output(&capture(r, &security(&["list-keychains", "-d", "user"]))?);
    run(
        r,
        &security(&["list-keychains", "-d", "user", "-s", &kc]).args(&existing),
    )?;

    // Import succeeding is not evidence codesign can sign with it: read it
    // back the same way build.sh looks it up, so a broken search list fails
    // here and not as a silent ad-hoc fallback three builds later.
    if !identity_can_sign(r, &kc_path, tmp_root) {
        eprintln!("✗ Identity imported but codesign cannot sign with it; keychain search list may be off.");
        return Err(1);
    }
    println!(
        "✓ Created signing identity '{}'. Future ./build.sh runs use it automatically.",
        IDENTITY_NAME
    );
    Ok(())
}

pub fn run_cli(args: &[String]) -> i32 {
    if !args.is_empty() {
        eprintln!("usage: setup_signing");
        return 2;
    }
    let Some(home) = std::env::var_os("HOME").filter(|h| !h.is_empty()) else {
        eprintln!("✗ HOME is not set");
        return 1;
    };
    match setup_signing(
        &mut release_exec::SystemRunner::from_env(),
        Path::new(&home),
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
    use std::cell::Cell;
    use std::rc::Rc;

    fn scratch(name: &str) -> (TempDir, PathBuf, PathBuf) {
        let root = make_temp_dir(&std::env::temp_dir(), name).unwrap();
        let home = root.join("home");
        let tmp = root.join("tmp");
        fs::create_dir_all(&home).unwrap();
        fs::create_dir_all(&tmp).unwrap();
        (TempDir(root), home, tmp)
    }

    #[test]
    fn a_working_identity_is_left_alone() {
        let (_g, home, tmp) = scratch("setup_signing_noop");
        let mut r = FakeRunner::succeeding();
        assert_eq!(setup_signing(&mut r, &home, &tmp), Ok(()));
        assert_eq!(r.calls.len(), 2);
        assert!(r.calls[0].starts_with("security unlock-keychain -p vitruvian-signing "));
        assert!(r.calls[1]
            .starts_with("codesign --force --strip-disallowed-xattrs --sign Vitruvian Signing "));
        assert_eq!(
            fs::read_dir(&tmp).unwrap().count(),
            0,
            "the probe is removed"
        );
    }

    #[test]
    fn it_never_asks_for_legacy_or_a_find_identity_listing() {
        let (req, export) = openssl_commands(Path::new("/w"));
        assert!(!req.args.contains(&"-legacy".to_string()));
        assert!(!export.args.contains(&"-legacy".to_string()));
        assert_eq!(
            export.line(),
            "openssl pkcs12 -export -inkey /w/key.pem -in /w/cert.pem -out /w/id.p12 -passout pass:vitruvian-signing -name Vitruvian Signing -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1"
        );
    }

    #[test]
    fn a_new_identity_is_made_imported_and_read_back() {
        let (_g, home, tmp) = scratch("setup_signing_fake");
        let imported = Rc::new(Cell::new(false));
        let i2 = imported.clone();
        let mut r = FakeRunner::new(move |c| {
            match (c.program.as_str(), c.args.first().map(String::as_str)) {
                ("codesign", _) => {
                    if i2.get() {
                        Out::ok("")
                    } else {
                        Out::fail(1, "no identity found")
                    }
                }
                ("security", Some("import")) => {
                    i2.set(true);
                    Out::ok("")
                }
                ("security", Some("list-keychains")) if c.args.len() == 3 => {
                    Out::ok("    \"/stub/login.keychain-db\"\n")
                }
                _ => Out::ok(""),
            }
        });
        assert_eq!(setup_signing(&mut r, &home, &tmp), Ok(()));
        let kc = keychain_path(&home).to_string_lossy().to_string();
        let order: Vec<String> = r
            .calls
            .iter()
            .map(|c| c.split(' ').take(2).collect::<Vec<_>>().join(" "))
            .collect();
        assert_eq!(
            order,
            vec![
                "security unlock-keychain",
                "codesign --force",
                "openssl req",
                "openssl pkcs12",
                "security delete-keychain",
                "security create-keychain",
                "security set-keychain-settings",
                "security unlock-keychain",
                "security import",
                "security set-key-partition-list",
                "security list-keychains",
                "security list-keychains",
                "security unlock-keychain",
                "codesign --force",
            ]
        );
        assert_eq!(
            r.calls[11],
            format!(
                "security list-keychains -d user -s {} /stub/login.keychain-db",
                kc
            )
        );
        assert_eq!(
            fs::read_dir(&tmp).unwrap().count(),
            0,
            "work folder and probes are removed"
        );
    }

    #[test]
    fn an_identity_codesign_still_cannot_use_fails() {
        let (_g, home, tmp) = scratch("setup_signing_unusable");
        let mut r = FakeRunner::new(|c| {
            if c.program == "codesign" {
                Out::fail(1, "")
            } else {
                Out::ok("")
            }
        });
        assert_eq!(setup_signing(&mut r, &home, &tmp), Err(1));
        assert_eq!(r.count("codesign"), 2);
    }

    #[test]
    fn a_failed_export_says_so() {
        let (_g, home, tmp) = scratch("setup_signing_export");
        let mut r = FakeRunner::new(|c| {
            if c.program == "codesign" || c.args.first().map(String::as_str) == Some("pkcs12") {
                Out::fail(1, "")
            } else {
                Out::ok("")
            }
        });
        assert_eq!(setup_signing(&mut r, &home, &tmp), Err(1));
        assert_eq!(r.count("security"), 1, "no keychain is touched");
    }

    /// Runs against the Mac's stock /usr/bin/openssl, which is LibreSSL: it
    /// rejects OpenSSL 3's -legacy flag outright, and the script once died on
    /// exactly that with its stderr discarded. security(1) and codesign are
    /// stand-ins that log what they are asked and touch no keychain; the
    /// codesign stand-in refuses until the identity has been imported, as
    /// codesign does before one has been made. (Moved here from the app's
    /// RepositoryFeatureTests, which ran Tools/setup-signing.sh the same way.)
    #[cfg(target_os = "macos")]
    #[test]
    fn it_runs_end_to_end_against_the_stock_openssl() {
        use std::os::unix::fs::PermissionsExt;
        let (_g, home, tmp) = scratch("setup_signing_e2e");
        let root = home.parent().unwrap().to_path_buf();
        let stubs = root.join("bin");
        fs::create_dir_all(&stubs).unwrap();
        let log = root.join("calls.log");
        let log_call =
            r#"{ printf '%s' "${0##*/}"; printf '|%s' "$@"; printf '\n'; } >> "$STUB_LOG""#;
        for (name, body) in [
            (
                "security",
                "[ \"$1\" = import ] && : > \"$STUB_STATE/imported\"\n[ \"$1\" = list-keychains ] && [ \"$#\" -eq 3 ] && echo '    \"/stub/login.keychain-db\"'\nexit 0\n",
            ),
            (
                "codesign",
                "for last; do :; done\ncmp -s \"$last\" /bin/echo && echo \"probe is a copy of /bin/echo\" >> \"$STUB_LOG\"\n[ -e \"$STUB_STATE/imported\" ]\n",
            ),
            ("openssl", "exec /usr/bin/openssl \"$@\"\n"),
        ] {
            let p = stubs.join(name);
            fs::write(&p, format!("#!/bin/sh\n{}\n{}", log_call, body)).unwrap();
            fs::set_permissions(&p, fs::Permissions::from_mode(0o755)).unwrap();
        }
        let mut r = release_exec::SystemRunner::new();
        r.envs
            .insert("PATH".into(), format!("{}:/usr/bin:/bin", stubs.display()));
        r.envs
            .insert("HOME".into(), home.to_string_lossy().to_string());
        r.envs
            .insert("TMPDIR".into(), tmp.to_string_lossy().to_string());
        r.envs
            .insert("STUB_LOG".into(), log.to_string_lossy().to_string());
        r.envs
            .insert("STUB_STATE".into(), root.to_string_lossy().to_string());
        let mut resolving = Resolving {
            inner: r,
            bin: stubs.clone(),
        };
        assert_eq!(setup_signing(&mut resolving, &home, &tmp), Ok(()));

        let calls: Vec<String> = fs::read_to_string(&log)
            .unwrap()
            .lines()
            .map(String::from)
            .collect();
        assert!(
            calls
                .iter()
                .any(|c| c.starts_with("openssl|pkcs12|-export|")),
            "{:#?}",
            calls
        );
        assert!(
            calls.iter().any(|c| c.starts_with("openssl|"))
                && !calls
                    .iter()
                    .any(|c| c.starts_with("openssl|") && c.contains("|-legacy"))
        );
        assert!(
            calls.iter().any(|c| c.starts_with("security|import|"))
                && !calls.iter().any(|c| c.contains("find-identity"))
        );
        assert!(calls
            .iter()
            .any(|c| c.starts_with("codesign|") && c.contains("|--sign|Vitruvian Signing|")));
        assert!(calls.iter().any(|c| c == "probe is a copy of /bin/echo"));
        assert_eq!(
            fs::read_dir(&tmp).unwrap().count(),
            0,
            "it removes its probe and its work folder"
        );
    }

    /// std's Command resolves a bare program name with the parent's PATH, not
    /// the child's, so the test points each stand-in's name at its file.
    #[cfg(target_os = "macos")]
    struct Resolving {
        inner: release_exec::SystemRunner,
        bin: PathBuf,
    }

    #[cfg(target_os = "macos")]
    impl Resolving {
        fn resolve(&self, cmd: &Cmd) -> Cmd {
            let mut c = cmd.clone();
            let stub = self.bin.join(&c.program);
            if !c.program.contains('/') && stub.exists() {
                c.program = stub.to_string_lossy().to_string();
            }
            c
        }
    }

    #[cfg(target_os = "macos")]
    impl Runner for Resolving {
        fn status(&mut self, cmd: &Cmd) -> i32 {
            let c = self.resolve(cmd);
            self.inner.status(&c)
        }
        fn output(&mut self, cmd: &Cmd) -> Out {
            let c = self.resolve(cmd);
            self.inner.output(&c)
        }
        fn status_within(&mut self, cmd: &Cmd, limit: std::time::Duration) -> Option<i32> {
            let c = self.resolve(cmd);
            self.inner.status_within(&c, limit)
        }
        fn sleep(&mut self, d: std::time::Duration) {
            self.inner.sleep(d)
        }
    }
}
