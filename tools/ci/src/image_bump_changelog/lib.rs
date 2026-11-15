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

//! image_bump_changelog — resolves `org.opencontainers.image.revision` for an
//! old and new container digest from an OCI/Docker v2 registry (including
//! multi-arch indexes) and prints a Markdown changelog summary.
//!
//! Std-only (+ `shell_compat`) so `.github/actions/build-ci-tool` compiles it on
//! runners without Bazel.

use shell_compat::{env, err, out};
use std::collections::BTreeSet;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Output, Stdio};
use std::sync::atomic::{AtomicUsize, Ordering};

const DEFAULT_REPO: &str = "VitruvianSoftware/vitruvian-core";
const DEFAULT_BASE_REF: &str = "origin/main";
const MAX_UPSTREAM_COMMITS: usize = 50;
const MAX_TAG_PAGES: usize = 20;
const TAG_HEAD_CONCURRENCY: usize = 8;

const USAGE: &str = "image-bump-changelog: usage: image-bump-changelog \
--image <registry/repo> \
(--old-digest <digest> --new-digest <digest> | --values-file <path> [--base-ref <ref>]) \
[--path <dir>]... [--shared-path <path>]... [--repo <owner/name>] [--upstream]\n";

const ACCEPT_ANY: &str = "application/vnd.oci.image.index.v1+json, \
application/vnd.docker.distribution.manifest.list.v2+json, \
application/vnd.oci.image.manifest.v1+json, \
application/vnd.docker.distribution.manifest.v2+json";

const ACCEPT_MANIFEST: &str = "application/vnd.oci.image.manifest.v1+json, \
application/vnd.docker.distribution.manifest.v2+json";

#[derive(Debug, PartialEq, Eq)]
struct Config {
    image: String,
    old_digest: Option<String>,
    new_digest: Option<String>,
    values_file: Option<String>,
    base_ref: String,
    paths: Vec<String>,
    shared_paths: Vec<String>,
    repo: String,
    upstream: bool,
}

#[derive(Debug, PartialEq, Eq)]
pub struct CommitInfo {
    pub sha: String,
    pub subject: String,
}

#[derive(Debug, PartialEq, Eq)]
pub enum ChangelogInput<'a> {
    Local {
        repo: &'a str,
        app_paths: &'a [String],
        commits: Option<&'a [CommitInfo]>,
        shared_commit_count: usize,
    },
    Upstream {
        repo: &'a str,
        commits: Option<&'a [CommitInfo]>,
        total_upstream_commits: usize,
    },
}

/// CLI entrypoint. Returns `0` on success, `1` on runtime/registry failure,
/// `2` on usage error.
pub fn run(args: &[String]) -> i32 {
    if args.is_empty() {
        err(USAGE.as_bytes());
        return 2;
    }
    if args.iter().any(|a| a == "-h" || a == "--help") {
        out(USAGE.as_bytes());
        return 0;
    }

    let cfg = match parse_args(args) {
        Ok(c) => c,
        Err(msg) => {
            err(format!("image-bump-changelog: {msg}\n{USAGE}").as_bytes());
            return 2;
        }
    };

    match execute(&cfg) {
        Ok(md) => {
            out(md.as_bytes());
            0
        }
        Err(reason) => {
            let line = single_line(&reason);
            err(format!("image-bump-changelog: {line}\n").as_bytes());
            1
        }
    }
}

fn parse_args(args: &[String]) -> Result<Config, String> {
    let mut image: Option<String> = None;
    let mut old_digest: Option<String> = None;
    let mut has_old_flag = false;
    let mut new_digest: Option<String> = None;
    let mut values_file: Option<String> = None;
    let mut base_ref = DEFAULT_BASE_REF.to_string();
    let mut paths: Vec<String> = Vec::new();
    let mut shared_paths: Vec<String> = Vec::new();
    let mut repo: Option<String> = None;
    let mut upstream = false;

    let mut i = 0;
    while i < args.len() {
        let flag = args[i].as_str();
        let next_val = |idx: &mut usize, name: &str| -> Result<String, String> {
            *idx += 1;
            args.get(*idx)
                .cloned()
                .ok_or_else(|| format!("missing value for {name}"))
        };
        match flag {
            "--image" => image = Some(next_val(&mut i, "--image")?),
            "--old-digest" => {
                has_old_flag = true;
                let v = next_val(&mut i, "--old-digest")?;
                old_digest = if v.trim().is_empty() {
                    None
                } else {
                    Some(normalize_digest(&v)?)
                };
            }
            "--new-digest" => {
                let v = next_val(&mut i, "--new-digest")?;
                new_digest = Some(normalize_digest(&v)?);
            }
            "--values-file" => values_file = Some(next_val(&mut i, "--values-file")?),
            "--base-ref" => base_ref = next_val(&mut i, "--base-ref")?,
            "--path" => {
                let p = next_val(&mut i, "--path")?;
                let trimmed = p.trim_end_matches('/').to_string();
                if trimmed.is_empty() {
                    return Err("--path must not be empty".to_string());
                }
                paths.push(trimmed);
            }
            "--shared-path" => {
                let p = next_val(&mut i, "--shared-path")?;
                let trimmed = p.trim_end_matches('/').to_string();
                if trimmed.is_empty() {
                    return Err("--shared-path must not be empty".to_string());
                }
                shared_paths.push(trimmed);
            }
            "--repo" => repo = Some(next_val(&mut i, "--repo")?),
            "--upstream" => upstream = true,
            other => return Err(format!("unknown argument '{other}'")),
        }
        i += 1;
    }

    let image = image.ok_or_else(|| "--image is required".to_string())?;
    if values_file.is_some() && (has_old_flag || new_digest.is_some()) {
        return Err(
            "--values-file cannot be combined with --old-digest or --new-digest".to_string(),
        );
    }
    if values_file.is_none() && new_digest.is_none() {
        return Err(
            "pass either --new-digest (and optional --old-digest) or --values-file".to_string(),
        );
    }
    if !upstream && paths.is_empty() {
        return Err("at least one --path is required unless --upstream is set".to_string());
    }
    let repo = match repo {
        Some(r) if !r.trim().is_empty() => r.trim().to_string(),
        Some(_) => return Err("--repo must not be empty".to_string()),
        None => {
            if upstream {
                return Err("--repo <owner/name> is required when --upstream is set".to_string());
            }
            DEFAULT_REPO.to_string()
        }
    };

    Ok(Config {
        image,
        old_digest,
        new_digest,
        values_file,
        base_ref,
        paths,
        shared_paths,
        repo,
        upstream,
    })
}

fn execute(cfg: &Config) -> Result<String, String> {
    let (registry, repository) = parse_image_ref(&cfg.image)?;
    let (old_digest, new_digest) = resolve_digests(cfg)?;

    let mut auth = RegistryAuth::new(&registry, &repository);
    let new_rev = auth.resolve_revision(&new_digest)?;
    let old_rev = match old_digest {
        Some(ref old) if old == &new_digest => new_rev.clone(),
        Some(ref old) => auth.resolve_revision(old)?,
        None => None,
    };

    if cfg.upstream {
        let mut commits_storage: Option<Vec<CommitInfo>> = None;
        let mut total = 0usize;
        if let (Some(ref old_r), Some(ref new_r)) = (&old_rev, &new_rev) {
            if old_r != new_r {
                if let Some((commits, count)) = fetch_upstream_compare(&cfg.repo, old_r, new_r) {
                    total = count;
                    commits_storage = Some(commits);
                }
            }
        }
        return Ok(render_markdown(
            old_rev.as_deref(),
            new_rev.as_deref(),
            ChangelogInput::Upstream {
                repo: &cfg.repo,
                commits: commits_storage.as_deref(),
                total_upstream_commits: total,
            },
        ));
    }

    let shared_paths = if cfg.shared_paths.is_empty() {
        default_shared_paths(&cfg.paths)
    } else {
        cfg.shared_paths.clone()
    };

    let mut app_commits_storage: Option<Vec<CommitInfo>> = None;
    let mut shared_count = 0usize;

    if let (Some(ref old_r), Some(ref new_r)) = (&old_rev, &new_rev) {
        if old_r != new_r && git_commit_exists(old_r) && git_commit_exists(new_r) {
            let app_commits = git_commits_in_range(old_r, new_r, &cfg.paths)?;
            let app_shas: BTreeSet<&str> = app_commits.iter().map(|c| c.sha.as_str()).collect();
            let shared_commits = if shared_paths.is_empty() {
                Vec::new()
            } else {
                git_commits_in_range(old_r, new_r, &shared_paths)?
            };
            let mut seen_shared = BTreeSet::new();
            for c in &shared_commits {
                if !app_shas.contains(c.sha.as_str()) {
                    seen_shared.insert(c.sha.as_str());
                }
            }
            shared_count = seen_shared.len();
            app_commits_storage = Some(app_commits);
        }
    }

    Ok(render_markdown(
        old_rev.as_deref(),
        new_rev.as_deref(),
        ChangelogInput::Local {
            repo: &cfg.repo,
            app_paths: &cfg.paths,
            commits: app_commits_storage.as_deref(),
            shared_commit_count: shared_count,
        },
    ))
}

