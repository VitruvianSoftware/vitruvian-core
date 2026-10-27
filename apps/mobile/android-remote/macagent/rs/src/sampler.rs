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

//! Background metrics sampler, fixed tool argv builders, and screen capture helpers.

use std::collections::{BTreeMap, HashMap};
use std::fs::{self, File};
use std::io::{Read, Seek, SeekFrom};
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::{mpsc, Arc, RwLock};
use std::thread;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use vitruvian_remote_macagent_metrics::{
    count_processes_named, cwd_from_transcript, parse_agy_agents, parse_agy_models,
    parse_argo_apps, parse_battery, parse_boottime, parse_default_interface, parse_df,
    parse_docker_ps, parse_ether, parse_gh_pr_view, parse_gh_search_prs, parse_kubectl_nodes,
    parse_lima_list, parse_load_avg, parse_nested_battery_temperature, parse_netstat,
    parse_ollama_list, parse_ollama_ps, parse_podman_ps, parse_processes, parse_therm, parse_top,
    parse_transcript_tail, parse_vm_stat, parse_volume_settings, parse_womp, pr_checks_verdict,
    project_from_dir_name, trim_runes, Antigravity, ArgoApps, Audio, ClaudeSessions, Containers,
    Host, K8s, Network, Ollama, PRRef, PRs, Processes, Session, Sessions, Snapshot, Timestamp,
    Tool, Tools, VMs, PR, STATE_IDLE, STATE_WAITING_FOR_PERMISSION, STATE_WORKING,
};

use crate::http_util::CancelToken;
use crate::notify::{Notification, Notifier};

pub fn get_hostname() -> String {
    run_cmd("hostname", &["-s"])
        .map(|s| s.trim().to_string())
        .unwrap_or_default()
}

pub const TOP_PROCESSES: usize = 8;
pub const SESSION_WINDOW: Duration = Duration::from_secs(30 * 60);
pub const CLAUDE_SESSION_WINDOW: Duration = Duration::from_secs(4 * 3600);
pub const TRANSCRIPT_TAIL: usize = 64 << 10;
pub const NOT_CONFIGURED_KUBE: &str = "not configured (--kube-context)";
pub const DATA_VOLUME: &str = "/System/Volumes/Data";
pub const HOME_SPEAKER_BINARY: &str = "/Applications/HomeSpeaker.app/Contents/MacOS/HomeSpeaker";

pub const CMD_TIMEOUT: Duration = Duration::from_secs(10);
pub const TOP_TIMEOUT: Duration = Duration::from_secs(30);
pub const TOOL_TIMEOUT: Duration = Duration::from_secs(5);

pub const MIN_SCREEN_WIDTH: i32 = 200;
pub const MAX_SCREEN_WIDTH: i32 = 1600;
pub const DEFAULT_SCREEN_WIDTH: i32 = 800;
pub const MIN_SCREEN_FRACTION: f64 = 1.0 / 16.0;

pub const SCREEN_DENIED_REASON: &str =
    "Screen Recording is not granted to the agent — System Settings → Privacy & Security → Screen Recording";
pub const ERR_SCREEN_RECORDING_DENIED: &str = SCREEN_DENIED_REASON;

pub const KNOWN_TOOLS: &[&str] = &[
    "adb",
    "agy",
    "claude",
    "docker",
    "homespeaker",
    "kubectl",
    "limactl",
    "ollama",
    "osascript",
    "podman",
    "shortcuts",
    "xcodebuild",
];

pub const OWN_SAMPLERS: &[&str] = &["top", "ps"];

pub fn default_unavailable() -> BTreeMap<String, String> {
    let mut m = BTreeMap::new();
    m.insert(
        "soc_temperature_c".to_string(),
        "needs root (powermetrics) or an SMC reader; the battery sensor is in battery.temperature_c"
            .to_string(),
    );
    m.insert("fan_rpm".to_string(), "needs an SMC reader".to_string());
    m.insert(
        "gpu_percent".to_string(),
        "needs root (powermetrics)".to_string(),
    );
    m.insert(
        "ane_percent".to_string(),
        "needs root (powermetrics)".to_string(),
    );
    m.insert(
        "soc_power_watts".to_string(),
        "needs root (powermetrics); tools/ops/macos-power-agent pushes this to Prometheus"
            .to_string(),
    );
    m
}

pub fn augmented_path() -> String {
    let home = std::env::var("HOME").unwrap_or_default();
    let home_path = PathBuf::from(&home);
    let extra = [
        PathBuf::from("/opt/homebrew/bin"),
        PathBuf::from("/usr/local/bin"),
        home_path.join(".local").join("bin"),
        home_path.join("bin"),
        home_path
            .join("Library")
            .join("Android")
            .join("sdk")
            .join("platform-tools"),
    ];
    let cur = std::env::var("PATH").unwrap_or_else(|_| "/usr/bin:/bin:/usr/sbin:/sbin".to_string());
    let have: Vec<&str> = cur.split(':').collect();
    let mut add = Vec::new();
    for p in &extra {
        let s = p.to_string_lossy().into_owned();
        if !s.is_empty() && !have.contains(&s.as_str()) && p.is_dir() {
            add.push(s);
        }
    }
    if add.is_empty() {
        cur
    } else {
        add.push(cur);
        add.join(":")
    }
}

pub fn extend_path() {
    let new_path = augmented_path();
    std::env::set_var("PATH", new_path);
}

pub fn find_executable_in_path(name: &str) -> Option<String> {
    if name.is_empty() {
        return None;
    }
    if name.contains('/') {
        let p = Path::new(name);
        if is_executable_file(p) {
            return Some(name.to_string());
        }
        return None;
    }
    let path_var = augmented_path();
    for dir in path_var.split(':') {
        if dir.is_empty() {
            continue;
        }
        let candidate = Path::new(dir).join(name);
        if is_executable_file(&candidate) {
            return Some(candidate.to_string_lossy().into_owned());
        }
    }
    None
}

fn is_executable_file(p: &Path) -> bool {
    let Ok(meta) = fs::metadata(p) else {
        return false;
    };
    meta.is_file() && (meta.permissions().mode() & 0o111 != 0)
}

pub fn first_line(s: &str) -> String {
    let s = s.trim();
    if s.is_empty() {
        return String::new();
    }
    match s.split_once('\n') {
        Some((line, _)) => line.trim().to_string(),
        None => s.to_string(),
    }
}

