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

//! Native Rust port of `apps/desktop/nexus-agent/src/sessions.test.js`.

use nexus_agent_src_lib::sessions::{
    delete_persisted_session, delete_workspace, get_persisted_session, get_session_name,
    get_workspaces, has_persisted_session, set_persisted_session, set_session_name, set_workspace,
    SessionStore,
};
use std::env;
use std::fs;
use std::path::PathBuf;
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};

static ENV_LOCK: Mutex<()> = Mutex::new(());

fn setup_temp_workdir() -> PathBuf {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let dir = env::temp_dir().join(format!("nexus-sessions-{}-{}", std::process::id(), nanos));
    fs::create_dir_all(&dir).unwrap();
    env::remove_var("AGY_WORKING_DIR");
    env::set_var("GEMINI_WORKING_DIR", &dir);
    dir
}

#[test]
fn session_ids_round_trip_and_chat_id_is_coerced_to_string() {
    let _guard = ENV_LOCK.lock().unwrap();
    let dir = setup_temp_workdir();

    set_persisted_session(123, "sess-abc");
    assert_eq!(get_persisted_session("123").as_deref(), Some("sess-abc"));
    assert!(has_persisted_session(123));

    let _ = fs::remove_dir_all(&dir);
}

#[test]
fn deleting_a_session_also_clears_its_name() {
    let _guard = ENV_LOCK.lock().unwrap();
    let dir = setup_temp_workdir();

    set_persisted_session(5, "s");
    set_session_name(5, "my session");
    delete_persisted_session(5);
    assert_eq!(get_persisted_session(5), None);
    assert_eq!(get_session_name(5), None);
    assert!(!has_persisted_session(5));

    let _ = fs::remove_dir_all(&dir);
}

#[test]
fn get_workspaces_returns_a_copy_mutating_it_does_not_affect_the_store() {
    let _guard = ENV_LOCK.lock().unwrap();
    let dir = setup_temp_workdir();

    set_workspace("proj", "/abs/proj");
    let mut ws = get_workspaces();
    ws.insert("proj".to_string(), "/tampered".to_string());
    ws.insert("injected".to_string(), "/evil".to_string());
    assert_eq!(
        get_workspaces().get("proj").map(|s| s.as_str()),
        Some("/abs/proj")
    );
    assert_eq!(get_workspaces().get("injected"), None);

    let _ = fs::remove_dir_all(&dir);
}

#[test]
fn delete_workspace_removes_only_the_named_alias() {
    let _guard = ENV_LOCK.lock().unwrap();
    let dir = setup_temp_workdir();

    set_workspace("a", "/a");
    set_workspace("b", "/b");
    delete_workspace("a");
    assert_eq!(get_workspaces().get("a"), None);
    assert_eq!(get_workspaces().get("b").map(|s| s.as_str()), Some("/b"));

    let _ = fs::remove_dir_all(&dir);
}

#[test]
fn changes_persist_to_disk_fresh_read_of_store_sees_them() {
    let _guard = ENV_LOCK.lock().unwrap();
    let dir = setup_temp_workdir();

    set_persisted_session(99, "persisted");
    let file = dir.join(".bot-sessions.json");
    let raw = fs::read_to_string(&file).unwrap();
    let on_disk = SessionStore::from_json_str(&raw).unwrap();
    assert_eq!(
        on_disk.sessions.get("99").map(|s| s.as_str()),
        Some("persisted")
    );

    let _ = fs::remove_dir_all(&dir);
}
