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

//! Linux `evdev` `uinput` virtual mouse + keyboard injector, Linux `<linux/input-event-codes.h>`
//! key mapping table, and `/dev/uinput` permission diagnostics.

use std::fs::OpenOptions;
use std::path::Path;
use wand_core::{
    Action, BrightnessAction, Direction, MediaAction, NavAction, SystemAction, VolumeAction,
};

/// Path to the Linux uinput character device.
pub const UINPUT_DEVICE_PATH: &str = "/dev/uinput";

/// Documentation path referenced when `/dev/uinput` is not writable.
pub const LINUX_SETUP_DOC_PATH: &str = "docs/setup-linux.md";

// Standard Linux `<linux/input-event-codes.h>` keycode constants (matching `evdev::KeyCode`).
pub const KEY_ESC: u16 = 1;
pub const KEY_1: u16 = 2;
pub const KEY_2: u16 = 3;
pub const KEY_3: u16 = 4;
pub const KEY_4: u16 = 5;
pub const KEY_5: u16 = 6;
pub const KEY_6: u16 = 7;
pub const KEY_7: u16 = 8;
pub const KEY_8: u16 = 9;
pub const KEY_9: u16 = 10;
pub const KEY_0: u16 = 11;
pub const KEY_MINUS: u16 = 12;
pub const KEY_EQUAL: u16 = 13;
pub const KEY_BACKSPACE: u16 = 14;
pub const KEY_TAB: u16 = 15;
pub const KEY_Q: u16 = 16;
pub const KEY_W: u16 = 17;
pub const KEY_E: u16 = 18;
pub const KEY_R: u16 = 19;
pub const KEY_T: u16 = 20;
pub const KEY_Y: u16 = 21;
pub const KEY_U: u16 = 22;
pub const KEY_I: u16 = 23;
pub const KEY_O: u16 = 24;
pub const KEY_P: u16 = 25;
pub const KEY_LEFTBRACE: u16 = 26;
pub const KEY_RIGHTBRACE: u16 = 27;
pub const KEY_ENTER: u16 = 28;
pub const KEY_LEFTCTRL: u16 = 29;
pub const KEY_A: u16 = 30;
pub const KEY_S: u16 = 31;
pub const KEY_D: u16 = 32;
pub const KEY_F: u16 = 33;
pub const KEY_G: u16 = 34;
pub const KEY_H: u16 = 35;
pub const KEY_J: u16 = 36;
pub const KEY_K: u16 = 37;
pub const KEY_L: u16 = 38;
pub const KEY_SEMICOLON: u16 = 39;
pub const KEY_APOSTROPHE: u16 = 40;
pub const KEY_GRAVE: u16 = 41;
pub const KEY_LEFTSHIFT: u16 = 42;
pub const KEY_BACKSLASH: u16 = 43;
pub const KEY_Z: u16 = 44;
pub const KEY_X: u16 = 45;
pub const KEY_C: u16 = 46;
pub const KEY_V: u16 = 47;
pub const KEY_B: u16 = 48;
pub const KEY_N: u16 = 49;
pub const KEY_M: u16 = 50;
pub const KEY_COMMA: u16 = 51;
pub const KEY_DOT: u16 = 52;
pub const KEY_SLASH: u16 = 53;
pub const KEY_LEFTALT: u16 = 56;
pub const KEY_SPACE: u16 = 57;
pub const KEY_F1: u16 = 59;
pub const KEY_F2: u16 = 60;
pub const KEY_F3: u16 = 61;
pub const KEY_F4: u16 = 62;
pub const KEY_F5: u16 = 63;
pub const KEY_F6: u16 = 64;
pub const KEY_F7: u16 = 65;
pub const KEY_F8: u16 = 66;
pub const KEY_F9: u16 = 67;
pub const KEY_F10: u16 = 68;
pub const KEY_F11: u16 = 87;
pub const KEY_F12: u16 = 88;
pub const KEY_HOME: u16 = 102;
pub const KEY_UP: u16 = 103;
pub const KEY_PAGEUP: u16 = 104;
pub const KEY_LEFT: u16 = 105;
pub const KEY_RIGHT: u16 = 106;
pub const KEY_END: u16 = 107;
pub const KEY_DOWN: u16 = 108;
pub const KEY_PAGEDOWN: u16 = 109;
pub const KEY_DELETE: u16 = 111;
pub const KEY_MUTE: u16 = 113;
pub const KEY_VOLUMEDOWN: u16 = 114;
pub const KEY_VOLUMEUP: u16 = 115;
pub const KEY_LEFTMETA: u16 = 125;
pub const KEY_BACK: u16 = 158;
pub const KEY_NEXTSONG: u16 = 163;
pub const KEY_PLAYPAUSE: u16 = 164;
pub const KEY_PREVIOUSSONG: u16 = 165;
pub const KEY_HOMEPAGE: u16 = 172;
pub const KEY_BRIGHTNESSDOWN: u16 = 224;
pub const KEY_BRIGHTNESSUP: u16 = 225;
pub const BTN_LEFT: u16 = 0x110;
pub const BTN_RIGHT: u16 = 0x111;
pub const BTN_MIDDLE: u16 = 0x112;

