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

use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

#[derive(Debug, Clone)]
pub struct FlashArgs {
    pub port: Option<String>,
    pub monitor: bool,
    pub env: String,
    pub help: bool,
}

impl Default for FlashArgs {
    fn default() -> Self {
        Self {
            port: None,
            monitor: false,
            env: "esp32-s3-devkitc-1".into(),
            help: false,
        }
    }
}

pub fn parse_args(args: &[String]) -> Result<FlashArgs, String> {
    let mut result = FlashArgs::default();
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "-h" | "--help" => {
                result.help = true;
                return Ok(result);
            }
            "-p" | "--port" => {
                i += 1;
                if i >= args.len() {
                    return Err("--port requires an argument".into());
                }
                result.port = Some(args[i].clone());
            }
            "-m" | "--monitor" => {
                result.monitor = true;
            }
            "--env" => {
                i += 1;
                if i >= args.len() {
                    return Err("--env requires an argument".into());
                }
                result.env = args[i].clone();
            }
            other => {
                if result.port.is_none() && !other.starts_with('-') {
                    result.port = Some(other.to_string());
                } else {
                    return Err(format!("unexpected argument: {}", other));
                }
            }
        }
        i += 1;
    }
    Ok(result)
}

pub fn usage() -> &'static str {
    "Usage: flash [--port <port>] [--monitor] [--env <env>]\n\
     Flashes ESP32-S3 firmware to the specified port, or auto-detects if omitted.\n\
     \n\
     Options:\n\
       -p, --port <port>   Serial port (default: auto-detect /dev/cu.usbmodem* or /dev/ttyACM*)\n\
       -m, --monitor       Open serial monitor after flashing\n\
       --env <env>         PlatformIO environment (default: esp32-s3-devkitc-1)\n\
       -h, --help          Show this help"
}

pub fn find_pio() -> Option<PathBuf> {
    if let Ok(pio_bin) = env::var("PIO_BIN") {
        let p = PathBuf::from(&pio_bin);
        if p.exists() {
            return Some(p);
        }
    }

    if let Some(path) = which("pio") {
        return Some(path);
    }

    let home = env::var("HOME").unwrap_or_default();
    if !home.is_empty() {
        let candidate = PathBuf::from(&home)
            .join(".platformio")
            .join("penv")
            .join("bin")
            .join("pio");
        if candidate.exists() {
            return Some(candidate);
        }
    }

    None
}

fn which(name: &str) -> Option<PathBuf> {
    let path_var = env::var("PATH").unwrap_or_default();
    for dir in path_var.split(':') {
        let candidate = PathBuf::from(dir).join(name);
        if candidate.is_file() {
            return Some(candidate);
        }
    }
    None
}

pub fn detect_port() -> Option<String> {
    for pattern_dir in ["/dev"] {
        if let Ok(entries) = fs::read_dir(pattern_dir) {
            let mut ports: Vec<String> = entries
                .filter_map(|e| e.ok())
                .filter_map(|e| {
                    let name = e.file_name().to_string_lossy().to_string();
                    if name.starts_with("cu.usbmodem") || name.starts_with("ttyACM") {
                        Some(format!("/dev/{}", name))
                    } else {
                        None
                    }
                })
                .collect();
            ports.sort();
            if let Some(first) = ports.into_iter().next() {
                return Some(first);
            }
        }
    }
    None
}

pub fn resolve_project_dir() -> PathBuf {
    if let Ok(ws) = env::var("BUILD_WORKSPACE_DIRECTORY") {
        PathBuf::from(ws).join("apps/embedded/esp32-s3")
    } else {
        PathBuf::from(".")
    }
}

pub fn flash(args: &FlashArgs) -> Result<(), String> {
    let port = match &args.port {
        Some(p) => p.clone(),
        None => detect_port().ok_or(
            "No ESP32-S3 serial port detected. Specify explicitly:\n  flash --port /dev/cu.usbmodemXXXX"
                .to_string(),
        )?,
    };

    let pio = find_pio()
        .ok_or("PlatformIO not found. Install via: uv tool install platformio".to_string())?;

    let project_dir = resolve_project_dir();

    eprintln!("==================================================");
    eprintln!("Uploading Firmware to ESP32-S3 on {}", port);
    eprintln!("==================================================");

    let status = Command::new(&pio)
        .arg("run")
        .arg("-e")
        .arg(&args.env)
        .arg("-t")
        .arg("upload")
        .arg("--upload-port")
        .arg(&port)
        .arg("-d")
        .arg(&project_dir)
        .status()
        .map_err(|e| format!("failed to run pio: {}", e))?;

    if !status.success() {
        return Err("PlatformIO upload failed".into());
    }

    if args.monitor {
        eprintln!("Opening serial monitor on {}...", port);
        let status = Command::new(&pio)
            .arg("device")
            .arg("monitor")
            .arg("-p")
            .arg(&port)
            .status()
            .map_err(|e| format!("failed to run pio monitor: {}", e))?;
        if !status.success() {
            return Err("PlatformIO monitor failed".into());
        }
    }

    Ok(())
}

