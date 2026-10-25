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

//! Writing the record (record.go): a GitHub commit status on the head
//! commit, set by ONE named identity, the recorder in recorder.tsv. The
//! token is minted from the recorder's own key; GH_TOKEN and the gh login
//! are never used, so a record cannot quietly come from whoever is logged in.

use std::collections::{BTreeMap, BTreeSet};
use std::time::Duration;

use unitfile::gocompat::exec::{self, Cmd, Ctx, Io};
use unitfile::gocompat::json::{self, Dec};
use unitfile::gocompat::path;
use unitfile::gocompat::quote::quote;

use crate::http;
use crate::sha256;
use crate::shim::Invocation;

pub const STATUS_CONTEXT: &str = "verified-run";
pub const REPO_SLUG: &str = "VitruvianSoftware/vitruvian-core";
pub const RECORDER_FILE: &str = "tools/pipeline/verifiedrun/recorder.tsv";
pub const AGENTS_FILE: &str = "tools/agent-app/agents.tsv";

/// What a passing run writes.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Record {
    pub head: String,
    pub tree: String,
    pub base: String,
    pub lanes: Vec<String>,
    pub plan: String,
    pub target_url: String,
}

/// Names exactly what ran: one line per lane and target, sorted, hashed.
pub fn plan_digest(invs: &[Invocation]) -> String {
    let mut seen = BTreeSet::new();
    for inv in invs {
        for t in inv.targets.iter().flatten() {
            seen.insert(format!("{}\t{t}", inv.lane));
        }
    }
    let lines: Vec<String> = seen.into_iter().collect();
    sha256::hex_digest(lines.join("\n").as_bytes())
}

fn lanes_of(invs: &[Invocation]) -> Vec<String> {
    let set: BTreeSet<String> = invs.iter().map(|i| i.lane.clone()).collect();
    set.into_iter().collect()
}

/// The one BuildBuddy run, or the commit's page listing them all.
fn target_url(head: &str, invs: &[Invocation]) -> String {
    let urls: BTreeSet<&str> = invs.iter().map(|i| i.url.as_str()).collect();
    if urls.len() == 1 {
        return invs[0].url.clone();
    }
    format!("https://app.buildbuddy.io/history/commit/{head}")
}

pub fn new_record(head: &str, tree: &str, base: &str, invs: &[Invocation]) -> Record {
    Record {
        head: head.to_string(),
        tree: tree.to_string(),
        base: base.to_string(),
        lanes: lanes_of(invs),
        plan: plan_digest(invs),
        target_url: target_url(head, invs),
    }
}

/// The first 12 bytes.
pub fn short(s: &str) -> &str {
    if s.len() > 12 {
        s.get(..12).unwrap_or(s)
    } else {
        s
    }
}

impl Record {
    /// Fits GitHub's 140-character limit and carries what the PR check
    /// compares: the exact files, the diff base and the work done.
    pub fn description(&self) -> String {
        format!(
            "tree={} base={} plan={}",
            self.tree,
            short(&self.base),
            short(&self.plan)
        )
    }
}

/// The recorder's public ids.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct RecorderConfig {
    pub agent: String,
    pub app_id: String,
    pub installation_id: String,
    pub bot_user_id: String,
}

pub fn err_no_recorder() -> String {
    format!(
        "not recorded: {RECORDER_FILE} names no recorder.\n  The record is a commit status, and it must be set by the one App named\n  there, which needs the \"Commit statuses: write\" permission."
    )
}

fn all_digits(s: &str) -> bool {
    !s.is_empty() && s.bytes().all(|c| c.is_ascii_digit())
}

fn agent_name_ok(s: &str) -> bool {
    let b = s.as_bytes();
    !b.is_empty()
        && b[0].is_ascii_lowercase()
        && b[1..]
            .iter()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || *c == b'-')
}

