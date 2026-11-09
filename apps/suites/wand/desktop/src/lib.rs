// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of this
// software and associated documentation files (the "Software"), to deal in the Software
// without restriction, including without limitation the rights to use, copy, modify,
// merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
// permit persons to whom the Software is furnished to do so, subject to the following
// conditions:
//
// The above copyright notice and this permission notice shall be included in all copies
// or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
// INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
// PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
// HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
// CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE
// OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

//! Cross-platform desktop library for the Wand air-mouse application (macOS and Linux).

pub mod ble;
pub mod cli;
pub mod config;
pub mod glide;
pub mod injector;
pub mod input;
pub mod launch;
pub mod linux;
pub mod macos;
pub mod radial_overlay;
pub mod status;
pub mod theme;
pub mod tray;
pub mod ui;

use std::sync::{Arc, Mutex};

use crate::ble::spawn_ble_thread;
use crate::cli::{CliCommand, parse_cli_args, run_doctor, run_record, run_replay};
use crate::config::{default_config_path, load_config_from};
use crate::input::{create_platform_injector, spawn_input_thread};
use crate::status::Status;
use crate::ui::{WINDOW_DEFAULT_SIZE, WINDOW_MIN_SIZE, WandApp};

/// Entrypoint invoked by `main.rs`. Parses CLI arguments and runs either the
/// requested subcommand (`doctor`, `replay`, `record`) or the `eframe` GUI.
pub fn run_from_env() -> Result<(), String> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let cmd = parse_cli_args(&args)?;
    match cmd {
        CliCommand::Doctor => {
            run_doctor()?;
            Ok(())
        }
        CliCommand::Replay { path, inject } => {
            run_replay(&path, inject)?;
            Ok(())
        }
        CliCommand::Record { path } => run_record(&path),
        CliCommand::Gui => run_gui(),
    }
}

/// Launch the `eframe` desktop GUI together with the BLE and input threads.
pub fn run_gui() -> Result<(), String> {
    let config_path = default_config_path();
    let config = load_config_from(&config_path);
    let status = Arc::new(Mutex::new(Status::default()));

    let (injector, perm_ok, perm_msg) = create_platform_injector();
    if let Ok(mut st) = status.lock() {
        st.permission_ok = perm_ok;
        st.permission_message = perm_msg;
    }

    let (input_tx, input_join) = spawn_input_thread(config.clone(), injector, Arc::clone(&status));
    let (ble_tx, _ble_join) = spawn_ble_thread(
        config.settings.auto_reconnect,
        input_tx.clone(),
        Arc::clone(&status),
    );

    let viewport = egui::ViewportBuilder::default()
        .with_title("Wand")
        .with_inner_size(WINDOW_DEFAULT_SIZE)
        .with_min_inner_size(WINDOW_MIN_SIZE);

    let native_options = eframe::NativeOptions {
        viewport,
        ..Default::default()
    };

    let exit_input_tx = input_tx.clone();
    let exit_ble_tx = ble_tx.clone();
    let res = eframe::run_native(
        "Wand",
        native_options,
        Box::new(move |_cc| {
            Ok(Box::new(WandApp::new(
                config,
                config_path,
                status,
                input_tx,
                ble_tx,
            )))
        }),
    )
    .map_err(|e| format!("eframe error: {e}"));

    let _ = exit_input_tx.send(crate::input::InputCommand::ReleaseAll);
    let _ = exit_ble_tx.send(crate::ble::BleCommand::Shutdown);
    let _ = exit_input_tx.send(crate::input::InputCommand::Shutdown);
    let _ = input_join.join();
    res
}
