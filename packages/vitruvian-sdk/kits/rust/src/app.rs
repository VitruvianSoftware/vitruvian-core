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

use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};

use serde::de::DeserializeOwned;
use serde::Serialize;
use serde_json::Value;

use crate::error::ToolError;
use crate::generated::{
    methods, ClipboardReadTextResult, ClipboardWriteTextParams, ClipboardWriteTextResult,
    CommandsStateParams, Empty, KeyEquivalent, KeystrokesPasteParams,
    KeystrokesPressMenuItemParams, KeystrokesPressMenuItemResult, LogParams, NotifyHudParams,
    OpenUrlParams, OpenUrlResult, ProcessesTerminateParams, StorageGetParams, StorageGetResult,
    StorageSetParams, UiBadgeParams, UiStatusParams, UiText,
};
use crate::tool::State;

/// What an app may have beyond the first release of a protocol version, by
/// the name it gives at hello. Ask with [`App::supports`].
pub mod features {
    /// `ui/status`: the tool's status on the closed island.
    pub const STATUS: &str = "ui.status";
    /// The `choice` block.
    pub const CHOICE: &str = "ui.choice";
    /// `options` on a text preference, drawn as a pop-up menu.
    pub const PREFERENCE_OPTIONS: &str = "preferences.options";
    /// `activity` and `since` on `ui/status`: a few words, or a count of
    /// seconds, beside the mark. From 3.50.
    pub const STATUS_ACTIVITY: &str = "ui.status.activity";
    /// `open` in a panel's answer may name the tool's own settings panel:
    /// the app opens Settings on the tool's detail. From 3.58.
    pub const OPEN_SETTINGS: &str = "ui.open.settings";
    /// The `chips` block.
    pub const CHIPS: &str = "ui.chips";
    /// `section` on a heading, and `help` on a switch, a field, a choice and
    /// chips.
    pub const SECTIONS: &str = "ui.sections";
}

/// What [`Ui::status_with`] takes beside the state. Every field may be left
/// out: `StatusOptions { activity: Some("3".into()), ..Default::default() }`.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct StatusOptions {
    /// What it means, in one short line, for VoiceOver and the tooltip.
    pub text: Option<UiText>,
    /// An SF Symbol name, drawn in place of the state's own glyph.
    pub icon: Option<String>,
    /// A few words for the closed island, beside the mark. Sent only to an
    /// app that has [`features::STATUS_ACTIVITY`].
    pub activity: Option<UiText>,
    /// A start time the app counts the seconds from, when there are no
    /// words. Written as Unix seconds; a time before 1970 is written as 0.
    pub since: Option<SystemTime>,
}

/// What a status says, for [`Ui::status`]. The app draws each in its own
/// style.
pub mod status {
    /// No mark.
    pub const NONE: &str = "none";
    /// All is well.
    pub const OK: &str = "ok";
    /// Something is under way.
    pub const BUSY: &str = "busy";
    /// Something waits for the person.
    pub const ATTENTION: &str = "attention";
    /// Something failed.
    pub const FAILURE: &str = "failure";
}

/// The app, as a handler sees it. Each call is one request of the
/// protocol, grouped by the service the tool's manifest must list in
/// `uses` for it. Any call can be refused: it then returns
/// [`ToolError::App`] with the failure the app answered, and
/// [`crate::RefusalCode::of`] says which refusal it is. A handler that
/// returns it has its command answered as refused.
///
/// A tool may do any of this itself: it is a separate program with every
/// permission the app has. These are for what is better done through the
/// app.
pub struct App<'a> {
    state: &'a mut State,
}

impl<'a> App<'a> {
    pub(crate) fn new(state: &'a mut State) -> Self {
        App { state }
    }

    pub(crate) fn state_mut(&mut self) -> &mut State {
        self.state
    }

    /// The language the app is in, as a tag such as `en-US`. It follows
    /// the person's changes by itself.
    pub fn language(&self) -> &str {
        &self.state.language
    }

    /// The folder the tool may keep its own files in. It is also the
    /// folder the app starts the tool in.
    pub fn data_folder(&self) -> &Path {
        &self.state.data_folder
    }

    /// Whether this app has something a later release added to the
    /// protocol version: it named it at hello. [`features`] holds the
    /// names. False for an app that named nothing, as every app before 3.48
    /// does. Ask before using a `choice` block, and send a `field` to an
    /// app without it; before `chips`, and send a `toggle` for each option
    /// to an app without [`features::CHIPS`]; and before a heading's
    /// `section` or a control's `help`, which an app without
    /// [`features::SECTIONS`] does not draw.
    pub fn supports(&self, feature: &str) -> bool {
        self.state.features.contains(feature)
    }

