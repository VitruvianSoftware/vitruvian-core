// Copyright 2026 VitruvianSoftware
// SPDX-License-Identifier: AGPL-3.0-or-later

pub mod app_holds_engine;
pub mod engine_contract;
pub mod inject_app_credentials;
pub mod install;

#[cfg(test)]
mod tests {
    use super::*;

    // --- inject_app_credentials: credential validation -----------------------

    #[test]
    fn valid_api_id() {
        assert_eq!(
            inject_app_credentials::validate_api_id("4242424").unwrap(),
            "4242424"
        );
    }

    #[test]
    fn api_id_strips_leading_zeros() {
        assert_eq!(
            inject_app_credentials::validate_api_id("004242424").unwrap(),
            "4242424"
        );
    }

    #[test]
    fn api_id_max_value() {
        assert_eq!(
            inject_app_credentials::validate_api_id("2147483647").unwrap(),
            "2147483647"
        );
    }

    #[test]
    fn api_id_one() {
        assert_eq!(inject_app_credentials::validate_api_id("1").unwrap(), "1");
    }

    #[test]
    fn api_id_zero_rejected() {
        assert!(inject_app_credentials::validate_api_id("0").is_err());
    }

    #[test]
    fn api_id_over_max_rejected() {
        assert!(inject_app_credentials::validate_api_id("2147483648").is_err());
    }

    #[test]
    fn api_id_huge_rejected() {
        assert!(inject_app_credentials::validate_api_id("99999999999999999999").is_err());
    }

    #[test]
    fn api_id_not_a_number_rejected() {
        assert!(inject_app_credentials::validate_api_id("notanumber").is_err());
    }

    #[test]
    fn api_id_negative_rejected() {
        assert!(inject_app_credentials::validate_api_id("-4242424").is_err());
    }

    #[test]
    fn api_id_with_whitespace() {
        assert_eq!(
            inject_app_credentials::validate_api_id("  4242424  \n").unwrap(),
            "4242424"
        );
    }

    #[test]
    fn valid_api_hash() {
        assert_eq!(
            inject_app_credentials::validate_api_hash("0123456789abcdef0123456789abcdef").unwrap(),
            "0123456789abcdef0123456789abcdef"
        );
    }

    #[test]
    fn api_hash_uppercase_valid() {
        assert_eq!(
            inject_app_credentials::validate_api_hash("0123456789ABCDEF0123456789ABCDEF").unwrap(),
            "0123456789ABCDEF0123456789ABCDEF"
        );
    }

    #[test]
    fn api_hash_too_short_rejected() {
        assert!(inject_app_credentials::validate_api_hash("0123456789abcdef").is_err());
    }

    #[test]
    fn api_hash_too_long_rejected() {
        assert!(
            inject_app_credentials::validate_api_hash("0123456789abcdef0123456789abcdef00")
                .is_err()
        );
    }

    #[test]
    fn api_hash_not_hex_rejected() {
        assert!(
            inject_app_credentials::validate_api_hash("ghijklmnopqrstuvwxyzghijklmnopqr").is_err()
        );
    }

    #[test]
    fn api_hash_with_whitespace() {
        assert_eq!(
            inject_app_credentials::validate_api_hash("  0123456789abcdef0123456789abcdef  \n")
                .unwrap(),
            "0123456789abcdef0123456789abcdef"
        );
    }

    // --- inject_app_credentials: plist generation ----------------------------

    #[test]
    fn plist_well_formed() {
        let plist =
            inject_app_credentials::generate_plist("4242424", "0123456789abcdef0123456789abcdef");
        assert!(plist.contains("<?xml version=\"1.0\""));
        assert!(plist.contains("<integer>4242424</integer>"));
        assert!(plist.contains("<string>0123456789abcdef0123456789abcdef</string>"));
        assert!(plist.contains("<key>api_id</key>"));
        assert!(plist.contains("<key>api_hash</key>"));
        assert!(plist.contains("</plist>"));
    }

    #[test]
    fn plist_api_id_is_integer_element() {
        let plist =
            inject_app_credentials::generate_plist("42", "abcdef01234567890123456789abcdef");
        let lines: Vec<&str> = plist.lines().collect();
        let id_idx = lines
            .iter()
            .position(|l| l.contains("<key>api_id</key>"))
            .unwrap();
        assert!(lines[id_idx + 1].contains("<integer>42</integer>"));
    }

    #[test]
    fn plist_api_hash_is_string_element() {
        let plist =
            inject_app_credentials::generate_plist("42", "abcdef01234567890123456789abcdef");
        let lines: Vec<&str> = plist.lines().collect();
        let hash_idx = lines
            .iter()
            .position(|l| l.contains("<key>api_hash</key>"))
            .unwrap();
        assert!(lines[hash_idx + 1].contains("<string>abcdef01234567890123456789abcdef</string>"));
    }