/// Resolved Linux evdev key chord (`keycode` + optional modifier keycodes).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LinuxKeySpec {
    /// Primary `KEY_*` code from `<linux/input-event-codes.h>`.
    pub keycode: u16,
    /// `KEY_LEFTCTRL` held.
    pub ctrl: bool,
    /// `KEY_LEFTALT` held.
    pub alt: bool,
    /// `KEY_LEFTSHIFT` held.
    pub shift: bool,
    /// `KEY_LEFTMETA` held.
    pub meta: bool,
}

impl LinuxKeySpec {
    /// Creates a plain unmodified Linux key spec.
    pub const fn plain(keycode: u16) -> Self {
        Self {
            keycode,
            ctrl: false,
            alt: false,
            shift: false,
            meta: false,
        }
    }
}

/// Maps a key identifier string from [`wand_core::KeyChord::key`] to a Linux `KEY_*` code.
pub fn linux_keycode_for_key(key: &str) -> Option<u16> {
    match key.trim().to_ascii_lowercase().as_str() {
        "a" => Some(KEY_A),
        "b" => Some(KEY_B),
        "c" => Some(KEY_C),
        "d" => Some(KEY_D),
        "e" => Some(KEY_E),
        "f" => Some(KEY_F),
        "g" => Some(KEY_G),
        "h" => Some(KEY_H),
        "i" => Some(KEY_I),
        "j" => Some(KEY_J),
        "k" => Some(KEY_K),
        "l" => Some(KEY_L),
        "m" => Some(KEY_M),
        "n" => Some(KEY_N),
        "o" => Some(KEY_O),
        "p" => Some(KEY_P),
        "q" => Some(KEY_Q),
        "r" => Some(KEY_R),
        "s" => Some(KEY_S),
        "t" => Some(KEY_T),
        "u" => Some(KEY_U),
        "v" => Some(KEY_V),
        "w" => Some(KEY_W),
        "x" => Some(KEY_X),
        "y" => Some(KEY_Y),
        "z" => Some(KEY_Z),
        "0" => Some(KEY_0),
        "1" => Some(KEY_1),
        "2" => Some(KEY_2),
        "3" => Some(KEY_3),
        "4" => Some(KEY_4),
        "5" => Some(KEY_5),
        "6" => Some(KEY_6),
        "7" => Some(KEY_7),
        "8" => Some(KEY_8),
        "9" => Some(KEY_9),
        "return" | "enter" => Some(KEY_ENTER),
        "space" | " " => Some(KEY_SPACE),
        "tab" => Some(KEY_TAB),
        "backspace" => Some(KEY_BACKSPACE),
        "delete" | "forwarddelete" => Some(KEY_DELETE),
        "escape" | "esc" => Some(KEY_ESC),
        "up" | "arrowup" => Some(KEY_UP),
        "down" | "arrowdown" => Some(KEY_DOWN),
        "left" | "arrowleft" => Some(KEY_LEFT),
        "right" | "arrowright" => Some(KEY_RIGHT),
        "home" => Some(KEY_HOME),
        "end" => Some(KEY_END),
        "pageup" => Some(KEY_PAGEUP),
        "pagedown" => Some(KEY_PAGEDOWN),
        "f1" => Some(KEY_F1),
        "f2" => Some(KEY_F2),
        "f3" => Some(KEY_F3),
        "f4" => Some(KEY_F4),
        "f5" => Some(KEY_F5),
        "f6" => Some(KEY_F6),
        "f7" => Some(KEY_F7),
        "f8" => Some(KEY_F8),
        "f9" => Some(KEY_F9),
        "f10" => Some(KEY_F10),
        "f11" => Some(KEY_F11),
        "f12" => Some(KEY_F12),
        "-" | "minus" => Some(KEY_MINUS),
        "=" | "equal" | "equals" => Some(KEY_EQUAL),
        "[" | "leftbracket" => Some(KEY_LEFTBRACE),
        "]" | "rightbracket" => Some(KEY_RIGHTBRACE),
        "\\" | "backslash" => Some(KEY_BACKSLASH),
        ";" | "semicolon" => Some(KEY_SEMICOLON),
        "'" | "quote" => Some(KEY_APOSTROPHE),
        "," | "comma" => Some(KEY_COMMA),
        "." | "period" => Some(KEY_DOT),
        "/" | "slash" => Some(KEY_SLASH),
        "`" | "grave" => Some(KEY_GRAVE),
        _ => None,
    }
}