fn resolve_digests(cfg: &Config) -> Result<(Option<String>, String), String> {
    if let Some(ref vf) = cfg.values_file {
        let new_text = fs::read_to_string(vf).map_err(|e| format!("failed to read {vf}: {e}"))?;
        let new_d = extract_digest_from_manifest_text(&new_text)
            .ok_or_else(|| format!("no sha256 digest found in {vf}"))?;
        let old_d = git_show_file(&cfg.base_ref, vf)
            .as_deref()
            .and_then(extract_digest_from_manifest_text);
        return Ok((old_d, new_d));
    }
    let new_d = cfg
        .new_digest
        .clone()
        .ok_or_else(|| "missing --new-digest".to_string())?;
    Ok((cfg.old_digest.clone(), new_d))
}

/// Splits an image reference such as `ghcr.io/VitruvianSoftware/foo:main@sha256:...`
/// into `(registry, repository)` in lowercase repository form where needed.
pub fn parse_image_ref(image: &str) -> Result<(String, String), String> {
    let trimmed = image.trim();
    let slash = trimmed
        .find('/')
        .ok_or_else(|| format!("invalid image '{image}': expected <registry>/<repository>"))?;
    let registry = &trimmed[..slash];
    let mut repo = &trimmed[slash + 1..];
    if let Some(at) = repo.find('@') {
        repo = &repo[..at];
    }
    if let Some(colon) = repo.find(':') {
        repo = &repo[..colon];
    }
    if registry.is_empty()
        || repo.is_empty()
        || registry.chars().any(char::is_whitespace)
        || repo.chars().any(char::is_whitespace)
    {
        return Err(format!(
            "invalid image '{image}': expected <registry>/<repository>"
        ));
    }
    Ok((registry.to_string(), repo.to_string()))
}

/// Extracts and validates a `sha256:<64-hex>` digest from either `sha256:...`
/// or `<tag>@sha256:...`.
pub fn normalize_digest(raw: &str) -> Result<String, String> {
    let trimmed = raw.trim();
    let candidate = match trimmed.rsplit_once('@') {
        Some((_, rhs)) => rhs,
        None => trimmed,
    };
    let hex = candidate
        .strip_prefix("sha256:")
        .ok_or_else(|| format!("invalid digest '{raw}': expected sha256:<64 hex chars>"))?;
    if hex.len() != 64 || !hex.bytes().all(|b| b.is_ascii_hexdigit()) {
        return Err(format!(
            "invalid digest '{raw}': expected 64 hex characters after sha256:"
        ));
    }
    Ok(format!("sha256:{}", hex.to_ascii_lowercase()))
}

/// Extracts the first non-comment `sha256:<64-hex>` digest from a GitOps YAML file.
pub fn extract_digest_from_manifest_text(text: &str) -> Option<String> {
    for raw_line in text.lines() {
        let stripped = strip_yaml_comment(raw_line);
        let mut search_from = 0;
        while let Some(pos) = stripped[search_from..].find("sha256:") {
            let start = search_from + pos + "sha256:".len();
            let rest = &stripped[start..];
            if rest.len() >= 64 {
                let (hex, after) = rest.split_at(64);
                let boundary_ok = after
                    .chars()
                    .next()
                    .map_or(true, |c| !c.is_ascii_hexdigit());
                if boundary_ok && hex.bytes().all(|b| b.is_ascii_hexdigit()) {
                    return Some(format!("sha256:{}", hex.to_ascii_lowercase()));
                }
            }
            search_from = start;
        }
    }
    None
}

fn strip_yaml_comment(line: &str) -> &str {
    let trim_start = line.trim_start();
    if trim_start.starts_with('#') {
        return "";
    }
    if let Some(pos) = line.find(" #") {
        return &line[..pos];
    }
    line
}

pub fn default_shared_paths(app_paths: &[String]) -> Vec<String> {
    let mut out = vec![
        "MODULE.bazel".to_string(),
        "MODULE.bazel.lock".to_string(),
        ".bazelversion".to_string(),
        "tools/toolchains".to_string(),
    ];
    for p in app_paths {
        if let Some(app_name) = Path::new(p).file_name().and_then(|s| s.to_str()) {
            let wf = format!(".github/workflows/{app_name}-image.yaml");
            if !out.contains(&wf) {
                out.push(wf);
            }
        }
        let base = Path::new(p);
        if base.join("rs/Cargo.toml").is_file() || base.join("Cargo.toml").is_file() {
            for extra in ["Cargo.toml", "Cargo.lock"] {
                if !out.iter().any(|x| x == extra) {
                    out.push(extra.to_string());
                }
            }
        }
        if base.join("package.json").is_file() || p.starts_with("apps/web/") {
            for extra in [
                ".nvmrc",
                "package.json",
                "pnpm-lock.yaml",
                "pnpm-workspace.yaml",
            ] {
                if !out.iter().any(|x| x == extra) {
                    out.push(extra.to_string());
                }
            }
        }
    }
    out
}

fn normalize_revision(raw: Option<&str>) -> Option<String> {
    let s = raw?.trim();
    if s.is_empty() || s.eq_ignore_ascii_case("unknown") || s.eq_ignore_ascii_case("null") {
        return None;
    }
    if (7..=40).contains(&s.len()) && s.bytes().all(|b| b.is_ascii_hexdigit()) {
        Some(s.to_ascii_lowercase())
    } else {
        None
    }
}

fn short7(sha: &str) -> &str {
    &sha[..7.min(sha.len())]
}

// ---------------------------------------------------------------------------
// Registry client & OCI manifest/config parsing
// ---------------------------------------------------------------------------

struct RegistryAuth<'a> {
    registry: &'a str,
    repository: &'a str,
    bearer_token: Option<String>,
    gh_token: Option<String>,
    tried_gh_token: bool,
    cached_hex_tags: Option<Vec<String>>,
    tag_digest_cache: Vec<(String, Option<String>)>,
}

impl<'a> RegistryAuth<'a> {
    fn new(registry: &'a str, repository: &'a str) -> Self {
        let gh_token = env_string("GITHUB_TOKEN").or_else(|| env_string("GH_TOKEN"));
        Self {
            registry,
            repository,
            bearer_token: None,
            gh_token,
            tried_gh_token: false,
            cached_hex_tags: None,
            tag_digest_cache: Vec::new(),
        }
    }

    fn resolve_revision(&mut self, digest: &str) -> Result<Option<String>, String> {
        self.ensure_initial_token()?;

        let manifest_url = format!(
            "https://{}/v2/{}/manifests/{}",
            self.registry, self.repository, digest
        );
        let top_bytes = self.get_with_auth_retry(&manifest_url, ACCEPT_ANY)?;
        let top_json = parse_json(&top_bytes)
            .map_err(|e| format!("invalid manifest JSON for {digest}: {e}"))?;

        let (platform_manifest, index_rev) = match select_platform_manifest(&top_json)? {
            ManifestResolution::PlatformDigest {
                digest: plat_digest,
                fallback_revision,
            } => {
                let plat_url = format!(
                    "https://{}/v2/{}/manifests/{}",
                    self.registry, self.repository, plat_digest
                );
                let plat_bytes = self.get_with_auth_retry(&plat_url, ACCEPT_MANIFEST)?;
                let plat_json = parse_json(&plat_bytes).map_err(|e| {
                    format!("invalid platform manifest JSON for {plat_digest}: {e}")
                })?;
                (plat_json, fallback_revision)
            }
            ManifestResolution::SingleManifest => (top_json, None),
        };

        let config_digest = extract_config_digest(&platform_manifest)?;
        let blob_url = format!(
            "https://{}/v2/{}/blobs/{}",
            self.registry, self.repository, config_digest
        );
        let config_bytes = self.get_with_auth_retry(
            &blob_url,
            "application/vnd.oci.image.config.v1+json, application/vnd.docker.container.image.v1+json, application/json",
        )?;
        let config_json = parse_json(&config_bytes)
            .map_err(|e| format!("invalid config JSON for {config_digest}: {e}"))?;

        let rev = extract_revision_from_config(&config_json)
            .or_else(|| extract_revision_annotation(&platform_manifest))
            .or(index_rev);
        if rev.is_some() {
            return Ok(rev);
        }
        Ok(self.resolve_revision_from_tags(digest))
    }

