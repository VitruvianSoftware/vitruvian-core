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

//! macOS event injection (`CoreGraphics` + `AppKit` `NSSystemDefined` media/brightness keys),
//! virtual keycode mapping table, per-display union clamping, and Accessibility permission helpers.

use crate::injector::{Injector, InjectorError, scale_move_delta, scale_scroll_pixels_accum};
use crate::launch::launch_app;
use std::process::Command;
use wand_core::{
    Action, BrightnessAction, Direction, KeyChord, MediaAction, NavAction, SystemAction,
    VolumeAction,
};

/// Deep-link URL to the macOS System Settings -> Privacy & Security -> Accessibility pane.
pub const MACOS_ACCESSIBILITY_SETTINGS_URL: &str =
    "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility";

// Carbon / HIToolbox ANSI virtual keycodes (`<Carbon/HIToolbox/Events.h>`).
pub const VK_ANSI_A: u16 = 0x00;
pub const VK_ANSI_S: u16 = 0x01;
pub const VK_ANSI_D: u16 = 0x02;
pub const VK_ANSI_F: u16 = 0x03;
pub const VK_ANSI_H: u16 = 0x04;
pub const VK_ANSI_G: u16 = 0x05;
pub const VK_ANSI_Z: u16 = 0x06;
pub const VK_ANSI_X: u16 = 0x07;
pub const VK_ANSI_C: u16 = 0x08;
pub const VK_ANSI_V: u16 = 0x09;
pub const VK_ANSI_B: u16 = 0x0B;
pub const VK_ANSI_Q: u16 = 0x0C;
pub const VK_ANSI_W: u16 = 0x0D;
pub const VK_ANSI_E: u16 = 0x0E;
pub const VK_ANSI_R: u16 = 0x0F;
pub const VK_ANSI_Y: u16 = 0x10;
pub const VK_ANSI_T: u16 = 0x11;
pub const VK_ANSI_1: u16 = 0x12;
pub const VK_ANSI_2: u16 = 0x13;
pub const VK_ANSI_3: u16 = 0x14;
pub const VK_ANSI_4: u16 = 0x15;
pub const VK_ANSI_6: u16 = 0x16;
pub const VK_ANSI_5: u16 = 0x17;
pub const VK_ANSI_EQUAL: u16 = 0x18;
pub const VK_ANSI_9: u16 = 0x19;
pub const VK_ANSI_7: u16 = 0x1A;
pub const VK_ANSI_MINUS: u16 = 0x1B;
pub const VK_ANSI_8: u16 = 0x1C;
pub const VK_ANSI_0: u16 = 0x1D;
pub const VK_ANSI_RIGHT_BRACKET: u16 = 0x1E;
pub const VK_ANSI_O: u16 = 0x1F;
pub const VK_ANSI_U: u16 = 0x20;
pub const VK_ANSI_LEFT_BRACKET: u16 = 0x21;
pub const VK_ANSI_I: u16 = 0x22;
pub const VK_ANSI_P: u16 = 0x23;
pub const VK_RETURN: u16 = 0x24;
pub const VK_ANSI_L: u16 = 0x25;
pub const VK_ANSI_J: u16 = 0x26;
pub const VK_ANSI_QUOTE: u16 = 0x27;
pub const VK_ANSI_K: u16 = 0x28;
pub const VK_ANSI_SEMICOLON: u16 = 0x29;
pub const VK_ANSI_BACKSLASH: u16 = 0x2A;
pub const VK_ANSI_COMMA: u16 = 0x2B;
pub const VK_ANSI_SLASH: u16 = 0x2C;
pub const VK_ANSI_N: u16 = 0x2D;
pub const VK_ANSI_M: u16 = 0x2E;
pub const VK_ANSI_PERIOD: u16 = 0x2F;
pub const VK_TAB: u16 = 0x30;
pub const VK_SPACE: u16 = 0x31;
pub const VK_ANSI_GRAVE: u16 = 0x32;
pub const VK_DELETE: u16 = 0x33;
pub const VK_ESCAPE: u16 = 0x35;
pub const VK_F5: u16 = 0x60;
pub const VK_F6: u16 = 0x61;
pub const VK_F7: u16 = 0x62;
pub const VK_F3: u16 = 0x63;
pub const VK_F8: u16 = 0x64;
pub const VK_F9: u16 = 0x65;
pub const VK_F11: u16 = 0x67;
pub const VK_F10: u16 = 0x6D;
pub const VK_F12: u16 = 0x6F;
pub const VK_HOME: u16 = 0x73;
pub const VK_PAGE_UP: u16 = 0x74;
pub const VK_FORWARD_DELETE: u16 = 0x75;
pub const VK_F4: u16 = 0x76;
pub const VK_END: u16 = 0x77;
pub const VK_F2: u16 = 0x78;
pub const VK_PAGE_DOWN: u16 = 0x79;
pub const VK_F1: u16 = 0x7A;
pub const VK_LEFT_ARROW: u16 = 0x7B;
pub const VK_RIGHT_ARROW: u16 = 0x7C;
pub const VK_DOWN_ARROW: u16 = 0x7D;
pub const VK_UP_ARROW: u16 = 0x7E;