/// Maps any key-based [`Action`] (`Key`, `Media`, `Volume`, `Brightness`, `System`, `Nav`, `DPad`)
/// to its Linux [`LinuxKeySpec`]:
/// - `System(Copy)` -> `Ctrl+C`
/// - `System(Paste)` -> `Ctrl+V`
/// - `System(Cut)` -> `Ctrl+X`
/// - `System(Undo)` -> `Ctrl+Z`
/// - `System(AppSwitcher)` -> `Alt+Tab`
pub fn linux_action_key_spec(action: &Action) -> Option<LinuxKeySpec> {
    match action {
        Action::Key(chord) => linux_keycode_for_key(&chord.key).map(|keycode| LinuxKeySpec {
            keycode,
            ctrl: chord.ctrl,
            alt: chord.alt,
            shift: chord.shift,
            meta: chord.meta,
        }),
        Action::Media(MediaAction::PlayPause) => Some(LinuxKeySpec::plain(KEY_PLAYPAUSE)),
        Action::Media(MediaAction::Next) => Some(LinuxKeySpec::plain(KEY_NEXTSONG)),
        Action::Media(MediaAction::Previous) => Some(LinuxKeySpec::plain(KEY_PREVIOUSSONG)),
        Action::Volume(VolumeAction::Up) => Some(LinuxKeySpec::plain(KEY_VOLUMEUP)),
        Action::Volume(VolumeAction::Down) => Some(LinuxKeySpec::plain(KEY_VOLUMEDOWN)),
        Action::Volume(VolumeAction::Mute) => Some(LinuxKeySpec::plain(KEY_MUTE)),
        Action::Brightness(BrightnessAction::Up) => Some(LinuxKeySpec::plain(KEY_BRIGHTNESSUP)),
        Action::Brightness(BrightnessAction::Down) => Some(LinuxKeySpec::plain(KEY_BRIGHTNESSDOWN)),
        Action::System(SystemAction::Copy) => Some(LinuxKeySpec {
            keycode: KEY_C,
            ctrl: true,
            alt: false,
            shift: false,
            meta: false,
        }),
        Action::System(SystemAction::Paste) => Some(LinuxKeySpec {
            keycode: KEY_V,
            ctrl: true,
            alt: false,
            shift: false,
            meta: false,
        }),
        Action::System(SystemAction::Cut) => Some(LinuxKeySpec {
            keycode: KEY_X,
            ctrl: true,
            alt: false,
            shift: false,
            meta: false,
        }),
        Action::System(SystemAction::Undo) => Some(LinuxKeySpec {
            keycode: KEY_Z,
            ctrl: true,
            alt: false,
            shift: false,
            meta: false,
        }),
        Action::System(SystemAction::AppSwitcher) => Some(LinuxKeySpec {
            keycode: KEY_TAB,
            ctrl: false,
            alt: true,
            shift: false,
            meta: false,
        }),
        Action::System(SystemAction::MissionControl) => Some(LinuxKeySpec::plain(KEY_LEFTMETA)),
        Action::System(SystemAction::ShowDesktop) => Some(LinuxKeySpec {
            keycode: KEY_D,
            ctrl: false,
            alt: false,
            shift: false,
            meta: true,
        }),
        Action::Nav(NavAction::Back) => Some(LinuxKeySpec::plain(KEY_BACK)),
        Action::Nav(NavAction::Home) => Some(LinuxKeySpec::plain(KEY_HOMEPAGE)),
        Action::Nav(NavAction::Recents) => Some(LinuxKeySpec::plain(KEY_LEFTMETA)),
        Action::Nav(NavAction::Notifications) | Action::Nav(NavAction::QuickSettings) => {
            Some(LinuxKeySpec {
                keycode: KEY_V,
                ctrl: false,
                alt: false,
                shift: false,
                meta: true,
            })
        }
        Action::DPad(Direction::Up) => Some(LinuxKeySpec::plain(KEY_UP)),
        Action::DPad(Direction::Down) => Some(LinuxKeySpec::plain(KEY_DOWN)),
        Action::DPad(Direction::Left) => Some(LinuxKeySpec::plain(KEY_LEFT)),
        Action::DPad(Direction::Right) => Some(LinuxKeySpec::plain(KEY_RIGHT)),
        Action::DPad(Direction::Center) => Some(LinuxKeySpec::plain(KEY_ENTER)),
        _ => None,
    }
}

