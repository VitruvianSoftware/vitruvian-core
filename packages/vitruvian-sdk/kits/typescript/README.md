# @vitruviansoftware/tool-kit

Write a tool for the [Vitruvian](https://vitruviansoftware.dev) Mac app in
TypeScript or JavaScript. A tool is a folder with a `vitruvian-tool.json` and
a program; the app starts the program and talks to it over its standard input
and output. This kit is that conversation: you say what each command does, and
call the app from inside a command as an ordinary function call.

```js
import { Tool } from "@vitruviansoftware/tool-kit";

const tool = new Tool({ version: "0.1.0" });

tool.command("hello", (app) => {
  app.notify.hud({ icon: "hand.wave", message: "Hello" });
});

tool.run();
```

- **One call per message.** `app.notify.hud(...)`, `app.clipboard.readText()`,
  `app.storage.get({ key })`: each is one request of the protocol, named as the
  protocol names it, typed from its schema. The app may refuse any of them;
  the call then throws a `Refusal`. Throw `new CommandRefused("why")` to
  refuse a command yourself.
- **Synchronous, on one thread.** A call to the app waits for its answer, ten
  seconds at most, and returns it as a value. A handler must not be `async`:
  the kit never gives Node's event loop a turn while it serves the app.
- **Never `console.log`.** Standard output is the link to the app. Write to
  standard error, or call `app.log({ message })`.

## Shipping it

No build step: write the tool as a `.mjs` file (add `// @ts-check` to have
the editor check it against the kit's types), run `npm install` in the tool's
folder, and add the folder to the app. `node_modules/` goes with it.

The app starts a tool with the short `PATH` macOS gives an app, which has no
`node` in it. Start the tool from a small shell script that looks where Node
is installed (`/opt/homebrew/bin`, `/usr/local/bin`), and name that script in
the manifest. `vitruvian-tool init --template typescript` writes a tool set up
this way. The kit needs Node 20 or later and has no dependencies.

The whole guide, the protocol and the other kits are in
[the SDK](https://github.com/VitruvianSoftware/vitruvian-sdk). MIT licence.
