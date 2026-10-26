// Copyright (c) 2026 VitruvianSoftware
//
// SPDX-License-Identifier: MIT

use serde_json::{json, Map, Value};
use std::collections::{HashMap, HashSet};

pub fn escape_html(val: &Value) -> String {
    let s = match val {
        Value::Null => String::new(),
        Value::String(s) => s.clone(),
        Value::Bool(b) => b.to_string(),
        Value::Number(n) => n.to_string(),
        other => other.to_string(),
    };
    escape_html_str(&s)
}

pub fn escape_html_str(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&#39;")
}

pub fn openui_literal(val: &Value) -> String {
    match val {
        Value::Null => "null".to_string(),
        Value::Bool(b) => if *b { "true" } else { "false" }.to_string(),
        Value::Number(n) => {
            let text = n.to_string();
            if !text.contains('e') && !text.contains('E') {
                return text;
            }
            quote_openui_str(&text)
        }
        Value::String(s) => quote_openui_str(s),
        other => quote_openui_str(&other.to_string()),
    }
}

pub fn openui_f64(val: f64) -> String {
    if val.is_finite() {
        let s = format!("{val}");
        if !s.contains('e') && !s.contains('E') {
            return s;
        }
    }
    quote_openui_str(&val.to_string())
}

fn quote_openui_str(s: &str) -> String {
    let escaped = s
        .replace('\\', "\\\\")
        .replace('"', "\\\"")
        .replace("\r\n", "\n")
        .replace('\r', "\n")
        .replace('\n', "\\n")
        .replace('\t', "\\t");
    format!("\"{escaped}\"")
}

pub fn resolve_data_path(context: &Value, path_str: &str) -> Option<Value> {
    let parts: Vec<&str> = path_str.split('.').collect();
    resolve_parts(context, &parts)
}

fn resolve_parts(current: &Value, parts: &[&str]) -> Option<Value> {
    if parts.is_empty() {
        return Some(current.clone());
    }
    match current {
        Value::Null => None,
        Value::Array(arr) => {
            let mapped: Vec<Value> = arr
                .iter()
                .map(|item| resolve_parts(item, parts).unwrap_or(Value::Null))
                .collect();
            Some(Value::Array(mapped))
        }
        Value::Object(map) => {
            let next = map.get(parts[0])?;
            resolve_parts(next, &parts[1..])
        }
        _ => None,
    }
}

#[derive(Debug, Clone, PartialEq)]
enum Tok {
    Punct(char),
    Str(String),
    Num(f64),
    Bool(bool),
    Null,
    Ident(String),
}

fn tokenize(input: &str) -> Vec<Tok> {
    let chars: Vec<char> = input.chars().collect();
    let len = chars.len();
    let mut i = 0;
    let mut tokens = Vec::new();

    while i < len {
        let ch = chars[i];
        if ch.is_ascii_whitespace() {
            i += 1;
            continue;
        }
        if ch == '#' || (ch == '/' && i + 1 < len && chars[i + 1] == '/') {
            while i < len && chars[i] != '\n' {
                i += 1;
            }
            continue;
        }
        if "()[],=:+".contains(ch) {
            tokens.push(Tok::Punct(ch));
            i += 1;
            continue;
        }
        if ch == '"' || ch == '\'' {
            let quote = ch;
            i += 1;
            let mut s = String::new();
            while i < len && chars[i] != quote {
                if chars[i] == '\\' && i + 1 < len {
                    let next = chars[i + 1];
                    match next {
                        'n' => s.push('\n'),
                        't' => s.push('\t'),
                        other => s.push(other),
                    }
                    i += 2;
                } else {
                    s.push(chars[i]);
                    i += 1;
                }
            }
            if i < len {
                i += 1;
            }
            tokens.push(Tok::Str(s));
            continue;
        }
        if ch.is_ascii_digit() || (ch == '-' && i + 1 < len && chars[i + 1].is_ascii_digit()) {
            let mut num_str = String::new();
            num_str.push(ch);
            i += 1;
            while i < len && (chars[i].is_ascii_digit() || chars[i] == '.') {
                num_str.push(chars[i]);
                i += 1;
            }
            let n = num_str.parse::<f64>().unwrap_or(0.0);
            tokens.push(Tok::Num(n));
            continue;
        }
        if ch.is_ascii_alphabetic() || ch == '_' || ch == '$' {
            let mut ident = String::new();
            ident.push(ch);
            i += 1;
            while i < len
                && (chars[i].is_ascii_alphanumeric()
                    || chars[i] == '_'
                    || chars[i] == '$'
                    || chars[i] == '.'
                    || chars[i] == '-')
            {
                ident.push(chars[i]);
                i += 1;
            }
            match ident.as_str() {
                "true" => tokens.push(Tok::Bool(true)),
                "false" => tokens.push(Tok::Bool(false)),
                "null" => tokens.push(Tok::Null),
                _ => tokens.push(Tok::Ident(ident)),
            }
            continue;
        }
        i += 1;
    }
    tokens
}

