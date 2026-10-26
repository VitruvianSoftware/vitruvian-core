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

//! Command macagent is the Mac half of Vitruvian Remote: a small daemon that
//! serves the machine's vital signs over HTTP and runs paired actions.

use std::fs;
use std::io;
use std::net::TcpListener;
use std::path::PathBuf;
use std::sync::Arc;
use std::thread;
use std::time::Duration;

use vitruvian_remote_macagent::exec::set_exec_dir;
use vitruvian_remote_macagent::hook::{run_install_claude_hook, run_permission_hook};
use vitruvian_remote_macagent::http_util::{log_line, serve_listener, CancelToken};
use vitruvian_remote_macagent::notify::Notifier;
use vitruvian_remote_macagent::pair::{default_config_dir, expand_home, Store, PAIR_TTL};
use vitruvian_remote_macagent::permission::{
    clamp_permission_wait, log_permission_wait, set_permission_wait, PERMISSION_WAIT_DEFAULT,
};
use vitruvian_remote_macagent::sampler::{extend_path, split_repos, Sampler};
use vitruvian_remote_macagent::server::{Server, DEFAULT_PORT, VERSION};
use vitruvian_remote_macagent::tailnet::{tailscale_ipv4, TailnetListener, TailnetWatcher};

struct TcpTailnetListener {
    listener: TcpListener,
    cancel: CancelToken,
}

impl TailnetListener for TcpTailnetListener {
    fn close(&self) {
        self.cancel.cancel();
        if let Ok(addr) = self.listener.local_addr() {
            let _ = std::net::TcpStream::connect_timeout(&addr, Duration::from_millis(50));
        }
    }
}

fn parse_duration(s: &str) -> Option<Duration> {
    let s = s.trim();
    if let Some(ms) = s.strip_suffix("ms") {
        return ms.parse::<u64>().ok().map(Duration::from_millis);
    }
    if let Some(sec) = s.strip_suffix('s') {
        return sec.parse::<u64>().ok().map(Duration::from_secs);
    }
    if let Some(min) = s.strip_suffix('m') {
        return min.parse::<u64>().ok().map(|m| Duration::from_secs(m * 60));
    }
    s.parse::<u64>().ok().map(Duration::from_secs)
}

fn read_token_file(p: &str) -> String {
    if p.is_empty() {
        return String::new();
    }
    let path = expand_home(p);
    match fs::read_to_string(&path) {
        Ok(b) => b.trim().to_string(),
        Err(e) => {
            log_line(&format!("prometheus-token-file: {}", e));
            std::process::exit(1);
        }
    }
}

fn print_usage() {
    eprintln!(
        "vitruvian-remote-agent v{} -- the Mac half of Vitruvian Remote\n",
        VERSION
    );
    eprintln!(
        r#"Reading (metrics, host, processes, vms, containers, k8s, audio, sessions,
claude/sessions, antigravity/sessions, prs, argocd, promql, phone, healthz)
needs no auth. Acting (exec, exec/stream, claude/resume, antigravity/resume,
prs/action, argocd/sync, screen, clipboard, audio, power, notify/test,
phone/link, phone/result) needs a bearer token, which only pairing issues.

POST /mcp/phone is the MCP server that puts the linked phone's tools in front
of Claude Code and Antigravity. Loopback only, and a token of its own in
~/.config/vitruvian-remote-agent/mcp-token (see the README).

POST /v1/claude/permission/ask is where Claude Code's permission hook parks a
prompt for the phone. Loopback only, with ~/.config/vitruvian-remote-agent/
hook-token. The phone's toggle installs or removes the hook.

Commands:
  pair <code>      open a five-minute window for the phone showing <code>
  token [--rotate] print the token, or issue a new one and un-pair everything
  permission-hook  Claude Code's PermissionRequest hook (stdin -> stdout);
                   prints a decision or nothing, always exits 0
  install-claude-hook [--remove] [--settings PATH]
                   add or remove that hook in ~/.claude/settings.json

Install as a login item with:  bazel run //mobile/android/remote/macagent:install
Pair a phone with:            bazel run //mobile/android/remote/macagent:pair -- 482917"#
    );
}

