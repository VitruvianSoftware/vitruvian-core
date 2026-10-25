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

//! OTLP/HTTP JSON payload builder (`otlp_builder.py`).

use crate::json::J;
use crate::pyutil::{py_str, strip};
use crate::sys;

pub const DEFAULT_LATENCY_BOUNDS: [f64; 11] = [
    10.0, 50.0, 100.0, 250.0, 500.0, 1000.0, 2500.0, 5000.0, 10000.0, 30000.0, 60000.0,
];

/// First label of a hostname: `"mbp.local" -> "mbp"`.
fn first_label(s: &str) -> String {
    s.split('.').next().unwrap_or("").to_string()
}

fn env_nonblank(name: &str) -> Option<String> {
    std::env::var(name).ok().filter(|v| !strip(v).is_empty())
}

/// macOS's Bonjour name, which is what people recognise their Mac by.
pub fn scutil_local_host_name() -> Option<String> {
    if !std::path::Path::new("/usr/sbin/scutil").exists() {
        return None;
    }
    let out = sys::run(
        &["/usr/sbin/scutil", "--get", "LocalHostName"],
        None,
        Some(1.0),
    )
    .ok()?;
    let text = String::from_utf8_lossy(&out.stdout).into_owned();
    if out.code == 0 && !strip(&text).is_empty() {
        Some(strip(&text).to_string())
    } else {
        None
    }
}

/// Workstation hostname, stripped of domain suffixes (`otlp_builder.get_hostname`).
pub fn get_hostname() -> String {
    for var in ["ANTIGRAVITY_HOST", "ANTIGRAVITY_HOSTNAME"] {
        if let Some(v) = env_nonblank(var) {
            return first_label(strip(&v));
        }
    }
    let otel = std::env::var("OTEL_RESOURCE_ATTRIBUTES").unwrap_or_default();
    if !otel.is_empty() {
        for pair in otel.split(',') {
            if let Some((k, v)) = pair.split_once('=') {
                if matches!(strip(k), "host.name" | "host") {
                    return first_label(strip(v));
                }
            }
        }
    }
    for var in ["HOST_NAME", "HOSTNAME"] {
        if let Some(v) = env_nonblank(var) {
            return first_label(strip(&v));
        }
    }
    if let Some(name) = scutil_local_host_name() {
        return name;
    }
    let mut hostname = sys::hostname();
    for suffix in [".local", ".lan", ".home"] {
        if let Some(stripped) = hostname.strip_suffix(suffix) {
            hostname = stripped.to_string();
        }
    }
    first_label(&hostname)
}

/// `host_name or get_hostname()`.
pub fn host_or_default(host: Option<&str>) -> String {
    match host {
        Some(h) if !h.is_empty() => h.to_string(),
        _ => get_hostname(),
    }
}

/// One OTLP attribute, typed the way `otel_attr` dispatches on Python types.
pub fn otel_attr(key: &str, value: &J) -> J {
    let typed = match value {
        J::Bool(b) => J::obj(vec![("boolValue", J::Bool(*b))]),
        J::Int(i) => J::obj(vec![("intValue", J::Str(i.to_string()))]),
        J::Float(f) => J::obj(vec![("doubleValue", J::Float(*f))]),
        other => J::obj(vec![("stringValue", J::Str(py_str(other)))]),
    };
    J::obj(vec![("key", J::str(key)), ("value", typed)])
}

/// An attribute array, skipping `None` values.
pub fn otel_attrs(attrs: &[(&str, J)]) -> J {
    J::Arr(
        attrs
            .iter()
            .filter(|(_, v)| !v.is_null())
            .map(|(k, v)| otel_attr(k, v))
            .collect(),
    )
}

fn string_attr(key: &str, value: &str) -> J {
    J::obj(vec![
        ("key", J::str(key)),
        ("value", J::obj(vec![("stringValue", J::str(value))])),
    ])
}

pub fn build_resource(service_name: &str, host_name: Option<&str>) -> J {
    let host = host_or_default(host_name);
    J::obj(vec![(
        "attributes",
        J::Arr(vec![
            string_attr("service.name", service_name),
            string_attr("service.version", "1.0.0"),
            string_attr("host.name", &host),
        ]),
    )])
}

/// Count observed values into explicit-bounds buckets (`le` semantics).
pub fn compute_histogram_buckets(values: &[f64], bounds: &[f64]) -> Vec<String> {
    let mut counts = vec![0u64; bounds.len() + 1];
    for v in values {
        match bounds.iter().position(|b| v <= b) {
            Some(i) => counts[i] += 1,
            None => *counts.last_mut().expect("bounds.len() + 1 > 0") += 1,
        }
    }
    counts.iter().map(|c| c.to_string()).collect()
}