/// All raw evdev key and button codes registered on the Linux uinput virtual device.
pub const ALL_SUPPORTED_LINUX_KEYCODES: &[u16] = &[
    BTN_LEFT,
    BTN_RIGHT,
    BTN_MIDDLE,
    KEY_ESC,
    KEY_1,
    KEY_2,
    KEY_3,
    KEY_4,
    KEY_5,
    KEY_6,
    KEY_7,
    KEY_8,
    KEY_9,
    KEY_0,
    KEY_MINUS,
    KEY_EQUAL,
    KEY_BACKSPACE,
    KEY_TAB,
    KEY_Q,
    KEY_W,
    KEY_E,
    KEY_R,
    KEY_T,
    KEY_Y,
    KEY_U,
    KEY_I,
    KEY_O,
    KEY_P,
    KEY_LEFTBRACE,
    KEY_RIGHTBRACE,
    KEY_ENTER,
    KEY_LEFTCTRL,
    KEY_A,
    KEY_S,
    KEY_D,
    KEY_F,
    KEY_G,
    KEY_H,
    KEY_J,
    KEY_K,
    KEY_L,
    KEY_SEMICOLON,
    KEY_APOSTROPHE,
    KEY_GRAVE,
    KEY_LEFTSHIFT,
    KEY_BACKSLASH,
    KEY_Z,
    KEY_X,
    KEY_C,
    KEY_V,
    KEY_B,
    KEY_N,
    KEY_M,
    KEY_COMMA,
    KEY_DOT,
    KEY_SLASH,
    KEY_LEFTALT,
    KEY_SPACE,
    KEY_F1,
    KEY_F2,
    KEY_F3,
    KEY_F4,
    KEY_F5,
    KEY_F6,
    KEY_F7,
    KEY_F8,
    KEY_F9,
    KEY_F10,
    KEY_F11,
    KEY_F12,
    KEY_HOME,
    KEY_UP,
    KEY_PAGEUP,
    KEY_LEFT,
    KEY_RIGHT,
    KEY_END,
    KEY_DOWN,
    KEY_PAGEDOWN,
    KEY_DELETE,
    KEY_MUTE,
    KEY_VOLUMEDOWN,
    KEY_VOLUMEUP,
    KEY_LEFTMETA,
    KEY_BACK,
    KEY_NEXTSONG,
    KEY_PLAYPAUSE,
    KEY_PREVIOUSSONG,
    KEY_HOMEPAGE,
    KEY_BRIGHTNESSDOWN,
    KEY_BRIGHTNESSUP,
];

