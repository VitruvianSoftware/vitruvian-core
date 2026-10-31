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

use std::collections::{BTreeSet, HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::process::Command;

pub const BROWSER_GLOBALS: &[&str] = &[
    "window",
    "document",
    "navigator",
    "HTMLElement",
    "HTMLCanvasElement",
    "Image",
    "Audio",
    "localStorage",
    "sessionStorage",
    "requestAnimationFrame",
    "cancelAnimationFrame",
    "getComputedStyle",
];

pub const NODE_BUILTINS: &[&str] = &[
    "assert",
    "assert/strict",
    "async_hooks",
    "buffer",
    "child_process",
    "cluster",
    "console",
    "constants",
    "crypto",
    "dgram",
    "diagnostics_channel",
    "dns",
    "dns/promises",
    "domain",
    "events",
    "fs",
    "fs/promises",
    "http",
    "http2",
    "https",
    "inspector",
    "inspector/promises",
    "module",
    "net",
    "os",
    "path",
    "path/posix",
    "path/win32",
    "perf_hooks",
    "process",
    "punycode",
    "querystring",
    "readline",
    "readline/promises",
    "repl",
    "stream",
    "stream/consumers",
    "stream/promises",
    "stream/web",
    "string_decoder",
    "sys",
    "test",
    "timers",
    "timers/promises",
    "tls",
    "trace_events",
    "tty",
    "url",
    "util",
    "util/types",
    "v8",
    "vm",
    "wasi",
    "worker_threads",
    "zlib",
];

pub fn is_node_builtin(specifier: &str) -> bool {
    if specifier.starts_with("node:") {
        return true;
    }
    NODE_BUILTINS.contains(&specifier)
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ModuleAnalysis {
    pub imports: Vec<String>,
    pub browser: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DirectionSummary {
    pub modules: usize,
    pub portable_entries: usize,
}

#[derive(Debug, Clone, PartialEq, Eq)]
enum Token<'a> {
    Ident(&'a str),
    StringLit(String),
    TemplateChunk,
    Punct(&'a str),
    RegexLit,
}

fn is_ident_start(b: u8) -> bool {
    b.is_ascii_alphabetic() || b == b'_' || b == b'$' || b >= 0x80
}

fn is_ident_continue(b: u8) -> bool {
    b.is_ascii_alphanumeric() || b == b'_' || b == b'$' || b >= 0x80
}

fn can_precede_regex(prev: Option<&Token<'_>>) -> bool {
    match prev {
        None => true,
        Some(Token::Punct(p)) => !matches!(*p, ")" | "]"),
        Some(Token::Ident(id)) => matches!(
            *id,
            "return"
                | "throw"
                | "case"
                | "in"
                | "of"
                | "typeof"
                | "void"
                | "delete"
                | "await"
                | "yield"
                | "new"
                | "else"
                | "do"
                | "instanceof"
        ),
        _ => false,
    }
}

fn tokenize_js(source: &str) -> Vec<Token<'_>> {
    let bytes = source.as_bytes();
    let n = bytes.len();
    let mut i = 0;
    let mut tokens = Vec::with_capacity(n / 6);
    let mut template_brace_stack: Vec<usize> = Vec::new();

    // Skip shebang if present
    if source.starts_with("#!") {
        while i < n && bytes[i] != b'\n' {
            i += 1;
        }
    }

    while i < n {
        let b = bytes[i];

        if b.is_ascii_whitespace() {
            i += 1;
            continue;
        }

        // Line comment
        if b == b'/' && i + 1 < n && bytes[i + 1] == b'/' {
            i += 2;
            while i < n && bytes[i] != b'\n' {
                i += 1;
            }
            continue;
        }

        // Block comment
        if b == b'/' && i + 1 < n && bytes[i + 1] == b'*' {
            i += 2;
            while i + 1 < n && !(bytes[i] == b'*' && bytes[i + 1] == b'/') {
                i += 1;
            }
            i = (i + 2).min(n);
            continue;
        }

        // String literal
        if b == b'\'' || b == b'"' {
            let quote = b;
            i += 1;
            let mut val = String::new();
            while i < n && bytes[i] != quote {
                if bytes[i] == b'\\' && i + 1 < n {
                    i += 1;
                    val.push(bytes[i] as char);
                } else {
                    val.push(bytes[i] as char);
                }
                i += 1;
            }
            if i < n {
                i += 1;
            }
            tokens.push(Token::StringLit(val));
            continue;
        }

        // Template literal start or continuation
        if b == b'`' {
            i += 1;
            tokens.push(Token::TemplateChunk);
            while i < n {
                if bytes[i] == b'\\' {
                    i = (i + 2).min(n);
                } else if bytes[i] == b'`' {
                    i += 1;
                    break;
                } else if bytes[i] == b'$' && i + 1 < n && bytes[i + 1] == b'{' {
                    i += 2;
                    template_brace_stack.push(0);
                    tokens.push(Token::Punct("${"));
                    break;
                } else {
                    i += 1;
                }
            }
            continue;
        }

        // Closing brace that may resume a template literal
        if b == b'}' {
            if let Some(depth) = template_brace_stack.last_mut() {
                if *depth == 0 {
                    template_brace_stack.pop();
                    tokens.push(Token::Punct("}"));
                    i += 1;
                    tokens.push(Token::TemplateChunk);
                    while i < n {
                        if bytes[i] == b'\\' {
                            i = (i + 2).min(n);
                        } else if bytes[i] == b'`' {
                            i += 1;
                            break;
                        } else if bytes[i] == b'$' && i + 1 < n && bytes[i + 1] == b'{' {
                            i += 2;
                            template_brace_stack.push(0);
                            tokens.push(Token::Punct("${"));
                            break;
                        } else {
                            i += 1;
                        }
                    }
                    continue;
                } else {
                    *depth -= 1;
                }
            }
            tokens.push(Token::Punct("}"));
            i += 1;
            continue;
        }

        if b == b'{' {
            if let Some(depth) = template_brace_stack.last_mut() {
                *depth += 1;
            }
            tokens.push(Token::Punct("{"));
            i += 1;
            continue;
        }

        // Regex literal
        if b == b'/' && can_precede_regex(tokens.last()) {
            i += 1;
            let mut in_class = false;
            while i < n {
                if bytes[i] == b'\\' {
                    i = (i + 2).min(n);
                } else if bytes[i] == b'[' {
                    in_class = true;
                    i += 1;
                } else if bytes[i] == b']' {
                    in_class = false;
                    i += 1;
                } else if bytes[i] == b'/' && !in_class {
                    i += 1;
                    while i < n && bytes[i].is_ascii_alphabetic() {
                        i += 1;
                    }
                    break;
                } else if bytes[i] == b'\n' {
                    break;
                } else {
                    i += 1;
                }
            }
            tokens.push(Token::RegexLit);
            continue;
        }

        // Identifier
        if is_ident_start(b) {
            let start = i;
            i += 1;
            while i < n && is_ident_continue(bytes[i]) {
                i += 1;
            }
            // Advance to UTF-8 char boundary if needed
            while i < n && !source.is_char_boundary(i) {
                i += 1;
            }
            tokens.push(Token::Ident(&source[start..i]));
            continue;
        }

        // Numbers (skip cleanly so digits/dots don't look like identifiers)
        if b.is_ascii_digit() {
            i += 1;
            while i < n
                && (bytes[i].is_ascii_alphanumeric() || bytes[i] == b'.' || bytes[i] == b'_')
            {
                i += 1;
            }
            continue;
        }

        // Multi-char punctuation
        if i + 1 < n {
            let two = &bytes[i..i + 2];
            if two == b"?."
                || two == b"=>"
                || two == b"=="
                || two == b"!="
                || two == b"&&"
                || two == b"||"
            {
                tokens.push(Token::Punct(&source[i..i + 2]));
                i += 2;
                continue;
            }
        }

        if b < 0x80 {
            tokens.push(Token::Punct(&source[i..i + 1]));
            i += 1;
        } else {
            let ch_len = source[i..].chars().next().map(|c| c.len_utf8()).unwrap_or(1);
            tokens.push(Token::Punct(&source[i..i + ch_len]));
            i += ch_len;
        }
    }

    tokens
}

fn mark_params_in_parens(
    tokens: &[Token<'_>],
    open_paren: usize,
    excluded: &mut [bool],
) -> Option<usize> {
    if tokens.get(open_paren) != Some(&Token::Punct("(")) {
        return None;
    }
    let mut depth_paren = 0usize;
    let mut depth_brace = 0usize;
    let mut depth_bracket = 0usize;
    let mut in_default_expr = false;

    for idx in open_paren..tokens.len() {
        match &tokens[idx] {
            Token::Punct(p) => match *p {
                "(" => depth_paren += 1,
                ")" => {
                    depth_paren = depth_paren.saturating_sub(1);
                    if depth_paren == 0 {
                        return Some(idx);
                    }
                }
                "{" => depth_brace += 1,
                "}" => depth_brace = depth_brace.saturating_sub(1),
                "[" => depth_bracket += 1,
                "]" => depth_bracket = depth_bracket.saturating_sub(1),
                "=" if depth_paren == 1 && depth_brace == 0 && depth_bracket == 0 => {
                    in_default_expr = true;
                }
                "," if depth_paren == 1 && depth_brace == 0 && depth_bracket == 0 => {
                    in_default_expr = false;
                }
                _ => {}
            },
            Token::Ident(_) if !in_default_expr && depth_paren == 1 => {
                excluded[idx] = true;
            }
            _ => {}
        }
    }
    None
}

/// Inspect literal module dependencies and browser-platform references without executing code.
/// Port of upstream's `analyzeModule(source)` (`scripts/module-analysis.mjs`, not in this copy).
pub fn analyze_module(source: &str) -> Result<ModuleAnalysis, String> {
    let tokens = tokenize_js(source);
    let len = tokens.len();
    let mut imports = Vec::new();
    let mut excluded_ident = vec![false; len];

    let mut i = 0;
    while i < len {
        match &tokens[i] {
            Token::Ident(id) if *id == "import" => {
                let prev_is_dot = i > 0
                    && matches!(
                        &tokens[i - 1],
                        Token::Punct(p) if *p == "." || *p == "?."
                    );
                if !prev_is_dot {
                    // import.meta
                    if matches!(tokens.get(i + 1), Some(Token::Punct(p)) if *p == ".") {
                        i += 2;
                        continue;
                    }
                    // Dynamic import(...)
                    if matches!(tokens.get(i + 1), Some(Token::Punct(p)) if *p == "(") {
                        match (tokens.get(i + 2), tokens.get(i + 3)) {
                            (Some(Token::StringLit(spec)), Some(Token::Punct(close)))
                                if *close == ")" || *close == "," =>
                            {
                                imports.push(spec.clone());
                                i += 3;
                                continue;
                            }
                            _ => {
                                return Err(
                                    "Computed module imports are not allowed in runtime code"
                                        .to_string(),
                                );
                            }
                        }
                    }
                    // Side-effect import 'spec'
                    if let Some(Token::StringLit(spec)) = tokens.get(i + 1) {
                        imports.push(spec.clone());
                        i += 2;
                        continue;
                    }
                    // Static import ... from 'spec'
                    let mut j = i + 1;
                    while j < len {
                        if matches!(&tokens[j], Token::Ident(_)) {
                            excluded_ident[j] = true;
                        }
                        if matches!(&tokens[j], Token::Ident(w) if *w == "from") {
                            if let Some(Token::StringLit(spec)) = tokens.get(j + 1) {
                                imports.push(spec.clone());
                                j += 2;
                                break;
                            } else {
                                return Err(
                                    "Computed module imports are not allowed in runtime code"
                                        .to_string(),
                                );
                            }
                        }
                        if matches!(&tokens[j], Token::Punct(p) if *p == ";") {
                            break;
                        }
                        j += 1;
                    }
                    i = j;
                    continue;
                }
            }
            Token::Ident(id) if *id == "export" => {
                // export * from 'spec', export * as ns from 'spec', export { ... } from 'spec'
                if matches!(tokens.get(i + 1), Some(Token::Punct(p)) if *p == "*" || *p == "{") {
                    let mut j = i + 1;
                    if matches!(tokens.get(j), Some(Token::Punct(p)) if *p == "{") {
                        let mut depth = 0usize;
                        while j < len {
                            if matches!(&tokens[j], Token::Punct(p) if *p == "{") {
                                depth += 1;
                            } else if matches!(&tokens[j], Token::Punct(p) if *p == "}") {
                                depth = depth.saturating_sub(1);
                                if depth == 0 {
                                    j += 1;
                                    break;
                                }
                            }
                            j += 1;
                        }
                    } else {
                        // `*` or `* as ns`
                        j += 1;
                        if matches!(tokens.get(j), Some(Token::Ident(w)) if *w == "as") {
                            if j + 1 < len {
                                excluded_ident[j + 1] = true;
                            }
                            j += 2;
                        }
                    }
                    if matches!(tokens.get(j), Some(Token::Ident(w)) if *w == "from") {
                        if let Some(Token::StringLit(spec)) = tokens.get(j + 1) {
                            imports.push(spec.clone());
                            i = j + 2;
                            continue;
                        }
                    }
                }
            }
            Token::Ident(id) if *id == "require" => {
                let prev_is_dot_or_decl = i > 0
                    && matches!(
                        &tokens[i - 1],
                        Token::Punct(p) if *p == "." || *p == "?."
                    )
                    || (i > 0
                        && matches!(
                            &tokens[i - 1],
                            Token::Ident(w) if *w == "function" || *w == "const" || *w == "let" || *w == "var"
                        ));
                if !prev_is_dot_or_decl
                    && matches!(tokens.get(i + 1), Some(Token::Punct(p)) if *p == "(")
                {
                    return Err("Runtime modules must use ES imports".to_string());
                }
            }
            Token::Ident(id) if *id == "const" || *id == "let" || *id == "var" => {
                if i + 1 < len {
                    match &tokens[i + 1] {
                        Token::Ident(_) => {
                            excluded_ident[i + 1] = true;
                        }
                        Token::Punct(p) if *p == "{" || *p == "[" => {
                            let open = *p;
                            let close = if open == "{" { "}" } else { "]" };
                            let mut depth = 0usize;
                            let mut in_default = false;
                            let mut k = i + 1;
                            while k < len {
                                match &tokens[k] {
                                    Token::Punct(pk) if *pk == open => depth += 1,
                                    Token::Punct(pk) if *pk == close => {
                                        depth = depth.saturating_sub(1);
                                        if depth == 0 {
                                            break;
                                        }
                                    }
                                    Token::Punct(pk) if *pk == "=" && depth == 1 => {
                                        in_default = true;
                                    }
                                    Token::Punct(pk) if *pk == "," && depth == 1 => {
                                        in_default = false;
                                    }
                                    Token::Ident(_) if !in_default && depth == 1 => {
                                        excluded_ident[k] = true;
                                    }
                                    _ => {}
                                }
                                k += 1;
                            }
                        }
                        _ => {}
                    }
                }
            }
            Token::Ident(id) if *id == "function" || *id == "class" => {
                let mut k = i + 1;
                if matches!(tokens.get(k), Some(Token::Punct(p)) if *p == "*") {
                    k += 1;
                }
                if matches!(tokens.get(k), Some(Token::Ident(_))) {
                    excluded_ident[k] = true;
                    k += 1;
                }
                if *id == "function" {
                    let _ = mark_params_in_parens(&tokens, k, &mut excluded_ident);
                }
            }
            Token::Punct(p) if *p == "=>" => {
                if i > 0 {
                    match &tokens[i - 1] {
                        Token::Ident(_) => {
                            excluded_ident[i - 1] = true;
                        }
                        Token::Punct(close) if *close == ")" => {
                            let mut depth = 0usize;
                            let mut k = i - 1;
                            loop {
                                match &tokens[k] {
                                    Token::Punct(pk) if *pk == ")" => depth += 1,
                                    Token::Punct(pk) if *pk == "(" => {
                                        depth = depth.saturating_sub(1);
                                        if depth == 0 {
                                            let _ = mark_params_in_parens(
                                                &tokens,
                                                k,
                                                &mut excluded_ident,
                                            );
                                            break;
                                        }
                                    }
                                    _ => {}
                                }
                                if k == 0 {
                                    break;
                                }
                                k -= 1;
                            }
                        }
                        _ => {}
                    }
                }
            }
            _ => {}
        }
        i += 1;
    }

    // Also mark method definitions `ident(...) {`
    for idx in 0..len {
        if let Token::Ident(name) = &tokens[idx] {
            if !matches!(
                *name,
                "if" | "for" | "while" | "switch" | "catch" | "with" | "function" | "return"
            ) && matches!(tokens.get(idx + 1), Some(Token::Punct(p)) if *p == "(")
            {
                let prev_is_method_ctx = idx > 0
                    && matches!(
                        &tokens[idx - 1],
                        Token::Punct(p) if *p == "{" || *p == "," || *p == "}" || *p == ";"
                    )
                    || (idx > 0
                        && matches!(
                            &tokens[idx - 1],
                            Token::Ident(w) if *w == "async" || *w == "get" || *w == "set" || *w == "static"
                        ));
                if prev_is_method_ctx {
                    if let Some(close_paren) =
                        mark_params_in_parens(&tokens, idx + 1, &mut excluded_ident)
                    {
                        if matches!(tokens.get(close_paren + 1), Some(Token::Punct(p)) if *p == "{")
                        {
                            excluded_ident[idx] = true;
                        }
                    }
                }
            }
        }
    }

    let mut browser = Vec::new();
    let mut browser_seen = HashSet::new();
    let mut add_browser = |name: &str| {
        if BROWSER_GLOBALS.contains(&name) && browser_seen.insert(name.to_string()) {
            browser.push(name.to_string());
        }
    };

    for idx in 0..len {
        // Check `globalThis.<name>`, `self.<name>`, `globalThis['<name>']`, `self['<name>']`
        if let Token::Ident(obj) = &tokens[idx] {
            if *obj == "globalThis" || *obj == "self" {
                if let Some(Token::Punct(p)) = tokens.get(idx + 1) {
                    if *p == "." || *p == "?." {
                        if let Some(Token::Ident(prop)) = tokens.get(idx + 2) {
                            add_browser(prop);
                        }
                    } else if *p == "[" {
                        if let (Some(Token::StringLit(prop)), Some(Token::Punct(close))) =
                            (tokens.get(idx + 2), tokens.get(idx + 3))
                        {
                            if *close == "]" {
                                add_browser(prop);
                            }
                        }
                    }
                }
            }
        }

        if let Token::Ident(name) = &tokens[idx] {
            if !BROWSER_GLOBALS.contains(name) || excluded_ident[idx] {
                continue;
            }
            // Non-computed member property (`obj.window` or `obj?.window`)
            let is_member_prop = idx > 0
                && matches!(
                    &tokens[idx - 1],
                    Token::Punct(p) if *p == "." || *p == "?."
                );
            if is_member_prop {
                continue;
            }
            // Object property key (`{ document: 1 }`)
            let is_object_key = matches!(tokens.get(idx + 1), Some(Token::Punct(p)) if *p == ":")
                && !(idx > 0 && matches!(&tokens[idx - 1], Token::Punct(p) if *p == "?"));
            if is_object_key {
                continue;
            }

            add_browser(name);
        }
    }

    Ok(ModuleAnalysis { imports, browser })
}

pub fn is_code_file(file: &str) -> bool {
    file.ends_with(".js") || file.ends_with(".mjs") || file.ends_with(".cjs")
}

pub fn is_entry_file(file: &str) -> bool {
    file == "src/main.js" || file.starts_with("src/standalone/")
}

pub fn is_test_file(file: &str) -> bool {
    file.ends_with(".test.mjs")
        || file.starts_with("src/testSupport/")
        || file.starts_with("src/tooling/")
        || file == "src/overlays/worldOverlayAllocation.worker.mjs"
}

pub fn is_source_file(file: &str) -> bool {
    if file.starts_with("src/sources/") {
        return true;
    }
    if let Some(rest) = file.strip_prefix("src/layers/") {
        if let Some((_, tail)) = rest.split_once('/') {
            return matches!(tail, "source.js" | "bundledSource.js" | "flowSource.js");
        }
    }
    false
}

pub fn is_renderer_file(file: &str) -> bool {
    if file.starts_with("src/ui/")
        || file.starts_with("src/app/")
        || file.starts_with("src/standalone/")
        || file.starts_with("src/overlays/")
    {
        return true;
    }
    if let Some(rest) = file.strip_prefix("src/layers/") {
        if let Some((_, tail)) = rest.split_once('/') {
            return matches!(
                tail,
                "index.js"
                    | "rendering.js"
                    | "snapshotRenderer.js"
                    | "overlay.js"
                    | "presentation.js"
                    | "cards.js"
                    | "controls.js"
            );
        }
    }
    false
}

pub fn is_compatibility_edge(from: &str, to: &str) -> bool {
    from == "server/providers/local.js" && to == "server/standalone/key-setup.js"
}

pub fn is_portable_export(key: &str) -> bool {
    if key.starts_with("./sources/") || key.ends_with("/source") {
        return true;
    }
    if matches!(
        key,
        "./layers/flights/records"
            | "./layers/flights/ingestion"
            | "./layers/military/records"
            | "./layers/military/ingestion"
            | "./layers/vessels/records"
            | "./layers/vessels/ingestion"
            | "./director"
            | "./tools"
            | "./tools/mcp"
            | "./tools/services"
            | "./view"
            | "./voice/action-schemas"
            | "./voice/session"
            | "./data/lifecycle"
    ) {
        return true;
    }
    false
}

/// The keys of the JSON object at `path` inside `raw`, in document order.
///
/// `serde_json::Map` sorts its keys (this crate does not enable
/// `preserve_order`), but the Node checks these ports replace walked
/// `package.json#exports` and `scripts/package-boundaries.json` in file
/// order: that order decides the order of reports and which failure is named
/// first. Returns an empty list when `path` is not an object.
pub fn json_object_keys_in_order(raw: &str, path: &[&str]) -> Vec<String> {
    use serde::de::{DeserializeSeed, Deserializer, IgnoredAny, MapAccess, SeqAccess, Visitor};
    use std::fmt;

    struct Seek<'a> {
        path: &'a [&'a str],
    }

    impl<'de, 'a> DeserializeSeed<'de> for Seek<'a> {
        type Value = Option<Vec<String>>;
        fn deserialize<D: Deserializer<'de>>(self, d: D) -> Result<Self::Value, D::Error> {
            d.deserialize_any(self)
        }
    }

    impl<'de, 'a> Visitor<'de> for Seek<'a> {
        type Value = Option<Vec<String>>;
        fn expecting(&self, f: &mut fmt::Formatter) -> fmt::Result {
            f.write_str("any JSON value")
        }
        fn visit_map<A: MapAccess<'de>>(self, mut map: A) -> Result<Self::Value, A::Error> {
            let mut found = None;
            let mut keys = Vec::new();
            while let Some(key) = map.next_key::<String>()? {
                match self.path.split_first() {
                    Some((head, rest)) if found.is_none() && *head == key => {
                        found = map.next_value_seed(Seek { path: rest })?;
                    }
                    _ => {
                        map.next_value::<IgnoredAny>()?;
                    }
                }
                if self.path.is_empty() && !keys.contains(&key) {
                    keys.push(key);
                }
            }
            Ok(if self.path.is_empty() { Some(keys) } else { found })
        }
        fn visit_seq<A: SeqAccess<'de>>(self, mut seq: A) -> Result<Self::Value, A::Error> {
            while seq.next_element::<IgnoredAny>()?.is_some() {}
            Ok(None)
        }
        fn visit_bool<E>(self, _: bool) -> Result<Self::Value, E> {
            Ok(None)
        }
        fn visit_i64<E>(self, _: i64) -> Result<Self::Value, E> {
            Ok(None)
        }
        fn visit_u64<E>(self, _: u64) -> Result<Self::Value, E> {
            Ok(None)
        }
        fn visit_f64<E>(self, _: f64) -> Result<Self::Value, E> {
            Ok(None)
        }
        fn visit_str<E>(self, _: &str) -> Result<Self::Value, E> {
            Ok(None)
        }
        fn visit_unit<E>(self) -> Result<Self::Value, E> {
            Ok(None)
        }
    }

    let mut de = serde_json::Deserializer::from_str(raw);
    Seek { path }
        .deserialize(&mut de)
        .ok()
        .flatten()
        .unwrap_or_default()
}

