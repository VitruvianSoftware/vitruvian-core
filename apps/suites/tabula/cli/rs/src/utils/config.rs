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

use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};

pub const VALID_CONFIG_KEYS: &[&str] = &["projectId", "environment", "region", "databaseUrl"];

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct EnvironmentConfig {
    pub project_id: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Config {
    pub version: Option<String>,
    pub project_id: String,
    pub environment: Option<String>,
    pub region: String,
    pub database_url: Option<String>,
    pub neon_org_id: Option<String>,
    pub neon_api_key: Option<String>,
    pub created_at: Option<String>,
    pub environments: BTreeMap<String, EnvironmentConfig>,
    pub extra: BTreeMap<String, String>,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            version: Some("0.1.0".to_string()),
            project_id: String::new(),
            environment: None,
            region: String::new(),
            database_url: None,
            neon_org_id: None,
            neon_api_key: None,
            created_at: None,
            environments: BTreeMap::new(),
            extra: BTreeMap::new(),
        }
    }
}

impl Config {
    pub fn get_value(&self, key: &str) -> Option<&str> {
        match key {
            "version" => self.version.as_deref(),
            "projectId" => Some(self.project_id.as_str()),
            "environment" => self.environment.as_deref(),
            "region" => Some(self.region.as_str()),
            "databaseUrl" => self.database_url.as_deref(),
            "neonOrgId" => self.neon_org_id.as_deref(),
            "neonApiKey" => self.neon_api_key.as_deref(),
            "createdAt" => self.created_at.as_deref(),
            other => self.extra.get(other).map(String::as_str),
        }
    }

    pub fn has_key(&self, key: &str) -> bool {
        match key {
            "projectId" => !self.project_id.is_empty(),
            "region" => !self.region.is_empty(),
            "version" => self.version.is_some(),
            "environment" => self.environment.is_some(),
            "databaseUrl" => self.database_url.is_some(),
            "neonOrgId" => self.neon_org_id.is_some(),
            "neonApiKey" => self.neon_api_key.is_some(),
            "createdAt" => self.created_at.is_some(),
            other => self.extra.contains_key(other),
        }
    }

    pub fn set_value(&mut self, key: &str, value: String) -> Result<(), String> {
        if !VALID_CONFIG_KEYS.contains(&key) {
            return Err(format!(
                "Invalid key. Valid keys: {}",
                VALID_CONFIG_KEYS.join(", ")
            ));
        }
        match key {
            "projectId" => self.project_id = value,
            "environment" => self.environment = Some(value),
            "region" => self.region = value,
            "databaseUrl" => self.database_url = Some(value),
            _ => {
                self.extra.insert(key.to_string(), value);
            }
        }
        Ok(())
    }

    pub fn unset_value(&mut self, key: &str) -> Result<(), String> {
        if !self.has_key(key) {
            return Err(format!("Key not found: {key}"));
        }
        match key {
            "projectId" => self.project_id.clear(),
            "region" => self.region.clear(),
            "version" => self.version = None,
            "environment" => self.environment = None,
            "databaseUrl" => self.database_url = None,
            "neonOrgId" => self.neon_org_id = None,
            "neonApiKey" => self.neon_api_key = None,
            "createdAt" => self.created_at = None,
            other => {
                self.extra.remove(other);
            }
        }
        Ok(())
    }

