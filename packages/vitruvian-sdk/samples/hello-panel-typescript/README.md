# A tool that draws, in TypeScript

A counter the app draws in the island, from blocks the tool sends, with a
button and a field; a switch in Settings; a command, `addOne`, that counts
too and sends the open page again; and a status, the small mark the app draws
on the closed island, with a pop-up menu to pick it. The same tool as `hello-panel-swift`,
written with the TypeScript kit in plain JavaScript that Node runs as it is.

```sh
cd samples/hello-panel-typescript && npm install
vitruvian-tool run samples/hello-panel-typescript --command addOne
```

A page is `tree` of its blocks, one function for each kind; a block that is
`false` is left out:

```javascript file=samples/hello-panel-typescript/bin/tool.mjs
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
```

`tool.panel` takes the two handlers by name: `onOpen` gives the first page,
`onEvent` answers what the person did with `{ page }`, `{ keep: true }`,
`{ open }` or `{ reply }`. The handle it returns sends a page unprompted,
with `render`, and sets the tool's badge in the island, with `badge`:

```javascript file=samples/hello-panel-typescript/bin/tool.mjs
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
```

```javascript file=samples/hello-panel-typescript/bin/tool.mjs
tool.command("addOne", (app) => {
  counter.count += step();
  island.render(page(app));
  if (counter.words === "count") showStatus(app);
});
```

## A status, and a choice

The tool's status is a small mark the app draws on the closed island. The
manifest declares it, `"status": { "placement": "island" }` under
`contributes`, and `app.status` sets it: `none`, `ok`, `busy`, `attention` or
`failure`, with a line for VoiceOver. It needs nothing in `uses`.

```javascript file=samples/hello-panel-typescript/bin/tool.mjs
function showStatus(app) {
  const says = STATUSES.find(({ state }) => state === counter.status)?.says;
  const options = says === undefined ? {} : { text: says };
  // An app before 3.50 is sent the status without the words.
  if (counter.words === "count") options.activity = String(counter.count);
  if (counter.words === "seconds") options.since = counter.since;
  return app.status(counter.status, options);
}
```

The mark goes when the tool's program ends, so the tool sets it each time it
starts, and its manifest says `"activation": ["onLaunch"]` so that it starts
with the app:

```javascript file=samples/hello-panel-typescript/bin/tool.mjs
tool.onStart = (app) => {
  try {
    showStatus(app);
  } catch (error) {
    app.log({ message: `no status: ${error}` });
  }
};
```

The island page has a pop-up menu to pick the status with: a `choice` block.
Picking is the event `change`, with the option's value, as leaving a field
changed is. Both the status and the `choice` block are newer than protocol 2
itself, and Vitruvian 3.46 and 3.47 have neither. There `app.status` sends
nothing and returns false. A `choice` would be drawn as plain words nobody
can change, so the tool asks first and sends a field in its place:

```javascript file=samples/hello-panel-typescript/bin/tool.mjs
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
```

## A few words beside the mark

On Vitruvian 3.50 and later the status may carry a few words, drawn beside
the mark on the closed island, or a start time the app counts the seconds
from. The manifest says so, `"status": { "placement": "island", "activity":
true }`, and `app.status` takes `activity` and `since`. When the app has
them, `app.supports(Feature.statusActivity)`, the island page gains a second
menu: None, the count, or seconds since it was picked. It starts at None, so
the sample does not take the place of what you read there until you ask. An
older app is sent the status without the words.

```javascript file=samples/hello-panel-typescript/bin/tool.mjs
function wordsPicker() {
  return choice("words", counter.words, WORDS, {
    title: "Words on the closed island",
  });
}
```

The manifest says `"protocol": "2"` and lists the two panels under
`contributes.panels`. Add the folder in Vitruvian, `node_modules/` and all:
Settings, Features, Tools from outside, Add a Tool.