fn walk_dir_rel_files(root: &Path, dir: &Path, out: &mut BTreeSet<String>) {
    let entries = match std::fs::read_dir(dir) {
        Ok(rd) => rd,
        Err(_) => return,
    };
    for entry in entries.flatten() {
        let p = entry.path();
        if p.is_dir() {
            walk_dir_rel_files(root, &p, out);
        } else if let Ok(rel) = p.strip_prefix(root) {
            let rel_str = rel.to_string_lossy().replace('\\', "/");
            out.insert(rel_str);
        }
    }
}

pub fn discover_repo_files(root: &Path, subdirs: &[&str]) -> Vec<String> {
    // `git ls-files` whenever `root` is inside a work tree (the app sits in the
    // monorepo, whose .git is at the repository root, not here), as the Node
    // check did; a directory walk only when git cannot answer (no repository,
    // e.g. a fixture or a sandbox outside the checkout).
    {
        let mut cmd = Command::new("git");
        cmd.arg("ls-files")
            .arg("-z")
            .arg("--cached")
            .arg("--others")
            .arg("--exclude-standard")
            .arg("--");
        for d in subdirs {
            cmd.arg(d);
        }
        cmd.current_dir(root);
        if let Ok(output) = cmd.output() {
            if output.status.success() {
                let text = String::from_utf8_lossy(&output.stdout);
                let mut set = BTreeSet::new();
                for part in text.split('\0') {
                    if !part.is_empty() {
                        set.insert(part.to_string());
                    }
                }
                return set.into_iter().collect();
            }
        }
    }

    let mut set = BTreeSet::new();
    for d in subdirs {
        let sub = root.join(d);
        if sub.is_dir() {
            walk_dir_rel_files(root, &sub, &mut set);
        }
    }
    set.into_iter().collect()
}