// IOKit `NX_KEYTYPE_*` constants (`<IOKit/hidsystem/ev_keymap.h>`) for `NSSystemDefined` subtype 8.
pub const NX_KEYTYPE_SOUND_UP: u32 = 0;
pub const NX_KEYTYPE_SOUND_DOWN: u32 = 1;
pub const NX_KEYTYPE_BRIGHTNESS_UP: u32 = 2;
pub const NX_KEYTYPE_BRIGHTNESS_DOWN: u32 = 3;
pub const NX_KEYTYPE_MUTE: u32 = 7;
pub const NX_KEYTYPE_PLAY: u32 = 16;
pub const NX_KEYTYPE_NEXT: u32 = 17;
pub const NX_KEYTYPE_PREVIOUS: u32 = 18;

/// Resolved macOS key injection representation for a key-producing [`Action`].
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum MacosKeySpec {
    /// Standard `CGEventCreateKeyboardEvent` virtual keycode + modifier flags.
    VirtualKey {
        keycode: u16,
        ctrl: bool,
        alt: bool,
        shift: bool,
        meta: bool,
    },
    /// `NSSystemDefined` (`subtype = 8`) auxiliary control button (`NX_KEYTYPE_*`).
    SystemDefined { nx_key: u32 },
}

pub use crate::injector::CANONICAL_KEY_NAMES;

/// Maps a key identifier string from [`KeyChord::key`] to a macOS Carbon virtual keycode.
pub fn macos_keycode_for_key(key: &str) -> Option<u16> {
    match key.trim().to_ascii_lowercase().as_str() {
        "a" => Some(VK_ANSI_A),
        "b" => Some(VK_ANSI_B),
        "c" => Some(VK_ANSI_C),
        "d" => Some(VK_ANSI_D),
        "e" => Some(VK_ANSI_E),
        "f" => Some(VK_ANSI_F),
        "g" => Some(VK_ANSI_G),
        "h" => Some(VK_ANSI_H),
        "i" => Some(VK_ANSI_I),
        "j" => Some(VK_ANSI_J),
        "k" => Some(VK_ANSI_K),
        "l" => Some(VK_ANSI_L),
        "m" => Some(VK_ANSI_M),
        "n" => Some(VK_ANSI_N),
        "o" => Some(VK_ANSI_O),
        "p" => Some(VK_ANSI_P),
        "q" => Some(VK_ANSI_Q),
        "r" => Some(VK_ANSI_R),
        "s" => Some(VK_ANSI_S),
        "t" => Some(VK_ANSI_T),
        "u" => Some(VK_ANSI_U),
        "v" => Some(VK_ANSI_V),
        "w" => Some(VK_ANSI_W),
        "x" => Some(VK_ANSI_X),
        "y" => Some(VK_ANSI_Y),
        "z" => Some(VK_ANSI_Z),
        "0" => Some(VK_ANSI_0),
        "1" => Some(VK_ANSI_1),
        "2" => Some(VK_ANSI_2),
        "3" => Some(VK_ANSI_3),
        "4" => Some(VK_ANSI_4),
        "5" => Some(VK_ANSI_5),
        "6" => Some(VK_ANSI_6),
        "7" => Some(VK_ANSI_7),
        "8" => Some(VK_ANSI_8),
        "9" => Some(VK_ANSI_9),
        "return" | "enter" => Some(VK_RETURN),
        "space" | " " => Some(VK_SPACE),
        "tab" => Some(VK_TAB),
        "backspace" => Some(VK_DELETE),
        "delete" | "forwarddelete" => Some(VK_FORWARD_DELETE),
        "escape" | "esc" => Some(VK_ESCAPE),
        "up" | "arrowup" => Some(VK_UP_ARROW),
        "down" | "arrowdown" => Some(VK_DOWN_ARROW),
        "left" | "arrowleft" => Some(VK_LEFT_ARROW),
        "right" | "arrowright" => Some(VK_RIGHT_ARROW),
        "home" => Some(VK_HOME),
        "end" => Some(VK_END),
        "pageup" => Some(VK_PAGE_UP),
        "pagedown" => Some(VK_PAGE_DOWN),
        "f1" => Some(VK_F1),
        "f2" => Some(VK_F2),
        "f3" => Some(VK_F3),
        "f4" => Some(VK_F4),
        "f5" => Some(VK_F5),
        "f6" => Some(VK_F6),
        "f7" => Some(VK_F7),
        "f8" => Some(VK_F8),
        "f9" => Some(VK_F9),
        "f10" => Some(VK_F10),
        "f11" => Some(VK_F11),
        "f12" => Some(VK_F12),
        "-" | "minus" => Some(VK_ANSI_MINUS),
        "=" | "equal" | "equals" => Some(VK_ANSI_EQUAL),
        "[" | "leftbracket" => Some(VK_ANSI_LEFT_BRACKET),
        "]" | "rightbracket" => Some(VK_ANSI_RIGHT_BRACKET),
        "\\" | "backslash" => Some(VK_ANSI_BACKSLASH),
        ";" | "semicolon" => Some(VK_ANSI_SEMICOLON),
        "'" | "quote" => Some(VK_ANSI_QUOTE),
        "," | "comma" => Some(VK_ANSI_COMMA),
        "." | "period" => Some(VK_ANSI_PERIOD),
        "/" | "slash" => Some(VK_ANSI_SLASH),
        "`" | "grave" => Some(VK_ANSI_GRAVE),
        _ => None,
    }
}

