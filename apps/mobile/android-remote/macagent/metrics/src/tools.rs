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

//! Developer tools, processes, VMs, containers, k8s nodes, audio, Ollama, and Antigravity parsers.

use std::collections::BTreeMap;

use crate::json::{JsonMap, JsonValue};
use crate::time_util::Timestamp;

/// One row of `GET /v1/processes`.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct Process {
    pub name: String,
    pub cpu_percent: f64,
    pub memory_bytes: u64,
}

impl Process {
    pub fn to_json(&self) -> JsonValue {
        self.to_json_value()
    }

    pub fn to_json_value(&self) -> JsonValue {
        let mut m = JsonMap::new();
        m.insert("name", JsonValue::from_str_val(&self.name));
        m.insert("cpu_percent", JsonValue::from_f64(self.cpu_percent));
        m.insert("memory_bytes", JsonValue::from_u64(self.memory_bytes));
        JsonValue::Object(m)
    }
}

/// Body of `GET /v1/processes`.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct Processes {
    pub sampled_at: Timestamp,
    pub processes: Vec<Process>,
}

impl Processes {
    pub fn to_json(&self) -> JsonValue {
        self.to_json_value()
    }

    pub fn to_json_value(&self) -> JsonValue {
        let mut m = JsonMap::new();
        m.insert(
            "sampled_at",
            JsonValue::from_str_val(self.sampled_at.to_rfc3339()),
        );
        m.insert(
            "processes",
            JsonValue::Array(self.processes.iter().map(|p| p.to_json_value()).collect()),
        );
        JsonValue::Object(m)
    }

    pub fn to_json_string(&self) -> String {
        self.to_json_value().to_json_string()
    }
}

/// One row of `GET /v1/vms`.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct VM {
    pub name: String,
    pub status: String,
    pub vm_type: String,
    pub cpus: i32,
    pub memory_bytes: u64,
    pub disk_bytes: u64,
    pub arch: String,
}

impl VM {
    pub fn to_json(&self) -> JsonValue {
        self.to_json_value()
    }

    pub fn to_json_value(&self) -> JsonValue {
        let mut m = JsonMap::new();
        m.insert("name", JsonValue::from_str_val(&self.name));
        m.insert("status", JsonValue::from_str_val(&self.status));
        m.insert("vm_type", JsonValue::from_str_val(&self.vm_type));
        m.insert("cpus", JsonValue::from_i32(self.cpus));
        m.insert("memory_bytes", JsonValue::from_u64(self.memory_bytes));
        m.insert("disk_bytes", JsonValue::from_u64(self.disk_bytes));
        m.insert("arch", JsonValue::from_str_val(&self.arch));
        JsonValue::Object(m)
    }
}

/// Body of `GET /v1/vms`.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct VMs {
    pub available: bool,
    pub reason: String,
    pub vms: Vec<VM>,
}

impl VMs {
    pub fn to_json(&self) -> JsonValue {
        self.to_json_value()
    }

    pub fn to_json_value(&self) -> JsonValue {
        let mut m = JsonMap::new();
        m.insert("available", JsonValue::from_bool(self.available));
        m.insert("reason", JsonValue::from_str_val(&self.reason));
        m.insert(
            "vms",
            JsonValue::Array(self.vms.iter().map(|v| v.to_json_value()).collect()),
        );
        JsonValue::Object(m)
    }

    pub fn to_json_string(&self) -> String {
        self.to_json_value().to_json_string()
    }
}

/// One row of `GET /v1/containers`.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct Container {
    pub name: String,
    pub image: String,
    pub status: String,
}

impl Container {
    pub fn to_json(&self) -> JsonValue {
        self.to_json_value()
    }

    pub fn to_json_value(&self) -> JsonValue {
        let mut m = JsonMap::new();
        m.insert("name", JsonValue::from_str_val(&self.name));
        m.insert("image", JsonValue::from_str_val(&self.image));
        m.insert("status", JsonValue::from_str_val(&self.status));
        JsonValue::Object(m)
    }
}

/// Body of `GET /v1/containers`.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct Containers {
    pub available: bool,
    pub reason: String,
    pub runtime: String,
    pub containers: Vec<Container>,
}

impl Containers {
    pub fn to_json(&self) -> JsonValue {
        self.to_json_value()
    }

    pub fn to_json_value(&self) -> JsonValue {
        let mut m = JsonMap::new();
        m.insert("available", JsonValue::from_bool(self.available));
        m.insert("reason", JsonValue::from_str_val(&self.reason));
        m.insert("runtime", JsonValue::from_str_val(&self.runtime));
        m.insert(
            "containers",
            JsonValue::Array(self.containers.iter().map(|c| c.to_json_value()).collect()),
        );
        JsonValue::Object(m)
    }

    pub fn to_json_string(&self) -> String {
        self.to_json_value().to_json_string()
    }
}

