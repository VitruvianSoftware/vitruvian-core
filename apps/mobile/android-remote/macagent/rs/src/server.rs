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

//! HTTP server routing, authentication middleware, and core endpoints for Mac Agent.

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use vitruvian_remote_macagent_metrics::json::{JsonObject, JsonValue};
use vitruvian_remote_macagent_metrics::{parse_volume_settings, Timestamp};

use crate::antigravity::{
    default_agy_summaries, handle_agy_resume_sse, handle_agy_sessions, real_agy_stream, AgyStreamFn,
};
use crate::exec::{
    is_valid_power_action, pbcopy, pbpaste, power_action, run_act, run_argv, run_cmd_simple,
    set_volume, ExecRequest, CLAUDE_RESUME_TIMEOUT_SEC, MAX_OUTPUT,
};
use crate::homespeaker::HomeSpeaker;
use crate::hook::{default_claude_settings, hook_command_line_for_dir};
use crate::http_util::{
    http_request, is_loopback_addr, log_act, log_line, parse_bearer, url_encode, HttpHandler,
    HttpRequest, HttpResponse,
};
use crate::mcp::{handle_mcp_phone, is_loopback_host};
use crate::notify::{Notification, ERR_NOTIFY_DISABLED, ERR_NOTIFY_NOT_CONFIGURED};
use crate::pair::Store;
use crate::pairpage::handle_pair_page;
use crate::permission::{
    get_permission_wait, handle_permission_ask, handle_permission_decide,
    handle_permission_enabled, handle_permission_list, PermissionBroker,
};
use crate::phone::PhoneBridge;
use crate::sampler::{
    argo_sync_argv, parse_screen_region, pr_action_argv, resume_argv, run_tool_within,
    screenshot_jpeg, Sampler, ScreenRegion, DEFAULT_SCREEN_WIDTH, ERR_SCREEN_RECORDING_DENIED,
    MAX_SCREEN_WIDTH, MIN_SCREEN_WIDTH, NOT_CONFIGURED_KUBE, SCREEN_DENIED_REASON,
};
use crate::stream::handle_exec_stream;
use crate::tv::{handle_tv_get, handle_tv_post, TVController};

pub const VERSION: &str = "1.9.1";
pub const DEFAULT_PORT: &str = "7411";
pub const SCREEN_CACHE_TTL: Duration = Duration::from_secs(2);

pub type ScreenCaptureFn = Arc<dyn Fn(i32, ScreenRegion) -> Result<Vec<u8>, String> + Send + Sync>;

struct ScreenCache {
    at: Option<Instant>,
    px: i32,
    region: ScreenRegion,
    jpeg: Option<Vec<u8>>,
}

impl Default for ScreenCache {
    fn default() -> Self {
        Self {
            at: None,
            px: 0,
            region: ScreenRegion::default(),
            jpeg: None,
        }
    }
}

pub struct Server {
    pub sampler: Arc<Sampler>,
    pub store: Arc<Store>,
    pub prom_url: String,
    pub prom_token: String,
    pub capture: ScreenCaptureFn,
    pub speaker: Arc<HomeSpeaker>,
    pub tv: Arc<TVController>,
    pub phone: Arc<PhoneBridge>,
    pub perms: Arc<PermissionBroker>,
    pub permission_wait: Duration,
    pub claude_settings: PathBuf,
    pub hook_command: String,
    pub agy_summaries: PathBuf,
    pub agy_stream: Arc<AgyStreamFn>,
    screen_cache: Mutex<ScreenCache>,
}

pub fn new_mux(
    sampler: Arc<Sampler>,
    store: Store,
    prom_url: impl Into<String>,
    prom_token: impl Into<String>,
) -> Arc<Server> {
    Server::new(sampler, Arc::new(store), prom_url, prom_token)
}

impl HttpHandler for Server {
    fn handle(&self, req: &HttpRequest) -> HttpResponse {
        Server::handle(self, req)
    }
}

impl HttpHandler for Arc<Server> {
    fn handle(&self, req: &HttpRequest) -> HttpResponse {
        Server::handle(self, req)
    }
}

impl Server {
    pub fn new(
        sampler: Arc<Sampler>,
        store: Arc<Store>,
        prom_url: impl Into<String>,
        prom_token: impl Into<String>,
    ) -> Arc<Self> {
        let prom_url = prom_url.into().trim_end_matches('/').to_string();
        let prom_token = prom_token.into();
        let hook_command =
            hook_command_line_for_dir(&store.dir().to_string_lossy()).unwrap_or_default();
        Arc::new(Self {
            sampler,
            store,
            prom_url,
            prom_token,
            capture: Arc::new(|width, region| screenshot_jpeg(width, region)),
            speaker: Arc::new(HomeSpeaker::new()),
            tv: Arc::new(TVController::default_controller()),
            phone: Arc::new(PhoneBridge::new()),
            perms: Arc::new(PermissionBroker::new()),
            permission_wait: get_permission_wait(),
            claude_settings: default_claude_settings(),
            hook_command,
            agy_summaries: default_agy_summaries(),
            agy_stream: Arc::new(real_agy_stream),
            screen_cache: Mutex::new(ScreenCache::default()),
        })
    }

    pub fn with_capture(mut self: Arc<Self>, capture: ScreenCaptureFn) -> Arc<Self> {
        if let Some(s) = Arc::get_mut(&mut self) {
            s.capture = capture;
        }
        self
    }

