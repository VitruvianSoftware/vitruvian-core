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

use std::fs;
use std::io::Write;
use std::net::UdpSocket;
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

pub fn get_cpu_usage() -> u32 {
    if let Ok(output) = Command::new("sh")
        .args(["-c", "top -l 1 -n 0 | grep 'CPU usage'"])
        .output()
    {
        if output.status.success() {
            return parse_top_cpu(&String::from_utf8_lossy(&output.stdout));
        }
    }
    0
}

pub fn parse_top_cpu(output: &str) -> u32 {
    for line in output.lines() {
        if !line.contains("CPU usage") {
            continue;
        }
        let parts: Vec<&str> = line.split(',').collect();
        if parts.is_empty() {
            continue;
        }
        let mut user = 0.0f64;
        let mut sys = 0.0f64;

        if let Some(colon) = parts[0].find(':') {
            let val = parts[0][colon + 1..]
                .trim()
                .replace("% user", "")
                .trim()
                .parse::<f64>()
                .unwrap_or(0.0);
            user = val;
        }
        if parts.len() > 1 {
            let val = parts[1]
                .trim()
                .replace("% sys", "")
                .trim()
                .parse::<f64>()
                .unwrap_or(0.0);
            sys = val;
        }
        return (user + sys).round() as u32;
    }
    0
}

pub fn get_ram_usage() -> u32 {
    if let Ok(output) = Command::new("vm_stat").output() {
        if output.status.success() {
            return parse_vm_stat(&String::from_utf8_lossy(&output.stdout));
        }
    }
    0
}

pub fn parse_vm_stat(output: &str) -> u32 {
    let mut free_pages: u64 = 0;
    let mut active_pages: u64 = 0;
    let mut inactive_pages: u64 = 0;
    let mut speculative_pages: u64 = 0;
    let mut wired_pages: u64 = 0;
    let mut compressed_pages: u64 = 0;

    for line in output.lines() {
        if line.contains("Pages free:") {
            free_pages = extract_page_count(line);
        } else if line.contains("Pages active:") {
            active_pages = extract_page_count(line);
        } else if line.contains("Pages inactive:") {
            inactive_pages = extract_page_count(line);
        } else if line.contains("Pages speculative:") {
            speculative_pages = extract_page_count(line);
        } else if line.contains("Pages wired down:") {
            wired_pages = extract_page_count(line);
        } else if line.contains("Pages occupied by compressor:") {
            compressed_pages = extract_page_count(line);
        }
    }

    let used = active_pages + wired_pages + compressed_pages;
    let total = used + inactive_pages + free_pages + speculative_pages;
    if total > 0 {
        ((used as f64 / total as f64) * 100.0).round() as u32
    } else {
        0
    }
}

fn extract_page_count(line: &str) -> u64 {
    line.split_whitespace()
        .last()
        .unwrap_or("0")
        .trim_end_matches('.')
        .parse()
        .unwrap_or(0)
}

pub fn get_battery_status() -> (i32, bool) {
    if let Ok(output) = Command::new("pmset").args(["-g", "batt"]).output() {
        if output.status.success() {
            return parse_pmset(&String::from_utf8_lossy(&output.stdout));
        }
    }
    (-1, false)
}

pub fn parse_pmset(output: &str) -> (i32, bool) {
    let charging = output.contains("charging")
        && !output.contains("not charging")
        && !output.contains("discharging");

    for line in output.lines() {
        if let Some(pos) = line.find('%') {
            let before = &line[..pos];
            let num_str: String = before
                .chars()
                .rev()
                .take_while(|c| c.is_ascii_digit())
                .collect::<String>()
                .chars()
                .rev()
                .collect();
            if let Ok(pct) = num_str.parse::<i32>() {
                return (pct, charging);
            }
        }
    }
    (-1, charging)
}

pub fn get_network_ip() -> String {
    if let Ok(output) = Command::new("sh")
        .args([
            "-c",
            "ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null",
        ])
        .output()
    {
        if output.status.success() {
            let ip = String::from_utf8_lossy(&output.stdout).trim().to_string();
            if !ip.is_empty() {
                return ip;
            }
        }
    }
    "0.0.0.0".into()
}