    fn load_40_hex_tags(&mut self) -> Vec<String> {
        if let Some(ref cached) = self.cached_hex_tags {
            return cached.clone();
        }
        let mut all_tags = Vec::new();
        let mut seen = BTreeSet::new();
        let mut url = format!(
            "https://{}/v2/{}/tags/list?n=1000",
            self.registry, self.repository
        );
        for _ in 0..MAX_TAG_PAGES {
            let Ok((body, hdrs)) = self.get_with_headers_and_auth_retry(&url, "application/json")
            else {
                break;
            };
            let Ok(json) = parse_json(&body) else {
                break;
            };
            for tag in extract_40_hex_tags(&json) {
                if seen.insert(tag.clone()) {
                    all_tags.push(tag);
                }
            }
            let Some(next_url) = parse_next_link_url(&hdrs, self.registry) else {
                break;
            };
            if next_url == url {
                break;
            }
            url = next_url;
        }
        self.cached_hex_tags = Some(all_tags.clone());
        all_tags
    }

    fn resolve_revision_from_tags(&mut self, target_digest: &str) -> Option<String> {
        if let Some((tag, _)) = self
            .tag_digest_cache
            .iter()
            .find(|(_, d)| d.as_deref() == Some(target_digest))
        {
            return Some(tag.clone());
        }

        let all_tags = self.load_40_hex_tags();
        let unprobed: Vec<String> = all_tags
            .into_iter()
            .rev()
            .filter(|t| !self.tag_digest_cache.iter().any(|(cached, _)| cached == t))
            .collect();
        let secrets = self.auth_secrets();

        for chunk in unprobed.chunks(TAG_HEAD_CONCURRENCY) {
            let results: Vec<(String, Option<String>)> = {
                let auth_ref: &RegistryAuth<'_> = &*self;
                let secrets_ref: &[String] = &secrets;
                std::thread::scope(|s| {
                    let handles: Vec<_> = chunk
                        .iter()
                        .map(|tag| {
                            let url = format!(
                                "https://{}/v2/{}/manifests/{}",
                                auth_ref.registry, auth_ref.repository, tag
                            );
                            s.spawn(move || {
                                let digest = auth_ref
                                    .do_head(&url, ACCEPT_ANY, secrets_ref)
                                    .ok()
                                    .and_then(|hdrs| extract_docker_content_digest(&hdrs));
                                (tag.clone(), digest)
                            })
                        })
                        .collect();
                    handles
                        .into_iter()
                        .map(|h| h.join().unwrap_or_else(|_| (String::new(), None)))
                        .collect()
                })
            };
            let mut matched = None;
            for (tag, maybe_digest) in results {
                if tag.is_empty() {
                    continue;
                }
                if matched.is_none() && maybe_digest.as_deref() == Some(target_digest) {
                    matched = Some(tag.clone());
                }
                self.tag_digest_cache.push((tag, maybe_digest));
            }
            if matched.is_some() {
                return matched;
            }
        }
        None
    }

    fn ensure_initial_token(&mut self) -> Result<(), String> {
        if self.bearer_token.is_some() {
            return Ok(());
        }
        let token_url = format!(
            "https://{}/token?scope=repository:{}:pull&service={}",
            self.registry, self.repository, self.registry
        );
        match curl_get(&token_url, &[], &[]) {
            Ok(body) => {
                if let Some(tok) = extract_token(&body) {
                    self.bearer_token = Some(tok);
                    return Ok(());
                }
            }
            Err(anon_err) => {
                if self.gh_token.is_none() {
                    return Err(format!("registry token fetch failed: {anon_err}"));
                }
            }
        }
        if self.try_upgrade_to_gh_token(&token_url)? {
            return Ok(());
        }
        Err("registry returned an empty pull token".to_string())
    }

    fn try_upgrade_to_gh_token(&mut self, token_url: &str) -> Result<bool, String> {
        if self.tried_gh_token {
            return Ok(false);
        }
        let Some(ref gh) = self.gh_token else {
            return Ok(false);
        };
        self.tried_gh_token = true;
        let raw_creds = format!("x-access-token:{gh}");
        let b64 = base64_encode(raw_creds.as_bytes());
        let auth_header = format!("Authorization: Basic {b64}");
        let mut secrets: Vec<&str> = Vec::new();
        secrets.push(gh.as_str());
        secrets.push(b64.as_str());
        if let Ok(body) = curl_get(token_url, &[&auth_header], &secrets) {
            if let Some(tok) = extract_token(&body) {
                self.bearer_token = Some(tok);
                return Ok(true);
            }
        }
        // Fallback when registry accepts GitHub token directly as Bearer.
        self.bearer_token = Some(gh.clone());
        Ok(true)
    }

    fn auth_secrets(&self) -> Vec<String> {
        let mut secrets = Vec::new();
        if let Some(ref gh) = self.gh_token {
            secrets.push(gh.clone());
        }
        if let Some(ref tok) = self.bearer_token {
            secrets.push(tok.clone());
        }
        secrets
    }

    fn with_auth_retry<T>(
        &mut self,
        op: impl Fn(&Self, &[String]) -> Result<T, String>,
    ) -> Result<T, String> {
        let secrets = self.auth_secrets();
        let first_err = match op(self, &secrets) {
            Ok(val) => return Ok(val),
            Err(e) => e,
        };
        if !self.tried_gh_token && self.gh_token.is_some() {
            let token_url = format!(
                "https://{}/token?scope=repository:{}:pull&service={}",
                self.registry, self.repository, self.registry
            );
            if self.try_upgrade_to_gh_token(&token_url)? {
                let retry_secrets = self.auth_secrets();
                if let Ok(val) = op(self, &retry_secrets) {
                    return Ok(val);
                }
            }
        }
        Err(first_err)
    }

    fn get_with_auth_retry(&mut self, url: &str, accept: &str) -> Result<Vec<u8>, String> {
        self.with_auth_retry(|auth, secrets| auth.do_get(url, accept, secrets))
    }

    fn get_with_headers_and_auth_retry(
        &mut self,
        url: &str,
        accept: &str,
    ) -> Result<(Vec<u8>, Vec<u8>), String> {
        self.with_auth_retry(|auth, secrets| auth.do_get_with_headers(url, accept, secrets))
    }

    fn call_with_headers<T>(
        &self,
        accept: &str,
        secrets: &[String],
        exec: impl FnOnce(&[&str], &[&str]) -> Result<T, String>,
    ) -> Result<T, String> {
        let accept_hdr = format!("Accept: {accept}");
        let mut headers = vec![accept_hdr.as_str()];
        let auth_hdr;
        if let Some(ref tok) = self.bearer_token {
            auth_hdr = format!("Authorization: Bearer {tok}");
            headers.push(auth_hdr.as_str());
        }
        let scrub_refs: Vec<&str> = secrets.iter().map(String::as_str).collect();
        exec(&headers, &scrub_refs)
    }

    fn do_get(&self, url: &str, accept: &str, secrets: &[String]) -> Result<Vec<u8>, String> {
        self.call_with_headers(accept, secrets, |hdrs, scrub| curl_get(url, hdrs, scrub))
    }

    fn do_get_with_headers(
        &self,
        url: &str,
        accept: &str,
        secrets: &[String],
    ) -> Result<(Vec<u8>, Vec<u8>), String> {
        self.call_with_headers(accept, secrets, |hdrs, scrub| {
            curl_get_with_headers(url, hdrs, scrub)
        })
    }

    fn do_head(&self, url: &str, accept: &str, secrets: &[String]) -> Result<Vec<u8>, String> {
        self.call_with_headers(accept, secrets, |hdrs, scrub| curl_head(url, hdrs, scrub))
    }
}

