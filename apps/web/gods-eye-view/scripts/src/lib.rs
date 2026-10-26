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

pub mod build_military_names;
pub mod dev_helpers;
pub mod opensky_import_client;
pub mod verify_cesium_assets;

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    // ---- SHA-256 test vectors (FIPS 180-4) ----

    #[test]
    fn sha256_empty() {
        assert_eq!(
            build_military_names::sha256_hex(b""),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        );
    }

    #[test]
    fn sha256_abc() {
        assert_eq!(
            build_military_names::sha256_hex(b"abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
    }

    #[test]
    fn sha256_hello() {
        assert_eq!(
            build_military_names::sha256_hex(b"hello"),
            "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        );
    }

    #[test]
    fn sha256_448_bits() {
        assert_eq!(
            build_military_names::sha256_hex(
                b"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
            ),
            "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"
        );
    }

    #[test]
    fn sha256_longer_input() {
        let data = b"The quick brown fox jumps over the lazy dog";
        assert_eq!(
            build_military_names::sha256_hex(data),
            "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592"
        );
    }

    // ---- build_military_names::assemble ----

    fn make_row(
        kind: &str,
        id: u64,
        at: u64,
        name: &str,
        military: &str,
        lon: f64,
        lat: f64,
        area: f64,
        xmin: f64,
        ymin: f64,
        xmax: f64,
        ymax: f64,
    ) -> serde_json::Value {
        json!({
            "sources": [{
                "dataset": "OpenStreetMap",
                "record_id": format!("{}{}@{}", kind, id, at),
                "version": "2026-09-23T12:00:00Z"
            }],
            "bbox": {"xmin": xmin, "ymin": ymin, "xmax": xmax, "ymax": ymax},
            "lon": lon,
            "lat": lat,
            "area": area,
            "military": military,
            "name": name,
        })
    }

    #[test]
    fn assemble_valid_single_row() {
        let row = make_row(
            "w", 12345, 67890, "Test Airfield", "airfield", 10.25, 20.25, 5000.0, 10.0, 20.0,
            10.5, 20.5,
        );
        let result = build_military_names::assemble(&[row]).unwrap();
        let records = result.get("records").unwrap().as_array().unwrap();
        assert_eq!(records.len(), 1);
        let r = records[0].as_array().unwrap();
        assert_eq!(r[0].as_str().unwrap(), "w12345");
        assert_eq!(r[1].as_str().unwrap(), "Test Airfield");
        assert_eq!(r[2].as_f64().unwrap(), 10.25);
        assert_eq!(r[3].as_f64().unwrap(), 20.25);
        assert_eq!(r[8].as_u64().unwrap(), 1);
        assert_eq!(r[9].as_i64().unwrap(), 5000);

        assert_eq!(
            result.get("release").unwrap().as_str().unwrap(),
            build_military_names::RELEASE
        );
        let snaps = result.get("snapshots").unwrap().as_array().unwrap();
        assert_eq!(snaps.len(), 1);
        assert_eq!(snaps[0].as_str().unwrap(), "2026-09-23");
    }

    #[test]
    fn assemble_sorts_by_type_then_id() {
        let row_n = make_row(
            "n", 100, 1, "Node", "base", 10.0, 20.0, 50.0, 9.5, 19.5, 10.5, 20.5,
        );
        let row_w = make_row(
            "w", 50, 1, "Way", "airfield", 10.1, 20.1, 60.0, 9.5, 19.5, 10.5, 20.5,
        );
        let row_n2 = make_row(
            "n", 50, 1, "Node2", "range", 10.2, 20.2, 70.0, 9.5, 19.5, 10.5, 20.5,
        );
        let result = build_military_names::assemble(&[row_w, row_n, row_n2]).unwrap();
        let records = result.get("records").unwrap().as_array().unwrap();
        assert_eq!(records[0].as_array().unwrap()[0].as_str().unwrap(), "n50");
        assert_eq!(records[1].as_array().unwrap()[0].as_str().unwrap(), "n100");
        assert_eq!(records[2].as_array().unwrap()[0].as_str().unwrap(), "w50");
    }

    #[test]
    fn assemble_duplicate_osm_identity() {
        let row1 = make_row(
            "w", 12345, 1, "A", "airfield", 10.0, 20.0, 100.0, 9.5, 19.5, 10.5, 20.5,
        );
        let row2 = make_row(
            "w", 12345, 2, "B", "base", 10.1, 20.1, 200.0, 9.5, 19.5, 10.5, 20.5,
        );
        let result = build_military_names::assemble(&[row1, row2]);
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("Duplicate OSM identity"));
    }

    #[test]
    fn assemble_invalid_record_id() {
        let row = json!({
            "sources": [{"dataset": "OpenStreetMap", "record_id": "x12345@67890", "version": "2026-09-23T00:00:00Z"}],
            "bbox": {"xmin": 10.0, "ymin": 20.0, "xmax": 10.5, "ymax": 20.5},
            "lon": 10.25, "lat": 20.25, "area": 100.0,
            "military": "airfield", "name": "Test",
        });
        let result = build_military_names::assemble(&[row]);
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("Invalid typed OSM identity"));
    }

    #[test]
    fn assemble_non_finite_geometry() {
        let row = json!({
            "sources": [{"dataset": "OpenStreetMap", "record_id": "w1@1", "version": "2026-09-23T00:00:00Z"}],
            "bbox": {"xmin": 10.0, "ymin": 20.0, "xmax": 10.5, "ymax": 20.5},
            "lon": null, "lat": 20.0, "area": 100.0,
            "military": "base", "name": "Test",
        });
        let result = build_military_names::assemble(&[row]);
        assert!(result.is_err());
    }

    #[test]
    fn assemble_label_outside_bbox() {
        let row = make_row(
            "w", 1, 1, "Test", "base", 100.0, 20.0, 100.0, 9.5, 19.5, 10.5, 20.5,
        );
        let result = build_military_names::assemble(&[row]);
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("Label outside source bounds"));
    }

    #[test]
    fn assemble_unknown_military_class_defaults_to_index_0() {
        let row = make_row(
            "w", 1, 1, "Test", "unknown_type", 10.0, 20.0, 100.0, 9.5, 19.5, 10.5, 20.5,
        );
        let result = build_military_names::assemble(&[row]).unwrap();
        let r = result.get("records").unwrap().as_array().unwrap()[0]
            .as_array()
            .unwrap();
        assert_eq!(r[8].as_u64().unwrap(), 0);
    }

    #[test]
    fn assemble_area_rounding() {
        let row = make_row(
            "w", 1, 1, "Test", "base", 10.0, 20.0, 0.3, 9.5, 19.5, 10.5, 20.5,
        );
        let result = build_military_names::assemble(&[row]).unwrap();
        let r = result.get("records").unwrap().as_array().unwrap()[0]
            .as_array()
            .unwrap();
        assert_eq!(r[9].as_i64().unwrap(), 1);
    }

    // ---- build_military_names --verify mode ----

    #[test]
    fn verify_mode_pass_and_mismatch() {
        let tmp = std::env::temp_dir().join("gev_test_verify_mode");
        let _ = std::fs::remove_dir_all(&tmp);
        let cache = tmp.join("cache");
        let pack = tmp.join("pack");
        std::fs::create_dir_all(&cache).unwrap();
        std::fs::create_dir_all(&pack).unwrap();

        let row = make_row(
            "n", 1, 1, "Base", "military_land", 10.0, 20.0, 100.0, 9.5, 19.5, 10.5, 20.5,
        );
        let rows = vec![row];
        let cached_json = serde_json::to_string(&rows).unwrap();
        let cache_file = cache.join(format!(
            "military-names-{}.json",
            build_military_names::RELEASE
        ));
        std::fs::write(&cache_file, &cached_json).unwrap();

        let result = build_military_names::assemble_pack(&rows).unwrap();
        let raw = serde_json::to_string(&result).unwrap();
        let digest = build_military_names::sha256_hex(raw.as_bytes());
        std::fs::write(pack.join("names.json"), raw.as_bytes()).unwrap();
        std::fs::write(
            pack.join("names.sha256"),
            format!("{}  names.json\n", digest),
        )
        .unwrap();

        let args = vec![
            "--cache".into(),
            cache.to_string_lossy().into_owned(),
            "--pack".into(),
            pack.to_string_lossy().into_owned(),
            "--verify".into(),
        ];
        assert!(build_military_names::run(&args).is_ok());

        std::fs::write(
            pack.join("names.sha256"),
            "0000000000000000000000000000000000000000000000000000000000000000  names.json\n",
        )
        .unwrap();
        let err = build_military_names::run(&args).unwrap_err();
        assert!(err.contains("SHA-256 mismatch"));

        let _ = std::fs::remove_dir_all(&tmp);
    }

    // ---- verify_cesium_assets ----

    #[test]
    fn verify_cesium_pass() {
        let tmp = std::env::temp_dir().join("gev_test_cesium_pass");
        let _ = std::fs::remove_dir_all(&tmp);
        let cesium = tmp.join("cesium");
        std::fs::create_dir_all(cesium.join("Workers")).unwrap();
        std::fs::create_dir_all(cesium.join("ThirdParty")).unwrap();
        std::fs::create_dir_all(cesium.join("Assets")).unwrap();
        std::fs::create_dir_all(cesium.join("Widgets")).unwrap();
        std::fs::write(cesium.join("Cesium.js"), "content").unwrap();
        std::fs::write(cesium.join("Widgets/widgets.css"), "body{}").unwrap();
        std::fs::write(cesium.join("Assets/dummy.txt"), "x").unwrap();

        let msg = verify_cesium_assets::verify(&tmp).unwrap();
        assert!(msg.contains("verified successfully"));

        let _ = std::fs::remove_dir_all(&tmp);
    }

    #[test]
    fn verify_cesium_missing_cesium_js() {
        let tmp = std::env::temp_dir().join("gev_test_cesium_missing_js");
        let _ = std::fs::remove_dir_all(&tmp);
        let cesium = tmp.join("cesium");
        std::fs::create_dir_all(&cesium).unwrap();

        let err = verify_cesium_assets::verify(&tmp).unwrap_err();
        assert!(err.contains("Cesium.js"));

        let _ = std::fs::remove_dir_all(&tmp);
    }

    #[test]
    fn verify_cesium_missing_workers_dir() {
        let tmp = std::env::temp_dir().join("gev_test_cesium_missing_workers");
        let _ = std::fs::remove_dir_all(&tmp);
        let cesium = tmp.join("cesium");
        std::fs::create_dir_all(cesium.join("Widgets")).unwrap();
        std::fs::write(cesium.join("Cesium.js"), "x").unwrap();
        std::fs::write(cesium.join("Widgets/widgets.css"), "x").unwrap();

        let err = verify_cesium_assets::verify(&tmp).unwrap_err();
        assert!(err.contains("Workers"));

        let _ = std::fs::remove_dir_all(&tmp);
    }

    #[test]
    fn verify_cesium_empty_assets() {
        let tmp = std::env::temp_dir().join("gev_test_cesium_empty_assets");
        let _ = std::fs::remove_dir_all(&tmp);
        let cesium = tmp.join("cesium");
        std::fs::create_dir_all(cesium.join("Workers")).unwrap();
        std::fs::create_dir_all(cesium.join("ThirdParty")).unwrap();
        std::fs::create_dir_all(cesium.join("Assets")).unwrap();
        std::fs::create_dir_all(cesium.join("Widgets")).unwrap();
        std::fs::write(cesium.join("Cesium.js"), "x").unwrap();
        std::fs::write(cesium.join("Widgets/widgets.css"), "x").unwrap();

        let err = verify_cesium_assets::verify(&tmp).unwrap_err();
        assert!(err.contains("Assets directory is empty"));

        let _ = std::fs::remove_dir_all(&tmp);
    }

    // ---- opensky_import_client ----

    #[test]
    fn parse_credentials_camel_case() {
        let json = r#"{"clientId": "myid", "clientSecret": "mysecret"}"#;
        let creds = opensky_import_client::parse_credentials(json).unwrap();
        assert_eq!(creds.client_id, "myid");
        assert_eq!(creds.client_secret, "mysecret");
    }

    #[test]
    fn parse_credentials_snake_case() {
        let json = r#"{"client_id": "myid", "client_secret": "mysecret"}"#;
        let creds = opensky_import_client::parse_credentials(json).unwrap();
        assert_eq!(creds.client_id, "myid");
        assert_eq!(creds.client_secret, "mysecret");
    }

    #[test]
    fn parse_credentials_trims_whitespace() {
        let json = r#"{"clientId": "  myid  ", "clientSecret": "  mysecret  "}"#;
        let creds = opensky_import_client::parse_credentials(json).unwrap();
        assert_eq!(creds.client_id, "myid");
        assert_eq!(creds.client_secret, "mysecret");
    }

    #[test]
    fn parse_credentials_missing_secret() {
        let json = r#"{"clientId": "myid"}"#;
        let result = opensky_import_client::parse_credentials(json);
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("missing client id or client secret"));
    }

    #[test]
    fn parse_credentials_empty_values() {
        let json = r#"{"clientId": "", "clientSecret": ""}"#;
        let result = opensky_import_client::parse_credentials(json);
        assert!(result.is_err());
    }

    #[test]
    fn parse_credentials_camel_takes_precedence() {
        let json =
            r#"{"clientId": "camel", "client_id": "snake", "clientSecret": "s1", "client_secret": "s2"}"#;
        let creds = opensky_import_client::parse_credentials(json).unwrap();
        assert_eq!(creds.client_id, "camel");
        assert_eq!(creds.client_secret, "s1");
    }

    // ---- dev_helpers: dotenv parsing ----

    #[test]
    fn dotenv_basic_parsing() {
        let content = "# comment\nGOOGLE_MAPS_API_KEY=test123\nOTHER=val\n";
        assert_eq!(
            dev_helpers::parse_dotenv_value(content, "GOOGLE_MAPS_API_KEY"),
            Some("test123".into())
        );
        assert_eq!(
            dev_helpers::parse_dotenv_value(content, "OTHER"),
            Some("val".into())
        );
        assert_eq!(dev_helpers::parse_dotenv_value(content, "MISSING"), None);
    }

    #[test]
    fn dotenv_quoted_values() {
        let content = "KEY1=\"quoted value\"\nKEY2='single quoted'\n";
        assert_eq!(
            dev_helpers::parse_dotenv_value(content, "KEY1"),
            Some("quoted value".into())
        );
        assert_eq!(
            dev_helpers::parse_dotenv_value(content, "KEY2"),
            Some("single quoted".into())
        );
    }

    #[test]
    fn dotenv_empty_value() {
        let content = "KEY=\n";
        assert_eq!(
            dev_helpers::parse_dotenv_value(content, "KEY"),
            Some(String::new())
        );
    }

    #[test]
    fn dotenv_skips_comments_and_blank() {
        let content = "\n# header\n\nKEY=val\n# footer\n";
        assert_eq!(
            dev_helpers::parse_dotenv_value(content, "KEY"),
            Some("val".into())
        );
    }

    // ---- dev_helpers: OpenSky auth modes ----

    #[test]
    fn opensky_auth_mode_parsing() {
        assert_eq!(
            dev_helpers::parse_opensky_auth_mode("basic"),
            dev_helpers::OpenSkyAuthMode::Basic
        );
        assert_eq!(
            dev_helpers::parse_opensky_auth_mode("oauth"),
            dev_helpers::OpenSkyAuthMode::OAuth
        );
        assert_eq!(
            dev_helpers::parse_opensky_auth_mode("auto"),
            dev_helpers::OpenSkyAuthMode::Auto
        );
        assert_eq!(
            dev_helpers::parse_opensky_auth_mode("anon"),
            dev_helpers::OpenSkyAuthMode::Anon
        );
    }

    #[test]
    fn opensky_auth_mode_case_insensitive() {
        assert_eq!(
            dev_helpers::parse_opensky_auth_mode("OAUTH"),
            dev_helpers::OpenSkyAuthMode::OAuth
        );
        assert_eq!(
            dev_helpers::parse_opensky_auth_mode("Basic"),
            dev_helpers::OpenSkyAuthMode::Basic
        );
    }

    #[test]
    fn opensky_auth_mode_invalid_defaults_to_oauth() {
        assert_eq!(
            dev_helpers::parse_opensky_auth_mode("invalid"),
            dev_helpers::OpenSkyAuthMode::OAuth
        );
    }

    // ---- dev_helpers: external key tracking ----

    #[test]
    fn external_key_tracking() {
        let env = |key: &str| -> Option<String> {
            match key {
                "GOOGLE_MAPS_API_KEY" => Some("abc".into()),
                "CESIUM_ION_TOKEN" => Some("xyz".into()),
                _ => None,
            }
        };
        let keys = dev_helpers::track_external_keys(&env);
        assert!(keys.contains(&"GOOGLE_MAPS_API_KEY".to_string()));
        assert!(keys.contains(&"CESIUM_ION_TOKEN".to_string()));
        assert!(!keys.contains(&"OPENAI_API_KEY".to_string()));
        assert_eq!(keys.len(), 2);
    }

    #[test]
    fn external_keys_csv_format() {
        let keys = vec!["A".to_string(), "B".to_string(), "C".to_string()];
        assert_eq!(dev_helpers::external_keys_csv(&keys), "A,B,C");
        assert_eq!(dev_helpers::external_keys_csv(&[]), "");
    }

    // ---- dev_helpers: preset configs ----

    #[test]
    fn cctv_preset_fresh_defaults() {
        let cfg = dev_helpers::default_cctv_config(dev_helpers::Preset::Fresh);
        assert_eq!(cfg.austin_max_sources, "250");
        assert_eq!(cfg.max_sources, "4000");
        assert_eq!(cfg.caltrans_districts, "4,7,11,3");
        assert_eq!(cfg.tfl_enabled, "1");
        assert!(cfg.sources_file.is_empty());
    }

    #[test]
    fn cctv_preset_cctv_lighter() {
        let cfg = dev_helpers::default_cctv_config(dev_helpers::Preset::Cctv);
        assert_eq!(cfg.austin_max_sources, "36");
        assert_eq!(cfg.max_sources, "48");
        assert_eq!(cfg.sources_file, "config/cctv_sources.austin.json");
        assert_eq!(cfg.prefer_austin, "1");
    }

    #[test]
    fn cctv_preset_secure_minimal() {
        let cfg = dev_helpers::default_cctv_config(dev_helpers::Preset::Secure);
        assert_eq!(cfg.austin_max_sources, "36");
        assert_eq!(cfg.max_sources, "48");
        assert!(cfg.sources_file.is_empty());
    }

    // ---- dev_helpers: catalog wiring check ----

    #[test]
    fn catalog_wiring_check_pass() {
        let result = dev_helpers::check_catalog_wiring(
            true,
            "function init() { return createApplicationCatalog(config) }",
            "  createApplicationCctv({ sources })\n  other()",
        );
        assert!(result.is_ok());
    }

    #[test]
    fn catalog_wiring_check_missing_cctv_js() {
        let result = dev_helpers::check_catalog_wiring(false, "anything", "anything");
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("cctv.js"));
    }

    #[test]
    fn catalog_wiring_check_missing_catalog_call() {
        let result = dev_helpers::check_catalog_wiring(
            true,
            "function init() { /* no catalog */ }",
            "  createApplicationCctv({ sources })",
        );
        assert!(result.is_err());
    }

    #[test]
    fn catalog_wiring_check_missing_cctv_wire() {
        let result = dev_helpers::check_catalog_wiring(
            true,
            "return createApplicationCatalog(config)",
            "// no cctv wire here",
        );
        assert!(result.is_err());
    }

    // ---- dev_helpers: Google Maps key resolution ----

    #[test]
    fn dev_secure_keychain_wins_over_env() {
        let keychain = |svc: &str, acct: &str| -> String {
            if svc == "google-maps-api" && acct == "api-key" {
                "keychain_value".into()
            } else {
                String::new()
            }
        };
        let (key, source) = dev_helpers::resolve_google_maps_key_secure("env_value", &keychain);
        assert_eq!(key, "keychain_value");
        assert_eq!(source, "keychain:api-key");
    }

    #[test]
    fn dev_secure_env_fallback_when_no_keychain() {
        let keychain = |_: &str, _: &str| -> String { String::new() };
        let (key, source) = dev_helpers::resolve_google_maps_key_secure("env_value", &keychain);
        assert_eq!(key, "env_value");
        assert_eq!(source, "env");
    }

    #[test]
    fn dev_secure_not_configured() {
        let keychain = |_: &str, _: &str| -> String { String::new() };
        let (key, source) = dev_helpers::resolve_google_maps_key_secure("", &keychain);
        assert!(key.is_empty());
        assert_eq!(source, "not configured");
    }

    #[test]
    fn dev_fresh_env_wins_over_keychain() {
        let keychain = |svc: &str, acct: &str| -> String {
            if svc == "google-maps-api" && acct == "api-key" {
                "keychain_value".into()
            } else {
                String::new()
            }
        };
        let (key, source) =
            dev_helpers::resolve_google_maps_key_fresh("env_value", "", &keychain);
        assert_eq!(key, "env_value");
        assert_eq!(source, "env");
    }

    #[test]
    fn dev_fresh_dotenv_then_keychain() {
        let keychain = |svc: &str, acct: &str| -> String {
            if svc == "google-maps-api" && acct == "default" {
                "kc".into()
            } else {
                String::new()
            }
        };
        let (key, source) =
            dev_helpers::resolve_google_maps_key_fresh("", "dotenv_val", &keychain);
        assert_eq!(key, "dotenv_val");
        assert_eq!(source, "dotenv");

        let (key2, source2) = dev_helpers::resolve_google_maps_key_fresh("", "", &keychain);
        assert_eq!(key2, "kc");
        assert_eq!(source2, "keychain:default");
    }

    // ---- dev_helpers: OpenSky credential resolution ----

    #[test]
    fn opensky_resolve_basic_mode_clears_oauth_fields() {
        let state = dev_helpers::resolve_opensky_credentials(
            "basic",
            &|_| String::new(),
            &|svc, acct| {
                if svc == "opensky-network" && acct == "username" {
                    "user1".into()
                } else if svc == "opensky-network" && acct == "password" {
                    "pass1".into()
                } else {
                    String::new()
                }
            },
            None,
            "",
            "",
            "",
            "",
        );
        assert_eq!(state.auth_mode, dev_helpers::OpenSkyAuthMode::Basic);
        assert_eq!(state.username, "user1");
        assert_eq!(state.password, "pass1");
        assert!(state.client_id.is_empty());
        assert!(state.client_secret.is_empty());
    }

    #[test]
    fn opensky_resolve_oauth_mode_clears_basic_fields() {
        let state = dev_helpers::resolve_opensky_credentials(
            "oauth",
            &|_| String::new(),
            &|svc, acct| {
                if svc == "opensky-network" && acct == "client_id" {
                    "cid".into()
                } else if svc == "opensky-network" && acct == "client_secret" {
                    "csecret".into()
                } else {
                    String::new()
                }
            },
            None,
            "",
            "",
            "",
            "",
        );
        assert_eq!(state.auth_mode, dev_helpers::OpenSkyAuthMode::OAuth);
        assert_eq!(state.client_id, "cid");
        assert_eq!(state.client_secret, "csecret");
        assert!(state.username.is_empty());
        assert!(state.password.is_empty());
    }

    #[test]
    fn opensky_resolve_anon_clears_all() {
        let state = dev_helpers::resolve_opensky_credentials(
            "anon",
            &|_| String::new(),
            &|_, _| "should_be_cleared".into(),
            None,
            "cid",
            "csecret",
            "user",
            "pass",
        );
        assert_eq!(state.auth_mode, dev_helpers::OpenSkyAuthMode::Anon);
        assert!(state.client_id.is_empty());
        assert!(state.client_secret.is_empty());
        assert!(state.username.is_empty());
        assert!(state.password.is_empty());
    }

    #[test]
    fn opensky_resolve_auto_keeps_both() {
        let state = dev_helpers::resolve_opensky_credentials(
            "auto",
            &|_| String::new(),
            &|svc, acct| {
                if svc == "opensky-network" && acct == "username" {
                    "user1".into()
                } else if svc == "opensky-network" && acct == "password" {
                    "pass1".into()
                } else if svc == "opensky-network" && acct == "client_id" {
                    "cid".into()
                } else if svc == "opensky-network" && acct == "client_secret" {
                    "csecret".into()
                } else {
                    String::new()
                }
            },
            None,
            "",
            "",
            "",
            "",
        );
        assert_eq!(state.auth_mode, dev_helpers::OpenSkyAuthMode::Auto);
        assert_eq!(state.username, "user1");
        assert_eq!(state.password, "pass1");
        assert_eq!(state.client_id, "cid");
        assert_eq!(state.client_secret, "csecret");
    }

    #[test]
    fn opensky_resolve_oauth_from_credentials_file() {
        let cred_json = r#"{"clientId": "file_cid", "clientSecret": "file_cs"}"#;
        let state = dev_helpers::resolve_opensky_credentials(
            "oauth",
            &|_| String::new(),
            &|_, _| String::new(),
            Some(cred_json),
            "",
            "",
            "",
            "",
        );
        assert_eq!(state.client_id, "file_cid");
        assert_eq!(state.client_secret, "file_cs");
    }

    #[test]
    fn opensky_resolve_env_wins_over_credentials_file() {
        let cred_json = r#"{"clientId": "file_cid", "clientSecret": "file_cs"}"#;
        let state = dev_helpers::resolve_opensky_credentials(
            "oauth",
            &|_| String::new(),
            &|_, _| String::new(),
            Some(cred_json),
            "env_cid",
            "env_cs",
            "",
            "",
        );
        assert_eq!(state.client_id, "env_cid");
        assert_eq!(state.client_secret, "env_cs");
    }

    // ---- dev_helpers: LAN warning ----

    #[test]
    fn lan_warning_localhost_returns_none() {
        assert!(dev_helpers::lan_warning_message("localhost", "4173", None).is_none());
        assert!(dev_helpers::lan_warning_message("127.0.0.1", "4173", None).is_none());
        assert!(dev_helpers::lan_warning_message("::1", "4173", None).is_none());
    }

    #[test]
    fn lan_warning_exposed_returns_message() {
        let msg = dev_helpers::lan_warning_message("0.0.0.0", "4173", Some("192.168.1.10"));
        assert!(msg.is_some());
        let text = msg.unwrap();
        assert!(text.contains("WARNING"));
        assert!(text.contains("192.168.1.10"));
    }

    // ---- parse_osm_record_id ----

    #[test]
    fn osm_record_id_valid() {
        assert_eq!(
            build_military_names::parse_osm_record_id("n12345@67890"),
            Some(('n', "12345"))
        );
        assert_eq!(
            build_military_names::parse_osm_record_id("w1@1"),
            Some(('w', "1"))
        );
        assert_eq!(
            build_military_names::parse_osm_record_id("r999@0"),
            Some(('r', "999"))
        );
    }

    #[test]
    fn osm_record_id_invalid() {
        assert!(build_military_names::parse_osm_record_id("x1@1").is_none());
        assert!(build_military_names::parse_osm_record_id("n@1").is_none());
        assert!(build_military_names::parse_osm_record_id("n1@").is_none());
        assert!(build_military_names::parse_osm_record_id("n1").is_none());
        assert!(build_military_names::parse_osm_record_id("").is_none());
        assert!(build_military_names::parse_osm_record_id("n1@1extra").is_none());
    }
}
