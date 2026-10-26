// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: MIT
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

//! Native Rust port of `apps/desktop/nexus-agent/bot.sh`.
//! Process manager for the Antigravity (agy) Telegram Bot (`start|stop|restart|status|logs`).

use std::env;
use std::fs::{self, OpenOptions};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::thread;
use std::time::Duration;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BotAction {
    Start,
    Stop,
    Restart,
    Status,
    Logs,
    Usage,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BotOptions {
    pub action: BotAction,
    pub script_dir: PathBuf,
    pub dry_run: bool,
}

pub fn usage_text() -> &'static str {
    "Usage: ./bot.sh {start|stop|restart|status|logs}

  start    Start the bot in the background
  stop     Stop the bot gracefully
  restart  Stop and start the bot
  status   Check if the bot is running
  logs     Tail the bot log file
"
}

pub fn parse_args(args: &[String]) -> BotOptions {
    let mut script_dir = env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
    let mut dry_run = false;
    let mut action = BotAction::Usage;

    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--dir" => {
                i += 1;
                if i < args.len() {
                    script_dir = PathBuf::from(&args[i]);
                }
            }
            "--dry-run" => dry_run = true,
            "start" => action = BotAction::Start,
            "stop" => action = BotAction::Stop,
            "restart" => action = BotAction::Restart,
            "status" => action = BotAction::Status,
            "logs" => action = BotAction::Logs,
            _ => {}
        }
        i += 1;
    }

    BotOptions {
        action,
        script_dir,
        dry_run,
    }
}

pub fn pid_file_path(script_dir: &Path) -> PathBuf {
    script_dir.join(".bot.pid")
}

pub fn log_file_path(script_dir: &Path) -> PathBuf {
    script_dir.join("bot.log")
}

pub fn read_pid(pid_file: &Path) -> Option<u32> {
    let content = fs::read_to_string(pid_file).ok()?;
    content.trim().parse::<u32>().ok()
}

