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

//! `eframe` / `egui` user interface for Vitruvian Wand Desktop.

use std::f32::consts::{FRAC_PI_2, TAU};
use std::path::PathBuf;
use std::sync::mpsc::Sender;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use egui::{
    Align, Align2, CentralPanel, Color32, ComboBox, Context, CornerRadius, FontId, Frame, Grid, Id,
    Key, Layout, Margin, Panel, Rect, RichText, ScrollArea, Sense, Slider, Stroke, StrokeKind, Ui,
    ViewportBuilder, ViewportClass, ViewportCommand, ViewportId, WindowLevel, pos2, vec2,
};
use tokio::sync::mpsc::UnboundedSender;
use vitruvian_wand_core::{
    Action, Binding, BrightnessAction, Button, Config, KeyChord, MediaAction, NavAction, Platform,
    PointingMode, Press, RADIAL_SLOT_COUNT, RadialSlot, SystemAction, TriggerMode, VolumeAction,
};

use crate::ble::BleCommand;
use crate::config::{
    DebouncedSaver, ThemePreference, get_gyro_touchpad_scroll, get_theme, set_gyro_touchpad_scroll,
    set_theme,
};
use crate::input::InputCommand;
use crate::radial_overlay::{
    RADIAL_VIEWPORT_SIZE, compute_radial_viewport_origin, is_wayland_session,
};
use crate::status::{ConnectionState, Status};
use crate::theme::{
    Palette, RADIAL_COLOR_PRESETS, active_palette, apply_theme, resolve_slot_color, spacing,
    type_scale,
};
use crate::tray::{TrayAction, WandTray};

/// Main window default dimensions (`760×540`).
pub const WINDOW_DEFAULT_SIZE: [f32; 2] = [760.0, 540.0];
/// Main window minimum dimensions (`640×480`).
pub const WINDOW_MIN_SIZE: [f32; 2] = [640.0, 480.0];
/// Left sidebar fixed width (`160 px`).
pub const SIDEBAR_WIDTH: f32 = 160.0;

/// Sidebar navigation sections.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SidebarSection {
    Connection,
    Controls,
    Bindings,
    RadialMenu,
    TestMode,
}

impl SidebarSection {
    pub const ALL: [Self; 5] = [
        Self::Connection,
        Self::Controls,
        Self::Bindings,
        Self::RadialMenu,
        Self::TestMode,
    ];

    #[must_use]
    pub const fn label(self) -> &'static str {
        match self {
            Self::Connection => "Connection",
            Self::Controls => "Controls",
            Self::Bindings => "Bindings",
            Self::RadialMenu => "Radial menu",
            Self::TestMode => "Test mode",
        }
    }

    #[must_use]
    pub fn from_env() -> Self {
        match std::env::var("VITRUVIAN_WAND_INITIAL_TAB")
            .unwrap_or_default()
            .trim()
            .to_ascii_lowercase()
            .as_str()
        {
            "controls" => Self::Controls,
            "bindings" => Self::Bindings,
            "radial" | "radial_menu" | "radial-menu" => Self::RadialMenu,
            "test" | "test_mode" | "test-mode" => Self::TestMode,
            _ => Self::Connection,
        }
    }
}

/// Identifies which binding cell (or radial slot) is currently capturing a keyboard chord.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ChordCaptureTarget {
    Binding(Button, Press),
    RadialSlot(usize),
}

/// Main `eframe` application state.
pub struct WandApp {
    config: Config,
    saver: DebouncedSaver,
    status: Arc<Mutex<Status>>,
    input_tx: Sender<InputCommand>,
    ble_tx: UnboundedSender<BleCommand>,
    section: SidebarSection,
    confirm_reset: bool,
    capturing_chord: Option<ChordCaptureTarget>,
    tray: Option<WandTray>,
    tray_init_attempted: bool,
    quit_requested: bool,
    theme_applied: Option<ThemePreference>,
}

impl WandApp {
    /// Construct a new [`WandApp`].
    #[must_use]
    pub fn new(
        config: Config,
        config_path: PathBuf,
        status: Arc<Mutex<Status>>,
        input_tx: Sender<InputCommand>,
        ble_tx: UnboundedSender<BleCommand>,
    ) -> Self {
        Self {
            config,
            saver: DebouncedSaver::new(config_path),
            status,
            input_tx,
            ble_tx,
            section: SidebarSection::from_env(),
            confirm_reset: false,
            capturing_chord: None,
            tray: None,
            tray_init_attempted: false,
            quit_requested: false,
            theme_applied: None,
        }
    }

    fn mark_config_changed(&mut self, now: Instant) {
        self.saver.mark_dirty_at(now);
        let _ = self
            .input_tx
            .send(InputCommand::UpdateConfig(self.config.clone()));
        let _ = self.ble_tx.send(BleCommand::SetAutoReconnect(
            self.config.settings.auto_reconnect,
        ));
    }

    fn handle_tray_events(&mut self, ctx: &Context, status_snapshot: &Status) {
        if !self.tray_init_attempted {
            self.tray_init_attempted = true;
            match WandTray::new() {
                Ok(tray) => self.tray = Some(tray),
                Err(err) => log::warn!("System tray unavailable: {err}"),
            }
        }

        let actions = if let Some(tray) = &mut self.tray {
            tray.sync_status(status_snapshot);
            tray.poll_actions()
        } else {
            Vec::new()
        };

        for action in actions {
            match action {
                TrayAction::ShowWindow => {
                    ctx.send_viewport_cmd(ViewportCommand::Visible(true));
                    ctx.send_viewport_cmd(ViewportCommand::Focus);
                }
                TrayAction::ConnectToggle => {
                    if matches!(
                        status_snapshot.connection,
                        ConnectionState::Connected | ConnectionState::Scanning
                    ) {
                        let _ = self.input_tx.send(InputCommand::ReleaseAll);
                        let _ = self.ble_tx.send(BleCommand::Disconnect);
                    } else {
                        let _ = self.ble_tx.send(BleCommand::Connect);
                    }
                }
                TrayAction::GyroModeToggle => {
                    let _ = self.input_tx.send(InputCommand::ToggleGyroMode);
                }
                TrayAction::Quit => {
                    self.quit_requested = true;
                    let _ = self.input_tx.send(InputCommand::ReleaseAll);
                    let _ = self.ble_tx.send(BleCommand::Shutdown);
                    let _ = self.input_tx.send(InputCommand::Shutdown);
                    ctx.send_viewport_cmd(ViewportCommand::Close);
                }
            }
        }
    }

