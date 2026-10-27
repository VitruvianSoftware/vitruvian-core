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

//! Native Rust port of `apps/desktop/nexus-agent/src/sessions.js`.
//! Manages persistent `.bot-sessions.json` state for Telegram chat sessions,
//! session labels, and workspace shortcuts.

use crate::JsonValue;
use std::collections::BTreeMap;
use std::env;
use std::fmt::Display;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::{Mutex, OnceLock};

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct SessionStore {
    pub sessions: BTreeMap<String, String>,
    pub session_names: BTreeMap<String, String>,
    pub workspaces: BTreeMap<String, String>,
}

impl SessionStore {
    pub fn from_json_str(content: &str) -> Result<Self, String> {
        let parsed = JsonValue::parse(content)?;
        let Some(entries) = parsed.as_object() else {
            return Err("Expected JSON object in .bot-sessions.json".to_string());
        };
        if let Some(sessions_val) = parsed.get("sessions") {
            Ok(SessionStore {
                sessions: extract_string_map(sessions_val),
                session_names: parsed
                    .get("sessionNames")
                    .map(extract_string_map)
                    .unwrap_or_default(),
                workspaces: parsed
                    .get("workspaces")
                    .map(extract_string_map)
                    .unwrap_or_default(),
            })
        } else {
            // Legacy flat format (chatId -> sessionId)
            let mut sessions = BTreeMap::new();
            for (k, v) in entries {
                if let Some(s) = v.as_str() {
                    sessions.insert(k.clone(), s.to_string());
                }
            }
            Ok(SessionStore {
                sessions,
                session_names: BTreeMap::new(),
                workspaces: BTreeMap::new(),
            })
        }
    }

    pub fn to_json_pretty(&self) -> String {
        let to_obj = |map: &BTreeMap<String, String>| -> JsonValue {
            JsonValue::Object(
                map.iter()
                    .map(|(k, v)| (k.clone(), JsonValue::String(v.clone())))
                    .collect(),
            )
        };
        let root = JsonValue::Object(vec![
            ("sessions".to_string(), to_obj(&self.sessions)),
            ("sessionNames".to_string(), to_obj(&self.session_names)),
            ("workspaces".to_string(), to_obj(&self.workspaces)),
        ]);
        root.to_json_pretty(0)
    }
}

fn extract_string_map(val: &JsonValue) -> BTreeMap<String, String> {
    let mut map = BTreeMap::new();
    if let Some(entries) = val.as_object() {
        for (k, v) in entries {
            if let Some(s) = v.as_str() {
                map.insert(k.clone(), s.to_string());
            }
        }
    }
    map
}

pub fn resolve_sessions_file_path() -> PathBuf {
    let base = env::var("AGY_WORKING_DIR")
        .ok()
        .filter(|s| !s.is_empty())
        .or_else(|| {
            env::var("GEMINI_WORKING_DIR")
                .ok()
                .filter(|s| !s.is_empty())
        })
        .map(PathBuf::from)
        .unwrap_or_else(|| env::current_dir().unwrap_or_else(|_| PathBuf::from(".")));
    base.join(".bot-sessions.json")
}

#[derive(Debug, Clone)]
pub struct SessionManager {
    file_path: PathBuf,
    store: SessionStore,
}

impl SessionManager {
    pub fn new(file_path: PathBuf) -> Self {
        let mut mgr = SessionManager {
            file_path,
            store: SessionStore::default(),
        };
        mgr.load();
        mgr
    }

    pub fn load(&mut self) {
        if self.file_path.exists() {
            if let Ok(raw) = fs::read_to_string(&self.file_path) {
                if let Ok(loaded) = SessionStore::from_json_str(&raw) {
                    self.store = loaded;
                }
            }
        }
    }

    pub fn save(&self) {
        let _ = fs::write(&self.file_path, self.store.to_json_pretty());
    }

    pub fn file_path(&self) -> &Path {
        &self.file_path
    }

    pub fn get_persisted_session(&self, chat_id: &str) -> Option<String> {
        self.store.sessions.get(chat_id).cloned()
    }

    pub fn set_persisted_session(&mut self, chat_id: &str, session_id: &str) {
        self.store
            .sessions
            .insert(chat_id.to_string(), session_id.to_string());
        self.save();
    }

    pub fn delete_persisted_session(&mut self, chat_id: &str) {
        self.store.sessions.remove(chat_id);
        self.store.session_names.remove(chat_id);
        self.save();
    }

    pub fn has_persisted_session(&self, chat_id: &str) -> bool {
        self.store.sessions.contains_key(chat_id)
    }

    pub fn get_session_name(&self, chat_id: &str) -> Option<String> {
        self.store.session_names.get(chat_id).cloned()
    }

    pub fn set_session_name(&mut self, chat_id: &str, name: &str) {
        self.store
            .session_names
            .insert(chat_id.to_string(), name.to_string());
        self.save();
    }

    pub fn get_workspaces(&self) -> BTreeMap<String, String> {
        self.store.workspaces.clone()
    }

    pub fn set_workspace(&mut self, alias: &str, absolute_path: &str) {
        self.store
            .workspaces
            .insert(alias.to_string(), absolute_path.to_string());
        self.save();
    }

    pub fn delete_workspace(&mut self, alias: &str) {
        self.store.workspaces.remove(alias);
        self.save();
    }
}

static GLOBAL_SESSIONS: OnceLock<Mutex<SessionManager>> = OnceLock::new();

fn with_global_manager<F, R>(f: F) -> R
where
    F: FnOnce(&mut SessionManager) -> R,
{
    let mutex = GLOBAL_SESSIONS.get_or_init(|| {
        let path = resolve_sessions_file_path();
        Mutex::new(SessionManager::new(path))
    });
    let mut guard = mutex.lock().unwrap_or_else(|e| e.into_inner());
    let expected_path = resolve_sessions_file_path();
    if guard.file_path() != expected_path {
        *guard = SessionManager::new(expected_path);
    }
    f(&mut guard)
}

// ─── Module-Level Functions (matching sessions.js exports) ──────────────────

pub fn get_persisted_session<T: Display>(chat_id: T) -> Option<String> {
    let key = chat_id.to_string();
    with_global_manager(|m| m.get_persisted_session(&key))
}

pub fn set_persisted_session<T: Display>(chat_id: T, session_id: &str) {
    let key = chat_id.to_string();
    with_global_manager(|m| m.set_persisted_session(&key, session_id));
}

pub fn delete_persisted_session<T: Display>(chat_id: T) {
    let key = chat_id.to_string();
    with_global_manager(|m| m.delete_persisted_session(&key));
}

pub fn has_persisted_session<T: Display>(chat_id: T) -> bool {
    let key = chat_id.to_string();
    with_global_manager(|m| m.has_persisted_session(&key))
}

pub fn get_session_name<T: Display>(chat_id: T) -> Option<String> {
    let key = chat_id.to_string();
    with_global_manager(|m| m.get_session_name(&key))
}

pub fn set_session_name<T: Display>(chat_id: T, name: &str) {
    let key = chat_id.to_string();
    with_global_manager(|m| m.set_session_name(&key, name));
}

pub fn get_workspaces() -> BTreeMap<String, String> {
    with_global_manager(|m| m.get_workspaces())
}

pub fn set_workspace(alias: &str, absolute_path: &str) {
    with_global_manager(|m| m.set_workspace(alias, absolute_path));
}

pub fn delete_workspace(alias: &str) {
    with_global_manager(|m| m.delete_workspace(alias));
}
