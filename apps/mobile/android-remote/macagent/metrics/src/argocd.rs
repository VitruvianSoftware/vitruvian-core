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

//! ArgoCD `Application` list parser (`kubectl get applications -A -o json`).

use crate::json::{JsonMap, JsonValue};
use crate::time_util::Timestamp;

/// One row of `GET /v1/argocd`.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct ArgoApp {
    pub name: String,
    pub namespace: String,
    pub project: String,
    pub sync: String,
    pub health: String,
    pub revision: String,
    pub last_synced: Timestamp,
    pub message: String,
}

impl ArgoApp {
    pub fn to_json(&self) -> JsonValue {
        self.to_json_value()
    }

    pub fn to_json_value(&self) -> JsonValue {
        let mut m = JsonMap::new();
        m.insert("name", JsonValue::from_str_val(&self.name));
        m.insert("namespace", JsonValue::from_str_val(&self.namespace));
        m.insert("project", JsonValue::from_str_val(&self.project));
        m.insert("sync", JsonValue::from_str_val(&self.sync));
        m.insert("health", JsonValue::from_str_val(&self.health));
        m.insert("revision", JsonValue::from_str_val(&self.revision));
        m.insert(
            "last_synced",
            JsonValue::from_str_val(self.last_synced.to_rfc3339()),
        );
        m.insert("message", JsonValue::from_str_val(&self.message));
        JsonValue::Object(m)
    }
}

/// Body of `GET /v1/argocd`.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct ArgoApps {
    pub available: bool,
    pub reason: String,
    pub apps: Vec<ArgoApp>,
}

impl ArgoApps {
    pub fn to_json(&self) -> JsonValue {
        self.to_json_value()
    }

    pub fn to_json_value(&self) -> JsonValue {
        let mut m = JsonMap::new();
        m.insert("available", JsonValue::from_bool(self.available));
        m.insert("reason", JsonValue::from_str_val(&self.reason));
        m.insert(
            "apps",
            JsonValue::Array(self.apps.iter().map(|a| a.to_json_value()).collect()),
        );
        JsonValue::Object(m)
    }

    pub fn to_json_string(&self) -> String {
        self.to_json_value().to_json_string()
    }
}

/// Reads the Application list from `kubectl get applications -A -o json`.
pub fn parse_argo_apps(out: &str) -> Result<Vec<ArgoApp>, String> {
    let root = JsonValue::parse(out).map_err(|e| format!("kubectl get applications: {}", e))?;
    let obj = root
        .as_object()
        .ok_or_else(|| "kubectl get applications: expected JSON object".to_string())?;
    let items = obj.get("items").and_then(|v| v.as_array()).unwrap_or(&[]);

    let mut apps = Vec::with_capacity(items.len());
    for it in items {
        let meta = it.get("metadata");
        let name = meta.map(|m| m.get_str("name")).unwrap_or("").to_string();
        let namespace = meta
            .map(|m| m.get_str("namespace"))
            .unwrap_or("")
            .to_string();
        let project = it
            .get("spec")
            .map(|s| s.get_str("project"))
            .unwrap_or("")
            .to_string();

        let status = it.get("status");
        let sync_obj = status.and_then(|s| s.get("sync"));
        let sync = sync_obj
            .map(|s| s.get_str("status"))
            .unwrap_or("")
            .to_string();
        let raw_rev = sync_obj.map(|s| s.get_str("revision")).unwrap_or("");
        let revision = short_revision(raw_rev);

        let health = status
            .and_then(|s| s.get("health"))
            .map(|h| h.get_str("status"))
            .unwrap_or("")
            .to_string();

        let op_state = status.and_then(|s| s.get("operationState"));
        let message = op_state
            .map(|o| o.get_str("message"))
            .unwrap_or("")
            .to_string();
        let mut ts = op_state.map(|o| o.get_str("finishedAt")).unwrap_or("");
        if ts.is_empty() {
            ts = status.map(|s| s.get_str("reconciledAt")).unwrap_or("");
        }
        let last_synced = Timestamp::parse_rfc3339(ts).unwrap_or(Timestamp::ZERO);

        apps.push(ArgoApp {
            name,
            namespace,
            project,
            sync,
            health,
            revision,
            last_synced,
            message,
        });
    }

    apps.sort_by(|a, b| a.name.cmp(&b.name));
    Ok(apps)
}

/// First 8 characters of a git SHA, or whole string if <= 8 chars.
pub fn short_revision(rev: &str) -> String {
    if rev.len() <= 8 {
        rev.to_string()
    } else {
        rev[..8].to_string()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn read_fixture(name: &str) -> String {
        for candidate in [
            format!("testdata/{}", name),
            format!(
                "apps/mobile/android-remote/macagent/metrics/testdata/{}",
                name
            ),
        ] {
            if let Ok(s) = std::fs::read_to_string(&candidate) {
                return s;
            }
        }
        if let Ok(srcdir) = std::env::var("TEST_SRCDIR") {
            let p = format!(
                "{}/_main/apps/mobile/android-remote/macagent/metrics/testdata/{}",
                srcdir, name
            );
            if let Ok(s) = std::fs::read_to_string(&p) {
                return s;
            }
        }
        panic!("fixture {} not found", name);
    }

    #[test]
    fn test_parse_argo_apps_on_real_applications() {
        let data = read_fixture("argocd-apps.json");
        let apps = parse_argo_apps(&data).expect("parse_argo_apps");
        assert_eq!(apps.len(), 2);
        let a = &apps[0];
        assert_eq!(a.name, "alertmanager-ntfy-bridge");
        assert_eq!(a.namespace, "argocd");
        assert_eq!(a.project, "platform-project");
        assert_eq!(a.sync, "Synced");
        assert_eq!(a.health, "Healthy");
        assert_eq!(a.revision, "8da57d77");
        assert_eq!(a.message, "successfully synced (all tasks run)");
        assert!(!a.last_synced.is_zero(), "last_synced did not parse");
        assert_eq!(apps[1].revision, "0.23.2");
    }

    #[test]
    fn test_parse_argo_apps_edges() {
        let apps =
            parse_argo_apps(r#"{"apiVersion":"v1","kind":"List","items":[]}"#).expect("empty list");
        assert_eq!(apps.len(), 0);

        let one = r#"{"items":[{"metadata":{"name":"adopted","namespace":"argocd"},"spec":{"project":"default"},
          "status":{"sync":{"status":"OutOfSync","revision":"abcdef1234567890"},"health":{"status":"Degraded"},
          "reconciledAt":"2026-09-07T20:10:11Z"}}]}"#;
        let apps = parse_argo_apps(one).expect("adopted app");
        assert_eq!(apps.len(), 1);
        assert!(
            !apps[0].last_synced.is_zero(),
            "with no finishedAt, last_synced must fall back to reconciledAt"
        );
        assert_eq!(apps[0].sync, "OutOfSync");
        assert_eq!(apps[0].health, "Degraded");

        assert!(
            parse_argo_apps(r#"error: the server doesn't have a resource type "applications""#)
                .is_err(),
            "a kubectl error must not parse as zero apps"
        );
    }

    #[test]
    fn test_parse_argo_apps_sorts_by_name() {
        let raw = r#"{"items":[
          {"metadata":{"name":"zebra","namespace":"argocd"},"spec":{},"status":{}},
          {"metadata":{"name":"alpha","namespace":"argocd"},"spec":{},"status":{}}]}"#;
        let apps = parse_argo_apps(raw).expect("sort");
        assert_eq!(apps[0].name, "alpha");
        assert_eq!(apps[1].name, "zebra");
    }
}