#[derive(Debug, Clone)]
enum Expr {
    Literal(Value),
    Array(Vec<Expr>),
    Concat(Box<Expr>, Box<Expr>),
    Ref(String),
    Component(String, Vec<Expr>),
}

#[derive(Debug, Clone, PartialEq)]
pub struct ParsedOpenUI {
    pub root: Value,
    pub bindings: HashMap<String, Value>,
    pub order: Vec<String>,
}

fn f64_to_json_num(n: f64) -> Value {
    if n.fract() == 0.0 && n >= (i64::MIN as f64) && n <= (i64::MAX as f64) {
        json!(n as i64)
    } else {
        json!(n)
    }
}

pub fn parse_openui_lang(source: &str, data: &Value) -> ParsedOpenUI {
    let tokens = tokenize(source);
    let mut pos = 0;

    fn match_punct(tokens: &[Tok], pos: &mut usize, target: char) -> bool {
        if let Some(Tok::Punct(c)) = tokens.get(*pos) {
            if *c == target {
                *pos += 1;
                return true;
            }
        }
        false
    }

    fn parse_primary(tokens: &[Tok], pos: &mut usize) -> Option<Expr> {
        let tok = tokens.get(*pos)?.clone();
        match tok {
            Tok::Str(s) => {
                *pos += 1;
                Some(Expr::Literal(Value::String(s)))
            }
            Tok::Num(n) => {
                *pos += 1;
                Some(Expr::Literal(f64_to_json_num(n)))
            }
            Tok::Bool(b) => {
                *pos += 1;
                Some(Expr::Literal(Value::Bool(b)))
            }
            Tok::Null => {
                *pos += 1;
                Some(Expr::Literal(Value::Null))
            }
            Tok::Punct('[') => {
                *pos += 1;
                let mut items = Vec::new();
                while *pos < tokens.len() && tokens.get(*pos) != Some(&Tok::Punct(']')) {
                    if let Some(e) = parse_expr(tokens, pos) {
                        items.push(e);
                    }
                    match_punct(tokens, pos, ',');
                }
                match_punct(tokens, pos, ']');
                Some(Expr::Array(items))
            }
            Tok::Ident(ident) => {
                *pos += 1;
                if match_punct(tokens, pos, '(') {
                    let mut args = Vec::new();
                    while *pos < tokens.len() && tokens.get(*pos) != Some(&Tok::Punct(')')) {
                        if let Some(e) = parse_expr(tokens, pos) {
                            args.push(e);
                        }
                        match_punct(tokens, pos, ',');
                    }
                    match_punct(tokens, pos, ')');
                    Some(Expr::Component(ident, args))
                } else {
                    Some(Expr::Ref(ident))
                }
            }
            Tok::Punct(c) => {
                *pos += 1;
                Some(Expr::Literal(Value::String(c.to_string())))
            }
        }
    }

    fn parse_expr(tokens: &[Tok], pos: &mut usize) -> Option<Expr> {
        let mut left = parse_primary(tokens, pos)?;
        while match_punct(tokens, pos, '+') {
            if let Some(right) = parse_primary(tokens, pos) {
                left = Expr::Concat(Box::new(left), Box::new(right));
            }
        }
        Some(left)
    }

    let mut raw_bindings: HashMap<String, Expr> = HashMap::new();
    let mut order: Vec<String> = Vec::new();

    while pos < tokens.len() {
        if let (Some(Tok::Ident(name)), Some(Tok::Punct('='))) =
            (tokens.get(pos).cloned(), tokens.get(pos + 1))
        {
            pos += 2;
            if let Some(expr) = parse_expr(&tokens, &mut pos) {
                raw_bindings.insert(name.clone(), expr);
                if !order.contains(&name) {
                    order.push(name);
                }
            }
        } else if let Some(expr) = parse_expr(&tokens, &mut pos) {
            if !raw_bindings.contains_key("root") {
                raw_bindings.insert("root".to_string(), expr);
                order.push("root".to_string());
            }
        }
    }

    let mut resolved_cache: HashMap<String, Value> = HashMap::new();
    let mut visiting: HashSet<String> = HashSet::new();

    let mut data_ctx = Map::new();
    data_ctx.insert("data".to_string(), data.clone());
    if let Value::Object(m) = data {
        for (k, v) in m {
            data_ctx.insert(k.clone(), v.clone());
        }
    }
    let data_ctx_val = Value::Object(data_ctx);

    fn val_to_concat_str(v: &Value) -> String {
        match v {
            Value::Null => String::new(),
            Value::String(s) => s.clone(),
            Value::Bool(b) => b.to_string(),
            Value::Number(n) => n.to_string(),
            other => other.to_string(),
        }
    }

    fn evaluate(
        node: &Expr,
        raw_bindings: &HashMap<String, Expr>,
        resolved_cache: &mut HashMap<String, Value>,
        visiting: &mut HashSet<String>,
        data: &Value,
        data_ctx_val: &Value,
    ) -> Value {
        match node {
            Expr::Literal(v) => v.clone(),
            Expr::Array(items) => Value::Array(
                items
                    .iter()
                    .map(|e| {
                        evaluate(
                            e,
                            raw_bindings,
                            resolved_cache,
                            visiting,
                            data,
                            data_ctx_val,
                        )
                    })
                    .collect(),
            ),
            Expr::Concat(l, r) => {
                let lv = evaluate(
                    l,
                    raw_bindings,
                    resolved_cache,
                    visiting,
                    data,
                    data_ctx_val,
                );
                let rv = evaluate(
                    r,
                    raw_bindings,
                    resolved_cache,
                    visiting,
                    data,
                    data_ctx_val,
                );
                Value::String(format!(
                    "{}{}",
                    val_to_concat_str(&lv),
                    val_to_concat_str(&rv)
                ))
            }
            Expr::Ref(name) => {
                if let Some(cached) = resolved_cache.get(name) {
                    return cached.clone();
                }
                if let Some(raw_expr) = raw_bindings.get(name) {
                    if !visiting.contains(name) {
                        visiting.insert(name.clone());
                        let val = evaluate(
                            raw_expr,
                            raw_bindings,
                            resolved_cache,
                            visiting,
                            data,
                            data_ctx_val,
                        );
                        visiting.remove(name);
                        resolved_cache.insert(name.clone(), val.clone());
                        return val;
                    }
                }
                if name.contains('.') {
                    if let Some(from_data) = resolve_data_path(data_ctx_val, name) {
                        return from_data;
                    }
                }
                if let Value::Object(m) = data {
                    if let Some(v) = m.get(name) {
                        return v.clone();
                    }
                }
                Value::String(name.clone())
            }
            Expr::Component(name, args) => {
                if name == "Query" {
                    let fallback = args
                        .get(2)
                        .map(|e| {
                            evaluate(
                                e,
                                raw_bindings,
                                resolved_cache,
                                visiting,
                                data,
                                data_ctx_val,
                            )
                        })
                        .unwrap_or_else(|| json!({}));
                    return if fallback.is_null() {
                        json!({})
                    } else {
                        fallback
                    };
                }
                let eval_args: Vec<Value> = args
                    .iter()
                    .map(|e| {
                        evaluate(
                            e,
                            raw_bindings,
                            resolved_cache,
                            visiting,
                            data,
                            data_ctx_val,
                        )
                    })
                    .collect();
                json!({
                    "$component": name,
                    "args": eval_args,
                })
            }
        }
    }

    for key in &order {
        if !resolved_cache.contains_key(key) {
            if let Some(expr) = raw_bindings.get(key) {
                visiting.insert(key.clone());
                let val = evaluate(
                    expr,
                    &raw_bindings,
                    &mut resolved_cache,
                    &mut visiting,
                    data,
                    &data_ctx_val,
                );
                visiting.remove(key);
                resolved_cache.insert(key.clone(), val);
            }
        }
    }

    let root = resolved_cache.get("root").cloned().unwrap_or(Value::Null);
    ParsedOpenUI {
        root,
        bindings: resolved_cache,
        order,
    }
}