/// The non-comment, non-blank lines of a tab-separated file.
fn tsv_rows(p: &str) -> Result<Vec<Vec<String>>, String> {
    let b = unitfile::read_file(p).map_err(|(_, m)| m)?;
    Ok(String::from_utf8_lossy(&b)
        .split('\n')
        .map(exec::go_trim)
        .filter(|l| !l.is_empty() && !l.starts_with('#'))
        .map(|l| l.split('\t').map(String::from).collect())
        .collect())
}

/// Reads recorder.tsv and checks it against agents.tsv.
pub fn load_recorder(recorder_path: &str, agents_path: &str) -> Result<RecorderConfig, String> {
    let rows = tsv_rows(recorder_path)
        .map_err(|e| format!("not recorded: cannot read {RECORDER_FILE}: {e}"))?;
    if rows.is_empty() {
        return Err(err_no_recorder());
    }
    if rows.len() > 1 {
        return Err(format!(
            "not recorded: {RECORDER_FILE} must name exactly one recorder, it names {}",
            rows.len()
        ));
    }
    let r = &rows[0];
    if r.len() != 2 || !agent_name_ok(&r[0]) || !all_digits(&r[1]) {
        return Err(format!(
            "not recorded: {RECORDER_FILE} must be one line: agent name, a tab, its bot user id"
        ));
    }
    let mut cfg = RecorderConfig {
        agent: r[0].clone(),
        bot_user_id: r[1].clone(),
        ..RecorderConfig::default()
    };
    let agents = tsv_rows(agents_path)
        .map_err(|e| format!("not recorded: cannot read {AGENTS_FILE}: {e}"))?;
    for a in agents {
        if a.len() < 4 || a[0] != cfg.agent {
            continue;
        }
        if a[3] != cfg.bot_user_id {
            return Err(format!(
                "not recorded: {RECORDER_FILE} says {}'s bot user id is {}, {AGENTS_FILE} says {}",
                cfg.agent, cfg.bot_user_id, a[3]
            ));
        }
        if !all_digits(&a[1]) || !all_digits(&a[2]) {
            return Err(format!(
                "not recorded: {AGENTS_FILE} has no usable app id and installation id for {}",
                cfg.agent
            ));
        }
        cfg.app_id = a[1].clone();
        cfg.installation_id = a[2].clone();
        return Ok(cfg);
    }
    Err(format!(
        "not recorded: the recorder {} is not in {AGENTS_FILE}",
        quote(&cfg.agent)
    ))
}

/// Drops ambient GitHub credentials from an environment.
pub fn without_github_tokens(env: Vec<String>) -> Vec<String> {
    env.into_iter()
        .filter(|kv| {
            let k = kv.split_once('=').map(|(k, _)| k).unwrap_or(kv);
            !matches!(k, "GH_TOKEN" | "GITHUB_TOKEN" | "GH_ENTERPRISE_TOKEN")
        })
        .collect()
}

/// This process's environment as "KEY=value" entries.
pub fn environ() -> Vec<String> {
    std::env::vars_os()
        .map(|(k, v)| format!("{}={}", k.to_string_lossy(), v.to_string_lossy()))
        .collect()
}

/// Turns the recorder's key into a short-lived installation token.
pub type Minter<'a> = Box<dyn Fn(&RecorderConfig, &str) -> Result<String, String> + 'a>;

/// Reuses //tools/agent-app's `token` command.
pub fn agent_app_minter(agent_app: String, ctx: &Ctx) -> Minter<'_> {
    Box::new(move |cfg: &RecorderConfig, key_path: &str| {
        let mut c = Cmd::new(
            "bash",
            &[
                &agent_app,
                "token",
                &cfg.app_id,
                key_path,
                &cfg.installation_id,
            ],
        );
        c.env = Some(without_github_tokens(environ()));
        c.stdout = Io::Capture;
        c.stderr = Io::Capture;
        let (r, out) = exec::run(&c, ctx);
        if let Err(e) = r {
            return Err(format!(
                "could not get a token for {}: {e}: {}",
                cfg.agent,
                exec::trim_space(&out.stderr)
            ));
        }
        let tok = exec::trim_space(&out.stdout);
        if tok.is_empty() {
            return Err(format!(
                "could not get a token for {}: empty token",
                cfg.agent
            ));
        }
        Ok(tok)
    })
}