/// Maps any key-based [`Action`] (`Key`, `Media`, `Volume`, `Brightness`, `System`, `Nav`, `DPad`)
/// to its macOS [`MacosKeySpec`].
pub fn macos_action_key_spec(action: &Action) -> Option<MacosKeySpec> {
    match action {
        Action::Key(chord) => {
            macos_keycode_for_key(&chord.key).map(|keycode| MacosKeySpec::VirtualKey {
                keycode,
                ctrl: chord.ctrl,
                alt: chord.alt,
                shift: chord.shift,
                meta: chord.meta,
            })
        }
        Action::Media(MediaAction::PlayPause) => Some(MacosKeySpec::SystemDefined {
            nx_key: NX_KEYTYPE_PLAY,
        }),
        Action::Media(MediaAction::Next) => Some(MacosKeySpec::SystemDefined {
            nx_key: NX_KEYTYPE_NEXT,
        }),
        Action::Media(MediaAction::Previous) => Some(MacosKeySpec::SystemDefined {
            nx_key: NX_KEYTYPE_PREVIOUS,
        }),
        Action::Volume(VolumeAction::Up) => Some(MacosKeySpec::SystemDefined {
            nx_key: NX_KEYTYPE_SOUND_UP,
        }),
        Action::Volume(VolumeAction::Down) => Some(MacosKeySpec::SystemDefined {
            nx_key: NX_KEYTYPE_SOUND_DOWN,
        }),
        Action::Volume(VolumeAction::Mute) => Some(MacosKeySpec::SystemDefined {
            nx_key: NX_KEYTYPE_MUTE,
        }),
        Action::Brightness(BrightnessAction::Up) => Some(MacosKeySpec::SystemDefined {
            nx_key: NX_KEYTYPE_BRIGHTNESS_UP,
        }),
        Action::Brightness(BrightnessAction::Down) => Some(MacosKeySpec::SystemDefined {
            nx_key: NX_KEYTYPE_BRIGHTNESS_DOWN,
        }),
        Action::System(SystemAction::Copy) => Some(MacosKeySpec::VirtualKey {
            keycode: VK_ANSI_C,
            ctrl: false,
            alt: false,
            shift: false,
            meta: true,
        }),
        Action::System(SystemAction::Paste) => Some(MacosKeySpec::VirtualKey {
            keycode: VK_ANSI_V,
            ctrl: false,
            alt: false,
            shift: false,
            meta: true,
        }),
        Action::System(SystemAction::Cut) => Some(MacosKeySpec::VirtualKey {
            keycode: VK_ANSI_X,
            ctrl: false,
            alt: false,
            shift: false,
            meta: true,
        }),
        Action::System(SystemAction::Undo) => Some(MacosKeySpec::VirtualKey {
            keycode: VK_ANSI_Z,
            ctrl: false,
            alt: false,
            shift: false,
            meta: true,
        }),
        Action::System(SystemAction::AppSwitcher) => Some(MacosKeySpec::VirtualKey {
            keycode: VK_TAB,
            ctrl: false,
            alt: false,
            shift: false,
            meta: true,
        }),
        Action::System(SystemAction::MissionControl) => Some(MacosKeySpec::VirtualKey {
            keycode: VK_UP_ARROW,
            ctrl: true,
            alt: false,
            shift: false,
            meta: false,
        }),
        Action::System(SystemAction::ShowDesktop) => Some(MacosKeySpec::VirtualKey {
            keycode: VK_F11,
            ctrl: false,
            alt: false,
            shift: false,
            meta: false,
        }),
        Action::Nav(NavAction::Back) => Some(MacosKeySpec::VirtualKey {
            keycode: VK_ANSI_LEFT_BRACKET,
            ctrl: false,
            alt: false,
            shift: false,
            meta: true,
        }),
        Action::Nav(NavAction::Home) | Action::Nav(NavAction::Recents) => {
            Some(MacosKeySpec::VirtualKey {
                keycode: VK_UP_ARROW,
                ctrl: true,
                alt: false,
                shift: false,
                meta: false,
            })
        }
        Action::Nav(NavAction::Notifications) | Action::Nav(NavAction::QuickSettings) => {
            Some(MacosKeySpec::VirtualKey {
                keycode: VK_F11,
                ctrl: false,
                alt: false,
                shift: false,
                meta: false,
            })
        }
        Action::DPad(Direction::Up) => Some(MacosKeySpec::VirtualKey {
            keycode: VK_UP_ARROW,
            ctrl: false,
            alt: false,
            shift: false,
            meta: false,
        }),
        Action::DPad(Direction::Down) => Some(MacosKeySpec::VirtualKey {
            keycode: VK_DOWN_ARROW,
            ctrl: false,
            alt: false,
            shift: false,
            meta: false,
        }),
        Action::DPad(Direction::Left) => Some(MacosKeySpec::VirtualKey {
            keycode: VK_LEFT_ARROW,
            ctrl: false,
            alt: false,
            shift: false,
            meta: false,
        }),
        Action::DPad(Direction::Right) => Some(MacosKeySpec::VirtualKey {
            keycode: VK_RIGHT_ARROW,
            ctrl: false,
            alt: false,
            shift: false,
            meta: false,
        }),
        Action::DPad(Direction::Center) => Some(MacosKeySpec::VirtualKey {
            keycode: VK_RETURN,
            ctrl: false,
            alt: false,
            shift: false,
            meta: false,
        }),
        _ => None,
    }
}