/// `t or time.time_ns()`.
pub fn time_or_now(t: Option<i128>) -> i128 {
    match t {
        Some(v) if v != 0 => v,
        _ => sys::now_ns(),
    }
}

pub fn build_sum_datapoint(
    value: &J,
    attributes: &[(&str, J)],
    time_unix_nano: Option<i128>,
    start_time_unix_nano: Option<i128>,
) -> J {
    let mut dp = J::obj(vec![
        ("attributes", otel_attrs(attributes)),
        (
            "timeUnixNano",
            J::Str(time_or_now(time_unix_nano).to_string()),
        ),
        ("asInt", J::Str(py_str(value))),
    ]);
    if let Some(start) = start_time_unix_nano {
        dp.set("startTimeUnixNano", J::Str(start.to_string()));
    }
    dp
}

pub fn build_histogram_datapoint(
    values: &[f64],
    attributes: &[(&str, J)],
    explicit_bounds: Option<&[f64]>,
    time_unix_nano: Option<i128>,
) -> J {
    let bounds = explicit_bounds.unwrap_or(&DEFAULT_LATENCY_BOUNDS);
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

pub fn build_sum_metric(
    name: &str,
    description: &str,
    unit: &str,
    datapoints: Vec<J>,
    is_monotonic: bool,
    aggregation_temporality: i64,
) -> J {
    J::obj(vec![
        ("name", J::str(name)),
        ("description", J::str(description)),
        ("unit", J::str(unit)),
        (
            "sum",
            J::obj(vec![
                ("aggregationTemporality", J::from(aggregation_temporality)),
                ("isMonotonic", J::Bool(is_monotonic)),
                ("dataPoints", J::Arr(datapoints)),
            ]),
        ),
    ])
}

pub fn build_histogram_metric(
    name: &str,
    description: &str,
    unit: &str,
    datapoints: Vec<J>,
    aggregation_temporality: i64,
) -> J {
    J::obj(vec![
        ("name", J::str(name)),
        ("description", J::str(description)),
        ("unit", J::str(unit)),
        (
            "histogram",
            J::obj(vec![
                ("aggregationTemporality", J::from(aggregation_temporality)),
                ("dataPoints", J::Arr(datapoints)),
            ]),
        ),
    ])
}

// ============================================================================
// The 7 standard metric builders
// ============================================================================

pub fn build_token_usage_metric(
    input: &J,
    output: &J,
    thinking: &J,
    cached: &J,
    model: &J,
    host: Option<&str>,
    time_unix_nano: Option<i128>,
) -> J {
    let h = J::Str(host_or_default(host));
    let dps = [
        ("input", input),
        ("output", output),
        ("thinking", thinking),
        ("cached", cached),
    ]
    .iter()
    .map(|(token_type, val)| {
        build_sum_datapoint(
            val,
            &[
                ("host", h.clone()),
                ("token_type", J::str(*token_type)),
                ("model", model.clone()),
            ],
            time_unix_nano,
            None,
        )
    })
    .collect();
    build_sum_metric(
        "antigravity_token_usage_total",
        "Total tokens consumed by Antigravity and AGY CLI",
        "{tokens}",
        dps,
        true,
        2,
    )
}

pub fn build_api_request_metric(
    model: &J,
    status_code: &J,
    count: i64,
    host: Option<&str>,
    time_unix_nano: Option<i128>,
) -> J {
    let h = J::Str(host_or_default(host));
    let dp = build_sum_datapoint(
        &J::from(count),
        &[
            ("host", h),
            ("model", model.clone()),
            ("status_code", J::Str(py_str(status_code))),
        ],
        time_unix_nano,
        None,
    );
    build_sum_metric(
        "antigravity_api_request_count_total",
        "Total API requests to LLM backend",
        "{requests}",
        vec![dp],
        true,
        2,
    )
}

pub fn build_tool_call_count_metric(
    tool_name: &J,
    status: &J,
    count: i64,
    host: Option<&str>,
    time_unix_nano: Option<i128>,
) -> J {
    let h = J::Str(host_or_default(host));
    let dp = build_sum_datapoint(
        &J::from(count),
        &[
            ("host", h),
            ("tool_name", tool_name.clone()),
            ("status", status.clone()),
        ],
        time_unix_nano,
        None,
    );
    build_sum_metric(
        "antigravity_tool_call_count_total",
        "Total tool calls executed by Antigravity and AGY agents",
        "{calls}",
        vec![dp],
        true,
        2,
    )
}

pub fn build_tool_call_latency_metric(
    tool_name: &J,
    latency_ms: &[f64],
    status: &J,
    host: Option<&str>,
    explicit_bounds: Option<&[f64]>,
    time_unix_nano: Option<i128>,
) -> J {
    let h = J::Str(host_or_default(host));
    let dp = build_histogram_datapoint(
        latency_ms,
        &[
            ("host", h),
            ("tool_name", tool_name.clone()),
            ("status", status.clone()),
        ],
        explicit_bounds,
        time_unix_nano,
    );
    build_histogram_metric(
        "antigravity_tool_call_latency_milliseconds",
        "Tool call duration distribution in milliseconds",
        "ms",
        vec![dp],
        2,
    )
}

pub fn build_session_count_metric(
    status: &J,
    count: i64,
    host: Option<&str>,
    time_unix_nano: Option<i128>,
) -> J {
    let h = J::Str(host_or_default(host));
    let dp = build_sum_datapoint(
        &J::from(count),
        &[("host", h), ("status", status.clone())],
        time_unix_nano,
        None,
    );
    build_sum_metric(
        "antigravity_session_count_total",
        "Total sessions launched",
        "{sessions}",
        vec![dp],
        true,
        2,
    )
}

pub fn build_turn_count_metric(
    model: &J,
    count: i64,
    host: Option<&str>,
    time_unix_nano: Option<i128>,
) -> J {
    let h = J::Str(host_or_default(host));
    let dp = build_sum_datapoint(
        &J::from(count),
        &[("host", h), ("model", model.clone())],
        time_unix_nano,
        None,
    );
    build_sum_metric(
        "antigravity_turn_count_total",
        "Total turns executed by Antigravity agents",
        "{turns}",
        vec![dp],
        true,
        2,
    )
}

pub fn build_subagent_spawn_metric(
    subagent_type: &J,
    count: i64,
    host: Option<&str>,
    time_unix_nano: Option<i128>,
) -> J {
    let h = J::Str(host_or_default(host));
    let dp = build_sum_datapoint(
        &J::from(count),
        &[("host", h), ("subagent_type", subagent_type.clone())],
        time_unix_nano,
        None,
    );
    build_sum_metric(
        "antigravity_subagent_spawn_count_total",
        "Total subagents spawned",
        "{spawns}",
        vec![dp],
        true,
        2,
    )
}

pub const SCOPE_NAME: &str = "tools/antigravity-telemetry";
pub const SCOPE_VERSION: &str = "1.0.0";

fn scope(scope_name: &str, scope_version: &str) -> J {
    J::obj(vec![
        ("name", J::str(scope_name)),
        ("version", J::str(scope_version)),
    ])
}

/// Wrap metrics in a `/v1/metrics` export request.
pub fn build_metrics_payload(
    metrics: Vec<J>,
    service_name: &str,
    host_name: Option<&str>,
    scope_name: &str,
    scope_version: &str,
) -> J {
    let host = host_or_default(host_name);
    J::obj(vec![(
        "resourceMetrics",
        J::Arr(vec![J::obj(vec![
            ("resource", build_resource(service_name, Some(&host))),
            (
                "scopeMetrics",
                J::Arr(vec![J::obj(vec![
                    ("scope", scope(scope_name, scope_version)),
                    ("metrics", J::Arr(metrics)),
                ])]),
            ),
        ])]),
    )])
}

// ============================================================================
// Traces
// ============================================================================

pub struct SpanArgs<'a> {
    pub name: &'a str,
    pub start_time_ns: i128,
    pub end_time_ns: i128,
    pub attributes: Vec<(&'a str, J)>,
    pub trace_id: Option<String>,
    pub span_id: Option<String>,
    pub parent_span_id: Option<String>,
    pub kind: i64,
    pub status_code: i64,
    pub status_message: Option<String>,
}

impl<'a> SpanArgs<'a> {
    pub fn new(name: &'a str, start_time_ns: i128, end_time_ns: i128) -> Self {
        SpanArgs {
            name,
            start_time_ns,
            end_time_ns,
            attributes: Vec::new(),
            trace_id: None,
            span_id: None,
            parent_span_id: None,
            kind: 1,
            status_code: 1,
            status_message: None,
        }
    }
}

fn non_empty(s: &Option<String>) -> Option<&str> {
    s.as_deref().filter(|v| !v.is_empty())
}

/// One OTLP span. Unset trace and span IDs are random, as in Python
/// (`secrets.token_hex`).
pub fn build_span(args: &SpanArgs) -> J {
    let trace_id = non_empty(&args.trace_id)
        .map(str::to_string)
        .unwrap_or_else(|| sys::token_hex(16));
    let span_id = non_empty(&args.span_id)
        .map(str::to_string)
        .unwrap_or_else(|| sys::token_hex(8));
    let mut status = J::obj(vec![("code", J::from(args.status_code))]);
    let mut span = J::obj(vec![
        ("traceId", J::Str(trace_id)),
        ("spanId", J::Str(span_id)),
        ("name", J::str(args.name)),
        ("kind", J::from(args.kind)),
        ("startTimeUnixNano", J::Str(args.start_time_ns.to_string())),
        ("endTimeUnixNano", J::Str(args.end_time_ns.to_string())),
        ("attributes", otel_attrs(&args.attributes)),
        ("status", J::Null),
    ]);
    if let Some(parent) = non_empty(&args.parent_span_id) {
        span.set("parentSpanId", J::str(parent));
    }
    if let Some(msg) = non_empty(&args.status_message) {
        status.set("message", J::str(msg));
    }
    span.set("status", status);
    span
}

/// Wrap spans in a `/v1/traces` export request.
pub fn build_traces_payload(
    spans: Vec<J>,
    service_name: &str,
    host_name: Option<&str>,
    scope_name: &str,
    scope_version: &str,
) -> J {
    let host = host_or_default(host_name);
    J::obj(vec![(
        "resourceSpans",
        J::Arr(vec![J::obj(vec![
            ("resource", build_resource(service_name, Some(&host))),
            (
                "scopeSpans",
                J::Arr(vec![J::obj(vec![
                    ("scope", scope(scope_name, scope_version)),
                    ("spans", J::Arr(spans)),
                ])]),
            ),
        ])]),
    )])
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::json::dumps;

    #[test]
    fn histogram_buckets_le_semantics() {
        let got = compute_histogram_buckets(&[5.0, 10.0, 10.1, 70000.0], &DEFAULT_LATENCY_BOUNDS);
        assert_eq!(
            got,
            vec!["2", "1", "0", "0", "0", "0", "0", "0", "0", "0", "0", "1"]
        );
    }

    #[test]
    fn attrs_typed_like_python() {
        let a = otel_attrs(&[
            ("b", J::Bool(true)),
            ("i", J::Int(3)),
            ("f", J::Float(1.5)),
            ("n", J::Null),
            ("s", J::str("x")),
        ]);
        assert_eq!(
            dumps(&a, None, false),
            r#"[{"key": "b", "value": {"boolValue": true}}, {"key": "i", "value": {"intValue": "3"}}, {"key": "f", "value": {"doubleValue": 1.5}}, {"key": "s", "value": {"stringValue": "x"}}]"#
        );
    }

    #[test]
    fn span_ids_and_optional_fields() {
        let mut args = SpanArgs::new("op", 1, 2);
        args.parent_span_id = Some("abcd".into());
        args.status_message = Some("boom".into());
        let s = build_span(&args);
        assert_eq!(s.get("traceId").and_then(J::as_str).map(str::len), Some(32));
        assert_eq!(s.get("spanId").and_then(J::as_str).map(str::len), Some(16));
        assert_eq!(s.get("parentSpanId"), Some(&J::str("abcd")));
        assert_eq!(
            dumps(s.get("status").unwrap(), None, false),
            r#"{"code": 1, "message": "boom"}"#
        );
        let keys: Vec<&str> = match &s {
            J::Obj(p) => p.iter().map(|(k, _)| k.as_str()).collect(),
            _ => vec![],
        };
        assert_eq!(
            keys,
            vec![
                "traceId",
                "spanId",
                "name",
                "kind",
                "startTimeUnixNano",
                "endTimeUnixNano",
                "attributes",
                "status",
                "parentSpanId"
            ]
        );
    }

    #[test]
    fn token_metric_shape() {
        let m = build_token_usage_metric(
            &J::Int(1),
            &J::Int(2),
            &J::Int(3),
            &J::Int(4),
            &J::str("m"),
            Some("h"),
            Some(7),
        );
        let text = dumps(&m, None, false);
        assert!(text.starts_with(r#"{"name": "antigravity_token_usage_total", "description": "Total tokens consumed by Antigravity and AGY CLI", "unit": "{tokens}", "sum": {"aggregationTemporality": 2, "isMonotonic": true, "dataPoints": [{"attributes": [{"key": "host", "value": {"stringValue": "h"}}, {"key": "token_type", "value": {"stringValue": "input"}}, {"key": "model", "value": {"stringValue": "m"}}], "timeUnixNano": "7", "asInt": "1"}"#), "{}", text);
    }
}
