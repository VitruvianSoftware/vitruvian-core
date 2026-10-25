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

//! Lifecycle hook engine (`telemetry_hook.py`): turns one Gemini-CLI-style
//! hook event on stdin into OTLP metrics and always answers
//! `{"decision": "allow"}`.
//!
//! The Python module carries its own copies of the metric builders, with
//! different descriptions, attribute order and resource block from
//! `otlp_builder.py`; they are reproduced here as they are, because that is
//! what the collector has been receiving.

use crate::http_client::{Flavor, TelemetryHttpClient};
use crate::json::J;
use crate::otlp_builder::{
    compute_histogram_buckets, otel_attrs, scutil_local_host_name, time_or_now,
    DEFAULT_LATENCY_BOUNDS,
};
use crate::pyutil::{
    get, get_or, py_float, py_int, py_iter, py_str, require_hashable, split_ws_count, strip,
    truthy, PyResult,
};
use crate::sys;
use std::collections::HashMap;
use std::io::{Read, Write};

pub const DEFAULT_ENDPOINT: &str = "https://otel.lab.ipv1337.dev";
const DEFAULT_MODEL: &str = "gemini-3.7-flash";

/// Hostname as the hook and the session exporter resolve it (no
/// `OTEL_RESOURCE_ATTRIBUTES`, no suffix stripping beyond the first label).
pub fn get_hostname() -> String {
    for var in [
        "ANTIGRAVITY_HOST",
        "ANTIGRAVITY_HOSTNAME",
        "HOST_NAME",
        "HOSTNAME",
    ] {
        if let Ok(v) = std::env::var(var) {
            if !strip(&v).is_empty() {
                return strip(&v).split('.').next().unwrap_or("").to_string();
            }
        }
    }
    if let Some(name) = scutil_local_host_name() {
        return name;
    }
    sys::hostname().split('.').next().unwrap_or("").to_string()
}

/// `ANTIGRAVITY_OTLP_ENDPOINT`, then `OTEL_EXPORTER_OTLP_ENDPOINT`, then the
/// homelab collector; trailing slashes dropped.
pub fn get_target_endpoint() -> String {
    let v = std::env::var("ANTIGRAVITY_OTLP_ENDPOINT")
        .or_else(|_| std::env::var("OTEL_EXPORTER_OTLP_ENDPOINT"))
        .unwrap_or_else(|_| DEFAULT_ENDPOINT.to_string());
    v.trim_end_matches('/').to_string()
}

pub fn build_sum_dp(value: &J, attributes: &[(&str, J)], time_unix_nano: Option<i128>) -> J {
    J::obj(vec![
        ("attributes", otel_attrs(attributes)),
        (
            "timeUnixNano",
            J::Str(time_or_now(time_unix_nano).to_string()),
        ),
        ("asInt", J::Str(py_str(value))),
    ])
}

pub fn build_sum_metric(name: &str, description: &str, unit: &str, datapoints: Vec<J>) -> J {
    J::obj(vec![
        ("name", J::str(name)),
        ("description", J::str(description)),
        ("unit", J::str(unit)),
        (
            "sum",
            J::obj(vec![
                ("aggregationTemporality", J::Int(2)),
                ("isMonotonic", J::Bool(true)),
                ("dataPoints", J::Arr(datapoints)),
            ]),
        ),
    ])
}

pub fn build_hist_dp(values: &[f64], attributes: &[(&str, J)], time_unix_nano: Option<i128>) -> J {
    let bounds = &DEFAULT_LATENCY_BOUNDS;
    let sum: f64 = values.iter().fold(0.0, |acc, v| acc + v);
    J::obj(vec![
        ("attributes", otel_attrs(attributes)),
        (
            "timeUnixNano",
            J::Str(time_or_now(time_unix_nano).to_string()),
        ),
        ("count", J::Str(values.len().to_string())),
        ("sum", J::Float(sum)),
        (
            "bucketCounts",
            J::Arr(
                compute_histogram_buckets(values, bounds)
                    .into_iter()
                    .map(J::Str)
                    .collect(),
            ),
        ),
        (
            "explicitBounds",
            J::Arr(bounds.iter().map(|b| J::Float(*b)).collect()),
        ),
    ])
}