/// Axis-aligned display rectangle `(x, y, width, height)` in global screen coordinates.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct DisplayRect {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
}

impl DisplayRect {
    /// Creates a new [`DisplayRect`].
    pub const fn new(x: f64, y: f64, width: f64, height: f64) -> Self {
        Self {
            x,
            y,
            width,
            height,
        }
    }

    /// Returns the centre point `(cx, cy)` of this display in global screen coordinates.
    pub const fn center(&self) -> (f64, f64) {
        (self.x + self.width * 0.5, self.y + self.height * 0.5)
    }

    /// Maps an `Action::PointTo { x, y }` (in screen-width units relative to display centre)
    /// onto this display and clamps the resulting pixel coordinates to this display's bounds.
    pub fn map_point_to(&self, x: f32, y: f32) -> (f64, f64) {
        let (cx, cy) = self.center();
        let px = cx + (x as f64) * self.width;
        let py = cy + (y as f64) * self.width;
        clamp_to_bounds(
            px,
            py,
            self.x,
            self.y,
            self.x + self.width,
            self.y + self.height,
        )
    }
}

/// Finds the display in `rects` containing `(x, y)` (or the nearest display if `(x, y)` lies on
/// an outer boundary or dead gap), falling back to a default `1440×900` rect if `rects` is empty.
pub fn display_containing_point(x: f64, y: f64, rects: &[DisplayRect]) -> DisplayRect {
    let mut best: Option<(DisplayRect, f64)> = None;
    for &r in rects {
        if r.width <= 0.0 || r.height <= 0.0 {
            continue;
        }
        let (cx, cy) = clamp_to_bounds(x, y, r.x, r.y, r.x + r.width, r.y + r.height);
        let dx = cx - x;
        let dy = cy - y;
        let dist_sq = dx * dx + dy * dy;
        if dist_sq == 0.0 {
            return r;
        }
        match best {
            None => best = Some((r, dist_sq)),
            Some((_, best_dist_sq)) if dist_sq < best_dist_sq => {
                best = Some((r, dist_sq));
            }
            _ => {}
        }
    }
    best.map(|(r, _)| r)
        .unwrap_or_else(|| DisplayRect::new(0.0, 0.0, 1440.0, 900.0))
}