/// One row of `GET /v1/k8s`.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct Node {
    pub name: String,
    pub ready: bool,
    pub version: String,
    pub roles: Vec<String>,
}

impl Node {
    pub fn to_json(&self) -> JsonValue {
        self.to_json_value()
    }

    pub fn to_json_value(&self) -> JsonValue {
        let mut m = JsonMap::new();
        m.insert("name", JsonValue::from_str_val(&self.name));
        m.insert("ready", JsonValue::from_bool(self.ready));
        m.insert("version", JsonValue::from_str_val(&self.version));
        m.insert(
            "roles",
            JsonValue::Array(
                self.roles
                    .iter()
                    .map(|r| JsonValue::from_str_val(r))
                    .collect(),
            ),
        );
        JsonValue::Object(m)
    }
}

/// Body of `GET /v1/k8s`.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct K8s {
    pub available: bool,
    pub reason: String,
    pub context: String,
    pub nodes: Vec<Node>,
}

impl K8s {
    pub fn to_json(&self) -> JsonValue {
        self.to_json_value()
    }

    pub fn to_json_value(&self) -> JsonValue {
        let mut m = JsonMap::new();
        m.insert("available", JsonValue::from_bool(self.available));
        m.insert("reason", JsonValue::from_str_val(&self.reason));
        m.insert("context", JsonValue::from_str_val(&self.context));
        m.insert(
            "nodes",
            JsonValue::Array(self.nodes.iter().map(|n| n.to_json_value()).collect()),
        );
        JsonValue::Object(m)
    }

    pub fn to_json_string(&self) -> String {
        self.to_json_value().to_json_string()
    }
}

/// Body of `GET /v1/audio` and reply to `POST /v1/audio`.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct Audio {
    pub volume_percent: i32,
    pub muted: bool,
}

impl Audio {
    pub fn to_json(&self) -> JsonValue {
        self.to_json_value()
    }

    pub fn to_json_value(&self) -> JsonValue {
        let mut m = JsonMap::new();
        m.insert("volume_percent", JsonValue::from_i32(self.volume_percent));
        m.insert("muted", JsonValue::from_bool(self.muted));
        JsonValue::Object(m)
    }

    pub fn to_json_string(&self) -> String {
        self.to_json_value().to_json_string()
    }
}

/// One Claude Code project seen recently on this machine.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct Session {
    pub project: String,
    pub last_active: Timestamp,
    pub path: String,
}

impl Session {
    pub fn to_json(&self) -> JsonValue {
        self.to_json_value()
    }

    pub fn to_json_value(&self) -> JsonValue {
        let mut m = JsonMap::new();
        m.insert("project", JsonValue::from_str_val(&self.project));
        m.insert(
            "last_active",
            JsonValue::from_str_val(self.last_active.to_rfc3339()),
        );
        m.insert("path", JsonValue::from_str_val(&self.path));
        JsonValue::Object(m)
    }
}

/// Body of `GET /v1/sessions`.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct Sessions {
    pub sessions: Vec<Session>,
    pub running_processes: i32,
}

impl Sessions {
    pub fn to_json(&self) -> JsonValue {
        self.to_json_value()
    }

    pub fn to_json_value(&self) -> JsonValue {
        let mut m = JsonMap::new();
        m.insert(
            "sessions",
            JsonValue::Array(self.sessions.iter().map(|s| s.to_json_value()).collect()),
        );
        m.insert(
            "running_processes",
            JsonValue::from_i32(self.running_processes),
        );
        JsonValue::Object(m)
    }

    pub fn to_json_string(&self) -> String {
        self.to_json_value().to_json_string()
    }
}

/// Reads `ps -Aceo pcpu,rss,comm -r` and keeps the first `limit` rows (`limit == 0` keeps all).
pub fn parse_processes(out: &str, limit: usize) -> Result<Vec<Process>, String> {
    let mut got = Vec::new();
    for line in out.lines() {
        if line.contains("%CPU") {
            continue;
        }
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        // Parse first two whitespace-delimited fields: `<cpu> <rss> <rest of line>`
        let mut parts = trimmed.splitn(2, char::is_whitespace);
        let Some(cpu_str) = parts.next() else {
            continue;
        };
        let Some(rest1) = parts.next() else {
            continue;
        };
        let rest1 = rest1.trim_start();
        let mut parts2 = rest1.splitn(2, char::is_whitespace);
        let Some(rss_str) = parts2.next() else {
            continue;
        };
        let Some(name_str) = parts2.next() else {
            continue;
        };
        let name = name_str.trim();
        if name.is_empty() {
            continue;
        }
        let Ok(cpu) = cpu_str.parse::<f64>() else {
            continue;
        };
        let Ok(rss_kib) = rss_str.parse::<u64>() else {
            continue;
        };
        got.push(Process {
            name: name.to_string(),
            cpu_percent: cpu,
            memory_bytes: rss_kib * 1024,
        });
        if limit > 0 && got.len() == limit {
            break;
        }
    }
    if got.is_empty() {
        return Err("ps: no process rows".to_string());
    }
    Ok(got)
}

