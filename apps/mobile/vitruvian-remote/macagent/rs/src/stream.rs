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

//! SSE streaming command execution (`POST /v1/exec/stream`) with process-group cleanup.

use std::io::{BufRead, BufReader};
use std::os::unix::process::CommandExt;
use std::process::{Command, Stdio};
use std::sync::mpsc::{self, Sender};
use std::thread;
use std::time::{Duration, Instant};

use vitruvian_remote_macagent_metrics::{JsonMap, JsonValue};

use crate::exec::ExecRequest;
use crate::http_util::{agent_log, CancelToken, HttpRequest, HttpResponse, SseSink};
use crate::sampler::augmented_path;

pub const DEFAULT_STREAM_TIMEOUT_SEC: i32 = 300;
pub const MAX_STREAM_TIMEOUT_SEC: i32 = 600;

extern "C" {
    fn kill(pid: i32, sig: i32) -> i32;
}

const SIGTERM: i32 = 15;
const SIGKILL: i32 = 9;

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct StreamLine {
    pub stream: String,
    pub text: String,
}

impl StreamLine {
    pub fn to_json_value(&self) -> JsonValue {
        let mut m = JsonMap::new();
        m.insert("stream", JsonValue::from_str_val(&self.stream));
        m.insert("text", JsonValue::from_str_val(&self.text));
        JsonValue::Object(m)
    }

    pub fn to_json_string(&self) -> String {
        self.to_json_value().to_json_string()
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct StreamExit {
    pub exit_code: i32,
    pub duration_ms: i64,
    pub timed_out: bool,
}

impl StreamExit {
    pub fn to_json_value(&self) -> JsonValue {
        let mut m = JsonMap::new();
        m.insert("exit_code", JsonValue::from_i32(self.exit_code));
        m.insert("duration_ms", JsonValue::from_i64(self.duration_ms));
        m.insert("timed_out", JsonValue::from_bool(self.timed_out));
        JsonValue::Object(m)
    }

    pub fn to_json_string(&self) -> String {
        self.to_json_value().to_json_string()
    }
}

pub fn clamp_stream_timeout(sec: i32) -> Duration {
    if sec <= 0 {
        Duration::from_secs(DEFAULT_STREAM_TIMEOUT_SEC as u64)
    } else if sec > MAX_STREAM_TIMEOUT_SEC {
        Duration::from_secs(MAX_STREAM_TIMEOUT_SEC as u64)
    } else {
        Duration::from_secs(sec as u64)
    }
}

pub fn handle_exec_stream(req: &HttpRequest) -> HttpResponse {
    if req.method != "POST" {
        return HttpResponse::json_error(405, "POST only");
    }
    let Ok(val) = JsonValue::parse(&req.body_str()) else {
        return HttpResponse::json_error(400, "invalid JSON");
    };
    let Ok(r) = ExecRequest::from_json(&val) else {
        return HttpResponse::json_error(400, "invalid JSON");
    };
    if r.command.trim().is_empty() {
        return HttpResponse::json_error(400, "command is empty");
    }
    if r.kind != "shell" && r.kind != "claude_prompt" {
        return HttpResponse::json_error(400, "unknown kind (want shell or claude_prompt)");
    }

    agent_log(&format!(
        "act stream: kind={} cwd={:?} cmd={:?}",
        r.kind,
        r.cwd,
        first_n_chars(&r.command, 80)
    ));

    let timeout = clamp_stream_timeout(r.timeout_seconds);
    HttpResponse::sse(move |sink: &mut dyn SseSink, cancel: CancelToken| {
        let start = Instant::now();
        let (tx, rx) = mpsc::channel::<StreamLine>();
        let r_clone = r.clone();
        let cancel_for_timeout = cancel.clone();

        // Spawn a timeout timer that cancels `cancel` when `timeout` elapses
        let timed_out_flag = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false));
        let timed_out_for_timer = std::sync::Arc::clone(&timed_out_flag);
        let done_flag = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false));
        let done_for_timer = std::sync::Arc::clone(&done_flag);
        thread::spawn(move || {
            if !cancel_for_timeout.wait_timeout(timeout)
                && !done_for_timer.load(std::sync::atomic::Ordering::SeqCst)
            {
                timed_out_for_timer.store(true, std::sync::atomic::Ordering::SeqCst);
                cancel_for_timeout.cancel();
            }
        });

