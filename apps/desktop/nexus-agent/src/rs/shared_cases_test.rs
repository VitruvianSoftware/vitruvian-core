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

//! Native Rust port of `apps/desktop/nexus-agent/src/shared-cases.test.js`.
//! Reads every shared cross-platform fixture in `apps/desktop/nexus-agent/testdata/*.json`
//! and verifies the Rust bridge, dotenv parser, and flag builder against them.

use nexus_agent_src_lib::agy::{approval_args, build_agy_args, AgyBridge};
use nexus_agent_src_lib::annotations::annotation_is_archived;
use nexus_agent_src_lib::{dotenv_encode_value, dotenv_parse, JsonValue};
use std::collections::BTreeMap;
use std::env;
use std::fs;
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

fn make_scratch_dir(prefix: &str) -> PathBuf {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let dir = env::temp_dir().join(format!("{}-{}-{}", prefix, std::process::id(), nanos));
    fs::create_dir_all(&dir).unwrap();
    dir
}

fn load_cases(file: &str) -> Vec<JsonValue> {
    let relative = format!("apps/desktop/nexus-agent/testdata/{}", file);
    let mut candidates = Vec::new();
    if let Ok(srcdir) = env::var("TEST_SRCDIR") {
        if let Ok(ws) = env::var("TEST_WORKSPACE") {
            candidates.push(PathBuf::from(&srcdir).join(&ws).join(&relative));
        }
        candidates.push(PathBuf::from(&srcdir).join("_main").join(&relative));
    }
    candidates.push(PathBuf::from(&relative));
    candidates.push(PathBuf::from("../testdata").join(file));

    let path = candidates.iter().find(|p| p.is_file()).unwrap_or_else(|| {
        panic!(
            "shared cases file {} is missing; looked in {:?}",
            file, candidates
        )
    });
    let raw = fs::read_to_string(path)
        .unwrap_or_else(|e| panic!("shared cases file {:?} cannot be read: {}", path, e));
    let parsed = JsonValue::parse(&raw)
        .unwrap_or_else(|e| panic!("shared cases file {:?} invalid JSON: {}", path, e));
    let cases = parsed
        .get("cases")
        .and_then(|v| v.as_array())
        .unwrap_or_else(|| panic!("shared cases file {:?} has no cases array", path))
        .to_vec();
    assert!(
        !cases.is_empty(),
        "shared cases file {:?} has no cases",
        path
    );
    cases
}

fn json_string_list(val: &JsonValue, name: &str) -> Vec<String> {
    let arr = val
        .as_array()
        .unwrap_or_else(|| panic!("{}: expected list", name));
    arr.iter()
        .map(|v| {
            v.as_str()
                .unwrap_or_else(|| panic!("{}: expected string in list", name))
                .to_string()
        })
        .collect()
}

#[test]
fn archive_annotations_the_bot_reads_every_shared_example_as_written() {
    let cases = load_cases("archive-annotations.json");
    let mut checked = 0;
    for item in &cases {
        let name = item
            .get("name")
            .and_then(|v| v.as_str())
            .unwrap_or("(unnamed)");
        let text = item
            .get("text")
            .and_then(|v| v.as_str())
            .unwrap_or_else(|| panic!("{}: text is a string", name));
        let archived = item
            .get("archived")
            .and_then(|v| v.as_bool())
            .unwrap_or_else(|| panic!("{}: archived is a boolean", name));
        assert_eq!(annotation_is_archived(text), archived, "{}", name);
        checked += 1;
    }
    assert_eq!(checked, cases.len());
}