struct ToneClasses {
    text: &'static str,
    bg: &'static str,
    border: &'static str,
    bar: &'static str,
}

fn tone_classes(tone: &str) -> ToneClasses {
    match tone.to_ascii_lowercase().as_str() {
        "success" | "good" | "green" => ToneClasses {
            text: "text-emerald-500",
            bg: "bg-emerald-500/15",
            border: "border-emerald-500/30",
            bar: "bg-emerald-500",
        },
        "warning" | "warn" | "amber" | "wait" => ToneClasses {
            text: "text-amber-500",
            bg: "bg-amber-500/15",
            border: "border-amber-500/30",
            bar: "bg-amber-500",
        },
        "danger" | "error" | "bad" | "red" => ToneClasses {
            text: "text-rose-500",
            bg: "bg-rose-500/15",
            border: "border-rose-500/30",
            bar: "bg-rose-500",
        },
        "info" | "blue" | "run" => ToneClasses {
            text: "text-blue-500",
            bg: "bg-blue-500/15",
            border: "border-blue-500/30",
            bar: "bg-blue-500",
        },
        "purple" => ToneClasses {
            text: "text-purple-500",
            bg: "bg-purple-500/15",
            border: "border-purple-500/30",
            bar: "bg-purple-500",
        },
        _ => ToneClasses {
            text: "text-[var(--foreground)]",
            bg: "bg-[var(--background)]",
            border: "border-[var(--border)]",
            bar: "bg-blue-500",
        },
    }
}