    pub fn handle(&self, req: &HttpRequest) -> HttpResponse {
        let path = req.path.as_str();
        match path {
            // --- read ---
            "/v1/metrics" => self.get_only(req, |_| {
                HttpResponse::json(200, &self.sampler.snapshot().to_json())
            }),
            "/v1/host" => self.get_only(req, |_| {
                HttpResponse::json(200, &self.sampler.host().to_json())
            }),
            "/v1/processes" => self.get_only(req, |_| {
                HttpResponse::json(200, &self.sampler.processes().to_json())
            }),
            "/v1/tools" => self.get_only(req, |_| {
                HttpResponse::json(200, &self.sampler.tools().to_json())
            }),
            "/v1/antigravity" => self.get_only(req, |_| {
                HttpResponse::json(200, &self.sampler.antigravity().to_json())
            }),
            "/v1/ollama" => self.get_only(req, |_| {
                HttpResponse::json(200, &self.sampler.ollama().to_json())
            }),
            "/v1/vms" => self.get_only(req, |_| {
                HttpResponse::json(200, &self.sampler.vms().to_json())
            }),
            "/v1/containers" => self.get_only(req, |_| {
                HttpResponse::json(200, &self.sampler.containers().to_json())
            }),
            "/v1/k8s" => self.get_only(req, |_| {
                HttpResponse::json(200, &self.sampler.k8s().to_json())
            }),
            "/v1/sessions" => self.get_only(req, |_| {
                HttpResponse::json(200, &self.sampler.sessions().to_json())
            }),
            "/v1/promql" => self.get_only(req, |r| self.promql(r)),
            "/healthz" => self.get_only(req, |r| self.healthz(r)),

            // --- v1.2 read ---
            "/v1/claude/sessions" => self.get_only(req, |_| {
                HttpResponse::json(200, &self.sampler.claude_sessions().to_json())
            }),
            "/v1/prs" => self.get_only(req, |_| {
                HttpResponse::json(200, &self.sampler.prs().to_json())
            }),
            "/v1/argocd" => self.get_only(req, |_| {
                HttpResponse::json(200, &self.sampler.argocd().to_json())
            }),

            // --- pairing ---
            "/v1/pair" => self.post_only(req, |r| self.pair(r)),
            "/pair" => self.get_only(req, |r| handle_pair_page(r)),

            // --- read + act on the same path ---
            "/v1/audio" => match req.method.as_str() {
                "GET" | "HEAD" => HttpResponse::json(200, &self.sampler.audio().to_json()),
                "POST" => self.act(req, |r| self.set_audio(r)),
                _ => HttpResponse::method_not_allowed("GET, HEAD, POST"),
            },
            "/v1/clipboard" => match req.method.as_str() {
                "GET" => self.act(req, |r| self.get_clipboard(r)),
                "POST" => self.act(req, |r| self.set_clipboard(r)),
                _ => HttpResponse::method_not_allowed("GET, POST"),
            },

            // --- act ---
            "/v1/exec" => self.post_only(req, |r| self.act(r, |r2| self.exec(r2))),
            "/v1/power" => self.post_only(req, |r| self.act(r, |r2| self.power(r2))),

            // --- v1.2 act ---
            "/v1/exec/stream" => self.post_only(req, |r| self.act(r, |r2| handle_exec_stream(r2))),
            "/v1/claude/resume" => {
                self.post_only(req, |r| self.act(r, |r2| self.claude_resume(r2)))
            }
            "/v1/prs/action" => self.post_only(req, |r| self.act(r, |r2| self.pr_action(r2))),
            "/v1/argocd/sync" => self.post_only(req, |r| self.act(r, |r2| self.argo_sync(r2))),
            "/v1/notify/test" => self.post_only(req, |r| self.act(r, |r2| self.notify_test(r2))),
            "/v1/notify/settings" => {
                self.post_only(req, |r| self.act(r, |r2| self.notify_settings(r2)))
            }
            "/v1/screen" => self.get_only(req, |r| self.act(r, |r2| self.screen(r2))),

            // --- v1.3: the phone bridge ---
            "/v1/phone/link" => {
                self.post_only(req, |r| self.act(r, |r2| self.phone.handle_link(r2)))
            }
            "/v1/phone/result" => {
                self.post_only(req, |r| self.act(r, |r2| self.phone.handle_result(r2)))
            }
            "/v1/phone" => self.get_only(req, |_| self.phone.handle_status()),

            // --- v1.4: HomeSpeaker ---
            "/v1/homespeaker" => match req.method.as_str() {
                "GET" | "HEAD" => self.speaker.handle_get(&self.phone),
                "POST" => self.act(req, |r| self.speaker.handle_set(r, &self.phone)),
                _ => HttpResponse::method_not_allowed("GET, HEAD, POST"),
            },
            "/v1/homespeaker/say" => {
                self.post_only(req, |r| self.act(r, |r2| self.speaker.handle_say(r2)))
            }
            "/v1/homespeaker/phone-say" => self.post_only(req, |r| {
                self.act_or_loopback(r, |r2| self.speaker.handle_phone_say(r2, &self.phone))
            }),
            "/v1/homespeaker/volume" => match req.method.as_str() {
                "GET" | "HEAD" => self.speaker.handle_get_volume(),
                "POST" => self.act(req, |r| self.speaker.handle_set_volume(r)),
                _ => HttpResponse::method_not_allowed("GET, HEAD, POST"),
            },

            // --- MCP phone server ---
            "/mcp/phone" => handle_mcp_phone(&self.store, &self.phone, req),

            // --- v1.6: Claude Code permission prompts ---
            "/v1/claude/permission/ask" => handle_permission_ask(
                req,
                &self.store,
                &self.perms,
                self.permission_wait,
                Some(self.sampler.notifier()),
            ),
            "/v1/claude/permissions" => self.get_only(req, |r| {
                self.act(r, |r2| {
                    handle_permission_list(
                        r2,
                        &self.perms,
                        self.permission_wait,
                        &self.claude_settings,
                        &self.hook_command,
                    )
                })
            }),
            "/v1/claude/permission/decide" => self.post_only(req, |r| {
                self.act(r, |r2| handle_permission_decide(r2, &self.perms))
            }),
            "/v1/claude/permission/enabled" => self.post_only(req, |r| {
                self.act(r, |r2| {
                    handle_permission_enabled(r2, &self.claude_settings, &self.hook_command)
                })
            }),

            // --- v1.7: Antigravity sessions and resume ---
            "/v1/antigravity/sessions" => {
                self.get_only(req, |r| handle_agy_sessions(r, &self.agy_summaries))
            }
            "/v1/antigravity/resume" => self.post_only(req, |r| {
                self.act(r, |r2| {
                    handle_agy_resume_sse(
                        r2,
                        &self.agy_summaries,
                        &self.agy_stream,
                        Some(Arc::clone(self.sampler.notifier())),
                    )
                })
            }),

            // --- Sony Google TV over wireless ADB ---
            "/v1/tv" => self.get_only(req, |_| handle_tv_get(&self.tv)),
            "/v1/tv/act" => self.post_only(req, |r| self.act(r, |r2| handle_tv_post(r2, &self.tv))),

            _ => HttpResponse::error(404, "not found"),
        }
    }

    pub fn get_only<F>(&self, req: &HttpRequest, f: F) -> HttpResponse
    where
        F: FnOnce(&HttpRequest) -> HttpResponse,
    {
        if req.method != "GET" && req.method != "HEAD" {
            return HttpResponse::method_not_allowed("GET, HEAD");
        }
        f(req)
    }

    pub fn post_only<F>(&self, req: &HttpRequest, f: F) -> HttpResponse
    where
        F: FnOnce(&HttpRequest) -> HttpResponse,
    {
        if req.method != "POST" {
            return HttpResponse::method_not_allowed("POST");
        }
        f(req)
    }

    pub fn act<F>(&self, req: &HttpRequest, f: F) -> HttpResponse
    where
        F: FnOnce(&HttpRequest) -> HttpResponse,
    {
        let Some(presented) = parse_bearer(req) else {
            return HttpResponse::error(401, "act endpoints need a bearer token; pair first")
                .with_header(
                    "WWW-Authenticate",
                    r#"Bearer realm="vitruvian-remote-agent""#,
                );
        };
        if !self.store.authorized(&presented) {
            return HttpResponse::error(403, "token not recognised; pair again");
        }
        f(req)
    }