    /// Sends any request of the protocol and reads its answer.
    pub fn send<R: DeserializeOwned>(
        &mut self,
        method: &str,
        params: &impl Serialize,
    ) -> Result<R, ToolError> {
        self.state.call(method, params)
    }

    /// Says which commands can run now. Until the first time, all of them
    /// can. It is a notice: the app does not answer it.
    pub fn set_runnable(&mut self, commands: &[&str]) {
        let runnable = commands.iter().map(|id| id.to_string()).collect();
        self.state
            .note(methods::COMMANDS_STATE, &CommandsStateParams { runnable });
    }

    /// Writes a line to the tool's log in Settings. It is a notice.
    pub fn log(&mut self, line: &str) {
        let message = line.to_string();
        self.state.note(methods::LOG, &LogParams { message });
    }

    /// The app's short on-screen message and its alert sound. Needs
    /// `notify` in the manifest's `uses`.
    pub fn notify(&mut self) -> Notify<'_> {
        Notify { state: self.state }
    }

    /// Opening links. Needs `open`.
    pub fn open(&mut self) -> Open<'_> {
        Open { state: self.state }
    }

    /// The tool's badge and its status in the island, for a tool of
    /// protocol 2. The badge needs `notify`; the status needs nothing in
    /// `uses`.
    pub fn ui(&mut self) -> Ui<'_> {
        Ui { state: self.state }
    }

    /// The clipboard's text. Needs `clipboard.read` to read and
    /// `clipboard.write` to write.
    pub fn clipboard(&mut self) -> Clipboard<'_> {
        Clipboard { state: self.state }
    }

    /// Typing into the app in front. Needs `keystrokes`.
    pub fn keystrokes(&mut self) -> Keystrokes<'_> {
        Keystrokes { state: self.state }
    }

    /// Ending processes, with the app's checks. Needs `processes`.
    pub fn processes(&mut self) -> Processes<'_> {
        Processes { state: self.state }
    }

    /// The preferences the manifest declares. Needs `storage`.
    pub fn storage(&mut self) -> Storage<'_> {
        Storage { state: self.state }
    }
}

/// See [`App::notify`].
pub struct Notify<'a> {
    state: &'a mut State,
}

impl Notify<'_> {
    /// Shows the app's short on-screen message. `icon` is an SF Symbol
    /// name.
    pub fn hud(self, message: &str, icon: &str) -> Result<(), ToolError> {
        let params = NotifyHudParams {
            icon: icon.to_string(),
            message: message.to_string(),
        };
        self.state.call::<Empty>(methods::NOTIFY_HUD, &params)?;
        Ok(())
    }

    /// Plays the alert sound.
    pub fn beep(self) -> Result<(), ToolError> {
        self.state.call::<Empty>(methods::NOTIFY_BEEP, &Empty {})?;
        Ok(())
    }
}

/// See [`App::ui`].
pub struct Ui<'a> {
    state: &'a mut State,
}

impl Ui<'_> {
    /// Puts a count, or a dot, beside the tool's page in the island's Explore gallery.
    /// With neither, the badge goes.
    pub fn badge(self, count: Option<i64>, dot: bool) -> Result<(), ToolError> {
        let params = UiBadgeParams {
            count,
            dot: if dot { Some(true) } else { None },
        };
        self.state.call::<Empty>(methods::UI_BADGE, &params)?;
        Ok(())
    }

    /// Sets the tool's status, a small mark the app draws on the closed
    /// island: `ui/status`. `state` is one of [`status`]'s. Each one
    /// replaces the last; [`status::NONE`] takes it away; and it goes when
    /// the tool's program ends, so a tool that wants it to last starts with
    /// the app (`"activation": ["onLaunch"]`). `text` says what it means,
    /// for VoiceOver. `icon`, an SF Symbol name, replaces the state's own
    /// glyph. The manifest must declare `contributes.status`: without it
    /// the app refuses, and the refusal is the error. It needs nothing in
    /// `uses`.
    ///
    /// `Ok(false)`, and nothing is sent, when the app did not say it has
    /// `ui.status`: an app before 3.48 shows no status, and that is no
    /// error. `Ok(true)` when the request was sent and answered; the person
    /// may still have switched the mark off.
    pub fn status(
        self,
        state: &str,
        text: Option<UiText>,
        icon: Option<&str>,
    ) -> Result<bool, ToolError> {
        self.status_with(
            state,
            StatusOptions {
                text,
                icon: icon.map(str::to_string),
                ..StatusOptions::default()
            },
        )
    }

    /// [`Ui::status`], with everything a status may carry. `activity`, a
    /// few words, and `since`, a start time the app counts the seconds from,
    /// are drawn beside the mark while it is the one the closed island
    /// shows; the words win over the start time. Six characters or fewer,
    /// and a number is best. They show only on an app that has
    /// [`features::STATUS_ACTIVITY`] (3.50 and later): to an app without it
    /// the status is sent without them. The manifest's status must say
    /// `"activity": true`, or the app leaves them out.
    ///
    /// `Ok(false)`, and nothing is sent, when the app did not say it has
    /// `ui.status`, as for [`Ui::status`].
    pub fn status_with(self, state: &str, options: StatusOptions) -> Result<bool, ToolError> {
        if !self.state.features.contains(features::STATUS) {
            return Ok(false);
        }
        // An app from before 3.50 is sent the status without its words.
        let words = self.state.features.contains(features::STATUS_ACTIVITY);
        let params = UiStatusParams {
            state: state.to_string(),
            text: options.text,
            icon: options.icon,
            activity: if words { options.activity } else { None },
            since: if words {
                options.since.map(|since| {
                    since
                        .duration_since(UNIX_EPOCH)
                        .map(|elapsed| elapsed.as_secs_f64())
                        .unwrap_or(0.0)
                })
            } else {
                None
            },
        };
        self.state.call::<Empty>(methods::UI_STATUS, &params)?;
        Ok(true)
    }
}

