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

use serde::de::DeserializeOwned;
use serde::Serialize;
use serde_json::Value;

use crate::error::ToolError;
use crate::generated::{
    methods, ClipboardReadTextResult, ClipboardWriteTextParams, ClipboardWriteTextResult,
    CommandsStateParams, Empty, KeyEquivalent, KeystrokesPasteParams,
    KeystrokesPressMenuItemParams, KeystrokesPressMenuItemResult, LogParams, NotifyHudParams,
    OpenUrlParams, OpenUrlResult, ProcessesTerminateParams, StorageGetParams, StorageGetResult,
    StorageSetParams,
};
use crate::tool::State;

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