#[test]
fn approval_modes_the_bot_passes_agy_the_flags_every_shared_example_says() {
    let scratch = make_scratch_dir("nexus-shared-approval");
    let bridge = AgyBridge::from_dotenv_and_env("", &BTreeMap::new(), &scratch.to_string_lossy());
    let when_absent = bridge.get_chat_settings(0).approval_mode;

    let cases = load_cases("approval-modes.json");
    let mut checked = 0;
    for item in &cases {
        let name = item
            .get("name")
            .and_then(|v| v.as_str())
            .unwrap_or("(unnamed)");
        let args = json_string_list(
            item.get("args")
                .unwrap_or_else(|| panic!("{}: missing args", name)),
            name,
        );
        let val_node = item
            .get("value")
            .unwrap_or_else(|| panic!("{}: missing value", name));
        let mode = if val_node.is_null() {
            when_absent.as_str()
        } else {
            val_node
                .as_str()
                .unwrap_or_else(|| panic!("{}: value must be string or null", name))
        };
        assert_eq!(approval_args(mode), args, "{}", name);
        checked += 1;
    }
    assert_eq!(checked, cases.len());
    let _ = fs::remove_dir_all(&scratch);
}

#[test]
fn approval_modes_an_empty_agy_approval_mode_in_environment_gives_flags_of_empty_example() {
    let scratch = make_scratch_dir("nexus-shared-empty-mode");
    let cases = load_cases("approval-modes.json");
    let empty: Vec<&JsonValue> = cases
        .iter()
        .filter(|item| item.get("value").and_then(|v| v.as_str()) == Some(""))
        .collect();
    assert_eq!(
        empty.len(),
        1,
        "the shared examples have one case for an empty value"
    );
    let expected_args = json_string_list(empty[0].get("args").unwrap(), "empty case");

    let mut env_map = BTreeMap::new();
    env_map.insert("HOME".to_string(), scratch.to_string_lossy().to_string());
    env_map.insert(
        "AGY_WORKING_DIR".to_string(),
        scratch.to_string_lossy().to_string(),
    );
    env_map.insert("AGY_APPROVAL_MODE".to_string(), String::new());

    let bridge = AgyBridge::from_dotenv_and_env("", &env_map, &scratch.to_string_lossy());
    let mode = bridge.get_chat_settings(0).approval_mode;
    assert_eq!(mode, "", "the bot kept the empty mode, not its default");
    assert_eq!(approval_args(&mode), expected_args);
    let _ = fs::remove_dir_all(&scratch);
}

#[test]
fn env_files_dotenv_reads_every_shared_file_as_written() {
    let cases = load_cases("env-files.json");
    let mut checked = 0;
    for item in &cases {
        let name = item
            .get("name")
            .and_then(|v| v.as_str())
            .unwrap_or("(unnamed)");
        let content = item
            .get("content")
            .and_then(|v| v.as_str())
            .unwrap_or_else(|| panic!("{}: content is a string", name));
        let values_entries = item
            .get("values")
            .and_then(|v| v.as_object())
            .unwrap_or_else(|| panic!("{}: values is an object", name));
        let mut expected = BTreeMap::new();
        for (k, v) in values_entries {
            expected.insert(
                k.clone(),
                v.as_str()
                    .unwrap_or_else(|| panic!("{}: value for {} must be string", name, k))
                    .to_string(),
            );
        }
        assert_eq!(dotenv_parse(content), expected, "{}", name);
        checked += 1;
    }
    assert_eq!(checked, cases.len());
}

#[test]
fn env_lines_dotenv_reads_every_shared_example_as_written() {
    let cases = load_cases("env-lines.json");
    let mut checked = 0;
    for item in &cases {
        let name = item
            .get("name")
            .and_then(|v| v.as_str())
            .unwrap_or("(unnamed)");
        let line = item
            .get("line")
            .and_then(|v| v.as_str())
            .unwrap_or_else(|| panic!("{}: line is a string", name));
        let key_node = item
            .get("key")
            .unwrap_or_else(|| panic!("{}: missing key", name));
        let val_node = item
            .get("value")
            .unwrap_or_else(|| panic!("{}: missing value", name));
        let mut expected = BTreeMap::new();
        if key_node.is_null() && val_node.is_null() {
            // expects empty map
        } else {
            let k = key_node
                .as_str()
                .unwrap_or_else(|| panic!("{}: key must be string", name));
            let v = val_node
                .as_str()
                .unwrap_or_else(|| panic!("{}: value must be string", name));
            expected.insert(k.to_string(), v.to_string());
        }
        assert_eq!(dotenv_parse(line), expected, "{}", name);
        checked += 1;
    }
    assert_eq!(checked, cases.len());
}