pub fn build_hist_metric(name: &str, description: &str, unit: &str, datapoints: Vec<J>) -> J {
    J::obj(vec![
        ("name", J::str(name)),
        ("description", J::str(description)),
        ("unit", J::str(unit)),
        (
            "histogram",
            J::obj(vec![
                ("aggregationTemporality", J::Int(2)),
                ("dataPoints", J::Arr(datapoints)),
            ]),
        ),
    ])
}

pub fn build_token_usage_metric(
    input: i128,
    output: i128,
    thinking: i128,
    cached: i128,
    model: &J,
    host: &str,
) -> J {
    let t = sys::now_ns();
    let h = J::str(host);
    let dps = [
        ("input", input),
        ("output", output),
        ("thinking", thinking),
        ("cached", cached),
    ]
    .iter()
    .map(|(token_type, val)| {
        build_sum_dp(
            &J::Int(*val),
            &[
                ("host", h.clone()),
                ("model", model.clone()),
                ("token_type", J::str(*token_type)),
            ],
            Some(t),
        )
    })
    .collect();
    build_sum_metric(
        "antigravity_token_usage_total",
        "Cumulative count of LLM tokens consumed by Antigravity",
        "{tokens}",
        dps,
    )
}

pub fn build_api_request_metric(model: &J, status_code: &str, count: i64, host: &str) -> J {
    let dp = build_sum_dp(
        &J::from(count),
        &[
            ("host", J::str(host)),
            ("model", model.clone()),
            ("status_code", J::str(status_code)),
        ],
        None,
    );
    build_sum_metric(
        "antigravity_api_request_count_total",
        "Total count of API requests made to Gemini LLM endpoints",
        "{requests}",
        vec![dp],
    )
}

pub fn build_turn_count_metric(model: &J, count: i64, host: &str) -> J {
    let dp = build_sum_dp(
        &J::from(count),
        &[("host", J::str(host)), ("model", model.clone())],
        None,
    );
    build_sum_metric(
        "antigravity_turn_count_total",
        "Total agent turns completed in Antigravity sessions",
        "{turns}",
        vec![dp],
    )
}

pub fn build_subagent_spawn_metric(subagent_type: &str, count: i64, host: &str) -> J {
    let dp = build_sum_dp(
        &J::from(count),
        &[
            ("host", J::str(host)),
            ("subagent_type", J::str(subagent_type)),
        ],
        None,
    );
    build_sum_metric(
        "antigravity_subagent_spawn_count_total",
        "Total count of subagents invoked by Antigravity",
        "{subagents}",
        vec![dp],
    )
}

pub fn build_tool_call_count_metric(tool_name: &J, status: &str, count: i64, host: &str) -> J {
    let dp = build_sum_dp(
        &J::from(count),
        &[
            ("host", J::str(host)),
            ("tool_name", tool_name.clone()),
            ("status", J::str(status)),
        ],
        None,
    );
    build_sum_metric(
        "antigravity_tool_call_count_total",
        "Total count of tools executed by Antigravity",
        "{calls}",
        vec![dp],
    )
}

pub fn build_tool_call_latency_metric(
    tool_name: &J,
    latency_ms: f64,
    status: &str,
    host: &str,
) -> J {
    let dp = build_hist_dp(
        &[latency_ms],
        &[
            ("host", J::str(host)),
            ("tool_name", tool_name.clone()),
            ("status", J::str(status)),
        ],
        None,
    );
    build_hist_metric(
        "antigravity_tool_call_latency_milliseconds",
        "Latency distribution of tool calls in milliseconds",
        "ms",
        vec![dp],
    )
}

pub fn build_session_count_metric(status: &J, count: i64, host: &str) -> J {
    let dp = build_sum_dp(
        &J::from(count),
        &[("host", J::str(host)), ("status", status.clone())],
        None,
    );
    build_sum_metric(
        "antigravity_session_count_total",
        "Total count of Antigravity / agy interactive sessions",
        "{sessions}",
        vec![dp],
    )
}