/// Reads `limactl list --json` (newline-delimited JSON objects).
pub fn parse_lima_list(out: &str) -> Result<Vec<VM>, String> {
    let mut vms = Vec::new();
    for line in out.lines() {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        let raw = JsonValue::parse(line).map_err(|e| format!("limactl: {}", e))?;
        let obj = raw
            .as_object()
            .ok_or_else(|| "limactl: expected JSON object".to_string())?;
        vms.push(VM {
            name: obj.get_str("name").to_string(),
            status: obj.get_str("status").to_string(),
            vm_type: obj.get_str("vmType").to_string(),
            cpus: obj.get_i32("cpus"),
            memory_bytes: obj.get("memory").and_then(|v| v.as_u64()).unwrap_or(0),
            disk_bytes: obj.get("disk").and_then(|v| v.as_u64()).unwrap_or(0),
            arch: obj.get_str("arch").to_string(),
        });
    }
    Ok(vms)
}

/// Reads `docker ps --format '{{json .}}'`: one object per line.
pub fn parse_docker_ps(out: &str) -> Result<Vec<Container>, String> {
    let mut cs = Vec::new();
    for line in out.lines() {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        let raw = JsonValue::parse(line).map_err(|e| format!("docker: {}", e))?;
        let obj = raw
            .as_object()
            .ok_or_else(|| "docker: expected JSON object".to_string())?;
        let names = obj.get_str("Names");
        let name = names.split(',').next().unwrap_or("").to_string();
        cs.push(Container {
            name,
            image: obj.get_str("Image").to_string(),
            status: obj.get_str("Status").to_string(),
        });
    }
    Ok(cs)
}

/// Reads `podman ps --format json`.
pub fn parse_podman_ps(out: &str) -> Result<Vec<Container>, String> {
    let out = out.trim();
    if out.is_empty() {
        return Ok(Vec::new());
    }
    let val = JsonValue::parse(out).map_err(|e| format!("podman: {}", e))?;
    let arr = val
        .as_array()
        .ok_or_else(|| "podman: expected JSON array".to_string())?;
    let mut cs = Vec::with_capacity(arr.len());
    for r in arr {
        let name = r
            .get("Names")
            .and_then(|v| v.as_array())
            .and_then(|a| a.first())
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string();
        cs.push(Container {
            name,
            image: r.get_str("Image").to_string(),
            status: r.get_str("Status").to_string(),
        });
    }
    Ok(cs)
}

const NODE_ROLE_PREFIX: &str = "node-role.kubernetes.io/";

/// Reads `kubectl get nodes -o json`.
pub fn parse_kubectl_nodes(out: &str) -> Result<Vec<Node>, String> {
    let root = JsonValue::parse(out).map_err(|e| format!("kubectl: {}", e))?;
    let obj = root
        .as_object()
        .ok_or_else(|| "kubectl: expected JSON object".to_string())?;
    let items = obj.get("items").and_then(|v| v.as_array()).unwrap_or(&[]);

    let mut nodes = Vec::with_capacity(items.len());
    for it in items {
        let meta = it.get("metadata");
        let name = meta.map(|m| m.get_str("name")).unwrap_or("").to_string();
        let status = it.get("status");
        let version = status
            .and_then(|s| s.get("nodeInfo"))
            .map(|ni| ni.get_str("kubeletVersion"))
            .unwrap_or("")
            .to_string();

        let mut ready = false;
        if let Some(conds) = status
            .and_then(|s| s.get("conditions"))
            .and_then(|c| c.as_array())
        {
            for c in conds {
                if c.get_str("type") == "Ready" {
                    ready = c.get_str("status") == "True";
                }
            }
        }

        let mut roles = Vec::new();
        if let Some(labels) = meta
            .and_then(|m| m.get("labels"))
            .and_then(|l| l.as_object())
        {
            for (k, _) in labels.iter() {
                if let Some(r) = k.strip_prefix(NODE_ROLE_PREFIX) {
                    if !r.is_empty() {
                        roles.push(r.to_string());
                    }
                }
            }
        }
        roles.sort();

        nodes.push(Node {
            name,
            ready,
            version,
            roles,
        });
    }
    Ok(nodes)
}

