// @ts-check
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

// A tool that draws, written with the TypeScript kit, in plain JavaScript
// that Node runs as it is. Its page in the island is a counter with a button
// and a field; its page in Settings is one switch. The app draws both, from
// the blocks this program sends. The command `addOne` counts too, and sends
// the open page again. bin/tool starts it: see the note there about Node and
// the PATH.

import {
  button,
  field,
  heading,
  text,
  toggle,
  Tool,
  tree,
} from "@vitruviansoftware/tool-kit";

const tool = new Tool({ version: "0.1.0" });

/** What the tool knows. One thread reads the link, so one object is enough. */
const counter = { count: 0, name: "", byTwo: false };
const step = () => (counter.byTwo ? 2 : 1);

/** The island page: what it says now. */
function page() {
  return tree([
    heading("Counter"),
    text(`Pressed ${counter.count} times`),
    button("add", `Add ${step()}`, { style: "prominent" }),
    field("name", {
      title: "Your name",
      value: counter.name,
      placeholder: "Type it and press Return",
    }),
    counter.name !== "" &&
      text(`Hello, ${counter.name}`, { style: "secondary" }),
  ]);
}

/** The Settings page. */
function settings() {
  return tree([
    toggle("byTwo", "Count by two", counter.byTwo),
    text("The island's counter adds this much each time.", {
      style: "caption",
    }),
  ]);
}

const island = tool.panel("counter", {
  onOpen: () => page(),
  onEvent: (_app, panel, event) => {
    switch (event.block) {
      case "add":
        counter.count += step();
        panel.badge({ count: counter.count });
        break;
      case "name":
        counter.name = event.text ?? counter.name;
        break;
      default:
        return { keep: true };
    }
    return { page: page() };
  },
});

tool.panel("settings", {
  onOpen: () => settings(),
  onEvent: (_app, _panel, event) => {
    if (event.block !== "byTwo" || event.isOn === undefined)
      return { keep: true };
    counter.byTwo = event.isOn;
    return { page: settings() };
  },
});

tool.command("addOne", () => {
  counter.count += step();
  island.render(page());
});

tool.run();
