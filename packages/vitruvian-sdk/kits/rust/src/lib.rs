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

//! Write a Vitruvian tool in Rust: declare commands, handle them, call the
//! app.
//!
//! ```no_run
//! use vitruvian_tool_kit::Tool;
//!
//! let mut tool = Tool::new("0.1.0");
//! tool.command("hello", |app| app.notify().hud("Hello", "hand.wave"));
//! tool.run();
//! ```
//!
//! A tool is a program the Vitruvian app starts and talks to in JSON, one
//! message per line, over the program's standard input and output. The kit
//! is that conversation: it answers the app's greeting, runs a command's
//! handler when the app asks, and turns each call on [`App`] into a request
//! and its answer.
//!
//! Handlers run one at a time, on the thread that called [`Tool::run`]. A
//! call to the app inside a handler waits there for its answer, so from the
//! handler's side every call is an ordinary function call. One more thread
//! reads standard input, because the standard library cannot wait on it
//! with a deadline; what the app sends while a handler waits is kept and
//! handled after the handler returns.
//!
//! Never print to standard output yourself: it is the link. Write to
//! standard error, or call [`App::log`].
//!
//! A tool of protocol 2 draws: [`Tool::panel`] says what a panel shows,
//! and a page is [`tree!`] of its blocks, one function a kind. [`Panel`]
//! here is that handle; the manifest's own panel type is
//! [`generated::Panel`].
//!
//! Two things are newer than protocol 2 itself, and an app says at hello
//! whether it has them ([`App::supports`], [`features`]): the tool's status
//! on the closed island ([`Ui::status`]), and a pop-up menu on a page
//! ([`choice`]). On an app from before them a status sends nothing, and a
//! choice is drawn as its fallback text.

pub mod generated;
pub use generated::*;

mod app;
mod error;
mod link;
mod panels;
mod tool;

pub use app::{features, status, App, Clipboard, Keystrokes, Notify, Open, Processes, Storage, Ui};
pub use error::{codes, RefusalCode, ToolError};
pub use panels::{
    button, choice, divider, field, heading, image, link, list, progress, row, spacer, text,
    toggle, Button, Choice, Field, Image, IntoBlocks, Panel, PanelAnswer, PanelEvent, Progress,
    Row, Text, Toggle,
};
pub use tool::Tool;