/// Returns `true` if `path` (typically `/dev/uinput`) can be opened for reading and writing.
pub fn is_uinput_writable_at(path: &Path) -> bool {
    OpenOptions::new().read(true).write(true).open(path).is_ok()
}

/// Returns `true` if `/dev/uinput` is writable by the current user.
pub fn is_uinput_writable() -> bool {
    is_uinput_writable_at(Path::new(UINPUT_DEVICE_PATH))
}

/// Formats a clear diagnostic error pointing at `docs/setup-linux.md` when `/dev/uinput` is not writable.
pub fn uinput_permission_error_message() -> String {
    format!(
        "Cannot write to {UINPUT_DEVICE_PATH}: permission denied or module not loaded. \
         Configure the udev rule and 'input' group as documented in {LINUX_SETUP_DOC_PATH}."
    )
}

/// Converts absolute `Action::PointTo { x, y }` coordinates (in screen-width units) into integer
/// relative pixel deltas `(ix, iy)` for Linux `uinput` (`REL_X` / `REL_Y`).
///
/// Difference from macOS: on macOS, CoreGraphics can read the cursor position and warp directly to
/// `display_centre + (x, y) * display_width`. On Linux, `uinput` only emits relative motion and
/// Wayland compositors do not expose global cursor coordinates to clients. Therefore, after
/// entering gyro mode or `Recenter`, Linux treats the current cursor position as the centre `(0, 0)`
/// (no initial jump to the physical display centre) and converts each `PointTo` into a relative
/// delta from the previous `PointTo` scaled by `screen_width_px`.
#[derive(Debug, Clone)]
pub struct LinuxPointToConverter {
    screen_width_px: u64,
    prev_point: (f32, f32),
    rem_x: f32,
    rem_y: f32,
}

impl Default for LinuxPointToConverter {
    fn default() -> Self {
        Self::new(wand_core::RANGE_SCREEN_WIDTH_PX.default)
    }
}

impl LinuxPointToConverter {
    /// Creates a new [`LinuxPointToConverter`] with the given `screen_width_px`.
    pub fn new(screen_width_px: u64) -> Self {
        Self {
            screen_width_px: wand_core::RANGE_SCREEN_WIDTH_PX.clamp(screen_width_px),
            prev_point: (0.0, 0.0),
            rem_x: 0.0,
            rem_y: 0.0,
        }
    }

    /// Updates `screen_width_px` (clamped to [`wand_core::RANGE_SCREEN_WIDTH_PX`]).
    pub fn set_screen_width_px(&mut self, screen_width_px: u64) {
        self.screen_width_px = wand_core::RANGE_SCREEN_WIDTH_PX.clamp(screen_width_px);
    }

    /// Returns the configured `screen_width_px`.
    pub const fn screen_width_px(&self) -> u64 {
        self.screen_width_px
    }

    /// Resets the reference point back to `(0.0, 0.0)` without moving the cursor (treating the
    /// current cursor position as the new centre on Wayland/Linux).
    pub fn recenter(&mut self) {
        self.prev_point = (0.0, 0.0);
        self.rem_x = 0.0;
        self.rem_y = 0.0;
    }

    /// Converts the next `PointTo { x, y }` into an integer `(dx_px, dy_px)` step, carrying
    /// sub-pixel remainders across calls.
    pub fn step(&mut self, x: f32, y: f32) -> (i32, i32) {
        let (prev_x, prev_y) = self.prev_point;
        self.prev_point = (x, y);
        let width = self.screen_width_px as f32;
        let total_x = (x - prev_x) * width + self.rem_x;
        let total_y = (y - prev_y) * width + self.rem_y;
        let ix = total_x.trunc() as i32;
        let iy = total_y.trunc() as i32;
        self.rem_x = total_x - ix as f32;
        self.rem_y = total_y - iy as f32;
        (ix, iy)
    }
}

