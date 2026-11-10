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

//! Button binding definitions, actions, trigger modes, and platform defaults.

use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::fmt;
use std::str::FromStr;

/// Target operating environment determining default button bindings and gesture behavior.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Default, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Platform {
    /// macOS or Linux desktop.
    #[default]
    Desktop,
    /// Android phone or tablet.
    Android,
    /// Android TV (leanback / D-pad focus navigation).
    AndroidTv,
}

/// Bindable controller inputs (5 physical buttons plus touchpad tap).
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Button {
    /// Touchpad physical click button.
    Click,
    /// App (minus / menu) button.
    App,
    /// Home (circle / Daydream) button.
    Home,
    /// Volume up button.
    VolUp,
    /// Volume down button.
    VolDown,
    /// Capacitive touchpad tap gesture.
    Tap,
}

impl Button {
    /// All 5 physical hardware buttons in canonical order.
    pub const PHYSICAL: [Button; 5] = [
        Button::Click,
        Button::App,
        Button::Home,
        Button::VolUp,
        Button::VolDown,
    ];

    /// All 6 bindable inputs (5 physical buttons + touchpad tap).
    pub const ALL: [Button; 6] = [
        Button::Click,
        Button::App,
        Button::Home,
        Button::VolUp,
        Button::VolDown,
        Button::Tap,
    ];

    /// Stable lowercase identifier used in serialized binding keys.
    pub const fn as_str(self) -> &'static str {
        match self {
            Button::Click => "click",
            Button::App => "app",
            Button::Home => "home",
            Button::VolUp => "vol_up",
            Button::VolDown => "vol_down",
            Button::Tap => "tap",
        }
    }
}

impl fmt::Display for Button {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_str())
    }
}

impl FromStr for Button {
    type Err = String;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "click" => Ok(Button::Click),
            "app" => Ok(Button::App),
            "home" => Ok(Button::Home),
            "vol_up" => Ok(Button::VolUp),
            "vol_down" => Ok(Button::VolDown),
            "tap" => Ok(Button::Tap),
            other => Err(format!("unknown button '{other}'")),
        }
    }
}

/// Press classification per button.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Press {
    /// Single quick press and release.
    Short,
    /// Press held for at least the long-press threshold (default 500 ms).
    Long,
    /// Two short presses within the double-press gap (default 300 ms).
    Double,
}

impl Press {
    /// All 3 press types.
    pub const ALL: [Press; 3] = [Press::Short, Press::Long, Press::Double];

    /// Stable lowercase identifier used in serialized binding keys.
    pub const fn as_str(self) -> &'static str {
        match self {
            Press::Short => "short",
            Press::Long => "long",
            Press::Double => "double",
        }
    }
}

impl fmt::Display for Press {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_str())
    }
}

impl FromStr for Press {
    type Err = String;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "short" => Ok(Press::Short),
            "long" => Ok(Press::Long),
            "double" => Ok(Press::Double),
            other => Err(format!("unknown press type '{other}'")),
        }
    }
}

/// How a bound action is triggered when its button press activates.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Default, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TriggerMode {
    /// Fire the action once when the press gesture completes.
    #[default]
    Once,
    /// Emit the down/start action on press activation and the up/stop action on release.
    Hold,
    /// Alternate between the down/start action and the up/stop action on successive activations.
    Toggle,
}

/// Alias for [`TriggerMode`].
pub type Trigger = TriggerMode;

/// Media transport control actions.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MediaAction {
    PlayPause,
    Next,
    Previous,
}

/// System audio volume actions.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum VolumeAction {
    Up,
    Down,
    Mute,
}

/// Display brightness actions.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum BrightnessAction {
    Up,
    Down,
}

/// Desktop keyboard key or modifier chord.
#[derive(Debug, Clone, PartialEq, Eq, Hash, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct KeyChord {
    /// Primary key identifier (e.g., `"a"`, `"Return"`, `"Space"`, `"Escape"`).
    pub key: String,
    /// Control modifier held.
    pub ctrl: bool,
    /// Alt / Option modifier held.
    pub alt: bool,
    /// Shift modifier held.
    pub shift: bool,
    /// Meta / Command / Super modifier held.
    pub meta: bool,
}