    pub fn to_json_pretty(&self) -> String {
        let mut fields: Vec<(String, String)> = Vec::new();
        if let Some(ref v) = self.version {
            fields.push(("version".to_string(), json_quote(v)));
        }
        if !self.project_id.is_empty() {
            fields.push(("projectId".to_string(), json_quote(&self.project_id)));
        }
        if let Some(ref v) = self.environment {
            fields.push(("environment".to_string(), json_quote(v)));
        }
        if !self.region.is_empty() {
            fields.push(("region".to_string(), json_quote(&self.region)));
        }
        if let Some(ref v) = self.database_url {
            fields.push(("databaseUrl".to_string(), json_quote(v)));
        }
        if let Some(ref v) = self.neon_org_id {
            fields.push(("neonOrgId".to_string(), json_quote(v)));
        }
        if let Some(ref v) = self.neon_api_key {
            fields.push(("neonApiKey".to_string(), json_quote(v)));
        }
        if let Some(ref v) = self.created_at {
            fields.push(("createdAt".to_string(), json_quote(v)));
        }
        if !self.environments.is_empty() {
            let mut env_entries = Vec::new();
            for (env_name, env_cfg) in &self.environments {
                env_entries.push(format!(
                    "    {}: {{\n      \"projectId\": {}\n    }}",
                    json_quote(env_name),
                    json_quote(&env_cfg.project_id)
                ));
            }
            fields.push((
                "environments".to_string(),
                format!("{{\n{}\n  }}", env_entries.join(",\n")),
            ));
        }
        for (k, v) in &self.extra {
            fields.push((k.clone(), json_quote(v)));
        }

        let mut out = String::from("{\n");
        for (idx, (k, v)) in fields.iter().enumerate() {
            let comma = if idx + 1 < fields.len() { "," } else { "" };
            out.push_str(&format!("  {}: {}{}\n", json_quote(k), v, comma));
        }
        out.push('}');
        out
    }

    pub fn from_json_str(content: &str) -> Result<Self, String> {
        let trimmed = content.trim();
        if !trimmed.starts_with('{') || !trimmed.ends_with('}') {
            return Err("Expected JSON object".to_string());
        }
        let pairs = parse_top_level_json_object(trimmed)?;
        let mut cfg = Config {
            version: None,
            ..Config::default()
        };

        for (k, raw_val) in pairs {
            let v_trim = raw_val.trim();
            if v_trim == "null" {
                continue;
            }
            if k == "environments" {
                if v_trim.starts_with('{') && v_trim.ends_with('}') {
                    let env_pairs = parse_top_level_json_object(v_trim)?;
                    for (env_name, env_obj) in env_pairs {
                        let env_obj_trim = env_obj.trim();
                        if env_obj_trim.starts_with('{') && env_obj_trim.ends_with('}') {
                            let inner = parse_top_level_json_object(env_obj_trim)?;
                            for (ik, iv) in inner {
                                if ik == "projectId" {
                                    if let Some(s) = unquote_json_string(&iv) {
                                        cfg.environments.insert(
                                            env_name.clone(),
                                            EnvironmentConfig { project_id: s },
                                        );
                                    }
                                }
                            }
                        }
                    }
                }
                continue;
            }

            let val_str = unquote_json_string(v_trim)
                .ok_or_else(|| format!("Invalid string value for key '{k}'"))?;
            match k.as_str() {
                "version" => cfg.version = Some(val_str),
                "projectId" => cfg.project_id = val_str,
                "environment" => cfg.environment = Some(val_str),
                "region" => cfg.region = val_str,
                "databaseUrl" => cfg.database_url = Some(val_str),
                "neonOrgId" => cfg.neon_org_id = Some(val_str),
                "neonApiKey" => cfg.neon_api_key = Some(val_str),
                "createdAt" => cfg.created_at = Some(val_str),
                _ => {
                    cfg.extra.insert(k, val_str);
                }
            }
        }
        Ok(cfg)
    }
}

pub fn config_file_path(base_dir: &Path) -> PathBuf {
    base_dir.join(".tabula").join("config.json")
}

pub fn get_config() -> Result<Config, String> {
    let cwd = std::env::current_dir().map_err(|e| e.to_string())?;
    get_config_from(&cwd)
}

pub fn get_config_from(base_dir: &Path) -> Result<Config, String> {
    let config_file = config_file_path(base_dir);
    if !config_file.exists() {
        return Err("Configuration not found. Run: tabcli init".to_string());
    }
    let content = fs::read_to_string(&config_file)
        .map_err(|e| format!("Failed to parse configuration file: {e}"))?;
    Config::from_json_str(&content).map_err(|e| format!("Failed to parse configuration file: {e}"))
}