/// Reads `osascript -e 'get volume settings'`.
pub fn parse_volume_settings(out: &str) -> Result<Audio, String> {
    let Some(vol_idx) = out.find("output volume:") else {
        return Err(format!("volume: unreadable settings {:?}", out.trim()));
    };
    let after_vol = &out[vol_idx + "output volume:".len()..];
    let digits_len = after_vol.bytes().take_while(|b| b.is_ascii_digit()).count();
    if digits_len == 0 {
        return Err(format!("volume: unreadable settings {:?}", out.trim()));
    }
    let vol: i32 = after_vol[..digits_len]
        .parse()
        .map_err(|_| format!("volume: unreadable settings {:?}", out.trim()))?;

    let Some(mute_idx) = after_vol.find("output muted:") else {
        return Err(format!("volume: unreadable settings {:?}", out.trim()));
    };
    let after_mute = &after_vol[mute_idx + "output muted:".len()..];
    let muted = if after_mute.starts_with("true") {
        true
    } else if after_mute.starts_with("false") {
        false
    } else {
        return Err(format!("volume: unreadable settings {:?}", out.trim()));
    };

    Ok(Audio {
        volume_percent: vol,
        muted,
    })
}

/// Pulls the hardware MAC address out of `ifconfig en0`.
pub fn parse_ether(out: &str) -> Result<String, String> {
    for line in out.lines() {
        let trimmed = line.trim();
        if let Some(rest) = trimmed.strip_prefix("ether") {
            let candidate = rest.trim();
            if is_mac_addr(candidate) {
                return Ok(candidate.to_ascii_lowercase());
            }
        }
    }
    Err("ifconfig: no ether line".to_string())
}

fn is_mac_addr(s: &str) -> bool {
    if s.len() != 17 {
        return false;
    }
    let parts: Vec<&str> = s.split(':').collect();
    if parts.len() != 6 {
        return false;
    }
    parts
        .iter()
        .all(|p| p.len() == 2 && p.bytes().all(|b| b.is_ascii_hexdigit()))
}

/// Reads the `womp` setting out of `pmset -g`.
pub fn parse_womp(out: &str) -> bool {
    for line in out.lines() {
        let fields: Vec<&str> = line.split_whitespace().collect();
        if fields.len() == 2 && fields[0] == "womp" && fields[1].bytes().all(|b| b.is_ascii_digit())
        {
            return fields[1] != "0";
        }
    }
    false
}

/// Counts lines of `ps -Axo comm=` whose basename is `name`.
pub fn count_processes_named(out: &str, name: &str) -> i32 {
    let mut n = 0;
    for line in out.lines() {
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        let base = line.rsplit('/').next().unwrap_or(line);
        if base == name {
            n += 1;
        }
    }
    n
}

/// Turns a Claude Code project directory name back into the display path it encodes.
pub fn project_from_dir_name(dir: &str) -> String {
    dir.strip_prefix('-').unwrap_or(dir).replace('-', "/")
}

/// Pulls the working directory out of the head of a Claude Code transcript.
pub fn cwd_from_transcript(head: &str) -> String {
    const KEY: &str = "\"cwd\":\"";
    let Some(i) = head.find(KEY) else {
        return String::new();
    };
    let rest = &head[i + KEY.len()..];
    let Some(j) = rest.find('"') else {
        return String::new();
    };
    rest[..j].to_string()
}

/// Body of `GET /v1/ollama`.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct Ollama {
    pub available: bool,
    pub reason: String,
    pub models: Vec<OllamaModel>,
    pub running: Vec<OllamaLoaded>,
}

impl Ollama {
    pub fn to_json(&self) -> JsonValue {
        self.to_json_value()
    }

    pub fn to_json_value(&self) -> JsonValue {
        let mut m = JsonMap::new();
        m.insert("available", JsonValue::from_bool(self.available));
        m.insert("reason", JsonValue::from_str_val(&self.reason));
        m.insert(
            "models",
            JsonValue::Array(self.models.iter().map(|x| x.to_json_value()).collect()),
        );
        m.insert(
            "running",
            JsonValue::Array(self.running.iter().map(|x| x.to_json_value()).collect()),
        );
        JsonValue::Object(m)
    }

    pub fn to_json_string(&self) -> String {
        self.to_json_value().to_json_string()
    }
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct OllamaModel {
    pub name: String,
    pub id: String,
    pub size_bytes: i64,
    pub modified: String,
}

impl OllamaModel {
    pub fn to_json(&self) -> JsonValue {
        self.to_json_value()
    }

    pub fn to_json_value(&self) -> JsonValue {
        let mut m = JsonMap::new();
        m.insert("name", JsonValue::from_str_val(&self.name));
        m.insert("id", JsonValue::from_str_val(&self.id));
        m.insert("size_bytes", JsonValue::from_i64(self.size_bytes));
        m.insert("modified", JsonValue::from_str_val(&self.modified));
        JsonValue::Object(m)
    }
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct OllamaLoaded {
    pub name: String,
    pub id: String,
    pub size_bytes: i64,
    pub processor: String,
    pub context: i32,
    pub until: String,
}

impl OllamaLoaded {
    pub fn to_json(&self) -> JsonValue {
        self.to_json_value()
    }