/// The hook's own payload wrapper: no `service.version`, scope
/// `antigravity-telemetry`.
pub fn build_metrics_payload(metrics: Vec<J>, service_name: &str, host_name: &str) -> J {
    let attr = |k: &str, v: &str| {
        J::obj(vec![
            ("key", J::str(k)),
            ("value", J::obj(vec![("stringValue", J::str(v))])),
        ])
    };
    J::obj(vec![(
        "resourceMetrics",
        J::Arr(vec![J::obj(vec![
            (
                "resource",
                J::obj(vec![(
                    "attributes",
                    J::Arr(vec![
                        attr("service.name", service_name),
                        attr("host.name", host_name),
                    ]),
                )]),
            ),
            (
                "scopeMetrics",
                J::Arr(vec![J::obj(vec![
                    (
                        "scope",
                        J::obj(vec![
                            ("name", J::str("antigravity-telemetry")),
                            ("version", J::str("1.0.0")),
                        ]),
                    ),
                    ("metrics", J::Arr(metrics)),
                ])]),
            ),
        ])]),
    )])
}

/// Start times of tools seen in `BeforeTool`, keyed by tool name, so the
/// matching `AfterTool` in the same process can report a real latency.
#[derive(Default)]
pub struct ToolTimers {
    started: HashMap<String, f64>,
}

fn timer_key(tool_name: &J) -> PyResult<String> {
    require_hashable(tool_name)?;
    Ok(crate::json::dumps(tool_name, None, false))
}