#[test]
fn env_values_what_the_apps_write_dotenv_reads_back_as_same_value() {
    let cases = load_cases("env-written-values.json");
    let mut checked = 0;
    for item in &cases {
        let name = item
            .get("name")
            .and_then(|v| v.as_str())
            .unwrap_or("(unnamed)");
        let value = item
            .get("value")
            .and_then(|v| v.as_str())
            .unwrap_or_else(|| panic!("{}: value is a string", name));
        let line = item
            .get("line")
            .and_then(|v| v.as_str())
            .unwrap_or_else(|| panic!("{}: line is a string", name));
        assert_eq!(dotenv_encode_value(value), line, "{}: encoded line", name);
        let parsed = dotenv_parse(&format!("K={}", line));
        let read = parsed.get("K").map(|s| s.as_str()).unwrap_or("");
        if let Some(lossy_node) = item.get("lossy") {
            assert_eq!(
                lossy_node.as_bool(),
                Some(true),
                "{}: lossy is true or left out",
                name
            );
            assert_ne!(read, value, "{}: marked lossy, but it reads back", name);
        } else {
            assert_eq!(read, value, "{}", name);
        }
        checked += 1;
    }
    assert_eq!(checked, cases.len());
}

fn start_bot_flags(
    scratch: &PathBuf,
    env_text: &str,
    environment: &BTreeMap<String, String>,
) -> (Vec<String>, Vec<String>) {
    let mut proc_env = BTreeMap::new();
    proc_env.insert("HOME".to_string(), scratch.to_string_lossy().to_string());
    proc_env.insert("AGY_BIN".to_string(), "/usr/bin/false".to_string());
    for (k, v) in environment {
        proc_env.insert(k.clone(), v.clone());
    }
    let bridge = AgyBridge::from_dotenv_and_env(env_text, &proc_env, &scratch.to_string_lossy());
    let settings = bridge.get_chat_settings(0);
    let args = build_agy_args("hi", &settings, "stream-json", None, None);
    let head = args.iter().take(4).cloned().collect();
    let flags = args.into_iter().skip(4).collect();
    (head, flags)
}

#[test]
fn agy_flags_the_bot_started_over_each_shared_env_passes_agy_the_flags_the_example_says() {
    let scratch = make_scratch_dir("nexus-shared-flags-file");
    let cases: Vec<JsonValue> = load_cases("agy-flags.json")
        .into_iter()
        .filter(|item| item.get("environment").is_none() && item.get("custom").is_none())
        .collect();
    assert!(!cases.is_empty(), "there are examples with a file alone");
    let mut checked = 0;
    for item in &cases {
        let name = item
            .get("name")
            .and_then(|v| v.as_str())
            .unwrap_or("(unnamed)");
        let env_str = item
            .get("env")
            .and_then(|v| v.as_str())
            .unwrap_or_else(|| panic!("{}: env is a string", name));
        let expected_args = json_string_list(
            item.get("args")
                .unwrap_or_else(|| panic!("{}: missing args", name)),
            name,
        );
        assert!(
            item.get("apps").is_none(),
            "{}: with a file alone there is no apps list",
            name
        );
        let (head, flags) = start_bot_flags(&scratch, env_str, &BTreeMap::new());
        assert_eq!(
            head,
            vec!["-p", "hi", "--output-format", "stream-json"],
            "{}: the flags follow the prompt and the format",
            name
        );
        assert_eq!(flags, expected_args, "{}", name);
        checked += 1;
    }
    assert_eq!(checked, cases.len());
    let _ = fs::remove_dir_all(&scratch);
}

