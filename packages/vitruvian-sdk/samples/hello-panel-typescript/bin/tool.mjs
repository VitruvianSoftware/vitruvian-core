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
//
// It also shows a status, the small mark the app draws on the closed island,
// and its island page has a pop-up menu to pick it with. Both are newer than
// protocol 2 itself, so the tool asks the app what it has. An app that draws
// a status's words (3.50 and later) gets a second menu: the count, or a count
// of seconds, beside the mark.

import {
  button,
  choice,
  Feature,
  field,
  heading,
  text,
  toggle,
  Tool,
  tree,
} from "@vitruviansoftware/tool-kit";

const tool = new Tool({ version: "0.1.0" });

/** What the tool knows. One thread reads the link, so one object is enough. */
const counter = {
  count: 0,
  name: "",
  byTwo: false,
  status: "ok",
  // What it says beside the mark: none, the count, or seconds; and when
  // "Seconds" was picked, which the app counts from.
  words: "none",
  since: new Date(),
};
const step = () => (counter.byTwo ? 2 : 1);

/** The island page: what it says now. */
function page(app) {
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
    statusPicker(app),
    app.supports(Feature.statusActivity) && wordsPicker(),
  ]);
}

/** What may stand beside the mark, in the second menu. */
const WORDS = [
  { value: "none", title: "None" },
  { value: "count", title: "The count" },
  { value: "seconds", title: "Seconds" },
];

/**
 * The words beside the mark, to pick. It starts at None, so the sample does
 * not take the place of what the person reads there until they ask.
 */
function wordsPicker() {
  return choice("words", counter.words, WORDS, {
    title: "Words on the closed island",
  });
}

/** What each status is called in the menu, and what it says to VoiceOver. */
const STATUSES = [
  { state: "none", title: "None" },
  { state: "ok", title: "OK", says: "The counter is fine" },
  { state: "busy", title: "Busy", says: "The counter is counting" },
  {
    state: "attention",
    title: "Needs attention",
    says: "The counter wants a look",
  },
  { state: "failure", title: "Failed", says: "The counter failed" },
];

/**
 * The status, to pick: a pop-up menu where the app has one. An app before
 * 3.48 draws a `choice` as plain words nobody can change, so there it is a
 * field to type the word in.
 */
function statusPicker(app) {
  if (!app.supports(Feature.choice)) {
    return field("status", {
      title: "Status: none, ok, busy, attention or failure",
      value: counter.status,
    });
  }
  const options = STATUSES.map(({ state, title }) => ({ value: state, title }));
  return choice("status", counter.status, options, {
    title: "Status on the closed island",
  });
}

/**
 * Sets the mark on the closed island. Nothing is sent to an app that has no
 * status, and the call says so.
 */
function showStatus(app) {
  const says = STATUSES.find(({ state }) => state === counter.status)?.says;
  const options = says === undefined ? {} : { text: says };
  // An app before 3.50 is sent the status without the words.
  if (counter.words === "count") options.activity = String(counter.count);
  if (counter.words === "seconds") options.since = counter.since;
  return app.status(counter.status, options);
}

/**
 * The Settings page. An app that has sections draws the switch's help under
 * it, and lists the heading to jump to; an older one is sent the same words
 * as a caption after the switch.
 */
function settings(app) {
  const help = "The island's counter adds this much each time.";
  if (!app.supports(Feature.sections))
    return tree([
      toggle("byTwo", "Count by two", counter.byTwo),
      text(help, { style: "caption" }),
    ]);
  return tree([
    heading("Counting", { section: true }),
    toggle("byTwo", "Count by two", counter.byTwo, { help }),
  ]);
}

const island = tool.panel("counter", {
  onOpen: (app) => page(app),
  onEvent: (app, panel, event) => {
    switch (event.block) {
      case "add":
        counter.count += step();
        panel.badge({ count: counter.count });
        if (counter.words === "count") showStatus(app);
        break;
      case "name":
        counter.name = event.text ?? counter.name;
        break;
      case "status":
        // A pick is the event `change`, as leaving a field changed is.
        if (!STATUSES.some(({ state }) => state === event.text))
          return { keep: true };
        counter.status = event.text;
        showStatus(app);
        break;
      case "words":
        if (!WORDS.some(({ value }) => value === event.text))
          return { keep: true };
        counter.words = event.text;
        if (event.text === "seconds") counter.since = new Date();
        showStatus(app);
        break;
      default:
        return { keep: true };
    }
    return { page: page(app) };
  },
});

tool.panel("settings", {
  onOpen: (app) => settings(app),
  onEvent: (app, _panel, event) => {
    if (event.block !== "byTwo" || event.isOn === undefined)
      return { keep: true };
    counter.byTwo = event.isOn;
    return { page: settings(app) };
  },
});

tool.command("addOne", (app) => {
  counter.count += step();
  island.render(page(app));
  if (counter.words === "count") showStatus(app);
});

// The status goes when the program ends, so it is set each time the program
// starts. The app may refuse any request: the tool carries on without.
tool.onStart = (app) => {
  try {
    showStatus(app);
  } catch (error) {
    app.log({ message: `no status: ${error}` });
  }
};

tool.run();
