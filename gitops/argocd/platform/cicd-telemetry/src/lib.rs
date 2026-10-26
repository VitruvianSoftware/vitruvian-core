// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT

//! Invariants of the CI collector that must never silently regress.
//!
//! Spec: `docs/superpowers/specs/2026-09-28-cicd-telemetry-design.md`

pub mod yaml;

use serde_json::Value;

pub const PKG_DIR: &str = "gitops/argocd/platform/cicd-telemetry";

/// Real Dependabot run names (GitHub 'dynamic' runs, 2026-09-29): one per run.
pub const DEPENDABOT_RUN_NAMES: &[&str] = &[
    "Configured Graph Update: go_modules in /apps/cli/devx #1587192811",
    "Configured Graph Update: go_modules in /apps/suites/tabula/infra/app, /apps/suites/tabula/infra/build, /apps/suites/tabula/infra/data, /apps/suites/tabula/infra/identity, /apps/suites/tabula/infra/web, /apps/web/oauth-user-inspector/infra/app, /apps/web/oauth-user-inspector/infra/identity #1587193184",
    "Configured Graph Update: go_modules in /apps/suites/tabula/infra/data, /apps/suites/tabula/infra/identity #1582857905",
    "github_actions in /., /.github/actions/*, /apps/cli/devx/.github/workflows, /apps/cli/homelab/.github/workflows, /apps/desktop/nexus-agent/.github/workflows, /apps/mcp/slack/.github/workflows, /apps/web/gods-eye-view/.github/workflows, /packages/pulumi/examples/go-foundation/.github/workflows, /packages/pulumi/examples/go-foundation/build, /packages/pulumi/examples/ts-foundation/.github/workflows, /packages/pulumi/examples/ts-foundation/build, /packages/pulumi/library/.github/workflows - Update #1587170913",
    "go_modules in /apps/cli/devx - Update #1587170882",
    "go_modules in /apps/cli/homelab - Update #1587170990",
    "go_modules in /apps/suites/tabula/infra/**, /apps/web/oauth-user-inspector/infra/app, /apps/web/oauth-user-inspector/infra/identity, /infrastructure/pulumi/** - Update #1587170918",
    "npm_and_yarn in /. - Update #1587168571",
    "npm_and_yarn in /. for @octokit/plugin-paginate-rest, @octokit/request, @octokit/request-error, @opentelemetry/core, @opentelemetry/propagator-jaeger, adm-zip, adm-zip, body-parser, colord, d3-color, deepmerge-ts, elliptic, extract-zip, extract-zip, file-type, hono, hono, hono, js-yaml, js-yaml, locutus, locutus, locutus, locutus, lodash, lodash, minimatch, minimatch, minimatch, multer, multer, multer, multer, mysql2, mysql2, nanoid, prismjs, react-router, react-router, svgo, svgo, uuid - Update #1582538339",
    "npm_and_yarn in /. for @octokit/plugin-paginate-rest, @octokit/request, @octokit/request-error, @opentelemetry/core, @opentelemetry/propagator-jaeger, adm-zip, adm-zip, body-parser, colord, d3-color, deepmerge-ts, elliptic, extract-zip, extract-zip, file-type, hono, hono, hono, js-yaml, js-yaml, locutus, locutus, locutus, locutus, lodash, lodash, minimatch, minimatch, minimatch, multer, multer, multer, multer, mysql2, mysql2, nanoid, prismjs, react-router, react-router, svgo, svgo, uuid - Update #1582561233Graph Update: go_modules in /infrastructure/pulumi/accounts/personal #1582863532",
];