pub fn get_media_status() -> (String, bool) {
    let script = r#"tell application "System Events"
  set musicApps to {"Spotify", "Music"}
  repeat with appName in musicApps
    if (name of processes) contains appName then
      try
        if appName is "Spotify" then
          tell application "Spotify"
            if player state is playing then
              return "playing," & name of current track & " - " & artist of current track
            else
              return "paused," & name of current track & " - " & artist of current track
            end if
          end tell
        else
          tell application "Music"
            if player state is playing then
              return "playing," & name of current track & " - " & artist of current track
            end if
          end tell
        end if
      end try
    end if
  end repeat
  return "stopped,"
end tell"#;

    if let Ok(output) = Command::new("osascript").args(["-e", script]).output() {
        if output.status.success() {
            let text = String::from_utf8_lossy(&output.stdout).trim().to_string();
            if text.starts_with("playing,") {
                return (text[8..].to_string(), true);
            } else if text.starts_with("paused,") {
                return (text[7..].to_string(), false);
            }
        }
    }
    (String::new(), false)
}

pub fn collect_all_stats(include_ci: bool, repo: &str) -> String {
    let cpu = get_cpu_usage();
    let ram = get_ram_usage();
    let (batt_pct, charging) = get_battery_status();
    let ip = get_network_ip();

    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default();
    let secs = now.as_secs();
    let hours = ((secs % 86400) / 3600) as u32;
    let minutes = ((secs % 3600) / 60) as u32;
    let ampm = if hours < 12 { "AM" } else { "PM" };
    let h12 = if hours == 0 {
        12
    } else if hours > 12 {
        hours - 12
    } else {
        hours
    };
    let time_str = format!("{:02}:{:02} {}", h12, minutes, ampm);

    let mut payload = format!(
        r#"{{"type":"stats","cpu":{},"ram":{},"battery":{},"charging":{},"ip":"{}","time":"{}""#,
        cpu,
        ram,
        batt_pct,
        charging,
        json_escape(&ip),
        time_str,
    );

    if include_ci && !repo.is_empty() {
        payload.push_str(r#","ci":true"#);
    }

    payload.push('}');
    payload
}

pub fn find_esp32_serial_port() -> Option<String> {
    if let Ok(entries) = fs::read_dir("/dev") {
        let mut ports: Vec<String> = entries
            .filter_map(|e| e.ok())
            .filter_map(|e| {
                let name = e.file_name().to_string_lossy().to_string();
                if name.starts_with("cu.usbmodem") {
                    Some(format!("/dev/{}", name))
                } else {
                    None
                }
            })
            .collect();
        ports.sort();
        return ports.into_iter().next();
    }
    None
}

pub fn send_over_serial(port: &str, baud: u32, data: &str) -> Result<(), String> {
    let stty_args = format!("speed {} cs8 -cstopb -parenb", baud);
    let _ = Command::new("stty")
        .args(["-f", port])
        .args(stty_args.split_whitespace())
        .output();

    let mut file = fs::OpenOptions::new()
        .write(true)
        .open(port)
        .map_err(|e| format!("open {}: {}", port, e))?;

    file.write_all(data.as_bytes())
        .map_err(|e| format!("write to {}: {}", port, e))?;
    file.flush().map_err(|e| format!("flush {}: {}", port, e))?;

    Ok(())
}

pub fn send_over_http(host: &str, port: u16, data: &str) -> Result<(), String> {
    let sock = UdpSocket::bind("0.0.0.0:0").map_err(|e| format!("bind: {}", e))?;
    sock.send_to(data.as_bytes(), (host, port))
        .map_err(|e| format!("send to {}:{}: {}", host, port, e))?;
    Ok(())
}

fn json_escape(s: &str) -> String {
    s.replace('\\', "\\\\")
        .replace('"', "\\\"")
        .replace('\n', "\\n")
        .replace('\r', "\\r")
}

#[derive(Debug)]
pub struct DaemonArgs {
    pub mode: String,
    pub port: Option<String>,
    pub baud: u32,
    pub host: String,
    pub udp_port: u16,
    pub interval: f64,
    pub repo: String,
    pub once: bool,
    pub help: bool,
}

impl Default for DaemonArgs {
    fn default() -> Self {
        Self {
            mode: "serial".into(),
            port: None,
            baud: 115200,
            host: "vitruvian-companion.local".into(),
            udp_port: 8266,
            interval: 1.0,
            repo: ".".into(),
            once: false,
            help: false,
        }
    }
}

pub fn parse_daemon_args(args: &[String]) -> Result<DaemonArgs, String> {
    let mut result = DaemonArgs::default();
    let mut i = 0;

    while i < args.len() {
        match args[i].as_str() {
            "--mode" => {
                i += 1;
                if i >= args.len() {
                    return Err("--mode requires an argument".into());
                }
                result.mode = args[i].clone();
            }
            "--port" | "-p" => {
                i += 1;
                if i >= args.len() {
                    return Err("--port requires an argument".into());
                }
                result.port = Some(args[i].clone());
            }
            "--baud" => {
                i += 1;
                if i >= args.len() {
                    return Err("--baud requires an argument".into());
                }
                result.baud = args[i]
                    .parse()
                    .map_err(|_| format!("invalid baud rate: {}", args[i]))?;
            }
            "--host" => {
                i += 1;
                if i >= args.len() {
                    return Err("--host requires an argument".into());
                }
                result.host = args[i].clone();
            }
            "--udp-port" => {
                i += 1;
                if i >= args.len() {
                    return Err("--udp-port requires an argument".into());
                }
                result.udp_port = args[i]
                    .parse()
                    .map_err(|_| format!("invalid port: {}", args[i]))?;
            }
            "--interval" => {
                i += 1;
                if i >= args.len() {
                    return Err("--interval requires an argument".into());
                }
                result.interval = args[i]
                    .parse()
                    .map_err(|_| format!("invalid interval: {}", args[i]))?;
            }
            "--repo" => {
                i += 1;
                if i >= args.len() {
                    return Err("--repo requires an argument".into());
                }
                result.repo = args[i].clone();
            }
            "--once" => result.once = true,
            "-h" | "--help" => {
                result.help = true;
                return Ok(result);
            }
            other => return Err(format!("unexpected argument: {}", other)),
        }
        i += 1;
    }

    Ok(result)
}

pub fn usage() -> &'static str {
    "Usage: mac_stats_daemon [OPTIONS]\n\
     \n\
     Options:\n\
       --mode <serial|http>  Transport mode (default: serial)\n\
       --port <port>         Serial port (default: auto-detect)\n\
       --baud <rate>         Baud rate (default: 115200)\n\
       --host <host>         HTTP/UDP target host (default: vitruvian-companion.local)\n\
       --udp-port <port>     UDP target port (default: 8266)\n\
       --interval <sec>      Telemetry interval in seconds (default: 1.0)\n\
       --repo <dir>          Repository directory for CI status (default: .)\n\
       --once                Send one payload and exit\n\
       -h, --help            Show this help"
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_top_cpu_typical() {
        let output = "CPU usage: 12.34% user, 5.67% sys, 81.99% idle\n";
        let cpu = parse_top_cpu(output);
        assert_eq!(cpu, 18); // 12.34 + 5.67 = 18.01 -> 18
    }

    #[test]
    fn test_parse_top_cpu_high() {
        let output = "CPU usage: 85.0% user, 10.0% sys, 5.0% idle\n";
        assert_eq!(parse_top_cpu(output), 95);
    }

    #[test]
    fn test_parse_top_cpu_zero() {
        let output = "CPU usage: 0.0% user, 0.0% sys, 100.0% idle\n";
        assert_eq!(parse_top_cpu(output), 0);
    }

    #[test]
    fn test_parse_top_cpu_empty() {
        assert_eq!(parse_top_cpu(""), 0);
    }

    #[test]
    fn test_parse_top_cpu_garbage() {
        assert_eq!(parse_top_cpu("no cpu info here"), 0);
    }

    #[test]
    fn test_parse_vm_stat_typical() {
        let output = "\
Mach Virtual Memory Statistics: (page size of 16384 bytes)
Pages free:                               12000.
Pages active:                             40000.
Pages inactive:                           10000.
Pages speculative:                         2000.
Pages throttled:                              0.
Pages wired down:                         15000.
Pages purgeable:                           1000.
Pages occupied by compressor:              8000.
";
        let ram = parse_vm_stat(output);
        // used = 40000 + 15000 + 8000 = 63000
        // total = 63000 + 10000 + 12000 + 2000 = 87000
        // pct = 63000/87000 * 100 = 72.4 -> 72
        assert_eq!(ram, 72);
    }

    #[test]
    fn test_parse_vm_stat_empty() {
        assert_eq!(parse_vm_stat(""), 0);
    }

    #[test]
    fn test_parse_pmset_charging() {
        let output = "\
Now drawing from 'AC Power'
 -InternalBattery-0 (id=1234)	85%; charging; 1:30 remaining present: true
";
        let (pct, charging) = parse_pmset(output);
        assert_eq!(pct, 85);
        assert!(charging);
    }

    #[test]
    fn test_parse_pmset_discharging() {
        let output = "\
Now drawing from 'Battery Power'
 -InternalBattery-0 (id=1234)	42%; discharging; 3:15 remaining present: true
";
        let (pct, charging) = parse_pmset(output);
        assert_eq!(pct, 42);
        assert!(!charging);
    }

    #[test]
    fn test_parse_pmset_not_charging() {
        let output = "\
Now drawing from 'AC Power'
 -InternalBattery-0 (id=1234)	100%; not charging present: true
";
        let (pct, charging) = parse_pmset(output);
        assert_eq!(pct, 100);
        assert!(!charging);
    }

    #[test]
    fn test_parse_pmset_empty() {
        let (pct, charging) = parse_pmset("");
        assert_eq!(pct, -1);
        assert!(!charging);
    }

    #[test]
    fn test_collect_all_stats_structure() {
        let stats = collect_all_stats(false, ".");
        assert!(stats.starts_with(r#"{"type":"stats""#));
        assert!(stats.contains(r#""cpu":"#));
        assert!(stats.contains(r#""ram":"#));
        assert!(stats.contains(r#""time":"#));
        assert!(stats.ends_with('}'));
    }

    #[test]
    fn test_collect_all_stats_with_ci() {
        let stats = collect_all_stats(true, "/my/repo");
        assert!(stats.contains(r#""ci":true"#));
    }

    #[test]
    fn test_daemon_args_default() {
        let args: Vec<String> = vec![];
        let parsed = parse_daemon_args(&args).unwrap();
        assert_eq!(parsed.mode, "serial");
        assert!(parsed.port.is_none());
        assert_eq!(parsed.baud, 115200);
        assert!(!parsed.once);
    }

    #[test]
    fn test_daemon_args_once() {
        let args = vec!["--once".to_string()];
        let parsed = parse_daemon_args(&args).unwrap();
        assert!(parsed.once);
    }

    #[test]
    fn test_daemon_args_full() {
        let args = vec![
            "--mode".to_string(),
            "http".to_string(),
            "--host".to_string(),
            "192.168.1.50".to_string(),
            "--udp-port".to_string(),
            "9000".to_string(),
            "--interval".to_string(),
            "2.5".to_string(),
            "--repo".to_string(),
            "/my/repo".to_string(),
            "--once".to_string(),
        ];
        let parsed = parse_daemon_args(&args).unwrap();
        assert_eq!(parsed.mode, "http");
        assert_eq!(parsed.host, "192.168.1.50");
        assert_eq!(parsed.udp_port, 9000);
        assert_eq!(parsed.interval, 2.5);
        assert_eq!(parsed.repo, "/my/repo");
        assert!(parsed.once);
    }

    #[test]
    fn test_daemon_args_serial_port() {
        let args = vec![
            "--port".to_string(),
            "/dev/cu.usbmodem123".to_string(),
            "--baud".to_string(),
            "9600".to_string(),
        ];
        let parsed = parse_daemon_args(&args).unwrap();
        assert_eq!(parsed.port, Some("/dev/cu.usbmodem123".to_string()));
        assert_eq!(parsed.baud, 9600);
    }

    #[test]
    fn test_daemon_args_help() {
        let args = vec!["-h".to_string()];
        let parsed = parse_daemon_args(&args).unwrap();
        assert!(parsed.help);
    }

    #[test]
    fn test_json_escape_special() {
        assert_eq!(json_escape("a\"b"), r#"a\"b"#);
        assert_eq!(json_escape("a\\b"), r#"a\\b"#);
        assert_eq!(json_escape("a\nb"), r#"a\nb"#);
    }

    #[test]
    fn test_send_over_http_bad_host() {
        let result = send_over_http("999.999.999.999", 8266, "test");
        assert!(result.is_err());
    }

    #[test]
    fn test_extract_page_count() {
        assert_eq!(
            extract_page_count("Pages free:                               12000."),
            12000
        );
        assert_eq!(extract_page_count("Pages active:     0."), 0);
        assert_eq!(extract_page_count("garbage"), 0);
    }
}