    fn render_header(&mut self, ui: &mut Ui, status: &Status, palette: Palette) {
        let header_frame = Frame::new()
            .fill(palette.surface)
            .inner_margin(Margin::symmetric(spacing::S4 as i8, spacing::S3 as i8))
            .stroke(Stroke::new(1.0, palette.divider));

        Panel::top("wand_header_bar")
            .frame(header_frame)
            .resizable(false)
            .show_separator_line(false)
            .show(ui, |ui| {
                ui.horizontal(|ui| {
                    ui.label(
                        RichText::new("Vitruvian Wand")
                            .size(type_scale::H3)
                            .strong()
                            .color(palette.text),
                    );

                    ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                        // Theme selector: System / Light / Dark
                        let current_theme = get_theme(&self.config);
                        let mut selected_theme = current_theme;
                        ComboBox::from_id_salt("header_theme_selector")
                            .width(92.0)
                            .selected_text(current_theme.label())
                            .show_ui(ui, |ui| {
                                for candidate in [
                                    ThemePreference::System,
                                    ThemePreference::Light,
                                    ThemePreference::Dark,
                                ] {
                                    ui.selectable_value(
                                        &mut selected_theme,
                                        candidate,
                                        candidate.label(),
                                    );
                                }
                            });
                        if selected_theme != current_theme {
                            set_theme(&mut self.config, selected_theme);
                            apply_theme(ui.ctx(), selected_theme);
                            self.theme_applied = Some(selected_theme);
                            self.mark_config_changed(Instant::now());
                        }

                        ui.add_space(spacing::S3);

                        // Battery % with 4-level icon
                        self.draw_battery_indicator(ui, status, palette);

                        ui.add_space(spacing::S3);

                        // Status pill
                        self.draw_status_pill(ui, status, palette);
                    });
                });
            });
    }

    fn draw_status_pill(&self, ui: &mut Ui, status: &Status, palette: Palette) {
        let (pill_bg, dot_color, label) = match &status.connection {
            ConnectionState::Disconnected => (
                palette.surface_2,
                palette.neutral_500,
                "Disconnected".to_owned(),
            ),
            ConnectionState::Scanning => {
                (palette.accent_quiet, palette.accent, "Scanning…".to_owned())
            }
            ConnectionState::Connected => (
                Color32::from_rgba_unmultiplied(palette.ok.r(), palette.ok.g(), palette.ok.b(), 38),
                palette.ok,
                format!("Connected · {}", status.device_name),
            ),
            ConnectionState::Error(_) => (
                Color32::from_rgba_unmultiplied(
                    palette.crit.r(),
                    palette.crit.g(),
                    palette.crit.b(),
                    38,
                ),
                palette.crit,
                "Error".to_owned(),
            ),
        };

        Frame::new()
            .fill(pill_bg)
            .stroke(Stroke::new(1.0, dot_color))
            .inner_margin(Margin::symmetric(spacing::S3 as i8, spacing::S1 as i8))
            .show(ui, |ui| {
                ui.horizontal(|ui| {
                    let (dot_rect, _) = ui.allocate_exact_size(vec2(8.0, 8.0), Sense::hover());
                    ui.painter()
                        .circle_filled(dot_rect.center(), 3.5, dot_color);
                    ui.label(
                        RichText::new(label)
                            .size(type_scale::SMALL)
                            .color(palette.text),
                    );
                });
            });
    }

    fn draw_battery_indicator(&self, ui: &mut Ui, status: &Status, palette: Palette) {
        let bars = status.battery_percent.map_or(0, Status::battery_level_bars);
        let pct_text = status
            .battery_percent
            .map_or_else(|| "—%".to_owned(), |p| format!("{p}%"));
        let bar_color = match status.battery_percent {
            Some(p) if p < 15 => palette.crit,
            Some(p) if p < 35 => palette.warn,
            Some(_) => palette.ok,
            None => palette.neutral_500,
        };

        ui.horizontal(|ui| {
            ui.label(
                RichText::new(pct_text)
                    .size(type_scale::SMALL)
                    .monospace()
                    .color(palette.text_dim),
            );
            let (icon_rect, _) = ui.allocate_exact_size(vec2(24.0, 12.0), Sense::hover());
            let painter = ui.painter();
            let body = Rect::from_min_size(icon_rect.min, vec2(20.0, 12.0));
            let tip = Rect::from_min_size(pos2(body.max.x, body.center().y - 3.0), vec2(3.0, 6.0));
            painter.rect_stroke(
                body,
                CornerRadius::ZERO,
                Stroke::new(1.0, palette.text_dim),
                StrokeKind::Inside,
            );
            painter.rect_filled(tip, CornerRadius::ZERO, palette.text_dim);

            for i in 0..4u8 {
                let x = body.min.x + 2.0 + f32::from(i) * 4.2;
                let seg = Rect::from_min_size(pos2(x, body.min.y + 2.0), vec2(3.2, 8.0));
                let fill = if i < bars {
                    bar_color
                } else {
                    palette.surface_2
                };
                painter.rect_filled(seg, CornerRadius::ZERO, fill);
            }
        });
    }

    fn render_low_battery_banner(&self, ui: &mut Ui, status: &Status, palette: Palette) {
        if !status.low_battery_alert_active {
            return;
        }
        let pct = status.battery_percent.unwrap_or(0);
        let banner_frame = Frame::new()
            .fill(Color32::from_rgba_unmultiplied(
                palette.warn.r(),
                palette.warn.g(),
                palette.warn.b(),
                36,
            ))
            .stroke(Stroke::new(1.0, palette.warn))
            .inner_margin(Margin::symmetric(spacing::S4 as i8, spacing::S2 as i8));

        Panel::top("wand_low_battery_banner")
            .frame(banner_frame)
            .resizable(false)
            .show_separator_line(false)
            .show(ui, |ui| {
                ui.horizontal(|ui| {
                    ui.label(
                        RichText::new(format!(
                            "Low controller battery ({pct}%) — charge your Daydream controller soon."
                        ))
                        .size(type_scale::SMALL)
                        .strong()
                        .color(palette.text),
                    );
                });
            });
    }

    fn render_sidebar(&mut self, ui: &mut Ui, palette: Palette) {
        let sidebar_frame = Frame::new()
            .fill(palette.surface)
            .inner_margin(Margin::symmetric(spacing::S3 as i8, spacing::S4 as i8))
            .stroke(Stroke::new(1.0, palette.divider));

        Panel::left("wand_left_sidebar")
            .exact_size(SIDEBAR_WIDTH)
            .resizable(false)
            .show_separator_line(false)
            .frame(sidebar_frame)
            .show(ui, |ui| {
                ui.vertical(|ui| {
                    for item in SidebarSection::ALL {
                        let is_selected = self.section == item;
                        let fill = if is_selected {
                            palette.accent_quiet
                        } else {
                            Color32::TRANSPARENT
                        };
                        let text_color = if is_selected {
                            palette.accent_text
                        } else {
                            palette.text_dim
                        };
                        let stroke = if is_selected {
                            Stroke::new(1.0, palette.accent)
                        } else {
                            Stroke::NONE
                        };

                        let btn = egui::Button::new(
                            RichText::new(item.label())
                                .size(type_scale::BODY)
                                .color(text_color),
                        )
                        .fill(fill)
                        .stroke(stroke)
                        .min_size(vec2(SIDEBAR_WIDTH - spacing::S3 * 2.0, 32.0));

                        if ui.add(btn).clicked() {
                            self.section = item;
                            self.capturing_chord = None;
                        }
                        ui.add_space(spacing::S1);
                    }
                });
            });
    }

    fn render_connection_section(&mut self, ui: &mut Ui, status: &Status, palette: Palette) {
        ui.heading("Connection");
        ui.add_space(spacing::S2);
        ui.label(
            RichText::new(
                "Pair and connect a Daydream controller over Bluetooth Low Energy (service 0xFE55).",
            )
            .color(palette.text_dim),
        );
        ui.add_space(spacing::S4);

        Frame::new()
            .fill(palette.surface)
            .stroke(Stroke::new(1.0, palette.divider))
            .inner_margin(Margin::same(spacing::S4 as i8))
            .show(ui, |ui| {
                ui.horizontal(|ui| {
                    let is_active = matches!(
                        status.connection,
                        ConnectionState::Connected | ConnectionState::Scanning
                    );
                    let btn_label = if is_active { "Disconnect" } else { "Connect" };
                    if ui
                        .add_sized([130.0, 32.0], egui::Button::new(btn_label))
                        .clicked()
                    {
                        if is_active {
                            let _ = self.input_tx.send(InputCommand::ReleaseAll);
                            let _ = self.ble_tx.send(BleCommand::Disconnect);
                        } else {
                            let _ = self.ble_tx.send(BleCommand::Connect);
                        }
                    }

                    ui.add_space(spacing::S3);

                    if ui
                        .add_sized([130.0, 32.0], egui::Button::new("Recalibrate"))
                        .clicked()
                    {
                        let _ = self.input_tx.send(InputCommand::Recalibrate);
                    }
                    ui.label(
                        RichText::new("Lay the controller flat, then press")
                            .size(type_scale::SMALL)
                            .color(palette.text_dim),
                    );
                });

                if let ConnectionState::Error(err) = &status.connection {
                    ui.add_space(spacing::S3);
                    ui.label(
                        RichText::new(format!("Error: {err}"))
                            .size(type_scale::SMALL)
                            .color(palette.crit),
                    );
                }

                ui.add_space(spacing::S2);
                ui.separator();
                ui.add_space(spacing::S2);

                let mut auto_reconnect = self.config.settings.auto_reconnect;
                if ui
                    .checkbox(
                        &mut auto_reconnect,
                        "Auto-reconnect when controller wakes or disconnects",
                    )
                    .changed()
                {
                    self.config.settings.auto_reconnect = auto_reconnect;
                    self.mark_config_changed(Instant::now());
                }
            });

        ui.add_space(spacing::S4);

        // Permission status card
        Frame::new()
            .fill(palette.surface)
            .stroke(Stroke::new(1.0, palette.divider))
            .inner_margin(Margin::same(spacing::S4 as i8))
            .show(ui, |ui| {
                ui.horizontal(|ui| {
                    #[cfg(target_os = "macos")]
                    {
                        let trusted = crate::macos::is_accessibility_trusted();
                        let (status_str, status_color) = if trusted {
                            ("Accessibility permission: Granted", palette.ok)
                        } else {
                            (
                                "Accessibility permission: Not granted (required for input injection)",
                                palette.warn,
                            )
                        };
                        ui.label(RichText::new(status_str).color(status_color));
                        ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                            if ui.button("Open Accessibility Settings").clicked() {
                                let _ = crate::macos::open_accessibility_settings();
                            }
                        });
                    }

                    #[cfg(target_os = "linux")]
                    {
                        let writable = crate::linux::is_uinput_writable();
                        let (status_str, status_color) = if writable {
                            ("/dev/uinput permission: Writable", palette.ok)
                        } else {
                            (
                                "/dev/uinput permission: Not writable (see docs/setup-linux.md)",
                                palette.warn,
                            )
                        };
                        ui.label(RichText::new(status_str).color(status_color));
                        ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                            if ui.button("Fix (/dev/uinput guide)").clicked() {
                                let _ = std::process::Command::new("xdg-open")
                                    .arg(crate::linux::LINUX_SETUP_DOC_PATH)
                                    .spawn();
                            }
                        });
                    }
                });
            });
    }

    fn render_controls_section(&mut self, ui: &mut Ui, palette: Palette) {
        ui.heading("Controls");
        ui.add_space(spacing::S2);
        ui.label(
            RichText::new("Tune pointer speed, deadzones, response curve, and touchpad behaviour.")
                .color(palette.text_dim),
        );
        ui.add_space(spacing::S4);

        let mut changed = false;

        Frame::new()
            .fill(palette.surface)
            .stroke(Stroke::new(1.0, palette.divider))
            .inner_margin(Margin::same(spacing::S3 as i8))
            .show(ui, |ui| {
                Grid::new("wand_controls_sliders_grid")
                    .num_columns(2)
                    .spacing([spacing::S4, spacing::S2])
                    .show(ui, |ui| {
                        ui.label("Touch sensitivity");
                        changed |= ui
                            .add(
                                Slider::new(
                                    &mut self.config.settings.touch_sensitivity,
                                    50.0..=1200.0,
                                )
                                .fixed_decimals(0),
                            )
                            .changed();
                        ui.end_row();

                        ui.label("Touch deadzone");
                        changed |= ui
                            .add(
                                Slider::new(&mut self.config.settings.touch_deadzone, 0.0..=0.2)
                                    .fixed_decimals(3),
                            )
                            .changed();
                        ui.end_row();

                        ui.label("Pointing");
                        ui.horizontal(|ui| {
                            changed |= ui
                                .selectable_value(
                                    &mut self.config.settings.pointing_mode,
                                    PointingMode::Absolute,
                                    "Laser pointer",
                                )
                                .changed();
                            changed |= ui
                                .selectable_value(
                                    &mut self.config.settings.pointing_mode,
                                    PointingMode::Relative,
                                    "Mouse",
                                )
                                .changed();
                        });
                        ui.end_row();

                        match self.config.settings.pointing_mode {
                            PointingMode::Absolute => {
                                ui.label(format!(
                                    "Screen width covers {:.0}°",
                                    self.config.settings.pointing_span_deg
                                ));
                                changed |= ui
                                    .add(
                                        Slider::new(
                                            &mut self.config.settings.pointing_span_deg,
                                            15.0..=150.0,
                                        )
                                        .fixed_decimals(0)
                                        .suffix("°"),
                                    )
                                    .changed();
                                ui.end_row();

                                ui.label("");
                                changed |= ui
                                    .checkbox(
                                        &mut self.config.settings.motion_glide,
                                        "Smooth cursor between updates",
                                    )
                                    .changed();
                                ui.end_row();

                                ui.label("");
                                ui.label(
                                    RichText::new(
                                        "Point at the middle of the screen and press App to start",
                                    )
                                    .size(type_scale::SMALL)
                                    .color(palette.text_dim),
                                );
                                ui.end_row();

                                #[cfg(target_os = "linux")]
                                {
                                    ui.label("Screen width (px)");
                                    changed |= ui
                                        .add(
                                            Slider::new(
                                                &mut self.config.settings.screen_width_px,
                                                640..=7680,
                                            )
                                            .suffix(" px"),
                                        )
                                        .changed();
                                    ui.end_row();
                                }
                            }
                            PointingMode::Relative => {
                                ui.label("Gyro X speed");
                                changed |= ui
                                    .add(
                                        Slider::new(
                                            &mut self.config.settings.gyro_x_speed,
                                            1.0..=60.0,
                                        )
                                        .fixed_decimals(1),
                                    )
                                    .changed();
                                ui.end_row();

                                ui.label("Gyro Y speed");
                                changed |= ui
                                    .add(
                                        Slider::new(
                                            &mut self.config.settings.gyro_y_speed,
                                            1.0..=60.0,
                                        )
                                        .fixed_decimals(1),
                                    )
                                    .changed();
                                ui.end_row();

                                ui.label("Acceleration curve");
                                changed |= ui
                                    .add(
                                        Slider::new(
                                            &mut self.config.settings.acceleration_curve,
                                            1.0..=3.0,
                                        )
                                        .fixed_decimals(2),
                                    )
                                    .changed();
                                ui.end_row();
                            }
                        }

                        ui.label("Gyro deadzone");
                        changed |= ui
                            .add(
                                Slider::new(&mut self.config.settings.gyro_deadzone, 0.0..=0.5)
                                    .fixed_decimals(3),
                            )
                            .changed();
                        ui.end_row();

                        ui.label("Smoothing");
                        changed |= ui
                            .add(
                                Slider::new(&mut self.config.settings.ema_smoothing, 0.0..=0.95)
                                    .fixed_decimals(2),
                            )
                            .changed();
                        ui.end_row();

                        ui.label("Scroll strength");
                        changed |= ui
                            .add(
                                Slider::new(&mut self.config.settings.scroll_strength, 0.1..=5.0)
                                    .fixed_decimals(2),
                            )
                            .changed();
                        ui.end_row();
                    });

                ui.add_space(spacing::S2);
                ui.separator();
                ui.add_space(spacing::S2);

                changed |= ui
                    .checkbox(
                        &mut self.config.settings.reverse_scroll,
                        "Reverse scroll direction",
                    )
                    .changed();

                let mut gyro_scroll = get_gyro_touchpad_scroll(&self.config);
                if ui
                    .checkbox(&mut gyro_scroll, "Touchpad scrolling in gyro mode")
                    .changed()
                {
                    set_gyro_touchpad_scroll(&mut self.config, gyro_scroll);
                    changed = true;
                }

                ui.indent("horiz_scroll_indent", |ui| {
                    ui.add_enabled_ui(gyro_scroll, |ui| {
                        changed |= ui
                            .checkbox(
                                &mut self.config.settings.horizontal_scroll,
                                "Horizontal touchpad scroll",
                            )
                            .changed();
                    });
                });
                changed |= ui
                    .checkbox(
                        &mut self.config.settings.tap_in_touch_mode,
                        "Touchpad tap in touch mode",
                    )
                    .changed();
                changed |= ui
                    .checkbox(
                        &mut self.config.settings.tap_in_gyro_mode,
                        "Touchpad tap in gyro mode",
                    )
                    .changed();

                ui.add_space(spacing::S2);
                ui.horizontal(|ui| {
                    if !self.confirm_reset {
                        if ui.button("Reset to defaults").clicked() {
                            self.confirm_reset = true;
                        }
                    } else {
                        ui.label(
                            RichText::new("Reset all controls to defaults?").color(palette.warn),
                        );
                        if ui.button("Confirm reset").clicked() {
                            let def = Config::for_platform(Platform::Desktop);
                            self.config.settings = def.settings;
                            set_gyro_touchpad_scroll(&mut self.config, true);
                            self.confirm_reset = false;
                            changed = true;
                        }
                        if ui.button("Cancel").clicked() {
                            self.confirm_reset = false;
                        }
                    }
                });
            });

        if changed {
            self.mark_config_changed(Instant::now());
        }
    }

    fn render_bindings_section(&mut self, ui: &mut Ui, palette: Palette) {
        ui.heading("Bindings");
        ui.add_space(spacing::S2);
        ui.label(
            RichText::new(
                "Assign Short, Long, and Double press actions and trigger modes for each button.",
            )
            .color(palette.text_dim),
        );
        ui.add_space(spacing::S3);

        self.poll_chord_capture(ui);

        let mut changed = false;

        Frame::new()
            .fill(palette.surface)
            .stroke(Stroke::new(1.0, palette.divider))
            .inner_margin(Margin::same(spacing::S3 as i8))
            .show(ui, |ui| {
                Grid::new("wand_bindings_matrix_grid")
                    .num_columns(4)
                    .striped(true)
                    .spacing([spacing::S2, spacing::S2])
                    .show(ui, |ui| {
                        ui.label(
                            RichText::new("Button")
                                .font(FontId::proportional(type_scale::H5))
                                .strong()
                                .color(palette.text),
                        );
                        for p in Press::ALL {
                            ui.label(
                                RichText::new(press_label(p))
                                    .font(FontId::proportional(type_scale::H5))
                                    .strong()
                                    .color(palette.text),
                            );
                        }
                        ui.end_row();

                        for button in Button::ALL {
                            ui.label(
                                RichText::new(button_label(button))
                                    .strong()
                                    .color(palette.text),
                            );

                            for press in Press::ALL {
                                let mut slot = self.config.bindings.get(&(button, press)).cloned();
                                let hold_hint =
                                    hold_delay_hint(&self.config.bindings, button, press);
                                if render_binding_cell(
                                    ui,
                                    button,
                                    press,
                                    &mut slot,
                                    hold_hint,
                                    &mut self.capturing_chord,
                                    palette,
                                ) {
                                    if let Some(binding) = slot {
                                        self.config.bindings.insert((button, press), binding);
                                    } else {
                                        self.config.bindings.remove(&(button, press));
                                    }
                                    changed = true;
                                }
                            }
                            ui.end_row();
                        }
                    });
            });

        if changed {
            self.mark_config_changed(Instant::now());
        }
    }

    fn render_radial_section(&mut self, ui: &mut Ui, palette: Palette) {
        ui.heading("Radial menu");
        ui.add_space(spacing::S2);
        ui.label(
            RichText::new(
                "Configure the 8 radial slots (0 = Up, clockwise) and preview the wheel.",
            )
            .color(palette.text_dim),
        );
        ui.add_space(spacing::S3);

        self.poll_chord_capture(ui);
        while self.config.radial_slots.len() < RADIAL_SLOT_COUNT {
            self.config.radial_slots.push(RadialSlot {
                label: format!("Slot {}", self.config.radial_slots.len() + 1),
                color: "slate".to_owned(),
                action: None,
            });
        }

        let mut changed = false;

        ui.horizontal_top(|ui| {
            // Left: 8-slot list
            Frame::new()
                .fill(palette.surface)
                .stroke(Stroke::new(1.0, palette.divider))
                .inner_margin(Margin::same(spacing::S3 as i8))
                .show(ui, |ui| {
                    Grid::new("wand_radial_slots_grid")
                        .num_columns(4)
                        .spacing([spacing::S2, spacing::S2])
                        .show(ui, |ui| {
                            ui.label(RichText::new("#").strong().color(palette.text));
                            ui.label(RichText::new("Label").strong().color(palette.text));
                            ui.label(RichText::new("Colour").strong().color(palette.text));
                            ui.label(RichText::new("Action").strong().color(palette.text));
                            ui.end_row();

                            for idx in 0..RADIAL_SLOT_COUNT {
                                let slot = &mut self.config.radial_slots[idx];
                                ui.label(
                                    RichText::new(format!("{}", idx + 1))
                                        .monospace()
                                        .color(palette.text_dim),
                                );
                                changed |= ui
                                    .add(
                                        egui::TextEdit::singleline(&mut slot.label)
                                            .desired_width(82.0),
                                    )
                                    .changed();

                                ComboBox::from_id_salt(("radial_color_combo", idx))
                                    .width(78.0)
                                    .selected_text(&slot.color)
                                    .show_ui(ui, |ui| {
                                        for (preset_name, _) in RADIAL_COLOR_PRESETS {
                                            if ui
                                                .selectable_label(
                                                    slot.color.eq_ignore_ascii_case(preset_name),
                                                    *preset_name,
                                                )
                                                .clicked()
                                            {
                                                slot.color = (*preset_name).to_owned();
                                                changed = true;
                                            }
                                        }
                                    });

                                ui.vertical(|ui| {
                                    if render_action_combo(
                                        ui,
                                        Id::unique(("radial_action_combo", idx)),
                                        &mut slot.action,
                                        true,
                                        96.0,
                                    ) {
                                        changed = true;
                                    }
                                    if let Some(act) = &mut slot.action {
                                        match act {
                                            Action::Key(chord) => {
                                                let target = ChordCaptureTarget::RadialSlot(idx);
                                                let is_capturing =
                                                    self.capturing_chord == Some(target);
                                                let btn_text = if is_capturing {
                                                    "Press key…".to_owned()
                                                } else {
                                                    format!("Chord: {}", format_chord(chord))
                                                };
                                                if ui
                                                    .add(egui::Button::new(
                                                        RichText::new(btn_text)
                                                            .size(type_scale::SMALL)
                                                            .color(if is_capturing {
                                                                palette.accent_text
                                                            } else {
                                                                palette.text_dim
                                                            }),
                                                    ))
                                                    .clicked()
                                                {
                                                    self.capturing_chord = Some(target);
                                                }
                                            }
                                            Action::LaunchApp(app_target) => {
                                                if ui
                                                    .add(
                                                        egui::TextEdit::singleline(app_target)
                                                            .desired_width(96.0)
                                                            .hint_text("bundle id / name"),
                                                    )
                                                    .changed()
                                                {
                                                    changed = true;
                                                }
                                            }
                                            _ => {}
                                        }
                                    }
                                });
                                ui.end_row();
                            }
                        });
                });

            ui.add_space(spacing::S3);

            // Right: live preview circle
            Frame::new()
                .fill(palette.surface)
                .stroke(Stroke::new(1.0, palette.divider))
                .inner_margin(Margin::same(spacing::S3 as i8))
                .show(ui, |ui| {
                    ui.vertical_centered(|ui| {
                        ui.label(RichText::new("Live preview").strong().color(palette.text));
                        ui.add_space(spacing::S2);
                        draw_radial_wheel(ui, &self.config.radial_slots, None, 170.0, palette);
                    });
                });
        });

        if changed {
            self.mark_config_changed(Instant::now());
        }
    }

    fn render_test_mode_section(&mut self, ui: &mut Ui, status: &Status, palette: Palette) {
        ui.heading("Test mode");
        ui.add_space(spacing::S2);
        ui.label(
            RichText::new(
                "Inspect live controller sensors and button states while suppressing OS cursor and key injection.",
            )
            .color(palette.text_dim),
        );
        ui.add_space(spacing::S3);

        let mut test_mode = status.test_mode;
        if ui
            .checkbox(
                &mut test_mode,
                "Enable engine test mode (suppress OS input injection)",
            )
            .changed()
        {
            let _ = self.input_tx.send(InputCommand::SetTestMode(test_mode));
        }

        ui.add_space(spacing::S3);

        let sample = status.last_sample;

        ui.horizontal_top(|ui| {
            // Left card: Touchpad circle + 5 button indicators
            Frame::new()
                .fill(palette.surface)
                .stroke(Stroke::new(1.0, palette.divider))
                .inner_margin(Margin::same(spacing::S4 as i8))
                .show(ui, |ui| {
                    ui.vertical_centered(|ui| {
                        ui.label(RichText::new("Touchpad").strong().color(palette.text));
                        ui.add_space(spacing::S2);
                        let (rect, _) = ui.allocate_exact_size(vec2(150.0, 150.0), Sense::hover());
                        let painter = ui.painter();
                        let center = rect.center();
                        let radius = 68.0;
                        painter.circle_filled(center, radius, palette.surface_2);
                        painter.circle_stroke(center, radius, Stroke::new(1.5, palette.divider));

                        // Crosshairs
                        painter.line_segment(
                            [
                                pos2(center.x - radius, center.y),
                                pos2(center.x + radius, center.y),
                            ],
                            Stroke::new(1.0, palette.line),
                        );
                        painter.line_segment(
                            [
                                pos2(center.x, center.y - radius),
                                pos2(center.x, center.y + radius),
                            ],
                            Stroke::new(1.0, palette.line),
                        );

                        if let Some(s) = sample
                            && s.touching
                        {
                            let nx = s.touch_x * 2.0 - 1.0;
                            let ny = s.touch_y * 2.0 - 1.0;
                            let dot_pos = pos2(center.x + nx * radius, center.y + ny * radius);
                            painter.circle_filled(dot_pos, 6.0, palette.accent);
                        }

                        ui.add_space(spacing::S3);
                        ui.label(RichText::new("Buttons").strong().color(palette.text));
                        ui.add_space(spacing::S2);
                        let (click, home, app, vol_down, vol_up) = sample
                            .map_or((false, false, false, false, false), |s| {
                                (s.click, s.home, s.app, s.vol_down, s.vol_up)
                            });
                        ui.horizontal_wrapped(|ui| {
                            for (name, down) in [
                                ("Click", click),
                                ("Home", home),
                                ("App", app),
                                ("Vol −", vol_down),
                                ("Vol +", vol_up),
                            ] {
                                let fill = if down {
                                    palette.accent
                                } else {
                                    palette.surface_2
                                };
                                let fg = if down {
                                    palette.on_accent
                                } else {
                                    palette.text_dim
                                };
                                Frame::new()
                                    .fill(fill)
                                    .stroke(Stroke::new(1.0, palette.divider))
                                    .inner_margin(Margin::symmetric(
                                        spacing::S2 as i8,
                                        spacing::S1 as i8,
                                    ))
                                    .show(ui, |ui| {
                                        ui.label(
                                            RichText::new(name).size(type_scale::SMALL).color(fg),
                                        );
                                    });
                            }
                        });
                    });
                });

            ui.add_space(spacing::S3);

            // Right card: 3 Gyro bars + 3 Accel bars
            Frame::new()
                .fill(palette.surface)
                .stroke(Stroke::new(1.0, palette.divider))
                .inner_margin(Margin::same(spacing::S4 as i8))
                .show(ui, |ui| {
                    ui.vertical(|ui| {
                        ui.label(
                            RichText::new("Gyroscope (rad/s)")
                                .strong()
                                .color(palette.text),
                        );
                        ui.add_space(spacing::S2);
                        let gyro =
                            sample.map_or([0.0, 0.0, 0.0], |s| [s.gyro.x, s.gyro.y, s.gyro.z]);
                        for (axis, val) in [("X", gyro[0]), ("Y", gyro[1]), ("Z", gyro[2])] {
                            draw_sensor_bar(ui, axis, val, 10.0, palette.accent, palette);
                        }

                        ui.add_space(spacing::S4);
                        ui.label(
                            RichText::new("Accelerometer (m/s²)")
                                .strong()
                                .color(palette.text),
                        );
                        ui.add_space(spacing::S2);
                        let accel =
                            sample.map_or([0.0, 0.0, 0.0], |s| [s.accel.x, s.accel.y, s.accel.z]);
                        for (axis, val) in [("X", accel[0]), ("Y", accel[1]), ("Z", accel[2])] {
                            draw_sensor_bar(ui, axis, val, 40.0, palette.ok, palette);
                        }
                    });
                });
        });
    }

    fn render_radial_overlay_viewport(&self, ctx: &Context, status: &Status, palette: Palette) {
        if !status.radial_open {
            return;
        }
        let wayland = is_wayland_session();
        #[cfg(target_os = "macos")]
        let (cursor_pos, screen_size) = {
            let cur = crate::macos::current_cursor_location()
                .ok()
                .map(|p| (p.x as f32, p.y as f32));
            let (min_x, min_y, max_x, max_y) = crate::macos::union_display_bounds();
            let w = ((max_x - min_x) as f32).max(1440.0);
            let h = ((max_y - min_y) as f32).max(900.0);
            (cur, (w, h))
        };
        #[cfg(not(target_os = "macos"))]
        let (cursor_pos, screen_size) = (Some((760.0, 540.0)), (1440.0, 900.0));
        let origin = compute_radial_viewport_origin(wayland, cursor_pos, screen_size);
        let builder = ViewportBuilder::default()
            .with_title("Vitruvian Wand Radial")
            .with_decorations(false)
            .with_transparent(true)
            .with_always_on_top()
            .with_window_level(WindowLevel::AlwaysOnTop)
            .with_resizable(false)
            .with_inner_size([RADIAL_VIEWPORT_SIZE, RADIAL_VIEWPORT_SIZE])
            .with_position(pos2(origin.0, origin.1));

        let slots = self.config.radial_slots.clone();
        let highlighted = status.radial_selected_slot.map(usize::from);

        ctx.show_viewport_immediate(
            ViewportId::from_hash_of("wand_radial_overlay_viewport"),
            builder,
            move |ui, _class: ViewportClass| {
                CentralPanel::no_frame().show(ui, |ui| {
                    ui.vertical_centered(|ui| {
                        draw_radial_wheel(
                            ui,
                            &slots,
                            highlighted,
                            RADIAL_VIEWPORT_SIZE - 16.0,
                            palette,
                        );
                    });
                });
            },
        );
    }

    fn poll_chord_capture(&mut self, ui: &mut Ui) {
        let Some(target) = self.capturing_chord else {
            return;
        };

        let captured = ui.input(|i| {
            for ev in &i.events {
                if let egui::Event::Key {
                    key,
                    pressed: true,
                    modifiers,
                    ..
                } = ev
                {
                    if *key == Key::Escape && !modifiers.any() {
                        return Some(None);
                    }
                    if let Some(code_name) = egui_key_to_key_name(*key) {
                        return Some(Some(KeyChord {
                            key: code_name.to_owned(),
                            ctrl: modifiers.ctrl,
                            alt: modifiers.alt,
                            shift: modifiers.shift,
                            meta: modifiers.mac_cmd || modifiers.command,
                        }));
                    }
                }
            }
            None
        });

        if let Some(outcome) = captured {
            if let Some(chord) = outcome {
                match target {
                    ChordCaptureTarget::Binding(button, press) => {
                        let mode = self
                            .config
                            .bindings
                            .get(&(button, press))
                            .map_or(TriggerMode::Once, |b| b.trigger);
                        self.config
                            .bindings
                            .insert((button, press), Binding::new(Action::Key(chord), mode));
                    }
                    ChordCaptureTarget::RadialSlot(idx) => {
                        if let Some(slot) = self.config.radial_slots.get_mut(idx) {
                            slot.action = Some(Action::Key(chord));
                        }
                    }
                }
                self.mark_config_changed(Instant::now());
            }
            self.capturing_chord = None;
        }
    }
}

