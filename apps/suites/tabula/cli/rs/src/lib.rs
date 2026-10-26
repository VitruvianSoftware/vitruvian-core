// Copyright (c) 2026 VitruvianSoftware
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

pub mod commands;
pub mod utils;

use crate::commands::auth::run_auth_command;
use crate::commands::config::run_config_command;
use crate::commands::db::run_db_command;
use crate::commands::ext::run_ext_command;
use crate::commands::init::run_init_command;
use crate::commands::version::{run_version_command, CLI_REPORTED_VERSION};
use crate::commands::workos::run_workos_command;

pub fn help_text() -> String {
    [
        "Usage: tabcli [options] [command]",
        "",
        "TabCLI - Command-line tool for managing Tabula infrastructure and operations",
        "",
        "Options:",
        "  -V, --version   output the version number",
        "  -h, --help      display help for command",
        "",
        "Commands:",
        "  init [options]  Initialize Tabula configuration",
        "  config          Manage TabCLI configuration",
        "  db              Database management commands",
        "  version         Show TabCLI and component versions",
        "  auth            Manage authentication for external services",
        "  workos          WorkOS CLI wrapper with automatic authentication",
        "  ext             Manage the local load-unpacked dev extension install",
        "  help [command]  display help for command",
        "",
        "Examples:",
        "  $ tabcli init                    # Initialize Tabula configuration",
        "  $ tabcli auth neon               # Authenticate with Neon",
        "  $ tabcli auth gcloud             # Authenticate with GCP",
        "  $ tabcli config set project my-project",
        "  $ tabcli db migrate              # Run database migrations",
        "  $ tabcli ext update              # Pull the latest dev extension build",
        "",
        "Documentation:",
        "  For more information, visit: https://github.com/VitruvianSoftware/vitruvian-core",
    ]
    .join("\n")
}

