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

use std::cell::RefCell;
use std::rc::Rc;

use vitruvian_tool_kit::{button, field, heading, text, toggle, tree, PanelAnswer, Tool, UiTree};

/// What the tool knows. One thread reads the link, so one value is enough,
/// shared between the handlers.
#[derive(Default)]
struct Counter {
    count: i64,
    name: String,
    by_two: bool,
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
    fn page(&self) -> UiTree {
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
        ]
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
    let counter = Rc::new(RefCell::new(Counter::default()));

    let opened = counter.clone();
    let acted = counter.clone();
    let island = tool.panel(
        "counter",
        move |_app, _panel| Ok(Some(opened.borrow().page())),
        move |app, panel, event| {
            let mut counter = acted.borrow_mut();
            match event.block.as_deref() {
                Some("add") => {
                    let step = counter.step();
                    counter.count += step;
                    panel.badge(app, Some(counter.count), false)?;
                }
                Some("name") => {
                    if let Some(name) = event.text() {
                        counter.name = name.to_string();
                    }
                }
                _ => return Ok(PanelAnswer::Keep),
            }
            Ok(PanelAnswer::Page(counter.page()))
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
        island.render(app, &counter.page());
        Ok(())
    });

    tool.run();
}