impl eframe::App for WandApp {
    fn ui(&mut self, ui: &mut Ui, _frame: &mut eframe::Frame) {
        let ctx = ui.ctx().clone();
        let pref = get_theme(&self.config);
        if self.theme_applied != Some(pref) {
            apply_theme(&ctx, pref);
            self.theme_applied = Some(pref);
        }

        // Closing the window hides it to the tray; Quit exits.
        if ctx.input(|i| i.viewport().close_requested()) && !self.quit_requested {
            ctx.send_viewport_cmd(ViewportCommand::CancelClose);
            ctx.send_viewport_cmd(ViewportCommand::Visible(false));
        }

        let status_snapshot = self.status.lock().map(|s| s.clone()).unwrap_or_default();

        self.handle_tray_events(&ctx, &status_snapshot);
        let _ = self.saver.poll_save(&self.config, Instant::now());

        let palette = active_palette(&ctx, pref);

        self.render_header(ui, &status_snapshot, palette);
        self.render_low_battery_banner(ui, &status_snapshot, palette);
        self.render_sidebar(ui, palette);

        let central_frame = Frame::new()
            .fill(palette.bg)
            .inner_margin(Margin::same(spacing::S4 as i8));

        CentralPanel::default().frame(central_frame).show(ui, |ui| {
            ScrollArea::vertical()
                .auto_shrink([false, false])
                .show(ui, |ui| match self.section {
                    SidebarSection::Connection => {
                        self.render_connection_section(ui, &status_snapshot, palette);
                    }
                    SidebarSection::Controls => {
                        self.render_controls_section(ui, palette);
                    }
                    SidebarSection::Bindings => {
                        self.render_bindings_section(ui, palette);
                    }
                    SidebarSection::RadialMenu => {
                        self.render_radial_section(ui, palette);
                    }
                    SidebarSection::TestMode => {
                        self.render_test_mode_section(ui, &status_snapshot, palette);
                    }
                });
        });

        self.render_radial_overlay_viewport(&ctx, &status_snapshot, palette);

        // Repaint at ~30 Hz while connected or scanning (or when debounced save is pending).
        if matches!(
            status_snapshot.connection,
            ConnectionState::Connected | ConnectionState::Scanning
        ) || self.saver.is_dirty()
        {
            ctx.request_repaint_after(Duration::from_millis(33));
        }
    }