pub fn run_cli(args: &[String]) -> Result<String, String> {
    if args.is_empty() {
        return Ok(help_text());
    }
    match args[0].as_str() {
        "-h" | "--help" | "help" => Ok(help_text()),
        "-V" | "--version" => Ok(CLI_REPORTED_VERSION.to_string()),
        "init" => run_init_command(&args[1..]),
        "config" => run_config_command(&args[1..]),
        "db" => run_db_command(&args[1..]),
        "version" => run_version_command(),
        "auth" => run_auth_command(&args[1..]),
        "workos" => run_workos_command(&args[1..]),
        "ext" => run_ext_command(&args[1..]),
        other => Err(format!("error: unknown command '{other}'")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cmp::Ordering;
    use std::collections::{BTreeMap, VecDeque};
    use std::fs;
    use std::path::{Path, PathBuf};
    use std::sync::atomic::{AtomicUsize, Ordering as AtomicOrdering};

    use crate::commands::auth::{build_gsm_store_neon_key_command, persist_verified_neon_api_key};
    use crate::commands::config::run_config_command_at;
    use crate::commands::db::{get_db_env, plan_db_command, DbActionPlan};
    use crate::commands::ext::{
        execute_ext_update, parse_ext_update_options, run_tool_capture_with, run_tool_with,
        ExtUpdateOptions, ToolRunResult, ToolRunner, ToolSpawnError,
    };
    use crate::commands::init::{init_config_at, InitAnswers};
    use crate::commands::version::PACKAGE_VERSION;
    use crate::commands::workos::{
        browser_open_command_for_os, build_workos_headless_env, filter_workos_passthrough_args,
        format_redirect_uris_json, generate_callback_urls, parse_cloud_run_services_csv,
    };
    use crate::utils::config::{
        escape_shell_arg, get_config_from, parse_top_level_json_object, save_config_to,
        unquote_json_string, Config, EnvironmentConfig,
    };
    use crate::utils::extension::{
        atomic_install, atomic_install_with_renamer, compare_semver, compare_semver_diff,
        default_extension_dir, read_bundle_info, read_installed_channel, resolve_beta_artifact,
        resolve_channel, resolve_latest_extension_tag, validate_bundle_dir,
        write_installed_channel, BetaArtifact, BundleInfo, InstallChannel,
    };
    use crate::utils::secrets::{
        get_project_id, load_neon_api_key, load_upstash_credentials, load_workos_api_key,
        load_workos_client_id, SecretFetcher,
    };

    static TMP_COUNTER: AtomicUsize = AtomicUsize::new(1);

    fn mk_tmp() -> PathBuf {
        let id = TMP_COUNTER.fetch_add(1, AtomicOrdering::SeqCst);
        let dir =
            std::env::temp_dir().join(format!("tabula-ext-rs-test-{}-{id}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).expect("create temp dir");
        dir
    }

    fn write_bundle(dir: &Path, commit: &str) {
        fs::create_dir_all(dir).expect("mkdir bundle");
        fs::write(dir.join("manifest.json"), r#"{"name":"Tabula"}"#).expect("write manifest");
        fs::write(
            dir.join("build-info.json"),
            format!(r#"{{"commit":"{commit}"}}"#),
        )
        .expect("write build-info");
    }

    struct MockToolRunner {
        calls: Vec<(String, Vec<String>)>,
        responses: VecDeque<ToolRunResult>,
    }

    impl MockToolRunner {
        fn new(responses: Vec<ToolRunResult>) -> Self {
            Self {
                calls: Vec::new(),
                responses: responses.into(),
            }
        }
    }

    impl ToolRunner for MockToolRunner {
        fn spawn_inherit(&mut self, cmd: &str, args: &[String]) -> ToolRunResult {
            self.calls.push((cmd.to_string(), args.to_vec()));
            self.responses.pop_front().unwrap_or(ToolRunResult {
                error: None,
                status: Some(0),
                stdout: String::new(),
            })
        }

        fn spawn_capture(&mut self, cmd: &str, args: &[String]) -> ToolRunResult {
            self.calls.push((cmd.to_string(), args.to_vec()));
            self.responses.pop_front().unwrap_or(ToolRunResult {
                error: None,
                status: Some(0),
                stdout: String::new(),
            })
        }
    }

    struct MockSecretFetcher {
        secrets: BTreeMap<(String, String), String>,
    }

    impl SecretFetcher for MockSecretFetcher {
        fn fetch_secret(&self, project_id: &str, secret_name: &str) -> Option<String> {
            self.secrets
                .get(&(project_id.to_string(), secret_name.to_string()))
                .cloned()
        }
    }

    fn find_cli_data_file(name: &str) -> PathBuf {
        let candidate1 = PathBuf::from("apps/suites/tabula/cli").join(name);
        if candidate1.exists() {
            return candidate1;
        }
        PathBuf::from(name)
    }

    // --- utils/extension.test.ts parity tests ---

    #[test]
    fn default_extension_dir_ends_with_tabula_extension() {
        let p = default_extension_dir();
        assert!(p.ends_with(".tabula/extension"));
    }

    #[test]
    fn read_bundle_info_reads_commit_from_build_info_json() {
        let dir = mk_tmp();
        write_bundle(&dir, "deadbee");
        assert_eq!(
            read_bundle_info(&dir),
            Some(BundleInfo {
                commit: Some("deadbee".to_string()),
                built_at: None,
                version: None,
            })
        );
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn read_bundle_info_reads_commit_from_legacy_build_underscore_info_fallback() {
        let dir = mk_tmp();
        fs::create_dir_all(&dir).unwrap();
        fs::write(dir.join("build_info.json"), r#"{"commit":"legacybee"}"#).unwrap();
        assert_eq!(
            read_bundle_info(&dir),
            Some(BundleInfo {
                commit: Some("legacybee".to_string()),
                built_at: None,
                version: None,
            })
        );
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn read_bundle_info_returns_none_when_missing_or_invalid() {
        let dir = mk_tmp();
        assert_eq!(read_bundle_info(&dir), None);
        fs::write(dir.join("build-info.json"), "not json").unwrap();
        assert_eq!(read_bundle_info(&dir), None);
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn validate_bundle_dir_errors_when_manifest_missing() {
        let dir = mk_tmp();
        let err = validate_bundle_dir(&dir).unwrap_err();
        assert!(err.contains("manifest.json"));
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn atomic_install_installs_fresh_bundle_when_no_previous_exists() {
        let root = mk_tmp();
        let staging = root.join("staging");
        let target = root.join("extension");
        write_bundle(&staging, "abc1234");

        atomic_install(&staging, &target).expect("atomic install");

        assert!(target.join("manifest.json").exists());
        assert!(!staging.exists());
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn atomic_install_replaces_previous_install_and_leaves_no_leftovers() {
        let root = mk_tmp();
        let staging = root.join("staging");
        let target = root.join("extension");
        write_bundle(&target, "oldcommit");
        write_bundle(&staging, "newcommit");

        atomic_install(&staging, &target).expect("atomic install");

        assert_eq!(
            read_bundle_info(&target).and_then(|b| b.commit),
            Some("newcommit".to_string())
        );
        let entries: Vec<String> = fs::read_dir(&root)
            .unwrap()
            .map(|e| e.unwrap().file_name().to_string_lossy().into_owned())
            .collect();
        assert_eq!(entries, vec!["extension".to_string()]);
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn atomic_install_leaves_existing_untouched_when_staging_invalid() {
        let root = mk_tmp();
        let staging = root.join("staging");
        let target = root.join("extension");
        write_bundle(&target, "oldcommit");
        fs::create_dir_all(&staging).unwrap(); // no manifest.json

        let err = atomic_install(&staging, &target).unwrap_err();
        assert!(err.contains("manifest.json"));
        assert_eq!(
            read_bundle_info(&target).and_then(|b| b.commit),
            Some("oldcommit".to_string())
        );
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn atomic_install_rolls_previous_install_back_when_final_swap_fails() {
        let root = mk_tmp();
        let staging = root.join("staging");
        let target = root.join("extension");
        write_bundle(&target, "oldcommit");
        write_bundle(&staging, "newcommit");

        let mut call_count = 0usize;
        let res = atomic_install_with_renamer(&staging, &target, |from, to| {
            call_count += 1;
            if call_count == 2 {
                Err("simulated rename failure".to_string())
            } else {
                fs::rename(from, to).map_err(|e| e.to_string())
            }
        });

        assert_eq!(res.unwrap_err(), "simulated rename failure");
        assert_eq!(
            read_bundle_info(&target).and_then(|b| b.commit),
            Some("oldcommit".to_string())
        );
        assert_eq!(
            read_bundle_info(&staging).and_then(|b| b.commit),
            Some("newcommit".to_string())
        );
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn channel_helpers_read_and_write_channel_json() {
        let dir = mk_tmp();
        fs::write(dir.join("channel.json"), r#"{"channel":"beta"}"#).unwrap();
        assert_eq!(read_installed_channel(&dir), Some(InstallChannel::Beta));

        let dir2 = mk_tmp();
        assert_eq!(read_installed_channel(&dir2), None);
        fs::write(dir2.join("channel.json"), "not json").unwrap();
        assert_eq!(read_installed_channel(&dir2), None);
        fs::write(dir2.join("channel.json"), r#"{"channel":"stable"}"#).unwrap();
        assert_eq!(read_installed_channel(&dir2), None);

        write_installed_channel(&dir2, InstallChannel::Alpha).unwrap();
        assert_eq!(read_installed_channel(&dir2), Some(InstallChannel::Alpha));

        let _ = fs::remove_dir_all(&dir);
        let _ = fs::remove_dir_all(&dir2);
    }

    #[test]
    fn resolve_channel_precedence_and_errors() {
        assert_eq!(
            resolve_channel(Some("beta"), Some(InstallChannel::Alpha)).unwrap(),
            InstallChannel::Beta
        );
        assert_eq!(
            resolve_channel(None, Some(InstallChannel::Beta)).unwrap(),
            InstallChannel::Beta
        );
        assert_eq!(resolve_channel(None, None).unwrap(), InstallChannel::Alpha);
        let stable_err = resolve_channel(Some("stable"), None).unwrap_err();
        assert!(stable_err.contains("Web Store") && stable_err.contains("M3"));

        let unknown_err = resolve_channel(Some("nightly"), None).unwrap_err();
        assert!(unknown_err.contains("alpha, beta, stable"));
    }

    #[test]
    fn compare_semver_orders_numerically_per_segment_and_pads_zeros() {
        assert_eq!(compare_semver("0.10.0", "0.9.9"), Ordering::Greater);
        assert_eq!(compare_semver("1.0.0", "1.0.0"), Ordering::Equal);
        assert_eq!(compare_semver("0.1.9", "0.2.0"), Ordering::Less);
        assert_eq!(compare_semver("1.0", "1.0.0"), Ordering::Equal);
        assert_eq!(compare_semver("1.0.1", "1.0"), Ordering::Greater);

        assert!(compare_semver_diff("0.10.0", "0.9.9") > 0);
        assert_eq!(compare_semver_diff("1.0", "1.0.0"), 0);
    }

    #[test]
    fn resolve_latest_extension_tag_and_beta_artifact() {
        let json = r#"[
          {"tagName":"tabula-cli-v0.3.0"},
          {"tagName":"tabula-extension-v0.1.9"},
          {"tagName":"tabula-extension-dev-latest"},
          {"tagName":"tabula-extension-v0.1.10"},
          {"tagName":"devx-v1.2.3"},
          {"tagName":"tabula-extension-v0.1.2"}
        ]"#;
        assert_eq!(
            resolve_latest_extension_tag(json),
            Some("tabula-extension-v0.1.10".to_string())
        );
        assert_eq!(
            resolve_latest_extension_tag(r#"[{"tagName":"devx-v1.0.0"}]"#),
            None
        );
        assert_eq!(resolve_latest_extension_tag("[]"), None);
        assert_eq!(resolve_latest_extension_tag("gh exploded"), None);

        assert_eq!(
            resolve_beta_artifact(r#"[{"tagName":"tabula-extension-v0.1.10"}]"#),
            Some(BetaArtifact {
                tag: "tabula-extension-v0.1.10".to_string(),
                zip_name: "tabula-extension-v0.1.10-chrome.zip".to_string(),
            })
        );
        assert_eq!(resolve_beta_artifact("[]"), None);
    }

    // --- commands/ext.test.ts parity tests ---

    #[test]
    fn ext_command_wiring_and_options() {
        let help = run_ext_command(&[]).unwrap();
        assert!(help.contains("update"));
        assert!(help.contains("path"));

        let opts = parse_ext_update_options(&[]).unwrap();
        assert_eq!(opts.dir, default_extension_dir());
        assert_eq!(opts.channel, None);
    }

    #[test]
    fn run_tool_and_capture_errors_and_stdout() {
        let mut runner = MockToolRunner::new(vec![
            ToolRunResult {
                error: Some(ToolSpawnError::NotFound),
                status: None,
                stdout: String::new(),
            },
            ToolRunResult {
                error: None,
                status: Some(1),
                stdout: String::new(),
            },
            ToolRunResult {
                error: None,
                status: Some(0),
                stdout: r#"[{"tagName":"tabula-extension-v0.1.9"}]"#.to_string(),
            },
            ToolRunResult {
                error: Some(ToolSpawnError::NotFound),
                status: None,
                stdout: String::new(),
            },
            ToolRunResult {
                error: None,
                status: Some(1),
                stdout: String::new(),
            },
        ]);

        let err1 = run_tool_with(
            &mut runner,
            "gh",
            &["release".to_string(), "download".to_string()],
        )
        .unwrap_err();
        assert!(err1.contains("'gh' not found on PATH"));

        let err2 = run_tool_with(&mut runner, "unzip", &["-o".to_string()]).unwrap_err();
        assert!(err2.contains("unzip -o failed (exit 1)"));

        let out = run_tool_capture_with(
            &mut runner,
            "gh",
            &["release".to_string(), "list".to_string()],
        )
        .unwrap();
        assert_eq!(out, r#"[{"tagName":"tabula-extension-v0.1.9"}]"#);

        let err3 = run_tool_capture_with(
            &mut runner,
            "gh",
            &["release".to_string(), "list".to_string()],
        )
        .unwrap_err();
        assert!(err3.contains("'gh' not found on PATH"));

        let err4 = run_tool_capture_with(
            &mut runner,
            "gh",
            &["release".to_string(), "list".to_string()],
        )
        .unwrap_err();
        assert!(err4.contains("gh release list failed (exit 1)"));
    }

    #[test]
    fn ext_update_action_branching_stable_and_beta() {
        let mut runner = MockToolRunner::new(vec![]);
        let stable_opts = ExtUpdateOptions {
            dir: PathBuf::from("/tmp/tabula-ext-stable-test"),
            repo: "VitruvianSoftware/vitruvian-core".to_string(),
            channel: Some("STABLE".to_string()),
        };
        let logs = execute_ext_update(&stable_opts, &mut runner).unwrap();
        assert!(runner.calls.is_empty());
        assert!(logs[0].contains("Web Store listing (M3)"));

        let mut beta_runner = MockToolRunner::new(vec![
            ToolRunResult {
                error: None,
                status: Some(0),
                stdout: r#"[{"tagName":"tabula-extension-v0.1.10"}]"#.to_string(),
            },
            ToolRunResult {
                error: None,
                status: Some(1),
                stdout: String::new(),
            },
        ]);
        let beta_opts = ExtUpdateOptions {
            dir: PathBuf::from("/tmp/tabula-ext-beta-test"),
            repo: "VitruvianSoftware/vitruvian-core".to_string(),
            channel: Some("beta".to_string()),
        };
        let beta_err = execute_ext_update(&beta_opts, &mut beta_runner).unwrap_err();
        assert!(beta_err.contains("may still be publishing"));
        assert_eq!(beta_runner.calls.len(), 2);
        let dl_args = &beta_runner.calls[1].1;
        assert!(dl_args.contains(&"download".to_string()));
        assert!(dl_args.contains(&"tabula-extension-v0.1.10".to_string()));
        assert!(dl_args.contains(&"--pattern".to_string()));
        assert!(dl_args.contains(&"tabula-extension-v0.1.10-chrome.zip".to_string()));
    }

    // --- init, config, db, workos, auth, secrets, version tests ---

    #[test]
    fn init_and_config_commands_roundtrip() {
        let dir = mk_tmp();
        let answers = InitAnswers {
            project_id: "tabula-dev".to_string(),
            environment: "development".to_string(),
            region: "us-central1".to_string(),
            database_url: Some("postgresql://localhost:5432/tabula".to_string()),
            created_at: "2026-01-01T00:00:00.000Z".to_string(),
        };
        let out = init_config_at(&dir, false, &answers, false).unwrap();
        assert!(out.contains("✓ TabCLI initialized"));
        assert!(out.contains("tabcli auth neon"));

        // Second init without force warns
        let out_dup = init_config_at(&dir, false, &answers, true).unwrap();
        assert!(out_dup.contains("Use --force to overwrite"));

        // Config list / get / set / unset
        let list_out = run_config_command_at(&dir, &["list".to_string()]).unwrap();
        assert!(list_out.contains("tabula-dev"));
        assert!(list_out.contains("(set)"));

        let get_out =
            run_config_command_at(&dir, &["get".to_string(), "projectId".to_string()]).unwrap();
        assert_eq!(get_out, "tabula-dev");

        run_config_command_at(
            &dir,
            &[
                "set".to_string(),
                "region".to_string(),
                "europe-west1".to_string(),
            ],
        )
        .unwrap();
        let region_out =
            run_config_command_at(&dir, &["get".to_string(), "region".to_string()]).unwrap();
        assert_eq!(region_out, "europe-west1");

        let invalid_err = run_config_command_at(
            &dir,
            &[
                "set".to_string(),
                "invalidKey".to_string(),
                "val".to_string(),
            ],
        )
        .unwrap_err();
        assert!(invalid_err.contains("Invalid key. Valid keys:"));

        run_config_command_at(&dir, &["unset".to_string(), "databaseUrl".to_string()]).unwrap();
        assert!(
            run_config_command_at(&dir, &["get".to_string(), "databaseUrl".to_string()]).is_err()
        );

        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn escape_shell_arg_escapes_single_quotes() {
        assert_eq!(escape_shell_arg("simple"), "'simple'");
        assert_eq!(escape_shell_arg("a'b"), "'a'\\''b'");
    }

    #[test]
    fn db_command_planning_and_env_resolution() {
        let dir = mk_tmp();
        let answers = InitAnswers {
            database_url: Some("postgresql://remote/db".to_string()),
            ..InitAnswers::default()
        };
        init_config_at(&dir, true, &answers, true).unwrap();

        let ambient = BTreeMap::from([(
            "DATABASE_URL".to_string(),
            "postgresql://local/db".to_string(),
        )]);
        let remote_env = get_db_env(&dir, false, &ambient);
        assert_eq!(
            remote_env.get("DATABASE_URL").map(String::as_str),
            Some("postgresql://remote/db")
        );
        let local_env = get_db_env(&dir, true, &ambient);
        assert_eq!(
            local_env.get("DATABASE_URL").map(String::as_str),
            Some("postgresql://local/db")
        );

        let migrate_plan = plan_db_command(
            &dir,
            &[
                "migrate".to_string(),
                "--name".to_string(),
                "add_users".to_string(),
            ],
        )
        .unwrap();
        assert_eq!(
            migrate_plan,
            DbActionPlan::Migrate {
                local: false,
                name: "add_users".to_string(),
                cwd: dir.join("api"),
                command: vec![
                    "npx".to_string(),
                    "prisma".to_string(),
                    "migrate".to_string(),
                    "dev".to_string(),
                    "--name".to_string(),
                    "add_users".to_string(),
                ],
            }
        );

        let reset_no_force = plan_db_command(&dir, &["reset".to_string()]).unwrap();
        if let DbActionPlan::Reset { force, command, .. } = reset_no_force {
            assert!(!force);
            assert!(command.is_none());
        } else {
            panic!("expected Reset plan");
        }

        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn workos_cloud_run_parsing_and_passthrough_filtering() {
        let csv = "\
tabula-api-dev,https://tabula-api-dev-xyz.a.run.app
other-service,https://other.a.run.app
tabula-api-stg,https://tabula-api-stg-xyz.a.run.app
";
        let urls = parse_cloud_run_services_csv(csv);
        assert_eq!(urls.len(), 2);
        assert_eq!(
            urls.get("dev").map(String::as_str),
            Some("https://tabula-api-dev-xyz.a.run.app")
        );
        assert_eq!(
            urls.get("stg").map(String::as_str),
            Some("https://tabula-api-stg-xyz.a.run.app")
        );

        let callbacks = generate_callback_urls(&urls);
        assert_eq!(
            callbacks,
            vec![
                "https://tabula-api-dev-xyz.a.run.app/api/v1/auth/callback".to_string(),
                "https://tabula-api-stg-xyz.a.run.app/api/v1/auth/callback".to_string(),
                "http://localhost:8080/api/v1/auth/callback".to_string(),
            ]
        );
        let json = format_redirect_uris_json(&callbacks);
        assert!(json.contains("\"redirectUris\""));

        let filtered = filter_workos_passthrough_args(&[
            "--env".to_string(),
            "staging".to_string(),
            "organizations".to_string(),
            "list".to_string(),
            "-e".to_string(),
            "prod".to_string(),
        ]);
        assert_eq!(
            filtered,
            vec!["organizations".to_string(), "list".to_string()]
        );

        let headless = build_workos_headless_env("sk_test_123");
        assert_eq!(
            headless
                .get("WORKOS_ACTIVE_ENVIRONMENT")
                .map(String::as_str),
            Some("headless")
        );
        assert_eq!(
            headless
                .get("WORKOS_ENVIRONMENTS_HEADLESS_API_KEY")
                .map(String::as_str),
            Some("sk_test_123")
        );
        assert_eq!(browser_open_command_for_os("macos"), "open");
        assert_eq!(browser_open_command_for_os("linux"), "xdg-open");
    }

    #[test]
    fn secrets_and_auth_helpers() {
        let mut cfg = Config {
            project_id: "tabula-default".to_string(),
            region: "us-central1".to_string(),
            neon_api_key: Some("neon_from_cfg".to_string()),
            ..Config::default()
        };
        cfg.environments.insert(
            "staging".to_string(),
            EnvironmentConfig {
                project_id: "tabula-staging".to_string(),
            },
        );
        assert_eq!(get_project_id(&cfg, "staging"), "tabula-staging");
        assert_eq!(get_project_id(&cfg, "dev"), "tabula-default");

        let mut secrets = BTreeMap::new();
        secrets.insert(
            ("tabula-staging".to_string(), "WORKOS_API_KEY".to_string()),
            "sk_stg_secret".to_string(),
        );
        secrets.insert(
            ("tabula-staging".to_string(), "WORKOS_CLIENT_ID".to_string()),
            "client_stg_123".to_string(),
        );
        secrets.insert(
            ("tabula-staging".to_string(), "UPSTASH_EMAIL".to_string()),
            "ops@tabula.dev".to_string(),
        );
        secrets.insert(
            ("tabula-staging".to_string(), "UPSTASH_API_KEY".to_string()),
            "upstash_key_123".to_string(),
        );
        let fetcher = MockSecretFetcher { secrets };
        let mut env_vars = BTreeMap::new();

        assert_eq!(
            load_workos_api_key(&cfg, "staging", &mut env_vars, &fetcher),
            Some("sk_stg_secret".to_string())
        );
        assert_eq!(
            load_workos_client_id(&cfg, "staging", &mut env_vars, &fetcher),
            Some("client_stg_123".to_string())
        );
        assert_eq!(
            load_neon_api_key(&cfg, "staging", &mut env_vars, &fetcher),
            Some("neon_from_cfg".to_string())
        );
        assert!(load_upstash_credentials(
            &cfg,
            "staging",
            &mut env_vars,
            &fetcher
        ));

        let gsm_cmd = build_gsm_store_neon_key_command("neon_k", "proj-1");
        assert!(gsm_cmd.contains("gcloud secrets create NEON_API_KEY"));

        let dir = mk_tmp();
        fs::create_dir_all(dir.join(".tabula")).unwrap();
        save_config_to(&dir, &cfg).unwrap();
        let msg = persist_verified_neon_api_key(&dir, "neon_new", true).unwrap();
        assert_eq!(
            msg,
            Some("✓ Removed API Key from local configuration".to_string())
        );
        assert_eq!(get_config_from(&dir).unwrap().neon_api_key, None);
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn version_sync_with_package_json_and_release_please() {
        let pkg_raw =
            fs::read_to_string(find_cli_data_file("package.json")).expect("read package.json");
        let pkg_pairs = parse_top_level_json_object(&pkg_raw).expect("parse package.json");
        let pkg_version = pkg_pairs
            .iter()
            .find(|(k, _)| k == "version")
            .and_then(|(_, v)| unquote_json_string(v))
            .expect("package.json version");

        let manifest_raw = fs::read_to_string(find_cli_data_file(".release-please-manifest.json"))
            .expect("read .release-please-manifest.json");
        let manifest_pairs = parse_top_level_json_object(&manifest_raw).expect("parse manifest");
        let manifest_version = manifest_pairs
            .iter()
            .find(|(k, _)| k == "apps/suites/tabula/cli")
            .and_then(|(_, v)| unquote_json_string(v))
            .expect("manifest version");

        let rp_config_raw = fs::read_to_string(find_cli_data_file("release-please-config.json"))
            .expect("read release-please-config.json");
        assert!(rp_config_raw.contains("\"component\": \"tabula-cli\""));

        assert_eq!(pkg_version, manifest_version);
        assert_eq!(PACKAGE_VERSION, pkg_version);
        assert_eq!(run_cli(&["--version".to_string()]).unwrap(), "0.1.0");
    }
}