fn subcommand(name: &str, args: &[String]) -> Result<(), String> {
    let mut config_dir = default_config_dir();
    let mut rotate = false;
    let mut pos = Vec::new();
    let mut i = 0;
    while i < args.len() {
        let a = &args[i];
        if a == "--config-dir" || a == "-config-dir" {
            i += 1;
            if i >= args.len() {
                return Err("missing value for --config-dir".to_string());
            }
            config_dir = PathBuf::from(&args[i]);
        } else if let Some(v) = a
            .strip_prefix("--config-dir=")
            .or_else(|| a.strip_prefix("-config-dir="))
        {
            config_dir = PathBuf::from(v);
        } else if a == "--rotate" || a == "-rotate" {
            rotate = true;
        } else {
            pos.push(a.clone());
        }
        i += 1;
    }

    match name {
        "pair" => {
            if pos.len() != 1 {
                return Err(
                    "usage: vitruvian-remote-agent pair <the six-digit code the phone is showing>"
                        .to_string(),
                );
            }
            let store = Store::new(config_dir);
            store.ensure_token()?;
            store.write_pairing(&pos[0])?;
            println!(
                "pairing open for {}s: the phone showing {} may now claim a token.",
                PAIR_TTL.as_secs(),
                pos[0]
            );
            println!("Nothing else to do -- a running agent picks this up without a restart.");
            Ok(())
        }
        "token" => {
            let store = Store::new(config_dir);
            if rotate {
                let tok = store.rotate_token()?;
                println!("{}", tok);
                eprintln!("every previously paired phone must pair again.");
                return Ok(());
            }
            let tok = store.ensure_token()?;
            println!("{}", tok);
            Ok(())
        }
        "install-claude-hook" => run_install_claude_hook(args),
        other => Err(format!(
            "unknown command {:?} (want pair, token, permission-hook or install-claude-hook)",
            other
        )),
    }
}