/// Writes the record. Its only credential is the minted token.
pub struct StatusRecorder<'a> {
    pub config_path: String,
    pub agents_path: String,
    pub key_dir: String,
    pub mint: Minter<'a>,
    pub api_base: String,
}

fn short512(b: &[u8]) -> String {
    if b.len() > 512 {
        return String::from_utf8_lossy(&b[..512]).into_owned() + "...";
    }
    String::from_utf8_lossy(b).into_owned()
}

impl StatusRecorder<'_> {
    pub fn record(&self, r: &Record) -> Result<(), String> {
        let cfg = load_recorder(&self.config_path, &self.agents_path)?;
        let key_path = path::join(&[&self.key_dir, &format!("{}.pem", cfg.agent)]);
        if std::fs::metadata(&key_path).is_err() {
            return Err(format!(
                "not recorded: the recorder is {}, but its private key is not at {key_path} (bazel run //tools/sync-env-secrets:agent-keys-pull)",
                cfg.agent
            ));
        }
        let token = (self.mint)(&cfg, &key_path).map_err(|e| format!("not recorded: {e}"))?;
        let mut body = BTreeMap::new();
        body.insert("state", "success".to_string());
        body.insert("context", STATUS_CONTEXT.to_string());
        body.insert("description", r.description());
        body.insert("target_url", r.target_url.clone());
        let body = json::marshal(&body);
        let url = format!(
            "{}/repos/{REPO_SLUG}/statuses/{}",
            self.api_base.trim_end_matches('/'),
            r.head
        );
        let headers = [
            ("Authorization", format!("Bearer {token}")),
            ("Accept", "application/vnd.github+json".to_string()),
            ("X-GitHub-Api-Version", "2022-11-28".to_string()),
        ];
        let resp =
            http::post(&url, &headers, body.as_bytes(), Duration::from_secs(30)).map_err(|e| {
                format!(
                    "not recorded: GitHub could not be reached: Post {}: {e}",
                    quote(&url)
                )
            })?;
        let mut msg = resp.body;
        msg.truncate(64 * 1024);
        if resp.status != 201 {
            let hint = if resp.status == 422 {
                " (has this commit been pushed?)"
            } else {
                ""
            };
            return Err(format!(
                "not recorded: GitHub answered {}{hint}: {}",
                resp.status,
                exec::go_trim(&short512(&msg))
            ));
        }
        // Check GitHub's own account of who set it, rather than assume.
        let (mut id, mut login) = (String::new(), String::new());
        let decoded = json::parse(&msg).and_then(|v| {
            let mut d = Dec::new();
            d.object(&v, "", "struct { Creator struct { ID json.Number \"json:\\\"id\\\"\"; Login string \"json:\\\"login\\\"\" } \"json:\\\"creator\\\"\" }", &["creator"], |d, _, c| {
                d.object(c, "", "struct { ID json.Number \"json:\\\"id\\\"\"; Login string \"json:\\\"login\\\"\" }", &["id", "login"], |d, name, x| {
                    if name == "login" {
                        d.string(x, &mut login);
                    } else {
                        match x {
                            json::GoValue::Num(t, _) => id = t.clone(),
                            json::GoValue::Str(s) => id = s.clone(),
                            json::GoValue::Null => {}
                            _ => d.string(&json::GoValue::Bool(false), &mut String::new()),
                        }
                    }
                });
            });
            d.finish()
        });
        if decoded.is_err() || id != cfg.bot_user_id {
            return Err(format!(
                "the status was written, but GitHub says it was set by {} (id {id}), not the recorder {} (id {}). Do not trust it",
                quote(&login),
                cfg.agent,
                cfg.bot_user_id
            ));
        }
        Ok(())
    }
}