pub fn save_config(config: &Config) -> Result<(), String> {
    let cwd = std::env::current_dir().map_err(|e| e.to_string())?;
    save_config_to(&cwd, config)
}

pub fn save_config_to(base_dir: &Path, config: &Config) -> Result<(), String> {
    let config_file = config_file_path(base_dir);
    fs::write(&config_file, config.to_json_pretty())
        .map_err(|e| format!("Failed to save configuration: {e}"))
}

/// Escape shell argument to prevent command injection.
pub fn escape_shell_arg(arg: &str) -> String {
    format!("'{}'", arg.replace('\'', "'\\''"))
}

pub fn json_quote(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    out.push('"');
    for ch in s.chars() {
        match ch {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

pub fn unquote_json_string(raw: &str) -> Option<String> {
    let s = raw.trim();
    if s.len() < 2 || !s.starts_with('"') || !s.ends_with('"') {
        return None;
    }
    let inner = &s[1..s.len() - 1];
    let mut out = String::with_capacity(inner.len());
    let mut chars = inner.chars();
    while let Some(c) = chars.next() {
        if c == '\\' {
            match chars.next()? {
                '"' => out.push('"'),
                '\\' => out.push('\\'),
                '/' => out.push('/'),
                'n' => out.push('\n'),
                'r' => out.push('\r'),
                't' => out.push('\t'),
                other => out.push(other),
            }
        } else {
            out.push(c);
        }
    }
    Some(out)
}

pub fn parse_top_level_json_object(obj_str: &str) -> Result<Vec<(String, String)>, String> {
    let trimmed = obj_str.trim();
    if !trimmed.starts_with('{') || !trimmed.ends_with('}') {
        return Err("Not a JSON object".to_string());
    }
    let body = trimmed[1..trimmed.len() - 1].trim();
    if body.is_empty() {
        return Ok(Vec::new());
    }

    let mut items = Vec::new();
    let mut start = 0;
    let mut in_string = false;
    let mut escape = false;
    let mut depth = 0i32;
    let bytes = body.as_bytes();

    for (idx, &b) in bytes.iter().enumerate() {
        if in_string {
            if escape {
                escape = false;
            } else if b == b'\\' {
                escape = true;
            } else if b == b'"' {
                in_string = false;
            }
            continue;
        }
        match b {
            b'"' => in_string = true,
            b'{' | b'[' => depth += 1,
            b'}' | b']' => {
                depth -= 1;
                if depth < 0 {
                    return Err("Unbalanced braces in JSON".to_string());
                }
            }
            b',' if depth == 0 => {
                items.push(&body[start..idx]);
                start = idx + 1;
            }
            _ => {}
        }
    }
    if in_string || depth != 0 {
        return Err("Unterminated string or brace in JSON".to_string());
    }
    items.push(&body[start..]);

    let mut pairs = Vec::new();
    for item in items {
        let item_trim = item.trim();
        if item_trim.is_empty() {
            return Err("Trailing comma or empty entry in JSON".to_string());
        }
        // Find colon outside string
        let mut colon_idx = None;
        let mut s_mode = false;
        let mut esc = false;
        for (i, &b) in item_trim.as_bytes().iter().enumerate() {
            if s_mode {
                if esc {
                    esc = false;
                } else if b == b'\\' {
                    esc = true;
                } else if b == b'"' {
                    s_mode = false;
                }
                continue;
            }
            if b == b'"' {
                s_mode = true;
            } else if b == b':' {
                colon_idx = Some(i);
                break;
            }
        }
        let c_idx = colon_idx.ok_or_else(|| "Missing ':' in JSON object entry".to_string())?;
        let raw_key = item_trim[..c_idx].trim();
        let raw_val = item_trim[c_idx + 1..].trim();
        let key = unquote_json_string(raw_key)
            .ok_or_else(|| format!("Invalid JSON object key: {raw_key}"))?;
        if raw_val.is_empty() {
            return Err("Empty JSON value".to_string());
        }
        pairs.push((key, raw_val.to_string()));
    }

    Ok(pairs)
}