/// Every workflow name in `.github/workflows` at the time: must NOT be rewritten.
pub const WORKFLOW_NAMES: &[&str] = &[
    "Auto-merge release PRs",
    "Backstage image update PR",
    "Buzz image update PR",
    "CI",
    "Changelog Summary Test",
    "Conformance Check",
    "Copybara Config Smoke Test",
    "Copybara Export (devx)",
    "Copybara Export (homelab)",
    "Copybara Export (mcp-slack)",
    "Copybara Export (nexus-agent)",
    "Copybara Export (oauth-user-inspector)",
    "Copybara Export (pulumi-library)",
    "Copybara Export (pulumi_go-example-foundation)",
    "Copybara Export (pulumi_ts-example-foundation)",
    "Copybara Export (reusable)",
    "Copybara Import PR",
    "Copybara Import PR auto-close mirror",
    "Dependabot Bazel reconcile",
    "Dependabot Lock Rebase Test",
    "Dependabot auto-merge",
    "Dependabot lock rebase",
    "Deploy Affected Test",
    "Foundation App Digest Guard Test",
    "Foundation App-Infra Deploy",
    "Foundation Environment Deploy",
    "Foundation Network Deploy",
    "Foundation Preview",
    "Foundation Projects Deploy",
    "Foundation Pulumi Summary Test",
    "Foundation Release & Deploy",
    "GCP Secret Or Fail Test",
    "Go Test With Retry Test",
    "LLVM Cache Key Test",
    "Notify CI Issues Test",
    "Periodic Full Sweep",
    "Presubmit",
    "Pulumi Preview",
    "Release Hold Test",
    "Relevant Paths Test",
    "Repo Config Apply",
    "Repo Config Preview",
    "Require Dev Soak Test",
    "Resolve Deploy Base Test",
    "Secret Scan Test",
    "Site Verification Test",
    "Supply Chain",
    "Tabula Deploy Preflight Test",
    "Tidy Check",
    "_deploy-cloud-run",
    "_oauth-identity-apply",
    "_tabula-identity-apply",
    "_zitadel-apps-apply",
    "actionlint",
    "apps-release",
    "backstage-image",
    "chart-render",
    "culprit-finder",
    "delivery",
    "delivery-drift",
    "gitops-validate",
    "gods-eye-view-image",
    "home-speaker-release",
    "iot-esp32-s3",
    "iot-esp32-s3-release",
    "mcp-slack image update PR",
    "mcp-slack-image",
    "migration-safety",
    "notify-ci-issues",
    "preview-teardown",
    "prune-pr-caches",
    "pulumi-library-release",
    "pulumi-stack-reset",
    "release-hold",
    "renovate",
    "storybook-image",
    "tabula Data Stack Deploy",
    "tabula-e2e",
    "tabula-release",
    "zitadel-apps-mcp-slack-apply",
];

/// Load the `OpenTelemetryCollector` document from `collector.yaml`.
pub fn load_collector() -> Value {
    let path = yaml::resolve_data_path(PKG_DIR, "collector.yaml");
    let raw = std::fs::read_to_string(&path)
        .unwrap_or_else(|e| panic!("failed to read {}: {e}", path.display()));
    let docs = yaml::parse_all(&raw).expect("failed to parse collector.yaml");
    let cols: Vec<&Value> = docs
        .iter()
        .filter(|d| d.get("kind").and_then(Value::as_str) == Some("OpenTelemetryCollector"))
        .collect();
    assert_eq!(cols.len(), 1, "expected 1 OpenTelemetryCollector document");
    cols[0].clone()
}

/// Extract all `trace_statements` strings from `processors["transform/ci-labels"]`.
pub fn trace_statements(cfg: &Value) -> Vec<String> {
    cfg.pointer("/processors/transform~1ci-labels/trace_statements")
        .and_then(Value::as_array)
        .map(|groups| {
            groups
                .iter()
                .filter_map(|g| g.get("statements").and_then(Value::as_array))
                .flatten()
                .filter_map(Value::as_str)
                .map(ToString::to_string)
                .collect()
        })
        .unwrap_or_default()
}