fn extract_token(bytes: &[u8]) -> Option<String> {
    let json = parse_json(bytes).ok()?;
    let tok = json
        .get("token")
        .or_else(|| json.get("access_token"))
        .and_then(JsonValue::as_str)?;
    if tok.is_empty() {
        None
    } else {
        Some(tok.to_string())
    }
}

#[derive(Debug, PartialEq, Eq)]
pub enum ManifestResolution {
    SingleManifest,
    PlatformDigest {
        digest: String,
        fallback_revision: Option<String>,
    },
}

/// Decides whether a top-level OCI/Docker manifest JSON is a single-platform
/// manifest or a multi-arch index/manifest-list, skipping attestation manifests
/// when selecting the first runnable platform entry.
pub fn select_platform_manifest(json: &JsonValue) -> Result<ManifestResolution, String> {
    let Some(manifests) = json.get("manifests").and_then(JsonValue::as_array) else {
        return Ok(ManifestResolution::SingleManifest);
    };
    let index_rev = extract_revision_annotation(json);

    let is_attestation_or_unknown = |entry: &JsonValue| -> bool {
        if let Some(ref_type) = entry
            .get("annotations")
            .and_then(|a| a.get("vnd.docker.reference.type"))
            .and_then(JsonValue::as_str)
        {
            if ref_type == "attestation-manifest" {
                return true;
            }
        }
        if let Some(plat) = entry.get("platform") {
            let os = plat.get("os").and_then(JsonValue::as_str).unwrap_or("");
            let arch = plat
                .get("architecture")
                .and_then(JsonValue::as_str)
                .unwrap_or("");
            if os == "unknown" || arch == "unknown" {
                return true;
            }
        }
        false
    };

    let mut chosen: Option<&JsonValue> = None;
    for entry in manifests {
        if is_attestation_or_unknown(entry) {
            continue;
        }
        let has_digest = entry
            .get("digest")
            .and_then(JsonValue::as_str)
            .map_or(false, |d| d.starts_with("sha256:"));
        if !has_digest {
            continue;
        }
        if chosen.is_none() {
            chosen = Some(entry);
        }
        let os = entry
            .get("platform")
            .and_then(|p| p.get("os"))
            .and_then(JsonValue::as_str);
        let arch = entry
            .get("platform")
            .and_then(|p| p.get("architecture"))
            .and_then(JsonValue::as_str);
        if os == Some("linux") && arch == Some("amd64") {
            chosen = Some(entry);
            break;
        }
    }

    let entry = chosen
        .ok_or_else(|| "multi-arch index contains no runnable platform manifest".to_string())?;
    let digest = entry
        .get("digest")
        .and_then(JsonValue::as_str)
        .ok_or_else(|| "platform manifest entry missing digest".to_string())?;
    let entry_rev = extract_revision_annotation(entry).or(index_rev);
    Ok(ManifestResolution::PlatformDigest {
        digest: digest.to_string(),
        fallback_revision: entry_rev,
    })
}

pub fn extract_config_digest(manifest: &JsonValue) -> Result<String, String> {
    let raw = manifest
        .get("config")
        .and_then(|c| c.get("digest"))
        .and_then(JsonValue::as_str)
        .ok_or_else(|| "image manifest missing config.digest".to_string())?;
    normalize_digest(raw)
}

pub fn extract_revision_from_config(config: &JsonValue) -> Option<String> {
    let cfg_obj = config.get("config")?;
    let labels = cfg_obj.get("Labels").or_else(|| cfg_obj.get("labels"))?;
    let raw = labels
        .get("org.opencontainers.image.revision")
        .and_then(JsonValue::as_str);
    normalize_revision(raw)
}

fn extract_revision_annotation(val: &JsonValue) -> Option<String> {
    let ann = val.get("annotations")?;
    let raw = ann
        .get("org.opencontainers.image.revision")
        .and_then(JsonValue::as_str);
    normalize_revision(raw)
}

/// Returns `true` when `tag` is an exact 40-character lowercase hex git SHA.
pub fn is_40_lowercase_hex(tag: &str) -> bool {
    tag.len() == 40 && tag.bytes().all(|b| matches!(b, b'0'..=b'9' | b'a'..=b'f'))
}

/// Filters a `/v2/<name>/tags/list` JSON body down to 40-character lowercase
/// hex commit tags, ignoring floating, short-sha, and non-hex tags.
pub fn extract_40_hex_tags(json: &JsonValue) -> Vec<String> {
    let Some(tags) = json.get("tags").and_then(JsonValue::as_array) else {
        return Vec::new();
    };
    tags.iter()
        .filter_map(JsonValue::as_str)
        .filter(|t| is_40_lowercase_hex(t))
        .map(str::to_string)
        .collect()
}

/// Extracts the normalized `sha256:...` digest from the last
/// `Docker-Content-Digest` HTTP response header.
pub fn extract_docker_content_digest(headers_raw: &[u8]) -> Option<String> {
    let text = String::from_utf8_lossy(headers_raw);
    let mut found = None;
    for line in text.lines() {
        let line = line.trim_end_matches('\r');
        if let Some((name, value)) = line.split_once(':') {
            if name.trim().eq_ignore_ascii_case("docker-content-digest") {
                let cleaned = value.trim().trim_matches('"');
                if let Ok(digest) = normalize_digest(cleaned) {
                    found = Some(digest);
                }
            }
        }
    }
    found
}

/// Parses an RFC 5988 `Link: <...>; rel="next"` header from registry HTTP
/// response headers and resolves relative targets against `registry`.
pub fn parse_next_link_url(headers_raw: &[u8], registry: &str) -> Option<String> {
    let text = String::from_utf8_lossy(headers_raw);
    for line in text.lines() {
        let line = line.trim_end_matches('\r');
        let Some((name, value)) = line.split_once(':') else {
            continue;
        };
        if !name.trim().eq_ignore_ascii_case("link") {
            continue;
        }
        let mut rest = value.trim();
        while let Some(open) = rest.find('<') {
            let after_open = &rest[open + 1..];
            let Some(close) = after_open.find('>') else {
                break;
            };
            let target = after_open[..close].trim();
            let after_close = &after_open[close + 1..];
            let (params_part, remainder) = match after_close.find(',') {
                Some(comma) => (&after_close[..comma], &after_close[comma + 1..]),
                None => (after_close, ""),
            };
            let is_next = params_part.split(';').any(|param| {
                if let Some((k, v)) = param.trim().split_once('=') {
                    k.trim().eq_ignore_ascii_case("rel")
                        && v.trim()
                            .trim_matches('"')
                            .split_whitespace()
                            .any(|tok| tok.eq_ignore_ascii_case("next"))
                } else {
                    false
                }
            });
            if is_next && !target.is_empty() {
                if target.starts_with("https://") || target.starts_with("http://") {
                    return Some(target.to_string());
                }
                if target.starts_with('/') {
                    return Some(format!("https://{registry}{target}"));
                }
                return Some(format!("https://{registry}/{target}"));
            }
            rest = remainder;
        }
    }
    None
}

// ---------------------------------------------------------------------------
// Upstream GitHub compare API
// ---------------------------------------------------------------------------

fn fetch_upstream_compare(
    repo: &str,
    old_rev: &str,
    new_rev: &str,
) -> Option<(Vec<CommitInfo>, usize)> {
    let url = format!("https://api.github.com/repos/{repo}/compare/{old_rev}...{new_rev}");
    let gh = env_string("GITHUB_TOKEN").or_else(|| env_string("GH_TOKEN"));
    let mut hdrs = vec!["Accept: application/vnd.github+json"];
    let auth_hdr;
    let mut secrets = Vec::new();
    if let Some(ref tok) = gh {
        auth_hdr = format!("Authorization: Bearer {tok}");
        hdrs.push(auth_hdr.as_str());
        secrets.push(tok.as_str());
    }
    let body = curl_get(&url, &hdrs, &secrets).ok()?;
    let json = parse_json(&body).ok()?;
    parse_upstream_compare_json(&json)
}