fn has_non_node_uri_scheme(specifier: &str) -> bool {
    if specifier.starts_with("node:") {
        return false;
    }
    if let Some(colon) = specifier.find(':') {
        return colon > 0
            && specifier[..colon]
                .bytes()
                .all(|b| b.is_ascii_alphabetic());
    }
    false
}

#[derive(Debug, Clone)]
struct LoadedModule {
    browser: Vec<String>,
    edges: Vec<String>,
    external: Vec<String>,
}

pub fn normalize_lexical_path(path: &Path) -> PathBuf {
    use std::path::Component;
    let mut out = PathBuf::new();
    for comp in path.components() {
        match comp {
            Component::CurDir => {}
            Component::ParentDir => {
                out.pop();
            }
            other => out.push(other.as_os_str()),
        }
    }
    out
}

pub fn cached_canonicalize(
    path: &Path,
    cache: &mut HashMap<PathBuf, Option<PathBuf>>,
) -> Option<PathBuf> {
    let key = normalize_lexical_path(path);
    if let Some(res) = cache.get(&key) {
        return res.clone();
    }
    let resolved = std::fs::canonicalize(path).ok();
    cache.insert(key, resolved.clone());
    resolved
}

fn seed_dir_non_symlink(dir: &Path, cache: &mut HashMap<PathBuf, Option<PathBuf>>) {
    let entries = match std::fs::read_dir(dir) {
        Ok(rd) => rd,
        Err(_) => return,
    };
    for entry in entries.flatten() {
        if let Ok(ft) = entry.file_type() {
            if ft.is_symlink() {
                continue;
            }
            let p = entry.path();
            if ft.is_dir() {
                seed_dir_non_symlink(&p, cache);
            } else if ft.is_file() {
                cache.insert(p.clone(), Some(p));
            }
        }
    }
}