#[derive(Debug, Clone)]
pub struct RenderOptions {
    pub dsl_source: Option<String>,
    pub include_dsl_tab: bool,
    pub id_prefix: String,
    pub title: String,
    pub footer: String,
}

impl Default for RenderOptions {
    fn default() -> Self {
        Self {
            dsl_source: None,
            include_dsl_tab: true,
            id_prefix: "openui".to_string(),
            title: "OpenUI Dashboard".to_string(),
            footer: String::new(),
        }
    }
}

pub fn render_node_to_html(node: &Value, opts: &RenderOptions) -> String {
    match node {
        Value::Null => String::new(),
        Value::String(_) | Value::Number(_) | Value::Bool(_) => {
            format!(
                "<span class=\"text-xs text-[var(--foreground)]\">{}</span>",
                escape_html(node)
            )
        }
        Value::Array(arr) => arr
            .iter()
            .map(|c| render_node_to_html(c, opts))
            .collect::<Vec<_>>()
            .join("\n"),
        Value::Object(obj) => {
            let Some(name) = obj.get("$component").and_then(|v| v.as_str()) else {
                return String::new();
            };
            let args = obj
                .get("args")
                .and_then(|v| v.as_array())
                .cloned()
                .unwrap_or_default();

            match name {
                "Card" => {
                    let children = args
                        .first()
                        .and_then(|v| v.as_array())
                        .cloned()
                        .unwrap_or_else(|| args.clone());
                    let inner = children
                        .iter()
                        .map(|c| render_node_to_html(c, opts))
                        .collect::<Vec<_>>()
                        .join("\n");
                    format!(
                        "<div class=\"bg-[var(--card)] text-[var(--foreground)] border border-[var(--border)] rounded-xl p-4 shadow-sm space-y-3\" data-openui-component=\"Card\">\n        {inner}\n      </div>"
                    )
                }
                "Header" => {
                    let title = args.first().unwrap_or(&Value::Null);
                    let subtitle = args.get(1).unwrap_or(&Value::Null);
                    let status_text = args.get(2).unwrap_or(&Value::Null);
                    let status_tone = args.get(3).and_then(|v| v.as_str()).unwrap_or("success");
                    let tone = tone_classes(status_tone);
                    let status_str = escape_html(status_text);
                    let badge_html = if !status_str.is_empty() {
                        format!(
                            "<span class=\"px-2.5 py-1 rounded-full text-xs font-medium {} {} border {}\">{}</span>",
                            tone.bg, tone.text, tone.border, status_str
                        )
                    } else {
                        String::new()
                    };
                    let sub_str = escape_html(subtitle);
                    let sub_html = if !sub_str.is_empty() {
                        format!(
                            "<span class=\"px-2 py-0.5 rounded-md bg-[var(--background)] border border-[var(--border)] font-mono text-xs text-[var(--muted-foreground)]\">{}</span>",
                            sub_str
                        )
                    } else {
                        String::new()
                    };
                    format!(
                        "<div class=\"flex flex-wrap items-center justify-between gap-2 pb-2.5 border-b border-[var(--border)]\" data-openui-component=\"Header\">\n        <div class=\"flex items-center gap-2.5\">\n          <span class=\"relative flex h-2.5 w-2.5\">\n            <span class=\"animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75\"></span>\n            <span class=\"relative inline-flex rounded-full h-2.5 w-2.5 {}\"></span>\n          </span>\n          <div>\n            <div class=\"flex items-center gap-2\">\n              <h2 class=\"font-semibold text-sm text-[var(--foreground)]\">{}</h2>\n              {}\n            </div>\n          </div>\n        </div>\n        <div class=\"flex items-center gap-2\">\n          {}\n        </div>\n      </div>",
                        tone.bar,
                        escape_html(title),
                        sub_html,
                        badge_html
                    )
                }
                "Grid" => {
                    let cols = args.first().and_then(|v| v.as_i64()).unwrap_or(4);
                    let children = args
                        .get(1)
                        .and_then(|v| v.as_array())
                        .cloned()
                        .unwrap_or_else(|| args.iter().skip(1).cloned().collect());
                    let grid_cols_cls = match cols {
                        2 => "grid-cols-1 sm:grid-cols-2",
                        3 => "grid-cols-1 sm:grid-cols-3",
                        _ => "grid-cols-2 sm:grid-cols-4",
                    };
                    let inner = children
                        .iter()
                        .map(|c| render_node_to_html(c, opts))
                        .collect::<Vec<_>>()
                        .join("\n");
                    format!(
                        "<div class=\"grid {grid_cols_cls} gap-2.5\" data-openui-component=\"Grid\">\n        {inner}\n      </div>"
                    )
                }
                "Kpi" => {
                    let label = args.first().unwrap_or(&Value::Null);
                    let value = args.get(1).unwrap_or(&Value::Null);
                    let subtext = args.get(2).unwrap_or(&Value::Null);
                    let tone_name = args.get(3).and_then(|v| v.as_str()).unwrap_or("neutral");
                    let tone = tone_classes(tone_name);
                    let sub_str = escape_html(subtext);
                    let sub_html = if !sub_str.is_empty() {
                        format!(
                            "<div class=\"text-xs text-[var(--muted-foreground)]\">{}</div>",
                            sub_str
                        )
                    } else {
                        String::new()
                    };
                    let bar_html = if let Some(pct) = args.get(4).and_then(|v| v.as_f64()) {
                        let clamped = pct.clamp(0.0, 100.0);
                        format!(
                            "<div class=\"w-full bg-[var(--border)] h-1.5 rounded-full mt-1 overflow-hidden\"><div class=\"{} h-full rounded-full\" style=\"width: {}%\"></div></div>",
                            tone.bar, clamped
                        )
                    } else {
                        String::new()
                    };
                    format!(
                        "<div class=\"bg-[var(--background)] border border-[var(--border)] rounded-lg p-2.5 space-y-0.5\" data-openui-component=\"Kpi\">\n        <div class=\"text-xs text-[var(--muted-foreground)]\">{}</div>\n        <div class=\"text-sm font-bold {}\">{}</div>\n        {}\n        {}\n      </div>",
                        escape_html(label),
                        tone.text,
                        escape_html(value),
                        sub_html,
                        bar_html
                    )
                }
                "Table" => {
                    let raw_cols = args
                        .first()
                        .and_then(|v| v.as_array())
                        .cloned()
                        .unwrap_or_else(|| args.clone());
                    let cols: Vec<&Value> = raw_cols
                        .iter()
                        .filter(|c| c.get("$component").and_then(|v| v.as_str()) == Some("Col"))
                        .collect();
                    let headers: Vec<String> = cols
                        .iter()
                        .map(|c| {
                            c.get("args")
                                .and_then(|a| a.as_array())
                                .and_then(|a| a.first())
                                .map(escape_html)
                                .unwrap_or_default()
                        })
                        .collect();
                    let col_arrays: Vec<Vec<Value>> = cols
                        .iter()
                        .map(|c| {
                            let second = c
                                .get("args")
                                .and_then(|a| a.as_array())
                                .and_then(|a| a.get(1));
                            match second {
                                Some(Value::Array(arr)) => arr.clone(),
                                Some(other) => vec![other.clone()],
                                None => vec![Value::String(String::new())],
                            }
                        })
                        .collect();
                    let row_count = col_arrays.iter().map(|a| a.len()).max().unwrap_or(0);
                    let th_html = headers
                        .iter()
                        .map(|h| {
                            format!(
                                "<th class=\"py-2 px-3 font-medium text-xs text-[var(--muted-foreground)]\">{h}</th>"
                            )
                        })
                        .collect::<Vec<_>>()
                        .join("");
                    let mut rows_html = Vec::new();
                    for r in 0..row_count {
                        let tds = col_arrays
                            .iter()
                            .enumerate()
                            .map(|(c_idx, arr)| {
                                let cell_val = arr.get(r).unwrap_or(&Value::Null);
                                let cell_raw = match cell_val {
                                    Value::Null => String::new(),
                                    Value::String(s) => s.clone(),
                                    other => other.to_string(),
                                };
                                let lower = cell_raw.to_ascii_lowercase();
                                let tone_match = if cell_raw.starts_with('✓')
                                    || lower.contains("healthy")
                                    || lower.contains("pass")
                                    || lower.contains("synced")
                                {
                                    "text-emerald-500 font-semibold"
                                } else if cell_raw.starts_with('✗')
                                    || lower.contains("fail")
                                    || lower.contains("degraded")
                                {
                                    "text-rose-500 font-semibold"
                                } else if cell_raw.starts_with('•')
                                    || lower.contains("tracked")
                                    || lower.contains("pending")
                                {
                                    "text-amber-500 font-semibold"
                                } else if c_idx == 0 {
                                    "font-medium text-[var(--foreground)]"
                                } else {
                                    "text-[var(--muted-foreground)]"
                                };
                                format!(
                                    "<td class=\"py-2 px-3 text-xs {tone_match}\">{}</td>",
                                    escape_html_str(&cell_raw)
                                )
                            })
                            .collect::<Vec<_>>()
                            .join("");
                        rows_html.push(format!("<tr>{tds}</tr>"));
                    }
                    format!(
                        "<div class=\"bg-[var(--background)] border border-[var(--border)] rounded-lg overflow-x-auto\" data-openui-component=\"Table\">\n        <table class=\"w-full text-left border-collapse text-xs\">\n          <thead>\n            <tr class=\"border-b border-[var(--border)] bg-[var(--card)]\">{th_html}</tr>\n          </thead>\n          <tbody class=\"divide-y divide-[var(--border)]\">\n            {}\n          </tbody>\n        </table>\n      </div>",
                        rows_html.join("\n")
                    )
                }
                "Badge" => {
                    let text = args.first().unwrap_or(&Value::Null);
                    let tone_name = args.get(1).and_then(|v| v.as_str()).unwrap_or("neutral");
                    let tone = tone_classes(tone_name);
                    format!(
                        "<span class=\"inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium {} {} border {}\" data-openui-component=\"Badge\">{}</span>",
                        tone.bg,
                        tone.text,
                        tone.border,
                        escape_html(text)
                    )
                }
                "TextContent" => {
                    let text = args.first().unwrap_or(&Value::Null);
                    let variant = args.get(1).and_then(|v| v.as_str()).unwrap_or("body");
                    let cls = match variant {
                        "large-heavy" => "text-sm font-bold text-[var(--foreground)]",
                        "muted" => "text-xs text-[var(--muted-foreground)]",
                        _ => "text-xs text-[var(--foreground)]",
                    };
                    format!(
                        "<div class=\"{cls}\" data-openui-component=\"TextContent\">{}</div>",
                        escape_html(text)
                    )
                }
                _ => {
                    let children = args
                        .first()
                        .and_then(|v| v.as_array())
                        .cloned()
                        .unwrap_or_else(|| args.clone());
                    let inner = children
                        .iter()
                        .map(|c| render_node_to_html(c, opts))
                        .collect::<Vec<_>>()
                        .join("\n");
                    format!(
                        "<div class=\"space-y-2\" data-openui-component=\"{}\">\n        {inner}\n      </div>",
                        escape_html_str(name)
                    )
                }
            }
        }
    }
}