pub fn is_pid_alive(pid: u32) -> bool {
    Command::new("kill")
        .args(["-0", &pid.to_string()])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

pub fn is_running(script_dir: &Path) -> Option<u32> {
    let pid = read_pid(&pid_file_path(script_dir))?;
    if is_pid_alive(pid) {
        Some(pid)
    } else {
        None
    }
}

pub fn last_n_lines(content: &str, n: usize) -> Vec<String> {
    let all: Vec<&str> = content.lines().collect();
    let start = all.len().saturating_sub(n);
    all[start..].iter().map(|s| (*s).to_string()).collect()
}

pub fn run_bot(opts: &BotOptions) -> Result<String, String> {
    let pid_file = pid_file_path(&opts.script_dir);
    let log_file = log_file_path(&opts.script_dir);

    match opts.action {
        BotAction::Usage => Ok(usage_text().to_string()),
        BotAction::Start => {
            if let Some(pid) = is_running(&opts.script_dir) {
                return Err(format!("⚠️  Bot is already running (PID {})\n", pid));
            }
            let mut out = String::from("🚀 Starting Antigravity Telegram Bot...\n");
            if opts.dry_run {
                out.push_str("✅ Bot started (PID 99999)\n");
                out.push_str(&format!("📋 Logs: tail -f {}\n", log_file.display()));
                return Ok(out);
            }

            let log_handle = OpenOptions::new()
                .create(true)
                .append(true)
                .open(&log_file)
                .map_err(|e| format!("Failed to open log file {}: {}", log_file.display(), e))?;
            let log_err = log_handle
                .try_clone()
                .map_err(|e| format!("Failed to clone log file handle: {}", e))?;

            let child = Command::new("node")
                .arg("src/bot.js")
                .current_dir(&opts.script_dir)
                .stdout(Stdio::from(log_handle))
                .stderr(Stdio::from(log_err))
                .spawn()
                .map_err(|e| format!("❌ Bot failed to start: {}\n", e))?;

            let pid = child.id();
            fs::write(&pid_file, format!("{}\n", pid))
                .map_err(|e| format!("Failed to write PID file: {}", e))?;

            thread::sleep(Duration::from_millis(100));
            if is_pid_alive(pid) {
                out.push_str(&format!("✅ Bot started (PID {})\n", pid));
                out.push_str(&format!("📋 Logs: tail -f {}\n", log_file.display()));
                Ok(out)
            } else {
                let _ = fs::remove_file(&pid_file);
                Err(format!(
                    "{}❌ Bot failed to start. Check logs: cat {}\n",
                    out,
                    log_file.display()
                ))
            }
        }
        BotAction::Stop => {
            let Some(pid) = is_running(&opts.script_dir) else {
                if !opts.dry_run {
                    let _ = Command::new("pkill")
                        .args(["-f", "node src/bot.js"])
                        .stdout(Stdio::null())
                        .stderr(Stdio::null())
                        .status();
                    let _ = fs::remove_file(&pid_file);
                }
                return Ok("⚠️  Bot is not running\n".to_string());
            };

            let mut out = format!("🛑 Stopping bot (PID {})...\n", pid);
            if !opts.dry_run {
                let _ = Command::new("kill")
                    .arg(pid.to_string())
                    .stdout(Stdio::null())
                    .stderr(Stdio::null())
                    .status();

                let mut count = 0;
                while is_pid_alive(pid) && count < 10 {
                    thread::sleep(Duration::from_millis(500));
                    count += 1;
                }
                if is_pid_alive(pid) {
                    out.push_str("⚠️  Force killing...\n");
                    let _ = Command::new("kill")
                        .args(["-9", &pid.to_string()])
                        .stdout(Stdio::null())
                        .stderr(Stdio::null())
                        .status();
                }
                let _ = Command::new("pkill")
                    .args(["-f", "node src/bot.js"])
                    .stdout(Stdio::null())
                    .stderr(Stdio::null())
                    .status();
                let _ = fs::remove_file(&pid_file);
            }
            out.push_str("✅ Bot stopped\n");
            Ok(out)
        }
        BotAction::Restart => {
            let mut out = String::from("🔄 Restarting bot...\n");
            let stop_opts = BotOptions {
                action: BotAction::Stop,
                script_dir: opts.script_dir.clone(),
                dry_run: opts.dry_run,
            };
            out.push_str(&run_bot(&stop_opts)?);
            if !opts.dry_run {
                thread::sleep(Duration::from_millis(200));
            }
            let start_opts = BotOptions {
                action: BotAction::Start,
                script_dir: opts.script_dir.clone(),
                dry_run: opts.dry_run,
            };
            out.push_str(&run_bot(&start_opts)?);
            Ok(out)
        }
        BotAction::Status => {
            if let Some(pid) = is_running(&opts.script_dir) {
                let mut out = format!("✅ Bot is running (PID {})\n📋 Last 5 log lines:\n", pid);
                if let Ok(content) = fs::read_to_string(&log_file) {
                    for line in last_n_lines(&content, 5) {
                        out.push_str(&line);
                        out.push('\n');
                    }
                }
                Ok(out)
            } else {
                let mut out = String::from("❌ Bot is not running\n");
                if !opts.dry_run {
                    if let Ok(pgrep) = Command::new("pgrep")
                        .args(["-f", "node src/bot.js"])
                        .output()
                    {
                        let orphans = String::from_utf8_lossy(&pgrep.stdout).trim().to_string();
                        if !orphans.is_empty() {
                            out.push_str(&format!(
                                "⚠️  Found orphan processes: {}\n   Run './bot.sh stop' to clean them up\n",
                                orphans
                            ));
                        }
                    }
                }
                Ok(out)
            }
        }
        BotAction::Logs => {
            if !log_file.is_file() {
                return Err("No log file found.\n".to_string());
            }
            let mut out = String::from("📋 Following bot logs (Ctrl+C to exit)...\n");
            if opts.dry_run {
                if let Ok(content) = fs::read_to_string(&log_file) {
                    for line in last_n_lines(&content, 5) {
                        out.push_str(&line);
                        out.push('\n');
                    }
                }
                return Ok(out);
            }
            let status = Command::new("tail").arg("-f").arg(&log_file).status();
            if let Err(e) = status {
                return Err(format!("Failed to tail logs: {}\n", e));
            }
            Ok(out)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn make_temp_dir(prefix: &str) -> PathBuf {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let dir = env::temp_dir().join(format!("{}-{}-{}", prefix, std::process::id(), nanos));
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn test_parse_args_and_usage() {
        let opts = parse_args(&[]);
        assert_eq!(opts.action, BotAction::Usage);
        let out = run_bot(&opts).unwrap();
        assert!(out.contains("Usage: ./bot.sh {start|stop|restart|status|logs}"));

        let start_opts = parse_args(&["start".to_string(), "--dry-run".to_string()]);
        assert_eq!(start_opts.action, BotAction::Start);
        assert!(start_opts.dry_run);
    }

    #[test]
    fn test_last_n_lines() {
        let log = "line1\nline2\nline3\nline4\nline5\nline6\nline7\n";
        let tail = last_n_lines(log, 5);
        assert_eq!(tail, vec!["line3", "line4", "line5", "line6", "line7"]);
    }

    #[test]
    fn test_status_stop_start_and_logs_lifecycle() {
        let tmp = make_temp_dir("nexus-bot-test");

        // 1. Status when not running
        let status_out = run_bot(&BotOptions {
            action: BotAction::Status,
            script_dir: tmp.clone(),
            dry_run: true,
        })
        .unwrap();
        assert!(status_out.contains("❌ Bot is not running"));

        // 2. Stop when not running
        let stop_out = run_bot(&BotOptions {
            action: BotAction::Stop,
            script_dir: tmp.clone(),
            dry_run: true,
        })
        .unwrap();
        assert!(stop_out.contains("⚠️  Bot is not running"));

        // 3. Start in dry-run mode
        let start_out = run_bot(&BotOptions {
            action: BotAction::Start,
            script_dir: tmp.clone(),
            dry_run: true,
        })
        .unwrap();
        assert!(start_out.contains("🚀 Starting Antigravity Telegram Bot..."));
        assert!(start_out.contains("✅ Bot started"));

        // 4. Simulate running PID (current test process PID is guaranteed alive)
        let self_pid = std::process::id();
        fs::write(pid_file_path(&tmp), format!("{}\n", self_pid)).unwrap();
        fs::write(log_file_path(&tmp), "a\nb\nc\nd\ne\nf\n").unwrap();

        let running_status = run_bot(&BotOptions {
            action: BotAction::Status,
            script_dir: tmp.clone(),
            dry_run: true,
        })
        .unwrap();
        assert!(running_status.contains(&format!("✅ Bot is running (PID {})", self_pid)));
        assert!(running_status.contains("b\nc\nd\ne\nf\n"));

        // 5. Starting while already running returns error
        let dup_start = run_bot(&BotOptions {
            action: BotAction::Start,
            script_dir: tmp.clone(),
            dry_run: true,
        });
        assert!(dup_start.is_err());
        assert!(dup_start.unwrap_err().contains("Bot is already running"));

        // 6. Logs check
        let logs_out = run_bot(&BotOptions {
            action: BotAction::Logs,
            script_dir: tmp.clone(),
            dry_run: true,
        })
        .unwrap();
        assert!(logs_out.contains("📋 Following bot logs"));

        let _ = fs::remove_dir_all(&tmp);
    }
}