pub fn run_tool_within(
    limit: Duration,
    name: &str,
    args: &[String],
    custom_env: Option<Vec<(String, String)>>,
) -> (String, String, Option<String>) {
    let mut cmd = Command::new(name);
    cmd.args(args);
    if let Some(env_vars) = custom_env {
        cmd.env_clear();
        for (k, v) in env_vars {
            cmd.env(k, v);
        }
    } else {
        cmd.env("PATH", augmented_path());
    }
    cmd.stdout(Stdio::piped());
    cmd.stderr(Stdio::piped());

    let mut child = match cmd.spawn() {
        Ok(c) => c,
        Err(e) => {
            if e.kind() == std::io::ErrorKind::NotFound {
                return (
                    String::new(),
                    String::new(),
                    Some(format!(
                        "exec: {:?}: executable file not found in $PATH",
                        name
                    )),
                );
            }
            return (String::new(), String::new(), Some(e.to_string()));
        }
    };

    let stdout_pipe = child.stdout.take();
    let stderr_pipe = child.stderr.take();
    let out_handle = thread::spawn(move || {
        let mut buf = Vec::new();
        if let Some(mut p) = stdout_pipe {
            let _ = p.read_to_end(&mut buf);
        }
        String::from_utf8_lossy(&buf).into_owned()
    });
    let err_handle = thread::spawn(move || {
        let mut buf = Vec::new();
        if let Some(mut p) = stderr_pipe {
            let _ = p.read_to_end(&mut buf);
        }
        String::from_utf8_lossy(&buf).into_owned()
    });

    let pid = child.id() as i32;
    let (tx, rx) = mpsc::channel();
    let wait_handle = thread::spawn(move || {
        let st = child.wait();
        let _ = tx.send(st);
    });

    let err_opt = match rx.recv_timeout(limit) {
        Ok(Ok(status)) => {
            let _ = wait_handle.join();
            if status.success() {
                None
            } else {
                let code = status.code().unwrap_or(1);
                Some(format!("exit status {}", code))
            }
        }
        Ok(Err(e)) => {
            let _ = wait_handle.join();
            Some(e.to_string())
        }
        Err(_) => {
            unsafe {
                extern "C" {
                    fn kill(pid: i32, sig: i32) -> i32;
                }
                let _ = kill(pid, 9);
            }
            let _ = wait_handle.join();
            Some(format!("{}: no answer within {}s", name, limit.as_secs()))
        }
    };

    let stdout = out_handle.join().unwrap_or_default();
    let stderr = err_handle.join().unwrap_or_default();
    (stdout, stderr, err_opt)
}

pub fn run_cmd(name: &str, args: &[&str]) -> Result<String, String> {
    run_cmd_within(CMD_TIMEOUT, name, args)
}

pub fn run_cmd_within(limit: Duration, name: &str, args: &[&str]) -> Result<String, String> {
    let owned: Vec<String> = args.iter().map(|s| (*s).to_string()).collect();
    let (stdout, _, err) = run_tool_within(limit, name, &owned, None);
    match err {
        Some(e) => Err(e),
        None => Ok(stdout),
    }
}

pub fn run_tool(name: &str, args: &[&str]) -> (String, String, Option<String>) {
    let owned: Vec<String> = args.iter().map(|s| (*s).to_string()).collect();
    run_tool_within(TOOL_TIMEOUT, name, &owned, None)
}

pub fn tool_reason(name: &str, stderr: &str, err: &str) -> String {
    let line = first_line(stderr);
    if !line.is_empty() {
        return line;
    }
    if err.contains("executable file not found") {
        return format!("{} is not installed", name);
    }
    format!("{}: {}", name, err)
}

pub fn tool_presence(names: &[&str]) -> Tools {
    let mut tools = BTreeMap::new();
    for &n in names {
        if n == "homespeaker" {
            let avail = Path::new(HOME_SPEAKER_BINARY).exists();
            tools.insert(
                n.to_string(),
                Tool {
                    available: avail,
                    path: HOME_SPEAKER_BINARY.to_string(),
                },
            );
            continue;
        }
        match find_executable_in_path(n) {
            Some(p) => {
                let mut avail = true;
                if n == "xcodebuild" {
                    let (_, _, err) = run_tool_within(
                        Duration::from_secs(5),
                        &p,
                        &["-version".to_string()],
                        None,
                    );
                    avail = err.is_none();
                }
                tools.insert(
                    n.to_string(),
                    Tool {
                        available: avail,
                        path: p,
                    },
                );
            }
            None => {
                tools.insert(
                    n.to_string(),
                    Tool {
                        available: false,
                        path: String::new(),
                    },
                );
            }
        }
    }
    Tools { tools }
}

pub fn split_repos(csv: &str) -> Vec<String> {
    let mut out = Vec::new();
    for r in csv.split(',') {
        let trimmed = r.trim();
        if !trimmed.is_empty() {
            out.push(trimmed.to_string());
        }
    }
    out
}

pub fn read_tail(path: &Path, n: usize) -> String {
    let Ok(mut fh) = File::open(path) else {
        return String::new();
    };
    let Ok(meta) = fh.metadata() else {
        return String::new();
    };
    let len = meta.len();
    if len > n as u64 {
        if fh.seek(SeekFrom::End(-(n as i64))).is_err() {
            return String::new();
        }
    }
    let mut buf = Vec::new();
    if fh.take(n as u64).read_to_end(&mut buf).is_err() {
        return String::new();
    }
    String::from_utf8_lossy(&buf).into_owned()
}

pub fn gh_search_argv(author: &str) -> Vec<String> {
    vec![
        "search".to_string(),
        "prs".to_string(),
        "--author".to_string(),
        author.to_string(),
        "--state".to_string(),
        "open".to_string(),
        "--json".to_string(),
        "number,repository,title,url,updatedAt".to_string(),
        "--limit".to_string(),
        "20".to_string(),
    ]
}

pub fn gh_search_repo_argv(repo: &str) -> Vec<String> {
    vec![
        "search".to_string(),
        "prs".to_string(),
        "--repo".to_string(),
        repo.to_string(),
        "--state".to_string(),
        "open".to_string(),
        "--json".to_string(),
        "number,repository,title,url,updatedAt".to_string(),
        "--limit".to_string(),
        "20".to_string(),
    ]
}

pub fn gh_view_argv(repo: &str, number: i32) -> Vec<String> {
    vec![
        "pr".to_string(),
        "view".to_string(),
        number.to_string(),
        "--repo".to_string(),
        repo.to_string(),
        "--json".to_string(),
        "isDraft,headRefName,baseRefName,mergeStateStatus,reviewDecision,statusCheckRollup,autoMergeRequest,author".to_string(),
    ]
}