pub fn parse_upstream_compare_json(json: &JsonValue) -> Option<(Vec<CommitInfo>, usize)> {
    let commits_arr = json.get("commits").and_then(JsonValue::as_array)?;
    let mut all = Vec::new();
    for item in commits_arr {
        let Some(sha) = item.get("sha").and_then(JsonValue::as_str) else {
            continue;
        };
        let msg = item
            .get("commit")
            .and_then(|c| c.get("message"))
            .and_then(JsonValue::as_str)
            .unwrap_or("");
        let subject = msg.lines().next().unwrap_or("").trim().to_string();
        all.push(CommitInfo {
            sha: sha.to_string(),
            subject,
        });
    }
    let total = json
        .get("total_commits")
        .and_then(JsonValue::as_number_usize)
        .unwrap_or(all.len());
    Some((all, total))
}

// ---------------------------------------------------------------------------
// Local Git helpers
// ---------------------------------------------------------------------------

fn git_show_file(git_ref: &str, path: &str) -> Option<String> {
    let spec = format!("{git_ref}:{path}");
    let o = Command::new("git")
        .args(["show", &spec])
        .stdin(Stdio::null())
        .output()
        .ok()?;
    if !o.status.success() {
        return None;
    }
    Some(String::from_utf8_lossy(&o.stdout).into_owned())
}

fn git_commit_exists(rev: &str) -> bool {
    let spec = format!("{rev}^{{commit}}");
    Command::new("git")
        .args(["rev-parse", "--verify", "--quiet", &spec])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map_or(false, |s| s.success())
}

fn git_commits_in_range(
    old_rev: &str,
    new_rev: &str,
    paths: &[String],
) -> Result<Vec<CommitInfo>, String> {
    if paths.is_empty() {
        return Ok(Vec::new());
    }
    let range = format!("{old_rev}..{new_rev}");
    let mut cmd = Command::new("git");
    cmd.args(["log", "--no-merges", "--format=%H\x09%s", &range, "--"]);
    for p in paths {
        cmd.arg(p);
    }
    cmd.stdin(Stdio::null());
    let o = cmd
        .output()
        .map_err(|e| format!("failed to run git log: {e}"))?;
    if !o.status.success() {
        let stderr = String::from_utf8_lossy(&o.stderr);
        return Err(format!("git log failed: {}", single_line(&stderr)));
    }
    let text = String::from_utf8_lossy(&o.stdout);
    let mut out = Vec::new();
    for line in text.lines() {
        if line.is_empty() {
            continue;
        }
        if let Some((sha, subject)) = line.split_once('\t') {
            out.push(CommitInfo {
                sha: sha.trim().to_string(),
                subject: subject.trim().to_string(),
            });
        }
    }
    Ok(out)
}

// ---------------------------------------------------------------------------
// Markdown renderer
// ---------------------------------------------------------------------------

pub fn render_markdown(
    old_rev: Option<&str>,
    new_rev: Option<&str>,
    input: ChangelogInput<'_>,
) -> String {
    match input {
        ChangelogInput::Local {
            repo,
            app_paths,
            commits,
            shared_commit_count,
        } => render_local(
            old_rev,
            new_rev,
            repo,
            app_paths,
            commits,
            shared_commit_count,
        ),
        ChangelogInput::Upstream {
            repo,
            commits,
            total_upstream_commits,
        } => render_upstream(old_rev, new_rev, repo, commits, total_upstream_commits),
    }
}

fn render_local(
    old_rev: Option<&str>,
    new_rev: Option<&str>,
    repo: &str,
    app_paths: &[String],
    commits: Option<&[CommitInfo]>,
    shared_commit_count: usize,
) -> String {
    match (old_rev, new_rev) {
        (Some(old_r), Some(new_r)) if old_r == new_r => {
            format!(
                "Built from [`{}`](https://github.com/{repo}/commit/{new_r}) \
                 (same source revision as previous digest).\n",
                short7(new_r)
            )
        }
        (Some(old_r), Some(new_r)) => {
            let mut out = format!(
                "Built from [`{}..{}`](https://github.com/{repo}/compare/{old_r}...{new_r}).\n",
                short7(old_r),
                short7(new_r)
            );
            match commits {
                Some(list) => {
                    out.push('\n');
                    if list.is_empty() {
                        let scope = app_paths.join("`, `");
                        out.push_str(&format!(
                            "- No commits in this range touched `{scope}` directly.\n"
                        ));
                    } else {
                        for c in list {
                            out.push_str(&format!(
                                "- [`{}`](https://github.com/{repo}/commit/{}) {}\n",
                                short7(&c.sha),
                                c.sha,
                                c.subject
                            ));
                        }
                    }
                    out.push('\n');
                    if shared_commit_count == 1 {
                        out.push_str("1 other commit in this range changed shared build inputs.\n");
                    } else {
                        out.push_str(&format!(
                            "{shared_commit_count} other commits in this range changed shared build inputs.\n"
                        ));
                    }
                }
                None => {
                    out.push_str(
                        "\nLocal git checkout does not contain both revisions; \
                         see the compare link above for commit details.\n",
                    );
                }
            }
            out
        }
        (None, Some(new_r)) => {
            format!(
                "Built from [`{}`](https://github.com/{repo}/commit/{new_r}) \
                 (previous revision unknown — prior image predates \
                 `org.opencontainers.image.revision`; \
                 [commit history](https://github.com/{repo}/commits/{new_r})).\n",
                short7(new_r)
            )
        }
        (Some(old_r), None) => {
            format!(
                "Source revision unknown for the new image (`org.opencontainers.image.revision` \
                 label absent on the new digest; previous image was built from \
                 [`{}`](https://github.com/{repo}/commit/{old_r})).\n",
                short7(old_r)
            )
        }
        (None, None) => "Source revision unknown (neither previous nor new image records \
                         `org.opencontainers.image.revision`).\n"
            .to_string(),
    }
}

fn render_upstream(
    old_rev: Option<&str>,
    new_rev: Option<&str>,
    repo: &str,
    commits: Option<&[CommitInfo]>,
    total_upstream_commits: usize,
) -> String {
    match (old_rev, new_rev) {
        (Some(old_r), Some(new_r)) if old_r == new_r => {
            format!(
                "Built from [`{}`](https://github.com/{repo}/commit/{new_r}) \
                 (same upstream revision as previous digest).\n",
                short7(new_r)
            )
        }
        (Some(old_r), Some(new_r)) => {
            let mut out = format!(
                "Built from [`{}..{}`](https://github.com/{repo}/compare/{old_r}...{new_r}).\n",
                short7(old_r),
                short7(new_r)
            );
            if let Some(list) = commits {
                if !list.is_empty() {
                    out.push('\n');
                    for c in list.iter().take(MAX_UPSTREAM_COMMITS) {
                        out.push_str(&format!(
                            "- [`{}`](https://github.com/{repo}/commit/{}) {}\n",
                            short7(&c.sha),
                            c.sha,
                            c.subject
                        ));
                    }
                    let shown = list.len().min(MAX_UPSTREAM_COMMITS);
                    let total = total_upstream_commits.max(list.len());
                    if total > shown {
                        out.push_str(&format!(
                            "- ... and {} more commit(s) ([full diff](https://github.com/{repo}/compare/{old_r}...{new_r}))\n",
                            total - shown
                        ));
                    }
                }
            }
            out
        }
        (None, Some(new_r)) => {
            format!(
                "Built from [`{}`](https://github.com/{repo}/commit/{new_r}) \
                 (previous revision unknown — upstream revision isn't recorded on the prior image).\n",
                short7(new_r)
            )
        }
        (Some(old_r), None) => {
            format!(
                "Upstream revision isn't recorded on the new image (`org.opencontainers.image.revision` \
                 label absent; prior image was [`{}`](https://github.com/{repo}/commit/{old_r})).\n",
                short7(old_r)
            )
        }
        (None, None) => "Upstream revision isn't recorded on this image \
                         (`org.opencontainers.image.revision` label absent).\n"
            .to_string(),
    }
}

// ---------------------------------------------------------------------------
// Subprocess curl & utilities
// ---------------------------------------------------------------------------

static HDR_TMP_SEQ: AtomicUsize = AtomicUsize::new(0);

fn format_curl_error(o: &Output, secrets_to_scrub: &[&str]) -> String {
    let code = o.status.code().unwrap_or(1);
    let raw_err = String::from_utf8_lossy(&o.stderr);
    let cleaned = scrub_secrets(&single_line(&raw_err), secrets_to_scrub);
    if cleaned.is_empty() {
        format!("curl exited {code} fetching registry data")
    } else {
        cleaned
    }
}

