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

//! Command-line argument parser and execution for `vitruvian-wand`:
//! - `vitruvian-wand` -> launch the `eframe` GUI + system tray
//! - `vitruvian-wand record <file>` -> connect to a Daydream controller and write `<t_us> <40 hex chars>` until Ctrl-C
//! - `vitruvian-wand replay <file> [--inject]` -> replay a `.replay` session through `vitruvian_wand_core::Engine`, printing
//!   every emitted `Action` and only injecting OS events when `--inject` is passed
//! - `vitruvian-wand doctor` -> report Bluetooth adapter presence, macOS Accessibility / Linux `/dev/uinput` status,
//!   config path, and version

use crate::ble::{matches_daydream_peripheral, probe_bluetooth_adapter};
use crate::config::{default_config_path, load_config_from};
use crate::injector::{FakeInjector, Injector};
use crate::input::{create_platform_injector, drive_replay_with_injector};
use btleplug::api::{Central, Manager as _, Peripheral as _, ScanFilter};
use btleplug::platform::Manager;
use futures::StreamExt;
use std::fs::{self, File};
use std::io::{BufWriter, Write};
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};
use uuid::Uuid;
use vitruvian_wand_core::replay::format_line;
use vitruvian_wand_core::{Daydream, Engine, Platform};

/// Parsed CLI subcommand for the `vitruvian-wand` desktop binary.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CliCommand {
    /// Launch the graphical settings & visualizer window with tray icon.
    Gui,
    /// Connect to a Daydream controller and record packets to `path` until Ctrl-C.
    Record { path: PathBuf },
    /// Replay a `.replay` packet log from `path`, optionally injecting actions into the OS.
    Replay { path: PathBuf, inject: bool },
    /// Print system diagnostic checks (Bluetooth, permissions, config path, version).
    Doctor,
}

/// Parses command-line arguments (excluding `argv[0]`) into a [`CliCommand`].
pub fn parse_cli_args<I, S>(args: I) -> Result<CliCommand, String>
where
    I: IntoIterator<Item = S>,
    S: AsRef<str>,
{
    let tokens: Vec<String> = args.into_iter().map(|s| s.as_ref().to_string()).collect();
    if tokens.is_empty() {
        return Ok(CliCommand::Gui);
    }

    match tokens[0].as_str() {
        "doctor" => {
            if tokens.len() > 1 {
                return Err(format!(
                    "unexpected arguments after 'doctor': {}",
                    tokens[1..].join(" ")
                ));
            }
            Ok(CliCommand::Doctor)
        }
        "record" => {
            if tokens.len() != 2 {
                return Err("usage: vitruvian-wand record <file>".to_string());
            }
            Ok(CliCommand::Record {
                path: PathBuf::from(&tokens[1]),
            })
        }
        "replay" => {
            let mut path: Option<PathBuf> = None;
            let mut inject = false;
            for arg in &tokens[1..] {
                if arg == "--inject" {
                    inject = true;
                } else if arg.starts_with('-') {
                    return Err(format!("unknown flag '{arg}' for 'vitruvian-wand replay'"));
                } else if path.is_none() {
                    path = Some(PathBuf::from(arg));
                } else {
                    return Err("usage: vitruvian-wand replay <file> [--inject]".to_string());
                }
            }
            let Some(path) = path else {
                return Err("usage: vitruvian-wand replay <file> [--inject]".to_string());
            };
            Ok(CliCommand::Replay { path, inject })
        }
        other => Err(format!(
            "unknown subcommand '{other}'. Expected: vitruvian-wand [record <file> | replay <file> [--inject] | doctor]"
        )),
    }
}

/// Runs `vitruvian-wand doctor`, printing Bluetooth adapter status, OS input permission status,
/// configuration file path, and binary version.
pub fn run_doctor() -> Result<String, String> {
    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .map_err(|e| format!("failed to start tokio runtime: {e}"))?;

    let bt_status = match rt.block_on(probe_bluetooth_adapter()) {
        Ok(msg) => msg,
        Err(err) => format!("unavailable ({err})"),
    };

    #[cfg(target_os = "macos")]
    let perm_line = {
        let trusted = crate::macos::is_accessibility_trusted();
        format!(
            "macOS Accessibility trusted: {} (settings: {})",
            if trusted { "yes" } else { "no" },
            crate::macos::MACOS_ACCESSIBILITY_SETTINGS_URL
        )
    };

    #[cfg(target_os = "linux")]
    let perm_line = {
        let writable = crate::linux::is_uinput_writable();
        format!(
            "Linux /dev/uinput writable: {} (setup guide: {})",
            if writable { "yes" } else { "no" },
            crate::linux::LINUX_SETUP_DOC_PATH
        )
    };

    #[cfg(not(any(target_os = "macos", target_os = "linux")))]
    let perm_line = "Input permission: n/a".to_string();

    let cfg_path = default_config_path();
    let pkg_version = env!("CARGO_PKG_VERSION");
    let version = if pkg_version.is_empty() || pkg_version == "0.0.0" {
        "0.1.0"
    } else {
        pkg_version
    };

    let report = format!(
        "Vitruvian Wand Doctor\n\
         Version: {version}\n\
         Bluetooth adapter: {bt_status}\n\
         {perm_line}\n\
         Config path: {}\n",
        cfg_path.display()
    );
    print!("{report}");
    Ok(report)
}