pub fn pr_action_argv(action: &str, repo: &str, number: i32) -> Result<Vec<String>, String> {
    let n = number.to_string();
    match action {
        "approve" => Ok(vec![
            "pr".to_string(),
            "review".to_string(),
            n,
            "--repo".to_string(),
            repo.to_string(),
            "--approve".to_string(),
        ]),
        "merge" => Ok(vec![
            "pr".to_string(),
            "merge".to_string(),
            n,
            "--repo".to_string(),
            repo.to_string(),
            "--merge".to_string(),
        ]),
        "auto_merge" => Ok(vec![
            "pr".to_string(),
            "merge".to_string(),
            n,
            "--repo".to_string(),
            repo.to_string(),
            "--auto".to_string(),
            "--merge".to_string(),
        ]),
        "ready" => Ok(vec![
            "pr".to_string(),
            "ready".to_string(),
            n,
            "--repo".to_string(),
            repo.to_string(),
        ]),
        other => Err(format!(
            "unknown action {:?} (want approve, merge, auto_merge or ready)",
            other
        )),
    }
}

pub fn kubectl_args(kubeconfig: &str, kube_context: &str, rest: &[&str]) -> Vec<String> {
    let mut args = Vec::new();
    if !kubeconfig.is_empty() {
        args.push("--kubeconfig".to_string());
        args.push(kubeconfig.to_string());
    }
    if !kube_context.is_empty() {
        args.push("--context".to_string());
        args.push(kube_context.to_string());
    }
    for &r in rest {
        args.push(r.to_string());
    }
    args
}

pub fn argo_sync_argv(
    kubeconfig: &str,
    kube_context: &str,
    namespace: &str,
    name: &str,
) -> Vec<String> {
    kubectl_args(
        kubeconfig,
        kube_context,
        &[
            "-n",
            namespace,
            "patch",
            "application",
            name,
            "--type",
            "merge",
            "-p",
            r#"{"operation":{"initiatedBy":{"username":"vitruvian-remote"},"sync":{}}}"#,
        ],
    )
}

pub fn resume_argv(session_id: &str, prompt: &str) -> Vec<String> {
    vec![
        "claude".to_string(),
        "--resume".to_string(),
        session_id.to_string(),
        "-p".to_string(),
        prompt.to_string(),
        "--output-format".to_string(),
        "text".to_string(),
    ]
}

#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub struct ScreenRegion {
    pub x: f64,
    pub y: f64,
    pub w: f64,
    pub h: f64,
}

impl ScreenRegion {
    pub fn full(&self) -> bool {
        self.w == 0.0
            || self.h == 0.0
            || (self.x <= 0.0 && self.y <= 0.0 && self.w >= 1.0 && self.h >= 1.0)
    }
}

pub fn parse_screen_region(q: &HashMap<String, String>) -> Result<ScreenRegion, String> {
    let raw = [
        q.get("x").map(|s| s.as_str()).unwrap_or(""),
        q.get("y").map(|s| s.as_str()).unwrap_or(""),
        q.get("w").map(|s| s.as_str()).unwrap_or(""),
        q.get("h").map(|s| s.as_str()).unwrap_or(""),
    ];
    let given = raw.iter().filter(|v| !v.is_empty()).count();
    if given == 0 {
        return Ok(ScreenRegion::default());
    }
    if given != 4 {
        return Err("x, y, w and h must all be given, as fractions of the display".to_string());
    }
    let mut f = [0.0f64; 4];
    for (i, v) in raw.iter().enumerate() {
        let Ok(n) = v.parse::<f64>() else {
            return Err("x, y, w and h must be numbers between 0 and 1".to_string());
        };
        if !n.is_finite() {
            return Err("x, y, w and h must be numbers between 0 and 1".to_string());
        }
        f[i] = n;
    }
    let r = ScreenRegion {
        x: f[0],
        y: f[1],
        w: f[2],
        h: f[3],
    };
    if r.w < MIN_SCREEN_FRACTION
        || r.h < MIN_SCREEN_FRACTION
        || r.w > 1.0
        || r.h > 1.0
        || r.x < 0.0
        || r.y < 0.0
        || r.x + r.w > 1.0001
        || r.y + r.h > 1.0001
    {
        return Err(format!(
            "the region must lie inside the display and be at least {} of it each way",
            MIN_SCREEN_FRACTION
        ));
    }
    Ok(r)
}

pub fn crop_box(pw: i32, ph: i32, r: ScreenRegion) -> (i32, i32, i32, i32) {
    let mut x = (r.x * (pw as f64)).round() as i32;
    let mut y = (r.y * (ph as f64)).round() as i32;
    let mut w = (r.w * (pw as f64)).round() as i32;
    let mut h = (r.h * (ph as f64)).round() as i32;
    if w < 1 {
        w = 1;
    }
    if h < 1 {
        h = 1;
    }
    if x + w > pw {
        x = pw - w;
    }
    if y + h > ph {
        y = ph - h;
    }
    if x < 0 {
        x = 0;
    }
    if y < 0 {
        y = 0;
    }
    (x, y, w, h)
}

pub fn parse_sips_pixels(out: &str) -> (i32, i32) {
    let mut w = 0;
    let mut h = 0;
    for line in out.lines() {
        let Some((k, v)) = line.trim().split_once(':') else {
            continue;
        };
        let Ok(n) = v.trim().parse::<i32>() else {
            continue;
        };
        match k.trim() {
            "pixelWidth" => w = n,
            "pixelHeight" => h = n,
            _ => {}
        }
    }
    (w, h)
}

pub fn is_screen_denied(stderr: &str) -> bool {
    let s = stderr.to_ascii_lowercase();
    s.contains("could not create image")
        || s.contains("not authorized")
        || s.contains("screen recording")
}

