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
// SPDX-License-Identifier: MIT

//! Local control plane for Roborock vacuums: daemon, CLI (`rrctl`), and MCP server.

pub mod auth;
pub mod cli;
pub mod cloud;
pub mod codes;
pub mod config;
pub mod crypto;
pub mod daemon;
pub mod device;
pub mod link;
pub mod local;
pub mod mapimg;
pub mod mcp;
pub mod mqtt;
pub mod protocol;
pub mod state;

pub const VERSION: &str = "0.2.0";

const DASHBOARD_HTML: &str = include_str!("../assets/dashboard.html");

pub fn dashboard_html() -> &'static str {
    DASHBOARD_HTML
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::auth::{ApiClient, ApiError, LoginFlow};
    use crate::cli::{CliClient, CliHooks, DaemonSubcommand, ParseOutcome, Subcommand};
    use crate::config::{ConfigError, Credentials};
    use crate::daemon::{
        ClientError, DaemonClient, DaemonRequestError, DaemonServer, DaemonUnavailable, StopSignal,
    };
    use crate::device::{
        resolve_rooms, DeviceCandidate, DeviceError, RawVacuumStatus, RoborockVacuum, Room,
        UpdateCallback, Vacuum,
    };
    use crate::mcp::{build_server, Bridge, DaemonApi};
    use crate::state::{CommandError, ServiceOptions, StateStore, VacuumService};
    use serde_json::{json, Map, Value};
    use std::collections::HashSet;
    use std::env;
    use std::fs::{self, Permissions};
    use std::io::{BufRead, BufReader, Write};
    use std::net::{SocketAddr, TcpListener, TcpStream};
    use std::os::unix::fs::PermissionsExt;
    use std::path::{Path, PathBuf};
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::sync::{Arc, Mutex};
    use std::thread;
    use std::time::{Duration, Instant};

    static ENV_LOCK: Mutex<()> = Mutex::new(());
    static TEST_DIR_SEQ: AtomicU64 = AtomicU64::new(1);

    const TOKEN: &str = "test-token-0123456789";

    fn png_bytes() -> Vec<u8> {
        let mut v = b"\x89PNG\r\n\x1a\n".to_vec();
        v.extend_from_slice(&[0u8; 16]);
        v
    }

    fn user_data() -> Map<String, Value> {
        json!({
            "rriot": {
                "u": "user",
                "s": "secret",
                "h": "hmac",
                "k": "key",
                "r": {"r": "US", "a": "https://a", "m": "ssl://m", "l": "https://l"}
            },
            "uid": 1,
            "token": "tok",
            "rruid": "rr1",
            "region": "us",
            "countrycode": "1",
            "country": "US",
            "nickname": "tester"
        })
        .as_object()
        .unwrap()
        .clone()
    }

    fn default_status_doc() -> Map<String, Value> {
        json!({
            "device": {"id": "duid-1", "name": "Rocky", "model": "roborock.vacuum.a70", "local": true},
            "state": "charging",
            "state_code": 8,
            "battery": 100,
            "error": null,
            "in_cleaning": false,
            "in_returning": false,
            "rooms": [{"id": 16, "name": "Kitchen"}, {"id": 17, "name": "Living Room"}]
        })
        .as_object()
        .unwrap()
        .clone()
    }

    fn default_rooms() -> Vec<Room> {
        vec![Room::new(16, "Kitchen"), Room::new(17, "Living Room")]
    }

    fn with_isolated_home<F: FnOnce(&Path)>(f: F) {
        let _guard = ENV_LOCK.lock().unwrap_or_else(|e| e.into_inner());
        let seq = TEST_DIR_SEQ.fetch_add(1, Ordering::Relaxed);
        let root = env::temp_dir().join(format!("roborock-rs-test-{}-{seq}", std::process::id()));
        let home = root.join("home");
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(&home).unwrap();

        env::set_var("HOME", &home);
        env::remove_var("XDG_CONFIG_HOME");
        env::remove_var(config::HOME_ENV);
        env::remove_var(config::PORT_ENV);
        env::remove_var(config::DEVICE_ENV);

        f(&home);

        let _ = fs::remove_dir_all(&root);
    }

    fn save_test_login() -> Credentials {
        let creds = Credentials::new("me@example.com", user_data());
        config::save_credentials(&creds).unwrap();
        creds
    }

    fn mode(path: &Path) -> u32 {
        fs::metadata(path).unwrap().permissions().mode() & 0o777
    }

    fn until<F: Fn() -> bool>(predicate: F) {
        let deadline = Instant::now() + Duration::from_secs(3);
        while !predicate() {
            assert!(Instant::now() <= deadline, "condition not reached in time");
            thread::sleep(Duration::from_millis(5));
        }
    }

    struct FakeVacuum {
        snapshot: Mutex<Map<String, Value>>,
        png: Mutex<Option<Vec<u8>>>,
        commands: Mutex<Vec<(String, Option<Map<String, Value>>)>>,
        connects: Mutex<usize>,
        closed: Mutex<usize>,
        fail_connect: Mutex<usize>,
        fail_status: Mutex<bool>,
        credentials_rejected: Mutex<bool>,
        listener: Mutex<Option<UpdateCallback>>,
    }

    impl FakeVacuum {
        fn new() -> Arc<Self> {
            Arc::new(Self {
                snapshot: Mutex::new(default_status_doc()),
                png: Mutex::new(Some(png_bytes())),
                commands: Mutex::new(Vec::new()),
                connects: Mutex::new(0),
                closed: Mutex::new(0),
                fail_connect: Mutex::new(0),
                fail_status: Mutex::new(false),
                credentials_rejected: Mutex::new(false),
                listener: Mutex::new(None),
            })
        }

        fn push_update(&self, doc: Map<String, Value>) {
            let cb = self.listener.lock().unwrap().clone();
            if let Some(cb) = cb {
                cb(doc);
            }
        }
    }

    impl Vacuum for FakeVacuum {
        fn connect(&self) -> Result<(), DeviceError> {
            *self.connects.lock().unwrap() += 1;
            let mut fail = self.fail_connect.lock().unwrap();
            if *fail > 0 {
                *fail -= 1;
                return Err(DeviceError::rejected("cloud unreachable"));
            }
            Ok(())
        }

        fn close(&self) -> Result<(), DeviceError> {
            *self.closed.lock().unwrap() += 1;
            Ok(())
        }

        fn status(&self) -> Result<Map<String, Value>, DeviceError> {
            if *self.fail_status.lock().unwrap() {
                return Err(DeviceError::rejected("no answer"));
            }
            Ok(self.snapshot.lock().unwrap().clone())
        }

        fn map_png(&self) -> Result<Option<Vec<u8>>, DeviceError> {
            Ok(self.png.lock().unwrap().clone())
        }

        fn command(
            &self,
            action: &str,
            params: Option<&Map<String, Value>>,
        ) -> Result<Value, DeviceError> {
            if action == "bogus" {
                return Err(DeviceError::unknown_action("Unknown action 'bogus'."));
            }
            if action == "wash_start" {
                return Err(DeviceError::rejected(
                    "The vacuum refused 'wash_start': unsupported",
                ));
            }
            self.commands
                .lock()
                .unwrap()
                .push((action.to_string(), params.cloned()));
            Ok(json!(["ok"]))
        }

        fn on_update(&self, callback: UpdateCallback) {
            *self.listener.lock().unwrap() = Some(callback);
        }

        fn credentials_rejected(&self) -> bool {
            *self.credentials_rejected.lock().unwrap()
        }
    }

    // =========================================================================
    // 1. test_config.py ports
    // =========================================================================

    #[test]
    fn test_default_location_is_under_xdg_config() {
        with_isolated_home(|home| {
            assert_eq!(
                config::credentials_path(),
                home.join(".config")
                    .join("vitruvian")
                    .join("roborock")
                    .join("credentials.json")
            );
        });
    }

    #[test]
    fn test_xdg_config_home_is_honoured() {
        with_isolated_home(|home| {
            let xdg = home.join("xdg");
            env::set_var("XDG_CONFIG_HOME", &xdg);
            assert_eq!(config::config_dir(), xdg.join("vitruvian").join("roborock"));
        });
    }

    #[test]
    fn test_saved_credentials_are_private_and_round_trip() {
        with_isolated_home(|_| {
            let creds =
                Credentials::new("me@example.com", user_data()).with_base_url("https://usiot");
            let path = config::save_credentials(&creds).unwrap();
            assert_eq!(mode(&path), 0o600);
            assert_eq!(mode(path.parent().unwrap()), 0o700);
            let loaded = config::load_credentials().unwrap().unwrap();
            assert_eq!(loaded.email, "me@example.com");
            assert_eq!(loaded.user_data, user_data());
            assert_eq!(loaded.base_url.as_deref(), Some("https://usiot"));
            let leftovers: Vec<PathBuf> = fs::read_dir(path.parent().unwrap())
                .unwrap()
                .filter_map(|e| e.ok().map(|e| e.path()))
                .filter(|p| {
                    p.file_name()
                        .and_then(|n| n.to_str())
                        .map(|s| s.starts_with(".credentials.json."))
                        .unwrap_or(false)
                })
                .collect();
            assert!(leftovers.is_empty(), "temp file left behind");
        });
    }

    #[test]
    fn test_loading_tightens_a_file_someone_loosened() {
        with_isolated_home(|_| {
            save_test_login();
            let path = config::credentials_path();
            fs::set_permissions(&path, Permissions::from_mode(0o644)).unwrap();
            config::load_credentials().unwrap();
            assert_eq!(mode(&path), 0o600);
        });
    }

    #[test]
    fn test_no_login_anywhere_is_none_not_an_error() {
        with_isolated_home(|_| {
            assert_eq!(config::load_credentials().unwrap(), None);
        });
    }

    #[test]
    fn test_legacy_roborock_file_is_migrated_and_left_in_place() {
        for key in ["userData", "user_data"] {
            with_isolated_home(|_| {
                let legacy = config::legacy_credentials_path();
                let doc = json!({
                    key: user_data(),
                    "email": "me@example.com",
                    "cacheData": {"homeData": {}}
                });
                let content = serde_json::to_string(&doc).unwrap();
                fs::write(&legacy, &content).unwrap();

                let loaded = config::load_credentials().unwrap().unwrap();
                assert_eq!(loaded.email, "me@example.com");
                assert_eq!(loaded.user_data, user_data());
                assert_eq!(
                    loaded.migrated_from.as_deref(),
                    Some(legacy.to_string_lossy().as_ref())
                );
                assert_eq!(mode(&config::credentials_path()), 0o600);
                let saved_text = fs::read_to_string(config::credentials_path()).unwrap();
                assert!(
                    !saved_text.contains("cacheData"),
                    "only the login is copied, not the cache"
                );
                assert_eq!(fs::read_to_string(&legacy).unwrap(), content);
            });
        }
    }

    #[test]
    fn test_existing_credentials_win_over_legacy_file() {
        with_isolated_home(|_| {
            save_test_login();
            let legacy_doc = json!({"userData": user_data(), "email": "other@example.com"});
            fs::write(
                config::legacy_credentials_path(),
                serde_json::to_string(&legacy_doc).unwrap(),
            )
            .unwrap();
            let loaded = config::load_credentials().unwrap().unwrap();
            assert_eq!(loaded.email, "me@example.com");
        });
    }

    #[test]
    fn test_unusable_legacy_file_is_ignored() {
        let cases = [
            "not json".to_string(),
            "[]".to_string(),
            serde_json::to_string(&json!({"email": "me@example.com"})).unwrap(),
            serde_json::to_string(&json!({"userData": {"token": "x"}, "email": "me@example.com"}))
                .unwrap(),
        ];
        for content in cases {
            with_isolated_home(|_| {
                fs::write(config::legacy_credentials_path(), &content).unwrap();
                assert_eq!(config::load_credentials().unwrap(), None);
                assert!(!config::credentials_path().exists());
            });
        }
    }

    #[test]
    fn test_migration_can_be_switched_off() {
        with_isolated_home(|_| {
            let doc = json!({"userData": user_data(), "email": "me@example.com"});
            fs::write(
                config::legacy_credentials_path(),
                serde_json::to_string(&doc).unwrap(),
            )
            .unwrap();
            assert_eq!(config::load_credentials_with_options(false).unwrap(), None);
        });
    }

    #[test]
    fn test_corrupt_credentials_raise_config_error() {
        for content in [
            "{".to_string(),
            serde_json::to_string(&json!({"email": "me@example.com"})).unwrap(),
            serde_json::to_string(&json!([1])).unwrap(),
        ] {
            with_isolated_home(|_| {
                config::ensure_private_dir(&config::config_dir()).unwrap();
                fs::write(config::credentials_path(), &content).unwrap();
                assert!(config::load_credentials().is_err());
            });
        }
    }

    #[test]
    fn test_unknown_fields_survive_a_rewrite() {
        with_isolated_home(|_| {
            save_test_login();
            let path = config::credentials_path();
            let mut doc: Value = serde_json::from_str(&fs::read_to_string(&path).unwrap()).unwrap();
            doc.as_object_mut()
                .unwrap()
                .insert("added_by_a_newer_version".to_string(), json!({"x": 1}));
            fs::write(&path, serde_json::to_string(&doc).unwrap()).unwrap();
            let loaded = config::load_credentials().unwrap().unwrap();
            config::save_credentials(&loaded).unwrap();
            let after: Value = serde_json::from_str(&fs::read_to_string(&path).unwrap()).unwrap();
            assert_eq!(after["added_by_a_newer_version"], json!({"x": 1}));
        });
    }

    #[test]
    fn test_token_is_created_once_private_and_stable() {
        with_isolated_home(|_| {
            assert_eq!(config::read_token(), None);
            let token = config::load_or_create_token().unwrap();
            assert!(token.len() >= 32);
            assert_eq!(mode(&config::token_path()), 0o600);
            assert_eq!(config::load_or_create_token().unwrap(), token);
            assert_eq!(config::read_token().as_deref(), Some(token.as_str()));
        });
    }

    #[test]
    fn test_port_comes_from_env_and_is_validated() {
        with_isolated_home(|_| {
            assert_eq!(config::daemon_port().unwrap(), 8765);
            env::set_var(config::PORT_ENV, "9000");
            assert_eq!(config::daemon_port().unwrap(), 9000);
            for bad in ["abc", "0", "70000"] {
                env::set_var(config::PORT_ENV, bad);
                assert!(matches!(config::daemon_port(), Err(ConfigError(_))));
            }
        });
    }

    #[test]
    fn test_email_is_masked_for_display() {
        assert_eq!(config::mask_email("james@example.com"), "j***@example.com");
        assert_eq!(config::mask_email("nonsense"), "***");
    }

    // =========================================================================
    // 2. test_auth.py ports
    // =========================================================================

    struct FakeApiClient {
        id: usize,
        email: String,
        log: Arc<Mutex<Vec<(String, String, usize, String)>>>,
        fail_request: Option<ApiError>,
    }

    impl ApiClient for FakeApiClient {
        fn request_code_v4(&self) -> Result<(), ApiError> {
            if let Some(ref err) = self.fail_request {
                return Err(err.clone());
            }
            self.log.lock().unwrap().push((
                "request".to_string(),
                self.email.clone(),
                self.id,
                String::new(),
            ));
            Ok(())
        }

        fn code_login_v4(&self, code: &str) -> Result<Map<String, Value>, ApiError> {
            self.log.lock().unwrap().push((
                "login".to_string(),
                self.email.clone(),
                self.id,
                code.to_string(),
            ));
            if code != "123456" {
                return Err(ApiError::new("RoborockInvalidCode", "bad code"));
            }
            Ok(user_data())
        }

        fn base_url(&self) -> Option<String> {
            Some("https://usiot.roborock.com".to_string())
        }
    }

    fn make_test_flow() -> (
        LoginFlow,
        Arc<Mutex<Vec<(String, String, usize, String)>>>,
        Arc<Mutex<usize>>,
    ) {
        let log = Arc::new(Mutex::new(Vec::new()));
        let count = Arc::new(Mutex::new(0usize));
        let log_clone = log.clone();
        let count_clone = count.clone();
        let flow = LoginFlow::new(Some(Arc::new(move |email: &str| {
            let mut c = count_clone.lock().unwrap();
            *c += 1;
            Arc::new(FakeApiClient {
                id: *c,
                email: email.to_string(),
                log: log_clone.clone(),
                fail_request: None,
            })
        })));
        (flow, log, count)
    }

    #[test]
    fn test_logged_out_status_carries_the_setup_hint() {
        with_isolated_home(|_| {
            let st = auth::auth_status().as_dict();
            assert_eq!(
                Value::Object(st),
                json!({"authenticated": false, "hint": auth::SETUP_HINT})
            );
            let err = auth::require_credentials().unwrap_err();
            assert!(err.is_not_authenticated());
            assert!(err.message().contains("rrctl setup"));
        });
    }

    #[test]
    fn test_logged_in_status_masks_the_email() {
        with_isolated_home(|_| {
            save_test_login();
            let st = auth::auth_status().as_dict();
            assert_eq!(st.get("authenticated"), Some(&Value::Bool(true)));
            assert_eq!(
                st.get("email"),
                Some(&Value::String("m***@example.com".to_string()))
            );
            assert!(!st.contains_key("hint"));
        });
    }

    #[test]
    fn test_corrupt_credentials_read_as_logged_out_not_a_crash() {
        with_isolated_home(|_| {
            config::ensure_private_dir(&config::config_dir()).unwrap();
            fs::write(config::credentials_path(), "{").unwrap();
            let st = auth::auth_status();
            assert!(!st.authenticated && st.error.is_some());
            assert!(auth::require_credentials().is_err());
        });
    }

    #[test]
    fn test_code_flow_stores_a_login_using_the_client_that_requested_the_code() {
        with_isolated_home(|_| {
            let (flow, log, made) = make_test_flow();
            flow.request_code("  Me@Example.com ").unwrap();
            let creds = flow.complete("me@example.com", " 123 456 ").unwrap();
            assert_eq!(
                *made.lock().unwrap(),
                1,
                "login must reuse the requesting client"
            );
            assert_eq!(log.lock().unwrap()[1].3, "123456");
            let stored = config::load_credentials().unwrap().unwrap();
            assert_eq!(stored.email, "me@example.com");
            assert_eq!(creds.email, "me@example.com");
            assert_eq!(stored.user_data, user_data());
            assert_eq!(
                stored.base_url.as_deref(),
                Some("https://usiot.roborock.com")
            );
        });
    }

    #[test]
    fn test_wrong_code_is_explained_and_can_be_retried() {
        with_isolated_home(|_| {
            let (flow, _, _) = make_test_flow();
            flow.request_code("me@example.com").unwrap();
            let err = flow.complete("me@example.com", "000000").unwrap_err();
            assert!(err.message().contains("wrong or has expired"));
            assert!(config::load_credentials().unwrap().is_none());
            flow.complete("me@example.com", "123456").unwrap();
            assert!(config::load_credentials().unwrap().is_some());
        });
    }

    #[test]
    fn test_completing_without_requesting_first_is_refused() {
        with_isolated_home(|_| {
            let (flow, _, made) = make_test_flow();
            let err = flow.complete("me@example.com", "123456").unwrap_err();
            assert!(err.message().contains("Request one first"));
            assert_eq!(*made.lock().unwrap(), 0);
        });
    }

    #[test]
    fn test_non_numeric_code_never_reaches_roborock() {
        for code in ["", "12ab", "one two"] {
            with_isolated_home(|_| {
                let (flow, log, _) = make_test_flow();
                flow.request_code("me@example.com").unwrap();
                let err = flow.complete("me@example.com", code).unwrap_err();
                assert!(err.message().contains("number"));
                let actions: Vec<String> =
                    log.lock().unwrap().iter().map(|e| e.0.clone()).collect();
                assert_eq!(actions, vec!["request".to_string()]);
            });
        }
    }

    #[test]
    fn test_bad_email_is_refused_before_any_request() {
        with_isolated_home(|_| {
            let (flow, _, made) = make_test_flow();
            let err = flow.request_code("not-an-email").unwrap_err();
            assert!(err.message().contains("valid email"));
            assert_eq!(*made.lock().unwrap(), 0);
        });
    }

    #[test]
    fn test_unrecognised_failure_keeps_the_original_message() {
        with_isolated_home(|_| {
            let flow = LoginFlow::new(Some(Arc::new(|email: &str| {
                Arc::new(FakeApiClient {
                    id: 1,
                    email: email.to_string(),
                    log: Arc::new(Mutex::new(Vec::new())),
                    fail_request: Some(ApiError::new("RuntimeError", "socket closed")),
                })
            })));
            let err = flow.request_code("me@example.com").unwrap_err();
            assert!(err.message().contains("socket closed"));
        });
    }

    // =========================================================================
    // 3. test_device.py ports
    // =========================================================================

    fn make_roborock_vacuum(
        in_cleaning: i64,
        mut status_mod: impl FnMut(&mut RawVacuumStatus),
    ) -> RoborockVacuum {
        let creds = Credentials::new("me@example.com", user_data());
        let vac = RoborockVacuum::new(creds, None, Some(PathBuf::from("/tmp/roborock-cache")));
        let mut raw = RawVacuumStatus {
            in_cleaning: Some(in_cleaning),
            ..RawVacuumStatus::default()
        };
        status_mod(&mut raw);
        let dev = DeviceCandidate {
            duid: "duid-1".to_string(),
            name: "Rocky".to_string(),
            model: Some("a70".to_string()),
            is_local_connected: true,
            supports_v1: true,
        };
        vac.set_test_state(dev, raw, default_rooms());
        vac
    }

    #[test]
    fn test_rooms_resolve_by_name_ignoring_case_or_by_id_without_duplicates() {
        let wanted = vec![
            json!("kitchen"),
            json!("LIVING ROOM"),
            json!("16"),
            json!(17),
        ];
        assert_eq!(
            resolve_rooms(&wanted, &default_rooms()).unwrap(),
            vec![16, 17]
        );
    }

    #[test]
    fn test_unknown_room_lists_what_is_available() {
        let err = resolve_rooms(&[json!("Garage")], &default_rooms()).unwrap_err();
        assert!(err
            .message()
            .contains("Unknown room \"Garage\". Available: Kitchen, Living Room"));
        let err2 = resolve_rooms(&[json!("99")], &default_rooms()).unwrap_err();
        assert!(err2.message().contains("Unknown room \"99\""));
    }

    #[test]
    fn test_no_rooms_is_an_error_not_a_whole_home_clean() {
        let err = resolve_rooms(&[], &default_rooms()).unwrap_err();
        assert!(err.message().contains("at least one room"));
    }

    #[test]
    fn test_simple_actions_map_to_roborock_commands() {
        let vac = make_roborock_vacuum(0, |_| {});
        for &(action, raw) in device::SIMPLE_ACTIONS {
            assert_eq!(
                vac.resolve_action(action, &Map::new()).unwrap(),
                (raw.to_string(), None)
            );
        }
    }

    #[test]
    fn test_resume_continues_the_kind_of_clean_that_was_paused() {
        for (in_cleaning, raw) in [
            (0, "app_start"),
            (1, "app_start"),
            (2, "resume_zoned_clean"),
            (3, "resume_segment_clean"),
        ] {
            let vac = make_roborock_vacuum(in_cleaning, |_| {});
            assert_eq!(
                vac.resolve_action("resume", &Map::new()).unwrap(),
                (raw.to_string(), None)
            );
        }
    }

    #[test]
    fn test_clean_rooms_builds_a_segment_clean() {
        let vac = make_roborock_vacuum(0, |_| {});
        let params = json!({"rooms": ["Kitchen"], "repeat": 2})
            .as_object()
            .unwrap()
            .clone();
        assert_eq!(
            vac.resolve_action("clean_rooms", &params).unwrap(),
            (
                "app_segment_clean".to_string(),
                Some(json!([{"segments": [16], "repeat": 2}]))
            )
        );
        let bad_params = json!({"rooms": ["Kitchen"], "repeat": 9})
            .as_object()
            .unwrap()
            .clone();
        let err = vac.resolve_action("clean_rooms", &bad_params).unwrap_err();
        assert!(err.message().contains("repeat"));
    }

    #[test]
    fn test_unknown_action_is_refused_by_name() {
        let vac = make_roborock_vacuum(0, |_| {});
        let err = vac.resolve_action("explode", &Map::new()).unwrap_err();
        assert!(err.is_unknown_action());
        assert!(err.message().contains("Unknown action \"explode\""));
    }

    #[test]
    fn test_snapshot_reports_no_error_when_the_code_is_zero() {
        let vac = make_roborock_vacuum(0, |_| {});
        let snap = vac.snapshot().unwrap();
        assert_eq!(snap.get("error"), Some(&Value::Null));
        assert_eq!(snap.get("error_code"), Some(&Value::Null));
        assert_eq!(snap.get("state"), Some(&json!("charging")));
        assert_eq!(snap.get("state_code"), Some(&json!(8)));
        assert_eq!(snap.get("battery"), Some(&json!(87)));
        assert_eq!(
            snap.get("device"),
            Some(&json!({"id": "duid-1", "name": "Rocky", "model": "a70", "local": true}))
        );
    }

    #[test]
    fn test_snapshot_reports_a_real_error() {
        let vac = make_roborock_vacuum(0, |st| {
            st.error_code = Some(5);
            st.error_code_name = Some("main brush jammed".to_string());
        });
        let snap = vac.snapshot().unwrap();
        assert_eq!(snap.get("error"), Some(&json!("main brush jammed")));
        assert_eq!(snap.get("error_code"), Some(&json!(5)));
    }

    #[test]
    fn test_snapshot_survives_a_label_that_cannot_be_computed() {
        let vac = make_roborock_vacuum(0, |st| {
            st.fan_speed_name = Err("device features not loaded".to_string());
        });
        let snap = vac.snapshot().unwrap();
        assert_eq!(snap.get("fan_speed"), Some(&Value::Null));
    }

    #[test]
    fn test_calls_before_connect_fail_clearly() {
        let creds = Credentials::new("me@example.com", user_data());
        let vac = RoborockVacuum::new(creds, None, Some(PathBuf::from("/tmp/roborock-cache")));
        let err = vac.command("pause", None).unwrap_err();
        assert!(err.message().contains("Not connected"));
    }

    #[test]
    fn test_device_selection() {
        let v1 = DeviceCandidate {
            duid: "a".to_string(),
            name: "Rocky".to_string(),
            model: Some("a70".to_string()),
            is_local_connected: true,
            supports_v1: true,
        };
        let other = DeviceCandidate {
            duid: "b".to_string(),
            name: "Dyad".to_string(),
            model: None,
            is_local_connected: false,
            supports_v1: false,
        };
        let creds = Credentials::new("me@example.com", user_data());
        let list = vec![other.clone(), v1.clone()];

        assert_eq!(
            RoborockVacuum::new(creds.clone(), None, None)
                .select_device(&list)
                .unwrap(),
            &v1
        );
        assert_eq!(
            RoborockVacuum::new(creds.clone(), Some("Rocky".to_string()), None)
                .select_device(&list)
                .unwrap(),
            &v1
        );
        assert_eq!(
            RoborockVacuum::new(creds.clone(), Some("a".to_string()), None)
                .select_device(&list)
                .unwrap(),
            &v1
        );
        assert!(
            RoborockVacuum::new(creds.clone(), Some("Dyad".to_string()), None)
                .select_device(&list)
                .unwrap_err()
                .message()
                .contains("does not support yet")
        );
        assert!(
            RoborockVacuum::new(creds.clone(), Some("nope".to_string()), None)
                .select_device(&[v1])
                .unwrap_err()
                .message()
                .contains("No device named")
        );
        assert!(RoborockVacuum::new(creds.clone(), None, None)
            .select_device(&[])
            .unwrap_err()
            .message()
            .contains("no devices"));
        assert!(RoborockVacuum::new(creds, None, None)
            .select_device(&[other])
            .unwrap_err()
            .message()
            .contains("does not support yet"));
    }

    // =========================================================================
    // 4. test_state.py ports
    // =========================================================================

    fn make_service_for(
        vacuum: Arc<FakeVacuum>,
        poll_parked: Duration,
    ) -> (Arc<StateStore>, Arc<VacuumService>) {
        let store = Arc::new(StateStore::new());
        let vac_trait: Arc<dyn Vacuum> = vacuum;
        let opts = ServiceOptions {
            poll_parked,
            poll_active: Duration::from_millis(10),
            map_parked: Duration::from_secs(600),
            backoff_initial: Duration::from_millis(10),
            backoff_max: Duration::from_secs(1),
        };
        let service = Arc::new(VacuumService::new(
            store.clone(),
            Some(Arc::new(move |_| vac_trait.clone())),
            opts,
        ));
        (store, service)
    }

    #[test]
    fn test_store_only_announces_real_changes() {
        let store = StateStore::new();
        let queue = store.subscribe();
        assert!(store.set_status(
            json!({"connected": true, "battery": 50, "updated_at": 1})
                .as_object()
                .unwrap()
                .clone()
        ));
        assert!(!store.set_status(
            json!({"connected": true, "battery": 50, "updated_at": 2})
                .as_object()
                .unwrap()
                .clone()
        ));
        assert!(store.set_status(
            json!({"connected": true, "battery": 49, "updated_at": 3})
                .as_object()
                .unwrap()
                .clone()
        ));
        assert_eq!(queue.qsize(), 2);
        assert_eq!(store.status().get("updated_at"), Some(&json!(3)));
    }

    #[test]
    fn test_map_version_moves_only_when_the_image_does() {
        let store = StateStore::new();
        let queue = store.subscribe();
        let png = png_bytes();
        assert!(!store.set_map(None));
        assert!(store.set_map(Some(&png)));
        assert!(!store.set_map(Some(&png)));
        let mut png2 = png.clone();
        png2.push(b'x');
        assert!(store.set_map(Some(&png2)));
        assert_eq!(store.map_version(), 2);
        assert_eq!(store.status().get("map_version"), Some(&json!(2)));
        let ev1 = queue.get_nowait().unwrap().unwrap();
        let ev2 = queue.get_nowait().unwrap().unwrap();
        assert_eq!(ev1.0, "map");
        assert_eq!(ev1.1.get("version"), Some(&json!(1)));
        assert_eq!(ev2.0, "map");
        assert_eq!(ev2.1.get("version"), Some(&json!(2)));
    }

    #[test]
    fn test_a_stalled_subscriber_loses_old_events_not_new_ones() {
        let store = StateStore::new();
        let queue = store.subscribe();
        for battery in 0..100 {
            store.set_status(json!({"battery": battery}).as_object().unwrap().clone());
        }
        assert_eq!(queue.qsize(), queue.maxsize());
        let mut last = None;
        while let Some(Some((_, doc))) = queue.get_nowait() {
            last = doc.get("battery").and_then(|v| v.as_i64());
        }
        assert_eq!(last, Some(99));
    }

    #[test]
    fn test_unsubscribed_queues_hear_nothing_and_close_ends_streams() {
        let store = StateStore::new();
        let gone = store.subscribe();
        let staying = store.subscribe();
        store.unsubscribe(&gone);
        store.close();
        assert!(gone.is_empty());
        assert_eq!(staying.get_nowait(), Some(None));
    }

    #[test]
    fn test_without_a_login_the_service_reports_it_and_refuses_commands() {
        with_isolated_home(|_| {
            let vacuum = FakeVacuum::new();
            let (store, service) = make_service_for(vacuum.clone(), Duration::from_secs(60));
            service.start();
            until(|| store.status().contains_key("hint"));
            assert_eq!(store.status().get("authenticated"), Some(&json!(false)));
            assert_eq!(store.status().get("hint"), Some(&json!(auth::SETUP_HINT)));
            assert_eq!(*vacuum.connects.lock().unwrap(), 0);
            let err = service.command("pause", None).unwrap_err();
            assert!(
                matches!(err, CommandError::Unavailable(ref u) if u.code == "not_authenticated")
            );
            service.stop();
        });
    }

    #[test]
    fn test_connects_polls_and_publishes_status_and_map() {
        with_isolated_home(|_| {
            save_test_login();
            let vacuum = FakeVacuum::new();
            let (store, service) = make_service_for(vacuum.clone(), Duration::from_secs(60));
            service.start();
            until(|| store.map_png().is_some());
            let st = store.status();
            assert_eq!(st.get("authenticated"), Some(&json!(true)));
            assert_eq!(st.get("connected"), Some(&json!(true)));
            assert_eq!(st.get("state"), Some(&json!("charging")));
            assert_eq!(st.get("map_version"), Some(&json!(1)));
            assert_eq!(store.map_png().unwrap(), png_bytes());
            service.stop();
            assert_eq!(*vacuum.closed.lock().unwrap(), 1);
        });
    }

    #[test]
    fn test_command_reaches_the_vacuum_and_triggers_an_immediate_refresh() {
        with_isolated_home(|_| {
            save_test_login();
            let vacuum = FakeVacuum::new();
            let (store, service) = make_service_for(vacuum.clone(), Duration::from_secs(60));
            service.start();
            until(|| store.status().get("connected") == Some(&json!(true)));
            {
                let mut snap = vacuum.snapshot.lock().unwrap();
                snap.insert("state".to_string(), json!("cleaning"));
                snap.insert("state_code".to_string(), json!(5));
            }
            let params = json!({"rooms": ["Kitchen"]}).as_object().unwrap().clone();
            let res = service.command("clean_rooms", Some(&params)).unwrap();
            assert_eq!(res, json!(["ok"]));
            assert_eq!(
                *vacuum.commands.lock().unwrap(),
                vec![("clean_rooms".to_string(), Some(params))]
            );
            until(|| store.status().get("state") == Some(&json!("cleaning")));
            service.stop();
        });
    }

    #[test]
    fn test_failed_connect_is_reported_then_retried() {
        with_isolated_home(|_| {
            save_test_login();
            let vacuum = FakeVacuum::new();
            *vacuum.fail_connect.lock().unwrap() = 2;
            let (store, service) = make_service_for(vacuum.clone(), Duration::from_secs(60));
            service.start();
            until(|| {
                store.status().get("error") == Some(&json!("cloud unreachable"))
                    || store.status().get("connected") == Some(&json!(true))
            });
            until(|| store.status().get("connected") == Some(&json!(true)));
            assert_eq!(*vacuum.connects.lock().unwrap(), 3);
            service.stop();
        });
    }

    #[test]
    fn test_a_failed_poll_keeps_last_known_state_and_recovers() {
        with_isolated_home(|_| {
            save_test_login();
            let vacuum = FakeVacuum::new();
            let (store, service) = make_service_for(vacuum.clone(), Duration::from_millis(10));
            service.start();
            until(|| store.status().get("connected") == Some(&json!(true)));
            *vacuum.fail_status.lock().unwrap() = true;
            until(|| store.status().get("connected") == Some(&json!(false)));
            assert_eq!(store.status().get("error"), Some(&json!("no answer")));
            assert_eq!(store.status().get("state"), Some(&json!("charging")));
            *vacuum.fail_status.lock().unwrap() = false;
            until(|| store.status().get("connected") == Some(&json!(true)));
            assert_eq!(store.status().get("error"), Some(&Value::Null));
            assert_eq!(*vacuum.connects.lock().unwrap(), 1);
            service.stop();
        });
    }

    #[test]
    fn test_rejected_login_stops_the_loop_and_asks_for_setup() {
        with_isolated_home(|_| {
            save_test_login();
            let vacuum = FakeVacuum::new();
            let (store, service) = make_service_for(vacuum.clone(), Duration::from_millis(10));
            service.start();
            until(|| store.status().get("connected") == Some(&json!(true)));
            *vacuum.credentials_rejected.lock().unwrap() = true;
            until(|| store.status().get("authenticated") == Some(&json!(false)));
            assert!(store
                .status()
                .get("error")
                .and_then(|v| v.as_str())
                .unwrap_or("")
                .contains("rejected"));
            let err = service.command("pause", None).unwrap_err();
            assert!(
                matches!(err, CommandError::Unavailable(ref u) if u.code == "not_authenticated")
            );
            let connects = *vacuum.connects.lock().unwrap();
            thread::sleep(Duration::from_millis(40));
            assert_eq!(*vacuum.connects.lock().unwrap(), connects);
            service.stop();
        });
    }

    #[test]
    fn test_reload_picks_up_a_login_made_after_start() {
        with_isolated_home(|_| {
            let vacuum = FakeVacuum::new();
            let (store, service) = make_service_for(vacuum, Duration::from_secs(60));
            service.start();
            until(|| store.status().contains_key("hint"));
            save_test_login();
            service.reload();
            until(|| store.status().get("connected") == Some(&json!(true)));
            assert!(!store.status().contains_key("hint"));
            service.stop();
        });
    }

    #[test]
    fn test_pushed_updates_are_published_without_waiting_for_a_poll() {
        with_isolated_home(|_| {
            save_test_login();
            let vacuum = FakeVacuum::new();
            let (store, service) = make_service_for(vacuum.clone(), Duration::from_secs(60));
            service.start();
            until(|| {
                vacuum.listener.lock().unwrap().is_some()
                    && store.status().get("connected") == Some(&json!(true))
            });
            let mut pushed = default_status_doc();
            pushed.insert("battery".to_string(), json!(42));
            vacuum.push_update(pushed);
            assert_eq!(store.status().get("battery"), Some(&json!(42)));
            service.stop();
        });
    }

    // =========================================================================
    // 5. test_server.py ports
    // =========================================================================

    fn run_with_server<F>(vacuum: Arc<FakeVacuum>, wait_connected: bool, scenario: F)
    where
        F: FnOnce(u16, &Arc<StateStore>, &Arc<StopSignal>),
    {
        let (store, service) = make_service_for(vacuum, Duration::from_secs(60));
        let stop = Arc::new(StopSignal::new());
        let mut server = DaemonServer::start(
            0,
            store.clone(),
            service.clone(),
            TOKEN.to_string(),
            Some(stop.clone()),
        )
        .unwrap();
        let port = server.port();
        service.start();
        if wait_connected {
            until(|| store.map_png().is_some());
        }
        scenario(port, &store, &stop);
        service.stop();
        server.shutdown();
    }

    #[test]
    fn test_requests_without_the_token_are_refused() {
        with_isolated_home(|_| {
            save_test_login();
            let vacuum = FakeVacuum::new();
            run_with_server(vacuum.clone(), true, |port, _, _| {
                let raw_client = DaemonClient::with_port(port, None);
                for path in ["/status", "/map.png", "/events"] {
                    assert_eq!(
                        raw_client
                            .raw_request("GET", path, &[], None)
                            .unwrap()
                            .status,
                        401
                    );
                }
                assert_eq!(
                    raw_client
                        .raw_request("GET", "/status", &[("Authorization", "Bearer wrong")], None)
                        .unwrap()
                        .status,
                    401
                );
                let basic = format!("Basic {TOKEN}");
                assert_eq!(
                    raw_client
                        .raw_request("GET", "/status", &[("Authorization", &basic)], None)
                        .unwrap()
                        .status,
                    401
                );
                assert_eq!(
                    raw_client
                        .raw_request(
                            "POST",
                            "/command",
                            &[("Content-Type", "application/json")],
                            Some(b"{\"command\":\"pause\"}")
                        )
                        .unwrap()
                        .status,
                    401
                );
                assert!(vacuum.commands.lock().unwrap().is_empty());
            });
        });
    }

    #[test]
    fn test_token_in_the_query_string_is_not_accepted() {
        with_isolated_home(|_| {
            save_test_login();
            let vacuum = FakeVacuum::new();
            run_with_server(vacuum, true, |port, _, _| {
                let raw_client = DaemonClient::with_port(port, None);
                let path = format!("/status?token={TOKEN}");
                assert_eq!(
                    raw_client
                        .raw_request("GET", &path, &[], None)
                        .unwrap()
                        .status,
                    401
                );
            });
        });
    }

    #[test]
    fn test_cross_origin_requests_are_refused_even_with_the_token() {
        with_isolated_home(|_| {
            save_test_login();
            let vacuum = FakeVacuum::new();
            run_with_server(vacuum.clone(), true, |port, _, _| {
                let raw_client = DaemonClient::with_port(port, None);
                let auth_hdr = format!("Bearer {TOKEN}");
                for origin in ["https://evil.example", "http://127.0.0.1:1", "null"] {
                    let resp = raw_client
                        .raw_request(
                            "POST",
                            "/command",
                            &[
                                ("Authorization", &auth_hdr),
                                ("Origin", origin),
                                ("Content-Type", "application/json"),
                            ],
                            Some(b"{\"command\":\"pause\"}"),
                        )
                        .unwrap();
                    assert_eq!(resp.status, 403, "{origin}");
                    assert_eq!(resp.json().unwrap()["error"], json!("forbidden_origin"));
                }
                assert!(vacuum.commands.lock().unwrap().is_empty());
                let own_origin = format!("http://127.0.0.1:{port}");
                let ok_resp = raw_client
                    .raw_request(
                        "GET",
                        "/status",
                        &[("Authorization", &auth_hdr), ("Origin", &own_origin)],
                        None,
                    )
                    .unwrap();
                assert_eq!(ok_resp.status, 200);
            });
        });
    }

    #[test]
    fn test_a_foreign_host_header_is_refused() {
        with_isolated_home(|_| {
            save_test_login();
            let vacuum = FakeVacuum::new();
            run_with_server(vacuum, true, |port, _, _| {
                let raw_client = DaemonClient::with_port(port, None);
                let auth_hdr = format!("Bearer {TOKEN}");
                let evil_host = format!("evil.example:{port}");
                let resp = raw_client
                    .raw_request(
                        "GET",
                        "/status",
                        &[("Authorization", &auth_hdr), ("Host", &evil_host)],
                        None,
                    )
                    .unwrap();
                assert_eq!(resp.status, 403);
                assert_eq!(resp.json().unwrap()["error"], json!("forbidden_host"));

                let local_host = format!("localhost:{port}");
                let ok_resp = raw_client
                    .raw_request(
                        "GET",
                        "/status",
                        &[("Authorization", &auth_hdr), ("Host", &local_host)],
                        None,
                    )
                    .unwrap();
                assert_eq!(ok_resp.status, 200);
            });
        });
    }

    #[test]
    fn test_no_response_grants_cross_origin_access() {
        with_isolated_home(|_| {
            save_test_login();
            let vacuum = FakeVacuum::new();
            run_with_server(vacuum, true, |port, _, _| {
                let raw_client = DaemonClient::with_port(port, None);
                let auth_hdr = format!("Bearer {TOKEN}");
                let resp = raw_client
                    .raw_request("GET", "/status", &[("Authorization", &auth_hdr)], None)
                    .unwrap();
                assert!(!resp
                    .headers
                    .keys()
                    .any(|k| k.starts_with("access-control-")));
                assert_eq!(resp.header("cache-control"), Some("no-store"));
            });
        });
    }

    #[test]
    fn test_dashboard_and_health_are_public_but_carry_no_secrets() {
        with_isolated_home(|_| {
            save_test_login();
            let vacuum = FakeVacuum::new();
            run_with_server(vacuum, true, |port, _, _| {
                let raw_client = DaemonClient::with_port(port, None);
                let page = raw_client.raw_request("GET", "/", &[], None).unwrap();
                assert_eq!(page.status, 200);
                assert_eq!(page.content_type(), "text/html");
                assert!(page
                    .header("content-security-policy")
                    .unwrap()
                    .contains("frame-ancestors 'none'"));
                let body = page.text();
                assert!(body.contains("<canvas") && !body.contains(TOKEN));

                let health = raw_client
                    .raw_request("GET", "/healthz", &[], None)
                    .unwrap()
                    .json()
                    .unwrap();
                assert_eq!(health["service"], json!("vitruvian-roborock"));
                assert_eq!(health["ok"], json!(true));
                assert!(!health.to_string().contains(TOKEN));
            });
        });
    }

    #[test]
    fn test_status_and_map() {
        with_isolated_home(|_| {
            save_test_login();
            let vacuum = FakeVacuum::new();
            run_with_server(vacuum, true, |port, _, _| {
                let raw_client = DaemonClient::with_port(port, None);
                let auth_hdr = format!("Bearer {TOKEN}");
                let status = raw_client
                    .raw_request("GET", "/status", &[("Authorization", &auth_hdr)], None)
                    .unwrap()
                    .json()
                    .unwrap();
                assert_eq!(status["connected"], json!(true));
                assert_eq!(status["battery"], json!(100));
                assert_eq!(status["map_version"], json!(1));

                let picture = raw_client
                    .raw_request("GET", "/map.png", &[("Authorization", &auth_hdr)], None)
                    .unwrap();
                assert_eq!(picture.content_type(), "image/png");
                assert_eq!(picture.body, png_bytes());
                let etag = picture.header("etag").unwrap().to_string();

                let cached = raw_client
                    .raw_request(
                        "GET",
                        "/map.png",
                        &[("Authorization", &auth_hdr), ("If-None-Match", &etag)],
                        None,
                    )
                    .unwrap();
                assert_eq!(cached.status, 304);
            });
        });
    }

    #[test]
    fn test_map_is_404_until_one_arrives() {
        with_isolated_home(|_| {
            save_test_login();
            let vacuum = FakeVacuum::new();
            *vacuum.png.lock().unwrap() = None;
            run_with_server(vacuum, false, |port, store, _| {
                until(|| store.status().get("connected") == Some(&json!(true)));
                let raw_client = DaemonClient::with_port(port, None);
                let auth_hdr = format!("Bearer {TOKEN}");
                let resp = raw_client
                    .raw_request("GET", "/map.png", &[("Authorization", &auth_hdr)], None)
                    .unwrap();
                assert_eq!(resp.status, 404);
                assert_eq!(resp.json().unwrap()["error"], json!("no_map"));
            });
        });
    }

    #[test]
    fn test_command_round_trip_and_its_refusals() {
        with_isolated_home(|_| {
            save_test_login();
            let vacuum = FakeVacuum::new();
            run_with_server(vacuum.clone(), true, |port, _, _| {
                let raw_client = DaemonClient::with_port(port, None);
                let auth_hdr = format!("Bearer {TOKEN}");
                let ok_resp = raw_client
                    .raw_request(
                        "POST",
                        "/command",
                        &[
                            ("Authorization", &auth_hdr),
                            ("Content-Type", "application/json"),
                        ],
                        Some(
                            serde_json::to_vec(&json!({
                                "command": "clean_rooms",
                                "params": {"rooms": ["Kitchen"]}
                            }))
                            .unwrap()
                            .as_slice(),
                        ),
                    )
                    .unwrap();
                assert_eq!(ok_resp.status, 200);
                assert_eq!(
                    ok_resp.json().unwrap(),
                    json!({"ok": true, "command": "clean_rooms", "result": ["ok"]})
                );

                let cases: Vec<(&str, Vec<u8>, u16, &str)> = vec![
                    (
                        "application/json",
                        serde_json::to_vec(&json!({"command": "bogus"})).unwrap(),
                        400,
                        "unknown_command",
                    ),
                    (
                        "application/json",
                        serde_json::to_vec(&json!({"command": "wash_start"})).unwrap(),
                        502,
                        "device_error",
                    ),
                    (
                        "application/json",
                        serde_json::to_vec(&json!({})).unwrap(),
                        400,
                        "bad_request",
                    ),
                    (
                        "application/json",
                        serde_json::to_vec(&json!({"command": "pause", "params": [1]})).unwrap(),
                        400,
                        "bad_request",
                    ),
                    (
                        "application/json",
                        serde_json::to_vec(&json!(["pause"])).unwrap(),
                        400,
                        "bad_request",
                    ),
                    ("application/json", b"{".to_vec(), 400, "bad_request"),
                    (
                        "application/x-www-form-urlencoded",
                        b"command=pause".to_vec(),
                        415,
                        "unsupported_media_type",
                    ),
                    (
                        "text/plain",
                        b"{\"command\": \"pause\"}".to_vec(),
                        415,
                        "unsupported_media_type",
                    ),
                ];

                for (ct, body, expected_status, expected_code) in cases {
                    let resp = raw_client
                        .raw_request(
                            "POST",
                            "/command",
                            &[("Authorization", &auth_hdr), ("Content-Type", ct)],
                            Some(&body),
                        )
                        .unwrap();
                    assert_eq!(resp.status, expected_status);
                    assert_eq!(resp.json().unwrap()["error"], json!(expected_code));
                }
                assert_eq!(vacuum.commands.lock().unwrap().len(), 1);
            });
        });
    }

    #[test]
    fn test_commands_without_a_login_answer_409_with_the_reason() {
        with_isolated_home(|_| {
            let vacuum = FakeVacuum::new();
            run_with_server(vacuum, false, |port, store, _| {
                until(|| store.status().contains_key("hint"));
                let raw_client = DaemonClient::with_port(port, None);
                let auth_hdr = format!("Bearer {TOKEN}");
                let status = raw_client
                    .raw_request("GET", "/status", &[("Authorization", &auth_hdr)], None)
                    .unwrap()
                    .json()
                    .unwrap();
                assert_eq!(status["authenticated"], json!(false));
                assert!(status["hint"].as_str().unwrap().contains("rrctl setup"));

                let resp = raw_client
                    .raw_request(
                        "POST",
                        "/command",
                        &[
                            ("Authorization", &auth_hdr),
                            ("Content-Type", "application/json"),
                        ],
                        Some(b"{\"command\":\"pause\"}"),
                    )
                    .unwrap();
                assert_eq!(resp.status, 409);
                assert_eq!(resp.json().unwrap()["error"], json!("not_authenticated"));
            });
        });
    }

    #[test]
    fn test_commands_while_disconnected_answer_503() {
        with_isolated_home(|_| {
            save_test_login();
            let vacuum = FakeVacuum::new();
            *vacuum.fail_connect.lock().unwrap() = 10_000;
            run_with_server(vacuum, false, |port, store, _| {
                until(|| store.status().get("error") == Some(&json!("cloud unreachable")));
                let raw_client = DaemonClient::with_port(port, None);
                let auth_hdr = format!("Bearer {TOKEN}");
                let resp = raw_client
                    .raw_request(
                        "POST",
                        "/command",
                        &[
                            ("Authorization", &auth_hdr),
                            ("Content-Type", "application/json"),
                        ],
                        Some(b"{\"command\":\"pause\"}"),
                    )
                    .unwrap();
                assert_eq!(resp.status, 503);
                assert_eq!(resp.json().unwrap()["error"], json!("not_connected"));
            });
        });
    }

    fn read_sse_event<R: BufRead>(reader: &mut R) -> (String, Value) {
        let mut event = String::new();
        let mut data = Value::Null;
        loop {
            let mut line = String::new();
            reader.read_line(&mut line).unwrap();
            let trimmed = line.trim_end_matches(&['\r', '\n'][..]);
            if let Some(ev) = trimmed.strip_prefix("event:") {
                event = ev.trim().to_string();
            } else if let Some(d) = trimmed.strip_prefix("data:") {
                data = serde_json::from_str(d.trim()).unwrap();
            } else if trimmed.is_empty() && !event.is_empty() {
                return (event, data);
            }
        }
    }

    #[test]
    fn test_event_stream_sends_current_state_then_changes() {
        with_isolated_home(|_| {
            save_test_login();
            let vacuum = FakeVacuum::new();
            run_with_server(vacuum.clone(), true, |port, store, _| {
                let mut stream =
                    TcpStream::connect(SocketAddr::from(([127, 0, 0, 1], port))).unwrap();
                stream
                    .set_read_timeout(Some(Duration::from_secs(2)))
                    .unwrap();
                let req = format!(
                    "GET /events HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\nAuthorization: Bearer {TOKEN}\r\n\r\n"
                );
                stream.write_all(req.as_bytes()).unwrap();
                let mut reader = BufReader::new(stream);
                let mut status_line = String::new();
                reader.read_line(&mut status_line).unwrap();
                assert!(status_line.contains("200"));
                loop {
                    let mut hdr = String::new();
                    reader.read_line(&mut hdr).unwrap();
                    if hdr.trim().is_empty() {
                        break;
                    }
                }

                let (ev1, data1) = read_sse_event(&mut reader);
                assert_eq!(ev1, "status");
                assert_eq!(data1["state"], json!("charging"));

                let mut cleaning = default_status_doc();
                cleaning.insert("state".to_string(), json!("cleaning"));
                cleaning.insert("state_code".to_string(), json!(5));
                vacuum.push_update(cleaning);

                let (ev2, data2) = read_sse_event(&mut reader);
                assert_eq!(ev2, "status");
                assert_eq!(data2["state"], json!("cleaning"));

                let mut new_png = png_bytes();
                new_png.extend_from_slice(b"new");
                store.set_map(Some(&new_png));
                let (ev3, data3) = read_sse_event(&mut reader);
                assert_eq!(ev3, "map");
                assert_eq!(data3, json!({"version": 2}));
            });
        });
    }

    #[test]
    fn test_shutdown_sets_the_stop_signal() {
        with_isolated_home(|_| {
            save_test_login();
            let vacuum = FakeVacuum::new();
            run_with_server(vacuum, true, |port, _, stop| {
                let raw_client = DaemonClient::with_port(port, None);
                assert_eq!(
                    raw_client
                        .raw_request(
                            "POST",
                            "/shutdown",
                            &[("Content-Type", "application/json")],
                            Some(b"{}")
                        )
                        .unwrap()
                        .status,
                    401
                );
                assert!(!stop.is_set());

                let auth_hdr = format!("Bearer {TOKEN}");
                assert_eq!(
                    raw_client
                        .raw_request(
                            "POST",
                            "/shutdown",
                            &[
                                ("Authorization", &auth_hdr),
                                ("Content-Type", "application/json"),
                            ],
                            Some(b"{}")
                        )
                        .unwrap()
                        .status,
                    200
                );
                assert!(stop.is_set());
            });
        });
    }

    #[test]
    fn test_rust_client_end_to_end() {
        with_isolated_home(|_| {
            save_test_login();
            env::set_var("HTTP_PROXY", "http://127.0.0.1:9");
            env::set_var("http_proxy", "http://127.0.0.1:9");
            let vacuum = FakeVacuum::new();
            run_with_server(vacuum, true, |port, store, _| {
                let api = DaemonClient::new(
                    Some(port),
                    Some(TOKEN.to_string()),
                    Some(Duration::from_secs(5)),
                )
                .unwrap();
                assert_eq!(
                    api.health().unwrap().get("service"),
                    Some(&json!("vitruvian-roborock"))
                );
                assert_eq!(api.status().unwrap().get("battery"), Some(&json!(100)));
                assert_eq!(api.map_png().unwrap().unwrap(), png_bytes());
                assert_eq!(
                    Value::Object(api.command("pause", None).unwrap()),
                    json!({"ok": true, "command": "pause", "result": ["ok"]})
                );

                let Err(ClientError::Request(refused)) = api.command("bogus", None) else {
                    panic!("expected DaemonRequestError");
                };
                assert_eq!(
                    (refused.status, refused.code().as_str()),
                    (400, "unknown_command")
                );

                let wrong_client = DaemonClient::new(
                    Some(port),
                    Some("wrong".to_string()),
                    Some(Duration::from_secs(5)),
                )
                .unwrap();
                let Err(ClientError::Request(wrong)) = wrong_client.status() else {
                    panic!("expected unauthorized");
                };
                assert_eq!(wrong.code(), "unauthorized");

                assert_eq!(Value::Object(api.reload().unwrap()), json!({"ok": true}));
                until(|| store.status().get("connected") == Some(&json!(true)));
            });
            env::remove_var("HTTP_PROXY");
            env::remove_var("http_proxy");
        });
    }

    #[test]
    fn test_rust_client_reports_a_missing_daemon_and_a_missing_token() {
        with_isolated_home(|_| {
            let probe = TcpListener::bind("127.0.0.1:0").unwrap();
            let free_port = probe.local_addr().unwrap().port();
            drop(probe);

            let api = DaemonClient::new(
                Some(free_port),
                Some(TOKEN.to_string()),
                Some(Duration::from_millis(500)),
            )
            .unwrap();
            assert!(api.health().is_none());
            let err = api.status().unwrap_err();
            assert!(err.to_string().contains("not reachable"));

            let no_tok = DaemonClient::new(Some(free_port), None, None).unwrap();
            let err2 = no_tok.status().unwrap_err();
            assert!(err2.to_string().contains("No daemon token"));
        });
    }

    #[test]
    fn test_a_foreign_program_on_the_port_is_named_instead_of_spawning_into_it() {
        with_isolated_home(|_| {
            let listener = TcpListener::bind("127.0.0.1:0").unwrap();
            let port = listener.local_addr().unwrap().port();
            let stop = Arc::new(StopSignal::new());
            let stop_bg = stop.clone();
            let _ = listener.set_nonblocking(true);
            let bg = thread::spawn(move || {
                while !stop_bg.is_set() {
                    if let Ok((mut s, _)) = listener.accept() {
                        let _ = s.write_all(
                            b"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 12\r\n\r\n{\"ok\": true}",
                        );
                    } else {
                        thread::sleep(Duration::from_millis(5));
                    }
                }
            });

            let spawned = Arc::new(Mutex::new(Vec::new()));
            let spawned_clone = spawned.clone();
            let client = DaemonClient::new(Some(port), Some(TOKEN.to_string()), None).unwrap();
            assert!(client.health().is_none());

            let res =
                daemon::ensure_running_with_spawner(Some(port), Duration::from_secs(1), move |p| {
                    spawned_clone.lock().unwrap().push(p);
                    Ok(Box::new(|| true))
                });
            let err = res.unwrap_err();
            assert!(err
                .to_string()
                .contains(&format!("Port {port} is in use by another program")));
            assert!(spawned.lock().unwrap().is_empty());

            stop.set();
            let _ = bg.join();
        });
    }

    // =========================================================================
    // 6. test_mcp.py ports
    // =========================================================================

    struct FakeMcpDaemon {
        commands: Mutex<Vec<(String, Option<Map<String, Value>>)>>,
        png: Mutex<Option<Vec<u8>>>,
        doc: Mutex<Map<String, Value>>,
        refuse: Mutex<Option<ClientError>>,
    }

    impl FakeMcpDaemon {
        fn new() -> Arc<Self> {
            let mut doc = default_status_doc();
            doc.insert("authenticated".to_string(), json!(true));
            doc.insert("connected".to_string(), json!(true));
            Arc::new(Self {
                commands: Mutex::new(Vec::new()),
                png: Mutex::new(Some(png_bytes())),
                doc: Mutex::new(doc),
                refuse: Mutex::new(None),
            })
        }
    }

    impl DaemonApi for FakeMcpDaemon {
        fn status(&self) -> Result<Map<String, Value>, ClientError> {
            if let Some(ref err) = *self.refuse.lock().unwrap() {
                return Err(err.clone());
            }
            Ok(self.doc.lock().unwrap().clone())
        }

        fn map_png(&self) -> Result<Option<Vec<u8>>, ClientError> {
            if let Some(ref err) = *self.refuse.lock().unwrap() {
                return Err(err.clone());
            }
            Ok(self.png.lock().unwrap().clone())
        }

        fn command(
            &self,
            action: &str,
            params: Option<&Map<String, Value>>,
        ) -> Result<Map<String, Value>, ClientError> {
            if let Some(ref err) = *self.refuse.lock().unwrap() {
                return Err(err.clone());
            }
            self.commands
                .lock()
                .unwrap()
                .push((action.to_string(), params.cloned()));
            Ok(json!({"ok": true, "command": action})
                .as_object()
                .unwrap()
                .clone())
        }
    }

    fn make_mcp_server(daemon: Arc<FakeMcpDaemon>) -> mcp::McpServer {
        let (flow, _, _) = make_test_flow();
        let d_trait: Arc<dyn DaemonApi> = daemon;
        let bridge = Bridge::new(
            Some(Arc::new(move || Ok(d_trait.clone()))),
            Some(flow),
            Some(Arc::new(|| false)),
        );
        build_server(Some(bridge))
    }

    #[test]
    fn test_the_agreed_tools_and_resources_are_exposed() {
        let daemon = FakeMcpDaemon::new();
        let server = make_mcp_server(daemon);
        let tools = server.list_tools();
        let resources = server.list_resources();

        let tool_names: HashSet<String> = tools.iter().map(|t| t.name.clone()).collect();
        let expected_tools: HashSet<String> = [
            "get_status",
            "start_clean",
            "control",
            "return_to_dock",
            "wash_mop",
            "get_map",
            "setup_login",
        ]
        .into_iter()
        .map(ToString::to_string)
        .collect();
        assert_eq!(tool_names, expected_tools);

        let resource_pairs: Vec<(String, String)> = resources
            .iter()
            .map(|r| (r.uri.clone(), r.mime_type.clone()))
            .collect();
        assert_eq!(
            resource_pairs,
            vec![
                (
                    "roborock://status".to_string(),
                    "application/json".to_string()
                ),
                ("roborock://map.png".to_string(), "image/png".to_string()),
                (
                    "ui://dashboard".to_string(),
                    "text/html;profile=mcp-app".to_string()
                ),
            ]
        );

        let get_status = tools.iter().find(|t| t.name == "get_status").unwrap();
        assert_eq!(
            get_status.meta,
            Some(json!({"ui": {"resourceUri": "ui://dashboard"}}))
        );
        assert!(get_status.annotations.read_only_hint);

        let control = tools.iter().find(|t| t.name == "control").unwrap();
        assert_eq!(
            control.input_schema["properties"]["action"]["enum"],
            json!(["pause", "resume", "stop", "find"])
        );
        assert!(tools.iter().all(|t| !t.description.is_empty()));
    }

    #[test]
    fn test_get_status_returns_the_daemon_document() {
        let daemon = FakeMcpDaemon::new();
        let server = make_mcp_server(daemon);
        let res = server.call_tool("get_status", &Map::new()).unwrap();
        assert_eq!(
            res.structured_content.unwrap().get("state"),
            Some(&json!("charging"))
        );
    }

    #[test]
    fn test_unauthenticated_status_is_an_answer_not_an_error() {
        let daemon = FakeMcpDaemon::new();
        let doc = json!({
            "authenticated": false,
            "connected": false,
            "hint": auth::SETUP_HINT
        })
        .as_object()
        .unwrap()
        .clone();
        *daemon.doc.lock().unwrap() = doc.clone();
        let server = make_mcp_server(daemon);
        let res = server.call_tool("get_status", &Map::new()).unwrap();
        assert!(!res.is_error);
        assert_eq!(res.structured_content, Some(doc));
    }

    #[test]
    fn test_commands_while_logged_out_explain_what_to_do() {
        let daemon = FakeMcpDaemon::new();
        *daemon.refuse.lock().unwrap() = Some(ClientError::Request(DaemonRequestError::new(
            409,
            json!({"ok": false, "error": "not_authenticated", "message": "Not logged in."})
                .as_object()
                .unwrap()
                .clone(),
        )));
        let server = make_mcp_server(daemon);
        for (name, args) in [
            ("start_clean", json!({})),
            ("control", json!({"action": "pause"})),
            ("return_to_dock", json!({})),
            ("wash_mop", json!({})),
        ] {
            let res = server.call_tool(name, args.as_object().unwrap()).unwrap();
            assert!(!res.is_error, "{name}");
            let sc = res.structured_content.unwrap();
            assert_eq!(sc.get("error"), Some(&json!("not_authenticated")));
            assert!(sc
                .get("hint")
                .and_then(|v| v.as_str())
                .unwrap()
                .contains("setup_login"));
        }
        let map_res = server.call_tool("get_map", &Map::new()).unwrap();
        assert!(map_res.content[0]
            .text
            .as_deref()
            .unwrap()
            .contains("Not logged in."));
    }

    #[test]
    fn test_a_daemon_that_will_not_start_is_reported_plainly() {
        let bridge = Bridge::new(
            Some(Arc::new(|| {
                Err(DaemonUnavailable::new(
                    "The daemon did not start on port 8765.",
                ))
            })),
            None,
            None,
        );
        let server = build_server(Some(bridge));
        let res = server.call_tool("get_status", &Map::new()).unwrap();
        assert_eq!(
            Value::Object(res.structured_content.unwrap()),
            json!({
                "ok": false,
                "error": "daemon_unavailable",
                "message": "The daemon did not start on port 8765."
            })
        );
        let map_res = server.call_tool("get_map", &Map::new()).unwrap();
        assert!(map_res.content[0]
            .text
            .as_deref()
            .unwrap()
            .contains("did not start"));
    }

    #[test]
    fn test_action_tools_send_the_right_daemon_commands() {
        let daemon = FakeMcpDaemon::new();
        let server = make_mcp_server(daemon.clone());
        server.call_tool("start_clean", &Map::new()).unwrap();
        server
            .call_tool(
                "start_clean",
                json!({"rooms": ["Kitchen", "Living Room"], "repeat": 2})
                    .as_object()
                    .unwrap(),
            )
            .unwrap();
        server
            .call_tool("control", json!({"action": "pause"}).as_object().unwrap())
            .unwrap();
        server
            .call_tool("control", json!({"action": "resume"}).as_object().unwrap())
            .unwrap();
        server.call_tool("return_to_dock", &Map::new()).unwrap();
        server.call_tool("wash_mop", &Map::new()).unwrap();
        server
            .call_tool("wash_mop", json!({"action": "stop"}).as_object().unwrap())
            .unwrap();

        let cmds = daemon.commands.lock().unwrap().clone();
        assert_eq!(
            cmds,
            vec![
                ("start".to_string(), None),
                (
                    "clean_rooms".to_string(),
                    Some(
                        json!({"rooms": ["Kitchen", "Living Room"], "repeat": 2})
                            .as_object()
                            .unwrap()
                            .clone()
                    )
                ),
                ("pause".to_string(), None),
                ("resume".to_string(), None),
                ("dock".to_string(), None),
                ("wash_start".to_string(), None),
                ("wash_stop".to_string(), None),
            ]
        );
    }

    #[test]
    fn test_control_rejects_actions_outside_its_list() {
        let daemon = FakeMcpDaemon::new();
        let server = make_mcp_server(daemon.clone());
        let err = server
            .call_tool(
                "control",
                json!({"action": "self_destruct"}).as_object().unwrap(),
            )
            .unwrap_err();
        assert!(err
            .to_string()
            .contains("Input should be 'pause', 'resume', 'stop' or 'find'"));
        assert!(daemon.commands.lock().unwrap().is_empty());
    }

    #[test]
    fn test_get_map_returns_a_png_image_or_says_why_not() {
        let daemon = FakeMcpDaemon::new();
        let server = make_mcp_server(daemon.clone());
        let picture = &server.call_tool("get_map", &Map::new()).unwrap().content[0];
        assert_eq!(
            (picture.content_type.as_str(), picture.mime_type.as_deref()),
            ("image", Some("image/png"))
        );
        assert_eq!(
            config::base64_decode(picture.data.as_deref().unwrap()).unwrap(),
            png_bytes()
        );
        *daemon.png.lock().unwrap() = None;
        let none_res = server.call_tool("get_map", &Map::new()).unwrap();
        assert!(none_res.content[0]
            .text
            .as_deref()
            .unwrap()
            .contains("not sent a map yet"));
    }

    #[test]
    fn test_setup_login_is_two_steps_and_stores_the_login() {
        with_isolated_home(|_| {
            let daemon = FakeMcpDaemon::new();
            let server = make_mcp_server(daemon);
            let first = server
                .call_tool(
                    "setup_login",
                    json!({"email": "me@example.com"}).as_object().unwrap(),
                )
                .unwrap()
                .structured_content
                .unwrap();
            assert_eq!(first.get("ok"), Some(&json!(true)));
            assert_eq!(first.get("authenticated"), Some(&json!(false)));
            assert!(first
                .get("next")
                .and_then(|v| v.as_str())
                .unwrap()
                .contains("code"));
            assert!(config::load_credentials().unwrap().is_none());

            let wrong = server
                .call_tool(
                    "setup_login",
                    json!({"email": "me@example.com", "code": "999999"})
                        .as_object()
                        .unwrap(),
                )
                .unwrap()
                .structured_content
                .unwrap();
            assert_eq!(wrong.get("ok"), Some(&json!(false)));
            assert_eq!(wrong.get("error"), Some(&json!("login_failed")));

            let done = server
                .call_tool(
                    "setup_login",
                    json!({"email": "me@example.com", "code": "123456"})
                        .as_object()
                        .unwrap(),
                )
                .unwrap()
                .structured_content
                .unwrap();
            assert_eq!(
                Value::Object(done),
                json!({"ok": true, "authenticated": true, "daemon_reloaded": false})
            );
            assert_eq!(
                config::load_credentials().unwrap().unwrap().email,
                "me@example.com"
            );
        });
    }

    #[test]
    fn test_resources_serve_status_map_and_dashboard() {
        let daemon = FakeMcpDaemon::new();
        let server = make_mcp_server(daemon);
        let st_item = &server.read_resource("roborock://status").unwrap()[0];
        let parsed: Value = serde_json::from_str(st_item.text.as_deref().unwrap()).unwrap();
        assert_eq!(parsed["battery"], json!(100));

        let map_item = &server.read_resource("roborock://map.png").unwrap()[0];
        assert_eq!(map_item.bytes.as_ref().unwrap(), &png_bytes());

        let page = &server.read_resource("ui://dashboard").unwrap()[0];
        assert_eq!(page.mime_type, "text/html;profile=mcp-app");
        assert!(page.text.as_deref().unwrap().contains("<canvas"));
    }

    // =========================================================================
    // 7. test_cli.py ports
    // =========================================================================

    struct FakeCliClient {
        doc: Mutex<Map<String, Value>>,
        png: Mutex<Option<Vec<u8>>>,
        sent: Mutex<Vec<String>>,
        refuse: Mutex<Option<ClientError>>,
        health_doc: Mutex<Option<Map<String, Value>>>,
    }

    impl FakeCliClient {
        fn new() -> Arc<Self> {
            let mut doc = default_status_doc();
            doc.insert("authenticated".to_string(), json!(true));
            doc.insert("connected".to_string(), json!(true));
            Arc::new(Self {
                doc: Mutex::new(doc),
                png: Mutex::new(Some(png_bytes())),
                sent: Mutex::new(Vec::new()),
                refuse: Mutex::new(None),
                health_doc: Mutex::new(None),
            })
        }
    }

    impl DaemonApi for FakeCliClient {
        fn status(&self) -> Result<Map<String, Value>, ClientError> {
            if let Some(ref err) = *self.refuse.lock().unwrap() {
                return Err(err.clone());
            }
            Ok(self.doc.lock().unwrap().clone())
        }

        fn map_png(&self) -> Result<Option<Vec<u8>>, ClientError> {
            Ok(self.png.lock().unwrap().clone())
        }

        fn command(
            &self,
            action: &str,
            _params: Option<&Map<String, Value>>,
        ) -> Result<Map<String, Value>, ClientError> {
            if let Some(ref err) = *self.refuse.lock().unwrap() {
                return Err(err.clone());
            }
            self.sent.lock().unwrap().push(action.to_string());
            Ok(json!({"ok": true}).as_object().unwrap().clone())
        }
    }

    impl CliClient for FakeCliClient {
        fn base_url(&self) -> String {
            "http://127.0.0.1:8765".to_string()
        }

        fn port(&self) -> u16 {
            8765
        }

        fn health(&self) -> Option<Map<String, Value>> {
            self.health_doc.lock().unwrap().clone()
        }

        fn reload(&self) -> Result<Map<String, Value>, ClientError> {
            Ok(json!({"ok": true}).as_object().unwrap().clone())
        }

        fn shutdown(&self) -> Result<Map<String, Value>, ClientError> {
            Ok(json!({"ok": true}).as_object().unwrap().clone())
        }
    }

    fn hooks_with_fake(fake: Arc<FakeCliClient>) -> CliHooks {
        let f1 = fake.clone();
        let f2 = fake;
        let (flow_factory, _, _) = make_test_flow();
        let _ = flow_factory;
        CliHooks {
            ensure_running: Box::new(move |_| Ok(f1.clone() as Arc<dyn CliClient>)),
            probe_client: Box::new(move |_| Ok(f2.clone() as Arc<dyn CliClient>)),
            api_client_factory: Some(Arc::new(|email: &str| {
                Arc::new(FakeApiClient {
                    id: 1,
                    email: email.to_string(),
                    log: Arc::new(Mutex::new(Vec::new())),
                    fail_request: None,
                })
            })),
            prompt_input: Box::new(|_| Ok("123456".to_string())),
        }
    }

    fn run_cli(fake: Arc<FakeCliClient>, args: &[&str]) -> cli::CliExecution {
        let argv: Vec<String> = args.iter().map(|s| s.to_string()).collect();
        let hooks = hooks_with_fake(fake);
        cli::run_with_hooks(&argv, &hooks)
    }

    #[test]
    fn test_every_agreed_command_exists() {
        for sub in [
            "setup",
            "status",
            "map",
            "pause",
            "resume",
            "dock",
            "daemon",
            "mcp",
            "dashboard",
        ] {
            let res = cli::parse_args(&[sub.to_string()]);
            assert!(matches!(res, ParseOutcome::Args(_)), "{sub}");
        }
        let ParseOutcome::Args(daemon_default) = cli::parse_args(&["daemon".to_string()]) else {
            panic!("expected Args");
        };
        assert_eq!(
            daemon_default.command,
            Subcommand::Daemon {
                action: DaemonSubcommand::Run
            }
        );
        let ParseOutcome::Args(daemon_start) = cli::parse_args(&[
            "--port".to_string(),
            "9000".to_string(),
            "daemon".to_string(),
            "start".to_string(),
        ]) else {
            panic!("expected Args");
        };
        assert_eq!(daemon_start.port, Some(9000));
    }

    #[test]
    fn test_version_and_unknown_command() {
        let fake = FakeCliClient::new();
        let ver = run_cli(fake.clone(), &["--version"]);
        assert_eq!(ver.exit_code, 0);
        assert!(ver.stdout.contains(VERSION));

        let refused = run_cli(fake, &["explode"]);
        assert_eq!(refused.exit_code, 2);
    }

    #[test]
    fn test_status_prints_a_summary() {
        let fake = FakeCliClient::new();
        let res = run_cli(fake, &["status"]);
        assert_eq!(res.exit_code, 0);
        assert!(res.stdout.contains("Rocky: charging"));
        assert!(res.stdout.contains("battery   100%"));
        assert!(res.stdout.contains("Kitchen, Living Room"));
    }

    #[test]
    fn test_status_json_is_the_raw_document() {
        let fake = FakeCliClient::new();
        let res = run_cli(fake.clone(), &["status", "--json"]);
        assert_eq!(res.exit_code, 0);
        let parsed: Map<String, Value> = serde_json::from_str(&res.stdout).unwrap();
        assert_eq!(parsed, *fake.doc.lock().unwrap());
    }

    #[test]
    fn test_status_when_logged_out_says_how_to_fix_it_and_fails() {
        let fake = FakeCliClient::new();
        *fake.doc.lock().unwrap() = json!({
            "authenticated": false,
            "connected": false,
            "hint": auth::SETUP_HINT
        })
        .as_object()
        .unwrap()
        .clone();
        let res = run_cli(fake, &["status"]);
        assert_eq!(res.exit_code, 1);
        assert!(res.stdout.contains("rrctl setup"));
    }

    #[test]
    fn test_status_when_unreachable_fails_with_the_reason() {
        let fake = FakeCliClient::new();
        *fake.doc.lock().unwrap() = json!({
            "authenticated": true,
            "connected": false,
            "error": "cloud unreachable"
        })
        .as_object()
        .unwrap()
        .clone();
        let res = run_cli(fake, &["status"]);
        assert_eq!(res.exit_code, 1);
        assert!(res.stdout.contains("cloud unreachable"));
    }

    #[test]
    fn test_action_commands() {
        for (argv, action) in [("pause", "pause"), ("resume", "resume"), ("dock", "dock")] {
            let fake = FakeCliClient::new();
            let res = run_cli(fake.clone(), &[argv]);
            assert_eq!(res.exit_code, 0);
            assert_eq!(*fake.sent.lock().unwrap(), vec![action.to_string()]);
        }
    }

    #[test]
    fn test_a_refused_action_is_one_line_on_stderr() {
        let fake = FakeCliClient::new();
        *fake.refuse.lock().unwrap() = Some(ClientError::Request(DaemonRequestError::new(
            409,
            json!({"error": "not_authenticated", "message": "Not logged in to Roborock."})
                .as_object()
                .unwrap()
                .clone(),
        )));
        let res = run_cli(fake, &["pause"]);
        assert_eq!(res.exit_code, 1);
        assert_eq!(res.stderr, "rrctl: Not logged in to Roborock.\n");
        assert_eq!(res.stdout, "");
    }

    #[test]
    fn test_daemon_that_cannot_start_is_reported() {
        let hooks = CliHooks {
            ensure_running: Box::new(|_| {
                Err(DaemonUnavailable::new(
                    "The daemon did not start on port 8765.",
                ))
            }),
            ..CliHooks::default()
        };
        let res = cli::run_with_hooks(&["status".to_string()], &hooks);
        assert_eq!(res.exit_code, 1);
        assert!(res.stderr.contains("did not start"));
    }

    #[test]
    fn test_map_writes_the_png() {
        with_isolated_home(|home| {
            let target = home.join("m.png");
            let fake = FakeCliClient::new();
            let res = run_cli(fake.clone(), &["map", "-o", &target.to_string_lossy()]);
            assert_eq!(res.exit_code, 0);
            assert_eq!(fs::read(&target).unwrap(), png_bytes());

            *fake.png.lock().unwrap() = None;
            let res2 = run_cli(fake, &["map", "-o", &target.to_string_lossy()]);
            assert_eq!(res2.exit_code, 1);
            assert!(res2.stderr.contains("not sent a map yet"));
        });
    }

    #[test]
    fn test_dashboard_url_carries_the_token_in_the_fragment_only() {
        with_isolated_home(|_| {
            let token = config::load_or_create_token().unwrap();
            let fake = FakeCliClient::new();
            let res = run_cli(fake, &["dashboard", "--no-open"]);
            assert_eq!(res.exit_code, 0);
            let url = res.stdout.trim();
            assert_eq!(url, format!("http://127.0.0.1:8765/#token={token}"));
            assert!(!url.contains('?'));
        });
    }

    #[test]
    fn test_setup_is_a_no_op_when_already_logged_in() {
        with_isolated_home(|_| {
            save_test_login();
            let fake = FakeCliClient::new();
            let res = run_cli(fake, &["setup"]);
            assert_eq!(res.exit_code, 0);
            assert!(res.stdout.contains("Already logged in as m***@example.com"));
        });
    }

    #[test]
    fn test_setup_runs_the_code_flow() {
        with_isolated_home(|_| {
            let fake = FakeCliClient::new();
            let res = run_cli(fake, &["setup", "--email", "me@example.com"]);
            assert_eq!(res.exit_code, 0);
            assert_eq!(
                config::load_credentials().unwrap().unwrap().email,
                "me@example.com"
            );
            assert!(res.stdout.contains("Logged in"));
        });
    }

    #[test]
    fn test_daemon_status_and_stop_when_nothing_is_running() {
        let fake = FakeCliClient::new();
        let st = run_cli(fake.clone(), &["daemon", "status"]);
        assert_eq!(st.exit_code, 1);
        let stop = run_cli(fake, &["daemon", "stop"]);
        assert_eq!(stop.exit_code, 0);
        assert!(stop.stdout.contains("not running"));
    }

    // =========================================================================
    // Release metadata: the release workflow reads Cargo.toml's version, so
    // every manifest a user installs from must say the same, and every MCP
    // config must start the Rust binary.
    // =========================================================================

    const MANIFESTS: &[(&str, &str)] = &[
        ("plugin/plugin.json", include_str!("../plugin/plugin.json")),
        (
            "plugin/.claude-plugin/plugin.json",
            include_str!("../plugin/.claude-plugin/plugin.json"),
        ),
        (
            "plugin/gemini-extension.json",
            include_str!("../plugin/gemini-extension.json"),
        ),
        (
            ".claude-plugin/marketplace.json",
            include_str!("../.claude-plugin/marketplace.json"),
        ),
    ];

    const MCP_CONFIGS: &[(&str, &str)] = &[
        ("plugin/.mcp.json", include_str!("../plugin/.mcp.json")),
        (
            "plugin/mcp_config.json",
            include_str!("../plugin/mcp_config.json"),
        ),
        (
            "plugin/gemini-extension.json",
            include_str!("../plugin/gemini-extension.json"),
        ),
    ];

    #[test]
    fn test_every_manifest_carries_the_cargo_version() {
        let cargo = include_str!("../Cargo.toml");
        let cargo_version = cargo
            .lines()
            .skip_while(|l| l.trim() != "[package]")
            .find_map(|l| l.strip_prefix("version = "))
            .map(|v| v.trim_matches('"'))
            .expect("Cargo.toml [package] has a version");
        assert_eq!(VERSION, cargo_version, "lib.rs VERSION vs Cargo.toml");
        for (name, text) in MANIFESTS {
            let doc: Value = serde_json::from_str(text).unwrap();
            let version = doc
                .get("version")
                .or_else(|| doc["plugins"][0].get("version"))
                .and_then(Value::as_str)
                .unwrap_or_else(|| panic!("{name} has no version"));
            assert_eq!(version, cargo_version, "{name}");
        }
    }

    #[test]
    fn test_every_mcp_config_starts_rrctl_mcp() {
        for (name, text) in MCP_CONFIGS {
            let doc: Value = serde_json::from_str(text).unwrap();
            let server = &doc["mcpServers"]["roborock"];
            assert_eq!(server["command"], "rrctl", "{name}");
            assert_eq!(server["args"], json!(["mcp"]), "{name}");
        }
    }
}