/// Stateful macOS display-capture and `PointTo` pixel mapper.
///
/// Captures the target display containing the cursor on the first `PointTo` after gyro mode is
/// entered or recentred; `reset_capture` clears the captured display on `ToggleGyro` or `Recenter`.
#[derive(Debug, Clone, Default)]
pub struct MacosPointToState {
    captured_display: Option<DisplayRect>,
}

impl MacosPointToState {
    /// Creates a new [`MacosPointToState`] with no captured display.
    pub const fn new() -> Self {
        Self {
            captured_display: None,
        }
    }

    /// Resets the captured target display (called on `ToggleGyro` or `Recenter`).
    pub fn reset_capture(&mut self) {
        self.captured_display = None;
    }

    /// Returns the currently captured target display, if any.
    pub const fn captured_display(&self) -> Option<DisplayRect> {
        self.captured_display
    }

    /// Maps `PointTo { x, y }` to clamped display pixel coordinates `(px, py)`, capturing the
    /// target display via `capture_fn` on the first `PointTo` after a recenter.
    pub fn resolve<F>(&mut self, x: f32, y: f32, capture_fn: F) -> Result<(f64, f64), InjectorError>
    where
        F: FnOnce() -> Result<DisplayRect, InjectorError>,
    {
        let display = match self.captured_display {
            Some(d) => d,
            None => {
                let d = capture_fn()?;
                self.captured_display = Some(d);
                d
            }
        };
        Ok(display.map_point_to(x, y))
    }
}

/// Clamps `(x, y)` into the bounding box `(min_x, min_y, max_x, max_y)`.
#[inline]
pub fn clamp_to_bounds(
    x: f64,
    y: f64,
    min_x: f64,
    min_y: f64,
    max_x: f64,
    max_y: f64,
) -> (f64, f64) {
    let hi_x = max_x.max(min_x);
    let hi_y = max_y.max(min_y);
    (x.clamp(min_x, hi_x), y.clamp(min_y, hi_y))
}

/// Clamps `(x, y)` to the nearest point inside the union of `rects`, preventing the cursor
/// from entering dead gaps in L-shaped or staggered multi-display arrangements.
pub fn clamp_to_display_rects(x: f64, y: f64, rects: &[DisplayRect]) -> (f64, f64) {
    let mut best: Option<((f64, f64), f64)> = None;
    for r in rects {
        if r.width <= 0.0 || r.height <= 0.0 {
            continue;
        }
        let (cx, cy) = clamp_to_bounds(x, y, r.x, r.y, r.x + r.width, r.y + r.height);
        let dx = cx - x;
        let dy = cy - y;
        let dist_sq = dx * dx + dy * dy;
        if dist_sq == 0.0 {
            return (x, y);
        }
        match best {
            None => best = Some(((cx, cy), dist_sq)),
            Some((_, best_dist_sq)) if dist_sq < best_dist_sq => {
                best = Some(((cx, cy), dist_sq));
            }
            _ => {}
        }
    }
    best.map(|(pt, _)| pt)
        .unwrap_or_else(|| clamp_to_bounds(x, y, 0.0, 0.0, 1440.0, 900.0))
}