    fn on_exit(&mut self) {
        let _ = self.saver.flush(&self.config);
        let _ = self.input_tx.send(InputCommand::ReleaseAll);
        let _ = self.ble_tx.send(BleCommand::Shutdown);
        let _ = self.input_tx.send(InputCommand::Shutdown);
    }
}

impl Drop for WandApp {
    fn drop(&mut self) {
        let _ = self.saver.flush(&self.config);
        let _ = self.input_tx.send(InputCommand::ReleaseAll);
        let _ = self.ble_tx.send(BleCommand::Shutdown);
        let _ = self.input_tx.send(InputCommand::Shutdown);
    }
}

/// Returns the one-line UI hint explaining the Hold delay trade-off when a button has both a
/// `Short` `Hold` binding and a `Long` or `Double` binding.
#[must_use]
pub fn hold_delay_hint(
    bindings: &vitruvian_wand_core::Bindings,
    button: Button,
    press: Press,
) -> Option<&'static str> {
    if press != Press::Short {
        return None;
    }
    let is_short_hold = bindings
        .get(&(button, Press::Short))
        .is_some_and(|b| b.trigger == TriggerMode::Hold);
    if !is_short_hold {
        return None;
    }
    if bindings.contains_key(&(button, Press::Long)) {
        Some("Long is also bound, so this clicks on release and cannot drag")
    } else if bindings.contains_key(&(button, Press::Double)) {
        Some("Double is also bound, so this clicks on release and cannot drag")
    } else {
        None
    }
}