fn run_curl(
    base_args: &[&str],
    url: &str,
    headers: &[&str],
    secrets_to_scrub: &[&str],
) -> Result<Vec<u8>, String> {
    let mut cmd = Command::new("curl");
    cmd.args(base_args);
    for h in headers {
        cmd.arg("-H").arg(h);
    }
    cmd.arg(url);
    cmd.stdin(Stdio::null());
    let o = cmd
        .output()
        .map_err(|e| format!("failed to run curl: {e}"))?;
    if !o.status.success() {
        return Err(format_curl_error(&o, secrets_to_scrub));
    }
    Ok(o.stdout)
}

fn curl_get(url: &str, headers: &[&str], secrets_to_scrub: &[&str]) -> Result<Vec<u8>, String> {
    run_curl(
        &["-fsSL", "--max-time", "20"],
        url,
        headers,
        secrets_to_scrub,
    )
}

fn curl_head(url: &str, headers: &[&str], secrets_to_scrub: &[&str]) -> Result<Vec<u8>, String> {
    run_curl(
        &["-fsSL", "-I", "--max-time", "20"],
        url,
        headers,
        secrets_to_scrub,
    )
}

fn curl_get_with_headers(
    url: &str,
    headers: &[&str],
    secrets_to_scrub: &[&str],
) -> Result<(Vec<u8>, Vec<u8>), String> {
    let tmp_dir = env_string("TEST_TMPDIR")
        .map(PathBuf::from)
        .unwrap_or_else(std::env::temp_dir);
    let seq = HDR_TMP_SEQ.fetch_add(1, Ordering::Relaxed);
    let hdr_path = tmp_dir.join(format!("ibc-hdr-{}-{seq}.txt", std::process::id()));

    let mut cmd = Command::new("curl");
    cmd.args(["-fsSL", "--max-time", "20", "-D"]);
    cmd.arg(&hdr_path);
    for h in headers {
        cmd.arg("-H").arg(h);
    }
    cmd.arg(url);
    cmd.stdin(Stdio::null());
    let o = cmd.output();
    let raw_headers = fs::read(&hdr_path).unwrap_or_default();
    let _ = fs::remove_file(&hdr_path);
    let o = o.map_err(|e| format!("failed to run curl: {e}"))?;
    if !o.status.success() {
        return Err(format_curl_error(&o, secrets_to_scrub));
    }
    Ok((o.stdout, raw_headers))
}

fn scrub_secrets(s: &str, secrets: &[&str]) -> String {
    let mut out = s.to_string();
    for sec in secrets {
        if !sec.is_empty() {
            out = out.replace(sec, "[REDACTED]");
        }
    }
    out
}

fn single_line(s: &str) -> String {
    s.lines()
        .map(str::trim)
        .find(|l| !l.is_empty())
        .unwrap_or("")
        .to_string()
}

fn env_string(name: &str) -> Option<String> {
    let bytes = env(name)?;
    let s = String::from_utf8_lossy(&bytes).trim().to_string();
    if s.is_empty() {
        None
    } else {
        Some(s)
    }
}

fn base64_encode(input: &[u8]) -> String {
    const TABLE: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::with_capacity((input.len() + 2) / 3 * 4);
    for chunk in input.chunks(3) {
        let b0 = chunk[0] as u32;
        let b1 = if chunk.len() > 1 { chunk[1] as u32 } else { 0 };
        let b2 = if chunk.len() > 2 { chunk[2] as u32 } else { 0 };
        let triple = (b0 << 16) | (b1 << 8) | b2;
        out.push(TABLE[((triple >> 18) & 0x3f) as usize] as char);
        out.push(TABLE[((triple >> 12) & 0x3f) as usize] as char);
        out.push(if chunk.len() > 1 {
            TABLE[((triple >> 6) & 0x3f) as usize] as char
        } else {
            '='
        });
        out.push(if chunk.len() > 2 {
            TABLE[(triple & 0x3f) as usize] as char
        } else {
            '='
        });
    }
    out
}

// ---------------------------------------------------------------------------
// Minimal RFC 8259 JSON parser (std-only)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum JsonValue {
    Null,
    Bool(bool),
    Number(String),
    Str(String),
    Array(Vec<JsonValue>),
    Object(Vec<(String, JsonValue)>),
}

impl JsonValue {
    pub fn get(&self, key: &str) -> Option<&JsonValue> {
        match self {
            JsonValue::Object(entries) => {
                // Last key wins for duplicate keys per common JSON convention.
                entries.iter().rev().find(|(k, _)| k == key).map(|(_, v)| v)
            }
            _ => None,
        }
    }

    pub fn as_str(&self) -> Option<&str> {
        match self {
            JsonValue::Str(s) => Some(s.as_str()),
            _ => None,
        }
    }

    pub fn as_array(&self) -> Option<&[JsonValue]> {
        match self {
            JsonValue::Array(items) => Some(items.as_slice()),
            _ => None,
        }
    }

    fn as_number_usize(&self) -> Option<usize> {
        match self {
            JsonValue::Number(raw) => raw.parse::<usize>().ok(),
            _ => None,
        }
    }
}

pub fn parse_json(bytes: &[u8]) -> Result<JsonValue, String> {
    let text = std::str::from_utf8(bytes).map_err(|_| "response is not valid UTF-8".to_string())?;
    let mut parser = JsonParser {
        bytes: text.as_bytes(),
        pos: 0,
    };
    let val = parser.parse_value(0)?;
    parser.skip_ws();
    if parser.pos != parser.bytes.len() {
        return Err(format!("trailing bytes at offset {}", parser.pos));
    }
    Ok(val)
}

struct JsonParser<'a> {
    bytes: &'a [u8],
    pos: usize,
}

impl<'a> JsonParser<'a> {
    fn skip_ws(&mut self) {
        while self.pos < self.bytes.len() {
            match self.bytes[self.pos] {
                b' ' | b'\t' | b'\r' | b'\n' => self.pos += 1,
                _ => break,
            }
        }
    }

    fn peek(&self) -> Option<u8> {
        self.bytes.get(self.pos).copied()
    }

    fn next(&mut self) -> Option<u8> {
        let b = self.peek()?;
        self.pos += 1;
        Some(b)
    }

    fn parse_value(&mut self, depth: usize) -> Result<JsonValue, String> {
        if depth > 64 {
            return Err("JSON nesting too deep".to_string());
        }
        self.skip_ws();
        let Some(b) = self.peek() else {
            return Err("unexpected end of JSON input".to_string());
        };
        match b {
            b'{' => self.parse_object(depth + 1),
            b'[' => self.parse_array(depth + 1),
            b'"' => self.parse_string().map(JsonValue::Str),
            b't' => self.expect_literal(b"true", JsonValue::Bool(true)),
            b'f' => self.expect_literal(b"false", JsonValue::Bool(false)),
            b'n' => self.expect_literal(b"null", JsonValue::Null),
            b'-' | b'0'..=b'9' => self.parse_number(),
            other => Err(format!(
                "unexpected byte '{}' at offset {}",
                other as char, self.pos
            )),
        }
    }

    fn expect_literal(&mut self, lit: &[u8], val: JsonValue) -> Result<JsonValue, String> {
        if self.bytes[self.pos..].starts_with(lit) {
            self.pos += lit.len();
            Ok(val)
        } else {
            Err(format!("invalid literal at offset {}", self.pos))
        }
    }

    fn parse_object(&mut self, depth: usize) -> Result<JsonValue, String> {
        self.pos += 1; // consume '{'
        self.skip_ws();
        let mut entries = Vec::new();
        if self.peek() == Some(b'}') {
            self.pos += 1;
            return Ok(JsonValue::Object(entries));
        }
        loop {
            self.skip_ws();
            if self.peek() != Some(b'"') {
                return Err(format!("expected object key string at offset {}", self.pos));
            }
            let key = self.parse_string()?;
            self.skip_ws();
            if self.next() != Some(b':') {
                return Err(format!("expected ':' at offset {}", self.pos));
            }
            let val = self.parse_value(depth)?;
            entries.push((key, val));
            self.skip_ws();
            match self.next() {
                Some(b',') => continue,
                Some(b'}') => return Ok(JsonValue::Object(entries)),
                _ => return Err(format!("expected ',' or '}}' at offset {}", self.pos)),
            }
        }
    }