pub fn screenshot_jpeg(width: i32, region: ScreenRegion) -> Result<Vec<u8>, String> {
    let width = width.clamp(MIN_SCREEN_WIDTH, MAX_SCREEN_WIDTH);
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    let dir = std::env::temp_dir().join(format!(
        "vitruvian-remote-screen-{}-{}",
        std::process::id(),
        nanos
    ));
    fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    let path = dir.join("screen.jpg");
    let path_str = path.to_string_lossy().into_owned();

    let result = (|| -> Result<Vec<u8>, String> {
        let (_, stderr, err) = run_tool_within(
            Duration::from_secs(15),
            "screencapture",
            &[
                "-x".to_string(),
                "-t".to_string(),
                "jpg".to_string(),
                path_str.clone(),
            ],
            None,
        );
        if let Some(e) = err {
            if is_screen_denied(&stderr) {
                return Err(ERR_SCREEN_RECORDING_DENIED.to_string());
            }
            let msg = first_line(&stderr);
            return Err(format!(
                "screencapture: {}",
                if msg.is_empty() { e } else { msg }
            ));
        }
        let Ok(meta) = fs::metadata(&path) else {
            return Err(ERR_SCREEN_RECORDING_DENIED.to_string());
        };
        if meta.len() == 0 {
            return Err(ERR_SCREEN_RECORDING_DENIED.to_string());
        }

        if !region.full() {
            let (out, stderr, err) = run_tool_within(
                Duration::from_secs(15),
                "sips",
                &[
                    "-g".to_string(),
                    "pixelWidth".to_string(),
                    "-g".to_string(),
                    "pixelHeight".to_string(),
                    path_str.clone(),
                ],
                None,
            );
            if let Some(e) = err {
                let msg = first_line(&stderr);
                return Err(format!("sips: {}", if msg.is_empty() { e } else { msg }));
            }
            let (pw, ph) = parse_sips_pixels(&out);
            if pw == 0 || ph == 0 {
                return Err("sips: could not read the capture's pixel size".to_string());
            }
            let (x, y, cw, ch) = crop_box(pw, ph, region);
            let (_, stderr, err) = run_tool_within(
                Duration::from_secs(15),
                "sips",
                &[
                    "--cropOffset".to_string(),
                    y.to_string(),
                    x.to_string(),
                    "-c".to_string(),
                    ch.to_string(),
                    cw.to_string(),
                    path_str.clone(),
                ],
                None,
            );
            if let Some(e) = err {
                let msg = first_line(&stderr);
                return Err(format!("sips: {}", if msg.is_empty() { e } else { msg }));
            }
        }

        let (_, stderr, err) = run_tool_within(
            Duration::from_secs(15),
            "sips",
            &[
                "--resampleWidth".to_string(),
                width.to_string(),
                path_str.clone(),
            ],
            None,
        );
        if let Some(e) = err {
            let msg = first_line(&stderr);
            return Err(format!("sips: {}", if msg.is_empty() { e } else { msg }));
        }
        fs::read(&path).map_err(|e| e.to_string())
    })();

    let _ = fs::remove_dir_all(&dir);
    result
}

struct SamplerState {
    snap: Snapshot,
    host: Host,
    processes: Processes,
    vms: VMs,
    container: Containers,
    k8s: K8s,
    audio: Audio,
    sessions: Sessions,
    ollama: Ollama,
    tools: Tools,
    antigravity: Antigravity,
    claude: ClaudeSessions,
    prs: PRs,
    argo: ArgoApps,
    prev_session_state: HashMap<String, String>,
    prev_pr_verdict: HashMap<String, String>,
    prev_net: Network,
    prev_at: Timestamp,
}

pub struct Sampler {
    state: RwLock<SamplerState>,
    notifier: Arc<Notifier>,
    gh_extra_repos: Vec<String>,
    interval: Duration,
    kubeconfig: String,
    kube_context: String,
}

impl Sampler {
    pub fn new(
        interval: Duration,
        kubeconfig: impl Into<String>,
        kube_context: impl Into<String>,
        gh_extra_repos: Vec<String>,
        notifier: Option<Arc<Notifier>>,
    ) -> Arc<Self> {
        let kubeconfig = kubeconfig.into();
        let kube_context = kube_context.into();
        let not_yet = "sampling";
        let kube_reason = if kube_context.is_empty() {
            NOT_CONFIGURED_KUBE
        } else {
            not_yet
        };
        let notifier = notifier.unwrap_or_else(|| Arc::new(Notifier::new("", "", "")));
        Arc::new(Self {
            state: RwLock::new(SamplerState {
                snap: Snapshot::default(),
                host: Host::default(),
                processes: Processes {
                    sampled_at: Timestamp::ZERO,
                    processes: Vec::new(),
                },
                vms: VMs {
                    available: false,
                    reason: not_yet.to_string(),
                    vms: Vec::new(),
                },
                container: Containers {
                    available: false,
                    runtime: String::new(),
                    reason: not_yet.to_string(),
                    containers: Vec::new(),
                },
                k8s: K8s {
                    available: false,
                    context: kube_context.clone(),
                    reason: kube_reason.to_string(),
                    nodes: Vec::new(),
                },
                audio: Audio::default(),
                sessions: Sessions {
                    running_processes: 0,
                    sessions: Vec::new(),
                },
                ollama: Ollama::default(),
                tools: Tools::default(),
                antigravity: Antigravity::default(),
                claude: ClaudeSessions {
                    running: 0,
                    sessions: Vec::new(),
                },
                prs: PRs {
                    available: false,
                    reason: not_yet.to_string(),
                    sampled_at: Timestamp::ZERO,
                    prs: Vec::new(),
                },
                argo: ArgoApps {
                    available: false,
                    reason: kube_reason.to_string(),
                    apps: Vec::new(),
                },
                prev_session_state: HashMap::new(),
                prev_pr_verdict: HashMap::new(),
                prev_net: Network::default(),
                prev_at: Timestamp::ZERO,
            }),
            notifier,
            gh_extra_repos,
            interval,
            kubeconfig,
            kube_context,
        })
    }

    pub fn snapshot(&self) -> Snapshot {
        self.state.read().unwrap().snap.clone()
    }

    pub fn set_snapshot(&self, snap: Snapshot) {
        self.state.write().unwrap().snap = snap;
    }

    pub fn host(&self) -> Host {
        self.state.read().unwrap().host.clone()
    }

    pub fn set_host(&self, host: Host) {
        self.state.write().unwrap().host = host;
    }

    pub fn processes(&self) -> Processes {
        self.state.read().unwrap().processes.clone()
    }

    pub fn tools(&self) -> Tools {
        self.state.read().unwrap().tools.clone()
    }

    pub fn antigravity(&self) -> Antigravity {
        self.state.read().unwrap().antigravity.clone()
    }

    pub fn ollama(&self) -> Ollama {
        self.state.read().unwrap().ollama.clone()
    }

    pub fn vms(&self) -> VMs {
        self.state.read().unwrap().vms.clone()
    }

    pub fn containers(&self) -> Containers {
        self.state.read().unwrap().container.clone()
    }

    pub fn k8s(&self) -> K8s {
        self.state.read().unwrap().k8s.clone()
    }