fn button_label(button: Button) -> &'static str {
    match button {
        Button::Click => "Click",
        Button::App => "App",
        Button::Home => "Home",
        Button::VolUp => "Vol+",
        Button::VolDown => "Vol−",
        Button::Tap => "Tap",
    }
}

fn press_label(press: Press) -> &'static str {
    match press {
        Press::Short => "Short",
        Press::Long => "Long",
        Press::Double => "Double",
    }
}

fn trigger_mode_label(mode: TriggerMode) -> &'static str {
    match mode {
        TriggerMode::Once => "Once",
        TriggerMode::Hold => "Hold",
        TriggerMode::Toggle => "Toggle",
    }
}

fn render_binding_cell(
    ui: &mut Ui,
    button: Button,
    press: Press,
    slot: &mut Option<Binding>,
    hold_hint: Option<&'static str>,
    capturing_chord: &mut Option<ChordCaptureTarget>,
    palette: Palette,
) -> bool {
    let mut changed = false;
    ui.vertical(|ui| {
        ui.horizontal(|ui| {
            ui.spacing_mut().item_spacing.x = spacing::S1;
            ui.spacing_mut().button_padding = vec2(spacing::S2, spacing::S1);

            let mut action_opt = slot.as_ref().map(|b| b.action.clone());
            if render_action_combo(
                ui,
                Id::unique(("binding_action", button, press)),
                &mut action_opt,
                true,
                84.0,
            ) {
                match action_opt {
                    None => {
                        *slot = None;
                    }
                    Some(act) => {
                        let trigger = slot.as_ref().map_or(TriggerMode::Once, |b| b.trigger);
                        *slot = Some(Binding::new(act, trigger));
                    }
                }
                changed = true;
            }

            if let Some(binding) = slot.as_mut() {
                ComboBox::from_id_salt(("binding_mode", button, press))
                    .width(54.0)
                    .selected_text(
                        RichText::new(trigger_mode_label(binding.trigger)).size(type_scale::SMALL),
                    )
                    .show_ui(ui, |ui| {
                        for mode in [TriggerMode::Once, TriggerMode::Hold, TriggerMode::Toggle] {
                            if ui
                                .selectable_value(
                                    &mut binding.trigger,
                                    mode,
                                    trigger_mode_label(mode),
                                )
                                .changed()
                            {
                                changed = true;
                            }
                        }
                    });
            } else {
                ui.add_enabled_ui(false, |ui| {
                    let mut dummy = TriggerMode::Once;
                    ComboBox::from_id_salt(("binding_mode", button, press))
                        .width(54.0)
                        .selected_text(
                            RichText::new(trigger_mode_label(dummy)).size(type_scale::SMALL),
                        )
                        .show_ui(ui, |ui| {
                            ui.selectable_value(&mut dummy, TriggerMode::Once, "Once");
                        });
                });
            }
        });

        if let Some(hint) = hold_hint {
            let (rect, _) = ui.allocate_exact_size(vec2(130.0, 13.0), Sense::hover());
            ui.painter().text(
                rect.left_center(),
                Align2::LEFT_CENTER,
                hint,
                FontId::proportional(type_scale::LABEL),
                palette.warn,
            );
        }

        // Extra inline editor for Keyboard chord capture or LaunchApp target
        if let Some(binding) = slot.as_mut() {
            match &mut binding.action {
                Action::Key(chord) => {
                    let target = ChordCaptureTarget::Binding(button, press);
                    let is_capturing = *capturing_chord == Some(target);
                    let btn_text = if is_capturing {
                        "Press a key chord… (Esc cancels)".to_owned()
                    } else {
                        format!("Chord: {}", format_chord(chord))
                    };
                    if ui
                        .add(egui::Button::new(
                            RichText::new(btn_text).size(type_scale::SMALL).color(
                                if is_capturing {
                                    palette.accent_text
                                } else {
                                    palette.text_dim
                                },
                            ),
                        ))
                        .clicked()
                    {
                        *capturing_chord = Some(target);
                    }
                }
                Action::LaunchApp(app_target) => {
                    ui.horizontal(|ui| {
                        ui.label(RichText::new("App:").size(type_scale::SMALL));
                        if ui
                            .add(
                                egui::TextEdit::singleline(app_target)
                                    .desired_width(110.0)
                                    .hint_text("bundle id / name"),
                            )
                            .changed()
                        {
                            changed = true;
                        }
                    });
                }
                _ => {}
            }
        }
    });
    changed
}