    pub fn to_json_value(&self) -> JsonValue {
        let mut m = JsonMap::new();
        m.insert("name", JsonValue::from_str_val(&self.name));
        m.insert("id", JsonValue::from_str_val(&self.id));
        m.insert("size_bytes", JsonValue::from_i64(self.size_bytes));
        m.insert("processor", JsonValue::from_str_val(&self.processor));
        m.insert("context", JsonValue::from_i32(self.context));
        m.insert("until", JsonValue::from_str_val(&self.until));
        JsonValue::Object(m)
    }
}

/// Turns `"23 GB"` / `"9.6 GB"` / `"512 MB"` into decimal bytes (`GB == 1e9`).
pub fn parse_ollama_size(s: &str) -> i64 {
    let f: Vec<&str> = s.split_whitespace().collect();
    if f.len() != 2 {
        return 0;
    }
    let Ok(n) = f[0].parse::<f64>() else {
        return 0;
    };
    let mult: f64 = match f[1].to_ascii_uppercase().as_str() {
        "B" => 1.0,
        "KB" => 1e3,
        "MB" => 1e6,
        "GB" => 1e9,
        "TB" => 1e12,
        _ => 0.0,
    };
    (n * mult) as i64
}

fn split_ollama_columns(line: &str) -> Vec<&str> {
    let mut cols = Vec::new();
    let bytes = line.as_bytes();
    let mut start = 0;
    let mut i = 0;
    while i < bytes.len() {
        if i + 1 < bytes.len() && bytes[i] == b' ' && bytes[i + 1] == b' ' {
            cols.push(&line[start..i]);
            while i < bytes.len() && bytes[i] == b' ' {
                i += 1;
            }
            start = i;
        } else {
            i += 1;
        }
    }
    if start < bytes.len() {
        cols.push(&line[start..]);
    }
    cols
}

/// Reads `ollama list`: `NAME ID SIZE MODIFIED`.
pub fn parse_ollama_list(out: &str) -> Result<Vec<OllamaModel>, String> {
    let mut models = Vec::new();
    let mut first = true;
    for raw_line in out.lines() {
        let line = raw_line.trim_end_matches(' ');
        if first {
            first = false;
            if !line.starts_with("NAME") {
                return Err(format!("ollama list: unexpected header {:?}", line));
            }
            continue;
        }
        if line.trim().is_empty() {
            continue;
        }
        let c = split_ollama_columns(line);
        if c.len() < 4 {
            continue;
        }
        models.push(OllamaModel {
            name: c[0].to_string(),
            id: c[1].to_string(),
            size_bytes: parse_ollama_size(c[2]),
            modified: c[3].to_string(),
        });
    }
    Ok(models)
}

/// Reads `ollama ps`: `NAME ID SIZE PROCESSOR CONTEXT UNTIL`.
pub fn parse_ollama_ps(out: &str) -> Result<Vec<OllamaLoaded>, String> {
    let mut loaded = Vec::new();
    let mut first = true;
    for raw_line in out.lines() {
        let line = raw_line.trim_end_matches(' ');
        if first {
            first = false;
            if !line.starts_with("NAME") {
                return Err(format!("ollama ps: unexpected header {:?}", line));
            }
            continue;
        }
        if line.trim().is_empty() {
            continue;
        }
        let c = split_ollama_columns(line);
        if c.len() < 6 {
            continue;
        }
        let ctx_n = c[4].parse::<i32>().unwrap_or(0);
        loaded.push(OllamaLoaded {
            name: c[0].to_string(),
            id: c[1].to_string(),
            size_bytes: parse_ollama_size(c[2]),
            processor: c[3].to_string(),
            context: ctx_n,
            until: c[5].to_string(),
        });
    }
    Ok(loaded)
}

/// Body of `GET /v1/tools`.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct Tools {
    pub tools: BTreeMap<String, Tool>,
}

impl Tools {
    pub fn to_json(&self) -> JsonValue {
        self.to_json_value()
    }

    pub fn to_json_value(&self) -> JsonValue {
        let mut tools_map = JsonMap::new();
        for (k, v) in &self.tools {
            tools_map.insert(k.clone(), v.to_json_value());
        }
        let mut m = JsonMap::new();
        m.insert("tools", JsonValue::Object(tools_map));
        JsonValue::Object(m)
    }

    pub fn to_json_string(&self) -> String {
        self.to_json_value().to_json_string()
    }
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct Tool {
    pub available: bool,
    pub path: String,
}

impl Tool {
    pub fn to_json(&self) -> JsonValue {
        self.to_json_value()
    }

    pub fn to_json_value(&self) -> JsonValue {
        let mut m = JsonMap::new();
        m.insert("available", JsonValue::from_bool(self.available));
        m.insert("path", JsonValue::from_str_val(&self.path));
        JsonValue::Object(m)
    }
}

/// Body of `GET /v1/antigravity`.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct Antigravity {
    pub available: bool,
    pub reason: String,
    pub version: String,
    pub models: Vec<AgyModel>,
    pub agents: Vec<String>,
}

impl Antigravity {
    pub fn to_json(&self) -> JsonValue {
        self.to_json_value()
    }

