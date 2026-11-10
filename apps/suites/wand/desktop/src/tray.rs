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

//! System tray icon and menu using [`tray_icon`].

use tray_icon::menu::{CheckMenuItem, Menu, MenuEvent, MenuId, MenuItem, PredefinedMenuItem};
use tray_icon::{Icon, TrayIcon, TrayIconBuilder};

use crate::status::{ConnectionState, Status};

/// Actions emitted when the user clicks an item in the system tray menu.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TrayAction {
    ShowWindow,
    ConnectToggle,
    GyroModeToggle,
    Quit,
}

/// Manages the system tray icon, menu items, and tooltip updates.
pub struct WandTray {
    tray_icon: TrayIcon,
    show_id: MenuId,
    connect_item: MenuItem,
    connect_id: MenuId,
    gyro_item: CheckMenuItem,
    gyro_id: MenuId,
    quit_id: MenuId,
    last_connected: bool,
    last_gyro: bool,
    last_tooltip: String,
}

impl WandTray {
    /// Create the system tray icon and menu. Must be called on the main UI thread
    /// once the platform event loop is running.
    pub fn new() -> Result<Self, String> {
        let menu = Menu::new();
        let show_item = MenuItem::new("Show window", true, None);
        let connect_item = MenuItem::new("Connect", true, None);
        let gyro_item = CheckMenuItem::new("Gyro mode", true, false, None);
        let quit_item = MenuItem::new("Quit", true, None);

        let show_id = show_item.id().clone();
        let connect_id = connect_item.id().clone();
        let gyro_id = gyro_item.id().clone();
        let quit_id = quit_item.id().clone();

        menu.append(&show_item).map_err(|e| e.to_string())?;
        menu.append(&PredefinedMenuItem::separator())
            .map_err(|e| e.to_string())?;
        menu.append(&connect_item).map_err(|e| e.to_string())?;
        menu.append(&gyro_item).map_err(|e| e.to_string())?;
        menu.append(&PredefinedMenuItem::separator())
            .map_err(|e| e.to_string())?;
        menu.append(&quit_item).map_err(|e| e.to_string())?;

        let icon = build_wand_icon()?;
        let default_tooltip = "Wand — Disconnected".to_owned();
        let tray_icon = TrayIconBuilder::new()
            .with_menu(Box::new(menu))
            .with_tooltip(&default_tooltip)
            .with_icon(icon)
            .build()
            .map_err(|e| e.to_string())?;

        Ok(Self {
            tray_icon,
            show_id,
            connect_item,
            connect_id,
            gyro_item,
            gyro_id,
            quit_id,
            last_connected: false,
            last_gyro: false,
            last_tooltip: default_tooltip,
        })
    }

    /// Poll pending tray menu events and translate them to [`TrayAction`]s.
    pub fn poll_actions(&self) -> Vec<TrayAction> {
        let mut actions = Vec::new();
        while let Ok(ev) = MenuEvent::receiver().try_recv() {
            if ev.id == self.show_id {
                actions.push(TrayAction::ShowWindow);
            } else if ev.id == self.connect_id {
                actions.push(TrayAction::ConnectToggle);
            } else if ev.id == self.gyro_id {
                actions.push(TrayAction::GyroModeToggle);
            } else if ev.id == self.quit_id {
                actions.push(TrayAction::Quit);
            }
        }
        actions
    }

    /// Synchronize menu item labels/check states and tray tooltip with [`Status`].
    pub fn sync_status(&mut self, status: &Status) {
        let is_active = matches!(
            status.connection,
            ConnectionState::Connected | ConnectionState::Scanning
        );
        if is_active != self.last_connected {
            self.last_connected = is_active;
            self.connect_item
                .set_text(if is_active { "Disconnect" } else { "Connect" });
        }

        if status.gyro_mode != self.last_gyro {
            self.last_gyro = status.gyro_mode;
            self.gyro_item.set_checked(status.gyro_mode);
        }

        let tooltip = format_tray_tooltip(status);
        if tooltip != self.last_tooltip {
            let _ = self.tray_icon.set_tooltip(Some(&tooltip));
            self.last_tooltip = tooltip;
        }
    }
}

/// Format the tray tooltip string, including the low-battery warning once triggered
/// for the current connection.
#[must_use]
pub fn format_tray_tooltip(status: &Status) -> String {
    if status.low_battery_alert_active
        && let Some(pct) = status.battery_percent
    {
        return format!("Wand — Low battery ({pct}%)");
    }
    match &status.connection {
        ConnectionState::Disconnected => "Wand — Disconnected".to_owned(),
        ConnectionState::Scanning => "Wand — Scanning…".to_owned(),
        ConnectionState::Connected => {
            if let Some(pct) = status.battery_percent {
                format!("Wand — Connected · {} ({pct}%)", status.device_name)
            } else {
                format!("Wand — Connected · {}", status.device_name)
            }
        }
        ConnectionState::Error(msg) => format!("Wand — Error: {msg}"),
    }
}

fn build_wand_icon() -> Result<Icon, String> {
    let size = 16u32;
    let mut rgba = vec![0u8; (size * size * 4) as usize];
    for y in 0..size {
        for x in 0..size {
            let dx = x as f32 - 7.5;
            let dy = y as f32 - 7.5;
            let dist = (dx * dx + dy * dy).sqrt();
            let idx = ((y * size + x) * 4) as usize;
            if dist <= 6.5 {
                if dist <= 2.5 {
                    rgba[idx] = 0xe7;
                    rgba[idx + 1] = 0xe4;
                    rgba[idx + 2] = 0xdd;
                    rgba[idx + 3] = 0xff;
                } else {
                    rgba[idx] = 0x59;
                    rgba[idx + 1] = 0x80;
                    rgba[idx + 2] = 0xa6;
                    rgba[idx + 3] = 0xff;
                }
            }
        }
    }
    Icon::from_rgba(rgba, size, size).map_err(|e| e.to_string())
}
