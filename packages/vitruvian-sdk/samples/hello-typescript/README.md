# A tool in TypeScript

A tool with two commands, written with the TypeScript kit: `hello` shows a
short message, and `count` keeps a number in a preference and shows it. It is
plain JavaScript that Node runs as it is; `// @ts-check` has an editor check
it against the kit's types.

```sh
vitruvian-tool init ~/hello-ts --id com.you.hello-ts --name "Hello" --publisher "You" --template typescript
cd ~/hello-ts && npm install
vitruvian-tool run ~/hello-ts --command hello --command count
```

The program, `bin/tool.mjs`:

```javascript file=samples/hello-typescript/bin/tool.mjs
import { Tool } from "@vitruviansoftware/tool-kit";

const tool = new Tool({ version: "0.1.0" });

tool.command("hello", (app) => {
  app.notify.hud({ icon: "hand.wave", message: "Hello from TypeScript" });
});

tool.command("count", (app) => {
  const next = Number(app.storage.get({ key: "count" }).value) + 1;
  app.storage.set({ key: "count", value: next });
  app.notify.hud({ icon: "number", message: `Counted to ${next}` });
});

tool.run();
```

The manifest names `bin/tool`, which starts Node. The app starts a tool with
a short `PATH` that has no `node` in it, so `bin/tool` also looks where
Homebrew and the installer from nodejs.org put it:

```sh file=samples/hello-typescript/bin/tool
PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"
exec node "$(dirname "$0")/tool.mjs"
```

Add the folder in Vitruvian, `node_modules/` and all:
Settings › Extensions, "Add from Folder…".

## Drawing

[`../hello-panel-typescript`](../hello-panel-typescript) is a tool of
protocol 2, written with the same kit: a counter the app draws in the island
from blocks the tool sends. The guide's "Drawing" says how. Its page:

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