pub fn render_openui_fragment(dsl_source: &str, data: &Value, opts: &RenderOptions) -> String {
    let parsed = parse_openui_lang(dsl_source, data);
    let mut render_opts = opts.clone();
    render_opts.dsl_source = Some(dsl_source.to_string());
    let body_html = render_node_to_html(&parsed.root, &render_opts);
    format!(
        "{body_html}\n<script>\nwindow.__openuiSwitchTab = window.__openuiSwitchTab || function(prefix, activeIdx) {{\n  var i = 0;\n  while (true) {{\n    var btn = document.getElementById(prefix + '-tab-btn-' + i);\n    var pane = document.getElementById(prefix + '-tab-pane-' + i);\n    if (!btn || !pane) break;\n    if (i === activeIdx) {{\n      pane.classList.remove('hidden');\n      btn.classList.add('border-blue-500', 'font-semibold', 'text-[var(--foreground)]');\n      btn.classList.remove('border-transparent', 'font-medium', 'text-[var(--muted-foreground)]');\n    }} else {{\n      pane.classList.add('hidden');\n      btn.classList.remove('border-blue-500', 'font-semibold', 'text-[var(--foreground)]');\n      btn.classList.add('border-transparent', 'font-medium', 'text-[var(--muted-foreground)]');\n    }}\n    i++;\n  }}\n}};\n</script>"
    )
}