fn main() {
    extend_path();

    let args: Vec<String> = std::env::args().collect();
    if args.len() > 1 && args[1] == "permission-hook" {
        let mut stdin = io::stdin();
        let mut stdout = io::stdout();
        run_permission_hook(&args[2..], &mut stdin, &mut stdout);
        return;
    }
    if args.len() > 1 && !args[1].starts_with('-') {
        if let Err(e) = subcommand(&args[1], &args[2..]) {
            log_line(&e);
            std::process::exit(1);
        }
        return;
    }

    let mut listen = format!("127.0.0.1:{}", DEFAULT_PORT);
    let mut tailscale = true;
    let mut interval = Duration::from_secs(2);
    let mut config_dir = String::new();
    let mut kube_cfg = String::new();
    let mut kube_ctx = String::new();
    let mut prom_url = String::new();
    let mut prom_tok = String::new();
    let mut ntfy_url = String::new();
    let mut ntfy_topic = String::new();
    let mut ntfy_tok = String::new();
    let mut gh_repos = String::new();
    let mut exec_dir_f = String::new();
    let mut perm_wait = PERMISSION_WAIT_DEFAULT;

    let mut i = 1;
    while i < args.len() {
        let arg = &args[i];
        if arg == "-h" || arg == "--help" {
            print_usage();
            return;
        }
        let (key, val_opt) = if let Some((k, v)) = arg.split_once('=') {
            (k.trim_start_matches('-'), Some(v.to_string()))
        } else {
            (arg.trim_start_matches('-'), None)
        };
        let mut next_val = || -> String {
            if let Some(ref v) = val_opt {
                v.clone()
            } else {
                i += 1;
                args.get(i).cloned().unwrap_or_default()
            }
        };
        match key {
            "listen" => listen = next_val(),
            "tailscale" => {
                if let Some(ref v) = val_opt {
                    tailscale = v == "true" || v == "1";
                } else {
                    tailscale = true;
                }
            }
            "interval" => {
                let v = next_val();
                if let Some(d) = parse_duration(&v) {
                    interval = d;
                }
            }
            "config-dir" => config_dir = next_val(),
            "kubeconfig" => kube_cfg = next_val(),
            "kube-context" => kube_ctx = next_val(),
            "prometheus-url" => prom_url = next_val(),
            "prometheus-token-file" => prom_tok = next_val(),
            "ntfy-url" => ntfy_url = next_val(),
            "ntfy-topic" => ntfy_topic = next_val(),
            "ntfy-token-file" => ntfy_tok = next_val(),
            "gh-extra-repos" => gh_repos = next_val(),
            "exec-dir" => exec_dir_f = next_val(),
            "permission-wait" => {
                let v = next_val();
                if let Some(d) = parse_duration(&v) {
                    perm_wait = d;
                }
            }
            _ => {}
        }
        i += 1;
    }

    let clamped_wait = clamp_permission_wait(perm_wait);
    set_permission_wait(clamped_wait);
    log_permission_wait(perm_wait, clamped_wait);

    let store_path = if config_dir.is_empty() {
        default_config_dir()
    } else {
        PathBuf::from(&config_dir)
    };
    let store = Arc::new(Store::new(store_path));
    if let Err(e) = store.ensure_token() {
        log_line(&format!("token: {}", e));
        std::process::exit(1);
    }
    if let Err(e) = store.ensure_mcp_token() {
        log_line(&format!("mcp-token: {}", e));
        std::process::exit(1);
    }
    if let Err(e) = store.ensure_hook_token() {
        log_line(&format!("hook-token: {}", e));
        std::process::exit(1);
    }

    let notifier = Arc::new(Notifier::new(
        &ntfy_url,
        &ntfy_topic,
        &read_token_file(&ntfy_tok),
    ));
    notifier.set_enabled(store.notify_enabled());
    if !ntfy_url.is_empty() && !notifier.configured() {
        log_line("--ntfy-url without --ntfy-topic: there is nowhere to publish to");
        std::process::exit(1);
    }

    if !exec_dir_f.is_empty() {
        let d = expand_home(&exec_dir_f);
        if !d.is_dir() {
            log_line(&format!("--exec-dir {:?} is not a directory", d));
            std::process::exit(1);
        }
        set_exec_dir(d);
    }

    let cancel = CancelToken::new();
    let kube_cfg_path = if kube_cfg.is_empty() {
        String::new()
    } else {
        expand_home(&kube_cfg).to_string_lossy().into_owned()
    };
    let sampler = Sampler::new(
        interval,
        kube_cfg_path,
        kube_ctx,
        split_repos(&gh_repos),
        Some(notifier),
    );
    let sampler_bg = Arc::clone(&sampler);
    let cancel_bg = cancel.clone();
    thread::spawn(move || sampler_bg.run(cancel_bg));

    let srv = Server::new(sampler, store, prom_url, read_token_file(&prom_tok));

    let ln = match TcpListener::bind(&listen) {
        Ok(l) => l,
        Err(e) => {
            log_line(&format!("listen {}: {}", listen, e));
            std::process::exit(1);
        }
    };
    log_line(&format!(
        "serving on http://{} (v{}); act endpoints need a paired token",
        listen, VERSION
    ));

    if tailscale {
        let port = listen
            .rsplit_once(':')
            .map(|(_, p)| p.to_string())
            .unwrap_or_else(|| DEFAULT_PORT.to_string());
        let srv_ts = Arc::clone(&srv);
        let watcher = TailnetWatcher::new(
            port,
            tailscale_ipv4,
            move |addr| {
                let l = TcpListener::bind(addr).map_err(|e| e.to_string())?;
                let l2 = l.try_clone().map_err(|e| e.to_string())?;
                let c = CancelToken::new();
                let c2 = c.clone();
                let srv_clone = Arc::clone(&srv_ts);
                thread::spawn(move || {
                    serve_listener(l2, Arc::new(move |req: &_| srv_clone.handle(req)), c2);
                });
                let res: Arc<dyn TailnetListener> = Arc::new(TcpTailnetListener {
                    listener: l,
                    cancel: c,
                });
                Ok(res)
            },
            |_| {},
        );
        let cancel_ts = cancel.clone();
        thread::spawn(move || watcher.run(cancel_ts, Duration::from_secs(5)));
    }

    serve_listener(ln, Arc::new(move |req: &_| srv.handle(req)), cancel);
}