fn grouped_action_catalog() -> Vec<(&'static str, Vec<(&'static str, Action)>)> {
    vec![
        (
            "Mouse",
            vec![
                ("Left click", Action::LeftClick),
                ("Right click", Action::RightClick),
                ("Mouse down", Action::MouseDown),
                ("Mouse up", Action::MouseUp),
            ],
        ),
        (
            "Scroll",
            vec![
                ("Scroll up", Action::Scroll { dx: 0.0, dy: 1.0 }),
                ("Scroll down", Action::Scroll { dx: 0.0, dy: -1.0 }),
                ("Scroll left", Action::Scroll { dx: -1.0, dy: 0.0 }),
                ("Scroll right", Action::Scroll { dx: 1.0, dy: 0.0 }),
            ],
        ),
        (
            "Media",
            vec![
                ("Play / Pause", Action::Media(MediaAction::PlayPause)),
                ("Next track", Action::Media(MediaAction::Next)),
                ("Prev track", Action::Media(MediaAction::Previous)),
            ],
        ),
        (
            "Volume",
            vec![
                ("Volume up", Action::Volume(VolumeAction::Up)),
                ("Volume down", Action::Volume(VolumeAction::Down)),
                ("Mute", Action::Volume(VolumeAction::Mute)),
            ],
        ),
        (
            "Brightness",
            vec![
                ("Brightness up", Action::Brightness(BrightnessAction::Up)),
                (
                    "Brightness down",
                    Action::Brightness(BrightnessAction::Down),
                ),
            ],
        ),
        (
            "Keyboard",
            vec![
                ("Key chord…", Action::Key(KeyChord::new("Space"))),
                ("Copy", Action::System(SystemAction::Copy)),
                ("Paste", Action::System(SystemAction::Paste)),
            ],
        ),
        (
            "System",
            vec![
                ("App switcher", Action::System(SystemAction::AppSwitcher)),
                (
                    "Mission Control",
                    Action::System(SystemAction::MissionControl),
                ),
                ("Show desktop", Action::System(SystemAction::ShowDesktop)),
                ("Back", Action::Nav(NavAction::Back)),
                ("Home", Action::Nav(NavAction::Home)),
            ],
        ),
        (
            "Vitruvian Wand",
            vec![
                ("Toggle gyro mode", Action::ToggleGyro),
                ("Recenter pointer", Action::Recenter),
                ("Radial menu", Action::RadialMenu),
            ],
        ),
        (
            "Apps",
            vec![(
                "Launch app…",
                Action::LaunchApp("com.apple.Safari".to_owned()),
            )],
        ),
    ]
}

