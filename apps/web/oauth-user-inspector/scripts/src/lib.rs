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

pub mod check_sensitive;
pub mod deploy;
pub mod setup_dev;
pub mod smoke;
pub mod start;

#[cfg(test)]
mod tests {
    use super::check_sensitive::is_sensitive;
    use super::deploy::{
        compute_service_account, resolve_deploy_config, DEFAULT_REGION, REQUIRED_SERVICES,
        SERVICE_NAME,
    };
    use super::setup_dev::{install_pre_commit_hook, PRE_COMMIT_HOOK_SCRIPT};
    use super::smoke::{as_captured, command_v, find_chrome_binary, mounted};
    use super::start::{resolve_env_or_default, validate_build_dirs, BuildCheckError};
    use std::fs;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn env_file_at_root() {
        assert!(is_sensitive(".env.local"));
    }

    #[test]
    fn env_file_in_subdir() {
        assert!(is_sensitive("some/path/.env.production"));
    }

    #[test]
    fn bare_env_file() {
        assert!(is_sensitive(".env"));
    }

    #[test]
    fn dist_dir() {
        assert!(is_sensitive("dist/bundle.js"));
    }

    #[test]
    fn dist_server_dir() {
        assert!(is_sensitive("dist-server/index.js"));
    }

    #[test]
    fn dist_at_root() {
        assert!(is_sensitive("dist/"));
    }

    #[test]
    fn nested_dist() {
        assert!(is_sensitive("foo/dist/bar.js"));
    }

    #[test]
    fn safe_file() {
        assert!(!is_sensitive("src/index.ts"));
    }

    #[test]
    fn safe_env_like() {
        assert!(!is_sensitive("environment.ts"));
    }

    #[test]
    fn safe_dist_like() {
        assert!(!is_sensitive("distribute.sh"));
    }

    fn by_name(name: &str) -> impl Fn(&str) -> Option<std::path::PathBuf> + '_ {
        move |c| (c == name).then(|| std::path::PathBuf::from(c))
    }

    #[test]
    fn chrome_binary_returns_none_when_missing() {
        assert!(find_chrome_binary(|_| None).is_none());
    }

    #[test]
    fn chrome_binary_prefers_stable_then_chrome_then_chromium() {
        for name in ["google-chrome-stable", "google-chrome", "chromium-browser"] {
            assert_eq!(
                find_chrome_binary(by_name(name)),
                Some(std::path::PathBuf::from(name))
            );
        }
    }

    #[test]
    fn command_v_falls_back_to_a_non_executable_match_like_bash() {
        use std::os::unix::fs::PermissionsExt;
        let base = std::env::var_os("TEST_TMPDIR")
            .map(std::path::PathBuf::from)
            .unwrap_or_else(std::env::temp_dir)
            .join(format!("smoke-cmdv-{}", std::process::id()));
        let (a, b, c) = (base.join("a"), base.join("b"), base.join("c"));
        for d in [&a, &b, &c] {
            fs::create_dir_all(d).unwrap();
        }
        fs::create_dir_all(a.join("tool")).unwrap(); // a directory never matches
        fs::write(b.join("tool"), "").unwrap(); // not executable: the fallback
        fs::write(c.join("tool"), "").unwrap();
        let path = std::env::join_paths([&a, &b, &c]).unwrap();
        assert_eq!(command_v("tool", Some(path.clone())), Some(b.join("tool")));
        fs::set_permissions(c.join("tool"), fs::Permissions::from_mode(0o755)).unwrap();
        assert_eq!(command_v("tool", Some(path)), Some(c.join("tool")));
        assert_eq!(command_v("tool", None), None);
        let _ = fs::remove_dir_all(&base);
    }

    #[test]
    fn dom_is_what_command_substitution_captured() {
        assert_eq!(as_captured(b"<p>x</p>\n\n".to_vec()), b"<p>x</p>");
        assert_eq!(as_captured(b"a\0b\n\xff".to_vec()), b"ab\n\xff");
        assert!(mounted(b"<div>Select a provider</div>"));
        assert!(!mounted(b"Select a\nprovider"));
    }

    #[test]
    fn start_env_defaults_when_unset_or_empty() {
        assert_eq!(resolve_env_or_default(None, "development"), "development");
        assert_eq!(
            resolve_env_or_default(Some(""), "development"),
            "development"
        );
        assert_eq!(
            resolve_env_or_default(Some("production"), "development"),
            "production"
        );
        assert_eq!(resolve_env_or_default(None, "8080"), "8080");
        assert_eq!(resolve_env_or_default(Some("3000"), "8080"), "3000");
    }

    #[test]
    fn start_validates_dist_and_dist_server_layout() {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let tmp = std::env::temp_dir().join(format!("oauth-start-test-{nanos}"));
        fs::create_dir_all(&tmp).unwrap();

        assert_eq!(validate_build_dirs(&tmp), Err(BuildCheckError::MissingDist));

        fs::create_dir_all(tmp.join("dist")).unwrap();
        assert_eq!(
            validate_build_dirs(&tmp),
            Err(BuildCheckError::MissingDistServer)
        );

        fs::create_dir_all(tmp.join("dist-server")).unwrap();
        assert_eq!(
            validate_build_dirs(&tmp),
            Err(BuildCheckError::MissingServerJs)
        );

        fs::write(tmp.join("dist-server/server.js"), "console.log('ok');\n").unwrap();
        assert_eq!(validate_build_dirs(&tmp), Ok(()));

        let _ = fs::remove_dir_all(&tmp);
    }

    #[test]
    fn deploy_config_resolves_cli_args_and_gcloud_fallback() {
        let args = vec![
            "deploy".to_string(),
            "my-project".to_string(),
            "europe-west1".to_string(),
        ];
        let cfg = resolve_deploy_config(&args, || None).unwrap();
        assert_eq!(cfg.project_id, "my-project");
        assert_eq!(cfg.region, "europe-west1");
        assert_eq!(cfg.service_name, SERVICE_NAME);

        let fallback_args = vec!["deploy".to_string()];
        let fallback_cfg =
            resolve_deploy_config(&fallback_args, || Some("default-proj".to_string())).unwrap();
        assert_eq!(fallback_cfg.project_id, "default-proj");
        assert_eq!(fallback_cfg.region, DEFAULT_REGION);

        assert!(resolve_deploy_config(&fallback_args, || None).is_err());
        assert_eq!(
            compute_service_account("1234567890"),
            "1234567890-compute@developer.gserviceaccount.com"
        );
        assert_eq!(REQUIRED_SERVICES.len(), 4);
    }

    #[test]
    fn setup_dev_installs_executable_pre_commit_hook() {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let tmp = std::env::temp_dir().join(format!("oauth-setup-dev-test-{nanos}"));
        fs::create_dir_all(&tmp).unwrap();

        let hook_path = install_pre_commit_hook(&tmp).unwrap();
        assert_eq!(hook_path, tmp.join(".git/hooks/pre-commit"));
        assert_eq!(
            fs::read_to_string(&hook_path).unwrap(),
            PRE_COMMIT_HOOK_SCRIPT
        );
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mode = fs::metadata(&hook_path).unwrap().permissions().mode();
            assert_ne!(mode & 0o111, 0);
        }

        let _ = fs::remove_dir_all(&tmp);
    }
}