impl KeyChord {
    /// Creates a plain unmodified key chord.
    pub fn new(key: impl Into<String>) -> Self {
        Self {
            key: key.into(),
            ctrl: false,
            alt: false,
            shift: false,
            meta: false,
        }
    }

    /// Creates a key chord with explicit modifiers.
    pub fn with_modifiers(
        key: impl Into<String>,
        ctrl: bool,
        alt: bool,
        shift: bool,
        meta: bool,
    ) -> Self {
        Self {
            key: key.into(),
            ctrl,
            alt,
            shift,
            meta,
        }
    }
}

/// Desktop system-level shortcut actions.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SystemAction {
    Copy,
    Paste,
    Cut,
    Undo,
    AppSwitcher,
    MissionControl,
    ShowDesktop,
}

/// Android global navigation actions (`AccessibilityService.performGlobalAction`).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum NavAction {
    Back,
    Home,
    Recents,
    Notifications,
    QuickSettings,
}

/// D-pad directional navigation for Android TV.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Direction {
    Up,
    Down,
    Left,
    Right,
    Center,
}

/// Output action emitted by [`crate::engine::Engine`] for the platform host to execute.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", content = "value", rename_all = "snake_case")]
pub enum Action {
    /// Complete left mouse click (or tap on Android).
    LeftClick,
    /// Complete right mouse click (or context click).
    RightClick,
    /// Press and hold primary mouse button (for dragging).
    MouseDown,
    /// Release primary mouse button (completing a drag).
    MouseUp,
    /// Relative 2D scroll delta.
    Scroll { dx: f32, dy: f32 },
    /// Media playback control.
    Media(MediaAction),
    /// System volume adjustment.
    Volume(VolumeAction),
    /// Display brightness adjustment.
    Brightness(BrightnessAction),
    /// Desktop keyboard key or chord.
    Key(KeyChord),
    /// Desktop system action (copy, paste, app switcher, etc.).
    System(SystemAction),
    /// Toggle between touchpad pointer mode and gyroscope air-mouse mode.
    ToggleGyro,
    /// Launch an application by bundle ID, desktop entry, or package name.
    LaunchApp(String),
    /// Open or trigger the 8-slot desktop radial menu.
    RadialMenu,
    /// Android global navigation action.
    Nav(NavAction),
    /// Android TV D-pad focus movement.
    DPad(Direction),
    /// Lock / turn off the screen on Android.
    ScreenOff,
    /// Invoke the voice assistant on Android.
    Assistant,
    /// Start voice dictation / typing.
    VoiceTyping,
    /// Move the pointer by `(dx, dy)` in device-independent units.
    Move { dx: f32, dy: f32 },
    /// Position the pointer at `(x, y)` in screen-width units relative to the screen centre.
    PointTo { x: f32, y: f32 },
    /// Recenter the gyroscope aim to the screen centre.
    Recenter,
}

/// Binding associating a button press slot with an [`Action`] and [`TriggerMode`].
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Binding {
    /// Action to perform.
    pub action: Action,
    /// Trigger behavior (`Once`, `Hold`, or `Toggle`).
    #[serde(default)]
    pub trigger: TriggerMode,
}

impl Binding {
    /// Creates a new [`Binding`].
    pub const fn new(action: Action, trigger: TriggerMode) -> Self {
        Self { action, trigger }
    }

    /// Creates a [`Binding`] with [`TriggerMode::Once`].
    pub const fn once(action: Action) -> Self {
        Self {
            action,
            trigger: TriggerMode::Once,
        }
    }

    /// Creates a [`Binding`] with [`TriggerMode::Hold`].
    pub const fn hold(action: Action) -> Self {
        Self {
            action,
            trigger: TriggerMode::Hold,
        }
    }

    /// Creates a [`Binding`] with [`TriggerMode::Toggle`].
    pub const fn toggle(action: Action) -> Self {
        Self {
            action,
            trigger: TriggerMode::Toggle,
        }
    }
}