fn action_summary_label(action: Option<&Action>) -> String {
    match action {
        None => "None".to_owned(),
        Some(Action::LeftClick) => "Left click".to_owned(),
        Some(Action::RightClick) => "Right click".to_owned(),
        Some(Action::MouseDown) => "Mouse down".to_owned(),
        Some(Action::MouseUp) => "Mouse up".to_owned(),
        Some(Action::Scroll { dx, dy }) => {
            if *dy > 0.0 {
                "Scroll up".to_owned()
            } else if *dy < 0.0 {
                "Scroll down".to_owned()
            } else if *dx < 0.0 {
                "Scroll left".to_owned()
            } else {
                "Scroll right".to_owned()
            }
        }
        Some(Action::Media(MediaAction::PlayPause)) => "Play / Pause".to_owned(),
        Some(Action::Media(MediaAction::Next)) => "Next track".to_owned(),
        Some(Action::Media(MediaAction::Previous)) => "Prev track".to_owned(),
        Some(Action::Volume(VolumeAction::Up)) => "Volume up".to_owned(),
        Some(Action::Volume(VolumeAction::Down)) => "Volume down".to_owned(),
        Some(Action::Volume(VolumeAction::Mute)) => "Mute".to_owned(),
        Some(Action::Brightness(BrightnessAction::Up)) => "Brightness up".to_owned(),
        Some(Action::Brightness(BrightnessAction::Down)) => "Brightness down".to_owned(),
        Some(Action::Key(chord)) => format!("Key ({})", format_chord(chord)),
        Some(Action::System(SystemAction::Copy)) => "Copy".to_owned(),
        Some(Action::System(SystemAction::Paste)) => "Paste".to_owned(),
        Some(Action::System(SystemAction::Cut)) => "Cut".to_owned(),
        Some(Action::System(SystemAction::Undo)) => "Undo".to_owned(),
        Some(Action::System(SystemAction::AppSwitcher)) => "App switcher".to_owned(),
        Some(Action::System(SystemAction::MissionControl)) => "Mission Control".to_owned(),
        Some(Action::System(SystemAction::ShowDesktop)) => "Show desktop".to_owned(),
        Some(Action::Nav(NavAction::Back)) => "Back".to_owned(),
        Some(Action::Nav(NavAction::Home)) => "Home".to_owned(),
        Some(Action::ToggleGyro) => "Toggle gyro".to_owned(),
        Some(Action::Recenter) => "Recenter pointer".to_owned(),
        Some(Action::RadialMenu) => "Radial menu".to_owned(),
        Some(Action::LaunchApp(app)) => format!("Launch: {app}"),
        Some(other) => format!("{other:?}"),
    }
}