    fn parse_array(&mut self, depth: usize) -> Result<JsonValue, String> {
        self.pos += 1; // consume '['
        self.skip_ws();
        let mut items = Vec::new();
        if self.peek() == Some(b']') {
            self.pos += 1;
            return Ok(JsonValue::Array(items));
        }
        loop {
            let val = self.parse_value(depth)?;
            items.push(val);
            self.skip_ws();
            match self.next() {
                Some(b',') => continue,
                Some(b']') => return Ok(JsonValue::Array(items)),
                _ => return Err(format!("expected ',' or ']' at offset {}", self.pos)),
            }
        }
    }

    fn parse_number(&mut self) -> Result<JsonValue, String> {
        let start = self.pos;
        if self.peek() == Some(b'-') {
            self.pos += 1;
        }
        match self.peek() {
            Some(b'0') => self.pos += 1,
            Some(b'1'..=b'9') => {
                while matches!(self.peek(), Some(b'0'..=b'9')) {
                    self.pos += 1;
                }
            }
            _ => return Err(format!("invalid JSON number at offset {start}")),
        }
        if self.peek() == Some(b'.') {
            self.pos += 1;
            if !matches!(self.peek(), Some(b'0'..=b'9')) {
                return Err(format!("invalid fraction in JSON number at offset {start}"));
            }
            while matches!(self.peek(), Some(b'0'..=b'9')) {
                self.pos += 1;
            }
        }
        if matches!(self.peek(), Some(b'e' | b'E')) {
            self.pos += 1;
            if matches!(self.peek(), Some(b'+' | b'-')) {
                self.pos += 1;
            }
            if !matches!(self.peek(), Some(b'0'..=b'9')) {
                return Err(format!("invalid exponent in JSON number at offset {start}"));
            }
            while matches!(self.peek(), Some(b'0'..=b'9')) {
                self.pos += 1;
            }
        }
        let raw = std::str::from_utf8(&self.bytes[start..self.pos])
            .map_err(|_| "invalid UTF-8 in number".to_string())?;
        Ok(JsonValue::Number(raw.to_string()))
    }

    fn parse_string(&mut self) -> Result<String, String> {
        self.pos += 1; // consume opening '"'
        let mut out = String::new();
        while self.pos < self.bytes.len() {
            let b = self.bytes[self.pos];
            if b == b'"' {
                self.pos += 1;
                return Ok(out);
            }
            if b == b'\\' {
                self.pos += 1;
                let esc = self
                    .next()
                    .ok_or_else(|| "unterminated escape in JSON string".to_string())?;
                match esc {
                    b'"' => out.push('"'),
                    b'\\' => out.push('\\'),
                    b'/' => out.push('/'),
                    b'b' => out.push('\u{0008}'),
                    b'f' => out.push('\u{000c}'),
                    b'n' => out.push('\n'),
                    b'r' => out.push('\r'),
                    b't' => out.push('\t'),
                    b'u' => {
                        let code = self.parse_hex4()?;
                        if (0xD800..=0xDBFF).contains(&code) {
                            if !self.bytes[self.pos..].starts_with(b"\\u") {
                                return Err(
                                    "unpaired UTF-16 high surrogate in JSON string".to_string()
                                );
                            }
                            self.pos += 2;
                            let low = self.parse_hex4()?;
                            if !(0xDC00..=0xDFFF).contains(&low) {
                                return Err(
                                    "invalid UTF-16 low surrogate in JSON string".to_string()
                                );
                            }
                            let cp = 0x10000 + (((code - 0xD800) << 10) | (low - 0xDC00));
                            let ch = char::from_u32(cp)
                                .ok_or_else(|| "invalid Unicode scalar".to_string())?;
                            out.push(ch);
                        } else {
                            let ch = char::from_u32(code)
                                .ok_or_else(|| "invalid Unicode scalar".to_string())?;
                            out.push(ch);
                        }
                    }
                    other => {
                        return Err(format!(
                            "invalid escape '\\{}' at offset {}",
                            other as char, self.pos
                        ))
                    }
                }
                continue;
            }
            if b < 0x20 {
                return Err(format!(
                    "unescaped control character in JSON string at {}",
                    self.pos
                ));
            }
            // Fast path: consume contiguous UTF-8 bytes up to next '"' or '\\'.
            let start = self.pos;
            while self.pos < self.bytes.len()
                && self.bytes[self.pos] != b'"'
                && self.bytes[self.pos] != b'\\'
                && self.bytes[self.pos] >= 0x20
            {
                self.pos += 1;
            }
            let chunk = std::str::from_utf8(&self.bytes[start..self.pos])
                .map_err(|_| "invalid UTF-8 inside JSON string".to_string())?;
            out.push_str(chunk);
        }
        Err("unterminated JSON string".to_string())
    }

    fn parse_hex4(&mut self) -> Result<u32, String> {
        if self.pos + 4 > self.bytes.len() {
            return Err("truncated \\u escape in JSON string".to_string());
        }
        let hex = std::str::from_utf8(&self.bytes[self.pos..self.pos + 4])
            .map_err(|_| "invalid UTF-8 in \\u escape".to_string())?;
        let val = u32::from_str_radix(hex, 16).map_err(|_| format!("invalid hex in \\u{hex}"))?;
        self.pos += 4;
        Ok(val)
    }
}

