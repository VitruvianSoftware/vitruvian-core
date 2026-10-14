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

//! A tool that draws, written with the Rust kit. Its page in the island is
//! a counter with a button and a field; its page in Settings is one switch.
//! The app draws both, from the blocks this program sends. The command
//! `addOne` counts too, and sends the open page again.
//!
//! It also shows a status, the small mark the app draws on the closed
//! island, and its island page has a pop-up menu to pick it with. Both are
//! newer than protocol 2 itself, so the tool asks the app what it has. An
//! app that draws a status's words (3.50 and later) gets a second menu: the
//! count, or a count of seconds, beside the mark.

use std::cell::RefCell;
use std::rc::Rc;
use std::time::SystemTime;

use vitruvian_tool_kit::{
    button, choice, features, field, heading, status, text, toggle, tree, App, PanelAnswer,
    StatusOptions, Tool, ToolError, UiBlock, UiChoiceOption, UiTree,
};

/// What each status is called in the menu, and what it says to VoiceOver.
const STATUSES: [(&str, &str, Option<&str>); 5] = [
    (status::NONE, "None", None),
    (status::OK, "OK", Some("The counter is fine")),
    (status::BUSY, "Busy", Some("The counter is counting")),
    (
        status::ATTENTION,
        "Needs attention",
        Some("The counter wants a look"),
    ),
    (status::FAILURE, "Failed", Some("The counter failed")),
];

/// What may stand beside the mark, in the second menu.
const WORDS: [(&str, &str); 3] = [
    ("none", "None"),
    ("count", "The count"),
    ("seconds", "Seconds"),
];

/// What the tool knows. One thread reads the link, so one value is enough,
/// shared between the handlers.
struct Counter {
    count: i64,
    name: String,
    by_two: bool,
    /// What the tool shows on the closed island.
    status: String,
    /// What it says beside the mark: none, the count, or seconds.
    words: String,
    /// When "Seconds" was picked: the app counts from here.
    since: SystemTime,
}

impl Counter {
    fn step(&self) -> i64 {
        if self.by_two {
            2
        } else {
            1
        }
    }

    /// The island page: what it says now.
    fn page(&self, app: &App<'_>) -> UiTree {
        tree![
            heading("Counter"),
            text(format!("Pressed {} times", self.count)),
            button("add", format!("Add {}", self.step())).style("prominent"),
            field("name")
                .title("Your name")
                .value(&self.name)
                .placeholder("Type it and press Return"),
            (!self.name.is_empty())
                .then(|| text(format!("Hello, {}", self.name)).style("secondary")),
            self.status_picker(app),
            app.supports(features::STATUS_ACTIVITY)
                .then(|| self.words_picker()),
        ]
    }

    /// The words beside the mark, to pick. It starts at None, so the sample
    /// does not take the place of what the person reads there until they
    /// ask.
    fn words_picker(&self) -> UiBlock {
        let options = WORDS
            .iter()
            .map(|(value, title)| UiChoiceOption {
                value: value.to_string(),
                title: (*title).into(),
            })
            .collect();
        choice("words", &self.words, options)
            .title("Words on the closed island")
            .into()
    }

    /// The status, to pick: a pop-up menu where the app has one. An app
    /// before 3.48 draws a `choice` as plain words nobody can change, so
    /// there it is a field to type the word in.
    fn status_picker(&self, app: &App<'_>) -> UiBlock {
        if !app.supports(features::CHOICE) {
            return field("status")
                .title("Status: none, ok, busy, attention or failure")
                .value(&self.status)
                .into();
        }
        let options = STATUSES
            .iter()
            .map(|(state, title, _)| UiChoiceOption {
                value: state.to_string(),
                title: (*title).into(),
            })
            .collect();
        choice("status", &self.status, options)
            .title("Status on the closed island")
            .into()
    }

    /// Sets the mark on the closed island. Nothing is sent to an app that
    /// has no status, and the call says so.
    fn show_status(&self, app: &mut App<'_>) -> Result<bool, ToolError> {
        let says = STATUSES
            .iter()
            .find(|(state, _, _)| *state == self.status)
            .and_then(|(_, _, says)| *says);
        // An app before 3.50 is sent the status without the words.
        app.ui().status_with(
            &self.status,
            StatusOptions {
                text: says.map(Into::into),
                activity: (self.words == "count").then(|| self.count.to_string().into()),
                since: (self.words == "seconds").then_some(self.since),
                ..StatusOptions::default()
            },
        )
    }

    /// The Settings page.
    fn settings(&self) -> UiTree {
        tree![
            toggle("byTwo", "Count by two", self.by_two),
            text("The island's counter adds this much each time.").style("caption"),
        ]
    }
}

fn main() {
    let mut tool = Tool::new("0.1.0");
    let counter = Rc::new(RefCell::new(Counter {
        count: 0,
        name: String::new(),
        by_two: false,
        status: status::OK.to_string(),
        words: "none".to_string(),
        since: SystemTime::now(),
    }));

    let opened = counter.clone();
    let acted = counter.clone();
    let island = tool.panel(
        "counter",
        move |app, _panel| Ok(Some(opened.borrow().page(app))),
        move |app, panel, event| {
            let mut counter = acted.borrow_mut();
            match event.block.as_deref() {
                Some("add") => {
                    let step = counter.step();
                    counter.count += step;
                    panel.badge(app, Some(counter.count), false)?;
                    if counter.words == "count" {
                        counter.show_status(app)?;
                    }
                }
                Some("name") => {
                    if let Some(name) = event.text() {
                        counter.name = name.to_string();
                    }
                }
                Some("status") => {
                    // A pick is the event `change`, as leaving a field
                    // changed is.
                    let picked = event
                        .text()
                        .filter(|word| STATUSES.iter().any(|(state, _, _)| state == word));
                    let Some(picked) = picked else {
                        return Ok(PanelAnswer::Keep);
                    };
                    counter.status = picked.to_string();
                    counter.show_status(app)?;
                }
                Some("words") => {
                    let picked = event
                        .text()
                        .filter(|word| WORDS.iter().any(|(value, _)| value == word));
                    let Some(picked) = picked else {
                        return Ok(PanelAnswer::Keep);
                    };
                    counter.words = picked.to_string();
                    if picked == "seconds" {
                        counter.since = SystemTime::now();
                    }
                    counter.show_status(app)?;
                }
                _ => return Ok(PanelAnswer::Keep),
            }
            Ok(PanelAnswer::Page(counter.page(app)))
        },
    );

    let opened = counter.clone();
    let acted = counter.clone();
    tool.panel(
        "settings",
        move |_app, _panel| Ok(Some(opened.borrow().settings())),
        move |_app, _panel, event| {
            let (Some("byTwo"), Some(is_on)) = (event.block.as_deref(), event.is_on()) else {
                return Ok(PanelAnswer::Keep);
            };
            let mut counter = acted.borrow_mut();
            counter.by_two = is_on;
            Ok(PanelAnswer::Page(counter.settings()))
        },
    );

    let counted = counter.clone();
    tool.command("addOne", move |app| {
        let mut counter = counted.borrow_mut();
        let step = counter.step();
        counter.count += step;
        island.render(app, &counter.page(app));
        if counter.words == "count" {
            counter.show_status(app)?;
        }
        Ok(())
    });

    // The status goes when the program ends, so it is set each time the
    // program starts. The app may refuse any request: the tool carries on
    // without.
    let started = counter.clone();
    tool.on_start(move |app| {
        if let Err(error) = started.borrow().show_status(app) {
            app.log(&format!("no status: {error}"));
        }
    });

    tool.run();
}