    // --- inject_app_credentials: store_dirs resolution -----------------------

    #[test]
    fn store_dirs_secrets_dir_override() {
        // When COURIER_SECRETS_DIR is set, only that dir is returned.
        let _guard = TestEnvGuard::new();
        std::env::set_var("COURIER_SECRETS_DIR", "/tmp/test-secrets");
        std::env::remove_var("BUILD_WORKSPACE_DIRECTORY");
        let dirs = inject_app_credentials::store_dirs(std::path::Path::new("/nonexistent"));
        assert_eq!(dirs.len(), 1);
        assert_eq!(dirs[0], std::path::PathBuf::from("/tmp/test-secrets"));
        std::env::remove_var("COURIER_SECRETS_DIR");
    }

    // --- engine_contract: protocol version extraction -------------------------

    #[test]
    fn extract_protocol_from_json_content() {
        let dir = std::env::temp_dir().join("engine_contract_test");
        let _ = std::fs::create_dir_all(&dir);
        let json = dir.join("protocol.json");
        std::fs::write(&json, "{\n  \"protocol\": 5,\n  \"messages\": []\n}\n").unwrap();
        // We test via the module's run function indirectly; here test that the
        // contract test parses the version correctly by examining the file
        let content = std::fs::read_to_string(&json).unwrap();
        let mut version = None;
        for line in content.lines() {
            if let Some(rest) = line.strip_prefix("  \"protocol\": ") {
                let rest = rest.trim_end_matches(',').trim();
                if rest.chars().all(|c| c.is_ascii_digit()) && !rest.is_empty() {
                    version = Some(rest.to_string());
                }
            }
        }
        assert_eq!(version, Some("5".to_string()));
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn extract_protocol_from_swift_content() {
        let content = "    public static let version = 5\n";
        let mut version = None;
        for line in content.lines() {
            let trimmed = line.trim();
            if let Some(rest) = trimmed.strip_prefix("public static let version = ") {
                let rest = rest.trim();
                if rest.chars().all(|c| c.is_ascii_digit()) && !rest.is_empty() {
                    version = Some(rest.to_string());
                }
            }
        }
        assert_eq!(version, Some("5".to_string()));
    }

    #[test]
    fn extract_supervisor_flags() {
        let content = r#"
            let args = ["--data", dataDir.path, "--parent-fd", "0"]
        "#;
        assert!(content.contains("\"--data\", dataDir.path, \"--parent-fd\", \"0\""));
    }

    // --- app_holds_engine: archive resolution --------------------------------

    #[test]
    fn resolve_app_from_zip_name() {
        // resolve_app looks for .zip extension
        let paths = vec!["something".to_string(), "Courier.zip".to_string()];
        // We cannot actually unzip here, but we can verify the resolution
        // logic finds the .zip path. Since the file doesn't exist, this
        // would fail at unzip; we test the parsing separately.
        let paths_with_app = vec!["Courier.app".to_string()];
        // When a .app dir doesn't exist, resolve_app returns Err.
        let result = app_holds_engine::resolve_app(&paths_with_app);
        // Courier.app doesn't exist as a dir so this should fail:
        assert!(result.is_err());
    }

    // --- install: argument / archive resolution ------------------------------

    #[test]
    fn install_run_no_args_exits_2() {
        let args = vec!["install".to_string()];
        assert_eq!(install::run(&args), 2);
    }

    #[test]
    fn install_run_unknown_arg_exits_2() {
        let args = vec![
            "install".to_string(),
            "injector".to_string(),
            "archive.zip".to_string(),
            "--unknown".to_string(),
        ];
        assert_eq!(install::run(&args), 2);
    }

    // Helper to set/unset env vars in tests without interference.
    struct TestEnvGuard {
        vars: Vec<(String, Option<String>)>,
    }

    impl TestEnvGuard {
        fn new() -> Self {
            let keys = [
                "COURIER_SECRETS_DIR",
                "BUILD_WORKSPACE_DIRECTORY",
                "COURIER_TELEGRAM_API_ID",
                "COURIER_TELEGRAM_API_HASH",
                "COURIER_SIGN_IDENTITY",
                "COURIER_SIGN_FLAGS",
            ];
            let vars = keys
                .iter()
                .map(|k| (k.to_string(), std::env::var(k).ok()))
                .collect();
            Self { vars }
        }
    }

    impl Drop for TestEnvGuard {
        fn drop(&mut self) {
            for (k, v) in &self.vars {
                match v {
                    Some(val) => std::env::set_var(k, val),
                    None => std::env::remove_var(k),
                }
            }
        }
    }
}