#[cfg(target_os = "linux")]
mod imp {
    use super::*;
    use crate::injector::{scale_move_delta, scale_scroll_pixels_accum, Injector, InjectorError};
    use crate::launch::launch_app;
    use evdev::uinput::VirtualDevice;
    use evdev::{AttributeSet, EventType, InputEvent, KeyCode, RelativeAxisCode};

    /// Linux `uinput` virtual pointer + keyboard injector.
    pub struct LinuxInjector {
        device: VirtualDevice,
        rem_x: f32,
        rem_y: f32,
        scroll_rem_x: f32,
        scroll_rem_y: f32,
        point_to: LinuxPointToConverter,
    }

    impl LinuxInjector {
        /// Creates and registers a single `uinput` virtual device with relative axes,
        /// mouse buttons, keyboard keys, media transport keys, volume keys, and brightness keys.
        pub fn new() -> Result<Self, InjectorError> {
            if !is_uinput_writable() {
                return Err(InjectorError(uinput_permission_error_message()));
            }

            let mut axes = AttributeSet::<RelativeAxisCode>::new();
            axes.insert(RelativeAxisCode::REL_X);
            axes.insert(RelativeAxisCode::REL_Y);
            axes.insert(RelativeAxisCode::REL_WHEEL);
            axes.insert(RelativeAxisCode::REL_HWHEEL);
            axes.insert(RelativeAxisCode::REL_WHEEL_HI_RES);
            axes.insert(RelativeAxisCode::REL_HWHEEL_HI_RES);

            let mut keys = AttributeSet::<KeyCode>::new();
            for &code in ALL_SUPPORTED_LINUX_KEYCODES {
                keys.insert(KeyCode(code));
            }

            let device = VirtualDevice::builder()
                .map_err(|e| InjectorError(format!("{}: {e}", uinput_permission_error_message())))?
                .name("Wand Virtual Air Mouse")
                .with_relative_axes(&axes)
                .map_err(|e| InjectorError(format!("uinput with_relative_axes failed: {e}")))?
                .with_keys(&keys)
                .map_err(|e| InjectorError(format!("uinput with_keys failed: {e}")))?
                .build()
                .map_err(|e| InjectorError(format!("uinput device build failed: {e}")))?;

            Ok(Self {
                device,
                rem_x: 0.0,
                rem_y: 0.0,
                scroll_rem_x: 0.0,
                scroll_rem_y: 0.0,
                point_to: LinuxPointToConverter::default(),
            })
        }

        fn emit_key(&mut self, code: u16, pressed: bool) -> Result<(), InjectorError> {
            let ev = InputEvent::new(EventType::KEY.0, code, if pressed { 1 } else { 0 });
            self.device
                .emit(&[ev])
                .map_err(|e| InjectorError(format!("uinput key emit failed: {e}")))
        }

        fn emit_spec(&mut self, spec: &LinuxKeySpec) -> Result<(), InjectorError> {
            let mut mods = Vec::with_capacity(4);
            if spec.ctrl {
                mods.push(KEY_LEFTCTRL);
            }
            if spec.alt {
                mods.push(KEY_LEFTALT);
            }
            if spec.shift {
                mods.push(KEY_LEFTSHIFT);
            }
            if spec.meta {
                mods.push(KEY_LEFTMETA);
            }

            for &m in &mods {
                self.emit_key(m, true)?;
            }
            self.emit_key(spec.keycode, true)?;
            self.emit_key(spec.keycode, false)?;
            for &m in mods.iter().rev() {
                self.emit_key(m, false)?;
            }
            Ok(())
        }
    }

    impl Injector for LinuxInjector {
        fn set_screen_width_px(&mut self, width_px: u64) {
            self.point_to.set_screen_width_px(width_px);
        }