pub fn seed_non_symlink_files(
    root: &Path,
    subdirs: &[&str],
    cache: &mut HashMap<PathBuf, Option<PathBuf>>,
) {
    for d in subdirs {
        let sub = root.join(d);
        if let Ok(meta) = std::fs::symlink_metadata(&sub) {
            if meta.is_dir() && !meta.file_type().is_symlink() {
                seed_dir_non_symlink(&sub, cache);
            }
        }
    }
}

/// Check every runtime file, plus transitive portable/source graphs, independently of bundler reachability.
/// Port of upstream's `checkImportDirections(root)` (`scripts/check-import-directions.mjs`, not in this copy).
pub fn check_import_directions(root_in: &Path) -> Result<DirectionSummary, String> {
    let root = std::fs::canonicalize(root_in)
        .map_err(|e| format!("Failed to resolve root {}: {}", root_in.display(), e))?;
    let pkg_raw = std::fs::read_to_string(root.join("package.json"))
        .map_err(|e| format!("Failed to read package.json: {}", e))?;
    let pkg: serde_json::Value =
        serde_json::from_str(&pkg_raw).map_err(|e| format!("Invalid package.json: {}", e))?;
    let pkg_name = pkg.get("name").and_then(|v| v.as_str()).unwrap_or("");
    let pkg_exports = pkg.get("exports").and_then(|v| v.as_object());

    let files: Vec<String> = discover_repo_files(&root, &["src", "server"])
        .into_iter()
        .filter(|file| is_code_file(file) && !is_test_file(file) && root.join(file).exists())
        .collect();

    let mut errors: Vec<String> = Vec::new();
    let mut errors_seen: HashSet<String> = HashSet::new();
    let mut report = |file: &str, message: &str| {
        let entry = format!("{}: {}", file, message);
        if errors_seen.insert(entry.clone()) {
            errors.push(entry);
        }
    };

    let mut modules: HashMap<String, Option<LoadedModule>> = HashMap::new();
    let mut canon_cache: HashMap<PathBuf, Option<PathBuf>> = HashMap::new();
    seed_non_symlink_files(&root, &["src", "server"], &mut canon_cache);

    #[allow(clippy::too_many_arguments)]
    fn load(
        file: &str,
        root: &Path,
        pkg_name: &str,
        pkg_exports: Option<&serde_json::Map<String, serde_json::Value>>,
        modules: &mut HashMap<String, Option<LoadedModule>>,
        canon_cache: &mut HashMap<PathBuf, Option<PathBuf>>,
        report: &mut dyn FnMut(&str, &str),
    ) -> Option<LoadedModule> {
        if let Some(existing) = modules.get(file) {
            return existing.clone();
        }
        let full_path = root.join(file);
        let resolved = match cached_canonicalize(&full_path, canon_cache) {
            Some(p) => p,
            None => {
                modules.insert(file.to_string(), None);
                return None;
            }
        };
        let rel_resolved = resolved
            .strip_prefix(root)
            .ok()
            .map(|p| p.to_string_lossy().replace('\\', "/"));
        if rel_resolved.as_deref() != Some(file) {
            report(
                file,
                "Runtime modules must not alias other owners through symlinks",
            );
            modules.insert(file.to_string(), None);
            return None;
        }

        let source_text = match std::fs::read_to_string(&resolved) {
            Ok(s) => s,
            Err(e) => {
                report(file, &e.to_string());
                modules.insert(file.to_string(), None);
                return None;
            }
        };

        let analysis = match analyze_module(&source_text) {
            Ok(a) => a,
            Err(msg) => {
                report(file, &msg);
                modules.insert(file.to_string(), None);
                return None;
            }
        };

        // Insert placeholder to break cycles
        modules.insert(
            file.to_string(),
            Some(LoadedModule {
                browser: analysis.browser.clone(),
                edges: Vec::new(),
                external: Vec::new(),
            }),
        );

        let mut edges = Vec::new();
        let mut external = Vec::new();

        for specifier in &analysis.imports {
            let target_path = if specifier.starts_with('.') {
                let clean = specifier.split('?').next().unwrap_or(specifier);
                resolved
                    .parent()
                    .unwrap_or(root)
                    .join(clean)
            } else if !pkg_name.is_empty()
                && (specifier == pkg_name || specifier.starts_with(&format!("{}/", pkg_name)))
            {
                let key = if specifier == pkg_name {
                    ".".to_string()
                } else {
                    format!(".{}", &specifier[pkg_name.len()..])
                };
                let exported = pkg_exports
                    .and_then(|m| m.get(&key))
                    .and_then(|v| v.as_str());
                match exported {
                    Some(exp) => root.join(exp),
                    None => {
                        report(file, &format!("Unsupported self import: {}", specifier));
                        continue;
                    }
                }
            } else {
                external.push(specifier.clone());
                if file.starts_with("src/") && is_node_builtin(specifier) {
                    report(
                        file,
                        &format!("Node builtin in browser module: {}", specifier),
                    );
                }
                if specifier.starts_with('/') || has_non_node_uri_scheme(specifier) {
                    report(
                        file,
                        &format!("Use repository or package imports: {}", specifier),
                    );
                }
                continue;
            };

            let target_real = match cached_canonicalize(&target_path, canon_cache) {
                Some(p) => p,
                None => {
                    report(file, &format!("Missing import: {}", specifier));
                    continue;
                }
            };
            let to = match target_real.strip_prefix(root) {
                Ok(rel) => rel.to_string_lossy().replace('\\', "/"),
                Err(_) => {
                    report(file, &format!("Import escapes repository: {}", specifier));
                    continue;
                }
            };
            if to.starts_with("../") || Path::new(&to).is_absolute() {
                report(file, &format!("Import escapes repository: {}", specifier));
                continue;
            }

            edges.push(to.clone());

            if file.starts_with("src/") && to.starts_with("server/") {
                report(file, &format!("Browser imports server: {}", to));
            }
            if !is_compatibility_edge(file, &to)
                && file.starts_with("server/providers/")
                && (to.starts_with("server/standalone/") || is_renderer_file(&to))
            {
                report(
                    file,
                    &format!("Provider imports application/rendering: {}", to),
                );
            }
            if !is_compatibility_edge(file, &to)
                && file.starts_with("src/")
                && !is_entry_file(file)
                && is_entry_file(&to)
            {
                report(
                    file,
                    &format!("Reusable module imports standalone setup: {}", to),
                );
            }
            if is_source_file(file) && is_renderer_file(&to) {
                report(file, &format!("Source imports rendering/application: {}", to));
            }
            if file == "src/voice/gevActions.js" && to == "src/data/manager.js" {
                report(
                    file,
                    "Actions must consume feed state without the manager facade",
                );
            }
        }

        let record = LoadedModule {
            browser: analysis.browser,
            edges,
            external,
        };
        modules.insert(file.to_string(), Some(record.clone()));
        Some(record)
    }

    for file in &files {
        load(
            file,
            &root,
            pkg_name,
            pkg_exports,
            &mut modules,
            &mut canon_cache,
            &mut report,
        );
    }

    // Browser graph check
    let mut browser_seen: HashSet<String> = HashSet::new();
    #[allow(clippy::too_many_arguments)]
    fn visit_browser(
        file: &str,
        root: &Path,
        pkg_name: &str,
        pkg_exports: Option<&serde_json::Map<String, serde_json::Value>>,
        modules: &mut HashMap<String, Option<LoadedModule>>,
        canon_cache: &mut HashMap<PathBuf, Option<PathBuf>>,
        browser_seen: &mut HashSet<String>,
        report: &mut dyn FnMut(&str, &str),
    ) {
        if !is_code_file(file) || !browser_seen.insert(file.to_string()) {
            return;
        }
        let info = match load(file, root, pkg_name, pkg_exports, modules, canon_cache, report) {
            Some(m) => m,
            None => return,
        };
        for specifier in &info.external {
            if is_node_builtin(specifier) {
                report(
                    file,
                    &format!("Browser graph reaches Node builtin: {}", specifier),
                );
            }
        }
        for to in &info.edges {
            if to.starts_with("server/") || is_test_file(to) {
                report(
                    file,
                    &format!("Browser graph reaches non-runtime owner: {}", to),
                );
            } else {
                visit_browser(
                    to,
                    root,
                    pkg_name,
                    pkg_exports,
                    modules,
                    canon_cache,
                    browser_seen,
                    report,
                );
            }
        }
    }

    for file in files.iter().filter(|f| f.starts_with("src/")) {
        visit_browser(
            file,
            &root,
            pkg_name,
            pkg_exports,
            &mut modules,
            &mut canon_cache,
            &mut browser_seen,
            &mut report,
        );
    }

    // Portable/source roots
    // A JS Map: insertion order, and setting an existing key keeps its place.
    let mut roots: Vec<(String, String)> = Vec::new();
    let set_root = |roots: &mut Vec<(String, String)>, start: String, label: String| {
        match roots.iter_mut().find(|(k, _)| *k == start) {
            Some(slot) => slot.1 = label,
            None => roots.push((start, label)),
        }
    };
    for file in files.iter().filter(|f| is_source_file(f)) {
        set_root(&mut roots, file.clone(), "source".to_string());
    }
    if let Some(exports_map) = pkg_exports {
        for key in json_object_keys_in_order(&pkg_raw, &["exports"]) {
            let Some(value) = exports_map.get(&key) else {
                continue;
            };
            if is_portable_export(&key) {
                if let Some(val_str) = value.as_str() {
                    let clean = val_str.strip_prefix("./").unwrap_or(val_str).to_string();
                    set_root(&mut roots, clean, key.clone());
                }
            }
        }
    }
    set_root(
        &mut roots,
        "src/data/feedState.js".to_string(),
        "feed state".to_string(),
    );

    for (start, label) in &roots {
        if !root.join(start).exists() {
            report(start, &format!("Missing portable entry: {}", label));
            continue;
        }
        let mut seen: HashSet<String> = HashSet::new();
        #[allow(clippy::too_many_arguments)]
        fn visit_portable(
            file: &str,
            label: &str,
            root: &Path,
            pkg_name: &str,
            pkg_exports: Option<&serde_json::Map<String, serde_json::Value>>,
            modules: &mut HashMap<String, Option<LoadedModule>>,
            canon_cache: &mut HashMap<PathBuf, Option<PathBuf>>,
            seen: &mut HashSet<String>,
            report: &mut dyn FnMut(&str, &str),
        ) {
            if !is_code_file(file) || !seen.insert(file.to_string()) {
                return;
            }
            let info = match load(file, root, pkg_name, pkg_exports, modules, canon_cache, report) {
                Some(m) => m,
                None => return,
            };
            if !info.browser.is_empty() {
                report(
                    file,
                    &format!("{} reaches browser globals: {}", label, info.browser.join(", ")),
                );
            }
            for specifier in &info.external {
                let is_cesium_or_vite = specifier == "cesium"
                    || specifier.starts_with("cesium/")
                    || specifier == "vite"
                    || specifier.starts_with("vite/");
                if is_node_builtin(specifier) || is_cesium_or_vite {
                    report(
                        file,
                        &format!(
                            "{} reaches platform/rendering dependency: {}",
                            label, specifier
                        ),
                    );
                }
            }
            for to in &info.edges {
                if is_renderer_file(to) || to.starts_with("server/") {
                    report(
                        file,
                        &format!("{} reaches application/rendering: {}", label, to),
                    );
                } else {
                    visit_portable(
                        to,
                        label,
                        root,
                        pkg_name,
                        pkg_exports,
                        modules,
                        canon_cache,
                        seen,
                        report,
                    );
                }
            }
        }
        visit_portable(
            start,
            label,
            &root,
            pkg_name,
            pkg_exports,
            &mut modules,
            &mut canon_cache,
            &mut seen,
            &mut report,
        );
    }

    // Voice controls check
    if root.join("src/voice/sessionCommands.js").exists() {
        let mut voice_seen: HashSet<String> = HashSet::new();
        #[allow(clippy::too_many_arguments)]
        fn visit_voice(
            file: &str,
            root: &Path,
            pkg_name: &str,
            pkg_exports: Option<&serde_json::Map<String, serde_json::Value>>,
            modules: &mut HashMap<String, Option<LoadedModule>>,
            canon_cache: &mut HashMap<PathBuf, Option<PathBuf>>,
            voice_seen: &mut HashSet<String>,
            report: &mut dyn FnMut(&str, &str),
        ) {
            if !voice_seen.insert(file.to_string()) {
                return;
            }
            if let Some(info) = load(file, root, pkg_name, pkg_exports, modules, canon_cache, report) {
                for to in &info.edges {
                    if to.starts_with("src/voice/realtime") {
                        report(
                            file,
                            &format!("Common voice controls import protocol: {}", to),
                        );
                    } else if is_code_file(to) {
                        visit_voice(
                            to,
                            root,
                            pkg_name,
                            pkg_exports,
                            modules,
                            canon_cache,
                            voice_seen,
                            report,
                        );
                    }
                }
            }
        }
        visit_voice(
            "src/voice/sessionCommands.js",
            &root,
            pkg_name,
            pkg_exports,
            &mut modules,
            &mut canon_cache,
            &mut voice_seen,
            &mut report,
        );
    }

    if !errors.is_empty() {
        return Err(errors.join("\n"));
    }

    Ok(DirectionSummary {
        modules: files.len(),
        portable_entries: roots.len(),
    })
}