    pub fn audio(&self) -> Audio {
        self.state.read().unwrap().audio.clone()
    }

    pub fn set_audio(&self, a: Audio) {
        self.state.write().unwrap().audio = a;
    }

    pub fn sessions(&self) -> Sessions {
        self.state.read().unwrap().sessions.clone()
    }

    pub fn claude_sessions(&self) -> ClaudeSessions {
        self.state.read().unwrap().claude.clone()
    }

    pub fn set_claude_sessions(&self, c: ClaudeSessions) {
        self.state.write().unwrap().claude = c;
    }

    pub fn prs(&self) -> PRs {
        self.state.read().unwrap().prs.clone()
    }

    pub fn set_prs(&self, p: PRs) {
        self.state.write().unwrap().prs = p;
    }

    pub fn argocd(&self) -> ArgoApps {
        self.state.read().unwrap().argo.clone()
    }

    pub fn set_argocd(&self, a: ArgoApps) {
        self.state.write().unwrap().argo = a;
    }

    pub fn notifier(&self) -> &Arc<Notifier> {
        &self.notifier
    }

    pub fn kubeconfig(&self) -> &str {
        &self.kubeconfig
    }

    pub fn kube_context(&self) -> &str {
        &self.kube_context
    }

    pub fn notify_session_transitions(&self, sessions: &ClaudeSessions) {
        if !self.notifier.configured() {
            return;
        }
        let prev = {
            let mut st = self.state.write().unwrap();
            let mut next = HashMap::with_capacity(sessions.sessions.len());
            for sess in &sessions.sessions {
                next.insert(sess.session_id.clone(), sess.state.clone());
            }
            std::mem::replace(&mut st.prev_session_state, next)
        };

        for sess in &sessions.sessions {
            let was = prev.get(&sess.session_id).map(|s| s.as_str()).unwrap_or("");
            if was == sess.state {
                continue;
            }
            let project = Path::new(&sess.project)
                .file_name()
                .and_then(|s| s.to_str())
                .unwrap_or(&sess.project);
            match sess.state.as_str() {
                STATE_WAITING_FOR_PERMISSION => {
                    let _ = self.notifier.send(&Notification {
                        key: format!("claude:{}:permission", sess.session_id),
                        title: "Claude Code may be waiting".to_string(),
                        body: format!("{} · {} · no result for 90 s", project, sess.last_tool),
                        priority: "high".to_string(),
                        tags: "raised_hand".to_string(),
                        click: "vitruvian-remote://sessions".to_string(),
                    });
                }
                STATE_IDLE => {
                    if was != STATE_WORKING {
                        continue;
                    }
                    let _ = self.notifier.send(&Notification {
                        key: format!("claude:{}:idle", sess.session_id),
                        title: "Claude Code finished a turn".to_string(),
                        body: format!("{} · {}", project, trim_runes(&sess.last_text, 120)),
                        priority: "default".to_string(),
                        tags: "white_check_mark".to_string(),
                        click: "vitruvian-remote://sessions".to_string(),
                    });
                }
                _ => {}
            }
        }
    }

    pub fn notify_pr_transitions(&self, prs: &PRs) {
        if !self.notifier.configured() || !prs.available {
            return;
        }
        let prev = {
            let mut st = self.state.write().unwrap();
            let mut next = HashMap::with_capacity(prs.prs.len());
            for pr in &prs.prs {
                next.insert(
                    format!("{}#{}", pr.repo, pr.number),
                    pr_checks_verdict(&pr.checks).to_string(),
                );
            }
            std::mem::replace(&mut st.prev_pr_verdict, next)
        };

        for pr in &prs.prs {
            let id = format!("{}#{}", pr.repo, pr.number);
            let verdict = pr_checks_verdict(&pr.checks);
            if verdict.is_empty() {
                continue;
            }
            let Some(was) = prev.get(&id) else {
                continue;
            };
            if was == verdict {
                continue;
            }
            let (title, tag, prio) = if verdict == "red" {
                (format!("PR #{} checks failed", pr.number), "x", "high")
            } else {
                (
                    format!("PR #{} checks green", pr.number),
                    "white_check_mark",
                    "default",
                )
            };
            let _ = self.notifier.send(&Notification {
                key: format!("pr:{}:{}", id, verdict),
                title,
                body: pr.title.clone(),
                priority: prio.to_string(),
                tags: tag.to_string(),
                click: "vitruvian-remote://prs".to_string(),
            });
        }
    }

    pub fn run(self: &Arc<Self>, cancel: CancelToken) {
        self.read_host();

        let s_cpu = Arc::clone(self);
        let c_cpu = cancel.clone();
        thread::spawn(move || s_cpu.cpu_loop(c_cpu));

        let s_tools = Arc::clone(self);
        let c_tools = cancel.clone();
        thread::spawn(move || s_tools.tools_loop(c_tools));

        let s_agy = Arc::clone(self);
        let c_agy = cancel.clone();
        thread::spawn(move || s_agy.agy_loop(c_agy));

        let s_claude = Arc::clone(self);
        let c_claude = cancel.clone();
        thread::spawn(move || s_claude.claude_loop(c_claude));

        let s_prs = Arc::clone(self);
        let c_prs = cancel.clone();
        thread::spawn(move || s_prs.prs_loop(c_prs));

        let notifier = Arc::clone(&self.notifier);
        let hostname = self.host().hostname;
        thread::spawn(move || {
            let _ = notifier.send(&Notification {
                key: "agent:start".to_string(),
                title: "Agent online".to_string(),
                body: hostname,
                priority: "low".to_string(),
                tags: "computer".to_string(),
                click: "vitruvian-remote://mac".to_string(),
            });
        });

        self.fast_loop(cancel);
    }

    fn cpu_loop(&self, cancel: CancelToken) {
        while !cancel.is_cancelled() {
            if let Ok(out) = run_cmd_within(TOP_TIMEOUT, "top", &["-l", "2", "-n", "0", "-s", "1"])
            {
                if let Some((u, s, i)) = parse_top(&out) {
                    let mut st = self.state.write().unwrap();
                    st.snap.cpu.ready = true;
                    st.snap.cpu.user_percent = u;
                    st.snap.cpu.sys_percent = s;
                    st.snap.cpu.idle_percent = i;
                    st.snap.cpu.busy_percent = u + s;
                }
            }
            if cancel.wait_timeout(self.interval) {
                break;
            }
        }
    }

    fn fast_loop(&self, cancel: CancelToken) {
        while !cancel.is_cancelled() {
            self.read_fast();
            if cancel.wait_timeout(self.interval) {
                break;
            }
        }
    }