        fn apply(&mut self, action: &Action) -> Result<(), InjectorError> {
            match action {
                Action::Move { dx, dy } => {
                    let (px_dx, px_dy) = scale_move_delta(*dx, *dy);
                    let total_x = px_dx + self.rem_x;
                    let total_y = px_dy + self.rem_y;
                    let ix = total_x.trunc() as i32;
                    let iy = total_y.trunc() as i32;
                    self.rem_x = total_x - ix as f32;
                    self.rem_y = total_y - iy as f32;
                    if ix == 0 && iy == 0 {
                        return Ok(());
                    }
                    let evs = [
                        InputEvent::new(EventType::RELATIVE.0, RelativeAxisCode::REL_X.0, ix),
                        InputEvent::new(EventType::RELATIVE.0, RelativeAxisCode::REL_Y.0, iy),
                    ];
                    self.device
                        .emit(&evs)
                        .map_err(|e| InjectorError(format!("uinput move emit failed: {e}")))
                }
                Action::PointTo { x, y } => {
                    let (ix, iy) = self.point_to.step(*x, *y);
                    if ix == 0 && iy == 0 {
                        return Ok(());
                    }
                    let evs = [
                        InputEvent::new(EventType::RELATIVE.0, RelativeAxisCode::REL_X.0, ix),
                        InputEvent::new(EventType::RELATIVE.0, RelativeAxisCode::REL_Y.0, iy),
                    ];
                    self.device
                        .emit(&evs)
                        .map_err(|e| InjectorError(format!("uinput point_to emit failed: {e}")))
                }
                Action::MouseDown => self.emit_key(BTN_LEFT, true),
                Action::MouseUp => self.emit_key(BTN_LEFT, false),
                Action::LeftClick => {
                    self.emit_key(BTN_LEFT, true)?;
                    self.emit_key(BTN_LEFT, false)
                }
                Action::RightClick => {
                    self.emit_key(BTN_RIGHT, true)?;
                    self.emit_key(BTN_RIGHT, false)
                }
                Action::Scroll { dx, dy } => {
                    let (px_dx, px_dy) = scale_scroll_pixels_accum(
                        *dx,
                        *dy,
                        &mut self.scroll_rem_x,
                        &mut self.scroll_rem_y,
                    );
                    let mut evs = Vec::with_capacity(4);
                    if px_dy != 0 {
                        evs.push(InputEvent::new(
                            EventType::RELATIVE.0,
                            RelativeAxisCode::REL_WHEEL_HI_RES.0,
                            px_dy * 5,
                        ));
                        let detents = (px_dy / 12).clamp(-10, 10);
                        if detents != 0 {
                            evs.push(InputEvent::new(
                                EventType::RELATIVE.0,
                                RelativeAxisCode::REL_WHEEL.0,
                                detents,
                            ));
                        }
                    }
                    if px_dx != 0 {
                        evs.push(InputEvent::new(
                            EventType::RELATIVE.0,
                            RelativeAxisCode::REL_HWHEEL_HI_RES.0,
                            px_dx * 5,
                        ));
                        let detents = (px_dx / 12).clamp(-10, 10);
                        if detents != 0 {
                            evs.push(InputEvent::new(
                                EventType::RELATIVE.0,
                                RelativeAxisCode::REL_HWHEEL.0,
                                detents,
                            ));
                        }
                    }
                    if evs.is_empty() {
                        Ok(())
                    } else {
                        self.device
                            .emit(&evs)
                            .map_err(|e| InjectorError(format!("uinput scroll emit failed: {e}")))
                    }
                }
                Action::LaunchApp(app) => launch_app(app),
                Action::ToggleGyro | Action::Recenter => {
                    self.point_to.recenter();
                    Ok(())
                }
                Action::RadialMenu => Ok(()),
                Action::ScreenOff | Action::Assistant | Action::VoiceTyping => Ok(()),
                other => {
                    if let Some(spec) = linux_action_key_spec(other) {
                        self.emit_spec(&spec)
                    } else {
                        Err(InjectorError(format!(
                            "unmapped Linux key action: {other:?}"
                        )))
                    }
                }
            }
        }
    }
}

#[cfg(target_os = "linux")]
pub use imp::LinuxInjector;