/// Runs `vitruvian-wand replay <file> [--inject]`, printing every emitted [`vitruvian_wand_core::Action`]
/// and only injecting into the OS when `inject` is `true`.
pub fn run_replay(path: &Path, inject: bool) -> Result<Vec<vitruvian_wand_core::Action>, String> {
    let replay_text = fs::read_to_string(path)
        .map_err(|e| format!("failed to read replay file {}: {e}", path.display()))?;
    let cfg = load_config_from(&default_config_path());
    let mut engine = Engine::new(cfg, Platform::Desktop);

    let mut injector: Box<dyn Injector> = if inject {
        let (plat_inj, _, _) = create_platform_injector();
        plat_inj
    } else {
        Box::new(FakeInjector::new())
    };

    let actions = drive_replay_with_injector(&mut engine, &replay_text, injector.as_mut())
        .map_err(|e| format!("replay error in {}: {e}", path.display()))?;

    for (idx, action) in actions.iter().enumerate() {
        println!("{idx}: {action:?}");
    }
    Ok(actions)
}

/// Runs `vitruvian-wand record <file>`, connecting to a Daydream controller over BLE and writing
/// `<t_us> <40 hex chars>` lines until interrupted.
pub fn run_record(path: &Path) -> Result<(), String> {
    let file = File::create(path)
        .map_err(|e| format!("failed to create record file {}: {e}", path.display()))?;
    let mut writer = BufWriter::new(file);

    let rt = tokio::runtime::Builder::new_multi_thread()
        .worker_threads(2)
        .enable_all()
        .build()
        .map_err(|e| format!("failed to build tokio runtime: {e}"))?;

    rt.block_on(async move {
        let manager = Manager::new()
            .await
            .map_err(|e| format!("Bluetooth unavailable: {e}"))?;
        let adapters = manager
            .adapters()
            .await
            .map_err(|e| format!("Failed to list Bluetooth adapters: {e}"))?;
        let adapter = adapters
            .into_iter()
            .next()
            .ok_or_else(|| "No Bluetooth LE adapter found".to_string())?;

        adapter
            .start_scan(ScanFilter::default())
            .await
            .map_err(|e| format!("Failed to start BLE scan: {e}"))?;

        println!("Scanning for {}...", Daydream::NAME);
        let deadline = Instant::now() + Duration::from_secs(15);
        let peripheral = loop {
            let peripherals = adapter
                .peripherals()
                .await
                .map_err(|e| format!("Failed to query peripherals: {e}"))?;
            let mut found = None;
            for p in peripherals {
                if let Ok(Some(props)) = p.properties().await
                    && matches_daydream_peripheral(props.local_name.as_deref(), &props.services)
                {
                    found = Some(p);
                    break;
                }
            }
            if let Some(p) = found {
                break p;
            }
            if Instant::now() >= deadline {
                let _ = adapter.stop_scan().await;
                return Err("Timed out waiting for Daydream controller".to_string());
            }
            tokio::time::sleep(Duration::from_millis(250)).await;
        };

        let _ = adapter.stop_scan().await;
        peripheral
            .connect()
            .await
            .map_err(|e| format!("Failed to connect: {e}"))?;
        peripheral
            .discover_services()
            .await
            .map_err(|e| format!("Failed to discover services: {e}"))?;

        let notify_uuid = Uuid::parse_str(Daydream::NOTIFY_UUID).unwrap();
        let notify_char = peripheral
            .characteristics()
            .into_iter()
            .find(|c| c.uuid == notify_uuid)
            .ok_or_else(|| "Daydream notify characteristic not found".to_string())?;

        peripheral
            .subscribe(&notify_char)
            .await
            .map_err(|e| format!("Failed to subscribe: {e}"))?;

        println!(
            "Recording Daydream packets to {} (press Ctrl-C to stop)...",
            path.display()
        );
        let mut stream = peripheral
            .notifications()
            .await
            .map_err(|e| format!("Failed to open notifications stream: {e}"))?;
        let start = Instant::now();

        while let Some(notif) = stream.next().await {
            if notif.uuid == notify_uuid && notif.value.len() >= 20 {
                let mut pkt = [0u8; 20];
                pkt.copy_from_slice(&notif.value[..20]);
                let t_us = start.elapsed().as_micros() as u64;
                let line = format_line(t_us, &pkt);
                writeln!(writer, "{line}")
                    .map_err(|e| format!("failed writing to {}: {e}", path.display()))?;
                writer
                    .flush()
                    .map_err(|e| format!("failed flushing {}: {e}", path.display()))?;
            }
        }
        Ok(())
    })
}