pub fn compile_to_html(dsl_source: &str, data: &Value, opts: &RenderOptions) -> String {
    let fragment = render_openui_fragment(dsl_source, data, opts);
    let footer_html = if !opts.footer.is_empty() {
        format!(
            "<div class=\"pt-2 border-t border-[var(--border)] text-xs text-[var(--muted-foreground)] flex items-center justify-between\">{}</div>",
            escape_html_str(&opts.footer)
        )
    } else {
        String::new()
    };
    let title = if opts.title.is_empty() {
        "OpenUI Dashboard"
    } else {
        opts.title.as_str()
    };
    format!(
        "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n  <meta charset=\"UTF-8\">\n  <title>{}</title>\n  <script src=\"https://www.gstatic.com/antigravity/web/dev/tailwindcss.min.js\"></script>\n</head>\n<body class=\"bg-transparent text-[var(--foreground)] antialiased p-3 text-xs\">\n  {fragment}\n  {footer_html}\n</body>\n</html>\n",
        escape_html_str(title)
    )
}

fn call(name: &str, args: &[Value]) -> String {
    let inner = args
        .iter()
        .map(openui_literal)
        .collect::<Vec<_>>()
        .join(", ");
    format!("{name}({inner})")
}

fn list(items: &[String], indent: &str) -> String {
    if items.is_empty() {
        "[]".to_string()
    } else {
        let joined = items
            .iter()
            .map(|item| format!("{indent}  {item}"))
            .collect::<Vec<_>>()
            .join(",\n");
        format!("[\n{joined}\n{indent}]")
    }
}