#[cfg(target_os = "macos")]
#[link(name = "ApplicationServices", kind = "framework")]
unsafe extern "C" {
    fn AXIsProcessTrusted() -> bool;
}

/// Returns `true` when the process has been granted macOS Accessibility (`AXIsProcessTrusted`) permission.
pub fn is_accessibility_trusted() -> bool {
    #[cfg(target_os = "macos")]
    {
        unsafe { AXIsProcessTrusted() }
    }
    #[cfg(not(target_os = "macos"))]
    {
        true
    }
}

/// Opens the macOS System Settings -> Privacy & Security -> Accessibility pane.
pub fn open_accessibility_settings() -> Result<(), String> {
    Command::new("open")
        .arg(MACOS_ACCESSIBILITY_SETTINGS_URL)
        .spawn()
        .map(|_| ())
        .map_err(|e| format!("failed to open macOS Accessibility settings: {e}"))
}

#[cfg(target_os = "macos")]
mod imp {
    use super::*;
    use core_graphics::display::CGDisplay;
    use core_graphics::event::{
        CGEvent, CGEventFlags, CGEventTapLocation, CGEventType, CGMouseButton, CGScrollEventUnit,
        ScrollEventUnit,
    };
    use core_graphics::event_source::{CGEventSource, CGEventSourceStateID};
    use core_graphics::geometry::CGPoint;
    use objc2::rc::Retained;
    use objc2_app_kit::{NSEvent, NSEventModifierFlags, NSEventType};
    use objc2_foundation::NSPoint;

    #[link(name = "CoreGraphics", kind = "framework")]
    unsafe extern "C" {
        fn CGEventCreateScrollWheelEvent2(
            source: core_graphics::sys::CGEventSourceRef,
            units: CGScrollEventUnit,
            wheel_count: u32,
            wheel1: i32,
            wheel2: i32,
            wheel3: i32,
        ) -> core_graphics::sys::CGEventRef;

        fn CGEventPost(tap_location: CGEventTapLocation, event: core_graphics::sys::CGEventRef);
    }

    /// Queries all active macOS display bounds via `CGGetActiveDisplayList` + `CGDisplayBounds`.
    pub fn active_display_rects() -> Vec<DisplayRect> {
        let mut rects = Vec::new();
        if let Ok(ids) = CGDisplay::active_displays() {
            for id in ids {
                let b = CGDisplay::new(id).bounds();
                if b.size.width > 0.0
                    && b.size.height > 0.0
                    && b.origin.x.is_finite()
                    && b.origin.y.is_finite()
                {
                    rects.push(DisplayRect::new(
                        b.origin.x,
                        b.origin.y,
                        b.size.width,
                        b.size.height,
                    ));
                }
            }
        }
        if rects.is_empty() {
            let main = CGDisplay::main().bounds();
            if main.size.width > 0.0 && main.size.height > 0.0 {
                rects.push(DisplayRect::new(
                    main.origin.x,
                    main.origin.y,
                    main.size.width,
                    main.size.height,
                ));
            } else {
                rects.push(DisplayRect::new(0.0, 0.0, 1440.0, 900.0));
            }
        }
        rects
    }

    /// Computes the union `(min_x, min_y, max_x, max_y)` of all active macOS displays.
    pub fn union_display_bounds() -> (f64, f64, f64, f64) {
        let rects = active_display_rects();
        let mut min_x = f64::INFINITY;
        let mut min_y = f64::INFINITY;
        let mut max_x = f64::NEG_INFINITY;
        let mut max_y = f64::NEG_INFINITY;
        for b in &rects {
            min_x = min_x.min(b.x);
            min_y = min_y.min(b.y);
            max_x = max_x.max(b.x + b.width);
            max_y = max_y.max(b.y + b.height);
        }
        if min_x.is_finite() && max_x > min_x && max_y > min_y {
            (min_x, min_y, max_x, max_y)
        } else {
            (0.0, 0.0, 1440.0, 900.0)
        }
    }

    /// Reads the current global cursor position in CoreGraphics screen coordinates.
    pub fn current_cursor_location() -> Result<CGPoint, InjectorError> {
        let source = CGEventSource::new(CGEventSourceStateID::HIDSystemState)
            .map_err(|_| InjectorError("failed to create CGEventSource".to_string()))?;
        let ev = CGEvent::new(source)
            .map_err(|_| InjectorError("failed to query CGEvent cursor location".to_string()))?;
        Ok(ev.location())
    }