    pub fn act_or_loopback<F>(&self, req: &HttpRequest, f: F) -> HttpResponse
    where
        F: FnOnce(&HttpRequest) -> HttpResponse,
    {
        if is_loopback_addr(&req.remote_addr) && req.header("Authorization").is_empty() {
            let host = req.header("Host");
            if !is_loopback_host(host) {
                return HttpResponse::error(
                    403,
                    "loopback requests without a bearer token require a loopback Host header",
                );
            }
            let ct = req.header("Content-Type").trim().to_ascii_lowercase();
            if !ct.starts_with("application/json") {
                return HttpResponse::error(
                    415,
                    "loopback requests without a bearer token require Content-Type: application/json",
                );
            }
            return f(req);
        }
        self.act(req, f)
    }

    pub fn healthz(&self, _req: &HttpRequest) -> HttpResponse {
        let snap = self.sampler.snapshot();
        let now = Timestamp::now();
        let (age_ms, is_stale) = if snap.sampled_at.is_zero() {
            (-1i64, true)
        } else {
            let age = now.duration_since(snap.sampled_at);
            (age.as_millis() as i64, age > Duration::from_secs(30))
        };
        let status = if is_stale { 503 } else { 200 };
        let n = self.sampler.notifier();
        let mut notify_obj = JsonObject::new();
        notify_obj.push("configured", JsonValue::Bool(n.configured()));
        notify_obj.push("enabled", JsonValue::Bool(n.enabled()));
        notify_obj.push("topic", JsonValue::Str(n.topic().to_string()));

        let mut obj = JsonObject::new();
        obj.push("ok", JsonValue::Bool(status == 200));
        obj.push("sample_age_ms", JsonValue::Int(age_ms));
        obj.push("agent_version", JsonValue::Str(VERSION.to_string()));
        obj.push("read_only", JsonValue::Bool(false));
        obj.push("paired", JsonValue::Bool(self.store.paired()));
        obj.push("sampled_at", JsonValue::Str(snap.sampled_at.to_rfc3339()));
        obj.push("notify", notify_obj.into_value());
        HttpResponse::json(status, &obj.into_value())
    }

    pub fn claude_resume(&self, req: &HttpRequest) -> HttpResponse {
        let val = match req.json() {
            Ok(v) => v,
            Err(e) => return HttpResponse::error(400, &e),
        };
        let session_id = val.get_str("session_id").trim().to_string();
        let prompt = val.get_str("prompt").trim().to_string();
        if session_id.is_empty() || prompt.is_empty() {
            return HttpResponse::error(400, "session_id and prompt are required");
        }
        log_act("claude-resume", &format!("{}: {}", session_id, prompt));
        let argv = resume_argv(&session_id, &prompt);
        let res = run_argv(
            &argv,
            Duration::from_secs(CLAUDE_RESUME_TIMEOUT_SEC),
            &req.cancel,
        );
        HttpResponse::json(200, &res.to_json())
    }

    pub fn pr_action(&self, req: &HttpRequest) -> HttpResponse {
        let val = match req.json() {
            Ok(v) => v,
            Err(e) => return HttpResponse::error(400, &e),
        };
        let repo = val.get_str("repo").trim().to_string();
        let number = val.get_i64("number") as i32;
        let action = val.get_str("action").to_string();
        if repo.is_empty() || number <= 0 {
            return HttpResponse::error(400, "repo and a positive number are required");
        }
        let args = match pr_action_argv(&action, &repo, number) {
            Ok(a) => a,
            Err(e) => return HttpResponse::error(400, &e),
        };
        log_act("pr", &format!("{} {}#{}", action, repo, number));
        let (stdout, stderr, err) = run_tool_within(Duration::from_secs(60), "gh", &args, None);
        let out = format!("{}\n{}", stdout.trim(), stderr.trim())
            .trim()
            .to_string();
        let mut obj = JsonObject::new();
        if let Some(e) = err {
            let full = format!("{}\n{}", out, e).trim().to_string();
            obj.push("ok", JsonValue::Bool(false));
            obj.push("output", JsonValue::Str(full));
        } else {
            obj.push("ok", JsonValue::Bool(true));
            obj.push("output", JsonValue::Str(out));
        }
        HttpResponse::json(200, &obj.into_value())
    }

    pub fn argo_sync(&self, req: &HttpRequest) -> HttpResponse {
        let val = match req.json() {
            Ok(v) => v,
            Err(e) => return HttpResponse::error(400, &e),
        };
        let name = val.get_str("name").trim().to_string();
        let namespace = val.get_str("namespace").trim().to_string();
        if name.is_empty() || namespace.is_empty() {
            return HttpResponse::error(400, "name and namespace are required");
        }
        if self.sampler.kube_context().is_empty() {
            return HttpResponse::error(400, NOT_CONFIGURED_KUBE);
        }
        log_act("argocd", &format!("sync {}/{}", namespace, name));
        let args = argo_sync_argv(
            self.sampler.kubeconfig(),
            self.sampler.kube_context(),
            &namespace,
            &name,
        );
        let (stdout, stderr, err) =
            run_tool_within(Duration::from_secs(30), "kubectl", &args, None);
        let out = format!("{}\n{}", stdout.trim(), stderr.trim())
            .trim()
            .to_string();
        let mut obj = JsonObject::new();
        if let Some(e) = err {
            let full = format!("{}\n{}", out, e).trim().to_string();
            obj.push("ok", JsonValue::Bool(false));
            obj.push("output", JsonValue::Str(full));
        } else {
            obj.push("ok", JsonValue::Bool(true));
            obj.push("output", JsonValue::Str(out));
        }
        HttpResponse::json(200, &obj.into_value())
    }