pub fn resolve_app_root(explicit: Option<&str>) -> Result<PathBuf, String> {
    if let Some(dir) = explicit {
        let p = PathBuf::from(dir);
        if p.join("package.json").is_file() {
            if let Ok(real_pkg) = std::fs::canonicalize(p.join("package.json")) {
                if let Some(parent) = real_pkg.parent() {
                    return Ok(parent.to_path_buf());
                }
            }
            return Ok(p);
        }
    }

    let candidates: Vec<Option<String>> = vec![
        // `bazel run`: check the working tree it was started from, as
        // `node scripts/check-*.mjs` did.
        std::env::var("BUILD_WORKSPACE_DIRECTORY")
            .ok()
            .filter(|s| !s.is_empty())
            .map(|r| format!("{}/apps/web/gods-eye-view", r)),
        std::env::var("RUNFILES_DIR")
            .ok()
            .filter(|s| !s.is_empty())
            .map(|r| format!("{}/_main/apps/web/gods-eye-view", r)),
        std::env::var("TEST_SRCDIR")
            .ok()
            .filter(|s| !s.is_empty())
            .map(|r| format!("{}/_main/apps/web/gods-eye-view", r)),
        Some("apps/web/gods-eye-view".to_string()),
        Some(".".to_string()),
    ];

    for candidate in &candidates {
        if let Some(path_str) = candidate {
            let p = PathBuf::from(path_str);
            let pkg = p.join("package.json");
            if pkg.is_file() && p.join("scripts/package-boundaries.json").is_file() {
                if let Ok(real_pkg) = std::fs::canonicalize(&pkg) {
                    if let Some(parent) = real_pkg.parent() {
                        return Ok(parent.to_path_buf());
                    }
                }
                return Ok(p);
            }
        }
    }

    Err("Could not locate gods-eye-view root directory".to_string())
}