/// See [`App::open`].
pub struct Open<'a> {
    state: &'a mut State,
}

impl Open<'_> {
    /// Opens a link. False when nothing could open it.
    pub fn url(self, url: &str) -> Result<bool, ToolError> {
        let params = OpenUrlParams {
            url: url.to_string(),
        };
        let answer: OpenUrlResult = self.state.call(methods::OPEN_URL, &params)?;
        Ok(answer.opened)
    }
}

/// See [`App::clipboard`].
pub struct Clipboard<'a> {
    state: &'a mut State,
}

impl Clipboard<'_> {
    /// The clipboard's text; None when it holds none.
    pub fn read_text(self) -> Result<Option<String>, ToolError> {
        let answer: ClipboardReadTextResult =
            self.state.call(methods::CLIPBOARD_READ_TEXT, &Empty {})?;
        Ok(answer.text)
    }

    /// Replaces the clipboard with `text`. False when the clipboard would
    /// not take it.
    pub fn write_text(self, text: &str) -> Result<bool, ToolError> {
        let params = ClipboardWriteTextParams {
            text: text.to_string(),
        };
        let answer: ClipboardWriteTextResult =
            self.state.call(methods::CLIPBOARD_WRITE_TEXT, &params)?;
        Ok(answer.written)
    }
}

/// See [`App::keystrokes`].
pub struct Keystrokes<'a> {
    state: &'a mut State,
}

impl Keystrokes<'_> {
    /// Pastes `text` into the app in front.
    pub fn paste(self, text: &str) -> Result<(), ToolError> {
        let params = KeystrokesPasteParams {
            text: text.to_string(),
        };
        self.state
            .call::<Empty>(methods::KEYSTROKES_PASTE, &params)?;
        Ok(())
    }

    /// Presses the menu item with one of these key equivalents in the app
    /// in front. False when it has none.
    pub fn press_menu_item(self, equivalents: &[KeyEquivalent]) -> Result<bool, ToolError> {
        let params = KeystrokesPressMenuItemParams {
            equivalents: equivalents.to_vec(),
        };
        let answer: KeystrokesPressMenuItemResult = self
            .state
            .call(methods::KEYSTROKES_PRESS_MENU_ITEM, &params)?;
        Ok(answer.pressed)
    }
}

/// See [`App::processes`].
pub struct Processes<'a> {
    state: &'a mut State,
}

impl Processes<'_> {
    /// Ends a process: at once with `force`, else by asking it to quit.
    pub fn terminate(self, pid: i64, name: &str, force: bool) -> Result<(), ToolError> {
        let params = ProcessesTerminateParams {
            pid,
            name: name.to_string(),
            force,
        };
        self.state
            .call::<Empty>(methods::PROCESSES_TERMINATE, &params)?;
        Ok(())
    }
}

/// See [`App::storage`].
pub struct Storage<'a> {
    state: &'a mut State,
}

impl Storage<'_> {
    /// One preference's value: text, true or false, or a number.
    pub fn get(self, key: &str) -> Result<Value, ToolError> {
        let params = StorageGetParams {
            key: key.to_string(),
        };
        let answer: StorageGetResult = self.state.call(methods::STORAGE_GET, &params)?;
        Ok(answer.value)
    }

    /// Saves one preference: text, true or false, or a number.
    pub fn set(self, key: &str, value: impl Into<Value>) -> Result<(), ToolError> {
        let params = StorageSetParams {
            key: key.to_string(),
            value: value.into(),
        };
        self.state.call::<Empty>(methods::STORAGE_SET, &params)?;
        Ok(())
    }
}