/// Parse one hook event and build its metrics (`process_event`).
///
/// Errors carry the message Python's exception would; callers swallow them
/// the same way the Python entrypoints do.
pub fn process_event(data: &J, host: Option<&str>, timers: &mut ToolTimers) -> PyResult<Vec<J>> {
    let h = match host {
        Some(v) if !v.is_empty() => v.to_string(),
        _ => get_hostname(),
    };
    let hook_event = match get(data, "hook_event")? {
        Some(v) => v.clone(),
        None => get_or(data, "hookEvent", J::str(""))?,
    };
    let event = hook_event.as_str().unwrap_or("");
    let is_str = hook_event.as_str().is_some();
    let mut metrics = Vec::new();

    if is_str && matches!(event, "AfterModel" | "PostInvocation") {
        let resp = match get(data, "llm_response")? {
            Some(v) => v.clone(),
            None => get_or(data, "llmResponse", J::empty_obj())?,
        };
        let usage = match get(&resp, "usage_metadata")? {
            Some(v) => v.clone(),
            None => get_or(&resp, "usageMetadata", J::empty_obj())?,
        };
        let model = match get(&resp, "model")? {
            Some(v) => v.clone(),
            None => get_or(data, "model", J::str(DEFAULT_MODEL))?,
        };
        let count = |snake: &str, camel: &str| -> PyResult<i128> {
            let v = match get(&usage, snake)? {
                Some(v) => v.clone(),
                None => get_or(&usage, camel, J::Int(0))?,
            };
            py_int(&v)
        };
        let input_tokens = count("prompt_token_count", "promptTokenCount")?;
        let output_tokens = count("candidates_token_count", "candidatesTokenCount")?;
        let mut thinking_tokens = count("thinking_token_count", "thinkingTokenCount")?;
        let cached_tokens = count("cached_content_token_count", "cachedContentTokenCount")?;

        if thinking_tokens == 0 {
            let candidates = get_or(&resp, "candidates", J::Arr(vec![]))?;
            for cand in py_iter(&candidates)? {
                let content = get_or(&cand, "content", J::empty_obj())?;
                let parts = get_or(&content, "parts", J::Arr(vec![]))?;
                for part in py_iter(&parts)? {
                    if truthy(&get_or(&part, "thought", J::Bool(false))?)
                        && part.contains_key("text")
                    {
                        let text = part.get("text").expect("checked above");
                        let words = match text {
                            J::Str(s) => split_ws_count(s),
                            other => {
                                return Err(format!(
                                    "'{}' object has no attribute 'split'",
                                    crate::pyutil::type_name(other)
                                ))
                            }
                        };
                        thinking_tokens += words.max(1) as i128;
                    }
                }
            }
        }

        metrics.push(build_token_usage_metric(
            input_tokens,
            output_tokens,
            thinking_tokens,
            cached_tokens,
            &model,
            &h,
        ));
        metrics.push(build_api_request_metric(&model, "200", 1, &h));
        metrics.push(build_turn_count_metric(&model, 1, &h));
    } else if is_str && matches!(event, "BeforeTool" | "PreToolUse") {
        let tool_name = match get(data, "tool_name")? {
            Some(v) => v.clone(),
            None => get_or(data, "toolName", J::str("unknown"))?,
        };
        timers
            .started
            .insert(timer_key(&tool_name)?, sys::now_secs());

        if tool_name == J::str("invoke_subagent") {
            let tool_input = match get(data, "tool_input")? {
                Some(v) => v.clone(),
                None => get_or(data, "toolInput", J::empty_obj())?,
            };
            let mut subagent_type = J::str("general");
            for key in ["Recipient", "role", "subagent_type", "agent_name"] {
                let v = get_or(&tool_input, key, J::Null)?;
                if truthy(&v) {
                    subagent_type = v;
                    break;
                }
            }
            metrics.push(build_subagent_spawn_metric(&py_str(&subagent_type), 1, &h));
        }
    } else if is_str && matches!(event, "AfterTool" | "PostToolUse") {
        let tool_name = match get(data, "tool_name")? {
            Some(v) => v.clone(),
            None => get_or(data, "toolName", J::str("unknown"))?,
        };
        let error = match get(data, "error")? {
            Some(v) => v.clone(),
            None => get_or(data, "is_error", J::Bool(false))?,
        };
        let status = if truthy(&error) { "failure" } else { "success" };

        // CPython's `dict.pop` on an empty dict returns the default before
        // hashing the key, so an unhashable tool name only raises once some
        // timer has been recorded.
        let start_time = if timers.started.is_empty() {
            None
        } else {
            timers.started.remove(&timer_key(&tool_name)?)
        };
        let duration_ms = if data.contains_key("duration_ms") || data.contains_key("latency_ms") {
            let v = match data.get("duration_ms") {
                Some(v) => v.clone(),
                None => data.get("latency_ms").cloned().unwrap_or(J::Float(0.0)),
            };
            py_float(&v)?
        } else if let Some(start) = start_time.filter(|s| *s != 0.0) {
            ((sys::now_secs() - start) * 1000.0).max(1.0)
        } else {
            25.0
        };

        metrics.push(build_tool_call_count_metric(&tool_name, status, 1, &h));
        metrics.push(build_tool_call_latency_metric(
            &tool_name,
            duration_ms,
            status,
            &h,
        ));
    } else if is_str && matches!(event, "AfterAgent" | "Stop") {
        let status = get_or(data, "status", J::str("completed"))?;
        metrics.push(build_session_count_metric(&status, 1, &h));
    }

    Ok(metrics)
}

/// `_dispatch_otlp`: post the payload, ignore the outcome.
pub fn dispatch_otlp(payload: &J, endpoint: &str) {
    let client = TelemetryHttpClient::new(endpoint, 1.5, Flavor::Hook);
    let _ = client.post_json("v1/metrics", payload, true, true);
}