    /// macOS `CGEvent` + `NSSystemDefined` input injector.
    pub struct MacosInjector {
        left_button_down: bool,
        scroll_rem_x: f32,
        scroll_rem_y: f32,
        point_to: MacosPointToState,
    }

    impl Default for MacosInjector {
        fn default() -> Self {
            Self::new()
        }
    }

    impl MacosInjector {
        /// Creates a new [`MacosInjector`].
        pub const fn new() -> Self {
            Self {
                left_button_down: false,
                scroll_rem_x: 0.0,
                scroll_rem_y: 0.0,
                point_to: MacosPointToState::new(),
            }
        }

        fn make_source() -> Result<CGEventSource, InjectorError> {
            CGEventSource::new(CGEventSourceStateID::HIDSystemState)
                .map_err(|_| InjectorError("failed to create CGEventSource".to_string()))
        }

        fn post_mouse(
            &self,
            event_type: CGEventType,
            pos: CGPoint,
            button: CGMouseButton,
        ) -> Result<(), InjectorError> {
            let source = Self::make_source()?;
            let event =
                CGEvent::new_mouse_event(source, event_type, pos, button).map_err(|_| {
                    InjectorError(format!("failed to create mouse event {event_type:?}"))
                })?;
            event.post(CGEventTapLocation::HID);
            Ok(())
        }

        fn post_virtual_key(
            &self,
            keycode: u16,
            ctrl: bool,
            alt: bool,
            shift: bool,
            meta: bool,
        ) -> Result<(), InjectorError> {
            let mut flags = CGEventFlags::CGEventFlagNull;
            if ctrl {
                flags |= CGEventFlags::CGEventFlagControl;
            }
            if alt {
                flags |= CGEventFlags::CGEventFlagAlternate;
            }
            if shift {
                flags |= CGEventFlags::CGEventFlagShift;
            }
            if meta {
                flags |= CGEventFlags::CGEventFlagCommand;
            }

            let down_src = Self::make_source()?;
            let down = CGEvent::new_keyboard_event(down_src, keycode, true)
                .map_err(|_| InjectorError(format!("failed to create keydown for {keycode:#x}")))?;
            down.set_flags(flags);
            down.post(CGEventTapLocation::HID);

            let up_src = Self::make_source()?;
            let up = CGEvent::new_keyboard_event(up_src, keycode, false)
                .map_err(|_| InjectorError(format!("failed to create keyup for {keycode:#x}")))?;
            up.set_flags(flags);
            up.post(CGEventTapLocation::HID);
            Ok(())
        }

        /// Posts an `NSSystemDefined` (`subtype = 8`) media or brightness key event via `objc2-app-kit`.
        fn post_nx_system_key(&self, nx_key: u32) -> Result<(), InjectorError> {
            for (is_down, state_byte, mod_flags) in [
                (true, 0x0Aisize, 0x0A00usize),
                (false, 0x0Bisize, 0x0B00usize),
            ] {
                let data1 = ((nx_key as isize) << 16) | (state_byte << 8);
                let ns_event = NSEvent::otherEventWithType_location_modifierFlags_timestamp_windowNumber_context_subtype_data1_data2(
                    NSEventType::SystemDefined,
                    NSPoint::new(0.0, 0.0),
                    NSEventModifierFlags(mod_flags),
                    0.0,
                    0,
                    None,
                    8,
                    data1,
                    -1,
                )
                .ok_or_else(|| {
                    InjectorError(format!(
                        "failed to construct NSSystemDefined event for nx_key={nx_key} (down={is_down})"
                    ))
                })?;

                let cg_event = ns_event.CGEvent().ok_or_else(|| {
                    InjectorError(format!("NSEvent.CGEvent returned nil for nx_key={nx_key}"))
                })?;
                let raw_ptr = Retained::as_ptr(&cg_event) as core_graphics::sys::CGEventRef;
                unsafe {
                    CGEventPost(CGEventTapLocation::HID, raw_ptr);
                }
            }
            Ok(())
        }