    fn tools_loop(&self, cancel: CancelToken) {
        while !cancel.is_cancelled() {
            self.read_tools();
            if cancel.wait_timeout(self.interval) {
                break;
            }
        }
    }

    fn agy_loop(&self, cancel: CancelToken) {
        while !cancel.is_cancelled() {
            let ag = self.read_antigravity();
            self.state.write().unwrap().antigravity = ag;
            if cancel.wait_timeout(Duration::from_secs(10 * 60)) {
                break;
            }
        }
    }

    fn claude_loop(&self, cancel: CancelToken) {
        while !cancel.is_cancelled() {
            let sessions = self.read_claude_sessions();
            self.state.write().unwrap().claude = sessions.clone();
            self.notify_session_transitions(&sessions);
            if cancel.wait_timeout(Duration::from_secs(5)) {
                break;
            }
        }
    }

    fn prs_loop(&self, cancel: CancelToken) {
        while !cancel.is_cancelled() {
            let prs = self.read_prs();
            self.state.write().unwrap().prs = prs.clone();
            self.notify_pr_transitions(&prs);
            if cancel.wait_timeout(Duration::from_secs(60)) {
                break;
            }
        }
    }

    pub fn read_host(&self) {
        let mut h = Host::default();
        let get = |key: &str| -> String {
            run_cmd("sysctl", &["-n", key])
                .map(|s| s.trim().to_string())
                .unwrap_or_default()
        };
        h.chip = get("machdep.cpu.brand_string");
        h.cores = get("hw.ncpu").parse::<i32>().unwrap_or(0);
        h.memory_bytes = get("hw.memsize").parse::<i64>().unwrap_or(0);
        if let Ok(out) = run_cmd("sw_vers", &["-productVersion"]) {
            h.os_version = out.trim().to_string();
        }
        if let Ok(out) = run_cmd("hostname", &["-s"]) {
            h.hostname = out.trim().to_string();
        }
        if let Ok(out) = run_cmd("ifconfig", &["en0"]) {
            if let Ok(mac) = parse_ether(&out) {
                h.mac_address = mac;
            }
        }
        if let Ok(out) = run_cmd("pmset", &["-g"]) {
            h.wake_on_lan = parse_womp(&out);
        }
        self.state.write().unwrap().host = h;
    }

    fn read_fast(&self) {
        let now = Timestamp::now();
        let mut next = Snapshot::default();
        let mem_bytes = self.state.read().unwrap().host.memory_bytes;

        if let Ok(out) = run_cmd("vm_stat", &[]) {
            next.memory = parse_vm_stat(&out, mem_bytes);
        }
        if let Ok(out) = run_cmd("ioreg", &["-r", "-c", "AppleSmartBattery", "-d", "1"]) {
            let mut b = parse_battery(&out);
            if b.present && b.temperature_c.is_none() {
                if let Ok(full) = run_cmd("ioreg", &["-r", "-c", "AppleSmartBattery", "-l"]) {
                    if let Some(t) = parse_nested_battery_temperature(&full) {
                        b.temperature_c = Some(t);
                    }
                }
            }
            next.battery = b;
        }
        let disk_mount = if Path::new(DATA_VOLUME).exists() {
            DATA_VOLUME
        } else {
            "/"
        };
        if let Ok(out) = run_cmd("df", &["-k", disk_mount]) {
            next.disk = parse_df(&out);
        }
        if let Ok(out) = run_cmd("pmset", &["-g", "therm"]) {
            next.thermal = parse_therm(&out);
        }
        if let Ok(out) = run_cmd("sysctl", &["-n", "kern.boottime"]) {
            if let Some(up) = parse_boottime(&out, now) {
                next.uptime_seconds = up;
            }
        }
        let iface = run_cmd("route", &["-n", "get", "default"])
            .ok()
            .map(|out| parse_default_interface(&out))
            .unwrap_or_default();
        if !iface.is_empty() {
            if let Ok(out) = run_cmd("netstat", &["-ibn"]) {
                if let Some((rx, tx)) = parse_netstat(&out, &iface) {
                    let mut n = Network {
                        ready: true,
                        interface: iface.clone(),
                        rx_bytes: rx,
                        tx_bytes: tx,
                        rx_bytes_per_sec: 0.0,
                        tx_bytes_per_sec: 0.0,
                    };
                    let mut st = self.state.write().unwrap();
                    if st.prev_net.interface == iface && !st.prev_at.is_zero() {
                        let dt = now.duration_since(st.prev_at).as_secs_f64();
                        if dt > 0.0
                            && n.rx_bytes >= st.prev_net.rx_bytes
                            && n.tx_bytes >= st.prev_net.tx_bytes
                        {
                            n.rx_bytes_per_sec = ((n.rx_bytes - st.prev_net.rx_bytes) as f64) / dt;
                            n.tx_bytes_per_sec = ((n.tx_bytes - st.prev_net.tx_bytes) as f64) / dt;
                        }
                    }
                    st.prev_net = n.clone();
                    st.prev_at = now;
                    next.network = n;
                }
            }
        }

        next.sampled_at = Timestamp::now();

        let load_out = run_cmd("sysctl", &["-n", "vm.loadavg"]).ok();
        let mut st = self.state.write().unwrap();
        next.cpu = st.snap.cpu.clone();
        if let Some(ref out) = load_out {
            if let Some((l1, l5, l15)) = parse_load_avg(out) {
                next.cpu.load_avg_1 = l1;
                next.cpu.load_avg_5 = l5;
                next.cpu.load_avg_15 = l15;
            }
        }
        st.snap = next;
    }

    fn read_tools(&self) {
        let procs = self.read_processes();
        let vms = self.read_vms();
        let containers = self.read_containers();
        let k8s = self.read_k8s();
        let sessions = self.read_sessions();
        let ollama = self.read_ollama();
        let argo = self.read_argocd();
        let tools = tool_presence(KNOWN_TOOLS);

        {
            let mut st = self.state.write().unwrap();
            st.tools = tools;
            if let Some(p) = procs {
                st.processes = Processes {
                    sampled_at: Timestamp::now(),
                    processes: p,
                };
            }
            st.vms = vms;
            st.container = containers;
            st.k8s = k8s;
            st.sessions = sessions;
            st.ollama = ollama;
            st.argo = argo;
        }

        if let Ok(out) = run_cmd("osascript", &["-e", "get volume settings"]) {
            if let Ok(a) = parse_volume_settings(&out) {
                self.set_audio(a);
            }
        }
    }