fn as_num(val: Option<&Value>) -> i64 {
    match val {
        Some(Value::Number(n)) => n
            .as_i64()
            .or_else(|| n.as_f64().map(|f| f as i64))
            .unwrap_or(0),
        Some(Value::String(s)) => s.parse::<i64>().unwrap_or(0),
        _ => 0,
    }
}

fn is_truthy(val: Option<&Value>) -> bool {
    match val {
        None | Some(Value::Null) => false,
        Some(Value::Bool(b)) => *b,
        Some(Value::Number(n)) => n.as_f64().is_some_and(|f| f != 0.0 && f.is_finite()),
        Some(Value::String(s)) => !s.is_empty(),
        Some(Value::Array(_)) | Some(Value::Object(_)) => true,
    }
}

fn failing_count(watch: &Value) -> i64 {
    if let Some(arr) = watch.get("failing").and_then(|v| v.as_array()) {
        return arr.len() as i64;
    }
    if let Some(arr) = watch.get("failingChecks").and_then(|v| v.as_array()) {
        return arr.len() as i64;
    }
    as_num(watch.get("counts").and_then(|c| c.get("fail")))
}

fn watch_status(watch: &Value) -> String {
    if is_truthy(watch.get("closed")) {
        let state = watch
            .get("prState")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_ascii_uppercase();
        return if state == "MERGED" {
            "✓ merged".to_string()
        } else {
            "closed".to_string()
        };
    }
    if is_truthy(watch.get("lastError")) {
        return "✗ unreadable".to_string();
    }
    let failing = failing_count(watch);
    if failing > 0 {
        return format!("✗ {failing} failing");
    }
    if is_truthy(watch.get("conflicting")) {
        return "✗ conflict".to_string();
    }
    if is_truthy(watch.get("queued")) {
        let at = as_num(watch.get("queuePosition"));
        return if at > 0 {
            format!("• queued #{at}")
        } else {
            "• queued".to_string()
        };
    }
    if as_num(watch.get("counts").and_then(|c| c.get("pending"))) > 0 {
        return "• running".to_string();
    }
    if is_truthy(watch.get("isDraft")) {
        return "draft".to_string();
    }
    if !is_truthy(watch.get("counts")) {
        return "• not read yet".to_string();
    }
    "✓ green".to_string()
}

fn watch_checks(watch: &Value) -> String {
    let Some(c) = watch.get("counts").filter(|v| is_truthy(Some(*v))) else {
        return String::new();
    };
    format!(
        "{} ok · {} red · {} running",
        as_num(c.get("pass")),
        as_num(c.get("fail")),
        as_num(c.get("pending"))
    )
}