    pub fn to_json_value(&self) -> JsonValue {
        let mut m = JsonMap::new();
        m.insert("available", JsonValue::from_bool(self.available));
        m.insert("reason", JsonValue::from_str_val(&self.reason));
        m.insert("version", JsonValue::from_str_val(&self.version));
        m.insert(
            "models",
            JsonValue::Array(self.models.iter().map(|x| x.to_json_value()).collect()),
        );
        m.insert(
            "agents",
            JsonValue::Array(
                self.agents
                    .iter()
                    .map(|a| JsonValue::from_str_val(a))
                    .collect(),
            ),
        );
        JsonValue::Object(m)
    }

    pub fn to_json_string(&self) -> String {
        self.to_json_value().to_json_string()
    }
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct AgyModel {
    pub id: String,
    pub label: String,
}

impl AgyModel {
    pub fn to_json(&self) -> JsonValue {
        self.to_json_value()
    }

    pub fn to_json_value(&self) -> JsonValue {
        let mut m = JsonMap::new();
        m.insert("id", JsonValue::from_str_val(&self.id));
        m.insert("label", JsonValue::from_str_val(&self.label));
        JsonValue::Object(m)
    }
}

/// Reads `agy models`: a `"Fetching available models..."` preamble, then `<id><TAB><label>`.
pub fn parse_agy_models(out: &str) -> Vec<AgyModel> {
    let mut models = Vec::new();
    for line in out.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with("Fetching") {
            continue;
        }
        let Some((id, label)) = line.split_once('\t') else {
            continue;
        };
        models.push(AgyModel {
            id: id.trim().to_string(),
            label: label.trim().to_string(),
        });
    }
    models
}

/// Reads `agy agents`: one agent name per non-empty line.
pub fn parse_agy_agents(out: &str) -> Vec<String> {
    let mut agents = Vec::new();
    for line in out.lines() {
        let line = line.trim();
        if let Some(first) = line.split_whitespace().next() {
            agents.push(first.to_string());
        }
    }
    agents
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

    const FIXTURE_PS: &str = " %CPU    RSS COMM\n\
 96.7  46992 fseventsd\n\
 94.3   7120 top\n\
 14.1 589136 Google Chrome Helper (Renderer)\n\
 12.9 5638688 com.apple.Virtualization.VirtualMachine\n\
  8.5 520512 loginwindow\n\
  6.6 296496 Gemini\n\
  6.0 3744352 Google Chrome\n\
  4.3 445536 WindowServer\n";

    #[test]
    fn test_parse_processes_keeps_names_with_spaces() {
        let got = parse_processes(FIXTURE_PS, 8).expect("parse_processes");
        assert_eq!(got.len(), 8);
        assert_eq!(got[0].name, "fseventsd");
        assert_eq!(got[0].cpu_percent, 96.7);
        assert_eq!(got[2].name, "Google Chrome Helper (Renderer)");
        assert_eq!(got[3].memory_bytes, 5638688 * 1024);
        for p in &got {
            assert_ne!(p.name, "COMM");
        }
        assert_eq!(parse_processes(FIXTURE_PS, 3).unwrap().len(), 3);
        assert!(parse_processes(" %CPU    RSS COMM\n", 8).is_err());
    }

    #[test]
    fn test_parse_lima_list_ignores_the_config_blob() {
        let out = read_fixture("limactl-list.jsonl");
        let vms = parse_lima_list(&out).expect("parse_lima_list");
        assert_eq!(vms.len(), 2);
        let (stopped, running) = (&vms[0], &vms[1]);
        assert_eq!(stopped.name, "alice-dev-machine");
        assert_eq!(stopped.status, "Stopped");
        assert_eq!(running.name, "k8s-node");
        assert_eq!(running.status, "Running");
        assert_eq!(running.vm_type, "vz");
        assert_eq!(running.arch, "aarch64");
        assert_eq!(running.cpus, 2);
        assert_eq!(running.memory_bytes, 4294967296);
        assert_eq!(running.disk_bytes, 107374182400);
        assert!(parse_lima_list("{not json}\n").is_err());
    }

    #[test]
    fn test_parse_docker_ps() {
        let out = concat!(
            r#"{"Command":"\"/docker-entrypoint.…\"","CreatedAt":"2026-09-06 10:02:11 -0700 PDT","ID":"9f2c1a0b7d31","Image":"nginx:1.27","Names":"proxy,web","Ports":"0.0.0.0:8080->80/tcp","Status":"Up 3 hours"}"#,
            "\n",
            r#"{"Command":"\"redis-server\"","CreatedAt":"2026-09-05 22:41:03 -0700 PDT","ID":"2b7e5c9a44de","Image":"redis:7","Names":"cache","Ports":"6379/tcp","Status":"Up 12 hours (healthy)"}"#,
            "\n"
        );
        let cs = parse_docker_ps(out).expect("parse_docker_ps");
        assert_eq!(cs.len(), 2);
        assert_eq!(cs[0].name, "proxy");
        assert_eq!(cs[0].image, "nginx:1.27");
        assert_eq!(cs[0].status, "Up 3 hours");
        assert_eq!(cs[1].name, "cache");
        assert_eq!(parse_docker_ps("").unwrap().len(), 0);
    }

    #[test]
    fn test_parse_podman_ps() {
        let out = r#"[{"Id":"5f0d","Image":"docker.io/library/alpine:3.20","Names":["tidy_hopper"],"Status":"Up 2 minutes"}]"#;
        let cs = parse_podman_ps(out).expect("parse_podman_ps");
        assert_eq!(cs.len(), 1);
        assert_eq!(cs[0].name, "tidy_hopper");
        assert_eq!(cs[0].image, "docker.io/library/alpine:3.20");
        assert_eq!(parse_podman_ps("[]").unwrap().len(), 0);
    }

    const FIXTURE_NODES: &str = r#"{
  "apiVersion": "v1",
  "kind": "List",
  "items": [
    {
      "apiVersion": "v1",
      "kind": "Node",
      "metadata": {
        "name": "fedora",
        "labels": {
          "kubernetes.io/arch": "amd64",
          "kubernetes.io/hostname": "fedora",
          "node-role.kubernetes.io/etcd": "true",
          "node-role.kubernetes.io/control-plane": "true"
        }
      },
      "status": {
        "conditions": [
          {"type": "MemoryPressure", "status": "False"},
          {"type": "Ready", "status": "True"}
        ],
        "nodeInfo": {"kubeletVersion": "v1.35.3+k3s1", "osImage": "Fedora Linux 42"}
      }
    },
    {
      "apiVersion": "v1",
      "kind": "Node",
      "metadata": {
        "name": "james-mbp16",
        "labels": {"kubernetes.io/arch": "arm64"}
      },
      "status": {
        "conditions": [{"type": "Ready", "status": "True"}],
        "nodeInfo": {"kubeletVersion": "v1.35.3+k3s1"}
      }
    },
    {
      "apiVersion": "v1",
      "kind": "Node",
      "metadata": {
        "name": "nuc9i9",
        "labels": {"node-role.kubernetes.io/worker": "true"}
      },
      "status": {
        "conditions": [{"type": "Ready", "status": "Unknown"}],
        "nodeInfo": {"kubeletVersion": "v1.35.3+k3s1"}
      }
    }
  ]
}"#;