/// The hook entrypoint. Never fails and always allows, so a broken collector
/// can't wedge a `PreToolUse` permission check.
pub fn main() -> i32 {
    let result: PyResult<()> = (|| {
        let mut raw = Vec::new();
        std::io::stdin()
            .read_to_end(&mut raw)
            .map_err(|e| e.to_string())?;
        let raw = String::from_utf8(raw).map_err(|e| e.to_string())?;
        let data = if strip(&raw).is_empty() {
            J::empty_obj()
        } else {
            J::parse(&raw)?
        };
        let endpoint = get_target_endpoint();
        let host = get_hostname();
        let metrics = process_event(&data, Some(&host), &mut ToolTimers::default())?;
        if !metrics.is_empty() {
            let payload = build_metrics_payload(metrics, "antigravity", &host);
            dispatch_otlp(&payload, &endpoint);
        }
        Ok(())
    })();
    if let Err(e) = result {
        eprintln!("[telemetry_hook] Warning: {}", e);
    }
    let mut out = std::io::stdout();
    let _ = out.write_all(b"{\"decision\": \"allow\"}\n");
    let _ = out.flush();
    0
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::json::dumps;

    fn names(metrics: &[J]) -> Vec<String> {
        metrics
            .iter()
            .map(|m| m.get("name").and_then(J::as_str).unwrap_or("").to_string())
            .collect()
    }

    #[test]
    fn after_model_counts_tokens_and_thought_words() {
        let data = J::parse(
            r#"{"hook_event": "AfterModel", "llm_response": {"model": "gemini-x",
                "usage_metadata": {"prompt_token_count": "10", "candidates_token_count": 5.9},
                "candidates": [{"content": {"parts": [{"thought": true, "text": "a b c"}, {"text": "skip"}]}}]}}"#,
        )
        .unwrap();
        let m = process_event(&data, Some("h"), &mut ToolTimers::default()).unwrap();
        assert_eq!(
            names(&m),
            vec![
                "antigravity_token_usage_total",
                "antigravity_api_request_count_total",
                "antigravity_turn_count_total"
            ]
        );
        let dps = m[0].get("sum").unwrap().get("dataPoints").unwrap();
        let as_ints: Vec<String> = match dps {
            J::Arr(items) => items
                .iter()
                .map(|d| d.get("asInt").and_then(J::as_str).unwrap().to_string())
                .collect(),
            _ => vec![],
        };
        assert_eq!(as_ints, vec!["10", "5", "3", "0"]);
    }

    #[test]
    fn subagent_type_falls_through_falsy_values() {
        let data = J::parse(
            r#"{"hookEvent": "PreToolUse", "toolName": "invoke_subagent", "toolInput": {"Recipient": "", "role": "researcher"}}"#,
        )
        .unwrap();
        let m = process_event(&data, Some("h"), &mut ToolTimers::default()).unwrap();
        assert!(dumps(&m[0], None, false)
            .contains(r#"{"key": "subagent_type", "value": {"stringValue": "researcher"}}"#));
    }

    #[test]
    fn after_tool_latency_sources() {
        let mut timers = ToolTimers::default();
        let ev = J::parse(r#"{"hook_event": "AfterTool", "tool_name": "x", "latency_ms": "70000", "is_error": 1}"#).unwrap();
        let m = process_event(&ev, Some("h"), &mut timers).unwrap();
        let text = dumps(&m[1], None, false);
        assert!(text.contains(r#""sum": 70000.0"#), "{}", text);
        assert!(text.contains(r#"{"stringValue": "failure"}"#));
        let ev = J::parse(r#"{"hook_event": "AfterTool", "tool_name": "x"}"#).unwrap();
        let m = process_event(&ev, Some("h"), &mut timers).unwrap();
        assert!(dumps(&m[1], None, false).contains(r#""sum": 25.0"#));
    }

    #[test]
    fn malformed_payloads_raise_like_python() {
        let mut t = ToolTimers::default();
        assert_eq!(
            process_event(&J::Arr(vec![]), Some("h"), &mut t).unwrap_err(),
            "'list' object has no attribute 'get'"
        );
        let ev = J::parse(r#"{"hook_event": "AfterModel", "llm_response": null}"#).unwrap();
        assert_eq!(
            process_event(&ev, Some("h"), &mut t).unwrap_err(),
            "'NoneType' object has no attribute 'get'"
        );
        let ev = J::parse(r#"{"hook_event": "Unknown"}"#).unwrap();
        assert!(process_event(&ev, Some("h"), &mut t).unwrap().is_empty());
    }
}