        let cancel_for_runner = cancel.clone();
        let runner = thread::spawn(move || run_stream(&cancel_for_runner, &r_clone, tx));

        for line in rx {
            if sink.write_event("line", &line.to_json_string()).is_err() {
                cancel.cancel();
                break;
            }
        }

        let (code, _) = runner.join().unwrap_or((-1, false));
        done_flag.store(true, std::sync::atomic::Ordering::SeqCst);
        let timed_out = timed_out_flag.load(std::sync::atomic::Ordering::SeqCst);
        let exit = StreamExit {
            exit_code: if timed_out { -1 } else { code },
            duration_ms: start.elapsed().as_millis() as i64,
            timed_out,
        };
        let _ = sink.write_event("exit", &exit.to_json_string());
    })
}

/// Runs `r`, sending each line of stdout and stderr to `lines` as it arrives.
/// Drops `lines` when the child finishes and returns `(exit_code, killed_by_cancel)`.
pub fn run_stream(cancel: &CancelToken, r: &ExecRequest, lines: Sender<StreamLine>) -> (i32, bool) {
    let mut cmd = if r.kind == "claude_prompt" {
        let mut c = Command::new("claude");
        c.args(["-p", &r.command, "--output-format", "text"]);
        if !r.cwd.is_empty() {
            c.current_dir(&r.cwd);
        }
        c
    } else {
        let mut c = Command::new("/bin/zsh");
        c.args(["-lc", &r.command]);
        if !r.cwd.is_empty() {
            c.current_dir(&r.cwd);
        }
        c
    };

    cmd.env("PATH", augmented_path());
    cmd.process_group(0);
    cmd.stdout(Stdio::piped());
    cmd.stderr(Stdio::piped());

    let mut child = match cmd.spawn() {
        Ok(c) => c,
        Err(e) => {
            let _ = lines.send(StreamLine {
                stream: "stderr".to_string(),
                text: e.to_string(),
            });
            return (-1, false);
        }
    };

    let pid = child.id() as i32;
    let stdout_pipe = child.stdout.take();
    let stderr_pipe = child.stderr.take();

    let tx_out = lines.clone();
    let out_thread = thread::spawn(move || {
        if let Some(p) = stdout_pipe {
            let reader = BufReader::new(p);
            for line in reader.lines().map_while(Result::ok) {
                if tx_out
                    .send(StreamLine {
                        stream: "stdout".to_string(),
                        text: line,
                    })
                    .is_err()
                {
                    break;
                }
            }
        }
    });

    let tx_err = lines;
    let err_thread = thread::spawn(move || {
        if let Some(p) = stderr_pipe {
            let reader = BufReader::new(p);
            for line in reader.lines().map_while(Result::ok) {
                if tx_err
                    .send(StreamLine {
                        stream: "stderr".to_string(),
                        text: line,
                    })
                    .is_err()
                {
                    break;
                }
            }
        }
    });

    // Watcher thread that kills the process group if `cancel` triggers before child exits.
    let child_done = std::sync::Arc::new((std::sync::Mutex::new(false), std::sync::Condvar::new()));
    let child_done_watcher = std::sync::Arc::clone(&child_done);
    let cancel_watcher = cancel.clone();
    let killer_thread = thread::spawn(move || loop {
        if cancel_watcher.is_cancelled() {
            kill_group(pid);
            return true;
        }
        let (lock, cvar) = &*child_done_watcher;
        let guard = lock.lock().unwrap();
        if *guard {
            return false;
        }
        let (guard, _) = cvar.wait_timeout(guard, Duration::from_millis(15)).unwrap();
        if *guard {
            return false;
        }
    });

    let _ = out_thread.join();
    let _ = err_thread.join();
    let status = child.wait();
    {
        let (lock, cvar) = &*child_done;
        *lock.lock().unwrap() = true;
        cvar.notify_all();
    }
    let killed = killer_thread.join().unwrap_or(false);

    if killed || cancel.is_cancelled() {
        return (-1, true);
    }
    let code = match status {
        Ok(st) => st.code().unwrap_or(-1),
        Err(_) => -1,
    };
    (code, false)
}