fn render_action_combo(
    ui: &mut Ui,
    id: Id,
    current: &mut Option<Action>,
    allow_none: bool,
    width: f32,
) -> bool {
    let mut changed = false;
    let summary = action_summary_label(current.as_ref());
    ComboBox::from_id_salt(id)
        .width(width)
        .truncate()
        .selected_text(RichText::new(summary).size(type_scale::SMALL))
        .show_ui(ui, |ui| {
            if allow_none && ui.selectable_label(current.is_none(), "None").clicked() {
                *current = None;
                changed = true;
            }
            for (group_name, items) in grouped_action_catalog() {
                ui.separator();
                ui.label(RichText::new(group_name).size(type_scale::LABEL).strong());
                for (item_label, item_action) in items {
                    let is_same = current.as_ref() == Some(&item_action);
                    if ui.selectable_label(is_same, item_label).clicked() {
                        *current = Some(item_action);
                        changed = true;
                    }
                }
            }
        });
    changed
}

fn format_chord(chord: &KeyChord) -> String {
    let mut parts = Vec::new();
    if chord.ctrl {
        parts.push("Ctrl".to_owned());
    }
    if chord.alt {
        parts.push("Alt".to_owned());
    }
    if chord.shift {
        parts.push("Shift".to_owned());
    }
    if chord.meta {
        parts.push("Cmd".to_owned());
    }
    parts.push(chord.key.clone());
    parts.join("+")
}

fn draw_radial_wheel(
    ui: &mut Ui,
    slots: &[RadialSlot],
    highlighted: Option<usize>,
    diameter: f32,
    palette: Palette,
) {
    let (rect, _) = ui.allocate_exact_size(vec2(diameter, diameter), Sense::hover());
    let painter = ui.painter();
    let center = rect.center();
    let outer_r = diameter * 0.46;
    let inner_r = diameter * 0.16;

    painter.circle_filled(center, outer_r + 4.0, palette.surface_2);
    painter.circle_stroke(center, outer_r + 4.0, Stroke::new(1.5, palette.divider));

    let sector_angle = TAU / (RADIAL_SLOT_COUNT as f32);
    for idx in 0..RADIAL_SLOT_COUNT {
        // Slot 0 = Up (-FRAC_PI_2 in screen coords), clockwise.
        let center_angle = -FRAC_PI_2 + (idx as f32) * sector_angle;
        let start_angle = center_angle - sector_angle * 0.5;
        let is_hi = highlighted == Some(idx);

        let slot_color = slots
            .get(idx)
            .map_or(palette.accent, |s| resolve_slot_color(&s.color, palette));

        // Divider ray
        let ray_end = pos2(
            center.x + outer_r * start_angle.cos(),
            center.y + outer_r * start_angle.sin(),
        );
        let ray_start = pos2(
            center.x + inner_r * start_angle.cos(),
            center.y + inner_r * start_angle.sin(),
        );
        painter.line_segment([ray_start, ray_end], Stroke::new(1.0, palette.divider));

        // Badge + label at the midpoint of the wedge
        let label_r = (inner_r + outer_r) * 0.56;
        let badge_pos = pos2(
            center.x + label_r * center_angle.cos(),
            center.y + label_r * center_angle.sin(),
        );
        let badge_radius = if is_hi { 20.0 } else { 15.0 };
        painter.circle_filled(badge_pos, badge_radius, slot_color);
        if is_hi {
            painter.circle_stroke(
                badge_pos,
                badge_radius + 2.0,
                Stroke::new(2.0, palette.text),
            );
        }

        let label = slots.get(idx).map_or("", |s| s.label.as_str());
        painter.text(
            badge_pos,
            Align2::CENTER_CENTER,
            label,
            FontId::proportional(type_scale::LABEL),
            palette.on_accent,
        );
    }

    painter.circle_filled(center, inner_r, palette.bg);
    painter.circle_stroke(center, inner_r, Stroke::new(1.5, palette.divider));
}

fn draw_sensor_bar(
    ui: &mut Ui,
    axis: &str,
    value: f32,
    range: f32,
    fill_color: Color32,
    palette: Palette,
) {
    ui.horizontal(|ui| {
        ui.label(RichText::new(axis).monospace().strong());
        let (bar_rect, _) = ui.allocate_exact_size(vec2(180.0, 14.0), Sense::hover());
        let painter = ui.painter();
        painter.rect_filled(bar_rect, CornerRadius::ZERO, palette.surface_2);
        painter.rect_stroke(
            bar_rect,
            CornerRadius::ZERO,
            Stroke::new(1.0, palette.divider),
            StrokeKind::Inside,
        );
        let mid_x = bar_rect.center().x;
        painter.line_segment(
            [pos2(mid_x, bar_rect.min.y), pos2(mid_x, bar_rect.max.y)],
            Stroke::new(1.0, palette.divider),
        );
        let norm = (value / range).clamp(-1.0, 1.0);
        let half_w = bar_rect.width() * 0.5;
        let active_rect = if norm >= 0.0 {
            Rect::from_min_max(
                pos2(mid_x, bar_rect.min.y + 2.0),
                pos2(mid_x + norm * half_w, bar_rect.max.y - 2.0),
            )
        } else {
            Rect::from_min_max(
                pos2(mid_x + norm * half_w, bar_rect.min.y + 2.0),
                pos2(mid_x, bar_rect.max.y - 2.0),
            )
        };
        painter.rect_filled(active_rect, CornerRadius::ZERO, fill_color);
        ui.label(
            RichText::new(format!("{value:+6.2}"))
                .monospace()
                .size(type_scale::SMALL)
                .color(palette.text_dim),
        );
    });
}

fn egui_key_to_key_name(key: Key) -> Option<&'static str> {
    Some(match key {
        Key::A => "a",
        Key::B => "b",
        Key::C => "c",
        Key::D => "d",
        Key::E => "e",
        Key::F => "f",
        Key::G => "g",
        Key::H => "h",
        Key::I => "i",
        Key::J => "j",
        Key::K => "k",
        Key::L => "l",
        Key::M => "m",
        Key::N => "n",
        Key::O => "o",
        Key::P => "p",
        Key::Q => "q",
        Key::R => "r",
        Key::S => "s",
        Key::T => "t",
        Key::U => "u",
        Key::V => "v",
        Key::W => "w",
        Key::X => "x",
        Key::Y => "y",
        Key::Z => "z",
        Key::Num0 => "0",
        Key::Num1 => "1",
        Key::Num2 => "2",
        Key::Num3 => "3",
        Key::Num4 => "4",
        Key::Num5 => "5",
        Key::Num6 => "6",
        Key::Num7 => "7",
        Key::Num8 => "8",
        Key::Num9 => "9",
        Key::Escape => "Escape",
        Key::Enter => "Return",
        Key::Tab => "Tab",
        Key::Space => "Space",
        Key::Backspace => "Backspace",
        Key::Delete => "Delete",
        Key::ArrowUp => "Up",
        Key::ArrowDown => "Down",
        Key::ArrowLeft => "Left",
        Key::ArrowRight => "Right",
        Key::Home => "Home",
        Key::End => "End",
        Key::PageUp => "PageUp",
        Key::PageDown => "PageDown",
        Key::F1 => "F1",
        Key::F2 => "F2",
        Key::F3 => "F3",
        Key::F4 => "F4",
        Key::F5 => "F5",
        Key::F6 => "F6",
        Key::F7 => "F7",
        Key::F8 => "F8",
        Key::F9 => "F9",
        Key::F10 => "F10",
        Key::F11 => "F11",
        Key::F12 => "F12",
        _ => return None,
    })
}