pub fn build_flash_command(pio: &Path, args: &FlashArgs, project_dir: &Path) -> Vec<String> {
    let mut cmd = vec![
        pio.to_string_lossy().to_string(),
        "run".into(),
        "-e".into(),
        args.env.clone(),
        "-t".into(),
        "upload".into(),
    ];
    if let Some(ref port) = args.port {
        cmd.push("--upload-port".into());
        cmd.push(port.clone());
    }
    cmd.push("-d".into());
    cmd.push(project_dir.to_string_lossy().to_string());
    cmd
}

pub fn build_monitor_command(pio: &Path, port: &str) -> Vec<String> {
    vec![
        pio.to_string_lossy().to_string(),
        "device".into(),
        "monitor".into(),
        "-p".into(),
        port.into(),
    ]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_default() {
        let args: Vec<String> = vec![];
        let result = parse_args(&args).unwrap();
        assert!(result.port.is_none());
        assert!(!result.monitor);
        assert_eq!(result.env, "esp32-s3-devkitc-1");
        assert!(!result.help);
    }

    #[test]
    fn test_parse_port_long() {
        let args = vec!["--port".to_string(), "/dev/cu.usbmodem1234".to_string()];
        let result = parse_args(&args).unwrap();
        assert_eq!(result.port, Some("/dev/cu.usbmodem1234".to_string()));
    }

    #[test]
    fn test_parse_port_short() {
        let args = vec!["-p".to_string(), "/dev/ttyACM0".to_string()];
        let result = parse_args(&args).unwrap();
        assert_eq!(result.port, Some("/dev/ttyACM0".to_string()));
    }

    #[test]
    fn test_parse_monitor() {
        let args = vec!["-m".to_string()];
        let result = parse_args(&args).unwrap();
        assert!(result.monitor);
    }

    #[test]
    fn test_parse_env() {
        let args = vec!["--env".to_string(), "esp32-devkit".to_string()];
        let result = parse_args(&args).unwrap();
        assert_eq!(result.env, "esp32-devkit");
    }

    #[test]
    fn test_parse_help() {
        let args = vec!["-h".to_string()];
        let result = parse_args(&args).unwrap();
        assert!(result.help);
    }

    #[test]
    fn test_parse_all_flags() {
        let args = vec![
            "--port".to_string(),
            "/dev/cu.usbmodem42".to_string(),
            "--monitor".to_string(),
            "--env".to_string(),
            "myenv".to_string(),
        ];
        let result = parse_args(&args).unwrap();
        assert_eq!(result.port, Some("/dev/cu.usbmodem42".to_string()));
        assert!(result.monitor);
        assert_eq!(result.env, "myenv");
    }

    #[test]
    fn test_parse_positional_port() {
        let args = vec!["/dev/cu.usbmodem99".to_string()];
        let result = parse_args(&args).unwrap();
        assert_eq!(result.port, Some("/dev/cu.usbmodem99".to_string()));
    }

    #[test]
    fn test_build_flash_command_with_port() {
        let pio = PathBuf::from("/usr/local/bin/pio");
        let args = FlashArgs {
            port: Some("/dev/cu.usbmodem1".into()),
            monitor: false,
            env: "esp32-s3-devkitc-1".into(),
            help: false,
        };
        let cmd = build_flash_command(&pio, &args, Path::new("/project"));
        assert!(cmd.contains(&"upload".to_string()));
        assert!(cmd.contains(&"--upload-port".to_string()));
        assert!(cmd.contains(&"/dev/cu.usbmodem1".to_string()));
    }

    #[test]
    fn test_build_monitor_command() {
        let pio = PathBuf::from("/usr/local/bin/pio");
        let cmd = build_monitor_command(&pio, "/dev/cu.usbmodem1");
        assert_eq!(cmd[1], "device");
        assert_eq!(cmd[2], "monitor");
        assert_eq!(cmd[4], "/dev/cu.usbmodem1");
    }

    #[test]
    fn test_missing_port_arg() {
        let args = vec!["--port".to_string()];
        assert!(parse_args(&args).is_err());
    }

    #[test]
    fn test_missing_env_arg() {
        let args = vec!["--env".to_string()];
        assert!(parse_args(&args).is_err());
    }
}