/// Sends `SIGTERM` to the process group `-pid`, then `SIGKILL` 200ms later.
pub fn kill_group(pid: i32) {
    if pid <= 0 {
        return;
    }
    unsafe {
        let _ = kill(-pid, SIGTERM);
    }
    thread::sleep(Duration::from_millis(200));
    unsafe {
        let _ = kill(-pid, SIGKILL);
    }
}

/// Collapses whitespace/newlines and truncates on Unicode scalar (rune) boundaries.
pub fn first_n_chars(s: &str, n: usize) -> String {
    let collapsed = s.trim().replace('\n', " ");
    let chars: Vec<char> = collapsed.chars().collect();
    if chars.len() <= n {
        collapsed
    } else {
        let prefix: String = chars[..n].iter().collect();
        format!("{}...", prefix)
    }
}

static NEXT_EXEC_STREAM_ID: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(1);

pub fn next_exec_stream_id() -> u64 {
    NEXT_EXEC_STREAM_ID.fetch_add(1, std::sync::atomic::Ordering::SeqCst)
}

pub fn run_stream_argv(
    argv: &[String],
    dir: &std::path::Path,
    timeout: Duration,
    cancel: &CancelToken,
    lines_tx: mpsc::SyncSender<StreamLine>,
) -> (i32, Duration) {
    let start = Instant::now();
    if argv.is_empty() {
        return (-1, start.elapsed());
    }
    let mut cmd = Command::new(&argv[0]);
    cmd.args(&argv[1..]);
    if !dir.as_os_str().is_empty() && dir.exists() {
        cmd.current_dir(dir);
    }
    cmd.env("PATH", augmented_path());
    cmd.process_group(0);
    cmd.stdout(Stdio::piped());
    cmd.stderr(Stdio::piped());

    let mut child = match cmd.spawn() {
        Ok(c) => c,
        Err(e) => {
            let _ = lines_tx.send(StreamLine {
                stream: "stderr".to_string(),
                text: e.to_string(),
            });
            return (-1, start.elapsed());
        }
    };

    let pid = child.id() as i32;
    let stdout_pipe = child.stdout.take();
    let stderr_pipe = child.stderr.take();

    let tx_out = lines_tx.clone();
    let out_thread = thread::spawn(move || {
        if let Some(p) = stdout_pipe {
            let reader = BufReader::new(p);
            for line in reader.lines().map_while(Result::ok) {
                if tx_out
                    .send(StreamLine {
                        stream: "stdout".to_string(),
                        text: line,
                    })
                    .is_err()
                {
                    break;
                }
            }
        }
    });

    let tx_err = lines_tx;
    let err_thread = thread::spawn(move || {
        if let Some(p) = stderr_pipe {
            let reader = BufReader::new(p);
            for line in reader.lines().map_while(Result::ok) {
                if tx_err
                    .send(StreamLine {
                        stream: "stderr".to_string(),
                        text: line,
                    })
                    .is_err()
                {
                    break;
                }
            }
        }
    });

    let child_done = std::sync::Arc::new((std::sync::Mutex::new(false), std::sync::Condvar::new()));
    let child_done_watcher = std::sync::Arc::clone(&child_done);
    let cancel_watcher = cancel.clone();
    let killer_thread = thread::spawn(move || {
        let deadline = Instant::now() + timeout;
        loop {
            if cancel_watcher.is_cancelled() || Instant::now() >= deadline {
                kill_group(pid);
                return true;
            }
            let (lock, cvar) = &*child_done_watcher;
            let guard = lock.lock().unwrap();
            if *guard {
                return false;
            }
            let (guard, _) = cvar.wait_timeout(guard, Duration::from_millis(15)).unwrap();
            if *guard {
                return false;
            }
        }
    });

    let _ = out_thread.join();
    let _ = err_thread.join();
    let status = child.wait();
    {
        let (lock, cvar) = &*child_done;
        *lock.lock().unwrap() = true;
        cvar.notify_all();
    }
    let killed = killer_thread.join().unwrap_or(false);
    let code = if killed || cancel.is_cancelled() {
        -1
    } else {
        match status {
            Ok(st) => st.code().unwrap_or(-1),
            Err(_) => -1,
        }
    };
    (code, start.elapsed())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::http_util::http_open_stream;
    use crate::pair::Store;
    use crate::sampler::Sampler;
    use crate::server::new_mux;
    use std::path::Path;
    use std::sync::atomic::{AtomicU64, Ordering};

    fn require_shell() -> bool {
        Path::new("/bin/zsh").exists()
    }

    fn temp_dir() -> std::path::PathBuf {
        static COUNTER: AtomicU64 = AtomicU64::new(0);
        let id = COUNTER.fetch_add(1, Ordering::Relaxed);
        let d = std::env::temp_dir().join(format!(
            "macagent-stream-test-{}-{}",
            std::process::id(),
            id
        ));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        d
    }

    #[test]
    fn test_run_stream_interleaves_stdout_and_stderr() {
        if !require_shell() {
            return;
        }
        let (tx, rx) = mpsc::channel();
        let cancel = CancelToken::new();
        thread::spawn(move || {
            run_stream(
                &cancel,
                &ExecRequest {
                    kind: "shell".to_string(),
                    command: "echo one; sleep 0.25; echo problem >&2; sleep 0.25; echo two"
                        .to_string(),
                    ..Default::default()
                },
                tx,
            );
        });
        let got: Vec<StreamLine> = rx.into_iter().collect();
        assert_eq!(got.len(), 3, "want three lines, got {:?}", got);
        assert_eq!(
            got[0],
            StreamLine {
                stream: "stdout".to_string(),
                text: "one".to_string()
            }
        );
        assert_eq!(
            got[1],
            StreamLine {
                stream: "stderr".to_string(),
                text: "problem".to_string()
            }
        );
        assert_eq!(
            got[2],
            StreamLine {
                stream: "stdout".to_string(),
                text: "two".to_string()
            }
        );
    }

    #[test]
    fn test_run_stream_exit_code() {
        if !require_shell() {
            return;
        }
        let (tx, rx) = mpsc::channel();
        let cancel = CancelToken::new();
        let handle = thread::spawn(move || {
            let (code, _) = run_stream(
                &cancel,
                &ExecRequest {
                    kind: "shell".to_string(),
                    command: "exit 7".to_string(),
                    ..Default::default()
                },
                tx,
            );
            code
        });
        for _ in rx {}
        let code = handle.join().unwrap();
        assert_eq!(code, 7);
    }

    fn wait_for<F: Fn() -> bool>(limit: Duration, cond: F) -> bool {
        let deadline = Instant::now() + limit;
        while Instant::now() < deadline {
            if cond() {
                return true;
            }
            thread::sleep(Duration::from_millis(50));
        }
        cond()
    }

    fn pgrep_count(arg: &str) -> usize {
        let Ok(out) = Command::new("pgrep")
            .args(["-f", &format!("sleep {}", arg)])
            .output()
        else {
            return 0;
        };
        String::from_utf8_lossy(&out.stdout)
            .lines()
            .filter(|l| !l.trim().is_empty())
            .count()
    }

    #[test]
    fn test_run_stream_kills_the_process_group() {
        if !require_shell() {
            return;
        }
        if Command::new("pgrep").arg("-V").output().is_err()
            && !Path::new("/usr/bin/pgrep").exists()
        {
            return;
        }
        let marker = "31.5";
        let cancel = CancelToken::new();
        let cancel_runner = cancel.clone();
        let (tx, rx) = mpsc::channel();
        let done = thread::spawn(move || {
            run_stream(
                &cancel_runner,
                &ExecRequest {
                    kind: "shell".to_string(),
                    command: format!("sleep {}", marker),
                    ..Default::default()
                },
                tx,
            );
        });
        thread::spawn(move || for _ in rx {});

        if !wait_for(Duration::from_secs(3), || pgrep_count(marker) > 0) {
            cancel.cancel();
            let _ = done.join();
            return;
        }
        cancel.cancel();
        let _ = done.join();

        assert!(
            wait_for(Duration::from_secs(5), || pgrep_count(marker) == 0),
            "a `sleep {}` survived the cancellation: the process group was not killed",
            marker
        );
    }

    #[test]
    fn test_clamp_stream_timeout() {
        assert_eq!(
            clamp_stream_timeout(0),
            Duration::from_secs(DEFAULT_STREAM_TIMEOUT_SEC as u64)
        );
        assert_eq!(
            clamp_stream_timeout(-1),
            Duration::from_secs(DEFAULT_STREAM_TIMEOUT_SEC as u64)
        );
        assert_eq!(clamp_stream_timeout(120), Duration::from_secs(120));
        assert_eq!(
            clamp_stream_timeout(999999),
            Duration::from_secs(MAX_STREAM_TIMEOUT_SEC as u64)
        );
        assert!(MAX_STREAM_TIMEOUT_SEC > crate::exec::MAX_TIMEOUT_SEC);
    }

    #[test]
    fn test_exec_stream_serves_sse() {
        if !require_shell() {
            return;
        }
        let sampler = Sampler::new(Duration::from_secs(1), "", "", Vec::new(), None);
        let store = Store::new(temp_dir());
        store.ensure_token().unwrap();
        store.write_pairing("482917").unwrap();
        let tok = store.claim_pairing("482917").unwrap();
        let srv = crate::http_util::TestServer::start(new_mux(sampler, store, "", ""));

        let auth = format!("Bearer {}", tok);
        let (status, headers, reader, _ctrl) = http_open_stream(
            "POST",
            &format!("{}/v1/exec/stream", srv.url),
            &[("Authorization", &auth)],
            br#"{"kind":"shell","command":"echo alpha; echo beta"}"#,
        )
        .expect("open SSE stream");
        assert_eq!(status, 200);

        let ct = headers
            .iter()
            .find(|(k, _)| k.eq_ignore_ascii_case("content-type"))
            .map(|(_, v)| v.as_str())
            .unwrap_or("");
        let cc = headers
            .iter()
            .find(|(k, _)| k.eq_ignore_ascii_case("cache-control"))
            .map(|(_, v)| v.as_str())
            .unwrap_or("");
        assert_eq!(ct, "text/event-stream");
        assert_eq!(cc, "no-store");

        let mut events = Vec::new();
        let mut texts = Vec::new();
        let mut exit_code: Option<i32> = None;
        let mut cur_event = String::new();
        for line in reader.lines().map_while(Result::ok) {
            if let Some(ev) = line.strip_prefix("event: ") {
                cur_event = ev.to_string();
                events.push(cur_event.clone());
            } else if let Some(data) = line.strip_prefix("data: ") {
                match cur_event.as_str() {
                    "line" => {
                        let v = JsonValue::parse(data).expect("line JSON");
                        texts.push(v.get_str("text").to_string());
                    }
                    "exit" => {
                        let v = JsonValue::parse(data).expect("exit JSON");
                        exit_code = Some(v.get_i32("exit_code"));
                    }
                    _ => {}
                }
            }
        }
        assert_eq!(texts, vec!["alpha", "beta"]);
        assert_eq!(events.last().map(|s| s.as_str()), Some("exit"));
        assert_eq!(exit_code, Some(0));
    }

    #[test]
    fn test_exec_stream_rejects_a_bad_request_before_the_first_byte() {
        let sampler = Sampler::new(Duration::from_secs(1), "", "", Vec::new(), None);
        let store = Store::new(temp_dir());
        store.ensure_token().unwrap();
        store.write_pairing("482917").unwrap();
        let tok = store.claim_pairing("482917").unwrap();
        let srv = crate::http_util::TestServer::start(new_mux(sampler, store, "", ""));

        for body in [
            r#"{"kind":"rm","command":"-rf /"}"#,
            r#"{"kind":"shell","command":"   "}"#,
        ] {
            let resp = crate::http_util::http_post_json(
                &format!("{}/v1/exec/stream", srv.url),
                &tok,
                body,
            )
            .unwrap();
            assert_eq!(resp.status, 400, "body: {}", body);
            let got = resp.json().unwrap();
            assert!(!got.get_str("error").is_empty());
        }
    }

    #[test]
    fn test_first_n_chars_truncates_on_runes() {
        assert_eq!(first_n_chars("  echo\nhi  ", 80), "echo hi");
        let long = "é".repeat(100);
        let got = first_n_chars(&long, 80);
        assert!(got.ends_with("..."));
        assert_eq!(got.strip_suffix("...").unwrap().chars().count(), 80);
    }
}
