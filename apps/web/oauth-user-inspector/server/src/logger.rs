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

use serde_json::{json, Map, Value};
use std::time::{SystemTime, UNIX_EPOCH};

/// Structured logger for Cloud Run (JSON format) and local development.
#[derive(Debug, Clone)]
pub struct Logger {
    pub service: String,
    pub environment: String,
    pub is_cloud_run: bool,
    pub silent: bool,
    pub default_meta: Map<String, Value>,
}

impl Default for Logger {
    fn default() -> Self {
        create_logger()
    }
}

pub fn now_epoch_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

pub fn create_logger() -> Logger {
    let is_cloud_run = std::env::var("K_SERVICE").is_ok()
        || std::env::var("NODE_ENV").ok().as_deref() == Some("production");
    let environment = std::env::var("NODE_ENV").unwrap_or_else(|_| "development".to_string());
    let is_test = cfg!(test)
        || environment == "test"
        || std::env::var("LOG_SILENT").ok().as_deref() == Some("1");
    Logger {
        service: "oauth-user-inspector".to_string(),
        environment,
        is_cloud_run,
        silent: is_test,
        default_meta: Map::new(),
    }
}

impl Logger {
    pub fn child(&self, additional_meta: Map<String, Value>) -> Logger {
        let mut combined = self.default_meta.clone();
        for (k, v) in additional_meta {
            combined.insert(k, v);
        }
        Logger {
            service: self.service.clone(),
            environment: self.environment.clone(),
            is_cloud_run: self.is_cloud_run,
            silent: self.silent,
            default_meta: combined,
        }
    }

    fn emit(&self, severity: &str, message: &str, meta: Option<Value>) {
        if self.silent {
            return;
        }
        let mut record = self.default_meta.clone();
        if let Some(Value::Object(map)) = meta {
            for (k, v) in map {
                record.insert(k, v);
            }
        }
        if self.is_cloud_run {
            record.insert("severity".to_string(), Value::String(severity.to_string()));
            record.insert("message".to_string(), Value::String(message.to_string()));
            record.insert("service".to_string(), Value::String(self.service.clone()));
            record.insert(
                "environment".to_string(),
                Value::String(self.environment.clone()),
            );
            record.insert("timestamp_ms".to_string(), json!(now_epoch_ms()));
            println!("{}", Value::Object(record));
        } else {
            let meta_str = if record.is_empty() {
                String::new()
            } else {
                format!(" {}", Value::Object(record))
            };
            println!(
                "{} [{}]: {}{}",
                now_epoch_ms(),
                severity.to_lowercase(),
                message,
                meta_str
            );
        }
    }

    pub fn info(&self, message: &str, meta: Option<Value>) {
        self.emit("INFO", message, meta);
    }

    pub fn warn(&self, message: &str, meta: Option<Value>) {
        self.emit("WARNING", message, meta);
    }

    pub fn error(&self, message: &str, meta: Option<Value>) {
        self.emit("ERROR", message, meta);
    }

    pub fn debug(&self, message: &str, meta: Option<Value>) {
        self.emit("DEBUG", message, meta);
    }
}

pub fn create_request_logger(
    base: &Logger,
    request_id: &str,
    endpoint: &str,
    method: &str,
    provider: Option<&str>,
) -> Logger {
    let mut meta = Map::new();
    meta.insert(
        "requestId".to_string(),
        Value::String(request_id.to_string()),
    );
    meta.insert("endpoint".to_string(), Value::String(endpoint.to_string()));
    meta.insert("method".to_string(), Value::String(method.to_string()));
    if let Some(p) = provider {
        meta.insert("provider".to_string(), Value::String(p.to_string()));
    }
    base.child(meta)
}

pub fn log_timing(
    request_logger: &Logger,
    operation: &str,
    start_time_ms: u64,
    additional_meta: Option<Value>,
) {
    let duration = now_epoch_ms().saturating_sub(start_time_ms);
    let mut meta = match additional_meta {
        Some(Value::Object(m)) => m,
        _ => Map::new(),
    };
    meta.insert("duration".to_string(), json!(duration));
    meta.insert(
        "operation".to_string(),
        Value::String(operation.to_string()),
    );
    request_logger.info(&format!("{operation} completed"), Some(Value::Object(meta)));
}

pub fn log_error(
    request_logger: &Logger,
    message: &str,
    error_message: &str,
    additional_meta: Option<Value>,
) {
    let mut meta = match additional_meta {
        Some(Value::Object(m)) => m,
        _ => Map::new(),
    };
    meta.insert(
        "error".to_string(),
        Value::String(error_message.to_string()),
    );
    request_logger.error(message, Some(Value::Object(meta)));
}