    pub fn notify_settings(&self, req: &HttpRequest) -> HttpResponse {
        let val = match req.json() {
            Ok(v) => v,
            Err(e) => return HttpResponse::error(400, &e),
        };
        let Some(enabled) = val.get("enabled").and_then(|v| v.as_bool()) else {
            return HttpResponse::error(400, r#""enabled" is required (true or false)"#);
        };
        if let Err(e) = self.store.set_notify_enabled(enabled) {
            return HttpResponse::error(500, &e);
        }
        let n = self.sampler.notifier();
        n.set_enabled(enabled);
        let state = if enabled { "on" } else { "off" };
        log_act("notify", &format!("switched {}", state));
        let mut obj = JsonObject::new();
        obj.push("ok", JsonValue::Bool(true));
        obj.push("enabled", JsonValue::Bool(n.enabled()));
        obj.push("configured", JsonValue::Bool(n.configured()));
        obj.push("topic", JsonValue::Str(n.topic().to_string()));
        HttpResponse::json(200, &obj.into_value())
    }

    pub fn notify_test(&self, _req: &HttpRequest) -> HttpResponse {
        let n = self.sampler.notifier();
        if !n.configured() {
            return HttpResponse::error(400, ERR_NOTIFY_NOT_CONFIGURED);
        }
        if !n.enabled() {
            return HttpResponse::error(400, ERR_NOTIFY_DISABLED);
        }
        log_act("notify", "test");
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos();
        let key = format!("notify:test:{}", nanos);
        if let Err(e) = n.send(&Notification {
            key,
            title: "Test from Vitruvian Remote".to_string(),
            body: "If this arrived, notifications work.".to_string(),
            priority: "default".to_string(),
            tags: "bell".to_string(),
            click: "vitruvian-remote://mac".to_string(),
        }) {
            return HttpResponse::error(502, &e);
        }
        let mut obj = JsonObject::new();
        obj.push("ok", JsonValue::Bool(true));
        obj.push("topic", JsonValue::Str(n.topic().to_string()));
        HttpResponse::json(200, &obj.into_value())
    }

    pub fn screen(&self, req: &HttpRequest) -> HttpResponse {
        let mut width = DEFAULT_SCREEN_WIDTH;
        if let Some(q) = req.query_param("width") {
            if !q.is_empty() {
                match q.parse::<i32>() {
                    Ok(n) => width = n,
                    Err(_) => {
                        return HttpResponse::error(
                            400,
                            "width must be a number between 200 and 1600",
                        );
                    }
                }
            }
        }
        width = width.clamp(MIN_SCREEN_WIDTH, MAX_SCREEN_WIDTH);

        let mut qmap = HashMap::new();
        for k in ["x", "y", "w", "h"] {
            if let Some(v) = req.query_param(k) {
                qmap.insert(k.to_string(), v);
            }
        }
        let region = match parse_screen_region(&qmap) {
            Ok(r) => r,
            Err(e) => return HttpResponse::error(400, &e),
        };
        if region.full() {
            log_act("screen", &format!("capture width {}", width));
        } else {
            log_act(
                "screen",
                &format!(
                    "capture width {} of {:.3},{:.3} {:.3}x{:.3}",
                    width, region.x, region.y, region.w, region.h
                ),
            );
        }

        let mut cache = self.screen_cache.lock().unwrap();
        if let (Some(ref jpeg), Some(at)) = (&cache.jpeg, cache.at) {
            if cache.px == width && cache.region == region && at.elapsed() < SCREEN_CACHE_TTL {
                return write_jpeg(jpeg.clone());
            }
        }
        match (self.capture)(width, region) {
            Ok(img) => {
                cache.jpeg = Some(img.clone());
                cache.px = width;
                cache.region = region;
                cache.at = Some(Instant::now());
                write_jpeg(img)
            }
            Err(e) => {
                if e == ERR_SCREEN_RECORDING_DENIED {
                    let mut obj = JsonObject::new();
                    obj.push("available", JsonValue::Bool(false));
                    obj.push("reason", JsonValue::Str(SCREEN_DENIED_REASON.to_string()));
                    HttpResponse::json(503, &obj.into_value())
                } else {
                    HttpResponse::error(500, &e)
                }
            }
        }
    }

    pub fn pair(&self, req: &HttpRequest) -> HttpResponse {
        let val = match req.json() {
            Ok(v) => v,
            Err(e) => return HttpResponse::error(400, &e),
        };
        let code = val.get_str("code").to_string();
        match self.store.claim_pairing(&code) {
            Ok(tok) => {
                log_line("pair: a client paired successfully");
                let mut obj = JsonObject::new();
                obj.push("token", JsonValue::Str(tok));
                HttpResponse::json(200, &obj.into_value())
            }
            Err(e) => {
                log_line(&format!("pair: refused ({})", e));
                HttpResponse::error(403, "pairing refused")
            }
        }
    }

    pub fn exec(&self, req: &HttpRequest) -> HttpResponse {
        let val = match req.json() {
            Ok(v) => v,
            Err(e) => return HttpResponse::error(400, &e),
        };
        let exec_req = match ExecRequest::from_json(&val) {
            Ok(r) => r,
            Err(e) => return HttpResponse::error(400, &e),
        };
        if exec_req.command.trim().is_empty() {
            return HttpResponse::error(400, "command is required");
        }
        log_act(&exec_req.kind, &exec_req.command);
        match run_act(&exec_req, &req.cancel) {
            Ok(res) => HttpResponse::json(200, &res.to_json()),
            Err(e) => HttpResponse::error(400, &e),
        }
    }

    pub fn get_clipboard(&self, req: &HttpRequest) -> HttpResponse {
        log_act("clipboard", "read");
        match pbpaste(&req.cancel) {
            Ok(text) => {
                let mut obj = JsonObject::new();
                obj.push("text", JsonValue::Str(text));
                HttpResponse::json(200, &obj.into_value())
            }
            Err(e) => HttpResponse::error(500, &format!("pbpaste: {}", e)),
        }
    }

    pub fn set_clipboard(&self, req: &HttpRequest) -> HttpResponse {
        let val = match req.json() {
            Ok(v) => v,
            Err(e) => return HttpResponse::error(400, &e),
        };
        let text = val.get_str("text").to_string();
        log_act("clipboard", &format!("write {}", text));
        match pbcopy(&text, &req.cancel) {
            Ok(()) => {
                let mut obj = JsonObject::new();
                obj.push("ok", JsonValue::Bool(true));
                HttpResponse::json(200, &obj.into_value())
            }
            Err(e) => HttpResponse::error(500, &format!("pbcopy: {}", e)),
        }
    }

    pub fn set_audio(&self, req: &HttpRequest) -> HttpResponse {
        let val = match req.json() {
            Ok(v) => v,
            Err(e) => return HttpResponse::error(400, &e),
        };
        let vol = val.get_i64("volume_percent") as i32;
        log_act("audio", &format!("volume {}", vol));
        if let Err(e) = set_volume(vol, &req.cancel) {
            return HttpResponse::error(500, &format!("set volume: {}", e));
        }
        if let Ok(out) = run_cmd_simple("osascript", &["-e", "get volume settings"], &req.cancel) {
            if let Ok(a) = parse_volume_settings(&out) {
                self.sampler.set_audio(a.clone());
                return HttpResponse::json(200, &a.to_json());
            }
        }
        HttpResponse::json(200, &self.sampler.audio().to_json())
    }

    pub fn power(&self, req: &HttpRequest) -> HttpResponse {
        let val = match req.json() {
            Ok(v) => v,
            Err(e) => return HttpResponse::error(400, &e),
        };
        let action = val.get_str("action").to_string();
        if !is_valid_power_action(&action) {
            return HttpResponse::error(
                400,
                &format!("unknown action {} (want sleep or restart)", action),
            );
        }
        log_act("power", &action);
        let cancel = req.cancel.clone();
        let action_clone = action.clone();
        std::thread::spawn(move || {
            if let Err(e) = power_action(&action_clone, &cancel) {
                log_line(&format!("power {}: {}", action_clone, e));
            }
        });
        let mut obj = JsonObject::new();
        obj.push("ok", JsonValue::Bool(true));
        HttpResponse::json(200, &obj.into_value())
    }

    pub fn promql(&self, req: &HttpRequest) -> HttpResponse {
        if self.prom_url.is_empty() {
            let mut obj = JsonObject::new();
            obj.push("available", JsonValue::Bool(false));
            obj.push(
                "reason",
                JsonValue::Str("not configured (--prometheus-url)".to_string()),
            );
            return HttpResponse::json(200, &obj.into_value());
        }
        let q = req.query_param("q").unwrap_or_default();
        if q.trim().is_empty() {
            return HttpResponse::error(400, "q is required");
        }
        let upstream = format!("{}/api/v1/query?query={}", self.prom_url, url_encode(&q));
        let mut headers = Vec::new();
        let auth_hdr;
        if !self.prom_token.is_empty() {
            auth_hdr = format!("Bearer {}", self.prom_token);
            headers.push(("Authorization", auth_hdr.as_str()));
        }
        match http_request("GET", &upstream, &headers, None, Duration::from_secs(10)) {
            Ok((status, _, body)) => {
                if body.len() > MAX_OUTPUT {
                    let mut obj = JsonObject::new();
                    obj.push("available", JsonValue::Bool(false));
                    obj.push(
                        "reason",
                        JsonValue::Str(format!(
                            "result larger than {} KiB; narrow the query (fewer series, or a label filter)",
                            MAX_OUTPUT / 1024
                        )),
                    );
                    return HttpResponse::json(200, &obj.into_value());
                }
                HttpResponse::new(status, body)
                    .with_header("Content-Type", "application/json")
                    .with_header("Cache-Control", "no-store")
            }
            Err(e) => HttpResponse::error(502, &format!("prometheus: {}", e)),
        }
    }
}

fn write_jpeg(b: Vec<u8>) -> HttpResponse {
    let len = b.len().to_string();
    HttpResponse::new(200, b)
        .with_header("Content-Type", "image/jpeg")
        .with_header("Cache-Control", "no-store")
        .with_header("Content-Length", &len)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::http_util::TestServer;
    use crate::notify::Notifier;
    use crate::sampler::{
        crop_box, gh_search_argv, gh_search_repo_argv, gh_view_argv, is_screen_denied,
        parse_sips_pixels, read_tail, split_repos, TRANSCRIPT_TAIL,
    };
    use crate::tailnet::tailscale_ipv4;
    use std::fs;
    use std::sync::atomic::{AtomicI32, AtomicUsize, Ordering};
    use vitruvian_remote_macagent_metrics::{
        ArgoApp, ArgoApps, Checks, ClaudeSession, ClaudeSessions, Host, PRs, Snapshot, CPU, PR,
        STATE_IDLE, STATE_WAITING_FOR_PERMISSION, STATE_WORKING,
    };

    static TEST_COUNTER: AtomicUsize = AtomicUsize::new(0);

    fn temp_dir(prefix: &str) -> PathBuf {
        let id = TEST_COUNTER.fetch_add(1, Ordering::SeqCst);
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos();
        let dir = std::env::temp_dir().join(format!(
            "macagent-srv-{}-{}-{}-{}",
            prefix,
            std::process::id(),
            nanos,
            id
        ));
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn new_test_agent(prefix: &str) -> (Arc<Sampler>, Arc<Store>, Arc<Server>, PathBuf) {
        let dir = temp_dir(prefix);
        let sampler = Sampler::new(Duration::from_secs(1), "", "", Vec::new(), None);
        let store = Arc::new(Store::new(dir.clone()));
        store.ensure_token().unwrap();
        let srv = Server::new(Arc::clone(&sampler), Arc::clone(&store), "", "");
        (sampler, store, srv, dir)
    }

    fn paired_token(store: &Store) -> String {
        store.ensure_token().unwrap();
        store.write_pairing("123456").unwrap();
        store.claim_pairing("123456").unwrap()
    }

    #[test]
    fn test_read_endpoints_are_get_only() {
        let (_, _, srv, dir) = new_test_agent("read-get-only");
        for path in [
            "/v1/metrics",
            "/v1/host",
            "/v1/processes",
            "/v1/vms",
            "/v1/containers",
            "/v1/k8s",
            "/v1/sessions",
            "/healthz",
        ] {
            for method in ["POST", "PUT", "DELETE", "PATCH"] {
                let req = HttpRequest::new_test(method, path, "");
                let resp = srv.handle(&req);
                assert_eq!(resp.status, 405, "{} {}", method, path);
                assert_eq!(
                    resp.header("Allow"),
                    Some("GET, HEAD"),
                    "{} {}",
                    method,
                    path
                );
            }
        }
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_act_endpoints_refuse_an_unpaired_caller() {
        let (_, store, srv, dir) = new_test_agent("act-unpaired");
        for (method, path) in [
            ("POST", "/v1/exec"),
            ("GET", "/v1/clipboard"),
            ("POST", "/v1/clipboard"),
            ("POST", "/v1/audio"),
            ("POST", "/v1/power"),
        ] {
            let req = HttpRequest::new_test(method, path, "{}");
            let resp = srv.handle(&req);
            assert_eq!(resp.status, 401, "{} {}", method, path);
            assert!(
                resp.header("WWW-Authenticate").is_some(),
                "{} {}",
                method,
                path
            );
        }

        let req = HttpRequest::new_test(
            "POST",
            "/v1/exec",
            r#"{"kind":"shell","command":"echo hi"}"#,
        )
        .with_header("Authorization", &format!("Bearer {}", "a".repeat(64)));
        let resp = srv.handle(&req);
        assert_eq!(resp.status, 403);

        assert!(!store.authorized(""));
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_healthz_before_and_after_the_first_sample() {
        let (sampler, store, srv, dir) = new_test_agent("healthz");
        let get = || -> (u16, JsonValue) {
            let req = HttpRequest::new_test("GET", "/healthz", "");
            let resp = srv.handle(&req);
            let body = JsonValue::parse(&resp.body_string()).unwrap();
            (resp.status, body)
        };

        let (code, body) = get();
        assert_eq!(code, 503);
        assert_eq!(body.get_i64("sample_age_ms"), -1);
        assert_eq!(body.get_bool("read_only"), false);
        assert_eq!(body.get_bool("paired"), false);

        store.write_pairing("482917").unwrap();
        store.claim_pairing("482917").unwrap();
        let (_, body) = get();
        assert_eq!(body.get_bool("paired"), true);

        sampler.set_snapshot(Snapshot {
            sampled_at: Timestamp::now(),
            ..Default::default()
        });
        let (code, _) = get();
        assert_eq!(code, 200);

        sampler.set_snapshot(Snapshot {
            sampled_at: Timestamp::now().sub(Duration::from_secs(45)),
            ..Default::default()
        });
        let (code, _) = get();
        assert_eq!(code, 503);

        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_metrics_and_host_are_served_as_json_with_no_store() {
        let (sampler, _, srv, dir) = new_test_agent("metrics-host");
        sampler.set_snapshot(Snapshot {
            sampled_at: Timestamp::now(),
            cpu: CPU {
                ready: true,
                busy_percent: 12.5,
                ..Default::default()
            },
            ..Default::default()
        });
        sampler.set_host(Host {
            hostname: "atlas".to_string(),
            cores: 16,
            mac_address: "a2:26:7e:45:c1:2d".to_string(),
            wake_on_lan: true,
            ..Default::default()
        });

        for (path, want) in [
            ("/v1/metrics", r#""busy_percent":12.5"#),
            ("/v1/host", r#""mac_address":"a2:26:7e:45:c1:2d""#),
        ] {
            let req = HttpRequest::new_test("GET", path, "");
            let resp = srv.handle(&req);
            assert_eq!(resp.header("Content-Type"), Some("application/json"));
            assert_eq!(resp.header("Cache-Control"), Some("no-store"));
            let body = resp.body_string();
            assert!(
                body.contains(want),
                "{}: {} does not contain {}",
                path,
                body,
                want
            );
        }
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_tailscale_ipv4_only_matches_cgnat() {
        if let Some(ip) = tailscale_ipv4() {
            assert!(ip.starts_with("100."), "returned {}", ip);
        }
    }

    #[test]
    fn test_promql_overflow_is_a_reason_not_a_cut() {
        let dir = temp_dir("promql-overflow");
        let big = TestServer::start(|_req: &HttpRequest| {
            let mut body = Vec::from(&b"{\"status\":\"success\",\"data\":{\"result\":[\""[..]);
            body.extend(std::iter::repeat(b'x').take(MAX_OUTPUT + 10));
            body.extend_from_slice(b"\"]}}");
            HttpResponse::new(200, body).with_header("Content-Type", "application/json")
        });
        let sampler = Sampler::new(Duration::from_secs(1), "", "", Vec::new(), None);
        let store = Arc::new(Store::new(dir.clone()));
        let srv = Server::new(sampler, store, big.url(), "");

        let req = HttpRequest::new_test("GET", "/v1/promql?q=up", "");
        let resp = srv.handle(&req);
        let got = JsonValue::parse(&resp.body_string()).unwrap();
        assert_eq!(got.get_bool("available"), false);
        assert!(got.get_str("reason").contains("narrow the query"));

        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_pr_action_argv_is_fixed() {
        for (action, want) in [
            (
                "approve",
                vec![
                    "pr",
                    "review",
                    "2226",
                    "--repo",
                    "VitruvianSoftware/vitruvian-core",
                    "--approve",
                ],
            ),
            (
                "merge",
                vec![
                    "pr",
                    "merge",
                    "2226",
                    "--repo",
                    "VitruvianSoftware/vitruvian-core",
                    "--merge",
                ],
            ),
            (
                "auto_merge",
                vec![
                    "pr",
                    "merge",
                    "2226",
                    "--repo",
                    "VitruvianSoftware/vitruvian-core",
                    "--auto",
                    "--merge",
                ],
            ),
            (
                "ready",
                vec![
                    "pr",
                    "ready",
                    "2226",
                    "--repo",
                    "VitruvianSoftware/vitruvian-core",
                ],
            ),
        ] {
            let got = pr_action_argv(action, "VitruvianSoftware/vitruvian-core", 2226).unwrap();
            assert_eq!(got, want);
        }
        assert!(pr_action_argv("close", "o/r", 1).is_err());
        let got = pr_action_argv("merge", "--admin", 1).unwrap();
        assert_eq!(got[3], "--repo");
        assert_eq!(got[4], "--admin");
    }

    #[test]
    fn test_argo_sync_argv_carries_the_cluster_flags() {
        let got = argo_sync_argv(
            "/Users/alice/.kube/cluster.yaml",
            "default",
            "argocd",
            "cnpg-operator",
        );
        let want = vec![
            "--kubeconfig",
            "/Users/alice/.kube/cluster.yaml",
            "--context",
            "default",
            "-n",
            "argocd",
            "patch",
            "application",
            "cnpg-operator",
            "--type",
            "merge",
            "-p",
            r#"{"operation":{"initiatedBy":{"username":"vitruvian-remote"},"sync":{}}}"#,
        ];
        assert_eq!(got, want);

        let got2 = argo_sync_argv("", "default", "argocd", "x");
        assert_eq!(got2[0], "--context");
    }

    #[test]
    fn test_gh_argv_asks_for_the_fields_the_parser_reads() {
        let view = gh_view_argv("o/r", 12).join(" ");
        for field in [
            "isDraft",
            "headRefName",
            "baseRefName",
            "mergeStateStatus",
            "reviewDecision",
            "statusCheckRollup",
            "autoMergeRequest",
            "author",
        ] {
            assert!(view.contains(field), "missing {}", field);
        }

        let search = gh_search_argv("@me").join(" ");
        for field in ["number", "repository", "title", "url", "updatedAt"] {
            assert!(search.contains(field), "missing {}", field);
        }
        assert!(gh_search_repo_argv("o/r").join(" ").contains("--repo o/r"));
    }

    #[test]
    fn test_resume_argv_passes_the_session_id_as_a_value() {
        let got = resume_argv("b4d0359c-d7e1-4db0-8960-536873764a56", "carry on");
        let want = vec![
            "claude",
            "--resume",
            "b4d0359c-d7e1-4db0-8960-536873764a56",
            "-p",
            "carry on",
            "--output-format",
            "text",
        ];
        assert_eq!(got, want);
    }

    #[test]
    fn test_claude_resume_requires_both_fields() {
        let (_, store, srv, dir) = new_test_agent("claude-resume-req");
        let tok = paired_token(&store);
        for body in [r#"{"prompt":"go on"}"#, r#"{"session_id":"abc"}"#, r#"{}"#] {
            let req = HttpRequest::new_test("POST", "/v1/claude/resume", body)
                .with_header("Authorization", &format!("Bearer {}", tok));
            let resp = srv.handle(&req);
            assert_eq!(resp.status, 400, "{}", body);
        }
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_v12_act_endpoints_refuse_an_unpaired_caller() {
        let (_, _, srv, dir) = new_test_agent("v12-act");
        for (method, path) in [
            ("POST", "/v1/exec/stream"),
            ("POST", "/v1/claude/resume"),
            ("POST", "/v1/prs/action"),
            ("POST", "/v1/argocd/sync"),
            ("POST", "/v1/notify/test"),
            ("GET", "/v1/screen"),
        ] {
            let req = HttpRequest::new_test(method, path, "{}");
            let resp = srv.handle(&req);
            assert_eq!(resp.status, 401, "{} {}", method, path);
        }
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_v12_read_endpoints_need_no_token() {
        let (sampler, _, srv, dir) = new_test_agent("v12-read");
        sampler.set_claude_sessions(ClaudeSessions {
            running: 0,
            sessions: vec![ClaudeSession {
                session_id: "b4d0359c".to_string(),
                project: "/Users/alice/core".to_string(),
                state: STATE_WAITING_FOR_PERMISSION.to_string(),
                last_tool: "Bash".to_string(),
                ..Default::default()
            }],
        });
        sampler.set_prs(PRs {
            available: true,
            reason: String::new(),
            sampled_at: Timestamp::ZERO,
            prs: vec![PR {
                repo: "o/r".to_string(),
                number: 1,
                checks: Checks {
                    success: 26,
                    skipped: 19,
                    ..Default::default()
                },
                ..Default::default()
            }],
        });
        sampler.set_argocd(ArgoApps {
            available: true,
            reason: String::new(),
            apps: vec![ArgoApp {
                name: "cnpg-operator".to_string(),
                sync: "Synced".to_string(),
                ..Default::default()
            }],
        });

        for (path, want) in [
            ("/v1/claude/sessions", r#""state":"waiting_for_permission""#),
            ("/v1/prs", r#""success":26"#),
            ("/v1/argocd", r#""name":"cnpg-operator""#),
        ] {
            let req = HttpRequest::new_test("GET", path, "");
            let resp = srv.handle(&req);
            assert_eq!(resp.status, 200);
            let body = resp.body_string();
            assert!(body.contains(want), "{}: {} missing {}", path, body, want);
        }
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_screen_success_path_with_an_injected_capture() {
        let (sampler, store, _, dir) = new_test_agent("screen-ok");
        let calls = Arc::new(AtomicI32::new(0));
        let last_width = Arc::new(AtomicI32::new(0));
        let last_region = Arc::new(Mutex::new(ScreenRegion::default()));

        let calls_c = Arc::clone(&calls);
        let width_c = Arc::clone(&last_width);
        let region_c = Arc::clone(&last_region);
        let srv = Server::new(sampler, Arc::clone(&store), "", "").with_capture(Arc::new(
            move |width, region| {
                calls_c.fetch_add(1, Ordering::SeqCst);
                width_c.store(width, Ordering::SeqCst);
                *region_c.lock().unwrap() = region;
                Ok(vec![0xFF, 0xD8, 0xFF, 0xE0, b'j', b'p', b'g'])
            },
        ));
        let tok = paired_token(&store);

        let get = |q: &str| -> HttpResponse {
            let req = HttpRequest::new_test("GET", &format!("/v1/screen{}", q), "")
                .with_header("Authorization", &format!("Bearer {}", tok));
            srv.handle(&req)
        };

        let resp = get("?width=1000");
        assert_eq!(resp.status, 200);
        assert_eq!(resp.header("Content-Type"), Some("image/jpeg"));
        assert_eq!(resp.header("Cache-Control"), Some("no-store"));
        assert_eq!(resp.body_bytes().len(), 7);
        assert_eq!(last_width.load(Ordering::SeqCst), 1000);

        let _ = get("?width=1000");
        assert_eq!(calls.load(Ordering::SeqCst), 1);

        let _ = get("?width=400");
        assert_eq!(calls.load(Ordering::SeqCst), 2);

        let resp = get("?width=400&x=0.25&y=0.5&w=0.25&h=0.25");
        assert_eq!(resp.status, 200);
        assert_eq!(calls.load(Ordering::SeqCst), 3);
        assert_eq!(
            *last_region.lock().unwrap(),
            ScreenRegion {
                x: 0.25,
                y: 0.5,
                w: 0.25,
                h: 0.25
            }
        );

        let _ = get("?width=400&x=0.25&y=0.5&w=0.25&h=0.25");
        assert_eq!(calls.load(Ordering::SeqCst), 3);

        for q in [
            "?x=0.5",
            "?x=0.9&y=0&w=0.5&h=0.5",
            "?x=0&y=0&w=0.01&h=0.01",
            "?x=a&y=0&w=1&h=1",
        ] {
            let resp = get(&format!("?width=400&{}", &q[1..]));
            assert_eq!(resp.status, 400, "{}", q);
        }
        assert_eq!(calls.load(Ordering::SeqCst), 3);

        let _ = get("?width=99999");
        assert_eq!(last_width.load(Ordering::SeqCst), MAX_SCREEN_WIDTH);

        let _ = get("?width=1");
        assert_eq!(last_width.load(Ordering::SeqCst), MIN_SCREEN_WIDTH);

        let resp = get("?width=wide");
        assert_eq!(resp.status, 400);

        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_screen_denied_is_a_503_with_the_documented_reason() {
        let (sampler, store, _, dir) = new_test_agent("screen-denied");
        let srv =
            Server::new(sampler, Arc::clone(&store), "", "").with_capture(Arc::new(|_, _| {
                Err(ERR_SCREEN_RECORDING_DENIED.to_string())
            }));
        let tok = paired_token(&store);

        let req = HttpRequest::new_test("GET", "/v1/screen", "")
            .with_header("Authorization", &format!("Bearer {}", tok));
        let resp = srv.handle(&req);
        assert_eq!(resp.status, 503);
        let got = JsonValue::parse(&resp.body_string()).unwrap();
        assert_eq!(got.get_bool("available"), false);
        assert_eq!(got.get_str("reason"), SCREEN_DENIED_REASON);
        assert!(SCREEN_DENIED_REASON.contains("System Settings"));

        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_is_screen_denied_recognises_the_real_refusal() {
        assert!(is_screen_denied("could not create image from display\n"));
        assert!(is_screen_denied(
            "screencapture: not authorized to capture the screen"
        ));
        assert!(!is_screen_denied(
            "screencapture: cannot write file to /tmp: No space left on device"
        ));
        assert!(!is_screen_denied(""));
    }

    #[test]
    fn test_notify_test_says_so_when_unconfigured() {
        let (_, store, srv, dir) = new_test_agent("notify-unconf");
        let tok = paired_token(&store);
        let req = HttpRequest::new_test("POST", "/v1/notify/test", "{}")
            .with_header("Authorization", &format!("Bearer {}", tok));
        let resp = srv.handle(&req);
        assert_eq!(resp.status, 400);
        let got = JsonValue::parse(&resp.body_string()).unwrap();
        assert!(got.get_str("error").contains("--ntfy-url"));
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_healthz_reports_notify_configuration() {
        let (_, _, srv, dir) = new_test_agent("healthz-notify");
        let resp = srv.handle(&HttpRequest::new_test("GET", "/healthz", ""));
        let body = JsonValue::parse(&resp.body_string()).unwrap();
        let n = body.get("notify").unwrap();
        assert_eq!(n.get_bool("configured"), false);
        assert_eq!(n.get_str("topic"), "");

        let notifier = Arc::new(Notifier::new(
            "https://ntfy.example",
            "vitruvian-remote",
            "s3cr3t",
        ));
        let sampler2 = Sampler::new(Duration::from_secs(1), "", "", Vec::new(), Some(notifier));
        let store2 = Arc::new(Store::new(dir.clone()));
        store2.ensure_token().unwrap();
        let srv2 = Server::new(sampler2, store2, "", "");
        let resp2 = srv2.handle(&HttpRequest::new_test("GET", "/healthz", ""));
        let text = resp2.body_string();
        assert!(text.contains(r#""configured":true"#));
        assert!(text.contains(r#""topic":"vitruvian-remote""#));
        assert!(!text.contains("s3cr3t"));

        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_split_repos_drops_empties() {
        let got = split_repos(" a/b , , c/d ,");
        assert_eq!(got, vec!["a/b", "c/d"]);
        assert!(split_repos("").is_empty());
    }

    #[test]
    fn test_session_notifications_fire_on_transitions_only() {
        let received: Arc<Mutex<Vec<(String, String)>>> = Arc::new(Mutex::new(Vec::new()));
        let rec_clone = Arc::clone(&received);
        let up = TestServer::start(move |req: &HttpRequest| {
            let title = req.header("Title").to_string();
            let body = req.body_string();
            rec_clone.lock().unwrap().push((title, body));
            HttpResponse::new(200, b"ok".to_vec())
        });

        let notifier = Arc::new(Notifier::new(up.url(), "topic", ""));
        let s = Sampler::new(Duration::from_secs(1), "", "", Vec::new(), Some(notifier));

        let waiting = ClaudeSessions {
            running: 0,
            sessions: vec![ClaudeSession {
                session_id: "abc".to_string(),
                project: "/Users/alice/core".to_string(),
                state: STATE_WAITING_FOR_PERMISSION.to_string(),
                last_tool: "Bash".to_string(),
                ..Default::default()
            }],
        };
        s.notify_session_transitions(&waiting);
        assert_eq!(received.lock().unwrap().len(), 1);
        assert_eq!(received.lock().unwrap()[0].0, "Claude Code may be waiting");
        assert_eq!(
            received.lock().unwrap()[0].1,
            "core · Bash · no result for 90 s"
        );

        s.notify_session_transitions(&waiting);
        assert_eq!(received.lock().unwrap().len(), 1);

        let working = ClaudeSessions {
            running: 0,
            sessions: vec![ClaudeSession {
                session_id: "abc".to_string(),
                project: "/Users/alice/core".to_string(),
                state: STATE_WORKING.to_string(),
                ..Default::default()
            }],
        };
        s.notify_session_transitions(&working);

        let idle = ClaudeSessions {
            running: 0,
            sessions: vec![ClaudeSession {
                session_id: "abc".to_string(),
                project: "/Users/alice/core".to_string(),
                state: STATE_IDLE.to_string(),
                last_text: "All four gates are green.".to_string(),
                ..Default::default()
            }],
        };
        s.notify_session_transitions(&idle);
        assert_eq!(received.lock().unwrap().len(), 2);
        assert_eq!(received.lock().unwrap()[1].0, "Claude Code finished a turn");

        let notifier2 = Arc::new(Notifier::new(up.url(), "topic", ""));
        let s2 = Sampler::new(Duration::from_secs(1), "", "", Vec::new(), Some(notifier2));
        let before = received.lock().unwrap().len();
        s2.notify_session_transitions(&idle);
        assert_eq!(received.lock().unwrap().len(), before);
    }

    #[test]
    fn test_pr_notifications_fire_on_verdict_changes_only() {
        let received: Arc<Mutex<Vec<(String, String)>>> = Arc::new(Mutex::new(Vec::new()));
        let rec_clone = Arc::clone(&received);
        let up = TestServer::start(move |req: &HttpRequest| {
            let title = req.header("Title").to_string();
            let prio = req.header("Priority").to_string();
            rec_clone.lock().unwrap().push((title, prio));
            HttpResponse::new(200, b"ok".to_vec())
        });

        let notifier = Arc::new(Notifier::new(up.url(), "topic", ""));
        let s = Sampler::new(Duration::from_secs(1), "", "", Vec::new(), Some(notifier));

        let pending = PRs {
            available: true,
            reason: String::new(),
            sampled_at: Timestamp::ZERO,
            prs: vec![PR {
                repo: "o/r".to_string(),
                number: 7,
                title: "a change".to_string(),
                checks: Checks {
                    success: 3,
                    pending: 1,
                    ..Default::default()
                },
                ..Default::default()
            }],
        };
        let green = PRs {
            available: true,
            reason: String::new(),
            sampled_at: Timestamp::ZERO,
            prs: vec![PR {
                repo: "o/r".to_string(),
                number: 7,
                title: "a change".to_string(),
                checks: Checks {
                    success: 4,
                    ..Default::default()
                },
                ..Default::default()
            }],
        };
        let red = PRs {
            available: true,
            reason: String::new(),
            sampled_at: Timestamp::ZERO,
            prs: vec![PR {
                repo: "o/r".to_string(),
                number: 7,
                title: "a change".to_string(),
                checks: Checks {
                    success: 3,
                    failure: 1,
                    ..Default::default()
                },
                ..Default::default()
            }],
        };

        s.notify_pr_transitions(&pending);
        assert_eq!(received.lock().unwrap().len(), 0);

        s.notify_pr_transitions(&green);
        assert_eq!(received.lock().unwrap().len(), 1);
        assert_eq!(received.lock().unwrap()[0].0, "PR #7 checks green");

        s.notify_pr_transitions(&green);
        assert_eq!(received.lock().unwrap().len(), 1);

        s.notify_pr_transitions(&red);
        assert_eq!(received.lock().unwrap().len(), 2);
        assert_eq!(received.lock().unwrap()[1].1, "high");

        let notifier2 = Arc::new(Notifier::new(up.url(), "topic", ""));
        let s2 = Sampler::new(Duration::from_secs(1), "", "", Vec::new(), Some(notifier2));
        let before = received.lock().unwrap().len();
        s2.notify_pr_transitions(&green);
        assert_eq!(received.lock().unwrap().len(), before);
    }

    #[test]
    fn test_read_tail_reads_only_the_end() {
        let dir = temp_dir("read-tail");
        let path = dir.join("t.jsonl");
        let big = format!("{}\nTHE-END\n", "x".repeat(TRANSCRIPT_TAIL));
        fs::write(&path, big.as_bytes()).unwrap();
        let got = read_tail(&path, TRANSCRIPT_TAIL);
        assert!(got.len() <= TRANSCRIPT_TAIL);
        assert!(got.contains("THE-END"));

        let small_path = dir.join("s.jsonl");
        fs::write(&small_path, b"small\n").unwrap();
        assert_eq!(read_tail(&small_path, TRANSCRIPT_TAIL), "small\n");
        assert_eq!(read_tail(&dir.join("nope.jsonl"), TRANSCRIPT_TAIL), "");

        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn test_crop_box_stays_inside_the_picture() {
        let (x, y, w, h) = crop_box(
            7680,
            2160,
            ScreenRegion {
                x: 0.5,
                y: 0.5,
                w: 0.5,
                h: 0.5,
            },
        );
        assert_eq!((x, y, w, h), (3840, 1080, 3840, 1080));

        let (x2, _, w2, _) = crop_box(
            1000,
            100,
            ScreenRegion {
                x: 0.6667,
                y: 0.0,
                w: 0.3334,
                h: 1.0,
            },
        );
        assert!(x2 + w2 <= 1000 && w2 == 333);

        let (_, _, w3, h3) = crop_box(
            10,
            10,
            ScreenRegion {
                x: 0.0,
                y: 0.0,
                w: 0.01,
                h: 0.01,
            },
        );
        assert_eq!((w3, h3), (1, 1));
    }

    #[test]
    fn test_parse_sips_pixels() {
        let (w, h) =
            parse_sips_pixels("/tmp/x/screen.jpg\n  pixelWidth: 7680\n  pixelHeight: 2160\n");
        assert_eq!((w, h), (7680, 2160));
        assert_eq!(parse_sips_pixels("garbage"), (0, 0));
    }
}