pub fn to_openui_lang(state: Option<&Value>) -> String {
    let empty = json!({});
    let s = match state {
        Some(v) if v.is_object() => v,
        _ => &empty,
    };
    let mut watches: Vec<&Value> = s
        .get("watches")
        .and_then(|v| v.as_array())
        .map(|arr| arr.iter().filter(|w| w.is_object()).collect())
        .unwrap_or_default();

    watches.sort_by(|a, b| {
        let a_closed = is_truthy(a.get("closed"));
        let b_closed = is_truthy(b.get("closed"));
        if a_closed == b_closed {
            let a_at = as_num(a.get("addedAt"));
            let b_at = as_num(b.get("addedAt"));
            b_at.cmp(&a_at)
        } else if a_closed {
            std::cmp::Ordering::Greater
        } else {
            std::cmp::Ordering::Less
        }
    });

    let open: Vec<&&Value> = watches
        .iter()
        .filter(|w| !is_truthy(w.get("closed")))
        .collect();
    let failing = open.iter().filter(|w| failing_count(w) > 0).count();
    let running = open
        .iter()
        .filter(|w| as_num(w.get("counts").and_then(|c| c.get("pending"))) > 0)
        .count();
    let queued = open.iter().filter(|w| is_truthy(w.get("queued"))).count();
    let flaky: Vec<&Value> = s
        .get("flaky")
        .and_then(|v| v.as_array())
        .map(|arr| arr.iter().filter(|f| f.is_object()).collect())
        .unwrap_or_default();
    let pace = s.get("pace").filter(|v| v.is_object()).unwrap_or(&empty);
    let reviews = s
        .get("lists")
        .and_then(|l| l.get("reviews"))
        .and_then(|r| r.get("items"))
        .and_then(|v| v.as_array())
        .map(|a| a.len())
        .unwrap_or(0);

    let (header_status, header_tone) = if failing > 0 {
        (format!("{failing} failing"), "danger")
    } else if running > 0 {
        (format!("{running} running"), "info")
    } else if !open.is_empty() {
        ("all green".to_string(), "success")
    } else {
        ("idle".to_string(), "neutral")
    };

    let flaky_top = if let Some(first) = flaky.first() {
        let name = first.get("name").and_then(|v| v.as_str()).unwrap_or("?");
        let count = as_num(first.get("count"));
        format!("top: {name} ×{count}")
    } else {
        "none recorded".to_string()
    };

    let interval = pace.get("intervalSeconds").and_then(|v| v.as_f64());
    let pace_value = match interval {
        Some(n) if n.is_finite() && n > 0.0 => {
            if n.fract() == 0.0 {
                format!("{}s", n as i64)
            } else {
                format!("{n}s")
            }
        }
        _ => "—".to_string(),
    };
    let mut pace_parts = Vec::new();
    if let Some(m) = pace
        .get("mode")
        .and_then(|v| v.as_str())
        .filter(|x| !x.is_empty())
    {
        pace_parts.push(m);
    }
    if let Some(r) = pace
        .get("reason")
        .and_then(|v| v.as_str())
        .filter(|x| !x.is_empty())
    {
        pace_parts.push(r);
    }
    let pace_note = pace_parts.join(" · ");

    let kpis = vec![
        call(
            "Kpi",
            &[
                json!("Watched PRs"),
                json!(watches.len()),
                json!(format!(
                    "{} open · {queued} queued · {reviews} to review",
                    open.len()
                )),
                json!("info"),
            ],
        ),
        call(
            "Kpi",
            &[
                json!("Failing"),
                json!(failing),
                json!(if failing > 0 {
                    "PRs with red checks"
                } else {
                    "nothing red"
                }),
                json!(if failing > 0 { "danger" } else { "success" }),
            ],
        ),
        call(
            "Kpi",
            &[
                json!("Flaky checks"),
                json!(flaky.len()),
                json!(flaky_top),
                json!(if !flaky.is_empty() {
                    "warning"
                } else {
                    "neutral"
                }),
            ],
        ),
        call(
            "Kpi",
            &[
                json!("Pace"),
                json!(pace_value),
                json!(pace_note),
                json!(
                    if pace.get("mode").and_then(|v| v.as_str()) == Some("fast") {
                        "info"
                    } else {
                        "neutral"
                    }
                ),
            ],
        ),
    ];

    let column = |title: &str, cells: &[Value]| -> String {
        let lit_cells: Vec<String> = cells.iter().map(openui_literal).collect();
        format!(
            "Col({}, {})",
            openui_literal(&Value::String(title.to_string())),
            list(&lit_cells, "    ")
        )
    };

    let pr_labels: Vec<Value> = watches
        .iter()
        .map(|w| {
            let repo = w.get("repo").and_then(|v| v.as_str()).unwrap_or("");
            if !repo.is_empty() && w.get("number").is_some() && !w["number"].is_null() {
                let num_str = match &w["number"] {
                    Value::String(s) => s.clone(),
                    other => other.to_string(),
                };
                Value::String(format!("{repo}#{num_str}"))
            } else {
                let key = w.get("key").and_then(|v| v.as_str()).unwrap_or("?");
                Value::String(key.to_string())
            }
        })
        .collect();
    let titles: Vec<Value> = watches
        .iter()
        .map(|w| {
            Value::String(
                w.get("title")
                    .and_then(|v| v.as_str())
                    .unwrap_or("")
                    .to_string(),
            )
        })
        .collect();
    let statuses: Vec<Value> = watches
        .iter()
        .map(|w| Value::String(watch_status(w)))
        .collect();
    let checks: Vec<Value> = watches
        .iter()
        .map(|w| Value::String(watch_checks(w)))
        .collect();

    let columns = vec![
        column("PR", &pr_labels),
        column("Title", &titles),
        column("Status", &statuses),
        column("Checks", &checks),
    ];

    let version = match s.get("version") {
        Some(Value::String(v)) if !v.is_empty() => format!("v{v}"),
        Some(Value::Number(n)) => format!("v{n}"),
        _ => String::new(),
    };

    let header_str = call(
        "Header",
        &[
            json!("GH Watch"),
            json!(version),
            json!(header_status),
            json!(header_tone),
        ],
    );
    let grid_str = format!("Grid(4, {})", list(&kpis, "  "));
    let table_str = format!("Table({})", list(&columns, "  "));

    format!(
        "# gh-watch state as OpenUI Lang v0.5\nroot = Card([\n  {header_str},\n  {grid_str},\n  {table_str}\n])\n"
    )
}