pub fn run(args: &[String]) -> Result<String, String> {
    let root = resolve_app_root(args.first().map(String::as_str))?;
    let summary = check_import_directions(&root)?;
    Ok(format!(
        "{{\"modules\":{},\"portableEntries\":{}}}",
        summary.modules, summary.portable_entries
    ))
}

/// The cases of upstream's `src/tooling/importDirections.test.mjs` (not in this
/// copy), against the Rust port. `analyze_module`'s cases are in `lib.rs`.
#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};

    static NEXT: AtomicUsize = AtomicUsize::new(0);

    struct Fixture {
        root: PathBuf,
    }

    impl Fixture {
        fn new(exports: &str) -> Self {
            let root = std::env::temp_dir().join(format!(
                "gev-directions-{}-{}",
                std::process::id(),
                NEXT.fetch_add(1, Ordering::SeqCst)
            ));
            let _ = std::fs::remove_dir_all(&root);
            std::fs::create_dir_all(&root).unwrap();
            let f = Fixture { root };
            f.write(
                "package.json",
                &format!(r#"{{"name":"@gods-eye-view/core","exports":{exports}}}"#),
            );
            f.write("src/data/feedState.js", "");
            f
        }

        fn write(&self, name: &str, body: &str) {
            let p = self.root.join(name);
            std::fs::create_dir_all(p.parent().unwrap()).unwrap();
            std::fs::write(p, body).unwrap();
        }

        fn check(&self) -> Result<DirectionSummary, String> {
            check_import_directions(&self.root)
        }

        fn rejects(&self, pattern: &str) {
            match self.check() {
                Ok(s) => panic!("expected a failure matching {pattern:?}, got Ok({s:?})"),
                Err(e) => assert!(e.contains(pattern), "{pattern:?} not in:\n{e}"),
            }
        }
    }

    impl Drop for Fixture {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.root);
        }
    }

    #[test]
    fn portable_sources_share_records_and_standalone_assembles_rendering() {
        let f = Fixture::new(r#"{"./layers/demo/source":"./src/layers/demo/source.js"}"#);
        f.write("src/layers/demo/source.js", "export { read } from './records.js';");
        f.write("src/layers/demo/records.js", "export const read = (value) => value;");
        f.write("src/standalone/catalog.js", "import '../layers/demo/index.js';");
        f.write("src/layers/demo/index.js", "import * as Cesium from 'cesium';");
        assert_eq!(f.check().unwrap().modules, 5);
    }

    #[test]
    fn rejects_each_direction_violation() {
        let cases: &[(&str, &[(&str, &str)], &str)] = &[
            (
                "unreachable source imports rendering",
                &[
                    ("src/layers/demo/source.js", "import './rendering.js';"),
                    ("src/layers/demo/rendering.js", ""),
                ],
                "Source imports rendering",
            ),
            (
                "source reaches a platform through a record helper",
                &[
                    ("src/layers/demo/source.js", "import './records.js';"),
                    ("src/layers/demo/records.js", "import 'cesium';"),
                ],
                "reaches platform/rendering",
            ),
            (
                "source reaches a DOM helper",
                &[
                    ("src/sources/demo.js", "import '../data/helper.js';"),
                    ("src/data/helper.js", "export const view = () => globalThis.document;"),
                ],
                "reaches browser globals",
            ),
            (
                "browser imports Node without prefix",
                &[("src/unused.mjs", "import 'fs/promises';")],
                "Node builtin",
            ),
            (
                "browser hides Node outside src",
                &[
                    ("src/unused.js", "import '../shared/helper.js';"),
                    ("shared/helper.js", "export * from 'node:fs';"),
                ],
                "Browser graph reaches Node",
            ),
            (
                "browser imports server",
                &[
                    ("src/data/demo.js", "import '../../server/helper.js';"),
                    ("server/helper.js", ""),
                ],
                "Browser imports server",
            ),
            (
                "reusable module selects standalone",
                &[
                    ("src/app/demo.js", "import '../standalone/catalog.js';"),
                    ("src/standalone/catalog.js", ""),
                ],
                "Reusable module imports standalone",
            ),
            (
                "provider selects application setup",
                &[
                    ("server/providers/demo.js", "import '../standalone/key-setup.js';"),
                    ("server/standalone/key-setup.js", ""),
                ],
                "Provider imports application",
            ),
            (
                "voice controls reach protocol indirectly",
                &[
                    ("src/voice/sessionCommands.js", "import './helper.js';"),
                    ("src/voice/helper.js", "import './realtimeSession.js';"),
                    ("src/voice/realtimeSession.js", ""),
                ],
                "Common voice controls import protocol",
            ),
            (
                "dynamic import cannot evade direction",
                &[("src/app/demo.js", "const target = './module.js'; import(target);")],
                "Computed",
            ),
            (
                "browser imports test helper",
                &[
                    ("src/app/demo.js", "import '../testSupport/helper.js';"),
                    ("src/testSupport/helper.js", ""),
                ],
                "non-runtime owner",
            ),
        ];
        for (name, files, pattern) in cases {
            let f = Fixture::new("{}");
            for (file, body) in *files {
                f.write(file, body);
            }
            match f.check() {
                Ok(s) => panic!("{name}: expected {pattern:?}, got Ok({s:?})"),
                Err(e) => assert!(e.contains(pattern), "{name}: {pattern:?} not in:\n{e}"),
            }
        }
    }

    #[test]
    fn self_package_imports_cannot_evade_portable_ownership() {
        let f = Fixture::new(r#"{"./view":"./src/ui/view.js"}"#);
        f.write("src/sources/demo.js", "import '@gods-eye-view/core/view';");
        f.write("src/ui/view.js", "");
        f.rejects("Source imports rendering");
    }

    #[test]
    fn the_compatibility_exception_is_limited_to_the_existing_composition_entry() {
        let f = Fixture::new("{}");
        f.write("src/standalone/catalog.js", "");
        f.write("server/providers/local.js", "import '../standalone/key-setup.js';");
        f.write("server/standalone/key-setup.js", "");
        f.check().unwrap();
        f.write("src/ui.js", "import './standalone/catalog.js';");
        f.rejects("Reusable module imports standalone");
        f.write("src/ui.js", "");
        f.write("src/ui/new.js", "import '../standalone/catalog.js';");
        f.rejects("Reusable module imports standalone");
    }

    #[test]
    fn symlink_aliases_do_not_hide_renderer_ownership() {
        let f = Fixture::new("{}");
        f.write("src/sources/demo.js", "import './helper/view.js';");
        f.write("src/ui/view.js", "");
        std::os::unix::fs::symlink(f.root.join("src/ui"), f.root.join("src/sources/helper"))
            .unwrap();
        let e = f.check().unwrap_err();
        assert!(e.contains("rendering") || e.contains("symlinks"), "{e}");
    }

    #[test]
    fn portable_roots_follow_package_json_order_and_last_label_wins() {
        // Both exports name one file: the Node Map kept the first key's place
        // and the last key's label, so the report names `./view`.
        let f = Fixture::new(
            r#"{"./tools":"./src/data/shared.js","./view":"./src/data/shared.js"}"#,
        );
        f.write("src/data/shared.js", "globalThis.document;");
        f.rejects("src/data/shared.js: ./view reaches browser globals: document");
        assert!(!f.check().unwrap_err().contains("./tools reaches"));
    }

    #[test]
    fn json_object_keys_in_order_keeps_document_order() {
        let raw = r#"{"z":1,"exports":{"./b":"x","./a":{"node":"y"},"./c":[1,{"q":2}]},"a":{"k":3}}"#;
        assert_eq!(json_object_keys_in_order(raw, &[]), vec!["z", "exports", "a"]);
        assert_eq!(
            json_object_keys_in_order(raw, &["exports"]),
            vec!["./b", "./a", "./c"]
        );
        assert_eq!(json_object_keys_in_order(raw, &["exports", "./a"]), vec!["node"]);
        assert!(json_object_keys_in_order(raw, &["missing"]).is_empty());
        assert!(json_object_keys_in_order("not json", &[]).is_empty());
    }
}
