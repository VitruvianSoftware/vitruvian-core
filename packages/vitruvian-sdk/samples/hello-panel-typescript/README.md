# A tool that draws, in TypeScript

A counter the app draws in the island, from blocks the tool sends, with a
button and a field; a switch in Settings; and a command, `addOne`, that counts
too and sends the open page again. The same tool as `hello-panel-swift`,
written with the TypeScript kit in plain JavaScript that Node runs as it is.

```sh
cd samples/hello-panel-typescript && npm install
vitruvian-tool run samples/hello-panel-typescript --command addOne
```

A page is `tree` of its blocks, one function for each kind; a block that is
`false` is left out:

```javascript file=samples/hello-panel-typescript/bin/tool.mjs
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
```

`tool.panel` takes the two handlers by name: `onOpen` gives the first page,
`onEvent` answers what the person did with `{ page }`, `{ keep: true }`,
`{ open }` or `{ reply }`. The handle it returns sends a page unprompted,
with `render`, and sets the tool's badge in the island, with `badge`:

```javascript file=samples/hello-panel-typescript/bin/tool.mjs
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
```

```javascript file=samples/hello-panel-typescript/bin/tool.mjs
tool.command("addOne", () => {
  counter.count += step();
  island.render(page());
});
```

The manifest says `"protocol": "2"` and lists the two panels under
`contributes.panels`. Add the folder in Vitruvian, `node_modules/` and all:
Settings, Features, Tools from outside, Add a Tool.