        fn post_scroll(&mut self, dx: f32, dy: f32) -> Result<(), InjectorError> {
            let (px_dx, px_dy) =
                scale_scroll_pixels_accum(dx, dy, &mut self.scroll_rem_x, &mut self.scroll_rem_y);
            if px_dx == 0 && px_dy == 0 {
                return Ok(());
            }
            unsafe {
                let event_ref = CGEventCreateScrollWheelEvent2(
                    std::ptr::null_mut(),
                    ScrollEventUnit::PIXEL,
                    2,
                    px_dy,
                    px_dx,
                    0,
                );
                if event_ref.is_null() {
                    return Err(InjectorError(
                        "CGEventCreateScrollWheelEvent2 returned null".to_string(),
                    ));
                }
                CGEventPost(CGEventTapLocation::HID, event_ref);
                core_foundation::base::CFRelease(event_ref as *const _);
            }
            Ok(())
        }
    }

    impl Injector for MacosInjector {
        fn apply(&mut self, action: &Action) -> Result<(), InjectorError> {
            match action {
                Action::Move { dx, dy } => {
                    let cur = current_cursor_location()?;
                    let (px_dx, px_dy) = scale_move_delta(*dx, *dy);
                    let rects = active_display_rects();
                    let (nx, ny) =
                        clamp_to_display_rects(cur.x + px_dx as f64, cur.y + px_dy as f64, &rects);
                    let target = CGPoint::new(nx, ny);
                    let event_type = if self.left_button_down {
                        CGEventType::LeftMouseDragged
                    } else {
                        CGEventType::MouseMoved
                    };
                    self.post_mouse(event_type, target, CGMouseButton::Left)
                }
                Action::PointTo { x, y } => {
                    let (nx, ny) = self.point_to.resolve(*x, *y, || {
                        let cur = current_cursor_location()?;
                        let rects = active_display_rects();
                        Ok(display_containing_point(cur.x, cur.y, &rects))
                    })?;
                    let target = CGPoint::new(nx, ny);
                    let event_type = if self.left_button_down {
                        CGEventType::LeftMouseDragged
                    } else {
                        CGEventType::MouseMoved
                    };
                    self.post_mouse(event_type, target, CGMouseButton::Left)
                }
                Action::MouseDown => {
                    self.left_button_down = true;
                    let cur = current_cursor_location()?;
                    self.post_mouse(CGEventType::LeftMouseDown, cur, CGMouseButton::Left)
                }
                Action::MouseUp => {
                    self.left_button_down = false;
                    let cur = current_cursor_location()?;
                    self.post_mouse(CGEventType::LeftMouseUp, cur, CGMouseButton::Left)
                }
                Action::LeftClick => {
                    let cur = current_cursor_location()?;
                    self.post_mouse(CGEventType::LeftMouseDown, cur, CGMouseButton::Left)?;
                    self.post_mouse(CGEventType::LeftMouseUp, cur, CGMouseButton::Left)
                }
                Action::RightClick => {
                    let cur = current_cursor_location()?;
                    self.post_mouse(CGEventType::RightMouseDown, cur, CGMouseButton::Right)?;
                    self.post_mouse(CGEventType::RightMouseUp, cur, CGMouseButton::Right)
                }
                Action::Scroll { dx, dy } => self.post_scroll(*dx, *dy),
                Action::LaunchApp(app) => launch_app(app),
                Action::ToggleGyro | Action::Recenter => {
                    self.point_to.reset_capture();
                    Ok(())
                }
                Action::RadialMenu => Ok(()),
                Action::ScreenOff | Action::Assistant | Action::VoiceTyping => Ok(()),
                other => {
                    if let Some(spec) = macos_action_key_spec(other) {
                        match spec {
                            MacosKeySpec::VirtualKey {
                                keycode,
                                ctrl,
                                alt,
                                shift,
                                meta,
                            } => self.post_virtual_key(keycode, ctrl, alt, shift, meta),
                            MacosKeySpec::SystemDefined { nx_key } => {
                                self.post_nx_system_key(nx_key)
                            }
                        }
                    } else {
                        Err(InjectorError(format!(
                            "unmapped macOS key action: {other:?}"
                        )))
                    }
                }
            }
        }
    }
}

#[cfg(target_os = "macos")]
pub use imp::{MacosInjector, active_display_rects, current_cursor_location, union_display_bounds};

/// Helper constructing sample [`KeyChord`]s for testing macOS keycode completeness.
pub fn sample_key_chord(key: &str) -> KeyChord {
    KeyChord::new(key)
}