    #[test]
    fn test_parse_kubectl_nodes() {
        let nodes = parse_kubectl_nodes(FIXTURE_NODES).expect("parse_kubectl_nodes");
        assert_eq!(nodes.len(), 3);
        assert_eq!(nodes[0].name, "fedora");
        assert!(nodes[0].ready);
        assert_eq!(nodes[0].version, "v1.35.3+k3s1");
        assert_eq!(nodes[0].roles, vec!["control-plane", "etcd"]);
        assert!(nodes[1].roles.is_empty());
        assert!(
            !nodes[2].ready,
            "a node with Ready=\"Unknown\" must not be ready"
        );
        assert!(parse_kubectl_nodes("Unable to connect to the server").is_err());
    }

    #[test]
    fn test_parse_volume_settings() {
        let a = parse_volume_settings(
            "output volume:31, input volume:86, alert volume:50, output muted:false\n",
        )
        .expect("volume");
        assert_eq!(a.volume_percent, 31);
        assert!(!a.muted);

        let a = parse_volume_settings(
            "output volume:31, input volume:86, alert volume:50, output muted:true\n",
        )
        .expect("muted volume");
        assert!(a.muted);
        assert_eq!(a.volume_percent, 31);

        assert!(
            parse_volume_settings("output volume:missing value, output muted:missing value\n")
                .is_err()
        );
    }

    #[test]
    fn test_parse_ether() {
        let out = "en0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500\n\
\toptions=6460<TSO4,TSO6,CHANNEL_IO,PARTIAL_CSUM,ZEROINVERT_CSUM>\n\
\tether a2:26:7e:45:c1:2d\n\
\tinet6 fe80::c4b:7b0f:5d3c:1a2b%en0 prefixlen 64 secured scopeid 0xe\n\
\tinet 192.168.1.44 netmask 0xffffff00 broadcast 192.168.1.255\n\
\tmedia: autoselect\n\
\tstatus: active\n";
        assert_eq!(parse_ether(out).unwrap(), "a2:26:7e:45:c1:2d");
        assert!(parse_ether("lo0: flags=8049<UP,LOOPBACK,RUNNING,MULTICAST> mtu 16384\n").is_err());
    }

    #[test]
    fn test_parse_womp() {
        let on = "System-wide power settings:\n\
Currently in use:\n\
 standby              1\n\
 womp                 1\n\
 halfdim              1\n";
        assert!(parse_womp(on));
        assert!(!parse_womp("Currently in use:\n womp                 0\n"));
        assert!(!parse_womp("Currently in use:\n standby              1\n"));
    }