// ---------------------------------------------------------------------------
// Unit tests (fixture data only — no network)
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_image_and_digest_formats() {
        assert_eq!(
            parse_image_ref("ghcr.io/vitruviansoftware/vitruvian-slack-mcp"),
            Ok((
                "ghcr.io".to_string(),
                "vitruviansoftware/vitruvian-slack-mcp".to_string()
            ))
        );
        assert_eq!(
            parse_image_ref("ghcr.io/block/buzz:main@sha256:abc"),
            Ok(("ghcr.io".to_string(), "block/buzz".to_string()))
        );
        assert!(parse_image_ref("no-slash").is_err());

        let d = "1f35f89c8e64e1a43fbae32f5fc34466b599c807143453b6e17cfbf93f93b46b";
        assert_eq!(
            normalize_digest(&format!("main@sha256:{}", d.to_uppercase())),
            Ok(format!("sha256:{d}"))
        );
        assert_eq!(
            normalize_digest(&format!("sha256:{d}")),
            Ok(format!("sha256:{d}"))
        );
        assert!(normalize_digest("sha256:tooshort").is_err());
    }

    #[test]
    fn extract_digest_from_all_repo_manifest_formats() {
        let slack_vals = "image:\n  repository: ghcr.io/vitruviansoftware/vitruvian-slack-mcp\n  # digest: sha256:0000000000000000000000000000000000000000000000000000000000000000\n  digest: \"main@sha256:2245ded815b9c434ce90574ddb6bbaf3d819286a7a56d6f3bea7fd66ad7ce73a\"\n";
        assert_eq!(
            extract_digest_from_manifest_text(slack_vals).as_deref(),
            Some("sha256:2245ded815b9c434ce90574ddb6bbaf3d819286a7a56d6f3bea7fd66ad7ce73a")
        );

        let backstage_vals = "backstage:\n  image:\n    tag: latest@sha256:948301b1abcdef0123456789abcdef0123456789abcdef0123456789abcdef01\n";
        assert_eq!(
            extract_digest_from_manifest_text(backstage_vals).as_deref(),
            Some("sha256:948301b1abcdef0123456789abcdef0123456789abcdef0123456789abcdef01")
        );

        let gev_kustomize = "images:\n  - name: ghcr.io/vitruviansoftware/gods-eye-view\n    digest: sha256:989930a011111111222222223333333344444444555555556666666677777777\n";
        assert_eq!(
            extract_digest_from_manifest_text(gev_kustomize).as_deref(),
            Some("sha256:989930a011111111222222223333333344444444555555556666666677777777")
        );

        let buzz_vals = "image:\n  tag: \"main@sha256:85995e6911111111222222223333333344444444555555556666666677777777\"\n";
        assert_eq!(
            extract_digest_from_manifest_text(buzz_vals).as_deref(),
            Some("sha256:85995e6911111111222222223333333344444444555555556666666677777777")
        );
    }

    #[test]
    fn multi_arch_index_skips_attestation_and_picks_platform_manifest() {
        let index_json = br#"{
          "schemaVersion": 2,
          "mediaType": "application/vnd.oci.image.index.v1+json",
          "manifests": [
            {
              "mediaType": "application/vnd.oci.image.manifest.v1+json",
              "digest": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
              "platform": { "architecture": "unknown", "os": "unknown" },
              "annotations": { "vnd.docker.reference.type": "attestation-manifest" }
            },
            {
              "mediaType": "application/vnd.oci.image.manifest.v1+json",
              "digest": "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
              "platform": { "architecture": "arm64", "os": "linux" }
            },
            {
              "mediaType": "application/vnd.oci.image.manifest.v1+json",
              "digest": "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
              "platform": { "architecture": "amd64", "os": "linux" }
            }
          ]
        }"#;
        let parsed = parse_json(index_json).unwrap();
        assert_eq!(
            select_platform_manifest(&parsed),
            Ok(ManifestResolution::PlatformDigest {
                digest: "sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
                    .to_string(),
                fallback_revision: None,
            })
        );

        let single_manifest = br#"{
          "schemaVersion": 2,
          "config": {
            "digest": "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
          }
        }"#;
        let single_parsed = parse_json(single_manifest).unwrap();
        assert_eq!(
            select_platform_manifest(&single_parsed),
            Ok(ManifestResolution::SingleManifest)
        );
        assert_eq!(
            extract_config_digest(&single_parsed),
            Ok(
                "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
                    .to_string()
            )
        );
    }

    #[test]
    fn config_revision_label_extraction_handles_missing_or_unknown() {
        let with_label = parse_json(
            br#"{"config":{"Labels":{"org.opencontainers.image.revision":"E0B974296378B9E30757C5E5045A86498408B071"}}}"#,
        )
        .unwrap();
        assert_eq!(
            extract_revision_from_config(&with_label).as_deref(),
            Some("e0b974296378b9e30757c5e5045a86498408b071")
        );

        let unknown =
            parse_json(br#"{"config":{"Labels":{"org.opencontainers.image.revision":"unknown"}}}"#)
                .unwrap();
        assert_eq!(extract_revision_from_config(&unknown), None);

        let empty_labels = parse_json(br#"{"config":{"Labels":{}}}"#).unwrap();
        assert_eq!(extract_revision_from_config(&empty_labels), None);
    }

    #[test]
    fn json_parser_handles_escapes_and_surrogates() {
        let j = parse_json(br#"{"msg":"line1\nline2 \u0041 \uD83D\uDE80"}"#).unwrap();
        assert_eq!(
            j.get("msg").and_then(JsonValue::as_str),
            Some("line1\nline2 A 🚀")
        );
    }

    #[test]
    fn render_local_and_upstream_markdown() {
        let app_paths = vec!["apps/mcp/vitruvian-slack-mcp".to_string()];
        let commits = vec![CommitInfo {
            sha: "bfaa3fadf0000000000000000000000000000000".to_string(),
            subject: "chore(rust): upgrade default Rust toolchain (#4874)".to_string(),
        }];
        let md = render_markdown(
            Some("10b86d19bdaab4b63838035f9c9aa3aaccd00293"),
            Some("e0b974296378b9e30757c5e5045a86498408b071"),
            ChangelogInput::Local {
                repo: "VitruvianSoftware/vitruvian-core",
                app_paths: &app_paths,
                commits: Some(&commits),
                shared_commit_count: 1,
            },
        );
        assert!(md.contains("Built from [`10b86d1..e0b9742`](https://github.com/VitruvianSoftware/vitruvian-core/compare/10b86d19bdaab4b63838035f9c9aa3aaccd00293...e0b974296378b9e30757c5e5045a86498408b071)."));
        assert!(md.contains("(#4874)"));
        assert!(md.contains("1 other commit in this range changed shared build inputs."));

        let missing_old = render_markdown(
            None,
            Some("e0b974296378b9e30757c5e5045a86498408b071"),
            ChangelogInput::Local {
                repo: "VitruvianSoftware/vitruvian-core",
                app_paths: &app_paths,
                commits: None,
                shared_commit_count: 0,
            },
        );
        assert!(missing_old.contains("previous revision unknown"));
        assert!(missing_old.contains("e0b9742"));

        let upstream_unlabeled = render_markdown(
            None,
            None,
            ChangelogInput::Upstream {
                repo: "block/buzz",
                commits: None,
                total_upstream_commits: 0,
            },
        );
        assert!(upstream_unlabeled.contains("Upstream revision isn't recorded"));
    }

    #[test]
    fn parse_upstream_compare_fixture() {
        let fixture = br#"{
          "total_commits": 2,
          "commits": [
            {"sha": "1fb33e4545660196d4c863daf70e1d3bc245f164", "commit": {"message": "feat: thing\n\nbody"}},
            {"sha": "2222222222222222222222222222222222222222", "commit": {"message": "fix: bug (#9)"}}
          ]
        }"#;
        let json = parse_json(fixture).unwrap();
        let (commits, total) = parse_upstream_compare_json(&json).unwrap();
        assert_eq!(total, 2);
        assert_eq!(commits.len(), 2);
        assert_eq!(commits[0].subject, "feat: thing");
        assert_eq!(commits[1].subject, "fix: bug (#9)");
    }

    #[test]
    fn tag_fallback_helpers_filter_40_lowercase_hex_and_parse_headers() {
        let valid_sha = "6da38a7a64e677f03c8ba248a41c4129374a0696";
        assert!(is_40_lowercase_hex(valid_sha));
        assert!(!is_40_lowercase_hex("1fb33e4"));
        assert!(!is_40_lowercase_hex("sha-1fa63ba"));
        assert!(!is_40_lowercase_hex(&valid_sha[..39]));
        assert!(!is_40_lowercase_hex(&format!("{valid_sha}a")));
        assert!(!is_40_lowercase_hex(&valid_sha.to_ascii_uppercase()));
        assert!(!is_40_lowercase_hex(
            "gggggggggggggggggggggggggggggggggggggggg"
        ));
        assert!(!is_40_lowercase_hex("latest"));
        assert!(!is_40_lowercase_hex("buildcache"));

        let tags_json = parse_json(
            format!(
                r#"{{"name":"vitruviansoftware/gods-eye-view","tags":["latest","buildcache","1fb33e4","sha-1fa63ba","{upper}","{nonhex}","{valid_sha}"]}}"#,
                upper = valid_sha.to_ascii_uppercase(),
                nonhex = "gggggggggggggggggggggggggggggggggggggggg",
            )
            .as_bytes(),
        )
        .unwrap();
        assert_eq!(extract_40_hex_tags(&tags_json), vec![valid_sha.to_string()]);

        let null_tags = parse_json(br#"{"name":"repo","tags":null}"#).unwrap();
        assert!(extract_40_hex_tags(&null_tags).is_empty());

        let hdrs = b"HTTP/2 302 \r\nLocation: https://example.com\r\n\r\nHTTP/2 200 \r\ncontent-type: application/vnd.oci.image.index.v1+json\r\ndocker-content-digest: sha256:989930A0DA11D3DCEC74ED4FEA9AD8FFB9E97F281F366942591567B6E518BC0F\r\n";
        assert_eq!(
            extract_docker_content_digest(hdrs).as_deref(),
            Some("sha256:989930a0da11d3dcec74ed4fea9ad8ffb9e97f281f366942591567b6e518bc0f")
        );

        let redirect_hdrs = b"HTTP/2 200 \r\ndocker-content-digest: sha256:1111111111111111111111111111111111111111111111111111111111111111\r\n\r\nHTTP/2 200 \r\ndocker-content-digest: \"sha256:2222222222222222222222222222222222222222222222222222222222222222\"\r\n";
        assert_eq!(
            extract_docker_content_digest(redirect_hdrs).as_deref(),
            Some("sha256:2222222222222222222222222222222222222222222222222222222222222222")
        );

        let link_hdr = b"HTTP/2 200 \r\nlink: </v2/vitruviansoftware/gods-eye-view/tags/list?last=abc&n=1000>; rel=\"next\"\r\n";
        assert_eq!(
            parse_next_link_url(link_hdr, "ghcr.io").as_deref(),
            Some("https://ghcr.io/v2/vitruviansoftware/gods-eye-view/tags/list?last=abc&n=1000")
        );
        let prev_only_hdr = b"HTTP/2 200 \r\nlink: </v2/foo/tags/list?last=abc>; rel=\"prev\"\r\n";
        assert_eq!(parse_next_link_url(prev_only_hdr, "ghcr.io"), None);
    }
}
