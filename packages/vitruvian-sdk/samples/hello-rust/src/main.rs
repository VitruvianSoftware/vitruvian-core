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

//! A tool written with the Rust kit. It has two commands: `hello` asks the
//! app to show a short message, and `count` keeps a number in a preference
//! its manifest declares. `vitruvian-tool init --template rust` starts a
//! new tool from this file.

use vitruvian_tool_kit::Tool;

fn main() {
    let mut tool = Tool::new("0.1.0");

    tool.command("hello", |app| {
        app.notify().hud("Hello from a Rust tool", "hand.wave")
    });

    tool.command("count", |app| {
        let next = app.storage().get("count")?.as_f64().unwrap_or(0.0) + 1.0;
        app.storage().set("count", next)?;
        app.notify().hud(&format!("Counted to {next}"), "number")
    });

    tool.run();
}