    #[test]
    fn test_count_processes_named_matches_the_basename_only() {
        let out = "/Applications/Claude.app/Contents/Helpers/chrome-native-host\n\
/Users/alice/.vscode-insiders/extensions/anthropic.claude-code-2.1.263-darwin-arm64/resources/native-binary/claude\n\
/Users/alice/Library/Application Support/Claude/Claude Extensions/ant.dir.gh.grafana.grafana-mcp/server/darwin-arm64/mcp-grafana\n\
/Users/alice/.vscode-insiders/extensions/anthropic.claude-code-2.1.263-darwin-arm64/resources/native-binary/claude\n\
/Users/alice/.claude/telegram-bot/.venv/bin/python\n\
/Users/alice/Library/Application Support/Claude/Claude Extensions/ant.dir.gh.grafana.grafana-mcp/server/darwin-arm64/mcp-grafana\n";
        assert_eq!(count_processes_named(out, "claude"), 2);
        assert_eq!(count_processes_named("", "claude"), 0);
    }

    #[test]
    fn test_project_from_dir_name() {
        assert_eq!(
            project_from_dir_name("-Users-james-Workspace-vitruvian"),
            "Users/james/Workspace/vitruvian"
        );
        assert_eq!(
            project_from_dir_name("-Users-james-Workspace-vitruvian-vitruvian-core"),
            "Users/james/Workspace/vitruvian/vitruvian/core"
        );
        assert_eq!(project_from_dir_name("-private-tmp"), "private/tmp");
    }

    #[test]
    fn test_cwd_from_transcript_beats_the_lossy_dir_name() {
        let head = concat!(
            r#"{"type":"user","cwd":"/Users/alice/src/acme/.claude/worktrees/new-android-app-setup-355ad3","sessionId":"b4d0"}"#,
            "\n",
            r#"{"type":"assistant","cwd":"/somewhere/else"}"#
        );
        assert_eq!(
            cwd_from_transcript(head),
            "/Users/alice/src/acme/.claude/worktrees/new-android-app-setup-355ad3"
        );
        assert_eq!(cwd_from_transcript(r#"{"type":"user"}"#), "");
    }

    #[test]
    fn test_parse_ollama_list_and_ps() {
        let list = concat!(
            "NAME                        ID              SIZE      MODIFIED     \n",
            "qwen3.6:35b-a3b-q4_K_M      07d35212591f    23 GB     4 months ago    \n",
            "gemma4:e4b-it-q4_K_M        c6eb396dbd59    9.6 GB    5 months ago    \n",
            "gemma4:26b-a4b-it-q4_K_M    5571076f3d70    17 GB     5 months ago    \n"
        );
        let m = parse_ollama_list(list).expect("parse_ollama_list");
        assert_eq!(m.len(), 3);
        assert_eq!(m[1].name, "gemma4:e4b-it-q4_K_M");
        assert_eq!(m[1].size_bytes, 9_600_000_000);
        assert_eq!(m[1].modified, "5 months ago");

        let ps = parse_ollama_ps("NAME    ID    SIZE    PROCESSOR    CONTEXT    UNTIL \n")
            .expect("idle ps");
        assert_eq!(ps.len(), 0);

        let loaded = concat!(
            "NAME                    ID              SIZE     PROCESSOR    CONTEXT    UNTIL              \n",
            "gemma4:e4b-it-q4_K_M    c6eb396dbd59    11 GB    100% GPU     4096       4 minutes from now    \n"
        );
        let ps = parse_ollama_ps(loaded).expect("loaded ps");
        assert_eq!(ps.len(), 1);
        assert_eq!(ps[0].processor, "100% GPU");
        assert_eq!(ps[0].context, 4096);
        assert_eq!(ps[0].until, "4 minutes from now");

        assert_eq!(parse_ollama_size("512 MB"), 512_000_000);
        assert_eq!(parse_ollama_size("garbage"), 0);
        assert!(parse_ollama_list("Error: could not connect to ollama app").is_err());
    }

    #[test]
    fn test_parse_agy_models_and_agents() {
        let out = concat!(
            "Fetching available models...\n",
            "gemini-3.8-flash-high\tGemini 3.8 Flash (High)\n",
            "gemini-3.1-pro-low\tGemini 3.1 Pro (Low)\n"
        );
        let m = parse_agy_models(out);
        assert_eq!(m.len(), 2);
        assert_eq!(m[0].id, "gemini-3.8-flash-high");
        assert_eq!(m[1].label, "Gemini 3.1 Pro (Low)");
        assert_eq!(parse_agy_models("Fetching available models...\n").len(), 0);
        assert_eq!(parse_agy_agents("").len(), 0);
        let a = parse_agy_agents("reviewer  some description\nshipper\n");
        assert_eq!(a.len(), 2);
        assert_eq!(a[0], "reviewer");
    }
}