/// Parse an OTTL `replace_pattern(resource.attributes["cicd.pipeline.name"], "<pat>", "<repl>")` statement.
pub fn parse_replace_pattern_statement(st: &str) -> Option<(String, String)> {
    let prefix = r#"replace_pattern(resource.attributes["cicd.pipeline.name"], ""#;
    let rest = st.strip_prefix(prefix)?;
    let rest = rest.strip_suffix(r#"")"#)?;
    let (pat, repl) = rest.split_once(r#"", ""#)?;
    Some((pat.replace(r"\\", r"\"), repl.to_string()))
}

/// Apply the resource-context `replace_pattern` statements the way OTTL would.
pub fn collapse_pipeline_name(statements: &[String], name: &str) -> String {
    let mut current = name.to_string();
    for st in statements {
        if let Some((pat, repl)) = parse_replace_pattern_statement(st) {
            current = regex_replace_anchored(&pat, &repl, &current);
        }
    }
    current
}

/// Check if `st` contains any unprefixed OTTL path (`(?<![\w.])(attributes|name|kind)(?=[\[ ,)])`).
pub fn find_bare_ottl_paths(st: &str) -> Vec<&'static str> {
    let mut found = Vec::new();
    let bytes = st.as_bytes();
    for &kw in &["attributes", "name", "kind"] {
        let kw_bytes = kw.as_bytes();
        let mut start = 0;
        while let Some(rel) = st[start..].find(kw) {
            let idx = start + rel;
            let end = idx + kw_bytes.len();
            let prev_ok = if idx == 0 {
                true
            } else {
                let pb = bytes[idx - 1];
                !(pb.is_ascii_alphanumeric() || pb == b'_' || pb == b'.')
            };
            let next_ok = end < bytes.len() && matches!(bytes[end], b'[' | b' ' | b',' | b')');
            if prev_ok && next_ok {
                found.push(kw);
            }
            start = idx + 1;
        }
    }
    found
}

// ---------------------------------------------------------------------------
// Minimal anchored regex matcher & replacer supporting `(?:...)`, `(...)`,
// `[a-z_]`, `\d`, `.`, `?`, `*`, `+`, and `$$1` / `$1` capture replacement.
// ---------------------------------------------------------------------------

#[derive(Clone, Debug)]
enum Atom {
    Literal(char),
    Any,
    Digit,
    CharClass(Vec<(char, char)>),
    Group {
        capture_idx: Option<usize>,
        seq: Vec<Piece>,
    },
}

#[derive(Clone, Debug)]
struct Piece {
    atom: Atom,
    min: usize,
    max: Option<usize>,
}

fn compile_regex(pat: &str) -> Vec<Piece> {
    let pat = pat.strip_prefix('^').unwrap_or(pat);
    let pat = pat.strip_suffix('$').unwrap_or(pat);
    let chars: Vec<char> = pat.chars().collect();
    let mut pos = 0;
    let mut next_cap = 1;
    parse_seq(&chars, &mut pos, &mut next_cap, false)
}

fn parse_seq(
    chars: &[char],
    pos: &mut usize,
    next_cap: &mut usize,
    stop_on_paren: bool,
) -> Vec<Piece> {
    let mut seq = Vec::new();
    while *pos < chars.len() {
        let c = chars[*pos];
        if stop_on_paren && c == ')' {
            *pos += 1;
            break;
        }
        let atom = match c {
            '(' => {
                *pos += 1;
                let capture_idx =
                    if *pos + 1 < chars.len() && chars[*pos] == '?' && chars[*pos + 1] == ':' {
                        *pos += 2;
                        None
                    } else {
                        let idx = *next_cap;
                        *next_cap += 1;
                        Some(idx)
                    };
                let inner = parse_seq(chars, pos, next_cap, true);
                Atom::Group {
                    capture_idx,
                    seq: inner,
                }
            }
            '[' => {
                *pos += 1;
                let mut ranges = Vec::new();
                while *pos < chars.len() && chars[*pos] != ']' {
                    let start = chars[*pos];
                    if *pos + 2 < chars.len() && chars[*pos + 1] == '-' && chars[*pos + 2] != ']' {
                        let end = chars[*pos + 2];
                        ranges.push((start, end));
                        *pos += 3;
                    } else {
                        ranges.push((start, start));
                        *pos += 1;
                    }
                }
                if *pos < chars.len() && chars[*pos] == ']' {
                    *pos += 1;
                }
                Atom::CharClass(ranges)
            }
            '\\' => {
                *pos += 1;
                let esc = chars.get(*pos).copied().unwrap_or('\\');
                *pos += 1;
                if esc == 'd' {
                    Atom::Digit
                } else {
                    Atom::Literal(esc)
                }
            }
            '.' => {
                *pos += 1;
                Atom::Any
            }
            ch => {
                *pos += 1;
                Atom::Literal(ch)
            }
        };

        let (min, max) = match chars.get(*pos).copied() {
            Some('?') => {
                *pos += 1;
                (0, Some(1))
            }
            Some('*') => {
                *pos += 1;
                (0, None)
            }
            Some('+') => {
                *pos += 1;
                (1, None)
            }
            _ => (1, Some(1)),
        };
        seq.push(Piece { atom, min, max });
    }
    seq
}

type Captures = [Option<(usize, usize)>; 10];

fn match_seq(
    seq: &[Piece],
    t: &[char],
    ti: usize,
    caps: Captures,
    require_end: bool,
) -> Option<(usize, Captures)> {
    if seq.is_empty() {
        if !require_end || ti == t.len() {
            return Some((ti, caps));
        }
        return None;
    }
    let piece = &seq[0];
    let rest = &seq[1..];

    let mut states: Vec<(usize, Captures)> = Vec::new();
    if piece.min == 0 {
        states.push((ti, caps));
    }
    let mut cur_pos = ti;
    let mut cur_caps = caps;
    let mut count = 0usize;
    loop {
        if let Some(m) = piece.max {
            if count >= m {
                break;
            }
        }
        let Some((next_pos, next_caps)) = match_atom(&piece.atom, t, cur_pos, cur_caps) else {
            break;
        };
        if next_pos == cur_pos && piece.max.is_none() {
            break;
        }
        count += 1;
        cur_pos = next_pos;
        cur_caps = next_caps;
        if count >= piece.min {
            states.push((cur_pos, cur_caps));
        }
    }

    for &(pos, st_caps) in states.iter().rev() {
        if let Some(res) = match_seq(rest, t, pos, st_caps, require_end) {
            return Some(res);
        }
    }
    None
}

fn match_atom(atom: &Atom, t: &[char], ti: usize, mut caps: Captures) -> Option<(usize, Captures)> {
    match atom {
        Atom::Literal(c) => (ti < t.len() && t[ti] == *c).then_some((ti + 1, caps)),
        Atom::Any => (ti < t.len()).then_some((ti + 1, caps)),
        Atom::Digit => (ti < t.len() && t[ti].is_ascii_digit()).then_some((ti + 1, caps)),
        Atom::CharClass(ranges) => {
            if ti >= t.len() {
                return None;
            }
            let ch = t[ti];
            let ok = ranges.iter().any(|&(lo, hi)| (lo..=hi).contains(&ch));
            ok.then_some((ti + 1, caps))
        }
        Atom::Group { capture_idx, seq } => {
            let (end_pos, mut next_caps) = match_seq(seq, t, ti, caps, false)?;
            if let Some(idx) = *capture_idx {
                if idx < next_caps.len() {
                    next_caps[idx] = Some((ti, end_pos));
                }
            }
            caps = next_caps;
            Some((end_pos, caps))
        }
    }
}

pub fn regex_captures(pat: &str, text: &str) -> Option<Vec<String>> {
    let seq = compile_regex(pat);
    let chars: Vec<char> = text.chars().collect();
    let (_, caps) = match_seq(&seq, &chars, 0, [None; 10], true)?;
    let mut out = vec![text.to_string()];
    for cap in caps.iter().skip(1) {
        if let Some((s, e)) = *cap {
            out.push(chars[s..e].iter().collect());
        } else {
            out.push(String::new());
        }
    }
    Some(out)
}

pub fn regex_is_match(pat: &str, text: &str) -> bool {
    regex_captures(pat, text).is_some()
}

pub fn regex_replace_anchored(pat: &str, repl: &str, text: &str) -> String {
    let Some(caps) = regex_captures(pat, text) else {
        return text.to_string();
    };
    // OTTL uses `$$1` for capture group 1
    let mut out = repl.replace("$$1", &caps[1]);
    out = out.replace("$1", &caps[1]);
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use std::collections::HashSet;

    #[test]
    fn test_webhook_secret_comes_from_the_required_secret() {
        let col = load_collector();
        assert_eq!(
            col.pointer("/spec/config/receivers/github/webhook/secret")
                .and_then(Value::as_str),
            Some("${env:GITHUB_WEBHOOK_SECRET}")
        );
        let envs: Vec<&Value> = col
            .pointer("/spec/env")
            .and_then(Value::as_array)
            .expect("missing spec.env")
            .iter()
            .filter(|e| e.get("name").and_then(Value::as_str) == Some("GITHUB_WEBHOOK_SECRET"))
            .collect();
        assert_eq!(envs.len(), 1);
        let secret_ref = envs[0]
            .pointer("/valueFrom/secretKeyRef")
            .expect("missing valueFrom.secretKeyRef");
        assert_eq!(
            (
                secret_ref.get("name").and_then(Value::as_str),
                secret_ref.get("key").and_then(Value::as_str)
            ),
            (Some("github-otel-webhook"), Some("GITHUB_WEBHOOK_SECRET"))
        );
        assert_eq!(
            secret_ref.get("optional").and_then(Value::as_bool),
            Some(false)
        );
    }

    #[test]
    fn test_raw_event_bodies_not_attached() {
        let col = load_collector();
        assert_eq!(
            col.pointer("/spec/config/receivers/github/webhook/include_span_events")
                .and_then(Value::as_bool),
            Some(false)
        );
    }

    #[test]
    fn test_webhook_address() {
        let col = load_collector();
        let wh = col
            .pointer("/spec/config/receivers/github/webhook")
            .expect("missing github.webhook");
        assert_eq!(
            (
                wh.get("endpoint").and_then(Value::as_str),
                wh.get("path").and_then(Value::as_str)
            ),
            (Some("0.0.0.0:19418"), Some("/events"))
        );
    }

    #[test]
    fn test_committer_identity_deleted() {
        let col = load_collector();
        let cfg = col.pointer("/spec/config").expect("missing spec.config");
        let acts = cfg
            .pointer("/processors/resource~1drop-identity/attributes")
            .and_then(Value::as_array)
            .expect("missing resource/drop-identity attributes");
        let deleted: HashSet<&str> = acts
            .iter()
            .filter(|a| a.get("action").and_then(Value::as_str) == Some("delete"))
            .filter_map(|a| a.get("key").and_then(Value::as_str))
            .collect();
        let expected: HashSet<&str> = [
            "vcs.ref.head.revision.author.name",
            "vcs.ref.head.revision.author.email",
        ]
        .into_iter()
        .collect();
        assert_eq!(deleted, expected);

        let trace_procs = cfg
            .pointer("/service/pipelines/traces/processors")
            .and_then(Value::as_array)
            .expect("missing traces processors");
        assert!(trace_procs
            .iter()
            .any(|p| p.as_str() == Some("resource/drop-identity")));
    }

    #[test]
    fn test_metric_labels_are_exactly_the_approved_four() {
        let col = load_collector();
        let dims: Vec<&str> = col
            .pointer("/spec/config/connectors/span_metrics/dimensions")
            .and_then(Value::as_array)
            .expect("missing span_metrics dimensions")
            .iter()
            .filter_map(|d| d.get("name").and_then(Value::as_str))
            .collect();
        assert_eq!(
            dims,
            vec![
                "cicd.pipeline.name",
                "ci.span.type",
                "ci.trigger",
                "ci.retry"
            ]
        );
    }

    #[test]
    fn test_duration_buckets_fine_enough_for_ci() {
        let col = load_collector();
        let raw_buckets = col
            .pointer("/spec/config/connectors/span_metrics/histogram/explicit/buckets")
            .and_then(Value::as_array)
            .expect("missing explicit histogram buckets");
        let mut inside: Vec<f64> = Vec::new();
        for b in raw_buckets {
            let s = b.as_str().expect("bucket must be string");
            let (num_str, unit) = s.split_at(s.len() - 1);
            let mult = match unit {
                "s" => 1.0,
                "m" => 60.0,
                other => panic!("unexpected bucket unit {other}"),
            };
            let secs = num_str.parse::<f64>().expect("invalid bucket number") * mult;
            if (60.0..=3600.0).contains(&secs) {
                inside.push(secs);
            }
        }
        for pair in inside.windows(2) {
            let (lo, hi) = (pair[0], pair[1]);
            assert!(hi / lo <= 1.5, "bucket gap {lo}s -> {hi}s too wide");
        }
    }

    #[test]
    fn test_every_real_dependabot_run_name_collapses() {
        let col = load_collector();
        let cfg = col.pointer("/spec/config").expect("missing spec.config");
        let stmts = trace_statements(cfg);
        let mut collapsed_set: HashSet<String> = HashSet::new();
        for &name in DEPENDABOT_RUN_NAMES {
            let got = collapse_pipeline_name(&stmts, name);
            assert!(
                regex_is_match(r"^dependabot (graph )?[a-z_]+$", &got),
                "unexpected collapsed name {got:?} for {name:?}"
            );
            collapsed_set.insert(got);
        }
        let mut sorted: Vec<String> = collapsed_set.into_iter().collect();
        sorted.sort();
        assert_eq!(
            sorted,
            vec![
                "dependabot github_actions",
                "dependabot go_modules",
                "dependabot graph go_modules",
                "dependabot npm_and_yarn",
            ]
        );
    }

    #[test]
    fn test_real_workflow_names_are_untouched() {
        let col = load_collector();
        let cfg = col.pointer("/spec/config").expect("missing spec.config");
        let stmts = trace_statements(cfg);
        for &name in WORKFLOW_NAMES {
            assert_eq!(collapse_pipeline_name(&stmts, name), name);
        }
    }

    #[test]
    fn test_run_span_name_follows_the_collapsed_name() {
        let col = load_collector();
        let cfg = col.pointer("/spec/config").expect("missing spec.config");
        let stmts = trace_statements(cfg);
        let expected = r#"set(span.name, resource.attributes["cicd.pipeline.name"]) where span.kind == SPAN_KIND_SERVER"#;
        assert!(stmts.iter().any(|s| s == expected));
    }

    #[test]
    fn test_metrics_add_up_across_runs() {
        let col = load_collector();
        let cfg = col.pointer("/spec/config").expect("missing spec.config");
        assert_eq!(
            cfg.pointer("/connectors/span_metrics/resource_metrics_key_attributes"),
            Some(&json!(["service.name"]))
        );
        let mp_procs = cfg
            .pointer("/service/pipelines/metrics/processors")
            .and_then(Value::as_array)
            .expect("missing metrics pipeline processors");
        assert!(mp_procs
            .iter()
            .any(|p| p.as_str() == Some("transform/metrics-resource")));
        let metric_stmts: Vec<&str> = cfg
            .pointer("/processors/transform~1metrics-resource/metric_statements")
            .and_then(Value::as_array)
            .expect("missing metric_statements")
            .iter()
            .filter_map(|g| g.get("statements").and_then(Value::as_array))
            .flatten()
            .filter_map(Value::as_str)
            .collect();
        assert!(metric_stmts.contains(&r#"keep_keys(resource.attributes, ["service.name"])"#));
    }

    #[test]
    fn test_timeouts_and_startup_failures_count_as_failures() {
        let col = load_collector();
        let cfg = col.pointer("/spec/config").expect("missing spec.config");
        let stmts = trace_statements(cfg);
        let expected = r#"set(span.status.code, STATUS_CODE_ERROR) where span.status.message == "timed_out" or span.status.message == "startup_failure""#;
        assert!(stmts.iter().any(|s| s == expected));
    }

    #[test]
    fn test_prometheus_can_scrape_the_collector() {
        let path = yaml::resolve_data_path(PKG_DIR, "network-policy.yaml");
        let raw = std::fs::read_to_string(&path).expect("failed to read network-policy.yaml");
        let pol = yaml::parse_doc(&raw).expect("failed to parse network-policy.yaml");
        let ingress = pol
            .pointer("/spec/ingress")
            .and_then(Value::as_array)
            .expect("missing spec.ingress");
        let mut ok = false;
        for rule in ingress {
            let from_prom = rule
                .get("fromEndpoints")
                .and_then(Value::as_array)
                .is_some_and(|eps| {
                    eps.iter().any(|e| {
                        let ml = e.get("matchLabels");
                        ml.and_then(|m| m.get("io.kubernetes.pod.namespace"))
                            .and_then(Value::as_str)
                            == Some("monitoring")
                            && ml
                                .and_then(|m| m.get("app.kubernetes.io/name"))
                                .and_then(Value::as_str)
                                == Some("prometheus")
                    })
                });
            let has_8888 = rule
                .get("toPorts")
                .and_then(Value::as_array)
                .is_some_and(|tps| {
                    tps.iter().any(|tp| {
                        tp.get("ports")
                            .and_then(Value::as_array)
                            .is_some_and(|ports| {
                                ports.iter().any(|p| {
                                    p.get("port").and_then(Value::as_str) == Some("8888")
                                        || p.get("port").and_then(Value::as_i64) == Some(8888)
                                })
                            })
                    })
                });
            if from_prom && has_8888 {
                ok = true;
            }
        }
        assert!(ok, "no ingress rule lets monitoring/prometheus reach :8888");
    }

    #[test]
    fn test_ottl_paths_carry_their_context() {
        let col = load_collector();
        let cfg = col.pointer("/spec/config").expect("missing spec.config");
        for st in trace_statements(cfg) {
            let bare = find_bare_ottl_paths(&st);
            assert!(bare.is_empty(), "unprefixed path {bare:?} in: {st}");
        }
    }

    #[test]
    fn test_github_receiver_only_in_traces_pipeline() {
        let col = load_collector();
        let pipes = col
            .pointer("/spec/config/service/pipelines")
            .and_then(Value::as_object)
            .expect("missing service.pipelines");
        let users: Vec<&str> = pipes
            .iter()
            .filter(|(_, p)| {
                p.get("receivers")
                    .and_then(Value::as_array)
                    .is_some_and(|r| r.iter().any(|x| x.as_str() == Some("github")))
            })
            .map(|(k, _)| k.as_str())
            .collect();
        assert_eq!(users, vec!["traces"]);
    }

    #[test]
    fn test_memory_limit_backs_memory_limiter() {
        let col = load_collector();
        assert!(col
            .pointer("/spec/config/processors/memory_limiter")
            .is_some());
        assert!(
            col.pointer("/spec/resources/limits/memory")
                .and_then(Value::as_str)
                .is_some_and(|s| !s.is_empty()),
            "no memory limit"
        );
        assert!(
            col.pointer("/spec/resources/requests/memory")
                .and_then(Value::as_str)
                .is_some_and(|s| !s.is_empty()),
            "no memory request"
        );
        assert!(
            col.pointer("/spec/resources/limits/cpu").is_none(),
            "a CPU limit only throttles"
        );
    }

    #[test]
    fn test_span_metrics_series_expire() {
        let col = load_collector();
        let exp = col
            .pointer("/spec/config/connectors/span_metrics/metrics_expiration")
            .and_then(Value::as_str)
            .expect("span_metrics keeps every series forever");
        let caps = regex_captures(r"^(\d+)h$", exp)
            .unwrap_or_else(|| panic!("metrics_expiration {exp:?}: write it in hours"));
        let hours: i64 = caps[1].parse().expect("invalid hours");
        assert!(hours >= 168);
    }

    #[test]
    fn test_survives_one_node_down() {
        let col = load_collector();
        assert_eq!(
            col.pointer("/spec/replicas").and_then(Value::as_i64),
            Some(2)
        );
        assert_eq!(
            col.pointer("/spec/podDisruptionBudget/minAvailable")
                .and_then(Value::as_i64),
            Some(1)
        );
        assert!(col
            .pointer(
                "/spec/affinity/podAntiAffinity/requiredDuringSchedulingIgnoredDuringExecution"
            )
            .and_then(Value::as_array)
            .is_some_and(|a| !a.is_empty()));
    }

    #[test]
    fn test_no_deprecated_component_names() {
        let col = load_collector();
        let cfg = col.pointer("/spec/config").expect("missing spec.config");
        let mut names = Vec::new();
        for sec in ["connectors", "exporters", "receivers"] {
            if let Some(obj) = cfg.get(sec).and_then(Value::as_object) {
                names.extend(obj.keys().map(String::as_str));
            }
        }
        for old in ["spanmetrics", "prometheusremotewrite", "otlp"] {
            let bad: Vec<&str> = names
                .iter()
                .copied()
                .filter(|n| n.split('/').next() == Some(old))
                .collect();
            assert!(bad.is_empty(), "deprecated component name {old:?} in use");
        }
    }

    #[test]
    fn test_argocd_sees_real_config_changes() {
        let app_path = yaml::resolve_data_path("gitops/argocd/applications", "cicd-telemetry.yaml");
        let raw = std::fs::read_to_string(&app_path).expect("failed to read cicd-telemetry.yaml");
        let app = yaml::parse_doc(&raw).expect("failed to parse cicd-telemetry.yaml");
        let compare_opts = app
            .pointer("/metadata/annotations/argocd.argoproj.io~1compare-options")
            .and_then(Value::as_str)
            .unwrap_or("");
        assert!(!compare_opts.contains("ServerSideDiff=true"));
    }

    #[test]
    fn test_ports_declare_the_webhook_default() {
        let col = load_collector();
        let ports = col
            .pointer("/spec/ports")
            .and_then(Value::as_array)
            .expect("missing spec.ports");
        for port in ports {
            let name = port.get("name").and_then(Value::as_str).unwrap_or("?");
            assert!(
                port.get("targetPort").is_some(),
                "port {name} lacks targetPort"
            );
        }
    }

    #[test]
    fn test_operator_does_not_write_its_own_network_policy() {
        let col = load_collector();
        assert_eq!(
            col.pointer("/spec/networkPolicy/enabled")
                .and_then(Value::as_bool),
            Some(false)
        );
    }

    #[test]
    fn test_detects_bare_ottl_paths_in_invalid_statement() {
        assert_eq!(
            find_bare_ottl_paths(r#"set(attributes["ci.span.type"], "job")"#),
            vec!["attributes"]
        );
        assert!(find_bare_ottl_paths(r#"set(span.attributes["ci.span.type"], "job")"#).is_empty());
    }
}