    fn read_processes(&self) -> Option<Vec<vitruvian_remote_macagent_metrics::Process>> {
        let out = run_cmd("ps", &["-Aceo", "pcpu,rss,comm", "-r"]).ok()?;
        let procs = parse_processes(&out, TOP_PROCESSES + OWN_SAMPLERS.len()).ok()?;
        let filtered: Vec<_> = procs
            .into_iter()
            .filter(|p| !OWN_SAMPLERS.contains(&p.name.as_str()))
            .take(TOP_PROCESSES)
            .collect();
        Some(filtered)
    }

    fn read_vms(&self) -> VMs {
        let (stdout, stderr, err) = run_tool("limactl", &["list", "--json"]);
        if let Some(e) = err {
            return VMs {
                available: false,
                reason: tool_reason("limactl", &stderr, &e),
                vms: Vec::new(),
            };
        }
        match parse_lima_list(&stdout) {
            Ok(vms) => VMs {
                available: true,
                reason: String::new(),
                vms,
            },
            Err(e) => VMs {
                available: false,
                reason: e,
                vms: Vec::new(),
            },
        }
    }

    fn read_containers(&self) -> Containers {
        let (docker_out, docker_stderr, docker_err) =
            run_tool("docker", &["ps", "--format", "{{json .}}"]);
        if docker_err.is_none() {
            return match parse_docker_ps(&docker_out) {
                Ok(cs) => Containers {
                    available: true,
                    runtime: "docker".to_string(),
                    reason: String::new(),
                    containers: cs,
                },
                Err(e) => Containers {
                    available: false,
                    runtime: String::new(),
                    reason: e,
                    containers: Vec::new(),
                },
            };
        }
        let (podman_out, _, podman_err) = run_tool("podman", &["ps", "--format", "json"]);
        if podman_err.is_none() {
            if let Ok(cs) = parse_podman_ps(&podman_out) {
                return Containers {
                    available: true,
                    runtime: "podman".to_string(),
                    reason: String::new(),
                    containers: cs,
                };
            }
        }
        Containers {
            available: false,
            runtime: String::new(),
            reason: tool_reason("docker", &docker_stderr, &docker_err.unwrap_or_default()),
            containers: Vec::new(),
        }
    }

    fn read_k8s(&self) -> K8s {
        if self.kube_context.is_empty() {
            return K8s {
                available: false,
                context: String::new(),
                reason: NOT_CONFIGURED_KUBE.to_string(),
                nodes: Vec::new(),
            };
        }
        let args = kubectl_args(
            &self.kubeconfig,
            &self.kube_context,
            &["get", "nodes", "-o", "json"],
        );
        let (stdout, stderr, err) = run_tool_within(TOOL_TIMEOUT, "kubectl", &args, None);
        if let Some(e) = err {
            return K8s {
                available: false,
                context: self.kube_context.clone(),
                reason: tool_reason("kubectl", &stderr, &e),
                nodes: Vec::new(),
            };
        }
        match parse_kubectl_nodes(&stdout) {
            Ok(nodes) => K8s {
                available: true,
                context: self.kube_context.clone(),
                reason: String::new(),
                nodes,
            },
            Err(e) => K8s {
                available: false,
                context: self.kube_context.clone(),
                reason: e,
                nodes: Vec::new(),
            },
        }
    }

    fn read_argocd(&self) -> ArgoApps {
        if self.kube_context.is_empty() {
            return ArgoApps {
                available: false,
                reason: NOT_CONFIGURED_KUBE.to_string(),
                apps: Vec::new(),
            };
        }
        let args = kubectl_args(
            &self.kubeconfig,
            &self.kube_context,
            &["get", "applications", "-A", "-o", "json"],
        );
        let (stdout, stderr, err) =
            run_tool_within(Duration::from_secs(20), "kubectl", &args, None);
        if let Some(e) = err {
            return ArgoApps {
                available: false,
                reason: tool_reason("kubectl", &stderr, &e),
                apps: Vec::new(),
            };
        }
        match parse_argo_apps(&stdout) {
            Ok(apps) => ArgoApps {
                available: true,
                reason: String::new(),
                apps,
            },
            Err(e) => ArgoApps {
                available: false,
                reason: e,
                apps: Vec::new(),
            },
        }
    }

    fn read_ollama(&self) -> Ollama {
        let (stdout, stderr, err) = run_tool("ollama", &["list"]);
        if let Some(e) = err {
            return Ollama {
                available: false,
                reason: tool_reason("ollama", &stderr, &e),
                models: Vec::new(),
                running: Vec::new(),
            };
        }
        let models = match parse_ollama_list(&stdout) {
            Ok(m) => m,
            Err(e) => {
                return Ollama {
                    available: false,
                    reason: e,
                    models: Vec::new(),
                    running: Vec::new(),
                };
            }
        };
        let mut running = Vec::new();
        let (ps_out, _, ps_err) = run_tool("ollama", &["ps"]);
        if ps_err.is_none() {
            if let Ok(r) = parse_ollama_ps(&ps_out) {
                running = r;
            }
        }
        Ollama {
            available: true,
            reason: String::new(),
            models,
            running,
        }
    }

    fn read_antigravity(&self) -> Antigravity {
        let (ver, stderr, err) = run_tool_within(
            Duration::from_secs(30),
            "agy",
            &["--version".to_string()],
            None,
        );
        if let Some(e) = err {
            return Antigravity {
                available: false,
                version: String::new(),
                reason: tool_reason("agy", &stderr, &e),
                models: Vec::new(),
                agents: Vec::new(),
            };
        }
        let mut out = Antigravity {
            available: true,
            version: ver.trim().to_string(),
            reason: String::new(),
            models: Vec::new(),
            agents: Vec::new(),
        };
        let (mo, _, merr) = run_tool_within(
            Duration::from_secs(30),
            "agy",
            &["models".to_string()],
            None,
        );
        if merr.is_none() {
            out.models = parse_agy_models(&mo);
        }
        let (ao, _, aerr) = run_tool_within(
            Duration::from_secs(30),
            "agy",
            &["agents".to_string()],
            None,
        );
        if aerr.is_none() {
            out.agents = parse_agy_agents(&ao);
        }
        out
    }