#[test]
fn agy_flags_variable_already_set_in_process_wins_over_same_line_of_env() {
    let scratch = make_scratch_dir("nexus-shared-flags-env");
    let cases: Vec<JsonValue> = load_cases("agy-flags.json")
        .into_iter()
        .filter(|item| item.get("environment").is_some())
        .collect();
    assert!(
        !cases.is_empty(),
        "there are examples with a process environment"
    );
    let mut checked = 0;
    for item in &cases {
        let name = item
            .get("name")
            .and_then(|v| v.as_str())
            .unwrap_or("(unnamed)");
        let env_str = item
            .get("env")
            .and_then(|v| v.as_str())
            .unwrap_or_else(|| panic!("{}: env is a string", name));
        let expected_args = json_string_list(
            item.get("args")
                .unwrap_or_else(|| panic!("{}: missing args", name)),
            name,
        );
        assert!(
            item.get("apps").and_then(|v| v.as_array()).is_some(),
            "{}: apps is a list",
            name
        );
        let env_entries = item
            .get("environment")
            .and_then(|v| v.as_object())
            .unwrap_or_else(|| panic!("{}: environment is an object", name));
        let mut proc_env = BTreeMap::new();
        for (k, v) in env_entries {
            proc_env.insert(
                k.clone(),
                v.as_str()
                    .unwrap_or_else(|| panic!("{}: env value must be string", name))
                    .to_string(),
            );
        }
        let (_head, flags) = start_bot_flags(&scratch, env_str, &proc_env);
        assert_eq!(flags, expected_args, "{}", name);
        checked += 1;
    }
    assert_eq!(checked, cases.len());
    let _ = fs::remove_dir_all(&scratch);
}

#[test]
fn agy_flags_command_of_users_own_is_run_as_written_with_no_effort_flag_added() {
    let scratch = make_scratch_dir("nexus-shared-flags-custom");
    let cases: Vec<JsonValue> = load_cases("agy-flags.json")
        .into_iter()
        .filter(|item| item.get("custom").is_some())
        .collect();
    assert!(
        !cases.is_empty(),
        "there is an example with a command of the user's own"
    );

    // Create a portable helper script that prints its arguments as a JSON array
    let helper = scratch.join("print-args.sh");
    fs::write(
        &helper,
        "#!/bin/sh\nprintf '['\nsep=''\nfor a in \"$@\"; do\n  printf '%s\"%s\"' \"$sep\" \"$a\"\n  sep=','\ndone\nprintf ']\\n'\n",
    )
    .unwrap();
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mut perms = fs::metadata(&helper).unwrap().permissions();
        perms.set_mode(0o755);
        fs::set_permissions(&helper, perms).unwrap();
    }

    let provider = format!(
        "CLI_PROVIDER=custom\nCLI_COMMAND_TEMPLATE='\"{}\" {{prompt}}'\n",
        helper.to_string_lossy()
    );
    let mut checked = 0;
    for item in &cases {
        let name = item
            .get("name")
            .and_then(|v| v.as_str())
            .unwrap_or("(unnamed)");
        assert_eq!(
            item.get("custom").and_then(|v| v.as_bool()),
            Some(true),
            "{}: custom is true or left out",
            name
        );
        let env_str = item
            .get("env")
            .and_then(|v| v.as_str())
            .unwrap_or_else(|| panic!("{}: env is a string", name));
        let expected_extra = json_string_list(item.get("args").unwrap(), name);

        let mut proc_env = BTreeMap::new();
        proc_env.insert("HOME".to_string(), scratch.to_string_lossy().to_string());
        let bridge = AgyBridge::from_dotenv_and_env(
            &format!("{}{}", env_str, provider),
            &proc_env,
            &scratch.to_string_lossy(),
        );
        let res = bridge.execute_prompt("hi", None).unwrap();
        let parsed = JsonValue::parse(&res.text).unwrap();
        let actual_argv = json_string_list(&parsed, name);
        let mut expected_argv = vec!["hi".to_string()];
        expected_argv.extend(expected_extra);
        assert_eq!(actual_argv, expected_argv, "{}", name);
        checked += 1;
    }
    assert_eq!(checked, cases.len());
    let _ = fs::remove_dir_all(&scratch);
}