/// Map from `(Button, Press)` slots to their configured [`Binding`].
pub type Bindings = BTreeMap<(Button, Press), Binding>;

/// Returns the specification's default button bindings for `platform`:
/// - `Click` short = `LeftClick` (`Hold`, emitting `MouseDown` on press and `MouseUp` on release)
/// - `Tap` short = `LeftClick` (`Once`)
/// - `Home` short = `RightClick` on `Desktop`; short `Nav(Back)` + long `Nav(Home)` on `Android` / `AndroidTv`
/// - `App` short = `ToggleGyro` (`Once`)
/// - `VolUp` short = `Scroll { dx: 0.0, dy: 1.0 }`, `VolDown` short = `Scroll { dx: 0.0, dy: -1.0 }`
pub fn default_bindings(platform: Platform) -> Bindings {
    let mut map = BTreeMap::new();
    map.insert(
        (Button::Click, Press::Short),
        Binding::hold(Action::LeftClick),
    );
    map.insert(
        (Button::Tap, Press::Short),
        Binding::once(Action::LeftClick),
    );
    map.insert(
        (Button::App, Press::Short),
        Binding::once(Action::ToggleGyro),
    );
    map.insert(
        (Button::VolUp, Press::Short),
        Binding::once(Action::Scroll { dx: 0.0, dy: 1.0 }),
    );
    map.insert(
        (Button::VolDown, Press::Short),
        Binding::once(Action::Scroll { dx: 0.0, dy: -1.0 }),
    );

    match platform {
        Platform::Desktop => {
            map.insert(
                (Button::Home, Press::Short),
                Binding::once(Action::RightClick),
            );
        }
        Platform::Android | Platform::AndroidTv => {
            map.insert(
                (Button::Home, Press::Short),
                Binding::once(Action::Nav(NavAction::Back)),
            );
            map.insert(
                (Button::Home, Press::Long),
                Binding::once(Action::Nav(NavAction::Home)),
            );
        }
    }

    map
}

/// Serde adapter that serializes [`Bindings`] (`BTreeMap<(Button, Press), Binding>`) using
/// `"<button>.<press>"` string keys so JSON and TOML map formats work cleanly.
pub mod serde_bindings {
    use super::{Binding, Bindings, Button, Press};
    use serde::de::{Error as DeError, MapAccess, Visitor};
    use serde::ser::SerializeMap;
    use serde::{Deserializer, Serializer};
    use std::collections::BTreeMap;
    use std::fmt;

    pub fn serialize<S>(bindings: &Bindings, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        let mut map = serializer.serialize_map(Some(bindings.len()))?;
        for ((button, press), binding) in bindings {
            let key = format!("{}.{}", button.as_str(), press.as_str());
            map.serialize_entry(&key, binding)?;
        }
        map.end()
    }

    pub fn deserialize<'de, D>(deserializer: D) -> Result<Bindings, D::Error>
    where
        D: Deserializer<'de>,
    {
        struct BindingsVisitor;

        impl<'de> Visitor<'de> for BindingsVisitor {
            type Value = Bindings;

            fn expecting(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
                formatter.write_str("a map of '<button>.<press>' keys to Binding values")
            }

            fn visit_map<M>(self, mut access: M) -> Result<Self::Value, M::Error>
            where
                M: MapAccess<'de>,
            {
                let mut map = BTreeMap::new();
                while let Some((key, binding)) = access.next_entry::<String, Binding>()? {
                    let (btn_str, press_str) = key
                        .split_once('.')
                        .or_else(|| key.split_once(':'))
                        .ok_or_else(|| {
                            M::Error::custom(format!(
                                "invalid binding key '{key}', expected '<button>.<press>'"
                            ))
                        })?;
                    let button = btn_str.parse::<Button>().map_err(M::Error::custom)?;
                    let press = press_str.parse::<Press>().map_err(M::Error::custom)?;
                    map.insert((button, press), binding);
                }
                Ok(map)
            }
        }

        deserializer.deserialize_map(BindingsVisitor)
    }
}