    fn read_sessions(&self) -> Sessions {
        let mut out = Sessions {
            running_processes: 0,
            sessions: Vec::new(),
        };
        if let Ok(ps) = run_cmd("ps", &["-Axo", "comm="]) {
            out.running_processes = count_processes_named(&ps, "claude");
        }
        let Ok(home) = std::env::var("HOME") else {
            return out;
        };
        let root = Path::new(&home).join(".claude").join("projects");
        let Ok(entries) = fs::read_dir(&root) else {
            return out;
        };
        let now_sys = SystemTime::now();
        let cutoff = now_sys.checked_sub(SESSION_WINDOW).unwrap_or(UNIX_EPOCH);
        for entry in entries.flatten() {
            let path = entry.path();
            if !path.is_dir() {
                continue;
            }
            let Ok(files) = fs::read_dir(&path) else {
                continue;
            };
            let mut newest: Option<SystemTime> = None;
            let mut newest_file: Option<PathBuf> = None;
            for f in files.flatten() {
                let fp = f.path();
                if fp.extension().and_then(|s| s.to_str()) != Some("jsonl") {
                    continue;
                }
                let Ok(meta) = f.metadata() else {
                    continue;
                };
                let Ok(mtime) = meta.modified() else {
                    continue;
                };
                if newest.map_or(true, |cur| mtime > cur) {
                    newest = Some(mtime);
                    newest_file = Some(fp);
                }
            }
            let (Some(newest_mtime), Some(newest_fp)) = (newest, newest_file) else {
                continue;
            };
            if newest_mtime < cutoff {
                continue;
            }
            let mut project = String::new();
            if let Ok(mut fh) = File::open(&newest_fp) {
                let mut buf = vec![0u8; 8192];
                let n = fh.read(&mut buf).unwrap_or(0);
                project = cwd_from_transcript(&String::from_utf8_lossy(&buf[..n]));
            }
            if project.is_empty() {
                let dir_name = entry.file_name().to_string_lossy().into_owned();
                project = project_from_dir_name(&dir_name);
            }
            let last_active_nanos = newest_mtime
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_nanos() as i128;
            out.sessions.push(Session {
                project,
                last_active: Timestamp::from_unix_nanos(last_active_nanos),
                path: path.to_string_lossy().into_owned(),
            });
        }
        out.sessions
            .sort_by(|a, b| b.last_active.cmp(&a.last_active));
        out
    }

    fn read_claude_sessions(&self) -> ClaudeSessions {
        let mut out = ClaudeSessions {
            running: 0,
            sessions: Vec::new(),
        };
        let Ok(home) = std::env::var("HOME") else {
            return out;
        };
        let root = Path::new(&home).join(".claude").join("projects");
        let Ok(entries) = fs::read_dir(&root) else {
            return out;
        };
        let now_sys = SystemTime::now();
        let now_ts = Timestamp::now();
        let cutoff = now_sys
            .checked_sub(CLAUDE_SESSION_WINDOW)
            .unwrap_or(UNIX_EPOCH);
        for entry in entries.flatten() {
            let path = entry.path();
            if !path.is_dir() {
                continue;
            }
            let Ok(files) = fs::read_dir(&path) else {
                continue;
            };
            let mut newest: Option<SystemTime> = None;
            let mut newest_file: Option<PathBuf> = None;
            for f in files.flatten() {
                let fp = f.path();
                if fp.extension().and_then(|s| s.to_str()) != Some("jsonl") {
                    continue;
                }
                let Ok(meta) = f.metadata() else {
                    continue;
                };
                let Ok(mtime) = meta.modified() else {
                    continue;
                };
                if newest.map_or(true, |cur| mtime > cur) {
                    newest = Some(mtime);
                    newest_file = Some(fp);
                }
            }
            let (Some(newest_mtime), Some(newest_fp)) = (newest, newest_file) else {
                continue;
            };
            if newest_mtime < cutoff {
                continue;
            }
            let tail = read_tail(&newest_fp, TRANSCRIPT_TAIL);
            let mut sess = parse_transcript_tail(&tail, now_ts);
            let dir_name = entry.file_name().to_string_lossy().into_owned();
            if sess.project.is_empty() {
                sess.project = project_from_dir_name(&dir_name);
            }
            if sess.updated_at.is_zero() {
                let nanos = newest_mtime
                    .duration_since(UNIX_EPOCH)
                    .unwrap_or_default()
                    .as_nanos() as i128;
                sess.updated_at = Timestamp::from_unix_nanos(nanos);
            }
            sess.session_id = newest_fp
                .file_stem()
                .and_then(|s| s.to_str())
                .unwrap_or("")
                .to_string();
            out.sessions.push(sess);
        }
        out.sessions.sort_by(|a, b| b.updated_at.cmp(&a.updated_at));
        out
    }

    fn read_prs(&self) -> PRs {
        let (mut refs, reason) = self.search_prs(&gh_search_argv("@me"));
        if !reason.is_empty() {
            return PRs {
                available: false,
                reason,
                sampled_at: Timestamp::ZERO,
                prs: Vec::new(),
            };
        }
        for repo in &self.gh_extra_repos {
            let (extra, _) = self.search_prs(&gh_search_repo_argv(repo));
            refs.extend(extra);
        }
        let mut seen = HashMap::new();
        let mut out = Vec::with_capacity(refs.len());
        for r in refs {
            let id = format!("{}#{}", r.repo, r.number);
            if seen.insert(id, true).is_some() {
                continue;
            }
            let mut pr = PR {
                repo: r.repo.clone(),
                number: r.number,
                title: r.title.clone(),
                url: r.url.clone(),
                updated_at: r.updated_at,
                ..Default::default()
            };
            let (stdout, _, err) = run_tool_within(
                Duration::from_secs(20),
                "gh",
                &gh_view_argv(&r.repo, r.number),
                None,
            );
            if err.is_none() {
                if let Ok(mut detail) = parse_gh_pr_view(&stdout) {
                    detail.repo = pr.repo;
                    detail.number = pr.number;
                    detail.title = pr.title;
                    detail.url = pr.url;
                    detail.updated_at = pr.updated_at;
                    pr = detail;
                }
            }
            out.push(pr);
        }
        PRs {
            available: true,
            reason: String::new(),
            sampled_at: Timestamp::now(),
            prs: out,
        }
    }

    fn search_prs(&self, args: &[String]) -> (Vec<PRRef>, String) {
        let (stdout, stderr, err) = run_tool_within(Duration::from_secs(30), "gh", args, None);
        if let Some(e) = err {
            return (Vec::new(), tool_reason("gh", &stderr, &e));
        }
        match parse_gh_search_prs(&stdout) {
            Ok(refs) => (refs, String::new()),
            Err(e) => (Vec::new(), e),
        }
    }
}
